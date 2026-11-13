#!/usr/bin/env bash
# publish_guard.sh <tag> [<package directory>]
#
# Refuses a release tag `<package>-v<version>` unless, at the checked-out
# commit:
#   version            - the package's pubspec `version` equals the tag's;
#   changelog          - the package's CHANGELOG.md has a heading for it;
#   sibling-dependency - pub.dev lists the version every sibling package named
#                        in the pubspec's `dependencies` declares here.
#
# Run from the repository root. The directory defaults to
# `packages/<package without its genesis_ prefix>`. Pubspecs and changelogs
# are read as plain text; the only network read is pub.dev's package listing,
# through curl.
#
# Exit 0: every check passed. Exit 1: a check refused (each refusal is one
# stderr line naming it). Exit 2: a usage error.
set -euo pipefail

usage() {
  echo "publish_guard: usage: $1" >&2
  echo 'publish_guard: usage: publish_guard.sh <package>-v<version> [<package directory>]' >&2
  exit 2
}

# Prints the value of the top-level `<key>:` line of a YAML file, with any
# trailing comment and one pair of surrounding quotes removed. Prints nothing
# when the file has no such line.
top_level_value() {
  awk -v key="$2" -v sq="'" '
    index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/[ \t]+#.*$/, "", v)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      first = substr(v, 1, 1)
      last = substr(v, length(v), 1)
      if (length(v) >= 2 && first == last && (first == "\"" || first == sq)) {
        v = substr(v, 2, length(v) - 2)
      }
      print v
      exit
    }
  ' "$1"
}

# Prints each key of the pubspec's top-level `dependencies:` block, one per
# line. Nested keys (a multi-line entry's `hosted:`/`version:`) are skipped.
dependency_keys() {
  awk '
    in_block && /^[^ \t#]/ { in_block = 0 }
    /^dependencies:[ \t]*(#.*)?$/ { in_block = 1; next }
    in_block && /^  [A-Za-z0-9_]+:/ {
      k = $0
      sub(/^  /, "", k)
      sub(/:.*$/, "", k)
      print k
    }
  ' "$1"
}

# Exits 0 when the changelog has a heading whose first word, with one
# surrounding bracket pair and one leading `v` removed, is exactly the version.
changelog_has_heading() {
  awk -v want="$2" '
    /^#+[ \t]/ {
      line = $0
      sub(/^#+[ \t]+/, "", line)
      split(line, words, /[ \t]+/)
      w = words[1]
      if (w ~ /^\[.*\]$/) w = substr(w, 2, length(w) - 2)
      sub(/^v/, "", w)
      if (w == want) { found = 1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "$1"
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage "expected 1 or 2 arguments, got $#"
fi

tag="$1"
tag_pattern='^[a-z0-9_]+-v[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.+-]+)?$'
if ! [[ "$tag" =~ $tag_pattern ]]; then
  usage "malformed tag '$tag': expected <package>-v<major>.<minor>.<patch>[<suffix>]"
fi
package="${tag%%-v*}"
version="${tag#*-v}"

if [ "$#" -eq 2 ]; then
  directory="${2%/}"
else
  directory="packages/${package#genesis_}"
fi

pubspec="$directory/pubspec.yaml"
changelog="$directory/CHANGELOG.md"

if [ ! -f "$pubspec" ]; then
  usage "no pubspec at $pubspec"
fi

declared_name="$(top_level_value "$pubspec" name)"
if [ "$declared_name" != "$package" ]; then
  usage "$pubspec names '$declared_name', but the tag is for '$package'"
fi

declared_version="$(top_level_value "$pubspec" version)"
if [ -z "$declared_version" ]; then
  usage "$pubspec has no top-level version line"
fi

refused=0
refuse() {
  echo "publish_guard: refused: $1: $2" >&2
  refused=1
}

# Check `version`.
if [ "$declared_version" != "$version" ]; then
  refuse version "tag says $version, $pubspec says $declared_version"
fi

# Check `changelog`.
if [ ! -f "$changelog" ]; then
  refuse changelog "no $changelog to hold a heading for $version"
elif ! changelog_has_heading "$changelog" "$version"; then
  refuse changelog "no heading for $version in $changelog"
fi

# Check `sibling-dependency`. Siblings are the packages/*/pubspec.yaml files,
# identified by their declared name; the map is "<name> <version>" lines.
siblings=''
for sibling_pubspec in packages/*/pubspec.yaml; do
  [ -f "$sibling_pubspec" ] || continue
  sibling_name="$(top_level_value "$sibling_pubspec" name)"
  [ -n "$sibling_name" ] || continue
  sibling_version="$(top_level_value "$sibling_pubspec" version)"
  siblings="$siblings$sibling_name ${sibling_version:-}
"
done

for dependency in $(dependency_keys "$pubspec"); do
  [ "$dependency" != "$package" ] || continue
  # No early `exit` in awk: it reads the whole map, so printf never meets a
  # closed pipe under pipefail.
  entry="$(printf '%s' "$siblings" | awk -v n="$dependency" '$1 == n && !seen { print; seen = 1 }')"
  [ -n "$entry" ] || continue
  sibling_version="${entry#* }"
  if [ -z "$sibling_version" ]; then
    refuse sibling-dependency "$dependency declares no version"
    continue
  fi
  if ! listing="$(curl -fsSL --retry 3 \
    -H 'Accept: application/vnd.pub.v2+json' \
    "https://pub.dev/api/packages/$dependency")"; then
    refuse sibling-dependency "$dependency $sibling_version: pub.dev read failed"
    continue
  fi
  # grep without -q reads all its input, so the pipe never closes early.
  if ! printf '%s' "$listing" | tr -d '[:space:]' |
    grep -F -- "\"version\":\"$sibling_version\"" >/dev/null; then
    refuse sibling-dependency "$dependency $sibling_version is not listed on pub.dev"
  fi
done

if [ "$refused" -ne 0 ]; then
  exit 1
fi

echo "publish_guard: $tag passed version, changelog and sibling-dependency checks"
