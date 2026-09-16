// `aspect-ratio` (CSS Sizing 4 §4): a box with one definite dimension
// takes the other from the ratio.
//
// Every number below was read off Chromium 141 on the same markup, in a
// 400px containing block at 16px/20px monospace with no margins:
//
//   aspect-ratio: 2                    400 x 200   an auto width fills, the ratio gives the height
//   aspect-ratio: 2; width: 100px      100 x 50
//   aspect-ratio: 2; height: 40px       80 x 40    a definite height gives the width, block-level or not
//   aspect-ratio: 2; w 100; h 60       100 x 60    both definite, the ratio does not apply
//   aspect-ratio: 1/2; width: 100px    100 x 200
//   aspect-ratio: 4/3; width: 120px    120 x 90
//   aspect-ratio: 2; w 100; padding 10 120 x 70    the ratio is the content box
//   the same with box-sizing: border-box 100 x 50  and now it is the border box
//   aspect-ratio: 2; w 100; border 10  120 x 70
//   aspect-ratio: 2; w 100; max-height 30  100 x 30
//   aspect-ratio: 2; w 100; min-height 80  100 x 80
//   aspect-ratio: 2; w 100, three lines of text  100 x 60   content is a minimum
//   the same with overflow: hidden     100 x 50   and it is not, there
//   aspect-ratio: 0; width: 100px      100 x 0    a zero term is degenerate
//   aspect-ratio: 2/0; width: 100px    100 x 0
//   aspect-ratio: -1; width: 100px     100 x 0    invalid: computes to auto
//   aspect-ratio: auto; width: 100px   100 x 0
//   display: flex; aspect-ratio: 2; w 100  100 x 50
//
// The last check of each group is the one that does not depend on a
// number being known in advance: `2` and `4/2` are two ways of writing
// one ratio and must land on the same box, and a ratio that resolves to
// 50 pixels must give the same box as writing `height: 50px`.
import ../../src/browser/page.f
import ../assert.f

Box func aspectBox(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'div', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    arr[Box] imgs = []
    collectBoxesForTag(root, 'img', imgs)
    for int i = 0, i < imgs.length, i++ {
        if imgs[i].node != null && getAttr(imgs[i].node, 'id') == id { return imgs[i] }
    }
    return null
}

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:400px">'

// Each case in its own document: a box whose height comes from a ratio
// is exactly the kind of thing that shifts what follows it, and one
// contaminated reference is worth more than all the cases it saves.
Box func caseBox(markup:text) {
    Page p = pageFromHtml(head + markup + '</body>', 'tests/fixtures/page.html', 400)
    return aspectBox(p.root, 'e')
}

// ---- the ratio gives the dimension that is automatic -------------------
Box a1 = caseBox('<div id="e" style="aspect-ratio:2"></div>')
checkEqInt(a1.w, 400, 'an automatic width still fills the containing block')
checkEqInt(a1.h, 200, 'and the ratio gives the height from it')

Box a2 = caseBox('<div id="e" style="aspect-ratio:2;width:100px"></div>')
checkEqInt(a2.w, 100, 'a declared width is untouched')
checkEqInt(a2.h, 50, 'and the height comes from the ratio')

Box a3 = caseBox('<div id="e" style="aspect-ratio:2;height:40px"></div>')
checkEqInt(a3.h, 40, 'a declared height is untouched')
checkEqInt(a3.w, 80, 'and a block-level box takes its width from the ratio rather than filling')

Box a4 = caseBox('<div id="e" style="display:inline-block;aspect-ratio:2;height:40px"></div>')
checkEqInt(a4.w, 80, 'an inline-block does the same')
checkEqInt(a4.h, 40, 'at the height it was given')

Box a5 = caseBox('<div id="e" style="aspect-ratio:2;width:100px;height:60px"></div>')
checkEqInt(a5.w, 100, 'with both dimensions declared the width is the declared one')
checkEqInt(a5.h, 60, 'and so is the height: the ratio does not apply')

