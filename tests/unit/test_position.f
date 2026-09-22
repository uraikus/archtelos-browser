// Positioning: CSS2 §9.3 and CSS Positioned Layout 3. Until now
// `position` did not appear in src/css at all and every box was static.
// See css-2026.md, "CSS Level 2".

import ../../src/browser/page.f
import ../assert.f

// ---- the properties are computed at all --------------------------------
Page p0 = pageFromHtml('<!doctype html><body><p style="position: relative; top: 5px; left: 7px; z-index: 3">x</p></body>', 'about:blank', 800)
Node el0 = findElement(p0.doc, 'p')
checkEqInt(el0.style.position, POS_RELATIVE, 'position: relative is computed')
checkEqInt(resolveLen(el0.style.top, 0, -1), 5, 'top is computed')
checkEqInt(resolveLen(el0.style.left, 0, -1), 7, 'left is computed')
checkEqInt(el0.style.zIndex, 3, 'z-index is computed')

// ---- relative offsets the box and leaves the flow alone ---------------
Page p1 = pageFromHtml('<!doctype html><body style="margin:0"><div style="height:20px">a</div><div id="m" style="height:20px; position: relative; top: 30px; left: 15px">b</div><div style="height:20px">c</div></body>', 'about:blank', 800)
arr[Box] divs = []
collectBoxesForTag(p1.root, 'div', divs)
checkEqInt(divs.length, 3, 'three divs')
checkEqInt(divs[0].y, 0, 'the first div is at the top')
checkEqInt(divs[1].y, 50, 'the relative div is offset by top')
checkEqInt(divs[1].x, 15, 'and by left')
checkEqInt(divs[2].y, 40, 'the div after it keeps its in-flow position')

// a relative box carries its descendants with it
Page p1b = pageFromHtml('<!doctype html><body style="margin:0"><div style="position: relative; top: 10px"><p style="margin:0">x</p></div></body>', 'about:blank', 800)
arr[Box] inner = []
collectBoxesForTag(p1b.root, 'p', inner)
checkEqInt(inner[0].y, 10, 'a descendant of a relative box moves with it')

// ---- absolute leaves the flow -----------------------------------------
Page p2 = pageFromHtml('<!doctype html><body style="margin:0"><div style="height:20px">a</div><div style="height:20px; position: absolute; top: 100px; left: 50px">b</div><div style="height:20px">c</div></body>', 'about:blank', 800)
arr[Box] d2 = []
collectBoxesForTag(p2.root, 'div', d2)
checkEqInt(d2[2].y, 20, 'an absolute box takes no space in the flow')
checkEqInt(d2[1].y, 100, 'and sits where top says')
checkEqInt(d2[1].x, 50, 'and where left says')

// ---- absolute resolves against the nearest positioned ancestor --------
// The 40px sits above the div as a gap in the flow, so the absolute
// child resolves against a containing block that starts at 40.
Page p3 = pageFromHtml('<!doctype html><body style="margin:0"><div style="height:40px"></div><div style="position: relative; height: 200px"><p id="a" style="position: absolute; top: 10px; left: 20px; margin: 0">x</p></div></body>', 'about:blank', 800)
arr[Box] ap = []
collectBoxesForTag(p3.root, 'p', ap)
checkEqInt(ap[0].y, 50, 'top is measured from the positioned ancestor, not the page')
checkEqInt(ap[0].x, 20, 'and so is left')

// a static ancestor is not a containing block
Page p4 = pageFromHtml('<!doctype html><body style="margin:0"><div style="margin-top: 40px"><p style="position: absolute; top: 10px; margin: 0">x</p></div></body>', 'about:blank', 800)
arr[Box] ap4 = []
collectBoxesForTag(p4.root, 'p', ap4)
checkEqInt(ap4[0].y, 10, 'a static ancestor is skipped when finding the containing block')

// ---- right and bottom -------------------------------------------------
Page p5 = pageFromHtml('<!doctype html><body style="margin:0"><div style="position: relative; width: 400px; height: 300px"><p style="position: absolute; right: 30px; bottom: 40px; width: 100px; height: 20px; margin: 0">x</p></div></body>', 'about:blank', 800)
arr[Box] ap5 = []
collectBoxesForTag(p5.root, 'p', ap5)
checkEqInt(ap5[0].x, 270, 'right positions from the right edge of the containing block')
checkEqInt(ap5[0].y, 240, 'bottom positions from its bottom edge')

