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

1. **`all: inherit`**, the one CSS-wide keyword left: `inherit`,
   `initial`, `unset`, `revert` and `revert-layer` all work on their
   own, and `all` carries every one of them but this. `all` itself is
   done — it drops every declaration
   before it in the block; for `initial` it computes the element as
   though it had no parent, which is what every default in
   `computeStyleValues` already means by "root"; for `revert` it puts
   the previous origin's declarations back; and `unset` needs nothing
   beyond the dropping, because taking the parent's value for an
   inherited property and the initial value for the rest is what the
   ordinary cascade does. `inherit` is the one that does not fit:
   giving a *non-inherited* property the parent's value means copying
   the parent style field by field, and a hand-written list of a
   struct's fields is exactly what rotted in `styleDigest`. It wants a
   generated copy, or a language that can copy a struct by value.

### Then the official definition, largest holes first

1. **What is left of the CSS2 chapters**: nothing whole. Paged media
   (§13) is in -- `@page` with `size` and `margin`, the page selectors,
   named pages, the three `page-break-*` properties and a `--print` that
   writes one image per page -- but three parts of it are not:
   the **margin boxes** (`@top-center` and its fifteen siblings), which
   are parsed and dropped because each is a box generated from `content`
   in a place the layout engine has no notion of; **the side a
   `break-before: left` asks for**, which needs a blank page generated to
   put the next one on the right side; and **a page's own `size` when a
   named page declares a different one**, because the document is laid
   out once at the first page's width and a page that wanted a wider
   sheet would need a second layout. A wheel
   over a scroll container scrolls it, the thumb follows, and the thumb
   can be taken hold of and dragged. Both axes scroll, both thumbs drag,
   and a wheel tilted sideways scrolls a container across **on X11 and
   nowhere else**: the language has no horizontal wheel event, and no
   event of any kind carries a modifier, so neither a horizontal wheel
   nor shift-wheel is expressible as such. X11 happens to send a tilt as
   a press of button 6 or 7 and this reads those; a Windows build reads
   `WM_MOUSEWHEEL` only, so the same gesture produces nothing there
   (FINDINGS.md, finding 38; festina.md §3s). What is also missing is a
   keyboard scroll of the focused container, `scroll-behavior`, and a
   click on the empty part of a track, which every browser treats as a
   page up or down.

   Positioning (§9.3), floats (§9.5), generated content (§12) and
   `overflow: hidden` clipping (§11) are done.
2. **Flexible Box 1 is done**, as far as anything here measures it:
   the automatic minimum size of §4.5, §9.7's freeze-and-repeat, `order`
   and both reverse directions all answer what Chromium answers on the
   same markup. Three things this list called missing already worked --
   `flex-basis: content`, a flex container as an item of another, and
   `order` -- and checking each against Chromium before writing anything
   is what found the one that did not: a reverse direction packed its
   items against the near edge where the standard packs them against the
   far one. `flex-wrap`,
   `align-content`, `baseline` alignment and auto margins are done.
3. **The pseudo-elements this does not have.** `::before`, `::after`,
   `::first-letter`, `::first-line` and `::marker` are done;
   `::selection`, `::placeholder`, `::backdrop` and `::target-text` are
   not, and the first three of those need something this browser has no
   notion of -- a selection, a placeholder attribute laid out as text,
   and a top layer. Two limits of `::first-line` are worth naming rather than
   leaving to be discovered: the restricted property set the standard
   defines for it is not enforced, so a declaration the standard would
   ignore there is applied instead (none of the ones that would matter
   reach a text box, but the engine does not know that), and a rule that
   changes the line's metrics re-measures the words on the line rather
   than re-running the line breaker, so a word that no longer fits moves
   to the second line without the first line being broken again.

   None of this is gradeable by the selector instrument -- a
   pseudo-element selects part of an element rather than an element, so
   `querySelectorAll` has no answer to compare against -- nor by the
   property instrument, which cannot see `counter-reset`,
   `counter-increment` or `quotes` because Chromium does not enumerate
   them on a computed style. It grades `content` on an ordinary
   element, which is a different feature of the same property and is
   done: `content: url()` there replaces the element's contents. The
   pseudo-element half is measured by geometry and by the generated text
   and pixels, as tests/unit/test_counters.f, tests/unit/test_quotes.f
   and tests/render/content.f do.
4. **What is left of CSS Images.** The level itself is done -- linear,
   radial and conic gradients with interpolation hints and every
   degenerate case, `object-fit`, `object-position`, `object-view-box`,
   `image()`, `image-set()` and `cross-fade()`. Two limits are worth
   naming rather than leaving to be found. `image()`'s colour fallback
   is read and dropped, because a solid colour is an image the runtime
   cannot make, and the source it names always loads in the tests, so
   the fallback has never had to show. And `cross-fade()` blits the
   second image over the first, which is exactly the standard's mix for
   two opaque images and an approximation where either has alpha of its
   own: the correct form needs both mixed in premultiplied space before
   either is composited, which needs an offscreen image per image
   rather than per layer.

   **Chromium's pixels are ground truth again**, read by
   `tests/chromium.py pixels`. The full `chrome` binary in this
   container writes a screenshot whose first scanline is correct and
   whose every other row is blank -- a 40x40 block of flat colour comes
   back as one row of colour and 39 of white, whatever
   `--virtual-time-budget`, `--run-all-compositor-stages-before-draw` or
   a software rasterizer is asked of it -- but the Playwright
   `headless_shell` binary beside it rasterizes the whole page, and that
   is the one the pixel mode runs. `object-fit`, `object-position` and
   the gradients are still graded against the specifications' own
   algorithms, which is exact where it applies; what the pixel mode adds
   is an answer for the questions no algorithm settles on its own, such
   as where a tiling starts.
