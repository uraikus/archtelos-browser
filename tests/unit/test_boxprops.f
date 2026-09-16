// A batch of properties the engine computed and ignored, or did not
// parse at all. The geometry here was read out of Chromium 141 with
// getBoundingClientRect on the same markup.
//
//   box-sizing     CSS Box Sizing 3
//   max-height     CSS Box Sizing 3 -- the declaration was inert
//   word-spacing   CSS Text 3
//   caption-side   CSS2 §17 -- the snapshot has no separate tables module
//   outline-*      CSS Basic User Interface 3

import ../../src/browser/page.f
import ../assert.f

Box func byId(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'div', all)
    collectBoxesForTag(root, 'p', all)
    collectBoxesForTag(root, 'span', all)
    collectBoxesForTag(root, 'caption', all)
    collectBoxesForTag(root, 'td', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

// ---- box-sizing -------------------------------------------------------
Page p1 = pageFromHtml('<!doctype html><body style="margin:0;width:400px"><div id="a" style="box-sizing:border-box;width:200px;height:100px;padding:10px;border:5px solid"></div><div id="b" style="box-sizing:content-box;width:200px;height:100px;padding:10px;border:5px solid"></div></body>', 'about:blank', 400)
Box a = byId(p1.root, 'a')
checkEqInt(a.w, 200, 'border-box: the declared width is the border box')
checkEqInt(a.h, 100, 'and the declared height is the border box')
Box b = byId(p1.root, 'b')
checkEqInt(b.w, 230, 'content-box: padding and border add to the width')
checkEqInt(b.h, 130, 'and to the height')

// ---- max-height -------------------------------------------------------
Page p2 = pageFromHtml('<!doctype html><body style="margin:0;width:400px"><div id="c" style="height:300px;max-height:40px"></div></body>', 'about:blank', 400)
checkEqInt(byId(p2.root, 'c').h, 40, 'max-height caps the used height')

Page p2b = pageFromHtml('<!doctype html><body style="margin:0;width:400px"><div id="c" style="height:20px;max-height:40px"></div></body>', 'about:blank', 400)
checkEqInt(byId(p2b.root, 'c').h, 20, 'and leaves a smaller height alone')

// ---- word-spacing -----------------------------------------------------
// Two spaces at 10px each: exactly 20px wider, whatever the font.
Page p3 = pageFromHtml('<!doctype html><body style="margin:0;width:800px"><p style="margin:0"><span id="plain">aa bb cc</span></p><p style="margin:0;word-spacing:10px"><span id="spaced">aa bb cc</span></p></body>', 'about:blank', 800)
Box plain = byId(p3.root, 'plain')
Box spaced = byId(p3.root, 'spaced')
check(plain != null && spaced != null, 'both spans exist')
int plainW = 0
int spacedW = 0
arr[Box] paras = []
collectBoxesForTag(p3.root, 'p', paras)
for int j = 0, j < paras[0].lines[0].frags.length, j++ {
    Fragment f = paras[0].lines[0].frags[j]
    if f.x + f.w > plainW { plainW = f.x + f.w }
}
for int j = 0, j < paras[1].lines[0].frags.length, j++ {
    Fragment f = paras[1].lines[0].frags[j]
    if f.x + f.w > spacedW { spacedW = f.x + f.w }
}
checkEqInt(spacedW - plainW, 20, 'word-spacing widens each space by its length')

// ---- caption-side -----------------------------------------------------
Page p4 = pageFromHtml('<!doctype html><body style="margin:0;width:400px"><table style="caption-side:bottom"><caption id="cap">cap</caption><tr><td id="cell">x</td></tr></table></body>', 'about:blank', 400)
Box cap = byId(p4.root, 'cap')
Box cell = byId(p4.root, 'cell')
check(cap != null && cell != null, 'the caption and the cell both generate boxes')
check(cap.y > cell.y, 'caption-side: bottom puts the caption below the rows')

Page p5 = pageFromHtml('<!doctype html><body style="margin:0;width:400px"><table><caption id="cap">cap</caption><tr><td id="cell">x</td></tr></table></body>', 'about:blank', 400)
check(byId(p5.root, 'cap').y < byId(p5.root, 'cell').y, 'and the default keeps it above')

// ---- outline ----------------------------------------------------------
Page p6 = pageFromHtml('<!doctype html><body style="margin:0;width:400px"><div id="o" style="width:100px;height:50px;outline:3px solid #ff0000"></div></body>', 'about:blank', 400)
Box o = byId(p6.root, 'o')
checkEqInt(o.style.outlineWidth, 3, 'outline width is computed')
checkEqInt(o.style.outlineColor, packColor(255, 0, 0, 255), 'and its colour')
checkEqInt(o.w, 100, 'an outline does not change the box size')
checkEqInt(o.h, 50, 'in either axis')

finish('box properties')
