// Offscreen render checks: the pipeline draws onto the canvas and the
// test reads pixels back with getPixelColor. No window is opened.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color red = 'red'
color white = 'white'
color blue = 'blue'
color black = 'black'

Page p1 = pageFromHtml('<body style="margin:0"><div style="width:100px;height:50px;background:red"></div><div style="margin-left:20px;width:30px;height:30px;background:#00f;border:5px solid black"></div></body>', 'test.html', 400)
checkEqInt(p1.height, 90, 'document height')
clearCanvas()
paintPage(p1, 0, 0, 300)
check(getPixelColor(10, 10) == red, 'red div painted')
check(getPixelColor(150, 10) == white, 'canvas background white beside the div')
check(getPixelColor(10, 60) == white, 'nothing at x=10 below the first div (margin-left 20)')
check(getPixelColor(22, 52) == black, 'border painted')
check(getPixelColor(35, 65) == blue, 'inner blue box inside its border')
check(getPixelColor(10, 200) == white, 'below the content is background')

// scrolling: the same page painted with scrollY 50 puts the blue box at the top
clearCanvas()
paintPage(p1, 0, 50, 300)
check(getPixelColor(35, 15) == blue, 'scrolled paint moves content up')
check(getPixelColor(10, 10) == white, 'red div scrolled out of view')

// text is painted in its color; the background of body propagates
Page p2 = pageFromHtml('<body style="margin:0;background:#00f"><p style="margin:0;color:red;font-size:40px">IIII</p></body>', 'test.html', 400)
clearCanvas()
paintPage(p2, 0, 0, 300)
check(getPixelColor(390, 290) == blue, 'body background fills the viewport')
bool sawRed = false
for int x = 0, x < 60 && !sawRed, x++ {
    for int y = 0, y < 48 && !sawRed, y++ {
        if getPixelColor(x, y) == red { sawRed = true }
    }
}
check(sawRed, 'red glyph pixels painted')

