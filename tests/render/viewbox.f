// `object-view-box` (CSS Images 4): a rectangle over a replaced
// element's own pixels, which becomes the image's natural size. What
// `object-fit` then fits into the box is that rectangle rather than the
// whole image.
//
// Read off Chromium 141, on a 20x10 source:
//
//   no view box                          natural 20 x 10
//   inset(0 10px 0 0)                    natural 10 x 10
//   inset(2px 4px 2px 4px)               natural 12 x  6
//   rect(0 10px 10px 0)                  natural 10 x 10
//   xywh(0 0 10px 10px)                  natural 10 x 10
//   inset(-5px)                          natural 30 x 20
//   none                                 natural 20 x 10
//
// and `rect()` and `xywh()` naming one rectangle compute to the same
// `inset()` as each other, which is the check below that does not
// depend on any number: three spellings of one region must give one
// picture.
//
// The fixture is the 10x10 tile whose left half is blue (#0000ff) and
// right half green (#008000), so a view box over one half is a single
// colour and says both which half was taken and that it was scaled to
// fill the box.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color vbBlue = 'blue'
color vbGreen = 'green'
color vbWhite = 'white'

text vbHead = '<!doctype html><body style="margin:0;font:16px/20px monospace">'
text vbBase = 'tests/fixtures/page.html'

Box func vbImage(root:Box) {
    arr[Box] all = []
    collectBoxesForTag(root, 'img', all)
    return all.length > 0 ? all[0] : null
}

// The natural size a view box leaves, read as the box an image with no
// declared width or height comes to.
arr[int] func vbNatural(style:text) {
    Page p = pageFromHtml(vbHead + `<img src="tile.png" style="${style}">` + '</body>',
                          vbBase, 400)
    Box im = vbImage(p.root)
    arr[int] out = []
    if im == null { return out }
    out.push(im.w)
    out.push(im.h)
    return out
}

void func vbCheckSize(got:arr[int], w:int, h:int, label:text) {
    if got.length < 2 {
        check(false, label)
        return
    }
    checkEqInt(got[0], w, `${label}: width`)
    checkEqInt(got[1], h, `${label}: height`)
}

// ---- the view box is the natural size --------------------------------
vbCheckSize(vbNatural(''), 10, 10, 'an image with no view box is its own size')
vbCheckSize(vbNatural('object-view-box:none'), 10, 10, '`none` is the same as none at all')
vbCheckSize(vbNatural('object-view-box:inset(0 5px 0 0)'), 5, 10,
            'an inset from the right leaves the left half')
vbCheckSize(vbNatural('object-view-box:inset(0 0 0 5px)'), 5, 10,
            'and an inset from the left leaves the right half')
vbCheckSize(vbNatural('object-view-box:inset(2px)'), 6, 6, 'one value insets all four edges')
vbCheckSize(vbNatural('object-view-box:inset(-5px 0 0 0)'), 10, 15,
            'a negative inset reaches outside the image')

// Three spellings of the left half.
arr[int] vbIns = vbNatural('object-view-box:inset(0 5px 0 0)')
arr[int] vbRect = vbNatural('object-view-box:rect(0 5px 10px 0)')
arr[int] vbXywh = vbNatural('object-view-box:xywh(0 0 5px 10px)')
arr[int] vbPct = vbNatural('object-view-box:inset(0 50% 0 0)')
check(vbRect.length == 2 && vbIns.length == 2
      && vbRect[0] == vbIns[0] && vbRect[1] == vbIns[1],
      '`rect()` names the rectangle `inset()` does')
check(vbXywh.length == 2 && vbXywh[0] == vbIns[0] && vbXywh[1] == vbIns[1],
      'and so does `xywh()`')
check(vbPct.length == 2 && vbPct[0] == vbIns[0] && vbPct[1] == vbIns[1],
      'and a percentage of the image is the same as the length it works out to')

// ---- and what is painted is that rectangle ---------------------------
// The image is stretched over a 40x40 box, so a view box over one half
// of the tile fills the whole box with that half's colour.
void func vbPaint(style:text) {
    Page p = pageFromHtml(vbHead
        + `<img src="tile.png" style="width:40px;height:40px;${style}">` + '</body>',
        vbBase, 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// The pixels are read well inside the box rather than at its edges.
// Scaling is smoothed, so an eight-fold upscale -- which a five-pixel
// view box stretched over forty is -- carries the blend several pixels
// in from each edge, where the four-fold upscale of the whole tile
// keeps it to one. x = 10 and x = 30 are past that band on both.
const int VB_LEFT = 10
const int VB_RIGHT = 30

vbPaint('object-view-box:inset(0 5px 0 0)')
check(getPixelColor(VB_LEFT, 20) == vbBlue, 'the left half fills the box')
check(getPixelColor(VB_RIGHT, 20) == vbBlue, 'all the way across it')

vbPaint('object-view-box:inset(0 0 0 5px)')
check(getPixelColor(VB_LEFT, 20) == vbGreen, 'and the right half fills it with the other colour')
check(getPixelColor(VB_RIGHT, 20) == vbGreen, 'across the whole box as well')

// Without a view box both halves are there, which is what tells the two
// checks above from a pair that would pass on an unstretched image.
vbPaint('')
check(getPixelColor(VB_LEFT, 20) == vbBlue, 'with no view box the blue half is on the left')
check(getPixelColor(VB_RIGHT, 20) == vbGreen, 'and the green half on the right')

// `rect()` must paint what `inset()` painted, not merely measure the same.
vbPaint('object-view-box:rect(0 5px 10px 0)')
check(getPixelColor(VB_LEFT, 20) == vbBlue && getPixelColor(VB_RIGHT, 20) == vbBlue,
      '`rect()` paints the rectangle `inset()` painted')
vbPaint('object-view-box:xywh(0 0 5px 10px)')
check(getPixelColor(VB_LEFT, 20) == vbBlue && getPixelColor(VB_RIGHT, 20) == vbBlue,
      'and so does `xywh()`')

// A view box reaching above the image leaves those rows empty rather
// than repeating an edge: the top third of the box is not the tile.
vbPaint('object-view-box:inset(-5px 0 0 0)')
check(getPixelColor(20, 2) == vbWhite, 'a view box outside the image is transparent there')
check(getPixelColor(VB_LEFT, 30) == vbBlue, 'and the image itself is below it')

finish('object-view-box')
