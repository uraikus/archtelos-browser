# Roadmap

Open work and deliberate non-work. Everything here is future tense on
purpose; every other document except changelog.md and benchmarks.md
describes the present (CLAUDE.md, §3).

## CSS: move to the 2026 snapshot

Where the engine stands against
**[CSS Snapshot 2026](https://www.w3.org/TR/css-2026/)** is measured,
specification by specification, in [css-2026.md](css-2026.md). The
snapshot's official definition of CSS is 24 specifications; the engine
implements no part of 8 of them. That list, not a sense of what feels
modern, sets the order below.

### The cascade

The seven conformance bugs are fixed: specificity is compared as a
triple, importance inverts the origin order, `inherit` takes the
parent's computed value, `@supports` evaluates its condition,
`text-decoration` and `opacity` no longer inherit, `rem` and `vh`
resolve against the real root font size and viewport, and an unparseable
selector drops its whole rule. What is left of CSS Cascade 4:

1. **`revert`**, which rolls a property back to the value the previous
   cascade origin gave. It behaves as `unset` today because the origins
   are not kept apart once the cascade has run; doing it properly means
   keeping a per-origin computed value, or recomputing with the author
   declarations removed.
2. **`all`**, which sets every property at once to a CSS-wide keyword.

### Then the official definition, largest holes first

1. **The CSS2 chapters that are still missing**: `overflow` clipping
   (§11), which needs a clip region the canvas does not have, and
   generated content with counters (§12), which needs pseudo-elements.
   Positioning (§9.3) and floats (§9.5) are done.
2. **Flexbox, completed**: `flex-wrap`, so a container can be
   multi-line, and the `align-content` that only means something once
   it is; `baseline` alignment; and auto margins inside a flex
   container, which absorb the free space before `justify-content` sees
   it.
3. **Pseudo-elements**: `::before`, `::after`, `::first-line`,
   `::first-letter`. The rest of Selectors 3 is done and measured;
   these are what is left of it, and generated content needs them
   anyway. They are also the one part of Selectors 3 the instrument
   cannot grade, because they select part of an element rather than an
   element, so `querySelectorAll` has no answer to compare against.
4. **CSS Images 3, completed**: `radial-gradient()` and
   `conic-gradient()`, gradient interpolation hints, `object-fit` and
   `object-position`. Linear gradients are done; a radial one needs the
   same band machinery with circles instead of strips.
5. **Backgrounds and Borders 3, completed**: background images and
   layers with position, repeat, size and clip; `box-shadow`;
   `border-image`; and border styles that paint as something other than
   solid.
6. **Fonts 3**: a real numeric `font-weight` instead of a boolean, and
   `@font-face`.
7. **Counter Styles 3**, which also fixes the list markers: today
   `lower-alpha`, `upper-alpha`, `lower-roman` and `upper-roman` all
   render as arabic numerals.
8. The remainder of the official definition, lower value for this
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

**Two measurements exist now**, both with floors in `tests/run.sh`:
`tests/conformance/properties.f` reports how many of the 373 CSS
properties Chromium knows change what this engine renders (67), and
`tests/conformance/elements.f` how many of the 121 HTML elements get
the default `display` Chromium gives them (121 of 121). Each entry in
the work above should move the first number, and the runner names every
property that still does nothing.

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

## A margin that collapses through to the root is dropped

`<body style="margin:0"><div style="margin-top:40px">` puts the div at
the very top. Chromium puts it at 40, and says so:
`getBoundingClientRect().top` is 40 there and 0 here.

`layoutDocument` computes the margin collapsing into the root and never
applies it, because applying it at the root double-counts the ordinary
case where `layoutBlock` already has. The fix is to separate the margin
that collapses *through* the root from the one that collapses *into* it.
Found while testing absolute positioning, which resolves against the
ancestor's border box and so depends on it.

## Layout

The layout engine handles normal flow well and does not attempt the
rest. In rough order of how often real pages need it:

- **Block formatting contexts.** A float belongs to one and cannot
  escape it; there is a single float list for the document instead, so
  `overflow: hidden` or an inline-block does not contain a float, and a
  float does not grow the parent that holds it.
- **`position: sticky`**, which computes as `relative` because nothing
  in layout knows the scroll offset.
- **Multi-line flex containers.** `flex-wrap` is not implemented, so a
  row that overflows its container shrinks rather than wrapping, and
  `align-content` has no lines to distribute.
- **Grid**, which still falls back to block layout.
- **`overflow: hidden`** clips nothing: the canvas has no clip region,
  so a clipped box would need to be drawn into an offscreen image and
  composited. See festina.md.
- **Generated content** (`::before`, `::after`), which the selector
  parser already recognizes and refuses to match.
- **Vertical writing modes**, **multi-column**, **`aspect-ratio`**.

## Performance

Chromium parses, styles and lays out the 51 KB page about **3.3 times
faster** — 25.5 ms against 85 — with both sides measured from inside and
start-up outside the timer (benchmarks.md). The cascade and layout are
88% of our time and all of the gap, and **layout is now the larger half
of the two**. In order:

- **Collecting and applying declarations, now that computing them is
  cheap.** Matching is 7 ms and applying 13 ms of a 31 ms cascade, and
  both are still paid per element: 8,578 selector tests and 11,614
  declarations applied into a fresh map. The same insight that made
  computing cheap applies again — an element whose matched rule set is
  identical to a sibling's could share the merged declaration map too,
  and then the whole cascade would be paid once per distinct style
  rather than once per element.
- **Read the declarations an element has, rather than asking for every
  property it might have.** `computeStyle` looks up about 73 named
  properties per element and 83% of them find nothing. This matters much
  less now that a distinct style is computed only 24 times on the
  benchmark page, but it is still the shape that keeps the phase flat as
  more properties land.
- **An angled gradient is painted a rectangle per band per row**, which
  is 14 ms for sixty boxes where an axis-aligned one is 1 ms
  (benchmarks.md). Rendering the gradient once into an offscreen image
  and drawing that image would make the angle free; `blankImage` and
  image drawing exist, so this needs no new language feature.
- **Layout, which is now the bigger half.** 48 ms against the cascade's
  28: building the box tree is 14 ms, placing text 12, measuring it 9.
  The box tree is rebuilt from scratch on every relayout even when only
  the viewport width changed.
- **A string interner.** A large share of both phases is comparing and
  hashing tag, class and property names that could be integers. This
  wants language support to be worth it; see festina.md.

**Do not compare unequal canvases again.** PNG encoding is linear in
pixels and dominates at this page size: the same page onto 800x8000
instead of 800x600 costs 336 ms instead of 120 ms, and all of that
difference is encoding. `tests/bench.sh` pins both engines to 800x600.

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