Box a6 = caseBox('<div id="e" style="aspect-ratio:1/2;width:100px"></div>')
checkEqInt(a6.h, 200, 'a ratio below one makes the box taller than it is wide')

Box a7 = caseBox('<div id="e" style="aspect-ratio:4/3;width:120px"></div>')
checkEqInt(a7.h, 90, 'four by three')

// ---- which box the ratio is ------------------------------------------
Box b1 = caseBox('<div id="e" style="aspect-ratio:2;width:100px;padding:10px"></div>')
checkEqInt(b1.w, 120, 'padding is outside the declared width')
checkEqInt(b1.h, 70, 'and outside the height the ratio gave the content box')

Box b2 = caseBox('<div id="e" style="aspect-ratio:2;width:100px;padding:10px;box-sizing:border-box"></div>')
checkEqInt(b2.w, 100, 'a border-box width includes the padding')
checkEqInt(b2.h, 50, 'and the ratio is then the border box, not the content box')

Box b3 = caseBox('<div id="e" style="aspect-ratio:2;width:100px;border:10px solid #ff0000"></div>')
checkEqInt(b3.w, 120, 'a border counts like padding')
checkEqInt(b3.h, 70, 'on both axes')

Box b4 = caseBox('<div id="e" style="aspect-ratio:2;height:40px;padding:10px"></div>')
checkEqInt(b4.w, 100, 'and the width derived from a height is the content width plus the padding')
checkEqInt(b4.h, 60, 'the declared height being the content box')

// ---- the bounds still apply ------------------------------------------
Box c1 = caseBox('<div id="e" style="aspect-ratio:2;width:100px;max-height:30px"></div>')
checkEqInt(c1.h, 30, 'max-height cuts a height the ratio gave')
checkEqInt(c1.w, 100, 'and the width is not recomputed to match')

Box c2 = caseBox('<div id="e" style="aspect-ratio:2;width:100px;min-height:80px"></div>')
checkEqInt(c2.h, 80, 'min-height raises it')

// ---- content is a minimum, unless the box clips ------------------------
text threeLines = 'aa bb cc dd ee ff gg hh'
Box d0 = caseBox(`<div id="e" style="width:100px">${threeLines}</div>`)
check(d0.h > 50, 'the text is taller than the ratio would make the box')
Box d1 = caseBox(`<div id="e" style="aspect-ratio:2;width:100px">${threeLines}</div>`)
checkEqInt(d1.h, d0.h, 'content the ratio cannot hold makes the box taller, not clipped')
Box d2 = caseBox(`<div id="e" style="aspect-ratio:2;width:100px;overflow:hidden">${threeLines}</div>`)
checkEqInt(d2.h, 50, 'a box that clips takes the ratio and lets the content overflow')

// ---- degenerate and invalid ratios ------------------------------------
Box e1 = caseBox('<div id="e" style="aspect-ratio:0;width:100px"></div>')
checkEqInt(e1.h, 0, 'a zero term makes the derived dimension zero')
Box e2 = caseBox('<div id="e" style="aspect-ratio:2/0;width:100px"></div>')
checkEqInt(e2.h, 0, 'on either side of the slash')
Box e3 = caseBox('<div id="e" style="aspect-ratio:-1;width:100px"></div>')
checkEqInt(e3.h, 0, 'a negative ratio is an invalid declaration and is dropped')
Box e4 = caseBox('<div id="e" style="aspect-ratio:auto;width:100px"></div>')
checkEqInt(e4.h, 0, 'and `auto` on a box with no natural ratio does nothing')

// ---- a flex container is sized like a block ----------------------------
Box f1 = caseBox('<div id="e" style="display:flex;aspect-ratio:2;width:100px"></div>')
checkEqInt(f1.h, 50, 'a flex container takes its height from the ratio too')
Box f2 = caseBox('<div id="e" style="display:grid;aspect-ratio:2;width:100px"></div>')
checkEqInt(f2.h, 50, 'and so does a grid container')

