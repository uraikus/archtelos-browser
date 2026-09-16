// CSS Nesting 1: a style rule inside a style rule, the `&` nesting
// selector that stands for the rule it is in, and the relative form
// that implies one.
//
// Every expectation here is Chromium 141's, read with getComputedStyle
// off the same stylesheet and the same document. `background-color` is
// the probe because it does not inherit: a rule that should not have
// matched cannot be hidden by one that matched an ancestor.
import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

// One document for every case. The names are short because each one is
// written many times: `w` wraps everything, `a` is the element a nested
// rule usually hangs off, `b` and `c` are what it reaches, `s` is a
// sibling of an `a` rather than a descendant, and `zz`/`x1` exist so a
// flat rule can compete with a nested one at a chosen specificity.
const text NEST_HEAD = '<html><head><style>'
const text NEST_TAIL = '</style></head><body>'
    + '<div class="w">'
    + '<div class="a" id="x"><span class="b" id="b1" data-q="1">b</span><i class="c" id="c1">c</i></div>'
    + '<div class="s" id="s1">s</div>'
    + '<div class="a" id="a2"><div class="b" id="b3"><em class="c" id="c2">d</em></div></div>'
    + '<div class="b" id="b2">o</div>'
    + '</div>'
    + '<div class="zz"><div class="a x1" id="ia"><span class="b" id="b4">q</span></div></div>'
    + '</body></html>'

Node func nestNodeById(n:Node, id:text) {
    if n.kind == NODE_ELEMENT && n.attrs['id'] == id { return n }
    for int i = 0, i < n.children.length, i++ {
        Node found = nestNodeById(n.children[i], id)
        if found != null { return found }
    }
    return null
}

// The document is reparsed per case rather than per check, so a case
// with several expectations is one parse and one cascade.
Node nestDoc = null

void func nestStyle(css:text) {
    cascadeReset()
    nestDoc = parseHtmlText(NEST_HEAD + css + NEST_TAIL)
    cascadeAddDocumentStyles(nestDoc)
    computeStyles(nestDoc)
}

int nestNone = packColor(0, 0, 0, 0)

// `n` is the red channel, which is how each rule in a case is told
// apart: every declaration is `background: rgb(n, 0, 0)`.
int func nestRed(n:int) { return packColor(n, 0, 0, 255) }

void func nestBgIs(id:text, want:int, label:text) {
    Node e = nestNodeById(nestDoc, id)
    if e == null {
        checksFailed++
        log(`FAIL: ${label}: no element #${id}`)
        return
    }
    int got = e.style.background
    if got == want { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: #${id} is rgba(${colorRed(got)}, ${colorGreen(got)}, ${colorBlue(got)}, ${colorAlpha(got)})`)
    }
}

// ---- 1. a nested rule is a descendant rule -----------------------------
// The parent's own declarations still apply to the parent, and the
// nested rule's apply to what its selector reaches below it.
nestStyle('.a { background: rgb(1, 0, 0); .b { background: rgb(2, 0, 0) } }')
nestBgIs('x', nestRed(1), 'the parent declarations style the parent')
nestBgIs('b1', nestRed(2), 'the nested rule styles a descendant')
nestBgIs('b3', nestRed(2), 'and one nested deeper')
nestBgIs('c1', nestNone, 'and nothing the nested selector does not match')
nestBgIs('b2', nestNone, 'and no .b outside the parent')

// ---- 2. `&` stands for the rule it is in -------------------------------
nestStyle('.a { & .b { background: rgb(3, 0, 0) } }')
nestBgIs('b1', nestRed(3), '`& .b` is `.a .b`')
nestBgIs('b2', nestNone, 'and reaches no .b outside .a')

// A nested selector with no `&` gets one, as a descendant.
nestStyle('.a { .b { background: rgb(4, 0, 0) } }')
nestBgIs('b1', nestRed(4), 'a nested selector implies a descendant `&`')

// `&` in the middle or at the end is where it is written, not prepended.
nestStyle('.s { .w & { background: rgb(5, 0, 0) } }')
nestBgIs('s1', nestRed(5), '`.w &` is `.w .s`')
nestStyle('.b { .w & { background: rgb(6, 0, 0) } }')
nestBgIs('b1', nestRed(6), '`.w &` reaches every .b under .w')
nestBgIs('b2', nestRed(6), 'including one that is not under an .a')
nestBgIs('b4', nestNone, 'and none outside .w')

