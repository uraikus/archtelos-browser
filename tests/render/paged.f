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
    paintPagedPage(p, box, pageStartY[index], pageEndY[index])
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

finish('paged render')
