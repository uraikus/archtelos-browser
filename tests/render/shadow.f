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

// ---- the falloff is the Gaussian the standard asks for (§7.1) -----------
// A shadow's blur is a Gaussian blur of the shadow's own shape whose
// standard deviation is half the blur radius. A Gaussian blur of a
// rectangle has a closed form: along one axis it is the difference of
// the Gaussian's own integral at the two edges, and the whole of it is
// the two axes multiplied, because a two-dimensional Gaussian is two
// one-dimensional ones. That is what makes a corner a quarter of the
// colour where an edge is a half of it.
//
// The box is 60x40 at (20,20), so it runs from x = 20 to x = 80 and
// from y = 20 to y = 60, and `box-shadow: 0 0 20px red` blurs it with a
// standard deviation of 10. **The box is only four standard deviations
// tall, so the two horizontal edges' blurs overlap through the whole of
// it**: along the middle row the vertical term is 0.954, not 1, and an
// expectation that read the alpha half a pixel past the right edge as
// the Gaussian's own 0.480 would be wrong by that factor. It is the
// difference of the two integrals that is right, and the difference is
// what these numbers are:
//
//   (80, 40)  half a pixel past the right edge     0.458089
//   (90, 40)  a standard deviation past it         0.140137
//   (100, 40) two standard deviations              0.019258
//   (40, 19)  half a pixel above the top edge      0.470329
//   (80, 60)  diagonally past the bottom right     0.230446
//   (19, 19)  and past the top left                0.230446
//
// Chromium 141 paints this page -- read with `tests/chromium.py pixels`
// -- as #ff8989, #ffdcdc and #fffcfc along that row and #ffc4c4 at the
// corner, which over white is 0.463, 0.137, 0.012 and 0.231 of red
// against the 0.458, 0.140, 0.019 and 0.230 here. The corner is exact
// to the byte; the others are Chromium's own approximation, which
// blurs with three box blurs rather than with a Gaussian.
//
// The check paints a patch of the same red at the alpha the standard
// asks for, on the same white page, and requires the shadow's pixel to
// be that colour -- an expectation this engine cannot meet by being
// consistent with itself.
//
// One eight-bit level of slack, because the painter quantizes twice:
// one axis's profile is an image, so it is rounded to a byte before the
// other axis's share multiplies it, and a product of two rounded
// numbers can land a level away from the product of the exact ones. It
// shows in the tails, where a level is a large share of a small alpha,
// and the checks that pass exactly are marked as such below. A level is
// far less than the difference between this falloff and any other: the
// nested rectangles this replaced were a whole 0.52 out at the edge.
color func patchAt(alpha:float) {
    fillStyle(white)
    fillAlpha(1.0)
    drawRect(300, 200, 12, 12)
    fillStyle(red)
    fillAlpha(alpha)
    drawRect(300, 200, 12, 12)
    fillAlpha(1.0)
    return getPixelColor(305, 205)
}

bool func isAlpha(c:color, alpha:float) {
    return c == patchAt(alpha) || c == patchAt(alpha + 0.002)
        || c == patchAt(alpha - 0.002)
}

shot('0 0 20px red')
color edgeHalf = getPixelColor(80, 40)
color edgeOneSigma = getPixelColor(90, 40)
color edgeTwoSigma = getPixelColor(100, 40)
color pastCorner = getPixelColor(80, 60)
color farOut = getPixelColor(115, 40)
color leftEdge = getPixelColor(19, 40)
color topEdge = getPixelColor(40, 19)
color topLeft = getPixelColor(19, 19)
check(edgeHalf == patchAt(0.458089), 'against its own edge a blurred shadow is half its colour')
check(edgeOneSigma == patchAt(0.140137), 'a standard deviation out it is the Gaussian\'s integral')
check(isAlpha(edgeTwoSigma, 0.019258), 'and two standard deviations out, to a level')
check(pastCorner == patchAt(0.230446),
      'a corner is the two axes multiplied, as a two-dimensional Gaussian is')
check(farOut == white, 'and three and a half standard deviations out there is nothing left')
check(leftEdge == patchAt(0.458089), 'the left edge falls off the same way as the right')
check(topEdge == patchAt(0.470329),
      'and the top by its own axis, which the box is wide enough not to crowd')
check(topLeft == patchAt(0.230446), 'with the same product at that corner')

