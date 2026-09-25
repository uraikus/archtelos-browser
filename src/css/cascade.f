// The cascade: which declarations apply to an element, in what order,
// and what computed Style they produce.

import parser.f
import ../dom/node.f
import ../util/color.f
import ../util/bidi.f
import ua.f

const int ORIGIN_UA = 0
const int ORIGIN_AUTHOR = 1
const int ORIGIN_INLINE = 2

const int ROOT_FONT_SIZE = 16
const int LEN_INVALID = -1

// A length that did not parse, which every caller already tests for by
// kind. It lives here rather than beside `lenPx` because `LEN_INVALID`
// does: style.f is imported by this file, not the other way round.
Len func lenInvalid() {
    Len l
    l.kind = LEN_INVALID
    return l
}

// hot-spot accumulators, reported with ARCHTELOS_TIMING=1
int profCollectMs = 0
int profSortMs = 0
int profApplyMs = 0
int profComputeMs = 0
int profElements = 0
int profMatchesTotal = 0
int profHintsMs = 0
int profSelectorTests = 0
map[Style] styleCache = {}
int profShareTotal = 0
int profShareDistinct = 0
int styleSerialNext = 1
int profPropReads = 0

text func cascadeProfile() {
    return `[timing] cascade detail: ${profElements} elements, ${profMatchesTotal} matched decls; collect ${profCollectMs} ms (hints ${profHintsMs} ms, ${profSelectorTests} selector tests), sort ${profSortMs} ms, apply ${profApplyMs} ms, compute ${profComputeMs} ms; property reads ${profPropReads}; ${profShareDistinct} distinct styles for ${profShareTotal} elements`
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
    layer:int
    // The `@container` query gating this rule, or CQ_NONE. Kept beside
    // the rule so the hot loop below does not reach through it.
    containerQuery:int
}

struct Bucket {
    refs:arr[RuleRef]
}

map[Bucket] ruleIndex = {}
map[int] bucketSizes = {}       // key -> number of refs, so existence is a scalar lookup

// Whether any rule anywhere names a pseudo-element. Almost no document
// has one, and computing ::before and ::after for every element would
// be two extra rule walks per element on every page (CLAUDE.md §3, "a
// feature must not cost anything to the pages that do not use it").
bool anyPseudoRules = false
// Which tags have a ::before or ::after rule, and whether any such rule
// is keyed on something other than a tag. The user-agent sheet styles
// q::before, so without this every document would run the pseudo-
// element pass over every element for a rule almost no page can match:
// measured at 8 ms on the 51 KB benchmark page, which has no <q>.
map[bool] pseudoTagSet = {}
bool pseudoNonTag = false
// Which elements have a ::first-letter or a ::first-line style, and
// whether any rule anywhere asks for one at all.
map[bool] pseudoHasFirstLetter = {}
map[bool] pseudoHasFirstLine = {}
// Which elements have a ::marker style, and whether any rule asks.
map[bool] pseudoHasMarker = {}
bool anyMarker = false
bool anyFirstLetter = false
// Whether any rule on the page names ::first-line. A page that does not
// pays one boolean per element and nothing else.
bool anyFirstLine = false
// The style each node in a ::first-line block's inline subtree wears
// while it is on the first line, keyed by node id. The standard
// describes ::first-line as a fictional tag wrapped around the line's
// characters, so a descendant's first-line style is what it computes to
// with that fictional element as its parent -- which is this walk.
map[Style] firstLineStyles = {}
// Whether any declaration anywhere says `revert` or `revert-layer`. A
// page that does not pays one boolean per element and nothing else: the
// user-agent origin's values are only kept where something asks to roll
// back to them.
bool anyRevert = false
// Whether any declaration anywhere is a cross-fade(). Copying the second
// image's url into the painter's layer struct is two text assignments,
// and that struct is filled for every background layer on the page, so
// a page with no cross-fade does not pay them.
bool anyCrossFade = false
// The user-agent origin's declarations for the element being computed,
// which is what `revert` rolls back to. Rebuilt per element, and only
// where a page says `revert` at all.
map[text] revertBase = {}
bool revertBaseTaken = false
// And the map as it stood before the layer being applied began, which is
// what `revert-layer` rolls back to.
map[text] layerBase = {}
// Whether any computed style anywhere asked for a background image by
// url(). A page with none never walks the document looking for them.
bool anyBackgroundUrl = false

// Whether any rule anywhere sets a counter, and how deep the style walk
// is. Almost no document uses counters, and maintaining the stack for
// every element would cost every page (CLAUDE.md §3).
bool anyCounters = false
// The quote depth is a running count over the whole document, not a
// measure of nesting: an element three containers deep is still at
// depth zero until something has emitted an open-quote.
bool anyQuotes = false
int quoteDepth = 0
int styleDepth = 0

// Set when any element's computed style carries a transform, so the
// painter can ask once per document instead of testing every box: a
// page with no transform pays one bool for the feature (CLAUDE.md, "a
// feature must not cost anything to the pages that do not use it").
bool cascadeSawTransform = false
// Whether any element computed a negative `z-index`. CSS2 §9.9's
// hoisting -- a negative child of a box that is not a stacking context
// is painted by the nearest ancestor that is -- costs a walk, and a
// document that never says one needs none of it.
bool cascadeSawNegativeZ = false
// Which computed styles **declared** a `z-index`. `auto` and `0` both
// compute to 0 here, and the difference is exactly what makes a
// positioned box a stacking context, so the fact that a declaration
// happened is kept beside the value rather than as a field on `Style`
// (benchmarks.md, "What one `int` on `Style` costs").
map[bool] explicitZIndexOfSerial = {}
bool anyExplicitZIndex = false

bool func zIndexIsExplicit(s:Style) {
    if !anyExplicitZIndex || s == null { return false }
    return explicitZIndexOfSerial[`${s.serial}`] == true
}
// The same question for `clip-path` and the legacy `clip`: a page with
// neither pays one bool, and the painter never asks a box.
bool cascadeSawClip = false
// Whether any declaration anywhere said `color-scheme`. A page that
// does not is every page that renders as it always did: the resolution
// below is skipped, `cssSchemeIsDark` stays false, and the nineteen
// system colours answer from the one table they always answered from.
bool cascadeSawColorScheme = false
// Whether anything on this page said which way the inline axis runs.
// The logical inline aliases resolve to the left edge in a left-to-right
// element and the right edge in a right-to-left one, so an element's
// direction has to be known before its declarations are applied -- and
// on a page that never mentions one, it is known without asking.
bool cascadeSawDirection = false
bool cascadeApplyRtl = false

// The same question for `writing-mode`, and for the same reason: a
// vertical mode makes `inline-start` the top edge and `block-start` a
// side, so the mode has to be known before the declarations are
// applied. A page that never says `writing-mode` never asks.
bool cascadeSawWritingMode = false
int cascadeApplyWM = 0
// Whether any element on this document is in a vertical writing mode.
// Layout and paint both ask it once per box, so it guards the work that
// would otherwise be done for pages with no vertical text on them.
bool anyVerticalWM = false

// What the container queries came to, keyed by element and query. It is
// filled by layoutDocument from the box tree of the pass before, so it
// is empty on the first pass and every container rule is dropped --
// which is the right starting point, since nothing is known about any
// container's size until something has been laid out.
map[int] containerQueryAnswers = {}

bool func containerQueryHolds(nid:int, q:int) {
    int got = containerQueryAnswers[`${nid}:${q}`]
    return got != null && got == 1
}
// And for `shape-outside`, which the float code asks once per document.
bool cascadeSawShape = false
// Whether any rule anywhere on this document writes `anchor-size(`.
// Without it, `computeStyleValues` would ask fourteen properties of
// every element for a function almost no page uses: the loop cost
// two milliseconds of cascade on features.html before this flag, which
// is what a paired benchmark found and what this exists to stop.
bool cascadeSawAnchorSize = false
// And for `font-size-adjust`, which is read at the very end of
// `computeStyleValues` and would otherwise be one map lookup for every
// element of every page.
bool cascadeSawFontSizeAdjust = false
// And for `baseline-source`.
bool cascadeSawBaselineSource = false
// And for `zoom`, which multiplies every pixel length of the element
// that says it and of everything under it.
bool cascadeSawZoom = false
// And for `resize`, which is one keyword read off the element that
// says it.
bool cascadeSawResize = false
// And for `text-wrap-style`, which is one keyword and inherits, so an
// element that says nothing still has to be asked about its parent --
// but only on a document where something said it.
bool cascadeSawTextWrapStyle = false
bool cascadeSawPrintColorAdjust = false
bool cascadeSawFontCaps = false
// And for the two ruby properties, which inherit for the same reason.
bool cascadeSawRuby = false
// The same question for `anchor(` inside an expression. The four
// insets are read of every element already, so this guards only the
// scan that tells a bare `anchor()` from one inside a `calc()`.
bool cascadeSawAnchorInset = false

// Raises whichever of the two flags a declaration value mentions, in
// ONE scan rather than two: both function names begin `anchor`, and
// the character after it says which. Lowercasing is done by the
// comparison rather than by rewriting the value, because this runs on
// every declaration of every rule and an `asciiLower` there allocates
// a string per declaration.
void func cascadeNoteAnchorFns(v:ascii) {
    int at = 0
    while true {
        int hit = asciiIndexOfLower(v, 'anchor', at)
        if hit < 0 { return }
        at = hit + 6
        if at < v.length && v.charCodeAt(at) == CH_LPAREN { cascadeSawAnchorInset = true }
        else if asciiStartsWithLower(v, '-size(', at) { cascadeSawAnchorSize = true }
        if cascadeSawAnchorSize && cascadeSawAnchorInset { return }
    }
}

void func cascadeReset() {
    // The `@page` rules come out of the same stylesheets, so they are
    // dropped with everything else: a second cascade of one document
    // would otherwise register every one of them twice.
    resetPageRules()
    anyPageBreak = false
    anyPlaceShorthand = false
    anyLateShorthand = false
    anySmallCaps = false
    map[int] emptyFontCaps = {}
    fontCapsOfSerial = emptyFontCaps
    anyUnicodeBidi = false
    anyCornerShape = false
    cornerCustomK = []
    anyAnchorName = false
    anyAnchorScope = false
    anyAnchorInset = false
    anyAnchorSize = false
    anchorInfos = []
    // A `Len` of kind LEN_MINMAX holds an INDEX into these, so they go
    // together: a table kept across documents would leave the previous
    // document's comparisons under the next one's indices.
    anyMinMax = false
    minmaxOp = []
    minmaxAt = []
    minmaxCount = []
    minmaxKind = []
    minmaxV = []
    minmaxPct = []
    anyOffsetPath = false
    anySticky = false
    anyFilter = false
    filterSpecs = []
    anyMask = false
    maskSpecs = []
    insetRadiiList = []
    motionInfos = []
    anyClipMargin = false
    map[int] emptyClipMargin = {}
    clipMarginOf = emptyClipMargin
    anyTextBoxTrim = false
    map[int] emptyTextBox = {}
    textBoxOf = emptyTextBox
    anyDecorationClone = false
    map[int] emptyDecoClone = {}
    decoCloneOf = emptyDecoClone
    anyOverscrollBehavior = false
    map[int] emptyOverscroll = {}
    overscrollOf = emptyOverscroll
    anyInitialLetter = false
    map[int] emptyInitialLetter = {}
    initialLetterOf = emptyInitialLetter
    map[int] emptyMotion = {}
    motionOfSerial = emptyMotion
    map[bool] emptyHidden = {}
    anchorHiddenIds = emptyHidden
    anyAnchorHidden = false
    cssResetLayers()
    cascadeSawTransform = false
    cascadeSawNegativeZ = false
    map[bool] emptyExplicitZ = {}
    explicitZIndexOfSerial = emptyExplicitZ
    anyExplicitZIndex = false
    cascadeSawClip = false
    cascadeSawColorScheme = false
    cascadeSawDirection = false
    cascadeApplyRtl = false
    cascadeSawWritingMode = false
    cascadeApplyWM = 0
    anyVerticalWM = false
    map[int] emptyContainerAnswers = {}
    containerQueryAnswers = emptyContainerAnswers
    cssResetContainerQueries()
    // A page that never says `color-scheme` skips the resolution
    // entirely, so this has to be put back here rather than left where
    // the last page left it: otherwise a dark page followed by an
    // ordinary one darkens the ordinary one's system colours.
    cssSchemeIsDark = false
    cascadeSawShape = false
    cascadeSawAnchorSize = false
    cascadeSawAnchorInset = false
    cascadeSawFontSizeAdjust = false
    cascadeSawBaselineSource = false
    cascadeSawZoom = false
    cascadeSawResize = false
    cascadeSawTextWrapStyle = false
    cascadeSawPrintColorAdjust = false
    cascadeSawFontCaps = false
    cascadeSawRuby = false
    anyZoom = false
    cascadeZoomScale = 1.0
    map[int] emptyZoom = {}
    zoomOfSerial = emptyZoom
    anyBaselineSource = false
    map[int] emptyBaselineSource = {}
    baselineSourceOfSerial = emptyBaselineSource
    anyResize = false
    map[int] emptyResize = {}
    resizeOfSerial = emptyResize
    anyTextWrapStyle = false
    map[int] emptyTextWrapStyle = {}
    textWrapStyleOfSerial = emptyTextWrapStyle
    anyRuby = false
    map[int] emptyRubyPos = {}
    map[int] emptyRubyAlign = {}
    rubyPositionOfSerial = emptyRubyPos
    rubyAlignOfSerial = emptyRubyAlign
    // A dragged size belongs to the document it was dragged in. The
    // node registry starts its ids again for every document, so an
    // override left behind would land on whichever element of the next
    // page happened to take that id.
    resizeUsedReset()
    cssResetNamespaces()
    cssResetCounterStyles()
    // The computed-style cache is keyed partly on declaration serials,
    // which are unique for the life of the process, so a stale entry
    // could never be returned for a new page -- but it would sit in the
    // map forever. A page load starts with an empty one.
    map[Style] emptyStyleCache = {}
    styleCache = emptyStyleCache
    anyPseudoRules = false
    pseudoTagSet = {}
    pseudoNonTag = false
    pseudoHasFirstLetter = {}
    pseudoHasFirstLine = {}
    pseudoHasMarker = {}
    anyMarker = false
    anyFirstLetter = false
    anyFirstLine = false
    firstLineStyles = {}
    anyRevert = false
    anyCrossFade = false
    anyBackgroundUrl = false
    anyCounters = false
    anyQuotes = false
    quoteDepth = 0
    resetPseudoElements()
    resetCounters()
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
        bool ruleHasSupportedSelector = false
        for int i = 0, i < rule.selectors.length, i++ {
            Selector sel = rule.selectors[i]
            if sel.unsupported || sel.parts.length == 0 { continue }
            RuleRef ref
            ref.rule = rule
            ref.sel = sel
            ref.origin = origin
            ref.layer = rule.layer
            ref.containerQuery = rule.containerQuery
            if sel.pseudoElement != '' {
                anyPseudoRules = true
                text pk = selectorKey(sel)
                if sel.pseudoElement == 'first-letter' { anyFirstLetter = true }
                if sel.pseudoElement == 'first-line' { anyFirstLine = true }
                if sel.pseudoElement == 'marker' { anyMarker = true }
                if pk == '*' || pk.charCodeAt(0) == CH_HASH || pk.charCodeAt(0) == CH_DOT {
                    pseudoNonTag = true
                } else {
                    pseudoTagSet[pk] = true
                }
            }
            addToBucket(selectorKey(sel), ref)
            ruleHasSupportedSelector = true
        }
        // Every per-document flag here is a question about this rule's
        // DECLARATIONS, so it is asked once per rule and in ONE pass
        // over them. It used to be nine passes, inside the loop over
        // the rule's selectors -- a rule with five selectors read its
        // declarations forty-five times, and each flag that stayed
        // false read all of them. The question is still only asked of
        // a rule that can match something, which is what the flag from
        // the loop above says.
        if !ruleHasSupportedSelector { continue }
        bool wantAnchor = !cascadeSawAnchorSize || !cascadeSawAnchorInset
        if anyCounters && anyQuotes && cascadeSawColorScheme && cascadeSawDirection
            && cascadeSawFontSizeAdjust && cascadeSawBaselineSource && cascadeSawZoom
            && cascadeSawResize && cascadeSawTextWrapStyle && cascadeSawRuby
            && cascadeSawPrintColorAdjust
            && anyRevert && !wantAnchor { continue }
        for int d = 0, d < rule.decls.length, d++ {
            text dn = rule.decls[d].name
            if !anyCounters && (dn == 'counter-reset' || dn == 'counter-increment'
                || dn == 'counter-set') { anyCounters = true }
            if !anyQuotes && dn == 'quotes' { anyQuotes = true }
            if !cascadeSawColorScheme && dn == 'color-scheme' { cascadeSawColorScheme = true }
            if !cascadeSawDirection && dn == 'direction' { cascadeSawDirection = true }
            if !cascadeSawWritingMode && dn == 'writing-mode' { cascadeSawWritingMode = true }
            if !cascadeSawFontSizeAdjust && dn == 'font-size-adjust' {
                cascadeSawFontSizeAdjust = true
            }
            if !cascadeSawBaselineSource && dn == 'baseline-source' {
                cascadeSawBaselineSource = true
            }
            if !cascadeSawZoom && dn == 'zoom' { cascadeSawZoom = true }
            if !cascadeSawResize && dn == 'resize' { cascadeSawResize = true }
            if !cascadeSawTextWrapStyle && (dn == 'text-wrap-style' || dn == 'text-wrap') {
                cascadeSawTextWrapStyle = true
            }
            if !cascadeSawFontCaps
                && (dn == 'font-variant-caps' || dn == 'font-variant' || dn == 'font') {
                cascadeSawFontCaps = true
            }
            if !cascadeSawPrintColorAdjust && dn == 'print-color-adjust' {
                cascadeSawPrintColorAdjust = true
            }
            if !cascadeSawRuby && (dn == 'ruby-position' || dn == 'ruby-align') {
                cascadeSawRuby = true
            }
            if !anyRevert && declIsRevert(rule.decls[d].value) { anyRevert = true }
            // The scan is inside `cascadeNoteAnchorFns`, and does not
            // lower the value first: this runs on every declaration of
            // every rule, and an `asciiLower` there allocates a string
            // per declaration. That cost six milliseconds of cascade on
            // generated.html, which a paired benchmark read as 22 of 25
            // pairs slower.
            if !cascadeSawAnchorSize || !cascadeSawAnchorInset {
                cascadeNoteAnchorFns(rule.decls[d].value)
            }
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

// The cascade sorts on origin, importance and layer first, then
// specificity, then source order (CSS Cascade 5 §6.4). Importance
// *inverts* the whole of that order: a normal author declaration beats
// a normal user-agent one, an important user-agent declaration beats an
// important author one, and an important declaration in an early layer
// beats one in a late layer. Inline style is author origin, ranked
// above author rules and in no layer.
//
//   normal UA < normal author layers, in order < normal unlayered author
//             < normal inline
//             < important author unlayered < important author layers,
//               in reverse < important inline < important UA
//
// The layers occupy a band of ranks each, which is why this is one
// number rather than the four the standard describes: Festina sorts on
// an int, and the tiers are packed into it in the order the standard
// compares them.
int func originRank(important:bool, origin:int, layer:int) {
    int span = CASCADE_MAX_LAYERS + 1
    int inLayer = layer < 0 || layer > CASCADE_NO_LAYER ? CASCADE_NO_LAYER : layer
    if !important {
        if origin == ORIGIN_UA { return 0 }
        if origin == ORIGIN_INLINE { return 1 + span }
        // 1 .. span: the layers in order, with no layer last.
        return 1 + inLayer
    }
    if origin == ORIGIN_UA { return 4 + 2 * span }
    if origin == ORIGIN_INLINE { return 3 + 2 * span }
    // An important declaration in no layer is the weakest of the
    // important author ones, and the earliest layer the strongest.
    if inLayer == CASCADE_NO_LAYER { return 2 + span }
    return 3 + span + (CASCADE_NO_LAYER - 1 - inLayer)
}

// The three tiers packed into one int, in the order the standard
// compares them. Specificity is a triple packed base 1024, so it is
// under 2^30, which times a million stays inside the rank's field; the
// rank reaches 518 with 256 layers, which times ten thousand billion
// stays inside an int. What has to give is source order, which holds a
// million rules and counts no further: a sheet with more than that
// decides its last rules on specificity alone.
int func matchWeight(important:bool, origin:int, layer:int, specificity:int, order:int) {
    return originRank(important, origin, layer) * 10000000000000000
         + specificity * 1000000
         + (order < 1000000 ? order : 999999)
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
    // The `i` flag matches without regard to case, which is one
    // lowercasing of both sides rather than a second comparison at
    // every operator below (Selectors 4 §6.3).
    text wanted = a.value
    if a.caseInsensitive {
        ascii lowered = v.toAscii()
        if lowered != null { v = asciiLower(lowered).toText() }
        ascii loweredWant = wanted.toAscii()
        if loweredWant != null { wanted = asciiLower(loweredWant).toText() }
    }
    if a.op == ATTR_EQUALS { return v == wanted }
    ascii av = v.toAscii()
    ascii want = wanted.toAscii()
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


// ---- HTML's form-state pseudo-classes (Selectors 4 §11) ---------------
//
// Every one of these is a question about the document's own attributes:
// no focus, no script and no user input is involved, so all of them are
// answerable here. What each one means was measured in Chromium against
// tests/fixtures/selectors.html rather than derived from its name, and
// todo.md records the answers -- several of them are not what the name
// suggests.

text func inputTypeOf(nid:int) {
    text t = attrOf(nid, 'type')
    if t == null || t == '' { return 'text' }
    ascii a = t.toAscii()
    if a == null { return 'text' }
    return asciiLower(a).toText()
}

// The input types `readonly` applies to (HTML §4.10.5.3.6). A checkbox
// is not one, which is why a checkbox is `:read-only` although nothing
// about it is readonly.
bool func inputTakesReadonly(t:text) {
    return t == 'text' || t == 'search' || t == 'url' || t == 'tel'
        || t == 'email' || t == 'password' || t == 'date' || t == 'month'
        || t == 'week' || t == 'time' || t == 'datetime-local' || t == 'number'
}

// `contenteditable` makes any element editable, and `false` on a nearer
// ancestor takes it back. The instrument's fixture holds no such
// element -- HTML's own controls are what it can grade -- so the unit
// suite is what asserts this branch.
bool func isContentEditable(nid:int) {
    int cur = nid
    while cur > 0 {
        if nodeRegistry[cur].kind != NODE_ELEMENT { return false }
        // `hasAttrOf` rather than a null test on the value: a
        // valueless `contenteditable` is present with an empty value,
        // and an empty `text` does not distinguish itself from an
        // absent one here.
        if hasAttrOf(cur, 'contenteditable') {
            text v = attrOf(cur, 'contenteditable')
            ascii a = v == null ? null : v.toAscii()
            text low = a == null ? '' : asciiLower(a).toText()
            if low == 'false' { return false }
            return true
        }
        cur = nodeRegistry[cur].parentId
    }
    return false
}

bool func isEditableControl(nid:int) {
    text tag = nodeRegistry[nid].tag
    if tag == 'textarea' || tag == 'input' {
        if hasAttrOf(nid, 'disabled') { return false }
        if hasAttrOf(nid, 'readonly') { return false }
        if tag == 'textarea' { return true }
        return inputTakesReadonly(inputTypeOf(nid))
    }
    return isContentEditable(nid)
}

// The controls `required` can be put on.
bool func isRequirableTag(tag:text) {
    return tag == 'input' || tag == 'select' || tag == 'textarea'
}

// An element's own value, as the document states it: an attribute for an
// input, the text content for a textarea.
text func controlValueOf(nid:int) {
    if nodeRegistry[nid].tag == 'textarea' {
        text out = ''
        arr[Node] kids = nodeRegistry[nid].children
        for int i = 0, i < kids.length, i++ {
            if kids[i].kind == NODE_TEXT && kids[i].data != null { out = out + kids[i].data }
        }
        return out
    }
    text v = attrOf(nid, 'value')
    return v == null ? '' : v
}

// The form this control belongs to, or 0. The `form` attribute is not
// read: nothing in the fixture uses it and nothing here could grade it.
int func owningFormOf(nid:int) {
    int cur = nodeRegistry[nid].parentId
    while cur > 0 {
        if nodeRegistry[cur].tag == 'form' { return cur }
        cur = nodeRegistry[cur].parentId
    }
    return 0
}

bool func isSubmitButton(nid:int) {
    text tag = nodeRegistry[nid].tag
    if tag == 'button' {
        text t = attrOf(nid, 'type')
        if t == null || t == '' { return true }
        ascii a = t.toAscii()
        return a != null && asciiLower(a).toText() == 'submit'
    }
    if tag != 'input' { return false }
    text t = inputTypeOf(nid)
    return t == 'submit' || t == 'image'
}

// The first submit button of `form` in document order, or 0.
int func firstSubmitIn(nid:int, form:int) {
    arr[Node] kids = nodeRegistry[nid].children
    for int i = 0, i < kids.length, i++ {
        int kid = kids[i].id
        if nodeRegistry[kid].kind != NODE_ELEMENT { continue }
        if isSubmitButton(kid) && owningFormOf(kid) == form { return kid }
        int deep = firstSubmitIn(kid, form)
        if deep > 0 { return deep }
    }
    return 0
}

// Whether any radio of this one's group is checked. The group is the
// controls with the same `name` inside the same form, or in the same
// document when there is none.
bool func radioGroupChecked(nid:int, root:int, name:text, form:int) {
    arr[Node] kids = nodeRegistry[root].children
    for int i = 0, i < kids.length, i++ {
        int kid = kids[i].id
        if nodeRegistry[kid].kind != NODE_ELEMENT { continue }
        if nodeRegistry[kid].tag == 'input' && inputTypeOf(kid) == 'radio'
            && attrOf(kid, 'name') == name && owningFormOf(kid) == form
            && hasAttrOf(kid, 'checked') { return true }
        if radioGroupChecked(nid, kid, name, form) { return true }
    }
    return false
}

int func documentRootOf(nid:int) {
    int cur = nid
    while nodeRegistry[cur].parentId > 0 { cur = nodeRegistry[cur].parentId }
    return cur
}

// Whether the element takes part in constraint validation at all.
// `disabled` and `readonly` bar it, and so do the button-like types --
// which is what keeps `:valid` and `:invalid` from partitioning every
// control between them, and what makes those two rows able to fail.
bool func isValidationCandidate(nid:int) {
    text tag = nodeRegistry[nid].tag
    if !isRequirableTag(tag) { return false }
    if hasAttrOf(nid, 'disabled') { return false }
    if hasAttrOf(nid, 'readonly') { return false }
    if tag != 'input' { return true }
    text t = inputTypeOf(nid)
    return t != 'hidden' && t != 'reset' && t != 'button' && t != 'submit' && t != 'image'
}

// The range a number-like input declares, if it declares one.
bool func inputTakesRange(t:text) {
    return t == 'number' || t == 'range' || t == 'date' || t == 'month'
        || t == 'week' || t == 'time' || t == 'datetime-local'
}

const int RANGE_NONE = 0
const int RANGE_IN = 1
const int RANGE_OUT = 2

int func inputRangeState(nid:int) {
    if nodeRegistry[nid].tag != 'input' { return RANGE_NONE }
    if !inputTakesRange(inputTypeOf(nid)) { return RANGE_NONE }
    text lo = attrOf(nid, 'min')
    text hi = attrOf(nid, 'max')
    if (lo == null || lo == '') && (hi == null || hi == '') { return RANGE_NONE }
    text v = controlValueOf(nid)
    if v == '' { return RANGE_NONE }
    float value = parseFloatAscii(v.toAscii())
    if lo != null && lo != '' && value < parseFloatAscii(lo.toAscii()) { return RANGE_OUT }
    if hi != null && hi != '' && value > parseFloatAscii(hi.toAscii()) { return RANGE_OUT }
    return RANGE_IN
}

// HTML's `valid e-mail address` production, which is a fixed grammar
// rather than an opinion: one or more of a named set before an `@`,
// then a dot-separated sequence of labels that each begin and end with
// a letter or digit. A bare label after the `@` is allowed -- `a@b` is
// valid, measured -- and a missing local part, a missing domain, a
// second `@` and an inner space are not.
bool func isEmailAtomCode(c:int) {
    if (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) { return true }
    // . ! # $ % & ' * + / = ? ^ _ ` { | } ~ -
    return c == 46 || c == 33 || c == 35 || c == 36 || c == 37 || c == 38
        || c == 39 || c == 42 || c == 43 || c == 47 || c == 61 || c == 63
        || c == 94 || c == 95 || c == 96 || c == 123 || c == 124 || c == 125
        || c == 126 || c == 45
}

bool func isValidEmail(a:ascii) {
    if a == null { return false }
    int n = a.length
    int at = 0 - 1
    for int i = 0, i < n, i++ {
        if a.charCodeAt(i) != 64 { continue }              // @
        if at >= 0 { return false }                        // a second one
        at = i
    }
    if at <= 0 || at == n - 1 { return false }
    for int i = 0, i < at, i++ {
        if !isEmailAtomCode(a.charCodeAt(i)) { return false }
    }
    // the domain: labels of alphanumerics and hyphens, each beginning
    // and ending with an alphanumeric, separated by dots
    int i = at + 1
    while i < n {
        int start = i
        while i < n && a.charCodeAt(i) != 46 { i++ }
        if i == start { return false }
        if !isAlnumCode(a.charCodeAt(start)) { return false }
        if !isAlnumCode(a.charCodeAt(i - 1)) { return false }
        for int j = start, j < i, j++ {
            int c = a.charCodeAt(j)
            if !isAlnumCode(c) && c != 45 { return false }
        }
        if i < n { i++  if i == n { return false } }
    }
    return true
}

// A valid absolute URL, as far as markup can tell: a scheme, then `:`,
// and where a `//` follows it a non-empty host. `foo:bar` is valid and
// `//example.com` and `http://` are not, measured.
bool func isValidUrl(a:ascii) {
    if a == null || a.length == 0 { return false }
    int n = a.length
    int c0 = a.charCodeAt(0)
    if !((c0 >= 65 && c0 <= 90) || (c0 >= 97 && c0 <= 122)) { return false }
    int i = 1
    while i < n {
        int c = a.charCodeAt(i)
        if c == 58 { break }                               // :
        if !isAlnumCode(c) && c != 43 && c != 45 && c != 46 { return false }
        i++
    }
    if i >= n { return false }                             // no colon
    int rest = i + 1
    if rest + 1 < n && a.charCodeAt(rest) == 47 && a.charCodeAt(rest + 1) == 47 {
        int h = rest + 2
        int hostEnd = h
        while hostEnd < n && a.charCodeAt(hostEnd) != 47 && a.charCodeAt(hostEnd) != 63
            && a.charCodeAt(hostEnd) != 35 { hostEnd++ }
        return hostEnd > h
    }
    return true
}

// §4.10.5.3.6's step base: the `min` attribute if there is one, and
// otherwise the `value` *content* attribute. So `step=5 value=7`
// measures 7 from 7 and is a whole zero steps -- a step mismatch can
// only come out of markup when `min` is there too, which is measured
// rather than derived.
bool func stepMismatches(nid:int) {
    if nodeRegistry[nid].tag != 'input' { return false }
    text t = inputTypeOf(nid)
    if !inputTakesRange(t) { return false }
    // A `range` sanitises its value to the nearest step before anything
    // can ask, so it never mismatches.
    if t == 'range' { return false }
    text st = attrOf(nid, 'step')
    if st == null || st == '' { return false }
    ascii sa = st.toAscii()
    if sa != null && asciiLower(sa).toText() == 'any' { return false }
    float step = parseFloatAscii(sa)
    if step <= 0.0 { return false }
    text v = controlValueOf(nid)
    if v == '' { return false }
    text lo = attrOf(nid, 'min')
    float base = lo != null && lo != '' ? parseFloatAscii(lo.toAscii()) : parseFloatAscii(v.toAscii())
    float off = parseFloatAscii(v.toAscii()) - base
    float steps = off / step
    float nearest = Math.round(steps).toFloat()
    float slack = step / 100000.0
    float diff = nearest * step - off
    if diff < 0.0 { diff = 0.0 - diff }
    return diff > slack
}

// The value a control is judged to have. A checkbox or a radio has one
// only when it is checked; a select's is its selected option's, which
// is that option's own text when it declares no `value`; everything
// else is the attribute or the text content.
text func validationValueOf(nid:int) {
    text tag = nodeRegistry[nid].tag
    if tag == 'input' {
        text t = inputTypeOf(nid)
        if t == 'checkbox' || t == 'radio' {
            return hasAttrOf(nid, 'checked') ? 'on' : ''
        }
        return controlValueOf(nid)
    }
    if tag == 'select' { return selectedValueOf(nid) }
    return controlValueOf(nid)
}

// The value of the option a select has selected, or '' when it has
// selected none. A `multiple` select selects nothing of its own, which
// is why the same markup satisfies `required` without it and fails with
// it.
text func selectedValueOf(nid:int) {
    arr[Node] kids = nodeRegistry[nid].children
    for int i = 0, i < kids.length, i++ {
        int kid = kids[i].id
        if nodeRegistry[kid].kind != NODE_ELEMENT { continue }
        if nodeRegistry[kid].tag == 'optgroup' {
            text deep = selectedValueOf(kid)
            if deep != '' { return deep }
            continue
        }
        if nodeRegistry[kid].tag != 'option' { continue }
        if !optionIsSelected(kid) { continue }
        if hasAttrOf(kid, 'value') {
            text v = attrOf(kid, 'value')
            return v == null ? '' : v
        }
        // With no `value`, an option's value is its own text.
        text out = ''
        arr[Node] tk = nodeRegistry[kid].children
        for int j = 0, j < tk.length, j++ {
            if tk[j].kind == NODE_TEXT && tk[j].data != null { out = out + tk[j].data }
        }
        return asciiTrim(out.toAscii()).toText()
    }
    return ''
}

// Whether a control satisfies its constraints. Four of HTML's
// conditions come out of markup and are read: a missing required value,
// a value outside a declared range, a type mismatch on `email` or
// `url`, and a step mismatch. `minlength` and `maxlength` apply only
// once a user has edited the value and `pattern` needs a regular
// expression engine; todo.md records both.
bool func controlIsValid(nid:int) {
    text v = validationValueOf(nid)
    if hasAttrOf(nid, 'required') && v == '' { return false }
    if inputRangeState(nid) == RANGE_OUT { return false }
    if stepMismatches(nid) { return false }
    if v != '' && nodeRegistry[nid].tag == 'input' {
        text t = inputTypeOf(nid)
        // `multiple` makes the value a comma-separated list, and each
        // part is judged on its own.
        if t == 'email' {
            if hasAttrOf(nid, 'multiple') {
                arr[ascii] parts = asciiSplitChar(v.toAscii(), CH_COMMA)
                for int i = 0, i < parts.length, i++ {
                    if !isValidEmail(asciiTrim(parts[i])) { return false }
                }
                return true
            }
            return isValidEmail(v.toAscii())
        }
        if t == 'url' { return isValidUrl(v.toAscii()) }
    }
    return true
}

// Whether any validation candidate inside this form or fieldset fails.
bool func hasInvalidControl(nid:int, form:int) {
    arr[Node] kids = nodeRegistry[nid].children
    for int i = 0, i < kids.length, i++ {
        int kid = kids[i].id
        if nodeRegistry[kid].kind != NODE_ELEMENT { continue }
        if isValidationCandidate(kid) && owningFormOf(kid) == form && !controlIsValid(kid) { return true }
        if hasInvalidControl(kid, form) { return true }
    }
    return false
}

// The value of `dir` on this element, lowercased, or '' when it has
// none or one neither engine recognises. `dir="bogus"` is not a
// declaration at all and falls through to the parent, measured.
text func dirAttrOf(nid:int) {
    if !hasAttrOf(nid, 'dir') { return '' }
    text v = attrOf(nid, 'dir')
    ascii a = v == null ? null : v.toAscii()
    text low = a == null ? '' : asciiLower(a).toText()
    if low == 'rtl' || low == 'ltr' || low == 'auto' { return low }
    return ''
}

// Whether this element's text counts towards an ancestor's `dir="auto"`
// (HTML §3.2.6.4). A descendant that declares its own direction is
// answering the question for itself, so it is passed over; so are the
// elements whose text is not the document's prose. A `select` is not on
// the list, which is the row no reading of the name would give: a
// textarea's own contents are skipped and an option's are not.
bool func dirAutoSkips(nid:int) {
    if dirAttrOf(nid) != '' { return true }
    text tag = nodeRegistry[nid].tag
    return tag == 'bdi' || tag == 'script' || tag == 'style'
        || tag == 'textarea' || tag == 'input'
}

// The first strong character of a run of text, as a direction, or ''.
// UAX #9's L is left-to-right and R and AL are right-to-left; a digit, a
// quotation mark and whitespace are none of those, which is why
// `123 "<hebrew>" said` reads right-to-left.
text func firstStrongOf(t:text) {
    if t == null { return '' }
    for int i = 0, i < t.length, i++ {
        int cls = bidiClass(t.charCodeAt(i))
        if cls == BIDI_L { return 'ltr' }
        if cls == BIDI_R || cls == BIDI_AL { return 'rtl' }
    }
    return ''
}

// The first strong character in this element's subtree, skipping the
// descendants that do not count.
text func firstStrongIn(nid:int) {
    arr[Node] kids = nodeRegistry[nid].children
    for int i = 0, i < kids.length, i++ {
        Node k = kids[i]
        if k.kind == NODE_TEXT {
            text got = firstStrongOf(k.data)
            if got != '' { return got }
            continue
        }
        if k.kind != NODE_ELEMENT { continue }
        if dirAutoSkips(k.id) { continue }
        text got = firstStrongIn(k.id)
        if got != '' { return got }
    }
    return ''
}

// `dir="auto"`, and `bdi` with no `dir` at all, which is the same thing
// written as an element. A control that holds its own value reads that
// rather than its children.
text func autoDirectionOf(nid:int) {
    text tag = nodeRegistry[nid].tag
    text got = ''
    if tag == 'input' {
        if inputTakesReadonly(inputTypeOf(nid)) { got = firstStrongOf(controlValueOf(nid)) }
    } else if tag == 'textarea' {
        got = firstStrongOf(controlValueOf(nid))
    } else {
        got = firstStrongIn(nid)
    }
    return got == '' ? 'ltr' : got
}

// The element's directionality: the nearest ancestor-or-self that
// declares one. `auto` is a declaration that computes rather than
// inherits, so it stops the walk too.
text func directionalityOf(nid:int) {
    int cur = nid
    while cur > 0 {
        if nodeRegistry[cur].kind != NODE_ELEMENT { break }
        text d = dirAttrOf(cur)
        if d == 'rtl' || d == 'ltr' { return d }
        if d == 'auto' { return autoDirectionOf(cur) }
        // `<bdi>` is `dir="auto"` with no attribute, which is the whole
        // reason the element exists: English inside a right-to-left
        // division reads left to right.
        if nodeRegistry[cur].tag == 'bdi' { return autoDirectionOf(cur) }
        cur = nodeRegistry[cur].parentId
    }
    return 'ltr'
}

// The family, answered in one place. Called from `pseudoMatches` after
// every pseudo-class the engine already had, so nothing that worked
// before pays a comparison for these.
bool func formStateMatches(nid:int, name:text, a:ascii) {
    text tag = nodeRegistry[nid].tag
    if name == 'read-write' { return isEditableControl(nid) }
    if name == 'read-only' { return !isEditableControl(nid) }
    if name == 'required' { return isRequirableTag(tag) && hasAttrOf(nid, 'required') }
    if name == 'optional' { return isRequirableTag(tag) && !hasAttrOf(nid, 'required') }
    if name == 'placeholder-shown' {
        if tag != 'input' && tag != 'textarea' { return false }
        if tag == 'input' && !inputTakesReadonly(inputTypeOf(nid)) { return false }
        text ph = attrOf(nid, 'placeholder')
        return ph != null && ph != '' && controlValueOf(nid) == ''
    }
    if name == 'default' {
        if tag == 'option' { return hasAttrOf(nid, 'selected') }
        if tag == 'input' {
            text t = inputTypeOf(nid)
            if t == 'checkbox' || t == 'radio' { return hasAttrOf(nid, 'checked') }
        }
        if !isSubmitButton(nid) { return false }
        int form = owningFormOf(nid)
        if form == 0 { return false }
        return firstSubmitIn(form, form) == nid
    }
    if name == 'indeterminate' {
        if tag != 'input' || inputTypeOf(nid) != 'radio' { return false }
        text nm = attrOf(nid, 'name')
        if nm == null { nm = '' }
        int form = owningFormOf(nid)
        return !radioGroupChecked(nid, documentRootOf(nid), nm, form)
    }
    if name == 'valid' || name == 'invalid' {
        bool ok = true
        if tag == 'form' {
            ok = !hasInvalidControl(nid, nid)
        } else if isValidationCandidate(nid) {
            ok = controlIsValid(nid)
        } else {
            return false
        }
        return name == 'valid' ? ok : !ok
    }
    if name == 'in-range' { return inputRangeState(nid) == RANGE_IN }
    if name == 'out-of-range' { return inputRangeState(nid) == RANGE_OUT }
    if asciiStartsWith(a, 'dir:', 0) {
        return directionalityOf(nid) == a.slice(4, a.length).toText()
    }
    return false
}

// Whether an `<option>` is selected. The attribute is not the whole
// answer: a single-selection `<select>` with nothing declared selects
// its **first** option (HTML §4.10.7), so `option:checked` matches it
// although the document says nothing. Found by the selector instrument
// when the fixture gained a select whose option carries no `selected`,
// which is the point of putting one there.
bool func optionIsSelected(nid:int) {
    if hasAttrOf(nid, 'selected') { return true }
    int sel = 0
    int cur = nodeRegistry[nid].parentId
    while cur > 0 {
        if nodeRegistry[cur].tag == 'select' { sel = cur  break }
        if nodeRegistry[cur].tag != 'optgroup' { break }
        cur = nodeRegistry[cur].parentId
    }
    if sel == 0 { return false }
    if hasAttrOf(sel, 'multiple') { return false }
    // A `size` above one is a list box, which selects nothing of its own.
    text sz = attrOf(sel, 'size')
    if sz != null && sz != '' && sz.toInt() > 1 { return false }
    return firstSelectableOption(sel, sel) == nid
}

// The first `<option>` of a select in tree order, or the first one
// carrying `selected` if any does -- in which case this one is not the
// default and the caller's attribute test has already answered.
int func firstSelectableOption(nid:int, sel:int) {
    arr[Node] kids = nodeRegistry[nid].children
    int first = 0
    for int i = 0, i < kids.length, i++ {
        int kid = kids[i].id
        if nodeRegistry[kid].kind != NODE_ELEMENT { continue }
        if nodeRegistry[kid].tag == 'option' {
            if hasAttrOf(kid, 'selected') { return 0 }
            if first == 0 { first = kid }
            continue
        }
        if nodeRegistry[kid].tag == 'optgroup' {
            int deep = firstSelectableOption(kid, sel)
            if deep == 0 && first == 0 { return 0 }
            if deep > 0 && first == 0 { first = deep }
        }
    }
    return first
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
    if name == 'only-of-type' {
        return pseudoMatches(nid, 'first-of-type') && pseudoMatches(nid, 'last-of-type')
    }
    if name == 'empty' {
        // Selectors 3 SS6.6.5.7: no children at all, not even text.
        // A comment is not a child for this purpose; whitespace is.
        Node e = nodeRegistry[nid]
        for int i = 0, i < e.children.length, i++ {
            Node c = e.children[i]
            if c.kind == NODE_ELEMENT { return false }
            if c.kind == NODE_TEXT && c.data != null && c.data.length > 0 { return false }
        }
        return true
    }
    if name == 'enabled' || name == 'disabled' {
        if !isEnableableTag(nodeRegistry[nid].tag) { return false }
        bool off = hasAttrOf(nid, 'disabled')
        return name == 'disabled' ? off : !off
    }
    if name == 'checked' {
        text tag = nodeRegistry[nid].tag
        if tag == 'option' { return optionIsSelected(nid) }
        if tag != 'input' { return false }
        text t = attrOf(nid, 'type')
        text lower = t == null ? '' : asciiLower(t.toAscii()).toText()
        if lower != 'checkbox' && lower != 'radio' { return false }
        return hasAttrOf(nid, 'checked')
    }
    if name == 'target' {
        // No fragment is ever navigated to, so nothing is the target.
        // Matching nothing is what the standard says for that state.
        return false
    }

    ascii a = name.toAscii()
    if asciiStartsWith(a, 'lang:', 0) {
        ascii want = a.slice(5, a.length)
        // the nearest ancestor with a lang attribute decides
        int cur = nid
        while cur > 0 {
            text got = attrOf(cur, 'lang')
            if got != null && got != '' {
                ascii have = asciiLower(got.toAscii())
                if have == want { return true }
                // `:lang(fr)` also matches `fr-CA`
                if have.length > want.length && asciiStartsWith(have, want, 0)
                    && have.charCodeAt(want.length) == CH_MINUS { return true }
                return false
            }
            cur = nodeRegistry[cur].parentId
        }
        return false
    }

    // the nth family: `<name>:<A>:<B>`, matching when the element's
    // index is A*n + B for some integer n >= 0 (Selectors 3 SS6.6.5).
    bool fromEnd = asciiStartsWith(a, 'nth-last-child:', 0) || asciiStartsWith(a, 'nth-last-of-type:', 0)
    bool ofType = asciiStartsWith(a, 'nth-of-type:', 0) || asciiStartsWith(a, 'nth-last-of-type:', 0)
    bool isNth = ofType || asciiStartsWith(a, 'nth-child:', 0) || asciiStartsWith(a, 'nth-last-child:', 0)
    if isNth {
        int colon = asciiIndexOf(a, ':'.toAscii(), 0)
        int colon2 = asciiIndexOf(a, ':'.toAscii(), colon + 1)
        if colon < 0 || colon2 < 0 { return false }
        int stepA = a.slice(colon + 1, colon2).toText().toInt()
        int offB = a.slice(colon2 + 1, a.length).toText().toInt()
        int pos = nthIndexOf(nid, fromEnd, ofType)
        return nthMatches(pos, stepA, offB)
    }
    return formStateMatches(nid, name, a)
}

// Whether `disabled` means anything on this element (HTML's own list of
// form controls). `:enabled` matches only elements that could be
// disabled, so a <div> is neither enabled nor disabled.
bool func isEnableableTag(tag:text) {
    return tag == 'input' || tag == 'button' || tag == 'select' || tag == 'textarea'
        || tag == 'option' || tag == 'optgroup' || tag == 'fieldset'
}

// The element's 1-based index among its siblings, counted from the end
// when `fromEnd`, and among siblings of the same tag when `ofType`.
int func nthIndexOf(nid:int, fromEnd:bool, ofType:bool) {
    text tag = nodeRegistry[nid].tag
    int pos = 1
    int sib = fromEnd ? nextElementSiblingOf(nid) : prevElementSiblingOf(nid)
    while sib > 0 {
        if !ofType || nodeRegistry[sib].tag == tag { pos++ }
        sib = fromEnd ? nextElementSiblingOf(sib) : prevElementSiblingOf(sib)
    }
    return pos
}

// Is there an integer n >= 0 with pos == stepA * n + offB?
bool func nthMatches(pos:int, stepA:int, offB:int) {
    if stepA == 0 { return pos == offB }
    int diff = pos - offB
    if diff % stepA != 0 { return false }
    return Math.floorDiv(diff, stepA) >= 0
}

// Whether `anc` is an ancestor of `nid`.
bool func isAncestorOf(anc:int, nid:int) {
    int p = nodeRegistry[nid].parentId
    while p > 0 {
        if p == anc { return true }
        p = nodeRegistry[p].parentId
    }
    return false
}

// `:has()` takes a *relative* selector (Selectors 4 §4.2): its leading
// combinator says how the element it finds stands to the element being
// tested, and the bare form means a descendant. So the argument is a
// whole complex selector anchored at one end to this element, and the
// question is whether any element satisfies it.
//
// The anchor is checked where the walk runs out of compounds: the
// leftmost one has matched some element, and that element must stand to
// `scope` in the relation `lead` names. Without that the argument would
// be an ordinary selector and `div:has(> p)` would find a `p` anywhere
// below.
bool func relAnchorHolds(nid:int, scope:int, lead:int) {
    if lead == COMB_CHILD { return nodeRegistry[nid].parentId == scope }
    if lead == COMB_ADJACENT { return prevElementSiblingOf(nid) == scope }
    if lead == COMB_SIBLING {
        int prev = prevElementSiblingOf(nid)
        while prev > 0 {
            if prev == scope { return true }
            prev = prevElementSiblingOf(prev)
        }
        return false
    }
    return isAncestorOf(scope, nid)
}

// matchFrom, with the extra condition that the leftmost compound's
// element stands to `scope` as `lead` says.
bool func matchFromRelative(nid:int, sel:Selector, index:int, scope:int, lead:int) {
    if !matchCompound(nid, sel.parts[index]) { return false }
    if index == 0 { return relAnchorHolds(nid, scope, lead) }
    int comb = sel.parts[index].combinator
    if comb == COMB_CHILD {
        int parent = nodeRegistry[nid].parentId
        if parent <= 0 { return false }
        return matchFromRelative(parent, sel, index - 1, scope, lead)
    }
    if comb == COMB_ADJACENT {
        int prev = prevElementSiblingOf(nid)
        if prev == 0 { return false }
        return matchFromRelative(prev, sel, index - 1, scope, lead)
    }
    if comb == COMB_SIBLING {
        int prev = prevElementSiblingOf(nid)
        while prev > 0 {
            if matchFromRelative(prev, sel, index - 1, scope, lead) { return true }
            prev = prevElementSiblingOf(prev)
        }
        return false
    }
    int anc = nodeRegistry[nid].parentId
    while anc > 0 {
        if nodeRegistry[anc].kind != NODE_ELEMENT { return false }
        if matchFromRelative(anc, sel, index - 1, scope, lead) { return true }
        anc = nodeRegistry[anc].parentId
    }
    return false
}

// Every element of the subtree rooted at `nid`, itself excluded, tried
// as the subject of one alternative.
bool func relSubtreeMatches(nid:int, scope:int, alt:Selector, lead:int) {
    arr[Node] kids = nodeRegistry[nid].children
    for int i = 0, i < kids.length, i++ {
        int kid = kids[i].id
        if nodeRegistry[kid].kind != NODE_ELEMENT { continue }
        if matchFromRelative(kid, alt, alt.parts.length - 1, scope, lead) { return true }
        if relSubtreeMatches(kid, scope, alt, lead) { return true }
    }
    return false
}

// One alternative of a `:has()`, with the relation it opened with.
//
// Where the subject can be follows from that relation: a descendant or
// child relation puts the whole match inside this element's subtree, a
// sibling relation puts it in a following sibling's. Walking only those
// is what keeps `:has()` from being a scan of the document.
bool func relMatches(nid:int, alt:Selector, lead:int) {
    if lead == COMB_ADJACENT || lead == COMB_SIBLING {
        int sib = nextElementSiblingOf(nid)
        while sib > 0 {
            if matchFromRelative(sib, alt, alt.parts.length - 1, nid, lead) { return true }
            if relSubtreeMatches(sib, nid, alt, lead) { return true }
            if lead == COMB_ADJACENT { return false }
            sib = nextElementSiblingOf(sib)
        }
        return false
    }
    return relSubtreeMatches(nid, nid, alt, lead)
}

bool func hasMatchingDescendant(nid:int, sub:SubSelector) {
    for int k = 0, k < sub.alternatives.length, k++ {
        int lead = k < sub.leads.length ? sub.leads[k] : COMB_DESCENDANT
        if relMatches(nid, sub.alternatives[k], lead) { return true }
    }
    return false
}

// Whether the element matches any alternative of an `of` clause.
bool func nthOfMatches(nid:int, of:arr[Selector]) {
    for int k = 0, k < of.length, k++ {
        if matchSelector(nid, of[k]) { return true }
    }
    return false
}

// `:nth-child(An+B of S)` (Selectors 4 §6.6.5). The element's position
// is counted among the siblings that match S, and the element must be
// one of them: `:nth-child(2 of .lead)` is the second `.lead` rather
// than a `.lead` that happens to be second.
//
// Its own function, called only when a compound carries one, because a
// call written inside `matchCompound` costs the pages that never reach
// it (CLAUDE.md, "A feature must not cost anything to the pages that do
// not use it").
bool func matchNthOf(nid:int, c:Compound) {
    for int i = 0, i < c.nths.length, i++ {
        NthOf nth = c.nths[i]
        if !nthOfMatches(nid, nth.of) { return false }
        int pos = 1
        int sib = nth.fromEnd ? nextElementSiblingOf(nid) : prevElementSiblingOf(nid)
        while sib > 0 {
            if nthOfMatches(sib, nth.of) { pos++ }
            sib = nth.fromEnd ? nextElementSiblingOf(sib) : prevElementSiblingOf(sib)
        }
        if !nthMatches(pos, nth.stepA, nth.offB) { return false }
    }
    return true
}

bool func matchSubSelectors(nid:int, c:Compound) {
    for int i = 0, i < c.subs.length, i++ {
        SubSelector sub = c.subs[i]
        if sub.kind == SUBSEL_HAS {
            if !hasMatchingDescendant(nid, sub) { return false }
            continue
        }
        bool any = false
        for int k = 0, k < sub.alternatives.length, k++ {
            if matchSelector(nid, sub.alternatives[k]) { any = true }
        }
        // `:not()` wants none of them to match; `:is()` and `:where()`
        // want any. That is the whole difference between the three.
        if sub.kind == SUBSEL_NOT {
            if any { return false }
        } else if !any { return false }
    }
    return true
}

bool func matchCompound(nid:int, c:Compound) {
    if nodeRegistry[nid].kind != NODE_ELEMENT { return false }
    if c.unsupported { return false }
    // Every element this engine builds comes from an HTML document, so
    // it is in the XHTML namespace; a namespace part is a question
    // about that one string (CSS Namespaces 3).
    if c.nsKind != NS_DEFAULT || cssDefaultNamespace != '' {
        if !namespaceAccepts(c, XHTML_NS) { return false }
    }
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
    // The four functional pseudo-classes live in their own function
    // rather than in this loop, and this call is guarded by a length.
    // Inlined here, the call to `matchSelector` that `:is()` needs put
    // `matchCompound` inside a cycle the compiler would not inline, and
    // a page with no `:is()`, `:not()` or `:has()` on it paid two
    // milliseconds of cascade for a loop it ran zero times.
    if c.subs.length > 0 && !matchSubSelectors(nid, c) { return false }
    if c.nths.length > 0 && !matchNthOf(nid, c) { return false }
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
    // Almost no element carries one of these, and this used to be a
    // dozen map lookups on every element in the document -- 8 ms of the
    // cascade's 15 ms collection phase on the benchmark page. A cell is
    // the exception: `border` and `cellpadding` on the table it sits in
    // style the cell, so a cell has to look even when it carries
    // nothing itself.
    text tag = n.tag
    bool isCell = tag == 'td' || tag == 'th'
    if !n.hasPresHint && !isCell { return }
    int w = matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 0, 0)
    // HTML's `dir` is what right-to-left content actually carries, and
    // it means `direction` (HTML, "Rendering"). It arrives here rather
    // than as a `[dir=rtl]` rule in the user-agent stylesheet because
    // such a rule has no tag, class or id to bucket on and would be
    // tested against every element of every page; a presentational hint
    // is looked at only for an element that has one.
    // Only an element that carries a presentational attribute can carry
    // this one, `dir` being in that list, so the cell path below -- which
    // runs for every cell whether it has an attribute or not -- must not
    // pay for the lookup. It did, and the benchmark page's 1,560 cells
    // made that about two milliseconds.
    if n.hasPresHint {
        text dirAttr = getAttr(n, 'dir')
        if dirAttr != null {
            ascii d = asciiLower(dirAttr.toAscii())
            if d == 'rtl' || d == 'ltr' {
                cascadeSawDirection = true
                addMatch(matches, 'direction', d.toText(), w)
            }
        }
    }
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
    if isCell {
        int tbl = closestElementId(n, 'table')
        if tbl > 0 && nodeRegistry[tbl].hasPresHint {
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
    // `<ol type>` is the oldest way to ask for letters or roman numerals,
    // and the standard maps it to `list-style-type` as a presentational
    // hint (HTML, "the `ol` element").
    if tag == 'ol' {
        text ty = getAttr(n, 'type')
        if ty != null {
            if ty == 'a' { addMatch(matches, 'list-style-type', 'lower-alpha', w) }
            else if ty == 'A' { addMatch(matches, 'list-style-type', 'upper-alpha', w) }
            else if ty == 'i' { addMatch(matches, 'list-style-type', 'lower-roman', w) }
            else if ty == 'I' { addMatch(matches, 'list-style-type', 'upper-roman', w) }
            else if ty == '1' { addMatch(matches, 'list-style-type', 'decimal', w) }
        }
    }
    // A checkbox's size is not a presentational hint: it is the size
    // the user agent supplies for the control it draws, and
    // `appearance: none` asks it not to draw one. A hint would still be
    // a declared width, which `appearance: none` has no way to undo, so
    // the size is an intrinsic one applied in layout instead.
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
// Which generated box the current collection is for: '' for the element
// itself, 'before' or 'after' for one of its pseudo-elements. A rule
// with a pseudo-element does not style the element it matches, and a
// rule without one does not style the generated box, so the two passes
// are the same walk with opposite filters.
text collectingPseudo = ''

// Which pseudo-element the style being computed is for, as it appears in
// the sharing cache's key. '' for an element's own style. Globals are
// not hoisted here, so it sits beside the flag it belongs with rather
// than beside the function that reads it.
text collectingPseudoKey = ''

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
        if b.refs[i].sel.pseudoElement != collectingPseudo { continue }
        // A rule inside `@container` applies only where that query is
        // satisfied. The answers come from the layout pass before this
        // one, and the test is skipped entirely on a page whose sheets
        // never said `@container`.
        if cssSawContainerQuery && b.refs[i].containerQuery != CQ_NONE
            && !containerQueryHolds(nid, b.refs[i].containerQuery) { continue }
        profSelectorTests++
        if !matchSelector(nid, b.refs[i].sel) { continue }
        int decls = b.refs[i].rule.decls.length
        int specificity = b.refs[i].sel.specificity
        int origin = b.refs[i].origin
        int order = b.refs[i].rule.order
        // A layer's rank, read once per rule rather than once per
        // declaration, and not at all on a page with no `@layer` on it.
        // The four milliseconds this change first cost were the array
        // literals in the shorthand guards rather than this call --
        // moving it out here changed nothing measurable, and it stays
        // because reading a global once per rule is plainly cheaper
        // than once per declaration, not because a benchmark said so.
        int layerRank = cssLayerRank.length == 0 ? b.refs[i].layer
                                                 : cssLayerRankOf(b.refs[i].layer)
        for int d = 0, d < decls, d++ {
            Match m
            m.decl = b.refs[i].rule.decls[d]
            m.weight = matchWeight(b.refs[i].rule.decls[d].important, origin,
                                   layerRank, specificity, order)
            matches.push(m)
        }
    }
}

// What a `resize` drag has made a box, by the id of the element it
// belongs to. The box tree is rebuilt on every layout and the size has
// to outlive it, exactly as a scroll offset does (layout.f), and the
// node registry is what lasts. A page nobody has dragged never touches
// either map.
//
// The size is a BORDER box, because that is the rectangle the pointer
// took hold of a corner of. It reaches layout as a declaration rather
// than as a field the layout code reads: a computed `Style` is shared
// between elements that matched the same rules and is never written to
// after it is computed, so a used size that belongs to one element has
// to change what that element MATCHED -- which is also what keeps it
// out of every other element's cache entry.
map[int] resizeUsedW = {}
map[int] resizeUsedH = {}
bool anyResizeUsed = false

void func resizeUsedReset() {
    map[int] emptyW = {}
    map[int] emptyH = {}
    resizeUsedW = emptyW
    resizeUsedH = emptyH
    anyResizeUsed = false
}

void func resizeUsedMatches(n:Node, matches:arr[Match]) {
    int w = resizeUsedW[`${n.id}`]
    int h = resizeUsedH[`${n.id}`]
    if w == null && h == null { return }
    // An important inline declaration, which is the weight a user's own
    // drag deserves: it beats anything the page can have written about
    // this element's size.
    int weight = matchWeight(true, ORIGIN_INLINE, CASCADE_NO_LAYER, 999999, 999999)
    // The dragged rectangle is the border box whatever the element's
    // own `box-sizing` says, so that is declared beside it.
    addMatch(matches, 'box-sizing', 'border-box', weight)
    if w != null { addMatch(matches, 'width', `${w}px`.toAscii(), weight) }
    if h != null { addMatch(matches, 'height', `${h}px`.toAscii(), weight) }
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
    if anyResizeUsed { resizeUsedMatches(n, matches) }
    text inline = getAttr(n, 'style')
    if inline != null {
        ascii ia = inline.toAscii()
        if ia == null { ia = textToAsciiSafeForCss(inline) }
        arr[Decl] decls = parseDeclarations(stripCssComments(ia))
        for int d = 0, d < decls.length, d++ {
            // `anyCounters` and `anyQuotes` are what let these features
            // cost nothing to the pages without them, and they were
            // raised by walking the stylesheet rules -- which an inline
            // declaration is not in. A counter written only in a style
            // attribute was therefore dropped, and its element numbered
            // nothing. Asked here, the question reaches only elements
            // that carry a style attribute, and only until it is
            // answered yes; it is asked before this element's own
            // values are computed, which is what makes the element that
            // raises the flag benefit from it.
            if !anyCounters && (decls[d].name == 'counter-reset'
                || decls[d].name == 'counter-increment'
                || decls[d].name == 'counter-set') { anyCounters = true }
            if !anyQuotes && decls[d].name == 'quotes' { anyQuotes = true }
            if !cascadeSawColorScheme && decls[d].name == 'color-scheme' {
                cascadeSawColorScheme = true
            }
            if !cascadeSawDirection && decls[d].name == 'direction' {
                cascadeSawDirection = true
            }
            if !cascadeSawWritingMode && decls[d].name == 'writing-mode' {
                cascadeSawWritingMode = true
            }
            if !cascadeSawFontSizeAdjust && decls[d].name == 'font-size-adjust' {
                cascadeSawFontSizeAdjust = true
            }
            if !cascadeSawBaselineSource && decls[d].name == 'baseline-source' {
                cascadeSawBaselineSource = true
            }
            if !cascadeSawZoom && decls[d].name == 'zoom' { cascadeSawZoom = true }
            if !cascadeSawResize && decls[d].name == 'resize' { cascadeSawResize = true }
            if !cascadeSawTextWrapStyle && (decls[d].name == 'text-wrap-style'
                || decls[d].name == 'text-wrap') { cascadeSawTextWrapStyle = true }
            if !cascadeSawFontCaps && (decls[d].name == 'font-variant-caps'
                || decls[d].name == 'font-variant' || decls[d].name == 'font') {
                cascadeSawFontCaps = true
            }
            if !cascadeSawPrintColorAdjust && decls[d].name == 'print-color-adjust' {
                cascadeSawPrintColorAdjust = true
            }
            if !cascadeSawRuby && (decls[d].name == 'ruby-position'
                || decls[d].name == 'ruby-align') { cascadeSawRuby = true }
            // `anchor-size()` written only in a style attribute has to
            // raise its flag here too, for the reason above: the
            // stylesheet walk never sees an inline declaration, and the
            // guarded loop would then read none of it. The anchor suite
            // is written that way and said so at once.
            if !cascadeSawAnchorSize || !cascadeSawAnchorInset {
                cascadeNoteAnchorFns(decls[d].value)
            }
            // A style attribute is parsed per element rather than
            // indexed, so this is where its `revert` is noticed -- in
            // time, because the element's own declarations are applied
            // after this runs.
            if !anyRevert && declIsRevert(decls[d].value) { anyRevert = true }
            Match m
            m.decl = decls[d]
            m.weight = matchWeight(decls[d].important, ORIGIN_INLINE, CASCADE_NO_LAYER, 0, d)
            matches.push(m)
        }
    }
    int t0 = archtelosTiming ? now() : 0
    matches.sort(compareMatches)
    if archtelosTiming { profSortMs = profSortMs + (now() - t0) }
    return matches
}

// ---- counters (CSS2 §12.4) -------------------------------------------
//
// A counter is a stack of instances. `counter-reset` on an element
// creates a new instance, in scope for that element, its descendants
// and its following siblings; `counter-increment` adds to the innermost
// instance, creating one on the root if none exists (§12.4.3).
// `counter()` reads the innermost instance and `counters()` joins them
// all, outermost first.
//
// The stack is walked in document order alongside the style computation,
// which already visits elements in that order. It is deliberately not
// part of the computed-style cache: two elements can match exactly the
// same declarations and still stand at different counts, and the cache
// shares a Style between them. What differs is the generated *content*,
// which is resolved per element and stored per node, so the two do not
// collide.

struct CounterInstance {
    name:text
    value:int
    depth:int       // the depth at which counter-reset created it
    // Whether an instance of the same name was already in scope when
    // this one was created. Such an instance is in scope for its
    // element and that element's descendants only; one created where
    // there was none carries on to the element's following siblings,
    // which is what lets a single reset number a list of siblings.
    ownOnly:bool
}

arr[CounterInstance] counterStack = []

void func resetCounters() {
    arr[CounterInstance] empty = []
    counterStack = empty
}

// Drops every instance created at or below `depth`, which happens once
// the parent whose children created them has been left.
void func popCountersBelow(depth:int) {
    int n = counterStack.length
    while n > 0 && counterStack[n - 1].depth >= depth { n-- }
    if n == counterStack.length { return }
    arr[CounterInstance] kept = []
    for int i = 0, i < n, i++ { kept.push(counterStack[i]) }
    counterStack = kept
}

bool func counterInScope(name:text) {
    for int i = counterStack.length - 1, i >= 0, i-- {
        if counterStack[i].name == name { return true }
    }
    return false
}

void func counterReset(name:text, value:int, depth:int) {
    CounterInstance c
    c.name = name
    c.value = value
    c.depth = depth
    c.ownOnly = counterInScope(name)
    counterStack.push(c)
}

// Drops the instances an element created that shadow one already in
// scope, which is done when the element's own subtree is finished.
// Measured against Chromium 141: with `counter-reset: c 11` outside and
// `counter-reset: c 7` on a child, the child reads 7 and the child's
// following sibling reads 11 -- and with no outer reset at all, that
// same sibling reads 7.
void func popShadowingCountersAt(depth:int) {
    bool any = false
    for int i = counterStack.length - 1, i >= 0, i-- {
        if counterStack[i].depth < depth { break }
        if counterStack[i].depth == depth && counterStack[i].ownOnly { any = true  break }
    }
    if !any { return }
    arr[CounterInstance] kept = []
    for int i = 0, i < counterStack.length, i++ {
        if counterStack[i].depth == depth && counterStack[i].ownOnly { continue }
        kept.push(counterStack[i])
    }
    counterStack = kept
}

void func counterIncrement(name:text, by:int, depth:int) {
    for int i = counterStack.length - 1, i >= 0, i-- {
        if counterStack[i].name != name { continue }
        counterStack[i].value = counterStack[i].value + by
        return
    }
    // no instance in scope: the standard creates one on the root
    CounterInstance c
    c.name = name
    c.value = by
    c.depth = 0
    counterStack.push(c)
}

// `counter-set` sets the innermost instance in scope rather than making
// a new one, so the value outlives the element that set it: a following
// sibling sees it, where a `counter-reset` on the same element would
// have made an instance that died with it. With nothing in scope it
// creates one, scoped as a reset would have scoped it (Lists 3 §4.2).
void func counterSet(name:text, value:int, depth:int) {
    for int i = counterStack.length - 1, i >= 0, i-- {
        if counterStack[i].name != name { continue }
        counterStack[i].value = value
        return
    }
    counterReset(name, value, depth)
}

int func counterValue(name:text) {
    for int i = counterStack.length - 1, i >= 0, i-- {
        if counterStack[i].name == name { return counterStack[i].value }
    }
    return 0
}

text func counterValues(name:text, sep:text) {
    arr[text] parts = []
    for int i = 0, i < counterStack.length, i++ {
        if counterStack[i].name == name { parts.push(`${counterStack[i].value}`) }
    }
    if parts.length == 0 { return '0' }
    return parts.join(sep)
}

// `counter-reset: a 2 b` / `counter-increment: x` -- a list of names,
// each optionally followed by an integer.
const int COUNTER_OP_RESET = 0
const int COUNTER_OP_INCREMENT = 1
const int COUNTER_OP_SET = 2

void func applyCounterProperty(v:ascii, depth:int, op:int) {
    if v == null { return }
    ascii t = asciiTrim(v)
    if t == null || t.length == 0 { return }
    if asciiLower(t) == 'none' { return }
    arr[ascii] toks = cssTokens(t)
    int i = 0
    while i < toks.length {
        text name = asciiLower(toks[i]).toText()
        // The value a name takes when it carries none of its own:
        // `counter-increment` steps by one, the other two say zero.
        int value = op == COUNTER_OP_INCREMENT ? 1 : 0
        if i + 1 < toks.length {
            int got = toks[i + 1].toText().toInt()
            if got != null { value = got  i++ }
        }
        if op == COUNTER_OP_RESET { counterReset(name, value, depth) }
        else if op == COUNTER_OP_SET { counterSet(name, value, depth) }
        else { counterIncrement(name, value, depth) }
        i++
    }
}

// ---- generated boxes (CSS2 §12.1) ------------------------------------
//
// `::before` and `::after` describe a box generated inside the element,
// before or after its content. The box exists only when `content`
// computes to something other than `none`, and it inherits from the
// element rather than from the element's parent.
//
// The results live in two maps keyed by `<node id>:b` / `<node id>:a`
// rather than in fields on Node: almost no element has one, and a Style
// field on every node would cost every document for the few that do.
map[Style] pseudoStyles = {}
map[text] pseudoContents = {}

// `content` may interleave strings with url()s, and the boxes they
// generate have to come out in the order they were written, so what a
// pseudo-element carries is a run of pieces rather than one string: for
// piece i, `urls[i]` is the image it names, or null when `parts[i]` is
// the text it contributes.
struct ContentRun {
    parts:arr[text]
    urls:arr[text]
}
map[ContentRun] pseudoContentRuns = {}

// Raised when any resolved `content` named a url. Nothing walks the
// tree for content images, and no generated box asks for one, unless
// some declaration on the page actually has one.
bool anyContentUrl = false

void func resetPseudoElements() {
    map[Style] emptyStyles = {}
    map[text] emptyContents = {}
    map[ContentRun] emptyRuns = {}
    pseudoStyles = emptyStyles
    pseudoContents = emptyContents
    pseudoContentRuns = emptyRuns
    anyContentUrl = false
}

text func pseudoKey(nid:int, which:text) {
    return `${nid}:${which}`
}

// The style rather than the content: an empty `text` reads back as null
// (FINDINGS.md, "an empty text is null"), so a `content` that is
// nothing but a url -- whose text is empty and whose boxes are in its
// run -- would otherwise say the pseudo-element is not there.
bool func hasPseudo(nid:int, which:text) {
    return pseudoStyles[pseudoKey(nid, which)] != null
}

Style func pseudoStyleOf(nid:int, which:text) {
    return pseudoStyles[pseudoKey(nid, which)]
}

text func pseudoContentOf(nid:int, which:text) {
    return pseudoContents[pseudoKey(nid, which)]
}

ContentRun func pseudoContentRunOf(nid:int, which:text) {
    return pseudoContentRuns[pseudoKey(nid, which)]
}

arr[Match] func collectPseudoMatches(n:Node, which:text) {
    arr[Match] matches = []
    collectingPseudo = which
    collectFromBucket(n, '*', matches)
    collectFromBucket(n, n.tag, matches)
    text id = getAttr(n, 'id')
    if id != null { collectFromBucket(n, `#${id}`, matches) }
    arr[text] classes = nodeClasses(n)
    for int i = 0, i < classes.length, i++ {
        collectFromBucket(n, `.${classes[i]}`, matches)
    }
    collectingPseudo = ''
    // an inline style attribute cannot name a pseudo-element, so it is
    // deliberately not consulted here
    matches.sort(compareMatches)
    return matches
}

// `content`: a sequence of strings and attr() references, or `none`.
// Answers null when nothing should be generated.
// The `quotes` list of the element whose generated content is being
// resolved. Festina has no closures and globals are not hoisted, so
// this is set just before resolveContent is called rather than passed
// -- see FINDINGS.md, "one global namespace, and globals are not
// hoisted".
arr[text] contentQuotePairs = []

// resolveContent answers the text a `content` value produces, and a
// value may also name images, so the pieces it saw come back in these
// rather than in the return value -- Festina returns one value from a
// function (see FINDINGS.md, "one value out of a function"). They are
// reset by resolveContent itself, so a caller that ignores them is not
// left holding the previous element's.
arr[text] contentRunParts = []
arr[text] contentRunUrls = []
bool contentRunHasUrl = false
bool contentRunStarted = false

// Splits a `quotes` value into its strings: pairs of open and close,
// outermost first. Anything that is not a quoted string invalidates the
// whole list, which is what makes `quotes: none` produce nothing.
arr[text] func parseQuotePairs(v:ascii) {
    arr[text] out = []
    if v == null { return out }
    ascii t = asciiTrim(v)
    if t == null || t.length == 0 { return out }
    int i = 0
    int len = t.length
    while i < len {
        int c = t.charCodeAt(i)
        if isSpaceCode(c) { i++  continue }
        if c != CH_QUOTE && c != CH_APOS {
            arr[text] empty = []
            return empty
        }
        int close = i + 1
        while close < len && t.charCodeAt(close) != c { close++ }
        if close >= len {
            arr[text] empty = []
            return empty
        }
        text one = t.slice(i + 1, close).toText()
        out.push(one == null ? '' : one)
        i = close + 1
    }
    // An odd number of strings is not a list of pairs.
    if out.length % 2 != 0 {
        arr[text] empty = []
        return empty
    }
    return out
}

// The string for one end of the quote at `depth`. Past the end of the
// list every deeper level repeats the last pair, which is what Chromium
// does and what keeps a runaway nesting from printing nothing.
text func quoteStringAt(pairs:arr[text], depth:int, open:bool) {
    if pairs.length < 2 { return '' }
    int levels = Math.floorDiv(pairs.length, 2)
    int lv = depth
    if lv < 0 { lv = 0 }
    if lv >= levels { lv = levels - 1 }
    return pairs[lv + lv + (open ? 0 : 1)]
}

// One term of a ratio: a number and nothing else after it.
bool func aspectTerm(t:ascii) {
    if t == null || t.length == 0 { return false }
    parseNumberAt(t, 0)
    return numOk && numEnd == t.length
}

// `aspect-ratio: auto || <ratio>`, where a ratio is one number or two
// separated by a slash (Sizing 4 §4). The two terms are kept rather
// than their quotient because a zero on either side is degenerate and
// has to stay tellable from the other: Chromium 141 gives both `0 / 1`
// and `2 / 0` a height of nothing.
//
// The slash is found before anything is split on whitespace, because
// `16 / 9` is the ordinary way to write a ratio and splitting first
// makes the slash a token of its own.
//
// A negative or non-numeric term makes the whole declaration invalid,
// which Chromium reports as a computed `auto`, so nothing is stored and
// the box is sized as it was.
void func applyAspectRatio(s:Style, v:ascii) {
    s.aspectW = 0.0
    s.aspectH = 0.0
    s.hasAspectRatio = false
    s.aspectPrefersNatural = false
    if v == null { return }
    ascii t = asciiLower(asciiTrim(v))
    if t == null || t.length == 0 { return }
    bool sawAuto = false
    if asciiStartsWithLower(t, 'auto', 0) && (t.length == 4 || isSpaceCode(t.charCodeAt(4))) {
        sawAuto = true
        t = asciiTrim(t.slice(4, t.length))
    } else if t.length > 5 && asciiStartsWithLower(t, 'auto', t.length - 4)
              && isSpaceCode(t.charCodeAt(t.length - 5)) {
        sawAuto = true
        t = asciiTrim(t.slice(0, t.length - 4))
    }
    // `auto` on its own: a replaced box already uses its natural ratio
    // and no other box has one, so there is nothing to store.
    if t == null || t.length == 0 { return }
    float w = 0.0
    float h = 1.0
    int slash = asciiIndexOf(t, '/'.toAscii(), 0)
    if slash < 0 {
        if !aspectTerm(t) { return }
        w = numValue
    } else {
        ascii num = asciiTrim(t.slice(0, slash))
        if !aspectTerm(num) { return }
        w = numValue
        ascii den = asciiTrim(t.slice(slash + 1, t.length))
        if !aspectTerm(den) { return }
        h = numValue
    }
    if w < 0.0 || h < 0.0 { return }
    s.aspectW = w
    s.aspectH = h
    s.hasAspectRatio = true
    s.aspectPrefersNatural = sawAuto
}

text func resolveContent(v:ascii, n:Node) {
    // Before the first return, not after it: an element with no
    // `content` at all leaves through the next line, and a run left
    // standing from the element before would be read as this one's.
    // The arrays are not built here: a `content` with no url in it --
    // every one on a page that does not use the feature -- would then
    // allocate two of them per pseudo-element and use neither.
    contentRunHasUrl = false
    contentRunStarted = false
    if v == null { return null }
    ascii t = asciiTrim(v)
    if t == null || t.length == 0 { return null }
    ascii low = asciiLower(t)
    if low == 'none' || low == 'normal' { return null }
    text out = ''
    // What the pieces already closed off contribute, so the value
    // returned is still the whole text however many images split it.
    text closed = ''
    int i = 0
    int len = t.length
    while i < len {
        int c = t.charCodeAt(i)
        if isSpaceCode(c) { i++  continue }
        if c == CH_QUOTE || c == CH_APOS {
            int close = i + 1
            while close < len && t.charCodeAt(close) != c { close++ }
            if close >= len { return null }          // unterminated
            out = out + t.slice(i + 1, close).toText()
            i = close + 1
            continue
        }
        if asciiStartsWithLower(t, 'no-open-quote', i) {
            quoteDepth++
            i = i + 13
            continue
        }
        if asciiStartsWithLower(t, 'no-close-quote', i) {
            if quoteDepth > 0 { quoteDepth-- }
            i = i + 14
            continue
        }
        if asciiStartsWithLower(t, 'open-quote', i) {
            out = out + quoteStringAt(contentQuotePairs, quoteDepth, true)
            quoteDepth++
            i = i + 10
            continue
        }
        if asciiStartsWithLower(t, 'close-quote', i) {
            // The level comes back up first, so an open and a close at
            // the same level print the two halves of one pair. Closing
            // what was never opened prints nothing at all and leaves
            // the level where it was -- measured against Chromium 141,
            // which renders no characters for it.
            if quoteDepth > 0 {
                quoteDepth--
                out = out + quoteStringAt(contentQuotePairs, quoteDepth, false)
            }
            i = i + 11
            continue
        }
        if asciiStartsWithLower(t, 'attr(', i) {
            int close = asciiIndexOf(t, ')'.toAscii(), i)
            if close < 0 { return null }
            text name = asciiLower(asciiTrim(t.slice(i + 5, close))).toText()
            text got = getAttr(n, name)
            out = out + (got == null ? '' : got)
            i = close + 1
            continue
        }
        if asciiStartsWithLower(t, 'counters(', i) {
            int close = asciiIndexOf(t, ')'.toAscii(), i)
            if close < 0 { return null }
            arr[ascii] args = splitTopLevelCommas(t.slice(i + 9, close))
            if args.length < 2 { return null }
            text name = asciiLower(asciiTrim(args[0])).toText()
            ascii sepRaw = asciiTrim(args[1])
            if sepRaw.length < 2 { return null }
            int q = sepRaw.charCodeAt(0)
            if q != CH_QUOTE && q != CH_APOS { return null }
            text sep = sepRaw.slice(1, sepRaw.length - 1).toText()
            if sep == null { sep = '' }
            out = out + counterValues(name, sep)
            i = close + 1
            continue
        }
        if asciiStartsWithLower(t, 'counter(', i) {
            int close = asciiIndexOf(t, ')'.toAscii(), i)
            if close < 0 { return null }
            arr[ascii] args = splitTopLevelCommas(t.slice(i + 8, close))
            if args.length < 1 { return null }
            text name = asciiLower(asciiTrim(args[0])).toText()
            // a list style as the second argument is not implemented;
            // only decimal is produced (todo.md, Counter Styles 3)
            out = out + `${counterValue(name)}`
            i = close + 1
            continue
        }
        if asciiStartsWithLower(t, 'url(', i) {
            int close = asciiIndexOf(t, ')'.toAscii(), i)
            if close < 0 { return null }
            ascii raw = asciiTrim(t.slice(i + 4, close))
            if raw.length >= 2 {
                int q = raw.charCodeAt(0)
                if q == CH_QUOTE || q == CH_APOS {
                    if raw.charCodeAt(raw.length - 1) != q { return null }
                    raw = raw.slice(1, raw.length - 1)
                }
            }
            if raw.length == 0 { return null }
            if !contentRunStarted {
                arr[text] runParts = []
                arr[text] runUrls = []
                contentRunParts = runParts
                contentRunUrls = runUrls
                contentRunStarted = true
            }
            // The text written so far closes its own piece, so that the
            // image lands between the strings either side of it.
            contentRunParts.push(out)
            contentRunUrls.push(null)
            contentRunParts.push('')
            contentRunUrls.push(raw.toText())
            closed = closed + out
            out = ''
            i = close + 1
            continue
        }
        // an unrecognized component makes the whole value invalid
        // rather than silently dropping part of it
        return null
    }
    // Only a value that parsed all the way through has a run: an
    // invalid component returns null above, and the flag stays down so
    // the pieces already pushed are never used.
    if contentRunStarted {
        contentRunParts.push(out)
        contentRunUrls.push(null)
        contentRunHasUrl = true
        return closed + out
    }
    return out
}

void func computePseudoFor(n:Node, own:Style, which:text) {
    arr[Match] matches = collectPseudoMatches(n, which)
    if matches.length == 0 { return }
    map[text] props = {}
    cascadeApplyRtl = cascadeSawDirection && matchedDirectionRtl(matches, own.directionRtl)
    cascadeApplyWM = cascadeSawWritingMode ? matchedWritingMode(matches, own.writingMode) : 0
    applyMatches(props, matches)
    // open-quote and close-quote read the element's own `quotes` list,
    // and move a document-wide depth as a side effect, so the list has
    // to be in place before the value is resolved.
    arr[text] noQuotes = []
    contentQuotePairs = noQuotes
    if anyQuotes { contentQuotePairs = parseQuotePairs(own.quotes.toAscii()) }
    text content = resolveContent(styleProp(props, 'content'), n)
    // An empty `text` is null (FINDINGS.md, finding 4), so a content
    // made only of images has to be recognized by its run.
    if content == null && !contentRunHasUrl { return }
    // a generated box inherits from the element it is generated in
    Style s = computeStyleValues(n, own, false, props)
    pseudoStyles[pseudoKey(n.id, which)] = s
    pseudoContents[pseudoKey(n.id, which)] = content
    if contentRunHasUrl {
        ContentRun run
        run.parts = contentRunParts
        run.urls = contentRunUrls
        pseudoContentRuns[pseudoKey(n.id, which)] = run
        anyContentUrl = true
    }
}

// `initial-letter: normal | <number> <integer>?`. The size is a
// baseline rather than a multiplier: the letter's cap top is the cap
// top of the first line and its baseline is the baseline of line
// `size`, so its cap height is `cap(1) + (size - 1) * line-height` and
// its font size follows from that. The sink defaults to the size
// rounded down. All of it is measured, in todo.md.
//
// The size is applied to the pseudo-element's own style here rather
// than in layout, because this is where the paragraph's font size and
// line height are both to hand and where the style is made.
void func applyInitialLetter(ps:Style, own:Style, v:ascii) {
    ascii low = asciiLower(asciiTrim(v))
    if low == 'normal' { return }
    arr[ascii] w = asciiSplitSpace(low)
    if w.length == 0 || w.length > 2 { return }
    float size = parseFloatAscii(w[0])
    if size <= 1.0 { return }
    int sink = Math.floor(size)
    if w.length > 1 {
        int asked = Math.floor(parseFloatAscii(w[1]))
        if asked < 1 { return }
        sink = asked
    }
    if sink < 1 || sink > 63 { return }
    int lh = lineHeightOf(own)
    float cap = FONT_CAP * own.fontSize.toFloat() + (size - 1.0) * lh.toFloat()
    int scaled = roundPx(cap / FONT_CAP)
    if scaled <= 0 { return }
    ps.fontSize = scaled
    refreshFontKey(ps)
    // The letter's own line box is as tall as it spans, which puts its
    // baseline on the baseline of line `size` by the same arithmetic
    // that centres any other inline in its line: the half-leading is
    // negative here and the sum comes out exactly right.
    ps.lineHeight = roundPx(size * lh.toFloat())
    ps.floatSide = FLOAT_LEFT
    initialLetterOf[`${ps.serial}`] = roundPx(size * 100.0) * 64 + sink
    anyInitialLetter = true
}

// ::first-letter carries no `content`: it restyles characters that are
// already there, so the style is kept on its own without one.
void func computeFirstLetterFor(n:Node, own:Style) {
    arr[Match] matches = collectPseudoMatches(n, 'first-letter')
    if matches.length == 0 { return }
    map[text] props = {}
    cascadeApplyRtl = cascadeSawDirection && matchedDirectionRtl(matches, own.directionRtl)
    cascadeApplyWM = cascadeSawWritingMode ? matchedWritingMode(matches, own.writingMode) : 0
    applyMatches(props, matches)
    Style ps = computeStyleValues(n, own, false, props)
    ascii il = styleProp(props, 'initial-letter')
    if il != null { applyInitialLetter(ps, own, il) }
    pseudoStyles[pseudoKey(n.id, 'first-letter')] = ps
    pseudoHasFirstLetter[pseudoKey(n.id, 'first-letter')] = true
}

// `::placeholder` restyles text that is already there, as
// `::first-letter` does, and carries no `content`.
//
// It is computed **on demand**, from the one place in layout that
// builds a control's text box, rather than in the style pass beside the
// other pseudo-elements. Every other one applies to elements a document
// has many of, so the style pass is where they belong; this one applies
// only to an `<input>` that is showing its placeholder, and layout is
// the only code that knows which those are. A document with no such
// input never calls this, so it costs nothing to ask.
//
// The user agent's stylesheet declares the grey on the pseudo-element
// itself (ua.f), which is what stops the input's own `color` reaching
// it: an inherited value loses to any declaration, whatever origin the
// declaration comes from. Measured in Chromium (todo.md).
Style func placeholderStyleFor(n:Node, own:Style) {
    arr[Match] matches = collectPseudoMatches(n, 'placeholder')
    if matches.length == 0 { return own }
    map[text] props = {}
    cascadeApplyRtl = cascadeSawDirection && matchedDirectionRtl(matches, own.directionRtl)
    cascadeApplyWM = cascadeSawWritingMode ? matchedWritingMode(matches, own.writingMode) : 0
    applyMatches(props, matches)
    // Through the ordinary sharing cache, because the same reasoning
    // holds: two placeholders that matched the same declarations in the
    // same order under the same parent style compute the same style, and
    // a form full of them matches the same one rule every time. Building
    // a `Style` each was two thirds of what this cost the page that has
    // them (benchmarks.md).
    collectingPseudoKey = 'placeholder'
    text key = styleCacheKey(n, own, false, matches)
    collectingPseudoKey = ''
    Style cached = styleCache[key]
    if cached != null { return cached }
    Style s = computeStyleValues(n, own, false, props)
    styleCache[key] = s
    return s
}

// ::first-line restyles the characters that fall on the first line,
// which is not known until the line has been broken -- so what is kept
// here is the style, and the layout decides who wears it.
void func computeFirstLineFor(n:Node, own:Style) {
    arr[Match] matches = collectPseudoMatches(n, 'first-line')
    if matches.length == 0 { return }
    map[text] props = {}
    cascadeApplyRtl = cascadeSawDirection && matchedDirectionRtl(matches, own.directionRtl)
    cascadeApplyWM = cascadeSawWritingMode ? matchedWritingMode(matches, own.writingMode) : 0
    applyMatches(props, matches)
    pseudoStyles[pseudoKey(n.id, 'first-line')] = computeStyleValues(n, own, false, props)
    pseudoHasFirstLine[pseudoKey(n.id, 'first-line')] = true
}

// Gives every node in `n`'s inline subtree the style it wears while it
// is on the first line: what it computes to under the fictional
// ::first-line element, which is `parent` here. A block-level
// descendant starts a first line of its own, so the walk stops there
// rather than dressing its content in this block's rule.
//
// Runs after the subtree has its ordinary styles, because the stop
// condition is a computed display. The style cache keys on the parent's
// serial, so the second walk shares nothing with the first by accident
// and computes each descendant once.
void func computeFirstLineSubtree(n:Node, parent:Style) {
    for int i = 0, i < n.children.length, i++ {
        Node c = n.children[i]
        if c.kind == NODE_TEXT {
            firstLineStyles[`${c.id}`] = parent
            continue
        }
        if c.kind != NODE_ELEMENT || c.style == null { continue }
        // Only a non-replaced inline is part of the line. A block-level
        // child begins a first line of its own, and an atomic inline --
        // an inline-block, say -- lays its content out on its own lines,
        // which this rule does not reach either.
        int d = c.style.display
        if d != DISPLAY_INLINE && d != DISPLAY_CONTENTS { continue }
        Style s = computeStyle(c, parent, false)
        firstLineStyles[`${c.id}`] = s
        computeFirstLineSubtree(c, s)
    }
}

void func computeFirstLineStyles(n:Node) {
    if !anyFirstLine { return }
    if n.id <= 0 { return }
    if pseudoHasFirstLine[pseudoKey(n.id, 'first-line')] == null { return }
    Style ps = pseudoStyleOf(n.id, 'first-line')
    // The block itself wears it too, which is what gives the first line
    // its strut when the rule only sets a line height.
    firstLineStyles[`${n.id}`] = ps
    computeFirstLineSubtree(n, ps)
}

// ::marker styles a list item's marker (CSS Lists 3 §3). Like
// ::first-letter it restyles something already there, so an empty rule
// is still a rule -- but unlike it, a `content` replaces what the marker
// says, so the string is kept beside the style.
void func computeMarkerFor(n:Node, own:Style) {
    arr[Match] matches = collectPseudoMatches(n, 'marker')
    if matches.length == 0 { return }
    map[text] props = {}
    cascadeApplyRtl = cascadeSawDirection && matchedDirectionRtl(matches, own.directionRtl)
    cascadeApplyWM = cascadeSawWritingMode ? matchedWritingMode(matches, own.writingMode) : 0
    applyMatches(props, matches)
    arr[text] noQuotes = []
    contentQuotePairs = noQuotes
    if anyQuotes { contentQuotePairs = parseQuotePairs(own.quotes.toAscii()) }
    text content = resolveContent(styleProp(props, 'content'), n)
    pseudoStyles[pseudoKey(n.id, 'marker')] = computeStyleValues(n, own, false, props)
    if content != null { pseudoContents[pseudoKey(n.id, 'marker')] = content }
    pseudoHasMarker[pseudoKey(n.id, 'marker')] = true
}

void func computePseudoElements(n:Node, own:Style) {
    if !anyPseudoRules { return }
    // One map lookup rules out every element no pseudo rule names,
    // which is all of them on a page whose only such rule is the user
    // agent's own q::before.
    if !pseudoNonTag && pseudoTagSet[n.tag] == null { return }
    computePseudoFor(n, own, 'before')
    computePseudoFor(n, own, 'after')
    if anyFirstLetter { computeFirstLetterFor(n, own) }
    if anyFirstLine { computeFirstLineFor(n, own) }
    if anyMarker { computeMarkerFor(n, own) }
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

// ---- one background layer's worth of each longhand -------------------
// Every background longhand is a comma-separated list, one value per
// layer (Backgrounds and Borders 3 §3.10), and a list shorter than the
// image list repeats from its start. These take a value already chosen
// for a layer, so the first layer and the rest go through the same
// code and cannot drift apart.
//
// The shared empty list of extra layers: nothing writes to it, and it
// is what almost every style keeps.
arr[BgLayer] bgNoLayers = []

ascii func layerValue(v:ascii, i:int) {
    if v == null { return null }
    arr[ascii] parts = splitTopLevelCommas(v)
    if parts.length == 0 { return null }
    // Copied rather than aliased: the slices point into a local that is
    // gone when this returns (FINDINGS.md, "ascii aliases are not
    // retained").
    return dup(asciiTrim(parts[i % parts.length]))
}

// The two axes of background-repeat. Out-parameters because a Festina
// function returns one value (FINDINGS.md, "one value out of a
// function").
bool bgRepeatXOut = true
bool bgRepeatYOut = true

void func parseBgRepeat(v:ascii) {
    bgRepeatXOut = true
    bgRepeatYOut = true
    if v == null { return }
    // The lowered string is held in a local and its words indexed
    // rather than bound (FINDINGS.md, "ascii aliases are not retained").
    ascii low = asciiLower(v)
    arr[ascii] parts = asciiSplitSpace(low)
    if parts.length == 1 {
        if parts[0] == 'no-repeat' { bgRepeatXOut = false  bgRepeatYOut = false }
        else if parts[0] == 'repeat-x' { bgRepeatYOut = false }
        else if parts[0] == 'repeat-y' { bgRepeatXOut = false }
    } else if parts.length >= 2 {
        bgRepeatXOut = parts[0] != 'no-repeat'
        bgRepeatYOut = parts[1] != 'no-repeat'
    }
}

int bgSizeKindOut = BGSIZE_AUTO
Len bgSizeWOut = lenAuto()
Len bgSizeHOut = lenAuto()

void func parseBgSize(v:ascii, fontSize:int) {
    bgSizeKindOut = BGSIZE_AUTO
    bgSizeWOut = lenAuto()
    bgSizeHOut = lenAuto()
    if v == null { return }
    ascii low = asciiLower(v)
    arr[ascii] parts = asciiSplitSpace(low)
    if parts.length == 0 { return }
    if parts[0] == 'cover' { bgSizeKindOut = BGSIZE_COVER  return }
    if parts[0] == 'contain' { bgSizeKindOut = BGSIZE_CONTAIN  return }
    Len sw = parseLength(parts[0], fontSize)
    // One value gives the width and leaves the height `auto`, which
    // takes its size from the image's own ratio.
    Len sh = lenAuto()
    if parts.length >= 2 { sh = parseLength(parts[1], fontSize) }
    if sw.kind == LEN_PX || sw.kind == LEN_PERCENT || sh.kind == LEN_PX || sh.kind == LEN_PERCENT {
        bgSizeKindOut = BGSIZE_EXPLICIT
        bgSizeWOut = sw
        bgSizeHOut = sh
    }
}

int func parseBgClip(v:ascii) {
    if v == null { return BGCLIP_BORDER }
    ascii low = asciiLower(asciiTrim(v))
    if low == 'padding-box' { return BGCLIP_PADDING }
    if low == 'content-box' { return BGCLIP_CONTENT }
    return BGCLIP_BORDER
}

int func parseBgOrigin(v:ascii) {
    if v == null { return BGORIGIN_PADDING }
    ascii low = asciiLower(asciiTrim(v))
    if low == 'border-box' { return BGORIGIN_BORDER }
    if low == 'content-box' { return BGORIGIN_CONTENT }
    return BGORIGIN_PADDING
}

// The two axes of one layer's position. Out-parameters, because a
// Festina function returns one value (FINDINGS.md). Declared here
// rather than beside `splitBackgroundPosition`, which is four thousand
// lines below, because the mask reader uses them and globals are not
// hoisted (FINDINGS.md, finding 9).
text bgPosXOut = ''
text bgPosYOut = ''

// ---- CSS Masking 1: the mask layer ------------------------------------
//
// `mask-*` is `background-*` with the result used as alpha, so the
// geometry is read with the background readers rather than a second
// copy of the same five questions. Two of the initial values differ and
// both were measured rather than read off: `mask-origin` is the BORDER
// box, where `background-origin` is the padding box, and `mask-clip` is
// the border box like `background-clip`.
//
// Every gradient is painted -- linear, radial and conic -- each with its
// own projection from a pixel to the gradient's parameter. A `url()`
// mask is not: it needs that image's own alpha per pixel, which is
// FINDINGS.md finding 35, the same block that leaves a bitmap image
// unfiltered. A mask this engine cannot paint leaves `maskIdx`
// negative, so the element renders unmasked rather than half-masked.
// One mask layer's geometry and mode, read with the background readers.
void func maskOneLayer(spec:MaskSpec, props:map[text], i:int,
                       currentColor:int, fontSize:int) {
    BgLayer l
    l.url = null
    l.fadeUrl = null
    l.fade = 0.0 - 1.0
    Gradient g
    g.present = false
    ascii mi = styleProp(props, 'mask-image')
    if mi != null {
        ascii one = asciiTrim(layerValue(mi, i))
        if one != null && one.length > 0 && asciiLower(one) != 'none' {
            g = parseGradient(one, currentColor, fontSize)
        }
    }
    l.image = g
    parseBgRepeat(layerValue(styleProp(props, 'mask-repeat'), i))
    l.repeatX = bgRepeatXOut
    l.repeatY = bgRepeatYOut
    // CSS Masking 1 has no `mask-position-x`/`-y`, so the two axes are
    // split here rather than read as longhands the way a background's
    // are.
    ascii mp = layerValue(styleProp(props, 'mask-position'), i)
    l.posX = lenPercent(0.0)
    l.posY = lenPercent(0.0)
    if mp != null {
        splitBackgroundPosition(mp)
        if bgPosXOut != '' {
            l.posX = parsePositionAxis(asciiLower(bgPosXOut.toAscii()), true, fontSize)
            l.posY = parsePositionAxis(asciiLower(bgPosYOut.toAscii()), false, fontSize)
        }
    }
    parseBgSize(layerValue(styleProp(props, 'mask-size'), i), fontSize)
    l.sizeKind = bgSizeKindOut
    l.sizeW = bgSizeWOut
    l.sizeH = bgSizeHOut
    ascii clip = layerValue(styleProp(props, 'mask-clip'), i)
    l.clip = clip == null ? BGCLIP_BORDER : parseBgClip(clip)
    // The one initial value that is not the background's: the border
    // box, measured against Chromium (todo.md).
    ascii orig = layerValue(styleProp(props, 'mask-origin'), i)
    l.origin = orig == null ? BGORIGIN_BORDER : parseBgOrigin(orig)
    l.fixed = false
    spec.layers.push(l)

    int mode = MASKMODE_MATCH
    ascii md = layerValue(styleProp(props, 'mask-mode'), i)
    if md != null {
        ascii m = asciiLower(asciiTrim(md))
        if m == 'alpha' { mode = MASKMODE_ALPHA }
        else if m == 'luminance' { mode = MASKMODE_LUMINANCE }
    }
    spec.modes.push(mode)

    int op = MASKOP_ADD
    ascii co = layerValue(styleProp(props, 'mask-composite'), i)
    if co != null {
        ascii c = asciiLower(asciiTrim(co))
        if c == 'subtract' { op = MASKOP_SUBTRACT }
        else if c == 'intersect' { op = MASKOP_INTERSECT }
        else if c == 'exclude' { op = MASKOP_EXCLUDE }
    }
    spec.composites.push(op)
}

bool func anyMaskGeometry(props:map[text]) {
    return styleProp(props, 'mask-mode') != null
        || styleProp(props, 'mask-repeat') != null
        || styleProp(props, 'mask-position') != null
        || styleProp(props, 'mask-size') != null
        || styleProp(props, 'mask-origin') != null
        || styleProp(props, 'mask-clip') != null
        || styleProp(props, 'mask-composite') != null
}

// How many comma-separated layers the longhands between them describe.
// `mask-image` decides it, as the background's image list does; a
// shorter list on another longhand repeats, which is what `layerValue`
// already does.
int func maskLayerCount(props:map[text]) {
    ascii mi = styleProp(props, 'mask-image')
    if mi == null { return 1 }
    return splitTopLevelCommas(mi).length
}

// Every gradient is painted -- linear, radial and conic -- each with its
// own projection from a pixel to the gradient's parameter. A `url()`
// mask is not: it needs that image's own alpha per pixel, which is
// FINDINGS.md finding 35, the same block that leaves a bitmap image
// unfiltered. A mask this engine cannot paint leaves `maskIdx`
// negative, so the element renders unmasked rather than half-masked.
int func parseMaskLayer(props:map[text], currentColor:int, fontSize:int) {
    MaskSpec spec
    spec.layers = []
    spec.modes = []
    spec.composites = []
    int n = maskLayerCount(props)
    if n < 1 { n = 1 }
    for int i = 0, i < n, i++ {
        maskOneLayer(spec, props, i, currentColor, fontSize)
    }
    bool paintable = false
    for int i = 0, i < spec.layers.length, i++ {
        if spec.layers[i].image.present { paintable = true }
    }
    spec.paintable = paintable
    // An unpaintable image with no geometry beside it leaves nothing to
    // store: the engine throws the image away, so a computed style that
    // recorded it would be claiming a value nothing reads.
    if !paintable && !anyMaskGeometry(props) { return 0 }
    maskSpecs.push(spec)
    return paintable ? maskSpecs.length : 0 - maskSpecs.length
}

// Everything but the image itself, for one layer past the first.
void func bgLayerProps(l:BgLayer, props:map[text], i:int, fontSize:int) {
    parseBgRepeat(layerValue(styleProp(props, 'background-repeat'), i))
    l.repeatX = bgRepeatXOut
    l.repeatY = bgRepeatYOut
    ascii px = layerValue(styleProp(props, 'background-position-x'), i)
    ascii py = layerValue(styleProp(props, 'background-position-y'), i)
    l.posX = px == null ? lenPercent(0.0) : parsePositionAxis(asciiLower(px), true, fontSize)
    l.posY = py == null ? lenPercent(0.0) : parsePositionAxis(asciiLower(py), false, fontSize)
    parseBgSize(layerValue(styleProp(props, 'background-size'), i), fontSize)
    l.sizeKind = bgSizeKindOut
    l.sizeW = bgSizeWOut
    l.sizeH = bgSizeHOut
    ascii clip = layerValue(styleProp(props, 'background-clip'), i)
    l.clip = clip == null ? BGCLIP_BORDER : parseBgClip(clip)
    ascii orig = layerValue(styleProp(props, 'background-origin'), i)
    l.origin = orig == null ? BGORIGIN_PADDING : parseBgOrigin(orig)
    ascii att = layerValue(styleProp(props, 'background-attachment'), i)
    l.fixed = att != null && asciiLower(asciiTrim(att)) == 'fixed'
}

// ---- applying declarations (shorthand expansion) -------------------

void func setProp(props:map[text], name:text, value:ascii) {
    props[name] = value.toText()
}

// Reads a property back as a fresh ascii (null when absent). The map
// holds text because a text local made from a map entry is a private
// copy, where an ascii one would alias the entry (FINDINGS.md).
// The custom properties in scope while one element's style is computed.
// A global for the same reason cascadeParentStyle is one.
map[text] cascadeCustom = {}

// Replaces every var(--name[, fallback]) in a value. A custom property
// may itself use var(), so this runs until nothing changes, with a
// small bound: the standard makes a cycle invalid and this is how that
// shows up here.
const int VAR_MAX_PASSES = 8

// The needle every property read scans for, built once. `'var('.toAscii()`
// inside styleProp allocated a fresh four-byte ascii on every read of
// every property of every element.
ascii varNeedle = 'var('.toAscii()

ascii func substituteVars(v:ascii) {
    // Work on a copy this function owns. `out` is reassigned every time
    // a var() is replaced, and reassigning an alias of the caller's
    // value releases the caller's buffer -- valgrind caught exactly
    // that as an invalid read in festina_ascii_release
    // (FINDINGS.md, "ascii aliasing").
    text own = v.length > 0 ? v.toText() : ''
    if own == null || own == '' { return null }
    ascii out = own.toAscii()
    if out == null { return null }
    for int pass = 0, pass < VAR_MAX_PASSES, pass++ {
        int at = asciiIndexOfLower(out, varNeedle, 0)
        if at < 0 { return out }
        // find the matching close paren
        int depth = 0
        int end = -1
        for int i = at + 3, i < out.length, i++ {
            int c = out.charCodeAt(i)
            if c == CH_LPAREN { depth++ }
            else if c == CH_RPAREN {
                depth--
                if depth == 0 { end = i  break }
            }
        }
        if end < 0 { return null }
        // Indices into `out`, never into a slice of it: an ascii that
        // came out of slice()/asciiTrim() is an alias, and taking a
        // second slice from one is the aliasing hazard in FINDINGS.md.
        // Doing it here cost an out-of-memory in asciiTrim.
        int argStart = at + 4
        int comma = -1
        for int i = argStart, i < end, i++ {
            if out.charCodeAt(i) == CH_COMMA { comma = i  break }
        }
        ascii name = asciiTrim(out.slice(argStart, comma >= 0 ? comma : end))
        ascii fallback = comma >= 0 ? asciiTrim(out.slice(comma + 1, end)) : null
        text got = cascadeCustom[name.toText()]
        ascii rep = got != null ? got.toAscii() : fallback
        // An unresolvable var() with no fallback makes the declaration
        // invalid at computed-value time, not merely empty.
        if rep == null { return null }
        // An empty ascii and null are one value, so a slice that came
        // out empty cannot go through toText() (FINDINGS.md, "empty
        // text"); the guards keep the pieces as text throughout.
        text head = at > 0 ? out.slice(0, at).toText() : ''
        text mid = rep.length > 0 ? rep.toText() : ''
        text tail = end + 1 < out.length ? out.slice(end + 1, out.length).toText() : ''
        if head == null { head = '' }
        if mid == null { mid = '' }
        if tail == null { tail = '' }
        text joined = `${head}${mid}${tail}`
        if joined == null || joined == '' { return null }
        out = joined.toAscii()
        if out == null { return null }
    }
    return null
}

ascii func styleProp(props:map[text], name:text) {
    profPropReads++
    text v = props[name]
    if v == null { return null }
    ascii a = v.toAscii()
    if a == null { return null }
    if asciiIndexOfLower(a, varNeedle, 0) < 0 { return a }
    return substituteVars(a)
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
// `inset` is the shorthand for the four inset properties, taking the
// same one-to-four-value form the margin shorthand does.
void func applyFourSidesInset(props:map[text], value:ascii) {
    arr[ascii] t = cssTokens(value)
    if t.length == 0 { return }
    ascii top = dup(t[0])
    ascii right = dup(t.length > 1 ? t[1] : t[0])
    ascii bottom = dup(t.length > 2 ? t[2] : t[0])
    ascii left = dup(t.length > 3 ? t[3] : (t.length > 1 ? t[1] : t[0]))
    setProp(props, 'top', top)
    setProp(props, 'right', right)
    setProp(props, 'bottom', bottom)
    setProp(props, 'left', left)
}

void func applyBorderShorthand(props:map[text], sides:arr[text], value:ascii) {
    if declIsCssWide(value) {
        for int i = 0, i < sides.length, i++ {
            props['border-' + sides[i] + '-width'] = dup(value)
            props['border-' + sides[i] + '-style'] = dup(value)
            props['border-' + sides[i] + '-color'] = dup(value)
        }
        return
    }
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
    if declIsCssWide(value) {
        props['font-style'] = dup(value)
        props['font-weight'] = dup(value)
        props['font-size'] = dup(value)
        props['line-height'] = dup(value)
        props['font-family'] = dup(value)
        return
    }
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

// ---- gradients (CSS Images 3) ----------------------------------------
//
// `linear-gradient([<angle> | to <side-or-corner>,]? <stop>#)`. The
// angle is degrees clockwise from pointing up, which is what the
// standard says and what makes `to bottom` 180 and `to right` 90.

// Splits on top-level commas, so a comma inside rgb(...) stays put.
arr[ascii] func splitTopLevelCommas(v:ascii) {
    arr[ascii] out = []
    int n = v.length
    int depth = 0
    int start = 0
    int i = 0
    while i < n {
        int c = v.charCodeAt(i)
        if c == CH_QUOTE || c == CH_APOS { i = skipQuoted(v, i)  continue }
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN { depth-- }
        else if c == CH_COMMA && depth <= 0 {
            out.push(asciiTrim(v.slice(start, i)))
            start = i + 1
        }
        i++
    }
    if start < n { out.push(asciiTrim(v.slice(start, n))) }
    return out
}

// `to right`, `to bottom left`, `45deg`, `0.5turn`. Returns -1 when the
// text is not a direction at all, which is how the caller knows the
// first component was a colour stop instead.
float func parseGradientDirection(t:ascii) {
    ascii low = asciiLower(asciiTrim(t))
    if low == null || low.length == 0 { return -1.0 }
    if asciiStartsWithLower(low, 'to ', 0) {
        bool top = asciiIndexOf(low, 'top'.toAscii(), 0) >= 0
        bool bottom = asciiIndexOf(low, 'bottom'.toAscii(), 0) >= 0
        bool left = asciiIndexOf(low, 'left'.toAscii(), 0) >= 0
        bool right = asciiIndexOf(low, 'right'.toAscii(), 0) >= 0
        if top && left { return 315.0 }
        if top && right { return 45.0 }
        if bottom && left { return 225.0 }
        if bottom && right { return 135.0 }
        if top { return 0.0 }
        if right { return 90.0 }
        if bottom { return 180.0 }
        if left { return 270.0 }
        return -1.0
    }
    parseNumberAt(low, 0)
    if !numOk { return -1.0 }
    ascii unit = asciiLower(asciiTrim(low.slice(numEnd, low.length)))
    if unit == 'deg' { return numValue }
    if unit == 'turn' { return numValue * 360.0 }
    if unit == 'rad' { return numValue * 180.0 / 3.14159265358979 }
    if unit == 'grad' { return numValue * 0.9 }
    return -1.0
}

// One `<color> <position>?` stop. The position comes back as -1 when it
// was not given, so the caller can space those evenly as the standard
// requires.
int gradStopColor = COLOR_UNSET
int gradStopKind = GSTOP_AUTO
float gradStopVal = 0.0

// A conic gradient's stop positions are angles rather than distances,
// and a percentage there is a fraction of the whole turn. Both come out
// as a fraction of the sweep, which is what the stop machinery already
// means by GSTOP_PERCENT -- so the painter needs to know nothing about
// the difference.
// One stop position, into gradStopKind and gradStopVal. Along a line it
// is a length or a percentage of the line; around a sweep it is an
// angle or a percentage of the turn, and both come out as a fraction,
// which is what GSTOP_PERCENT means either way. False for anything that
// is not a position at all.
bool func parseGradientPosition(p:ascii, conic:bool, fontSize:int) {
    gradStopKind = GSTOP_AUTO
    gradStopVal = 0.0
    if p == null || p.length == 0 { return false }
    if p.charCodeAt(p.length - 1) == CH_PERCENT {
        parseNumberAt(p, 0)
        if !numOk { return false }
        gradStopKind = GSTOP_PERCENT
        gradStopVal = numValue / 100.0
        return true
    }
    if conic {
        arr[bool] ok = [false]
        float deg = parseAngleDegrees(p, ok)
        if !ok[0] { return false }
        gradStopKind = GSTOP_PERCENT
        gradStopVal = deg / 360.0
        return true
    }
    // a length: resolved the way every other length is, the pixels kept
    // for the painter, which is the only thing that knows how long the
    // line turned out to be
    Len l = parseLength(p, fontSize)
    if l.kind != LEN_PX { return false }
    gradStopKind = GSTOP_PX
    gradStopVal = l.v
    return true
}

void func parseConicStop(t:ascii, currentColor:int, fontSize:int) {
    gradStopColor = COLOR_UNSET
    gradStopKind = GSTOP_AUTO
    gradStopVal = 0.0
    arr[ascii] parts = cssTokens(t)
    if parts.length == 0 { return }
    gradStopColor = parseCssColor(parts[0], currentColor)
    if parts.length > 1 { parseGradientPosition(asciiTrim(parts[1]), true, fontSize) }
}

void func parseGradientStop(t:ascii, currentColor:int, fontSize:int) {
    gradStopColor = COLOR_UNSET
    gradStopKind = GSTOP_AUTO
    gradStopVal = 0.0
    arr[ascii] parts = cssTokens(t)
    if parts.length == 0 { return }
    gradStopColor = parseCssColor(parts[0], currentColor)
    if parts.length > 1 {
        ascii p = asciiTrim(parts[1])
        parseNumberAt(p, 0)
        if numOk {
            ascii unit = asciiLower(asciiTrim(p.slice(numEnd, p.length)))
            if unit == '%' {
                gradStopKind = GSTOP_PERCENT
                gradStopVal = numValue / 100.0
            } else {
                // a length: resolve it the way every other length is
                // resolved, then keep the pixels for the painter
                Len l = parseLength(p, fontSize)
                if l.kind == LEN_PX {
                    gradStopKind = GSTOP_PX
                    gradStopVal = l.v
                }
            }
        }
    }
}

// Parses a whole `linear-gradient(...)` / `repeating-linear-gradient(...)`
// value. An unparseable one comes back with present = false, which makes
// the declaration do nothing, as an invalid value should.
// The `[ <shape> || <size> ]? [ at <position> ]?` that may precede a
// radial gradient's stops. Everything in it is optional, and what is
// absent keeps the initial value -- an ellipse reaching the farthest
// corner, centred. Returns false when the component is not a prelude at
// all, which is how the caller learns the first component was a stop.
bool radPreludeCircle = false
int radPreludeExtent = RADEXT_FARTHEST_CORNER
Len radPreludeRx = lenAuto()
Len radPreludeRy = lenAuto()
Len radPreludePosX = lenPercent(50.0)
Len radPreludePosY = lenPercent(50.0)

// The `[ from <angle> ]? [ at <position> ]?` that may precede a conic
// gradient's stops. Both are optional; what is absent keeps the initial
// value -- a sweep starting straight up, centred. Returns false when the
// component is not a prelude at all, which is how the caller learns the
// first component was a colour stop.
float conicPreludeFrom = 0.0
Len conicPreludePosX = lenPercent(50.0)
Len conicPreludePosY = lenPercent(50.0)

bool func parseConicPrelude(t:ascii, fontSize:int) {
    conicPreludeFrom = 0.0
    conicPreludePosX = lenPercent(50.0)
    conicPreludePosY = lenPercent(50.0)
    ascii low = asciiLower(asciiTrim(t))
    if low.length == 0 { return false }
    arr[ascii] w = asciiSplitSpace(low)
    if w.length == 0 { return false }
    bool any = false
    int i = 0
    // The words are indexed rather than bound (FINDINGS.md, "ascii
    // aliases are not retained").
    while i < w.length {
        if w[i] == 'from' {
            i++
            if i >= w.length { return false }
            arr[bool] ok = [false]
            float deg = parseAngleDegrees(w[i], ok)
            if !ok[0] { return false }
            conicPreludeFrom = deg
            any = true
            i++
            continue
        }
        if w[i] == 'at' {
            i++
            arr[ascii] pos = []
            while i < w.length { pos.push(w[i])  i++ }
            if pos.length >= 2 {
                conicPreludePosX = parsePositionAxis(pos[0], true, fontSize)
                conicPreludePosY = parsePositionAxis(pos[1], false, fontSize)
            } else if pos.length == 1 {
                if pos[0] == 'top' { conicPreludePosY = lenPercent(0.0) }
                else if pos[0] == 'bottom' { conicPreludePosY = lenPercent(100.0) }
                else { conicPreludePosX = parsePositionAxis(pos[0], true, fontSize) }
            } else {
                return false
            }
            any = true
            break
        }
        return false
    }
    return any
}

bool func parseRadialPrelude(t:ascii, fontSize:int) {
    radPreludeCircle = false
    radPreludeExtent = RADEXT_FARTHEST_CORNER
    radPreludeRx = lenAuto()
    radPreludeRy = lenAuto()
    radPreludePosX = lenPercent(50.0)
    radPreludePosY = lenPercent(50.0)
    if t == null { return false }
    // The lowered string is held in a local, because the words the
    // split returns alias it and a temporary would be released out from
    // under them (FINDINGS.md, "ascii aliases are not retained").
    ascii low = asciiLower(asciiTrim(t))
    if low.length == 0 { return false }
    arr[ascii] w = asciiSplitSpace(low)
    if w.length == 0 { return false }

    bool any = false
    arr[Len] radii = []
    int i = 0
    // The words are indexed rather than bound to a local, for the same
    // reason (FINDINGS.md, "ascii aliases are not retained").
    while i < w.length {
        if w[i] == 'at' {
            i++
            arr[ascii] pos = []
            while i < w.length { pos.push(w[i])  i++ }
            if pos.length >= 2 {
                radPreludePosX = parsePositionAxis(pos[0], true, fontSize)
                radPreludePosY = parsePositionAxis(pos[1], false, fontSize)
            } else if pos.length == 1 {
                if pos[0] == 'top' { radPreludePosY = lenPercent(0.0) }
                else if pos[0] == 'bottom' { radPreludePosY = lenPercent(100.0) }
                else { radPreludePosX = parsePositionAxis(pos[0], true, fontSize) }
            } else {
                return false
            }
            any = true
            break
        }
        if w[i] == 'circle' { radPreludeCircle = true  any = true  i++  continue }
        if w[i] == 'ellipse' { radPreludeCircle = false  any = true  i++  continue }
        if w[i] == 'closest-side' { radPreludeExtent = RADEXT_CLOSEST_SIDE  any = true  i++  continue }
        if w[i] == 'closest-corner' { radPreludeExtent = RADEXT_CLOSEST_CORNER  any = true  i++  continue }
        if w[i] == 'farthest-side' { radPreludeExtent = RADEXT_FARTHEST_SIDE  any = true  i++  continue }
        if w[i] == 'farthest-corner' { radPreludeExtent = RADEXT_FARTHEST_CORNER  any = true  i++  continue }
        Len got = parseLength(w[i], fontSize)
        // Anything that is not a length ends the prelude and is a
        // colour stop instead. `parseLength` says so with LEN_INVALID,
        // not LEN_AUTO -- reading only for LEN_AUTO here swallowed the
        // first stop of every gradient that named no size.
        if got.kind != LEN_PX && got.kind != LEN_PERCENT { return false }
        radii.push(got)
        any = true
        i++
    }
    if radii.length > 0 {
        radPreludeExtent = RADEXT_EXPLICIT
        radPreludeRx = radii[0]
        radPreludeRy = radii.length > 1 ? radii[1] : radii[0]
        // One length is a circle's radius; two are an ellipse's.
        if radii.length == 1 { radPreludeCircle = true }
    }
    return any
}

// `linear-gradient()`, `radial-gradient()` and their repeating forms.
// The stop list is parsed the same way for all four: a stop's position
// is a fraction of the gradient line for a linear gradient and of the
// gradient ray for a radial one, which is the same number either way.
// One shadow of a `box-shadow` list. The lengths come in order --
// offset-x, offset-y, then blur and spread if they are there -- and the
// colour and `inset` may sit anywhere among them.
// The `)` closing the `(` at `open`, counting nested parentheses, or -1.
// A transform function's argument can itself hold parentheses -- a
// calc() length -- so scanning for the next `)` is not enough.
int func asciiMatchingParen(t:ascii, open:int) {
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

// An angle in degrees. CSS angles come in four units and Festina's
// rotate takes degrees, so the rest are converted here rather than at
// the call.
float func parseAngleDegrees(tok:ascii, ok:arr[bool]) {
    ok[0] = false
    ascii t = asciiLower(asciiTrim(tok))
    parseNumberAt(t, 0)
    if !numOk { return 0.0 }
    float v = numValue
    ascii unit = t.slice(numEnd, t.length)
    ok[0] = true
    if unit == 'deg' || unit == '' { return v }
    if unit == 'grad' { return v * 0.9 }
    if unit == 'rad' { return v * 180.0 / 3.14159265358979 }
    if unit == 'turn' { return v * 360.0 }
    ok[0] = false
    return 0.0
}

// One `transform` function, or a kind of -1 for one this canvas cannot
// express. The standard's own answer for a transform it cannot apply is
// to drop it, which is what a -1 means to the caller.
Transform func parseTransformFunction(name:text, args:arr[ascii], fontSize:int) {
    Transform tr
    tr.kind = -1
    tr.sx = 1.0
    tr.sy = 1.0
    if name == 'translate' || name == 'translatex' || name == 'translatey' {
        if args.length == 0 { return tr }
        Len a = parseLength(args[0], fontSize)
        if a.kind != LEN_PX && a.kind != LEN_PERCENT { return tr }
        tr.kind = TX_TRANSLATE
        if name == 'translatey' {
            tr.y = a
        } else {
            tr.x = a
            if name == 'translate' && args.length > 1 {
                Len b = parseLength(args[1], fontSize)
                if b.kind == LEN_PX || b.kind == LEN_PERCENT { tr.y = b }
            }
        }
        return tr
    }
    if name == 'scale' || name == 'scalex' || name == 'scaley' {
        if args.length == 0 { return tr }
        parseNumberAt(asciiTrim(args[0]), 0)
        if !numOk { return tr }
        float a = numValue
        tr.kind = TX_SCALE
        if name == 'scalex' { tr.sx = a }
        else if name == 'scaley' { tr.sy = a }
        else {
            tr.sx = a
            tr.sy = a
            if args.length > 1 {
                parseNumberAt(asciiTrim(args[1]), 0)
                if numOk { tr.sy = numValue }
            }
        }
        return tr
    }
    if name == 'rotate' || name == 'rotatez' {
        if args.length == 0 { return tr }
        arr[bool] ok = [false]
        float deg = parseAngleDegrees(args[0], ok)
        if !ok[0] { return tr }
        tr.kind = TX_ROTATE
        tr.angle = deg
        return tr
    }
    return tr
}

// The `transform` property: a list of functions, applied left to right.
// CSS Masking 1's <basic-shape> and <geometry-box>. What comes back is
// the shape as written: the reference box is not known until layout has
// run, so every length stays a Len and the painter resolves it.
//
// The value is lowered into a buffer this function owns, and every
// slice is taken from that one value rather than from another slice,
// which is what FINDINGS.md's first entry asks for.
ClipShape func parseClipPath(v:ascii, fontSize:int) {
    ClipShape sh
    sh.kind = CLIPSHAPE_NONE
    sh.geoBox = GEOBOX_BORDER
    if v == null { return sh }
    ascii t = asciiLower(asciiTrim(v))
    if t.length == 0 || t == 'none' { return sh }
    int i = 0
    while i < t.length {
        while i < t.length && isSpaceCode(t.charCodeAt(i)) { i++ }
        if i >= t.length { break }
        int start = i
        while i < t.length && !isSpaceCode(t.charCodeAt(i)) && t.charCodeAt(i) != CH_LPAREN { i++ }
        if i < t.length && t.charCodeAt(i) == CH_LPAREN {
            int close = asciiMatchingParen(t, i)
            if close < 0 { break }
            if asciiRegionEquals(t, start, i, 'inset') {
                readInsetShape(sh, t.slice(i + 1, close), fontSize)
            } else if asciiRegionEquals(t, start, i, 'circle') {
                readRadialShape(sh, t.slice(i + 1, close), fontSize, true)
            } else if asciiRegionEquals(t, start, i, 'ellipse') {
                readRadialShape(sh, t.slice(i + 1, close), fontSize, false)
            } else if asciiRegionEquals(t, start, i, 'polygon') {
                readPolygonShape(sh, t.slice(i + 1, close), fontSize)
            }
            i = close + 1
            continue
        }
        int box = geometryBoxAt(t, start, i)
        if box >= 0 {
            sh.geoBox = box
            sh.geoBoxExplicit = true
            // A geometry box on its own is the shape. Beside a function
            // it only says what that function resolves against, which
            // is why this does not overwrite a shape already read.
            if sh.kind == CLIPSHAPE_NONE { sh.kind = CLIPSHAPE_RECT }
        }
    }
    return sh
}

// Which reference box a region of `src` names, or -1 for none of them.
// The SVG boxes -- `fill-box`, `stroke-box`, `view-box` -- name a box
// this engine cannot produce, so they are none of them too.
int func geometryBoxAt(src:ascii, from:int, to:int) {
    if asciiRegionEquals(src, from, to, 'border-box') { return GEOBOX_BORDER }
    if asciiRegionEquals(src, from, to, 'padding-box') { return GEOBOX_PADDING }
    if asciiRegionEquals(src, from, to, 'content-box') { return GEOBOX_CONTENT }
    if asciiRegionEquals(src, from, to, 'margin-box') { return GEOBOX_MARGIN }
    return -1
}

// inset( <length-percentage>{1,4} [round <radius>]? ) -- the same one to
// four shorthand as margin. A `round` radius is read and dropped: a
// rounded clip needs the path API an image does not have (FINDINGS.md).
void func readInsetShape(sh:ClipShape, args:ascii, fontSize:int) {
    sh.kind = CLIPSHAPE_RECT
    arr[ascii] parts = cssTokens(args)
    arr[Len] sides = []
    int roundAt = -1
    for int i = 0, i < parts.length, i++ {
        if parts[i] == 'round' { roundAt = i  break }
        Len l = parseLength(parts[i], fontSize)
        if l.kind == LEN_AUTO { continue }
        sides.push(l)
    }
    if sides.length == 0 { return }
    sh.insetTop = sides[0]
    sh.insetRight = sides.length > 1 ? sides[1] : sides[0]
    sh.insetBottom = sides.length > 2 ? sides[2] : sides[0]
    sh.insetLeft = sides.length > 3 ? sides[3] : sh.insetRight
    if roundAt >= 0 { readInsetRadii(sh, parts, roundAt + 1, fontSize) }
}

// The `round` half: `<length-percentage>{1,4} [ / <length-percentage>{1,4} ]?`
// -- the same grammar as `border-radius`, and graded by the same
// one-to-four rule, so `radiusSlot` answers both rather than this
// growing a second copy of it.
//
// A radius of zero on every corner is a square corner, and leaves the
// index at 0 so that `inset(10px round 0)` costs a rounded rectangle
// nothing and takes the same branch as `inset(10px)`.
void func readInsetRadii(sh:ClipShape, parts:arr[ascii], from:int, fontSize:int) {
    arr[Len] across = []
    arr[Len] down = []
    bool afterSlash = false
    bool any = false
    for int i = from, i < parts.length, i++ {
        if parts[i] == '/' { afterSlash = true  continue }
        Len l = parseLength(parts[i], fontSize)
        if l.kind == LEN_AUTO { continue }
        if afterSlash { down.push(l) } else { across.push(l) }
        if !(l.kind == LEN_PX && l.v == 0.0) { any = true }
    }
    if across.length == 0 || !any { return }
    InsetRadii r
    r.rx = []
    r.ry = []
    for int i = 0, i < 4, i++ {
        r.rx.push(radiusSlot(across, i))
        r.ry.push(radiusSlot(down.length > 0 ? down : across, i))
    }
    insetRadiiList.push(r)
    sh.insetRoundIdx = insetRadiiList.length
}

// circle( <radius>? [at <position>]? ) and ellipse(), which differ only
// in how many radii they take.
void func readRadialShape(sh:ClipShape, args:ascii, fontSize:int, isCircle:bool) {
    sh.kind = isCircle ? CLIPSHAPE_CIRCLE : CLIPSHAPE_ELLIPSE
    sh.centreX = lenPercent(50.0)
    sh.centreY = lenPercent(50.0)
    sh.radiusXKind = CLIPRAD_CLOSEST
    sh.radiusYKind = CLIPRAD_CLOSEST
    arr[ascii] parts = cssTokens(args)
    int at = -1
    for int i = 0, i < parts.length, i++ {
        if parts[i] == 'at' {
            at = i
            break
        }
    }
    int radiiEnd = at < 0 ? parts.length : at
    int taken = 0
    for int i = 0, i < radiiEnd, i++ {
        int kind = CLIPRAD_LENGTH
        Len l = lenAuto()
        if parts[i] == 'closest-side' { kind = CLIPRAD_CLOSEST }
        else if parts[i] == 'farthest-side' { kind = CLIPRAD_FARTHEST }
        else {
            l = parseLength(parts[i], fontSize)
            if l.kind == LEN_AUTO { continue }
        }
        if taken == 0 {
            sh.radiusX = l
            sh.radiusXKind = kind
            // A circle has one radius, which serves both axes.
            if isCircle {
                sh.radiusY = l
                sh.radiusYKind = kind
            }
        } else if taken == 1 && !isCircle {
            sh.radiusY = l
            sh.radiusYKind = kind
        }
        taken++
    }
    if at < 0 { return }
    int seen = 0
    for int i = at + 1, i < parts.length, i++ {
        if seen == 0 { sh.centreX = clipPositionLen(parts[i], fontSize, false) }
        else if seen == 1 { sh.centreY = clipPositionLen(parts[i], fontSize, true) }
        seen++
    }
}

// One component of a position inside a basic shape: a length, a
// percentage, or the side keyword that stands for one.
Len func clipPositionLen(t:ascii, fontSize:int, vertical:bool) {
    if t == 'center' { return lenPercent(50.0) }
    if !vertical && t == 'left' { return lenPercent(0.0) }
    if !vertical && t == 'right' { return lenPercent(100.0) }
    if vertical && t == 'top' { return lenPercent(0.0) }
    if vertical && t == 'bottom' { return lenPercent(100.0) }
    Len l = parseLength(t, fontSize)
    if l.kind == LEN_AUTO { return lenPercent(50.0) }
    return l
}

// polygon( <fill-rule>? , [<length-percentage> <length-percentage>]# ).
// The fill rule is kept. It says nothing about a polygon that does not
// cross itself, and everything about one that does: `nonzero`, the
// initial value, keeps the middle of a star where `evenodd` cuts it
// out (todo.md, measured against Chromium).
void func readPolygonShape(sh:ClipShape, args:ascii, fontSize:int) {
    arr[ascii] pairs = splitTopLevelCommas(args)
    arr[Len] xs = []
    arr[Len] ys = []
    bool evenOdd = false
    for int i = 0, i < pairs.length, i++ {
        arr[ascii] two = cssTokens(pairs[i])
        // The rule, when it is there, is the whole of the first
        // argument -- a single token where a vertex is a pair.
        if i == 0 && two.length == 1 {
            ascii rule = asciiLower(asciiTrim(two[0]))
            if rule == 'evenodd' { evenOdd = true }
            continue
        }
        if two.length < 2 { continue }
        Len x = parseLength(two[0], fontSize)
        Len y = parseLength(two[1], fontSize)
        if x.kind == LEN_AUTO || y.kind == LEN_AUTO { continue }
        xs.push(x)
        ys.push(y)
    }
    if xs.length < 3 { return }
    sh.kind = CLIPSHAPE_POLYGON
    sh.pointsX = xs
    sh.pointsY = ys
    sh.fillEvenOdd = evenOdd
}

// The CSS2 `clip`, which said the same thing about an absolutely
// positioned box before clip-path existed: rect(top, right, bottom,
// left) is a rectangle measured from the border box's top and left
// edges, so it becomes the four insets the painter already cuts by.
// `auto` on a side means that side of the box, which is no inset.
ClipShape func parseClipRect(v:ascii, fontSize:int) {
    ClipShape sh
    sh.kind = CLIPSHAPE_NONE
    sh.geoBox = GEOBOX_BORDER
    if v == null { return sh }
    ascii t = asciiLower(asciiTrim(v))
    int open = asciiIndexOf(t, '('.toAscii(), 0)
    if open <= 0 || !asciiEndsWith(t, ')') { return sh }
    if !asciiRegionEquals(t, 0, open, 'rect') { return sh }
    arr[ascii] parts = splitTopLevelCommas(t.slice(open + 1, t.length - 1))
    // rect() is written with commas or with spaces; both are four
    // values and the standard accepts either.
    if parts.length == 1 { parts = cssTokens(parts[0]) }
    if parts.length < 4 { return sh }
    sh.kind = CLIPSHAPE_RECT
    sh.insetTop = clipRectEdge(parts[0], fontSize, false)
    sh.insetRight = clipRectEdge(parts[1], fontSize, true)
    sh.insetBottom = clipRectEdge(parts[2], fontSize, true)
    sh.insetLeft = clipRectEdge(parts[3], fontSize, false)
    return sh
}

// One edge of a rect(). Top and left are already insets. Right and
// bottom are distances from the same two edges, so the inset from the
// far side is the box's own size less the distance -- which is a
// percentage of 100 minus a length, and that is what a calc Len holds.
Len func clipRectEdge(t:ascii, fontSize:int, fromFarSide:bool) {
    if t == 'auto' { return lenPx(0.0) }
    Len l = parseLength(t, fontSize)
    if l.kind != LEN_PX { return lenPx(0.0) }
    if !fromFarSide { return l }
    return lenCalc(0.0 - l.v, 100.0)
}

// ---- CSS Filter Effects 1 §8: `filter` --------------------------------
//
// Parsed into a FilterSpec, applied to each source colour as it is
// painted. The whole declaration is dropped when it names a function
// this engine cannot apply -- `blur()`, `drop-shadow()`, `url()` -- so
// that a page asking for one of those gets the unfiltered rendering
// rather than a partially filtered one. That is also what keeps the
// property instrument honest: its row is `blur(2px)`, and it must go on
// failing.

// The amount a filter function was given. A number or a percentage;
// `hue-rotate` takes an angle instead and is read separately. An
// omitted argument is the function's own identity-breaking default,
// which the standard gives as 1 for every one of these.
float func filterAmount(args:arr[ascii], dflt:float, ok:arr[bool]) {
    ok[0] = true
    if args.length == 0 { return dflt }
    if args.length > 1 { ok[0] = false  return dflt }
    ascii a = asciiTrim(args[0])
    if a.length == 0 { return dflt }
    parseNumberAt(a, 0)
    if !numOk { ok[0] = false  return dflt }
    ascii unit = a.slice(numEnd, a.length)
    if unit == '%' { return numValue / 100.0 }
    if unit == '' { return numValue }
    ok[0] = false
    return dflt
}

// A 1-based index into filterSpecs, or 0 for `none` and for any list
// this engine cannot paint.
int func parseFilterList(v:ascii) {
    if v == null { return 0 }
    ascii t = asciiTrim(v)
    if t.length == 0 { return 0 }
    if asciiLower(t) == 'none' { return 0 }
    FilterSpec spec
    spec.kinds = []
    spec.amounts = []
    arr[bool] ok = [true]
    int i = 0
    while i < t.length {
        int open = asciiIndexOf(t, '('.toAscii(), i)
        if open < 0 { break }
        int close = asciiMatchingParen(t, open)
        if close < 0 { return 0 }
        text name = asciiLower(asciiTrim(t.slice(i, open))).toText()
        arr[ascii] args = splitTopLevelCommas(t.slice(open + 1, close))
        int kind = 0
        float amt = 0.0
        if name == 'grayscale' { kind = CFILTER_GRAYSCALE  amt = filterAmount(args, 1.0, ok) }
        else if name == 'sepia' { kind = CFILTER_SEPIA  amt = filterAmount(args, 1.0, ok) }
        else if name == 'saturate' { kind = CFILTER_SATURATE  amt = filterAmount(args, 1.0, ok) }
        else if name == 'invert' { kind = CFILTER_INVERT  amt = filterAmount(args, 1.0, ok) }
        else if name == 'brightness' { kind = CFILTER_BRIGHTNESS  amt = filterAmount(args, 1.0, ok) }
        else if name == 'contrast' { kind = CFILTER_CONTRAST  amt = filterAmount(args, 1.0, ok) }
        else if name == 'opacity' { kind = CFILTER_OPACITY  amt = filterAmount(args, 1.0, ok) }
        else if name == 'hue-rotate' {
            kind = CFILTER_HUEROTATE
            if args.length == 0 { amt = 0.0 }
            else if args.length > 1 { return 0 }
            else { amt = parseAngleDegrees(args[0], ok) }
        }
        // blur(), drop-shadow(), url() and anything unrecognised.
        else { return 0 }
        if !ok[0] { return 0 }
        // The four amounts the standard clamps below zero, and the four
        // it clamps at one as well.
        if amt < 0.0 && kind != CFILTER_HUEROTATE { amt = 0.0 }
        if amt > 1.0 && (kind == CFILTER_GRAYSCALE || kind == CFILTER_SEPIA
            || kind == CFILTER_INVERT || kind == CFILTER_OPACITY) { amt = 1.0 }
        spec.kinds.push(kind)
        spec.amounts.push(amt)
        i = close + 1
    }
    if spec.kinds.length == 0 { return 0 }
    filterSpecs.push(spec)
    return filterSpecs.length
}

arr[Transform] func parseTransformList(v:ascii, fontSize:int) {
    arr[Transform] out = []
    if v == null { return out }
    ascii t = asciiTrim(v)
    if asciiLower(t) == 'none' || t == '' { return out }
    int i = 0
    while i < t.length {
        int open = asciiIndexOf(t, '('.toAscii(), i)
        if open < 0 { break }
        int close = asciiMatchingParen(t, open)
        if close < 0 { break }
        text name = asciiLower(asciiTrim(t.slice(i, open))).toText()
        arr[ascii] args = splitTopLevelCommas(t.slice(open + 1, close))
        Transform tr = parseTransformFunction(name, args, fontSize)
        if tr.kind >= 0 { out.push(tr) }
        i = close + 1
    }
    return out
}

// Splits a value on top-level slashes, which is how `grid-column` and
// `grid-row` separate their two edges.
arr[ascii] func splitTopLevelSlash(v:ascii) {
    arr[ascii] out = []
    int depth = 0
    int start = 0
    for int i = 0, i < v.length, i++ {
        int c = v.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN { depth-- }
        else if c == CH_SLASH && depth <= 0 {
            out.push(asciiTrim(v.slice(start, i)))
            start = i + 1
        }
    }
    out.push(asciiTrim(v.slice(start, v.length)))
    return out
}

// One grid track: its two sizing functions (Grid 1 §7.2). `fr` is a
// share of the free space rather than a length, so it cannot go through
// parseLength at all. Anything unrecognized is `auto`, which is both
// the initial value and what an invalid track list falls back to.
Track func parseTrack(tok:ascii, fontSize:int) {
    Track t
    t.kind = TRACK_AUTO
    t.minKind = TRACK_AUTO
    ascii low = asciiLower(asciiTrim(tok))
    if low == 'auto' { return t }
    if low == 'min-content' {
        t.kind = TRACK_MIN_CONTENT
        t.minKind = TRACK_MIN_CONTENT
        return t
    }
    if low == 'max-content' {
        t.kind = TRACK_MAX_CONTENT
        t.minKind = TRACK_MAX_CONTENT
        return t
    }
    if asciiStartsWithLower(low, 'minmax(', 0) && low.charCodeAt(low.length - 1) == CH_RPAREN {
        arr[ascii] mm = splitTopLevelCommas(low.slice(7, low.length - 1))
        if mm.length != 2 { return t }
        Track lo = parseTrack(asciiTrim(mm[0]), fontSize)
        Track hi = parseTrack(asciiTrim(mm[1]), fontSize)
        // Neither `fr` nor `fit-content()` is valid as a minimum, and
        // `fit-content()` is not valid as a maximum inside minmax()
        // either; each reads as `auto`, the value an invalid component
        // of a track list falls back to.
        t.minKind = lo.kind == TRACK_FR || lo.kind == TRACK_FIT_CONTENT ? TRACK_AUTO : lo.kind
        t.minSize = lo.size
        t.kind = hi.kind == TRACK_FIT_CONTENT ? TRACK_AUTO : hi.kind
        t.size = hi.size
        t.fr = hi.fr
        return t
    }
    if asciiStartsWithLower(low, 'fit-content(', 0) && low.charCodeAt(low.length - 1) == CH_RPAREN {
        Len clamp = parseLength(asciiTrim(low.slice(12, low.length - 1)), fontSize)
        if clamp.kind == LEN_PX || clamp.kind == LEN_PERCENT {
            t.kind = TRACK_FIT_CONTENT
            t.size = clamp
        }
        return t
    }
    if low.length > 2 && low.slice(low.length - 2, low.length) == 'fr' {
        parseNumberAt(low, 0)
        if numOk {
            t.kind = TRACK_FR
            t.fr = numValue > 0.0 ? numValue : 0.0
            return t
        }
        return t
    }
    Len l = parseLength(low, fontSize)
    if l.kind == LEN_PX || l.kind == LEN_PERCENT {
        t.kind = TRACK_LEN
        t.size = l
        t.minKind = TRACK_LEN
        t.minSize = l
    }
    return t
}

// A track list, with `repeat(n, <list>)` expanded in place. The count
// is capped because a template is written by hand and a runaway repeat
// would be a denial of service rather than a layout.
// The names a track list wrote in brackets, and the line each sits at.
// They come back in globals because a Festina function returns one
// value (FINDINGS.md, "one value out of a function"), and they are
// reset here so a caller that ignores them never reads the last list's.
arr[text] trackLineNames = []
arr[int] trackLineAt = []
// The empty answer, shared rather than built afresh. Almost every call
// here is for a property the page never declared, and two allocations
// apiece across four track properties per distinct style is a cost the
// pages without a grid should not pay. Nothing writes to these: the
// first bracketed name swaps in arrays of its own.
arr[text] trackNoNames = []
arr[int] trackNoLines = []
bool trackLinesOwned = false
// Where a `repeat(auto-fill | auto-fit, ...)` group ended up in the
// list, how long it is, and which of the two it was. Out-parameters for
// the same reason the line names are: a Festina function returns one
// value (FINDINGS.md, "one value out of a function"). A length of zero
// means the list has no auto-repeat in it.
int trackAutoRepeatAt = -1
int trackAutoRepeatLen = 0
bool trackAutoRepeatFit = false

// Set by parseTrackList when the list was the word `subgrid`, which
// declares no tracks of its own: they come from the parent grid.
bool trackIsSubgrid = false

arr[Track] func parseTrackList(v:ascii, fontSize:int) {
    trackLineNames = trackNoNames
    trackLineAt = trackNoLines
    trackLinesOwned = false
    trackAutoRepeatAt = -1
    trackAutoRepeatLen = 0
    trackAutoRepeatFit = false
    trackIsSubgrid = false
    arr[Track] out = []
    if v == null { return out }
    ascii t = asciiTrim(v)
    if t == '' || asciiLower(t) == 'none' { return out }
    arr[ascii] toks = cssTokens(t)
    // `subgrid` may be followed by a line-name list (Grid 2 §3), which
    // names the lines the subgrid spans rather than declaring tracks of
    // its own. Reading the keyword only when it is the whole value lost
    // the flag the moment a name list appeared, and the box became an
    // ordinary grid -- silently, because the names parsed fine.
    int from = 0
    if toks.length > 0 && asciiLower(asciiTrim(toks[0])) == 'subgrid' {
        trackIsSubgrid = true
        from = 1
    }
    // A subgrid declares no tracks, so the line a name belongs to
    // cannot be counted from them: its lines are consecutive, one per
    // bracketed group.
    int subgridLine = 1
    for int i = from, i < toks.length, i++ {
        // `[a b]` names the line before the next track. cssTokens splits
        // on whitespace and knows nothing of brackets, so a bracketed
        // run arrives as several tokens and is gathered back here.
        if toks[i].charCodeAt(0) == CH_LBRACKET {
            if !trackLinesOwned {
                arr[text] freshNames = []
                arr[int] freshAt = []
                trackLineNames = freshNames
                trackLineAt = freshAt
                trackLinesOwned = true
            }
            int j = i
            while j < toks.length {
                ascii piece = asciiTrim(toks[j])
                int from = piece.charCodeAt(0) == CH_LBRACKET ? 1 : 0
                bool last = piece.charCodeAt(piece.length - 1) == CH_RBRACKET
                ascii inner = asciiTrim(piece.slice(from, last ? piece.length - 1 : piece.length))
                if inner.length > 0 {
                    trackLineNames.push(asciiLower(inner).toText())
                    // Line numbers count from 1, and this names the line
                    // before the track that follows.
                    trackLineAt.push(trackIsSubgrid ? subgridLine : out.length + 1)
                }
                if last { break }
                j++
            }
            subgridLine++
            i = j
            continue
        }
        // The token is indexed rather than bound, because a bound
        // element releases an alias that was never retained
        // (FINDINGS.md, "ascii aliases are not retained"). Only
        // valgrind sees the difference.
        if asciiStartsWithLower(asciiLower(toks[i]), 'repeat(', 0)
            && toks[i].charCodeAt(toks[i].length - 1) == CH_RPAREN {
            arr[ascii] args = splitTopLevelCommas(toks[i].slice(7, toks[i].length - 1))
            if args.length < 2 { continue }
            // `auto-fill` and `auto-fit` repeat as many times as the
            // container turns out to have room for, which is not known
            // here. One copy of the group goes in and where it sits is
            // recorded; layout expands it. The standard allows one such
            // repeat in a list, so a second is ignored.
            ascii how = asciiLower(asciiTrim(args[0]))
            if how == 'auto-fill' || how == 'auto-fit' {
                if trackAutoRepeatLen > 0 { continue }
                arr[ascii] once = cssTokens(asciiTrim(args[1]))
                if once.length == 0 { continue }
                trackAutoRepeatAt = out.length
                trackAutoRepeatLen = once.length
                trackAutoRepeatFit = how == 'auto-fit'
                for int k = 0, k < once.length, k++ { out.push(parseTrack(once[k], fontSize)) }
                continue
            }
            parseNumberAt(asciiTrim(args[0]), 0)
            if !numOk { continue }
            int n = minInt(maxInt(roundPx(numValue), 0), 1000)
            arr[ascii] inner = cssTokens(asciiTrim(args[1]))
            for int r = 0, r < n, r++ {
                for int k = 0, k < inner.length, k++ { out.push(parseTrack(inner[k], fontSize)) }
            }
            continue
        }
        out.push(parseTrack(toks[i], fontSize))
    }
    return out
}

// Whether one edge of `grid-area` is a name rather than a number,
// `span`, or `auto` -- only a name is copied to the edges left out.
bool func gridEdgeIsName(v:ascii) {
    if v == null { return false }
    arr[ascii] t = cssTokens(v)
    if t.length == 0 { return false }
    ascii first = asciiLower(asciiTrim(t[0]))
    if first == 'span' || first == 'auto' || first.length == 0 { return false }
    parseNumberAt(first, 0)
    return !numOk
}

// One edge of a grid placement: a line number, `span n`, or `auto`.
GridLine func parseGridLine(v:ascii) {
    GridLine g
    g.kind = GRIDLINE_AUTO
    if v == null { return g }
    arr[ascii] t = cssTokens(v)
    if t.length == 0 { return g }
    if asciiLower(t[0]) == 'span' {
        // `span [ <integer> || <custom-ident> ]`, in either order. The
        // name is not decoration: §8.3 counts only lines carrying it,
        // and assumes it on the implicit lines when the template has
        // too few -- so `span zz` is a span to the implicit grid, not a
        // span of one.
        g.kind = GRIDLINE_SPAN
        g.n = 1
        bool sawCount = false
        for int i = 1, i < t.length, i++ {
            ascii tok = asciiTrim(t[i])
            if tok.length == 0 { continue }
            parseNumberAt(tok, 0)
            if numOk {
                if !sawCount { g.n = maxInt(roundPx(numValue), 1)  sawCount = true }
            } else if g.name == null || g.name == '' {
                g.name = tok.toText()
            }
        }
        return g
    }
    if asciiLower(t[0]) == 'auto' { return g }
    // `<integer> && <custom-ident>` in either order, so the count and
    // the name are looked for separately rather than by position. A
    // count without a name is a line number; a name without a count
    // means the first line carrying it.
    int count = 0
    ascii nameTok = null
    for int i = 0, i < t.length, i++ {
        ascii tok = asciiTrim(t[i])
        if tok.length == 0 { continue }
        parseNumberAt(tok, 0)
        if numOk {
            if count == 0 { count = roundPx(numValue) }
        } else if nameTok == null {
            nameTok = tok
        }
    }
    if nameTok == null {
        if count != 0 {
            g.kind = GRIDLINE_NUMBER
            g.n = count
        }
        return g
    }
    // A name. Which line it is depends on the container's template, so
    // it is carried as a name and resolved in layout, where the grid it
    // belongs to is in hand; `n` is which line of that name is wanted.
    g.kind = GRIDLINE_NAME
    g.name = asciiLower(nameTok).toText()
    g.n = count == 0 ? 1 : count
    return g
}

// `grid-template-areas`: one quoted string per row, each a row of cell
// names with `.` for a cell belonging to no area (Grid 1 §7.3). The
// whole declaration is invalid -- and dropped, leaving no areas at all
// -- if the rows are not all the same length or if any name covers
// something other than a rectangle. Chromium 141 drops both.
//
// The result is a flat row-major array of names; the row width comes
// back in `areaTemplateCols` and is 0 when there is no template.
arr[text] areaTemplateNames = []
int areaTemplateCols = 0
// Shared for the same reason as the empty line-name lists above: a page
// with no `grid-template-areas` anywhere allocates nothing for it.
arr[text] areaNoNames = []

void func parseGridAreas(v:ascii) {
    areaTemplateNames = areaNoNames
    areaTemplateCols = 0
    if v == null { return }
    ascii t = asciiTrim(v)
    if t == null || t.length == 0 || asciiLower(t) == 'none' { return }
    arr[ascii] rows = cssTokens(t)
    if rows.length == 0 { return }
    arr[text] cells = []
    int cols = -1
    for int r = 0, r < rows.length, r++ {
        ascii row = asciiTrim(rows[r])
        if row.length < 2 { return }
        int q = row.charCodeAt(0)
        if q != CH_QUOTE && q != CH_APOS { return }
        if row.charCodeAt(row.length - 1) != q { return }
        arr[ascii] names = asciiSplitSpace(asciiTrim(row.slice(1, row.length - 1)))
        if names.length == 0 { return }
        if cols < 0 { cols = names.length }
        else if names.length != cols { return }
        for int c = 0, c < names.length, c++ {
            // A run of dots is one null cell, however many dots.
            cells.push(asciiIsAllDots(names[c]) ? '' : asciiLower(names[c]).toText())
        }
    }
    if cols <= 0 { return }
    // Every name must cover a rectangle and nothing else: find each
    // name's bounding box and require it to be full and to hold no
    // other name.
    int rowCount = Math.floorDiv(cells.length, cols)
    for int i = 0, i < cells.length, i++ {
        if cells[i] == '' { continue }
        bool seen = false
        for int j = 0, j < i, j++ { if cells[j] == cells[i] { seen = true  break } }
        if seen { continue }
        int minR = rowCount
        int maxR = -1
        int minC = cols
        int maxC = -1
        for int j = 0, j < cells.length, j++ {
            if cells[j] != cells[i] { continue }
            int rr = Math.floorDiv(j, cols)
            int cc = j % cols
            if rr < minR { minR = rr }
            if rr > maxR { maxR = rr }
            if cc < minC { minC = cc }
            if cc > maxC { maxC = cc }
        }
        for int rr = minR, rr <= maxR, rr++ {
            for int cc = minC, cc <= maxC, cc++ {
                if cells[rr * cols + cc] != cells[i] { return }
            }
        }
    }
    areaTemplateNames = cells
    areaTemplateCols = cols
}

Shadow func parseShadow(v:ascii, currentColor:int, fontSize:int) {
    arr[ascii] t = cssTokens(v)
    if t.length == 0 { return null }
    Shadow sh
    sh.color = currentColor
    arr[int] lengths = []
    for int i = 0, i < t.length, i++ {
        // The token is indexed rather than bound, because a bound slice
        // releases an alias that was never retained (FINDINGS.md,
        // "ascii aliases are not retained").
        if asciiLower(t[i]) == 'inset' { sh.inset = true  continue }
        Len l = parseLength(t[i], fontSize)
        if l.kind == LEN_PX { lengths.push(roundPx(l.v))  continue }
        int c = parseCssColor(t[i], COLOR_UNSET)
        if c != COLOR_UNSET { sh.color = c }
    }
    if lengths.length < 2 { return null }
    sh.dx = lengths[0]
    sh.dy = lengths[1]
    if lengths.length > 2 { sh.blur = maxInt(lengths[2], 0) }
    if lengths.length > 3 { sh.spread = lengths[3] }
    return sh
}

Gradient func parseGradient(v:ascii, currentColor:int, fontSize:int) {
    Gradient g = noGradient()
    if v == null { return g }
    ascii low = asciiLower(asciiTrim(v))
    bool repLinear = asciiStartsWithLower(low, 'repeating-linear-gradient(', 0)
    bool plainLinear = asciiStartsWithLower(low, 'linear-gradient(', 0)
    bool repRadial = asciiStartsWithLower(low, 'repeating-radial-gradient(', 0)
    bool plainRadial = asciiStartsWithLower(low, 'radial-gradient(', 0)
    bool repConic = asciiStartsWithLower(low, 'repeating-conic-gradient(', 0)
    bool plainConic = asciiStartsWithLower(low, 'conic-gradient(', 0)
    if !repLinear && !plainLinear && !repRadial && !plainRadial
        && !repConic && !plainConic { return g }
    bool radial = repRadial || plainRadial
    bool conic = repConic || plainConic
    bool repeating = repLinear || repRadial || repConic
    int open = asciiIndexOf(v, '('.toAscii(), 0)
    if open < 0 || v.charCodeAt(v.length - 1) != CH_RPAREN { return g }
    ascii inside = asciiTrim(v.slice(open + 1, v.length - 1))
    arr[ascii] parts = splitTopLevelCommas(inside)
    if parts.length == 0 { return g }

    int first = 0
    float angle = 180.0                 // `to bottom` when none is given
    if conic {
        if parseConicPrelude(parts[0], fontSize) { first = 1 }
        g.conicFrom = conicPreludeFrom
        g.radialPosX = conicPreludePosX
        g.radialPosY = conicPreludePosY
    } else if radial {
        if parseRadialPrelude(parts[0], fontSize) { first = 1 }
        g.radialCircle = radPreludeCircle
        g.radialExtent = radPreludeExtent
        g.radialRx = radPreludeRx
        g.radialRy = radPreludeRy
        g.radialPosX = radPreludePosX
        g.radialPosY = radPreludePosY
    } else {
        float dir = parseGradientDirection(parts[0])
        if dir >= 0.0 { angle = dir  first = 1 }
    }

    arr[int] colors = []
    arr[int] kinds = []
    arr[float] vals = []
    arr[int] hintKinds = []
    arr[float] hintVals = []
    for int i = first, i < parts.length, i++ {
        if conic { parseConicStop(parts[i], currentColor, fontSize) }
        else { parseGradientStop(parts[i], currentColor, fontSize) }
        if gradStopColor == COLOR_UNSET {
            // A component with a position and no colour is not a stop:
            // it is an interpolation hint for the pair it sits between
            // (§3.4.4). One that sits before any stop, or a second one
            // for the same pair, is invalid and takes the gradient with
            // it, which is what the standard asks for.
            arr[ascii] only = cssTokens(asciiTrim(parts[i]))
            if only.length != 1 || colors.length == 0 { return noGradient() }
            if hintKinds[colors.length - 1] != GSTOP_AUTO { return noGradient() }
            if !parseGradientPosition(asciiTrim(only[0]), conic, fontSize) { return noGradient() }
            hintKinds[colors.length - 1] = gradStopKind
            hintVals[colors.length - 1] = gradStopVal
            continue
        }
        colors.push(gradStopColor)
        kinds.push(gradStopKind)
        vals.push(gradStopVal)
        hintKinds.push(GSTOP_AUTO)
        hintVals.push(0.0)
    }
    if colors.length < 2 { return noGradient() }

    g.present = true
    g.repeating = repeating
    g.radial = radial
    g.conic = conic
    g.angle = angle
    g.stops = colors
    g.posKind = kinds
    g.posVal = vals
    g.hintKind = hintKinds
    g.hintVal = hintVals
    return g
}

void func applyBackgroundShorthand(props:map[text], value:ascii) {
    if declIsCssWide(value) {
        props['background-color'] = dup(value)
        props['background-image'] = dup(value)
        props['background-repeat'] = dup(value)
        props['background-position'] = dup(value)
        props['background-size'] = dup(value)
        props['background-attachment'] = dup(value)
        props['background-origin'] = dup(value)
        props['background-clip'] = dup(value)
        return
    }
    arr[ascii] t = cssTokens(value)
    ascii found = 'transparent'
    ascii image = null
    for int i = 0, i < t.length, i++ {
        ascii tok = dup(t[i])
        if asciiStartsWithLower(tok, 'url(', 0) { continue }
        if asciiIndexOf(asciiLower(tok), 'gradient('.toAscii(), 0) >= 0 { image = tok  continue }
        int c = parseCssColor(tok, COLOR_BLACK)
        if c != COLOR_UNSET { found = tok }
    }
    setProp(props, 'background-color', found)
    // The shorthand resets the image, whether or not it names one.
    if image == null {
        setProp(props, 'background-image', 'none')
    } else {
        setProp(props, 'background-image', image)
    }
}

// `background-position` sets `background-position-x` and
// `background-position-y`, and is expanded here rather than read beside
// them, because otherwise cascade order between a shorthand and a
// longhand could not be honoured: whichever the reader consulted first
// would always win.
//
// One value positions the horizontal axis and centres the other, unless
// it is a vertical keyword, in which case it does the reverse -- which
// is what Chromium computes for `background-position: top` too.
void func splitBackgroundPosition(value:ascii) {
    bgPosXOut = ''
    bgPosYOut = ''
    ascii low = asciiLower(asciiTrim(value))
    arr[ascii] parts = asciiSplitSpace(low)
    if parts.length >= 2 {
        bgPosXOut = parts[0].toText()
        bgPosYOut = parts[1].toText()
        return
    }
    if parts.length != 1 { return }
    if parts[0] == 'top' {
        bgPosXOut = 'center'
        bgPosYOut = 'top'
    } else if parts[0] == 'bottom' {
        bgPosXOut = 'center'
        bgPosYOut = 'bottom'
    } else {
        bgPosXOut = parts[0].toText()
        bgPosYOut = 'center'
    }
}

// `mask` (CSS Masking 1 §6.7). A shorthand sets every longhand it
// covers, so each is reset to its initial value first and then whatever
// the value names is written over it -- otherwise a `mask` after a
// `mask-repeat` would leave the repeat standing, which is not what a
// shorthand does.
//
// One geometry box sets BOTH origin and clip; two set origin then clip,
// in that order. A `/` separates the position from the size.
void func applyMaskShorthand(props:map[text], value:ascii) {
    props['mask-image'] = 'none'
    props['mask-mode'] = 'match-source'
    props['mask-repeat'] = 'repeat'
    props['mask-position'] = '0% 0%'
    props['mask-size'] = 'auto'
    props['mask-origin'] = 'border-box'
    props['mask-clip'] = 'border-box'
    props['mask-composite'] = 'add'
    ascii v = asciiTrim(value)
    if v.length == 0 { return }
    int slash = asciiIndexOf(v, '/', 0)
    ascii sizePart = null
    if slash >= 0 {
        sizePart = asciiTrim(v.slice(slash + 1, v.length))
        v = asciiTrim(v.slice(0, slash))
    }
    arr[ascii] toks = cssTokens(v)
    text posToks = ''
    int boxes = 0
    for int i = 0, i < toks.length, i++ {
        // `dup`, because an `ascii` local bound straight to an array
        // element aliases it and both are released (FINDINGS.md,
        // "ascii aliasing"). Valgrind caught the double free here with
        // all 28 pixel checks passing.
        ascii tok = dup(toks[i])
        ascii low = asciiLower(tok)
        if asciiIndexOf(low, '(', 0) >= 0 || low == 'none' {
            props['mask-image'] = tok.toText()
        } else if low == 'repeat' || low == 'no-repeat' || low == 'repeat-x'
            || low == 'repeat-y' || low == 'round' || low == 'space' {
            props['mask-repeat'] = tok.toText()
        } else if low == 'alpha' || low == 'luminance' || low == 'match-source' {
            props['mask-mode'] = tok.toText()
        } else if low == 'border-box' || low == 'padding-box' || low == 'content-box' {
            if boxes == 0 {
                props['mask-origin'] = tok.toText()
                props['mask-clip'] = tok.toText()
            } else {
                props['mask-clip'] = tok.toText()
            }
            boxes++
        } else if low == 'no-clip' {
            props['mask-clip'] = 'border-box'
            boxes++
        } else {
            if posToks != '' { posToks = posToks + ' ' }
            posToks = posToks + tok.toText()
        }
    }
    if posToks != '' { props['mask-position'] = posToks }
    if sizePart != null && sizePart.length > 0 { props['mask-size'] = sizePart.toText() }
}

void func applyBackgroundPositionShorthand(props:map[text], value:ascii) {
    // One layer per comma, and each longhand keeps the same list, so a
    // page with several background images positions each of them
    // (Backgrounds and Borders 3 §3.10).
    // Named bgLayerList rather than `layers`: a local that shares a name
    // with a function anywhere in the program -- including a test's --
    // resolves to the function, and the namespace is global across
    // every imported file (FINDINGS.md, finding 9).
    arr[ascii] bgLayerList = splitTopLevelCommas(value)
    if bgLayerList.length == 0 { return }
    text xs = ''
    text ys = ''
    for int i = 0, i < bgLayerList.length, i++ {
        splitBackgroundPosition(asciiTrim(bgLayerList[i]))
        if bgPosXOut == '' && bgPosYOut == '' { continue }
        if xs != '' { xs = xs + ', '  ys = ys + ', ' }
        xs = xs + bgPosXOut
        ys = ys + bgPosYOut
    }
    if xs == '' { return }
    props['background-position-x'] = xs.toAscii()
    props['background-position-y'] = ys.toAscii()
}

// Which way the inline axis runs for the element these matches belong
// to. The list is sorted by weight, so the last `direction` in it is the
// one that wins; a value that is neither keyword -- `inherit`, or
// anything unparseable -- leaves the parent's answer standing, which is
// what the computed value does with it too.
//
// This has to be answered before the declarations are applied, because
// applying `margin-inline-start` means choosing an edge. A page that
// never mentions `direction` or carries a `dir` skips it entirely.
bool func matchedDirectionRtl(matches:arr[Match], parentRtl:bool) {
    bool rtl = parentRtl
    for int i = 0, i < matches.length, i++ {
        if matches[i].decl.name != 'direction' { continue }
        ascii v = asciiLower(asciiTrim(matches[i].decl.value))
        if v == 'rtl' { rtl = true }
        else if v == 'ltr' { rtl = false }
    }
    return rtl
}

// One of the WM_ values from a keyword, or -1 for anything this engine
// does not recognise, which leaves the inherited mode standing.
int func writingModeKeyword(v:ascii) {
    if v == 'horizontal-tb' { return WM_HORIZONTAL_TB }
    if v == 'vertical-rl' { return WM_VERTICAL_RL }
    if v == 'vertical-lr' { return WM_VERTICAL_LR }
    if v == 'sideways-rl' { return WM_SIDEWAYS_RL }
    if v == 'sideways-lr' { return WM_SIDEWAYS_LR }
    // The two SVG spellings CSS Writing Modes 4 §3.1 keeps as aliases.
    if v == 'tb' || v == 'tb-rl' { return WM_VERTICAL_RL }
    return -1
}

// The same question `matchedDirectionRtl` answers, for `writing-mode`,
// and asked at the same point and for the same reason.
int func matchedWritingMode(matches:arr[Match], parentMode:int) {
    int wm = parentMode
    for int i = 0, i < matches.length, i++ {
        if matches[i].decl.name != 'writing-mode' { continue }
        int k = writingModeKeyword(asciiLower(asciiTrim(matches[i].decl.value)))
        if k >= 0 { wm = k }
    }
    return wm
}

// The weight of a declaration in the user-agent origin that is not
// important: `originRank` gives it 0, and everything else at least 1,
// so one comparison says which side of the origin boundary a match
// falls on. An important user-agent declaration ranks above every
// author one and so wins outright, which is why `revert` never has to
// roll back past it.
const int UA_WEIGHT_LIMIT = 10000000000000000

// Whether a declaration's value is one of the two rollback keywords.
// They roll back to different places -- `revert` to the previous origin
// and `revert-layer` to the previous layer of this one -- so the two are
// told apart where they are resolved and taken together only where the
// question is whether the page uses either.
bool func declIsRevertOnly(v:ascii) {
    if v == null { return false }
    return asciiLower(asciiTrim(v)) == 'revert'
}

bool func declIsRevertLayer(v:ascii) {
    if v == null { return false }
    return asciiLower(asciiTrim(v)) == 'revert-layer'
}

bool func declIsRevert(v:ascii) {
    return declIsRevertOnly(v) || declIsRevertLayer(v)
}

// The tier a match falls in, which is the origin and the layer packed
// together: `matchWeight` multiplies `originRank` by this and adds the
// specificity and the source order under it, so dividing takes the rank
// back out. A change in it is a layer boundary, or an origin one.
int func matchRankOf(weight:int) {
    return Math.floorDiv(weight, UA_WEIGHT_LIMIT)
}

// A property map copied, because a snapshot has to outlive the writes
// that follow it.
map[text] func copyProps(props:map[text]) {
    map[text] out = {}
    arr[text] ks = props.keys()
    for int i = 0, i < ks.length, i++ { out[ks[i]] = props[ks[i]] }
    return out
}

// The declarations of one element, applied in cascade order, with
// `revert` resolved.
//
// `revert` rolls a property back to the value the previous origin gave
// it (Cascade 4 §7.4), so what it needs is that origin's answer kept
// apart from the winner. The matches arrive sorted, so the user-agent
// origin's declarations are exactly the ones before the first weight at
// or above the boundary: copying `props` there is the whole of the
// bookkeeping, and it is done only on a page that says `revert`.
//
// Resolving afterwards rather than at the declaration is what makes a
// shorthand work: `applyDecl` has already expanded it into longhands by
// then, and each of those carries the keyword.
void func applyMatches(props:map[text], matches:arr[Match]) {
    if !anyRevert {
        for int i = 0, i < matches.length, i++ {
            applyDecl(props, matches[i].decl.name, matches[i].decl.value)
        }
        return
    }
    revertBase = {}
    revertBaseTaken = false
    layerBase = {}
    int curRank = 0 - 1
    for int i = 0, i < matches.length, i++ {
        int rank = matchRankOf(matches[i].weight)
        if rank != curRank {
            // A layer has ended. Whatever it left saying `revert-layer`
            // is resolved now, against the map as it stood before that
            // layer began -- which is the only moment that map is still
            // to hand.
            if curRank >= 0 { resolveRevertLayer(props) }
            layerBase = copyProps(props)
            curRank = rank
        }
        if !revertBaseTaken && matches[i].weight >= UA_WEIGHT_LIMIT {
            revertBase = copyProps(props)
            revertBaseTaken = true
        }
        applyDecl(props, matches[i].decl.name, matches[i].decl.value)
    }
    if curRank >= 0 { resolveRevertLayer(props) }
    // A `revert` is resolved last, because it rolls back past every
    // layer to the origin below. One still in the map came from the
    // user-agent origin itself, or found nothing to roll back to; either
    // way it is `unset`, which is what removing the declaration leaves.
    arr[text] names = props.keys()
    for int i = 0, i < names.length, i++ {
        // The entry goes through a `text` local first: a `text` made
        // from a map entry is a private copy where an `ascii` one would
        // alias it (FINDINGS.md, "ascii aliasing").
        text raw = props[names[i]]
        if !declIsRevertOnly(raw.toAscii()) { continue }
        if revertBase[names[i]] == null { delete props[names[i]] }
        else { props[names[i]] = revertBase[names[i]] }
    }
}

// Every `revert-layer` in the map, replaced by what the layer below
// this one left -- or removed, which is `unset`, where that layer said
// nothing.
void func resolveRevertLayer(props:map[text]) {
    arr[text] names = props.keys()
    for int i = 0, i < names.length, i++ {
        text raw = props[names[i]]
        if !declIsRevertLayer(raw.toAscii()) { continue }
        if layerBase[names[i]] == null { delete props[names[i]] }
        else { props[names[i]] = layerBase[names[i]] }
    }
}

const int CSSWIDE_NONE = 0
const int CSSWIDE_INHERIT = 1
const int CSSWIDE_INITIAL = 2
const int CSSWIDE_UNSET = 3

// A CSS-wide keyword -- `inherit`, `initial`, `unset`, `revert` or
// `revert-layer` -- on a shorthand sets **every one of its longhands**
// to that keyword. The four-sides shorthands get this free, because
// they pass their value through to each side unparsed; the ones that
// parse a value into parts have to be told, and those that were not
// read the keyword as a font family, a colour or a list marker and set
// the rest to their defaults. `font: revert` is what found it: it gave
// font-weight `normal` where the rollback should have reached the
// user-agent sheet's `bold`, and a sweep of every shorthand found four
// more (todo.md).
//
// The test comes before the longhand names are written out, and the
// names are written out rather than passed as a list, because both an
// array literal and a list parameter are an allocation on every
// shorthand declaration on the page -- and a page that never says one
// of these keywords would pay it on all of them.
bool func declIsCssWide(value:ascii) {
    return cssWideKeyword(value) != CSSWIDE_NONE || declIsRevert(value)
}


// The logical-to-physical table for a vertical writing mode. The
// horizontal table below is a renaming of the inline edges only, and
// cannot be extended in place, because a vertical mode moves the BLOCK
// edges as well: `block-start` is a side rather than the top, and
// `inline-start` is the top rather than a side. Chromium's answers are
// in todo.md -- `inline-size` sets the height, `block-size` the width,
// `margin-inline-start` the top margin.
//
// A page in the ordinary horizontal mode never calls this: the caller
// tests one integer, which is zero unless some element on the document
// declared a vertical mode.
// `sideways-lr` runs its inline axis bottom to top, so its inline-start
// is the bottom edge where every other vertical mode's is the top.
bool func wmInlineUpwards() { return cascadeApplyWM == WM_SIDEWAYS_LR }
bool func wmBlockRightToLeft() {
    return cascadeApplyWM == WM_VERTICAL_RL || cascadeApplyWM == WM_SIDEWAYS_RL
}
text func wmInlineStartSide() { return cascadeApplyRtl != wmInlineUpwards() ? 'bottom' : 'top' }
text func wmInlineEndSide() { return cascadeApplyRtl != wmInlineUpwards() ? 'top' : 'bottom' }
text func wmBlockStartSide() { return wmBlockRightToLeft() ? 'right' : 'left' }
text func wmBlockEndSide() { return wmBlockRightToLeft() ? 'left' : 'right' }

// The four physical sides in whichever writing mode and direction is in
// force. `wmInlineStartSide` and its three neighbours answer for a
// vertical mode only, because that is the only place `wmPhysicalName`
// calls them; a two-value logical shorthand needs the answer in both,
// since it names its two sides itself rather than going through the
// longhand table. Nothing calls these unless such a shorthand is
// declared, so a page without one pays nothing.
text func logicalInlineStartSide() {
    if cascadeApplyWM != WM_HORIZONTAL_TB { return wmInlineStartSide() }
    return cascadeApplyRtl ? 'right' : 'left'
}
text func logicalInlineEndSide() {
    if cascadeApplyWM != WM_HORIZONTAL_TB { return wmInlineEndSide() }
    return cascadeApplyRtl ? 'left' : 'right'
}
text func logicalBlockStartSide() {
    if cascadeApplyWM != WM_HORIZONTAL_TB { return wmBlockStartSide() }
    return 'top'
}
text func logicalBlockEndSide() {
    if cascadeApplyWM != WM_HORIZONTAL_TB { return wmBlockEndSide() }
    return 'bottom'
}

text func wmPhysicalName(name:text) {
    // The two sizes exchange axes outright.
    if name == 'inline-size' { return 'height' }
    if name == 'block-size' { return 'width' }
    if name == 'min-inline-size' { return 'min-height' }
    if name == 'max-inline-size' { return 'max-height' }
    if name == 'min-block-size' { return 'min-width' }
    if name == 'max-block-size' { return 'max-width' }
    if name == 'overflow-block' { return 'overflow-x' }
    if name == 'overflow-inline' { return 'overflow-y' }
    if name == 'contain-intrinsic-inline-size' { return 'contain-intrinsic-height' }
    if name == 'contain-intrinsic-block-size' { return 'contain-intrinsic-width' }
    if name == 'overscroll-behavior-inline' { return 'overscroll-behavior-y' }
    if name == 'overscroll-behavior-block' { return 'overscroll-behavior-x' }
    // The insets name a side on their own.
    if name == 'inset-block-start' { return wmBlockStartSide() }
    if name == 'inset-block-end' { return wmBlockEndSide() }
    if name == 'inset-inline-start' { return wmInlineStartSide() }
    if name == 'inset-inline-end' { return wmInlineEndSide() }
    // A corner is a block side and an inline side, and the physical
    // name puts the horizontal one second: in `vertical-rl` the
    // start-start corner is the block-start side (the right) and the
    // inline-start side (the top), which is `border-top-right-radius`.
    if name == 'border-start-start-radius' { return `border-${wmInlineStartSide()}-${wmBlockStartSide()}-radius` }
    if name == 'border-start-end-radius' { return `border-${wmInlineEndSide()}-${wmBlockStartSide()}-radius` }
    if name == 'border-end-start-radius' { return `border-${wmInlineStartSide()}-${wmBlockEndSide()}-radius` }
    if name == 'border-end-end-radius' { return `border-${wmInlineEndSide()}-${wmBlockEndSide()}-radius` }
    if name == 'margin-inline-start' { return `margin-${wmInlineStartSide()}` }
    if name == 'margin-inline-end' { return `margin-${wmInlineEndSide()}` }
    if name == 'margin-block-start' { return `margin-${wmBlockStartSide()}` }
    if name == 'margin-block-end' { return `margin-${wmBlockEndSide()}` }
    if name == 'padding-inline-start' { return `padding-${wmInlineStartSide()}` }
    if name == 'padding-inline-end' { return `padding-${wmInlineEndSide()}` }
    if name == 'padding-block-start' { return `padding-${wmBlockStartSide()}` }
    if name == 'padding-block-end' { return `padding-${wmBlockEndSide()}` }
    if name == 'scroll-padding-inline-start' { return `scroll-padding-${wmInlineStartSide()}` }
    if name == 'scroll-padding-inline-end' { return `scroll-padding-${wmInlineEndSide()}` }
    if name == 'scroll-padding-block-start' { return `scroll-padding-${wmBlockStartSide()}` }
    if name == 'scroll-padding-block-end' { return `scroll-padding-${wmBlockEndSide()}` }
    if name == 'scroll-margin-inline-start' { return `scroll-margin-${wmInlineStartSide()}` }
    if name == 'scroll-margin-inline-end' { return `scroll-margin-${wmInlineEndSide()}` }
    if name == 'scroll-margin-block-start' { return `scroll-margin-${wmBlockStartSide()}` }
    if name == 'scroll-margin-block-end' { return `scroll-margin-${wmBlockEndSide()}` }
    if name == 'border-inline-start' { return `border-${wmInlineStartSide()}` }
    if name == 'border-inline-end' { return `border-${wmInlineEndSide()}` }
    if name == 'border-block-start' { return `border-${wmBlockStartSide()}` }
    if name == 'border-block-end' { return `border-${wmBlockEndSide()}` }
    if name == 'border-inline-start-width' { return `border-${wmInlineStartSide()}-width` }
    if name == 'border-inline-end-width' { return `border-${wmInlineEndSide()}-width` }
    if name == 'border-block-start-width' { return `border-${wmBlockStartSide()}-width` }
    if name == 'border-block-end-width' { return `border-${wmBlockEndSide()}-width` }
    if name == 'border-inline-start-style' { return `border-${wmInlineStartSide()}-style` }
    if name == 'border-inline-end-style' { return `border-${wmInlineEndSide()}-style` }
    if name == 'border-block-start-style' { return `border-${wmBlockStartSide()}-style` }
    if name == 'border-block-end-style' { return `border-${wmBlockEndSide()}-style` }
    if name == 'border-inline-start-color' { return `border-${wmInlineStartSide()}-color` }
    if name == 'border-inline-end-color' { return `border-${wmInlineEndSide()}-color` }
    if name == 'border-block-start-color' { return `border-${wmBlockStartSide()}-color` }
    if name == 'border-block-end-color' { return `border-${wmBlockEndSide()}-color` }
    return name
}

void func applyDecl(props:map[text], nameIn:text, value:ascii) {
    text name = nameIn
    // `all` (Cascade 4 §3.2) sets every property at once to one
    // CSS-wide keyword, and overrides every declaration before it in the
    // block -- so those are dropped here and the ones after it are
    // applied over the top as usual.
    //
    // `initial` is recorded for computeStyleValues, which then computes
    // the element as though it had no parent. `unset` and `revert` need
    // nothing beyond the dropping: taking the parent's value for an
    // inherited property and the initial value for every other one is
    // what the ordinary cascade already does, and `revert` behaves as
    // `unset` here for the reason cssWideKeyword gives. `inherit` is not
    // honoured -- giving a non-inherited property the parent's value
    // needs a field-by-field copy of the parent style, and a
    // hand-written list of fields is the thing that rotted in
    // styleDigest (todo.md).
    if name == 'all' {
        int allKw = cssWideKeyword(value)
        if allKw == CSSWIDE_NONE { return }
        arr[text] had = props.keys()
        for int i = 0, i < had.length, i++ {
            // `direction` and `unicode-bidi` are the two the standard
            // leaves alone, because they carry the document's meaning
            // rather than its presentation.
            if had[i] == 'direction' || had[i] == 'unicode-bidi' { continue }
            delete props[had[i]]
        }
        if allKw == CSSWIDE_INITIAL { setProp(props, 'all', value) }
        // `all: revert` puts the previous origin's declarations back and
        // `all: revert-layer` the previous layer's, which is what the
        // drop above took away.
        if declIsRevert(value) {
            map[text] back = declIsRevertLayer(value) ? layerBase : revertBase
            arr[text] base = back.keys()
            for int i = 0, i < base.length, i++ {
                if base[i] == 'direction' || base[i] == 'unicode-bidi' { continue }
                props[base[i]] = back[base[i]]
            }
        }
        return
    }
    // `display` is validated here rather than where it is read, because
    // by then the declaration it beat is gone. See isDisplayKeyword. A
    // CSS-wide keyword is a valid value for every property, so it goes
    // through: `display: revert` has to reach the map for the rollback
    // to find it, and `display: inherit` for the resolver to.
    if name == 'display' && !isDisplayKeyword(value)
        && cssWideKeyword(value) == CSSWIDE_NONE { return }
    // The logical border shorthands are renamed before anything else,
    // because the shorthand dispatch below reads the name: renaming
    // afterwards left `border-block-start` as a longhand nobody handles.
    if cascadeApplyWM != WM_HORIZONTAL_TB { name = wmPhysicalName(name) }
    if name == 'border-block-start' { name = 'border-top' }
    else if name == 'border-block-end' { name = 'border-bottom' }
    else if name == 'border-inline-start' { name = cascadeApplyRtl ? 'border-right' : 'border-left' }
    else if name == 'border-inline-end' { name = cascadeApplyRtl ? 'border-left' : 'border-right' }
    else if name == 'border-block' {
        applyBorderShorthand(props, [logicalBlockStartSide(), logicalBlockEndSide()], value)
        return
    } else if name == 'border-inline' {
        applyBorderShorthand(props, [logicalInlineStartSide(), logicalInlineEndSide()], value)
        return
    }
    if name == 'scroll-padding' || name == 'scroll-margin' {
        applyFourSides(props, name, '', value)
        return
    }
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
    if name == 'background-position' {
        applyBackgroundPositionShorthand(props, value)
        return
    }
    if name == 'mask' {
        applyMaskShorthand(props, value)
        return
    }
    // `container: <name> [ / <type> ]` (CSS Conditional 4 §2.3). A
    // shorthand sets both longhands, so it is expanded here for the
    // same reason `background-position` is: cascade order has to decide
    // between it and a longhand written either side of it.
    if name == 'container' {
        int slash = asciiIndexOf(value, '/', 0)
        ascii namePart = slash < 0 ? asciiTrim(value) : asciiTrim(value.slice(0, slash))
        props['container-name'] = namePart.length > 0 ? dup(namePart) : 'none'.toAscii()
        if slash < 0 {
            props['container-type'] = 'normal'.toAscii()
        } else {
            ascii typePart = asciiTrim(value.slice(slash + 1, value.length))
            props['container-type'] = typePart.length > 0 ? dup(typePart) : 'normal'.toAscii()
        }
        return
    }
    // `grid-column` and `grid-row` are `<start> / <end>`, and a single
    // value sets the start alone.
    // `border-image` is source, slice, width, outset and repeat, with
    // the three lengths separated by slashes after the slice.
    // `text-emphasis` is a style and a colour in either order.
    if name == 'text-emphasis' {
        arr[ascii] et = cssTokens(value)
        arr[ascii] styleToks = []
        for int i = 0, i < et.length, i++ {
            ascii tok = asciiLower(et[i])
            if tok == 'none' || tok == 'filled' || tok == 'open' || tok == 'dot'
                || tok == 'circle' || tok == 'double-circle' || tok == 'triangle'
                || tok == 'sesame' {
                styleToks.push(et[i])
                continue
            }
            if et[i].length >= 2 {
                int first = et[i].charCodeAt(0)
                if first == CH_QUOTE || first == CH_APOS { styleToks.push(et[i])  continue }
            }
            setProp(props, 'text-emphasis-color', et[i])
        }
        if styleToks.length > 0 {
            text joined = ''
            for int i = 0, i < styleToks.length, i++ {
                joined = joined + (i > 0 ? ' ' : '') + styleToks[i].toText()
            }
            setProp(props, 'text-emphasis-style', joined.toAscii())
        }
        return
    }
    // `overflow` is a shorthand for the two axes: one value says both,
    // two say the horizontal and then the vertical (CSS Overflow 3 §3).
    if name == 'overflow' {
        arr[ascii] ot = cssTokens(value)
        if ot.length > 0 {
            setProp(props, 'overflow-x', ot[0])
            setProp(props, 'overflow-y', ot.length > 1 ? ot[1] : ot[0])
        }
        return
    }
    if name == 'border-image' {
        arr[ascii] slashed = splitTopLevelSlash(value)
        arr[ascii] first = cssTokens(slashed[0])
        arr[ascii] sliceToks = []
        for int i = 0, i < first.length, i++ {
            ascii t = asciiLower(first[i])
            if asciiStartsWithLower(t, 'url(', 0) {
                setProp(props, 'border-image-source', first[i])
            } else if t == 'stretch' || t == 'repeat' || t == 'round' || t == 'space' {
                setProp(props, 'border-image-repeat', first[i])
            } else {
                sliceToks.push(first[i])
            }
        }
        if sliceToks.length > 0 {
            text joined = ''
            for int i = 0, i < sliceToks.length, i++ {
                joined = joined + (i > 0 ? ' ' : '') + sliceToks[i].toText()
            }
            setProp(props, 'border-image-slice', joined.toAscii())
        }
        if slashed.length > 1 { setProp(props, 'border-image-width', slashed[1]) }
        if slashed.length > 2 { setProp(props, 'border-image-outset', slashed[2]) }
        return
    }
    // `columns` is a width and a count in either order.
    if name == 'columns' {
        arr[ascii] ct = cssTokens(value)
        for int i = 0, i < ct.length, i++ {
            ascii t = asciiLower(ct[i])
            if t == 'auto' { continue }
            Len l = parseLength(t, 16)
            if l.kind == LEN_PX && asciiIndexOf(t, 'px'.toAscii(), 0) >= 0 {
                setProp(props, 'column-width', ct[i])
            } else {
                setProp(props, 'column-count', ct[i])
            }
        }
        return
    }
    if name == 'grid-column' || name == 'grid-row' {
        text axis = name == 'grid-column' ? 'column' : 'row'
        arr[ascii] halves = splitTopLevelSlash(value)
        if halves.length > 0 { setProp(props, `grid-${axis}-start`, halves[0]) }
        if halves.length > 1 { setProp(props, `grid-${axis}-end`, halves[1]) }
        return
    }
    if name == 'grid-area' {
        arr[ascii] parts = splitTopLevelSlash(value)
        // An omitted edge copies the one it mirrors when that one is a
        // name, and is otherwise automatic (Grid 1 §8.4). This is what
        // makes `grid-area: a` set all four edges, and it is the whole
        // of how an item lands in a named area.
        if parts.length > 0 { setProp(props, 'grid-row-start', parts[0]) }
        if parts.length > 1 { setProp(props, 'grid-column-start', parts[1]) }
        else if parts.length > 0 && gridEdgeIsName(parts[0]) {
            setProp(props, 'grid-column-start', parts[0])
        }
        if parts.length > 2 { setProp(props, 'grid-row-end', parts[2]) }
        else if parts.length > 0 && gridEdgeIsName(parts[0]) {
            setProp(props, 'grid-row-end', parts[0])
        }
        if parts.length > 3 { setProp(props, 'grid-column-end', parts[3]) }
        else if parts.length > 1 && gridEdgeIsName(parts[1]) {
            setProp(props, 'grid-column-end', parts[1])
        } else if parts.length == 1 && gridEdgeIsName(parts[0]) {
            setProp(props, 'grid-column-end', parts[0])
        }
        return
    }
    if name == 'list-style' {
        if declIsCssWide(value) {
            props['list-style-type'] = dup(value)
            props['list-style-position'] = dup(value)
            props['list-style-image'] = dup(value)
            return
        }
        arr[ascii] t = cssTokens(value)
        for int i = 0, i < t.length, i++ {
            ascii tok = asciiLower(t[i])
            if asciiStartsWithLower(tok, 'url(', 0) {
                setProp(props, 'list-style-image', t[i])
            } else if tok == 'inside' || tok == 'outside' {
                setProp(props, 'list-style-position', tok)
            } else if tok == 'none' || tok == 'disc' || tok == 'circle' || tok == 'square' || tok == 'decimal' || tok == 'lower-alpha' || tok == 'upper-alpha' || tok == 'lower-roman' || tok == 'upper-roman' {
                setProp(props, 'list-style-type', tok)
            }
        }
        return
    }
    // A vertical writing mode moves the block edges as well as the
    // inline ones, so its whole table is asked first and the horizontal
    // one below then finds a name already made physical. One integer
    // test, and zero on every page that never says `writing-mode`.
    if cascadeApplyWM != WM_HORIZONTAL_TB { name = wmPhysicalName(name) }
    if name == 'inline-size' { name = 'width' }
    if name == 'block-size' { name = 'height' }
    // The inline edges. `inline-start` is the left edge of a
    // left-to-right element and the right edge of a right-to-left one,
    // which is why these are resolved here, where the cascade order
    // between a logical declaration and its physical twin is still
    // intact, rather than afterwards over the finished property map.
    if name == 'margin-inline-start' { name = cascadeApplyRtl ? 'margin-right' : 'margin-left' }
    if name == 'margin-inline-end' { name = cascadeApplyRtl ? 'margin-left' : 'margin-right' }
    if name == 'padding-inline-start' { name = cascadeApplyRtl ? 'padding-right' : 'padding-left' }
    if name == 'padding-inline-end' { name = cascadeApplyRtl ? 'padding-left' : 'padding-right' }
    if name == 'margin-block-start' { name = 'margin-top' }
    if name == 'margin-block-end' { name = 'margin-bottom' }
    // The rest of the logical box. These lines are the LEFT-TO-RIGHT
    // HORIZONTAL answers, and nothing more: `inline-start` is the left
    // edge and `block-start` the top. A vertical mode never reaches
    // them, because `wmPhysicalName` above has already turned the name
    // into a physical one that none of these tests matches.
    if name == 'padding-block-start' { name = 'padding-top' }
    if name == 'padding-block-end' { name = 'padding-bottom' }
    // The scroll box's two families take the same aliases, because a
    // snapport's padding and a snap area's margin are the box's own
    // edges under other names (Scroll Snap 1 §6.2, §6.3).
    if name == 'scroll-padding-block-start' { name = 'scroll-padding-top' }
    if name == 'scroll-padding-block-end' { name = 'scroll-padding-bottom' }
    if name == 'scroll-padding-inline-start' {
        name = cascadeApplyRtl ? 'scroll-padding-right' : 'scroll-padding-left'
    }
    if name == 'scroll-padding-inline-end' {
        name = cascadeApplyRtl ? 'scroll-padding-left' : 'scroll-padding-right'
    }
    if name == 'scroll-margin-block-start' { name = 'scroll-margin-top' }
    if name == 'scroll-margin-block-end' { name = 'scroll-margin-bottom' }
    if name == 'scroll-margin-inline-start' {
        name = cascadeApplyRtl ? 'scroll-margin-right' : 'scroll-margin-left'
    }
    if name == 'scroll-margin-inline-end' {
        name = cascadeApplyRtl ? 'scroll-margin-left' : 'scroll-margin-right'
    }
    if name == 'inset-block-start' { name = 'top' }
    if name == 'inset-block-end' { name = 'bottom' }
    if name == 'inset-inline-start' { name = cascadeApplyRtl ? 'right' : 'left' }
    if name == 'inset-inline-end' { name = cascadeApplyRtl ? 'left' : 'right' }
    if name == 'min-inline-size' { name = 'min-width' }
    if name == 'max-inline-size' { name = 'max-width' }
    if name == 'min-block-size' { name = 'min-height' }
    if name == 'max-block-size' { name = 'max-height' }
    if name == 'overflow-block' { name = 'overflow-y' }
    if name == 'overflow-inline' { name = 'overflow-x' }
    if name == 'border-start-start-radius' { name = cascadeApplyRtl ? 'border-top-right-radius' : 'border-top-left-radius' }
    if name == 'border-start-end-radius' { name = cascadeApplyRtl ? 'border-top-left-radius' : 'border-top-right-radius' }
    if name == 'border-end-start-radius' { name = cascadeApplyRtl ? 'border-bottom-right-radius' : 'border-bottom-left-radius' }
    if name == 'border-end-end-radius' { name = cascadeApplyRtl ? 'border-bottom-left-radius' : 'border-bottom-right-radius' }
    if name == 'border-block-start-width' { name = 'border-top-width' }
    if name == 'border-block-end-width' { name = 'border-bottom-width' }
    if name == 'border-inline-start-width' { name = cascadeApplyRtl ? 'border-right-width' : 'border-left-width' }
    if name == 'border-inline-end-width' { name = cascadeApplyRtl ? 'border-left-width' : 'border-right-width' }
    if name == 'border-block-start-style' { name = 'border-top-style' }
    if name == 'border-block-end-style' { name = 'border-bottom-style' }
    if name == 'border-inline-start-style' { name = cascadeApplyRtl ? 'border-right-style' : 'border-left-style' }
    if name == 'border-inline-end-style' { name = cascadeApplyRtl ? 'border-left-style' : 'border-right-style' }
    if name == 'border-block-start-color' { name = 'border-top-color' }
    if name == 'border-block-end-color' { name = 'border-bottom-color' }
    if name == 'border-inline-start-color' { name = cascadeApplyRtl ? 'border-right-color' : 'border-left-color' }
    if name == 'border-inline-end-color' { name = cascadeApplyRtl ? 'border-left-color' : 'border-right-color' }
    if name == 'inset' {
        applyFourSidesInset(props, value)
        return
    }
    if name == 'inset-block' || name == 'inset-inline' {
        arr[ascii] t = cssTokens(value)
        if t.length == 0 { return }
        ascii a = dup(t[0])
        ascii b = dup(t.length > 1 ? t[1] : t[0])
        // The pair is start then end, and which physical side each is
        // depends on the writing mode and on `direction` -- exactly as
        // it does for the longhands, which reach the same answer
        // through `wmPhysicalName` and the horizontal table below.
        if name == 'inset-block' {
            setProp(props, logicalBlockStartSide(), a)
            setProp(props, logicalBlockEndSide(), b)
        } else {
            setProp(props, logicalInlineStartSide(), a)
            setProp(props, logicalInlineEndSide(), b)
        }
        return
    }
    if name == 'margin-inline' || name == 'padding-inline' || name == 'margin-block' || name == 'padding-block' {
        arr[ascii] t = cssTokens(value)
        if t.length == 0 { return }
        ascii a = dup(t[0])
        ascii b = dup(t.length > 1 ? t[1] : t[0])
        bool inline = name == 'margin-inline' || name == 'padding-inline'
        text base = asciiStartsWith(name.toAscii(), 'margin', 0) ? 'margin' : 'padding'
        setProp(props, `${base}-${inline ? logicalInlineStartSide() : logicalBlockStartSide()}`, a)
        setProp(props, `${base}-${inline ? logicalInlineEndSide() : logicalBlockEndSide()}`, b)
        return
    }
    // `text-decoration` is the shorthand for the line, the style, the
    // colour and the thickness (Text Decoration 4 sec. 2.5), and it is
    // expanded into those four keys rather than kept as a fifth. Two
    // keys meant the reader applied the shorthand first and the
    // longhand afterwards, so the longhand won whatever the stylesheet
    // said: `text-decoration-line: underline; text-decoration:
    // overline` gave underline where Chromium gives overline, and the
    // other order gave underline too. One key, and the cascade decides.
    //
    // An omitted longhand takes its initial value, which is what the
    // deletes are for: Chromium answers `text-decoration-color: red;
    // text-decoration: underline` with the text's own colour, not red.
    // Deleting is how a declaration map says "initial" -- a weaker
    // declaration of the same longhand is what the shorthand resets.
    if name == 'text-decoration' {
        if declIsCssWide(value) {
            props['text-decoration-line'] = dup(value)
            props['text-decoration-style'] = dup(value)
            props['text-decoration-color'] = dup(value)
            props['text-decoration-thickness'] = dup(value)
            return
        }
        if props['text-decoration-line'] != null { delete props['text-decoration-line'] }
        if props['text-decoration-style'] != null { delete props['text-decoration-style'] }
        if props['text-decoration-color'] != null { delete props['text-decoration-color'] }
        if props['text-decoration-thickness'] != null { delete props['text-decoration-thickness'] }
        arr[ascii] dt = cssTokens(value)
        text lineToks = ''
        for int i = 0, i < dt.length, i++ {
            ascii t = asciiLower(dt[i])
            if t == 'none' || t == 'underline' || t == 'line-through'
                || t == 'overline' || t == 'blink' {
                lineToks = lineToks + (lineToks.length > 0 ? ' ' : '') + t.toText()
                continue
            }
            if decorationStyleKeyword(t) >= 0 {
                setProp(props, 'text-decoration-style', t)
                continue
            }
            // A thickness is `auto`, `from-font` or a length, and a
            // length is told from a colour by its first character
            // rather than by parsing it: `parseLength` answers `auto`
            // for everything it cannot read, so asking it would make
            // every colour keyword a thickness.
            int c0 = t.length > 0 ? t.charCodeAt(0) : 0
            if t == 'auto' || t == 'from-font' || isDigitCode(c0)
                || c0 == CH_DOT || c0 == CH_PLUS || c0 == CH_MINUS {
                setProp(props, 'text-decoration-thickness', t)
                continue
            }
            setProp(props, 'text-decoration-color', dt[i])
        }
        if lineToks.length > 0 { setProp(props, 'text-decoration-line', lineToks.toAscii()) }
        return
    }
    // `white-space` is the shorthand for `white-space-collapse` and
    // `text-wrap-mode` (CSS Text 4 sec. 3), expanded here for the same
    // reason `text-decoration` is: read beside its longhands with the
    // shorthand first, the longhand won whatever the stylesheet said,
    // and `white-space-collapse: preserve; white-space: normal` gave
    // preserve where Chromium gives collapse.
    //
    // The comparison is written plain rather than behind a flag because
    // the user-agent sheet says `white-space` on `pre`, `textarea` and
    // `nobr`, so the flag would be true on every page it was asked of.
    if name == 'white-space' {
        if declIsCssWide(value) {
            props['white-space-collapse'] = dup(value)
            props['text-wrap-mode'] = dup(value)
            return
        }
        ascii wsk = asciiLower(asciiTrim(value))
        text wsCollapse = ''
        text wsMode = ''
        if wsk == 'normal' { wsCollapse = 'collapse'  wsMode = 'wrap' }
        else if wsk == 'pre' { wsCollapse = 'preserve'  wsMode = 'nowrap' }
        else if wsk == 'nowrap' { wsCollapse = 'collapse'  wsMode = 'nowrap' }
        else if wsk == 'pre-wrap' { wsCollapse = 'preserve'  wsMode = 'wrap' }
        else if wsk == 'pre-line' { wsCollapse = 'preserve-breaks'  wsMode = 'wrap' }
        else if wsk == 'break-spaces' { wsCollapse = 'break-spaces'  wsMode = 'wrap' }
        // An unknown keyword drops the whole declaration, so a longhand
        // written before it still stands.
        if wsCollapse.length == 0 { return }
        props['white-space-collapse'] = wsCollapse
        props['text-wrap-mode'] = wsMode
        return
    }
    // `text-wrap` is the shorthand for `text-wrap-mode` and
    // `text-wrap-style` (CSS Text 4 sec. 6.1). Its style half was read
    // out of the shorthand by applyTextWrapStyle and **its mode half
    // had no reader at all**, so `text-wrap: nowrap` did nothing
    // whatever. Both halves are written here, the one the shorthand
    // does not name at its initial value, so that the two shorthands
    // that share `text-wrap-mode` are decided by source order: written
    // either way round, `white-space: nowrap; text-wrap: wrap` and its
    // reverse give different answers in Chromium and could not here.
    if name == 'text-wrap' {
        if declIsCssWide(value) {
            props['text-wrap-mode'] = dup(value)
            props['text-wrap-style'] = dup(value)
            return
        }
        arr[ascii] twt = cssTokens(value)
        if twt.length == 0 || twt.length > 2 { return }
        text twMode = ''
        text twStyle = ''
        for int i = 0, i < twt.length, i++ {
            ascii twk = asciiLower(twt[i])
            if twk == 'wrap' || twk == 'nowrap' {
                if twMode.length > 0 { return }
                twMode = twk.toText()
                continue
            }
            if twk == 'auto' || twk == 'balance' || twk == 'pretty' || twk == 'stable' {
                if twStyle.length > 0 { return }
                twStyle = twk.toText()
                continue
            }
            return
        }
        props['text-wrap-mode'] = twMode.length > 0 ? twMode : 'wrap'
        props['text-wrap-style'] = twStyle.length > 0 ? twStyle : 'auto'
        return
    }
    // `place-items`, `place-content` and `place-self` are Box Alignment
    // 3's two-value shorthands (sec. 6): the first value is the block
    // axis and the second the inline one, and one value sets both.
    // Expanded here for the reason above -- one key per longhand, so
    // the cascade decides between a shorthand and a longhand written
    // either side of it -- and dropped whole when either value is a
    // keyword this engine does not know, because Chromium leaves
    // `align-items` alone for `place-items: end nonsense` where a
    // reader that took the first token and stopped would not.
    if anyPlaceShorthand && (name == 'place-items' || name == 'place-content'
                             || name == 'place-self') {
        text blockAxis = name == 'place-items' ? 'align-items'
            : (name == 'place-content' ? 'align-content' : 'align-self')
        text inlineAxis = name == 'place-items' ? 'justify-items'
            : (name == 'place-content' ? 'justify-content' : 'justify-self')
        if declIsCssWide(value) {
            props[blockAxis] = dup(value)
            props[inlineAxis] = dup(value)
            return
        }
        arr[ascii] pt = cssTokens(value)
        if pt.length == 0 || pt.length > 2 { return }
        // `dup` rather than a plain binding: an `ascii` local bound to
        // an array element aliases it, and the array is released at
        // the end of the call before the locals are, so releasing them
        // writes into freed memory (FINDINGS.md, "ascii aliases are
        // not retained"). Valgrind found this one; the ordinary run
        // printed the right answers.
        ascii firstVal = dup(pt[0])
        ascii secondVal = dup(pt.length > 1 ? pt[1] : pt[0])
        if parseAlignValue(firstVal, 0 - 1) < 0 { return }
        if parseAlignValue(secondVal, 0 - 1) < 0 { return }
        setProp(props, blockAxis, firstVal)
        setProp(props, inlineAxis, secondVal)
        return
    }
    // ---- the eight shorthands read from the map, now expanded --------
    //
    // An audit of the whole engine for the shape `text-decoration` had
    // -- a shorthand read from the declaration map in
    // computeStyleValues rather than expanded into its longhands here
    // -- turned up eight more. Every one of them got the cascade wrong
    // in exactly one direction, and which direction depended on where
    // the reader happened to sit: `flex-flow` is read after its
    // longhands and so always won, the other seven are read before
    // theirs and so always lost. Two of them carried a comment saying
    // the fixed order was the cascade's doing, which it was not.
    //
    // All eight are behind one flag, because the user-agent stylesheet
    // says none of them.
    if anyLateShorthand {
        // The two logical spellings are the same properties under other
        // names; these are the horizontal answers, a vertical mode
        // having been answered by `wmPhysicalName` above. Renamed
        // rather than
        // read separately, so that a logical declaration and its
        // physical twin occupy one key and the cascade decides between
        // them -- Chromium answers
        // `overscroll-behavior-x: contain; overscroll-behavior-inline: none`
        // with `none` and the reverse with `contain`, and reading one
        // family after the other can only get one of those right.
        if name == 'overscroll-behavior-inline' { name = 'overscroll-behavior-x' }
        else if name == 'overscroll-behavior-block' { name = 'overscroll-behavior-y' }
        // The same for the two `contain-intrinsic` spellings, which the
        // readers took in a fixed order too.
        if name == 'contain-intrinsic-inline-size' { name = 'contain-intrinsic-width' }
        else if name == 'contain-intrinsic-block-size' { name = 'contain-intrinsic-height' }
        // `column-rule` is a width, a style and a colour in any order,
        // exactly as `outline` and `border` are, and was read before
        // all three of its longhands. The hand-written list this audit
        // started from did not have it: it was found by asking the
        // source which property names are read with a helper and which
        // of those is a prefix of another.
        if name == 'column-rule' {
            if declIsCssWide(value) {
                props['column-rule-width'] = dup(value)
                props['column-rule-style'] = dup(value)
                props['column-rule-color'] = dup(value)
                return
            }
            if props['column-rule-width'] != null { delete props['column-rule-width'] }
            if props['column-rule-style'] != null { delete props['column-rule-style'] }
            if props['column-rule-color'] != null { delete props['column-rule-color'] }
            arr[ascii] crt = cssTokens(value)
            for int i = 0, i < crt.length, i++ {
                ascii crk = asciiLower(crt[i])
                if isLineStyleKeyword(crk) { setProp(props, 'column-rule-style', crk)  continue }
                if crk == 'thin' || crk == 'medium' || crk == 'thick' {
                    setProp(props, 'column-rule-width', crk)
                    continue
                }
                Len crl = parseLength(crk, 16)
                if crl.kind == LEN_PX { setProp(props, 'column-rule-width', crt[i])  continue }
                setProp(props, 'column-rule-color', crt[i])
            }
            return
        }
        // `contain-intrinsic-size` is the two axes, one value setting
        // both. A leading `auto` is the remembered-size form, whose
        // remembered size this engine never has, so the lengths after
        // it are what the longhands get; `none` is both axes back at
        // their initial value, which is what the deletes are.
        if name == 'contain-intrinsic-size' {
            if declIsCssWide(value) {
                props['contain-intrinsic-width'] = dup(value)
                props['contain-intrinsic-height'] = dup(value)
                return
            }
            arr[ascii] cit = intrinsicSizeLengths(value)
            if cit.length == 0 {
                if props['contain-intrinsic-width'] != null {
                    delete props['contain-intrinsic-width']
                }
                if props['contain-intrinsic-height'] != null {
                    delete props['contain-intrinsic-height']
                }
                return
            }
            if cit.length > 2 { return }
            ascii ciW = dup(cit[0])
            ascii ciH = dup(cit.length > 1 ? cit[1] : cit[0])
            setProp(props, 'contain-intrinsic-width', ciW)
            setProp(props, 'contain-intrinsic-height', ciH)
            return
        }
        // `border-radius` is the four corners across, optionally a
        // slash and the four down, each list filled by CSS's 1-to-4
        // rule. Each corner longhand takes `<x> <y>`, which is what
        // the corner reader already parses.
        if name == 'border-radius' {
            if declIsCssWide(value) {
                props['border-top-left-radius'] = dup(value)
                props['border-top-right-radius'] = dup(value)
                props['border-bottom-right-radius'] = dup(value)
                props['border-bottom-left-radius'] = dup(value)
                return
            }
            arr[ascii] brt = cssTokens(value)
            arr[text] across = []
            arr[text] down = []
            bool pastSlash = false
            for int i = 0, i < brt.length, i++ {
                if brt[i] == '/' { pastSlash = true  continue }
                if pastSlash { down.push(brt[i].toText()) }
                else { across.push(brt[i].toText()) }
            }
            if across.length == 0 || across.length > 4 || down.length > 4 { return }
            if down.length == 0 { down = across }
            arr[text] corners = ['border-top-left-radius', 'border-top-right-radius',
                                 'border-bottom-right-radius', 'border-bottom-left-radius']
            for int i = 0, i < 4, i++ {
                props[corners[i]] = radiusSlotText(across, i) + ' ' + radiusSlotText(down, i)
            }
            return
        }
        // `outline` is a width, a style and a colour in any order, and
        // the ones it does not name go back to their initial values --
        // which is what the deletes are: `outline-width: 9px;
        // outline: solid blue` is the medium width in Chromium.
        if name == 'outline' {
            if declIsCssWide(value) {
                props['outline-width'] = dup(value)
                props['outline-style'] = dup(value)
                props['outline-color'] = dup(value)
                return
            }
            if props['outline-width'] != null { delete props['outline-width'] }
            if props['outline-style'] != null { delete props['outline-style'] }
            if props['outline-color'] != null { delete props['outline-color'] }
            arr[ascii] olt = cssTokens(value)
            for int i = 0, i < olt.length, i++ {
                ascii olk = asciiLower(olt[i])
                if isLineStyleKeyword(olk) { setProp(props, 'outline-style', olk)  continue }
                if olk == 'thin' || olk == 'medium' || olk == 'thick' {
                    setProp(props, 'outline-width', olk)
                    continue
                }
                Len oll = parseLength(olk, 16)
                if oll.kind == LEN_PX { setProp(props, 'outline-width', olt[i])  continue }
                setProp(props, 'outline-color', olt[i])
            }
            return
        }
        // `flex` is `<grow> [<shrink>] [<basis>]` plus the three
        // keywords, and a bare number zeroes the basis -- which is what
        // makes `flex: 1` share the whole line rather than the slack.
        if name == 'flex' {
            if declIsCssWide(value) {
                props['flex-grow'] = dup(value)
                props['flex-shrink'] = dup(value)
                props['flex-basis'] = dup(value)
                return
            }
            ascii fxk = asciiLower(asciiTrim(value))
            if fxk == 'none' {
                props['flex-grow'] = '0'
                props['flex-shrink'] = '0'
                props['flex-basis'] = 'auto'
                return
            }
            if fxk == 'auto' {
                props['flex-grow'] = '1'
                props['flex-shrink'] = '1'
                props['flex-basis'] = 'auto'
                return
            }
            if fxk == 'initial' {
                props['flex-grow'] = '0'
                props['flex-shrink'] = '1'
                props['flex-basis'] = 'auto'
                return
            }
            arr[ascii] fxt = cssTokens(value)
            if fxt.length == 0 || fxt.length > 3 { return }
            text fxGrow = ''
            text fxShrink = ''
            text fxBasis = ''
            for int i = 0, i < fxt.length, i++ {
                ascii fxp = asciiLower(fxt[i])
                parseNumberAt(fxp, 0)
                if numOk && numEnd == fxp.length {
                    if fxGrow.length == 0 { fxGrow = fxp.toText()  continue }
                    if fxShrink.length == 0 { fxShrink = fxp.toText()  continue }
                    return
                }
                Len fxl = parseLength(fxp, 16)
                if fxl.kind == LEN_INVALID { return }
                if fxBasis.length > 0 { return }
                fxBasis = fxp.toText()
            }
            props['flex-grow'] = fxGrow.length > 0 ? fxGrow : '0'
            props['flex-shrink'] = fxShrink.length > 0 ? fxShrink : '1'
            props['flex-basis'] = fxBasis.length > 0 ? fxBasis : '0px'
            return
        }
        // `flex-flow` is a direction and a wrap in either order.
        if name == 'flex-flow' {
            if declIsCssWide(value) {
                props['flex-direction'] = dup(value)
                props['flex-wrap'] = dup(value)
                return
            }
            arr[ascii] fft = cssTokens(value)
            if fft.length == 0 || fft.length > 2 { return }
            text ffDir = ''
            text ffWrap = ''
            for int i = 0, i < fft.length, i++ {
                ascii ffk = asciiLower(fft[i])
                if ffk == 'row' || ffk == 'row-reverse' || ffk == 'column'
                    || ffk == 'column-reverse' {
                    if ffDir.length > 0 { return }
                    ffDir = ffk.toText()
                    continue
                }
                if ffk == 'wrap' || ffk == 'nowrap' || ffk == 'wrap-reverse' {
                    if ffWrap.length > 0 { return }
                    ffWrap = ffk.toText()
                    continue
                }
                return
            }
            props['flex-direction'] = ffDir.length > 0 ? ffDir : 'row'
            props['flex-wrap'] = ffWrap.length > 0 ? ffWrap : 'nowrap'
            return
        }
        // `gap` is the row gap then the column gap, and one value sets
        // both.
        if name == 'gap' {
            if declIsCssWide(value) {
                props['row-gap'] = dup(value)
                props['column-gap'] = dup(value)
                return
            }
            arr[ascii] gpt = cssTokens(value)
            if gpt.length == 0 || gpt.length > 2 { return }
            ascii gpRow = dup(gpt[0])
            ascii gpCol = dup(gpt.length > 1 ? gpt[1] : gpt[0])
            setProp(props, 'row-gap', gpRow)
            setProp(props, 'column-gap', gpCol)
            return
        }
        // `font-variant`'s one-keyword form is the only part of that
        // shorthand this engine has, so it reaches `font-variant-caps`
        // and every other value resets the caps -- which is what
        // Chromium does for `font-variant: common-ligatures`, and
        // differs from it only for a value that is invalid outright.
        if name == 'font-variant' {
            if declIsCssWide(value) {
                props['font-variant-caps'] = dup(value)
                return
            }
            ascii fvk = asciiLower(asciiTrim(value))
            if fvk == 'small-caps' || fvk == 'all-small-caps' {
                setProp(props, 'font-variant-caps', fvk)
            } else {
                props['font-variant-caps'] = 'normal'
            }
            return
        }
        // `text-box` is a trim and an edge (CSS Inline 3 sec. 4). An
        // edge written with no trim keyword means `trim-both`, which
        // is the one place the shorthand is not two values side by
        // side, and `normal` is both halves at their initial value.
        if name == 'text-box' {
            if declIsCssWide(value) {
                props['text-box-trim'] = dup(value)
                props['text-box-edge'] = dup(value)
                return
            }
            arr[ascii] tbt = cssTokens(value)
            if tbt.length == 0 || tbt.length > 3 { return }
            text tbTrimV = ''
            text tbEdgeV = ''
            for int i = 0, i < tbt.length, i++ {
                ascii tbk = asciiLower(tbt[i])
                if tbk == 'normal' {
                    if tbt.length != 1 { return }
                    if props['text-box-trim'] != null { delete props['text-box-trim'] }
                    if props['text-box-edge'] != null { delete props['text-box-edge'] }
                    props['text-box-trim'] = 'none'
                    return
                }
                if textBoxTrimKeyword(tbk) >= 0 {
                    if tbTrimV.length > 0 { return }
                    tbTrimV = tbk.toText()
                    continue
                }
                tbEdgeV = tbEdgeV.length > 0 ? tbEdgeV + ' ' + tbk.toText() : tbk.toText()
            }
            if props['text-box-trim'] != null { delete props['text-box-trim'] }
            if props['text-box-edge'] != null { delete props['text-box-edge'] }
            props['text-box-trim'] = tbTrimV.length > 0 ? tbTrimV : 'trim-both'
            if tbEdgeV.length > 0 { props['text-box-edge'] = tbEdgeV }
            return
        }
        // `overscroll-behavior` is the inline axis then the block one,
        // and one value sets both.
        if name == 'overscroll-behavior' {
            if declIsCssWide(value) {
                props['overscroll-behavior-x'] = dup(value)
                props['overscroll-behavior-y'] = dup(value)
                return
            }
            arr[ascii] obt = cssTokens(value)
            if obt.length == 0 || obt.length > 2 { return }
            ascii obX = dup(obt[0])
            ascii obY = dup(obt.length > 1 ? obt[1] : obt[0])
            if overscrollKeyword(asciiLower(obX)) < 0 { return }
            if overscrollKeyword(asciiLower(obY)) < 0 { return }
            setProp(props, 'overscroll-behavior-x', obX)
            setProp(props, 'overscroll-behavior-y', obY)
            return
        }
    }
    // CSS2's three page-break properties are the three fragmentation
    // properties under their older names (Fragmentation 3 §4.4), so a
    // declaration under an old name is applied under the new one rather
    // than implemented again. That makes the cascade between the two
    // spellings one property's cascade: two properties would let
    // whichever was read last always win, whatever the stylesheet said.
    // `always` is the old spelling of `page`, and every other value
    // carries over as itself.
    //
    // This sits at the end and not the top because `applyDecl` runs once
    // per matched declaration -- 11,614 of them on the benchmark page --
    // and three name comparisons up there cost a millisecond to every
    // page, whether or not it has ever said `page-break-anything`. Down
    // here every other property has already returned.
    //
    // Applied again under the modern name rather than renamed in place:
    // binding the value to a local `ascii` would alias a parameter the
    // compiler never retained (FINDINGS.md, "ascii aliases are not
    // retained"), which segfaults on the release at the end of the call.
    if anyPageBreak && (name == 'page-break-before' || name == 'page-break-after') {
        text modern = name == 'page-break-before' ? 'break-before' : 'break-after'
        if asciiLower(asciiTrim(value)) == 'always' {
            applyDecl(props, modern, 'page'.toAscii())
        } else {
            applyDecl(props, modern, value)
        }
        return
    }
    if anyPageBreak && name == 'page-break-inside' {
        applyDecl(props, 'break-inside', value)
        return
    }
    setProp(props, name, value)
}

// ---- computing --------------------------------------------------------

// ---- calc() -----------------------------------------------------------
//
// A calc() expression resolves to a length that may mix pixels and a
// percentage -- `calc(100% - 2em)` is the ordinary case -- so the result
// carries both parts and the percentage waits for the containing block.
//
// The grammar is the standard's: a sum of products, where a product
// multiplies or divides by a plain number, and a term is a number with
// a unit, a percentage, a bare number or a parenthesised sum. Anything
// else -- another function, a comparison, a unit this engine has no
// answer for -- makes the whole expression invalid, which is what the
// standard asks for and leaves the declaration to be dropped.

// The running value of a sub-expression: pixels plus a percentage.
struct CalcVal {
    px:float
    pct:float
    num:float       // a plain number, when this is not a length at all
    isNum:bool
    ok:bool
}

CalcVal calcBad

CalcVal func calcNumber(v:float) {
    CalcVal c
    c.num = v
    c.isNum = true
    c.ok = true
    return c
}

CalcVal func calcLength(px:float, pct:float) {
    CalcVal c
    c.px = px
    c.pct = pct
    c.ok = true
    return c
}

// The cursor the expression parser walks, as a pair of globals: Festina
// has no tuples and no out-parameters, so a recursive-descent parser
// either threads a struct or shares a position (FINDINGS.md, "no
// tuples").
ascii calcSrc
int calcPos = 0

void func calcSkipSpace() {
    while calcPos < calcSrc.length && isSpaceCode(calcSrc.charCodeAt(calcPos)) { calcPos++ }
}

// Which comparison function is at the cursor, and how long its name is
// including the opening parenthesis. Both answers come from the one
// test rather than the length being matched back to a name: `min` and
// `max` are the same length, and telling them apart afterwards is a
// place to get it wrong -- which is what the suite caught when this
// read the wrong character and every `min()` inside a `calc()` came
// out as the maximum.
int calcMinMaxOp = -1

int func calcMinMaxNameLen() {
    calcMinMaxOp = -1
    if asciiStartsWithLower(calcSrc, 'min(', calcPos) {
        calcMinMaxOp = MM_MIN
        return 4
    }
    if asciiStartsWithLower(calcSrc, 'max(', calcPos) {
        calcMinMaxOp = MM_MAX
        return 4
    }
    if asciiStartsWithLower(calcSrc, 'clamp(', calcPos) {
        calcMinMaxOp = MM_CLAMP
        return 6
    }
    return 0
}

CalcVal func calcParseTerm(fontSize:int) {
    calcSkipSpace()
    if calcPos >= calcSrc.length { return calcBad }
    int c = calcSrc.charCodeAt(calcPos)
    if c == CH_LPAREN {
        calcPos++
        CalcVal inner = calcParseSum(fontSize)
        calcSkipSpace()
        if calcPos >= calcSrc.length || calcSrc.charCodeAt(calcPos) != CH_RPAREN { return calcBad }
        calcPos++
        return inner
    }
    // a nested calc() is just a parenthesised sum
    if calcPos + 5 <= calcSrc.length && asciiLower(calcSrc.slice(calcPos, calcPos + 5)) == 'calc(' {
        calcPos = calcPos + 5
        CalcVal inner = calcParseSum(fontSize)
        calcSkipSpace()
        if calcPos >= calcSrc.length || calcSrc.charCodeAt(calcPos) != CH_RPAREN { return calcBad }
        calcPos++
        return inner
    }
    // A comparison inside an expression. It contributes one length, so
    // it is read with the ordinary parser and its answer taken --
    // except when that answer is itself a deferred comparison, which a
    // `CalcVal` has nowhere to put: a `CalcVal` is a pixel part and a
    // percentage part, and `min(50%, 100px)` is neither until the base
    // is known. That case is refused rather than approximated, and is
    // recorded as a limit (todo.md).
    int mmLen = calcMinMaxNameLen()
    if mmLen > 0 {
        int close = asciiMatchingParen(calcSrc, calcPos + mmLen - 1)
        if close < 0 { return calcBad }
        Len m = parseMinMax(calcSrc.slice(calcPos + mmLen, close), fontSize, calcMinMaxOp)
        calcPos = close + 1
        if m.kind == LEN_PX { return calcLength(m.v, 0.0) }
        if m.kind == LEN_PERCENT { return calcLength(0.0, m.v) }
        if m.kind == LEN_CALC { return calcLength(m.v, m.pct) }
        return calcBad
    }
    parseNumberAt(calcSrc, calcPos)
    if !numOk { return calcBad }
    float v = numValue
    int after = numEnd
    int unitEnd = after
    while unitEnd < calcSrc.length && (isAlphaCode(calcSrc.charCodeAt(unitEnd))
        || calcSrc.charCodeAt(unitEnd) == CH_PERCENT) { unitEnd++ }
    ascii unit = asciiLower(calcSrc.slice(after, unitEnd))
    calcPos = unitEnd
    if unit == '' { return calcNumber(v) }
    if unit == '%' { return calcLength(0.0, v) }
    // Reuse the ordinary unit table: a term is exactly one length.
    Len l = parseLength(`${v}${unit.toText()}`.toAscii(), fontSize)
    if l.kind == LEN_PX { return calcLength(l.v, 0.0) }
    return calcBad
}

CalcVal func calcParseProduct(fontSize:int) {
    CalcVal left = calcParseTerm(fontSize)
    if !left.ok { return calcBad }
    while true {
        calcSkipSpace()
        if calcPos >= calcSrc.length { return left }
        int c = calcSrc.charCodeAt(calcPos)
        if c != CH_STAR && c != CH_SLASH { return left }
        calcPos++
        CalcVal right = calcParseTerm(fontSize)
        if !right.ok { return calcBad }
        if c == CH_STAR {
            // exactly one side must be a plain number
            if left.isNum && !right.isNum {
                left = calcLength(right.px * left.num, right.pct * left.num)
            } else if right.isNum && !left.isNum {
                left = calcLength(left.px * right.num, left.pct * right.num)
            } else if left.isNum && right.isNum {
                left = calcNumber(left.num * right.num)
            } else { return calcBad }
        } else {
            if !right.isNum || right.num == 0.0 { return calcBad }
            if left.isNum { left = calcNumber(left.num / right.num) }
            else { left = calcLength(left.px / right.num, left.pct / right.num) }
        }
    }
    return left
}

CalcVal func calcParseSum(fontSize:int) {
    CalcVal left = calcParseProduct(fontSize)
    if !left.ok { return calcBad }
    while true {
        calcSkipSpace()
        if calcPos >= calcSrc.length { return left }
        int c = calcSrc.charCodeAt(calcPos)
        if c != CH_PLUS && c != CH_MINUS { return left }
        // `+` and `-` must be surrounded by whitespace, which is what
        // keeps `10px -5px` from reading as a subtraction.
        if calcPos == 0 || !isSpaceCode(calcSrc.charCodeAt(calcPos - 1)) { return calcBad }
        if calcPos + 1 >= calcSrc.length || !isSpaceCode(calcSrc.charCodeAt(calcPos + 1)) { return calcBad }
        calcPos++
        CalcVal right = calcParseProduct(fontSize)
        if !right.ok { return calcBad }
        if left.isNum != right.isNum { return calcBad }
        if left.isNum {
            left = calcNumber(c == CH_PLUS ? left.num + right.num : left.num - right.num)
        } else if c == CH_PLUS {
            left = calcLength(left.px + right.px, left.pct + right.pct)
        } else {
            left = calcLength(left.px - right.px, left.pct - right.pct)
        }
    }
    return left
}

// Evaluates `calc( ... )`, given the text between the parentheses.
Len func evaluateCalc(body:ascii, fontSize:int) {
    Len bad
    bad.kind = LEN_INVALID
    calcSrc = body
    calcPos = 0
    CalcVal r = calcParseSum(fontSize)
    calcSkipSpace()
    if !r.ok || r.isNum || calcPos < calcSrc.length { return bad }
    if r.pct == 0.0 { return lenPx(r.px) }
    if r.px == 0.0 { return lenPercent(r.pct) }
    return lenCalc(r.px, r.pct)
}

// `object-view-box: none | inset() | rect() | xywh()` (Images 4). The
// three functional forms name one rectangle over the image's own
// pixels in three ways, and Chromium computes all of them to an
// `inset()`; here they keep their own kind and are resolved together
// once the image's size is known.
ViewBox func parseViewBox(v:ascii, fontSize:int) {
    ViewBox vb
    vb.kind = VIEWBOX_NONE
    if v == null { return vb }
    ascii t = asciiLower(asciiTrim(v))
    if t == null || t.length == 0 || t == 'none' { return vb }
    if t.charCodeAt(t.length - 1) != CH_RPAREN { return vb }
    int open = asciiIndexOf(t, '('.toAscii(), 0)
    if open <= 0 { return vb }
    ascii fn = asciiTrim(t.slice(0, open))
    int kind = VIEWBOX_NONE
    if fn == 'inset' { kind = VIEWBOX_INSET }
    else if fn == 'rect' { kind = VIEWBOX_RECT }
    else if fn == 'xywh' { kind = VIEWBOX_XYWH }
    if kind == VIEWBOX_NONE { return vb }
    arr[ascii] args = asciiSplitSpace(asciiTrim(t.slice(open + 1, t.length - 1)))
    if args.length == 0 { return vb }
    arr[Len] got = []
    for int i = 0, i < args.length, i++ {
        // `rect()` writes `auto` for an edge that is not moved; it is
        // the same as a zero inset from that side here.
        if args[i] == 'auto' { got.push(lenPx(0.0))  continue }
        got.push(parseLength(args[i], fontSize))
    }
    if kind == VIEWBOX_XYWH {
        if got.length < 4 { return vb }
        vb.t = got[0]
        vb.r = got[1]
        vb.b = got[2]
        vb.l = got[3]
        vb.kind = kind
        return vb
    }
    if kind == VIEWBOX_RECT {
        if got.length < 4 { return vb }
        vb.t = got[0]
        vb.r = got[1]
        vb.b = got[2]
        vb.l = got[3]
        vb.kind = kind
        return vb
    }
    // `inset()` takes one to four values in the margin shorthand's
    // order: all, then vertical and horizontal, then top / horizontal /
    // bottom, then all four.
    vb.t = got[0]
    vb.r = got.length > 1 ? got[1] : got[0]
    vb.b = got.length > 2 ? got[2] : vb.t
    vb.l = got.length > 3 ? got[3] : vb.r
    vb.kind = kind
    return vb
}

// Splits on commas that are not inside parentheses, which is what a
// comparison's argument list needs and `asciiSplitChar` cannot do:
// `min(100px, max(10px, 300px))` has two arguments, not three. An
// empty piece is KEPT rather than dropped, because a trailing comma is
// invalid and dropping it would make it valid (measured, todo.md).
arr[ascii] func asciiSplitTopLevel(s:ascii, sep:int) {
    arr[ascii] out = []
    int depth = 0
    int start = 0
    int n = s.length
    for int i = 0, i <= n, i++ {
        if i == n {
            out.push(asciiTrim(s.slice(start, i)))
            break
        }
        int c = s.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN { depth-- }
        else if c == sep && depth == 0 {
            out.push(asciiTrim(s.slice(start, i)))
            start = i + 1
        }
    }
    return out
}

// One `min()`, `max()` or `clamp()`, as the length it resolves to.
//
// An argument list of nothing but pixels is folded here, because the
// answer cannot change: the result is an ordinary LEN_PX and works
// wherever a length works. Anything with a percentage in it is kept
// whole in the side table and answered in `resolveLen`, because the
// comparison happens after the percentage is resolved -- `min(50%,
// 100px)` is 100 against a 400px base and 50 against a 100px one.
Len func parseMinMax(inner:ascii, fontSize:int, op:int) {
    arr[ascii] args = asciiSplitTopLevel(inner, CH_COMMA)
    if args.length == 0 { return lenInvalid() }
    if op == MM_CLAMP ? args.length != 3 : args.length < 1 { return lenInvalid() }
    arr[int] kinds = []
    arr[float] vs = []
    arr[float] pcts = []
    bool allPx = true
    for int i = 0, i < args.length, i++ {
        if args[i].length == 0 { return lenInvalid() }
        // A bare number is not a length here, where `calc()` takes one
        // as a multiplier, and zero is not exempt: `max(0, 100px)` is
        // invalid in Chromium (todo.md).
        parseNumberAt(args[i], 0)
        if numOk && numEnd == args[i].length { return lenInvalid() }
        Len a = parseLength(args[i], fontSize)
        if a.kind == LEN_INVALID || a.kind == LEN_AUTO { return lenInvalid() }
        if a.kind != LEN_PX { allPx = false }
        kinds.push(a.kind)
        vs.push(a.v)
        pcts.push(a.pct)
    }
    if allPx {
        Len folded
        folded.kind = LEN_PX
        folded.v = minmaxFold(op, vs)
        return folded
    }
    Len l
    l.kind = LEN_MINMAX
    l.v = minmaxOp.length.toFloat()
    minmaxOp.push(op)
    minmaxAt.push(minmaxKind.length)
    minmaxCount.push(kinds.length)
    for int i = 0, i < kinds.length, i++ {
        minmaxKind.push(kinds[i])
        minmaxV.push(vs[i])
        minmaxPct.push(pcts[i])
    }
    anyMinMax = true
    return l
}

// The same comparison `resolveMinMax` makes, over operands that are
// already pixels. Written once here and once there rather than shared,
// because the two take their operands from different places and what
// must agree is the answer -- which the suite checks by asking for a
// folded value and an unfolded one that pick the same argument.
float func minmaxFold(op:int, vs:arr[float]) {
    if op == MM_CLAMP {
        float mid = vs[1]
        if mid > vs[2] { mid = vs[2] }
        if mid < vs[0] { mid = vs[0] }
        return mid
    }
    float best = vs[0]
    for int i = 1, i < vs.length, i++ {
        if op == MM_MIN ? vs[i] < best : vs[i] > best { best = vs[i] }
    }
    return best
}

Len func parseLength(tok:ascii, fontSize:int) {
    Len l
    l.kind = LEN_INVALID
    if tok == null { return l }
    ascii t = asciiLower(asciiTrim(tok))
    if t == 'auto' || t == 'none' || t == 'initial' || t == 'unset' { return lenAuto() }
    // CSS Box Sizing 3's intrinsic keywords. Kept as a kind of their
    // own rather than resolved here, because the answer is the box's
    // content and this function is given a font size.
    if t == 'min-content' || t == 'max-content' || t == 'fit-content' {
        Len li
        li.kind = LEN_INTRINSIC
        li.v = t == 'min-content' ? INTRINSIC_MIN.toFloat()
             : (t == 'max-content' ? INTRINSIC_MAX.toFloat() : INTRINSIC_FIT.toFloat())
        return li
    }
    if t.length > 5 && asciiLower(t.slice(0, 5)) == 'calc(' && t.charCodeAt(t.length - 1) == CH_RPAREN {
        return evaluateCalc(t.slice(5, t.length - 1), fontSize)
    }
    // Values and Units 4 §10. The closing parenthesis is required to be
    // the one that matches, so `min(1px,2px)min(3px)` is not a length
    // although it ends in one.
    if asciiStartsWith(t, 'min(', 0) && asciiMatchingParen(t, 3) == t.length - 1 {
        return parseMinMax(t.slice(4, t.length - 1), fontSize, MM_MIN)
    }
    if asciiStartsWith(t, 'max(', 0) && asciiMatchingParen(t, 3) == t.length - 1 {
        return parseMinMax(t.slice(4, t.length - 1), fontSize, MM_MAX)
    }
    if asciiStartsWith(t, 'clamp(', 0) && asciiMatchingParen(t, 5) == t.length - 1 {
        return parseMinMax(t.slice(6, t.length - 1), fontSize, MM_CLAMP)
    }
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
    // The inch divided by 2.54 and by 25.4, rather than a rounded 37.8
    // and 3.78: CSS defines the centimetre, the millimetre and the `q`
    // below off the same inch, so three constants for one quantity is
    // three chances for one of them to be wrong -- which it was.
    // `1000cm` came out 37800 against Chromium's 37795.3, and `40000q`,
    // written with the exact constant, disagreed with the centimetre it
    // is equal to by definition.
    if unit == 'cm' { return lenPx(v * 96.0 / 2.54) }
    if unit == 'mm' { return lenPx(v * 96.0 / 25.4) }
    // Each of these is a ratio of the font size measured for the face
    // this engine renders in, rather than an API answer: the runtime
    // exposes no x-height, no zero advance and no cap height. The
    // constants are in style.f beside the two `text-box-edge` reads
    // them, because they are the same quantities -- one cap height,
    // one x-height -- and two constants for one of them is how a
    // number goes stale in one place and not the other.
    if unit == 'ex' { return lenPx(v * fontSize.toFloat() * FONT_EX) }
    if unit == 'ch' { return lenPx(v * fontSize.toFloat() * FONT_CH) }
    if unit == 'vw' { return lenPx(v * cssViewportWidth.toFloat() / 100.0) }
    if unit == 'vh' { return lenPx(v * cssViewportHeight.toFloat() / 100.0) }
    if unit == 'vmin' { return lenPx(v * minInt(cssViewportWidth, cssViewportHeight).toFloat() / 100.0) }
    if unit == 'vmax' { return lenPx(v * maxInt(cssViewportWidth, cssViewportHeight).toFloat() / 100.0) }
    // Values and Units 4. `q` is a quarter of a millimetre. The small,
    // large and dynamic viewport units are three names for this
    // viewport, which has no toolbar that slides away to tell them
    // apart, and `vi` and `vb` are the inline and block axes, which in
    // a horizontal writing mode are the horizontal and the vertical.
    if unit == 'q' { return lenPx(v * 0.94488188976378) }
    // `lh` is the element's own computed line height and `rlh` the root
    // element's. The cascade computes `line-height` before every other
    // length, so the global below holds this element's by the time any
    // of them is parsed -- and holds the parent's while `line-height`
    // itself is being computed, which is what the unit means there.
    if unit == 'lh' { return lenPx(v * cascadeLineHeight.toFloat()) }
    if unit == 'rlh' { return lenPx(v * cssRootLineHeight.toFloat()) }
    if unit == 'svw' || unit == 'lvw' || unit == 'dvw' || unit == 'vi' {
        return lenPx(v * cssViewportWidth.toFloat() / 100.0)
    }
    if unit == 'svh' || unit == 'lvh' || unit == 'dvh' || unit == 'vb' {
        return lenPx(v * cssViewportHeight.toFloat() / 100.0)
    }
    if unit == 'svmin' || unit == 'lvmin' || unit == 'dvmin' {
        return lenPx(v * minInt(cssViewportWidth, cssViewportHeight).toFloat() / 100.0)
    }
    if unit == 'svmax' || unit == 'lvmax' || unit == 'dvmax' {
        return lenPx(v * maxInt(cssViewportWidth, cssViewportHeight).toFloat() / 100.0)
    }
    // An ideograph's advance is an em in every font this engine can
    // load, and Chromium measures exactly that here at every size.
    if unit == 'ic' { return lenPx(v * fontSize.toFloat()) }
    if unit == 'cap' { return lenPx(v * fontSize.toFloat() * FONT_CAP) }
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

// The lengths of a contain-intrinsic-size value, with a leading `auto`
// dropped: `auto 200px` means "the remembered size, or 200px", and this
// engine never remembers one.
arr[ascii] func intrinsicSizeLengths(v:ascii) {
    arr[ascii] t = cssTokens(v)
    arr[ascii] out = []
    for int i = 0, i < t.length, i++ {
        if asciiLower(t[i]) == 'auto' { continue }
        if asciiLower(t[i]) == 'none' { return out }
        out.push(t[i])
    }
    return out
}

Len func intrinsicSizeProp(props:map[text], name:text, fontSize:int, dflt:Len) {
    ascii v = styleProp(props, name)
    if v == null { return dflt }
    arr[ascii] t = intrinsicSizeLengths(v)
    if t.length == 0 { return dflt }
    Len l = parseLength(t[0], fontSize)
    if l.kind != LEN_PX { return dflt }
    return l
}

// One corner's radius, or the value the shorthand already gave it.
// One corner longhand, which takes one radius or two: `20px` is a
// quarter circle, `20px 5px` an ellipse a fifth as tall as it is wide.
// Two values out of a function need globals (FINDINGS.md, "one value
// out of a function").
Len cornerRadiusX = lenPx(0.0)
Len cornerRadiusY = lenPx(0.0)

bool func cornerRadiusProp(props:map[text], name:text, fontSize:int) {
    ascii v = styleProp(props, name)
    if v == null { return false }
    arr[ascii] t = cssTokens(v)
    if t.length == 0 { return false }
    Len rx = parseRadiusLen(t[0], fontSize)
    if rx.kind != LEN_PX && rx.kind != LEN_PERCENT { return false }
    cornerRadiusX = rx
    cornerRadiusY = rx
    if t.length > 1 {
        Len ry = parseRadiusLen(t[1], fontSize)
        if ry.kind == LEN_PX || ry.kind == LEN_PERCENT { cornerRadiusY = ry }
    }
    return true
}

// The shorthand's slots: one value is every corner, two are the two
// diagonals, three leave the fourth to mirror the second, four are
// clockwise from the top left.
// CSS's 1-to-4 rule over the tokens of a `border-radius`, as text, so
// that applyDecl can write the corner longhands without parsing a
// length it would only serialize back. The same rule radiusSlot
// applies to parsed lengths, one step earlier.
text func radiusSlotText(list:arr[text], at:int) {
    if list.length == 0 { return '0' }
    if at == 0 { return list[0] }
    if at == 1 { return list.length > 1 ? list[1] : list[0] }
    if at == 2 { return list.length > 2 ? list[2] : list[0] }
    if list.length > 3 { return list[3] }
    return list.length > 1 ? list[1] : list[0]
}

Len func radiusSlot(list:arr[Len], at:int) {
    if list.length == 0 { return lenPx(0.0) }
    if at == 0 { return list[0] }
    if at == 1 { return list.length > 1 ? list[1] : list[0] }
    if at == 2 { return list.length > 2 ? list[2] : list[0] }
    if list.length > 3 { return list[3] }
    return list.length > 1 ? list[1] : list[0]
}

// Whether any corner of this style is rounded at all.
bool func radiusAny(s:Style) {
    return lenIsPositive(s.radiusTopLeftX) || lenIsPositive(s.radiusTopRightX)
        || lenIsPositive(s.radiusBottomRightX) || lenIsPositive(s.radiusBottomLeftX)
}

bool func lenIsPositive(l:Len) {
    return (l.kind == LEN_PX || l.kind == LEN_PERCENT) && l.v > 0.0
}

// A radius is never negative, and a percentage is kept for the painter
// to resolve against the box.
Len func parseRadiusLen(tok:ascii, fontSize:int) {
    Len l = parseLength(tok, fontSize)
    if l.kind == LEN_PX && l.v < 0.0 { return lenPx(0.0) }
    if l.kind == LEN_PERCENT && l.v < 0.0 { return lenPercent(0.0) }
    return l
}

// One side's border-style. Anything the painter does not know paints
// solid.
// One line-style keyword. Anything the painter does not know paints
// solid; `none` and `hidden` mean no line at all.
int func lineStyleKeyword(t:ascii) {
    if t == 'none' || t == 'hidden' { return BORDER_NONE }
    if t == 'dashed' { return BORDER_DASHED }
    if t == 'dotted' { return BORDER_DOTTED }
    if t == 'double' { return BORDER_DOUBLE }
    if t == 'groove' { return BORDER_GROOVE }
    if t == 'ridge' { return BORDER_RIDGE }
    if t == 'inset' { return BORDER_INSET }
    if t == 'outset' { return BORDER_OUTSET }
    return BORDER_SOLID
}

// Whether a token is one of the line-style keywords at all, which the
// `outline` shorthand needs in order to tell a style from a colour.
// break-before and break-after. `column` ends a column and `page` ends
// a page; the page-side keywords -- `left`, `right`, `recto`, `verso` --
// each end a page as well and then name the side the next one must be
// formatted as, which the paginator reaches by generating a blank page
// where it has to. `avoid`, `avoid-column` and `avoid-page`
// all forbid a break, since the only two contexts here are the column
// and the page.
int func breakKeyword(v:ascii) {
    if v == null { return BRK_AUTO }
    ascii t = asciiLower(asciiTrim(v))
    if t == 'column' { return BRK_COLUMN }
    if t == 'page' { return BRK_PAGE }
    // `recto` and `verso` are the sides named by the page progression
    // rather than by the reader's hand. This engine has no vertical
    // writing mode, so the progression is always left to right and
    // `recto` is `right`, `verso` is `left`.
    if t == 'right' || t == 'recto' { return BRK_RIGHT }
    if t == 'left' || t == 'verso' { return BRK_LEFT }
    if t == 'avoid' || t == 'avoid-column' || t == 'avoid-page' { return BRK_AVOID }
    return BRK_AUTO
}

// CSS Scroll Snap 1 §5. `scroll-snap-type` names an axis and, after it,
// how strictly the container snaps; the standard's initial strictness is
// `proximity`, so a bare axis is that. Three answers out of a function
// need globals (FINDINGS.md, "one value out of a function").
bool snapAxisXOut = false
bool snapAxisYOut = false
int snapStrictOut = SNAP_NONE

void func snapTypeProp(v:ascii) {
    snapAxisXOut = false
    snapAxisYOut = false
    snapStrictOut = SNAP_NONE
    if v == null { return }
    arr[ascii] t = cssTokens(v)
    if t.length == 0 { return }
    text axis = asciiLower(t[0]).toText()
    // The logical axes are the physical ones in a horizontal writing
    // mode, which is the only one this engine lays out in.
    if axis == 'x' || axis == 'inline' { snapAxisXOut = true }
    else if axis == 'y' || axis == 'block' { snapAxisYOut = true }
    else if axis == 'both' { snapAxisXOut = true  snapAxisYOut = true }
    else { return }
    snapStrictOut = SNAP_PROXIMITY
    if t.length > 1 && asciiLower(t[1]) == 'mandatory' { snapStrictOut = SNAP_MANDATORY }
}

int func snapAlignKeyword(t:ascii) {
    if t == 'start' { return SNAPALIGN_START }
    if t == 'center' { return SNAPALIGN_CENTER }
    if t == 'end' { return SNAPALIGN_END }
    return SNAPALIGN_NONE
}

// `scroll-snap-align` takes one value for both axes or two, the block
// axis first (§4.1). Two answers out of a function need globals.
int snapAlignBlockOut = SNAPALIGN_NONE
int snapAlignInlineOut = SNAPALIGN_NONE

void func snapAlignProp(v:ascii) {
    snapAlignBlockOut = SNAPALIGN_NONE
    snapAlignInlineOut = SNAPALIGN_NONE
    if v == null { return }
    arr[ascii] t = cssTokens(v)
    if t.length == 0 { return }
    snapAlignBlockOut = snapAlignKeyword(asciiLower(t[0]))
    snapAlignInlineOut = t.length > 1 ? snapAlignKeyword(asciiLower(t[1])) : snapAlignBlockOut
}

// `corner-shape`'s keywords and `superellipse()`, as the exponent each
// one names (CSS Borders 4 §5). Zero is "not a shape", which no real
// value is, because a superellipse of exponent zero is not a curve.
float func cornerShapeKeyword(v:ascii) {
    if v == null { return 0.0 }
    ascii t = asciiLower(asciiTrim(v))
    if t == 'round' { return CORNER_K_ROUND }
    if t == 'square' { return CORNER_K_SQUARE }
    if t == 'bevel' { return CORNER_K_BEVEL }
    if t == 'scoop' { return CORNER_K_SCOOP }
    if t == 'notch' { return CORNER_K_NOTCH }
    if t == 'squircle' { return CORNER_K_SQUIRCLE }
    if asciiStartsWith(t, 'superellipse('.toAscii(), 0) && t[t.length - 1] == ')' {
        ascii inner = asciiTrim(t.slice(13, t.length - 1))
        if inner == 'infinity' { return CORNER_K_SQUARE }
        if inner == '-infinity' { return CORNER_K_NOTCH }
        float n = parseFloatAscii(inner)
        // An exponent of zero is not a curve, and one past the extremes
        // is the extreme.
        if n == 0.0 { return 0.0 }
        if n > CORNER_K_SQUARE { return CORNER_K_SQUARE }
        if n < CORNER_K_NOTCH { return CORNER_K_NOTCH }
        return n
    }
    return 0.0
}

// One `corner-*-shape` longhand, or the value already there when the
// declaration is absent or unreadable.
float func cornerShapeProp(props:map[text], name:text, fallback:float) {
    ascii v = styleProp(props, name)
    if v == null { return fallback }
    float k = cornerShapeKeyword(v)
    return k == 0.0 ? fallback : k
}

// `position-area`'s keywords (CSS Anchor Positioning 1 §3.1). A keyword
// names a band, and some name an axis with it: `top` and `bottom` are
// the block axis, `left` and `right` the inline one. `start`, `end`,
// `center` and `span-all` name neither, and take the block axis first
// and the inline second, which is what the standard's grammar means by
// taking them in order.
const int PAREA_AX_ANY = 0
const int PAREA_AX_BLOCK = 1
const int PAREA_AX_INLINE = 2

int pareaBand = PAREA_NONE
int pareaAxis = PAREA_AX_ANY

void func pareaKeyword(v:ascii) {
    pareaBand = PAREA_NONE
    pareaAxis = PAREA_AX_ANY
    if v == 'top' { pareaBand = PAREA_BEFORE  pareaAxis = PAREA_AX_BLOCK  return }
    if v == 'bottom' { pareaBand = PAREA_AFTER  pareaAxis = PAREA_AX_BLOCK  return }
    if v == 'block-start' || v == 'y-start' || v == 'y-self-start' {
        pareaBand = PAREA_BEFORE  pareaAxis = PAREA_AX_BLOCK  return
    }
    if v == 'block-end' || v == 'y-end' || v == 'y-self-end' {
        pareaBand = PAREA_AFTER  pareaAxis = PAREA_AX_BLOCK  return
    }
    if v == 'left' { pareaBand = PAREA_BEFORE  pareaAxis = PAREA_AX_INLINE  return }
    if v == 'right' { pareaBand = PAREA_AFTER  pareaAxis = PAREA_AX_INLINE  return }
    if v == 'inline-start' || v == 'x-start' || v == 'x-self-start' {
        pareaBand = PAREA_BEFORE  pareaAxis = PAREA_AX_INLINE  return
    }
    if v == 'inline-end' || v == 'x-end' || v == 'x-self-end' {
        pareaBand = PAREA_AFTER  pareaAxis = PAREA_AX_INLINE  return
    }
    if v == 'start' || v == 'self-start' { pareaBand = PAREA_BEFORE  return }
    if v == 'end' || v == 'self-end' { pareaBand = PAREA_AFTER  return }
    if v == 'center' { pareaBand = PAREA_CENTER  return }
    if v == 'span-all' { pareaBand = PAREA_SPAN  return }
}

// The whole value: one or two keywords, packed block then inline. A
// keyword that names an axis goes to it and leaves the other spanning;
// one that names neither fills the block axis first. A single keyword
// naming neither applies to both, which is what makes `center` centre
// in two directions rather than one.
int func positionAreaValue(v:ascii) {
    if v == null { return PAREA_NONE }
    arr[ascii] t = cssTokens(asciiLower(v))
    if t.length == 0 { return PAREA_NONE }
    int blockBand = PAREA_NONE
    int inlineBand = PAREA_NONE
    // The keywords that name an axis are placed first, because one that
    // names none takes whichever axis is left: in `top span-all` the
    // span is the inline axis, and assigning in written order would
    // give it the block axis the `top` had already claimed.
    for int i = 0, i < t.length, i++ {
        pareaKeyword(t[i])
        if pareaBand == PAREA_NONE { return PAREA_NONE }
        if pareaAxis == PAREA_AX_BLOCK { blockBand = pareaBand }
        else if pareaAxis == PAREA_AX_INLINE { inlineBand = pareaBand }
    }
    int anyCount = 0
    for int i = 0, i < t.length, i++ {
        pareaKeyword(t[i])
        if pareaAxis != PAREA_AX_ANY { continue }
        anyCount++
        if blockBand == PAREA_NONE { blockBand = pareaBand }
        else if inlineBand == PAREA_NONE { inlineBand = pareaBand }
    }
    // One axis-agnostic keyword on its own covers both axes, which is
    // what makes `center` centre in two directions rather than one.
    if t.length == 1 && anyCount == 1 { inlineBand = blockBand }
    if blockBand == PAREA_NONE { blockBand = PAREA_SPAN }
    if inlineBand == PAREA_NONE { inlineBand = PAREA_SPAN }
    return blockBand * PAREA_AXIS + inlineBand
}

// A dashed identifier as written, or '' -- an anchor name is compared
// rather than parsed, so it keeps its dashes.
text func anchorIdent(props:map[text], name:text) {
    ascii v = styleProp(props, name)
    if v == null { return '' }
    return asciiTrim(v).toText()
}

// CSS Writing Modes 3 §2.2: which pair of formatting characters the
// element's text is treated as being wrapped in.
int func unicodeBidiKeyword(v:ascii) {
    if v == null { return UBIDI_NORMAL }
    if v == 'embed' { return UBIDI_EMBED }
    if v == 'bidi-override' { return UBIDI_OVERRIDE }
    if v == 'isolate' { return UBIDI_ISOLATE }
    if v == 'isolate-override' { return UBIDI_ISOLATE_OVERRIDE }
    if v == 'plaintext' { return UBIDI_PLAINTEXT }
    return UBIDI_NORMAL
}

// CSS Scrollbars 1 §3: how wide a scroll container's bars are.
int func scrollbarWidthKeyword(v:ascii) {
    if v == null { return SCROLLBAR_AUTO }
    ascii t = asciiLower(asciiTrim(v))
    if t == 'thin' { return SCROLLBAR_THIN }
    if t == 'none' { return SCROLLBAR_NONE }
    return SCROLLBAR_AUTO
}

// CSS Overflow 4 §3.3. `both-edges` is only meaningful beside `stable`,
// which is what the grammar says: the keyword on its own is not a value.
int func scrollbarGutterKeyword(v:ascii) {
    if v == null { return SCROLLBAR_GUTTER_AUTO }
    arr[ascii] t = cssTokens(v)
    if t.length == 0 { return SCROLLBAR_GUTTER_AUTO }
    if asciiLower(t[0]) != 'stable' { return SCROLLBAR_GUTTER_AUTO }
    if t.length > 1 && asciiLower(t[1]) == 'both-edges' { return SCROLLBAR_GUTTER_BOTH }
    return SCROLLBAR_GUTTER_STABLE
}

// `scrollbar-color` is one colour for the thumb and one for the track,
// in that order, and `auto` -- or anything that is not two colours --
// leaves the painter its own. Two values out of a function need globals
// (FINDINGS.md, "one value out of a function").
int scrollbarThumbOut = 0
int scrollbarTrackOut = 0

void func scrollbarColorProp(props:map[text], inheritThumb:int, inheritTrack:int) {
    scrollbarThumbOut = inheritThumb
    scrollbarTrackOut = inheritTrack
    ascii v = styleProp(props, 'scrollbar-color')
    if v == null { return }
    if cssWideKeyword(v) != CSSWIDE_NONE { return }
    if asciiLower(asciiTrim(v)) == 'auto' {
        scrollbarThumbOut = 0
        scrollbarTrackOut = 0
        return
    }
    arr[ascii] t = cssTokens(v)
    // One colour is not two: the standard takes the pair or nothing, so
    // a half-written declaration leaves the pair alone rather than
    // colouring the thumb and guessing at the track.
    if t.length != 2 { return }
    int a = parseCssColor(t[0], COLOR_BLACK)
    int b = parseCssColor(t[1], COLOR_BLACK)
    if a == COLOR_UNSET || b == COLOR_UNSET { return }
    scrollbarThumbOut = a
    scrollbarTrackOut = b
}

// `page` names the page an element belongs on, or nothing for `auto`.
// The name is an identifier, so its case is its own.
text func pageNameProp(v:ascii) {
    if v == null { return '' }
    ascii t = asciiTrim(v)
    if t.length == 0 { return '' }
    if asciiLower(t) == 'auto' { return '' }
    return t.toText()
}

// A positive integer property -- `orphans` and `widows` -- keeping the
// inherited value when the declaration is absent or not a number.
int func countProp(props:map[text], name:text, inherited:int) {
    ascii v = styleProp(props, name)
    if v == null { return inherited }
    parseNumberAt(asciiTrim(v), 0)
    if !numOk { return inherited }
    return maxInt(roundPx(numValue), 1)
}

bool func isLineStyleKeyword(t:ascii) {
    return t == 'none' || t == 'hidden' || t == 'solid' || t == 'dashed'
        || t == 'dotted' || t == 'double' || t == 'groove' || t == 'ridge'
        || t == 'inset' || t == 'outset'
}

// The character a text-emphasis-style draws. A `<string>` value is
// drawn as itself; a keyword pair picks one of the standard's five
// marks in its filled or open form. Empty means no mark at all.
text func emphasisMarkFor(v:ascii) {
    arr[ascii] t = cssTokens(v)
    bool open = false
    text shape = ''
    for int i = 0, i < t.length, i++ {
        ascii tok = asciiLower(t[i])
        if tok == 'none' { return '' }
        if tok == 'open' { open = true  continue }
        if tok == 'filled' { continue }
        if tok == 'dot' || tok == 'circle' || tok == 'double-circle'
            || tok == 'triangle' || tok == 'sesame' {
            shape = tok.toText()
            continue
        }
        // a quoted string is drawn as itself
        if t[i].length >= 2 {
            int first = t[i].charCodeAt(0)
            if first == CH_QUOTE || first == CH_APOS {
                return t[i].slice(1, t[i].length - 1).toText()
            }
        }
    }
    if shape == '' { shape = 'circle' }
    if shape == 'dot' { return open ? '◦' : '•' }
    if shape == 'circle' { return open ? '○' : '●' }
    if shape == 'double-circle' { return open ? '◎' : '◉' }
    if shape == 'triangle' { return open ? '△' : '▲' }
    return open ? '﹆' : '﹅'
}

// One text-decoration-style keyword, or -1 for a token that is not one.
int func decorationStyleKeyword(t:ascii) {
    if t == 'solid' { return DECOSTYLE_SOLID }
    if t == 'double' { return DECOSTYLE_DOUBLE }
    if t == 'dotted' { return DECOSTYLE_DOTTED }
    if t == 'dashed' { return DECOSTYLE_DASHED }
    if t == 'wavy' { return DECOSTYLE_WAVY }
    return -1
}

int func borderStyleProp(props:map[text], side:text) {
    ascii v = styleProp(props, `border-${side}-style`)
    // The initial value is `none`, and saying so matters beyond tidiness:
    // while this answered `solid` for an undeclared border, declaring
    // `border-top-style: solid` changed no style field at all, and the
    // property registered as implemented only through the width that a
    // declared style gives its side.
    if v == null { return BORDER_NONE }
    return lineStyleKeyword(asciiLower(asciiTrim(v)))
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

// `justify-content`, `align-items` and `align-self` share a vocabulary.
int func parseAlignValue(v:ascii, dflt:int) {
    if v == null { return dflt }
    ascii t = asciiLower(asciiTrim(v))
    if t == 'flex-start' || t == 'start' || t == 'left' { return BOXALIGN_START }
    if t == 'flex-end' || t == 'end' || t == 'right' { return BOXALIGN_END }
    if t == 'center' { return BOXALIGN_CENTRE }
    if t == 'stretch' || t == 'normal' { return BOXALIGN_STRETCH }
    if t == 'baseline' { return BOXALIGN_BASELINE }
    if t == 'space-between' { return BOXALIGN_SPACE_BETWEEN }
    if t == 'space-around' { return BOXALIGN_SPACE_AROUND }
    if t == 'space-evenly' { return BOXALIGN_SPACE_EVENLY }
    if t == 'auto' { return BOXALIGN_AUTO }
    return dflt
}

// The block-level `display` an inline-level one blockifies to
// (Display 3 sec. 2.7). Anything already block-level, and the two
// values that name no box, come back unchanged.
int func blockifiedDisplay(d:int) {
    if d == DISPLAY_INLINE || d == DISPLAY_INLINE_BLOCK { return DISPLAY_BLOCK }
    if d == DISPLAY_INLINE_FLEX { return DISPLAY_FLEX }
    if d == DISPLAY_INLINE_GRID { return DISPLAY_GRID }
    if d == DISPLAY_INLINE_TABLE { return DISPLAY_TABLE }
    return d
}

// Whether a value is one this property has. An invalid declaration is
// dropped rather than applied (CSS Syntax 3 sec. 8.2), and for `display`
// that is the difference between a `<div>` keeping the block the
// user-agent stylesheet gave it and becoming an inline: there is one
// map of declarations, so a value that reaches it has already beaten
// the user-agent's, and falling back afterwards falls back to the
// property's initial value rather than to what it replaced.
bool func isDisplayKeyword(v:ascii) {
    return parseDisplay(v, -1) != -1
}

int func parseDisplay(v:ascii, dflt:int) {
    if v == null { return dflt }
    ascii t = asciiLower(v)
    if t == 'none' { return DISPLAY_NONE }
    if t == 'block' || t == 'flow-root' { return DISPLAY_BLOCK }
    if t == 'grid' { return DISPLAY_GRID }
    if t == 'flex' { return DISPLAY_FLEX }
    if t == 'inline-flex' { return DISPLAY_INLINE_FLEX }
    if t == 'inline-grid' { return DISPLAY_INLINE_GRID }
    if t == 'inline' { return DISPLAY_INLINE }
    if t == 'contents' { return DISPLAY_CONTENTS }
    if t == 'inline-block' { return DISPLAY_INLINE_BLOCK }
    if t == 'list-item' { return DISPLAY_LIST_ITEM }
    if t == 'table' { return DISPLAY_TABLE }
    // A table inside, an inline outside: it sits on the line beside the
    // text rather than starting one, and takes the width its cells ask
    // for, which a block-level table does too.
    if t == 'inline-table' { return DISPLAY_INLINE_TABLE }
    if t == 'table-row' { return DISPLAY_TABLE_ROW }
    if t == 'table-cell' { return DISPLAY_TABLE_CELL }
    if t == 'table-row-group' { return DISPLAY_TABLE_ROW_GROUP }
    if t == 'table-header-group' { return DISPLAY_TABLE_HEADER_GROUP }
    if t == 'table-footer-group' { return DISPLAY_TABLE_FOOTER_GROUP }
    if t == 'table-caption' { return DISPLAY_TABLE_CAPTION }
    if t == 'table-column' { return DISPLAY_TABLE_COLUMN }
    if t == 'table-column-group' { return DISPLAY_TABLE_COLUMN_GROUP }
    if t == 'ruby' { return DISPLAY_RUBY }
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
    cascadeApplyRtl = cascadeSawDirection
        && matchedDirectionRtl(matches, isRoot ? false : parent.directionRtl)
    cascadeApplyWM = cascadeSawWritingMode
        ? matchedWritingMode(matches, isRoot ? WM_HORIZONTAL_TB : parent.writingMode)
        : WM_HORIZONTAL_TB
    applyMatches(props, matches)
    if archtelosTiming {
        profApplyMs = profApplyMs + (now() - t1)
        profElements++
        profMatchesTotal = profMatchesTotal + matches.length
    }
    int t2 = archtelosTiming ? now() : 0
    // Two elements that matched the same declarations in the same order,
    // under the same parent, compute the same style -- and on a real
    // document most elements do: this page's 1,560 table cells all match
    // the same four rules. Parsing those values once and handing out the
    // same Style is what keeps this phase from being paid per element.
    // The Style is never written to after this point, which is what
    // makes sharing one safe (see Box.forcedWidthPx for the one place
    // that used to).
    text key = styleCacheKey(n, parent, isRoot, matches)
    Style cached = styleCache[key]
    if cached != null {
        profShareTotal++
        if archtelosTiming { profComputeMs = profComputeMs + (now() - t2) }
        return cached
    }
    Style s = computeStyleValues(n, parent, isRoot, props)
    styleCache[key] = s
    profShareTotal++
    profShareDistinct++
    if archtelosTiming { profComputeMs = profComputeMs + (now() - t2) }
    return s
}

// The identity of a computed style: what it was computed from. The
// parent is named by its serial rather than by its contents, which is
// sound because an identical parent is itself shared and so carries the
// same serial.
text func styleCacheKey(n:Node, parent:Style, isRoot:bool, matches:arr[Match]) {
    arr[text] parts = []
    parts.push(`${parentSerialOf(parent)}`)
    parts.push(isRoot ? 'r' : 'e')
    // The pseudo-element the style is for, so an entry made for
    // `input::placeholder` can never be handed to an `input`. The
    // matched declarations would have to be identical for that to
    // happen, but a cache whose key omits part of what it was computed
    // from is one waiting to be wrong.
    parts.push(collectingPseudoKey)
    parts.push(n.tag)
    for int i = 0, i < matches.length, i++ {
        Decl d = matches[i].decl
        if d.serial > 0 {
            parts.push(`${d.serial}:${matches[i].weight}`)
        } else {
            // synthesized for this element: key on what it says
            parts.push(`${d.name}=${d.value == null ? '' : d.value.toText()}:${matches[i].weight}`)
        }
    }
    return parts.join('|')
}

int func parentSerialOf(parent:Style) {
    if parent == null { return 0 }
    return parent.serial
}

// The URL inside a `url(...)`, unquoted. Returns '' for anything else,
// which is how a gradient value falls through to the gradient parser.
// How many device pixels this display puts in a CSS pixel. One: the
// canvas is not scaled, and `resolution` in a media query answers 96dpi
// for the same reason. `image-set()` chooses its candidate against it.
const float CSS_DEVICE_DPPX = 1.0

// A resolution, in device pixels per CSS pixel, or -1 for a token that
// is not one. `x` and `dppx` are the same unit under two names; an inch
// is 96 CSS pixels and a centimetre 96/2.54 of them, which is how
// Chromium normalises `96dpi` to `1dppx`.
float func parseResolutionValue(t:ascii) {
    if t == null { return -1.0 }
    parseNumberAt(t, 0)
    if !numOk { return -1.0 }
    float v = numValue
    ascii unit = asciiLower(t.slice(numEnd, t.length))
    if unit == 'x' || unit == 'dppx' { return v }
    if unit == 'dpi' { return v / 96.0 }
    if unit == 'dpcm' { return v / 37.795275590551 }
    return -1.0
}

// The text of a quoted string token, or '' for anything else.
// `image-set()` takes a bare string beside a `url()`, and they mean the
// same thing.
text func quotedTokenText(t:ascii) {
    if t == null || t.length < 2 { return '' }
    int q = t.charCodeAt(0)
    if q != CH_QUOTE && q != CH_APOS { return '' }
    if t.charCodeAt(t.length - 1) != q { return '' }
    return t.slice(1, t.length - 1).toText()
}

// The candidate `image-set()` chooses for this display: the smallest
// resolution at or above it, and the largest below it when there is
// none, which is what a list of only 2x and 3x has to fall back to. A
// candidate naming no resolution is 1x, and `type()` says what the file
// is rather than how big, so it is skipped.
text func imageSetUrl(inner:ascii) {
    arr[ascii] cands = splitTopLevelCommas(inner)
    text bestUrl = ''
    float bestRes = 0.0
    for int i = 0, i < cands.length, i++ {
        ascii one = dup(asciiTrim(cands[i]))
        arr[ascii] toks = cssTokens(one)
        text u = ''
        float res = 1.0
        for int k = 0, k < toks.length, k++ {
            if asciiStartsWithLower(toks[k], 'type('.toAscii(), 0) { continue }
            text fromUrl = parseUrlValue(toks[k])
            if fromUrl != '' { u = fromUrl  continue }
            text fromString = quotedTokenText(toks[k])
            if fromString != '' { u = fromString  continue }
            float r = parseResolutionValue(toks[k])
            if r > 0.0 { res = r }
        }
        if u == '' { continue }
        bool better = bestUrl == ''
        if !better && bestRes < CSS_DEVICE_DPPX && res > bestRes { better = true }
        if !better && res >= CSS_DEVICE_DPPX
            && (bestRes < CSS_DEVICE_DPPX || res < bestRes) { better = true }
        if better {
            bestUrl = u
            bestRes = res
        }
    }
    return bestUrl
}

// cross-fade() mixes two images: the second's share is `crossFadeAmount`
// and the two urls are the globals below, which the caller copies out
// before the next value is read. Globals rather than a struct because a
// returned struct would be allocated per declaration, and this runs
// where every background-image is parsed.
text crossFadeA = ''
text crossFadeB = ''
float crossFadeAmount = -1.0

// Reads `cross-fade(<image> <percentage>?, <image> <percentage>?)`
// (CSS Images 4 §3). A percentage is that image's own share; where only
// one is given the other image takes the remainder, and where neither
// is the two are even. Answers whether the value was one at all.
//
// Chromium implements only `-webkit-cross-fade(A, B, p)`, whose pixels
// say p of B over 1 - p of A, byte for byte in sRGB; that is the same
// mix this reads, written the other way round.
bool func parseCrossFade(v:ascii) {
    crossFadeA = ''
    crossFadeB = ''
    crossFadeAmount = -1.0
    if v == null { return false }
    ascii t = asciiTrim(v)
    int open = 0
    if asciiStartsWithLower(t, 'cross-fade('.toAscii(), 0) { open = 11 }
    else if asciiStartsWithLower(t, '-webkit-cross-fade('.toAscii(), 0) { open = 19 }
    if open == 0 { return false }
    if t.charCodeAt(t.length - 1) != CH_RPAREN { return false }
    arr[ascii] args = splitTopLevelCommas(dup(t.slice(open, t.length - 1)))
    if args.length < 2 { return false }
    text urlA = ''
    text urlB = ''
    float shareA = -1.0
    float shareB = -1.0
    for int i = 0, i < 2, i++ {
        arr[ascii] toks = cssTokens(dup(asciiTrim(args[i])))
        text u = ''
        float share = -1.0
        for int k = 0, k < toks.length, k++ {
            text fromUrl = imageUrlValue(toks[k])
            if fromUrl != '' { u = fromUrl  continue }
            text fromString = quotedTokenText(toks[k])
            if fromString != '' { u = fromString  continue }
            Len l = parseLength(toks[k], 16)
            if l.kind == LEN_PERCENT { share = l.v / 100.0 }
        }
        if i == 0 { urlA = u  shareA = share }
        else { urlB = u  shareB = share }
    }
    if urlA == '' || urlB == '' { return false }
    // The second image's share is what the painter needs, because it is
    // blitted over the first.
    float b = shareB
    if b < 0.0 { b = shareA >= 0.0 ? 1.0 - shareA : 0.5 }
    // `-webkit-cross-fade` writes that share as a third argument rather
    // than beside the image it belongs to.
    if open == 19 && args.length > 2 {
        Len l = parseLength(dup(asciiTrim(args[2])), 16)
        if l.kind == LEN_PERCENT { b = l.v / 100.0 }
        else if l.kind == LEN_PX { b = l.v }
    }
    if b < 0.0 { b = 0.0 }
    if b > 1.0 { b = 1.0 }
    crossFadeA = urlA
    crossFadeB = urlB
    crossFadeAmount = b
    anyCrossFade = true
    return true
}

// The url an image notation reduces to, or '' for a value that is not
// one. `image()` names a source with an optional colour to fall back to
// when it does not load; the colour alone would be a solid-colour image,
// which nothing here can make, so only the source is read (css-2026.md).
text func imageNotationUrl(v:ascii) {
    if v == null { return '' }
    ascii t = asciiTrim(v)
    int open = 0
    if asciiStartsWithLower(t, 'image-set('.toAscii(), 0) { open = 10 }
    else if asciiStartsWithLower(t, '-webkit-image-set('.toAscii(), 0) { open = 18 }
    else if asciiStartsWithLower(t, 'image('.toAscii(), 0) { open = 6 }
    if open == 0 { return '' }
    if t.charCodeAt(t.length - 1) != CH_RPAREN { return '' }
    ascii inner = dup(t.slice(open, t.length - 1))
    if open != 6 { return imageSetUrl(inner) }
    // image(): the first argument that is a source.
    arr[ascii] args = splitTopLevelCommas(inner)
    for int i = 0, i < args.length, i++ {
        ascii one = dup(asciiTrim(args[i]))
        text fromUrl = parseUrlValue(one)
        if fromUrl != '' { return fromUrl }
        text fromString = quotedTokenText(one)
        if fromString != '' { return fromString }
    }
    return ''
}

// Where an `<image>` is expected: a plain `url()`, or the url an image
// notation reduces to.
text func imageUrlValue(v:ascii) {
    text u = parseUrlValue(v)
    if u != '' { return u }
    return imageNotationUrl(v)
}

text func parseUrlValue(v:ascii) {
    if v == null { return '' }
    // Worked out with indices and taken as ONE slice of the argument.
    // Slicing a value that is itself a slice, and reassigning a local
    // to a slice of itself, are both ways to read freed memory here --
    // see FINDINGS.md, "slicing an ascii that came from a slice" and
    // "ascii aliases are not retained". Valgrind caught this version's
    // predecessor; the tests did not.
    int n = v.length
    int a = 0
    while a < n && isSpaceCode(v.charCodeAt(a)) { a++ }
    if !asciiStartsWithLower(v, 'url(', a) { return '' }
    int close = asciiIndexOf(v, ')'.toAscii(), a)
    if close < 0 { return '' }
    int from = a + 4
    int to = close
    while from < to && isSpaceCode(v.charCodeAt(from)) { from++ }
    while to > from && isSpaceCode(v.charCodeAt(to - 1)) { to-- }
    if to - from >= 2 {
        int q = v.charCodeAt(from)
        if (q == CH_QUOTE || q == CH_APOS) && v.charCodeAt(to - 1) == q {
            from++
            to--
        }
    }
    if to <= from { return '' }
    return v.slice(from, to).toText()
}

// One axis of a position value, shared by `background-position` and
// `object-position`. A keyword is a percentage of the space the image
// leaves over, which is what makes `right` mean the right edge rather
// than an offset of the box's width.
//
// A percentage `Len` holds the number out of a hundred, as `resolveLen`
// reads it everywhere else, so the keywords are written that way too. A
// keyword that stored a fraction instead read as a hundredth of itself
// the moment a real percentage appeared beside it.
Len func parsePositionAxis(t:ascii, horizontal:bool, fontSize:int) {
    if t == 'left' { return lenPercent(0.0) }
    if t == 'right' { return lenPercent(100.0) }
    if t == 'top' { return lenPercent(0.0) }
    if t == 'bottom' { return lenPercent(100.0) }
    if t == 'center' || t == 'centre' { return lenPercent(50.0) }
    Len got = parseLength(t, fontSize)
    if got.kind == LEN_AUTO || got.kind == LEN_INVALID { return lenPercent(0.0) }
    return got
}

// ---- CSS Inline 3: text-box-trim and text-box-edge ------------------------

// One `anchor()`, as the three things it says. Returned through
// globals rather than a struct, for the reason FINDINGS.md records
// about forwarded structs.
text anchorInsetName = ''
int anchorInsetPct = -1
int anchorInsetFallback = ANCHOR_NO_FALLBACK

// The position along the anchor a side keyword names, in hundredths of
// a percent, or -1 for a word that is not one: the near sides are 0,
// `center` is 5000, and the far sides 10000.
//
// **A physical side must lie on the axis of the property being set.**
// `top: anchor(left)` names a horizontal edge for a vertical inset, and
// Chromium treats it as it treats any value it cannot parse -- the
// declaration has no effect and the box keeps its static position
// (todo.md has the probe). That is what `vertical` is for, and it was
// missing: the two keywords were read by position rather than by which
// axis they name.
//
// `start`, `end`, `self-start` and `self-end` are still read as the near
// and far sides here, which is right only where the axis is not
// reversed. `direction: rtl` reverses the inline axis and a vertical
// `writing-mode` the block one, and todo.md records Chromium's answers
// for both; the percentage is resolved into the cascade's own map for
// the bare `anchor()` form, before either the containing block or the
// box's own mode is in hand, so making these follow it is a piece of
// work of its own rather than a keyword table.
int func anchorSidePct(w:ascii, vertical:bool) {
    if w == 'left' || w == 'right' { if vertical { return -1 } }
    if w == 'top' || w == 'bottom' { if !vertical { return -1 } }
    if w == 'left' || w == 'top' || w == 'start' || w == 'self-start' { return 0 }
    if w == 'center' { return 5000 }
    if w == 'right' || w == 'bottom' || w == 'end' || w == 'self-end' { return 10000 }
    if w.length > 1 && w.charCodeAt(w.length - 1) == CH_PERCENT {
        parseNumberAt(w, 0)
        if numOk && numEnd == w.length - 1 { return roundPx(numValue * 100.0) }
    }
    return -1
}

// `[ <name>? <side> ] , <fallback>?` -- the inside of one `anchor()`.
// Answers whether it parsed, and leaves what it said in the three
// globals above. `axis` is which inset this is, and it decides whether a
// physical side keyword is on the right axis to be valid at all; the
// resolver still knows which edge to measure from.
bool func parseAnchorInset(inner:ascii, axis:int) {
    anchorInsetName = ''
    anchorInsetPct = -1
    anchorInsetFallback = ANCHOR_NO_FALLBACK
    arr[ascii] parts = asciiSplitChar(inner, CH_COMMA)
    if parts.length == 0 || parts.length > 2 { return false }
    arr[ascii] words = asciiSplitSpace(asciiTrim(parts[0]))
    if words.length == 0 || words.length > 2 { return false }
    int at = 0
    if words.length == 2 {
        if !asciiStartsWith(words[0], '--', 0) { return false }
        anchorInsetName = words[0].toText()
        at = 1
    }
    int pct = anchorSidePct(words[at], axis >= ANCHOR_INSET_TOP)
    if pct < 0 { return false }
    anchorInsetPct = pct
    if parts.length == 2 {
        Len l = parseLength(asciiTrim(parts[1]), 16)
        if l.kind == LEN_INVALID || lenIsAuto(l) { return false }
        anchorInsetFallback = resolveLen(l, 0, 0)
    }
    return true
}

// One `anchor-size()`. Same three globals-not-a-struct shape as
// `anchor()` above, and the same reason.
text anchorSizeName = ''
int anchorSizeDim = -1
int anchorSizeFallback = ANCHOR_NO_FALLBACK

// Which of the anchor's two dimensions a word names, or -1. The
// logical spellings are the physical ones here, as the side keywords
// are: there is no `writing-mode` to make them anything else.
int func anchorDimension(w:ascii) {
    if w == 'width' || w == 'inline' || w == 'self-inline' { return ANCHOR_DIM_WIDTH }
    if w == 'height' || w == 'block' || w == 'self-block' { return ANCHOR_DIM_HEIGHT }
    return -1
}

// `[ <name>? <dimension> ] , <fallback>?` -- the inside of one
// `anchor-size()`. Answers whether it parsed, and leaves what it said
// in the three globals above. Which property this is does not come
// into it: the dimension names the anchor's box, not the property's
// axis, which is measured rather than assumed (todo.md).
bool func parseAnchorSize(inner:ascii) {
    anchorSizeName = ''
    anchorSizeDim = -1
    anchorSizeFallback = ANCHOR_NO_FALLBACK
    arr[ascii] parts = asciiSplitChar(inner, CH_COMMA)
    if parts.length == 0 || parts.length > 2 { return false }
    arr[ascii] words = asciiSplitSpace(asciiTrim(parts[0]))
    if words.length == 0 || words.length > 2 { return false }
    int at = 0
    if words.length == 2 {
        if !asciiStartsWith(words[0], '--', 0) { return false }
        anchorSizeName = words[0].toText()
        at = 1
    }
    int dim = anchorDimension(words[at])
    if dim < 0 { return false }
    anchorSizeDim = dim
    if parts.length == 2 {
        Len l = parseLength(asciiTrim(parts[1]), 16)
        if l.kind == LEN_INVALID || lenIsAuto(l) { return false }
        anchorSizeFallback = resolveLen(l, 0, 0)
    }
    return true
}

// `auto | contain | none`, or -1 for anything else.
void func applyRuby(s:Style, parent:Style, isRoot:bool, props:map[text]) {
    int pos = isRoot ? RUBYPOS_OVER : rubyPositionOf(parent)
    ascii rp = styleProp(props, 'ruby-position')
    if rp != null {
        ascii t = asciiLower(asciiTrim(rp))
        if t == 'over' { pos = RUBYPOS_OVER }
        else if t == 'under' { pos = RUBYPOS_UNDER }
        else if t == 'alternate' { pos = RUBYPOS_ALTERNATE }
        else if t == 'inter-character' { pos = RUBYPOS_INTER_CHARACTER }
    }
    int al = isRoot ? RUBYALIGN_SPACE_AROUND : rubyAlignOf(parent)
    ascii ra = styleProp(props, 'ruby-align')
    if ra != null {
        ascii t = asciiLower(asciiTrim(ra))
        if t == 'space-around' { al = RUBYALIGN_SPACE_AROUND }
        else if t == 'start' { al = RUBYALIGN_START }
        else if t == 'center' { al = RUBYALIGN_CENTER }
        else if t == 'space-between' { al = RUBYALIGN_SPACE_BETWEEN }
    }
    if pos != RUBYPOS_OVER { rubyPositionOfSerial[`${s.serial}`] = pos  anyRuby = true }
    if al != RUBYALIGN_SPACE_AROUND { rubyAlignOfSerial[`${s.serial}`] = al  anyRuby = true }
}

int func textWrapStyleKeyword(w:ascii) {
    if w == 'balance' { return TWS_BALANCE }
    if w == 'pretty' { return TWS_PRETTY }
    if w == 'stable' { return TWS_STABLE }
    return TWS_AUTO
}

// `text-wrap-style` inherits, and the `text-wrap` shorthand is
// `<text-wrap-mode> || <text-wrap-style>` -- the two halves in either
// order, either one alone. The mode half is applied where the rest of
// `white-space` is; only the style half belongs here.
// `print-color-adjust` inherits, so an element with no declaration of
// its own takes the parent's -- which is what makes `exact` on a
// wrapper reach everything inside it, and what lets a child withdraw
// it again with `economy`. Both were measured (todo.md).
void func applyPrintColorAdjust(s:Style, parent:Style, isRoot:bool, props:map[text]) {
    int v = isRoot ? PCA_ECONOMY : printColorAdjustOf(parent)
    ascii pca = styleProp(props, 'print-color-adjust')
    if pca != null {
        ascii k = asciiLower(asciiTrim(pca))
        if k == 'exact' { v = PCA_EXACT }
        else if k == 'economy' { v = PCA_ECONOMY }
    }
    if v != PCA_ECONOMY {
        printColorAdjustOfSerial[`${s.serial}`] = v
        anyPrintColorAdjust = true
    }
}

// `font-variant-caps` inherits. No face this engine can reach carries a
// small-caps feature, so the value is a drawing instruction rather than
// a font selection: the reader in layout turns it into a smaller size
// for the letters it applies to (CSS Fonts 4 §5.3, and the synthesis
// §2.2 allows). `font-variant`'s one-keyword form reaches the same
// value, which is the only part of that shorthand this engine has.
void func applyFontCaps(s:Style, parent:Style, isRoot:bool, props:map[text]) {
    int v = isRoot ? CAPS_NORMAL : fontCapsOf(parent)
    // `font-variant` reaches here as `font-variant-caps`, which
    // applyDecl expanded it into.
    ascii decl = styleProp(props, 'font-variant-caps')
    if decl != null {
        ascii k = asciiLower(asciiTrim(decl))
        if k == 'small-caps' { v = CAPS_SMALL }
        else if k == 'all-small-caps' { v = CAPS_ALL_SMALL }
        else if k == 'normal' || k == 'none' { v = CAPS_NORMAL }
    }
    if v != CAPS_NORMAL {
        fontCapsOfSerial[`${s.serial}`] = v
        anySmallCaps = true
    }
}

void func applyTextWrapStyle(s:Style, parent:Style, isRoot:bool, props:map[text]) {
    int v = isRoot ? TWS_AUTO : textWrapStyleOf(parent)
    // `text-wrap` reaches here as its two longhands, which applyDecl
    // expanded it into, so there is nothing to read under the
    // shorthand's own name.
    ascii tws = styleProp(props, 'text-wrap-style')
    if tws != null { v = textWrapStyleKeyword(asciiLower(asciiTrim(tws))) }
    if v != TWS_AUTO {
        textWrapStyleOfSerial[`${s.serial}`] = v
        anyTextWrapStyle = true
    }
}

int func resizeKeyword(w:ascii) {
    if w == 'both' { return RESIZE_BOTH }
    if w == 'horizontal' { return RESIZE_HORIZONTAL }
    if w == 'vertical' { return RESIZE_VERTICAL }
    if w == 'block' { return RESIZE_BLOCK }
    if w == 'inline' { return RESIZE_INLINE }
    return RESIZE_NONE
}

int func overscrollKeyword(w:ascii) {
    if w == 'auto' { return OSB_AUTO }
    if w == 'contain' { return OSB_CONTAIN }
    if w == 'none' { return OSB_NONE }
    return -1
}

int func textBoxTrimKeyword(w:ascii) {
    if w == 'trim-both' { return TBTRIM_BOTH }
    if w == 'trim-start' { return TBTRIM_START }
    if w == 'trim-end' { return TBTRIM_END }
    if w == 'none' { return TBTRIM_NONE }
    return -1
}

// `text-box-edge: auto | <text-edge>`, where a bare over-edge keyword is
// *not* a value: Chromium computes `cap` alone back to `auto`, and only
// `auto`, `text` and a pair are taken (todo.md records the measurement).
// Returns over * 4 + under, or -1 for a value that is none of those.
int func textBoxEdgePair(words:arr[ascii], from:int) {
    int n = words.length - from
    if n <= 0 { return -1 }
    if n == 1 {
        if words[from] == 'auto' || words[from] == 'text' {
            return TBOVER_TEXT * 4 + TBUNDER_TEXT
        }
        return -1
    }
    int over = -1
    if words[from] == 'text' { over = TBOVER_TEXT }
    else if words[from] == 'cap' { over = TBOVER_CAP }
    else if words[from] == 'ex' { over = TBOVER_EX }
    if over < 0 { return -1 }
    int under = -1
    if words[from + 1] == 'text' { under = TBUNDER_TEXT }
    else if words[from + 1] == 'alphabetic' { under = TBUNDER_ALPHABETIC }
    if under < 0 { return -1 }
    return over * 4 + under
}

// ---- CSS Motion Path 1 ---------------------------------------------------

// `offset-path: none | ray() | <basic-shape> | path()`. The basic
// shapes are the ones `clip-path` already reads, so they are read the
// same way; a ray and a path() are this property's own.
// The SVG geometry a fragment reference names. Foreign elements are in
// the DOM with their attributes -- `insertForeignElement` puts them
// there -- whether or not anything ever draws one, which is the whole
// reason `offset-path: url()` needs no SVG rendering.
//
// All seven geometry elements are travelled, and none of them needed new
// machinery. `motionPolygon` travels a CLIPSHAPE_POLYGON and
// `motionPathData` travels a path string, and every shape is one or the
// other: a `<rect>` is the polygon of its four corners, clockwise from
// (x, y), which is where Chromium starts and the way it goes; a `<line>`
// and a `<polyline>` are `M ... L ...`, which is open, where a polygon
// closes itself and would double the distance.
//
// A `<rect>` carrying `rx` or `ry` is travelled as though its corners
// were sharp. Chromium rounds them, so that one case is wrong here, and
// it is written down rather than hidden (todo.md).
bool func isSvgMotionShape(tag:text) {
    return tag == 'path' || tag == 'circle' || tag == 'ellipse'
        || tag == 'polygon' || tag == 'rect' || tag == 'line' || tag == 'polyline'
}

Node func svgShapeById(n:Node, want:text) {
    if n.kind == NODE_ELEMENT && isSvgMotionShape(n.tag)
        && attrOf(n.id, 'id') == want { return n }
    for int i = 0, i < n.children.length, i++ {
        Node f = svgShapeById(n.children[i], want)
        if f != null { return f }
    }
    return null
}

// The numbers in an SVG attribute, which separates them by commas, by
// spaces or by both. Scanned rather than split, so that `0,60 100,60`
// and `0 60 100 60` read the same.
arr[Len] func svgNumbers(t:text, fontSize:int) {
    arr[Len] out = []
    ascii a = t.toAscii()
    if a == null { return out }
    int i = 0
    while i < a.length {
        int c = a.charCodeAt(i)
        if !(isDigitCode(c) || c == CH_DOT || c == CH_MINUS || c == CH_PLUS) {
            i++
            continue
        }
        int from = i
        while i < a.length {
            int d = a.charCodeAt(i)
            if isDigitCode(d) || d == CH_DOT || d == CH_MINUS || d == CH_PLUS {
                i++
            } else {
                break
            }
        }
        Len l = parseLength(a.slice(from, i), fontSize)
        if l.kind != LEN_AUTO { out.push(l) }
    }
    return out
}

// A `<rect>`'s corner radius, which is not `svgAttrLen` because the
// three ways it can be missing are three different answers, all
// measured against Chromium rather than read off SVG 2 section 10.2
// (todo.md):
//
//   absent        -- `auto`, which is the other axis
//   negative      -- also `auto`; Chromium rounds `rx=-5 ry=10` by ten
//   `auto` itself -- zero, so the corners are sharp, which is NOT what
//                    the standard says the keyword means
//
// The last is a divergence and is written down as one.
const float SVG_RADIUS_AUTO = 0.0 - 1.0

float func svgRectRadius(e:Node, name:text, fontSize:int) {
    text v = attrOf(e.id, name)
    if v == null { return SVG_RADIUS_AUTO }
    arr[Len] n = svgNumbers(v, fontSize)
    if n.length == 0 { return 0.0 }
    return n[0].v < 0.0 ? SVG_RADIUS_AUTO : n[0].v
}

// SVG 1.1 section 9.2's own equivalent path for a rounded rectangle:
// four sides joined by four quarter-ellipse arcs, starting at
// (x + rx, y) and running clockwise. `motionPathData` has read `A` since
// the curve commands landed, so this needs no primitive of its own.
text func svgRoundRectPath(x:float, y:float, w:float, h:float, rx:float, ry:float) {
    return `M ${x + rx} ${y} H ${x + w - rx} A ${rx} ${ry} 0 0 1 ${x + w} ${y + ry}`
        + ` V ${y + h - ry} A ${rx} ${ry} 0 0 1 ${x + w - rx} ${y + h}`
        + ` H ${x + rx} A ${rx} ${ry} 0 0 1 ${x} ${y + h - ry}`
        + ` V ${y + ry} A ${rx} ${ry} 0 0 1 ${x + rx} ${y} Z`
}

Len func svgAttrLen(e:Node, name:text, fontSize:int) {
    text v = attrOf(e.id, name)
    if v == null { return lenPx(0.0) }
    arr[Len] n = svgNumbers(v, fontSize)
    return n.length > 0 ? n[0] : lenPx(0.0)
}

// Fills `mi` from whatever a `url(#id)` named. Every way the reference
// can fail -- no such element, an element that is not one of the four, a
// `<path>` with no `d` -- leaves an EMPTY path rather than `none`, which
// is measured against Chromium: the offset still applies and puts the
// box on the path's single point at the origin, where `none` leaves it
// where the flow put it (todo.md).
void func motionFromSvgShape(mi:MotionInfo, nid:int, want:text, fontSize:int) {
    mi.pathData = ''
    mi.pathKind = MPATH_PATH
    if nid <= 0 || nid >= nodeRegistry.length { return }
    Node root = nodeRegistry[documentRootOf(nid)]
    if root == null { return }
    Node e = svgShapeById(root, want)
    if e == null { return }
    if e.tag == 'path' {
        text d = attrOf(e.id, 'd')
        if d != null { mi.pathData = d }
        return
    }
    // A line and a polyline are open, so they become path data, which
    // the motion code already travels. Everything else is a shape.
    if e.tag == 'line' {
        mi.pathData = `M ${svgAttrLen(e, 'x1', fontSize).v} ${svgAttrLen(e, 'y1', fontSize).v}`
            + ` L ${svgAttrLen(e, 'x2', fontSize).v} ${svgAttrLen(e, 'y2', fontSize).v}`
        return
    }
    if e.tag == 'polyline' {
        arr[Len] pl = svgNumbers(attrOf(e.id, 'points'), fontSize)
        if pl.length < 4 { return }
        text d = `M ${pl[0].v} ${pl[1].v}`
        for int i = 2, i + 1 < pl.length, i = i + 2 {
            d = d + ` L ${pl[i].v} ${pl[i + 1].v}`
        }
        mi.pathData = d
        return
    }
    ClipShape sh
    sh.kind = CLIPSHAPE_NONE
    sh.geoBox = GEOBOX_BORDER
    if e.tag == 'rect' {
        Len rx = svgAttrLen(e, 'x', fontSize)
        Len ry = svgAttrLen(e, 'y', fontSize)
        Len rw = svgAttrLen(e, 'width', fontSize)
        Len rh = svgAttrLen(e, 'height', fontSize)
        if rw.v <= 0.0 || rh.v <= 0.0 { return }
        float crx = svgRectRadius(e, 'rx', fontSize)
        float cry = svgRectRadius(e, 'ry', fontSize)
        if crx == SVG_RADIUS_AUTO { crx = cry }
        if cry == SVG_RADIUS_AUTO { cry = crx }
        if crx == SVG_RADIUS_AUTO { crx = 0.0 }
        if cry == SVG_RADIUS_AUTO { cry = 0.0 }
        // Each is clamped to half its own side, which the start point
        // alone cannot show: (50, 0) is where rx=50 starts whatever ry
        // is, so the clamp was measured a tenth of the way round.
        if crx > rw.v / 2.0 { crx = rw.v / 2.0 }
        if cry > rh.v / 2.0 { cry = rh.v / 2.0 }
        // A zero in either axis is sharp, so the polygon below still
        // serves every rect that asks for no rounding.
        if crx > 0.0 && cry > 0.0 {
            mi.pathData = svgRoundRectPath(rx.v, ry.v, rw.v, rh.v, crx, cry)
            return
        }
        sh.kind = CLIPSHAPE_POLYGON
        sh.pointsX = [rx, lenPx(rx.v + rw.v), lenPx(rx.v + rw.v), rx]
        sh.pointsY = [ry, ry, lenPx(ry.v + rh.v), lenPx(ry.v + rh.v)]
    } else if e.tag == 'polygon' {
        arr[Len] nums = svgNumbers(attrOf(e.id, 'points'), fontSize)
        if nums.length < 6 { return }
        arr[Len] xs = []
        arr[Len] ys = []
        for int i = 0, i + 1 < nums.length, i = i + 2 {
            xs.push(nums[i])
            ys.push(nums[i + 1])
        }
        sh.kind = CLIPSHAPE_POLYGON
        sh.pointsX = xs
        sh.pointsY = ys
    } else {
        sh.kind = e.tag == 'circle' ? CLIPSHAPE_CIRCLE : CLIPSHAPE_ELLIPSE
        sh.centreX = svgAttrLen(e, 'cx', fontSize)
        sh.centreY = svgAttrLen(e, 'cy', fontSize)
        sh.radiusXKind = CLIPRAD_LENGTH
        sh.radiusYKind = CLIPRAD_LENGTH
        if e.tag == 'circle' {
            Len r = svgAttrLen(e, 'r', fontSize)
            sh.radiusX = r
            sh.radiusY = r
        } else {
            sh.radiusX = svgAttrLen(e, 'rx', fontSize)
            sh.radiusY = svgAttrLen(e, 'ry', fontSize)
        }
    }
    mi.shape = sh
    mi.pathKind = MPATH_SHAPE
}

void func motionReadPath(mi:MotionInfo, v:ascii, fontSize:int, nid:int) {
    mi.pathKind = MPATH_NONE
    if v == null { return }
    ascii t = asciiTrim(v)
    if t.length == 0 { return }
    ascii lower = asciiLower(t)
    if lower == 'none' { return }
    // `url(#id)` travels the `d` of the SVG <path> it names. The path is
    // never drawn -- there is no SVG rendering here -- and does not have
    // to be: only its attribute is read.
    if asciiStartsWith(lower, 'url(', 0) {
        int uclose = asciiMatchingParen(t, 3)
        if uclose < 0 { return }
        int ufrom = 4
        int uto = uclose
        while ufrom < uto && isSpaceCode(t.charCodeAt(ufrom)) { ufrom++ }
        while uto > ufrom && isSpaceCode(t.charCodeAt(uto - 1)) { uto-- }
        if uto - ufrom >= 2 {
            int uq = t.charCodeAt(ufrom)
            if (uq == CH_QUOTE || uq == CH_APOS) && t.charCodeAt(uto - 1) == uq {
                ufrom++
                uto--
            }
        }
        if uto > ufrom && t.charCodeAt(ufrom) == CH_HASH { ufrom++ }
        // A reference to nothing is still a path -- an empty one.
        if uto > ufrom {
            motionFromSvgShape(mi, nid, t.slice(ufrom, uto).toText(), fontSize)
        } else {
            mi.pathData = ''
            mi.pathKind = MPATH_PATH
        }
        return
    }
    if asciiStartsWith(lower, 'ray(', 0) {
        int close = asciiMatchingParen(t, 3)
        if close < 0 { return }
        // The lowered argument is held in a local and its words are
        // indexed rather than bound: `ascii w = parts[i]` is an alias
        // the runtime never retains and then releases twice, which
        // valgrind sees and an ordinary run does not. See FINDINGS.md,
        // "ascii aliases are not retained".
        ascii rayLow = asciiLower(t.slice(4, close))
        arr[ascii] parts = asciiSplitSpace(rayLow)
        bool sawAngle = false
        mi.raySize = RAYSIZE_CLOSEST_SIDE
        for int i = 0, i < parts.length, i++ {
            if parts[i] == 'closest-side' { mi.raySize = RAYSIZE_CLOSEST_SIDE }
            else if parts[i] == 'closest-corner' { mi.raySize = RAYSIZE_CLOSEST_CORNER }
            else if parts[i] == 'farthest-side' { mi.raySize = RAYSIZE_FARTHEST_SIDE }
            else if parts[i] == 'farthest-corner' { mi.raySize = RAYSIZE_FARTHEST_CORNER }
            else if parts[i] == 'sides' { mi.raySize = RAYSIZE_SIDES }
            else if parts[i] == 'contain' { continue }
            else {
                arr[bool] ok = [false]
                float deg = parseAngleDegrees(parts[i], ok)
                if ok[0] { mi.rayAngle = deg  sawAngle = true }
            }
        }
        if !sawAngle { return }
        mi.pathKind = MPATH_RAY
        return
    }
    // `path()` carries SVG commands, which are case-sensitive: `m` is
    // not `M`. So its argument is taken from the unlowered value.
    if asciiStartsWith(lower, 'path(', 0) {
        int close = asciiMatchingParen(t, 4)
        if close < 0 { return }
        // The trimming and unquoting are indices into `t`, and the
        // argument is cut from it once. Slicing a slice of a trim
        // aliases a buffer that is then released twice (FINDINGS.md,
        // "Slicing an ascii that came from a slice").
        int from = 5
        int to = close
        while from < to && isSpaceCode(t.charCodeAt(from)) { from++ }
        while to > from && isSpaceCode(t.charCodeAt(to - 1)) { to-- }
        if to - from >= 2 {
            int q = t.charCodeAt(from)
            if (q == CH_QUOTE || q == CH_APOS) && t.charCodeAt(to - 1) == q {
                from++
                to--
            }
        }
        if to <= from { return }
        mi.pathData = t.slice(from, to).toText()
        mi.pathKind = MPATH_PATH
        return
    }
    ClipShape sh = parseClipPath(lower, fontSize)
    if sh.kind == CLIPSHAPE_CIRCLE || sh.kind == CLIPSHAPE_ELLIPSE
        || sh.kind == CLIPSHAPE_POLYGON {
        mi.shape = sh
        mi.pathKind = MPATH_SHAPE
    }
}

// `offset-rotate: [ auto | reverse ] || <angle>`. There is no `none`,
// so a declaration saying it is dropped and the initial `auto` stands
// -- which is what the measurement's first round read as a control and
// was not one.
void func motionReadRotate(mi:MotionInfo, v:ascii) {
    if v == null { return }
    // Held in a local and indexed, never bound (FINDINGS.md, "ascii
    // aliases are not retained").
    ascii rotLow = asciiLower(asciiTrim(v))
    arr[ascii] parts = asciiSplitSpace(rotLow)
    if parts.length == 0 { return }
    int mode = -1
    float angle = 0.0
    bool sawAngle = false
    for int i = 0, i < parts.length, i++ {
        if parts[i] == 'auto' { mode = MROT_AUTO  continue }
        if parts[i] == 'reverse' { mode = MROT_REVERSE  continue }
        arr[bool] ok = [false]
        float deg = parseAngleDegrees(parts[i], ok)
        if !ok[0] { return }
        angle = deg
        sawAngle = true
    }
    if mode < 0 && !sawAngle { return }
    mi.rotateMode = mode < 0 ? MROT_ANGLE : mode
    mi.rotateAngle = angle
}

// The `anchor-size()` slots an element that said nothing gets. They are
// shared rather than built per element: three fourteen-slot arrays
// allocated for every element of every page is what the six-slot
// version already cost, and this made it fourteen. Nothing writes to
// them -- an element that does say `anchor-size()` builds its own --
// so one copy is safe for the whole program.
arr[text] anchorSizeNoNames = ['', '', '', '', '', '', '', '', '', '', '', '', '', '']
arr[text] anchorSizeNoExprs = ['', '', '', '', '', '', '', '', '', '', '', '', '', '']
arr[int] anchorSizeNoDims = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]
arr[int] anchorSizeNoFalls = [ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                              ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                              ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                              ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                              ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK]

// The key the text measurer caches widths under. Anything that changes
// the font after the style is computed has to rebuild it, or the cache
// answers for the font the style used to have: `initial-letter` scaled
// a drop cap to 106px and got the paragraph's 20px advance back.
void func refreshFontKey(s:Style) {
    // The zoom is in the key because the font the text is SET in is
    // the computed size times it, and the width cache is keyed on this
    // -- without it one zoom's advance is served at another, which is
    // the drop cap's stale-key bug in a different coat.
    s.fontKey = `${s.fontSize}|${s.fontBold ? 1 : 0}|${s.fontItalic ? 1 : 0}|${s.fontFamily}`
    if anyZoom {
        int zk = zoomOfSerial[`${s.serial}`]
        if zk != null { s.fontKey = s.fontKey + `|${zk}` }
    }
    // Synthesised small caps draws part of a run at a smaller size, so
    // two styles alike but for the keyword measure differently -- and
    // the width cache is keyed on this. Leaving it out serves one
    // style's advance to the other, which is the drop cap's stale-key
    // bug a third time.
    if anySmallCaps {
        int ck = fontCapsOfSerial[`${s.serial}`]
        if ck != null { s.fontKey = s.fontKey + `|c${ck}` }
    }
}

Style func computeStyleValues(n:Node, parentIn:Style, isRootIn:bool, props:map[text]) {
    Style s
    Style parent = parentIn
    // `all: initial` computes the element as though it had no parent at
    // all, which is what every default below already means by `isRoot`.
    // A declaration after it -- including one saying `inherit` -- still
    // resolves against the real parent, so only the defaults change.
    bool isRoot = isRootIn || styleProp(props, 'all') != null
    s.serial = styleSerialNext
    styleSerialNext++
    cascadeParentStyle = parent
    cascadeParentIsRoot = isRootIn

    // Custom properties inherit. An element that declares none shares
    // its parent's map rather than copying it, which matters: on a real
    // page almost nothing declares one.
    map[text] emptyCustom = {}
    map[text] inheritedCustom = isRoot ? emptyCustom : parent.customProps
    if inheritedCustom == null { inheritedCustom = emptyCustom }
    arr[text] declared = props.keys()
    bool addsCustom = false
    for int i = 0, i < declared.length, i++ {
        text k = declared[i]
        // `text` indexes without allocating; `k.toAscii()` here built a
        // fresh ascii per key per element, which on this page was tens
        // of thousands of allocations to read two characters.
        if k.length > 1 && k.charCodeAt(0) == CH_MINUS && k.charCodeAt(1) == CH_MINUS {
            addsCustom = true
            break
        }
    }
    if addsCustom {
        map[text] merged = {}
        arr[text] ik = inheritedCustom.keys()
        for int i = 0, i < ik.length, i++ { merged[ik[i]] = inheritedCustom[ik[i]] }
        for int i = 0, i < declared.length, i++ {
            text k = declared[i]
            ascii ka = k.toAscii()
            if ka != null && ka.length > 1 && ka.charCodeAt(0) == CH_MINUS && ka.charCodeAt(1) == CH_MINUS {
                merged[k] = props[k]
            }
        }
        s.customProps = merged
    } else {
        s.customProps = inheritedCustom
    }
    cascadeCustom = s.customProps
    // inherited
    int parentFont = isRoot ? ROOT_FONT_SIZE : parent.fontSize
    s.fontSize = computeFontSize(styleProp(props, 'font-size'), parentFont)
    // `rem` multiplies this, and the root is computed before anything
    // that can refer to it.
    if isRoot { cssRootFontSize = s.fontSize }
    // `zoom` goes up HERE: after the font size, which stays unzoomed so
    // that a child's `em` resolves against it once, and before every
    // other length, each of which is multiplied as `lenPx` builds it.
    if cascadeSawZoom { applyZoom(s, parent, isRoot, props) }
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
    // Before the key is built, because the key folds the keyword in:
    // a style resolved after it would get a key that does not mention
    // the smaller size its text is partly drawn at, and the width cache
    // would serve the plain run's advance to the small-caps one.
    if cascadeSawFontCaps { applyFontCaps(s, parent, isRoot, props) }
    refreshFontKey(s)
    // CSS Color Adjustment 1 §2. `color-scheme` is inherited, and it
    // has to be resolved before anything on this element parses a
    // colour, because a system colour name answers according to it.
    //
    // The list is resolved against the user's own preference, which
    // this browser reports as light (Media Queries 4), so a list that
    // offers `light` is light whatever order it is written in and only
    // a list offering `dark` without `light` is dark. `only` says how
    // far a user agent may override the choice and does not change it;
    // an ident nobody knows is carried along and ignored, which leaves
    // a list of nothing but unknown idents resolving as `normal` does.
    s.colorSchemeDark = isRoot ? false : parent.colorSchemeDark
    if cascadeSawColorScheme {
        ascii csch = styleProp(props, 'color-scheme')
        if csch != null {
            arr[ascii] schemes = asciiSplitSpace(asciiLower(asciiTrim(csch)))
            bool sawLight = false
            bool sawDark = false
            for int i = 0, i < schemes.length, i++ {
                if schemes[i] == 'light' { sawLight = true }
                else if schemes[i] == 'dark' { sawDark = true }
            }
            s.colorSchemeDark = sawDark && !sawLight
        }
        cssSchemeIsDark = s.colorSchemeDark
    }
    s.color = colorProp(props, 'color', isRoot ? COLOR_BLACK : parent.color, isRoot ? COLOR_BLACK : parent.color)
    s.lineHeight = isRoot ? 0 : zoomInherit(parent.lineHeight, parent)
    // `lh` inside `line-height` itself is the parent's, the way `em`
    // inside `font-size` is: the value being computed cannot be its own
    // unit. So the global carries the inherited line height across the
    // declaration below and is set to this element's own afterwards,
    // where every other length will read it.
    cascadeLineHeight = isRoot ? lineHeightFor(0, s.fontSize)
                              : lineHeightFor(parent.lineHeight, parent.fontSize)
    ascii lh = styleProp(props, 'line-height')
    if lh != null {
        ascii t = asciiLower(asciiTrim(lh))
        if t == 'normal' { s.lineHeight = 0 }
        else if t != 'inherit' {
            parseNumberAt(t, 0)
            if numOk {
                ascii unit = t.slice(numEnd, t.length)
                if unit == '' { s.lineHeight = zoomHere(roundPx(numValue * s.fontSize.toFloat())) }
                else {
                    Len l = parseLength(t, s.fontSize)
                    if l.kind == LEN_PX { s.lineHeight = roundPx(l.v) }
                    else if l.kind == LEN_PERCENT { s.lineHeight = zoomHere(roundPx(s.fontSize.toFloat() * l.v / 100.0)) }
                }
            }
        }
    }
    cascadeLineHeight = lineHeightFor(s.lineHeight, s.fontSize)
    if isRoot { cssRootLineHeight = cascadeLineHeight }
    // direction inherits, and text-align's `start` and `end` resolve
    // against it, so it is read before text-align rather than after.
    // `direction` is one of the two properties `all` does not reset
    // (Cascade 4 §3.2), so it inherits from the real parent whatever
    // `all` said -- which is why this asks isRootIn rather than isRoot.
    s.directionRtl = isRootIn ? false : parent.directionRtl
    ascii dirv = styleProp(props, 'direction')
    if dirv != null {
        ascii t = asciiLower(asciiTrim(dirv))
        if t == 'rtl' { s.directionRtl = true }
        else if t == 'ltr' { s.directionRtl = false }
    }
    // `writing-mode` inherits, and the logical properties resolve
    // against it, so it is read here beside `direction` for the same
    // reason. A vertical mode is recorded for the document as a whole
    // as well: layout and paint both ask per box whether they are in
    // one, and on a page with no vertical text that question is a
    // boolean rather than a walk.
    s.writingMode = isRootIn ? WM_HORIZONTAL_TB : parent.writingMode
    ascii wmv = styleProp(props, 'writing-mode')
    if wmv != null {
        int k = writingModeKeyword(asciiLower(asciiTrim(wmv)))
        if k >= 0 { s.writingMode = k }
    }
    if s.writingMode != WM_HORIZONTAL_TB { anyVerticalWM = true }
    // `text-orientation` inherits too, and says nothing in a horizontal
    // mode (Writing Modes 4 §5.1).
    s.textOrientation = isRootIn ? TO_MIXED : parent.textOrientation
    ascii torv = styleProp(props, 'text-orientation')
    if torv != null {
        ascii tt = asciiLower(asciiTrim(torv))
        if tt == 'upright' { s.textOrientation = TO_UPRIGHT }
        else if tt == 'sideways' || tt == 'sideways-right' { s.textOrientation = TO_SIDEWAYS }
        else if tt == 'mixed' { s.textOrientation = TO_MIXED }
    }
    // `unicode-bidi` does not inherit: an element opens an embedding of
    // its own or it does not, and its children decide that again.
    s.unicodeBidi = UBIDI_NORMAL
    ascii ubidi = styleProp(props, 'unicode-bidi')
    if ubidi != null {
        s.unicodeBidi = unicodeBidiKeyword(asciiLower(asciiTrim(ubidi)))
        if s.unicodeBidi != UBIDI_NORMAL { anyUnicodeBidi = true }
    }
    s.textAlignExplicit = isRoot ? false : parent.textAlignExplicit
    s.textAlign = isRoot ? ALIGN_LEFT : parent.textAlign
    ascii ta = styleProp(props, 'text-align')
    if ta != null {
        ascii t = asciiLower(ta)
        // `start` and `end` are the two ends of the inline axis, which
        // swap with the direction; `left` and `right` never do.
        if t == 'left' { s.textAlign = ALIGN_LEFT  s.textAlignExplicit = true }
        else if t == 'right' { s.textAlign = ALIGN_RIGHT  s.textAlignExplicit = true }
        else if t == 'center' { s.textAlign = ALIGN_CENTER  s.textAlignExplicit = true }
        else if t == 'start' { s.textAlignExplicit = false }
        else if t == 'end' {
            // the far end, which is the side the direction is not
            s.textAlign = s.directionRtl ? ALIGN_LEFT : ALIGN_RIGHT
            s.textAlignExplicit = true
        }
        else if t == 'justify' { s.textAlignExplicit = false }
    }
    // The initial value is `start`, and so is anything that resolves to
    // it, so an element with no side of its own follows its direction.
    if !s.textAlignExplicit { s.textAlign = s.directionRtl ? ALIGN_RIGHT : ALIGN_LEFT }
    // text-align-last aligns the last line of a block, and the line
    // before a forced break. `auto` -- the initial value -- is not an
    // alignment but an absence of one, so it is kept as -1 rather than
    // folded into text-align: the line must be able to ask whether it
    // was set at all.
    s.textAlignLast = isRoot ? -1 : parent.textAlignLast
    ascii tal = styleProp(props, 'text-align-last')
    if tal != null {
        ascii t = asciiLower(tal)
        if t == 'auto' { s.textAlignLast = -1 }
        else if t == 'left' { s.textAlignLast = ALIGN_LEFT }
        else if t == 'right' { s.textAlignLast = ALIGN_RIGHT }
        else if t == 'start' { s.textAlignLast = s.directionRtl ? ALIGN_RIGHT : ALIGN_LEFT }
        else if t == 'end' { s.textAlignLast = s.directionRtl ? ALIGN_LEFT : ALIGN_RIGHT }
        else if t == 'center' { s.textAlignLast = ALIGN_CENTER }
        else if t == 'justify' { s.textAlignLast = s.directionRtl ? ALIGN_RIGHT : ALIGN_LEFT }
    }
    // text-decoration is NOT an inherited property: the element's own
    // computed value starts at none. What the standard does instead is
    // propagate the decoration of an ancestor to the boxes inside it,
    // which is what inheritedDecoration carries for the painter.
    s.inheritedDecoration = isRoot ? DECO_NONE : decoUnion(parent.inheritedDecoration, parent.textDecoration)
    // How a propagated decoration is drawn travels with it: the
    // standard draws an ancestor's decoration in the ancestor's colour
    // and style across every descendant it crosses. A parent that
    // decorates something hands its own appearance down; one that does
    // not passes on what it was handed.
    if isRoot {
        s.inheritedDecoColor = COLOR_UNSET
        s.inheritedDecoStyle = DECOSTYLE_SOLID
        s.inheritedDecoThickness = 0
        s.inheritedDecoOffset = 0
    } else if parent.textDecoration != DECO_NONE {
        s.inheritedDecoColor = parent.decorationColor == COLOR_UNSET ? parent.color : parent.decorationColor
        s.inheritedDecoStyle = parent.decorationStyle
        s.inheritedDecoThickness = parent.decorationThickness
        s.inheritedDecoOffset = parent.underlineOffset
    } else {
        s.inheritedDecoColor = parent.inheritedDecoColor
        s.inheritedDecoStyle = parent.inheritedDecoStyle
        s.inheritedDecoThickness = parent.inheritedDecoThickness
        s.inheritedDecoOffset = parent.inheritedDecoOffset
    }
    // `text-decoration` reaches here as its four longhands, which
    // applyDecl expanded it into, so there is nothing to read under the
    // shorthand's own name.
    s.textDecoration = DECO_NONE
    s.decorationColor = COLOR_UNSET
    s.decorationStyle = DECOSTYLE_SOLID
    s.decorationThickness = 0
    s.underlineOffset = 0
    ascii tdl = styleProp(props, 'text-decoration-line')
    if tdl != null {
        arr[ascii] lt = cssTokens(tdl)
        int deco = 0
        for int i = 0, i < lt.length, i++ {
            ascii t = asciiLower(lt[i])
            if t == 'underline' { deco = deco + DECO_UNDERLINE }
            else if t == 'line-through' { deco = deco + DECO_LINE_THROUGH }
            else if t == 'overline' { deco = deco + DECO_OVERLINE }
        }
        s.textDecoration = deco
    }
    ascii tdc = styleProp(props, 'text-decoration-color')
    if tdc != null {
        int c = parseCssColor(asciiTrim(tdc), s.color)
        if c != COLOR_UNSET { s.decorationColor = c }
    }
    ascii tds = styleProp(props, 'text-decoration-style')
    if tds != null {
        int st = decorationStyleKeyword(asciiLower(asciiTrim(tds)))
        if st >= 0 { s.decorationStyle = st }
    }
    // `auto` and `from-font` both leave the thickness to the engine,
    // which derives it from the font size, and that is the zero value.
    ascii tdt2 = styleProp(props, 'text-decoration-thickness')
    if tdt2 != null {
        Len l = parseLength(asciiTrim(tdt2), s.fontSize)
        if l.kind == LEN_PX { s.decorationThickness = maxInt(roundPx(l.v), 0) }
    }
    // text-emphasis. The style resolves to the character to draw, so
    // the painter needs no table and a `<string>` value needs no
    // special case. `filled` and `open` pick between two shapes of the
    // same mark; `filled` is the default.
    s.emphasisColor = COLOR_UNSET
    ascii tes = styleProp(props, 'text-emphasis-style')
    if tes != null { s.emphasisMark = emphasisMarkFor(tes) }
    ascii tec = styleProp(props, 'text-emphasis-color')
    if tec != null {
        int c = parseCssColor(asciiTrim(tec), s.color)
        if c != COLOR_UNSET { s.emphasisColor = c }
    }
    ascii tep = styleProp(props, 'text-emphasis-position')
    if tep != null {
        s.emphasisUnder = asciiIndexOf(asciiLower(tep), 'under'.toAscii(), 0) >= 0
    }
    // text-underline-position: `under` drops the underline below the
    // descenders. `left` and `right` only mean anything in a vertical
    // writing mode, which this engine does not have, so they behave as
    // `auto` -- css-2026.md says so.
    ascii tup = styleProp(props, 'text-underline-position')
    if tup != null {
        s.underlinePosUnder = asciiLower(asciiTrim(tup)) == 'under'
    }
    ascii tuo = styleProp(props, 'text-underline-offset')
    if tuo != null {
        Len l = parseLength(asciiTrim(tuo), s.fontSize)
        if l.kind == LEN_PX { s.underlineOffset = roundPx(l.v) }
    }
    // text-shadow is box-shadow's grammar without `inset` or a spread.
    ascii tsh = styleProp(props, 'text-shadow')
    if tsh != null {
        ascii tshLow = asciiLower(asciiTrim(tsh))
        if tshLow != 'none' && tshLow != '' {
            arr[Shadow] list = []
            arr[ascii] pieces = splitTopLevelCommas(tsh)
            for int i = 0, i < pieces.length, i++ {
                Shadow sh = parseShadow(pieces[i], s.color, s.fontSize)
                if sh != null { sh.spread = 0  sh.inset = false  list.push(sh) }
            }
            if list.length > 0 { s.textShadows = list }
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
    s.quotes = isRoot ? '' : parent.quotes
    ascii qv = styleProp(props, 'quotes')
    if qv != null { s.quotes = qv.toText() }
    // white-space is a shorthand for white-space-collapse and
    // text-wrap-mode. It is expanded here rather than in the shorthand
    // pass because both longhands inherit, so the inherited pair has to
    // be in place before either the shorthand or a longhand overrides
    // part of it.
    s.whiteSpaceCollapse = isRoot ? WSC_COLLAPSE : parent.whiteSpaceCollapse
    s.textWrapMode = isRoot ? WRAP_WRAP : parent.textWrapMode
    // `white-space` reaches here as its two longhands, which applyDecl
    // expanded it into. `break-spaces` arrives as a
    // `white-space-collapse` of its own name and is folded onto
    // `preserve` below, because it differs from `pre-wrap` only in
    // where a line may break inside a run of preserved spaces, which
    // this engine does not do either way.
    ascii wsc = styleProp(props, 'white-space-collapse')
    if wsc != null {
        ascii t = asciiLower(wsc)
        if t == 'collapse' { s.whiteSpaceCollapse = WSC_COLLAPSE }
        else if t == 'preserve' || t == 'break-spaces' { s.whiteSpaceCollapse = WSC_PRESERVE }
        else if t == 'preserve-breaks' { s.whiteSpaceCollapse = WSC_PRESERVE_BREAKS }
        else if t == 'preserve-spaces' { s.whiteSpaceCollapse = WSC_PRESERVE }
    }
    ascii twm = styleProp(props, 'text-wrap-mode')
    if twm != null {
        ascii t = asciiLower(twm)
        if t == 'wrap' { s.textWrapMode = WRAP_WRAP }
        else if t == 'nowrap' { s.textWrapMode = WRAP_NOWRAP }
    }
    // word-break and overflow-wrap both say a word may be broken.
    // `word-break: break-word` is the legacy spelling of
    // `overflow-wrap: break-word` and the standard keeps it as that.
    s.wordBreaking = isRoot ? BREAK_NONE : parent.wordBreaking
    ascii owp = styleProp(props, 'overflow-wrap')
    if owp != null {
        ascii t = asciiLower(owp)
        if t == 'normal' { s.wordBreaking = BREAK_NONE }
        else if t == 'break-word' { s.wordBreaking = BREAK_WORD }
        else if t == 'anywhere' { s.wordBreaking = BREAK_ALL }
    }
    ascii wb = styleProp(props, 'word-break')
    if wb != null {
        ascii t = asciiLower(wb)
        if t == 'normal' || t == 'keep-all' { s.wordBreaking = BREAK_NONE }
        else if t == 'break-all' { s.wordBreaking = BREAK_ALL }
        else if t == 'break-word' { s.wordBreaking = BREAK_WORD }
    }
    // line-break (CSS Text 4 §5.2) says how strictly a break may fall
    // around punctuation. `loose`, `normal` and `strict` differ only in
    // the CJK rules they loosen or tighten, and this engine has none of
    // them, so all three leave the line where it was. `anywhere` is the
    // one that says something here: a break may fall between any two
    // characters, which is the permission `break-all` already carries.
    ascii lbk = styleProp(props, 'line-break')
    if lbk != null {
        ascii t = asciiLower(asciiTrim(lbk))
        if t == 'anywhere' { s.wordBreaking = BREAK_ALL }
    }
    // hyphens. `manual` -- the initial value -- honours a soft hyphen
    // as a break opportunity; `none` suppresses it. `auto` needs a
    // dictionary per language and behaves as `manual`, which css-2026.md
    // records.
    s.hyphensNone = isRoot ? false : parent.hyphensNone
    ascii hy = styleProp(props, 'hyphens')
    if hy != null {
        ascii t = asciiLower(asciiTrim(hy))
        if t == 'none' { s.hyphensNone = true }
        else if t == 'manual' || t == 'auto' { s.hyphensNone = false }
    }
    s.hyphenChar = isRoot ? '' : parent.hyphenChar
    ascii hc = styleProp(props, 'hyphenate-character')
    if hc != null {
        ascii hct = asciiTrim(hc)
        if asciiLower(hct) == 'auto' { s.hyphenChar = '' }
        else if hct.length >= 2 {
            int q = hct.charCodeAt(0)
            if (q == CH_QUOTE || q == CH_APOS) && hct.charCodeAt(hct.length - 1) == q {
                s.hyphenChar = hct.slice(1, hct.length - 1).toText()
            }
        }
    }
    // tab-size: a number of spaces, or a length saying the advance
    // outright. Both inherit; the initial value is eight spaces.
    s.tabSize = isRoot ? 8 : parent.tabSize
    s.tabSizePx = isRoot || parent.tabSizePx < 0 ? -1 : zoomInherit(parent.tabSizePx, parent)
    ascii ts = styleProp(props, 'tab-size')
    if ts != null {
        arr[ascii] tst = cssTokens(ts)
        if tst.length > 0 {
            // parseLength cannot tell a bare number from a px length --
            // both compute to LEN_PX -- and here the two mean different
            // things, so the unit is read directly.
            ascii tt = asciiLower(asciiTrim(tst[0]))
            parseNumberAt(tt, 0)
            if numOk {
                if tt.slice(numEnd, tt.length) == '' {
                    s.tabSize = maxInt(roundPx(numValue), 0)
                    s.tabSizePx = -1
                } else {
                    Len l = parseLength(tt, s.fontSize)
                    if l.kind == LEN_PX { s.tabSizePx = maxInt(roundPx(l.v), 0) }
                }
            }
        }
    }
    // list-style-image inherits with the rest of the list properties.
    s.listImageUrl = isRoot ? '' : parent.listImageUrl
    ascii lsi = styleProp(props, 'list-style-image')
    if lsi != null {
        ascii t = asciiLower(asciiTrim(lsi))
        if t == 'none' { s.listImageUrl = '' }
        else {
            text u = imageUrlValue(lsi)
            if u != '' { s.listImageUrl = u  anyBackgroundUrl = true }
        }
    }
    // CSS Content 3 §2.1: `content` on an ordinary element replaces its
    // contents. `content` does not inherit, so this starts empty and is
    // filled only by a declaration on this element, and only a `url()`
    // fills it -- `content: "a string"` on an element renders the
    // element's own text in Chromium 141, and `none` and `normal` are
    // both "no replacement". The lookup is one map read per DISTINCT
    // style rather than per element (24 of them on the benchmark page),
    // which is why it needs no flag of its own.
    s.contentUrl = ''
    ascii ecu = styleProp(props, 'content')
    if ecu != null {
        text cu = imageUrlValue(ecu)
        if cu != '' { s.contentUrl = cu  anyContentUrl = true }
    }
    s.listStyle = isRoot ? LIST_DISC : parent.listStyle
    // list-style-type inherits, and so does the name it was given:
    // an <li> takes its marker from the <ol> around it.
    s.listStyleName = isRoot ? '' : parent.listStyleName
    ascii ls = styleProp(props, 'list-style-type')
    if ls != null {
        ascii t = asciiLower(ls)
        if t == 'none' { s.listStyle = LIST_NONE }
        else if t == 'disc' { s.listStyle = LIST_DISC }
        else if t == 'circle' { s.listStyle = LIST_CIRCLE }
        else if t == 'square' { s.listStyle = LIST_SQUARE }
        else if t == 'decimal' || t == 'decimal-leading-zero' { s.listStyle = LIST_DECIMAL }
        else if t == 'lower-alpha' || t == 'lower-latin' { s.listStyle = LIST_LOWER_ALPHA }
        else if t == 'upper-alpha' || t == 'upper-latin' { s.listStyle = LIST_UPPER_ALPHA }
        else if t == 'lower-roman' { s.listStyle = LIST_LOWER_ROMAN }
        else if t == 'upper-roman' { s.listStyle = LIST_UPPER_ROMAN }
        else {
            // Any other name is a counter style -- one the page defined
            // with `@counter-style`, or one of the predefined ones the
            // keywords above do not cover. The marker comes from the
            // counter-style engine rather than from a constant.
            s.listStyle = LIST_DECIMAL
        }
        // The name is kept whatever it was, because a keyword like
        // `decimal-leading-zero` is a counter style too and its marker
        // is not the plain number the constant would give.
        if t != 'none' && t != 'disc' && t != 'circle' && t != 'square' {
            s.listStyleName = t.toText()
        } else {
            s.listStyleName = ''
        }
    }
    s.hidden = isRoot ? false : parent.hidden
    ascii vis = styleProp(props, 'visibility')
    if vis != null {
        ascii t = asciiLower(vis)
        if t == 'hidden' || t == 'collapse' { s.hidden = true }
        else if t == 'visible' { s.hidden = false }
    }
    s.letterSpacing = isRoot ? 0 : zoomInherit(parent.letterSpacing, parent)
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
    // `inline` is both the fallback when nothing declares `display` and
    // the property's initial value, so `initial` and `unset` land on it
    // by taking the same path a missing declaration takes. `inherit` is
    // the one that needs the parent, because `display` does not inherit
    // on its own.
    int dfltDisplay = DISPLAY_INLINE
    ascii displayDecl = styleProp(props, 'display')
    s.display = cssWideKeyword(displayDecl) == CSSWIDE_INHERIT
        ? (isRoot ? dfltDisplay : parent.display)
        : parseDisplay(displayDecl, dfltDisplay)
    s.background = colorProp(props, 'background-color', s.color, COLOR_TRANSPARENT)
    // A background image paints over the background colour. Only
    // gradients are supported; `url()` needs a fetch the cascade cannot
    // do, and is left for Backgrounds and Borders 3 (todo.md).
    s.counterReset = ''
    s.counterIncrement = ''
    s.counterSet = ''
    if anyCounters {
        ascii cr = styleProp(props, 'counter-reset')
        ascii ci = styleProp(props, 'counter-increment')
        ascii cst = styleProp(props, 'counter-set')
        if cr != null { s.counterReset = cr.toText() }
        if ci != null { s.counterIncrement = ci.toText() }
        if cst != null { s.counterSet = cst.toText() }
    }
    // background-image and the longhands beside it are comma-separated
    // lists, one value per layer (§3.10). The first layer goes in the
    // fields it has always been in -- so a page with one background or
    // none pays nothing -- and the rest go in `bgExtra`, which is the
    // shared empty list until a page declares a second.
    s.backgroundImage = noGradient()
    s.backgroundUrl = ''
    s.backgroundFadeUrl = ''
    s.backgroundFade = -1.0
    s.bgExtra = bgNoLayers
    ascii bgimg = styleProp(props, 'background-image')
    int layerCount = 1
    if bgimg != null {
        arr[ascii] imgParts = splitTopLevelCommas(bgimg)
        layerCount = maxInt(imgParts.length, 1)
        ascii first = layerCount > 1 ? dup(asciiTrim(imgParts[0])) : bgimg
        s.backgroundImage = parseGradient(first, s.color, s.fontSize)
        if !s.backgroundImage.present {
            s.backgroundUrl = imageUrlValue(first)
            if s.backgroundUrl == '' && parseCrossFade(first) {
                s.backgroundUrl = crossFadeA
                s.backgroundFadeUrl = crossFadeB
                s.backgroundFade = crossFadeAmount
            }
            if s.backgroundUrl != '' { anyBackgroundUrl = true }
        }
        if layerCount > 1 {
            arr[BgLayer] extra = []
            for int i = 1, i < layerCount, i++ {
                BgLayer l
                ascii one = dup(asciiTrim(imgParts[i]))
                l.image = parseGradient(one, s.color, s.fontSize)
                l.url = ''
                l.fadeUrl = ''
                l.fade = -1.0
                if !l.image.present {
                    l.url = imageUrlValue(one)
                    if l.url == '' && parseCrossFade(one) {
                        l.url = crossFadeA
                        l.fadeUrl = crossFadeB
                        l.fade = crossFadeAmount
                    }
                    if l.url != '' { anyBackgroundUrl = true }
                }
                bgLayerProps(l, props, i, s.fontSize)
                extra.push(l)
            }
            s.bgExtra = extra
        }
    }
    // border-image. The source goes through the same gathering as a
    // background url, so anyBackgroundUrl covers it too.
    s.borderImageUrl = ''
    ascii bimg = styleProp(props, 'border-image-source')
    if bimg != null {
        s.borderImageUrl = imageUrlValue(bimg)
        if s.borderImageUrl != '' { anyBackgroundUrl = true }
    }
    // The slices are four fractions of the source. A bare number is a
    // count of source pixels and a percentage is of the source's size,
    // so both keep their kind and the painter resolves them against the
    // image it has.
    ascii bslice = styleProp(props, 'border-image-slice')
    if bslice != null {
        arr[ascii] st = cssTokens(bslice)
        arr[Len] sides = []
        for int i = 0, i < st.length, i++ {
            if asciiLower(st[i]) == 'fill' { s.borderImageFill = true  continue }
            Len l = parseLength(st[i], s.fontSize)
            if l.kind == LEN_PX || l.kind == LEN_PERCENT { sides.push(l) }
        }
        if sides.length > 0 {
            s.borderImageSliceTop = sides[0]
            s.borderImageSliceRight = sides.length > 1 ? sides[1] : sides[0]
            s.borderImageSliceBottom = sides.length > 2 ? sides[2] : sides[0]
            s.borderImageSliceLeft = sides.length > 3 ? sides[3]
                : (sides.length > 1 ? sides[1] : sides[0])
        }
    }
    s.borderImageWidthTop = -1
    s.borderImageWidthRight = -1
    s.borderImageWidthBottom = -1
    s.borderImageWidthLeft = -1
    ascii bwid = styleProp(props, 'border-image-width')
    if bwid != null {
        arr[ascii] wt = cssTokens(bwid)
        arr[int] sides = []
        for int i = 0, i < wt.length, i++ {
            if asciiLower(wt[i]) == 'auto' { sides.push(-1)  continue }
            Len l = parseLength(wt[i], s.fontSize)
            if l.kind == LEN_PX { sides.push(maxInt(roundPx(l.v), 0)) }
        }
        if sides.length > 0 {
            s.borderImageWidthTop = sides[0]
            s.borderImageWidthRight = sides.length > 1 ? sides[1] : sides[0]
            s.borderImageWidthBottom = sides.length > 2 ? sides[2] : sides[0]
            s.borderImageWidthLeft = sides.length > 3 ? sides[3]
                : (sides.length > 1 ? sides[1] : sides[0])
        }
    }
    s.borderImageOutset = 0
    ascii bout = styleProp(props, 'border-image-outset')
    if bout != null {
        arr[ascii] ot = cssTokens(bout)
        if ot.length > 0 {
            Len l = parseLength(ot[0], s.fontSize)
            if l.kind == LEN_PX { s.borderImageOutset = maxInt(roundPx(l.v), 0) }
        }
    }
    // Two keywords, the first for the top and bottom edges and the
    // second for the left and right; one keyword says both.
    s.borderImageRepeat = BORDERIMG_STRETCH
    s.borderImageRepeatY = BORDERIMG_STRETCH
    ascii brep = styleProp(props, 'border-image-repeat')
    if brep != null {
        arr[ascii] rt = cssTokens(brep)
        if rt.length > 0 {
            s.borderImageRepeat = borderImageRepeatKeyword(asciiLower(rt[0]))
            s.borderImageRepeatY = rt.length > 1
                ? borderImageRepeatKeyword(asciiLower(rt[1])) : s.borderImageRepeat
        }
    }
    // background-attachment: fixed paints the background against the
    // viewport rather than the document, so it does not scroll.
    // Every one of these is the first layer's slice of a comma-separated
    // list, read by the same functions the other layers use.
    ascii bga = layerValue(styleProp(props, 'background-attachment'), 0)
    if bga != null {
        s.backgroundFixed = asciiLower(asciiTrim(bga)) == 'fixed'
    }
    parseBgRepeat(layerValue(styleProp(props, 'background-repeat'), 0))
    s.backgroundRepeatX = bgRepeatXOut
    s.backgroundRepeatY = bgRepeatYOut
    // Only the longhands are read: `background-position` was expanded
    // into them where it was applied, so the later of a shorthand and a
    // longhand wins whichever way round they are written.
    s.backgroundPosX = lenPercent(0.0)
    s.backgroundPosY = lenPercent(0.0)
    ascii bgposX = layerValue(styleProp(props, 'background-position-x'), 0)
    if bgposX != null {
        s.backgroundPosX = parsePositionAxis(asciiLower(asciiTrim(bgposX)), true, s.fontSize)
    }
    ascii bgposY = layerValue(styleProp(props, 'background-position-y'), 0)
    if bgposY != null {
        s.backgroundPosY = parsePositionAxis(asciiLower(asciiTrim(bgposY)), false, s.fontSize)
    }
    // box-shadow (Backgrounds and Borders 3 §6): a comma-separated list,
    // each `<offset-x> <offset-y> <blur>? <spread>? <colour>? inset?` in
    // any order. A style that does not mention it leaves the list empty,
    // which is the zero value.
    ascii shadowDecl = styleProp(props, 'box-shadow')
    if shadowDecl != null {
        ascii shadowLow = asciiLower(asciiTrim(shadowDecl))
        if shadowLow != 'none' && shadowLow != '' {
            arr[Shadow] list = []
            arr[ascii] pieces = splitTopLevelCommas(shadowDecl)
            for int i = 0, i < pieces.length, i++ {
                Shadow sh = parseShadow(pieces[i], s.color, s.fontSize)
                if sh != null { list.push(sh) }
            }
            if list.length > 0 { s.shadows = list }
        }
    }
    // background-clip and background-origin (Backgrounds and Borders 3
    // §3.7, §3.8). Both initial values are the zero value of their
    // field, so a style that names neither writes nothing here.
    ascii bgclip = layerValue(styleProp(props, 'background-clip'), 0)
    if bgclip != null { s.backgroundClip = parseBgClip(bgclip) }
    ascii bgorigin = layerValue(styleProp(props, 'background-origin'), 0)
    if bgorigin != null {
        s.backgroundOrigin = parseBgOrigin(bgorigin)
    }
    // background-size (Backgrounds and Borders 3 §3.9). `auto` is the
    // initial value on both axes and is the zero value of these fields,
    // so a style that does not mention it writes nothing here.
    ascii bgsize = layerValue(styleProp(props, 'background-size'), 0)
    if bgsize != null {
        parseBgSize(bgsize, s.fontSize)
        s.backgroundSizeKind = bgSizeKindOut
        s.backgroundSizeW = bgSizeWOut
        s.backgroundSizeH = bgSizeHOut
    }
    // object-fit and object-position (CSS Images 3 §5.5, §5.6). The
    // initial position is `50% 50%`, unlike background-position's
    // `0% 0%`, so the centre is written in rather than left at the
    // zero value.
    s.objectPosX = lenPercent(50.0)
    s.objectPosY = lenPercent(50.0)
    ascii objfit = styleProp(props, 'object-fit')
    if objfit != null {
        // The lowered string is held in a local and its words indexed
        // rather than bound, because a bound slice releases an alias the
        // compiler never retained (FINDINGS.md, "ascii aliases are not
        // retained").
        ascii objfitLow = asciiLower(objfit)
        if objfitLow == 'contain' { s.objectFit = OBJECTFIT_CONTAIN }
        else if objfitLow == 'cover' { s.objectFit = OBJECTFIT_COVER }
        else if objfitLow == 'none' { s.objectFit = OBJECTFIT_NONE }
        else if objfitLow == 'scale-down' { s.objectFit = OBJECTFIT_SCALE_DOWN }
        else { s.objectFit = OBJECTFIT_FILL }
    }
    s.objectViewBox = parseViewBox(styleProp(props, 'object-view-box'), s.fontSize)
    ascii objpos = styleProp(props, 'object-position')
    if objpos != null {
        ascii objposLow = asciiLower(objpos)
        arr[ascii] parts = asciiSplitSpace(objposLow)
        if parts.length >= 2 {
            s.objectPosX = parsePositionAxis(parts[0], true, s.fontSize)
            s.objectPosY = parsePositionAxis(parts[1], false, s.fontSize)
        } else if parts.length == 1 {
            // one value positions the horizontal axis and centres the
            // other, unless it is a vertical keyword
            if parts[0] == 'top' { s.objectPosY = lenPercent(0.0) }
            else if parts[0] == 'bottom' { s.objectPosY = lenPercent(100.0) }
            else { s.objectPosX = parsePositionAxis(parts[0], true, s.fontSize) }
        }
    }
    s.width = lenProp(props, 'width', s.fontSize, lenAuto())
    s.height = lenProp(props, 'height', s.fontSize, lenAuto())
    s.minWidth = lenProp(props, 'min-width', s.fontSize, lenAuto())
    s.maxWidth = lenProp(props, 'max-width', s.fontSize, lenAuto())
    s.minHeight = lenProp(props, 'min-height', s.fontSize, lenAuto())
    s.maxHeight = lenProp(props, 'max-height', s.fontSize, lenAuto())
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
    // The declared keyword per side. `borderWidthProp` has already
    // turned `none` and `hidden` into a zero width, so a side with no
    // width paints nothing whatever this says.
    s.borderTopStyle = borderStyleProp(props, 'top')
    s.borderRightStyle = borderStyleProp(props, 'right')
    s.borderBottomStyle = borderStyleProp(props, 'bottom')
    s.borderLeftStyle = borderStyleProp(props, 'left')
    // border-radius: the shorthand's one-to-four values run top-left,
    // top-right, bottom-right, bottom-left, each missing one taking the
    // value of the corner opposite it. A `/` splits the horizontal radii
    // from the vertical ones, each side read the same way; with no slash
    // the vertical radii are the horizontal ones and every corner is a
    // quarter circle.
    Len zeroRadius = lenPx(0.0)
    s.radiusTopLeftX = zeroRadius
    s.radiusTopLeftY = zeroRadius
    s.radiusTopRightX = zeroRadius
    s.radiusTopRightY = zeroRadius
    s.radiusBottomRightX = zeroRadius
    s.radiusBottomRightY = zeroRadius
    s.radiusBottomLeftX = zeroRadius
    s.radiusBottomLeftY = zeroRadius
    // `border-radius` reaches here as its four corner longhands,
    // which applyDecl expanded it into.
    if cornerRadiusProp(props, 'border-top-left-radius', s.fontSize) {
        s.radiusTopLeftX = cornerRadiusX
        s.radiusTopLeftY = cornerRadiusY
    }
    if cornerRadiusProp(props, 'border-top-right-radius', s.fontSize) {
        s.radiusTopRightX = cornerRadiusX
        s.radiusTopRightY = cornerRadiusY
    }
    if cornerRadiusProp(props, 'border-bottom-right-radius', s.fontSize) {
        s.radiusBottomRightX = cornerRadiusX
        s.radiusBottomRightY = cornerRadiusY
    }
    if cornerRadiusProp(props, 'border-bottom-left-radius', s.fontSize) {
        s.radiusBottomLeftX = cornerRadiusX
        s.radiusBottomLeftY = cornerRadiusY
    }
    s.borderRadius = radiusAny(s) ? 1 : 0
    // `corner-shape` (CSS Borders 4 §5): the shorthand in the same
    // one-to-four form as `border-radius`, then the four physical
    // longhands, then the four logical ones -- which in the
    // left-to-right horizontal mode this engine lays out in name the
    // same four corners.
    float cshTL = CORNER_K_ROUND
    float cshTR = CORNER_K_ROUND
    float cshBR = CORNER_K_ROUND
    float cshBL = CORNER_K_ROUND
    ascii csh = styleProp(props, 'corner-shape')
    if csh != null {
        arr[ascii] ct = cssTokens(csh)
        arr[float] ks = []
        for int i = 0, i < ct.length, i++ {
            float k = cornerShapeKeyword(ct[i])
            if k != 0.0 { ks.push(k) }
        }
        if ks.length > 0 {
            cshTL = ks[0]
            cshTR = ks.length > 1 ? ks[1] : ks[0]
            cshBR = ks.length > 2 ? ks[2] : ks[0]
            cshBL = ks.length > 3 ? ks[3] : (ks.length > 1 ? ks[1] : ks[0])
        }
    }
    cshTL = cornerShapeProp(props, 'corner-top-left-shape', cshTL)
    cshTR = cornerShapeProp(props, 'corner-top-right-shape', cshTR)
    cshBR = cornerShapeProp(props, 'corner-bottom-right-shape', cshBR)
    cshBL = cornerShapeProp(props, 'corner-bottom-left-shape', cshBL)
    cshTL = cornerShapeProp(props, 'corner-start-start-shape', cshTL)
    cshTR = cornerShapeProp(props, 'corner-start-end-shape', cshTR)
    cshBL = cornerShapeProp(props, 'corner-end-start-shape', cshBL)
    cshBR = cornerShapeProp(props, 'corner-end-end-shape', cshBR)
    // CSS Anchor Positioning 1: the three properties that place a box,
              // behind one index. The entry
    // is only made when the element said something, so a page with no
    // anchors carries no side table and every `Style` holds a zero.
    s.anchorInfo = 0
    text aName = anchorIdent(props, 'anchor-name')
    text aAnchor = anchorIdent(props, 'position-anchor')
    int aArea = positionAreaValue(styleProp(props, 'position-area'))
    text aFall = anchorIdent(props, 'position-try-fallbacks')
    if aFall == 'none' { aFall = '' }
    int aOrder = TRYORDER_NORMAL
    ascii ordv = styleProp(props, 'position-try-order')
    if ordv != null {
        ascii ot = asciiLower(asciiTrim(ordv))
        if ot == 'most-height' || ot == 'most-block-size' { aOrder = TRYORDER_MOST_BLOCK }
        else if ot == 'most-width' || ot == 'most-inline-size' { aOrder = TRYORDER_MOST_INLINE }
    }
    int aVis = POSVIS_ALWAYS
    ascii visv = styleProp(props, 'position-visibility')
    if visv != null && asciiLower(asciiTrim(visv)) == 'no-overflow' {
        aVis = POSVIS_NO_OVERFLOW
    }
    text aScope = ''
    ascii scopev = styleProp(props, 'anchor-scope')
    if scopev != null {
        ascii st = asciiLower(asciiTrim(scopev))
        if st != 'none' && st != '' { aScope = st.toText() }
    }
    // `anchor()` in the four insets, read into one position along the
    // anchor's box per side.
    arr[text] inNames = ['', '', '', '']
    arr[int] inPcts = [-1, -1, -1, -1]
    arr[text] inExprs = ['', '', '', '']
    arr[int] inFalls = [ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                        ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK]
    bool anySaidInset = false
    arr[text] insetProps = ['left', 'right', 'top', 'bottom']
    for int i = 0, i < 4, i++ {
        ascii raw = styleProp(props, insetProps[i])
        if raw == null { continue }
        ascii low = asciiLower(asciiTrim(raw))
        // The bare form -- the function and nothing else -- keeps its
        // own path: it needs no arithmetic and no second parse.
        if asciiStartsWith(low, 'anchor(', 0) {
            int close = asciiMatchingParen(low, 6)
            if close == low.length - 1 {
                if !parseAnchorInset(low.slice(7, close), i) { continue }
                inNames[i] = anchorInsetName
                inPcts[i] = anchorInsetPct
                inFalls[i] = anchorInsetFallback
                anySaidInset = true
                anyAnchorInset = true
                continue
            }
        }
        // Anything else holding the function is an expression, kept
        // whole so each occurrence's length can be substituted into it
        // once the anchors and the containing block are both known.
        if !cascadeSawAnchorInset { continue }
        if asciiIndexOf(low, 'anchor(', 0) < 0 { continue }
        inExprs[i] = low.toText()
        anySaidInset = true
        anyAnchorInset = true
    }
    // `anchor-size()` in the six sizing properties.
    // Asked once per document rather than fourteen times per element,
    // and the slots are the shared do-nothing ones until a page has
    // actually written the function: no page that never says
    // `anchor-size(` allocates or looks anything up for it.
    arr[text] szNames = anchorSizeNoNames
    arr[int] szDims = anchorSizeNoDims
    arr[int] szFalls = anchorSizeNoFalls
    arr[text] szExprs = anchorSizeNoExprs
    bool anySaidSize = false
    if cascadeSawAnchorSize {
        arr[text] mySzNames = ['', '', '', '', '', '', '', '', '', '', '', '', '', '']
        arr[int] mySzDims = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]
        arr[int] mySzFalls = [ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                              ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                              ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                              ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                              ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK]
        arr[text] mySzExprs = ['', '', '', '', '', '', '', '', '', '', '', '', '', '']
        arr[text] sizeProps = ['width', 'height', 'min-width', 'max-width',
                               'min-height', 'max-height',
                               'margin-left', 'margin-right', 'margin-top', 'margin-bottom',
                               'left', 'right', 'top', 'bottom']
        for int i = 0, i < ANCHOR_SIZE_SLOTS, i++ {
            ascii rawsz = styleProp(props, sizeProps[i])
            if rawsz == null { continue }
            ascii lowsz = asciiLower(asciiTrim(rawsz))
            // The bare form -- the function and nothing else -- keeps
            // its own path: it needs no arithmetic and no second parse.
            if asciiStartsWith(lowsz, 'anchor-size(', 0) {
                int closesz = asciiMatchingParen(lowsz, 11)
                if closesz == lowsz.length - 1 {
                    if !parseAnchorSize(lowsz.slice(12, closesz)) { continue }
                    mySzNames[i] = anchorSizeName
                    mySzDims[i] = anchorSizeDim
                    mySzFalls[i] = anchorSizeFallback
                    anySaidSize = true
                    anyAnchorSize = true
                    continue
                }
            }
            // Anything else holding the function is an expression, kept
            // whole so the length can be substituted into it once the
            // anchor is known.
            if asciiIndexOf(lowsz, 'anchor-size(', 0) < 0 { continue }
            mySzExprs[i] = lowsz.toText()
            anySaidSize = true
            anyAnchorSize = true
        }
        if anySaidSize {
            szNames = mySzNames
            szDims = mySzDims
            szFalls = mySzFalls
            szExprs = mySzExprs
        }
    }
    if aName != '' || aAnchor != '' || aArea != PAREA_NONE || aFall != ''
        || aOrder != TRYORDER_NORMAL || aVis != POSVIS_ALWAYS || aScope != ''
        || anySaidInset || anySaidSize {
        AnchorInfo ai
        ai.name = aName
        ai.anchor = aAnchor
        ai.area = aArea
        ai.fallbacks = aFall
        ai.tryOrder = aOrder
        ai.visibility = aVis
        ai.scope = aScope
        ai.insetNames = inNames
        ai.insetPcts = inPcts
        ai.insetExprs = inExprs
        ai.insetFallbacks = inFalls
        ai.sizeNames = szNames
        ai.sizeDims = szDims
        ai.sizeFallbacks = szFalls
        ai.sizeExprs = szExprs
        anchorInfos.push(ai)
        s.anchorInfo = anchorInfos.length
        if aName != '' { anyAnchorName = true }
        if aScope != '' { anyAnchorScope = true }
    }
    ascii isoProp = styleProp(props, 'isolation')
    if isoProp != null { s.isolate = asciiLower(asciiTrim(isoProp)) == 'isolate' }
    // CSS Masking 1's mask, held the same way as the filter below it.
    // Any of the seven longhands brings the layer into being, because
    // `mask-clip` has a computed value whether or not an image is
    // beside it -- and the painter reads it as soon as one is.
    if styleProp(props, 'mask-image') != null || anyMaskGeometry(props) {
        s.maskIdx = parseMaskLayer(props, s.color, s.fontSize)
        if s.maskIdx > 0 { anyMask = true }
    }
    // CSS Filter Effects 1. One index on the Style and a flag for the
    // page, so a document with no `filter` reaches none of the painter's
    // filtering at all.
    ascii filterProp = styleProp(props, 'filter')
    if filterProp != null {
        s.filterIdx = parseFilterList(filterProp)
        if s.filterIdx > 0 { anyFilter = true }
    }
    // CSS Motion Path 1, held the same way: five properties behind one
    // index, and no side table at all on a page that says none of them.
    ascii mPath = styleProp(props, 'offset-path')
    ascii mDist = styleProp(props, 'offset-distance')
    ascii mRot = styleProp(props, 'offset-rotate')
    ascii mAnch = styleProp(props, 'offset-anchor')
    ascii mPos = styleProp(props, 'offset-position')
    if mPath != null || mDist != null || mRot != null || mAnch != null || mPos != null {
        MotionInfo mi
        mi.pathKind = MPATH_NONE
        mi.rotateMode = MROT_AUTO
        mi.anchorAuto = true
        mi.posNormal = true
        motionReadPath(mi, mPath, s.fontSize, n.id)
        motionReadRotate(mi, mRot)
        if mDist != null { mi.distance = parseLength(asciiTrim(mDist), s.fontSize) }
        if mAnch != null {
            // Held in a local and indexed, as every split here is
            // (FINDINGS.md, "ascii aliases are not retained").
            ascii anchLow = asciiLower(asciiTrim(mAnch))
            arr[ascii] a = asciiSplitSpace(anchLow)
            if a.length == 1 && a[0] == 'auto' {
            } else if a.length >= 1 {
                mi.anchorAuto = false
                mi.anchorX = parsePositionAxis(a[0], true, s.fontSize)
                mi.anchorY = a.length > 1 ? parsePositionAxis(a[1], false, s.fontSize)
                    : lenPercent(50.0)
            }
        }
        if mPos != null {
            ascii posLow = asciiLower(asciiTrim(mPos))
            arr[ascii] a = asciiSplitSpace(posLow)
            if a.length == 1 && (a[0] == 'normal' || a[0] == 'auto') {
            } else if a.length >= 1 {
                mi.posNormal = false
                mi.posX = parsePositionAxis(a[0], true, s.fontSize)
                mi.posY = a.length > 1 ? parsePositionAxis(a[1], false, s.fontSize)
                    : lenPercent(50.0)
            }
        }
        motionInfos.push(mi)
        motionOfSerial[`${s.serial}`] = motionInfos.length
        if mi.pathKind != MPATH_NONE { anyOffsetPath = true }
    }
    s.cornerShapes = 0
    if cshTL != CORNER_K_ROUND || cshTR != CORNER_K_ROUND
        || cshBR != CORNER_K_ROUND || cshBL != CORNER_K_ROUND {
        s.cornerShapes = cornerShapesPacked(cshTL, cshTR, cshBR, cshBL)
        anyCornerShape = true
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
    s.textIndent = pxProp(props, 'text-indent', s.fontSize,
                          isRoot ? 0 : zoomInherit(parent.textIndent, parent))
    s.verticalAlign = VALIGN_BASELINE
    ascii va = styleProp(props, 'vertical-align')
    if va != null {
        ascii t = asciiLower(va)
        if t == 'middle' { s.verticalAlign = VALIGN_MIDDLE }
        else if t == 'top' || t == 'text-top' || t == 'super' { s.verticalAlign = VALIGN_TOP }
        else if t == 'bottom' || t == 'text-bottom' || t == 'sub' { s.verticalAlign = VALIGN_BOTTOM }
        else if t == 'inherit' && !isRoot { s.verticalAlign = parent.verticalAlign }
    }
    // ---- flexbox ------------------------------------------------------
    s.flexDirection = FLEX_ROW
    s.flexWrap = FLEXWRAP_NOWRAP
    ascii fd = styleProp(props, 'flex-direction')
    if fd != null {
        ascii t = asciiLower(fd)
        if t == 'row-reverse' { s.flexDirection = FLEX_ROW_REVERSE }
        else if t == 'column' { s.flexDirection = FLEX_COLUMN }
        else if t == 'column-reverse' { s.flexDirection = FLEX_COLUMN_REVERSE }
    }
    // `flex-flow` reaches here as `flex-direction` and `flex-wrap`.
    ascii fwrap = styleProp(props, 'flex-wrap')
    if fwrap != null {
        ascii t = asciiLower(asciiTrim(fwrap))
        if t == 'wrap' { s.flexWrap = FLEXWRAP_WRAP }
        else if t == 'wrap-reverse' { s.flexWrap = FLEXWRAP_WRAP_REVERSE }
        else if t == 'nowrap' { s.flexWrap = FLEXWRAP_NOWRAP }
    }
    // `normal` behaves as `stretch` on a grid container and as
    // `flex-start` on a flex one; BOXALIGN_STRETCH is the initial value
    // because only the grid can tell the two apart -- flexOffsetFor
    // gives it and BOXALIGN_START the same offset.
    s.justifyContent = parseAlignValue(styleProp(props, 'justify-content'), BOXALIGN_STRETCH)
    // justify-items is inherited in effect rather than by the cascade:
    // it is read off the parent box at layout time, so it is stored as
    // the element's own value and the child asks for it there.
    // CSS Multi-column. `column-rule` is width, style and colour in any
    // order, like `border` and `outline`; the rule takes no space, so
    // its width never reaches the box model.
    s.columnCount = 0
    ascii ccnt = styleProp(props, 'column-count')
    if ccnt != null {
        ascii t = asciiLower(asciiTrim(ccnt))
        if t != 'auto' {
            parseNumberAt(t, 0)
            if numOk { s.columnCount = maxInt(roundPx(numValue), 0) }
        }
    }
    ascii cwid = styleProp(props, 'column-width')
    if cwid != null {
        ascii t = asciiLower(asciiTrim(cwid))
        if t != 'auto' {
            Len l = parseLength(t, s.fontSize)
            if l.kind == LEN_PX { s.columnWidth = l }
        }
    }
    s.columnRuleStyle = BORDER_NONE
    s.columnRuleColor = s.color
    int ruleDeclaredWidth = -1
    // `column-rule` reaches here as its three longhands.
    // CSS Shapes 1. The same basic shapes, resolved against the float's
    // margin box unless the declaration names another, and grown by
    // `shape-margin`. It does nothing on a box that does not float,
    // which is where the float code asks rather than here.
    ascii shapeProp = styleProp(props, 'shape-outside')
    if shapeProp != null {
        ClipShape outside = parseClipPath(shapeProp, s.fontSize)
        if outside.kind != CLIPSHAPE_NONE {
            if !outside.geoBoxExplicit { outside.geoBox = GEOBOX_MARGIN }
            s.shapeOutside = outside
            cascadeSawShape = true
        }
    }
    s.shapeMargin = 0
    ascii shapeMarginProp = styleProp(props, 'shape-margin')
    if shapeMarginProp != null {
        Len l = parseLength(shapeMarginProp, s.fontSize)
        if l.kind == LEN_PX { s.shapeMargin = maxInt(roundPx(l.v), 0) }
    }
    // CSS Fragmentation 3: where a column break may or must happen.
    // `orphans` and `widows` are inherited, since they describe a
    // paragraph's lines and the declaration is usually on an ancestor.
    s.breakBefore = breakKeyword(styleProp(props, 'break-before'))
    s.breakAfter = breakKeyword(styleProp(props, 'break-after'))
    s.breakInsideAvoid = breakKeyword(styleProp(props, 'break-inside')) == BRK_AVOID
    s.pageName = pageNameProp(styleProp(props, 'page'))
    snapTypeProp(styleProp(props, 'scroll-snap-type'))
    s.snapX = snapAxisXOut
    s.snapY = snapAxisYOut
    s.snapStrict = snapStrictOut
    ascii snapStopV = styleProp(props, 'scroll-snap-stop')
    s.snapStopAlways = snapStopV != null && asciiLower(asciiTrim(snapStopV)) == 'always'
    snapAlignProp(styleProp(props, 'scroll-snap-align'))
    s.snapAlignBlock = snapAlignBlockOut
    s.snapAlignInline = snapAlignInlineOut
    s.scrollPaddingTop = parseLength(styleProp(props, 'scroll-padding-top'), s.fontSize)
    s.scrollPaddingRight = parseLength(styleProp(props, 'scroll-padding-right'), s.fontSize)
    s.scrollPaddingBottom = parseLength(styleProp(props, 'scroll-padding-bottom'), s.fontSize)
    s.scrollPaddingLeft = parseLength(styleProp(props, 'scroll-padding-left'), s.fontSize)
    s.scrollMarginTop = parseLength(styleProp(props, 'scroll-margin-top'), s.fontSize)
    s.scrollMarginRight = parseLength(styleProp(props, 'scroll-margin-right'), s.fontSize)
    s.scrollMarginBottom = parseLength(styleProp(props, 'scroll-margin-bottom'), s.fontSize)
    s.scrollMarginLeft = parseLength(styleProp(props, 'scroll-margin-left'), s.fontSize)
    s.scrollbarWidth = scrollbarWidthKeyword(styleProp(props, 'scrollbar-width'))
    s.scrollbarGutter = scrollbarGutterKeyword(styleProp(props, 'scrollbar-gutter'))
    scrollbarColorProp(props, isRoot ? 0 : parent.scrollbarThumb,
                       isRoot ? 0 : parent.scrollbarTrack)
    s.scrollbarThumb = scrollbarThumbOut
    s.scrollbarTrack = scrollbarTrackOut
    s.orphans = countProp(props, 'orphans', isRoot ? 2 : parent.orphans)
    s.widows = countProp(props, 'widows', isRoot ? 2 : parent.widows)
    ascii cspan = styleProp(props, 'column-span')
    if cspan != null { s.columnSpanAll = asciiLower(asciiTrim(cspan)) == 'all' }
    ascii cfill = styleProp(props, 'column-fill')
    if cfill != null { s.columnFillAuto = asciiLower(asciiTrim(cfill)) == 'auto' }
    ascii crs = styleProp(props, 'column-rule-style')
    if crs != null { s.columnRuleStyle = lineStyleKeyword(asciiLower(asciiTrim(crs))) }
    ascii crw = styleProp(props, 'column-rule-width')
    if crw != null {
        ascii t = asciiLower(asciiTrim(crw))
        if t == 'thin' { ruleDeclaredWidth = 1 }
        else if t == 'medium' { ruleDeclaredWidth = 3 }
        else if t == 'thick' { ruleDeclaredWidth = 5 }
        else {
            Len l = parseLength(t, s.fontSize)
            if l.kind == LEN_PX { ruleDeclaredWidth = maxInt(roundPx(l.v), 0) }
        }
    }
    s.columnRuleWidth = s.columnRuleStyle == BORDER_NONE ? 0
                      : (ruleDeclaredWidth >= 0 ? ruleDeclaredWidth : 3)
    ascii crc = styleProp(props, 'column-rule-color')
    if crc != null {
        int c = parseCssColor(asciiTrim(crc), s.color)
        if c != COLOR_UNSET { s.columnRuleColor = c }
    }
    // CSS Grid. The templates are parsed once per distinct style, like
    // every other property here, so a page with no grid on it allocates
    // nothing: an absent template is an empty list.
    s.gridCols = parseTrackList(styleProp(props, 'grid-template-columns'), s.fontSize)
    s.gridColsSubgrid = trackIsSubgrid
    s.gridColLineNames = trackLineNames
    s.gridColLineAt = trackLineAt
    s.gridColsAutoAt = trackAutoRepeatAt
    s.gridColsAutoLen = trackAutoRepeatLen
    s.gridColsAutoFit = trackAutoRepeatFit
    s.gridRows = parseTrackList(styleProp(props, 'grid-template-rows'), s.fontSize)
    s.gridRowsSubgrid = trackIsSubgrid
    s.gridRowLineNames = trackLineNames
    s.gridRowLineAt = trackLineAt
    s.gridRowsAutoAt = trackAutoRepeatAt
    s.gridRowsAutoLen = trackAutoRepeatLen
    s.gridRowsAutoFit = trackAutoRepeatFit
    parseGridAreas(styleProp(props, 'grid-template-areas'))
    s.gridAreaNames = areaTemplateNames
    s.gridAreaCols = areaTemplateCols
    s.gridAutoCols = parseTrackList(styleProp(props, 'grid-auto-columns'), s.fontSize)
    s.gridAutoRows = parseTrackList(styleProp(props, 'grid-auto-rows'), s.fontSize)
    ascii gaf = styleProp(props, 'grid-auto-flow')
    s.gridAutoFlowColumn = gaf != null && asciiIndexOf(asciiLower(gaf), 'column'.toAscii(), 0) >= 0
    s.gridAutoFlowDense = gaf != null && asciiIndexOf(asciiLower(gaf), 'dense'.toAscii(), 0) >= 0
    s.gridColStart = parseGridLine(styleProp(props, 'grid-column-start'))
    s.gridColEnd = parseGridLine(styleProp(props, 'grid-column-end'))
    s.gridRowStart = parseGridLine(styleProp(props, 'grid-row-start'))
    s.gridRowEnd = parseGridLine(styleProp(props, 'grid-row-end'))
    s.justifyItems = parseAlignValue(styleProp(props, 'justify-items'), BOXALIGN_START)
    s.justifySelf = parseAlignValue(styleProp(props, 'justify-self'), BOXALIGN_AUTO)
    ascii tov = styleProp(props, 'text-overflow')
    s.textOverflowEllipsis = tov != null && asciiLower(asciiTrim(tov)) == 'ellipsis'
    s.pointerEvents = PE_AUTO
    ascii pev = styleProp(props, 'pointer-events')
    if pev != null {
        ascii t = asciiLower(asciiTrim(pev))
        if t == 'none' { s.pointerEvents = PE_NONE }
        else if t == 'visible' { s.pointerEvents = PE_VISIBLE }
        else if t == 'all' { s.pointerEvents = PE_ALL }
    }
    s.alignItems = parseAlignValue(styleProp(props, 'align-items'), BOXALIGN_STRETCH)
    s.alignSelf = parseAlignValue(styleProp(props, 'align-self'), BOXALIGN_AUTO)
    s.alignContent = parseAlignValue(styleProp(props, 'align-content'), BOXALIGN_STRETCH)
    s.flexGrow = 0.0
    s.flexShrink = 1.0
    s.flexBasis = lenAuto()
    // `flex` reaches here as its three longhands.
    ascii fg = styleProp(props, 'flex-grow')
    if fg != null { parseNumberAt(asciiTrim(fg), 0)  if numOk { s.flexGrow = numValue } }
    ascii fs2 = styleProp(props, 'flex-shrink')
    if fs2 != null { parseNumberAt(asciiTrim(fs2), 0)  if numOk { s.flexShrink = numValue } }
    ascii fb = styleProp(props, 'flex-basis')
    if fb != null {
        Len l = parseLength(fb, s.fontSize)
        if l.kind != LEN_INVALID { s.flexBasis = l }
    }
    s.rowGap = 0
    s.columnGap = 0
    // `gap` reaches here as `row-gap` and `column-gap`.
    s.rowGap = pxProp(props, 'row-gap', s.fontSize, s.rowGap)
    s.columnGap = pxProp(props, 'column-gap', s.fontSize, s.columnGap)
    s.order = 0
    ascii od = styleProp(props, 'order')
    if od != null {
        int o = asciiTrim(od).toText().toInt()
        if o != null { s.order = o }
    }
    s.boxSizing = BOX_CONTENT
    ascii bsz = styleProp(props, 'box-sizing')
    if bsz != null && asciiLower(bsz) == 'border-box' { s.boxSizing = BOX_BORDER }
    applyAspectRatio(s, styleProp(props, 'aspect-ratio'))
    s.captionSide = CAPTION_TOP
    ascii cs2 = styleProp(props, 'caption-side')
    if cs2 != null && asciiLower(cs2) == 'bottom' { s.captionSide = CAPTION_BOTTOM }
    s.wordSpacing = isRoot ? 0 : zoomInherit(parent.wordSpacing, parent)
    s.wordSpacing = pxProp(props, 'word-spacing', s.fontSize, s.wordSpacing)
    // An outline has a style of its own, like a border side: the
    // keyword used to decide only whether the outline existed, so every
    // outline painted solid however it was declared -- and `@supports`
    // answered yes for `outline-style`, which is the lie it exists to
    // prevent. The width is kept separate from the style so that the
    // absent width can fall back to `medium` exactly when a style says
    // there is a line to draw.
    s.outlineStyle = BORDER_NONE
    s.outlineColor = s.color
    int declaredWidth = -1
    ascii ow = styleProp(props, 'outline-width')
    ascii ost = styleProp(props, 'outline-style')
    ascii oc = styleProp(props, 'outline-color')
    // `outline` reaches here as its three longhands.
    if ost != null { s.outlineStyle = lineStyleKeyword(asciiLower(asciiTrim(ost))) }
    if ow != null {
        ascii t = asciiLower(asciiTrim(ow))
        if t == 'thin' { declaredWidth = 1 }
        else if t == 'medium' { declaredWidth = 3 }
        else if t == 'thick' { declaredWidth = 5 }
        else {
            Len l = parseLength(t, s.fontSize)
            if l.kind == LEN_PX { declaredWidth = maxInt(roundPx(l.v), 0) }
        }
    }
    // `none` draws nothing however wide it is asked to be, and a style
    // with no width takes `medium`.
    s.outlineWidth = s.outlineStyle == BORDER_NONE ? 0
                   : (declaredWidth >= 0 ? declaredWidth : 3)
    if oc != null {
        int c = parseCssColor(oc, s.color)
        if c != COLOR_UNSET { s.outlineColor = c }
    }
    // transform, and the three individual properties that say the same
    // things separately. The standard applies translate, then rotate,
    // then scale, and then the `transform` list, so they are pushed in
    // that order onto one list the painter walks.
    arr[Transform] txs = []
    ascii trProp = styleProp(props, 'translate')
    if trProp != null {
        arr[ascii] tp = cssTokens(trProp)
        if tp.length > 0 && asciiLower(asciiTrim(tp[0])) != 'none' {
            Transform tr
            tr.kind = TX_TRANSLATE
            tr.sx = 1.0
            tr.sy = 1.0
            Len a = parseLength(tp[0], s.fontSize)
            if a.kind == LEN_PX || a.kind == LEN_PERCENT { tr.x = a }
            if tp.length > 1 {
                Len b = parseLength(tp[1], s.fontSize)
                if b.kind == LEN_PX || b.kind == LEN_PERCENT { tr.y = b }
            }
            txs.push(tr)
        }
    }
    ascii rotProp = styleProp(props, 'rotate')
    if rotProp != null {
        arr[ascii] rp = cssTokens(rotProp)
        if rp.length > 0 && asciiLower(asciiTrim(rp[0])) != 'none' {
            arr[bool] ok = [false]
            // `rotate: x 45deg` names an axis first; only a z rotation
            // is in the plane this paints on, and the angle is the last
            // token either way
            float deg = parseAngleDegrees(rp[rp.length - 1], ok)
            if ok[0] {
                Transform tr
                tr.kind = TX_ROTATE
                tr.angle = deg
                tr.sx = 1.0
                tr.sy = 1.0
                txs.push(tr)
            }
        }
    }
    ascii scProp = styleProp(props, 'scale')
    if scProp != null {
        arr[ascii] sp = cssTokens(scProp)
        if sp.length > 0 && asciiLower(asciiTrim(sp[0])) != 'none' {
            parseNumberAt(asciiTrim(sp[0]), 0)
            if numOk {
                Transform tr
                tr.kind = TX_SCALE
                tr.sx = numValue
                tr.sy = numValue
                if sp.length > 1 {
                    parseNumberAt(asciiTrim(sp[1]), 0)
                    if numOk { tr.sy = numValue }
                }
                txs.push(tr)
            }
        }
    }
    ascii txProp = styleProp(props, 'transform')
    if txProp != null {
        arr[Transform] list = parseTransformList(txProp, s.fontSize)
        for int i = 0, i < list.length, i++ { txs.push(list[i]) }
    }
    if txs.length > 0 {
        s.transforms = txs
        cascadeSawTransform = true
    }
    // transform-origin: two of a position's components, defaulting to
    // the box's centre. An unset Len is auto, which the painter reads
    // as 50%, so the initial value costs no write.
    // `fill-box` and `stroke-box` are SVG's own boxes; outside SVG they
    // are the content box and the border box, which is what Chromium
    // 141 renders and all this engine has.
    ascii appr = styleProp(props, 'appearance')
    if appr != null { s.appearanceAuto = asciiLower(asciiTrim(appr)) != 'none' }
    ascii fsz = styleProp(props, 'field-sizing')
    if fsz != null { s.fieldSizingContent = asciiLower(asciiTrim(fsz)) == 'content' }
    ascii acc = styleProp(props, 'accent-color')
    if acc != null {
        ascii accLow = asciiLower(asciiTrim(acc))
        if accLow == 'auto' { s.accentColor = 0 }
        else {
            int got = parseCssColor(accLow, s.color)
            if got != COLOR_UNSET { s.accentColor = got }
        }
    }
    ascii tbox = styleProp(props, 'transform-box')
    if tbox != null {
        ascii tboxLow = asciiLower(asciiTrim(tbox))
        s.transformBoxContent = tboxLow == 'content-box' || tboxLow == 'fill-box'
    }
    ascii toProp = styleProp(props, 'transform-origin')
    if toProp != null {
        arr[ascii] tot = cssTokens(toProp)
        if tot.length > 0 {
            Len ox = parsePositionAxis(asciiLower(tot[0]), true, s.fontSize)
            if ox.kind == LEN_PX || ox.kind == LEN_PERCENT { s.transformOriginX = ox }
        }
        if tot.length > 1 {
            Len oy = parsePositionAxis(asciiLower(tot[1]), false, s.fontSize)
            if oy.kind == LEN_PX || oy.kind == LEN_PERCENT { s.transformOriginY = oy }
        }
    }
    // contain: a list of keywords, or one of the two shorthands.
    // `strict` is all four; `content` is all of them but size, which is
    // the whole difference between them.
    s.containInlineSize = false
    s.containBlockSize = false
    s.containLayout = false
    s.containPaint = false
    s.containStyle = false
    ascii containDecl = styleProp(props, 'contain')
    if containDecl != null {
        arr[ascii] ct = cssTokens(containDecl)
        for int i = 0, i < ct.length, i++ {
            ascii t = asciiLower(ct[i])
            if t == 'strict' {
                s.containInlineSize = true  s.containBlockSize = true
                s.containLayout = true
                s.containPaint = true  s.containStyle = true
            } else if t == 'content' {
                s.containLayout = true  s.containPaint = true  s.containStyle = true
            } else if t == 'size' { s.containInlineSize = true  s.containBlockSize = true }
            else if t == 'inline-size' { s.containInlineSize = true }
            else if t == 'layout' { s.containLayout = true }
            else if t == 'paint' { s.containPaint = true }
            else if t == 'style' { s.containStyle = true }
        }
    }
    // CSS Conditional 4 §2. `container-type` is containment under
    // another name: a query can only be answered about a box whose size
    // does not depend on what a rule the query controls might do to its
    // contents, so `inline-size` contains the inline axis and `size`
    // contains both, and each carries layout and style containment with
    // it. Chromium lays a float out under `container-type: inline-size`
    // exactly as it does under `contain: inline-size`, which is what
    // tests/unit/test_contain.f asserts rather than a number of its own.
    s.containerType = CONTAINER_NORMAL
    s.containerName = ''
    ascii ctype = styleProp(props, 'container-type')
    if ctype != null {
        ascii ct = asciiLower(asciiTrim(ctype))
        if ct == 'inline-size' { s.containerType = CONTAINER_INLINE_SIZE }
        else if ct == 'size' { s.containerType = CONTAINER_SIZE }
    }
    if s.containerType != CONTAINER_NORMAL {
        s.containInlineSize = true
        s.containLayout = true
        s.containStyle = true
        if s.containerType == CONTAINER_SIZE { s.containBlockSize = true }
    }
    ascii cname = styleProp(props, 'container-name')
    if cname != null {
        ascii cn = asciiLower(asciiTrim(cname))
        if cn != 'none' && cn.length > 0 { s.containerName = cn.toText() }
    }
    // content-visibility: hidden skips the contents, which carries size
    // containment with it (Containment 2 §4).
    s.contentHidden = false
    ascii cvis = styleProp(props, 'content-visibility')
    if cvis != null && asciiLower(asciiTrim(cvis)) == 'hidden' {
        s.contentHidden = true
        s.containInlineSize = true
        s.containBlockSize = true
        s.containLayout = true
        s.containPaint = true
        s.containStyle = true
    }
    // contain-intrinsic-size and the four axis spellings. `auto <len>`
    // is the remembered-size form, whose remembered size this engine
    // never has, so the length after it is what is used.
    // The shorthand and the two logical spellings reach here as
    // `contain-intrinsic-width` and `-height`.
    s.intrinsicWidth = intrinsicSizeProp(props, 'contain-intrinsic-width', s.fontSize, s.intrinsicWidth)
    s.intrinsicHeight = intrinsicSizeProp(props, 'contain-intrinsic-height', s.fontSize, s.intrinsicHeight)
    s.outlineOffset = 0
    ascii ooff = styleProp(props, 'outline-offset')
    if ooff != null {
        Len l = parseLength(asciiTrim(ooff), s.fontSize)
        if l.kind == LEN_PX { s.outlineOffset = roundPx(l.v) }
    }
    // table-layout: fixed takes the column widths from the first row
    // and ignores every cell's content (CSS2 17.5.2.1).
    s.tableLayoutFixed = false
    ascii tl = styleProp(props, 'table-layout')
    if tl != null && asciiLower(asciiTrim(tl)) == 'fixed' { s.tableLayoutFixed = true }
    // empty-cells inherits, because a table sets it and the cells obey.
    s.emptyCellsHide = isRoot ? false : parent.emptyCellsHide
    ascii ec = styleProp(props, 'empty-cells')
    if ec != null {
        ascii t = asciiLower(asciiTrim(ec))
        if t == 'hide' { s.emptyCellsHide = true }
        else if t == 'show' { s.emptyCellsHide = false }
    }
    // list-style-position inherits, so a rule on the <ul> reaches the
    // items, which is how it is nearly always written.
    s.listInside = isRoot ? false : parent.listInside
    ascii lsp = styleProp(props, 'list-style-position')
    if lsp != null {
        ascii t = asciiLower(asciiTrim(lsp))
        if t == 'inside' { s.listInside = true }
        else if t == 'outside' { s.listInside = false }
    }
    s.clearSide = CLEAR_NONE
    ascii cl = styleProp(props, 'clear')
    if cl != null {
        ascii t = asciiLower(cl)
        if t == 'left' { s.clearSide = CLEAR_LEFT }
        else if t == 'right' { s.clearSide = CLEAR_RIGHT }
        else if t == 'both' { s.clearSide = CLEAR_BOTH }
    }
    s.position = POS_STATIC
    ascii pos = styleProp(props, 'position')
    if pos != null {
        ascii t = asciiLower(pos)
        if t == 'relative' { s.position = POS_RELATIVE }
        else if t == 'absolute' { s.position = POS_ABSOLUTE }
        else if t == 'fixed' { s.position = POS_FIXED }
        // `sticky` keeps its place in the flow and is shifted by the
        // painter, which is the one part of the pipeline that knows
        // where the document is scrolled to.
        else if t == 'sticky' { s.position = POS_STICKY  anySticky = true }
    }
    // CSS Masking 1. A shape stays as it was written and is resolved
    // against the box at paint time; `clip` is the same rectangle said
    // in CSS2's words, and it applies only to a positioned box.
    ascii clipPathProp = styleProp(props, 'clip-path')
    if clipPathProp != null {
        ClipShape shape = parseClipPath(clipPathProp, s.fontSize)
        if shape.kind != CLIPSHAPE_NONE {
            s.clipShape = shape
            cascadeSawClip = true
        }
    }
    ClipShape rect = parseClipRect(styleProp(props, 'clip'), s.fontSize)
    if rect.kind != CLIPSHAPE_NONE {
        // `clip` computes on any box and is used only by a positioned
        // one, so it is kept whatever this element's position is and
        // the painter asks.
        s.clipRect = rect
        cascadeSawClip = true
    }
    s.top = lenProp(props, 'top', s.fontSize, lenAuto())
    s.right = lenProp(props, 'right', s.fontSize, lenAuto())
    s.bottom = lenProp(props, 'bottom', s.fontSize, lenAuto())
    s.left = lenProp(props, 'left', s.fontSize, lenAuto())
    s.zIndex = 0
    ascii zi = styleProp(props, 'z-index')
    if zi != null {
        int z = asciiTrim(zi).toText().toInt()
        // `auto` does not parse as an integer, which is what keeps it
        // out of both of these: it is neither a declared z-index nor a
        // negative one.
        if z != null {
            s.zIndex = z
            explicitZIndexOfSerial[`${s.serial}`] = true
            anyExplicitZIndex = true
            if z < 0 { cascadeSawNegativeZ = true }
        }
    }
    s.floatSide = FLOAT_NONE
    ascii fl = styleProp(props, 'float')
    if fl != null {
        ascii t = asciiLower(fl)
        if t == 'left' { s.floatSide = FLOAT_LEFT }
        else if t == 'right' { s.floatSide = FLOAT_RIGHT }
    }
    // Blockification (Display 3 sec. 2.7). A float, an absolute or
    // fixed position, being a flex or grid item, and being the root
    // element each replace an inline-level `display` with the
    // block-level value it corresponds to -- not with `block`
    // flatly: an `inline-flex` becomes a `flex` and an `inline-table` a
    // `table`. `none` and `contents` are left alone, because neither
    // names a box to convert.
    //
    // This sits here because it needs `float` and `position`, which are
    // read a few lines above and below, and the parent's display, which
    // is to hand. The condition is four integer tests on fields already
    // loaded, and it is written as one `if` rather than four so that an
    // ordinary static box in normal flow -- which is nearly every box
    // on nearly every page -- pays those four and nothing else.
    if s.floatSide != FLOAT_NONE || s.position == POS_ABSOLUTE
        || s.position == POS_FIXED || isRoot
        || (!isRoot && (parent.display == DISPLAY_FLEX
                        || parent.display == DISPLAY_INLINE_FLEX
                        || parent.display == DISPLAY_GRID
                        || parent.display == DISPLAY_INLINE_GRID)) {
        s.display = blockifiedDisplay(s.display)
    }
    // The two axes, and the standard's rule that a `visible` beside
    // anything else is really `auto`: a box cannot clip one axis and
    // let the other spill, so the one that was left alone gains a
    // scrollbar where it needs one.
    s.overflowX = overflowKeyword(styleProp(props, 'overflow-x'))
    s.overflowY = overflowKeyword(styleProp(props, 'overflow-y'))
    if s.overflowX == OVERFLOW_VISIBLE && s.overflowY != OVERFLOW_VISIBLE {
        s.overflowX = OVERFLOW_AUTO
    }
    if s.overflowY == OVERFLOW_VISIBLE && s.overflowX != OVERFLOW_VISIBLE {
        s.overflowY = OVERFLOW_AUTO
    }
    // Every value but `visible` clips what runs past the box.
    s.overflowHidden = s.overflowX != OVERFLOW_VISIBLE || s.overflowY != OVERFLOW_VISIBLE
    // CSS Inline 3. The shorthand is read first so a longhand beside it
    // wins, which is what the cascade already does for every other pair.
    int tbTrim = TBTRIM_NONE
    int tbEdge = TBOVER_TEXT * 4 + TBUNDER_TEXT
    bool tbSaid = false
    ascii tbTrimV = styleProp(props, 'text-box-trim')
    if tbTrimV != null {
        int t = textBoxTrimKeyword(asciiLower(asciiTrim(tbTrimV)))
        if t >= 0 { tbTrim = t  tbSaid = true }
    }
    ascii tbEdgeV = styleProp(props, 'text-box-edge')
    if tbEdgeV != null {
        ascii tbeLow = asciiLower(asciiTrim(tbEdgeV))
        arr[ascii] w = asciiSplitSpace(tbeLow)
        int e = textBoxEdgePair(w, 0)
        if e >= 0 { tbEdge = e  tbSaid = true }
    }
    if tbSaid {
        textBoxOf[`${s.serial}`] = tbTrim * 16 + tbEdge
        if tbTrim != TBTRIM_NONE { anyTextBoxTrim = true }
    }
    // `box-decoration-break: slice | clone`. Only `clone` is recorded:
    // `slice` is the initial value and what an unrecorded style means.
    ascii bdb = styleProp(props, 'box-decoration-break')
    if bdb != null && asciiLower(asciiTrim(bdb)) == 'clone' {
        decoCloneOf[`${s.serial}`] = 1
        anyDecorationClone = true
    }
    // `overscroll-behavior: [ contain | none | auto ]{1,2}`, the first
    // value the horizontal axis and the second the vertical, one value
    // both. The logical longhands are the physical ones under other
    // names -- `inline` is `x` and `block` is `y`, in either direction
    // (todo.md) -- so they are read into the same pair. The shorthand is
    // read before them, which resolves the two by a fixed order rather
    // than by where they were written, as this file does elsewhere.
    int osbX = OSB_AUTO
    int osbY = OSB_AUTO
    bool osbSaid = false
    // The shorthand and the two logical spellings reach here as
    // `overscroll-behavior-x` and `-y`, which applyDecl turned them
    // into.
    ascii osbXv = styleProp(props, 'overscroll-behavior-x')
    if osbXv != null {
        int v = overscrollKeyword(asciiLower(asciiTrim(osbXv)))
        if v >= 0 { osbX = v  osbSaid = true }
    }
    ascii osbYv = styleProp(props, 'overscroll-behavior-y')
    if osbYv != null {
        int v = overscrollKeyword(asciiLower(asciiTrim(osbYv)))
        if v >= 0 { osbY = v  osbSaid = true }
    }
    if osbSaid && (osbX != OSB_AUTO || osbY != OSB_AUTO) {
        overscrollOf[`${s.serial}`] = osbX * 4 + osbY
        anyOverscrollBehavior = true
    }
    // `overflow-clip-margin: <visual-box> || <length [0,inf]>`. The box
    // defaults to the padding box, which is what an unmoved clip edge
    // already is, and the length to zero.
    ascii ocm = styleProp(props, 'overflow-clip-margin')
    if ocm != null {
        ascii ocmLow = asciiLower(asciiTrim(ocm))
        arr[ascii] ocmWords = asciiSplitSpace(ocmLow)
        int ocmBox = GEOBOX_PADDING
        int ocmPx = 0
        bool ocmSaid = false
        for int i = 0, i < ocmWords.length, i++ {
            int gb = geometryBoxAt(ocmWords[i], 0, ocmWords[i].length)
            if gb >= 0 {
                ocmBox = gb
                ocmSaid = true
            } else {
                Len l = parseLength(ocmWords[i], s.fontSize)
                if l.kind != LEN_AUTO && l.kind != LEN_INVALID {
                    int px = resolveLen(l, 0, 0)
                    if px > 0 { ocmPx = px }
                    ocmSaid = true
                }
            }
        }
        if ocmSaid {
            clipMarginOf[`${s.serial}`] = ocmPx * 8 + ocmBox
            anyClipMargin = true
        }
    }
    // LAST, because the adjustment changes the font actually used and
    // nothing else: `font-size` still computes to the specified value
    // and every `em` above has already resolved against it, which is
    // measured -- `width: 2em` under `font-size-adjust: 1` is 32px and
    // not 57 (todo.md). A `line-height: normal` follows the used size
    // instead, and does so for free, because `normal` is stored as 0
    // and worked out from `fontSize` when it is read.
    if cascadeSawFontSizeAdjust { applyFontSizeAdjust(s, props) }
    // Back to no zoom, so nothing outside this element's declarations
    // is scaled: `lenPx` is called from layout and paint as well.
    cascadeZoomScale = 1.0
    // `resize` is stored as the keyword that was declared, because
    // that is what it computes to: Chromium reports `block` for
    // `resize: block` rather than resolving it to `vertical`. Whether
    // it may be seen at all is a question about `overflow`, and it is
    // asked where the grabber is painted rather than here, since the
    // computed value does not depend on it.
    if cascadeSawTextWrapStyle { applyTextWrapStyle(s, parent, isRoot, props) }
    if cascadeSawPrintColorAdjust { applyPrintColorAdjust(s, parent, isRoot, props) }
    if cascadeSawRuby { applyRuby(s, parent, isRoot, props) }
    if cascadeSawResize {
        ascii rsz = styleProp(props, 'resize')
        if rsz != null {
            int rv = resizeKeyword(asciiLower(asciiTrim(rsz)))
            if rv != RESIZE_NONE {
                resizeOfSerial[`${s.serial}`] = rv
                anyResize = true
            }
        }
    }
    if cascadeSawBaselineSource {
        ascii bsrc = styleProp(props, 'baseline-source')
        if bsrc != null {
            ascii bw = asciiLower(asciiTrim(bsrc))
            int bv = bw == 'first' ? BSRC_FIRST : (bw == 'last' ? BSRC_LAST : BSRC_AUTO)
            if bv != BSRC_AUTO {
                baselineSourceOfSerial[`${s.serial}`] = bv
                anyBaselineSource = true
            }
        }
    }
    return s
}

// The aspect of each metric this engine can answer -- the metric as a
// fraction of the em -- from the constants the `ex`, `ch` and `cap`
// units read. Chromium's are the HINTED metrics and move with the
// size; these do not, so the used size differs by 2.8% at 16px and
// more below it, which todo.md records with both numbers.
float func fontSizeAdjustAspect(metric:ascii) {
    if metric == 'ex-height' { return FONT_EX }
    if metric == 'cap-height' { return FONT_CAP }
    if metric == 'ch-width' { return FONT_CH }
    // An ideograph's advance is an em, and so is its height in every
    // font this engine can load, which is what Chromium measures here.
    if metric == 'ic-width' || metric == 'ic-height' { return 1.0 }
    return 0.0
}

// The element's effective zoom: its parent's times its own, because
// `zoom` compounds down the tree -- a `zoom: 2` inside a `zoom: 2` is
// at four and a `zoom: 0.5` inside one is back at one, both measured.
// `normal`, zero, a negative and anything that is not a number all
// leave it at the parent's, which is what Chromium computes.
// An INHERITED length, brought from the parent's zoom into this
// element's. Every declared length is zoomed as `lenPx` builds it, but
// an inherited one is copied rather than parsed, so it arrives
// carrying the PARENT's zoom and needs the ratio. Chromium's model is
// the same seen from the other side: it keeps computed values unzoomed
// and multiplies at use, where this multiplies once and converts on
// the way down.
//
// The inherited properties that carry a length are few and this is all
// of them: `line-height`, `letter-spacing`, `word-spacing`,
// `text-indent` and `tab-size`. `border-spacing` would belong here too
// and does not inherit in this engine at all, which is its own gap.
int func zoomInherit(v:int, parent:Style) {
    if !cascadeSawZoom { return v }
    float pz = zoomOf(parent)
    if pz == cascadeZoomScale { return v }
    return roundPx(v.toFloat() * cascadeZoomScale / pz)
}

// A length computed HERE from the unzoomed font size rather than
// parsed -- a unitless or percentage `line-height` -- which `lenPx`
// therefore never sees.
int func zoomHere(v:int) {
    if !cascadeSawZoom || cascadeZoomScale == 1.0 { return v }
    return roundPx(v.toFloat() * cascadeZoomScale)
}

void func applyZoom(s:Style, parent:Style, isRoot:bool, props:map[text]) {
    float eff = isRoot ? 1.0 : zoomOf(parent)
    ascii raw = styleProp(props, 'zoom')
    if raw != null {
        ascii z = asciiLower(asciiTrim(raw))
        if z != 'normal' {
            // A percentage is the number over a hundred, which is what
            // makes `zoom: 50%` and `zoom: 0.5` the same.
            bool pct = z.length > 1 && z.charCodeAt(z.length - 1) == CH_PERCENT
            ascii num = pct ? z.slice(0, z.length - 1) : z
            parseNumberAt(num, 0)
            if numOk && numEnd == num.length {
                float v = pct ? numValue / 100.0 : numValue
                if v > 0.0 { eff = eff * v }
            }
        }
    }
    cascadeZoomScale = eff
    if eff != 1.0 {
        zoomOfSerial[`${s.serial}`] = roundPx(eff * 10000.0)
        anyZoom = true
    }
}

void func applyFontSizeAdjust(s:Style, props:map[text]) {
    ascii raw = styleProp(props, 'font-size-adjust')
    if raw == null { return }
    arr[ascii] words = asciiSplitSpace(asciiLower(asciiTrim(raw)))
    if words.length == 0 || words.length > 2 { return }
    // The words are INDEXED rather than bound to locals: an element of
    // a split aliases the buffer it was cut from, and an `ascii` bound
    // to a local is released at scope exit without ever having been
    // retained (FINDINGS.md, "ascii aliases are not retained"). Writing
    // `ascii amount = words[at]` here passed every check natively and
    // failed under valgrind with an invalid read of size 8 in
    // `festina_ascii_release`, which is the same shape as the bug this
    // branch already records.
    int at = words.length - 1
    // `from-font` asks for the font's own aspect, which by definition
    // leaves the size where it is.
    if words[at] == 'from-font' || words[at] == 'none' { return }
    // `ex-height` is the default, so a bare number means it.
    float aspect = words.length == 2 ? fontSizeAdjustAspect(words[0]) : FONT_EX
    if aspect <= 0.0 { return }
    // A bare number and nothing else. A percentage, a negative and a
    // second number are all invalid, measured rather than assumed.
    parseNumberAt(words[at], 0)
    if !numOk || numEnd != words[at].length || numValue < 0.0 { return }
    s.fontSize = roundPx(s.fontSize.toFloat() * numValue / aspect)
    // The width cache keys on the font, so a font changed after the
    // style was computed has to rebuild the key or every string at the
    // new size gets the old size's advance (changelog.md, the drop cap
    // that measured 38 pixels at three different font sizes).
    refreshFontKey(s)
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
    // The counters an element resets or increments are in force for its
    // own generated content, so they are applied before it is resolved.
    if anyCounters {
        // Reset, then increment, then set: `counter-reset: c 100;
        // counter-set: c 5` is 5 and `counter-increment: c 500;
        // counter-set: c 1` is 1, both measured against Chromium 141.
        applyCounterProperty(s.counterReset.toAscii(), styleDepth, COUNTER_OP_RESET)
        applyCounterProperty(s.counterIncrement.toAscii(), styleDepth, COUNTER_OP_INCREMENT)
        applyCounterProperty(s.counterSet.toAscii(), styleDepth, COUNTER_OP_SET)
    }
    computePseudoElements(n, s)
    styleDepth++
    for int i = 0, i < n.children.length, i++ {
        computeStylesFrom(n.children[i], s, false)
    }
    styleDepth--
    // The first-line variants need the subtree's ordinary styles, so
    // they are computed on the way back up. A page with no ::first-line
    // rule pays one boolean here.
    if anyFirstLine { computeFirstLineStyles(n) }
    // An instance created by a child is in scope for that child's
    // following siblings, so it lives until the children are done.
    if anyCounters {
        popCountersBelow(styleDepth + 1)
        popShadowingCountersAt(styleDepth)
    }
}

void func computeStyles(doc:Node) {
    Style none
    styleDepth = 0
    // A layer's place depends on layers that may be named after it, so
    // the ranks are computed once here rather than as each is declared.
    // A page with no `@layer` on it returns on the function's first
    // line.
    cssComputeLayerRanks()
    resetCounters()
    computeStylesFrom(doc, none, true)
    if archtelosTiming { log(cascadeProfile()) }
}

// A readable dump of a computed style, and the digest the shorthand
// audit in tests/unit/test_cascade_rules.f compares two documents by.
// Which fields it carries is therefore not a matter of taste: a
// shorthand whose longhand is missing from here cannot be graded at
// all, because the document that reverts and the document that does
// not compute the same string. Nine of the twenty shorthands in that
// audit could not be asked until the second line below existed
// (todo.md, "What a sweep of the CSS Cascade row found").
text func describeStyle(s:Style) {
    text base = `display=${s.display} color=${s.color} bg=${s.background} font=${s.fontKey} lh=${s.lineHeight} align=${s.textAlign} deco=${s.textDecoration} ws=${s.whiteSpaceCollapse}/${s.textWrapMode} list=${s.listStyle} m=${resolveLen(s.marginTop, 0, -1)}/${resolveLen(s.marginRight, 0, -1)}/${resolveLen(s.marginBottom, 0, -1)}/${resolveLen(s.marginLeft, 0, -1)} p=${resolveLen(s.paddingTop, 0, -1)}/${resolveLen(s.paddingRight, 0, -1)}/${resolveLen(s.paddingBottom, 0, -1)}/${resolveLen(s.paddingLeft, 0, -1)} b=${s.borderTop}/${s.borderRight}/${s.borderBottom}/${s.borderLeft} w=${s.width.kind}:${s.width.v} h=${s.height.kind}:${s.height.v}`
    return `${base} cols=${s.columnCount} gap=${s.rowGap}/${s.columnGap} of=${s.overflowX}/${s.overflowY} flex=${s.flexGrow}/${s.flexShrink} ai=${s.alignItems} jc=${s.justifyContent} ins=${resolveLen(s.top, 0, -1)}/${resolveLen(s.left, 0, -1)} sm=${resolveLen(s.scrollMarginTop, 0, -1)} gr=${s.gridRowStart.kind}:${s.gridRowStart.n} gc=${s.gridColStart.kind}:${s.gridColStart.n}`
}


// One border-image-repeat keyword.
int func borderImageRepeatKeyword(t:ascii) {
    if t == 'repeat' { return BORDERIMG_REPEAT }
    if t == 'round' { return BORDERIMG_ROUND }
    if t == 'space' { return BORDERIMG_SPACE }
    return BORDERIMG_STRETCH
}


// One `overflow-x` or `overflow-y` keyword.
int func overflowKeyword(v:ascii) {
    if v == null { return OVERFLOW_VISIBLE }
    ascii t = asciiLower(asciiTrim(v))
    if t == 'hidden' { return OVERFLOW_HIDDEN }
    if t == 'clip' { return OVERFLOW_CLIP }
    if t == 'scroll' { return OVERFLOW_SCROLL }
    if t == 'auto' { return OVERFLOW_AUTO }
    return OVERFLOW_VISIBLE
}
