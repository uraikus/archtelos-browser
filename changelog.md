# Changelog

The past, by change. Every other document except todo.md and
benchmarks.md describes the present (CLAUDE.md, §3).

## Unreleased

### `justify-content` and `align-content` distribute a grid's tracks

`normal` and `start` were one value on a grid: §12.8's stretch ran
whatever the distribution said, so two `auto` columns in a 400px grid
came out 200 apiece under both. Chromium gives 200 under `normal` and
19 -- the content width -- under `start`, `center`, `end` and
`space-between`, then positions the pair at 0, 181, 361 and spread.

The stretch is now conditional on the axis distributing `stretch`, and
what it leaves over is handed to `flexOffsetFor`, the same function
that distributes a flex line's leftover among its items, once per
track. The initial value of `justify-content` moves from `start` to
`stretch`, which a flex container cannot notice: `flexOffsetFor`
returns the same offset for both.

Writing the test found a second bug behind the first. The row axis had
never stretched **at all** -- `gridSizeAxis` was called with an axis
size of -1 for the rows, so §12.8's `axisSize >= 0` guard excluded it,
and a two-row grid 400px tall left both rows at their 19px content
height. The container's content height is already sitting in
`layoutCBHeight`, put there by the caller that sized the box, so the
row axis now gets it -- captured before any child is laid out, because
laying one out moves that global to the child's own containing block.

`tests/unit/test_grid.f` 145 -> 170. The column-axis cases were written
first and failed on the value they were supposed to; the row-axis cases
failed on something nobody had asked about, which is the argument for
writing the mirror of a test rather than only the case in hand.

Two divergences from Chromium are left in Grid: a spanning item does
not widen the tracks it spans, and a line name the template does not
know leaves the edge automatic rather than making an implicit line.

### A negative margin collapses by CSS2 §8.3.1

Collapsing margins take the **largest positive** and the **most
negative** and add them. This took the maximum, and the larger of 0 and
-40 is 0 -- so a negative `margin-top` did nothing at all, while a
negative `margin-left`, which goes nowhere near the collapsing code,
worked. Four stacked 100px blocks with `-40px` on the second sat at 0,
100, 200, 300 where Chromium puts them at 0, **60**, 160, 260.

Five pairs measured before anything was written, and all five are
`max(positives, 0) + min(negatives, 0)`: +50/+20 gives 50, +50/-20
gives 30, -30/-50 gives -50, 0/-40 gives -40, -40/+10 gives -30. The
same correction goes into the parent-and-child collapse, which took the
same maximum.

**Nothing in the suite moved**, which is worth saying rather than
passing over: a change to how every page's flow collapses its margins
regressed nothing, because not one test had used a negative margin.
That is the same shape as the benchmark pages having no `z-index` and
no `placeholder` -- an engine is only as measured as its fixtures are
varied.

Found by writing a hit-testing fixture that needed two in-flow blocks
to overlap. They did not, and the fixture was measuring nothing.

layout 83 -> 94.

### A click lands on the topmost box

Hit testing returned the **first** child whose rectangle held the point
rather than the topmost, so where two boxes overlapped the one earlier
in document order took the click and the painter put the other on top.
Now that CSS2 §9.9's order exists there is something to walk backwards,
and the descent does: the positioned children at zero and above,
highest `z-index` first and latest first within a z; then this box's
own inline content; then the in-flow children, latest first; then the
negative ones. The out-of-flow fallback added a commit earlier runs the
same way, which is where the second of the two failures showed up --
two absolutely positioned boxes make their parent zero tall, so they
are only reachable through that fallback, and it was scanning document
order.

Five overlapping pairs measured in Chromium first, each pinning one
step against the one below. The fourth is the one worth keeping: a
`z-index: -1` box loses to in-flow content that has
`background: transparent`, so hit testing is about the **box** rather
than the ink in it -- which is the model this engine already had, and
what made the fix a reordering rather than a new question.

The transform and `pointer-events` rules moved into one `hitChild`
shared by the three passes, so they cannot drift apart between them.

**And the test that meant to ask the plainest question was asking
nothing.** Two in-flow blocks overlapped by a negative `margin-top`
would be the simplest case, and they do not overlap here at all: a
negative `margin-top` is dropped, where a negative `margin-left` works.
Four stacked 100px blocks with `-40px` on the second sit at 0, 100,
200, 300 against Chromium's 0, 60, 160, 260. That is its own bug, in
todo.md with the numbers; the case is asked of two positioned boxes at
the same z instead, which is the same loop.

position 65 -> 71.

### An out-of-flow box beyond its ancestors is hit again

`hitTest` descends only into children whose rectangle holds the point,
so a box laid out past every ancestor's box was unreachable. With an
empty body -- height **0** -- an absolutely positioned box at 100,100
was found by nothing; Chromium's `elementFromPoint` finds it, and so
does one beyond a parent ten pixels tall, and a `fixed` one beyond both.

The out-of-flow boxes are collected as `layoutPositioned` passes them,
which is a push on a walk that already happens, and the search falls
back to that list **only once the ordinary descent has returned
nothing** -- so no answer this already gave can change, which is what
keeps a hit-testing change out of the rest of the suite. The fallback
honours `pointer-events: none` and goes through the inverse transform,
so a translated out-of-flow box is hit where it is drawn: the two
features agree rather than each answering on its own.

What it deliberately leaves alone is the older imprecision, now written
down in todo.md: the descent returns the first child whose rectangle
holds the point rather than the topmost.

position 58 -> 65.

### CSS2 §9.9's painting order

A `z-index: -1` child painted above everything here, including the
background of the box it is inside. The standard puts it after that
background and before the box's own content -- and, when the box is not
a stacking context, **behind** that background, because the child
belongs to the nearest ancestor that is one.

That hoisting is the whole of it, and it is what made the previous
entry's third part unshippable: making `transform` a stacking context
changes nothing until there is an order for it to change. Both landed
together.

**What makes a context was measured rather than listed.** A positioned
box with a *declared* `z-index`, a box with a `transform`, and a box
with an `opacity` below 1 all answer identically, and `z-index: auto`
answers as declaring nothing. Since `auto` and `0` both compute to 0
here, the fact that a declaration happened is kept in a side map keyed
by the computed style's serial rather than as a field on `Style`, for
the reason benchmarks.md gives about one `int` on `Style`.

**A document that declares no negative `z-index` does none of the
walk.** `cascadeSawNegativeZ` is raised where the value is computed, and
it guards both the collecting pass and the skip in the ordinary
positioned loop -- which is also what kept a painting-order change from
moving a pixel of the twenty-four render suites.

**It costs three milliseconds of paint on a page that uses it**, which
is measured, attributed, and the cheapest of three implementations
tried. Two attempts to remove it made it worse -- one by seven
milliseconds of layout, one by eighty-eight -- and the second of those
is a Festina finding rather than an engine one: `parentBox` is a
registry read, and a struct read out of a registry is a retained
temporary whose release walks everything reachable from it. A few
hundred of them is a hundred milliseconds. FINDINGS.md 39 and 40, and
benchmarks.md, carry both.

The feature page had no `z-index` on it at all, so the first pairing
could not have seen any of this. It has a negative stack per section
now, and a `--verify` probe that requires turning the order off to move
pixels.

New `stacking` render suite, 10 checks.

### What a transform makes of a box

Two of the three things Transforms 1 §3 asks of a transformed box, and
the measurement decided which two were worth taking.

**It is the containing block for its positioned descendants**, and for
both kinds. The trigger is the computed value rather than the matrix:
Chromium makes a containing block of `rotate(0deg)`, which computes to
`matrix(1, 0, 0, 1, 0, 0)` -- byte for byte what `translateX(0px)`
computes to -- and not of `none`. So the test is `transforms.length`,
because `none` parses to no functions at all and an identity transform
parses to one. A `fixed` box's containing block is carried separately
from an `absolute` one's, since a merely positioned ancestor makes one
for `absolute` alone and the nearest transformed ancestor can be further
out than the nearest positioned one.

**Hit testing goes through the inverse transform.** The painter composes
`translate(origin)`, the functions in the order written, then
`translate(-origin)`, so the point is undone by the same functions
inverted and applied in the opposite order, and the box and its whole
subtree are then searched in that space. A 100x40 box rotated ninety
degrees is hit along the 40x100 shape it is drawn as and missed at the
ends of the rectangle it was laid out as, which is what Chromium's
`elementFromPoint` answers for the same seven points. A zero scale draws
nothing, so the point is sent somewhere the box is not.

**The stacking context is not taken, and that is a judgement rather than
an omission.** The observable difference is where a `z-index: -1` child
paints, and this painter puts every positioned child after the box's own
background and lines -- so a negative child already paints above a
background it should be behind. Making `transform` establish a stacking
context changes nothing until CSS2 §9.9's order is there to change,
because the negative children of a box that is *not* a stacking context
have to be painted by the nearest ancestor that is, which is hoisting
rather than reordering. Shipping the keyword first would be
`outline-style` again. todo.md carries it with what it needs.

**And the work turned up a bug in hit testing that has nothing to do
with transforms.** `hitTest` descends only into children whose rectangle
holds the point, so an out-of-flow box laid out beyond its parent's box
is unreachable -- an absolutely positioned box at 100,100 inside a body
of zero height is found by neither. Chromium finds it. Recorded rather
than fixed here, because the fix is for the descent to use a box's ink
extent rather than its laid-out one and that wants its own measurement.

position 34 -> 58.

### `::placeholder`

The placeholder attribute was already laid out as the control's text.
What this adds is the pseudo-element that styles it, and the measurement
is what made it a small change rather than a special case.

**The grey is a declaration, not a fallback.** Chromium computes
`rgb(117, 117, 117)` on `::placeholder`, and `color` on the input does
not reach it -- which is not a rule about placeholders at all. The grey
is declared in the user agent's stylesheet *on the pseudo-element*, and
an inherited value loses to any declaration whatever origin it comes
from. So one line in `ua.f` reproduces both answers and nothing had to
be written to make the colour win. A `value` is not a placeholder and
still takes the input's colour, which is the check that says the grey
belongs to the pseudo-element rather than to every text box a control
makes.

**It is computed on demand, from layout.** Every other pseudo-element
here is computed in the style pass, because every other one applies to
elements a document has many of. This one applies to an `<input>` that
is showing its placeholder, and layout is the only code that knows which
those are -- so `placeholderStyleFor` is called from the one place that
builds a control's text box, and a document with no such input never
calls it.

`formControlText` says which of the two it returned through a global,
because two answers out of one function need one (FINDINGS.md), and
asking a second predicate the same question would be the same walk
written twice.

Chromium ignores `display` on it and this does too, for the plain reason
that the placeholder's style is used for the text and nothing else.

**And it cost two milliseconds of layout until it went through the
sharing cache.** Neither benchmark page had a `placeholder` on it, so
the first pairing could not have seen the feature at all;
`tests/featurepage.py` gained one per section and a `--verify` probe
that requires it to move pixels. On that page the twenty placeholders
each built their own `Style`, and a third binary attributed two thirds
of the cost to exactly that. `placeholderStyleFor` now goes through
`styleCache`, which has shared a computed style between
identically-matched elements since the table-cell entry, and the key
gains the pseudo-element's name so an entry made for
`input::placeholder` can never be handed to an `input`. Cached against
uncached reads -2 ms of layout forward and +2 reversed, slower in 24 of
25 pairs -- the strongest reading this method has produced.

forms 17 -> 26 and render 54 -> 60.

### The side a page break asks for

CSS 2 §13.3.1 says `left` and `right` force **one or two** page breaks,
whichever it takes for the next page to be formatted as a page of that
side. The second one is a page with nothing on it. All four keywords --
`left`, `right`, `recto` and `verso` -- were read as a plain `page`
break here, and now ask for their side.

**Chromium does not do this**, which the measurement settled before any
code was written. Giving `@page :left` and `@page :right` different
`size` declarations makes each printed page say which side rule
formatted it, and the sizes come out of the PDF catalogue with no
content-stream arithmetic. Chromium honours the two selectors and starts
on a right page -- so the parity this engine already assumed is the
browser's too -- but `break-before: right` puts its content on the left
page that follows, and two of them in a row print three pages where the
standard asks for five. The CSS2 spelling behaves the same way, so it is
not a question of which syntax is recognised. The standard is
unambiguous, so this follows the standard and writes the browser's
answer down beside it, as Motion Path's ray sizing already does.

**`@page :blank` now has something to select.** It was parsed and could
never match, because nothing generated a page with nothing on it. The
page this generates is the only such page, so the rule and the page
arrive together.

**The side is read back off the boxes rather than carried on the unit.**
A `ColumnUnit` is built for every line of every multi-column container
on screen, and an `int` there would cost every one of those pages a
struct they never read -- which is exactly what one `int` on `Style` was
measured to cost. `pageSideAt` asks the box at the break, and then the
previous sibling's `break-after`, skipping the same siblings the unit
collector skips. It runs once per break of a print.

What the unit collector pays is one comparison becoming two:
`break-before` ends a page when it is `BRK_PAGE` or above, and the two
side values sit above it so the range test's first comparison rejects
the `auto` almost every box carries.

paged 125 -> 128 and paged render 90 -> 106.

### `print-color-adjust`

269 -> 270 properties. css-2026.md said a PDF read makes the property
measurable. It does, but the first probe could not see it: **`--print-to-pdf` prints background graphics
unconditionally**, so `economy` and `exact` give byte-identical fills and
three runs agreeing meant only that the instrument could not tell the two
answers apart.

What separates them is `Page.printToPDF`'s `printBackground`, which the
CLI does not expose, so the probe is a CDP client written for it -- a
socket, the WebSocket handshake and its framing, standard library only,
no dependency. With backgrounds omitted, an undeclared box and an
`economy` box lose theirs and an `exact` box keeps it.

**So the property overrides an omission rather than causing one**, and
that decides the whole implementation. `economy` grants a permission the
user agent may not be using and is indistinguishable from not declaring
the property; `exact` withdraws it. A renderer that always prints
backgrounds cannot tell them apart, which is what this engine was, so
storing the keyword alone would have been `outline-style` again -- a
property the instrument scores while the engine does nothing with it.

`--no-background-graphics` is the omission, named after the print
dialog's own setting. It is **off by default**, because a `--print` that
silently stopped printing backgrounds would be a behaviour change nothing
asked for; under it a box's background is drawn only where the computed
`print-color-adjust` is `exact`.

**It inherits**, which was measured rather than read off the
specification: `exact` on a parent reaches an undeclared child, and the
child takes it back with `economy`. Both are in the suite.

The gate is one boolean on the ordinary path -- `printsBackground`
returns true without reading the property whenever the render is not
omitting anything, which is every render but this one.

Twelve checks, written before the code and watched failing: five of them
failed for the right reason and the other seven passed, because with
nothing omitted `economy` and `exact` agree and cannot fail. That
agreement is asserted too, since it is the measurement.

### The `@page` margin boxes

All sixteen. `@top-center` and its fifteen siblings were parsed out of
the `@page` body and dropped, on the recorded reasoning that each is a
box generated from `content` in a place the layout engine has no notion
of -- and on the assumption that no browser reached them. Chromium 141
lays all sixteen down, which the measurement commit ahead of this one
read out of its print.

**Reading a print needs no new dependency.** `--print-to-pdf` writes
Flate streams and `zlib` is in Python's standard library, so a probe
inflates the content stream, reads the `Tm`/`Td`/`Tj` operators and maps
the glyph ids back through the standard glyph order. That gives every
string Chromium drew and where its baseline is, in CSS pixels, which is
what turned the sixteen boxes into a table of numbers rather than an
opinion. It also disproves a note this project had been carrying: that
`print-color-adjust` was unmeasurable here. todo.md now says the
opposite, and that the property is worth doing.

**What the numbers said is the standard's own table.** Each box on the
top and bottom edges is vertically centred in its band; the three down
each side are top-, middle- and bottom-aligned in the region between the
corners; and a corner aligns *inward*, toward the page content -- a
`@top-left-corner` is right-aligned. That is CSS Paged Media 3 §5.2's
default `text-align` and `vertical-align` per box, which is worth
saying, because it means the standard could be implemented rather than
the browser copied.

**A margin box inherits from the root element, not from `body`**, which
is what the page context is. The decisive pair in the measurement was a
monospace `font` on `html` reaching the box and the same on `body` not.
`color` and `font-size` on the box itself win over what it inherits.

**Each box is an `@page` rule of its own.** The parser splits a nested
block out of the `@page` body at the last semicolon before its brace and
registers one extra rule per selector and slot, so the boxes cascade by
the same page-selector specificity the page box already uses: a `@page
:first` rule's `@top-center` replaces the general one on the first sheet
and leaves it in force on the rest. Nothing walks for them on a page
that declares none -- `anyPageMarginBox` is raised while the sheet is
read and the painter asks it once per page.

`content` takes strings, `counter(page)` and `counter(pages)`,
concatenated in the order written; `content: none` and an empty box draw
nothing.

The render suite grew 45 checks, to 78. They are ink-bounds checks
rather than glyph checks -- which band the ink is in and where in that
band -- because what a margin box has to get right is its place, and ink
bounds say that without pinning a font's advances. Two of them are
colour checks, and they draw at 30px: at 16px no pixel of a stem is
fully opaque, so a check for the colour itself could not have passed
however right the colour was.

### CSS Ruby Annotation Layout 1

267 -> 269 properties, and a specification off zero. Almost everything
it needs was already here -- the tree builder handles `<rt>` and
`<rp>`, the user-agent stylesheet said `ruby { display: ruby }`, and
the element instrument already agreed with Chromium that `rt` is
`inline` and `rp` is `none`. What was missing was the layout, and
`display: ruby` fell through to the block branch, so **a `<ruby>` was
a block box and broke the line it was on in two**.

**A ruby is an atomic inline made of two anonymous bands**, the
annotation and the base. Building it that way is the whole trick: each
band goes through the ordinary inline layout, the ruby itself goes
through the ordinary atomic-inline path, and nothing in either of them
knows about ruby. The bands are built annotation-first whatever
`ruby-position` says -- where they are *placed* is the layout's
business, which keeps the property out of the box tree.

**The band takes its metrics from the `<rt>`, not from the ruby.** A
band is a block and a block's line has a strut, so a band built from
the ruby's own style would be a full base line tall however small the
annotation is. The user-agent stylesheet gives `rt` half the font size
and its own `line-height: normal` -- which is HTML's Rendering section
-- and the band inherits exactly that, so it is the height of the
annotation's text.

**`ruby-align` is the bands' text alignment.** A band is a block as
wide as the ruby, so placing the narrower one against the wider is
what `text-align` already does. Chromium distinguishes `start` and
nothing else: rasterised, a four-character annotation over a
sixteen-character base sits at columns 0-19 under `start` and at 67-86
under `center`, `space-between` **and** `space-around`, which are
pixel-identical. So all three centre here, and the suite asserts that
by agreement rather than by three numbers.

That last one is why the measurement was rasterised rather than read
off `getBoundingClientRect`: the `<rt>` box is stretched to the ruby's
width under every value, so the box metrics say the four values agree
and the pixels say two of them do not.

**Where it differs, measured.** The band is a full annotation line
tall where Chromium overlaps it two pixels into the base's ascent, so
a ruby line is 30 pixels here against Chromium's 27. The base does not
break across lines, because the ruby is atomic. `alternate` and
`inter-character` are kept apart in the computed style and behave as
`over`.

It measured **free** on a page with no ruby in it. What it adds there
is one comparison in `isInlineLevelBox`, which every child of every
block is asked about: the forward pairing read layout at -1 and the
reversed at +1, which add to zero -- a difference of nothing, once the
order effect the entry before this one names is separated out.

31 checks in `tests/unit/test_ruby.f`.

### `text-wrap-style`

266 -> 267 properties. `balance` breaks a paragraph of six lines or
fewer so that its lines come out as even as the greedy breaker can
make them, **without changing the line count or the block's height** --
which is the first thing the suite asserts, against `auto` rather than
against numbers, so it holds whatever this engine's advances are.

**It is a search over the width, not a second line breaker.** CSS Text
4 §6.2 leaves the algorithm to the user agent and asks only that the
difference between the longest and the shortest line be minimised, so
balancing here is: lay the inline content out again at narrower and
narrower measures, and keep the narrowest one that still breaks into
the same number of lines. Narrowing can only add lines and never
remove one, so the widths that give the same count are exactly those
at or above a threshold -- which is what makes it a binary search
rather than a scan, and what bounds it at nine or ten passes over one
paragraph. The block keeps its own width; only the lines inside it get
shorter.

On a two-line paragraph that lands on Chromium's answer:
`mmm mmm mmm mmm mmm mm mm` in 200px is 190 + 50 greedily and 110 +
130 balanced here, against Chromium's 183 + 48 and 106 + 125 -- the
ratio between them being the whole-pixel advance this engine rounds to
where Chromium's monospace is 9.633.

**Where it is weaker, and why, measured rather than assumed.** On a
paragraph of equal words the narrowest measure that still gives six
lines is the one the greedy break already used, so the search runs,
finds nothing better, and changes nothing; Chromium redistributes the
words between the lines there, 183 ×5 + 48 becoming 183, 183, 145,
145, 145, 164, which no width can produce. And Chromium's `balance`
carries a **widow rule that outranks balancing**: it refuses a
one-word last line even where avoiding it makes the widest line wider,
turning 106 + 116 into 67 + 154. That rule is what `pretty` is made of
rather than part of balancing, so it is not implemented and `pretty`
breaks as `auto` does. Both disagreements are in todo.md with the
tables they were read from.

**The threshold is six lines**, which is where Chromium stops too. A
one-line paragraph and a seven-line one never run the search at all,
and the suite asserts that by reading the *measure* the breaker was
given rather than the break it produced -- the two answer different
questions, and separating them is what let the six-line row say
"balancing ran and found nothing" rather than "balancing did not run".

The property **inherits**, which no other side-mapped value in this
engine does, so the applier reads the parent's value out of the same
map before it looks at the element's own declaration. The `text-wrap`
shorthand sets it, in either order and with either half alone.

And inline content holding a **float** is left alone: a float is
registered with its formatting context as it is placed, so a second
pass would place it twice. The suite says so rather than the comment
alone.

It measured **free** on both benchmark pages -- and the run is in
benchmarks.md for what it took to say so. Two forward rounds read a
paired median of +1 ms of layout, which this project's own rule calls
real; the **reversed** pairing read +1 to +2 the other way, which says
both numbers were the order rather than the code. A reading and its
mirror image that are both positive are measuring which binary ran
second. CLAUDE.md has the rule now.

52 checks in `tests/unit/test_textwrap.f`.

### `resize`

265 -> 266 properties, and the last of Basic User Interface 3 this
engine can reach. The property **reserves no space and changes no
geometry** -- fourteen declarations measured in Chromium, and the only
row whose client box moves is `overflow: scroll`, which moves the same
way with no `resize` on it at all. Its computed value is the declared
keyword under every `overflow`, `visible` included. So neither geometry
nor `getComputedStyle` can tell whether it is doing anything, and the
painter is the only instrument that can see it.

**What there is to see is the grabber.** Two diagonal hairlines in
`#666666`, at `x + y` = corner - 8 and corner - 4, inside a seven by
seven square inset one pixel from the bottom-right corner of the
*padding* box. Every number there was read off a rasterised corner
rather than derived: the same reading with a five pixel border puts the
lines at the same offsets from the padding box's corner, which is how
the measurement tells the padding box from the border box.

**The keyword constrains the drag, not the drawing.** `horizontal`,
`vertical`, `block` and `inline` all paint the grabber `both` paints,
which the suite asserts by agreement rather than by pixels of their
own -- each is checked against `both`'s signature, so all five can only
pass together. What the keyword cannot do alone is make the grabber
appear: it shows only where `overflow` is neither `visible` nor `clip`,
though the computed `resize` is still `both` either way. That is the
one place the painting and `getComputedStyle` disagree, in Chromium as
here, and the `clip` half of it is measured rather than read off the
specification, which names only `visible`.

**A drag reaches layout as a declaration.** A computed `Style` is
shared between elements that matched the same rules and is never
written to after it is computed, so a used size belonging to one
element cannot be a field somebody sets on it: it has to change what
that element *matched*. The dragged size is added to that element's
matches as an important inline `width` and `height` -- the weight a
user's own drag deserves, beating anything the page wrote -- and the
document is styled and laid out again. Everything that depends on the
new size follows from that one pass rather than from a second rule
about dragging, and the box's lines, its descendants and the boxes
after it all move because a declared length moved. What follows the
pointer is the **border** box whatever the element's `box-sizing`
says, since that is the rectangle whose corner was taken hold of, so
`box-sizing: border-box` is declared beside it.

The painter draws the grabber from the same three functions the
pointer is tested against, which is what the scroll thumb already
does: what it looks like and what can be taken hold of are one square
rather than two formulas that agree.

**And the benchmark found a cost that was mostly not this change's.**
The flag `resize` needed -- one scan of a rule's
declarations for the word, so that a page without it pays nothing --
read a paired median of **+1 ms of cascade on both benchmark pages,
across two rounds**, against a floor of 0. The scan was the eighth of
nine such loops, and all nine sat *inside the loop over the rule's
selectors*: a rule with five selectors read its declarations
forty-five times over, and every flag that stayed false read all of
them. They are one pass now, once per rule, and the same two rounds on
both pages read the cascade at or below its floor -- so the cost this
change was about to add is gone and eight loops went with it.

51 checks in `tests/render/resize.f`.

### `zoom`

264 -> 265 properties. Every length zooms exactly once: a declared
`100px` is 200 device pixels at `zoom: 2`, and so are the paddings,
the borders, the margins and the height. `em`, `rem` and `vw` resolve
against the *unzoomed* font size, root font size and viewport and then
zoom. A **percentage needs nothing**, because the containing block it
resolves against is already in device pixels -- which is also why an
`auto` width still fills its containing block and only the height
changes. It compounds down the tree, and zero, a negative and
`normal` all leave it alone.

**One multiply in `lenPx` is the whole of it for lengths**, because
every relative unit has already become pixels by the time it gets
there. That is worth more than the line count suggests: there is no
list of properties to keep in sync, so a length added to the engine
tomorrow zooms without anyone remembering to make it.

**The font could not join them.** A child's `em` resolves against its
parent's computed `fontSize`, so zooming that would zoom the child's
`em` twice -- and Chromium keeps the computed font size unzoomed for
exactly this reason, reporting `16px` under `zoom: 2`. The zoom is
applied where the font is chosen instead, in `setFontFor`, and folded
into the `fontKey` so the width cache cannot serve one zoom's advance
at another. That is the drop cap's stale-key bug in a different coat,
avoided rather than repeated.

