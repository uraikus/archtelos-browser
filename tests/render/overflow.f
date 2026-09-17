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

// ---- `scroll` and `auto` draw a scrollbar in the room they took -------
// A scroll container reserves fifteen pixels inside its padding box and
// paints a scrollbar there: a track, and a thumb as long a share of it
// as the box is of the content it scrolls. The colours are Chromium's
// classic scrollbar -- a #fcfcfc track and a #8b8b8b thumb -- so that
// the pixels can be compared with its own, which for the page below
// reads #fcfcfc at the track's edge and #8b8b8b through the middle of
// the thumb.
//
// The geometry is checked in tests/unit/test_layout.f; what these ask
// is whether anything is drawn in the room it took, which the geometry
// cannot tell.
color track = '#fcfcfc'
color thumb = '#8b8b8b'
color pale = '#ddffdd'

Page pscroll = pageFromHtml(head
    + '<div style="width:200px;height:100px;overflow:scroll;background:#ddffdd">'
    + '<div style="height:300px"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(pscroll, 0, 0, 300)
check(getPixelColor(100, 20) == pale, 'the content area keeps the box\'s own background')
check(getPixelColor(186, 20) == track, 'the vertical scrollbar draws its track beside it')
check(getPixelColor(192, 10) == thumb, 'with a thumb down the middle of the track')
check(getPixelColor(192, 80) == track,
      'which is only a share of it, because the content is three times the box')
check(getPixelColor(20, 92) == track, 'and a horizontal track along the bottom')

// `auto` with nothing to scroll draws neither, and leaves the whole
// width to the content.
Page pauto = pageFromHtml(head
    + '<div style="width:200px;height:100px;overflow:auto;background:#ddffdd">'
    + '<div style="height:20px"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(pauto, 0, 0, 300)
check(getPixelColor(186, 20) == pale, '`auto` draws no track while there is nothing to scroll')
check(getPixelColor(196, 50) == pale, 'and the content keeps the width the bar would have taken')

// `auto` with content past the bottom draws the vertical one only.
Page pauto2 = pageFromHtml(head
    + '<div style="width:200px;height:100px;overflow:auto;background:#ddffdd">'
    + '<div style="height:300px"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(pauto2, 0, 0, 300)
check(getPixelColor(192, 10) == thumb, '`auto` draws the bar once the content overflows')
check(getPixelColor(20, 92) == pale, 'and only the one axis that overflows')

finish('overflow')
