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

// ---- background-origin and background-clip -------------------------------
// One box throughout: 60x20 of content, 15px of padding and a 10px
// border, so the border box is 110x70 at the origin, the padding box is
// 90x50 at (10,10) and the content box is 60x20 at (25,25). The border
// is transparent, which paints nothing, so what the background does
// under it is visible.
//
// `background-clip` bounds what is painted; `background-origin` bounds
// where the image is placed. The clip checks use the background colour
// alone, so the colours are exact -- no image, no scaling, nothing
// filtered.
text areaBox = 'width:60px;height:20px;padding:15px;border:10px solid transparent'

Page c1 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd'
    + '"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(c1, 0, 0, 300)
check(getPixelColor(2, 2) == grey, 'background-clip defaults to border-box, under the border')
check(getPixelColor(12, 12) == grey, 'and across the padding')
check(getPixelColor(27, 27) == grey, 'and the content')

Page c2 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-clip:padding-box"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(c2, 0, 0, 300)
check(getPixelColor(2, 2) == white, 'background-clip: padding-box paints nothing under the border')
check(getPixelColor(12, 12) == grey, 'and starts at the padding edge')
check(getPixelColor(27, 27) == grey, 'covering the content too')

Page c3 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-clip:content-box"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(c3, 0, 0, 300)
check(getPixelColor(2, 2) == white, 'background-clip: content-box paints nothing under the border')
check(getPixelColor(12, 12) == white, 'nor across the padding')
check(getPixelColor(27, 27) == grey, 'only the content box')

// `border-box` written out must mean what leaving it off means.
Page c4 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-clip:border-box"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(c4, 0, 0, 300)
check(getPixelColor(2, 2) == grey, 'background-clip: border-box written out is the default')
check(getPixelColor(27, 27) == grey, 'throughout')

// background-origin places the image. The tile is 10x10 and unscaled,
// so these boundaries are exact.
Page o1 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(o1, 0, 0, 300)
check(getPixelColor(12, 12) == blue, 'background-origin defaults to padding-box, so the tile starts at (10,10)')
check(getPixelColor(17, 12) == green, 'with its green half beside it')
check(getPixelColor(2, 2) == grey, 'and nothing of it under the border')

Page o2 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-origin:border-box"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(o2, 0, 0, 300)
check(getPixelColor(2, 2) == blue, 'background-origin: border-box starts the tile at the border edge')
check(getPixelColor(7, 2) == green, 'halves intact')
check(getPixelColor(12, 12) == grey, 'and it has ended before the padding edge')

Page o3 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-origin:content-box"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(o3, 0, 0, 300)
check(getPixelColor(27, 27) == blue, 'background-origin: content-box starts it at the content edge')
check(getPixelColor(32, 27) == green, 'halves intact')
check(getPixelColor(12, 12) == grey, 'with nothing of it in the padding')

Page o4 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-origin:padding-box"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(o4, 0, 0, 300)
check(getPixelColor(12, 12) == blue, 'background-origin: padding-box written out is the default')
check(getPixelColor(2, 2) == grey, 'to the pixel')

// The two are independent: the origin anchors the tile grid, the clip
// decides what survives. Anchored at the border edge the grid falls on
// multiples of ten, so the content box -- which starts at 25 -- shows
// each tile from its sixth pixel, where the green half is.
Page b1 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-image:url(tile.png);background-origin:border-box;'
    + 'background-clip:content-box"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(b1, 0, 0, 300)
check(getPixelColor(12, 12) == white, 'clip content-box paints nothing in the padding')
check(getPixelColor(27, 27) == green, 'and the grid anchored at 0 puts x=27 seven pixels into a tile')

