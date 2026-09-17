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

// ---- the longhands, against the shorthand that already worked ----------
// `background-position-x` and `background-position-y` say separately
// what `background-position` says together, so the test that earns its
// place is that the two land on the same pixel rather than that each
// lands on one worked out here. The shorthand's own pixels are checked
// above, which is what makes it a reference worth comparing against.
text posBox = '<div style="width:100px;height:60px;background-color:#dddddd;'
    + 'background-image:url(tile.png);background-repeat:no-repeat;'

// Where the tile's top-left corner landed, as x * 1000 + y, or -1 if
// the tile is not in the box at all. Scanning the whole box rather than
// one row matters: a helper that looked along y=32 answered "not found"
// for a tile at the top, and two positions that both miss the row
// compare equal, so a pair of checks passed while the feature was
// absent. One value comes out of a function here (FINDINGS.md, "one
// value out of a function"), so the two coordinates are packed.
int func tileOrigin(css:text) {
    Page pp = pageFromHtml(head + posBox + css + '"></div></body>',
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(pp, 0, 0, 300)
    for int y = 0, y < 60, y++ {
        for int x = 0, x < 100, x++ {
            if getPixelColor(x, y) == blue { return x * 1000 + y }
        }
    }
    return -1
}

// The shorthand's own pixels are checked above, which is what makes it
// a reference worth comparing against; that the tile is found at all is
// asserted first, so "not found" on both sides cannot read as agreement.
check(tileOrigin('background-position:20px 30px') == 20 * 1000 + 30,
      'the shorthand puts the tile where the pixels above say it does')

checkEqInt(tileOrigin('background-position-x:20px;background-position-y:30px'),
           tileOrigin('background-position:20px 30px'),
           'the longhands put the tile where the shorthand does')
checkEqInt(tileOrigin('background-position-x:right;background-position-y:top'),
           tileOrigin('background-position:right top'),
           'keyword longhands agree with the keyword shorthand')
checkEqInt(tileOrigin('background-position-y:bottom;background-position-x:20px'),
           tileOrigin('background-position:20px bottom'),
           'and a keyword on the vertical axis beside a length on the other')
// A percentage is the one the shorthand had wrong once: it is of the
// space the image leaves over, not of the box.
checkEqInt(tileOrigin('background-position-x:50%;background-position-y:0'),
           tileOrigin('background-position:50% 0'),
           'a percentage longhand agrees with the percentage shorthand')

// Cascade order decides between a shorthand and a longhand, which is
// only true if the shorthand expands into the longhands rather than
// being read beside them.
checkEqInt(tileOrigin('background-position:10px 20px;background-position-x:20px'),
           tileOrigin('background-position:20px 20px'),
           'a longhand after the shorthand wins on its own axis and leaves the other')
checkEqInt(tileOrigin('background-position-x:99px;background-position:20px 30px'),
           tileOrigin('background-position:20px 30px'),
           'and the shorthand after a longhand overrides it')

// ---- more than one layer (Backgrounds and Borders 3 §3.10) -----------
// `background-image` takes a comma-separated list, and every other
// background longhand takes one too: the i-th value goes with the i-th
// image, and a list shorter than the images repeats from its start.
//
// The layers paint back to front in the *reverse* of the order they are
// written, so the first one written is on top — which is the whole of
// what these checks are about, and which cannot be read off a single
// layer however it is positioned.
//
// The fixtures are the 10x10 blue-and-green tile and a 10x10 flat red
// square, so a pixel says which layer painted it.
color red = 'red'

void func layers(style:text) {
    Page p = pageFromHtml(head + '<div style="width:100px;height:60px;background-color:#dddddd;'
        + style + '"></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// Two layers, side by side: each paints where its own position puts it.
layers('background-image:url(red.png), url(tile.png);'
     + 'background-repeat:no-repeat;background-position:0 0, 20px 0')
check(getPixelColor(2, 2) == red, 'the first layer paints at its own position')
check(getPixelColor(22, 2) == blue, 'and the second at its own, blue half first')
check(getPixelColor(27, 2) == green, 'with its green half beside it')
check(getPixelColor(12, 2) == grey, 'and the background colour between them')

// The same two layers at the same place: the first one written wins.
layers('background-image:url(red.png), url(tile.png);'
     + 'background-repeat:no-repeat;background-position:0 0')
check(getPixelColor(2, 2) == red, 'two layers at one position: the first is on top')
check(getPixelColor(7, 2) == red, 'across the whole of it')

// Written the other way round, the other one wins -- which is the check
// that does not depend on either colour being the right answer.
layers('background-image:url(tile.png), url(red.png);'
     + 'background-repeat:no-repeat;background-position:0 0')
check(getPixelColor(2, 2) == blue, 'and reversing the list reverses which is on top')
check(getPixelColor(7, 2) == green, 'the whole tile over the red')

// A repeat list shorter than the image list repeats from its start, so
// one `no-repeat` covers both layers.
layers('background-image:url(red.png), url(tile.png);'
     + 'background-repeat:no-repeat;background-position:0 0, 20px 0')
check(getPixelColor(22, 40) == grey, 'a single repeat value applies to every layer')

// A gradient is a layer like any other, and one written first covers
// the image under it.
layers('background-image:linear-gradient(red, red), url(tile.png);'
     + 'background-repeat:no-repeat')
check(getPixelColor(2, 2) == red, 'a gradient layer paints over the image below it')
check(getPixelColor(50, 40) == red, 'across the whole box, since a gradient has no tile')

// One layer still behaves exactly as it did.
layers('background-image:url(tile.png);background-repeat:no-repeat')
check(getPixelColor(2, 2) == blue, 'a single layer is unchanged')
check(getPixelColor(2, 40) == grey, 'and still leaves the colour below it')

// ---- a scaled tile has hard edges and no seam ----------------------------
// A scaled blit samples half a source pixel past the rectangle it
// fills, and with nothing there it fades to transparent: the tile's own
// edge then blends into whatever is under it, and two scaled tiles side
// by side show a band of it between them -- five pixels wide at a ten
// times enlargement.
//
// Chromium 141 draws neither, and `tests/chromium.py pixels` says so on
// these two pages. The 10x10 fixture at `background-size: 100px 100px`
// over `#dddddd`, `no-repeat`: x = 0 is `#0000ff` and x = 99 is
// `#008000`, both the fixture's own colours undiluted, and x = 100 is
// the background exactly. Repeating: the row repeats exactly every 100
// pixels, and the fixture's blue and green blend across each tile
// boundary rather than into the background -- 99 is `#0006f2` where
// 100 is `#0000ff`.
Page pEdge = pageFromHtml(head + '<div style="width:300px;height:100px;'
    + 'background-color:#dddddd;background-image:url(tile.png);'
    + 'background-size:100px 100px;background-repeat:no-repeat"></div></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pEdge, 0, 0, 300)
check(getPixelColor(0, 50) == blue, 'a scaled tile starts at its own colour, undiluted')
check(getPixelColor(99, 50) == green, 'and ends at the other half of it')
check(getPixelColor(100, 50) == grey, 'with the background beginning where the tile stops')

Page pSeam = pageFromHtml(head + '<div style="width:300px;height:100px;'
    + 'background-color:#dddddd;background-image:url(tile.png);'
    + 'background-size:100px 100px"></div></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pSeam, 0, 0, 300)

bool seamRepeats = true
for int x = 0, x < 200, x++ {
    if getPixelColor(x, 50) != getPixelColor(x + 100, 50) { seamRepeats = false }
}
check(seamRepeats, 'a background tiled at a scaled size repeats exactly, tile for tile')

bool seamShowsBack = false
for int x = 0, x < 300, x++ {
    if getPixelColor(x, 50) == grey { seamShowsBack = true }
}
check(!seamShowsBack, 'and never lets the background colour through between two tiles')

// ---- image-set() (CSS Images 4 §4) ------------------------------------
// `image-set()` is a choice between images at different resolutions, not
// a way of drawing one, so what it has to be checked against is the
// candidate it should have chosen. Every check below is that agreement:
// the same box with `image-set(...)` and with the plain `url()` of the
// candidate for this display must paint the same pixels.
//
// This display is one device pixel per CSS pixel, and Chromium 141 at
// the same ratio computes `image-set("tile.png" 1x, "red.png" 2x)` to a
// list whose first candidate is `1dppx` and picks it. A bare number
// with no unit is not a resolution and a candidate that names none is
// `1x`, which is what makes the `type()` row below choose the tile.
// The style attribute is quoted with apostrophes rather than quotation
// marks, because `image-set("tile.png" 1x)` carries quotation marks of
// its own and a double-quoted attribute ends at the first of them. The
// apostrophe is written as its code point: a Festina string literal is
// delimited by one and has no escape for it (FINDINGS.md, finding 34).
text apos = 39.toChar()

arr[color] func rowAfter(style:text, y:int) {
    Page p = pageFromHtml(head + '<div style=' + apos
        + 'width:100px;height:60px;background-color:#dddddd;'
        + style + apos + '></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
    arr[color] out = []
    for int x = 0, x < 100, x++ { out.push(getPixelColor(x, y)) }
    return out
}

int func rowDiff(a:arr[color], b:arr[color]) {
    int n = 0
    for int i = 0, i < a.length && i < b.length, i++ {
        if !(a[i] == b[i]) { n++ }
    }
    return n
}

text noRepeat = ';background-repeat:no-repeat;background-position:0 0'
arr[color] plainTile = rowAfter('background-image:url(tile.png)' + noRepeat, 2)
arr[color] plainRed = rowAfter('background-image:url(red.png)' + noRepeat, 2)

// The instrument first: the two candidates have to differ, or choosing
// between them could not be measured at all.
check(rowDiff(plainTile, plainRed) > 0, 'the two candidate images differ')

checkEqInt(rowDiff(rowAfter('background-image:image-set(url(tile.png) 1x, url(red.png) 2x)'
    + noRepeat, 2), plainTile), 0, 'image-set picks the 1x candidate on a 1x display')

// Order must not decide it, which is the check that does not depend on
// either candidate being the right answer.
checkEqInt(rowDiff(rowAfter('background-image:image-set(url(red.png) 2x, url(tile.png) 1x)'
    + noRepeat, 2), plainTile), 0, 'and picks it wherever in the list it is written')

// The bare-string form the standard allows beside url().
checkEqInt(rowDiff(rowAfter('background-image:image-set("tile.png" 1x, "red.png" 2x)'
    + noRepeat, 2), plainTile), 0, 'a candidate may be a bare string rather than a url()')

// A candidate with no resolution is 1x.
checkEqInt(rowDiff(rowAfter('background-image:image-set(url(tile.png) type("image/png"), url(red.png) 2x)'
    + noRepeat, 2), plainTile), 0, 'a candidate naming no resolution is 1x')

// The three spellings of one resolution say the same thing, so all
// three have to choose the same candidate.
checkEqInt(rowDiff(rowAfter('background-image:image-set(url(tile.png) 1dppx, url(red.png) 2x)'
    + noRepeat, 2), plainTile), 0, '1dppx is 1x')
checkEqInt(rowDiff(rowAfter('background-image:image-set(url(tile.png) 96dpi, url(red.png) 2x)'
    + noRepeat, 2), plainTile), 0, 'and 96dpi is 1x, as Chromium computes it')

// Nothing at 1x: the nearest resolution above is taken rather than none
// at all, so a list of 2x and 3x still paints.
checkEqInt(rowDiff(rowAfter('background-image:image-set(url(tile.png) 2x, url(red.png) 3x)'
    + noRepeat, 2), plainTile), 0, 'with no 1x candidate the nearest one is taken')

// And it is a layer like any other: one written over another covers it.
checkEqInt(rowDiff(rowAfter('background-image:image-set(url(red.png) 1x), url(tile.png)'
    + noRepeat, 2), plainRed), 0, 'an image-set layer covers the layer under it')

// ---- image() (CSS Images 4 §2) ----------------------------------------
// `image()` names a source with an optional colour to fall back to. It
// is graded against the specification rather than against Chromium,
// which supports none of it -- `getComputedStyle` answers `none` for
// every form below -- so what is checked is that it reaches the same
// pixels the plain `url()` of its source does.
checkEqInt(rowDiff(rowAfter('background-image:image(url(tile.png))' + noRepeat, 2), plainTile), 0,
    'image() paints its source')
checkEqInt(rowDiff(rowAfter('background-image:image("tile.png")' + noRepeat, 2), plainTile), 0,
    'and takes a bare string for it as image-set does')
checkEqInt(rowDiff(rowAfter('background-image:image(url(tile.png), blue)' + noRepeat, 2), plainTile), 0,
    'a colour beside a source that loads changes nothing')

// ---- cross-fade() (CSS Images 4 §3) -----------------------------------
// Chromium supports only the `-webkit-cross-fade(A, B, p)` spelling, and
// its pixels say exactly what that means: (1 - p) of A plus p of B, byte
// for byte in sRGB. Over the blue-and-green tile and the flat red
// square, at 10px each, Chromium 141 renders
//
//   p = 0     #0000ff / #008000   the tile untouched
//   p = 25%   #4000bf / #406000
//   p = 50%   #800080 / #804000
//   p = 100%  #ff0000             the red untouched
//
// The standard's own spelling gives each image its weight, so
// `cross-fade(A 75%, B 25%)` is that p = 25% row.
color fade25 = '#4000bf'
color fade25g = '#406000'
// Chromium's blue half at half and half is #800080; this engine's is
// #80007f. Half of 255 is 127.5 and the two round it the other way,
// which is the whole of the difference: every other channel here, and
// every other mix below, agrees to the byte, and the green half agrees
// at half and half too because half of 128 is exactly 64.
color fade50 = '#80007f'
color fade50g = '#804000'
color fadeRev = '#bf0040'
color fadeRevG = '#bf2000'

// The ends first, because they need no number at all: all of one image
// and none of the other has to paint exactly what that image paints.
checkEqInt(rowDiff(rowAfter('background-image:cross-fade(url(tile.png) 100%, url(red.png) 0%)'
    + noRepeat, 2), plainTile), 0, 'all of the first image is the first image')
checkEqInt(rowDiff(rowAfter('background-image:cross-fade(url(tile.png) 0%, url(red.png) 100%)'
    + noRepeat, 2), plainRed), 0, 'and all of the second is the second')

void func fadePage(style:text) {
    Page p = pageFromHtml(head + '<div style=' + apos
        + 'width:100px;height:60px;background-color:#dddddd;'
        + style + apos + '></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

fadePage('background-image:cross-fade(url(tile.png) 50%, url(red.png) 50%)' + noRepeat)
check(getPixelColor(2, 2) == fade50, 'half of each mixes the blue half with the red')
check(getPixelColor(7, 2) == fade50g, 'and the green half with it too')

fadePage('background-image:cross-fade(url(tile.png) 75%, url(red.png) 25%)' + noRepeat)
check(getPixelColor(2, 2) == fade25, 'a quarter of the second image is a quarter of the way')
check(getPixelColor(7, 2) == fade25g, 'on the green half as well')

// One percentage is enough: the other image takes the remainder.
fadePage('background-image:cross-fade(url(tile.png), url(red.png) 25%)' + noRepeat)
check(getPixelColor(2, 2) == fade25, 'a single percentage leaves the rest to the other image')

// Written the other way round the mix is the other way round: three
// quarters red and a quarter tile, which is the complement of the row
// above rather than a restatement of it.
fadePage('background-image:cross-fade(url(red.png) 75%, url(tile.png) 25%)' + noRepeat)
check(getPixelColor(2, 2) == fadeRev, 'reversing the two images reverses the mix')
check(getPixelColor(7, 2) == fadeRevG, 'on the green half too')

finish('background images')
