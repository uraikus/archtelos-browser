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

# The control row. CLAUDE.md requires that, before any number here is
# copied into benchmarks.md, one row this change could not possibly have
# moved -- Chromium's, usually -- is checked against what it said last
# time, and that a row which shifted disqualifies the run. That was a
# thing to remember rather than a thing this script did, and a run
# reporting Chromium at 30.4 ms on the page where benchmarks.md records
# 25.6 printed without a word of complaint. The question is asked below
# instead, of the one number no change to this browser can move.
#
# CONTROL_MS is the middle of Chromium's own distribution rather than any
# one run of it, and the tolerance is set from that distribution's width
# rather than chosen: eight best-of-5 samples on an idle machine gave
# 25.3, 25.6, 25.6, 25.9, 26.1, 26.1, 27.4 and 28.8 ms, which is -3% to
# +11% around 26.0, and the contended run this check exists for sat at
# 30.4, which is +17%. Fifteen per cent separates them with room on both
# sides. A tighter band would fail honest runs, which is how a check
# earns being ignored.
#
# Raise CONTROL_MS when the reference browser itself changes -- a new
# Chromium is a new control, not a bad run -- and record the new
# distribution in benchmarks.md when you do.
CONTROL_PAGE="${CONTROL_PAGE:-generated.html}"
CONTROL_MS="${CONTROL_MS:-26.0}"
CONTROL_TOLERANCE="${CONTROL_TOLERANCE:-15}"
CONTROL_SEEN="-"

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

# The second large page. generated.html is headings, paragraphs, lists
# and tables: no <img>, no counter, no grid, no multi-column container,
# no transform and no form control, so the features that use those could
# land without any number here moving. It stays as it is, because every
# figure in benchmarks.md was taken against it and a new page is a new
# control the same way a new reference browser is; features.html is
# measured beside it. tests/featurepage.py writes it, its control, and
# the image both use.
python3 tests/featurepage.py "$BENCH" >/dev/null

# And the page is asked whether it still exercises what it claims to,
# because a page that has quietly stopped reads exactly like a feature
# that costs nothing. Each feature is turned off by an appended rule and
# has to change the render.
FEATURES_BAD=0
echo
echo "## Does the feature page exercise its features?"
echo
feature_check="$(python3 tests/featurepage.py --verify "$BENCH" "$BENCH/browser" 2>&1)" \
    || FEATURES_BAD=1
echo "$feature_check" | sed 's/^/  /'

PAGES="examples/hello.html examples/css.html $BENCH/generated.html $BENCH/features.html"

human_size() { awk 'BEGIN{printf "%.0f KB", '"$(wc -c < "$1")"'/1024}'; }

# ---- end to end: html file in, rendered PNG out -------------------------
# Both engines are given the SAME canvas: 800x600. Headless Chromium's
# --screenshot captures the viewport, so asking this browser for its
# default full-document canvas compared a 6.4-megapixel encode against a
# 0.48-megapixel one and charged the difference to layout. Encoding is
# linear in pixels and dominates both, so the canvas has to match for the
# number to mean anything.
CHROME="$(python3 tests/chromium.py which 2>/dev/null)"
CANVAS_W=800
CANVAS_H=600
echo
echo "## End to end: parse, style, lay out and write a ${CANVAS_W}x${CANVAS_H} PNG (best of $RUNS, ms)"
echo
printf "%-26s %8s %12s %12s\n" "page" "size" "this browser" "chromium"
for page in $PAGES; do
    best=999999
    for _ in $(seq "$RUNS"); do
        start=$(date +%s%N)
        "$BENCH/browser" "$page" --screenshot "$BENCH/out.png" \
            --width "$CANVAS_W" --height "$CANVAS_H" >/dev/null 2>&1
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
                --window-size="$CANVAS_W,$CANVAS_H" --screenshot="$BENCH/chrome.png" \
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
             --width "$CANVAS_W" --height "$CANVAS_H" 2>&1 | awk '/\[timing\] parse:/ {print $3}')
        [ -z "$ms" ] && ms=999999
        [ "$ms" -lt "$best" ] && best=$ms
    done
    cms=$(echo "$CHROME_PARSE" | awk -v n="$(basename "$page")" '$2 == n {printf "%.1f", $3}')
    [ -z "$cms" ] && cms="-"
    printf "%-26s %8s %12s %12s\n" "$(basename "$page")" "$(human_size "$page")" "$best" "$cms"
