// A CSS parser: stylesheets into rules, rules into selector lists and
// declarations. Works on `ascii` throughout (see util/text.f for why).
// Supported selector syntax: type, universal, #id, .class,
// [attr], [attr=v], [attr~=v], [attr^=v], [attr$=v], [attr*=v],
// the descendant / child / adjacent / general-sibling combinators,
// and the pseudo-classes :first-child, :last-child, :only-child,
// :nth-child(odd|even|N), :root, :link, :any-link, :not(<compound>).
// A selector using anything else never matches, which is what a real
// browser does with a selector it does not understand.

import ../util/text.f
import counterstyles.f
import page.f

const int COMB_NONE = 0
const int COMB_DESCENDANT = 1
const int COMB_CHILD = 2
const int COMB_ADJACENT = 3
const int COMB_SIBLING = 4

const int ATTR_EXISTS = 0
const int ATTR_EQUALS = 1
const int ATTR_INCLUDES = 2
const int ATTR_PREFIX = 3
const int ATTR_SUFFIX = 4
const int ATTR_SUBSTRING = 5
const int ATTR_DASH = 6

struct AttrSel {
    name:text
    op:int
    value:text
    caseInsensitive:bool    // the `i` flag after the value
}

// `:not()`, `:is()`, `:where()` and `:has()` each take a comma-separated
// list of selectors. They differ in what a match means: `:not()` wants
// none to match, `:is()` and `:where()` want any, and `:has()` wants a
// descendant to match. `:where()` alone contributes no specificity,
// which is its whole reason for existing beside `:is()`.
const int SUBSEL_NOT = 0
const int SUBSEL_IS = 1
const int SUBSEL_WHERE = 2
const int SUBSEL_HAS = 3

struct SubSelector {
    kind:int
    // Selectors 4 §3.1 gives `:is()`, `:where()`, `:not()` and `:has()`
    // a <complex-selector-list>, not a list of compounds, so each
    // alternative is a whole selector: `:is(div > p)` is one of them.
    alternatives:arr[Selector]
    // `:has()`'s argument is a *relative* selector list, so each
    // alternative may open with a combinator naming how the match
    // stands to the element being tested: COMB_CHILD for `:has(> p)`,
    // COMB_ADJACENT for `:has(+ p)`, COMB_SIBLING for `:has(~ p)`, and
    // COMB_DESCENDANT for the bare `:has(p)`. One per alternative,
    // because `:has(> p, + div)` names two different relations and
    // Chromium answers both.
    leads:arr[int]
}

// `:nth-child( <An+B> of <complex-selector-list> )` and its
// `:nth-last-child()` twin (Selectors 4 §6.6.5). The `of` clause filters
// *which siblings are counted* before An+B is applied to the position,
// so `:nth-child(2 of .lead)` is the second `.lead` among its siblings
// rather than a `.lead` that happens to be second.
//
// It is a list of its own rather than another entry in `pseudos`,
// because `pseudos` holds text and this needs whole selectors. A
// compound with no `of` clause has an empty one, and the matcher is
// guarded by its length -- the plain `:nth-child(2n+1)` still goes
// through `pseudos` and costs exactly what it did.
struct NthOf {
    fromEnd:bool
    stepA:int
    offB:int
    of:arr[Selector]
}

struct Compound {
    tag:text                // '' = any
    // The namespace part, which is whatever stood before a `|`.
    // NS_ANY is `*|`, NS_NONE is a bare `|`, NS_PREFIX names one that
    // was declared, and NS_DEFAULT is a selector with no `|` at all --
    // which matches any namespace until an `@namespace` with no prefix
    // says otherwise.
    nsKind:int
    nsUri:text
    id:text                 // '' = none
    classes:arr[text]
    attrs:arr[AttrSel]
    pseudos:arr[text]       // e.g. 'first-child', 'nth-child:2:1'
    pseudoElement:text      // '' = none; 'before', 'after', 'first-letter', 'first-line', 'marker'
    // The functional pseudo-classes that take a selector list of their
    // own: `:not()`, `:is()`, `:where()` and `:has()`. One list serves
    // all four because they differ only in how a match is read, which
    // is what `kind` says.
    subs:arr[SubSelector]
    // The `:nth-child()`s that carry an `of` clause; see NthOf.
    nths:arr[NthOf]
    combinator:int          // relation to the compound on its LEFT
    unsupported:bool
}

struct Selector {
    parts:arr[Compound]     // left to right
    specificity:int         // packed base 1024: see packSpecificity
    unsupported:bool
    // The pseudo-element of the rightmost compound, if any. A rule with
    // one does not style the element it matches: it describes a box
    // generated before or after that element's content (CSS2 §12.1),
    // so the cascade collects it separately.
    pseudoElement:text
}

int declSerialNext = 1

struct Decl {
    name:text
    value:ascii
    important:bool
    // Identifies this declaration for the computed-style cache. A
    // declaration parsed from a stylesheet gets a serial and keeps it;
    // one synthesized per element (a presentational hint, an inline
    // style) keeps 0, and the cache keys on its name and value instead.
    serial:int
}

struct Rule {
    selectors:arr[Selector]
    decls:arr[Decl]
    order:int               // source order across every sheet
    // Which cascade layer this rule is in, as an index into
    // cssLayerNames, or CASCADE_NO_LAYER for a rule in none.
    layer:int
    // The `@container` query that gates this rule, as an index into
    // cssContainerQueryConds, or CQ_NONE. A query cannot be answered
    // until a box tree exists, so the rule is stored like any other and
    // the answer is asked for at match time.
    containerQuery:int
}

struct Stylesheet {
    rules:arr[Rule]
}

int cssRuleCounter = 0
// CSS Namespaces 3. Every element in an HTML document is in the XHTML
// namespace, so a namespace part is a question about one string.
const int NS_DEFAULT = 0    // no `|` in the selector at all
const int NS_ANY = 1        // `*|`
const int NS_NONE = 2       // a bare `|`
const int NS_PREFIX = 3     // a declared prefix, its URI in nsUri
const int NS_UNKNOWN = 4    // a prefix nobody declared: the selector is invalid

const text XHTML_NS = 'http://www.w3.org/1999/xhtml'

// The prefixes an `@namespace` rule declared, and the default one.
map[text] cssNamespacePrefixes = {}
text cssDefaultNamespace = ''

// CSS Cascade 5's layers. A layer is declared the first time it is
// named -- by a `@layer a, b;` statement or by a `@layer a { }` block --
// and its place in this list is its place in the cascade: of two
// layered declarations the one in the later layer wins, and a
// declaration in no layer beats both. `!important` reverses all of it,
// which the weight below does rather than this list.
//
// A rule in no layer carries CASCADE_NO_LAYER, which ranks above every
// layer index. Only 256 layers are kept apart, because the weight packs
// the layer into a field beside the origin and the specificity and that
// field has to end somewhere; a sheet with more competes on specificity
// from there on.
// ---- CSS Conditional 4: container queries ----------------------------
//
// A `@container` rule asks about the size of an ancestor, which layout
// knows and the cascade does not. So the rules inside one are parsed
// into the sheet like any others, each carrying the index of the query
// that gates it, and nothing is evaluated here: layoutDocument answers
// the queries once it has a box tree and runs the cascade again.
//
// A query nested inside another holds only if the outer one does, which
// is what `parent` is for -- satisfaction walks the chain rather than
// this keeping a list per rule.
const int CQ_NONE = -1
const int CQ_MAX = 64
arr[text] cssContainerQueryNames = []
arr[text] cssContainerQueryConds = []
arr[int] cssContainerQueryParent = []
int cssCurrentContainerQuery = CQ_NONE
bool cssSawContainerQuery = false

void func cssResetContainerQueries() {
    arr[text] emptyNames = []
    arr[text] emptyConds = []
    arr[int] emptyParents = []
    cssContainerQueryNames = emptyNames
    cssContainerQueryConds = emptyConds
    cssContainerQueryParent = emptyParents
    cssCurrentContainerQuery = CQ_NONE
    cssSawContainerQuery = false
}

// Splits a `@container` prelude into its optional name and its
// condition. A prelude that starts with `(` or with `not (` has no
// name; anything else begins with one.
text cqSplitName = ''
text func containerPreludeCondition(prelude:ascii) {
    cqSplitName = ''
    ascii p = asciiTrim(prelude)
    if p.length == 0 { return '' }
    if p.charCodeAt(0) == CH_LPAREN { return p.toText() }
    int i = 0
    while i < p.length && isNameCode(p.charCodeAt(i)) { i++ }
    if i == 0 { return p.toText() }
    ascii first = asciiLower(p.slice(0, i))
    ascii rest = asciiTrim(p.slice(i, p.length))
    // `not` is part of the condition, never a container's name.
    if first == 'not' { return p.toText() }
    cqSplitName = first.toText()
    return rest.toText()
}

// Whether a condition asks anything about the block axis. A container
// that contains only its inline size cannot answer one -- Chromium
// matches no height query against `container-type: inline-size`
// however tall the box is -- so the query fails rather than being
// answered from a size nothing is holding still.
bool func conditionNeedsBlockAxis(cond:text) {
    ascii c = asciiLower(cond.toAscii())
    if c == null { return false }
    return asciiIndexOf(c, 'height', 0) >= 0
        || asciiIndexOf(c, 'block-size', 0) >= 0
        || asciiIndexOf(c, 'aspect-ratio', 0) >= 0
        || asciiIndexOf(c, 'orientation', 0) >= 0
}

int func declareContainerQuery(name:text, cond:text) {
    if cssContainerQueryNames.length >= CQ_MAX { return CQ_NONE }
    cssContainerQueryNames.push(name)
    cssContainerQueryConds.push(cond)
    cssContainerQueryParent.push(cssCurrentContainerQuery)
    cssSawContainerQuery = true
    return cssContainerQueryNames.length - 1
}

const int CASCADE_MAX_LAYERS = 256
const int CASCADE_NO_LAYER = 256

arr[text] cssLayerNames = []
map[int] cssLayerIndex = {}
// The layer the rules being parsed are in, and its full dotted name, so
// `@layer b` inside `@layer a` is the layer `a.b`.
int cssCurrentLayer = CASCADE_NO_LAYER
text cssCurrentLayerName = ''
int cssAnonymousLayers = 0

// The place each declared layer takes in the cascade, which is not the
// order it was declared in: CSS Cascade 5 nests `a.b` inside `a`, so
// the sub-layer takes `a`'s place in the outer order, and within `a`
// the sub-layers come first and `a`'s own rules last. A rule is stamped
// with the layer's declaration index, and this turns that into the rank
// the weight is built from.
arr[int] cssLayerRank = []

void func cssResetLayers() {
    arr[text] emptyNames = []
    map[int] emptyIndex = {}
    arr[int] emptyRank = []
    cssLayerNames = emptyNames
    cssLayerIndex = emptyIndex
    cssLayerRank = emptyRank
    cssCurrentLayer = CASCADE_NO_LAYER
    cssCurrentLayerName = ''
    cssAnonymousLayers = 0
}

// The declaration indices of a layer and every layer it is nested in,
// outermost first. `declareLayer` declares every ancestor before the
// layer itself, so each of them is known here.
arr[int] func cssLayerPath(at:int) {
    arr[int] path = []
    ascii full = cssLayerNames[at].toAscii()
    for int i = 0, i < full.length, i++ {
        if full.charCodeAt(i) != CH_DOT { continue }
        int anc = cssLayerIndex[full.slice(0, i).toText()]
        if anc != null { path.push(anc) }
    }
    path.push(at)
    return path
}

// Which of two layers comes first. The paths are compared term by term,
// and where one is a prefix of the other the **deeper** one comes
// first, because a layer's own rules come after everything nested in
// it.
int func cssComparePaths(a:arr[int], b:arr[int]) {
    int m = a.length < b.length ? a.length : b.length
    for int i = 0, i < m, i++ {
        if a[i] != b[i] { return a[i] < b[i] ? 0 - 1 : 1 }
    }
    if a.length == b.length { return 0 }
    return a.length > b.length ? 0 - 1 : 1
}

// Computes `cssLayerRank`. Called once before a cascade pass rather
// than as layers are declared, because a layer's place depends on
// layers that may not have been named yet. A page with no `@layer` on
// it returns on the first line.
void func cssComputeLayerRanks() {
    int n = cssLayerNames.length
    arr[int] ranks = []
    if n == 0 { cssLayerRank = ranks  return }
    arr[arr[int]] paths = []
    arr[int] order = []
    for int i = 0, i < n, i++ {
        paths.push(cssLayerPath(i))
        order.push(i)
        ranks.push(0)
    }
    // n is at most CASCADE_MAX_LAYERS, so an insertion sort is the
    // right shape: it runs once per document and never on a page with
    // no layers.
    for int i = 1, i < n, i++ {
        int cur = order[i]
        int j = i - 1
        while j >= 0 && cssComparePaths(paths[order[j]], paths[cur]) > 0 {
            order[j + 1] = order[j]
            j--
        }
        order[j + 1] = cur
    }
    for int i = 0, i < n, i++ { ranks[order[i]] = i }
    cssLayerRank = ranks
}

// The rank of a layer, or the layer itself where no ranks have been
// computed -- which is what `CASCADE_NO_LAYER` and a direct call to
// `matchWeight` both want.
int func cssLayerRankOf(layer:int) {
    if layer < 0 || layer >= cssLayerRank.length { return layer }
    return cssLayerRank[layer]
}

