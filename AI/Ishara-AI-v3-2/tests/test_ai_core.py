"""
Fast checks of the AI code against the Mobile Kit it produced.
Run from AI/Ishara-AI-v3-2:  python -m pytest tests -q
The kit is taken from ../../app/Ishara-Mobile-Kit (override with ISHARA_KIT=...).
"""
import hashlib
import json
import os
import py_compile
import sys

import numpy as np
import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
AI_DIR = os.path.dirname(HERE)
sys.path.insert(0, AI_DIR)
os.chdir(AI_DIR)                       # the code loads models and decider.json by relative path
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

KIT = os.environ.get("ISHARA_KIT", os.path.join(AI_DIR, "..", "..", "app", "Ishara-Mobile-Kit"))
if not os.path.isdir(KIT):
    KIT = os.path.join(AI_DIR, "..", "Ishara-Mobile-Kit")

import common  # noqa: E402
import live  # noqa: E402
import simulate_data as sim  # noqa: E402


def _tv():
    with open(os.path.join(KIT, "test", "test_vectors.json")) as f:
        return json.load(f)


def _sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def test_every_script_compiles():
    for name in sorted(os.listdir(AI_DIR)):
        if name.endswith(".py"):
            py_compile.compile(os.path.join(AI_DIR, name), doraise=True)


def test_labels_match_the_kit():
    with open(os.path.join(KIT, "model", "labels.txt")) as f:
        kit_labels = [l.strip() for l in f if l.strip()]
    assert kit_labels == common.LABELS
    with open(os.path.join(AI_DIR, "labels.txt")) as f:
        assert [l.strip() for l in f if l.strip()] == common.LABELS
    assert common.LABELS[-2:] == ["rest", "other"] and len(common.SIGN_LABELS) == 20


def test_kit_models_are_the_current_models():
    """The kit must have been built from the models in this folder."""
    with open(os.path.join(KIT, "model", "decider.json")) as f:
        models = json.load(f)["cnn"]["models"]
    for m in models:
        assert _sha(os.path.join(KIT, "model", m)) == _sha(os.path.join(AI_DIR, m)), m


def test_kit_decider_config_matches():
    with open(os.path.join(KIT, "model", "decider.json")) as f:
        kit = json.load(f)["cnn"]
    with open(os.path.join(AI_DIR, "decider.json")) as f:
        mine = json.load(f)["cnn"]
    for key in ("smooth", "active_s", "confirm_s", "idle", "tentative", "active",
                "pair_level", "confirm_on_rest", "rest_conf", "rest_run", "rest_null"):   # spec v3.3 fields too
        assert kit.get(key) == mine.get(key), key


@pytest.mark.parametrize("line", [
    '#CAL {"v":2,"open":[1,2,3,4,5],"fist":[9,8,7,6,5],"gyro_bias_raw":[10,-20,30],'
    '"roll_neutral":1.5,"roll_min":-40,"roll_max":42}',
    '#CAL {"v":2,"open":[1,2,3,4,5],"fist":[9,8,7,6,5],"gyroBias":[10,-20,30],'
    '"rollNeutral":1.5,"rollMin":-40,"rollMax":42}',
])
def test_parse_glove_cal_snake_and_camel_case(line):
    cal = common.parse_glove_cal(line)
    assert cal["open"] == [1, 2, 3, 4, 5] and cal["fist"] == [9, 8, 7, 6, 5]
    assert cal["gyro_bias"] == [10, -20, 30]
    assert cal["roll"] == {"neutral": 1.5, "min": -40, "max": 42}


def test_normalize_matches_the_kit_vectors():
    tv = _tv()
    cal = tv["calibration"]
    o, f, b = (np.asarray(cal[k], float) for k in ("open", "fist", "gyro_bias_raw"))
    for case in tv["normalize"]["cases"]:
        x = common.normalize(np.asarray(case["raw_window"], float), o, f, b)
        assert np.allclose(x[0], case["normalized_first_row"], atol=1e-4)
        assert abs(float(x.sum()) - case["normalized_sum"]) < 1e-2


def test_decider_matches_the_kit_vectors():
    dt = _tv()["decider"]
    d = live.Decider(common.LABELS, dt["config"])
    got = []
    for i, p in enumerate(dt["probs"]):
        got += [{"step": i, "event": e, "word": w} for e, w in d.step(np.asarray(p))]
    assert got == dt["expected"]


def test_gap_rule_matches_the_kit_vectors():
    g = _tv()["gaps"]
    sr = live.StreamRecognizer(live.Predictor("cnn"), g["config"], g["calibration"])
    got = []
    for i, line in enumerate(g["input"]):
        got += [{"input": i, "event": e, "word": w} for e, w in sr.feed(line[0], line[1:])]
    assert got == g["expected"]


@pytest.mark.parametrize("label", common.LABELS)
def test_simulator_makes_valid_takes(label):
    sim.rng = np.random.default_rng(1)
    take = sim.make_sample(label, sim.make_person())
    assert take.shape == (common.WINDOW, 11)
    assert take[:, :5].min() >= 0 and take[:, :5].max() <= 4095
    assert np.abs(take[:, 5:]).max() <= 32767


def _calib_file(person, step):
    path = os.path.join(KIT, "mock", person, "calibration", f"{step}.csv")
    with open(path) as f:
        lines = f.read().splitlines()
    cal = json.loads(lines[0][len("#CAL "):])
    raw = np.array([[float(v) for v in ln.split(",")[1:]] for ln in lines[1:]])
    return cal, raw


@pytest.mark.parametrize("person", ["A", "B"])
def test_calibration_mocks_follow_the_firmware_rules(person):
    """The mock glove plays these files during OPEN / FIST / TURN (firmware config.h rules)."""
    with open(os.path.join(KIT, "mock", person, "hello.csv")) as f:
        first_line = f.readline().strip()
    for step in ("open", "fist"):
        cal, raw = _calib_file(person, step)
        assert "#CAL " + json.dumps(cal, separators=(",", ":")) == first_line   # same person, same #CAL
        gyro_dps = (raw[:, 8:11] - np.asarray(cal["gyro_bias_raw"])) / 65.5
        assert gyro_dps.std(axis=0).max() < 3.0                                  # CAL_STILL_GYRO_STD_DPS
        assert np.allclose(raw[:, :5].mean(axis=0), cal[step], atol=20)          # fingers at the #CAL values
    cal, _ = _calib_file(person, "open")
    assert np.all(np.abs(np.asarray(cal["fist"]) - np.asarray(cal["open"])) >= 300)   # CAL_MIN_FLEX_RANGE
    _, raw = _calib_file(person, "turn")
    roll = np.degrees(np.arctan2(raw[:, 6], raw[:, 7]))                          # firmware: atan2(ay, az)
    assert roll.max() - roll.min() >= 30.0                                       # CAL_MIN_ROLL_RANGE_DEG
    assert cal["roll_min"] - 5 <= roll.min() and roll.max() <= cal["roll_max"] + 5
