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

finish('mask')