// The index of a layer, declaring it -- and every layer it is nested in
// -- if this is the first time it has been named.
int func declareLayer(name:text) {
    if name == '' { return CASCADE_NO_LAYER }
    int known = cssLayerIndex[name]
    if known != null { return known }
    // `a.b` implies `a`, and `a` has to be declared first: it is the
    // outer layer, and the standard orders an outer layer before what
    // is nested in it.
    ascii full = name.toAscii()
    int dot = -1
    for int i = 0, i < full.length, i++ {
        if full.charCodeAt(i) == CH_DOT { dot = i }
    }
    if dot > 0 { declareLayer(full.slice(0, dot).toText()) }
    if cssLayerNames.length >= CASCADE_MAX_LAYERS { return CASCADE_MAX_LAYERS - 1 }
    int at = cssLayerNames.length
    cssLayerNames.push(name)
    cssLayerIndex[name] = at
    return at
}

// The full name of a layer written inside the one being parsed.
text func qualifiedLayerName(name:text) {
    if cssCurrentLayerName == '' { return name }
    return cssCurrentLayerName + '.' + name
}

void func cssResetNamespaces() {
    map[text] empty = {}
    cssNamespacePrefixes = empty
    cssDefaultNamespace = ''
}

// The body of an `@counter-style` rule.
CounterStyle func parseCounterStyleBody(body:ascii) {
    CounterStyle c
    c.system = CS_SYMBOLIC
    c.suffix = '. '
    c.firstValue = 1
    c.defined = true
    arr[ascii] decls = splitOnSemicolons(body)
    for int i = 0, i < decls.length, i++ {
        int colon = asciiIndexOf(decls[i], ':', 0)
        if colon < 0 { continue }
        text name = asciiLower(asciiTrim(decls[i].slice(0, colon))).toText()
        ascii value = asciiTrim(decls[i].slice(colon + 1, decls[i].length))
        if name == 'system' {
            arr[ascii] st = namespacePreludeTokens(value)
            if st.length == 0 { continue }
            text sys = asciiLower(st[0]).toText()
            if sys == 'cyclic' { c.system = CS_CYCLIC }
            else if sys == 'fixed' {
                c.system = CS_FIXED
                if st.length > 1 {
                    int v = st[1].toText().toInt()
                    if v != null { c.firstValue = v }
                }
            }
            else if sys == 'symbolic' { c.system = CS_SYMBOLIC }
            else if sys == 'alphabetic' { c.system = CS_ALPHABETIC }
            else if sys == 'numeric' { c.system = CS_NUMERIC }
            else if sys == 'additive' { c.system = CS_ADDITIVE }
        } else if name == 'symbols' {
            arr[ascii] syms = namespacePreludeTokens(value)
            for int k = 0, k < syms.length, k++ { c.symbols.push(unquoteCssString(syms[k])) }
        } else if name == 'additive-symbols' {
            // `weight symbol` pairs, separated by commas
            arr[ascii] pairs = splitOnCommas(value)
            for int k = 0, k < pairs.length, k++ {
                arr[ascii] parts = namespacePreludeTokens(asciiTrim(pairs[k]))
                if parts.length < 2 { continue }
                int w = parts[0].toText().toInt()
                if w == null { continue }
                c.addValues.push(w)
                c.addSymbols.push(unquoteCssString(parts[1]))
            }
        } else if name == 'suffix' {
            c.suffix = unquoteCssString(value)
        } else if name == 'prefix' {
            c.prefix = unquoteCssString(value)
        } else if name == 'pad' {
            arr[ascii] parts = namespacePreludeTokens(value)
            if parts.length >= 2 {
                int w = parts[0].toText().toInt()
                if w != null { c.padTo = w }
                c.padSymbol = unquoteCssString(parts[1])
            }
        } else if name == 'range' {
            // `[ <integer> | infinite ]{2}` -- the multi-range form is
            // not taken, because nothing measured says what this engine
            // should do with a gap between two of them.
            arr[ascii] parts = namespacePreludeTokens(value)
            if asciiLower(asciiTrim(value)) == 'auto' { c.hasRange = false }
            else if parts.length >= 2 {
                text lo = asciiLower(parts[0]).toText()
                text hi = asciiLower(parts[1]).toText()
                int a = lo == 'infinite' ? 0 - 1000000000 : lo.toInt()
                int b = hi == 'infinite' ? 1000000000 : hi.toInt()
                if a != null && b != null {
                    c.rangeMin = a
                    c.rangeMax = b
                    c.hasRange = true
                }
            }
        } else if name == 'fallback' {
            arr[ascii] parts = namespacePreludeTokens(value)
            if parts.length >= 1 { c.fallback = asciiLower(parts[0]).toText() }
        } else if name == 'negative' {
            arr[ascii] parts = namespacePreludeTokens(value)
            if parts.length >= 1 { c.negPrefix = unquoteCssString(parts[0]) }
            if parts.length >= 2 { c.negSuffix = unquoteCssString(parts[1]) }
        }
    }
    return c
}

text func unquoteCssString(v:ascii) {
    ascii t = asciiTrim(v)
    if t.length < 2 { return t.toText() }
    int first = t.charCodeAt(0)
    if (first == CH_QUOTE || first == CH_APOS) && t.charCodeAt(t.length - 1) == first {
        return t.slice(1, t.length - 1).toText()
    }
    return t.toText()
}

arr[ascii] func splitOnSemicolons(v:ascii) {
    arr[ascii] out = []
    int start = 0
    int depth = 0
    for int i = 0, i < v.length, i++ {
        int c = v.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN { depth-- }
        else if c == CH_SEMI && depth <= 0 {
            out.push(asciiTrim(v.slice(start, i)))
            start = i + 1
        }
    }
    out.push(asciiTrim(v.slice(start, v.length)))
    return out
}

arr[ascii] func splitOnCommas(v:ascii) {
    arr[ascii] out = []
    int start = 0
    int depth = 0
    for int i = 0, i < v.length, i++ {
        int c = v.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN { depth-- }
        else if c == CH_COMMA && depth <= 0 {
            out.push(asciiTrim(v.slice(start, i)))
            start = i + 1
        }
    }
    out.push(asciiTrim(v.slice(start, v.length)))
    return out
}

// The `@namespace` prelude, split on whitespace outside parentheses.
// Written here for the same reason as parseNamespaceUri below: the
// cascade's tokenizer is declared in the file that imports this one.
arr[ascii] func namespacePreludeTokens(v:ascii) {
    arr[ascii] out = []
    int n = v.length
    int i = 0
    while i < n {
        while i < n && isSpaceCode(v.charCodeAt(i)) { i++ }
        if i >= n { break }
        int start = i
        int depth = 0
        while i < n {
            int c = v.charCodeAt(i)
            // A quoted string is one token however it is spelled: a
            // `negative: "(" ")"` counts its parentheses otherwise, and
            // the two halves never come apart.
            if c == CH_QUOTE || c == CH_APOS {
                i = skipQuoted(v, i)
                continue
            }
            if c == CH_LPAREN { depth++ }
            else if c == CH_RPAREN { depth-- }
            else if isSpaceCode(c) && depth <= 0 { break }
            i++
        }
        out.push(v.slice(start, i))
    }
    return out
}

// The URI of an `@namespace` prelude: `url(...)` or a quoted string.
// The unwrapping is written here rather than shared with the cascade's
// because the cascade imports this file and not the other way round,
// and a global is only visible below its own declaration (FINDINGS.md,
// finding 9).
text func parseNamespaceUri(v:ascii) {
    ascii t = asciiTrim(v)
    if t.length == 0 { return '' }
    if asciiStartsWithLower(t, 'url(', 0) && t.charCodeAt(t.length - 1) == CH_RPAREN {
        t = asciiTrim(t.slice(4, t.length - 1))
        if t.length == 0 { return '' }
    }
    int first = t.charCodeAt(0)
    if t.length >= 2 && (first == CH_QUOTE || first == CH_APOS)
        && t.charCodeAt(t.length - 1) == first {
        return t.slice(1, t.length - 1).toText()
    }
    return t.toText()
}

// The viewport width @media queries are evaluated against; set by the
// browser before parsing author sheets.
int cssViewportWidth = 800
int cssViewportHeight = 600
// True only while a `@container` condition is being evaluated, which is
// done by pointing the two above at the container's content box and
// calling the media-condition evaluator: the grammar is the same one,
// and the range form, `and`, `or`, `not` and grouping come free.
bool cssAnsweringContainer = false
// The root element's computed font-size, which `rem` multiplies. The
// cascade assigns it when it computes the root; 16 is the initial value
// and the right answer before then.
int cssRootFontSize = 16
// The root element's computed line height, which `rlh` multiplies, and
// the line height of the element being computed, which `lh` does. Both
// are assigned by the cascade; 19 is what `normal` comes to at the
// initial 16px font size, and the right answer before then.
int cssRootLineHeight = 19
int cascadeLineHeight = 19

void func setCssViewport(w:int, h:int) {
    cssViewportWidth = w
    cssViewportHeight = h
}

// ---- comments and block skipping -----------------------------------

// Comments are consumed by the tokenizer (CSS Syntax 3 §4.3), so a
// `/*` is only a comment where a token can begin: not inside a string,
// and not inside an unquoted `url()`. A scan that did not know that
// turned `content: "/*"` into a comment running to the end of the
// stylesheet and dropped every rule after it.
//
// The other direction matters as much and is the easier one to get
// wrong: a comment ends at the FIRST `*/` whatever is inside it, so a
// quote there is ordinary text and `/* "*/` really does leave a string
// open. Chromium loses the rest of that sheet and so does this, which
// the suite asserts.
//
// A page with no comment in it at all pays one `asciiIndexOf`, as it
// did before.
ascii func stripCssComments(src:ascii) {
    if asciiIndexOf(src, '/*', 0) < 0 { return src }
    text out = ''
    int n = src.length
    int runStart = 0
    int i = 0
    // 0 outside anything, otherwise the character that ends the run:
    // a quote for a string, ')' for an unquoted url().
    int closer = 0
    // Built once rather than per character: this loop visits every byte
    // of every stylesheet, and an `ascii` allocated inside it would be
    // one allocation per byte.
    ascii urlOpen = 'url('.toAscii()
    while i < n {
        int c = src.charCodeAt(i)
        if closer != 0 {
            // A backslash escapes the next character inside a string.
            // An unquoted url() takes one too (§4.3.6), so both are
            // handled the same way here.
            if c == CH_BACKSLASH { i = i + 2  continue }
            if c == closer { closer = 0 }
            i++
            continue
        }
        if c == CH_QUOTE || c == CH_APOS { closer = c  i++  continue }
        // `url(` opens a run only when what follows is unquoted; a
        // quoted one is an ordinary string and the branch above takes
        // it at the quote.
        // The letter is tested first so that the prefix compare runs
        // only where it can match: `u` or `U` and nothing else.
        if (c == 117 || c == 85) && asciiStartsWithLower(src, urlOpen, i) {
            int j = i + 4
            while j < n && isSpaceCode(src.charCodeAt(j)) { j++ }
            if j < n && src.charCodeAt(j) != CH_QUOTE && src.charCodeAt(j) != CH_APOS {
                closer = CH_RPAREN
            }
            i = j
            continue
        }
        if c == CH_SLASH && i + 1 < n && src.charCodeAt(i + 1) == CH_STAR {
            if i > runStart {
                text run = src.slice(runStart, i).toText()
                out = out + run
            }
            int end = asciiIndexOf(src, '*/', i + 2)
            i = end < 0 ? n : end + 2
            runStart = i
            out = out + ' '
            continue
        }
        i++
    }
    if n > runStart {
        text tail = src.slice(runStart, n).toText()
        out = out + tail
    }
    return out.toAscii()
}

// Index just past the '}' that closes the block opened at `open`
// (which must point at a '{'); honors nested braces and quotes.
int func skipBlock(s:ascii, open:int) {
    int depth = 0
    int n = s.length
    int i = open
    while i < n {
        int c = s.charCodeAt(i)
        if c == CH_QUOTE || c == CH_APOS {
            i = skipQuoted(s, i)
            continue
        }
        if c == CH_LBRACE { depth++ }
        else if c == CH_RBRACE {
            depth--
            if depth == 0 { return i + 1 }
        }
        i++
    }
    return n
}

int func skipQuoted(s:ascii, at:int) {
    int q = s.charCodeAt(at)
    int n = s.length
    int i = at + 1
    while i < n {
        int c = s.charCodeAt(i)
        if c == CH_BACKSLASH {
            i = i + 2
            continue
        }
        if c == q { return i + 1 }
        i++
    }
    return n
}

// ---- declarations --------------------------------------------------

// Splits a declaration block body on top-level ';' and parses each
// `name: value` pair.
arr[Decl] func parseDeclarations(body:ascii) {
    arr[Decl] out = []
    int n = body.length
    int start = 0
    int depth = 0
    int i = 0
    while i <= n {
        int c = i < n ? body.charCodeAt(i) : CH_SEMI
        if i < n && (c == CH_QUOTE || c == CH_APOS) {
            i = skipQuoted(body, i)
            continue
        }
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN { depth-- }
        else if c == CH_SEMI && depth <= 0 {
            Decl d = parseOneDeclaration(body.slice(start, i))
            if d != null { out.push(d) }
            start = i + 1
        }
        i++
    }
    return out
}

