// Paged media: the page box a paginated render lays a document into
// (CSS2 §13, CSS Paged Media 3).
//
// A page box is a sheet of a named or declared size with margins inside
// it; what is left over is the page area, and the document is poured
// through it one page's worth at a time. `@page` declares the box for
// every page, and the page selectors declare it for particular ones:
// `:first` for the first, `:left` and `:right` for the two sides of a
// spread, and a name for the pages a `page` property sends there.
//
// This sits at the parser's layer rather than the cascade's because the
// rule arrives while the stylesheet is being read and nothing about it
// depends on an element: a page box is a property of the sheet and the
// page number, not of anything in the document.
import ../util/text.f

// Whether the medium is print rather than screen (Media Queries 4 §3).
// A paginated render answers `print` and everything else answers
// `screen`, which is what makes a document's print stylesheet -- and
// the `@page` rules almost always inside it -- reach its pages.
bool cssMediaPrint = false

// Whether this document has ever said one of CSS2's three page-break
// properties. `applyDecl` runs once per matched declaration -- 11,614 of
// them on the benchmark page -- so a page that never says one pays a
// single boolean rather than three name comparisons. Set while a
// stylesheet is read and cleared by cascadeReset, and declared here
// rather than beside its use because a global is not hoisted
// (FINDINGS.md, "one global namespace, and globals are not hoisted").
bool anyPageBreak = false

struct PageBox {
    width:int
    height:int
    marginTop:int
    marginRight:int
    marginBottom:int
    marginLeft:int
}

// `size: auto` is the sheet this browser prints on, and it is US Letter
// because that is the sheet Chromium prints on beside it: 612x792pt,
// which is 816x1056 pixels at 96dpi.
const int PAGE_DEFAULT_W = 816
const int PAGE_DEFAULT_H = 1056

// The one number on a page box that no standard fixes. 0.4in at 96dpi.
// Chromium's own print default measures 37px a side here, which is a
// setting of its print dialog rather than anything CSS says; a page
// that declares its margins agrees with it exactly.
const int PAGE_DEFAULT_MARGIN = 38

// One declaration of an `@page` rule, kept in the order it was written
// because a longhand after its shorthand has to win.
struct PageDecl {
    name:text
    value:ascii
}

// ---- the margin boxes --------------------------------------------------
//
// Sixteen boxes in the page margin (CSS Paged Media 3 §5), numbered
// the way the standard lists them: the five along the top, the five
// along the bottom, then the three down each side. The order is what
// the painter walks, and nothing else depends on it.
const int MB_NONE = -1
const int MB_TOP_LEFT_CORNER = 0
const int MB_TOP_LEFT = 1
const int MB_TOP_CENTER = 2
const int MB_TOP_RIGHT = 3
const int MB_TOP_RIGHT_CORNER = 4
const int MB_BOTTOM_LEFT_CORNER = 5
const int MB_BOTTOM_LEFT = 6
const int MB_BOTTOM_CENTER = 7
const int MB_BOTTOM_RIGHT = 8
const int MB_BOTTOM_RIGHT_CORNER = 9
const int MB_LEFT_TOP = 10
const int MB_LEFT_MIDDLE = 11
const int MB_LEFT_BOTTOM = 12
const int MB_RIGHT_TOP = 13
const int MB_RIGHT_MIDDLE = 14
const int MB_RIGHT_BOTTOM = 15
const int MB_COUNT = 16

