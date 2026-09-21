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

Node func valNodeById(n:Node, id:text) {
    if n.kind == NODE_ELEMENT && attrOf(n.id, 'id') == id { return n }
    for int i = 0, i < n.children.length, i++ {
        Node f = valNodeById(n.children[i], id)
        if f != null { return f }
    }
    return null
}

// ---- min(), max() and clamp() -----------------------------------------
//
// Values and Units 4 §10. Every number here is Chromium 141's, on a
// block in a containing block 400 wide and 300 tall (todo.md). The
// checks that earn their place are the ones that need no number: a
// comparison of two lengths must land where the length it picks lands.

// All lengths, which fold at parse time -- and folding is the point,
// because a folded value is an ordinary LEN_PX and works in the places
// that take one rather than only where `resolveLen` is called.
Len m1 = parseLength('min(100px, 200px)'.toAscii(), 16)
checkEqInt(m1.kind, LEN_PX, 'a comparison of two lengths folds to a length')
checkEqInt(resolveLen(m1, 400, -1), 100, 'and it is the smaller')
checkEqInt(resolveLen(parseLength('max(100px, 200px)'.toAscii(), 16), 400, -1), 200,
    'max() takes the larger')
checkEqInt(resolveLen(parseLength('min(200px, 100px, 150px)'.toAscii(), 16), 400, -1), 100,
    'min() of three')
checkEqInt(resolveLen(parseLength('max(100px, 200px, 150px)'.toAscii(), 16), 400, -1), 200,
    'max() of three')

checkEqInt(resolveLen(parseLength('clamp(50px, 100px, 200px)'.toAscii(), 16), 400, -1), 100,
    'clamp() leaves a value between its bounds alone')
checkEqInt(resolveLen(parseLength('clamp(150px, 100px, 200px)'.toAscii(), 16), 400, -1), 150,
    'and raises one below the minimum')
checkEqInt(resolveLen(parseLength('clamp(50px, 300px, 200px)'.toAscii(), 16), 400, -1), 200,
    'and lowers one above the maximum')
// Measured rather than derived: the minimum wins where the two bounds
// cross, so this is 200 and not 50.
checkEqInt(resolveLen(parseLength('clamp(200px, 100px, 50px)'.toAscii(), 16), 400, -1), 200,
    'a minimum above the maximum wins')

checkEqInt(resolveLen(parseLength('min(10em, 100px)'.toAscii(), 16), 400, -1), 100,
    'em resolves before the comparison')
checkEqInt(resolveLen(parseLength('max(10em, 100px)'.toAscii(), 16), 400, -1), 160,
    'and the em is the larger of the two')

checkEqInt(resolveLen(parseLength('min(100px)'.toAscii(), 16), 400, -1), 100,
    'min() takes a single argument')
checkEqInt(resolveLen(parseLength('max(100px)'.toAscii(), 16), 400, -1), 100,
    'and so does max()')
checkEqInt(resolveLen(parseLength('min( 100px , 200px )'.toAscii(), 16), 400, -1), 100,
    'whitespace around the arguments is allowed')
checkEqInt(resolveLen(parseLength('min(-100px, 100px)'.toAscii(), 16), 400, -1), -100,
    'a negative is smaller than a positive, and the function says so')

// Nesting, in both directions.
checkEqInt(resolveLen(parseLength('calc(min(100px, 200px) + 10px)'.toAscii(), 16), 400, -1), 110,
    'a comparison inside a calc()')
checkEqInt(resolveLen(parseLength('min(calc(50px + 50px), 200px)'.toAscii(), 16), 400, -1), 100,
    'a calc() inside a comparison')
checkEqInt(resolveLen(parseLength('min(min(100px, 200px), 150px)'.toAscii(), 16), 400, -1), 100,
    'a comparison inside a comparison')
checkEqInt(resolveLen(parseLength('calc(2 * min(50px, 200px))'.toAscii(), 16), 400, -1), 100,
    'a comparison multiplied')
