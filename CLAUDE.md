# archtelos-browser — intent and working rules

This file is for whoever works on this repository next, human or agent.
It holds three things that belong in no other document: what the
project is for, how the owner wants work on it done, and where every
kind of information lives.

- What the browser does today is in [README.md](README.md).
- What is open is in [todo.md](todo.md); what changed is in
  [changelog.md](changelog.md).
- What building this taught us about Festina is in
  [FINDINGS.md](FINDINGS.md), and what Festina should gain as a result
  is in [festina.md](festina.md).
- How fast it is, against other browsers, is in
  [benchmarks.md](benchmarks.md).
- Where the style engine stands against the CSS snapshot,
  specification by specification, is in [css-2026.md](css-2026.md).

## 1 Intent

- **A real HTML/CSS renderer written entirely in Festina.** No C, no
  shelling out, no library that Festina does not already link. One
  `.f` entry file plus imports, compiled to one native binary.
- **Two purposes, equally weighted.** It must render real pages
  correctly, and it must keep finding the places where Festina is
  insufficient. A workaround for a language gap is written down in
  FINDINGS.md and turned into a concrete proposal in festina.md; a
  workaround that goes unrecorded has wasted half its value.
- **Correctness is measured, not asserted.** Conformance is a number
  from someone else's test suite, not an opinion about the code.
- **Performance is measured against real browsers**, on the same pages,
  with the numbers written down.

## 2 The standards this targets

