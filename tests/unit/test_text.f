// CSS Text 3: the white-space longhands, tab-size, the two ways of
// breaking inside a word, and text-align-last.
//
// `white-space` is a shorthand for two independent things — whether
// spaces and newlines survive, and whether a line may wrap — and the
// engine has always stored the product of the two as one enum. So the
// checks here are the kind CLAUDE.md asks for when two spellings must
// agree: every shorthand value is put against the longhands it stands
// for, rather than against a number. A check that `pre` computes to 1
// would pass just as well if both spellings were broken the same way.
//
// The behaviours are checked in layout, because a property the cascade
// computes and layout never reads is not implemented.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Style func styleOf(decl:text) {
    cascadeReset()
    Node doc = parseHtmlText(`<html><body><p id="t" style="${decl}">x</p></body></html>`)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    arr[Node] ps = []
    collectElements(doc, 'p', ps)
    return ps[0].style
}

void func checkSameWhiteSpace(shorthand:text, longhands:text, label:text) {
    Style a = styleOf(shorthand)
    Style b = styleOf(longhands)
    checkEqInt(a.whiteSpaceCollapse, b.whiteSpaceCollapse, label + ' (collapsing)')
    checkEqInt(a.textWrapMode, b.textWrapMode, label + ' (wrapping)')
}

Box func layoutHtml(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box root = layoutDocument(doc, width)
    numberListItems(root)
    return root
}

Box func findBox(b:Box, tag:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node.tag == tag { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findBox(b.children[i], tag)
        if f != null { return f }
    }
    return null
}

// The used width of one line: from the left edge of its first fragment
// to the right edge of its last.
int func usedLineWidth(b:Box, i:int) {
    Line ln = b.lines[i]
    if ln.frags.length == 0 { return 0 }
    int lo = ln.frags[0].x
    int hi = lo
    for int j = 0, j < ln.frags.length, j++ {
        if ln.frags[j].x < lo { lo = ln.frags[j].x }
        int r = ln.frags[j].x + ln.frags[j].w
        if r > hi { hi = r }
    }
    return hi - lo
}

int func lineLeft(b:Box, i:int) {
    Line ln = b.lines[i]
    if ln.frags.length == 0 { return 0 }
    int lo = ln.frags[0].x
    for int j = 0, j < ln.frags.length, j++ {
        if ln.frags[j].x < lo { lo = ln.frags[j].x }
    }
    return lo
}

// ---- the white-space shorthand and its two longhands ---------------------

checkSameWhiteSpace('white-space:normal', 'white-space-collapse:collapse;text-wrap-mode:wrap',
                    'white-space:normal is collapse + wrap')
checkSameWhiteSpace('white-space:pre', 'white-space-collapse:preserve;text-wrap-mode:nowrap',
                    'white-space:pre is preserve + nowrap')
checkSameWhiteSpace('white-space:nowrap', 'white-space-collapse:collapse;text-wrap-mode:nowrap',
                    'white-space:nowrap is collapse + nowrap')
checkSameWhiteSpace('white-space:pre-wrap', 'white-space-collapse:preserve;text-wrap-mode:wrap',
                    'white-space:pre-wrap is preserve + wrap')
checkSameWhiteSpace('white-space:pre-line', 'white-space-collapse:preserve-breaks;text-wrap-mode:wrap',
                    'white-space:pre-line is preserve-breaks + wrap')

// The five shorthand values are five distinct pairs. Without this the
// checks above would pass with every value collapsing to one pair.
Style wsNormal = styleOf('white-space:normal')
Style wsPre = styleOf('white-space:pre')
Style wsNowrap = styleOf('white-space:nowrap')
Style wsPreWrap = styleOf('white-space:pre-wrap')
Style wsPreLine = styleOf('white-space:pre-line')
check(wsPre.textWrapMode != wsPreWrap.textWrapMode, 'pre and pre-wrap differ in wrapping')
check(wsPreWrap.whiteSpaceCollapse != wsPreLine.whiteSpaceCollapse,
      'pre-wrap and pre-line differ in collapsing')
check(wsNormal.whiteSpaceCollapse != wsPreLine.whiteSpaceCollapse,
      'normal and pre-line differ in collapsing')
check(wsNormal.textWrapMode != wsNowrap.textWrapMode, 'normal and nowrap differ in wrapping')

// ---- pre-line ------------------------------------------------------------
// pre-line keeps newlines and collapses runs of spaces. It used to be
// treated as pre-wrap, which keeps both.

Box rPreLine = layoutHtml('<body><div style="white-space:pre-line;width:300px">a    b'
    + '\nc</div></body>', 400)
Box dPreLine = findBox(rPreLine, 'div')
checkEqInt(dPreLine.lines.length, 2, 'pre-line breaks at the newline')

Box rPreWrap = layoutHtml('<body><div style="white-space:pre-wrap;width:300px">a    b'
    + '\nc</div></body>', 400)
Box dPreWrap = findBox(rPreWrap, 'div')
checkEqInt(dPreWrap.lines.length, 2, 'pre-wrap breaks at the newline too')

Box rCollapsed = layoutHtml('<body><div style="white-space:pre-line;width:300px">a b'
    + '\nc</div></body>', 400)
Box dCollapsed = findBox(rCollapsed, 'div')
checkEqInt(usedLineWidth(dPreLine, 0), usedLineWidth(dCollapsed, 0),
           'pre-line collapses a run of spaces to one')
