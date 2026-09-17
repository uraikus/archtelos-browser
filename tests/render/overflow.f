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

// ---- and what it scrolls ----------------------------------------------
// Scrolling moves the content and leaves the box, its background and
// its scrollbars where they are. The offset is kept by the id of the
// element rather than on the box, because a box tree lasts one layout
// and a scroll position has to outlive several.
color band1 = '#ff0000'
color band2 = '#0000ff'

Box func scrollBoxOf(p:Page) {
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == 'sc' { return all[i] }
    }
    return null
}

boxScrollReset()
Page pmove = pageFromHtml(head
    + '<div id="sc" style="width:200px;height:100px;overflow:scroll;background:#ddffdd">'
    + '<div style="height:50px;background:#ff0000"></div>'
    + '<div style="height:50px;background:#0000ff"></div>'
    + '<div style="height:300px"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(pmove, 0, 0, 300)
check(getPixelColor(50, 10) == band1, 'the first band paints at the top of the box')
check(getPixelColor(50, 60) == band2, 'and the second below it')

Box sc = scrollBoxOf(pmove)
check(sc != null, 'the scroll container is in the box tree')
check(boxScrollRange(sc) == 315,
      'which can scroll its content less what is visible of it: 400 against 85')
check(boxScrollBy(sc, 50), 'scrolling it by fifty moves it')
clearCanvas()
paintPage(pmove, 0, 0, 300)
check(getPixelColor(50, 10) == band2, 'and brings the second band to the top')
check(getPixelColor(50, 60) != band2, 'with the rest of the content moved with it')
check(getPixelColor(186, 20) == track, 'while the scrollbar stays where it is')
check(getPixelColor(100, 95) != band2, 'and the horizontal bar is not scrolled either')

// The thumb says where in the content the box is: at the top it starts
// at the track's top, and scrolled it has moved down by the same share.
check(getPixelColor(192, 4) == track, 'the thumb has moved off the top of its track')
check(getPixelColor(192, 12) == thumb, 'to where the content is through what there is of it')

// A wheel over the box scrolls the box; over the page outside it, the
// page. Asking which is the innermost scroll container under the point
// is what the shell does with its own wheel.
// Two struct values cannot be compared with `==` (FINDINGS.md, finding
// 37), so the box that comes back is identified by the element behind
// it rather than by being the same box.
Box foundIn = scrollContainerAt(pmove.root, 50, 50, 1)
check(foundIn != null && foundIn.node.id == sc.node.id,
      'a point inside the box finds it as the container to scroll')
check(scrollContainerAt(pmove.root, 300, 50, 1) == null,
      'and a point outside it finds nothing, so the page takes the wheel')

// The offset stops at the end of the content and at the start of it.
check(boxScrollBy(sc, 10000), 'a wheel past the end still moves it')
check(!boxScrollBy(sc, 10000), 'but not once it is there, which is what hands the page the rest')
check(boxScrollBy(sc, 0 - 10000), 'and the same at the top')
check(!boxScrollBy(sc, 0 - 10000), 'where it stops as well')
clearCanvas()
paintPage(pmove, 0, 0, 300)
check(getPixelColor(50, 10) == band1, 'back at the top the first band is back')
check(scrollContainerAt(pmove.root, 50, 50, 0 - 1) == null,
      'and a wheel upwards there finds nothing, because there is nowhere to go')
Box foundDown = scrollContainerAt(pmove.root, 50, 50, 1)
check(foundDown != null && foundDown.node.id == sc.node.id,
      'while downwards still finds the box')

// A link inside a scrolled box is where it looks, not where it was laid
// out: hit testing asks the box how far it has been scrolled.
boxScrollReset()
Page plink = pageFromHtml(head
    + '<div id="sc" style="width:200px;height:100px;overflow:scroll">'
    + '<div style="height:120px"></div><a href="deep.html">link</a></div></body>',
    'test.html', 400)
clearCanvas()
paintPage(plink, 0, 0, 300)
check(linkAt(plink.root, 20, 70) == null, 'the link is past the bottom of the box to start with')
Box scl = scrollBoxOf(plink)
// The spacer is 120 and the line about 20, so the content is 140 and
// the visible part 85: fifty-five pixels of scrolling, which a wheel of
// any size ends at. The link then sits at 65 rather than 120.
checkEqInt(boxScrollRange(scl), 55, 'the box scrolls by what its content exceeds it by')
check(boxScrollBy(scl, 400), 'scrolling to the end brings the link up')
check(linkAt(plink.root, 20, 70) == 'deep.html', 'and clicking where it now is finds it')

// ---- the thumb can be taken hold of -----------------------------------
// A press on the thumb takes hold of it and moving the pointer scrolls
// the box. What makes that safe to check is that the painter draws the
// thumb from the same four functions the pointer is tested against, so
// the two cannot drift: the pixel checks above already say the thumb is
// drawn where those functions put it.
Page pdrag = pageFromHtml(head
    + '<div id="d" style="width:200px;height:100px;overflow:auto;background:#ddffdd">'
    + '<div style="height:300px"></div></div></body>', 'test.html', 400)
arr[Box] dboxes = []
collectBoxesForTag(pdrag.root, 'div', dboxes)
Box drag = dboxes[0]
check(drag != null && drag.sbW == 15, 'the box has a vertical scrollbar')
boxScrollReset()

int tTop = scrollTrackTop(drag)
int tRun = scrollTrackHeight(drag) - scrollThumbHeight(drag)
int tMidX = scrollThumbLeft(drag) + Math.floorDiv(scrollThumbWidth(drag), 2)

// Where the thumb is, and where it is not.
check(scrollThumbAt(pdrag.root, tMidX, tTop + 2) != null, 'the pointer finds the thumb on it')
check(scrollThumbAt(pdrag.root, tMidX, tTop + scrollTrackHeight(drag) - 2) == null,
      'and finds nothing on the empty part of the track')
check(scrollThumbAt(pdrag.root, 100, tTop + 2) == null, 'nor anywhere off the bar')

// Dragging it the length of its run scrolls the box the whole way, and
// dragging it back brings it back.
check(scrollThumbDragTo(drag, tTop + tRun), 'dragging the thumb to the end scrolls the box')
checkEqInt(boxScrollTop(drag), boxScrollRange(drag), 'all the way to the end')
check(scrollThumbDragTo(drag, tTop), 'and dragging it back to the top')
checkEqInt(boxScrollTop(drag), 0, 'scrolls the box back to the start')

// Half way down the run is half way through the content, to the pixel
// the integer division lands on.
check(scrollThumbDragTo(drag, tTop + Math.floorDiv(tRun, 2)), 'a drag to the middle moves it')
checkEqInt(boxScrollTop(drag),
           Math.floorDiv(Math.floorDiv(tRun, 2) * boxScrollRange(drag), tRun),
           'and lands where that share of the run says')

// The thumb moves with the content, which is the agreement that matters:
// wherever the box is scrolled to, the pointer finds the thumb at the
// place the painter has just drawn it.
boxScrollReset()
boxScrollBy(drag, 400)
check(scrollThumbAt(pdrag.root, tMidX, scrollThumbTop(drag) + 2) != null,
      'after scrolling, the thumb is found where it is now drawn')
checkEqInt(scrollThumbTop(drag) + scrollThumbHeight(drag),
           tTop + scrollTrackHeight(drag),
           'and a box scrolled to its end puts the thumb at the end of its track')
boxScrollReset()

// ---- the horizontal axis scrolls too ----------------------------------
// A box whose content is wider than it is scrolls across as well as
// down. Chromium 141 on a 200x100 `overflow: auto` box holding a 500x50
// child: clientWidth 200, clientHeight 85 -- the horizontal bar took
// its fifteen -- scrollWidth 500, and `scrollLeft` clamps to 300, which
// is 500 less the 200 that is visible.
Page pacross = pageFromHtml(head
    + '<div id="a" style="width:200px;height:100px;overflow:auto;background:#ddffdd">'
    + '<div style="width:500px;height:50px">'
    + '<div style="width:40px;height:20px;margin-left:220px;background:#ff0000"></div>'
    + '</div></div></body>', 'test.html', 400)
arr[Box] aboxes = []
collectBoxesForTag(pacross.root, 'div', aboxes)
Box across = aboxes[0]
boxScrollReset()
check(across != null && across.sbH == 15, 'the wide content raised a horizontal bar')
checkEqInt(across.sbW, 0, 'and the short content raised no vertical one')
checkEqInt(across.scrollW, 500, 'the scrollable width is the content')
checkEqInt(boxScrollLeftRange(across), 300,
           'and it scrolls across by what the content exceeds the box by')

// It clamps at both ends, as `scrollLeft` does.
check(boxScrollLeftBy(across, 10000), 'scrolling far to the right moves it')
checkEqInt(boxScrollLeft(across), 300, 'and stops at the end rather than past it')
check(boxScrollLeftBy(across, 0 - 10000), 'scrolling back moves it again')
checkEqInt(boxScrollLeft(across), 0, 'and stops at the start')

// The content moves under the box: a block 220px along the content is
// off the right of a 200px box until the box is scrolled to it.
color redMark = '#ff0000'
boxScrollReset()
clearCanvas()
paintPage(pacross, 0, 0, 300)
check(!(getPixelColor(100, 10) == redMark), 'the mark past the right edge is not painted')
boxScrollLeftBy(across, 150)
clearCanvas()
paintPage(pacross, 0, 0, 300)
check(getPixelColor(100, 10) == redMark, 'and scrolling across brings it into the box')
boxScrollReset()

// The horizontal thumb is found and dragged the same way the vertical
// one is, from the same shared geometry the painter draws it with.
int hLeft = scrollHThumbLeft(across)
int hTop = scrollHTrackTop(across)
int hRun = scrollHTrackWidth(across) - scrollHThumbWidth(across)
int hMidY = hTop + Math.floorDiv(across.sbH, 2)
check(scrollHThumbAt(pacross.root, hLeft + 2, hMidY) != null, 'the pointer finds the thumb on it')
check(scrollHThumbAt(pacross.root, hLeft + scrollHTrackWidth(across) - 2, hMidY) == null,
      'and finds nothing on the empty part of the track')
check(scrollHThumbAt(pacross.root, hLeft + 2, 10) == null, 'nor above the bar')

check(scrollHThumbDragTo(across, scrollHTrackLeft(across) + hRun),
      'dragging the thumb to the end scrolls the box')
checkEqInt(boxScrollLeft(across), boxScrollLeftRange(across), 'all the way across')
check(scrollHThumbDragTo(across, scrollHTrackLeft(across)), 'and dragging it back')
checkEqInt(boxScrollLeft(across), 0, 'brings it back to the start')

// The thumb moves with the content, which is the agreement that matters.
boxScrollLeftBy(across, 1000)
check(scrollHThumbAt(pacross.root, scrollHThumbLeft(across) + 2, hMidY) != null,
      'after scrolling, the thumb is found where it is now drawn')
checkEqInt(scrollHThumbLeft(across) + scrollHThumbWidth(across),
           scrollHTrackLeft(across) + scrollHTrackWidth(across),
           'and a box scrolled to its end puts the thumb at the end of its track')
boxScrollReset()

// ---- the wheel hands a container the scroll it can still take --------
// A wheel over a scroll container scrolls that container, and the page
// only once the container has reached its end in the direction asked
// for. The across-axis answer is the same question over the other axis,
// and it is the one a horizontal wheel needs -- which this browser reads
// as a press of X11's button 6 or 7, because the language has no
// horizontal wheel event (FINDINGS.md, finding 38).
boxScrollReset()
check(scrollContainerAcrossAt(pacross.root, 50, 10, 1) != null,
      'a box with room to its right takes a scroll to the right')
check(scrollContainerAcrossAt(pacross.root, 50, 10, 0 - 1) == null,
      'and at its left end it takes none to the left')
boxScrollLeftBy(across, 1000)
check(scrollContainerAcrossAt(pacross.root, 50, 10, 1) == null,
      'at its right end it takes no more to the right')
check(scrollContainerAcrossAt(pacross.root, 50, 10, 0 - 1) != null,
      'but takes one back to the left')
boxScrollReset()
check(scrollContainerAcrossAt(pacross.root, 50, 250, 1) == null,
      'and a point outside it finds nothing at all')

// A box that scrolls only down is not a box that scrolls across, which
// is what keeps a horizontal wheel from moving a vertical list.
check(scrollContainerAcrossAt(pdrag.root, 50, 10, 1) == null,
      'a box with only a vertical bar takes no scroll across')

// ---- scrollbar-color and scrollbar-width ------------------------------
// The bar is painted in the two colours a stylesheet gave it, thumb
// first and track second (CSS Scrollbars 1 §2), and `none` paints no bar
// at all. Both are asked, because a painter that drew nothing would pass
// a check that only looked for the absence of the default grey.
color sbThumb = '#ff0000'
color sbTrack = '#0000ff'
color sbDefaultTrack = '#fcfcfc'

Page sbc = pageFromHtml(head + '<div style="width:100px;height:60px;overflow:scroll;'
    + 'scrollbar-color:#ff0000 #0000ff">'
    + '<div style="width:300px;height:300px"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(sbc, 0, 0, 300)
check(getPixelColor(92, 5) == sbThumb, 'the thumb takes the first colour')
check(getPixelColor(92, 40) == sbTrack, 'and the track the second')

Page sbd = pageFromHtml(head + '<div style="width:100px;height:60px;overflow:scroll">'
    + '<div style="width:300px;height:300px"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(sbd, 0, 0, 300)
check(getPixelColor(92, 40) == sbDefaultTrack, 'and without the property the track is the browser own')

// `scrollbar-width: none` reserves nothing, so the pixels the bar was in
// belong to the content -- and the box still scrolls, which the unit
// suite checks and a pixel cannot.
Page sbn = pageFromHtml(head + '<div style="width:100px;height:60px;overflow:scroll;'
    + 'scrollbar-width:none;background:#dddddd">'
    + '<div style="width:300px;height:300px;background:green"></div></div></body>', 'test.html', 400)
clearCanvas()
paintPage(sbn, 0, 0, 300)
check(getPixelColor(92, 40) == green, 'scrollbar-width: none leaves the content where the bar was')
check(!(getPixelColor(92, 40) == sbDefaultTrack), 'and paints no track there')

finish('overflow')
