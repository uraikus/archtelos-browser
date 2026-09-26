# Changelog

The past, by change. Every other document except todo.md and
benchmarks.md describes the present (CLAUDE.md, §3).

## Unreleased

### The end of the input is not a tag terminator: 1535 → 1546

The standard reaches an end tag through the **end tag name state**, which
goes on into the tag on whitespace, `/` or `>` -- and on *anything else*
emits the `</` and the name it had buffered **as character tokens** and
returns to the raw-text state it came from. The end of the input is one
such "anything else". So `<script></script` gives the script the text
`</script`, while `<script></script ` is a real tag whose EOF then drops
it silently.

This engine treated the end of the input as a tag terminator, which
answered the second correctly and the first not at all: it lost the text.
Ten cases of `tests16.dat` were that, five shapes each appearing once with
a doctype and once without, and an eleventh came free in `tests2.dat`
because RCDATA reaches the same code -- `<title></title` keeps its text
too.

**The first fix was the wrong one and the corpus said so.** Flushing the
buffer from inside the end-tag branch gained those ten and lost thirteen,
1535 to 1532, because it flushed for `</script ` as well -- where the
standard has a tag, and an EOF inside a tag drops it. The narrow fix is
one condition in `findRawTextEnd`: an end tag needs a *real* terminator
after its name, not the end of the input. The two cases then separate by
themselves.

**1535 → 1546, and Chromium is 1535**, measured in the same minutes on the
same corpus. This engine is ahead on 29 cases and behind on 18; 88 are
failed by both, 84 of them the whole of `processing-instructions.dat`,
whose expected output is a processing-instruction node that the
bogus-comment state cannot produce. `CONFORMANCE_MIN` is 1546.

Seven checks in `tests/unit/test_html.f` say it directly, one per shape
plus the instrument that a *terminated* end tag still closes the script
and takes nothing with it -- without which every other check would hold on
an engine that never closed one.

### Fragmentation is recursive

A wrapper holding two 30-tall blocks, 210 wide in two columns of 100,
comes out **32** tall in Chromium with a rectangle in each column. This
engine left it whole, so the container became its full **64** and the
second column was empty: a multi-column container holding one such
wrapper degenerated to a single column. Not a wrong number so much as the
feature not applying.

Chromium's rule is simply the column algorithm at every level. With three
children it splits the **middle** one across the break, 15 either side;
with one 70-tall child it splits that, 35 either side. Both are the
operation `cutUnitIntoColumns` already performed on a direct child, one
level deeper.

So the unit collector descends. A child that is a plain block in normal
flow, holds no lines, has children and was not forbidden by
`break-inside: avoid` contributes **its descendants'** units instead of
one unit of its own, and the first and last of them carry its opening and
closing edges the way a paragraph's first and last lines already carried
what sat above and below them. What is not descended into is what the
flow does not simply stack -- a flex or grid container, a table, a scroll
container, a box with columns of its own.

**The wrapper's own rectangles are read off its children rather than from
the plan**, because by the time it is sized they have been moved: a
child's `x` says which column it is in, and a child that was itself cut
reaches into its parts' columns too. Grouping them by column gives one
part per column, and the rule is the one every other part here follows --
a part that is not the last fills its column, and the last is its own
content plus the closing edge. A wrapper inside a wrapper works provided
the inner one is sized first, which is why the pass walks the record of
descended boxes backwards.

`childIndex` could not be reused to say which box a unit belongs to: the
paginator reads it back as an index into the host's children, and a unit's
box may now be a descendant. Units carry `unitBoxId` for that instead.

The pixel suite gained the check only pixels can make -- that the
wrapper's background and border are painted in the second column, behind a
child that was never inside its first rectangle -- and seven of its twelve
new checks fail when the parts are not built. The paginator shares the
collector and its two suites pass unchanged, 128 and 106.

Clean under valgrind, counts unchanged: 290/405 properties, 122/122
displays, 129/129 selectors, 1535/1652 conformance. Paired on both pages,
each still rendering byte-identically: **+1 then -1** forward on
`features.html` and **-1 then +2** on `generated.html`, the two forward
rounds disagreeing in sign on both, so this fails at the first gate rather
than the mirror. Neither page exercises the recursion -- `features.html`'s
columns hold paragraphs, which hold lines -- so what was measured is the
predicate's cost to the pages that do not use it, and it is nothing. The
binary grew 4,256 bytes.

### `box-decoration-break: clone` takes space in every column

`clone` puts the whole box on every part of a broken one, so the repeated
edges are *in* the columns and the columns have to be taller to hold them.
Chromium on four lines of 20 in a paragraph with a 2px border, two columns
of 100: **44 with `clone` against 42 with `slice`**, each part 44 rather
than 42. This engine gave 42 either way and painted the cloned edge over
the bottom of the last line's box -- the border was there, in the right
colour, two pixels above where it belonged.

The accounting goes in `columnPlan`, at the two places it takes a break:
the column that ends there closes with the box's lower edge and the one
that starts opens with its upper one, so the ending column's height gains
the closing edge and the starting column's top moves up by the opening
one -- which is what puts the lines after the break below the edge instead
of at the column's very top. Both fall out of one number per side,
`cloneEdgeTop` and `cloneEdgeBottom`, which are zero under `slice` because
the first part's opening edge and the last part's closing edge are already
in the flow.

Only a child whose **lines** are split asks this. A childless block is cut
in its border box, which carries its own edges wherever the cut falls.

The pixel suite had an expectation that was stale in exactly the way the
fix intends: it looked for the first part's closing border at 41, where it
sat while the column height was worked out without it. It is at 42 and 43
now, below the last line rather than over it, and the suite says both --
that the border is there and that 41 is no longer part of it.

### A child whose lines are split gets a part per column

Its lines were always moved into their columns; what it did not have was
a rectangle in each of them, so every column after the first had nothing
painted behind its lines. The parts `Box.frags` already held for a
childless cut block are the same shape, and Chromium's rule for this case
is the one `cutUnitIntoColumns` already follows: every part but the last
fills its column, and the last is its own content's extent. Three lines
in two columns of 100 are **42 and 22**, not 42 and 42.

**Three separate defects, and the rectangle was wrong before the parts
were missing.** `refitFragmentedChild` cut the box back to its first
column by reading its *lines*, so the box's `x` came out as the first
line's `x` -- inside its own left border, 2 where the border box starts at
0 -- and its `y` and `h` likewise came from the lines rather than from the
column. That was true of a child that was *not* split as well, since the
refit ran for every line-bearing child.

**And a column was short by the box's opening edge.** A per-line column
unit's top was the line's top, and only the *last* line's unit was
stretched to cover the box, so nothing carried the border and padding
*above* the first line. Three lines with a 2px border came out 40 here
against Chromium's 42. The first line's unit now starts at the box's
margin-box top, which is the mirror of what the last one already did.

`buildLineFragments` replaces the refit. It reads the same plan the
placement loop read, so the parts land where the lines did, and it reads
the columns' final height rather than the balancing target, because a
unit taller than the target sets its own column's height. A child whose
lines all sat in one column comes out of it unchanged, which is why it
does not test for a split first.

Measured against Chromium on four fixtures -- four lines, three lines,
five lines with padding below them, and four lines under a 14-tall block
-- and this engine now gives its numbers on all four, containers
included. The pixel checks in `tests/render/colfrag.f` grew from 20 to
31, and eight of the eleven new ones fail when the parts are not built.

What stays open is a block whose own **children** straddle a break, which
would have to be laid out again in the next column, and
`box-decoration-break: clone` making the container taller -- 44 against
42, because the repeated edges take space in every column. Both are in
todo.md with Chromium's rows.

Clean under valgrind, counts unchanged: 290/405 properties, 122/122
displays, 129/129 selectors, 1535/1652 conformance. Paired on both pages,
each rendering byte-identically between the two binaries: `generated.html`
runs none of the new code and read **-3 and -4** forward, `features.html`
runs it and read **+4 and +2** forward against a mirror of +1. A control
that finds a saving in lines it cannot execute is the instrument
describing itself, so this is reported as nothing; benchmarks.md has the
rounds. The binary grew 40 bytes.

### A childless fixed-height block is cut at a column break

Chromium fragments a block whose height does not fit what is left of its
column; this engine moved whole boxes and never split one. The rows are
in todo.md, read with `getClientRects`, which returns one rectangle per
fragment where `getBoundingClientRect` returns only their union -- which
is why the earlier note had the union and not the parts.

**The engine's old answer was Chromium's answer for `break-inside:
avoid`** on all three counts: the box moved whole, it went to the next
column, and the balanced height grew to hold it. So the gap was a missing
choice rather than a wrong number, and the fixture that says so is the
one this change has to keep passing: `avoid` must still move the block
whole, or every check about the cut would hold on an engine that split
unconditionally.

**A box keeps its first part and carries the rest.** `Box` gained
`frags`, and the parts after the first go there; every reader that knows
nothing about fragments -- which is all of them but the painter and the
hit tester -- goes on reading `x`, `y`, `w` and `h` and gets the first
part, exactly as `refitFragmentedChild` has always left a child whose
lines were split.

**It is a field and not a side map, and the test is what settled that.**
The first version kept the parts in a flat array with two maps giving
each box its range, to keep an empty array off every box on every page.
Box ids start again with every layout, so the map outlived the boxes it
described: the suite lays several documents out and keeps them all, and a
whole block read as split because a later layout's block had taken its
id. That is the same hazard as a scroll offset outliving its document,
one layer down, and it was caught by the one check in the new set that
asked about a box from an earlier layout.

**Only a childless block is cut**, because a block holding lines or
children would need that content re-placed in the column after the break,
and this engine breaks nothing deeper than the container's own children.
A childless block has nothing to re-place: its height is the whole of it.

**One walk decides the columns now.** `columnBreaks` returned the indices
a column starts at and the placement loop re-derived the rest; a break
can now fall *inside* a unit, which an index cannot say. `columnPlan`
records the column, the offset and the cut for every unit, and the
placement loop only reads them -- the two cannot disagree, which is what
the old function's comment already said mattered. Nothing in the walk
writes to a box, because the balancing loop runs it several times with a
growing target and a walk that had shortened a box would plan the next
round against the height it had just changed.

The first version of that walk had a real bug of its own: when
`columnBreakPoint` put the break *after* the unit that overflowed -- which
is what `break-before: avoid` asks for -- it jumped to the break and left
the units in between unplanned. Four checks in the fragmentation suite
failed on it, which is what a suite is for.

**`box-decoration-break` decides the break edge**, measured in Chromium's
pixels both ways: `slice`, the initial value, paints no border across the
break and lets the background run to the column's end; `clone` paints
one. The sides and the background are on every part either way. The part
is painted by moving the box to it, painting, and putting it back, so
every painter reads the same fields it always did.

**And a part answers the pointer.** Chromium's `elementFromPoint` names
the block at every point in every part. That needed the rectangle test
widened in two places, not one: `hitChild`, and the cull in
`hitPhaseWalk` that rejects a child before `hitChild` is reached. The
second was found by a check that failed after the first was written --
the same third-place lesson `interactivity: inert` taught.

`balance` now gives Chromium's answer where it did not: 20 and 30 in two
columns balance to 25 with the tall block cut, against the 30 that moving
it whole produced. A block taller than a whole column splits as many
times as it needs.

Clean under valgrind, counts unchanged: 290/405 properties, 122/122
displays, 129/129 selectors, 1535/1652 conformance. Paired on
`generated.html`, which declares no multi-column container and so cannot
reach the new code -- **+0 and +1 forward, -3 reversed**, against a parent
whose own total moved 139 to 137 between two rounds of identical code.
Reported as nothing; benchmarks.md has the rounds. The binary grew 5,184
bytes, which is the only thing here that can be measured at all.

### A scroll offset no longer outlives its document

`boxScrollTops` and `boxScrollLefts` are keyed by **node id**, because a
box tree lasts one layout and a scroll position has to outlive several.
Node ids start again at 1 for every document, and nothing cleared the
two maps, so whichever element of the next page took a scrolled
element's id opened part-way down. The fixture shows it exactly: a
container scrolled 200 down and 150 across, and the next document's
container starting at 200 and 150.

**The fix is not the line todo.md predicted.** It said `cascadeReset`,
where `resize` clears its own two maps for the same reason. That cannot
work: the dragged sizes live in cascade.f because they reach layout as
declarations, while the scroll offsets live in layout.f, which imports
cascade.f -- so `cascadeReset` cannot name `boxScrollReset` without a
cycle. It goes beside `nodeRegistryReset` in the page pipeline instead,
which is the truer pairing: the line that restarts the ids is the line
the offsets are keyed on.

`boxScrollReset` already existed and was called from the suite only.

The checks go in `tests/render/pagestate.f`, whose whole subject is what
leaks from one document into the next, and they assert the invariant
rather than a number: a fresh document's scroll container starts at the
top and at the left, whatever was scrolled before it.

**A reload now starts a scrolled box at the top**, where the shell keeps
the page's own `scrollY` on purpose (`reload` saves it across
`loadInto`). That is the standard's position -- the inner offset belongs
to the document instance that was replaced -- and it is a real change in
behaviour, not only a leak closed.

No count moves, and no benchmark round: the two assignments run once per
document load, outside every loop over boxes or declarations.

### `math-depth`, which acts only beside `font-size: math`

The keyword `math` on `font-size` is the parent's size scaled by **0.71
per step of `math-depth` away from the parent's own depth**. Chromium at
32px: one step is 22.72, two 16.1312, three 11.4532, and minus one
**45.0704** -- a negative depth grows the text. `add(2)` is the parent's
depth plus two, and `auto-add` adds nothing outside MathML, which this
engine does not render.

**From the parent's depth, not from zero**, which two fixtures pin down:
a child with `font-size: math` at depth 2 inside a parent already at
depth 2 computes the parent's own size, and `add(1)` inside a parent one
step down takes one more step rather than two from the root.
`math-depth` inherits, which is what makes the parent's depth available
to subtract.

The reader sits **before the font size** rather than with the other
appliers, because that is what the font size needs -- and `font-size:
math` already computed to the parent's size before this change, since
`parseLength` could not read the keyword and fell back to it. So the
whole of the change is the factor, and the keyword that was silently
doing the right thing at depth 0 now does the right thing everywhere.

**`math-style` is a decline beside it**: the same fixture gives
`compact` and `normal` the same size in Chromium, so the two must agree
here rather than differ, and the suite asks them to.

**289 → 290**, and the instrument's row carries `font-size: math` as
context, because `math-depth` alone changes nothing -- in Chromium
either, which is the measurement that says the context is honest rather
than convenient. `--fields` then names `fontSize`, `marginTop`,
`marginBottom`, `mathDepth` and `fontKey`: the property's own field and
the four things that follow a font size.

Paired on `generated.html`: **-7 forward and -6 reversed**, both
directions favouring whichever binary ran second, with the parent's own
total at **145 and 142** against 126 to 128 that morning. That is the
day's drift outgrowing the thing being measured, and benchmarks.md now
records the whole series -- the paired comparison has stopped resolving
a per-feature difference on this machine, which is a fact about the
machine and worth writing down rather than working around.

### The sweep: `view-transition-name` acts, and eight properties do not

The reachable pool had thinned to where the honest first step was to ask
Chromium whether a property does anything in HTML at all, before
implementing it. Two fixtures answered eleven rows.

**`view-transition-name` creates a stacking context**, which is the
whole of what it can do in a browser with no clock to transition with,
and this engine has stacking contexts -- so it is one line beside
`isolation`. Only whether a name was given is stored, not the name:
nothing here would read it, and the behaviour is a boolean.

**Eight declines with a measurement behind them.** `font-stretch` at
`50%` and at `condensed`, `text-size-adjust`, `math-style`,
`text-rendering`, `font-optical-sizing` and `font-kerning` all leave
`MMMM` at exactly the unstyled 77.06 at 32px monospace; and
`paint-order`, `overflow-anchor` and `text-size-adjust` leave a
`z-index: -1` child behind its parent's background, so none of them
creates a stacking context either. `font-stretch` wants a condensed
face and Chromium will not synthesise one, `text-size-adjust` is a
mobile inflation control a desktop ignores, `math-style` needs the
scaling its companion does without it, and the rest are hints. An
engine graded against Chromium has nothing to copy where Chromium does
nothing.

**And one more that acts, left for its own change**: `math-depth`
scales the font beside `font-size: math`, by 0.71 per step of depth
*from the parent's depth* -- which two rows pin down, since a child at
depth 2 inside a parent at depth 2 computes the parent's own size.
todo.md has the table.

**288 → 289**, with `--fields` naming `viewTransitionName`. Paired on
`generated.html`: **+3 forward and +3 reversed**, so whichever binary
runs second pays three milliseconds and neither number is a difference
between them -- the mirror image is supposed to cancel the forward
reading, and two of the same sign say the machine is measuring the
order.

### `scroll-initial-target`, which is the start edge and not the nearest one

A scroll container whose descendant declares it starts scrolled so that
the target's **start edge** is at the container's own start edge. That
is 150 on Chromium's fixture and not the minimal 110 the keyword
`nearest` suggests, so the name describes **which container is chosen**
rather than where in it the target lands -- and only the nearest one
moves: an outer container around it stays at 0 even though the inner
container is itself below its own scrollport.

**The document is a scroll container for this too.** A target 900 into
the page's own flow leaves Chromium's `scrollY` at 900, and this engine
answers it through a field on `Page` that the shell applies on
navigation -- because `layoutDocument` returns a box and the shell owns
the page's scroll position. `reload` still keeps the reader where they
were, which it does by overwriting that offset on purpose.

The container case is a pass after layout rather than anything in it,
because it needs every box's final position: one walk of the tree on a
document that declares the property, and one boolean on one that does
not. The offset goes through `boxScrollTops`, keyed by node id, clamped
by `boxScrollRange`, which is the same path a wheel takes.