done

# ---- the rendering work itself, both engines ----------------------------
# Parse, style and lay out, with no process start-up and no PNG encode on
# either side. This is the comparison that means something: timing the
# whole command and subtracting a start-up baseline subtracts two numbers
# near 500 ms to get one near 50, and Chromium's start-up varies by more
# than 100 ms run to run, so that answer was mostly noise.
#
# Chromium's number is DOMParser + adoption into a sized container + a
# forced layout, timed inside the page with performance.now(). Ours is
# the sum of the parse, stylesheet, cascade and layout phases reported by
# ARCHTELOS_TIMING, which is the same work.
echo
echo "## Parse, style and lay out -- no start-up, no encode (best of $RUNS, ms)"
echo
printf "%-26s %8s %12s %12s\n" "page" "size" "this browser" "chromium"
CHROME_RENDER="$(python3 tests/chromium.py render "$RUNS" $PAGES 2>/dev/null)"
for page in $PAGES; do
    best=999999
    for _ in $(seq "$RUNS"); do
        ms=$(ARCHTELOS_TIMING=1 "$BENCH/browser" "$page" --screenshot "$BENCH/out.png" \
             --width "$CANVAS_W" --height "$CANVAS_H" 2>&1 | awk '
             /\[timing\] parse:/       { t += $3 }
             /\[timing\] stylesheets:/ { t += $3 }
             /\[timing\] cascade:/     { t += $3 }
             /\[timing\] layout:/      { t += $3 }
             END { print t }')
        [ -z "$ms" ] && ms=999999
        [ "$ms" -lt "$best" ] && best=$ms
    done
    cms=$(echo "$CHROME_RENDER" | awk -v n="$(basename "$page")" '$2 == n {printf "%.1f", $3}')
    [ -z "$cms" ] && cms="-"
    [ "$(basename "$page")" = "$CONTROL_PAGE" ] && CONTROL_SEEN="$cms"
    printf "%-26s %8s %12s %12s\n" "$(basename "$page")" "$(human_size "$page")" "$best" "$cms"
done

# The control, asked of the row above rather than left to the reader.
CONTROL_BAD=0
if [ "$CONTROL_SEEN" = "-" ]; then
    echo
    echo "control: Chromium did not report $CONTROL_PAGE, so nothing here is checked"
    CONTROL_BAD=1
else
    control_drift=$(awk -v got="$CONTROL_SEEN" -v want="$CONTROL_MS" 'BEGIN {
        d = (got - want) / want * 100; if (d < 0) d = -d; printf "%.1f", d }')
    if awk -v d="$control_drift" -v t="$CONTROL_TOLERANCE" 'BEGIN { exit !(d > t) }'; then
        echo
        echo "control: Chromium is ${CONTROL_SEEN} ms on $CONTROL_PAGE against ${CONTROL_MS} recorded" \
             "-- ${control_drift}% out, over the ${CONTROL_TOLERANCE}% this run is allowed."
        echo "control: this run is measuring the machine. Do not copy its numbers into benchmarks.md;" \
             "run it again on an idle machine, and raise CONTROL_MS only if the reference browser changed."
        CONTROL_BAD=1
    else
        echo
        echo "control: Chromium is ${CONTROL_SEEN} ms on $CONTROL_PAGE against ${CONTROL_MS} recorded," \
             "${control_drift}% -- within the ${CONTROL_TOLERANCE}% this run is allowed."
    fi
fi

# ---- what a full-document canvas costs -------------------------------------
# Not a comparison: headless Chromium will not produce this. It is here
# because the difference is almost all PNG encoding, and that is worth
# knowing before reading the table above as a layout result.
echo
echo "## The same page onto a full-document canvas (this browser only, best of $RUNS, ms)"
echo
printf "%-26s %12s %12s\n" "canvas" "ms" "pixels"
for h in 600 2000 8000; do
    best=999999
    for _ in $(seq "$RUNS"); do
        start=$(date +%s%N)
        "$BENCH/browser" "$BENCH/generated.html" --screenshot "$BENCH/out.png" \
            --width "$CANVAS_W" --height "$h" >/dev/null 2>&1
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        [ "$ms" -lt "$best" ] && best=$ms
    done
    printf "%-26s %12s %12s\n" "${CANVAS_W}x${h}" "$best" "$(( CANVAS_W * h ))"
done

# ---- what a gradient costs ----------------------------------------------
# A gradient is painted as a run of one-pixel bands, because the canvas's
# own fillLinearGradient cannot be called with colours that are not
# literals (FINDINGS.md, "a gradient cannot be built at run time"). That
# is a great many drawRect calls, and off the axis a great many polygon
# fills, so the cost is worth knowing rather than assuming. The control
# is the same page with flat backgrounds: same boxes, same layout, only
# the painting differs.
python3 tests/gradpages.py "$BENCH"

echo
echo "## What painting a gradient costs (60 boxes of 760x60, best of $RUNS, ms)"
echo
printf "%-34s %12s %12s\n" "page" "paint" "end to end"
for name in grad-flat grad-on grad-off; do
    bp=999999
    be=999999
    for _ in $(seq "$RUNS"); do
        start=$(date +%s%N)
        out=$(ARCHTELOS_TIMING=1 "$BENCH/browser" "$BENCH/$name.html" --screenshot "$BENCH/out.png" \
              --width "$CANVAS_W" --height "$CANVAS_H" 2>&1)
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        p=$(echo "$out" | awk '/\[timing\] paint:/ {print $3}')
        [ -n "$p" ] && [ "$p" -lt "$bp" ] && bp=$p
        [ "$ms" -lt "$be" ] && be=$ms
    done
    label="$name.html"
    [ "$name" = "grad-flat" ] && label="flat colours (the control)"
    [ "$name" = "grad-on" ] && label="gradients, along an axis"
    [ "$name" = "grad-off" ] && label="gradients, at 37 degrees"
    printf "%-34s %12s %12s\n" "$label" "$bp" "$be"
done

# ---- what the feature page's features cost -------------------------------
# The same document twice, with the same markup and the same element
# count; only the stylesheet differs. features-plain.html turns the grid
# into blocks, the multi-column containers into one column, the
# transforms into `none`, the generated counters into no generated
# content, `object-fit` back to its initial value and the form controls
# out of being painted as form controls. What separates the two rows is
# those features doing their work.
#
# Both pages fetch and decode the same image, so image loading is in
# both rows and in neither difference; the `images` phase below reports
# it on its own.
echo
echo "## What the feature page's features cost (best of $RUNS, ms)"
echo
printf "%-34s %9s %9s %9s %12s\n" "page" "cascade" "layout" "paint" "end to end"
for name in features-plain features; do
    bc=999999; bl=999999; bp=999999; be=999999
    for _ in $(seq "$RUNS"); do
        start=$(date +%s%N)
        out=$(ARCHTELOS_TIMING=1 "$BENCH/browser" "$BENCH/$name.html" --screenshot "$BENCH/out.png" \
              --width "$CANVAS_W" --height "$CANVAS_H" 2>&1)
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        c=$(echo "$out" | awk '/\[timing\] cascade:/ {print $3}')
        l=$(echo "$out" | awk '/\[timing\] layout:/ {print $3}')
        p=$(echo "$out" | awk '/\[timing\] paint:/ {print $3}')
        [ -n "$c" ] && [ "$c" -lt "$bc" ] && bc=$c
        [ -n "$l" ] && [ "$l" -lt "$bl" ] && bl=$l
        [ -n "$p" ] && [ "$p" -lt "$bp" ] && bp=$p
        [ "$ms" -lt "$be" ] && be=$ms
    done
    label="$name.html"
    [ "$name" = "features-plain" ] && label="features off (the control)"
    [ "$name" = "features" ] && label="features on"
    printf "%-34s %9s %9s %9s %12s\n" "$label" "$bc" "$bl" "$bp" "$be"
done

echo
echo "  Phases, features.html at ${CANVAS_W}px:"
ARCHTELOS_TIMING=1 "$BENCH/browser" "$BENCH/features.html" --screenshot "$BENCH/out.png" \
    --width "$CANVAS_W" --height "$CANVAS_H" 2>&1 | grep '^\[timing\]' | sed 's/^\[timing\] /    /'

# ---- what the preload scanner is worth -----------------------------------
# The scanner reads the raw bytes for <link>, <img> and <script> URLs
# before tree construction and prefetches them on four worker threads,
# so the requests overlap the parse instead of following it. Its whole
# value is hiding latency, and a local file has none, so this section
# measures against tests/latencyserver.py -- a real socket with a fixed
# 50 ms per response. ARCHTELOS_NO_PRELOAD=1 turns the scanner off, so
# both numbers come from one binary on one page.
PRELOAD_PORT="${PRELOAD_PORT:-8731}"
PRELOAD_DELAY="${PRELOAD_DELAY:-0.05}"
python3 tests/latencyserver.py "$PRELOAD_PORT" "$PRELOAD_DELAY" >/dev/null 2>&1 &
SRV_PID=$!
trap 'kill $SRV_PID 2>/dev/null' EXIT
sleep 1

if python3 -c "
import socket, sys
s = socket.socket(); s.settimeout(5)
try:
    s.connect(('127.0.0.1', $PRELOAD_PORT))
except OSError:
    sys.exit(1)
" 2>/dev/null; then
    echo
    echo "## What the preload scanner is worth (50 ms per response, best of $RUNS, ms)"
    echo
    printf "%-36s %10s %10s %12s\n" "page" "off" "on" "speed-up"
    for page in n2p2000 n8p400 n16p200; do
        url="http://127.0.0.1:$PRELOAD_PORT/$page"
        for mode in off on; do
            best=999999
            for _ in $(seq "$RUNS"); do
                start=$(date +%s%N)
                if [ "$mode" = off ]; then
                    ARCHTELOS_NO_PRELOAD=1 "$BENCH/browser" "$url" --screenshot "$BENCH/out.png" \
                        --width "$CANVAS_W" --height "$CANVAS_H" >/dev/null 2>&1
                else
                    "$BENCH/browser" "$url" --screenshot "$BENCH/out.png" \
                        --width "$CANVAS_W" --height "$CANVAS_H" >/dev/null 2>&1
                fi
                end=$(date +%s%N)
                ms=$(( (end - start) / 1000000 ))
                [ "$ms" -lt "$best" ] && best=$ms
            done
            [ "$mode" = off ] && off_ms=$best || on_ms=$best
        done
        ratio=$(awk -v a="$off_ms" -v b="$on_ms" 'BEGIN{ printf (b>0 ? "%.2fx" : "-"), a/b }')
        n=${page#n}; n=${n%%p*}
        printf "%-36s %10s %10s %12s\n" "$n subresources" "$off_ms" "$on_ms" "$ratio"
    done
    echo
    echo "  Phases, 16 subresources, preload off then on:"
    for mode in off on; do
        if [ "$mode" = off ]; then E=1; else E=""; fi
        ARCHTELOS_NO_PRELOAD=$E ARCHTELOS_TIMING=1 "$BENCH/browser" \
            "http://127.0.0.1:$PRELOAD_PORT/n16p200" --screenshot "$BENCH/out.png" \
            --width "$CANVAS_W" --height "$CANVAS_H" 2>&1 \
            | grep -E '\[timing\] (preload wait|stylesheets|images):' \
            | sed "s/^\[timing\] /    $mode: /"
    done
else
    echo
    echo "## What the preload scanner is worth"
    echo
    echo "  skipped: no latency server on 127.0.0.1:$PRELOAD_PORT"
fi
kill $SRV_PID 2>/dev/null
trap - EXIT

# ---- what the compiler vectorizes ----------------------------------------
# Festina has no SIMD types and no intrinsics, so whatever vector code
# this binary contains was put there by LLVM's autovectorizer on the IR
# the compiler generated. Which loops it reaches is worth knowing rather
# than assuming, so this reports packed instructions in named functions
# of the browser's own code -- not a count over the whole binary, which
# would mostly count scalar SSE and the C libraries this links.
if command -v objdump >/dev/null 2>&1; then
    echo
    echo "## What the autovectorizer reached (packed instructions per function)"
    echo
    printf "%-34s %10s %10s %12s\n" "function" "packed" "scalar" "widest"
    for fn in paintLinearGradient gradientColorAt asciiIndexOf cascadeMatches layoutBlock; do
        dis=$(objdump -d --disassemble="$fn" "$BENCH/browser" 2>/dev/null)
        [ -z "$dis" ] && continue
        packed=$(echo "$dis" | grep -coE '\b(v?(add|sub|mul|div|max|min)(ps|pd)|v?p(add|sub|mull|mulu|xor|or|and)[a-z]*|vpbroadcast[a-z]?)\b')
        scalar=$(echo "$dis" | grep -coE '\bv?(add|sub|mul|div|cvt)[a-z]*s[sd]\b')
        widest=$(echo "$dis" | grep -oE '%(zmm|ymm|xmm)' | sort -u | tail -1)
        printf "%-34s %10s %10s %12s\n" "$fn" "$packed" "$scalar" "${widest:--}"
    done
fi

# ---- memory and size ----------------------------------------------------
# Peak RSS is the largest amount of memory one process needed at one
# moment, measured with tests/maxrss.py (ru_maxrss for the child tree,
# because /usr/bin/time is not everywhere). Each run is a fresh
# interpreter, because ru_maxrss is a high-water mark that never falls.
echo
echo "## Peak memory rendering the same ${CANVAS_W}x${CANVAS_H} PNG (best of $RUNS, MB)"
echo
printf "%-26s %8s %12s %12s\n" "page" "size" "this browser" "chromium"
for page in $PAGES; do
    best=99999999
    for _ in $(seq "$RUNS"); do
        kb=$(python3 tests/maxrss.py -- "$BENCH/browser" "$page" --screenshot "$BENCH/out.png" \
             --width "$CANVAS_W" --height "$CANVAS_H")
        [ -n "$kb" ] && [ "$kb" -lt "$best" ] && best=$kb
    done
    cbest="-"
    if [ -n "$CHROME" ]; then
        cb=99999999
        for _ in $(seq "$RUNS"); do
            kb=$(python3 tests/maxrss.py -- "$CHROME" --headless --disable-gpu --no-sandbox \
                 --hide-scrollbars --window-size="$CANVAS_W,$CANVAS_H" \
                 --screenshot="$BENCH/chrome.png" "file://$PWD/$page")
            [ -n "$kb" ] && [ "$kb" -lt "$cb" ] && cb=$kb
        done
        cbest=$(awk "BEGIN{printf \"%.1f\", $cb/1024}")
    fi
    printf "%-26s %8s %12s %12s\n" "$(basename "$page")" "$(human_size "$page")" \
        "$(awk "BEGIN{printf \"%.1f\", $best/1024}")" "$cbest"
done

# ---- what the binary costs ----------------------------------------------
# The whole browser is one native binary with no vendored code, so its
# size is a real number rather than the entry point of an install tree.
# Chromium's is given for scale only: its main executable is one file of
# many, and the install it comes from is far larger than the row says.
echo
echo "## Binary size"
echo
printf "%-40s %14s\n" "binary" "bytes"
printf "%-40s %14s\n" "this browser (build/bench/browser)" "$(wc -c < "$BENCH/browser")"
if [ -n "$CHROME" ]; then
    printf "%-40s %14s\n" "chromium (main executable only)" "$(wc -c < "$CHROME")"
    cdir="$(dirname "$CHROME")"
    printf "%-40s %14s\n" "chromium (whole install tree)" "$(du -sb "$cdir" | cut -f1)"
fi
printf "%-40s %14s\n" "this browser (source, all .f files)" "$(cat browser.f $(find src -name '*.f') | wc -c)"

# ---- per phase, for the generated page --------------------------------------
echo
echo "## Phases of this browser, generated.html at 800px"
echo
ARCHTELOS_TIMING=1 "$BENCH/browser" "$BENCH/generated.html" --screenshot "$BENCH/out.png" \
    --width "$CANVAS_W" --height "$CANVAS_H" 2>&1 | grep '^\[timing\]' | sed 's/^\[timing\] /  /'

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

# A disqualified control fails the run, and so does a feature page that
# has stopped exercising a feature, so a script that copies these
# numbers anywhere has to decide what to do about it rather than not
# notice.
if [ "$CONTROL_BAD" != 0 ] || [ "$FEATURES_BAD" != 0 ]; then exit 1; fi
exit 0
