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

## A machine this table cannot be refreshed from, 2026-09-25

`tests/bench.sh` was run twice on an idle machine and its control failed
both times: Chromium rendered `generated.html` in 20.4 and then 20.2 ms
against the 26.0 this file records, 21.5% and 22.3% out, past the 15%
the run allows. Asked directly, six best-of-5 samples on an idle machine
give **20.1, 20.2, 21.0, 21.2, 21.9 and 22.0** ms -- a 1.9 ms spread
around 21, which is tight, so this is not a contended run.

**The reference browser did not change**: it is Chromium 141.0.7390.37,
the same build named at the top of this file and by the property audit.
So `CONTROL_MS` stays at 26.0 and the tolerance stays at 15%. What moved
is the machine, and the control is doing exactly the job it was written
for -- the numbers from those two runs are not in this file, and the
table above still records 2026-09-16.

What a machine like this *can* still measure honestly is a **paired**
comparison: two binaries built from two revisions, run alternately in
the same minutes on the same hardware, where the machine's own speed
cancels. That is what `tests/bench.sh`'s absolute table is not and what
the paired phase comparison is. A reading of this table's kind has to
wait for a machine whose control lands.

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
engine, a compositor and a network stack, against a 2.8 MB native binary
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
| hello.html | 4 KB | 38 ms | 450 ms |
| css.html | 3 KB | 37 ms | 462 ms |
| generated.html | 51 KB | 151 ms | 494 ms |
| features.html | 76 KB | 177 ms | 497 ms |

Chromium's four figures span 450 to 497 in one run of one script on an
idle machine, on pages whose engine work differs by a factor of four.
That 47 ms is the start-up spread this section is about.

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
| hello.html | 4 KB | 12 ms | 1.2 ms | 10x |
| css.html | 3 KB | 12 ms | 1.0 ms | 12x |
| generated.html | 51 KB | 120 ms | 24.7 ms | **4.9x** |
| features.html | 76 KB | 128 ms | 26.9 ms | **4.8x** |

The feature page is 1,928 elements against 2,728 and carries more of
them in grids, multi-column blocks and images, which is why it lands
beside the page above it rather than below. The run's control qualified
at 5.0%.

**Our column moved from 101 to 120 on `generated.html` since this table
was last written, and it is the machine rather than the code.** The
revision this file recorded 101 for, rebuilt and paired against the
current one in the same minutes, reads the same 120: parse, cascade and
layout come out at 9, 40 and 71 ms on both, with the paired difference
a median of zero in each phase and in both orders. A comparison against
a number written down on another day is measuring the day, which is why
the rule above asks for the old revision beside the new one.

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
| generated.html | 51 KB | 8 ms | 1.9 ms |
| features.html | 76 KB | 7 ms | 1.8 ms |

**Between two and four times slower** on the large page. Ours is 8 ms
run after run; Chromium's has been measured between 2.1 and 3.9 ms
across runs, so a single ratio would be reporting that spread rather
than a difference — the row gives the run this table came from. Call it
6 MB/s against 13 to 25. For a tokenizer and tree builder written in a
young language against one of the most optimized parsers in software
that is a reasonable place to be, and at 8 ms of a 120 ms render it is
not where the time goes.

## Where the time actually goes

`generated.html` at 800x600, 2,728 elements:

| Phase | Time |
|---|---|
| fetch (local file) | 0 ms |
| parse | 9 ms |
| stylesheets | 2 ms |
| images | 0 ms |
| cascade | 39 ms |
| layout | 70 ms |
| paint | 19 ms |

Of the 120 ms before painting, the cascade and layout are 109 — **91%**.
Parsing is 8%, and paint, once it is not also encoding six megapixels,
is 19 ms. Chromium does the first five phases in 24.7 ms against our 120;
the whole gap is here, and **layout is the larger half of it**. The
`images` row is zero because this page has no image and no longer walks
its tree looking for one — see below.

Inside the cascade: 8,578 selector tests produce 11,614 matched
declarations across 2,728 elements. Five consecutive runs put collecting
them at 6 to 16 ms, applying at 14 to 17 and computing at 3 to 9 — the
sub-phase timers are noisier than the phase totals they add up to, so
read them as proportions and not as figures. Computing is the small one
because only **24 distinct styles** are computed for the 2,728 elements
and the rest are handed a style a previous element already produced;
it is still the phase that grows with every property implemented.

Inside layout: 11,564 text measurements, of which 620 miss the width
cache and reach Cairo (7 to 9 ms across those runs); building the box
tree is 21 to 25 ms and inline placement 8 to 14.

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
| gradients, at 37 degrees | **14 ms** | **63 ms** |
| conic gradients | **13 ms** | **64 ms** |

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

It is 24 sections of 1,928 elements — a two-area named grid and a
three-column grid of figures, four images a section at a size that
makes `object-fit` do work, counters on the headings and on the step
lists, rotated and scaled inline badges, a three-column multi-column
block, a form row of checkboxes, radios, a `field-sizing: content`
text input and a button, a small-caps paragraph, a negative-margin
pair, a `z-index: -1` stack, and a float with two paragraphs beside
it.

`features-plain.html` is its control: the same markup, the same element
count, the same image, and a stylesheet that turns the grids into
blocks, the multi-column containers into one column, the transforms
into `none`, the generated counters into no generated content,
`object-fit` back to its initial value and the form controls out of
being painted as form controls. What separates the two rows is those
features doing their work.

| Page | Cascade | Layout | Paint | End to end |
|---|---|---|---|---|
| features off (the control) | 32 ms | 70 ms | 13 ms | 158 ms |
| features on | 36 ms | 82 ms | 17 ms | **176 ms** |

**About 18 ms, and most of it is layout.** A difference between two
numbers near 170 is the shape this file has got wrong before, so both
terms are phase timers read from inside the engine rather than two
whole commands subtracted. Per phase the separation is 70 against 82 of
layout, 32 against 36 of cascade and 13 against 17 of paint, on two
pages of the same element count.

The page has grown since the rows above it were written — it carries
four features it did not, one of them the float that makes CSS2 §9.9's
step 4 run at all — so this pair is a new baseline rather than a
movement from the 114 and 124 ms it used to read.

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

## What one `int` on `Style` costs, and the control that proved it

CSS Motion Path was first written the way the anchor properties are:
five values in a side table, and one `int` on `Style` indexing it. The
benchmark page has no `offset-path` anywhere on it, so the index is zero
on every style and nothing reads it.

Twenty-five alternating pairs against the rebuilt parent, layout and
paint both, 2026-09-18:

| | Min | Median | Max | Paired median | Paired mean | Slower in |
|---|---|---|---|---|---|---|
| layout, parent | 58 ms | 61 ms | 65 ms | | | |
| layout, with the field | 59 ms | 61 ms | 66 ms | +1 ms | **+1.08 ms** | 14 of 25 |
| paint, parent | 8 ms | 9 ms | 11 ms | | | |
| paint, with the field | 8 ms | 9 ms | 10 ms | 0 ms | -0.04 ms | 5 of 25 |

Fourteen of twenty-five is barely more than half, and a median of +1 ms
on a 61 ms phase is the sort of number that gets waved through. **So the
same script was run with the parent binary against a copy of itself**,
which is the only way to know what this method's own noise is:

| | Paired median | Paired mean | B slower in |
|---|---|---|---|
| layout, parent against parent | 0 ms | -0.16 ms | 6 of 25 |
| paint, parent against parent | 0 ms | -0.24 ms | 4 of 25 |

Against a floor of -0.16 and 6 of 25, +1.08 and 14 of 25 is real. It is
the same finding `corner-shape` produced at four times the size -- four
floats on `Style` cost 2 ms -- and this is what the small end of it
looks like: one field, one machine word, one millisecond, and no test
anywhere that would have objected.

The index moved off `Style` into a map keyed by the computed style's own
serial, which is the right grain anyway: a computed style is shared
between every element that matched the same declarations, and the map is
only ever read behind `anyOffsetPath`. Re-measured the same way:

| | Min | Median | Max | Paired median | Slower in |
|---|---|---|---|---|---|
| layout, parent | 58 ms | 60 ms | 64 ms | | |
| layout, after the move | 58 ms | 60 ms | 82 ms | 0 ms | 7 of 25 |
| paint, after the move | 8 ms | 9 ms | 9 ms | 0 ms | 4 of 25 |

Seven of twenty-five against the control's six. The paired differences
are every one of them in [-3, +2] except a single +24, which is the 82 ms
sample and a hiccup rather than a cost; dropping that one pair leaves a
mean of -0.33 ms, which is the control's number. Reported with the
outlier in the table rather than trimmed out of it, because a maximum
that far from the median is the sort of thing a reader should get to
judge.

## What `position-visibility` cost, and the measurement that missed it

`position-visibility` puts a test at the top of `paintBox`, which every
painted box on every page reaches. The first paired A/B said median 0,
mean -0.40, slower in 11 of 25 pairs -- and measured nothing at all,
because the harness these comparisons use sums **parse, stylesheets,
cascade and layout**, and this change is in none of them. Paint is
outside that sum.

Asked of the paint phase, over the same twenty-five alternating samples:

| | Min | Median | Max | Slower in |
|---|---|---|---|---|
| before | 8 ms | 9 ms | 10 ms | |
| after | 8 ms | 9 ms | 13 ms | 8 of 25 pairs |

Median 0, paired mean +0.36 ms on a 9 ms phase. Free, for the reason
the code is written that way: a document that hides no anchored box
never sets `anyAnchorHidden`, so the test is one boolean that fails
immediately.

The lesson is the one this file keeps relearning in new costumes. The
first measurement was not wrong about its own numbers; it was answering
a question nobody asked, and it answered it confidently. A paired A/B is
only as good as its agreement with the phase the change is in, and
nothing in its output says which phase that is -- the same shape as a
property row that computes to its initial value, or a
`getComputedStyle` probe of a paint-time property.

## What sorting the position-try candidates cost

`position-try-order` builds the candidate list and sorts it, which
sounds like more work than the retry loop it replaced a branch in. It is
not: the list is built only for a box that names an anchor and declares
either fallbacks or an order, so on every other page neither the build
nor the sort is reached. Twenty-five alternating samples against the
revision before it: median -1 ms, paired mean -2.08, slower in 8 of 25
pairs.

The sort itself is a selection sort over a list that is a handful of
entries long, which is the right shape here: an allocation-free sort
over four items beats anything cleverer, and it is stable, so candidates
offering equal room keep their written order.

## What the position-try retry loop cost

The retry loop lays an anchored box out, tests it against its containing
block and tries the next candidate. It runs only for a box that both
names an anchor and overflows, so on a page with neither it is a
comparison that fails immediately. Twenty-five alternating samples
against the revision before it: median 0 ms, paired mean -0.64, slower
in 12 of 25 pairs.

The containing block it tests against is tracked down the recursion
rather than stored on each box, for the reason the section below
measured: a field on a per-box record costs more than a parameter does.

## What anchor positioning cost, with the lesson below applied first

CSS Anchor Positioning adds two walks of the finished box tree -- one to
collect the anchors' rectangles, one to place the boxes that name them
-- and seven properties' worth of data per element. Written the obvious
way that would be seven fields on `Style`, which the section below
measures at two milliseconds for four.

So it was not written that way. `Style` carries **one `int`**, an index
into a side table that only elements mentioning an anchor appear in, and
both walks sit behind `anyAnchorName`, which no page that never names an
anchor sets. Twenty-five alternating samples against the revision
before it:

| | Min | Median | Max | Slower in |
|---|---|---|---|---|
| before | 102 ms | 105 ms | 134 ms | |
| after | 104 ms | 106 ms | 115 ms | 13 of 25 pairs |

Paired mean -0.20 ms. Thirteen of twenty-five is what a coin gives, and
the feature is free to the pages that do not use it -- which is the
result the section below had to be paid for once to learn.

## What four fields on `Style` cost, and why `corner-shape` is a bitfield

`corner-shape` was written with the obvious representation: one `float`
per corner on `Style`, holding the superellipse exponent that corner is
drawn with. The suite passed, the new render suite matched Chromium's
corner profile row for row, and the paired benchmark said it cost **2 ms
on `generated.html`** -- a page with no `corner-shape` in it and no
corner shaped at all.

Twenty-five alternating samples, parse through layout, at 800x600:

| | Min | Median | Max | Slower in |
|---|---|---|---|---|
| before | 102 ms | 105 ms | 107 ms | |
| four floats on `Style` | 104 ms | 106 ms | 111 ms | 21 of 25 pairs |
| four codes in one int | 103 ms | 104 ms | 109 ms | 28 of 50 pairs |

Twenty-one pairs of twenty-five is not a coin. The phase timings said
where it was and where it was not:

| | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| before | 9 | 1 | 36 | 57-58 | 8 |
| four floats | 9 | 2 | 36 | 59-60 | 9 |

All of it in **layout**, none in the cascade that parses the property or
the paint that draws it. That rules out every line the feature runs,
because layout does not run any of them.

The cause is the struct, not the code. Compiling the revision *before*
`corner-shape` with four `float` fields added to `Style` and **never
read** reproduces it exactly: layout 59, 61, 61 against that same
revision's 57-58. `Style` is dereferenced once per box throughout
layout, and `generated.html` has 2,728 boxes sharing 24 of them, so
thirty-two bytes of growth moves the fields a box reads apart from one
another.

Padding the same revision with one and with two `int` fields costs
nothing -- 57, 58, 59, and 58, 59, 59 -- so the threshold is somewhere
between eight bytes and thirty-two, not at any growth at all. The four
exponents are therefore packed into one `int`, six bits a corner, with
codes past the six keywords indexing a per-page list of the exponents
`superellipse()` named. Re-measured, the new binary is slower in 28 of
50 paired samples, which is within one standard deviation of the 25 a
coin gives, and the median difference is 1 ms.

What makes this worth writing down is that **no test could have caught
it**. Every suite passed on the slow version; the new feature's own
render suite matched Chromium exactly. The only instrument that noticed
was a paired A/B against the previous revision, and the only reason the
cause was findable was that the phase timers put the cost in a phase the
feature does not touch. A readable four-member struct is the right
default everywhere `Style` is not read once per box.

## What UAX #9's explicit rules cost a page with no bidi in it

The explicit half of the bidirectional algorithm reaches every page,
because the question "is there anything here that could reorder" is
asked of every text box, and the nine formatting characters are now part
of that question. That is a test inside a loop over every character of
the document, which is the shape the rule about features costing nothing
exists to catch.

Two things keep it off the pages that do not use it. `bidiClass` returns
for ASCII before it reaches the nine, and asks for them behind a single
range test rather than nine equalities; and `bidiNeedsReorder` asks
`c >= BIDI_LRE` once, because every formatting class is numbered above
every ordinary one.

The run of 2026-09-18 read 104 ms on `generated.html` where the table
above records 101, which on its own would look like a 3 ms regression.
It is not: the revision before this one, rebuilt and run in the same
minutes on the same machine, reads the same. Twenty-five alternating
samples of the two binaries, parse through layout, `generated.html` at
800x600:

| | Min | Median | Max |
|---|---|---|---|
| before (43731f7) | 104 ms | 107 ms | 120 ms |
| after (b7620bf) | 103 ms | 105 ms | 133 ms |
| paired, after less before | -7 ms | **-2 ms** | +13 ms |

The new binary is the slower one in 6 pairs of 25, and the paired mean
is -0.96 ms. The change costs nothing measurable, and the 3 ms is the
machine: Chromium's control row moved the other way on the same run,
24.6 ms against the 26.0 recorded, 5.4% and inside the 15% the script
allows. That the two engines drifted in opposite directions by similar
fractions is what a day's difference in machine state looks like, and it
is why the rendering table's large row is the middle of eight samples
rather than one run of five -- one run of five is what produced the 104.

## What the `@page` margin boxes cost the pages that have no `@page`

2026-09-22, same machine and script. The margin boxes reach a page
through two doors and no more: `splitPageBody`, which only
`parsePageRule` calls, and `paintPageMarginBoxes`, which the paginated
painter calls once per page behind `anyPageMarginBox`. Neither
benchmark page has an `@page` rule at all -- `grep -c @page` is 0 on
both -- so the expected cost is exactly nothing, and what the pairing
is really checking is whether anything leaked out of those two doors.

| generated.html | forward, parent first | reversed, candidate first |
|---|---|---|
| parse | +0, 11 of 25 | +0, 4 of 25 |
| cascade | **+1**, 13 of 25 | +0, 10 of 25 |
| layout | -2, 9 of 25 | +1, 13 of 25 |
| paint | -1, 5 of 25 | -1, 7 of 25 |

The cascade's forward +1 is the shape this file's own rule calls real
-- a forward millisecond against a reversed zero -- and here it is not,
which is worth writing down because the rule is a prompt to look at the
code rather than a verdict. The mean behind that median is **-0.48**,
the wrong sign for a cost, and the commit does not touch
`src/css/cascade.f` at all. The reading is noise wearing the pattern's
clothes; the rule's own instruction is that the question goes to the
code, and the code answers it.

`features.html`, forward: parse +0, cascade +0, layout -1, paint +0.

The whole-table run beside this one reads 118 ms on `generated.html`
and 99 on `features.html`, against the 101 and 85 recorded above, while
Chromium reads 23.7 against the 26.0 recorded -- the control passed at
8.8% of a 15% band. A machine that is 9% faster for Chromium and 17%
slower for this browser is not one measurement, so the table above is
not restated from it. The paired run is the comparison that holds: the
parent and the candidate were built and run in the same minutes, and
they read the same.

## What the negative-margin fix cost, and the page it cannot be measured on

2026-09-22, same machine and script. The change is one function call
where a `maxInt` was, on the path every block's margins already take.
On `generated.html`, which declares no negative margin, it reads
nothing -- every median 0 in both directions but a single -1 of layout.

**And `features.html` cannot answer the question at all**, which is the
entry's point. A negative margin was added to it for the usual reason,
so that the benchmark could see the feature -- and that makes the two
binaries lay out **different pages**. The old one drops the
`margin-top: -18px` on twenty-five boxes and the new one applies it, so
the new one has four hundred and fifty fewer pixels of document. Its
forward reading was +1 of paint against a reversed 0, the shape this
file calls real, and it is not a cost: it is two different documents
being timed.

That is a tension worth stating, because both rules are right and they
pull against each other. **A benchmark page has to exercise a feature
for the measurement to mean anything, and it must not change shape
between the two binaries for a paired reading to mean anything.** A
feature that only adds work -- a new property read, a new pass --
satisfies both, which is why it has not come up before. A feature that
*fixes the layout* cannot: the page that shows it working is the page
whose geometry moved.

So the cost of a layout fix is measured on a page the fix does not
touch, and the page that exercises it is kept for `--verify` and the
render suite, where a difference is the point rather than the noise.

## What a subgrid's contribution cost, and a page that exercises the guard

2026-09-22, same machine and script. Both benchmark pages render
byte-identically between the two binaries, so the pairing compares
code. `features.html` is the page that matters here: it has two grids
and **no subgrid**, which is exactly the path the change adds -- one
walk of the item list per axis per grid, finding nothing and handing
the list straight back.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| forward, parent then candidate | +0 | **-2** | **-1** | -1 |
| reversed, candidate then parent | +0 | **-1** | **-2** | -1 |
| `generated.html`, no grid at all | +0 | +0 | +0 | +0 |

