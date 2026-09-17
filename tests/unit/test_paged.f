// Paged media (CSS2 §13, CSS Paged Media 3).
//
// A page box is a rectangle of a named or declared size with margins
// inside it; the page area left over is what the document is laid out
// into, one page's worth at a time. `@page` declares the box, `@page
// :first`, `:left` and `:right` declare it for particular pages, and a
// named `@page` declares it for the elements a `page` property sends
// there.
//
// The sizes are checked against Chromium 141, which prints to PDF and
// writes the page box into the file's `/MediaBox` in points. `size: A4`
// comes back as 594.96 x 841.92pt -- 793.28 x 1122.56 CSS pixels -- and
// this engine converts 210mm x 297mm at 96dpi to 794 x 1123, a pixel
// wider because Chromium quantises the width to its own device unit and
// this rounds the millimetre. `size: 400px 600px` comes back as 300 x
// 450pt, which is 400 x 600 pixels exactly, so the arithmetic agrees
// wherever the standard fixes it.
import ../../src/layout/paginate.f
import ../../src/html/parser.f
import ../assert.f

// The page box a stylesheet gives to a page, by name and number.
PageBox func boxOf(css:text, name:text, index:int) {
    resetPageRules()
    parseStylesheet(css.toAscii())
    return pageBoxFor(name, index)
}

void func checkBox(css:text, name:text, index:int, w:int, h:int, label:text) {
    PageBox b = boxOf(css, name, index)
    checkEqInt(b.width, w, `${label}: width`)
    checkEqInt(b.height, h, `${label}: height`)
}

// ---- the default page --------------------------------------------------
// Chromium prints to US Letter here -- 612 x 792pt, which is 816 x 1056
// pixels -- and this engine says the same, because the yardstick for
// everything else in this file is the browser beside it.
checkBox('', '', 1, 816, 1056, 'no @page at all is US Letter')

// The default margin is the one thing on this page the standard leaves
// to the implementation, so it is stated rather than matched: 0.4in,
// which is 38px at 96dpi. Chromium's own print default measures 37px a
// side, and that is a print setting rather than a CSS one -- a page
// that declares its margins agrees with it exactly, which is the part
// the standard does fix.
PageBox dflt = boxOf('', '', 1)
checkEqInt(dflt.marginTop, 38, 'the default margin is 0.4in')
checkEqInt(dflt.marginLeft, 38, 'on every side')
checkEqInt(dflt.width - dflt.marginLeft - dflt.marginRight, 740, 'so the page area is 740 wide')
checkEqInt(dflt.height - dflt.marginTop - dflt.marginBottom, 980, 'and 980 tall')

// ---- the named sizes ---------------------------------------------------
checkBox('@page { size: A4 }', '', 1, 794, 1123, 'A4')
checkBox('@page { size: A5 }', '', 1, 559, 794, 'A5')
checkBox('@page { size: A3 }', '', 1, 1123, 1587, 'A3')
checkBox('@page { size: B5 }', '', 1, 665, 945, 'B5')
checkBox('@page { size: B4 }', '', 1, 945, 1334, 'B4')
checkBox('@page { size: JIS-B5 }', '', 1, 688, 971, 'JIS-B5')
checkBox('@page { size: JIS-B4 }', '', 1, 971, 1376, 'JIS-B4')
checkBox('@page { size: letter }', '', 1, 816, 1056, 'letter')
checkBox('@page { size: legal }', '', 1, 816, 1344, 'legal')
checkBox('@page { size: ledger }', '', 1, 1056, 1632, 'ledger')

// `landscape` swaps the two, `portrait` leaves them, and either may be
// written before or after the name. Chromium answers `size: A5
// landscape` with 594.96 x 420pt -- the A5 height across and its width
// down -- which is the swap and not some other page.
checkBox('@page { size: A4 landscape }', '', 1, 1123, 794, 'A4 landscape')
checkBox('@page { size: landscape A4 }', '', 1, 1123, 794, 'the keywords either way round')
checkBox('@page { size: A4 portrait }', '', 1, 794, 1123, 'A4 portrait is A4')
// A named size is already taller than it is wide, so `portrait` and the
// bare name have to agree -- and `landscape` has to differ from both,
// or the keyword is being read and dropped.
PageBox lp = boxOf('@page { size: A4 landscape }', '', 1)
PageBox pp = boxOf('@page { size: A4 }', '', 1)
check(lp.width != pp.width, 'landscape is not the same box as portrait')

