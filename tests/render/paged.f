// Painting a page of a paginated render (CSS2 §13).
//
// A page is the document drawn at an offset, inside the page box's
// margins. Nothing is moved to make one: the document is laid out once
// at the page area's width and each page is a strip of it, which is the
// same thing a scroll position is.
//
// What these check is the part that is not just an offset. A box taller
// than the page is painted whole -- the painter culls by box, not by
// pixel -- so without the margins being laid back over it afterwards its
// remainder would run through the bottom margin and off the sheet. That
// is a pixel question, and this is where it is asked.
import ../../src/browser/page.f
import ../assert.f

color white = 'white'
color red = 'red'
color blue = 'blue'

// A page box of 400x600 with 50px margins leaves an area 300x500.
text PAGE = '@page { size: 400px 600px; margin: 50px }'

void func printPage(css:text, body:text, index:int) {
    cssMediaPrint = true
    Page p = pageFromHtml('<!doctype html><html><head><style>' + css
        + '</style></head><body>' + body + '</body></html>', 'test.html', 300)
    paginateDocument(p.root)
    cssMediaPrint = false
    PageBox box = pageBoxes[index]
    setClientWidth(box.width)
    setClientHeight(box.height)
    clearCanvas()
    paintPagedPage(p, box, pageStartY[index], pageEndY[index], index, pageStartY.length)
}

int func pageCount(css:text, body:text) {
    cssMediaPrint = true
    Page p = pageFromHtml('<!doctype html><html><head><style>' + css
        + '</style></head><body>' + body + '</body></html>', 'test.html', 300)
    paginateDocument(p.root)
    cssMediaPrint = false
    return pageStartY.length
}

// ---- the margins are the page, and the content is inside them --------
text twoBlocks = 'body { margin: 0 } #a { height: 300px; background: red }'
    + ' #b { height: 300px; background: blue }'
text twoBody = '<div id="a"></div><div id="b"></div>'

checkEqInt(pageCount(PAGE + twoBlocks, twoBody), 2, 'two 300px blocks need two pages of 500')

printPage(PAGE + twoBlocks, twoBody, 0)
check(getPixelColor(200, 25) == white, 'the top margin is the page, not the document')
check(getPixelColor(25, 200) == white, 'and so is the left margin')
check(getPixelColor(375, 200) == white, 'and the right')
check(getPixelColor(200, 575) == white, 'and the bottom')
check(getPixelColor(200, 50) == red, 'the first block starts at the top margin')
check(getPixelColor(50, 200) == red, 'and at the left one')
check(getPixelColor(349, 200) == red, 'and reaches the right margin')
check(getPixelColor(350, 200) == white, 'without crossing it')
check(getPixelColor(200, 349) == red, 'the block ends where it should')
check(getPixelColor(200, 351) == white, 'and nothing follows it on this page')

// The second page carries what the first could not, at the same place
// on the sheet -- which is the whole of what a page is.
printPage(PAGE + twoBlocks, twoBody, 1)
check(getPixelColor(200, 25) == white, 'page two has the same top margin')
check(getPixelColor(200, 50) == blue, 'and begins with the block page one refused')
check(getPixelColor(200, 349) == blue, 'which runs its own 300px')
check(getPixelColor(200, 351) == white, 'and stops')

// ---- a box taller than the page --------------------------------------
// Nothing may break a single 700px block, so it straddles: page one
// carries the first 500 of it and page two the remaining 200. The
// painter draws the whole box either way, so this is the check that the
// margins are laid back over what ran past them.
text tall = 'body { margin: 0 } #t { height: 700px; background: red }'
text tallBody = '<div id="t"></div>'
checkEqInt(pageCount(PAGE + tall, tallBody), 2, 'a 700px block spans two pages of 500')

printPage(PAGE + tall, tallBody, 0)
check(getPixelColor(200, 50) == red, 'the tall block starts at the top margin')
check(getPixelColor(200, 549) == red, 'and fills the page area to its last row')
check(getPixelColor(200, 550) == white, 'and is cut at the bottom margin, not through it')
check(getPixelColor(200, 599) == white, 'with the margin still the page to the sheet edge')
check(getPixelColor(25, 300) == white, 'and the side margins uncrossed')