Decl func parseOneDeclaration(piece:ascii) {
    int colon = asciiIndexOf(piece, ':', 0)
    if colon <= 0 { return null }
    ascii name = asciiLower(asciiTrim(piece.slice(0, colon)))
    if name.length == 0 { return null }
    // A custom property is kept -- it is a value other declarations
    // read through var() -- but a vendor prefix is not something this
    // engine paints.
    if name.charCodeAt(0) == CH_MINUS
        && !(name.length > 1 && name.charCodeAt(1) == CH_MINUS) { return null }
    ascii value = asciiTrim(piece.slice(colon + 1, piece.length))
    bool important = false
    int bang = asciiIndexOf(value, '!', 0)
    if bang >= 0 {
        ascii rest = asciiLower(asciiTrim(value.slice(bang + 1, value.length)))
        if rest == 'important' {
            important = true
            value = asciiTrim(value.slice(0, bang))
        }
    }
    if value.length == 0 { return null }
    Decl d
    d.name = name.toText()
    // Whether this document has ever said one of CSS2's three page-break
    // properties. `applyDecl` runs once per matched declaration -- 11,614
    // of them on the benchmark page -- so the three name comparisons that
    // rename them are worth a millisecond there, and a page that never
    // says one pays a single boolean instead. See cascadeReset, which
    // clears it with everything else the document put here.
    if asciiStartsWith(name, 'page-break', 0) { anyPageBreak = true }
    if asciiStartsWith(name, 'place-', 0) { anyPlaceShorthand = true }
    // Prefixes rather than the eight exact names: a longhand that
    // matches one only sets a flag the page was going to pay for
    // anyway, and this runs once per parsed declaration rather than
    // once per matched one.
    if asciiStartsWith(name, 'flex', 0) || asciiStartsWith(name, 'outline', 0)
        || asciiStartsWith(name, 'gap', 0) || asciiStartsWith(name, 'text-box', 0)
        || asciiStartsWith(name, 'overscroll', 0)
        || asciiStartsWith(name, 'font-variant', 0)
        || asciiStartsWith(name, 'border-radius', 0)
        || asciiStartsWith(name, 'column-rule', 0)
        || asciiStartsWith(name, 'contain-intrinsic', 0) {
        anyLateShorthand = true
    }
    d.value = value
    d.important = important
    d.serial = declSerialNext
    declSerialNext++
    return d
}

// ---- selectors -----------------------------------------------------

// `An+B` (Selectors 3 SS6.6.5): `odd`, `even`, an integer, `n`, `2n`,
// `2n+1`, `-n+3`, `+3`. Answers false for anything else, which matters:
// the old parser read `2n` with toInt() and got 2, so `:nth-child(2n)`
// silently matched the second child instead of every even one.
//
// Two results out of one function, through globals: see FINDINGS.md,
// "one value out of a function".
int anbA = 0
int anbB = 0

// The index of the `of` keyword in a `:nth-child()` argument, or -1.
// It has to be a token of its own: `1of p` is one identifier and a
// syntax error, and `.info` holds an `of` that is part of a class name.
// The argument arrives lowercased.
int func nthOfKeywordAt(a:ascii) {
    int n = a.length
    for int i = 0, i + 1 < n, i++ {
        if a.charCodeAt(i) != 111 { continue }            // o
        if a.charCodeAt(i + 1) != 102 { continue }        // f
        if i == 0 || !isSpaceCode(a.charCodeAt(i - 1)) { continue }
        if i + 2 >= n || !isSpaceCode(a.charCodeAt(i + 2)) { continue }
        return i
    }
    return 0 - 1
}

bool func parseAnPlusB(argIn:ascii) {
    ascii a = asciiTrim(argIn)
    if a == null || a.length == 0 { return false }
    if a == 'odd' { anbA = 2  anbB = 1  return true }
    if a == 'even' { anbA = 2  anbB = 0  return true }

    int i = 0
    int n = a.length
    int sign = 1
    if a.charCodeAt(i) == CH_PLUS { i++ }
    else if a.charCodeAt(i) == CH_MINUS { sign = -1  i++ }

    int digitsStart = i
    while i < n && isDigitCode(a.charCodeAt(i)) { i++ }
    bool hadDigits = i > digitsStart
    int lead = hadDigits ? a.slice(digitsStart, i).toText().toInt() : 1

    if i >= n {
        // a plain integer: An+B with A = 0
        if !hadDigits { return false }
        anbA = 0
        anbB = sign * lead
        return true
    }
    if a.charCodeAt(i) != CH_N_LOWER { return false }
    i++
    anbA = sign * lead

    if i >= n { anbB = 0  return true }
    int bSign = 1
    if a.charCodeAt(i) == CH_PLUS { i++ }
    else if a.charCodeAt(i) == CH_MINUS { bSign = -1  i++ }
    else { return false }
    while i < n && isSpaceCode(a.charCodeAt(i)) { i++ }
    int bStart = i
    while i < n && isDigitCode(a.charCodeAt(i)) { i++ }
    if i == bStart || i < n { return false }
    anbB = bSign * a.slice(bStart, i).toText().toInt()
    return true
}

Compound func newCompound() {
    Compound c
    c.tag = ''
    c.id = ''
    c.pseudoElement = ''
    c.combinator = COMB_NONE
    return c
}

int selPos = 0
ascii selSrc = ''

// The index just past the escape that begins at `at`, which must be a
// backslash (CSS Syntax 3 §4.3.7). A backslash before hex digits takes
// up to six of them and then one whitespace character, which is the
// escape's terminator rather than part of what follows; before anything
// else it takes that one character.
int func cssEscapeEnd(s:ascii, at:int) {
    int n = s.length
    if at + 1 >= n { return at + 1 }
    if !isHexCode(s.charCodeAt(at + 1)) { return at + 2 }
    int i = at + 1
    int last = minInt(at + 6, n - 1)
    while i <= last && isHexCode(s.charCodeAt(i)) { i++ }
    if i < n && isSpaceCode(s.charCodeAt(i)) { i++ }
    return i
}

// An identifier with its escapes decoded. The answer is `text` rather
// than `ascii` because a code point above 127 is a real character here:
// the tokenizer expands the document's own escapes, so an element's
// class attribute holds `café` and not the form `src/html/decode.f`
// rewrites the bytes into. A selector has to spell it the same way or
// the two can never meet -- which was measured before this was written,
// by asking what the DOM actually stores.
//
// An identifier with no backslash in it is handed straight back, so an
// ordinary page pays one search per name.
text func cssDecodeIdent(a:ascii) {
    if a == null { return null }
    if asciiIndexOf(a, '\\', 0) < 0 { return a.toText() }
    text out = ''
    int n = a.length
    int i = 0
    while i < n {
        int c = a.charCodeAt(i)
        if c != CH_BACKSLASH { out = out + c.toChar()  i++  continue }
        if i + 1 >= n { break }
        int end = cssEscapeEnd(a, i)
        if !isHexCode(a.charCodeAt(i + 1)) {
            out = out + a.charCodeAt(i + 1).toChar()
            i = end
            continue
        }
        int cp = 0
        int j = i + 1
        while j < end && isHexCode(a.charCodeAt(j)) { cp = cp * 16 + hexValue(a.charCodeAt(j))  j++ }
        // §4.3.7 replaces zero, a surrogate and anything past the last
        // code point with U+FFFD. 55296..57343 are the surrogates and
        // 1114111 is the last code point; Festina takes no hex literal,
        // so they are written out.
        if cp == 0 || (cp >= 55296 && cp <= 57343) || cp > 1114111 { cp = 65533 }
        out = out + cp.toChar()
        i = end
    }
    return out
}

// Whether the identifier `scanIdent` just walked held an escape. The
// scan has already looked at every byte of it, so asking again would be
// a second pass over every name on the page: one stylesheet of 6,000
// selectors paid a millisecond for it. Read it immediately after the
// call that set it -- `identAt` below is the only way in.
bool scanIdentEscaped = false

int func scanIdent(from:int) {
    int i = from
    int n = selSrc.length
    scanIdentEscaped = false
    while i < n {
        int c = selSrc.charCodeAt(i)
        if c == CH_BACKSLASH { scanIdentEscaped = true  i = cssEscapeEnd(selSrc, i)  continue }
        if isNameCode(c) { i++  continue }
        break
    }
    return i
}

// The identifier between two indices the scan just produced, decoded
// only where the scan saw a backslash.
text func identAt(from:int, to:int) {
    if !scanIdentEscaped { return selSrc.slice(from, to).toText() }
    return cssDecodeIdent(selSrc.slice(from, to))
}

// The index of the `]` that closes the attribute selector opened at
// `at`, or -1. Selectors 4 §6.1 takes a string for the value, and a
// string takes any character, so the first `]` in the source is not
// necessarily the selector's: `[data-x="a]b"]` cut there leaves `"]`
// over, which marked the whole selector unsupported and dropped its
// rule. An escape is stepped over for the same reason.
int func attrSelEnd(s:ascii, at:int) {
    int n = s.length
    int i = at + 1
    while i < n {
        int c = s.charCodeAt(i)
        if c == CH_BACKSLASH { i = cssEscapeEnd(s, i)  continue }
        if c == CH_QUOTE || c == CH_APOS { i = skipQuoted(s, i)  continue }
        if c == CH_RBRACKET { return i }
        i++
    }
    return 0 - 1
}

// Parses one compound selector starting at selPos (which must not be
// at whitespace); leaves selPos after it.
// The type selector after a namespace part: a name, or `*` for any.
void func readTypeAfterNamespace(comp:Compound) {
    int n = selSrc.length
    if selPos >= n { return }
    if selSrc.charCodeAt(selPos) == CH_STAR { selPos++  return }
    int end = scanIdent(selPos)
    if end > selPos {
        text tagIdent = identAt(selPos, end)
        ascii tagAscii = tagIdent.toAscii()
        comp.tag = tagAscii == null ? tagIdent : asciiLower(tagAscii).toText()
        selPos = end
    }
}

// Whether a compound's namespace part accepts an element in `uri`.
// Every element in an HTML document is in the XHTML namespace, so this
// is one string comparison and the four spellings differ only in which
// string they compare against.
bool func namespaceAccepts(comp:Compound, uri:text) {
    if comp.nsKind == NS_ANY { return true }
    if comp.nsKind == NS_NONE { return uri == '' }
    if comp.nsKind == NS_UNKNOWN { return false }
    if comp.nsKind == NS_PREFIX { return comp.nsUri == uri }
    // no `|` at all: a default namespace applies if one was declared,
    // and otherwise the selector matches in any namespace
    if cssDefaultNamespace == '' { return true }
    return cssDefaultNamespace == uri
}

