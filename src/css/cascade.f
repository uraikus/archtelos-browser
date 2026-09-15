// The cascade: which declarations apply to an element, in what order,
// and what computed Style they produce.

import parser.f
import ../dom/node.f
import ../util/color.f
import ua.f

const int ORIGIN_UA = 0
const int ORIGIN_AUTHOR = 1
const int ORIGIN_INLINE = 2

const int ROOT_FONT_SIZE = 16
const int LEN_INVALID = -1

// hot-spot accumulators, reported with ARCHTELOS_TIMING=1
int profCollectMs = 0
int profSortMs = 0
int profApplyMs = 0
int profComputeMs = 0
int profElements = 0
int profMatchesTotal = 0
int profHintsMs = 0
int profSelectorTests = 0

text func cascadeProfile() {
    return `[timing] cascade detail: ${profElements} elements, ${profMatchesTotal} matched decls; collect ${profCollectMs} ms (hints ${profHintsMs} ms, ${profSelectorTests} selector tests), sort ${profSortMs} ms, apply ${profApplyMs} ms, compute ${profComputeMs} ms`
}


struct Match {
    decl:Decl
    weight:int
}

arr[Stylesheet] cascadeSheets = []
arr[int] cascadeOrigins = []

// Rules are indexed by the rightmost compound of each selector -- an
// id, a class, a tag, or '*' -- so an element only tests the selectors
// that could possibly match it. A map value cannot be an array in
// Festina, hence the Bucket wrapper.
struct RuleRef {
    rule:Rule
    sel:Selector
    origin:int
}

struct Bucket {
    refs:arr[RuleRef]
}

map[Bucket] ruleIndex = {}
map[int] bucketSizes = {}       // key -> number of refs, so existence is a scalar lookup

void func cascadeReset() {
    cascadeSheets = []
    cascadeOrigins = []
    ruleIndex = {}
    bucketSizes = {}
    Stylesheet ua = parseStylesheet(uaStylesheetText.toAscii())
    cascadeSheets.push(ua)
    cascadeOrigins.push(ORIGIN_UA)
    indexSheet(ua, ORIGIN_UA)
}

void func cascadeAddAuthorSheet(sheet:Stylesheet) {
    cascadeSheets.push(sheet)
    cascadeOrigins.push(ORIGIN_AUTHOR)
    indexSheet(sheet, ORIGIN_AUTHOR)
}

text func selectorKey(sel:Selector) {
    Compound c = sel.parts[sel.parts.length - 1]
    if c.id != '' { return `#${c.id}` }
    if c.classes.length > 0 { return `.${c.classes[0]}` }
    if c.tag != '' { return c.tag }
    return '*'
}

void func addToBucket(key:text, ref:RuleRef) {
    if bucketSizes[key] == null {
        Bucket fresh
        ruleIndex[key] = fresh
        bucketSizes[key] = 0
    }
    ruleIndex[key].refs.push(ref)
    bucketSizes[key] = bucketSizes[key] + 1
}

void func indexSheet(sheet:Stylesheet, origin:int) {
    for int r = 0, r < sheet.rules.length, r++ {
        Rule rule = sheet.rules[r]
        for int i = 0, i < rule.selectors.length, i++ {
            Selector sel = rule.selectors[i]
            if sel.unsupported || sel.parts.length == 0 { continue }
            RuleRef ref
            ref.rule = rule
            ref.sel = sel
            ref.origin = origin
            addToBucket(selectorKey(sel), ref)
        }
    }
}

// Registers every <style> element of a document, in order, as an
// author sheet. (<link rel=stylesheet> needs a fetch, so the browser
// shell handles those itself, interleaved in document order.)
void func cascadeAddDocumentStyles(doc:Node) {
    arr[Node] styles = []
    collectElements(doc, 'style', styles)
    for int i = 0, i < styles.length, i++ {
        Node st = styles[i]
        text media = getAttr(st, 'media')
        if media != null && media.toAscii() != null && !evaluateMediaQuery(media.toAscii()) { continue }
        text css = textContent(st)
        ascii a = css.toAscii()
        if a == null { a = textToAsciiSafeForCss(css) }
        cascadeAddAuthorSheet(parseStylesheet(a))
    }
}

// The cascade sorts on origin and importance first, then specificity,
// then source order (CSS Cascade 4 §6.1). Importance *inverts* the
// origin order: a normal author declaration beats a normal user-agent
// one, and an important user-agent declaration beats an important
// author one. Inline style is author origin, ranked above author rules.
//
//   normal UA < normal author < normal inline
//             < important author < important inline < important UA
int func originRank(important:bool, origin:int) {
    if !important { return origin }
    if origin == ORIGIN_UA { return 5 }
    if origin == ORIGIN_INLINE { return 4 }
    return 3
}

int func matchWeight(important:bool, origin:int, specificity:int, order:int) {
    return originRank(important, origin) * 100000000000000000
         + specificity * 10000000
         + order
}

// ---- selector matching ------------------------------------------------
//
// Every function here takes a node ID and reads the node through
// nodeRegistry inline. Passing the Node itself would be natural, but a
// forwarded struct parameter is released on exit with a collector walk
// of its subtree, and the ancestor loop forwards <body> and <html> --
// the whole document -- for every descendant selector it rejects
// (FINDINGS.md, "cycle trials"). Ids make the matcher allocation-free.

bool func attrMatches(nid:int, a:AttrSel) {
    if !hasAttrOf(nid, a.name) { return false }
    if a.op == ATTR_EXISTS { return true }
    text v = attrOf(nid, a.name)
    if v == null { v = '' }
    if a.op == ATTR_EQUALS { return v == a.value }
    ascii av = v.toAscii()
    ascii want = a.value.toAscii()
    if av == null || want == null { return false }
    if a.op == ATTR_INCLUDES {
        arr[ascii] words = asciiSplitSpace(av)
        for int i = 0, i < words.length, i++ {
            if words[i] == want { return true }
        }
        return false
    }
    if a.op == ATTR_PREFIX { return want.length > 0 && asciiStartsWith(av, want, 0) }
    if a.op == ATTR_SUFFIX { return want.length > 0 && asciiEndsWith(av, want) }
    if a.op == ATTR_SUBSTRING { return want.length > 0 && asciiIndexOf(av, want, 0) >= 0 }
    if a.op == ATTR_DASH { return av == want || asciiStartsWith(av, want + '-', 0) }
    return false
}