// `&` alone is the parent itself.
nestStyle('.a { & { background: rgb(7, 0, 0) } }')
nestBgIs('x', nestRed(7), '`&` alone styles the parent')
nestBgIs('b1', nestNone, 'and nothing below it')

// Appended to `&`, a compound selector joins the parent's own compound.
nestStyle('.a { &.x1 { background: rgb(8, 0, 0) } }')
nestBgIs('ia', nestRed(8), '`&.x1` is `.a.x1`')
nestBgIs('x', nestNone, 'and does not match an .a without .x1')
nestStyle('.a { &:first-child { background: rgb(9, 0, 0) } }')
nestBgIs('x', nestRed(9), '`&:first-child` is `.a:first-child`')
nestBgIs('a2', nestNone, 'and not an .a that is not one')

// `&` that matches nothing matches nothing: `.a .a` has no instance.
nestStyle('.a { & & { background: rgb(10, 0, 0) } }')
nestBgIs('x', nestNone, '`& &` is `.a .a`, which nothing here is')

// ---- 3. a relative selector implies the `&` ----------------------------
nestStyle('.a { > .b { background: rgb(11, 0, 0) } }')
nestBgIs('b1', nestRed(11), 'a leading child combinator gets an `&`')
nestBgIs('c2', nestNone, 'and stays a child combinator')
nestStyle('.a { ~ .s { background: rgb(12, 0, 0) } }')
nestBgIs('s1', nestRed(12), 'a leading sibling combinator gets one too')
nestStyle('.a { + .s { background: rgb(13, 0, 0) } }')
nestBgIs('s1', nestRed(13), 'and a leading adjacent combinator')

// A type selector, an attribute selector and a list all nest.
nestStyle('.a { span { background: rgb(14, 0, 0) } }')
nestBgIs('b1', nestRed(14), 'a nested type selector')
nestBgIs('c1', nestNone, 'matches only that type')
nestStyle('.a { [data-q] { background: rgb(15, 0, 0) } }')
nestBgIs('b1', nestRed(15), 'a nested attribute selector')
nestBgIs('b3', nestNone, 'matches only what carries the attribute')
nestStyle('.a { .b, .c { background: rgb(16, 0, 0) } }')
nestBgIs('b1', nestRed(16), 'a nested selector list, first branch')
nestBgIs('c1', nestRed(16), 'a nested selector list, second branch')

// ---- 4. nesting nests ---------------------------------------------------
nestStyle('.a { .b { .c { background: rgb(17, 0, 0) } } }')
nestBgIs('c2', nestRed(17), 'three levels deep')
nestBgIs('c1', nestNone, 'and the middle level is required')
nestStyle('.a { & .b { & .c { background: rgb(18, 0, 0) } } }')
nestBgIs('c2', nestRed(18), 'three levels deep, written with `&`')

// ---- 5. where a nested rule falls in source order ------------------------
// A nested rule is at the point it is written, so a flat rule after it
// at the same specificity wins and one before it loses.
nestStyle('.a { .b { background: rgb(19, 0, 0) } } .a .b { background: rgb(20, 0, 0) }')
nestBgIs('b1', nestRed(20), 'a flat rule after a nested one wins')
nestStyle('.a .b { background: rgb(21, 0, 0) } .a { .b { background: rgb(22, 0, 0) } }')
nestBgIs('b1', nestRed(22), 'and before it, loses')
nestStyle('.a { & .b { background: rgb(23, 0, 0) } & .b { background: rgb(24, 0, 0) } }')
nestBgIs('b1', nestRed(24), 'two nested rules order among themselves')

// A declaration written after a nested rule cascades after it, which is
// the whole reason the parent's declarations cannot be gathered into one
// rule and emitted at the top.
nestStyle('.a { & { background: rgb(25, 0, 0) } background: rgb(26, 0, 0) }')
nestBgIs('x', nestRed(26), 'a declaration after a nested rule wins')
nestStyle('.a { background: rgb(27, 0, 0); & { background: rgb(28, 0, 0) } }')
nestBgIs('x', nestRed(28), 'and before it, loses')
nestStyle('.a { background: rgb(29, 0, 0); .b { background: rgb(30, 0, 0) } background: rgb(31, 0, 0) }')
nestBgIs('x', nestRed(31), 'declarations on both sides of a nested rule')
nestBgIs('b1', nestRed(30), 'and the nested rule between them')

