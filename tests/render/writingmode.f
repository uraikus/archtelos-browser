// CSS Writing Modes 4: a vertical `writing-mode`, in pixels.
//
// The check that earns its place here is not that some pixel is black.
// It is that the SAME text, set horizontally and set vertically, puts
// its ink in the same places once one of them is turned a quarter turn
// -- which is what a vertical writing mode is. Neither profile is
// written down, and neither engine metric has to be known: the two are
// asked of each other, as CLAUDE.md asks of two things that must agree.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(400)

text WMTEXT = 'Ilium'
// Wider than the run and taller than a line, so neither is clipped.
const int WMSPAN = 240
// A band comfortably deeper than one line of 16px text, and the same
// band is used on both axes.
const int WMBAND = 40

// A `color` compares only with another `color`, never with a text
// (FINDINGS.md), so the page's background is a named value here.
color WMPAPER = '#ffffff'

bool func wmInk(c:color) { return c != WMPAPER }

// The horizontal profile: for each position along the inline axis,
// whether the line has any ink there.
arr[bool] func wmProfileH() {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:16px">` +
        `<div style="width:${WMSPAN}px;color:#000000">${WMTEXT}</div></body>`,
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    arr[bool] out = []
    for int i = 0, i < WMSPAN, i++ {
        bool any = false
        for int j = 0, j < WMBAND, j++ {
            if wmInk(getPixelColor(i, j)) { any = true }
        }
        out.push(any)
    }
    return out
}

// The vertical one, along the same inline axis -- which is now down the
// page. `vertical-rl` puts its single line against the right edge of
// its own box, and the box is at the left of the page, so the band to
// sweep is the box's own width.
arr[bool] func wmProfileV(mode:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:16px">` +
        `<div style="writing-mode:${mode};height:${WMSPAN}px;color:#000000">${WMTEXT}</div>` +
        `</body>`, 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    arr[bool] out = []
    for int i = 0, i < WMSPAN, i++ {
        bool any = false
        for int j = 0, j < WMBAND, j++ {
            if wmInk(getPixelColor(j, i)) { any = true }
        }
        out.push(any)
    }
    return out
}

arr[bool] hp = wmProfileH()
arr[bool] vp = wmProfileV('vertical-rl')
arr[bool] vl = wmProfileV('vertical-lr')

// The instrument first. A profile with no ink in it would make every
// comparison below hold on an engine that painted nothing at all.
int inked = 0
for int i = 0, i < hp.length, i++ {
    if hp[i] { inked++ }
}
check(inked > 20, 'the horizontal run puts ink on the page at all')

// What must agree is where the run STARTS and ENDS along the inline
// axis: that is the rotation and the advance, which is what a writing
// mode decides. Pixel-for-pixel equality would be asking the rasteriser
// instead, and it answers differently -- a glyph turned a quarter turn
// is hinted along the other axis, so the gaps between letters open and
// close by a pixel either way while the run keeps its length.
int func wmFirst(pr:arr[bool]) {
    for int i = 0, i < pr.length, i++ {
        if pr[i] { return i }
    }
    return -1
}

int func wmLast(pr:arr[bool]) {
    int last = -1
    for int i = 0, i < pr.length, i++ {
        if pr[i] { last = i }
    }
    return last
}

checkNear(wmFirst(vp), wmFirst(hp), 1, 'vertical-rl starts the run where the horizontal one does')
checkNear(wmLast(vp), wmLast(hp), 1, 'and ends it there')
checkNear(wmFirst(vl), wmFirst(hp), 1, 'and so does vertical-lr')
checkNear(wmLast(vl), wmLast(hp), 1, 'at both ends')

// And the box itself is the horizontal box transposed. A background
// says where its edges are without a single number being written down.
int func wmBoxWidth(decl:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:16px">` +
        `<div style="${decl};color:#000000;background:#0088ff">${WMTEXT}</div></body>`,
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    int w = 0
    while w < 399 && getPixelColor(w, 0) != WMPAPER { w++ }
    return w
}

int func wmBoxHeight(decl:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:16px">` +
        `<div style="${decl};color:#000000;background:#0088ff">${WMTEXT}</div></body>`,
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    int h = 0
    while h < 399 && getPixelColor(0, h) != WMPAPER { h++ }
    return h
}

// Shrink-to-fit in both modes, so the painted rectangle is the run's
// own size in one axis and one line in the other.
int hW = wmBoxWidth('display:inline-block')
int hH = wmBoxHeight('display:inline-block')
// No height on the vertical one: its containing block's block size is
// indefinite, so the orthogonal flow shrinks to fit and the box is the
// run's own size in each axis -- the horizontal box transposed.
int vW = wmBoxWidth('writing-mode:vertical-rl')
int vH = wmBoxHeight('writing-mode:vertical-rl')
check(hW > hH, 'the horizontal box is wider than it is tall')
checkEqInt(vW, hH, 'the vertical one is as wide as the horizontal one is tall')
checkEqInt(vH, hW, 'and as tall as it is wide')

// ---- text-orientation: upright ---------------------------------------
// A turned glyph and an upright one are the same glyph, so their ink
// must be the same rectangle with its sides exchanged. Neither
// rectangle is written down: the two are asked of each other, which is
// the only form of this check that does not depend on knowing what an
// `L` measures in this font.
arr[int] func wmInkBox(orient:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:32px">` +
        `<div style="writing-mode:vertical-rl;text-orientation:${orient};` +
        `color:#000000">L</div></body>`, 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    int minX = 399
    int maxX = -1
    int minY = 399
    int maxY = -1
    for int x = 0, x < 120, x++ {
        for int y = 0, y < 120, y++ {
            if getPixelColor(x, y) == WMPAPER { continue }
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    arr[int] out = []
    out.push(maxX - minX + 1)
    out.push(maxY - minY + 1)
    return out
}

arr[int] upBox = wmInkBox('upright')
arr[int] sideBox = wmInkBox('sideways')
check(upBox[0] > 0 && sideBox[0] > 0, 'both orientations put an L on the page')
// An `L` is taller than it is wide, so the two rectangles are not
// square and the exchange below can fail.
check(upBox[1] > upBox[0], 'an upright L is taller than it is wide')
// Two pixels of slack on a 32px glyph, for the reason the ink profile
// above needed slack: an upright glyph is hinted, its stems snapped to
// the pixel grid, and a turned one is hinted along the other axis or
// not at all. The turned `L` here comes out two longer along its
// advance and two shorter across it.
checkNear(sideBox[0], upBox[1], 2, 'a turned L is as wide as the upright one is tall')
checkNear(sideBox[1], upBox[0], 2, 'and as tall as it is wide')

finish('writing-mode pixels')
