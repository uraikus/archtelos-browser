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

finish('cascade rules')