The candidate reads faster in *both* directions on the page with
grids, which cannot be a difference between two binaries any more than
the §12.5 entry's -2 and -3 could; and the page with no grid reads flat
in every phase. Nothing to attribute, so no control was built.

Two things in this diff could have read as a cost and did not. The
placement pass moved out of `layoutGrid` into `gridPlaceItems`, turning
a hundred lines of inline code into a call, on a path every grid takes.
And the expansion allocates nothing on a grid without a subgrid,
because the walk that looks for one returns the caller's own list
rather than a copy -- which is the difference between a guard that
costs a comparison per item and one that costs an array.

## What resolving an unknown grid line name cost

2026-09-22, same machine and script. Both benchmark pages render
byte-identically between the two binaries -- neither uses a line name
the template does not declare -- so the pairing compares code.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| forward, parent then candidate | +0 | +0 | +0 | +0 |
| reversed, candidate then parent | +0 | **-1** | **-1** | **-1** |
| `generated.html`, no grid at all | +0 | +0 | -2 | +0 |

Nothing to read: every median is zero or negative, and the reversed
row's three -1s are the parent paying for running second, which is the
order effect this file has measured repeatedly on this machine. No
control was built, because the rule calls for one when a reading looks
like a cost and none does.

The reason is structural. The resolver runs once per placement edge of
a grid item that names one, and what it added is a counter in a loop
that already walked the template's names and one arithmetic expression
where it used to return 0. `parseGridLine` now walks its tokens rather
than indexing the first, which is once per declaration at cascade time.
A page with no grid on it never reaches any of it.

## What `range` and `fallback` cost

2026-09-22, same machine and script. `generated.html` is lists among
its headings and paragraphs, so it runs `counterStyleLabel` for every
marker on the page -- which is the function this change touches, and
the reason the benchmark can see the path even though no page here
declares a range of its own. Both pages render byte-identically between
the binaries, `cmp`-checked first.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| forward, parent then candidate | +0 | +0 | +0 | +0 |
| reversed | +0 | +0 | -2 | +0 |

Nothing to read: every median is zero but the reversed layout, which is
negative, and a change cannot make the parent slower. No control was
built, the rule calling for one when a reading looks like a cost.

The structure is why. `counterStyleLabel` gained one comparison on the
path it already took -- the range test was there, and what is new is
where it goes afterwards -- and the recursion it can now make is
bounded at four and reached only by a counter outside its style's
range, which the predefined styles put at 3999.

## What synthesised small caps cost, and a cascade millisecond from dead code

2026-09-22, same machine and script. **Neither benchmark page had a
`font-variant` on it**, so the pairing below measures what the feature
costs a page that does *not* use it -- which is the question this file's
own rule asks -- and the feature page gains a probe for it so the next
reading is not blind.

Both pages render byte-identically between the binaries, `cmp`-checked
before any timing.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| forward, parent then candidate, `features.html` | +0 | +0 | -1 | +0 |
| reversed | +0 | +0 | +1 | -1 |
| forward, `generated.html` | +0 | **+1** | **+1** | **+1** |
| reversed, `generated.html` | +0 | +0 | +0 | +0 |

`features.html` reads nothing: -1 forward against +1 reversed is the
order effect. `generated.html` reads +1 in three phases forward against
nothing reversed, which this file calls an order effect *plus* a
millisecond -- so a third binary was built.

The control is the parent recompiled with the six functions on the
measured path -- `asciiUpper`, the two that segment a run, the one that
sets an explicit size and the measurer -- under other names and **called
from nowhere**. It comes out 624 bytes above the parent.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| parent then control (dead code only) | +0 | **+1** | +0 | +0 |
| control then candidate | +0 | +0 | **+1** | +0 |

**The cascade millisecond is reproduced exactly by code that cannot
run, in a phase the dead code is not even in.** That is the sixth time
the control has disagreed with the parent here and the sixth time it
has been right. The paint reading vanishes against the control too.

What survives is +1 of layout against the control, with a mean of
**+0.12** -- a median of one on a 77 ms phase whose mean says nothing.
That is the floor this method reads at rather than an established cost,
and it is recorded as such. What the code actually adds to a page with
no small caps is one boolean test per `measureWidth` miss and one per
fragment painted, both behind `anySmallCaps`.

## What §12.5's spanning pass cost, and three binaries that would not add up

2026-09-22, same machine and script. `features.html` is the right page
for once and for a reason worth stating: `.wide` draws
`"pic note" "pic meta"`, so `.pic` **spans two rows** and the new code
runs on it -- but those rows already held the two lines beside it, so
the span asks for nothing and the page renders **byte-identically**
between the two binaries. The work happens and the document does not
move, which is exactly what the paired-benchmark rule wants and what a
layout fix usually cannot give.

Paired 25 times each way against the parent:

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| forward, parent then candidate | +0 | +1 | **+3** | +0 |
| reversed, candidate then parent | +0 | +1 | **+1** | +0 |

Both directions positive, which is the order effect: +3 and +1 split
into about +2 of order and about +1 that might be the code.

**`generated.html` has no grid on it at all**, so nothing in this diff
can execute there. Forward +1 of layout, reversed +0. That is the same
size as the residue above, from a page where the residue is known to be
nothing, and it is the floor this method reads at.

The control settles the rest. The parent recompiled with
`gridPlanSpanIncrease` under another name and called from nowhere comes
out at 3,082,288 bytes -- the candidate's size **exactly**, though the
diff also adds lines inside `gridSizeAxis` and `layoutGrid` that the
control cannot carry.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| control then candidate | +0 | +0 | **-2** | -1 |
| candidate then control | +0 | +0 | **-3** | +0 |
| parent then control (dead code only) | +0 | +0 | +0 | +1 |

The candidate reads **faster than the control in both directions**,
which cannot be a difference between them: a real one would come out
+n and -n. So the residue is not a property of the diff, the same
conclusion three binaries have forced here before, and the honest
answer is that no cost was established above the floor.

What the code does cost is structural rather than measured, and it is
worth naming because the measurement cannot see it. A page with no grid
never enters `layoutGrid`. A grid whose every item sits in one track
leaves `maxSpan` at 1 and the span loop never runs. A row-spanning item
is laid out an extra time only where one of the rows it spans is
intrinsic. What every grid now pays, spanning item or not, is three
`arr[bool]` pushes per track and one comparison per item -- and that is
below anything this pairing can read.

## What distributing a grid's tracks cost, and a control that read a whole millisecond of nothing

2026-09-22, same machine and script. `features.html` answers this one:
the fix changes **where** tracks sit and how tall rows are, and both of
its grids are `normal` on both axes with automatic heights, so the two
binaries render it **byte-identically** -- checked with `cmp` on the
screenshots before any timing, which is what the negative-margin entry
above says to do.

Paired 25 times each way:

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| forward, parent then candidate | +0 | +0 | **+1** | +0 |
| reversed, candidate then parent | +0 | +0 | **-1** | +0 |

Forward +1 and reversed -1 is this file's own strongest shape for a
real cost: both rounds say the candidate is a millisecond slower at
laying out, on a 76 ms phase. The means disagree with the medians in
both directions (-1.04 and -0.68, the candidate *faster* on average)
and the candidate is slower in 14 of 25 pairs forward and 11 of 25
reversed, which is a coin, but the rule says to take the question to
the control rather than to another round.

The control is the parent recompiled with `gridDistributeTracks`
appended under a different name and **called from nowhere**. It comes
out at 3,078,144 bytes, which is the candidate's size exactly, against
the parent's 3,078,096.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| control then candidate | +0 | +0 | **+1** | +0 |
| candidate then control | +0 | +0 | **+0** | +0 |
| parent then control (dead code only) | +0 | +0 | +0 *(mean **+1.52**)* | +0 |

The candidate reads the same +1 against a binary that carries the same
machine code and never executes a byte of it. And the last row is the
finding in miniature: the parent against itself-plus-dead-code reads a
mean **+1.52 ms of layout** from code that cannot run. So the
millisecond is where the compiler put things, not work done -- the
fourth time this file has caught it, and the first where the reading
never reached a conclusion at all, because the control was built the
moment the mirror image failed rather than after a number had been
published and had to be withdrawn.

**The real cost is two integer comparisons per grid axis.**
`gridDistributeTracks` returns on its first line when the distribution
is `stretch`, which every grid that does not say otherwise is, and it
is called twice per grid container. A page with no grid on it never
reaches it.

## What finding an out-of-flow box costs

2026-09-22, same machine and script. Nothing, and the reason is
structural rather than lucky: hit testing does not run during a render
at all -- it runs when a pointer moves, and the benchmark moves none --
so the only thing on the measured path is a `push` onto a list as
`layoutPositioned` passes each out-of-flow box, on a walk that already
happens.

| features.html | forward | reversed |
|---|---|---|
| cascade | +0, 9 of 25 | +0, 8 of 25 |
| layout | -2, 6 of 25 | +0, 10 of 25 |
| paint | +0, 9 of 25 | -1, 8 of 25 |

Every median is zero or below in both directions, so there is nothing
here for a placement control to settle -- that control is for a reading
that *looks* like a cost, and none of these do.

Worth saying what is **not** measured: the fallback scan itself, which
walks the out-of-flow list once per click that the ordinary descent
misses. It is as long as the document has out-of-flow boxes, and a
click is not on any hot path, so it is left unmeasured rather than
guessed at.

**Reversing the descent into painting order costs nothing either**, for
the same structural reason, and the two binaries came out thirty-two
bytes apart:

| features.html | forward | reversed |
|---|---|---|
| cascade | +0, 7 of 25 | +0, 12 of 25 |
| layout | +0, 12 of 25 | +0, 10 of 25 |
| paint | +0, 10 of 25 | +1, 13 of 25 |

Three passes over the children where there was one, and a `z` loop over
the positioned ones -- all of it on a path a render never takes.

## What CSS2 §9.9's painting order cost, and three ways of paying it

2026-09-22, same machine and script. Neither benchmark page had a
`z-index` on it at all -- the `::placeholder` lesson repeating one
feature later -- so `tests/featurepage.py` gained a negative-`z-index`
stack per section and a `--verify` probe that turns the parent into a
stacking context and requires the pixels to move. Thirteen features now.

On the page that has them the first implementation cost **three
milliseconds of paint**:

| features.html | forward | reversed |
|---|---|---|
| paint | **+3** (mean +3.16), **23 of 25** | **-3** (mean -3.04), 2 of 25 |
| layout | +2, 14 of 25 | -1, 9 of 25 |

Both directions say the same thing, which is what a cost looks like.
`generated.html`, which declares no `z-index`, reads a median of 0 in
every phase in both directions: the per-document flag does what it
claims.

**Two attempts to remove it made it worse, and both are worth the
space.**

The cost is asking every painted box whether it is a stacking context.
The obvious fix is to work that out once, on a walk something else
already makes, so the first attempt threaded the owning context down
`layoutPositioned` and filed each negative box under it. Paint stayed at
+3 -- because the per-box question was still being asked there -- and
**layout gained seven**, since `layoutPositioned` visits every box in
the tree including the text and inline ones that paint skips.

The second attempt collected the negative boxes cheaply on the way down
and worked out each one's owner afterwards by walking *up* from it,
marking the owner so the painter could read a field. Twenty-five upward
walks, a handful of steps each. It cost **eighty-eight milliseconds of
layout**, 25 of 25 pairs, on a layout of seventy.

That number is the finding. `parentBox` is `boxRegistry[b.parentId]`,
and **a struct read out of a registry is a retained temporary whose
release walks everything reachable from it** -- finding 1's cost,
arriving without a back-pointer, through what looks like an array
index. A few hundred of those reads is a hundred milliseconds.
FINDINGS.md 40 has the reproduction.

**So the three milliseconds stands, measured and attributed**, and the
cheapest of the three is the simplest. It is paid only by a page that
declares a negative `z-index`, which is what this file's rule asks; the
way to remove it is a borrowed registry read, which is a language
change rather than an engine one.

## What the transform's containing block and hit testing cost

2026-09-22, same machine and script. Both halves are guarded by
`cascadeSawTransform`, so a document that never says `transform` pays
one boolean in the positioned-layout walk and one in `hitTest`. Hit
testing is not on the render path at all -- it runs when a pointer
moves, and the benchmark moves none.

`generated.html`, which has no transform on it, says nothing: cascade
reads **+1 in both directions**, which is what an order effect looks
like, and every other phase is 0.

`features.html` has a hundred and twenty transforms, and against the
**parent** it read layout +0 forward and -3 reversed. Against a
**placement control** it reads nothing:

| features.html | pad -> new | new -> pad |
|---|---|---|
| cascade | +0, 10 of 25 | +1, 13 of 25 |
| layout | **-1**, 7 of 25 | **+1**, 16 of 25 |
| paint | -1, 8 of 25 | +0, 10 of 25 |

The two layout readings add to zero, which is what nothing looks like.
The control here is the tightest this file has had: the parent
recompiled with the change's two functions renamed and called from
nowhere came out at **3,073,392 bytes, byte for byte the candidate's
size**. The -3 against the parent was four kilobytes of growth.

That is three features in a row where a reading against the parent
disagreed with the same reading against a size-matched control, and
three where the control won. The rule in CLAUDE.md is not a caveat any
more; it is the measurement.

## What `::placeholder` cost, and the page that could not have shown it

2026-09-22, same machine and script. This is the first entry here whose
*first* problem was that neither benchmark page exercised the feature at
all. `generated.html` has no form control, and `features.html` had
twenty text inputs and not one `placeholder` attribute, so both pairings
measured leakage and neither could have measured the work:

| generated.html | forward | reversed |
|---|---|---|
| cascade | -1, 7 of 25 | +0, 12 of 25 |
| layout | +0, 11 of 25 | +0, 11 of 25 |
| paint | +0, 8 of 25 | +1, 13 of 25 |

Nothing there, which is right and which says nothing about the feature.
So `tests/featurepage.py` gained a placeholder input per section and
`PROBES` gained a row for it -- `--verify` renders the page with
`::placeholder{color:#000}` and requires the pixels to move, so a page
that stopped exercising this would say so. Twelve features now, all
twelve live.

**On that page the feature cost two milliseconds of layout.**

| features.html, with placeholders | forward | reversed |
|---|---|---|
| layout | **+2** (mean +3.08), 17 of 25 | **-4** (mean -3.60), 3 of 25 |

Both directions say the candidate is the slower one, which is the shape
that means a cost rather than an order effect. A third binary split it:
the same head with `placeholderStyleFor` collecting its matches and then
returning the input's own style -- the selector work without the style
work -- read layout +1 of the +2. So a third of it was matching and two
thirds was **building a `Style` for each of the twenty placeholders**.

**The fix was to stop building them.** `computeStyle` has shared a
computed style between identically-matched elements since the table-cell
entry above; the same reasoning holds here, because twenty placeholders
under the same parent matching the same one user-agent rule compute the
same style. Routing `placeholderStyleFor` through `styleCache` is the
whole change, and the cache key gains the pseudo-element's name so an
entry made for `input::placeholder` can never be handed to an `input`.

| cached against uncached, features.html | forward | reversed |
|---|---|---|
| layout | **-2** (mean -2.92), 2 of 25 | **+2** (mean +2.28), **24 of 25** |

Twenty-four of twenty-five is the strongest reading this method has
produced. Against a **placement control** -- the parent recompiled with
the same code renamed and called from nowhere, forty-eight bytes from
the candidate -- the cached binary reads a median of 0 in every phase in
both directions, and the control itself reads 0 against the parent. The
cost is gone rather than moved.

The lesson is the one about instruments rather than the one about
caches: **the first two pairings were clean, symmetric and meaningless**,
because the page had nothing for the feature to do. A benchmark that
cannot see a feature reports no cost for it, which reads exactly like a
feature that has none.

## What the page-side breaks cost, and the millisecond that changed phase

2026-09-22, same machine and script. The change reaches an ordinary page
through one line: the unit collector's test for "does this box end the
container" becomes a range rather than an equality, because the two side
values sit above `BRK_PAGE`. Its first comparison rejects the `auto`
almost every box carries. `pageSideAt` runs once per break of a print
and not at all otherwise, and neither benchmark page is printed.

| generated.html | forward, parent first | reversed, candidate first |
|---|---|---|
| parse | +0, 7 of 25 | +0, 0 of 25 |
| cascade | **+1** (mean +1.12), 16 of 25 | +0 (mean -0.16), 8 of 25 |
| layout | +0, 9 of 25 | +0, 10 of 25 |
| paint | +0, 5 of 25 | +0, 6 of 25 |

A forward +1 against a reversed 0 is this file's clearest shape for a
real cost, and `src/css/cascade.f` is on the diff, so unlike the entry
below the rule had somewhere to send the question. The code answers it
anyway: the only cascade-side change is inside `breakKeyword`, which
returns before any of its comparisons when the property is undeclared,
and `generated.html` declares no `break-*` at all.

**So the control was built again** -- the parent recompiled with this
change's constants, its array and a reader of the same shape, all
renamed and called from nowhere. It came out eight bytes from the
candidate, and it moved a millisecond too. Into a different phase:

| generated.html | parent -> parent + dead code |
|---|---|
| cascade | +0 (mean -0.04), 10 of 25 |
| layout | **+1** (mean +1.36), 18 of 25 |

That is the finding. **The millisecond is not attached to a phase; it
follows wherever the compiler puts the code.** Against the parent the
candidate's landed in cascade and the dead code's in layout, which no
account of either diff can explain, because the dead code runs nowhere
and the candidate's cascade change runs nowhere on this page.

**Paired against the control, the candidate reads below it, both ways
and on both pages:**

| | pad -> new | new -> pad |
|---|---|---|
| `generated.html` cascade | **-1**, 4 of 25 | +1, 13 of 25 |
| `generated.html` layout | **-1**, 4 of 25 | +1, 15 of 25 |
| `features.html` cascade | +0, 8 of 25 | +1, 14 of 25 |
| `features.html` layout | **-2**, 3 of 25 | +1, 19 of 25 |

Every pair says the same thing in both directions: a binary that does
this work is no slower than a binary of the same size that does none,
and on these runs it is a millisecond quicker. The readings against the
*parent* do not compose with each other -- +1 of cascade for the
candidate, +1 of layout for the dead code, and -1 of both between them
-- and a quantity that does not add up across three binaries is not a
property of any one diff.

## What `print-color-adjust` cost, and the control that unmasked it

2026-09-22, same machine and script. The property reaches a page
through one door: `printsBackground`, which `paintBoxInner` asks once
per box and which returns true without reading anything whenever
`printOmitBackgrounds` is false -- every render but a
`--no-background-graphics` print. The cascade's applier is behind
`cascadeSawPrintColorAdjust`, and neither benchmark page says the
property, so the expected cost is nothing.

| generated.html | forward, parent first | reversed, candidate first |
|---|---|---|
| parse | +0, 6 of 25 | +0, 11 of 25 |
| cascade | -1, 7 of 25 | +0, 8 of 25 |
| layout | **+1**, 15 of 25 | **-1**, 4 of 25 |
| paint | +0, 12 of 25 | +0, 8 of 25 |

Those two layout readings do **not** cancel. A forward +1 against a
reversed -1 says the candidate is a millisecond slower in layout
whichever order it runs in, which is this file's strongest shape for a
real cost -- and the diff does not touch `src/layout/` at all, so the
rule's instruction to take the question to the code had nowhere to take
it.

**Two controls, and the second one answered it.** The same binary
paired against a copy of itself reads a median of 0 in every phase, so
the harness is not inventing the millisecond; the mean of -1.64 on
layout is the order effect this file already knows about, whichever
binary runs second reading faster here.

