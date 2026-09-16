// border-image (Backgrounds and Borders 3 §6).
//
// The source is cut into nine regions by `border-image-slice`: four
// corners drawn at the border's own size, four edges filling the space
// between them, and a middle drawn only when `fill` asks for it.
//
// tests/fixtures/nine.png is nine 3x3 regions in CSS-named colours, so
// a slice of 3 cuts exactly those nine and each region can be named by
// the colour it must put on the box. Its top edge varies across its
// three columns -- lime, white, lime -- because a uniform edge looks
// the same stretched as repeated, and that difference is the whole of
// `border-image-repeat`.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color red = 'red'
color lime = 'lime'
color blue = 'blue'
color yellow = 'yellow'
color green = 'green'
color aqua = 'aqua'
color fuchsia = 'fuchsia'
color gray = 'gray'
color black = 'black'
color white = 'white'

text head = '<!doctype html><body style="margin:0">'

// A 30x30 border box with 10px borders, so each corner region is drawn
// at 10x10 and each edge fills the 10px between them.
void func shotBorderImage(style:text) {
    Page p = pageFromHtml(head + '<div style="width:10px;height:10px;'
        + 'border:10px solid transparent;background:white;' + style
        + '"></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// ---- without a source nothing is drawn ------------------------------------

shotBorderImage('')
check(getPixelColor(2, 2) == white, 'with no border image the corner is not painted')

// ---- the nine regions land where they belong ------------------------------

shotBorderImage('border-image:url(nine.png) 3')
check(getPixelColor(2, 2) == red, 'the top-left region goes in the top-left corner')
check(getPixelColor(27, 2) == blue, 'the top-right region in the top-right corner')
check(getPixelColor(2, 27) == fuchsia, 'the bottom-left region in the bottom-left corner')
check(getPixelColor(27, 27) == black, 'the bottom-right region in the bottom-right corner')
check(getPixelColor(2, 15) == yellow, 'the left region fills the left edge')
check(getPixelColor(27, 15) == aqua, 'the right region fills the right edge')
check(getPixelColor(15, 27) == gray, 'the bottom region fills the bottom edge')

// The middle is not drawn unless `fill` asks, so the box's own
// background shows through.
check(getPixelColor(15, 15) == white, 'the middle region is left out')
shotBorderImage('border-image:url(nine.png) 3 fill')
check(getPixelColor(15, 15) == green, 'and drawn when `fill` asks for it')

// ---- the slice can be a percentage ----------------------------------------
// A third of a 9px source is 3px, so these two must agree.

shotBorderImage('border-image:url(nine.png) 33.333%')
check(getPixelColor(2, 2) == red, 'a percentage slice cuts the same corner')
check(getPixelColor(27, 27) == black, 'and the same opposite corner')

// ---- border-image-repeat --------------------------------------------------
// The top edge is lime, white, lime across its three source columns.
// Stretched into 10px that is one band of white; repeated it is
// several. Counting them is what tells the two apart.

int func whiteRunsAcrossTop() {
    int runs = 0
    bool inRun = false
    for int x = 10, x < 20, x++ {
        bool isWhite = getPixelColor(x, 2) == white
        if isWhite && !inRun { runs++ }
        inRun = isWhite
    }
    return runs
}

// A stretched blit is filtered, so the one-pixel white column of a
// 3px region blends into the lime on either side and never reaches the
// full colour; a tiled one is an unscaled blit and is exact. That is
// why the stretched edge is expected to show none and the tiled one
// several, rather than one against many.
shotBorderImage('border-image:url(nine.png) 3 stretch')
int stretched = whiteRunsAcrossTop()

shotBorderImage('border-image:url(nine.png) 3 repeat')
int repeated = whiteRunsAcrossTop()
check(repeated >= 2, 'a repeated edge lays its region down more than once')
check(repeated > stretched, 'which a stretched edge does not')

// ---- border-image-width ---------------------------------------------------
// The width of the drawn border image, which is the border's own width
// by default and can differ from it.

// A 3x3 corner region scaled into 4x4 is filtered at every pixel, so
// the check asks that the corner is painted at all rather than that it
// is the exact colour -- which it can only be where the scale is large
// enough to leave an unblended interior.
shotBorderImage('border-image:url(nine.png) 3 / 4px')
check(getPixelColor(1, 1) != white, 'a narrower border-image-width still draws the corner')
check(getPixelColor(6, 6) == white, 'but only as far as it was asked to')

shotBorderImage('border-image:url(nine.png) 3')
check(getPixelColor(6, 6) == red, 'where the default width reaches the whole border')

// ---- border-image-outset --------------------------------------------------
// The outset pushes the image beyond the border box, into space the box
// does not occupy.

// The wrapper is padded rather than the box margined, because a top
// margin here collapses through to the root and is dropped, which would
// put the box somewhere other than where the check expects.
void func shotInset(style:text) {
    Page p = pageFromHtml(head + '<div style="padding:10px"><div style="width:10px;'
        + 'height:10px;border:10px solid transparent;background:white;' + style
        + '"></div></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

shotInset('border-image:url(nine.png) 3')
check(getPixelColor(12, 12) == red, 'without an outset the image starts at the border box')
check(getPixelColor(7, 7) == white, 'and nothing is painted outside it')
shotInset('border-image:url(nine.png) 3;border-image-outset:5px')
check(getPixelColor(7, 7) != white, 'an outset pushes it outside the border box')

// ---- the longhands say what the shorthand says ----------------------------

shotBorderImage('border-image:url(nine.png) 3 repeat')
int shorthandRuns = whiteRunsAcrossTop()
shotBorderImage('border-image-source:url(nine.png);border-image-slice:3;'
    + 'border-image-repeat:repeat')
checkEqInt(whiteRunsAcrossTop(), shorthandRuns,
           'the border-image longhands draw what the shorthand draws')
check(getPixelColor(2, 2) == red, 'corners included')

finish('border image')
