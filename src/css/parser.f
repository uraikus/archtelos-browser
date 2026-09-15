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
}

struct Compound {
    tag:text                // '' = any
    id:text                 // '' = none
    classes:arr[text]
    attrs:arr[AttrSel]
    pseudos:arr[text]       // e.g. 'first-child', 'nth-child:3'
    notSel:Compound         // the argument of :not(); meaningful only when hasNot
    hasNot:bool             // a struct field can never read as null (see FINDINGS.md), hence the flag
    combinator:int          // relation to the compound on its LEFT
    unsupported:bool
}

struct Selector {
    parts:arr[Compound]     // left to right
    specificity:int         // ids * 10000 + classes/attrs/pseudos * 100 + types
    unsupported:bool
}

struct Decl {
    name:text
    value:ascii
    important:bool
}

struct Rule {
    selectors:arr[Selector]
    decls:arr[Decl]
    order:int               // source order across every sheet
}

struct Stylesheet {
    rules:arr[Rule]
}

int cssRuleCounter = 0
// The viewport width @media queries are evaluated against; set by the
// browser before parsing author sheets.
int cssViewportWidth = 800
int cssViewportHeight = 600

// ---- comments and block skipping -----------------------------------

ascii func stripCssComments(src:ascii) {
    if asciiIndexOf(src, '/*', 0) < 0 { return src }
    text out = ''
    int n = src.length
    int runStart = 0
    int i = 0
    while i < n {
        if src.charCodeAt(i) == CH_SLASH && i + 1 < n && src.charCodeAt(i + 1) == CH_STAR {
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
    // a vendor prefix or a custom property is not something we paint
    if name.charCodeAt(0) == CH_MINUS { return null }
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
    d.value = value
    d.important = important
    return d
}

// ---- selectors -----------------------------------------------------

Compound func newCompound() {
    Compound c
    c.tag = ''
    c.id = ''
    c.combinator = COMB_NONE
    return c
}

int selPos = 0
ascii selSrc = ''

int func scanIdent(from:int) {
    int i = from
    int n = selSrc.length
    while i < n {
        int c = selSrc.charCodeAt(i)
        if isNameCode(c) || c == CH_BACKSLASH { i++ }
        else { break }
    }
    return i
}

// Parses one compound selector starting at selPos (which must not be
// at whitespace); leaves selPos after it.
Compound func parseCompound() {
    Compound comp = newCompound()
    int n = selSrc.length
    bool any = false
    while selPos < n {
        int c = selSrc.charCodeAt(selPos)
        if c == CH_STAR {
            selPos++
            any = true
        } else if c == CH_HASH {
            int end = scanIdent(selPos + 1)
            comp.id = selSrc.slice(selPos + 1, end).toText()
            selPos = end
            any = true
        } else if c == CH_DOT {
            int end = scanIdent(selPos + 1)
            comp.classes.push(selSrc.slice(selPos + 1, end).toText())
            selPos = end
            any = true
        } else if c == CH_LBRACKET {
            int end = asciiIndexOf(selSrc, ']', selPos)
            if end < 0 { end = n }
            parseAttrSel(comp, selSrc.slice(selPos + 1, end))
            selPos = end + 1
            any = true
        } else if c == CH_COLON {
            int start = selPos + 1
            if start < n && selSrc.charCodeAt(start) == CH_COLON {
                // a pseudo-element: nothing here renders ::before/::after
                comp.unsupported = true
                start++
            }
            int end = scanIdent(start)
            ascii name = asciiLower(selSrc.slice(start, end))
            selPos = end
            if selPos < n && selSrc.charCodeAt(selPos) == CH_LPAREN {
                int close = matchParen(selSrc, selPos)
                ascii arg = asciiTrim(selSrc.slice(selPos + 1, close))
                selPos = close + 1
                if name == 'not' {
                    int savedPos = selPos
                    ascii savedSrc = dup(selSrc)
                    selSrc = arg
                    selPos = 0
                    comp.notSel = parseCompound()
                    comp.hasNot = true
                    if selPos < arg.length { comp.unsupported = true }
                    selSrc = savedSrc
                    selPos = savedPos
                } else if name == 'nth-child' {
                    ascii a = asciiLower(arg)
                    if a == 'odd' || a == 'even' || (a.length > 0 && isDigitCode(a.charCodeAt(0)) && a.toText().toInt() > 0) {
                        comp.pseudos.push(`nth-child:${a.toText()}`)
                    } else {
                        comp.unsupported = true
                    }
                } else {
                    comp.unsupported = true
                }
            } else {
                if name == 'first-child' || name == 'last-child' || name == 'only-child'
                    || name == 'root' || name == 'link' || name == 'any-link' || name == 'first-of-type' || name == 'last-of-type' {
                    comp.pseudos.push(name.toText())
                } else {
                    // :hover, :focus, :visited, :checked ... never match here
                    comp.unsupported = true
                }
            }
            any = true
        } else if isNameCode(c) && !any {
            int end = scanIdent(selPos)
            comp.tag = asciiLower(selSrc.slice(selPos, end)).toText()
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

void func parseAttrSel(comp:Compound, inner:ascii) {
    AttrSel a
    a.op = ATTR_EXISTS
    a.value = ''
    int n = inner.length
    int i = 0
    while i < n && isNameCode(inner.charCodeAt(i)) { i++ }
    a.name = asciiLower(inner.slice(0, i)).toText()
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
        // a trailing " i" flag would be case-insensitivity; ignore it
        if i < end && (inner.charCodeAt(i) == CH_QUOTE || inner.charCodeAt(i) == CH_APOS) {
            int q = inner.charCodeAt(i)
            int close = i + 1
            while close < end && inner.charCodeAt(close) != q { close++ }
            a.value = inner.slice(i + 1, close).toText()
        } else {
            a.value = inner.slice(i, end).toText()
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
    sel.specificity = computeSpecificity(sel)
    return sel
}

int func compoundSpecificity(c:Compound) {
    int s = 0
    if c.id != '' { s = s + 10000 }
    s = s + (c.classes.length + c.attrs.length + c.pseudos.length) * 100
    if c.tag != '' { s = s + 1 }
    if c.hasNot { s = s + compoundSpecificity(c.notSel) }
    return s
}

int func computeSpecificity(sel:Selector) {
    int s = 0
    for int i = 0, i < sel.parts.length, i++ {
        s = s + compoundSpecificity(sel.parts[i])
    }
    return s
}

// Splits a selector list on top-level commas.
arr[Selector] func parseSelectorList(prelude:ascii) {
    arr[Selector] out = []
    int n = prelude.length
    int depth = 0
    int start = 0
    for int i = 0, i <= n, i++ {
        int c = i < n ? prelude.charCodeAt(i) : CH_COMMA
        if c == CH_LPAREN || c == CH_LBRACKET { depth++ }
        else if c == CH_RPAREN || c == CH_RBRACKET { depth-- }
        else if c == CH_COMMA && depth <= 0 {
            ascii piece = asciiTrim(prelude.slice(start, i))
            if piece.length > 0 { out.push(parseSelector(piece)) }
            start = i + 1
        }
    }
    return out
}

// ---- @media ---------------------------------------------------------

// Evaluates a media query list against the viewport. Understands
// `all`, `screen`, `print`, `not`, `and`, `,` and the (min|max)-width
// / (min|max)-height features; any other feature is false.
bool func evaluateMediaQuery(query:ascii) {
    arr[ascii] alternatives = asciiSplitChar(asciiLower(query), CH_COMMA)
    if alternatives.length == 0 { return true }
    for int i = 0, i < alternatives.length, i++ {
        if evaluateOneMediaQuery(alternatives[i]) { return true }
    }
    return false
}

bool func evaluateOneMediaQuery(q:ascii) {
    bool negate = false
    // a copy, not `ascii s = q`: rebinding an ascii parameter to a
    // local double-releases it (FINDINGS.md, "ascii parameter aliasing")
    ascii s = q.slice(0, q.length)
    if asciiStartsWith(s, 'not ', 0) {
        negate = true
        s = asciiTrim(s.slice(4, s.length))
    }
    if asciiStartsWith(s, 'only ', 0) { s = asciiTrim(s.slice(5, s.length)) }
    bool result = true
    // split on ' and '
    int n = s.length
    int start = 0
    while start < n {
        int andAt = asciiIndexOf(s, ' and ', start)
        int end = andAt < 0 ? n : andAt
        ascii term = asciiTrim(s.slice(start, end))
        if !evaluateMediaTerm(term) { result = false }
        start = andAt < 0 ? n : andAt + 5
    }
    return negate ? !result : result
}

bool func evaluateMediaTerm(term:ascii) {
    if term.length == 0 || term == 'all' || term == 'screen' { return true }
    if term == 'print' || term == 'speech' { return false }
    if term.charCodeAt(0) == CH_LPAREN && asciiEndsWith(term, ')') {
        ascii inner = asciiTrim(term.slice(1, term.length - 1))
        int colon = asciiIndexOf(inner, ':', 0)
        if colon < 0 {
            ascii feat = asciiTrim(inner)
            return feat == 'color' || feat == 'hover'
        }
        ascii feature = asciiTrim(inner.slice(0, colon))
        ascii value = asciiTrim(inner.slice(colon + 1, inner.length))
        parseNumberAt(value, 0)
        if !numOk { return false }
        float v = numValue
        ascii unit = asciiLower(value.slice(numEnd, value.length))
        if unit == 'em' || unit == 'rem' { v = v * 16.0 }
        if feature == 'min-width' { return cssViewportWidth.toFloat() >= v }
        if feature == 'max-width' { return cssViewportWidth.toFloat() <= v }
        if feature == 'min-height' { return cssViewportHeight.toFloat() >= v }
        if feature == 'max-height' { return cssViewportHeight.toFloat() <= v }
        if feature == 'width' { return cssViewportWidth.toFloat() == v }
        return false
    }
    return false
}

// ---- stylesheets ------------------------------------------------------

void func parseRulesInto(sheet:Stylesheet, src:ascii) {
    int n = src.length
    int i = 0
    while i < n {
        int c = src.charCodeAt(i)
        if isSpaceCode(c) {
            i++
            continue
        }
        if c == CH_AT {
            int nameEnd = scanIdentAt(src, i + 1)
            ascii atName = asciiLower(src.slice(i + 1, nameEnd))
            // find whichever comes first: ';' or '{'
            int semi = asciiIndexOf(src, ';', nameEnd)
            int brace = asciiIndexOf(src, '{', nameEnd)
            if brace < 0 || (semi >= 0 && semi < brace) {
                i = semi < 0 ? n : semi + 1
                continue
            }
            int blockEnd = skipBlock(src, brace)
            if atName == 'media' {
                ascii query = asciiTrim(src.slice(nameEnd, brace))
                if evaluateMediaQuery(query) {
                    int close = blockEnd - 1
                    if close < brace + 1 { close = brace + 1 }
                    parseRulesInto(sheet, src.slice(brace + 1, close))
                }
            } else if atName == 'supports' || atName == 'layer' {
                int close = blockEnd - 1
                if close < brace + 1 { close = brace + 1 }
                parseRulesInto(sheet, src.slice(brace + 1, close))
            }
            // @font-face, @keyframes, @page, @import ...: skipped
            i = blockEnd
            continue
        }
        if c == CH_RBRACE {
            i++
            continue
        }
        int brace = asciiIndexOf(src, '{', i)
        if brace < 0 { break }
        ascii prelude = src.slice(i, brace)
        int blockEnd = skipBlock(src, brace)
        int close = blockEnd - 1
        if close < brace + 1 { close = brace + 1 }
        ascii body = src.slice(brace + 1, close)
        Rule r
        r.selectors = parseSelectorList(prelude)
        r.decls = parseDeclarations(body)
        r.order = cssRuleCounter
        cssRuleCounter++
        if r.selectors.length > 0 && r.decls.length > 0 { sheet.rules.push(r) }
        i = blockEnd
    }
}

int func scanIdentAt(s:ascii, from:int) {
    int i = from
    while i < s.length && isNameCode(s.charCodeAt(i)) { i++ }
    return i
}

Stylesheet func parseStylesheet(src:ascii) {
    Stylesheet sheet
    if src == null { return sheet }
    parseRulesInto(sheet, stripCssComments(src))
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
        if c.hasNot {
            Selector inner
            inner.parts.push(c.notSel)
            text innerText = dumpSelector(inner)
            out = `${out}:not(${innerText})`
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
