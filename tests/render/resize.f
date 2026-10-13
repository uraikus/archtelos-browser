// `resize` (CSS Basic User Interface 3 §5.1, whose `block` and
// `inline` keywords come from Level 4): the user may resize a box.
//
// The property reserves no space and changes no geometry -- todo.md
// records fourteen declarations measured in Chromium, and the only row
// whose client box moves is `overflow: scroll`, which moves the same
// way with no `resize` on it at all. Its computed value is the declared
// keyword under every `overflow`, `visible` included. So neither
// geometry nor `getComputedStyle` can tell whether this property is
// doing anything, and the painter is the only instrument that can:
// what there is to see is the grabber in the corner.
//
// Chromium draws it as two diagonal hairlines in #666666, at
// `x + y` = corner - 8 and corner - 4, inside a seven by seven square
// inset one pixel from the bottom-right corner of the PADDING box. The
// pixel rows in todo.md are what these expectations were read from.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color white = 'white'
color grab = '#666666'

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace">'

// A 100 by 60 box at the origin, so its padding box's last pixel is
// (99, 59) and every expectation below can be read off todo.md's rows
// by subtracting twenty from each of Chromium's.
Page func boxPage(css:text) {
    return pageFromHtml(head + '<div id="d" style="width:100px;height:60px;'
        + 'background:white;' + css + '"></div></body>', 'test.html', 400)
}

// The ten by ten square at a corner, with the grabber's own colour
// marked and everything else blank. A signature rather than a count,
// so that two ways of reaching the same grabber can be compared
// without either one's pixels being written down twice.
text func cornerSig(cx:int, cy:int) {
    arr[text] parts = []
    for int dy = -9, dy <= 0, dy++ {
        for int dx = -9, dx <= 0, dx++ {
            parts.push(getPixelColor(cx + dx, cy + dy) == grab ? '#' : '.')
        }
    }
    return parts.join('')
}

int func inkCount(sig:text) {
    int n = 0
    ascii a = sig.toAscii()
    for int i = 0, i < a.length, i++ { if a[i] == '#' { n++ } }
    return n
}

text func paintSig(css:text, cx:int, cy:int) {
    Page p = boxPage(css)
    clearCanvas()
    paintPage(p, 0, 0, 300)
    return cornerSig(cx, cy)
}

// ---- the grabber, pixel by pixel --------------------------------------
Page p1 = boxPage('resize:both;overflow:hidden')
clearCanvas()
paintPage(p1, 0, 0, 300)

// The long diagonal: seven pixels, from (98, 52) down to (92, 58).
check(getPixelColor(98, 52) == grab, 'the long diagonal starts one pixel in from the corner')
check(getPixelColor(95, 55) == grab, 'and runs through the middle of the square')
check(getPixelColor(92, 58) == grab, 'and ends one pixel above the bottom edge')
// The short one: three pixels, from (98, 56) down to (96, 58).
check(getPixelColor(98, 56) == grab, 'the short diagonal starts four pixels lower')
check(getPixelColor(96, 58) == grab, 'and is cut to three pixels by the same inset')
// And what is between and around them.
check(getPixelColor(97, 55) == white, 'the gap between the two diagonals is not painted')
check(getPixelColor(99, 59) == white, 'nor is the corner pixel itself')
check(getPixelColor(91, 51) == white, 'nor anything outside the seven by seven square')

text sigBoth = cornerSig(99, 59)
checkEqInt(inkCount(sigBoth), 10, 'ten pixels in all, seven and three')

// ---- when it paints, and when it does not -----------------------------
checkEqInt(inkCount(paintSig('resize:none;overflow:hidden', 99, 59)), 0,
           'resize: none paints no grabber')
// `overflow: visible` is the one place the computed value and the
// painting disagree: Chromium still reports `resize: both` and draws
// nothing, which is the specification's own "applies to: elements with
// overflow other than visible".
checkEqInt(inkCount(paintSig('resize:both', 99, 59)), 0,
           'a box whose overflow is visible gets no grabber')
// `clip` is the other one Chromium refuses, measured rather than read
// off the specification, which names only `visible`.
checkEqInt(inkCount(paintSig('resize:both;overflow:clip', 99, 59)), 0,
           'nor does overflow: clip')
