// CSS Grid 1: track sizing and placement.
//
// A grid is two independent axes of the same algorithm, so most of what
// is checked in one axis is checked in the other by the same means --
// and where the two should agree, they are asked to: `repeat(3, 100px)`
// against the three tracks written out, and a row-flow grid against the
// same items placed by hand.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func layoutHtml(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, width)
}

Box func findById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

text head = '<body style="margin:0;font:16px/20px monospace">'

// A grid container 300px wide, with however many items are asked for.
Box func gridOf(containerStyle:text, items:text) {
    return layoutHtml(head + '<div style="width:300px;display:grid;' + containerStyle
        + '">' + items + '</div></body>', 400)
}

text func gridCell(id:text, style:text) {
    return '<div id="' + id + '" style="' + style + '">x</div>'
}

// ---- explicit tracks in the inline axis ----------------------------------

Box g1 = gridOf('grid-template-columns:100px 200px', gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(g1, 'a').x, 0, 'the first column starts at the content edge')
checkEqInt(findById(g1, 'a').w, 100, 'and is as wide as its track')
checkEqInt(findById(g1, 'b').x, 100, 'the second column follows the first')
checkEqInt(findById(g1, 'b').w, 200, 'and is as wide as its own track')

// ---- explicit tracks in the block axis -----------------------------------

Box g2 = gridOf('grid-template-columns:100px;grid-template-rows:50px 30px',
                gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(g2, 'a').y, 0, 'the first row starts at the content edge')
checkEqInt(findById(g2, 'a').h, 50, 'and is as tall as its track')
checkEqInt(findById(g2, 'b').y, 50, 'the second row follows the first')
checkEqInt(findById(g2, 'b').h, 30, 'and is as tall as its own track')

// ---- auto-placement ------------------------------------------------------
// Four items in two columns fill row by row, which is what
// grid-auto-flow: row means and is its initial value.

Box g3 = gridOf('grid-template-columns:100px 100px;grid-template-rows:20px 20px',
                gridCell('a', '') + gridCell('b', '') + gridCell('c', '') + gridCell('d', ''))
checkEqInt(findById(g3, 'a').x, 0, 'item 1 goes in column 1')
checkEqInt(findById(g3, 'a').y, 0, 'of row 1')
checkEqInt(findById(g3, 'b').x, 100, 'item 2 goes in column 2')
checkEqInt(findById(g3, 'b').y, 0, 'of the same row')
checkEqInt(findById(g3, 'c').x, 0, 'item 3 wraps to column 1')
checkEqInt(findById(g3, 'c').y, 20, 'of row 2')
checkEqInt(findById(g3, 'd').x, 100, 'and item 4 to column 2 of row 2')

// grid-auto-flow: column fills down the first column instead.
Box g4 = gridOf('grid-auto-flow:column;grid-template-columns:100px 100px;'
                + 'grid-template-rows:20px 20px',
                gridCell('a', '') + gridCell('b', '') + gridCell('c', ''))
checkEqInt(findById(g4, 'b').x, 0, 'with column flow item 2 stays in column 1')
checkEqInt(findById(g4, 'b').y, 20, 'and moves down a row')
checkEqInt(findById(g4, 'c').x, 100, 'item 3 starts the second column')
checkEqInt(findById(g4, 'c').y, 0, 'at its first row')

// ---- fr, the free-space unit ---------------------------------------------

Box g5 = gridOf('grid-template-columns:1fr 1fr', gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(g5, 'a').w, 150, 'two equal fr tracks split the space')
checkEqInt(findById(g5, 'b').w, 150, 'evenly')

Box g6 = gridOf('grid-template-columns:1fr 2fr', gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(g6, 'a').w, 100, 'fr tracks share in proportion')
checkEqInt(findById(g6, 'b').w, 200, 'to their factors')

// fr takes what is left after the fixed tracks, not the whole width.
Box g7 = gridOf('grid-template-columns:100px 1fr', gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(g7, 'b').w, 200, 'an fr track takes what the fixed ones leave')

// ---- percentages ---------------------------------------------------------

Box g8 = gridOf('grid-template-columns:25% 75%', gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(g8, 'a').w, 75, 'a percentage track is of the container')
checkEqInt(findById(g8, 'b').w, 225, 'as is its neighbour')

// ---- repeat() ------------------------------------------------------------
// Two ways of saying one thing, which is the check that earns its place.

Box gRepeat = gridOf('grid-template-columns:repeat(3, 100px)',
                     gridCell('a', '') + gridCell('b', '') + gridCell('c', ''))
Box gWritten = gridOf('grid-template-columns:100px 100px 100px',
                      gridCell('a', '') + gridCell('b', '') + gridCell('c', ''))
checkEqInt(findById(gRepeat, 'c').x, findById(gWritten, 'c').x,
           'repeat(3, 100px) places the third item where three tracks do')
checkEqInt(findById(gRepeat, 'c').w, findById(gWritten, 'c').w, 'at the same width')
checkEqInt(findById(gWritten, 'c').x, 200, 'which is the third track')

// repeat() of a list repeats the whole list.
Box gRepeatPair = gridOf('grid-template-columns:repeat(2, 50px 100px)',
                         gridCell('a', '') + gridCell('b', '') + gridCell('c', '') + gridCell('d', ''))
checkEqInt(findById(gRepeatPair, 'c').x, 150, 'repeat(2, 50px 100px) repeats both tracks')
checkEqInt(findById(gRepeatPair, 'c').w, 50, 'starting the list again')

// ---- the gaps ------------------------------------------------------------

Box gGap = gridOf('grid-template-columns:100px 100px;column-gap:20px',
                  gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(gGap, 'b').x, 120, 'column-gap separates the columns')

Box gRowGap = gridOf('grid-template-columns:100px;grid-template-rows:20px 20px;row-gap:10px',
                     gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(gRowGap, 'b').y, 30, 'row-gap separates the rows')

// A gap is between tracks, not around them, so two columns have one.
Box gGapFr = gridOf('grid-template-columns:1fr 1fr;column-gap:20px',
                    gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(gGapFr, 'a').w, 140, 'the gap comes out of the space fr tracks share')
checkEqInt(findById(gGapFr, 'b').x, 160, 'leaving one gap between two tracks')

// ---- placing an item by line ---------------------------------------------

Box gLine = gridOf('grid-template-columns:100px 100px 100px',
                   gridCell('a', 'grid-column-start:3') + gridCell('b', ''))
