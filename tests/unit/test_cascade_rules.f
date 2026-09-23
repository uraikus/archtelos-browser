// The cascade rules the CSS Snapshot 2026 requires and this engine got
// wrong: specificity comparison, origin order under !important,
// inherit/initial/unset/revert, @supports evaluation, which properties
// inherit, the rem and vh bases, and whole-rule invalidation.
// See css-2026.md, "CSS Cascade 4" and "CSS Values and Units 3".

import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

// ---- 1. specificity is compared as a triple, not summed ---------------
// 100 classes weigh 100*100 in the old single-integer scheme, exactly a
// tie with one id, so source order decided it. CSS compares (a,b,c)
// lexicographically and the id wins however many classes there are.
cascadeReset()
Node d1 = parseHtmlText('<html><head><style>#target { color: #0000ff } .c0.c1.c2.c3.c4.c5.c6.c7.c8.c9.c10.c11.c12.c13.c14.c15.c16.c17.c18.c19.c20.c21.c22.c23.c24.c25.c26.c27.c28.c29.c30.c31.c32.c33.c34.c35.c36.c37.c38.c39.c40.c41.c42.c43.c44.c45.c46.c47.c48.c49.c50.c51.c52.c53.c54.c55.c56.c57.c58.c59.c60.c61.c62.c63.c64.c65.c66.c67.c68.c69.c70.c71.c72.c73.c74.c75.c76.c77.c78.c79.c80.c81.c82.c83.c84.c85.c86.c87.c88.c89.c90.c91.c92.c93.c94.c95.c96.c97.c98.c99 { color: #ff0000 }</style></head><body><p id="target" class="c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 c16 c17 c18 c19 c20 c21 c22 c23 c24 c25 c26 c27 c28 c29 c30 c31 c32 c33 c34 c35 c36 c37 c38 c39 c40 c41 c42 c43 c44 c45 c46 c47 c48 c49 c50 c51 c52 c53 c54 c55 c56 c57 c58 c59 c60 c61 c62 c63 c64 c65 c66 c67 c68 c69 c70 c71 c72 c73 c74 c75 c76 c77 c78 c79 c80 c81 c82 c83 c84 c85 c86 c87 c88 c89 c90 c91 c92 c93 c94 c95 c96 c97 c98 c99">x</p></body></html>')
cascadeAddDocumentStyles(d1)
computeStyles(d1)
Node t1 = findElement(d1, 'p')
checkEqInt(t1.style.color, packColor(0, 0, 255, 255), 'one id beats a hundred classes')

// ---- 2. !important inverts the origin order ---------------------------
// Normal: UA < author < inline. Important: author < inline < UA, because
// an important user-agent declaration outranks an important author one.
check(matchWeight(false, ORIGIN_UA, CASCADE_NO_LAYER, 0, 0) < matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 0, 0),
      'normal author beats normal UA')
check(matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 0, 0) < matchWeight(false, ORIGIN_INLINE, CASCADE_NO_LAYER, 0, 0),
      'normal inline beats normal author')
check(matchWeight(false, ORIGIN_INLINE, CASCADE_NO_LAYER, 0, 0) < matchWeight(true, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 0, 0),
      'any important beats any normal')
check(matchWeight(true, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 0, 0) < matchWeight(true, ORIGIN_INLINE, CASCADE_NO_LAYER, 0, 0),
      'important inline beats important author')
check(matchWeight(true, ORIGIN_INLINE, CASCADE_NO_LAYER, 0, 0) < matchWeight(true, ORIGIN_UA, CASCADE_NO_LAYER, 0, 0),
      'important UA beats important inline')
check(matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 100, 0) < matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 200, 0),
      'higher specificity wins within an origin')
check(matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 100, 1) < matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 100, 2),
      'later source order wins at equal specificity')

