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
| CSS | [CSS Snapshot 2026](https://www.w3.org/TR/css-2026/) | the target; see todo.md for the gap |

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
| `src/css/` | `parser.f` (rules, selectors, `@media`), `ua.f` (the user-agent stylesheet), `style.f` (the computed `Style` record), `cascade.f` (matching, specificity, shorthands, computed values) |
| `src/layout/layout.f` | the box tree, block and inline formatting, tables, intrinsic widths |
| `src/paint/paint.f` | painting and hit testing |
| `src/net/fetch.f` | URL resolution, HTTP(S) with redirects, local files |
| `src/util/` | `text.f` (the string operations `text` lacks), `color.f`, `named_colors.f` |
| `tests/unit/` | unit suites: utilities, HTML, CSS parser, cascade, layout geometry |
| `tests/render/` | the pipeline painting offscreen, checked with `getPixelColor` |
| `tests/conformance/` | the WPT tree-construction runner |
| `tests/chromium.py` | drives headless Chromium, so conformance and speed have a yardstick |
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
- `ARCHTELOS_TIMING=1` makes the pipeline print per-phase timings.
- `WPT_HTML_TESTS` points the conformance suite at the corpus.
