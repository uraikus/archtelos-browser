// `text-wrap-style` (CSS Text 4 §6.2): how the line breaker chooses
// among the breaks that fit.
//
// The measurements are in todo.md, and they separate the four values
// cleanly. `auto` and `stable` are the greedy break. `pretty` refuses
// a one-word last line where another break avoids it. `balance` adds
// to that, at six lines or fewer, the break whose widest line is
// narrowest -- and it never changes the line count or the block's
// height, which is the first thing asserted here.
//
// The standard leaves the algorithm to the user agent and asks only
// that the difference between the longest and the shortest line be
// minimised, so this engine implements it as a search over the WIDTH
// the greedy breaker is given: the narrowest width that still breaks
// into the same number of lines. That needs no second line breaker
// and it is the shape of the answer Chromium gives on a two-line
// paragraph -- 183 + 48 greedily and 106 + 125 balanced there, 190 +
// 50 and 110 + 130 here, the ratio being the whole-pixel advance this
// engine rounds to. It is WEAKER than Chromium's on a paragraph whose
// words cannot be redistributed by narrowing the measure alone;
// todo.md records where and why.
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

Box func findBox(b:Box, tag:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node.tag == tag { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findBox(b.children[i], tag)
        if f != null { return f }
    }
    return null
}

// A paragraph of `text`, `px` wide, under one `text-wrap-style`.
Box func para(style:text, px:int, body:text) {
    return findBox(layoutHtml('<body style="margin:0;font:16px/20px monospace">'
        + '<p style="margin:0;width:' + `${px}` + 'px;text-wrap-style:' + style + '">'
        + body + '</p></body>', 400), 'p')
}

// `Line.w` is the width the line box was GIVEN, not the width of what
// is on it, and balancing works by giving the breaker a narrower one.
// So the two readings answer two different questions and both are
// needed: the measure says whether balancing ran, the ink says what it
// did.
int func measureOf(p:Box) { return p.lines.length == 0 ? 0 : p.lines[0].w }

int func inkOf(l:Line) {
    int right = l.x
    for int f = 0, f < l.frags.length, f++ {
        int e = l.frags[f].x + l.frags[f].w
        if e > right { right = e }
    }
    return right - l.x
}

int func widest(p:Box) {
    int m = 0
    for int i = 0, i < p.lines.length, i++ {
        int v = inkOf(p.lines[i])
        if v > m { m = v }
    }
    return m
}

text func lineShape(p:Box) {
    arr[text] parts = []
    for int i = 0, i < p.lines.length, i++ { parts.push(`${inkOf(p.lines[i])}`) }
    return parts.join(',')
}

// `n` three-character words, then two two-character ones -- the
// fixture the threshold was measured with, which leaves a short last
// line at every length.
text func tailText(n:int) {
    arr[text] w = []
    for int i = 0, i < n, i++ { w.push('mmm') }
    w.push('mm')
    w.push('mm')
    return w.join(' ')
}

// ---- the computed value -----------------------------------------------
checkEqInt(textWrapStyleOf(para('auto', 200, 'x').style), TWS_AUTO, 'auto computes to auto')
checkEqInt(textWrapStyleOf(para('balance', 200, 'x').style), TWS_BALANCE, 'balance computes to balance')
checkEqInt(textWrapStyleOf(para('pretty', 200, 'x').style), TWS_PRETTY, 'pretty computes to pretty')
checkEqInt(textWrapStyleOf(para('stable', 200, 'x').style), TWS_STABLE, 'stable computes to stable')
checkEqInt(textWrapStyleOf(para('nonsense', 200, 'x').style), TWS_AUTO,
           'an unknown keyword leaves the initial value')

// ---- balance keeps the line count and the height ----------------------
// Asserted against `auto` rather than against numbers, so it holds
// whatever this engine's advances are.
for int n = 1, n <= 8, n++ {
    Box a = para('auto', 200, tailText(5 * n))
    Box b = para('balance', 200, tailText(5 * n))
    checkEqInt(b.lines.length, a.lines.length, `balance keeps the line count at ${n * 5 + 2} words`)
    checkEqInt(b.h, a.h, `and the block's height at ${n * 5 + 2} words`)
}

// ---- and it never widens the widest line ------------------------------
for int n = 1, n <= 8, n++ {
    Box a = para('auto', 200, tailText(5 * n))
    Box b = para('balance', 200, tailText(5 * n))
    check(widest(b) <= widest(a), `balance never widens the widest line at ${n * 5 + 2} words`)
}

