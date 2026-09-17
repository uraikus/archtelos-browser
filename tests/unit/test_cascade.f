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

// ---- revert (Cascade 4 §7.4) -----------------------------------------
// `revert` rolls the property back to the value the previous cascade
// origin gave it -- here the user-agent sheet's, because there is no
// user origin -- and to `unset` when that origin declared nothing.
// Chromium 141 on this markup, read off `getComputedStyle`:
//
//   b { font-weight: normal }        plain b 400, reverted b 700
//   span { display: block }          plain span block, reverted inline
//   div { display: inline }          plain div inline, reverted block
//   li { list-style-type: square }   plain li square, reverted disc
//   p { color: red }                 plain p red, reverted black
//   i { font-weight: revert }        400 -- the UA sheet says nothing
//   b { all: revert }                font-weight 700 and display inline
//
// The two `p` rows are the ones that tell `revert` apart from a
// no-op: the user-agent sheet has no `color` for a paragraph, so the
// rollback lands on the inherited value rather than on anything the UA
// declared.
Style func revertStyleOf(markup:text, tag:text, id:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>'
        + 'b { font-weight: normal }'
        + 'span { display: block }'
        + 'div.inl { display: inline }'
        + 'li { list-style-type: square }'
        + 'p { color: #ff0000 }'
        + '</style></head><body>' + markup + '</body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    arr[Node] found = []
    collectElements(d, tag, found)
    for int i = 0, i < found.length, i++ {
        if attrOf(found[i].id, 'id') == id { return found[i].style }
    }
    return null
}

// The author rule wins where nothing reverts, which is the reference
// every check below is read against.
Style bPlain = revertStyleOf('<b id="a">x</b>', 'b', 'a')
Style bRevert = revertStyleOf('<b id="a" style="font-weight: revert">x</b>', 'b', 'a')
check(bPlain != null && bRevert != null, 'both <b> elements have styles')
check(!bPlain.fontBold, 'the author rule takes the boldness off <b>')
check(bRevert.fontBold, 'and `revert` puts the user-agent sheet back')

Style spanPlain = revertStyleOf('<span id="a">x</span>', 'span', 'a')
Style spanRevert = revertStyleOf('<span id="a" style="display: revert">x</span>', 'span', 'a')
checkEqInt(spanPlain.display, DISPLAY_BLOCK, 'the author rule makes a span a block')
checkEqInt(spanRevert.display, DISPLAY_INLINE, 'and `revert` gives it back the UA display')

Style divPlain = revertStyleOf('<div class="inl" id="a">x</div>', 'div', 'a')
Style divRevert = revertStyleOf('<div class="inl" id="a" style="display: revert">x</div>', 'div', 'a')
checkEqInt(divPlain.display, DISPLAY_INLINE, 'the author rule makes a div inline')
checkEqInt(divRevert.display, DISPLAY_BLOCK, 'and `revert` gives it back block')

Style liPlain = revertStyleOf('<ul><li id="a">x</li></ul>', 'li', 'a')
Style liRevert = revertStyleOf('<ul><li id="a" style="list-style-type: revert">x</li></ul>', 'li', 'a')
checkEqInt(liPlain.listStyle, LIST_SQUARE, 'the author rule squares the marker')
checkEqInt(liRevert.listStyle, LIST_DISC, 'and `revert` gives back the UA disc')

// The case that tells a rollback from a no-op: the user-agent sheet
// declares no `color` for a paragraph, so reverting one lands on the
// inherited value and not on anything the UA said.
Style pPlain = revertStyleOf('<p id="a">x</p>', 'p', 'a')
Style pRevert = revertStyleOf('<p id="a" style="color: revert">x</p>', 'p', 'a')
checkEqInt(pPlain.color, packColor(255, 0, 0, 255), 'the author rule reddens a paragraph')
checkEqInt(pRevert.color, COLOR_BLACK, 'and `revert` falls through to the inherited colour')

// A property the user-agent sheet says nothing about on this element
// reverts to `unset` rather than to some other element's UA value.
Style iRevert = revertStyleOf('<i id="a" style="font-weight: revert">x</i>', 'i', 'a')
check(!iRevert.fontBold, '`revert` on a property the UA sheet does not set is `unset`')

// `all: revert` rolls every property back at once.
Style allRevert = revertStyleOf('<b id="a" style="all: revert">x</b>', 'b', 'a')
check(allRevert.fontBold, '`all: revert` restores the UA boldness')
checkEqInt(allRevert.display, DISPLAY_INLINE, 'and leaves the UA display alone')

