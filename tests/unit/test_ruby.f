// CSS Ruby Annotation Layout 1: an annotation set in a band beside the
// base text it annotates.
//
// The measurements are in todo.md. What they say, in one sentence: the
// annotation sits above the base, the ruby is as wide as the wider of
// the two, the line grows to hold the band, and `rt` is set at half
// the element's font size. `ruby-position: under` puts the band below
// instead, and `ruby-align` has two behaviours rather than four --
// `start` puts the annotation at the base's start edge and every other
// value centres it, which is what Chromium does pixel for pixel.
//
// Almost none of this is written down as numbers here. A ruby box is
// made of two runs of text measured by the same measurer, so what the
// checks can assert without inventing an advance is how the two relate:
// the wider one gives the width, the narrower one is centred in it, and
// the line is the base's line plus the band.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func layoutHtml(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, width)
}

Box func findBox(b:Box, tag:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node.tag == tag { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findBox(b.children[i], tag)
        if f != null { return f }
    }
    return null
}

Box func rubyPara(css:text, body:text) {
    return findBox(layoutHtml('<body style="margin:0;font:16px/20px monospace">'
        + '<p style="margin:0;width:400px;' + css + '">' + body + '</p></body>', 400), 'p')
}

// A ruby box is two anonymous bands: the annotation and the base, in
// that order whatever `ruby-position` says -- where they are PLACED is
// the layout's business, which is what keeps the property out of the
// box tree. A laid-out inline's position is on the fragment the line
// holds rather than on the box (FINDINGS.md), so the ink is read off
// the band's own line.
Box func annBand(r:Box) { return r.children[0] }
Box func baseBand(r:Box) { return r.children[1] }

int func inkX(band:Box) {
    if band.lines.length == 0 { return -1 }
    int left = -1
    for int f = 0, f < band.lines[0].frags.length, f++ {
        int x = band.lines[0].frags[f].x
        if left < 0 || x < left { left = x }
    }
    return left
}

int func inkW(band:Box) {
    if band.lines.length == 0 { return 0 }
    int left = inkX(band)
    int right = left
    for int f = 0, f < band.lines[0].frags.length, f++ {
        int e = band.lines[0].frags[f].x + band.lines[0].frags[f].w
        if e > right { right = e }
    }
    return right - left
}

// ---- a ruby is inline-level -------------------------------------------
// The whole of it has to sit on one line with the text either side,
// which is what `display: ruby` being inline-level means and what this
// engine did not do: a ruby was a block box and broke the line in two.
Box p1 = rubyPara('', 'X<ruby>base<rt>ann</rt></ruby>Y')
checkEqInt(p1.lines.length, 1, 'the ruby and the text around it are one line')
Box r1 = findBox(p1, 'ruby')
check(r1 != null, 'the ruby has a box')
check(isInlineLevelBox(r1), 'and it is inline-level')
checkEqInt(r1.children.length, 2, 'it is two bands')

// ---- the line grows by the band ---------------------------------------
Box plain = rubyPara('', 'XbaseY')
check(p1.h > plain.h, 'the ruby makes the paragraph taller than plain text does')
checkEqInt(p1.h, plain.h + annBand(r1).h, 'by exactly the height of the annotation band')
// The band is the height of the ANNOTATION's own line rather than the
// base's, because it takes its metrics from the `<rt>`: half the font
// size and `line-height: normal`, which the user-agent stylesheet
// gives it. Without that the band would be a full base line tall.
check(annBand(r1).h < baseBand(r1).h, 'the annotation band is shorter than the base band')

// ---- the wider of the two gives the width -----------------------------
Box wideBase = rubyPara('', '<ruby>basetext<rt>a</rt></ruby>')
Box wb = findBox(wideBase, 'ruby')
check(inkW(baseBand(wb)) > inkW(annBand(wb)), 'the base is the wider one here')
checkEqInt(wb.w, inkW(baseBand(wb)), 'and the ruby is as wide as it')
// As wide as the same text with no ruby around it, which needs no
// number: the base is measured by the measurer either way.
Box bare = rubyPara('', '<span>basetext</span>')
Box bs = findBox(bare, 'span')
checkEqInt(wb.w, bare.lines[0].frags[1].w, 'and as wide as that text unwrapped')

