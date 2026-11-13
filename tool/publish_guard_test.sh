#!/usr/bin/env bash
# Exercises tool/publish_guard.sh against the fixture repository under
# tool/test_fixtures/publish_guard/repo, with a fake curl first on PATH that
# serves pub.dev reads from tool/test_fixtures/publish_guard/pub_dev and logs
# every URL. The proxy variables point at a closed local port, so a real curl
# that slipped through would fail rather than reach the network.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
guard="$repo_root/tool/publish_guard.sh"
fixtures="$repo_root/tool/test_fixtures/publish_guard"
fixture_repo="$fixtures/repo"

# An explicit template: macOS's `mktemp -d` alone ignores TMPDIR.
work="$(mktemp -d "${TMPDIR:-/tmp}/publish_guard_test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
cp "$fixtures/fake_curl.sh" "$work/bin/curl"
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"

export PUBLISH_GUARD_FAKE_CURL_LOG="$work/curl.log"
export PUBLISH_GUARD_FAKE_PUB_DEV="$fixtures/pub_dev"
export http_proxy='http://127.0.0.1:9'
export https_proxy='http://127.0.0.1:9'
export HTTPS_PROXY='http://127.0.0.1:9'
export ALL_PROXY='http://127.0.0.1:9'
unset no_proxy NO_PROXY

stdout="$work/stdout"
stderr="$work/stderr"
pub_dev='https://pub.dev/api/packages'
checks='version changelog sibling-dependency'
passed=0
case_name=''
status=0

fail() {
  echo "not ok - $case_name: $1" >&2
  echo '--- stdout' >&2
  cat "$stdout" >&2
  echo '--- stderr' >&2
  cat "$stderr" >&2
  echo '--- curl log' >&2
  cat "$PUBLISH_GUARD_FAKE_CURL_LOG" >&2
  exit 1
}

# run_guard <case> <arg>...: runs the guard from inside the fixture repository.
run_guard() {
  case_name="$1"
  shift
  : >"$PUBLISH_GUARD_FAKE_CURL_LOG"
  set +e
  (cd "$fixture_repo" && bash "$guard" "$@") >"$stdout" 2>"$stderr"
  status=$?
  set -e
}

expect_status() {
  [ "$status" -eq "$1" ] || fail "exit $status, expected $1"
}

# expect_curl_log <url>...: the fake was asked for exactly these URLs, in order.
expect_curl_log() {
  local expected=''
  if [ "$#" -gt 0 ]; then
    expected="$(printf '%s\n' "$@")"
  fi
  local actual
  actual="$(cat "$PUBLISH_GUARD_FAKE_CURL_LOG")"
  [ "$actual" = "$expected" ] ||
    fail "curl log was [$actual], expected [$expected]"
}

expect_stderr_line() {
  grep -Fxq -- "$1" "$stderr" || fail "stderr lacks the line: $1"
}

expect_stdout_line() {
  grep -Fxq -- "$1" "$stdout" || fail "stdout lacks the line: $1"
}

# expect_only_refused <check>...: no `refused:` line names any other check.
expect_only_refused() {
  local check allowed
  for check in $checks; do
    allowed=0
    for expected in "$@"; do
      [ "$check" != "$expected" ] || allowed=1
    done
    if [ "$allowed" -eq 0 ] &&
      grep -Fq -- "publish_guard: refused: $check:" "$stderr"; then
      fail "unexpected refusal of $check"
    fi
  done
}

expect_no_pass_line() {
  if grep -Fq -- 'passed version, changelog and sibling-dependency checks' "$stdout"; then
    fail 'printed the pass line'
  fi
}

ok() {
  echo "ok - $case_name"
  passed=$((passed + 1))
}

pass_line='publish_guard: genesis_alpha-v1.2.0 passed version, changelog and sibling-dependency checks'

run_guard pass-explicit-dir genesis_alpha-v1.2.0 packages/alpha
expect_status 0
expect_stdout_line "$pass_line"
expect_only_refused
[ ! -s "$stderr" ] || fail 'stderr is not empty'
expect_curl_log "$pub_dev/genesis_beta"
ok

run_guard pass-derived-dir genesis_alpha-v1.2.0
expect_status 0
expect_stdout_line "$pass_line"
expect_only_refused
[ ! -s "$stderr" ] || fail 'stderr is not empty'
expect_curl_log "$pub_dev/genesis_beta"
ok

run_guard version-mismatch genesis_stale-v1.2.0
expect_status 1
expect_stderr_line 'publish_guard: refused: version: tag says 1.2.0, packages/stale/pubspec.yaml says 1.1.0'
expect_only_refused version
expect_no_pass_line
expect_curl_log
ok

run_guard changelog-missing genesis_unlogged-v1.2.0
expect_status 1
expect_stderr_line 'publish_guard: refused: changelog: no heading for 1.2.0 in packages/unlogged/CHANGELOG.md'
expect_only_refused changelog
expect_no_pass_line
expect_curl_log
ok

run_guard sibling-unlisted genesis_waiting-v1.0.0
expect_status 1
expect_stderr_line 'publish_guard: refused: sibling-dependency: genesis_delta 0.4.0 is not listed on pub.dev'
expect_only_refused sibling-dependency
expect_no_pass_line
expect_curl_log "$pub_dev/genesis_delta"
ok

run_guard sibling-read-failed genesis_orphan-v1.0.0
expect_status 1
expect_stderr_line 'publish_guard: refused: sibling-dependency: genesis_ghost 0.1.0: pub.dev read failed'
expect_only_refused sibling-dependency
expect_no_pass_line
expect_curl_log "$pub_dev/genesis_ghost"
ok

run_guard malformed-tag genesis_alpha-1.2.0
expect_status 2
grep -Fq -- "publish_guard: usage: malformed tag 'genesis_alpha-1.2.0'" "$stderr" ||
  fail 'stderr does not name the malformed tag'
expect_only_refused
expect_no_pass_line
expect_curl_log
ok

run_guard name-mismatch genesis_alpha-v1.2.0 packages/beta
expect_status 2
grep -Fq -- "publish_guard: usage: packages/beta/pubspec.yaml names 'genesis_beta', but the tag is for 'genesis_alpha'" "$stderr" ||
  fail 'stderr does not name the pubspec name mismatch'
expect_only_refused
expect_no_pass_line
expect_curl_log
ok

echo "publish_guard_test: $passed passed"
