import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

cascadeReset()
Node doc = parseHtmlText('<html><head><style>p { color: #123456; margin: 1em 2em !important } .x { margin: 0 } #y { font: italic bold 20px/30px "Georgia", serif } div > p { background: url(a.png) rgb(1,2,3) } li:first-child { color: red } .box { border: 2px dashed blue; padding: 4px 8px; width: 50%; height: 10em }</style></head><body><p id="p1" class="x">a</p><div><p id="y" style="color: green; margin-top: 5px">b</p></div><ul><li>one</li><li>two</li></ul><h1>H</h1><a href="#">link</a><table border="1" cellpadding="3"><tr><td>c</td></tr></table><span class="box">s</span><font color="maroon" size="5">f</font><pre>x</pre></body></html>')
cascadeAddDocumentStyles(doc)
computeStyles(doc)

Node body = findElement(doc, 'body')
checkEqInt(body.style.display, DISPLAY_BLOCK, 'body is block')
checkEqInt(resolveLen(body.style.marginTop, 0, -1), 8, 'body margin 8px from UA sheet')
checkEqInt(body.style.fontSize, 16, 'root font size')
checkEq(body.style.fontFamily, 'sans-serif', 'default family')

arr[Node] ps = []
collectElements(doc, 'p', ps)
Style p1 = ps[0].style
checkEqInt(p1.color, packColor(18, 52, 86, 255), 'p color from author sheet')
checkEqInt(resolveLen(p1.marginTop, 0, -1), 16, '!important beats later class rule')
checkEqInt(resolveLen(p1.marginLeft, 0, -1), 32, 'em margins resolved against font size')
Style p2 = ps[1].style
checkEqInt(p2.color, packColor(0, 128, 0, 255), 'inline style wins over id rule')
checkEqInt(resolveLen(p2.marginTop, 0, -1), 20, '!important author rule beats inline style')
checkEqInt(p2.fontSize, 20, 'font shorthand size')
checkEqInt(p2.lineHeight, 30, 'font shorthand line-height')
check(p2.fontBold && p2.fontItalic, 'font shorthand style and weight')
checkEq(p2.fontFamily, 'Georgia', 'font shorthand family unquoted')
checkEqInt(p2.background, packColor(1, 2, 3, 255), 'background shorthand color, child combinator')

arr[Node] lis = []
collectElements(doc, 'li', lis)
checkEqInt(lis[0].style.color, packColor(255, 0, 0, 255), ':first-child matches first li')
checkEqInt(lis[1].style.color, COLOR_BLACK, ':first-child does not match second li')
checkEqInt(lis[1].style.display, DISPLAY_LIST_ITEM, 'li is list-item')
checkEqInt(lis[1].style.listStyle, LIST_DISC, 'ul list style inherited')

Node h1 = findElement(doc, 'h1')
checkEqInt(h1.style.fontSize, 32, 'h1 is 2em')
check(h1.style.fontBold, 'h1 is bold')
checkEqInt(resolveLen(h1.style.marginTop, 0, -1), 21, 'h1 margin 0.67em of 32px')

Node a = findElement(doc, 'a')
checkEqInt(a.style.color, COLOR_LINK, 'a[href] link color')
checkEqInt(a.style.textDecoration, DECO_UNDERLINE, 'a[href] underline')
Node aText = a.children[0]
checkEqInt(aText.style.textDecoration, DECO_UNDERLINE, 'text node shares parent style')

Node td = findElement(doc, 'td')
checkEqInt(td.style.borderTop, 1, 'table border attr gives cell border')
checkEqInt(resolveLen(td.style.paddingLeft, 0, -1), 3, 'cellpadding attr')
checkEqInt(td.style.display, DISPLAY_TABLE_CELL, 'td display')
Node tbl = findElement(doc, 'table')
checkEqInt(tbl.style.borderLeft, 1, 'table border attr')

Node span = findElement(doc, 'span')
checkEqInt(span.style.borderTop, 2, 'border shorthand width')
checkEqInt(span.style.borderTopColor, packColor(0, 0, 255, 255), 'border shorthand color')
checkEqInt(resolveLen(span.style.paddingRight, 0, -1), 8, 'padding two values')
checkEqInt(resolveLen(span.style.paddingBottom, 0, -1), 4, 'padding two values bottom')
checkEqInt(span.style.width.kind, LEN_PERCENT, 'percent width kept as percent')
checkEqInt(resolveLen(span.style.width, 400, -1), 200, 'percent width resolved at layout')
checkEqInt(resolveLen(span.style.height, 0, -1), 160, 'em height')