Page b2 = pageFromHtml(head + '<div style="' + areaBox + ';background-color:#dddddd;'
    + 'background-image:url(tile.png);background-origin:content-box;'
    + 'background-clip:content-box"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(b2, 0, 0, 300)
check(getPixelColor(27, 27) == blue, 'anchored at the content edge instead, x=27 is two pixels in')
check(getPixelColor(32, 27) == green, 'and the green half follows five later')

// ---- background-size ----------------------------------------------------
// The tile is drawn at the size this gives it, and that size is then
// what `background-position` distributes the leftover of and what
// `background-repeat` steps by.

// Two explicit lengths: the 10x10 tile is drawn at 20x20, so each half
// is ten pixels wide instead of five. Samples stay three pixels clear of
// the seam and the edges, because a scaled blit is filtered.
Page s1 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-size:20px 20px"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s1, 0, 0, 300)
check(getPixelColor(4, 4) == blue, 'background-size: 20px 20px doubles the tile, blue half first')
check(getPixelColor(15, 4) == green, 'with the green half from x=10')
check(getPixelColor(4, 16) == blue, 'and twice as tall')
check(getPixelColor(25, 4) == grey, 'past the tile the background colour shows')
check(getPixelColor(4, 25) == grey, 'below it too')

// `contain` fits the image inside the box keeping its ratio: 20x10 in a
// 100x40 box scales by min(100/20, 40/10) = 4, giving 80x40.
Page s2 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(fit.png);background-repeat:no-repeat;'
    + 'background-size:contain"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s2, 0, 0, 300)
check(getPixelColor(20, 20) == blue, 'contain scales 20x10 by 4 to 80x40')
check(getPixelColor(60, 20) == green, 'so the halves meet at x=40')
check(getPixelColor(90, 20) == grey, 'and the last 20 pixels of the box are uncovered')

// `cover` fills the box instead: the same image scales by 5 to 100x50,
// which is wider than contain and taller than the box.
Page s3 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(fit.png);background-repeat:no-repeat;'
    + 'background-size:cover"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s3, 0, 0, 300)
check(getPixelColor(20, 20) == blue, 'cover scales the same image by 5 to 100x50')
check(getPixelColor(70, 20) == green, 'so the halves meet at x=50')
check(getPixelColor(90, 20) == green, 'and the box is covered to its right edge')
check(getPixelColor(90, 35) == green, 'and to its bottom')

// A percentage is of the box, and `100% 100%` must mean the same as the
// box's own measurements written out.
Page s4 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(fit.png);background-repeat:no-repeat;'
    + 'background-size:100% 100%"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s4, 0, 0, 300)
color pctMid = getPixelColor(20, 20)
color pctRight = getPixelColor(80, 20)
Page s5 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(fit.png);background-repeat:no-repeat;'
    + 'background-size:100px 40px"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s5, 0, 0, 300)
check(pctMid == blue, 'background-size: 100% 100% stretches the image over the box')
check(pctRight == green, 'both halves')
check(pctMid == getPixelColor(20, 20), 'and means the same as the box size written in pixels')
check(pctRight == getPixelColor(80, 20), 'to the pixel')

// `auto` on one axis takes the ratio from the other: 40px across on a
// 20x10 image is 20px down.
Page s6 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(fit.png);background-repeat:no-repeat;'
    + 'background-size:40px auto"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s6, 0, 0, 300)
check(getPixelColor(8, 8) == blue, '40px auto keeps the 2:1 ratio, so the image is 40x20')
check(getPixelColor(30, 8) == green, 'with the halves at 20 each')
check(getPixelColor(8, 30) == grey, 'and nothing below y=20')

// One value means that width and `auto` for the height.
Page s7 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(fit.png);background-repeat:no-repeat;'
    + 'background-size:40px"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s7, 0, 0, 300)
check(getPixelColor(8, 8) == blue, 'one value means that width and auto for the height')
check(getPixelColor(30, 8) == green, 'the same as writing auto out')
check(getPixelColor(8, 30) == grey, 'to the pixel')

// The size is what repeat steps by.
Page s8 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-size:20px 20px"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s8, 0, 0, 300)
check(getPixelColor(4, 4) == blue, 'repeat steps by the scaled size, not the intrinsic one')
check(getPixelColor(24, 4) == blue, 'so the second tile starts at x=20')
check(getPixelColor(35, 4) == green, 'with its green half from x=30')

// And what position distributes the leftover of: a 20px tile in a 100px
// box leaves 80, so `right` starts it at x=80.
Page s9 = pageFromHtml(head + '<div style="width:100px;height:40px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-size:20px 20px;background-position:right top"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(s9, 0, 0, 300)
check(getPixelColor(84, 4) == blue, 'position leaves over the scaled size, so right is x=80')
check(getPixelColor(95, 4) == green, 'with the green half at the box edge')
check(getPixelColor(70, 4) == grey, 'and nothing to its left')

// ---- a percentage position, not just a keyword -------------------------
// A percentage is a fraction of the space the image leaves over, the
// same rule the keywords are shorthand for. In a 50px box a 10px tile
// leaves 40 over, so 50% starts it at x=20 -- which is also where
// `center` puts it, and the two must agree.
Page pA = pageFromHtml(head + '<div style="width:50px;height:20px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-position:50% 0"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pA, 0, 0, 300)
check(getPixelColor(22, 2) == blue, 'background-position: 50% starts the tile at x=20')
check(getPixelColor(27, 2) == green, 'with its green half beside it')
check(getPixelColor(2, 2) == grey, 'and the background showing to its left')
check(getPixelColor(47, 2) == grey, 'and to its right')

Page pB = pageFromHtml(head + '<div style="width:50px;height:20px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'
    + 'background-position:center 0"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pB, 0, 0, 300)
check(getPixelColor(22, 2) == blue, 'and `center` means exactly the same thing')
check(getPixelColor(2, 2) == grey, 'to the pixel')

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
