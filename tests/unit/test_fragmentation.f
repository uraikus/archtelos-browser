// Where a multi-column container is allowed to break: CSS Fragmentation
// 3's `break-before`, `break-after` and `break-inside`, and CSS2's
// `orphans` and `widows`.
//
// Every expected position is Chromium 141's, read off these same
// fixtures with getBoundingClientRect before any of this was written --
// each line wrapped in a span of its own, so which column a line landed
// in is Chromium's answer and not an inference from a height. A forced
// or forbidden break unbalances the columns, and the container's height
// is the tallest column, which is how both engines report it.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func fragLayout(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, width)
}

Box func fragFind(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = fragFind(b.children[i], id)
        if f != null { return f }
    }
    return null
}

text fragHead = '<body style="margin:0;font:16px/20px monospace">'
text fragOpen = '<div id="c" style="width:300px;column-gap:0;column-count:2">'

// Six 30px blocks: two columns of three is the balanced answer, so any
// departure from it is a break one of these properties asked for.
Box func blocksWith(at:int, extra:text) {
    text out = ''
    for int i = 0, i < 6, i++ {
        text style = 'height:30px'
        if i == at { style = style + extra }
        out = out + '<div id="b' + i.toText() + '" style="' + style + '"></div>'
    }
    return fragLayout(fragHead + fragOpen + out + '</div></body>', 400)
}

// A run of lines in one child, which is what orphans and widows are
// about. No trailing <br>, so the child has exactly n line boxes.
Box func linesWith(n:int, extra:text) {
    text lines = ''
    for int i = 0, i < n, i++ {
        if i > 0 { lines = lines + '<br>' }
        lines = lines + 'xxxx'
    }
    return fragLayout(fragHead + fragOpen + '<div id="p" style="margin:0;' + extra + '">'
        + lines + '</div></div></body>', 400)
}

// How many of a child's lines landed in the first column. The columns
// are 150px wide with no gap, so the second starts at 150.
int func linesInFirstColumn(root:Box, n:int) {
    Box lineHost = fragFind(root, 'p')
    int count = 0
    int seen = 0
    for int i = 0, i < lineHost.lines.length, i++ {
        if lineHost.lines[i].frags.length == 0 { continue }
        seen++
        if lineHost.lines[i].frags[0].x < 150 { count++ }
    }
    if seen != n {
        checksFailed++
        log(`FAIL: the fixture has ${seen} lines with content, not ${n}`)
    }
    return count
}

// ---- the controls --------------------------------------------------------

Box plain = blocksWith(-1, '')
checkEqInt(fragFind(plain, 'c').h, 90, 'six 30px blocks balance into two columns of 90')
checkEqInt(fragFind(plain, 'b2').x, 0, 'the third block is in the first column')
checkEqInt(fragFind(plain, 'b3').x, 150, 'and the fourth starts the second')

Box six = linesWith(6, '')
checkEqInt(fragFind(six, 'c').h, 60, 'six lines balance into two columns of three')
checkEqInt(linesInFirstColumn(six, 6), 3, 'three lines in the first column')

Box five = linesWith(5, '')
checkEqInt(linesInFirstColumn(five, 5), 3, 'five lines split three and two')
checkEqInt(fragFind(five, 'c').h, 60, 'so the first column is the taller one')

// ---- break-before: column ------------------------------------------------
// A forced break wins over balancing: the columns come out unequal and
// the container is as tall as the taller one.

Box beforeCol = blocksWith(2, ';break-before:column')
checkEqInt(fragFind(beforeCol, 'b2').x, 150, 'break-before:column starts a new column')
checkEqInt(fragFind(beforeCol, 'b2').y, 0, 'at its top')
checkEqInt(fragFind(beforeCol, 'b1').x, 0, 'leaving two blocks in the first')
checkEqInt(fragFind(beforeCol, 'c').h, 120, 'and the container as tall as the taller column')

// `page` and `always` break a page, not a column, so in a column
// container they do nothing. A test that asserted otherwise would pass
// for an implementation that forced a break on any keyword at all.
Box beforePage = blocksWith(2, ';break-before:page')
checkEqInt(fragFind(beforePage, 'c').h, 90, 'break-before:page does not break a column')
checkEqInt(fragFind(beforePage, 'b2').x, 0, 'and leaves the third block where it was')

// ---- break-after: column -------------------------------------------------
// The same break said from the other side must lay out identically.
// This is the check that does not depend on either answer being known
// in advance: break-after on one child and break-before on the next are
// two ways of saying one thing.

Box afterCol = blocksWith(1, ';break-after:column')
checkEqInt(fragFind(afterCol, 'b2').x, fragFind(beforeCol, 'b2').x,
           'break-after:column puts the next child where break-before does')