// `revert-layer` is not `revert` even where no layer is named. A style
// attribute ranks above an unlayered author rule, so rolling back one
// step lands on that rule rather than on the origin below it: Chromium
// 141 gives `style="font-weight: revert"` 700 on this markup and
// `style="font-weight: revert-layer"` 400.
//
// This check asserted the opposite until `revert-layer` stopped being
// an alias for `revert`, because it was written against the alias
// rather than against the standard -- which is what a test written
// after the code tests.
Style bRevertLayer = revertStyleOf('<b id="a" style="font-weight: revert-layer">x</b>', 'b', 'a')
check(!bRevertLayer.fontBold, '`revert-layer` rolls back one step, not the whole origin')
check(bRevert.fontBold, 'where `revert` beside it rolls back the whole origin')

// ---- the CSS-wide keywords on `display` -------------------------------
// `display` is validated where it is applied, because by then the
// declaration it beat is gone -- and a CSS-wide keyword is a valid value
// for every property, so it has to go through that check. Chromium 141
// on `.par { display: inline-block }` around `span.a { display: block }`:
//
//   #i1 { display: inherit }   inline-block, the parent's
//   #i2 { display: bogus }     block, the author rule's -- invalid is dropped
//
// `initial` and `unset` are the initial value, which for `display` is
// `inline`, because `display` does not inherit.
Style func displayKeywordStyle(decl:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>'
        + '.par { display: inline-block } span.a { display: block }'
        + '</style></head><body><div class="par">'
        + '<span class="a" id="k" style="' + decl + '">x</span></div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    arr[Node] found = []
    collectElements(d, 'span', found)
    for int i = 0, i < found.length, i++ {
        if attrOf(found[i].id, 'id') == 'k' { return found[i].style }
    }
    return null
}

checkEqInt(displayKeywordStyle('').display, DISPLAY_BLOCK, 'the author rule makes the span a block')
checkEqInt(displayKeywordStyle('display: inherit').display, DISPLAY_INLINE_BLOCK,
    '`display: inherit` takes the parent display')
checkEqInt(displayKeywordStyle('display: initial').display, DISPLAY_INLINE,
    '`display: initial` is inline, the initial value')
checkEqInt(displayKeywordStyle('display: unset').display, DISPLAY_INLINE,
    '`display: unset` is the same, because display does not inherit')
checkEqInt(displayKeywordStyle('display: bogus').display, DISPLAY_BLOCK,
    'and an invalid value is dropped, leaving the author rule')

// ---- revert-layer (Cascade 5 §6.3) ------------------------------------
// `revert-layer` rolls the property back to the value the previous
// cascade *layer* gave it, where `revert` rolls back the whole origin.
// An unlayered declaration is in the implicit outer layer, which comes
// after every named one, so reverting one of those lands on the last
// named layer rather than on the origin below.
//
// Chromium 141 on three layers -- `base` blue, `mid` green, `top` the
// one under test:
//
//   @layer top { color: revert-layer }   green: the previous layer
//   @layer top { color: revert }         black: past both, to the origin
//   unlayered   { color: revert-layer }  green: the last named layer
//   @layer top { color: #ff00ff }        magenta, the reference
Style func layerStyleOf(rules:text, id:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>'
        + '@layer base, mid, top;'
        + '@layer base { p { color: #0000ff } }'
        + '@layer mid  { p { color: #008000 } }'
        + rules
        + '</style></head><body><p id="' + id + '">x</p></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    arr[Node] found = []
    collectElements(d, 'p', found)
    for int i = 0, i < found.length, i++ {
        if attrOf(found[i].id, 'id') == id { return found[i].style }
    }
    return null
}

int func layerColour(rules:text, id:text) {
    Style st = layerStyleOf(rules, id)
    return st == null ? 0 : st.color
}

// The reference first: the layers themselves have to be working, or
// every rollback below is being read against nothing.
checkEqInt(layerColour('', 'z'), packColor(0, 128, 0, 255),
    'the later layer wins where nothing reverts')
checkEqInt(layerColour('@layer top { #d { color: #ff00ff } }', 'd'),
    packColor(255, 0, 255, 255), 'and a third layer beats them both')

checkEqInt(layerColour('@layer top { #a { color: revert-layer } }', 'a'),
    packColor(0, 128, 0, 255), '`revert-layer` rolls back to the previous layer')
checkEqInt(layerColour('@layer top { #b { color: revert } }', 'b'),
    COLOR_BLACK, 'where `revert` rolls back past every layer of the origin')
checkEqInt(layerColour('#c { color: revert-layer }', 'c'),
    packColor(0, 128, 0, 255),
    'an unlayered `revert-layer` rolls back to the last named layer')

// Two layers deep: reverting the middle one lands on the first, not on
// the origin, which is what tells a per-layer rollback from a per-origin
// one when only two layers are in play.
checkEqInt(layerColour('@layer mid { #e { color: revert-layer } }', 'e'),
    packColor(0, 0, 255, 255), 'reverting the middle layer lands on the first')

finish('cascade')
