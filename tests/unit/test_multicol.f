// CSS Multi-column 1.
//
// A multi-column container lays its content out once at the column
// width and then breaks that single flow into columns of equal height.
// So the checks are about two things a single flow cannot show: that
// the content is narrower than the container, and that what did not
// fit in the first column appears beside it rather than below.
//
// Breaking happens between the container's direct children and between
// the line boxes of a child that holds lines. Nothing deeper is broken,
// which css-2026.md records.
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

// Six 30px blocks in a 300px container, however many columns are asked
// for. Six blocks divide evenly by two and by three, so a balanced
// height is exact and the checks can be exact with it.
text blocks = ''
for int i = 0, i < 6, i++ {
    blocks = blocks + '<div id="b' + i.toText() + '" style="height:30px"></div>'
}

Box func colsOf(style:text) {
    return layoutHtml(head + '<div id="c" style="width:300px;' + style + '">'
        + blocks + '</div></body>', 400)
}

// ---- the control ---------------------------------------------------------

Box plain = colsOf('')
checkEqInt(findById(plain, 'c').h, 180, 'six 30px blocks stack to 180px')
checkEqInt(findById(plain, 'b3').y, 90, 'and the fourth starts at 90')
checkEqInt(findById(plain, 'b0').w, 300, 'each filling the container')

// ---- column-count --------------------------------------------------------

Box two = colsOf('column-count:2')
checkEqInt(findById(two, 'c').h, 90, 'two columns halve the height')
checkEqInt(findById(two, 'b0').w, 150, 'and halve the width of what is in them')
checkEqInt(findById(two, 'b0').x, 0, 'the first block is in the first column')
checkEqInt(findById(two, 'b0').y, 0, 'at the top')
checkEqInt(findById(two, 'b2').y, 60, 'the third is still in the first column')
checkEqInt(findById(two, 'b2').x, 0, 'which has room for three')
checkEqInt(findById(two, 'b3').x, 150, 'the fourth starts the second column')
checkEqInt(findById(two, 'b3').y, 0, 'back at the top')

Box three = colsOf('column-count:3')
checkEqInt(findById(three, 'c').h, 60, 'three columns take a third of the height')
checkEqInt(findById(three, 'b2').x, 100, 'and the third block starts the second column')
checkEqInt(findById(three, 'b4').x, 200, 'the fifth the third column')

// ---- column-width --------------------------------------------------------
// A width asks for as many columns of at least that width as fit.

Box byWidth = colsOf('column-width:100px')
checkEqInt(findById(byWidth, 'b0').w, 100, 'column-width gives three columns of 100 in 300')
checkEqInt(findById(byWidth, 'b2').x, 100, 'and fills them in turn')

// Both together: the count is a maximum.
Box both = colsOf('column-width:100px;column-count:2')
checkEqInt(findById(both, 'b0').w, 150, 'a count beside a width caps the number of columns')

// ---- column-gap ----------------------------------------------------------

Box gapped = colsOf('column-count:2;column-gap:20px')
checkEqInt(findById(gapped, 'b0').w, 140, 'the gap comes out of the columns')
checkEqInt(findById(gapped, 'b3').x, 160, 'and separates them')

// ---- breaking between the lines of one child -----------------------------
// The common case is one long run of text, whose lines are all in one
// child. Breaking only between children would leave it in column one.

text manyLines = ''
for int i = 0, i < 6, i++ {
    manyLines = manyLines + 'xxxx<br>'
}
Box lines2 = layoutHtml(head + '<div id="c" style="width:300px;column-count:2">'
    + '<div id="p" style="margin:0">' + manyLines + '</div></div></body>', 400)
Box pBox = findById(lines2, 'p')
check(pBox.lines.length >= 6, 'the fixture has at least six lines')
int firstColLines = 0
int secondColLines = 0
for int i = 0, i < pBox.lines.length, i++ {
    if pBox.lines[i].frags.length == 0 { continue }
    if pBox.lines[i].frags[0].x < 150 { firstColLines++ } else { secondColLines++ }
}
check(firstColLines > 0, 'some lines are in the first column')
check(secondColLines > 0, 'and some in the second -- a long run is broken between its lines')

// ---- column-rule ---------------------------------------------------------
// The rule is a line in the gap, so it needs a gap to be in. It takes
// no space of its own, which is what separates it from a border.

Box ruled = colsOf('column-count:2;column-gap:20px;column-rule:4px solid red')
checkEqInt(findById(ruled, 'b0').w, 140, 'a column rule takes no space of its own')
checkEqInt(findById(ruled, 'b3').x, 160, 'and does not move the columns')

// The longhands say what the shorthand says.
Box ruledLong = colsOf('column-count:2;column-gap:20px;column-rule-width:4px;'
    + 'column-rule-style:solid;column-rule-color:red')
checkEqInt(findById(ruledLong, 'b0').w, findById(ruled, 'b0').w,
           'the column-rule longhands lay out as the shorthand does')

