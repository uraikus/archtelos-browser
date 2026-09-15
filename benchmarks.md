# Benchmarks

Measurements of this browser against headless Chromium on the same
input. This file records runs and is therefore dated by nature; the
other documents describe the present (CLAUDE.md, §3).

Re-run everything with:

```bash
FESTINA_HOME=/path/to/festina WPT_HTML_TESTS=/path/to/corpus tests/bench.sh
```

## Method

- **Machine**: x86-64 container, Linux 6.18, 4 CPUs. Ubuntu 24.04 with
  DejaVu fonts, Cairo 1.18.
- **Builds**: this browser compiled natively by Festina 0.44 through
  `bin/festina compile` (not the generic-CPU build that
  `tools/festina-generic` makes for valgrind — that one is slower).
  Chromium 141.0.7390.37, headless, `--disable-gpu --no-sandbox`.
- **Statistic**: best of 5 runs. The best run is the one least
  disturbed by whatever else the machine was doing; medians and means
  on a shared container mostly measure the neighbours.
- **Both engines get the same canvas**, 800x600, and the rendering
  comparison is measured from inside both engines rather than by
  subtracting a start-up baseline. Both of those are easy to get wrong
  and this file has got both of them wrong — see below.
- **Memory** is peak resident set size from `tests/maxrss.py`, and
  **size** is `wc -c` on the binaries. Both are described where they
  are reported.
- **Pages**: the two examples in this repository, plus
  `generated.html`, which `tests/bench.sh` generates deterministically
  (40 sections, each a heading, a bordered card with a wrapping
  paragraph and a six-item list, and a twelve-row table: 2,728
  elements, 51 KB). Nobody else's HTML is vendored here.

Everything below was measured on 2026-09-15.

## The canvas has to match, or the number means nothing

Headless Chromium's `--screenshot` captures the **viewport**. This
browser's `--screenshot` defaults to a canvas the height of the whole
**document**. On `generated.html` that is 800x600 against 800x8000:
Chromium encodes 480,000 pixels and this browser encodes 6,400,000, more
than thirteen times as many.

PNG encoding is linear in pixels and dominates both engines at this page
size, so that difference was being charged to layout:

| Canvas | This browser | Pixels |
|---|---|---|
| 800x600 | 115 ms | 480,000 |
| 800x2000 | 154 ms | 1,600,000 |
| 800x8000 | 330 ms | 6,400,000 |

Same page, same layout, same paint — 215 ms of the difference is
encoding. `tests/bench.sh` gives both engines 800x600.

## Start-up is not a rendering result, and subtracting it does not work

Chromium takes **446 ms** to screenshot a one-line page at 800x600, and
this browser takes **28 ms**. That difference is process start-up — a
browser engine bringing up a multi-process architecture, a JavaScript
engine, a compositor and a network stack, against a 2.3 MB native binary
that opens a Cairo surface. It is real if what you want is a screenshot
from a shell script, and it says nothing about rendering speed.

The obvious repair is to subtract that baseline from every row. **That
repair does not work, and this file used to report a headline that came
out of it.** Twelve consecutive start-up measurements of Chromium on
this machine:

```
436 470 476 483 487 493 505 511 511 516 521 542
```

A spread of 106 ms, around a quantity of about 30 to 90 ms. Subtracting
a number near 500 from a number near 510 to obtain the rendering work
measures the variance of the baseline and almost nothing else: on one
run it says Chromium is 1.15 times faster on the 51 KB page, on the next
3.8 times. Both were noise.

So the comparison worth making is measured directly, on both sides, with
start-up outside the timer.

## End to end: HTML file in, 800x600 PNG out

What a shell script waiting for a PNG actually experiences:

| Page | Size | This browser | Chromium |
|---|---|---|---|
| hello.html | 4 KB | 36 ms | 446 ms |
| css.html | 3 KB | 36 ms | 481 ms |
| generated.html | 51 KB | 115 ms | 470 ms |

This browser is done before Chromium has finished starting. That is a
true statement about the command and a false one about the engine, which
is what the next table is for.

## The rendering work itself

Parse, style and lay out, with no process start-up and no PNG encode on
either side. Chromium's number is `DOMParser`, adoption into an 800px
container, and a forced layout, timed inside the page with
`performance.now()`; ours is the sum of the parse, stylesheet, cascade
and layout phases that `ARCHTELOS_TIMING=1` reports. Same work, same
page, both measured from inside.

| Page | Size | This browser | Chromium | Ratio |
|---|---|---|---|---|
| hello.html | 4 KB | 10 ms | 1.2 ms | 8x |
| css.html | 3 KB | 10 ms | 0.9 ms | 11x |
| generated.html | 51 KB | 81 ms | 25.5 ms | **3.2x** |

**Chromium renders the 51 KB page about three times faster**,
and the gap is wider on small pages because a fixed cost of about 10 ms
has nothing to amortize against. This is the honest headline, and it is
a worse one than this file used to carry. The cascade and layout are
where it lives; the section after next says where inside them.

