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
  on a shared container mostly measure the neighbours. Best-of-5 does
  not rescue a contended machine, though, because all five runs are
  contended — which is what the control check below is for.
- **Both engines get the same canvas**, 800x600, and the rendering
  comparison is measured from inside both engines rather than by
  subtracting a start-up baseline. Both of those are easy to get wrong
  and this file has got both of them wrong — see below.
- **Memory** is peak resident set size from `tests/maxrss.py`, and
  **size** is `wc -c` on the binaries. Both are described where they
  are reported.
- **Pages**: the two examples in this repository plus two generated
  ones, so the large cases are reproducible without vendoring anyone
  else's HTML. `generated.html` is 40 sections, each a heading, a
  bordered card with a wrapping paragraph and a six-item list, and a
  twelve-row table: 2,728 elements, 51 KB, and no image, counter,
  grid, multi-column container, transform or form control in it.
  `features.html` is 24 sections of all six, with
  `features-plain.html` as its control — see "what the feature page's
  features cost".

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
| 800x600 | 136 ms | 480,000 |
| 800x2000 | 173 ms | 1,600,000 |
| 800x8000 | 369 ms | 6,400,000 |

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
| hello.html | 4 KB | 39 ms | 517 ms |
| css.html | 3 KB | 39 ms | 485 ms |
| generated.html | 51 KB | 138 ms | 533 ms |
| features.html | 60 KB | 123 ms | 473 ms |

The last row comes from a later run of the same day, which is why
Chromium reads 473 there against 485 to 533 above: that 60 ms is the
start-up spread this section is about, on a browser whose engine did
the same work in both.

Chromium's column here moved by 40 ms between two runs an hour apart on
an idle machine, and ours by 8, while the rendering table below held to
within a millisecond. That is what start-up costs a measurement: this
table is a statement about the command, and the ratios in it are not
worth taking.

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

Both figures in the large row are the middle of eight best-of-5 samples
rather than one run of five, because one run of five is not enough here:
see the spread below.

| Page | Size | This browser | Chromium | Ratio |
|---|---|---|---|---|
| hello.html | 4 KB | 11 ms | 1.1 ms | 10x |
| css.html | 3 KB | 11 ms | 0.9 ms | 12x |
| generated.html | 51 KB | 101 ms | 26.0 ms | **3.9x** |
| features.html | 60 KB | 85 ms | 21.8 ms | **3.9x** |

The feature page is larger in bytes and smaller in elements — 1,688
against 2,728 — which is why it renders faster than the page above it
while landing on the same ratio. Its row is one run rather than the
middle of eight; the run's control qualified at 8.1%.

**Chromium renders the 51 KB page about four times faster**, and the gap
is wider on small pages because a fixed cost of about 10 ms has nothing
to amortize against. The cascade and layout are where it lives; the
section after next says where inside them.

Neither column is one number. Eight best-of-5 samples of Chromium taken
back to back on an idle machine give 25.3, 25.6, 25.6, 25.9, 26.1, 26.1,
27.4 and 28.8 ms; eight of this browser give 99, 100, 101, 101, 102,
103, 103 and 104. Sampled that way each is tight — 3% below to 11% above
26.0, and about 2% either side of 101 — but a whole `tests/bench.sh` run,
which reaches this table after a dozen Chromium launches and several
hundred renders, has put our row at 98 on one occasion and 110 on
another. So the row records the middle of the samples, and a difference
under about 10% between two runs of this table is the machine.

Chromium's own row is also the control, and that is what its spread is
for. A run whose control falls
outside 15% of 26.0 is measuring the machine rather than either engine,
and `tests/bench.sh` now says so and exits non-zero rather than leaving
the reader to notice: the run that prompted it reported 30.4 ms, which
is 17% out, and printed without comment beside a table that looked
ordinary. `CONTROL_MS` and `CONTROL_TOLERANCE` override it, and a new
reference browser is a new control rather than a bad run.

Four of our 101 ms are the preload scanner's worker threads taxing every
allocation in the process, on a page that prefetches nothing — see
"what the preload scanner is worth" below. The movement from the 93 ms
this file carried before is the machine, not the code: the previous
revision, rebuilt and run alternately with this one in the same
minutes, gives 97 to 104 ms against this one's 96 to 104. Chromium's
own row is the control — 26.0 ms today against 25.3 ms then — and it
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
| generated.html | 51 KB | 8 ms | 2.2 ms |
| features.html | 60 KB | 6 ms | 1.5 ms |