// ---- fixed is measured from the viewport ------------------------------
Page p6 = pageFromHtml('<!doctype html><body style="margin:0"><div style="position: relative; margin-top: 300px; height: 100px"><p style="position: fixed; top: 12px; left: 8px; margin: 0">x</p></div></body>', 'about:blank', 800)
arr[Box] ap6 = []
collectBoxesForTag(p6.root, 'p', ap6)
checkEqInt(ap6[0].y, 12, 'a fixed box ignores its positioned ancestor')
checkEqInt(ap6[0].x, 8, 'in both axes')

// ---- the static position (CSS2 §10.3.7) -------------------------------

// A box with an `auto` inset sits where it would have been in flow, not
// at the corner of its containing block. Every number below is
// Chromium's, in todo.md, as the box's position relative to its
// containing block.

Box func staticBox(inner:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0;font:16px/20px monospace">'
        + '<div id="cb" style="position:relative;width:400px;height:200px">'
        + inner + '</div></body>', 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'i', all)
    return all.length > 0 ? all[0] : null
}

// The box under test is an <i>, so that `collectBoxesForTag` finds it
// whether it was written block-level or inline-level.
text ABS = '<i style="position:absolute;display:block;width:30px;height:20px"></i>'

Box sb1 = staticBox(ABS)
checkEqInt(sb1.x, 0, 'a direct child of the containing block starts at its corner')
checkEqInt(sb1.y, 0, 'in both axes')

Box sb2 = staticBox('<div style="height:50px"></div>' + ABS)
checkEqInt(sb2.y, 50, 'a box after a 50px block sits below it')
checkEqInt(sb2.x, 0, 'and still at the left')

Box sb3 = staticBox('<div style="margin-left:60px">' + ABS + '</div>')
checkEqInt(sb3.x, 60, 'a box inside an indented div is indented with it')
checkEqInt(sb3.y, 0, 'and still at the top')

Box sb4 = staticBox('<div style="height:50px"></div>'
                    + '<div style="margin-left:60px">' + ABS + '</div>')
checkEqInt(sb4.x, 60, 'both at once, across')
checkEqInt(sb4.y, 50, 'and down')

// A block-level box among inline content starts on the line after it.
Box sb5 = staticBox('abcde' + ABS)
checkEqInt(sb5.y, 20, 'a block-level box after text starts on the next line')
checkEqInt(sb5.x, 0, 'at the start of it')

// The flow begins inside the containing block's padding.
Page padded = pageFromHtml('<!doctype html><body style="margin:0;font:16px/20px monospace">'
    + '<div id="cb" style="position:relative;width:400px;height:200px;padding:20px">'
    + '<div style="height:50px"></div>' + ABS + '</div></body>', 'about:blank', 800)
arr[Box] padIt = []
collectBoxesForTag(padded.root, 'i', padIt)
checkEqInt(padIt[0].x, 20, "the containing block's padding moves the static position across")
checkEqInt(padIt[0].y, 70, 'and down')

// An inset that is not `auto` is unaffected, so the two axes are
// decided separately.
Box sb6 = staticBox('<div style="height:50px"></div>'
    + '<div style="margin-left:60px">'
    + '<i style="position:absolute;display:block;width:30px;height:20px;top:5px"></i>'
    + '</div>')
checkEqInt(sb6.x, 60, 'a declared top leaves the static position across alone')
checkEqInt(sb6.y, 5, 'while down it is the inset that decides')

// ---- a transform is a containing block (Transforms 1 §3, measured) -----
//
// Chromium, on a positioned grandparent holding a middle box holding an
// out-of-flow child at left/top 0 (todo.md): the child lands on the
// grandparent when the middle box has no transform and on the **middle
// box** when it has one, and a `position: fixed` child does the same --
// it lands on the viewport normally and on the transformed box here.
//
// The trigger is the computed value rather than the matrix:
// `rotate(0deg)` computes to matrix(1, 0, 0, 1, 0, 0), byte for byte
// what `translateX(0px)` computes to, and both count. Only `none` does
// not -- which is exactly `transforms.length`.

