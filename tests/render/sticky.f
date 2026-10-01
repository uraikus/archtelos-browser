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

finish('sticky')