printPage(PAGE + tall, tallBody, 1)
check(getPixelColor(200, 50) == red, 'page two carries the rest of it')
check(getPixelColor(200, 249) == red, 'for the 200px that were left')
check(getPixelColor(200, 251) == white, 'and no more')
check(getPixelColor(200, 25) == white, 'its top margin is the page too')

// ---- the page box may differ from page to page ------------------------
// `@page :first` gives the first sheet a box of its own, so the two are
// not the same picture at a different offset -- which is what says the
// box is read per page rather than once.
text firstCss = '@page { size: 400px 600px; margin: 50px }'
    + ' @page :first { size: 400px 600px; margin: 150px }'
    + ' body { margin: 0 } #a { height: 200px; background: red }'
    + ' #b { height: 200px; background: blue }'
text firstBody = '<div id="a"></div><div id="b"></div>'
printPage(firstCss, firstBody, 0)
check(getPixelColor(200, 149) == white, 'page one takes the :first margin')
check(getPixelColor(200, 150) == red, 'so its content starts 150 down')
printPage(firstCss, firstBody, 1)
check(getPixelColor(200, 149) == blue, 'while page two starts 50 down')
check(getPixelColor(200, 25) == white, 'inside a margin of its own')

// ---- @media print reaches the page ------------------------------------
// A print stylesheet is the one that applies to a printed page, and a
// screen stylesheet is not. Both are asked, because a renderer that
// applied neither would pass a check that only asked about one.
// The base rule comes first, because a rule of equal specificity written
// after the media block would win on source order and the check would
// pass whatever the media type did.
text mediaCss = PAGE + ' body { margin: 0 } #a { height: 200px; background: white }'
    + ' @media print { #a { background: red } }'
printPage(mediaCss, '<div id="a"></div>', 0)
check(getPixelColor(200, 100) == red, 'printing, the print rule paints the block')

text screenCss = PAGE + ' body { margin: 0 } #a { height: 200px; background: white }'
    + ' @media screen { #a { background: blue } }'
printPage(screenCss, '<div id="a"></div>', 0)
check(getPixelColor(200, 100) == white, 'and the screen rule does not')

// ---- the margin boxes (CSS Paged Media 3 §5) --------------------------
//
// Sixteen boxes in the page margin, each generated from its own
// `content`. The measurements are in todo.md, read out of Chromium's
// print by inflating the PDF's content stream -- every string it drew
// and where its baseline is. The model they give is the standard's own
// §5.2 table, so it is the standard implemented here rather than the
// browser copied.
//
// These are ink checks rather than glyph checks: what a margin box has
// to get right is which band it is in and where in that band, and ink
// bounds say that without pinning a font's advances.

// Where the non-white pixels are in a rectangle, or -1 when there are
// none. Two values out of a function need globals (FINDINGS.md, "one
// value out of a function").
int inkLeft = -1
int inkRight = -1
int inkTop = -1
int inkBottom = -1

void func inkIn(x0:int, y0:int, x1:int, y1:int) {
    inkLeft = -1
    inkRight = -1
    inkTop = -1
    inkBottom = -1
    for int y = y0, y < y1, y++ {
        for int x = x0, x < x1, x++ {
            if getPixelColor(x, y) == white { continue }
            if inkLeft < 0 || x < inkLeft { inkLeft = x }
            if x > inkRight { inkRight = x }
            if inkTop < 0 || y < inkTop { inkTop = y }
            if y > inkBottom { inkBottom = y }
        }
    }
}

// Whether a rectangle holds a pixel of exactly this colour. A glyph's
// edge pixels are blended with the paper, so the question a colour
// check can answer is whether the colour is drawn at all, not what the
// corner of its ink bounds happens to be.
bool func hasColorIn(x0:int, y0:int, x1:int, y1:int, c:color) {
    for int y = y0, y < y1, y++ {
        for int x = x0, x < x1, x++ {
            if getPixelColor(x, y) == c { return true }
        }
    }
    return false
}