The second control is the new one. The **parent plus dead code** -- the
four globals and the one reader function of this change appended to
`src/css/style.f` under different names, called from nowhere, compiled
in and never executed:

| generated.html | parent -> parent + dead code |
|---|---|
| parse | +0, 6 of 25 |
| cascade | +0, 9 of 25 |
| layout | **+1** (mean +1.20), 16 of 25 |
| paint | +0, 7 of 25 |

Dead code cannot run, so that millisecond is **where the compiler put
the machine code**, not work anyone asked for. It is the candidate's
forward reading to the digit -- +1 of layout, 15 and 16 of 25 -- and it
belongs to the binary having grown, not to the feature.

**Paired against that control, the feature reads zero.** Both binaries
then carry the same growth and differ only by the live code:

| | pad -> new | new -> pad |
|---|---|---|
| `generated.html` cascade | +0, 7 of 25 | +0, 9 of 25 |
| `generated.html` layout | +0, 8 of 25 | +0, 11 of 25 |
| `generated.html` paint | +0, 9 of 25 | +0, 7 of 25 |
| `features.html` cascade | +0, 5 of 25 | +1, 13 of 25 |
| `features.html` layout | -1, 9 of 25 | +1, 13 of 25 |
| `features.html` paint | +0, 7 of 25 | +0, 5 of 25 |

Every `generated.html` median is 0 in both directions, and every
`features.html` pair adds to zero. The feature costs the pages that do
not use it nothing.

The lesson is that **a paired reading can survive its own mirror image
and still not be a cost**. Adding code moves code, and on a phase the
diff never touches that is the only mechanism left; the control that
separates the two is a binary that grows by the same amount and does
nothing with it.

## What ruby cost the pages with no ruby in them

2026-09-21, same machine and script. Ruby adds one comparison to
`isInlineLevelBox`, which every child of every block is asked about,
and one branch in the box builder's display dispatch. Nothing else on
a page that has no `<ruby>`.

| generated.html | forward, parent first | reversed, candidate first |
|---|---|---|
| cascade | +0, 11 of 25 | +0, 12 of 25 |
| layout | **-1**, 8 of 25 | **+1**, 14 of 25 |
| paint | +0, 11 of 25 | +1, 13 of 25 |

The two layout readings **add to zero**, which is what a difference of
nothing looks like once the order effect is separated out: whichever
binary runs second reads about a millisecond slower, and here that is
the whole of it. Compare the entry below, where both directions came
out positive and the answer was still nothing, and the one below that,
where forward was +1 and reversed 0 and a millisecond was real.

## What `text-wrap-style` cost, and the reversed pairing that read it

2026-09-21, same machine and script as the entry below, 25 iterations
a run. On a page that never says `text-wrap-style` the whole of it is
one boolean in `layoutBlockContent`, one behind the cascade's flag,
and one more comparison inside the declaration pass the entry below
merged -- no new pass anywhere.

| layout, paired median | generated.html | features.html |
|---|---|---|
| round one, parent first | +0, 8 of 25 | -1, 7 of 25 |
| round two, parent first | +1, 13 of 25 | +1, 14 of 25 |
| **reversed**, candidate first | **+2, 17 of 25** | **+1, 16 of 25** |
| the floor, candidate against a copy of itself | | +0, 10 of 25 |

**The reversed row is the answer.** Run the parent first and the
candidate reads about a millisecond slower; run the candidate first
and the *parent* reads one to two milliseconds slower. A reading and
its mirror image that both come out positive are not measuring a
difference between the binaries at all -- they are measuring the
order, and whichever runs second on this machine pays. The forward
rounds alone would have read as a real cost by this file's own rule of
a median of +1 across two rounds.

So the reversed pairing is worth running whenever a cost survives two
rounds, and it goes in the method above beside the floor. It is what
separated this entry, where the answer was "nothing", from the one
below, where the forward reading was +1 and the reversed one was 0 --
an order effect *plus* a real millisecond, which a third binary then
pinned to one loop.

## What `resize` cost, and the eight older loops it uncovered

2026-09-21, on the same machine as the entries above, paired with
`$S/abphase.sh` at 25 iterations a run: each iteration runs the parent
binary and then the candidate, so a machine that drifts drifts under
both halves of one pair.

`resize` puts no field on `Style` and no pass over the box tree. Its
only cost to a page that never says it is one boolean in the painter,
one in `collectMatches`, one in `applyStyle`, and **one scan of a
rule's declarations for the word `resize`** in `indexSheet`, so that
the flag can be raised before any element is styled. The first three
are free. The fourth read:

| cascade, paired median | features.html | generated.html |
|---|---|---|
| the floor (parent against a byte-identical copy) | +0, 7 of 25 | -1, 8 of 25 |
| the floor, round two | +0, 9 of 25 | +1, 14 of 25 |
| `resize` with its own scan | **+1, 15 of 25** | **+1, 13 of 25** |
| the same, round two | **+1, 13 of 25** | **+1, 14 of 25** |
| with the nine scans merged | +0, 9 of 25 | +0, 11 of 25 |
| the same, round two | +0, 12 of 25 | +0, 8 of 25 |

A paired median of +1 in both rounds on both pages, against a floor of
0, is the shape this file calls real. **A reversed pairing disagreed**
-- running the candidate first and the parent second read 0 in every
phase -- which is what sent the question to the code rather than to
another round: if a reading and its mirror image do not add to zero,
one of them is measuring the order.

The code answered it. The scan was the eighth of **nine** such loops
over a rule's declarations, one per per-document flag, and every one of
them sat *inside the loop over the rule's selectors*. A rule with five
selectors read its declarations forty-five times, and a flag that
stayed false -- which is every flag, on a page that never uses the
feature -- read all of them every time. They are one pass now, once per
rule, guarded by one test that skips the pass entirely when every flag
is already set. The last two rows are that binary.

So the cost this change was about to add is gone, and eight older ones
went with it. The lesson is the file's own, arriving from the other
direction: **a per-document flag is only free if asking the question is
free**, and the ninth copy of a cheap question is what made the first
eight visible.

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
| Source | 26,586 lines of Festina across `browser.f` and `src/` |
| Compile | 14.2 s, whole program, no incremental build |
| Binary | 2.8 MB, linking Cairo, X11, libjpeg, mbedTLS and libc |

Against Chromium, whose binary this browser is compared with everywhere
else in this file:

| | Bytes |
|---|---|
| This browser, the whole program | 2,842,688 |
| This browser, all `.f` source | 996,802 |
| Chromium, main executable only | 463,227,992 |
| Chromium, whole install tree | 624,734,779 |

**The binary is about 165 times smaller than Chromium's executable
alone**, and 222 times smaller than the tree it ships in. The comparison
flatters this browser and should be read with that in mind: what is
absent from the 2.8 MB — a JavaScript engine, a compositor, a sandbox,
a network stack, an extension system, ICU — is most of what is in the
463 MB. The figure is a fair measure of *this* program's size and a poor
measure of how much cheaper a browser could be.

Of that 14.2 s, **3.4 s is the single generated map literal** holding the
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

Several background layers cost **9,672 bytes** (2,768,672 → 2,778,344)
and nothing measurable in time: paint is 8 ms on `generated.html` before
and after, and its end-to-end best of five moved from 135 to 136 ms,
which is the noise two builds of the same source show. The page has no
background image on it, so what is being checked there is that the
refactor did not cost the boxes that have only a colour: a box with no
image of its own does not reach the layer machinery at all.

`all` costs **48 bytes** (2,768,624 → 2,768,672), which is what a
feature reached through one string comparison per declaration looks
like. Nothing walks the property list unless a page says `all`.

The Gaussian blur of an outer `box-shadow` costs **4,384 bytes**
(2,787,088 → 2,791,472) and about twice the paint time of the nested
rectangles it replaces, which is a few milliseconds on a page made of
shadows and nothing at all on one without them: `paintShadows` returns
on the first line where a box has none.

Measured on two pages of 60 cards each, best of five, `paint` from
`ARCHTELOS_TIMING=1`. Sixty cards sharing one `0 2px 8px` shadow: 1 to
2 ms before, 3 ms after. Sixty cards with a `0 2px 20px` shadow in 60
*different* colours, so nothing is shared and every ramp is built: 3 ms
before, 5 to 7 ms after. The first version of the change worked each
corner out a pixel at a time and took **91 ms** on that second page;
blitting one axis's profile at the other axis's alpha is what brought it
down, because `drawImage` multiplies an image's own alpha by `fillAlpha`
and that product is what a separable blur is.

The flex automatic minimum size and §9.7's freeze-and-repeat cost
**4,168 bytes** (2,791,512 → 2,795,680) and no measurable time.
`computeIntrinsic` is on the hot path for every box that sizes to its
content, and it gained one assignment; `generated.html`'s layout is 57,
57, 57, 58, 64 ms before and 57, 57, 59, 57, 60 after, five samples each
in the same minutes on the same machine. The freezing loop runs only
where a line overflows, and then at most once per item.

An `inset` shadow's Gaussian costs **40 bytes** (2,791,472 →
2,791,512) and nothing measurable: sixty cards with
`inset 0 0 12px rgba(0,0,0,.5)` paint in 2 ms against 1 to 2 ms for the
frames it replaces, five samples each. It is two passes of plain strips
rather than a pixel at a time, because the inside of a shadow is the
outside of its hole and one minus a product is what two passes
accumulate to.

Neither benchmark page has a shadow on it, so no table above moves.

Percentage and elliptical `border-radius` costs **9,088 bytes**
(2,759,536 → 2,768,624). The corners are resolved per painted box now
rather than once per computed style, which is eight lengths and a
comparison for a box that has a radius and one boolean for a box that
does not.

Interpolation hints and the mirrored degenerate ellipse cost **4,256
bytes** (2,755,280 → 2,759,536). A gradient with no hint in it pays one
comparison per band against a resolved offset of -1.

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


`::first-line` costs **5,336 bytes** (2,809,408 → 2,814,744) and nothing
measurable to a page that does not name it. The two places it could have
cost something are the hottest in the engine — `appendWord`, once per
word on every line, and `computeStylesFrom`, once per element — and both
reach it through a boolean that is false unless a rule somewhere said
`::first-line`.

Rebuilt and sampled alternately with the revision before it, in the same
minutes on the same machine, fifteen paired samples of `generated.html`
give

```
before: 108 104 104 105 106 104 106 112 129 109 140 106 105 109 105
after:  106 104 105 105 107 106 108 110 106 108 107 106 107 111 105
```

— the same best of 104 on each side, and the two readings over 120 both
on the side that does not have the feature. An earlier pair of best-of-7
runs read 102 against 104 and would have been reported as a 2 ms
regression; the wider sample is what shows that to be the machine.

The run's own control qualified at 7.7%: Chromium renders
`generated.html` in 24.0 ms against the 26.0 recorded here.

`revert` costs **376 bytes** (2,814,744 → 2,815,120) and nothing to a
page that does not say it: the map copy that keeps the user-agent
origin's declarations apart is taken only where a declaration somewhere
asked to roll back to them, and the apply loop is otherwise the one it
was. Nine paired samples of `generated.html`, rebuilt and run
alternately with the revision before it in the same minutes, give

```
before: 109 110 109 109 104 107 107 109 107
after:  106 109 105 109 107 106 106 108 113
```

— a best of 104 against 105, one millisecond apart on two series that
overlap through their whole range.

`lh` and `rlh` cost **4,216 bytes** (2,815,120 → 2,819,336) and, at the
second attempt, nothing measurable in time. The first attempt did cost
something, and the rule that predicted it is already in CLAUDE.md: the
cascade asked `lineHeightOf(parent)` and `lineHeightOf(s)` once per
computed style, and **a forwarded struct parameter is released on exit
with a collector walk of its subtree** (FINDINGS.md, "cycle trials").
Fifteen paired samples of `generated.html` with the struct version gave

```
before: 118 104 106 111 107 105 106 107 105 104 105 108 105 106 104
after:  111 111 107 112 109 106 107 108 109 106 106 107 107 109 107
```

— a best of 104 against 106, and every reading on the new side at or
above the old one's median. Splitting the function so the cascade passes
the two ints it needs, and the Style form calls that, removes the walk.
The same fifteen paired samples then give

```
before: 149 105 106 105 107 108 107 108 108 106 104 103 113 107 107
after:  106 103 105 104 105 107 107 107 107 102 104 104 112 110 105
```

— a best of 103 against 102, two series that interleave through their
whole range, and the one reading near 150 on the side without the
feature. Two ints where a struct was is the whole difference.

The three image notations cost **4,752 bytes** (2,819,336 → 2,824,088),
and the second attempt at `cross-fade()` costs nothing measurable where
the first cost about two milliseconds. The measurement had to be taken
on `features.html` rather than `generated.html` to see it at all:
`generated.html` has no background image on it, so it never reaches the
layer struct the cost was in.

`cross-fade()` gives a background layer a second image, which means two
more fields in the struct the painter fills **for every background layer
on the page**. Filling them unconditionally is two text assignments per
layer, and eleven paired samples of `features.html` said so:

```
before: 91 90 92 91 90 91 91 91 92 92 89
after:  91 93 98 92 93 93 92 92 92 92 93
```

— a best of 89 against 91, and every reading on the new side at or above
the old side's median. Behind the per-document flag that says a page
named a cross-fade at all, thirteen paired samples give

```
before: 88 88 91 90 91 89 89 90 95 91 90 93 91
after:  90 91 91 91 90 91 94 89 89 94 92 96 90
```

— 88 against 89 at the best, 90 against 91 at the median, two series
that interleave, which is what two builds of the same source look like
on this machine. What is left per layer is two boolean tests and a float
comparison.

The draggable thumb and the horizontal bar a long line raises cost
**4,744 bytes** (2,824,088 → 2,828,832), and **neither benchmark page
can say what they cost in time**, which is worth saying rather than
leaving the reader to infer it from a number that did not move. Neither
page has a scroll container on it, so neither reaches the two walks that
measure how far content overflows, and neither reaches `paintScrollbars`
past its first line. What the pages can say is that nothing else got
slower: twenty-six paired samples of `generated.html`, in two rounds,

```
before: 106 109 104 105 116 109 109 110 108 110 108
after:  114 113 107 108 107 112 113 110 106 109 109

before: 115 108 108 106 105 104 104 105 105 105 106 105 109 109 108
after:  111 113 106 109 103 111 105 104 105 110 107 117 106 107 106
```

— a best of 104 against 106 in the first round and 104 against 103 in
the second, which is the two rounds disagreeing about the sign of a
difference they both put at one or two milliseconds. That is what the
binary's own layout looks like on this machine, and it is why a single
round of eleven is not enough to claim one.

The horizontal scroll axis costs **4,832 bytes** (2,828,832 →
2,833,664). What it adds to a page that scrolls nothing is one function
call per clipped box painted, which answers zero on the first line
without looking anything up; neither benchmark page has a scroll
container, so neither can say more than that nothing else got slower.
Twenty-six paired samples of `generated.html`, in two rounds, give bests
of 104 against 104 and then 106 against 105, with the medians a
millisecond apart in opposite directions -- two rounds that do not agree
on a sign, which is this machine rather than the feature. One round had
a reading of 157 on the new side, and a single round is exactly what
such a reading would have been allowed to decide.

`::marker` costs **4,400 bytes** (2,833,664 → 2,838,064) and nothing
measurable in time. This is one feature `generated.html` *can* speak
for: the page is forty sections of a heading, a paragraph, a list and a
table, so every list item on it paints a marker and reaches the two
lookups the feature added. Both answer on their first line when no rule
anywhere named `::marker`. Thirteen paired samples give

```
before: 105 108 108 110 110 109 108 109 107 109 111 109 132
after:  110 106 111 111 114 109 108 118 109 109 109 111 105
```

— the same best of 105, medians a millisecond apart, and the highest
reading on the side without the feature.

Scrolling a container across with the wheel costs **168 bytes**
(2,838,064 → 2,838,232) and is not timed here, which is a statement
rather than an omission: the only new code is one function the shell
calls from a mouse-button handler, and the benchmark runs the renderer
with no window and no pointer. A paired series would measure the
machine, and there is already enough of that in this file.

`revert-layer` costs **4,456 bytes** (2,838,232 → 2,842,688) and nothing
at all to a page that does not say it: the whole of the layer
bookkeeping sits inside the branch `revert` already put behind the
per-document flag, so a page with neither keyword runs the same apply
loop it always ran. Eleven paired samples of `generated.html` give the
same best of 104 ms on each side, the two series interleaving through
their whole range.

A shadow cast from the box's own shape costs **12,992 bytes**
(2,842,688 → 2,855,680) and nothing to a box whose corners are square.
**Neither benchmark page can say so, and that is the point of saying it
here**: neither `generated.html` nor `features.html` casts a shadow at
all, so the only number either of them could move is the binary's. The
timing below comes from a page written for the question -- 2,000 cards
under `box-shadow: 0 4px 12px rgba(0,0,0,0.35)`, painted onto an
800x4000 canvas so about 355 of them are on it -- and from the same
2,000 cards with no shadow on them at all, as the control.

**The first version did cost something.** Twenty-one paired samples put
it 2 to 3 ms above the old binary on a 45 ms paint, while the no-shadow
control gave 10 ms on both sides on every sample: the cost was in the
shadows, not in the build.

Finding it took five binaries and it was none of the four things that
looked expensive. The eight extra arguments cost nothing -- the old
painter body behind the new fifteen-argument signature times the same as
the old binary. `resolveCornerRadii` behind the `borderRadius` flag cost
nothing. Growing the eight corners by the spread cost nothing. And
**41 KB of never-called code compiled into the old revision**, to shift
the layout of every function after it, cost nothing either, which is
what ruled out the explanation that would have been easiest to believe.
What removed it was taking the radii out of `paintShadows` altogether,
into a function reached only through that flag. Twenty-one paired
samples then give the same 42 ms minimum on both sides, medians 45 and
44, the new binary faster on eleven of the twenty-one and level on two.

**The rounded path is cheaper than the square one it replaces.**
Fifteen paired samples of the same 2,000 cards with
`border-radius: 10px` give 43-48 ms on the old binary against 27-31 on
the new. The two are not doing the same work -- the old one paints a
square shadow there, the new one a round shadow -- but the reason is
worth writing down. A square corner separates, so it is drawn as one
blit of a one-pixel ramp per row of the blur's reach, thirty-six blits
to a corner here; a round one does not separate and is instead a single
cached image, blitted once. The cache is keyed on everything the answer
depends on, so 355 identical cards build four corners between them. The
same trick would suit the square corners, and todo.md now says so.

Paged media costs **18,856 bytes** (2,855,680 → 2,874,536) and, once the
one thing in it that ran per declaration was put behind a flag, nothing
to a page that does not paginate. Twenty-five paired samples of
`generated.html` give a minimum of 103 ms against 102 and medians of 106
against 105, the median paired difference −1; twenty-one of
`features.html` give 88 against 89, medians 92 and 92, median paired
difference 0.

**The first version cost 2 ms on `generated.html`, and the rule that
catches this was already written down.** CSS2's `page-break-before` and
its two siblings are renamed onto the modern properties where a
declaration is applied, and `applyDecl` runs once per matched
declaration -- 11,614 of them on that page. Three name comparisons there,
paid by every page whether or not it has ever said `page-break` anything,
is exactly the "test inside a loop over every declaration" CLAUDE.md says
to put a flag in front of before it lands.

