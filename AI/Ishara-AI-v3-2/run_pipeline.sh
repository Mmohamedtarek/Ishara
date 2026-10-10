#!/bin/bash
# v3 pipeline on simulated data: data -> train -> mine (2 rounds) -> train ensemble -> evaluate -> kit
# The first training comes BEFORE mining, so round 1 mines with a fresh model trained on this data
# (not with old model files left on disk from another vocabulary).
# The Decider settings come from decider.json (config B). To search new settings: python eval_live.py --tune
set -e
PY=${PY:-python}
# The kit: app/Ishara-Mobile-Kit in the repo (or set KIT=...)
KIT=${KIT:-$( [ -d ../../app/Ishara-Mobile-Kit ] && echo ../../app/Ishara-Mobile-Kit || echo ../Ishara-Mobile-Kit )}
$PY simulate_data.py
rm -f ishara_cnn*.tflite ishara_cnn*.keras ishara_rf.joblib   # old models (maybe with other labels) must not mix with the new ones
$PY train_rf.py | tail -9
$PY train_cnn.py 2>&1 | grep -E "الدقة|KB|labels" || true
$PY mine_negatives.py --round 1
$PY train_rf.py | tail -9
$PY train_cnn.py 2>&1 | grep -E "الدقة|KB|labels" || true
$PY mine_negatives.py --round 2
$PY train_rf.py | tail -9
$PY train_cnn.py 2>&1 | grep -E "الدقة|KB|labels" || true
$PY train_cnn.py --member 2 2>&1 | grep -E "KB" || true
$PY train_cnn.py --member 3 2>&1 | grep -E "KB" || true
$PY eval_live.py --hours 30
$PY eval_live.py --sessions 20 --no-stress --hours 1
$PY build_kit.py "$KIT"