Box func cbChild(mid:text, kind:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0">'
        + '<div style="position:relative;left:50px;top:50px;width:400px;height:200px;'
        + 'border:1px solid #000">'
        + '<div id="m" style="margin:20px;width:200px;height:100px;' + mid + '">'
        + '<div id="c" style="position:' + kind + ';left:0;top:0;width:30px;height:30px"></div>'
        + '</div></div></body>', 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    for int i = 0, i < all.length, i++ {
        if getAttr(all[i].node, 'id') == 'c' { return all[i] }
    }
    return null
}

Box cbPlainAbs = cbChild('', 'absolute')
Box cbTxAbs = cbChild('transform:translateX(0px)', 'absolute')
Box cbNoneAbs = cbChild('transform:none', 'absolute')
Box cbRotAbs = cbChild('transform:rotate(0deg)', 'absolute')

check(cbPlainAbs != null, 'the absolute child has a box')
// The grandparent's one-pixel border puts its padding box at 51,51 and
// stops the middle box's margin collapsing through it, so the middle box
// is at 71,71 and the two are distinguishable on both axes.
checkEqInt(cbPlainAbs.x, 51, 'with no transform the absolute child takes the positioned ancestor')
checkEqInt(cbPlainAbs.y, 51, 'on both axes')
checkEqInt(cbTxAbs.x, 71, 'a transform makes the middle box the containing block')
checkEqInt(cbTxAbs.y, 71, 'on both axes')

// `none` is not a transform, so it must agree with declaring nothing --
// which is the check that does not depend on either number being known.
checkEqInt(cbNoneAbs.x, cbPlainAbs.x, 'transform: none is not a containing block')
checkEqInt(cbNoneAbs.y, cbPlainAbs.y, 'on both axes')

// An identity matrix is still a transform, and the two spellings of one
// must agree rather than each match a number.
checkEqInt(cbRotAbs.x, cbTxAbs.x, 'rotate(0deg) is a transform as much as translateX(0px)')
checkEqInt(cbRotAbs.y, cbTxAbs.y, 'on both axes')

// A fixed child resolves against the viewport, and against a
// transformed ancestor when there is one.
Box cbPlainFix = cbChild('', 'fixed')
Box cbTxFix = cbChild('transform:translateX(0px)', 'fixed')
checkEqInt(cbPlainFix.x, 0, 'a fixed child takes the viewport')
checkEqInt(cbPlainFix.y, 0, 'on both axes')
checkEqInt(cbTxFix.x, 71, 'and a transformed ancestor where there is one')
checkEqInt(cbTxFix.y, 71, 'on both axes')

// ---- hit testing goes through the inverse transform --------------------
//
// A 100x40 box rotated 90 degrees about its centre is drawn 40 wide and
// 100 tall. Chromium's elementFromPoint follows the drawn shape: the
// points inside it and outside the laid-out rectangle hit it, and the
// points inside the laid-out rectangle and outside the drawn one miss.

// The body is given a height because hit testing culls by the
// ancestor's rectangle, so an out-of-flow box outside it is unreachable
// -- which is its own bug rather than this one's (todo.md).
Box func hitTransformRoot() {
    Page p = pageFromHtml('<!doctype html><body style="margin:0;height:600px">'
        + '<div id="r" style="position:absolute;left:100px;top:300px;'
        + 'width:100px;height:40px;transform:rotate(90deg)"></div>'
        + '</body>', 'about:blank', 800)
    return p.root
}

Box hitRootT = hitTransformRoot()
// Drawn: x 130..170, y 270..370, about the centre 150,320.
Box hitInsideDrawn = hitTest(hitRootT, 150, 280)
Box hitInsideDrawn2 = hitTest(hitRootT, 150, 360)
Box hitOutsideDrawn = hitTest(hitRootT, 110, 320)
Box hitOutsideDrawn2 = hitTest(hitRootT, 190, 320)
Box hitCentre = hitTest(hitRootT, 150, 320)

check(hitInsideDrawn != null && getAttr(hitInsideDrawn.node, 'id') == 'r',
      'a point inside the drawn box but outside the laid-out one hits it')
check(hitInsideDrawn2 != null && getAttr(hitInsideDrawn2.node, 'id') == 'r',
      'and so does the other end of it')
check(hitOutsideDrawn == null || getAttr(hitOutsideDrawn.node, 'id') != 'r',
      'a point inside the laid-out box but outside the drawn one misses')