// A bare orientation takes the default page and turns it.
checkBox('@page { size: landscape }', '', 1, 1056, 816, 'landscape on its own turns the default')

// ---- explicit lengths --------------------------------------------------
checkBox('@page { size: 400px 600px }', '', 1, 400, 600, 'two lengths')
checkBox('@page { size: 500px }', '', 1, 500, 500, 'one length is a square')
checkBox('@page { size: 4in 6in }', '', 1, 384, 576, 'inches')
checkBox('@page { size: 210mm 297mm }', '', 1, 794, 1123, 'millimetres reach A4')
// `auto` is the initial value, so it is the default page and not zero.
checkBox('@page { size: auto }', '', 1, 816, 1056, 'auto is the default page')

// ---- margins -----------------------------------------------------------
PageBox m1 = boxOf('@page { margin: 1in }', '', 1)
checkEqInt(m1.marginTop, 96, 'margin: 1in')
checkEqInt(m1.marginRight, 96, 'on all four sides')
checkEqInt(m1.marginBottom, 96, 'bottom too')
checkEqInt(m1.marginLeft, 96, 'and left')

PageBox m2 = boxOf('@page { margin: 10px 20px 30px 40px }', '', 1)
checkEqInt(m2.marginTop, 10, 'four values: top')
checkEqInt(m2.marginRight, 20, 'right')
checkEqInt(m2.marginBottom, 30, 'bottom')
checkEqInt(m2.marginLeft, 40, 'left')

PageBox m3 = boxOf('@page { margin: 5px 15px }', '', 1)
checkEqInt(m3.marginTop, 5, 'two values: block')
checkEqInt(m3.marginLeft, 15, 'and inline')

PageBox m4 = boxOf('@page { margin: 0; margin-left: 7px }', '', 1)
checkEqInt(m4.marginLeft, 7, 'a longhand after the shorthand wins')
checkEqInt(m4.marginTop, 0, 'and leaves the rest at zero')

// A percentage margin is of the page box, on both axes (CSS2 §13.2).
PageBox m5 = boxOf('@page { size: 400px 600px; margin: 10% }', '', 1)
checkEqInt(m5.marginLeft, 40, 'a percentage margin is of the page width')
checkEqInt(m5.marginTop, 60, 'and of its height down the page')

// ---- the page selectors ------------------------------------------------
// `:first` is the first page, `:left` and `:right` alternate from the
// first page being a right-hand one (CSS2 §13.2.4).
text sel = '@page { margin: 10px } @page :first { margin: 20px }'
    + ' @page :left { margin: 30px } @page :right { margin: 40px }'
checkEqInt(boxOf(sel, '', 1).marginTop, 20, 'page 1 is :first')
checkEqInt(boxOf(sel, '', 2).marginTop, 30, 'page 2 is :left')
checkEqInt(boxOf(sel, '', 3).marginTop, 40, 'page 3 is :right')
checkEqInt(boxOf(sel, '', 4).marginTop, 30, 'page 4 is :left again')

// The specificity is a triple -- a name counts in the first place,
// `:first` in the second, `:left` and `:right` in the third (Paged
// Media 3 §3.5) -- so `:first` beats `:right` on page 1 however they
// are ordered, which source order alone would not give.
text order = '@page :first { margin: 20px } @page :right { margin: 40px }'
checkEqInt(boxOf(order, '', 1).marginTop, 20, ':first outranks :right on page one')
text order2 = '@page :right { margin: 40px } @page :first { margin: 20px }'
checkEqInt(boxOf(order2, '', 1).marginTop, 20, 'whichever order they are written in')

// A name outranks both, and applies only to the pages that asked for it.
text named = '@page { margin: 10px } @page :first { margin: 20px }'
    + ' @page narrow { margin: 50px }'
checkEqInt(boxOf(named, 'narrow', 1).marginTop, 50, 'a name outranks :first')
checkEqInt(boxOf(named, '', 1).marginTop, 20, 'and does not reach a page that did not ask')
checkEqInt(boxOf(named, 'other', 2).marginTop, 10, 'an unknown name falls back to the plain rule')

// Rules accumulate: what a later rule does not say, an earlier one
// still does, which is the cascade and not a last-one-wins.
text accum = '@page { size: A4; margin: 10px } @page :first { margin-top: 99px }'
PageBox acc = boxOf(accum, '', 1)
checkEqInt(acc.width, 794, ':first keeps the size the plain rule set')
checkEqInt(acc.marginTop, 99, 'and takes the margin it set itself')
checkEqInt(acc.marginLeft, 10, 'leaving the other three where they were')

