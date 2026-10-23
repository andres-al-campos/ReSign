#!/usr/bin/env bash
# Law: each feature file, the README and any guide in docs/ carries a stamp,
# "Updated YYYY-MM-DD HH:MM, at <version>.", and each Principle and Call starts
# "YYYY-MM-DD HH:MM, <version>.", with a time that isn't in the future and a
# version project.pbxproj has had. A Call's "Applies *Name*." names a Principle in
# AGENTS.md. The pre-commit hook (hooks/stamp-docs.mjs) writes the stamps; this
# catches a commit made with the hook off.
cd "$(dirname "$0")/.." || exit 1
problems=()

current=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION = ([^;]+);.*/\1/p' ReSign.xcodeproj/project.pbxproj | head -1)
# Every version project.pbxproj has had, so a typo'd version doesn't pass for a real one.
known=" $current $(git log -p --format= -- ReSign.xcodeproj/project.pbxproj 2>/dev/null \
  | sed -nE 's/^[-+ ][[:space:]]*MARKETING_VERSION = ([^;]+);.*/\1/p' | sort -u | tr '\n' ' ')"
now=$(date '+%Y-%m-%d %H:%M')

# Prints what's wrong with a time and version, or nothing.
problem_with() {
  # A real time reads back the same; date -j rolls 25:00 over to the next day.
  if [ "$(date -j -f '%Y-%m-%d %H:%M' "$1" '+%Y-%m-%d %H:%M' 2>/dev/null)" != "$1" ]; then
    echo "\"$1\" isn't a time like $now"
  elif [[ "$1" > "$now" ]]; then
    echo "$1 is in the future"
  else
    case "$known" in *" $2 "*) ;; *) echo "$2 is a version project.pbxproj has never had (now $current)" ;; esac
  fi
}

features=$(ls features/*.md 2>/dev/null || true)
docs="$features"
[ -f README.md ] && docs="$docs README.md"
docs="$docs $(ls docs/*.md 2>/dev/null || true)"

for doc in $docs; do
  stamp=$(grep -m1 -E '^Updated .+, at [^ ]+\.$' "$doc" || true)
  if [ -z "$stamp" ]; then
    problems+=("$doc has no stamp. Turn the hook on (./build.sh does it) and it adds one the next time the file is committed, or add under its title: \"Updated $now, at $current.\"")
    continue
  fi
  time=$(printf '%s' "$stamp" | sed -E 's/^Updated (.+), at [^ ]+\.$/\1/')
  version=$(printf '%s' "$stamp" | sed -E 's/^Updated .+, at ([^ ]+)\.$/\1/')
  p=$(problem_with "$time" "$version")
  [ -n "$p" ] && problems+=("$doc's stamp: $p. Set it to when the description last changed, like \"Updated $now, at $current.\"")
done

# Principle names, from "**Name.**" after each Principle's time.
principles=$(awk '/^#+ /{s = /^## Principles/; next} s' AGENTS.md | sed -nE 's/^- [^*]*\*\*([^*]+)\.\*\*.*/\1/p')
named=$(printf '%s' "$principles" | paste -sd ';' - | sed 's/;/; /g')

for file in AGENTS.md $features; do
  # Each line inside a Principles or Calls section, as "n:line".
  while IFS=: read -r n line; do
    rest=$line
    while [[ "$rest" =~ Applies\ \*([^*]+)\*\.(.*) ]]; do
      name=${BASH_REMATCH[1]}; rest=${BASH_REMATCH[2]}
      grep -qxF "$name" <<<"$principles" ||
        problems+=("$file:$n: cites \"$name\", which isn't a Principle in AGENTS.md (${named:-none named yet}). Cite one of those, or none.")
    done
    [[ "$line" == "- "* ]] || continue
    if [[ "$line" =~ ^-\ ([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}),\ ([^ ]+)\.\  ]]; then
      p=$(problem_with "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
    else
      p="starts \"${line:2:20}…\" without a time and version"
    fi
    [ -n "$p" ] && problems+=("$file:$n: $p. Commit it with the hook on and it adds one, or start it with \"- $now, $current. \".")
  done < <(awk '/^#+ /{s = /^## (Principles|Calls)([^A-Za-z]|$)/; next} s {print NR ":" $0}' "$file")
done

[ ${#problems[@]} -eq 0 ] && exit 0
printf '%s\n' "${problems[@]}"
exit 1
