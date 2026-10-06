// `position: sticky` (CSS Positioned Layout 3 §3.5). A sticky box keeps
// its place in the flow and is shifted at paint time so that it stays
// within the scrollport, and no further than its containing block.
//
// The scroll offset is the painter's -- `paintPage(p, 0, scrollY, 300)`
// -- so every check here is a pair of renders of the same document at
// two scroll positions, and what is asserted is how far the box moved
// between them. No screen row is written down: a number worked out here
// would only test the arithmetic that produced it, while "it did not
// move" and "it moved exactly as far as the page scrolled" are what
// sticking and not sticking actually mean.
//
//   before it sticks   the box moves with the page, as a static box does
//   while it is stuck  the box does not move at all
//   past the clamp     it moves with the page again, and it is sitting
//                      where `position: absolute; bottom: 0` in the same
//                      containing block puts a box
//
// The last of those is the one that pins the clamp edge, because the
// three middle rows would all pass on an engine that ignored `sticky`.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

// The marker colour the box is painted in, which nothing else on the
// page uses.
color stMark = '#0088ff'

// The document: a 100px containing block at y=50 with a 20px box at the
// top of it, and enough below to scroll. `top: 20px` leaves room between
// the box's natural place and the clamp, so being stuck and being
// clamped are different rows rather than the same one.
text func stDoc(decl:text) {
    return '<!doctype html><body style="margin:0">'
        + '<div style="height:50px"></div>'
        + '<div id="cb" style="position:relative;height:100px;background:#eeeeee">'
        + `<div id="q" style="${decl};height:20px;background:#0088ff"></div>`
        + '<div style="height:80px"></div></div>'
        + '<div style="height:600px"></div></body>'
}

// The screen rows the marker occupies, read down one column, or an
// empty list where the box is off screen.
arr[int] func stRows(decl:text, scrollY:int) {
    Page p = pageFromHtml(stDoc(decl), 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, scrollY, 300)
    arr[int] out = []
    for int y = 0, y < 300, y++ {
        if getPixelColor(10, y) == stMark { out.push(y) }
    }
    return out
}

// The first marker row, or -1 where the box is off screen.
int func stTop(decl:text, scrollY:int) {
    arr[int] rows = stRows(decl, scrollY)
    return rows.length == 0 ? -1 : rows[0]
}

text STICKY = 'position:sticky;top:20px'
text STATIC = ''
text ABSBOT = 'position:absolute;bottom:0;left:0;width:400px'

// The instrument first. The box has to be on screen at every scroll
// these checks use, or "it did not move" is two absences agreeing.
check(stTop(STICKY, 0) >= 0, 'the box is on screen at scroll 0')
check(stTop(STICKY, 20) >= 0, 'and at scroll 20')
check(stTop(STICKY, 60) >= 0, 'and at scroll 60')
check(stTop(STICKY, 100) >= 0, 'and at scroll 100')
check(stTop(STICKY, 115) >= 0, 'and at scroll 115')
check(stTop(STICKY, 125) >= 0, 'and at scroll 125')
// And a static box, which is the reference the first checks use, has to
// move with the page and scroll off the top before scroll 60 -- so the
// checks below are comparing two rows rather than two absences.
checkEqInt(stTop(STATIC, 0) - stTop(STATIC, 20), 20,
    'a static box moves with the page')
checkEqInt(stTop(STATIC, 80), -1, 'and is gone off the top by scroll 80')

// Before it sticks: `top: 20px` is reached at scroll 30, so at scroll 0
// and scroll 20 the box is still in its natural place and scrolls away
// with the page.
checkEqInt(stTop(STICKY, 0) - stTop(STICKY, 20), 20,
    'an unstuck sticky box moves with the page')
checkEqInt(stTop(STICKY, 0), stTop(STATIC, 0),
    'and sits exactly where a static box sits')
checkEqInt(stTop(STICKY, 20), stTop(STATIC, 20),
    'at both scrolls')

// While it is stuck: from scroll 30 until the clamp at scroll 110, the
// box stays put on the screen however far the page scrolls.
checkEqInt(stTop(STICKY, 60), stTop(STICKY, 100),
    'a stuck sticky box does not move between scroll 60 and scroll 100')
checkEqInt(stTop(STICKY, 60), stTop(STICKY, 40),
    'nor between scroll 40 and scroll 60')

