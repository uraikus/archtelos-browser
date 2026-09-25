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

// ---- a vertical run's decoration lines --------------------------------
// The three lines follow the LINE BOX in a vertical mode rather than
// the baseline, which is what Chromium says and is a different rule
// from the horizontal one (todo.md). What is asked here is that rule
// and not a number: the underline at one block edge, the overline at
// the other, the line-through between them, and the two outer lines a
// line box apart. The decoration is painted in its own colour so that
// the glyphs cannot be mistaken for it.
color WMDECO = '#ff0000'

arr[int] func wmDecoSpan(mode:text, deco:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:16px">` +
        `<div style="writing-mode:${mode};text-decoration:${deco};` +
        `text-decoration-color:#ff0000;color:#000000;padding:20px">HHHH</div></body>`,
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    int lo = 399
    int hi = -1
    for int x = 0, x < 120, x++ {
        for int y = 0, y < 200, y++ {
            if getPixelColor(x, y) != WMDECO { continue }
            if x < lo { lo = x }
            if x > hi { hi = x }
        }
    }
    arr[int] out = []
    out.push(lo)
    out.push(hi)
    return out
}

arr[int] du = wmDecoSpan('vertical-rl', 'underline')
arr[int] dl = wmDecoSpan('vertical-rl', 'line-through')
arr[int] doo = wmDecoSpan('vertical-rl', 'overline')
// The instrument: an engine that draws no vertical decoration at all
// finds no red pixel, and every comparison below would be between two
// sentinels.
check(du[1] >= 0 && dl[1] >= 0 && doo[1] >= 0, 'all three lines are painted in a vertical run')
check(du[0] < dl[0], 'the underline is on the far side of the line-through')
check(dl[0] < doo[0], 'and the overline on the other side of it')
// The two outer lines are a line box apart, and the middle one is
// between them rather than at either edge.
int span = doo[0] - du[0]
check(span >= 16 && span <= 24, 'the outer two are a line box apart')
checkNear(dl[0] - du[0], Math.floorDiv(span, 2), 2, 'and the line-through is between them')

// The two vertical modes agree on all three, as they do in Chromium.
arr[int] lu = wmDecoSpan('vertical-lr', 'underline')
arr[int] lo2 = wmDecoSpan('vertical-lr', 'overline')
checkEqInt(lu[0], du[0], 'vertical-lr underlines on the same side')
checkEqInt(lo2[0], doo[0], 'and overlines on the same side')

// ---- an emphasis mark, and synthesised small caps ---------------------
// The marks run DOWN a vertical line, beside it, rather than across it
// (todo.md has Chromium's table). Painted in their own colour so the
// glyphs cannot be mistaken for them.
color WMMARK = '#00aa00'

arr[int] func wmMarkBox(mode:text, pos:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:16px">` +
        `<div style="writing-mode:${mode};text-emphasis:filled circle;` +
        `text-emphasis-color:#00aa00;text-emphasis-position:${pos};` +
        `color:#000000;padding:30px">HHHH</div></body>`,
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    int x0 = 399
    int x1 = -1
    int y0 = 399
    int y1 = -1
    for int x = 0, x < 160, x++ {
        for int y = 0, y < 200, y++ {
            if getPixelColor(x, y) != WMMARK { continue }
            if x < x0 { x0 = x }
            if x > x1 { x1 = x }
            if y < y0 { y0 = y }
            if y > y1 { y1 = y }
        }
    }
    arr[int] out = []
    out.push(x0)
    out.push(x1)
    out.push(y0)
    out.push(y1)
    return out
}

arr[int] mv = wmMarkBox('vertical-rl', 'over right')
arr[int] mh = wmMarkBox('horizontal-tb', 'over right')
// The instrument: an engine painting no mark at all finds no green
// pixel, and the comparison below would be between two sentinels.
check(mv[1] >= 0 && mh[1] >= 0, 'both runs paint their emphasis marks')
// The horizontal run's marks lie in a row and the vertical run's in a
// column: each is longer along its own inline axis than across it.
check(mh[1] - mh[0] > mh[3] - mh[2], 'a horizontal run marks across the line')
check(mv[3] - mv[2] > mv[1] - mv[0], 'and a vertical run marks down it')
// Four characters, four marks, so the run of marks is about as long as
// the run of text: the two are asked of each other rather than of a
// number.
checkNear(mv[3] - mv[2], mh[1] - mh[0], 3, 'as many marks, over as long a run')

// The two vertical modes agree, as they do in Chromium.
arr[int] ml = wmMarkBox('vertical-lr', 'over right')
checkEqInt(ml[0], mv[0], 'vertical-lr marks on the same side')

