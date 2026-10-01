// CSS Scrollbars 1, and `scrollbar-gutter` from CSS Overflow 4.
//
// A scroll container's bar takes its room from the content, so how wide
// the bar is decides how wide the content box is. That makes every
// number here readable off the box tree: `sbW` and `sbH` are the room
// the two bars took, and Chromium reports the same thing as the
// difference between `offsetWidth` and `clientWidth`.
//
// Every expectation is Chromium 141's, read off these same declarations
// on a 200x100 `overflow: scroll` box whose content is 400x400:
//
//   default            clientWidth 185  clientHeight 85
//   scrollbar-width: thin     190              90
//   scrollbar-width: none     200             100
//   scrollbar-width: auto     185              85
//
// -- so `thin` is ten pixels, `none` is none at all, and `auto` is the
// fifteen this engine already reserved.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Node func sbNodeById(n:Node, id:text) {
    if n.kind == NODE_ELEMENT && attrOf(n.id, 'id') == id { return n }
    for int i = 0, i < n.children.length, i++ {
        Node f = sbNodeById(n.children[i], id)
        if f != null { return f }
    }
    return null
}

Box func sbBoxById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = sbBoxById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

// A 200x100 box of the given declarations, holding content 400x400.
Box func scrollBox(decl:text, inner:text) {
    cascadeReset()
    cssViewportWidth = 600
    Node doc = parseHtmlText('<html><body style="margin:0"><div id="s" style="width:200px;'
        + 'height:100px;overflow:scroll;' + decl + '">' + inner + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box root = layoutDocument(doc, 600)
    return sbBoxById(root, 's')
}

text BIG = '<div style="width:400px;height:400px"></div>'

// ---- scrollbar-width ---------------------------------------------------
Box b0 = scrollBox('', BIG)
checkEqInt(b0.sbW, 15, 'a scroll container reserves fifteen pixels across')
checkEqInt(b0.sbH, 15, 'and fifteen down')

Box thin = scrollBox('scrollbar-width:thin', BIG)
checkEqInt(thin.sbW, 10, 'scrollbar-width: thin is ten across')
checkEqInt(thin.sbH, 10, 'and ten down')

Box none = scrollBox('scrollbar-width:none', BIG)
checkEqInt(none.sbW, 0, 'scrollbar-width: none reserves nothing across')
checkEqInt(none.sbH, 0, 'and nothing down')

Box auto = scrollBox('scrollbar-width:auto', BIG)
checkEqInt(auto.sbW, 15, 'scrollbar-width: auto is the fifteen it always was')
checkEqInt(auto.sbH, 15, 'on both axes')

// The three values have to differ from each other, or a reader that
// answered fifteen to everything would pass two of the checks above.
check(thin.sbW != b0.sbW, 'thin is not the default')
check(none.sbW != thin.sbW, 'and none is not thin')

// **A bar with no width is still a scroll container.** `none` hides the
// bar; it does not stop the box scrolling, and a check that only
// counted pixels would not tell the two apart.
checkEqInt(boxScrollLeftRange(none), 200, 'a box with no bar still scrolls across')
check(boxScrollRange(none) > 0, 'and still scrolls down')

// ---- scrollbar-gutter --------------------------------------------------
// `stable` reserves the inline-end gutter even where nothing overflows,
// so a box that would show no bar still has a narrower content box.
// Chromium answers `overflow: auto` with a 10x10 child: clientWidth 200
// without it and 185 with, and clientHeight 100 either way -- the gutter
// is the inline axis's, and the block axis keeps nothing.
text SMALL = '<div style="width:10px;height:10px"></div>'

Box loose = scrollBox('overflow:auto', SMALL)
checkEqInt(loose.sbW, 0, 'nothing overflowing reserves nothing')
checkEqInt(loose.sbH, 0, 'on either axis')

Box stable = scrollBox('overflow:auto;scrollbar-gutter:stable', SMALL)
checkEqInt(stable.sbW, 15, 'a stable gutter is reserved anyway')
checkEqInt(stable.sbH, 0, 'and only on the inline axis')

// The gutter is the bar's own width, so a thin bar leaves a thin gutter.
Box thinGutter = scrollBox('overflow:auto;scrollbar-gutter:stable;scrollbar-width:thin', SMALL)
checkEqInt(thinGutter.sbW, 10, 'a stable gutter is as wide as the bar would be')

// `none` leaves nothing to reserve, so a gutter for it is no gutter.
Box noneGutter = scrollBox('overflow:auto;scrollbar-gutter:stable;scrollbar-width:none', SMALL)
checkEqInt(noneGutter.sbW, 0, 'and a bar of no width leaves no gutter')

// `both-edges` reserves the gutter on the other inline side as well, so
// a 200px box keeps 170 of it rather than 185. Chromium says so, and it
// is the one value of the three that moves the content's left edge --
// nothing else in this engine insets a box from the left, which is what
// made it worth a field of its own rather than a wider `sbW`.
Box both = scrollBox('overflow:auto;scrollbar-gutter:stable both-edges', SMALL)
checkEqInt(both.sbW, 15, 'both-edges keeps the inline-end gutter')
checkEqInt(both.sbLeft, 15, 'and reserves the inline-start one too')
checkEqInt(both.w - both.sbW - both.sbLeft, 170, 'leaving 170 of the 200')
check(both.sbLeft != stable.sbLeft, 'which stable alone does not do')
checkEqInt(stable.sbLeft, 0, 'stable reserves nothing on the near side')

// The content starts after the gutter, which is the whole point of
// reserving it: a child's left edge moves by exactly the gutter's width.
Box bothInner = both.children[0]
Box stableInner = stable.children[0]
checkEqInt(bothInner.x - stableInner.x, 15, 'and the content begins after it')

// A thin bar leaves two thin gutters, so the pair follows the width
// rather than being fifteen twice.
Box bothThin = scrollBox('overflow:auto;scrollbar-gutter:stable both-edges;scrollbar-width:thin', SMALL)
checkEqInt(bothThin.sbLeft, 10, 'a thin bar leaves a thin near gutter')
checkEqInt(bothThin.sbW, 10, 'and a thin far one')

// A box that is not a scroll container at all has no gutter to be
// stable about, which is what keeps the property off every other box.
cascadeReset()
cssViewportWidth = 600
Node plainDoc = parseHtmlText('<html><body style="margin:0"><div id="s" style="width:200px;'
    + 'height:100px;scrollbar-gutter:stable">' + SMALL + '</div></body></html>')
cascadeAddDocumentStyles(plainDoc)
computeStyles(plainDoc)
Box plain = sbBoxById(layoutDocument(plainDoc, 600), 's')
checkEqInt(plain.sbW, 0, 'a box that does not scroll reserves no gutter')

// ---- the computed values -----------------------------------------------
// `scrollbar-color` inherits and the other two do not, which is what
// Chromium 141 answers: a child of an element declaring all three
// reports the colours and `auto` for the width and the gutter. The
// standard makes `scrollbar-width` inherited too; this follows the
// browser it is measured against, and says so.
Style func sbStyleOf(decl:text, id:text) {
    cascadeReset()
    cssViewportWidth = 600
    Node doc = parseHtmlText('<html><body><div id="p" style="' + decl
        + '"><div id="c">x</div></div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return sbNodeById(doc, id).style
}

text ALL3 = 'scrollbar-width:thin;scrollbar-color:red blue;scrollbar-gutter:stable'
checkEqInt(sbStyleOf(ALL3, 'p').scrollbarWidth, SCROLLBAR_THIN, 'the parent is thin')
checkEqInt(sbStyleOf(ALL3, 'c').scrollbarWidth, SCROLLBAR_AUTO,
           'and the child is auto, because the width does not inherit')
checkEqInt(sbStyleOf(ALL3, 'p').scrollbarGutter, SCROLLBAR_GUTTER_STABLE, 'the parent is stable')
checkEqInt(sbStyleOf(ALL3, 'c').scrollbarGutter, SCROLLBAR_GUTTER_AUTO,
           'and the child is auto, because the gutter does not inherit either')
checkEqInt(sbStyleOf(ALL3, 'p').scrollbarThumb, packColor(255, 0, 0, 255), 'the thumb is the first colour')
checkEqInt(sbStyleOf(ALL3, 'p').scrollbarTrack, packColor(0, 0, 255, 255), 'and the track the second')
checkEqInt(sbStyleOf(ALL3, 'c').scrollbarThumb, packColor(255, 0, 0, 255),
           'both of which the child inherits, because the colour does')
checkEqInt(sbStyleOf(ALL3, 'c').scrollbarTrack, packColor(0, 0, 255, 255), 'track included')

// `auto` is no declared colour at all, which is how the painter knows
// to use its own.
checkEqInt(sbStyleOf('scrollbar-color:auto', 'p').scrollbarThumb, 0,
           'scrollbar-color: auto declares no thumb colour')
checkEqInt(sbStyleOf('', 'p').scrollbarThumb, 0, 'and neither does saying nothing')

// One colour is not two, so the declaration is dropped whole rather
// than half-applied.
checkEqInt(sbStyleOf('scrollbar-color:red', 'p').scrollbarThumb, 0,
           'a single colour is not a scrollbar-color')

finish('scrollbars')