checkEqInt(findById(gLine, 'a').x, 200, 'grid-column-start puts an item in that column')
check(findById(gLine, 'b').x != 200, 'and the next item does not land on top of it')

Box gEnd = gridOf('grid-template-columns:100px 100px 100px',
                  gridCell('a', 'grid-column-start:1;grid-column-end:3'))
checkEqInt(findById(gEnd, 'a').w, 200, 'an item between lines 1 and 3 covers two tracks')

Box gSpan = gridOf('grid-template-columns:100px 100px 100px',
                   gridCell('a', 'grid-column-end:span 2'))
checkEqInt(findById(gSpan, 'a').w, 200, 'a span of two covers two tracks')

Box gRowLine = gridOf('grid-template-columns:100px;grid-template-rows:20px 20px 20px',
                      gridCell('a', 'grid-row-start:2'))
checkEqInt(findById(gRowLine, 'a').y, 20, 'grid-row-start puts an item in that row')

// The shorthand says what the two longhands say.
Box gShort = gridOf('grid-template-columns:100px 100px 100px',
                    gridCell('a', 'grid-column:1 / 3'))
checkEqInt(findById(gShort, 'a').w, findById(gEnd, 'a').w,
           'the grid-column shorthand is its two longhands')

// ---- implicit tracks -----------------------------------------------------
// More items than the explicit rows hold create rows that were not
// asked for, sized by grid-auto-rows.

Box gImplicit = gridOf('grid-template-columns:100px 100px;grid-template-rows:20px;'
                       + 'grid-auto-rows:40px',
                       gridCell('a', '') + gridCell('b', '') + gridCell('c', ''))
checkEqInt(findById(gImplicit, 'c').y, 20, 'an item past the explicit rows starts a new one')
checkEqInt(findById(gImplicit, 'c').h, 40, 'sized by grid-auto-rows')

Box gAutoCol = gridOf('grid-auto-flow:column;grid-template-rows:20px;'
                      + 'grid-template-columns:100px;grid-auto-columns:60px',
                      gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(gAutoCol, 'b').x, 100, 'an implicit column follows the explicit one')
checkEqInt(findById(gAutoCol, 'b').w, 60, 'sized by grid-auto-columns')

// ---- an item's own width, and the track around it ------------------------
// The item declares a width, so it keeps it whatever the track does --
// and the track does not keep still: an auto track is stretched to what
// the rest of the grid leaves, which the track sizing section below
// measures.

Box gAuto = gridOf('grid-template-columns:auto 100px',
                   gridCell('a', 'width:40px') + gridCell('b', ''))
checkEqInt(findById(gAuto, 'a').w, 40, 'a declared width is the item width, track or no track')

Box gAutoRow = gridOf('grid-template-columns:100px',
                      gridCell('a', 'height:37px'))
checkEqInt(findById(gAutoRow, 'a').h, 37, 'and an auto row as tall as its own')

// ---- the container's own height ------------------------------------------

Box gHeight = gridOf('grid-template-columns:100px;grid-template-rows:20px 30px',
                     gridCell('a', '') + gridCell('b', ''))
Box container = findById(gHeight, 'a')
checkEqInt(parentBox(container).h, 50, 'the container is as tall as its rows')

// ---- an automatic row is as tall as what is in it -------------------------
// The block axis is sized from the items' heights, and an item has no
// height until it has been laid out, so this has to be asked of the
// container rather than of the item: an item's own `h` was already 37
// while the container around it was nothing at all.
//
// Chromium 141 gives all three of these the height of their contents:
// 37 for a declared height, one line for one line of text, two for two.
//
// `parentBox` reaches the parent through the box registry, and the
// registry belongs to the most recent layout -- so a container read
// after the next document has been laid out is that document's
// container, at whatever height it happens to have. Each layout is
// therefore asked its question before the next one runs.
int func gridHeightOf(containerStyle:text, items:text) {
    return parentBox(findById(gridOf(containerStyle, items), 'a')).h
}

int oneLine = findById(layoutHtml(head + '<div id="p" style="width:100px">x</div></body>', 400), 'p').h
check(oneLine > 0, 'a line of text has a height to compare against')

checkEqInt(gridHeightOf('grid-template-columns:100px', gridCell('a', 'height:37px')), 37,
           'an automatic row is as tall as the item in it')
checkEqInt(gridHeightOf('grid-template-columns:100px', gridCell('a', '')), oneLine,
           'an automatic row holding one line of text is one line tall')
checkEqInt(gridHeightOf('grid-template-columns:100px', gridCell('a', '') + gridCell('b', '')),
           oneLine * 2, 'and two such rows are two lines tall')

// A declared row is not measured and does not grow: the item overflows
// it, which is the case that tells a measuring pass from one that
// simply hands the container its item's height.
checkEqInt(gridHeightOf('grid-template-columns:100px;grid-template-rows:20px',
                        gridCell('a', 'height:90px')), 20,
           'a declared row keeps its height and lets the item overflow')

// ---- an item placed past the explicit grid (Grid 1 §8.1, §8.5) --------
// A line number beyond the explicit grid creates implicit tracks, and
// the flow has to wrap at the whole grid rather than at its explicit
// part. A one-column grid holding an item at `grid-column: 2` searched
// a row one cell wide for a free cell at index 1, which no search can
// find: the layout never returned. This is the check that it does.
//
// What the implicit tracks are *sized* to is the track sizing section
// below; what is checked here is that the item lands in one of them and
// that the layout returns at all.
//
// The cursor goes with it: an item that names a column moves the
// auto-placement cursor there, so an automatically placed item after it
// goes to the next row rather than back to the cell the named one
// skipped over -- measured in Chromium 141, which puts the second item
// at the start of the second row.

Box gPast = gridOf('grid-template-columns:100px',
                   gridCell('a', '') + gridCell('b', 'grid-column:2'))
Box pastA = findById(gPast, 'a')
Box pastB = findById(gPast, 'b')
check(pastA != null && pastB != null, 'both items are laid out')
checkEqInt(pastA.x, 0, 'the explicit column starts at the content edge')
checkEqInt(pastA.w, 100, 'and keeps its length')
checkEqInt(pastB.x, 100, 'the implicit column follows it')
checkEqInt(pastB.y, pastA.y, 'both are in the first row')

