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

// ---- position-try-fallbacks ----------------------------------------------
// An anchored box that overflows its containing block tries the
// fallbacks in written order and takes the first that fits. Every
// number here is Chromium 141's, read off a clipping 400x300 block, an
// anchor 100x20 whose top varies, and a 40x30 box naming it.
//
//   anchor top 150, `top`, no fallback          y 120
//   anchor top 10,  `top`, no fallback          y -20
//   anchor top 10,  `top`, `bottom`             y 30
//   anchor top 150, `top`, `bottom`             y 120
//   anchor top 10,  `top`, `left, bottom`       x 110, y 5
//   anchor top 10,  `top`, `flip-block`         y 30
//   anchor top 150, `left`, `flip-inline`       unchanged
//   anchor top 270, `bottom`, `top`             y 240
//   anchor top 10,  `top`, `top`                y -20

Box func tried(ancTop:int, area:text, fb:text) {
    cascadeReset()
    cssViewportWidth = 600
    text fbDecl = fb == '' ? '' : ('position-try-fallbacks:' + fb + ';')
    Node doc = parseHtmlText('<html><body style="margin:0">'
        + '<div style="position:relative;width:400px;height:300px;overflow:hidden">'
        + `<div id="anc" style="position:absolute;left:150px;top:${ancTop}px;`
        + 'width:100px;height:20px;anchor-name:--a"></div>'
        + '<div id="pos" style="position:absolute;position-anchor:--a;'
        + 'width:40px;height:30px;position-area:' + area + ';' + fbDecl + '"></div>'
        + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return anchorBoxById(layoutDocument(doc, 600), 'pos')
}

int func triedX(ancTop:int, area:text, fb:text) { Box b = tried(ancTop, area, fb)  return b == null ? -1 : b.x }
int func triedY(ancTop:int, area:text, fb:text) { Box b = tried(ancTop, area, fb)  return b == null ? -1 : b.y }

// A position that fits is kept, and the fallbacks are never consulted.
checkEqInt(triedY(150, 'top', ''), 120, 'a fitting position is kept')
checkEqInt(triedY(150, 'top', 'bottom'), 120, 'and a fallback beside it is not used')

// Without fallbacks, an overflowing position is left overflowing: this
// is a retry list, not an automatic correction.
checkEqInt(triedY(10, 'top', ''), -20, 'an overflowing position with no fallback stands')

// With one, the box moves to it.
checkEqInt(triedY(10, 'top', 'bottom'), 30, 'an overflowing position takes its fallback')
check(triedY(10, 'top', 'bottom') != triedY(10, 'top', ''),
      'which is not where it would have been')

// With two, the FIRST that fits wins -- not the best fit. `left` is
// merely written first, and that is what decides it.
checkEqInt(triedX(10, 'top', 'left, bottom'), 110, 'the first fallback that fits wins')
checkEqInt(triedY(10, 'top', 'left, bottom'), 5, 'in both axes')
check(triedY(10, 'top', 'left, bottom') != triedY(10, 'top', 'bottom'),
      'and the order of the list is what chooses between them')

// When nothing fits, the original position stands. An implementation
// that kept the last candidate it tried would put the box elsewhere.
checkEqInt(triedY(10, 'top', 'top'), -20, 'when no candidate fits the original stands')

// Overflow at the far edge falls back too, not just at the near one.
checkEqInt(triedY(270, 'bottom', 'top'), 240, 'overflow past the end falls back as well')

// ---- the flip keywords ---------------------------------------------------
// A `flip-` fallback transforms the area in force rather than naming a
// new one, and is not applied at all when the original fits.
checkEqInt(triedY(10, 'top', 'flip-block'), 30, 'flip-block swaps the block axis bands')
checkEqInt(triedY(10, 'top', 'flip-block'), triedY(10, 'top', 'bottom'),
           'which is what `bottom` would have said')
checkEqInt(triedX(150, 'left', 'flip-inline'), 110, 'a flip is not applied when the original fits')
checkEqInt(triedY(150, 'left', 'flip-inline'), 145, 'in either axis')

// ---- position-try-order --------------------------------------------------
// The order sorts the candidates by the space the region offers in the
// named axis, descending, and that sort applies whether or not the
// original position overflows -- which is what makes it a different
// mechanism from the retry loop above rather than a tie-break inside
// it.
//
// Chromium 141 on an anchor at (60, 200) sized 40x20 in a 400x300
// block, so the space is 200 above, 80 below, 60 left and 300 right,
// with a 30x30 box naming it:
//
//   `left`,   `left, right`,  normal        x 30   (left, first and fits)
//   `left`,   `left, right`,  most-width    x 100  (right, 300 > 60)
//   `bottom`, `bottom, top`,  normal        y 220  (bottom fits)
//   `bottom`, `bottom, top`,  most-height   y 170  (top, 200 > 80)

Box func ordered(area:text, fb:text, ord:text) {
    cascadeReset()
    cssViewportWidth = 600
    text ordDecl = ord == '' ? '' : ('position-try-order:' + ord + ';')
    Node doc = parseHtmlText('<html><body style="margin:0">'
        + '<div style="position:relative;width:400px;height:300px;overflow:hidden">'
        + '<div id="anc" style="position:absolute;left:60px;top:200px;'
        + 'width:40px;height:20px;anchor-name:--a"></div>'
        + '<div id="pos" style="position:absolute;position-anchor:--a;'
        + 'width:30px;height:30px;position-area:' + area + ';'
        + 'position-try-fallbacks:' + fb + ';' + ordDecl + '"></div>'
        + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return anchorBoxById(layoutDocument(doc, 600), 'pos')
}

int func orderedX(area:text, fb:text, ord:text) { Box b = ordered(area, fb, ord)  return b == null ? -1 : b.x }
int func orderedY(area:text, fb:text, ord:text) { Box b = ordered(area, fb, ord)  return b == null ? -1 : b.y }

// Without an order the first candidate that fits wins, which is the
// one written first.
checkEqInt(orderedX('left', 'left, right', ''), 30, 'with no order the first that fits wins')
checkEqInt(orderedY('bottom', 'bottom, top', ''), 220, 'and a fitting original is kept')

// `most-width` sorts by the inline space each region offers, so the
// right side -- 300 against 60 -- goes first and is taken.
checkEqInt(orderedX('left', 'left, right', 'most-width'), 100,
           'most-width takes the side with more room')
check(orderedX('left', 'left, right', 'most-width') != orderedX('left', 'left, right', ''),
      'which is not where the written order would have put it')

// The row that says the order is not part of the retry: `bottom` fits,
// and `most-height` moves the box to `top` anyway.
checkEqInt(orderedY('bottom', 'bottom, top', 'most-height'), 170,
           'most-height sorts even when the original fits')
check(orderedY('bottom', 'bottom, top', 'most-height')
      != orderedY('bottom', 'bottom, top', ''),
      'so the order applies without any overflow to trigger it')

// The logical spellings are the physical ones in this writing mode.
checkEqInt(orderedY('bottom', 'bottom, top', 'most-block-size'),
           orderedY('bottom', 'bottom, top', 'most-height'),
           'most-block-size is most-height here')
checkEqInt(orderedX('left', 'left, right', 'most-inline-size'),
           orderedX('left', 'left, right', 'most-width'),
           'and most-inline-size is most-width')
// Both would also pass if neither did anything, so each must differ
// from the unordered case too.
check(orderedY('bottom', 'bottom, top', 'most-block-size')
      != orderedY('bottom', 'bottom, top', ''),
      'and each of them moves the box at all')

// ---- which of several anchors of one name --------------------------------
// Measured against Chromium: an anchor that comes after the box in tree
// order is not a candidate at all, and of the ones before it the last
// wins. A registry holding one rectangle per name cannot say either --
// the document's last writer is the only answer it has -- so the box
// between two anchors is the row that tells the two rules apart.
//
// Both anchors carry `--a`: one at (20, 20), one at (200, 200), each
// 40x30. The box is 40x30 and asks for `bottom center`, so it lands at
// the anchor's own x and 30 below its top.
Box func treeOrder(where:text) {
    cascadeReset()
    cssViewportWidth = 600
    text near = '<div style="position:absolute;left:20px;top:20px;width:40px;'
        + 'height:30px;anchor-name:--a"></div>'
    text far = '<div style="position:absolute;left:200px;top:200px;width:40px;'
        + 'height:30px;anchor-name:--a"></div>'
    text pos = '<div id="pos" style="position:absolute;position-anchor:--a;'
        + 'width:40px;height:30px;position-area:bottom center"></div>'
    text inner = near + far + pos
    if where == 'between' { inner = near + pos + far }
    if where == 'before' { inner = pos + near + far }
    Node doc = parseHtmlText('<html><body style="margin:0">'
        + '<div style="position:relative;width:400px;height:300px">'
        + inner + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return anchorBoxById(layoutDocument(doc, 600), 'pos')
}

Box tAfter = treeOrder('after')
checkEqInt(tAfter.x, 200, 'with both anchors before it the box takes the last')
checkEqInt(tAfter.y, 230, 'in the other axis too')

Box tBetween = treeOrder('between')
checkEqInt(tBetween.x, 20, 'an anchor after the box is not a candidate')
checkEqInt(tBetween.y, 50, 'so the one before it is what the box resolves to')
check(tBetween.x != tAfter.x, 'and moving the box past an anchor changes the answer')

Box tBefore = treeOrder('before')
checkEqInt(tBefore.x, 0, 'a box before every anchor of its name resolves to none')
checkEqInt(tBefore.y, 0, 'and keeps the position it would have had')

// ---- anchor-scope --------------------------------------------------------
// A scope is a boundary in *both* directions, which is the part a
// reading of "scopes the name to this element's subtree" gets wrong. An
// anchor and a box see each other only when the nearest scope of that
// name enclosing each of them is the same element -- so a box inside a
// scope of `--a` is cut off from every `--a` outside it as well, even
// when the scope holds no anchor of that name at all. That row, `empty
// scope` below, is the one an outward-only implementation passes
// everything else without.
//
// Two anchors of `--a`, one near at (20, 20) and one far at (200, 200),
// each 40x30; the box is 40x30 and asks for `bottom center`, so it
// lands at its anchor's own x and 30 below its top, and at (0, 0) when
// it resolves to no anchor at all.
text ANEAR = '<div style="position:absolute;left:20px;top:20px;width:40px;'
    + 'height:30px;anchor-name:--a"></div>'
text AFAR = '<div style="position:absolute;left:200px;top:200px;width:40px;'
    + 'height:30px;anchor-name:--a"></div>'
text APOS = '<div id="pos" style="position:absolute;position-anchor:--a;'
    + 'width:40px;height:30px;position-area:bottom center"></div>'

Box func scopeCase(inner:text, id:text) {
    cascadeReset()
    cssViewportWidth = 600
    Node doc = parseHtmlText('<html><body style="margin:0">'
        + '<div style="position:relative;width:400px;height:300px">'
        + inner + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return anchorBoxById(layoutDocument(doc, 600), id)
}

int func scopeX(inner:text) { Box b = scopeCase(inner, 'pos')  return b == null ? -1 : b.x }
int func scopeY(inner:text) { Box b = scopeCase(inner, 'pos')  return b == null ? -1 : b.y }

text func scopeOf(names:text, inner:text) {
    return '<div style="anchor-scope:' + names + '">' + inner + '</div>'
}

// The control: no scope anywhere, so the box takes the only anchor.
checkEqInt(scopeX(ANEAR + APOS), 20, 'with no scope the box finds the anchor')
checkEqInt(scopeY(ANEAR + APOS), 50, 'in both axes')

// Outward: a scoped name does not reach a box outside the scope.
checkEqInt(scopeX(scopeOf('--a', ANEAR) + APOS), 0, 'a scoped anchor is hidden from outside')
checkEqInt(scopeY(scopeOf('--a', ANEAR) + APOS), 0, 'so the box keeps its own position')
check(scopeX(scopeOf('--a', ANEAR) + APOS) != scopeX(ANEAR + APOS),
      'which is not where the unscoped page put it')

// Inward: a box inside a scope takes the scope's own anchor over one
// outside it.
checkEqInt(scopeX(AFAR + scopeOf('--a', ANEAR + APOS)), 20,
           'a box inside a scope takes the scoped anchor')
checkEqInt(scopeY(AFAR + scopeOf('--a', ANEAR + APOS)), 50, 'and not the outer one')

// The row that matters: the scope declares `--a` and holds no anchor of
// that name, and the box inside it resolves to nothing rather than
// reaching the `--a` outside.
checkEqInt(scopeX(AFAR + scopeOf('--a', APOS)), 0,
           'an empty scope cuts the box off from an outer anchor too')
checkEqInt(scopeY(AFAR + scopeOf('--a', APOS)), 0, 'in both axes')
check(scopeX(AFAR + scopeOf('--a', APOS)) != scopeX(AFAR + APOS),
      'which is not what the same page without the scope does')

// Nesting: the innermost scope of the name owns it.
checkEqInt(scopeX(scopeOf('--a', AFAR + scopeOf('--a', ANEAR + APOS))), 20,
           'a box in the inner of two scopes takes the inner anchor')
checkEqInt(scopeX(scopeOf('--a', AFAR + scopeOf('--a', ANEAR) + APOS)), 200,
           'and a box in the outer one takes the outer anchor')
checkEqInt(scopeY(scopeOf('--a', AFAR + scopeOf('--a', ANEAR) + APOS)), 230,
           'in both axes')

// `all` scopes every name; `none` is the initial value and scopes none;
// a name the scope does not list is left alone. The last two must agree
// with the unscoped control, which is the only way to tell a keyword
// that does nothing from one that is read and means nothing here.
checkEqInt(scopeX(scopeOf('all', ANEAR) + APOS), 0, 'all hides every name outward')
checkEqInt(scopeX(AFAR + scopeOf('all', APOS)), 0, 'and inward')
checkEqInt(scopeX(scopeOf('none', ANEAR) + APOS), scopeX(ANEAR + APOS),
           'none scopes nothing, so the page reads as if it were absent')
checkEqInt(scopeX(scopeOf('--b', ANEAR) + APOS), scopeX(ANEAR + APOS),
           'and a scope of another name leaves --a alone')
check(scopeX(scopeOf('none', ANEAR) + APOS) != scopeX(scopeOf('all', ANEAR) + APOS),
      'while none and all do not agree with each other')

// A list scopes each of its names.
text BNEAR = '<div style="position:absolute;left:20px;top:20px;width:40px;'
    + 'height:30px;anchor-name:--b"></div>'
text BPOS = '<div id="pos" style="position:absolute;position-anchor:--b;'
    + 'width:40px;height:30px;position-area:bottom center"></div>'
checkEqInt(scopeX(BNEAR + BPOS), 20, 'the --b control finds its anchor')
checkEqInt(scopeX(scopeOf('--a, --b', BNEAR) + BPOS), 0,
           'and a two-name scope covers the second name as well')

// A scope encloses itself, not only its descendants: the element that
// declares both is hidden from outside, and a box that scopes a name is
// cut off from every anchor of it.
text SELFANC = '<div style="position:absolute;left:20px;top:20px;width:40px;'
    + 'height:30px;anchor-name:--a;anchor-scope:--a"></div>'
checkEqInt(scopeX(SELFANC + APOS), 0, 'an element scoping its own name hides itself')
text SELFPOS = '<div id="pos" style="position:absolute;position-anchor:--a;'
    + 'anchor-scope:--a;width:40px;height:30px;position-area:bottom center"></div>'
checkEqInt(scopeX(ANEAR + SELFPOS), 0, 'and a box that scopes the name sees no anchor')

// Two sibling scopes of one name, which is what the property is for:
// each box takes the anchor from its own subtree.
text PAIR = scopeOf('--a', ANEAR + APOS)
    + scopeOf('--a', AFAR + '<div id="two" style="position:absolute;'
      + 'position-anchor:--a;width:40px;height:30px;position-area:bottom center"></div>')
Box pairOne = scopeCase(PAIR, 'pos')
Box pairTwo = scopeCase(PAIR, 'two')
checkEqInt(pairOne.x, 20, 'of two sibling scopes the first box takes its own anchor')
checkEqInt(pairTwo.x, 200, 'and the second takes its own')
check(pairOne.x != pairTwo.x, 'so the two subtrees resolve the one name differently')

// ---- anchor() in an inset property ------------------------------------

// The same fixture, but the argument is declarations rather than a
// `position-area` value, because what is under test here is what an
// inset resolves to.
Box func anchoredBy(decls:text) {
    cascadeReset()
    cssViewportWidth = 600
    Node doc = parseHtmlText('<html><body style="margin:0">'
        + '<div style="position:relative;width:400px;height:300px">'
        + '<div id="anc" style="position:absolute;left:150px;top:100px;'
        + 'width:100px;height:60px;anchor-name:--a"></div>'
        + '<div id="pos" style="position:absolute;position-anchor:--a;'
        + 'width:40px;height:20px;' + decls + '"></div>'
        + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return anchorBoxById(layoutDocument(doc, 600), 'pos')
}

int func insetX(decls:text) { Box b = anchoredBy(decls)  return b == null ? -1 : b.x }
int func insetY(decls:text) { Box b = anchoredBy(decls)  return b == null ? -1 : b.y }

// The same fixture the regions above use: the anchor's border box is
// x 150 to 250 and y 100 to 160, so its centre is 200, 130, and the
// positioned box is 40 by 20.
//
// Every number below comes from Chromium, in todo.md -- but the checks
// that earn their place are the ones that do not: a percentage along
// the anchor must land where the side keyword for that percentage
// lands, which holds without any of the six positions being known.

checkEqInt(insetX('left:anchor(--a left)'), 150,
           'anchor(left) is the anchor\'s left edge')
checkEqInt(insetX('left:anchor(--a right)'), 250, 'and anchor(right) its right')
checkEqInt(insetX('left:anchor(--a center)'), 200, 'and anchor(center) its centre')
checkEqInt(insetY('top:anchor(--a top)'), 100, 'anchor(top) is its top edge')
checkEqInt(insetY('top:anchor(--a bottom)'), 160, 'and anchor(bottom) its bottom')

// An inset on the far side puts the box's own far edge there.
checkEqInt(insetX('right:anchor(--a left)'), 110,
           "a right inset puts the box's right edge on the anchor's left")
checkEqInt(insetY('bottom:anchor(--a top)'), 80,
           "and a bottom inset its bottom edge on the anchor's top")

// The percentage and the keyword are two ways of saying one thing.
checkEqInt(insetX('left:anchor(--a 0%)'), insetX('left:anchor(--a left)'),
           '0% along the anchor is its start side')
checkEqInt(insetX('left:anchor(--a 100%)'), insetX('left:anchor(--a right)'),
           'and 100% its end side')
checkEqInt(insetX('left:anchor(--a 50%)'), insetX('left:anchor(--a center)'),
           'and 50% its centre')
checkEqInt(insetY('top:anchor(--a 100%)'), insetY('top:anchor(--a bottom)'),
           'which holds down the block axis too')
checkEqInt(insetX('left:anchor(--a 25%)'), 175, 'a quarter along is a quarter of 100')

// The logical names are the physical ones here, there being no
// writing-mode to make them anything else.
checkEqInt(insetY('top:anchor(--a start)'), insetY('top:anchor(--a top)'),
           'start on the block axis is the top')
checkEqInt(insetY('top:anchor(--a end)'), insetY('top:anchor(--a bottom)'),
           'and end is the bottom')
checkEqInt(insetX('left:anchor(--a self-start)'), insetX('left:anchor(--a left)'),
           'and self-start on the inline axis is the left')

// Both axes at once, and the name left out.
Box both = anchoredBy('left:anchor(--a right);top:anchor(--a bottom)')
checkEqInt(both.x, 250, 'two insets resolve together, across')
checkEqInt(both.y, 160, 'and down')
checkEqInt(insetX('left:anchor(right)'), 250,
           'a nameless anchor() takes the name position-anchor gave')

// A margin sits between the anchor and the box, on whichever side the
// inset names: the box's *margin* edge goes on the anchor, not its
// border edge. Measured, and it is what an absolutely positioned box
// does with an ordinary inset too.
checkEqInt(insetX('left:anchor(--a right);margin-left:10px'),
           insetX('left:anchor(--a right)') + 10,
           'a left margin pushes the box further from the anchor')
checkEqInt(insetX('right:anchor(--a left);margin-right:10px'),
           insetX('right:anchor(--a left)') - 10,
           'and a right margin pushes it the other way')
checkEqInt(insetY('top:anchor(--a bottom);margin-top:10px'),
           insetY('top:anchor(--a bottom)') + 10,
           'a top margin does the same down the block axis')
checkEqInt(insetY('bottom:anchor(--a top);margin-bottom:10px'),
           insetY('bottom:anchor(--a top)') - 10, 'and a bottom margin')

// The fallback is taken only when the anchor cannot be found.
checkEqInt(insetX('left:anchor(--missing right, 7px)'), 7,
           'a missing anchor falls back to the length beside it')
checkEqInt(insetX('left:anchor(--a right, 7px)'), 250,
           'and an anchor that is found ignores the fallback')
checkEqInt(insetX('left:anchor(--missing right)'),
           insetX(''),
           'with no fallback the declaration has no effect at all')

// ---- anchor-size() ---------------------------------------------------
//
// `anchor-size(<name>? <dimension>, <fallback>?)` gives the anchor's own
// border-box size to an absolutely positioned box. Every number below
// is Chromium 141 on this fixture -- an anchor 100 by 60, and the
// positioned box declared 40 by 20 so that a declaration doing nothing
// reads as 40 or 20 rather than as a plausible answer. todo.md has the
// whole table.
//
// A size cannot wait for the positioning pass the way a placement can:
// the box has to be laid out at that size in the first place, and the
// anchor has no rectangle until the layout it is measured from has
// finished. So this runs on a second layout pass, and what is carried
// between the two is keyed by NODE id -- the box tree is rebuilt and
// the box ids start again.

int func sizeW(decls:text) { Box b = anchoredBy(decls)  return b == null ? -1 : b.w }
int func sizeH(decls:text) { Box b = anchoredBy(decls)  return b == null ? -1 : b.h }

// The control, so that a declaration doing nothing is visible.
checkEqInt(sizeW(''), 40, 'the box is 40 wide with nothing said')
checkEqInt(sizeH(''), 20, 'and 20 tall')

checkEqInt(sizeW('width:anchor-size(--a width)'), 100, "the anchor's width")
checkEqInt(sizeH('height:anchor-size(--a height)'), 60, "and its height")
checkEqInt(sizeH('width:anchor-size(--a width)'), 20,
           'sizing one axis leaves the other alone')

// The logical dimensions are the physical ones here, as the side
// keywords are: there is no `writing-mode` to make them anything else.
checkEqInt(sizeW('width:anchor-size(--a inline)'), 100, '`inline` is the width')
checkEqInt(sizeW('width:anchor-size(--a self-inline)'), 100, 'and `self-inline`')
checkEqInt(sizeH('height:anchor-size(--a block)'), 60, '`block` is the height')
checkEqInt(sizeH('height:anchor-size(--a self-block)'), 60, 'and `self-block`')

// The dimension is the ANCHOR's, not the property's. This is the row
// that does not follow from the name, and it is measured.
checkEqInt(sizeW('width:anchor-size(--a height)'), 60,
           "the anchor's height, asked for by the width")
checkEqInt(sizeH('height:anchor-size(--a width)'), 100,
           "and its width, asked for by the height")

// The name may be left out, and `position-anchor` supplies it. Two ways
// of naming one anchor must give one box.
checkEqInt(sizeW('width:anchor-size(width)'), 100,
           'the name is optional where position-anchor gives one')
checkEqInt(sizeW('width:anchor-size(width)'), sizeW('width:anchor-size(--a width)'),
           'and it is the same anchor either way')

// The fallback is taken only when the anchor cannot be found.
checkEqInt(sizeW('width:anchor-size(--missing width, 5px)'), 5,
           'a missing anchor falls back to the length beside it')
checkEqInt(sizeW('width:anchor-size(--a width, 5px)'), 100,
           'and an anchor that is found ignores the fallback')

// With no fallback and no anchor the answer is ZERO, not the declared
// width -- which is the opposite of `anchor()` in an inset, where the
// same case leaves the box where it was.
checkEqInt(sizeW('width:anchor-size(--missing width)'), 0,
           'a missing anchor with no fallback is zero, not the declared width')
checkEqInt(sizeH('height:anchor-size(--missing height)'), 0, 'and zero tall')

// The minima and maxima take it too.
checkEqInt(sizeW('min-width:anchor-size(--a width)'), 100,
           'a minimum width of the anchor widens the box to it')
checkEqInt(sizeW('max-width:anchor-size(--a width);width:999px'), 100,
           'and a maximum width holds it there')
checkEqInt(sizeH('min-height:anchor-size(--a height)'), 60, 'the same down the block axis')
checkEqInt(sizeH('max-height:anchor-size(--a height);height:999px'), 60, 'and its maximum')

finish('anchor positioning')