bool func anyInk(x0:int, y0:int, x1:int, y1:int) {
    inkIn(x0, y0, x1, y1)
    return inkLeft >= 0
}

// The page is 400x600 with 50px margins, so the bands are the top and
// bottom 50 rows and the left and right 50 columns, and the regions
// between the corners are x 50..350 and y 50..550.
text MB = '@page { size: 400px 600px; margin: 50px;'
text ONE = '<div style="height:10px"></div>'

// ---- nothing is drawn where nothing is declared -----------------------
printPage(PAGE, ONE, 0)
check(!anyInk(0, 0, 400, 50), 'a page with no margin boxes has a blank top band')
check(!anyInk(0, 550, 400, 600), 'and a blank bottom band')

// ---- the five along the top -------------------------------------------
printPage(MB + ' @top-center { content: "X" } }', ONE, 0)
check(anyInk(50, 0, 350, 50), 'top-center draws in the top band')
int centreMid = Math.floorDiv(inkLeft + inkRight, 2)
checkNear(centreMid, 200, 2, 'centred on the middle of the region')

printPage(MB + ' @top-left { content: "X" } }', ONE, 0)
check(anyInk(50, 0, 350, 50), 'top-left draws in the top band')
checkEqInt(inkLeft, 50, 'left-aligned at the region edge')

printPage(MB + ' @top-right { content: "X" } }', ONE, 0)
check(anyInk(50, 0, 350, 50), 'top-right draws in the top band')
checkEqInt(inkRight, 349, 'right-aligned at the region edge')

// The corners align INWARD, toward the page content: the left corner's
// text is right-aligned and the right corner's left-aligned. That is
// the one part of the table a reader would not guess.
printPage(MB + ' @top-left-corner { content: "X" } }', ONE, 0)
check(anyInk(0, 0, 50, 50), 'top-left-corner draws in the corner')
checkEqInt(inkRight, 49, 'right-aligned, toward the content')

printPage(MB + ' @top-right-corner { content: "X" } }', ONE, 0)
check(anyInk(350, 0, 400, 50), 'top-right-corner draws in the corner')
checkEqInt(inkLeft, 350, 'left-aligned, toward the content')

// ---- and the five along the bottom ------------------------------------
printPage(MB + ' @bottom-center { content: "X" } }', ONE, 0)
check(anyInk(50, 550, 350, 600), 'bottom-center draws in the bottom band')
checkNear(Math.floorDiv(inkLeft + inkRight, 2), 200, 2, 'centred there too')
printPage(MB + ' @bottom-left { content: "X" } }', ONE, 0)
check(anyInk(50, 550, 350, 600), 'bottom-left draws in the bottom band')
checkEqInt(inkLeft, 50, 'bottom-left is left-aligned')
printPage(MB + ' @bottom-right { content: "X" } }', ONE, 0)
check(anyInk(50, 550, 350, 600), 'bottom-right draws')
checkEqInt(inkRight, 349, 'and is right-aligned')
printPage(MB + ' @bottom-left-corner { content: "X" } }', ONE, 0)
check(anyInk(0, 550, 50, 600), 'bottom-left-corner draws in its corner')
printPage(MB + ' @bottom-right-corner { content: "X" } }', ONE, 0)
check(anyInk(350, 550, 400, 600), 'bottom-right-corner draws in its corner')

// ---- the three down each side ------------------------------------------
// Centred across the band, and top, middle or bottom of the region.
printPage(MB + ' @left-top { content: "X" } }', ONE, 0)
check(anyInk(0, 50, 50, 550), 'left-top draws in the left band')
int leftTopY = inkTop
checkNear(Math.floorDiv(inkLeft + inkRight, 2), 25, 2, 'centred across the band')
check(leftTopY >= 50 && leftTopY < 100, 'at the top of the region')

