#!/usr/bin/env bash
# A stand-in for curl, installed first on PATH by tool/publish_guard_test.sh.
#
# Appends the URL (its last argument) to $PUBLISH_GUARD_FAKE_CURL_LOG, then
# serves $PUBLISH_GUARD_FAKE_PUB_DEV/<name>.json for
# https://pub.dev/api/packages/<name>. Exits 22 (curl -f's HTTP-error code)
# when no fixture exists, and 3 for any other URL. It never touches the
# network. The two variables are the fake's alone; the guard knows nothing of
# them.
set -euo pipefail

url="${!#}"
printf '%s\n' "$url" >>"$PUBLISH_GUARD_FAKE_CURL_LOG"

prefix='https://pub.dev/api/packages/'
case "$url" in
  "$prefix"*) ;;
  *) exit 3 ;;
esac

fixture="$PUBLISH_GUARD_FAKE_PUB_DEV/${url#"$prefix"}.json"
if [ ! -f "$fixture" ]; then
  exit 22
fi
cat "$fixture"