bool func pseudoMatches(nid:int, name:text) {
    if name == 'first-child' { return prevElementSiblingOf(nid) == 0 }
    if name == 'last-child' { return nextElementSiblingOf(nid) == 0 }
    if name == 'only-child' { return prevElementSiblingOf(nid) == 0 && nextElementSiblingOf(nid) == 0 }
    if name == 'root' { return nodeRegistry[nid].tag == 'html' }
    if name == 'link' || name == 'any-link' {
        return (nodeRegistry[nid].tag == 'a' || nodeRegistry[nid].tag == 'area') && hasAttrOf(nid, 'href')
    }
    if name == 'first-of-type' || name == 'last-of-type' {
        bool forward = name == 'last-of-type'
        int sib = forward ? nextElementSiblingOf(nid) : prevElementSiblingOf(nid)
        while sib > 0 {
            if nodeRegistry[sib].tag == nodeRegistry[nid].tag { return false }
            sib = forward ? nextElementSiblingOf(sib) : prevElementSiblingOf(sib)
        }
        return true
    }
    ascii a = name.toAscii()
    if asciiStartsWith(a, 'nth-child:', 0) {
        ascii arg = a.slice(10, a.length)
        int pos = 1
        int sib = prevElementSiblingOf(nid)
        while sib > 0 {
            pos++
            sib = prevElementSiblingOf(sib)
        }
        if arg == 'odd' { return pos % 2 == 1 }
        if arg == 'even' { return pos % 2 == 0 }
        return pos == arg.toText().toInt()
    }
    return false
}

bool func matchCompound(nid:int, c:Compound) {
    if nodeRegistry[nid].kind != NODE_ELEMENT { return false }
    if c.unsupported { return false }
    if c.tag != '' && c.tag != nodeRegistry[nid].tag { return false }
    if c.id != '' {
        text id = attrOf(nid, 'id')
        if id == null || id != c.id { return false }
    }
    for int i = 0, i < c.classes.length, i++ {
        if !hasClassOf(nid, c.classes[i]) { return false }
    }
    for int i = 0, i < c.attrs.length, i++ {
        if !attrMatches(nid, c.attrs[i]) { return false }
    }
    for int i = 0, i < c.pseudos.length, i++ {
        if !pseudoMatches(nid, c.pseudos[i]) { return false }
    }
    if c.hasNot {
        if matchCompound(nid, c.notSel) { return false }
    }
    return true
}

// Matches parts[0..index] against the node, right to left.
bool func matchFrom(nid:int, sel:Selector, index:int) {
    if !matchCompound(nid, sel.parts[index]) { return false }
    if index == 0 { return true }
    int comb = sel.parts[index].combinator
    if comb == COMB_CHILD {
        int parent = nodeRegistry[nid].parentId
        if parent <= 0 { return false }
        return matchFrom(parent, sel, index - 1)
    }
    if comb == COMB_ADJACENT {
        int prev = prevElementSiblingOf(nid)
        if prev == 0 { return false }
        return matchFrom(prev, sel, index - 1)
    }
    if comb == COMB_SIBLING {
        int prev = prevElementSiblingOf(nid)
        while prev > 0 {
            if matchFrom(prev, sel, index - 1) { return true }
            prev = prevElementSiblingOf(prev)
        }
        return false
    }
    // descendant
    int anc = nodeRegistry[nid].parentId
    while anc > 0 {
        if nodeRegistry[anc].kind != NODE_ELEMENT { return false }
        if matchFrom(anc, sel, index - 1) { return true }
        anc = nodeRegistry[anc].parentId
    }
    return false
}

bool func matchSelector(nid:int, sel:Selector) {
    if sel.unsupported || sel.parts.length == 0 { return false }
    return matchFrom(nid, sel, sel.parts.length - 1)
}

// Node-taking conveniences for callers outside the hot path.
bool func hasClass(n:Node, cls:text) {
    return hasClassOf(n.id, cls)
}

bool func selectorMatchesNode(n:Node, sel:Selector) {
    return matchSelector(n.id, sel)
}

// ---- collecting declarations ---------------------------------------

int func compareMatches(a:Match, b:Match) {
    if a.weight < b.weight { return -1 }
    if a.weight > b.weight { return 1 }
    return 0
}

void func addMatch(matches:arr[Match], name:text, value:ascii, weight:int) {
    Decl d
    d.name = `${name}`          // a fresh copy: see FINDINGS.md, "text parameters"
    d.value = dup(value)
    d.important = false
    Match m
    m.decl = d
    m.weight = weight
    matches.push(m)
}

