// CSS Motion Path 1.
//
// `offset-path` gives a box a path, `offset-distance` a point along it,
// and the box is painted there. None of it needs a clock: the numbers
// below are Chromium 141's, read off a still frame.
//
// The fixture is the one the measurement used -- a 40x20 box at
// `left: 30px; top: 40px` inside a 400x300 positioned block -- so every
// expected rectangle here is a row of the probe's output. The box's
// laid-out position never changes, so the check is on pixels.
//
// The whole effect is one translation:
//
//     painted top-left = laid-out top-left + P - offset-anchor
//
// where P is the point on the path, in the element's own coordinates
// rather than the containing block's, and the rotation is about the
// point P itself.
//
// `offset-rotate: none` does not appear here, because there is no such
// value: the grammar is `[ auto | reverse ] || <angle>`, and a
// declaration writing `none` is dropped, leaving the initial `auto`.
// The first round of the measurement wrote it as a control and read
// every rotated row as though rotation were off (todo.md records it).
// `0deg` is how rotation is turned off.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color red = 'red'
color blue = 'blue'
color white = 'white'

text mHead = '<!doctype html><body style="margin:0">'
    + '<div style="position:relative;width:400px;height:300px">'

// The moving box: 40x20 red, with a 10x20 blue stripe at its left end,
// so a rotation of 180 degrees is visible where the bounding rectangle
// alone could never show it.
void func shotMoving(style:text) {
    Page p = pageFromHtml(mHead
        + '<div style="position:absolute;left:30px;top:40px;width:40px;height:20px;'
        + 'background:red;' + style + '">'
        + '<div style="width:10px;height:20px;background:blue"></div></div>'
        + '</div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// The painted extent of one colour, as [x, y, w, h]; w is 0 when the
// colour is nowhere, which is how a box painted off the canvas reads.
int mLeft = 0
int mTop = 0
int mW = 0
int mH = 0
void func boundsOf(c:color) {
    int x0 = 9999
    int y0 = 9999
    int x1 = -1
    int y1 = -1
    for int y = 0, y < 300, y++ {
        for int x = 0, x < 400, x++ {
            if getPixelColor(x, y) == c {
                if x < x0 { x0 = x }
                if y < y0 { y0 = y }
                if x > x1 { x1 = x }
                if y > y1 { y1 = y }
            }
        }
    }
    if x1 < 0 { mLeft = 0  mTop = 0  mW = 0  mH = 0  return }
    mLeft = x0
    mTop = y0
    mW = x1 - x0 + 1
    mH = y1 - y0 + 1
}

// The ink of both colours together, which is the whole moving box.
void func inkBounds(style:text) {
    shotMoving(style)
    boundsOf(red)
    int rl = mLeft
    int rt = mTop
    int rr = mLeft + mW
    int rb = mTop + mH
    boundsOf(blue)
    if mW == 0 { mLeft = rl  mTop = rt  mW = rr - rl  mH = rb - rt  return }
    int l = mLeft < rl ? mLeft : rl
    int t = mTop < rt ? mTop : rt
    int r = mLeft + mW > rr ? mLeft + mW : rr
    int b = mTop + mH > rb ? mTop + mH : rb
    mLeft = l  mTop = t  mW = r - l  mH = b - t
}

// Every rectangle is checked to within a pixel, because the engine
// paints on integers and a path point does not land on one.
void func checkRect(style:text, x:int, y:int, w:int, h:int, what:text) {
    inkBounds(style)
    check(mW > 0, what + ': paints something')
    checkNear(mLeft, x, 1, what + ': left')
    checkNear(mTop, y, 1, what + ': top')
    checkNear(mW, w, 1, what + ': width')
    checkNear(mH, h, 1, what + ': height')
}

// ---- the control ---------------------------------------------------------
// Without a path the box paints where it was laid out, and every row
// below has to differ from this one or it is measuring nothing.
checkRect('', 30, 40, 40, 20, 'no offset-path')
checkRect('offset-distance:50px;offset-position:200px 150px', 30, 40, 40, 20,
          'a distance and a position with no path do nothing')

// ---- ray() ---------------------------------------------------------------
// 0deg points up, 90deg right, 180deg down. The ray starts at the
// element's own position unless offset-position moves it.
checkRect('offset-path:ray(90deg);offset-distance:100px;offset-rotate:0deg',
          110, 30, 40, 20, 'ray(90deg) 100px goes right')
checkRect('offset-path:ray(180deg);offset-distance:100px;offset-rotate:0deg',
          10, 130, 40, 20, 'ray(180deg) 100px goes down')
checkRect('offset-position:200px 150px;offset-path:ray(90deg);'
          + 'offset-distance:100px;offset-rotate:0deg',
          310, 180, 40, 20, 'offset-position moves where the ray starts')
checkRect('offset-path:ray(90deg);offset-distance:0px;offset-rotate:0deg',
          10, 30, 40, 20, 'a ray at zero distance still moves the box by -anchor')

// ---- circle(): three o'clock, clockwise ----------------------------------
// The start is the rightmost point, not the top, and the quarters run
// clockwise from it.
text circ = 'offset-path:circle(50px at 100px 100px);offset-rotate:0deg;offset-distance:'
checkRect(circ + '0%', 160, 130, 40, 20, 'a circle starts at three o\'clock')
checkRect(circ + '25%', 110, 180, 40, 20, 'and a quarter along is six o\'clock')
checkRect(circ + '50%', 60, 130, 40, 20, 'half is nine')
checkRect(circ + '75%', 110, 80, 40, 20, 'three quarters is twelve')
checkRect(circ + '12.5%', 145, 165, 40, 20, 'an eighth is forty-five degrees along')
checkRect(circ + '125%', 110, 180, 40, 20, 'and a distance past the end wraps')

// The rectangles above are the proof that the path is in the element's
// own coordinates rather than the containing block's: a circle centred
// at (100, 100) on a box laid out at (30, 40) puts three o'clock at
// (180, 140) on the page and not at (150, 100). A box at the origin
// cannot tell the two apart, which is what the measurement's first
// round got wrong.

// ---- offset-anchor -------------------------------------------------------
// Which point of the box sits on the path. `auto` is the centre.
checkRect(circ + '0%;offset-anchor:0% 0%', 180, 140, 40, 20, 'anchor 0% 0% is the corner')
checkRect(circ + '0%;offset-anchor:100% 100%', 140, 120, 40, 20, 'anchor 100% 100% the far one')
checkRect(circ + '0%;offset-anchor:10px 5px', 170, 135, 40, 20, 'and a length is itself')
// Two ways of saying the centre must agree, which is the check that does
// not depend on either answer being known in advance.
inkBounds(circ + '0%;offset-anchor:50% 50%')
int anchorHalfX = mLeft
inkBounds(circ + '0%')
checkEqInt(anchorHalfX, mLeft, 'offset-anchor: 50% 50% is what auto resolves to')

// ---- polygon(), which closes itself --------------------------------------
text poly = 'offset-path:polygon(0px 0px, 100px 0px, 100px 100px);offset-rotate:0deg;offset-distance:'
checkRect(poly + '0%', 10, 30, 40, 20, 'a polygon starts at its first point')
checkRect(poly + '25%', 95, 30, 40, 20, 'a quarter of 341.42 is along the first edge')
checkRect(poly + '50%', 110, 101, 40, 20, 'half is down the second')
checkRect(poly + '90%', 34, 54, 40, 20, 'and nine tenths is on the closing edge')
checkRect(poly + '100%', 10, 30, 40, 20, 'a full turn is back at the start')

// ---- ellipse() -----------------------------------------------------------
text ell = 'offset-path:ellipse(80px 40px at 100px 100px);offset-rotate:0deg;offset-distance:'
checkRect(ell + '0%', 190, 130, 40, 20, 'an ellipse starts at three o\'clock too')
checkRect(ell + '25%', 110, 170, 40, 20, 'and its quarters are its quarters')
checkRect(ell + '50%', 30, 130, 40, 20, 'half way round')
checkRect(ell + '75%', 110, 90, 40, 20, 'three quarters')
// A circle is an ellipse with two equal radii, and the two must land on
// the same pixel at the same distance however each is worked out.
inkBounds('offset-path:ellipse(50px 50px at 100px 100px);offset-rotate:0deg;offset-distance:37%')
int ellX = mLeft
int ellY = mTop
inkBounds(circ + '37%')
checkEqInt(ellX, mLeft, 'a circle and an equal-radius ellipse agree across')
checkEqInt(ellY, mTop, 'and down')

// ---- path() --------------------------------------------------------------
text pth = 'offset-rotate:0deg;offset-path:'
checkRect(pth + 'path(\'M 0 0 L 200 0\');offset-distance:50%', 110, 30, 40, 20,
          'path() walks a line')
checkRect(pth + 'path(\'M 0 0 H 200 V 100\');offset-distance:50%', 160, 30, 40, 20,
          'H and V are the same line in one axis')
checkRect(pth + 'path(\'M 0 0 L 100 0 L 100 100 Z\');offset-distance:60%', 107, 127, 40, 20,
          'and Z closes it')
// The same outline written two ways must agree at the same distance.
inkBounds(pth + 'path(\'M 0 0 L 100 0 L 100 100 Z\');offset-distance:80%')
int pathX = mLeft
int pathY = mTop
inkBounds(poly + '80%')
checkEqInt(pathX, mLeft, 'a closed path() and the polygon of its points agree across')
checkEqInt(pathY, mTop, 'and down')
// As must a ray and the straight path that traces it.
inkBounds(pth + 'path(\'M 0 0 L 200 0\');offset-distance:50%')
int rayX = mLeft
inkBounds('offset-path:ray(90deg);offset-distance:100px;offset-rotate:0deg')
checkEqInt(rayX, mLeft, 'a ray and the line it draws agree')

// ---- offset-rotate -------------------------------------------------------
// At three o'clock on a clockwise circle the direction is straight down,
// so `auto` turns the 40x20 box on its end.
checkRect('offset-path:circle(50px at 100px 100px);offset-rotate:auto;offset-distance:0%',
          170, 120, 20, 40, 'auto turns the box to face along the path')
checkRect('offset-path:circle(50px at 100px 100px);offset-rotate:auto 90deg;offset-distance:0%',
          160, 130, 40, 20, 'and an angle beside auto adds to it')
// A rotation of 180 degrees leaves the bounding rectangle alone, so the
// blue end of the box is what tells `auto` from `reverse`.
shotMoving('offset-path:circle(50px at 100px 100px);offset-rotate:auto;offset-distance:0%')
boundsOf(blue)
int autoBlueY = mTop
shotMoving('offset-path:circle(50px at 100px 100px);offset-rotate:reverse;offset-distance:0%')
boundsOf(blue)
check(mTop != autoBlueY, 'reverse puts the other end of the box first')
// `reverse` is `auto 180deg`, and the two spellings must agree.
int reverseBlueY = mTop
shotMoving('offset-path:circle(50px at 100px 100px);offset-rotate:auto 180deg;offset-distance:0%')
boundsOf(blue)
checkEqInt(mTop, reverseBlueY, 'reverse is auto 180deg')

// ---- the transform property applies first --------------------------------
// The box is rotated about its own origin and the offset then moves the
// result, so the translation is the full 100px either way.
inkBounds('transform:rotate(90deg);transform-origin:0 0')
int spunLeft = mLeft
inkBounds('offset-path:ray(90deg);offset-distance:100px;offset-rotate:0deg;'
          + 'transform:rotate(90deg);transform-origin:0 0')
checkEqInt(mLeft - spunLeft, 100, 'the offset translates the transformed box')

finish('motion path')
