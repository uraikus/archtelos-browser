// CSS Images 3, linear gradients, checked in pixels against Chromium 141.
//
// Every expected colour was read out of Chromium by painting the same
// gradient and calling getImageData, so these are that engine's numbers
// and not a derivation of what this one does.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(600)

// A `color` cannot be decomposed, printed, or built from numbers at run
// time in Festina -- it compares equal or it does not (FINDINGS.md, "a
// color is opaque"). Tolerance still matters here, because Skia dithers
// gradients and so disagrees with Cairo by a unit or two.
//
// The way through is that `fillStyle` does take runtime numbers: paint a
// candidate colour into a scratch pixel, read it back, and compare the
// two colours. Trying every candidate within the tolerance turns "is
// this pixel about right" into a question the language can answer.
const int SCRATCH_X = 399
const int SCRATCH_Y = 599

bool func pixelIs(x:int, y:int, r:int, g:int, b:int) {
    color want = getPixelColor(x, y)
    fillStyle(r, g, b)
    drawRect(SCRATCH_X, SCRATCH_Y, 1, 1)
    return getPixelColor(SCRATCH_X, SCRATCH_Y) == want
}

void func checkPixel(x:int, y:int, r:int, g:int, b:int, label:text) {
    int tol = 3
    for int dr = 0 - tol, dr <= tol, dr++ {
        for int dg = 0 - tol, dg <= tol, dg++ {
            for int db = 0 - tol, db <= tol, db++ {
                if pixelIs(x, y, r + dr, g + dg, b + db) {
                    checksPassed++
                    return
                }
            }
        }
    }
    checksFailed++
    log(`FAIL: ${label}: no colour within ${tol} of ${r},${g},${b} at ${x},${y}`)
}

text head = '<!doctype html><body style="margin:0">'