**A text box inside the target set the offset back to zero.** It shares
the target's own computed style -- the same serial, so
`scrollInitialTarget` answers the same for it -- while its `y` is not
the target's, so the walk found the target, set 150, then found the text
inside it and set 0. Every property kept by a style's serial has that
shape, and this is the first one where a text box's own *position*
mattered; the pass asks for an element's box now.

**287 → 288**, with `--fields` naming `scrollInitialTarget`. Paired on
`generated.html`: −1 and +4 forward and −2 reversed, with the parent's
own total at 135, 130 and 131 across the three runs. Two forward rounds
that disagree by five milliseconds on a control that moved by five are
not a reading of anything.

### `interactivity: inert`, which is not `pointer-events: none`

Hit testing is what this engine has of interaction, and `inert` is a
hit-testing rule: it takes the element **and its whole subtree** out of
hit testing, and nothing inside can undo it. That last clause is the
whole difference from `pointer-events: none`, whose descendants this
engine searches *on purpose* because a child may ask for pointer events
back -- so `inert` returns before the subtree is walked where
`pointer-events` returns after. `inert` also beats `pointer-events:
auto` on the same element.

The computed value does not inherit, which is measured: the child of an
inert element computes to `auto`. What reaches the subtree is the
inertness rather than the property, and the hit tester stopping above it
is exactly that.

The rest of what `inert` means in CSS UI 4 -- no focus, no selection, no
`:hover` -- has nothing here to act on, and that is recorded rather than
implied.

What the point lands on instead is whatever is behind the subtree: the
root element in Chromium, an anonymous box here. So the checks ask that
nothing in the inert subtree is hit rather than that nothing at all is,
which is the honest form of the same statement -- and one of them failed
first as `none` against `anon`, which is how the distinction was
noticed.

An **inert inline** is skipped too, and the box behind it answered --
which is the one case where `inert` and `pointer-events` agree, because
a run of text cannot ask to be hit again. That one was found by asking
the engine rather than reading it: the block-level cases passed while a
`<span>` with `interactivity: inert` was still being hit, because the
inline path in `hitLines` is the third place the walk can reach content
and the first two are where the obvious guards go.

**286 → 287**, with `--fields` naming `interactivity`. Paired on
`generated.html`, which does no hit testing at all in a `--screenshot`
run: −1 and +0 forward and +1 reversed. The parent's own total read 135,
133 and 133 across the three runs against 127 earlier in the day, so the
machine has drifted further than anything being looked for -- which is
the reading, rather than a reason to keep running rounds.

### The three baseline properties, declined with a control behind it

`dominant-baseline`, `alignment-baseline` and `baseline-shift` have rows
in the instrument and are defined for CSS as well as SVG, so they look
implementable. Chromium moves an HTML inline box by **exactly nothing**
for all three -- against a `vertical-align: 10px` control that moves the
same span ten pixels and grows its line box from 40 to 50 to hold it.
The control is the point: the fixture can see a baseline shift when
there is one. An engine graded against Chromium has nothing to copy, so
all three stay unimplemented with a measurement behind them rather than
a gap.

### `will-change`, which is two predicates rather than a hint

There is no compositor here to hint at, so the hint half of CSS Will
Change 1 is nothing -- but the specification also says a `will-change`
naming a property that *would* create a stacking context creates one
before the property is ever set, and the same for being a containing
block. Both of those exist in this engine already, so both are the
property.

**The two lists are different**, which is the finding. Seventeen names
create a stacking context: `transform`, `opacity`, `filter`,
`z-index`, `position`, `contain`, `isolation`, `mix-blend-mode`,
`clip-path`, `mask`, `perspective`, `rotate`, `scale`, `translate`,
`offset-path`, `backdrop-filter` and `view-transition-name`. Ten of
those also make the element a containing block for absolutely
positioned descendants, and the other **seven do not** -- `opacity`,
`z-index`, `clip-path`, `mask`, `isolation`, `mix-blend-mode` and
`view-transition-name` create a context and no containing block, and
nothing does the reverse. That subset relation is what lets one
ordered value say both.

The names are case-insensitive and a comma list asks for the strongest
thing any one of its names asks for, so `left, transform` is a
containing block because `transform` is. A `fixed` child takes the
containing block too, as it does from a real transform.

Both effects go through predicates that already existed --
`boxIsStackingContext` in the painter and `boxTransformsPositioned` in
layout -- so the change is two lines of behaviour and a reader, all of
it behind `anyWillChange`.

The checks are agreements with what the engine already does rather
than colours or coordinates of their own: a qualifying `will-change`
must paint what `z-index: 0` paints and place what
`transform: translateX(0px)` places, and one that does not qualify must
match declaring nothing at all.

**285 → 286**, with `--fields` naming `willChange`.

Paired on `generated.html`, three forward rounds read +1, +5 and −2 and
the mirror −2: nothing that agrees with itself, so nothing to take to
the code. The reason to believe that rather than chase the +5 is in the
table's own last column -- **the parent's total moved 130, 129, 133,
132 across the four runs**, which is a wider spread than the difference
being looked for. A run whose control drifts by four milliseconds
cannot answer a question about one.

### `image-rendering: pixelated`, drawn rather than asked for

This engine scales an image through `drawImage`, which filters, and the
runtime does not say how -- so nearest-neighbour resampling had to be
**drawn**: `img.getPixelColor` reads a source pixel and a rectangle
fills the destination block it maps to, which is the pair the clip
machinery already uses a row at a time. A destination pixel takes the
source pixel at `floor(dx * sw / w)`, which is where Chromium puts its
boundary, and consecutive destination pixels sharing a source pixel are
one fill -- so the work is one rectangle per source pixel where the
image is enlarged and one per destination pixel where it is reduced,
the smaller of the two in each axis either way.

`crisp-edges` is **`auto` in Chromium, pixel for pixel**, which the
standard does not say and Chromium does anyway, so the two compute to
the same value here rather than to a second non-smoothing keyword.
That was measured, not assumed.

The checks need no colour written down: a nearest-neighbour enlargement
contains only colours the source contains, so the middle of each
enlarged block must be exactly what the unscaled image paints at that
pixel, and the boundary pixel either side must be the two source
pixels it falls between with nothing in between them. The fixture's
top edge varies across its own three columns, which is what makes nine
samples nine different colours -- and is also what caught the boundary
expectation being written from the region rather than read from the
source.

All three paths a replaced element's content can take go through it:
the `fill` stretch, the direct blit and the clipped layer, the last
drawing into the layer rather than the canvas.

**284 → 285**, with `--fields` naming `imageRendering`. Paired on
`generated.html`, which has no image on it and executes none of the new
code: −2 total across two agreeing forward rounds and +0 reversed,
which is the candidate reading a shade *faster* and so the compiler's
placement rather than work either way.

### `font-synthesis-small-caps`, and three synthesis controls that cannot act here

Small caps in this engine **are** a synthesis -- no face it can reach
carries the feature, so a lowercase letter is drawn as its capital at
0.7 of the size -- which makes `font-synthesis-small-caps: none` a
refusal with something real to refuse. It puts the run back at the
width and the pixels it has with no `font-variant-caps` at all.
Chromium's widths are in todo.md and this engine now agrees with them.

The `font-synthesis` shorthand reaches it, and is **written out into
its three longhands** rather than read beside them, so the two are
decided by source order like every other pair here. The shorthand names
what may be synthesised, so a component it leaves out is a refusal:
`font-synthesis: weight style` declines small caps. `auto` is not one of
its values and `font-synthesis: auto` is an invalid declaration dropped,
which Chromium confirms -- the longhand before it stands.

**The other three cannot be told apart, and one of them for an
interesting reason.** `font-synthesis-weight` and
`font-synthesis-style` have nothing to act on: this engine hands `bold`
or `italic` to `changeFont` and the runtime chooses or synthesises a
face without saying which. And `font-variant-position` **synthesises
nothing in Chromium**: `sub` and `super` leave the advance at exactly
normal's, because the family has no `subs` or `sups` feature and
Chromium does not draw a smaller glyph on a shifted baseline instead.
The small-caps machinery would make synthesising it easy here, and
doing so would disagree with the yardstick, which is a reason not to
rather than an obstacle.

**A fourth stale key, found by the suite rather than by reading.** The
width cache is keyed on `fontKey`, which carries the font size, the
weight, the style, the family, the zoom and the caps keyword -- and now
the refusal, because two styles alike but for it measure differently.
Without it the same string in two documents, one refusing and one not,
served the first document's advance to the second: the checks failed
with the cascade already answering correctly, which is what said the
cache rather than the cascade was wrong.

**283 → 284**, with `--fields` naming `fontSynthSmallCaps`, and the
instrument's row carries `font-variant-caps: small-caps` as context
because there is nothing to decline to synthesise without it.

The change adds two string comparisons per declaration to the scan that
raises the per-document flags, and a guarded block to `refreshFontKey`,
so it was paired on `generated.html`: +1 total across two agreeing
forward rounds, and **+2 reversed**. Both binaries read slower running
second, which is the order and not a difference between them -- the
mirror image is supposed to cancel the forward reading, and two of the
same sign say the machine is measuring itself.

### `text-combine-upright: all`, the last property in Writing Modes 4

An inline that asks for it is typeset horizontally inside **one square
of its own em** along the inline axis, whatever it holds: one character
is widened to the em and six are condensed into it, a space inside the
run is content like any other, and an empty run takes no room at all.
Chromium's rows are in todo.md and this engine now agrees with them.

