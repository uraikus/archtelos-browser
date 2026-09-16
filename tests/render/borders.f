// Border styles (Backgrounds and Borders 3 §4.3).
//
// Every border used to paint solid: the cascade derived one style for
// the whole box from whether any width was non-zero, so the declared
// keyword never reached the painter and a box could not have one style
// on one side and another on the next.
//
// What each style must look like is not equally specified. `double` is
// exact -- two parallel lines with a gap between them, each as close to
// a third of the border's width as the width allows -- so it is checked
// to the pixel. `dashed` and `dotted` are left to the user agent, which
// is why these checks ask what the standard actually requires, that the
// line be broken rather than solid, instead of inventing a dash length
// and pretending Chromium agrees with it.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color red = 'red'
color white = 'white'

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace">'

void func shotBox(style:text) {
    Page p = pageFromHtml(head + '<div style="width:60px;height:20px;' + style
        + '"></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// How many pixels along a row are the border colour and how many are
// not -- a solid line is all of the first, a broken one is some of each
// -- and how many separate marks the row is broken into, which is what
// tells a dotted line from a dashed one. The totals do not: both put a
// gap of its own length after every mark, so both cover about half the
// edge however often they break it.
int runRed = 0
int runGap = 0
int runMarks = 0
void func scanRow(y:int, x0:int, x1:int) {
    runRed = 0
    runGap = 0
    runMarks = 0
    bool inMark = false
    for int x = x0, x < x1, x++ {
        bool isRed = getPixelColor(x, y) == red
        if isRed { runRed++ } else { runGap++ }
        if isRed && !inMark { runMarks++ }
        inMark = isRed
    }
}

// ---- solid is the contrast the others are measured against -----------
shotBox('border-top:4px solid red')
scanRow(1, 0, 60)
check(runRed == 60, 'a solid border paints every pixel along its edge')
check(runGap == 0, 'with no gaps at all')

// ---- dashed is broken ------------------------------------------------
shotBox('border-top:4px dashed red')
scanRow(1, 0, 60)
check(runRed > 0, 'a dashed border paints something')
check(runGap > 0, 'and leaves gaps -- it is not the solid line it used to be')
check(runRed < 60, 'so it does not cover the whole edge')

// ---- dotted is broken too, and more finely ---------------------------
shotBox('border-top:4px dotted red')
scanRow(1, 0, 60)
int dottedMarks = runMarks
check(runRed > 0, 'a dotted border paints something')
check(runGap > 0, 'and leaves gaps')

shotBox('border-top:4px dashed red')
scanRow(1, 0, 60)
check(dottedMarks > runMarks, 'dotted breaks the line into more marks than dashed')

// ---- double is exact --------------------------------------------------
// Six pixels of width become two lines of two with a two-pixel gap: the
// standard says the lines and the gap are as near a third each as the
// width allows, and six divides exactly.
shotBox('border-top:6px double red')
check(getPixelColor(30, 0) == red, 'double paints its outer line at the outer edge')
check(getPixelColor(30, 1) == red, 'two pixels of it')
check(getPixelColor(30, 2) == white, 'then a gap')
check(getPixelColor(30, 3) == white, 'two pixels of that')
check(getPixelColor(30, 4) == red, 'then the inner line')
check(getPixelColor(30, 5) == red, 'two pixels of that, filling the six')

// ---- each side keeps its own style -------------------------------------
shotBox('border-top:4px solid red;border-bottom:4px dashed red')
scanRow(1, 0, 60)
int topRed = runRed
scanRow(26, 0, 60)
check(topRed == 60, 'the top border is solid')
check(runGap > 0, 'and the bottom one is dashed, on the same box')

// ---- and the left and right sides too -----------------------------------
shotBox('border-left:4px dotted red;border-right:4px solid red')
// only the left and right sides have a border here, so the box is the
// content's own 20 tall
int leftRed = 0
int leftGap = 0
for int y = 0, y < 20, y++ {
    if getPixelColor(1, y) == red { leftRed++ } else { leftGap++ }
}
int rightRed = 0
for int y = 0, y < 20, y++ {
    if getPixelColor(66, y) == red { rightRed++ }
}
check(leftRed > 0, 'a dotted left border paints something')
check(leftGap > 0, 'and breaks down its length')
check(rightRed == 20, 'while the solid right border is unbroken')

// ---- none still paints nothing -------------------------------------------
shotBox('border-top:4px none red')
check(getPixelColor(30, 1) == white, 'border-style: none paints nothing')

// ---- a style with no width still gives the medium default ----------------
shotBox('border-top-style:dashed;border-top-color:red')
scanRow(1, 0, 60)
check(runRed > 0, 'a style with no width takes the medium width and paints')
check(runGap > 0, 'dashed, not solid')

// ---- groove, ridge, inset and outset ------------------------------------
// These four shade an edge to suggest relief, and the standard leaves
// the two shades to the user agent: CSS2 §8.5.3 says only that the
// colours are "based on" the border colour. So these checks assert the
// relationships the standard does fix -- which edges differ from which,
// and which pair is the reverse of which -- rather than naming a shade
// and testing this engine's arithmetic against itself.
//
// The box is 60x20 of content inside an 8px border, so the top edge is
// rows 0-7, the bottom rows 28-35, and each edge's outer and inner
// halves are four rows each.

shotBox('border:8px solid red')
color solidTop = getPixelColor(38, 3)
color solidBottom = getPixelColor(38, 31)
check(solidTop == solidBottom, 'a solid border is the same colour on opposite edges')

shotBox('border:8px inset red')
color insetTop = getPixelColor(38, 3)
color insetBottom = getPixelColor(38, 31)
check(insetTop != insetBottom, 'inset shades the top and bottom differently')
check(insetTop != solidTop || insetBottom != solidBottom, 'and neither like a solid border')

shotBox('border:8px outset red')
color outsetTop = getPixelColor(38, 3)
color outsetBottom = getPixelColor(38, 31)
check(outsetTop != outsetBottom, 'outset shades them differently too')
check(outsetTop == insetBottom, 'and is inset turned over: its top is inset bottom')
check(outsetBottom == insetTop, 'and its bottom is inset top')

shotBox('border:8px groove red')
color grooveOuter = getPixelColor(38, 1)
color grooveInner = getPixelColor(38, 6)
check(grooveOuter != grooveInner, 'groove splits one edge into two shades')

shotBox('border:8px ridge red')
color ridgeOuter = getPixelColor(38, 1)
color ridgeInner = getPixelColor(38, 6)
check(ridgeOuter != ridgeInner, 'ridge splits it too')
check(ridgeOuter == grooveInner, 'and is groove turned over: its outer half is groove inner')
check(ridgeInner == grooveOuter, 'and its inner half is groove outer')

// The left and right edges take the same treatment as the top and
// bottom, which is what makes the whole box read as raised or sunken
// rather than only its horizontal edges.
shotBox('border:8px inset red')
check(getPixelColor(3, 18) != getPixelColor(72, 18), 'inset shades the left and right edges apart as well')

// ---- border-radius, per corner -------------------------------------------
// A radius rounds one corner away, so the pixel just inside that corner
// of the box stops being the box's own colour. Rounding one corner and
// leaving the other three square is the check that the four are kept
// apart rather than collapsed into one number, which is what used to
// happen: the shorthand's first token was taken and the rest dropped.
void func shotFill(style:text) {
    Page p = pageFromHtml(head + '<div style="width:40px;height:40px;'
        + 'background-color:red;' + style + '"></div></body>',
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

shotFill('')
check(getPixelColor(1, 1) == red, 'a square box fills its top-left corner')
check(getPixelColor(38, 1) == red, 'and its top-right')
check(getPixelColor(1, 38) == red, 'and its bottom-left')
check(getPixelColor(38, 38) == red, 'and its bottom-right')

shotFill('border-radius:20px 0 0 0')
check(getPixelColor(1, 1) != red, 'one radius rounds the top-left corner away')
check(getPixelColor(38, 1) == red, 'and leaves the top-right square')
check(getPixelColor(1, 38) == red, 'and the bottom-left')
check(getPixelColor(38, 38) == red, 'and the bottom-right')

shotFill('border-radius:0 20px 0 0')
check(getPixelColor(38, 1) != red, 'the second value is the top-right corner')
check(getPixelColor(1, 1) == red, 'not the top-left')

shotFill('border-radius:0 0 20px 0')
check(getPixelColor(38, 38) != red, 'the third is the bottom-right')
check(getPixelColor(1, 1) == red, 'still not the top-left')

shotFill('border-radius:0 0 0 20px')
check(getPixelColor(1, 38) != red, 'and the fourth is the bottom-left')
check(getPixelColor(38, 1) == red, 'leaving the top-right square')

// The longhands say the same thing as the shorthand's four slots.
shotFill('border-top-right-radius:20px')
check(getPixelColor(38, 1) != red, 'border-top-right-radius rounds that corner')
check(getPixelColor(1, 1) == red, 'and only that one')

// Two values are the two diagonals, as the shorthand's grammar says.
shotFill('border-radius:20px 0')
check(getPixelColor(1, 1) != red, 'two values round the first diagonal, top-left')
check(getPixelColor(38, 38) != red, 'and bottom-right')
check(getPixelColor(38, 1) == red, 'leaving the other diagonal square')



// ---- outline styles ------------------------------------------------------
// An outline is drawn just outside the border box and took no style at
// all: the cascade read `outline-style` only to decide whether the
// outline existed, and every outline painted solid. `@supports` said it
// was implemented, which is the lie the property instrument now catches.
//
// The outline is painted through the same code as a border side, so
// these ask the question the border checks ask -- is the line broken --
// rather than inventing a dash length.
// The wrapper is padded rather than the box margined, because a top
// margin here collapses through to the root and is dropped, which would
// put the outline's top edge above the canvas.
void func shotOutline(style:text) {
    Page p = pageFromHtml(head + '<div style="padding:10px"><div style="width:60px;'
        + 'height:20px;' + style + '"></div></div></body>',
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// The box starts at (10,10), and the outline is drawn outside it, so
// its top edge is the four rows above y=10 and it runs four pixels
// wider on each side.
shotOutline('outline:4px solid red')
scanRow(7, 10, 70)
check(runRed == 60, 'a solid outline paints every pixel along its edge')
check(runGap == 0, 'with no gaps')

shotOutline('outline:4px dashed red')
scanRow(7, 10, 70)
check(runRed > 0, 'a dashed outline paints something')
check(runGap > 0, 'and leaves gaps -- it is not the solid line it used to be')
int outlineDashedMarks = runMarks

shotOutline('outline:4px dotted red')
scanRow(7, 10, 70)
check(runGap > 0, 'a dotted outline leaves gaps too')
check(runMarks > outlineDashedMarks, 'and breaks the line into more marks than dashed')

// The longhand says the same as the shorthand's keyword.
shotOutline('outline-width:4px;outline-style:dashed;outline-color:red')
scanRow(7, 10, 70)
int longhandRed = runRed
int longhandMarks = runMarks
shotOutline('outline:4px dashed red')
scanRow(7, 10, 70)
checkEqInt(longhandRed, runRed, 'the outline longhands paint what the shorthand does')
checkEqInt(longhandMarks, runMarks, 'and break it in the same places')

// An outline with a style but no width is the medium three pixels, and
// one with no style at all paints nothing however wide it is asked to be.
shotOutline('outline-style:solid;outline-color:red')
scanRow(8, 10, 70)
check(runRed == 60, 'a styled outline with no width takes the medium width')
shotOutline('outline-width:4px;outline-color:red')
scanRow(7, 10, 70)
checkEqInt(runRed, 0, 'and an outline with no style paints nothing at all')

finish('borders')
