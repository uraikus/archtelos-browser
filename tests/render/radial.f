// `radial-gradient()` and `repeating-radial-gradient()`
// (CSS Images 3 §3.4.2).
//
// The ground truth is the specification's sizing algorithm, not another
// browser's pixels: headless Chromium in this container paints only the
// first scanline of a screenshot (todo.md records the evidence), so the
// linear-gradient suite's method of reading Chromium's own colours out
// with getImageData is not available here.
//
// What makes that sound is the gradient used throughout:
//
//     red 0%, red 50%, blue 50%, blue 100%
//
// Two hard stops, so the result is a flat red region inside half the
// gradient ray and flat blue outside it, with no interpolation anywhere.
// The colours are then exact -- no tolerance, no dithering to allow for
// -- and every check is really a question about *where the boundary
// is*, which is the whole content of the sizing algorithm. Each one
// names the radius it implies.
//
// The gradient is painted as concentric bands, so the boundary lands
// within about a pixel of its true position; samples stay at least
// three pixels clear of it on either side.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(400)

color red = 'red'
color blue = 'blue'

text stops = 'red 0%, red 50%, blue 50%, blue 100%'
text head = '<!doctype html><body style="margin:0;font:16px/20px monospace">'

void func paint(w:int, h:int, image:text) {
    Page p = pageFromHtml(head + '<div style="width:' + w.toText() + 'px;height:'
        + h.toText() + 'px;background-image:' + image + '"></div></body>',
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
}

// ---- the default: ellipse farthest-corner at the centre ---------------
// In a 100x100 box the centre is (50,50) and the farthest corner is
// 50*sqrt(2) = 70.7 away, so the ray is 70.7 long and the boundary sits
// at 35.4 from the centre.
paint(100, 100, 'radial-gradient(' + stops + ')')
check(getPixelColor(50, 50) == red, 'the centre of a radial gradient is its first stop')
check(getPixelColor(50, 20) == red, '30 from the centre is inside the 35.4 boundary')
check(getPixelColor(50, 10) == blue, '40 from the centre is outside it')
check(getPixelColor(20, 50) == red, 'and the same along the other axis, inside')
check(getPixelColor(10, 50) == blue, 'and outside -- a square box makes the default a circle')
check(getPixelColor(2, 2) == blue, 'the corner is the last stop, which farthest-corner reaches')
check(getPixelColor(97, 97) == blue, 'at every corner')

// ---- circle closest-side ----------------------------------------------
// In a 100x60 box the centre is (50,30); the nearest side is 30 away, so
// a circle closest-side has radius 30 and the boundary sits at 15.
paint(100, 60, 'radial-gradient(circle closest-side, ' + stops + ')')
check(getPixelColor(50, 30) == red, 'circle closest-side: the centre is the first stop')
check(getPixelColor(50, 20) == red, '10 above the centre is inside the 15 boundary')
check(getPixelColor(50, 10) == blue, '20 above it is outside')
check(getPixelColor(40, 30) == red, '10 to the left is inside')
check(getPixelColor(30, 30) == blue, '20 to the left is outside -- a circle, so both axes agree')

// ---- ellipse closest-side ---------------------------------------------
// The same box, but the ellipse takes each axis separately: rx is the 50
// to the nearest vertical side and ry the 30 to the nearest horizontal
// one, so the boundary is 25 across and 15 down.
paint(100, 60, 'radial-gradient(ellipse closest-side, ' + stops + ')')
check(getPixelColor(70, 30) == red, 'ellipse closest-side: 20 across is inside the 25 boundary')
check(getPixelColor(80, 30) == blue, '30 across is outside it')
check(getPixelColor(50, 40) == red, '10 down is inside the 15 boundary')
check(getPixelColor(50, 50) == blue, '20 down is outside it')
check(getPixelColor(70, 40) == blue, 'and the corner between them is outside both')

// ---- the shape keyword is what separates those two --------------------
// A circle in the same box takes the smaller radius on both axes, so the
// point that was inside the ellipse is outside the circle.
paint(100, 60, 'radial-gradient(circle closest-side, ' + stops + ')')
check(getPixelColor(70, 30) == blue, 'a circle in the same box puts 20 across outside')

// ---- farthest-side ----------------------------------------------------
// Centre (25,30) in a 100x60 box: the farthest vertical side is 75 away,
// so a circle farthest-side has radius 75 and the boundary is at 37.5.
paint(100, 60, 'radial-gradient(circle farthest-side at 25% 50%, ' + stops + ')')
check(getPixelColor(25, 30) == red, 'farthest-side: the centre is where `at` put it')
check(getPixelColor(55, 30) == red, '30 across is inside the 37.5 boundary')
check(getPixelColor(70, 30) == blue, '45 across is outside it')

// ---- at <position> ----------------------------------------------------
// Centre (25,25) in a 100x100 box: the nearest side is 25 away, so a
// circle closest-side has radius 25 and the boundary is at 12.5.
paint(100, 100, 'radial-gradient(circle closest-side at 25% 25%, ' + stops + ')')
check(getPixelColor(25, 25) == red, 'at 25% 25% moves the centre there')
check(getPixelColor(25, 33) == red, '8 below it is inside the 12.5 boundary')
check(getPixelColor(25, 42) == blue, '17 below it is outside')
check(getPixelColor(50, 50) == blue, 'and the middle of the box is well outside')

// ---- a keyword position ------------------------------------------------
// Centred on the corner, the farthest side is the whole 100 away, so the
// radius is 100 and the boundary is at 50.
paint(100, 100, 'radial-gradient(circle farthest-side at left top, ' + stops + ')')
check(getPixelColor(2, 2) == red, '`at left top` puts the centre in the corner')
check(getPixelColor(30, 30) == red, '42 out is inside the 50 boundary')
check(getPixelColor(60, 60) == blue, '85 out is beyond it')

// ---- a degenerate gradient is a solid fill ------------------------------
// `closest-side` centred on the corner has nothing between the centre
// and the nearest side, so the ending shape has zero radius. That is a
// gradient ray of zero length, which renders as the last stop over the
// whole box (CSS Images 3 §3.4.2.3) -- not as nothing, and not as the
// first stop.
paint(100, 100, 'radial-gradient(circle closest-side at left top, ' + stops + ')')
check(getPixelColor(2, 2) == blue, 'a zero-radius gradient is the last stop at the centre')
check(getPixelColor(50, 50) == blue, 'in the middle')
check(getPixelColor(97, 97) == blue, 'and in the far corner -- a solid fill, not nothing')

// ---- an explicit radius -------------------------------------------------
// A circle of radius 20 puts the boundary at 10.
paint(100, 100, 'radial-gradient(circle 20px, ' + stops + ')')
check(getPixelColor(50, 45) == red, 'an explicit 20px radius puts the boundary at 10')
check(getPixelColor(50, 35) == blue, 'so 15 out is the last stop')
check(getPixelColor(50, 25) == blue, 'and it stays the last stop beyond the ray')

// ---- explicit radii make an ellipse -------------------------------------
// 40px across and 20px down: boundaries at 20 and 10.
paint(100, 100, 'radial-gradient(ellipse 40px 20px, ' + stops + ')')
check(getPixelColor(65, 50) == red, 'two explicit radii: 15 across is inside the 20 boundary')
check(getPixelColor(75, 50) == blue, '25 across is outside it')
check(getPixelColor(50, 56) == red, '6 down is inside the 10 boundary')
check(getPixelColor(50, 65) == blue, '15 down is outside it')

// ---- repeating ----------------------------------------------------------
// A 20px ray repeats every 20px, so red and blue alternate in 10px rings
// all the way out.
paint(100, 100, 'repeating-radial-gradient(circle 20px, ' + stops + ')')
check(getPixelColor(50, 45) == red, 'repeating: the first ring is red')
check(getPixelColor(50, 35) == blue, 'the second is blue')
check(getPixelColor(50, 25) == red, 'the third is red again -- the ray repeats')
check(getPixelColor(50, 15) == blue, 'and the fourth is blue')
check(getPixelColor(50, 5) == red, 'out to the edge of the box')

// ---- a linear gradient is still a linear gradient ------------------------
paint(100, 100, 'linear-gradient(to right, ' + stops + ')')
check(getPixelColor(20, 50) == red, 'a linear gradient still runs along its line')
check(getPixelColor(80, 50) == blue, 'and not out from a centre')
check(getPixelColor(20, 10) == red, 'with every row alike')
check(getPixelColor(80, 90) == blue, 'top to bottom')

finish('radial gradients')