**Between two and four times slower** on the large page. Ours is 8 ms
run after run; Chromium's has been measured between 2.1 and 3.9 ms
across runs, so a single ratio would be reporting that spread rather
than a difference — the row gives the run this table came from. Call it
6 MB/s against 13 to 25. For a tokenizer and tree builder written in a
young language against one of the most optimized parsers in software
that is a reasonable place to be, and at 8 ms of a 101 ms render it is
not where the time goes.

## Where the time actually goes

`generated.html` at 800x600, 2,728 elements:

| Phase | Time |
|---|---|
| fetch (local file) | 0 ms |
| parse | 9 ms |
| stylesheets | 1 ms |
| images | 0 ms |
| cascade | 35 ms |
| layout | 56 ms |
| paint | 8 ms |

Of the 101 ms before painting, the cascade and layout are 91 — **90%**.
Parsing is 9%, and paint, once it is not also encoding six megapixels,
is 8 ms. Chromium does the first five phases in 26.0 ms against our 101;
the whole gap is here, and **layout is the larger half of it**. The
`images` row is zero because this page has no image and no longer walks
its tree looking for one — see below.

Inside the cascade: 8,578 selector tests produce 11,614 matched
declarations across 2,728 elements. Five consecutive runs put collecting
them at 6 to 16 ms, applying at 14 to 17 and computing at 3 to 7 — the
sub-phase timers are noisier than the phase totals they add up to, so
read them as proportions and not as figures. Computing is the small one
because only **24 distinct styles** are computed for the 2,728 elements
and the rest are handed a style a previous element already produced;
it is still the phase that grows with every property implemented.

Inside layout: 11,564 text measurements, of which 620 miss the width
cache and reach Cairo (7 to 9 ms across those runs); building the box
tree is 21 to 23 ms and inline placement 8 to 14.

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
| conic gradients | **12 ms** | **61 ms** |

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

A conic sweep costs about what the angled linear one does, and for the
same reason: both draw one rectangle per band per row. Its wedges are
found by arithmetic rather than by searching — a ray's crossing of a row
is one multiply once its tangent is known — so the sweep is not paying
for an `atan2` per pixel, which is what the obvious implementation
costs.

Both figures are measured at 800x600, which is the viewport, so most of
the 4,080-pixel-tall page is culled. A page whose angled gradients are
all on screen pays more.

## What the feature page's features cost

`generated.html` is headings, paragraphs, lists and tables. It has no
`<img>`, no counter, no grid, no multi-column container, no transform
and no form control, so six features landed whose code none of its
2,728 elements reaches and whose only number in this file was a size in
bytes. `features.html` is the second page, measured beside the first
rather than in place of it: replacing it would throw away every figure
above, because a new page is a new control the same way a new reference
browser is.

It is 24 sections of 1,688 elements — a two-area named grid and a
three-column grid of figures, four images a section at a size that
makes `object-fit` do work, counters on the headings and on the step
lists, rotated and scaled inline badges, a three-column multi-column
block, and a form row of checkboxes, radios, a `field-sizing: content`
text input and a button.

`features-plain.html` is its control: the same markup, the same element
count, the same image, and a stylesheet that turns the grids into
blocks, the multi-column containers into one column, the transforms
into `none`, the generated counters into no generated content,
`object-fit` back to its initial value and the form controls out of
being painted as form controls. What separates the two rows is those
features doing their work.

| Page | Cascade | Layout | Paint | End to end |
|---|---|---|---|---|
| features off (the control) | 24 ms | 44 ms | 6 ms | 114 ms |
| features on | 26 ms | 50 ms | 7 ms | **124 ms** |

**About 10 ms, and most of it is layout.** A difference between two
numbers near 120 is the shape this file has got wrong before, so both
terms' spreads are here and not the difference alone. Eight alternating
best-of-3 samples give the control at 113, 115, 115, 116, 116, 117, 118
and 122 ms end to end against the feature page's 124, 125, 125, 125,
126, 126, 127 and 127 — two series that do not overlap. Per phase the
separation is cleaner still: layout 44 to 45 against 50 to 51, cascade
24 to 25 against 26 to 27, paint 6 to 7 against 7 to 8. The end-to-end
table above reads 123 ms for the same page in the same run, one below
the best of these samples, which is the size of the noise at this
resolution.

The image is in both columns and therefore in neither difference: a
stylesheet can turn a grid into a block but it cannot un-write an
`<img>`, so both pages fetch and decode the same PNG. That cost is in
the phase list instead — `images: 4 ms` here against 0 on
`generated.html`. It read 2 ms there when this page was first measured,
on a document with no image in it at all, which is the next section.

