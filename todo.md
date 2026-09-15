# Roadmap

Open work and deliberate non-work. Everything here is future tense on
purpose; every other document except changelog.md and benchmarks.md
describes the present (CLAUDE.md, §3).

## CSS: move to the 2026 snapshot

Where the engine stands against
**[CSS Snapshot 2026](https://www.w3.org/TR/css-2026/)** is measured,
specification by specification, in [css-2026.md](css-2026.md). The
snapshot's official definition of CSS is 24 specifications; the engine
implements no part of 12 of them. That list, not a sense of what feels
modern, sets the order below.

### First, the cascade bugs

Each is small, each is wrong on ordinary pages today, and every feature
built on top inherits the error. All seven are official-definition
conformance, not polish.

1. Compare specificity as a triple rather than collapsing it into one
   integer weighted 10000 / 100 / 1, where a hundred classes tie an id.
2. Make `!important` invert the origin order. It adds the same constant
   to every origin, so an important author rule beats an important UA
   rule.
3. Make `inherit` return the parent's value. It returns the initial
   value for all but a handful of properties. Add `revert` and `all`,
   and honour `initial` and `unset` outside lengths (CSS Cascade 4).
4. Evaluate the `@supports` condition. Applying every block means a
   page's fallback and its enhancement both land (CSS Conditional 3).
5. Stop inheriting `text-decoration`; propagate it to descendants the
   way the standard does. Stop inheriting `opacity` at all.
6. Resolve `rem` against the real root font size and `vh` against the
   real viewport height, which is still the 600 its initializer sets.
7. Drop a whole rule when one of its selectors will not parse, rather
   than only that selector (CSS Syntax 3).

### Then the official definition, largest holes first

1. **Custom properties and `calc()`.** Both are in the official
   definition, not a later level. Custom properties are dropped by name
   at parse time, so `var()` can never resolve, and `calc()` has no
   parser at all. Modern stylesheets are written in these two.
2. **The CSS2 chapters that are missing**, in this order: positioning
   and `z-index` (§9.3), floats and `clear` (§9.5), `overflow` clipping
   (§11), and generated content with counters (§12). `position` does not
   appear in `src/css/` at all, and `float` and `overflow` are computed
   and never read. These are the four largest visual gaps.
3. **Flexbox.** Accepted as a `display` value and laid out as a block,
   which is why a modern page renders as one column.
4. **Selectors 3, completed**: `An+B` in `:nth-child()`, the
   `:nth-last-child` / `:nth-of-type` / `:nth-last-of-type` /
   `:only-of-type` family, `:empty`, `:target`, `:enabled`, `:disabled`,
   `:checked`, `:lang()`, and pseudo-elements — which generated content
   needs anyway.
5. **CSS Images 3**: gradients, `object-fit`, `object-position`. No CSS
   image of any kind is supported today.
6. **Backgrounds and Borders 3, completed**: background images and
   layers with position, repeat, size and clip; `box-shadow`;
   `border-image`; and border styles that paint as something other than
   solid.
7. **Fonts 3**: a real numeric `font-weight` instead of a boolean, and
   `@font-face`.
8. **Counter Styles 3**, which also fixes the list markers: today
   `lower-alpha`, `upper-alpha`, `lower-roman` and `upper-roman` all
   render as arabic numerals.
9. The remainder of the official definition, lower value for this
   renderer but still part of the definition: Writing Modes 3, Basic
   User Interface 3, Multi-column 1, Transforms 1, Compositing and
   Blending 1, Containment 1, Easing 1, Namespaces 3.

### After the official definition

Grid; `@layer` ordering, which is discarded today (Cascade 5); the
Media Queries 4 range syntax; Selectors 4's `:is()`, `:where()`,
`:has()` and a selector list inside `:not()`; `color-mix()` and the
wider colour spaces; `box-sizing`, since every box is content-box; the
`display` corrections in Display 3; and the Text 3 and Text Decoration 3
gaps. These sit in the snapshot's three lower classes, which is lower
than their prominence suggests.

### The instrument

**Find a CSS conformance corpus.** The HTML parser went from 20% to 93%
against the standard's own tests, level with Chromium, and the only
reason that was possible is that a corpus existed and could be run.
`css/` in web-platform-tests is the equivalent, and the first question
is how much of it runs without script, since the reference-comparison
harness assumes a scripting browser. A pixel comparison against Chromium
on a fixed page set, both already wired up in `tests/chromium.py`, may be
the more practical instrument.

**Re-checking the snapshot needs it supplied.** `www.w3.org` is refused
by this network's egress policy, so a session cannot fetch the document
itself; it has to be handed in.

## HTML: the remaining conformance gap

1,535 of 1,652 tree-construction cases pass, which is what Chromium
passes on the same corpus. Of the 117 failures, 84 are cases Chromium
fails too. The rest, largest first:

- **`tests16.dat`** (11 cases). Script-data tokenizer corners, mostly
  around `<!--` inside a script element and the escaped states.
- **`tests26.dat`** (5) and **`tests1.dat`** (5), **`tests2.dat`** (4),
  **`tests19.dat`** (2): a different small rule each, mostly formatting
  elements interacting with tables and with `<nobr>`.
- **Foreign content corners** (`namespace-sensitivity.dat`,
  `html5test-com.dat`, one case each): breaking out of SVG and MathML
  when an HTML block tag arrives in a namespace-sensitive position.
- **Adoption agency corners** (`adoption01.dat`, `adoption02.dat`,
  `tests6.dat`, `tables01.dat`, one each).
- **Fragment parsing** (195 cases, currently skipped). `innerHTML`
  parsing needs the fragment algorithm and a context element. Nothing
  in the renderer needs it, but it is the single largest block of
  skipped tests.
- **NUL bytes in input** (98 cases, currently skipped). A Festina `text`
  cannot hold a NUL at all, so these cannot run without moving the
  tokenizer onto a byte buffer. See festina.md.
- **Scripted tests** (14 cases, permanently skipped). There is no
  JavaScript engine and there will not be one.

**`processing-instructions.dat` is deliberately not implemented.** The
corpus expects `<?x>` to build a processing-instruction node; the
tokenizer's bogus-comment state builds a comment, and so does Chromium,
which was checked directly. Whichever is right, matching the corpus here
would mean disagreeing with every shipping engine. Revisit when the
standard's text is reachable.

**Where this browser is ahead of Chromium** it is mostly configuration
rather than quality: `noscript01.dat` assumes a disabled scripting flag,
which is permanently true here. `webkit02.dat` and three other files are
genuine leads.

## Layout

The layout engine handles normal flow well and does not attempt the
rest. In rough order of how often real pages need it:

- **Floats.** `float: left/right` is parsed and computed but laid out
  as if static. This is the most visible gap on older pages.
- **Positioning.** `position: relative/absolute/fixed/sticky` are all
  laid out as static.
- **Flexbox**, then **Grid**. Both currently fall back to block layout,
  which is why a modern page lays out as a single column.
- **`overflow: hidden`** clips nothing: the canvas has no clip region,
  so a clipped box would need to be drawn into an offscreen image and
  composited. See festina.md.
- **Generated content** (`::before`, `::after`), which the selector
  parser already recognizes and refuses to match.
- **Vertical writing modes**, **multi-column**, **`aspect-ratio`**.

## Performance

Parsing is 6% of the time to render a 51 KB page; the cascade is 34%
and layout 31% (benchmarks.md). Neither has an obvious hot spot left —
they are constant-factor costs spread evenly. Worth trying, in order:

- **Share computed styles between elements whose matched declarations
  are identical.** Most elements in a real document have the same
  declarations as a sibling.
- **Cache the box tree across relayouts** when only the viewport width
  changed, instead of rebuilding it.
- **A string interner.** A large share of both phases is comparing and
  hashing tag, class and property names that could be integers. This
  wants language support to be worth it; see festina.md.

## Deliberate non-work

- **JavaScript.** Out of scope permanently. It is a second language
  implementation, not a renderer feature, and its absence is what makes
  the scripting flag simple.
- **Networking beyond HTTP(S) GET.** No cookies, no cache, no
  compression negotiation. The fetch layer exists to feed the renderer.
- **Forms that submit**, file uploads, drag and drop.
- **Incremental rendering.** Pages are parsed, laid out and painted in
  full. Streaming layout would complicate every phase for a benefit
  that only shows on slow networks.
- **Benchmarks in CI.** The suite runs on every pull request; the
  benchmarks do not. A shared runner with unknown neighbours measures
  the neighbours, and a timing gate that fires at random teaches people
  to ignore it. `tests/bench.sh` is run deliberately, on one machine,
  with the result written into benchmarks.md.
