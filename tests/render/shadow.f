// `box-shadow` (Backgrounds and Borders 3 §6).
//
// A shadow is painted beneath the element's own background, offset by
// its two lengths, grown by its spread and blurred by its blur radius.
//
// The canvas has no blur, so the falloff is approximated: nested
// rectangles, each drawn at a small alpha, so the alpha accumulates
// where more of them overlap and the edge fades outwards. The shape and
// the extent are therefore exact and the gradient of the fade is not,
// which is what these checks assume -- an offset or a spread is checked
// to the pixel, and the blur is checked for what any blur must do,
// which is to reach beyond the box and to weaken with distance.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color white = 'white'
color red = 'red'
color blue = 'blue'

text head = '<!doctype html><body style="margin:20px;font:16px/20px monospace">'

// The box sits at (20,20) and is 60x40 of solid blue.
void func shot(shadow:text) {
    Page p = pageFromHtml(head + '<div style="width:60px;height:40px;'
        + 'background-color:blue;box-shadow:' + shadow + '"></div></body>',
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// ---- an offset shadow with no blur is a solid rectangle ---------------
// 10px right and down, no blur, no spread: a red 60x40 at (30,30), with
// the blue box on top of it from (20,20).
shot('10px 10px 0 red')
check(getPixelColor(40, 40) == blue, 'the box itself still paints over its shadow')
check(getPixelColor(85, 65) == red, 'the shadow shows past the box, bottom right')
check(getPixelColor(85, 35) == red, 'down the right edge')
check(getPixelColor(40, 65) == red, 'and along the bottom')
check(getPixelColor(25, 15) == white, 'with nothing above the box')
check(getPixelColor(15, 25) == white, 'and nothing to its left')

// ---- the offset is exact ------------------------------------------------
// The shadow's right edge is at 20 + 60 + 10 = 90, so 89 is shadow and
// 90 is the page.
check(getPixelColor(89, 65) == red, 'the shadow reaches exactly to x=89')
check(getPixelColor(90, 65) == white, 'and stops there')

// ---- spread grows it on every side --------------------------------------
// No offset, no blur, 5px of spread: the shadow is the box grown by 5,
// so it shows as a 5px band all the way round.
shot('0 0 0 5px red')
check(getPixelColor(17, 40) == red, 'spread shows a band to the left of the box')
check(getPixelColor(40, 17) == red, 'above it')
check(getPixelColor(83, 40) == red, 'to the right')
check(getPixelColor(40, 63) == red, 'and below')
check(getPixelColor(14, 40) == white, 'ending five pixels out, left')
check(getPixelColor(86, 40) == white, 'and right')

// ---- blur reaches past the box and weakens with distance -----------------
// Any blur must do both of those, whatever its curve.
shot('0 0 8px red')
check(getPixelColor(18, 40) != white, 'a blurred shadow reaches past the box')
check(getPixelColor(40, 40) == blue, 'without covering the box')
check(getPixelColor(5, 40) == white, 'and fades out before it gets far')
bool nearIsStronger = getPixelColor(18, 40) != getPixelColor(26, 40)
check(nearIsStronger, 'and is stronger near the box than further from it')

// ---- no blur, no spread, no offset paints nothing visible ---------------
shot('0 0 0 red')
check(getPixelColor(15, 40) == white, 'a shadow with no offset, blur or spread hides behind the box')
check(getPixelColor(40, 40) == blue, 'which still paints')

// ---- more than one shadow ------------------------------------------------
// Two solid shadows, one each way: both must show.
shot('20px 0 0 red, -20px 0 0 blue')
check(getPixelColor(95, 40) == red, 'the first of two shadows paints')
check(getPixelColor(5, 40) == blue, 'and so does the second')

// ---- the colour defaults to the text colour ------------------------------
Page p = pageFromHtml(head + '<div style="width:60px;height:40px;color:red;'
    + 'background-color:blue;box-shadow:10px 10px 0"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p, 0, 0, 300)
check(getPixelColor(85, 65) == red, 'a shadow with no colour takes the current colour')

// ---- none paints nothing --------------------------------------------------
shot('none')
check(getPixelColor(85, 65) == white, 'box-shadow: none paints no shadow')
check(getPixelColor(40, 40) == blue, 'and leaves the box alone')

finish('box shadow')