// Half the blur radius is half the standard deviation. The box is eight
// of those tall now, so the vertical term is 0.99993 along the middle
// row and the horizontal one carries the answer: 0.460141 half a pixel
// out, 0.135657 five and a half pixels out, nothing at 18.
shot('0 0 10px red')
check(getPixelColor(80, 40) == patchAt(0.460141),
      'a narrower blur is steeper against the edge')
check(getPixelColor(85, 40) == patchAt(0.135657), 'and falls off in proportion to it')
check(getPixelColor(98, 40) == white, 'reaching nothing three standard deviations out')

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

// ---- inset shadows fall inside the box ---------------------------------
// An inset shadow is the box's own padding area minus that area offset
// and shrunk by the spread, so it reads as a band inside the edge rather
// than a shape outside it.

// Five pixels of spread, no offset: a band all the way round, inside.
shot('inset 0 0 0 5px red')
check(getPixelColor(22, 40) == red, 'an inset shadow bands the left edge from inside')
check(getPixelColor(40, 22) == red, 'the top edge')
check(getPixelColor(78, 40) == red, 'the right')
check(getPixelColor(40, 58) == red, 'and the bottom')
check(getPixelColor(40, 40) == blue, 'leaving the middle of the box alone')
check(getPixelColor(15, 40) == white, 'and painting nothing outside it')

// Offset with no spread. The hole is the padding box moved by the
// offsets, so shifting it right by 12 uncovers a band twelve wide on the
// *left* -- the shadow falls opposite the direction it is offset, which
// is what casting a shadow inward from that edge means.
shot('inset 12px 0 0 red')
check(getPixelColor(24, 40) == red, 'a rightward offset bands the left edge')
check(getPixelColor(60, 40) == blue, 'not the middle')
check(getPixelColor(75, 40) == blue, 'and not the edge it moved towards')

// A blurred inset shadow reaches inward and weakens.
shot('inset 0 0 10px red')
check(getPixelColor(22, 40) != blue, 'a blurred inset shadow darkens the inside edge')
check(getPixelColor(50, 40) == blue, 'and leaves the centre')
check(getPixelColor(15, 40) == white, 'without escaping the box')

// ---- and its falloff is the same Gaussian, from the other side ----------
// The inside of a blurred shadow is the outside of its hole: where an
// outer shadow keeps the two axes multiplied, an inset one keeps one
// minus that. The hole here is the padding box itself -- no offset, no
// spread -- so with `inset 0 0 20px red` on the same 60x40 box the
// alpha is 1 - fx*fy, which is
//
//   (20, 40)  the first column inside the left edge   0.503859
//   (30, 40)  ten pixels in                           0.185908
//   (50, 40)  the middle of the box                   0.048378
//   (20, 20)  the first pixel inside the corner       0.729684
//   (79, 59)  and the one inside the opposite corner  0.729684
//
// -- a half against the edge and three quarters into a corner, which is
// the outer shadow's half and quarter seen from the other side.
//
// Chromium 141 paints the same page at #7b0084, #2b00d4, #0800f7 and
// #b4004b, which over the blue is 0.482, 0.169, 0.031 and 0.706 of red.
// Each is a little under the Gaussian's own answer, the same way its
// outer shadow was: three box blurs spread a little wider than the
// Gaussian they stand in for, and it is the Gaussian the standard asks
// for.
//
// The patch is painted over the box's own blue here rather than over
// the page, because that is what the shadow is painted over.
color func patchOverBox(alpha:float) {
    fillStyle(blue)
    fillAlpha(1.0)
    drawRect(300, 200, 12, 12)
    fillStyle(red)
    fillAlpha(alpha)
    drawRect(300, 200, 12, 12)
    fillAlpha(1.0)
    return getPixelColor(305, 205)
}

// Two eight-bit levels of slack here rather than the one an outer
// shadow needs, because an inset one is two passes composited over each
// other and the compositor drops a fraction each time: the middle of
// this box reads 46 of 255 where the exact answer is 47.4. That is a
// hundredth of the alpha, against the half the nested frames this
// replaced were out by.
bool func isAlphaOverBox(c:color, alpha:float) {
    return c == patchOverBox(alpha) || c == patchOverBox(alpha + 0.002)
        || c == patchOverBox(alpha - 0.002) || c == patchOverBox(alpha - 0.006)
}