check(hitOutsideDrawn2 == null || getAttr(hitOutsideDrawn2.node, 'id') != 'r',
      'on the other side too')
check(hitCentre != null && getAttr(hitCentre.node, 'id') == 'r',
      'the centre is inside both and hits')

// The centre of a rotation does not move, so a box rotated by any angle
// is hit at its centre -- which needs no number and holds for all four.
Box func rotatedRoot(angle:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0;height:600px">'
        + '<div id="r" style="position:absolute;left:100px;top:100px;'
        + 'width:80px;height:40px;transform:rotate(' + angle + ')"></div>'
        + '</body>', 'about:blank', 800)
    return p.root
}
Box rc0 = hitTest(rotatedRoot('0deg'), 140, 120)
Box rc30 = hitTest(rotatedRoot('30deg'), 140, 120)
Box rc90 = hitTest(rotatedRoot('90deg'), 140, 120)
Box rc180 = hitTest(rotatedRoot('180deg'), 140, 120)
check(rc0 != null && getAttr(rc0.node, 'id') == 'r', 'the centre is hit unrotated')
check(rc30 != null && getAttr(rc30.node, 'id') == 'r', 'and at 30 degrees')
check(rc90 != null && getAttr(rc90.node, 'id') == 'r', 'and at 90')
check(rc180 != null && getAttr(rc180.node, 'id') == 'r', 'and at 180')

// A translate moves the drawn box whole, so the point that was inside
// misses and the point it moved onto hits.
Page pmove = pageFromHtml('<!doctype html><body style="margin:0;height:600px">'
    + '<div id="r" style="position:absolute;left:100px;top:100px;'
    + 'width:80px;height:40px;transform:translate(200px,0)"></div>'
    + '</body>', 'about:blank', 800)
Box mvIn = hitTest(pmove.root, 140, 120)
Box mvOut = hitTest(pmove.root, 340, 120)
check(mvIn == null || getAttr(mvIn.node, 'id') != 'r',
      'a translated box is not where it was laid out')
check(mvOut != null && getAttr(mvOut.node, 'id') == 'r', 'it is where it was drawn')

// ---- an out-of-flow box beyond its ancestors is still hit ------------
//
// Hit testing descends only into children whose rectangle holds the
// point, so a box laid out past every ancestor's box was unreachable.
// Chromium finds it: with an empty body -- `getBoundingClientRect`
// gives it a height of **0** -- a `position: absolute` box at 100,100
// answers `elementFromPoint` at 140,120, and so does one beyond a
// parent ten pixels tall, and a `position: fixed` one beyond both
// (todo.md).

Box func outFlowRoot(css:text, body:text) {
    Page p = pageFromHtml('<!doctype html><head><style>body{margin:0}' + css
        + '</style><body>' + body + '</body>', 'about:blank', 800)
    return p.root
}

text OF_ABS = '#a{position:absolute;left:100px;top:100px;width:80px;height:40px}'

Box ofEmpty = hitTest(outFlowRoot(OF_ABS, '<div id="a"></div>'), 140, 120)
check(ofEmpty != null && getAttr(ofEmpty.node, 'id') == 'a',
      'an absolute box in an empty body is hit')

Box ofBeside = hitTest(outFlowRoot(OF_ABS, '<div id="a"></div>'), 300, 120)
check(ofBeside == null || getAttr(ofBeside.node, 'id') != 'a',
      'and a point beside it is not')

text OF_SHORT = '#p{position:relative;width:50px;height:10px}' + OF_ABS
Box ofChild = hitTest(outFlowRoot(OF_SHORT, '<div id="p"><div id="a"></div></div>'), 140, 120)
check(ofChild != null && getAttr(ofChild.node, 'id') == 'a',
      'an absolute box beyond a short parent is hit')

Box ofParent = hitTest(outFlowRoot(OF_SHORT, '<div id="p"><div id="a"></div></div>'), 20, 5)
check(ofParent != null && getAttr(ofParent.node, 'id') == 'p',
      'and the parent is still hit where it is')

text OF_FIXED = '#p{width:10px;height:10px}'
    + '#a{position:fixed;left:200px;top:200px;width:80px;height:40px}'
Box ofFixed = hitTest(outFlowRoot(OF_FIXED, '<div id="p"><div id="a"></div></div>'), 240, 220)
check(ofFixed != null && getAttr(ofFixed.node, 'id') == 'a',
      'a fixed box beyond everything is hit')