What the page cannot do is attribute the 10 ms to any one feature.
Turning them off one at a time would take six more control pages; the
honest reading is that this is what a page of this shape pays for all
of them together, against nothing at all before.

### The page is asked whether it still exercises what it claims to

A benchmark page that has quietly stopped exercising a feature reads
exactly like a feature that costs nothing, which is the failure this
project keeps finding in its instruments. So
`tests/featurepage.py --verify` renders the page, renders it again with
each feature turned off by an appended rule, and requires the pixels or
the document height to move; `tests/bench.sh` runs it before any of the
tables and fails the run when something is dead.

It caught two dead features on the first version of the page, before
any number here was recorded. The form controls sat below the probe's
canvas, so turning them off changed nothing it could see. And the
image's natural size was its box's size, which makes `fill`, `cover`
and `contain` paint identical pixels — `object-fit` was in the
stylesheet and in none of the measurements. The image is 120x60 in a
96x64 box now, and the probe's canvas is 3,000 pixels tall.

## What looking for an image cost the pages that have none

The first thing the second page measured was not a feature. Reading its
phase list beside `generated.html`'s showed `images: 2 ms` on a document
with no `<img>` in it: the two milliseconds were a walk of 2,728
elements finding nothing. Two more walks went unreported beside it,
because resolving `<iframe>` and `<frame>` is not a timed phase and
searched the whole tree for each.

`newElement` is the one place a tagged node is made, so it can answer
"is there an image in this registry" and "is there a frame" for the cost
of a comparison it makes once per element, and the three walks are
skipped on a document that has neither. Six alternating best-of-3
samples of the revision before it against this one, in the same minutes:

| | Best | Samples |
|---|---|---|
| before | 136 ms | 136, 136, 137, 138, 138, 150 |
| after | 133 ms | 133, 133, 133, 134, 134, 134 |

**About 3 ms**, and the series do not overlap: the worst reading after
is better than the best reading before. The parse, stylesheet, cascade
and layout phases do not move at all — none of the three walks is inside
them — so the rendering table above is unaffected and this is entirely
in what the command takes end to end. The binary is 80 bytes larger.

That is a small number by itself. What makes it worth writing down is
that it was invisible for as long as the only large page had no image
on it: the cost of looking for something is paid by the pages that do
not have it, which is the failure the rule about features costing
nothing is meant to catch, and it took a second page to see it.

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
| features.html | 60 KB | 17.3 MB | 195.1 MB |

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
| Source | 23,281 lines of Festina across `browser.f` and `src/` |
| Compile | 11.6 s, whole program, no incremental build |
| Binary | 2.6 MB, linking Cairo, X11, libjpeg, mbedTLS and libc |

Against Chromium, whose binary this browser is compared with everywhere
else in this file:

| | Bytes |
|---|---|
| This browser, the whole program | 2,737,648 |
| This browser, all `.f` source | 899,340 |
| Chromium, main executable only | 463,227,992 |
| Chromium, whole install tree | 624,734,779 |

**The binary is about 171 times smaller than Chromium's executable
alone**, and 233 times smaller than the tree it ships in. The comparison
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

`shape-outside` and `shape-margin` cost **4,744 bytes**
(2,627,888 → 2,632,632) and nothing at render time: `cascadeSawShape` is
false on a page with neither, so no float grows a shape and the edge
scan is the rectangle test it always was. Where a shape does exist the
scan is arithmetic rather than a loop over rows — an ellipse's widest
row in a band is the row in it nearest the centre, and a polygon's is a
band end or a vertex — so a shaped float costs about what an unshaped
one does.

`column-span: all` costs **4,216 bytes** (2,632,632 → 2,636,848) and
nothing at render time. A container with no spanner takes one run
through the same code that laid out every child before, and a document
with no multi-column container never reaches it at all.

Display 3's two corrections cost **80 bytes** (2,636,848 → 2,636,928):
`display: contents` is a branch in the one place a box tree is built
from children, and refusing an invalid `display` keyword is a test
where declarations are applied.

**Media Queries 3 and 4 cost 9,080 bytes** (2,636,928 → 2,646,008)
across the three changes that make up the pair: the Level 3 feature set
4,304, Level 4's range syntax and conditions 4,736, and Level 4's own
features 40 — the last being that small because answering `scripting:
none` is a string in a table beside the others. None of it is reached
unless a sheet has an `@media`, and it runs once per such rule at parse
time rather than per element.