Compound func parseCompound() {
    Compound comp = newCompound()
    int n = selSrc.length
    bool any = false
    while selPos < n {
        int c = selSrc.charCodeAt(selPos)
        if c == CH_STAR {
            selPos++
            // `*|` is a namespace wildcard rather than a universal
            // selector, so the `*` belongs to the namespace part.
            if selPos < n && selSrc.charCodeAt(selPos) == CH_PIPE
                && selPos + 1 < n && selSrc.charCodeAt(selPos + 1) != CH_EQ {
                selPos++
                comp.nsKind = NS_ANY
                readTypeAfterNamespace(comp)
            }
            any = true
        } else if c == CH_PIPE && (selPos + 1 >= n || selSrc.charCodeAt(selPos + 1) != CH_EQ) {
            // a bare `|` is the no-namespace selector
            selPos++
            comp.nsKind = NS_NONE
            readTypeAfterNamespace(comp)
            any = true
        } else if c == CH_HASH {
            int end = scanIdent(selPos + 1)
            comp.id = identAt(selPos + 1, end)
            selPos = end
            any = true
        } else if c == CH_DOT {
            int end = scanIdent(selPos + 1)
            comp.classes.push(identAt(selPos + 1, end))
            selPos = end
            any = true
        } else if c == CH_LBRACKET {
            int end = attrSelEnd(selSrc, selPos)
            if end < 0 { end = n }
            parseAttrSel(comp, selSrc.slice(selPos + 1, end))
            selPos = end + 1
            any = true
        } else if c == CH_COLON {
            int start = selPos + 1
            bool doubleColon = false
            if start < n && selSrc.charCodeAt(start) == CH_COLON {
                doubleColon = true
                start++
            }
            int end = scanIdent(start)
            ascii name = asciiLower(selSrc.slice(start, end))
            selPos = end
            // `::before`, `::after`, `::first-letter` and `::first-line`
            // name a box other than this element's own, and each has a
            // one-colon spelling CSS2 used. `::marker` names one too and
            // has no such spelling: `:marker` is not a pseudo-element,
            // so it falls through to the pseudo-class handling below and
            // matches nothing.
            bool isLegacyPseudo = name == 'before' || name == 'after'
                || name == 'first-line' || name == 'first-letter'
            bool isElementPseudo = isLegacyPseudo || name == 'marker'
                || name == 'placeholder'
            if doubleColon {
                if isElementPseudo {
                    comp.pseudoElement = name.toText()
                } else {
                    comp.unsupported = true
                }
                any = true
                continue
            }
            if isLegacyPseudo {
                comp.pseudoElement = name.toText()
                any = true
                continue
            }
            if selPos < n && selSrc.charCodeAt(selPos) == CH_LPAREN {
                int close = matchParen(selSrc, selPos)
                ascii arg = asciiTrim(selSrc.slice(selPos + 1, close))
                selPos = close + 1
                if name == 'not' || name == 'is' || name == 'where' || name == 'has'
                    || name == 'matches' || name == 'any' {
                    SubSelector sub
                    sub.kind = name == 'not' ? SUBSEL_NOT
                             : (name == 'has' ? SUBSEL_HAS
                             : (name == 'where' ? SUBSEL_WHERE : SUBSEL_IS))
                    // §3.1: `:is()` and `:where()` take a *forgiving*
                    // selector list -- an alternative this engine
                    // cannot read is dropped and the rest still work,
                    // so `:is(p, &&&bogus)` matches every `p`.
                    // `:not()` and `:has()` do not, and one bad
                    // alternative makes the whole selector invalid.
                    // Chromium was asked all four, and the answers are
                    // in todo.md.
                    bool forgiving = sub.kind == SUBSEL_IS || sub.kind == SUBSEL_WHERE
                    int savedPos = selPos
                    ascii savedSrc = dup(selSrc)
                    arr[ascii] alts = splitOnCommas(arg)
                    for int k = 0, k < alts.length, k++ {
                        ascii alt = asciiTrim(alts[k])
                        if alt.length == 0 {
                            if !forgiving { comp.unsupported = true }
                            continue
                        }
                        // `:has()` takes a *relative* selector, so it
                        // may open with the combinator that says how
                        // the match stands to this element. The other
                        // three take an ordinary complex selector, and
                        // a leading combinator in one of those is a
                        // syntax error rather than a relation.
                        int lead = COMB_DESCENDANT
                        int at = 0
                        int lc = alt.charCodeAt(0)
                        if lc == CH_GT { lead = COMB_CHILD  at = 1 }
                        else if lc == CH_PLUS { lead = COMB_ADJACENT  at = 1 }
                        else if lc == CH_TILDE { lead = COMB_SIBLING  at = 1 }
                        if at > 0 && sub.kind != SUBSEL_HAS {
                            // A leading combinator is a relation, and
                            // only `:has()` takes one. `:not(> p)` is a
                            // syntax error; `:is(> p)` is a dropped
                            // alternative, because the list forgives.
                            if !forgiving { comp.unsupported = true }
                            continue
                        }
                        if at > 0 {
                            alt = asciiTrim(alt.slice(at, alt.length))
                            if alt.length == 0 { comp.unsupported = true  continue }
                        }
                        Selector innerSel = parseSelector(alt)
                        if innerSel.unsupported || innerSel.parts.length == 0 {
                            if !forgiving { comp.unsupported = true }
                            continue
                        }
                        sub.alternatives.push(innerSel)
                        sub.leads.push(lead)
                    }
                    // A forgiving list that forgave everything is still
                    // a valid selector; it simply matches nothing,
                    // which is what an empty alternative list already
                    // means to `:is()` and `:where()` in the matcher.
                    if sub.alternatives.length == 0 && !forgiving { comp.unsupported = true }
                    comp.subs.push(sub)
                    selSrc = savedSrc
                    selPos = savedPos
                } else if name == 'nth-child' || name == 'nth-last-child'
                    || name == 'nth-of-type' || name == 'nth-last-of-type' {
                    // §6.6.5's `of <complex-selector-list>`, which only
                    // `:nth-child()` and `:nth-last-child()` take --
                    // `:nth-of-type(1 of p)` is a syntax error, asked of
                    // Chromium. The keyword needs whitespace on both
                    // sides, because `1of` is one token; it is matched
                    // without regard to case, which is CSS's general
                    // rule and where Chromium disagrees (todo.md).
                    ascii lowered = asciiLower(arg)
                    int ofAt = nthOfKeywordAt(lowered)
                    if ofAt < 0 {
                        if parseAnPlusB(lowered) {
                            comp.pseudos.push(`${name}:${anbA}:${anbB}`)
                        } else {
                            comp.unsupported = true
                        }
                    } else if name != 'nth-child' && name != 'nth-last-child' {
                        comp.unsupported = true
                    } else {
                        ascii head = asciiTrim(lowered.slice(0, ofAt))
                        ascii tail = asciiTrim(arg.slice(ofAt + 2, arg.length))
                        if !parseAnPlusB(head) || tail.length == 0 {
                            comp.unsupported = true
                        } else {
                            NthOf nth
                            nth.fromEnd = name == 'nth-last-child'
                            nth.stepA = anbA
                            nth.offB = anbB
                            int savedNthPos = selPos
                            ascii savedNthSrc = dup(selSrc)
                            arr[ascii] ofAlts = splitOnCommas(tail)
                            for int k = 0, k < ofAlts.length, k++ {
                                ascii one = asciiTrim(ofAlts[k])
                                if one.length == 0 { comp.unsupported = true  continue }
                                Selector ofSel = parseSelector(one)
                                if ofSel.unsupported || ofSel.parts.length == 0 {
                                    comp.unsupported = true
                                    continue
                                }
                                nth.of.push(ofSel)
                            }
                            selSrc = savedNthSrc
                            selPos = savedNthPos
                            if nth.of.length == 0 { comp.unsupported = true }
                            comp.nths.push(nth)
                        }
                    }
                } else if name == 'dir' {
                    // `:dir(ltr)` and `:dir(rtl)` (Selectors 4 §14.2).
                    // `auto` is a real value of the `dir` attribute but
                    // not of this selector, so only the two are taken.
                    ascii d = asciiLower(asciiTrim(arg))
                    if d != null && (d == 'ltr' || d == 'rtl') {
                        comp.pseudos.push(`dir:${d.toText()}`)
                    } else {
                        comp.unsupported = true
                    }
                } else if name == 'lang' {
                    ascii a = asciiLower(asciiTrim(arg))
                    if a != null && a.length > 0 {
                        comp.pseudos.push(`lang:${a.toText()}`)
                    } else {
                        comp.unsupported = true
                    }
                } else {
                    comp.unsupported = true
                }
            } else {
                if name == 'first-child' || name == 'last-child' || name == 'only-child'
                    || name == 'root' || name == 'link' || name == 'any-link'
                    || name == 'first-of-type' || name == 'last-of-type' || name == 'only-of-type'
                    || name == 'empty' || name == 'enabled' || name == 'disabled'
                    || name == 'checked' || name == 'target'
                    // HTML's form-state pseudo-classes (Selectors 4
                    // §11), every one of which is a question about the
                    // document's own attributes.
                    || name == 'read-write' || name == 'read-only'
                    || name == 'required' || name == 'optional'
                    || name == 'placeholder-shown' || name == 'default'
                    || name == 'indeterminate' || name == 'valid' || name == 'invalid'
                    || name == 'in-range' || name == 'out-of-range' {
                    comp.pseudos.push(name.toText())
                } else {
                    // :hover, :focus, :visited ... never match here
                    comp.unsupported = true
                }
            }
            any = true
        } else if isNameCode(c) && !any {
            int end = scanIdent(selPos)
            // `prefix|E` -- but not `[attr|=value]`, which is handled
            // in the attribute branch and never reaches here.
            if end < n && selSrc.charCodeAt(end) == CH_PIPE
                && end + 1 < n && selSrc.charCodeAt(end + 1) != CH_EQ {
                text prefix = selSrc.slice(selPos, end).toText()
                text uri = cssNamespacePrefixes[prefix]
                comp.nsKind = uri == null ? NS_UNKNOWN : NS_PREFIX
                comp.nsUri = uri == null ? '' : uri
                selPos = end + 1
                readTypeAfterNamespace(comp)
                any = true
                continue
            }
            text tagIdent = identAt(selPos, end)
        ascii tagAscii = tagIdent.toAscii()
        comp.tag = tagAscii == null ? tagIdent : asciiLower(tagAscii).toText()
            selPos = end
            any = true
        } else {
            break
        }
    }
    if !any { comp.unsupported = true }
    return comp
}

int func matchParen(s:ascii, open:int) {
    int depth = 0
    int n = s.length
    for int i = open, i < n, i++ {
        int c = s.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN {
            depth--
            if depth == 0 { return i }
        }
    }
    return n
}

// Both halves of `[name matcher value]` are CSS Syntax 3 tokens, so
// both take escapes (§4.3.7): the name is an identifier, and the value
// is an identifier or a string. Nothing here decoded one, so
// `[data\-x=a\ b]` looked for an attribute called `data` holding the
// value `a\` -- neither of which any document has.
void func parseAttrSel(comp:Compound, inner:ascii) {
    AttrSel a
    a.op = ATTR_EXISTS
    a.value = ''
    int n = inner.length
    int i = 0
    bool nameEscaped = false
    while i < n {
        int nc = inner.charCodeAt(i)
        if nc == CH_BACKSLASH { nameEscaped = true  i = cssEscapeEnd(inner, i)  continue }
        if isNameCode(nc) { i++  continue }
        break
    }
    a.name = nameEscaped ? textLower(cssDecodeIdent(inner.slice(0, i)))
                         : asciiLower(inner.slice(0, i)).toText()
    while i < n && isSpaceCode(inner.charCodeAt(i)) { i++ }
    if i < n {
        int c = inner.charCodeAt(i)
        if c == CH_EQ { a.op = ATTR_EQUALS }
        else if c == CH_TILDE { a.op = ATTR_INCLUDES }
        else if c == 94 { a.op = ATTR_PREFIX }       // ^
        else if c == 36 { a.op = ATTR_SUFFIX }       // $
        else if c == CH_STAR { a.op = ATTR_SUBSTRING }
        else if c == 124 { a.op = ATTR_DASH }        // |
        i++
        if a.op != ATTR_EQUALS && i < n && inner.charCodeAt(i) == CH_EQ { i++ }
        while i < n && isSpaceCode(inner.charCodeAt(i)) { i++ }
        int end = n
        while end > i && isSpaceCode(inner.charCodeAt(end - 1)) { end-- }
        if i < end && (inner.charCodeAt(i) == CH_QUOTE || inner.charCodeAt(i) == CH_APOS) {
            int q = inner.charCodeAt(i)
            int close = i + 1
            // A backslash before the closing quote is that quote, not
            // the end of the string, so `[a="x\"y"]` holds `x"y`.
            while close < end {
                int cc = inner.charCodeAt(close)
                if cc == CH_BACKSLASH { close = cssEscapeEnd(inner, close)  continue }
                if cc == q { break }
                close++
            }
            if close > end { close = end }
            a.value = cssDecodeIdent(inner.slice(i + 1, close))
            // A trailing `i` or `s` after the closing quote is the
            // case-sensitivity flag (Selectors 4 §6.3). It was parsed
            // and thrown away, which made `[a="X" i]` an ordinary
            // case-sensitive match rather than the one that was asked
            // for.
            int after = close + 1
            while after < end && isSpaceCode(inner.charCodeAt(after)) { after++ }
            if after < end {
                int flag = inner.charCodeAt(after)
                if flag == 73 || flag == 105 { a.caseInsensitive = true }   // I or i
            }
        } else {
            // An unquoted value ends at the first whitespace that is
            // not part of an escape, and may be followed by the same
            // flag. Scanning backwards from the end for that whitespace
            // read `a\ b` as the value `a\` and the flag `b`, and read
            // the space that terminates `a\62 ` as the gap before one.
            int valueEnd = i
            while valueEnd < end {
                int vc = inner.charCodeAt(valueEnd)
                if vc == CH_BACKSLASH { valueEnd = cssEscapeEnd(inner, valueEnd)  continue }
                if isSpaceCode(vc) { break }
                valueEnd++
            }
            if valueEnd > end { valueEnd = end }
            int after = valueEnd
            while after < end && isSpaceCode(inner.charCodeAt(after)) { after++ }
            if after >= end {
                // nothing follows the value
            } else if end - after == 1 {
                int flag = inner.charCodeAt(after)
                if flag == 73 || flag == 105 { a.caseInsensitive = true }
                else if flag != 83 && flag != 115 { valueEnd = end }
            } else {
                valueEnd = end
            }
            a.value = cssDecodeIdent(inner.slice(i, valueEnd))
        }
    }
    comp.attrs.push(a)
}

Selector func parseSelector(src:ascii) {
    Selector sel
    selSrc = asciiTrim(src)
    selPos = 0
    int n = selSrc.length
    int pending = COMB_NONE
    while selPos < n {
        int c = selSrc.charCodeAt(selPos)
        if isSpaceCode(c) {
            if pending == COMB_NONE && sel.parts.length > 0 { pending = COMB_DESCENDANT }
            selPos++
            continue
        }
        if c == CH_GT {
            pending = COMB_CHILD
            selPos++
            continue
        }
        if c == CH_PLUS {
            pending = COMB_ADJACENT
            selPos++
            continue
        }
        if c == CH_TILDE {
            pending = COMB_SIBLING
            selPos++
            continue
        }
        int before = selPos
        Compound comp = parseCompound()
        if selPos == before {
            sel.unsupported = true
            break
        }
        comp.combinator = sel.parts.length == 0 ? COMB_NONE : pending
        pending = COMB_NONE
        if comp.unsupported { sel.unsupported = true }
        sel.parts.push(comp)
    }
    if sel.parts.length == 0 { sel.unsupported = true }
    // The pseudo-element may only be on the rightmost compound, and it
    // makes the rule describe a generated box rather than the element.
    sel.pseudoElement = ''
    for int i = 0, i < sel.parts.length, i++ {
        if sel.parts[i].pseudoElement == '' { continue }
        if i == sel.parts.length - 1 { sel.pseudoElement = sel.parts[i].pseudoElement }
        else { sel.unsupported = true }
    }
    sel.specificity = computeSpecificity(sel)
    return sel
}

