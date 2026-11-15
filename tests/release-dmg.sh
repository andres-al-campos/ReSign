#!/usr/bin/env bash
# Law: a Mac app's release ships as a DMG, never a zip. Opening a DMG shows the
# app beside an Applications shortcut, so a download gets installed; a zip
# leaves the app in Downloads, where it gets run from instead.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  echo "✗ release-dmg: $1" >&2
  echo "  Fix: build the DMG in release.sh and attach it to gh release create:" >&2
  echo "    stage=\$(mktemp -d); ditto <App>.app \"\$stage/<App>.app\"; ln -s /Applications \"\$stage/Applications\"" >&2
  echo "    hdiutil create -quiet -volname <App> -srcfolder \"\$stage\" -format UDZO <App>-<version>.dmg" >&2
  exit 1
}

[ -f release.sh ] || fail "there is no release.sh to check."
grep -qE '\.zip|ditto -c' release.sh && fail "release.sh still makes or attaches a zip."
grep -q 'hdiutil create' release.sh || fail "release.sh never builds a DMG with hdiutil create."
grep -E 'gh release create' release.sh | grep -qi 'dmg' || fail "release.sh's gh release create doesn't attach the DMG."
echo "✓ release-dmg: release.sh ships the app as a DMG"