printPage(MB + ' @left-middle { content: "X" } }', ONE, 0)
check(anyInk(0, 50, 50, 550), 'left-middle draws in the left band')
checkNear(Math.floorDiv(inkTop + inkBottom, 2), 300, 12, 'about the middle of the region')

printPage(MB + ' @left-bottom { content: "X" } }', ONE, 0)
check(anyInk(0, 50, 50, 550), 'left-bottom draws in the left band')
check(inkBottom > 500, 'at the bottom of the region')

printPage(MB + ' @right-middle { content: "X" } }', ONE, 0)
check(anyInk(350, 50, 400, 550), 'right-middle draws in the right band')
checkNear(Math.floorDiv(inkLeft + inkRight, 2), 375, 2, 'centred across that band')

// ---- content: none, and an empty box ------------------------------------
printPage(MB + ' @top-center { content: none } }', ONE, 0)
check(!anyInk(0, 0, 400, 50), 'content: none draws nothing')
printPage(MB + ' @top-center { } }', ONE, 0)
check(!anyInk(0, 0, 400, 50), 'and an empty box draws nothing')

// ---- counter(page) and counter(pages) -----------------------------------
// The ink differs between page one and page two, which is what a page
// number is. Asserted as a difference rather than as a glyph, because
// what is being checked is that the counter is read per page.
text twoPage = MB + ' @bottom-center { content: counter(page) } }'
    + ' body { margin: 0 } #a { height: 300px } #b { height: 300px }'
text twoPageBody = '<div id="a"></div><div id="b"></div>'
checkEqInt(pageCount(twoPage, twoPageBody), 2, 'the counter fixture is two pages')
printPage(twoPage, twoPageBody, 0)
check(anyInk(50, 550, 350, 600), 'page one draws its number')
int oneLeft = inkLeft
int oneRight = inkRight
printPage(twoPage, twoPageBody, 1)
check(anyInk(50, 550, 350, 600), 'page two draws its own')
check(inkLeft != oneLeft || inkRight != oneRight, 'and it is a different number')

// ---- a margin box inherits from the ROOT element -------------------------
// The decisive pair in the measurement: `html` reaches a margin box and
// `body` does not, because the page context inherits from the root.
// The glyphs are drawn large, because a 16px stem is never a fully
// opaque pixel: at that size every pixel of the ink is the colour
// blended with the paper, and a check for the colour itself could not
// pass however right the colour was.
text bigBox = ' @top-center { content: "IIII"; font-size: 30px } }'
printPage(MB + bigBox + ' html { color: blue }', ONE, 0)
check(anyInk(50, 0, 350, 50), 'the margin box draws')
check(hasColorIn(50, 0, 350, 50, blue), 'in the colour the root element gives it')
printPage(MB + bigBox + ' body { color: blue }', ONE, 0)
check(anyInk(50, 0, 350, 50), 'and draws with a colour on body')
check(!hasColorIn(50, 0, 350, 50, blue), 'which does not reach it')

// The box's own declarations win over what it inherits, and both of
// the two it reads have to act.
printPage(MB + ' @top-center { content: "IIII"; font-size: 30px; color: blue } }'
    + ' html { color: red }', ONE, 0)
check(hasColorIn(50, 0, 350, 50, blue), 'a color on the box itself wins')
check(!hasColorIn(50, 0, 350, 50, red), 'over the one it would inherit')

// `font-size` is the second: the same string at two sizes is two
// different widths, which is a measurement neither number has to be
// known in advance for.
printPage(MB + ' @top-center { content: "IIII"; font-size: 10px } }', ONE, 0)
check(anyInk(50, 0, 350, 50), 'a small margin box draws')
int smallWide = inkRight - inkLeft
printPage(MB + ' @top-center { content: "IIII"; font-size: 30px } }', ONE, 0)
check(anyInk(50, 0, 350, 50), 'and a large one draws too')
check(inkRight - inkLeft > smallWide, 'wider, because font-size reaches a margin box')