int func marginBoxSlot(n:ascii) {
    if n == 'top-left-corner' { return MB_TOP_LEFT_CORNER }
    if n == 'top-left' { return MB_TOP_LEFT }
    if n == 'top-center' { return MB_TOP_CENTER }
    if n == 'top-right' { return MB_TOP_RIGHT }
    if n == 'top-right-corner' { return MB_TOP_RIGHT_CORNER }
    if n == 'bottom-left-corner' { return MB_BOTTOM_LEFT_CORNER }
    if n == 'bottom-left' { return MB_BOTTOM_LEFT }
    if n == 'bottom-center' { return MB_BOTTOM_CENTER }
    if n == 'bottom-right' { return MB_BOTTOM_RIGHT }
    if n == 'bottom-right-corner' { return MB_BOTTOM_RIGHT_CORNER }
    if n == 'left-top' { return MB_LEFT_TOP }
    if n == 'left-middle' { return MB_LEFT_MIDDLE }
    if n == 'left-bottom' { return MB_LEFT_BOTTOM }
    if n == 'right-top' { return MB_RIGHT_TOP }
    if n == 'right-middle' { return MB_RIGHT_MIDDLE }
    if n == 'right-bottom' { return MB_RIGHT_BOTTOM }
    return MB_NONE
}

// Each box's default `text-align` and `vertical-align` (§5.2). The
// corners align INWARD, toward the page content, which is the one part
// of the table a reader would not guess and the one the measurement in
// todo.md pinned: a `@top-left-corner`'s text is right-aligned.
const int MBALIGN_START = 0
const int MBALIGN_CENTER = 1
const int MBALIGN_END = 2

int func marginBoxDefaultAlign(slot:int) {
    if slot == MB_TOP_LEFT_CORNER || slot == MB_BOTTOM_LEFT_CORNER { return MBALIGN_END }
    if slot == MB_TOP_RIGHT_CORNER || slot == MB_BOTTOM_RIGHT_CORNER { return MBALIGN_START }
    if slot == MB_TOP_LEFT || slot == MB_BOTTOM_LEFT { return MBALIGN_START }
    if slot == MB_TOP_RIGHT || slot == MB_BOTTOM_RIGHT { return MBALIGN_END }
    return MBALIGN_CENTER
}

// Where the line sits in the band, down the page: the top and bottom
// edges centre it, and the three down each side are the three the
// names say.
int func marginBoxDefaultVAlign(slot:int) {
    if slot == MB_LEFT_TOP || slot == MB_RIGHT_TOP { return MBALIGN_START }
    if slot == MB_LEFT_BOTTOM || slot == MB_RIGHT_BOTTOM { return MBALIGN_END }
    return MBALIGN_CENTER
}

// An `@page` rule: which pages it speaks for, and what it says.
// `blank` speaks for a page the paginator generated to put the next one
// on the side a `break-before: left` or `right` asked for; there is no
// other way to produce a page with nothing on it, so a `:blank` rule
// speaks for those pages alone.
struct PageRule {
    name:text
    first:bool
    blank:bool
    left:bool
    right:bool
    // MB_NONE for the page box itself, or the margin box this rule's
    // declarations belong to. One array holds both, so the matcher and
    // the specificity are written once.
    slot:int
    order:int
    decls:arr[PageDecl]
}

// A page that declares no margin box pays nothing for them.
bool anyPageMarginBox = false

arr[PageRule] cssPageRules = []
int cssPageRuleOrder = 0

void func resetPageRules() {
    arr[PageRule] empty = []
    cssPageRules = empty
    cssPageRuleOrder = 0
    anyPageMarginBox = false
}

// ---- lengths -----------------------------------------------------------

// A length in a page rule. Only the absolute units mean anything on a
// sheet of paper -- there is no font here to resolve `em` against and no
// viewport to resolve `vh` against -- plus a percentage of the page box,
// which the caller resolves because only it knows which axis.
bool pageLenOk = false
bool pageLenPercent = false

float func pageLength(v:ascii) {
    pageLenOk = false
    pageLenPercent = false
    ascii t = asciiLower(asciiTrim(v))
    if t.length == 0 { return 0.0 }
    parseNumberAt(t, 0)
    if !numOk { return 0.0 }
    float n = numValue
    ascii unit = asciiTrim(t.slice(numEnd, t.length))
    if unit.length == 0 {
        // A bare zero is a length; any other bare number is not.
        if n == 0.0 { pageLenOk = true }
        return 0.0
    }
    if unit == '%' { pageLenOk = true  pageLenPercent = true  return n }
    pageLenOk = true
    if unit == 'px' { return n }
    if unit == 'in' { return n * 96.0 }
    if unit == 'cm' { return n * 96.0 / 2.54 }
    if unit == 'mm' { return n * 96.0 / 25.4 }
    if unit == 'q' { return n * 96.0 / 101.6 }
    if unit == 'pt' { return n * 96.0 / 72.0 }
    if unit == 'pc' { return n * 16.0 }
    pageLenOk = false
    return 0.0
}