// Specificity is the triple (ids, classes+attributes+pseudo-classes,
// types) compared lexicographically, not a sum: any number of classes
// loses to one id. It is packed into one int base 1024 so that a plain
// integer comparison is the lexicographic one, with each count clamped
// to 1023 so a pathological selector cannot carry into the field above.
const int SPEC_BASE = 1024

int func specClamp(n:int) {
    return n > SPEC_BASE - 1 ? SPEC_BASE - 1 : n
}

int func packSpecificity(ids:int, classes:int, types:int) {
    return specClamp(ids) * SPEC_BASE * SPEC_BASE + specClamp(classes) * SPEC_BASE + specClamp(types)
}

// `/` is float division and there is no integer-division operator, so
// unpacking goes through Math.floor (FINDINGS.md, "no integer division").
int func specIds(s:int) { return Math.floor(s / (SPEC_BASE * SPEC_BASE)) }
int func specClasses(s:int) { return Math.floor(s / SPEC_BASE) % SPEC_BASE }
int func specTypes(s:int) { return s % SPEC_BASE }

// Adds two packed triples componentwise, which is what a compound or a
// complex selector does to its parts.
int func specAdd(a:int, b:int) {
    return packSpecificity(specIds(a) + specIds(b),
                           specClasses(a) + specClasses(b),
                           specTypes(a) + specTypes(b))
}

int func compoundSpecificity(c:Compound) {
    int ids = c.id != '' ? 1 : 0
    // An `:nth-child()` with an `of` clause is in `nths` rather than
    // `pseudos`, and still weighs a pseudo-class of its own.
    int classes = c.classes.length + c.attrs.length + c.pseudos.length + c.nths.length
    // A pseudo-element counts as a type, not a pseudo-class
    // (Selectors 3 §9).
    int types = (c.tag != '' ? 1 : 0) + (c.pseudoElement != '' ? 1 : 0)
    int s = packSpecificity(ids, classes, types)
    // `:not()`, `:is()` and `:has()` take the specificity of their most
    // specific argument; `:where()` takes none at all (Selectors 4).
    for int i = 0, i < c.subs.length, i++ {
        if c.subs[i].kind == SUBSEL_WHERE { continue }
        int best = 0
        for int k = 0, k < c.subs[i].alternatives.length, k++ {
            int inner = computeSpecificity(c.subs[i].alternatives[k])
            if inner > best { best = inner }
        }
        s = specAdd(s, best)
    }
    // And `:nth-child(An+B of S)` adds S's, the same way: measured in
    // Chromium, where `:nth-child(1 of #s1)` beats `.lead.lead` written
    // either side of it.
    for int i = 0, i < c.nths.length, i++ {
        int best = 0
        for int k = 0, k < c.nths[i].of.length, k++ {
            int inner = computeSpecificity(c.nths[i].of[k])
            if inner > best { best = inner }
        }
        s = specAdd(s, best)
    }
    return s
}

int func computeSpecificity(sel:Selector) {
    int s = 0
    for int i = 0, i < sel.parts.length, i++ {
        s = specAdd(s, compoundSpecificity(sel.parts[i]))
    }
    return s
}

// Splits a selector list on top-level commas.
//
// A `[` inside a string is not a bracket. `[data-x="a[b"], #n` left the
// depth at one when the list ended, so the comma was never top-level
// and both selectors were run together into one that names nothing --
// which is a rule dropped whole rather than a rule that fails to match.
// A backslash is stepped over for the same reason, so `[a=x\[]` counts
// no bracket either.
arr[Selector] func parseSelectorList(prelude:ascii) {
    arr[Selector] out = []
    int n = prelude.length
    int depth = 0
    int start = 0
    int i = 0
    while i <= n {
        int c = i < n ? prelude.charCodeAt(i) : CH_COMMA
        if c == CH_BACKSLASH && i < n { i = cssEscapeEnd(prelude, i)  continue }
        if (c == CH_QUOTE || c == CH_APOS) && i < n { i = skipQuoted(prelude, i)  continue }
        if c == CH_LPAREN || c == CH_LBRACKET { depth++ }
        else if c == CH_RPAREN || c == CH_RBRACKET { depth-- }
        else if c == CH_COMMA && depth <= 0 {
            ascii piece = asciiTrim(prelude.slice(start, i))
            if piece.length > 0 { out.push(parseSelector(piece)) }
            start = i + 1
        }
        i++
    }
    return out
}

// ---- @supports --------------------------------------------------------
//
// A feature query is only useful if it can say no. Evaluating it means
// answering "would this engine accept this declaration?", which is the
// property being one the cascade actually computes and the value being
// one it can resolve. Applying every block unconditionally, as this used
// to, lands a page's fallback and its enhancement on top of each other.

// The properties the cascade reads. A declaration naming anything else
// is not supported, whatever its value.
arr[text] supportedProperties = [
    'display', 'visibility', 'opacity', 'color', 'background-color', 'background',
    'background-image', 'content', 'counter-reset', 'counter-increment', 'quotes',
    'width', 'height', 'min-width', 'max-width', 'min-height',
    'margin', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
    'padding', 'padding-top', 'padding-right', 'padding-bottom', 'padding-left',
    'border', 'border-width', 'border-style', 'border-color', 'border-radius',
    'border-top', 'border-right', 'border-bottom', 'border-left',
    'border-top-width', 'border-right-width', 'border-bottom-width', 'border-left-width',
    'border-top-style', 'border-right-style', 'border-bottom-style', 'border-left-style',
    'border-top-color', 'border-right-color', 'border-bottom-color', 'border-left-color',
    'border-spacing', 'border-collapse',
    'overflow-clip-margin', 'text-box-trim', 'text-box-edge',
    'box-decoration-break',
    'overscroll-behavior', 'overscroll-behavior-x', 'overscroll-behavior-y',
    'overscroll-behavior-inline', 'overscroll-behavior-block',
    'initial-letter',
    'offset-path', 'offset-distance', 'offset-rotate', 'offset-anchor', 'offset-position',
    'filter',
    'mask-image', 'mask-mode', 'mask-repeat', 'mask-position', 'mask-size',
    'mask-origin', 'mask-clip', 'mask-composite', 'isolation', 'writing-mode', 'text-orientation', 'text-combine-upright',
    'anchor-name', 'anchor-scope', 'position-anchor', 'position-area', 'position-try-fallbacks', 'position-try-order', 'position-visibility',
    'corner-shape', 'corner-top-left-shape', 'corner-top-right-shape',
    'corner-bottom-right-shape', 'corner-bottom-left-shape',
    'corner-start-start-shape', 'corner-start-end-shape',
    'corner-end-start-shape', 'corner-end-end-shape',
    'font', 'font-size', 'font-size-adjust', 'font-weight', 'font-style', 'font-family',
    'font-variant-caps', 'font-synthesis', 'font-synthesis-small-caps', 'image-rendering', 'will-change',
    'line-height',
    'text-align', 'text-decoration', 'text-decoration-line', 'text-transform',
    'text-decoration-color', 'text-decoration-style',
    'text-decoration-thickness', 'text-underline-offset', 'text-shadow',
    'direction', 'unicode-bidi',
    'text-emphasis', 'text-emphasis-style', 'text-emphasis-color',
    'text-emphasis-position', 'text-underline-position',
    'text-indent', 'letter-spacing', 'white-space', 'vertical-align', 'baseline-source',
    'zoom',
    'resize',
    'text-wrap-style',
    'print-color-adjust',
    'ruby-position', 'ruby-align',
    'white-space-collapse', 'text-wrap-mode', 'text-align-last',
    'word-break', 'line-break', 'overflow-wrap', 'tab-size', 'all',
    'hyphens', 'hyphenate-character',
    'list-style', 'list-style-type', 'list-style-image', 'background-attachment',
    'position', 'top', 'right', 'bottom', 'left', 'z-index',
    'float', 'clear',
    'box-sizing', 'max-height', 'word-spacing', 'caption-side', 'aspect-ratio',
    'counter-set',
    'flex', 'flex-direction', 'flex-grow', 'flex-shrink', 'flex-basis',
    'flex-wrap', 'flex-flow',
    'justify-content', 'align-items', 'align-self', 'align-content',
    'justify-items', 'justify-self', 'text-overflow', 'pointer-events',
    'place-items', 'place-content', 'place-self',
    'white-space', 'text-wrap',
    'border-radius', 'outline', 'flex', 'flex-flow', 'gap', 'text-box',
    'overscroll-behavior',
    'border-image', 'border-image-source', 'border-image-slice',
    'border-image-width', 'border-image-outset', 'border-image-repeat',
    'columns', 'column-count', 'column-width',
    'column-rule', 'column-rule-width', 'column-rule-style', 'column-rule-color',
    'column-span', 'column-fill',
    'break-before', 'break-after', 'break-inside', 'orphans', 'widows',
    'page', 'page-break-before', 'page-break-after', 'page-break-inside',
    'scrollbar-width', 'scrollbar-color', 'scrollbar-gutter',
    'scroll-snap-type', 'scroll-snap-align', 'scroll-snap-stop', 'scroll-padding', 'scroll-margin',
    'scroll-padding-top', 'scroll-padding-right', 'scroll-padding-bottom', 'scroll-padding-left',
    'scroll-margin-top', 'scroll-margin-right', 'scroll-margin-bottom', 'scroll-margin-left',
    'scroll-padding-block-start', 'scroll-padding-block-end',
    'scroll-padding-inline-start', 'scroll-padding-inline-end',
    'scroll-margin-block-start', 'scroll-margin-block-end',
    'scroll-margin-inline-start', 'scroll-margin-inline-end',
    'clip-path', 'clip', 'shape-outside', 'shape-margin',
    'grid-template-columns', 'grid-template-rows', 'grid-template-areas',
    'grid-auto-columns', 'grid-auto-rows', 'grid-auto-flow',
    'grid-column', 'grid-row', 'grid-area',
    'grid-column-start', 'grid-column-end',
    'grid-row-start', 'grid-row-end',
    'gap', 'row-gap', 'column-gap', 'order',
    'outline', 'outline-width', 'outline-style', 'outline-color',
    'outline-offset', 'table-layout', 'empty-cells', 'list-style-position',
    'transform', 'transform-origin', 'transform-box',
    'appearance', 'field-sizing', 'accent-color', 'translate', 'rotate', 'scale',
    'contain', 'content-visibility', 'contain-intrinsic-size',
    'contain-intrinsic-width', 'contain-intrinsic-height',
    'contain-intrinsic-inline-size', 'contain-intrinsic-block-size',
    'color-scheme', 'container-type', 'container-name',
    'background-position', 'background-position-x', 'background-position-y',
    'background-repeat', 'background-size',
    'background-origin', 'background-clip',
    'border-top-left-radius', 'border-top-right-radius',
    'border-bottom-right-radius', 'border-bottom-left-radius',
    'border-start-start-radius', 'border-start-end-radius',
    'border-end-start-radius', 'border-end-end-radius',
    'box-shadow', 'object-fit', 'object-position', 'object-view-box',
    // A property belongs here when something reads it, not when the
    // cascade merely computes it: claiming otherwise is the lie
    // @supports exists to prevent (css-2026.md). `overflow` was absent
    // on exactly that ground until the painter began clipping by it.
    'overflow', 'overflow-x', 'overflow-y',

    'inline-size', 'block-size',
    'margin-inline', 'margin-inline-start', 'margin-inline-end',
    'margin-block', 'margin-block-start', 'margin-block-end',
    'padding-inline', 'padding-inline-start', 'padding-inline-end', 'padding-block',
    'padding-block-start', 'padding-block-end',
    'min-inline-size', 'max-inline-size', 'min-block-size', 'max-block-size',
    'border-block', 'border-inline',
    'border-block-start', 'border-block-end', 'border-inline-start', 'border-inline-end',
    'border-block-start-width', 'border-block-end-width',
    'border-inline-start-width', 'border-inline-end-width',
    'border-block-start-style', 'border-block-end-style',
    'border-inline-start-style', 'border-inline-end-style',
    'border-block-start-color', 'border-block-end-color',
    'border-inline-start-color', 'border-inline-end-color',
    'inset', 'inset-block', 'inset-inline',
    'inset-block-start', 'inset-block-end', 'inset-inline-start', 'inset-inline-end',
    'overflow-block', 'overflow-inline'
]

bool func cssKnownProperty(prop:ascii) {
    text p = prop.toText()
    for int i = 0, i < supportedProperties.length, i++ {
        if supportedProperties[i] == p { return true }
    }
    return false
}