It **inherits**, which is what makes a nested element a combined run of
its own rather than part of its parent's, so `<span all>1<span>2</span>
</span>` is two ems; a child declaring `none` is ordinary text. The
property says nothing in a horizontal mode.

The em is the element's own rather than the line box: `line-height:
40px` around it changes nothing, and borders and padding add outside it.

Three places read it, all of them behind the one global a page with no
vertical text pays for. `measureWidth` answers the em instead of
measuring, in the same branch that already counted an upright run's
cells -- which now costs a page in a horizontal mode one global read
where it used to cost a call. `placeTextUncounted` hands the run to
`placeCombined`, which joins its words back and places the square as one
unbreakable thing, because the square is the element's text rather than
its words. And `computeIntrinsicUncounted` answers the same square for
both intrinsic sizes, which is what a shrink-to-fit box around one asks
for -- found by the space in `1 2` coming out two squares wide in a box
sized by its content while the line itself was right.

The painter sets the run horizontally and centres it across the line,
condensing anything wider than the em to fit rather than letting it out
of the room layout kept. Chromium condenses by choosing a condensed
face where the family has one and scaling where it does not; no face
here has one, so this scales.

The checks need no number from either engine: a line holding a combined
run is the same length whatever that run's text is, and longer than the
same line with the text left uncombined. In pixels, against the same
text uncombined in the same mode, the combined run's ink is shorter
down the line and wider across it, and lies inside the square layout
reserved -- three checks that fail when the painter's branch is taken
out.

**The cascade's own read of it is behind a per-document flag**, and the
benchmark is why. One `styleProp` lookup per element, for a property no
page in the benchmark declares, read **+3 and +4 of 126 ms** on
`generated.html` across two agreeing forward rounds -- the shape this
project's rules call real, on a page that cannot execute one line of the
feature. A third binary with that one lookup deleted and everything else
kept read **-2**, which pins it to the lookup rather than to where the
compiler put the code. `cascadeSawTextCombine`, raised by the same two
declaration scans that raise `cascadeSawWritingMode` -- the stylesheet
rules and the inline `style` attribute, the second of which is what lets
the element raising the flag benefit from it -- takes the reading to +0
and -5 forward and -3 reversed: two forward rounds that disagree, which
is this project's own definition of nothing.

**282 → 283**, with `--fields` naming `textCombine`, the property's own
field. `tests/run.sh` raises its floor to match.

Two numbers elsewhere had gone stale and are corrected with it.
css-2026.md's headline read 284 of 418, which was the count before the
thirteen shorthand rows came out of the instrument and took the
denominator back to 405. And README said the engine implements no part
of two of the snapshot's specifications, where css-2026.md has said for
some time that Compositing and Blending's `isolation` is implemented
and only Easing is untouched.

### The scroll box in a vertical flow was right, and now something asks

The last item on CSS Writing Modes 4 read "a scroll container inside a
vertical flow reserves its bar on the physical axis", written as though
that were the bug. It is what Chromium does. A scrollbar is a physical
thing and `overflow-x` and `overflow-y` name physical axes, so neither
the bar nor the room it takes moves with the writing mode; what follows
the mode is the **logical** pair, and this engine already had that right
-- `overflow-block` is `overflow-x` in a vertical mode and `overflow-y`
in a horizontal one, which `wmPhysicalName` has answered since the
vertical modes landed.

Fifteen rows of Chromium, and this engine agreed with every one before
these checks existed. **That is the point of the change**: CLAUDE.md's
rule is that a claim of this shape has no instrument behind it until one
is written, and nothing here asked. The checks ask the two spellings that
are synonyms in a given mode to reserve the same bar, which needs no
number from either engine, and they were made to fail before being
believed: reversing `wmPhysicalName`'s two `overflow` lines breaks eight
of them.

No engine code changed, so there is nothing for a benchmark to move.
This is the fifth sentence in this stretch of work that was wrong for
want of a probe, and the second whose correction is a test rather than a
fix.

### `column-fill: auto` fills each column to the container's own height

It was filling them to the **balanced** share instead, so 20 and 30 in a
container of 60 went into two columns where Chromium puts both in one.
All four of Chromium's `auto` fixtures now agree:

| height | items | before | now, and Chromium |
|---|---|---|---|
| `60px` | 20, 30 | 0,0 / **55,0** | 0,0 / **0,20** |
| `60px` | 20, 20, 20 | 0,0 / 0,20 / **55,0** | 0,0 / 0,20 / **0,40** |
| `40px` | 20, 20, 20 | 0,0 / 0,20 / 55,0 | unchanged |
| auto | 20, 30 | 0,0 / 0,20 | unchanged |

**The comment above the line is the reason it went unnoticed**, and it
was a claim about Chromium written from memory: "Given a definite height
the two agree, and the balancing below is what produces it." They do not
agree. `auto` fills to the height *declared* and `balance` to the height
*computed*, and those coincide only by arithmetic accident -- which is
exactly what the suite's own fixture was. Twelve 20px blocks over three
columns balance to 80, and 80 is the height it declares, so the check
that `auto` and `balance` put the fifth block in one place passed while
saying nothing. That comment in the test now says which coincidence it
rests on.

**Cost: nothing.** The two binaries are the same size to the byte -- the
change reorganises a branch rather than adding one, and the balancing
path is untouched. Paired on `features.html`, which has the two
multi-column containers, two forward rounds give a total of +4 and then
-4, with 18 of 25 pairs slower and then 7 of 25.

### A fixed-height block is still not fragmented across a column break

The same probe shows it and it is its own piece of work: Chromium splits
a 30-tall block across two columns of 25, leaving its rectangle the union
of the two halves, where this engine moves whole boxes and never splits
one. So `column-fill: balance` with no height gives 30 here against
Chromium's 25, and `auto` with a height of 25 keeps both blocks whole
where Chromium fragments the second. todo.md records it with the rows.

### A definite height on a table reaches its rows (CSS2 17.5.3)

`<table style="height: 60px">` over rows needing 50 left the rows at
their content heights and the table as tall as their sum, so the
declaration changed nothing at all. All seven of Chromium's fixtures now
match, and three of them are the rule:

| rows | table | before | now, and Chromium |
|---|---|---|---|
| 20, 30 | `60px` | 100x50, rows 20/30 | 100x60, rows **24/36** |
| 20, 30 | `100px` | 100x50, rows 20/30 | 100x100, rows **40/60** |
| 10, 20, 30 | `120px` | 100x60, rows 10/20/30 | 100x120, rows **20/40/60** |
| 50 (on the row), 30 | `100px` | 100x80 | 100x100, rows **63/38** |
| 20, 30 | `40px` | 100x50, rows 20/30 | unchanged |

**The surplus is shared in proportion to each row's own height**, not
equally and not to the last row -- which is why 20 and 30 in 60 are 24
and 36, both scaled by 1.2, and in 100 are 40 and 60, both scaled by 2.
A row's own declared height feeds the proportion rather than being
exempt from it, which falls out of scaling the heights the row loop
already arrived at. And **a declared height is a minimum**: `40px`
against 50 of content is ignored, and the table stays 50 tall.

The cell stretch is now a function, because the post-pass calls it a
second time to grow a row. The second call sees `cell.h` at the old row
height, so the vertical-align shift it applies is the one the growth
adds, and the two compose rather than double-counting.

**Each row is rounded on its own, as Chromium rounds them**, so 50 and 30
scaled to 100 are 63 and 38 -- which sum to 101. The table keeps the
height it was told and the last row overflows by a pixel, rather than the
remainder being handed to it. The checks name numbers only there, because
the rounding is part of the answer and a ratio would be satisfied by
neither; everywhere else they are proportions, which hold whatever the
rows' content heights turn out to be.

**The benchmark caught a real cost, and the guard is because of it.**
The row loop collected every row and its height so the post-pass could
scale them -- two array pushes per row, on every table, whether or not
the table declared a height. Paired against the parent on
`generated.html`, which has forty tables and declares no table height,
that read **+2 of layout across two agreeing forward rounds**: the
shape this project's rules call real, on the phase that genuinely runs
the diff, with a mechanism to point at. Collecting the rows only where
the table declares a height took it to -1 and 0, and the totals from
+4 and +1 to 0 and -2. A table that declares none -- which is every
table the user-agent stylesheet makes -- now pays one `Len` read.

**Found by the writing-mode fixtures**, which walked past it: a
`display:table` with `block-size` came out 100x50 where Chromium gives
100x60, and the agreement checks could not see it because both sides of
the turn shared the gap.

### A physical side on the wrong axis is invalid in `anchor()`

`top: anchor(--a left)` names a horizontal edge for a vertical inset.
Chromium treats it as it treats any value it cannot parse -- the
declaration has no effect and the box keeps its static position -- and
this engine answered it, giving `top` the anchor's *top* edge: the two
keywords were being read by position rather than by which axis they
name. Wrong in the plain horizontal writing mode since `anchor()`
landed, and nothing to do with writing modes; found while probing them.

The check is an agreement rather than a number, so neither answer has to
be known in advance: a wrong-axis side must behave exactly as a keyword
that does not exist, because both are invalid. Its instrument asks that
an unknown keyword and a valid one land in different places, or the four
checks would hold on an engine that accepted everything.

**Cost: nothing.** The two binaries are the same size to the byte, and
`anchorSidePct` runs only for a declaration that contains an `anchor()`.
Paired on `generated.html`, two forward rounds give a total of 0 and
then +2, which do not agree.

**Three of the four findings from that probe are not in this change**,
and todo.md carries Chromium's numbers for each. `start` and `end`
follow the containing block's inline direction where the property's axis
is the inline one and its block direction where that axis is the block
one -- so `direction: rtl` reverses them on the horizontal axis, and so
does `vertical-rl` -- and `self-start`/`self-end` are the same question
asked of the box's own mode. This engine reverses neither and does not
distinguish the `self-` pair from the plain one. The reason it is a
separate piece of work rather than a keyword table: the bare `anchor()`
form has its percentage resolved into the cascade's own map, before
either the containing block or the box is in hand, so the keyword has to
survive into layout before any of the three can be answered.

### An absolutely positioned box no longer turns with a vertical flow

`position: absolute; left: 60px; top: 50px; width: 40px; height: 30px`
inside a `vertical-rl` container came out **30x40**, where every browser
gives 40x30: `left`, `top`, `width` and `height` are physical, and a
writing mode does not move a physical thing. The wrong positions
followed from the wrong size -- `right: 20px` put a 30-wide box at 150
rather than 140.

**The cause is that such a box is laid out twice.** The in-flow pass
turns the subtree, and then `layoutPositioned` lays the out-of-flow box
out again, by which time everything around it is already physical. The
second layout treated it as an ordinary box *inside* a vertical flow --
logical, awaiting a turn that had already happened and would not come
again. So it starts a fresh vertical flow instead, and
`wmStartsVerticalFlow` says so for any out-of-flow box whatever its
parent is. One predicate; twelve of the thirteen failing checks came
back with it.

The checks need no number from either engine. `left`, `top`, `width`
and `height` being physical means the same declaration must give the
same rectangle in all three modes, and the fixture discriminates three
ways: every horizontal row agrees, so the instrument is not broken; the
in-flow row agrees in both vertical modes, so the turn itself is right;
and only the out-of-flow rows differed.

**Cost: nothing, and the binary says so before the benchmark does.**
The two binaries are the same size to the byte, because the predicate
sits behind `wmVert &&` and a page that never says `writing-mode` does
not call it at all. Paired on `generated.html`, two forward rounds give
a total of -1 and then +1, with 9 and 13 of 25 pairs slower.

**What is still wrong, and asserted so that fixing it says so.** The
static position -- where an un-inset out-of-flow box goes -- is recorded
by the flow in logical coordinates and nothing turns it. `horizontal-tb`
and `vertical-lr` put a first child at the origin, so they come out
right for a reason that does not reach `vertical-rl`, which should start
the box at the container's right edge and starts it at 0. Turning the
recorded point in `wmTransposeWalk` was tried and made it worse, because
the point is recorded before the box has any extent to turn it by. The
suite asserts the gap; todo.md says what the fix wants.

### Twelve logical shorthands that never asked the writing mode

`margin-inline`, `margin-block`, `padding-inline`, `padding-block`,
`inset-inline`, `inset-block`, `border-inline`, `border-block`,
`contain-intrinsic-inline-size`, `contain-intrinsic-block-size`,
`overscroll-behavior-inline` and `overscroll-behavior-block` now follow
the writing mode, and the six two-value ones follow `direction` as well.

**Found by a test that was aimed at something else.** The auto-margin
checks below came out with `margin-block` and `margin-inline` swapped,
and the cause was not the auto margin. `applyDecl` sends every logical
*longhand* through `wmPhysicalName` and then expands the two-value
shorthands further down with physical names written into the source.
Asking the source which names those are -- every one containing
`inline` or `block`, minus the ones `wmPhysicalName` answers -- gave
twelve; the two the test happened to name are the two a hand-written
list would have had.

**The `rtl` row is the part that is not about writing modes at all.**
Chromium answers `margin-inline: 11px 22px` on a right-to-left box with
`margin-right: 11px; margin-left: 22px`, and this engine answered
left 11, right 22. That has been wrong since the logical properties
landed, in a file whose own opening paragraph says the inline aliases
are the ones `direction` decides, and no check asked.

The fix is four side functions that answer in both modes -- the
existing `wmInlineStartSide` and its neighbours are vertical-only,
being called from nowhere else -- and the four renames added to
`wmPhysicalName`. Nothing calls the side functions unless one of the
six two-value shorthands is declared.

The check needs no numbers, because a shorthand and its own two
longhands are two ways of writing one thing: whatever
`margin-inline-start` and `margin-inline-end` compute to,
`margin-inline` must compute to the same, in every mode and either
direction. 87 checks failed on that before the fix.

**One of them failed for a reason worth keeping.**
`overscroll-behavior` is not a field of `Style`: it lives in a side map
keyed by the style's serial, and `cascadeReset` restarts the serials.
Two styles computed in two documents therefore cannot be compared
through it -- the second document's styles take the first's serials and
the map answers for whichever was written last -- and the engine was
right all along in the four cases that looked wrong. Those checks put
both elements in one document.

### The benchmark's control refused two runs, correctly

`tests/bench.sh` was run twice on an idle machine for the two changes
above and its control failed both times: Chromium rendered
`generated.html` in 20.4 and then 20.2 ms against the 26.0
benchmarks.md records, past the 15% a run is allowed. Asked directly,
six best-of-5 samples give 20.1 to 22.0 ms -- a spread of 1.9 around
21, so not a contended run -- and the browser is Chromium
141.0.7390.37, **the same build benchmarks.md already names**. The
machine changed, not the reference, so `CONTROL_MS` stays where it is
and no number from those runs is in the file. benchmarks.md records the
refusal instead.

**The paired comparison still works on such a machine**, because two
binaries run alternately in the same minutes cancel its speed, and it
says this pair of changes costs about **3 ms of 130** on
`generated.html`: +3 and +3 against the parent across two forward
rounds, +6 and +3 against a dead-code control built within 16 bytes of
the candidate, and +4 and +3 for the layout half alone with the cascade
half reverted -- three agreeing pairings. On `features.html` the same
binaries read +9 and +4 forward and +1 and -2 mirrored, which does not
add to zero and so says nothing.

**Which line costs it did not settle.** The layout half's only
executable additions on a page with no vertical box are a saved copy of
`cw` and one `!wmRoot` test; a binary without the save read -2 against
the candidate, one without the test -1, and one without the whole
auto-margin plumbing read -1 and then +5, which disagrees with itself.
So the cost is in the layout half and in none of its lines separately,
which is as far as five binaries got.

### An auto margin on an orthogonal flow

`margin: 0 auto` on a vertical box inside a horizontal one now centres
it in its parent's **width**, where it centred it in its parent's
height before.

Chromium's twelve rows are in todo.md, and what they say is that there
is no orthogonal-flow rule to implement: a logical margin maps through
the element's own writing mode, an auto margin resolves against the
containing block's inline axis, and the two composed give every row.
This engine resolved the auto margins inside the logical space the
subtree is laid out in, where that axis is the flow's *block* axis and
`cw` had been clamped to it, so `margin: 0 auto` landed at 30 -- which
is `(100 - 40) / 2`, the box centred in the outer block's height.

They are resolved after the turn now, against the containing block's
own inline size rather than the clamped one, which is also the only
point at which the box's physical side margins and its turned width are
both to hand.

### Flex, grid, table and multicol turn with the writing mode

A flex, grid, table or multi-column container in a vertical mode now
exchanges its axes, which is the last of CSS Writing Modes 4's layout
work. Chromium was asked for each of the four twice, once
`horizontal-tb` and once `vertical-rl`, and every vertical reading is
the horizontal one turned a quarter turn: a `row` flex container's
items stack down the page at the main size their `height` declares, a
grid's column tracks run down the page and its row tracks right to
left, a table's cells run down the inline axis and its rows across the
block one, and a multi-column container's column boxes stack along the
inline axis. **So none of the four algorithms is wrong.** Each is
already correct in logical space -- which is where everything below a
vertical flow's root is laid out, the transposition walk turning the
finished subtree once at the end. Only the lengths they read off a
style are physical.

Two things were therefore missing, and both are small. A flex, grid or
table container left `layoutBlock` by an early return of its own and so
was never turned at all; multicol, which goes down the ordinary block
path, already was, which is why it needed nothing but the exchange.
And `flexBaseSize`, `flexMinMainSize`, `flexHeightIndefinite`,
`layoutGrid`, `layoutTable`, `layoutTableWithWidths`, `tableColumns`,
`fixedTableColumnWidths` and `computeTableIntrinsic` each reached for
`width` where they meant the inline size. Each now takes the physical
axis beside the logical one, from a single local `bool` off the
container's own writing mode: a `row` flex container's main axis is
still the inline one whichever way the page is turned, but its length
is `height` when the page is turned. A page with no vertical box on it
reads one global per container and nothing else.

The checks ask the vertical layout of a logically-sized container to be
the horizontal one turned, rather than asking either for a number. That
form needs the fixtures to discriminate, and three did not until they
were changed: a grid whose items declare nothing never reads an item's
length at all, so two more fixtures give one its own inline size inside
a larger track and leave another's block size to be stretched; a flex
container whose items all declare both sizes never stretches or grows,
so three more cover a column container, a stretched item and two that
grow; and a fixture whose two vertical modes come out identical cannot
tell a block direction from its reverse, which is now asked of either
item rather than the first. The four grid and flex reads went from
passing to failing on the two new fixtures before the exchange was
written, which is the only reason to believe they were being measured.

**Cost: nothing measurable.** The exchange is one global read per
flex, grid or table container and one ternary per cell, and *both*
benchmark pages reach it -- `features.html` has 24 tables and two
grids, `generated.html` 40 tables -- so neither could serve as the page
the change cannot reach. Paired against the parent, two forward rounds
each: `features.html` gave a total of +4 ms median (mean +0.76, 14 of
25 pairs slower) and then +1 (mean -1.84, 13 of 25); `generated.html`
+3 (mean +5.44, 15 of 25) and then -4 (mean -0.72, 11 of 25). No two
rounds agree, the means change sign, and the parent's own median moved
from 155 to 160 ms between the first page's two rounds -- more than the
difference being claimed. Nothing there earns a question to the code,
and benchmarks.md is unchanged.

**The fixtures found two gaps in the horizontal engine**, which the
agreement form cannot see because both sides share them, and which are
written down in todo.md with Chromium's numbers beside this engine's: a
table row does not stretch to a definite table block size, and
`column-fill: auto` breaks to a new column before the current one is
full.

### An orthogonal flow clamps to the viewport

An orthogonal flow whose containing block has no definite block size now
takes the **viewport's height** as its inline size, which is what
Chromium does at every window height measured -- 200, 300, 400, 600, 900
and 1400 all give a box exactly that tall, its block extent falling as
the reciprocal.

**The reason recorded for not doing it was wrong**, and worth keeping as
a lesson rather than quietly deleting: it said nothing at layout time
knows the viewport's height. `cssViewportHeight` is a global in
`src/css/parser.f`, set by `setCssViewport`, read by the `vh`, `vmin`
and `vmax` units and by `layoutPositioned` -- which lives in the same
file as the clamp that was left unbounded for want of it. That is the
failure CLAUDE.md names, a sentence about this engine written from
memory rather than run, and it was written in the same stretch of work
that quoted the rule.

The check sets two different viewports and asks for the number back, so
a constant cannot satisfy it.

### `sideways-rl` and `sideways-lr`

The last two of CSS Writing Modes 4's four vertical modes, which
completes `writing-mode`'s value list.

**No box moves.** The block axis is the same in all four: two children
of 40 and 25 pixels land at the same offsets under `vertical-rl` and
`sideways-rl`, and under `vertical-lr` and `sideways-lr`, with or
without `text-orientation: sideways`. What differs is the glyph and the
direction the run advances -- two `L`s at 32px put the second below the
first in three of the modes and **above** it in `sideways-lr`, whose
inline axis runs bottom to top and whose glyphs are turned
counter-clockwise.

So `sideways-rl` is `vertical-rl` with the sideways orientation, which
this engine already draws the same way on Latin. `sideways-lr` is
`vertical-lr` with two changes rather than one: the transposition walk
measures its inline offsets back from the far end, and the glyph painter
turns the canvas the other way. Everything that walks a run in the
inline direction reverses with it -- the upright cells, the emphasis
marks -- and the decoration lines do not, being rectangles of the line
box; but the ascent side they name is the other one, so the underline
and the overline change places.

The render suite asks for the two things a unit test cannot see: which
glyph is painted higher, and which side of its own box the ink of a
turned `L` falls on. Neither is written down -- the two turns are asked
to be mirror images of each other.

### An emphasis mark and small caps on a vertical run

`text-emphasis` marks now run **down** a vertical line beside it rather
than across it, and `font-variant-caps` synthesises its small capitals
inside the turn rather than drawing the letters at full size in room
kept for smaller ones.

**Which side the marks go on was measured.** In a vertical mode the
`left`/`right` half of `text-emphasis-position` decides the side and the
`over`/`under` half is ignored -- the other way round from a horizontal
mode, where `over` and `under` decide. The two vertical modes agree.
This engine's computed style carries only the over/under half, so the
default is the right-hand side and `under` is the left, which is the
nearest thing it can say; todo.md records that divergence with
Chromium's table.

**The small caps were half working, which is the worse half.**
`measureWidth` already answered the shorter length, because the
measurement is the same measurement either way, so the box was the right
size and the painter drew the letters at full size inside it. The walk
is now one function taking a starting point rather than a fragment, so
the vertical painter asks for it at the origin of its own turned space
-- the same pair of functions the horizontal path uses, which is what
keeps the ink inside the room the measurer kept. The render suite asks
exactly that: the ink of an `all-small-caps` vertical run stays within
the extent the measurer gave it.

### A vertical run's decoration lines

`underline`, `overline` and `line-through` on a vertical run, in every
`text-decoration-style` the horizontal ones have, because
`paintBorderSide` already takes the axis as a flag.

**They are not the quarter turn the glyphs take**, which was the guess
and is what Chromium contradicts. A horizontal underline follows the
**baseline** -- 14 below the line box's top at 16px, 29 to 31 at 32px.
A vertical one follows the **line box**: the underline at its far block
edge, the overline at the near one, the line-through between them, at
both sizes and in both vertical modes. todo.md has the table.

Before this the three lines were drawn by the horizontal code from a
fragment whose `baseline` is an absolute *x* in a vertical run, so a
decorated vertical run got a horizontal rule across the page at a
coordinate that meant nothing. The render suite asks the rule rather
than the numbers: the underline on the far side of the line-through,
the overline on the other side of it, the outer two a line box apart
and the middle one between them, and the two vertical modes agreeing.

### `text-orientation: upright`

Each character stands up in a cell of its own along the inline axis
(CSS Writing Modes 4 §5.1). **281 → 282**, with `--fields` naming
`textOrientation`.

**What the cell is had to be measured, not guessed.** It does not follow
`line-height` -- three upright glyphs come to 57 at `normal`, at `1`, at
`2` and at `40px`, while the block extent moves 19, 16, 32 and 40 with
each -- and it is not the same for every family, 57 in monospace against
51 in sans-serif. It is the character's vertical advance, which is a
font metric, and Festina exposes the inked height of a string and
nothing else. So it is measured the way `FONT_CAP` was: Chromium, across
8 to 180px, in the family this engine renders in. Least squares gives
**1.116 x the size** with an intercept of -0.06, and rounding that
product lands on Chromium's own integer at 8 of the 13 sizes and within
a pixel at the other five. todo.md has the table.

The measurer counts cells rather than measuring glyphs, before the width
cache, which is keyed by the font and the string and knows nothing of an
orientation; the painter walks the run through the same cell, as the
synthesised small caps do, because a glyph drawn where the measurer
reserved no room leaves ink outside the box. A space takes a cell of its
own, and `sideways` agrees with `mixed` on Latin, as they do in
Chromium.

The render check asks the one thing that does not need this font's
metrics known: an upright `L` and a turned one are the same glyph, so
their ink is the same rectangle with its sides exchanged. Two pixels of
slack on a 32px glyph, for the reason the ink profile below needed
slack -- an upright glyph is hinted and a turned one is not.

### A vertical `writing-mode`

CSS Writing Modes 4's `vertical-rl` and `vertical-lr`, which css-2026.md
called "Nothing" and dismissed as "a second layout axis, not a
property". Chromium says otherwise and todo.md has the table: a vertical
block is the horizontal layout turned a quarter turn clockwise, with the
same inline lengths and the same line thicknesses, and only the
direction the lines stack differing between the two modes. **280 →
281**, with `--fields` naming `writingMode` as the field that moved.

**How it is done.** The box is laid out in a *logical* space whose x
axis is its inline axis, by the ordinary block algorithm: `resolveEdges`
rotates the box's own padding, border and margins once, `layoutBlock`
reads the length that names the inline axis -- `height` in a vertical
mode -- and one walk at the end turns every box, line and fragment
rectangle in the subtree into place. The painter turns the canvas about
a run's baseline and then draws the run exactly as a horizontal one, so
a rotated Latin glyph keeps its advance.

Everything that is not the layout of a block follows from the same
rotation and none of it is here yet: `text-orientation` computes and
inherits and does nothing, so it is deliberately not in the digest; a
vertical run gets no underline, emphasis mark or synthesised small caps;
and a flex, grid, table or multi-column container keeps the physical
axes. todo.md lists all six in the order they are worth doing.

**The logical properties follow the mode.** `inline-size` sets the
height and `block-size` the width, `margin-inline-start` is the top
margin and `margin-block-start` a side -- the right in `vertical-rl` --
while `width` and `height` stay physical. The horizontal table could not
be extended in place, because it renames the inline edges only; the
vertical one is asked first, and a page that never says `writing-mode`
tests one integer and calls nothing.

**An orthogonal flow shrinks to fit**, clamped to the containing block's
block size where that is definite, because the axis it would otherwise
fill is the containing block's *block* axis. Where that is indefinite
Chromium clamps to the viewport and this does not clamp at all, nothing
at layout time here knowing the viewport's height.

Both suites ask the horizontal and the vertical layout of the same
content to agree rather than writing this engine's metrics down: the
vertical container is as wide as the horizontal one is tall, and the
ink profile of a line set horizontally, column by column, is the ink
profile of the same line set vertically, row by row.
`tests/unit/test_writingmode.f`: 20 passed, 0 failed.
`tests/render/writingmode.f`: 8 passed, 0 failed.

### Who owns a positioned descendant's `z-index`, and `isolation`

CSS2 §9.9 confines a positioned descendant's `z-index` to a **stacking
context**. This engine confined it to any positioned box at all:
`collectPositionedPainted` descended only through `PSTEP_SPLIT`
children, so a `position: relative` box with `z-index: auto` was marked
`PSTEP_POSITIONED`, painted whole, and painted its own positioned
descendants inside itself.

A positioned box that is not a stacking context now hoists them into
the ancestor's list, in tree order after itself, which is what the
standard's "as if it created a stacking context, but its positioned
descendants are part of the parent's" comes to. The hit tester hoists
identically, or a click would land on a box the paint put underneath
another.

**`isolation` lands with it**, and could not have landed without it. Its
whole effect here is that `isolation: isolate` creates a stacking
context; with the old confinement every box behaved as one, so the
property could not have changed a pixel. **279 → 280.** `filter` and
`mask` are added to `boxIsStackingContext` in the same line: the
standard gives each one, both were given `boxPaintsWhole` when they
landed this session, and that gets a subtree into one layer, which is a
different question from who owns a `z-index`.

**What still confines, and why.** A replaced leaf, a `clip-path`, an
`offset-path`, a mask, `contain: paint`, `content-visibility: hidden`
and `overflow: hidden` keep their positioned descendants. For all but
the last that agrees with the standard. `overflow: hidden` is a
divergence: this engine clips by painting the subtree into a layer and
blitting it back, so hoisting a descendant out would take it out of its
clip. It is asserted in the suite rather than left to be discovered.

Two things the work turned on. The first attempt suppressed a hoisted
box from painting its own positioned descendants while collecting them
with the **mark-based** walk, which only sees marks set for the box
being walked — so they were suppressed and never collected, and the
fixture painted white. The structural collector, which the hit tester
already used, sees the real tree. And the suite that found the original
bug found it on its **first line**: the instrument check, the one
asserting the un-isolated case behaves as Chromium does, failed while
every other check in the file passed vacuously.

No render suite changed its answer. `tests/render/isolation.f`: 9
passed, 0 failed.

The benchmark cost a day and is written up in benchmarks.md: paired
against its parent the change showed every signal this project calls a
real cost, and the same reading appeared on `generated.html`, which
cannot execute a line of it. CLAUDE.md gains the cheaper control that
found this -- pair on a page the change cannot reach -- and the
instruction to sum the five phases, since the compiler moves
milliseconds between them.

### `mask-composite`, and a second mask layer

`mask-image` takes a comma-separated list, each layer with its own
`mask-mode`, `mask-repeat`, `mask-position`, `mask-size`, `mask-origin`
and `mask-composite`, combined bottom upwards. **272 → 279**, with
`mask-composite` the property that moved and `--fields` naming the mask
field.

The four operators are Porter-Duff on the alpha channel alone (§7.5),
and all four agree with Chromium to the pixel on two flat layers at 0.8
over 0.25:

| operator | painted | alpha | |
|---|---|---|---|
| `add` | `#2626ff` | 0.851 | `as + ad - as*ad` |
| `subtract` | `#6666ff` | 0.600 | `as * (1 - ad)` |
| `intersect` | `#ccccff` | 0.200 | `as * ad` |
| `exclude` | `#5959ff` | 0.651 | `as + ad - 2*as*ad` |