// An item taller than the ratio makes the container taller, and does
// not once the container clips -- the same two answers a block gives,
// and Chromium 141 gives 90 and 50 for these four.
Box f3 = caseBox('<div id="e" style="display:flex;aspect-ratio:2;width:100px">'
    + '<div style="height:90px;width:10px"></div></div>')
checkEqInt(f3.h, 90, 'a flex item taller than the ratio makes the container taller')
Box f4 = caseBox('<div id="e" style="display:flex;aspect-ratio:2;width:100px;overflow:hidden">'
    + '<div style="height:90px;width:10px"></div></div>')
checkEqInt(f4.h, 50, 'and does not once the container clips')
Box f5 = caseBox('<div id="e" style="display:grid;aspect-ratio:2;width:100px">'
    + '<div style="height:90px"></div></div>')
checkEqInt(f5.h, 90, 'a grid row taller than the ratio does the same')
Box f6 = caseBox('<div id="e" style="display:grid;aspect-ratio:2;width:100px;overflow:hidden">'
    + '<div style="height:90px"></div></div>')
checkEqInt(f6.h, 50, 'and gives way to the ratio when the container clips')

// ---- `auto <ratio>` prefers a natural ratio ---------------------------
// tile.png is 10x10, so its natural ratio is 1. `auto 2` must leave that
// alone and `2` must override it -- which is the whole difference
// between the two forms, and neither can be read off the other.
Box g1 = caseBox('<img id="e" src="tile.png" style="width:100px">')
checkEqInt(g1.h, 100, 'an image keeps its natural ratio')
Box g2 = caseBox('<img id="e" src="tile.png" style="aspect-ratio:2;width:100px">')
checkEqInt(g2.h, 50, 'a declared ratio overrides the natural one')
Box g3 = caseBox('<img id="e" src="tile.png" style="aspect-ratio:auto 2;width:100px">')
checkEqInt(g3.h, 100, '`auto <ratio>` keeps the natural ratio where there is one')
Box g4 = caseBox('<div id="e" style="aspect-ratio:auto 2;width:100px"></div>')
checkEqInt(g4.h, 50, 'and falls back to the ratio where there is not')

// ---- two ways of saying the same thing --------------------------------
// Neither of these depends on 50 being the right answer: they assert
// that two spellings agree, which is what catches the case the numbers
// above were not chosen to cover.
Box h1 = caseBox('<div id="e" style="aspect-ratio:2;width:100px"></div>')
Box h2 = caseBox('<div id="e" style="aspect-ratio:4/2;width:100px"></div>')
checkEqInt(h2.h, h1.h, '`4/2` is the ratio `2`')
checkEqInt(h2.w, h1.w, 'on both axes')
// Spaces around the slash are the ordinary way to write a ratio, and
// they are the spelling a parser that splits on whitespace first gets
// wrong -- `16 / 9` arriving as three tokens rather than one.
Box h2b = caseBox('<div id="e" style="aspect-ratio:16 / 9;width:160px"></div>')
Box h2c = caseBox('<div id="e" style="aspect-ratio:16/9;width:160px"></div>')
checkEqInt(h2b.h, h2c.h, 'the spaces around a slash make no difference')
checkEqInt(h2b.h, 90, 'and sixteen by nine at 160 wide is 90 tall')

Box h3 = caseBox('<div id="e" style="aspect-ratio:2 auto;width:100px"></div>')
checkEqInt(h3.h, g4.h, 'the ratio may be written before `auto` as well as after')
Box h4 = caseBox('<div id="e" style="width:100px;height:50px"></div>')
checkEqInt(h1.h, h4.h, 'a ratio that works out to 50 pixels is the box `height: 50px` gives')
checkEqInt(h1.w, h4.w, 'and the same width with it')

finish('aspect ratio')