// HTML's presentational attributes, expressed as author declarations
// of zero specificity.
void func presentationalHints(n:Node, matches:arr[Match]) {
    int w = matchWeight(false, ORIGIN_AUTHOR, 0, 0)
    text tag = n.tag
    text align = getAttr(n, 'align')
    if align != null {
        ascii a = asciiLower(align.toAscii())
        if a != null {
            if tag == 'table' || tag == 'img' {
                if a == 'center' && tag == 'table' {
                    addMatch(matches, 'margin-left', 'auto', w)
                    addMatch(matches, 'margin-right', 'auto', w)
                }
            } else if a == 'left' || a == 'center' || a == 'right' {
                addMatch(matches, 'text-align', a, w)
            }
        }
    }
    text bg = getAttr(n, 'bgcolor')
    if bg != null && bg.toAscii() != null { addMatch(matches, 'background-color', bg.toAscii(), w) }
    text bgi = getAttr(n, 'background')
    if bgi == null && tag == 'body' { }
    if tag == 'font' {
        text c = getAttr(n, 'color')
        if c != null && c.toAscii() != null { addMatch(matches, 'color', c.toAscii(), w) }
        text face = getAttr(n, 'face')
        if face != null && face.toAscii() != null { addMatch(matches, 'font-family', face.toAscii(), w) }
        text size = getAttr(n, 'size')
        if size != null {
            int s = size.toInt()
            ascii sa = size.toAscii()
            if s != null && sa != null && sa.length > 0 {
                int c0 = sa.charCodeAt(0)
                if c0 == CH_PLUS || c0 == CH_MINUS { s = 3 + s }
                s = clampInt(s, 1, 7)
                ascii px = '16px'
                if s == 1 { px = '10px' }
                if s == 2 { px = '13px' }
                if s == 4 { px = '18px' }
                if s == 5 { px = '24px' }
                if s == 6 { px = '32px' }
                if s == 7 { px = '48px' }
                addMatch(matches, 'font-size', px, w)
            }
        }
    }
    if tag == 'img' || tag == 'table' || tag == 'td' || tag == 'th' || tag == 'hr' || tag == 'iframe' || tag == 'video' || tag == 'canvas' {
        text wa = getAttr(n, 'width')
        if wa != null { addDimensionHint(matches, 'width', wa, w) }
        text ha = getAttr(n, 'height')
        if ha != null && tag != 'td' && tag != 'th' { addDimensionHint(matches, 'height', ha, w) }
    }
    if tag == 'table' {
        text border = getAttr(n, 'border')
        if border != null && border.toInt() != null && border.toInt() > 0 {
            text bw = `${border.toInt()}px`
            addMatch(matches, 'border', (bw + ' solid #808080').toAscii(), w)
        }
        text cs = getAttr(n, 'cellspacing')
        if cs != null && cs.toInt() != null { addMatch(matches, 'border-spacing', `${cs.toInt()}px`.toAscii(), w) }
    }
    if tag == 'td' || tag == 'th' {
        int tbl = closestElementId(n, 'table')
        if tbl > 0 {
            text border = getAttr(nodeRegistry[tbl], 'border')
            if border != null && border.toInt() != null && border.toInt() > 0 {
                addMatch(matches, 'border', '1px solid #808080', w)
            }
            text cp = getAttr(nodeRegistry[tbl], 'cellpadding')
            if cp != null && cp.toInt() != null { addMatch(matches, 'padding', `${cp.toInt()}px`.toAscii(), w) }
        }
        if hasAttr(n, 'nowrap') { addMatch(matches, 'white-space', 'nowrap', w) }
    }
    if tag == 'hr' {
        if hasAttr(n, 'noshade') { addMatch(matches, 'border-color', '#808080', w) }
    }
    if tag == 'input' {
        text ty = getAttr(n, 'type')
        if ty != null && (textLower(ty) == 'checkbox' || textLower(ty) == 'radio') {
            addMatch(matches, 'width', '13px', w)
            addMatch(matches, 'height', '13px', w)
            addMatch(matches, 'padding', '0', w)
        }
    }
}

void func addDimensionHint(matches:arr[Match], prop:text, value:text, w:int) {
    ascii a = asciiTrim(value.toAscii())
    if a == null || a.length == 0 { return }
    parseNumberAt(a, 0)
    if !numOk { return }
    if numEnd < a.length && a.charCodeAt(numEnd) == CH_PERCENT {
        addMatch(matches, prop, a.slice(0, numEnd + 1), w)
    } else {
        addMatch(matches, prop, a.slice(0, numEnd) + 'px', w)
    }
}

// Rule objects are read through the index inline rather than bound to
// locals: the rule graph is cycle-capable (a Compound holds a
// Compound), and releasing a local alias of any part of it costs a
// collector walk of everything reachable from it (FINDINGS.md).
void func collectFromBucket(n:Node, key:text, matches:arr[Match]) {
    if bucketSizes[key] == null { return }
    // the bucket travels as a borrowed parameter: a struct read out of
    // a map is a retained temporary that is released after the
    // expression, and that release walks the whole rule graph
    collectFromBucketRefs(n, ruleIndex[key], matches)
}

void func collectFromBucketRefs(n:Node, b:Bucket, matches:arr[Match]) {
    int count = b.refs.length
    int nid = n.id
    for int i = 0, i < count, i++ {
        profSelectorTests++
        if !matchSelector(nid, b.refs[i].sel) { continue }
        int decls = b.refs[i].rule.decls.length
        int specificity = b.refs[i].sel.specificity
        int origin = b.refs[i].origin
        int order = b.refs[i].rule.order
        for int d = 0, d < decls, d++ {
            Match m
            m.decl = b.refs[i].rule.decls[d]
            m.weight = matchWeight(b.refs[i].rule.decls[d].important, origin, specificity, order)
            matches.push(m)
        }
    }
}

arr[Match] func collectMatches(n:Node) {
    arr[Match] matches = []
    int th = archtelosTiming ? now() : 0
    presentationalHints(n, matches)
    if archtelosTiming { profHintsMs = profHintsMs + (now() - th) }
    collectFromBucket(n, '*', matches)
    collectFromBucket(n, n.tag, matches)
    text id = getAttr(n, 'id')
    if id != null { collectFromBucket(n, `#${id}`, matches) }
    arr[text] classes = nodeClasses(n)
    for int i = 0, i < classes.length, i++ {
        collectFromBucket(n, `.${classes[i]}`, matches)
    }
    text inline = getAttr(n, 'style')
    if inline != null {
        ascii ia = inline.toAscii()
        if ia == null { ia = textToAsciiSafeForCss(inline) }
        arr[Decl] decls = parseDeclarations(stripCssComments(ia))
        for int d = 0, d < decls.length, d++ {
            Match m
            m.decl = decls[d]
            m.weight = matchWeight(decls[d].important, ORIGIN_INLINE, 0, d)
            matches.push(m)
        }
    }
    int t0 = archtelosTiming ? now() : 0
    matches.sort(compareMatches)
    if archtelosTiming { profSortMs = profSortMs + (now() - t0) }
    return matches
}

// A style attribute holding non-ASCII (a font name, say): rewrite the
// offending characters as '?' rather than dropping the whole thing.
ascii func textToAsciiSafeForCss(t:text) {
    text out = ''
    int i = 0
    while true {
        int cp = t.charCodeAt(i)
        if cp == null { break }
        text ch = cp < 128 ? cp.toChar() : '?'
        out = out + ch
        i++
    }
    return out.toAscii()
}

// ---- value tokenization -----------------------------------------------

// Splits a value on top-level whitespace, keeping parenthesized and
// quoted runs together.
arr[ascii] func cssTokens(value:ascii) {
    arr[ascii] out = []
    int n = value.length
    int i = 0
    while i < n {
        while i < n && isSpaceCode(value.charCodeAt(i)) { i++ }
        if i >= n { break }
        int start = i
        int depth = 0
        while i < n {
            int c = value.charCodeAt(i)
            if c == CH_QUOTE || c == CH_APOS {
                i = skipQuoted(value, i)
                continue
            }
            if c == CH_LPAREN { depth++ }
            else if c == CH_RPAREN { depth-- }
            else if isSpaceCode(c) && depth <= 0 { break }
            i++
        }
        out.push(value.slice(start, i))
    }
    return out
}

