#!/usr/bin/env bash
set -euo pipefail

publishing_doc='docs/publishing.md'
pattern='ADR-?[0-9]|\b(the[[:space:]]+register|decision(-|[[:space:]]+)register)\b|\bA[0-9]{1,2}\b|spike'

if ! grep -Fq "grep -rniE \"${pattern}\" \\" "${publishing_doc}"; then
  echo 'publishing scrub expression differs from the required narrow pattern' >&2
  exit 1
fi

if ! grep -Fq 'README.md CHANGELOG.md lib example 2>/dev/null | grep -viE "A2UI"' "${publishing_doc}"; then
  echo 'publishing scrub file set or A2UI exclusion changed' >&2
  exit 1
fi

if printf '%s\n' 'registerServiceExtension' | grep -qE "${pattern}"; then
  echo 'registerServiceExtension must pass the publishing scrub' >&2
  exit 1
fi

if ! printf '%s\n' '// internal decision register reference' | grep -qE "${pattern}"; then
  echo 'decision register must fail the publishing scrub' >&2
  exit 1
fi
