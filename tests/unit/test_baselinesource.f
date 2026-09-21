// `baseline-source` (CSS Inline 3 §5.1).
//
// Which of an atomic inline's baselines the line it sits on aligns to.
// What the declaration moves is the SIBLING, not the declaring element:
// Chromium's inline-block keeps its top at 0 and its height at 40 under
// every value, while the span beside it moves between 0 and 20.
//
// `auto` is not one answer. An inline-block's `auto` baseline is its
// LAST line and an inline-flex's is its FIRST, so `first` on an
// inline-block and `last` on an inline-flex are the two rows that do
// anything. todo.md has Chromium's table.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func bsBoxById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = bsBoxById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

// A two-line atomic inline 60px wide beside a one-line span, in a 400px
// block at a line height of 20. `disp` is the atomic inline's display.
Box func bsLaid(disp:text, decls:text) {
    cascadeReset()
    cssViewportWidth = 600
    Node doc = parseHtmlText('<html><body style="margin:0;font-size:16px">'
        + '<div id="cb" style="width:400px;line-height:20px">'
        + '<span id="ib" style="display:' + disp + ';width:60px;' + decls + '">A<br>B</span>'
        + '<span id="s">X</span>'
        + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, 600)
}

// Where a box's text actually landed. A laid-out inline's position is
// on the FRAGMENT the line holds, not on the box: the span's own box
// is zero tall at zero under every value, and so is the text box
// beneath it, so a check reading either would register nothing
// whatever the property did. That instrument was written first and
// failed its own test, answering 0 for all seven rows.
// Matched by box ID rather than by reference: two `Box` values compare
// with `==` only if the compiler will emit it, and it will not -- the
// LLVM backend rejects `fb == target` on struct references with
// "defined with type 'ptr' but expected 'i64'". Every box carries an
// id, so the id is what identifies one.
int func bsFragTopOfId(cb:Box, boxId:int) {
    for int li = 0, li < cb.lines.length, li++ {
        for int fi = 0, fi < cb.lines[li].frags.length, fi++ {
            Box fb = cb.lines[li].frags[fi].box
            if fb != null && fb.id == boxId { return cb.lines[li].frags[fi].y }
        }
    }
    return -1
}

int func bsFragTop(cb:Box, target:Box) {
    int own = bsFragTopOfId(cb, target.id)
    if own >= 0 { return own }
    for int ci = 0, ci < target.children.length, ci++ {
        int y = bsFragTopOfId(cb, target.children[ci].id)
        if y >= 0 { return y }
    }
    return -1
}

// The sibling span's text, relative to the containing block: the number
// the property actually moves.
int func bsSpanTop(disp:text, decls:text) {
    Box root = bsLaid(disp, decls)
    Box cb = bsBoxById(root, 'cb')
    Box sp = bsBoxById(root, 's')
    if cb == null || sp == null { return -1 }
    int y = bsFragTop(cb, sp)
    return y < 0 ? -1 : y - cb.y
}

int func bsOwnTop(disp:text, decls:text) {
    Box root = bsLaid(disp, decls)
    Box cb = bsBoxById(root, 'cb')
    Box ib = bsBoxById(root, 'ib')
    if cb == null || ib == null { return -1 }
    return ib.y - cb.y
}

int func bsOwnHeight(disp:text, decls:text) {
    Box root = bsLaid(disp, decls)
    Box ib = bsBoxById(root, 'ib')
    return ib == null ? -1 : ib.h
}

// ---- the default, which differs by display type ---------------------
checkEqInt(bsSpanTop('inline-block', ''), 20,
           'an inline-block aligns on its LAST line, so the span drops to the second')
checkEqInt(bsSpanTop('inline-block', 'baseline-source:auto'), 20,
           'which is what `auto` means there')
// The inline-flex half of Chromium's table is NOT reproduced here, and
// deliberately so: this engine lays a `display: inline-flex` span
// holding `A<br>B` out at ZERO height where Chromium gives 40, so a
// check against it would agree with Chromium's "span at 0" for a
// reason that has nothing to do with this property. That is its own
// finding and todo.md records it with the numbers.

// ---- the keyword overriding it --------------------------------------
checkEqInt(bsSpanTop('inline-block', 'baseline-source:first'), 0,
           '`first` takes the first line instead')
checkEqInt(bsSpanTop('inline-block', 'baseline-source:last'), 20,
           'and `last` is what it already did')

// ---- the checks that need no number of their own --------------------
// `auto` is a default rather than a value, so it must land exactly
// where the keyword naming that default lands.
checkEqInt(bsSpanTop('inline-block', 'baseline-source:auto'),
           bsSpanTop('inline-block', 'baseline-source:last'),
           'auto on an inline-block is last, written out')
// And the two keywords must DISAGREE, which is what says the property
// is read at all: a declaration that fell through to the default would
// make these equal and every check above pass but this one.
check(bsSpanTop('inline-block', 'baseline-source:first')
      != bsSpanTop('inline-block', 'baseline-source:last'),
      'the two keywords do not answer the same')
// The distance between them is the line height, because the two
// baselines are one line apart -- which holds at any line height and
// needs neither number.
checkEqInt(bsSpanTop('inline-block', 'baseline-source:last')
           - bsSpanTop('inline-block', 'baseline-source:first'),
           20, 'and they are exactly one line apart')

// ---- what it does not touch -----------------------------------------
// Measured: the declaring element's own box does not move under any
// value, so a test that read IT would register nothing at all.
checkEqInt(bsOwnTop('inline-block', 'baseline-source:first'), bsOwnTop('inline-block', ''),
           'the declaring element does not move')
checkEqInt(bsOwnHeight('inline-block', 'baseline-source:first'),
           bsOwnHeight('inline-block', ''),
           'nor change height')
// And the fixture is what it claims to be: two lines of twenty, so a
// baseline taken from the wrong one is twenty pixels visible rather
// than a rounding.
checkEqInt(bsOwnHeight('inline-block', ''), 40, 'the atomic inline really is two lines tall')
checkEqInt(bsOwnHeight('inline-block', 'baseline-source:first'), 40, 'under either keyword')

// An invalid value leaves the default in force.
checkEqInt(bsSpanTop('inline-block', 'baseline-source:banana'), 20,
           'an unknown keyword is ignored')

finish('baseline source')
