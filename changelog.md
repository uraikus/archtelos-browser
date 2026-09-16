# Changelog

The past, by change. Every other document except todo.md and
benchmarks.md describes the present (CLAUDE.md, §3).

## Unreleased

### Ordered lists count in the system they were asked for

`lower-alpha`, `upper-alpha`, `lower-roman` and `upper-roman` were all
parsed as `decimal`, so a list asking for letters or roman numerals
counted 1, 2, 3. They number as themselves now, and `<ol type>` — the
oldest way to ask, which the standard maps to `list-style-type` — is
honoured as a presentational hint, along with the `lower-latin` and
`upper-latin` aliases.

**The alphabetic system is bijective base 26**, which is where this
invites an off-by-one: there is no zero digit, so 26 is `z` and 27 is
`aa`. Taking the remainder before the decrement gives `a0`, and the
checks pin 26, 27, 52, 53, 702 and 703 for exactly that reason.

**Roman is the subtractive form** — 4 is `iv`, not `iiii` — and it can
write neither zero, nor a negative, nor anything above 3999. Those fall
back to decimal, which the standard asks of a counter style that cannot
represent its value and which is also the only answer that leaves the
list readable.

Thirty-four checks in the new `tests/unit/test_markers.f`, which can
compare the labels as strings, and five in the render suite that the
label reaches the marker — two systems agreeing on every pixel would
mean the style never arrived, which is precisely what used to happen.
Regressing roman back to decimal fails three of them.

**This moves no instrument count**, for the same reason the border
styles did not: `--fields` says `list-style-type -> listStyle`, so the
property registers for its own field and always did. The instrument
asks whether a property is *read*, not whether it is *honoured*, and
reading `lower-roman` and then counting in arabic satisfies the first
question completely. That is the second feature this session where the
count was right and the rendering wrong.

### box-shadow

An outer shadow with offset, blur, spread and colour, a comma-separated
list of them, painted beneath the element's own background. The colour
defaults to the current colour, and the lengths are read in the order
the standard gives while `inset` and the colour may sit anywhere among
them.

**The canvas has no blur**, so the falloff is nested rectangles, one per
pixel of the blur's reach, each drawn at a small alpha: where more of
them overlap the alpha accumulates, so the shadow is densest against its
own edge and fades outwards. The shape and the extent are exact; the
curve of the fade is not. The checks are written to that division — an
offset and a spread are checked to the pixel, and the blur is checked
for what any blur must do, which is to reach past the box and to weaken
with distance.

Twenty-five pixel checks in the new `tests/render/shadow.f`. Paint is
unmoved on a page with no shadow: median 0.0 ms over 25 interleaved
paired runs, six slower and ten faster.

Properties **88 → 89**, and this is the first feature graded under the
rule that arrived with the last commit: `--fields` says
`box-shadow -> shadows`, so it registers for its own field rather than
for a neighbour's.

`inset` is parsed and not painted, and todo.md says so rather than
leaving it to be discovered.

### The instrument was crediting properties for other properties' fields

Painting borders turned up something the audit could not see: the
physical `border-*-style` rows had been registering all along, for an
engine that threw the declared keyword away. Declaring a style gives
that side the medium width, and the width alone moved the digest.

Three things came of chasing it.

**The digest can now say which field moved.** It was ninety-one values
joined with `|`, and nothing named them — so the instrument could report
*that* a property moved something and never *what*. It is a list now,
with a parallel list of names checked against it at startup, so a field
added to one and not the other stops the instrument rather than
mislabelling every property after it. `--fields` prints the mapping. The
join is no longer `|` either: `fontKey` contains one, so splitting the
old digest back gave ninety-four fields for ninety-one values and
misaligned everything past it. That was found by the startup check, on
its first run.

**A row's extra declarations are context now, not part of the test.**
Some properties do nothing alone — a border width computes to zero
unless that side has a style — so those rows carry a second declaration.
Graded against a bare element, the second declaration did the work:
`border-top-width: 10px; border-style: solid` registered on the strength
of the `solid`, and would have gone on registering if width parsing were
deleted outright. Each row is graded against an element that already has
its context, so the property has to move something itself. The audit
isolates the same way, so the two agree about what a row proves.

**`border-*-style`'s initial value was wrong.** The cascade answered
`solid` for an undeclared border. CSS says `none`. Nothing rendered
wrong, because a width of zero already stopped the paint, but it is why
declaring `border-top-style: solid` changed no style field: the field
already said solid. It says `none` now, and the row registers for its
own field.

**The count went down, from 89 to 88, and the engine did not regress.**
`outline-style` was registering only through the width a declared
outline style gives, and this engine has no outline style at all. The
floor in `tests/run.sh` moved down with it, with the reason beside it.

A count that goes up is not yet evidence the feature works, which is now
a rule in CLAUDE.md. Ask which field moved.

### Borders paint as the style they were given

Every border painted solid. The cascade derived one style for the whole
box from whether any width was non-zero and threw the declared keyword
away, so `border: 1px dashed` came out as a solid line and a box could
not be solid on one edge and dashed on the next.

Each side now carries its own style, and the painter draws it:

- **`double`** is the one the standard fixes exactly — two parallel
  lines with a gap, each as near a third of the width as the width
  allows — so it is checked to the pixel: six pixels become two, two and
  two. A width that does not divide by three gives the spare pixels to
  the lines rather than the gap, so a 2px double border is two hairlines
  rather than one line and a gap it has no room for.
- **`dashed` and `dotted`** are left to the user agent, so the checks
  ask what the standard actually requires — that the line be broken —
  rather than inventing a dash length and claiming Chromium agrees. A
  dash is three times the border's thickness and a dot is square, each
  followed by a gap of its own length, and the run is stretched so a
  whole number of marks spans the edge instead of ending in a stub.
- **`groove`, `ridge`, `inset` and `outset`** are accepted and painted
  solid: the right width and colour, without the relief. css-2026.md and
  todo.md say so rather than leaving it to be discovered.

Twenty-two pixel checks in the new `tests/render/borders.f`; stubbing
every side back to solid fails nine of them. The paint phase is unmoved
on the benchmark page, which is full of bordered table cells — a median
of 0.0 ms over 25 interleaved paired runs, five slower and seven faster.

**This moves no instrument count, and that is worth saying.** The
physical `border-*-style` rows already registered, because
`borderWidthProp` gives a side with a declared style the medium width
and that alone changes the computed style. They were registering for a
property the engine did not implement — the count was right for the
wrong reason, which is the same failure the audit found in the row
values, one level up. What the checks measure here is pixels.

**One test expectation was wrong and the code was right.** The first
draft asserted that dotted leaves more gap than dashed. It does not:
both put a gap of its own length after every mark, so both cover about
half the edge however often they break it. What differs is the number of
marks, which is what the check counts now.

### background-origin and background-clip

`background-origin` chooses the edge a background image is placed and
sized from; `background-clip` chooses the edge the whole background is
cut off at. Both take `border-box`, `padding-box` and `content-box`, and
they are independent: the origin anchors the tile grid, the clip decides
what survives.

- **Each constant is numbered so its own initial value is zero** —
  `border-box` for the clip, `padding-box` for the origin — so the two
  do not share a numbering and a style that mentions neither writes
  nothing. The alternative, one shared enum, would have made every
  element on every page set a field to say what the zero value already
  said.
- **Neither area is worked out unless it is asked for.**
  `paintBackground` runs for every box on the page: the clip rectangle
  is computed only when it is not the border box it defaults to, and the
  origin only when there is an image to put in it. The paint phase is
  unmoved — a median of 0.0 ms over 25 interleaved paired runs, nine
  slower and nine faster.
- **A gradient is clipped too.** It takes its geometry from the
  positioning area and must not paint outside the painting area, so when
  the two differ it goes through an image the size of the clip. That is
  the fourth thing standing in for the clip region the canvas does not
  have, after `overflow: hidden`, background tiling and `object-fit`.

Thirteen more pixel checks. The clip ones use the background colour
alone, with a transparent border so what happens underneath is visible —
no image, no scaling, so the colours are exact and the check is purely
about which rectangle was painted.

Properties **87 → 89**, both registered end to end.