checkEqInt(resolveLen(parseLength('min(100px, 200px, max(10px, 300px))'.toAscii(), 16), 400, -1), 100,
    'the other function nested inside this one')

// A percentage cannot fold, because the answer depends on the base:
// the comparison happens AFTER the percentage is resolved, which is
// measured. Asking the same value against two bases is what shows it
// is deferred rather than decided at parse time.
Len mp = parseLength('min(50%, 100px)'.toAscii(), 16)
checkEqInt(resolveLen(mp, 400, -1), 100, 'against a 400 base the length wins')
checkEqInt(resolveLen(mp, 100, -1), 50, 'and against a 100 base the percentage does')
checkEqInt(resolveLen(parseLength('max(50%, 100px)'.toAscii(), 16), 400, -1), 200,
    'max() of the same pair takes the percentage')
checkEqInt(resolveLen(parseLength('min(10%, 20%)'.toAscii(), 16), 400, -1), 40,
    'two percentages against a 400 base')
checkEqInt(resolveLen(parseLength('min(10%, 20%)'.toAscii(), 16), 200, -1), 20,
    'and against a 200 base, which a folded value could not do')
checkEqInt(resolveLen(parseLength('max(10%, 20%)'.toAscii(), 16), 400, -1), 80,
    'and max() of them')
checkEqInt(resolveLen(parseLength('clamp(10%, 100px, 90%)'.toAscii(), 16), 400, -1), 100,
    'clamp() between two percentages')

// The checks that need no number of their own.
checkEqInt(resolveLen(parseLength('min(10px, 20px)'.toAscii(), 16), 400, -1),
           resolveLen(parseLength('10px'.toAscii(), 16), 400, -1),
           'min() of two lengths is the smaller, written out')
checkEqInt(resolveLen(parseLength('max(10px, 20px)'.toAscii(), 16), 400, -1),
           resolveLen(parseLength('20px'.toAscii(), 16), 400, -1),
           'and max() is the larger')
checkEqInt(resolveLen(parseLength('clamp(5px, 10px, 20px)'.toAscii(), 16), 400, -1),
           resolveLen(parseLength('10px'.toAscii(), 16), 400, -1),
           'and a clamp() inside its bounds is the value')
checkEqInt(resolveLen(parseLength('min(50%, 100%)'.toAscii(), 16), 370, -1),
           resolveLen(parseLength('50%'.toAscii(), 16), 370, -1),
           'and a percentage comparison is the percentage it picks')

// The standard's invalid cases, all measured in Chromium.
checkEqInt(parseLength('min(100px, 5)'.toAscii(), 16).kind, LEN_INVALID,
    'a bare number is not a length here, where calc() takes one as a multiplier')
checkEqInt(parseLength('min(100, 200)'.toAscii(), 16).kind, LEN_INVALID,
    'and neither argument may be one')
checkEqInt(parseLength('max(0, 100px)'.toAscii(), 16).kind, LEN_INVALID,
    'and zero is not exempt')
checkEqInt(parseLength('clamp(100px)'.toAscii(), 16).kind, LEN_INVALID,
    'clamp() takes exactly three arguments')
checkEqInt(parseLength('clamp(10px, 20px)'.toAscii(), 16).kind, LEN_INVALID,
    'two of them is not enough')
checkEqInt(parseLength('min()'.toAscii(), 16).kind, LEN_INVALID, 'an empty argument list is invalid')
checkEqInt(parseLength('min(100px,)'.toAscii(), 16).kind, LEN_INVALID, 'and so is a trailing comma')
checkEqInt(parseLength('min(100px'.toAscii(), 16).kind, LEN_INVALID, 'and an unclosed one')

// And it reaches a real declaration, in each of the four kinds of
// property Chromium was asked about.
cascadeReset()
Node dm = parseHtmlText('<html><body><div style="width:400px;height:300px">'
    + '<p id="a" style="width: min(100px, 200px)">x</p>'
    + '<p id="b" style="height: min(10%, 100px)">x</p>'
    + '<p id="c" style="margin-left: min(30px, 60px)">x</p>'
    + '<p id="d" style="font-size: min(30px, 60px); width: 10em">x</p>'
    + '</div></body></html>')
