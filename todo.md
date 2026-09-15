# Roadmap

Open work and deliberate non-work. Everything here is future tense on
purpose; every other document except changelog.md and benchmarks.md
describes the present (CLAUDE.md, §3).

## CSS: move to the 2026 snapshot

Where the style engine stands against
**[CSS Snapshot 2026](https://www.w3.org/TR/css-2026/)** is measured,
module by module, in [css-2026.md](css-2026.md). This section is the
work that measurement implies, in the order it is worth doing.

1. **Fix the cascade bugs before adding anything.** Each is small, each
   is wrong on ordinary pages today, and every feature built on top
   inherits the error:
   - Compare specificity as a triple rather than collapsing it into one
     integer weighted 10000 / 100 / 1, where a hundred classes tie an id
     and a hundred and one beat it.
   - Make `!important` invert the origin order, so an important UA rule
     beats an important author rule.
   - Make `inherit` return the parent's value. It returns the initial
     value for every property except a handful.
   - Stop inheriting `text-decoration`; propagate it to descendants the
     way the standard does. Stop inheriting `opacity` at all.
   - Evaluate the `@supports` condition. Applying every block means a
     page's fallback and its enhancement both land.
   - Resolve `rem` against the real root font size and `vh` against the
     real viewport height, which is still the 600 its initializer sets.
   - Drop a whole rule when one of its selectors will not parse, rather
     than only that selector.
2. **Add `calc()` and custom properties.** `var()` cannot resolve at all:
   custom properties are dropped by name at parse time. These two are
   what modern stylesheets are written in, so the parser rejecting them
   silently costs more than any single missing property.
3. **Positioning.** `position` is not parsed at all and every box is
   static. This is the single largest visual gap.
4. **Flexbox**, then **Grid**. Both are accepted and laid out as blocks,
   which is why a modern page renders as one column.
5. **Floats**, which are computed and never read, and the `clear` that
   goes with them.
6. **Selectors Level 4**: `:is()`, `:where()`, `:has()`, a full selector
   list inside `:not()`, `An+B` in `:nth-child()`, and the attribute
   case-insensitivity flag, which is parsed and thrown away.
7. **`@layer` ordering.** Layers are flattened into the ordinary cascade
   today, so a layered sheet competes purely on specificity.
8. **Colors Level 4/5**: `lab()`, `lch()`, `oklab()`, `oklch()`,
   `color-mix()`. The runtime color is already a packed RGBA integer, so
   these are parse-and-convert rather than architecture.
9. **`overflow: hidden`**, which is computed and clips nothing. It needs
   a clip region the canvas does not have; see festina.md.
10. **Generated content** (`::before`, `::after`), which needs pseudo-
    element support the selector parser does not have.

**Find a CSS conformance corpus.** The HTML parser went from 20% to 93%
against the standard's own tests, level with Chromium, and the only
reason that was possible is that a corpus existed and could be run.
`css/` in web-platform-tests is the equivalent, and the first question
is how much of it runs without script, since the reference-comparison
harness assumes a scripting browser. A pixel comparison against Chromium
on a fixed page set, both already wired up in `tests/chromium.py`, may be
the more practical instrument.

**The snapshot itself is not reachable from this network.** `www.w3.org`
answers the proxy's CONNECT with 403, so css-2026.md takes its module
axis from the test suite's own directories instead. Someone who can
reach the snapshot should add its classification of each module as
stable, in testing, or abandoned, and check the axis against it.

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