// ---- applying declarations (shorthand expansion) -------------------

void func setProp(props:map[text], name:text, value:ascii) {
    props[name] = value.toText()
}

// Reads a property back as a fresh ascii (null when absent). The map
// holds text because a text local made from a map entry is a private
// copy, where an ascii one would alias the entry (FINDINGS.md).
ascii func styleProp(props:map[text], name:text) {
    text v = props[name]
    if v == null { return null }
    return v.toAscii()
}

void func applyFourSides(props:map[text], prefix:text, suffix:text, value:ascii) {
    arr[ascii] t = cssTokens(value)
    if t.length == 0 { return }
    ascii top = dup(t[0])
    ascii right = dup(t.length > 1 ? t[1] : t[0])
    ascii bottom = dup(t.length > 2 ? t[2] : t[0])
    ascii left = dup(t.length > 3 ? t[3] : right)
    setProp(props, `${prefix}-top${suffix}`, top)
    setProp(props, `${prefix}-right${suffix}`, right)
    setProp(props, `${prefix}-bottom${suffix}`, bottom)
    setProp(props, `${prefix}-left${suffix}`, left)
}

bool func isBorderStyleKeyword(t:ascii) {
    return t == 'none' || t == 'solid' || t == 'hidden' || t == 'dashed' || t == 'dotted'
        || t == 'double' || t == 'groove' || t == 'ridge' || t == 'inset' || t == 'outset'
}

bool func isBorderWidthToken(t:ascii) {
    if t == 'thin' || t == 'medium' || t == 'thick' { return true }
    parseNumberAt(t, 0)
    return numOk
}

// border / border-top / ...: any order of width, style, color.
void func applyBorderShorthand(props:map[text], sides:arr[text], value:ascii) {
    arr[ascii] t = cssTokens(value)
    ascii width = 'medium'
    ascii style = 'none'
    ascii color = 'currentcolor'
    for int i = 0, i < t.length, i++ {
        ascii tok = asciiLower(t[i])
        if isBorderStyleKeyword(tok) { style = tok }
        else if isBorderWidthToken(tok) { width = tok }
        else { color = t[i] }
    }
    for int i = 0, i < sides.length, i++ {
        setProp(props, `border-${sides[i]}-width`, width)
        setProp(props, `border-${sides[i]}-style`, style)
        setProp(props, `border-${sides[i]}-color`, color)
    }
}

void func applyFontShorthand(props:map[text], value:ascii) {
    arr[ascii] t = cssTokens(value)
    if t.length == 0 { return }
    ascii lower = asciiLower(value)
    if lower == 'caption' || lower == 'icon' || lower == 'menu' || lower == 'message-box' || lower == 'small-caption' || lower == 'status-bar' { return }
    int i = 0
    setProp(props, 'font-style', 'normal')
    setProp(props, 'font-weight', 'normal')
    while i < t.length {
        ascii tok = asciiLower(t[i])
        if tok == 'italic' || tok == 'oblique' { setProp(props, 'font-style', tok) }
        else if tok == 'bold' || tok == 'bolder' || tok == 'lighter' || (tok.length == 3 && isDigitCode(tok.charCodeAt(0)) && isDigitCode(tok.charCodeAt(1)) && isDigitCode(tok.charCodeAt(2))) { setProp(props, 'font-weight', tok) }
        else if tok == 'normal' || tok == 'small-caps' { }
        else { break }
        i++
    }
    if i >= t.length { return }
    ascii sizeTok = dup(t[i])
    int slash = asciiIndexOf(sizeTok, '/', 0)
    if slash >= 0 {
        setProp(props, 'line-height', sizeTok.slice(slash + 1, sizeTok.length))
        sizeTok = sizeTok.slice(0, slash)
    }
    setProp(props, 'font-size', sizeTok)
    i++
    if i < t.length {
        text fam = ''
        for int j = i, j < t.length, j++ {
            text piece = t[j].toText()
            fam = j == i ? piece : `${fam} ${piece}`
        }
        setProp(props, 'font-family', fam.toAscii())
    }
}

void func applyBackgroundShorthand(props:map[text], value:ascii) {
    arr[ascii] t = cssTokens(value)
    ascii found = 'transparent'
    for int i = 0, i < t.length, i++ {
        ascii tok = dup(t[i])
        if asciiStartsWithLower(tok, 'url(', 0) || asciiIndexOf(tok, 'gradient(', 0) >= 0 { continue }
        int c = parseCssColor(tok, COLOR_BLACK)
        if c != COLOR_UNSET { found = tok }
    }
    setProp(props, 'background-color', found)
}

void func applyDecl(props:map[text], nameIn:text, value:ascii) {
    text name = nameIn
    if name == 'margin' || name == 'padding' {
        applyFourSides(props, name, '', value)
        return
    }
    if name == 'border-width' || name == 'border-style' || name == 'border-color' {
        text suffix = name == 'border-width' ? '-width' : (name == 'border-style' ? '-style' : '-color')
        applyFourSides(props, 'border', suffix, value)
        return
    }
    if name == 'border' {
        applyBorderShorthand(props, ['top', 'right', 'bottom', 'left'], value)
        return
    }
    if name == 'border-top' || name == 'border-right' || name == 'border-bottom' || name == 'border-left' {
        text side = name == 'border-top' ? 'top' : (name == 'border-right' ? 'right' : (name == 'border-bottom' ? 'bottom' : 'left'))
        applyBorderShorthand(props, [side], value)
        return
    }
    if name == 'border-inline' || name == 'border-block' { return }
    if name == 'font' {
        applyFontShorthand(props, value)
        return
    }
    if name == 'background' {
        applyBackgroundShorthand(props, value)
        return
    }
    if name == 'list-style' {
        arr[ascii] t = cssTokens(value)
        for int i = 0, i < t.length, i++ {
            ascii tok = asciiLower(t[i])
            if tok == 'none' || tok == 'disc' || tok == 'circle' || tok == 'square' || tok == 'decimal' || tok == 'lower-alpha' || tok == 'upper-alpha' || tok == 'lower-roman' || tok == 'upper-roman' {
                setProp(props, 'list-style-type', tok)
            }
        }
        return
    }
    if name == 'text-decoration-line' { name = 'text-decoration' }
    if name == 'overflow-x' || name == 'overflow-y' { name = 'overflow' }
    if name == 'inline-size' { name = 'width' }
    if name == 'block-size' { name = 'height' }
    if name == 'margin-inline-start' { name = 'margin-left' }
    if name == 'margin-inline-end' { name = 'margin-right' }
    if name == 'padding-inline-start' { name = 'padding-left' }
    if name == 'padding-inline-end' { name = 'padding-right' }
    if name == 'margin-block-start' { name = 'margin-top' }
    if name == 'margin-block-end' { name = 'margin-bottom' }
    if name == 'margin-inline' || name == 'padding-inline' || name == 'margin-block' || name == 'padding-block' {
        arr[ascii] t = cssTokens(value)
        if t.length == 0 { return }
        ascii a = dup(t[0])
        ascii b = dup(t.length > 1 ? t[1] : t[0])
        bool inline = name == 'margin-inline' || name == 'padding-inline'
        text base = asciiStartsWith(name.toAscii(), 'margin', 0) ? 'margin' : 'padding'
        setProp(props, inline ? `${base}-left` : `${base}-top`, a)
        setProp(props, inline ? `${base}-right` : `${base}-bottom`, b)
        return
    }
    setProp(props, name, value)
}

