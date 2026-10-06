// CSS Overscroll Behavior 1.
//
// A wheel over a scroll container that has reached its end does not
// stop there: `scrollContainerAt` walks outward to the nearest ancestor
// that can still take it, and the shell gives whatever is left to the
// page. `overscroll-behavior: contain` and `none` stop that chain at
// the box that declares them.
//
// Chromium cannot be asked this directly -- a synthetic WheelEvent is
// untrusted, so it moves neither the scroller nor its ancestor with
// `contain` and equally with the default `auto`, and an instrument
// whose control cannot move is not measuring anything (todo.md). What
// Chromium does answer is the computed values, and those are graded by
// the property instrument. This suite grades the chain.
//
// `contain` and `none` behave identically here and the checks say so by
// asking both: `none` differs only in suppressing the overscroll
// affordance, and this browser has none to suppress.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

// An inner scroller inside an outer one, both with more content than
// they can show, so there are two links of chain to break.
text func chainPage(osb:text) {
    return `<!doctype html><body style="margin:0;font:16px/20px monospace">`
        + `<div id="outer" style="width:200px;height:100px;overflow:scroll">`
        + `<div id="inner" style="width:150px;height:60px;overflow:scroll;${osb}">`
        + `<div style="height:300px"></div></div>`
        + `<div style="height:300px"></div></div></body>`
}

Box func boxById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && getAttr(b.node, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = boxById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

// Lays the page out, puts the inner scroller `innerAt` from its top and
// the outer one `outerAt`, then asks what a downward wheel at a point
// inside the inner box would scroll. Answers the box's id, or 'page'
// when the chain reached the page, or 'blocked' when it did not.
Page chainedPage = null
Box chainOuter = null
Box chainInner = null
text func wheelTarget(osb:text, innerAt:int, outerAt:int) {
    boxScrollReset()
    chainedPage = pageFromHtml(chainPage(osb), 'tests/fixtures/page.html', 400)
    chainOuter = boxById(chainedPage.root, 'outer')
    chainInner = boxById(chainedPage.root, 'inner')
    if chainOuter == null || chainInner == null { return 'missing' }
    boxScrollBy(chainInner, innerAt)
    boxScrollBy(chainOuter, outerAt)
    Box hit = wheelTargetAt(chainedPage.root, 10, 10, 20)
    if hit != null { return getAttr(hit.node, 'id') }
    return wheelChainBlocked ? 'blocked' : 'page'
}

// ---- the chain, with nothing declared ----------------------------------

checkEq(wheelTarget('', 0, 0), 'inner',
        'a wheel over a scroller that can still scroll scrolls it')
checkEq(wheelTarget('', 10000, 0), 'outer',
        'and one that has reached its end passes the wheel to its ancestor')
checkEq(wheelTarget('', 10000, 10000), 'page',
        'and when that has reached its end too, the page takes it')

// ---- what `contain` and `none` change ----------------------------------

// Only at the boundary: a container that can still scroll takes the
// wheel whatever it declares, which is the check that does not depend
// on the keyword doing anything.
checkEq(wheelTarget('overscroll-behavior:contain', 0, 0), 'inner',
        'contain changes nothing while the scroller can still take the wheel')
checkEq(wheelTarget('overscroll-behavior:none', 0, 0), 'inner',
        'and neither does none')

checkEq(wheelTarget('overscroll-behavior:contain', 10000, 0), 'blocked',
        'contain stops the chain at the end of the scroller that declares it')
checkEq(wheelTarget('overscroll-behavior:none', 10000, 0), 'blocked',
        'and none stops it in exactly the same way')
checkEq(wheelTarget('overscroll-behavior:auto', 10000, 0), 'outer',
        'while auto, the initial value, is the chain it always was')

// ---- the axis it names -------------------------------------------------

// A vertical wheel asks the y axis. Containing the x axis alone leaves
// it alone, and the two logical spellings are the two physical ones:
// `block` is `y` and `inline` is `x` (todo.md).
checkEq(wheelTarget('overscroll-behavior-x:contain', 10000, 0), 'outer',
        'containing the horizontal axis does not stop a vertical wheel')
checkEq(wheelTarget('overscroll-behavior-y:contain', 10000, 0), 'blocked',
        'and containing the vertical axis does')
checkEq(wheelTarget('overscroll-behavior-block:contain', 10000, 0), 'blocked',
        'block is the vertical axis under another name')
checkEq(wheelTarget('overscroll-behavior-inline:contain', 10000, 0), 'outer',
        'and inline is the horizontal one')

// The shorthand takes the two axes in the order x then y, so one value
// contains both and two contain the one they name.
checkEq(wheelTarget('overscroll-behavior:contain auto', 10000, 0), 'outer',
        'the shorthand gives its first value to the horizontal axis')
checkEq(wheelTarget('overscroll-behavior:auto contain', 10000, 0), 'blocked',
        'and its second to the vertical one')
checkEq(wheelTarget('overscroll-behavior:scroll', 10000, 0), 'outer',
        'an invalid keyword leaves the initial auto')

// ---- and it stops the page taking it -----------------------------------

checkEq(wheelTarget('', 10000, 10000), 'page',
        'the page takes a wheel neither scroller could')
Page outerContained = null
text func outerWheel(osb:text) {
    boxScrollReset()
    outerContained = pageFromHtml(
        `<!doctype html><body style="margin:0;font:16px/20px monospace">`
        + `<div id="outer" style="width:200px;height:100px;overflow:scroll;${osb}">`
        + `<div style="height:300px"></div></div>`
        + `<div style="height:600px"></div></body>`, 'tests/fixtures/page.html', 400)
    Box o = boxById(outerContained.root, 'outer')
    if o == null { return 'missing' }
    boxScrollBy(o, 10000)
    Box hit = wheelTargetAt(outerContained.root, 10, 10, 20)
    if hit != null { return getAttr(hit.node, 'id') }
    return wheelChainBlocked ? 'blocked' : 'page'
}
checkEq(outerWheel(''), 'page', 'a lone scroller at its end gives the wheel to the page')
checkEq(outerWheel('overscroll-behavior:contain'), 'blocked',
        'and contain keeps the page still')

// ---- a scroller with nothing to scroll ---------------------------------

// A box with `overflow: scroll` whose content fits is at both of its
// ends at once, so it is at a boundary and contains the chain exactly
// as one scrolled to its end does. The wheel reached it either way;
// having nothing to give back is not a reason to pass it on.
Page emptyScroller = null
text func fittedWheel(osb:text) {
    boxScrollReset()
    emptyScroller = pageFromHtml(
        `<!doctype html><body style="margin:0;font:16px/20px monospace">`
        + `<div id="outer" style="width:200px;height:100px;overflow:scroll">`
        + `<div id="inner" style="width:150px;height:60px;overflow:scroll;${osb}">`
        + `<div style="height:5px"></div></div>`
        + `<div style="height:300px"></div></div></body>`, 'tests/fixtures/page.html', 400)
    Box i = boxById(emptyScroller.root, 'inner')
    if i == null { return 'missing' }
    checkEqInt(boxScrollRange(i), 0, 'the inner scroller has nothing to scroll')
    Box hit = wheelTargetAt(emptyScroller.root, 10, 10, 20)
    if hit != null { return getAttr(hit.node, 'id') }
    return wheelChainBlocked ? 'blocked' : 'page'
}
checkEq(fittedWheel(''), 'outer',
        'a scroller with nothing to scroll passes the wheel to its ancestor')
checkEq(fittedWheel('overscroll-behavior:contain'), 'blocked',
        'and contain stops it there all the same')

finish('overscroll behavior')
