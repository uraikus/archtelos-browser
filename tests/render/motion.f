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

// ---- the curve commands ------------------------------------------------

// `path()` read only straight lines until now, stopping at the first
// curve. Every point below is Chromium's, in todo.md.
//
// Each path starts at y = 60 rather than at the origin, because the
// fixture's box sits 40 pixels from the top of the canvas and the arcs
// and the smooth curves go *up*: measured from y = 0 their upper halves
// fall off the canvas, and `boundsOf` then reports where the ink was
// clipped rather than where the box is. The first version of these
// checks read -30 for every one of them, which is the canvas edge and
// not a curve.
//
// Each path is measured against its own 0% point, so the fixture's
// laid-out position never enters the arithmetic.

int curveX = 0
int curveY = 0
void func pointAt(d:text, path:text) {
    inkBounds(`offset-path:path('${path}');offset-distance:${d};offset-rotate:0deg`)
    curveX = mLeft
    curveY = mTop
}

int curveOriginX = 0
int curveOriginY = 0
void func originOf(path:text) {
    pointAt('0%', path)
    curveOriginX = curveX
    curveOriginY = curveY
}

// A straight path is the control: its half-way point is its middle.
originOf('M 0 60 L 100 60')
check(curveOriginY > 60, 'the box is on the canvas at the start of a path')
pointAt('50%', 'M 0 60 L 100 60')
checkNear(curveX - curveOriginX, 50, 1, 'half way along a straight 100px path is 50 across')
checkNear(curveY - curveOriginY, 0, 1, 'and nowhere down')

// A cubic: 0,0 / 11,48 / 50,75 / 89,48 / 100,0 from its start.
text CUBIC = 'M 0 60 C 0 160 100 160 100 60'
originOf(CUBIC)
pointAt('25%', CUBIC)
checkNear(curveX - curveOriginX, 11, 2, 'a quarter along the cubic is 11 across')
checkNear(curveY - curveOriginY, 48, 2, 'and 48 down')
pointAt('50%', CUBIC)
checkNear(curveX - curveOriginX, 50, 2, 'half way is 50 across')
checkNear(curveY - curveOriginY, 75, 2, 'and 75 down, which is not the control point')
pointAt('100%', CUBIC)
checkNear(curveX - curveOriginX, 100, 2, 'and the end is the end point')
checkNear(curveY - curveOriginY, 0, 2, 'back on the axis')

// The relative form is the same curve, which needs neither point known.
pointAt('25%', CUBIC)
int absX = curveX
int absY = curveY
pointAt('25%', 'M 0 60 c 0 100 100 100 100 0')
checkEqInt(curveX, absX, 'a relative cubic is the same curve, across')
checkEqInt(curveY, absY, 'and down')

// A quadratic: 0,0 / 19,31 / 50,50 / 81,31 / 100,0.
text QUAD = 'M 0 60 Q 50 160 100 60'
originOf(QUAD)
pointAt('25%', QUAD)
checkNear(curveX - curveOriginX, 19, 2, 'a quarter along the quadratic is 19 across')
checkNear(curveY - curveOriginY, 31, 2, 'and 31 down')
pointAt('50%', QUAD)
checkNear(curveY - curveOriginY, 50, 2, 'half way is 50 down, half of its control point')

// `S` reflects the previous cubic's second control point, so the path
// is symmetric about its middle: as far above the axis in the second
// half as below it in the first. That symmetry is the check that does
// not depend on either half being known.
text SMOOTH = 'M 0 60 C 0 110 50 110 50 60 S 100 10 100 60'
originOf(SMOOTH)
pointAt('25%', SMOOTH)
int sDown = curveY - curveOriginY
pointAt('75%', SMOOTH)
int sUp = curveY - curveOriginY
checkNear(sDown, 38, 2, 'a quarter along the smooth cubic is 38 down')
checkNear(sUp, 0 - sDown, 2, 'and three quarters along is as far up, by reflection')
pointAt('50%', SMOOTH)
checkNear(curveY - curveOriginY, 0, 2, 'with the join itself on the axis')

// `T` reflects the previous quadratic's control point the same way.
text TSMOOTH = 'M 0 60 Q 25 110 50 60 T 100 60'
originOf(TSMOOTH)
pointAt('25%', TSMOOTH)
int tDown = curveY - curveOriginY
pointAt('75%', TSMOOTH)
checkNear(tDown, 25, 2, 'a quarter along the smooth quadratic is 25 down')
checkNear(curveY - curveOriginY, 0 - tDown, 2, 'and three quarters as far up')

// An arc. A chord of 100 with a radius of 50 is exactly a semicircle,
// so the sweep flag alone decides which side of the chord it takes --
// and the two are mirror images, which again needs neither known.
text ARCUP = 'M 0 60 A 50 50 0 0 1 100 60'
text ARCDOWN = 'M 0 60 A 50 50 0 1 0 100 60'
originOf(ARCUP)
pointAt('50%', ARCUP)
int arcUp = curveY - curveOriginY
pointAt('25%', ARCUP)
checkNear(curveX - curveOriginX, 15, 2, 'a quarter along the arc is 15 across')
checkNear(curveY - curveOriginY, 0 - 35, 2, 'and 35 up')
originOf(ARCDOWN)
pointAt('50%', ARCDOWN)
int arcDown = curveY - curveOriginY
checkNear(arcUp, 0 - 50, 2, 'the top of the sweeping arc is 50 up')
checkNear(arcDown, 0 - arcUp, 2, 'and the other sweep is its mirror')