Box gPast3 = gridOf('grid-template-columns:100px',
                    gridCell('a', '') + gridCell('b', 'grid-column:3'))
check(findById(gPast3, 'b') != null, 'naming column 3 lays out too, two tracks past the explicit one')

Box gInside = gridOf('grid-template-columns:100px 100px',
                     gridCell('a', '') + gridCell('b', 'grid-column:2'))
checkEqInt(findById(gInside, 'b').x, 100, 'a column inside the explicit grid makes no implicit track')
checkEqInt(findById(gInside, 'b').w, 100, 'and keeps its declared length')

Box gCursor = gridOf('grid-template-columns:100px',
                     gridCell('a', 'grid-column:2') + gridCell('b', ''))
Box curA = findById(gCursor, 'a')
Box curB = findById(gCursor, 'b')
checkEqInt(curA.x, 100, 'an item that names a column is placed there')
checkEqInt(curB.x, 0, 'and the next item starts the row again')
check(curB.y > curA.y, 'in the row below, because the cursor moved past the named column')

// ---- the track sizing functions (Grid 1 §12) ---------------------------
// A track has two sizing functions, a minimum and a maximum, and every
// keyword is shorthand for a pair: `auto` is minmax(auto, max-content),
// `100px` is minmax(100px, 100px), `1fr` is minmax(auto, 1fr),
// `min-content` and `max-content` are that function twice over, and
// `fit-content(L)` is the max-content size clamped to L but never below
// the min-content size. Free space is then handed out twice: first to
// grow every track towards its maximum, in equal shares, each track
// freezing as it reaches it; then, if any is still spare and no `fr`
// track took it, to stretch the tracks whose maximum is `auto`.
//
// The item below holds two 60px inline-blocks, so its min-content
// contribution is 60 -- one per line -- and its max-content
// contribution 120, whatever the font does. Chromium 141, grid
// container 300px wide, reading `getComputedStyle().gridTemplateColumns`,
// which reports the used sizes in pixels:
//
//   min-content                 60      max-content                120
//   minmax(50px, 100px)        100      minmax(150px, 300px)       300
//   minmax(min-content, 200px) 200      minmax(max-content, 280px) 280
//   minmax(100px, min-content) 100      minmax(150px, 1fr)         300
//   fit-content(80px)           80      fit-content(200px)         120
//   fit-content(40px)           60

text twoBoxes = '<span style="display:inline-block;width:60px;height:20px"></span>'
              + '<span style="display:inline-block;width:60px;height:20px"></span>'

// One track, one item: the track is exactly what its sizing functions
// and that item make it.
int func oneTrack(cols:text) {
    Box g = gridOf('grid-template-columns:' + cols, '<div id="a">' + twoBoxes + '</div>')
    Box c = findById(g, 'a')
    return c == null ? -1 : c.w
}

checkEqInt(oneTrack('min-content'), 60, '`min-content` is the min-content contribution')
checkEqInt(oneTrack('max-content'), 120, '`max-content` is the max-content contribution')
checkEqInt(oneTrack('minmax(50px, 100px)'), 100, 'a minmax track grows to its maximum')
checkEqInt(oneTrack('minmax(150px, 300px)'), 300, 'and to a larger one when the space is there')
checkEqInt(oneTrack('minmax(min-content, 200px)'), 200, 'a min-content minimum with a length maximum')
checkEqInt(oneTrack('minmax(max-content, 280px)'), 280, 'and a max-content minimum with one')
checkEqInt(oneTrack('minmax(100px, min-content)'), 100,
           'a maximum below the minimum is the minimum')
checkEqInt(oneTrack('minmax(150px, 1fr)'), 300, 'an fr maximum takes the free space')
checkEqInt(oneTrack('fit-content(80px)'), 80, '`fit-content` clamps the max-content size')
checkEqInt(oneTrack('fit-content(200px)'), 120, 'but never grows past it')
checkEqInt(oneTrack('fit-content(40px)'), 60, 'and never shrinks below min-content')

// Two tracks, the item in the first and an empty probe in the second,
// which contributes nothing to it. Chromium 141 on the same page:
//
//   min-content max-content              60    0
//   min-content 1fr                      60  240
//   minmax(50px,100px) 1fr              100  200
//   fit-content(80px) auto               80  220
//   minmax(0px,100px) minmax(0px,400px) 100  200
//   minmax(0px,400px) minmax(0px,400px) 150  150
//   auto minmax(0px,80px)               220   80

int func twoTracks(cols:text, id:text) {
    Box g = gridOf('grid-template-columns:' + cols,
                   '<div id="a">' + twoBoxes + '</div><div id="b" style="grid-column:2"></div>')
    Box c = findById(g, id)
    return c == null ? -1 : c.w
}

checkEqInt(twoTracks('min-content max-content', 'a'), 60, 'the first of two tracks is its own size')
checkEqInt(twoTracks('min-content max-content', 'b'), 0, 'and an empty max-content track is zero')
checkEqInt(twoTracks('min-content 1fr', 'a'), 60, 'an fr track beside a min-content one')
checkEqInt(twoTracks('min-content 1fr', 'b'), 240, 'takes everything the other left')
checkEqInt(twoTracks('minmax(50px,100px) 1fr', 'a'), 100, 'a minmax track reaches its maximum first')
checkEqInt(twoTracks('minmax(50px,100px) 1fr', 'b'), 200, 'and the fr track takes the rest')
checkEqInt(twoTracks('fit-content(80px) auto', 'a'), 80, 'a fit-content track beside an auto one')
checkEqInt(twoTracks('fit-content(80px) auto', 'b'), 220, 'which is stretched by what is spare')
checkEqInt(twoTracks('minmax(0px,100px) minmax(0px,400px)', 'a'), 100,
           'free space is shared equally until a track freezes at its maximum')
checkEqInt(twoTracks('minmax(0px,100px) minmax(0px,400px)', 'b'), 200,
           'and what the frozen one could not take goes to the other')
checkEqInt(twoTracks('minmax(0px,400px) minmax(0px,400px)', 'a'), 150,
           'two tracks that freeze at nothing share it evenly')
checkEqInt(twoTracks('minmax(0px,400px) minmax(0px,400px)', 'b'), 150, 'half each')
checkEqInt(twoTracks('auto minmax(0px,80px)', 'a'), 220,
           'an auto track is stretched by whatever the maximizing left over')