**And an inherited length arrives carrying the parent's zoom.** Every
declared length is scaled as `lenPx` builds it, but an inherited one
is copied rather than parsed, so it needs the ratio between the two
zooms. The inherited properties that carry a length are few and all of
them are handled: `line-height`, `letter-spacing`, `word-spacing`,
`text-indent` and `tab-size`. `border-spacing` would belong with them
and does not inherit in this engine at all, which is its own gap.

Two checks earn their place without a number. A zoom of two on a box
is the same box as every length doubled -- which holds for the width,
the padding and the border at once. And a zoom of two is the same ink
as twice the font size. Twice the *width* is not, and cannot be: this
engine rounds a glyph's advance to whole pixels, so ten of them are
100 at 16px and 190 at 32px where Chromium's 96.33 and 192.66 are
exactly double.

### `attr()` was implemented, untested, and documented as missing

css-2026.md's Values and Units 3 row said "`attr()` is missing". It
has worked in `content` since generated content landed, and `content`
is the only place Values 3 allows it -- the typed form that reaches
other properties belongs to Values 5. Nothing in the suite asked,
which is why a claim about the engine could sit in a file that says it
is read from the code.

Five checks pin it: the attribute's value is generated, a missing
attribute generates the empty string rather than dropping the
declaration, it sits among the strings beside it in the order written,
the attribute's name folds while its value does not, and -- the one
that needs no number -- an attribute holding exactly what a string
would have said generates what that string generates.

### A flex container's text becomes an anonymous item, and its baseline its first item's

Two halves of one bug, found by writing `baseline-source`'s fixture.

**Flexbox 1 §4: each contiguous run of a flex container's text is
wrapped in an anonymous block flex item.** Without it a text box is an
item with no layout and no height, so a container holding nothing but
text collapsed to nothing -- which `display: inline-flex` made
visible, at zero height where Chromium gives 40.

The run is text and forced breaks and nothing else, which is narrower
than the wrapping a block container does: every other element child is
an item in its own right, so `A<span>B</span>C` is **three** items and
`A<img>B` is three. A `<br>` does *not* break a run -- `A<br>B` is one
item forty pixels tall, not three items of twenty, nineteen and twenty
-- because a forced line break belongs to the inline content around it
rather than being a box the flex algorithm can place. Both are
measured against a `flex-direction: column` container, which counts
the items by stacking them.

**And an anonymous box's margins were `auto`.** A `Style` built fresh
has every `Len` at kind 0, which is `auto`, and the initial value of
`margin` is zero. On a block container the two are indistinguishable,
because an auto margin beside an auto width resolves to nothing; in a
flex container auto margins absorb the free space, so the first
anonymous item centred itself and pushed the next item to the far
edge -- 155 pixels either side of a 30-pixel text item in a 400-pixel
row.

Zeroing them for *every* anonymous box cost **two milliseconds** on
`generated.html`, which is a page of headings and paragraphs and
tables and therefore a page of anonymous boxes: four `Len` writes
each, a paired median of +1 in both cascade and layout across two
rounds. A third binary with the four writes taken back out read on the
floor, which attributed it exactly. Only a flex item can tell an auto
margin from a zero one, so only a flex item pays for one now, and the
cost measures away.

**Flexible Box 1 §8.5: a flex container's baseline is its first item's
first baseline**, where this engine synthesised one from the bottom
edge. That is the opposite default from an inline-block, whose
baseline is its *last* line, and it is why `baseline-source: auto`
means different things on the two. A container's last baseline is its
last item's last, so only the first needs asking for: an item's own
baseline is already its last line.

### `baseline-source`

CSS Inline 3 §5.1: which of an atomic inline's baselines the line it
sits on aligns to. `first` and `last` work on a box that has its own
line boxes, which is what an inline-block is; CSS2 §10.8.1 already
said the default there is the *last* line, and that is what this
engine already did, so `first` is the whole of the new behaviour and
it is one index at the end of the inline layout.

**What the declaration moves is the sibling, not the declaring
element.** The inline-block keeps its top and its height under every
value; the line it sits on realigns around it, and the span beside it
moves by exactly one line height. The suite asserts that distance
rather than either position, which holds whatever the line height is.

`auto` on a flex container is the **opposite** default -- its first
item's first baseline rather than its last line -- so the two display
types disagree about what `auto` means, which the suite asserts
directly.

That half was not implementable when this landed, and finding out why
is what led to the next entry: a `display: inline-flex` span holding
two lines of text laid out at **zero height** here where Chromium
gives 40, and Chromium's answer for the sibling there is 0, which this
engine also answered -- from a box that contributed nothing to the
line rather than from a first-line baseline. The inline-flex rows were
left out of the suite until that was fixed, rather than left in
agreeing by accident.

Two Festina notes came out of writing the instrument. **A laid-out
inline's position is on the fragment the line holds, not on the box**:
the span's own box and the text box beneath it are both zero tall at
zero, so the first instrument answered 0 for all seven rows. And **two
struct references do not compare with `==`** -- the LLVM backend
rejects it with "defined with type 'ptr' but expected 'i64'" -- so a
fragment is matched to its box by the box's id.

### `font-size-adjust`

The used font size is the specified one times `<number> / aspect`,
where the aspect is the named metric as a fraction of the em, so text
set in two families comes out the same visual size. All five metrics
are taken -- `ex-height`, which a bare number means, `cap-height`,
`ch-width`, `ic-width` and `ic-height` -- and `from-font` asks for the
font's own aspect, which by definition leaves the size where it is.

**It changes the font actually used and nothing else**, which is three
separate measurements. `font-size` still computes to the specified
value. An `em` beside the declaration resolves against *that*, so
`width: 2em` under an adjust of 1 is 32px and not 57. And a
`line-height: normal` follows the *used* size, growing a 19px line box
to 33. So the adjustment is applied at the very end of the cascade,
after every length has resolved its `em` -- and the line height
follows for free, because `normal` is stored as zero and worked out
from the font size when it is read.

The aspects come from the constants the `ex`, `ch` and `cap` units
read, which is one ratio per metric where Chromium's are the hinted
metrics and move with the size. The divergence is known rather than
discovered: 2.8% at 16px, and 14% at 8px, where Chromium's x-height
has moved from 9/16 of the em to 5/8.

**The aliasing bug this branch already records happened again, and
valgrind caught it again.** `ascii amount = words[at]` binds an element
of a split to a local, which is released at scope exit without ever
having been retained; the 25 checks passed natively and the same suite
failed under valgrind with an invalid read of size 8 in
`festina_ascii_release`. The words are indexed in place now, as the
engine's twenty other callers of `asciiSplitSpace` already do.

### `ex`, `ch` and `cap` are measured rather than approximated

The three were half an em, half an em and three quarters of one,
because the runtime reports no x-height, no zero advance and no cap
height. Chromium 141 on the same monospace face, `width: 10<unit>` at
16, 20, 48, 100 and 180px, least squares: `ex` is `0.5473 x size`,
`ch` is `0.6020 x size` with an intercept of zero, and `cap` is
`0.7310 x size`. So `ch` was 17% low, `ex` 9% low and `cap` 2.6% high
-- 35 pixels of a `10cap` at 180.

**Each is read twice.** `ch`: this engine's own face measures a `0` at
12px at 20, 60 at 100 and 108 at 180, which is exactly 0.6 of the size
-- the face is monospaced, so every glyph has that advance -- and
Chromium agrees to a third of a percent. `ex`: 0.5473 sits inside the
0.542 to 0.550 that rasterised ink gave when `FONT_CAP` was corrected.
`cap`: the two Chromium surfaces measure the same quantity, and
`0.733 x size - 0.41` from `text-box-edge` and `0.7310 x size - 0.144`
from the unit are within a tenth of a pixel of each other across the
whole range.

So `cap` takes `FONT_CAP` and `ex` takes `FONT_EX`, the constants
`text-box-edge` already reads, rather than carrying numbers of their
own: one cap height and one x-height, because two constants for one
quantity is how a number goes stale in one place and not the other.
`FONT_EX` is sharpened from 0.55 to 0.547 by this second reading.
`ic` needed nothing -- Chromium measures it at exactly an em, at every
size.

**`10cap` was pinned at 120 at 16px, which is Chromium's answer at
16px and nowhere else.** That is the same trap `FONT_CAP` fell into,
in the same file, and it is why the three quarters survived: a ratio
read off a single font size is a ratio plus a rounding error of up to
a pixel. The checks now read five sizes, and the one that needs no
number asserts each unit is linear in the font size -- ten of it at
18px is one of it at 180px -- which is exactly how these answers
differ from Chromium's, whose metrics are hinted per size.

### `min()`, `max()` and `clamp()`

CSS Values and Units 4 §10, wherever this engine reads a length --
which is every property that takes one, and inside `calc()`.

**An argument list of nothing but pixels is folded at parse time**, and
that is the point rather than an optimisation: a folded comparison is
an ordinary pixel length, so `min(10px, 20px)` works everywhere `10px`
works, including the places that take a length by kind rather than
through `resolveLen` and already refuse a `calc()`.

**A percentage cannot fold, because the comparison happens after the
percentage is resolved.** `min(50%, 100px)` is 100 against a 400px base
and 50 against a 100px one, so the operands are kept in a side table
and the answer is worked out in `resolveLen`, where the base finally
is. A side table rather than fields on `Len`, because `Style` holds
some thirty of them and this project has twice measured what a field
costs the pages that never read it. An unfolded comparison reaches
every property that goes through `resolveLen`, and is refused by the
ones that read a length's kind directly -- which is exactly where
`calc(100% - 2em)` is refused today.

