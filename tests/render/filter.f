// CSS Filter Effects 1 §8, the colour functions, as pixels.
//
// The specification describes a filter as a pass over the pixels an
// element and its descendants painted. This engine cannot make that
// pass -- a `color` read back off the canvas supports equality and
// nothing else -- and does not need to: every colour filter is affine,
// compositing forms convex combinations, and an affine map commutes
// with those. So each source colour is filtered as it is drawn, which
// gives the same pixels exactly.
//
// Two kinds of check below. The agreements need no number: a filtered
// box must paint what an unfiltered box of the filtered colour paints,
// and invert(1) inside invert(1) must come back to where it started.
// The absolute ones are Chromium 141's own answers, so that the two
// spellings cannot both be wrong in the same direction.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(200)
setClientHeight(400)

// Each row is a 40x20 box, so the box for row i is read at (10, 20i+10).
text fHtml = ''
int fCount = 0

void func fAddRow(style:text) {
    fHtml = fHtml + `<div style="width:40px;height:20px;${style}"></div>`
    fCount++
}

void func fPaint() {
    Page p = pageFromHtml('<!doctype html><body style="margin:0">' + fHtml
        + '</body>', 'tests/fixtures/page.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 400)
}

color func fAt(row:int) { return getPixelColor(10, row * 20 + 10) }

// The source colour every row below filters, and the answers Chromium
// gives for it.
const text SRC = 'background:#c86432'          // rgb(200,100,50)

// Chromium's answers as colours, because a `color` compares only with
// another `color`.
color fGrey = '#767676'
color fSepia = '#a59372'
color fInv = '#379bcd'
color fHue = '#329223'
color fBright = '#643219'
color fCon = '#ff4800'
color fSat = '#ff5200'
color fHalf = '#9f6d54'
color fBoth = '#898989'
color fSrc = '#c86432'
color fBlack = '#000000'


fAddRow(SRC)                                                      // 0: unfiltered
fAddRow(`filter:grayscale(1);${SRC}`)                             // 1
fAddRow('background:#767676')                                     // 2: (118,118,118)
fAddRow(`filter:sepia(1);${SRC}`)                                 // 3
fAddRow(`filter:invert(1);${SRC}`)                                // 4
fAddRow(`filter:hue-rotate(90deg);${SRC}`)                        // 5
fAddRow(`filter:brightness(0.5);${SRC}`)                          // 6
fAddRow(`filter:contrast(2);${SRC}`)                              // 7
fAddRow(`filter:saturate(2);${SRC}`)                              // 8
fAddRow(`filter:grayscale(50%);${SRC}`)                           // 9
fAddRow(`filter:grayscale(1) invert(1);${SRC}`)                   // 10
fAddRow(`filter:none;${SRC}`)                                     // 11
fPaint()

// The instrument first. If the filter does nothing, every agreement
// below holds between two boxes of the same unfiltered colour, and this
// is the check that says so.
check(fAt(1) != fAt(0), 'a filtered box does not paint its unfiltered colour')

// The agreement: grayscale(1) on this colour is (118,118,118), and a
// box declared that colour paints the same pixel.
check(fAt(1) == fAt(2), 'grayscale(1) paints what the grey it computes to paints')

// The absolutes, from Chromium 141.
check(fAt(1) == fGrey, 'grayscale(1) on rgb(200,100,50)')
check(fAt(3) == fSepia, 'sepia(1)')
check(fAt(4) == fInv, 'invert(1)')
check(fAt(5) == fHue, 'hue-rotate(90deg)')
check(fAt(6) == fBright, 'brightness(0.5)')
check(fAt(7) == fCon, 'contrast(2)')
check(fAt(8) == fSat, 'saturate(2)')

// A percentage is the same as the number it is a hundredth of.
check(fAt(9) == fHalf, 'grayscale(50%) is grayscale(0.5)')

// A list applies left to right: the grey first, then inverted.
check(fAt(10) == fBoth, 'two functions apply in order')

// `none` is not a filter, and must leave the colour alone.
check(fAt(11) == fAt(0), 'filter: none paints the unfiltered colour')

// ---- the subtree, and composition -------------------------------------
//
// A filter applies to the element AND its descendants, and a filter
// inside a filter composes. invert(1) twice is the identity, which is
// the check that needs no number and would catch a nesting that applied
// only the innermost or only the outermost.

Page p2 = pageFromHtml('<!doctype html><body style="margin:0">'
    + '<div style="width:40px;height:20px;background:#c86432"></div>'
    + '<div style="filter:invert(1)">'
    +   '<div style="width:40px;height:20px;background:#c86432"></div>'
    +   '<div style="filter:invert(1)">'
    +     '<div style="width:40px;height:20px;background:#c86432"></div>'
    +   '</div>'
    + '</div>'
    + '<div style="width:40px;height:20px;background:#c86432"></div>'
    + '</body>', 'tests/fixtures/page.html', 200)
clearCanvas()
paintPage(p2, 0, 0, 400)

check(getPixelColor(10, 10) == fSrc, 'the box above the filter is untouched')
check(getPixelColor(10, 30) == fInv, 'a child of a filtered box is filtered')
check(getPixelColor(10, 50) == fSrc, 'and invert(1) inside invert(1) is the identity')
check(getPixelColor(10, 70) == fSrc, 'the box after the filter is untouched again')

// ---- what the filter reaches ------------------------------------------
//
// A border and a text run are painted with the same fill the background
// is, so both are filtered. Each is read where only it can be.

Page p3 = pageFromHtml('<!doctype html><body style="margin:0">'
    + '<div style="filter:invert(1);width:60px;height:30px;background:#ffffff;'
    + 'border:6px solid #c86432"></div>'
    + '</body>', 'tests/fixtures/page.html', 200)
clearCanvas()
paintPage(p3, 0, 0, 400)
check(getPixelColor(3, 3) == fInv, 'a border is filtered')
check(getPixelColor(30, 20) == fBlack, 'and the white inside it inverts to black')

finish('colour filters as pixels')