check(usedLineWidth(dPreWrap, 0) > usedLineWidth(dCollapsed, 0),
      'pre-wrap keeps the run of spaces, which is what pre-line must not do')

// ---- tab-size ------------------------------------------------------------
// A tab in preserved text advances by tab-size. The default is 8.

Box rTab8 = layoutHtml('<body><div style="white-space:pre;width:300px">\tx</div></body>', 400)
Box rTab2 = layoutHtml('<body><div style="white-space:pre;width:300px;tab-size:2">\tx</div></body>', 400)
Box rTab0 = layoutHtml('<body><div style="white-space:pre;width:300px;tab-size:0">\tx</div></body>', 400)
check(usedLineWidth(findBox(rTab8, 'div'), 0) > usedLineWidth(findBox(rTab2, 'div'), 0),
      'a smaller tab-size makes a tab narrower')
check(usedLineWidth(findBox(rTab2, 'div'), 0) > usedLineWidth(findBox(rTab0, 'div'), 0),
      'and tab-size:0 removes the tab entirely')

// Eight spaces and a default tab come to the same width, which is the
// check that the default is 8 rather than the four it used to be.
Box rEight = layoutHtml('<body><div style="white-space:pre;width:300px">        x</div></body>', 400)
checkEqInt(usedLineWidth(findBox(rTab8, 'div'), 0), usedLineWidth(findBox(rEight, 'div'), 0),
           'the initial tab-size is eight spaces')

// A length says the advance directly.
Box rTabPx = layoutHtml('<body><div style="white-space:pre;width:300px;tab-size:40px">\tx</div></body>', 400)
Box rTabPx2 = layoutHtml('<body><div style="white-space:pre;width:300px;tab-size:80px">\tx</div></body>', 400)
check(usedLineWidth(findBox(rTabPx2, 'div'), 0) > usedLineWidth(findBox(rTabPx, 'div'), 0),
      'tab-size takes a length as well as a number')

// ---- breaking inside a word ----------------------------------------------
// A word too long for its line overflows unless something says it may
// be broken. `overflow-wrap: break-word` breaks a word that cannot fit
// on a line of its own; `word-break: break-all` breaks any word to fill
// the line.

text longWord = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz'
Box rOverflow = layoutHtml(`<body><div style="width:60px">${longWord}</div></body>`, 400)
checkEqInt(findBox(rOverflow, 'div').lines.length, 1,
           'a long word overflows its line by default')

Box rBreakWord = layoutHtml(`<body><div style="width:60px;overflow-wrap:break-word">${longWord}</div></body>`, 400)
check(findBox(rBreakWord, 'div').lines.length > 1,
      'overflow-wrap:break-word breaks a word that cannot fit')
check(usedLineWidth(findBox(rBreakWord, 'div'), 0) <= 60,
      'and the broken line stays inside the box')

Box rBreakAll = layoutHtml(`<body><div style="width:60px;word-break:break-all">${longWord}</div></body>`, 400)
check(findBox(rBreakAll, 'div').lines.length > 1, 'word-break:break-all breaks it too')

// The difference between the two: break-all breaks a word that would
// have fitted on the next line, break-word does not.
Box rFitsBreakWord = layoutHtml('<body><div style="width:60px;overflow-wrap:break-word">xx wwwwwwww</div></body>', 400)
Box rFitsBreakAll = layoutHtml('<body><div style="width:60px;word-break:break-all">xx wwwwwwww</div></body>', 400)
check(usedLineWidth(findBox(rFitsBreakAll, 'div'), 0) >= usedLineWidth(findBox(rFitsBreakWord, 'div'), 0),
      'break-all fills the first line at least as far as break-word')

// ---- text-align-last -----------------------------------------------------
// The last line of a block, and a line before a forced break, take
// text-align-last rather than text-align.

text twoLines = 'aaa bbb ccc ddd eee fff ggg hhh iii jjj kkk lll'
Box rLastDefault = layoutHtml(`<body><div style="width:100px">${twoLines}</div></body>`, 400)
Box dLastDefault = findBox(rLastDefault, 'div')
Box rLastRight = layoutHtml(`<body><div style="width:100px;text-align-last:right">${twoLines}</div></body>`, 400)
Box dLastRight = findBox(rLastRight, 'div')
check(dLastDefault.lines.length > 1, 'the text-align-last fixture wraps')
checkEqInt(dLastRight.lines.length, dLastDefault.lines.length,
           'text-align-last does not change where the lines break')
checkEqInt(lineLeft(dLastRight, 0), lineLeft(dLastDefault, 0),
           'text-align-last leaves every line but the last alone')
check(lineLeft(dLastRight, dLastRight.lines.length - 1)
      > lineLeft(dLastDefault, dLastDefault.lines.length - 1),
      'text-align-last:right pushes the last line to the right edge')

// A line before a <br> is a last line too.
Box rBr = layoutHtml('<body><div style="width:200px;text-align-last:right">aa<br>bb</div></body>', 400)
Box rBrPlain = layoutHtml('<body><div style="width:200px">aa<br>bb</div></body>', 400)
check(lineLeft(findBox(rBr, 'div'), 0) > lineLeft(findBox(rBrPlain, 'div'), 0),
      'the line before a forced break takes text-align-last')

finish('text')