Four of the rules are Chromium's rather than the grammar's.
`clamp()`'s minimum wins over its maximum, so `clamp(200px, 100px,
50px)` is 200. A bare number is not a length there and zero is not
exempt, where `calc()` takes one as a multiplier. `min()` and `max()`
take a single argument and `clamp()` takes exactly three. A trailing
comma is invalid.

Nesting works in both directions, and a comparison nested inside one is
one more operand rather than a case of its own. A comparison whose
answer is *deferred* inside a `calc()` is refused rather than
approximated: a `calc()`'s running value is a pixel part and a
percentage part, and a deferred comparison is neither until the base is
known.

The suite caught the implementation answering the wrong function: every
`min()` inside a `calc()` came out as the maximum, because the code
that chose between them read the name's first letter, which `min` and
`max` share. The two answers now come from the one test that
recognises the name.

### `anchor()` composes inside `calc()`, completing Anchor Positioning 1

The other function resolves to a length too, so the same substitution
works -- but what it resolves to is not a length until the *containing
block* is known. `anchor(--a right)` in a `left` is the anchor's right
edge measured from the containing block's left, and in a `right` it is
measured back from its right, which is what makes `right: anchor(--a
left)` hang the box off the anchor's left. So the expression is
resolved in the positioning pass, where the containing block already
is, rather than in the walk that collects the anchors' rectangles.

That walk still does the half only it can do. An expression may name
several anchors -- `calc(anchor(--a left) + anchor-size(--a width))`
names two -- and each resolves against the anchors the tree-order walk
has passed at the moment it is reached. So the walk records one
rectangle per *occurrence*, and one function numbers the occurrences
for both passes, so neither has to agree with the other about anything
else.

The failure is the one `anchor()` shows outside an expression rather
than the one `anchor-size()` shows inside it: a fallback is taken
before the arithmetic, so `calc(anchor(--missing right, 7px) + 1px)` is
8, and with no fallback the whole declaration has no effect, leaving
the box at its static position. `anchor-size()` zeroes its declaration
in the same case, and the two keep that difference inside an expression
as outside one.

A percentage beside the function is the containing block's on the
inset's own axis, and goes through `resolveLen`, which is what every
written-out inset resolves one against -- so the two land on the same
pixel by construction rather than by agreeing about a convention.

`min()`, `max()` and `clamp()` take both functions in Chromium and
neither goes inside one here. The three work over ordinary lengths;
an anchor function is not one, because it is substituted into an
expression's text before the ordinary parser sees it, and the length
parser is what knows `min(`. That is recorded in todo.md.

### `anchor-size()` composes inside `calc()`

The standard says the function resolves to a length, and that is taken
literally: the length is substituted into the expression and the
ordinary length parser is run over the result. `calc()`'s arithmetic,
precedence and nesting therefore come from the parser that already has
them rather than being written a second time -- `calc(anchor-size(--a
height) * 2 - 20px)` is 100 because that parser knows the product binds
before the difference, not because anything here was taught to.

A percentage survives the substitution as the `Len`'s own percentage
part, because the containing block is not known where the anchors'
rectangles are. It is resolved at the property's own read site against
the base a percentage there would have used: the containing block's
width for a width or any of the four margins, its height for a height.

The bare form keeps its own path rather than going through the
expression one -- it needs no arithmetic and no second parse -- so the
suite asserts the two agree: `calc(anchor-size(--a width))` must give
the box `anchor-size(--a width)` gives.

Each failure carries into the expression unchanged. A fallback is taken
before the arithmetic, so `calc(anchor-size(--missing width, 5px) +
1px)` is 6; with no fallback the whole declaration is zero rather than
the term being dropped, so `calc(anchor-size(--missing width) + 1px)`
is 0 and not 1.

`anchor()` inside an expression is not implemented. It resolves against
the containing block rather than against the anchor alone, and the
containing block is known in the positioning pass rather than where the
rectangles are collected. `min()` and `max()` take both functions in
Chromium and are not a gap in anchors here: this engine implements
neither for any value at all.

### `anchor-size()`, on a second layout pass

`anchor-size(<name>? <dimension>, <fallback>?)` gives an absolutely
positioned box the anchor's own border-box size, in `width`, `height`
and their minima and maxima.

**It needs a second layout pass, and that is the whole difficulty.**
`anchor()` in an inset is resolved after the tree is laid out, in the
same pass as `position-area`, because moving a box that is already laid
out is a shift. A size cannot wait like that: the box has to be laid
out at that size in the first place, and the anchor has no rectangle
until the layout it is measured from has finished. So one layout
records what each `anchor-size()` came to and the next reads it, and a
pass that changes no resolved size is the fixed point -- the sizes come
off the anchors' own boxes, and an anchor that did not move gives the
same answer again.

**What is carried between the passes is keyed by node id.**
`layoutDocumentOnce` rebuilds the box tree and restarts `nextBoxId`, so
a box id carried across a pass names a different box or none.

Three things the measurement gave that the name does not. The dimension
is the *anchor's* rather than the property's, so `width:
anchor-size(--a height)` is the anchor's height. With no fallback and
no anchor the answer is **zero** rather than no effect, which is the
opposite of `anchor()` in an inset, where the same case leaves the box
at its static position. And the logical dimensions are the physical
ones here, as the side keywords are.

**The four margins and the four insets take it too**, which `anchor()`
does not: `margin-left: anchor(--a right)` does nothing while
`margin-left: anchor-size(--a width)` moves the box by 100. They need
no second pass of their own -- a margin or an inset is resolved once the
anchor's rectangle is known -- but they read the same carry, so they are
slots on the same list of fourteen. What the function resolves to is
put in the property as if the length had been written out, and takes
the precedence a written-out one would: the start side before the end
side.

Two refusals came with the measurement. `padding-*` does not take it,
here as in Chromium, so a `padding-left: anchor-size(--a width)` leaves
the box 40 wide where it was. And `margin-right` and `margin-bottom`
move nothing on their own -- which is ordinary CSS rather than anything
to do with anchors, an end-side margin having nothing to push against
while its inset is `auto` -- and both work the moment that inset is
given a value.

Neither function composes inside `calc()`, which is the last of this
specification left.

**Three things keep the fourteen properties off the pages that do not
use them.** `cascadeSawAnchorSize` is raised once per document, by the
stylesheet walk and by the inline-style path both -- the anchor suite
writes its declarations in `style` attributes and said at once when only
the first was there. Behind it, the fourteen property lookups do not
run, and the slots an element gets are shared do-nothing arrays rather
than three fresh fourteen-slot ones. And the margin lookups live in
`applyAnchorSizeMargins` rather than inline in `resolveEdges`, which
runs for every box of every page.

None of the three is claimed to have fixed the two milliseconds of
layout that `generated.html` still shows, because measuring each
against the binary before it found no difference. benchmarks.md records
that, the per-phase pairing that located it in layout, and the floor
taken either side of the comparison.

### The property instrument grades a pseudo-element

A property whose whole effect is on `::first-letter` could not register
however complete it was: the instrument set each row's declaration on an
element and digested that element's computed style, and nothing
`initial-letter` does reaches the element. It sat in `supportsExempt`,
which silenced the `@supports` cross-check without making it
measurable -- an instrument that cannot fail, kept quiet rather than
fixed.

A row may now name a pseudo-element in a fourth column. The declaration
then goes into a `#t::<pseudo>` rule rather than a style attribute, and
the digest is taken from `pseudoStyleOf` with the pseudo-element's
`content` appended, because `content` lives outside `Style` here. The
row carries a context declaration beside the property, because a
pseudo-element with no declarations at all is not generated and there
would be nothing to compare against; a row whose pseudo-element does not
compute is reported as an instrument fault rather than read as a missing
property.

**`tests/chromium.py properties-audit` asks the same question**, through
`getComputedStyle`'s second argument. Two instruments asking different
questions of the same row can disagree without either one saying so, and
the audit still fails the row if Chromium cannot tell the value from the
initial one on the pseudo-element -- checked by putting `normal` in the
row and watching it fail.

`initial-letter` is what this moves into the count, at 262 of 405, and
`--fields` says it moved `initialLetterPacked` rather than a neighbour's
field: the digest gained that field so the reading would be unambiguous.

**`content` was never in that bucket**, which putting it there turned up.
It already registered through `contentUrl` on the element's own style,
because this engine implements `content: url()` on an ordinary element;
grading it on `::before` instead *lost* a property, since a `::before`
with no content generates no pseudo-element to compare against. Its row
is unchanged and `supportsExempt` is now empty.

### `FONT_CAP` is 0.733, and the cap height is floored

The engine models a font as four ratios per em, and one of them was
wrong by five per cent. `FONT_CAP` was 0.70; the cap height is about
0.733 of the em.

**It survived because it had only ever been read at one size.** A ratio
taken off a single font size is a ratio plus a rounding error of up to a
pixel -- 5% at 20px, 0.5% at 180 -- and 20px is where it was taken.
Measured across a range instead, two independent probes agree:
rasterising an `H` through this engine gives a least-squares
`0.7367 x size - 0.40` over 48 to 180 pixels, and asking Chromium for
the height of a `text-box-edge: cap alphabetic` box on the same family
gives `0.733 x size - 0.41`.

**The intercept is the other half of it.** 0.733 x 20 is 14.66 and
Chromium answers 14, so the cap height is the floor of the ratio rather
than the nearest integer; `capHeight` floors. That is why 0.70 rounded
looked right at 20px, and it was six pixels short at 180.

Nothing else moves. `text-box-edge: cap` answers 14 at 20px as it did.
The drop cap's font size is found by inverting the ratio, so its letters
at sizes 3 and 4 are now 61 and 86 pixels wide, which is Chromium's
answer exactly, against the 64 and 90 the old constant gave. At size 2
it is 37 against Chromium's 36: the font size lands at 60.93 where
Chromium's lands at 60, so the 0.6-em advance rounds up rather than
down. One pixel is the floor of what this measurement resolves --
Chromium's own three widths imply ratios of 0.750, 0.7347 and 0.7297,
which is one ratio seen through three roundings -- and a ratio that
pulled size 2 to 36 would put size 4 at 85.

The other three ratios were measured the same way and stand: ascent
0.921 to 0.938 against the constant's 0.93, descent 0.233 to 0.240
against 0.24, x-height 0.542 to 0.550 against 0.55.

### `initial-letter`, a drop cap on ::first-letter

`initial-letter: <size> <sink>?` on `::first-letter` makes a drop cap,
and the geometry is simpler than the property's reputation. The size is
where the letter's baseline sits: its cap top is the cap top of the
block's first line and its baseline is the baseline of line `size`, so
its cap height grows by exactly one line-height for each line it spans.
Setting the pseudo-element's own `font-size` to
`(cap + (size - 1) x line-height) / cap-ratio` and its `line-height` to
`size x line-height` puts it there, because an inline is centred in its
line box by half-leading and the half-leading is negative here.

**The sink is a separate number and it is not the size.** It defaults
to `floor(size)` and it alone says how many lines are shortened:
`initial-letter: 2 1` and `3 1` each indent exactly one. What is left
over goes above the text -- the block grows by `size - sink` lines and
its text begins that many lines down -- so the letter is placed where
the text starts, lifted back by the difference, and the rectangle it
excludes text with is cut to the sink. Five rows of Chromium's
measurement fit that and nothing else: a five-line paragraph is 150
tall at `2` and `3`, 180 at `2 1` and 210 at `3 1` and `4 2`.

**The letter is a floating atomic inline.** CSS2 §9.7 makes a float
block-level, and a `BOX_BLOCK` here makes the paragraph wrap the rest of
its text in an anonymous box, which puts the float outside the
formatting context that has to see it. `BOX_INLINE_BLOCK` floats
without that; a `BOX_INLINE` is never painted, because the painter
reaches a float through the box tree.

**Two instruments answered wrongly on the way.** `getComputedStyle`
reports `::first-letter`'s `font-size` as the paragraph's own under
every value of `initial-letter`, including the ones where the letter is
plainly seven times as wide, so the widths had to be rasterised. And
the measurer's own width cache is keyed by a `fontKey` built when the
style is computed: scaling the letter to 106px afterwards left the key
saying 20px, so every drop cap after the first in a process got the
first one's advance. `refreshFontKey` is called wherever the font
changes after the fact now.

**The property instrument cannot see this one.** It grades an element's
computed style and a drop cap lives on a pseudo-element, so the count
stays at 261 with the feature working. `tests/unit/test_initialletter.f`
is the measurement instead, and todo.md carries the `::pseudo` row that
would let the instrument reach it.

`initial-letter-align`, and `initial-letter` on an ordinary inline box,
are not implemented.

### The inline formatting context's containing block is restored

`layoutInlineContent` saves and restores thirteen globals when it enters
a formatting context, and did not save the two that say where the
containing block is. A float in inline content is laid out from inside
the line it interrupts, so a float with text in it ran through there and
left the outer context holding the float's own edges: every line after
it was as wide as the float rather than as wide as the paragraph. A
300px paragraph beside a 64px float wrapped its words in 64px, so four
lines became thirteen and the block came out 390px instead of 120.

An empty float has no inline content, takes no such detour and was
always right, which is why the float suite passed: it never put anything
inside one. It does now, and the test needs no number to make its point
-- the same paragraph beside an empty float and beside a float with one
letter in it must lay its lines out identically.

### A motion path's subpaths

A second `M` used to end the path. It begins a subpath now: the path's
length is the sum of them and a distance walks them in order with
nothing joining them, so half way along two equal legs is the end of
the first and the next step is the start of the second. `Z` closes the
subpath it is in rather than the path, and the coordinate pairs after
an `M`'s first are a line rather than another move (SVG §8.3.2), which
this engine had been dropping.

**A distance wraps round a path that is a single closed subpath and
clamps at the ends of anything else.** That is measured, not reasoned
about: `M 0 60 L 100 60 Z` answers 0,60 at 400px and 20,60 at −20px,
both taken modulo its 200, while the same path with a second subpath
after it answers its own end at 400px. So the wrap this engine already
did belongs to a lone closed subpath, and it is turned off the moment a
second `M` appears.

**The gap between two subpaths is a segment of no length**, which is
what lets the existing arc-length lookup walk them unchanged. It cost
one correction: the lookup takes the last point whose distance is not
past the one asked for, which at a join is the *start* of the next
subpath, where Chromium answers the end of the previous one. Stepping
back over a zero-length segment — and only when the distance is exactly
the join, or a point in the middle of the second subpath would step back
too — is what puts it there.

### A motion path's curve commands

`path()` read `M`, `L`, `H`, `V` and `Z` and stopped at the first curve.
It reads `C`, `S`, `Q`, `T` and `A` now, each flattened into the same
polyline the arc-length lookup already walks — sixty-four segments a
curve, which holds a hundred-pixel curve to well under a pixel.

**A quadratic is the cubic whose controls are two thirds of the way
from each end to it**, so there is one sampler rather than two. `S` and
`T` reflect the previous curve's control point about the current point,
and the current point itself where the command before was not of that
kind. `A` is converted from its two endpoints to a centre and two
angles, with radii too small for their chord scaled up until they fit,
which is what the standard asks for rather than treating the arc as
invalid.

The checks that earn their place need no point known in advance: a
relative cubic from the same start is the same curve as its absolute
twin at every distance; `S` and `T` make a path symmetric about its
middle, as far above the axis in the second half as below it in the
first; and the two sweeps of a semicircular arc are mirror images.

**The first version of those checks read −30 for everything that goes
up**, which is the canvas edge and not a curve. The suite's box sits
forty pixels from the top, so the upper half of every arc fell off the
canvas and `boundsOf` reported where the ink was clipped. The paths
start at y = 60 now, and each is measured against its own start rather
than the fixture's.

### The static position of an absolutely positioned box

CSS2 §10.3.7: a box with `position: absolute` and an `auto` inset sits
**where it would have been in flow**. This engine put it at the corner
of its containing block, on both axes and in every case tried — 0, 0
where Chromium answers 0, 50 for a box after a 50px block, 60, 0 for one
inside an indented div, 0, 20 for a block-level one after text on a
line, and 20, 70 in a containing block with 20px of padding.

**The flow already walks past these boxes, so the position was there to
be taken.** The block layout skips an out-of-flow child and
`placeInline` returns for one immediately; the static position is the
pen at exactly those two moments. It is recorded on the way past, in a
map keyed by box id that a document with nothing positioned never grows,
because `docHasPositioned` guards the writes as well as the read.

That split is also what gets the two kinds right without a case for
either. An **inline-level** box takes `ifcX`, `ifcY` and lands where the
inline itself would have been. A **block-level** one among inline
content is a sibling of the anonymous box holding that text, so the
block loop hands it the line after — which is what Chromium does, and
neither needed to be asked for.

**The two axes are decided separately**, so `top: 5px` with `left: auto`
puts the box at the declared 5 down and the static position across. A
`fixed` box has no such place: it resolves against the viewport and
stays at its corner.

This was found while implementing `anchor()`. With no fallback and no
anchor the declaration has no effect, and "no effect" means the static
position — which turned out to be somewhere the engine did not compute.

### `anchor()` in the inset properties

CSS Anchor Positioning 1's placement function, in `left`, `right`,
`top` and `bottom`. `left: anchor(--a right)` puts the box's left edge
on the anchor's right, `right: anchor(--a left)` hangs its right edge
off the anchor's left, and a fallback beside the name is used only when
the anchor cannot be found.

**Every side keyword is one number.** `left`, `top`, `start` and
`self-start` are 0, `center` is 50, `right`, `bottom` and `end` are 100,
and a percentage is itself — so the nine keywords and the percentage
are the same value in hundredths of a percent along the anchor's box,
and the resolver has one case rather than ten. That the logical names
are the physical ones here is measured rather than assumed: there is no
`writing-mode` to make them anything else.

The checks that earn their place are the ones that do not depend on a
position being known: `anchor(--a 0%)` must land where `anchor(--a
left)` lands, `100%` where `right` lands, and `50%` where `center`
lands, on both axes.

**Each `anchor()` resolves its own name**, against the anchors the
tree-order walk has already passed — the same rule `position-anchor`
follows — so one box can anchor its left edge to one element and its top
to another. A nameless one takes the name `position-anchor` gave.

It is resolved where `position-area` is, after the tree has been laid
out, because that is the first moment an anchor has a rectangle.

**It is the box's margin edge that lands on the anchor, not its border
edge.** The first version put the border edge there, which is
indistinguishable on a box with no margin and wrong on one with any --
so the margin was measured rather than reasoned about: a 10px left
margin moves the box ten further from the anchor and a 10px right
margin ten the other way, which is what an ordinary inset does too.

**`anchor-size()` is measured and not implemented, and the reason is
structural.** It sizes the box rather than placing it, and the size is
needed before the box is laid out while the anchor's rectangle is not
known until afterwards — so it wants a second layout pass, as
`@container` already has. Written down in todo.md rather than
half-built, along with `anchor()` inside `calc()`, which wants the calc
evaluator to carry a term that is not yet a length.

### `overscroll-behavior`

All five: the shorthand and `-x`, `-y`, `-inline`, `-block`. A scroll
container that has reached its end passes a wheel outward, to the
nearest ancestor that can still take it and then to the page;
`contain` and `none` stop that chain at the box that declares them.
The count is **261 of 405**, and `--fields` says all four graded rows
moved `overscrollBehavior`.

**The probe that would have measured the behaviour could not fail, and
the control is what said so.** A synthetic `WheelEvent` is untrusted, so
dispatching one over a nested scroller already at its end moves neither
the scroller nor its ancestor — with `contain`, and equally with the
default `auto`, where a real wheel would certainly chain. So Chromium
answers the computed values here and nothing else, and the chain is
graded against this engine's own scrolling, which is written down:
`scrollContainerAt` walks outward from the box under the pointer, and
`wheelAt` gives the remainder to the page.

The check that earns its place is the one that does not depend on the
keyword doing anything: a container that can **still** scroll takes the
wheel whatever it declares. `overscroll-behavior` acts at the boundary
and nowhere else, so `contain` and `auto` must be indistinguishable
until the scroller runs out.

**The two logical longhands are the two physical ones under other
names.** Chromium reads `-inline` back as `-x` and `-block` as `-y`, and
`dir="rtl"` changes neither; only a `writing-mode` could swap those axes
and there is none here. So they are read into the same pair rather than
resolved against a direction.

**`contain` and `none` differ in nothing this browser does.** `none`
also suppresses the overscroll affordance and there is none to suppress.
The checks ask both keywords and expect the same answer, which says
where the two are alike rather than implying one does more.

**A scroll container with nothing to scroll contains the chain too.**
The first version passed the wheel straight on from a box whose content
fits, because the walk returned before it reached the question. Such a
box is at both of its ends at once, so it is at a boundary exactly as
one scrolled to its end is, and the wheel reached it either way: having
nothing to give back is not a reason to pass it outward.

### `box-decoration-break`

`slice`, the initial value, is what the engine does. `clone` gives every
fragment of a broken inline the whole box: both side edges, each
continuation's content starting after the opening one.

**It changes no line break.** The natural reading is that cloning the
edges takes room and so breaks the text earlier. Chromium does not: the
same characters stay on the same lines, each continuation is pushed
right by the opening edge, and the closing edge overflows the line. Both
`slice` and `clone` put the first line's ink at x 11 to 143 in a 150px
paragraph, and `clone`'s closing border then sits at 150 to 153 —
outside the paragraph. So the closing edge is added to the fragment's
width and never to the pen.

The count is **257 of 405**, and `--fields` says the field that moved is
`boxDecorationBreak`.

The check counts the side borders alone: over three lines `clone` paints
three times as many as `slice`, because `slice` paints two however many
fragments there are — and the three is counted from the render, as the
number of bands of ink, rather than assumed. On a single line, where
there is one fragment either way, the two keywords must be
indistinguishable, and that check does not depend on the count at all.

**The first version of the multiplier check was measuring the overlap.**
At the 24px line height the rest of the suite uses, a padded inline's
box is 31 tall, so two consecutive fragments overlap by seven rows — and
three opening edges, which all sit in the same four columns, cover fewer
pixels than three of them. The fixture's line height is 40 for that
reason, which is written beside it.

**The properties floor in `tests/run.sh` was 210 against a count of
257.** A floor left where it was cannot catch the regression it exists
to catch, so it is raised with the count now and the rule is written
next to it.

### An inline box's own border and padding

CSS2 §8.4 gives an inline box margin, border and padding on all four
sides. The engine reserved the horizontal advance for them and painted
none of them: `paintInlineBackground` drew a background and the top and
bottom borders and stopped, so an inline's left and right borders were
drawn nowhere and its vertical padding took no room. The border render
suite was green because every border it tested was on a block.

**The opening side goes on the fragment that begins the inline and the
closing side on the fragment that ends it**, which is what the initial
`box-decoration-break: slice` means. A fragment now records which of the
two it carries, so a fragment in the middle of a broken inline gets
neither, and a margin takes no paint on the sides it does carry. The
four sides go through `paintBorderSide` rather than a filled rectangle,
so an inline's border draws dashed, dotted, double or in relief exactly
as a block's does.

**The decorations go on the content area, not the line box.** Measured
against Chromium, an inline's background covers the font's ascent and
descent about the baseline -- 18 pixels of a 24-pixel line -- and its
padding and border then grow that box outside the line. The engine used
the line box, or the inline's own line height where that was shorter,
which was two pixels high and five pixels tall out.

**None of it changes the line height.** Chromium's lines sit 24 apart
while each fragment box is 39 tall, so the box simply paints outside the
line and the block is no taller for it.

The check that earns its place counts the side borders alone, with the
top and bottom given no width and the text no colour: the same inline
over one line and over three must paint the same number of them, because
`slice` puts each side edge on exactly one fragment however many
fragments there are. Neither number is known in advance and neither is
written down in the test.

**A box taller than its line broke the painter's cull**, which skipped a
line box and a block box outside the window it was drawing. An inline's
border now reaches past both, so a border a few pixels from the edge
vanished when the line itself scrolled out: the last scroll position
that painted any of it was the line box's last row, 44, and not the
border box's, 50. Both culls are widened by the furthest any inline on
the document reaches outside its line, which is one number computed
where the fragments are placed and left at zero by a document with no
padded or bordered inline -- so the test is the plain one on every page
that does not use the feature.

The opening side is the physical left one. In right-to-left text
Chromium mirrors it, and this engine does not; that is measured and
written down in todo.md rather than half-fixed, because the fragments
would have to go into visual order first.

### `text-box-trim` and `text-box-edge`

A line box is taller than its text by the leading, half above and half
below. `text-box-trim` says which of those halves to drop, and
`text-box-edge` which two of the font's edges the height then runs
between. A 20px/2 block is 40 tall untrimmed, 24 under `trim-both`, and
14 between the cap height and the baseline.

**Trimming sets the edge; it does not shrink to it.** At a line height
below the content height the leading is negative, and trimming it makes
the line *taller*. That was the one check of twenty-three that failed
before it was fixed, and it only exists because the measurement showed
line-height 1, 2 and 3 all give 24 -- every ordinary line height hides
the bug.

**The engine needed no new capability.** It reads no font metrics --
Festina exposes only a string's inked width -- so it already models them
as ratios per em and already computes the half-leading this trims. Its
existing constants give 19 + 5 = 24 at 20px, which is Chromium's own
number, so only the `cap` and `ex` over-edges needed adding, at 0.70 and
0.55 per em. The two already there were evidently estimated and land
within 0.02 of the measurement.

The trim splits across lines the way the standard asks: the over edge on
the first line, and the under edge on the last once there is a last one.

**The property instrument was lying about one of them, and the row was
fixed rather than the count banked.** `text-box-edge: text` is the
initial edge and changes nothing without a trim beside it; it registered
only because storing the value made a map entry. Its row now reads
`cap alphabetic; text-box-trim: trim-both`, so it can register on the
edge alone -- and the count stayed the same, which is what says the
property was implemented rather than propped up.

**256 of 405.**

### `overflow-clip-margin`, and where a clip box's edge actually is

`overflow: clip` clips to the **padding** box, not the border box, and
`overflow-clip-margin` moves that edge outward -- by a length, or by
naming the box to start from. A clip box at left 100 with a 5px border
keeps ink from 105 under the initial value, from 85 under `20px`, and
from 115 under `content-box`. `overflow: hidden` ignores it.

**A `getClientRects()` probe said there was no difference**, on all five
cases, because it reports where the child was laid out rather than where
its ink survived. That is the third instrument in this release to answer
"no difference" confidently and wrongly about a paint-time property,
after `getComputedStyle` on `position-visibility` and a paired benchmark
that summed a phase the change was not in. Rasterising and reading the
pixels separated the five cases immediately.

The length and the box code are packed into one value in a page-level
map keyed by the computed style's serial, not a field on `Style`, for
the reason benchmarks.md records. Paint expands the clip rectangle only
for `overflow: clip`, and a page that never declares the property pays
one bool test.

**254 of 405.**

### CSS Motion Path, which was filed under things that need a clock

`offset-path` gives a box a path, `offset-distance` a point along it,
`offset-rotate` which way it faces there, `offset-anchor` which point of
the box sits on the path and `offset-position` where a ray begins. None
of it needs a clock: `offset-distance: 40%` places a box in a still
frame. The specification was grouped in css-2026.md with Transitions and
Animations under "an animation needs a clock and a repaint loop", which
is true of those and not of this one.

**The control was not a control.** The measurement's first round wrote
`offset-rotate: none` to hold rotation still, and there is no such value
-- the grammar is `[ auto | reverse ] || <angle>` -- so the declaration
was dropped and every row measured the initial `auto`. Half the rows
looked right anyway, because at those points the path's direction is
zero. Asking `getComputedStyle` which declarations had survived is what
found it, and `auto 0deg` came back.

**The path's coordinates are the element's own**, not the containing
block's: a `circle(50px at 100px 100px)` on a box laid out at (30, 40)
has its centre at (130, 140). A box at the origin cannot tell the two
apart, which is what the first round used. **A circle starts at three
o'clock and runs clockwise**, not at twelve. **`offset-anchor: auto` is
the transform origin**, not the box's centre, which only shows on a box
whose `transform-origin` says otherwise -- and that was the one test of
the hundred and fifty-four that failed before it was fixed.

Every path becomes a polyline, because the point at an arc length is
exact on one. A polygon and a `path()` of straight commands lose nothing
by it; a circle and an ellipse are sampled at 720 steps, which is far
below the pixel the painter rounds to. A ray is not a polyline at all:
it answers distances past its end and before its start.

**One `int` on `Style` cost the benchmark page 1.08 ms of layout** on a
page with no `offset-path` on it, against a parent-against-parent
control of -0.16 ms. The index moved to a map keyed by the computed
style's serial, and the re-measurement matches the control.
benchmarks.md has both, and the control beside them, because 14 of 25
pairs slower is the sort of number that gets waved through without one.

**253 of 405.**

### `anchor-scope`, and two rules of resolution it exposed

`anchor-scope: none | all | <dashed-ident>#` scopes an anchor name to an
element's subtree. **It is a boundary in both directions**, which the
property's own description does not say: a box inside a scope of `--a`
is cut off from every `--a` outside it as well, even when the scope
holds no anchor of that name at all. The rule is symmetric -- an anchor
and a box see each other only when the nearest scope of the name
enclosing each of them is the same element -- and the scope covers the
element declaring it, so `anchor-scope` and `anchor-name` together hide
an element from outside, and a box that scopes a name sees no anchor of
it anywhere. An implementation that only stopped a scoped name leaking
outward agrees with Chromium on every case tried but those.

**Two resolution rules came out of the same measurement**, neither of
them about scope. An anchor that comes after the box in tree order is
not a candidate, and of the ones before it the last wins; this engine
kept one rectangle per name and took the document's last writer, so a
box between two anchors took the wrong one. And an anchor must be a
descendant of the box's containing block -- a box inside its own anchor
is unanchored -- which stays unimplemented and recorded, because the
placement pass carries a containing block's four numbers rather than its
identity.

The first fell out of the fix for the scope. One tree-order walk now
keeps the live rectangle of each name, resolves each anchored box
against what it has passed, and stores the answer per box, so the
placement pass no longer resolves anything. The names are keyed by the
scope they are in; a page that scopes nothing keys by the bare name and
never touches the scope stack, which is one bool test per box.

**248 of 405.** All seven of the specification's properties work.

### `position-visibility`, and a probe that asked the wrong question

An anchored box that still overflows its containing block once every
candidate has been tried is hidden under `no-overflow` and drawn under
`always`. It hides the **whole** box rather than clipping it harder: a
box straddling the block's edge paints 20 of the 25 pixels sampled on a
row inside it under `always`, and none of them under `no-overflow`. A
stricter clip would leave those twenty.

**The first probe found nothing, confidently.** It read
`getComputedStyle().visibility` under each keyword and got `visible`
every time, because Chromium implements this as a paint-time state that
never reaches computed style. That is worth recording beside the
behaviour: an instrument asking the wrong question answers "no
difference" exactly as firmly as one asking the right question, and the
only reason it was caught is that a property doing nothing at all was
the less likely of the two explanations.

**`anchors-visible` is treated as `always`, and says so.** Telling them
apart needs the anchor scrolled out of a scrollport while the box stays
visible, and `position-area` ties the box to the anchor. A static render
has no such state, so this is a measurement that could not be made
rather than a guess dressed as one.

The hidden boxes are a page-level map keyed by element id, consulted in
paint behind a flag. `Style` is shared between identically-styled
elements so it cannot carry a per-box decision, and `Box` is allocated
per box -- 2,728 of them on the benchmark page -- where a field costs
whether or not anything reads it.

**247 of 405.** Six of the specification's seven properties work;
`anchor-scope` alone is left.

### `position-try-order`, which is not part of the retry loop

The order sorts the candidates -- the area the element asked for, then
its fallbacks -- by the room each region offers in the named axis, most
first. `most-height` and `most-block-size` measure the block axis,
`most-width` and `most-inline-size` the inline one, which coincide in
the writing mode this engine lays out in.

**The sort applies whether or not the original position overflows.**
That is the row the probe existed for: with `position-area: bottom` and
`position-try-order: most-height`, Chromium moves the box to `top` even
though `bottom` fits. Adding an ordering step to the overflow retry --
the obvious place for it -- would leave the box where it was and agree
with Chromium on every other case tried.

Making room for it simplified what was there. One candidate walk now
covers both the plain retry and the ordered choice: the candidates are
the declared area followed by the fallbacks, sorted when an order asks,
and the first that fits wins. Without an order the declared area is
simply first, so a fitting position is kept and the rest are never
reached -- the behaviour the previous commit spelled out separately.

**246 of 405**, and earned: layout sorts by it. `anchor-scope` and
`position-visibility` are still neither counted nor stored.

### CSS Anchor Positioning 1, and the retry loop `position-try-fallbacks` is

An anchored box that overflows its containing block now walks the
candidates `position-try-fallbacks` names and takes **the first that
fits**, in written order, rather than the best-fitting one. A position
that fits is kept and the list is never consulted; when no candidate
fits either, the original position stands rather than the last one
tried. `flip-block`, `flip-inline` and `flip-start` transform the area
in force rather than naming a new one, and are not applied at all when
the original fits.

Both of those last two rules are why the nine cases were read off
Chromium before anything was written: an implementation that kept the
last candidate it tried, or the one that overflowed least, agrees with
Chromium everywhere except exactly there.

`position-try-fallbacks` is counted because layout reads it -- 245 of
405. `position-try-order` and `position-visibility` are still not, and
still are not stored: neither has been probed, and a property nothing
reads is not implemented however faithfully it is kept.

### CSS Anchor Positioning 1: `anchor-name`, `position-anchor`, `position-area`

An absolutely positioned box resolves against the padding box of its
nearest positioned ancestor. `position-anchor` names a second rectangle
to resolve against instead -- another element's border box, found by the
`anchor-name` it declared -- and `position-area` says which of nine
regions around it the box goes in.

Each axis is one of three bands. A band before the anchor end-aligns the
box so its far edge meets the anchor's near one, a band after
start-aligns it, and the anchor's own band centres it. **`span-all`
centres on the anchor, not on the region it spans**: in a 300px
containing block Chromium answers 120 where centring in the region would
give 140, which is the case a region-first reading gets wrong and the
reason the thirteen regions were measured before any of this was
written.

The placement runs after the ordinary positioning pass rather than
inside it, because an anchor may itself be absolutely positioned and so
has no final rectangle until that pass is done.

**One bug the tests caught.** `top span-all` came out centred rather
than above: `span-all` names no axis, and assigning the keywords in
written order let it overwrite the block axis `top` had already claimed.
The keywords that name an axis are placed first now, and the ones that
name none fill whatever is left.

**Four of the specification's properties are not implemented, and are
not counted.** `anchor-scope`, `position-try-fallbacks`,
`position-try-order` and `position-visibility` all registered on the
instrument while they were merely stored in a field -- a property the
cascade computes but nothing reads renders the same either way, so by
this project's own definition it is not implemented. They are neither
stored nor claimed by `@supports` now, and todo.md says what each needs:
a scope tree for the first, and for the other three a retry loop that
lays the box out, tests it for overflow and lays it out again.

The count is therefore **244 of 405**, up from 241 by the three
properties that move a box, rather than the 248 the digest would have
given.

The three are held off `Style` in a side table indexed by one `int`,
because a field on `Style` costs time in layout whether or not anything
reads it -- four floats cost two milliseconds on a page using none of
them, measured the commit before this one.

### CSS Borders 4: `corner-shape`

A corner is the region the border radius already resolves, and every
value this property takes is that region under a different superellipse
exponent -- `|x/rx|^k + |y/ry|^k = 1`, with a negative exponent giving
the concave reflection. So there is one curve in the painter and not
six: `square` is a large k, `squircle` is 4, `round` is 2, `bevel` is 1,
`scoop` is -2 and `notch` is a large negative one. `superellipse()`
takes any of them, and the suite checks it against the keywords rather
than against numbers worked out here -- `superellipse(1)` must be the
same picture as `bevel`, or the keywords are a second table that happens
to agree.

The shorthand reads one to four values the way `border-radius` does, the
four physical longhands override it, and the four logical ones name the
same corners in the left-to-right horizontal mode this engine lays out
in. **241 of 405** properties now change the computed style, up from
233, and `--fields` says each of the eight moved its own corner's field.

**Chromium 141 was measured first**, as a 100x100 box with a 40px radius
read as the first fully black pixel on each row of the corner. `bevel`
is what pins the parameterisation down: an exponent of 1 collapses the
formula to a straight line, so all of its rows are exact rather than
near, and an exponent wrong anywhere could not match every one.

Three things the tests caught that the implementation had wrong:

**Sampling a corner evenly in one axis is wrong for an extreme
exponent.** `square` and `notch` put everything they do in the last
thousandth of an axis parameter, so sixteen even steps drew a diagonal
across the corner instead of the shape. The corner is walked in the
angle now, which samples every exponent evenly along its own curve.

**The shape was painter state, and stale state leaked between boxes.** A
page that used the property left the globals set, so the next box with
no shape came out bevelled. The check that caught it is the one that
asks two ways of saying the same thing to agree: a box with no
`corner-shape` must be the same picture as one asking for `round`.

**`Math.cos` of half pi is 6e-17, and `notch` raises it to the 1/500.**
That is 0.93 rather than 0, and it put the end of a corner three pixels
from the edge it joins. Both ends of every corner are pinned to the
straight edges exactly rather than computed.

A corner that is `round` keeps the bezier the canvas draws natively even
when another corner of the same box is shaped, so `round` is the same
pixels whatever surrounds it -- an invariant worth having structurally
rather than by watching a polyline converge to it. A page that never
says the property never leaves that path at all: `anyCornerShape` is one
boolean on the box's radius resolution, and `roundedRectPathEllipses`
takes its old four-curve route whole.

A shadow follows the shape its box has, because `resolveCornerRadii` is
where both the radii and the shapes are read and `shadowShapeRadii` goes
through it.

**The four exponents are one packed `int` rather than four `float`
fields, and the benchmark is why.** The readable version cost 2 ms on a
page with no corner shaped at all -- slower in 21 paired samples of 25,
all of it in layout, none of it in the cascade that parses the property
or the paint that draws it. Compiling the revision before this one with
four `float` fields added to `Style` and never read reproduces it
exactly, so the cost is thirty-two bytes of struct growth rather than
any line the feature runs: `Style` is dereferenced once per box
throughout layout, and the benchmark page has 2,728 boxes sharing 24 of
them. One and two `int` fields cost nothing on the same test, so four
codes of six bits in one field do too -- slower in 28 of 50 pairs, which
is what a coin gives. No test could have caught this; every suite passed
on the slow version. benchmarks.md keeps the numbers and the padding
experiment.

### The explicit half of UAX #9, and `unicode-bidi`

The bidirectional algorithm had its implicit half -- the W, N and I
rules, which resolve a character's direction from its own class and its
neighbours'. It now has the explicit half as well: the nine directional
formatting characters a document uses to say what the implicit rules
would get wrong. X1 to X8 maintain the directional status stack, the
depth limit of 125 and the two overflow counters that make a PDF or a
PDI undo an embedding that was dropped rather than nested; X9 removes
the embeddings, the overrides and the PDFs; X10 and BD13 build the
isolating run sequences, and the implicit rules run over one sequence at
a time rather than over the whole string, which is what lets an
isolate's content resolve without the text around it and the text around
it resolve without the content. An FSI takes its direction from the
first strong character between it and its matching PDI, which is P2 and
P3 applied to a span. None of the nine is drawn, so none of them is in
the visual order.

`unicode-bidi` is those characters under the names a stylesheet gives
them, and that is exactly how it is implemented. CSS Writing Modes 3
§2.2 defines each value as the pair the element's text is wrapped in --
`embed` an LRE or an RLE and a PDF, `bidi-override` an LRO or an RLO,
`isolate` an LRI or an RLI and a PDI, `isolate-override` both pairs,
`plaintext` an FSI and a PDI -- so the property wraps and calls the one
algorithm rather than opening a second path through it. All six values
work where only `bidi-override` did, and the value belongs to the
element the text is in rather than to the block: a text box carries its
element's computed style, which is where an inline's `unicode-bidi` is.

`normal` is now what the standard says it is, which is a fix rather than
an addition: an element with `direction: rtl` and no `unicode-bidi` does
*not* open an embedding, so its own direction does not reach the
ordering of its content -- the paragraph's stands. That is the
difference between `normal` and `embed`, and Chromium agrees: on
`ab` and a Hebrew word inside a `direction: rtl` inline, `normal`
answers `ab` first and `embed` answers the Hebrew first.

**Every expected order is Chromium 141's**, read by wrapping each
character in a span of its own and sorting the spans by their left
edges -- a character the browser gives no width, which is every one of
the nine, drops out of the answer, which is what this returns as well.
Thirteen explicit-code cases and eighteen property cases settled the
behaviour before any of it was written.

`@supports` answers yes for `unicode-bidi` now that every value it takes
does something, and the property registers on the instrument against a
field of its own: **233 of 405**, up from 232, with `unicodeBidi` the
field that moved.

Two rules of the standard are still out, and for the same reason the
character classes come from script ranges rather than from a table: W1
resolves a combining mark to the class of the character it sits on and
N0 mirrors a bracket inside a right-to-left run with its partner, and
both want the Unicode database this repository does not vendor.

A page that mentions neither a right-to-left script nor `unicode-bidi`
pays nothing: `anyUnicodeBidi` is set during the cascade beside
`anyRtlText`, and the reordering pass over a finished line is skipped
unless one of them is true.

### CSS Scroll Snap 1

A scroll container with `scroll-snap-type` comes to rest on one of the
positions its children's `scroll-snap-align` declares, rather than
wherever the scroll left it. `x`, `y`, `both` and the two logical axes,
each `mandatory` or `proximity`, against `start`, `center` and `end`,
with `scroll-padding` insetting the snapport and `scroll-margin`
outsetting a child's snap area, all four sides of each.

A snap position is one subtraction: the child's edge less the snapport's,
per alignment. The nearest wins and a tie goes to the lower.

**Chromium was measured before any of it was written**, which is why the
implementation passed its suite on the first run. Four probes settled it:
the subtraction each alignment is; that a tie goes to the lower, pinned
by the `end` alignment at 35 where 20 and 50 are both fifteen away; that
`proximity` is a third of the snapport rather than a fixed distance,
which took snap points 500 apart to see at all and two snapport sizes to
tell apart; and that a snap area larger than the snapport is a *range*
rather than a point (§6.1), so a scroll already inside a tall child stays
where it is instead of jumping to that child's top.

That last one is the case a nearest-point implementation gets wrong, and
the reason to measure first rather than write first: with four 100px
children in an 85px snapport, Chromium leaves 10 at 10, pulls 40 back to
15 -- the first child's own end -- and sends 60 on to 100.

The eight logical longhands -- `scroll-padding-block-start` and its
siblings -- are the physical eight under the names a writing mode gives
them, so they are renamed where every other logical property here is
renamed rather than implemented again. Each is checked against the
physical one it stands for *and* against the undeclared case, because a
pair of aliases that both did nothing would agree with each other
perfectly.

The property instrument goes from 214 to 232 of 405, and `--fields` says
each of the eighteen moved its own field. All ten change where a scroll comes
to rest, so none of them is a count that moved without anything else
moving.

### CSS Scrollbars 1, and a stable gutter

`scrollbar-width` and `scrollbar-color`, which is the whole of CSS
Scrollbars 1, and `scrollbar-gutter: stable` from CSS Overflow 4. The
browser paints its own scrollbars, so all three are acted on rather than
stored: the width decides how much room the bar takes from the content,
the colours decide what it is drawn in, and the gutter decides whether
the room is taken before there is anything to scroll.

Chromium 141 is the yardstick. A 200x100 `overflow: scroll` box has a
client width of 185, 190 and 200 under `auto`, `thin` and `none`, so
`thin` is ten pixels and `none` is none; an `overflow: auto` box with a
10x10 child has a client width of 200, and 185 once it declares
`scrollbar-gutter: stable`, with the client height 100 either way --
the gutter is the inline axis's and the block axis keeps nothing.

**A bar of no width is still a scroll container.** `scrollbar-width:
none` hides the bar; it does not take the scrolling away. The box tree
had been answering both questions with one number -- `sbW` was the room
the bar took *and* the test for whether the box scrolled -- so the first
version of `none` produced a box that could not be scrolled at all. The
two are separate fields now: everything that draws a bar or is asked
where one was clicked reads the room, and everything that scrolls reads
the scrolling.

`scrollbar-color` takes two colours, thumb then track, and inherits. A
declaration naming one colour is dropped whole rather than colouring the
thumb and guessing at the track, because the standard takes the pair or
nothing.

`scrollbar-width` does not inherit here. The standard makes it
inherited; Chromium does not, answering `auto` on the child of an
element that declared `thin`, and this follows the browser it is
measured against and says so rather than leaving the disagreement
unrecorded.

`scrollbar-gutter: both-edges` reserves the same width again on the side
no bar is ever drawn on, so the content sits between two equal gutters:
Chromium answers a 200px box with a client width of 170 rather than 185.
It is the one value here that moves a box's content to the right --
nothing else in this engine insets a box from that side -- so it is a
field of its own on the box rather than a wider bar, added in `contentX`,
which is the single place a content box's left edge is decided.

The property instrument goes from 211 to 214 of 405, and `--fields`
says each of the three moved its own field rather than a neighbour's.

### Paged media, and a browser that prints

CSS2's last unimplemented chapter. `@page` declares the page box: `size`
in the ten named sheets the standard lists -- A5 through A3, B5, B4, the
two JIS sizes, letter, legal and ledger -- or as one or two lengths,
turned by `portrait` and `landscape`; `margin` in the one-to-four-value
form, with percentages of the page box. `@page :first`, `:left` and
`:right` declare it for particular pages, and a named `@page` for the
pages a `page` property sends there. The selectors are weighed as the
triple Paged Media 3 6.5 gives, so `:first` outranks `:right` on the
first page however the two are ordered, and rules accumulate rather than
replace: what a later rule does not say, an earlier one still does.

`--print out.png` writes `out-1.png`, `out-2.png` and so on, one image to
a sheet. `@media print` is the medium such a render answers to, so a
document's print stylesheet is the one that reaches its pages -- and the
`@page` rules almost always inside it.

**A page is a fragmentation container like a column, so this is the
column algorithm over a different container**: the same units, the same
rules about where a break is allowed -- forced, forbidden, orphans,
widows -- and the same search for the nearest allowed point. What differs
is that the height is asked for one page at a time, because `@page
:first` can make the first sheet a different size from the rest, so no
single target would do.

CSS2's `page-break-before`, `page-break-after` and `page-break-inside`
are the three fragmentation properties under older names (Fragmentation
3 4.4), so a declaration under an old name is applied under the new one
rather than implemented twice. That makes the cascade between the two
spellings one property's cascade; two properties would let whichever was
read last always win, whatever the stylesheet said.

Nothing is moved to make a page. The document is laid out once, at the
page area's width, and a page is that document drawn at an offset --
which is what a scroll position already is, and uses the same painter.

**Three bugs, each found by a check that could fail.**

A block of 120px holding one 19px line reported the *line's* extent to
the fragmenter, so four of them fitted into 80px of a page. The unit a
child contributes now reaches the child's own bottom. This was a
multi-column bug too, and had been one all along: a 120px block in a
column occupies 120px of it. Both column suites pass unchanged.

The host to fragment was found by descending through boxes with a single
child, which looked equivalent to "the body" and was not: a document
whose body holds one block descends past the body into that block, finds
no children, and comes out one page however tall the block is. It is the
body's box now.

A page painted the whole of its area even when it ended at a break before
the area was full, so the last sheet showed the first inch of the next
one. A page carries the strip between its own two offsets.

**The first version cost 2 ms to every page, and the rule that catches
it was already written down.** The three `page-break-*` properties are
renamed onto the modern ones where a declaration is applied, and that
runs once per matched declaration -- 11,614 of them on the benchmark
page. Moving the comparisons to the end of `applyDecl` looked like the
fix and was not: the end is where most properties land, since only the
shorthands return before it. A per-document flag, set while the
stylesheet is read, is what removes it; twenty-five paired samples then
give a median difference of −1 ms. benchmarks.md has the numbers, and
the two suspects that were measured and cleared.

Chromium 141 is the yardstick throughout, printed to PDF and read back:
the `/MediaBox` gives the page box -- `size: A4` is 594.96 x 841.92pt,
`size: 400px 600px` is 300 x 450pt exactly -- and counting `/Type /Page`
gives the page count, which is where every count in the suite comes from.
Four 120px blocks on a 500px page area are one page and five are two; an
unbreakable 700px block is two and a 1200px block is three; a block on a
named page is three, because the name breaks into the run and out of it
again. The one number that is stated rather than matched is the default
margin, which no standard fixes: 0.4in here against the 37px a side
Chromium's print dialog defaults to.

### A shadow follows the box's `border-radius`

`box-shadow` was cast from a rectangle whatever the box's corners did,
so a rounded card carried a square corner's shadow. It is cast from the
box's own shape now, corner radii and all, grown by the spread -- a
round corner grows with it, a square one stays square (Backgrounds and
Borders 3 6.2) -- for a blurred shadow and for an unblurred one alike.

A rounded rectangle's Gaussian does not separate, because the shape's
width changes with the row. Its outer integral does: the value at a
point is the sum, over the rows the shape covers, of that row's share of
the vertical Gaussian times the horizontal Gaussian over that row's own
span. With every radius zero that sum telescopes back into the product
of the two axes, which is the closed form already there -- so the new
path and the old one owe each other an answer wherever a radius cannot
reach, and the suite collects the debt at the middle of an edge, out to
the twelve pixels a blur of eight reaches.

Only the corners need the sum. Past a corner's band every row of the
shape is the full width again, so widening the bands to hold the radius
as well as the blur's reach leaves the four edges and the middle the
single fills they already were, and a box with no radius resolves no
radii at all: `borderRadius`, the cascade's own answer to whether any
corner is round, gates the whole of it.

**Taking each row of the shape at its middle was wrong in a way only a
circle shows.** The edge of a circle goes as the square root of the
distance from the top of it, so the topmost row's midpoint is wider than
the row's average, and the error lands on the axis the rows run across
rather than the one they run along: the pixel above a circle came out
darker than the pixel beside it, at the same distance. A circle's shadow
is radially symmetric and nothing else in the fixture had to be known
for the suite to say so. Rows an ellipse crosses are taken in eight
slices now; measured against a reference of 64 slices, the worst case
over a 40x40 circle at blurs of 4, 8 and 20, a 100x100 at 8, a 30x30 at
2 and a 200x80 at 30 is 3.7 units of 255 at one slice to the row, 1.8 at
four and 0.77 at eight.

Chromium 141 on a 40x40 circle, reading the row three pixels above it
outwards from its left edge, gives `dfdfdf dadada d5d5d5 d1d1d1 cdcdcd
c9c9c9 c6c6c6 c4c4c4 c2c2c2 c1c1c1` against this engine's `e2e2e2
dddddd d8d8d8 d4d4d4 cfcfcf cbcbcb c8c8c8 c6c6c6 c4c4c4 c3c3c3` -- the
same profile two or three units lighter, which is the gap the square
corners already carry between a true Gaussian and the three box blurs
Skia approximates one with.

**The first version cost 2 to 3 ms on a page of square-cornered
shadows, and neither benchmark page could have said so** -- neither of
them casts a shadow at all. A page written for the question did: 2,000
cards under `box-shadow: 0 4px 12px rgba(0,0,0,0.35)` on an 800x4000
canvas, about 355 of them painted, with the same 2,000 cards and no
shadow as the control. The control gave 10 ms on both sides on every
sample, which is what said the cost was in the shadows.

It was none of the four things that looked expensive. Five binaries
each answered one: the eight extra arguments cost nothing, the guarded
`resolveCornerRadii` cost nothing, growing the corners by the spread
cost nothing, and 41 KB of never-called code compiled into the old
revision -- shifting the layout of every function after it -- cost
nothing either. What removed it was taking the radii out of
`paintShadows` and into a function reached only through the
`borderRadius` flag. Twenty-one paired samples now give the same 42 ms
minimum on both sides, medians 45 and 44, the new binary faster on
eleven of them and level on two.

The rounded path turns out to be *cheaper* than the square one it
replaces on a page whose cards share a shadow -- 27-31 ms against
43-48 -- because a round corner is one cached image blitted once where
a square corner, being separable, is one ramp blitted per row of the
blur's reach. The same cache would suit the square corners; todo.md
says so.

An `inset` shadow still does not follow the radius; todo.md says what
that needs.

### `revert-layer` rolls back a layer, not the origin

`revert-layer` had been read as `revert`. It rolls back one step now:
to the value the previous cascade layer gave, where `revert` rolls back
the whole origin (Cascade 5 §6.3).

The bookkeeping is the origin snapshot generalised. `matchWeight` packs
the origin and the layer into one rank and the specificity and source
order under it, so dividing takes the rank back out and a change in it
is a layer boundary. The map as it stood before each layer began is kept
the same way the origin's already was, and a `revert-layer` is resolved
when its layer ends -- which is the only moment that map is still to
hand. `revert` is still resolved last, because it rolls back past every
layer.

Chromium 141 over three layers -- `base` blue, `mid` green, `top` under
test -- gives `@layer top { color: revert-layer }` green, `@layer top {
color: revert }` black, and an *unlayered* `color: revert-layer` green,
because an unlayered declaration is in the implicit outer layer that
comes after every named one. All three agree here now.

**A check written against the old behaviour said the opposite.** When
`revert-layer` was an alias, a test asserted that one in a style
attribute reverts the origin -- and it passed, because it was written
against the alias rather than against the standard. Chromium gives
`style="font-weight: revert"` 700 on that markup and
`style="font-weight: revert-layer"` 400: a style attribute ranks above
an unlayered author rule, so rolling back one step lands on that rule.
The check now says so, and says why it used to say otherwise. This is
the thing CLAUDE.md means by a test written after the implementation
testing what the code does.

### A wheel tilted sideways scrolls a container across

The scroll container had both axes and both thumbs but only a vertical
wheel. Giving it the other one turned up a language gap worth the entry
it got: **`on mouseWheelUp` and `on mouseWheelDown` are the whole of the
wheel, and no event of any kind carries a modifier**, so neither a
horizontal wheel nor shift-wheel -- the two gestures every browser
offers for this -- is expressible as such (FINDINGS.md, finding 38;
festina.md §3s).

The data is arriving on X11 under a name that means something else. The
runtime maps buttons 4 and 5 to the two wheel events and lets every
other button through as an ordinary press, so a wheel tilted left or
right reaches a program as `mouseDown` with button 6 or 7. This browser
reads those, with the finding named beside them. A Windows build reads
`WM_MOUSEWHEEL` and nothing reads `WM_MOUSEHWHEEL`, so the same gesture
produces no event at all there and a container scrolls across only by
its thumb -- which is the part of the gap worth fixing upstream first:
two backends disagreeing about whether an event exists.

`scrollContainerAcrossAt` answers the same question across that
`scrollContainerAt` answers down -- which container under the pointer
can still take a scroll in the direction asked for -- so a box with only
a vertical bar takes none across, and one at its right end hands the
rest back.

### `::marker`

The pseudo-element restyles a list item's marker (CSS Lists 3 §3). A
colour on it changes no geometry; a `font-size` makes the marker wider
and pushes an inside item's text along; a `content` replaces the label
the counter would give, which is where `content: counter(list-item)`
belongs.

Chromium 141 on a 300px `ul` of `list-style-position: inside` at
16px/20px monospace starts the item's text at x 22 for a plain disc, 22
under `::marker { color: red }`, 29 under `content: "=> "`, and 43 under
`font-size: 32px`. The last is the row worth having: `li { font-size:
32px }` puts the text at 43 as well, so a 32px marker is a 32px marker
whichever rule made it one -- and the item's own text is 10px wide in
the first case and 19 in the second, which is what says they are two
different cases rather than one written twice. This engine's disc is
42px rather than 43 at that size, because its own metric is 1.3 times
the font size where Chromium's is a hair more, so the checks are written
as that agreement rather than against either number.

**The style is one lookup, not three.** The painter read the item's
style for the colour, the font size and the disc's radius; it reads the
marker's style for all three now, and because a ::marker style is
computed with the item as its parent, every inherited property --
`list-style-type`, `list-style-position`, `color` -- is already the
item's unless the rule changed it.

`:marker` with one colon is **not** a pseudo-element: only the four the
standard gives a legacy spelling are, so the selector parser now
separates the two lists and `:marker` falls through to the pseudo-class
handling, where it matches nothing. There is a check for that, because
a parser that accepted it would have passed every other check here.

**The first pixel check was reading white.** A colour changes no
geometry, so only a pixel can say a ::marker colour reached the painter
at all -- and the probe read x=10, which is past the disc. The disc
spans x 3 to 8 with its edges anti-aliased; x=5 is inside it. The engine
was right and the check was looking in the wrong place.

### The horizontal axis scrolls too

The entry above left the horizontal thumb undragged and called it "the
same three functions over the other axis". Reading the code said
otherwise, and todo.md was corrected before the work started: there was
no horizontal offset at all behind that bar. The painter translated its
clip layer by the vertical offset only, hit testing added back only
that, and nothing moved the content across -- so the bar was painted,
correctly, over an axis that did not move.

It moves now. The offset is kept beside the vertical one, by element id
for the same reason; the painter translates by both; hit testing adds
both back, so a link inside a box scrolled across is clickable where it
looks; and the horizontal thumb is found and dragged from the same
shared geometry the painter draws it with.

Chromium 141 on a 200x100 `overflow: auto` box holding a 500x50 child:
clientWidth 200, clientHeight 85 -- the horizontal bar took its fifteen
-- scrollWidth 500, and `scrollLeft` clamps to 300, which is 500 less
the 200 that is visible. This engine answers each the same.

The wheel still only scrolls a container down; a shift-wheel or a
horizontal wheel would scroll it across, and this reads neither
(todo.md).

### A draggable scrollbar thumb, and a horizontal bar for a long line

Two things todo.md named around scroll containers.

**A line of text raises the horizontal `auto` bar.** The check that
decides it walked the children and not the lines inside them, so a word
with nowhere to break overflowed its box without raising one. Chromium
141 on a 100x60 box of `overflow: auto` at 16px/20px monospace gives
`Supercalifragilisticexpialidocious` a client height of 45 -- the
fifteen pixels a bar takes -- against 60 for text that fits, and the
same 45 for a 300px child, which is the case that already worked and is
the reference the new one is read against. The walk goes to the lines
rather than to the text boxes, because a text box has no geometry of its
own here: the fragments carry their positions in document coordinates.
Both walks are asked only by a scroll container, so what they cost is
paid by the boxes that have one.

**The thumb can be taken hold of.** A press on it starts a drag, the
pointer moving scrolls the box, and a release ends it -- the pointer may
leave the bar and the thumb still follows, which is what every scrollbar
does. The box is held by node id rather than by the Box itself, because
a box tree lasts one layout and a drag outlives several.

**The thumb's geometry is one definition now.** The painter worked it
out inline and a hit test would have had to work it out again; the four
functions that place it live in the layout engine, the painter draws
from them and the pointer is tested against them, so where the thumb
looks and where it can be grabbed are the same rectangle by construction
rather than by two formulas that agree. The pixel checks that already
say the thumb is drawn in the right place pass unchanged through that
refactor, which is what says the move was faithful.

### `image-set()`, `image()` and `cross-fade()`, closing CSS Images

The three image notations the level defines beside its gradients.

**`image-set()`** chooses among candidates by resolution: the smallest
at or above this display's, and the largest below it when there is none,
so a list of only 2x and 3x still paints. A candidate is a `url()` or a
bare string, with a resolution in `x`, `dppx`, `dpi` or `dpcm` and an
optional `type()`; one naming no resolution is 1x. Chromium 141 computes
`image-set("tile.png" 1x, "red.png" 2x)` to a list whose candidates are
`1dppx` and `2dppx` and picks the first at this display's ratio, and it
normalises `96dpi` to `1dppx`, which is where that conversion comes
from. Every check is the agreement rather than a colour: the same box
with the `image-set()` and with the plain `url()` of the candidate it
should choose has to paint the same pixels.

**`image()`** takes its source the same two ways. The colour it may name
to fall back on when the source does not load would be a solid-colour
image, which nothing here can make, so it is read and dropped
(todo.md).

**`cross-fade()`** mixes two images by weight. The second is blitted
over the first at its own share, which for two opaque images is exactly
the standard's mix because the first is already down at full alpha.
Chromium implements only `-webkit-cross-fade(A, B, p)`, and its pixels
say (1 - p) of A plus p of B byte for byte: over the blue-and-green tile
and the flat red square it renders #4000bf at a quarter and #800080 at a
half. This engine agrees everywhere except where a channel lands on
exactly half of 255, which Chromium rounds up and Cairo down -- the blue
half at half and half is #80007f here against #800080 there, one unit in
one channel, and the green half agrees exactly because half of 128 is
64.

**A background layer's second image cost the pages that have no
cross-fade on them.** `cross-fade()` gives the layer two more fields,
and the painter fills its layer struct for every background layer on the
page; filling them unconditionally is two text assignments per layer.
Eleven paired samples of `features.html` -- the benchmark page that has
background images, where `generated.html` has none and could not have
shown it -- gave a best of 89 ms against 91, with every new-side reading
at or above the old side's median. Behind the per-document flag that
says a page named a cross-fade at all, the two series interleave.
benchmarks.md carries both.

**Three of the notations' tests were wrong before the engine was.** A
style attribute quoted with quotation marks ends at the first quotation
mark inside it, and `image-set("tile.png" 1x)` carries two; the parser
had been right about all three forms while the fixture was feeding it
half a declaration. The attribute is quoted with an apostrophe now,
written as its code point because a Festina string literal is delimited
by one and has no escape for it.

### The `lh` and `rlh` units

`lh` is the element's own computed line height and `rlh` the root
element's (Values and Units 4 §6.1). Chromium 141 on a document whose
root is 16px/20px: `line-height: 30px; width: 2lh` is 60px,
`width: 2rlh` is 40px, `margin-left: 1.5lh` beside a 30px line height is
45px, and `calc(1lh + 10px)` is 40px. This engine now answers each of
them the same.

**The unit is resolved where the length is parsed**, which works because
the cascade computes `line-height` before every other length: the unit
reads a global that is already set by then. The same global still holds
the *parent's* line height while `line-height` itself is being computed,
which is what the unit means there -- `line-height: 2lh` under a 20px
parent is 40px in Chromium, the way `em` inside `font-size` means the
parent's font size. A font size of the element's own does not change an
inherited line height, so `font-size: 32px; width: 1lh` under an
inherited `20px` is 20px, not 40.

`line-height: normal` declares no length, so `lh` there is whatever a
line box actually comes out at. That number lived in the layout engine
and the cascade cannot reach it from where a unit is parsed, so
`lineHeightOf` and the 1.2 it multiplies by moved to `style.f`, beside
the Style they read -- one definition rather than two that must agree.
`1lh` under `normal` at 16px is 19px here and 19px in Chromium.

**The first version of it cost two milliseconds on a page with no `lh`
on it**, and the rule that predicts why is already written down:
`lineHeightOf` takes a `Style`, the cascade called it twice per computed
style, and a forwarded struct parameter is released on exit with a
collector walk of its subtree (FINDINGS.md, "cycle trials"). The
function is now two: one over the two ints it actually reads, which is
what the cascade calls, and the `Style` form that calls it, which is
what the layout engine keeps. benchmarks.md carries both paired series.

### `revert`

The keyword rolls a property back to the value the previous cascade
origin gave it (Cascade 4 §7.4) instead of behaving as `unset`.
Chromium 141 on the same markup, read off `getComputedStyle`: with
`b { font-weight: normal }` in the author sheet, a reverted `<b>` is 700
against a plain one's 400; with `span { display: block }`, a reverted
span is `inline`; with `li { list-style-type: square }`, a reverted `li`
is `disc`. A reverted `color` on a paragraph is black, because the
user-agent sheet declares none and the rollback falls through to the
inherited value -- which is the row that tells a rollback from a no-op.

**The bookkeeping is one map copy, at one point.** The matches arrive
sorted, so the user-agent origin's declarations are exactly those before
the first weight at or above the origin boundary; copying the property
map there is the whole of it. An important user-agent declaration ranks
above every author one and so wins outright, which is why the rollback
never has to reach past one. A page that never says `revert` does not
take the copy at all.

Resolving the keyword after every declaration has been applied, rather
than at each one, is what makes it reach a shorthand: `applyDecl` has
expanded the shorthand into longhands by then, and each of those carries
the keyword. `all: revert` is the one that cannot work that way, because
`all` drops the map it would be resolved from, so it puts the previous
origin's declarations back where the drop took them away.

`display: revert` needed the one property that is validated where it is
applied to let a CSS-wide keyword through -- `display` is checked there
because by then the declaration it beat is gone. Letting them through
turned up `display: inherit`, which had been dropped with the invalid
values and now takes the parent's display, as Chromium does: a span
under an `inline-block` parent computes to `inline-block`. `initial` and
`unset` were already right, because the initial value of `display` is
`inline` and that is also the fallback a missing declaration takes.

### `::first-line`

The pseudo-element restyles whichever characters end up on the first
line of a block (CSS Pseudo-Elements 4 §3.2), metrics included: on a
200px paragraph of ten words at 16px/20px monospace,
`font-size: 40px; line-height: 50px` gives Chromium a paragraph 90px
tall -- a 50px first line and two 20px ones -- against 60 for the same
paragraph with no rule, and this engine now agrees.

The standard describes the rule as a fictional element wrapped around
the line's characters, and taking that literally is what made the
descendants work: after the subtree has its ordinary styles, the cascade
walks it a second time with that fictional element as the root's parent,
so a bold span on a red first line computes to bold and red and the same
span on the second line stays bold and black. The style cache keys on
the parent's serial, so the second walk shares nothing with the first by
accident.

**The line's fragments carry the style by pointing at a stand-in box.**
The alternative was a style field on `Fragment` and a test at each of
the eight places that ask a fragment for its box's style -- three in the
line metrics, three in hit testing, two in the painter. A stand-in box
built once per text box, holding the first-line style and the same node,
needed none of those: every reader already asks the box. What it does
need is that measurement follow the line, because a word measured in the
first line's font may not fit and then belongs to the second in the
element's own -- so the word is measured again after the break.

Where a block has both inline and block-level children its inline runs
sit in anonymous boxes, and the rule belongs to the first of them and to
no other. Chromium gives such a div 110px -- 50 for the styled first
line, then 20, 20 and 20 -- and 80 with no rule.

`::first-line` had been making its whole rule unusable in the selector
parser, which is where this started.

### Subgrid

A grid item that is itself a grid can take its tracks from the lines of
its parent that it spans, rather than sizing tracks of its own, so the
two levels line up (CSS Grid 2 §3). The parent hands the sizes down when
it lays the item out, where they are known, together with the gap that
separates them; the item's own template is replaced by tracks of exactly
those sizes.

**The substitution has to happen before the items are placed, not
after.** The first version put the sizes in where the tracks are sized,
which is after the placement pass -- and the placement pass wraps the
flow at the number of tracks there are, which for a subgrid's own
(empty) template is none. Every child landed in a row of its own, and
the checks that said so are the three that failed.

Against Chromium on a 300px grid of 100, 150 and 50 with rows of 40 and
60: a subgrid spanning all of it puts its children at 0, 100 and 250,
100, 150 and 50 wide, 40 then 60 tall; one spanning the second and third
columns gets 150 and 50, starting at 100.

### The units of Values and Units 4

`q`, a quarter of a millimetre; `vi` and `vb`, the inline and block
axes, which a horizontal writing mode makes the horizontal and the
vertical; the small, large and dynamic viewport units, which are three
names for this viewport because nothing here slides away to tell them
apart; `ic`, an ideograph's advance, which is an em in every font this
engine can load; and `cap`, taken as three quarters of an em, which is
what Chromium measures for the monospace face here.

`40q` is 38 pixels and `100q` is 94, both Chromium's own answers -- the
first version of the conversion carried 0.945 rather than the exact
0.94488, and `100q` came out a pixel wide of it.

The checks for the units this browser can only answer one way ask the
two spellings to agree rather than asking for a number, because what
they are testing is that a page written in either gets the same box.

**css-2026.md's units row was wrong about angles**: it called them all
missing where `deg`, `grad`, `rad` and `turn` are read wherever an angle
is taken. `lh` and `rlh` are the ones still missing, and they need the
line height threaded into the length parser.

### A scroll container scrolls

The wheel over a scroll container scrolls that container; over anything
else, or over one that has reached its end in the direction asked for,
the page takes it, which is what makes a scrollable box inside a page
usable at all.

The offset is kept by the id of the element rather than on the box,
because a box tree lasts one layout and a scroll position has to outlive
several. The painter carries it in the clip layer's own transform, so
the content moves and the box, its background and its scrollbars stay
where they are; the thumb sits as far down its track as the content is
through what there is of it; and hit testing adds the offset back, so a
link inside a scrolled box is clickable where it looks rather than where
it was laid out.

**Two struct values cannot be compared with `==` in Festina** -- the
comparison against `null` is special-cased and the general one emits
LLVM IR that will not parse. FINDINGS.md finding 37 has the six-line
reproduction and festina.md §3r the proposal; the test that
`scrollContainerAt` answers the right box compares the element behind it
instead, and says so.

### `overflow: scroll` and `auto`

The two values that show a scrollbar. `overflow-x` and `overflow-y` are
separate properties now rather than one boolean -- the cascade folded
both into `overflow` and kept only whether it said `hidden` -- with the
standard's rule that a `visible` beside a value that is not `visible`
computes to `auto`, so a box cannot clip one axis and let the other
spill.

A scroll container's scrollbar is drawn inside its padding box and takes
its room from the content, which is fifteen pixels here because that is
what Chromium's classic scrollbar takes and it makes the geometry
comparable: a 200px box shows its content 185 wide. `scroll` reserves it
whether or not there is anything to scroll; `auto` reserves it only
where the content overflows, which is not known until the content has
been laid out, so those boxes lay their content out a second time.

The bars are painted in Chromium's own colours -- a #fcfcfc track and a
#8b8b8b thumb -- and the thumb is as long a share of the track as the
box is of what it scrolls, with no thumb at all where there is nothing
to scroll, which is what Chromium draws. Our row of pixels across the
right edge reads content to 184, track to 188, thumb to 195 and track to
199; Chromium's reads the same, with a #c3c3c3 pixel at each end of the
thumb that is its rounded corner.

Only a scroll container pays for any of it: the walk that measures what
there is to scroll is behind the flag that says a bar was reserved.

**A horizontal `auto` bar is raised by a child box reaching past the
edge, not by a line of text doing it.** todo.md says so.

### A percentage height resolves against a definite containing block

CSS2 §10.5: a percentage height is that share of the containing block's
own content height, and computes to `auto` where that height is not
itself definite. This engine ignored percentage heights altogether --
`height: 50%` inside a 100px box laid out as tall as its content -- while
percentage widths had always worked. `min-height` and `max-height` take
percentages the same way and were the same: lengths only.

The containing block's definite content height is a global the layout
saves and puts back as it recurses, rather than a parameter every one of
the dozen calls that lay out children would have to carry. A box whose
own height is definite -- a length, or a percentage of a containing
block that is itself definite -- stands as that block for its children,
so the chain resolves: 50% of 50% of 100px is 25.

Against Chromium on the same markup: 50 for half of a 100px box, the
content's own height where the parent has none, 50 and 25 down a chain
of two, 50 where the parent's padding sits outside its declared height
and 40 where `border-box` puts it inside, and 100 for a `height: 100%`
child that is itself `border-box` with padding and a border.

It was found writing the tests for `overflow: scroll`, where the
scrollbar's effect on a `height: 100%` child is how Chromium shows the
content box shrinking.

### A reverse flex direction packs against the far edge

`row-reverse` and `column-reverse` run the main axis the other way, so
the main-start edge is the right one (or the bottom) and
`justify-content: flex-start` packs the items against it. This engine
reversed the sequence and laid it out from the near edge, which put the
items in the right order and the free space on the wrong side: a
`row-reverse` row of two items sat at the left edge where Chromium puts
it at the right, and `flex-end` sat at the right where Chromium puts it
at the left. The items are laid out forwards now and each position
mirrored against the line's own extent, which is one operation for both
the order and the packing.

It came out of writing a test for `order`, which todo.md listed as
missing and which turned out to be implemented, with no test of its own:
five checks of the sort and its stability pass unchanged, and the three
about `row-reverse` beside them did not.

### A flex item does not shrink below what its content needs

Flexible Box 1 §4.5 gives an item whose `min-width` is `auto` -- the
initial value -- an automatic minimum size: the smaller of its declared
width and its content's own min-content width. This engine shrank an
item to whatever the container left, so an unbreakable word was cut
where it should have pushed the item past the container's edge. A
declared `min-width` takes the minimum away, and so does the item being
a scroll container, whose automatic minimum the standard puts at zero
because the content can scroll instead.

The flexible lengths are resolved as §9.7 says now: the space is handed
out in proportion, every item is clamped to its own minimum, the clamped
ones are frozen and the rest of the shrinking is handed out again --
which is what makes an item that cannot shrink further push the
shrinking onto its neighbours rather than swallowing it.

**`computeIntrinsic` was keeping two different numbers in one field.**
A declared `width` replaced the content's min-content in `minContent`,
so an item with `width: 200px` reported a minimum of 200 where §4.5
wants the smaller of the declared width and what the content needs. The
two are separate fields now, filled in the same pass.

**Two of the three things todo.md listed as missing here already
worked**: `flex-basis: content`, and a flex container as an item of
another. Both were checked against Chromium's geometry on the same
markup before anything was written, which is why no code was written
for them.

### An inset box-shadow's blur is the same Gaussian, from the other side

The inside of a blurred shadow is the outside of its hole: where an
outer shadow's alpha is the two axes of the Gaussian multiplied, an
inset one's is one minus that. Painting `1 - fx` and then `1 - fy` over
it accumulates to exactly that -- one minus (1 - (1 - fx)) times
(1 - (1 - fy)) is one minus fx times fy -- so an inset shadow is two
passes of plain strips, with no per-pixel work and not even the ramp
images an outer shadow's corners need. Sixty cards with an
`inset 0 0 12px rgba(0,0,0,.5)` paint in 2 ms against the 1 to 2 ms the
frames it replaces took, and the binary grows 40 bytes.

Two passes only accumulate to the right answer at full alpha, so a
shadow that is not fully opaque is painted into an image at full alpha
and that image blitted at the alpha it wanted -- which is also what
keeps the strips inside the padding box, since the canvas has no clip
region.

Against Chromium's pixels on a 60x40 box with `inset 0 0 20px red`:
0.482, 0.169, 0.031 and 0.706 of red where the Gaussian's own answers
are 0.504, 0.186, 0.048 and 0.730. Each of Chromium's is a little under
the Gaussian, the same way its outer shadow was, because three box
blurs spread a little wider than the Gaussian they stand in for.

### An outer box-shadow's blur is the Gaussian the standard asks for

Backgrounds and Borders 3 §7.1 asks for a shadow blurred by a Gaussian
whose standard deviation is half the blur radius. The painter drew
nested rectangles at a small alpha each and let the alpha accumulate,
which reached full opacity against the shadow's own edge where the
standard asks for half of it, and gave a corner an edge's value where
the standard asks for the two multiplied.

A Gaussian blur of a rectangle has a closed form, so it is computed
rather than filtered: along one axis the alpha is the difference of the
Gaussian's own integral at the two edges, and the whole of it is the two
axes multiplied. `gaussIntegral` is Abramowitz and Stegun 7.1.26, whose
error is below 1.5e-7 -- a thousandth of the 1/255 a painted pixel can
tell apart.

**A separable blur is a product, and `drawImage` multiplies by
`fillAlpha`.** Working each corner out a pixel at a time cost 91 ms on a
page of 60 differently coloured shadows. One axis is a one pixel tall
image instead, blitted once per row at the other axis's own share, so
the shadow costs a row of work per pixel of the reach rather than a
pixel of work per pixel of it: the same page is 5 to 7 ms, against 3 ms
for the nested rectangles it replaces, and a page of 60 boxes sharing
one shadow is 3 ms against 2. The ramps are cached by everything the
answer depends on, so a page whose boxes share a shadow builds each
once.

The expectations are the closed form's own numbers, with Chromium's
pixels beside them: for `box-shadow: 0 0 20px red` on a 60x40 box, this
engine and Chromium agree on the corner to the byte, and differ by one
or two parts in 255 along the edges, which is Chromium's approximation
rather than the standard's Gaussian -- it blurs with three box blurs.

**The test's first version was wrong where the engine was right.** It
expected half the colour half a pixel past the edge, which is what a
blurred *edge* leaves; the box is four standard deviations tall, so its
two horizontal blurs overlap through the whole of it and the middle row
keeps 0.954 of the vertical term, not 1. The closed form says so and
Chromium's pixels agree with it.

### A background tiled at a scaled size has hard edges and no seam

A scaled blit samples half a source pixel past the rectangle it fills,
and with nothing there it fades to transparent. `background-size` drew
each tile as its own scaled blit, so the tile's edge blended into
whatever was under it and two tiles side by side showed a band of the
box's background between them -- five pixels of it at a ten times
enlargement. The image is now padded and scaled once, and every tile is
that one image blitted unscaled.

Which edge the padding copies is what the next tile will be: an axis
the background repeats on takes its padding from the opposite edge, so
the tiles blend into each other exactly as one continuous tiling would,
and an axis it does not repeat on takes its own edge, so the tile ends
in its own colour. Against Chromium's pixels, read with
`tests/chromium.py pixels`: a `no-repeat` tile of the 10x10 fixture
scaled to 100px is `#0000ff` at its first pixel and `#008000` at its
last, with the background beginning exactly at 100; repeating, the row
repeats exactly every 100 pixels and the blend across the boundary is
this engine's `#0007f1` against Chromium's `#0006f2`.

### border-image scales its edges to the border, and rounds and spaces them

Backgrounds and Borders 3 §6.5 scales every edge image to the thickness
of the border it fills before anything is tiled: the top edge's height
becomes the top border width and its width is scaled by the same
factor. This engine tiled each region at its own natural size, so
`border-image: url(nine.png) 3 repeat` in a 30px border laid down ten
3px tiles where the standard lays down exactly one 30px tile. The
fixture hid it -- a 3px slice in a 10px border is the one case where
the scaled tile fills the edge exactly -- and the test that was meant
to catch it asked whether a repeated edge shows more of the source's
white column than a stretched one, which was a statement about this
engine rather than about the standard.

With the tile the right size, `border-image-repeat`'s four values are
what differ about filling the edge with it: `stretch` pulls one tile
across, `repeat` centres whole tiles and lets the two ends cut a tile
each, `round` resizes the tile until a whole number of them fits
exactly, and `space` lays down only whole tiles and shares the leftover
into gaps around them -- one before the first, one after the last, one
between each pair -- drawing nothing where not even one tile fits. The
property takes two of them, one for the horizontal edges and one for
the vertical.

**A scaled blit has a seam, and tiling made it visible.** Cairo samples
half a source pixel past the rectangle it fills, and with nothing there
it fades to transparent: at a ten times enlargement that is five pixels
of the page showing through between one tile and the next, and between
a corner and the edge beside it. Each region is now padded with a copy
of its own edge pixels and scaled with that padding falling outside the
tile, and every tile of one size is that one image blitted unscaled --
so a tiled edge repeats exactly, which is what the test asks of it.

**The expectations come from Chromium's own pixels.** `tests/chromium.py
pixels` rasterizes a page and prints a row of it, and the runs of
colour this engine paints along a tiled edge now match Chromium's
exactly on every case in the test: the tile boundaries at 52.5 and 82.5
where `repeat` centres three tiles in 75 pixels, the three 25px tiles
`round` fits into the same edge, and `space`'s three five pixel gaps at
30-34, 65-69 and 100-104.

### Chromium's pixels are readable after all

The full `chrome` binary in this container writes a screenshot whose
first scanline is correct and whose every other row is blank, which is
why everything graded in pixels here was graded against a
specification's own algorithm instead. The Playwright `headless_shell`
binary beside it rasterizes the whole page. `tests/chromium.py pixels`
runs that one, decodes the PNG with zlib and the format's own five
filter types -- no library this project is not allowed -- and prints a
row as `x:rrggbb`, so a painting question has a browser's answer to be
graded against.

### Several background layers on one box

`background-image` takes a comma-separated list, and every other
background longhand takes one too: the i-th value goes with the i-th
image, and a list shorter than the images repeats from its start
(Backgrounds and Borders 3 §3.10). The layers paint back to front in the
**reverse** of the order they are written, so the first written is on
top, and the colour goes underneath them all — clipped by the *last*
layer's `background-clip`, which is what the standard says and what the
one-layer code was already doing by accident.

**The first layer stays in the fields it was always in.** Turning the
eleven background fields of `Style` into arrays would allocate for every
distinct style on every page, and almost every page has one background
or none; instead `bgExtra` is a shared empty list until a page declares
a second layer, and the painter reads one reusable `BgLayer` that is
filled from the style or from the list. A box with no image of its own
does not even pay for that fill.

Layer 0 and the rest go through the same parsing functions, called with
their own slice of each list, so the first layer and the others cannot
drift apart — the failure that this file records for `styleDigest` and
for `@supports`.

**`background-position` had to learn about commas.** It is expanded into
`background-position-x` and `background-position-y` where it is applied,
so cascade order between shorthand and longhand can be honoured, and
that expansion split on spaces: `0 0, 20px 0` became an x of `0` and a y
of `0,`. It splits on layers first now and hands each longhand a list of
its own.

Two Festina traps on the way: assigning to a field of an array element
writes to a copy, so the resolved url has to be written back into the
list; and a local named `layers` resolved to a *test's* function of that
name, because the namespace is global across every imported file
(FINDINGS.md, finding 9) — the compiler's message was that `length` is
not a field of `func[text]:void`.

9,672 bytes. Paint is 8 ms either way on the benchmark page, which has
no background image on it.

### `all`

One declaration setting every property to a CSS-wide keyword (Cascade 4
§3.2). It overrides everything written before it in the same block, so
those declarations are dropped where it is expanded, and the ones after
it are applied over the top — which is the whole of what makes
`all: initial; color: red` red and `color: red; all: initial` black.

`initial` computes the element as though it had no parent, which is what
every default in `computeStyleValues` already means by "root"; the
declaration is recorded and the `isRoot` it asks is widened. `unset` and
`revert` need nothing beyond the dropping, because taking the parent's
value for an inherited property and the initial value for every other
one is what the ordinary cascade does. `direction` and `unicode-bidi`
are left alone, as the standard requires: they carry the document's
meaning rather than its presentation, so the reset asks `isRootIn`
rather than the widened `isRoot`.

**`all: inherit` is not honoured**, and the reason is worth recording:
giving a *non-inherited* property the parent's value means copying the
parent style field by field, and a hand-written list of a struct's
fields is exactly what rotted in `styleDigest` — the list that scored
`object-fit` as unimplemented while it worked. What it does instead is
the half that costs nothing: the declarations before it are dropped, so
an inherited property still arrives and a non-inherited one takes its
initial value. todo.md carries what the other half needs.

### A `border-radius` in percentages, and corners that are ellipses

`border-radius: 50%` rounded nothing: a percentage radius was parsed,
found not to be a length, and dropped. It is the common spelling — a
pill, a circular avatar — and it needed the radii to stop being pixels
in the computed style, because a percentage is of the box and the box is
not known until paint time. The four ints are now eight `Len`s, resolved
against the border box when it is painted: the horizontal radius against
its width, the vertical against its height (Backgrounds and Borders 3
§5.1).

With both axes in hand the elliptical form follows. `border-radius:
20px / 5px` gives every corner a wide shallow curve rather than a
quarter circle; the horizontal radii are written before the slash and
the vertical after, and a longhand takes the pair directly
(`border-top-left-radius: 20px 5px`). The path was already Bézier
curves with the kappa approximation, so an ellipse is the same control
points with two radii instead of one.

**Overlapping radii are scaled, not clipped** (§5.5). Where two on one
edge add up to more than the edge, every radius is divided by the same
factor until they fit, so the shape keeps its proportions — which is why
`border-radius: 60px` on a 40px box is exactly `border-radius: 20px`,
and the test says so by painting both and counting.

9,088 bytes.

### `line-break: anywhere`, and `image-rendering` declined

`line-break` (CSS Text 4 §5.2) says how strictly a break may fall around
punctuation. Three of its four values — `loose`, `normal`, `strict` —
differ only in the CJK rules they loosen or tighten, and this engine has
none of those, so they leave the line where it was. `anywhere` is the
one that says something here: a break may fall between any two
characters, which is the permission `word-break: break-all` already
carries. The two must therefore break a long word in the same number of
lines, which is the check, and neither of the numbers in it has to be
known in advance. 209 to 210 properties, `line-break -> wordBreaking`,
and `supportedProperties` learned the name so `@supports` agrees.

**`image-rendering` is declined, and the reason is a new finding.**
`drawImage` scales bilinearly and nothing can ask for anything else: a
32x upscale of a two-pixel image puts a blend in 32 of the 64 pixels
across the seam, and no argument, image field or canvas state changes
it. Cairo has the control (`cairo_pattern_set_filter`); the runtime does
not expose it. FINDINGS.md finding 36 has the reproduction and
festina.md §3q the proposal. Storing the keyword would move the count
and change no pixel, which is the `outline-style` mistake this project
has already made once.

### Interpolation hints, and the degenerate ellipse the standard mirrors

A bare position between two colour stops is not a stop: it is an
interpolation hint (Images 3 §3.4.4), saying where the colour halfway
between them falls. The ramp either side follows the standard's curve,
`weight = P ^ (log 0.5 / log H)`, and a hint exactly in the middle is no
hint at all — which is the check that depends on the formula being right
for nothing: the hinted and unhinted gradients must agree pixel for
pixel. Before this, a component with a position and no colour made the
whole gradient invalid.

`radial-gradient(100px 0 at 50% 50%, ...)` is the one degenerate ending
shape the standard does not turn into a solid fill: an ellipse with zero
height and a width of its own renders as a linear gradient **mirrored
about its centre**, and it now does here. The other degenerate shapes —
a zero width, both radii zero — stay a fill of the last stop, which is
what a gradient line of zero length comes to.

That leaves `image()`, `image-set()` and `cross-fade()` of CSS Images 3,
which are notations for choosing between images rather than for drawing
one.

4,256 bytes for both.

### `conic-gradient()` and `repeating-conic-gradient()`

A conic gradient gives every point the colour of its own angle about a
centre, clockwise from pointing up, whatever its distance. The stop list
means a fraction of the turn rather than of a line, so the stop
machinery is shared unchanged: a position may be an angle in any of the
four units or a percentage, and `90deg` and `25%` are the same place —
which is the check that depends on no number being known in advance.
`from <angle>` turns the sweep and `at <position>` moves the centre.

**A wedge is not a rectangle**, so it is drawn a row at a time, and the
row's span is computed rather than searched for: a ray at angle `a` from
the centre meets row `ry` at `x = cx - (ry - cy)·tan a`, and only when
it points at that row at all. One tangent per wedge edge, taken once for
the whole box, then gives every row's span by a multiply — no `atan2`
per pixel, and every rectangle covers whole pixels, which is what keeps
abutting wedges from being blended into stipple.

**The first version painted every box the colour of its last wedge.** A
wedge neither of whose edges points at a row does not cover any of it;
that version gave it the whole row instead, and the last wedge painted
over everything before it. The rule is that one edge reaching means the
wedge straddles the horizontal and runs off the row on the side it leans
to, and neither edge reaching means the wedge is not on this row.

The gradient benchmark grew a fourth page for it. A conic sweep costs
about what an off-axis linear gradient does — 12 ms of painting against
14 for the same sixty 760x60 boxes — which is the answer the geometry
predicts: both draw one rectangle per band per row. 8,632 bytes.

### `repeat(auto-fill)`, `repeat(auto-fit)` and dense packing

How many times an auto-repeat group repeats depends on the space the
container turns out to have, so it cannot be expanded when the template
is parsed. The track list keeps one copy of the group and where it sits;
layout expands it, with the count the standard's largest N that does not
overflow — `N = floor((S - F - (K-1)·gap) / (G + L·gap))`, never less
than one, and one where the axis has no definite size at all.

`auto-fit` counts the same way and then collapses every track of the
repeat that no item occupies. **The gutters go with them**: Chromium 141
on a 300px grid with a 20px gap and `repeat(auto-fit, 60px)`, holding an
item in the first track and one at `grid-column: 4`, reads
`60px 0px 0px 60px` and puts the second item at x = 80 — one gutter past
the first, not three. A run of collapsed tracks and the gutters between
them comes to one gutter.

`grid-auto-flow: dense` starts each item's search at the beginning of
the grid instead of at the cursor, so a hole an item too wide for the
rest of its row left behind is filled by a later one. Sparse packing,
which never moves the cursor backwards, leaves it: measured both ways
against Chromium on a two-column grid holding a cell, a cell spanning
both columns, and a cell.

4,656 bytes, and no measurable time: five alternating best-of-3 samples
of the feature page give 121 to 124 ms before and 121 to 123 after, the
same best on each side.

### The grid track sizing functions

A track is a pair of sizing functions, a minimum and a maximum (Grid 1
§7.2), and until now this engine kept one: a length, an `fr`, or `auto`.
It now keeps both, and `minmax()`, `min-content`, `max-content` and
`fit-content()` all say what they mean. `auto` is minmax(auto,
max-content), `100px` is minmax(100px, 100px), `1fr` is minmax(auto,
1fr) — so `TRACK_AUTO` is zero, and the track `trackAt` hands back past
the end of a template is `auto` on both sides without having to say so.

Sizing follows the standard's order rather than one pass. Each track
gets a base size from its minimum and a growth limit from its maximum,
both read off the largest contribution of the items that sit in it
alone. Then the free space is handed out three times: every track grows
towards its limit in equal shares, each freezing as it arrives (§12.5);
the `fr` tracks take what the others left, never below their own base
(§12.7); and what is still spare, where nothing flexible took it,
stretches the tracks whose maximum is `auto` (§12.8). Where the free
space is indefinite — a row axis with no height to fill — a track whose
maximum is a definite length takes that length.

Every expectation is Chromium 141's, read off
`getComputedStyle().gridTemplateColumns`, which reports the used sizes
in pixels. The item in the fixture holds two 60px inline-blocks, so its
min-content contribution is 60 and its max-content 120 whatever the font
does, which is what makes the two functions tell each other apart.

**The stretching step changes what was there.** `grid-template-columns:
auto 100px` in a 300px grid used to leave the auto track at its content
size; Chromium gives it the 200 the fixed track leaves, and now so does
this. `justify-content` does not position tracks here, so the `normal`
that stretches and the `start` that does not cannot be told apart —
todo.md carries it.

It costs 4,264 bytes. What it costs in time cannot be read at this size:
the feature page, which has 48 grids on it, goes from 123–125 ms to
125–126 end to end, and `generated.html`, which has no grid at all and
so runs none of this, moves by the same 2 ms in the same direction. Two
series that differ by the noise floor say nothing about the feature.

### A grid item placed past the explicit grid hung the layout

`<div style="display:grid;grid-template-columns:100px"><div></div>
<div style="grid-column:2"></div></div>` never finished laying out. The
auto-placement search wraps the flow at `flowLines`, which counted the
explicit tracks only, so the second item's column — index 1 in a grid
one column wide — was a cell `gridRunIsFree` calls occupied for every
row there is, and the loop looking for a free one had no exit.

A line named past the explicit grid creates implicit tracks (Grid 1
§8.1), so the flow wraps at the whole grid: `flowLines` now takes the
definite placements into account as well as the template. The fix was
found writing the track-sizing tests, which put a probe item in a second
track that some of the templates did not declare.

**An item that names a column moves the cursor to it**, which came out
of the same fixture. Chromium 141 on a one-column grid with the first
item at `grid-column: 2` and the second placed automatically puts the
second at the start of the *second row*, not in the cell the first
skipped; the standard says so too (§8.5, step 4: an item naming a line
sets the cursor to it). This engine went back for the skipped cell.

### `content: url()` on an ordinary element

CSS Content 3 §2.1: a `content` naming an image replaces the element's
contents with it, which makes the element a replaced element. Its own
box properties still apply — the background, the border, a declared
width and height — and its children are not rendered, the same rule an
`<iframe>`'s children already followed. The count goes from 208 to 209,
and `--fields` says the field that moved is `content -> contentUrl`.

Chromium 141 on `fit.png`, which is 20x10, in a block 300 pixels wide:
`content: url(fit.png)` gives 300x150, the image's 2:1 ratio, exactly as
an `<img>` of that width would; with a declared 50px square it is 50x50;
on an inline element it is 20x10, the natural size. **A string replaces
nothing there** — `content: "just a string"` on a div renders the div's
own text — so only a `url()` fills the new field, and `none` and
`normal` leave it empty.

The pair of checks worth having is the one that does not depend on a
number: a string and no `content` at all must land on the same geometry,
because neither replaces anything.

It costs nothing to a page that does not use it. The lookup is one map
read per *distinct* computed style — 24 of them on the benchmark page,
not 2,728 — and six alternating best-of-3 samples give 130 to 133 ms
against 130 to 134 for the revision before it. The binary is the same
size to the byte, 2,737,728, which was checked rather than assumed: the
two hash differently (`756c6fe5` against `e2a09826`), so they are
different programs that round to the same size.

### Looking for an image cost the pages that have none

The first thing the second benchmark page measured was not a feature.
Its phase list beside `generated.html`'s showed `images: 2 ms` on a
document with no `<img>` in it: two milliseconds of walking 2,728
elements to find nothing. Two more walks went unreported beside it,
because resolving `<iframe>` and `<frame>` is not a timed phase and
searched the whole tree for each of the two tags.

`newElement` is the one place a node with a tag is made, so it answers
"is there an image in this registry" and "is there a frame" for a
comparison it makes once per element, and all three walks are skipped on
a document with neither. The flags clear with the node registry they
describe, which is the right lifetime: a framed document shares that
registry deliberately, so the answer is about the registry and never a
claim about one document — it can be true where a walk would find
nothing, which costs a walk, and cannot be false where a walk would have
found something, which would lose an image.

About 3 ms of 136 end to end on `generated.html`, six alternating
samples apiece with no overlap between the series. The rendering phases
do not move, because none of the three walks was inside them.

`tests/unit/test_images.f` is the check that no insertion path gets past
the flag: an image in the body, one foster-parented out of a table, one
beside foreign content, and one in a document loaded into a frame, each
naming a different file because `loadedImages` is a cache that outlives
a page and a second case naming the first case's file would pass either
way.

### A second benchmark page, and a check that it measures anything

`generated.html` — the page every figure in benchmarks.md is taken
against — is headings, paragraphs, lists and tables. It has no `<img>`,
no counter, no grid, no multi-column container, no transform and no
form control, so six features landed in a row whose cost no run here
could show. `features.html` is a second page carrying all six, measured
beside the first rather than replacing it: a new page is a new control
the same way a new reference browser is, and replacing this one would
have thrown away every number in the file.

Its control, `features-plain.html`, is the same markup and the same
element count with a stylesheet that turns each feature off. The two
differ by about 10 ms end to end, most of it layout, and both series'
spreads are recorded beside the difference because subtracting two
numbers near 120 is how this file has misled before.

**The page's first version did not exercise two of the things it
claimed to.** The form controls sat below the probe canvas, and the
image's natural size was exactly its box's size — which makes `fill`,
`cover` and `contain` paint identical pixels, so `object-fit` was in
the stylesheet and in none of the measurements. Both were found by
asking the page rather than by reading it: `tests/featurepage.py
--verify` renders it, renders it again with each feature turned off by
an appended rule, and requires the render to change. `tests/bench.sh`
runs that before any table and fails the run if a feature is dead.

### `appearance`, `accent-color` and `field-sizing`

Three properties of CSS Basic User Interface 4, taking the count from
205 to 208. Each moved its own field: `appearance -> appearanceAuto`,
`accent-color -> accentColor`, `field-sizing -> fieldSizingContent`.

**A text input was fourteen pixels wide.** Every form control here was
shrink-wrapped to its content, so an empty one was the width of its
padding and a full one grew with what was typed. `field-sizing` is the
property that names the difference: the initial `fixed` makes a field as
wide as its `size` attribute says, or twenty characters, whatever it
holds, and `content` is the sizing this engine had. So the property
arrived and a visible bug went with it.

**`appearance`'s initial value is `none`, not `auto`.** The first
version of this stored a flag meaning "is it none", which is inverted
against the specification, and the instrument said so at once: the
property could not register, because the row declares `auto` and an
unset element already read as not-none. The user-agent stylesheet is
what puts `auto` on the controls it draws, and the flag names that.

That correction is the whole of why `appearance: none` can take a
checkbox's size away. The thirteen-pixel square is not a declared width
any more but an intrinsic size applied in layout, because a
presentational hint is a declaration and `appearance` has no way to undo
one. A checkbox with `appearance: none` is 0 by 0, as it is in Chromium
141; one with a declared width keeps it.

`accent-color` colours the mark a checked control draws. The chrome here
is this engine's own rather than a copy of any browser's, so the accent
colours the mark it does draw rather than trying to reproduce a native
one.

### `column-fill` and `hyphenate-character`

Two properties off the measured work list, taking the count from 202 to
204 on `column-fill -> columnFillAuto` and
`hyphenate-character -> hyphenChar`.

`column-fill: auto` (Multi-column 1 §3.3) fills each column to the
container's height before starting the next -- so with no height to fill
to there is nothing to break at, the content stays in the first column
and the container grows instead. Chromium 141 gives twelve 20px blocks
one 240px column that way, against three columns of 80 when balancing,
and the two agree exactly once a height is declared. That agreement is
the second half of the check: it is what tells a `column-fill` that
works from one that has simply switched balancing off.

`hyphenate-character` (CSS Text 4) names the string a hyphenation break
draws instead of a hyphen. It is inherited, and it counts towards the
width of the prefix that has to fit, so a longer one can move the break.
It is stored empty for the initial `auto` rather than as `"-"`, so a
page that never declares it inherits a zero value and allocates nothing.

### `object-view-box`

CSS Images 4, and the property count goes from 201 to 202 on
`object-view-box -> objectViewBox`.

A rectangle over a replaced element's own pixels, which becomes its
natural size: `object-view-box: inset(0 5px 0 0)` on a ten-pixel-square
image makes it five by ten, and `object-fit` then fits that rectangle
rather than the whole image. All three spellings work -- `inset()`,
`rect()` and `xywh()` -- and the checks assert that they paint the same
picture rather than that each matches a number, which is the only thing
that could catch one of the three being read in the wrong order.

The terms stay unresolved in the computed style, because a percentage is
of the image's size and the image may not have loaded when the style is
computed.

A view box reaching outside the image is empty there rather than
repeating an edge. That falls out of how the region is cut: the canvas
cannot take a source rectangle (FINDINGS.md 30), so the region is
blitted into a blank image at a negative offset -- which `border-image`
already did -- and whatever lands outside is simply never drawn.

`object-fit: fill` needed its own path. It scales the two axes by
different amounts and `objectFitScale` answers with one number, so the
fill case blits directly; it now blits the cut region instead of the
whole image, which is the only change that case needed.

The test was wrong before the code was. It read pixels two from each
edge, which is inside the smoothing band when a five-pixel view box is
stretched over forty -- an eight-fold upscale where the suite's other
image checks do four. The feature was working; the sample points were
in the blend. They are ten pixels in now, with the reason written
beside them.

### `grid-template-areas` and named grid lines

CSS Grid 1 §7.3 and §8.3, and the property count goes from 200 to 201 on
`grid-template-areas -> gridAreas`. This was the largest of Grid's
remaining holes.

A template is one string per row, each cell a name or a `.` for no area.
The strings say how many rows and columns the explicit grid has, whether
or not a track list sizes them, so `grid-template-areas: 'a a' 'b b'`
alone gives a two-row grid. A template whose rows are of unequal length,
or in which a name covers something that is not a rectangle, is invalid
and dropped whole -- both of which Chromium 141 does.

Lines can also be named in brackets between the tracks of a template,
several names to a line and one name on as many lines as like. Every
area names the lines around itself as well, `<name>-start` and
`<name>-end`, which is why `grid-area: a` and
`grid-column: a-start / a-end` land on the same rectangle; the test
asserts that they agree rather than that either matches a number.

A name is resolved against the *container's* template, not the item's
own style, so it stays a name through the cascade and is looked up in
layout where both are in hand.

Two things had to be corrected to make it work. `grid-area: a` was
setting only `grid-row-start`, because the shorthand filled its four
longhands positionally and stopped; an edge left out copies the one it
mirrors when that one is a name (§8.4), which is the whole of how an
item lands in an area. And the lines an area creates had to be findable
by their literal names, not only by the area's bare name.

One divergence is left and todo.md records it: a placement naming a line
the template does not know leaves that edge automatic, where the
standard creates an implicit line of that name after the explicit grid.

### `counter-set`, and the `counter-reset` scoping it could not be told apart from

CSS Lists 3 §4.2, and the property count goes from 199 to 200 on
`counter-set -> counterSet`.

`counter-set` sets the counter already in scope instead of making a new
one, so the change outlives the element that made it: a following
sibling of the setter sees the new value. That is the whole of the
difference from `counter-reset`, whose instance dies with its element --
and it is the only thing that distinguishes the two, because on the
element itself both end up reading the same.

Which meant the feature could not be tested, because this engine's
`counter-reset` was wrong in exactly the place the difference lives. An
instance created where one of the same name was already in scope was
staying in scope for the element's following siblings. Chromium 141,
measured: with `counter-reset: c 11` outside and `counter-reset: c 7` on
a child, the child reads 7 and the child's following sibling reads 11 --
and with no outer reset at all, that same sibling reads 7. So a
shadowing instance is scoped to its own subtree and a fresh one is not,
which is what lets one reset number a list of siblings while a nested
list does not renumber the outer one.

Both had to land together: with the scoping wrong, `counter-set` and
`counter-reset` agree on every case a test can ask, and the check that
tells them apart is the only one that means anything.

The values came out of Chromium by rendering `counter(c)` into a
`::before` and comparing its width against spans whose `::before` is a
literal one, two, three or four characters long, so each case's
candidates were chosen to differ in length. The first run of that probe
was wrong: the measured inline-block held the whole fixture, so its
width came from a block child rather than from the generated text. The
answer it gave happened to be right, which is worse than if it had been
wrong.

### Every automatic grid row was zero

`gridSizeAxis` sizes an automatic track from the item in it. In the
inline axis it asks `computeIntrinsic`, which needs no layout; in the
block axis it asks `a.box.h`, and nothing had laid the items out when it
ran. So every automatic row was nothing, and a grid with no declared
rows had no height whatever was in it:
`<div style="display:grid;width:100px"><div style="height:90px">` was
100 by 0 here and is 100 by 90 in Chromium 141.

The comment beside the call already said what should happen -- "the rows
are sized after the columns, because an auto row's height is the height
of items laid out at their column widths" -- and the code did not lay
them out. It does now, for the items an automatic row actually depends
on: a grid whose rows are all declared lays nothing out twice, and
neither does an item spanning more than one row, which contributes to no
track's size either way.

The suite had been given a chance to catch this and could not, because
every grid check asked the *item* for its height and none asked the
container. An item's own `h` was already right.

Writing the check that does ask found a second trap, in the harness
rather than the engine. `parentBox` reaches a parent through the box
registry, and the registry belongs to the most recent layout, so a
container read after the next document has been laid out is that
document's container. Three checks passed against the wrong tree before
that came out. Each layout is now asked its question before the next one
runs, and the test says why.

### `aspect-ratio`

CSS Box Sizing 4 §4, and the property instrument's count goes from 198
to 199 on a field that means the property rather than a neighbour's:
`properties.f --fields` reports `aspect-ratio -> aspectRatio`.

A box with one definite dimension takes the other from the ratio. The
part that cannot be guessed from the name is that this applies to the
inline axis too: `aspect-ratio: 2; height: 40px` on a block-level box is
eighty pixels wide, not the width of its containing block, and Chromium
141 agrees. The box the ratio describes is the content box, or the
border box under `box-sizing: border-box` — the same declaration is 120
by 70 one way and 100 by 50 the other.

Two rules came out of the measurement rather than the specification
text. The content is an automatic minimum in the block axis, so three
lines in a box the ratio would make too short make it taller; and that
minimum does not apply once the box clips, so adding `overflow: hidden`
takes the ratio back and lets the content spill. Flex and grid
containers follow both, which is why the ratio is applied after they
have sized themselves from their lines and tracks rather than before.

The grammar is taken apart slash-first. Splitting on whitespace and
then looking for the slash makes `16 / 9` — the ordinary way to write a
ratio — three tokens instead of one, and that is exactly what the first
version of this did: the test that caught it asserts `16 / 9` and
`16/9` give the same box, not that either gives 90.

The two terms are kept rather than their quotient, because a zero on
either side is degenerate and a single number cannot hold `2 / 0` apart
from `0 / 1`; both give a height of nothing, as Chromium does. A
negative term makes the declaration invalid. `auto <ratio>` gives way to
a replaced element's natural ratio where there is one, which is the
whole difference between it and a bare ratio: `auto 2` leaves a square
image square and `2` does not.

A table is not covered: `layoutTable` sizes itself from its rows and the
ratio does not reach it. css-2026.md says so.

### `content: url()` generates an image, and `width` stops applying to inline boxes

CSS2 §12.2 lets `content` name a url, and generated content could not
carry an image: the value parser rejected `url()` outright, so
`#a::before { content: url(tile.png) }` generated no box at all. It now
generates a replaced box at the image's intrinsic size, in the order it
was written among the strings beside it -- `content: url(x) "ab"` and
`content: "ab" url(x)` come to the same width and differ in where the
image lands, which is the check that does not depend on either number
being known in advance.

Three things were measured against Chromium 141 rather than guessed. A
`width` or `height` on such a pseudo-element does not resize the image.
Its margin, border and padding surround the whole run and are applied
once. A url that does not load generates nothing, where an `<img>` with
the same url draws a frame and its alt text.

A `content` that is nothing but a url resolves to no text at all, and
that was indistinguishable from no pseudo-element: an empty `text`
reads back as null (FINDINGS.md 4), and the text was what recorded the
pseudo-element's existence. The style records it now, which a
struct-typed map value can hold without that ambiguity.

The measurement found a bug of its own. `width`, `min-width` and
`max-width` do not apply to a non-replaced inline box (CSS2 §10.3.1),
and inline layout already worked that way -- it lays an inline's
children out and takes whatever they come to. The intrinsic pass did
not, so the two disagreed: an inline-block wrapping
`<span style="width:120px">b</span>` reserved 120 pixels and then drew
ten. Chromium gives that wrapper the width of its content.

That in turn needed the blockification the same specification requires
(Display 3 §2.7): a flex or grid item's `display` computes to a block
one, so `<span style="width:30px">` is an item thirty pixels wide and
not a run of inline content. It had been getting its width from the
intrinsic pass letting `width` through, which is the bug above -- two
mistakes cancelling, and the flex suite was measuring both.

Nothing is walked or fetched for this on a document whose generated
content names no image, which is every document but the few that do,
and a `content` with no url in it does not even build the arrays a run
would need.

### Filter Effects 1 cannot be implemented, and now it is written down why

A filter is a function over the pixels an element and its descendants
painted. This browser already paints a subtree into an image -- that is
how `clip-path` and `overflow: hidden` work -- and `img.drawPixel`
writes one back. What it cannot do is read one. `img.getPixelColor`
returns a `color`, and a `color` supports equality and nothing else: no
`.r`, no `.toInt()`, no packed form. Equality is also the only relation,
so nothing can be recovered by searching either -- with no ordering
there is no binary search, and trying candidates is 256³ comparisons for
one pixel.

The comparison is exact: a pixel painted `rgb(200, 100, 50)` compares
equal to another painted the same and unequal to one painted
`rgb(201, 100, 50)`. The bytes are there and the runtime can tell them
apart. The program cannot see them. That is FINDINGS.md 35, with the
proposal in festina.md 3p -- channel accessors on `color`, or
`img.getPackedPixel`, or both.

The work that could be done ahead of the language was done. The
matrices are Filter Effects 1 §8, derived in a separate script from the
specification text, and they agree with Chromium 141 on all
twenty-seven cases -- seven functions against three colours -- read from
a canvas with `ctx.filter` and `getImageData`, which needs no
screenshot. The specification does not say how a real number becomes an
eight-bit channel and Chromium is not uniform about it: the matrix
filters round to nearest and the component-transfer ones truncate, which
is what a matrix in fixed point and a component lookup table each do.
That rule reproduces all twenty-seven exactly; either rule alone misses
eight or eleven by one. todo.md keeps the table.

The parsing and painting written against this were removed rather than
left in. A `filter` property that computes and changes no pixel is
`outline-style` again -- a property the instrument would score while the
engine does nothing with it -- and this branch has declined that twice
already for `print-color-adjust` and `forced-color-adjust`.

### The logical inline properties follow `direction`, and `dir` works

`margin-inline-start` was `margin-left` whichever way the text ran.
css-2026.md had said so for as long as the aliases existed -- "direction:
rtl reorders the text on a line but does not yet swap the inline edges
those aliases resolve to" -- and in a right-to-left element the start
edge is the right one. All twelve inline aliases follow the direction
now, including the two corner radii that change corner:
`border-start-start-radius` is the top-left in a left-to-right element
and the top-right in a right-to-left one.

Where it is resolved is the whole of the difficulty. A logical
declaration and its physical twin are the same property once the
direction is known, so the later of the two has to win, which rules out
mapping them afterwards over the finished property map. The direction is
worked out first instead, from the element's own declarations -- the
last `direction` among them, the list being already sorted by weight --
falling back to the inherited value, and only then are the declarations
applied. Chromium agrees in both orders: `margin-right: 5px;
margin-inline-start: 40px` is 40 and the same pair reversed is 5.

HTML's `dir` attribute means `direction`, and nothing here had
implemented it, so `<p dir="rtl">` did nothing at all. It arrives as a
presentational hint rather than as a `[dir=rtl]` rule in the user-agent
stylesheet: such a rule has no tag, class or id to bucket on and would
be tested against every element of every page, where a hint is looked at
only for an element that carries one.

A page that never mentions `direction` and carries no `dir` does not
even scan for it. That rests on `&&` short-circuiting, which is now
checked rather than assumed and written into CLAUDE.md, because every
per-document flag in this codebase is worth nothing without it.

The first version of the hint cost about two milliseconds on the
benchmark page, which the alternating measurement caught: four samples
of the revision before it gave 100, 100, 100 and 100 ms against 103,
103, 102 and 100. `presentationalHints` runs for every table cell
whether it carries an attribute or not -- a cell inherits `border` and
`cellpadding` from its table -- so the page's 1,560 cells were each
paying for a `dir` lookup they could not have needed. Only an element
with a presentational attribute can carry `dir`, so the lookup sits
behind that test now, and the two series overlap completely: 100, 103,
101, 100 against 102, 102, 103, 100.

Twenty-one of the eighty-nine checks fail with the swap disabled.

### @container is evaluated, and CSS Conditional 4 comes off the Nothing row

A container query asks about the size of an ancestor, which layout
knows and the cascade does not. So the rules inside a `@container`
block are parsed into the sheet like any others, each carrying the index
of the query that gates it, and nothing is answered until there is a box
tree to ask: the document is laid out, the queries are answered from
that tree, and the cascade and layout run again.

That repeats while any answer changes. One pass is not enough, and
Chromium is the reason it is known not to be: an outer query that widens
an inner container makes the inner container's own query true, and a
single pass would have measured the inner one before the widening. Three
checks hold it -- the narrow control, the widening, and an outer query
that narrows a wide inner container and takes the answer back off again.
Eight passes is the cap, for a stylesheet written to make two queries
flip each other for ever.

The condition grammar is Media Queries 4's, reused whole by pointing
the viewport globals at the container's content box for the duration of
the call: the range form in both orders and with both ends, `and`, `or`,
`not` and grouping all came free. `inline-size` and `block-size` are
names for the two axes, recognised only while a container query is being
answered -- answering `@media (inline-size: 100px)` would be a lie of
the kind `@supports` exists to prevent.

The content box is what a query measures. 320px of content inside 20px
of padding is a 360px border box, and Chromium answers 320: a query at
310 matches and one at 340 does not, and with `box-sizing: border-box`
the content is 280 and a query at 300 does not match either. All three
are checks here.

An `inline-size` container refuses a query about height, `block-size`,
`orientation` or `aspect-ratio` rather than answering it from a size
nothing is holding still, which is what Chromium does and is the whole
reason `container-type` applies containment.

A container is not inside itself, so a query never styles the element
that established it. The first version of the walk pushed the container
before taking its own answers and did style it -- the comment beside the
code said the right thing while the code did the opposite, and the check
for it was already written.

A rule inside `@container` cascades exactly as it would outside: the
at-rule gates it and adds nothing to its weight, so `#t` beats `.c`
whichever side of the query each is written on.

A page whose sheets never say `@container` does none of this: one
boolean, once per document, and the second pass is never reached.

### Size containment per axis, and the container properties

`contain: size` contained both axes and there was no way to contain one.
The two guards were already separate in the layout -- the intrinsic-width
pass in the inline axis, the height in the block axis -- so splitting the
one flag into `containInlineSize` and `containBlockSize` is the whole of
it. `contain: inline-size` makes a box as wide as an empty box would be
and as tall as its content needs once wrapped into that width.

A float is the only box whose width shows this, because a block-level
box takes its containing block's width whether its contents are measured
or not. That is also why the float bug in the commit before this one had
to be fixed first: with every float 600px wide, none of these checks
could tell the difference between contained and not.

CSS Conditional 4's `container-type` is that containment under another
name, and `container-name` and the `container` shorthand go with it. A
query can only be answered about a box whose size does not depend on
what a rule the query controls might do to its contents, which is why
the property applies containment rather than merely recording an
intention. Chromium lays a float out under `container-type: inline-size`
exactly as it does under `contain: inline-size`, so that is what the
checks assert rather than a number of their own.

198 of 405 properties, from 196. `container-name` moves `containerName`;
`container-type` moves the containment fields and `containerType`.

**`@container` itself is still not evaluated.** A `@container` block is
skipped like any other at-rule this engine does not know, so its rules
never apply. Answering a query needs the container's size, which is
known only after layout, and so a second style and layout pass. The
properties being right is what that pass will need; it is not the same
thing as having it, and css-2026.md says so in those words.

### A float with no width took the whole column

`width: auto` on a float is shrink-to-fit --
`min(max(min-content, available), max-content)`, CSS2 §10.3.5 -- and
`placeFloat` laid the float out as an ordinary block with the full
available width instead. Every float without a declared width spanned
its column, and the text meant to wrap beside it went underneath, which
is the visible half of it: a floated badge, pull-quote or image caption
pushed the paragraph down rather than sitting in it.

An inline-block is sized by that same formula and had been right all
along, so the fix is one predicate: a floated box joins the set whose
automatic width is shrink-to-fit. The checks are agreements with an
inline-block of the same content rather than widths worked out again,
which also makes them independent of this engine's monospace advance
being 10px where Chromium's is 9.6.

Both ends of the formula are checked, because the middle term alone
would pass on a naive "use max-content": a float whose longest
unbreakable word is wider than the space available comes out wider than
its container, since min-content is the floor, and one with forty words
stops at the container, since max-content is the cap. Chromium agrees on
both, at 270px in a 200px container and at 200px.

The twenty-one float checks that already existed all passed throughout,
because every one of them declared a width. That is how a float bug this
size survived a float suite.

The first version of this test put all its cases on one page, and the
inline-block it compares against read 50px rather than 150. The floats
from the earlier cases were still in the float list -- nothing here
establishes a block formatting context yet -- and a 200px-wide float
left the next line no room, so the reference fell back to its
min-content width. A reference measured with something in the way is not
one, so each case gets a page of its own.

### display: inline-table, and Display 3's three corrections done

`inline-table` mapped to `DISPLAY_TABLE`, so it laid out as a
block-level table: on a line of its own, with the text before and after
it on lines of their own. It is a table inside and an inline outside,
so it sits on the line beside that text and takes the width its cells
ask for -- which a block-level table does too, so `blockLevel` is the
whole of the difference, exactly as it already was for `inline-flex`
and `inline-grid`.

The checks compare the engine against itself rather than against
Chromium's pixels, because they must: this engine's monospace advance
is 10px where Chromium's is 9.6, so the same six characters put the box
at 60 here and 58 there. What has to be true either way is that an
`inline-table` sits where an `inline-block` of its width would, that a
block-level `table` does not sit there, that both tables are the same
width, and that the wrapper is one line high rather than three. The
block-level table is the control, so a change that did nothing would
make the two agree and fail the check that says they must differ.

No blockification either way: a floated or absolutely positioned
inline-level box keeps the display it was given, where the standard
would make it the block-level equivalent. css-2026.md says so now
rather than leaving it to be discovered.

### color-scheme, and CSS Color Adjustment 1 off the Nothing row

`color-scheme` is parsed, inherited and acted on. The list is resolved
against the user's own preference, which this browser reports as light,
so a list offering `light` is light whatever order it is written in and
only a list offering `dark` without `light` is dark. `only` says how far
a user agent may override the choice and does not change it; an ident
nobody knows is carried along and ignored, which leaves a list of
nothing but unknown idents resolving as `normal` does.

Under `dark`, eleven of the nineteen system colours answer differently
-- `Canvas`, `CanvasText`, `LinkText`, `VisitedText`, `ButtonFace`,
`ButtonText`, `ButtonBorder`, `Field`, `FieldText`, `SelectedItem` and
`SelectedItemText`. The other eight are the same under either scheme,
and that half is asserted too: a table that simply darkened everything
passes the first eleven checks and fails these eight.

Each entry of the dark table is asserted against `packColor` of the
channels its comment names. Festina has no hexadecimal literal, so a
packed colour is a decimal beside a comment, and that is exactly how
`COLOR_VISITED` came to be the wrong purple for months with nothing
comparing the two.

The resolution is guarded by a per-document flag, and the flag is
raised from inline declarations as well as stylesheet rules -- which is
the mistake `anyCounters` had made and this commit's predecessor found.
`cssSchemeIsDark` is put back to false on reset, because a page that
never says `color-scheme` skips the resolution entirely and would
otherwise inherit the last page's answer.

196 of 405 properties, from 195; `color-scheme` moves `colorSchemeDark`
and nothing else. With the dark table stubbed out, sixteen of the
fifty-five checks fail.

`print-color-adjust` and `forced-color-adjust` are left alone. Both
have rows that register the moment the keyword is stored, and neither
would change a pixel: nothing here prints and there is no forced-colors
mode. That is `outline-style` again, and todo.md says so rather than
this taking the count.

### background-position-x and background-position-y

The two axes of `background-position`, settable on their own. The
shorthand is expanded into them where declarations are applied rather
than read beside them, because a reader that consulted one first would
make that one always win: cascade order has to decide between
`background-position: 10px 20px; background-position-x: 20px` and the
same pair written the other way round, and now does.

195 of 405 properties, from 193. Each longhand moves its own field and
not the other's, which `--fields` says.

The checks are agreements rather than pixels worked out again: the
shorthand's own pixels are established above them in the same file, so
the longhands are asserted to put the tile exactly where the shorthand
puts it, for lengths, keywords, a percentage, and both orders of
shorthand and longhand.

The first version of the helper looked for the tile along one row, and
two positions that both miss that row compare equal -- so two of the
checks passed while the feature was absent. It scans the whole box now,
and the shorthand's own position is asserted outright first, so "not
found" on both sides cannot read as agreement.

### The property instrument was measuring against the wrong denominator

The row list in `tests/conformance/css-properties.txt` was built from
Chromium's indexed enumeration of a computed style, and its header said
so: "every CSS property Chromium 141 reports on a computed style". That
enumeration reports 406 names, 33 of them `-webkit-` prefixed, which is
where the 373 rows came from. It also **omits 120 properties Chromium
computes perfectly well** and answers for through `getPropertyValue`.

Eighty-one of the 120 are shorthands and six are legacy aliases --
`page-break-before`, `word-wrap`, `grid-gap` and the rest -- and neither
belongs in a per-longhand instrument. The classification is Chromium's,
not an opinion: a shorthand expands to more than one longhand when set
on an inline style, and an alias expands to exactly one with a different
name. That leaves **33 ordinary longhands**, and every one of them
grades.

**Seven were already implemented here and had never been counted**:
`quotes`, `counter-increment`, `counter-reset`, `contain`,
`content-visibility`, `text-decoration-thickness` and
`text-underline-offset`. The file's header had noticed three of those
and drawn the wrong conclusion, saying they "cannot appear here at all"
-- the enumeration is how the list was discovered, not a limit on what
can be graded.

The count is now **193 of 405**, against 186 of 369. Each of the seven
was checked with `--fields` for which field moved, and each moved one
that means the property.

### Three rows were excused for reasons nobody had tested

`d`, `grid-template-areas` and `hyphenate-character` carried a third
column declaring them ungradeable, with a reason each: that `d` applies
only to an SVG path, that `grid-template-areas` computes `none` off a
grid container, that `hyphenate-character` computes `auto` unless
hyphenation is applied. All three reasons were guesses, and all three
are wrong. The real cause was the same for all of them and had nothing
to do with the properties: their values are CSS strings written with
double quotes, and both the audit and the runner deliver a value inside
a double-quoted `style` attribute, which the first quote ends. The
value arrived as nothing and the property computed its initial value,
which reads exactly like a property Chromium cannot tell apart.

Written with single quotes, all three grade. The audit now names this
case in its own words instead of reporting it as Chromium computing no
difference, so the next one is diagnosed rather than excused. One row
remains genuinely ungradeable: `overlay`, which only the user agent can
set.

### A counter in a style attribute was dropped

`anyCounters` and `anyQuotes` are the per-document flags that let
counters and `quotes` cost nothing to the pages that do not use them,
and both were raised by walking the stylesheet rules -- which an inline
declaration is not in. So `<span style="counter-increment: c">` numbered
nothing, on any page whose stylesheets mentioned no counter.

The flags are now raised where the inline declarations are parsed,
which reaches only elements that carry a `style` attribute and only
until the answer is yes, and which happens before that element's own
values are computed, so the element that raises the flag benefits from
it. The check that holds it is the same counting written both ways,
asserted equal, with the absolute values beside it so that breaking
both forms together could not pass.

The `@supports` cross-check found this one on its own: `counter-reset`
and `counter-increment` were claimed by `supportedProperties` and
changed nothing the instrument could see.

### The benchmark's control row is the script's job now

`tests/bench.sh` compares Chromium's render of the benchmark page
against `CONTROL_MS`, prints how far out it is, and exits non-zero when
it is beyond `CONTROL_TOLERANCE`. CLAUDE.md had required that check
since the run that reported Chromium at 93 ms on a page where it takes
26, but required it of the reader; a run today reporting 30.4 ms where
the middle of the distribution is 26.0 printed without a word of
complaint beside a table that looked ordinary.

The tolerance is measured rather than chosen. Eight best-of-5 samples of
Chromium on an idle machine give 25.3, 25.6, 25.6, 25.9, 26.1, 26.1,
27.4 and 28.8 ms: a middle of 26.0, and a band from 3% below it to 11%
above. The contended run sat at 17% above. Fifteen per cent separates
them with room on both sides, and a band tight enough to fail honest
runs is a band that gets ignored.

Asking the same question of this browser's own row moved the recorded
number: eight samples give 99 to 104, while two whole-script runs gave
98 and 110, the script reaching that table after a dozen Chromium
launches. The table now records the middle of the samples — 101 ms
against Chromium's 26.0 — rather than the best run of one afternoon,
which was the low end of the spread and flattered us by three per cent.

### CSS Nesting 1

A style rule may be written inside a style rule. `&` stands for the
rule it is in and may appear anywhere in the nested selector; a nested
selector that does not contain one gets one in front, as a descendant,
which is also how a leading `>`, `+` or `~` is read. `@media`,
`@supports` and `@layer` nest in both directions: a style rule inside a
nested at-rule reaches what its selector says, and declarations written
directly inside one belong to the rule the at-rule is in.

A nested rule expands to the cross product of its own selector list
with its parent's, capped at 256 selectors, which is exact for matching
and not for weight. The standard gives `&` the specificity of the *most
specific* selector in the parent list whichever branch a match came
through, and reading the text of one branch computes that branch's own,
so the difference is added back once per substituted `&`. The check
that holds it is a pair: `.a, #ia { .b { } }` against a later
`.w .b { }`, where Chromium styles the `.b` that matched only through
`.a`, and the same shape with the id taken out, where it does not.
With the correction disabled exactly that one check fails.

Where a declaration sits among the nested rules decides when it
cascades, so a rule's body is emitted as the runs of declarations it is
written in rather than gathered into one: `.a { & { red } blue }` is
blue and `.a { blue; & { red } }` is red.

A rule body with no `{` and no `@` in it cannot hold a nested rule, and
takes the path it always took. That is every rule on a page that does
not nest, so the feature costs those pages one scan for a byte that is
not there. The revision before it, rebuilt and sampled alternately with
this one, renders the benchmark page in 100, 102, 102 and 112 ms against
this one's 99, 101, 101 and 103: two series that overlap, with the
higher reading on the side without the feature.

An `&` inside `:is()`, `:where()`, `:not()` or `:has()` is left in
place rather than substituted, which makes the selector unparseable and
drops the rule. Those take a compound selector in this engine and a
parent may be a complex one, so substituting would quietly change what
the selector means.

The selector expansion arrived with FINDINGS.md's shape (c) -- a local
bound to an element of an `arr[ascii]` -- for the fourth time. Here it
segfaulted rather than leaking quietly, because the user-agent
stylesheet is parsed at the start of every page and the double free
reached a live buffer.

### The relative colour syntax, which completes Color 5

`rgb(from red r g b)` and its form in every other colour function: the
origin colour is converted into that function's space, its channels are
bound to the names the function writes them with, and the three
components are expressions over those names -- a name, a number, a
percentage on that function's own scale, `none`, or a `calc()` over them
with the four operators and parentheses.

`color(from <color> <space> ...)` takes all eight predefined spaces,
which needed the XYZ-to-linear matrices for `display-p3`, `a98-rgb`,
`prophoto-rgb` and `rec2020` -- the inverses of the ones the absolute
forms use. The identity check is what says they are right: a colour
written back under its own channel names must be the colour it started
as, and it is, in all fifteen spaces.

The `xyz` spaces name their channels `x`, `y` and `z`, so
`color(from red xyz r g b)` is not a query about them and is dropped,
which is what Chromium does with it too.

It is the mirror of `color-mix()`: both wanted sRGB converted *into* a
space rather than out of it, and having done that for the mix there was
nothing left to do for this but name the channels.

With the relative form disabled, thirty-four of the thirty-nine checks
fail.

### color-mix()

Over every interpolation space the standard names: the rectangular
`srgb`, `srgb-linear`, `xyz`, `xyz-d65`, `xyz-d50`, `lab` and `oklab`,
and the polar `hsl`, `hwb`, `lch` and `oklch` with `shorter`, `longer`,
`increasing` and `decreasing` hue. CSS Color 5 moves from Nothing to
Partial; what it still does not have is the relative colour syntax.

Mixing is premultiplied, so `color-mix(in srgb, transparent, blue)` is
blue at half alpha rather than a dark blue. A hue is not premultiplied,
being an angle rather than a quantity. Percentages that do not add to a
hundred are normalised, and what they came to is carried into the
result's alpha: `red 30%, blue 30%` is the halfway colour at six tenths
alpha.

Every space needed the conversion the wider colour spaces did not: sRGB
*into* it rather than out of it. That is what the polar spaces were
waiting on, and it is what the relative colour syntax will want next.

Every expected pixel is Chromium 141's, read by setting the colour as a
canvas fill. Eleven of the fifty-six checks need no reference at all: a
colour mixed with itself is itself, in each of the ten spaces and for a
colour that is not a primary. A conversion wrong in both directions
passes every other check here and fails those.

With the space forced to sRGB, twenty-five of the fifty-six fail.

### @layer orders the cascade

The blocks were parsed and the ordering -- the entire point -- was
discarded. A layer is declared where it is first named, by a
`@layer a, b;` statement or by a `@layer a { }` block, and its place in
that order is its place in the cascade, above specificity and above
source order: of two layered declarations the one in the later layer
wins, and a declaration in no layer beats both.

`!important` reverses all of it, so an important declaration in the
*earliest* layer is the strongest author one and an important unlayered
declaration the weakest.

`@layer b` inside `@layer a` is the layer `a.b`, and declaring `a.b`
declares `a` first, because an outer layer comes before what is nested
in it. An anonymous `@layer { }` is a layer nothing can name again, so
two of them are two layers.

The cascade sorts on one integer, and there are now four tiers to pack
into it rather than three. The rank reaches 518 with 256 layers, which
leaves ten thousand billion for each rank; specificity is a triple
packed base 1024, so it fits in a million of those; and what had to give
is source order, which counts to a million and no further. A sheet with
more than a million rules decides its last ones on specificity alone,
and one with more than 256 layers stops telling them apart -- both
written down because neither is a thing the standard allows.

The count does not move -- `@layer` is not a property. What grades it is
`tests/unit/test_layers.f`: twelve stylesheets whose winning colour is
Chromium 141's, and eight assertions about the weights themselves, so a
failure says which tier is wrong and not only which colour won. With the
layer ignored, six of the twenty fail.

### The media features Level 4 adds

Each is a statement about this browser rather than a computation, and
two of them are where it differs from the reference:

- **`scripting: none`**, because there is no JavaScript engine. Chromium
  says `enabled`.
- **`overflow-block: scroll`** and **`overflow-inline: none`**, because
  the shell scrolls a document down and clips what runs across.
  Chromium says `scroll` to both.
- `update: fast`; `color-gamut: srgb`, because every colour is a packed
  sRGB integer by the time it is painted; `prefers-color-scheme: light`;
  and `prefers-reduced-motion`, `prefers-contrast`,
  `prefers-reduced-data`, `prefers-reduced-transparency`,
  `forced-colors`, `inverted-colors` and `dynamic-range` answering
  `no-preference`, `none` or `standard` — there being no user to have
  asked and nothing that moves.

A discrete feature takes only equality from the range form, because
keywords have no order: `(scripting >= none)` is not a query, and
`(orientation = landscape)` is the colon form said differently.

The boolean form of each follows its value, which is not always the
obvious answer: `(dynamic-range)` is false, because `standard` is the
falsy one of its two values.

### Media Queries 4's syntax

- **The range form**: `(width >= 400px)`, `(400px <= width)` with the
  value written first and the operator turned round with it, and
  `(400px <= width <= 900px)` with both ends, in `<`, `<=`, `>`, `>=`
  and `=`.
- **`or`** beside `and`, **`not`** inside a condition, and parentheses
  grouping conditions rather than only enclosing features.

Media Queries 4 moves from Nothing to Partial. What it still does not
add is features of its own — `prefers-color-scheme`, `update`,
`overflow-block` and the rest are not answered.

Two of the checks are of the shape that needs no answer known in
advance: `(width >= 640px)` must answer what `(min-width: 640px)`
answers, and `(width <= 640px)` what `(max-width: 640px)` answers. They
are two spellings of one question, and the older one was already right.

The query evaluator was a split on ` and ` and a loop. It is a small
recursive-descent evaluator now, because `and` and `or` and `not` and
parentheses cannot be read by splitting: a separator inside a group
belongs to the group.

### Every media feature Level 3 defines

`@media` understood five features and answered `(color)` and `(hover)`
with a hard-coded true. It now answers all of them:

- **sizes** — `width`, `height`, `device-width`, `device-height` with
  their `min-` and `max-` forms;
- **`orientation`**, which a square viewport answers `landscape`;
- **`aspect-ratio`** and **`device-aspect-ratio`**, compared as two
  whole numbers rather than two divisions, so 800 by 600 is `4/3`
  exactly and not to within a rounding error;
- **`color`, `color-index` and `monochrome`** — eight bits a component,
  no colour table, not monochrome;
- **`resolution`** in `dpi`, `dpcm`, `dppx` and `x`, at 96 to the inch;
- **`grid`** and **`scan`**, which describe devices this is not;
- and the **boolean form** of each, which asks whether the feature's
  value is something other than zero.

What this engine calls the device is its own window. There are no screen
metrics to ask for, and a page asking about the device is deciding
whether it is on a phone, which the window size answers as well as the
screen does.

`hover` and `pointer` answer `hover` and `fine`, because this browser
opens a window with a pointer in it. Headless Chromium answers `none`
and neither, which is a fact about that process rather than about the
standard, and the test says so where it departs from the reference.

The expected answers are Chromium 141's, read with `window.matchMedia`
and restated against this engine's viewport: a query about a width is a
question about a number both engines have, so what is checked is
Chromium's rule rather than Chromium's window.

The count does not move -- a media feature is not a property. What
grades this is `tests/unit/test_media.f`, sixty-eight checks.

What is left is time rather than features: a query is evaluated when the
sheet is parsed, so resizing the window does not re-evaluate it.

### Two of Display 3's three corrections

- **`display: contents` generates no box.** The element's children
  become its parent's, in its place; its own height, border and
  background describe a box that does not exist. It stays in the tree
  for inheritance, so its children still inherit from it.
- **An unknown `display` value is dropped**, as the invalid declaration
  it is. It was falling through to the property's *initial* value, which
  is `inline`, rather than to the declaration it had beaten — so
  `display: bogus` on a `<div>` made it an inline. There is one map of
  declarations, and a value that reaches it has already won the cascade,
  so the validity test has to happen where the declaration is applied
  and not where it is read.

The count does not move: `display` has registered on the property
instrument since the first commit, and it registered while both of these
were wrong. What grades them is `tests/unit/test_display.f`, sixteen
checks against Chromium 141's geometry on the same fixtures.

Two of the checks are of the shape that needs no answer known in
advance: a wrapper with no box properties of its own must lay out
identically whether it generates a box or not, and two `contents`
elements nested must collapse through both.

`inline-table` is still a block-level table, which is the third of the
three corrections and the one that needs an atomic inline whose inner
layout is the table algorithm.

### column-span: all

A direct child of a multi-column container with `column-span: all` is in
no column. It splits the container into three: the run before it,
columnised and balanced on its own; the spanner at the full width; and
the run after, columnised and balanced on its own again.

**Properties 185 → 186.** It is the gap css-2026.md named for
Multi-column 1.

`layoutColumns` laid out every child of the container and then moved
them; it now lays out a run of them, and a container with no spanner --
which is every multi-column container on almost every page -- takes one
run and is the function it always was. `layoutBlockChildren` and
`collectColumnUnits` grew a range for the same reason.

Only a direct child can span. The standard lets a spanner sit deeper and
breaks its ancestors around it, which needs the fragment boxes this
engine does not make.

The fixtures divide evenly into two columns, because Chromium will split
a block across a column boundary to balance and this engine will not:
seven blocks in two columns is a difference about fragmentation rather
than about spanning, and a test that used it would be measuring the
wrong thing.

One check asks what the feature is *not*: `column-span: none` is the
initial value, so it has to lay out exactly as no declaration does. An
implementation that treated any value of the property as a spanner
would pass every other check here.

### shape-outside, from the machinery clip-path had just built

- **`shape-outside`** over `inset()`, `circle()`, `ellipse()`,
  `polygon()` and the four geometry boxes, the default being the margin
  box. A float's exclusion edge follows the shape, so a circle lets the
  corners of a square float be written into.
- **`shape-margin`**, which grows the shape on every side.

**Properties 183 → 185.** CSS Shapes 1 moves from Nothing to Partial.

The shape geometry moved into `src/css/shapes.f`, because the two
features that want it are on opposite sides of the engine: the painter
cuts a box to a `clip-path` shape and the layout engine pushes line
boxes aside from a float's, and the painter imports the layout engine,
so neither could call the other. It takes the reference box as four
numbers rather than as a Box, which is what let it move.

The two ask different questions of the same shape, and the difference is
a pixel. A clip asks which pixels it keeps, so it samples at pixel
centres. A float asks how far a line box must clear, and a line box is a
rectangle over a continuous band, so the answer is the shape's extreme
anywhere in `[y, y+h]` — endpoints included. Sampling pixel centres for
that is one row short, and three of Chromium's line starts said so.

An exclusion is clamped to the float's own margin box in both axes,
which is not an optimisation: outside the float there is no float to
exclude anything. `circle(50px) shape-margin:10px` on a 100px float
reaches 102px horizontally and 110px vertically, and Chromium excludes
neither.

### clip-path, and a spec that was on the "Nothing" row

- **`clip-path`** over the basic shapes — `inset()` with its one to four
  lengths, `circle()` and `ellipse()` with a radius per axis, a centre
  and the `closest-side` and `farthest-side` keywords, and `polygon()` —
  and over the four geometry boxes, each of which names a rectangle.
- **`clip`**, the CSS2 rectangle that preceded it, on an absolutely
  positioned box. It computes on every box, as the standard says, and
  applies only where the box is positioned.

**Properties 181 → 183.** CSS Masking 1 moves from Nothing to Partial.

The canvas has no clip region and no path API. A rectangle was already
cut by painting the subtree into an image and blitting it back; a shape
is the same image blitted back one scanline at a time, each with the
span the shape covers at that row. A pixel belongs to the shape when its
centre does, which is the rule a rasteriser without antialiasing has to
use.

`overflow-clip-margin` was implemented far enough to register and then
taken out again. Chromium's answer for it on a bordered box did not
agree with the padding-box clip edge the standard describes, and the
two readings differ by a border width; a property whose meaning is not
pinned down is not one to ship for the sake of a count. It is on the
work list with what was measured.

The expected pixels are Chromium 141's. `document.elementFromPoint`
respects both properties, so asking it at each pixel's centre is asking
that engine which pixels a clip keeps, with no screenshot to decode. A
pixel whose answer Chromium changes within three pixels — the boundary
itself — is copied from the actual grid rather than compared, because
an engine that antialiases and one that does not are entitled to differ
there and nowhere else.

Four of the checks are of the shape that does not need the answer known
in advance: a circle is an ellipse with two equal radii, a rectangle is
a four-sided polygon, the content box of a box with 25px of padding is
an inset of 25px, and the legacy `clip` reaches that same rectangle from
the other side.

### Where a column may break

- **`break-before` and `break-after`** take `column` to force a column
  break and `avoid` or `avoid-column` to forbid one. `page` and the
  page-side keywords compute and do nothing, because there are no pages
  here — which is also what Chromium does with them on screen, and the
  check says so rather than asserting a break that should not happen.
- **`break-inside: avoid`** makes a child indivisible: it enters the
  column machinery as one unit however many lines it holds, so it moves
  whole.
- **`orphans` and `widows`** constrain a break inside a paragraph to
  leave that many lines behind it and take that many with it. They
  inherit, as the standard says, and the initial value of both is 2.

**Properties 176 → 181**, one field moved per property —
`tests/conformance/properties.f --fields` says which.

The two ends of the balancing loop now read one answer rather than each
deciding for itself. `columnsNeeded` and the placement loop each had
their own copy of "does a column break here", and a third case was about
to be added to both; they call one `columnBreaks` now, because a target
height that says two columns and a placement that makes three would give
the container the height of a column it does not contain.

`orphans` and `widows` pull a break in opposite directions, and a rule
that only looked one way would pass half the checks. Four of six lines
of orphans pushes the break a line later; four of widows pulls it two
lines earlier. Five and five of six is a contradiction, and the standard
says such a pair is ignored rather than making the content unbreakable —
what gives way is widows, which is what Chromium does and what the check
now requires.

Every expected position came from Chromium 141 before any of this was
written, with each line of the fixture wrapped in a span of its own, so
which column a line landed in is that engine's answer rather than an
inference from a height.

Comparing two `ColumnUnit`s asked whether two struct references were the
same, which Festina rejects in the backend rather than the parser
(FINDINGS.md, "two struct references cannot be compared"). The units
carry the child's index instead.

### CSS Color 4's wider color spaces, and a visited-link color that was wrong

- **`hwb()`**, **`lab()`**, **`lch()`**, **`oklab()`**, **`oklch()`**
  and **`color()`** over the eight predefined spaces (`srgb`,
  `srgb-linear`, `display-p3`, `a98-rgb`, `prophoto-rgb`, `rec2020`,
  `xyz`/`xyz-d65` and `xyz-d50`), each with `none` components, a hue in
  `deg`, `rad`, `grad` or `turn`, percentages on the standard's own
  scales — 125 for a Lab `a`, 150 for an LCH chroma, 0.4 for an Oklab
  one — and a slash alpha. They convert through the standard's own
  matrices to the packed sRGB integer everything else here paints, a
  channel outside the gamut clamped rather than gamut-mapped.
- **The nineteen system colors**, `Canvas` and `CanvasText` through
  `Highlight` (which carries alpha) to `VisitedText`.

**`COLOR_VISITED` was `rgb(85, 4, 121)`, not the `#551a8b` its own
comment claimed.** A hex-to-decimal conversion off by 5,650, of exactly
the kind FINDINGS.md's "no hexadecimal literal" finding predicts, and
nothing had ever compared the constant against anything. Visited links
have been painted the wrong purple since the user-agent stylesheet was
written. The check that catches it is the one that asks two things to
agree: the constant the stylesheet uses and the `VisitedText` the
standard names must be the same integer.

**Properties 176 → 176.** This moves no count, and could not: the
instrument sets `color: #123456` and asks whether the computed style
changed, so `color` has read as implemented since the first commit
whatever syntax reaches it. The deliverable is instead
`tests/unit/test_color4.f`, 79 checks whose expected pixels were derived
twice and independently — once by implementing the standard's §17
pseudocode in a separate script, once by asking headless Chromium for
the pixel it paints — and which agreed to the byte on all of them before
a line of Festina was written. Four more in `tests/render/basic_pixels.f`
(47 → 51) ask the question the unit suite cannot: whether a colour
syntax the cascade has never seen survives the declaration parser and
reaches the painter. Each of the four converts to a colour Festina can
name, so they are equalities rather than tolerances.

### Three properties, one of them written off too early

- **`hyphens`** honours a soft hyphen as a break opportunity: it shows
  nothing where the line does not break and a hyphen where it does, and
  `none` suppresses it. `auto` behaves as `manual`, because automatic
  hyphenation needs a dictionary per language.
- **`list-style-image`** draws a fetched image as the marker, at its own
  size, falling back to the type's marker when the image could not be
  fetched.
- **`background-attachment: fixed`** positions the background *image*
  against the viewport rather than the element, so it stays put while
  the page scrolls under it.

**Properties 173 → 176.** Nine checks in the new
`tests/unit/test_hyphens.f` and seven in `tests/render/basic_pixels.f`
(40 → 47).

`hyphens` had been set aside earlier on this branch as needing a
character the pipeline could not carry — the same wrong premise that
had set Writing Modes aside, and wrong for the same reason. A soft
hyphen is U+00AD, `text` holds UTF-8, and it arrives intact.

The `background-attachment` check began by giving its fixture a
background *colour*, which the property says nothing about: a colour
fills its box whatever the attachment, so the check would have passed
for an implementation that did nothing. It uses an image now, and says
why in the fixture.

One check earns its place by asking what the feature is *not*: a word
holding a soft hyphen that does not break must measure exactly as wide
as the same word without one. A soft hyphen that was quietly being drawn
would pass every other check here.

### The last five selectors, and the documentation that claimed they worked

`:is()` and `:where()`, which differ only in that `:where()` contributes
no specificity; `:has()`, as a descendant test; a selector list inside
`:not()`; and the attribute case-sensitivity flag. **The instrument goes
from 56 of 61 to 61 of 61** — every selector it asks about now matches
exactly the elements Chromium matches.

The four functional pseudo-classes share one implementation, because
they differ only in how a match is read: `:not()` wants none of its
alternatives to match, `:is()` and `:where()` want any, and `:has()`
wants a descendant to. `:has()` with a leading combinator — `:has(> p)`
— names a relation this engine does not distinguish and is refused
rather than quietly read as a descendant test.

**This was found because css-2026.md said they already worked.** Its
Selectors 3 row listed `:is()`, `:where()`, `:has()` and a `:not()` list
among the things that work, while the Selectors 4 row two classes below
named those same five as the measurement's only failures — the file
contradicted itself, and the measurement had been saying which half was
right on every run since the instrument was built.

So the rest of the file was audited rather than the one row fixed, and
five more had drifted the same way: Lists and Counters still said
`list-style-position` was missing, Logical Properties said the block
padding aliases were not done, Positioned Layout said there was no
`inset` shorthand, and Transforms 2 and Containment 2 sat in a row of
specifications with nothing implemented while each had gained a part.
Every one of those was a feature added on this branch whose row nobody
went back to.

**The headline moved with them.** Of the 24 specifications in the
snapshot's official definition the engine now implements part of 22 and
no part of 2, against 8 when this branch began — and the two it does not
touch are the two it cannot: Compositing and Blending needs a
compositing operator the runtime does not expose, and Easing needs an
animation clock.

### Counter styles

All five of the standard's numbering systems — `cyclic`, `fixed`,
`symbolic`, `alphabetic`, `numeric` and `additive` — with `symbols`,
`additive-symbols`, `prefix`, `suffix`, `pad` and `negative`.

**The predefined styles are built out of those same five**, so there is
one generator and a name is nothing but the definition it looks up:
`lower-roman` is an additive style with the roman weights,
`decimal-leading-zero` is a numeric one with a pad of two, and a page's
own `@counter-style` is the same structure with a different source. That
is the whole reason the specification defines them that way, and
following it is what makes `@counter-style` free once the predefined
ones work.

A number a system cannot write falls back to decimal, which is the
standard's rule and why `lower-roman` of 4000 is `4000` rather than four
thousand M's. That took a range on the roman styles: the additive system
will happily write `mmmm`, and a check said so.

Thirty-three checks in the new `tests/unit/test_counterstyles.f`, each
naming the value the standard gives for a number — a check that a marker
"is not decimal" would pass for any wrong answer. **Two of them ask
whether the marker reaches the list item that draws it**, which is a
different question from whether the generator is right, and the one that
would catch it being correct and unwired. It was: `list-style-type`
inherits and the name it was given did not, so an `<li>` inside a styled
`<ol>` got nothing.

A token splitter that counted parentheses inside quoted strings pulled
`negative: "(" ")"` apart at its first symbol. It skips quoted strings
now, which it should have done for CSS anyway.

No property moves — `list-style-type` already registered — but it is the
fifth of the snapshot's specifications to close this far.

### CSS Namespaces 3, in full

`@namespace` binds a prefix, or a default namespace when it names none,
and a selector's namespace part is honoured: `ns|E` for a declared
prefix, `*|E` for any namespace, `|E` for no namespace, and a bare `E`
for any namespace until a default is declared and then only that one. A
prefix nobody declared makes the selector invalid, so it matches nothing
rather than being read as a type selector with that name.

Every element in an HTML document is in the XHTML namespace, so the
whole specification comes down to one string comparison — which is why
this one can be honoured rather than approximated, and why the checks
ask the four spellings against each other: each alone would pass for a
parser that ignored the syntax and read `h|p` as a tag called `h`.

Twelve checks in the new `tests/unit/test_namespaces.f`. The selector
instrument is unmoved at 56 of 61, which is the check that adding `|` to
the selector grammar did not disturb the selectors already there.

No property moves, because the specification has none. It is the fourth
of the snapshot's untouched specifications to close, and the first to
close completely.

### Right-to-left text is drawn right to left

Hebrew and Arabic rendered before this — the decoder, the DOM, layout
and the painter all carried them — **in logical order, which for a
right-to-left script is backwards on the screen**. The bidirectional
algorithm (UAX #9) now puts each finished line into the order it is
read: the W, N and I rules and the L2 reordering.

`direction` sets a paragraph's base level, and it is what `text-align`'s
`start` and `end` resolve against — including the initial value, which
*is* `start`, so an element with no side of its own follows its own
direction rather than inheriting a resolved side. That distinction is
what `textAlignExplicit` exists for: `left` and `right` are sides and
inherit as they are, `start` and `end` are ends and cannot be resolved
once.

The character classes come from script ranges rather than the Unicode
database, which this repository would have to vendor; the ranges cover
the scripts the algorithm exists for. The explicit embedding and isolate
codes — the X rules — are not implemented, so a document that overrides
the implicit result with them gets the implicit result.
`unicode-bidi: bidi-override` is honoured, and is the one case where
reversing a line outright is the right answer.

**Thirty-six checks in the new `tests/unit/test_bidi.f`, each a rule of
the standard asked directly**, because the rules are what the algorithm
is: a check that a Hebrew word comes out reversed would pass for an
implementation that reverses everything. The check that would not is a
Latin run inside a right-to-left paragraph, where the line reverses at
one level and the Latin reverses back at another. Seven more in the new
`tests/render/bidi.f` ask whether the reordering reaches the pixels.

A page with no right-to-left character in it never runs the algorithm:
the flag is set once while the box tree is built.

**Properties 172 → 173.**

**The premise for skipping this was wrong, and measuring it is what
found that out.** Writing Modes had been set aside on the grounds that
`ascii` cannot hold non-ASCII and the decoder converts to an ASCII-safe
form, so the scripts that need bidi could not survive the pipeline. They
survive it perfectly: a Hebrew string renders, and the DOM reports its
four characters. `ascii` is the *parser's* type; the content is `text`,
which holds UTF-8 and indexes by code point. The whole of the reasoning
rested on a claim nobody had run.

`unicode-bidi` is deliberately absent from the `@supports` list. Its row
carries `embed`, which is not implemented, and changing the row to the
value that is would be choosing the goalpost rather than fixing a
defective one — unlike the grid rows, whose `none` was not valid for
those properties at all. `@supports` answers per property rather than
per value, so the only answer it can give without overclaiming is no.

### text-emphasis, and an underline that clears the descenders

`text-emphasis` draws a mark beside every character — over the text by
default, under it when `text-emphasis-position` asks, in its own colour
— in all five of the standard's shapes in either their filled or open
form, and from a `<string>` as itself. **Each shape resolves to the
character that draws it**, so the five need no drawing code between them
and a string value needs no special case.

The mark does not reserve space in the line. In a line only as tall as
its font there is nowhere above the ascender for it to go and it falls
outside the line, which css-2026.md records and todo.md carries; the
checks give their fixture a tall line box for that reason and say so.

`text-underline-position: under` drops the underline below the
descenders instead of sitting it on the baseline. `left` and `right`
behave as `auto`, because they mean something only in a vertical writing
mode.

**Properties 168 → 172.**

Fourteen checks in `tests/render/decoration.f` (38 → 50).

**A sixth instrument defect, and the first one caught automatically.**
The `text-underline-position` row carried `left` — valid CSS, and
Chromium computes it, but a value that can only mean something in a
vertical writing mode, so it measured a feature no horizontal engine
has. The `@supports` cross-check added earlier this branch found it
without being asked: the property was on the supported list and changing
nothing, which is exactly the disagreement that check exists to catch.
The row carries `under` now.

### border-image

The source is cut into nine regions by `border-image-slice` — a number
or a percentage on each side, and `fill` for the middle. The four
corners are drawn at the border's own size, the four edges fill what the
corners leave, stretched or tiled by `border-image-repeat`, and
`border-image-width` and `border-image-outset` move and resize the area
they go in. `round` and `space` tile as `repeat` does, differing only in
how the last tile is fitted, which todo.md records.

Each region is cut by blitting the source into a blank image at a
negative offset. That is the fifth thing standing in for a capability
the canvas does not have: an image destination takes no source rectangle
(FINDINGS.md, finding 30), and a border image inside a clipped subtree
is painting into an image rather than the canvas.

`tests/fixtures/nine.png` is nine 3x3 regions in CSS-named colours, so a
slice of 3 cuts exactly those nine and each region can be named by the
colour it must put on the box. **Its top edge varies across its three
columns — lime, white, lime — because a uniform edge looks identical
stretched and tiled**, and telling those apart is the whole of
`border-image-repeat`.

**Properties 163 → 168.**

Twenty-two checks in the new `tests/render/borderimage.f`.

Three of them had to be rewritten before they measured anything.
A scaled blit is filtered, so the one-pixel white column of a 3px region
stretched into 10px blends into the lime on either side and never
reaches the full colour — the check now asks that the tiled edge lays
its region down more than once and the stretched one does not, rather
than counting bands in both. A 3x3 corner scaled into 4x4 is filtered at
every pixel, so the narrow-width check asks that the corner is painted
at all. And a fixture using `margin` to inset the box had its margin
collapse through to the root and vanish, which is a trap this repository
has now fallen into twice; the wrapper is padded instead.

### Columns

The third of the snapshot's untouched specifications off zero.
`column-count` and `column-width` resolve by the standard's rule — a
count alone is that count, a width alone is as many columns of at least
that width as fit, both together make the count a maximum — with the
`columns` shorthand, `column-gap`, and `column-rule` and its three
longhands painted down the middle of each gap through the same code as a
border side.

**The content is laid out once, at the column width, and that single
flow is then broken into columns.** Nothing is laid out twice: the cost
is the walk that moves the content, not a second layout. The balanced
height starts at an equal share and grows until every unit fits in the
columns there are, because a unit taller than the share sets its own
column's height.

**Breaking happens between the container's direct children and between
the line boxes of a direct child, and no deeper.** That covers what
multi-column is used for — a stack of blocks, or one long run of text,
whose lines are all in one child — and css-2026.md says plainly what it
does not cover: a subtree nested below those children stays whole and
overflows its column. A child whose lines are split has its own box
refitted to the lines sharing its first column, so its background does
not smear across the gap. Real fragment boxes are in todo.md, where they
sit with paged media and the `break-*` properties, because it is one
piece of work for all three.

`column-count: 1` is checked against no columns at all — a
multi-column container with one column must be indistinguishable from an
ordinary block, and that is the check that would catch the whole
mechanism firing when it should not.

**Properties 158 → 163.**

Twenty-eight checks in the new `tests/unit/test_multicol.f` and seven in
`tests/render/borders.f` (66 → 73).

**A struct field that can never be null.** The first draft marked a
column unit as "a whole child" by leaving its `line` field unset and
testing `u.line == null`. A struct-typed field can never read as null
(FINDINGS.md, finding 5), so the test was always false and every unit
took the line branch: the blocks stayed in column one and seven checks
said so. It carries an explicit flag now.

### Grid

`display: grid` and `inline-grid` establish a grid container, and its
children are laid out on two axes at once rather than stacked. Three
passes, in the order the standard puts them: every item is placed on
both axes, then the tracks those placements imply are sized, then each
item is laid out in the area it occupies. Placement comes first because
a track's size can depend on the items in it and an item's track can
depend on no size.

**Tracks** come from `grid-template-columns` and `grid-template-rows` as
lengths, percentages, `auto`, `fr` and `repeat()` of a whole list, with
`grid-auto-columns` and `grid-auto-rows` sizing the tracks an item
creates past the template. `fr` is not a length — it is a share of what
the fixed tracks and the gaps leave — so it has a field of its own
rather than a `Len`, and the last `fr` track takes the remainder so the
tracks add up to the space exactly.

**Placement** is by line number, counting back from the end when
negative, or by `span n`; `grid-column`, `grid-row` and `grid-area` are
their shorthands. Auto-placement walks the grid in the flow's order and
takes the first free run of cells wide enough. An item that names one
axis keeps it and only the other is chosen, which is where the first
draft was wrong: auto-placement overwrote the named axis, and two
checks said so.

The `repeat()` form is checked against the tracks written out longhand,
and the shorthand against its two longhands — two ways of saying one
thing, which is the shape of check that can fail without either answer
being known in advance.

**Properties 149 → 158.**

Forty-eight checks in the new `tests/unit/test_grid.f`.

**A fifth instrument defect.** The four placement rows carried the value
`none`, which is not valid for those properties — and Chromium accepts
it, because a grid line may be named and `none` parses as a name. So
the rows measured named-line placement, which nothing here implements,
and a correct engine that rejects `none` scored zero for getting it
right. They carry `2` and `span 2` now, which are what the properties
are for; the audit still passes.

**A name collision that was a compile error in one program and nothing
in nine.** A local in the layout engine named `lineCount` met a
`lineCount` helper in one render suite, and the backend emitted a
reference to the function where the local belonged. The namespace is
global across every imported file, so which programs break depends on
which files are linked together. FINDINGS.md finding 3 gains the case.

**And a memory bug no test could see.** `parseTrackList` bound a token
to a local — `ascii tok = toks[i]` — which releases an alias the
compiler never retained. Every grid test passed and the program exited
0; valgrind showed an invalid read *and* an invalid write of size 8 in
`festina_ascii_release` on every track parsed. That is the fourth time
this exact shape has appeared in this repository, which is why the rule
is to index rather than bind (FINDINGS.md, finding 2).

**It costs pages without a grid nothing**, and this time that is
measured rather than asserted: the revision before this one and this one
were built side by side and timed alternately on the same idle machine,
at 92 to 98 ms and 94 to 99 ms on the benchmark page — two series that
overlap completely. A single run against the recorded 93 ms had
suggested a 3 ms regression, and Chromium's control row had moved by the
same proportion in the same run, which is what the rule about checking a
number you did not change is for.

### Four more, and an escape that was not one

- **`justify-items` and `justify-self`** move a block-level box in the
  inline axis of its containing block, once it has been sized and only
  into space it is not already using — which is why most boxes never
  notice the property. The container's `justify-items` is what a child
  with no answer of its own takes, and an auto margin wins over both, as
  the standard says.
- **`text-overflow: ellipsis`** cuts a line that runs out of a clipping
  box back to an ellipsis, dropping characters from the end until what
  is left plus the ellipsis fits. A line that fits is untouched, and so
  is one in a box that does not clip — there is nothing to hide there,
  and both are checks.
- **`pointer-events: none`** takes a box out of hit testing so that what
  is behind it is found instead, while its descendants are still
  searched, because a child may ask for pointer events back. It is the
  only value that changes anything here, and css-2026.md says so.

**Properties 145 → 149.**

Twenty checks in the new `tests/unit/test_alignment.f`.

**And an escape that was not one.** The ellipsis was written `\u2026`,
which Festina reads as the five characters `u2026` — an unrecognised
escape loses its backslash silently, with no diagnostic, so every
truncated line ended in `u2026` instead. `\t`, `\n` and `\\` are the
escapes the lexer knows and everything else falls out of the mechanism.
This is finding 7 in the other direction and it was caught the same way:
by comparing one character rather than eyeballing a string. FINDINGS.md
gains finding 34 and festina.md §3o. The workaround is to write the
character itself, which works but cannot be spelled portably.

### Containment

The second untouched specification off zero. `contain` takes `size`,
`layout`, `paint` and `style` in any combination, and both shorthands —
`strict` is all four, `content` is all but size, which is the whole
difference between them and what two of the checks ask.

**Size containment is the one that changes geometry.** A box with it is
laid out as if it had no content: its height is zero however much is
inside, and its intrinsic-width pass is *skipped* rather than run and
discarded, which is half of what the property is for. The five
`contain-intrinsic-*` properties supply the size an automatic one
resolves to instead. An explicit width or height still wins, because an
intrinsic size is a fallback rather than an override.

Each of those five does nothing without size containment, and a check
says so: `contain-intrinsic-height` on its own leaves the box measuring
its content. Without that check the property could pass by being applied
everywhere, which would be a different feature.

**Paint containment** clips the descendants to the padding box, through
the same offscreen image `overflow: hidden` uses — the fifth feature now
standing in for the clip region the canvas does not have.
**`content-visibility: hidden`** skips the contents entirely, painting
the box and nothing in it, and carries size containment with it.

Layout and style containment are computed and change nothing, and
todo.md says why: nothing escapes a box that way yet.

**Properties 140 → 145.**

Twenty-three checks in the new `tests/unit/test_contain.f` and five in
`tests/render/overflow.f` (11 → 16). Two of the new ones compare an
axis spelling with its physical twin and would have passed vacuously
while both were broken, so each also asserts the value is not the
uncontained one.

### Compositing and Blending 1 is blocked on Festina

`mix-blend-mode`, `isolation` and `background-blend-mode` all need a
compositing operator. The runtime sets `CAIRO_OPERATOR_SOURCE` at every
draw and exposes no call to change it, and Cairo has every Porter-Duff
and separable blend operator behind that one line. Recorded in todo.md
beside Fonts 3, which is blocked the same way.

### Transforms

The first of the snapshot's eight untouched specifications to move off
zero. `transform` takes `translate`, `translateX`, `translateY`,
`scale`, `scaleX`, `scaleY` and `rotate`, composed left to right;
`transform-origin` says what they turn about, defaulting to the box's
centre; and the individual `translate`, `rotate` and `scale` properties
say the same things separately, applied in that order before the
`transform` list. A percentage in a translate is of the box's own size.

A transform changes where a box and its descendants are painted and
nothing about the layout, which the standard is explicit about and which
is what makes it checkable: the same document is laid out once and
painted twice, and only the pixels differ. Three of the forty checks
assert the layout did not move.

The order the functions apply in is checked by asking that
`translateX(100px) scale(2)` and `scale(2) translateX(100px)` differ —
a list applied in the wrong order, or only in its last member, fails
that — and two translates are checked against the single translate that
says the same thing.

**`skew()` and `matrix()` are dropped**, which is the standard's own
answer for a function that cannot be applied. Festina's canvas composes
its matrix from `translate`, `rotate` and `scale` and has no call that
takes a matrix, so a shear cannot be expressed at all; the runtime
already holds a `cairo_matrix_t` and Cairo already has
`cairo_transform`, so what is missing is the entry point rather than the
capability. FINDINGS.md gains finding 33 and festina.md §3n.

The painter asks once per document whether any style carries a
transform, so a page without one pays a single bool rather than a test
on every box.

**Properties 135 → 140**: `transform`,
`transform-origin`, `translate`, `rotate` and `scale`.

Forty checks in the new `tests/render/transform.f`.

Not done, and in todo.md: a transformed box should establish a stacking
context and a containing block for its positioned descendants, and hit
testing should use the inverse transform, so today a click lands where
the box was laid out rather than where it is drawn.

### Four properties the machinery was already there for

- **`outline-offset`** moves the outline away from the border box and
  leaves the gap between them empty. The outline had no offset at all.
- **`table-layout: fixed`** (CSS2 17.5.2.1) takes its column widths from
  the first row and never measures a cell's content, which is the whole
  reason it exists: it skips the intrinsic-width pass rather than
  running it and ignoring the answer. A width in the first row is
  honoured and the rest share what is left; a width in a later row is
  ignored, which is what "first row" means and what the checks ask.
- **`empty-cells: hide`** (CSS2 17.6.1.1) drops a cell's background and
  border when it has nothing in it. A cell holding only collapsible
  whitespace counts as empty, because the whitespace is already gone by
  the time anything is painted.
- **`list-style-position: inside`** puts the marker in the first line
  instead of hanging it in the margin, so the content starts after it.
  Layout reserves the space and the painter draws into exactly that
  space, from one function, so the two agree by construction.

The last of those needed the list items numbered before layout rather
than after it: an inside marker's width is the width of its own label,
and `10.` is wider than `9.`. `numberListItems` runs as soon as the box
tree exists now, which also removes the two redundant walks the page
pipeline was making after every layout.

**Properties 131 → 135**, each on the field that names it.

Four checks in `tests/render/borders.f` (62 → 66), three in
`tests/render/basic_pixels.f` (35 → 40) and eleven in
`tests/unit/test_layout.f` (47 → 58).

### Text Decoration 3

The engine had `underline` and `line-through` and nothing else: one
solid pixel in the text's own colour. It has the whole specification's
appearance now — `overline`, `text-decoration-color`,
`text-decoration-style` in all five values, `text-decoration-thickness`,
`text-underline-offset` and `text-shadow`.

Four of the five styles are the ones a border has and are painted by
the border code, so `double`, `dotted` and `dashed` behave here exactly
as they do on a border. `wavy` has no border counterpart and is drawn
as stepped segments, because the canvas has no curve to follow.

**A decoration belongs to the box that asked for it.** `text-decoration`
does not inherit; the standard propagates it to descendant boxes and has
the *ancestor* draw it, in the ancestor's colour and style, across
everything it crosses. This drew it in the colour of whichever box it
was painting, so a blue `<span>` inside a red underlined paragraph broke
the underline into two colours. The colour, style, thickness and offset
travel with the propagated bits now. Where two ancestors decorate the
same text differently only the nearer one's appearance survives, which
css-2026.md records.

`text-shadow` casts the shadow of the text *and its decorations*, as the
standard says, which is also what makes it checkable: a glyph is
antialiased and never matches a colour exactly, while a decoration line
is flat colour.

**Properties 128 → 131** — `text-decoration-color`,
`text-decoration-style` and `text-shadow`; `text-decoration-thickness`
and `text-underline-offset` are implemented but cannot be graded,
because Chromium 141 does not report them on a computed style.

Thirty-eight checks in the new `tests/render/decoration.f`. The
benchmark was re-run on an idle machine: parse, style and lay out
generated.html is 93 ms against the 93 ms recorded, paint 5 ms against
6, so the per-fragment shadow test costs nothing measurable. Chromium's
control row moved 25.3 to 23.9 ms, inside the spread this file already
records for it, so no table is rewritten on this run's strength.

### An `arr` index is unchecked

Reading past the end of an `arr` is not a range error: an `arr[int]`
hands back whatever follows the buffer and an `arr[text]` segfaults in
`strdup`. A test here asked for the rows a decoration painted on, got an
empty list because the feature was not written yet, read `[0]` and
reported a row number in the trillions. FINDINGS.md gains finding 32
with the valgrind output and festina.md §3m the proposal.

### @supports was answering from a list nobody checked

`@supports` answers from `supportedProperties`, a list written by hand
in the CSS parser, while the property instrument measures what the
engine actually does. Nothing compared the two, and they had drifted in
both directions: **forty properties this engine implements were denied**
— every background longhand, `box-shadow`, `object-fit`, all eight
per-corner radii and the whole logical box — so a page testing for them
would take a fallback path it did not need.

The other direction was worse. `outline-style` was on the list, and the
engine had no outline style at all: the cascade read the keyword only to
decide whether the outline existed, and every outline painted solid. The
list's own comment says a property belongs there when something reads
it, "because claiming otherwise is the lie `@supports` exists to
prevent", and that is exactly what it was doing.

So `outline-style` is implemented rather than removed. An outline is
painted through the same code as a border side now, so `dashed`,
`dotted`, `double` and the four relief styles paint as themselves;
`none` draws nothing however wide it is asked to be, and a style with no
width takes `medium`. **Properties 127 → 128.** Fourteen checks in
`tests/render/borders.f` (52 → 62), including the longhands against the
shorthand.

The two lists are checked against each other on every run now. A
property that changes the computed style and is not on the list, or is
on the list and changes nothing, fails the suite and is named. One
honest disagreement is possible — `@supports` answers for the engine and
the instrument for an ordinary element, so `content`, which works on
`::before` and `::after`, registers as changing nothing on a `<p>` — and
that one is declared with its reason rather than tolerated silently.

This is the fourth instrument on this branch found unable to fail, and
the first that was not an instrument at all until now: nothing was
measuring `@supports`, so it could say anything.

### white-space was two properties all along

`white-space` is a shorthand for two independent questions — whether
spaces and newlines survive, and whether a line may wrap — and the
engine stored the product of the two as one enum of the shorthand's own
values. That enum has no room for `pre-line`, which preserves newlines
while still collapsing spaces, so `pre-line` was mapped to `pre-wrap`
and kept every run of spaces it should have collapsed.

The pair is stored as `white-space-collapse` and `text-wrap-mode` now,
which are real properties in their own right, and the shorthand expands
into them. `pre-line` behaves as itself. The five shorthand values are
five distinct pairs, and the checks say so: each is put against the two
longhands it stands for rather than against a number, which is the only
form of check that could fail if both spellings were broken the same
way.

Four more properties from the same specification:

- **`tab-size`**, as a count of spaces or as a length. A tab used to
  expand to four spaces with nothing able to change it; the initial
  value is eight.
- **`word-break`** and **`overflow-wrap`**, which both allow a break
  inside a word and differ on when: `break-all` breaks any word that
  will not fit in the room left on the line, `break-word` waits until
  the word would not fit on a line of its own. The engine had neither,
  so a long word simply overflowed.
- **`text-align-last`**, which aligns the last line of a block and any
  line the content broke itself. A `<br>` now closes a line differently
  from a line that merely ran out of room, which is the distinction the
  property is about.

**Properties 121 → 127**, and `--fields` shows each landing on the field
that means it rather than on a neighbour's.

Thirty-two checks in the new `tests/unit/test_text.f`, in layout rather
than in the cascade, because a property the cascade computes and layout
never reads is not implemented. Stubbing each of the three behaviours
back out fails six of them, which is the check that they can fail at
all.

### Every corner its own radius

`border-radius` read the first token and gave all four corners that one
number, so the shorthand's one-to-four-value form was three quarters
ignored and the eight per-corner properties did nothing at all.

Each corner now carries its own radius: the shorthand's values run
top-left, top-right, bottom-right, bottom-left with each missing one
taking the value of the corner opposite it, the four physical longhands
override it, and the four logical names — `border-start-start-radius`
and its family — map onto the physical corners. Every radius is capped
at half the shorter side of the box, which is the standard's rule for
overlapping curves. The elliptical `/` form is cut at the slash and only
its horizontal radii are read; css-2026.md says so.

**Properties 113 → 121**, and `--fields` shows each of the eight landing
on the corner it names — `border-end-start-radius -> radiusBottomLeft`
— rather than only on the aggregate `borderRadius`, which is what it
showed first and which would have scored all eight for one field.
`borderRadius` survives as the maximum of the four, because it is the
gate that asks once per box whether any corner is rounded at all.

Nineteen checks in `tests/render/borders.f` (33 → 52): each rounds one
corner and asserts the other three stay square, which is the shape of
check that the old code passed only by accident — one radius for all
four corners rounds the asked-for corner too. Two spellings are put
against each other where there are two: the longhand against the
shorthand slot it fills, and the two-value form against the diagonals it
means. Eight more in `tests/unit/test_logical.f` (48 → 56) put each
logical corner name against its physical twin.

### The logical box

Twenty-four logical properties did nothing: `border-block-start-width`,
`inset-inline-end`, `min-block-size`, `padding-block-start` and the rest
of that family were parsed and dropped. They are mapped onto their
physical twins now, along with the `inset`, `inset-block`,
`inset-inline`, `border-block` and `border-inline` shorthands and the
four single-edge border shorthands.

In a left-to-right horizontal writing mode this is a renaming and
nothing more — `inline-start` is the left edge, `block-start` the top —
which is exactly why the checks compare the two spellings against each
other rather than against a number: a check that `border-block-start-width`
computes to 7 would pass just as well if both spellings were broken the
same way. Forty-eight checks in the new `tests/unit/test_logical.f`, each
one a logical declaration and its physical twin computing the same
thing, and each also asserting the value is not simply the initial one
on both sides — which is the failure mode that would make an equivalence
check vacuous.

**Properties 89 → 113**, the largest move of the branch, and `--fields`
confirms each of the twenty-four lands on the physical field it should:
`inset-block-start -> top`, `max-inline-size -> maxWidth`,
`border-inline-end-color -> borderRightColor`.

**One ordering bug, found by the tests.** The four single-edge
shorthands kept failing after the longhands passed: the renames ran
*after* the shorthand dispatch, so `border-block-start` became
`border-top` too late for anything to handle it and arrived as a
longhand nobody knew. They are renamed at the top of `applyDecl` now,
before the dispatch reads the name.

This is an alias layer and would be wrong in any other writing mode,
which css-2026.md now says under Writing Modes 3 rather than leaving the
twenty-four to look like real support.

### groove, ridge, inset and outset

The last four border styles painted solid. They shade an edge against
its opposite now, which is what makes a box read as raised or sunken and
a line as carved into the surface.

- **`inset`** darkens the top and left; **`outset`** darkens the bottom
  and right instead.
- **`groove`** splits each edge in half and shades the halves
  oppositely; **`ridge`** reverses it.

The standard fixes only that the two colours are "based on" the border
colour (CSS2 §8.5.3), so the shades are the colour itself and half its
brightness — and the checks assert the relationships the standard *does*
fix rather than naming a shade: that `inset` makes opposite edges
differ, that `outset` is `inset` turned over, that `groove` splits one
edge into two, and that `ridge` is `groove` turned over. Naming a shade
would have tested this engine's arithmetic against itself.

Six more pixel checks, valgrind clean; dropping two of the four keywords
from the parser fails six of them.

With this, **every border style CSS defines paints as itself**, per
side.

### inset shadows

`box-shadow`'s `inset` keyword was parsed and thrown away. It paints
now, which closes the hole the last commit documented rather than
leaving it open.

An inset shadow is the padding box minus that box offset by the shadow's
lengths and shrunk by its spread — a band inside an edge rather than a
shape outside the box — drawn as the four rectangles between the two.
It goes over the background and under the content, so it is a second
pass rather than part of the one that puts the outer shadows underneath.

Seven more pixel checks, valgrind clean; stubbing the inset branch back
out fails seven of them.

**Two of those checks were wrong before the code was.** I had written
that an offset inset shadow bands the side it is offset towards. It is
the other way round: the *hole* is what moves, so shifting it right by
twelve uncovers a band twelve wide on the left. The standard says so
(§6.2, the inner rectangle is the padding box offset by the shadow's
offsets), and the implementation had it right — which is the fourth time
this session the measurement was the thing at fault rather than the
code.

### Why Fonts 3 is blocked, measured rather than assumed

The roadmap listed a numeric `font-weight` and `@font-face` as work to
be done. Neither can be done from Festina as it stands, and the roadmap
now says so with the evidence.

`changeFont` takes the weight inside a style string and the runtime
decides it by searching for one word, storing the answer in a
`cairo_font_weight_t`, which has two members. Measuring the same string
at every CSS weight gives 114 pixels for `normal`, `100`, `300`, `500`,
`600`, `700`, `900` and `lighter`, and 129 for `bold` and `bolder`:
every number measures as normal, `700` included, and `semibold` would
come out bold because the word contains `bold`.

This browser's cascade is not the problem — it maps the weights exactly
as CSS says, 600 and above to bold — and then has nowhere to put the
number. `@font-face` is closed by the same binding:
`cairo_select_font_face` is Cairo's toy API, which picks a family from
what the system has and cannot load a file.

FINDINGS.md gains the measurements and festina.md §3l the proposal: a
`changeFont` overload taking a numeric weight, resolved through
FontConfig or `cairo_ft_font_face_create_for_ft_face`, which is the same
call that would let a font be loaded at all.

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
