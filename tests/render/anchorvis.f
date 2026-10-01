// `position-visibility` (CSS Anchor Positioning 1 §6).
//
// An anchored box that overflows its containing block is hidden under
// `no-overflow` and drawn under `always`. What makes this a render test
// rather than a layout one is that the box is laid out either way: the
// property changes whether it is painted, not where it goes. Chromium
// does not surface it in computed style at all -- `getComputedStyle`
// answers `visibility: visible` under every keyword -- so a probe that
// asked the computed value reported no difference under any of them,
// which is why this asks the pixels.
//
// Chromium 141 on a 400x300 clipping block, an anchor at its lower edge
// and a 40x30 box placed `bottom` so it straddles that edge: of the 25
// pixels sampled on a row inside the block, `always` paints 20 and
// `no-overflow` paints none. So the keyword hides the whole box rather
// than clipping it harder -- a stricter clip would leave those 20.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(420)
setClientHeight(320)

color white = 'white'
color black = 'black'

void func shotVis(vis:text) {
    text visDecl = vis == '' ? '' : ('position-visibility:' + vis + ';')
    Page p = pageFromHtml('<!doctype html><body style="margin:0">'
        + '<div style="position:relative;width:400px;height:300px;overflow:hidden">'
        + '<div style="position:absolute;left:150px;top:260px;width:100px;height:20px;'
        + 'anchor-name:--a"></div>'
        + '<div style="position:absolute;position-anchor:--a;width:40px;height:30px;'
        + 'background:#000000;position-area:bottom;' + visDecl + '"></div>'
        + '</div></body>', 'tests/fixtures/page.html', 420)
    clearCanvas()
    paintPage(p, 0, 0, 320)
}

// The black pixels on a row that falls inside the block, where the box
// straddles its edge.
int func inkAt(y:int) {
    int n = 0
    for int x = 175, x < 200, x++ { if getPixelColor(x, y) == black { n++ } }
    return n
}

// ---- always paints, no-overflow does not ---------------------------------
shotVis('always')
int alwaysInk = inkAt(290)
check(alwaysInk > 0, 'always paints the part of the box inside the block')

shotVis('no-overflow')
checkEqInt(inkAt(290), 0, 'no-overflow hides a box that overflows')
check(inkAt(290) != alwaysInk, 'which is not what always does')

// The default is `always`, so a box that says nothing is drawn.
shotVis('')
checkEqInt(inkAt(290), alwaysInk, 'a box with no position-visibility is drawn')

// ---- it hides the whole box, not the overflowing part ---------------------
// A stricter clip would leave the pixels that fall inside the block.
// This is the check that tells hiding from clipping, and the reason the
// fixture puts the box across the edge rather than wholly outside it.
shotVis('always')
check(inkAt(290) >= 15, 'the part inside the block is most of the sampled row')
shotVis('no-overflow')
checkEqInt(inkAt(290), 0, 'and none of it survives the hiding')

// ---- a box that does not overflow is drawn under either keyword -----------
// `no-overflow` is a condition, not an unconditional hide: the same
// declaration on a box that fits must change nothing.
void func shotFits(vis:text) {
    text visDecl = vis == '' ? '' : ('position-visibility:' + vis + ';')
    Page p = pageFromHtml('<!doctype html><body style="margin:0">'
        + '<div style="position:relative;width:400px;height:300px;overflow:hidden">'
        + '<div style="position:absolute;left:150px;top:100px;width:100px;height:20px;'
        + 'anchor-name:--a"></div>'
        + '<div style="position:absolute;position-anchor:--a;width:40px;height:30px;'
        + 'background:#000000;position-area:bottom;' + visDecl + '"></div>'
        + '</div></body>', 'tests/fixtures/page.html', 420)
    clearCanvas()
    paintPage(p, 0, 0, 320)
}

shotFits('always')
int fitsInk = inkAt(130)
check(fitsInk > 0, 'a box that fits is drawn')
shotFits('no-overflow')
checkEqInt(inkAt(130), fitsInk, 'and no-overflow leaves it alone')

finish('anchor visibility')
