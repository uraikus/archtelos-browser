import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func layoutHtml(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box root = layoutDocument(doc, width)
    return root
}

Box func findBox(b:Box, tag:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node.tag == tag { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findBox(b.children[i], tag)
        if f != null { return f }
    }
    return null
}

// block stacking, body margin, margin collapsing
Box r1 = layoutHtml('<body><div style="height:10px;background:red"></div><p style="margin:20px 0;height:5px">x</p><div style="margin-top:30px;height:7px"></div></body>', 400)
Box body1 = findBox(r1, 'body')
checkEqInt(body1.x, 8, 'body x = 8px margin')
checkEqInt(body1.w, 384, 'body fills viewport minus margins')
Box div1 = findBox(r1, 'div')
checkEqInt(div1.y, 8, 'first div at body top')
checkEqInt(div1.h, 10, 'explicit height')
Box p1 = findBox(r1, 'p')
checkEqInt(p1.y, 38, 'p top: 10 + 20 margin')
Box lastDiv = body1.children[2]
checkEqInt(lastDiv.y, 73, 'sibling margins collapse to max(20,30)')
checkEqInt(body1.h, 72, 'body height excludes collapsed last margin')
checkEqInt(r1.h, 88, 'html height includes body margins')

// inline layout: wrapping, line height, text-align
Style s16
font base = '16px sans-serif'
changeFont(base)
int wHello = measureTextWidth('Hello')
int wWorld = measureTextWidth('world')
int wSpace = measureTextWidth(' ')
Box r2 = layoutHtml('<body style="margin:0"><p style="margin:0;width:100px">Hello world Hello</p></body>', 400)
Box p2 = findBox(r2, 'p')
checkEqInt(p2.lines.length, 2, 'two lines when three words exceed 100px')
checkEq(p2.lines[0].frags[0].content, 'Hello world', 'words merged into one run')
checkEqInt(p2.lines[0].frags[0].w, wHello + wSpace + wWorld, 'run width = words + space')
checkEqInt(p2.lines[0].h, 19, 'normal line height 1.2 * 16 rounded')
checkEqInt(p2.h, 38, 'paragraph height = two lines')
checkEqInt(p2.lines[0].baseline, 15, 'baseline inside first line')

Box r3 = layoutHtml('<body style="margin:0"><p style="margin:0;text-align:center;width:200px">Hi</p><p style="margin:0;text-align:right;width:200px">Hi</p></body>', 400)
int wHi = measureTextWidth('Hi')
Box pc = r3.children[0].children[0]
checkEqInt(pc.lines[0].frags[0].x, Math.floorDiv(200 - wHi, 2), 'text-align center')
Box pr = r3.children[0].children[1]
checkEqInt(pr.lines[0].frags[0].x, 200 - wHi, 'text-align right')

// inline element edges and whitespace across inline boundaries
Box r4 = layoutHtml('<body style="margin:0"><p style="margin:0">Hello <b style="padding:0 4px">world</b>!</p></body>', 400)
Box p4 = findBox(r4, 'p')
Line l4 = p4.lines[0]
checkEqInt(l4.frags.length, 4, 'text, span background, text, text fragments')
checkEq(l4.frags[2].content, 'world', 'bold run')
checkEqInt(l4.frags[2].x, wHello + wSpace + 4, 'space collapsed across inline boundary plus padding')
changeFont(16, 'bold', 'sans-serif')
int wWorldBold = measureTextWidth('world')
checkEqInt(l4.frags[3].x, wHello + wSpace + 4 + wWorldBold + 4, 'no space before !')
checkEqInt(l4.frags[1].w, 4 + wWorldBold + 4, 'inline background spans padding and content')

// anonymous blocks around mixed content
Box r5 = layoutHtml('<body style="margin:0">text<div style="height:10px"></div>more</body>', 400)
Box body5 = findBox(r5, 'body')
checkEqInt(body5.children.length, 3, 'anon, div, anon')
checkEqInt(body5.children[0].kind, BOX_ANON, 'first child anonymous')
checkEqInt(body5.children[1].y, 19, 'div after one line of text')

