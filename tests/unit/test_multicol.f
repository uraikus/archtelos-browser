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

finish('multicol')
