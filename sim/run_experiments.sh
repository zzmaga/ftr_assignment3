#!/usr/bin/env bash
# Три эксперимента отказов. Запуск: bash sim/run_experiments.sh   (из корня проекта)
set -euo pipefail
export PYTHONIOENCODING=utf-8
NS=aitu-sim
mkdir -p logs
now() { python3 -c 'import time;print(f"{time.time():.3f}")'; }
ready_count() { kubectl -n $NS get endpoints registration-service -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w; }
wait_ready_eq() { local end=$((SECONDS+120)); until [ "$(ready_count)" -eq "$1" ]; do [ "$SECONDS" -lt "$end" ] || { echo "timeout waiting for $1 endpoints" >&2; exit 1; }; sleep 0.2; done; }
wait_ready_lt() { local end=$((SECONDS+120)); until [ "$(ready_count)" -lt "$1" ]; do [ "$SECONDS" -lt "$end" ] || { echo "timeout waiting for fewer than $1 endpoints" >&2; exit 1; }; sleep 0.2; done; }

echo "== Подготовка =="
kubectl apply -f k8s/registration.yaml
kubectl -n $NS rollout status deploy/registration-service --timeout=120s
kubectl -n $NS rollout status deploy/db-mock --timeout=120s
kubectl apply -f k8s/loadgen.yaml
kubectl -n $NS wait --for=condition=Ready pod/loadgen --timeout=120s
sleep 15; echo "базовая линия готова, endpoints=$(ready_count)"

echo; echo "== Эксперимент 1: падение ОДНОЙ реплики Registration =="
POD=$(kubectl -n $NS get pod -l app=registration-service -o jsonpath='{.items[0].metadata.name}')
POD_IP=$(kubectl -n $NS get pod "$POD" -o jsonpath='{.status.podIP}')
T0=$(now); kubectl -n $NS delete pod "$POD" --wait=false
until ! kubectl -n $NS get endpoints registration-service -o jsonpath='{.subsets[*].addresses[*].ip}' | grep -q "$POD_IP"; do sleep 0.2; done; TD=$(now)
wait_ready_eq 2; TR=$(now); sleep 10; TE=$(now)
echo "T0=$T0"; echo "обнаружение (под убран из endpoints): $(python3 -c "print(round($TD-$T0,2))") с"
echo "восстановление (снова 2 Ready):       $(python3 -c "print(round($TR-$T0,2))") с"
kubectl -n $NS logs loadgen > logs/loadgen_exp1.txt
python3 sim/analyze.py logs/loadgen_exp1.txt "$T0" "$TE" | tee logs/exp1_result.txt

echo; echo "== Эксперимент 2: падение ВСЕХ реплик Registration =="
sleep 10
T0=$(now); kubectl -n $NS delete pod -l app=registration-service --grace-period=0 --force
wait_ready_lt 1; TD=$(now)
wait_ready_eq 2; TR=$(now); sleep 10; TE=$(now)
echo "T0=$T0"; echo "обнаружение (0 endpoints): $(python3 -c "print(round($TD-$T0,2))") с"
echo "восстановление (2 Ready):  $(python3 -c "print(round($TR-$T0,2))") с"
kubectl -n $NS logs loadgen > logs/loadgen_exp2.txt
python3 sim/analyze.py logs/loadgen_exp2.txt "$T0" "$TE" | tee logs/exp2_result.txt

echo; echo "== Эксперимент 3: БД недоступна 30 с =="
sleep 10
T0=$(now); kubectl -n $NS scale deploy/db-mock --replicas=0
sleep 30
T1=$(now); kubectl -n $NS scale deploy/db-mock --replicas=1
kubectl -n $NS rollout status deploy/db-mock --timeout=120s; sleep 10; TE=$(now)
echo "T0=$T0 (БД выключена), T1=$T1 (БД включена обратно)"
kubectl -n $NS logs loadgen > logs/loadgen_exp3.txt
python3 sim/analyze.py logs/loadgen_exp3.txt "$T0" "$TE" | tee logs/exp3_result.txt
echo "Перезапуски registration (restartCount; ожидаем 0):"
kubectl -n $NS get pod -l app=registration-service -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount | tee logs/exp3_restarts.txt
kubectl -n $NS get pods -o wide > logs/pods_final.txt
echo "Готово. Логи в папке logs/ — их приложить к отчёту."
