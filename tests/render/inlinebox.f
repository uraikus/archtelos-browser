// An inline box's own border and padding (CSS2 §8.4).
//
// An inline that breaks across lines paints its opening border and
// padding on the fragment that begins it and its closing ones on the
// fragment that ends it, and neither on the fragments in between --
// which is what `box-decoration-break: slice`, the initial value,
// means. The top and bottom edges are on every fragment, and none of
// the four changes the line height: an inline's padding and border
// take horizontal advance and paint outside the line box, leaving the
// block exactly as tall as it was.
//
// The central check counts pixels of the side borders alone, with the
// top and bottom borders given no width and the text no colour, so
// that nothing else can land on them. The same inline over one line
// and over three must then paint the same number of them, because
// `slice` puts each side edge on exactly one fragment however many
// fragments there are. Neither number is known in advance and neither
// is written down here.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color blue = 'blue'
color green = 'green'
color white = 'white'

// Long enough to break into three lines at 150px and to fit on one at
// 400px, in the 16px monospace the tests use.
const text WORDS = 'aaaa bbbb cccc dddd eeee ffff gg'

// A 20px spacer above the paragraph, because an inline's border box is
// taller than its line box and reaches above it; without the spacer the
// opening border's top would fall off the canvas.
text func inlinePage(pw:int, span:text) {
    return `<!doctype html><body style="margin:0;font:16px/24px monospace">`
        + `<div style="height:20px"></div>`
        + `<p style="width:${pw}px;margin:0 0 30px">`
        + `<span style="${span}">${WORDS}</span></p>`
        + `<div style="height:10px;background:green"></div></body>`
}