`@layer` costs **4,808 bytes** (2,646,008 → 2,650,816) and nothing per
element: a layer index rides in the field the cascade weight already
packed an origin into, so a page with no `@layer` compares the same
integer it compared before.

`color-mix()` costs **9,680 bytes** (2,650,816 → 2,660,496) and the
relative colour syntax **17,512** (2,660,496 → 2,678,008) — between
them the largest single addition on this list, because each of the
eleven interpolation spaces needs a conversion in both directions and
the relative form adds an expression evaluator over the channels. Both
are parse-time only: a colour is a packed integer by the time anything
paints it.

`background-position-x` and `background-position-y` cost **56 bytes**
(2,686,488 → 2,686,544): the shorthand was already parsed into the two
fields, so the change is which names reach them and when.

`color-scheme` costs **248 bytes** (2,686,544 → 2,686,792) and nothing
at render time. A page that never declares it skips the resolution
behind a per-document flag, and the second system-colour table is
consulted only by a name that is already a system colour, so a page with
none of them never asks. `generated.html` renders in 98 ms with it in,
against a recorded 101 whose spread is 99 to 104.

The float shrink-to-fit correction and per-axis size containment cost
**88 bytes** between them (2,686,792 → 2,686,880), both being a
predicate where there was a wider condition before.

**`@container` costs 14,272 bytes** (2,686,880 → 2,701,152) and, for a
page that uses it, a second layout — the document is laid out, the
queries are answered from that box tree, and the cascade and layout run
again, repeating while any answer changes. A page whose sheets never say
`@container` pays one boolean once per document and never reaches any of
it: `generated.html` renders in 102 ms with the feature in, against a
recorded 101 whose spread is 99 to 104, and the run's own control
qualified at 4.6%.

`content: url()` costs **5,024 bytes** (2,701,280 → 2,706,304) and
nothing per page to a document whose generated content names no image:
one boolean decides whether the tree is walked for content images, and
a `content` with no url in it never builds the arrays a run would need.
The revision before it, rebuilt and sampled alternately with this one in
the same minutes, gives 100, 104, 102, 101, 103, 106, 103, 100, 103,
100, 102 and 102 ms against this one's 113, 102, 106, 101, 105, 106,
108, 106, 101, 103, 102 and 104 — 100 to 106 against 101 to 113, two
series that overlap, with the best of each a millisecond apart. The
run's own control qualified at 5.0%.

The `2,701,152` this table carried before that measurement was two
commits stale: `direction` and `dir` had taken the binary to 2,701,280
without an entry here. The cost above is measured against that, not
against the number that was written down.

`aspect-ratio` costs **4,360 bytes** (2,706,304 → 2,710,664) and, to a
page that never declares it, one boolean read off the style the box is
already holding: the width path asks it before working out whether a
declared height fixes the box, and the height path asks it where a
declared height would have been. No flag, no second lookup, nothing per
document.

The automatic-grid-row fix costs **nothing the linker records** — the
binary is the same 2,710,664 with it and without — and, for a grid, one
extra layout of each item that decides an automatic row. A grid whose
rows are all declared measures none of them, and a page with no grid on
it never reaches the loop.

`counter-set`, with the `counter-reset` scoping correction beside it,
costs **4,368 bytes** (2,710,664 → 2,715,032) and nothing at all to a
page without counters: the benchmark page names none, so `anyCounters`
is false and neither the scope test a reset now makes nor the pop an
element now does is reached. Ten alternating samples each give 101 to
109 ms on both sides, with the same best — which is what "nothing at
all" should look like, and is the reason the page was checked for
counters before the numbers were read.

`grid-template-areas` and named lines cost **9,368 bytes**
(2,715,032 → 2,724,400) and nothing to a page without a grid. The empty
answer is shared rather than built afresh, which is the part worth
saying: `parseTrackList` runs for four properties on every distinct
style, almost always for a property the page never declared, and it was
allocating two arrays each time before the check that finds there is
nothing to parse. It hands back one shared empty list instead, and the
first bracketed name swaps in arrays of its own. Ten alternating samples
give 101 to 105 ms against the revision before it at 101 to 110, the
same best on each side, on a run whose control came in at 0.4%.

