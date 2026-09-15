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
- **Both engines get the same canvas**, 800x600. This is the whole
  ballgame and it is easy to get wrong — see below.
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
| 800x600 | 134 ms | 480,000 |
| 800x2000 | 174 ms | 1,600,000 |
| 800x8000 | 354 ms | 6,400,000 |

Same page, same layout, same paint — 220 ms of the difference is
encoding. `tests/bench.sh` now gives both engines 800x600.

## Start-up is not a rendering result

Chromium takes **457 ms** to screenshot a one-line page at 800x600, and
this browser takes **27 ms**. That difference is process start-up — a
browser engine bringing up a multi-process architecture, a JavaScript
engine, a compositor and a network stack, against a 2.2 MB native binary
that opens a Cairo surface. It is real if what you want is a screenshot
from a shell script, and it says nothing about rendering speed.

So the table below is also reported with that baseline subtracted, which
is the only honest way to compare the work rather than the start-up.

## End to end: HTML file in, 800x600 PNG out

| Page | Size | This browser | Chromium | Minus start-up: this | Minus start-up: Chromium |
|---|---|---|---|---|---|
| hello.html | 4 KB | 36 ms | 497 ms | 9 ms | 40 ms |
| css.html | 3 KB | 36 ms | 476 ms | 9 ms | 19 ms |
| generated.html | 51 KB | 132 ms | 548 ms | 105 ms | 91 ms |

On the 51 KB page Chromium does the same work about **1.15 times
faster**. On pages of a few kilobytes this browser is ahead. That is the
honest headline, and it is a very different one from what an unequal
canvas produced.

## HTML parsing alone

Chromium's number is `DOMParser.parseFromString` timed inside the page
with `performance.now()`; ours is the parse phase reported by
`ARCHTELOS_TIMING=1`, which includes the byte pre-pass that rewrites
non-ASCII input (see FINDINGS.md, "text has no substring").

| Page | Size | This browser | Chromium |
|---|---|---|---|
| hello.html | 4 KB | <1 ms | 0.1 ms |
| css.html | 3 KB | <1 ms | 0.1 ms |
| generated.html | 51 KB | 8 ms | 2.1 ms |

About **4x slower** on the large page, or roughly 6 MB/s against
25 MB/s. For a tokenizer and tree builder written in a young language
against one of the most optimized parsers in software, that is a
reasonable place to be, and it is not where the remaining time goes.

## Where the time actually goes

`generated.html` at 800x600, 2,728 elements:

| Phase | Time |
|---|---|
| fetch (local file) | 0 ms |
| parse | 8 ms |
| stylesheets | 2 ms |
| images | 1 ms |
| cascade | 54 ms |
| layout | 43 ms |
| paint | 4 ms |

The cascade and layout are **90%** of it. Parsing is 7%, and paint —
once it is not also encoding six megapixels — is 4 ms.

Inside the cascade: 8,578 selector tests produce 11,614 matched
declarations across 2,728 elements. Collecting them is 10 ms, applying
14 ms and computing 21 ms.

The presentational-attribute pass inside collection was 8 ms of that; it
is 3 ms now that an element records at parse time whether it carries
such an attribute, so the pass can skip the ones that do not. The saving
is real and measured at the sub-phase, and it is **inside the noise end
to end**: best-of-seven for the whole page moved from 132 ms to 135 ms,
which is to say it did not move. Computing styles is the phase worth
attacking next.

Inside layout: 11,564 text measurements, of which 620 miss the width
cache and reach Cairo (9 ms total); building the box tree is 15 ms and
inline placement 12 ms.

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

## Build

| | |
|---|---|
| Source | 11,289 lines of Festina across `browser.f` and `src/` |
| Compile | 9.1 s, whole program, no incremental build |
| Binary | 2.2 MB, linking Cairo, X11, libjpeg, mbedTLS and libc |

Of that 9.1 s, **4.2 s is the single generated map literal** holding the
standard's 2,231 named character references: a one-line program compiles
in 0.6 s, and the same program importing only that table takes 4.8 s.
The table is the right data structure — it looks up in constant time and
the runtime cost is nil — but a large literal is priced at compile time,
which is worth knowing before generating another one.
