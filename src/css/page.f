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

// An `@page` rule: which pages it speaks for, and what it says.
// `blank` is parsed and never matches -- this engine generates no blank
// pages, so a rule for one would be a rule for nothing.
struct PageRule {
    name:text
    first:bool
    blank:bool
    left:bool
    right:bool
    order:int
    decls:arr[PageDecl]
}

arr[PageRule] cssPageRules = []
int cssPageRuleOrder = 0

void func resetPageRules() {
    arr[PageRule] empty = []
    cssPageRules = empty
    cssPageRuleOrder = 0
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
// None are drawn here, so they are cut out before the list is split,
// rather than left to turn into declarations that are not any.
ascii func pageBodyWithoutMarginBoxes(body:ascii) {
    int at = asciiIndexOf(body, '{', 0)
    if at < 0 { return body }
    ascii out = ''
    int i = 0
    int n = body.length
    int keep = 0
    while i < n {
        if body.charCodeAt(i) == CH_LBRACE {
            out = out + body.slice(keep, i)
            int depth = 1
            i++
            while i < n && depth > 0 {
                int c = body.charCodeAt(i)
                if c == CH_LBRACE { depth++ }
                if c == CH_RBRACE { depth-- }
                i++
            }
            // The `@top-center` before the brace is not a declaration
            // either; it has no colon, so the split drops it.
            keep = i
            continue
        }
        i++
    }
    return out + body.slice(keep, n)
}

void func parsePageRule(prelude:ascii, body:ascii) {
    arr[PageDecl] decls = []
    arr[ascii] parts = splitOnSemicolons(pageBodyWithoutMarginBoxes(body))
    for int i = 0, i < parts.length, i++ {
        int colon = asciiIndexOf(parts[i], ':', 0)
        if colon < 0 { continue }
        PageDecl d
        d.name = asciiLower(asciiTrim(parts[i].slice(0, colon))).toText()
        d.value = asciiTrim(parts[i].slice(colon + 1, parts[i].length))
        if d.name == '' { continue }
        decls.push(d)
    }
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
    }
}

// ---- resolution --------------------------------------------------------

// Whether a rule speaks for this page. A rule with a name speaks only
// for the pages that asked for that name; one without speaks for any.
// The first page is a right-hand one, so odd pages are `:right` and
// even ones `:left` (CSS2 §13.2.4).
bool func pageRuleMatches(r:PageRule, name:text, index:int) {
    if r.blank { return false }
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
PageBox func pageBoxFor(name:text, index:int) {
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
            if pageRuleSpecificity(r) != spec { continue }
            if !pageRuleMatches(r, name, index) { continue }
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
