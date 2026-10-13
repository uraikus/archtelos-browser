// CSS Inline 3: `text-box-trim` and `text-box-edge`.
//
// A line box is taller than the text in it by the leading, half above
// and half below. `text-box-trim` says which of those halves to drop,
// and `text-box-edge` says which two of the font's edges the remaining
// height runs between.
//
// Every number here is Chromium 141's, read off a 20px block with
// line-height 2 holding "Hxy", by the block's own height:
//
//   none 40    trim-both 24    trim-start 32    trim-end 32
//   cap alphabetic 14    ex alphabetic 11    text alphabetic 19
//   cap text 19          ex text 16
//
// They are one set of four metrics -- ascent 19, descent 5, cap height
// 14, x-height 11 -- and they cross-check: cap..text is 14 + 5, ex..text
// is 11 + 5, text..text is 19 + 5. The checks below assert that
// arithmetic as well as the numbers, because a table of nine constants
// can be wrong in a way that a relation between them cannot.
//
// This is layout, not paint: the property changes how tall the block
// is, so the test asks the box.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func tbFind(b:Box, tag:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null && b.node.tag == tag { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = tbFind(b.children[i], tag)
        if f != null { return f }
    }
    return null
}

// The height of a 20px/2 block carrying the declaration under test.
int func boxHeight(decl:text) {
    cascadeReset()
    cssViewportWidth = 400
    Node doc = parseHtmlText('<html><body style="margin:0">'
        + '<div id="t" style="font-family:monospace;font-size:20px;line-height:2;'
        + decl + '">Hxy</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box d = tbFind(layoutDocument(doc, 400), 'div')
    return d == null ? -1 : d.h
}

// ---- the control -----------------------------------------------------
// Without a trim the block is the whole line box, and every row below
// has to differ from it or it is measuring nothing.
checkEqInt(boxHeight(''), 40, 'an untrimmed 20px/2 line box is 40 tall')

// ---- text-box-trim ---------------------------------------------------
checkEqInt(boxHeight('text-box-trim:trim-both'), 24, 'trim-both leaves ascent plus descent')
checkEqInt(boxHeight('text-box-trim:trim-start'), 32, 'trim-start drops the half above')
checkEqInt(boxHeight('text-box-trim:trim-end'), 32, 'trim-end drops the half below')
checkEqInt(boxHeight('text-box-trim:none'), 40, 'none is the initial value')

// The two halves must add up to the whole: what trim-both removes is
// what trim-start and trim-end remove between them. That relation holds
// whatever the leading is, which a check against 24 alone does not say.
int tbWhole = boxHeight('')
int tbBoth = boxHeight('text-box-trim:trim-both')
int tbStart = boxHeight('text-box-trim:trim-start')
int tbEnd = boxHeight('text-box-trim:trim-end')
checkEqInt(tbWhole - tbStart + (tbWhole - tbEnd), tbWhole - tbBoth,
           'the two halves of the leading add up to the whole of it')

// `trim-both` removes all the leading rather than a fixed amount, so
// the answer does not depend on the line height at all -- which is the
// row that tells the two readings apart.
checkEqInt(boxHeight('line-height:1;text-box-trim:trim-both'), 24,
           'trim-both at line-height 1 is the same height')
checkEqInt(boxHeight('line-height:3;text-box-trim:trim-both'), 24,
           'and at line-height 3')
check(boxHeight('line-height:1') != boxHeight('line-height:3'),
      'though the untrimmed heights differ')

// ---- text-box-edge ---------------------------------------------------
text tbT = 'text-box-trim:trim-both;text-box-edge:'
checkEqInt(boxHeight(tbT + 'text'), 24, 'text to text is ascent plus descent')
checkEqInt(boxHeight(tbT + 'cap alphabetic'), 14, 'cap to the baseline is the cap height')
checkEqInt(boxHeight(tbT + 'ex alphabetic'), 11, 'ex to the baseline is the x-height')
checkEqInt(boxHeight(tbT + 'text alphabetic'), 19, 'text to the baseline is the ascent')
checkEqInt(boxHeight(tbT + 'cap text'), 19, 'cap to text adds the descent')
checkEqInt(boxHeight(tbT + 'ex text'), 16, 'ex to text adds it too')

// The descent implied by each pair must be the same descent. This is
// the check that does not depend on any of the nine numbers being known
// in advance: two different over-edges must disagree by nothing.
checkEqInt(boxHeight(tbT + 'cap text') - boxHeight(tbT + 'cap alphabetic'),
           boxHeight(tbT + 'ex text') - boxHeight(tbT + 'ex alphabetic'),
           'the descent is the same whichever over-edge measures it')
checkEqInt(boxHeight(tbT + 'text text') - boxHeight(tbT + 'text alphabetic'),
           boxHeight(tbT + 'cap text') - boxHeight(tbT + 'cap alphabetic'),
           'and the same again from the text edge')

// `auto` is `text`, and a single keyword is not a value at all: Chromium
// computes `cap` alone back to `auto`, so it must not trim to the cap
// height.
checkEqInt(boxHeight(tbT + 'auto'), boxHeight(tbT + 'text'), 'auto is text')
checkEqInt(boxHeight(tbT + 'cap'), boxHeight(tbT + 'text'),
           'a lone `cap` is rejected and leaves auto')
checkEqInt(boxHeight(tbT + 'ex'), boxHeight(tbT + 'text'), 'and a lone `ex`')

// An edge without a trim changes nothing: the property says where the
// trimmed height runs to, not that there is one.
checkEqInt(boxHeight('text-box-edge:cap alphabetic'), 40,
           'an edge with no trim leaves the line box alone')

// ---- the shorthand ---------------------------------------------------
// Two ways of saying one thing must land on the same height.
checkEqInt(boxHeight('text-box:trim-both cap alphabetic'),
           boxHeight('text-box-trim:trim-both;text-box-edge:cap alphabetic'),
           'the text-box shorthand is its two longhands')
checkEqInt(boxHeight('text-box:trim-both'), boxHeight('text-box-trim:trim-both'),
           'and with the edge left out')

finish('text box')