Box wideAnn = rubyPara('', '<ruby>b<rt>annotation</rt></ruby>')
Box wa = findBox(wideAnn, 'ruby')
check(inkW(annBand(wa)) > inkW(baseBand(wa)), 'the annotation is the wider one here')
checkEqInt(wa.w, inkW(annBand(wa)), 'a wider annotation gives the ruby its width')

// ---- the narrower one is centred in it --------------------------------
checkEqInt(inkX(annBand(wb)) - wb.x, Math.floorDiv(wb.w - inkW(annBand(wb)), 2),
           'a narrower annotation is centred over the base')
checkEqInt(inkX(baseBand(wa)) - wa.x, Math.floorDiv(wa.w - inkW(baseBand(wa)), 2),
           'and a narrower base is centred under its annotation')

// ---- ruby-align: start ------------------------------------------------
// The one value Chromium distinguishes. Everything else centres, which
// is asserted by agreement with `center` rather than by a number.
Box st = rubyPara('ruby-align:start', '<ruby>basetext<rt>a</rt></ruby>')
Box sb = findBox(st, 'ruby')
checkEqInt(inkX(annBand(sb)), sb.x, 'ruby-align: start puts the annotation at the base edge')
for int i = 0, i < 3, i++ {
    text v = i == 0 ? 'center' : (i == 1 ? 'space-between' : 'space-around')
    Box q = rubyPara('ruby-align:' + v, '<ruby>basetext<rt>a</rt></ruby>')
    Box qb = findBox(q, 'ruby')
    checkEqInt(inkX(annBand(qb)) - qb.x, Math.floorDiv(qb.w - inkW(annBand(qb)), 2),
               `ruby-align: ${v} centres it`)
}

// ---- ruby-position ----------------------------------------------------
check(annBand(r1).y < baseBand(r1).y, 'the annotation is above the base by default')
checkEqInt(annBand(r1).y, r1.y, 'at the top of the ruby box')
Box un = rubyPara('ruby-position:under', 'X<ruby>base<rt>ann</rt></ruby>Y')
Box ub = findBox(un, 'ruby')
check(annBand(ub).y > baseBand(ub).y, 'ruby-position: under puts it below')
checkEqInt(annBand(ub).y + annBand(ub).h, ub.y + ub.h, 'at the bottom of the ruby box')
checkEqInt(baseBand(ub).y, ub.y, 'with the base at the top instead')
checkEqInt(un.h, p1.h, 'and the paragraph is the same height either way')

// ---- rp contributes nothing -------------------------------------------
Box withRp = rubyPara('', 'X<ruby>base<rp>(</rp><rt>ann</rt><rp>)</rp></ruby>Y')
checkEqInt(withRp.h, p1.h, 'the parenthesis fallback changes no height')
checkEqInt(findBox(withRp, 'ruby').w, r1.w, 'and no width')

// ---- the annotation is set at half the size ---------------------------
Box t1 = findBox(p1, 'rt')
check(t1 != null, 'the annotation has a box')
checkEqInt(t1.style.fontSize, Math.floorDiv(r1.style.fontSize, 2),
           'rt is set at half the element font size')

// ---- two pairs in one ruby --------------------------------------------
Box two = rubyPara('', '<ruby>aa<rt>1</rt>bb<rt>2</rt></ruby>')
checkEqInt(two.lines.length, 1, 'two base-annotation pairs are still one line')
Box tb = findBox(two, 'ruby')
checkEqInt(tb.children.length, 2, 'both annotations go in the one band')
checkEqInt(annBand(tb).lines.length, 1, 'which holds them on one line')

finish('ruby')
