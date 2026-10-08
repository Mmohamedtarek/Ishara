"""Shared paths for the tools that read the stripped prototype (output of strip_prototype.py)."""
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
STRIPPED = REPO / "app" / "tools" / "out" / "prototype" / "prototype.stripped.html"


def prototype_src() -> pathlib.Path:
    """Path of the stripped prototype; exits with a clear message if it hasn't been made yet."""
    if not STRIPPED.exists():
        sys.exit("error: run app/tools/strip_prototype.py first")
    return STRIPPED