// ---- computing --------------------------------------------------------

Len func parseLength(tok:ascii, fontSize:int) {
    Len l
    l.kind = LEN_INVALID
    if tok == null { return l }
    ascii t = asciiLower(asciiTrim(tok))
    if t == 'auto' || t == 'none' || t == 'initial' || t == 'unset' { return lenAuto() }
    parseNumberAt(t, 0)
    if !numOk { return l }
    float v = numValue
    ascii unit = t.slice(numEnd, t.length)
    if unit == '' { return lenPx(v) }
    if unit == 'px' { return lenPx(v) }
    if unit == '%' { return lenPercent(v) }
    if unit == 'em' { return lenPx(v * fontSize.toFloat()) }
    if unit == 'rem' { return lenPx(v * cssRootFontSize.toFloat()) }
    if unit == 'pt' { return lenPx(v * 4.0 / 3.0) }
    if unit == 'pc' { return lenPx(v * 16.0) }
    if unit == 'in' { return lenPx(v * 96.0) }
    if unit == 'cm' { return lenPx(v * 37.8) }
    if unit == 'mm' { return lenPx(v * 3.78) }
    if unit == 'ex' || unit == 'ch' { return lenPx(v * fontSize.toFloat() * 0.5) }
    if unit == 'vw' { return lenPx(v * cssViewportWidth.toFloat() / 100.0) }
    if unit == 'vh' { return lenPx(v * cssViewportHeight.toFloat() / 100.0) }
    if unit == 'vmin' { return lenPx(v * minInt(cssViewportWidth, cssViewportHeight).toFloat() / 100.0) }
    if unit == 'vmax' { return lenPx(v * maxInt(cssViewportWidth, cssViewportHeight).toFloat() / 100.0) }
    return l
}

// ---- the CSS-wide keywords --------------------------------------------
//
// `inherit` takes the parent's computed value; `initial` takes the
// property's initial value; `unset` is inherit for an inherited property
// and initial for the rest. `revert` should roll back to the value the
// previous cascade origin gave, which needs the origins kept apart after
// the cascade -- they are not, so it behaves as `unset` here
// (css-2026.md, "CSS Cascade 4").
const int CSSWIDE_NONE = 0
const int CSSWIDE_INHERIT = 1
const int CSSWIDE_INITIAL = 2
const int CSSWIDE_UNSET = 3

int func cssWideKeyword(v:ascii) {
    if v == null { return CSSWIDE_NONE }
    ascii t = asciiLower(asciiTrim(v))
    if t == 'inherit' { return CSSWIDE_INHERIT }
    if t == 'initial' { return CSSWIDE_INITIAL }
    if t == 'unset' { return CSSWIDE_UNSET }
    if t == 'revert' || t == 'revert-layer' { return CSSWIDE_UNSET }
    return CSSWIDE_NONE
}

// The parent's computed style, for the properties that resolve `inherit`
// by name. A global rather than a parameter because threading it through
// every resolver would change a dozen signatures for one keyword, and a
// forwarded struct parameter costs a collector walk (FINDINGS.md,
// "cycle trials").
Style cascadeParentStyle
bool cascadeParentIsRoot = true

Len func parentLenFor(name:text, dflt:Len) {
    if cascadeParentIsRoot { return dflt }
    Style p = cascadeParentStyle
    if name == 'width' { return p.width }
    if name == 'height' { return p.height }
    if name == 'min-width' { return p.minWidth }
    if name == 'max-width' { return p.maxWidth }
    if name == 'min-height' { return p.minHeight }
    if name == 'margin-top' { return p.marginTop }
    if name == 'margin-right' { return p.marginRight }
    if name == 'margin-bottom' { return p.marginBottom }
    if name == 'margin-left' { return p.marginLeft }
    if name == 'padding-top' { return p.paddingTop }
    if name == 'padding-right' { return p.paddingRight }
    if name == 'padding-bottom' { return p.paddingBottom }
    if name == 'padding-left' { return p.paddingLeft }
    return dflt
}

int func parentColorFor(name:text, dflt:int) {
    if cascadeParentIsRoot { return dflt }
    Style p = cascadeParentStyle
    if name == 'color' { return p.color }
    if name == 'background-color' { return p.background }
    if name == 'border-top-color' { return p.borderTopColor }
    if name == 'border-right-color' { return p.borderRightColor }
    if name == 'border-bottom-color' { return p.borderBottomColor }
    if name == 'border-left-color' { return p.borderLeftColor }
    return dflt
}

Len func lenProp(props:map[text], name:text, fontSize:int, dflt:Len) {
    ascii v = styleProp(props, name)
    if v == null { return dflt }
    int kw = cssWideKeyword(v)
    if kw == CSSWIDE_INHERIT { return parentLenFor(name, dflt) }
    // Every length property here is non-inherited, so `initial` and
    // `unset` both mean the initial value.
    if kw != CSSWIDE_NONE { return dflt }
    Len l = parseLength(v, fontSize)
    if l.kind == LEN_INVALID { return dflt }
    return l
}