void func shot(pw:int, span:text) {
    Page p = pageFromHtml(inlinePage(pw, span), 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

int func countColor(c:color, x0:int, y0:int, x1:int, y1:int) {
    int n = 0
    for int y = y0, y < y1, y++ {
        for int x = x0, x < x1, x++ {
            if getPixelColor(x, y) == c { n++ }
        }
    }
    return n
}

// The first column holding any pixel of `c`, or -1.
int func firstXOf(c:color) {
    for int x = 0, x < 400, x++ {
        for int y = 0, y < 300, y++ {
            if getPixelColor(x, y) == c { return x }
        }
    }
    return -1
}

// The first row holding any pixel of `c`, or -1.
int func firstYOf(c:color) {
    for int y = 0, y < 300, y++ {
        for int x = 0, x < 400, x++ {
            if getPixelColor(x, y) == c { return y }
        }
    }
    return -1
}

// The tallest unbroken run of `c` down a single column.
int func columnRun(c:color, x:int) {
    int best = 0
    int run = 0
    for int y = 0, y < 300, y++ {
        if getPixelColor(x, y) == c {
            run++
            if run > best { best = run }
        } else {
            run = 0
        }
    }
    return best
}

// Side borders only, and invisible text: every blue pixel on the canvas
// then belongs to an opening or a closing edge.
//
// The line height is raised past the border box on purpose. At the
// 24px the rest of this file uses, a padded inline's box is 31 tall and
// the boxes of two consecutive fragments overlap by seven rows -- so
// the opening edges of three fragments, which all sit in the same four
// columns, cover fewer pixels than three of them, and counting them
// would answer a question about the overlap rather than about the
// edges.
const text SIDES = 'color:white;line-height:40px;padding:6px;'
    + 'border:4px solid blue;border-top-width:0;border-bottom-width:0'
const text SIDES_BARE = 'color:white;line-height:40px;padding:0;'
    + 'border:4px solid blue;border-top-width:0;border-bottom-width:0'

// ---- the opening and closing edges are painted at all -------------------

shot(400, SIDES)
int oneLineBlue = countColor(blue, 0, 0, 400, 300)
check(oneLineBlue > 0, 'an inline paints the side borders of its own box')
checkEqInt(firstXOf(blue), 0,
           'the opening border sits at the start of the inline, not at its text')

// Two edges and no more, each as tall as the other: an inline on one
// line opens and closes on the same fragment.
int oneLineLeft = countColor(blue, 0, 0, 4, 300)
checkEqInt(oneLineBlue, oneLineLeft * 2,
           'one line carries exactly two side edges, the opening and the closing')

// ---- `slice` paints each side edge exactly once -------------------------

shot(150, SIDES)
checkEqInt(countColor(blue, 0, 0, 400, 300), oneLineBlue,
           'the same inline over three lines paints the same two side edges')
checkEqInt(countColor(blue, 0, 0, 4, 300), oneLineLeft,
           'and the opening edge alone is unchanged by the break')

// The second and third fragments begin at the paragraph's left edge, so
// an opening border on either would show up in the same four columns.
checkEqInt(columnRun(blue, 0), Math.floorDiv(oneLineLeft, 4),
           'a continuation fragment carries no opening border')

// ---- the side edges are as tall as the padding box ----------------------

int paddedEdge = Math.floorDiv(oneLineLeft, 4)
shot(400, SIDES_BARE)
int bareEdge = Math.floorDiv(countColor(blue, 0, 0, 4, 300), 4)
checkEqInt(paddedEdge - bareEdge, 12,
           'the side edge is as tall as the content area plus the padding')

// ---- and none of it moves the block ------------------------------------

shot(400, SIDES)
int paddedGreen = firstYOf(green)
shot(400, 'color:white;line-height:40px')
int plainGreen = firstYOf(green)
check(paddedGreen > 0, 'the strip below the paragraph is on the canvas')
checkEqInt(paddedGreen, plainGreen,
           "an inline's padding and border do not make the block any taller")

// ---- the opening edge pushes the text across ---------------------------

// With the text visible again and all four borders drawn: the first
// glyph cannot begin before the border and the padding that precede it,
// and monospace ink sits a little inside its advance, which is the
// slack above.
shot(400, 'padding:6px;border:4px solid blue')
checkEqInt(firstXOf(blue), 0, 'the opening border still starts the inline')
int textX = -1
for int x = 0, x < 400 && textX < 0, x++ {
    for int y = 0, y < 300 && textX < 0, y++ {
        color c = getPixelColor(x, y)
        if x > 3 && c != white && c != blue && c != green { textX = x }
    }
}
check(textX >= 10, 'the opening padding and border push the text across')
check(textX <= 14, 'and push it no further than they are wide')

// The content area is shorter than the line box, and the padding and
// border then reach past both: the box paints above the line, which
// starts at y = 20 under the spacer.
check(firstYOf(blue) < 20, "an inline's border box paints outside its line box")

// ---- and it survives the paint cull ------------------------------------

// The painter skips a line box outside the window it is drawing. An
// inline's border box reaches past its line box, so a line just above
// the window can still have a border inside it -- and the cull has to
// be of the larger box, or the border vanishes a few pixels early.
Page scrolled = pageFromHtml(
    `<!doctype html><body style="margin:0;font:16px/24px monospace">`
    + `<div style="height:20px"></div>`
    + `<p style="width:400px;margin:0 0 200px">`
    + `<span style="color:white;padding:6px;border:4px solid blue">abc</span>`
    + `</p></body>`, 'tests/fixtures/page.html', 400)

int func blueAfterScroll(sy:int) {
    clearCanvas()
    paintPage(scrolled, 0, sy, 300)
    return countColor(blue, 0, 0, 400, 300)
}

// Where the border box ends, read off the unscrolled render rather than
// worked out here. The line box under the 20px spacer ends at 43.
blueAfterScroll(0)
int boxBottom = -1
for int y = 0, y < 300, y++ {
    for int x = 0, x < 400, x++ {
        if getPixelColor(x, y) == blue { boxBottom = y }
    }
}
check(boxBottom > 43, "an inline's border box reaches below its line box")

// The last scroll position at which any of it is still painted must be
// the last row of the border box itself, not the last row of the line
// box -- and which row that is was read off the render above.
int lastVisible = -1
for int sy = 0, sy <= 80, sy++ {
    if blueAfterScroll(sy) > 0 { lastVisible = sy }
}
checkEqInt(lastVisible, boxBottom,
           'a border paints for exactly as long as its own box is in the window')

// ---- box-decoration-break ----------------------------------------------

// `slice`, the initial value, puts the opening edge on the fragment
// that begins the inline and the closing one on the fragment that ends
// it. `clone` puts both on every fragment. Measured against Chromium,
// it changes no break at all: the same characters stay on the same
// lines, each continuation is pushed right by the opening edge, and the
// closing edge overflows the line rather than forcing an earlier break.

const text CLONE = ';box-decoration-break:clone'

// The number of separate bands of ink down the canvas, which for a
// paragraph of plain text is the number of lines it broke into. Counted
// from the render rather than assumed, because it is what the check
// below multiplies by. The green strip under the paragraph is not ink.
int func inkBands() {
    int n = 0
    bool inBand = false
    for int y = 0, y < 300, y++ {
        bool any = false
        for int x = 0, x < 400 && !any, x++ {
            color c = getPixelColor(x, y)
            if c != white && c != green { any = true }
        }
        if any && !inBand { n++ }
        inBand = any
    }
    return n
}

shot(150, 'color:black')
int lineCount = inkBands()
checkEqInt(lineCount, 3, 'the narrow fixture breaks into three lines')

// One fragment carries both edges either way, so on a single line the
// two keywords must be indistinguishable. That check does not depend on
// the count at all.
shot(400, SIDES)
int oneSlice = countColor(blue, 0, 0, 400, 300)
shot(400, SIDES + CLONE)
checkEqInt(countColor(blue, 0, 0, 400, 300), oneSlice,
           'on a single fragment clone and slice are the same box')

// Over three, `clone` paints three times as many side edges as `slice`,
// because `slice` paints two however many fragments there are.
shot(150, SIDES)
int sliceBlue = countColor(blue, 0, 0, 400, 300)
shot(150, SIDES + CLONE)
checkEqInt(countColor(blue, 0, 0, 400, 300), sliceBlue * lineCount,
           'clone puts both side edges on every fragment')

// ---- and what that does to the text ------------------------------------

// The first and last column of ink on one row, ignoring the borders.
int inkFirst = -1
int inkLast = -1
void func scanInk(y:int) {
    inkFirst = -1
    inkLast = -1
    for int x = 0, x < 400, x++ {
        color c = getPixelColor(x, y)
        if c != white && c != blue {
            if inkFirst < 0 { inkFirst = x }
            inkLast = x
        }
    }
}

// Borders that take their space and paint nothing, so only the text is
// left to measure. The rows are the middle of each of the three lines,
// which sit 24 apart under the 20px spacer.
const text GHOST = 'color:black;padding:6px;border:4px solid transparent'

shot(150, GHOST)
scanInk(32)
int sliceL1First = inkFirst
int sliceL1Last = inkLast
scanInk(56)
int sliceL2First = inkFirst
check(sliceL1First >= 0 && sliceL2First >= 0, 'both lines have ink to measure')

shot(150, GHOST + CLONE)
scanInk(32)
checkEqInt(inkFirst, sliceL1First, 'clone leaves the first line where it was')
checkEqInt(inkLast, sliceL1Last,
           'and its closing edge overflows the line rather than breaking it early')
scanInk(56)
checkEqInt(inkFirst - sliceL2First, 10,
           'a continuation is pushed across by the opening edge clone gives it')

// ---- an inline-level box is painted once -------------------------------
//
// An in-flow inline-level box is CSS2 §9.9's step 5, reached through
// the line that holds it. It is also a child box, so a walk over the
// children that does not step over it paints the whole of it a second
// time. Nothing shows that while everything is opaque: the same pixels
// land on the same pixels. An `opacity` below 1 is what makes it
// visible, because a half-transparent box over itself is three
// quarters rather than a half.
//
// The number is not written down. The inline-block is asked for beside
// a *block* of the same colour at the same opacity, which is painted
// once by any order at all, and the two must land on the same pixel.
Page pop = pageFromHtml('<!doctype html><head><style>body{margin:0}'
    + '#wrap{background:#ffffff;line-height:0}'
    + '.half{opacity:0.5;background:#0000ff;width:60px;height:40px}'
    + '#ib{display:inline-block}'
    + '</style><body><div id="wrap"><span id="ib" class="half"></span></div>'
    + '<div id="bl" class="half"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(pop, 0, 0, 300)
color ibPixel = getPixelColor(30, 20)
color blPixel = getPixelColor(30, 60)
check(ibPixel == blPixel,
      'a half-transparent inline-block is painted once, as a block is')

finish('inline box')