// Past the clamp: the box has reached the bottom of its containing
// block and travels with it again.
checkEqInt(stTop(STICKY, 115) - stTop(STICKY, 125), 10,
    'a clamped sticky box moves with the page again')
// And where it stopped is where the containing block's bottom is,
// which an absolutely positioned box reaches by another route.
checkEqInt(stTop(STICKY, 115), stTop(ABSBOT, 115),
    'a clamped sticky box sits at its containing block bottom')
checkEqInt(stTop(STICKY, 125), stTop(ABSBOT, 125),
    'at the next scroll too')

// A sticky box with no inset has nothing to stick to and never moves
// out of the flow.
text NOINSET = 'position:sticky'
checkEqInt(stTop(NOINSET, 0), stTop(STATIC, 0),
    'a sticky box with no inset stays where a static box is')
checkEqInt(stTop(NOINSET, 20), stTop(STATIC, 20),
    'at every scroll')
checkEqInt(stTop(NOINSET, 80), -1,
    'and scrolls off the top with it')

// ---- inside a scroll container ---------------------------------------
//
// A sticky box sticks to the scrollport of its nearest scroll container,
// not the document's: `overflow` other than `visible` and `clip` makes
// one, whether or not the box can scroll, and the rectangle it keeps
// inside is that container's content box, moved by that container's own
// scroll offset. Every row below is the number Chromium gave for the
// same document (todo.md, "a sticky box inside a scroll container"),
// read as a position in the container's content and turned into a
// screen row -- the container is at y=50 with a 7px border-top, so its
// padding box starts on screen row 57 -- because a number worked out
// here would only test the arithmetic that produced it.

// The container: content between 5px of padding above and 8 below,
// holding a containing block of `cbHeight` whose sticky box sits after
// `spacer` pixels, and 500px more below it so there is room to scroll
// past the containing block's end.
text func scDoc(overflow:text, decl:text, cbHeight:int, spacer:int, height:int) {
    return '<!doctype html><body style="margin:0">'
        + '<div style="height:50px"></div>'
        + `<div id="sc" style="height:${height}px;overflow:${overflow};border-top:7px solid #000;padding:5px 0 8px 0">`
        + `<div style="position:relative;height:${cbHeight}px">`
        + `<div style="height:${spacer}px"></div>`
        + `<div id="q" style="${decl};height:20px;background:#0088ff"></div>`
        + `<div style="height:${cbHeight - spacer - 20}px"></div></div>`
        + '<div style="height:500px"></div></div>'
        + '<div style="height:1000px"></div></body>'
}

// Where the box is on screen with the container scrolled `inner` and the
// document scrolled `outer`, read as a position in the container's
// content -- that is, the screen row less the padding box's row, plus how
// far the container has scrolled -- so that the rows compare to
// Chromium's numbers directly. -1 where the box is off screen.
int func scPos(overflow:text, decl:text, cbHeight:int, spacer:int, height:int, inner:int, outer:int) {
    Page p = pageFromHtml(scDoc(overflow, decl, cbHeight, spacer, height), 'tests/fixtures/page.html', 400)
    Box sc = null
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    for int i = 0, i < all.length, i++ {
        if getAttr(all[i].node, 'id') == 'sc' { sc = all[i] }
    }
    if inner > 0 { boxScrollBy(sc, inner) }
    clearCanvas()
    paintPage(p, 0, outer, 300)
    for int y = 0, y < 300, y++ {
        if getPixelColor(10, y) == stMark { return y + outer - 57 + inner }
    }
    return -1
}

text SC_TOP = 'position:sticky;top:10px'

