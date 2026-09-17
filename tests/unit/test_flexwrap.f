// Flex containers with more than one line: `flex-wrap`, the
// `align-content` that only means anything once there is more than one
// line, and the auto margins that take the free space before
// `justify-content` is consulted.
//
// Every expected number was read out of Chromium 141 with
// getBoundingClientRect on this exact markup.

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
text i20 = 'width:150px;height:20px'
text i30 = 'width:150px;height:30px'

// ---- nowrap is the control: three 150px items shrink onto one line ---
// This is what the engine already did, and it must keep doing it.
Page p0 = pageFromHtml(head + `<div id="c" style="display:flex;width:400px"><div id="a" style="${i20}"></div><div id="b" style="${i20}"></div><div id="d" style="${i30}"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(p0.root, 'a').w, 133, 'without wrapping the items shrink to fit')
checkEqInt(byId(p0.root, 'd').x, 267, 'and all three stay on one line')
checkEqInt(byId(p0.root, 'c').h, 30, 'the container is one line tall')

// ---- the same three items, wrapping ----------------------------------
Page p1 = pageFromHtml(head + `<div id="c" style="display:flex;flex-wrap:wrap;width:400px"><div id="a" style="${i20}"></div><div id="b" style="${i20}"></div><div id="d" style="${i30}"></div></div></body>`, 'about:blank', 400)
Box c1 = byId(p1.root, 'c')
Box a1 = byId(p1.root, 'a')
Box b1 = byId(p1.root, 'b')
Box d1 = byId(p1.root, 'd')
checkEqInt(a1.w, 150, 'a wrapping item keeps its width instead of shrinking')
checkEqInt(a1.x, 0, 'the first item opens the first line')
checkEqInt(b1.x, 150, 'the second fits beside it')
checkEqInt(d1.x, 0, 'the third does not fit, so it opens a second line')
checkEqInt(a1.y, 0, 'the first line is at the top')
checkEqInt(d1.y, 20, 'the second line follows the first line height')
checkEqInt(c1.h, 50, 'an auto height is the sum of the line heights')

// ---- wrap-reverse stacks the lines the other way ---------------------
// It flips the cross axis, so the first line is at the bottom AND an
// item sits at the bottom of its own line.
Page p2 = pageFromHtml(head + `<div id="c" style="display:flex;flex-wrap:wrap-reverse;width:400px;height:100px"><div id="a" style="${i20}"></div><div id="b" style="${i20}"></div><div id="d" style="${i30}"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(p2.root, 'a').y, 80, 'wrap-reverse puts the first line last')
checkEqInt(byId(p2.root, 'b').y, 80, 'both of its items')
checkEqInt(byId(p2.root, 'd').y, 25, 'and the second line first')
checkEqInt(byId(p2.root, 'a').x, 0, 'the main axis is unaffected')

// ---- align-content, on a container with cross space to give ----------
Page p3 = pageFromHtml(head + `<div id="c" style="display:flex;flex-wrap:wrap;width:400px;height:200px;align-content:center"><div id="a" style="${i20}"></div><div id="b" style="${i20}"></div><div id="d" style="${i30}"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(p3.root, 'a').y, 75, 'align-content centre offsets the first line')
checkEqInt(byId(p3.root, 'd').y, 95, 'and the second follows it')

Page p4 = pageFromHtml(head + `<div id="c" style="display:flex;flex-wrap:wrap;width:400px;height:200px;align-content:space-between"><div id="a" style="${i20}"></div><div id="b" style="${i20}"></div><div id="d" style="${i30}"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(p4.root, 'a').y, 0, 'space-between pins the first line to the start')
checkEqInt(byId(p4.root, 'd').y, 170, 'and the last to the end')

Page p5 = pageFromHtml(head + `<div id="c" style="display:flex;flex-wrap:wrap;width:400px;height:200px;align-content:flex-end"><div id="a" style="${i20}"></div><div id="b" style="${i20}"></div><div id="d" style="${i30}"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(p5.root, 'a').y, 150, 'flex-end pushes every line to the far side')
checkEqInt(byId(p5.root, 'd').y, 170, 'keeping their order')

// ---- the default is stretch: the lines share the free cross space ----
Page p6 = pageFromHtml(head + '<div id="c" style="display:flex;flex-wrap:wrap;width:400px;height:200px"><div id="a" style="width:150px"></div><div id="b" style="width:150px"></div><div id="d" style="width:150px"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(p6.root, 'a').h, 100, 'two lines of no height each take half the container')
checkEqInt(byId(p6.root, 'd').y, 100, 'and the second starts where the first ends')

// ---- gaps count both in the break and between the lines --------------
Page p7 = pageFromHtml(head + `<div id="c" style="display:flex;flex-wrap:wrap;width:400px;gap:20px 10px"><div id="a" style="${i20}"></div><div id="b" style="${i20}"></div><div id="d" style="${i30}"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(p7.root, 'b').x, 160, 'the column gap separates items on a line')
checkEqInt(byId(p7.root, 'd').y, 40, 'the row gap separates the lines')
checkEqInt(byId(p7.root, 'c').h, 70, 'and counts towards an auto height')