shot('inset 0 0 20px red')
color inEdge = getPixelColor(20, 40)
color inTen = getPixelColor(30, 40)
color inMiddle = getPixelColor(50, 40)
color inCorner = getPixelColor(20, 20)
color inFarCorner = getPixelColor(79, 59)
check(isAlphaOverBox(inEdge, 0.503859), 'an inset shadow is half its colour against the edge')
check(isAlphaOverBox(inTen, 0.185908), 'a standard deviation in it is what the hole leaves')
check(isAlphaOverBox(inMiddle, 0.048378), 'and the middle of the box keeps a little of it')
check(isAlphaOverBox(inCorner, 0.729684), 'a corner keeps three quarters, the outer shadow\'s quarter inverted')
check(isAlphaOverBox(inFarCorner, 0.729684), 'and the opposite corner the same')
check(getPixelColor(15, 40) == white, 'with nothing outside the box')

// An inset shadow and an outer one on the same box are independent.
shot('inset 0 0 0 5px red, 15px 0 0 blue')
check(getPixelColor(22, 40) == red, 'the inset shadow still bands the inside')
check(getPixelColor(90, 40) == blue, 'while the outer one falls outside')

// ---- a shadow follows the border-radius -------------------------------
// The blur of a rectangle separates into two axes and has a closed form;
// the blur of a rounded rectangle does not separate, because the shape's
// width changes with the row. What does still hold is the outer
// integral: the blurred value at a point is the sum, over the rows the
// shape occupies, of that row's share of the vertical Gaussian times the
// horizontal Gaussian over that row's own span.
//
// A 40x40 box with `box-shadow: 0 0 8px #000` and `border-radius: 20px`
// is a circle, and Chromium 141 paints the row three pixels above it,
// from its left edge outwards, as
//
//   dfdfdf dadada d5d5d5 d1d1d1 cdcdcd c9c9c9 c6c6c6 c4c4c4 c2c2c2 c1c1c1
//
// against this engine's
//
//   e2e2e2 dddddd d8d8d8 d4d4d4 cfcfcf cbcbcb c8c8c8 c6c6c6 c4c4c4 c3c3c3
//
// -- the same profile two or three units lighter throughout, which is
// the difference between a true Gaussian and the three box blurs Skia
// uses to approximate one, and is the same two or three units the square
// corners are already out by. What the checks below ask for is therefore
// the shape rather than the number: that a rounded corner is not a
// square one, that the two agree where a radius cannot reach, and that a
// circle's shadow is radially symmetric, which no rectangle's is.
color shWhite = 'white'

// The shadow under a 40x40 box at (40,40) of the given radius, painted
// once so a whole profile can be read off it.
void func shadowShot(radius:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0;background:#ffffff">'
        + '<div style="position:absolute;left:40px;top:40px;width:40px;height:40px;'
        + 'background:#ffffff;box-shadow:0 0 8px #000000;' + radius
        + '"></div></body>', 'test.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 160)
}

// The square box's own shadow, read once: a profile out to the twelve
// pixels a blur of eight reaches, on all four sides of it.
arr[color] sqN = []
arr[color] sqS = []
arr[color] sqW = []
arr[color] sqE = []
shadowShot('')
color sqCorner = getPixelColor(38, 40)
for int d = 1, d <= 12, d++ {
    sqN.push(getPixelColor(60, 40 - d))
    sqS.push(getPixelColor(60, 79 + d))
    sqW.push(getPixelColor(40 - d, 60))
    sqE.push(getPixelColor(79 + d, 60))
}

// The instrument first: the two shapes have to differ somewhere, or
// every check below passes whatever the painter does.
shadowShot('border-radius:20px')
color rdCorner = getPixelColor(38, 40)
check(!(sqCorner == rdCorner), 'a rounded corner casts a different shadow from a square one')

// Two pixels left of the edge on the box's top row is deep inside a
// square box's shadow and far outside a circle's, so the rounded one is
// the paler of the two. `white` is the page, and neither reaches it.
check(!(sqCorner == white), 'the square corner casts a shadow there')
check(!(rdCorner == white), 'and the rounded one casts some shadow too')