## HTML parsing alone

Chromium's number is `DOMParser.parseFromString` timed inside the page
with `performance.now()`; ours is the parse phase reported by
`ARCHTELOS_TIMING=1`, which includes the byte pre-pass that rewrites
non-ASCII input (see FINDINGS.md, "text has no substring").

| Page | Size | This browser | Chromium |
|---|---|---|---|
| hello.html | 4 KB | <1 ms | 0.3 ms |
| css.html | 3 KB | <1 ms | 0.2 ms |
| generated.html | 51 KB | 8 ms | 3.9 ms |

**Between two and four times slower** on the large page. Ours is 8 ms
run after run; Chromium's has been measured between 2.1 and 3.9 ms
across runs, so a single ratio would be reporting that spread rather
than a difference — the row gives the run this table came from. Call it
6 MB/s against 13 to 25. For a tokenizer and tree builder written in a
young language against one of the most optimized parsers in software
that is a reasonable place to be, and at 8 ms of an 81 ms render it is
not where the time goes.

## Where the time actually goes

`generated.html` at 800x600, 2,728 elements:

| Phase | Time |
|---|---|
| fetch (local file) | 0 ms |
| parse | 8 ms |
| stylesheets | 2 ms |
| images | 1 ms |
| cascade | 28 ms |
| layout | 48 ms |
| paint | 6 ms |

The cascade and layout are **88%** of it. Parsing is 9%, and paint —
once it is not also encoding six megapixels — is 6 ms. Chromium does the
first four of those phases in 25.5 ms against our 81; the whole gap is
here, and **layout is now the larger half of it**.

Inside the cascade: 8,578 selector tests produce 11,614 matched
declarations across 2,728 elements. Collecting them is 7 ms, applying
12 ms and computing 8 ms — the last of those because only **24 distinct
styles** are computed for the 2,728 elements, and the rest are handed a
style a previous element already produced. Computing styles is the phase worth
attacking next, and the one that grows with every property implemented.

Inside layout: 11,564 text measurements, of which 620 miss the width
cache and reach Cairo (9 ms total); building the box tree is 14 ms and
inline placement 12 ms.

## What the CSS work cost, measured

Every revision below was rebuilt and re-run on the same machine within
the same few minutes, so the column is a comparison between builds and
not between days. Best of seven, `generated.html` at 800x600.

Read the column against itself, not against the tables above: those come
from a different run, and this machine's whole-command numbers drift by
several milliseconds between runs. The final row is 114 ms here and
115 ms in the end-to-end table for that reason. What the column
establishes is the *shape* — which change cost what — and that is not
sensitive to the drift, because every row moved together.

| Revision | What it added | End to end |
|---|---|---|
| `39dd9c7` | the equal-canvas benchmark | 131 ms |
| `635bea7` | the two conformance runners | 131 ms |
| `6971286` | `calc()` and custom properties | 136 ms |
| `1aa3126` | positioning | 154 ms |
| `ab697dc` | floats and `clear` | 156 ms |
| `f6fda9b` | box-sizing, max-height, outline, … | 161 ms |
| before tuning | flexbox | 164 ms |
| after tuning | the four changes below | 145 ms |
| this revision | one computed style per distinct match | **114 ms** |

**Positioning alone cost 18 ms of the 33**, and none of it was in the
feature: it was work every page paid whether or not it had a positioned
box. Four changes took 19 ms back:

- **The positioned-layout pass is skipped** when the document contains
  no positioned box. It was a second walk of the whole box tree on
  every page.
- **The painter's two-pass z-index child ordering is skipped** the same
  way, for a single pass in document order. Paint went from 9 ms to
  6 ms.
- **`boxIsOutOfFlow` and `boxIsFloated` answer from a document-level
  flag first.** They are asked of every child of every block, and on a
  page with neither they now cost one boolean read instead of four
  field reads. `applyFloatsToLine`, once per line box, likewise returns
  the containing block's edges without scanning the float list.
- **Two allocations came out of the cascade's inner loop**: a fresh
  `ascii` built per declaration per element to read two characters,
  which `text.charCodeAt` reads without allocating, and the `'var('`
  needle that `styleProp` rebuilt on every property read of every
  element.

The last row is a different kind of change, and a larger one. Computing
a style had grown to 37 ms because every element paid to parse every
declaration that matched it. It is 8 ms now, because **only 24 distinct
styles exist on this page**: an element whose matched declarations and
parent are the same as an earlier element's is handed that element's
computed style instead of parsing the values again. The section above
has the numbers; peak memory fell 3.5 MB with it, since 2,728 computed
styles became 24.

That leaves layout as the larger half of the remaining gap, which is
where todo.md now points.

## Conformance, measured on both engines


