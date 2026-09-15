# Changelog

The past, by change. Every other document except todo.md and
benchmarks.md describes the present (CLAUDE.md, §3).

## Unreleased

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
