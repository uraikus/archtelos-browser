// `conic-gradient()` and `repeating-conic-gradient()`
// (CSS Images 3 §3.4.3).
//
// A conic gradient sweeps its stops around a centre rather than along a
// line: a stop's position is an angle, measured clockwise from pointing
// up, and every point of the box takes the colour of its own angle
// whatever its distance.
//
// The ground truth is the specification's own rule, not another
// browser's pixels: headless Chromium in this container paints only the
// first scanline of a screenshot (todo.md records the evidence). What
// makes that sound is the gradient used throughout:
//
//     red 0deg, red 90deg, blue 90deg, blue 360deg
//
// Two hard stops, so the result is a flat red quadrant and flat blue
// everywhere else, with no interpolation anywhere. The colours are then
// exact and every check is a question about *which angle a pixel is
// at*, which is the whole of the feature. Samples stay several pixels
// clear of a boundary, because the sweep is painted as wedges and the
// edge lands within about a pixel of its true place.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(400)

color red = 'red'
color blue = 'blue'

text quadrant = 'red 0deg, red 90deg, blue 90deg, blue 360deg'
text head = '<!doctype html><body style="margin:0;font:16px/20px monospace">'

void func paint(image:text) {
    Page p = pageFromHtml(head + '<div style="width:100px;height:100px;background-image:'
        + image + '"></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
}

// ---- the default centre, and where the angles are ---------------------
// A 100x100 box has its centre at (50,50). The four points below are at
// 45, 135, 225 and 315 degrees, one in each quadrant, twenty-five
// pixels out -- far from every boundary.
paint('conic-gradient(' + quadrant + ')')
check(getPixelColor(75, 25) == red, 'the first quadrant, clockwise from up, is the first stop')
check(getPixelColor(75, 75) == blue, 'and the quadrant after it is the second')
check(getPixelColor(25, 75) == blue, 'as is the one after that')
check(getPixelColor(25, 25) == blue, 'and the one before zero')

// Straight up from the centre is zero degrees, and straight right is
// ninety: both are inside the red quadrant, one at each end of it.
check(getPixelColor(51, 20) == red, 'just clockwise of straight up is in the first stop')
check(getPixelColor(80, 49) == red, 'and so is just anticlockwise of straight right')
check(getPixelColor(49, 20) == blue, 'just anticlockwise of straight up is not')
check(getPixelColor(80, 51) == blue, 'and neither is just clockwise of straight right')

// ---- `from <angle>` turns the whole sweep -----------------------------
paint('conic-gradient(from 90deg, ' + quadrant + ')')
check(getPixelColor(75, 75) == red, '`from 90deg` moves the first quadrant a quarter turn on')
check(getPixelColor(75, 25) == blue, 'off the quadrant it was in')
check(getPixelColor(25, 25) == blue, 'and nowhere else')

paint('conic-gradient(from 180deg, ' + quadrant + ')')
check(getPixelColor(25, 75) == red, '`from 180deg` moves it half a turn')
check(getPixelColor(75, 75) == blue, 'past the quadrant a quarter turn made red')

// A whole turn is no turn at all: the two must agree.
paint('conic-gradient(from 360deg, ' + quadrant + ')')
check(getPixelColor(75, 25) == red, 'a full turn leaves the sweep where it was')
check(getPixelColor(75, 75) == blue, 'in both quadrants')

// ---- `at <position>` moves the centre ---------------------------------
// With the centre at the top-left corner every point of the box is
// between 90 and 180 degrees, so the red quadrant is off the box
// entirely -- which the centred version above is not.
paint('conic-gradient(at 0 0, ' + quadrant + ')')
check(getPixelColor(75, 25) == blue, 'a centre at the corner puts the whole box past the first stop')
check(getPixelColor(25, 75) == blue, 'every part of it')
paint('conic-gradient(at 100% 0, ' + quadrant + ')')
check(getPixelColor(25, 75) == blue, 'and a centre at the top right puts it between 180 and 270')

// ---- an angle and a percentage of a turn say the same thing -----------
// A percentage position is a fraction of the whole turn, so 25% is
// 90deg. Neither of these checks depends on 90 being the right answer:
// they assert that the two spellings land on the same pixels.
paint('conic-gradient(red 0%, red 25%, blue 25%, blue 100%)')
check(getPixelColor(75, 25) == red, 'a percentage position is a fraction of the turn')
check(getPixelColor(75, 75) == blue, 'the same sweep the degrees gave')
check(getPixelColor(25, 25) == blue, 'in every quadrant')

// ---- repeating ---------------------------------------------------------
// Six sectors of sixty degrees, red for the first half of each and blue
// for the second: 15 degrees is red, 45 is blue, 75 is red again.
paint('repeating-conic-gradient(red 0deg, red 30deg, blue 30deg, blue 60deg)')
check(getPixelColor(58, 21) == red, 'the first sector of a repeating sweep')
check(getPixelColor(75, 25) == blue, 'the second')
check(getPixelColor(79, 42) == red, 'and the third, a sixty-degree turn from the first')

// ---- what is left alone ------------------------------------------------
// A gradient with one stop is not a gradient, and an unparseable one
// paints nothing rather than something else.
paint('conic-gradient(red)')
check(getPixelColor(75, 25) != red, 'a conic gradient of one stop is not painted')
paint('conic-gradient(0deg, red, blue)')
check(getPixelColor(75, 25) != red, 'nor is one whose first component is neither a stop nor a prelude')

finish('conic')