int func pxProp(props:map[text], name:text, fontSize:int, dflt:int) {
    Len l = lenProp(props, name, fontSize, lenPx(dflt.toFloat()))
    if l.kind != LEN_PX { return dflt }
    return roundPx(l.v)
}

int func computeFontSize(v:ascii, parentSize:int) {
    if v == null { return parentSize }
    ascii t = asciiLower(asciiTrim(v))
    if t == 'xx-small' { return 9 }
    if t == 'x-small' { return 10 }
    if t == 'small' { return 13 }
    if t == 'medium' { return 16 }
    if t == 'large' { return 18 }
    if t == 'x-large' { return 24 }
    if t == 'xx-large' { return 32 }
    if t == 'xxx-large' { return 48 }
    if t == 'smaller' { return maxInt(roundPx(parentSize.toFloat() / 1.2), 1) }
    if t == 'larger' { return roundPx(parentSize.toFloat() * 1.2) }
    if t == 'inherit' { return parentSize }
    Len l = parseLength(t, parentSize)
    if l.kind == LEN_PX { return maxInt(roundPx(l.v), 1) }
    if l.kind == LEN_PERCENT { return maxInt(roundPx(parentSize.toFloat() * l.v / 100.0), 1) }
    return parentSize
}

int func colorProp(props:map[text], name:text, currentColor:int, dflt:int) {
    ascii v = styleProp(props, name)
    if v == null { return dflt }
    int kw = cssWideKeyword(v)
    if kw == CSSWIDE_INHERIT { return parentColorFor(name, dflt) }
    // `color` is the one inherited colour property, so its default when
    // absent is the parent's value but its *initial* value is black;
    // `unset` on it inherits, and on the rest is the initial value.
    if kw == CSSWIDE_INITIAL { return name == 'color' ? COLOR_BLACK : dflt }
    if kw == CSSWIDE_UNSET && name == 'color' { return parentColorFor(name, dflt) }
    if kw != CSSWIDE_NONE { return dflt }
    int c = parseCssColor(v, currentColor)
    if c == COLOR_UNSET { return dflt }
    return c
}

int func borderWidthProp(props:map[text], side:text, fontSize:int) {
    ascii style = styleProp(props, `border-${side}-style`)
    if style == null || asciiLower(style) == 'none' || asciiLower(style) == 'hidden' { return 0 }
    ascii w = styleProp(props, `border-${side}-width`)
    if w == null { return 3 }
    ascii t = asciiLower(w)
    if t == 'thin' { return 1 }
    if t == 'medium' { return 3 }
    if t == 'thick' { return 5 }
    Len l = parseLength(t, fontSize)
    if l.kind != LEN_PX { return 3 }
    return maxInt(roundPx(l.v), 0)
}

int func parseDisplay(v:ascii, dflt:int) {
    if v == null { return dflt }
    ascii t = asciiLower(v)
    if t == 'none' { return DISPLAY_NONE }
    if t == 'block' || t == 'flow-root' || t == 'grid' { return DISPLAY_BLOCK }
    if t == 'flex' || t == 'inline-flex' || t == 'inline-grid' { return DISPLAY_BLOCK }
    if t == 'inline' || t == 'contents' { return DISPLAY_INLINE }
    if t == 'inline-block' { return DISPLAY_INLINE_BLOCK }
    if t == 'list-item' { return DISPLAY_LIST_ITEM }
    if t == 'table' || t == 'inline-table' { return DISPLAY_TABLE }
    if t == 'table-row' { return DISPLAY_TABLE_ROW }
    if t == 'table-cell' { return DISPLAY_TABLE_CELL }
    if t == 'table-row-group' || t == 'table-header-group' || t == 'table-footer-group' { return DISPLAY_TABLE_ROW_GROUP }
    if t == 'table-caption' { return DISPLAY_BLOCK }
    return dflt
}

text func computeFontFamily(v:ascii, dflt:text) {
    if v == null { return dflt }
    ascii t = asciiTrim(v)
    if asciiLower(t) == 'inherit' { return dflt }
    arr[ascii] fams = asciiSplitChar(t, CH_COMMA)
    if fams.length == 0 { return dflt }
    ascii first = dup(fams[0])
    if first.length >= 2 {
        int q = first.charCodeAt(0)
        if (q == CH_QUOTE || q == CH_APOS) && first.charCodeAt(first.length - 1) == q {
            first = first.slice(1, first.length - 1)
        }
    }
    ascii lower = asciiLower(first)
    if lower == 'monospace' || lower == 'serif' || lower == 'sans-serif' { return lower.toText() }
    if lower == 'cursive' || lower == 'fantasy' { return 'serif' }
    if lower == 'system-ui' || lower == 'ui-sans-serif' { return 'sans-serif' }
    if lower == 'ui-monospace' { return 'monospace' }
    if lower == 'ui-serif' { return 'serif' }
    // Cairo's toy font API hands any family name to fontconfig, which
    // substitutes a real face; pass the author's name through.
    return first.toText()
}

Style func computeStyle(n:Node, parent:Style, isRoot:bool) {
    map[text] props = {}
    int t0 = archtelosTiming ? now() : 0
    arr[Match] matches = collectMatches(n)
    if archtelosTiming { profCollectMs = profCollectMs + (now() - t0) }
    int t1 = archtelosTiming ? now() : 0
    for int i = 0, i < matches.length, i++ {
        applyDecl(props, matches[i].decl.name, matches[i].decl.value)
    }
    if archtelosTiming {
        profApplyMs = profApplyMs + (now() - t1)
        profElements++
        profMatchesTotal = profMatchesTotal + matches.length
    }
    int t2 = archtelosTiming ? now() : 0
    Style s = computeStyleValues(n, parent, isRoot, props)
    if archtelosTiming { profComputeMs = profComputeMs + (now() - t2) }
    return s
}