// The value functions this engine cannot evaluate. A declaration using
// one of them would be dropped, so claiming support for it would be a
// lie of exactly the kind @supports exists to prevent.
bool func cssValueEvaluable(val:ascii) {
    if val.length == 0 { return false }
    ascii v = asciiLower(val)
    if asciiIndexOf(v, 'var(', 0) >= 0 { return false }
    if asciiIndexOf(v, 'calc(', 0) >= 0 { return false }
    if asciiIndexOf(v, 'min(', 0) >= 0 { return false }
    if asciiIndexOf(v, 'max(', 0) >= 0 { return false }
    if asciiIndexOf(v, 'clamp(', 0) >= 0 { return false }
    if asciiIndexOf(v, 'attr(', 0) >= 0 { return false }
    if asciiIndexOf(v, 'env(', 0) >= 0 { return false }
    // `filter` is supported for its colour functions and not for these
    // two: a `blur()` is a convolution over pixels and a
    // `drop-shadow()` wants a path API an image does not have, so a
    // declaration naming either is dropped whole. Neither spelling
    // appears in any other property's value.
    if asciiIndexOf(v, 'blur(', 0) >= 0 { return false }
    if asciiIndexOf(v, 'drop-shadow(', 0) >= 0 { return false }
    return true
}

bool func supportsDeclaration(decl:ascii) {
    int colon = asciiIndexOf(decl, ':', 0)
    if colon < 0 { return false }
    ascii prop = asciiLower(asciiTrim(decl.slice(0, colon)))
    ascii val = asciiTrim(decl.slice(colon + 1, decl.length))
    if prop.length == 0 { return false }
    // A custom property or a vendor prefix is dropped at parse time.
    if prop.charCodeAt(0) == CH_MINUS { return false }
    // `mask-image` is supported for a gradient and not for a bitmap,
    // which needs the image's own alpha per pixel. The property name
    // alone cannot say that, so it is asked here.
    if prop == 'mask-image' && asciiIndexOf(asciiLower(val), 'url(', 0) >= 0 {
        return false
    }
    return cssKnownProperty(prop) && cssValueEvaluable(val)
}

// Finds the next top-level occurrence of ` and ` / ` or `, outside any
// parentheses. Returns -1 when there is none.
int func supportsSplit(cond:ascii, word:ascii) {
    int depth = 0
    int n = cond.length
    for int i = 0, i < n, i++ {
        int c = cond.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN { depth-- }
        else if depth == 0 && isSpaceCode(c) {
            int j = i
            while j < n && isSpaceCode(cond.charCodeAt(j)) { j++ }
            if j + word.length <= n {
                ascii cand = asciiLower(cond.slice(j, j + word.length))
                if cand == word && j + word.length < n && isSpaceCode(cond.charCodeAt(j + word.length)) {
                    return i
                }
            }
        }
    }
    return -1
}

bool func evaluateSupportsCondition(cond:ascii) {
    ascii c = asciiTrim(cond)
    if c.length == 0 { return false }

    int andAt = supportsSplit(c, 'and'.toAscii())
    if andAt >= 0 {
        int rest = andAt
        while rest < c.length && isSpaceCode(c.charCodeAt(rest)) { rest++ }
        return evaluateSupportsCondition(c.slice(0, andAt))
            && evaluateSupportsCondition(c.slice(rest + 3, c.length))
    }
    int orAt = supportsSplit(c, 'or'.toAscii())
    if orAt >= 0 {
        int rest = orAt
        while rest < c.length && isSpaceCode(c.charCodeAt(rest)) { rest++ }
        return evaluateSupportsCondition(c.slice(0, orAt))
            || evaluateSupportsCondition(c.slice(rest + 2, c.length))
    }
    if c.length > 4 && asciiLower(c.slice(0, 4)) == 'not ' {
        return !evaluateSupportsCondition(c.slice(4, c.length))
    }
    if c.charCodeAt(0) == CH_LPAREN && c.charCodeAt(c.length - 1) == CH_RPAREN {
        ascii inner = asciiTrim(c.slice(1, c.length - 1))
        // (( ... )) or (not ...) nests; ( prop: value ) is a declaration.
        if inner.length > 0 && (inner.charCodeAt(0) == CH_LPAREN
            || (inner.length > 4 && asciiLower(inner.slice(0, 4)) == 'not ')) {
            return evaluateSupportsCondition(inner)
        }
        return supportsDeclaration(inner)
    }
    // selector(...) and any other unknown function: not supported.
    return false
}

// ---- @media ---------------------------------------------------------

// Evaluates a media query list against the viewport: `all` and
// `screen` as types, `not`, `only`, `and` and the comma list, and every
// media feature Level 3 defines, in its boolean form as well as with a
// value. A feature this does not know makes its term false, which makes
// the whole query false unless another alternative in the list is
// true.
bool func evaluateMediaQuery(query:ascii) {
    arr[ascii] alternatives = asciiSplitChar(asciiLower(query), CH_COMMA)
    if alternatives.length == 0 { return true }
    for int i = 0, i < alternatives.length, i++ {
        if evaluateOneMediaQuery(alternatives[i]) { return true }
    }
    return false
}

bool func evaluateOneMediaQuery(q:ascii) {
    // a copy, not `ascii s = q`: rebinding an ascii parameter to a
    // local double-releases it (FINDINGS.md, "ascii parameter aliasing")
    ascii s = q.slice(0, q.length)
    if asciiStartsWith(s, 'only ', 0) { return evaluateMediaCondition(asciiTrim(s.slice(5, s.length))) }
    return evaluateMediaCondition(asciiTrim(s))
}

// A media condition: terms joined by `and` or `or`, negated by `not`,
// and grouped by parentheses. The standard does not allow `and` and
// `or` to be mixed without parentheses, so whichever appears first at
// the top level decides how the rest are read.
bool func evaluateMediaCondition(cond:ascii) {
    ascii c = asciiTrim(cond)
    if c.length == 0 { return true }
    if asciiStartsWith(c, 'not ', 0) { return !evaluateMediaCondition(c.slice(4, c.length)) }
    arr[ascii] parts = []
    bool isOr = splitMediaCondition(c, parts)
    if parts.length > 1 {
        if isOr {
            for int i = 0, i < parts.length, i++ {
                if evaluateMediaCondition(parts[i]) { return true }
            }
            return false
        }
        for int i = 0, i < parts.length, i++ {
            if !evaluateMediaCondition(parts[i]) { return false }
        }
        return true
    }
    if c.charCodeAt(0) != CH_LPAREN { return evaluateMediaTerm(c) }
    // One parenthesised thing: either a condition of its own, or a
    // feature. Only unwrap when the first parenthesis is closed by the
    // last character, so `(a) or (b)` is not mistaken for a group.
    int close = mediaMatchingParen(c, 0)
    if close != c.length - 1 { return false }
    ascii inner = asciiTrim(c.slice(1, close))
    if inner.length == 0 { return false }
    if inner.charCodeAt(0) == CH_LPAREN || asciiStartsWith(inner, 'not ', 0) {
        return evaluateMediaCondition(inner)
    }
    return evaluateMediaFeature(inner)
}

// Splits a condition at the top level on ` and ` or ` or `, whichever
// comes first, and answers whether it was `or`. A separator inside
// parentheses belongs to the group and is not a split.
bool func splitMediaCondition(c:ascii, out:arr[ascii]) {
    int n = c.length
    int depth = 0
    int start = 0
    int width = 0
    bool isOr = false
    bool decided = false
    for int i = 0, i < n, i++ {
        int ch = c.charCodeAt(i)
        if ch == CH_LPAREN { depth++ }
        else if ch == CH_RPAREN { depth-- }
        else if depth == 0 && ch == CH_SPACE {
            bool here = false
            if (!decided || !isOr) && asciiStartsWith(c, ' and ', i) {
                here = true
                width = 5
                isOr = false
            } else if (!decided || isOr) && asciiStartsWith(c, ' or ', i) {
                here = true
                width = 4
                isOr = true
            }
            if here {
                decided = true
                out.push(asciiTrim(c.slice(start, i)))
                start = i + width
                i = start - 1
            }
        }
    }
    if decided { out.push(asciiTrim(c.slice(start, n))) }
    return isOr
}

int func mediaMatchingParen(s:ascii, open:int) {
    int depth = 0
    for int i = open, i < s.length, i++ {
        int c = s.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN {
            depth--
            if depth == 0 { return i }
        }
    }
    return -1
}

// What this engine is, as a device. The canvas is eight bits a
// component with no colour table, it is not a grid terminal, and it is
// drawn at one device pixel to the CSS pixel. The device it runs on is
// its own window: there are no screen metrics to ask for, and a page
// asking about the device is deciding whether it is on a phone, which
// the window size answers as well as the screen does.
const int MEDIA_COLOR_BITS = 8
const int MEDIA_DPI = 96

bool func evaluateMediaTerm(term:ascii) {
    // `all` is every medium, and of the two the standard still has this
    // is whichever one is being rendered for: `print` while a document
    // is being paginated and `screen` otherwise. `speech` is a device
    // this is not, and the rest are deprecated and match nothing.
    if term.length == 0 || term == 'all' { return true }
    return cssMediaPrint ? term == 'print' : term == 'screen'
}

// The comparisons a feature may be written with. `min-` and `max-` are
// the same question in the older spelling.
const int MQOP_EQ = 0
const int MQOP_LT = 1
const int MQOP_LE = 2
const int MQOP_GT = 3
const int MQOP_GE = 4

// The inside of one pair of parentheses: `name`, `name: value`,
// `name op value`, `value op name`, or `value op name op value`.
bool func evaluateMediaFeature(inner:ascii) {
    int colon = asciiIndexOf(inner, ':', 0)
    if colon >= 0 {
        ascii name = asciiTrim(inner.slice(0, colon))
        ascii value = asciiTrim(inner.slice(colon + 1, inner.length))
        int op = MQOP_EQ
        int from = 0
        if asciiStartsWith(name, 'min-', 0) {
            op = MQOP_GE
            from = 4
        } else if asciiStartsWith(name, 'max-', 0) {
            op = MQOP_LE
            from = 4
        }
        return mediaFeatureMatches(name.slice(from, name.length), op, value)
    }
    // The range forms. The first operator splits the text in two; a
    // second one means both ends are given, and the name is in the
    // middle.
    int first = mediaOperatorAt(inner, 0)
    if first < 0 { return mediaFeatureBoolean(asciiTrim(inner)) }
    int firstLen = mediaOperatorLength(inner, first)
    int second = mediaOperatorAt(inner, first + firstLen)
    if second < 0 {
        ascii left = asciiTrim(inner.slice(0, first))
        ascii right = asciiTrim(inner.slice(first + firstLen, inner.length))
        int op = mediaOperatorKind(inner, first)
        // `width >= 400px` and `400px <= width` say the same thing: the
        // name may be on either side, and the operator turns round with
        // it. A value begins with a digit, a dot or a sign, and a
        // feature name never does.
        if mediaLooksLikeName(left) { return mediaFeatureMatches(left, op, right) }
        return mediaFeatureMatches(right, mediaOperatorReversed(op), left)
    }
    int secondLen = mediaOperatorLength(inner, second)
    ascii lo = asciiTrim(inner.slice(0, first))
    ascii name = asciiTrim(inner.slice(first + firstLen, second))
    ascii hi = asciiTrim(inner.slice(second + secondLen, inner.length))
    if !mediaFeatureMatches(name, mediaOperatorReversed(mediaOperatorKind(inner, first)), lo) {
        return false
    }
    return mediaFeatureMatches(name, mediaOperatorKind(inner, second), hi)
}

bool func mediaLooksLikeName(t:ascii) {
    if t.length == 0 { return false }
    int c = t.charCodeAt(0)
    return !isDigitCode(c) && c != CH_DOT && c != CH_MINUS && c != CH_PLUS
}

// The index of the next `<`, `>` or `=` at or after `from`, or -1.
int func mediaOperatorAt(s:ascii, from:int) {
    for int i = from, i < s.length, i++ {
        int c = s.charCodeAt(i)
        if c == CH_LT || c == CH_GT || c == CH_EQ { return i }
    }
    return -1
}

int func mediaOperatorLength(s:ascii, at:int) {
    if at + 1 < s.length && s.charCodeAt(at + 1) == CH_EQ { return 2 }
    return 1
}

int func mediaOperatorKind(s:ascii, at:int) {
    int c = s.charCodeAt(at)
    bool orEqual = at + 1 < s.length && s.charCodeAt(at + 1) == CH_EQ
    if c == CH_LT { return orEqual ? MQOP_LE : MQOP_LT }
    if c == CH_GT { return orEqual ? MQOP_GE : MQOP_GT }
    return MQOP_EQ
}

// `a < b` read from b's side is `b > a`.
int func mediaOperatorReversed(op:int) {
    if op == MQOP_LT { return MQOP_GT }
    if op == MQOP_LE { return MQOP_GE }
    if op == MQOP_GT { return MQOP_LT }
    if op == MQOP_GE { return MQOP_LE }
    return MQOP_EQ
}

// `(feature)` on its own asks whether the feature's value is something
// other than zero, `none` or `no-preference`.
bool func mediaFeatureBoolean(feat:ascii) {
    if feat == 'color' || feat == 'resolution' || feat == 'orientation'
        || feat == 'aspect-ratio' || feat == 'device-aspect-ratio'
        || feat == 'width' || feat == 'height'
        || feat == 'device-width' || feat == 'device-height'
        || feat == 'hover' || feat == 'any-hover'
        || feat == 'pointer' || feat == 'any-pointer'
        || feat == 'update' || feat == 'overflow-block'
        || feat == 'prefers-color-scheme' || feat == 'color-gamut' { return true }
    // `scripting`, `overflow-inline`, `forced-colors`, `inverted-colors`,
    // the `prefers-` family and `dynamic-range` all answer with the
    // value this engine has, and every one of those is a falsy one.
    return false
}