// `pointer-events: none` takes it out of hit testing wherever it is, so
// the new path must honour it exactly as the ordinary descent does.
Box ofNone = hitTest(outFlowRoot(OF_ABS + '#a{pointer-events:none}',
    '<div id="a"></div>'), 140, 120)
check(ofNone == null || getAttr(ofNone.node, 'id') != 'a',
      'pointer-events: none keeps it out of the new path too')

// And a transformed one is hit where it is drawn, which is the two
// features agreeing rather than each answering on its own.
Box ofTx = hitTest(outFlowRoot(
    '#a{position:absolute;left:100px;top:100px;width:80px;height:40px;'
    + 'transform:translate(200px,0)}', '<div id="a"></div>'), 340, 120)
check(ofTx != null && getAttr(ofTx.node, 'id') == 'a',
      'a translated out-of-flow box is hit where it is drawn')

// ---- a click lands on the topmost box (CSS2 §9.9) ---------------------
//
// Hit testing answers the box the painter drew last at that point.
// Measured in Chromium (todo.md), five pairs pinning five steps of the
// painting order against the one below.

Box func topAt(css:text, body:text, x:int, y:int) {
    Page p = pageFromHtml('<!doctype html><head><style>body{margin:0;font:16px monospace}'
        + css + '</style><body>' + body + '</body>', 'about:blank', 800)
    return hitTest(p.root, x, y)
}

text func topIdAt(css:text, body:text, x:int, y:int) {
    Box b = topAt(css, body, x, y)
    if b == null { return 'null' }
    text id = getAttr(b.node, 'id')
    return id == null ? b.node.tag : id
}

// A positioned box written *before* an in-flow one still wins.
checkEq(topIdAt(
    '#pos{position:absolute;left:0;top:0;width:200px;height:100px}'
    + '#flow{width:200px;height:100px}',
    '<div id="pos"></div><div id="flow"></div>', 50, 50),
    'pos', 'a positioned box beats an in-flow one written after it')

// The later of two overlapping boxes at the same z wins. Two in-flow
// blocks would be the plainest case and cannot be written here: a
// negative `margin-top` is not applied by this engine, so they do not
// overlap at all (todo.md). Two positioned boxes at the same z ask the
// same question of the same loop.
checkEq(topIdAt(
    '#a{position:absolute;left:0;top:0;width:200px;height:100px}'
    + '#b{position:absolute;left:0;top:0;width:200px;height:100px}',
    '<div id="a"></div><div id="b"></div>', 50, 50),
    'b', 'the later of two boxes at the same z wins')

// The higher z-index wins whatever the document order.
checkEq(topIdAt(
    '#a{position:absolute;left:0;top:0;width:200px;height:100px;z-index:5}'
    + '#b{position:absolute;left:0;top:0;width:200px;height:100px;z-index:1}',
    '<div id="a"></div><div id="b"></div>', 50, 50),
    'a', 'the higher z-index wins whatever the order')

// A negative-z box loses to its stacking context's in-flow content.
checkEq(topIdAt(
    '#p{position:relative;z-index:0;width:200px;height:100px}'
    + '#neg{position:absolute;z-index:-1;left:0;top:0;width:200px;height:100px}'
    + '#flow{width:200px;height:100px}',
    '<div id="p"><div id="neg"></div><div id="flow"></div></div>', 50, 50),
    'flow', 'a negative z-index box is under the in-flow content')

// A child wins over its parent's background.
checkEq(topIdAt('#p{width:200px;height:100px}#c{width:100px;height:50px}',
    '<div id="p"><div id="c"></div></div>', 50, 25),
    'c', 'a child wins over its parent')

// The in-flow box in the fourth case has no background at all and still
// wins, so this is about the box rather than the ink -- asserted by
// giving it one and requiring the same answer.
checkEq(topIdAt(
    '#p{position:relative;z-index:0;width:200px;height:100px}'
    + '#neg{position:absolute;z-index:-1;left:0;top:0;width:200px;height:100px;background:red}'
    + '#flow{width:200px;height:100px;background:transparent}',
    '<div id="p"><div id="neg"></div><div id="flow"></div></div>', 50, 50),
    'flow', 'and a transparent box still takes the click')

finish('position')