// ---- more than one subpath ---------------------------------------------

// A second `M` used to end the path. The length is the sum of the
// subpaths and the distance walks them in order with nothing joining
// them, so the point at half way along two equal legs is the end of the
// first and not somewhere between the two.

text TWO = 'M 0 60 L 100 60 M 0 160 L 100 160'
originOf(TWO)
pointAt('50%', TWO)
checkNear(curveX - curveOriginX, 100, 2, 'half way along two equal subpaths is the end of the first')
checkNear(curveY - curveOriginY, 0, 2, 'still on the first subpath, not between them')
pointAt('75%', TWO)
checkNear(curveX - curveOriginX, 50, 2, 'three quarters is half way along the second')
checkNear(curveY - curveOriginY, 100, 2, 'a hundred further down')
pointAt('100%', TWO)
checkNear(curveX - curveOriginX, 100, 2, 'and the end is the end of the second')
checkNear(curveY - curveOriginY, 100, 2, 'down there')

// Unequal legs put the arithmetic in the open: 100 and 50 make 150, so
// half of it is 75 along the first.
text UNEVEN = 'M 0 60 L 100 60 M 0 160 L 50 160'
originOf(UNEVEN)
pointAt('50%', UNEVEN)
checkNear(curveX - curveOriginX, 75, 2, 'half of 150 is 75 along the first subpath')
checkNear(curveY - curveOriginY, 0, 2, 'which is still the first')

// `Z` closes the subpath it is in, so the first is 200 long -- out and
// back -- and the whole path 300.
text ZSUB = 'M 0 60 L 100 60 Z M 0 160 L 100 160'
originOf(ZSUB)
pointAt('150px', ZSUB)
checkNear(curveX - curveOriginX, 50, 2, 'past the turn, 150 is half way back along the return leg')
checkNear(curveY - curveOriginY, 0, 2, 'on the first subpath still')
pointAt('50%', ZSUB)
checkNear(curveX - curveOriginX, 50, 2, 'and half of 300 lands in the same place')

// A path of more than one subpath clamps at its ends, where a single
// closed one wraps. The two rows disagree at the same distance, which
// is the check: 400 is past the end of both.
pointAt('400px', ZSUB)
checkNear(curveX - curveOriginX, 100, 2, 'a multi-subpath path clamps at its end')
checkNear(curveY - curveOriginY, 100, 2, 'on the last subpath')
text ONECLOSED = 'M 0 60 L 100 60 Z'
originOf(ONECLOSED)
pointAt('400px', ONECLOSED)
checkNear(curveX - curveOriginX, 0, 2, 'while one closed subpath wraps, 400 of 200 being 0')
pointAt('150px', ONECLOSED)
checkNear(curveX - curveOriginX, 50, 2, 'and 150 of it is half way back')

// A second coordinate pair after `M` is a line, not another move, so
// the two spellings are one path -- which needs neither point known.
text IMPLICIT = 'M 0 60 100 60'
text EXPLICIT = 'M 0 60 L 100 60'
originOf(IMPLICIT)
pointAt('50%', IMPLICIT)
int impX = curveX
int impY = curveY
originOf(EXPLICIT)
pointAt('50%', EXPLICIT)
checkEqInt(impX, curveX, 'a pair after M is a line, so the two spellings agree across')
checkEqInt(impY, curveY, 'and down')

// ---- offset-path: url() (CSS Motion Path 1 §2.1) -----------------------
//
// `url(#p)` names an SVG `<path>` and travels its `d` attribute. The
// path is never drawn -- this engine renders no SVG -- but the element
// is in the DOM with its attributes, which is all a reference needs.
//
// Every check is an agreement between the two spellings of one path
// rather than a coordinate written down here. Chromium 141 puts a 10px
// box at `offset-distance: 50%` in the same place for both, and puts a
// reference that resolves to nothing somewhere neither `none` nor the
// path is (todo.md).

text mSvg = '<svg width="0" height="0">'
    + '<path id="p" d="M 0 60 L 100 60"/>'
    + '<path id="nod"/>'
    + '<circle id="circ" cx="50" cy="60" r="40"/>'
    + '<ellipse id="ell" cx="50" cy="60" rx="40" ry="20"/>'
    + '<polygon id="poly" points="0,60 100,60 100,110"/></svg>'

