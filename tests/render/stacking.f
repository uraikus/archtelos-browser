// CSS2 §9.9's painting order, asked in pixels.
//
// Within a stacking context the order is: the context element's own
// background and border, then its negative-`z-index` descendants, then
// the in-flow block descendants, the floats, the inline content, and
// finally the positioned descendants at zero and above. The part that
// is not obvious is what happens to a negative child of a box that is
// *not* a stacking context: it belongs to the nearest ancestor that is,
// so it paints **behind that box's own background**.
//
// Measured in Chromium (todo.md), with everything stacked at one spot
// and `elementFromPoint` naming the winner:
//
//   parent not a context   over the parent's background alone -> the parent
//   parent a context       over the same spot                 -> the child
//   either                 over an in-flow block sibling      -> the block
//
// and the three things that make a context -- a declared `z-index` on a
// positioned box, a `transform`, an `opacity` below 1 -- all answer the
// same way.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(400)

color green = '#00ff00'
color magenta = '#ff00ff'
color blue = '#0088ff'
color white = 'white'

// A 200x200 green parent, a magenta `z-index: -1` child covering all of
// it, and a 200x60 blue in-flow block across its top. Three questions in
// one picture: (30,150) is the parent's background against the negative
// child, and (30,30) is the in-flow block against both.
text stackBody = '<div id="p"><div id="neg"></div><div id="flow"></div></div>'

void func shotStack(extra:text) {
    Page p = pageFromHtml('<!doctype html><head><style>'
        + 'body{margin:0}'
        + '#p{position:relative;width:200px;height:200px;background:#00ff00;' + extra + '}'
        + '#flow{width:200px;height:60px;background:#0088ff}'
        + '#neg{position:absolute;z-index:-1;left:0;top:0;width:200px;height:200px;'
        + 'background:#ff00ff}'
        + '</style><body>' + stackBody + '</body>', 'test.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
}

// ---- a parent that is not a stacking context ---------------------------
// `position: relative` with no `z-index` is not one, so the negative
// child is hoisted past it and paints behind its background.
shotStack('')
check(getPixelColor(30, 150) == green, 'a negative child is behind a non-context parent')
check(getPixelColor(30, 30) == blue, 'and behind the in-flow block as well')

// ---- a declared z-index makes one --------------------------------------
shotStack('z-index:0')
check(getPixelColor(30, 150) == magenta, 'a declared z-index makes a stacking context')
check(getPixelColor(30, 30) == blue, 'the in-flow block still paints over the negative child')

// ---- and so does a transform -------------------------------------------
shotStack('transform:translateX(0px)')
check(getPixelColor(30, 150) == magenta, 'a transform makes a stacking context')
check(getPixelColor(30, 30) == blue, 'with the same order inside it')

// The two spellings of a context must agree, which needs no number.
shotStack('z-index:0')
color zeroAt150 = getPixelColor(30, 150)
color zeroAt30 = getPixelColor(30, 30)
shotStack('transform:rotate(0deg)')
check(getPixelColor(30, 150) == zeroAt150, 'an identity transform is a context like a z-index')
check(getPixelColor(30, 30) == zeroAt30, 'on both points')

// `z-index: auto` is not a declared z-index, so it must agree with
// declaring nothing at all rather than with declaring zero.
shotStack('')
color plainAt150 = getPixelColor(30, 150)
shotStack('z-index:auto')
check(getPixelColor(30, 150) == plainAt150, 'z-index: auto is not a stacking context')

// ---- a page with no negative z-index is untouched ----------------------
// The whole pass is behind a per-document flag, so a document that never
// says a negative z-index must paint exactly as it did. Two stacks of
// positioned boxes, one drawn with the flag down and one that would
// raise it elsewhere on the page, must agree where they overlap.
Page pz = pageFromHtml('<!doctype html><head><style>body{margin:0}'
    + '#a{position:absolute;left:0;top:0;width:100px;height:100px;background:#00ff00;z-index:0}'
    + '#b{position:absolute;left:0;top:0;width:100px;height:100px;background:#ff00ff}'
    + '</style><body><div id="a"></div><div id="b"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(pz, 0, 0, 400)
check(getPixelColor(30, 30) == magenta,
      'a later z-index: auto box paints over an earlier z-index: 0 one')

finish('stacking')
