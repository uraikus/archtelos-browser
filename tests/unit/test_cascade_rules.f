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



// ---- an attribute selector's brackets, quotes and escapes -------------
// Selectors 4 §6.1 builds `[name matcher value]` out of two CSS Syntax 3
// tokens: the name is an identifier and the value is an identifier or a
// string. So both take escapes, and a string takes any character at all
// -- including the `]` that ends the selector, the `[` that began it,
// and the quote around it. Three places here read a bracket wherever
// they saw one and decoded nothing: see todo.md, "What an attribute
// selector cannot say, measured".
//
// Every check below is a pair. A value spelled two ways -- quoted
// against escaped, one quote character against the other, a hex escape
// against the character it names -- must land on the same element,
// which is an assertion neither spelling can satisfy alone. A check
// against a colour worked out by hand catches the case that was thought
// of; a check that two spellings agree catches the one that was not.
// See CLAUDE.md, "When two things must agree, test them against each
// other".

int attrGrey = packColor(204, 204, 204, 255)
int attrRed = packColor(255, 0, 0, 255)

int func attrColor(sel:text, attrHtml:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>div{color:#cccccc}'
        + sel + '{color:#ff0000}</style></head><body><div id="q" '
        + attrHtml + '>x</div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    Node e = escById(d, 'q')
    return e == null ? 0 : e.style.color
}

void func attrAgree(a:text, b:text, attrHtml:text, label:text) {
    int ca = attrColor(a, attrHtml)
    int cb = attrColor(b, attrHtml)
    check(ca == cb && ca == attrRed, label)
}

// A `]` inside a string is not the end of the selector, and the same
// value written with the `]` escaped instead must reach the same place.
attrAgree('[data-x="a]b"]', '[data-x=a\\]b]', 'data-x="a]b"',
          'a quoted `]` and an escaped `]` name the same value')
// The whole value is the bracket, so the first `]` in the source is the
// one inside the quotes.
attrAgree('[data-x="]"]', '[data-x=\\]]', 'data-x="]"',
          'a value that is nothing but `]`')
// A `[` inside a string is not a bracket either. This one is dropped a
// level higher up than the others -- the selector list never pushes it
// -- so the rule disappears rather than failing to match.
attrAgree('[data-x="a[b"]', '[data-x=a\\[b]', 'data-x="a[b"',
          'a quoted `[` and an escaped `[` name the same value')
// A quote inside a string, escaped, against the same value written
// inside the other quote character, where it needs no escape.
attrAgree('[data-x="a\\"b"]', '[data-x=\'a"b\']', 'data-x=\'a"b\'',
          'an escaped quote and the other quote name the same value')
attrAgree('[data-x=\'a\\\'b\']', '[data-x="a\'b"]', 'data-x="a\'b"',
          'and the same the other way round')
// A hex escape in the value, against the character it names.
attrAgree('[data-x="a\\65 b"]', '[data-x="aeb"]', 'data-x="aeb"',
          'a hex escape in a quoted value is the character it names')
attrAgree('[data-x=a\\62 ]', '[data-x="ab"]', 'data-x="ab"',
          'and in an unquoted one, with its terminating space')
// An escaped space in an unquoted value is part of the value, not the
// gap before a case-sensitivity flag. `class="c d"` could not test this
// -- it is two classes -- but one attribute value holds the space.
attrAgree('[data-x=a\\ b]', '[data-x="a b"]', 'data-x="a b"',
          'an escaped space is part of an unquoted value')
// An escape in the name, not the value, in both forms of the selector.
attrAgree('[data\\-x="ab"]', '[data-x="ab"]', 'data-x="ab"',
          'an escape in the attribute name')
attrAgree('[data\\-x]', '[data-x]', 'data-x="ab"',
          'and in the name of an existence test')
// A backslash meaning a backslash.
attrAgree('[data-x="a\\\\b"]', '[data-x=a\\\\b]', 'data-x="a\\b"',
          'a doubled backslash is one backslash in the value')

// The other half: an element the selector does not name is left alone.
// Without these, a parser that cut the value at the first `]` would
// satisfy every check above by matching everything.
checkEqInt(attrColor('[data-x="a]b"]', 'data-x="a"'), attrGrey,
           'a value cut at the `]` does not match the part before it')
checkEqInt(attrColor('[data-x^="a]"]', 'data-x="ab"'), attrGrey,
           'and a prefix holding a `]` is the whole prefix')
checkEqInt(attrColor('[data-x=a\\62 ]', 'data-x="a62"'), attrGrey,
           'a hex escape is the code point, not the digits')
checkEqInt(attrColor('[data\\-x]', 'data-y="ab"'), attrGrey,
           'an escape in a name does not widen what the name matches')
checkEqInt(attrColor('[data-x=a\\ b]', 'data-x="a"'), attrGrey,
           'and an escaped space does not end the value')

// The `s` modifier (Selectors 4 §6.3) asks for a case-sensitive match
// where the attribute would otherwise be matched without regard to
// case. No attribute here is matched that way -- `attrMatches` in
// `src/css/cascade.f` lowercases only under the `i` flag -- so `s` is
// accepted and changes nothing, which is the behaviour §6.3 describes
// for exactly that situation. What the checks below can tell apart is
// a parser that read any trailing letter as `i`, and one that swallowed
// the flag into the value.
//
// The selector conformance instrument cannot ask this: Chromium has
// not shipped `s`, so `element.matches('[data-x="ab" s]')` throws a
// SyntaxError there and the row would be graded against nothing. See
// CLAUDE.md, "A claim about a function, a unit or an at-rule has no
// instrument behind it".
checkEqInt(attrColor('[data-x="ab" s]', 'data-x="ab"'), attrRed,
           'the `s` flag is accepted after a quoted value')
checkEqInt(attrColor('[data-x="AB" s]', 'data-x="ab"'), attrGrey,
           'and is not read as the `i` flag')
checkEqInt(attrColor('[data-x=ab s]', 'data-x="ab"'), attrRed,
           'the `s` flag is accepted after an unquoted value too')
checkEqInt(attrColor('[data-x=AB s]', 'data-x="ab"'), attrGrey,
           'and is not read as the `i` flag there either')

// A `[` inside a string, in one selector of a list, must not cost the
// other selector beside it. `parseSelectorList` counted that bracket,
// so the comma after it was never top-level and the two selectors were
// run together into one that names nothing. The check is that the
// *other* selector still arrives. Asserting the rule as its own
// statement would grade nothing: the prelude scan already steps over
// strings, so a rule on its own survives this bug and only its
// selector list is lost.
cascadeReset()
Node attrList = parseHtmlText('<html><head><style>'
    + 'div{color:#cccccc}[data-x="a[b"], #n{color:#0000ff}'
    + '</style></head><body><div id="q" data-x="a[b">x</div>'
    + '<div id="n">y</div></body></html>')
cascadeAddDocumentStyles(attrList)
computeStyles(attrList)
checkEqInt(escById(attrList, 'n').style.color, packColor(0, 0, 255, 255),
           'a `[` inside a string does not swallow the selector beside it')
checkEqInt(escById(attrList, 'q').style.color, packColor(0, 0, 255, 255),
           'and the selector holding it still matches')

// ---- a complex selector inside :is(), :where(), :not() and :has() ----
// Selectors 4 §3.1 gives each of the four a <complex-selector-list>,
// and §4.2 makes `:has()`'s a *relative* selector list -- so an
// alternative may open with the combinator that says how the match
// stands to the element being tested. Which elements each one matches
// is graded against Chromium by tests/conformance/selectors.f; what
// the instrument cannot ask is what follows.

// 1. The specificity a complex alternative contributes, which no
// "which ids" comparison can see. Measured in Chromium: `:is(div > p)`
// is (0,0,2) and beats a plain `p` written after it, while
// `:where(div > p)` is (0,0,0) and loses to one written before it.
cascadeReset()
Node spc = parseHtmlText('<html><head><style>'
    + '#w1 :is(div > p){color:#ff0000}#w1 p{color:#0000ff}'
    + '#w2 :where(div > p){color:#ff0000}#w2 p{color:#0000ff}'
    + '#w3 p{color:#0000ff}#w3 :where(div > p){color:#ff0000}'
    + '</style></head><body>'
    + '<div id="w1"><div><p id="s1">x</p></div></div>'
    + '<div id="w2"><div><p id="s2">x</p></div></div>'
    + '<div id="w3"><div><p id="s3">x</p></div></div>'
    + '</body></html>')
cascadeAddDocumentStyles(spc)
computeStyles(spc)
checkEqInt(escById(spc, 's1').style.color, packColor(255, 0, 0, 255),
           ':is() with a complex alternative carries that alternative\'s specificity')
checkEqInt(escById(spc, 's2').style.color, packColor(0, 0, 255, 255),
           ':where() carries none of it')
checkEqInt(escById(spc, 's3').style.color, packColor(0, 0, 255, 255),
           'and still none of it written second')

// 2. Which lists forgive and which do not, which the instrument cannot
// ask because an invalid selector and a selector that matches nothing
// are the same answer there. Chromium: `:is(p, &&&bogus)` matches every
// `p`; `:not(p, &&&bogus)` and `:has(p, &&&bogus)` are SyntaxErrors, and
// a rule whose selector is unparseable is dropped whole (§4).
int func forgivingColor(sel:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>p{color:#cccccc}'
        + sel + '{color:#ff0000}</style></head>'
        + '<body><div><p id="q">x</p></div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    Node e = escById(d, 'q')
    return e == null ? 0 : e.style.color
}
checkEqInt(forgivingColor('p:is(.nothing, &&&bogus)'), attrGrey,
           'a forgiving list drops what it cannot read')
checkEqInt(forgivingColor('p:is(:nth-child(1), &&&bogus)'), attrRed,
           'and keeps what it can, beside it')
checkEqInt(forgivingColor('p:where(:nth-child(1), &&&bogus)'), attrRed,
           ':where() forgives the same way')
checkEqInt(forgivingColor('p:is(&&&bogus)'), attrGrey,
           'a forgiving list that forgave everything matches nothing')
checkEqInt(forgivingColor('p:is(:nth-child(1), > span)'), attrRed,
           'a leading combinator outside :has() is one more thing to forgive')
// The unforgiving three. Each rule below is dropped whole, so the grey
// from the rule before it stands -- and the check can tell that apart
// from "matched nothing" only because a *valid* selector of the same
// shape is red above.
checkEqInt(forgivingColor('p:not(&&&bogus)'), attrGrey,
           ':not() does not forgive: the whole rule is dropped')
checkEqInt(forgivingColor('p:not(> span)'), attrGrey,
           'and a leading combinator in it is a syntax error, not a relation')
checkEqInt(forgivingColor('div:has(p, &&&bogus)'), attrGrey,
           ':has() does not forgive either')

// 3. `:has()`'s relation is per alternative, so one `:has()` may name
// two of them -- which Chromium answers both of, asked directly.
cascadeReset()
Node rel = parseHtmlText('<html><head><style>i{color:#cccccc}'
    + 'i:has(> b, + u){color:#ff0000}'
    + '</style></head><body>'
    + '<i id="r1"><b>x</b></i>'
    + '<i id="r2"></i><u>x</u>'
    + '<i id="r3"><em><b>x</b></em></i>'
    + '<i id="r4"></i>'
    + '</body></html>')
cascadeAddDocumentStyles(rel)
computeStyles(rel)
checkEqInt(escById(rel, 'r1').style.color, attrRed,
           'one alternative of a :has() names a child')
checkEqInt(escById(rel, 'r2').style.color, attrRed,
           'and the other names the next sibling')
checkEqInt(escById(rel, 'r3').style.color, attrGrey,
           'a grandchild is not a child, so the child relation is a relation')
checkEqInt(escById(rel, 'r4').style.color, attrGrey,
           'and an element neither relation reaches is left alone')

// ---- `:nth-child()`'s `of S` clause -----------------------------------
// Which elements each form matches is graded against Chromium by
// tests/conformance/selectors.f, which holds twelve rows of it. What
// the instrument cannot ask is below: two forms Chromium refuses, and
// one where this engine and Chromium disagree.
int func nthOfColor(sel:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>i{color:#cccccc}'
        + sel + '{color:#ff0000}</style></head><body><div>'
        + '<i id="n1" class="k">a</i><i id="n2">b</i><i id="n3" class="k">c</i>'
        + '</div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    Node e = escById(d, 'n3')
    return e == null ? 0 : e.style.color
}
// n3 is the second `.k` among its siblings and the third child, so a
// working `of` clause colours it and a working An+B alone does not.
checkEqInt(nthOfColor('i:nth-child(2 of .k)'), attrRed,
           'the `of` clause counts only the siblings that match it')
checkEqInt(nthOfColor('i:nth-child(2)'), attrGrey,
           'and without it the same An+B names a different element')
// `of` is matched without regard to case, which is CSS's general rule.
// Chromium refuses `OF` and `Of`; the difference is recorded in
// todo.md rather than copied, and this is what asserts the choice.
checkEqInt(nthOfColor('i:nth-child(2 OF .k)'), attrRed,
           'the keyword is matched without regard to case')
checkEqInt(nthOfColor('i:nth-child(2 Of .k)'), attrRed,
           'in either mixed spelling')
// The two forms Chromium refuses, and this engine refuses with it. Each
// drops its whole rule, so the grey stands.
checkEqInt(nthOfColor('i:nth-of-type(1 of i)'), attrGrey,
           'only :nth-child() and :nth-last-child() take an `of` clause')
checkEqInt(nthOfColor('i:nth-last-of-type(1 of i)'), attrGrey,
           'and neither of-type twin does')
checkEqInt(nthOfColor('i:nth-child(2of .k)'), attrGrey,
           'the keyword needs whitespace, because `2of` is one token')
checkEqInt(nthOfColor('i:nth-child(2 of )'), attrGrey,
           'and an empty clause is a syntax error')
// A class named `of` is not the keyword, which is what makes the scan
// look for whitespace on both sides rather than for the two letters.
cascadeReset()
Node ofcls = parseHtmlText('<html><head><style>i{color:#cccccc}'
    + 'i:nth-child(2 of .of){color:#ff0000}'
    + '</style></head><body><div>'
    + '<i id="c1" class="of">a</i><i id="c2">b</i><i id="c3" class="of">c</i>'
    + '</div></body></html>')
cascadeAddDocumentStyles(ofcls)
computeStyles(ofcls)
checkEqInt(escById(ofcls, 'c3').style.color, attrRed,
           'a class named `of` inside the clause is not a second keyword')

// The specificity S contributes, measured in Chromium: `:nth-child(1 of
// #a)` beats `.k.k` written either side of it, so the pseudo-class's own
// weight is added to S's most specific alternative rather than standing
// alone.
cascadeReset()
Node nsp = parseHtmlText('<html><head><style>'
    + '#g1 .k.k{color:#0000ff}#g1 :nth-child(1 of #a1){color:#ff0000}'
    + '#g2 :nth-child(1 of #a2){color:#ff0000}#g2 .k.k{color:#0000ff}'
    + '</style></head><body>'
    + '<div id="g1"><i id="a1" class="k">x</i></div>'
    + '<div id="g2"><i id="a2" class="k">x</i></div>'
    + '</body></html>')
cascadeAddDocumentStyles(nsp)
computeStyles(nsp)
checkEqInt(escById(nsp, 'a1').style.color, attrRed,
           'the `of` clause carries its own specificity')
checkEqInt(escById(nsp, 'a2').style.color, attrRed,
           'and carries it whichever order the rules are written in')

// ---- the form-state pseudo-classes the instrument cannot grade -------
// Which elements each one matches is graded against Chromium by
// tests/conformance/selectors.f, which holds twenty-one rows of this
// family. Two things the fixture cannot ask are below.

// 1. `contenteditable` makes any element `:read-write`, and `false` on a
// nearer ancestor takes it back. The instrument's fixture is HTML's own
// controls, so this branch has no row there.
cascadeReset()
Node ce = parseHtmlText('<html><head><style>'
    + 'div{color:#cccccc}div:read-write{color:#ff0000}'
    + '</style></head><body>'
    + '<div id="e1" contenteditable>a</div>'
    + '<div id="e2" contenteditable="true"><div id="e3">b</div></div>'
    + '<div id="e4" contenteditable><div id="e5" contenteditable="false">c</div></div>'
    + '<div id="e6">d</div>'
    + '</body></html>')
cascadeAddDocumentStyles(ce)
computeStyles(ce)
checkEqInt(escById(ce, 'e1').style.color, attrRed,
           'a bare contenteditable makes an element read-write')
checkEqInt(escById(ce, 'e3').style.color, attrRed,
           'and a descendant of one is read-write too')
checkEqInt(escById(ce, 'e5').style.color, attrGrey,
           'contenteditable="false" takes it back')
checkEqInt(escById(ce, 'e6').style.color, attrGrey,
           'and an ordinary div is read-only')

// 2. `:dir()` takes only `ltr` and `rtl`. `auto` is a real value of the
// `dir` attribute and not of this selector, so the rule is dropped
// rather than matching everything.
cascadeReset()
Node dirsel = parseHtmlText('<html><head><style>'
    + 'p{color:#cccccc}p:dir(auto){color:#ff0000}'
    + '</style></head><body><p id="q" dir="auto">x</p></body></html>')
cascadeAddDocumentStyles(dirsel)
computeStyles(dirsel)
checkEqInt(escById(dirsel, 'q').style.color, attrGrey,
           ':dir(auto) is not a selector, so its rule is dropped')
// An element under `dir="auto"` falls back to the default rather than
// asking the text, which todo.md records as the part not read.
cascadeReset()
Node dirauto = parseHtmlText('<html><head><style>'
    + 'p{color:#cccccc}p:dir(ltr){color:#ff0000}'
    + '</style></head><body><div dir="auto"><p id="q">x</p></div></body></html>')
cascadeAddDocumentStyles(dirauto)
computeStyles(dirauto)
checkEqInt(escById(dirauto, 'q').style.color, attrRed,
           'and `dir="auto"` is passed over rather than read')

// ---- a CSS-wide keyword on a shorthand ---------------------------------
// Cascade 4 §3.1: `inherit`, `initial`, `unset`, `revert` and
// `revert-layer` are valid values for every property, and on a shorthand
// each one sets **every longhand** to that keyword. The four-sides
// shorthands got this free, because they pass their value through to
// each side unparsed; the ones that parse a value into parts read the
// keyword as a font family, a colour or a list marker and set the rest
// to their defaults.
//
// Each check is a pair, and a third document makes it able to fail: the
// rollback must land on what the lower layer left, and must *not* land
// on what the shorthand itself said. Without the third, a shorthand that
// changed nothing at all would pass. See CLAUDE.md, "When two things
// must agree, test them against each other".
text func shStyle(css:text) {
    cascadeReset()
    setCssViewport(800, 600)
    Node d = parseHtmlText('<html><head><style>' + css + '</style></head><body>'
        + '<div id="q" style="display:grid;position:relative">x</div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    Node e = escById(d, 'q')
    return e == null ? 'NOELEM' : describeStyle(e.style)
}

void func shRollsBack(sh:text, longhand:text, low:text, high:text) {
    // `border-style: solid` sits outside the layers because a border
    // width with no style beside it computes to zero, which would make
    // three of these checks compare two zeroes (CLAUDE.md's own trap).
    text base = '#q{border-style:solid}'
    text reverted = base + '@layer a,b;@layer a{#q{' + longhand + ':' + low
        + '}}@layer b{#q{' + sh + ':' + high + ';' + sh + ':revert-layer}}'
    text expected = base + '#q{' + longhand + ':' + low + '}'
    text control = base + '@layer a,b;@layer a{#q{' + longhand + ':' + low
        + '}}@layer b{#q{' + sh + ':' + high + '}}'
    text a = shStyle(reverted)
    text b = shStyle(expected)
    text c = shStyle(control)
    check(b != c, `${sh}: the check can tell the rollback from the shorthand`)
    check(a == b, `${sh}: a CSS-wide keyword reaches every longhand`)
}

shRollsBack('font', 'font-weight', '700', 'italic 300 20px/2 serif')
shRollsBack('background', 'background-color', '#008000', '#ff0000')
shRollsBack('border', 'border-top-width', '9px', '2px solid #000000')
shRollsBack('border-top', 'border-top-width', '9px', '2px solid #000000')
shRollsBack('border-width', 'border-top-width', '9px', '2px')
shRollsBack('list-style', 'list-style-type', 'square', 'disc inside')
shRollsBack('margin', 'margin-top', '9px', '2px')
shRollsBack('padding', 'padding-top', '9px', '2px')
shRollsBack('margin-block', 'margin-top', '9px', '2px')
shRollsBack('padding-inline', 'padding-left', '9px', '2px')

// The one that started it, against the user-agent sheet rather than a
// layer: Chromium reverts `font` on a `<b>` to the sheet's `bold`.
cascadeReset()
Node shUa = parseHtmlText('<html><head><style>'
    + 'b{font:italic 400 20px/2 serif}#q{font:revert}'
    + '</style></head><body><b id="q">x</b></body></html>')
cascadeAddDocumentStyles(shUa)
computeStyles(shUa)
check(escById(shUa, 'q').style.fontBold,
      '`font: revert` reaches the user-agent sheet, where `font-weight: revert` did')

// ---- a shorthand and its longhand must compete -------------------------
// `text-decoration` and `text-decoration-line` were separate keys in the
// declaration map, and the reader applied the shorthand first and the
// longhand second -- so the longhand won whatever the source order was
// and the cascade never got to decide. Both orders are Chromium's,
// asked of it directly.
int func decoOf(css:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>' + css
        + '</style></head><body><p id="q">x</p></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    Node e = escById(d, 'q')
    return e == null ? 0 - 1 : e.style.textDecoration
}
checkEqInt(decoOf('#q{text-decoration-line:underline;text-decoration:overline}'),
           DECO_OVERLINE, 'a later `text-decoration` beats an earlier `text-decoration-line`')
checkEqInt(decoOf('#q{text-decoration:overline;text-decoration-line:underline}'),
           DECO_UNDERLINE, 'and the other order gives the other answer')
// The pair is what makes it a test rather than one remembered number:
// an engine that always prefers one of the two passes one check and
// fails the other, whichever one it prefers.
checkEqInt(decoOf('#q{text-decoration-line:underline}'), DECO_UNDERLINE,
           'the longhand alone still works')
checkEqInt(decoOf('#q{text-decoration:overline}'), DECO_OVERLINE,
           'and the shorthand alone')
checkEqInt(decoOf('#q{text-decoration-line:underline;text-decoration:none}'),
           DECO_NONE, '`text-decoration: none` after a line clears it')
checkEqInt(decoOf('#q{text-decoration-line:underline;text-decoration:initial}'),
           DECO_NONE, 'and so does a CSS-wide keyword through the shorthand')
checkEqInt(decoOf('#q{text-decoration:red}'), DECO_NONE,
           'a shorthand that names only a colour leaves the line at its initial value')

// The shorthand resets the longhands it does not name to their initial
// values, which is the half of "one key per longhand" that a reader
// applying the shorthand first would get wrong in the other direction.
// Every expectation is Chromium 141's, read with getComputedStyle.
Style func decoStyleOf(css:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>' + css
        + '</style></head><body><p id="q">x</p></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    return escById(d, 'q').style
}
Style tdReset = decoStyleOf('#q{text-decoration-color:red;text-decoration-style:dotted;'
    + 'text-decoration-thickness:5px;text-decoration:underline}')
check(tdReset.decorationColor == COLOR_UNSET,
      'the shorthand resets a colour it does not name')
checkEqInt(tdReset.decorationStyle, DECOSTYLE_SOLID,
           'and a style it does not name')
checkEqInt(tdReset.decorationThickness, 0,
           'and a thickness it does not name')
// And the other way: a longhand after the shorthand replaces only
// itself, so the shorthand's colour is still there.
Style tdKeep = decoStyleOf('#q{text-decoration:underline red;text-decoration-line:overline}')
checkEqInt(tdKeep.decorationColor, packColor(255, 0, 0, 255),
           'a later longhand leaves the shorthand\'s other values alone')
checkEqInt(tdKeep.textDecoration, DECO_OVERLINE,
           'while replacing the one it names')
checkEqInt(decoStyleOf('#q{text-decoration:underline 5px}').decorationThickness, 5,
           'the shorthand carries a thickness')
// The shorthand carries more than the line, and expanding it must not
// lose the rest.
cascadeReset()
Node tdFull = parseHtmlText('<html><head><style>'
    + '#q{text-decoration:underline dotted #ff0000}'
    + '</style></head><body><p id="q">x</p></body></html>')
cascadeAddDocumentStyles(tdFull)
computeStyles(tdFull)
checkEqInt(escById(tdFull, 'q').style.textDecoration, DECO_UNDERLINE,
           'the shorthand still carries its line')
checkEqInt(escById(tdFull, 'q').style.decorationColor, packColor(255, 0, 0, 255),
           'and its colour')
check(escById(tdFull, 'q').style.decorationStyle == decorationStyleKeyword('dotted'.toAscii()),
      'and its style')

// ---- place-items, place-content and place-self -------------------------
// Each is a two-value shorthand whose first value is the block-axis
// property and whose second is the inline one, and one value sets both
// (CSS Box Alignment 3). All six longhands were read here and none of
// the three shorthands that set them.
void func placeIs(css:text, wantAlign:int, wantJustify:int, label:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>#q{display:grid;' + css
        + '}</style></head><body><div id="q">x</div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    Node e = escById(d, 'q')
    if e == null { checksFailed++  log(`FAIL: ${label}: no element`)  return }
    checkEqInt(e.style.alignItems, wantAlign, label + ' (block axis)')
    checkEqInt(e.style.justifyItems, wantJustify, label + ' (inline axis)')
}
placeIs('align-items:end;justify-items:center', BOXALIGN_END, BOXALIGN_CENTRE,
        'the two longhands, as the yardstick the shorthand must match')
placeIs('place-items:end center', BOXALIGN_END, BOXALIGN_CENTRE,
        '`place-items` is the block axis then the inline one')
placeIs('place-items:end', BOXALIGN_END, BOXALIGN_END,
        'and one value sets both')

void func placeContentIs(css:text, wantAlign:int, wantJustify:int, label:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>#q{display:grid;' + css
        + '}</style></head><body><div id="q">x</div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    Node e = escById(d, 'q')
    if e == null { checksFailed++  log(`FAIL: ${label}: no element`)  return }
    checkEqInt(e.style.alignContent, wantAlign, label + ' (block axis)')
    checkEqInt(e.style.justifyContent, wantJustify, label + ' (inline axis)')
}
placeContentIs('align-content:start;justify-content:end', BOXALIGN_START, BOXALIGN_END,
               'the two longhands, as the yardstick')
placeContentIs('place-content:start end', BOXALIGN_START, BOXALIGN_END,
               '`place-content` is the block axis then the inline one')

void func placeSelfIs(css:text, wantAlign:int, wantJustify:int, label:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>#p{display:grid}#q{' + css
        + '}</style></head><body><div id="p"><div id="q">x</div></div></body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    Node e = escById(d, 'q')
    if e == null { checksFailed++  log(`FAIL: ${label}: no element`)  return }
    checkEqInt(e.style.alignSelf, wantAlign, label + ' (block axis)')
    checkEqInt(e.style.justifySelf, wantJustify, label + ' (inline axis)')
}
placeSelfIs('align-self:center;justify-self:end', BOXALIGN_CENTRE, BOXALIGN_END,
            'the two longhands, as the yardstick')
placeSelfIs('place-self:center end', BOXALIGN_CENTRE, BOXALIGN_END,
            '`place-self` is the block axis then the inline one')
placeSelfIs('place-self:center', BOXALIGN_CENTRE, BOXALIGN_CENTRE,
            'and one value sets both')
placeContentIs('place-content:center', BOXALIGN_CENTRE, BOXALIGN_CENTRE,
               '`place-content` takes one value too')
placeContentIs('place-content:space-between space-around',
               BOXALIGN_SPACE_BETWEEN, BOXALIGN_SPACE_AROUND,
               'and the distribution keywords go through it')
placeIs('place-items:baseline stretch', BOXALIGN_BASELINE, BOXALIGN_STRETCH,
        'as do baseline and stretch')

// A shorthand and a longhand of the same property must compete on
// source order, which is the whole reason these are expanded rather
// than read beside their longhands.
placeIs('align-items:start;place-items:end center', BOXALIGN_END, BOXALIGN_CENTRE,
        'a later `place-items` beats an earlier `align-items`')
placeIs('place-items:end center;align-items:start', BOXALIGN_START, BOXALIGN_CENTRE,
        'and an earlier one loses to a later `align-items`')

// An invalid value drops the whole declaration rather than the half of
// it that failed: Chromium answers `start` here, which is what the
// `align-items` before it said.
placeIs('align-items:start;justify-items:center;place-items:end nonsense',
        BOXALIGN_START, BOXALIGN_CENTRE,
        'an unknown second value drops the whole shorthand')

// ---- every shorthand competes with its longhands -----------------------
// `text-decoration` was not the only one. An audit of the whole engine
// for the same shape -- a shorthand read from the declaration map in
// computeStyleValues rather than expanded into its longhands in
// applyDecl -- turned up eight more. Each is asked in both orders,
// because whichever fixed order a reader picks, one of the two is
// wrong: reading the shorthand first makes the longhand always win,
// and reading it last makes the shorthand always win. Every expectation
// is Chromium 141's, read with getComputedStyle off the same block.
Style func shOf(css:text, body:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>' + css + '</style></head><body>'
        + body + '</body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    return escById(d, 'q').style
}
text plainDiv = '<div id="q">x</div>'
text flexKid = '<div id="p" style="display:flex"><div id="q">x</div></div>'
text scrollBox = '<div id="q" style="overflow:scroll;width:50px;height:50px">x</div>'

// border-radius against one corner.
checkEqInt(resolveLen(shOf('#q{border-top-left-radius:9px;border-radius:2px}', plainDiv).radiusTopLeftX, 100, -1),
           2, 'a later `border-radius` beats an earlier corner longhand')
checkEqInt(resolveLen(shOf('#q{border-radius:2px;border-top-left-radius:9px}', plainDiv).radiusTopLeftX, 100, -1),
           9, 'and the other order gives the other answer')
checkEqInt(resolveLen(shOf('#q{border-top-left-radius:9px;border-radius:2px}', plainDiv).radiusBottomRightX, 100, -1),
           2, 'while the shorthand still sets every corner')

// outline against its three longhands.
checkEqInt(shOf('#q{outline-color:#ff0000;outline:2px solid #0000ff}', plainDiv).outlineColor,
           packColor(0, 0, 255, 255), 'a later `outline` beats an earlier `outline-color`')
checkEqInt(shOf('#q{outline:2px solid #0000ff;outline-color:#ff0000}', plainDiv).outlineColor,
           packColor(255, 0, 0, 255), 'and the other order gives the other answer')
checkEqInt(shOf('#q{outline-width:9px;outline:solid #0000ff}', plainDiv).outlineWidth,
           3, 'the shorthand resets a width it does not name to medium')
checkEqInt(shOf('#q{outline-style:dotted;outline:2px #0000ff}', plainDiv).outlineStyle,
           BORDER_NONE, 'and a style it does not name to none')

// flex against its three longhands.
checkEqInt(Math.round(shOf('#q{flex-grow:7;flex:2 3 40px}', flexKid).flexGrow),
           2, 'a later `flex` beats an earlier `flex-grow`')
checkEqInt(Math.round(shOf('#q{flex:2 3 40px;flex-grow:7}', flexKid).flexGrow),
           7, 'and the other order gives the other answer')
checkEqInt(resolveLen(shOf('#q{flex-basis:40px;flex:2}', flexKid).flexBasis, 100, -1),
           0, '`flex: 2` zeroes a basis the shorthand does not name')
checkEqInt(Math.round(shOf('#q{flex-shrink:7;flex:2}', flexKid).flexShrink),
           1, 'and resets the shrink to one')

// flex-flow against flex-direction and flex-wrap.
checkEqInt(shOf('#q{display:flex;flex-direction:column;flex-flow:row wrap}', plainDiv).flexDirection,
           FLEX_ROW, 'a later `flex-flow` beats an earlier `flex-direction`')
checkEqInt(shOf('#q{display:flex;flex-flow:row wrap;flex-direction:column}', plainDiv).flexDirection,
           FLEX_COLUMN, 'and the other order gives the other answer')
checkEqInt(shOf('#q{display:flex;flex-wrap:wrap;flex-flow:column}', plainDiv).flexWrap,
           FLEXWRAP_NOWRAP, 'and it resets the wrap it does not name')

// gap against row-gap and column-gap.
checkEqInt(shOf('#q{display:grid;row-gap:9px;gap:2px}', plainDiv).rowGap,
           2, 'a later `gap` beats an earlier `row-gap`')
checkEqInt(shOf('#q{display:grid;gap:2px;row-gap:9px}', plainDiv).rowGap,
           9, 'and the other order gives the other answer')
checkEqInt(shOf('#q{display:grid;gap:2px}', plainDiv).columnGap,
           2, 'and one value sets both axes')

// font-variant against font-variant-caps.
checkEqInt(fontCapsOf(shOf('#q{font-variant-caps:small-caps;font-variant:normal}', plainDiv)),
           CAPS_NORMAL, 'a later `font-variant` beats an earlier `font-variant-caps`')
checkEqInt(fontCapsOf(shOf('#q{font-variant:normal;font-variant-caps:small-caps}', plainDiv)),
           CAPS_SMALL, 'and the other order gives the other answer')
checkEqInt(fontCapsOf(shOf('#q{font-variant:small-caps}', plainDiv)),
           CAPS_SMALL, 'while the shorthand still sets the caps')

// text-box against text-box-trim and text-box-edge.
checkEqInt(Math.floorDiv(textBoxPacked(shOf('#q{text-box-trim:trim-start;text-box:trim-both cap alphabetic}', plainDiv)), 16),
           TBTRIM_BOTH, 'a later `text-box` beats an earlier `text-box-trim`')
checkEqInt(Math.floorDiv(textBoxPacked(shOf('#q{text-box:trim-both cap alphabetic;text-box-trim:trim-start}', plainDiv)), 16),
           TBTRIM_START, 'and the other order gives the other answer')
checkEqInt(textBoxPacked(shOf('#q{text-box-edge:cap alphabetic;text-box:trim-both}', plainDiv)) % 16,
           TBOVER_TEXT * 4 + TBUNDER_TEXT, 'and it resets the edge it does not name')
// An edge with no trim keyword means `trim-both`, which is the one
// place the shorthand is not simply two values side by side.
checkEqInt(Math.floorDiv(textBoxPacked(shOf('#q{text-box:cap alphabetic}', plainDiv)), 16),
           TBTRIM_BOTH, 'an edge alone in the shorthand still trims both')

// overscroll-behavior against its two axes.
checkEqInt(overscrollX(shOf('#q{overscroll-behavior-x:none;overscroll-behavior:contain}', scrollBox)),
           OSB_CONTAIN, 'a later `overscroll-behavior` beats an earlier axis longhand')
checkEqInt(overscrollX(shOf('#q{overscroll-behavior:contain;overscroll-behavior-x:none}', scrollBox)),
           OSB_NONE, 'and the other order gives the other answer')
checkEqInt(overscrollY(shOf('#q{overscroll-behavior:contain}', scrollBox)),
           OSB_CONTAIN, 'one value sets both axes')
checkEqInt(overscrollY(shOf('#q{overscroll-behavior:contain none}', scrollBox)),
           OSB_NONE, 'and two set them separately')

// The logical spellings are the same two properties under other names,
// so they have to occupy the same keys or whichever the reader asks
// for last always wins. In a horizontal writing mode the inline axis
// is the horizontal one, which is what Chromium answers.
checkEqInt(overscrollX(shOf('#q{overscroll-behavior-inline:none}', scrollBox)),
           OSB_NONE, '`overscroll-behavior-inline` is the horizontal axis')
checkEqInt(overscrollY(shOf('#q{overscroll-behavior-inline:none}', scrollBox)),
           OSB_AUTO, 'and leaves the vertical one alone')
checkEqInt(overscrollY(shOf('#q{overscroll-behavior-block:none}', scrollBox)),
           OSB_NONE, '`overscroll-behavior-block` is the vertical axis')
checkEqInt(overscrollX(shOf('#q{overscroll-behavior-x:contain;overscroll-behavior-inline:none}', scrollBox)),
           OSB_NONE, 'a later logical spelling beats an earlier physical one')
checkEqInt(overscrollX(shOf('#q{overscroll-behavior-inline:none;overscroll-behavior-x:contain}', scrollBox)),
           OSB_CONTAIN, 'and the other order gives the other answer')
checkEqInt(overscrollX(shOf('#q{overscroll-behavior:contain;overscroll-behavior-inline:none}', scrollBox)),
           OSB_NONE, 'and the shorthand takes its place in the same order')
checkEqInt(overscrollX(shOf('#q{overscroll-behavior-inline:none;overscroll-behavior:contain}', scrollBox)),
           OSB_CONTAIN, 'either way round')

finish('cascade rules')