cascadeAddDocumentStyles(dm)
computeStyles(dm)
checkEqInt(resolveLen(valNodeById(dm, 'a').style.width, 400, -1), 100,
    'min() in a width declaration')
checkEqInt(resolveLen(valNodeById(dm, 'b').style.height, 300, -1), 30,
    'min() in a height, against the containing block\'s height')
checkEqInt(resolveLen(valNodeById(dm, 'c').style.marginLeft, 400, -1), 30,
    'min() in a margin')
checkEqInt(valNodeById(dm, 'd').style.fontSize, 30, 'min() in a font size')
checkEqInt(resolveLen(valNodeById(dm, 'd').style.width, 400, -1), 300,
    'which the em beside it then multiplies')

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
// ---- the font-relative units, measured rather than assumed ----------
//
// `ex`, `ch` and `cap` were each half an em, half an em and three
// quarters of one, because the runtime reports no x-height, no zero
// advance and no cap height. Chromium 141 on the same monospace face,
// `width: 10<unit>` at 16, 20, 48, 100 and 180px, least squares:
//
//   ex    0.5473 * size + 0.016
//   ch    0.6020 * size - 0.000
//   cap   0.7310 * size - 0.144
//   ic    1.0000 * size            (an em, which is what it already was)
//
// `ch` has a second, independent reading: this engine's own face
// measures a '0' at 12px at 20, 60 at 100 and 108 at 180, which is
// exactly 0.6 of the size, and Chromium's 0.6020 agrees to a third of
// a percent. `ex`'s 0.5473 agrees with the 0.542 to 0.550 the cap-ratio
// work read off rasterised ink. So the constants are what two
// measurements say rather than what one does.
//
// `cap` takes FONT_CAP, which is the same physical quantity the engine
// already measured twice for `text-box-edge` -- and the two Chromium
// surfaces agree: `0.733 * size - 0.41` and `0.7310 * size - 0.144`
// are within a tenth of a pixel of each other across the whole range.
checkEqInt(resolveLen(parseLength('10ex'.toAscii(), 16), 0, -1), 88,
           'ten ex at 16px, where Chromium measures 90')
checkEqInt(resolveLen(parseLength('10ex'.toAscii(), 180), 0, -1), 985,
           'and 985 at 180px, where Chromium measures 986')
checkEqInt(resolveLen(parseLength('10ch'.toAscii(), 20), 0, -1), 120,
           'ten ch at 20px is exactly what this engine measures ten zeroes at')
checkEqInt(resolveLen(parseLength('10ch'.toAscii(), 180), 0, -1), 1080,
           'and at 180px, where Chromium measures 1084')
checkEqInt(resolveLen(parseLength('10cap'.toAscii(), 180), 0, -1), 1319,
           'ten cap at 180px, where Chromium measures 1315')
// Where the old three-quarters was right, and the only place it was:
// Chromium's metric is hinted per size, so a single ratio cannot
// reproduce it at the small sizes where the hinting departs most.
checkEqInt(resolveLen(parseLength('10cap'.toAscii(), 16), 0, -1), 117,
           'and 117 at 16px, where Chromium measures 120')

// The check that needs no number: a unit that is a ratio of the font
// size is linear in it, so ten of it at one size must be the same as
// one of it at ten times the size. That holds for each of the four and
// fails for anything that quantises per size -- which is exactly how
// Chromium's own answers differ from these.
checkEqInt(resolveLen(parseLength('10ch'.toAscii(), 18), 0, -1),
           resolveLen(parseLength('1ch'.toAscii(), 180), 0, -1),
           'ten ch at 18px is one ch at 180px')
checkEqInt(resolveLen(parseLength('10ex'.toAscii(), 18), 0, -1),
           resolveLen(parseLength('1ex'.toAscii(), 180), 0, -1),
           'and the same of ex')