// Synthesised small caps in a vertical run. `all-small-caps` shrinks
// every letter, so the run is shorter than the same letters at full
// size -- which is the same thing the horizontal suite asks of it, and
// needs no number either.
int func wmCapsExtent(decl:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;font-size:16px">` +
        `<div id="v" style="writing-mode:vertical-rl;${decl}">HHHH</div></body>`,
        'tests/fixtures/page.html', 400)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    return all[0].h
}
int plainRun = wmCapsExtent('')
int capsRun = wmCapsExtent('font-variant-caps:all-small-caps')
check(plainRun > 0, 'the plain vertical run has an extent at all')
check(capsRun < plainRun, 'all-small-caps shortens a vertical run')

// And the ink has to fit the room that reserved. The measurer already
// answers the shorter length, so a painter that drew the letters at
// full size would run past the box -- which is the failure the
// horizontal pair of functions exists to prevent, asked of the vertical
// pair.
int func wmCapsInk(decl:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:16px">` +
        `<div style="writing-mode:vertical-rl;color:#000000;${decl}">HHHH</div></body>`,
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    int last = -1
    for int y = 0, y < 300, y++ {
        for int x = 0, x < 120, x++ {
            if getPixelColor(x, y) != WMPAPER { last = y }
        }
    }
    return last
}
check(wmCapsInk('font-variant-caps:all-small-caps') <= capsRun,
    'and its ink stays inside the room the measurer kept')

// ---- sideways-lr: the other turn, and the other direction -------------
// Two `L`s, each in its own colour, so which one comes first is visible
// without knowing anything about the font.
color WMFIRST = '#ff0000'
color WMSECOND = '#0000ff'

// Returns: first's y range, second's y range, and the first glyph's ink
// centroid as a fraction of its own width, in tenths.
arr[int] func wmTwoLs(mode:text) {
    Page p = pageFromHtml(
        `<!doctype html><body style="margin:0;background:#ffffff;font-size:32px">` +
        `<div style="writing-mode:${mode};padding:30px;display:inline-block">` +
        `<span style="color:#ff0000">L</span><span style="color:#0000ff">L</span>` +
        `</div></body>`, 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
    int ay0 = 399
    int ay1 = -1
    int by0 = 399
    int by1 = -1
    int ax0 = 399
    int ax1 = -1
    int sumX = 0
    int n = 0
    for int x = 0, x < 200, x++ {
        for int y = 0, y < 200, y++ {
            color c = getPixelColor(x, y)
            if c == WMFIRST {
                if y < ay0 { ay0 = y }
                if y > ay1 { ay1 = y }
                if x < ax0 { ax0 = x }
                if x > ax1 { ax1 = x }
                sumX = sumX + x
                n++
            }
            if c == WMSECOND {
                if y < by0 { by0 = y }
                if y > by1 { by1 = y }
            }
        }
    }
    arr[int] out = []
    out.push(ay0)
    out.push(ay1)
    out.push(by0)
    out.push(by1)
    // The centroid of the first glyph's ink across the block axis, in
    // tenths of its own width. A turn one way and a turn the other put
    // it either side of the middle.
    out.push(n == 0 || ax1 <= ax0 ? -1 : Math.floorDiv(10 * (Math.floorDiv(sumX, n) - ax0), ax1 - ax0))
    return out
}

arr[int] lrl = wmTwoLs('vertical-lr')
arr[int] lsl = wmTwoLs('sideways-lr')
// The instrument: both runs have to paint both glyphs, or the
// comparisons below are between sentinels.
check(lrl[1] >= 0 && lrl[3] >= 0, 'vertical-lr paints both glyphs')
check(lsl[1] >= 0 && lsl[3] >= 0, 'sideways-lr paints both glyphs')

// vertical-lr runs down the page; sideways-lr runs up it.
check(lrl[0] < lrl[2], 'vertical-lr puts the second glyph below the first')
check(lsl[0] > lsl[2], 'and sideways-lr puts it above')

// And the glyph itself is turned the other way, so the weight of its
// ink falls on the other side of its own box. Neither fraction is
// written down: the two are asked to be mirror images.
check(lrl[4] >= 0 && lsl[4] >= 0, 'both glyphs have ink to weigh')
checkNear(lrl[4] + lsl[4], 10, 2, 'the two turns mirror each other')

// sideways-rl is vertical-rl with the sideways orientation, which this
// engine already draws the same way on Latin, so the two agree outright.
arr[int] rrl = wmTwoLs('vertical-rl')
arr[int] rsr = wmTwoLs('sideways-rl')
checkEqInt(rsr[0], rrl[0], 'sideways-rl starts its run where vertical-rl does')
checkEqInt(rsr[2], rrl[2], 'and puts the second glyph in the same place')

finish('writing-mode pixels')