// A named page with its own size, which is the case a chapter opening
// on a wider sheet actually needs.
text bothNames = '@page { size: A5 } @page wide { size: A4 landscape }'
checkBox(bothNames, '', 1, 559, 794, 'the unnamed page keeps A5')
checkBox(bothNames, 'wide', 1, 1123, 794, 'and the named one is A4 landscape')

// ---- @media print ------------------------------------------------------
// A paginated render is the print medium, so `@media print` applies and
// `@media screen` does not -- and the other way round on screen. Every
// `@page` a real document carries is inside one of these.
cssMediaPrint = false
resetPageRules()
parseStylesheet('@media print { @page { margin: 60px } }'.toAscii())
checkEqInt(pageBoxFor('', 1).marginTop, 38, 'on screen, @media print is not applied')
cssMediaPrint = true
resetPageRules()
parseStylesheet('@media print { @page { margin: 60px } }'.toAscii())
checkEqInt(pageBoxFor('', 1).marginTop, 60, 'printing, it is')
resetPageRules()
parseStylesheet('@media screen { @page { margin: 70px } }'.toAscii())
checkEqInt(pageBoxFor('', 1).marginTop, 38, 'and @media screen is not')
cssMediaPrint = false

// The ordinary rules inside `@media print` reach the cascade the same
// way, which is what makes a print stylesheet work at all.
cssMediaPrint = true
Stylesheet ps = parseStylesheet('@media print { p { color: red } } @media screen { p { color: blue } }'.toAscii())
checkEq(dumpStylesheet(ps), 'p{1} { color: red; }\n', 'printing, the print rules are the ones kept')
cssMediaPrint = false
Stylesheet ss = parseStylesheet('@media print { p { color: red } } @media screen { p { color: blue } }'.toAscii())
checkEq(dumpStylesheet(ss), 'p{1} { color: blue; }\n', 'and on screen the screen rules are')

// ---- the break properties ----------------------------------------------
// A page break is a break like a column break, so `break-before: page`
// is a value of the property this engine already has rather than a
// property of its own. `page-break-before` and its two siblings are the
// same three properties under the names CSS2 gave them (Fragmentation 3
// §4.4), so they are renamed rather than reimplemented -- which is what
// makes the cascade between an old name and a new one one property's
// cascade instead of a race between two.
//
// Chromium 141 on the same markup computes `break-before: page` from
// `page-break-before: always`, and reports the legacy longhand as
// `always` and the modern one as `page` -- one property under two
// spellings, which is exactly the renaming.
Node func nodeById(n:Node, id:text) {
    if n.kind == NODE_ELEMENT && attrOf(n.id, 'id') == id { return n }
    for int i = 0, i < n.children.length, i++ {
        Node f = nodeById(n.children[i], id)
        if f != null { return f }
    }
    return null
}

