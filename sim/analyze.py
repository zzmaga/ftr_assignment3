#!/usr/bin/env python3
"""Анализ лога loadgen: python3 analyze.py logs/loadgen_full.txt T0 [T_END]
T0 / T_END — unix-время (сек) момента внесения/снятия отказа (печатает run_experiments.sh)."""
import sys

path, t0 = sys.argv[1], float(sys.argv[2])
t_end = float(sys.argv[3]) if len(sys.argv) > 3 else None
rows = []
for line in open(path):
    p = line.split()
    if len(p) == 2:
        try: rows.append((float(p[0]), int(p[1])))
        except ValueError: pass
w = [(t, c) for t, c in rows if t >= t0 - 5 and (t_end is None or t <= t_end + 30)]
after = [(t, c) for t, c in w if t >= t0]
errs = [(t, c) for t, c in after if c != 200]
print(f"запросов в окне: {len(w)}, ошибок после T0: {len(errs)}")
if not errs:
    print("Ошибок нет: пользователи отказа не заметили (error window = 0 с)")
    sys.exit()
first, last = errs[0][0], errs[-1][0]
codes = {}
for _, c in errs: codes[c] = codes.get(c, 0) + 1
print(f"коды ошибок: {codes}  (0 = нет соединения/таймаут)")
print(f"первая ошибка:   T0 + {first - t0:.1f} с")
print(f"последняя ошибка: T0 + {last - t0:.1f} с")
print(f"окно недоступности для пользователя ≈ {last - first + 0.1:.1f} с")
ok_after = [t for t, c in after if t > last and c == 200]
if ok_after:
    print(f"сервис полностью восстановлен: T0 + {ok_after[0] - t0:.1f} с")