**The first probe could not tell `subtract` from `intersect`**, because
it put 0.5 below: `as*(1-ad)` and `as*ad` are the same number when `ad`
is a half, so both read `#9999ff` and a wrong implementation would have
passed. A quarter separates them, 0.6 against 0.2. That is the third
time this session the fix was to choose a probe that can fail, after
`mask-origin`'s clamp and the `<rect>` radii, and it is the same rule
this project already writes down about instruments applied to a
measurement.

The layer resolution moved out of the painter's globals into a
`MaskPrep` per layer, prepared once per masked box and read per pixel,
because one set of globals cannot describe two layers at once. The blit
is untouched and is now shared by every shape and layer count: only the
alpha differs.

`tests/render/mask.f`: 54 passed, 0 failed.

### A mask over a radial or conic gradient

todo.md recorded these as the next mask work and said the radius
resolution would have to be lifted out of `paintRadialGradient`. It does
not: `radialRadii` is already its own function writing `radRx` and
`radRy`, and `resolveGradientCenter` already gives the centre. That is
the fourth written-down obstacle this session to dissolve on reading the
code rather than the note, and the first where the note was **mine**,
written two hours earlier.

So each shape is one expression. A radial mask's parameter is the point
in the ending ellipse's own coordinates, `sqrt((dx/rx)^2 + (dy/ry)^2)`,
which is 1 on the ending shape whatever its two radii are; a conic
mask's is the angle clockwise from pointing up, less `conicFrom`, over
360 -- `conicFrom` being the convention the background painter already
uses. The blit is unchanged and is now shared by all three shapes,
because only the alpha function differs between them.

All fifteen pixels measured match Chromium 141 exactly: five columns
each of `radial-gradient(closest-side, ...)`, `radial-gradient(circle
20px at 50px 20px, ...)` and `conic-gradient(...)`. Six of them are
asserted as absolutes, and the check that earns its place is the 20px
circle -- it leaves the columns 25 pixels either side of the centre
fully transparent, so an implementation that resolved no radius and
covered the box fails on white against white rather than on two shades
of blue.

`@supports` now answers yes for a radial and conic mask and no only for
a bitmap. The count does not move: `mask-image`'s row is `url(a.png)`.

`tests/render/mask.f`: 44 passed, 0 failed.

### CSS Masking 1's `mask`, over a linear gradient

css-2026.md said only that `mask` and its longhands were untouched, with
no reason given. The reason that would have been given -- a mask is
per-pixel alpha and this engine cannot read a pixel -- is wrong the same
way the filter block was, and one measurement settles it: **`drawImage`
honours `fillAlpha`**. An opaque red image blitted over white at
`fillAlpha(1.0)` gives `#ff0000` and at `fillAlpha(0.5)` gives
`#ff7f7f`, exactly the half composite. The clip machinery already paints
a subtree into a layer and blits it back in pieces, so a mask is that
loop with an alpha per piece instead of a span per row. The alpha is
computed, not sampled: this engine builds the gradient's colours itself
and so knows every alpha in one.

The other half of the answer is that **`mask-*` is `background-*` with
the result used as alpha**, so `mask-repeat`, `mask-position`,
`mask-size`, `mask-origin` and `mask-clip` are read with the background
readers rather than a second copy of the same five questions. One
initial value differs and was measured rather than assumed:
`mask-origin` is the border box where `background-origin` is the padding
box. `mask-image`, `mask-mode` and the `mask` shorthand complete the
set; a masked element is a stacking context.

**The count moves from 272 to 278**, and every one of the six is a
property the painter reads and a pixel test exercises: `mask-clip`,
`mask-mode`, `mask-origin`, `mask-position`, `mask-repeat` and
`mask-size`. `mask-image`'s row is `url(a.png)`, which stays
unimplemented and stays failing.

That needed the computed style to be got right rather than the
instrument. The six longhands first registered as nothing, because a
spec was only built when a paintable image was there; they are stored
whenever any of the seven is declared, since `mask-clip` has a computed
value whether or not an image is beside it and the painter reads it the
moment one is. The mirror of that: `mask-image: url()` with nothing
beside it builds no spec at all, because the engine throws the image
away and a computed style that recorded it would be scoring on a value
nothing reads -- the `outline-style` trap. `@supports` answers no for a
bitmap, a radial gradient and a conic one, so it and the instrument
agree.

**The bug the tests caught.** `cutRegion` copies with `drawImage`, which
honours `fillAlpha` -- so cutting the next run while the previous run's
alpha was still set faded each run by the one before it, and a uniform
half-alpha mask came out at a quarter. The check that found it is the
agreement that needs no number: a mask whose alpha is uniformly a half
must paint what `opacity: 0.5` paints. Both now give (127, 127, 255),
and the gradient matches Chromium to the pixel at its first pixel
(1, 1, 255) and its midpoint (129, 129, 255).

What stays out, recorded rather than hidden: a `url()` bitmap mask needs
that image's own alpha per pixel, which is FINDINGS.md finding 35 again;
a radial or conic gradient mask needs a projection this engine does not
compute; `mask-composite` and a second mask layer are not implemented.
A declaration naming any of the three unpaintable images is dropped
whole, so the element renders unmasked rather than half-masked.

28 pixel checks in `tests/render/mask.f`.

### CSS Filter Effects 1's colour functions, and a block that was answering the wrong question

The specification was recorded here as blocked on the language, and half
of that was true: a filter is a pass over the pixels a subtree painted,
and a `color` read back off the canvas supports equality and nothing
else. Checked rather than recalled -- `c.r`, `c.red`, `c.toText()`,
`c.hex()`, `c.value` and `c.rgba()` each give *cannot access field ...
on color*.

The conclusion did not follow, and two facts sat either side of it for
months. This engine's own colours are packed ints with `colorRed`,
`colorGreen`, `colorBlue`, `colorAlpha` and `clampChannel` already
written; and `applyFillColor` is a single choke point. Only a colour
read *back* is opaque. Every colour filter is affine, compositing forms
convex combinations, and an affine map commutes with those, so filtering
each source colour as it is drawn gives exactly the pixels filtering the
raster would. Measured in Chromium on the case that equivalence is
usually doubted for -- a half-transparent colour under `invert(1)`
composited over an *unfiltered* backdrop -- where the prediction from
the source colours and the browser's pixel are the same three numbers.

`filter` now takes `grayscale()`, `sepia()`, `saturate()`,
`hue-rotate()`, `invert()`, `brightness()`, `contrast()` and
`opacity()`, each with a number or a percentage and `hue-rotate()` with
an angle. A list applies left to right, the filter reaches the element
and its descendants, and a filter inside a filter composes. A filtered
element paints whole, which it must anyway, being a stacking context.

**The count does not move, and is not meant to.** The `filter` row in
`tests/conformance/css-properties.txt` reads `blur(2px)`, which stays
unimplemented. Changing it to one of the eight would be choosing the
sample after seeing the answer -- the error the thirteen shorthand rows
were -- so it stays. What was checked instead is that the instrument
*could* see the property: the digest gains the filter list, and with the
row temporarily set to `grayscale(1)` the count reads 273 of 405 with
`--fields` naming `filter` itself as the field that moved. Reverted, it
reads 272 again.

**What stays out.** A bitmap image reaches the canvas through
`drawImage` and never through the fill, so an `<img>` or a background
image inside a filtered subtree is not filtered; that one is the
pixel-reading block proper. `blur()` is a convolution and
`drop-shadow()` wants a path API, so a declaration naming either is
dropped whole rather than partly applied, and `@supports` answers no.
`backdrop-filter` filters what is behind an element and is separate.

**The bug the tests caught.** Applying a component transfer by dividing
into 0..1 and multiplying back loses a unit, and truncation keeps it
lost: `255 * (1 - 55/255)` is 199.99999999999997. A single filter is
right and `invert(1)` inside `invert(1)` comes back one short of where
it started. The nesting check is written as an identity rather than
against a number, which is why it failed instead of agreeing with a
number that was also wrong; the transfer is now applied on the 0..255
scale, as Chromium's own lookup table effectively is.

132 checks: 114 in `tests/unit/test_filter.f`, every one a Chromium
answer rather than this engine's, and 18 pixels in
`tests/render/filter.f`.

### A `<rect>` on a motion path has its corners rounded

The one case the SVG-shape work left wrong rather than absent: a `<rect>`
carrying `rx` or `ry` was travelled as though its corners were sharp.

What settled the implementation was measuring, rather than reasoning
about, what Chromium travels. Its rounded rect agrees to the hundredth
of a pixel with the `path()` of SVG 1.1 §9.2's own equivalent arc data,
at 0%, 25%, 50% and 75%, and `motionPathData` has read `A` since the
curve commands landed. So the rounded rect is path data and the feature
is one string builder and a radius resolver -- no rounded-rectangle
primitive, which is the fifth time the useful question has been what
this engine already travels rather than what the feature seems to want.

The radii cost a second and a third probe, because the start point
cannot see all of them. It shows the horizontal clamp and not the
vertical one -- `(50, 0)` is where `rx=50` starts whatever `ry` is -- so
the per-axis clamp was measured a tenth of the way round instead, where
`rx=80 ry=40` follows `rx=50 ry=25` and parts from `rx=50 ry=40`. And
the three ways a radius can be missing turn out to be three answers: a
zero in either axis is sharp, a negative value is the other axis, and
the keyword `auto` is **zero**, where SVG 2 §10.2 defines it as the
other axis and Chromium treats the attribute being absent exactly that
way. The engine follows Chromium and the divergence is written down.

The render suite gains twenty-two checks. Nineteen were written before
the implementation and fifteen of them failed, every rx offset reading
zero; the four that passed compare a coordinate the rounding does not
move. Eight are the two spellings agreeing at each distance, three are
offsets taken from Chromium's numbers rather than this engine's --
rounding by `rx` moves the start point `rx` right, which agreement
between two identical paths would never catch -- and the rest are the
`auto` defaults and the per-axis clamp.

The last three came out of the edge measurements and so were written
after the code, which makes them the ones to justify. Two of them pass
on the engine as it was, because a sharp rect is what both a zero radius
and the `auto` keyword should give: they guard against a wrong
implementation rather than an absent one. That is a weaker thing to be,
so it was checked rather than assumed -- resolving the keyword `auto` to
the other axis, which is what the standard says and what the absent
attribute does here, fails `and the keyword auto is zero, not the other
axis` by twenty pixels.

`tests/render/motion.f`: 243 passed, 0 failed.

### `<rect>`, `<line>` and `<polyline>` as motion paths, and a wrong reason of my own

The commit before last left these three out, on two reasons: that a
`<rect>` wants a rectangle path this engine does not travel, and that a
`<line>` and a `<polyline>` want an open-polyline flag it does not have.
**Both were wrong.** `motionPolygon` travels a `CLIPSHAPE_POLYGON` and
`motionPathData` travels a path string, and all three shapes are one or
the other: a rect is the polygon of its four corners clockwise from
(x, y), and the other two are `M ... L ...`, which is open. No new
machinery, and the fix is in the same function that already read the
other four.

The reasoning that went wrong is worth naming. The reason named the
capability the feature seemed to want rather than asking what the engine
already had that would serve -- which is precisely the mistake this
branch spent the day catching in css-2026.md, four times over, and it
was written by the hand that had just finished correcting two of them.

Eight more checks in `tests/render/motion.f`, each the SVG spelling
against its CSS twin, and one that earns the open/closed distinction: a
two-point `<polyline>` must **not** agree with a `polygon()` of the same
two points, because a polygon closes itself and doubles the distance.
All eight failed first, and the engine now answers Chromium's columns to
the pixel for all six geometry elements.

A `<rect>` carrying `rx` or `ry` is travelled with sharp corners, where
Chromium rounds them. That one is wrong rather than absent, and is
recorded.

### A `url()` motion path takes an SVG shape as well as a `<path>`

Chromium resolves five geometry elements besides `<path>`, and three are
shapes this engine's motion code already travels. Measured at
`offset-distance: 50%` on the same geometry: a `<circle>` lands where
`circle()` lands, an `<ellipse>` where `ellipse()` does, and a
`<polygon>` where `polygon()` does. So the cascade reads the element's
attributes into the `ClipShape` it already builds for those three
functions and hands it over as `MPATH_SHAPE`; nothing downstream
changed, exactly as with the `<path>` case.

The numbers in an SVG attribute are scanned rather than split, because
`points` separates them by commas, by spaces or by both, and
`0,60 100,60` has to read the same as `0 60 100 60`.

Eight checks in `tests/render/motion.f`, each the SVG spelling against
the CSS function of the same geometry, so no coordinate is written down
and a shape resolved to the wrong centre, radius or winding fails at
once. One of them is the instrument: a circle at 50% must differ from
the same circle at 0%. All eight failed before the change, and on an
independent fixture the engine now answers Chromium's own columns to the
pixel -- (5, 45), (5, 45) and (95, 26).

`<rect>`, `<line>` and `<polyline>` follow in the commit after this
one, which also records that the reason given here for leaving them out
was wrong.

### Thirteen shorthand rows come out of the property instrument

