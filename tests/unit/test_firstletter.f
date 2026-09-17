// ::first-letter (CSS2 §5.12.2): the first letter of the first line of
// a block, styled on its own.
//
// Measured in Chromium 141 on a whole document, at 16px monospace where
// a character is 9.6px wide, with `::first-letter { font-size: 32px }`
// so the selected characters are 19.2px each and the width says which
// ones were chosen:
//
//   <span>Hello</span>              48px   five 16px characters
//   ::first-letter 32px             58px   one 32px + four 16px
//   "Hello                          77px   TWO 32px + four 16px
//                                          -- leading punctuation joins the letter
//   (three spaces)Hello             58px   leading whitespace is skipped
//   <em>H</em>ello                  58px   a nested inline still yields it
//
// The width is the assertion. The line height Chromium produces for an
// enlarged first letter (26px against a 20px line-height) depends on
// font metrics this engine does not have (FINDINGS.md, "no font metrics
// beyond an inked height"), so it is not asserted here.
import ../../src/browser/page.f
import ../assert.f

int func spanWidth(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'span', all)
    for int i = 0, i < all.length, i++ {
        Box b = all[i]
        // An inline-block leaves two boxes for the one element; the
        // first carries the width.
        if b.node != null && getAttr(b.node, 'id') == id && b.w > 0 { return b.w }
    }
    return 0
}

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:600px">'
text sheet = '<style>span { display:inline-block } .big::first-letter { font-size:32px }</style>'

// ---- the control: no first-letter rule --------------------------------
Page p0 = pageFromHtml(head + sheet + '<span id="a">Hello</span></body>', 'about:blank', 600)
int plain = spanWidth(p0.root, 'a')
check(plain >= 45 && plain <= 51, `five 16px characters are about 48px, got ${plain}`)

// ---- one enlarged letter ----------------------------------------------
Page p1 = pageFromHtml(head + sheet + '<span id="a" class="big">Hello</span></body>', 'about:blank', 600)
int big = spanWidth(p1.root, 'a')
check(big > plain, `an enlarged first letter widens the box: ${big} vs ${plain}`)
check(big >= 54 && big <= 62, `one 32px plus four 16px is about 58px, got ${big}`)

// ---- leading punctuation goes with the letter -------------------------
Page p2 = pageFromHtml(head + sheet + '<span id="a" class="big">"Hello</span></body>', 'about:blank', 600)
int quoted = spanWidth(p2.root, 'a')
check(quoted >= 73 && quoted <= 81, `two 32px plus four 16px is about 77px, got ${quoted}`)
check(quoted > big, 'the quote mark is enlarged along with the letter')

// ---- leading whitespace is skipped ------------------------------------
Page p3 = pageFromHtml(head + sheet + '<span id="a" class="big">   Hello</span></body>', 'about:blank', 600)
int spaced = spanWidth(p3.root, 'a')
check(spaced >= 54 && spaced <= 62, `leading spaces do not take the styling, got ${spaced}`)

// ---- a nested inline still yields the first letter --------------------
Page p4 = pageFromHtml(head + sheet + '<span id="a" class="big"><em>H</em>ello</span></body>', 'about:blank', 600)
int nested = spanWidth(p4.root, 'a')
check(nested >= 54 && nested <= 62, `the letter inside an em is still the first, got ${nested}`)

// ---- only the first letter, not the first of every child --------------
// Asserted as a relation rather than a width: the same markup with and
// without the rule differs by exactly one character growing from 16px
// to 32px, whatever this engine's font metrics make that character.
// Chromium 141 measures the pair at 77px and 87px.
Page p5a = pageFromHtml(head + '<style>span { display:inline-block }</style>'
    + '<span id="a">Hello<em>World</em></span></body>', 'about:blank', 600)
Page p5b = pageFromHtml(head + sheet
    + '<span id="a" class="big">Hello<em>World</em></span></body>', 'about:blank', 600)
int without = spanWidth(p5a.root, 'a')
int with = spanWidth(p5b.root, 'a')
int grew = with - without
check(without > 0, `the control has a width, got ${without}`)
check(grew >= 8 && grew <= 12, `exactly one character grew by one 16px width, got ${grew}`)

// ---- a rule with no first-letter selector changes nothing -------------
Page p6 = pageFromHtml(head + '<style>span { display:inline-block }</style><span id="a">Hello</span></body>', 'about:blank', 600)
checkEqInt(spanWidth(p6.root, 'a'), plain, 'a page with no ::first-letter rule is unchanged')

finish('first letter')
