#!/bin/sh -l

set -eu

if [ "$#" -eq 0 ] || [ -z "${1:-}" ]; then
  echo "input 'arguments' is required" >&2
  exit 1
fi

set +e
# Input arguments are passed as a single string from action.yml.
# shellcheck disable=SC2086
out="$(sh -lc "/app/mzap $*" 2>&1)"
status=$?
set -e

printf '%s\n' "$out"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "output<<__MZAP_OUTPUT__"
    printf '%s\n' "$out"
    echo "__MZAP_OUTPUT__"
  } >> "$GITHUB_OUTPUT"
fi

exit "$status"
