#!/usr/bin/env bash
# Deliberate misuse, sorted by what the compiler does with it.
#
#   tests/caught/*.mojo    must FAIL to build, and the error text must contain
#                          the file's `# expect-error:` line.
#   tests/uncaught/*.mojo  must build with no diagnostics at all, run, and
#                          print the file's `# expect:` lines in that order —
#                          the wrong answer, reproduced on purpose.
#
# Both directions are a claim about the compiler. If a caught case starts
# compiling, a guarantee the README states has gone. If an uncaught case
# stops compiling, the compiler has learned to see something it could not —
# move the file to caught/, record the diagnostic, and shorten the list of
# things a reviewer has to check by hand.
set -u
cd "$(dirname "$0")/.."
command -v mojo >/dev/null || { echo "mojo not on PATH — run as: pixi run check"; exit 2; }
mkdir -p build/tests
fail=0
pass=0

expect_lines() { # $1 file, $2 marker → the text after each "# <marker>: "
    sed -n "s/^# $2: //p" "$1"
}

# in_order OUTPUT EXPECTED — every expected line occurs in OUTPUT, each one
# strictly after the previous match.
in_order() {
    local out=$1 cursor=0 hit
    while IFS= read -r want; do
        hit=$(awk -v n="$cursor" -v s="$want" 'NR > n && index($0, s) { print NR; exit }' <<<"$out")
        [ -n "$hit" ] || return 1
        cursor=$hit
    done <<<"$2"
    return 0
}

for f in tests/caught/*.mojo; do
    name=$(basename "$f" .mojo)
    want=$(expect_lines "$f" expect-error)
    if out=$(mojo build "$f" -I src -o "build/tests/$name" 2>&1); then
        echo "FAIL caught/$name: compiled; expected an error containing: $want"
        fail=$((fail + 1))
    elif ! grep -qF -- "$want" <<<"$out"; then
        echo "FAIL caught/$name: failed for a different reason; wanted: $want"
        echo "$out" | grep 'error:' | head -3
        fail=$((fail + 1))
    else
        echo "ok   caught/$name"
        pass=$((pass + 1))
    fi
done

for f in tests/uncaught/*.mojo; do
    name=$(basename "$f" .mojo)
    if ! out=$(mojo build "$f" -I src -o "build/tests/$name" 2>&1); then
        echo "FAIL uncaught/$name: no longer compiles — the compiler may have caught it:"
        echo "$out" | grep 'error:' | head -3
        fail=$((fail + 1))
        continue
    fi
    if grep -q 'warning:' <<<"$out"; then
        echo "FAIL uncaught/$name: compiled with a diagnostic:"
        echo "$out" | grep 'warning:' | head -3
        fail=$((fail + 1))
        continue
    fi
    got=$("build/tests/$name")
    if in_order "$got" "$(expect_lines "$f" expect)"; then
        echo "ok   uncaught/$name"
        pass=$((pass + 1))
    else
        echo "FAIL uncaught/$name: output did not match in order. Got:"
        echo "$got" | sed 's/^/    /'
        fail=$((fail + 1))
    fi
done

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
