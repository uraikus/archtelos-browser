# archtelos-browser

An HTML and CSS renderer, and a small web browser, written entirely in
the [Festina](https://github.com/uraikus/festina) language.

The project has two purposes, equally weighted: render real pages
correctly, and keep finding the places where Festina is insufficient.
The renderer is real — its own HTML tokenizer and tree builder, a CSS
parser and cascade, block, inline and table layout, painting on
Festina's canvas, and an HTTP(S) client — all in one 2.2 MB native
binary that links nothing Festina does not already link. What building
it reveals about the language is in [FINDINGS.md](FINDINGS.md), and what
Festina should gain as a result is in [festina.md](festina.md).

**HTML parsing follows the
[WHATWG HTML Living Standard](https://html.spec.whatwg.org/).** Against
the standard's own tree-construction corpus it passes **1,535 of 1,652**
cases — the same number Chromium 141 passes on the same corpus, and 84
of the 117 each fails are the same cases. CSS targets the
[CSS Snapshot 2026](https://www.w3.org/TR/css-2026/), whose official
definition of CSS is 24 specifications; the engine implements no part of
10 of them. Where it stands on each is in [css-2026.md](css-2026.md).

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
list markers and opacity.

Floats, positioned boxes, Flexbox and Grid are laid out as static
blocks; `overflow: hidden` clips nothing; there is no JavaScript. See
[todo.md](todo.md) for what is planned and what is deliberately not.

## Repository

| Path | Contents |
|---|---|
| `browser.f` | the windowed shell: toolbar, address bar, scrolling, history, link navigation, `--screenshot` |
| `src/browser/page.f` | the page pipeline: fetch, parse, stylesheets, images, cascade, layout, paint |
| `src/html/` | `decode.f`, `entities.f`, `named_refs.f` (the standard's reference table), `tokenizer.f`, `parser.f` |
| `src/dom/` | `node.f` (the node tree and its id registry), `serialize.f` (the standard's serialization) |
| `src/css/` | `parser.f`, `ua.f` (the user-agent stylesheet), `style.f`, `cascade.f` |
| `src/layout/layout.f` | the box tree, block and inline formatting, tables |
| `src/paint/paint.f` | painting and hit testing |
| `src/net/fetch.f` | URL resolution, HTTP(S) with redirects, local files |
| `src/util/` | `text.f`, `color.f`, `named_colors.f` |
| `tests/` | unit suites, offscreen pixel checks, the conformance runner, the runners |
| `.github/workflows/tests.yml` | CI: the same suite, natively and under valgrind |
| `tools/festina-generic` | a Festina wrapper targeting a generic CPU, so valgrind can run the result |

11,289 lines of Festina in `src/` and `browser.f`.

## Tests

```bash
FESTINA_HOME=/path/to/festina tests/run.sh             # everything
FESTINA_HOME=/path/to/festina tests/run.sh --valgrind  # the same, under valgrind
FESTINA_HOME=/path/to/festina tests/bench.sh           # benchmarks, incl. Chromium
```

The runner covers five unit suites (utilities, HTML, CSS parser,
cascade, layout geometry), an offscreen render suite that checks real
pixels with `getPixelColor`, the conformance suite, and a headless
render of every example. There is no test framework: `tests/assert.f` is
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
| Start-up (screenshot a one-line page) | 27 ms | 457 ms |
| Parse 51 KB of HTML | 8 ms | 2.1 ms |
| Render 51 KB, start-up subtracted | 105 ms | 91 ms |

Both engines are given the same 800x600 canvas, which matters more than
anything else in the table: PNG encoding is linear in pixels and
dominates at this page size, so comparing this browser's default
full-document canvas against Chromium's viewport screenshot charged
thirteen times the pixels to layout. On equal terms Chromium does the
rendering work about 1.15 times faster, and a native binary starts an
order of magnitude and a half faster. The cascade and layout are 90% of
our time; parsing is 7%.

## Working on this

[CLAUDE.md](CLAUDE.md) holds the project's standing rules — tests before
code, documents describe the present, benchmarks stay current, and the
conformance number may not go down.

## License

MIT, like Festina. See [LICENSE](LICENSE).
