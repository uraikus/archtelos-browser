# archtelos-browser

An HTML5 / CSS3 renderer and a small web browser, written entirely in
the [Festina](https://github.com/uraikus/festina) language.

The project exists to find the gaps and insufficiencies in Festina by
building something demanding with it, and to show what the language
already does well. The renderer is real: its own HTML tokenizer and
tree builder, a CSS parser and cascade, block/inline/table layout,
painting on Festina's canvas, and an HTTP(S) client, all in one native
binary with no libraries beyond what Festina itself links. What was
learned along the way is in [FINDINGS.md](FINDINGS.md).

![hello.html rendered by the browser](examples/screenshot-hello.png)

## Building and running

You need a Festina checkout (its `bin/festina`) and the dependencies
Festina's graphics tier needs (`clang`, `libsqlite3-dev`,
`libcairo2-dev`, `libx11-dev`, `libjpeg-dev`, `libmbedtls-dev`,
`pkg-config`; see Festina's setup.md).

```bash
export FESTINA_HOME=/path/to/festina
$FESTINA_HOME/bin/festina compile browser.f -o browser

./browser examples/hello.html                     # a local file
./browser https://raw.githubusercontent.com/uraikus/festina/main/docs/index.html
./browser                                          # a built-in welcome page

# headless: lay out at 900px and write a PNG of the whole document
./browser examples/hello.html --screenshot out.png --width 900
```

Inside the window:

| Input | Effect |
|---|---|
| mouse wheel, `Up`/`Down`, `PageUp`/`PageDown`, `Home`/`End`, space | scroll |
| click on a link | follow it (the target shows in the status bar while hovering) |
| `BackSpace`, or the `<` button | back |
| `F5` | reload |
| `F6`, or a click on the address bar | edit the address; `Return` loads it, `Escape` cancels |
| resizing the window | re-layout at the new width |

`ARCHTELOS_TIMING=1` in the environment prints how long each phase
(fetch, parse, stylesheets, images, cascade, layout, paint) took.

## What it renders

- **HTML**: an HTML5-style tokenizer (attributes with any quoting,
  entities including the HTML 4 named set and numeric references,
  comments, doctypes, CDATA, raw-text `script`/`style`, escapable
  `textarea`/`title`) and a tree builder with an html/head/body
  skeleton, void elements and the implied end tags that make untidy
  markup nest (`p`, `li`, `dt`/`dd`, `option`, `tr`/`td`/`th`, row
  groups, unclosed headings). UTF-8 input is handled through a byte
  pre-pass (see FINDINGS.md on why).
- **CSS**: stylesheets from `<style>`, `<link rel=stylesheet>` (fetched)
  and `style=""`; comments, `@media` (width/height features, `screen`,
  `print`, `not`, `and`, `,`), `@supports` and `@layer` blocks
  (contents used), other at-rules skipped; selectors: type, universal,
  `#id`, `.class`, `[attr]` with `=`, `~=`, `^=`, `$=`, `*=`, `|=`,
  descendant / child / adjacent / general-sibling combinators,
  `:first-child`, `:last-child`, `:only-child`, `:nth-child(odd|even|n)`,
  `:first-of-type`, `:last-of-type`, `:root`, `:link`, `:not(compound)`;
  specificity, source order, `!important`, inline styles and HTML
  presentational attributes (`align`, `bgcolor`, `width`, `height`,
  `border`, `cellpadding`, `cellspacing`, `font color/size/face`,
  `nowrap`, `hidden`); shorthands for `margin`, `padding`, `border`,
  `border-*`, `font`, `background`, `list-style`; units px, em, rem, %,
  pt, pc, in, cm, mm, ex, ch, vw, vh; colors by name (all 148), `#rgb`,
  `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`, `hsla()`,
  `transparent`, `currentcolor`; `inherit`.
- **Properties**: `display` (block, inline, inline-block, list-item,
  none, table, table-row, table-cell, table-row-group; flex and grid
  fall back to block), `color`, `background-color`, `font-size`
  (including keywords, `smaller`/`larger`), `font-weight`,
  `font-style`, `font-family`, `font`, `line-height`, `text-align`,
  `text-decoration`, `text-transform`, `letter-spacing`, `white-space`
  (normal, nowrap, pre, pre-wrap), `list-style-type`, `vertical-align`,
  `opacity`, `visibility`, `width`/`height`/`min-*`/`max-*`, margins
  (including `auto` centering), padding, borders with per-side widths
  and colors, `border-radius`, `border-spacing`, `border-collapse`,
  `text-indent`.
- **Layout**: block formatting with margin collapsing (siblings and
  through parents), inline formatting with word wrapping, collapsible
  whitespace across inline boundaries, line-height and baseline
  alignment, `text-align`, inline backgrounds and borders,
  inline-blocks with shrink-to-fit widths, replaced images with
  intrinsic sizes and aspect ratio, `br`, `pre`, list markers (disc,
  circle, square, decimal with `value`), automatic table layout with
  fixed and percentage columns, `colspan`, row height and vertical
  alignment, and form controls drawn as boxes (text fields, buttons,
  checkboxes, radios, selects).
- **Painting**: backgrounds, borders (rounded corners through a bezier
  path), text runs at their baselines, underline and line-through,
  images (PNG/JPEG), broken-image placeholders with alt text, list
  markers, opacity.

Not supported, deliberately or for now: floats, positioned boxes,
flexbox and grid (all laid out as static blocks), `overflow: hidden`
clipping, generated content, JavaScript, forms that submit, CSS
`background-image`, cookies, caching. See FINDINGS.md for what a
Festina limitation caused versus what is simply out of scope.

## Layout of the source

| Path | What it holds |
|---|---|
| `browser.f` | the windowed shell: toolbar, address bar, scrolling, history, link clicks, `--screenshot` |
| `src/browser/page.f` | the page pipeline shared with the tests: fetch, parse, stylesheets, images, cascade, layout, paint |
| `src/html/` | `decode.f` (UTF-8 to ASCII-safe), `entities.f`, `tokenizer.f`, `parser.f` (tree builder) |
| `src/dom/node.f` | the `Node` tree, registry-backed parent lookup |
| `src/css/` | `parser.f` (rules, selectors, `@media`), `ua.f` (default stylesheet), `style.f` (computed `Style`), `cascade.f` (matching, specificity, shorthands, computed values) |
| `src/layout/layout.f` | box tree, block and inline formatting, tables, intrinsic widths |
| `src/paint/paint.f` | painting and hit testing |
| `src/net/fetch.f` | URL resolution, HTTP(S) with redirects, local files |
| `src/util/` | `text.f` (the string helpers `text` lacks), `color.f`, `named_colors.f` |
| `tests/` | unit suites, offscreen pixel checks, the runner |
| `tools/festina-generic` | builds for a generic x86-64 CPU so valgrind can run the result |

About 6,000 lines of Festina in `src/` and `browser.f`.

## Tests

```bash
FESTINA_HOME=/path/to/festina tests/run.sh             # native
FESTINA_HOME=/path/to/festina tests/run.sh --valgrind  # generic-CPU builds under valgrind
```

The runner compiles and runs every suite in `tests/unit/` (utilities,
HTML parser, CSS parser, cascade, layout geometry) and `tests/render/`
(the pipeline painting offscreen, checked with `getPixelColor`), then
renders every example headlessly. There is no test framework:
`tests/assert.f` is a dozen lines and the suites are ordinary Festina
programs. The graphics functions used by the tests work without a
display; the windowed shell was exercised under Xvfb with xdotool
(scrolling, hovering, following a link, typing an address, going back).

## Performance

Measured with `ARCHTELOS_TIMING=1` on Festina's own documentation pages
fetched over HTTPS, after the fixes described in FINDINGS.md:

| Page | Elements | Document height | Parse | Cascade | Layout | Paint |
|---|---|---|---|---|---|---|
| docs/index.html | ~1,000 | 11,609 px | 3 ms | 102 ms | 19 ms | 4 ms |
| docs/api.html | 4,470 | 97,584 px | 22 ms | 110 ms | 247 ms | 19 ms |

Before those fixes the same two pages took 21 s and 43 s; the cause,
and why it matters for Festina, is the first entry of FINDINGS.md.

## License

MIT, like Festina. See [LICENSE](LICENSE).
