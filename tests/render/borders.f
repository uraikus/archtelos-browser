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

finish('borders')