// A circle's shadow is radially symmetric, which is a property no
// rectangle's has and which needs no number from anywhere: four points
// the same distance from the centre have to carry the same alpha. The
// box occupies 40..79 on both axes, so the mirror of a pixel three above
// its top edge is three below its bottom one -- 37 and 82, not 83 -- and
// the square box's own shadow being symmetric about those four is what
// says they are the right points to ask about. The whole profile is
// asked, because one distance can agree while the fall-off either side
// of it does not: taking each row of the shape at its middle puts six of
// the twelve distances out by a unit, halving the rows puts two out, and
// the slicing the painter settles on puts none.
int sqAsym = 0
int rdAsym = 0
int rdRadial = 0
for int d = 1, d <= 12, d++ {
    if !(sqN[d - 1] == sqS[d - 1]) { sqAsym++ }
    if !(sqW[d - 1] == sqE[d - 1]) { sqAsym++ }
    color north = getPixelColor(60, 40 - d)
    color south = getPixelColor(60, 79 + d)
    color west = getPixelColor(40 - d, 60)
    color east = getPixelColor(79 + d, 60)
    if !(north == south) { rdAsym++ }
    if !(west == east) { rdAsym++ }
    if !(north == west) { rdRadial++ }
}
checkEqInt(sqAsym, 0, 'the square box own shadow is symmetric on both axes')
checkEqInt(rdAsym, 0, 'and so is a circle on both of its own')
checkEqInt(rdRadial, 0, 'a circle casts the same shadow above it as beside it')

// Where the radius cannot reach -- the middle of an edge -- the two
// shapes are the same shape, so their shadows have to agree exactly.
// This is the check that says the rounded path did not disturb what was
// already right, and it is the one the two ways of computing a blur owe
// each other: with every radius zero the sum over the rows telescopes
// back into the product of the two axes.
int edgeDiff = 0
shadowShot('border-radius:6px')
for int d = 1, d <= 12, d++ {
    if !(getPixelColor(40 - d, 60) == sqW[d - 1]) { edgeDiff++ }
    if !(getPixelColor(60, 40 - d) == sqN[d - 1]) { edgeDiff++ }
}
checkEqInt(edgeDiff, 0, 'a small radius changes nothing at the middle of an edge')

// The spread grows a round corner and leaves a square one square
// (Backgrounds and Borders 3 §6.2), so a spread shadow under a circle is
// still round: the corner of its bounding box stays paler than the
// square box's corner grown the same way.
shadowShot('box-shadow:0 0 8px 6px #000000;border-radius:20px')
color rdSpread = getPixelColor(33, 34)
shadowShot('box-shadow:0 0 8px 6px #000000')
color sqSpread = getPixelColor(33, 34)
check(!(rdSpread == sqSpread), 'a spread shadow under a circle is still round')
check(!(sqSpread == white), 'and the square one reaches that corner')

// A shadow with no blur at all follows the radius too -- there is
// nothing to fade, so a point is either inside the shape or outside it.
// The far corner of the shifted shape is inside a square and outside
// a circle.
color black = 'black'
shadowShot('box-shadow:12px 12px 0 #000000;border-radius:20px')
color rdHard = getPixelColor(88, 88)
shadowShot('box-shadow:12px 12px 0 #000000')
color sqHard = getPixelColor(88, 88)
check(sqHard == black, 'an unblurred square shadow fills its own corner')
check(!(rdHard == black), 'and an unblurred round one does not')

// ---- an inset shadow follows the inner curve ---------------------------
//
// An inset shadow is the padding box minus that box offset and shrunk
// by the spread, and both of those are rounded where the box is. A
// 120x120 box with `border-radius: 40px` and `inset 0 0 0 12px`, read
// off Chromium with `tests/chromium.py pixels` at 200x200 (todo.md):
//
//   row 6    green to 16, red 19-100, green from 103
//   row 20   green to 4, red 5-18, white 21-98, red 101-113, green from 115
//   row 40   red 0-11, white 12-107, red 108-119, green from 120
//
// Row 40 is below both corners and is the square case the engine
// already drew; rows 6 and 20 are the curve. The spread shrinks the
// hole's radius with it -- 40 less 12 is 28, which is what puts the
// hole's edge at 20 on row 20 rather than at 28.

color ringGreen = '#00ff00'
color ringRed = '#ff0000'
color ringWhite = '#ffffff'

Page inset = pageFromHtml('<!doctype html><head><style>'
    + 'body{margin:0;width:200px;background:#00ff00}'
    + '#a{width:120px;height:120px;border-radius:40px;background:#ffffff;'
    + 'box-shadow:inset 0 0 0 12px #ff0000}'
    + '</style><body><div id="a"></div></body>', 'test.html', 200)
clearCanvas()
paintPage(inset, 0, 0, 200)