Moving the three comparisons to the end of `applyDecl` looked like the
fix and was not: the fall-through at the end is where *most* properties
land, since only the shorthands return before it, so nearly every
declaration still paid them. Twenty-five paired samples said so -- the
differences still clustered at +2 -- which is the whole reason to measure
again after a fix instead of reasoning about it. A per-document flag set
while the stylesheet is read, with `&&` in front of the comparisons, is
what removes it.

Two other suspects were measured and cleared on the way. The new `text`
field on `Style` costs something, but not this: three *more* dummy text
fields on top of it move the median 1 ms with the paired differences
scattered from −6 to +10, where the real regression was a tight cluster
at +2. And neither benchmark page paginates at all, so none of the
pagination, the page-box resolution or the `@page` parsing is on their
path -- which is why the only thing that could cost them anything was the
one line that ran per declaration.

CSS Scrollbars 1 and `scrollbar-gutter` cost **4,872 bytes** (2,874,536
→ 2,879,408) and nothing measurable. Twenty-one paired samples of
`generated.html` give the same 103 ms minimum and the same 106 ms median
on each side, with a median paired difference of 0 and the individual
differences running from −5 to +5 either way.

The cost worth watching for was not the cascade's: three more fields
read once per distinct computed style is nothing. It was the box tree's.
Separating "does this box scroll" from "how much room did its bar take"
put two more booleans on `Box`, and a `Box` is allocated per box rather
than per distinct style -- 2,728 of them on this page against the 24
styles they share. The measurement says those two booleans cost nothing
that twenty-one samples can see, which is the answer, but the reason to
take the samples was that this one could have gone the other way.

CSS Scroll Snap 1 costs **5,056 bytes** (2,879,408 → 2,884,464) and
nothing measurable. Twenty-one paired samples of `generated.html` give
102 ms against the previous 104 as a minimum and 105 against 106 as a
median, the median paired difference −1.

It is free for a structural reason and not a lucky measurement: snapping
runs from `boxScrollBy`, which a wheel or a dragged thumb calls and a
layout never does. A page that is rendered and not scrolled -- every
page the benchmark measures, and every page a screenshot takes -- does
not reach the code at all. What it does pay for is the thirteen fields
the snap properties put on `Style`, and those are read once per distinct
computed style: 24 of them for this page's 2,728 elements.

An inline box's own border and padding cost **4,352 bytes**
(2,956,712 → 2,961,064) and nothing measurable. Twenty-five alternating
paired samples of `generated.html`, parse through layout at 800x600:

| | Min | Median | Max |
|---|---|---|---|
| before (b7dc926) | 106 ms | 108 ms | 118 ms |
| after (71251ad) | 105 ms | 108 ms | 127 ms |
| paired, after less before | −12 ms | **0 ms** | +20 ms |

The new binary is the slower one in 10 pairs of 25 and the paired mean
is +0.64 ms. The noise floor was taken first, by running the parent
against a byte-identical copy of itself: nine pairs gave 107 against
108 as a minimum, so a 1 ms gap is what this machine calls "the same".

**The tables above are not updated from this run, because the control
says they would be measuring the machine.** The whole-run figures read
106 ms on `generated.html` where the table records 101, and Chromium's
control row read 24.0 ms where the table records 26.0 — the two engines
drifting in opposite directions by similar fractions, both inside the
15% the script allows. The parent, rebuilt and run in the same minutes,
reads the same 106, which is what settles it.

Two things could have cost something here and did not. The first is a
field on `Fragment`, which is allocated per text run and per inline per
line rather than per distinct style — nearer to `Box`'s 2,728 than to
the 24 styles they share. The second is the painter's cull, which every
line and every box on every page goes through: widening it by the
furthest any inline reaches outside its line is one addition against a
number that a document without a padded or bordered inline leaves at
zero, so the arithmetic is there but the pages that do not use the
feature get the same answer they got before.

`box-decoration-break` costs **200 bytes** (2,961,064 → 2,961,264) and
nothing measurable. Twenty-five alternating paired samples of
`generated.html`, parse through layout at 800x600:

| | Min | Median | Max |
|---|---|---|---|
| before (2674d33) | 104 ms | 111 ms | 123 ms |
| after (b6899cd) | 105 ms | 110 ms | 141 ms |
| paired, after less before | −7 ms | **−2 ms** | +21 ms |

The new binary is the slower one in 8 pairs of 25. The paired mean is
+0.72 ms and comes entirely from the single +21 pair, a 141 ms sample
where every other read 104 to 123; the median is where to read this one,
as it was for the `int` on `Style`.

Two hundred bytes is the smallest thing measured in this file, and the
reason is structural. `clone` adds no pass and no field: the keyword
goes in a map keyed by the computed style's serial, read once per
distinct style; the opening edge is added where `beginLine` already
re-opens the inlines that continue, which a page with no inline never
enters; and the closing edge is added in a loop over the inlines open
across a line break, which is empty on every line of a page that does
not break one.

`overscroll-behavior` and its four longhands cost **4,656 bytes**
(2,961,264 → 2,965,920) and nothing measurable. Twenty-five alternating
paired samples of `generated.html`, parse through layout at 800x600:

| | Min | Median | Max |
|---|---|---|---|
| before (b05691b) | 105 ms | 109 ms | 122 ms |
| after (ccbf5d1) | 105 ms | 108 ms | 122 ms |
| paired, after less before | −10 ms | **0 ms** | +3 ms |

The new binary is the slower one in 10 pairs of 25 and the paired mean
is −0.68 ms. The two ends of the run are the same on both sides, which
is the shape of a change that is not there.

It is free for the same structural reason the last two were, and the
reason is worth stating because it is now the pattern rather than a
piece of luck. The keyword pair is one packed `int` in a map keyed by
the computed style's serial, read once per distinct style — 24 of them
for this page's 2,728 elements — and the two reads on the scrolling path
are guarded by a per-document flag that a page never saying the property
leaves false. Nothing here runs per box, per fragment or per
declaration, and the benchmark pages do not scroll at all, so they never
reach the walk the property changes.

`anchor()` in the four inset properties costs **9,296 bytes**
(2,965,920 → 2,975,216) and nothing measurable. Twenty-five alternating
paired samples of `generated.html`, parse through layout at 800x600:

| | Min | Median | Max |
|---|---|---|---|
| before (edfce48) | 103 ms | 108 ms | 117 ms |
| after (c108fbe) | 104 ms | 107 ms | 139 ms |
| paired, after less before | −11 ms | **−2 ms** | +32 ms |

The new binary is the slower one in 7 pairs of 25 and the paired mean
is −0.04 ms. The one +32 pair is a 139 ms sample where every other read
104 to 117; the median is where to read this, as it was for the `int`
on `Style`.

It is free because it runs where the feature already ran. The four
references live on the `AnchorInfo` a page grows only when it says one
of the anchor properties, not on `Style`; reading them costs four array
lookups inside the walk that already resolves `position-anchor`, behind
a flag a page that never says the function leaves false; and the
resolution itself is in `placeAnchored`, which a page with no anchor
never reaches. `generated.html` says none of it.

The static position costs **4,592 bytes** (2,975,216 → 2,979,808) and
about **one millisecond on `generated.html`, which runs none of it**.
That sentence is the finding, and it took five binaries to be able to
write it honestly.

Twenty-five alternating paired samples each, parse through layout at
800x600, all on an idle machine:

| | Median | Mean | Slower in |
|---|---|---|---|
| the change | +1 ms | +0.72 ms | **17 of 25** |
| the change, again | +1 ms | +0.44 ms | **17 of 25** |
| the change, a third time | +2 ms | +1.56 ms | **17 of 25** |
| the change with its two map resets guarded | +1 ms | +1.08 ms | 15 of 25 |
| the two globals and the reset, none of the code | +1 ms | +0.92 ms | 16 of 25 |
| that binary against the whole change | −1 ms | −1.44 ms | 7 of 25 |
| **the parent against a copy of itself** | 0 ms | −1.96 ms | **6 of 25** |
| the parent against itself, again | 0 ms | −0.12 ms | 12 of 25 |
| the parent plus two *unused* global maps | 0 ms | −4.20 ms | 9 of 25 |

Everything carrying the change is slower in 15 to 17 pairs of 25.
Everything that does not carry it is slower in 6 to 12. The minimum
moves from 103 ms to 104 in every binary that is not the parent. Five
runs agree, so it is not the run.

**And it cannot be work.** `generated.html` declares no `position:` at
all; the engine's own `docHasPositioned` reads false on it, so the
writes, the read and the reset are all behind a flag that is never
raised. Two things that would have explained it do not: two unused
global maps added to the parent cost nothing by the pair statistics, and
guarding the resets — which does remove two allocations per layout —
did not move the number either.

So what is left is the shape of the binary rather than anything it does,
which is the explanation this file ruled out once before for
`corner-shape`, where 41 KB of never-called code cost nothing. It is not
ruled out here. It is recorded as measured, unattributed, and the number
is a millisecond on a page that never enters the feature.

The tables above are not updated from these runs.

A motion path's curve commands cost **4,360 bytes**
(2,979,560 → 2,983,920) and nothing measurable. Twenty-five alternating
paired samples of `generated.html`, parse through layout at 800x600:

| | Min | Median | Max |
|---|---|---|---|
| before (5bac95e) | 104 ms | 106 ms | 111 ms |
| after (b8f17ee) | 105 ms | 107 ms | 108 ms |
| paired, after less before | −6 ms | **0 ms** | +2 ms |

The new binary is the slower one in 11 pairs of 25 and the paired mean
is +0.12 ms. Eleven of twenty-five is inside the band the parent
measured against a copy of itself — 6 and 12 of 25 — where the entry
above it sat at 15 to 17 in five separate runs.

It is free for the plainest of reasons: the sampling runs where the path
is built, which is once per element that has an `offset-path`, and
`generated.html` has none. The minimum moved from 104 to 105 here as it
did there, which is the one part of that entry this run does not settle.

A motion path's subpaths cost **80 bytes** (2,983,920 → 2,984,000) and
nothing measurable. Twenty-five alternating paired samples of
`generated.html`, parse through layout at 800x600:

| | Min | Median | Max |
|---|---|---|---|
| before (1abcb5b) | 103 ms | 106 ms | 110 ms |
| after (520877e) | 103 ms | 106 ms | 115 ms |
| paired, after less before | −4 ms | **0 ms** | +5 ms |

The new binary is the slower one in 11 pairs of 25, the paired mean is
exactly zero and the minimum does not move — the one entry in this file
where it did not. Eighty bytes is the smallest change measured here: a
`moveTo` that pushes a point without adding the gap to the running
length, a counter, and two conditions.
Restoring the inline formatting context's containing block, and
`initial-letter` on top of it, cost **4,544 bytes**
(2,984,000 → 2,988,544) and nothing measurable. Twenty-five alternating
paired samples of `generated.html`, parse through layout at 800x600,
with a second round because the first carried one outlier:

| | Min | Median | Max |
|---|---|---|---|
| before (bc1b69e) | 114 ms | 116 ms | 119 ms |
| after (9575d45) | 114 ms | 116 ms | 136 ms |
| paired, after less before | −3 ms | **0 ms** | +20 ms |
| before, second round | 113 ms | 115 ms | 119 ms |
| after, second round | 114 ms | 116 ms | 120 ms |
| paired, second round | −4 ms | **1 ms** | +5 ms |

The new binary is the slower one in 11 pairs of 25 and then 13, against
the 7 the parent measured against a byte-identical copy of itself in the
same minutes — where the paired median was 0, the mean −0.40 and the
spread −6 to +6. The paired mean is +1.08 in the first round, all of it
the single +20 pair, and +0.16 in the second. `features.html` gives
median 0, mean −0.56, slower in 6 of 25.

That is what the guards are for. The drop cap's push is behind
`anyInitialLetter`, which `generated.html` never raises, and the float
branch asks `initialLetterPacked` only of a box that is already a float.
The containing-block fix is two integers saved and restored once per
formatting context, which is the one part of this that every page pays;
it does not show.

**The numbers in the tables above are not updated from this run, and
this run says why.** It read 114 ms on `generated.html` where the table
records 101, and Chromium read 23.1 ms where the table records 26.0 --
the engine 13% slow and the browser 11% fast in the same five minutes,
which is the machine rather than either of them. The control passed at
11.2% of the 15% the script allows, which is the furthest out this file
has recorded it. The paired comparison above is the measurement that
settles the change, because both of its binaries ran in those same
minutes.
Correcting `FONT_CAP` to 0.733 and flooring the cap height cost **32
bytes** (2,988,544 -> 2,988,576) and nothing measurable, on a noisier
machine than the entries above it. Twenty-five alternating paired
samples of `generated.html`, parse through layout at 800x600, with the
noise floor taken twice in the same minutes:

| | Min | Median | Max | Paired median | Mean | Slower in |
|---|---|---|---|---|---|---|
| parent against a copy of itself | 105 | 112 | 119 | 0 ms | +0.60 | 10 of 25 |
| the same, again | 106 | 112 | 132 | 1 ms | 0.00 | 13 of 25 |
| before (637eb26) | 95 | 113 | 118 | | | |
| after (cde729e) | 107 | 114 | 124 | **0 ms** | +0.84 | 10 of 25 |

`features.html` gives a paired median of 0, a mean of +1.12 and 11 of 25.

**The floor is wider here than in any other entry in this file** -- the
paired differences of a binary against a byte-identical copy of itself
run from -14 to +25 ms, where the same control an hour earlier ran -6 to
+6. Two container restarts and a full valgrind run had just finished,
and the machine had not settled. The medians are what carry the result:
the change reads 0 against a floor of 0 and 1. A single-round reading of
the means alone would not have been worth anything, which is the whole
reason the floor is taken beside the measurement rather than remembered
from last time.

The change touches two functions, `textBoxOverEdge` and
`applyInitialLetter`, and neither benchmark page declares
`text-box-trim` or `initial-letter`, so nothing on either page reaches
the changed code at all. That is a reason to expect the result, not a
substitute for it.
`anchor-size()` costs **9,136 bytes** (2,988,576 -> 2,997,712) and
nothing measurable, on two pages, each measured twice against its own
noise floor taken in the same minutes. Twenty-five alternating paired
samples, parse through layout at 800x600:

| `generated.html` | Median | Mean | Slower in |
|---|---|---|---|
| parent against a copy of itself | 1 ms | -0.04 | 13 of 25 |
| the same, again | 0 ms | -0.80 | 9 of 25 |
| after (66fe055), round one | **0 ms** | +2.64 | 10 of 25 |
| after, round two | **-1 ms** | -2.16 | 6 of 25 |

| `features.html` | Median | Mean | Slower in |
|---|---|---|---|
| parent against a copy of itself | 1 ms | +1.08 | **14 of 25** |
| after, round one | 2 ms | +2.00 | **18 of 25** |
| after, round two | 0 ms | +1.00 | 12 of 25 |

**The eighteen of twenty-five is why this entry has two rounds.** That
is the sort of number this file has twice found a real cost behind --
the `int` on `Style` was fourteen of twenty-five -- so the floor was
taken on that page rather than borrowed from the other, and it came
back at *fourteen*. The statistic has a per-page baseline: the harness
runs the two binaries alternately and the second of each pair is
systematically a touch slower on this page, whichever binary it is. A
second round then gave twelve, below that floor. The paired means swing
+2.64 and -2.16 on one page and +2.00 and +1.00 on the other, which is
what says neither is a measurement of the change.

The read sites are in the width and height of every box on every page,
which is why each one asks `anyAnchorSize` before calling the helper
rather than leaving the test to the helper's first line: a call that
returns -1 is still a call. The second layout pass itself is behind the
same flag and runs on no page that does not say `anchor-size()`.
Taking `anchor-size()` into the margins and insets costs **816 bytes**
(2,997,712 -> 2,998,528), nothing on `features.html`, and about **two
milliseconds of layout on `generated.html`** -- a page with no
`anchor-size()` in it, whose `anyAnchorSize` reads false. That is
recorded rather than explained: three candidate causes were found by
reading the diff, each was fixed, and none of the fixes removed it.

The reading is not the harness being noisy. A floor taken either side
of the comparison, all three runs in the same minutes, twenty-five
alternating paired samples of `generated.html`:

| | Paired median | Slower in |
|---|---|---|
| parent against a copy of itself | -1 ms | 9 of 25 |
| **parent against the change** | **+3 ms** | **20 of 25** |
| parent against a copy of itself, again | 0 ms | 11 of 25 |

**Asked per phase, it is layout.** The same twenty-five samples, with
each phase paired on its own rather than summed:

| | Floor | The change |
|---|---|---|
| parse | 0 ms, 7 of 25 | 0 ms, 5 of 25 |
| stylesheets | 0 ms, 4 of 25 | 0 ms, 3 of 25 |
| cascade | 0 ms, 11 of 25 | +1 ms, 14 of 25 |
| **layout** | **-1 ms, 7 of 25** | **+2 ms, 18 of 25** |

That is worth the table on its own: the summed harness had said
"slower", and only the per-phase pairing said *where*. It ruled out the
two explanations that had looked most likely from the diff.

**Three attributions were tested and all three failed.**

1. *The flag's scan allocated.* Raising `cascadeSawAnchorSize` lowercased
   every declaration value of every rule, which allocates a string per
   declaration. Replaced with `asciiIndexOfLower`, which searches
   without allocating. Measured against the unfixed binary: paired
   median 0, 11 of 25 -- no change.
2. *The slots were allocated per element.* Three fourteen-slot arrays
   were built for every element of every page, where the version before
   this built three six-slot ones. Replaced with shared do-nothing
   arrays that only a page actually writing the function replaces.
   Measured the same way: paired median 0, 11 of 25 -- no change.
3. *A branch was added inside a hot function.* `resolveEdges` runs for
   every box, and the four margin lookups were written inline in it.
   Moved out into `applyAnchorSizeMargins`, leaving one predictable
   branch. One round read layout at +1 ms and 15 of 25, halving it; the
   next read +2 ms and 17 of 25 again.

All three changes were kept. Each is strictly less work than what it
replaced, and the rule they serve -- a feature must not cost anything to
the pages that do not use it -- is a rule about what the code does, not
about what a noisy afternoon can measure. But none of them is claimed
to have fixed anything, because none of them measurably did.

What is left in the layout phase, on a page with no `anchor-size()`, is
one predictable-false branch per box and four guarded reads in a
positioning pass `generated.html` never enters. Two milliseconds is not
credible as the cost of that work, and no further explanation was
found. **This is the second entry in this file recorded as measured and
unattributed**, the first being the static position's millisecond, and
it has the same shape: localised to one phase, reproducible, and larger
than the work it could be doing.

`features.html` is free: paired median 0 and 11 of 25 against a floor
of -1 and 8 of 25, in the same minutes.

`anchor-size()` inside `calc()` costs **8,672 bytes** (2,998,528 ->
3,007,200) and nothing measurable, on both pages, each against its own
per-phase floor taken in the same minutes. Twenty-five alternating
paired samples at 800x600:

| `generated.html` | Floor | The change |
|---|---|---|
| parse | 0 ms, 1 of 25 | 0 ms, 2 of 25 |
| stylesheets | 0 ms, 3 of 25 | 0 ms, 3 of 25 |
| cascade | -1 ms, 5 of 25 | 0 ms, 6 of 25 |
| layout | +1 ms, 13 of 25 | +1 ms, 15 of 25 |