// ---- 6. `&` takes the specificity of the whole parent list ---------------
// This is the case textual substitution gets wrong. `.a, #ia` has an id
// in it, so `&` weighs (1,0,0) for *both* branches: an element that
// matched only through `.a` still beats a later `.w .b`, which has the
// two classes that `.a .b` would have had.
nestStyle('.a, #ia { .b { background: rgb(32, 0, 0) } } .w .b { background: rgb(33, 0, 0) }')
nestBgIs('b1', nestRed(32), '`&` weighs the most specific branch of the list')
nestBgIs('b4', nestRed(32), 'for the branch that supplied that weight too')
nestBgIs('b2', nestRed(33), 'and the flat rule still styles what nesting missed')
// The same shape without the id: now the flat rule is later and equal,
// so it wins. Without this row the one above proves nothing, because an
// engine that gave every nested rule an id would pass it.
nestStyle('.a .b { background: rgb(34, 0, 0) } .w .b { background: rgb(35, 0, 0) }')
nestBgIs('b1', nestRed(35), 'at equal specificity the later flat rule wins')
nestStyle('#ia { .b { background: rgb(36, 0, 0) } } .x1 .b { background: rgb(37, 0, 0) }')
nestBgIs('b4', nestRed(36), 'an id parent outweighs two classes after it')

// !important is unaffected: it beats a nested declaration as it beats
// any other normal one.
nestStyle('.a .b { background: rgb(38, 0, 0) !important } .a { .b { background: rgb(39, 0, 0) } }')
nestBgIs('b1', nestRed(38), 'important beats a nested declaration')

// ---- 7. at-rules nest, in both directions --------------------------------
nestStyle('.a { @media (min-width: 1px) { .b { background: rgb(40, 0, 0) } } }')
nestBgIs('b1', nestRed(40), 'a style rule inside a nested @media')
// Declarations directly inside a nested at-rule belong to the parent.
nestStyle('.a { @media (min-width: 1px) { background: rgb(41, 0, 0) } }')
nestBgIs('x', nestRed(41), 'declarations inside a nested @media are the parent\'s')
nestStyle('.a { @media (min-width: 99999px) { background: rgb(42, 0, 0) } }')
nestBgIs('x', nestNone, 'and a query that does not match drops them')
nestStyle('.a { @supports (color: red) { .b { background: rgb(43, 0, 0) } } }')
nestBgIs('b1', nestRed(43), 'a nested @supports')
nestStyle('@layer L1, L2; .a { @layer L1 { .b { background: rgb(44, 0, 0) } } }'
    + ' @layer L2 { .a .b { background: rgb(45, 0, 0) } }')
nestBgIs('b1', nestRed(45), 'a nested @layer puts the rule in that layer')

// ---- 8. an invalid nested rule is dropped, and nothing else is -----------
nestStyle('.a { ?? { background: rgb(46, 0, 0) } background: rgb(47, 0, 0) }')
nestBgIs('x', nestRed(47), 'an unparseable nested selector loses only its own rule')
nestBgIs('b1', nestNone, 'and that rule is dropped')
// An empty nested rule is not an error either.
nestStyle('.a { .b { } background: rgb(48, 0, 0) }')
nestBgIs('x', nestRed(48), 'an empty nested rule is skipped')

// A brace inside a string is not the start of a nested rule.
nestStyle('.a { background: rgb(49, 0, 0); background-image: url("x{y") }')
nestBgIs('x', nestRed(49), 'a brace inside a string is not a nested rule')

// ---- 9. `&` at the top of a stylesheet is the root -----------------------
// Outside any rule `&` is `:scope`, which for a stylesheet is the root
// element, so `& .b` reaches every .b in the document.
nestStyle('& .b { background: rgb(50, 0, 0) }')
nestBgIs('b1', nestRed(50), 'a top-level `&` is the root element')
nestBgIs('b2', nestRed(50), 'so it reaches every .b')

finish('nesting')