// The corner: the shadow must not be painted where the box is not.
check(getPixelColor(5, 6) == ringGreen, 'an inset shadow stops at the rounded corner')
check(getPixelColor(60, 6) == ringRed, 'and is painted across the top between the corners')
check(getPixelColor(124, 6) == ringGreen, 'on the far corner as well')

// Row 20 crosses both edges of the band, and both follow a curve: the
// outer one the box's 40, the inner one the 28 the spread leaves.
int ringOuter = -1
int ringInner = -1
for int x = 0, x < 60, x++ {
    if ringOuter < 0 && getPixelColor(x, 20) == ringRed { ringOuter = x }
    if ringOuter >= 0 && ringInner < 0 && getPixelColor(x, 20) == ringWhite { ringInner = x }
}
checkNear(ringOuter, 5, 1, "the band's outer edge follows the box's own radius")
checkNear(ringInner, 21, 1, "and its inner edge the radius the spread leaves")

// Below the corners it is the straight band it always was, which is
// what says the change did not move the easy case.
check(getPixelColor(5, 60) == ringRed, 'below the corners the band is unchanged')
check(getPixelColor(60, 60) == ringWhite, 'with the hole still open in the middle')
check(getPixelColor(112, 60) == ringRed, 'and the far side of the band still there')


// The blurred one is cut back to the same curve. Its falloff is still
// measured from the square hole -- what the curved one would take is in
// todo.md -- but it no longer paints over the corner the box rounded
// away. Chromium has the backdrop at x=0, 6 and 12 on row 6 and at x=0
// on row 20, and the shadow from there inwards.
Page insetBlur = pageFromHtml('<!doctype html><head><style>'
    + 'body{margin:0;width:200px;background:#00ff00}'
    + '#a{width:120px;height:120px;border-radius:40px;background:#ffffff;'
    + 'box-shadow:inset 0 0 20px 0 #ff0000}'
    + '</style><body><div id="a"></div></body>', 'test.html', 200)
clearCanvas()
paintPage(insetBlur, 0, 0, 200)
check(getPixelColor(12, 6) == ringGreen, 'a blurred inset shadow stops at the corner too')
check(getPixelColor(0, 20) == ringGreen, 'and on the row below it')
check(!(getPixelColor(30, 6) == ringGreen), 'while still being painted inside the curve')
check(!(getPixelColor(30, 6) == ringWhite), 'over the box\'s own background')


// And its falloff follows the curve, not just its edge. The two strip
// passes leave the complement of the *square* hole's blurred coverage;
// a rounded hole is inside the square one, so the shadow belongs darker
// at a corner than the strips make it. Each corner takes one more blit
// carrying `1 - round / (fx*fy)`, which is between zero and one because
// the rounded coverage never exceeds the square one -- so it can be
// painted over rather than subtracted, which matters, since the canvas
// cannot subtract.
//
// The check needs no number from anywhere: the same box with no radius
// paints exactly the square answer, so the two must **differ** where a
// corner curves and **agree** where no corner reaches. A blur of 20
// reaches 30 pixels, so the corner band is the top 70 rows and row 60
// is outside it.
void func insetShot(radius:text) {
    Page p = pageFromHtml('<!doctype html><head><style>'
        + 'body{margin:0;width:200px;background:#00ff00}'
        + '#a{width:120px;height:120px;background:#ffffff;'
        + 'box-shadow:inset 0 0 20px 0 #ff0000;' + radius + '}'
        + '</style><body><div id="a"></div></body>', 'test.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 200)
}

insetShot('border-radius:0')
color insetSqCorner = getPixelColor(6, 20)
color insetSqEdge = getPixelColor(6, 60)
color insetSqDeep = getPixelColor(16, 16)
insetShot('border-radius:40px')
check(!(getPixelColor(6, 20) == insetSqCorner),
      "a blurred inset shadow's corner is not the square answer")
check(!(getPixelColor(16, 16) == insetSqDeep),
      'nor is the point on the corner\'s own diagonal')
check(getPixelColor(6, 60) == insetSqEdge,
      'and away from every corner the two agree exactly')

// The four corners of a square box with equal radii must carry the
// same alpha, which no asymmetry in the correction could survive.
insetShot('border-radius:40px')
color insetTL = getPixelColor(14, 24)
check(getPixelColor(105, 24) == insetTL, 'the top-right corner matches the top-left')
check(getPixelColor(14, 95) == insetTL, 'the bottom-left matches it too')
check(getPixelColor(105, 95) == insetTL, 'and the bottom-right')


finish('box shadow')
