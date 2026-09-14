#!/usr/bin/env bash
# Benchmarks, including comparisons against headless Chromium on the same
# input. Writes a table on stdout; benchmarks.md holds the recorded runs.
#
#   FESTINA_HOME=/path/to/festina tests/bench.sh
#   WPT_HTML_TESTS=/path/to/corpus tests/bench.sh     # also compares conformance
#
# Every measurement is the best of N runs, because the best run is the
# one least polluted by whatever else the machine was doing.
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

RUNS="${RUNS:-5}"
BENCH=build/bench
mkdir -p "$BENCH"

echo "building..."
"$FESTINA_HOME/bin/festina" compile browser.f -o "$BENCH/browser" >/dev/null || exit 1

# ---- the pages ---------------------------------------------------------
# Two hand-written examples plus one generated page, so the large case is
# reproducible without vendoring anyone else's HTML.
python3 - "$BENCH/generated.html" <<'PYEOF'
import sys
rows = []
rows.append('<!DOCTYPE html><html><head><meta charset="utf-8"><title>Generated benchmark page</title>')
rows.append('<style>body{font-family:sans-serif;margin:20px;line-height:1.5}'
            'h2{color:#234;border-bottom:1px solid #ccd}'
            '.card{border:1px solid #ccd;border-radius:6px;padding:8px;margin:8px 0;background:#f8f8fc}'
            'table{border-collapse:collapse;width:100%}td,th{border:1px solid #bbb;padding:3px 6px}'
            'th{background:#dde}.r{text-align:right}code{font-family:monospace;background:#eef}'
            'ul{margin:4px 0}li{margin:2px 0}</style></head><body>')
rows.append('<h1>Generated benchmark page</h1>')
for section in range(40):
    rows.append('<h2>Section %d</h2>' % section)
    rows.append('<div class="card"><p>Paragraph %d with <b>bold</b>, <i>italic</i>, '
                '<code>code</code> and a <a href="#x%d">link</a>, long enough that it '
                'has to wrap across several line boxes when laid out at a typical '
                'viewport width of eight hundred pixels or so.</p>' % (section, section))
    rows.append('<ul>' + ''.join('<li>Item %d of section %d</li>' % (i, section)
                                 for i in range(6)) + '</ul></div>')
    rows.append('<table><tr><th>Name</th><th>Kind</th><th class="r">Value</th></tr>')
    for i in range(12):
        rows.append('<tr><td>row %d.%d</td><td>kind %d</td><td class="r">%d</td></tr>'
                    % (section, i, i % 4, i * 37))
    rows.append('</table>')
rows.append('</body></html>')
open(sys.argv[1], 'w').write('\n'.join(rows))
PYEOF

PAGES="examples/hello.html examples/css.html $BENCH/generated.html"

human_size() { awk 'BEGIN{printf "%.0f KB", '"$(wc -c < "$1")"'/1024}'; }

# ---- end to end: html file in, rendered PNG out -------------------------
CHROME="$(python3 tests/chromium.py which 2>/dev/null)"
echo
echo "## End to end: parse, style, lay out and write a PNG (best of $RUNS, ms)"
echo
printf "%-26s %8s %12s %12s\n" "page" "size" "this browser" "chromium"
for page in $PAGES; do
    best=999999
    for _ in $(seq "$RUNS"); do
        start=$(date +%s%N)
        "$BENCH/browser" "$page" --screenshot "$BENCH/out.png" --width 800 >/dev/null 2>&1
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        [ "$ms" -lt "$best" ] && best=$ms
    done
    cbest="-"
    if [ -n "$CHROME" ]; then
        cb=999999
        for _ in $(seq "$RUNS"); do
            start=$(date +%s%N)
            "$CHROME" --headless --disable-gpu --no-sandbox --hide-scrollbars \
                --window-size=800,600 --screenshot="$BENCH/chrome.png" \
                "file://$PWD/$page" >/dev/null 2>&1
            end=$(date +%s%N)
            ms=$(( (end - start) / 1000000 ))
            [ "$ms" -lt "$cb" ] && cb=$ms
        done
        cbest="$cb"
    fi
    printf "%-26s %8s %12s %12s\n" "$(basename "$page")" "$(human_size "$page")" "$best" "$cbest"
done

# ---- the parse phase alone ------------------------------------------------
echo
echo "## HTML parsing alone (best of $RUNS, ms)"
echo
printf "%-26s %8s %12s %12s\n" "page" "size" "this browser" "chromium"
CHROME_PARSE="$(python3 tests/chromium.py parse "$RUNS" $PAGES 2>/dev/null)"
for page in $PAGES; do
    best=999999
    for _ in $(seq "$RUNS"); do
        ms=$(ARCHTELOS_TIMING=1 "$BENCH/browser" "$page" --screenshot "$BENCH/out.png" \
             --width 800 2>&1 | awk '/\[timing\] parse:/ {print $3}')
        [ -z "$ms" ] && ms=999999
        [ "$ms" -lt "$best" ] && best=$ms
    done
    cms=$(echo "$CHROME_PARSE" | awk -v n="$(basename "$page")" '$2 == n {printf "%.1f", $3}')
    [ -z "$cms" ] && cms="-"
    printf "%-26s %8s %12s %12s\n" "$(basename "$page")" "$(human_size "$page")" "$best" "$cms"
done

# ---- per phase, for the generated page --------------------------------------
echo
echo "## Phases of this browser, generated.html at 800px"
echo
ARCHTELOS_TIMING=1 "$BENCH/browser" "$BENCH/generated.html" --screenshot "$BENCH/out.png" \
    --width 800 2>&1 | grep '^\[timing\]' | sed 's/^\[timing\] /  /'

# ---- conformance, both engines ------------------------------------------------
if [ -n "${WPT_HTML_TESTS:-}" ]; then
    echo
    echo "## WHATWG tree-construction conformance (same corpus, same cases)"
    echo
    "$FESTINA_HOME/bin/festina" compile tests/conformance/html5lib.f -o "$BENCH/conformance" >/dev/null
    mine=$("$BENCH/conformance" | sed 's/conformance: //')
    echo "  this browser: $mine"
    if [ -n "$CHROME" ]; then
        chrome_line=$(python3 tests/chromium.py conformance "$WPT_HTML_TESTS" 2>/dev/null | head -1)
        set -- $chrome_line
        [ $# -ge 3 ] && echo "  chromium:     $2/$3 passed"
    fi
fi
echo