checkEqInt(twoTracks('auto minmax(0px,80px)', 'b'), 80, 'the limited one stays at its maximum')

// The same two tracks with an item narrower than its track, which is
// where `auto` differs from `max-content`. Chromium 141:
//
//   auto 100px   200 100      auto auto   170 130      auto 1fr   40 260

int func narrowTracks(cols:text, id:text) {
    Box g = gridOf('grid-template-columns:' + cols,
                   '<div id="a"><div style="width:40px;height:20px"></div></div>'
                   + '<div id="b" style="grid-column:2"></div>')
    Box c = findById(g, id)
    return c == null ? -1 : c.w
}

checkEqInt(narrowTracks('auto 100px', 'a'), 200, 'an auto track takes the space a fixed one leaves')
checkEqInt(narrowTracks('auto 100px', 'b'), 100, 'and the fixed track keeps its length')
checkEqInt(narrowTracks('auto auto', 'a'), 170, 'two auto tracks split the free space equally')
checkEqInt(narrowTracks('auto auto', 'b'), 130, 'from bases of 40 and 0')
checkEqInt(narrowTracks('auto 1fr', 'a'), 40, 'an auto track beside an fr one is not stretched')
checkEqInt(narrowTracks('auto 1fr', 'b'), 260, 'because the fr track took the free space first')

// The implicit tracks the placement section above leaves unsized are
// sized by the same rules, `grid-auto-columns: auto` being the initial
// value. Chromium 141: `100px` plus an item at column 2 is 100px 200px,
// and plus one at column 3 is 100px 100px 100px.
// The probe is empty here, because an implicit track with something in
// it is sized by that something: `x` in the last column is ten pixels
// of min-content and the stretching starts from those rather than
// from nothing.
Box gImp2 = gridOf('grid-template-columns:100px',
                   gridCell('a', '') + '<div id="b" style="grid-column:2"></div>')
checkEqInt(findById(gImp2, 'b').w, 200, 'an implicit auto column is stretched like any other')
Box gImp3 = gridOf('grid-template-columns:100px',
                   gridCell('a', '') + '<div id="b" style="grid-column:3"></div>')
checkEqInt(findById(gImp3, 'b').x, 200, 'two implicit columns share what is left')
checkEqInt(findById(gImp3, 'b').w, 100, 'equally, 100 each')

// ---- the same functions in the block axis ------------------------------
// The container has no height, so there is no free space to maximize
// with -- and where the free space is indefinite the standard makes a
// track whose maximum is a definite length take that length (§12.5).
// Chromium 141, on an item 40px tall:
//
//   min-content / max-content / auto / 1fr  40      minmax(30px, 60px)   60
//   minmax(80px, 120px)                    120      fit-content(25px)    40
//   auto auto                             40  0

int func rowHeight(rows:text, id:text) {
    Box g = gridOf('grid-template-columns:100px;grid-template-rows:' + rows,
                   '<div id="a"><div style="height:40px"></div></div>'
                   + '<div id="b" style="grid-row:2"></div>')
    Box c = findById(g, id)
    return c == null ? -1 : c.h
}

checkEqInt(rowHeight('min-content', 'a'), 40, 'a min-content row is the item height')
checkEqInt(rowHeight('max-content', 'a'), 40, 'and so is a max-content row')
checkEqInt(rowHeight('auto', 'a'), 40, 'and an auto row, with no height to stretch into')
checkEqInt(rowHeight('1fr', 'a'), 40, 'and an fr row, with no free space to take')
checkEqInt(rowHeight('minmax(30px, 60px)', 'a'), 60,
           'a definite maximum is the size where the free space is indefinite')
checkEqInt(rowHeight('minmax(80px, 120px)', 'a'), 120, 'whatever the item needs')
checkEqInt(rowHeight('fit-content(25px)', 'a'), 40,
           'a fit-content maximum is not a definite one, so the content decides')
checkEqInt(rowHeight('auto auto', 'a'), 40, 'the first of two auto rows is its item')
checkEqInt(rowHeight('auto auto', 'b'), 0, 'and an empty one is nothing')

// ---- repeat(auto-fill) and repeat(auto-fit) (Grid 1 §7.2.3.2) ---------
// How many times the group repeats is decided by the space available
// rather than written down, so it cannot be expanded when the template
// is parsed. The count is the largest N that does not overflow:
//
//   N = floor((S - F - (K-1)*gap) / (G + L*gap))
//
// for a container of S, K fixed tracks outside the repeat totalling F,
// and a group of L tracks totalling G. Chromium 141 in a 300px grid:
//
//   repeat(auto-fill, 100px)               100px 100px 100px
//   repeat(auto-fill, 90px)                 90px  90px  90px   30 left over
//   repeat(auto-fill, 100px), gap 10px     100px 100px
//   repeat(auto-fill, 90px), gap 20px       90px  90px
//   repeat(auto-fill, 70px) 100px           70px  70px 100px
//   repeat(auto-fill, minmax(90px, 1fr))   100px 100px 100px
//
// A probe item names the last track, because the count is only visible
// in where a named column lands.

int func fillTrack(cols:text, extra:text, col:text, id:text) {
    Box g = gridOf('grid-template-columns:' + cols + ';' + extra,
                   gridCell('a', '') + '<div id="b" style="grid-column:' + col + '"></div>')
    Box c = findById(g, id)
    return c == null ? -1 : c.w
}
int func fillTrackX(cols:text, extra:text, col:text, id:text) {
    Box g = gridOf('grid-template-columns:' + cols + ';' + extra,
                   gridCell('a', '') + '<div id="b" style="grid-column:' + col + '"></div>')
    Box c = findById(g, id)
    return c == null ? -1 : c.x
}

checkEqInt(fillTrackX('repeat(auto-fill, 100px)', '', '3', 'b'), 200,
           'auto-fill repeats a 100px track three times in 300')
checkEqInt(fillTrack('repeat(auto-fill, 100px)', '', '3', 'b'), 100, 'each of them its own length')
checkEqInt(fillTrackX('repeat(auto-fill, 90px)', '', '3', 'b'), 180,
           'and a 90px track three times, leaving 30 over')
checkEqInt(fillTrack('repeat(auto-fill, 90px)', '', '3', 'b'), 90, 'without stretching any of them')
checkEqInt(fillTrackX('repeat(auto-fill, 100px)', 'column-gap:10px', '2', 'b'), 110,
           'a gap counts against the space, so 100px repeats twice')