| Area | Standard | Status here |
|---|---|---|
| HTML parsing and the DOM tree it builds | [WHATWG HTML Living Standard](https://html.spec.whatwg.org/), §13 "Parsing HTML documents" | the normative reference; conformance measured against the WPT corpus below |
| CSS | [CSS Snapshot 2026](https://www.w3.org/TR/css-2026/) | the target; the gap is measured per specification in css-2026.md and the work it implies is in todo.md. `www.w3.org` is refused by this network, so the snapshot must be supplied to a session rather than fetched |

**HTML is the WHATWG Living Standard, not "HTML5" generally.** When the
parser's behaviour and some other description of HTML disagree, the
Living Standard wins. Cite clauses by their spec section names
("the adoption agency algorithm", "reset the insertion mode
appropriately"), because the Living Standard has no version numbers to
cite instead.

**Conformance is measured with the web-platform-tests HTML parsing
corpus** — the tree-construction `.dat` files the standard's own test
suite maintains:

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/web-platform-tests/wpt
cd wpt && git sparse-checkout set html/syntax/parsing
export WPT_HTML_TESTS=$PWD/html/syntax/parsing/resources
```

`tests/run.sh` then runs all of them and prints a pass count. Without
`WPT_HTML_TESTS` the conformance suite skips cleanly and the rest of
the suite still runs, but **a change to the HTML parser is not finished
until the conformance run has been done and its number recorded** in
README.md and changelog.md. The number may not go down.

## 3 Working rules

These are standing instructions. They apply to every change.

**Write the test first.** For a behaviour change: write the test,
watch it fail for the right reason, then write the code. A test
written after the implementation tests what the code does; one written
first tests what was intended. For a spec conformance change the test
is usually already written — find the WPT case that fails, fix it,
and check the count moved. For a bug, reproduce it in a test before
fixing it.

**Documentation describes the present, and only the present.** Every
document states what the project *is* right now — not what it used to
be, not what it will become. No "as of", no "this used to", no "this
will be added later", no "(new)", no changelog entries smuggled into
prose. When a change makes a sentence read as history or as a promise,
rewrite the sentence; do not annotate it and do not leave the old and
new framing side by side. A number that has moved — a test count, a
measurement, a line count — is the same problem in miniature: correct
it, do not date it.

Exactly three documents are exempt, because recording time is their
whole purpose:

| | |
|---|---|
| [changelog.md](changelog.md) | the past, by change |
| [todo.md](todo.md) | the future — open work and deliberate non-work |
| [benchmarks.md](benchmarks.md) | measurements, which are dated by nature |

FINDINGS.md is not exempt: it describes the language as it is today,
and an entry that gets fixed upstream is deleted from it, not marked
"fixed".

**Keep the benchmarks current, and keep them honest.** Any change that
could plausibly move a number re-runs `tests/bench.sh` and updates
[benchmarks.md](benchmarks.md). Benchmarks compare against a real
browser — headless Chromium — on the same input, measuring the same
phases, with the methodology written down beside the table. Report
what the measurement says even when it is unflattering; a benchmark
that only ever shows a win is not being run honestly.

**A measurement made by subtracting two large numbers must report the
spread of both.** benchmarks.md once reported that Chromium rendered the
benchmark page "1.15 times faster". The number came of timing each whole
command and subtracting each engine's start-up: two quantities near
500 ms, subtracted to obtain one near 50. Chromium's start-up on one
machine spans 436 to 542 ms, so the same method gave 1.15x on one run
and 3.8x on the next, and the project carried one of them as a headline
for weeks. Measure the thing itself — from inside both engines, as
`tests/chromium.py render` and the phase timers now do — or, if a
difference is genuinely the only way in, publish the spread of every
term beside the answer and say what it implies. The same caution applies
to comparing today's number against one written down earlier: rebuild
the old revision and run it beside the new one, in the same minutes on
the same machine, or the comparison is measuring the machine.

**A feature must not cost anything to the pages that do not use it.**
Positioning cost 18 ms on a page with no positioned box, because it
added a walk of the box tree, a second painting pass and two predicates
in the hot child loops. All of it came back by asking once per document
whether the feature occurs at all. Anything that adds a pass over the
tree, or a test inside a loop over every box or every declaration, gets
that flag before it lands, not after a benchmark notices.

**An instrument must be able to fail.** A property row reading `initial`
computes to the initial value, so the property can never register as
implemented however complete the implementation is. A selector that
matches nothing in the fixture is graded the same way whether it is
implemented or dropped. Both of those shipped here and had to be found.
Before implementing something, check that the thing measuring it would
notice — give the property's row in `tests/conformance/css-properties.txt`
a real value, and the selector something to match — because the count in
README.md and css-2026.md is the deliverable, and a measurement that
cannot move is not one.

Fixing the fixture is only half of it: check the instrument's own
reading too. `object-fit` and `object-position` had real rows, put there
a commit ahead of the work, and still could not register, because
`styleDigest` in `tests/conformance/properties.f` compares a list of
fields by name and nobody had added the two new ones. The feature
worked; the count did not move. So the check is end to end — set the
property, run the instrument, watch the number go up — and it is done
when the implementation lands, not once the suite is green.

**Audit the whole instrument, not one row at a time.** Checking the row
in front of you leaves every other row unexamined, and they rot
silently: 218 of the 373 rows in `css-properties.txt` declared
`initial`, which computes to the initial value by definition, and 24
more carried a value equal to the initial one — a border width with no
border style beside it computes to zero, `text-decoration-style: solid`
*is* the initial value. Two hundred and forty-two properties could have
been implemented perfectly and the count would not have moved, and
`--verbose` listed them among the properties still to do, which is
where they hid. `tests/chromium.py properties-audit` now asks Chromium
of every row whether it can register at all, and `tests/run.sh` runs it
before grading the engine, so the question is asked of the whole file on
every run rather than of whichever row someone remembered.

**When two things must agree, test them against each other.** A check
against a number you worked out yourself only catches the case you
thought of. A check that two ways of saying the same thing land on the
same pixel catches the case you did not, because it does not depend on
either answer being known in advance. Every bug found here that the
suite had already been given a chance to catch was of that shape:

- `background-position: 50%` was a hundred times too far, because a
  percentage `Len` holds a number out of a hundred and the position code
  read it as a fraction. The keywords were written to match the wrong
  convention, so keywords worked, pixel lengths worked, and only a real
  percentage was broken. `50%` against `center` fails immediately.
- A background image ignored `opacity` and `object-fit`'s clip layer
  applied it twice. The same content painted through the clipped path
  and the unclipped path, at the same opacity, must give the same pixel;
  neither bug survives that.

So when a feature adds a second way to reach an existing result — a
keyword beside a length, a shorthand beside its longhands, a clipped
path beside an unclipped one, a new syntax beside the old one — the test
that earns its place asserts they agree, not that each one matches a
number.

**A count that goes up is not yet evidence the feature works.** A
property can register because of a field belonging to a different
property: declaring `border-top-style` gives that side the medium width,
and the width alone moved the digest, so the instrument scored the
property while the engine threw the declared keyword away. Declaring
`outline-style` did the same and the engine has no outline style at all.
So when a count moves, ask *which field moved* —
`tests/conformance/properties.f --fields` prints it — and require one
that means the property. Where a property genuinely cannot act alone, its
row carries the declarations it needs as context and is graded against an
element that already has them, so the context cannot do the work for it.

**Run the benchmarks on an idle machine, and check a number you did not
change.** "Best of N" does not rescue a contended run, because every one
of the N runs is contended: a benchmark run here beside a valgrind job
reported Chromium at 93 ms on the page where it takes 26, and the
browser's own rows moved with it. Nothing in the output said so. So
`tests/bench.sh` gets the machine to itself, and before any of its
numbers are copied into benchmarks.md, at least one row that this change
could not possibly have moved — Chromium's, usually — is checked against
what it said last time. A row that shifted is the run disqualifying
itself.

That check is the script's now rather than the reader's: `tests/bench.sh`
compares Chromium's render of the benchmark page against `CONTROL_MS`,
says how far out it is, and exits non-zero when it is beyond
`CONTROL_TOLERANCE`. Leaving it to be remembered was not enough — a run
reporting Chromium at 30.4 ms where benchmarks.md records 26.0 printed
without a word of complaint beside a table that looked ordinary. The
tolerance is set from Chromium's measured spread on this machine, which
benchmarks.md records beside the table, and not from an opinion about
how much noise is acceptable: a band tight enough to fail honest runs is
a band that gets ignored. A new reference browser is a new control, so
raise `CONTROL_MS` and record the new spread; do not widen the
tolerance to make a bad run pass.

**Never add a dependency** — a system library, a tool, a vendored file
— without explicit permission. The whole point is that this links what
Festina links and nothing else.

**Record every Festina limitation you work around.** The workaround
gets a comment naming the finding, FINDINGS.md gets the evidence (a
minimal reproduction, ideally under valgrind), and festina.md gets the
proposal. This is a deliverable, not a courtesy.

**Verify before pushing.** `tests/run.sh` must pass; for anything that
touches parsing, the conformance count must not drop; for anything that
touches memory ownership, run `tests/run.sh --valgrind`. GitHub Actions
runs the same suite, corpus included, on every pull request and on
`main` (`.github/workflows/tests.yml`). It is a second pair of eyes, not
a substitute for the run you do yourself: a red build on a branch is a
review finding like any other.

**Delivering.** Work on the designated branch, commit with clear
messages, push, and open a pull request at the end of every task.
Report outcomes faithfully: what passed, what failed with its output,
what was left out and why. Never put a model identifier in a commit
message, a comment, a document, or any other repository artifact.

## 4 Building and testing

Festina is not vendored here. Point `FESTINA_HOME` at a checkout of
[uraikus/festina](https://github.com/uraikus/festina):

```bash
export FESTINA_HOME=/path/to/festina        # the directory holding bin/festina
$FESTINA_HOME/bin/festina compile browser.f -o build/browser
```

`tests/run.sh` finds Festina itself if `FESTINA_HOME` is unset, by
trying `../festina`, `~/.festina` and `../uraikus/festina` in that
order; everything else assumes the variable is set.

Compiling needs Festina's graphics and TLS tiers, because this program
uses a canvas and fetches `https://`:

```bash
sudo apt install clang libsqlite3-dev libcairo2-dev libx11-dev \
                 libjpeg-dev libmbedtls-dev pkg-config
```

Running the whole suite:

```bash
tests/run.sh                 # unit suites, render suites, conformance, examples
tests/run.sh --valgrind      # the same, under valgrind (see below)
tests/bench.sh               # benchmarks, including Chromium comparisons
```

### Running under valgrind: `tools/festina-generic`

Festina's LLVM backend compiles for the host CPU's exact feature set
(`LLVMGetHostCPUName` / `LLVMGetHostCPUFeatures` in
`festina/llvm_backend.py`). On a machine with AVX-512 that produces
instructions valgrind cannot emulate, and **every** valgrind run dies
with `SIGILL` in something like `vpternlogq` before reaching `main`.

`tools/festina-generic` is a drop-in for `bin/festina` that patches the
backend's two CPU accessors to `x86-64` with no extra features, then
calls the ordinary CLI:

```bash
FESTINA_HOME=/path/to/festina tools/festina-generic compile x.f -o x
valgrind -q ./x
```

`tests/run.sh --valgrind` uses it for every binary it builds. Use it
whenever valgrind is involved and never otherwise — the generic build
is slower, and the numbers in benchmarks.md are native builds.

**Valgrind is the tool that finds Festina's memory bugs, so use it.**
Both memory-safety findings in FINDINGS.md were invisible in ordinary
runs: the programs printed the right answers and exited 0, while
valgrind showed an invalid read of size 8 in `festina_ascii_release`.
Any change that stores, aliases or frees an `ascii`, or that changes
how a struct graph is shaped, gets a valgrind run.

## 5 Repository map

| Path | Contents |
|---|---|
| `browser.f` | the windowed shell: toolbar, address bar, scrolling, history, link navigation, `--screenshot` |
| `src/browser/page.f` | the page pipeline the shell and the tests share: fetch, parse, stylesheets, images, cascade, layout, paint |
| `src/html/` | `decode.f` (bytes to an ASCII-safe form), `entities.f` (character references), `named_refs.f` (the standard's generated reference table), `tokenizer.f`, `parser.f` (tree construction) |
| `src/dom/` | `node.f` (the node tree and its id registry), `serialize.f` (the standard's tree serialization, which the conformance suite compares against) |
| `src/css/` | `parser.f` (rules, selectors, `@media`), `page.f` (`@page` and the page box), `ua.f` (the user-agent stylesheet), `style.f` (the computed `Style` record), `cascade.f` (matching, specificity, shorthands, computed values), `counterstyles.f` (`@counter-style` and the predefined list styles), `shapes.f` (a basic shape resolved against a box, which the painter and the layout engine both ask for) |
| `src/layout/layout.f` | the box tree, block and inline formatting, tables, intrinsic widths |
| `src/layout/paginate.f` | the document broken into pages, which is the column algorithm over a different container |
| `src/paint/paint.f` | painting and hit testing |
| `src/net/` | `fetch.f` (URL resolution, HTTP(S) with redirects, local files), `preload.f` (the preload scanner and the worker threads that prefetch what it finds) |
| `src/util/` | `text.f` (the string operations `text` lacks), `color.f`, `named_colors.f`, `bidi.f` (UAX #9) |
| `tests/unit/` | unit suites: utilities, HTML, CSS parser, cascade, cascade rules, values, layout geometry, box properties, aspect ratio, positioning, grid areas, form controls, image loading, floats, flex, flex wrapping, iframes, pseudo-elements, counters, quotes, first letter, list markers, logical properties, text, containment, alignment, grid, columns, fragmentation, shapes, bidi, namespaces, counter styles, hyphens, colour spaces, colour schemes, nesting, container queries, audio, paged media, scrollbars, scroll snapping, anchor positioning, the preload scanner |
| `tests/render/` | the pipeline painting offscreen, checked with `getPixelColor`: general rendering, gradients, radial gradients, conic gradients, overflow clipping, clip paths, background images, generated content, object fitting, object view boxes, borders, border images, text decoration, transforms, right-to-left text, box shadows, corner shapes, anchor visibility, first lines, printed pages |
| `tests/conformance/` | the WPT tree-construction runner, and the three instruments that grade this engine against Chromium: CSS properties, default element displays, and selector matching |
| `tests/chromium.py` | drives headless Chromium, so conformance, speed and painting have a yardstick; its `pixels` mode rasterizes a page and prints a row of it |
| `tests/featurepage.py` | the second benchmark page, its control and the image both use, and the `--verify` mode that requires the page to still exercise every feature it claims to |
| `tests/gradpages.py` | the three pages the gradient benchmark compares |
| `tests/latencyserver.py` | a local HTTP server that answers slowly, so the preload scanner has latency to hide |
| `tests/maxrss.py` | peak resident set size of a command, for the memory benchmark |
| `tests/run.sh`, `tests/bench.sh` | the test and benchmark runners |
| `.github/workflows/tests.yml` | CI: the whole suite, natively and under valgrind, on every pull request |
| `tools/festina-generic` | a Festina CLI wrapper that targets a generic CPU, for valgrind |

## 6 Conventions

- Source files end in `.f`; the entry file is `browser.f`.
- A comment that works around a language limitation names it:
  `// see FINDINGS.md, "ascii aliasing"`.
- Node and box graphs are **acyclic**, and parents are reached through
  an id registry. This is load-bearing, not a style preference: a
  back-pointer makes every release of a live alias walk the whole
  document (FINDINGS.md, finding 1). Do not add one.
- **`&&` and `||` short-circuit**, which is what makes the per-document
  flags above cost what they claim to: `cascadeSawDirection && scan(...)`
  does not call `scan` on a page that never said `direction`. Verified
  rather than assumed — a flag guarding an expensive right-hand side is
  worth nothing if both sides always run.
- `ARCHTELOS_TIMING=1` makes the pipeline print per-phase timings.
- `ARCHTELOS_NO_PRELOAD=1` turns the preload scanner off, so a benchmark
  can measure one binary with and without it.
- A program that declares a thread never exits on its own, so every
  entry point ends in an explicit `close()` (FINDINGS.md, "a declared
  thread makes the program non-terminating").
- `WPT_HTML_TESTS` points the conformance suite at the corpus.
