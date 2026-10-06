#!/bin/bash
# v3 pipeline on simulated data: data -> mine (2 rounds) -> train -> tune -> evaluate
set -e
PY=${PY:-python}
$PY simulate_data.py
$PY mine_negatives.py --round 1
$PY train_rf.py | tail -9
$PY train_cnn.py 2>&1 | grep -E "الدقة|KB|labels" || true
$PY mine_negatives.py --round 2
$PY train_rf.py | tail -9
$PY train_cnn.py 2>&1 | grep -E "الدقة|KB|labels" || true
$PY train_cnn.py --member 2 2>&1 | grep -E "KB" || true
$PY train_cnn.py --member 3 2>&1 | grep -E "KB" || true
$PY eval_live.py --tune --hours 30
$PY eval_live.py --sessions 20
$PY build_kit.py ../Ishara-Mobile-Kit
