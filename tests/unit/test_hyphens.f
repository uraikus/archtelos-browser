// `hyphens`, and the soft hyphen it is about.
//
// A soft hyphen is a break opportunity that shows nothing unless the
// line actually breaks there, and then shows a hyphen. `hyphens: none`
// suppresses it; `manual` -- the initial value -- honours it. Automatic
// hyphenation needs a dictionary per language and is not attempted.
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

Box func findById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

text head = '<body style="margin:0;font:16px/20px monospace">'
// The character itself: `­` is not an escape here (FINDINGS.md,
// finding 34).
text SHY = '­'

// One long word with a soft hyphen in the middle of it, in a box too
// narrow to hold the whole thing.
text func hyphenDoc(style:text) {
    return head + '<div id="t" style="width:90px;' + style + '">'
        + 'aaaaaaaa' + SHY + 'bbbbbbbb</div></body>'
}

// ---- the soft hyphen is a break opportunity ------------------------------

Box broken = layoutHtml(hyphenDoc(''), 400)
Box bBox = findById(broken, 't')
checkEqInt(bBox.lines.length, 2, 'a soft hyphen lets a long word break')

Box unbroken = layoutHtml(hyphenDoc('hyphens:none'), 400)
Box uBox = findById(unbroken, 't')
checkEqInt(uBox.lines.length, 1, 'hyphens:none leaves the word whole')

// ---- the hyphen is drawn only where the break happens --------------------

check(bBox.lines[0].frags.length > 0, 'the broken first line has content')
text firstLine = bBox.lines[0].frags[0].content
checkEq(firstLine[firstLine.length - 1], '-', 'a broken line ends with a hyphen')
check(bBox.lines[1].frags.length > 0, 'and the second line has the rest')
text secondLine = bBox.lines[1].frags[0].content
checkEq(secondLine[0], 'b', 'which starts after the break')

// A word that fits shows no hyphen at all, which is what makes the
// soft hyphen soft.
Box fits = layoutHtml(head + '<div id="t" style="width:300px">aaa' + SHY
    + 'bbb</div></body>', 400)
Box fBox = findById(fits, 't')
checkEqInt(fBox.lines.length, 1, 'a word that fits stays on one line')
text whole = fBox.lines[0].frags[0].content
checkEq(whole, 'aaabbb', 'and shows no hyphen where it did not break')

// ---- the soft hyphen never counts as a character on screen ---------------
// The width of a word holding one must be the width of the word
// without it, or the soft hyphen is being drawn when it should not be.

Box withShy = layoutHtml(head + '<div id="t" style="width:300px">aaa' + SHY
    + 'bbb</div></body>', 400)
Box without = layoutHtml(head + '<div id="t" style="width:300px">aaabbb</div></body>', 400)
checkEqInt(findById(withShy, 't').lines[0].frags[0].w,
           findById(without, 't').lines[0].frags[0].w,
           'a soft hyphen that does not break takes no width')

// ---- hyphenate-character (CSS Text 4) ------------------------------------
// The string a hyphenation break shows. `auto` -- the initial value --
// leaves it to the browser, which is a hyphen here. It is inherited,
// and it counts towards the width of the prefix that has to fit, so a
// longer one can move the break.

Box hcDefault = layoutHtml(hyphenDoc(''), 400)
checkEq(findById(hcDefault, 't').lines[0].frags[0].content, 'aaaaaaaa-',
        'a break with no hyphenate-character shows a hyphen')

Box hcEquals = layoutHtml(hyphenDoc("hyphenate-character:'='"), 400)
checkEq(findById(hcEquals, 't').lines[0].frags[0].content, 'aaaaaaaa=',
        'and shows what hyphenate-character names instead')

Box hcAuto = layoutHtml(hyphenDoc('hyphenate-character:auto'), 400)
checkEq(findById(hcAuto, 't').lines[0].frags[0].content,
        findById(hcDefault, 't').lines[0].frags[0].content,
        '`auto` is what the initial value already was')

// Inherited: declared on an ancestor, used at the break.
Box hcInherited = layoutHtml(head + '<div style="hyphenate-character:\'=\'">'
    + '<div id="t" style="width:90px">aaaaaaaa' + SHY + 'bbbbbbbb</div></div></body>', 400)
checkEq(findById(hcInherited, 't').lines[0].frags[0].content, 'aaaaaaaa=',
        'hyphenate-character is inherited')

// The second line is unaffected either way -- only the break carries
// the character, which is what tells this from appending it to the word.
checkEq(findById(hcEquals, 't').lines[1].frags[0].content,
        findById(hcDefault, 't').lines[1].frags[0].content,
        'and the rest of the word is the same however the break is drawn')

finish('hyphens')