checkEqInt(fillTrackX('repeat(auto-fill, 90px)', 'column-gap:20px', '2', 'b'), 110,
           'and so does 90px with a 20px gap')
checkEqInt(fillTrackX('repeat(auto-fill, 70px) 100px', '', '3', 'b'), 140,
           'a track outside the repeat is subtracted first')
checkEqInt(fillTrack('repeat(auto-fill, 70px) 100px', '', '3', 'b'), 100,
           'and keeps its own length at the end')
checkEqInt(fillTrack('repeat(auto-fill, minmax(90px, 1fr))', '', '3', 'b'), 100,
           'the count uses the minimum, and the fr maximum then shares the space')
checkEqInt(fillTrackX('repeat(auto-fill, minmax(90px, 1fr))', '', '3', 'b'), 200,
           'three tracks of a hundred')

// `auto-fit` counts the same way and then collapses every track no item
// occupies, along with the gutters beside it. Chromium 141, 300px wide
// with a 20px column gap and `repeat(auto-fit, 60px)`: four tracks, of
// which the second and third are empty, reads `60px 0px 0px 60px` and
// puts the item in the fourth track at x = 80 -- one gutter past the
// first, not three.
Box gFit = gridOf('grid-template-columns:repeat(auto-fit, 60px);column-gap:20px',
                  gridCell('a', '') + gridCell('b', 'grid-column:4'))
checkEqInt(findById(gFit, 'a').w, 60, 'an occupied auto-fit track keeps its size')
checkEqInt(findById(gFit, 'b').w, 60, 'and so does the one further along')
checkEqInt(findById(gFit, 'b').x, 80,
           'the collapsed tracks between them, and their gutters, take no space')

// With every track occupied nothing collapses.
Box gFitFull = gridOf('grid-template-columns:repeat(auto-fit, 100px)',
                      gridCell('a', '') + gridCell('b', '') + gridCell('c', ''))
checkEqInt(findById(gFitFull, 'b').x, 100, 'three items fill three auto-fit tracks')
checkEqInt(findById(gFitFull, 'c').x, 200, 'and none of them collapses')

// An fr maximum inside auto-fit gives the whole width to the tracks that
// survive: Chromium reads `300px 0px 0px` for one item and
// `150px 150px 0px` for two.
Box gFitFr = gridOf('grid-template-columns:repeat(auto-fit, minmax(90px, 1fr))', gridCell('a', ''))
checkEqInt(findById(gFitFr, 'a').w, 300, 'one item in an auto-fit fr repeat takes the width')
Box gFitFr2 = gridOf('grid-template-columns:repeat(auto-fit, minmax(90px, 1fr))',
                     gridCell('a', '') + gridCell('b', ''))
checkEqInt(findById(gFitFr2, 'a').w, 150, 'two items halve it')
checkEqInt(findById(gFitFr2, 'b').x, 150, 'the second starting where the first ends')

// ---- grid-auto-flow: dense (Grid 1 §8.5) ------------------------------
// Sparse packing never moves the cursor backwards, so a hole left by an
// item too wide to fit stays a hole. Dense packing starts each item's
// search at the beginning again and fills it. Chromium 141 on a
// two-column grid holding a single cell, a cell spanning both columns,
// and another single cell, with rows ten pixels tall:
//
//   row        a (0,0)   b (0,10)   c (0,20)
//   row dense  a (0,0)   b (0,10)   c (100,0)

text denseItems = gridCell('a', 'height:10px')
                + '<div id="b" style="grid-column:span 2;height:10px">b</div>'
                + gridCell('c', 'height:10px')

Box gSparse = gridOf('grid-template-columns:100px 100px', denseItems)
checkEqInt(findById(gSparse, 'b').y, 10, 'an item too wide for the rest of the row starts a new one')
checkEqInt(findById(gSparse, 'c').x, 0, 'and the next item follows it')
checkEqInt(findById(gSparse, 'c').y, 20, 'in a row of its own, leaving the hole beside a')

Box gDense = gridOf('grid-template-columns:100px 100px;grid-auto-flow:row dense', denseItems)
checkEqInt(findById(gDense, 'b').y, 10, 'dense packing places the wide item in the same place')
checkEqInt(findById(gDense, 'c').x, 100, 'but fills the hole beside a with what follows')
checkEqInt(findById(gDense, 'c').y, 0, 'in the first row')

// ---- subgrid (CSS Grid 2 §3) --------------------------------------------
// A grid item that is itself a grid can take its tracks from the lines
// of its parent that it spans, rather than sizing tracks of its own, so
// the two levels line up. The gaps come with them.
//
// Chromium 141 on a 300px grid of 100px 150px 50px and rows of 40 and
// 60, with an item spanning all of it and subgridding both axes:
//
//   the item's own children land at 0, 100 and 250, 100, 150 and 50
//   wide, and 40 then 60 tall on the second row
//
// and on the same columns with an item spanning the second and third:
//
//   its children are 150 and 50 wide, the first starting at x = 100
Box gSub = gridOf('grid-template-columns:100px 150px 50px;grid-template-rows:40px 60px',
    '<div id="sub" style="grid-column:1 / 4;grid-row:1 / 3;display:grid;'
    + 'grid-template-columns:subgrid;grid-template-rows:subgrid">'
    + '<div id="sa"></div><div id="sb"></div><div id="sc"></div>'
    + '<div id="sd"></div><div id="se"></div><div id="sf"></div></div>')
checkEqInt(findById(gSub, 'sa').x, 0, 'a subgrid puts its first child on the parent\'s first line')
checkEqInt(findById(gSub, 'sa').w, 100, 'at the width of the parent\'s own track')
checkEqInt(findById(gSub, 'sb').x, 100, 'the second child on the second line')
checkEqInt(findById(gSub, 'sb').w, 150, 'and that track\'s width')
checkEqInt(findById(gSub, 'sc').x, 250, 'the third where the parent\'s third track starts')
checkEqInt(findById(gSub, 'sc').w, 50, 'and as wide as it is')
checkEqInt(findById(gSub, 'sd').y, 40, 'the rows are the parent\'s too')
checkEqInt(findById(gSub, 'sd').h, 60, 'each as tall as the parent made it')

Box gSub2 = gridOf('grid-template-columns:100px 150px 50px',
    '<div id="sub2" style="grid-column:2 / 4;display:grid;grid-template-columns:subgrid">'
    + '<div id="ta"></div><div id="tb"></div></div>')