The instrument's header says shorthands and legacy aliases do not belong
in a per-longhand instrument. Thirteen shorthands were in it anyway --
`place-content`, `place-items`, `place-self`, `white-space`,
`text-wrap`, `border-radius`, `flex`, `flex-flow`, `gap`, `outline`,
`overscroll-behavior`, `text-box` and `column-rule` -- added earlier on
this branch to give the shorthand-expansion work an instrument. That was
a real need and this was the wrong instrument for it.

All thirteen registered, so they added thirteen to the numerator and
thirteen to the denominator. Against an engine passing about two rows in
three, thirteen certainties on both sides lifted the ratio from **67.2%
to 68.2%** -- and every one was a shorthand that had just been
implemented, which is choosing the sample after seeing the answer.

The count is **272 of 405**, where it reported 285 of 418.
`PROPERTIES_MIN` goes back to 272. No coverage is lost: a shorthand's
effect is its longhands', all of which are graded already, so the
thirteen counted the same implementations twice; and the bug they were
added to catch is instrumented in the ninety-three checks
`tests/unit/test_cascade_rules.f` gained for it.

It was found by asking whether the denominator was too *small* --
whether the ratio was flatter than the truth. Chromium's computed style
enumerates 406 names and every one is already in the file, so the answer
was no. The audit that followed, of every property `supportedProperties`
claims and the instrument does not grade, found 41; reading why they
were absent found the policy; the policy found the thirteen.

### `offset-path: url()`

CSS Motion Path 1 §2.1. css-2026.md recorded "no `url()` path", which
reads as needing SVG this engine does not render. **The path does not
have to be drawn, only read.** Three pieces were already here: the HTML
parser puts SVG elements in the DOM with their attributes
(`insertForeignElement`), `motionReadPath` already stores path data as a
string on `MotionInfo` with `MPATH_PATH` and everything downstream reads
only those two fields, and `documentRootOf` already walks from a node to
its document root. So `url(#p)` is: find the element, read `d`, set the
two fields the `path()` form sets. Nothing in `src/css/motion.f`
changed.

The fourth stated reason this session to fall over on inspection, after
`inset()`'s `round` radius, `polygon()`'s fill rule and
`scroll-snap-stop`. Each time the reason named a capability the engine
lacks, and the feature needed something narrower it already had.

**A reference that resolves to nothing is not `none`.** The standard
says it "behaves as `none`"; Chromium disagrees, and so does this engine
now. `none` leaves the box where the flow put it; a missing element, an
element that is not a `<path>`, and a `<path>` with no `d` all give an
*empty* path, and the offset machinery still runs -- the box is centred
on the path's single point at the origin, eleven pixels and one concept
away from where the wording would have put it. Measured on all three
forms.

Eleven checks in `tests/render/motion.f`, every one an agreement between
two spellings of one path rather than a coordinate written down: `url(#p)`
must land where `path()` with the same data lands, at the start of the
path and half way along it; the three ways of resolving to nothing must
agree with each other; and a reference that resolves to nothing must
*not* agree with no `offset-path` at all. One of the eleven is the
instrument -- a path at 50% must differ from the same path at 0%, or
every agreement holds between two boxes that never moved. Five failed
before the fix.

Against the fixture the measurement used, the engine now reproduces
Chromium's geometry exactly: the box at the container origin for `none`,
at half the path's length minus half its own width for both spellings of
the path, and at minus half its own width on both axes for all three
dangling forms.

Not taken, and recorded rather than left to be rediscovered: a `url()`
naming an SVG shape that is not a `<path>`. Chromium resolves a
`<circle>`, which means turning a circle, rect or polygon into a path --
a second feature wearing the same syntax.

### `scroll-snap-stop`

CSS Scroll Snap 1 §5. css-2026.md said the property "needs a notion of
one scroll gesture rather than one scroll position". For a browser with
fling and momentum that is a real difficulty -- a gesture there spans
many frames. **This engine has no momentum.** One wheel event is the
whole scroll, and `snapPosition` was already being called with the old
position and the requested one both in the caller's hand. The gesture
was there; it was not passed in. That is the third recorded reason in a
row to fall over on inspection, after `inset()`'s `round` radius and
`polygon()`'s fill rule.

The rule, from Chromium 141 on five 100px children in a 100px snapport:
a scroll stops at the first snap position carrying
`scroll-snap-stop: always` **strictly** between where the gesture began
and where it asked to go. Strictly, because a gesture starting on that
position is not held by it. A gesture that lands on it anyway is
unchanged, and one that never reaches it is unchanged.

The part that had to be measured rather than reasoned: **it acts under
`mandatory` only.** A `proximity` container ignores the declaration
completely -- not merely where proximity declines to snap, but also
where it does snap and the position lies in the path. A gesture of 310
from 0 rests at 300 with the rule and without it, passing an `always`
child at 100. The specification's words do not say that, and reading
them would have produced the opposite.

Twelve checks in `tests/unit/test_snap.f`, written against the control
rather than against Chromium's columns: what is asserted is that a
stopped gesture comes to rest exactly where a gesture that only asked to
go that far comes to rest, which is what "stops at that position" means.
Three of the twelve are the instrument -- without the rule a longer
gesture must travel further, and `mandatory` must differ where
`proximity` does not, or the proximity checks would pass on an engine
that had never read the property at all. Three failed before the fix.

The property instrument moved 284 to 285. It would not have: the row
existed and carried a real value, but `styleDigest` compares a list of
fields by name and `snapStopAlways` was not on it -- the same trap
`object-fit` and `object-position` fell into, checked here end to end
before the number was believed. `--fields` names `scroll-snap-stop ->
snapStopAlways`, so the field that moved is the one that means the
property. `scroll-snap-stop` also joins `supportedProperties`, so
`@supports` agrees with the instrument.

### `inset()`'s `round` radius

CSS Masking 1 §4.1. `readInsetShape` broke out of its loop at the
`round` keyword and never parsed what followed, so the radii were not
dropped late -- they were never read. css-2026.md gave the reason as a
rounded corner needing a path API the canvas does not have. That reason
was wrong, and the commit before this one records it: `clip-path` is not
drawn through a path here at all. The subtree goes into an image and
comes back **one scanline at a time**, each carrying the span the shape
covers at that row, and the arithmetic for how far a rounded corner
narrows that span was already in the repository as `cornerInset`, which
the box-shadow code asks for exactly this.

So `cornerInset` and `radiusShrink` move out of the painter into
`src/css/shapes.f`, where both callers can reach them -- the CSS cannot
call the painter, and the painter imports layout, which imports the CSS.
Neither is duplicated.

The radii are parsed with `border-radius`'s own grammar and graded by
`radiusSlot`, the one-to-four helper that property already uses, rather
than a second copy of that rule. They are stored in a per-document list
with one `int` index on `ClipShape`, because `ClipShape` is a by-value
field of `Style` and benchmarks.md records that thirty-two bytes of
growth there cost two milliseconds of layout. `inset(10px round 0)`
leaves the index at zero, so an all-zero radius costs a page exactly
what a square corner costs.

`paintShaped` blitted every `CLIPSHAPE_RECT` whole and never reached its
scanline loop, which is right for a square inset and wrong for a rounded
one; it now asks whether the corners are square rather than whether the
shape is a rectangle. A square `inset()` is still one blit.

Ten checks in `tests/render/clip.f`, every one an agreement between two
ways of reaching the same region rather than a column written down here,
because this engine does not antialias and Chromium does:
`inset(10px round 0)` must equal `inset(10px)`, and `inset(0 round 50%)`
must equal `circle(50%)` and `ellipse(50% 50%)` -- half the box on both
axes is an ellipse, which this engine reaches down a different branch
entirely. Chromium agrees with both, checked before they were written
down. Four failed before the fix and none after. On the independent
fixture the measurement used, the engine puts the arc's first red column
at 36 where Chromium's antialiased band runs 34 to 37.

### `polygon()`'s fill rule

CSS Masking 1 §4.2. `readPolygonShape`'s own comment said the rule was
"read and dropped: `nonzero` and `evenodd` describe the same region
unless the polygon crosses itself". The second half is true; the first
half was a bug, because a polygon that crosses itself is exactly what a
star is, and `shapeSpanAt` filled between sorted crossing pairs -- which
is even-odd, where CSS's initial value is `nonzero`. So every
self-intersecting `polygon()` was drawn with the wrong rule, and the two
keywords drew the same thing.

A five-pointed star of outer radius 80, its points joined in {5/2} order
so the middle pentagon is enclosed twice. Chromium 141 fills that middle
under `polygon(...)` and `polygon(nonzero, ...)` and leaves it empty
under `polygon(evenodd, ...)`; this engine left it empty under all
three. A point out on an arm is enclosed once and is filled by both
rules, which is the control: a `polygon()` that had failed to parse
would lose that pixel too, and every check would otherwise pass on a box
that painted nothing.

The crossing list now carries the direction each edge was travelling in.
Even-odd still fills between the pairs; `nonzero` fills wherever the
running sum of the directions crossed so far is not zero, joining
neighbouring inside spans so a star is one span a row rather than three.
Both rules push their spans through one `shapePushSpan`, so a pixel on
the boundary is rounded the same way whichever rule asked -- which is
what makes "the two rules agree on an arm" a real check rather than two
roundings that happen to match.

Nine checks in `tests/render/clip.f`. Three of them are the instrument
rather than the feature: the two rules must disagree somewhere, the star
must be painted at all, and the box outside it must not be. Three assert
the default and `nonzero` land on the same pixel rather than each
matching a colour written down here. Three failed before the fix and
none after.

css-2026.md's Masking row did not mention the fill rule at all, which is
why nothing noticed: it listed `polygon()` among the shapes that work.

### `position: sticky`

CSS Positioned Layout 3 §3.5. The cascade parsed the keyword and threw
it away -- it set `POS_RELATIVE` -- and `POS_STICKY` existed only as a
constant. todo.md gave the reason as layout not knowing the scroll
offset, which is true and cannot be fixed: layout runs once per
document and the offset changes on every wheel event. **The painter
knows.** `paintPage` already sets `paintScrollY` and `paintViewHeight`
for `background-attachment: fixed` to undo, so the shift goes there,
which is also where a real engine puts it.

Fifty documents to Chromium 141 first, on three fixtures, reading the
box's rectangle and the scroll offset back together so the answer is in
document coordinates. The rule they agree on, in order: a `top` inset
can only push the box down, to `scroll + top`; a `bottom` inset can only
pull it up, to `scroll + viewport - bottom`; and the total is clamped
into the two distances the box can travel before leaving its containing
block. The clamp is against that block's **content** box, which a
fixture carrying 30px of padding and 30px of border separates from its
padding box and its border box -- 290 against 300 and 350, and the test
was watched failing on both of the other two.

An inset-less sticky box never moves, which falls out of the rule rather
than needing a case of its own.

`paintSticky` translates the canvas, moves the cull window with it --
otherwise a box stuck at the top of the screen is culled for being far
above where it was laid out -- and re-enters `paintBox` for the same
box, so a sticky box that also carries a transform or an offset path
gets both without either being written out twice. `hitChild` subtracts
the same offset from the pointer before testing this box or anything
under it, so a stuck box is clickable where it is drawn. Both are
behind `anySticky`: a document that never says the word pays one
boolean per box painted and one per box tested.

Nineteen pixel checks in `tests/render/sticky.f`, none of which writes
down a screen row: what each asserts is how far the box moved between
two scroll positions, because "it did not move" and "it moved exactly
as far as the page scrolled" are what sticking and not sticking mean,
while a row worked out here would only test the arithmetic that
produced it. Fourteen more in `tests/unit/test_position.f` put the
three Chromium fixtures back to this engine in document coordinates,
which a pixel check cannot do at scroll positions that carry the box
off the screen.

What is not reached is written down rather than claimed: a sticky box
inside an `overflow: scroll` container sticks to the document's
scrollport and not to that container's, and `left` and `right` do
nothing, because there is no `paintScrollX` -- the document does not
scroll across.

### The intrinsic sizing keywords, and an expectation the engine was right about

CSS Box Sizing 3's `min-content`, `max-content` and `fit-content` as
values of `width`. css-2026.md recorded them as missing and they were:
`parseLength` did not know the three keywords at all, so
`width: min-content` was an invalid declaration and dropped. The grid
track sizer knew all three, but that is a separate parser for a
separate grammar.

They are a `Len` kind of their own now, `LEN_INTRINSIC`, carrying which
keyword in its value. `resolveLen` answers `dflt` for it, exactly as it
does for `auto`, because that function is given a containing block and
the answer is a property of the box's own content; layout asks the box.
The arithmetic was already here -- `computeIntrinsic` fills a box's
`minContent` and `maxContent` for shrink-to-fit and table columns, and
**shrink-to-fit is `fit-content` under an older name** -- so the width
code shares it rather than growing a second copy.

Seven checks in `tests/unit/test_layout.f`, each against another way of
asking for the same number rather than against a remembered one: a
float of the same content is the yardstick for `max-content` and
`fit-content` while the content fits, and a float holding only the
longest word is the yardstick for `min-content`. Two more assert the
three are not the same number, which is what stops those agreements
passing on an engine that ignores the keywords and leaves every box at
its container's width.

**One expectation was written from intuition and the engine was
right.** The last check said `fit-content` against a container narrower
than the content is clamped to the container, 60px. The engine
answered 70 and Chromium answered 67.4 -- its own `min-content` --
because `fit-content` is
`min(max-content, max(min-content, available))` and is clamped only
from above. Which is the rule this repository keeps learning in other
forms: the number in a test has to come from a measurement, and an
expectation that disagrees with the engine is a question rather than a
verdict.

The height axis is deliberately not claimed. All three keywords give
the same answer as `auto` on a one-line box in Chromium, so a fixture
that can tell them apart is needed before there is anything to test.

### Blockification, and the anonymous block it turned out to depend on

CSS Display 3 sec. 2.7: a float, an absolute or fixed position, being a
flex or grid item, and being the root element each replace an
inline-level `display` with the block-level value it corresponds to.
css-2026.md recorded this as missing and it was -- the box tree
converted a flex item's *box kind* and nothing anywhere touched the
computed value, so `display: inline; float: left` stayed `inline` where
Chromium reports `block`.

It is not "set everything to `block`": `inline-flex` becomes `flex`,
`inline-grid` becomes `grid`, `inline-table` becomes `table`, and
`none` and `contents` are left alone because neither names a box to
convert. Fourteen checks in `tests/unit/test_display.f`, each against
Chromium 141's computed value, including the three that must *not*
change -- `none`, `contents`, and `position: relative` -- so the test
cannot pass by blockifying indiscriminately.

**And it broke a float, which is the half worth recording.** A floated
`<span>` used to keep `display: inline`, so `wrapInlineRuns` counted it
as inline content and left the paragraph alone. Blockified, it became
block-level, and a paragraph with a float in it started generating the
anonymous blocks of CSS2 sec. 9.2.1.1 -- which took the paragraph's
lines away entirely. The float suite caught it on the first full run.

The fix is the standard's own wording: anonymous blocks are generated
around inline content when an **in-flow** block-level sibling is
present, and a float is not in flow. A float is exempt from that
counting now. An absolutely positioned box is *not*, though it is also
out of flow, because this engine finds its static position by leaving
it where it was written and Chromium puts that position on the line
after inline content -- which the position suite pins, and which an
intermediate version of this change broke before the suite said so.

Two functions were written during this change that already existed
under other names, and both were caught by the compiler rather than by
looking: the second, `boxIsFloated`, already did exactly the job and
already excluded a positioned box from being treated as a float. The
same failure as the audit list two commits ago, one level down.

### The at-rules this parser steps over, and a check that could not fail

The same derive-from-the-source treatment, applied to at-rules. The
parser recognises exactly seven -- `@media`, `@supports`, `@layer`,
`@page`, `@counter-style`, `@container` and `@namespace` -- and every
one of them already has a suite. The note in todo.md that said
otherwise named six, two of which (`@font-face` and `@property`) this
engine does not implement at all; it had been written from memory one
section after the rule against exactly that, and is corrected.

The gap is the other half of the dispatch. `@font-face`, `@keyframes`,
`@import` and anything unrecognised are **stepped over**, and stepping
over them is a brace-counting problem nothing was asking about:
`@keyframes` holds blocks of its own, so a skip that stopped at the
first `}` would leave the rest of its body behind as rules. Nine checks
now ask it, each against Chromium's answer to the same stylesheet, and
the engine gets all nine right.

**The first version of those checks passed against a `skipBlock`
deliberately broken to stop at the first `}`.** Two things made them
vacuous: a leaked rule written *before* the real one loses to it on
source order anyway, and a leaked keyframe selector like `100%` matches
nothing whatever, so the page came out the same either way. The checks
now put the leak last in the sheet and give it a selector that matches,
and the broken parser fails two of them. The only reason this was
caught is that the rule about disabling the code and watching the count
move was carried out rather than assumed -- which is the rule's whole
point, and it has now caught a check of mine as well as a fixture.

### Eight units nothing was checking, and three constants for one length

The rule this file's previous entry earned -- derive the list from the
code, then audit it -- applied to CLAUDE.md's other standing complaint,
that a claim about a function, a unit or an at-rule has no instrument
behind it. Of the 35 units the length parser knows, **eight appeared in
no suite at all**: `cm`, `pc`, `grad`, `dpcm`, `dvh`, `lvh`, `vmin` and
`vmax`. css-2026.md claimed all eight and nothing could have caught any
of them going wrong.

Seven were right. They have checks now, written as agreements rather
than against remembered numbers, which is what makes them able to catch
the case nobody thought of: `vmin` against whichever axis is shorter
*and then the viewport turned the other way round*, so a constant could
not pass; `dvh`, `lvh` and `svh` against `vh`, which is the claim that
this viewport has nothing that slides away to tell them apart;
`100grad` against `90deg` and `400grad` against `1turn`; `1dpcm`
against `2.54dpi` and `37.795dpcm` against `1dppx`. The resolution
checks were verified the way this file asks -- by disabling `dpcm` in
the parser and watching all three fail -- because two of them had been
written as a pair of falses, which would have passed whatever the
engine did.

