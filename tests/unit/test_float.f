// Floats and clear: CSS2 §9.5. Every expected number here was read out
// of Chromium 141 with getBoundingClientRect on the same markup, not
// reasoned about. See css-2026.md, "CSS Level 2".
//
// The rules that matter, and that the numbers encode:
//   - a float is placed at the edge of its containing block, as high as
//     it fits, after any float already there;
//   - a block box's own position and width ignore floats entirely, so a
//     block can sit underneath one;
//   - the LINE boxes inside a block are shortened by the floats beside
//     them, which is how text wraps around one;
//   - `clear` moves a block below the floats on that side;
//   - a float does not add to its parent's height.

import ../../src/browser/page.f
import ../assert.f

text page = '<!doctype html><html><head><style>'
    + 'body{margin:0;font:16px/20px monospace;width:400px}'
    + '</style></head><body>'
    + '<div id="c1"><div id="f1" style="float:left;width:100px;height:50px"></div><p id="t1" style="margin:0">aaaa bbbb cccc dddd eeee ffff gggg hhhh</p></div>'
    + '<div id="c2" style="margin-top:20px"><div id="f2" style="float:right;width:80px;height:40px"></div><p id="t2" style="margin:0">xxxx yyyy</p></div>'
    + '<div id="c3" style="margin-top:20px"><div id="f3" style="float:left;width:60px;height:30px"></div><div id="f4" style="float:left;width:60px;height:30px"></div><div id="n3" style="clear:left;height:10px"></div></div>'
    + '<div id="c4" style="margin-top:20px"><div id="f5" style="float:left;width:50px;height:25px"></div><div id="n4" style="height:10px"></div></div>'
    + '</body></html>'

Page p = pageFromHtml(page, 'about:blank', 400)

Box func boxById(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'div', all)
    collectBoxesForTag(root, 'p', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

// ---- a left float sits at the left edge, text wraps beside it --------
Box f1 = boxById(p.root, 'f1')
check(f1 != null, 'the float generates a box')
checkEqInt(f1.x, 0, 'a left float is at the left edge')
checkEqInt(f1.y, 0, 'and as high as it fits')
checkEqInt(f1.w, 100, 'with its declared width')

Box t1 = boxById(p.root, 't1')
checkEqInt(t1.x, 0, 'the paragraph beside it still starts at the left edge')
checkEqInt(t1.w, 400, 'and is still the full width: a block ignores floats')
checkEqInt(t1.h, 40, 'its text wraps onto two lines because the float shortens them')

Box c1 = boxById(p.root, 'c1')
checkEqInt(c1.h, 40, 'the float does not add to its parent height')

// ---- a right float --------------------------------------------------
Box f2 = boxById(p.root, 'f2')
checkEqInt(f2.x, 320, 'a right float is at the right edge')
checkEqInt(f2.y, 60, 'below the previous block')

Box c2 = boxById(p.root, 'c2')
checkEqInt(c2.y, 60, 'the block after an overflowing float is not pushed down')

// ---- two floats stack sideways, then clear ---------------------------
Box f3 = boxById(p.root, 'f3')
Box f4 = boxById(p.root, 'f4')
checkEqInt(f3.x, 0, 'the first of two left floats')
checkEqInt(f4.x, 60, 'the second sits beside it')
checkEqInt(f4.y, 100, 'at the same height')

Box n3 = boxById(p.root, 'n3')
checkEqInt(n3.y, 130, 'clear: left drops below both floats')

Box c3 = boxById(p.root, 'c3')
checkEqInt(c3.h, 40, 'and the parent grows to hold the cleared box')

// ---- without clear, a block goes under the float ---------------------
Box n4 = boxById(p.root, 'n4')
checkEqInt(n4.y, 160, 'a block with no clear starts beside the float')
checkEqInt(n4.x, 0, 'at the left edge, underneath it')

// ---- a line below a float is not shortened by it ---------------------
// The float is 20 tall and the line height 22, so the first line sits
// beside it and the second does not.
Page q = pageFromHtml('<!doctype html><body style="margin:0;font:16px/22px monospace;width:600px"><div style="float:right;width:100px;height:20px"></div><p style="margin:0">aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm nnnn oooo pppp qqqq rrrr ssss tttt uuuu vvvv wwww xxxx yyyy zzzz</p></body>', 'about:blank', 600)
arr[Box] qp = []
collectBoxesForTag(q.root, 'p', qp)
check(qp[0].lines.length >= 2, 'the paragraph wraps')
int firstRight = 0
int secondRight = 0
for int j = 0, j < qp[0].lines[0].frags.length, j++ {
    Fragment f = qp[0].lines[0].frags[j]
    if f.x + f.w > firstRight { firstRight = f.x + f.w }
}
for int j = 0, j < qp[0].lines[1].frags.length, j++ {
    Fragment f = qp[0].lines[1].frags[j]
    if f.x + f.w > secondRight { secondRight = f.x + f.w }
}
check(firstRight <= 500, 'the line beside the float stops at its edge')
check(secondRight > 500, 'the line below it runs past that edge')

finish('float')