// ---- the named sizes ---------------------------------------------------

// Two values out of a function need globals (FINDINGS.md, "one value
// out of a function").
float pageSizeW = 0.0
float pageSizeH = 0.0

// The named page sizes (Paged Media 3 §3.1), in CSS pixels at 96dpi: a
// millimetre is 96/25.4 pixels and an inch is 96 of them. Each is given
// the way the standard gives it, portrait, and an orientation keyword
// turns it afterwards.
bool func namedPageSize(name:text) {
    float mm = 96.0 / 25.4
    if name == 'a5' { pageSizeW = 148.0 * mm  pageSizeH = 210.0 * mm  return true }
    if name == 'a4' { pageSizeW = 210.0 * mm  pageSizeH = 297.0 * mm  return true }
    if name == 'a3' { pageSizeW = 297.0 * mm  pageSizeH = 420.0 * mm  return true }
    if name == 'b5' { pageSizeW = 176.0 * mm  pageSizeH = 250.0 * mm  return true }
    if name == 'b4' { pageSizeW = 250.0 * mm  pageSizeH = 353.0 * mm  return true }
    if name == 'jis-b5' { pageSizeW = 182.0 * mm  pageSizeH = 257.0 * mm  return true }
    if name == 'jis-b4' { pageSizeW = 257.0 * mm  pageSizeH = 364.0 * mm  return true }
    if name == 'letter' { pageSizeW = 816.0  pageSizeH = 1056.0  return true }
    if name == 'legal' { pageSizeW = 816.0  pageSizeH = 1344.0  return true }
    if name == 'ledger' { pageSizeW = 1056.0  pageSizeH = 1632.0  return true }
    return false
}

// ---- parsing -----------------------------------------------------------

// A page rule's body is an ordinary declaration list, except that a
// margin box -- `@top-center { ... }` -- is a nested block inside it.
// They are cut out before the list is split, so that neither the block
// nor the `@name` in front of it turns into a declaration that is not
// one, and kept: the caller registers a rule per box.
//
// Two lists out of a function need globals (FINDINGS.md, "one value
// out of a function").
arr[int] pageMarginSlots = []
arr[ascii] pageMarginBodies = []

// The last occurrence of a character code, or -1. `text.f` has no
// backward search and a margin box's name is whatever follows the last
// semicolon of the segment before its brace.
int func asciiLastIndexOfCode(s:ascii, code:int) {
    for int i = s.length - 1, i >= 0, i-- {
        if s.charCodeAt(i) == code { return i }
    }
    return -1
}

ascii func splitPageBody(body:ascii) {
    arr[int] slots = []
    arr[ascii] bodies = []
    pageMarginSlots = slots
    pageMarginBodies = bodies
    ascii out = ''
    int i = 0
    int n = body.length
    int keep = 0
    while i < n {
        if body.charCodeAt(i) == CH_LBRACE {
            // What is between the last declaration and this brace is
            // the box's `@name`, which is how the slot is known. The
            // declarations before it stay in the page's own body, so
            // the split is at the last semicolon rather than at `keep`.
            ascii seg = body.slice(keep, i)
            int cut = asciiLastIndexOfCode(seg, CH_SEMI)
            ascii head = asciiLower(asciiTrim(seg.slice(cut + 1, seg.length)))
            out = out + seg.slice(0, cut + 1)
            int open = i
            int depth = 1
            i++
            while i < n && depth > 0 {
                int c = body.charCodeAt(i)
                if c == CH_LBRACE { depth++ }
                if c == CH_RBRACE { depth-- }
                i++
            }
            if head.length > 1 && head.charCodeAt(0) == CH_AT {
                int slot = marginBoxSlot(asciiTrim(head.slice(1, head.length)))
                if slot != MB_NONE {
                    pageMarginSlots.push(slot)
                    pageMarginBodies.push(body.slice(open + 1, maxInt(i - 1, open + 1)))
                }
            }
            keep = i
            continue
        }
        i++
    }
    return out + body.slice(keep, n)
}