**The eighth was wrong, and it was the agreement that showed it.**
`cm` carried the constant 37.8 and `mm` carried 3.78, while `q` -- a
quarter of a millimetre, added later -- carried 96/2.54/40 exactly. CSS
defines all three off the same inch, so `1000cm` came out 37800 where
`40000q`, which is the same length by definition, came out 37795;
Chromium says 37795.3. Both now derive from the inch. The hazard is the
one the comment four lines below them in the same function already
names about `FONT_EX` and `FONT_CH`: two constants for one quantity is
how a number goes stale in one place and not the other. Here there were
three.

`env()` was checked too and needs nothing: it appears in the source
only in the list of functions `@supports` refuses to evaluate, which is
the honest answer for a function this engine does not implement.

### Every shorthand the engine reads is expanded, not read beside its longhands

`text-decoration`, `white-space` and `text-wrap` were each found the
same way and each fixed on its own, which is three times the same
lesson without once asking how many more there were. Put to the whole
engine -- which shorthands are read from the declaration map in
`computeStyleValues` rather than expanded into their longhands in
`applyDecl`? -- the answer was eight more, and **every one of them got
the cascade wrong**.

`border-radius`, `outline`, `flex`, `flex-flow`, `gap`, `font-variant`,
`text-box` and `overscroll-behavior`. Which direction each got wrong
depended only on where its reader happened to sit: `flex-flow` is read
after its longhands and so always won, the other seven are read before
theirs and so always lost. `outline-color: red; outline: 2px solid
blue` was red where Chromium gives blue; `flex-flow: row wrap;
flex-direction: column` was row where Chromium gives column.

Two of them carried a comment asserting the fixed order was the
cascade's doing. `flex-flow`'s said "a longhand after it still wins
because the cascade has already ordered them" and `text-box`'s said the
shorthand is read first "so a longhand beside it wins, which is what
the cascade already does for every other pair". Neither is true of a
map holding two keys: the reader's order decides and the cascade never
sees the question. Both comments are gone with the code they described.

The same audit turned up `overscroll-behavior-inline` and
`overscroll-behavior-block`, the axis longhands under other names, read
before the physical pair rather than renamed onto it -- the same fault
between two spellings of one property. They are renamed in `applyDecl`
now, beside the logical borders and margins.

All eight expansions sit behind one shared per-document flag, because
the user-agent stylesheet says none of the eight; a page that uses none
pays one boolean instead of eight name comparisons on each of its
matched declarations.

**Seven of the eight had no row in the property instrument at all**,
which is why none of this had been caught by a count that exists to
catch exactly this. `border-radius`, `flex`, `flex-flow`, `gap`,
`outline`, `overscroll-behavior` and `text-box` are graded now, each
moving the fields that mean it, and the count goes from 276 of 410 to
**283 of 417**. Twenty-two checks in
`tests/unit/test_cascade_rules.f`, every expectation Chromium 141's,
each asked in both orders because whichever fixed order a reader picks,
one of the two is wrong.

**And the audit's own list was wrong.** It was written out by hand, and
asking the source instead -- which property names are read with a
`...Prop(props, ...)` helper, and which of those is a prefix of another
-- turned up two more. `column-rule` is a width, a style and a colour
in any order, the same shape as `border` and `outline` which were
already expanded, read before all three of its longhands and with no
instrument row either. `contain-intrinsic-size` is the two axes read
before its longhands, and `contain-intrinsic-inline-size` and
`-block-size` are those axes under other names read after the physical
pair: three fixed orders in one block of four lines. Both expanded, the
logical pair renamed, fourteen more checks, `column-rule` graded, and
the count at **284 of 418**. A list of things to check written from
memory has holes in the same places the memory does.

`font-variant`'s row is left as it is. Its value is `none`, which is
the `none` of `font-variant-ligatures`; this engine has only the caps
half, so the row can never register here however complete that half is,
while `properties-audit` passes it because it asks Chromium whether a
row can move and Chromium's ligatures do. Changing the value to
`small-caps` would grade the half that works and call the property
done. What it exposes is a limit of one bit per property, recorded in
todo.md rather than papered over.

### `white-space` and `text-wrap` are shorthands, and `text-wrap` sets the mode

The sweep method applied to css-2026.md's CSS Text 3 row, which was the
last row with many sentences and no instrument behind it: thirty-five
documents to Chromium 141, one claim each. Twenty-seven agreed, two
differ for reasons that are not bugs, and six are three faults.

**Both shorthands are expanded into their longhands.** `white-space` is
a shorthand for `white-space-collapse` and `text-wrap-mode`; `text-wrap`
is a shorthand for `text-wrap-mode` and `text-wrap-style`. Both were
read beside their longhands with the shorthand read first, so the
longhand won whatever the stylesheet said and
`white-space-collapse: preserve; white-space: normal` gave preserve
where Chromium gives collapse. They now occupy the same keys their
longhands do, and the cascade decides.

**`text-wrap`'s mode half had no reader at all.** The style keyword was
taken out of the shorthand and nothing took the mode keyword, so
`text-wrap: nowrap` did nothing whatever. That is also what made the
two shorthands' shared longhand unreachable: `white-space` always won
`text-wrap-mode` because `text-wrap` never wrote it, whichever order
they were written in.

**A shorthand resets the longhand it does not name.**
`text-wrap-style: balance; text-wrap: wrap` is `auto` in Chromium and
was `balance` here, and `text-wrap-mode: nowrap; text-wrap: balance` is
`wrap` there and was `nowrap` here.

Two rows differ and neither is a bug.
`white-space-collapse: preserve-spaces` computes to `collapse` in
Chromium, which has not shipped the value; this engine honours it, and
CSS Text 4 defines it. And `break-spaces` keeps its own computed value
in Chromium where this engine folds it onto `preserve`, which is the
approximation the css-2026.md row already names: neither engine breaks
inside a run of preserved spaces, so the two render alike.

Twenty-five checks in `tests/unit/test_text.f`, each pairing the
shorthand against the longhands it must agree with. `white-space` and
`text-wrap` gained a row in the property instrument, which had graded
neither, and the count moved from 274 of 408 to **276 of 410**.

### A shorthand and its longhand compete, for text decoration and for alignment

Two bugs the widened style digest left behind, both of the same shape:
a shorthand that does not occupy the keys its longhands do.

**`text-decoration` now expands into its four longhands.** It had been a
fifth key of its own, and the reader applied the shorthand first and the
longhands after it, so a longhand won whatever the stylesheet said:
`text-decoration-line: underline; text-decoration: overline` gave
underline where Chromium gives overline. `applyDecl` now writes
`text-decoration-line`, `-style`, `-color` and `-thickness`, and deletes
the ones the shorthand does not name -- Chromium answers
`text-decoration-color: red; text-decoration: underline` with the text's
own colour, so the reset is half the behaviour rather than a detail. A
length in the shorthand is a thickness, told from a colour by its first
character, because `parseLength` answers `auto` for everything it cannot
read and would have made every colour keyword a thickness.

**`place-items`, `place-content` and `place-self` are implemented.** All
six longhands were already read and none of the three shorthands that
set them. Each is expanded the same way: the first value is the block
axis and the second the inline one, and one value sets both. A value
neither axis knows drops the whole declaration -- Chromium leaves
`align-items` alone for `place-items: end nonsense`, where a reader that
took the first token and stopped would not. The three comparisons sit
behind a per-document flag set while a stylesheet is read, so a page
that never says `place-` pays a boolean; the user-agent sheet says none
of them, which is what makes the flag worth having.

The `place-*` expansion shipped a use-after-free that the ordinary run
could not see: binding an `ascii` local to an element of the token
array aliases it, and the array is released before the locals are, so
the release wrote into freed memory. Every check passed and valgrind
found it -- the second time finding 2 has been paid for here. The
tokens are `dup`ed now.

Twenty-six checks in `tests/unit/test_cascade_rules.f` carry the two,
each pairing the shorthand against the two longhands that must agree
with it rather than against a remembered number. The property
instrument gained a row for each of the three, and the count moved from
271 of 405 to **274 of 408**; `--fields` says each moved the two fields
that mean it. `css-2026.md`'s selector row had been left at 61 of 61
after the instrument reached 129; it now says what the instrument says.

### A sub-layer is inside its parent, and a shorthand carries a keyword

Two bugs from one sweep: thirty claims in css-2026.md's CSS Cascade 4
and 5 rows put to Chromium one document each, of which twenty-six
already agreed.

**`a.b` is inside `a`, not beside it.** This engine gave every layer the
next number as it was first named, so `a` and `a.b` sorted as siblings
in declaration order. CSS Cascade 5 nests them: `a.b` takes `a`'s place
in the outer order, and within `a` the sub-layers come first and `a`'s
own rules last -- the implicit outer layer rule applied one level down.
So `@layer a { @layer b { div { lime } } div { red } }` is red, and the
engine gave every arrangement of that fact the other way round. The
other half is the same thing seen from outside: `a.z` loses to a
top-level `b` declared after `a`, where a flat reading gave `a.z` the
place it was named at and let it win.

A rule is still stamped with the layer's declaration index; a second
pass turns that into the rank the weight is built from, by sorting the
layers on their paths of declaration indices with the deeper of two
prefixes first. It runs once before a cascade pass rather than as each
layer is declared, because a layer's place depends on layers that may
not have been named yet, and it returns on its first line for a page
with no `@layer` on it.

**A CSS-wide keyword on a shorthand sets every one of its longhands.**
`font: revert` on a `<b>` gave 400 where `font-weight: revert` gave 700.
Fixing `font` alone would have fixed one of five: an audit of twenty
shorthands -- three documents each, so that the rollback must land on
what the lower layer left and must *not* land on what the shorthand
itself said -- found `font`, `background`, `border`, `border-top` and
`list-style` all failing, and `margin`, `padding`, `border-width`,
`margin-block` and `padding-inline` passing.

The ones that passed did so for a reason rather than by care: a
four-sides shorthand hands its value to each side unparsed, so the
keyword arrives whether anyone meant it to or not. The five that failed
parse their value into parts and read the keyword as a font family, a
colour or a list marker, setting the rest to their defaults -- which is
why `font: revert` came out as `normal`.

**Nine of the twenty could not be graded and the audit says so** rather
than passing them: `describeStyle` does not carry `column-count`,
`flex-grow`, `row-gap`, `overflow-x`, `text-decoration-line`, the grid
placement edges, `align-items`, `scroll-margin-top` or `top`, so two of
the three documents compute the same digest and the check has nothing to
tell apart. todo.md records that widening the digest is what would let
them be asked.

Seven checks of the nesting and eleven pairs of the keyword, each with
the third document that makes it able to fail; disabling the keyword
guard was tried and six fail.

**The keyword guard cost four milliseconds before it cost nothing**, and
the benchmark corrected the first guess at why. Passing each shorthand's
longhand names as an array literal builds that array on every call, so
every `font`, `background`, `border` and `list-style` declaration on a
page paid an allocation for a keyword it did not use: +4 and +3 of
cascade across two forward rounds, against -3 and -2 reversed. The
obvious suspect was the layer-rank lookup added to the loop over matched
declarations -- the shape the previous entry blames for two milliseconds
-- and moving it out changed the reading not at all. Writing the names
out, so nothing is allocated unless the keyword is there, took it to
zero both ways. It is the first reading in benchmarks.md to survive its
own second round.

### The rest of HTML's validity list that markup can express

`:valid` and `:invalid` read a missing required value and a value
outside a declared range. Four of HTML's conditions come out of markup,
and the other two now do:

- **A type mismatch** on `email` and `url`. HTML's e-mail production is
  a fixed grammar, so it is a scan rather than a judgement: a bare label
  after the `@` is allowed (`a@b` is valid) and an empty local part, an
  empty domain, a second `@` and an inner space are not. `multiple`
  makes the value a comma-separated list and judges each part. A URL
  needs a scheme and a `:`, and a host where `//` follows, so `foo:bar`
  is valid and `//example.com` and `http://` are not.
- **A step mismatch**, whose base is the surprise: the `min` attribute
  when there is one and **the `value` content attribute** otherwise. So
  `step=5 value=7` measures 7 from 7 and is a whole zero steps; a step
  mismatch can only come out of markup when `min` is there too. `step=0`
  is not a step and is ignored, and a `range` sanitises its value before
  anything asks.

**What a control's value is for this purpose** was the other half. A
checkbox and a radio have one only when checked; a select's is its
selected option's, which is that option's own text when it declares no
`value` -- so `<select required><option>x</option></select>` is
satisfied by the option HTML selected for it, and the same markup with
`multiple` is not, because such a select selects nothing of its own.

Three more instrument rows, 126/126 to 129/129. Disabling the step check
and the URL check was tried and both rows fail.

Two conditions stay out, and todo.md says why. `minlength` and
`maxlength` apply only once a user has edited the value -- HTML's dirty
value flag -- so `<input minlength=5 value="abc">` is valid in Chromium
and nothing done to a document makes it otherwise. `pattern` needs a
JavaScript regular expression engine, and an unparseable pattern is
ignored, so even declining it correctly needs a parser for the syntax;
Festina has none and this project links what Festina links, so it would
have to be written by hand.

### `dir="auto"`, and the option that was selected without saying so

`:dir()` read the nearest ancestor declaring a direction and passed
`auto` over, so an element under one fell back to `ltr` whatever its
text said. `auto` computes rather than inherits: the direction is that
of the **first strong character** of the element's own text, and `ltr`
when it has none. `<bdi>` is the same thing written as an element, which
is why English inside a right-to-left division reads left to right.

A digit, a quotation mark and whitespace are not strong, so
`123 "שלום" said` reads right to left. **Which descendants count is the
part the name does not say**, and it was measured rather than derived: a
descendant with a *valid* `dir`, a `bdi`, a `script`, a `style`, a
textarea's contents, an input's value and an `alt` are all passed over,
while a `select`'s options are not. A control with `dir="auto"` that
holds its own value -- an input, a textarea -- reads that rather than
its children.

The fixture gained fourteen elements for it, written in UTF-8 with real
Hebrew in them: an escape in the source would ask a different question,
because what is being measured is what the DOM stores and how
`bidiClass` classifies it.

**And the fixture found a bug it was not written for.** Giving it a
`<select>` whose option carries no `selected` broke `option:checked`,
which had read the attribute alone: a single-selection `<select>` with
nothing declared selects its **first** option (HTML §4.10.7), and
Chromium matches it. That row had passed for as long as every select in
the fixture declared its selection.

One divergence recorded rather than copied: a `dir="auto"` element
holding `U+2066 שלום U+2069 abc` is right to left in Chromium, where
passing over the text between an isolate initiator and its matching PDI
would leave ` abc` and give left to right. Scanning for the first strong
character with no isolate handling is what agrees with the browser.

Seven more instrument rows and the `option:checked` correction, 119/119
to 126/126.

### HTML's form-state and direction pseudo-classes

Selectors 4 §11 and §14.2: `:read-write`, `:read-only`, `:required`,
`:optional`, `:placeholder-shown`, `:default`, `:indeterminate`,
`:valid`, `:invalid`, `:in-range`, `:out-of-range` and `:dir()`. Every
one of them is a question about the document's own attributes -- no
focus, no script and no user input -- so all of them are answerable
here, and none of them was answered.

What each one means was measured in Chromium against the fixture rather
than derived from its name, and several are not what the name suggests:

- **`:read-write` follows the control, not the attribute.** A checkbox
  and a radio are `:read-only` although nothing about them is readonly,
  because `readonly` does not apply to those types at all; a disabled
  text input is `:read-only` too. Every element that is not an editable
  control is `:read-only`, which is why every `p` is one.
  `contenteditable` makes any element `:read-write`, and
  `contenteditable="false"` on a nearer ancestor takes it back.
- **`:optional` does not exclude a disabled control**: the question is
  whether `required` could apply and does not.
- **`disabled` and `readonly` bar a control from constraint
  validation**, so such a control is in neither `:valid` nor
  `:invalid`. That pair is what makes these rows able to fail: an
  implementation that partitions every control between the two passes
  neither, and disabling the `readonly` bar was tried and does fail
  `input:valid`.
- **`:default` is three things**: a checked checkbox, a selected option,
  and a form's *first* submit button.
- **`:indeterminate` needs no script**: a radio in a group where nothing
  is checked is indeterminate, which the document itself expresses.

The fixture grew what the family needs -- a `required` input, one with a
`placeholder`, an unchecked radio, a number in and out of its range, a
`readonly` input and textarea, a submit button and a `dir="rtl"`
division -- and the 103 rows already there were regenerated against the
larger document and still pass unchanged.

**The instrument passes all 119 of its rows**, 21 of them from this
family, having been 61/61 over 61 rows before this run of work began.

What is deliberately not read, and recorded in todo.md: `dir="auto"`,
which asks for the first strong character of the element's own text and
falls back to `ltr` instead; and the rest of HTML's validity list -- a
type mismatch, a `pattern`, a `step` -- beside the missing value and the
range that are. `:focus-within`, `:user-valid` and `:user-invalid` need
a focus and a user this browser does not have.

The whole family answers in one function, reached after every
pseudo-class the engine already had, so nothing that worked before pays
a comparison for these.

### `:nth-child()`'s `of S` clause

Selectors 4 §6.6.5 writes the structural pseudo-class as
`:nth-child( <An+B> [of <complex-selector-list>]? )`. The clause filters
*which siblings are counted* before An+B is applied, so
`p:nth-child(2 of .lead)` is the second `.lead` among its siblings
rather than a `.lead` that happens to be second. The An+B was read and
the clause refused, which dropped the rule.

