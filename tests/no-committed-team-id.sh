#!/bin/bash
# Law: no tracked file sets DEVELOPMENT_TEAM to a real Team ID. It is
# machine-specific and belongs in the gitignored Config.xcconfig.

cd "$(dirname "$0")/.."

hits=$(git grep -nE 'DEVELOPMENT_TEAM *= *"?[A-Z0-9]{10}"?' -- . ':!Config.xcconfig.example' || true)
if [ -n "$hits" ]; then
    echo "✗ no-committed-team-id: a tracked file sets DEVELOPMENT_TEAM:"
    echo "$hits" | sed 's/^/    /'
    echo "  Fix: delete that line and set DEVELOPMENT_TEAM in Config.xcconfig instead"
    echo "  (cp Config.xcconfig.example Config.xcconfig). In Xcode, leave the target's"
    echo "  Team unset in Signing & Capabilities so it isn't written back to the project."
    exit 1
fi
echo "✓ no-committed-team-id: no tracked file sets DEVELOPMENT_TEAM"
