# Roadmap

Open work and deliberate non-work. Everything here is future tense on
purpose; every other document except changelog.md and benchmarks.md
describes the present (CLAUDE.md, §3).

## CSS: move to the 2026 snapshot

Where the engine stands against
**[CSS Snapshot 2026](https://www.w3.org/TR/css-2026/)** is measured,
specification by specification, in [css-2026.md](css-2026.md). The
snapshot's official definition of CSS is 24 specifications; the engine
implements no part of 2 of them, and those two are the two it cannot:
Compositing and Blending 1 needs an operator the runtime never changes,
and Easing 1 needs a clock and a repaint loop rather than a property.
That list, not a sense of what feels modern, sets the order below.

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
   named pages, all sixteen margin boxes, the three `page-break-*`
   properties, the four page-side break keywords with the blank page
   they generate, and `@page :blank` for that page -- but one part of it
   is not: **a page's own `size` when a named page declares a different
   one**. The document is laid out once at the first page's width and
   every page is a strip of that one layout, which is what makes a page
   cost nothing to build; a named page on a wider sheet would need its
   own run of the document laid out at its own width and the strips
   stitched together, which is a different paginator rather than a
   second pass over this one. Each page already takes its own *height*
   from its own box, because the paginator asks for the box before it
   measures how much fits. A wheel
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
   `::first-letter`, `::first-line`, `::marker` and `::placeholder` are
   done; `::selection`, `::backdrop` and `::target-text` are not, and
   each needs something this browser has no notion of -- a selection, a
   top layer, and a find-in-page. Two limits of `::first-line` are worth naming rather than
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
   painted pixel can be compared but never read").

   **An `inset` shadow follows the inner curve**, blurred or not. The
   unblurred one is two runs a row between the padding box's curve and
   the hole's, within a pixel of Chromium on every edge. The blurred
   one keeps its two strip passes -- which leave the complement of the
   *square* hole's coverage -- and adds one blit per corner carrying
   `1 - round / (fx*fy)`, which is what painting over rather than
   adding requires: `a` then `d` gives `a + d(1 - a)`, and that equals
   `1 - round` exactly at that `d`. It is between zero and one because
   a rounded hole never covers more than a square one, which is what
   makes it paintable at all, the canvas having no operator that
   subtracts. The corner error goes from 59 units of 255 to one or two.

   **What is left of §6 is `text-shadow`'s blur**, above, and the
   square corners' cache: a round corner is one image built once per
   distinct shadow and blitted, a square one is a one-pixel ramp
   blitted once per row of the blur's reach. On a page of 355 cards
   sharing a shadow the round path measures 27-31 ms against the square
   path's 43-48.

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
   festina.md §3l the proposal. `font-variant-caps` is done, synthesised
   rather than selected, which was the part reachable without a font the
   system lacks. `font-stretch` is not and cannot be: it needs a face
   that carries the widths, and the runtime has no call that asks for
   one.
7. **Counter Styles 3, completed**: the `symbols()` function, which no
   instrument here can yet see, and `speak-as`, which is declined --
   nothing here speaks, so it would be a descriptor parsed and never
   read. `range` and `fallback` are done. Also the predefined
   styles that need a table this repository would have to vendor --
   `hebrew`, `armenian`, `georgian` and the East Asian ones beyond
   `cjk-decimal`. Lists 3 itself is done, `list-style-image` included --
   a fetched image stands in for the marker at its own size, and falls
   back to the type's marker where it could not be fetched.
8. **Transforms 1 is done** but for `skew()` and `matrix()`: a
   transformed box is a containing block for its positioned
   descendants, `absolute` and `fixed` alike, it establishes a stacking
   context, and hit testing goes through the inverse transform so a
   click lands where the box is drawn. The stacking context needed CSS2
   §9.9's painting order underneath it before it could mean anything,
   which is now there. `skew()` and `matrix()` are blocked on Festina
   rather than on effort: the canvas has no call that takes a matrix (FINDINGS.md,
   finding 33, festina.md §3n).

   **Hit testing reads the painter's order backwards, step by step.**
   An out-of-flow box laid out beyond every ancestor's rectangle is
   found -- the out-of-flow boxes are kept in a list as layout passes
   them, and the search falls back to it once the ordinary descent has
   come back empty. The descent runs the painter's passes in reverse:
   the positioned descendants at zero and above, highest `z-index`
   first and latest first within a z; then step 5, the in-flow inline
   content; then step 4, the floats; then step 3, the block-level
   boxes; then the negative ones. Each of those is `hitPhaseWalk`,
   which is `paintPhaseWalk` with every "paint" replaced by "answer if
   it is there", so a click and a pixel cannot drift apart.

   **The outlines are a pass of their own**, above the in-flow content
   and below anything positioned, which is where Chromium draws them
   rather than at the very end §9.9's wording suggests -- measured
   against all four things an outline can overlap, in the section
   below. A box that paints whole draws its own outline inside its own
   subtree, so a float's outline sits at step 4 with the float -- which
   is measured, and is what Chromium does. §9.9 is complete here.
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
11. **Grid**: subgrid itself, its own line names, its items'
    contribution to the parent's track sizing, named lines,
    `grid-template-areas`, the track sizing functions — `minmax()`,
    `min-content`, `max-content`, `fit-content()` — `repeat()` with
    `auto-fill` and `auto-fit`, dense packing, and §8.3's named spans
    in both directions are done. What is left is the parts of Grid 2
    beyond a subgrid's tracks: `masonry` and the `grid-template`
    shorthand's subgrid forms.
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
   `cursor`, which needs a window API Festina does not expose -- the
   pointer's shape is the window system's to set, and nothing here can
   ask it to; and Easing 1, which describes the timing functions of
   transitions and animations and needs a clock and a repaint loop
   rather than a property. `resize` and `appearance` were on this list
   under the same heading and neither belonged there: the grabber is
   painted by this engine and dragged through the mouse events it
   already receives, and a control's chrome is this engine's to draw
   or not to draw.
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

Also missing: an anchor that is itself anchor-positioned, which would
need a second round of the placement pass rather than the one this
does; and `position-area`'s effect on a box whose `width` or `height`
is `auto`, which should size the box to the region rather than shrink
to fit.

Both functions are done, in every place the standard puts them and
inside `calc()`. What they still cannot be written inside is `min()`,
`max()` and `clamp()` -- and that is not a gap in this specification,
because this engine has none of the three for any value at all. It is
in the Values and Units section below.

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

### The measurements `anchor()` and `anchor-size()` were built from

`anchor()` works in the four inset properties and `anchor-size()` in
the fourteen that take it -- the six sizing properties, the four
margins and the four insets -- and both compose inside `calc()`. This
section is the Chromium ground truth all of that was built against,
kept because the next change to either function is graded against it.

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
own border-box size. Measured against a second fixture -- an anchor 100
by 60, with the positioned box declared `width: 40px; height: 20px` so
that a declaration doing nothing is visible as 40 or 20:

| declaration | w | h |
|---|---|---|
| `width: anchor-size(--a width)` | 100 | 20 |
| `height: anchor-size(--a height)` | 40 | 60 |
| `width: anchor-size(--a inline)` | 100 | 20 |
| `width: anchor-size(--a self-inline)` | 100 | 20 |
| `height: anchor-size(--a block)` | 40 | 60 |
| `height: anchor-size(--a self-block)` | 40 | 60 |
| `width: anchor-size(width)` | 100 | 20 |
| `width: anchor-size(--missing width, 5px)` | 5 | 20 |
| `width: anchor-size(--a width, 5px)` | 100 | 20 |
| `width: anchor-size(--missing width)` | **0** | 20 |
| `height: anchor-size(--missing height)` | 40 | **0** |
| `width: anchor-size(--a height)` | **60** | 20 |
| `height: anchor-size(--a width)` | 40 | **100** |
| `min-width: anchor-size(--a width)` | 100 | 20 |
| `max-width: anchor-size(--a width); width: 999px` | 100 | 20 |
| `margin-left: anchor-size(--a width)` | 40 | 20, at x 100 |
| `left: anchor-size(--a width)` | 40 | 20, at x 100 |

Three of those rows do not follow from the name.

**The dimension is independent of the property.** `width:
anchor-size(--a height)` is 60 and `height: anchor-size(--a width)` is
100: the function always names a dimension of the *anchor*, whatever
property it is in.

**With no fallback and no anchor the answer is zero, not nothing.**
`width: anchor-size(--missing width)` gives 0 where the box declared 40,
so the earlier `width: 40px` is not retained. That is the opposite of
`anchor()` in an inset, where the same case leaves the box at its
static position -- the two functions fail differently and the
difference is measured rather than reasoned about.

**It is valid far beyond the sizing properties**, which `anchor()` is
not: `margin-left: anchor(--a right)` does nothing while `margin-left:
anchor-size(--a width)` moves the box by 100. Measured across all four
insets and all four margins, on the same fixture in a 400 by 300
containing block:

| declaration | x | y |
|---|---|---|
| (control) | 0 | 0 |
| `left: anchor-size(--a width)` | 100 | 0 |
| `right: anchor-size(--a width)` | 260 | 0 |
| `top: anchor-size(--a height)` | 0 | 60 |
| `bottom: anchor-size(--a height)` | 0 | 220 |
| `margin-left: anchor-size(--a width)` | 100 | 0 |
| `margin-right: anchor-size(--a width)` | 0 | 0 |
| `margin-top: anchor-size(--a height)` | 0 | 60 |
| `margin-bottom: anchor-size(--a height)` | 0 | 0 |
| `right: 0; margin-right: anchor-size(--a width)` | 260 | 0 |
| `bottom: 0; margin-bottom: anchor-size(--a height)` | 0 | 220 |
| `left: anchor-size(--missing width, 7px)` | 7 | 0 |
| `left: anchor-size(--missing width)` | 0 | 0 |
| `left: anchor(--a right); margin-left: anchor-size(--a width)` | 350 | 0 |
| `padding-left: anchor-size(--a width)` | 0 | 0 |

Every one of those is the length the function resolved to, put in the
property as if it had been written out. `margin-right` and
`margin-bottom` doing nothing on their own is ordinary CSS rather than
anything to do with anchors -- an end-side margin has nothing to push
against while the matching inset is `auto` -- and both work as soon as
that inset is given a value.

**`padding-*` refuses it.** `padding-left: anchor-size(--a width)`
leaves the box 40 wide at x 0, so the declaration is dropped rather
than resolved. Margins and insets take it; padding does not.

**`anchor()` and `anchor-size()` compose across two properties.**
`left: anchor(--a right)` with `margin-left: anchor-size(--a width)`
puts the box at 350 -- the anchor's right edge at 250 plus its own
width as a margin.

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

**Both functions compose inside `calc()`, `min()` and `max()`, and are
not implemented there.** Nineteen declarations in Chromium 141 on the
anchor suite's fixture -- an anchor 100 by 60 whose box is x 150 to 250,
in a containing block 400 by 300, with the positioned box declared 40 by
20:

| declaration | result |
|---|---|
| `left: calc(anchor(--a right) + 5px)` | x 255 |
| `left: calc(anchor(--a right) - 5px)` | x 245 |
| `left: calc(anchor(--a left) + anchor-size(--a width))` | x 250 |
| `width: calc(anchor-size(--a width) + 10px)` | 110 |
| `width: calc(anchor-size(--a width) * 2)` | 200 |
| `width: calc(anchor-size(--a width) / 2)` | 50 |
| `width: calc(2 * anchor-size(--a width))` | 200 |
| `height: calc(anchor-size(--a height) - 10px)` | 50 |
| `left: calc(anchor(--a center) - anchor-size(--a width) / 2)` | x 150 |
| `width: calc(anchor-size(--a width) + 10%)` | 140 |
| `left: calc(calc(anchor(--a right)) + 5px)` | x 255 |
| `width: min(anchor-size(--a width), 50px)` | 50 |
| `width: max(anchor-size(--a width), 500px)` | 500 |
| `margin-left: calc(anchor-size(--a width) + 5px)` | x 105 |

So: either operand order for `*`, ordinary precedence (`/` before `-`),
percentages of the containing block alongside, nesting, two functions in
one expression, and `min()` and `max()` as well as `calc()`.

**Each function fails inside `calc()` the way it fails outside it.**
`calc(anchor-size(--missing width, 5px) + 1px)` is 6 and
`calc(anchor(--missing right, 7px) + 1px)` is 8, so a fallback is taken
before the arithmetic. With no fallback,
`calc(anchor-size(--missing width) + 1px)` is **0** -- the whole
declaration, not just the term -- and `calc(anchor(--missing right) +
1px)` has **no effect** at all, leaving the box at its static position.
That is the same difference the two functions show when written alone.

**Both compose, by one substitution each.** What the standard means by
"the function resolves to a length" is taken literally: the length is
substituted into the expression and the ordinary length parser is run
over the result, so `calc()`'s arithmetic, precedence and nesting come
from the parser that already has them rather than being written a
second time.

The two differ only in where the substitution can be made.
`anchor-size()` resolves to the anchor's own dimension and is done in
the walk that collects the rectangles; its percentage survives as the
`Len`'s own percentage part and is resolved at the property's read
site, against the base a percentage there would have used.
`anchor()` resolves against the *containing block* -- `anchor(--a
right)` in a `left` is the anchor's right edge measured from the
containing block's left -- so its expressions are resolved in the
positioning pass, where `anchorInsetEdge` is. The collecting walk still
records one rectangle per occurrence there, because an expression may
name several anchors and each takes the ones tree order has passed.

**`min()`, `max()` and `clamp()` take both functions in Chromium and
neither anchor function goes inside one here.** The three work over
ordinary lengths, but an anchor function is not one: `anchor-size()` is
substituted into an expression's *text* before the ordinary parser
sees it, and the length parser is what knows `min(`. Making them
compose wants the substitution to happen before that parse rather than
after -- which is a question about where `anchorExprLength` runs, not
about the comparison functions.

**`anchor-size()` works in the six sizing properties** -- `width`,
`height` and their minima and maxima -- on a second layout pass. A
placement can wait: `anchor()` in an inset is resolved after the tree
has been laid out, in the same pass as `position-area`, because moving
a box that is already laid out is a shift. A *size* cannot -- the box
has to be laid out at that size in the first place, and an anchor has
no rectangle until the layout it would be measured from is finished. So
one layout records what each `anchor-size()` came to and the next reads
it, and a pass that changes no resolved size is the fixed point.

**What is carried between the passes is keyed by NODE id.**
`layoutDocumentOnce` rebuilds the box tree and restarts `nextBoxId`, so
a box id carried across a pass names a different box or none.

**The four margins and the four insets take it too**, which `anchor()`
does not. They need no second layout pass of their own -- a margin or an
inset is resolved once the anchor's rectangle is known -- but they read
the same carry, so they are slots on the same list of fourteen.
`padding-*` refuses the function, here as in Chromium.

### A flex container's text and baseline, and what they were built from

Both are done. A flex container wraps each run of its text in an
anonymous block item and takes its baseline from its first item's
first baseline. This section is the Chromium ground truth that was
built against, kept because the next change to either is graded
against it.

Found by writing `baseline-source`'s fixture, which is the only reason
it was found at all: the check that would have agreed with Chromium
was agreeing for the wrong reason. A `display: inline-flex` span
holding `A<br>B`, 60px wide, at a line height of 20:

| | Chromium | this engine, before |
|---|---|---|
| the span's height | 40 | **0** |
| its baseline | its first line | 0 |
| the containing block's height | 40 | 20 |

**Chromium 141, nine flex containers 200px wide at a line height of
20.** The third column is each *element* child's used size, so an
anonymous item shows up only as the height it gives the container:

| the container's content | its height | element children |
|---|---|---|
| `ABC` | 20 | none |
| `A<br>B` | **40** | the `<br>`, 0x19 |
| `A<div>B</div>` | 20 | 10x20 |
| `A<div>B</div>C` | 20 | 10x20 |
| `<div>A</div>` | 20 | 10x20 |
| `<div>A</div><div>B</div>` | 20 | 10x20, 10x20 |
| `A<span style="display:inline-block">B</span>` | 20 | 10x20 |
| whitespace only | **0** | none |
| `A <div>B</div>` | 20 | 10x20 |

**A `flex-direction: column` container counts the items for you**,
because it stacks them, so its height divided by the line height is
how many there are. Ten more, same width and line height:

| the container's content | its height | items | element children |
|---|---|---|---|
| `ABC` | 20 | 1 | none |
| `A<span>B</span>` | 40 | 2 | 200x20 |
| `<span>A</span>` | 20 | 1 | 200x20 |
| `<span>A</span><span>B</span>` | 40 | 2 | 200x20, 200x20 |
| `A<span>B</span>C` | 60 | **3** | 200x20 |
| **`A<br>B`** | **40** | **1** | the `<br>`, 0x19 |
| `<br>` alone | 20 | 1 | 0x19 |
| `A<span style="display:inline-block">B</span>` | 40 | 2 | 200x20 |
| `A<div>B</div>` | 40 | 2 | 200x20 |
| `A<img style="width:10px;height:10px">B` | 50 | **3** | 10x10 |

**Three rules, and the third is the one that is not obvious.** Each
maximal run of text becomes one anonymous *block* flex item, so
`A<span>B</span>C` is three items and `A<img>B` is three -- an element
child breaks the run and becomes an item of its own. A run that is
entirely whitespace produces no item, which is why the whitespace-only
container is zero tall rather than one line tall. And **`<br>` does
not break a run**: `A<br>B` is ONE item forty pixels tall, not three
items of twenty, nineteen and twenty. A forced line break belongs to
the inline content around it rather than being a box the flex
algorithm can place.

All of this happens whether or not there are block-level siblings:
`ABC` alone is one item, and in a row `A<div>B</div>` is two items
side by side, which is why that container is 20 tall and not 40.

**This engine has most of that function already**: `wrapInlineRuns`
builds anonymous block boxes out of runs of inline children and drops
all-blank runs, and `blockifyItems` already turns a flex container's
inline *element* children into block items. What is missing is the
text: a `BOX_TEXT` child is neither, so it becomes an item with no
layout and no height, and the container collapses.

So the wrapping a flex container needs is narrower than
`wrapInlineRuns` -- runs of `BOX_TEXT` and `BOX_BR` only, because
every other element child is an item in its own right.

**This is why the `baseline-source` suite has no inline-flex rows.**
Chromium's answer there is "the span beside it stays at 0", and this
engine also answers 0 -- from a zero-tall box that contributes nothing
to the line rather than from a first-line baseline. A check written
against it would have passed on both sides of the implementation and
measured nothing, which is the shape of instrument this project has
found eight of.

### `baseline-source` is done; this is what it was built from

`first` and `last` work on an atomic inline that has its own line
boxes and on a flex container, whose `auto` is the opposite default --
first rather than last.

CSS Inline 3 §5.1. Which of an atomic inline's baselines the line it
sits on aligns to. Chromium 141, a 60px-wide inline-block holding two
lines of 20px each, beside a one-line span, inside a 400px block:

| declaration | the span's top | the inline-block's computed value |
|---|---|---|
| (control) | 20 | `auto` |
| `baseline-source: auto` | 20 | `auto` |
| **`baseline-source: first`** | **0** | `first` |
| `baseline-source: last` | 20 | `last` |
| `display: inline-flex` | **0** | `auto` |
| `display: inline-flex; baseline-source: first` | 0 | `first` |

**`auto` is not one answer.** An inline-block's `auto` baseline is its
*last* line, so the span beside it drops to the second line's baseline
at 20; an inline-flex's `auto` baseline is its *first*, so the span
stays at 0. The keyword only has to override that default, which is
what makes `first` on an inline-block and `last` on an inline-flex the
two rows that do anything.

The inline-block's own box does not move under any of them -- its top
is 0 and its height 40 throughout -- and neither does the containing
block's height. What moves is the sibling, which is what the test
asserts rather than anything about the declaring element.

**The engine already computes the last-line baseline** --
`b.baseline = last.baseline - b.y` at the end of the inline layout --
so `first` is `b.lines[0]` in the same place, and `auto` is a question
about the box's display type rather than about the property.

### `font-size-adjust` is done; this is what it was built from

All five metrics work and the adjustment is applied at the end of the
cascade, where every `em` has already resolved. What it does not do is
follow Chromium's hinted metric, which moves with the size: this
engine carries one ratio per metric, so the used size is 2.8% out at
16px and 14% at 8px. Closing that needs the runtime to report a font's
x-height at a given size, which it does not (FINDINGS.md).

Chromium 141, a monospace `<span>` of ten `M`s at 16px inside a 400px
block. The control is 96.33 wide, which is ten advances of 0.6021 em.

| declaration | width | computed value |
|---|---|---|
| `0.5` | 85.61 | `0.5` |
| `0.547` | 93.61 | `0.547` |
| `1` | 171.22 | `1` |
| `2` | 342.42 | `2` |
| `0` | 0 | `0` |
| `none` | 96.33 | `none` |
| `from-font` | 96.33 | **`0.5625`** |
| `ex-height 0.5` | 85.61 | `0.5` |
| `cap-height 0.5` | 64.16 | `cap-height 0.5` |
| `ch-width 0.5` | 79.88 | `ch-width 0.5` |
| `ic-width 0.5` | 48.17 | `ic-width 0.5` |
| `ic-height 0.5` | 48.17 | `ic-height 0.5` |
| `cap-height from-font` | 96.33 | **`cap-height 0.75`** |
| `ch-width from-font` | 96.33 | **`ch-width 0.602051`** |
| `ic-width from-font` | 96.33 | **`ic-width 1`** |
| `font-size: 32px; font-size-adjust: 0.5` | 171.22 | `0.5` |
| `font-size: 8px; font-size-adjust: 1` | 77.05 | `1` |
| `-1` | 96.33 | `none` |
| `0.5 0.5` | 96.33 | `none` |
| `ex-height` alone | 96.33 | `none` |
| `50%` | 96.33 | `none` |

**The rule is one line**: the used font size is the specified one times
`<number> / aspect`, where the aspect is the named metric as a fraction
of the em. `from-font` answers the font's own, which is why it changes
nothing and why it is the cheapest way to read the aspect out of
Chromium -- it prints it in the computed value. Four of them, for this
face at 16px: **ex-height 0.5625, cap-height 0.75, ch-width 0.602051,
ic-width and ic-height 1**. `ex-height` is the default, so a bare
number means it.

**The aspect is the hinted metric, not a design constant**, which the
8px row is what shows: `font-size: 8px; font-size-adjust: 1` is 77.05,
which is 12.80px of used size, which is 8 / 0.625 -- an aspect of 5/8
rather than 9/16. At 16px the x-height is 9 pixels and at 8px it is 5,
and the ratio follows. That is the same per-size hinting the `ex` and
`cap` units show, from the same source: 0.5625 is 9/16 and 0.75 is
12/16, which is exactly what `width: 10ex` and `width: 10cap` measure
at 16px.

**So this engine will diverge, and by how much is known.** It carries
one ratio per metric rather than a hinted metric per size, so
`font-size-adjust: 1` at 16px gives 16 / 0.547 = 29.25 where Chromium
gives 16 / 0.5625 = 28.44, 2.8% apart; at 8px it gives 14.6 where
Chromium gives 12.8, 14% apart, because the hinting has moved further
by then and the engine cannot follow it.

**The adjustment changes the used font size and nothing else.**
`font-size` still computes to the specified value, and `width: 2em`
under `font-size-adjust: 1` is 32px rather than 57 -- so `em` resolves
against the specified size. But `line-height: normal` follows the
*adjusted* size: the control's line box is 19 tall and
`font-size-adjust: 1` makes it 33. So the adjustment belongs at the
end of the cascade, after every length has resolved its `em`, with the
line height recomputed where it was `normal`.

**Invalid, all computing to `none`**: a negative number, two numbers, a
metric keyword with no number after it, and a percentage.

### `line-height: normal` is 1.2 here and about 1.16 in Chromium

Measured while correcting the font-relative units. Chromium 141's `lh`
unit under `line-height: normal`, on the monospace face this engine
renders in, `width: 10lh` at five sizes:

| size | Chromium | ratio | this engine |
|---|---|---|---|
| 16px | 190 | 1.1875 | 192 |
| 20px | 240 | 1.2000 | 240 |
| 48px | 560 | 1.1667 | 576 |
| 100px | 1170 | 1.1700 | 1200 |
| 180px | 2090 | 1.1611 | 2160 |

Least squares: `1.1586 x size + 0.654`. This engine computes `normal`
as `1.2 x fontSize`, which agrees at 16 and 20 -- where the existing
check pins it at 19px -- and is 3% tall at 180. That is the same
single-size trap `FONT_CAP` and the `cap` unit both fell into.

**It is recorded rather than fixed, because `line-height: normal` sets
every line box in the engine.** Changing it moves the geometry that the
whole render suite and most of the layout suites assert, and the right
way to do that is to re-derive those numbers from Chromium rather than
to adjust them until they pass again -- which is its own task, and a
large one. The ratio and the intercept above are what it would be
built from.

### What `min()`, `max()` and `clamp()` still leave out

All three work, wherever this engine reads a length. Two things they
do not do.

**A comparison whose answer is deferred cannot go inside a `calc()`.**
`calc(min(100px, 200px) + 10px)` is 110, because the inner comparison
folds to a pixel length; `calc(min(50%, 100px) + 10px)` is refused,
because a `calc()`'s running value is a pixel part and a percentage
part and a deferred comparison is neither until the base is known.
Chromium answers it. Making it work wants `CalcVal` to carry an
operand list of its own, the way `Len` now does, rather than two
floats.

**An unfolded comparison is refused by the properties that read a
length's kind directly** -- `border-radius`, `transform-origin`,
`background-size` and the rest of the `l.kind == LEN_PX || l.kind ==
LEN_PERCENT` sites. That is exactly where `calc(100% - 2em)` is
refused today, so it is one gap rather than two: the fix is those sites
going through `resolveLen`, and it would carry `calc()` with it.

**The measurement below is what all of it was built against.**

CSS Values and Units 4 §10. A `Len` carries a pixel part and a
percentage part separately, so that `calc(100% - 2em)` can wait for the
containing block. A comparison cannot wait the same way:
`min(50%, 200px)` has no answer until the containing block is known,
and the two operands cannot be folded into one pixel-and-percentage
pair beforehand.

**Chromium 141, thirty-six declarations on a block in a containing
block 400 wide and 300 tall.** The box declares `width` unless another
property is named, so `auto` -- 400 -- is what an invalid declaration
reads as.

| declaration | width |
|---|---|
| `min(100px, 200px)` | 100 |
| `max(100px, 200px)` | 200 |
| `min(200px, 100px, 150px)` | 100 |
| `max(100px, 200px, 150px)` | 200 |
| `clamp(50px, 100px, 200px)` | 100 |
| `clamp(150px, 100px, 200px)` | 150 |
| `clamp(50px, 300px, 200px)` | 200 |
| **`clamp(200px, 100px, 50px)`** | **200** |
| `min(10%, 20%)` | 40 |
| `max(10%, 20%)` | 80 |
| **`min(50%, 100px)`** | **100** |
| **`max(50%, 100px)`** | **200** |
| `min(10%, 100px)` | 40 |
| `clamp(10%, 100px, 90%)` | 100 |
| `min(10em, 100px)` | 100 |
| `max(10em, 100px)` | 160 |
| `calc(min(100px, 200px) + 10px)` | 110 |
| `min(calc(50px + 50px), 200px)` | 100 |
| `min(min(100px, 200px), 150px)` | 100 |
| `calc(2 * min(50px, 200px))` | 100 |
| `min(100px, 200px, max(10px, 300px))` | 100 |
| **`min(100px, 5)`** | **400 (invalid)** |
| **`min(100, 200)`** | **400 (invalid)** |
| `min(100px)` | 100 |
| `max(100px)` | 100 |
| **`clamp(100px)`** | **400 (invalid)** |
| `min()` | 400 (invalid) |
| `min( 100px , 200px )` | 100 |
| **`min(100px,)`** | **400 (invalid)** |
| `min(-100px, 100px)` | 0 |
| **`max(0, 100px)`** | **400 (invalid)** |

And where else it is taken, with `width: 100px` beside it:
`margin-left: min(30px, 60px)` is 30, `padding-left:` the same,
`font-size: min(30px, 60px)` is 30 and makes `width: 10em` 300, and
`height: min(10%, 100px)` is 30 against the containing block's 300
while `height: max(10%, 100px)` is 100. So the percentage is the
containing block's on the property's own axis, as it is everywhere.

**Five of those rows are rules rather than arithmetic.**

1. **A percentage is resolved before the comparison, not after.**
   `min(50%, 100px)` is 100 and `max(50%, 100px)` is 200, which is 50%
   of 400 compared against 100 -- so the function cannot be folded into
   one pixel-and-percentage pair at parse time. Either the `Len` gains
   a deferred comparison, which `resolveLen` is the one place to answer
   it in, or the mixed case is refused and that refusal is written down
   here.
2. **`clamp()`'s minimum wins over its maximum.**
   `clamp(200px, 100px, 50px)` is 200, not 50.
3. **A bare number is not a length here, and zero is not exempt.**
   `min(100px, 5)`, `min(100, 200)` and `max(0, 100px)` are all
   invalid, where `calc()` takes a bare number as a multiplier.
4. **`min()` and `max()` take one argument; `clamp()` takes exactly
   three.** `min(100px)` is 100 and `clamp(100px)` is invalid.
5. **A trailing comma is invalid**, and so is an empty argument list.

The property instrument cannot grade a function, so
`tests/unit/test_values.f` is the instrument, at 86 checks. The ones
that earn their place assert `min(10px, 20px)` lands where `10px`
lands, and that the same unfolded comparison answers differently
against two bases -- which is what a folded value could not do.

### What CSS Inline 3 still needs

`text-box-trim` and `text-box-edge` work, with the `text-box` shorthand,
and `initial-letter` makes a drop cap on `::first-letter`: the size puts
the letter's baseline on the baseline of line `size`, the sink says how
many lines are shortened, and what is left over goes above the text.
What is not done:

**The ideographic edges.** `ideographic` and `ideographic-ink` are
accepted nowhere here: the engine models a font's metrics as four ratios
per em and has no notion of an ideographic box. A pair naming one is
dropped, which leaves `auto`, and that is what Chromium does with a
single keyword too.

**A `cap` or `ex` edge is the same approximation the rest of the engine
makes.** The four ratios -- ascent 0.93, descent 0.24, cap 0.733, ex
0.55 -- stand in for metrics Festina cannot read out of a font, so a
family whose real proportions differ will trim to the wrong place. The
numbers are measured against Chromium on the monospace family the tests
use, across a range of sizes; the table is below.

**`initial-letter-align`.** The standard lets the letter's over edge
align to `alphabetic`, `hanging`, `ideographic` or the `border-box`.
Only the alphabetic default is implemented, and the other three need
font metrics this engine does not have -- the same four-ratios-per-em
limit that stops `text-box-edge`'s ideographic edges.

**`initial-letter` on an ordinary inline box.** The property applies to
inline-level boxes as well as to `::first-letter`, and only the
pseudo-element is implemented. The layout is the same; what is missing
is the path that turns a declared inline into the float, because
`splitFirstLetter` is the only place that builds one.

**What this font's four ratios measure, and how they were taken.**
Neither measurement was taken at a single size: a ratio read off one
font size is a ratio plus a rounding error of up to a pixel, which is 5%
at 20px and 0.5% at 180, and reading it at 20px alone is what let
`FONT_CAP` sit at 0.70 rather than 0.733 for as long as it did.

Rasterised through this engine, one `H` on a white canvas, ink rows
scanned top and bottom:

| px | 20 | 48 | 63 | 80 | 100 | 106 | 120 | 149 | 180 |
|---|---|---|---|---|---|---|---|---|---|
| ink | 14 | 35 | 46 | 59 | 73 | 77 | 88 | 110 | 132 |
| ratio | .700 | .729 | .730 | .738 | .730 | .726 | .733 | .738 | .733 |

A least-squares line through the sizes from 48 up is
`0.7367 x size - 0.40`.

Chromium 141, asked for the height of a `text-box-trim: trim-both;
text-box-edge: cap alphabetic` box on the same monospace family, which
is the cap height by definition:

| px | 20 | 48 | 63 | 80 | 100 | 106 | 120 | 149 | 180 |
|---|---|---|---|---|---|---|---|---|---|
| cap | 14 | 35 | 45.56 | 58.56 | 72.91 | 76.81 | 87.22 | 109.33 | 131.47 |
| ratio | .700 | .729 | .723 | .732 | .729 | .725 | .727 | .734 | .730 |

Least squares over the same range: `0.733 x size - 0.41`. Chromium
reports whole pixels up to 48 and fractions above it, which is a
hinted-metrics threshold rather than a property of the font.

**0.70 was right at 20px by coincidence.** 0.733 x 20 is 14.66 and
Chromium answers 14 -- the cap height is the *floor* of the ratio rather
than the nearest integer, which is what the -0.41 intercept is. 0.733
floored reproduces Chromium's answer at every size in the table, to
within half a pixel of the fractional ones; 0.70 rounded was six pixels
short at 180.

The other three stand up. Measured the same way against Chromium, the
ascent runs 0.921 to 0.938 against the constant's 0.93, the descent
0.233 to 0.240 against 0.24, and the x-height 0.542 to 0.550 against
0.55. None is off by as much as one part in a hundred.

**What is left here is a family other than this one.** All four ratios
are constants, and a font with different proportions trims to the wrong
place; reading them out of the font needs metrics Festina does not
expose (FINDINGS.md, "no font metrics beyond an inked height").

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

**`forced-color-adjust` is the one this engine will not take.** It has
values Chromium computes differently from the initial one, so it would
move the count by one the moment the keyword were stored in the computed
style, and no pixel would follow: there is no forced-colors mode here for
it to be about, so it would be `outline-style` again -- a property the
instrument scores while the engine does nothing with it. It stays
unimplemented and counted as such. `print-color-adjust` was on this list
beside it and is no longer: the measurement below found the omission it
overrides, `--no-background-graphics` supplies it, and the property moves
pixels under it.

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

### `zoom`, measured

Twenty declarations in Chromium 141. The box under test is a block in
a containing block 400 wide and 200 tall at 16px/20px monospace, and
its content is ten `M`s, so an unzoomed line of it is 96.33 wide and
20 tall. `x`, `width` and `height` are `getBoundingClientRect`, which
is **device** pixels; `cs.*` is `getComputedStyle`.

| declaration | x | width | height | cs.width | cs.font-size |
|---|---|---|---|---|---|
| (control) | 0 | 400 | 20 | 400px | 16px |
| `zoom: 2` | 0 | **400** | 40 | **200px** | 16px |
| `zoom: 0.5` | 0 | **400** | 10 | **800px** | 16px |
| `zoom: normal` | 0 | 400 | 20 | 400px | 16px |
| `zoom: 2; width: 100px` | 0 | 200 | 40 | 100px | 16px |
| `zoom: 2; width: 50%` | 0 | 200 | 40 | 100px | 16px |
| `zoom: 2; width: 100px; padding: 10px` | 0 | 240 | 80 | 100px | 16px |
| `zoom: 2; width: 100px; border: 4px` | 0 | 216 | 56 | 100px | 16px |
| `zoom: 2; width: 100px; margin-left: 10px` | **20** | 200 | 40 | 100px | 16px |
| `zoom: 2; width: 10em` | 0 | 320 | 40 | 160px | 16px |
| `zoom: 2; font-size: 10px; width: 10em` | 0 | 200 | 40 | 100px | **10px** |
| `zoom: 2; width: 10vw` | 0 | 156 | 40 | 78px | 16px |
| `zoom: 2; width: 10rem` | 0 | 320 | 40 | 160px | 16px |
| `zoom: 2; height: 50px` | 0 | 200 | 100 | 100px | 16px |
| `zoom: 2; line-height: 30px` | 0 | 400 | 60 | 200px | 16px (`cs.line-height` 30px) |
| **`zoom: 0`** | 0 | 100 | 20 | 100px | computed `zoom` is **1** |
| **`zoom: -1`** | 0 | 100 | 20 | 100px | computed `zoom` is **1** |

And nested, a child inside the zoomed box:

| parent / child | the child's width |
|---|---|
| `zoom: 2` / `zoom: 2; width: 50px` | **200** |
| `zoom: 2` / `zoom: 0.5; width: 50px` | **50** |
| `zoom: 2; width: 100px` / `width: 50%` | 100 |

**The model is one sentence: every length zooms exactly once.** A
declared `100px` is 200 device pixels at zoom 2; so are the paddings,
the borders, the margins and the height. `em`, `rem` and `vw` resolve
against the *unzoomed* font size, root font size and viewport and then
zoom, which is why `10em` at 16px is 320 and `10vw` of a 780px
viewport is 156. A **percentage needs nothing**: the containing block
is already in device pixels, so `50%` of a 400-device-pixel block is
200 device pixels and comes out right for free. An `auto` width fills
its containing block in device pixels, which is why the first two rows
are still 400 wide.

**`zoom` compounds down the tree**, so a child of a `zoom: 2` box that
says `zoom: 2` itself is at four, and one that says `0.5` is back at
one. **Zero and a negative are invalid**, computing to `1`.

**And the computed style reports the UNZOOMED value**, which is the
part that decides where this belongs. `cs.width` under `zoom: 2` is
half the device width, `cs.font-size` is the specified 16px or 10px,
and `cs.line-height` is the specified 30px. So the zoom is a *used*
value transform, not a computed one.

**What that costs here.** Scaling every parsed pixel length would be
one line in `lenPx` behind a per-document flag -- percentages, `em`,
`rem` and `vw` all fall out correctly, because each already resolves
to pixels before `lenPx` sees them. The font size cannot join them:
it is an `int` on `Style` that a child's `em` resolves against, so
zooming it there would zoom a child's `em` twice. It has to stay
unzoomed in the computed style and be zoomed where the font is
actually selected and measured -- `setFontFor` and `measureWidth`,
with the effective zoom in the `fontKey` so the width cache does not
serve one zoom's advance at another.

### `resize`, measured

Fourteen declarations in Chromium 141, plus the grabber rasterised
through `headless_shell`. The box under test is 200 by 100 with no
border and no padding; `width` and `height` are
`getBoundingClientRect`, `clientW`/`clientH` are the element's.

| declaration | width | height | clientW | clientH | `cs.resize` |
|---|---|---|---|---|---|
| (control) | 200 | 100 | 200 | 100 | `none` |
| `resize: both; overflow: visible` | 200 | 100 | 200 | 100 | `both` |
| `resize: both; overflow: auto` | 200 | 100 | 200 | 100 | `both` |
| `resize: both; overflow: hidden` | 200 | 100 | 200 | 100 | `both` |
| `resize: both; overflow: scroll` | 200 | 100 | **185** | **85** | `both` |
| `resize: horizontal; overflow: auto` | 200 | 100 | 200 | 100 | `horizontal` |
| `resize: vertical; overflow: auto` | 200 | 100 | 200 | 100 | `vertical` |
| `resize: block; overflow: auto` | 200 | 100 | 200 | 100 | `block` |
| `resize: inline; overflow: auto` | 200 | 100 | 200 | 100 | `inline` |
| `resize: none; overflow: auto` | 200 | 100 | 200 | 100 | `none` |
| `resize: both` (no `overflow`) | 200 | 100 | 200 | 100 | `both` |
| `resize: both; display: inline` | 9.64 | 19 | 0 | 0 | `both` |

**`resize` reserves no space and changes no geometry**, in any
combination. The 185 by 85 row is the two scrollbars `overflow:
scroll` raises, which the control with no `resize` also gets; the
grabber is painted *over* the content rather than beside it. And the
computed value is the declared keyword under every `overflow`,
`visible` included, so `getComputedStyle` cannot tell whether the
property is doing anything.

So the only instrument that can see this property is the painter, and
the grabber is what there is to paint. Rasterised at the bottom-right
of a 100 by 60 box whose inner corner's last pixel is (119, 79):

```
y=72                                   118
y=73                               117
y=74                           116
y=75                       115
y=76                   114                 118
y=77               113                 117
y=78           112                 116
```

Every one of those is `#666666` on white. They are two diagonal
hairlines, at `x + y` = corner − 8 and corner − 4, inside a seven by
seven square inset one pixel from the corner: the first diagonal
crosses the whole square, the second is cut to three pixels by the
inset. The same reading with a 5px border puts them at the same
offsets from the **padding box's** corner rather than the border
box's, so the grabber sits inside the border.

Two more facts the rasteriser gives and the computed style does not.
`horizontal`, `vertical`, `block` and `inline` all paint **the same**
grabber as `both` -- the value constrains the drag, not the drawing.
And `overflow: visible` paints **no** grabber at all, though its
computed `resize` is still `both`: that is the specification's own
"applies to: elements with `overflow` other than `visible`", and it
is the one place the two readings disagree.

### `text-wrap-style`, measured

Chromium 141, a `<p>` of a given width at 16px/20px monospace, read
two ways: the widths `getClientRects` gives a `Range` over the whole
paragraph, and the text each line holds, grouped by the rect top of a
one-character range at each offset. The second reading is what the
first one needed -- a row of widths does not say which words moved.

**`balance` never changes the line count or the block's height.** It
is the same paragraph, broken differently. That holds in every case
below and is the first thing to implement.

**The dominant effect in the obvious fixture is not balancing at
all.** A run of equal words ending in one long one:

| words | `auto` | `balance` |
|---|---|---|
| 3 short + 1 long | `106, 116` | `67, 154` |
| 4 short + 1 long | `145, 116` | `106, 154` |
| 5 short + 1 long | `183, 116` | `145, 154` |
| 6 short + 1 long | `183, 154` | unchanged |
| 8 short + 1 long | `183, 106, 116` | `145, 106, 154` |
| 13 short + 1 long | `183, 183, 106, 116` | `145, 145, 145, 154` |

Every row that moved had a **one-word last line** under `auto`, and
`balance` pulled a word down onto it; every row that did not move
already had two. The three-word row makes the point sharpest: the
widest line went from 116 to **154**, which is worse by every measure
of evenness there is. So Chromium's `balance` carries a widow rule,
and that rule outranks balancing.

**Where the last line already holds two words, balancing is what is
left, and it minimises the widest line.** Thirty random paragraphs of
five to twelve words, twenty-two of them with a two-word last line:
eighteen came back unchanged and the ones that moved improved the
maximum.

| | `auto` | `balance` |
|---|---|---|
| a very short last line | `164, 173, 193, 58` (max 193) | `164, 135, 135, 154` (**max 164**) |
| five lines | `183, 145, 145, 125, 116` (max 183) | `145, 125, 145, 125, 173` (**max 173**) |

So the model to implement is: **the same line count as the greedy
break, and among the assignments with that count the one whose widest
line is narrowest**, with a widow rule that refuses a one-word last
line where another assignment avoids it. CSS Text 4 §6.2 leaves the
algorithm to the user agent and asks only that the difference between
the longest and the shortest line be minimised, so this follows the
standard and Chromium's answers are recorded beside it rather than
copied: the three-word row above is one this engine should *not*
reproduce, because there the widow rule and the standard's own
sentence point opposite ways.

**The threshold is six lines.** A paragraph of five three-character
words per line with a two-character tail leaves a 48-pixel last line
at every length, so `balance` has work to do at every length; it does
it at two, three, four, five and six lines and stops at **seven**.

| lines | `auto` | `balance` |
|---|---|---|
| 2 | `183, 48` | `106, 125` |
| 3 | `183, 183, 48` | `145, 145, 125` |
| 6 | `183 ×5, 48` | `183, 183, 145, 145, 145, 164` |
| **7** | `183 ×6, 48` | **unchanged** |
| 8 and up | | **unchanged** |

**And `pretty` is not `balance`.** It left every one of those rows
alone, including the two-line one, where `balance` moved 48 to 125 --
and yet it agreed with `balance` on `alpha beta gamma delta`, which
`auto` breaks into a one-word last line. So the three answers separate
cleanly:

| | |
|---|---|
| `auto`, `stable` | the greedy break |
| `pretty` | the greedy break, except that a **one-word last line** is refused where another break avoids it |
| `balance` | that widow rule, and then, at **six lines or fewer**, the break whose widest line is narrowest |

which is why the widow rule in the first table outranks balancing: it
is not part of balancing at all, it is the rule `pretty` is made of
and `balance` inherits.

### What `text-wrap-style` leaves out, and where it disagrees

`balance` works, as a search over the **width** the greedy breaker is
given rather than as a second line breaker. Two things follow, and
both are measured rather than assumed.

**Chromium redistributes words; a width search cannot.** On the
six-line fixture above Chromium turns `183 ×5, 48` into
`183, 183, 145, 145, 145, 164` -- five-word lines becoming four-word
ones further down. No single measure produces that: a width narrow
enough to make a line four words makes the *first* line four words
too, and the paragraph runs to seven lines. So on a paragraph of equal
words this engine's search runs, finds that the narrowest measure
giving six lines is the one the greedy break already used, and changes
nothing. Closing that means an optimal line breaker -- a pass over the
break opportunities minimising the widest line, rather than the
greedy one run again -- which is a piece of work in its own right and
would serve `pretty` as well.

**And `pretty` is not implemented.** Its widow rule -- refuse a
one-word last line where another break avoids it -- is measured in the
table above and needs the same optimal breaker, because the break that
avoids the widow is not in general reachable by narrowing the measure:
Chromium's `106, 116` becomes `67, 154`, which is *wider* at the
widest line, and a width search only ever narrows. `stable` is the
greedy break by definition and is complete. Both are kept apart in the
computed style, so the day the breaker arrives they have somewhere to
be read from.

**A float in the content stops balancing.** The second pass would
place the float a second time, since a float is registered with its
formatting context as it is placed. Saving and restoring the float
list around the search would lift that; the balancing this is for is
a paragraph of text, so it has not been.

### CSS Ruby Annotation Layout 1, measured

Nothing of it is implemented, and almost everything it needs is
already here: the tree builder handles `<rt>` and `<rp>`, the
user-agent stylesheet says `ruby { display: ruby }`, and the element
instrument already agrees with Chromium that `rt` is `inline` and `rp`
is `none`. What is missing is the layout.

Chromium 141, `X<ruby>base<rt>ann</rt></ruby>Y` in a 400px paragraph
at 16px/20px monospace, measured from the paragraph's own corner:

| | |
|---|---|
| the paragraph's height | **27**, where a plain line is 20 |
| the `<ruby>` box | 19 tall, at y **7** |
| the `<rt>` box | 9 tall, at y **0** |
| `rt`'s font size | **8px** -- half the element's |
| `ruby-align`'s initial value | `space-around` |
| `ruby-position`'s initial value | `over` |

So the annotation sits in a band above the base, the two **overlap by
two pixels**, and the line grows by seven. `ruby-position: under` puts
the `<rt>` at y 19, below the base, and the paragraph becomes 28 --
one taller than `over`, which is the descender the annotation has to
clear.

**The ruby box is as wide as the wider of the two**, and the
annotation is allowed to overhang when it is the wider: `base` with
`ann` gives a 38.53 box and a 38.52 annotation stretched to match,
while `b` with `annotation` gives a **40.17** box holding a **48.17**
annotation that starts 4 pixels to the *left* of it. Two base/
annotation pairs inside one `<ruby>` are laid out as two such units
side by side, and `<rp>` contributes nothing.

**`ruby-align` has two behaviours in Chromium, not four.** Rasterised,
a four-character annotation over a sixteen-character base puts its ink
at columns 0-19 under `start` and at 67-86 under `center`,
`space-between` **and** `space-around` -- the three are pixel-identical,
so Chromium distributes nothing between the annotation's characters
however the property is spelled. An implementation that centres for
everything but `start` reproduces Chromium exactly, and the two
computed values that matter are still distinct.

### What CSS Ruby Annotation Layout 1 still needs

The layout and both properties work. Three things do not.

**The band is a full annotation line tall**, where Chromium overlaps
it two pixels into the base's ascent: a ruby line is 30 pixels here
against Chromium's 27. Closing that needs the base font's ascent
against its cap height, so that the band can be sunk into the room a
line already leaves above the letters -- which is the same font metric
`initial-letter` and `text-box-edge` read, so it is a small piece of
work rather than a missing capability.

**The base does not break across lines**, because the ruby is an
atomic inline. A `<ruby>` holding a sentence is laid out on one line
and overflows rather than wrapping. Making it break means the bands
stop being two blocks and become a run of base/annotation pairs the
line breaker can split between, which is a different shape of layout
and the largest piece left here.

**`alternate` and `inter-character` behave as `over`.** The first
wants a notion of which side the last annotation went, kept across
sibling rubies; the second is a vertical writing mode, which this
engine does not have at all.

### The `@page` margin boxes, measured

Chromium 141 **implements them**, which this project had recorded as
"parsed and dropped because each is a box generated from `content` in
a place the layout engine has no notion of" and assumed no browser
reached. `CSSMarginRule` exists, the nested rules survive in
`cssRules`, and a print lays all sixteen down.

**Reading a print needs no new dependency.** `--print-to-pdf` writes
Flate streams and `zlib` is in the standard library, so
`/tmp/claude-0/probe/pdfboxes.py` inflates the content stream, reads
the `Tm`/`Td`/`Tj` operators, and maps the glyph ids back through the
standard glyph order the subset uses. That gives every string Chromium
drew and where its baseline is, in CSS pixels. The same route makes
`print-color-adjust` measurable, which had been written off here for
want of a PDF reader.

A 400 by 500 page with 60px margins, one letter in each of the
sixteen boxes. The bands are the top 60 rows, the bottom 60, the left
60 columns and the right 60; the corners are their 60 by 60
intersections, and the edge *regions* are what is left between the
corners -- x 60 to 340 across, y 60 to 440 down.

| box | x | baseline | reading |
|---|---|---|---|
| `@top-left-corner` | 48.44 | 35 | **right**-aligned to x 60 |
| `@top-left` | 60.00 | 35 | left-aligned in the region |
| `@top-center` | 194.66 | 35 | centred on x 200 |
| `@top-right` | 328.44 | 35 | right-aligned to x 340 |
| `@top-right-corner` | 340.00 | 35 | **left**-aligned from x 340 |
| `@bottom-*` | the same five | 475 | the same five, in the bottom band |
| `@left-top` | 24.22 | **74** | centred on x 30, line at the region's top |
| `@left-middle` | 25.11 | **255** | centred, line centred on y 250 |
| `@left-bottom` | 22.88 | **436** | centred, line at the region's bottom |
| `@right-top`, `-middle`, `-bottom` | centred on x 370 | 74, 255, 436 | the same three |

So each box is **vertically centred in its band** on the top and
bottom edges -- baseline 35 in a 60-tall band is a 19-tall line centred
-- and the three boxes down each side are top-, middle- and
bottom-aligned within the side region. The corners align *inward*,
toward the page content. That is exactly the table CSS Paged Media 3
§5.2 gives as each box's default `text-align` and `vertical-align`,
which is worth saying because it means the standard can be implemented
rather than the browser copied.

**`counter(page)` and `counter(pages)` work, and concatenate.**
`content: counter(page) " of " counter(pages)` on a three-page
document draws `1 of 3`, `2 of 3`, `3 of 3`, centred as one run.

**A margin box inherits from the ROOT element, not from `body`.** The
decisive pair: `html { font: 16px monospace }` makes `MMMM` 38.54 wide,
which is four monospace advances exactly; `body { font: 16px
monospace }` leaves it 56.9 wide, which is the default serif. The page
context inherits from the root element and `body` is not in it.

**`font-size` on a margin box works and keeps it centred**: 32px moves
the baseline from 35 to 41, which is a 38-tall line centred in the 60
band. `content: none` and an empty box both draw nothing.

**And `@page :first` selects a margin box.** A `:first` rule's
`@top-center` replaces the general one on page one and leaves it in
force on the rest, so the boxes cascade by the same page-selector
specificity the page box already uses here.

### The feature page does not exercise a rounded box inside a layer

Filling a `border-radius` into a layer a row at a time is measured at
0 ms on both benchmark pages, and both zeros are structural: neither
page has a rounded box inside a clipped subtree, so neither reaches the
path. A feature no page exercises reads exactly like a feature that
costs nothing, which is the failure this project keeps finding in its
own instruments.

Putting `overflow: hidden` on `figure` in `tests/featurepage.py`, which
already carries a `border-radius`, would exercise it ninety-six times.
It is not a one-line change: it also makes each figure a box that
paints whole, which moves it in §9.9's walk, and puts its inset shadow
inside a layer. So it wants its own pass, with the render suites
re-read afterwards rather than assumed.

### What the page-state invariant has not been pointed at yet

`tests/render/pagestate.f` requires painting a page twice, with another
page built and painted in between, to give the same pixels, and
`DocFlags` is what makes that true: the painter's per-document answers
are captured as a page's layout finishes and put back before it is
painted. The invariant is the guard, because a list of flags can be
incomplete and an invariant cannot -- but it only guards what its
fixture reaches. Its page has a float, a positioned box, a negative
z-index, a transform, an outline, a clip holding a rounded box with an
inset shadow, a bevelled corner and small capitals. It has no grid, no
multicol, no ruby, no anchor, no motion path, no `initial-letter`, no
container query and no printed page, and every one of those raises
answers of its own.

Widening the fixture is cheap and each addition is a real check, so
the next feature that raises a per-document answer should add its
shape to that page as part of landing. What it must not do is paint
something whose geometry depends on the answers being wrong, or the
suite grades the leak instead of catching it.

### Where a clipped background's curve comes from, measured

An 80x80 box with `border: 20px solid blue`, `border-radius: 40px`, a
red background and `background-clip: padding-box`, on a green page:

| row | what Chromium draws |
|---|---|
| 22 | green to 2, blue 5-28, red from 32 |
| 30 | green at 0, blue 2-21, red from 23 |
| 60 | blue 0-19, red from 20 |

The inner radius is 40 less 20, which is 20: at row 22 that puts the
background's edge at 31.3 -- `20 * (1 - sqrt(1 - (18/20)^2))` past the
padding box's left edge -- where a radius of 40 would put it at 47.5.
Before this engine derived the inner curve it drew the second, which
left eleven pixels of the page showing between the border and the
background.

### Where a background image's curve comes from, and what still differs

A 120x120 box with `border-radius: 40px` on a green page, painted twice:
once with `background-color: #ff0000` and once with
`background-image: linear-gradient(#ff0000, #ff0000)` at
`background-size: 100% 100%`. Read with `tests/chromium.py pixels` at
200x200:

| row | Chromium, colour | Chromium, image |
|---|---|---|
| 4 | green to 20, red from 23 | the same |
| 20 | green to 4, red from 6 | the same |

**Chromium's two renders are byte-identical**, which is what makes the
test number-free: the same box painted with an image has to land where
the same box painted with the colour does, and neither answer has to be
known in advance. Before the image was cut to the curve it was painted
as a rectangle from x=0 on every row, which that comparison catches at
44 rows out of 130.

**This engine's two cannot be byte-identical, and the difference is
worth knowing.** The colour is filled through the canvas's own path,
which draws a corner as a *bezier* and antialiases it; an image is
painted into a layer and blitted back a row at a time, cut to the
*ellipse* itself. The two agree to a pixel through the body of the
curve and part company where it runs flattest:

| row | bezier (the colour) | ellipse (the image) | Chromium |
|---|---|---|---|
| 0 | 31 | 34 | |
| 4 | 20 | 22 | 21 |

At row 4 the ellipse's own arithmetic is
`40 - 40*sqrt(1 - (35.5/40)^2)`, which is 21.6. So the two answers
straddle Chromium's rather than one of them being wrong, and the check
allows three pixels on the five rows nearest each tangent and one
everywhere else. Closing it means giving the bezier up on the canvas
path, or antialiasing the span on the layer -- and the layer has no
path API to do it with (FINDINGS.md, "an image is a drawable surface
with a smaller API").

### What a `/*` inside a string costs a stylesheet, measured

Comments are stripped before anything else is parsed, by a scan that
does not know where a string or a `url()` begins. CSS Syntax 3 §4.3
consumes comments in the tokenizer, so a `/*` inside a string token is
two ordinary characters; here it opens a comment that runs to the next
`*/` and, where there is none, **to the end of the stylesheet**.

Two sheets, each two rules, on a 200px page:

```css
#a{font-family:"/*";width:100px;height:40px;background:#00ff00}
#b{width:100px;height:40px;background:#ff0000}
```

```css
#a{background-image:url(no/*such.png);width:100px;height:40px;background-color:#00ff00}
#b{width:100px;height:40px;background:#ff0000}
```

| | Chromium | this engine |
|---|---|---|
| `#a` | green | nothing painted |
| `#b` | red | nothing painted |

Both rules are lost, not just the one the `/*` is in: the comment opens
mid-declaration and never closes. A single `content: "/*"` in a site's
stylesheet therefore drops every rule after it, which is not a corner
so much as a page that renders blank.

The scan knows those three places now. What it deliberately does not
do is the other direction: a comment ends at the **first** `*/`
whatever is inside it, so `/* "*/` leaves a `"` open and swallows the
rest of the sheet -- Chromium loses that rule too, measured, and the
suite asserts the loss so that a later "fix" cannot quietly introduce
a divergence.

What is still open in CSS Syntax 3 is the shape of the parser itself:
there is no tokenizer in the standard's sense, so every rule of §4.3
that the index scan does not happen to agree with is a divergence
waiting to be found the way the comment, the escape, the CDO and the
attribute selector's own escapes were. Four in a row came out of
reading one row of css-2026.md and asking Chromium; the row is worth
reading again.

### Where a selector's escapes come from, measured

CSS Syntax 3 §4.3.7 decodes an escape as it consumes an identifier: a
backslash before a non-hex character stands for that character, and a
backslash before up to six hex digits stands for the code point they
name, with one following space consumed as the terminator. Here the
backslash is accepted and kept, so the identifier the selector holds is
never the identifier the document has, and the rule can never match.

Four selectors, each against the element it names, on a page whose
`div` is grey until one matches:

| selector | element | Chromium | this engine, before |
|---|---|---|---|
| `.a\.b` | `class="a.b"` | matches | no match |
| `#x\#y` | `id="x#y"` | matches | no match |
| `.\41 bc` | `class="Abc"` | matches | no match |
| `.e\2d f` | `class="e-f"` | matches | no match |
| `.caf\e9` | `class="café"` | matches | no match |

The last row is where the decoded character has to live. The document's
own escapes are expanded by the tokenizer, so that attribute holds a
real U+00E9 and not the three-part form `src/html/decode.f` rewrites
bytes into -- which the first draft of the fix assumed, and which
asking the DOM settled.

The last two are the hex form, where the space after the digits is the
escape's terminator rather than a descendant combinator -- which is the
part a scan that only strips backslashes would still get wrong.

An escaped space is not on the list because HTML cannot express the
element it would need: `class="c d"` is two classes, not one class
named `c d`, and Chromium leaves `.c\ d` unmatched there too.

### Where a stylesheet's `<!--` goes, measured

CSS Syntax 3 §5.4.1 ignores a CDO (`<!--`) and a CDC (`-->`) at the top
level of a stylesheet: they are the wrapper pages once put round a
`<style>` element so that a browser which did not know the tag would
not print its contents. Here they are neither recognised nor skipped,
so they are swept into the selector beside them and take a rule with
them.

Two sheets of two rules, on a 200px page whose divs are sized by those
rules:

```css
<!--
#a{width:100px;height:20px;background:#ff0000}
#b{width:100px;height:20px;background:#0000ff}
-->
```

```css
#a{width:100px;height:20px;background:#ff0000}
--> #b{width:100px;height:20px;background:#0000ff}
```

| | Chromium | this engine, before |
|---|---|---|
| wrapped in `<!--`/`-->` | both rules apply | `#a` lost; the `-->` takes nothing, because a trailing one ends the sheet |
| a `-->` before the second rule | both rules apply | `#b` lost |

A `-->` that follows name characters is **not** a CDC: the identifier
takes both hyphens and the `>` left over is a child combinator.
Chromium's `selectorText` for `a-->b` is `a-- > b`, asked of it
directly. Testing for the token only where a rule or a declaration
begins is what keeps that true.

**Inside a declaration block the two already agree**: `#a{--> background:#0000ff}`
leaves the earlier `background` standing in both, because the
declaration's name is not one either engine knows. So the fix is at the
top level only, where a rule is read.

### What an attribute selector could not say, measured

A sweep of 37 attribute selectors, each asked of the element it names
with `element.matches()` in Chromium and against the same element's
laid-out width here, divides cleanly. Twenty-one agree. Two are the
engine ahead: Selectors 4 §6.3's `s` modifier is implemented here and
throws a `SyntaxError` in Chromium, so `[data-x="ab" s]` reads `ERR`
there and `Y` here. The remaining fourteen are one gap with three
places in it -- **nothing on the selector path is aware that a `]` or a
`[` inside a string is not a bracket, and nothing decodes an escape
inside `[...]`**.

| selector | element's `data-x` | Chromium | this engine, before |
|---|---|---|---|
| `[data-x="a]b"]` | `a]b` | matches | no match |
| `[data-x="]"]` | `]` | matches | no match |
| `[data-x^="a]"]` | `a]b` | matches | no match |
| `[data-x="a[b"]` | `a[b` | matches | no match |
| `[data-x="a\"b"]` | `a"b` | matches | no match |
| `[data-x="a\'b"]` | `a'b` | matches | no match |
| `[data-x="a\\b"]` | `a\b` | matches | no match |
| `[data-x="a\65 b"]` | `aeb` | matches | no match |
| `[data\-x="ab"]` | `ab` | matches | no match |
| `[data\-x]` | `ab` | matches | no match |
| `[data-x=a\ b]` | `a b` | matches | no match |
| `[data-x=a\]b]` | `a]b` | matches | no match |
| `[data-x=a\=b]` | `a=b` | matches | no match |
| `[data-x=a\62 ]` | `ab` | matches | no match |

The three places, each found by dumping what the parser built rather
than by reading it:

1. **`parseSelectorList` counts brackets without skipping strings.**
   `[data-x="a[b"]` leaves its depth at 1 when the list ends, so the
   one and only selector is never pushed and the rule is dropped whole.
   `dumpStylesheet` of `[data-x="a[b"]{width:50px}#z{color:red}` prints
   the `#z` rule alone.
2. **The compound parser takes the first `]` it finds.**
   `asciiIndexOf(selSrc, ']', selPos)` cuts `[data-x="a]b"]` at the `]`
   inside the quotes, and the `"]` left over marks the selector
   unsupported, which drops the rule for a second reason.
3. **`parseAttrSel` decodes nothing.** The name scan stops at the
   backslash of `data\-x`, the quoted-value scan ends at a `"` however
   it is escaped, and the unquoted-value scan reads `a\ b` as the value
   `a\` followed by a flag. `cssDecodeIdent`, which already decodes an
   identifier elsewhere in this file, is not reached from here at all.

An escaped space earns its place in the table where it could not in the
class-selector measurement: `class="c d"` is two classes and no element
can carry one named `c d`, but `data-x="a b"` is a single attribute
value with a space in it, so `[data-x=a\ b]` has something real to
match.

The two rows the sweep found that are **not** a gap here are the two
where Chromium throws: Selectors 4 §6.3's `s` modifier is not shipped
there, so `element.matches('[data-x="ab" s]')` raises a `SyntaxError`
and the selector conformance instrument can never grade it against a
browser. It has unit checks of its own in `tests/unit/`, because
nothing else here could notice if it stopped working.

### What the selector instrument has never asked, measured

The instrument grades 61 selectors and every one of them passes, which
says what those 61 are rather than what the engine can do. Selectors 4
has a great deal the list has never contained. Forty-five candidate
rows were put to Chromium against the same fixture,
`tests/fixtures/selectors.html`, with no change to the document; 25 of
them match at least one element there, so 25 can be graded today. The
engine agrees on 9 of the 25.

Passing already, and so worth adding to the list as it stands:

| row | matches |
|---|---|
| `:any-link`, `a:any-link` | `a1` |
| `div:not(:has(p))` | `d4 d5` |
| `*|p` | every `p` |
| `:root > body` | `body` |
| `:checked + input` | `i4` |
| `input:enabled:checked` | `i3` |
| `:is(h2):is(#h1)` | `h1` |
| `:not(:not(p))` | every `p` |

Failing, in three families:

**1. A complex selector inside `:is()`, `:where()`, `:not()` and
`:has()`.** Each of those takes a full `<complex-selector-list>` in
§3.1, and this engine takes a compound: `:is(h2, span)` works and
`:is(div > p)` does not. `:has()` is the same restriction wearing a
different hat -- it is a descendant test here, so a leading combinator
is refused rather than read.

| row | Chromium | this engine |
|---|---|---|
| `:is(div > p)` | `p1`..`p7` | nothing |
| `:where(div > p)` | `p1`..`p7` | nothing |
| `p:not(div > p)` | `p8 p9` | nothing |
| `div:has(> p)` | `d1 d2 d3` | nothing |
| `div:has(+ div)` | `d1 d2 d3` | nothing |
| `p:has(+ p)` | `p1 p2 p6 p8` | nothing |

**2. `:nth-child(An+B of S)`.** The `An+B` grammar is complete; the
`of S` clause that filters which siblings are counted is not read at
all.

| row | Chromium | this engine |
|---|---|---|
| `p:nth-child(2 of .lead)` | `p3` | nothing |
| `:nth-child(1 of p)` | `p1 p5 p6 p8` | nothing |
| `li:nth-child(even of :not(.x))` | `l2 l4 l6` | nothing |

**3. The form-state and direction pseudo-classes**, none of which the
engine has: `:read-write` (`i1`), `:read-only` (every `p`),
`:optional` (`i1`..`i4`), `:default` (`i3`), `option:default` (`o1`),
`:valid` (`i1 i3 i4`) and `:dir(ltr)` (every `p`).

Sixteen of the other twenty match nothing in this fixture, so they
cannot be graded without changing the document -- `:required`,
`:placeholder-shown`, `:indeterminate`, `:invalid`, `:in-range`,
`:out-of-range`, `:focus-within`, `:host`, `:open`, `:modal`,
`:popover-open`, `:autofill`, `:user-valid`, `:user-invalid`,
`li:nth-child(2 of .lead)` and `p:nth-last-child(2 of .tail)`. The
runner refuses such a row outright, which is the rule from CLAUDE.md
working: an ungradeable row would read as implemented in an engine that
dropped it. `p|p` is invalid with no namespace declared, and `:scope`,
`:defined` and `:has(:is(.lead))` match `html`, which has no id, so the
comparison cannot name what they matched.

**The 25 gradeable rows are the deliverable here**: adding them takes
the list from 61 to 86 and the count from 61/61 to 70/86 before any
code is written, so the number says what is left instead of only what
works.

### Where an inset shadow's curve comes from, measured

A 120x120 box with `border-radius: 40px`, a white background on a green
page and `box-shadow: inset 0 0 0 12px #ff0000`, read with
`tests/chromium.py pixels` at 200x200:

| row | what Chromium draws |
|---|---|
| 6 | green to 16, red 19-100, green from 103 |
| 20 | green to 4, red 5-18, white 21-98, red 101-113, green from 115 |
| 40 | red 0-11, white 12-107, red 108-119, green from 120 |

Row 40 is below both corners and is the straight band; rows 6 and 20
are the curve. Row 20 is what settles the hole's radius: the outer edge
at 5 is a radius of 40 -- `40 * (1 - sqrt(1 - (20/40)^2))` is 5.4 --
and the hole's edge at 20 is a radius of **28**, because 28 gives 8.4
and 40 would give 16. So the spread shrinks the hole's radius with it.

### Where an outline paints, measured

CSS2 §9.9's step 10 draws the outlines of a stacking context and its
descendants after everything else in it. Four overlaps against
Chromium 141, read with `tests/chromium.py pixels` at 300x300, a
200x60 blue box with `outline: 6px solid red` against something laid
over the band its outline occupies:

| what the outline overlaps | Chromium draws |
|---|---|
| an in-flow block written after it | the **outline** |
| a float | the **outline** |
| an inline-block pulled over it | the **outline** |
| an absolutely positioned box over it | the **positioned box** |

And the pass is over the stacking context's **in-flow** content rather
than over everything in it: a *float's* own outline travels with the
float at step 4, so an inline-block pulled over the float covers its
outline along with its background. Chromium draws that inline-block
across 0-199 on the float's rows and on its outline's band alike, which
is what this engine does already -- a float paints whole at step 4 and
draws its own outline inside itself.

So the outline is above steps 3, 4 and 5 and below step 8, which is
one pass of its own between the inline content and the positioned
descendants -- not the very last thing the standard's wording
suggests. The fourth row is the one that pins which side it falls on:
`#p{position:absolute;top:56px}` covers the outline's band at x 0-199
and leaves it showing only at 200-205, where the positioned box does
not reach.

Here the outline is drawn with the box's own background and border, so
it is step 3, and all three of the first rows go the other way.

### What three walks of the box tree cost, still unexplained

Separating CSS2 §9.9's steps 3, 4 and 5 as three walks of the subtree,
each asking `boxPaintsWhole` of every box, cost **7 ms of a 20 ms
paint** on generated.html and 23 of 33 on features.html. Replacing that
predicate's body with `return false` -- which on generated.html is the
answer it gives anyway, and the two binaries render it pixel for pixel
the same -- gave back 8 ms forward and 6 ms reversed, so the reading is
real and the predicate is where it lives.

**What it is not is a `Style` read**, which was the first explanation
and is wrong. A minimal Festina program (FINDINGS.md, finding 41)
builds a struct of 244 fields, 16 of them `text` and 14 of them arrays
-- `Style`'s own shape -- and forty thousand reads of the form
`Big s = n.big` do not register at millisecond resolution.

Part of it is now accounted for and part is not. Binding an element of
an `arr` to a local costs about 0.14 microseconds where passing it
straight to a call costs nothing (FINDINGS.md, finding 41), and the
walks bind `Box c = b.children[i]` once per child, so three walks of
2,728 boxes is about a millisecond of the seven. The other six are
still unattributed.

**And the obvious way to attribute them does not work.** Asking
`boxPaintsWhole` ten times a box instead of once reads **zero** extra
milliseconds, because the function is pure and the compiler folds the
nine repeats into the one. An instrument that measures a call by making
more of the same call cannot measure a call the optimizer can prove
redundant, which is worth remembering before reaching for it again.

The shipped painter does not pay any of this -- it asks the question
once and writes the answer on the box -- so what is left is a question
about Festina rather than about the browser, and the next answer to it
belongs in FINDINGS.md.

### Where Grid's named spans come from, measured

**A backwards search for a name the template does not declare.**
§8.3 assumes an unknown name on every implicit line, and for
`grid-column: span zz / 3` the search runs backwards, so the lines it
finds are the implicit ones *before* the explicit grid. On a grid of
two 100px columns in a 400px container, Chromium puts the item at
**x=0 with the columns 200, 100, 100** -- it has created a column ahead
of line 1 and stretched it, which renumbers every line and moves every
item already placed.

**The test needs no number, because the column it creates is one the
template could have written.** These two render identically in
Chromium, item and auto-placed sibling alike -- 400px of item on the
first row, 200px of sibling on the second:

| | template | item |
|---|---|---|
| the name | `100px 100px` | `grid-column: span zz / 3` |
| written out | `auto 100px 100px` | `grid-column: 1 / 4` |

So the check is that the two agree, and it catches the renumbering
rather than only the placement: the sibling is auto-placed, so it moves
only if line 1 really did move.

**The forward direction of the same sentence came from the same
place**: `span <custom-ident>` dropped the name at the parser, so every
named span was a span of one. On the same grid,
`grid-column: 1 / span zz` should count forward from line 1 for a line
named `zz`, find none, and take the first implicit line after the
explicit grid -- line 4, a span of three.

| | Chromium | this engine, before |
|---|---|---|
| `grid-column: 1 / span zz` | item 400 wide, sibling 100 at x=0 | item 100 wide, sibling 100 at x=100 |
| `grid-column: span zz / 3` | item 400 wide, sibling 200 at x=0 | item 100 at x=100, sibling 100 at x=0 |

**A subgrid is the exception, and it had to be measured to be found.**
Grid 2 §3.1 gives a subgrid no implicit tracks of its own, so a
backwards search that runs off its front stops at its first line rather
than making one. The first implementation made one, and it read clean
until `grid-auto-columns: 50px` was put on the subgrid to give that
track a size: Chromium 200 against this engine's 250, on a subgrid of
four 100px columns with `grid-column: span zz / 3`. Without a size on
it the track comes out zero wide and nothing shows.

Its numbered equivalent is `grid-column: 1 / 4`, on the template as
written: the implicit track it creates comes *after* the explicit grid,
which the engine already does for a bare name.

### Counter Styles 3's `range` and `fallback`, measured

`@counter-style` here parses `system`, `symbols`, `suffix`, `prefix`,
`pad` and `negative`. It does **not** parse `range`, `fallback` or
`speak-as`, and there is no `symbols()` function. The built-in roman
styles carry a range of their own and answer decimal outside it, so the
machinery is half there; what is missing is the descriptors.

Measured against Chromium 141 with a style of
`system: numeric; symbols: '0' '1' '2'` -- base three, so a value's
length gives it away in a monospace font -- and `range: 2 4`:

| counter | `range: 2 4`, no `fallback` | the same plus `fallback: upper-roman` |
|---|---|---|
| 1 | `1` (1 char) | `I` |
| 2 | `2` | `2` |
| 3 | `10` (2 chars) | `10` |
| 4 | `11` | `11` |
| 8 | `8` (**1 char**) | `VIII` (**4 chars**) |
| 9 | `9` (1 char) | `IX` (2 chars) |

So a counter inside the range is rendered by the style, and one outside
it falls to the **declared** `fallback` or to `decimal` where none is
declared. The 8 and 9 rows are the ones that discriminate: at 1 and 5
the roman and the decimal are both one character, and the first probe
could not tell them apart.

**Three instruments were thrown away before that table.**
`getComputedStyle(li, '::marker').content` answers `normal` whatever
the style; `getComputedStyle(el, '::before').content` answers the
*specified* `counter(k, ranged)` rather than the string it resolved to;
and a DOM `Range` over an element's contents measures zero, because a
pseudo-element's text is not in the DOM. What works is making the
element an `inline-block`, whose shrink-to-fit width **is** the
generated text's width, and dividing by the width of one character.

**`symbols()` is not measured and is not claimed.** The fourth
instrument -- an `inline-block` `<li>` with
`list-style-type: symbols(cyclic '*' '#')` and
`list-style-position: inside` -- reads one character, which is the
`x` inside the item; a `disc` item beside it reads one character too.
An instrument that answers the same for a style that certainly works is
measuring nothing, so what the row says about `symbols()` is nothing
either, and the function stays unimplemented until something can see
it.

**`speak-as` will not be taken.** Nothing here speaks, so it would be a
descriptor parsed and never read, which is `outline-style` again.

### How Chromium synthesises small caps, measured

`font-variant-caps` is the part of Fonts 4 that needs no font the
system lacks, because a browser with no such feature in the face
**synthesises** it. Chromium 141, monospace:

| | `abc` | `abc` small-caps | ratio |
|---|---|---|---|
| 16px | 28.91 | 19.88 | 0.6876 |
| 20px | 36.13 | 25.30 | 0.7003 |
| 40px | 72.25 | 50.58 | 0.7000 |
| 80px | 144.50 | 101.16 | 0.7000 |
| 100px | 180.63 | 126.44 | 0.7000 |

So a lowercase letter is drawn at **0.7 x the font size**, and the 16px
row is that rule with the size rounded: 0.7 x 16 is 11.2, and three
characters of 11px monospace come to 19.87.

Which letters are shrunk depends on the keyword, per character rather
than per run:

| | `abc` | `ABC` | `aBc` |
|---|---|---|---|
| `small-caps` | 50.58 | **72.25** | 57.80 |
| `all-small-caps` | 50.58 | **50.58** | 50.58 |

`small-caps` leaves an uppercase letter at the full size and
`all-small-caps` shrinks it too; `aBc` at 57.80 is one full-size
character plus two small ones, so the decision is made letter by
letter. The line box keeps the full font's metrics either way -- every
row above is 46 tall at 40px, the same as the normal run beside it.

### What §9.9's steps 3, 4 and 5 look like in pixels

The hit-testing table below says which box a *click* lands on. This is
the same order read off the screen, with `tests/chromium.py pixels`,
every rectangle checked with `getBoundingClientRect` before a row was
read. Both fixtures are in `tests/render/stacking.f`, which asserts the
pixels and the click at the same four points.

**A float against a later in-flow block.** A 100x100 blue float, a
100-tall red block after it, and a 60x60 green inline-block pulled over
both. At row 60, across 300 pixels:

| blue (float, step 4) | green (inline, step 5) | red (block, step 3) |
|---|---|---|
| 0-19 and 80-99 | 20-79 | 100-299 |

The float is above the block written after it and below the inline
content pulled over it, which is the whole of steps 3, 4 and 5 in one
row of pixels.

**And it is not only about floats.** A 100x60 green inline-block and a
red block after it with `margin-top: -40px`, no float anywhere:

| green (step 5) | red (step 3) |
|---|---|
| 0-99 | 100-299 |

So step 5 is not only about floats: it is every page where inline
content and a block overlap. **A `docHasFloats` guard would not be an
honest one**, because this second fixture has no float on it at all --
which is why the two extra walks of the box tree are unconditional and
`tests/featurepage.py` now puts a float on the benchmark page so that
step 4's walk is measured rather than skipped.

### Where a float sits in the hit-testing order, measured

CSS2 §9.9 paints non-positioned floats at step 4, between the in-flow
block-level descendants of step 3 and the in-flow inline-level content
of step 5. Five overlaps against Chromium 141's `elementFromPoint`,
every rectangle checked with `getBoundingClientRect` before the point
was asked for:

| what overlaps | Chromium names |
|---|---|
| a float against an in-flow block written **after** it | the **float** |
| a float against an in-flow block written before it, pulled over it | the **float** |
| an inline-block pulled over a float | the **inline-block** |
| an absolutely positioned box over a float | the **positioned** box |
| two floats, the later pulled over the earlier | the **later** float |

The first is the one that discriminates: the block comes later in
document order, so a search running the in-flow children latest-first
with the floats among them answers the block. Giving the floats a pass
of their own, between step 5's and step 3's, is what makes it answer
the float.

**Two fixtures had to be thrown away for overlapping nothing.** A float
written after inline content on the same line shortens that line and is
placed beside it, so the span that was meant to sit under the float was
pushed to x=101 while the float sat at x=1. Both read as a clean
answer, and both were asking nothing -- the rectangles were only
noticed because they were printed beside the result. An inline-level
box written *before* a float and genuinely overlapping it is hard to
construct for that reason; the case that settles step 5 against step 4
is the inline-block written after the float and pulled back over it.

### Which of two overlapping boxes a click lands on, measured

`elementFromPoint` names the **topmost in painting order**, so five
overlapping pairs pin five steps of CSS2 §9.9 against the one below:

| what overlaps | Chromium names |
|---|---|
| a positioned box written *before* an in-flow one | the **positioned** one |
| two in-flow blocks, overlapped by a negative margin | the **later** one |
| two positioned boxes, `z-index: 5` written before `z-index: 1` | the **higher z**, whatever the order |
| a `z-index: -1` box against its context's in-flow content | the **in-flow** content |
| a child against its parent's background | the **child** |

The fourth row is worth keeping: the in-flow box has
`background: transparent` and still wins, so hit testing is about the
**box** rather than about the ink in it. That is the model this engine
already has, and it is what makes the fix a reordering rather than a
new question.

### What a `transform` makes of a box, measured

Three questions, all answered by one page each.

**It is the containing block for its positioned descendants**, and for
both kinds. An `position: absolute` child at `left: 0; top: 0` inside a
`position: relative` grandparent lands on the *grandparent* normally and
on the **transformed parent** when the parent has a transform; a
`position: fixed` child lands on the viewport normally and on the
transformed parent the same way:

| the middle box | where the absolute child lands | where the fixed child lands |
|---|---|---|
| no transform | the positioned grandparent | the viewport, `0,0` |
| `transform: translateX(0px)` | **the middle box itself** | **the middle box itself** |
| `transform: none` | the positioned grandparent | -- |

**It is a stacking context.** A `z-index: -1` child paints behind a
non-context parent's background and above a context parent's, so
`elementFromPoint` at the parent's centre names which:

| the parent | what is on top |
|---|---|
| no transform | the parent -- the negative child is behind its background |
| `transform: translateX(0px)` | **the child** |
| `transform: rotate(0deg)` | **the child** |
| `transform: none` | the parent |
| `opacity: 0.5` | the child (a separate rule, and already true here) |

**The trigger is the computed value, not the matrix.** `rotate(0deg)`
computes to `matrix(1, 0, 0, 1, 0, 0)` -- byte for byte what
`translateX(0px)` computes to -- and both make a containing block and a
stacking context. An **identity** transform is still a transform. Only
`none` is not.

**Hit testing follows the drawn shape.** A 100x40 box rotated 90 degrees
about its centre is drawn 40 wide and 100 tall. Seven points against it,
with an unrotated box of the original geometry underneath to tell the
two shapes apart:

| point | `elementFromPoint` |
|---|---|
| 150,280 and 150,360 -- inside the drawn box, outside the laid-out one | the rotated box |
| 110,320 and 190,320 -- inside the laid-out box, outside the drawn one | the box underneath |
| 105,310 and 195,310 -- the same, nearer the corners | the box underneath |
| 150,320 -- the centre, inside both | the rotated box, which paints later |

So the pointer is tested against the transformed rectangle rather than
the laid-out one, which is the inverse transform applied to the point.

### `::placeholder`, measured

Thirteen inputs on one page, each with its own rule, read back through
`getComputedStyle(e, '::placeholder')`:

| declared | what the pseudo-element computes to |
|---|---|
| nothing | `color: rgb(117, 117, 117)` |
| `color` on the **input** | still `rgb(117, 117, 117)` |
| `color` on `::placeholder` | that colour |
| `font-size` on the input | inherited, 20px |
| `font-size` on `::placeholder` | that size, 9px |
| `opacity`, `background-color`, `letter-spacing`, `font-style`, `text-decoration-line`, `visibility` | all take |
| `display: none` | **ignored**, still `block` |

The first two rows are the interesting pair. The grey is not a default
the pseudo-element falls back to -- it is a **declaration in the user
agent's own stylesheet on the pseudo-element itself**, which is why the
input's `color` cannot reach it: an inherited value loses to any
declaration, whatever origin the declaration comes from. So one UA rule
reproduces both rows, and nothing special is needed to make the colour
win.

`width` computes to whatever is declared and moves no pixel, so it is
not evidence the property does anything there.

### `text-decoration-skip-ink`, measured and not taken

Rasterised at 40px monospace, `gjpqy` underlined in blue three pixels
thick, reading the row through the underline:

| | blue pixels | the gaps in it |
|---|---|---|
| `auto` | 58 | 1-22, 32-42, 49-57, 86-94, 101-111 |
| `all` | 58 | **identical, pixel for pixel** |
| `none` | 89 | 4-7, 15-20, 35-39, 50-55, 88-92, 104-108 |

Two things come out of it. **Chromium does not distinguish `auto` from
`all`**, which the standard defines as different -- `all` is meant to
skip where `auto` would not. And **`none` still shows gaps**, which are
not skipping: they are the glyph's own strokes, four to six pixels wide,
painted over an underline that Chromium draws *under* the text. `auto`'s
gaps are eleven to twenty-two pixels, which is the stroke plus the halo
the standard asks for either side.

So the default here disagrees with the browser on every descender: this
engine draws through them, and `auto` is the initial value.

**It is not taken, and the obstacle is the painter's coordinates rather
than the algorithm.** The engine has no glyph outlines -- `measureTextWidth`
is the whole of what it can ask about a string -- so the only way to find
where ink crosses the underline is to draw the glyphs, read the canvas
back along the band, and draw the line in the runs that did not change.
The read has to be in device pixels, and `paintTextFragment` runs inside
whatever `saveState`/`translate` the scroll offset, a transform and any
enclosing scroll container have pushed; the painter tracks no accumulated
offset to undo them with. Giving it one is the task, and it is a change
to the painter rather than to text decoration. The cost wants measuring
too: the scan is one read per pixel of every underlined fragment, which
every page with a link pays, and nothing here has read the canvas back
mid-paint before.

### A side break's blank page, measured

CSS 2 §13.3.1 and Fragmentation 3 §3.1 say `left` and `right` force
**one or two** page breaks, so that the next page is formatted as a page
of the named side. Two means a blank page in between. Chromium does not
generate it.

The measurement goes through the page size, because `/MediaBox` is plain
text in the PDF catalogue and needs no content-stream arithmetic. A
`@page :left` of 300px and a `@page :right` of 500px make each printed
page say which side rule it was formatted with:

| | page sizes printed |
|---|---|
| `break-before: page`, two blocks | 500px, **300px** |
| `break-before: page`, four blocks | 500, 300, 500, 300 |
| `break-before: right`, two blocks | 500px, **300px** |
| `break-before: left`, two blocks | 500px, 300px |

So **Chromium honours `:left` and `:right`, and the first page is a
right page**, which is what CSS2 §13.2.4 says for a left-to-right
document and what this engine already assumes. But `break-before: right`
put its content on the *left* page that followed, where the standard
asks for a blank left page and the content on the right page after it.
Counting pages says the same thing from the other side: `left`, `right`,
`recto` and `verso` all print exactly the page count `page` prints, and
two consecutive `break-before: right` blocks print three pages where the
standard asks for five. The CSS2 spelling `page-break-before: right`
behaves identically, so it is not a question of which syntax is
recognised.

**So this is a disagreement to be entered deliberately**, like Motion
Path's ray sizing: the standard is unambiguous, the browser does not
follow it, and this engine follows the standard and writes Chromium's
answer down beside it. What that costs is that the page count cannot be
graded against Chromium here -- the render suite grades it instead,
since this engine paints one image per page and a generated blank page
is one with the page box painted and no content on it.

### `print-color-adjust`, measured

The entry above says the PDF read makes this measurable. It does, but
not the way the first probe tried: **Chromium's `--print-to-pdf` prints
background graphics unconditionally**, so `economy` and `exact` give
byte-identical fills and the CLI can say nothing about the property at
all. Three runs agreeing is not evidence when the instrument cannot
distinguish the two answers.

What distinguishes them is `Page.printToPDF`'s **`printBackground`**,
which the CLI does not expose. `/tmp/claude-0/probe/cdp.py` is a CDP
client written for this -- a socket, the WebSocket handshake and its
framing, standard library only, no dependency -- and it gives the table
this property is made of. A 200x100 div with `background: #3366cc`, the
fill operators read out of the content stream:

| `print-color-adjust` | `printBackground: true` | `printBackground: false` |
|---|---|---|
| not declared (initial `economy`) | painted | **absent** |
| `economy` | painted | **absent** |
| `exact` | painted | **painted** |
| `-webkit-print-color-adjust: exact` | painted | painted |

So the property is exactly what CSS Color Adjustment 1 §3 says it is,
and the shape is worth stating plainly: **the user agent decides whether
to omit backgrounds, and `exact` overrides that decision.** `economy`
grants a permission and is indistinguishable from the initial value;
`exact` withdraws it. A renderer that always prints backgrounds cannot
tell the two apart, which is why the CLI could not, and why this engine
could not before it had a way to omit one.

**What that implied for the implementation.** Storing the keyword and
stopping there would have been `outline-style` again: the instrument
scores it and no pixel moves. Giving it something to be about meant
giving `--print` the omission the property overrides, so
`--no-background-graphics` is that switch, named after the print
dialog's own setting. It is off by default, because a `--print` that
silently stopped printing backgrounds would be a behaviour change
nothing asked for; under it a background is drawn only where the
computed value is `exact`. That is Chromium's own model with the flag
named differently.

### A scroll offset outlives the document it belongs to

Found by asking the same question of `resize`'s dragged sizes, which
are kept the same way. `boxScrollTops` and `boxScrollLefts` are keyed
by **node id**, because a box tree lasts one layout and a scroll
position has to outlive several. Node ids start again at 1 for every
document -- `pageFromHtml` and the shell's `navigate` both call
`nodeRegistryReset` -- and nothing clears the two maps, so a scroll
container on the next page inherits whatever the element with its id
was scrolled to on the previous one. `boxScrollReset` exists and is
called from the suite only.

`resize` clears its own two maps in `cascadeReset`, which is the fix
this wants as well: one line, in the one function every document load
goes through. It is not made here because the suite scrolls boxes
across pages deliberately in places and each of those would want
reading first, which is a task rather than a line.

### What the property instrument does not grade

The property instrument cross-checks every claim about a *property*:
one that css-2026.md says is implemented and that renders the same
either way is caught on every run. **Nothing plays that role for a
function, a unit, an at-rule or a selector's behaviour.** Those claims
are assertions until a suite asks, and one was wrong -- "`attr()` is
missing", of a function that has worked in `content` since generated
content landed.

The audit that found it swept css-2026.md's negative claims. The rest
hold up: `cursor`, `user-select`, `mix-blend-mode`,
`isolation`, `background-blend-mode`, `text-wrap-style`,
`text-decoration-skip-ink`, `shape-image-threshold`, `writing-mode`,
`text-orientation` and the four font ones are all *properties*, so the
instrument already grades them and agrees. `resize` was on that list
and is on it no longer. The claims with no
instrument are the ones to keep an eye on, and they now have suites:
`attr()` in `tests/unit/test_counters.f`, `min()`/`max()`/`clamp()`
and the `ex`, `ch`, `cap` and `ic` units in `test_values.f`, the two
anchor functions in `test_anchor.f`.

What still has no check of its own, and should get one before its
row is trusted: `@font-face`'s descriptors, `@counter-style`'s
`speak-as`, and `image()`'s colour fallback -- the last of which
css-2026.md already admits "has never had to show".

### The instrument

**Three measurements exist**, each with a floor in `tests/run.sh`:
`tests/conformance/properties.f` reports how many of the 405 CSS
properties the instrument can grade change what this engine renders
(269; Chromium answers for 406, and one of them -- `overlay` -- only the
user agent can set),
`tests/conformance/elements.f` how many of the 122 HTML elements get
the default `display` Chromium gives them (122 of 122), and
`tests/conformance/selectors.f` how many of 86 selectors match the same
elements as Chromium (70). Most entries in the work above should move
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