// top: 10px, the box first in the container. The view is the content
// box, so the first stop is 5 (padding) + 10, not 10.
checkEqInt(scPos('auto', SC_TOP, 400, 0, 100, 0, 0), 15, 'stuck at scroll 0, inset from the content box')
checkEqInt(scPos('auto', SC_TOP, 400, 0, 100, 20, 0), 35, 'and at scroll 20')
checkEqInt(scPos('auto', SC_TOP, 400, 0, 100, 60, 0), 75, 'and at scroll 60')
checkEqInt(scPos('auto', SC_TOP, 400, 0, 100, 200, 0), 215, 'and at scroll 200')
checkEqInt(scPos('auto', SC_TOP, 400, 0, 100, 380, 0), 385, 'clamped to its containing block at scroll 380')
// The same box after a spacer, so the natural place is below the stop:
// it has to wait to be reached.
checkEqInt(scPos('auto', SC_TOP, 400, 100, 100, 0, 0), 105, 'a box below its stop stays in its place at scroll 0')
checkEqInt(scPos('auto', SC_TOP, 400, 100, 100, 60, 0), 105, 'and at scroll 60')
checkEqInt(scPos('auto', SC_TOP, 400, 100, 100, 200, 0), 215, 'until it is reached')
// bottom: 10px pulls the box up into a view it is below.
text SC_BOT = 'position:sticky;bottom:10px'
checkEqInt(scPos('auto', SC_BOT, 400, 300, 100, 0, 0), 75, 'a bottom inset pulls it up to the content box bottom less 10')
checkEqInt(scPos('auto', SC_BOT, 400, 300, 100, 60, 0), 135, 'and it rides along with the scroll')
checkEqInt(scPos('auto', SC_BOT, 400, 300, 100, 220, 0), 295, 'and at scroll 220')
checkEqInt(scPos('auto', SC_BOT, 400, 300, 100, 240, 0), 305, 'until it is in its natural place')
// A containing block shorter than the scroller's content leaves the box
// nowhere to go but the clamp.
checkEqInt(scPos('auto', 'position:sticky;top:0', 150, 0, 100, 60, 0), 65, 'a short containing block: stuck')
checkEqInt(scPos('auto', 'position:sticky;top:0', 150, 0, 100, 100, 0), 105, 'and at scroll 100')

// The document's scroll does not move it: the container is the box's
// scrollport, so a scrolled page only carries the container away.
checkEqInt(scPos('hidden', SC_TOP, 400, 0, 300, 0, 0), 15, 'an overflow: hidden container is a scroll container')
checkEqInt(scPos('hidden', SC_TOP, 400, 0, 300, 0, 40), 15, 'and scrolling the page leaves the box in it')
// `clip` makes no scroll container, so the box sticks to the document.
checkEqInt(scPos('clip', SC_TOP, 400, 0, 300, 0, 60), 13, 'overflow: clip is not one, and the box sticks to the page')

// A click lands where the box is drawn, which is not where it was laid
// out: scrolled 200, the box is stuck at row 72 and laid out at row 62.
Page scHit = pageFromHtml(scDoc('auto', SC_TOP, 400, 0, 100), 'tests/fixtures/page.html', 400)
arr[Box] scHitBoxes = []
collectBoxesForTag(scHit.root, 'div', scHitBoxes)
for int i = 0, i < scHitBoxes.length, i++ {
    if getAttr(scHitBoxes[i].node, 'id') == 'sc' { boxScrollBy(scHitBoxes[i], 200) }
}
Box scHitQ = hitTest(scHit.root, 10, 72)
check(scHitQ != null && getAttr(scHitQ.node, 'id') == 'q', 'a click on the stuck box reaches it')
Box scHitBehind = hitTest(scHit.root, 10, 100)
check(scHitBehind == null || getAttr(scHitBehind.node, 'id') != 'q', 'and one below it does not')

// ---- left and right --------------------------------------------------
//
// The other axis is the same rule across: a `left` inset can only push
// the box right, a `right` inset can only pull it left, and the total is
// clamped to the two distances the box can travel inside its containing
// block's content box. Every row is the number Chromium gave for the
// same document (todo.md, "left and right on a sticky box"), as a
// position in the scroller's content box.
//
// The document cannot scroll across here -- the shell has no horizontal
// page scroll -- so a box in the page is only moved from where the flow
// put it to where its inset wants it, and the scroller is where
// scrolling across is checked.

// A containing block `cbW` wide, a flex row so that the box is `spacer`
// pixels in without a float or an inline run, with the marker 50px wide
// and 20px tall.
text func hRow(decl:text, spacer:int, cbW:int, cbStyle:text) {
    return `<div id="cb" style="position:relative;display:flex;width:${cbW}px;height:50px;${cbStyle}">`
        + `<div style="flex:none;width:${spacer}px;height:1px"></div>`
        + `<div id="q" style="${decl};flex:none;width:50px;height:20px;background:#0088ff"></div></div>`
}

// The first marker column along row 10, or -1.
int func hFirst(x0:int, x1:int) {
    for int x = x0, x < x1, x++ {
        if getPixelColor(x, 10) == stMark { return x }
    }
    return -1
}

int func hDocPos(decl:text, spacer:int, cbW:int, cbStyle:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0">' + hRow(decl, spacer, cbW, cbStyle) + '</body>',
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
    return hFirst(0, 400)
}