// The declarations of one block, in the order they were written.
arr[PageDecl] func parsePageDecls(body:ascii) {
    arr[PageDecl] decls = []
    arr[ascii] parts = splitOnSemicolons(body)
    for int i = 0, i < parts.length, i++ {
        int colon = asciiIndexOf(parts[i], ':', 0)
        if colon < 0 { continue }
        PageDecl d
        d.name = asciiLower(asciiTrim(parts[i].slice(0, colon))).toText()
        d.value = asciiTrim(parts[i].slice(colon + 1, parts[i].length))
        if d.name == '' { continue }
        decls.push(d)
    }
    return decls
}

void func parsePageRule(prelude:ascii, body:ascii) {
    arr[PageDecl] decls = parsePageDecls(splitPageBody(body))
    // `splitPageBody` fills these, and registering the boxes below
    // parses them again through the same declaration splitter, so a
    // margin box's body and a page's body are read one way.
    arr[int] slots = pageMarginSlots
    arr[ascii] bodies = pageMarginBodies
    // A comma list is one rule per selector, because each carries its
    // own specificity.
    arr[ascii] sels = splitOnCommas(asciiTrim(prelude))
    if sels.length == 0 {
        ascii none = ''
        sels.push(none)
    }
    for int i = 0, i < sels.length, i++ {
        ascii sel = asciiLower(asciiTrim(sels[i]))
        PageRule r
        r.name = ''
        r.first = false
        r.blank = false
        r.left = false
        r.right = false
        r.decls = decls
        r.slot = MB_NONE
        cssPageRuleOrder++
        r.order = cssPageRuleOrder
        int colon = asciiIndexOf(sel, ':', 0)
        ascii head = colon < 0 ? sel : asciiTrim(sel.slice(0, colon))
        r.name = head.toText()
        int at = colon
        while at >= 0 && at < sel.length {
            int next = asciiIndexOf(sel, ':', at + 1)
            int end = next < 0 ? sel.length : next
            ascii p = asciiTrim(sel.slice(at + 1, end))
            if p == 'first' { r.first = true }
            else if p == 'blank' { r.blank = true }
            else if p == 'left' { r.left = true }
            else if p == 'right' { r.right = true }
            at = next
        }
        cssPageRules.push(r)
        for int m = 0, m < slots.length, m++ {
            PageRule mr
            mr.name = r.name
            mr.first = r.first
            mr.blank = r.blank
            mr.left = r.left
            mr.right = r.right
            mr.slot = slots[m]
            mr.decls = parsePageDecls(bodies[m])
            cssPageRuleOrder++
            mr.order = cssPageRuleOrder
            cssPageRules.push(mr)
            anyPageMarginBox = true
        }
    }
}

// ---- resolution --------------------------------------------------------

// Whether a rule speaks for this page. A rule with a name speaks only
// for the pages that asked for that name; one without speaks for any.
// The first page is a right-hand one, so odd pages are `:right` and
// even ones `:left` (CSS2 §13.2.4).
bool func pageRuleMatches(r:PageRule, name:text, index:int, blank:bool) {
    if r.blank && !blank { return false }
    if r.name != '' && r.name != name { return false }
    if r.first && index != 1 { return false }
    bool odd = index - Math.floorDiv(index, 2) * 2 == 1
    if r.left && odd { return false }
    if r.right && !odd { return false }
    return true
}

