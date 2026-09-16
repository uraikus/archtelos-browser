# Benchmarks

Measurements of this browser against headless Chromium on the same
input. This file records runs and is therefore dated by nature; the
other documents describe the present (CLAUDE.md, §3).

Re-run everything with:

```bash
FESTINA_HOME=/path/to/festina WPT_HTML_TESTS=/path/to/corpus tests/bench.sh
```

## Method

- **Machine**: x86-64 container, Linux 6.18, 4 CPUs. The preload
  scanner uses four worker threads, so it is scheduled against that
  same core count rather than on top of it. Ubuntu 24.04 with
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

Everything below was measured on 2026-09-16.

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
| 800x600 | 134 ms | 480,000 |
| 800x2000 | 170 ms | 1,600,000 |
| 800x8000 | 349 ms | 6,400,000 |

Same page, same layout, same paint — 215 ms of the difference is
encoding. `tests/bench.sh` gives both engines 800x600.

## Start-up is not a rendering result, and subtracting it does not work

Chromium takes **471 ms** to screenshot a one-line page at 800x600, and
this browser takes **38 ms**. That difference is process start-up — a
browser engine bringing up a multi-process architecture, a JavaScript
engine, a compositor and a network stack, against a 2.6 MB native binary
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
| hello.html | 4 KB | 38 ms | 471 ms |
| css.html | 3 KB | 37 ms | 485 ms |
| generated.html | 51 KB | 130 ms | 493 ms |

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
| hello.html | 4 KB | 11 ms | 1.1 ms | 10x |
| css.html | 3 KB | 11 ms | 1.0 ms | 11x |
| generated.html | 51 KB | 98 ms | 24.9 ms | **3.9x** |

**Chromium renders the 51 KB page about four times faster**, and the gap
is wider on small pages because a fixed cost of about 10 ms has nothing
to amortize against. The cascade and layout are where it lives; the
section after next says where inside them.

Four of our 98 ms are the preload scanner's worker threads taxing every
allocation in the process, on a page that prefetches nothing — see
"what the preload scanner is worth" below. The movement from the 93 ms
this file carried before is the machine, not the code: the previous
revision, rebuilt and run alternately with this one in the same
minutes, gives 97 to 104 ms against this one's 96 to 104. Chromium's
own row is the control — 24.9 ms today against 25.3 ms then — and it
did not move, which is what makes the run worth recording at all.

## HTML parsing alone

Chromium's number is `DOMParser.parseFromString` timed inside the page
with `performance.now()`; ours is the parse phase reported by
`ARCHTELOS_TIMING=1`, which includes the byte pre-pass that rewrites
non-ASCII input (see FINDINGS.md, "text has no substring").

| Page | Size | This browser | Chromium |
|---|---|---|---|
| hello.html | 4 KB | <1 ms | 0.1 ms |
| css.html | 3 KB | <1 ms | 0.1 ms |
| generated.html | 51 KB | 8 ms | 2.0 ms |

**Between two and four times slower** on the large page. Ours is 8 ms
run after run; Chromium's has been measured between 2.1 and 3.9 ms
across runs, so a single ratio would be reporting that spread rather
than a difference — the row gives the run this table came from. Call it
6 MB/s against 13 to 25. For a tokenizer and tree builder written in a
young language against one of the most optimized parsers in software
that is a reasonable place to be, and at 8 ms of a 98 ms render it is
not where the time goes.

## Where the time actually goes

`generated.html` at 800x600, 2,728 elements:

| Phase | Time |
|---|---|
| fetch (local file) | 0 ms |
| parse | 9 ms |
| stylesheets | 1 ms |
| images | 1 ms |
| cascade | 35 ms |
| layout | 56 ms |
| paint | 7 ms |

The cascade and layout are **93%** of it. Parsing is 9%, and paint —
once it is not also encoding six megapixels — is 7 ms. Chromium does the
first four of those phases in 24.9 ms against our 98; the whole gap is
here, and **layout is the larger half of it**.

Inside the cascade: 8,578 selector tests produce 11,614 matched
declarations across 2,728 elements. Collecting them is 12 ms, applying
14 ms and computing 7 ms — the last of those because only **24 distinct
styles** are computed for the 2,728 elements, and the rest are handed a
style a previous element already produced. Computing styles is the phase worth
attacking next, and the one that grows with every property implemented.

Inside layout: 11,564 text measurements, of which 620 miss the width
cache and reach Cairo (9 ms total); building the box tree is 23 ms and
inline placement 14 ms.

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

## What painting a gradient costs