checkEqInt(findById(gSub2, 'ta').x, 100, 'a subgrid over part of the grid starts where its span does')
checkEqInt(findById(gSub2, 'ta').w, 150, 'with the first of the tracks it spans')
checkEqInt(findById(gSub2, 'tb').x, 250, 'and the second beside it')
checkEqInt(findById(gSub2, 'tb').w, 50, 'at that track\'s own width')

// A grid that is not a subgrid item sizes its own tracks, whatever the
// keyword would have done: this is the check that says the two are told
// apart rather than one standing in for the other.
Box gPlain = gridOf('grid-template-columns:100px 150px 50px',
    '<div id="plain" style="grid-column:1 / 4;display:grid;grid-template-columns:60px 40px">'
    + '<div id="pa"></div><div id="pb"></div></div>')
checkEqInt(findById(gPlain, 'pa').w, 60, 'an ordinary nested grid keeps its own first track')
checkEqInt(findById(gPlain, 'pb').x, 60, 'and its own second')

// ---- justify-content and align-content position the tracks ------------
//
// Measured in Chromium (todo.md): two `auto` columns holding `ab` and
// `cd` in a 400px grid are 200 wide apiece under `normal` and their
// content width apiece under `start`, `center`, `end` and
// `space-between`, which then place the pair at the start, centred, at
// the end, and spread to both edges. `align-content` answers the same
// way on the row axis.
//
// The numbers below are relations rather than pixel counts wherever a
// font advance is involved, because this engine's advance is not
// Chromium's: what is asserted is that `normal` fills the container and
// that the other four leave the tracks at the width `start` gives them
// and only move them.

Box func jcGrid(jc:text) {
    text decl = jc == '' ? '' : (';justify-content:' + jc)
    return layoutHtml(head
        + '<div id="g" style="display:grid;grid-template-columns:auto auto;'
        + 'width:400px' + decl + '">'
        + '<div id="c1">ab</div><div id="c2">cd</div></div></body>', 800)
}

Box jcNormal = jcGrid('normal')
Box jcNone = jcGrid('')
Box jcStart = jcGrid('start')
Box jcCentre = jcGrid('center')
Box jcEnd = jcGrid('end')
Box jcBetween = jcGrid('space-between')

Box nc1 = findById(jcNormal, 'c1')
Box nc2 = findById(jcNormal, 'c2')
checkEqInt(nc1.x, 0, 'normal puts the first track at the start')
checkEqInt(nc1.w, 200, 'and stretches it to half the container')
checkEqInt(nc2.x, 200, 'the second follows it')
checkEqInt(nc2.w, 200, 'and takes the other half')

// Declaring nothing is `normal`, which is the initial value -- so the
// two must agree rather than each match a number.
checkEqInt(findById(jcNone, 'c1').w, nc1.w, 'an undeclared justify-content is normal')
checkEqInt(findById(jcNone, 'c2').x, nc2.x, 'on both tracks')

Box sc1 = findById(jcStart, 'c1')
Box sc2 = findById(jcStart, 'c2')
check(sc1.w < 200, 'start does not stretch the track')
check(sc1.w > 0, 'and leaves it its content width')
checkEqInt(sc1.x, 0, 'start packs the tracks at the start')
checkEqInt(sc2.x, sc1.x + sc1.w, 'with the second against the first')

// The four that do not stretch must all give the same track widths:
// only where the tracks sit changes.
int packed = sc1.w + sc2.w
checkEqInt(findById(jcCentre, 'c1').w, sc1.w, 'center leaves the widths alone')
checkEqInt(findById(jcEnd, 'c1').w, sc1.w, 'and so does end')
checkEqInt(findById(jcBetween, 'c1').w, sc1.w, 'and space-between')

checkEqInt(findById(jcCentre, 'c1').x, Math.floorDiv(400 - packed, 2),
           'center puts the pair in the middle')
checkEqInt(findById(jcEnd, 'c2').x + findById(jcEnd, 'c2').w, 400,
           'end puts the last track against the far edge')
checkEqInt(findById(jcBetween, 'c1').x, 0, 'space-between starts at the near edge')
checkEqInt(findById(jcBetween, 'c2').x + findById(jcBetween, 'c2').w, 400,
           'and ends at the far one')

// ---- the row axis answers the same way ---------------------------------
Box func acGrid(ac:text) {
    text decl = ac == '' ? '' : (';align-content:' + ac)
    return layoutHtml(head
        + '<div id="g" style="display:grid;grid-template-rows:auto auto;'
        + 'height:400px' + decl + '">'
        + '<div id="r1">ab</div><div id="r2">cd</div></div></body>', 800)
}

Box acNormal = acGrid('normal')
Box acStart = acGrid('start')
Box acEnd = acGrid('end')
Box acBetween = acGrid('space-between')

checkEqInt(findById(acNormal, 'r1').h, 200, 'align-content: normal stretches the row')
checkEqInt(findById(acNormal, 'r2').y, 200, 'and the second follows it')

Box ar1 = findById(acStart, 'r1')
Box ar2 = findById(acStart, 'r2')
check(ar1.h < 200, 'start does not stretch the row')
checkEqInt(ar1.y, 0, 'and packs it at the top')
checkEqInt(ar2.y, ar1.y + ar1.h, 'with the second under it')

checkEqInt(findById(acEnd, 'r2').y + findById(acEnd, 'r2').h, 400,
           'end puts the last row against the bottom')
checkEqInt(findById(acBetween, 'r1').y, 0, 'space-between starts at the top')
checkEqInt(findById(acBetween, 'r2').y + findById(acBetween, 'r2').h, 400,
           'and ends at the bottom')

// ---- Grid 1 §12.5: a spanning item widens the tracks it spans ---------
// Measured against Chromium first (todo.md carries the fourteen cases).
// Every assertion here is a relation rather than one of Chromium's
// pixel counts, because this engine's font advance is its own: what
// must hold is that the extra a spanning item needs is shared equally
// among the spanned intrinsic tracks, that a track outside the span or
// unable to grow takes none of it, and that two spans overlapping a
// track resolve by the maximum of what each planned rather than by
// whichever ran last.
//
// Every container here is wide and says `justify-content: start`, which
// is what makes the instrument able to fail. A grid that shrinks to fit
// is the obvious fixture and the wrong one: its width already accounts
// for the spanning item, so §12.8 stretches the tracks to fill it and
// two of these checks pass against an engine that has no §12.5 at all.
// Chromium gives the same track sizes either way, so nothing is given
// up by taking the stretch out of the picture.