// ---- what a single column does -------------------------------------------
// column-count: 1 is a multi-column container with one column, which
// must be indistinguishable from no columns at all.

Box one = colsOf('column-count:1')
checkEqInt(findById(one, 'c').h, findById(plain, 'c').h, 'one column is as tall as no columns')
checkEqInt(findById(one, 'b3').y, findById(plain, 'b3').y, 'and lays out the same way')
checkEqInt(findById(one, 'b0').w, findById(plain, 'b0').w, 'at the same width')

// ---- column-span: all ----------------------------------------------------
// A spanner splits the container: what is before it is columnised, the
// spanner itself is laid out across every column, and what follows
// starts fresh columns under it.
//
// The expected geometry is Chromium 141's, on fixtures whose sections
// divide evenly into two columns -- Chromium will split a block across
// a column boundary to balance and this engine will not, so a section
// with an odd number of blocks is a difference about fragmentation
// rather than about spanning.

Box func spanColumns(n:int, at:int) {
    text out = ''
    for int i = 0, i < n, i++ {
        text style = 'height:30px'
        if i == at { style = style + ';column-span:all' }
        out = out + '<div id="b' + i.toText() + '" style="' + style + '"></div>'
    }
    return layoutHtml(head + '<div id="c" style="width:300px;column-gap:0;column-count:2">'
        + out + '</div></body>', 400)
}

// Two blocks, a spanner, four blocks.
Box spanMid = spanColumns(7, 2)
checkEqInt(findById(spanMid, 'b0').x, 0, 'the block before a spanner is in the first column')
checkEqInt(findById(spanMid, 'b1').x, 150, 'and the next in the second')
checkEqInt(findById(spanMid, 'b2').x, 0, 'the spanner starts at the container edge')
checkEqInt(findById(spanMid, 'b2').y, 30, 'below the columns before it')
checkEqInt(findById(spanMid, 'b2').w, 300, 'and is as wide as every column together')
checkEqInt(findById(spanMid, 'b3').x, 0, 'what follows starts a fresh first column')
checkEqInt(findById(spanMid, 'b3').y, 60, 'under the spanner')
checkEqInt(findById(spanMid, 'b4').y, 90, 'with room for two blocks in it')
checkEqInt(findById(spanMid, 'b5').x, 150, 'and two in the second')
checkEqInt(findById(spanMid, 'b5').y, 60, 'starting at the same height')
checkEqInt(findById(spanMid, 'c').h, 120, 'the container is the three sections stacked')

// A spanner first, with nothing above it.
Box spanFirst = spanColumns(5, 0)
checkEqInt(findById(spanFirst, 'b0').y, 0, 'a spanner first starts at the top')
checkEqInt(findById(spanFirst, 'b0').w, 300, 'at the full width')
checkEqInt(findById(spanFirst, 'b1').y, 30, 'and the columns begin below it')
checkEqInt(findById(spanFirst, 'b3').x, 150, 'balanced two and two')
checkEqInt(findById(spanFirst, 'c').h, 90, 'so the container is a spanner and two rows')

// A spanner last, with nothing below it.
Box spanLast = spanColumns(5, 4)
checkEqInt(findById(spanLast, 'b2').x, 150, 'four blocks above a spanner balance two and two')
checkEqInt(findById(spanLast, 'b4').y, 60, 'and the spanner goes under them')
checkEqInt(findById(spanLast, 'b4').w, 300, 'across every column')
checkEqInt(findById(spanLast, 'c').h, 90, 'making the container ninety tall')

// `column-span: none` is the initial value, so it must lay out exactly
// as no declaration does -- a check that fails for an implementation
// that treats any value of the property as a spanner.
text noneOut = ''
for int i = 0, i < 6, i++ {
    text st = 'height:30px'
    if i == 2 { st = st + ';column-span:none' }
    noneOut = noneOut + '<div id="b' + i.toText() + '" style="' + st + '"></div>'
}
Box spanNone = layoutHtml(head + '<div id="c" style="width:300px;column-gap:0;column-count:2">'
    + noneOut + '</div></body>', 400)
Box plainTwo = layoutHtml(head + '<div id="c" style="width:300px;column-gap:0;column-count:2">'
    + blocks + '</div></body>', 400)
checkEqInt(findById(spanNone, 'c').h, findById(plainTwo, 'c').h,
           'column-span:none lays out as no column-span does')
checkEqInt(findById(spanNone, 'b3').x, findById(plainTwo, 'b3').x, 'with the same columns')

// A spanner outside a multi-column container is an ordinary block.
Box spanNoColumns = layoutHtml(head + '<div id="c" style="width:300px">'
    + '<div id="b0" style="height:30px;column-span:all"></div>'
    + '<div id="b1" style="height:30px"></div></div></body>', 400)
checkEqInt(findById(spanNoColumns, 'b1').y, 30, 'outside a column container a spanner is a block')
checkEqInt(findById(spanNoColumns, 'b0').w, 300, 'at the width it would have had anyway')