Style func computeStyleValues(n:Node, parent:Style, isRoot:bool, props:map[text]) {
    Style s
    cascadeParentStyle = parent
    cascadeParentIsRoot = isRoot
    // inherited
    int parentFont = isRoot ? ROOT_FONT_SIZE : parent.fontSize
    s.fontSize = computeFontSize(styleProp(props, 'font-size'), parentFont)
    // `rem` multiplies this, and the root is computed before anything
    // that can refer to it.
    if isRoot { cssRootFontSize = s.fontSize }
    s.fontBold = isRoot ? false : parent.fontBold
    ascii fw = styleProp(props, 'font-weight')
    if fw != null {
        ascii t = asciiLower(fw)
        if t == 'bold' || t == 'bolder' { s.fontBold = true }
        else if t == 'normal' || t == 'lighter' { s.fontBold = false }
        else if t != 'inherit' {
            int nw = t.toText().toInt()
            if nw != null { s.fontBold = nw >= 600 }
        }
    }
    s.fontItalic = isRoot ? false : parent.fontItalic
    ascii fs = styleProp(props, 'font-style')
    if fs != null {
        ascii t = asciiLower(fs)
        if t == 'italic' || t == 'oblique' { s.fontItalic = true }
        else if t == 'normal' { s.fontItalic = false }
    }
    s.fontFamily = computeFontFamily(styleProp(props, 'font-family'), isRoot ? 'sans-serif' : parent.fontFamily)
    s.fontKey = `${s.fontSize}|${s.fontBold ? 1 : 0}|${s.fontItalic ? 1 : 0}|${s.fontFamily}`
    s.color = colorProp(props, 'color', isRoot ? COLOR_BLACK : parent.color, isRoot ? COLOR_BLACK : parent.color)
    s.lineHeight = isRoot ? 0 : parent.lineHeight
    ascii lh = styleProp(props, 'line-height')
    if lh != null {
        ascii t = asciiLower(asciiTrim(lh))
        if t == 'normal' { s.lineHeight = 0 }
        else if t != 'inherit' {
            parseNumberAt(t, 0)
            if numOk {
                ascii unit = t.slice(numEnd, t.length)
                if unit == '' { s.lineHeight = roundPx(numValue * s.fontSize.toFloat()) }
                else {
                    Len l = parseLength(t, s.fontSize)
                    if l.kind == LEN_PX { s.lineHeight = roundPx(l.v) }
                    else if l.kind == LEN_PERCENT { s.lineHeight = roundPx(s.fontSize.toFloat() * l.v / 100.0) }
                }
            }
        }
    }
    s.textAlign = isRoot ? ALIGN_LEFT : parent.textAlign
    ascii ta = styleProp(props, 'text-align')
    if ta != null {
        ascii t = asciiLower(ta)
        if t == 'left' || t == 'start' { s.textAlign = ALIGN_LEFT }
        else if t == 'center' { s.textAlign = ALIGN_CENTER }
        else if t == 'right' || t == 'end' { s.textAlign = ALIGN_RIGHT }
        else if t == 'justify' { s.textAlign = ALIGN_LEFT }
    }
    // text-decoration is NOT an inherited property: the element's own
    // computed value starts at none. What the standard does instead is
    // propagate the decoration of an ancestor to the boxes inside it,
    // which is what inheritedDecoration carries for the painter.
    s.inheritedDecoration = isRoot ? DECO_NONE : decoUnion(parent.inheritedDecoration, parent.textDecoration)
    s.textDecoration = DECO_NONE
    ascii td = styleProp(props, 'text-decoration')
    if td != null {
        ascii t = asciiLower(td)
        if asciiIndexOf(t, 'none', 0) >= 0 { s.textDecoration = DECO_NONE }
        else {
            int deco = 0
            if asciiIndexOf(t, 'underline', 0) >= 0 { deco = deco + DECO_UNDERLINE }
            if asciiIndexOf(t, 'line-through', 0) >= 0 { deco = deco + DECO_LINE_THROUGH }
            if deco > 0 { s.textDecoration = deco }
        }
    }
    s.textTransform = isRoot ? TT_NONE : parent.textTransform
    ascii tt = styleProp(props, 'text-transform')
    if tt != null {
        ascii t = asciiLower(tt)
        if t == 'uppercase' { s.textTransform = TT_UPPERCASE }
        else if t == 'lowercase' { s.textTransform = TT_LOWERCASE }
        else if t == 'capitalize' { s.textTransform = TT_CAPITALIZE }
        else if t == 'none' { s.textTransform = TT_NONE }
    }
    s.whiteSpace = isRoot ? WS_NORMAL : parent.whiteSpace
    ascii ws = styleProp(props, 'white-space')
    if ws != null {
        ascii t = asciiLower(ws)
        if t == 'normal' { s.whiteSpace = WS_NORMAL }
        else if t == 'pre' { s.whiteSpace = WS_PRE }
        else if t == 'nowrap' { s.whiteSpace = WS_NOWRAP }
        else if t == 'pre-wrap' || t == 'pre-line' || t == 'break-spaces' { s.whiteSpace = WS_PRE_WRAP }
    }
    s.listStyle = isRoot ? LIST_DISC : parent.listStyle
    ascii ls = styleProp(props, 'list-style-type')
    if ls != null {
        ascii t = asciiLower(ls)
        if t == 'none' { s.listStyle = LIST_NONE }
        else if t == 'disc' { s.listStyle = LIST_DISC }
        else if t == 'circle' { s.listStyle = LIST_CIRCLE }
        else if t == 'square' { s.listStyle = LIST_SQUARE }
        else if t == 'decimal' || t == 'lower-alpha' || t == 'upper-alpha' || t == 'lower-roman' || t == 'upper-roman' { s.listStyle = LIST_DECIMAL }
    }
    s.hidden = isRoot ? false : parent.hidden
    ascii vis = styleProp(props, 'visibility')
    if vis != null {
        ascii t = asciiLower(vis)
        if t == 'hidden' || t == 'collapse' { s.hidden = true }
        else if t == 'visible' { s.hidden = false }
    }
    s.letterSpacing = isRoot ? 0 : parent.letterSpacing
    s.letterSpacing = pxProp(props, 'letter-spacing', s.fontSize, s.letterSpacing)
    // opacity is not inherited either. The element's own value is its
    // computed value; effectiveOpacity is that multiplied by every
    // ancestor's, which is the approximation of group opacity the
    // painter uses in the absence of an offscreen layer.
    s.opacity = 1.0
    ascii op = styleProp(props, 'opacity')
    if op != null {
        parseNumberAt(asciiTrim(op), 0)
        if numOk {
            float o = numValue
            if numEnd < op.length && op.charCodeAt(numEnd) == CH_PERCENT { o = o / 100.0 }
            if o < 0.0 { o = 0.0 }
            if o > 1.0 { o = 1.0 }
            s.opacity = o
        }
    }
    s.effectiveOpacity = (isRoot ? 1.0 : parent.effectiveOpacity) * s.opacity

    // non-inherited
    int dfltDisplay = DISPLAY_INLINE
    s.display = parseDisplay(styleProp(props, 'display'), dfltDisplay)
    s.background = colorProp(props, 'background-color', s.color, COLOR_TRANSPARENT)
    s.width = lenProp(props, 'width', s.fontSize, lenAuto())
    s.height = lenProp(props, 'height', s.fontSize, lenAuto())
    s.minWidth = lenProp(props, 'min-width', s.fontSize, lenAuto())
    s.maxWidth = lenProp(props, 'max-width', s.fontSize, lenAuto())
    s.minHeight = lenProp(props, 'min-height', s.fontSize, lenAuto())
    Len zero = lenPx(0.0)
    s.marginTop = lenProp(props, 'margin-top', s.fontSize, zero)
    s.marginRight = lenProp(props, 'margin-right', s.fontSize, zero)
    s.marginBottom = lenProp(props, 'margin-bottom', s.fontSize, zero)
    s.marginLeft = lenProp(props, 'margin-left', s.fontSize, zero)
    s.paddingTop = lenProp(props, 'padding-top', s.fontSize, zero)
    s.paddingRight = lenProp(props, 'padding-right', s.fontSize, zero)
    s.paddingBottom = lenProp(props, 'padding-bottom', s.fontSize, zero)
    s.paddingLeft = lenProp(props, 'padding-left', s.fontSize, zero)
    s.borderTop = borderWidthProp(props, 'top', s.fontSize)
    s.borderRight = borderWidthProp(props, 'right', s.fontSize)
    s.borderBottom = borderWidthProp(props, 'bottom', s.fontSize)
    s.borderLeft = borderWidthProp(props, 'left', s.fontSize)
    s.borderTopColor = colorProp(props, 'border-top-color', s.color, s.color)
    s.borderRightColor = colorProp(props, 'border-right-color', s.color, s.color)
    s.borderBottomColor = colorProp(props, 'border-bottom-color', s.color, s.color)
    s.borderLeftColor = colorProp(props, 'border-left-color', s.color, s.color)
    s.borderStyle = (s.borderTop + s.borderRight + s.borderBottom + s.borderLeft) > 0 ? BORDER_SOLID : BORDER_NONE
    s.borderRadius = 0
    ascii br = styleProp(props, 'border-radius')
    if br != null {
        arr[ascii] t = cssTokens(br)
        if t.length > 0 {
            Len l = parseLength(t[0], s.fontSize)
            if l.kind == LEN_PX { s.borderRadius = maxInt(roundPx(l.v), 0) }
        }
    }
    s.borderSpacing = 0
    ascii bs = styleProp(props, 'border-spacing')
    if bs != null {
        arr[ascii] t = cssTokens(bs)
        if t.length > 0 {
            Len l = parseLength(t[0], s.fontSize)
            if l.kind == LEN_PX { s.borderSpacing = maxInt(roundPx(l.v), 0) }
        }
    }
    ascii bc = styleProp(props, 'border-collapse')
    s.borderCollapse = bc != null && asciiLower(bc) == 'collapse'
    if isRoot { s.borderCollapse = false }
    else if bc == null && (n.tag == 'td' || n.tag == 'th' || n.tag == 'tr' || n.tag == 'tbody' || n.tag == 'thead' || n.tag == 'tfoot') { s.borderCollapse = parent.borderCollapse }
    s.textIndent = pxProp(props, 'text-indent', s.fontSize, isRoot ? 0 : parent.textIndent)
    s.verticalAlign = VALIGN_BASELINE
    ascii va = styleProp(props, 'vertical-align')
    if va != null {
        ascii t = asciiLower(va)
        if t == 'middle' { s.verticalAlign = VALIGN_MIDDLE }
        else if t == 'top' || t == 'text-top' || t == 'super' { s.verticalAlign = VALIGN_TOP }
        else if t == 'bottom' || t == 'text-bottom' || t == 'sub' { s.verticalAlign = VALIGN_BOTTOM }
        else if t == 'inherit' && !isRoot { s.verticalAlign = parent.verticalAlign }
    }
    s.floatSide = FLOAT_NONE
    ascii fl = styleProp(props, 'float')
    if fl != null {
        ascii t = asciiLower(fl)
        if t == 'left' { s.floatSide = FLOAT_LEFT }
        else if t == 'right' { s.floatSide = FLOAT_RIGHT }
    }
    ascii ov = styleProp(props, 'overflow')
    s.overflowHidden = ov != null && (asciiLower(ov) == 'hidden' || asciiLower(ov) == 'clip')
    return s
}

