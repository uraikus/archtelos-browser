// CSS Anchor Positioning 1.
//
// An absolutely positioned box normally resolves against the padding
// box of its nearest positioned ancestor. `position-anchor` names a
// second rectangle to resolve against instead -- another element's
// border box, found by the `anchor-name` it declared -- and
// `position-area` says which of nine regions around that rectangle the
// box goes in.
//
// Every number below is Chromium 141's, read off an anchor at
// (150, 100) sized 100x60 -- so left 150, right 250, top 100, bottom
// 160, centre (200, 130) -- with a 40x20 box naming it:
//
//   center        180,120     top            180,80     bottom  180,160
//   left          110,120     right          250,120
//   top left      110,80      bottom right   250,160
//   start start   110,80      end end        250,160
//   span-all center 180,120   top span-all   180,80
//
// Each axis is one of three bands. A band before the anchor
// end-aligns the box, so its far edge meets the anchor's near one:
// `top` puts the box's bottom at the anchor's top, 100 - 20 = 80. A
// band after start-aligns it. The anchor's own band centres the box on
// the anchor, 130 - 10 = 120.
//
// `span-all` centres on the *anchor*, not on the region it spans: in a
// 300px containing block `span-all center` is 120, where centring in
// the region would be 140. That is the case this suite exists to pin.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func anchorBoxById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = anchorBoxById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

// The anchor sits at (150, 100) inside a 400x300 positioned block, and
// the box under test is 40x20 and names it. Returns the box, so a check
// can ask for either coordinate.
Box func anchored(area:text) {
    cascadeReset()
    cssViewportWidth = 600
    text areaDecl = area == '' ? '' : ('position-area:' + area + ';')
    Node doc = parseHtmlText('<html><body style="margin:0">'
        + '<div style="position:relative;width:400px;height:300px">'
        + '<div id="anc" style="position:absolute;left:150px;top:100px;'
        + 'width:100px;height:60px;anchor-name:--a"></div>'
        + '<div id="pos" style="position:absolute;position-anchor:--a;'
        + 'width:40px;height:20px;' + areaDecl + '"></div>'
        + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return anchorBoxById(layoutDocument(doc, 600), 'pos')
}

int func anchoredX(area:text) { Box b = anchored(area)  return b == null ? -1 : b.x }
int func anchoredY(area:text) { Box b = anchored(area)  return b == null ? -1 : b.y }

// ---- the nine regions ----------------------------------------------------
checkEqInt(anchoredX('center'), 180, 'center: centred on the anchor across')
checkEqInt(anchoredY('center'), 120, 'center: and down')

checkEqInt(anchoredY('top'), 80, 'top: the box sits above, its bottom at the anchor top')
checkEqInt(anchoredX('top'), 180, 'top: centred across')
checkEqInt(anchoredY('bottom'), 160, 'bottom: below, its top at the anchor bottom')
checkEqInt(anchoredX('left'), 110, 'left: its right edge at the anchor left')
checkEqInt(anchoredY('left'), 120, 'left: centred down')
checkEqInt(anchoredX('right'), 250, 'right: its left edge at the anchor right')

checkEqInt(anchoredX('top left'), 110, 'top left: the two axes combine')
checkEqInt(anchoredY('top left'), 80, 'top left: in both')
checkEqInt(anchoredX('bottom right'), 250, 'bottom right: and the other corner')
checkEqInt(anchoredY('bottom right'), 160, 'bottom right: in both')

// The regions have to differ from one another, or an implementation
// that answered `center` to everything would pass a third of these.
check(anchoredY('top') != anchoredY('bottom'), 'top and bottom are not the same place')
check(anchoredX('left') != anchoredX('right'), 'nor left and right')
check(anchoredY('top') != anchoredY('center'), 'nor top and center')

// ---- span-all centres on the anchor, not on the region -------------------
// The containing block is 300 tall, so centring in the region would put
// the box at 140. Chromium says 120, which is the anchor's centre.
checkEqInt(anchoredY('span-all center'), 120, 'span-all centres on the anchor')
check(anchoredY('span-all center') != 140, 'and not on the region it spans')
checkEqInt(anchoredX('top span-all'), 180, 'a span in the inline axis centres there too')
checkEqInt(anchoredY('top span-all'), 80, 'while the block axis still says top')

// ---- the logical keywords name the same regions --------------------------
// In the left-to-right horizontal mode this engine lays out in, `start`
// is `top` in the block axis and `left` in the inline one. Each is
// checked against the physical region it stands for *and* against a
// different region, because two names that both did nothing would agree.
checkEqInt(anchoredX('start start'), anchoredX('top left'), 'start start is top left across')
checkEqInt(anchoredY('start start'), anchoredY('top left'), 'and down')
checkEqInt(anchoredX('end end'), anchoredX('bottom right'), 'end end is bottom right across')
checkEqInt(anchoredY('end end'), anchoredY('bottom right'), 'and down')
check(anchoredY('start start') != anchoredY('end end'), 'and the two differ from each other')
checkEqInt(anchoredX('block-start inline-start'), 110, 'block-start inline-start is top left')
checkEqInt(anchoredY('block-start inline-start'), 80, 'in both axes')

// ---- a box that asked for nothing is not moved ---------------------------
// `position-area` is what places the box; an absolutely positioned box
// naming an anchor but no region keeps the placement it would have had,
// which is what keeps the feature off every ordinary positioned box.
int plainX = anchoredX('')
check(plainX != 110 || anchoredY('') != 80, 'no position-area is not a region')

finish('anchor positioning')
