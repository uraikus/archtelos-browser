// `object-fit` and `object-position` (CSS Images 3 §5.5 and §5.6).
//
// Both change where a replaced element's content is painted inside its
// content box and nothing about the box, so this is a pixel test.
//
// The ground truth is the specification's own sizing algorithm rather
// than another browser's pixels: headless Chromium in this container
// paints only the first scanline of a screenshot, so it cannot supply
// them (todo.md records the evidence). The algorithm is exact, which is
// what makes that acceptable — every expectation below is derived from
// the intrinsic size and the box, and the derivation is written beside
// the check so a failure says which step was wrong.
//
// The fixture is 20x10 — a 2:1 ratio, so `contain` and `cover` give
// different answers — with its left half CSS `blue` (#0000ff) and its
// right half CSS `green` (#008000). Against a 40x40 box the scale
// factors are min(40/20, 40/10) = 2 for `contain` and max(...) = 4 for
// `cover`.
//
// Sampling avoids the edges of a *scaled* blit. Cairo filters when the
// scale is not 1, which blends about two pixels either side of every
// edge and of the seam between the halves; an unscaled blit is exact to
// the pixel, so the `none` cases below can check a boundary directly
// and the scaled ones step three pixels clear of it.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color blue = 'blue'
color green = 'green'
color grey = '#dddddd'
color white = 'white'

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace">'
text box = 'display:block;width:40px;height:40px;background-color:#dddddd'
text tall = 'display:block;width:10px;height:40px;background-color:#dddddd'