// inline-block shrink-to-fit and images
Box r6 = layoutHtml('<body style="margin:0"><span style="display:inline-block;padding:2px;border:1px solid">Hi</span><img width="20" height="10"></body>', 400)
Box span6 = findBox(r6, 'span')
checkEqInt(span6.w, wHi + 6, 'inline-block shrinks to content plus edges')
checkEqInt(span6.h, 19 + 6, 'inline-block height')
Box img6 = findBox(r6, 'img')
checkEqInt(img6.w, 20, 'img width attr')
checkEqInt(img6.h, 10, 'img height attr')
checkEqInt(img6.x, span6.w, 'image follows inline-block on the line')
Line l6 = findBox(r6, 'body').lines[0]
checkEqInt(l6.h, 25, 'line grows to the tallest atomic box')

// lists
Box r7 = layoutHtml('<body style="margin:0"><ul style="margin:0"><li>a</li><li value="5">b</li><li>c</li></ul></body>', 400)
Box ul7 = findBox(r7, 'ul')
checkEqInt(ul7.children[0].x, 40, 'li indented by ul padding')
check(ul7.children[0].isListItem, 'li is a list item')
checkEqInt(ul7.children[2].listIndex, 6, 'li value attr renumbers')

// tables
Box r8 = layoutHtml('<body style="margin:0"><table style="border-spacing:0"><tr><td style="padding:0">ab</td><td style="padding:0;width:50px">c</td></tr><tr><td style="padding:0" colspan="2">x</td></tr></table></body>', 400)
Box t8 = findBox(r8, 'table')
changeFont(16, 'normal', 'sans-serif')
int wAb = measureTextWidth('ab')
checkEqInt(t8.w, wAb + 50, 'table width = content column + fixed column')
Box row2 = t8.children[1]
checkEqInt(row2.children[0].w, wAb + 50, 'colspan cell spans both columns')
checkEqInt(t8.h, 38, 'two rows of one line each')
Box r9 = layoutHtml('<body style="margin:0"><table style="width:300px;border-spacing:0"><tr><td style="padding:0">a</td><td style="padding:0">b</td></tr></table></body>', 400)
Box t9 = findBox(r9, 'table')
checkEqInt(t9.w, 300, 'fixed table width')
checkEqInt(t9.children[0].children[0].w + t9.children[0].children[1].w, 300, 'columns share the fixed width')

// pre
Box r10 = layoutHtml('<body style="margin:0"><pre style="margin:0">a  b\nc</pre></body>', 400)
Box pre10 = findBox(r10, 'pre')
checkEqInt(pre10.lines.length, 2, 'pre newline breaks a line')
checkEq(pre10.lines[0].frags[0].content, 'a  b', 'pre keeps spaces')

// br
Box r11 = layoutHtml('<body style="margin:0"><p style="margin:0">a<br>b<br></p></body>', 400)
checkEqInt(findBox(r11, 'p').lines.length, 2, 'br breaks; trailing br adds no line')

// width auto margins center
Box r12 = layoutHtml('<body style="margin:0"><div style="width:100px;margin:0 auto;height:1px"></div></body>', 400)
checkEqInt(findBox(r12, 'div').x, 150, 'auto margins center a fixed-width block')

// A space between text and a following inline element is a space.
// Shrink-to-fit width is what shows it: an inline-block sizes itself to
// its content, so a lost space makes the box narrower. Chromium 141
// measures all four of these at 29px -- three characters of 16px
// monospace -- and this engine's own character is 10px, so all four
// must come to the same width whatever that width is.
Box ws1 = layoutHtml('<body style="margin:0;font:16px/20px monospace"><span id="w" style="display:inline-block">A B</span></body>', 600)
Box ws2 = layoutHtml('<body style="margin:0;font:16px/20px monospace"><span id="w" style="display:inline-block">A <em>B</em></span></body>', 600)
Box ws3 = layoutHtml('<body style="margin:0;font:16px/20px monospace"><span id="w" style="display:inline-block"><em>A</em> B</span></body>', 600)
Box ws4 = layoutHtml('<body style="margin:0;font:16px/20px monospace"><span id="w" style="display:inline-block"><em>A</em> <em>B</em></span></body>', 600)
int wsPlain = findBox(ws1, 'span').w
check(wsPlain > 0, `the plain case has a width, got ${wsPlain}`)
checkEqInt(findBox(ws2, 'span').w, wsPlain, 'a space before an inline element is kept')
checkEqInt(findBox(ws3, 'span').w, wsPlain, 'a space after an inline element is kept')
checkEqInt(findBox(ws4, 'span').w, wsPlain, 'a space between two inline elements is kept')