`S` is a whole complex selector list: `:nth-child(1 of .lead, .tail)`,
`:nth-child(2 of div > p)` and `:nth-child(1 of :is(.lead, .tail))` all
work, and the complex one counts only the matching siblings of each
parent. Only `:nth-child()` and `:nth-last-child()` take a clause --
`:nth-of-type(1 of p)` is a syntax error here as in Chromium -- and the
keyword needs whitespace on both sides, because `1of` is one token and
a class may be named `of`.

**`S`'s specificity counts**, added to the pseudo-class's own:
`:nth-child(1 of #a)` beats `.k.k` written either side of it, which is
what Chromium answers and what the suite now asserts.

**The keyword is matched without regard to case.** Chromium refuses
`:nth-child(2 OF .lead)` and `:nth-child(2 Of .lead)`; CSS is ASCII
case-insensitive as a general rule and nothing in the grammar marks this
keyword as an exception, so all three spellings work here. That cannot
be an instrument row, since the runner needs Chromium to match
something, so the unit suite carries it and todo.md records the
disagreement.

A compound with an `of` clause keeps it in a list of its own rather than
in `pseudos`, which holds text and could not hold selectors, and the
matcher is guarded by that list's length and lives in its own function.
A plain `:nth-child(2n+1)` still goes through `pseudos` and costs what
it did; the paired benchmark reads nothing either way.

Twelve more instrument rows, 84/94 to 96/103.

### A complex selector inside `:is()`, `:where()`, `:not()` and `:has()`

Selectors 4 §3.1 gives all four a `<complex-selector-list>`. This engine
gave them a list of *compounds*, so `:is(h2, span)` worked and
`:is(div > p)` was refused -- and a refused selector drops its whole
rule, so a page using one lost it. Each alternative is a whole
`Selector` now, matched by the same right-to-left walk an ordinary
selector uses.

**`:has()` takes a relative selector list** (§4.2), which is the same
change wearing a different hat: an alternative may open with the
combinator that says how the match stands to the element being tested --
`:has(> p)` a child, `:has(+ p)` the next sibling, `:has(~ p)` any later
one -- and the bare form means a descendant. The relation is stored per
alternative, because `:has(> p, + div)` names two of them and Chromium
answers both, asked directly.

The relation is checked where the walk runs out of compounds: the
leftmost one has matched some element, and that element must stand to
the tested element as the relation says. Which elements can be the
subject follows from the same relation -- a descendant or child relation
puts the whole match inside the element's own subtree, a sibling
relation inside a following sibling's -- so `:has()` walks those and not
the document.

**`:is()` and `:where()` forgive; `:not()` and `:has()` do not.** An
alternative the engine cannot read is dropped from a forgiving list and
the rest still work, so `:is(p, &&&bogus)` matches every `p`; a
forgiving list that forgave everything matches nothing rather than
invalidating its rule. In the other two one bad alternative drops the
whole rule, and a leading combinator outside `:has()` is a syntax error
rather than a relation. Every one of those was asked of Chromium before
it was written.

**A complex alternative carries its whole specificity**, which no
"which ids does this match" comparison can see: `:is(div > p)` is
(0,0,2) and beats a plain `p` written after it, while
`:where(div > p)` is (0,0,0) and loses to one written before it. The
unit suite asserts all three, and the specificity of a sub-selector is
now the inner selector's rather than its first compound's.

**Where the call is written cost two milliseconds.** `matchSelector`,
called from inside `matchCompound`'s own loop over sub-selectors, put
that function in a cycle -- `matchCompound` → `matchSelector` →
`matchFrom` → `matchCompound` -- and a page with no `:is()`, no `:not()`
and no `:has()` in it paid two milliseconds of cascade for a loop it
runs zero times. The loop lives in `matchSubSelectors` now, called only
when there is a sub-selector to match, and the cost goes back to
nothing. benchmarks.md has both readings and the reason the second one
is not the first one repeated.

The instrument went from 61 rows to 94 and from 61/61 to 84/94: 25 rows
were added as the measurement, then 8 more that this work made worth
asking -- the relations, the mixed-relation form, a complex selector
under a relation, and the five forgiving cases. The ten that fail are
`:nth-child()`'s `of S` clause and the form-state and direction
pseudo-classes.

### An attribute selector's brackets, quotes and escapes

Selectors 4 §6.1 builds `[name matcher value]` out of two CSS Syntax 3
tokens: the name is an identifier, and the value is an identifier or a
string. So both take escapes, and a string takes any character at all --
including the `]` that ends the selector, the `[` that opened it, and
the quote around it. Three places read a bracket wherever they saw one
and decoded nothing:

- `parseSelectorList` counted the `[` inside `[data-x="a[b"]`, so the
  comma after it was never top-level and `[data-x="a[b"], #n` became one
  selector naming nothing -- the rule dropped whole, `#n` with it.
- The compound parser took the first `]` it found, cutting
  `[data-x="a]b"]` inside the quotes and leaving `"]` over, which marked
  the selector unsupported and dropped its rule for a second reason.
- `parseAttrSel` decoded no escape, so `[data\-x=a\ b]` looked for an
  attribute called `data` holding the value `a\` -- neither of which any
  document has.

All three skip strings and escapes now, and the name and both forms of
value go through the same `cssDecodeIdent` the identifier scan already
used. A selector with no backslash and no quote in it is unchanged: the
decoder hands back an identifier it finds no backslash in.

Measured first, against Chromium, as a sweep of 37 attribute selectors
asked with `element.matches()`: 14 differed, and every one of them is
one of the three above. The suite pins them as pairs -- a value spelled
quoted against the same value spelled with the character escaped, one
quote character against the other, a hex escape against the character it
names -- because a pair asserts the two spellings agree without either
answer being known in advance.

Two rows of that sweep are the engine ahead of the browser: Selectors 4
§6.3's `s` modifier works here and throws a `SyntaxError` in Chromium,
so the selector conformance instrument can never grade it. It has unit
checks of its own instead.

### `<!--` and `-->` are ignored where a rule is read

CSS Syntax 3 §5.4.1 ignores a CDO and a CDC at the top level of a
stylesheet: they are the wrapper pages once put round a `<style>`
element so a browser that did not know the tag would not print its
contents. Unrecognised, each was swept into the selector beside it and
took that rule with it -- a sheet written in the old style lost its
first rule, and a stray `-->` lost the rule after it.

They are skipped now, and only where §5.4.1 says: the flag is a
parameter, so an at-rule's body and a nested rule's body are parsed
without it.

**A `-->` that follows name characters is not a CDC**, because the
identifier takes both hyphens and the `>` left over is a child
combinator. Chromium's `selectorText` for `a-->b` is `a-- > b`, asked
of it directly rather than inferred from a render, and the suite pins
that: testing for the token only where a rule or a declaration begins
is what keeps it true, and a check would have caught a skip that cut
such a selector in half.

Inside a declaration block the two engines already agreed --
`#a{--> background:#0000ff}` leaves the earlier `background` standing
in both, because the declaration's name is not one either knows -- so
nothing there changed.

### An escape in a selector's identifier is decoded

CSS Syntax 3 §4.3.7 decodes an escape as it consumes an identifier. The
backslash was accepted as an ordinary name character and kept, so
`.a\.b` scanned as a class `a\` followed by a class `b` and could never
match `class="a.b"`. `#x\#y`, `.\41 bc` and `.e\2d f` were all the
same, and a site that escapes a dot in a class name -- which is what a
name holding one requires -- got none of its rules.

Both forms work now: a backslash before a non-hex character stands for
that character, and one before up to six hex digits stands for the code
point they name, with a single following whitespace consumed as the
escape's terminator rather than left as a descendant combinator. Zero,
a surrogate and anything past the last code point become U+FFFD. An
identifier with no backslash in it is handed straight back.

**Where a code point above ASCII goes took a measurement rather than a
guess.** The first draft sent it to the three-part form
`src/html/decode.f` rewrites the document's bytes into; asking the DOM
what it actually stores showed an attribute holding the real character,
because the tokenizer expands those escapes as it reads. So the decoded
identifier is `text` and carries the character itself, which is the only
spelling a selector and an attribute can meet in.

The check for that case then failed against a fix that was already
right: Festina's string literals take no `\uXXXX`, so the fixture's
`class="caf\u00e9"` was six ordinary characters. The test file carries
a literal U+00E9 now.

The first version asked each identifier again whether it held a
backslash, after the scan had already looked at every byte of it, and a
stylesheet of 6,000 selectors paid a millisecond for the second pass.
The scan sets a flag instead. A placement control could not settle that
one -- the compiler removes code nothing calls, so the control came out
four kilobytes below the candidate -- and the code answered instead;
benchmarks.md has both readings.

### A `/*` inside a string is not a comment

Comments are consumed by the tokenizer (CSS Syntax 3 §4.3), so a `/*`
is only a comment where a token can begin. The scan that strips them
ran first and knew none of that, so `font-family: "/*"` opened a
comment that ran to the next `*/` -- and where the sheet had none, to
its end. Both rules of the two-rule fixture were lost, not just the one
holding it: a single `content: "/*"` in a site's stylesheet dropped
every rule after it.

The scan knows the three places now -- `'...'`, `"..."` and an unquoted
`url(...)`, with a backslash escaping the next character in each -- and
a stylesheet with no `/*` in it pays the one search it paid before. The
prefix the `url(` test compares against is built once outside the loop
rather than per byte, and the letter is checked first so the compare
runs only where it can match.

**The other direction is the easier one to get wrong, and the suite
pins it.** A comment ends at the *first* `*/` whatever is inside it, so
a quote there is ordinary text and `/* "*/` really does leave a string
open and swallow the rest of the sheet. Chromium loses that rule too,
measured, so the check asserts the loss rather than fixing it.

### Grid 1 §8.3's named spans, in both directions

`span <custom-ident>` counts lines carrying that name rather than
tracks. The name was dropped at the parser, so every named span was a
span of one whichever way it ran, and both halves of the sentence were
wrong: `grid-column: 1 / span zz` should reach the first implicit line
past the explicit grid, and `grid-column: span zz / 3` the first one
*before* line 1 -- which puts a track in front of the grid and
renumbers every line after it.

The parser keeps the name now, `[ <integer> || <custom-ident> ]` in
either order, and the search runs outward from the line the other edge
fixes, counting only lines that carry the name and taking the shortfall
from the implicit lines on that side. Where that lands before line 1
the placement pass moves every item over by it and the template gets
that many tracks at its head, from `grid-auto-columns`. A grid that
never writes `span <name>` is handed its own track list back.

The tests are agreements rather than pixels, because the track the
search creates is one the template could have written:
`100px 100px` with `span zz / 3` has to land where
`auto 100px 100px` with `1 / 4` lands, item and auto-placed sibling
alike -- and the sibling is what makes the check about the renumbering
rather than only about the item, since it moves only if line 1 moved.

**A subgrid is the exception, and only a measurement found it.** Grid 2
§3.1 gives a subgrid no implicit tracks of its own, so a backwards
search that runs off its front stops at its first line and the span
shrinks with it. The first implementation made a track there, and the
check read clean: without a size on it the track comes out zero wide.
Putting `grid-auto-columns: 50px` on the subgrid is what showed it --
Chromium 200 against this engine's 250 -- and that is the fixture the
suite grades now.

### A background image is cut to the curve its colour is

A background layer's image is painted into an image the size of its
painting area and blitted back, and the blit was a rectangle: a box
with a `border-radius` had its colour cut to the curve and its image
painted over the corner the page should show through. With
`background-clip: padding-box` and a border wide enough it looked
right, because the image's square corner sticks out past the padding
box's curve and the border paints over it.

The blit is cut a row at a time now, from the same span function the
shadows and the clipped colour ask for, against the radii of whichever
box `background-clip` names -- the border box's own, or those less the
border and the padding for the inner two. A box with no radius reads
one field per layer painted and blits its image whole.

The test is the agreement rather than a number: the same box painted
with an image of one colour has to show the page through its corners
where the same box painted with that colour does. Chromium's two
renders are byte-identical; these two are not, and the reason is worth
having. The colour goes through the canvas's path, which draws a corner
as a bezier; the image is cut to the ellipse. They agree to a pixel
through the body of the curve and differ by three where it runs
flattest -- at row 4 of a 40px radius the ellipse says 21.6 and the
bezier says 20, where Chromium says 21, so the engine's two answers
straddle the browser's. todo.md carries it.

**The first draft of the second check could not fail.** It put the
inset on a `border: 20px solid transparent` so the page would show
through the corner, and disabling the branch it was meant to grade
changed nothing at all. The inset is padding now, with
`background-clip: content-box`, and disabling that branch moves 16 rows.

It costs seven milliseconds of paint on sixty rounded gradient boxes,
because a blit has no source rectangle here and cutting one means
copying the region out of the layer first -- the box's pixels go
through twice. Neither benchmark page reaches it, so benchmarks.md
measures it on a page built for it and says so. The rows a corner does
not reach go back as one band rather than one each, which is two of
the nine it cost before and changes no pixel.

### A page is painted from its own answers

The painter asks a set of per-document questions -- has this document
a float, a positioned box, a box that paints whole, an outline, a
transform, a clip, a corner shape, small caps -- and each was a global
raised while a box tree was built or the cascade ran, then read while
a document was painted. One document at a time made the two agree.
Two documents alive did not: a page painted after another had been
laid out was painted with the other page's answers.

A `Page` now carries a `DocFlags` captured as its layout finishes and
put back before it is painted, so painting is a function of the page
rather than of the order. Not every answer is a boolean: the values a
property keeps by the computed style's serial live in maps that
`cascadeReset` replaces, so the page holds the old map and the next
document fills a new one.

**The deliverable is `tests/render/pagestate.f`, not the list.** It
paints a rich page, builds and paints a plain one, paints the rich one
again and requires the same pixels, then does it the other way round.
A list of flags can be incomplete; the invariant cannot. It found
three separate things: the flags themselves (248 sampled pixels
moved), `font-variant-caps`, whose values the reset threw away while
the flag said they were there (20 more), and the shadow bug below
(21 more), which was never a page-state leak at all.

### A cached shadow corner is not scaled by the last strip's alpha

A blurred `inset` shadow's rounded corners are a correction blitted
over the square answer, and the correction is cached by the geometry
it depends on. A blit carries `fillAlpha`, and the two strip passes
that draw the square answer leave `fillAlpha` wherever their last row
put it. A corner that has to be *built* ends its own builder at one,
so only a corner served from the cache was scaled by whatever the
strips left -- which made the first painting of a shadow differ from
every later one, and every box after the first on a page differ from
the first.

The check that earns its place asks two boxes with the same shadow to
land on the same pixel, and its first draft could not fail: at a blur
of 20 against a radius of 40 the correction is small enough that
halving it rounds to the same byte. The geometry it grades now -- a
blur of 8 against a radius of 24 -- moves 1204 pixels of a 100x60 box
when the alpha is wrong.

### A `border-radius` survives a layer

A clipped subtree is painted into an image and blitted back, because
the canvas has no clip region -- and an image has no path API, so a
rounded box painted into one came out **square**. `overflow: hidden`
with a `border-radius` inside it is an ordinary thing for a page to
ask for, and what it got was a rectangle: on a 120x120 box of
`border-radius: 40px` inside a 150x150 clip, Chromium leaves the
backdrop showing out to x=20 on row 4 and this engine painted the box
from x=0.

The shape is filled a row at a time now, from the same span function
the shadows ask for, so the corners come out where they belong. They
are hard-edged rather than antialiased, which is the one thing the
layer cannot do, and the boundary lands within a pixel of Chromium's.

**The test needed no number, and its first draft was wrong in a way
worth recording.** The same box outside a clip is painted through the
canvas's own path, so the two have to agree away from that edge. The
first version painted the clipped page, built the unclipped one,
painted it, then painted the clipped page *again* -- and the painter's
per-document flags are raised while a box tree is built and read while
one is painted, so the second painting took the unclipped page's
answers, never gave the clipping box a layer, and compared the
unclipped rendering with itself. Two checks beside it, written against
a literal colour, kept failing correctly and are what gave it away.
todo.md carries the hazard and the durable fix.

### A clipped background follows the inner curve

`background-clip: padding-box` cuts the background to the padding box,
whose corners are the border box's less the border on each side
(Backgrounds and Borders 3 §5.2); the content box's are that less the
padding again. This painter used the border box's own radii at the
clipped rectangle, which cuts a bigger bite out of a smaller box -- so
an 80x80 box with a 20px border and `border-radius: 40px` had a band of
**the page showing through** between its border and its background. The
background's edge sat at 48 on row 22 where Chromium puts it at 31.

Every boundary now agrees with Chromium to the pixel on that fixture,
and the suite also asks the invariant that needs no number: reducing a
radius by a border of zero is the identity, so a box with no border
must paint the same whichever box its background is clipped to.

It reuses the inner curve the inset shadow above needed, which is the
only reason this is a few lines rather than its own piece of work. A
background *image* clipped that way is still cut to a rectangle rather
than to the curve -- the same missing path as the rounded corners
inside an `overflow: hidden` subtree.

### An `inset` shadow follows the inner curve

An inset shadow is the padding box minus the hole its offset and spread
leave, and on a rounded box both of those follow a curve. This painter
drew four straight strips whatever the corners did, so on a 120x120 box
with `border-radius: 40px` and `inset 0 0 0 12px` it painted the band
straight across the corner the box had rounded away.

The padding box's corners are the border box's less the border on each
side, floored at zero, and the hole takes those less the spread again
-- 40 against a 12 spread is 28, which the pixels say is what Chromium
does: it is what puts the hole's edge at 20 on row 20 rather than at
28. Each row is then two runs between two curves rather than four
strips, using the same span function the outer shadows' corners already
ask for. Against Chromium on that fixture every edge lands within a
pixel, and the rows below the corners are unchanged.