The same 1,652 cases of the WHATWG HTML standard's own tree-construction
corpus, run through both parsers and compared against the same expected
serializations. Chromium's run uses `tests/chromium.py`, which drives
its parser through `document.write` into an iframe and serializes the
result in the corpus's format.

| | Passed | Rate |
|---|---|---|
| This browser | 1535 / 1652 | 92.9% |
| Chromium 141 | 1535 / 1652 | 92.9% |

The two are level, and not by passing the same cases: this browser is
ahead on 23 and behind on 23.

**84 of the 117 cases each engine fails are the same cases** — the whole
of `processing-instructions.dat`, where the corpus expects `<?x>` to
build a processing-instruction node and both build a comment, which is
what the tokenizer's bogus-comment state produces. Setting that file
aside, both pass 1,495 of 1,528.

Where the two differ, in cases:

| File | This browser | Chromium |
|---|---|---|
| noscript01.dat | 18/18 | 3/18 |
| html5test-com.dat | 29/30 | 26/30 |
| webkit02.dat | 44/44 | 42/44 |
| tests18.dat | 36/36 | 35/36 |
| tests25.dat | 26/26 | 25/26 |
| tests5.dat | 16/16 | 15/16 |
| tests26.dat | 15/20 | 20/20 |
| tests16.dat | 180/191 | 185/191 |
| tests2.dat | 59/63 | 63/63 |
| tests1.dat | 107/112 | 109/112 |
| tests19.dat | 101/103 | 103/103 |
| adoption01.dat | 16/17 | 17/17 |
| adoption02.dat | 3/4 | 4/4 |
| tables01.dat | 18/19 | 19/19 |
| tests6.dat | 38/39 | 39/39 |
| namespace-sensitivity.dat | 0/1 | 1/1 |

This browser wins `noscript01.dat` only because it has no script engine
at all, so its scripting flag is permanently disabled, which is the mode
that file assumes; Chromium runs those cases with scripting enabled.
That is a difference in configuration, not in quality.

What is left on each side is small and scattered: foreign-content
corners and a few adoption-agency cases here, and on Chromium's side
mostly cases where its scripting flag is enabled. todo.md tracks the
ones worth closing.

## Peak memory

Peak resident set size, rendering the same 800x600 PNG. Measured with
`tests/maxrss.py`, which runs the command and reads `ru_maxrss` for the
child tree, because `/usr/bin/time` is not present in every environment
this runs in. `ru_maxrss` is a high-water mark across every descendant
that has been reaped, so a multi-process browser is scored by its
largest single process rather than by the sum of them — the honest
comparison to make against a single-process engine, but the reason the
Chromium column understates total system memory for that run.

| Page | Size | This browser | Chromium |
|---|---|---|---|
| hello.html | 4 KB | 12.9 MB | 195.5 MB |
| css.html | 3 KB | 13.0 MB | 195.5 MB |
| generated.html | 51 KB | 17.0 MB | 194.6 MB |

**About 15x less on a small page and 10x less on the large one**, and
the shape differs as much as the size: Chromium's footprint is flat
across all three pages because it is almost entirely fixed cost —
process architecture, a JavaScript heap, a compositor — while this
browser's grows with the document, from 12.9 MB to 17.0 MB as the page
goes from 4 KB to 51 KB. The 4.1 MB of growth is the DOM and the box
tree for 2,728 elements — about 1.5 KB per element across both. The
computed styles are no longer part of it: there are 24 of them, however
many elements the page has.

This is the same trade as the start-up figure above, seen from the other
side: what this browser does not have costs nothing to keep in memory.
It is not a claim that the engine is frugal with what it does build.

## Build

| | |
|---|---|
| Source | 12,978 lines of Festina across `browser.f` and `src/` |
| Compile | 9.5 s, whole program, no incremental build |
| Binary | 2.3 MB, linking Cairo, X11, libjpeg, mbedTLS and libc |

Against Chromium, whose binary this browser is compared with everywhere
else in this file:

| | Bytes |
|---|---|
| This browser, the whole program | 2,330,728 |
| This browser, all `.f` source | 430,389 |
| Chromium, main executable only | 463,227,992 |
| Chromium, whole install tree | 624,734,779 |

**The binary is about 200 times smaller than Chromium's executable
alone**, and 269 times smaller than the tree it ships in. The comparison
flatters this browser and should be read with that in mind: what is
absent from the 2.3 MB — a JavaScript engine, a compositor, a sandbox,
a network stack, an extension system, ICU — is most of what is in the
463 MB. The figure is a fair measure of *this* program's size and a poor
measure of how much cheaper a browser could be.

Of that 9.1 s, **4.2 s is the single generated map literal** holding the
standard's 2,231 named character references: a one-line program compiles
in 0.6 s, and the same program importing only that table takes 4.8 s.
The table is the right data structure — it looks up in constant time and
the runtime cost is nil — but a large literal is priced at compile time,
which is worth knowing before generating another one.
