// Painting a page must not depend on what else has been laid out.
//
// The painter asks a set of per-document questions -- has this document
// a float, a positioned box, a box that paints whole, an outline, a
// transform, a clip, a corner shape, small caps -- and each is a global
// raised while a box tree is **built** and read while one is
// **painted**. The browser holds one document at a time, so the two
// always agree there. A test file does not: it can build page A, build
// page B, and then paint A, and A would be painted with B's answers.
//
// That is not a hypothetical. A check in tests/render/overflow.f was
// written as "the clipped shape agrees with the unclipped one", painted
// the clipped page, built the unclipped one, painted it, and painted
// the clipped page again -- and the second painting took the unclipped
// page's flags, never gave the clipping box a layer, and compared the
// unclipped rendering with itself. It passed for an hour.
//
// This suite is the invariant that catches it, and catches the next one
// too: **painting a page twice, with another page built and painted in
// between, must give the same pixels.** A list of flags can be
// incomplete; an invariant cannot. The fixture below is rich on purpose
// -- every flag it can reach is a flag this protects.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(300)
setClientHeight(300)

// Everything that raises one of those flags, on one page.
text busyCss = '<!doctype html><head><style>'
    + 'body{margin:0;width:300px;background:#ffffff}'
    + '#f{float:left;width:60px;height:60px;background:#0088ff}'
    + '#blk{height:60px;background:#dd2222;outline:4px solid #118811}'
    + '#pos{position:absolute;left:20px;top:100px;width:80px;height:40px;'
    + 'background:#8844cc;z-index:2}'
    + '#neg{position:absolute;left:40px;top:110px;width:80px;height:40px;'
    + 'background:#ccaa00;z-index:-1}'
    + '#tf{width:60px;height:30px;background:#22aa88;transform:rotate(8deg)}'
    + '#clip{overflow:hidden;width:120px;height:70px;margin-top:6px}'
    + '#round{width:100px;height:60px;border-radius:24px;background:#334488;'
    + 'box-shadow:inset 0 0 8px 0 #ffffff}'
    + '#shape{width:60px;height:40px;background:#aa3377;border-radius:20px;'
    + 'corner-shape:bevel}'
    + '.caps{font-variant-caps:small-caps}'
    + '</style><body>'
    + '<div id="f"></div><div id="blk"></div>'
    + '<div id="pos"></div><div id="neg"></div>'
    + '<div id="tf"></div>'
    + '<div id="clip"><div id="round"></div></div>'
    + '<div id="shape"></div>'
    + '<p class="caps">small capitals here</p>'
    + '</body>'

// A page with none of it, built between the two paintings of the one
// above. Every flag it leaves down is a flag the first page needs up.
text plainCss = '<!doctype html><head><style>'
    + 'body{margin:0;width:300px;background:#ffffff}'
    + 'p{margin:0}'
    + '</style><body><p>nothing here raises anything</p></body>'

const int SAMPLE_STEP = 7

arr[color] func sampleCanvas() {
    arr[color] out = []
    for int y = 0, y < 280, y = y + SAMPLE_STEP {
        for int x = 0, x < 280, x = x + SAMPLE_STEP {
            out.push(getPixelColor(x, y))
        }
    }
    return out
}

Page busy = pageFromHtml(busyCss, 'test.html', 300)
clearCanvas()
paintPage(busy, 0, 0, 300)
arr[color] first = sampleCanvas()

// The page has to be worth protecting: a blank one would pass this
// suite while measuring nothing at all.
int inked = 0
color pageWhite = '#ffffff'
for int i = 0, i < first.length, i++ {
    if !(first[i] == pageWhite) { inked++ }
}
check(inked > 120, 'the fixture actually paints something to compare')

Page plain = pageFromHtml(plainCss, 'test.html', 300)
clearCanvas()
paintPage(plain, 0, 0, 300)

clearCanvas()
paintPage(busy, 0, 0, 300)
arr[color] second = sampleCanvas()

int moved = 0
for int i = 0, i < first.length, i++ {
    if !(first[i] == second[i]) { moved++ }
}
checkEqInt(moved, 0, 'painting a page again gives the same pixels')
checkEqInt(second.length, first.length, 'and the same number of them')

// And the other way round, because a flag can leak in either
// direction: the plain page must paint the same whether or not the
// busy one was built after it.
clearCanvas()
paintPage(plain, 0, 0, 300)
arr[color] plainFirst = sampleCanvas()
Page busyAgain = pageFromHtml(busyCss, 'test.html', 300)
clearCanvas()
paintPage(busyAgain, 0, 0, 300)
clearCanvas()
paintPage(plain, 0, 0, 300)
arr[color] plainSecond = sampleCanvas()
int plainMoved = 0
for int i = 0, i < plainFirst.length, i++ {
    if !(plainFirst[i] == plainSecond[i]) { plainMoved++ }
}
checkEqInt(plainMoved, 0, 'and a plain page is not disturbed by a busy one either')

// ---- a scroll offset belongs to its own document ------------------------
// The same class of leak one step over. `boxScrollTops` is keyed by NODE
// ID, because a box tree lasts one layout and a scroll offset has to
// outlive several -- and node ids start again at 1 for every document.
// So without a reset, whichever element of the next page happens to take
// a scrolled element's id starts scrolled to where that element was.
//
// `resizeUsedReset` is called from `cascadeReset` for exactly this
// reason, and says so in a comment. This is the same line for the same
// reason, and the check is the invariant rather than a number: a fresh
// document's scroll container starts at the top, whatever was scrolled
// before it.

Box func scrollBoxIn(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'div', all)
    for int i = 0, i < all.length, i++ {
        if getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

text scrollerHtml = '<!doctype html><body style="margin:0">'
    + '<div id="s" style="width:120px;height:60px;overflow-y:scroll;overflow-x:hidden">'
    + '<div style="height:400px"></div></div></body>'

// Page one, scrolled well down.
Page scrollA = pageFromHtml(scrollerHtml, 'tests/fixtures/page.html', 300)
Box scrollerA = scrollBoxIn(scrollA.root, 's')
check(scrollerA != null, 'the fixture has a scroll container')
boxScrollBy(scrollerA, 200)
check(boxScrollTop(scrollerA) > 0, 'and it scrolls')

// Page two: a different document that happens to have a scroll
// container of its own. It must start at the top.
Page scrollB = pageFromHtml(scrollerHtml, 'tests/fixtures/page.html', 300)
checkEqInt(boxScrollTop(scrollBoxIn(scrollB.root, 's')), 0,
    'a fresh document starts its scroll container at the top')

// And the same for the horizontal offset, which is a second map with
// the same key and the same hazard.
Page scrollC = pageFromHtml('<!doctype html><body style="margin:0">'
    + '<div id="s" style="width:120px;height:60px;overflow-x:scroll;overflow-y:hidden">'
    + '<div style="width:400px;height:20px"></div></div></body>',
    'tests/fixtures/page.html', 300)
Box scrollerC = scrollBoxIn(scrollC.root, 's')
boxScrollLeftBy(scrollerC, 150)
check(boxScrollLeft(scrollerC) > 0, 'a container scrolls across too')
Page scrollD = pageFromHtml('<!doctype html><body style="margin:0">'
    + '<div id="s" style="width:120px;height:60px;overflow-x:scroll;overflow-y:hidden">'
    + '<div style="width:400px;height:20px"></div></div></body>',
    'tests/fixtures/page.html', 300)
checkEqInt(boxScrollLeft(scrollBoxIn(scrollD.root, 's')), 0,
    'and a fresh document starts it at the left')

finish('page state')