// ---- 3. inherit takes the parent's value ------------------------------
cascadeReset()
Node d3 = parseHtmlText('<html><body><div style="margin-left: 40px; width: 300px; background-color: #ff0000"><p id="a" style="margin-left: inherit; width: inherit; background-color: inherit">x</p></div><section style="color: #00ff00"><p id="b" style="color: inherit">y</p></section></body></html>')
cascadeAddDocumentStyles(d3)
computeStyles(d3)
arr[Node] ps3 = []
collectElements(d3, 'p', ps3)
checkEqInt(resolveLen(ps3[0].style.marginLeft, 0, -1), 40, 'margin-left: inherit takes the parent value')
checkEqInt(resolveLen(ps3[0].style.width, 0, -1), 300, 'width: inherit takes the parent value')
checkEqInt(ps3[0].style.background, packColor(255, 0, 0, 255), 'background-color: inherit takes the parent value')
checkEqInt(ps3[1].style.color, packColor(0, 255, 0, 255), 'color: inherit still works')

// ---- initial and unset outside a length context -----------------------
cascadeReset()
Node d3b = parseHtmlText('<html><body><div style="color: #ff0000"><p style="color: initial">x</p><span style="color: unset">y</span></div></body></html>')
cascadeAddDocumentStyles(d3b)
computeStyles(d3b)
Node p3b = findElement(d3b, 'p')
Node s3b = findElement(d3b, 'span')
checkEqInt(p3b.style.color, COLOR_BLACK, 'color: initial is the initial value, not the parent')
checkEqInt(s3b.style.color, packColor(255, 0, 0, 255), 'color: unset inherits for an inherited property')

// ---- 4. @supports evaluates its condition -----------------------------
cascadeReset()
Node d4 = parseHtmlText('<html><head><style>@supports (color: red) { p { color: #00ff00 } } @supports (nonsense-property: 1) { p { color: #ff0000 } } @supports (display: block) and (color: blue) { p { margin-top: 3px } } @supports (nope: 1) or (color: blue) { p { margin-bottom: 4px } } @supports not (nonsense-property: 1) { p { margin-left: 5px } }</style></head><body><p>x</p></body></html>')
cascadeAddDocumentStyles(d4)
computeStyles(d4)
Node p4 = findElement(d4, 'p')
checkEqInt(p4.style.color, packColor(0, 255, 0, 255), '@supports with a supported declaration applies')
checkEqInt(resolveLen(p4.style.marginTop, 0, -1), 3, '@supports and: both true applies')
checkEqInt(resolveLen(p4.style.marginBottom, 0, -1), 4, '@supports or: one true applies')
checkEqInt(resolveLen(p4.style.marginLeft, 0, -1), 5, '@supports not: false condition negated applies')

// ---- 5. text-decoration and opacity are not inherited -----------------
// Decoration propagates to descendant boxes for painting, but the
// computed value of a child is not the parent's.
cascadeReset()
Node d5 = parseHtmlText('<html><body><p style="text-decoration: underline; opacity: 0.5">a <span>b</span></p></body></html>')
cascadeAddDocumentStyles(d5)
computeStyles(d5)
Node sp5 = findElement(d5, 'span')
Node p5 = findElement(d5, 'p')
checkEqInt(p5.style.textDecoration, DECO_UNDERLINE, 'the element itself keeps its decoration')
checkEqInt(sp5.style.textDecoration, DECO_NONE, 'text-decoration does not inherit')
check(sp5.style.inheritedDecoration == DECO_UNDERLINE, 'decoration still propagates for painting')
check(sp5.style.opacity > 0.99, 'opacity does not inherit')
check(p5.style.opacity < 0.51 && p5.style.opacity > 0.49, 'the element itself keeps its opacity')
check(sp5.style.effectiveOpacity < 0.51, 'group opacity still reaches descendants for painting')

// ---- 6. rem uses the root font size, vh the real viewport -------------
cascadeReset()
Node d6 = parseHtmlText('<html style="font-size: 20px"><body><p style="width: 2rem; height: 1em">x</p></body></html>')
cascadeAddDocumentStyles(d6)
computeStyles(d6)
Node p6 = findElement(d6, 'p')
checkEqInt(resolveLen(p6.style.width, 0, -1), 40, 'rem multiplies the root font size, not a constant')