// ---- the measured case ------------------------------------------------
// Chromium answers 183 + 48 greedy and 106 + 125 balanced on this one.
// This engine's advance is a whole pixel where Chromium's is 9.633, so
// the numbers differ by that ratio and the break does not: the greedy
// one leaves a last line a quarter of the first, and the balanced one
// does not.
Box g2 = para('auto', 200, tailText(5))
Box b2 = para('balance', 200, tailText(5))
checkEqInt(g2.lines.length, 2, 'the fixture is two lines')
checkEq(lineShape(g2), '190,50', 'greedy leaves a last line a quarter of the first')
checkEq(lineShape(b2), '110,130', 'and balance does not')
check(inkOf(g2.lines[1]) * 3 < inkOf(g2.lines[0]),
      'the greedy last line is under a third of the first')
check(inkOf(b2.lines[1]) * 3 > inkOf(b2.lines[0]), 'and the balanced one is not')
check(widest(b2) < widest(g2), 'the widest line is narrower balanced')

// ---- the threshold is six lines ---------------------------------------
// At seven lines and beyond the search does not run at all, which is
// where Chromium stops too and what keeps this bounded. The six-line
// row asserts the MEASURE narrowed rather than the break moved: on a
// paragraph of equal words the narrowest width that still gives six
// lines is the one the greedy break already used, so the search runs,
// finds no better width, and changes nothing. Chromium redistributes
// the words there and this engine cannot, which todo.md records.
Box a6 = para('auto', 200, tailText(25))
Box b6 = para('balance', 200, tailText(25))
checkEqInt(a6.lines.length, 6, 'twenty-seven words is six lines')
check(measureOf(b6) < measureOf(a6), 'at six lines balance still narrows the measure')
Box a7 = para('auto', 200, tailText(30))
Box b7 = para('balance', 200, tailText(30))
checkEqInt(a7.lines.length, 7, 'thirty-two words is seven lines')
checkEqInt(measureOf(b7), measureOf(a7), 'at seven lines the search does not run')
checkEq(lineShape(b7), lineShape(a7), 'and the break is left alone')

// ---- one line is already balanced -------------------------------------
Box a1 = para('auto', 200, 'mmm mm')
Box b1 = para('balance', 200, 'mmm mm')
checkEqInt(a1.lines.length, 1, 'the short paragraph is one line')
checkEqInt(measureOf(b1), measureOf(a1), 'a single line does not run the search')
checkEq(lineShape(b1), lineShape(a1), 'and is left alone')

// ---- the values this engine does not act on ---------------------------
// `pretty`'s widow rule and `stable` are measured in todo.md and not
// implemented, so both break exactly as `auto` does. They are kept
// apart in the computed style, which is what the check above asserts,
// and this one says plainly that nothing else follows from them yet.
Box ap = para('auto', 200, tailText(5))
checkEq(lineShape(para('pretty', 200, tailText(5))), lineShape(ap), 'pretty breaks as auto')
checkEq(lineShape(para('stable', 200, tailText(5))), lineShape(ap), 'and so does stable')
checkEqInt(measureOf(para('pretty', 200, tailText(5))), measureOf(ap),
           'and neither narrows the measure')

// ---- a float in the content is left alone -----------------------------
// Balancing runs the greedy breaker again at a narrower width, and a
// float is registered with its formatting context as it is placed, so
// a second pass would place it twice. Inline content holding one is
// not balanced, and says so here rather than in a comment alone.
text floaty = '<span style="float:left;width:20px;height:10px"></span>' + tailText(5)
checkEqInt(measureOf(para('balance', 200, floaty)), measureOf(para('auto', 200, floaty)),
           'inline content holding a float is not balanced')

// ---- it inherits, and the shorthand sets it ---------------------------
Box inh = findBox(layoutHtml('<body style="margin:0;font:16px/20px monospace;'
    + 'text-wrap-style:balance"><p style="margin:0;width:200px">' + tailText(5)
    + '</p></body>', 400), 'p')
checkEqInt(textWrapStyleOf(inh.style), TWS_BALANCE, 'text-wrap-style inherits')
checkEq(lineShape(inh), '110,130', 'and the inherited value balances the paragraph')

Box sh = findBox(layoutHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<p style="margin:0;width:200px;text-wrap:balance">' + tailText(5)
    + '</p></body>', 400), 'p')
checkEqInt(textWrapStyleOf(sh.style), TWS_BALANCE, 'the text-wrap shorthand sets the style half')
Box sh2 = findBox(layoutHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<p style="margin:0;width:200px;text-wrap:wrap balance">' + tailText(5)
    + '</p></body>', 400), 'p')
checkEqInt(textWrapStyleOf(sh2.style), TWS_BALANCE, 'and takes both halves in either order')
checkEqInt(sh2.style.textWrapMode, WRAP_WRAP, 'with the mode half still reaching the mode')

finish('text wrap')