// ---- two stops, left to right ----------------------------------------
Page p1 = pageFromHtml(head + '<div style="width:200px;height:100px;background:linear-gradient(to right, #ff0000, #0000ff)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p1, 0, 0, 300)
checkPixel(10, 50, 241, 0, 13, 'to right: near the start is nearly red')
checkPixel(100, 50, 127, 0, 128, 'to right: the middle is half and half')
checkPixel(190, 50, 12, 0, 243, 'to right: near the end is nearly blue')

// ---- two stops, top to bottom ----------------------------------------
Page p2 = pageFromHtml(head + '<div style="width:200px;height:100px;background:linear-gradient(to bottom, #ff0000, #00ff00)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p2, 0, 0, 300)
checkPixel(100, 50, 126, 128, 0, 'to bottom: the middle is half and half')
checkPixel(10, 50, 126, 128, 0, 'to bottom: and does not vary across the box')
checkPixel(190, 50, 126, 128, 0, 'at any x')

// ---- three stops -----------------------------------------------------
// The middle stop is what Festina's two-stop primitive cannot express,
// so this is the case the banding exists for.
Page p3 = pageFromHtml(head + '<div style="width:200px;height:100px;background:linear-gradient(to right, #ff0000 0%, #ffffff 50%, #0000ff 100%)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p3, 0, 0, 300)
checkPixel(10, 50, 255, 26, 26, 'three stops: the first band runs red to white')
checkPixel(100, 50, 253, 253, 255, 'three stops: the middle stop is white')
checkPixel(190, 50, 24, 24, 255, 'three stops: the second band runs white to blue')

// ---- an angle --------------------------------------------------------
// 90deg points to the right in CSS, where 0deg points up.
Page p4 = pageFromHtml(head + '<div style="width:200px;height:100px;background:linear-gradient(90deg, #000000, #ffffff)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p4, 0, 0, 300)
checkPixel(10, 50, 13, 13, 13, '90deg: near the start is nearly black')
checkPixel(100, 50, 128, 128, 128, '90deg: the middle is grey')
checkPixel(190, 50, 242, 242, 242, '90deg: near the end is nearly white')

// ---- a gradient is a background, so the box still has its geometry ----
Page p5 = pageFromHtml(head + '<div style="width:100px;height:40px;background:linear-gradient(to right, #ff0000, #ff0000)"></div><div style="width:100px;height:40px;background:#00ff00"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p5, 0, 0, 300)
checkPixel(50, 20, 255, 0, 0, 'a gradient fills its own box')
checkPixel(50, 60, 0, 255, 0, 'and the next box is where it should be')
checkPixel(150, 20, 255, 255, 255, 'and it does not paint outside its width')

// ---- an off-axis angle -----------------------------------------------
// 135deg points down and to the right, so on a square box the gradient
// line runs corner to corner. This is the case Festina's canvas cannot
// help with at all: no clip region, so each band is built as the
// polygon where it meets the box.
Page p6 = pageFromHtml(head + '<div style="width:200px;height:200px;background:linear-gradient(135deg, #ff0000, #0000ff)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p6, 0, 0, 400)
checkPixel(20, 20, 228, 0, 26, '135deg: the top-left corner is near the start')
checkPixel(100, 100, 126, 0, 128, '135deg: the centre is halfway')
checkPixel(180, 180, 24, 0, 230, '135deg: the bottom-right corner is near the end')

// ---- repeating -------------------------------------------------------
Page p7 = pageFromHtml(head + '<div style="width:200px;height:100px;background:repeating-linear-gradient(to right, #ff0000 0px, #0000ff 50px)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p7, 0, 0, 300)
checkPixel(10, 50, 201, 0, 53, 'repeating: a fifth into the first band')
checkPixel(40, 50, 48, 0, 206, 'repeating: four fifths into it')
checkPixel(60, 50, 201, 0, 53, 'repeating: and the pattern starts over')
checkPixel(110, 50, 201, 0, 53, 'repeating: in every band')

// ---- an off-axis gradient must be smooth, not stippled ---------------
// An earlier version drew each band as a polygon whose vertices had to
// be whole pixels, so abutting diagonal slivers were anti-aliased
// against each other and the ramp came out stippled. A 400x300 gradient
// came out as a 77 KB PNG, which a smooth ramp never is.
//
// Sampled values do not catch that, and it is worth being clear about
// why: every check below this comment passes on the stippled rendering
// too, because the stipple is a perturbation of a couple of units and
// the tolerance here is three. What catches it is counting how often
// neighbouring pixels are the *same* colour, further down.
Page p8 = pageFromHtml(head + '<div style="width:400px;height:300px;background:linear-gradient(37deg, #ff0000, #0000ff)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p8, 0, 0, 400)
checkPixel(100, 150, 159, 0, 95, 'off-axis run: x=100')
checkPixel(101, 150, 160, 0, 96, 'off-axis run: x=101')
checkPixel(102, 150, 158, 0, 96, 'off-axis run: x=102')
checkPixel(103, 150, 159, 0, 97, 'off-axis run: x=103')
checkPixel(104, 150, 158, 0, 96, 'off-axis run: x=104')
checkPixel(105, 150, 158, 0, 98, 'off-axis run: x=105')
checkPixel(106, 150, 157, 0, 97, 'off-axis run: x=106')
checkPixel(107, 150, 158, 0, 98, 'off-axis run: x=107')
checkPixel(200, 150, 127, 0, 127, 'off-axis: the centre is halfway')
checkPixel(50, 50, 133, 0, 121, 'off-axis: above the centre line')
checkPixel(350, 250, 122, 0, 133, 'off-axis: below it')

// The real check. A smooth ramp advances less than one colour level per
// pixel, so most neighbours are identical; stipple makes nearly every
// neighbour differ. Measured on this gradient: 245 of 360 adjacent
// pairs equal when it is drawn correctly, 147 when it is stippled. This
// is the only check in this file that distinguishes the two, and it
// needs nothing but colour equality, which is all Festina offers.
int func equalNeighbours(y:int, fromX:int, toX:int) {
    int same = 0
    for int x = fromX, x < toX, x++ {
        if getPixelColor(x, y) == getPixelColor(x + 1, y) { same++ }
    }
    return same
}

check(equalNeighbours(20, 20, 380) > 200, 'off-axis: the top of the ramp is smooth, not stippled')
check(equalNeighbours(150, 20, 380) > 200, 'off-axis: and the middle')
check(equalNeighbours(280, 20, 380) > 200, 'off-axis: and the bottom')

int sameDown = 0
for int y = 20, y < 279, y++ {
    if getPixelColor(200, y) == getPixelColor(200, y + 1) { sameDown++ }
}
check(sameDown > 130, 'off-axis: and down a column as well')

// ---- interpolation hints (CSS Images 3 §3.4.4) ------------------------
// A bare position between two colour stops is not a stop: it says where
// the colour is halfway between them, and the interpolation either side
// follows the standard's curve --
//
//     weight = P ^ (log 0.5 / log H)
//
// for P the fraction of the way between the two stops and H the hint's
// own fraction. Every number below comes from that formula rather than
// from another browser, because Chromium cannot supply pixels here; the
// numbers are the same arithmetic the code does, so what the checks
// really assert is the *shape*: the hint drags the midpoint to itself
// and bends the ramp either side of it.
//
// In a 100px box, `red, 25%, blue`:
//
//   x = 10   172, 0, 83      x = 25   126, 0, 129     the average colour
//   x = 50    74, 0, 181     x = 75    33, 0, 222
//
// without the hint the same points are 228/190/126/62 red.

Page ph = pageFromHtml(head + '<div style="width:100px;height:40px;background:'
    + 'linear-gradient(to right, #ff0000, 25%, #0000ff)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(ph, 0, 0, 200)
checkPixel(25, 20, 126, 0, 129, 'a hint at 25% puts the average colour a quarter along')
checkPixel(10, 20, 172, 0, 83, 'the ramp before it is bent towards the second colour')
checkPixel(50, 20, 74, 0, 181, 'and the ramp after it is bent away')
checkPixel(75, 20, 33, 0, 222, 'all the way to the end')

// A hint at three quarters bends it the other way.
Page ph2 = pageFromHtml(head + '<div style="width:100px;height:40px;background:'
    + 'linear-gradient(to right, #ff0000, 75%, #0000ff)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(ph2, 0, 0, 200)
checkPixel(75, 20, 125, 0, 130, 'a hint at 75% puts the average colour three quarters along')
checkPixel(25, 20, 246, 0, 9, 'holding the first colour most of the way')
checkPixel(50, 20, 206, 0, 49, 'past the point the unhinted ramp is half and half')

// A hint exactly halfway is no hint at all: the two must agree. This is
// the check that does not depend on the formula being right.
Page ph3 = pageFromHtml(head + '<div style="width:100px;height:40px;background:'
    + 'linear-gradient(to right, #ff0000, 50%, #0000ff)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(ph3, 0, 0, 200)
checkPixel(25, 20, 190, 0, 65, 'a hint at the midpoint leaves the ramp where it was')
checkPixel(50, 20, 126, 0, 129, 'half and half in the middle')
checkPixel(75, 20, 62, 0, 193, 'and unbent at the far end')

// A hint belongs between the two stops it sits between, so one in a
// three-stop gradient bends only its own half.
Page ph4 = pageFromHtml(head + '<div style="width:100px;height:40px;background:'
    + 'linear-gradient(to right, #ff0000, #ffffff 50%, 87.5%, #0000ff)"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(ph4, 0, 0, 200)
checkPixel(25, 20, 255, 130, 130, 'the half before the hint is the ordinary ramp')
checkPixel(88, 20, 119, 119, 255, 'and the hint bends only the half it sits in')

finish('gradients')