One thing deliberately not done: a background clipped to the padding or
content edge keeps the border box's `border-radius` rather than deriving
the smaller inner curve. The corner would need a rounded-rectangle path
on an image layer, which has no path API (FINDINGS.md, "an image is a
drawable surface with a smaller API"). todo.md and css-2026.md say so.

### The audit pinned the rows to one Chromium and turned CI red

The properties audit passed here and failed in CI on its first run,
which is the audit working and the rows being wrong: `outline-width`
carried `3px`, and `medium` *is* 3px, so a build that reports the
computed width rather than the used one sees no difference. This
container's Chromium 141 reports `0px` for a bare element and saw one.

The row was pre-existing; the audit is what made it visible, and made it
fatal. The fix is a value that cannot be the initial one on any build
rather than one checked against the browser to hand: the four
`border-*-width` rows and `outline-width` are 10px now, which is neither
zero nor `medium`.

The audit names the browser it asked — "all 369 rows can register
against Chromium 141.0.7390.37" — so the next disagreement between two
builds says so in the failure rather than looking like a broken row.

### background-size

`background-size` takes `cover`, `contain`, lengths, percentages and
`auto` on either axis. A single value gives the width and leaves the
height `auto`, which takes its size from the image's own ratio; `auto`
on both axes is the intrinsic size, which is what the property did
before it existed.

The size it gives is not only what the image is drawn at. It is also
what `background-position` distributes the leftover of — a 20px tile in
a 100px box leaves 80, so `right` starts it at x=80 rather than at the
90 the intrinsic 10px tile would have given — and what
`background-repeat` steps by. Both are checked.

Thirteen more pixel checks in `tests/render/background.f`, and the
equivalence checks the rule asks for: `100% 100%` against the box's own
measurements written in pixels, and `40px` against `40px auto`.

Properties **86 → 87**, checked end to end rather than assumed: the row
was already one Chromium can tell from the initial value, `styleDigest`
gained the three fields, and the count moved when the implementation
landed.

**It costs a page without a background image nothing, and the reason is
structural rather than a measurement.** `computeStyleValues` runs once
per *distinct* style, not once per element — 24 times on the benchmark
page's 2,728 elements — so one more property read is 24 map lookups for
the whole document. The paired run agrees: a median of 0.0 ms over 25
interleaved runs, with the mean leaning 0.4 ms in a timer that counts
whole milliseconds.

### The properties instrument could not grade two thirds of its own rows

`tests/conformance/css-properties.txt` lists every property Chromium
reports on a computed style, each with a value an implementation must
visibly change. **242 of the 373 rows carried a value that could not
show a difference**, so those properties could have been implemented
perfectly and the count would not have moved.

- **218 rows declared `initial`**, which computes to the initial value by
  definition.
- **24 more carried a value equal to the initial one**, which no string
  inspection would catch: a border width with no border style beside it
  computes to zero, `text-decoration-style: solid` *is* the initial
  value, `list-style-image: none` and `grid-template-columns: none` are
  their own initial values.

They hid in plain sight: `--verbose` listed them among "properties that
change nothing", which is exactly where a genuinely unimplemented
property belongs, so the work list and the instrument's own defects were
the same list.

Chromium chose the replacements — a candidate is kept only if Chromium
computes it differently from the initial value, applied the way the
runner applies it, which is a style attribute and so may carry two
declarations where one is not enough. 241 rows now do; four cannot be
graded by a probe that is an ordinary element and say so in a third
column with the reason, and are excluded from the denominator rather
than counted as unimplemented:

| | |
|---|---|
| `d` | applies only to an SVG path element |
| `grid-template-areas` | computes to `none` unless the probe is a grid container |
| `hyphenate-character` | computes to `auto` unless hyphenation is applied |
| `overlay` | only the user agent can set it |

`tests/chromium.py properties-audit` asks Chromium of every row whether
it can register at all, `tests/run.sh` runs it before grading the
engine, and it fails the suite on a dead row or on a third column that
is no longer needed. Its own failure mode was checked by breaking a row
and watching it fail.

**The score did not move: 86.** This engine implements none of the 242,
so the reading was numerically right and measuring nothing — the
denominator is now 369 rather than 373 because four rows are honestly
excluded. What changed is that work on those properties can now show up
at all.

### Radial gradients

`radial-gradient()` and `repeating-radial-gradient()` paint, which
completes the gradient half of CSS Images 3.

- **`circle` and `ellipse`**, with all four extent keywords —
  `closest-side`, `closest-corner`, `farthest-side` and the initial
  `farthest-corner` — explicit radii, and `at <position>`.
- **A degenerate ending shape is a solid fill of the last stop**
  (§3.4.2.3 via §3.4.1), which is what `closest-side` centred on an edge
  produces. Painting nothing there is the obvious wrong answer and was
  the first one this got.
- **Painted as concentric bands**, one per pixel of the longer radius,
  each drawn as one-pixel-tall horizontal runs — the same shape the
  off-axis linear gradient uses, and for the same reason: every
  rectangle covers whole pixels, so abutting bands are not
  anti-aliased against each other into a stipple.
- **Nothing per element.** The four `Len` fields the radial shape needs
  have zero values that already mean the initial value, so `noGradient()`
  — which runs for every element on every page — writes none of them.
  Paired over 25 interleaved runs on the benchmark page, the cascade
  phase moved a median of 0.0 ms, the new build faster in 8 and slower
  in 5.

Forty-seven pixel checks in the new `tests/render/radial.f`. Chromium
cannot supply the colours here, so the gradient under test is
`red 0%, red 50%, blue 50%, blue 100%` — two hard stops, so every
expectation is an exact colour and every check is really a question
about where the boundary is, which is the whole content of the sizing
algorithm.

### A percentage position was a hundred times too far

`background-position: 50% 0` put the image off the box entirely, and
`object-position` with a percentage did the same.

A percentage `Len` holds the number out of a hundred — `resolveLen`
divides by 100 wherever the layout reads one. The position code read it
as a fraction instead, and the keywords were written to match: `center`
was stored as `lenPercent(0.5)`, meaning half of one percent, which
`resolveLen`'s own convention would have placed one pixel in from the
edge. The two wrongs cancelled for a keyword and for a length in pixels,
which is everything the tests used, and nothing else worked at all.

Both now hold the standard convention and both readers divide by a
hundred. The regression tests pin the two against each other: a
percentage and the keyword that means the same thing must land on the
same pixel.

This is the second bug of the shape found in two commits — a value that
two pieces of code agree about only because neither was ever given a
case where the disagreement shows. The defence is the same one that
caught it: test the new way of saying a thing against the old way of
saying the same thing, not just against a number.

### One line of a parser, two features broken

`radial-gradient(red, blue)` — the plain form, with no shape, size or
position — painted nothing at all, because the prelude parser asked
whether a word was a length by testing for `LEN_AUTO`. `parseLength`
answers `LEN_INVALID` for a word that is not a length at all; `LEN_AUTO`
is only for the literal `auto`. So `red` parsed as a radius, the first
colour stop was eaten as part of the prelude, and the gradient came out
with a zero-length ray.

### object-fit and object-position

A replaced element's content was always stretched to its box, which is
`object-fit: fill` — right for the initial value and wrong for every
other one. All five fitting values work now, with `object-position`
placing the result.

- **`contain`** and **`cover`** scale by the smaller and the larger of
  the two axis ratios; **`none`** keeps the intrinsic size; and
  **`scale-down`** is the smaller of `none` and `contain`, which is
  `contain` capped at a scale of 1.
- **`object-position`** takes keywords and lengths on both axes, and
  resolves a percentage against the space the object leaves over, the
  same way `background-position` does. Its initial value is `50% 50%`,
  not `0% 0%`, so an object smaller than its box centres.
- **Content that overflows the box is clipped to it**, which `cover` and
  `none` both cause, through an image the size of the content box — the
  device `overflow: hidden` and background tiling already use, since the
  canvas has no clip region.
- **`fill` is still one blit.** It covers the box exactly, so there is
  nothing to position and nothing to clip; a page that never mentions
  `object-fit` reaches the same call it did before. Neither does the
  extra cascade work show up: paired over 25 interleaved runs on the
  benchmark page, the cascade phase moved by a median of 0.0 ms, and the
  new build was the faster of the pair in 10 runs against 7.

Forty-six pixel checks in `tests/render/objectfit.f`. The properties
instrument reads **86/373**, up from 84.

**The ground truth is the specification's algorithm, not another
browser.** Headless Chromium in this container paints only the first
scanline of a screenshot, so it cannot supply pixels; the sizing
algorithm is exact, so every expectation is derived from the intrinsic
size and the box with the derivation written beside the check.

**The instrument had to be fixed before it could register anything.**
Both properties already had real values in
`tests/conformance/css-properties.txt`, put there ahead of the work — but
`styleDigest` in `tests/conformance/properties.f` did not read the two
new fields, so the count stayed at 84 with the feature fully working.
A probe row with a real value is only half of it: the digest has to look
at the field the row moves.

**Cairo filters a scaled blit.** An unscaled `drawImage` is exact to the
pixel, and a scaled one blends about two pixels either side of every
edge and of any colour boundary inside the image. The pixel checks step
three pixels clear of a scaled edge and check the `none` cases, which
are unscaled, right on the boundary.

### Opacity and the clipping layer

Anything clipped here is painted into an image the size of the clip and
blitted back, because the canvas has no clip region. That blit is a
separate drawing call, and the element's opacity has to be applied to it
exactly once. Neither place that does this got it right.

- **A background image ignored `opacity` altogether.** `paintBackground`
  sets the alpha for the background colour and resets it to 1 before the
  image, so a background image on a half-transparent box painted fully
  opaque. Shipped in the background-images commit; no test combined the
  two.
- **`object-fit`'s clipping layer applied it twice**, once into the
  layer's own pixels and again as the layer was composited — and not
  even to a value another opacity could reproduce, because the
  intermediate is premultiplied and rounds.

Both now draw into the layer at full alpha and apply the element's
opacity to the blit. The tests compare the clipped path against the
unclipped one at the same opacity, which is the comparison that has to
hold and the one neither bug survived: a background image against a
background colour of the same blue, and `object-fit: none` (which
overflows a 10x10 box, so it clips) against `object-fit: contain`
(which fits, so it does not).

This is the hazard in using an image as a clip region rather than having
one: a clip is not supposed to be a drawing operation, and this one is,
so every piece of state that affects drawing has to be reasoned about
twice.

One Festina finding came out of it, number 30: the canvas takes
`drawImage`'s nine-argument source-rectangle form and an image
destination does not, so clipping a scaled draw inside a layer needs a
whole extra image where the canvas would need none. festina.md carries
the proposal, and the entry in festina.md's smaller-wants table about a
canvas clip region is corrected with it — `overflow: hidden` is
implemented, so what a clip region would save is an allocation and a
composite, not the feature.

### Background images

`background-image: url(...)` painted nothing: only gradients were
parsed, because a URL needs a fetch the cascade cannot do. It works now,
with `background-repeat` and `background-position`.

- **Fetched after the cascade**, not with the `<img>` elements, because
  a background URL only exists once styles are computed. The walk is
  gated on whether any computed style asked for one, so a page without
  them never makes it: paired over 25 interleaved runs on the benchmark
  page, median −1.0 ms, down in 14 runs and up in 9.
- **`background-repeat`** in all five forms, including the two-value
  one that names the axes separately.
- **`background-position`** takes keywords and lengths on both axes. A
  keyword is a percentage of the space the image leaves over, which is
  what makes `right` put the image's right edge on the box's right edge
  rather than pushing it a box-width across — in a 100px box a 10px
  tile starts at x=90, not x=100.
- **A tile that runs off the edge is cut off there**, painted through an
  offscreen image the size of the box, the same device `overflow:
  hidden` uses because the canvas has no clip region.

Twenty-five pixel checks in the new `tests/render/background.f`. The
properties instrument reads **84/373**, up from 82 — `background-repeat`
and `background-position` register, and their probe rows had to be given
real values first because both read `initial`.

The fixture's two halves are exactly CSS `blue` (#0000ff) and CSS
`green` (#008000). The first version used #00ff00, which is `lime`, and
every colour check failed against an implementation that was already
correct. The test file says so.

### Three memory bugs valgrind found and the tests could not

Parsing `background-repeat` and `background-position` splits a value
into words, and every one of the three splits this branch added bound a
word to a local — `ascii t = parts[0]`. That releases an alias the
compiler never retained, which is shape (c) of FINDINGS.md's second
finding, documented since the first week of this project. All twenty-five
pixel checks passed with the bug in place; the suite cannot see it.

One of the three shipped in the flex-wrap commit, in the `flex-flow`
shorthand, and was latent only because no test used `flex-flow`. There
is a test now, which is how a latent memory bug stops being latent.

The defence is to index at every use rather than bind — `parts[0] ==
'no-repeat'` instead of `ascii t = parts[0]` — and to run valgrind on
anything that splits an `ascii` before believing a green suite.
FINDINGS.md says so now, because knowing the finding was not enough to
prevent three fresh instances of it in one sitting.

### Two probe rows that could never have moved

`object-fit` and `object-position` are next on the roadmap, and their
rows in `tests/conformance/css-properties.txt` read `initial` — a value
that computes to the initial value, so the property could never have
registered as implemented however well it was implemented. They read
`cover` and `left top` now. Nothing else changed: the count is still
82/373 and both are still listed as doing nothing, which is the point.
The rule is to give a row a real value *before* the work, not to
discover afterwards that the number did not move.

Grading them needs pixels rather than geometry, because `object-fit`
changes where an image is painted inside its box and not the box
itself — and headless Chromium cannot supply those pixels here.
`--screenshot` paints only the first scanline: a plain 40x40 block of
flat colour comes back as one row of colour and 39 rows of white, with
or without `--virtual-time-budget`. It is the screenshot pipeline, not
images and not the decoder, which reads this project's own fixtures
correctly. `tests/chromium.py` never noticed because it reads the DOM.
todo.md records it so the next attempt does not spend the same hour
finding out.

### ::first-letter

The first letter of the first line of a block, styled on its own. The
selector parser accepted `::first-letter` and then made the rule
unusable; it now names a box, the cascade computes a style for it
without requiring any `content`, and the box tree splits the first text
box so that letter sits in an inline box of its own.

What counts as the first letter was read out of Chromium 141 rather
than assumed. At 16px monospace with `::first-letter { font-size: 32px }`
the width says which characters were chosen:

| markup | Chromium | what it means |
|---|---|---|
| `Hello` | 48px | five 16px characters |
| `Hello` with the rule | 58px | one 32px, four 16px |
| `"Hello` | 77px | **two** 32px — punctuation joins the letter |
| `   Hello` | 58px | leading whitespace is skipped |
| `<em>H</em>ello` | 58px | a nested inline still yields it |

Only the first letter of the block, not the first of every descendant:
the walk stops at the first one it splits and at any block-level child,
whose own first letter is its own.

`::first-line` still makes its rule unusable. Restyling a line that
only exists after line breaking is a different kind of change, and
saying so is better than matching the element and rendering something
nobody asked for.

Ten checks in the new `tests/unit/test_firstletter.f`. The line height
Chromium gives an enlarged first letter (26px against a 20px
line-height) depends on font metrics this engine does not have, so it is
not asserted.

### A space before an inline element was being dropped

`A <em>B</em>` rendered exactly as wide as `AB`, while `A B` and
`<em>A</em> B` were both correct. The space between a text box and a
following *element* was lost, which is ordinary prose — `a <b>word</b>`
— and it had been wrong for as long as there has been inline layout.

Intrinsic width only added a separating space when the box it was
looking at was itself text, so a space at the *end* of a text box
followed by an element was counted by nobody. It is carried across the
children as a pending flag now, and a text box that is nothing but
whitespace is treated as that space rather than as content with a width,
so two collapsing spaces are still one space.

Four widths that must all agree, in `tests/unit/test_layout.f`.
Chromium measures all four at 29px and this engine now measures all
four at 30px, the pixel being the known difference between its
character width and Chromium's. Found while measuring `::first-letter`
against a mixed-content case, which is the only reason it turned up.

Paired over 31 interleaved runs the fix costs nothing measurable:
median 0.0 ms, up in 15 runs and down in 13.

### open-quote and close-quote

The last of CSS2 §12 that was missing. `quotes` gives the strings,
`open-quote` and `close-quote` choose from them, and `no-open-quote` and
`no-close-quote` move the level without printing.

- **The depth runs over the document, not the tree.** An element three
  containers deep is still at depth zero until something has actually
  emitted an open-quote; an unclosed quote deepens everything that
  follows it in document order. Past the end of the list every deeper
  level repeats the last pair. All three were read out of Chromium 141
  by giving each level a string of a length nothing else shares and
  measuring the width it added.
- **A close-quote at depth zero prints nothing and stays there.** The
  first implementation decremented anyway and printed the level-one
  closing string; Chromium renders no characters at all, which the
  measurement said and the guess did not.
- **`<q>` gets a pair from the user-agent stylesheet**, so it renders
  quotation marks the way it should.

Twenty checks in the new `tests/unit/test_quotes.f`. The property
instrument cannot see any of this — Chromium does not enumerate `quotes`
on a computed style — so it is measured by the generated text, with
Chromium's widths as the corroboration.

### A user-agent rule that cost every page 8 ms

Adding `q::before` to the user-agent stylesheet turned the
pseudo-element pass on for every document, because the only gate was
"does any rule anywhere name a pseudo-element" — and the user-agent
sheet is registered for every page. The 51 KB benchmark page, which
contains no `<q>`, got 8 ms slower.

The gate is now per tag: registration records which tags have a
pseudo-element rule, and whether any such rule is keyed on something
other than a tag. A page whose only pseudo rule is the user agent's own
`q::before` rules out every element with one map lookup. Back to a
paired median of 0.0 ms against the build before the rule landed.

This is the rule in CLAUDE.md working as intended — a feature must not
cost anything to the pages that do not use it — and it is the second
time on this branch that a cost was found by measuring rather than by a
benchmark noticing later.

### Flex containers wrap

`flex-wrap` was the largest hole left in Flexible Box 1: every container
was single-line, so a row that did not fit shrank its items instead of
starting a second line, and `align-content` had nothing to distribute.

- **Items are broken into lines** before anything is sized, and each
  line grows and shrinks on its own. An item alone on the last line
  takes all of that line's free space, not a share of the container's.
- **`align-content`** distributes the lines across the cross axis in all
  six values, and stretches them when it is not asked otherwise — which
  is what makes two lines of height-less items fill half a container
  each. `flex-flow` parses as direction and wrap in either order.
- **`wrap-reverse`** flips the cross axis, which reverses the order of
  the lines *and* the end of its own line an item aligns to. Both halves
  are needed: Chromium puts the first line's items at the bottom of a
  line that is itself at the bottom.
- **Auto margins** absorb a line's free space before `justify-content`
  is consulted, sharing it equally when several are auto, which is how
  `margin-left: auto` on one item pushes the rest to the end.
- **`align-items: baseline`** lines the text up rather than the boxes:
  the line's depth is the deepest baseline plus the most that hangs
  below it, which is not the tallest item.

Forty checks in the new `tests/unit/test_flexwrap.f`, every expected
number read out of Chromium 141. The properties instrument reads
**82/373**, up from 80 — `flex-wrap` and `align-content` register.

### Free space is distributed by rounding the running total

Three items sharing 400px were 133, 133 and 134 and started at 0, 133
and 266, where Chromium starts them at 0, 133 and 267. Rounding each
item's share on its own loses a pixel off the end of the row; rounding
the *cumulative* share and taking differences puts every edge where a
browser puts it. The same change fixes `align-content: stretch`
distributing cross space between lines.

Every length here is still an integer, so an isolated width can be a
pixel off even when the edges are right. todo.md records that as the
sub-pixel gap it is rather than leaving it to be rediscovered.

### A measurement harness that quietly dropped the page font

The first Chromium probe for these numbers set `innerHTML` on a `<div>`
with markup that began `<body style="font:16px/20px monospace">`. A
`<body>` inside `innerHTML` is discarded by the parser, so the font
never applied and every font-dependent number came back wrong — a
32px item measured 37px tall instead of 20. The wrap cases all use
explicit pixel sizes and were unaffected; baseline alignment was not,
and was re-measured on a whole document. The test file says so, because
the next person writing a probe will reach for `innerHTML` too.


### A preload scanner, and prefetching on worker threads

A browser that waits for tree construction to finish before it asks the
network for a stylesheet has wasted the parse. A scanner now walks the
raw bytes once, before the tokenizer sees them, and reports the
`<link rel=stylesheet>`, `<img src>` and `<script src>` URLs the
document is going to want. The absolute ones are handed to four worker
threads and fetched while the main thread parses.

- **The scanner is not a second parser** and must not become one: it
  keeps no stack, has no opinion about nesting, and stops after 24
  resources or 64 KB of source. Where it does read markup it agrees with
  the tokenizer exactly — a trailing slash belongs to an unquoted
  attribute value, raw-text element contents are skipped — because a URL
  it reads differently from the tree builder is a request nobody wanted
  and does not save the request somebody did. 53 checks in the new
  `tests/unit/test_preload.f`.
- **Writing the test first caught a wrong intention.** The first draft
  asserted that `<img src=k.png/>` yields `k.png`. The standard's
  unquoted attribute value state ends on whitespace and `>` and nothing
  else, and Chromium 141 duly requests `k.png/`; the assertion was
  corrected to match, not the code.
- **Measured against a latency-bearing server** (`tests/latencyserver.py`,
  50 ms per response), a page with sixteen subresources loads 3.76 times
  faster: 1,558 ms down to 414 ms. Most of that is parallelism, which
  any concurrent fetch would give. The scanner's own contribution is the
  overlap with parsing, isolated on a 640 KB document where the wait for
  prefetches is 0 ms because both fetches finish inside the 127 ms
  parse. benchmarks.md reports both separately rather than quoting the
  flattering total.
- **It costs pages that do not use it 4 ms**, which the first draft of
  this entry recorded as "nothing measurable" and was wrong about. Not
  the scan, which is skipped outright for a non-HTTP base: the four
  worker threads *existing*. glibc's `malloc` gives up its
  single-threaded fast path at the first `pthread_create` and never
  takes it back, and Festina allocates on almost every operation. The
  number is a paired median over twenty interleaved runs of the build
  before and the build after, positive in 17 of 20.
- **`ARCHTELOS_NO_PRELOAD=1`** turns it off, so the benchmark measures
  one binary on one page rather than comparing two builds.
- Clean under valgrind and under helgrind — no invalid access, no leak,
  and no data race — which matters more than usual here, because
  collecting a worker's result needs uncounted shared memory.

### Findings: five more places Festina is insufficient

Two of them block this browser from the live web.

- **An HTTP response larger than 64 KiB takes thirty seconds.** The
  client reads to EOF rather than to `Content-Length`; a keep-alive
  server never sends EOF; the 30 second socket timeout ends the read.
  `curl` fetches the same 640 KB in 53 ms.
- **The query string is dropped from every outbound request.**
  `GET /page?a=1` goes out as `GET /page`, with `req.code` 200 and
  `req.url` unchanged, so nothing in the program can detect it.
- **A worker's answer cannot be collected synchronously.** Every route
  back — `reply`/`callback`, worker-to-main `postMessage` — goes through
  main's event loop, which straight-line code never reaches, and
  `drain()` does not pump it. The escape used here is a manually-managed
  `T?`, which crosses to a thread by reference: the workers write into
  its arrays and `drain()` is the barrier.
- **A thread body cannot share code, and a pool instance cannot name
  itself**, so `src/net/preload.f` carries the same eleven-line HTTP
  fetch four times, differing only in the offset it starts at.
- **A declared thread makes the program non-terminating**, because a
  live thread keeps the program alive. `tests/assert.f`'s `finish()` and
  every conformance runner now end in an explicit `close()`.
- **Declaring a thread taxes every allocation in the program.** Four
  workers that are asleep and have never been sent anything slow an
  allocation-heavy probe by 9%; an allocation-free one does not move.
  Killing them does not give it back. This is the one place this branch
  breaks the project's rule that a feature must not cost the pages that
  do not use it, and Festina offers nowhere to put the fix.

### SIMD: measured rather than asserted

Festina has no SIMD types and no intrinsics, so any vector code in the
binary is LLVM's autovectorizer working on generated IR. Counting vector
instructions over the whole binary would have answered the wrong
question — it links Cairo and libc, and scalar float arithmetic lives in
`%xmm` registers without being vectorization at all. Counting packed
against scalar instructions per named function gives the real answer:
the vectorizer works, and this browser's hot loops mostly defeat it.
`paintLinearGradient` gets 14 packed operations against 45 scalar;
`asciiIndexOf` and `cascadeMatches` get none. benchmarks.md carries the
table and the disassembly, and todo.md carries the one loop worth
rewriting for it.


### Flexible Box Layout 1

`display: flex` was accepted and laid out as a block, which is why a
page built on flexbox rendered as one column. It now establishes a flex
container. Every expected number in the 37 checks of the new flex suite
was read out of Chromium 141 with `getBoundingClientRect` on the same
markup, and five more checks in the render suite confirm in pixels that
a flex row paints side by side rather than stacked.

- **`flex-direction`** in all four values, with the reverse directions
  placing the items from the other end.
- **`order`**, applied by a stable sort so equal orders keep document
  order.
- **`flex-grow`, `flex-shrink` and `flex-basis`**, with the `flex`
  shorthand and its `none`, `auto` and `initial` keywords. A bare
  `flex: 1` zeroes the basis, which is what makes two items share the
  whole line rather than the slack.
- **`justify-content`** in all six values, including the three
  space-distribution ones.
- **`align-items` and `align-self`** with `stretch`, `flex-start`,
  `flex-end` and `center`. `baseline` parses and falls back to
  flex-start.
- **`gap`, `row-gap` and `column-gap`**.
- **`inline-flex`**, which is inline-level and shrinks to fit: its
  intrinsic width is the items plus the gaps along its own main axis,
  so it is placed on a line like an inline-block rather than taking the
  full width as a block.
- **Anonymous flex items**: text directly inside a flex container is an
  item of its own and takes main-axis space.

Not implemented: `flex-wrap`, so every container is single-line and
`align-content` has no lines to distribute; `baseline` alignment; and
auto margins inside a flex container.

Ten more properties change what renders: 67 of 373 to **77 of 373**, and
the suite's floor moves with it.

### Nineteen milliseconds back, where no page was using the feature

The CSS work of the last few changes cost 33 ms end to end on the 51 KB
benchmark page, 131 ms to 164, and positioning alone was 18 of them.
Almost none of that was the feature: it was work every page paid whether
or not it had a positioned or floated box. Rebuilding each revision and
re-running them together on one machine is what located it —
benchmarks.md has the per-revision table.

- **The positioned-layout pass is skipped** when the document contains
  no positioned box. It was a second walk of the whole box tree on
  every page.
- **The painter's two-pass z-index child ordering is skipped** the same
  way, leaving a single pass in document order.
- **`boxIsOutOfFlow` and `boxIsFloated` answer from a document-level
  flag first**, so on a page with neither they cost one boolean read
  rather than four field reads, and they are asked of every child of
  every block. `applyFloatsToLine`, once per line box, returns the
  containing block's edges without scanning the float list.
- **Two allocations came out of the cascade's inner loop.** Reading the
  first two characters of a declaration name built a fresh `ascii` per
  declaration per element, where `text.charCodeAt` needs none; and the
  `'var('` needle `styleProp` scans for was rebuilt on every property
  read of every element.

The page now renders in 152 ms end to end. The 14 ms that remain are the real cost
of computing about thirty more properties per element, which is the next
thing to attack.

### overflow: hidden clips, through an offscreen image

The canvas has no clip region, and todo.md said for that reason that
`overflow` clipping needed one. It does not. A Festina `img` is itself a
drawable surface — `drawRect`, `drawText`, `drawCircle`, `drawImage`, a
transform and a state stack — and it **clips at its own bounds**, cutting
a glyph in half at the edge like any clip should. So a clipped subtree is
painted into an image the size of the box's padding box, with the image's
own `translate` carrying the offset so everything still speaks document
coordinates, and the result is blitted back.

Every primitive in the painter now goes through a wrapper that sends it
to the canvas or to the current layer. The box itself is not clipped —
its background and border paint normally — and only its descendants go
to the layer, which is what §11.1.1 says.

**One thing is approximate, and it is recorded rather than hidden.** An
image has no path API at all: no `beginPath`, `moveTo`, `lineTo`,
`curveTo` or `fillPath`. So inside a clipped subtree a `border-radius`
is drawn square, and a bordered box's rounded stroke becomes four
straight sides. The fill state is shared between the two surfaces, so it
is the geometry that is missing rather than the colour. FINDINGS.md has
the asymmetry and festina.md proposes the fix: the same seven calls on
`img` that `translate` and `saveState` already have.

Eleven pixel checks, including the case a rectangle-by-rectangle clip
could never do — text cut off mid-glyph at the container's edge.

`overflow-x` and `overflow-y` now change what renders: 78 of 373 to
**80**. `overflow` joins the `@supports` list, which it was kept out of
on the ground that the cascade computed it and nothing read it — the
rule that keeps this project's numbers honest, applied in the direction
that costs it something and now in the direction that pays.

### The audio element draws its controls

`<audio>` was in the user-agent stylesheet's `display: none` list, so an
`<audio controls>` rendered nothing where Chromium draws a 300x54
control bar. The rule is `audio:not([controls]) { display: none }` now,
which is what Chromium's own stylesheet says and which this engine could
not express until Selectors 3 gained attribute selectors inside `:not()`.

An `<audio controls>` is a replaced element of that size, drawn as a
rounded bar with a play triangle, a timeline and a speaker. Its children
are fallback content for a user agent that cannot play it, so they are
not rendered — the same rule as an iframe's children.

The elements instrument gains a second row for the element: its first
column may now name a variant, `audio[controls]`, and the element looked
up is the part before the bracket. Default displays matching Chromium
go from 121 of 121 to **122 of 122**.

**It does not play, and that is a decision rather than an omission.**
Festina has real audio — `aud`, `.play()`, `.stop()`, `.isPlaying()` —
but using it links ALSA and libmpg123, and it links them dynamically, so
the binary would carry `libasound.so.2` and `libmpg123.so.0` as runtime
`NEEDED` entries the way it already carries `libcairo.so.2`. A browser
that will not start on a machine without a sound library is a worse
browser. todo.md records it as deliberate non-work and festina.md
proposes the fix: open the device lazily, so a program that merely can
play audio does not hard-require the library to start.

### Counters

`counter-reset`, `counter-increment`, and `counter()` and `counters()`
inside `content` (CSS2 §12.4). A counter is a stack of instances: a
reset creates one, in force for the element that reset it, its
descendants and its following siblings; an increment adds to the
innermost instance, creating one on the root if none is in scope.
`counter()` reads the innermost and `counters()` joins them all with a
separator, outermost first. The stack is walked in document order
alongside the style computation, which already visits elements that way.

The counters are deliberately not part of the computed-style cache, and
it is worth saying why, because the two look like they should collide.
Two elements that matched exactly the same declarations share one Style,
and they can still stand at different counts. What differs between them
is the generated *content*, which is resolved per element and stored per
node; what they share is the *declaration*, which is the same for both.
So `counter-reset` and `counter-increment` live on the Style and the
running counts live in the cascade's stack.

Thirteen checks. The values were confirmed against Chromium 141 by
measuring the width the generated content adds to an inline-block span,
which reveals how many characters it produced -- `getComputedStyle` on a
pseudo-element returns the specified `content`, `counter(sec) ". "`, not
the resolved text, so it cannot be the ground truth here.

Two notes on what the instruments can and cannot see. `counter-reset`,
`counter-increment` and `quotes` are not in css-properties.txt because
Chromium does not enumerate them on a computed style, so implementing
them moves no count; they are measured by tests/unit/test_counters.f
instead. And the denominator of that file is 373 where Chromium
enumerates 406: the 33 not there are all `-webkit-` prefixed, which the
CSS Snapshot does not define. Both facts are now written in the file
rather than inferable from it.

### ::before and ::after generate boxes

A rule naming `::before` or `::after` describes a box generated inside
the element, before or after its content, and it exists only when
`content` computes to something other than `none` (CSS2 §12.1). Both
the two-colon spelling and the one-colon spelling CSS2 used are parsed;
`::first-line` and `::first-letter` still make their rule unusable
rather than silently matching the element, which is what the old parser
did with every `::` selector.

`content` takes quoted strings and `attr()`, in any sequence, and any
other component -- a counter, `open-quote`, `url()` -- makes the whole
value invalid rather than dropping part of it silently.

The generated box carries the pseudo-element's own computed style,
inheriting from the element rather than from the element's parent, so
`display: block` on a `::before` puts the generated content on its own
line and a `color` on it does not touch the element's text. A rule that
sets a colour but no `content` generates nothing at all.

Rules with a pseudo-element are collected in a separate pass with the
opposite filter, so they never style the element they match and ordinary
rules never style the generated box. The pass runs only when some rule
somewhere names a pseudo-element, which almost no document does.

Twenty-one checks, the geometry read out of Chromium 141. They are
written as relations -- the width a two-character `::before` adds is to
the width a three-character one adds as 2 is to 3 -- because this
engine's font metrics differ from Chromium's by a pixel every few
characters and the relations are what the feature promises. The inline
case goes to the line fragments rather than the box, because an inline
box has no width of its own here.

### Selectors, measured against Chromium and then completed

A third instrument joins the two that grade CSS properties and default
element displays. `tests/conformance/css-selectors.txt` lists 61
selectors; each is run against one fixture document and the elements it
matches are compared with the elements Chromium's `querySelectorAll`
matches on the same document. A selector counts only when the two sets
are identical -- parsing it, or matching some of the right elements, is
not implementing it.

It started at **34 of 61** and found a bug in the first run.
`:nth-child(2n)` matched the second child: the argument was read with
`toInt()`, which answers 2 for `2n`, so a selector that should match
every even child silently matched exactly one. That is worse than not
supporting it, and nothing in the suite could see it.

What the measurement then drove:

- **The `An+B` grammar**, properly parsed -- `odd`, `even`, an integer,
  `n`, `2n`, `2n+1`, `-n+3`, `+3` -- and rejected when it is not one of
  those, rather than mis-read. Seventeen unit checks pin the forms, and
  five more pin that `An+B` decides membership rather than a position.
- **`:nth-last-child()`, `:nth-of-type()`, `:nth-last-of-type()` and
  `:only-of-type`**, which share one index-and-match routine with
  `:nth-child()`.
- **`:empty`**, **`:enabled`**, **`:disabled`**, **`:checked`** and
  **`:lang()`**, the last of which walks to the nearest ancestor with a
  `lang` attribute and matches `fr` against `fr-CA`.
- **`:target`**, which parses and matches nothing -- correct for a
  document that was never navigated to a fragment.

The count is **56 of 61**, and the five that remain are all Selectors 4:
`:is()`, `:where()`, `:has()`, a selector list inside `:not()`, and the
attribute case-sensitivity flag. Every Selectors 3 entry passes.

Two things about the instrument itself, because both were nearly wrong.
A comment marker of `#` silently dropped every id selector from the
list, since `#p1` is a selector and not a comment; a comment is `# `
now, with the space required. And `:has()` counted as working, because
the selector chosen for it matched nothing in the fixture and an engine
that drops a selector agrees with one that implements it. Every selector
in the list now matches at least one element, and the runner fails the
run if that stops being true.

### An off-axis gradient was stippled, and the tests said it was fine

A gradient at an angle was drawn as a run of bands, each the polygon
where the band met the box. A polygon's vertices have to be whole pixels
-- `moveTo` and `lineTo` take integers -- so abutting diagonal slivers
were anti-aliased against each other and the ramp came out stippled. A
400x300 gradient wrote a 77 KB PNG; the same gradient drawn correctly
writes 7.5 KB.

**Eleven pixel checks passed on the broken rendering**, including three
inside the gradient at the angle in question. The stipple perturbs a
pixel by a couple of units and the tolerance was three, so sampled
values could not see it. Neither could adjacent samples: a run of eight
neighbouring pixels passes on both renderings.

What distinguishes them is how often neighbouring pixels are the *same*
colour. A smooth ramp advances less than one colour level per pixel, so
most neighbours are identical; stipple makes nearly every neighbour
differ. On this gradient it is 245 equal pairs of 360 when drawn
correctly against 147 when stippled, and the check needs nothing but
colour equality, which is all Festina offers. That check now exists, and
it fails on the previous revision.

The fix is to stop drawing polygons. An off-axis band is painted as
one-pixel-tall horizontal runs, one per row of the box, so every
rectangle has integer coordinates and covers whole pixels exactly and
nothing is blended with anything.

That is not free, and the benchmark now says so. Along an axis a band is
one rectangle, so painting is proportional to the gradient line's length
and sixty gradient boxes cost a millisecond. Off the axis a band becomes
one rectangle per row, so the work is the line's length times the box's
height, and the same sixty boxes cost 14 ms of paint and take the page
from 24 ms to 60 end to end. The commit that introduced this called an
axis-aligned figure a general one; benchmarks.md carries both, and
todo.md carries the fix — render a gradient once into an offscreen image
and draw that image.

### Linear gradients, painted a band at a time

`linear-gradient()` and `repeating-linear-gradient()` work as a
background image: `to <side>` and `to <corner>` keywords, an angle in
`deg`, `turn`, `rad` or `grad`, any number of colour stops, and stop
positions given as percentages, as lengths, or omitted and spaced evenly
between their neighbours. Twenty-two pixel checks, every expected colour
read out of Chromium 141 by painting the same gradient and calling
`getImageData`.

**The canvas has `fillLinearGradient` and a browser cannot use it.** Its
two colour arguments are `color`-typed, and a `color` in Festina must
come from a literal — "so the compiler can resolve it once". A CSS
gradient's colours come from the document and are never literals, so the
one call that would draw this exactly is unreachable. It also takes
exactly two stops where CSS allows any number, and drops alpha.

So a gradient is painted as a run of one-pixel bands of flat colour.
Along an axis each band is a rectangle. Off the axis there is no clip
region on the canvas either, so a band cannot be a rotated rectangle
clipped to the box, and is built instead as the polygon where the band
meets the box and filled as a path — with each band starting a pixel
early, because the polygon's vertices must be whole pixels and abutting
diagonal slivers leave seams of background showing through.

FINDINGS.md gains two entries for this and festina.md a proposal: `rgb()`
as an expression, a gradient call taking a list of stops, and component
access on a `color`.

That last one matters for the tests as much as the renderer: a `color`
compares equal or not, and cannot be interpolated into a string or read
apart, so "this pixel is within three of that colour" is not a question
the language can ask. The gradient tests answer it by painting each
candidate with `fillStyle`, which does take numbers, and reading it back.
The tolerance is needed because Skia dithers gradients and Cairo does
not.

One more property changes what renders: 77 of 373 to **78**.

### Two pieces of repeated work in layout, and an honest null result

`textIsCollapsibleBlank` built a fresh `ascii` on every call to read
whether a string is all spaces, and it is asked several times of every
text child of every element while the box tree is built. It reads the
`text` directly now, which allocates nothing — and answers correctly for
a string with a non-ASCII character in it, where the old one answered
false because `toAscii` returned null.

`wordsOf` splits a text box into words with a regex replace and a split.
It was called 3,761 times for 2,201 text boxes, because intrinsic widths
ask for the words and then placing the text asks again. The words depend
only on the content and the computed style, both fixed once the cascade
has run, so they are worked out once and kept on the box.

**Neither change moves the benchmark.** The layout phase's best of
fifteen runs is 47 ms before and after; only the mean moves, 50 ms to
48. Removing 1,560 regex splits and a few thousand allocations is less
than the phase's own run-to-run spread. The sub-phase counter for
`wordsOf` reads 5 ms before and 0 after, which is why it looked like
more: that counter is noisy across runs, and the instrument itself is
not the explanation — a `now()` call costs about 20 ns here, so
bracketing 3,761 calls with two of them costs 0.15 ms, not 5.

The changes are kept because they are strictly less work for
byte-identical output, not because they made the page render faster.

### One computed style per distinct match, not one per element

Computing styles had become the largest phase of the cascade — 37 ms of
the 59 — and the one that grew with every property implemented, because
every element paid to parse every declaration that matched it. Two
elements that matched the same declarations under the same parent
compute the same style, and on a real document most elements do: this
benchmark page's 1,560 table cells all match the same four rules.

`computeStyle` now keys on what the computation reads — the parent
style, the tag, and the matched declarations in order with their weights
— and hands back a style it has already produced. **The 2,728 elements
of the benchmark page have 24 distinct computed styles between them.**

| | Before | After |
|---|---|---|
| Computing styles | 37 ms | 8 ms |
| Property reads | 200,128 | 1,725 |
| Cascade | 59 ms | 28 ms |
| Parse, style and lay out | 117 ms | 81 ms |
| Peak memory, 51 KB page | 20.5 MB | 17.0 MB |

Chromium's lead on the rendering work goes from 4.3x to **3.2x**, and
layout is now the larger half of what is left.

Sharing a computed style means many elements hold the same `Style`, so
nothing may write to one after the cascade. One place did: `layoutFlex`
put a flex item's main size into `style.width` for the duration of the
item's layout. That is `Box.forcedWidthPx` now, which is where a value
decided by layout belonged.

Eleven checks pin the cache key, most of them negative — a different
class, a different parent, an inline style of its own, a different tag,
a different inherited colour — because the failure mode of a cache key
is two elements sharing a style they should not. The rendered output is
byte-identical to the previous revision on every example, at two canvas
heights, including a framed document.

### Three standing rules, each bought with a mistake

CLAUDE.md §3 gains three rules. None is a preference; each is the
generalization of something this branch got wrong and had to correct.

- **A measurement made by subtracting two large numbers must report the
  spread of both.** The "1.15 times faster" headline came of subtracting
  two quantities near 500 ms to obtain one near 50.
- **A feature must not cost anything to the pages that do not use it.**
  Positioning cost 18 ms on a page with no positioned box.
- **Give a property's row in `css-properties.txt` a real value before
  implementing it.** A row reading `initial` can never register as
  implemented, so the instrument would not have moved when the work
  landed.

todo.md carried the first two while they were proposals; they are rules
now, and it no longer repeats them.

### The benchmark was subtracting noise, and said so

benchmarks.md reported that Chromium rendered the 51 KB page "about
1.15 times faster". That number came from timing the whole command for both
engines and subtracting each one's start-up baseline. Twelve consecutive
start-up measurements of Chromium on one machine span 436 to 542 ms — a
spread of 106 ms around a quantity of 30 to 90. Subtracting a number
near 500 from a number near 510 measures the variance of the baseline:
the same method gives 1.15x on one run and 3.8x on the next.

`tests/chromium.py` gains a `render` mode that times parse, style and
layout **inside** the page with `performance.now()`, the way its `parse`
mode already did, and `tests/bench.sh` compares it against the sum of
this browser's own parse, stylesheet, cascade and layout phases. Same
work, same page, start-up and PNG encoding outside the timer on both
sides.

Measured that way, **Chromium renders the 51 KB page 4.3 times faster**,
117 ms against 27.2, and about ten times faster on pages of a few
kilobytes where a fixed 10 ms has nothing to amortize against. That is
the real headline and it is a worse one. What remains true is the other
question: this browser produces the PNG in 152 ms against 558, because
Chromium spends about 515 of those starting up.

### Benchmarks record memory and size

`tests/bench.sh` measures peak resident set size against Chromium on the
same page and the same canvas, and reports the binary and source size.
Peak RSS comes from `tests/maxrss.py`, which reads `ru_maxrss` for the
child tree, because `/usr/bin/time` is not present everywhere this runs.
This browser peaks at 12.7-20.4 MB against Chromium's flat ~195 MB, and
its binary is 2.3 MB against Chromium's 463 MB executable. Both numbers
are recorded in benchmarks.md with what they do and do not prove.

### A batch of properties that were computed and ignored

Five that did nothing and one that was never parsed. The geometry in the
15 new checks was read out of Chromium with `getBoundingClientRect` on
the same markup.

- **`box-sizing`**, so a declared width or height can be the border box
  rather than the content box. Every box was content-box.
- **`max-height`**, which had no field at all: the declaration was
  inert, and a 300px-tall box with `max-height: 40px` stayed 300.
- **`word-spacing`**, which widens every space by its length.
- **`caption-side`**, so a caption can go below the rows. Captions
  always went above.
- **`outline`** and its longhands, drawn just outside the border box and
  taking no space. Every outline style paints solid, as every border
  style does.

Seven more properties change what renders: 60 of 373 to **67 of 373**,
and Basic User Interface 3 is no longer a specification the engine has
no part of, which takes the official definition from 11 untouched to
**10 of 24**.

### Floats and clear

`float` was parsed, computed and never read; every floated box laid out
as an ordinary block. CSS2 §9.5 works now, which leaves `overflow`
clipping and generated content as the CSS2 chapters still missing.

- A float is placed at the edge of its containing block, as high as it
  fits, after any float already there, and two floats on the same side
  sit beside each other until the line runs out.
- **The line boxes beside a float are shortened**, which is how text
  wraps around one. A line below the float gets the full width back.
- A block box's own position and width ignore floats entirely, so a
  block sits underneath one, which is what the standard says and what
  Chromium does.
- `clear: left`, `right` and `both` move a box below the floats on that
  side, and a float can clear too.
- A float does not add to its parent's height.

Every expected number in the 21 new checks was read out of Chromium with
`getBoundingClientRect` on the same markup rather than reasoned about,
and a page with both kinds of float was rendered in both engines to
compare.

Two more properties change what renders: 58 of 373 to **60 of 373**.

What is missing is the block formatting context. A float belongs to one
and cannot escape it; there is one float list for the document instead,
so `overflow: hidden` does not contain a float and a float does not grow
the parent that holds it. todo.md records it.

### Positioning

`position` did not appear in `src/css/` at all and every box was static.
CSS2 §9.3 is implemented now, which is the largest of the four CSS2
chapters the engine was missing:

- **`relative`** offsets a box from where the flow put it, carrying its
  descendants and its line fragments along, and leaves the space it
  occupied alone.
- **`absolute`** and **`fixed`** leave the flow entirely: they take no
  space, and they resolve against the padding box of the nearest
  positioned ancestor, or the viewport for `fixed`.
- All four inset properties work, with `left` and `top` winning over
  `right` and `bottom` when both are given.
- **`z-index`** orders positioned siblings, and a positioned box paints
  above its in-flow siblings whatever the document order. This is the
  common-case painting order, not the full stacking-context algorithm.
- `sticky` computes as `relative`, which is what it is until scrolling
  is part of layout.

Six more properties change what renders: 52 of 373 to **58 of 373**.

Two things this turned up. A text box shares the computed style of the
element around it, so `position` reads through to it, and an absolutely
positioned element lost its own text until out-of-flow was made a
property of the box rather than of the style. And a margin that
collapses all the way through to the root is dropped instead of moving
the document down — Chromium puts the div at 40 where this puts it at 0.
That one is recorded in todo.md rather than fixed here, because the
obvious fix double-counts the ordinary case.

### calc() and custom properties

Both are in the official definition of CSS, not a later level, and
neither existed. The official definition is 24 specifications and the
engine implements no part of 11 of them now, down from 12.

**`calc()`** is a sum of products over lengths and plain numbers, with
nested parentheses and nested `calc()`. A length now carries a pixel
part and a percentage part separately, so `calc(100% - 2em)` stays
unresolved until the containing block is known and resolves differently
in different places, which is the whole point of it. The standard's
invalid cases are rejected: a `-` without spaces around it, a length
added to a number, a length multiplied by a length, a trailing operator.

**Custom properties** are kept rather than dropped by name, they
inherit, and `var(--name, fallback)` substitutes them wherever a value
is read, including inside another custom property. An unresolvable
`var()` with no fallback makes the declaration invalid rather than
empty, as the standard requires. An element that declares none shares
its parent's map instead of copying it. A vendor prefix is still
dropped, and a test that asserted custom properties were dropped with
them was updated.

Two Festina findings came out of it. There are no forward declarations,
which is only a nuisance for mutually recursive functions. And slicing
an `ascii` that itself came from a slice is a use-after-free that
surfaces as an out-of-memory in `asciiTrim`, several frames away — the
same ownership gap as the unretained alias already recorded, reached
from the other direction.

### The cascade conformance bugs are fixed

Seven of them, each named in css-2026.md against CSS Cascade 4, Values 3
and Conditional 3, each with a test written before the fix.

- **Specificity is a triple**, (ids, classes and attributes and
  pseudo-classes, types), packed base 1024 so a plain integer comparison
  is the lexicographic one. It was a sum weighted 10000 / 100 / 1, where
  a hundred classes tied an id.
- **Importance inverts the origin order.** It added the same constant to
  every origin, so an important author declaration beat an important
  user-agent one. The order is now normal UA, normal author, normal
  inline, important author, important inline, important UA.
- **`inherit` takes the parent's computed value**, and `initial` and
  `unset` mean what they should outside a length context. `inherit`
  returned the initial value for every property but a handful, so
  `margin-left: inherit` was 0. `revert` behaves as `unset` and is
  recorded in todo.md as unfinished.
- **`@supports` evaluates its condition**, with `not`, `and`, `or` and
  nesting. It applied every block it saw, so a page's fallback and its
  enhancement both landed.
- **`text-decoration` and `opacity` no longer inherit.** Decoration
  propagates to descendant boxes for painting and opacity accumulates
  into a separate value, which is what the standard asks for and what
  the painter now reads.
- **`rem` resolves against the root element's computed font size** and
  **`vh` against the real viewport height**, which was never assigned at
  runtime and stayed at its initializer of 600.
- **An unparseable selector drops its whole rule**, not just itself.

Two test expectations changed with them, both encoding the old
behaviour: the specificity numbers the CSS parser dumps, and two rules
that used to survive with a selector that could never match.

### The benchmark was comparing unequal work

Headless Chromium's `--screenshot` captures the viewport; this browser's
defaults to a canvas the height of the whole document. On the 51 KB
benchmark page that is 800x600 against 800x8000 — Chromium encoding
480,000 pixels and this browser 6,400,000. PNG encoding is linear in
pixels and dominates both engines at that size, so thirteen times the
pixels were being charged to layout.

`tests/bench.sh` now pins both engines to 800x600. On equal terms
Chromium renders the page about **1.15 times faster**, where the old
table said four times. (That 1.15 was itself wrong, for a different
reason, and a later entry above corrects it to 4.5: it came from
subtracting a start-up baseline that varies by more than 100 ms.) The same page onto 800x8000 costs 354 ms against
134 ms, and all of that difference is encoding; the run records it as
its own row rather than as a comparison.

Correcting the canvas also moved paint from 15 ms to 4 ms and exposed
the real hot spots: the cascade and layout are 90% of the time, and 8 ms
of the cascade's 15 ms collection phase is the HTML presentational
attribute pass, run for all 2,728 elements though almost none carry such
an attribute. todo.md is ordered by that now.

### The CSS gap, measured against the snapshot

`css-2026.md` states where the style engine stands against the CSS
Snapshot 2026, taking the snapshot's own four classes in its own order.
The engine column is read from the code, counting a property as absent
when the cascade computes it but neither layout nor paint reads it,
since a page renders the same either way. That rule alone moves `float`,
`overflow` and `max-height` out of the supported column.

The headline is that the official definition of CSS is 24
specifications and the engine implements no part of 12 of them.

The classification corrects what the roadmap assumed. Custom properties,
`calc()`, flexbox and CSS Images are official-definition work rather
than modern extras, and positioning, floats, `overflow` clipping and
generated content are official-definition work too, through their CSS2
chapters. `:is()`, `:where()`, `:has()` and `@layer` ordering sit in the
snapshot's lower classes, below their prominence. todo.md is ordered
that way now.

Ahead of all of it are seven cascade corrections, because each is small,
each is wrong on ordinary pages, and anything built on top inherits the
error: specificity collapsed into one integer, `!important` not
inverting origin order, `inherit` returning the initial value,
`text-decoration` and `opacity` inheriting when they should not,
`@supports` applying every block it sees, `rem` against a hard-coded 16,
and `vh` against a viewport height still fixed at 600.

`www.w3.org` is refused by this network's egress policy, so the snapshot
has to be supplied to a session rather than fetched.

### Continuous integration

`.github/workflows/tests.yml` runs the whole suite on every pull request
and on `main`, in two legs: a native build and a valgrind build through
`tools/festina-generic`. Both run the unit suites, the offscreen render
checks, the tree-construction corpus with its floor enforced, and a
headless screenshot of each example, which the run keeps as an artifact.

Festina is not vendored, so the job assembles the toolchain the way
CLAUDE.md §4 documents it: a checkout of `uraikus/festina` on
`FESTINA_HOME`, the packages Festina links, and a sparse blobless
checkout of the corpus on `WPT_HTML_TESTS`.

A step checks the corpus arrived before the suite runs. The conformance
suite skips cleanly when the corpus is missing, which is right on a
laptop and wrong in CI, where a mistyped path would have turned the
conformance floor off without failing anything.

The native leg takes about a minute and the valgrind leg a little over
one, so both run on every pull request rather than on a schedule.

### Conformance brought level with Chromium

Closed the tree-construction gap on the two files where Chromium led
most, and the rest followed: **1,499 to 1,535 of 1,652** cases, which is
exactly what Chromium 141 passes on the same corpus. `template.dat` goes
123/123 and `webkit02.dat` 44/44, the latter two cases ahead of Chromium.

- **The insertion location** now implements the standard's foster
  parenting substeps: a template lower in the stack of open elements
  than the last table takes the node into its contents, and the
  template-contents redirect applies to whatever target the algorithm
  settles on. The adoption agency places its last node through the same
  algorithm instead of appending directly, so a repair inside a template
  stays inside it.
- **`<select>` holds ordinary flow content.** The "in select" and
  "in select in table" insertion modes are gone. A nested `<select>`
  start tag closes the open one, `<input>` breaks out of it, `<option>`
  and `<optgroup>` close their own kind, and `<hr>` closes both.
  `select` is no longer a "special" element, so it does not stop the
  adoption agency or an implied-end-tag search.
- **`<selectedcontent>` mirrors the selected option's content**, copied
  once when parsing finishes. This is an element behaviour rather than
  tree construction, but it is part of the document a parse produces.
- **frameset-ok** is saved and restored around a template, so a
  template's contents no longer decide whether a later `<frameset>`
  replaces the body; a template met in the body still rules one out.
- **A form in a table** is refused only when the form element pointer is
  set and no template is open, matching the rule "in body" uses.

The `<select>` and `<selectedcontent>` rules were derived from the
corpus's expected output and confirmed against Chromium directly,
because the standard's own text is not reachable from this network.

15 unit checks were added for these behaviours, since the corpus is
optional.

### HTML parsing rewritten against the WHATWG Living Standard

The parser was a hand-written scanner with a handful of implied-end-tag
rules. It is now the standard's own algorithm.

**Tokenizer** (`src/html/tokenizer.f`, rewritten). The states are the
standard's: tag and attribute states with every quoting form, the
comment states including `--!>`, the doctype states with public and
system identifiers and the force-quirks flag, RCDATA, RAWTEXT, PLAINTEXT
and the script-data escaped and double-escaped states, CDATA sections in
foreign content, and bogus comments for `<?`, `<!` and `</` followed by
a non-letter. A tag that reaches the end of the input without its `>` is
discarded, as the "eof in tag" states require.

**Character references** (`src/html/entities.f`,
`src/html/named_refs.f`). All 2,231 named references of the standard,
generated from its own tokenizer test data, matched longest-first, with
the 106 legacy names that are recognized without a semicolon and the
attribute-value rule that leaves `?a=1&copy=2` alone. Numeric references
get the standard's replacements for NUL, surrogates, out-of-range values
and the C1 block. The table replaces a hand-written 250-entry one.

**Tree construction** (`src/html/parser.f`, rewritten). All 23 insertion
modes; the stack of open elements with the default, list-item, button,
table and select scopes; the list of active formatting elements with the
Noah's Ark clause, reconstruction and the full adoption agency
algorithm; foster parenting; template contents as a real fragment node;
quirks-mode detection from the doctype, including the standard's list of
public identifier prefixes; and foreign content — SVG and MathML
namespaces, tag and attribute name adjustment, integration points and
the HTML breakout tags.

**DOM** (`src/dom/node.f`). Comment, doctype and fragment nodes, and a
namespace on every element. `dumpTree` was removed, superseded by the
standard's own serialization in `src/dom/serialize.f`.

**Input handling** (`src/html/decode.f`). Non-ASCII input was rewritten
as `&#N;` before tokenizing, which made a literal `&#233;` inside a
`<style>` element indistinguishable from a real character. The escape is
now a U+0001 sentinel that the source cannot otherwise carry, so raw
text keeps its ampersands undecoded and its non-ASCII intact.

Conformance against the standard's own tree-construction corpus went
from **329 to 1,499 of 1,652** cases. Chromium 141 passes 1,535 of the
same cases; 84 of the 153 remaining failures are cases Chromium fails
too. See benchmarks.md.

### Tests

- `tests/conformance/html5lib.f` runs the web-platform-tests
  tree-construction corpus and fails the build if the count regresses.
  It skips cleanly when `WPT_HTML_TESTS` is unset.
- `tests/unit/test_html.f` rewritten: 32 checks stated in the standard's
  serialization format, covering the adoption agency, foster parenting,
  template contents, quirks mode, raw text, character references and
  foreign content. The old expectations encoded the previous parser's
  non-conformant output.
- `tests/chromium.py` drives headless Chromium so conformance and parse
  speed have a yardstick.
- `tests/bench.sh` records benchmarks, comparing against Chromium on the
  same pages.

### Documents

- `CLAUDE.md` states the intent, the standards, and the working rules:
  tests before code, documents describe the present, benchmarks stay
  current, `FESTINA_HOME`, and valgrind through `tools/festina-generic`.
- `todo.md`, `changelog.md`, `benchmarks.md` and `festina.md` added.
  `FINDINGS.md` and `README.md` rewritten to describe the present.

### Festina findings from this round

- A **local** variable named like a global function miscompiles: the
  function wins and the emitted LLVM IR is invalid. Previously recorded
  only for parameters, where it was silent and produced garbage.
- `\n` in a regex literal matches the letter `n`, not a newline.
- Every imported file shares one global namespace, so two modules cannot
  both define `newFragment`.

## 0.1 — the first renderer

An HTML/CSS renderer and browser written entirely in Festina: tokenizer
and tree builder, CSS parser, user-agent stylesheet and cascade, block
and inline layout with tables and lists, painting on the Festina canvas,
HTTP(S) fetching, and a windowed shell with an address bar, scrolling,
history and link navigation, plus a headless `--screenshot` mode.

Five unit suites, an offscreen pixel-checking suite, and a runner that
can build generic-CPU binaries so valgrind can run them.

The Festina findings that shaped the code: unretained `ascii` aliases
(a use-after-free), cycle-collector walks that made tree traversal
quadratic, `'' == null`, struct fields that can never read as null, and
a parameter that cannot shadow a function.