// One feature, compared against its value with one operator.
bool func mediaFeatureMatches(name:ascii, op:int, value:ascii) {
    // A discrete feature's values are keywords, which have no order, so
    // the only comparison it takes is equality -- which is what the
    // colon form writes. `(scripting >= none)` is not a query.
    if mediaFeatureIsDiscrete(name) && op != MQOP_EQ { return false }
    if name == 'orientation' {
        bool portrait = cssViewportHeight > cssViewportWidth
        if value == 'portrait' { return portrait }
        if value == 'landscape' { return !portrait }
        return false
    }
    if name == 'hover' || name == 'any-hover' {
        // This browser opens a window with a pointer in it, so it says
        // so. A headless renderer would answer `none`, which is a fact
        // about that process rather than about the standard.
        return value == 'hover'
    }
    if name == 'pointer' || name == 'any-pointer' { return value == 'fine' }
    // Media Queries 4's own features. Each of these is a statement
    // about this browser rather than a computation.
    if name == 'scripting' {
        // There is no JavaScript engine, which is the whole of the
        // answer.
        return value == 'none'
    }
    if name == 'overflow-block' {
        // The shell scrolls down a document and paints what is in view.
        return value == 'scroll'
    }
    if name == 'overflow-inline' {
        // It does not scroll across: a line that overflows is clipped.
        return value == 'none'
    }
    if name == 'update' {
        // The window repaints as often as it is asked to.
        return value == 'fast'
    }
    if name == 'prefers-color-scheme' { return value == 'light' }
    if name == 'prefers-reduced-motion' || name == 'prefers-contrast'
        || name == 'prefers-reduced-data' || name == 'prefers-reduced-transparency' {
        // Nothing here moves, and there is no user to have asked.
        return value == 'no-preference'
    }
    if name == 'forced-colors' || name == 'inverted-colors' { return value == 'none' }
    if name == 'color-gamut' {
        // Every colour is a packed sRGB integer by the time it is
        // painted, whatever space it was written in.
        return value == 'srgb'
    }
    if name == 'dynamic-range' { return value == 'standard' }
    if name == 'scan' {
        // scan describes a television's refresh, and applies to the
        // `tv` media type only.
        return false
    }
    if name == 'aspect-ratio' || name == 'device-aspect-ratio' {
        float want = parseMediaRatio(value)
        if want < 0.0 || cssViewportHeight <= 0 { return false }
        if op == MQOP_EQ {
            // An exact ratio compares two whole numbers, not two
            // divisions: 800 by 600 is 4/3, and testing 800.0/600.0
            // against 4.0/3.0 is testing two roundings against each
            // other.
            return mediaRatioEquals(value, cssViewportWidth, cssViewportHeight)
        }
        float have = cssViewportWidth.toFloat() / cssViewportHeight.toFloat()
        return compareMediaOp(op, have, want)
    }
    parseNumberAt(value, 0)
    if !numOk { return false }
    float v = numValue
    ascii unit = asciiLower(value.slice(numEnd, value.length))
    // A length in a media query resolves against the initial font size:
    // there is no element for `em` to be relative to.
    if unit == 'em' || unit == 'rem' { v = v * 16.0 }
    // A resolution is compared in dots per inch whatever it was written
    // in: one CSS pixel is 1/96 inch, so 1dppx is 96dpi.
    if name == 'resolution' {
        if unit == 'dppx' || unit == 'x' { v = v * 96.0 }
        else if unit == 'dpcm' { v = v * 2.54 }
        else if unit != 'dpi' { return false }
        return compareMediaOp(op, MEDIA_DPI.toFloat(), v)
    }
    // `inline-size` and `block-size` are the container's spellings of
    // the same two axes, and are features only while a container query
    // is being answered -- `@media (inline-size: 100px)` is not a
    // thing, and answering it would be a lie of the kind @supports
    // exists to prevent.
    if name == 'width' || name == 'device-width'
        || (cssAnsweringContainer && name == 'inline-size') {
        return compareMediaOp(op, cssViewportWidth.toFloat(), v)
    }
    if name == 'height' || name == 'device-height'
        || (cssAnsweringContainer && name == 'block-size') {
        return compareMediaOp(op, cssViewportHeight.toFloat(), v)
    }
    if name == 'color' { return compareMediaOp(op, MEDIA_COLOR_BITS.toFloat(), v) }
    if name == 'color-index' || name == 'monochrome' { return compareMediaOp(op, 0.0, v) }
    if name == 'grid' { return compareMediaOp(op, 0.0, v) }
    return false
}

// Which features answer with a keyword rather than a number.
bool func mediaFeatureIsDiscrete(name:ascii) {
    return name == 'orientation' || name == 'hover' || name == 'any-hover'
        || name == 'pointer' || name == 'any-pointer' || name == 'scan'
        || name == 'scripting' || name == 'overflow-block' || name == 'overflow-inline'
        || name == 'update' || name == 'prefers-color-scheme'
        || name == 'prefers-reduced-motion' || name == 'prefers-contrast'
        || name == 'prefers-reduced-data' || name == 'prefers-reduced-transparency'
        || name == 'forced-colors' || name == 'inverted-colors'
        || name == 'color-gamut' || name == 'dynamic-range'
}

bool func compareMediaOp(op:int, have:float, want:float) {
    if op == MQOP_LT { return have < want }
    if op == MQOP_LE { return have <= want }
    if op == MQOP_GT { return have > want }
    if op == MQOP_GE { return have >= want }
    return have == want
}

// A <ratio> is `a/b`, or a bare number, which is that number over one.
// Answers -1 for anything else.
float func parseMediaRatio(value:ascii) {
    int slash = asciiIndexOf(value, '/', 0)
    if slash < 0 {
        parseNumberAt(asciiTrim(value), 0)
        if !numOk { return -1.0 }
        return numValue
    }
    parseNumberAt(asciiTrim(value.slice(0, slash)), 0)
    if !numOk { return -1.0 }
    float a = numValue
    parseNumberAt(asciiTrim(value.slice(slash + 1, value.length)), 0)
    if !numOk || numValue == 0.0 { return -1.0 }
    return a / numValue
}

// An exact ratio is a comparison of two whole numbers, not of two
// divisions: 800 by 600 is 4/3, and testing 800.0/600.0 against
// 4.0/3.0 is testing two roundings against each other.
bool func mediaRatioEquals(value:ascii, w:int, h:int) {
    int slash = asciiIndexOf(value, '/', 0)
    if slash < 0 {
        float want = parseMediaRatio(value)
        if want < 0.0 || h <= 0 { return false }
        return w.toFloat() == want * h.toFloat()
    }
    parseNumberAt(asciiTrim(value.slice(0, slash)), 0)
    if !numOk { return false }
    float a = numValue
    parseNumberAt(asciiTrim(value.slice(slash + 1, value.length)), 0)
    if !numOk { return false }
    float b = numValue
    return w.toFloat() * b == h.toFloat() * a
}

// ---- stylesheets ------------------------------------------------------

// ---- CSS Nesting 1 ----------------------------------------------------

// A nested rule is the cross product of its own selector list with its
// parent's, so the count multiplies with depth. It stops here rather
// than wherever the machine runs out.
const int NEST_MAX_SELECTORS = 256

// How many `&`s the last nestSubstitute replaced. One value comes out
// of a function (FINDINGS.md, "one value out of a function") and this
// one is read by the only caller, immediately.
int nestLastAmps = 0

// Replaces every `&` outside parentheses and strings in `sel` with
// `parent`. A selector with no `&` at all gets one in front, as a
// descendant: that is the relation CSS Nesting 1 implies for a nested
// selector that does not say where the parent goes (§2). An `&` inside
// a functional pseudo-class is left alone, so the selector parser
// refuses it rather than this quietly substituting a complex selector
// where only a compound may stand.
text func nestSubstitute(sel:ascii, parent:text) {
    nestLastAmps = 0
    text out = ''
    int n = sel.length
    int i = 0
    int start = 0
    int depth = 0
    while i < n {
        int c = sel.charCodeAt(i)
        if c == CH_QUOTE || c == CH_APOS {
            i = skipQuoted(sel, i)
            continue
        }
        if c == CH_LPAREN { depth++  i++  continue }
        if c == CH_RPAREN { depth--  i++  continue }
        if c == CH_AMP && depth <= 0 {
            out = out + sel.slice(start, i).toText() + parent
            nestLastAmps++
            i++
            start = i
            continue
        }
        i++
    }
    out = out + sel.slice(start, n).toText()
    if nestLastAmps == 0 {
        nestLastAmps = 1
        return parent + ' ' + out
    }
    return out
}

// The selector texts one rule's prelude expands to, given the selectors
// of the rule it is written inside. `outAmps` and `outParentSpec` carry
// what the specificity correction below needs: how many `&`s each text
// replaced, and the weight of the parent branch each replaced them
// with.
//
// Outside any rule there is no parent list, and `&` is `:scope`, which
// for a stylesheet is the root element. A branch with no `&` there is
// itself, with nothing put in front of it.
void func nestExpand(prelude:ascii, parents:arr[text], parentSpecs:arr[int],
                     outTexts:arr[text], outAmps:arr[int], outParentSpec:arr[int]) {
    arr[ascii] branches = splitOnCommas(prelude)
    // A branch is used where it sits rather than bound to a local:
    // `ascii one = branches[b]` aliases a buffer the compiler never
    // retained and releases it twice (see FINDINGS.md, "ascii aliases
    // are not retained").
    if parents.length == 0 {
        for int b = 0, b < branches.length, b++ {
            if branches[b].length == 0 { continue }
            // A top-level branch with no `&` keeps its own text: the
            // descendant `:root ` nestSubstitute would put in front
            // says nothing, every element being under the root, but it
            // would add the weight of a pseudo-class that is not there.
            if asciiIndexOf(branches[b], '&', 0) < 0 {
                outTexts.push(branches[b].toText())
            } else {
                outTexts.push(nestSubstitute(branches[b], ':root'))
            }
            outAmps.push(0)
            outParentSpec.push(0)
        }
        return
    }
    for int p = 0, p < parents.length, p++ {
        for int b = 0, b < branches.length, b++ {
            if outTexts.length >= NEST_MAX_SELECTORS { return }
            if branches[b].length == 0 { continue }
            outTexts.push(nestSubstitute(branches[b], parents[p]))
            outAmps.push(nestLastAmps)
            outParentSpec.push(parentSpecs[p])
        }
    }
}

// The greatest of a parent list's weights, which is what `&` counts as
// however many branches there are and whichever one a match came
// through (CSS Nesting 1 §3). A packed triple compares as an integer,
// so this is the ordinary maximum.
int func nestMaxSpec(specs:arr[int]) {
    int best = 0
    for int i = 0, i < specs.length, i++ {
        if specs[i] > best { best = specs[i] }
    }
    return best
}

// Parses the expanded texts and corrects each one's weight. Reading the
// text of one branch computes that branch's own specificity, and the
// standard wants the whole list's maximum, so the difference is added
// back once per `&` that was substituted. Returns false if any of them
// is unparseable, which invalidates the rule as any bad selector in a
// list does (Selectors 3 §4).
bool func nestBuildSelectors(texts:arr[text], amps:arr[int], parentSpecs:arr[int],
                             parentMax:int, out:arr[Selector], outSpecs:arr[int]) {
    for int i = 0, i < texts.length, i++ {
        arr[Selector] parsed = parseSelectorList(texts[i].toAscii())
        if parsed.length != 1 || parsed[0].unsupported { return false }
        Selector sel = parsed[0]
        if amps[i] > 0 && parentMax != parentSpecs[i] {
            int dIds = specIds(parentMax) - specIds(parentSpecs[i])
            int dCls = specClasses(parentMax) - specClasses(parentSpecs[i])
            int dTyp = specTypes(parentMax) - specTypes(parentSpecs[i])
            int ids = specIds(sel.specificity) + amps[i] * dIds
            int cls = specClasses(sel.specificity) + amps[i] * dCls
            int typ = specTypes(sel.specificity) + amps[i] * dTyp
            sel.specificity = packSpecificity(ids < 0 ? 0 : ids,
                                              cls < 0 ? 0 : cls,
                                              typ < 0 ? 0 : typ)
        }
        out.push(sel)
        outSpecs.push(sel.specificity)
    }
    return out.length > 0
}

// A run of declarations written directly in a rule's body becomes a
// rule of its own, with that rule's selectors and its own place in
// source order. CSS Nesting 1 makes a declaration that follows a nested
// rule cascade after it, so the runs on either side of one cannot be
// gathered together.
void func nestFlushDecls(sheet:Stylesheet, src:ascii, from:int, to:int,
                         parents:arr[text], parentSpecs:arr[int]) {
    if to <= from || parents.length == 0 { return }
    ascii run = asciiTrim(src.slice(from, to))
    if run.length == 0 { return }
    Rule r
    r.decls = parseDeclarations(run)
    if r.decls.length == 0 { return }
    for int k = 0, k < parents.length, k++ {
        arr[Selector] parsed = parseSelectorList(parents[k].toAscii())
        if parsed.length != 1 || parsed[0].unsupported { return }
        Selector sel = parsed[0]
        // The parent's weight is the corrected one, not what reading
        // its text again computes.
        sel.specificity = parentSpecs[k]
        r.selectors.push(sel)
    }
    if r.selectors.length == 0 { return }
    r.order = cssRuleCounter
    r.layer = cssCurrentLayer
    r.containerQuery = cssCurrentContainerQuery
    cssRuleCounter++
    sheet.rules.push(r)
}

