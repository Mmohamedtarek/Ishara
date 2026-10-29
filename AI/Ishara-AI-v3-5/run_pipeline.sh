#!/bin/bash
# v3 pipeline على الداتا الوهمية: data -> train -> mine (2 rounds) -> train ensemble -> evaluate -> kit
# الخطوات نفسها مكتوبة مرة واحدة في run_pipeline.py (نفس الملف لـ Linux و Windows)، والسكريبت ده بيشغّله بس.
# بيقف عند أول خطوة تفشل. Python تاني: PY=python3 ./run_pipeline.sh   مكان تاني للـ Kit: ./run_pipeline.sh --kit <فولدر>
set -e
cd "$(dirname "$0")"
PY=${PY:-python}
exec "$PY" run_pipeline.py "$@"
