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

// ---- auto tracks take their size from the content ------------------------

Box gAuto = gridOf('grid-template-columns:auto 100px',
                   gridCell('a', 'width:40px') + gridCell('b', ''))
checkEqInt(findById(gAuto, 'a').w, 40, 'an auto track is as wide as its content')

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

finish('grid')