checkEq(paintSig('resize:both;overflow:auto', 99, 59), sigBoth,
        'overflow: auto paints the same grabber as hidden')

// ---- the value constrains the drag, not the drawing -------------------
// Four values, one grabber. This is the check that needs no number:
// each is asserted to agree with `both` rather than to match pixels of
// its own, so all five could only pass together.
checkEq(paintSig('resize:horizontal;overflow:hidden', 99, 59), sigBoth,
            'horizontal paints the same grabber as both')
checkEq(paintSig('resize:vertical;overflow:hidden', 99, 59), sigBoth,
            'and so does vertical')
checkEq(paintSig('resize:block;overflow:hidden', 99, 59), sigBoth,
            'and the block keyword')
checkEq(paintSig('resize:inline;overflow:hidden', 99, 59), sigBoth,
            'and the inline one')

// ---- the padding box is what it sits in -------------------------------
// With a five pixel border the box is 110 by 70 and its padding box's
// last pixel is (104, 64). Chromium puts the grabber at the same two
// offsets from THAT corner, which is how the measurement distinguishes
// the padding box from the border box; here the two signatures have to
// come out identical.
checkEq(paintSig('resize:both;overflow:hidden;border:5px solid #999999', 104, 64),
            sigBoth, 'a border moves the grabber inward with the padding box')

// ---- the grabber can be taken hold of ---------------------------------
// The pointer is tested against the same square the painter has just
// drawn into, which is the agreement that makes this safe to check
// without writing the square's pixels down a second time.
Page pd = boxPage('resize:both;overflow:hidden')
resizeUsedReset()
arr[Box] dboxes = []
collectBoxesForTag(pd.root, 'div', dboxes)
Box d = dboxes[0]
check(d != null, 'the box is in the tree')
checkEqInt(resizeGrabberX(d), 99, 'the grabber is measured from the padding box')
checkEqInt(resizeGrabberY(d), 59, 'on both axes')
check(resizeGrabberAt(pd.root, 95, 55) != null, 'the pointer finds the grabber inside the square')
check(resizeGrabberAt(pd.root, 99, 59) != null, 'and at the corner pixel itself')
check(resizeGrabberAt(pd.root, 92, 52) == null,
      'and nothing one pixel outside the seven by seven square')
check(resizeGrabberAt(pd.root, 50, 30) == null, 'nor in the middle of the box')

// A drag takes the corner to the pointer. Nothing moves until the
// document is styled and laid out again, because the dragged size
// reaches layout as a declaration rather than as a box field -- which
// is what makes it behave exactly as a declared length does.
check(resizeDragTo(d, 149, 89), 'dragging the corner records a new size')
computeStyles(pd.doc)
layoutPage(pd, 400)
arr[Box] after = []
collectBoxesForTag(pd.root, 'div', after)
checkEqInt(after[0].w, 150, 'the box is as wide as the pointer took it')
checkEqInt(after[0].h, 90, 'and as tall')

// And the grabber follows: it is where the painter now draws it.
clearCanvas()
paintPage(pd, 0, 0, 300)
checkEq(cornerSig(149, 89), sigBoth, 'the grabber is redrawn in the new corner')
check(resizeGrabberAt(pd.root, 145, 85) != null, 'and is found there')

// The dragged size is the BORDER box, whatever the element's own
// `box-sizing` says. A 150 by 90 drag of a box with ten pixels of
// padding and five of border on every side is 150 by 90 either way,
// which a content-box reading would make 180 by 120.
Page pb = boxPage('resize:both;overflow:hidden;padding:10px;border:5px solid #999999')
resizeUsedReset()
arr[Box] bboxes = []
collectBoxesForTag(pb.root, 'div', bboxes)
check(resizeDragTo(bboxes[0], 149, 89), 'the bordered box takes a drag')
computeStyles(pb.doc)
layoutPage(pb, 400)
arr[Box] bafter = []
collectBoxesForTag(pb.root, 'div', bafter)
checkEqInt(bafter[0].w, 150, 'the drag sizes the border box across')
checkEqInt(bafter[0].h, 90, 'and down')