checkEqInt(fragFind(afterCol, 'b2').y, fragFind(beforeCol, 'b2').y, 'at the same height')
checkEqInt(fragFind(afterCol, 'c').h, fragFind(beforeCol, 'c').h,
           'and gives the container the same height')

// ---- break-inside: avoid -------------------------------------------------
// A child that may not be broken moves whole, so six lines that would
// have been split three and three stay together.

Box avoidInside = linesWith(6, 'break-inside:avoid')
checkEqInt(linesInFirstColumn(avoidInside, 6), 6,
           'break-inside:avoid keeps all six lines in one column')
checkEqInt(fragFind(avoidInside, 'c').h, 120, 'so the container is six lines tall')
checkEqInt(fragFind(avoidInside, 'p').w, 150, 'and the child is one column wide')

// ---- break-before: avoid -------------------------------------------------
// The break cannot happen before this child, so it happens after it:
// four blocks in the first column and two in the second.

Box avoidBefore = blocksWith(3, ';break-before:avoid')
checkEqInt(fragFind(avoidBefore, 'b3').x, 0, 'break-before:avoid keeps a child in its column')
checkEqInt(fragFind(avoidBefore, 'b4').x, 150, 'and the break goes after it')
checkEqInt(fragFind(avoidBefore, 'c').h, 120, 'leaving the first column taller')

// break-after: avoid on the child before says the same thing.
Box avoidAfter = blocksWith(2, ';break-after:avoid')
checkEqInt(fragFind(avoidAfter, 'b3').x, fragFind(avoidBefore, 'b3').x,
           'break-after:avoid forbids the same break')
checkEqInt(fragFind(avoidAfter, 'c').h, fragFind(avoidBefore, 'c').h,
           'and leaves the container the same height')

// `avoid-column` is the same instruction, named for the context.
Box avoidColumn = blocksWith(3, ';break-before:avoid-column')
checkEqInt(fragFind(avoidColumn, 'b4').x, fragFind(avoidBefore, 'b4').x,
           'break-before:avoid-column forbids a column break as avoid does')

// ---- orphans -------------------------------------------------------------
// The fewest lines that may be left at the foot of a column. Four of six
// pushes the break one line later than balance would put it.

Box orphans4 = linesWith(6, 'orphans:4;widows:1')
checkEqInt(linesInFirstColumn(orphans4, 6), 4,
           'orphans:4 leaves four lines at the foot of the first column')
checkEqInt(fragFind(orphans4, 'c').h, 80, 'making the first column the taller one')

// ---- widows --------------------------------------------------------------
// The fewest at the head of the next column, which moves the break the
// other way -- earlier, where orphans moved it later. A rule that only
// ever searched forward would pass the orphans check and fail this one.

Box widows4 = linesWith(6, 'orphans:1;widows:4')
checkEqInt(linesInFirstColumn(widows4, 6), 2,
           'widows:4 moves the break earlier, to leave four lines at the head')
checkEqInt(fragFind(widows4, 'c').h, 80, 'making the second column the taller one')

// Both at three is satisfied by the balanced split, so nothing moves.
Box threeThree = linesWith(6, 'orphans:3;widows:3')
checkEqInt(linesInFirstColumn(threeThree, 6), 3, 'orphans and widows of three still split evenly')

// ---- when they cannot both be honoured -----------------------------------
// Five and five of six lines is impossible. The standard says such a
// value is ignored rather than making the content unbreakable, and what
// gives way is widows: five lines stay at the foot and one goes over.

Box impossible = linesWith(6, 'orphans:5;widows:5')
checkEqInt(linesInFirstColumn(impossible, 6), 5, 'an impossible pair keeps orphans and drops widows')
checkEqInt(fragFind(impossible, 'c').h, 100, 'so the first column holds five of the six lines')

// The initial values are 2 and 2, and three lines cannot honour both.
Box three = linesWith(3, '')
checkEqInt(linesInFirstColumn(three, 3), 2, 'three lines split two and one under the initial 2 and 2')
checkEqInt(fragFind(three, 'c').h, 40, 'the first column being the taller')

// ---- what the feature costs the pages that do not use it -----------------
// None of this may change a document with no multi-column container in
// it, whatever these properties say.

Box notColumns = fragLayout(fragHead
    + '<div id="c" style="width:300px"><div id="b0" style="height:30px;break-before:column;'
    + 'break-inside:avoid;orphans:4;widows:4"></div>'
    + '<div id="b1" style="height:30px"></div></div></body>', 400)
checkEqInt(fragFind(notColumns, 'c').h, 60, 'outside a fragmented context the properties do nothing')
checkEqInt(fragFind(notColumns, 'b1').y, 30, 'and the blocks stack as they always did')
checkEqInt(fragFind(notColumns, 'b0').w, 300, 'at the full width')

finish('fragmentation')
