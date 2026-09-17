// Flexible Box Layout 1, which is in the official definition of CSS and
// of which this engine had none: `flex` was accepted as a `display`
// value and laid out as a block, which is why a modern page rendered as
// a single column. See css-2026.md.
//
// Every expected number was read out of Chromium 141 with
// getBoundingClientRect on the same markup.

import ../../src/browser/page.f
import ../assert.f

Box func byId(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'div', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:400px">'

// ---- a row of two items, stretched to the container ------------------
Page p1 = pageFromHtml(head + '<div id="c1" style="display:flex;height:60px"><div id="a1" style="width:80px"></div><div id="a2" style="width:100px"></div></div></body>', 'about:blank', 400)
Box a1 = byId(p1.root, 'a1')
Box a2 = byId(p1.root, 'a2')
checkEqInt(a1.x, 0, 'the first item starts at the content edge')
checkEqInt(a2.x, 80, 'the second follows it on the main axis')
checkEqInt(a1.w, 80, 'each keeps its declared width')
checkEqInt(a2.w, 100, 'both of them')
checkEqInt(a1.h, 60, 'align-items: stretch fills the cross axis')
checkEqInt(a2.h, 60, 'for every item')

// ---- justify-content -------------------------------------------------
Page p2 = pageFromHtml(head + '<div id="c2" style="display:flex;height:40px;justify-content:center"><div id="b1" style="width:80px"></div><div id="b2" style="width:60px"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(p2.root, 'b1').x, 130, 'center puts the free space either side')
checkEqInt(byId(p2.root, 'b2').x, 210, 'and the items stay together')

Page p3 = pageFromHtml(head + '<div id="c3" style="display:flex;height:40px;justify-content:space-between"><div id="d1" style="width:80px"></div><div id="d2" style="width:60px"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(p3.root, 'd1').x, 0, 'space-between pins the first item')
checkEqInt(byId(p3.root, 'd2').x, 340, 'and the last')

// ---- flex-grow -------------------------------------------------------
Page p4 = pageFromHtml(head + '<div id="c4" style="display:flex;height:50px"><div id="e1" style="flex:1"></div><div id="e2" style="flex:2"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(p4.root, 'e1').w, 133, 'flex: 1 takes a third of the free space')
checkEqInt(byId(p4.root, 'e2').w, 267, 'flex: 2 takes the rest')
checkEqInt(byId(p4.root, 'e2').x, 133, 'and they sit side by side')

// ---- align-items -----------------------------------------------------
Page p5 = pageFromHtml(head + '<div id="c5" style="display:flex;height:50px;align-items:center"><div id="g1" style="width:50px;height:20px"></div></div></body>', 'about:blank', 400)
Box g1 = byId(p5.root, 'g1')
checkEqInt(g1.h, 20, 'an item with a height is not stretched')
checkEqInt(g1.y, 15, 'and centre puts the spare cross space either side')

// ---- a column --------------------------------------------------------
Page p6 = pageFromHtml(head + '<div id="c6" style="display:flex;flex-direction:column;height:90px"><div id="h1" style="height:30px"></div><div id="h2" style="height:20px"></div></div></body>', 'about:blank', 400)
Box h1 = byId(p6.root, 'h1')
Box h2 = byId(p6.root, 'h2')
checkEqInt(h1.y, 0, 'the first item of a column is at the top')
checkEqInt(h2.y, 30, 'the second below it')
checkEqInt(h1.h, 30, 'each keeps its declared height')
checkEqInt(h1.w, 400, 'and stretches across the cross axis')

// ---- gap -------------------------------------------------------------
Page p7 = pageFromHtml(head + '<div id="c7" style="display:flex;height:40px;gap:20px"><div id="j1" style="width:50px"></div><div id="j2" style="width:50px"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(p7.root, 'j1').x, 0, 'gap does not move the first item')
checkEqInt(byId(p7.root, 'j2').x, 70, 'and separates it from the next')

// ---- inline-flex -----------------------------------------------------
// An inline-flex container is inline-level and shrinks to fit: its width
// is the items plus the gaps, not the line it sits on.
Page p8 = pageFromHtml(head + '<div id="c8" style="display:inline-flex"><div id="m1" style="width:30px;height:12px"></div><div id="m2" style="width:50px;height:12px"></div></div></body>', 'about:blank', 400)
Box c8 = byId(p8.root, 'c8')
checkEqInt(c8.w, 80, 'inline-flex shrinks to fit its items')
checkEqInt(c8.x, 0, 'and sits at the start of the line it makes')
checkEqInt(byId(p8.root, 'm2').x, 30, 'its items still lay out on the main axis')
checkEqInt(c8.h, 12, 'and it is as tall as the tallest of them')

Page p9 = pageFromHtml(head + '<div id="c9" style="display:inline-flex;gap:5px"><div id="n1" style="width:30px;height:10px"></div><div id="n2" style="width:40px;height:10px"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(p9.root, 'c9').w, 75, 'the gaps count towards the shrink-to-fit width')

// An inline-flex container inside a paragraph is placed on the line like
// any other inline-level box. The x of the container itself depends on
// the width of the text before it, which is a font metric rather than a
// layout result, so what is checked here is that the container sits
// after that text and that its items are laid out relative to it.
Page p10 = pageFromHtml(head + '<p>before <span id="f1" style="display:inline-flex;gap:5px"><span id="k1" style="width:30px;height:10px"></span><span id="k2" style="width:40px;height:10px"></span></span> after</p></body>', 'about:blank', 400)
arr[Box] spans = []
collectBoxesForTag(p10.root, 'span', spans)
Box f1 = null
Box k1 = null
Box k2 = null
for int i = 0, i < spans.length, i++ {
    text sid = getAttr(spans[i].node, 'id')
    if sid == 'f1' { f1 = spans[i] }
    if sid == 'k1' { k1 = spans[i] }
    if sid == 'k2' { k2 = spans[i] }
}
checkEqInt(f1.w, 75, 'an inline-flex container in a line still shrinks to fit')
check(f1.x > 0, 'and sits after the text before it')
checkEqInt(k1.x, f1.x, 'its first item starts at its content edge')
checkEqInt(k2.x - k1.x, 35, 'and the second is a width and a gap along')

// ---- one item, distributed ------------------------------------------
// The three space-distribution values disagree about a single item:
// space-between packs it to the start, the other two centre it.
Page p11 = pageFromHtml(head + '<div style="display:flex;justify-content:space-between;height:20px"><div id="s1" style="width:50px"></div></div><div style="display:flex;justify-content:space-around;height:20px"><div id="s2" style="width:50px"></div></div><div style="display:flex;justify-content:space-evenly;height:20px"><div id="s3" style="width:50px"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(p11.root, 's1').x, 0, 'space-between packs a lone item to the start')
checkEqInt(byId(p11.root, 's2').x, 175, 'space-around centres it')
checkEqInt(byId(p11.root, 's3').x, 175, 'and so does space-evenly')

// ---- an anonymous flex item -----------------------------------------
// Text directly inside a flex container is a flex item of its own, so
// it takes main-axis space rather than being laid out as a line inside
// the container. How wide "abc" is at 16px monospace is a font metric
// rather than a layout result, so what is checked is that the next item
// starts exactly where the text item ends.
Page p12 = pageFromHtml(head + '<div id="c12" style="display:flex;height:40px">abc<div id="w1" style="width:60px"></div></div></body>', 'about:blank', 400)
Box c12 = byId(p12.root, 'c12')
Box w1 = byId(p12.root, 'w1')
check(c12.children.length >= 2, 'the text is a child box of the container')
Box anon = c12.children[0]
check(anon.w > 0, 'the anonymous text item has a width')
checkEqInt(w1.x, anon.w, 'and the next item starts where it ends')
checkEqInt(w1.w, 60, 'which keeps its own declared width')

// ---- an item does not shrink below what its content needs (§4.5) ------
// A flex item whose `min-width` is `auto` has an automatic minimum
// size: the smaller of its own declared width and the width its content
// needs. An unbreakable word therefore keeps the item as wide as the
// word, and the item overflows its container rather than the word being
// cut. Two things take the minimum away: an explicit `min-width`, and
// the item being a scroll container, which the standard says has an
// automatic minimum of zero.
//
// The width a word needs is this engine's own text measurement, so
// these compare the item against an inline-block holding the same word
// rather than against a number -- Chromium 141 answers 96 for
// `wwwwwwwwww` in 16px monospace, where an advance of 9.6 is its own
// and not this engine's. The numbers Chromium gives for the same
// markup, which is what says the rules are these rules:
//
//   width:50 container, item with no width            96, overflowing
//   the same item with `width: 200px`                 96
//   the same item with `min-width: 0`                 50
//   the same item with `overflow: hidden`             50
//   `flex-basis: content` on `wwww` in a wide row     39, its own width
//   `wwww wwww` in a 50px container                   50, above its own
//                                                     minimum of 39
//   the same in a 30px container                      39
//
// where 96 and 39 are ten and four of Chromium's advances. The last two
// are the pair that says what the minimum is: a container wider than
// the item's minimum shrinks it to the container, and only a narrower
// one shows the floor at all, so a check written against the wider one
// would pass whether the floor existed or not.
text shrinkRow = '<div id="f1" style="display:flex;width:50px">'
    + '<div id="f1i" style="height:20px">wwwwwwwwww</div></div>'
    + '<div id="f2" style="display:flex;width:50px">'
    + '<div id="f2i" style="height:20px;width:200px">wwwwwwwwww</div></div>'
    + '<div id="f3" style="display:flex;width:50px">'
    + '<div id="f3i" style="height:20px;min-width:0">wwwwwwwwww</div></div>'
    + '<div id="f4" style="display:flex;width:50px">'
    + '<div id="f4i" style="height:20px;overflow:hidden">wwwwwwwwww</div></div>'
    + '<div id="f5" style="display:flex;width:300px">'
    + '<div id="f5i" style="height:20px;flex-basis:content">wwww</div>'
    + '<div id="f5j" style="height:20px;width:100px"></div></div>'
    + '<div id="f6" style="display:flex;width:50px">'
    + '<div id="f6i" style="height:20px">wwww wwww</div></div>'
    + '<div id="f7" style="display:flex;width:30px">'
    + '<div id="f7i" style="height:20px">wwww wwww</div></div>'
    + '<div id="ctl10" style="display:inline-block">wwwwwwwwww</div>'
    + '<div id="ctl4" style="display:inline-block">wwww</div>'

Page pmin = pageFromHtml(head + shrinkRow + '</body>', 'about:blank', 400)
int wordTen = byId(pmin.root, 'ctl10').w
int wordFour = byId(pmin.root, 'ctl4').w
check(wordTen > 50, 'the control word is wider than the container it is put in')
checkEqInt(byId(pmin.root, 'f1i').w, wordTen,
           'an item with no width keeps the width its one word needs')
checkEqInt(byId(pmin.root, 'f2i').w, wordTen,
           'and so does one whose declared width is larger than that')
checkEqInt(byId(pmin.root, 'f3i').w, 50,
           'an explicit min-width takes the automatic minimum away')
checkEqInt(byId(pmin.root, 'f4i').w, 50,
           'and so does being a scroll container, whose automatic minimum is zero')
checkEqInt(byId(pmin.root, 'f5i').w, wordFour,
           '`flex-basis: content` sizes the item from its content')
checkEqInt(byId(pmin.root, 'f5j').x, wordFour, 'and the next item follows it there')
checkEqInt(byId(pmin.root, 'f6i').w, 50,
           'text that can wrap shrinks to the container while that is above its minimum')
checkEqInt(byId(pmin.root, 'f7i').w, wordFour,
           'and stops at its longest word, which is what its content needs')

finish('flex')