| `features.html` | Floor | The change |
|---|---|---|
| parse | 0 ms, 5 of 25 | 0 ms, 7 of 25 |
| stylesheets | 0 ms, 7 of 25 | 0 ms, 10 of 25 |
| cascade | 0 ms, 9 of 25 | -1 ms, 9 of 25 |
| layout | -1 ms, 8 of 25 | 0 ms, 12 of 25 |

`generated.html`'s layout floors at thirteen of twenty-five here, which
is the per-page baseline this file records above; fifteen sits on it,
with a paired mean of 0.00. The one reading that moved at all is
`features.html`'s stylesheets, ten against a floor of seven, with a
median of 0 and a mean of +0.20 -- a fifth of a millisecond on a phase
that is not where any of this change's code is.

The expression path is the flag pattern again and nothing else: the
cascade reaches it only behind `cascadeSawAnchorSize`, and the layout
walk that resolves it only behind `anyAnchorSize`. Neither page says
`anchor-size()`, so neither raises either flag. The two milliseconds
of unattributed layout the entry above records on `generated.html` are
still there and are still not this.

**The table above is not rewritten from this change's `tests/bench.sh`
run, because that run disqualified its own absolute numbers.** It read
Chromium at 23.9 ms on `generated.html` where this file records 26.0 --
8.1% out, inside the 15% the script allows and so a pass, but a shift
in a row the change could not have touched. This browser's row moved
the other way in the same minutes, 120 ms against the 101 recorded, so
the machine was neither uniformly fast nor uniformly slow and neither
number is a reading of the engine. The paired measurements above are
what carry this entry: they compare two binaries alternately, in the
same minutes, on the same machine, and a machine that drifts under both
of them drifts out of the difference.

`anchor()` inside `calc()` costs **4,512 bytes** (3,007,200 ->
3,011,712) and nothing measurable, on both pages, each measured twice
against its own per-phase floor taken in the same minutes. Twenty-five
alternating paired samples at 800x600, paired mean in brackets:

| `generated.html` | Floor | The change | Floor again | The change again |
|---|---|---|---|---|
| parse | 9 of 25 (+0.12) | 9 (+0.40) | 9 (-0.04) | 7 (+0.20) |
| stylesheets | 1 of 25 (-0.12) | 2 (-0.16) | 2 (-0.08) | 2 (+0.08) |
| cascade | 10 of 25 (+0.52) | 12 (+1.04) | 11 (+0.72) | **8 (-0.76)** |
| layout | 9 of 25 (-1.36) | 13 (-1.12) | 12 (+1.44) | **7 (-1.24)** |

| `features.html` | Floor | The change | Floor again | The change again |
|---|---|---|---|---|
| parse | 5 of 25 (-0.20) | 9 (+0.08) | 6 (-0.28) | 7 (-0.08) |
| stylesheets | 5 of 25 (0.00) | 6 (-0.04) | 5 (-0.12) | 9 (+0.16) |
| cascade | 8 of 25 (-0.48) | 10 (**+2.24**) | 8 (-0.64) | 10 (-0.24) |
| layout | 9 of 25 (-0.68) | 9 (-0.48) | 12 (-0.04) | 11 (-0.32) |

**Two readings in the first round would have been worth chasing on
their own, and the second round took both back.** On `generated.html`
the change read 12 and 13 of 25 in cascade and layout against a floor
of 10 and 9; asked again it read **8 and 7**, *below* a floor that had
meanwhile moved to 11 and 12. On `features.html` the cascade's paired
mean read +2.24 ms, the largest single number in this comparison; asked
again it read -0.24 against a floor of -0.64. A mean that swings from
+2.24 to -0.24 across two rounds of the same two binaries is not a
measurement of either of them.

The +2.24 was worth ruling out rather than waving through, because this
change does add a scan to the declaration walk -- and `features.html`
is the page that exercises everything. It rules itself out: that page
contains no `anchor` anywhere, so `cascadeSawAnchorInset` never rises
and the scan the expression form needs never runs. It declares exactly
one `left` and one `bottom`, which is the whole population the inset
loop could have charged for.

What the change does to the walk it cannot avoid is strictly less work
than before, not more. Both function names begin `anchor`, so the two
flags are raised by **one** scan for that prefix rather than two scans
for the full names, with the character after it saying which -- a
shorter needle over the same bytes, once instead of twice.

`min()`, `max()` and `clamp()` cost **9,304 bytes** (3,011,712 ->
3,021,016) and nothing measurable, against a per-phase floor taken on
each page in the same minutes. Twenty-five alternating paired samples
at 800x600, paired mean in brackets:

| `generated.html` | Floor | The change |
|---|---|---|
| parse | 10 of 25 (+0.32) | 2 (-0.44) |
| stylesheets | 4 of 25 (+0.08) | 0 (-0.08) |
| cascade | 10 of 25 (-0.48) | 6 (-0.24) |
| layout | 13 of 25 (+0.84) | 12 (+0.92) |

| `features.html` | Floor | The change | Floor again | The change again |
|---|---|---|---|---|
| parse | 3 of 25 (-0.32) | 7 (+0.12) | 6 (-0.04) | 6 (+0.04) |
| stylesheets | 10 of 25 (+0.28) | 9 (-0.04) | 7 (+0.08) | 5 (-0.04) |
| cascade | 8 of 25 (+0.24) | 7 (-0.56) | 9 (+0.60) | 6 (+0.44) |
| layout | 11 of 25 (+0.12) | 13 (+0.12) | **13 (+0.92)** | **13 (-0.24)** |

**This is the change in this file with the most to prove**, because
what it touches is `resolveLen` -- the function that turns a `Len` into
pixels, called for every length of every box of every page. A cost
there would show in layout and nowhere else, which is why
`features.html`'s layout was asked twice. It read 13 of 25 against a
floor of 11; asked again the floor itself read **13**, with the change
also at 13 and a paired mean *below* it. Thirteen is what that page's
layout floors at today.

What `resolveLen` actually gained is one test for a kind it almost
never is, written as `anyMinMax && l.kind == LEN_MINMAX` so that a page
which never says one reads a global rather than a struct field. That
is not a saving the benchmark can see, and it is not claimed as one:
the guard is there because a test inside a loop over every box gets a
per-document flag before it lands, which is a rule about what the code
does.

Correcting the `ex`, `ch` and `cap` units costs **32 bytes**
(3,021,016 -> 3,021,048) and nothing attributable. On
`generated.html` the change read *below* its floor in all four phases
in one round and was left there. On `features.html` the cascade -- the
phase `parseLength` runs in -- was asked three times:

| `features.html`, cascade | Floor | The change |
|---|---|---|
| round one | 7 of 25 (-0.36) | 13 (+1.32) |
| round two | 7 of 25 (-1.16) | 11 (+0.76) |
| round three | 6 of 25 (-0.96) | 8 (+0.24) |

**The counts converge on the floor and the first round is the
outlier**: 13, 11, 8 against 7, 7, 6, with a paired median of 0 in
every one. The means do not converge as fast, and the reason is
visible in the floor's own column -- a binary paired against a
byte-identical copy of itself reads -0.36, -1.16 and -0.96 on this
page, so the *second* sample of each pair is systematically the faster
one here. That bias is the opposite of what this file recorded for the
same page when `anchor-size()` landed, where the second of each pair
was the slower. A per-page pairing bias that flips between sessions is
a reason to read the counts and the medians rather than the means, and
to take the floor every time rather than remember it.

The mechanism was checked rather than assumed, and there is not one.
`parseLength` split `unit == 'ex' || unit == 'ch'` into two `if`s,
which performs the same two comparisons on the path that falls through
both; `cap` reads a global float where it read an immediate; and the
three constants changed value. Nothing was added to any loop.

`font-size-adjust` costs **4,240 bytes** (3,021,048 -> 3,025,288) and
nothing measurable. On `generated.html` the change read at or below
its floor in all four phases. On `features.html`:

| `features.html`, layout | Floor | The change |
|---|---|---|
| round one | 10 of 25 (-0.60) | 14 (+1.04) |
| round two | **13 of 25 (+0.96)** | **10 (+0.76)** |

The first round's 14 against 10 inverted completely on the second: the
floor came back at 13 and the change at 10, *below* it, with a paired
median of 0 where the floor's was +1. That is the third time in this
file's recent entries that a first-round reading on this page has been
taken back by a second, and it is the reason the floor is taken every
time rather than remembered.

Neither page declares `font-size-adjust`, so
`cascadeSawFontSizeAdjust` never rises and the one map lookup the
property needs is never made -- the flag is why that lookup is not
paid by every element of every page that will never use it.

`baseline-source` costs **400 bytes** (3,025,288 -> 3,025,688) and
read below its floor in every phase of both pages, in one round:

| Phase | `generated.html` floor / change | `features.html` floor / change |
|---|---|---|
| parse | 6 of 25 / 9 | 6 of 25 / 5 |
| stylesheets | 5 of 25 / 6 | 11 of 25 / 8 |
| cascade | 8 of 25 / 12 | 7 of 25 / 9 |
| layout | **14 of 25 (+2.00) / 10 (-2.48)** | **13 of 25 (+0.52) / 8 (-1.28)** |

Layout is the phase the change is in, and on both pages the floor read
*higher* than the change did -- 14 against 10 and 13 against 8, with
the floor's paired mean positive and the change's negative on each.
There is nothing here to ask a second round about.

What layout gained is one test per block that has line boxes, not per
box: `anyBaselineSource && baselineSourceOf(b.style) == BSRC_FIRST`,
at the single place the inline layout finishes a box's baseline.
Neither page declares the property, so the flag stays false and the
right-hand side never runs.

**Four struct writes per anonymous box cost two milliseconds**, and
this is the first entry in this file where a cost was found,
attributed to the line that caused it, and removed.

Giving a flex container's anonymous text item the margins the standard
says it has -- zero, where a `Style` built fresh has `auto` -- meant
four `Len` writes in `anonymousStyle`, which every anonymous box on
every page goes through. `generated.html` is headings and paragraphs
and tables, so it is a page of anonymous boxes. Twenty-five
alternating paired samples:

| `generated.html` | Floor | The change |
|---|---|---|
| cascade, round one | -1 ms, 6 of 25 | **+1 ms, 13 of 25** |
| layout, round one | -1 ms, 7 of 25 | **+1 ms, 13 of 25** |
| cascade, round two | 0 ms, 11 of 25 | **+1 ms, 16 of 25** |
| layout, round two | -1 ms, 10 of 25 | **+1 ms, 15 of 25** |

Two rounds, the same direction, a paired median of +1 in all four --
which is what this file has learned to treat as real rather than as
the page's own bias, because the bias shows up as a count without a
median.

**A third binary attributed it.** The same head with the four writes
taken back out, against the same parent in the same minutes, read
cascade at 9 of 25 against a floor of 8 and layout at 12 against 11,
with a median of 0 in both -- so the cost is those four writes and
nothing else on the diff.

**Moving them costs nothing.** Only a flex item can tell an auto
margin from a zero one, so the four writes moved out of
`anonymousStyle` and into the one place that builds an anonymous flex
item. Measured again, twice, and on the other page:

| | Floor | The change |
|---|---|---|
| `generated.html` cascade | 8, then 9 of 25 | 10, then 12 |
| `generated.html` layout | 6, then 8 of 25 | 12, then 10 |
| `features.html` cascade | 14 of 25 (+1.84) | **8 (+0.40)** |
| `features.html` layout | 12 of 25 (+3.16) | **10 (+1.28)** |

Every median is 0, and on `features.html` the change reads below its
floor in both phases. The rule this serves is the file's own -- a
feature must not cost anything to the pages that do not use it -- and
the point of the entry is that the rule was checked rather than
assumed, and the check failed the first time.

**And it failed again, on the next feature, for a different reason.**
`zoom` scales every pixel length as `lenPx` builds it, which is one
line in the function that builds *every* length of every declaration.
Written as a branch -- `cascadeZoomScale == 1.0 ? px : px *
cascadeZoomScale` -- it cost a millisecond of cascade on **both**
pages:

| cascade | Floor | The change |
|---|---|---|
| `generated.html`, round one | 0 ms, 7 of 25 | **+1 ms, 13 of 25** |
| `generated.html`, round two | 0 ms, 8 of 25 | **+1 ms, 14 of 25** |
| `features.html` | 0 ms, 11 of 25 | **+1 ms, 15 of 25** |

A third binary attributed it: the same head with that one line reverted
to `l.v = px` read a median of 0 and 11 of 25 against a floor of 12.

**The fix was to take the branch out, not the work.** The scale is
1.0 on every page that never says `zoom`, so `l.v = px *
cascadeZoomScale` is a no-op multiply there -- and one predictable
multiply beats a compare and a branch:

| | Floor | The change |
|---|---|---|
| `generated.html` cascade, round one | 0 ms, 9 of 25 | 0 ms, 11 of 25 |
| `generated.html` cascade, round two | 0 ms, 12 of 25 | **-1 ms, 4 of 25** |
| `features.html` cascade | 0 ms, 4 of 25 | 0 ms, 9 of 25 |

Every median is 0 or better, and the second round reads *below* its
floor. Two entries in a row have now been found, attributed to a line,
and removed -- and the lesson of this one is narrower than the last:
**in the hottest function, the test that avoids the work can cost more
than the work.**

## What separating §9.9's steps 3, 4 and 5 cost, and the two designs that were wrong

CSS2 §9.9 paints a box's in-flow content in three steps where this
painter did one walk in document order. Three walks of the subtree is
the obvious shape, and it is the expensive one. Paired, 25 iterations,
`ARCHTELOS_TIMING` phases, forward and reversed:

| paint | `generated.html` | `features.html` |
|---|---|---|
| three walks, each asking which step paints a box | **+7 ms** of 20, 24 of 25 | **+23 ms** of 33, 25 of 25 |
| the same, its `Style` reads behind a per-document flag | +1 ms of 20, 18 of 25 | +23 ms of 33 |
| the answer written on the box by the first walk | 0 ms of 20, 9 of 25 | **-1 ms** of 33, 8 of 25 |

Every row's mirror image agrees with it: the first reads -6 reversed,
the second -1, the third 0 and 0.

**None of it was the walking.** Replacing `boxPaintsWhole`'s body with
`return false` — which on `generated.html` is the answer it gives
anyway, and the two binaries render the page pixel for pixel the same —
gave back 8 ms forward and 6 reversed. Two extra traversals of a
2,728-element box tree are free; asking each box a question three times
is not.

**The +1 ms row survived a placement control.** The parent recompiled
with this change's constants, globals and functions renamed and called
from nowhere came out within 4 KB of the candidate on a 3 MB binary,
and pairing the candidate against *that* read +1 forward and -1
reversed — so the millisecond was work rather than where the compiler
put the machine code. It is the only cost this project has measured
that the control has confirmed.

**And the obvious optimization was the worst of all.** Collecting the
boxes the later two steps want, during the first walk, so that neither
walks the tree again, turned `generated.html`'s 20 ms paint into 543 —
**+523 ms**. Putting a box in an `arr[Box]` costs a walk of everything
under it; FINDINGS.md's finding 41 has the minimal reproduction, where
ten traversals of a 1,093-node tree go from 0 ms pushing each node's
`id` to 306 ms pushing the node.

What works is an integer. The step 3 walk writes on each box which step
paints it, and the step 4, step 5 and positioned walks read that. The
millisecond `features.html` *gains* is the inline-level boxes that are
no longer painted twice — the same box reached once from the line that
holds it and once from a walk over its parent's children, which this
painter had done since the beginning and which nothing could see until
a `border-radius` blended an antialiased corner against itself.

**What is still unexplained is the microsecond a call.** A `Style` read
was the first explanation and is measured wrong: a Festina struct of
244 fields, 16 of them `text` and 14 of them arrays — `Style`'s own
shape — read forty thousand times does not register at millisecond
resolution. todo.md keeps the question.

## What giving the outline its own pass cost

CSS2 §9.9 draws outlines after the in-flow content and before the
positioned descendants, which is a pass of its own over the marks the
step 3 walk leaves. Paired, 25 iterations, both directions:

| paint | forward | reversed |
|---|---|---|
| `generated.html`, which declares no outline | 0 ms of 19, 9 of 25 | 0 ms, 9 of 25 |
| `features.html`, 96 outlined figures | +1 ms of 31, 16 of 25 | +2 ms |

The two binaries render `generated.html` byte for byte the same, so the
first row is the whole of what a page that does not use the feature
pays: one boolean, `docHasOutline`, asked once per subtree. On
`features.html` the pass runs and the two binaries differ by 1,424
pixels of 6.4 million — the outlines that now show where a neighbour
used to cover them — which is the feature working rather than the page
changing shape: the layout is identical and the same outlines are drawn
either way, in a different order.

**A third binary said the obvious optimization was not one.** Recording
on each box, during the step 3 walk, whether it asks for an outline, so
that the outline pass never reads a `Style` of its own, is the same
trick that took the three-step separation above from 7 ms to zero.
Paired against the straightforward version on `features.html` it read
**+1 ms of paint one way and 0 the other** — no gain, and it is not in
the code. The same shape of change is worth a great deal in one place
and nothing a few lines away, which is why it gets measured each time
rather than assumed.

## What making an inset shadow follow the inner curve cost

An unblurred inset shadow on a rounded box is now two runs a row
between two curves where it was four straight strips, and a blurred one
is cut back to that curve one scanline at a time. Paired, both
directions:

| paint | forward | reversed |
|---|---|---|
| `generated.html`, no shadow on it at all | 0 ms of 19, 10 of 20 | 0 ms, 5 of 20 |
| `features.html`, 96 rounded figures with an inset shadow | +1 ms of 33, 13 of 25 | +1 ms |

The first row is the point of the lazy flag: `paintInsetShadows`
returns on a box with no shadow before anything else happens, and the
curve is not resolved until an `inset` shadow is actually reached, so a
box carrying only an outer shadow does not pay for a curve nothing
draws.

The second row is the feature's own cost on a page that uses it, not a
regression: the two binaries paint the same 96 shadows, one as strips
and one as runs, and the strip version is the one that paints over the
corner. `tests/featurepage.py` grew the shadow and a probe in the same
change, because nothing else on either benchmark page casts a shadow at
all — the whole of `box-shadow` was unmeasured here until now.

**And the blurred one's corner correction is another 2 ms.** Each
corner takes one more blit of an image carrying `1 - round / (fx*fy)`,
built by the same outer-integral sum an outer shadow's corner uses and
cached by the same key, so a page of identical figures builds four and
blits them 384 times:

| paint | forward | reversed |
|---|---|---|
| `generated.html`, no shadow on it | 0 ms of 18, 6 of 20 | 0 ms, 7 of 20 |
| `features.html`, 96 blurred rounded inset shadows | +2 ms of 36, 18 of 25 | +2 ms |

What it buys is the corner going from **59 units of 255 out** against
Chromium to one or two, which is the offset the outer shadows already
carry. The feature page's figures now carry both an unblurred inset
shadow and a blurred one, so the two paths are measured together and
one probe turns both off.


## What filling a rounded rectangle into a layer costs

A `border-radius` inside a clipped subtree is filled a row at a time
rather than drawn as a rectangle. Paired, forward, 20 iterations:
`generated.html` 0 ms of 19 and `features.html` 0 ms of 40.

