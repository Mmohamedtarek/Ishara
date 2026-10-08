# Decisions

| Date | Decision | Reason |
|---|---|---|
| 2026-10-08 | Read the prototype through `app/tools/strip_prototype.py` (outputs in the git-ignored `app/tools/out/`) | The 12 MB file is mostly base64 GLBs. The script can be re-run and never touches `design/`. |
| 2026-10-08 | Treat `docs/BLE-CONTRACT.md` as the BLE source; the kit copy is identical today | User prompt names `docs/`. |
| 2026-10-08 | Proposed (pending approval): `webview_flutter` + a loopback HTTP server for the avatar, not `flutter_inappwebview` | First-party and maintained; ES modules don't load from `file://`. |
| 2026-10-08 | Proposed (pending approval): implement AI-SPEC "rounded" as Python's round-half-to-even | Matches `live.py`, which the spec says the app must behave exactly like. |