// A page selector's specificity is a triple: a name counts in the
// first place, `:first` and `:blank` in the second, `:left` and
// `:right` in the third (Paged Media 3 §3.5). Each place holds one bit,
// so the three pack into a number that compares the same way.
int func pageRuleSpecificity(r:PageRule) {
    int a = r.name != '' ? 4 : 0
    int b = r.first || r.blank ? 2 : 0
    int c = r.left || r.right ? 1 : 0
    return a + b + c
}

// The size declarations of the matching rules, applied in order. The
// size is settled before any margin is, because a percentage margin is
// of the page box and the page box is what this decides.
void func applyPageSize(box:PageBox, d:PageDecl) {
    if d.name != 'size' { return }
    arr[ascii] toks = namespacePreludeTokens(d.value)
    if toks.length == 0 { return }
    bool landscape = false
    bool oriented = false
    bool named = false
    float w = 0.0
    float h = 0.0
    bool haveW = false
    bool haveH = false
    for int i = 0, i < toks.length, i++ {
        text t = asciiLower(toks[i]).toText()
        if t == 'landscape' { landscape = true  oriented = true  continue }
        if t == 'portrait' { oriented = true  continue }
        if t == 'auto' { continue }
        if namedPageSize(t) {
            named = true
            w = pageSizeW
            h = pageSizeH
            haveW = true
            haveH = true
            continue
        }
        float v = pageLength(toks[i])
        if !pageLenOk || pageLenPercent { return }
        if !haveW { w = v  haveW = true } else { h = v  haveH = true }
    }
    if !haveW && !oriented { return }
    if !haveW {
        // A bare orientation turns whatever the page already is.
        w = box.width.toFloat()
        h = box.height.toFloat()
        haveW = true
        haveH = true
        named = true
    }
    if !haveH { h = w }
    if named || oriented {
        // A named size is given portrait, so an orientation keyword
        // orders the pair rather than swapping it blindly -- writing
        // `A4 portrait` twice must not turn the page twice.
        float lo = w < h ? w : h
        float hi = w < h ? h : w
        w = landscape ? hi : lo
        h = landscape ? lo : hi
    }
    box.width = maxInt(roundPx(w), 1)
    box.height = maxInt(roundPx(h), 1)
}

int func pageMarginPx(v:ascii, against:int) {
    float n = pageLength(v)
    if !pageLenOk { return 0 }
    if pageLenPercent { return roundPx(n * against.toFloat() / 100.0) }
    return roundPx(n)
}

void func applyPageMargin(box:PageBox, d:PageDecl) {
    if d.name == 'margin' {
        arr[ascii] toks = namespacePreludeTokens(d.value)
        if toks.length == 0 || toks.length > 4 { return }
        int t = pageMarginPx(toks[0], box.height)
        int r = pageMarginPx(toks[toks.length > 1 ? 1 : 0], box.width)
        int b = pageMarginPx(toks[toks.length > 2 ? 2 : 0], box.height)
        int l = pageMarginPx(toks[toks.length > 3 ? 3 : (toks.length > 1 ? 1 : 0)], box.width)
        box.marginTop = t
        box.marginRight = r
        box.marginBottom = b
        box.marginLeft = l
        return
    }
    if d.name == 'margin-top' { box.marginTop = pageMarginPx(d.value, box.height)  return }
    if d.name == 'margin-right' { box.marginRight = pageMarginPx(d.value, box.width)  return }
    if d.name == 'margin-bottom' { box.marginBottom = pageMarginPx(d.value, box.height)  return }
    if d.name == 'margin-left' { box.marginLeft = pageMarginPx(d.value, box.width)  return }
}