text H_LEFT = 'position:sticky;left:10px'
text H_RIGHT = 'position:sticky;right:10px'

checkEqInt(hDocPos(H_LEFT, 0, 1000, ''), 10, 'a left inset pushes a box at the edge in')
checkEqInt(hDocPos(H_LEFT, 100, 1000, ''), 100, 'and leaves a box beyond it alone')
checkEqInt(hDocPos('position:sticky', 0, 1000, ''), 0, 'a sticky box with no inset stays put')
checkEqInt(hDocPos(H_RIGHT, 500, 1000, ''), 340, 'a right inset pulls a box beyond the viewport back to its edge less 10')
checkEqInt(hDocPos(H_RIGHT, 100, 1000, ''), 100, 'and leaves a box inside it alone')
checkEqInt(hDocPos(H_RIGHT, 0, 200, ''), 0, 'a containing block narrower than the view clamps it')
checkEqInt(hDocPos('position:sticky;left:10%', 0, 1000, ''), 40, 'a percentage inset is of the viewport, not the containing block')
checkEqInt(hDocPos('position:sticky;right:10%', 500, 1000, ''), 310, 'on the right as well')
checkEqInt(hDocPos('position:sticky;left:10px;right:10px', 100, 1000, ''), 100, 'both insets together leave a box that fits where it is')
// Two ways to say the same: a percentage is the pixels it resolves to.
checkEqInt(hDocPos('position:sticky;left:10%', 0, 1000, ''), hDocPos('position:sticky;left:40px', 0, 1000, ''),
    'a percentage inset equals its pixels')
// The clamp is to the content box: 30px of padding and 30px of border
// on the left of the block put its content at 60, where the box rests
// even though `left: 10px` asks for less.
checkEqInt(hDocPos(H_LEFT, 0, 600, 'padding-left:30px;border-left:30px solid #444;box-sizing:content-box'), 60,
    'a box is clamped to its containing block content box')

// Scrolling across, in a 300px container with 7px of border, 5px of
// padding before and 8 after, so the content box starts at screen
// column 62.
text func hScDoc(decl:text, spacer:int, cbW:int, cbStyle:text) {
    return '<!doctype html><body style="margin:0;font-size:0">'
        + '<div id="sc" style="width:300px;height:100px;overflow:auto;position:absolute;left:50px;top:0;'
        + 'border-left:7px solid #888;padding-left:5px;padding-right:8px;font-size:0">'
        + hRow(decl, spacer, cbW, cbStyle)
        + '<div style="width:1600px;height:1px"></div></div></body>'
}

int func hScPos(decl:text, spacer:int, cbW:int, cbStyle:text, inner:int) {
    Page p = pageFromHtml(hScDoc(decl, spacer, cbW, cbStyle), 'tests/fixtures/page.html', 400)
    Box sc = null
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    for int i = 0, i < all.length, i++ {
        if getAttr(all[i].node, 'id') == 'sc' { sc = all[i] }
    }
    if inner > 0 { boxScrollLeftBy(sc, inner) }
    clearCanvas()
    paintPage(p, 0, 0, 300)
    int x = hFirst(0, 400)
    return x < 0 ? -1 : x - 62 + inner
}