Both zeros are structural rather than lucky: neither page has a rounded
box inside a layer, so neither reaches the path at all. **That also
makes it unmeasured**, which is the shape this file warns about
elsewhere -- a feature no page exercises reads exactly like a feature
that costs nothing. Putting `overflow: hidden` on the feature page's
`figure`, which already has a `border-radius`, would exercise it
ninety-six times over; it would also make each figure a box that paints
whole and move its inset shadow inside a layer, so it is a page change
worth making on its own rather than beside this one. todo.md carries
it.


## What restoring a page's painting flags costs

2026-09-23, same machine and script. A `Page` carries the painter's
per-document answers and puts them back before it is painted: fifteen
global writes once per paint, and one `fillAlpha` before a blurred
inset shadow's corner blits. Paired, 25 iterations, 800px.

Both pages render identically between the binaries except where the
alpha fix changes them: `generated.html` has no inset shadow at all,
and `features.html`'s figures carry one, so the second column is the
fix as well as the restore.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| forward, parent then candidate, `features.html` | +0 | +0 | -3 | +0 |
| reversed | +0 | +1 | +2 | +1 |
| forward, `generated.html` | +0 | +1 | +0 | +0 |
| reversed | +0 | +0 | -1 | +0 |

Nothing to read. The one figure worth a second look is `features.html`'s
layout, -3 forward against +2 reversed, and a change with no line in
`src/layout/` cannot make layout faster: the two are a mirror image of
each other and add to about zero, which is this file's own test for an
order effect. No control was built, the rule calling for one when a
reading survives its mirror image.

The restore is unconditional, which is why `generated.html` -- a page
that raises almost none of those answers -- is the row that matters: it
reads zero in paint, so a page that uses none of this pays nothing for
a page that does.


## What cutting a background image to the curve costs

2026-09-23, same machine and script. A layer's image is blitted back
cut to the painting area's curve rather than as a rectangle. Paired,
25 iterations, 800px. The control qualified at 0.4%.

**Neither benchmark page reaches the path**, and both render
byte-identically between the binaries: `features.html`'s rounded boxes
carry background *colours*, and the gradient pages' boxes carry no
`border-radius`. So their rows below are structural zeros -- the shape
this file warns about, where a feature no page exercises reads exactly
like a feature that costs nothing.

| | parse | cascade | layout | paint |
|---|---|---|---|---|
| forward, parent then candidate, `features.html` | +0 | -2 | +3 | -1 |
| reversed | +0 | +2 | -1 | -1 |
| forward, `generated.html` | +0 | -1 | +0 | +0 |
| reversed | +0 | +1 | -2 | -1 |

Nothing to read: every figure is mirrored by its opposite.

So the cost is measured on a page built for it: 60 boxes of 760x60
with a `border-radius` and a `linear-gradient`, which is the gradient
benchmark's shape with a radius added.

| | paint, forward | paint, reversed |
|---|---|---|
| 60 rounded gradient boxes, radius 24 | **+7 ms of 4**, 25 of 25 | **-6 ms**, 0 of 25 |
| the same, radius 6 | **+7 ms of 4**, 15 of 15 | |

**That is real and it is large**: the paint phase goes from 4 ms to 11.
A blit has no source rectangle here, so cutting one means copying the
region out of the layer first, and the box's pixels are copied twice
instead of once -- which is why the small radius costs the same as the
large one. It is not the number of regions: the rows a corner does not
reach go back as one band rather than one each, which took the radius
24 page from +9 to +7 and the radius 6 page from +9 to +7, changing no
pixel. The remaining seven milliseconds are the second copy.

A page with no `border-radius` on a box with a background image reads
one field per layer painted and blits the image whole, which is what
the two zeros above are.


## What Grid's named spans cost, and a machine that would not hold still

2026-09-23. `span <custom-ident>` resolves by counting named lines
instead of being a span of one. Per grid item that is two boolean reads
and a comparison in the placement pass; per grid axis it is one call
that hands the track list straight back unless a backwards span
actually ran off the front.

**The run is disqualified for absolute numbers and reported anyway.**
`tests/bench.sh`'s control read Chromium at 48.6 ms on
`generated.html` against the 26.0 recorded -- 86.9% out, where 15% is
allowed -- so none of its table is copied here. Nothing on this machine
was visibly running; the load average sat between 1.0 and 1.8 on four
cores with one runnable task.

The paired readings are the measurement that survives that, because
each pair runs both binaries back to back and a machine that drifts
drifts under both halves. Even so, here is the same pairing three
times, forward, on `features.html`:

| run | parse | cascade | layout | paint |
|---|---|---|---|---|
| first | +1 | +0 | **-6** | +0 |
| second | +0 | +0 | **+1** | +1 |
| third | +0 | +2 | **-3** | +0 |

and reversed once: parse +0, cascade -2, layout +5, paint +1.

**Seven milliseconds of spread between three runs of two binaries that
did not change** is the floor this reading can resolve, and it is far
above anything two boolean reads per grid item could cost. The mirror
agrees: whichever binary runs second is the slower one, forward and
reversed alike.

`generated.html` is the row worth reading, because it has no grid on it
at all and so cannot be affected by this change: forward parse +1,
cascade +2, layout -4, paint +1; reversed +0, -2, +2, +0. Four
milliseconds of layout on a page the diff cannot touch is the same
floor said another way.

Both benchmark pages render byte-identically between the binaries,
checked with `cmp` before any timing.


## What a string-aware comment scan costs, and the host's spread in one day

2026-09-23. `stripCssComments` now tracks whether it is inside a
string or an unquoted `url()`. It visits every byte of every
stylesheet, so this is the kind of change that should be measured on a
stylesheet rather than on a page.

**Neither benchmark page has a `/*` in its CSS**, so both take the
early return and only the user-agent sheet's two comments reach the new
loop. Their rows are structural again:

| `features.html` | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| forward, parent then candidate | +0 | +0 | +0 | -2 | +1 |
| reversed | +0 | +0 | +1 | -3 | +0 |

So the reading that counts is a stylesheet built for it: 970 KB, 6,000
rules, each with a comment, a string and an unquoted `url()`. Its
`stylesheets` phase is 33 ms, which is where any cost would land.

| 6,000 commented rules | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| forward | +0 | **-1** | +0 | +0 | +0 |
| reversed | +0 | **+1** | +0 | +0 | +0 |

Minus one against plus one is the order effect and nothing else: the
scan costs under a millisecond on a stylesheet approaching a megabyte.
Both pages render byte-identically between the binaries, `cmp`-checked
before any timing.

**The host moved by a factor of 2.4 in one day, and the control caught
it both ways.** Three `tests/bench.sh` runs this morning and afternoon
put Chromium's render of `generated.html` at 25.9 ms, then 48.6, then
20.0, against the 26.0 this file records. The first qualified; the
second failed the 15% band as too slow and the third as too **fast**,
which is the band working as intended -- a run where the reference
browser is a quarter quicker would have written this engine's row down
as a quarter quicker too.

None of the three later runs' numbers are copied here. What the spread
says about the band is a judgement for whoever next has this machine
quiet: 15% of 26.0 is 22.1 to 29.9, and today's host produced 20.0 and
48.6 with nothing visibly running. Either the band is too tight for
this host or the host is not one to benchmark on, and widening it to
make bad runs pass is the one answer this file has already ruled out.


## What decoding a selector's escapes costs

2026-09-23. A selector's identifiers are decoded as CSS Syntax 3 §4.3.7
says. `scanIdent` walks every name on the page either way, so the cost
is what is added to that walk. Paired, 15 iterations, 800px, on the
970 KB stylesheet of 6,000 rules built for the comment scan above --
its `stylesheets` phase is about 31 ms, which is where a cost would
land.

**The first version paid a millisecond, and the code said why rather
than a control.** It asked each identifier again, with an
`asciiIndexOf` for a backslash, after the scan had already looked at
every byte of it -- 6,000 second passes over short strings:

| | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| forward, asking twice | +0 | **+1** | +0 | +0 | +0 |
| reversed | +0 | +0 | +0 | +0 | +0 |

Plus one forward against nothing reversed is the shape this file calls
an order effect *plus* a millisecond. A placement control was built --
the parent with the two new functions appended under other names and
called from nowhere -- and **could not serve**: it came out 72 bytes
above the parent and four kilobytes below the candidate, because the
compiler removed code nothing calls. So the question went to the code,
where one extra scan per identifier is exactly the sort of thing that
costs a millisecond over six thousand of them.

The scan sets a flag instead, and the decode runs only where it saw a
backslash:

| | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| forward, asking once | +0 | +0 | +0 | +0 | +0 |
| reversed | +0 | **+1** | +0 | +0 | +0 |

Nothing left: each direction says the binary running second is the
slower one, which is the order and not the diff. The page renders
byte-identically between the binaries, `cmp`-checked before any timing.


## What skipping `<!--` costs, and a mirror image that was noise

2026-09-23. The rule loop tests two characters more per segment, at the
top level only, before it does anything else with them. Paired, 15
iterations, 800px, on the 970 KB stylesheet of 6,000 rules; its
`stylesheets` phase is about 31 ms.

| `stylesheets` | forward | reversed |
|---|---|---|
| round 1 | **+1** | **-1** |
| round 2 | +0 | +0 |

**Round one is the shape this file calls strongest for a real cost** --
a reading and its mirror image that flip sign, so both directions say
the candidate is the slower one. Round two says nothing at all, and the
code cannot account for a millisecond either: the diff adds two integer
comparisons per segment, about twelve thousand of them on this sheet,
and the `asciiStartsWith` behind each runs only where the character
already matched. No rule on the page begins with `<` or `-`.

So the mirror-image shape is not by itself evidence. It appeared here
from noise, on a diff too small to cost what it appeared to, and a
second round is what showed it. Two rounds each way is the cheaper
check than a placement control, and worth doing before building one.

The three benchmark pages render byte-identically between the binaries,
`cmp`-checked before any timing.

## What a string-aware selector list costs, and an order effect in both rounds

2026-09-23. `parseSelectorList` steps over a string and an escape before
it counts a bracket, and `parseAttrSel` decodes the name and either form
of value. Only the first of those runs on a page with no attribute
selector, and it adds two integer comparisons per character of every
prelude. Paired, 15 iterations, 800px, on the 970 KB stylesheet of 6,000
rules; its `stylesheets` phase is about 33 ms.

| `stylesheets` median | forward | reversed |
|---|---|---|
| round 1 | **-1** | **+1** |
| round 2 | **-1** | **+1** |

Both rounds agree, and both say the same thing: **the binary running
second pays a millisecond, whichever binary that is.** A cost of the
diff would read `+1` forward and `-1` reversed; this reads the opposite
sign forward, so the quantity is the order and not the code. The mean
tells the same story less tidily -- forward -0.33 and 0.00, reversed
+3.33 and +1.27 -- because one pair in fifteen runs long and the mean
carries it where the median does not.

On `generated.html`, whose stylesheet is small enough that the phase is
2 ms, `stylesheets` reads 0 both ways with means of +0.00 and -0.08.
`parse`, `cascade`, `layout` and `paint` all read non-negative in both
directions there, which is the same order effect on phases the diff has
no line in.

The benchmark pages have no attribute selector in them at all, so
`attrSelEnd` and the decoding in `parseAttrSel` never run on any of
them: what is measured above is the two comparisons in the list scan,
and nothing else. All three pages render byte-identically between the
binaries, `cmp`-checked before any timing.

## What one call in a hot function cost, and the loop it was moved out of

2026-09-23. Giving `:is()`, `:where()`, `:not()` and `:has()` a complex
selector list means an alternative is matched by `matchSelector` rather
than by `matchCompound`. Written inside `matchCompound`'s own loop over
sub-selectors, that call put the function in a cycle --
`matchCompound` → `matchSelector` → `matchFrom` → `matchCompound` --
and cost two milliseconds of cascade on a page that contains no `:is()`,
no `:not()` and no `:has()` at all.

Paired, 20 iterations, 800px, `generated.html`, whose cascade is about
34 ms and whose `collect` step runs 8,578 selector tests:

| `cascade` | forward | reversed | slower in, forward |
|---|---|---|---|
| the call inside the loop | **+2** (mean +2.10) | **-2** (mean -2.45) | 15 of 20 |
| the loop in its own function | -0 (mean -0.40) | -1 (mean -0.30) | 8 of 20 |

The first row is the shape this file calls real: a reading and its
mirror image that flip sign, and three quarters of the pairs agreeing
with the median. It is also a cost the page could not be doing the work
for -- the counts either side are identical, 8,578 selector tests and
11,614 matched declarations, and the loop that grew iterates **zero**
times on 8,576 of those tests. What changed was the code the compiler
emitted for the function around it.

Moving the loop into `matchSubSelectors`, called only when
`c.subs.length > 0`, takes it back. The second row is two non-positive
readings, which is no difference. The engine's own binary grew 40 bytes.

So the rule this file states for a feature -- that it must not cost
anything to the pages that do not use it -- has a form that is not about
passes or predicates at all: **a call added to a hot function can cost
the pages that never reach it**, and the fix is where the call is
written rather than what it does. The per-phase breakdown found it:
`collect`, which is where selector matching happens, moved and the other
steps did not.

Both binaries render `generated.html` byte-identically, `cmp`-checked
before any timing, and the machine was idle at a one-minute load under
0.25 for every reading above.

## What `:nth-child()`'s `of` clause costs, and two rounds that disagreed

2026-09-23. A compound with an `of` clause keeps it in a list of its
own, and the matcher is guarded by that list's length and lives in its
own function; a plain `:nth-child(2n+1)` still goes through `pseudos`.
Paired, 20 iterations, 800px, `generated.html`, which has no `of` clause
on it at all.

| median | round 1 forward | round 1 reversed | round 2 forward | round 2 reversed |
|---|---|---|---|---|
| `cascade` | -1 | +2 | +0 | +1 |
| `layout` | **+2** | -0 | **-2** | +2 |

Round one's layout reading is the shape this file warns about: +2
forward against a reversed nothing, 16 of 20 pairs agreeing with the
median, on a diff with **no line in `src/layout/` at all**. Round two
gives -2 forward and +2 reversed -- the same magnitude with the sign the
other way round, which no property of the code could produce. **The two
forward readings disagree with each other**, so neither is a
measurement of this diff, and the question does not go to the code.

`cascade`, the phase the diff does touch, reads non-positive forward in
both rounds and positive reversed in both, which is the order effect
this machine shows on whichever binary runs second.

That is the cheaper check the file recommends before building a
placement control, and here it was enough: a reading that does not
survive being taken twice never needed a third binary. The candidate is
4,864 bytes larger than the parent, and both render `generated.html`
and `features.html` byte-identically, `cmp`-checked before any timing,
on a machine idle at a one-minute load under 0.25.

## What twelve form-state pseudo-classes cost

2026-09-23. The whole family answers in one function reached after every
pseudo-class the engine already had, so a selector that worked before
tries no new comparison. Paired, 20 iterations, 800px, `generated.html`,
whose stylesheet names none of them.

| median | forward | reversed |
|---|---|---|
| `cascade` | +0 | -1 |
| `layout` | -1 | +0 |
| `paint` | -0 | +0 |
| `parse`, `stylesheets` | +0 | +0 |

Every phase reads zero or negative in both directions, which is no
difference in either. The binary grew 9,016 bytes and both render
`generated.html` and `features.html` byte-identically, `cmp`-checked
before any timing, on a machine idle at a one-minute load of 0.16.

## What `dir="auto"` costs

2026-09-23. The scan for a first strong character runs only where a
`:dir()` selector reaches an element that declares `auto`, and
`generated.html` has neither. Paired, 20 iterations, 800px.

| median | forward | reversed |
|---|---|---|
| `cascade` | -2 | +0 |
| `layout` | -2 | -1 |
| `parse`, `stylesheets`, `paint` | +0 | +0 |

Nothing reads positive in either direction on any phase. The binary grew
8,472 bytes and both render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing, on a machine idle at
a one-minute load of 0.19.

## What four validity conditions cost, and a second round that undid the first

2026-09-23. `controlIsValid` grew a type-mismatch scan and a step
check, and `validationValueOf` grew a walk of a select's options. None
of it runs on `generated.html`, which holds no form control at all --
`isValidationCandidate` answers no on the tag and returns. Paired, 20
iterations, 800px.

| median | round 1 forward | round 1 reversed | round 2 forward | round 2 reversed |
|---|---|---|---|---|
| `cascade` | **+2** | -1 | **-1** | +0 |
| `layout` | **+3** | +0 | **-1** | -1 |

Round one has the shape this file calls real for cascade -- +2 forward
against -1 reversed -- and a +3 of *layout* beside it on a diff with no
line in `src/layout/`. Round two gives -1 and -1 forward. **The two
forward readings disagree**, so round one was not measuring this diff,
and the rule this file already carries applies: two rounds each way
before the question goes to the code.

That is the second time in one day the same thing has happened, the
first being `:nth-child()`'s `of` clause. Both were diffs that add a
function the benchmark page never calls, and both read two to three
milliseconds on the first round and nothing on the second. A single
round on this host is not a measurement.

The binary grew 4,328 bytes and both pages render byte-identically,
`cmp`-checked before any timing, on a machine idle at a one-minute load
of 0.17.

## What an array literal in a shorthand cost, and a reading that was real

2026-09-24. The first version of the CSS-wide keyword guard passed each
shorthand's longhand names as an array literal:
`shorthandWideKeyword(props, ['font-style', 'font-weight', ...], value)`.
The literal is built on **every** call, so every `font`, `background`,
`border` and `list-style` declaration on the page paid an allocation for
a keyword it did not use. Paired, 20 iterations, 800px,
`generated.html`, whose cascade is about 35 ms.

| `cascade` median | forward | reversed | slower in, forward |
|---|---|---|---|
| the array literal | **+4** | -3 | 15 of 20 |
| the same, second round | **+3** | -2 | 17 of 20 |
| moving the rank lookup out of the loop as well | +4 | -2 | 17 of 20 |
| the names written out, no array | **+0** | +0 | 9 of 20 |

**This is the first reading this file has recorded that survives its own
second round**, and it is the one the rule above was written for: two
forward rounds agreeing at +4 and +3, against a mirror image of -3 and
-2, with three quarters of the pairs on one side and a tenth on the
other. The two readings before it in this file had the same shapes on
their first round and were contradicted by their second.

**The first guess about the cause was wrong, and the benchmark said so.**
The change also added `cssLayerRankOf` to the loop over matched
declarations, which is the shape the previous entry blames for two
milliseconds, so that was moved out first -- and the reading did not
move at all. Only writing the longhand names out, so that nothing is
allocated unless the keyword is actually there, took it to nothing. The
rank lookup stays out of the loop because reading a global once per rule
is plainly cheaper than once per declaration, not because a measurement
said so.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing, on a machine idle at
a one-minute load under 0.25 for every reading above.

## What two shorthand expansions cost, and a control that read the whole of it

2026-09-24. `text-decoration` expanding into its four longhands, and
`place-items`, `place-content` and `place-self` expanding into theirs,
both inside `applyDecl` -- which runs once per matched declaration,
11,614 of them on `generated.html`. The `place-` comparisons are behind
a per-document flag; the one `text-decoration` comparison is not,
because the user-agent stylesheet says `text-decoration` on four
selectors and a flag would be true on every page. Paired, 20
iterations, 800px, `generated.html`, whose cascade is about 35 ms and
whose layout is about 62.