// ---- the keyword constrains the drag ----------------------------------
// This is where the four values stop agreeing: they all draw the same
// grabber and each moves only the axes it names.
int func draggedW(css:text) {
    Page p = boxPage(css)
    resizeUsedReset()
    arr[Box] bs = []
    collectBoxesForTag(p.root, 'div', bs)
    resizeDragTo(bs[0], 149, 89)
    computeStyles(p.doc)
    layoutPage(p, 400)
    arr[Box] bs2 = []
    collectBoxesForTag(p.root, 'div', bs2)
    return bs2[0].w
}

int func draggedH(css:text) {
    Page p = boxPage(css)
    resizeUsedReset()
    arr[Box] bs = []
    collectBoxesForTag(p.root, 'div', bs)
    resizeDragTo(bs[0], 149, 89)
    computeStyles(p.doc)
    layoutPage(p, 400)
    arr[Box] bs2 = []
    collectBoxesForTag(p.root, 'div', bs2)
    return bs2[0].h
}

checkEqInt(draggedW('resize:horizontal;overflow:hidden'), 150, 'horizontal takes the width')
checkEqInt(draggedH('resize:horizontal;overflow:hidden'), 60, 'and leaves the height alone')
checkEqInt(draggedW('resize:vertical;overflow:hidden'), 100, 'vertical leaves the width alone')
checkEqInt(draggedH('resize:vertical;overflow:hidden'), 90, 'and takes the height')
// The two logical keywords are the same two axes in this engine's one
// writing mode, which is what `inline` and `block` mean here.
checkEqInt(draggedW('resize:inline;overflow:hidden'), 150, 'inline is the horizontal axis')
checkEqInt(draggedH('resize:inline;overflow:hidden'), 60, 'and only that one')
checkEqInt(draggedH('resize:block;overflow:hidden'), 90, 'block is the vertical axis')
checkEqInt(draggedW('resize:block;overflow:hidden'), 100, 'and only that one')

// ---- the floor, and a grabber inside a scrolled container -------------
// A box cannot be dragged smaller than its own grabber, or it could
// never be taken hold of again.
Page pm = boxPage('resize:both;overflow:hidden')
resizeUsedReset()
arr[Box] mboxes = []
collectBoxesForTag(pm.root, 'div', mboxes)
check(resizeSetSize(mboxes[0], 1, 1), 'a drag past the minimum still records a size')
computeStyles(pm.doc)
layoutPage(pm, 400)
arr[Box] mafter = []
collectBoxesForTag(pm.root, 'div', mafter)
checkEqInt(mafter[0].w, 7, 'and the box stops at the width of the grabber')
checkEqInt(mafter[0].h, 7, 'and at its height')
check(resizeGrabberAt(pm.root, 6, 6) != null, 'which leaves it something to take hold of')

// The pointer is tested through a scrolled container the way the
// scroll thumb is: the point moves into the container's own
// coordinates before its children are asked, so the grabber is found
// where it is drawn rather than where it was laid out.
resizeUsedReset()
Page ps = pageFromHtml(head
    + '<div id="s" style="width:300px;height:100px;overflow:auto">'
    + '<div style="height:20px"></div>'
    + '<div id="r" style="width:100px;height:60px;resize:both;overflow:hidden"></div>'
    + '<div style="height:300px"></div></div></body>', 'test.html', 400)
arr[Box] sboxes = []
collectBoxesForTag(ps.root, 'div', sboxes)
Box outer = sboxes[0]
Box inner = sboxes[2]
boxScrollReset()
checkEqInt(resizeGrabberY(inner), 79, 'the grabber is laid out where the flow put it')
check(resizeGrabberAt(ps.root, 95, 75) != null, 'and is found there unscrolled')
boxScrollBy(outer, 50)
checkEqInt(boxScrollTop(outer), 50, 'the container scrolls')
check(resizeGrabberAt(ps.root, 95, 25) != null,
      'and the grabber is found fifty pixels higher')
check(resizeGrabberAt(ps.root, 95, 75) == null, 'and no longer where it was laid out')
boxScrollReset()
resizeUsedReset()

// A box that says nothing cannot be dragged at all, which is the row
// that says the drag is the property's and not the corner's.
Page pn = boxPage('overflow:hidden')
resizeUsedReset()
arr[Box] nboxes = []
collectBoxesForTag(pn.root, 'div', nboxes)
check(!resizeDragTo(nboxes[0], 149, 89), 'a box with no resize refuses the drag')
resizeUsedReset()

finish('resize')
