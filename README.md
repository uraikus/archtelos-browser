# archtelos-browser

An HTML and CSS renderer, and a small web browser, written entirely in
the [Festina](https://github.com/uraikus/festina) language.

The project has two purposes, equally weighted: render real pages
correctly, and keep finding the places where Festina is insufficient.
The renderer is real — its own HTML tokenizer and tree builder, a CSS
parser and cascade, block, inline and table layout, painting on
Festina's canvas, and an HTTP(S) client — all in one 2.4 MB native
binary that links nothing Festina does not already link. What building
it reveals about the language is in [FINDINGS.md](FINDINGS.md), and what
Festina should gain as a result is in [festina.md](festina.md).

**HTML parsing follows the
[WHATWG HTML Living Standard](https://html.spec.whatwg.org/).** Against
the standard's own tree-construction corpus it passes **1,535 of 1,652**
cases — the same number Chromium 141 passes on the same corpus, and 84
of the 117 each fails are the same cases. **CSS selectors match the same
elements Chromium matches in 56 of 61 cases**, the five exceptions all
being Selectors 4. CSS targets the
[CSS Snapshot 2026](https://www.w3.org/TR/css-2026/), whose official
definition of CSS is 24 specifications; the engine implements no part of
8 of them. Where it stands on each is in [css-2026.md](css-2026.md).

![hello.html rendered by the browser](examples/screenshot-hello.png)

## Building and running

Point `FESTINA_HOME` at a Festina checkout and compile:

```bash
export FESTINA_HOME=/path/to/festina
sudo apt install clang libsqlite3-dev libcairo2-dev libx11-dev \
                 libjpeg-dev libmbedtls-dev pkg-config
$FESTINA_HOME/bin/festina compile browser.f -o browser

./browser examples/hello.html                     # a local file
./browser https://example.com/                    # over HTTP(S)
./browser                                          # a built-in welcome page

# headless: lay out at 900px and write a PNG of the whole document
./browser examples/hello.html --screenshot out.png --width 900
```

Inside the window:

| Input | Effect |
|---|---|
| wheel, `Up`/`Down`, `PageUp`/`PageDown`, `Home`/`End`, space | scroll |
| click a link | follow it; the target shows in the status bar on hover |
| `BackSpace`, or the `<` button | back |
| `F5` | reload |
| `F6`, or a click on the address bar | edit the address; `Return` loads, `Escape` cancels |
| resizing the window | re-layout at the new width |

`ARCHTELOS_TIMING=1` prints per-phase timings.

## What it renders

**HTML** is the standard's algorithm, not an approximation of it. The
tokenizer implements the tag, attribute, comment, doctype, RCDATA,
RAWTEXT, PLAINTEXT, script-data and script-data-escaped states, CDATA
sections, and bogus comments. Character references cover all 2,231 named
references with longest-match, the 106 legacy names that work without a
semicolon, the attribute-value rule that leaves `?a=1&copy=2` alone, and
numeric references with the standard's replacements. Tree construction
implements all 23 insertion modes, the stack of open elements with its
five scopes, the list of active formatting elements with the adoption
agency algorithm, foster parenting, template contents, quirks-mode
detection from the doctype, the `<select>` content model, and foreign
content — SVG and MathML namespaces, tag and attribute name adjustment,
and integration points.

**CSS** comes from `<style>`, `<link rel=stylesheet>` (fetched) and
`style=""`. Selectors: type, universal, `#id`, `.class`, `[attr]` with
`=`, `~=`, `^=`, `$=`, `*=`, `|=`, the descendant, child, adjacent and
general-sibling combinators, `:first-child`, `:last-child`,
`:only-child`, `:nth-child(odd|even|n)`, `:first-of-type`,
`:last-of-type`, `:root`, `:link` and `:not(compound)`. The cascade
handles specificity, source order, `!important`, inline styles and HTML
presentational attributes. `@media` is evaluated against the viewport;
`@supports` and `@layer` contribute their contents; other at-rules are
skipped. Units: px, em, rem, %, pt, pc, in, cm, mm, ex, ch, vw, vh.
Colors: all 148 names, `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`,
`rgba()`, `hsl()`, `hsla()`, `transparent` and `currentcolor`.

**Layout** is block formatting with margin collapsing, inline formatting
with word wrapping and baseline alignment, inline-blocks with
shrink-to-fit widths, replaced images with intrinsic sizes and aspect
ratio, `pre`, list markers, and automatic table layout with fixed and
percentage columns, `colspan`, row heights and vertical alignment. Form
controls are drawn as boxes.

**Painting** covers backgrounds, borders with rounded corners,
text with underline and line-through, images, broken-image placeholders,
list markers and opacity. `linear-gradient()` and
`repeating-linear-gradient()` paint as background images, at any angle
and with any number of colour stops, and `background-image: url()`
paints a fetched image with `background-repeat` and
`background-position` — a tile that runs off the edge is cut off
there. `object-fit` and `object-position` size and place a replaced
element's own content inside its box, in all five fitting values, and
clip it to the content box.

**`::before` and `::after`** generate boxes from `content`, which takes
quoted strings, `attr()`, `counter()`, `counters()` and the four quote
keywords. `counter-reset` and `counter-increment` maintain counters with
the standard's scoping, and `quotes` gives `open-quote` and
`close-quote` their strings at a depth that runs over the document in
document order rather than following element nesting — so `<q>` renders
its quotation marks.

**`::first-letter`** styles the first letter of the first line of a
block on its own, taking any punctuation in front of it along, skipping
leading whitespace, and finding the letter inside a nested inline. Only
the first of the block, not the first of every descendant.
`::first-line` still makes its rule unusable rather than matching the
element. `url()` in `content` is not implemented, and a counter always
renders in decimal.

**Flex containers** wrap: `flex-direction`, `flex-wrap` and the
`flex-flow` shorthand, `order`, `flex-grow`, `flex-shrink`,
`flex-basis` and the `flex` shorthand, `justify-content`,
`align-items`, `align-self`, `align-content` and the `gap` family.
Items are broken into lines that grow and shrink independently,
`align-content` distributes the lines across the cross axis,
`wrap-reverse` flips it, an auto margin takes the free space before
`justify-content` is consulted, and `align-items: baseline` lines the
text up rather than the boxes.

**`<audio>`** draws its controls at the size Chromium draws them, and is
invisible without a `controls` attribute, as the standard's own
stylesheet says. It does not play: see todo.md.

**`overflow: hidden`** clips a box's descendants, text included, by
painting them into an offscreen image — the canvas has no clip region
and an image clips at its own bounds. A `border-radius` inside such a
box is drawn square, because an image has no path API.

**Subresources are prefetched while the page is parsed.** A preload
scanner reads the raw bytes for `<link rel=stylesheet>`, `<img src>` and
`<script src>` before tree construction and hands the absolute URLs to
four worker threads, so the network overlaps the parse rather than
following it. `ARCHTELOS_NO_PRELOAD=1` turns it off.

Two Festina bugs stand between this and the live web: an HTTP response
larger than 64 KiB takes thirty seconds, and the query string is dropped
from every request. Both are in FINDINGS.md with reproductions and in
todo.md with their consequences.

Grid is laid out as a static block, and there is no JavaScript. See [todo.md](todo.md) for what is planned and
what is deliberately not.

## Repository

| Path | Contents |
|---|---|
| `browser.f` | the windowed shell: toolbar, address bar, scrolling, history, link navigation, `--screenshot` |
| `src/browser/page.f` | the page pipeline: fetch, parse, stylesheets, images, cascade, layout, paint |
| `src/html/` | `decode.f`, `entities.f`, `named_refs.f` (the standard's reference table), `tokenizer.f`, `parser.f` |
| `src/dom/` | `node.f` (the node tree and its id registry), `serialize.f` (the standard's serialization) |
| `src/css/` | `parser.f`, `ua.f` (the user-agent stylesheet), `style.f`, `cascade.f` |
| `src/layout/layout.f` | the box tree, block and inline formatting, tables, floats, positioning, flex |
| `src/paint/paint.f` | painting and hit testing |
| `src/net/` | `fetch.f` (URL resolution, HTTP(S) with redirects, local files), `preload.f` (the preload scanner and its worker threads) |
| `src/util/` | `text.f`, `color.f`, `named_colors.f` |
| `tests/` | unit suites, offscreen pixel checks, the conformance runner, the runners |
| `.github/workflows/tests.yml` | CI: the same suite, natively and under valgrind |
| `tools/festina-generic` | a Festina wrapper targeting a generic CPU, so valgrind can run the result |

14,659 lines of Festina in `src/` and `browser.f`.

## Tests

```bash
FESTINA_HOME=/path/to/festina tests/run.sh             # everything
FESTINA_HOME=/path/to/festina tests/run.sh --valgrind  # the same, under valgrind
FESTINA_HOME=/path/to/festina tests/bench.sh           # benchmarks, incl. Chromium
```

The runner covers nineteen unit suites (utilities, HTML, CSS parser,
cascade, cascade rules, values, layout geometry, box properties,
positioning, floats, flex, flex wrapping, iframes, pseudo-elements,
counters, quotes, first letter, audio, the preload scanner), five
offscreen render suites that check real pixels with `getPixelColor` —
general rendering, gradients, overflow clipping, background images and
object fitting — three conformance runners that measure the engine against
Chromium — CSS properties, default element displays, and which elements
a selector matches — the HTML conformance suite, and a headless render
of every example. There is no test framework: `tests/assert.f` is
a dozen lines and every suite is an ordinary Festina program.

The conformance suite needs the standard's corpus:

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/web-platform-tests/wpt
cd wpt && git sparse-checkout set html/syntax/parsing
export WPT_HTML_TESTS=$PWD/html/syntax/parsing/resources
```

Without it the suite skips cleanly and the rest still runs. With it,
`tests/run.sh` fails if the pass count drops.

The whole suite is clean under valgrind: no invalid reads or writes and
no leaks.

GitHub Actions runs both, natively and under valgrind, on every pull
request and on `main`. It assembles the toolchain the same way a person
does — a Festina checkout, the packages Festina links, and the corpus —
and fails if the corpus is missing rather than skipping the conformance
suite the way a laptop run may.

## Performance

Against headless Chromium on the same pages —
[benchmarks.md](benchmarks.md) has the method and the full tables:

| | This browser | Chromium 141 |
|---|---|---|
| Parse, style and lay out 51 KB | 93 ms | 25.3 ms |
| Parse 51 KB of HTML | 8 ms | 2.1–3.9 ms |
| Peak memory, 51 KB page | 17.9 MB | 194.8 MB |
| Binary | 2.4 MB | 463 MB |
| Screenshot a one-line page | 38 ms | 453 ms |

**Chromium renders about three and three quarter times faster.** The first row is
the one that describes the engines: both sides are timed from inside,
with process start-up and PNG encoding outside the timer, because
Chromium spends about 450 ms starting up, and subtracting a baseline
that varies by 106 ms run to run measures the variance rather than the
work.
The cascade and layout are 88% of our time and all of the gap, and
layout is now the larger half of the two; parsing is 9%.

The last row is a different question with a different answer: a native
binary is finished before Chromium has started, which matters if what
you want is a screenshot from a shell script and matters not at all as a
statement about rendering.

The memory and binary rows are the same trade seen from the other side:
what is absent from this browser — a JavaScript engine, a compositor, a
sandbox, a network stack, ICU — is most of what Chromium is carrying.
Chromium's footprint is flat across all three benchmark pages because it
is almost entirely fixed cost, while this browser's grows with the
document, from 13 MB to 18 MB as the page goes from 4 KB to 51 KB.

**Subresources are prefetched while the page is parsed.** A preload
scanner reads the raw bytes for `<link rel=stylesheet>`, `<img src>`
and `<script src>` before tree construction and fetches them on four
worker threads. Against a server answering in 50 ms, a page with
sixteen subresources loads **3.77 times faster** than the same page with
the scanner turned off, and one large enough to parse waits for nothing
at all.

It is not free to pages that never prefetch: its four worker threads
cost the 51 KB local benchmark page 4 ms, because glibc's `malloc`
gives up its single-threaded fast path at the first `pthread_create`
and Festina allocates constantly. Festina cannot start a thread on
demand, so there is nowhere to put the fix — FINDINGS.md and
benchmarks.md carry the measurement.

## Working on this

[CLAUDE.md](CLAUDE.md) holds the project's standing rules — tests before
code, documents describe the present, benchmarks stay current, and the
conformance number may not go down.

## License

MIT, like Festina. See [LICENSE](LICENSE).
