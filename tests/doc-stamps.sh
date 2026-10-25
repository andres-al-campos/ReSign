#!/usr/bin/env bash
# Law: every doc, Principle and Call is stamped with a real time and a version ReSign.xcodeproj/project.pbxproj has had,
# and every "Applies *Name*." names a Principle in AGENTS.md. The pre-commit hook writes the
# stamps; this catches a commit made with the hook off. The check itself is the hook's
# --check, so it can't drift from what the hook writes.
command -v node >/dev/null || { echo "doc-stamps: Node isn't installed, so the stamps can't be checked. Install it (brew install node), then run the check again."; exit 1; }
exec node "$(dirname "$0")/../dev/hooks/stamp-docs.mjs" --check ReSign.xcodeproj/project.pbxproj