// The page box for a page: the default sheet, then every `@page` rule
// that speaks for it, weakest specificity first and source order within
// it. Rules accumulate -- what a later one does not say, an earlier one
// still does -- because this is the cascade and not a last-one-wins.
// The declarations in force for one margin box on one page, in
// cascade order: the same selector specificity the page box uses, so
// a `@page :first` box replaces the general one on page one and
// leaves it standing on the rest.
arr[PageDecl] func marginBoxDecls(slot:int, name:text, index:int, blank:bool) {
    arr[PageDecl] out = []
    if !anyPageMarginBox { return out }
    for int spec = 0, spec <= 7, spec++ {
        for int i = 0, i < cssPageRules.length, i++ {
            PageRule r = cssPageRules[i]
            if r.slot != slot { continue }
            if pageRuleSpecificity(r) != spec { continue }
            if !pageRuleMatches(r, name, index, blank) { continue }
            for int j = 0, j < r.decls.length, j++ { out.push(r.decls[j]) }
        }
    }
    return out
}

// The text a margin box's `content` comes to. The value is a sequence
// of strings and counters; `counter(page)` is the page's own number
// and `counter(pages)` the number of pages, which are the two the
// standard makes available in a page context and the two a margin box
// is written for. Anything else contributes nothing rather than its
// own source text.
// The closing parenthesis matching the one at `open`. page.f is
// imported by the CSS parser and cannot reach the cascade's copy.
int func pageMatchingParen(t:ascii, open:int) {
    int depth = 0
    for int i = open, i < t.length, i++ {
        int c = t.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN {
            depth--
            if depth == 0 { return i }
        }
    }
    return -1
}

// The index of the next character equal to `code`, at or after `from`.
int func pageIndexOfCode(t:ascii, code:int, from:int) {
    for int i = from, i < t.length, i++ {
        if t.charCodeAt(i) == code { return i }
    }
    return -1
}

text func marginBoxContent(value:ascii, index:int, total:int) {
    ascii v = asciiTrim(value)
    if v == '' { return '' }
    ascii low = asciiLower(v)
    if low == 'none' || low == 'normal' { return '' }
    text out = ''
    int i = 0
    int n = v.length
    while i < n {
        int c = v.charCodeAt(i)
        if isSpaceCode(c) { i++  continue }
        if c == CH_QUOTE || c == CH_APOS {
            int close = pageIndexOfCode(v, c, i + 1)
            if close < 0 { break }
            out = out + v.slice(i + 1, close).toText()
            i = close + 1
            continue
        }
        int open = pageIndexOfCode(v, CH_LPAREN, i)
        if open < 0 { break }
        ascii fn = asciiLower(asciiTrim(v.slice(i, open)))
        int close = pageMatchingParen(v, open)
        if close < 0 { break }
        ascii arg = asciiLower(asciiTrim(v.slice(open + 1, close)))
        if fn == 'counter' {
            if arg == 'page' { out = out + `${index}` }
            else if arg == 'pages' { out = out + `${total}` }
        }
        i = close + 1
    }
    return out
}

PageBox func pageBoxFor(name:text, index:int, blank:bool) {
    PageBox box
    box.width = PAGE_DEFAULT_W
    box.height = PAGE_DEFAULT_H
    box.marginTop = PAGE_DEFAULT_MARGIN
    box.marginRight = PAGE_DEFAULT_MARGIN
    box.marginBottom = PAGE_DEFAULT_MARGIN
    box.marginLeft = PAGE_DEFAULT_MARGIN
    if cssPageRules.length == 0 { return box }

    arr[int] pick = []
    for int spec = 0, spec <= 7, spec++ {
        for int i = 0, i < cssPageRules.length, i++ {
            PageRule r = cssPageRules[i]
            if r.slot != MB_NONE { continue }
            if pageRuleSpecificity(r) != spec { continue }
            if !pageRuleMatches(r, name, index, blank) { continue }
            pick.push(i)
        }
    }
    if pick.length == 0 { return box }
    for int k = 0, k < pick.length, k++ {
        arr[PageDecl] ds = cssPageRules[pick[k]].decls
        for int j = 0, j < ds.length, j++ { applyPageSize(box, ds[j]) }
    }
    for int k = 0, k < pick.length, k++ {
        arr[PageDecl] ds = cssPageRules[pick[k]].decls
        for int j = 0, j < ds.length, j++ { applyPageMargin(box, ds[j]) }
    }
    return box
}