// ---- @page :first selects a margin box ----------------------------------
text firstSel = MB + ' @top-center { content: "X" } }'
    + ' @page :first { @top-center { content: "XXXXXX" } }'
    + ' body { margin: 0 } #a { height: 300px } #b { height: 300px }'
printPage(firstSel, twoPageBody, 0)
check(anyInk(50, 0, 350, 50), 'the first page draws its own box')
int firstWide = inkRight - inkLeft
printPage(firstSel, twoPageBody, 1)
check(anyInk(50, 0, 350, 50), 'and the second draws the general one')
check(inkRight - inkLeft < firstWide, 'which is the narrower of the two')

// ---- print-color-adjust (CSS Color Adjustment 1 §3) --------------------
//
// The property overrides an omission rather than causing one: a print
// that draws every background cannot tell `economy` from `exact`, which
// is what Chromium's `--print-to-pdf` demonstrated by giving byte
// identical fills for both. What separates them there is
// `printToPDF`'s `printBackground`, and `printOmitBackgrounds` is the
// same switch here. Measured in todo.md.

text PCBOX = 'body { margin: 0 } #a { width: 200px; height: 100px'

// With nothing omitted the two values agree, which is the measurement
// rather than an implementation detail: asserted as an agreement so it
// holds whatever this engine's backgrounds look like.
printOmitBackgrounds = false
printPage(PAGE + PCBOX + '; background: red }', '<div id="a"></div>', 0)
check(getPixelColor(100, 100) == red, 'printing every background, an undeclared box paints one')
printPage(PAGE + PCBOX + '; background: red; print-color-adjust: economy }',
    '<div id="a"></div>', 0)
check(getPixelColor(100, 100) == red, 'and economy paints the same one')
printPage(PAGE + PCBOX + '; background: red; print-color-adjust: exact }',
    '<div id="a"></div>', 0)
check(getPixelColor(100, 100) == red, 'and so does exact')

// Omitting them is what gives the property something to say.
printOmitBackgrounds = true
printPage(PAGE + PCBOX + '; background: red }', '<div id="a"></div>', 0)
check(getPixelColor(100, 100) == white, 'omitting them, an undeclared box loses its background')
printPage(PAGE + PCBOX + '; background: red; print-color-adjust: economy }',
    '<div id="a"></div>', 0)
check(getPixelColor(100, 100) == white, 'and economy loses it too, being the initial value')
printPage(PAGE + PCBOX + '; background: red; print-color-adjust: exact }',
    '<div id="a"></div>', 0)
check(getPixelColor(100, 100) == red, 'and exact keeps it')

// A gradient is a background image rather than a colour, and goes the
// same way -- one function paints both, so this says the switch is on
// the background and not on the fill.
printPage(PAGE + PCBOX + '; background: linear-gradient(red, red) }',
    '<div id="a"></div>', 0)
check(getPixelColor(100, 100) == white, 'a background image goes with the colour')
printPage(PAGE + PCBOX + '; background: linear-gradient(red, red); print-color-adjust: exact }',
    '<div id="a"></div>', 0)
check(getPixelColor(100, 100) == red, 'and exact keeps that too')

// It inherits, and a child can withdraw it -- both measured in Chromium.
printPage(PAGE + 'body { margin: 0 } #p { print-color-adjust: exact }'
    + ' #a { width: 200px; height: 100px; background: red }',
    '<div id="p"><div id="a"></div></div>', 0)
check(getPixelColor(100, 100) == red, 'exact on the parent reaches an undeclared child')
printPage(PAGE + 'body { margin: 0 } #p { print-color-adjust: exact }'
    + ' #a { width: 200px; height: 100px; background: red; print-color-adjust: economy }',
    '<div id="p"><div id="a"></div></div>', 0)
check(getPixelColor(100, 100) == white, 'and the child can withdraw it again')

// Only the background goes. The text on top of it is still printed,
// which is the whole point of omitting the one and not the other.
printPage(PAGE + 'body { margin: 0 } #a { background: red; color: blue; font-size: 30px }',
    '<div id="a">IIII</div>', 0)
