// Pseudo-elements: ::before and ::after, and the `content` they carry
// (Selectors 3 §7, CSS2 §12.1-12.2).
//
// Chromium's own numbers for this markup, at 16px monospace:
//
//   span, no pseudo          w 19      "ab"
//   span, ::before "XY"      w 39      "XYab"
//   span, ::after  "ZW"      w 39      "abZW"
//   span, ::before attr      w 48      "TAGab"
//   span, ::before ""        w 19      unchanged
//   p,    ::before block     h 40      an extra line
//   p,    no pseudo          h 20
//
// The spans are `display: inline-block` so that they have a width to
// measure. A purely inline box has none here -- its extent lives in the
// line fragments rather than on the box -- so the last check below goes
// to the fragments for the inline case.
//
// The checks below are written as relations between those rather than
// as absolute pixel counts, because this engine's font metrics differ
// from Chromium's by a pixel every few characters and the relations are
// what the feature actually promises.
import ../../src/browser/page.f
import ../assert.f

Box func spanById(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'span', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

Box func pById(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'p', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:400px">'
text styles = '<style>'
    + '#s1::before { content: "XY" }'
    + '#s2::after { content: "ZW" }'
    + '#s3::before { content: attr(data-tag) }'
    + '#s4::before { content: "" }'
    + '#s5:before { content: "XY" }'
    + '#p1::before { content: "B"; display: block }'
    + '</style>'
text ib = ' style="display:inline-block"'
text spans = `<div><span${ib} id="s0">ab</span></div>`
    + `<div><span${ib} id="s1">ab</span></div>`
    + `<div><span${ib} id="s2">ab</span></div>`
    + `<div><span${ib} id="s3" data-tag="TAG">ab</span></div>`
    + `<div><span${ib} id="s4">ab</span></div>`
    + `<div><span${ib} id="s5">ab</span></div>`
    + '<p id="p1">six</p><p id="p0">six</p>'

Page p = pageFromHtml(head + styles + spans + '</body>', 'about:blank', 400)
Box s0 = spanById(p.root, 's0')
Box s1 = spanById(p.root, 's1')
Box s2 = spanById(p.root, 's2')
Box s3 = spanById(p.root, 's3')
Box s4 = spanById(p.root, 's4')
Box s5 = spanById(p.root, 's5')

check(s0 != null && s1 != null, 'the spans are in the box tree')
check(s1.w > s0.w, '::before with content makes the element wider')
check(s2.w > s0.w, 'and so does ::after')
checkEqInt(s1.w, s2.w, 'by the same amount for two characters either side')
checkEqInt(s4.w, s0.w, 'content: "" adds nothing')
check(s3.w > s1.w, 'attr() content of three characters is wider than two')

// "XY" is two characters and "TAG" three, so the widths they add are in
// the ratio 2:3 whatever the font is.
checkEqInt((s1.w - s0.w) * 3, (s3.w - s0.w) * 2, 'the added widths are two characters against three')

// The one-colon spelling is the legacy form of the same thing.
checkEqInt(s5.w, s1.w, ':before means what ::before means')

// A block-level ::before puts the generated content on its own line,
// so the paragraph is two lines tall instead of one.
Box p1 = pById(p.root, 'p1')
Box p0 = pById(p.root, 'p0')
check(p1 != null && p0 != null, 'the paragraphs are in the box tree')
checkEqInt(p1.h, p0.h * 2, 'a block ::before adds a line')

// A pseudo-element styles itself, not its originating element.
Page p2 = pageFromHtml(head + '<style>#q::before { content: "Q"; color: #ff0000 }</style>'
    + `<div><span${ib} id="q">ab</span></div></body>`, 'about:blank', 400)
Box q = spanById(p2.root, 'q')
checkEqInt(q.style.color, packColor(0, 0, 0, 255), 'the element keeps its own colour')
check(q.children.length > 0, 'and the generated content is a child box')

// No rule, no pseudo-element: nothing is generated and nothing changes.
Page p3 = pageFromHtml(head + `<div><span${ib} id="n">ab</span></div></body>`, 'about:blank', 400)
checkEqInt(spanById(p3.root, 'n').w, s0.w, 'an element with no ::before rule is untouched')

// `content` is what generates the box: a rule that sets only a colour
// generates nothing at all (CSS2 §12.1).
Page p4 = pageFromHtml(head + '<style>#m::before { color: #ff0000 }</style>'
    + `<div><span${ib} id="m">ab</span></div></body>`, 'about:blank', 400)
checkEqInt(spanById(p4.root, 'm').w, s0.w, 'no content means no box')

// ---- a purely inline ::before ----------------------------------------
// An inline box has no width of its own here, so this asks the question
// the width was standing in for: the element's own text starts further
// along the line when a ::before is generated before it. Chromium puts
// "ab" at x=19 after a two-character ::before and at x=0 without one;
// the exact offset is a font metric, so what is checked is that the
// shift equals the width of the generated text.
Page p5 = pageFromHtml(head + '<style>#r::before { content: "XY" }</style>'
    + '<p id="pr"><span id="r">ab</span></p></body>', 'about:blank', 400)
Box pr = pById(p5.root, 'pr')
check(pr != null && pr.lines.length > 0, 'the paragraph has a line')
Line ln = pr.lines[0]
// A line carries a fragment for each inline box it opens as well as one
// per run of text, so the text fragments have to be picked out.
arr[Fragment] texts = []
for int i = 0, i < ln.frags.length, i++ {
    if ln.frags[i].content != null && ln.frags[i].content != '' { texts.push(ln.frags[i]) }
}
checkEqInt(texts.length, 2, 'the line has the generated text and the element text')
checkEq(texts[0].content, 'XY', 'the generated text comes first')
checkEq(texts[1].content, 'ab', 'then the element text')
checkEqInt(texts[0].x, 0, 'the generated text starts the line')
check(texts[1].x > 0, 'and the element text follows it')
checkEqInt(texts[1].x, texts[0].x + texts[0].w, 'exactly where the generated text ends')

finish('pseudo')
