#!/bin/bash
# Law: the feature map matches its files and their checks.
#
# The map is what "done" is checked against, so it can't drift: every row in
# features/README.md has a file, every file has a row, and every file's
# "Driving it" names a `./build.sh drive <name>` whose drive/<name>.sh exists.
# A feature without one writes "No check yet" and why.
#
# Can't catch a check that exists but checks the wrong thing; breaking the
# feature once and watching its check fail covers that.

cd "$(dirname "$0")/.."
problems=()

rows=$(grep -oE '^\|[^|]+\| \[[^]]+\]\(([^)]+\.md)\)' features/README.md | sed -E 's/.*\(([^)]+)\)$/\1/')
files=$(cd features && ls *.md 2>/dev/null | grep -vx README.md)

for r in $rows; do
    [ -f "features/$r" ] || problems+=("features/README.md links $r, which doesn't exist. Fix the link or remove the row.")
done
for f in $files; do
    printf '%s\n' "$rows" | grep -qx "$f" || problems+=("features/$f has no row in features/README.md. Add a row to the table.")

    if ! grep -q '^## Driving it' "features/$f"; then
        problems+=("features/$f has no \"## Driving it\" section. Add one naming its check, or \"No check yet\" and why.")
        continue
    fi
    # The "## Driving it" section, up to the next heading.
    driving=$(awk '/^## Driving it/{on=1; next} /^## /{on=0} on' "features/$f")
    printf '%s' "$driving" | grep -q 'No check yet' && continue
    names=$(printf '%s' "$driving" | grep -oE '`\./build\.sh drive [a-z0-9-]+' | awk '{print $3}')
    if [ -z "$names" ]; then
        problems+=("features/$f names no \`./build.sh drive <name>\`. Name its check, or write \"No check yet\" and why.")
    fi
    for n in $names; do
        [ -f "drive/$n.sh" ] || problems+=("features/$f runs \`./build.sh drive $n\`, but there's no drive/$n.sh. Write that check or fix the name.")
    done
done

if [ ${#problems[@]} -gt 0 ]; then
    echo "✗ feature-map:"
    printf '    %s\n' "${problems[@]}"
    exit 1
fi
echo "✓ feature-map: every feature has a row, a file and a check or a stated reason"