| pairing | `cascade` median | `layout` median | slower in, layout |
|---|---|---|---|
| candidate against parent, round one | +0 | -0 | 9 of 20 |
| the same, round two | +1 | **+2** | 12 of 20 |
| the same, round three | +1 | **+2** | 16 of 20 |
| reversed (parent second) | +0 | -1 | 8 of 20 |
| **control** against parent | +0 | -1 | 7 of 20 |
| candidate against **control** | **+0** | **-2** | 6 of 20 |

Round one disagreed with rounds two and three, which is the rule about
first rounds working as advertised in the other direction: here the
*first* round was the one that matched the answer. Two forward rounds
then agreed at +1 of cascade and +2 of layout, with 12 and 16 of 20
pairs on one side, which is the shape this file calls real -- and the
diff has no line in `src/layout/` at all, so there was nowhere to take
the question.

The control settles it. It is the parent recompiled with the change's
global and both expansions appended as one function under renamed
identifiers, **called from nowhere**: 3,167,288 bytes against the
candidate's 3,167,248, forty apart. Dead code cannot run, and the
candidate against it reads +0 of cascade with the pairs split ten and
ten, and -2 of layout. The three binaries do not add up -- parent to
control is -1 of layout, control to candidate -2, and parent to
candidate +2 -- which is what says the quantity belongs to none of
them. The extra comparison costs nothing this page can measure.

All three binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing, on a machine idle at
a one-minute load of 0.18 for every reading above.

### The control is reading low on this host, and the table was not refreshed

2026-09-24. `tests/bench.sh` disqualified itself twice in a row on an
idle machine, both times for the same reason and in the same direction:
Chromium rendered `generated.html` in 21.7 ms and then 20.2 ms against
the 26.0 this file records, 16.5% and 22.3% out of a band of 15%. The
control exists to catch a contended run, which reads *high* -- 93 ms on
the day it was written. A reading this far below the band says the host
is not the host the 26.0 was measured on.

Chromium is the same build the property audit names, 141.0.7390.37, so
this is not a new reference browser and `CONTROL_MS` is not raised for
it. Nothing from either run is copied into the table above, which
therefore still says what the last qualifying run said. The paired
reading in the section before this one is unaffected: it times two
binaries of this browser against each other in the same minutes, so a
host that is uniformly quicker moves both terms.

## What expanding `white-space` and `text-wrap` cost, and two rounds that disagreed

2026-09-24. Both shorthands moved out of the style readers and into
`applyDecl`, which runs once per matched declaration -- 11,614 of them
on `generated.html`. Two name comparisons added there and two
`styleProp` lookups taken out of the readers, so the change is close to
a wash by construction; the two binaries come out the same size to the
byte, 3,167,248 each. Paired, 20 iterations, 800px.

| pairing | `cascade` median | `layout` median | slower in, cascade |
|---|---|---|---|
| candidate against parent, round one | +1 | +1 | 11 of 20 |
| the same, round two | -0 | +0 | 9 of 20 |
| reversed (parent second) | -1 | +0 | 6 of 20 |

**The two forward rounds disagree**, so under this file's own rule
nothing here earns a question to the code, and no control was built.
Round one's +1 came with eleven pairs of twenty on one side, which is a
coin; round two put nine there. The reversed pairing's -1 of cascade
with six of twenty is the same coin landing the other way. A reading
that needs three quarters of the pairs to agree before it is believed
does not have them in any of the three rounds.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing, on a machine idle at
a one-minute load of 0.24 for every reading above.

## What expanding eight shorthands cost, and a control that carried the whole millisecond

2026-09-24. Eight shorthands moved out of the style readers and into
`applyDecl`, behind one per-document flag. `generated.html` says
`border-radius` on every card, so the flag is true there and the
expansions do real work rather than only being skipped. Paired, 20
iterations, 800px.

| pairing | `cascade` median | `layout` median | slower in, layout |
|---|---|---|---|
| candidate against parent, round one | +0 | **+1** | 12 of 20 |
| the same, round two | +1 | **+1** | 11 of 20 |
| reversed (parent second) | +0 | **-1** | 6 of 20 |
| **control** against parent | -1 | **+1** | 12 of 20 |
| candidate against **control** | +1 | +1 | 11 of 20 |

Two forward rounds agreeing at +1 of layout against a mirror image of
-1 is the shape this file calls strongest for a real cost, and the diff
has no line in `src/layout/`. The control is where it goes: the parent
recompiled with the change's global, its helper and all eight
expansions appended as one function under renamed identifiers and
**called from nowhere** reads the same +1 of layout, with the same
twelve pairs of twenty. Dead code cannot run.

The three binaries then refuse to add up -- parent to control +1 of
layout, control to candidate +1, and parent to candidate +1 rather than
the +2 those two imply -- which is the test this file already uses for
a quantity that belongs to no diff.

**This control is not as tight as the rule asks for.** It comes out
3,175,912 bytes against the candidate's 3,171,768, four kilobytes
apart rather than a few dozen, because the change *removes* eight
readers as well as adding eight expansions and a control can only add.
A change that deletes code cannot have a control within a few bytes of
it, so the size agreement that usually backs this argument is missing
here and the additivity check is carrying it alone.

All three binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing, on a machine idle at
a one-minute load of 0.20 for every reading above.

## What two more shorthands cost, and a third pair of rounds that disagreed

2026-09-24. `column-rule` and `contain-intrinsic-size` expanded in
`applyDecl`, behind the flag the eight before them share, with two more
prefixes added to the parser's test for it. The binaries come out 256
bytes apart, 3,172,024 against 3,171,768. Paired, 20 iterations, 800px.

| pairing | `cascade` median | `layout` median | slower in, cascade |
|---|---|---|---|
| candidate against parent, round one | +1 | +0 | 11 of 20 |
| the same, round two | +0 | -0 | 10 of 20 |
| reversed (parent second) | +0 | -1 | 8 of 20 |

Round one's +1 of cascade came with eleven pairs of twenty and round
two put ten there, which is a coin landing twice. The two forward
rounds disagree, so nothing here earns a question to the code and no
control was built -- the third time in this file that a first-round
reading has failed to survive being run again, and the second time this
week.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing, on a machine idle at
a one-minute load of 0.19 for every reading above.

## Two constants move 61% of the binary, and a diff the page cannot reach reads +1

2026-09-24. `cm` and `mm` changed from the constants 37.8 and 3.78 to
`96.0 / 2.54` and `96.0 / 25.4`. Neither `generated.html` nor
`features.html` contains a centimetre or a millimetre, so **this diff
cannot execute on either page**: whatever a paired run reads, it is not
work.

| pairing | `parse` | `cascade` | `layout` | slower in, layout |
|---|---|---|---|---|
| candidate against parent, round one | +0 | -0 | +0 | 10 of 20 |
| the same, round two | **+1** | +0 | **+1** | 11 of 20 |
| reversed (parent second) | +0 | +0 | +0 | 9 of 20 |

Round two read a millisecond of parse and a millisecond of layout out
of two float constants in a branch the page never enters. The rounds
disagree, so the rule already in this file throws it out -- but it is
the cleanest demonstration this file has of *why* that rule exists,
because here the "is it real work?" question has an answer known in
advance and the answer is no.

**And the mechanism is measurable.** The Festina compiler is
deterministic: the same source compiled twice gives byte-identical
output, and adding a comment to a source file changes **zero** bytes of
the binary. Changing those two float constants changes **1,948,895 of
3,172,024 bytes -- 61% of the binary -- at exactly the same total
size.** Nothing moved in or out; six bytes of the sixty-one per cent
are the constants and the rest is the compiler laying the same program
out differently.

That is the thing benchmarks.md has been calling "the compiler moving
code" since `print-color-adjust`, stated as a number rather than an
inference. A control binary within a few bytes of the candidate is not
within a few bytes of it *in layout*, and two binaries of identical
size can share almost none of their addresses. It is why a millisecond
that survives two rounds and its own mirror image still has to be put
to a control, and why a control that reads the same millisecond settles
the question rather than deepening it.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing, on a machine idle at
a one-minute load of 0.22 for every reading above.

## What blockification cost, on the one page it does not change

2026-09-24. Blockification (Display 3 sec. 2.7) adds four integer tests
to every element's computed style and one flag test to every child of
every block. Paired, 20 iterations, 800px.

**Measured on `generated.html` alone, because the fix changes
`features.html`.** That page has a `display: grid` whose first item is
an `<img>`; blockified, the image is a block-level grid item and gets
painted, where before it stayed inline and did not appear at all. Seven
64-pixel bands of the render change, one per section. A paired reading
needs the two binaries laying out the same document, and they no longer
do -- which is this file's own rule about a feature that fixes the
layout, and the reason the render suite and `--verify` keep the page
the fix touches while the benchmark uses the page it does not.

| pairing | `cascade` median | `layout` median | slower in, layout |
|---|---|---|---|
| candidate against parent, round one | +0 | **+2** | 13 of 20 |
| the same, round two | +1 | +0 | 9 of 20 |
| reversed (parent second) | **+2** | -1 | 7 of 20 |

The two forward rounds disagree on layout, so that reading is thrown
out unexamined. The cascade reading is worse than disagreeing: it is
+1 forward and +2 reversed, both positive, which is the definition this
file gives of an order effect -- whichever binary runs second pays --
rather than a difference between the two binaries. No control was
built, because nothing here survived the checks that come before one.

The two binaries render `generated.html` byte-identically,
`cmp`-checked before any timing, on a machine idle at a one-minute load
of 0.19 for every reading above. They do **not** render
`features.html` identically, which is the point above.

## What a test in `resolveLen` cost, and where it went instead

2026-09-24. The intrinsic sizing keywords need `resolveLen` to answer
`dflt` for the new `LEN_INTRINSIC` kind, and the obvious place for that
test is the line that already answers `dflt` for `auto`:

```
if l == null || l.kind == LEN_AUTO || l.kind == LEN_INTRINSIC { return dflt }
```

`resolveLen` is called for every length of every box. Paired against
the parent, 20 iterations, 800px, `generated.html`:

| pairing | `cascade` median | `layout` median | slower in, layout |
|---|---|---|---|
| beside `auto`, forward one | +0 | **+2** | 11 of 20 |
| the same, forward two | +1 | **+1** | 12 of 20 |
| the same, reversed | +0 | **-2** | 5 of 20 |
| **off the hot path**, forward one | +1 | +0 | 10 of 20 |
| the same, forward two | +0 | +0 | 10 of 20 |
| the same, reversed | +2 | +1 | 12 of 20 |

Two forward rounds agreeing at +1 and +2 against a mirror image of -2
is the shape this file calls strongest, and here the question had
somewhere to go: one comparison, in a function every box calls for
every length it has. No control was needed, because the fix is its own
control -- the same feature with the test moved reads +0 twice
forward, with the pairs split ten and ten.

Moved means `LEN_PX` now returns from a line of its own, before the
chain, so the intrinsic test sits after the four kinds that are
common and costs nothing to any of them. The cascade column is +1 and
+0 forward against +2 reversed, positive in both directions, which is
this file's definition of an order effect rather than a difference.

This is the third time the rule about a test or a call added to a hot
function has been paid for: `matchSelector` inside `matchCompound`'s
loop, the array literal in the shorthand guard, and now one integer
comparison in `resolveLen`. The first two were found by a benchmark
after the fact; this one was predicted from the rule and then
confirmed, which is the first time that has happened in this file.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing, on a machine idle at
a one-minute load of 0.20 for every reading above.

## What `position: sticky` cost, and a control that was the same size to the byte

`position: sticky` adds one test to `paintBox`, which runs once per box
painted, and one to `hitChild`, which runs once per box a click is
tested against. Both are `anySticky && ...`, so a page that never says
the word stops at the boolean -- the shape the rule about a call added
to a hot function exists to catch, because the call it guards,
`paintSticky`, calls `paintBox` back.

Paired against the revision before it, twenty-five alternating samples
on `features.html` at 800px, on a machine idle at a one-minute load of
0.15 to 0.18. Two forward rounds and the mirror image:

| | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| forward, round 1 | 0 | 0 | -1 | **-2** | **+1** |
| forward, round 2 | 0 | 0 | 0 | **-2** | **+1** |
| reversed | 0 | 0 | 0 | **+3** | **-1** |

Two forward rounds agreeing is what this file asks for before a reading
earns a question, and both survived the mirror image: forward -2 against
reversed +3 leaves the candidate about two and a half milliseconds
*faster* in layout, and forward +1 against reversed -1 leaves it one
millisecond slower in paint.

The layout number is the giveaway. **The diff has no line in
`src/layout/` at all**, so a reading there cannot be work, and this
file has recorded twice before that it is the compiler putting the
machine code somewhere else. The control settles both together:
the parent recompiled with this change's globals, its `DocFlags` field
and both its functions renamed and **called from nowhere**, which comes
out at 3,176,456 bytes -- the candidate's size to the byte. Paired
against that:

| | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| forward, round 1 | 0 | -1 | 0 | **+1** | 0 |
| forward, round 2 | -1 | 0 | +1 | 0 | 0 |
| reversed | 0 | 0 | 0 | **+2** | 0 |

The two forward rounds no longer agree on anything, so nothing earns a
question. Paint, which read +1 against the parent in both forward
rounds and -1 reversed, reads **zero in all three** against a binary
holding the same code in the same amount of it. So the millisecond of
paint was never the two boolean tests: it was where the compiler put
them, and the two and a half of layout was the same thing with the
opposite sign.

All three binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing. `tests/bench.sh`
qualified its own run at 8.5% against `CONTROL_MS`, inside the 15% it
allows.

## What `polygon()`'s fill rule cost, and a quantity that did not add up across four binaries

The fill rule adds a `bool` to `ClipShape`, which is a **by-value field
of `Style`** -- the struct the `corner-shape` section above found costs
layout milliseconds when it grows, because `Style` is dereferenced once
per box. It also adds one array push per crossing and one branch per
row inside `shapeSpanAt`'s polygon branch. `features.html` contains no
`polygon(` at all, so none of the second group runs on it, and the
first group is the question this section is about.

Paired against the revision before it, twenty-five alternating samples
at 800px on a machine idle at a one-minute load of 0.20 to 0.24:

| | cascade | layout | paint |
|---|---|---|---|
| forward, round 1 | 0 | **+4** | **+1** |
| forward, round 2 | +1 | **+3** | **+2** |
| reversed | -1 | **-1** | 0 |

Two forward rounds agreeing is what earns a reading a question here, and
these survive the mirror image as well: about two and a quarter
milliseconds of layout and three quarters of paint. On a page with no
`polygon()` on it, and from a diff whose only line outside
`src/css/shapes.f` is in the CSS parser.

The `corner-shape` precedent says to suspect the struct, so the parent
was recompiled with **the same `bool` added to `ClipShape` and never
read**, which comes out at 3,176,456 bytes -- the parent's size exactly,
where the candidate is 3,176,496. Against that:

| | cascade | layout | paint |
|---|---|---|---|
| padded parent, round 1 | -1 | **-2** | 0 |
| padded parent, round 2 | +2 | **+1** | 0 |
| candidate vs padded parent | +1 | **+2** | -1 |

The two padded rounds disagree with each other, which by this file's own
rule means nothing earns a question: **the field alone does not
reproduce it.** So across four binaries the same phase reads -2, +1, +2,
+3 and +4 forward and -1 reversed, on a page that cannot reach a line of
the new code. A quantity that does not add up across four binaries is
not a property of any one diff, which is the conclusion the
`print-color-adjust` section reached from three.

What is left is the forty bytes. This is the clearest instance yet of
the effect that section named, because here there are two controls
rather than one and they point in opposite directions: the struct
growth alone is free, and the code's mere presence moves a phase it
never runs in.

**What is not measured here** is the cost to a page that *does* use
`polygon()`: one array push per crossing and one branch per row, on a
path that runs only for `clip-path: polygon()` and `shape-outside:
polygon()`. A page with enough polygons to lift that out of the noise
is not one of the benchmark pages, and inventing one to measure against
itself would not say anything the arithmetic does not. It is recorded
rather than claimed to be free.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## What `inset()`'s `round` radius cost, and a reading that came out negative

The radius adds one integer test to `shapeSpansAt`'s rectangle branch
and one to `paintShaped`, both asking whether the corners are square, and
one `int` to `ClipShape` -- which is a by-value field of `Style`, the
struct the `corner-shape` section found costs layout when it grows. It
also moves `cornerInset` and `radiusShrink` out of the painter and into
`src/css/shapes.f`, which changes nothing about what runs and everything
about where the compiler puts it: the binary grows 4,528 bytes.
`features.html` contains no `inset(` at all.

Twenty-five alternating samples at 800px, machine idle at a one-minute
load of 0.20 to 0.39:

| | cascade | layout | paint |
|---|---|---|---|
| forward, round 1 | -1 | **+3** | -1 |
| forward, round 2 | -1 | **-1** | -1 |
| reversed | +2 | **0** | +1 |

Layout's two forward rounds disagree with each other, so by this file's
own rule nothing there earns a question. What does survive is cascade
and paint -- both agreeing across two forward rounds and both flipping
sign in the mirror, which is the shape this file calls real. And both
say the candidate is about a millisecond **faster**.

That settles it without a control. A change cannot make a page faster by
adding code the page never reaches, and this page never reaches a line
of it. The reading is where the compiler put four and a half kilobytes,
in the same direction as the negative layout readings the
`polygon()` section above collected from four binaries. It is recorded
here because a benchmark that only ever reports costs is not being run
honestly, and a phantom with a sign is still a phantom.

**Not measured**: what a page that does use `inset(... round ...)` pays.
A rounded rectangle now takes the scanline path instead of one blit,
which is a real cost to that page and by construction not to any other
-- `paintShaped` asks whether the corners are square, so every square
`inset()` still takes the blit. No benchmark page carries one, and
building a page to measure against itself would say nothing the
arithmetic does not.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## What `scroll-snap-stop` cost, and a triangle that does not close

The property adds one `bool` to `Style` -- the struct the `corner-shape`
section found costs layout when it grows -- and one `if
c.style.snapStopAlways` inside `snapPosition`'s loop over a container's
children. That loop runs on a scroll gesture and nowhere else;
`features.html` contains no `scroll-snap` at all, so it never runs here.
The binary grows 112 bytes.

Twenty-five alternating samples at 800px, idle at 0.19 to 0.56. Note
that the baselines are lower than the sections above -- cascade 35
against 41, layout 76 against 87 -- because the machine was quicker this
hour, which is the whole reason a comparison is paired rather than read
off two days' tables.

| | cascade | layout | **paint** |
|---|---|---|---|
| forward, round 1 | 0 | +1 | **+1** |
| forward, round 2 | 0 | -2 | **+1** |
| reversed | -1 | +1 | **0** |

Layout's forward rounds disagree, so nothing there earns a question.
Paint does: +1 twice forward against 0 reversed is, in this file's own
words, an order effect *plus* a millisecond -- about half of one after
the two are separated. And `snapPosition` is never called during paint.

Two controls, both by the `corner-shape` method:

| | paint, round 1 | paint, round 2 |
|---|---|---|
| parent vs parent + the `bool`, never read | 0 | -1 |
| that padded parent vs the candidate | 0 | -1 |

Neither pair agrees with itself, so neither the struct growth nor the
code earns a question. **The triangle does not close**: parent to
candidate reads about +0.5 of paint, parent to padded reads nothing, and
padded to candidate reads nothing. Nothing plus nothing is not a half.

