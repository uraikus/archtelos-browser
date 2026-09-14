#!/usr/bin/env bash
# Runs every test: the unit suites, the offscreen render checks and a
# headless screenshot of each example. Needs the Festina checkout on
# FESTINA_HOME (default: ../festina or ~/.festina).
#
#   tests/run.sh              # native builds
#   tests/run.sh --valgrind   # generic-CPU builds under valgrind
set -u
cd "$(dirname "$0")/.."
FESTINA_HOME="${FESTINA_HOME:-}"
if [ -z "$FESTINA_HOME" ]; then
    for cand in ../festina "$HOME/.festina" ../uraikus/festina; do
        if [ -x "$cand/bin/festina" ]; then FESTINA_HOME="$(cd "$cand" && pwd)"; break; fi
    done
fi
if [ -z "$FESTINA_HOME" ] || [ ! -x "$FESTINA_HOME/bin/festina" ]; then
    echo "set FESTINA_HOME to a Festina checkout (bin/festina not found)" >&2
    exit 2
fi
export FESTINA_HOME
VALGRIND=0
[ "${1:-}" = "--valgrind" ] && VALGRIND=1
BUILD="build/tests"
mkdir -p "$BUILD"
compile() {
    if [ "$VALGRIND" = 1 ]; then
        tools/festina-generic compile "$1" -o "$2"
    else
        "$FESTINA_HOME/bin/festina" compile "$1" -o "$2"
    fi
}
run() {
    if [ "$VALGRIND" = 1 ]; then
        valgrind -q --error-exitcode=99 --leak-check=no "$@"
    else
        "$@"
    fi
}
failed=0
for src in tests/unit/*.f tests/render/*.f; do
    name="$(basename "$src" .f)"
    if ! compile "$src" "$BUILD/$name" >/dev/null; then
        echo "COMPILE FAILED: $src"; failed=1; continue
    fi
    if ! run "$BUILD/$name"; then
        echo "FAILED: $src"; failed=1
    fi
done
if compile browser.f "$BUILD/browser" >/dev/null; then
    for page in examples/*.html; do
        out="$BUILD/$(basename "$page" .html).png"
        if run "$BUILD/browser" "$page" --screenshot "$out" --width 800 >/dev/null && [ -s "$out" ]; then
            echo "screenshot ok: $page -> $out"
        else
            echo "FAILED: screenshot of $page"; failed=1
        fi
    done
else
    echo "COMPILE FAILED: browser.f"; failed=1
fi
if [ "$failed" = 0 ]; then echo "all tests passed"; else echo "some tests failed"; fi
exit $failed
