#!/usr/bin/env bash
# Checks, as plain text, that .github/workflows/publish.yml gates `publish` on
# a `guard` job running tool/publish_guard.sh at the tag, and that
# .github/workflows/ci.yml runs the guard's tests. Comment lines are dropped
# before any assertion, so a commented-out line never satisfies one, and each
# expected line is matched whole, after its indentation.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
publish_yml="$repo_root/.github/workflows/publish.yml"
ci_yml="$repo_root/.github/workflows/ci.yml"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

# job_block <job>: the job's lines in publish.yml, comment lines dropped. A job
# key is a line indented two spaces under `jobs:`.
job_block() {
  awk -v job="$1" '
    /^[^ \t#]/ { in_jobs = ($0 ~ /^jobs:[ \t]*$/); in_job = 0; next }
    !in_jobs { next }
    /^  [A-Za-z0-9_-]+:[ \t]*$/ {
      key = $0
      sub(/^  /, "", key)
      sub(/:[ \t]*$/, "", key)
      in_job = (key == job)
      next
    }
    in_job && !/^[ \t]*#/ { print }
  ' "$publish_yml"
}

# has_line <text> <line>: <text> has <line>, whole, after leading whitespace.
has_line() {
  printf '%s\n' "$1" | awk -v want="$2" '
    { line = $0; sub(/^[ \t]+/, "", line); if (line == want) found = 1 }
    END { exit found ? 0 : 1 }
  '
}

guard="$(job_block guard)"
[ -n "$guard" ] || fail 'publish.yml has a guard job'

has_line "$guard" 'needs: parse' ||
  fail 'the guard job needs parse'
has_line "$guard" '- uses: actions/checkout@v4' ||
  fail 'the guard job checks out the repository with actions/checkout@'
has_line "$guard" 'ref: ${{ github.ref }}' ||
  fail 'the guard job checks out the tag (ref: github.ref)'
has_line "$guard" 'TAG: ${{ github.ref_name }}' ||
  fail 'the guard job passes the tag through env TAG'
has_line "$guard" 'DIRECTORY: ${{ needs.parse.outputs.directory }}' ||
  fail 'the guard job passes the parsed directory through env DIRECTORY'
has_line "$guard" 'run: bash tool/publish_guard.sh "$TAG" "packages/$DIRECTORY"' ||
  fail 'the guard job runs tool/publish_guard.sh with the tag and packages/<parsed directory>'

publish="$(job_block publish)"
[ -n "$publish" ] || fail 'publish.yml has a publish job'
publish_needs="$(printf '%s\n' "$publish" | awk '
  { line = $0; sub(/^[ \t]+/, "", line) }
  line ~ /^needs:/ { print line }
')"
case "$publish_needs" in
  'needs: [parse, guard]' | 'needs: [guard, parse]') ;;
  *) fail "the publish job needs both parse and guard (found: ${publish_needs:-no needs line})" ;;
esac

ci_lines="$(awk '!/^[ \t]*#/' "$ci_yml")"
has_line "$ci_lines" '- name: Publish guard tests' ||
  fail 'ci.yml has a Publish guard tests step'
has_line "$ci_lines" 'run: bash tool/publish_guard_test.sh && bash tool/publish_workflow_test.sh' ||
  fail 'ci.yml runs bash tool/publish_guard_test.sh and bash tool/publish_workflow_test.sh'

publishing_doc="$repo_root/docs/publishing.md"
grep -Fq -- 'tool/publish_guard.sh' "$publishing_doc" ||
  fail 'docs/publishing.md names tool/publish_guard.sh'

# The register entry recording the guard's rulings: its file, slug and
# decision headings only.
slug='a-release-tag-publishes-only-after-the-publish-guard-passes'
entry="$repo_root/docs/decisions/2026-11-13-$slug.md"
[ -f "$entry" ] || fail "the register carries $slug"
grep -Fxq -- "  slug: $slug" "$entry" || fail "the register entry's slug is $slug"
for rule in D1 D2 D3 D4; do
  grep -q -- "^\*\*$rule\.\*\* " "$entry" ||
    fail "the register entry has decision $rule"
done

echo 'publish_workflow_test: passed'