// Walks a stylesheet, or the body of one style rule when `parents`
// holds that rule's selectors. The two productions differ in one thing:
// inside a rule body a run of declarations belongs to the rule, and at
// the top of a stylesheet there is nothing for one to belong to.
// The two tokens §5.4.1 ignores, built once rather than per rule.
ascii cssCdo = '<!--'.toAscii()
ascii cssCdc = '-->'.toAscii()

// `topLevel` is CSS Syntax 3 §5.4.1's flag of the same name: a CDO
// (`<!--`) and a CDC (`-->`) are ignored where a stylesheet's own rules
// are read and nowhere else, so an at-rule's body and a nested rule's
// body are parsed with it unset.
void func parseRulesInto(sheet:Stylesheet, src:ascii, parents:arr[text], parentSpecs:arr[int],
                         topLevel:bool) {
    int n = src.length
    int i = 0
    // Where the run of declarations being gathered began. Each run ends
    // at the nested rule or at-rule that interrupts it, or at the end
    // of the body.
    int declStart = 0
    int parentMax = nestMaxSpec(parentSpecs)
    while i < n {
        int c = src.charCodeAt(i)
        if isSpaceCode(c) {
            i++
            continue
        }
        // They are the wrapper an old page put round its `<style>` so
        // that a browser which did not know the tag would not print the
        // contents. Tested only here, where a rule or a declaration
        // begins: a `-->` that follows name characters is not a CDC at
        // all -- the identifier takes both hyphens and the `>` left
        // over is a child combinator, which is what Chromium's
        // `selectorText` for `a-->b` says, and a test asserts.
        if topLevel && c == CH_LT && asciiStartsWith(src, cssCdo, i) { i = i + 4  continue }
        if topLevel && c == CH_MINUS && asciiStartsWith(src, cssCdc, i) { i = i + 3  continue }
        if c == CH_AT {
            nestFlushDecls(sheet, src, declStart, i, parents, parentSpecs)
            int nameEnd = scanIdentAt(src, i + 1)
            ascii atName = asciiLower(src.slice(i + 1, nameEnd))
            // find whichever comes first: ';' or '{'
            int semi = asciiIndexOf(src, ';', nameEnd)
            int brace = asciiIndexOf(src, '{', nameEnd)
            if brace < 0 || (semi >= 0 && semi < brace) {
                // a statement at-rule, ending at the semicolon
                if atName == 'namespace' {
                    int stop = semi < 0 ? n : semi
                    arr[ascii] parts = namespacePreludeTokens(asciiTrim(src.slice(nameEnd, stop)))
                    if parts.length == 1 {
                        cssDefaultNamespace = parseNamespaceUri(parts[0])
                    } else if parts.length >= 2 {
                        cssNamespacePrefixes[parts[0].toText()] = parseNamespaceUri(parts[1])
                    }
                } else if atName == 'layer' {
                    // `@layer a, b, c;` declares the order without
                    // giving any of them rules, which is the whole
                    // reason the statement form exists.
                    int stop = semi < 0 ? n : semi
                    arr[ascii] names = splitOnCommas(asciiTrim(src.slice(nameEnd, stop)))
                    for int k = 0, k < names.length, k++ {
                        ascii one = asciiTrim(names[k])
                        if one.length > 0 { declareLayer(qualifiedLayerName(asciiLower(one).toText())) }
                    }
                }
                i = semi < 0 ? n : semi + 1
                declStart = i
                continue
            }
            int blockEnd = skipBlock(src, brace)
            if atName == 'media' {
                ascii query = asciiTrim(src.slice(nameEnd, brace))
                if evaluateMediaQuery(query) {
                    int close = blockEnd - 1
                    if close < brace + 1 { close = brace + 1 }
                    parseRulesInto(sheet, src.slice(brace + 1, close), parents, parentSpecs, false)
                }
            } else if atName == 'supports' {
                if evaluateSupportsCondition(asciiTrim(src.slice(nameEnd, brace))) {
                    int close = blockEnd - 1
                    if close < brace + 1 { close = brace + 1 }
                    parseRulesInto(sheet, src.slice(brace + 1, close), parents, parentSpecs, false)
                }
            } else if atName == 'counter-style' {
                // The name is the prelude, and the body is an ordinary
                // declaration list.
                text csName = asciiLower(asciiTrim(src.slice(nameEnd, brace))).toText()
                int close = blockEnd - 1
                if close < brace + 1 { close = brace + 1 }
                if csName != '' {
                    cssCounterStyles[csName] = parseCounterStyleBody(src.slice(brace + 1, close))
                }
            } else if atName == 'page' {
                // The prelude is the page selector and the body an
                // ordinary declaration list. Nothing is resolved here:
                // which rules speak for a page depends on its number,
                // and that is pagination's to know.
                int close = blockEnd - 1
                if close < brace + 1 { close = brace + 1 }
                parsePageRule(src.slice(nameEnd, brace), src.slice(brace + 1, close))
            } else if atName == 'container' {
                // The rules inside go into the sheet like any others,
                // each tagged with this query. Nothing is evaluated
                // here: the container's size is layout's to know.
                int close = blockEnd - 1
                if close < brace + 1 { close = brace + 1 }
                text cond = containerPreludeCondition(src.slice(nameEnd, brace))
                int outerQuery = cssCurrentContainerQuery
                int q = declareContainerQuery(cqSplitName, cond)
                // Past CQ_MAX queries a sheet keeps its rules but they
                // are gated on the innermost query that did fit, which
                // is written down rather than silently dropped.
                if q != CQ_NONE { cssCurrentContainerQuery = q }
                parseRulesInto(sheet, src.slice(brace + 1, close), parents, parentSpecs, false)
                cssCurrentContainerQuery = outerQuery
            } else if atName == 'layer' {
                int close = blockEnd - 1
                if close < brace + 1 { close = brace + 1 }
                ascii layerName = asciiTrim(src.slice(nameEnd, brace))
                int outerLayer = cssCurrentLayer
                text outerName = cssCurrentLayerName
                text full = ''
                if layerName.length == 0 {
                    // An anonymous layer is a layer nothing can name
                    // again, so it gets a name no stylesheet can write.
                    cssAnonymousLayers++
                    full = qualifiedLayerName(`%anonymous${cssAnonymousLayers}`)
                } else {
                    full = qualifiedLayerName(asciiLower(layerName).toText())
                }
                cssCurrentLayer = declareLayer(full)
                cssCurrentLayerName = full
                parseRulesInto(sheet, src.slice(brace + 1, close), parents, parentSpecs, false)
                cssCurrentLayer = outerLayer
                cssCurrentLayerName = outerName
            }
            // @font-face, @keyframes, @import ...: skipped
            i = blockEnd
            declStart = i
            continue
        }
        if c == CH_RBRACE {
            nestFlushDecls(sheet, src, declStart, i, parents, parentSpecs)
            i++
            declStart = i
            continue
        }
        // From here to the next `;` or `{` is either a declaration or a
        // rule's prelude, and which one is not known until the
        // terminator is. Strings and parentheses are stepped over, so a
        // brace in `url("x{y")` starts nothing.
        int segStart = i
        int j = i
        int stop = 0
        while j < n {
            int d = src.charCodeAt(j)
            if d == CH_QUOTE || d == CH_APOS {
                j = skipQuoted(src, j)
                continue
            }
            if d == CH_LPAREN {
                j = matchParen(src, j) + 1
                continue
            }
            if d == CH_SEMI || d == CH_LBRACE || d == CH_RBRACE {
                stop = d
                break
            }
            j++
        }
        if stop != CH_LBRACE {
            // A declaration, which joins the run already being
            // gathered rather than ending it.
            i = stop == CH_SEMI ? j + 1 : j
            if i <= segStart { i = segStart + 1 }
            continue
        }
        nestFlushDecls(sheet, src, declStart, segStart, parents, parentSpecs)
        int brace = j
        ascii prelude = src.slice(segStart, brace)
        int blockEnd = skipBlock(src, brace)
        int close = blockEnd - 1
        if close < brace + 1 { close = brace + 1 }
        ascii body = src.slice(brace + 1, close)
        i = blockEnd
        declStart = i

        arr[text] selTexts = []
        arr[int] selAmps = []
        arr[int] selParentSpec = []
        nestExpand(prelude, parents, parentSpecs, selTexts, selAmps, selParentSpec)
        arr[Selector] sels = []
        arr[int] selSpecs = []
        // "If any selector in the list cannot be parsed, the group of
        // selectors is invalid" -- the whole rule goes, not just that
        // selector, so an unknown pseudo-element cannot leave a rule
        // half-applied (Selectors 3 §4). A rule nested inside it goes
        // with it, having nothing left to hang from.
        if !nestBuildSelectors(selTexts, selAmps, selParentSpec, parentMax, sels, selSpecs) {
            continue
        }
        // A body with no brace and no at-rule in it cannot hold a
        // nested rule, which is every rule on a page that does not use
        // nesting: those take the path they always took, and pay one
        // scan for a byte that is not there.
        if asciiIndexOf(body, '{', 0) < 0 && asciiIndexOf(body, '@', 0) < 0 {
            Rule r
            r.selectors = sels
            r.decls = parseDeclarations(body)
            r.order = cssRuleCounter
            r.layer = cssCurrentLayer
            r.containerQuery = cssCurrentContainerQuery
            cssRuleCounter++
            if r.decls.length > 0 { sheet.rules.push(r) }
            continue
        }
        parseRulesInto(sheet, body, selTexts, selSpecs, false)
    }
    nestFlushDecls(sheet, src, declStart, n, parents, parentSpecs)
}

int func scanIdentAt(s:ascii, from:int) {
    int i = from
    while i < s.length && isNameCode(s.charCodeAt(i)) { i++ }
    return i
}

Stylesheet func parseStylesheet(src:ascii) {
    Stylesheet sheet
    if src == null { return sheet }
    arr[text] noParents = []
    arr[int] noSpecs = []
    parseRulesInto(sheet, stripCssComments(src), noParents, noSpecs, true)
    return sheet
}

// A readable dump for tests.
text func dumpSelector(sel:Selector) {
    text out = ''
    for int i = 0, i < sel.parts.length, i++ {
        Compound c = sel.parts[i]
        if c.combinator == COMB_DESCENDANT { out = out + ' ' }
        if c.combinator == COMB_CHILD { out = out + ' > ' }
        if c.combinator == COMB_ADJACENT { out = out + ' + ' }
        if c.combinator == COMB_SIBLING { out = out + ' ~ ' }
        out = out + (c.tag == '' ? '*' : c.tag)
        if c.id != '' { out = `${out}#${c.id}` }
        for int j = 0, j < c.classes.length, j++ { out = `${out}.${c.classes[j]}` }
        for int j = 0, j < c.attrs.length, j++ {
            AttrSel a = c.attrs[j]
            out = a.op == ATTR_EXISTS ? `${out}[${a.name}]` : `${out}[${a.name}${a.op}${a.value}]`
        }
        for int j = 0, j < c.pseudos.length, j++ { out = `${out}:${c.pseudos[j]}` }
        for int j = 0, j < c.nths.length, j++ {
            NthOf nth = c.nths[j]
            text ofText = ''
            for int k = 0, k < nth.of.length, k++ {
                ofText = ofText + (k > 0 ? ',' : '') + dumpSelector(nth.of[k])
            }
            text nthName = nth.fromEnd ? 'nth-last-child' : 'nth-child'
            out = `${out}:${nthName}:${nth.stepA}:${nth.offB} of ${ofText}`
        }
        if c.pseudoElement != '' { out = `${out}::${c.pseudoElement}` }
        for int j = 0, j < c.subs.length, j++ {
            SubSelector sub = c.subs[j]
            text fname = sub.kind == SUBSEL_NOT ? 'not'
                       : (sub.kind == SUBSEL_HAS ? 'has'
                       : (sub.kind == SUBSEL_WHERE ? 'where' : 'is'))
            text inner = ''
            for int k = 0, k < sub.alternatives.length, k++ {
                int ld = k < sub.leads.length ? sub.leads[k] : COMB_DESCENDANT
                text mark = ld == COMB_CHILD ? '> '
                          : (ld == COMB_ADJACENT ? '+ '
                          : (ld == COMB_SIBLING ? '~ ' : ''))
                inner = inner + (k > 0 ? ',' : '') + mark + dumpSelector(sub.alternatives[k])
            }
            out = `${out}:${fname}(${inner})`
        }
    }
    if sel.unsupported { out = out + '!' }
    return `${out}{${sel.specificity}}`
}

text func dumpStylesheet(sheet:Stylesheet) {
    text out = ''
    for int i = 0, i < sheet.rules.length, i++ {
        Rule r = sheet.rules[i]
        for int j = 0, j < r.selectors.length, j++ {
            if j > 0 { out = out + ', ' }
            text s = dumpSelector(r.selectors[j])
            out = out + s
        }
        out = out + ' {'
        for int j = 0, j < r.decls.length, j++ {
            Decl d = r.decls[j]
            text v = d.value.toText()
            out = `${out} ${d.name}: ${v}${d.important ? ' !important' : ''};`
        }
        out = out + ' }\n'
    }
    return out
}
