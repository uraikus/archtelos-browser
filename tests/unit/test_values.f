// calc() and custom properties, both in the official definition of CSS
// (CSS Values and Units 3, CSS Custom Properties 1). See css-2026.md.

import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

// ---- calc() -----------------------------------------------------------
Len c1 = parseLength('calc(100% - 20px)'.toAscii(), 16)
checkEqInt(c1.kind, LEN_CALC, 'a percentage minus a length stays unresolved')
checkEqInt(resolveLen(c1, 400, -1), 380, 'and resolves against the containing block')
checkEqInt(resolveLen(c1, 200, -1), 180, 'against a different containing block')

checkEqInt(resolveLen(parseLength('calc(2em + 10px)'.toAscii(), 16), 0, -1), 42,
    'em resolves against the font size inside calc')
checkEqInt(resolveLen(parseLength('calc(50% + 25%)'.toAscii(), 16), 400, -1), 300,
    'two percentages fold into one')
checkEqInt(resolveLen(parseLength('calc(100px / 4)'.toAscii(), 16), 0, -1), 25, 'division by a number')
checkEqInt(resolveLen(parseLength('calc(3 * 10px)'.toAscii(), 16), 0, -1), 30, 'multiplication by a number')
checkEqInt(resolveLen(parseLength('calc((100% - 20px) / 2)'.toAscii(), 16), 400, -1), 190, 'nested parentheses')
checkEqInt(resolveLen(parseLength('calc(calc(10px + 5px) * 2)'.toAscii(), 16), 0, -1), 30, 'a nested calc()')

// the standard's invalid cases
checkEqInt(parseLength('calc(100%-20px)'.toAscii(), 16).kind, LEN_INVALID,
    'a - without spaces around it is not a subtraction')
checkEqInt(parseLength('calc(10px + )'.toAscii(), 16).kind, LEN_INVALID, 'a trailing operator is invalid')
checkEqInt(parseLength('calc(10px + 5)'.toAscii(), 16).kind, LEN_INVALID, 'a length plus a number is invalid')
checkEqInt(parseLength('calc(1px * 2px)'.toAscii(), 16).kind, LEN_INVALID, 'a length times a length is invalid')
checkEqInt(parseLength('calc(10px'.toAscii(), 16).kind, LEN_INVALID, 'an unclosed calc is invalid')

// and it reaches a real declaration
cascadeReset()
Node d1 = parseHtmlText('<html><body><div style="width: 400px"><p style="width: calc(100% - 40px); margin-left: calc(2em)">x</p></div></body></html>')
cascadeAddDocumentStyles(d1)
computeStyles(d1)
Node p1 = findElement(d1, 'p')
checkEqInt(resolveLen(p1.style.width, 400, -1), 360, 'calc() in a width declaration')
checkEqInt(resolveLen(p1.style.marginLeft, 0, -1), 32, 'calc() in a margin declaration')

// ---- custom properties and var() --------------------------------------
cascadeReset()
Node d2 = parseHtmlText('<html><head><style>:root { --gap: 12px; --brand: #112233 } .a { --gap: 4px } p { margin-top: var(--gap); color: var(--brand); padding-top: var(--missing, 7px); padding-left: var(--nope) }</style></head><body><p id="one">x</p><div class="a"><p id="two">y</p></div></body></html>')
cascadeAddDocumentStyles(d2)
computeStyles(d2)
arr[Node] ps = []
collectElements(d2, 'p', ps)
checkEqInt(resolveLen(ps[0].style.marginTop, 0, -1), 12, 'var() reads a custom property from the root')
checkEqInt(ps[0].style.color, packColor(17, 34, 51, 255), 'var() works for a colour too')
checkEqInt(resolveLen(ps[0].style.paddingTop, 0, -1), 7, 'an unset var() falls back')
checkEqInt(resolveLen(ps[0].style.paddingLeft, 0, -1), 0, 'an unset var() with no fallback drops the declaration')
checkEqInt(resolveLen(ps[1].style.marginTop, 0, -1), 4, 'a nearer custom property wins: they inherit')

// a custom property may hold a calc(), and one may name another
cascadeReset()
Node d3 = parseHtmlText('<html><head><style>:root { --base: 10px; --double: calc(var(--base) * 2) } p { width: var(--double) }</style></head><body><p>x</p></body></html>')
cascadeAddDocumentStyles(d3)
computeStyles(d3)
checkEqInt(resolveLen(findElement(d3, 'p').style.width, 0, -1), 20, 'a custom property naming another, holding a calc()')

// ---- the units of Values and Units 4 -----------------------------------
// `q` is a quarter of a millimetre, so forty of them are a centimetre:
// Chromium 141 makes `width: 40q` 38 pixels and `width: 100q` 94, which
// is 0.945 of a pixel each.
//
// The rest are units this browser can answer only one way, and the
// checks say so by asking for the two spellings to agree rather than
// for a number: a viewport that cannot be resized by a toolbar sliding
// away makes the small, large and dynamic viewport units one unit, and
// a horizontal writing mode makes the inline axis the horizontal one.
// `ic` is the advance of a CJK water ideograph, which is one em in
// every font this engine can load.
cssViewportWidth = 400
cssViewportHeight = 300
cssRootFontSize = 16

checkEqInt(resolveLen(parseLength('40q'.toAscii(), 16), 0, -1), 38,
           'forty quarter-millimetres are a centimetre, which is 37.8 pixels')
checkEqInt(resolveLen(parseLength('100q'.toAscii(), 16), 0, -1), 94,
           'and a hundred of them are 94')

int halfWide = resolveLen(parseLength('50vw'.toAscii(), 16), 0, -1)
int halfTall = resolveLen(parseLength('50vh'.toAscii(), 16), 0, -1)
checkEqInt(resolveLen(parseLength('50svw'.toAscii(), 16), 0, -1), halfWide,
           'the small viewport is this viewport')
checkEqInt(resolveLen(parseLength('50lvw'.toAscii(), 16), 0, -1), halfWide, 'and so is the large')
checkEqInt(resolveLen(parseLength('50dvw'.toAscii(), 16), 0, -1), halfWide, 'and the dynamic')
checkEqInt(resolveLen(parseLength('50svh'.toAscii(), 16), 0, -1), halfTall,
           'down the page as well as across it')
checkEqInt(resolveLen(parseLength('50vi'.toAscii(), 16), 0, -1), halfWide,
           'the inline axis is the horizontal one here')
checkEqInt(resolveLen(parseLength('50vb'.toAscii(), 16), 0, -1), halfTall,
           'and the block axis the vertical')
checkEqInt(resolveLen(parseLength('10ic'.toAscii(), 16), 0, -1),
           resolveLen(parseLength('10em'.toAscii(), 16), 0, -1),
           'an ideograph advance is an em')
checkEqInt(resolveLen(parseLength('10cap'.toAscii(), 16), 0, -1), 120,
           'and a cap height three quarters of one, which is what Chromium measures here')

finish('values')
