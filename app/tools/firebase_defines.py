#!/usr/bin/env python3
"""Firebase project values for a build with real accounts (step 10b).

Reads the git-ignored google-services.json (downloaded from the Firebase
console) and writes the git-ignored firebase.defines.json next to
pubspec.yaml, for:

    flutter run --dart-define=BACKEND=firebase \\
        --dart-define-from-file=firebase.defines.json

The repo is public: neither file is ever committed (root .gitignore, checked
by test/backend/firebase_config_guard_test.dart). This tool never prints a
value from the file, only what it checked.

    python3 app/tools/firebase_defines.py [path/to/google-services.json]
        [--expect-project <id>]

The project id is not written here (or anywhere in git): the file must hold
exactly one project and one Android app with this app's applicationId;
--expect-project adds a check that it is that project.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "ishara_app"
SOURCE = APP / "android" / "app" / "google-services.json"
TARGET = APP / "firebase.defines.json"
GRADLE = APP / "android" / "app" / "build.gradle.kts"


def application_id() -> str:
    m = re.search(r'^\s*applicationId\s*=\s*"([^"]+)"', GRADLE.read_text(), re.M)
    if not m:
        raise SystemExit(f"error: no applicationId in {GRADLE}")
    return m.group(1)


def defines(services: dict, package: str, expect_project: str | None = None) -> dict[str, str]:
    """The dart-defines for [package], or SystemExit naming what's wrong.

    Messages never contain a value from the file."""
    info = services.get("project_info")
    if not isinstance(info, dict):
        raise SystemExit("error: google-services.json must hold exactly one project (project_info)")
    project_id = info.get("project_id")
    if not isinstance(project_id, str) or not project_id:
        raise SystemExit("error: google-services.json has no project_id")
    if expect_project is not None and project_id != expect_project:
        raise SystemExit("error: this google-services.json is not for the project given with --expect-project")
    clients = [
        c
        for c in services.get("client") or []
        if (c.get("client_info") or {}).get("android_client_info", {}).get("package_name") == package
    ]
    if len(clients) != 1:
        raise SystemExit(f"error: expected one Android app {package} in google-services.json, found {len(clients)}")
    client = clients[0]
    keys = [k.get("current_key") for k in client.get("api_key") or [] if k.get("current_key")]
    out = {
        "FIREBASE_API_KEY": keys[0] if keys else "",
        "FIREBASE_APP_ID": (client.get("client_info") or {}).get("mobilesdk_app_id", ""),
        "FIREBASE_SENDER_ID": str(info.get("project_number", "")),
        "FIREBASE_PROJECT_ID": project_id,
        "FIREBASE_STORAGE_BUCKET": info.get("storage_bucket", ""),
    }
    missing = [k for k, v in out.items() if not v and k != "FIREBASE_STORAGE_BUCKET"]
    if missing:
        raise SystemExit(f"error: google-services.json has no value for {', '.join(missing)}")
    if ":android:" not in out["FIREBASE_APP_ID"]:
        raise SystemExit("error: the app id in google-services.json is not an Android app id")
    return {k: v for k, v in out.items() if v}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Write firebase.defines.json from google-services.json.")
    parser.add_argument("source", nargs="?", type=Path, default=SOURCE, help="google-services.json")
    parser.add_argument("--expect-project", metavar="ID", help="refuse a file from any other project")
    args = parser.parse_args(argv[1:])
    source = args.source
    if not source.is_file():
        print(f"error: {source} not found (download it from the Firebase console)", file=sys.stderr)
        return 1
    try:
        services = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print(f"error: {source} is not valid JSON", file=sys.stderr)
        return 1
    package = application_id()
    try:
        values = defines(services, package, args.expect_project)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 1
    # owner-only: it holds the project's API key
    fd = os.open(TARGET, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(values, f, indent=2)
        f.write("\n")
    os.chmod(TARGET, 0o600)
    print(f"wrote {TARGET.relative_to(APP.parent.parent)}: one project{' (as expected)' if args.expect_project else ''}, app {package}, keys {', '.join(sorted(values))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