Node font = findElement(doc, 'font')
checkEqInt(font.style.color, packColor(128, 0, 0, 255), 'font color attr')
checkEqInt(font.style.fontSize, 24, 'font size attr')
Node pre = findElement(doc, 'pre')
checkEqInt(pre.style.whiteSpaceCollapse, WSC_PRESERVE, 'pre preserves whitespace')
checkEqInt(pre.style.textWrapMode, WRAP_NOWRAP, 'and does not wrap')
checkEq(pre.style.fontFamily, 'monospace', 'pre monospace')
Node head = findElement(doc, 'head')
checkEqInt(head.style.display, DISPLAY_NONE, 'head hidden')
// ---- `all` (CSS Cascade 4 §3.2) ---------------------------------------
// One declaration setting every property to a CSS-wide keyword. The
// standard excludes `direction` and `unicode-bidi`, because they carry
// the document's meaning rather than its presentation, and custom
// properties, which are not properties in this sense.
//
// `all` is a shorthand, so it is expanded where it is written: a
// longhand after it wins, one before it does not.

Style func styleOf(markup:text, id:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>.p { color: #ff0000; border: 5px solid green; '
        + 'direction: rtl }</style></head><body><div class="p">' + markup + '</div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    arr[Node] found = []
    collectElements(d, 'span', found)
    for int i = 0, i < found.length, i++ {
        if attrOf(found[i].id, 'id') == id { return found[i].style }
    }
    return null
}

Style allInit = styleOf('<span id="a" style="all:initial">x</span>', 'a')
check(allInit != null, 'the element with `all: initial` is there')
checkEqInt(allInit.color, COLOR_BLACK, '`all: initial` takes the initial colour, not the inherited one')
checkEqInt(allInit.borderTop, 0, 'and the initial border width')

// `all: inherit` is the one keyword this engine does not honour: giving
// a non-inherited property the parent's value needs a field-by-field
// copy of the parent style, and a hand-written list of fields is the
// thing that rotted in styleDigest (todo.md). What it does instead is
// drop the declarations before it, which is the half of the standard's
// rule that costs nothing, so an inherited property still arrives and a
// non-inherited one takes its initial value.
Style allInherit = styleOf('<span id="a" style="border:9px solid;all:inherit">x</span>', 'a')
checkEqInt(allInherit.color, packColor(255, 0, 0, 255), '`all: inherit` leaves an inherited property inherited')
checkEqInt(allInherit.borderTop, 0, 'and drops the declarations before it')

// `unset` is inherit for an inherited property and initial for the rest,
// which is the one keyword that tells the two apart in a single
// declaration.
Style allUnset = styleOf('<span id="a" style="all:unset">x</span>', 'a')
checkEqInt(allUnset.color, packColor(255, 0, 0, 255), '`all: unset` inherits an inherited property')
checkEqInt(allUnset.borderTop, 0, 'and takes the initial value of one that does not inherit')

// Order within the declaration block.
Style afterAll = styleOf('<span id="a" style="all:initial;color:#0000ff">x</span>', 'a')
checkEqInt(afterAll.color, packColor(0, 0, 255, 255), 'a longhand after `all` wins')
Style beforeAll = styleOf('<span id="a" style="color:#0000ff;all:initial">x</span>', 'a')
checkEqInt(beforeAll.color, COLOR_BLACK, 'and one before it does not')

// The two properties the standard leaves alone.
Style keepsDir = styleOf('<span id="a" style="all:initial">x</span>', 'a')
check(keepsDir.directionRtl, '`all` does not touch `direction`')

// An `all` whose value is not a CSS-wide keyword is not a declaration
// at all, so it changes nothing.
Style bogus = styleOf('<span id="a" style="all:red">x</span>', 'a')
checkEqInt(bogus.color, packColor(255, 0, 0, 255), '`all: red` is invalid and leaves the inherited colour')

finish('cascade')
