// Background images from `url()`, with `background-repeat` and
// `background-position` (Backgrounds and Borders 3 §3).
//
// A background image changes no geometry — only what is painted inside
// the box — so this is a pixel test. The fixture is a 10x10 tile whose
// left half is blue and right half green, so one pixel says both where
// a tile starts and whether the pattern repeated.
//
// A tile that runs off the edge has to be cut off there, and the canvas
// has no clip region, so the background is painted into an image the
// size of the box and drawn back — the same device `overflow: hidden`
// uses.
//
// The fixture's halves are exactly CSS `blue` (#0000ff) and CSS `green`
// (#008000). `green` is not #00ff00 — that is `lime` — and a fixture
// built with pure green fails every one of these checks against a
// correct implementation, which is a slow thing to work out from a
// colour that looks green on screen.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color blue = 'blue'
color green = 'green'
color white = 'white'
color grey = '#dddddd'

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace">'

// ---- a background image paints at all --------------------------------
Page p1 = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p1, 0, 0, 300)
check(getPixelColor(2, 2) == blue, 'the tile paints at the top left, blue half first')
check(getPixelColor(7, 2) == green, 'and its green half beside it')
check(getPixelColor(2, 40) == grey, 'below the tile the background colour shows')
check(getPixelColor(50, 2) == grey, 'and beside it, because no-repeat means once')

// ---- repeat tiles both ways -------------------------------------------
Page p2 = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd;'
    + 'background-image:url(tile.png)"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p2, 0, 0, 300)
check(getPixelColor(2, 2) == blue, 'the first tile is at the origin')
check(getPixelColor(12, 2) == blue, 'and repeats across')
check(getPixelColor(17, 2) == green, 'with its halves in the same order')
check(getPixelColor(2, 32) == blue, 'and repeats down')
check(getPixelColor(92, 52) == blue, 'all the way to the far corner')

// ---- repeat-x only -----------------------------------------------------
Page p3 = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:repeat-x"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p3, 0, 0, 300)
check(getPixelColor(12, 2) == blue, 'repeat-x tiles across')
check(getPixelColor(2, 32) == grey, 'and not down')

// ---- repeat-y only -----------------------------------------------------
Page p4 = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:repeat-y"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p4, 0, 0, 300)
check(getPixelColor(2, 32) == blue, 'repeat-y tiles down')
check(getPixelColor(12, 2) == grey, 'and not across')

// ---- background-position moves the tile --------------------------------
// `right` puts the image's right edge on the box's right edge, so in a
// 100px box a 10px tile starts at x=90 -- not at x=100, which is what
// treating the percentage as a fraction of the box would give.
Page p5 = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-position:right top"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p5, 0, 0, 300)
check(getPixelColor(92, 2) == blue, 'right puts the tile against the right edge')
check(getPixelColor(97, 2) == green, 'with its own halves still in order')
check(getPixelColor(2, 2) == grey, 'and nothing at the left')

// ---- a length position --------------------------------------------------
Page p6 = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-position:20px 30px"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p6, 0, 0, 300)
check(getPixelColor(22, 32) == blue, 'a length offsets the tile by that many pixels')
check(getPixelColor(27, 32) == green, 'halves in order')
check(getPixelColor(2, 2) == grey, 'and the origin is bare')

// ---- centre ---------------------------------------------------------------
Page p7 = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-position:center center"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p7, 0, 0, 300)
check(getPixelColor(47, 27) == blue, 'centre puts the tile in the middle')
check(getPixelColor(52, 27) == green, 'halves in order')

// ---- a tile is cut off at the edge, not drawn past it ---------------------
// The box is 25px wide, so the third tile is half outside it and must
// stop at the border rather than painting over what is beside the box.
Page p8 = pageFromHtml(head + '<div style="width:25px;height:20px;background-color:#dddddd;'
    + 'background-image:url(tile.png)"></div>'
    + '<div style="position:absolute;left:30px;top:0;width:40px;height:20px;background:white"></div>'
    + '</body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p8, 0, 0, 300)
check(getPixelColor(22, 10) == blue, 'the tile that straddles the edge paints up to it')
check(getPixelColor(35, 10) == white, 'and not past it')

// ---- no background image, no change ---------------------------------------
Page p9 = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p9, 0, 0, 300)
check(getPixelColor(2, 2) == grey, 'a box with no background image is its colour')
check(getPixelColor(50, 30) == grey, 'throughout')

// ---- opacity reaches the image, not just the colour --------------------
// A background image is painted through a layer, and a layer is blitted
// by a call of its own: the element's opacity has to be applied to that
// blit or the image comes out fully opaque on a half-transparent box.
// A background *colour* at the same opacity over the same white page is
// the reference, because both are the fixture's blue over white.
Page p10 = pageFromHtml(head + '<div style="width:20px;height:10px;opacity:0.5;'
    + 'background-image:url(tile.png);background-repeat:no-repeat"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p10, 0, 0, 300)
color imageAtHalf = getPixelColor(2, 2)

Page p11 = pageFromHtml(head + '<div style="width:20px;height:10px;opacity:0.5;'
    + 'background-color:blue"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p11, 0, 0, 300)
color colorAtHalf = getPixelColor(2, 2)

check(imageAtHalf != blue, 'a background image on a half-transparent box is not fully opaque')
check(imageAtHalf == colorAtHalf, 'it blends exactly as the same colour at the same opacity does')

finish('background images')
