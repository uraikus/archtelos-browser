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

// ---- ::first-line -----------------------------------------------------
// ::first-line restyles whichever characters end up on the first line
// of a block, which is not known until the line has been broken
// (CSS Pseudo-Elements 4 §3.2). Chromium's numbers for a 200px
// paragraph of ten words at 16px/20px monospace:
//
//   p, no pseudo                                  h 60   three lines
//   p, ::first-line font-size:40px line-height:50px  h 90   50 + 20 + 20
//   p, ::first-line color:#ff0000                 h 60   unchanged
//
// The line counts below are this engine's own metrics rather than
// Chromium's, so what is checked is the first line's height, the styles
// the fragments wear, and that a colour-only rule leaves the geometry
// exactly as the plain paragraph's.
text flStyles = '<style>p{width:200px;margin:0}'
    + '#f1::first-line { font-size: 40px; line-height: 50px }'
    + '#f2::first-line { color: #ff0000 }'
    + '</style>'
text flText = 'one two three four five six seven eight nine ten'
Page pf = pageFromHtml(head + flStyles
    + `<p id="f1">${flText}</p><p id="f0">${flText}</p><p id="f2">${flText}</p></body>`,
    'about:blank', 400)
Box f0 = pById(pf.root, 'f0')
Box f1 = pById(pf.root, 'f1')
Box f2 = pById(pf.root, 'f2')
check(f0 != null && f1 != null && f2 != null, 'the three paragraphs have boxes')

// The first text fragment of a line, which is what ::first-line dresses.
Fragment func firstText(b:Box, line:int) {
    if b == null || b.lines.length <= line { return null }
    Line l = b.lines[line]
    for int i = 0, i < l.frags.length, i++ {
        if l.frags[i].kind == FRAG_TEXT { return l.frags[i] }
    }
    return null
}

checkEqInt(f0.lines[0].h, 20, 'the plain paragraph takes its own line-height')
check(f0.lines.length >= 3, 'and wraps onto three lines')
checkEqInt(f0.h, f0.lines.length * 20, 'its height is that many lines')

// The metric case: the first line is as tall as ::first-line asked.
checkEqInt(f1.lines[0].h, 50, 'the first line takes the pseudo-element line-height')
check(f1.lines.length >= 2, 'the paragraph still wraps')
checkEqInt(f1.lines[1].h, 20, 'and the second line is back to the element line-height')
checkEqInt(f1.h, 50 + (f1.lines.length - 1) * 20, 'the height is the first line plus the rest')
check(f1.h > f0.h, 'a bigger first line makes a taller paragraph')

Fragment t10 = firstText(f1, 0)
Fragment t11 = firstText(f1, 1)
check(t10 != null && t11 != null, 'both lines carry text')
checkEqInt(t10.box.style.fontSize, 40, 'the first line is set in the pseudo-element font size')
checkEqInt(t11.box.style.fontSize, 16, 'the second line is set in the element font size')
check(t10.w < f0.lines[0].w, 'fewer characters fit on the bigger first line')

// The paint-only case: a colour changes nothing about the geometry.
checkEqInt(f2.h, f0.h, 'a colour-only ::first-line leaves the height alone')
checkEqInt(f2.lines.length, f0.lines.length, 'and the line count')
Fragment t20 = firstText(f2, 0)
Fragment t21 = firstText(f2, 1)
check(t20 != null && t21 != null, 'both lines carry text')
checkEqInt(t20.box.style.color, packColor(255, 0, 0, 255), 'the first line takes the colour')
checkEqInt(t21.box.style.color, packColor(0, 0, 0, 255), 'the second line does not')
checkEq(t20.content, firstText(f0, 0).content, 'and the same words fall on it')
checkEqInt(t20.w, firstText(f0, 0).w, 'at the same width')

// The characters that move to the second line move with it: the first
// line holds strictly less text than the paragraph does.
check(t10.content != t20.content, 'the bigger first line breaks in a different place')

// ---- ::first-line reaches into the inline boxes on the line ----------
// The standard describes the rule as a fictional element wrapped around
// the line's characters, so an inline inside inherits from it and still
// wins with its own declarations. A bold span on a red first line is
// bold and red; on the second line it is bold and black.
Page pn = pageFromHtml(head
    + '<style>p{width:200px;margin:0}'
    + '#n1::first-line { color: #ff0000; font-size: 24px }'
    + '#n1 b { font-weight: bold }</style>'
    + '<p id="n1">one two <b>three four five six seven eight nine ten</b></p></body>',
    'about:blank', 400)
Box n1 = pById(pn.root, 'n1')
check(n1 != null && n1.lines.length >= 2, 'the paragraph wraps')
// The bold run's fragments on each line, which is what the rule dresses.
Fragment b0 = null
for int i = 0, i < n1.lines[0].frags.length, i++ {
    Fragment f = n1.lines[0].frags[i]
    if f.kind == FRAG_TEXT && f.box.style.fontBold { b0 = f }
}
Fragment b1 = null
for int i = 0, i < n1.lines[1].frags.length, i++ {
    Fragment f = n1.lines[1].frags[i]
    if f.kind == FRAG_TEXT && f.box.style.fontBold { b1 = f }
}
check(b0 != null, 'the bold run reaches the first line')
check(b1 != null, 'and continues onto the second')
checkEqInt(b0.box.style.color, packColor(255, 0, 0, 255), 'the bold run takes the first line colour')
checkEqInt(b0.box.style.fontSize, 24, 'and the first line font size')
checkEqInt(b1.box.style.color, packColor(0, 0, 0, 255), 'the second line keeps the element colour')
checkEqInt(b1.box.style.fontSize, 16, 'and the element font size')
checkEqInt(b0.box.node.id, b1.box.node.id, 'both are the same element')

// ---- the first line of a block whose inline content is anonymous -----
// A block with both inline and block-level children holds its inline
// runs in anonymous boxes. The rule belongs to the first of them and to
// no other: Chromium gives this div h=110 -- 50 for the styled first
// line, 20 for the rest of the run before the paragraph, 20 for the
// paragraph and 20 for the run after it -- against h=80 for the same
// markup with no rule, where the second run is not restyled either.
Page pa = pageFromHtml(head
    + '<style>div{width:200px;margin:0}p{margin:0}'
    + '#a1::first-line { font-size: 40px; line-height: 50px }</style>'
    + '<div id="a1">one two three four five six<p>block</p>seven eight nine ten</div>'
    + '<div id="a0">one two three four five six<p>block</p>seven eight nine ten</div></body>',
    'about:blank', 400)
arr[Box] divs = []
collectBoxesForTag(pa.root, 'div', divs)
Box a1 = null
Box a0 = null
for int i = 0, i < divs.length, i++ {
    if getAttr(divs[i].node, 'id') == 'a1' { a1 = divs[i] }
    if getAttr(divs[i].node, 'id') == 'a0' { a0 = divs[i] }
}
check(a1 != null && a0 != null, 'both divs have boxes')
checkEqInt(a1.h, a0.h + 30, 'only the first line grows, by the 50px line less the 20px one')
// The anonymous runs themselves: the first carries the rule, the second
// does not.
check(a1.children.length >= 3, 'the div has two anonymous runs and the paragraph')
checkEqInt(a1.children[0].lines[0].h, 50, 'the first run takes the pseudo-element line-height')
checkEqInt(a1.children[2].lines[0].h, 20, 'the run after the paragraph does not')

finish('pseudo')