text SPAN20 = 'WWWWWWWWWWWWWWWWWWWW'
text SPAN10 = 'WWWWWWWWWW'
text SPAN15 = 'WWWWWWWWWWWWWWW'

Box func spanGrid(cols:text, extra:text, items:text) {
    return layoutHtml(head
        + '<div id="g" style="display:grid;width:700px;justify-content:start;'
        + 'grid-template-columns:' + cols + ';' + extra + '">' + items
        + '</div></body>', 800)
}

text PROBES = '<div id="c1">x</div><div id="c2">x</div>'
text PROBES3 = '<div id="c1">x</div><div id="c2">x</div><div id="c3">x</div>'

// The item alone, so the test knows what it is asking the tracks to hold
// without hard-coding a font advance.
Box lone = layoutHtml(head + '<div id="w" style="float:left">' + SPAN20
                      + '</div></body>', 800)
int span20W = findById(lone, 'w').w
check(span20W > 100, 'the spanning item is wide enough to be worth sharing')

// Two auto columns with nothing spanning them: the baseline the rest is
// measured against.
Box noSpan = spanGrid('auto auto', '', PROBES)
int probeW = findById(noSpan, 'c1').w
check(probeW < span20W, 'a track holding one character is narrower than the item')

Box two = spanGrid('auto auto', '',
    PROBES + '<div style="grid-column:1/3">' + SPAN20 + '</div>')
Box t1 = findById(two, 'c1')
Box t2 = findById(two, 'c2')
check(t1.w > probeW, 'a spanning item widens the first track it spans')
checkEqInt(t2.w, t1.w, 'and both tracks take an equal share of the extra')
checkEqInt(t1.w + t2.w, span20W, 'and together they come to hold the item')

// The gutter between the tracks counts against what the item needs, so
// the tracks grow less by exactly the gap.
Box gapped = spanGrid('auto auto', 'column-gap:20px',
    PROBES + '<div style="grid-column:1/3">' + SPAN20 + '</div>')
Box gapA = findById(gapped, 'c1')
Box gapB = findById(gapped, 'c2')
checkEqInt(gapB.w, gapA.w, 'a gap leaves the shares equal')
checkEqInt(gapA.w + gapB.w + 20, span20W, 'and the gutter is part of what the item spans')

// A fixed track takes no share: it is not intrinsic, so all of the extra
// goes to the one track that can grow.
Box fixed = spanGrid('60px auto', '',
    PROBES + '<div style="grid-column:1/3">' + SPAN20 + '</div>')
checkEqInt(findById(fixed, 'c1').w, 60, 'a fixed track keeps its length')
checkEqInt(findById(fixed, 'c2').w, span20W - 60,
           'and the intrinsic track absorbs the whole of the extra')

// A track stops at its growth limit and hands the remainder on.
Box limited = spanGrid('minmax(auto,40px) auto', '',
    PROBES + '<div style="grid-column:1/3">' + SPAN20 + '</div>')
checkEqInt(findById(limited, 'c1').w, 40, 'a track grows no further than its limit')
checkEqInt(findById(limited, 'c2').w, span20W - 40,
           'and what it could not take goes to the rest')

// A track outside the span is untouched.
Box three = spanGrid('auto auto auto', '',
    PROBES3 + '<div style="grid-column:1/3">' + SPAN20 + '</div>')
Box t3a = findById(three, 'c1')
Box t3b = findById(three, 'c2')
Box t3c = findById(three, 'c3')
checkEqInt(t3b.w, t3a.w, 'the two spanned tracks share equally')
checkEqInt(t3a.w + t3b.w, span20W, 'and hold the item between them')
checkEqInt(t3c.w, probeW, 'the track outside the span is left where it was')

// An item spanning a flexible track contributes to no base size: §12.7
// gives the `fr` track the leftover afterwards, so the `auto` track
// stays exactly where it sits with no spanning item at all.
Box flexed = spanGrid('auto 1fr', '',
    PROBES + '<div style="grid-column:1/3">' + SPAN20 + '</div>')
Box flexCtl = spanGrid('auto 1fr', '', PROBES)
checkEqInt(findById(flexed, 'c1').w, findById(flexCtl, 'c1').w,
           'spanning a flexible track grows no base size')

// Two spans overlapping one track. This is the case a sequential loop
// cannot produce: the first item needs ten Ws over tracks 1-2 and the
// second fifteen over 2-3, and growing for one and then the other gives
// the wrong answer whichever order it runs in. Each track takes the
// maximum of what the two items planned for it against the original
// sizes, so track 1 gets half of the first item and tracks 2 and 3 half
// of the second -- which leaves the first item's pair wider than it
// asked for.
Box loneA = layoutHtml(head + '<div id="w" style="float:left">' + SPAN10
                       + '</div></body>', 800)
Box loneB = layoutHtml(head + '<div id="w" style="float:left">' + SPAN15
                       + '</div></body>', 800)
int span10W = findById(loneA, 'w').w
int span15W = findById(loneB, 'w').w
check(span15W > span10W, 'the second spanning item is the wider of the two')

Box over = spanGrid('auto auto auto', '',
    PROBES3
    + '<div style="grid-row:2;grid-column:1/3">' + SPAN10 + '</div>'
    + '<div style="grid-row:3;grid-column:2/4">' + SPAN15 + '</div>')
Box o1 = findById(over, 'c1')
Box o2 = findById(over, 'c2')
Box o3 = findById(over, 'c3')
checkEqInt(o3.w, o2.w, 'the wider span leaves its two tracks equal')
checkEqInt(o2.w + o3.w, span15W, 'and they hold the wider item exactly')
checkEqInt(o1.w, Math.floorDiv(span10W, 2),
           'the first track takes half of the narrower item, not what is left of it')
check(o1.w + o2.w > span10W,
      'so the narrower item ends up with more room than it asked for')

// Grid 1 §8.5 step 1: every item with a definite row *and* column takes
// its cells before any auto-placed item is positioned, whatever the
// order they are written in. Marking them as the placement loop reaches
// them lets an auto item earlier in the document take a cell a later
// item had named -- measured against Chromium, which puts the second
// auto item in row 2 either way.
text CLAIMED = '<div id="s" style="grid-row:1/3;grid-column:2;height:200px">t</div>'
text AUTOS = '<div id="c1">x</div><div id="c2">x</div>'