Page func shot(style:text) {
    Page p = pageFromHtml(head + '<img src="fit.png" style="' + style + '"></body>',
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
    return p
}

// ---- fill, the initial value, stretches to the box --------------------
// 20x10 becomes 40x40: the halves land on x 0-19 and x 20-39, and the
// aspect ratio is not kept.
Page p1 = shot(box)
check(getPixelColor(8, 6) == blue, 'fill stretches the blue half across the left of the box')
check(getPixelColor(31, 6) == green, 'and the green half across the right')
check(getPixelColor(8, 33) == blue, 'to the full height of the box, blue side')
check(getPixelColor(31, 33) == green, 'and green side -- fill does not keep the ratio')

// ---- contain fits inside, keeping the ratio ----------------------------
// scale 2 -> 40x20. The initial object-position is 50% 50%, and the
// leftover height is 20, so the object occupies y 10-29.
Page p2 = shot(box + ';object-fit:contain')
check(getPixelColor(8, 8) == grey, 'contain leaves the top of the box showing its background')
check(getPixelColor(8, 31) == grey, 'and the bottom -- 40x20 centred in 40 starts at y=10')
check(getPixelColor(8, 20) == blue, 'the object sits between them, blue half left')
check(getPixelColor(31, 20) == green, 'green half right')
check(getPixelColor(8, 15) == blue, 'across its whole height')
check(getPixelColor(31, 25) == green, 'on both halves')

// ---- cover fills the box and is clipped --------------------------------
// scale 4 -> 80x40. The leftover width is -40, so 50% places the object
// at x=-20 and the box shows its middle: source x 5 to 15, which puts
// the seam between the halves at box x=20.
Page p3 = shot(box + ';object-fit:cover')
check(getPixelColor(8, 5) == blue, 'cover fills the box to the top')
check(getPixelColor(8, 35) == blue, 'and to the bottom')
check(getPixelColor(17, 20) == blue, 'the halves still meet, blue up to x=20')
check(getPixelColor(23, 20) == green, 'green after it')
check(getPixelColor(45, 20) == white, 'and the overflow is clipped to the content box')

// ---- none paints at the intrinsic size ---------------------------------
// 20x10 centred: the leftovers are 20 and 30, so the object occupies
// x 10-29, y 15-24. Scale 1, so these boundaries are exact.
Page p4 = shot(box + ';object-fit:none')
check(getPixelColor(10, 15) == blue, 'none puts the intrinsic 20x10 at exactly x=10, y=15')
check(getPixelColor(9, 15) == grey, 'with the background one pixel to its left')
check(getPixelColor(29, 24) == green, 'and its far corner at x=29, y=24')
check(getPixelColor(30, 24) == grey, 'with the background one pixel beyond')
check(getPixelColor(15, 20) == blue, 'the halves keep their intrinsic width')
check(getPixelColor(25, 20) == green, 'ten pixels each')
check(getPixelColor(15, 14) == grey, 'nothing above the object')
check(getPixelColor(15, 25) == grey, 'nothing below it')

// ---- scale-down is none when the image already fits --------------------
// none is 20x10 and contain is 40x20; the smaller is none.
Page p5 = shot(box + ';object-fit:scale-down')
check(getPixelColor(10, 15) == blue, 'scale-down leaves an image that fits at its own size')
check(getPixelColor(29, 24) == green, 'corner for corner with none')
check(getPixelColor(9, 15) == grey, 'not scaled up to the box')

// ---- scale-down is contain when the image is larger --------------------
// In a 10x40 box, contain scales 20x10 by 0.5 to 10x5 and centres it in
// the leftover 35, so the object occupies y 18-22. `none` in the same
// box would keep 10 rows, y 15-24, which is what these checks separate.
Page p6 = shot(tall + ';object-fit:scale-down')
check(getPixelColor(2, 20) == blue, 'scale-down shrinks an image larger than its box')
check(getPixelColor(7, 20) == green, 'keeping the ratio, so the seam stays at the middle')
check(getPixelColor(2, 16) == grey, 'ten rows become five: y=16 is above the object')
check(getPixelColor(2, 24) == grey, 'and y=24 is below it')

Page p7 = shot(tall + ';object-fit:none')
check(getPixelColor(2, 16) == blue, 'where none in the same box still paints at y=16')
check(getPixelColor(2, 24) == blue, 'and at y=24 -- which is what scale-down changed')
check(getPixelColor(2, 14) == grey, 'both centred on the same row')

// ---- object-position moves the fitted object ---------------------------
// contain gives 40x20; `left top` puts it at the origin, so the
// leftover 20 rows fall at the bottom instead of being split.
Page p8 = shot(box + ';object-fit:contain;object-position:left top')
check(getPixelColor(8, 6) == blue, 'object-position: left top moves the object to the origin')
check(getPixelColor(31, 6) == green, 'both halves with it')
check(getPixelColor(8, 30) == grey, 'and all the leftover space falls below')

// ---- and to the far corner ---------------------------------------------
// none gives 20x10 and leftovers of 20 and 30, so `right bottom` puts
// its top left corner at exactly (20, 30).
Page p9 = shot(box + ';object-fit:none;object-position:right bottom')
check(getPixelColor(20, 30) == blue, 'right bottom lands the object at exactly x=20, y=30')
check(getPixelColor(19, 30) == grey, 'one pixel short of it is background')
check(getPixelColor(39, 39) == green, 'and its far corner is the box corner')
check(getPixelColor(25, 25) == grey, 'nothing above it')

// ---- a length positions from the top left ------------------------------
Page p10 = shot(box + ';object-fit:none;object-position:5px 5px')
check(getPixelColor(5, 5) == blue, 'a length offsets the object from the top left')
check(getPixelColor(4, 5) == grey, 'exactly, not approximately')
check(getPixelColor(24, 14) == green, 'the whole 20x10 moves with it')
check(getPixelColor(8, 2) == grey, 'leaving background above')

// ---- a percentage position -----------------------------------------------
// none gives 20x10 and leftovers of 20 and 30, so 50% 50% -- the initial
// value -- puts it at (10, 15), and writing that percentage out must
// mean the same as leaving it off.
Page pPct = shot(box + ';object-fit:none;object-position:50% 50%')
check(getPixelColor(10, 15) == blue, 'object-position: 50% 50% is the initial value written out')
check(getPixelColor(9, 15) == grey, 'to the pixel')
Page pPct2 = shot(box + ';object-fit:none;object-position:25% 0%')
check(getPixelColor(5, 0) == blue, '25% of the 20 leftover is 5, and 0% of 30 is 0')
check(getPixelColor(4, 0) == grey, 'exactly')

// ---- object-position does nothing under fill ---------------------------
// `fill` always covers the box exactly, so there is no leftover space
// for a position to distribute.
Page p11 = shot(box + ';object-position:right bottom')
check(getPixelColor(8, 6) == blue, 'object-position has nothing to move under fill')
check(getPixelColor(31, 33) == green, 'the object still covers the box')

// ---- the clipping layer must not change the opacity --------------------
// An object that overflows its box is painted through a layer and
// blitted back, and an object that fits is drawn straight on. The two
// paths must composite identically: if the layer is both drawn into and
// blitted at the element's opacity, it is applied twice.
//
// In a 10x10 box, `contain` gives 10x5 at (0,2), which fits and is
// drawn straight; `none` gives 20x10 at (-5,0), which hangs over both
// edges and goes through the layer. Both put the fixture's blue half
// under (2,4).
text small = 'display:block;width:10px;height:10px;background-color:#dddddd'
Page p12 = shot(small + ';object-fit:contain')
color directOpaque = getPixelColor(2, 4)
Page p13 = shot(small + ';object-fit:none')
color layerOpaque = getPixelColor(2, 4)
Page p14 = shot(small + ';object-fit:contain;opacity:0.5')
color directHalf = getPixelColor(2, 4)
Page p15 = shot(small + ';object-fit:none;opacity:0.5')
color layerHalf = getPixelColor(2, 4)

check(directOpaque == layerOpaque, 'both paths paint the same pixel when opaque')
check(directHalf != directOpaque, 'opacity changes that pixel on the direct path')
check(layerHalf != layerOpaque, 'and on the layer path')
check(directHalf == layerHalf, 'and changes it by exactly as much -- the layer applies it once')

// ---- image-rendering: pixelated (CSS Images 3 §5.3) --------------------
// The scale this engine draws goes through `drawImage`, which filters,
// and the runtime does not say how. `pixelated` asks for nearest
// neighbour instead, and the check that earns its place needs no
// colour written down here: a nearest-neighbour enlargement contains
// ONLY colours the source contains, so the middle of each enlarged
// block must be exactly what the unscaled image paints at that pixel.
// `nine.png` is nine 3x3 regions, and its top edge varies across its
// own three columns -- lime, white, lime -- so the nine pixels this
// samples are nine different colours and the boundary below has to be
// read from the source rather than assumed from the region.
//
// Chromium's rows are in todo.md: `pixelated` gives a hard boundary
// where `floor(dx * sw / w)` changes, and `crisp-edges` is `auto`
// pixel for pixel, which is why it is graded the same here.

Page func ninth(style:text) {
    Page p = pageFromHtml(head + '<img src="nine.png" style="display:block;' + style + '"></body>',
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
    return p
}

// The source, unscaled: one pixel per region, read at the region's own
// middle. Nothing about these colours is written down.
Page pNat = ninth('')
arr[color] nineSrc = []
for int gy = 0, gy < 3, gy++ {
    for int gx = 0, gx < 3, gx++ { nineSrc.push(getPixelColor(gx * 3 + 1, gy * 3 + 1)) }
}
// The two source pixels the boundary at x=30 falls between: a
// destination pixel takes source `floor(dx * 9 / 90)`, so x=29 takes
// column 2 and x=30 column 3.
color srcCol2 = getPixelColor(2, 1)
color srcCol3 = getPixelColor(3, 1)

// 9x9 to 90x90 is ten destination pixels per source pixel, so the
// middle of the region that came from source pixel (3gx+1, 3gy+1) is
// at (30gx + 15, 30gy + 15).
Page pPix = ninth('width:90px;height:90px;image-rendering:pixelated')
arr[color] ninePix = []
for int gy = 0, gy < 3, gy++ {
    for int gx = 0, gx < 3, gx++ { ninePix.push(getPixelColor(gx * 30 + 15, gy * 30 + 15)) }
}
// Read while that render is still on the canvas: every later `ninth`
// paints over it.
color pixLeft = getPixelColor(29, 15)
color pixRight = getPixelColor(30, 15)

Page pSmooth = ninth('width:90px;height:90px')
arr[color] nineSm = []
for int gy = 0, gy < 3, gy++ {
    for int gx = 0, gx < 3, gx++ { nineSm.push(getPixelColor(gx * 30 + 15, gy * 30 + 15)) }
}
color smLeft = getPixelColor(29, 15)
color smRight = getPixelColor(30, 15)

// The instrument: the nine regions have to be nine different colours,
// or every comparison below holds on an image that is all one colour.
int nineDistinct = 0
for int i = 0, i < nineSrc.length, i++ {
    bool seen = false
    for int j = 0, j < i, j++ { if nineSrc[i] == nineSrc[j] { seen = true } }
    if !seen { nineDistinct++ }
}
checkEqInt(nineDistinct, 9, 'the fixture has nine different colours in it')

for int i = 0, i < nineSrc.length, i++ {
    check(ninePix[i] == nineSrc[i],
          `a pixelated enlargement keeps the source colour, region ${i}`)
}

// And the boundary is hard: the last pixel of a block and the first of
// the next are the two source colours, with nothing between them.
check(pixLeft == srcCol2, 'the block runs up to its own edge')
check(pixRight == srcCol3, 'and the next block starts at the pixel after it')

// The instrument again, the other way: the smoothed scale has to
// differ there, or `pixelated` is being compared with itself.
check(pixLeft != pixRight, 'the two blocks differ at all')
check(smLeft != srcCol2 || smRight != srcCol3,
      'the smoothed scale blends the boundary, which is what pixelated removes')

// `crisp-edges` is `auto` in Chromium, pixel for pixel, so it is here.
Page pCrisp = ninth('width:90px;height:90px;image-rendering:crisp-edges')
color crispLeft = getPixelColor(29, 15)
check(crispLeft == smLeft, 'crisp-edges paints what auto paints')

finish('object fit')