A gradient is painted as a run of one-pixel bands of flat colour,
because the canvas's own `fillLinearGradient` cannot be called with
colours that are not literals (FINDINGS.md, "a gradient cannot be built
at run time"). The control is the same page with flat backgrounds: same
sixty boxes, same layout, only the painting differs.

| Page | Paint | End to end |
|---|---|---|
| flat colours (the control) | 0 ms | 25 ms |
| gradients, along an axis | 1 ms | 27 ms |
| gradients, at 37 degrees | **14 ms** | **60 ms** |

**An axis-aligned gradient is nearly free and an angled one is not**, and
the difference is structural rather than incidental. Along an axis each
band is one rectangle, so the work is proportional to the gradient
line's length — about 500 rectangles for one of these boxes. Off the
axis a band is not a rectangle, and drawing it as a polygon stipples the
result, so each band is drawn as one-pixel-tall horizontal runs: the
work becomes the line's length times the box's height, about 30,000
rectangles for the same box.

That is the honest cost of not having the two things that would do this
properly — a gradient fill that takes runtime colours, and a clip region
— and it is written down here rather than discovered later. Rendering
the gradient once into an offscreen image and drawing that image would
collapse it back; todo.md carries the idea.

Both figures are measured at 800x600, which is the viewport, so most of
the 4,080-pixel-tall page is culled. A page whose angled gradients are
all on screen pays more.

## What the preload scanner is worth

The preload scanner reads the raw bytes for `<link rel=stylesheet>`,
`<img src>` and `<script src>` before tree construction and prefetches
them on four worker threads, so the requests overlap the parse instead
of following it.

Latency is the only thing it hides, and a local file has none, so this
is measured against `tests/latencyserver.py` — a real socket answering
every request after a fixed 50 ms. `ARCHTELOS_NO_PRELOAD=1` turns the
scanner off, so both columns come from one binary on one page.

| Subresources | Scanner off | Scanner on | |
|---|---|---|---|
| 2 | 315 ms | 176 ms | 1.79x |
| 8 | 826 ms | 233 ms | 3.55x |
| 16 | 1557 ms | 413 ms | **3.77x** |

Where the time goes, on the 16-subresource page:

| Phase | Off | On |
|---|---|---|
| waiting for prefetches | 0 ms | 331 ms |
| stylesheets | 739 ms | 0 ms |
| images | 736 ms | 1 ms |

**Two separate effects, and only one of them is the scanner's.** Most of
what this table shows is parallelism: sixteen requests at 50 ms cost
1,483 ms one after another and 327 ms across four threads, and that
would be true of any concurrent fetch, scanned for or not. The scanner's
own contribution is the overlap with parsing, and on these pages the
parse is 1 ms, so there is nothing to overlap and the overlap is worth
nothing.

Isolating it needs a page big enough to parse. On a 640 KB document with
two subresources:

| Phase | Off | On |
|---|---|---|
| parse | 125 ms | 127 ms |
| waiting for prefetches | 0 ms | **0 ms** |
| stylesheets | 69 ms | 12 ms |
| images | 77 ms | 16 ms |

Nothing is waited for, because both 50 ms fetches finish inside the
127 ms parse. That is the scanner proper, and it is bounded by the parse
time: it can hide one parse worth of latency and not a millisecond more.

That page is not in the table above because it cannot be fairly timed
end to end — at 640 KB its own HTML costs 30.7 seconds to fetch, in both
columns, for the 64 KiB reason below. The phase timings are unaffected
by that and are what is quoted.

**What it costs the pages that do not use it**, which is the part this
file got wrong first time: **4 ms on the 51 KB page**, plus 0.5 ms of
process start-up and 30 KB of binary (2,370,912 → 2,401,552). A
`file://` page dispatches no prefetch at all and still pays.

The 4 ms is a paired median over twenty interleaved runs of the build
before this change and the build after, positive in 17 of 20 — not a
difference against a number written down on another day. It is not the
scan, which is 0 ms and skipped outright for a non-HTTP base; it is the
four worker threads *existing*. glibc's `malloc` abandons its
single-threaded fast path permanently at the first `pthread_create`, and
Festina allocates on almost every operation, so an allocation-heavy
probe slows 9% from four threads that are asleep and have never been
sent anything, while an allocation-free one does not move at all.
Killing the workers does not give it back (FINDINGS.md, "declaring a
thread taxes every allocation in the program").

This project's rules say a feature must not cost anything to the pages
that do not use it, and this one does. The fix — create a thread when it
is first used — is not available in Festina, so what is left is to say
so here rather than to round it to zero.

The 64 KiB ceiling in the table above is not a choice. An HTTP response
larger than that takes thirty seconds, because the client reads to EOF
rather than to `Content-Length` and a keep-alive server never sends one
(FINDINGS.md, "an HTTP response larger than 64 KiB takes thirty
seconds"). The latency server stays under the limit so that this
benchmark measures prefetching rather than that.

## What the autovectorizer reached

Festina has no SIMD types and no intrinsics, so whatever vector code
this binary contains was put there by LLVM's autovectorizer working on
the IR the compiler generated. The question worth answering is not
whether the binary contains vector instructions — it links Cairo and
libc, which are full of hand-written SIMD — but whether the browser's
own loops were vectorized. So this counts **packed** instructions in
named functions, against the **scalar** float instructions that also
live in `%xmm` registers and are not vectorization at all.

| Function | Packed | Scalar | Widest register |
|---|---|---|---|
| `paintLinearGradient` | 14 | 45 | `%xmm` |
| `gradientColorAt` | 4 | 21 | `%xmm` |
| `layoutBlock` | 7 | 7 | `%xmm` |
| `asciiIndexOf` | 0 | 0 | — |
| `cascadeMatches` | 0 | 0 | — |

**The vectorizer works, and this browser's hot loops mostly defeat it.**
That it works is not in doubt — a clean elementwise integer loop
compiles to four unrolled `vpmullq`/`vpaddq` pairs on `%ymm` registers,
with a `vextracti128` reduction tail:

```
vpbroadcastq %rsi,%ymm0
vpmullq      (%rdx,%rax,8),%ymm0,%ymm5     ; four 64-bit lanes
vpaddq       %ymm1,%ymm5,%ymm1
```

The browser's own loops do not get that treatment because they are not
that shape: `asciiIndexOf` exits early, `cascadeMatches` walks a tree
through pointers, and the paint loops carry a branch per pixel. What
`paintLinearGradient` does get — 14 packed double operations against 45
scalar ones — is the vectorizer catching the arithmetic between the
branches, not the loop.

This is a host-CPU build, which is why the numbers here are not portable
and why `tools/festina-generic` exists: the generic build compiles the
same loop to SSE2, with `%xmm` two lanes wide and no 64-bit multiply
instruction at all, so it synthesises one out of `pmuludq`, `psrlq`,
`psllq` and `paddq`. Same source, same compiler, roughly half the width.

Making the gradient row fill vectorizable — a branch-free pass over a
row of pixels — is the one place here where it would plainly pay;
todo.md carries it.

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
| hello.html | 4 KB | 13.2 MB | 194.5 MB |
| css.html | 3 KB | 13.4 MB | 194.1 MB |
| generated.html | 51 KB | 18.0 MB | 194.5 MB |

**About 15x less on a small page and 10x less on the large one**, and
the shape differs as much as the size: Chromium's footprint is flat
across all three pages because it is almost entirely fixed cost —
process architecture, a JavaScript heap, a compositor — while this
browser's grows with the document, from 13.2 MB to 18.0 MB as the page
goes from 4 KB to 51 KB. The 4.8 MB of growth is the DOM and the box
tree for 2,728 elements — about 1.5 KB per element across both. The
computed styles are no longer part of it: there are 24 of them, however
many elements the page has.

This is the same trade as the start-up figure above, seen from the other
side: what this browser does not have costs nothing to keep in memory.
It is not a claim that the engine is frugal with what it does build.

## Build

| | |
|---|---|
| Source | 20,984 lines of Festina across `browser.f` and `src/` |
| Compile | 11.6 s, whole program, no incremental build |
| Binary | 2.6 MB, linking Cairo, X11, libjpeg, mbedTLS and libc |

Against Chromium, whose binary this browser is compared with everywhere
else in this file:

| | Bytes |
|---|---|
| This browser, the whole program | 2,627,888 |
| This browser, all `.f` source | 757,635 |
| Chromium, main executable only | 463,227,992 |
| Chromium, whole install tree | 624,734,779 |

**The binary is about 176 times smaller than Chromium's executable
alone**, and 238 times smaller than the tree it ships in. The comparison
flatters this browser and should be read with that in mind: what is
absent from the 2.6 MB — a JavaScript engine, a compositor, a sandbox,
a network stack, an extension system, ICU — is most of what is in the
463 MB. The figure is a fair measure of *this* program's size and a poor
measure of how much cheaper a browser could be.

Of that 11.6 s, **3.4 s is the single generated map literal** holding the
standard's 2,231 named character references: a one-line program compiles
in 0.55 s, and the same program importing only that table takes 3.96 s.
The table is the right data structure — it looks up in constant time and
the runtime cost is nil — but a large literal is priced at compile time,
which is worth knowing before generating another one.

CSS Color 4's wider colour spaces — six colour functions, eight
predefined spaces and nineteen system colours — cost **13,696 bytes of
binary** (2,587,568 → 2,601,264) and 0.2 s of compile time, and nothing
at all at render time: the revision before them and the one with them,
rebuilt and run alternately in the same minutes, give 97 to 104 ms and
96 to 104 ms on `generated.html`. The conversions run only for a colour
function that is not `rgb()` or `hsl()`, which the benchmark pages do
not contain.

Column break control — `break-before`, `break-after`, `break-inside`,
`orphans` and `widows` — cost **4,384 bytes** (2,601,264 → 2,605,648)
and nothing at render time either, for the same reason: all of it is
inside `layoutColumns`, which a page with no multi-column container
never calls, and the five extra declarations are read once per distinct
computed style, which is 24 times on `generated.html`.

`clip-path` and `clip` cost **22,240 bytes** (2,605,648 → 2,627,888),
and again nothing at render time: `cascadeSawClip` is false on a page
with neither, so the painter never asks a box, and the two extra
declarations are read once per distinct computed style. What the feature
does cost is paid only by the boxes that use it, and it is not small: a
shape that is not a rectangle is blitted back one scanline at a time, so
a clipped box the height of the viewport is 600 image allocations where
a rectangle is one.