// The same page `shotMoving` builds, with an SVG the reference can find
// and a plain div it can wrongly find.
void func shotReferenced(style:text) {
    Page p = pageFromHtml(mHead + mSvg + '<div id="adiv"></div>'
        + '<div style="position:absolute;left:30px;top:40px;width:40px;height:20px;'
        + 'background:red;' + style + '">'
        + '<div style="width:10px;height:20px;background:blue"></div></div>'
        + '</div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

int refX = 0
int refY = 0
void func refAt(style:text) {
    shotReferenced(style)
    boundsOf(red)
    int rl = mLeft
    int rt = mTop
    boundsOf(blue)
    refX = mW == 0 ? rl : (mLeft < rl ? mLeft : rl)
    refY = mW == 0 ? rt : (mTop < rt ? mTop : rt)
}

int urlX = 0
int urlY = 0
void func keepRef() { urlX = refX  urlY = refY }

// The instrument first: the path has to move the box, or every
// agreement below holds between two boxes that never went anywhere.
refAt(`offset-path:path('M 0 60 L 100 60');offset-distance:0%;offset-rotate:0deg`)
keepRef()
refAt(`offset-path:path('M 0 60 L 100 60');offset-distance:50%;offset-rotate:0deg`)
check(refX != urlX, 'a path at 50% is not a path at 0%')

// The agreement: the two spellings of one path land on one pixel.
refAt('offset-path:url(#p);offset-distance:50%;offset-rotate:0deg')
keepRef()
refAt(`offset-path:path('M 0 60 L 100 60');offset-distance:50%;offset-rotate:0deg`)
checkEqInt(urlX, refX, 'url(#p) travels the element\'s d, across')
checkEqInt(urlY, refY, 'and down')

refAt('offset-path:url(#p);offset-distance:0%;offset-rotate:0deg')
keepRef()
refAt(`offset-path:path('M 0 60 L 100 60');offset-distance:0%;offset-rotate:0deg`)
checkEqInt(urlX, refX, 'and agrees at the start of the path too')
checkEqInt(urlY, refY, 'in both axes')

// A reference that resolves to nothing is an EMPTY path, not `none`.
// Measured against Chromium, which puts the box on the path's single
// point at the origin rather than leaving it where the flow did.
refAt('offset-path:url(#nosuch);offset-distance:50%;offset-rotate:0deg')
keepRef()
refAt('offset-path:url(#nod);offset-distance:50%;offset-rotate:0deg')
checkEqInt(urlX, refX, 'a missing element and a d-less path agree, across')
checkEqInt(urlY, refY, 'and down')

refAt('offset-path:url(#adiv);offset-distance:50%;offset-rotate:0deg')
checkEqInt(urlX, refX, 'and so does an element that is not a path')

refAt('offset-distance:50%;offset-rotate:0deg')
check(refX != urlX || refY != urlY,
    'a reference that resolves to nothing is not the same as no offset-path')

// ---- a url() naming an SVG shape rather than a <path> ------------------
//
// Chromium resolves five geometry elements besides `<path>`, and three
// of them are shapes this engine's motion code already travels. Each
// check is the SVG spelling against the CSS function of the same
// geometry: measured in Chromium at `offset-distance: 50%`, a `<circle>`
// lands where `circle()` lands, an `<ellipse>` where `ellipse()` does,
// and a `<polygon>` where `polygon()` does (todo.md). No coordinate is
// written down here, and a shape resolved to the wrong centre, the wrong
// radius or the wrong winding fails immediately.
//
// `<rect>`, `<line>` and `<polyline>` are not here: a rect needs a
// rectangle path this engine does not travel, and the other two are open
// where a `polygon()` closes itself. todo.md has the measurements.

// The instrument: a curved path has to move the box, or the agreements
// below hold between two boxes that never went anywhere.
refAt('offset-path:circle(40px at 50px 60px);offset-distance:0%;offset-rotate:0deg')
keepRef()
refAt('offset-path:circle(40px at 50px 60px);offset-distance:50%;offset-rotate:0deg')
check(refX != urlX, 'a circle at 50% is not a circle at 0%')

refAt('offset-path:url(#circ);offset-distance:50%;offset-rotate:0deg')
keepRef()
refAt('offset-path:circle(40px at 50px 60px);offset-distance:50%;offset-rotate:0deg')
checkEqInt(urlX, refX, 'url() naming a <circle> is circle(), across')
checkEqInt(urlY, refY, 'and down')

refAt('offset-path:url(#circ);offset-distance:25%;offset-rotate:0deg')
keepRef()
refAt('offset-path:circle(40px at 50px 60px);offset-distance:25%;offset-rotate:0deg')
checkEqInt(urlX, refX, 'and a quarter of the way round, across')
checkEqInt(urlY, refY, 'and down')

refAt('offset-path:url(#ell);offset-distance:50%;offset-rotate:0deg')
keepRef()
refAt('offset-path:ellipse(40px 20px at 50px 60px);offset-distance:50%;offset-rotate:0deg')
checkEqInt(urlX, refX, 'url() naming an <ellipse> is ellipse(), across')
checkEqInt(urlY, refY, 'and down')

refAt('offset-path:url(#poly);offset-distance:50%;offset-rotate:0deg')
keepRef()
refAt(`offset-path:polygon(0px 60px, 100px 60px, 100px 110px);offset-distance:50%;offset-rotate:0deg`)
checkEqInt(urlX, refX, 'url() naming a <polygon> is polygon(), across')
checkEqInt(urlY, refY, 'and down')

finish('motion path')
