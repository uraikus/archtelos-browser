// CSS Text Decoration 3.
//
// The engine had `underline` and `line-through` and nothing else: no
// `overline`, and no colour, style, thickness or offset, so every
// decoration was a one-pixel solid line in the text's own colour. It
// also drew a decoration in the colour of whatever box it was painting
// rather than the colour of the box that asked for it, which is the
// whole point of a decoration propagating rather than inheriting.
//
// A decoration line paints as flat colour while a glyph is
// antialiased, so an exact colour match finds the line and not the
// text -- which is what lets these checks ask where the line is
// without depending on the font's metrics.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color black = 'black'
color blue = 'blue'
color red = 'red'

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;color:black">'

void func shotText(style:text, content:text) {
    Page p = pageFromHtml(head + '<div style="' + style + '">' + content
        + '</div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// The rows, top to bottom, that carry a solid run of this colour across
// the whole of the text's width. Each decoration line is one such run;
// a glyph never is.
arr[int] func solidRows(c:color, y0:int, y1:int) {
    arr[int] out = []
    for int y = y0, y < y1, y++ {
        bool all = true
        for int x = 2, x < 36, x++ {
            if getPixelColor(x, y) != c { all = false }
        }
        if all { out.push(y) }
    }
    return out
}

// How many separate lines those rows make: rows that touch are one
// line, a gap between them starts another. This is what tells `double`
// from `solid` and counts three decorations on one box.
int func lineCount(rows:arr[int]) {
    int n = 0
    for int i = 0, i < rows.length, i++ {
        if i == 0 || rows[i] != rows[i - 1] + 1 { n++ }
    }
    return n
}

// The first of those rows, or -1. Reading `rows[0]` directly is how an
// empty result turned into a plausible row number here: an index past
// the end of an `arr` is unchecked (FINDINGS.md, finding 32).
int func firstRow(rows:arr[int]) {
    if rows.length == 0 { return -1 }
    return rows[0]
}

// Anything painted at all. A glyph is antialiased, so it never matches
// a colour exactly the way a decoration line does; this is the question
// to ask about the text itself.
int func countInk(x0:int, y0:int, x1:int, y1:int) {
    color white = 'white'
    int n = 0
    for int y = y0, y < y1, y++ {
        for int x = x0, x < x1, x++ {
            if getPixelColor(x, y) != white { n++ }
        }
    }
    return n
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

// ---- the three lines, and where each of them goes ------------------------

shotText('', 'xxxx')
checkEqInt(solidRows(black, 0, 24).length, 0, 'undecorated text draws no line at all')

shotText('text-decoration:underline', 'xxxx')
arr[int] under = solidRows(black, 0, 24)
checkEqInt(lineCount(under), 1, 'underline draws one line')
int underY = firstRow(under)

shotText('text-decoration:overline', 'xxxx')
arr[int] over = solidRows(black, 0, 24)
checkEqInt(lineCount(over), 1, 'overline draws one line -- it used to draw none')
check(firstRow(over) < underY && firstRow(over) >= 0, 'and draws it above the underline')

shotText('text-decoration:line-through', 'xxxx')
arr[int] through = solidRows(black, 0, 24)
checkEqInt(lineCount(through), 1, 'line-through draws one line')
check(firstRow(through) < underY && firstRow(through) >= 0, 'between the overline and the underline')
check(firstRow(through) > firstRow(over) && firstRow(over) >= 0, 'and below the overline')

shotText('text-decoration:underline overline line-through', 'xxxx')
checkEqInt(lineCount(solidRows(black, 0, 24)), 3, 'all three at once draw three lines')

// ---- the colour ----------------------------------------------------------

shotText('color:red;text-decoration:underline', 'xxxx')
checkEqInt(lineCount(solidRows(red, 0, 24)), 1, 'a decoration takes the text colour by default')

shotText('color:red;text-decoration:underline;text-decoration-color:blue', 'xxxx')
checkEqInt(lineCount(solidRows(blue, 0, 24)), 1, 'text-decoration-color colours the line')
checkEqInt(lineCount(solidRows(red, 0, 24)), 0, 'and the line is no longer the text colour')
check(countInk(0, 0, 40, 24) > 0, 'while the text itself is still painted')

// The shorthand says the same thing as the longhands.
shotText('color:red;text-decoration:underline blue', 'xxxx')
arr[int] shorthandBlue = solidRows(blue, 0, 24)
shotText('color:red;text-decoration-line:underline;text-decoration-color:blue', 'xxxx')
arr[int] longhandBlue = solidRows(blue, 0, 24)
checkEqInt(shorthandBlue.length, longhandBlue.length, 'the shorthand takes a colour, as the longhands do')
check(longhandBlue.length > 0, 'and both draw a line')
checkEqInt(firstRow(shorthandBlue), firstRow(longhandBlue), 'in the same place')

// ---- the style -----------------------------------------------------------

shotText('text-decoration:underline;text-decoration-style:double', 'xxxx')
checkEqInt(lineCount(solidRows(black, 0, 24)), 2, 'text-decoration-style:double draws two lines')

shotText('text-decoration:underline;text-decoration-style:dotted', 'xxxx')
checkEqInt(solidRows(black, 0, 24).length, 0, 'a dotted decoration is not a solid run')
check(countColor(black, 0, 0, 40, 24) > 0, 'but it does paint something')

shotText('text-decoration:underline;text-decoration-style:dashed', 'xxxx')
checkEqInt(solidRows(black, 0, 24).length, 0, 'nor is a dashed one')

shotText('text-decoration:underline;text-decoration-style:wavy', 'xxxx')
checkEqInt(solidRows(black, 0, 24).length, 0, 'nor a wavy one')
check(countColor(black, 0, 0, 40, 24) > 0, 'and the wave paints something')

// The shorthand's third part is the style.
shotText('text-decoration:underline double', 'xxxx')
checkEqInt(lineCount(solidRows(black, 0, 24)), 2, 'the shorthand takes a style too')

// ---- thickness and offset ------------------------------------------------

shotText('text-decoration:underline', 'xxxx')
int thinRows = solidRows(black, 0, 24).length
shotText('text-decoration:underline;text-decoration-thickness:5px', 'xxxx')
check(solidRows(black, 0, 24).length > thinRows, 'text-decoration-thickness makes the line thicker')

shotText('text-decoration:underline;text-underline-offset:6px', 'xxxx')
arr[int] moved = solidRows(black, 0, 24)
check(moved.length > 0, 'an offset underline is still drawn')
check(firstRow(moved) > underY, 'and text-underline-offset pushes it further from the text')

// An offset moves the underline and leaves the overline where it is.
shotText('text-decoration:overline;text-underline-offset:6px', 'xxxx')
arr[int] overMoved = solidRows(black, 0, 24)
check(overMoved.length > 0, 'the overline survives an underline offset')
checkEqInt(firstRow(overMoved), firstRow(over), 'and does not move -- the offset is the underline\'s')

// ---- a decoration belongs to the box that asked for it -------------------
// The standard draws the decoration of an ancestor across its
// descendants in the ancestor's own colour. This drew it in the colour
// of whichever box it happened to be painting.

shotText('color:red;text-decoration:underline', '<span style="color:blue">xxxx</span>')
checkEqInt(lineCount(solidRows(red, 0, 24)), 1,
           'a propagated decoration keeps the colour of the box that asked for it')
checkEqInt(lineCount(solidRows(blue, 0, 24)), 0, 'not the colour of the box it crosses')

// The same for its style: the ancestor's style, not the descendant's.
shotText('text-decoration:underline;text-decoration-style:double',
         '<span style="text-decoration-style:solid">xxxx</span>')
checkEqInt(lineCount(solidRows(black, 0, 24)), 2,
           'and the style of the box that asked for it')

// ---- text-shadow ---------------------------------------------------------
// A shadow of the text, offset and blurred, painted underneath it.

shotText('text-decoration:underline', 'xxxx')
int plainInk = countColor(black, 0, 0, 80, 24)
checkEqInt(countColor(red, 44, 0, 80, 24), 0, 'nothing is painted to the right of the text')

shotText('text-decoration:underline;text-shadow:20px 0 red', 'xxxx')
check(countColor(red, 44, 0, 80, 24) > 0, 'text-shadow paints an offset copy of the text')
checkEqInt(countColor(black, 0, 0, 80, 24), plainInk, 'and leaves the text itself alone')

// Two shadows are two copies.
shotText('text-decoration:underline;text-shadow:20px 0 red, 40px 0 blue', 'xxxx')
check(countColor(red, 44, 0, 80, 24) > 0, 'the first of two shadows is painted')
check(countColor(blue, 64, 0, 100, 24) > 0, 'and so is the second')

// A blur does two things, and the check asks for both: it spreads the
// shadow over more pixels, and it softens them, so what was the full
// colour no longer is. The underline is in the fixture because a
// decoration line paints as flat colour -- a glyph is antialiased and
// is never the full colour to begin with, so on glyphs alone the
// second half of the question has the same answer either way.
shotText('text-decoration:underline;text-shadow:20px 0 0 red', 'xxxx')
int sharpInk = countInk(20, 0, 80, 24)
int sharpFull = countColor(red, 20, 0, 80, 24)
check(sharpFull > 0, 'a sharp shadow paints its colour outright')

shotText('text-decoration:underline;text-shadow:20px 0 6px red', 'xxxx')
check(countInk(20, 0, 80, 24) > sharpInk, 'a blurred shadow covers more than a sharp one')
checkEqInt(countColor(red, 20, 0, 80, 24), 0, 'and none of it is the full colour any more')

// ---- text-emphasis -------------------------------------------------------
// A mark drawn beside each character, over it by default and under it
// when asked. The mark is a glyph, so it is antialiased and counted as
// ink rather than matched by colour -- the same reason the text itself
// is.

// The fixture is given a tall line box, because an emphasis mark does
// not reserve space for itself here: in a line only as tall as its
// font there is nowhere above the ascender for the mark to go, and it
// would fall outside the line. css-2026.md records that.
text tall = 'line-height:40px;'

// With a 40px line box and a 16px font the text sits around y=12 to
// y=24, so the rows above and below it are empty until a mark is asked
// for.
shotText(tall, 'xx')
int plainAbove = countInk(0, 0, 40, 10)
int plainBelow = countInk(0, 30, 40, 40)

shotText(tall + 'text-emphasis:filled dot', 'xx')
check(countInk(0, 0, 40, 10) > plainAbove, 'text-emphasis draws a mark above the text')
checkEqInt(countInk(0, 30, 40, 40), plainBelow, 'and not below it')

shotText(tall + 'text-emphasis:filled dot;text-emphasis-position:under', 'xx')
check(countInk(0, 30, 40, 40) > plainBelow, 'text-emphasis-position:under puts it below')
checkEqInt(countInk(0, 0, 40, 10), plainAbove, 'and not above')

// One mark per character, so more characters make more marks.
shotText(tall + 'text-emphasis:filled dot', 'x')
int oneMark = countInk(0, 0, 60, 10)
shotText(tall + 'text-emphasis:filled dot', 'xxx')
check(countInk(0, 0, 60, 10) > oneMark, 'a mark is drawn beside every character')

// The colour is its own.
shotText(tall + 'color:red;text-emphasis:filled dot blue', 'xx')
check(countColor(blue, 0, 0, 40, 10) > 0, 'text-emphasis takes a colour of its own')
shotText(tall + 'color:red;text-emphasis:filled dot', 'xx')
checkEqInt(countColor(blue, 0, 0, 40, 10), 0, 'and is the text colour when none is given')

// `none` is the initial value and draws nothing.
shotText(tall + 'text-emphasis:none', 'xx')
checkEqInt(countInk(0, 0, 40, 10), plainAbove, 'text-emphasis:none draws no mark')

// The longhands say what the shorthand says.
shotText(tall + 'text-emphasis:filled dot blue', 'xx')
int shorthandMark = countInk(0, 0, 40, 10)
shotText(tall + 'text-emphasis-style:filled dot;text-emphasis-color:blue', 'xx')
checkEqInt(countInk(0, 0, 40, 10), shorthandMark,
           'the text-emphasis longhands draw what the shorthand draws')

// A string is drawn as itself.
shotText(tall + 'text-emphasis:\'*\'', 'xx')
check(countInk(0, 0, 40, 10) > plainAbove, 'a string emphasis mark is drawn too')

// ---- text-underline-position ---------------------------------------------
// `under` drops the underline below the descenders instead of sitting
// it on the alphabetic baseline.

// Four characters, because solidRows asks for a run across the whole
// width it scans and two would not reach it.
shotText('text-decoration:underline', 'xxxx')
arr[int] atBaseline = solidRows(black, 0, 24)
shotText('text-decoration:underline;text-underline-position:under', 'xxxx')
arr[int] dropped = solidRows(black, 0, 24)
check(firstRow(dropped) > firstRow(atBaseline),
      'text-underline-position:under drops the underline below the baseline')
check(firstRow(atBaseline) >= 0, 'and both are drawn')

finish('decoration')