// ---- column-fill (Multi-column 1 §3.3) --------------------------------
// `balance` is the initial value and makes the columns as equal as it
// can. `auto` fills each column to the container's height before
// starting the next -- so with no height to fill to, everything stays
// in the first column and the container grows instead.
//
// Chromium 141 on twelve 20px blocks in a 300px, three-column container
// with no declared height: balance puts four in each column and the
// container is 80 tall; `auto` puts all twelve in the first column and
// the container is 240. With `height: 80px` the two agree exactly,
// which is the check that this does not simply turn balancing off.

text cfItems = ''
for int i = 0, i < 12, i++ {
    cfItems = cfItems + `<div id="f${i}" style="height:20px"></div>`
}

Box cfBalance = layoutHtml(head + `<div id="c" style="width:300px;column-count:3;column-gap:0">`
    + cfItems + '</div></body>', 400)
checkEqInt(findById(cfBalance, 'c').h, 80, 'balancing makes three columns of four')
checkEqInt(findById(cfBalance, 'f4').x, 100, 'the fifth block starts the second column')
checkEqInt(findById(cfBalance, 'f4').y, 0, 'at the top of it')

Box cfAuto = layoutHtml(head + `<div id="c" style="width:300px;column-count:3;column-gap:0;column-fill:auto">`
    + cfItems + '</div></body>', 400)
checkEqInt(findById(cfAuto, 'c').h, 240, 'with nothing to fill to, `auto` uses one column')
checkEqInt(findById(cfAuto, 'f4').x, 0, 'so the fifth block is still in the first column')
checkEqInt(findById(cfAuto, 'f4').y, 80, 'below the four before it')
check(findById(cfAuto, 'c').h != findById(cfBalance, 'c').h,
      'which is not what balancing does')

// Given a height to fill, the two agree *here* -- but only because this
// fixture's balanced height happens to equal the container's: twelve 20px
// blocks over three columns balance to exactly 80, which is the height
// declared. They do not agree in general, which the checks below are for.
Box cfAutoH = layoutHtml(head + `<div id="c" style="width:300px;column-count:3;column-gap:0;column-fill:auto;height:80px">`
    + cfItems + '</div></body>', 400)
Box cfBalanceH = layoutHtml(head + `<div id="c" style="width:300px;column-count:3;column-gap:0;height:80px">`
    + cfItems + '</div></body>', 400)
checkEqInt(findById(cfAutoH, 'f4').x, findById(cfBalanceH, 'f4').x,
           'with a height to fill, `auto` and `balance` put the fifth block in one place')
checkEqInt(findById(cfAutoH, 'f4').y, findById(cfBalanceH, 'f4').y, 'at one height')

// `column-fill: auto` fills each column to the container's OWN block size
// and starts the next only when that is full, so a container taller than
// the balanced share keeps more in the first column. todo.md has
// Chromium's rows; the check that earns its place is the agreement that
// follows from the rule -- the blocks land where ONE column of the same
// height puts them, for as long as they fit in it.
text cfTwo = '<div id="a" style="height:20px"></div><div id="b" style="height:30px"></div>'
text cfThree = '<div id="a" style="height:20px"></div><div id="b" style="height:20px"></div>'
    + '<div id="d" style="height:20px"></div>'

Box cfFill = layoutHtml(head
    + '<div id="c" style="width:100px;column-count:2;column-gap:10px;column-fill:auto;height:60px">'
    + cfTwo + '</div></body>', 400)
Box cfOne = layoutHtml(head
    + '<div id="c" style="width:100px;column-count:1;column-fill:auto;height:60px">'
    + cfTwo + '</div></body>', 400)
checkEqInt(findById(cfFill, 'a').y, findById(cfOne, 'a').y,
           'filling to the container height puts the first block where one column would')
checkEqInt(findById(cfFill, 'b').y, findById(cfOne, 'b').y, 'and the second below it')
checkEqInt(findById(cfFill, 'b').x, findById(cfFill, 'a').x,
           'both being in the first column, which had room for them')

// It does break, once the column really is full: three 20s in 40 leave
// the third for the second column.
Box cfFull = layoutHtml(head
    + '<div id="c" style="width:100px;column-count:2;column-gap:10px;column-fill:auto;height:40px">'
    + cfThree + '</div></body>', 400)
checkEqInt(findById(cfFull, 'b').x, findById(cfFull, 'a').x, 'two 20s fit a column of 40')
check(findById(cfFull, 'd').x > findById(cfFull, 'a').x, 'and the third starts the next column')
checkEqInt(findById(cfFull, 'd').y, findById(cfFull, 'a').y, 'at the top of it')

// The instrument: `balance` at the same height must put them elsewhere,
// or these checks would hold on an engine that ignored `column-fill`.
Box cfBal = layoutHtml(head
    + '<div id="c" style="width:100px;column-count:2;column-gap:10px;height:60px">'
    + cfTwo + '</div></body>', 400)
check(findById(cfBal, 'b').x != findById(cfFill, 'b').x,
      'balancing at that height really does put the second block elsewhere')

finish('multicol')
