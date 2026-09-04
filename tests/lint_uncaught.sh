#!/usr/bin/env bash
# The flip side of tests/check.sh: tests/uncaught/*.mojo are deliberate
# positives for mojolint (lint-mojo) — the origin and threading mistakes the
# compiler lets through, which is the whole point of the post. This asserts
# the linter actually catches all four: `mojolint --lsp -I src tests/uncaught`
# must exit non-zero, and its output must name every file in the directory.
#
# If a file stops being flagged, the linter has regressed on a case the post
# relies on. If mojolint starts exiting 0 here, something is badly wrong.
set -u
cd "$(dirname "$0")/.."
command -v mojolint >/dev/null || { echo "mojolint not on PATH — run as: pixi run lint-uncaught"; exit 2; }

out=$(mojolint --lsp -I src tests/uncaught 2>&1)
status=$?
fail=0

if [ "$status" -eq 0 ]; then
    echo "FAIL: mojolint exited 0 on tests/uncaught — expected findings"
    fail=1
fi

for f in tests/uncaught/*.mojo; do
    name=$(basename "$f")
    if grep -qF -- "$name" <<<"$out"; then
        echo "ok   flagged $name"
    else
        echo "FAIL: no finding reported for $name"
        fail=1
    fi
done

echo "$out"
[ "$fail" = 0 ]
