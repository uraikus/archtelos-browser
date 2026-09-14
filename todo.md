# Roadmap

Open work and deliberate non-work. Everything here is future tense on
purpose; every other document except changelog.md and benchmarks.md
describes the present (CLAUDE.md, §3).

## CSS: move to the 2026 snapshot

The style engine is written against CSS as generally understood rather
than against a specific edition. The target is
**[CSS Snapshot 2026](https://www.w3.org/TR/css-2026/)**, which names
the modules that are stable enough to implement, the same way the WHATWG
HTML Living Standard now governs the parser.

The work, in the order it is worth doing:

1. **Read the snapshot and write down the delta.** Produce a table of
   the modules it lists against what `src/css/` implements, so the rest
   of this section can be replaced by something measured rather than
   guessed.
2. **Find a conformance corpus, as was done for HTML.** The HTML parser
   went from 20% to 93% against the standard's own tests, level with
   Chromium,
   and the only reason that was possible is that a corpus existed and
   could be run. `web-platform-tests/css` is the equivalent; the first
   question is which of its tests can run without JavaScript, since the
   reference-comparison harness assumes a scripting browser. A pixel
   comparison against Chromium on a fixed page set (both already wired
   up in `tests/chromium.py`) may be the more practical instrument.
3. **Selectors Level 4**: `:is()`, `:where()`, `:has()`, `:not()` with a
   full selector list rather than one compound, and the case-insensitive
   attribute flag. The parser already rejects what it does not
   understand, so these fail closed rather than wrongly.
4. **Cascade Level 5**: `@layer` ordering (blocks are currently
   flattened and their contents used), `revert`, and `!important`
   interaction with layers.
5. **Values Level 4**: `calc()`, `min()`, `max()`, `clamp()`, and custom
   properties with `var()`. Custom properties are currently dropped at
   parse time.
6. **Box model and layout modules**: `position`, floats, Flexbox,
   Grid — see the layout section below, which is where the real work is.
7. **Colors Level 4/5**: `lab()`, `lch()`, `oklab()`, `oklch()`,
   `color-mix()`. The runtime color model is already a packed RGBA int,
   so these are parse-and-convert rather than architecture.

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
