// CSS Masking 1's `mask`, as pixels.
//
// A mask is per-pixel alpha and this engine cannot read a pixel back.
// It does not need to: `drawImage` honours `fillAlpha`, the clip
// machinery already blits a layer back in pieces, and the alpha of a
// gradient this engine built itself is known without sampling anything.
//
// Most checks below are agreements needing no number -- a uniform
// half-alpha mask must paint what `opacity: 0.5` paints, and a fully
// opaque mask must paint what no mask paints. The rest are the
// geometry, where what is asserted is which pixels are background,
// because "the mask is not here" is `alpha = 0` and that is the
// semantic most easily got backwards.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(200)
setClientHeight(400)

color mkBlue = '#0000ff'
color mkWhite = '#ffffff'
color mkHalf = '#7f7fff'
// Chromium's own answers for `linear-gradient(to right, black,
// transparent)` over this blue, at the first pixel and the midpoint.
color mkNearBlue = '#0101ff'
color mkMid = '#8181ff'
// Chromium's answers for the radial and conic masks below.
color mkRadEdge = '#f2f2ff'
color mkRadMid = '#0707ff'
color mkCircMid = '#0909ff'
color mkConA = '#bfbfff'
color mkConMid = '#6060ff'
color mkConB = '#4040ff'
// Chromium's answers for the two layers and their four composites.
color mkTop8 = '#3333ff'
color mkBot25 = '#bfbfff'
color mkCompAdd = '#2626ff'
color mkCompSub = '#6666ff'
color mkCompInt = '#ccccff'
color mkCompExc = '#5959ff'

// One 100x40 blue box per row, at y = 40*row, on a white page.
text mkRows = ''
void func mkAdd(style:text) {
    mkRows = mkRows + `<div style="width:100px;height:40px;background:#0000ff;${style}"></div>`
}

