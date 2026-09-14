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
- **Pages**: the two examples in this repository, plus
  `generated.html`, which `tests/bench.sh` generates deterministically
  (40 sections, each a heading, a bordered card with a wrapping
  paragraph and a six-item list, and a twelve-row table: 2,728
  elements, 51 KB). Nobody else's HTML is vendored here.

Everything below was measured on 2026-09-14.

## Start-up is not a rendering result

Chromium takes **458 ms** to screenshot a one-line page, and this
browser takes **6 ms**. That difference is process start-up — a browser
engine bringing up a multi-process architecture, a JavaScript engine, a
compositor and a network stack, against a 2.2 MB native binary that
opens a Cairo surface. It is real if what you want is a screenshot from
a shell script, and it says nothing at all about rendering speed.

So the end-to-end table below is reported with that baseline subtracted
in the last two columns, which is the only honest way to compare the
work rather than the start-up.

## End to end: HTML file in, rendered PNG out

| Page | Size | This browser | Chromium | Minus start-up: this | Minus start-up: Chromium |
|---|---|---|---|---|---|
| hello.html | 4 KB | 49 ms | 486 ms | 43 ms | 28 ms |
| css.html | 3 KB | 35 ms | 488 ms | 29 ms | 30 ms |
| generated.html | 51 KB | 317 ms | 530 ms | 311 ms | 72 ms |

On pages of a few kilobytes the two are level once start-up is removed.
On the 51 KB page Chromium does the same work about **four times
faster**. That gap is the honest headline, and it grows with page size.

## HTML parsing alone

Chromium's number is `DOMParser.parseFromString` timed inside the page
with `performance.now()`; ours is the parse phase reported by
`ARCHTELOS_TIMING=1`, which includes the byte pre-pass that rewrites
non-ASCII input (see FINDINGS.md, "text has no substring").

| Page | Size | This browser | Chromium |
|---|---|---|---|
| hello.html | 4 KB | 1 ms | 0.1 ms |
| css.html | 3 KB | <1 ms | 0.1 ms |
| generated.html | 51 KB | 8 ms | 1.7 ms |

About **5x slower** on the large page, or roughly 6 MB/s against
30 MB/s. For a tokenizer and tree builder written in a young language
against one of the most optimized parsers in software, that is a
reasonable place to be, and it is not where the remaining time goes.

## Where the time actually goes

`generated.html` at 800 px, 2,728 elements:

| Phase | Time |
|---|---|
| fetch (local file) | 0 ms |
| parse | 8 ms |
| stylesheets | 2 ms |
| images | 1 ms |
| cascade | 52 ms |
| layout | 52 ms |
| paint | 15 ms |

Parsing is 6% of the total. The cascade and layout are 82% of it, so
that is where any further work belongs — not in the parser.

Inside the cascade: 8,578 selector tests produce 11,614 matched
declarations across 2,728 elements, and the three sub-phases (collect
15 ms, apply 18 ms, compute 16 ms) are evenly matched, which means
there is no single hot spot left to remove — only the constant factor
of doing it in a language with no hash-consed strings.

Inside layout: 11,564 text measurements, of which 620 miss the width
cache and reach Cairo (9 ms total); building the box tree is 19 ms and
inline placement 13 ms.

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