// Computes the style of every element in the tree; text nodes share
// their parent's Style.
void func computeStylesFrom(n:Node, parent:Style, isRoot:bool) {
    if n.kind == NODE_TEXT {
        n.style = parent
        return
    }
    if n.kind == NODE_DOCUMENT {
        for int i = 0, i < n.children.length, i++ {
            computeStylesFrom(n.children[i], parent, true)
        }
        return
    }
    Style s = computeStyle(n, parent, isRoot)
    n.style = s
    for int i = 0, i < n.children.length, i++ {
        computeStylesFrom(n.children[i], s, false)
    }
}

void func computeStyles(doc:Node) {
    Style none
    computeStylesFrom(doc, none, true)
    if archtelosTiming { log(cascadeProfile()) }
}

text func describeStyle(s:Style) {
    return `display=${s.display} color=${s.color} bg=${s.background} font=${s.fontKey} lh=${s.lineHeight} align=${s.textAlign} deco=${s.textDecoration} ws=${s.whiteSpace} list=${s.listStyle} m=${resolveLen(s.marginTop, 0, -1)}/${resolveLen(s.marginRight, 0, -1)}/${resolveLen(s.marginBottom, 0, -1)}/${resolveLen(s.marginLeft, 0, -1)} p=${resolveLen(s.paddingTop, 0, -1)}/${resolveLen(s.paddingRight, 0, -1)}/${resolveLen(s.paddingBottom, 0, -1)}/${resolveLen(s.paddingLeft, 0, -1)} b=${s.borderTop}/${s.borderRight}/${s.borderBottom}/${s.borderLeft} w=${s.width.kind}:${s.width.v} h=${s.height.kind}:${s.height.v}`
}
