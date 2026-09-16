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

finish('flex')