That is the `print-color-adjust` conclusion reached a third time this
session, and by now it is less a finding than a property of the
instrument: a sub-millisecond reading on a phase that executes no line
of the change, not reproduced by either half of it, is where the
compiler put a hundred bytes. The useful rule it leaves behind is the
one already written down -- take the question to the code only when the
code can answer it, and check first whether the phase that moved runs
any of the diff at all.

**Not measured**: what a page that uses `scroll-snap-type: mandatory`
pays per gesture, which is one boolean test per snap child. A gesture is
one wheel event and the benchmark renders a page rather than scrolling
it, so there is no paired reading to be had; the cost is one comparison
in a loop that already resolves four lengths per child.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## What `offset-path: url()` cost, and the fourth shape of one effect

`features.html` contains no `offset-path`, so nothing the change adds
runs on it; the binary grows 4,168 bytes. Twenty-five alternating
samples at 800px, idle at 0.20 to 0.51:

| | cascade | layout | paint |
|---|---|---|---|
| forward, round 1 | **-1** | **-2** | 0 |
| forward, round 2 | **-2** | **-2** | +1 |
| reversed | **+1** | **+1** | 0 |

Paint's forward rounds disagree, so nothing there earns a question.
Cascade and layout both agree across two forward rounds and both flip
sign in the mirror, leaving the candidate about a millisecond and a half
faster in each -- on a page that reaches no line of the diff.

That settles itself without a control, exactly as the `inset()` section
above did: a change cannot make a page faster by adding code the page
never runs. No further apparatus is spent on it.

This is the fourth shape the same effect has taken in this file, and
they are worth listing together, because the collection is now the
evidence rather than any one of them:

| | how it showed |
|---|---|
| `print-color-adjust` | a quantity that did not add up across three binaries |
| `polygon()`'s fill rule | four binaries, the struct-padding control flat |
| `inset()`'s `round` radius | a reading that came out **negative** |
| `scroll-snap-stop` | a triangle that did not close |
| `offset-path: url()` | negative again, in two phases at once |

The rule they have converged on is short enough to keep: **before taking
a reading to the code, check whether the phase that moved runs any of
the diff at all.** Four of the five above fail that test immediately,
and the fifth had no line in the phase either.

**Not measured**: what a page that uses `offset-path: url()` pays. The
reference is resolved once per element that declares one, at cascade
time, by a walk of the document for a matching `<path>` -- linear in the
document for each such declaration. No benchmark page carries one, and a
page built to measure it against itself would say nothing the shape of
the walk does not.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## What an SVG shape in a `url()` motion path cost: nothing, plainly

`features.html` has no `offset-path`. Twenty-five alternating samples at
800px, idle at 0.22:

| | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| forward, round 1 | 0 | 0 | 0 | 0 | 0 |
| forward, round 2 | 0 | 0 | -1 | +1 | 0 |
| reversed | 0 | 0 | -1 | +1 | 0 |

The two forward rounds disagree on both phases that moved at all, so
nothing earns a question, and paint reads zero in all three. No control
is needed and none was built.

Worth one line because it is the counter-example to the five sections
above: the same machine, the same page, the same twenty-five pairs, and
a diff of 4,216 bytes produced **no** phantom. Whatever the compiler
does with a few kilobytes, it does not do it every time -- which is why
the rule those sections converged on is to check whether the phase that
moved runs any of the diff, rather than to expect a reading at all.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## The same number of bytes, arranged differently, reads half a millisecond

`<rect>`, `<line>` and `<polyline>` as motion paths. `features.html` has
no `offset-path`, so none of it runs there. Twenty-five alternating
samples at 800px, idle at 0.23:

| | cascade | layout | paint |
|---|---|---|---|
| forward, round 1 | 0 | 0 | **-1** |
| forward, round 2 | 0 | -2 | **-1** |
| reversed | 0 | -1 | **0** |

Layout's forward rounds disagree, so nothing there. Paint agrees across
both and flips in the mirror, leaving the candidate about half a
millisecond faster on a page that reaches none of it -- the negative
sign that settles itself, for the third time in this file.

What makes this one worth its own section is the binaries. Both are
**3,189,520 bytes**, to the byte, and `cmp` says they differ in content.
Every earlier section could point at a size change -- forty bytes, a
hundred and twelve, four thousand -- as the thing the compiler had to
rearrange around. Here there is no size change at all. The same number
of bytes, laid out differently, moves half a millisecond of a phase the
diff never executes.

That is the cleanest statement of the effect this file has: it is not
about how much code a change adds. It is about the code moving.
Together with the null result in the section above -- a 4,216-byte diff
that produced nothing -- the pair says the reading has no relationship
to the size of the diff in either direction.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## The control that the standing rule had already made unnecessary

A `<rect>`'s `rx` and `ry` on a motion path. The change is entirely in
`src/css/cascade.f`, and `features.html` has no `offset-path`, so
nothing it adds runs there. Twenty-five alternating samples at 800px,
idle at 0.22 to 0.23:

| | cascade | layout | paint |
|---|---|---|---|
| forward, round 1 | +1 | **+3** | -1 |
| forward, round 2 | -1 | **+1** | 0 |
| reversed | -1 | **-3** | 0 |

Cascade flips sign between the forward rounds, so nothing there. Layout
stays positive across both and reverses cleanly, which is the shape this
file has called strongest for a real cost: a reading and its mirror
adding to about zero.

It is not one, and the way that was established is the point of the
section. The rule these pages converged on is to ask, before taking a
reading to the code, whether the phase that moved runs any of the diff.
Layout does not: there is no line of `src/layout/` in the change, and no
line of the change is reachable from a page without an `offset-path`.
That answer was available before the first round was run.

A control was built anyway -- the parent recompiled with the change's
constant and three functions renamed and **called from nowhere**,
3,189,688 bytes against the candidate's 3,189,640, rendering both pages
byte-identically. It reads **layout +2** against the parent over 16 of
25 pairs. Dead code cannot run, so those two milliseconds are where the
compiler put the machine code. And the three binaries do not add up:
parent to candidate is +3, parent to control +2, control to candidate
+2, where the first should be the sum of the other two. A quantity that
is not additive across three binaries is not a property of any one of
them.

So the entry in this file is not the phantom, which is the eighth of its
kind and says nothing the seven before it did not. It is that the rule
worked and was not used. The cost of re-deriving a known result was four
benchmark rounds and a control build, against one reading of the diff,
and the reason it happened is that the mirror image is a compelling
shape to look at. The order matters: ask whether the phase runs the diff
**first**, and let the shape of the reading be the thing that has to
survive that question rather than the thing that prompts it.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## The colour filters cost the pages that have none nothing, measured

CSS Filter Effects 1's eight colour functions. Unlike most of the
sections above this one, the change does put something in the hot path:
`paintFill` gains a guard on every fill, and `boxPaintsWhole` gains a
test asked of every box in every paint walk. So the question is a real
one here rather than a phantom hunt.

Twenty-five alternating samples at 800px, idle at 0.16 to 0.24, on both
benchmark pages, neither of which carries a `filter`:

| | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| `features.html`, round 1 | 0 | 0 | 0 | -1 | **0** |
| `features.html`, round 2 | 0 | 0 | 0 | 0 | **0** |
| `generated.html` | 0 | 0 | 0 | +1 | **0** |

Paint is the phase to read and it is zero on every round. The two
forward rounds on `features.html` agree with each other at zero on every
phase, so nothing earns a question and no mirror or control was spent --
which is the rule from the section above this one being followed rather
than restated. Layout's -1 and +1 are one round each and land on a phase
that runs no line of the diff.

The guard is what makes this so, and it is written the way the
`:is()` section argued for: `anyFilter && paintFilters.length > 0` at
each call site, short-circuiting, rather than a call into a function
that decides. A page with no `filter` never reaches the filter code and
never makes the call to find that out.

The binary grows 9,536 bytes, the largest of any change measured on
these pages, and moves nothing. Both binaries render `generated.html`
and `features.html` byte-identically, `cmp`-checked before any timing.

## The masks cost nothing either, and the rounds disagreed on their own

CSS Masking 1's `mask` over a linear gradient. Like the filters before
it, this change puts something in the hot path: `paintBox` gains a guard
on every box and `boxPaintsWhole` a test asked of every box in every
paint walk. Twenty-five alternating samples at 800px, idle at 0.20 to
0.24, on the two benchmark pages, neither of which carries a `mask`:

| | parse | stylesheets | cascade | layout | paint |
|---|---|---|---|---|---|
| `features.html`, round 1 | 0 | 0 | +1 | +1 | **0** |
| `features.html`, round 2 | 0 | 0 | 0 | -1 | **-1** |
| `generated.html` | 0 | 0 | 0 | 0 | **0** |

The two forward rounds on `features.html` disagree on every phase that
moved at all, so nothing earns a question and no mirror or control was
spent. `generated.html` reads zero on all five. Paint is the phase to
watch, being where the guard is, and it reads 0, then -1, then 0.

The binary grows 17,888 bytes, larger again than the colour filters, and
moves nothing. That is now the fourth reading in this file saying the
same thing about size, and the second in a row where the change really
did touch a hot loop and the answer was still nothing -- which is what a
short-circuiting guard at the call site is supposed to buy, and the
second time it has been checked rather than assumed.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## A radial and conic mask, on pages that reach no mask at all

One line. The change adds nothing to the per-box or per-fill path --
every line of it is inside `paintMasked`, which neither benchmark page
enters, since neither carries a `mask`. The rule this file arrived at
says that settles it before any round is run, and the rounds agree by
disagreeing: layout reads -2 then 0, paint -1 then +1, cascade 0 then
+1, over twenty-five alternating samples at 800px each. Nothing earned a
question; no mirror, no control. The binary grows 4,448 bytes.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## mask-composite, and a binary that got smaller

The rule again, and again in one line: every line of the change is
inside the mask code, which neither benchmark page enters. Twenty-five
alternating samples at 800px, twice: layout -3 then 0, paint -1 then 0,
cascade 0 then -1. The forward rounds disagree on every phase that moved
at all, so nothing earned a question and no mirror or control was spent.

One thing is worth a sentence. The binary **shrank** by 368 bytes while
gaining a feature, because the layer resolution moved out of eighteen
module globals into one `MaskPrep` struct held in an array. Every other
entry in this file records a change that grew the binary and moved no
time; this is the first that shrank it and moved no time either, which
is the same conclusion from the other side.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## The strongest shape this file recognises, from code that cannot run

CSS2 §9.9's hoisting, with `isolation`. This one is worth the space,
because it produced every signal this file calls real and was still
nothing.

Paired against its parent on `features.html`, twenty-five alternating
samples at 800px on an idle machine, paint read **+2** (19 of 25) and
then **+3** (19 of 25) — two forward rounds agreeing — and the mirror
read **-3** (5 of 25), which cancels. Two agreeing forward rounds plus a
cancelling mirror is the shape this file's own rules call a real cost,
and paint is a phase that genuinely runs this diff, so there was nowhere
left to send the question but the code.

The code said no. Removing the hoist descent alone — the one line that
adds a structural walk — moved paint by **0** (9 of 25). Recompiling the
parent with the change's global, its eight functions and its modified
`boxIsStackingContext` appended under different names and **called from
nowhere** gave a binary 248 bytes from the candidate's; paired against
that control, paint read +2 (19 of 25), +1 (14 of 25), +2 (19 of 25),
and the mirror -1 (10 of 25). Summing the five phases per sample, which
this pairing did for the first time, the same three rounds read 0, +8
and — mirrored — +4: the second binary to run pays, whichever it is.

What settles it costs nothing to run. `generated.html` declares no
`position` anywhere, so `docHasPositioned` is false and **not one line
of the change executes on it**. Paint there:

| | parse | stylesheets | cascade | layout | paint | total |
|---|---|---|---|---|---|---|
| round 1 | 0 | 0 | -1 | 0 | **+1** (21 of 25) | +1 |
| round 2 | 0 | 0 | -1 | 0 | **+1** (17 of 25) | 0 |

Two forward rounds agreeing on a millisecond of paint, on a page whose
paint is 17 ms, from code the page cannot reach. That is a sixth of the
phase, and it is where the compiler put the machine code.

So a second control exists beside the dead-code one, and it is cheaper:
**pair the same two binaries on a page that cannot reach the change.**
No recompile, no renaming, and it answers the same question — whether a
reading is work or placement — from the other end. It is only available
when such a page exists, which is why the dead-code control stays.

The binary grows 4,248 bytes. Both binaries render `generated.html` and
`features.html` byte-identically, and so does the control and the
descent-removed probe; every one was `cmp`-checked before any timing.

## A vertical writing mode, on two pages that stay horizontal

CSS Writing Modes 4's `writing-mode`. Unlike the four entries above it,
this change does put something on the path every page walks: a guard in
`resolveEdges`, which runs for every box of every page, two more in the
definite-height helpers, one in `drawFragmentGlyphs`, which runs for
every text fragment, and three ternaries in `layoutBlock`. None of them
is a call -- each is `anyVerticalWM && ...`, answered on the first term
by a page that never says `writing-mode` -- but the test itself is real
work, and neither benchmark page says it.

Twenty-five alternating samples at 800px, idle at 0.23, with the five
phases summed per sample as well:

| | parse | stylesheets | cascade | layout | paint | total |
|---|---|---|---|---|---|---|
| `features.html`, round 1 | 0 | 0 | +1 | 0 | -1 | **-2** |
| `features.html`, round 2 | -1 | 0 | 0 | -2 | 0 | **-4** |
| `generated.html` | 0 | 0 | -2 | -2 | 0 | **-5** |

The two forward rounds disagree on every phase that moved at all --
cascade +1 then 0, layout 0 then -2, paint -1 then 0 -- so nothing
earned a question and no mirror or control was spent. Both totals are
negative, as is `generated.html`'s on all five phases.

The binary grows 9,120 bytes. Both binaries render `generated.html` and
`features.html` byte-identically, `cmp`-checked before any timing.

## An upright cell, and a reading in a phase that cannot have it

`text-orientation: upright`. Its guard sits at the top of
`measureWidth`, which is the hottest function in layout -- the width
cache exists because of how often it is asked -- so the guard is a
boolean before the cache lookup rather than a call, and neither
benchmark page says `writing-mode`.

Twenty-five alternating samples at 800px, idle, the five phases summed
per sample as well:

| | parse | stylesheets | cascade | layout | paint | total |
|---|---|---|---|---|---|---|
| `features.html`, round 1 | +1 | 0 | **+2** (18 of 25) | +1 | 0 | +5 |
| `features.html`, round 2 | 0 | 0 | **+1** (14 of 25) | -2 | 0 | +1 |
| `generated.html` | 0 | 0 | 0 | 0 | +1 | -5 |

The two forward rounds on `features.html` agree, weakly, on **cascade**:
+2 at 18 of 25 and then +1 at 14. That is the shape this file usually
takes to the code, and there is nothing to take it to. **Cascade runs no
line of this diff**: every line is in `measureWidth`, which layout calls,
and in `drawFragmentGlyphsVertical`, which the painter calls. The two
phases that do run it read +1 then -2 and 0 then 0.

So the order of the questions matters, and this is the case that shows
it: asking *which phase moved* and *whether that phase runs the diff*
settles a reading that looking at its shape would have sent to the code.
`generated.html` agrees by reading nothing on any phase and -5 in total.

The binary grows 168 bytes -- the smallest of any change measured here,
which is what a ratio, a multiply and two branches come to. Both
binaries render `generated.html` and `features.html` byte-identically,
`cmp`-checked before any timing.

## A vertical run's decoration lines, on pages whose runs are horizontal

The guard is one boolean at the top of `paintDecorationLines`, which
runs once per decorated fragment rather than once per fragment, so it is
the lightest touch of the three writing-mode changes. Twenty-five
alternating samples at 800px, idle, the five phases summed per sample:

| | parse | stylesheets | cascade | layout | paint | total |
|---|---|---|---|---|---|---|
| `features.html`, round 1 | 0 | 0 | +1 | +4 | 0 | +2 |
| `features.html`, round 2 | 0 | 0 | 0 | 0 | 0 | +1 |
| `generated.html` | 0 | 0 | 0 | 0 | -1 | -5 |

The two forward rounds disagree on both phases that moved -- layout +4
then 0, cascade +1 then 0 -- so nothing earned a question, and neither
phase runs a line of a diff that is entirely in the painter. Paint,
which does run it, reads 0, 0 and -1. The binary grows 144 bytes.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## The emphasis marks and the small caps, split in two

The mark painter gets a guard that runs once per fragment carrying a
`text-emphasis`, and the small-caps walk is split into a function taking
a starting point so the vertical painter can call it from inside its own
turn. A split is the kind of change the entries above keep finding
nothing in and the compiler keeps moving milliseconds around.
Twenty-five alternating samples at 800px, idle:

| | parse | stylesheets | cascade | layout | paint | total |
|---|---|---|---|---|---|---|
| `features.html`, round 1 | 0 | 0 | -2 | +1 | +1 | -1 |
| `features.html`, round 2 | 0 | 0 | 0 | -2 | -1 | -5 |

The two forward rounds disagree on every phase that moved -- cascade -2
then 0, layout +1 then -2, paint +1 then -1 -- so nothing earned a
question and no mirror, control or second page was spent. Both totals
are negative. The binary grows 4,192 bytes.

Both binaries render `generated.html` and `features.html`
byte-identically, `cmp`-checked before any timing.

## Two sideways modes, and two agreeing rounds in phases that cannot run

`sideways-rl` and `sideways-lr` add two keywords to the cascade's
`writingModeKeyword`, which is called only where a page says
`writing-mode`, and a pair of sign flips inside the vertical layout and
paint paths, which no horizontal page enters. So **neither benchmark
page can reach a line of this diff.**

Twenty-five alternating samples at 800px, idle:

| | parse | stylesheets | cascade | layout | paint | total |
|---|---|---|---|---|---|---|
| `features.html`, round 1 | 0 | 0 | **+1** (13 of 25) | **+1** (13 of 25) | 0 | +1 |
| `features.html`, round 2 | 0 | 0 | **+1** (14 of 25) | **+1** (13 of 25) | -1 | +2 |
| `generated.html` | 0 | 0 | 0 | -1 | 0 | -2 |

The two forward rounds **agree**, on cascade +1 and layout +1, which the
rules above call the point at which a reading earns a question. It has
nowhere to go twice over: neither phase runs a line of this diff on a
page that never says `writing-mode`, and the same two binaries read
nothing at all on `generated.html`, which cannot reach it either. Both
counts are 13 and 14 of 25 -- a coin's distance from half -- where a
reading this file has ever traced to work ran 18 or 19.

The binary grows 232 bytes. Both binaries render `generated.html` and
`features.html` byte-identically, `cmp`-checked before any timing.

## The viewport clamp, which is one expression

`WM_UNBOUNDED` gone and `cssViewportHeight` in its place, in the one
branch that runs where a vertical flow begins -- which neither benchmark
page has. Twenty-five alternating samples at 800px, idle:

| | parse | stylesheets | cascade | layout | paint | total |
|---|---|---|---|---|---|---|
| `features.html`, round 1 | 0 | 0 | -1 | -3 | 0 | -6 |
| `features.html`, round 2 | 0 | 0 | -1 | +1 | 0 | 0 |

Layout disagrees with itself between the rounds, cascade agrees at -1
while running no line of a diff that is one expression inside
`layoutBlock`, and both totals are at or below zero. Nothing earned a
question.

The binary **shrinks** by 40 bytes: a constant went away and a global
took its place. That is the second entry in this file to record a
smaller binary, and the first where the reason is a line deleted rather
than a structure changed.