check(!hasColorIn(50, 50, 350, 120, red), 'the omitted background is gone')
check(hasColorIn(50, 50, 350, 120, blue), 'and the text over it is not')

printOmitBackgrounds = false


// ---- a side break's blank page (CSS 2 §13.3.1) ------------------------
//
// `left` and `right` force one or two breaks, so that the next page is
// formatted as a page of that side. Two means a blank page in between.
// The first page is a right page (CSS2 §13.2.4), so odd pages are right
// and even ones left, which is the parity `pageBoxFor` already uses.
//
// Chromium generates no blank page at all -- it prints `left`, `right`,
// `recto` and `verso` as a plain `page` break (todo.md). The standard is
// unambiguous, so this follows the standard and the disagreement is
// written down; that is also why these are graded against this engine's
// own page count rather than against the browser's.
text sideBlocks = 'body { margin: 0 } #a { height: 100px; background: red }'
    + ' #b { height: 100px; background: blue }'
text sideBody = '<div id="a"></div><div id="b"></div>'

text toLeft = PAGE + sideBlocks + ' #b { break-before: left }'
text toRight = PAGE + sideBlocks + ' #b { break-before: right }'
text toPage = PAGE + sideBlocks + ' #b { break-before: page }'

// Page one is a right page, so the left page that follows it is page
// two: `left` needs one break and must agree with `page` exactly.
checkEqInt(pageCount(toPage, sideBody), 2, 'a plain page break makes two pages')
checkEqInt(pageCount(toLeft, sideBody), pageCount(toPage, sideBody),
    'break-before: left needs no blank page after a right page')

// `right` wants page three, so page two is blank.
checkEqInt(pageCount(toRight, sideBody), 3, 'break-before: right generates the blank page')

// recto is right and verso is left, in a left-to-right document.
checkEqInt(pageCount(PAGE + sideBlocks + ' #b { break-before: recto }', sideBody),
    pageCount(toRight, sideBody), 'recto is right here')
checkEqInt(pageCount(PAGE + sideBlocks + ' #b { break-before: verso }', sideBody),
    pageCount(toLeft, sideBody), 'and verso is left')

// break-after asks the same question from the other side.
checkEqInt(pageCount(PAGE + sideBlocks + ' #a { break-after: right }', sideBody),
    pageCount(toRight, sideBody), 'break-after: right agrees with break-before: right')

// Two of them in a row: A on page 1, blank 2, B on 3, blank 4, C on 5.
text threeBlocks = 'body { margin: 0 } div { height: 100px }'
    + ' #b, #c { break-before: right }'
checkEqInt(pageCount(PAGE + threeBlocks, '<div id="a"></div><div id="b"></div><div id="c"></div>'),
    5, 'two right breaks generate two blank pages')

// The blank page carries the sheet and nothing else.
printPage(toRight, sideBody, 1)
check(getPixelColor(200, 25) == white, 'the blank page has its top margin')
check(getPixelColor(200, 200) == white, 'and nothing in its area')
check(getPixelColor(200, 575) == white, 'and its bottom margin')
check(!anyInk(0, 0, 400, 600), 'a generated blank page is blank')

// And the content lands on the page after it, unchanged.
printPage(toRight, sideBody, 2)
check(getPixelColor(200, 50) == blue, 'the break-before: right block is on page three')
check(getPixelColor(200, 149) == blue, 'all 100px of it')
check(getPixelColor(200, 151) == white, 'and nothing else')

// `@page :blank` selects the page this generated, which it could not
// before there was one to select (Paged Media 3 §3.5).
text blankSel = toRight + ' @page :blank { margin-top: 200px }'
printPage(blankSel, sideBody, 1)
checkEqInt(pageBoxes[1].marginTop, 200, '@page :blank matches the generated page')
printPage(blankSel, sideBody, 0)
checkEqInt(pageBoxes[0].marginTop, 50, 'and no other page')

finish('paged render')
