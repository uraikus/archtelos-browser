// `isolation` (CSS Compositing 1 §6), and CSS2 §9.9's rule about which
// box owns a positioned descendant's `z-index`.
//
// A positioned box with `z-index: auto` is NOT a stacking context, so
// its positioned descendants compete in the nearest ancestor that is
// one. This engine used to confine them to any positioned box at all,
// which made `isolation` -- whose whole effect here is that it creates
// a stacking context -- impossible to measure.
//
// The fixture: a `z-index: 5` child inside a wrapper, against a
// `z-index: 2` sibling of the wrapper. Without a stacking context the
// child escapes and paints on top (red); with one it is confined and
// the sibling paints above it (blue). No number is written down --
// which of two colours is on top IS the question.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(200)
setClientHeight(200)

color isoRed = '#ff0000'
color isoBlue = '#0000ff'

// `decl` goes on the middle box, the one asked to become a context.
text func isoDoc(decl:text) {
    return '<!doctype html><body style="margin:0;background:#ffffff">'
        + '<div style="position:relative;width:100px;height:40px">'
        +   `<div style="position:relative;width:100px;height:40px;background:#00ff00;${decl}">`
        +     '<div style="position:absolute;left:0;top:0;width:100px;height:40px;'
        +     'background:#ff0000;z-index:5"></div>'
        +   '</div>'
        +   '<div style="position:absolute;left:0;top:0;width:100px;height:40px;'
        +   'background:#0000ff;z-index:2"></div>'
        + '</div></body>'
}

color func isoAt(decl:text) {
    Page p = pageFromHtml(isoDoc(decl), 'tests/fixtures/page.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 200)
    return getPixelColor(50, 20)
}

// The instrument, and the bug this suite was written for. Without it
// every check below could hold on an engine that painted blue whatever
// the middle box said -- which is exactly what this one did.
check(isoAt('') == isoRed, 'a z-index: auto wrapper does not own its descendant z-index')

check(isoAt('isolation:isolate') == isoBlue, 'isolation: isolate owns it')
check(isoAt('isolation:auto') == isoRed, 'and isolation: auto does not')

// Everything else the standard gives a stacking context to. The first
// two were implemented this session and given `boxPaintsWhole`, which
// gets the subtree into one layer -- a different question from this
// one, and one that hid the difference until the hoist landed.
check(isoAt('filter:grayscale(0)') == isoBlue, 'a filter owns it too')
check(isoAt('mask-image:linear-gradient(black,black)') == isoBlue, 'and a mask')
check(isoAt('opacity:0.99') == isoBlue, 'as opacity below one always did')
check(isoAt('transform:translateX(0px)') == isoBlue, 'and a transform')
check(isoAt('z-index:0') == isoBlue, 'and an explicit z-index on the wrapper itself')

// A box that CONFINES its subtree keeps its descendants whatever the
// stacking rules say, because hoisting them out would take them out of
// the clip they are painted into. `overflow: hidden` is not a stacking
// context by the standard, so this is a divergence, and it is asserted
// here rather than left to be discovered (todo.md).
check(isoAt('overflow:hidden') == isoBlue, 'a clipping box confines its descendants here')

finish('isolation')
