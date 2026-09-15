// open-quote and close-quote with the `quotes` property (CSS2 §12.3.2).
//
// The quote depth is a running count over the whole document in
// document order, not a measure of element nesting: an element deep
// inside three containers is at depth 0 until something has actually
// emitted an open-quote. Past the end of the list every deeper level
// repeats the last pair.
//
// Confirmed against Chromium 141 by measuring the width an
// inline-block span gains from its generated content at 16px monospace,
// with `quotes: 'AA' 'BBBB' 'CCC' 'DDDDD'` so that every level's string
// has a length nothing else shares. A bare "x" is 10px wide:
//
//   depth 0, open-quote       29px   2 chars   AA
//   depth 1, open-quote       39px   3 chars   CCC
//   past the list, open       39px   3 chars   CCC      (the last pair repeats)
//   past the list, close      58px   5 chars   DDDDD
//   open-quote close-quote    87px   8 chars   CCC + DDDDD
//
// This asserts the generated text, which the box tree carries, with
// those widths as the corroboration that the text is right.
import ../../src/browser/page.f
import ../assert.f

text func generatedBefore(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'span', all)
    for int i = 0, i < all.length, i++ {
        Box b = all[i]
        if b.node == null || getAttr(b.node, 'id') != id { continue }
        if b.children.length == 0 { return null }
        Box first = b.children[0]
        if first.children.length == 0 { return '' }
        return first.children[0].content
    }
    return null
}

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:600px">'
text sheet = '<style>'
    + '.q { quotes: "AA" "BBBB" "CCC" "DDDDD" }'
    + 'span { display:inline-block }'
    + '.o::before { content: open-quote }'
    + '.c::before { content: close-quote }'
    + '.oc::before { content: open-quote close-quote }'
    + '.noo::before { content: no-open-quote }'
    + '.noc::before { content: no-close-quote }'
    + '</style>'

// ---- the first open-quote takes the first pair ----------------------
Page p1 = pageFromHtml(head + sheet
    + '<div class="q"><span class="o" id="a">x</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p1.root, 'a'), 'AA', 'the first open-quote is the first string')

// ---- an unclosed quote deepens the level for what follows -----------
Page p2 = pageFromHtml(head + sheet
    + '<div class="q"><span class="o" id="a">x</span>'
    + '<div class="q"><span class="o" id="b">x</span></div></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p2.root, 'a'), 'AA', 'the first is still the first pair')
checkEq(generatedBefore(p2.root, 'b'), 'CCC', 'the next open-quote has gone a level deeper')

// ---- nesting alone does not deepen anything -------------------------
Page p3 = pageFromHtml(head + sheet
    + '<div class="q"><div class="q"><div class="q">'
    + '<span class="o" id="a">x</span></div></div></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p3.root, 'a'), 'AA', 'three containers deep is still depth zero')

// ---- past the end of the list the last pair repeats ------------------
Page p4 = pageFromHtml(head + sheet
    + '<div class="q"><span class="o" id="a">x</span><span class="o" id="b">x</span>'
    + '<span class="o" id="c">x</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p4.root, 'a'), 'AA', 'level one')
checkEq(generatedBefore(p4.root, 'b'), 'CCC', 'level two')
checkEq(generatedBefore(p4.root, 'c'), 'CCC', 'and level three repeats the last pair')

// ---- close-quote comes back up --------------------------------------
Page p5 = pageFromHtml(head + sheet
    + '<div class="q"><span class="o" id="a">x</span><span class="c" id="b">x</span>'
    + '<span class="o" id="c">x</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p5.root, 'a'), 'AA', 'open at level one')
checkEq(generatedBefore(p5.root, 'b'), 'BBBB', 'close comes back to the same level')
checkEq(generatedBefore(p5.root, 'c'), 'AA', 'so the next open is level one again')

// ---- both in one value ----------------------------------------------
Page p6 = pageFromHtml(head + sheet
    + '<div class="q"><span class="oc" id="a">x</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p6.root, 'a'), 'AABBBB', 'open and close together balance out')

// ---- the no- forms move the level without printing ------------------
Page p7 = pageFromHtml(head + sheet
    + '<div class="q"><span class="noo" id="a">x</span><span class="c" id="b">x</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p7.root, 'a'), '', 'no-open-quote prints nothing')
checkEq(generatedBefore(p7.root, 'b'), 'BBBB', 'but still went a level deeper')

// ---- a close at level zero prints nothing and stays there ------------
Page p8 = pageFromHtml(head + sheet
    + '<div class="q"><span class="c" id="a">x</span><span class="o" id="b">x</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p8.root, 'a'), '', 'closing what was never opened prints nothing')
checkEq(generatedBefore(p8.root, 'b'), 'AA', 'and the level does not go negative')

// ---- without a quotes property there is nothing to print -------------
Page p9 = pageFromHtml(head
    + '<style>span { display:inline-block } .o::before { content: open-quote }</style>'
    + '<div><span class="o" id="a">x</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p9.root, 'a'), '', 'an element with no quotes list generates nothing')

// ---- the width corroborates the text ---------------------------------
// A bare "x" is 10px; Chromium makes the depth-0 open-quote span 29px.
Page pw = pageFromHtml(head + sheet
    + '<div class="q"><span class="o" id="a">x</span></div></body>', 'about:blank', 600)
arr[Box] quoteSpans = []
collectBoxesForTag(pw.root, 'span', quoteSpans)
int quoteSpanW = 0
// An inline-block leaves two boxes for the one element -- the block
// that carries the width, and an inline wrapper that does not -- so
// this takes the first rather than the last.
for int i = 0, i < quoteSpans.length, i++ {
    Box sp = quoteSpans[i]
    if sp.node != null && getAttr(sp.node, 'id') == 'a' && quoteSpanW == 0 { quoteSpanW = sp.w }
}
check(quoteSpanW >= 26 && quoteSpanW <= 32, `an AA plus x span is about 29px wide, got ${quoteSpanW}`)

// ---- <q> gets its quotes from the user-agent stylesheet --------------
// Chromium renders `<q>x</q>` two characters wider than a bare "x": one
// opening and one closing quote. The quote characters themselves are
// locale-dependent and this engine uses the ASCII pair.
Page pq = pageFromHtml(head + '<style>span { display:inline-block }</style>'
    + '<span id="plain">x</span><span id="quoted"><q>x</q></span></body>', 'about:blank', 600)
arr[Box] qspans = []
collectBoxesForTag(pq.root, 'span', qspans)
int plainW = 0
int quotedW = 0
for int i = 0, i < qspans.length, i++ {
    Box sp = qspans[i]
    if sp.node == null { continue }
    text sid = getAttr(sp.node, 'id')
    if sid == 'plain' && plainW == 0 { plainW = sp.w }
    if sid == 'quoted' && quotedW == 0 { quotedW = sp.w }
}
check(plainW > 0, `the bare span has a width, got ${plainW}`)
check(quotedW > plainW, `a q renders wider than its text alone: ${quotedW} vs ${plainW}`)
int added = quotedW - plainW
check(added >= 16 && added <= 24, `a q adds two characters, about 19px; got ${added}`)

finish('quotes')