5. **Backgrounds and Borders 3, completed**: **`text-shadow`'s blur**,
   which is still repeated draws at a fraction of the alpha where
   `box-shadow`'s is now the standard's Gaussian. Text is not a
   rectangle, so the closed form `box-shadow` uses does not carry over:
   what would is blurring the glyphs' own coverage, which means reading
   a painted pixel back, and the language cannot (FINDINGS.md, "a
   painted pixel can be compared but never read"). **And an `inset`
   shadow does not follow a `border-radius`** where an outer one now
   does: it is drawn as a frame of strips whatever the box's corners do.
   The shape is the complement of the outer one, so the sum over rows an
   outer corner uses carries over, but the strips it would replace are
   also what keeps an inset shadow inside the padding box, and that
   clip has to be made to follow the inner curve at the same time.

   **A square shadow corner could be cached the way a round one is.**
   A round corner is one image, built once per distinct shadow and
   blitted; a square one is separable, so it is a one-pixel ramp blitted
   once per row of the blur's reach -- thirty-six blits to a corner at a
   blur of 12. On a page of 355 cards sharing a shadow the round path
   measures 27-31 ms against the square path's 43-48, which is the
   difference those blits make. The same 2D cache would suit the square
   corners; what it costs is memory, one image per distinct shadow
   rather than two ramps.

   A single background image from `url()` with `repeat`,
   `position`, `size`, `origin` and `clip` is done, as many layers deep as
   a page asks for, and so is every border
   style, per side, and a radius on each corner separately — in lengths
   or percentages, with the elliptical `/` form that gives a corner two
   radii, and the standard's overlap scaling where two on an edge would
   meet. A background clipped to the padding or
   content edge still uses the border box's `border-radius` rather than
   the smaller inner curve, which needs the rounded-rectangle path that
   an image layer does not have (FINDINGS.md, "an image is a drawable
   surface with a smaller API").
6. **Fonts 3**, which is **blocked on Festina rather than on effort**: a
   numeric `font-weight` has nowhere to go, because the runtime stores
   the weight in a two-valued Cairo enum and decides it by searching the
   style string for `bold`; and `@font-face` cannot be done at all,
   because `cairo_select_font_face` picks a family from the system and
   no call loads a font file. FINDINGS.md has the measurements and
   festina.md §3l the proposal. Until Festina grows either, the most
   this item can gain is `font-variant` and `font-stretch`, which are
   the parts that do not need a font the system lacks.
7. **Counter Styles 3, completed**: the `range`, `fallback` and
   `speak-as` descriptors; the `symbols()` function; and the predefined
   styles that need a table this repository would have to vendor --
   `hebrew`, `armenian`, `georgian` and the East Asian ones beyond
   `cjk-decimal`. What is left of Lists 3 is `list-style-image`, which
   needs a fetched image for the marker.
8. **Transforms 1, completed**: a transformed box should establish a
   stacking context and a containing block for its positioned
   descendants, and hit testing should use the inverse transform so a
   click lands where the box is drawn rather than where it was laid
   out. `skew()` and `matrix()` are blocked on Festina rather than on
   effort: the canvas has no call that takes a matrix (FINDINGS.md,
   finding 33, festina.md §3n).
9. **Containment 1, completed**: layout and style containment are
   computed and change nothing, because nothing escapes a box that way
   yet — there is no counter or quote scope to cut, and a float does
   not leave its formatting context because none is established.
   `content-visibility: auto` needs to know what is on screen.
10. **Compositing and Blending 1 is blocked on Festina**, like Fonts 3:
   `mix-blend-mode`, `isolation` and `background-blend-mode` all need a
   compositing operator, and the runtime sets `CAIRO_OPERATOR_SOURCE`
   everywhere with no call to change it. Cairo has every Porter-Duff
   and separable blend operator; the entry point is what is missing.
11. **Grid, completed**: **a subgrid's own line names and its items'
    contribution to the parent's track sizing**. A subgrid takes the
    sizes of the lines it spans and places its items on them, which is
    what the feature is for; what it does not do is let its items'
    content widen one of those tracks, which the standard has the parent
    take into account, and it does not accept a line-name list of its
    own beside the keyword. Subgrid itself, named lines,
    `grid-template-areas`, the track sizing functions — `minmax()`,
    `min-content`, `max-content`, `fit-content()` — `repeat()` with
    `auto-fill` and `auto-fit`, and dense packing are done. Three divergences are left in what is
    done. A placement naming a line the template does not know leaves
    that edge automatic, where the standard creates an implicit line of
    that name after the explicit grid — Chromium puts `grid-area: zz` on
    a two-column grid at the fourth column line and the fourth row line,
    and this puts it wherever auto-placement does. A track's size comes
    from the items that sit in it alone, so an item spanning two tracks
    grows neither of them. And `justify-content` does not position the
    tracks, so the `normal` that stretches an `auto` track and the
    `start` that does not are one value here: the stretching happens
    either way.
12. **Multi-column 1, completed**: a spanner that sits below the
    container's own children, which needs its ancestors broken around
    it; and real fragment boxes, so that a subtree nested
    below those children can be broken and a split child's background
    paints in each column rather than only the first. Fragment boxes are what
    Fragmentation 3 still wants too: `break-before` and `break-after`
    decide where a column breaks, but a break can only fall between
    the container's own children or between one child's lines, so
    `break-inside: avoid` on a grandchild changes nothing, and
    `box-decoration-break` has no two boxes to choose between. That is
    one piece of work for paged media as well.
13. The remainder of the official definition, lower value for this
   renderer but still part of the definition: Basic User Interface 3's
   `cursor`, `resize` and `appearance`, which need window APIs Festina
   does not expose, and Easing 1, which describes the timing functions
   of transitions and animations and needs a clock and a repaint loop
   rather than a property.
14. **Writing Modes 3, completed**: `writing-mode` and
    `text-orientation`, which need a second layout axis rather than a
    property; reordering across two inline boxes on one line rather than
    within each, which is what would let an isolate differ from an
    embedding here rather than only in its own content; rule W1, which
    resolves a combining mark to the class of the character it sits on,
    and rule N0, which mirrors a bracket inside a right-to-left run with
    its partner — both want the Unicode database this repository does
    not vendor, as the character classes themselves do; and Arabic
    shaping, which needs contextual forms the toy font API does not
    offer (FINDINGS.md, finding 31).

### Filter Effects 1, when the language allows it

**Blocked, and not on the work.** A filter is a function over the pixels
an element and its descendants painted, and this browser already paints
a subtree into an image — that is how `clip-path` and `overflow: hidden`
work. What it cannot do is read a pixel back: `img.getPixelColor`
returns a `color`, and a `color` supports equality and nothing else
(FINDINGS.md, finding 35; the proposal is festina.md, 3p). The pass over
the pixels is a dozen lines and cannot be written.

The part that could be done in advance has been. The matrices below are
Filter Effects 1 §8, derived in a separate script from the specification
text, and they agree with Chromium 141 on every one of twenty-seven
cases — seven functions against three colours — taken from a canvas
with `ctx.filter` and `getImageData`, which needs no screenshot.

The one thing the specification leaves open is how a real number becomes
an eight-bit channel, and Chromium is not uniform: the matrix filters
(`grayscale`, `sepia`, `saturate`, `hue-rotate`) round to nearest and
the component-transfer ones (`invert`, `brightness`, `contrast`)
truncate — what a matrix applied in fixed point and a component lookup
table each do. Following that rule reproduces all twenty-seven exactly;
either rule alone misses eight or eleven of them by one.

| filter | on rgb(200,100,50) | on rgb(255,0,0) | on rgb(0,128,255) |
|---|---|---|---|
| `grayscale(1)` | 118,118,118 | 54,54,54 | 110,110,110 |
| `grayscale(0.5)` | 159,109,84 | 155,27,27 | 55,119,182 |
| `sepia(1)` | 165,147,114 | 100,89,69 | 147,131,102 |
| `saturate(0)` | 118,118,118 | — | — |
| `saturate(2)` | 255,82,0 | — | 0,146,255 |
| `hue-rotate(90deg)` | 50,146,35 | 0,91,0 | 255,56,220 |
| `invert(1)` | 55,155,205 | — | — |
| `invert(0.25)` | 163,113,88 | 191,63,63 | 63,127,191 |
| `brightness(0.5)` | 100,50,25 | 127,0,0 | — |
| `brightness(1.5)` | 255,150,75 | — | 0,192,255 |
| `contrast(2)` | 255,72,0 | — | — |
| `contrast(0.5)` | 163,113,88 | 191,63,63 | 63,127,191 |

`blur()` and `drop-shadow()` are a second question and stay out
regardless: one is a convolution and the other wants the path API an
image does not have.

### What is left of CSS Scroll Snap 1

`scroll-snap-type`, `scroll-snap-align`, `scroll-padding` and
`scroll-margin` are in, and a scroll comes to rest on a snap position.
Two things are not:

**`scroll-snap-stop: always`**, which forbids a scroll from passing a
snap point even when the gesture would carry it further. That needs a
notion this engine has not got: one *gesture*. A wheel event here is a
scroll position, not a movement with a magnitude that might skip several
points, so there is nothing yet for `always` to stop.

**Snap areas deeper than a child.** The positions come from the
container's own children, which is the depth this engine fragments and
measures at everywhere else. A grandchild carrying `scroll-snap-align`
is not a snap point, where in the standard it is.

### What CSS Anchor Positioning still needs

All seven properties work. What sits beside them does not:

**An anchor must be a descendant of the box's containing block**, and
being that containing block is not enough. A box inside its own anchor,
and a box in a `position: relative` block whose anchor is outside it,
are both unanchored in Chromium and both find their anchor here. The
placement pass carries a containing block's four numbers rather than its
identity, so it cannot ask; giving it the identity is the work.

`position-visibility` treats **`anchors-visible` as `always`**. Telling
the two apart needs the anchor scrolled out of a scrollport while the
box stays visible, and `position-area` ties the box to the anchor, so
both leave together; a static render has no such state. That is a
measurement that could not be made rather than one that was skipped,
and it is recorded here for whoever can make it.

Also missing: the `anchor()` and `anchor-size()` functions, which give
an inset or a size from the anchor's own box rather than choosing a
region; an anchor that is itself anchor-positioned, which would need a
second round of the placement pass rather than the one this does; and
`position-area`'s effect on a box whose `width` or `height` is `auto`,
which should size the box to the region rather than shrink to fit.

### What CSS Motion Path 1 still needs

All five properties work. What is not done:

**Curves.** Every path becomes a polyline, so `path()` reads `M`, `L`,
`H`, `V` and `Z` and stops where a `C`, `Q`, `S`, `T` or `A` begins. A
curve wants either a flattening step before the polyline or a numeric
arc length over the segment; the first is the smaller change and the one
to make.

**A second subpath.** A `path()` with a second `M` ends there, because
joining the two would invent a segment the path does not contain and
count its length. The polyline would have to hold a break.

**`url()`**, which names an SVG element this engine has no way to find.

**The containing block.** A ray's length under a percentage distance,
and a percentage inside a shape, resolve against the parent box here
where the standard says the containing block. Those are the same
rectangle whenever the parent is the containing block, and differ for a
box whose containing block is further up. The painter carries the parent
and not the containing block, which is the same gap the anchor placement
has.

**`inset()` is not a path here.** Chromium puts a start point on the
inset rectangle's top-left corner and then never moves along it at any
distance, which is not a rule worth copying either way. It waits for
something to copy.

**The ray sizing keywords follow the standard rather than the browser**,
which is the one place in this engine that is true. From a ray origin at
`(120, 80)` in a 400x300 block Chromium answers `closest-side` 80 and
`closest-corner` 144.2 -- both right -- and then `farthest-side` 120
where the right edge is 280 away, `farthest-corner` 144.2, which is the
closest one, and `sides` 0 in every case tried. All of it fits one rule:
the sizes come out as the `min` and `max` of the origin's own two
coordinates, as though only the top and left sides existed. A
`circle(25% at 50% 50%)` collapses to a point for the same reason. That
is a defect rather than a decision, so it is written down here and not
copied.

### What `overscroll-behavior` leaves out

All five work: the shorthand and `-x`, `-y`, `-inline`, `-block`. This
is what they were measured against and what is left over.

Chromium's computed values, for a 100x60 `overflow: scroll` box:

| declaration | -x | -y | -inline | -block | shorthand |
|---|---|---|---|---|---|
| `overscroll-behavior: contain` | contain | contain | contain | contain | `contain` |
| `overscroll-behavior: contain none` | contain | none | contain | none | `contain none` |
| `overscroll-behavior: auto contain` | auto | contain | auto | contain | `auto contain` |
| `overscroll-behavior-x: contain` | contain | auto | contain | auto | `contain auto` |
| `overscroll-behavior-y: none` | auto | none | auto | none | `auto none` |
| `overscroll-behavior-block: none` | auto | none | auto | none | `auto none` |
| `overscroll-behavior-inline: contain` | contain | auto | contain | auto | `contain auto` |
| `overscroll-behavior: scroll` | auto | auto | auto | auto | `auto` |

So the shorthand is `<x> <y>` with one value applying to both, an
invalid keyword leaves the initial `auto`, and **the two logical
longhands are the two physical ones under other names**: `inline` reads
back as `-x` and `block` as `-y`, and `dir="rtl"` changes neither. Only
a `writing-mode` could swap those axes and this engine has none, so the
logical pair is a spelling rather than a mapping to resolve. It computes
on a box that does not scroll, too; it simply has no effect there. The
root element's value is `auto`.

**The behaviour cannot be measured from Chromium in this harness, and
the control says so rather than the guess.** A synthetic `WheelEvent` is
untrusted, so dispatching one over a nested scroller already at its end
moves neither the scroller nor its ancestor -- with `contain` *and* with
the default `auto`, where a real wheel would certainly chain. An
instrument whose control cannot move is not measuring the thing.

What the property changes here is therefore checked against this
engine's own scrolling, which is written down and testable:
`scrollContainerAt` in src/paint/paint.f walks outward from the box
under the pointer to the nearest ancestor that can still scroll in the
direction asked for, and `wheelAt` in browser.f gives what is left to
the page. That walk is the chain `contain` and `none` stop, and
`tests/render/overscroll.f` grades it.

**What is left out is the scroll a wheel does not start.** A scroll
this engine performs any other way -- the thumb dragged, a fragment
navigated to -- never chains in the first place, so there is no chain
for the property to stop there and nothing to test. The standard's
affordance half is out for the reason below.

**`contain` and `none` differ in nothing this browser does.** `none`
additionally suppresses the overscroll affordance -- the rubber band, the
pull to refresh -- and there is none to suppress. The two are
distinguishable in the computed style and nowhere else, which is worth
saying rather than implying that one of them does more.

### An inline box's side edges are on the wrong side in right-to-left text

An inline's opening margin, border and padding go on the fragment that
begins it and the closing ones on the fragment that ends it. This
engine puts the opening edge at the fragment's physical **left** and
the closing one at its physical right, which is correct in left-to-right
text and mirrored in right-to-left.

Measured: the same inline in `direction: rtl`, 6px padding and a 4px
border in a 150px paragraph. Chromium puts the opening edge at x 146
to 149, the right-hand end of the first fragment, and the closing one
at x 121 to 124, the left-hand end of the last.

Fixing the side alone would give a half-mirrored result, because the
engine does not reorder inline boxes on a line at all -- bidi
reordering here is within each text fragment and not across two inline
boxes (css-2026.md, CSS Writing Modes 3). The two belong together: the
fragments go into visual order and then the opening edge follows the
inline's start side rather than its left.

### What `initial-letter` was measured to be

A drop cap: `initial-letter: <size> <sink>?`, on `::first-letter`. All
of the following is Chromium 141 on a 300px paragraph at 20px/30px
monospace, and the geometry is simpler than the property's reputation.

**The size is where the letter's baseline sits.** Its cap top is the cap
top of the first line and its baseline is the baseline of line `size`,
so its cap height is one line-height taller for each line it spans.
Rasterised, the ink of an `H`:

| size | ink rows | cap height |
|---|---|---|
| 2 | 7 to 49 | 43 |
| 3 | 7 to 79 | 73 |
| 4 | 8 to 109 | 102 |

Thirty apart each time, which is the line height exactly, and the ink
top does not move. The unscaled `H` at 20px is 13 tall, so the rule is
`cap(size) = cap(1) + (size - 1) x line-height` with nothing else in it.

**The sink is how many lines are shortened, and it is not the size.**
With the default sink -- `floor(size)` -- a size of 3 indents three
lines by the letter's advance and a size of 2 indents two. Declared, it
is the sink alone that counts: `initial-letter: 2 1` and
`initial-letter: 3 1` each indent exactly **one** line, and the lines
after it start at the paragraph's own edge.

**What is left over goes above the text.** The paragraph grows by
`size - sink` lines and the text begins that many lines down, so the
letter's top rises out of the first line rather than its bottom sinking
past the last one. A five-line paragraph is 150 tall at `2` and `3`, 180
at `2 1`, 210 at `3 1` and `4 2`.

| declaration | lines indented | paragraph | text starts |
|---|---|---|---|
| `2` | 2 | +0 lines | line 1 |
| `3` | 3 | +0 | line 1 |
| `2 1` | 1 | +1 | line 2 |
| `3 1` | 1 | +2 | line 3 |
| `4 2` | 2 | +2 | line 3 |

The advance the lines are indented by is the letter's own: 36, 61 and 86
pixels at sizes 2, 3 and 4, against 12 unscaled.

**`getComputedStyle` cannot see the size, so it has to be rasterised.**
Asked for the `font-size` of `::first-letter`, Chromium answers the
paragraph's own `20px` under every value of `initial-letter`, including
the ones where the letter is plainly seven times as wide. That is the
fourth instrument this branch has caught answering a well-formed
falsehood, and the widths above come from pixels for that reason.

**The engine's cap ratio is not Chromium's, so the test must check the
relation and not the widths.** Chromium's letter at size 2 is 60px with
a 43px cap, which makes its monospace cap ratio 0.717; this engine's
`FONT_CAP` is 0.70, so the same rule gives a letter about two per cent
larger. What is the same in both is that the cap height grows by exactly
one line-height per line and the baseline lands on line `size` -- so
that is what to assert, as `text-box-edge` does with the same four
ratios.

### What is left of `anchor()` and `anchor-size()`

`anchor()` works in the four inset properties. `anchor-size()` does
not, and neither function composes inside `calc()`; both are measured
and both are left out for the same structural reason, at the end.

All of the following is Chromium 141, against an anchor whose border
box is x 100 to 220 and y 80 to 140 -- 120 by 60, centre 160, 110 --
with the box absolutely positioned in the same containing block.

**`anchor(<name>? <side>, <fallback>?)` in an inset property** resolves
to a position on the anchor's border box, in the containing block's
coordinates:

| declaration | box | reading |
|---|---|---|
| `left: anchor(--a left)` | x = 100 | the anchor's left edge |
| `left: anchor(--a right)` | x = 220 | its right edge |
| `left: anchor(--a center)` | x = 160 | its centre |
| `left: anchor(--a 25%)` | x = 130 | 100 + a quarter of 120 |
| `left: anchor(--a 0%)` | x = 100 | the start side |
| `left: anchor(--a 100%)` | x = 220 | the end side |
| `right: anchor(--a left)` | x = 70 | the box's *right* edge at 100 |
| `top: anchor(--a top)` | y = 80 | |
| `top: anchor(--a bottom)` | y = 140 | |
| `bottom: anchor(--a top)` | y = 60 | the box's bottom edge at 80 |

**The logical side names are the physical ones here.** `top:
anchor(--a start)` is 80 and `end` is 140, and `left: anchor(--a
self-start)` is 100 -- the block axis runs down and the inline axis
runs right, and this engine has no `writing-mode` to make them
anything else.

**`anchor-size(<name>? <dimension>, <fallback>?)`** gives the anchor's
own size: `width: anchor-size(--a width)` is 120, `height:
anchor-size(--a height)` is 60, and `self-inline` is 120 as well.

**The name may be left out, and then `position-anchor` supplies it.**
`left: anchor(right)` beside `position-anchor: --a` is 220. With no
`position-anchor` either, it has no effect at all.

**The fallback is taken only when the anchor cannot be found.**
`anchor(--missing right, 7px)` gives 7; `anchor-size(--missing width,
5px)` gives 5; `anchor-size(--a width, 5px)` gives 120, because the
anchor was found. With no fallback and no anchor the declaration has no
effect -- `left: anchor(--missing right)` leaves the box at its static
position.

**A margin sits between the anchor and the box.** It is the box's
margin edge that lands on the anchor: `left: anchor(--a right)` with a
10px left margin puts the border box at 230 rather than 220, and
`right: anchor(--a left)` with a 10px right margin puts it at 60 rather
than 70. Down the block axis the same, at 150 and 50.

**Both are refused outside the places the standard allows.**
`margin-left: anchor(--a right)` does nothing. `anchor-size()` on a
`position: static` or `position: relative` box does nothing: the box
came out 780 wide, which is `width: auto` against the body. So the
functions need an absolutely positioned box, and `anchor()` needs an
inset property.

**`anchor()` composes inside `calc()`**: `left: calc(anchor(--a right)
+ 5px)` gives 225. Not implemented -- it needs the calc evaluator to
carry a term that is not a length until the anchor is known, where the
whole-value form needs only the rectangle the positioning pass already
has.

**`anchor-size()` is not implemented either, and the reason is the
ordering.** A placement can wait: `anchor()` in an inset is resolved
after the tree has been laid out, in the same pass as `position-area`,
because moving a box that is already laid out is a shift. A *size*
cannot -- the box has to be laid out at that size in the first place,
and an anchor has no rectangle until the layout it would be measured
from is finished. So it wants a second layout pass, which this engine
already has the shape of for `@container`: lay out, resolve the sizes,
lay out again. `Box.forcedWidthPx` is the hook the second pass would
write to.

### How far `initial-letter` got, and where it stopped

The measurement above is complete. An implementation was written
against it and taken out again rather than left half working, because a
drop cap painted over the text is worse than no drop cap. What follows
is what was learnt, so the next attempt starts where this one stopped.

**The cascade half works and is the easy half.** The size is applied to
the ::first-letter style where it is computed, in `computeFirstLetterFor`
in src/css/cascade.f, because that is the one place the paragraph's own
font size and line height are both to hand. Setting
`ps.fontSize = round((FONT_CAP * base + (size - 1) * lh) / FONT_CAP)`
gave rasterised cap heights of 46, 77 and 110 at sizes 2, 3 and 4
against 14 unscaled -- the right shape, and see the caveat below about
the constant.

**Setting the letter's own `line-height` to `size * lh` puts its
baseline where it belongs, for free.** An inline is centred in its line
box by half-leading, which is negative here, and the sum comes out at
`(size - 1) * lh` below the first line's baseline to within a pixel at
every size tried. No special-case baseline arithmetic is needed.

**The letter has to be an atomic inline, not a block.** CSS2 §9.7 makes
a float block-level, so the first attempt built the letter as
`BOX_BLOCK` -- and the paragraph then wrapped its remaining text in an
anonymous box, which put the float outside the inline formatting context
that was supposed to see it. A `BOX_INLINE` is not painted at all, since
the painter reaches a float through the box tree. `BOX_INLINE_BLOCK` is
the one that works: `boxIsFloated` accepts it, `placeInline` routes
floats before atomics, the painter draws it, and no anonymous box
appears.

**`newBox` will not raise `docHasFloats` for it.** The flag is set from
the box's own node, and the letter is built from a *text* box whose node
does not qualify, so the drop cap has to raise it itself.

**What is still wrong, and is where to start.** With the letter as a
floating atomic inline the lines nearest it are shortened correctly and
the `size - sink` push works, but the block comes out about twice as
tall as it should: a five-line paragraph with `initial-letter: 3`
measured 381 pixels where it should measure about 150. The likely cause
is that the letter is being counted twice -- once as the float it is and
once on the line it also sits on -- or that its 90-pixel line box is
being added to the block's height rather than overlapping it. That is
one measurement away from an answer: print the block's `lines.length`
and each line's `y` and `h` for a paragraph with and without the drop
cap, and see which of the two it is.

**The engine's `FONT_CAP` is not this font's cap ratio, and it shows
here.** Rasterised, the unscaled `H` at 20px is 14 tall, which is
exactly the 0.70 the constant assumes -- but at 63, 106 and 149 pixels
the same letter measures 46, 77 and 110, which are ratios of 0.73, 0.726
and 0.738. So inverting the constant to find a font size overshoots by
about four per cent, and the cap height grows by 31 to 33 pixels a line
where the standard asks for exactly 30. Two honest ways out: measure the
ratio and correct `FONT_CAP` -- which is a change to `text-box-edge`'s
numbers too, so it needs its own measurement and its own commit -- or
keep the constant and say in the test that the step is 31 and why. The
ratio is not constant across sizes either, which is worth writing down
whichever way it goes.

### What CSS Inline 3 still needs

`text-box-trim` and `text-box-edge` work, with the `text-box` shorthand.
What is not done:

**The ideographic edges.** `ideographic` and `ideographic-ink` are
accepted nowhere here: the engine models a font's metrics as four ratios
per em and has no notion of an ideographic box. A pair naming one is
dropped, which leaves `auto`, and that is what Chromium does with a
single keyword too.

**A `cap` or `ex` edge is the same approximation the rest of the engine
makes.** The four ratios -- ascent 0.93, descent 0.24, cap 0.70, ex 0.55
-- stand in for metrics Festina cannot read out of a font, so a family
whose real proportions differ will trim to the wrong place. The numbers
come from Chromium on the monospace family the tests use.

### After the official definition

the media features about a user's own preferences that
this browser has no way to learn (Media Queries 4), and the three about
a folding screen; the gamut mapping Color 4 asks for, since a
colour outside sRGB is clamped per channel here; Display 3's two-value
syntax, and the blockification it asks for, which would make a floated
or absolutely positioned inline-level box the block-level equivalent
instead of leaving its computed display alone; what is left of Text 3 — `line-break`, which is about
CJK, and `text-wrap-style: balance`, which needs the line breaker run
more than once — and what is left of Text Decoration 3:
`text-decoration-skip-ink`, which needs the glyph outlines Festina does
not expose; an emphasis mark that reserves space in the line rather than
falling outside it; and a `wavy` underline drawn as a curve rather than
as stepped segments, which needs the path API an image does not have.
What is left of Shapes 1: `shape-image-threshold`, which needs a shape
read out of an image's alpha channel, and the round outset
`shape-margin` asks for on a polygon, which is a square one here.
What is left of Masking 1: the masks themselves — `mask` and its seven
longhands, `mask-type` and `clip-rule` — and `inset()`'s `round`
radius, both of which want the path API too; and a `clip-path` inside
another clipped subtree, which does not clip again, the same limit
`overflow: hidden` has here.
What is left of Nesting 1: an `&` inside `:is()`, `:where()`, `:not()`
or `:has()`, which needs those to take a complex selector rather than a
compound, and the `:scope` that `&` outside any rule stands for, which
is the root element here and would be the enclosing scope once
`@scope` exists.
These sit in the
snapshot's three lower classes, which is lower than their prominence
suggests.

**`print-color-adjust` and `forced-color-adjust` are two rows this
engine will not take.** Both have values Chromium computes differently
from the initial one, so either would move the count by one the moment
the keyword were stored in the computed style. Neither would change a
pixel: nothing here prints, and there is no forced-colors mode, so both
would be `outline-style` again — a property the instrument scores while
the engine does nothing with it. They stay unimplemented and counted as
such until there is something for them to adjust.

**`image-rendering` is blocked on Festina rather than on effort.** Its
three values choose how a scaled image is filtered, and `drawImage`
scales bilinearly with no way to ask for anything else: a 32x upscale of
a two-pixel image puts a blend in 32 of the 64 pixels across the seam,
and nothing in the canvas state, the image, or `drawImage`'s arguments
changes it. Cairo has the control the runtime does not expose
(FINDINGS.md, finding 36; festina.md §3q). Storing the keyword would
move the count and change no pixel, which is the `outline-style` mistake
again.

**`overflow-clip-margin` needs its meaning pinned down before it is
worth implementing.** It was written far enough to register on the
property instrument and then removed: on a box 60px wide with a 10px
border and `overflow: clip`, Chromium keeps a child's pixel 75px from
the border box's left edge, which the padding box (which ends at 70)
does not contain and the border box (which ends at 80) does. With
`overflow-clip-margin: 20px` the same probe puts the edge at 90, which
is the padding box plus the margin and not the border box plus it. The
two readings disagree by a border width, and a property whose meaning is
not settled is not one to ship for the sake of a count. The probe is
`document.elementFromPoint` at each pixel's centre, which is how
`clip-path`'s own expectations were read.

### The instrument

**Three measurements exist**, each with a floor in `tests/run.sh`:
`tests/conformance/properties.f` reports how many of the 405 CSS
properties the instrument can grade change what this engine renders
(210; Chromium answers for 406, and one of them -- `overlay` -- only the
user agent can set),
`tests/conformance/elements.f` how many of the 122 HTML elements get
the default `display` Chromium gives them (122 of 122), and
`tests/conformance/selectors.f` how many of 61 selectors match the same
elements as Chromium (61). Most entries in the work above should move
the first number, and the runner names every property that still does
nothing. Some cannot: CSS Color 4's colour spaces are a value syntax,
and the instrument asks only whether `color` changes the computed
style, so `tests/unit/test_color4.f` is what grades them.

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
- **Sub-pixel layout.** Every length is an integer, so three items
  sharing 400px are 133, 134 and 133 where a browser keeps 133.33 and
  rounds only when painting. Distributing free space by rounding the
  running total rather than each share puts the *edges* in the right
  place, which is what the flex code now does, but an isolated width can
  still be a pixel off.
- **Vertical writing modes.**

## Networking is blocked on two Festina bugs

Neither is a design decision and neither has a workaround in this
repository. Both are written up in FINDINGS.md with minimal
reproductions and proposed in festina.md.

1. **An HTTP response over 64 KiB takes thirty seconds.** The runtime's
   client reads to EOF rather than to `Content-Length`, and a keep-alive
   server never sends EOF, so the read ends when the 30 second socket
   timeout fires. The bytes are correct; only the wait is wrong. Most
   real pages are over 64 KiB, so this is the single thing standing
   between this browser and the live web. `tests/latencyserver.py`
   serves under the limit to keep the preload benchmark measuring
   prefetching instead of this.
2. **The query string is dropped from every request.** `GET /page?a=1`
   goes out as `GET /page`, with `req.code` 200 and `req.url`
   unchanged, so nothing can detect it. Half the web is behind a query
   string and the URL is the only input `send()` takes.

Until the first is fixed there is no honest end-to-end benchmark against
a real site, and the numbers in benchmarks.md are all local files or a
local server.

## Networking, once it is unblocked

- **Prefetch across a navigation, not only within one.** The preload
  scanner's cache is cleared at the start of every load, so a resource
  shared by two pages is fetched twice. A cache keyed by URL with the
  response's own validators would fix it, and would need the
  conditional-request headers the fetch layer does not send yet.
- **Teach the scanner `media`.** `gatherStylesheets` skips a
  `<link rel=stylesheet media=print>`; the scanner does not, so one gets
  prefetched and thrown away. That is a request nobody wanted, which is
  the one kind of mistake a scanner is not allowed to make. Evaluating
  the query needs `evaluateMediaQuery`, which lives in the CSS layer,
  and `src/net/` does not import the CSS layer — so this is a layering
  question before it is a code one.
- **Let a worker fetch a local file.** A preload worker speaks HTTP and
  nothing else, so a `file://` page dispatches nothing. That is the
  right trade today, because a local read is microseconds, but it makes
  the scanner untestable without a server.
- **Follow redirects on a worker.** A worker cannot call `resolveUrl`
  (a thread body may not call a top-level function, FINDINGS.md), so a
  prefetch that redirects is abandoned and refetched on the main thread.
  Correct, and one round trip wasted.

## Performance

Chromium parses, styles and lays out the 51 KB page about **four times
faster** — 26.0 ms against 101 — with both sides measured from inside and
start-up outside the timer (benchmarks.md). The cascade and layout are
93% of our time and all of the gap, and **layout is the larger half
of the two**. In order:

- **Collecting and applying declarations, now that computing them is
  cheap.** Matching is 12 ms and applying 14 ms of a 35 ms cascade, and
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
- **Give the vectorizer a loop it can take.** LLVM autovectorizes
  Festina's IR and reaches almost none of this browser's hot loops:
  `paintLinearGradient` gets 14 packed operations against 45 scalar
  ones, `asciiIndexOf` and `cascadeMatches` get none, because they exit
  early or chase pointers (benchmarks.md). The gradient row fill is the
  one that could plainly be rewritten branch-free over a row of pixels,
  and it is the same rewrite the offscreen-image item above wants.
- **Layout, which is now the bigger half.** 48 ms against the cascade's
  28: building the box tree is 14 ms, placing text 12, measuring it 9.
  The box tree is rebuilt from scratch on every relayout even when only
  the viewport width changed.
- **Four of those 93 ms are the preload scanner's worker threads**, on a
  page that prefetches nothing: glibc's `malloc` abandons its
  single-threaded fast path at the first `pthread_create` and never
  takes it back, and Festina allocates on almost every operation
  (FINDINGS.md). Festina cannot create a thread on demand, so this is
  not fixable here — festina.md proposes the lazy start that would fix
  it, and until then it is the one place this project breaks its own
  rule that a feature must not cost the pages that do not use it.
- **A string interner.** A large share of both phases is comparing and
  hashing tag, class and property names that could be integers. This
  wants language support to be worth it; see festina.md.

**Do not compare unequal canvases again.** PNG encoding is linear in
pixels and dominates at this page size: the same page onto 800x8000
instead of 800x600 costs 336 ms instead of 120 ms, and all of that
difference is encoding. `tests/bench.sh` pins both engines to 800x600.

## Deliberate non-work

- **Playing audio.** `<audio>` lays out and draws its controls, and it
  does not play. Festina has real audio — `aud`, `.play()`, `.stop()`,
  `.isPlaying()` — but using it links ALSA and libmpg123, and Festina
  links them dynamically, so the produced binary would carry
  `libasound.so.2` and `libmpg123.so.0` as runtime `NEEDED` entries the
  way it already carries `libcairo.so.2`. A browser that cannot start on
  a machine without a sound library is a worse browser, and this is two
  new system dependencies rather than one. festina.md proposes the fix:
  open the audio device lazily, so a program that merely *can* play
  audio does not hard-require the library to start.

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
