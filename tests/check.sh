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
#
# Then a third claim, about a tool rather than the compiler: each uncaught
# case is rebuilt with `mojo build --sanitize thread` and run, and what
# ThreadSanitizer says is checked against the file's `# expect-tsan: race` or
# `# expect-tsan: clean` line. `src/origins.mojo` — the corrected listing —
# carries the same marker and is the control: a "clean" verdict only means
# something if a correct program earns one.
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

# ── the sanitizer's verdict ─────────────────────────────────────────────────
# What a tool can see at runtime, as opposed to what the compiler sees at
# build time. Only `plain_store_races` is a data race; the three lifetime bugs
# come out clean, and that is the finding rather than a hole in the harness.
# Each of them poisons its cell from the *main* thread — before `pthread_create`
# in two cases, after the join in the third — so every access is ordered and
# there is nothing for TSan to report. A race detector is the wrong instrument
# for a use-after-destroy; mojolint's L001/L002 remain the ones that catch
# those.
#
# The leg is skipped where ThreadSanitizer cannot run at all. On linux-64 with
# Mojo 1.0.0 the binary links, but the runtime's bundled TCMalloc aborts during
# startup under TSan's address-space reservation ("MmapAligned() failed ...
# TCMalloc assumes a 48-bit virtual address space"). A canary decides;
# CHECK_TSAN=1 forces the leg to run anyway (to find out whether a newer
# toolchain has fixed it), CHECK_TSAN=0 skips it.

# tsan_canary — can a trivial `--sanitize thread` binary build and run here?
tsan_canary() {
    cat >build/tests/tsan_canary.mojo <<'CANARY'
def main():
    print("tsan canary ok")
CANARY
    mojo build --sanitize thread build/tests/tsan_canary.mojo \
        -o build/tests/tsan_canary >build/tests/tsan_canary.log 2>&1 || return 1
    build/tests/tsan_canary >>build/tests/tsan_canary.log 2>&1
    grep -q 'tsan canary ok' build/tests/tsan_canary.log
}

run_tsan=1
skip_reason=
case "${CHECK_TSAN:-auto}" in
0) run_tsan=0 skip_reason="CHECK_TSAN=0" ;;
1) ;;
*) tsan_canary || {
    run_tsan=0
    skip_reason="the canary did not run — see build/tests/tsan_canary.log"
} ;;
esac

if [ "$run_tsan" = 0 ]; then
    echo "skip ThreadSanitizer leg: $skip_reason"
else
    # Without this TSan prints "Stack dump without symbol names" and a report
    # names an address instead of a Mojo frame. The symbolizer ships in the
    # same conda package as mojo.
    if [ -z "${LLVM_SYMBOLIZER_PATH:-}" ]; then
        symbolizer=$(command -v llvm-symbolizer || true)
        [ -n "$symbolizer" ] && export LLVM_SYMBOLIZER_PATH="$symbolizer"
    fi
    for f in tests/uncaught/*.mojo src/origins.mojo; do
        name=$(basename "$f" .mojo)
        want=$(expect_lines "$f" expect-tsan)
        if [ "$want" != race ] && [ "$want" != clean ]; then
            echo "FAIL tsan/$name: no '# expect-tsan: race|clean' line in $f"
            fail=$((fail + 1))
            continue
        fi
        if ! out=$(mojo build --sanitize thread "$f" -I src \
            -o "build/tests/$name-tsan" 2>&1); then
            echo "FAIL tsan/$name: --sanitize thread build failed:"
            echo "$out" | grep -i 'error' | head -3
            fail=$((fail + 1))
            continue
        fi
        log="build/tests/$name.tsan.log"
        # A reported race aborts the process, and the shell announces that
        # ("Abort trap: 6") on its own stderr, in the middle of the results.
        # Run it one shell down so that announcement goes to /dev/null while
        # the program's own output still lands in the log.
        bash -c '"$0" >"$1" 2>&1' "build/tests/$name-tsan" "$log" 2>/dev/null
        status=$?
        # TSan's exit code is not the verdict: a reported race aborts the
        # process here, and a clean run under a different version might not
        # exit 0 either. The verdict is what it printed.
        races=$(grep -c 'WARNING: ThreadSanitizer' "$log")
        if [ "$want" = race ] && [ "$races" -eq 0 ]; then
            echo "FAIL tsan/$name: expected a race; ThreadSanitizer reported none"
            fail=$((fail + 1))
        elif [ "$want" = clean ] && [ "$races" -ne 0 ]; then
            echo "FAIL tsan/$name: expected a clean run; ThreadSanitizer reported $races:"
            grep -A3 'WARNING: ThreadSanitizer' "$log" | head -16 | sed 's/^/    /'
            fail=$((fail + 1))
        elif [ "$want" = clean ] && [ "$status" -ne 0 ]; then
            echo "FAIL tsan/$name: clean, but the run exited $status:"
            tail -5 "$log" | sed 's/^/    /'
            fail=$((fail + 1))
        else
            echo "ok   tsan/$name ($want)"
            pass=$((pass + 1))
        fi
    done
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