setCssViewport(800, 1000)
Len vh = parseLength('50vh'.toAscii(), 16)
checkEqInt(roundPx(vh.v), 500, 'vh resolves against the real viewport height')
setCssViewport(800, 600)
Len vh2 = parseLength('50vh'.toAscii(), 16)
checkEqInt(roundPx(vh2.v), 300, 'vh follows a changed viewport height')

// ---- 7. one bad selector invalidates the whole rule -------------------
cascadeReset()
Node d7 = parseHtmlText('<html><head><style>p, ::totally-unknown { color: #ff0000 } p { background-color: #00ff00 }</style></head><body><p>x</p></body></html>')
cascadeAddDocumentStyles(d7)
computeStyles(d7)
Node p7 = findElement(d7, 'p')
checkEqInt(p7.style.color, COLOR_BLACK, 'an unparseable selector in the list drops the whole rule')
checkEqInt(p7.style.background, packColor(0, 255, 0, 255), 'a later valid rule still applies')


// ---- the computed-style cache ----------------------------------------
// Two elements that matched the same declarations under the same parent
// compute the same style, so they are handed the same Style rather than
// parsing the same values twice. These checks exist to pin what belongs
// in that cache key: everything the computation reads. A key that is
// missing a term shows up here as two elements sharing a style they
// should not.
cascadeReset()
Node sc = parseHtmlText('<html><head><style>.a { color: #ff0000 } .b { color: #0000ff }</style></head><body>'
    + '<div id="p1" style="color:#00ff00"><span class="a">x</span><span class="a">y</span><span class="b">z</span></div>'
    + '<div id="p2" style="color:#123456"><span class="a">q</span></div>'
    + '<span class="a" style="margin:1px">inline</span>'
    + '<em class="a">tag differs</em>'
    + '</body></html>')
cascadeAddDocumentStyles(sc)
computeStyles(sc)
arr[Node] spans = []
collectElements(sc, 'span', spans)
arr[Node] ems = []
collectElements(sc, 'em', ems)

// Two computed styles are the same object when they carry the same
// serial. Comparing the references directly is not available: `==` on
// two struct values emits invalid IR (FINDINGS.md, "two struct
// references cannot be compared").
checkEqInt(spans[0].style.serial, spans[1].style.serial, 'two identical siblings share one computed style')
check(spans[0].style.serial != spans[2].style.serial, 'a different class does not share')
check(spans[0].style.serial != spans[3].style.serial, 'the same class under a different parent does not share')
check(spans[0].style.serial != spans[4].style.serial, 'an inline style of its own does not share')
check(spans[0].style.serial != ems[0].style.serial, 'a different tag does not share')
checkEqInt(spans[0].style.color, packColor(255, 0, 0, 255), 'and the shared style is the right one')
checkEqInt(spans[2].style.color, packColor(0, 0, 255, 255), 'as is the unshared one')
checkEqInt(spans[3].style.color, packColor(255, 0, 0, 255), 'and the one under the other parent')

// Inheritance is part of the key by way of the parent: two elements
// declaring nothing inherit different colours from different parents.
cascadeReset()
Node sc2 = parseHtmlText('<html><body><div style="color:#ff0000"><i>a</i></div><div style="color:#0000ff"><i>b</i></div></body></html>')
cascadeAddDocumentStyles(sc2)
computeStyles(sc2)
arr[Node] is2 = []
collectElements(sc2, 'i', is2)
check(is2[0].style.serial != is2[1].style.serial, 'inheriting a different colour does not share')
checkEqInt(is2[0].style.color, packColor(255, 0, 0, 255), 'the first inherits red')
checkEqInt(is2[1].style.color, packColor(0, 0, 255, 255), 'the second inherits blue')
// An+B decides membership, not a position: `pos` matches when there is
// an integer n >= 0 with pos == A*n + B.
check(nthMatches(1, 2, 1) && nthMatches(3, 2, 1) && !nthMatches(2, 2, 1), '2n+1 is the odd ones')
check(nthMatches(2, 2, 0) && !nthMatches(1, 2, 0), '2n is the even ones')
check(nthMatches(3, 0, 3) && !nthMatches(4, 0, 3), '0n+3 is only the third')
check(nthMatches(1, -1, 3) && nthMatches(3, -1, 3) && !nthMatches(4, -1, 3), '-n+3 is the first three')
check(nthMatches(3, 1, 3) && nthMatches(9, 1, 3) && !nthMatches(2, 1, 3), 'n+3 is the third onwards')

