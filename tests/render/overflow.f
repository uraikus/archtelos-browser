// `overflow: hidden` clips a box's descendants to its padding box
// (CSS2 §11.1.1).
//
// Overflow changes no geometry: Chromium lays the inner box out at
// 200x100 either way, and the container stays 100x40 with the next box
// at y=40. What changes is what is painted, so this is a pixel test.
//
// The canvas has no clip region. What it has is images that are
// themselves drawable surfaces and that clip at their own bounds --
// rectangles and text alike -- so a clipped subtree is painted into one
// and blitted back.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color red = 'red'
color green = 'green'
color white = 'white'
color grey = '#dddddd'

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace">'

// ---- hidden clips ----------------------------------------------------
Page p1 = pageFromHtml(head + '<div style="width:100px;height:40px;overflow:hidden;background:#dddddd">'
    + '<div style="width:200px;height:100px;background:red"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p1, 0, 0, 300)
check(getPixelColor(50, 20) == red, 'inside the container the child paints')
check(getPixelColor(150, 20) == white, 'past its width the child is clipped away')
check(getPixelColor(50, 60) == white, 'and past its height')

// ---- visible does not ------------------------------------------------
Page p2 = pageFromHtml(head + '<div style="width:100px;height:40px;background:#dddddd">'
    + '<div style="width:200px;height:100px;background:green"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p2, 0, 0, 300)
check(getPixelColor(50, 20) == green, 'without overflow the child paints inside')
check(getPixelColor(150, 20) == green, 'and past the width too')
check(getPixelColor(50, 60) == green, 'and past the height')

// ---- text is clipped, not just boxes ---------------------------------
// Text is the case a rectangle-by-rectangle clip cannot do, since a
// glyph has to be cut in half.
Page p3 = pageFromHtml(head + '<div style="width:40px;height:20px;overflow:hidden">'
    + '<span style="white-space:nowrap">WWWWWWWWWWWW</span></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p3, 0, 0, 300)
bool inkInside = false
bool inkOutside = false
for int x = 0, x < 40, x++ {
    for int y = 0, y < 20, y++ { if getPixelColor(x, y) != white { inkInside = true } }
}
for int x = 45, x < 200, x++ {
    for int y = 0, y < 20, y++ { if getPixelColor(x, y) != white { inkOutside = true } }
}
check(inkInside, 'the text paints inside the container')
check(!inkOutside, 'and is cut off at its edge')

// ---- the container itself still paints -------------------------------
Page p4 = pageFromHtml(head + '<div style="width:100px;height:40px;overflow:hidden;background:#dddddd"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p4, 0, 0, 300)
check(getPixelColor(50, 20) == grey, 'an empty clipping container paints its own background')
check(getPixelColor(150, 20) == white, 'and nothing beyond it')

// ---- a box after the container is where it should be -----------------
Page p5 = pageFromHtml(head + '<div style="width:100px;height:40px;overflow:hidden">'
    + '<div style="width:200px;height:100px;background:red"></div></div>'
    + '<div style="width:100px;height:20px;background:green"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(p5, 0, 0, 300)
check(getPixelColor(50, 50) == green, 'the next box follows the container, not its overflow')

// ---- containment (CSS Containment 1) -------------------------------------
// Paint containment clips a box's descendants to its padding box, the
// same thing `overflow: hidden` does and through the same layer.
// content-visibility: hidden goes further: the contents are not
// rendered at all, while the box itself still paints.

Page pContainPaint = pageFromHtml('<body style="margin:0">'
    + '<div style="width:40px;height:40px;contain:paint">'
    + '<div style="width:100px;height:100px;background:red"></div></div></body>',
    'test.html', 400)
clearCanvas()
paintPage(pContainPaint, 0, 0, 300)
check(getPixelColor(10, 10) == red, 'contain:paint leaves what is inside the box alone')
check(getPixelColor(60, 10) == white, 'and clips what runs out of it')

Page pNoContain = pageFromHtml('<body style="margin:0">'
    + '<div style="width:40px;height:40px">'
    + '<div style="width:100px;height:100px;background:red"></div></div></body>',
    'test.html', 400)
clearCanvas()
paintPage(pNoContain, 0, 0, 300)
check(getPixelColor(60, 10) == red, 'without it the overflow shows, so the clip is doing the work')

Page pHidden = pageFromHtml('<body style="margin:0">'
    + '<div style="width:40px;height:40px;background:green;content-visibility:hidden">'
    + '<div style="width:20px;height:20px;background:red"></div></div></body>',
    'test.html', 400)
clearCanvas()
paintPage(pHidden, 0, 0, 300)
check(getPixelColor(5, 5) == green, 'content-visibility:hidden still paints the box itself')
check(getPixelColor(10, 10) != red, 'and does not paint what is inside it')

finish('overflow')