checkEqInt(hScPos(H_LEFT, 0, 1000, '', 0), 10, 'left: 10px with the box first: stuck at scroll 0')
checkEqInt(hScPos(H_LEFT, 0, 1000, '', 20), 30, 'and at scroll 20')
checkEqInt(hScPos(H_LEFT, 0, 1000, '', 60), 70, 'and at scroll 60')
checkEqInt(hScPos(H_LEFT, 0, 1000, '', 300), 310, 'and at scroll 300')
checkEqInt(hScPos(H_LEFT, 0, 1000, '', 700), 710, 'and at scroll 700')
// Past the clamp the box is where the end of its containing block is, and
// a few pixels more scroll would carry it out of the container's clip, so
// the check is made while it is still in view.
checkEqInt(hScPos(H_LEFT, 0, 1000, '', 945), 950, 'clamped to the end of its containing block')
checkEqInt(hScPos(H_LEFT, 100, 1000, '', 0), 100, 'a box beyond its stop waits at scroll 0')
checkEqInt(hScPos(H_LEFT, 100, 1000, '', 60), 100, 'and at scroll 60')
checkEqInt(hScPos(H_LEFT, 100, 1000, '', 100), 110, 'until it is reached')
checkEqInt(hScPos(H_LEFT, 100, 1000, '', 200), 210, 'and then rides along')
checkEqInt(hScPos(H_RIGHT, 600, 1000, '', 0), 240, 'a right inset pulls it to the view edge less 10')
checkEqInt(hScPos(H_RIGHT, 600, 1000, '', 60), 300, 'and carries it along as the container scrolls')
checkEqInt(hScPos(H_RIGHT, 600, 1000, '', 300), 540, 'at scroll 300')
checkEqInt(hScPos(H_RIGHT, 600, 1000, '', 500), 600, 'until it reaches its natural place')
checkEqInt(hScPos(H_RIGHT, 600, 1000, '', 560), 600, 'and stays in it')
checkEqInt(hScPos('position:sticky;left:0', 0, 200, '', 152), 150, 'a narrow containing block clamps at its far edge')
checkEqInt(hScPos('position:sticky;left:10px;right:10px', 100, 1000, '', 0), 100, 'both insets: a box that fits stays')
checkEqInt(hScPos('position:sticky;left:10px;right:10px', 100, 1000, '', 200), 210, 'and both at scroll 200')
checkEqInt(hScPos(H_LEFT, 0, 600, 'padding-left:30px;border-left:30px solid #444;box-sizing:content-box', 0), 60,
    'rests inside the containing block content box')
checkEqInt(hScPos(H_LEFT, 0, 600, 'padding-left:30px;border-left:30px solid #444;box-sizing:content-box', 605), 610,
    'and is clamped to its far edge')
// A percentage inset is of the scrollport's width -- 300 -- and not of
// the 1000px containing block.
checkEqInt(hScPos('position:sticky;left:10%', 0, 1000, '', 0), 30, 'left: 10% is of the container content box')
checkEqInt(hScPos('position:sticky;left:10%', 0, 1000, '', 60), 90, 'and rides along')
checkEqInt(hScPos('position:sticky;left:10%', 0, 1000, '', 60), hScPos('position:sticky;left:30px', 0, 1000, '', 60),
    'and equals its pixels')

// A click lands where the box is drawn across as well as down.
Page hHit = pageFromHtml(hScDoc(H_LEFT, 0, 1000, ''), 'tests/fixtures/page.html', 400)
arr[Box] hHitBoxes = []
collectBoxesForTag(hHit.root, 'div', hHitBoxes)
for int i = 0, i < hHitBoxes.length, i++ {
    if getAttr(hHitBoxes[i].node, 'id') == 'sc' { boxScrollLeftBy(hHitBoxes[i], 200) }
}
// Scrolled 200 across, the box is laid out at screen column 62 and drawn
// 200 right of that, plus the 10px inset.
Box hHitQ = hitTest(hHit.root, 62 + 10 + 20, 10)
check(hHitQ != null && getAttr(hHitQ.node, 'id') == 'q', 'a click on the box where it is stuck reaches it')
Box hHitNot = hitTest(hHit.root, 62 + 200 + 10 + 80, 10)
check(hHitNot == null || getAttr(hHitNot.node, 'id') != 'q', 'and one beyond its right edge does not')

// ---- percentages in the vertical inset ---------------------------------
//
// A percentage inset is of the scrollport -- the box it sticks to --
// and not of the containing block. The document is 300px tall here, so
// `top: 10%` is 30px, and the box (natural place 50, containing block
// 100 tall) is stuck 30px below the top edge.
checkEqInt(stTop('position:sticky;top:10%', 60), 30, 'top: 10% of the viewport, not of the 100px containing block')
checkEqInt(stTop('position:sticky;top:10%', 60), stTop('position:sticky;top:30px', 60), 'which is its pixels')
checkEqInt(stTop('position:sticky;top:10%', 20), stTop('position:sticky;top:30px', 20), 'at another scroll too')
// In a container it is the container's content height, 100px: the same
// rows as `top: 10px`.
checkEqInt(scPos('auto', 'position:sticky;top:10%', 400, 0, 100, 60, 0), 75, 'top: 10% in a 100px container is 10px')
checkEqInt(scPos('auto', 'position:sticky;top:10%', 400, 0, 100, 200, 0), 215, 'and at scroll 200')
checkEqInt(scPos('auto', 'position:sticky;bottom:10%', 400, 300, 100, 60, 0), 135, 'bottom: 10% in a 100px container is 10px')

finish('sticky')