// And it is one space, not two: a text box ending in a space followed
// by one starting with a space still separates them by a single space.
Box ws5 = layoutHtml('<body style="margin:0;font:16px/20px monospace"><span id="w" style="display:inline-block">A <em> B</em></span></body>', 600)
checkEqInt(findBox(ws5, 'span').w, wsPlain, 'two collapsing spaces are still one space')

// ---- table-layout: fixed (CSS2 17.5.2.1) ---------------------------------
// The fixed algorithm takes its column widths from the first row alone
// and ignores every cell's content, which is the whole reason it
// exists: a table can be laid out without measuring what is in it. The
// automatic algorithm widens a column to fit its widest cell.

text twoCol = '<body style="margin:0;font:16px/20px monospace">'
    + '<table style="width:300px;border-spacing:0;TL"><tr><td>a</td><td>b</td></tr>'
    + '<tr><td>aaaaaaaaaaaaaaaaaaaaaaaa</td><td>b</td></tr></table></body>'

Box tAuto = layoutHtml(twoCol.replace(regex('TL', 'g'), ''), 600)
Box tFixed = layoutHtml(twoCol.replace(regex('TL', 'g'), 'table-layout:fixed'), 600)

arr[Box] autoCells = []
collectBoxesForTag(tAuto, 'td', autoCells)
arr[Box] fixedCells = []
collectBoxesForTag(tFixed, 'td', fixedCells)
check(autoCells.length == 4 && fixedCells.length == 4, 'the fixture has four cells')
check(autoCells[0].w > autoCells[1].w,
      'the automatic algorithm widens the column holding the long cell')
checkEqInt(fixedCells[0].w, fixedCells[1].w,
           'the fixed algorithm shares the width equally, whatever the cells hold')
checkEqInt(fixedCells[0].w + fixedCells[1].w, 300, 'and the columns fill the table')

// A width on a first-row cell is honoured, and the rest share what is
// left -- the part of the algorithm that makes it useful.
Box tFixedW = layoutHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<table style="width:300px;border-spacing:0;table-layout:fixed">'
    + '<tr><td style="width:100px">a</td><td>b</td><td>c</td></tr>'
    + '<tr><td>aaaaaaaaaaaaaaaaaaaaaaaa</td><td>b</td><td>c</td></tr></table></body>', 600)
arr[Box] fwCells = []
collectBoxesForTag(tFixedW, 'td', fwCells)
checkEqInt(fwCells[0].w, 100, 'a width in the first row is honoured')
checkEqInt(fwCells[1].w, fwCells[2].w, 'and the rest share what is left')
checkEqInt(fwCells[1].w + fwCells[2].w, 200, 'which is all of it')

// A width in a later row is ignored, which is what "first row" means.
Box tLater = layoutHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<table style="width:300px;border-spacing:0;table-layout:fixed">'
    + '<tr><td>a</td><td>b</td></tr>'
    + '<tr><td style="width:250px">a</td><td>b</td></tr></table></body>', 600)
arr[Box] laterCells = []
collectBoxesForTag(tLater, 'td', laterCells)
checkEqInt(laterCells[0].w, laterCells[1].w, 'a width in a later row is ignored')

// ---- list-style-position: inside -----------------------------------------
// An outside marker hangs in the margin and the text starts at the
// content edge; an inside marker is part of the first line and pushes
// the text along.

Box liOutside = layoutHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<ul style="margin:0;padding:0"><li>xx</li></ul></body>', 600)
Box liInside = layoutHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<ul style="margin:0;padding:0"><li style="list-style-position:inside">xx</li></ul></body>', 600)
Box loBox = findBox(liOutside, 'li')
Box liBox = findBox(liInside, 'li')
check(loBox.lines.length > 0 && liBox.lines.length > 0, 'both list items have a line')
check(liBox.lines[0].frags[0].x > loBox.lines[0].frags[0].x,
      'an inside marker pushes the first line along; an outside one does not')
checkEqInt(loBox.w, liBox.w, 'and neither changes the item box itself')

finish('layout')
