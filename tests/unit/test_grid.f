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

finish('grid')