Box claimLast = layoutHtml(head
    + '<div style="display:grid;grid-template-columns:auto auto;width:400px;'
    + 'justify-content:start">' + AUTOS + CLAIMED + '</div></body>', 800)
Box claimFirst = layoutHtml(head
    + '<div style="display:grid;grid-template-columns:auto auto;width:400px;'
    + 'justify-content:start">' + CLAIMED + AUTOS + '</div></body>', 800)
checkEqInt(findById(claimLast, 'c1').x, 0, 'the first auto item takes the first column')
checkEqInt(findById(claimLast, 'c2').x, 0,
           'and the second goes under it, not into the cell the span named')
check(findById(claimLast, 'c2').y > 0, 'which is the row below')
checkEqInt(findById(claimFirst, 'c2').x, findById(claimLast, 'c2').x,
           'and where the claim is written makes no difference')
checkEqInt(findById(claimFirst, 'c2').y, findById(claimLast, 'c2').y,
           'in either axis')

// The block axis answers the same way: a 200px item spanning two auto
// rows makes them 100 apiece, a declared row keeps its length and the
// spanned rows take what is left, and a row outside the span is
// untouched. Measured against Chromium with the same fixtures.
Box func spanRows(rows:text, items:text) {
    return layoutHtml(head
        + '<div id="g" style="display:grid;grid-template-columns:auto auto;'
        + 'width:400px;align-content:start;justify-content:start;'
        + 'grid-template-rows:' + rows + '">' + items + '</div></body>', 800)
}

text TALL = '<div id="s" style="grid-row:1/3;grid-column:2;height:200px">t</div>'

Box rowSpan = spanRows('auto auto',
    '<div id="c1">x</div><div id="c2">x</div>' + TALL)
Box rs1 = findById(rowSpan, 'c1')
checkEqInt(findById(rowSpan, 's').h, 200, 'the spanning item keeps its declared height')
checkEqInt(rs1.h, 100, 'and the two rows it spans take half of it each')
checkEqInt(findById(rowSpan, 'g').h, 200, 'so the grid is exactly as tall as the item')

Box rowFixed = spanRows('60px auto',
    '<div id="c1">x</div><div id="c2">x</div>' + TALL)
checkEqInt(findById(rowFixed, 'c1').h, 60, 'a declared row keeps its height')
checkEqInt(findById(rowFixed, 'g').h, 200, 'and the automatic one absorbs the rest')

Box rowOutside = spanRows('auto auto auto',
    '<div id="c1">x</div><div id="c2">x</div><div id="c3" style="grid-row:3">x</div>' + TALL)
checkEqInt(findById(rowOutside, 'c1').h, 100, 'the spanned rows share equally')
checkEqInt(findById(rowOutside, 'c3').h, 20,
           'and the row outside the span keeps its one line')

// ---- Grid 1 §8.3: a name the template does not know -------------------
// "If not enough lines with that name exist, all implicit grid lines
// are assumed to have that name for the purpose of finding this
// position." Every check here asserts that the named placement lands
// exactly where the numbered one does, rather than at a pixel worked
// out here: the explicit grid has lines 1, 2 and 3, so a name nothing
// declares is line 4, and `grid-column: 4` is the same placement said
// another way.

Box func namedGrid(cols:text, items:text) {
    return layoutHtml(head
        + '<div style="display:grid;width:400px;grid-template-rows:50px 50px;'
        + 'grid-template-columns:' + cols + '">' + items + '</div></body>', 800)
}

void func sameAs(named:text, numbered:text, cols:text, before:text, what:text) {
    Box a = namedGrid(cols, before + '<div id="i" style="' + named + '">t</div>')
    Box b = namedGrid(cols, before + '<div id="i" style="' + numbered + '">t</div>')
    Box ia = findById(a, 'i')
    Box ib = findById(b, 'i')
    checkEqInt(ia.x, ib.x, what)
    checkEqInt(ia.w, ib.w, what + ', and is as wide')
    checkEqInt(ia.y, ib.y, what + ', on the other axis too')
    checkEqInt(ia.h, ib.h, what + ', and as tall')
}

text TWOCOLS = '100px 100px'

sameAs('grid-column:zz;grid-row:1', 'grid-column:4;grid-row:1', TWOCOLS, '',
       'an unknown name is the first line after the explicit grid')
sameAs('grid-column:zz / zz;grid-row:1', 'grid-column:4;grid-row:1', TWOCOLS, '',
       'the same name on both edges spans one track')
sameAs('grid-column:zz / span 2;grid-row:1', 'grid-column:4 / span 2;grid-row:1',
       TWOCOLS, '', 'and a span from it runs on from there')
sameAs('grid-column:1 / zz;grid-row:1', 'grid-column:1 / 4;grid-row:1', TWOCOLS, '',
       'an unknown name on the end edge reaches the same line')
sameAs('grid-row:zz;grid-column:1', 'grid-row:4;grid-column:1', TWOCOLS, '',
       'and the row axis answers the same way')
sameAs('grid-area:zz', 'grid-row:4;grid-column:4', TWOCOLS, '',
       'grid-area names both axes at once')

// A name that exists, but not often enough: the shortfall comes from
// the implicit lines, so `aa 2` against one `aa` is line 4 as well.
sameAs('grid-column:aa 2;grid-row:1', 'grid-column:4;grid-row:1', '[aa] 100px 100px', '',
       'a name short by one takes the shortfall from the implicit lines')
sameAs('grid-column:aa 3;grid-row:1', 'grid-column:4;grid-row:1', '[aa] 100px [aa] 100px', '',
       'and short by one of two is the same line')
// A count the template does satisfy still means what it says.
sameAs('grid-column:aa 2;grid-row:1', 'grid-column:2;grid-row:1', '[aa] 100px [aa] 100px', '',
       'a count the template can meet is the line it names')

// The count is against the explicit grid, not the grid as it stands: an
// item forcing tracks 3 to 5 into being does not move where `zz` is.
sameAs('grid-column:zz;grid-row:2', 'grid-column:4;grid-row:2', TWOCOLS,
       '<div style="grid-column:5;grid-row:1">o</div>',
       'implicit tracks already made do not move an unknown name')

finish('grid')