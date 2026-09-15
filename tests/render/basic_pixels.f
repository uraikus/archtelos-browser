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

finish('render')