`object-view-box` costs **8,776 bytes** (2,724,400 → 2,733,176) and,
at render time, one field test per image box — and `generated.html`
carries no `<img>` at all, so on the benchmark page it is not reached
even once. That is worth stating rather than implying: the run put the
page at 98 ms against a recorded 101 whose spread is 99 to 104, and ten
alternating samples give 99 to 115 against the revision before it at
101 to 106. The new side's best is two milliseconds under the old
side's, which is a good run rather than a faster browser: nothing that
changed executes here.

`column-fill` and `hyphenate-character` cost **64 bytes** between them
(2,733,176 → 2,733,240), which is a boolean and a text field plus two
predicates inside conditions that already existed. The benchmark page
has neither a multi-column container nor a soft hyphen, so neither is
reached; the run put it at 99 ms and eight alternating samples give 98
to 121 against the revision before it at 100 to 117 — two series with
an outlier apiece and overlapping bests, which is the machine rather
than the change.

`transform-box` costs **no bytes the linker records**: the binary is
2,733,240 with it and without. That number was checked rather than
taken, because an unchanged size is also what a stale build looks like
— the two binaries hash differently (`c47a9923` against `5322c080`), so
they are different programs that happen to round to the same size. The
benchmark page has no transform on it, so nothing here is reached:
eight alternating samples give 100 to 106 ms against 97 to 104, two
overlapping series whose difference is the machine.

`conic-gradient()` costs **8,632 bytes** (2,746,648 → 2,755,280) and
nothing at all to a page without one: the painter is reached only
through the gradient dispatch, which asks the style it is already
holding.

`repeat(auto-fill)`, `repeat(auto-fit)` and dense packing cost **4,656
bytes** (2,741,992 → 2,746,648) and no measurable time: five alternating
best-of-3 samples of `features.html` give 121 to 124 ms before and 121
to 123 after, the same best on each side. Nothing new runs on a grid
that does not use them — the expansion returns the template's own list
untouched when it holds no auto-repeat, and the collapse array is a
shared empty one.

The grid track sizing functions cost **4,264 bytes** (2,737,728 →
2,741,992). What they cost in time this file cannot say at this size,
and the reason is worth the line: `features.html`, which has 48 grid
containers on it, goes from 123 to 125 ms before to 125 to 126 after,
six alternating best-of-3 samples apiece — and `generated.html`, which
has no grid at all and therefore runs not one line of the new code,
moves by the same 2 ms in the same direction, 128 to 131 against 130 to
134. A difference a page that cannot have it shows just as clearly is
the binary's own layout, or the machine, and not the feature.

`content: url()` on an ordinary element costs **no bytes the linker
records**: 2,737,728 with it and without. The two binaries hash
differently (`756c6fe5` against `e2a09826`), so that is two programs
rounding to the same size rather than a stale build. Its cost at run
time is one map read per *distinct* computed style — 24 on the benchmark
page, not 2,728 — and six alternating best-of-3 samples give 130 to
133 ms against 130 to 134 for the revision before it: two series that
overlap almost entirely, which is what a feature nothing on the page
uses should look like.

`appearance`, `accent-color` and `field-sizing` cost **4,408 bytes**
(2,733,240 → 2,737,648) between them. The benchmark page carries no form
control, so none of it is reached there: eight alternating samples give
99 to 104 ms against the revision before it at 99 to 108, the same best
on each side.

**That was the sixth feature to land whose cost `generated.html` could
not show**, each of the six measured above in bytes and controlled
against a timing that never reached it. `generated.html` exercises
block and inline layout over 2,728 elements, the cascade and text,
which is what its headline number measures and what makes that number
sound; it has no `<img>`, no counters, no grid, no multi-column
container, no transform and no form control. `features.html` has all
six and is measured beside it, so a run reaches them — see "what the
feature page's features cost" above for what they come to together.

Together the earlier two leave `generated.html` where it was. The revision before
both, rebuilt and sampled alternately with this one in the same minutes,
gives 107, 104, 102, 106, 102, 103, 123, 103, 103 and 105 ms against
this one's 101, 103, 105, 103, 103, 105, 103, 101, 102 and 105 — the
best of each a millisecond apart, and the one reading over 110 on the
side that does not have the features. The run's own control qualified at
4.2%.

CSS Nesting costs **8,480 bytes** (2,678,008 → 2,686,488) and one
`memchr` per rule on a page that does not nest. A rule body with no `{`
and no `@` in it cannot contain a nested rule, so it takes the path it
always took. The revision before it, rebuilt and sampled alternately
with this one in the same minutes, gives 100, 102, 102 and 112 ms
against this one's 99, 101, 101 and 103 — two series that overlap, with
the higher reading on the side that does not have the feature.