// an image
Page p3 = pageFromHtml('<body style="margin:0"><img src="red.png" width="40" height="40"></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(p3, 0, 0, 300)
check(getPixelColor(20, 20) == red, 'image fetched relative to the page and drawn')
check(getPixelColor(45, 20) == white, 'image scaled to its width attribute')

// a link is hit-testable
Page p4 = pageFromHtml('<body style="margin:0"><p style="margin:0">go <a href="/next">there</a></p></body>', 'http://example.com/a/b.html', 400)
Line ln = p4.root.children[0].children[0].lines[0]
int linkX = ln.frags[2].x + 2
text href = linkAt(p4.root, linkX, 8)
checkEq(href, '/next', 'link found under the pointer')
checkEq(resolveUrl(p4.url, href), 'http://example.com/next', 'root-relative url resolves')
checkEq(resolveUrl(p4.url, '../c/d.html?x=1#f'), 'http://example.com/c/d.html?x=1#f', 'dot segments resolve')
checkEq(resolveUrl(p4.url, '//cdn.example.com/x.css'), 'http://cdn.example.com/x.css', 'protocol-relative url')
checkEq(resolveUrl(p4.url, 'https://other.org/p'), 'https://other.org/p', 'absolute url')
checkEq(resolveUrl('dir/page.html', 'img/a.png'), 'dir/img/a.png', 'relative file path')
checkEq(resolveUrl('http://h.com', 'x'), 'http://h.com/x', 'host without path')
check(linkAt(p4.root, 350, 8) == null, 'no link on empty space')

// a flex row actually paints side by side, not stacked: geometry the
// unit suite checks in numbers, checked here in pixels.
Page p5 = pageFromHtml('<body style="margin:0"><div style="display:flex;height:40px"><div style="width:60px;background:red"></div><div style="width:60px;background:blue"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p5, 0, 0, 300)
check(getPixelColor(30, 20) == red, 'the first flex item paints at the start of the row')
check(getPixelColor(90, 20) == blue, 'the second beside it, not below it')
check(getPixelColor(30, 60) == white, 'and nothing is stacked underneath')

// justify-content: flex-end moves the pair to the far edge
Page p6 = pageFromHtml('<body style="margin:0"><div style="display:flex;height:40px;justify-content:flex-end"><div style="width:60px;background:red"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p6, 0, 0, 300)
check(getPixelColor(370, 20) == red, 'flex-end paints the item against the far edge')
check(getPixelColor(30, 20) == white, 'and nothing at the start')

// an audio element with controls paints a bar; one without paints
// nothing at all
Page p7 = pageFromHtml('<body style="margin:0"><audio src="x.mp3" controls></audio></body>', 'test.html', 400)
clearCanvas()
paintPage(p7, 0, 0, 300)
check(getPixelColor(150, 27) != white, 'the audio controls paint a bar')
check(getPixelColor(150, 100) == white, 'and nothing below it')
check(getPixelColor(350, 27) == white, 'and nothing past its 300px width')

Page p8 = pageFromHtml('<body style="margin:0"><audio src="x.mp3"></audio></body>', 'test.html', 400)
clearCanvas()
paintPage(p8, 0, 0, 300)
check(getPixelColor(150, 27) == white, 'an audio without controls paints nothing')

// ---- list markers count in the system they were asked for ---------------
// The exact labels are checked in tests/unit/test_markers.f, which can
// compare strings; what these check is that the label reaches the
// marker, by painting the same list item under different systems and
// requiring the ink to differ. Two systems that agreed on every pixel
// would mean the style never reached the painter, which is what used to
// happen: every ordered list counted in arabic numerals.
text listHead = '<!doctype html><body style="margin:0;font:16px/20px monospace">'

arr[int] func markerInk(html:text, rowFrom:int, rowTo:int) {
    Page p = pageFromHtml(listHead + html + '</body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
    arr[int] out = []
    for int y = rowFrom, y < rowTo, y++ {
        int n = 0
        for int x = 0, x < 40, x++ { if getPixelColor(x, y) != white { n++ } }
        out.push(n)
    }
    return out
}

bool func sameInk(a:arr[int], b:arr[int]) {
    if a.length != b.length { return false }
    for int i = 0, i < a.length, i++ { if a[i] != b[i] { return false } }
    return true
}

text fourItems = '<li>x</li><li>x</li><li>x</li><li>x</li>'
arr[int] dec4 = markerInk('<ol style="list-style-type:decimal">' + fourItems + '</ol>', 60, 80)
arr[int] rom4 = markerInk('<ol style="list-style-type:lower-roman">' + fourItems + '</ol>', 60, 80)
arr[int] ROM4 = markerInk('<ol style="list-style-type:upper-roman">' + fourItems + '</ol>', 60, 80)
check(!sameInk(dec4, rom4), 'the fourth marker differs between decimal and lower-roman')
check(!sameInk(rom4, ROM4), 'and between lower-roman and upper-roman')

arr[int] one1 = markerInk('<ol type="1"><li>x</li></ol>', 0, 20)
arr[int] oneA = markerInk('<ol type="a"><li>x</li></ol>', 0, 20)
arr[int] oneI = markerInk('<ol type="I"><li>x</li></ol>', 0, 20)
check(!sameInk(one1, oneA), 'an ol type=a marker differs from type=1')
check(!sameInk(one1, oneI), 'and type=I differs from both')
check(!sameInk(oneA, oneI), 'as the attribute is meant to')

// ---- empty-cells (CSS2 17.6.1.1) -----------------------------------------
// In the separated borders model a cell with no content draws no
// background and no border when `empty-cells: hide`. The initial value
// is `show`, so the contrast is between the two.

text emptyCellDoc = '<body style="margin:0;font:16px/20px monospace">'
    + '<table style="border-spacing:0;EC"><tr>'
    + '<td style="width:40px;height:20px;background:red"></td>'
    + '<td style="width:40px;height:20px;background:blue">x</td>'
    + '</tr></table></body>'

Page pShow = pageFromHtml(emptyCellDoc.replace(regex('EC', 'g'), 'empty-cells:show'),
                          'test.html', 400)
clearCanvas()
paintPage(pShow, 0, 0, 300)
check(getPixelColor(10, 10) == red, 'empty-cells:show paints the empty cell')
check(getPixelColor(60, 10) == blue, 'and the cell that has content')

Page pHide = pageFromHtml(emptyCellDoc.replace(regex('EC', 'g'), 'empty-cells:hide'),
                          'test.html', 400)
clearCanvas()
paintPage(pHide, 0, 0, 300)
check(getPixelColor(10, 10) == white, 'empty-cells:hide leaves the empty cell unpainted')
check(getPixelColor(60, 10) == blue, 'and leaves the one with content alone')

// A cell holding only collapsible whitespace is empty too.
Page pBlank = pageFromHtml(emptyCellDoc.replace(regex('EC', 'g'), 'empty-cells:hide')
                               .replace(regex('background:red"></td>', 'g'), 'background:red"> </td>'),
                           'test.html', 400)
clearCanvas()
paintPage(pBlank, 0, 0, 300)
check(getPixelColor(10, 10) == white, 'a cell holding only whitespace counts as empty')

// ---- list-style-image ----------------------------------------------------
// A fetched image stands in for the marker, at its own size.

Page pMarkerPlain = pageFromHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<ul style="margin:0;padding-left:30px"><li>x</li></ul></body>',
    'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pMarkerPlain, 0, 0, 300)
int plainMarkerInk = 0
for int y = 0, y < 24, y++ {
    for int x = 0, x < 28, x++ { if getPixelColor(x, y) != white { plainMarkerInk++ } }
}
check(plainMarkerInk > 0, 'a list item has a marker of some kind to begin with')

Page pMarkerImage = pageFromHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<ul style="margin:0;padding-left:30px;list-style-image:url(red.png)">'
    + '<li>x</li></ul></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pMarkerImage, 0, 0, 300)
int imageMarkerRed = 0
for int y = 0, y < 24, y++ {
    for int x = 0, x < 28, x++ { if getPixelColor(x, y) == red { imageMarkerRed++ } }
}
check(imageMarkerRed > 0, 'list-style-image draws the image as the marker')

// `none` puts the bullet back, which is the check that the image is
// what changed rather than the marker disappearing.
Page pMarkerNone = pageFromHtml('<body style="margin:0;font:16px/20px monospace">'
    + '<ul style="margin:0;padding-left:30px;list-style-image:none">'
    + '<li>x</li></ul></body>', 'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pMarkerNone, 0, 0, 300)
int noneMarkerRed = 0
for int y = 0, y < 24, y++ {
    for int x = 0, x < 28, x++ { if getPixelColor(x, y) == red { noneMarkerRed++ } }
}
checkEqInt(noneMarkerRed, 0, 'and list-style-image:none leaves the bullet')

// ---- background-attachment ------------------------------------------------
// `fixed` anchors the background *image* to the viewport instead of the
// element, so it stays put as the page scrolls. It says nothing about a
// background colour, which is why the fixture uses an image: a colour
// fills its box either way and the property would look implemented
// whatever it did.

text tallDoc = '<body style="margin:0"><div style="height:600px;'
    + 'background-image:url(red.png);background-repeat:no-repeat;ATTACH">'
    + '</div></body>'

Page pScroll = pageFromHtml(tallDoc.replace(regex('ATTACH', 'g'), ''),
                            'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pScroll, 0, 0, 100)
check(getPixelColor(1, 1) == red, 'a scrolling background image starts at the element')
clearCanvas()
paintPage(pScroll, 0, 200, 100)
check(getPixelColor(1, 1) != red, 'and scrolls away with it')

Page pFixed = pageFromHtml(tallDoc.replace(regex('ATTACH', 'g'),
                                           'background-attachment:fixed'),
                           'tests/fixtures/page.html', 400)
clearCanvas()
paintPage(pFixed, 0, 0, 100)
check(getPixelColor(1, 1) == red, 'a fixed background image starts there too')
clearCanvas()
paintPage(pFixed, 0, 200, 100)
check(getPixelColor(1, 1) == red, 'and stays where it is when the page scrolls')

finish('render')