Style func styleOfId(css:text, id:text) {
    cascadeReset()
    cssViewportWidth = 800
    Node doc = parseHtmlText('<html><head><style>' + css
        + '</style></head><body><div id="a"><span id="inner">x</span></div>'
        + '<div id="b">y</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return nodeById(doc, id).style
}

checkEqInt(styleOfId('#a { break-before: page }', 'a').breakBefore, BRK_PAGE,
           'break-before: page')
checkEqInt(styleOfId('#a { page-break-before: always }', 'a').breakBefore, BRK_PAGE,
           'page-break-before: always is the same thing')
checkEqInt(styleOfId('#a { page-break-before: avoid }', 'a').breakBefore, BRK_AVOID,
           'page-break-before: avoid')
checkEqInt(styleOfId('#a { page-break-after: always }', 'a').breakAfter, BRK_PAGE,
           'page-break-after: always')
check(styleOfId('#a { page-break-inside: avoid }', 'a').breakInsideAvoid,
      'page-break-inside: avoid')
checkEqInt(styleOfId('#a { break-before: left }', 'a').breakBefore, BRK_PAGE,
           'a side keyword asks for a page break')
checkEqInt(styleOfId('#a { break-before: recto }', 'a').breakBefore, BRK_PAGE,
           'and so does recto')
checkEqInt(styleOfId('#a { break-before: avoid-page }', 'a').breakBefore, BRK_AVOID,
           'avoid-page forbids one')
checkEqInt(styleOfId('#a { break-before: column }', 'a').breakBefore, BRK_COLUMN,
           'a column break is still its own value')
checkEqInt(styleOfId('#a { break-before: bogus }', 'a').breakBefore, BRK_AUTO,
           'and a word that is neither is auto')

// The rename is guarded by a flag set while the stylesheet is read, so
// it has to be set by every route a declaration can arrive by. An inline
// style is the other one, and it is the one a guard set in the wrong
// place would silently drop.
Style func inlineStyleOf(decl:text) {
    cascadeReset()
    cssViewportWidth = 800
    Node doc = parseHtmlText('<html><body><div id="a" style="' + decl
        + '">x</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return nodeById(doc, 'a').style
}
checkEqInt(inlineStyleOf('page-break-before: always').breakBefore, BRK_PAGE,
           'a page-break in a style attribute is renamed too')
checkEqInt(inlineStyleOf('page-break-after: avoid').breakAfter, BRK_AVOID,
           'and so is one after it')
check(inlineStyleOf('page-break-inside: avoid').breakInsideAvoid,
      'and one inside it')

// One property under two spellings: the later declaration wins whichever
// name it was written under. Two properties would let the legacy one
// always lose, or always win, depending on which was read last.
checkEqInt(styleOfId('#a { break-before: page; page-break-before: auto }', 'a').breakBefore,
           BRK_AUTO, 'the legacy name beats an earlier modern one')
checkEqInt(styleOfId('#a { page-break-before: always; break-before: auto }', 'a').breakBefore,
           BRK_AUTO, 'and the modern name beats an earlier legacy one')

// ---- the page property -------------------------------------------------
// `page` names the page an element belongs on. Chromium computes it to
// `auto` on an element that does not say it *and on that element's
// descendants*, so it does not inherit -- which is worth a check of its
// own, because a property that named a page and inherited would put a
// whole subtree on a named page by accident.
checkEq(styleOfId('#a { page: chapter }', 'a').pageName, 'chapter', 'page names a page')
checkEq(styleOfId('#a { page: chapter }', 'inner').pageName, '',
        'and does not inherit, which Chromium says too')
checkEq(styleOfId('#a { page: chapter }', 'b').pageName, '', 'nor reach a sibling')
checkEq(styleOfId('#a { page: auto }', 'a').pageName, '', 'auto is no page at all')
checkEq(styleOfId('#a { page: Chapter }', 'a').pageName, 'Chapter',
        'a page name keeps its case, being an identifier')

// ---- pagination --------------------------------------------------------
// A page is a fragmentation container like a column, so this is the
// column algorithm over a different container. Every count below is
// Chromium 141's, taken by printing the same fixture to PDF and counting
// the `/Type /Page` objects in it: a page box of 400x600 with 50px
// margins leaves an area 300x500, and a block of 120px is one of four
// that fit on it.
text PAGE_CSS = '@page { size: 400px 600px; margin: 50px } body { margin: 0 }'
    + ' .b { height: 120px }'

text func blocks(n:int) {
    text out = ''
    for int i = 0, i < n, i++ { out = out + `<div class="b" id="b${i}">${i}</div>` }
    return out
}

void func paginateFixture(css:text, body:text) {
    cascadeReset()
    resetPageRules()
    cssMediaPrint = true
    cssViewportWidth = 300
    Node doc = parseHtmlText('<html><head><style>' + css
        + '</style></head><body>' + body + '</body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box root = layoutDocument(doc, 300)
    paginateDocument(root)
    cssMediaPrint = false
}

int func pagesOf(css:text, body:text) {
    paginateFixture(css, body)
    return pageStartY.length
}

checkEqInt(pagesOf(PAGE_CSS, blocks(4)), 1, 'four blocks of 120 fit one page of 500')
checkEqInt(pagesOf(PAGE_CSS, blocks(5)), 2, 'the fifth starts a second')
checkEqInt(pagesOf(PAGE_CSS, blocks(8)), 2, 'eight still fill two')
checkEqInt(pagesOf(PAGE_CSS, blocks(10)), 3, 'and ten need three')
// An empty document is one page, not none: a sheet with nothing on it
// is still a sheet.
checkEqInt(pagesOf(PAGE_CSS, ''), 1, 'an empty document is one page')

// Where each page begins in the document, which is the whole of what
// pagination decides. The first begins at the top of the document
// rather than at its first block, because the body's own margin belongs
// on it.
paginateFixture(PAGE_CSS, blocks(10))
checkEqInt(pageStartY[0], 0, 'page one begins at the top of the document')
checkEqInt(pageStartY[1], 480, 'page two at the fifth block')
checkEqInt(pageStartY[2], 960, 'page three at the ninth')

// ---- forced breaks -----------------------------------------------------
checkEqInt(pagesOf(PAGE_CSS + ' #b1 { break-before: page }', blocks(4)), 2,
           'break-before: page starts a page that had room')
checkEqInt(pagesOf(PAGE_CSS + ' #b1 { page-break-before: always }', blocks(4)), 2,
           'and so does the name CSS2 gave it')
checkEqInt(pagesOf(PAGE_CSS + ' #b1 { break-after: page }', blocks(4)), 2,
           'break-after: page starts one after')
checkEqInt(pagesOf(PAGE_CSS + ' #b1 { break-before: column }', blocks(4)), 1,
           'a column break asks for nothing of a page')
paginateFixture(PAGE_CSS + ' #b1 { break-before: page }', blocks(4))
checkEqInt(pageStartY[1], 120, 'and the page begins where the block does')

// ---- a named page ------------------------------------------------------
// A change of `page` between two siblings forces a break, entering the
// named run and leaving it: Chromium prints three pages for four blocks
// whose third asked for a page of its own, which is two breaks.
text namedCss = PAGE_CSS + ' #b2 { page: chapter }'
    + ' @page chapter { size: 400px 600px; margin: 50px }'
checkEqInt(pagesOf(namedCss, blocks(4)), 3, 'a named page breaks into it and out again')
paginateFixture(namedCss, blocks(4))
checkEq(pageNames[0], '', 'page one is the unnamed page')
checkEq(pageNames[1], 'chapter', 'page two is the named one')
checkEq(pageNames[2], '', 'and page three is unnamed again')

// ---- the page box varies by page ---------------------------------------
// `@page :first` gives the first page a box of its own, so how much fits
// on it is not how much fits on the others. Chromium prints two pages
// for four blocks when the first page's top margin is 300px, where the
// same document on one box is a single page.
text firstCss = '@page { size: 400px 600px; margin: 50px }'
    + ' @page :first { margin-top: 300px } body { margin: 0 } .b { height: 120px }'
checkEqInt(pagesOf(firstCss, blocks(4)), 2, ':first shrinks the first page only')
paginateFixture(firstCss, blocks(4))
checkEqInt(pageBoxes[0].marginTop, 300, 'page one takes the :first margin')
checkEqInt(pageBoxes[1].marginTop, 50, 'and page two does not')
checkEqInt(pageAreaHeight(pageBoxes[0]), 250, 'so page one is 250 tall')
checkEqInt(pageAreaHeight(pageBoxes[1]), 500, 'and page two is 500')

// ---- break-inside: avoid -----------------------------------------------
// A block that may not be broken is one unit however many lines it
// holds, so a page ends before it rather than through it.
text avoidCss = '@page { size: 400px 600px; margin: 50px } body { margin: 0 }'
    + ' .b { height: 120px } #b3 { height: 300px; break-inside: avoid }'
checkEqInt(pagesOf(avoidCss, blocks(4)), 2, 'an unbreakable block moves to the next page')

// ---- a page break does not disturb a column ----------------------------
// The two containers are separate: on screen there is no page, so a
// `break-before: page` inside a multi-column container has to leave the
// columns exactly where they were. Chromium 141 says the same -- a
// forced column break moves the paragraph to the second column and a
// forced page break does not -- and this asks the engine both questions
// at once, because a check that only asked about the page break would
// pass against a container that ignores every break there is.
int func colTopOf(css:text) {
    cascadeReset()
    cssViewportWidth = 400
    Node doc = parseHtmlText('<html><head><style>'
        + '#c { column-count: 2; column-gap: 20px; width: 220px; height: 200px;'
        + ' font: 16px/20px monospace } #c p { margin: 0 } ' + css
        + '</style></head><body><div id="c"><p id="p1">one</p><p id="p2">two</p>'
        + '<p id="p3">three</p><p id="p4">four</p><p id="p5">five</p>'
        + '<p id="p6">six</p></div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box root = layoutDocument(doc, 400)
    return boxLeftOf(root, 'p2')
}

int func boxLeftOf(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b.x }
    for int i = 0, i < b.children.length, i++ {
        int f = boxLeftOf(b.children[i], id)
        if f >= 0 { return f }
    }
    return 0 - 1
}

int plainLeft = colTopOf('')
int columnLeft = colTopOf('#p2 { break-before: column }')
int pageLeft = colTopOf('#p2 { break-before: page }')
check(columnLeft != plainLeft, 'a column break moves the paragraph to the next column')
checkEqInt(pageLeft, plainLeft, 'and a page break leaves it where it was')

finish('paged')