// ---- CSS Syntax 3 §4.3.7: an escape in an identifier is decoded --------
// A backslash before a non-hex character stands for that character, and
// a backslash before up to six hex digits stands for the code point
// they name, with one following space consumed as the escape's
// terminator rather than left as a descendant combinator.
//
// Each of these is asserted as the colour the element ends up with:
// grey is the rule that matches everything, so a selector that failed
// to match leaves grey behind and one that matched wrongly would take
// a colour from the wrong rule. todo.md has Chromium's reading.
Node esc = parseHtmlText('<html><head><style>'
    + 'div{color:#cccccc}'
    + '.a\\.b{color:#ff0000}'
    + '#x\\#y{color:#0000ff}'
    + '.\\41 bc{color:#ff00ff}'
    + '.e\\2d f{color:#00ffff}'
    + '</style></head><body>'
    + '<div id="one" class="a.b">x</div>'
    + '<div id="x#y">x</div>'
    + '<div id="three" class="Abc">x</div>'
    + '<div id="four" class="e-f">x</div>'
    + '<div id="five" class="ab">x</div>'
    + '</body></html>')
cascadeReset()
cascadeAddDocumentStyles(esc)
computeStyles(esc)

// The suite has no id lookup of its own, and `findElement` takes a tag.
Node func escById(n:Node, want:text) {
    if n.id != 0 && getAttr(n, 'id') == want { return n }
    for int i = 0, i < n.children.length, i++ {
        Node f = escById(n.children[i], want)
        if f != null { return f }
    }
    return null
}
checkEqInt(escById(esc, 'one').style.color, packColor(255, 0, 0, 255),
           'a backslash before a dot is that dot in the class name')
checkEqInt(escById(esc, 'x#y').style.color, packColor(0, 0, 255, 255),
           'and before a hash, in an id')
checkEqInt(escById(esc, 'three').style.color, packColor(255, 0, 255, 255),
           'a hex escape is the code point it names')
checkEqInt(escById(esc, 'four').style.color, packColor(0, 255, 255, 255),
           'and the space after its digits terminates it, not a combinator')
// The one that must NOT match: `\41 bc` is `Abc`, so a document class
// of `ab` is a different name. Without this the check above would pass
// for a parser that threw the escape away and matched on `bc`.
checkEqInt(escById(esc, 'five').style.color, packColor(204, 204, 204, 255),
           'and an element the decoded name does not name is left alone')

// A code point outside ASCII. The document's own escapes are expanded
// by the tokenizer, so this element's class attribute holds the real
// character rather than the form `src/html/decode.f` rewrites bytes
// into -- which is what the decoded selector has to spell too, and was
// measured by asking what the DOM actually stores. Chromium matches
// `.caf\e9` here, measured.
//
// The character below is a literal U+00E9: Festina's string literals
// take no `\uXXXX`, and the first draft of this check wrote one, so the
// document held six ordinary characters and the check failed against a
// fix that was already right.
Node escU = parseHtmlText('<html><head><style>'
    + 'div{color:#cccccc}.caf\\e9{color:#ff0000}'
    + '</style></head><body><div id="u" class="café">x</div></body></html>')
cascadeReset()
cascadeAddDocumentStyles(escU)
computeStyles(escU)
checkEqInt(escById(escU, 'u').style.color, packColor(255, 0, 0, 255),
           'a hex escape above ASCII is the character the document carries')

finish('cascade rules')