checkEqInt(resolveLen(parseLength('10cap'.toAscii(), 18), 0, -1),
           resolveLen(parseLength('1cap'.toAscii(), 180), 0, -1),
           'and of cap')

// And they are four different ratios, which the half-an-em pair were
// not: `ex` and `ch` gave the same answer under the old constants and
// must not now.
check(resolveLen(parseLength('10ex'.toAscii(), 100), 0, -1)
      != resolveLen(parseLength('10ch'.toAscii(), 100), 0, -1),
      'an x-height is not a zero advance')
check(resolveLen(parseLength('10cap'.toAscii(), 100), 0, -1)
      != resolveLen(parseLength('10ic'.toAscii(), 100), 0, -1),
      'and a cap height is not an em')

// ---- lh and rlh (Values and Units 4 §6.1) -----------------------------
// `lh` is the element's own computed line height and `rlh` the root
// element's. Chromium 141 on a document whose root is 16px/20px:
//
//   line-height: 30px; width: 2lh            60px
//   width: 2rlh                              40px
//   line-height: 30px; margin-left: 1.5lh    45px
//   line-height: 30px; width: calc(1lh+10px) 40px
//   line-height: 2lh                         40px -- the parent's, not its own
//   font-size: 32px; width: 1lh              20px -- the inherited 20px stands
//   line-height: normal; width: 1lh          19px
//
// The fifth is the one that fixes the order: `lh` inside `line-height`
// itself cannot mean the value being computed, so it means the parent's,
// the way `em` does inside `font-size`.
Style func lhStyleOf(decl:text, id:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>'
        + 'html { font-size: 16px; line-height: 20px }'
        + 'body { font: 16px/20px monospace }'
        + '</style></head><body><div id="' + id + '" style="' + decl + '">x</div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    arr[Node] found = []
    collectElements(d, 'div', found)
    for int i = 0, i < found.length, i++ {
        if attrOf(found[i].id, 'id') == id { return found[i].style }
    }
    return null
}

Style lhA = lhStyleOf('line-height: 30px; width: 2lh', 'a')
check(lhA != null, 'the element is there')
checkEqInt(resolveLen(lhA.width, 0, -1), 60, '`lh` is the element own line height')

Style lhB = lhStyleOf('width: 2rlh', 'b')
checkEqInt(resolveLen(lhB.width, 0, -1), 40, '`rlh` is the root element line height')

Style lhC = lhStyleOf('line-height: 30px; margin-left: 1.5lh', 'c')
checkEqInt(resolveLen(lhC.marginLeft, 0, -1), 45, 'a fractional `lh`')

Style lhD = lhStyleOf('line-height: 30px; width: calc(1lh + 10px)', 'd')
checkEqInt(resolveLen(lhD.width, 0, -1), 40, '`lh` inside calc()')

// The declaration order inside the block must not matter: the line
// height is computed before every other length whatever the author
// wrote first.
Style lhOrder = lhStyleOf('width: 2lh; line-height: 30px', 'o')
checkEqInt(resolveLen(lhOrder.width, 0, -1), 60, 'and the order it is written in does not matter')

Style lhE = lhStyleOf('line-height: 2lh', 'e')
checkEqInt(lhE.lineHeight, 40, '`lh` inside `line-height` is the parent line height')

Style lhF = lhStyleOf('font-size: 32px; width: 1lh', 'f')
checkEqInt(resolveLen(lhF.width, 0, -1), 20,
    'a font size of its own does not change an inherited line height')

// `line-height: normal` has no declared length, so `lh` is whatever a
// line actually comes out at -- which is the other way of asking for
// the same number, and the two have to agree.
Style lhN = lhStyleOf('line-height: normal; width: 1lh', 'n')
checkEqInt(resolveLen(lhN.width, 0, -1), lineHeightOf(lhN),
    '`lh` under `line-height: normal` is the line height a line gets')
checkEqInt(resolveLen(lhN.width, 0, -1), 19, 'which is 19px at 16px, as Chromium measures it')

finish('values')