void func mkPaint() {
    Page p = pageFromHtml('<!doctype html><body style="margin:0;background:#ffffff">'
        + mkRows + '</body>', 'tests/fixtures/page.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 400)
}

color func mkAt(row:int, x:int) { return getPixelColor(x, row * 40 + 20) }

const text GRAD = 'mask-image:linear-gradient(to right, black, transparent)'

mkAdd('')                                                          // 0 plain
mkAdd(GRAD)                                                        // 1
mkAdd('mask-image:linear-gradient(rgba(0,0,0,0.5), rgba(0,0,0,0.5))')  // 2
mkAdd('opacity:0.5')                                               // 3
mkAdd('mask-image:linear-gradient(black, black)')                  // 4
mkAdd('mask-image:linear-gradient(to right, white, black)')        // 5
mkAdd('mask-image:linear-gradient(to right, white, black);mask-mode:luminance') // 6
mkAdd('mask-image:none')                                           // 7
mkAdd(GRAD + ';mask-size:50% 100%;mask-repeat:no-repeat')          // 8
mkAdd(GRAD + ';mask-position:25px 0;mask-repeat:no-repeat')        // 9
mkPaint()

// The instrument. Without this every agreement below could hold between
// two boxes that were never masked at all.
check(mkAt(1, 90) != mkAt(0, 90), 'a masked box does not paint what an unmasked one paints')
check(mkAt(0, 90) == mkBlue, 'and the unmasked one is the plain colour')

// A uniformly half-alpha mask is opacity: 0.5. No number either side.
check(mkAt(2, 50) == mkAt(3, 50), 'a half-alpha mask paints what opacity: 0.5 paints')
check(mkAt(2, 50) == mkHalf, 'which over white is half the blue')

// A fully opaque mask is no mask.
check(mkAt(4, 50) == mkAt(0, 50), 'a fully opaque mask paints what no mask paints')
check(mkAt(7, 50) == mkAt(0, 50), 'and so does mask-image: none')

// The one most easily got backwards: `match-source` reads a CSS image's
// ALPHA, so a white-to-black gradient -- opaque at both ends -- masks
// nothing. Only `luminance` reads the colour.
check(mkAt(5, 10) == mkAt(0, 10), 'a white-to-black gradient masks nothing, at the white end')
check(mkAt(5, 90) == mkAt(0, 90), 'nor at the black end')
check(mkAt(6, 90) != mkAt(0, 90), 'under mask-mode: luminance the black end does mask')
check(mkAt(6, 2) != mkWhite, 'and the white end does not')

// The gradient masks progressively. The two absolutes are Chromium's
// own answers for this gradient over this colour, and this engine
// reproduces both exactly; the left edge is (1,1,255) rather than pure
// blue in BOTH engines, which is what a hundred-pixel ramp does at its
// first pixel.
check(mkAt(1, 0) == mkNearBlue, 'the left of the gradient mask is all but opaque')
check(mkAt(1, 50) == mkMid, 'and half way along it is half gone')
check(mkAt(1, 99) != mkBlue, 'and the right of it has gone')

// Where the mask image is NOT, alpha is zero rather than one.
check(mkAt(8, 2) != mkWhite, 'a half-width mask still covers the left')
check(mkAt(8, 70) == mkWhite, 'and beyond it the box is masked out, not left opaque')
check(mkAt(9, 5) == mkWhite, 'a mask moved 25px right leaves the first 25 masked out')
check(mkAt(9, 30) != mkWhite, 'and covers the box from there')

// ---- mask-origin and mask-clip ----------------------------------------
//
// Both are read against a box with a 10px border and 10px padding, so
// the three boxes are distinct. mask-origin's initial value is the
// BORDER box, which is where it differs from background-origin, and
// that is measured rather than assumed.

Page p2 = pageFromHtml('<!doctype html><body style="margin:0;background:#ffffff">'
    + '<div style="width:60px;height:20px;background:#0000ff;border:10px solid #0000ff;'
    + 'padding:10px;mask-image:linear-gradient(black,black);mask-repeat:no-repeat;'
    + 'mask-size:4px 4px"></div>'
    + '</body>', 'tests/fixtures/page.html', 200)
clearCanvas()
paintPage(p2, 0, 0, 400)
check(getPixelColor(1, 1) == mkBlue, 'mask-origin defaults to the border box')
check(getPixelColor(21, 21) == mkWhite, 'not the content box')

Page p3 = pageFromHtml('<!doctype html><body style="margin:0;background:#ffffff">'
    + '<div style="width:60px;height:20px;background:#0000ff;border:10px solid #0000ff;'
    + 'padding:10px;mask-image:linear-gradient(black,black);mask-repeat:no-repeat;'
    + 'mask-size:4px 4px;mask-origin:content-box"></div>'
    + '</body>', 'tests/fixtures/page.html', 200)
clearCanvas()
paintPage(p3, 0, 0, 400)
check(getPixelColor(1, 1) == mkWhite, 'mask-origin: content-box moves the tile off the border')
check(getPixelColor(21, 21) == mkBlue, 'and onto the content box')

Page p4 = pageFromHtml('<!doctype html><body style="margin:0;background:#ffffff">'
    + '<div style="width:60px;height:20px;background:#0000ff;border:10px solid #0000ff;'
    + 'padding:10px;mask-image:linear-gradient(black,black);mask-clip:content-box"></div>'
    + '</body>', 'tests/fixtures/page.html', 200)
clearCanvas()
paintPage(p4, 0, 0, 400)
check(getPixelColor(1, 1) == mkWhite, 'mask-clip: content-box leaves the border unpainted')
check(getPixelColor(15, 15) == mkWhite, 'and the padding too')
check(getPixelColor(25, 25) == mkBlue, 'while the content box is painted')

// ---- the `mask` shorthand ---------------------------------------------
//
// A shorthand sets every longhand it covers, so the pair below is the
// check that earns its place: the same mask written long and short must
// paint the same pixels, and a `mask` written AFTER a `mask-repeat`
// must reset that repeat rather than leave it standing.

Page p5 = pageFromHtml('<!doctype html><body style="margin:0;background:#ffffff">'
    + '<div style="width:100px;height:40px;background:#0000ff;'
    + "mask-image:linear-gradient(to right, black, transparent);"
    + 'mask-repeat:no-repeat;mask-size:50% 100%"></div>'
    + '<div style="width:100px;height:40px;background:#0000ff;'
    + "mask:linear-gradient(to right, black, transparent) no-repeat 0% 0% / 50% 100%"
    + '"></div>'
    + '</body>', 'tests/fixtures/page.html', 200)
clearCanvas()
paintPage(p5, 0, 0, 400)
check(getPixelColor(2, 20) == getPixelColor(2, 60), 'the shorthand paints what the longhands paint, at the left')
check(getPixelColor(30, 20) == getPixelColor(30, 60), 'in the middle')
check(getPixelColor(70, 20) == getPixelColor(70, 60), 'and past the end of the tile')
check(getPixelColor(70, 20) == mkWhite, 'where both are masked out')

// ---- radial and conic gradient masks ----------------------------------
//
// Both are computed the way the linear one is, each with its own
// projection from a pixel to the gradient's parameter. The check that
// earns its place is the circle with a radius: a 20px circle centred at
// (50, 20) must leave the columns 25 pixels either side FULLY
// transparent, so an implementation that resolved no radius and covered
// the box fails on white against white rather than on two shades of
// blue.

mkRows = ''
mkAdd('mask-image:radial-gradient(closest-side, black, transparent)')       // 0
mkAdd('mask-image:radial-gradient(circle 20px at 50px 20px, black, transparent)') // 1
mkAdd('mask-image:conic-gradient(black, transparent)')                      // 2
mkAdd('')                                                                   // 3 plain
mkPaint()

check(mkAt(1, 25) == mkWhite, 'a 20px circle mask leaves x=25 fully transparent')
check(mkAt(1, 75) == mkWhite, 'and x=75 too')
check(mkAt(1, 50) != mkWhite, 'while its centre is painted')
check(mkAt(1, 50) != mkAt(3, 50), 'and is not simply the unmasked colour')

check(mkAt(0, 50) != mkWhite, 'a closest-side radial mask paints its centre')
check(mkAt(0, 2) != mkAt(0, 50), 'and fades away from it')
check(mkAt(0, 2) != mkAt(1, 2), 'closest-side is not the 20px circle')

check(mkAt(2, 2) != mkWhite, 'a conic mask paints somewhere')
check(mkAt(2, 2) != mkAt(2, 98), 'and sweeps, so two columns differ')
check(mkAt(2, 50) != mkAt(3, 50), 'and it is not the unmasked colour')

// And the absolutes. All fifteen pixels of the three masks match
// Chromium 141 exactly; these six are the ones a wrong projection could
// not pass by accident -- a centre and an edge of each shape.
check(mkAt(0, 2) == mkRadEdge, 'closest-side radial: Chromium at x=2')
check(mkAt(0, 50) == mkRadMid, 'and at its centre')
check(mkAt(1, 50) == mkCircMid, 'the 20px circle at its centre')
check(mkAt(2, 2) == mkConA, 'conic at x=2')
check(mkAt(2, 50) == mkConMid, 'at x=50')
check(mkAt(2, 98) == mkConB, 'and at x=98')

// ---- mask-composite, and a second layer -------------------------------
//
// Two flat layers, the top at alpha 0.8 and the one below at 0.25, each
// operator combining them. The absolutes are Chromium's own answers.
//
// A quarter below rather than a half, deliberately: `subtract` is
// `as * (1 - ad)` and `intersect` is `as * ad`, which are the SAME
// number when `ad` is a half. A test written with 0.5 would pass on an
// engine that confused the two.

const text TOP = 'linear-gradient(rgba(0,0,0,0.8), rgba(0,0,0,0.8))'
const text BOT = 'linear-gradient(rgba(0,0,0,0.25), rgba(0,0,0,0.25))'

mkRows = ''
mkAdd(`mask-image:${TOP}, ${BOT};mask-composite:add, add`)          // 0
mkAdd(`mask-image:${TOP}, ${BOT};mask-composite:subtract, add`)     // 1
mkAdd(`mask-image:${TOP}, ${BOT};mask-composite:intersect, add`)    // 2
mkAdd(`mask-image:${TOP}, ${BOT};mask-composite:exclude, add`)      // 3
mkAdd(`mask-image:${TOP}`)                                          // 4
mkAdd(`mask-image:${BOT}`)                                          // 5
mkPaint()

check(mkAt(4, 50) == mkTop8, 'the top layer alone is alpha 0.8')
check(mkAt(5, 50) == mkBot25, 'and the one below it alpha 0.25')

check(mkAt(0, 50) == mkCompAdd, 'add')
check(mkAt(1, 50) == mkCompSub, 'subtract')
check(mkAt(2, 50) == mkCompInt, 'intersect')
check(mkAt(3, 50) == mkCompExc, 'exclude')

// The four must be four different answers, which is what a second layer
// combined by the wrong operator -- or ignored altogether -- fails.
check(mkAt(0, 50) != mkAt(1, 50), 'add is not subtract')
check(mkAt(1, 50) != mkAt(2, 50), 'subtract is not intersect')
check(mkAt(2, 50) != mkAt(3, 50), 'intersect is not exclude')
check(mkAt(0, 50) != mkAt(4, 50), 'and none of them is the top layer alone')

finish('mask')