// ---- growing is per line, not across the container --------------------
Page p8 = pageFromHtml(head + `<div id="c" style="display:flex;flex-wrap:wrap;width:400px"><div id="a" style="${i20};flex-grow:1"></div><div id="b" style="${i20};flex-grow:1"></div><div id="d" style="${i30};flex-grow:1"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(p8.root, 'a').w, 200, 'the two items on the first line split its free space')
checkEqInt(byId(p8.root, 'b').x, 200, 'and follow one another')
checkEqInt(byId(p8.root, 'd').w, 400, 'the item alone on the second line takes all of its own')

// ---- a column container wraps into columns ---------------------------
Page p9 = pageFromHtml(head + '<div id="c" style="display:flex;flex-direction:column;flex-wrap:wrap;width:400px;height:60px"><div id="a" style="width:50px;height:40px"></div><div id="b" style="width:60px;height:40px"></div><div id="d" style="width:70px;height:40px"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(p9.root, 'a').y, 0, 'the first item opens the first column')
checkEqInt(byId(p9.root, 'b').y, 0, 'the second does not fit below it, so it opens the next')
checkEqInt(byId(p9.root, 'b').x, 123, 'the columns are laid out across the cross axis')
checkEqInt(byId(p9.root, 'd').x, 257, 'one per item here')

// ---- auto margins take the free space before justify-content does ----
Page pa = pageFromHtml(head + '<div id="c" style="display:flex;width:400px;height:40px"><div id="a" style="width:100px;height:20px;margin-right:auto"></div><div id="b" style="width:100px;height:20px"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(pa.root, 'a').x, 0, 'an auto margin on one side leaves the item where it is')
checkEqInt(byId(pa.root, 'b').x, 300, 'and pushes everything after it to the end')

Page pb = pageFromHtml(head + '<div id="c" style="display:flex;width:400px;height:40px"><div id="a" style="width:100px;height:20px;margin-left:auto;margin-right:auto"></div></div></body>', 'about:blank', 400)
checkEqInt(byId(pb.root, 'a').x, 150, 'auto on both sides centres the item')

// ---- baseline alignment ----------------------------------------------
// Items sit so their first baselines coincide, which is not the same as
// aligning their boxes: the one with the smaller baseline moves down.
//
// The numbers here were measured on a whole document rather than by
// setting innerHTML on a div, because a <body> inside innerHTML is
// dropped by the parser and the page's own font never applies -- which
// silently changed every font-dependent number in the first attempt.
Page pc = pageFromHtml(head + '<div id="c" style="display:flex;align-items:baseline;width:400px;height:80px"><div id="a" style="width:100px;font-size:16px">Ag</div><div id="b" style="width:100px;font-size:32px">Ag</div></div></body>', 'about:blank', 400)
Box ba = byId(pc.root, 'a')
Box bb = byId(pc.root, 'b')
checkEqInt(bb.y, 0, 'the item with the deepest baseline sets the line')
checkEqInt(ba.y, 6, 'and the other drops so its baseline meets it')
checkEqInt(ba.y + ba.baseline, bb.y + bb.baseline, 'which is to say the baselines coincide')

// Without it the two boxes simply start together.
Page pd = pageFromHtml(head + '<div id="c" style="display:flex;align-items:flex-start;width:400px;height:80px"><div id="a" style="width:100px;font-size:16px">Ag</div><div id="b" style="width:100px;font-size:32px">Ag</div></div></body>', 'about:blank', 400)
checkEqInt(byId(pd.root, 'a').y, 0, 'flex-start aligns the boxes, not the text')
check(byId(pd.root, 'a').y + byId(pd.root, 'a').baseline != byId(pd.root, 'b').y + byId(pd.root, 'b').baseline, 'so the baselines do not coincide')

// ---- flex-flow names direction and wrap, in either order -------------
// Exercised because it is the only path through the shorthand, and an
// unexercised path is where a memory bug hides: this one released an
// ascii alias that was never retained, which valgrind found and the
// tests could not (FINDINGS.md, "ascii aliases are not retained").
Page pf = pageFromHtml(head + `<div id="c" style="display:flex;flex-flow:row wrap;width:400px"><div id="a" style="${i20}"></div><div id="b" style="${i20}"></div><div id="d" style="${i30}"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(pf.root, 'a').w, 150, 'flex-flow row wrap wraps rather than shrinking')
checkEqInt(byId(pf.root, 'd').y, 20, 'onto a second line')

Page pg = pageFromHtml(head + `<div id="c" style="display:flex;flex-flow:wrap column;width:400px;height:60px"><div id="a" style="width:50px;height:40px"></div><div id="b" style="width:60px;height:40px"></div></div></body>`, 'about:blank', 400)
checkEqInt(byId(pg.root, 'b').y, 0, 'and the other order names the same two things')

finish('flex wrap')