**A blurred one now follows the curve as well.** Its two strip passes
leave the complement of the *square* hole's blurred coverage, and a
rounded hole lies inside the square one, so its coverage is the smaller
and the shadow belongs darker at a corner than the strips make it -- by
**59 units of 255** on the fixture above, which is a quarter of the
range and plainly visible.

Painting over accumulates rather than adds, so the correction is not
the difference itself: `a` then `d` gives `a + d(1 - a)`, and setting
that equal to `1 - round`, with `a` the `1 - fx*fy` already there,
solves to `d = 1 - round / (fx*fy)`. That is between zero and one
precisely because a rounded hole never covers more than a square one --
which is what makes this possible at all, the canvas having no operator
that subtracts. Each corner is one more blit of an image carrying `d`,
built by the same outer-integral sum an outer shadow's corner uses and
cached the same way. The corner error goes from 59 units to **one or
two**, which is the offset the outer shadows already carry against
Skia's three box blurs.

The strips still go into a layer that is blitted through the inner
curve a scanline at a time, which is what stops the shadow painting
over the corner the box rounded away.

**A box that has only an outer shadow never asks.** The curve is
resolved on reaching the first `inset` shadow rather than at the top of
the function, because most boxes that carry a shadow carry an outer
one.

### An outline paints in a pass of its own

CSS2 §9.9 draws the outlines of a stacking context and its descendants
after everything else in it. Here an outline was drawn with the box's
own background and border, which is step 3, so anything painted later
covered it: an in-flow block written after it, a float, a line of text
pulled over it.

Four overlaps against Chromium say where it belongs, and the fourth is
the one that settles it:

| the outline overlaps | Chromium draws |
|---|---|
| an in-flow block written after it | the **outline** |
| a float | the **outline** |
| an inline-block pulled over it | the **outline** |
| an absolutely positioned box | the **positioned box** |

So it is not the last thing of all, as §9.9's wording suggests, but a
pass between step 5 and step 8. It is that now, walking the marks the
step 3 walk already leaves on each box, and a document that declares no
outline does not walk for them at all.

**The pass is over the in-flow content, not over everything in the
context.** A float's own outline travels with the float at step 4, so
an inline-block pulled over the float covers its outline along with its
background -- measured, and already what this engine did, since a float
paints whole. That is §9.9 complete here.

**A clipping box's own outline goes on after the blit.** Such a box
paints its contents into a layer the size of its padding box, and an
outline lies outside the border box, so an outline drawn in there falls
outside the layer and vanishes -- which is what used to happen to it,
`paintClipped` having never drawn one.

**The optimization that worked above did not work here.** Recording on
each box, during the step 3 walk, whether it asks for an outline -- so
the outline pass reads no `Style` of its own, which is what took the
three-step separation from 7 ms to zero -- paired against the
straightforward version at +1 ms of paint one way and 0 the other. No
gain, so it is not in the code. The same shape of change is worth a
great deal in one place and nothing a few lines away.

**One fixture had to be rebuilt for asking the wrong question.** The
float case put the outlined box twenty pixels down with a
`margin-top`, which Chromium honours by moving the whole body and this
engine drops, because a margin that collapses all the way through to
the root is dropped here. Both engines were right about their own
layout and the test was measuring that instead. A spacer box does the
same job with no margin in it.

### CSS2 §9.9's steps 3, 4 and 5, separated

The standard paints a box's in-flow content in three steps -- the
block-level descendants' own decoration, then the non-positioned
floats, then the inline-level content -- and this painter did all three
in one walk in document order, with a box's own lines before its
children. So a float painted among its in-flow siblings instead of
above them, and inline content painted below the blocks it overlapped.
Both are now three walks of the subtree, run for every box that paints
whole, and `hitTest` runs the same three backwards.

**It could not be fixed in the hit tester, and it could not be fixed
per box.** Painter and hit tester agreed with each other while both
diverged from the standard, so moving one alone would make a click and
a pixel disagree -- which is worse. And step 5 is a property of the
whole subtree rather than of a box's siblings: an anonymous block
holding nothing but inline content is a block-level descendant, so it
is step 3 while what is in it is step 5, which is the ordinary shape of
text beside a float or beside a block. Two attempts that moved one box's
own lines were reverted for that reason before this one was written.

**A box that paints whole is a phase boundary.** A float takes its
whole subtree at step 4, and so does a positioned box, a nested
stacking context, a replaced element, and anything that paints through
a layer -- `overflow`, paint containment, a `clip-path` -- because a
layer is built and blitted once rather than three times.

**The two extra walks are free; asking them anything is not.** Written
as three walks that each ask which step paints a box, the change cost
**7 ms of a 20 ms paint** on generated.html and 23 of 33 on
features.html. None of it was the walking: replacing `boxPaintsWhole`'s
body with `return false` -- the answer it gives anyway on
generated.html, where the two binaries render the page pixel for pixel
the same -- gave back 8 ms forward and 6 reversed, which is the whole
of the figure. *Why* a handful of field reads costs a microsecond a
call is not established; todo.md keeps the question, and the first
explanation, that a `Style` read is expensive, is measured and wrong.

Two ways round it were tried before the third worked. A per-document
flag over the part of the predicate that reads a `Style` took
generated.html to +1 ms -- paired against a placement control, the
parent recompiled with this change's code renamed and called from
nowhere, so the millisecond is work rather than where the compiler put
the machine code -- and left features.html at +23, because a page with
a `transform` or a positioned box on it raises the other guards.
Collecting the boxes each later step wants into an `arr[Box]` during
the first walk cost **523 ms**, and that one is now a Festina finding
with a minimal reproduction: putting a node in a second place costs a
walk of everything under it (FINDINGS.md, finding 41).

What works is to answer the question once and write the answer on the
box. The step 3 walk marks each child with the step that paints it, and
the step 4, step 5 and positioned walks read an int. Paint is then
unchanged on generated.html and a millisecond *faster* on features.html
in both directions, the millisecond being the inline-level boxes that
are no longer painted twice. The hit tester cannot use the marks -- a
click can arrive on a page that was laid out and never painted -- so it
asks the questions itself, once per click rather than once per frame.

`tests/featurepage.py` grew a float section with a probe, so the one
pass that *can* be skipped is measured rather than skipped: the float
pass is behind `docHasFloats`, and the inline pass cannot be behind
anything, because the second of the two fixtures that measure this has
no float on it at all.

**And an inline-level box is painted once.** It is step 5 content,
reached through the line that holds it -- and it is a child box as
well, so a walk over the children that does not step over it paints the
whole of it a second time. This painter's did not, and had not since
the beginning. Nothing showed it while everything was opaque, because
the same pixels landed on the same pixels; a `border-radius` on an
inline-block is where it surfaced, its antialiased corner blended
against itself and so half a shade too solid. The suite asks it of an
`opacity: 0.5` inline-block against a block of the same colour and
opacity, which is painted once by any order at all, and requires the
two to land on the same pixel -- a number nobody has to know in
advance. It is why the two binaries do not render the benchmark page
identically, which benchmarks.md records beside the timing.

**An atomic inline is now hit through its own box.** The fragment a
line holds for one is the *margin* box, so `margin-left: -80px` on a
60-wide inline-block gives the fragment a width of **-20** at the
line's own x while the box itself sits 80 pixels to the left. The
painter always drew it from the box; hit testing read the fragment, so
the click landed nowhere near the pixels. It goes through the same
`hitChild` as every other box now, which takes it through the inverse
transform as well.

### `@counter-style` takes a `range` and a `fallback`

Counter Styles 3's two remaining descriptors this engine can act on.
`range` bounds the numbers a style writes -- a pair, `infinite` on
either side, or `auto` for the system's own -- and a counter outside it
falls to the style's `fallback`, or to `decimal` where none is
declared. The struct already carried `rangeMin`, `rangeMax` and
`hasRange` for the built-in romans, which is why `lower-roman` of 4000
has always been `4000`; what was missing was the parsing and somewhere
for the fallback to go.

**A `fallback` chain is followed four deep and then gives up.** A style
may name one that names it back, and the standard leaves that limit to
the implementation rather than defining the cycle away -- so the suite
has two checks that a loop and a self-reference both end in decimal
rather than hanging, which is the sort of thing that is easy to leave
until a page does it.

**Four instruments were thrown away before the measurement.**
`getComputedStyle(li, '::marker').content` answers `normal` whatever
the style; the `::before` form answers the *specified*
`counter(k, ranged)` rather than the string it resolved to; a DOM
`Range` over an element measures zero, because pseudo text is not in
the DOM; and an inline-block `<li>` reads the same for `symbols()` as
for `disc`, so it is seeing neither. What works is an inline-block
whose shrink-to-fit width **is** the generated text's, divided by one
character's width.

**And the first working instrument still did not discriminate.** The
fallback was first read at counters 1 and 5, where `I` and `V` are one
character and so are `1` and `5` -- so the table came out identical
with and without the descriptor. It is 8 and 9 that settle it: `VIII`
at four characters and `IX` at two against decimal's one.

`tests/unit/test_counterstyles.f` 38 -> 44.

Left out: the multi-range form of `range`, nothing having measured what
a gap between two ranges should do; `symbols()`, which no instrument
here can see, so it is not claimed; and `speak-as`, declined because
nothing here speaks and it would be a descriptor parsed and never read.

### `font-variant-caps`, synthesised rather than selected

CSS Fonts 4, and the part of it this engine can reach. No face here
carries a small-caps feature and `cairo_select_font_face` cannot load
one, so the keyword is a **drawing instruction**: a lowercase letter is
drawn as its capital at 0.7 of the font size, which is what Chromium
does when the face has no feature either (§2.2 allows it).

Measured across five sizes first -- 0.7000 at 20, 40, 80 and 100px, and
0.6876 at 16px, which is the same rule with the smaller size rounded,
0.7 x 16 being 11.2. The choice is made **letter by letter**:
`small-caps` leaves an uppercase letter at the full size,
`all-small-caps` shrinks it too, and `aBc` measures as one full-size
character plus two small ones. The line box keeps the full font's
metrics either way.

**Measuring and painting walk the run through one pair of functions**,
`smallCapsAt` and `smallCapsRunAt`, and that is the design rather than
a tidiness. A run drawn in segments the measurer did not agree with
puts ink where the layout reserved no room, and the two would drift
apart the first time either learned about a character the other did
not -- which is the same reason the resize grabber is drawn from the
functions the pointer is tested against.

**The width cache caught the stale key for the third time.** The first
implementation put the applier beside the other inherited properties,
which run *after* `refreshFontKey` -- so the key said nothing about the
keyword, and the plain run's advance was served to the small-caps one
from the cache. The tests read 72 where they wanted 51 for `abc` while
`aBc` was right, which is the signature: a mixed run had no plain
counterpart in the cache to collide with. The applier now runs before
the key is built, where the zoom's does, and for the same reason.

`tests/unit/test_text.f` 40 -> 44, and every check is a relation rather
than an advance worked out here: a small-caps run must measure what the
same letters uppercased measure at the smaller size, which is "drawn as
uppercase at 0.7" said in widths.

Properties 270 -> **271**, and `--fields` says the field that moved is
`fontCaps` rather than something belonging to another property.

**And the feature page could not see it**, which is the fourth time.
`features.html` had no `font-variant` on it at all, so the paired
benchmark would have reported free while measuring nothing. It has a
small-caps paragraph with a probe now, and `--verify` is at fifteen
features.

Left out: `petite-caps` and its `all-` form want a second synthesised
size nothing has measured, and `unicase` and `titling-caps` want a font
feature no face here carries.

### A subgrid names its own lines, and its items size the parent's tracks

Grid 2 §3's two halves, and they turned out to be one parser bug and
one missing pass.

**The name list was dropping the keyword, not the names.**
`grid-template-columns: subgrid [a] [b] [c]` is a name list beside the
keyword, naming the lines the subgrid spans. The parser recognised
`subgrid` only when it was the *whole* value, so the moment a list
appeared the flag was never set and the box became an ordinary grid --
silently, because the names themselves parsed fine. The keyword is read
off the first token now, and the names count from the subgrid's own
first line rather than the parent's: on a three-column parent a subgrid
at `grid-column: 2/4` puts `a` in the parent's second column. A subgrid
declares no tracks, so the line a name belongs to cannot be counted
from them; its lines are consecutive, one per bracketed group.

**And a subgrid is not a spanning item.** Its children sit on the
parent's tracks, so it is *their* contributions that size those tracks.
A parent of two `auto` columns holding a subgrid with a twenty-`W` item
and an `x` comes out 192.66 and 9.64 in Chromium; this engine gave 100
and 100, having treated the subgrid as one item spanning both and split
its width equally between them. The row axis was worse in a way that
shows: a subgrid of an 80px and a 30px child gave its parent two rows
of 55 where Chromium gives 80 and 30.

The sizing pass is now handed a list with every subgrid item replaced
by its children mapped onto this grid's lines, per axis, and the
placement pass still works from the original because the subgrid box is
what gets laid out. A grid with no subgrid in the axis being sized gets
its own list back and allocates nothing. The row measurement measures
the expanded list too: a grandchild has no height until something lays
it out, and the subgrid box's own height is not the answer for either
of the rows it spans.

**That needed the placement pass factored out of `layoutGrid`.** The
parent needs the answer for a subgrid's *children* before it can size
its own tracks, and running the placement from two copies of it is how
the two would come to disagree. `gridPlaceItems` is that pass, verbatim
and behaviour-preserving -- the suite read the same count before and
after the move, which is the only thing that makes a refactor of a
hundred lines worth trusting.

**A segfault caught a fixture asking nothing.** One of the new checks
compared `findById(asSpan, 'c1')` against a fixture whose spanning
element had no `id` at all, so the lookup returned null and the
dereference took the process down. That is the fourth fixture in two
tasks that was measuring nothing -- and the only one that announced
itself, because the others returned clean answers.

`tests/unit/test_grid.f` 242 -> 255.

### A grid line name the template does not declare lands after the grid

Grid 1 §8.3: "if not enough lines with that name exist, all implicit
grid lines are assumed to have that name for the purpose of finding
this position." This engine left the edge automatic and auto-placed
the item instead, so `grid-column: zz` went wherever the flow happened
to put it.

Count the explicit lines carrying the name in order and take the
shortfall from the implicit ones. A name nothing declares is short by
one, so it is the first line past the explicit grid -- line 4 on a
two-column template -- and naming line 4 brings tracks 3 and 4 into
being, which is why two implicit columns appear and the item sits in
the second of them. The count is against the **explicit** grid rather
than the grid as it stands: an item at `grid-column: 5` forces tracks
3, 4 and 5 into existence and `zz` beside it still resolves to line 4.

**A name could not be asked for by count at all.** `grid-column: a 2`
parsed as `a` and took the first line of that name, because the parser
read the first token and dropped the rest. The integer and the name
are now looked for separately, in either order as the grammar allows,
so `a 2` is the second line called `a` -- and where the template has
only one, the shortfall lands on the implicit lines like any other.

Ten cases, each written as the named placement agreeing with the
numbered one rather than as a pixel worked out here: `grid-column: zz`
must land exactly where `grid-column: 4` lands, on both axes, in width
and in height. That is a test that does not depend on either answer
being known in advance, and it is what caught the two implicit tracks
rather than one.

Left out deliberately, with the measurement in todo.md: a backwards
search, `grid-column: span zz / 3`, which assumes the name on the
implicit lines *before* the explicit grid. Chromium creates a column
ahead of line 1 for it, which renumbers every line and moves every
item already placed.

`tests/unit/test_grid.f` 202 -> 242.

### A spanning grid item widens the tracks it spans

Grid 1 §12.5's second half. A track's size came from the items that sit
in it alone, so an item spanning two `auto` columns grew neither of
them: two columns holding `x` stayed ten pixels apiece under an item
two hundred wide, where Chromium makes them a hundred each.

Fourteen cases were measured before anything was written, and they
pinned a rule with more corners than it looks like. The extra an item
needs over what its tracks already hold -- the gutters between them
counting towards it -- is shared **equally** among the spanned tracks
that may grow, and which those are depends on the contribution: a
fixed minimum takes no share of a min-content contribution, and a
`min-content` maximum takes none of a max-content one. That is why the
same span widens a `min-content` track for unbreakable text, where the
two contributions are equal, and leaves it exactly where it was for
text that wraps. A definite length maximum takes its share and stops
where it says; `fit-content()` does not, because its clamp is on the
track's own content rather than on what a spanning item asks of it.

**Two overlapping spans are what settled the algorithm's shape.** Three
`auto` columns, an item spanning 1-2 that needs ten `W`s and one
spanning 2-3 that needs fifteen: Chromium gives 48.16, 72.25, 72.25,
and no sequential loop produces that in either order. It is §12.5 as
written -- every item in a span group plans its increase against the
sizes the group started with, each track takes the **maximum** planned
for it, and the increases are applied once at the end. The first item's
pair ends up wider than it asked for, which is the giveaway.

The row axis is the same algorithm and needed one more thing: the pass
that measures items for automatic rows skipped anything spanning more
than one, so a row-spanning item had no height to contribute. It is
measured now, at the width of the columns it spans, and only where one
of the rows it spans is intrinsic.

### A grid item that names both its axes takes its cells first

Found by writing the row-axis test above, which could not be made to
mean anything until it was fixed. §8.5 step 1 positions every item with
a definite row **and** column before any auto-placed item, and this
marked them as the placement loop reached them instead -- so an auto
item written earlier took a cell a later item had already named. A grid
with two auto items and a `grid-row: 1/3; grid-column: 2` span put the
second auto item in the span's own cell, and moving the span to the
front of the document changed the answer. Chromium puts it in the row
below either way, and so does this now.

`tests/unit/test_grid.f` 170 -> 202.

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
