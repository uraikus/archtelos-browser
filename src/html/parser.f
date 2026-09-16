// Tree construction, per the WHATWG HTML Living Standard
// ("Tree construction"): the insertion modes, the stack of open
// elements and its scopes, the list of active formatting elements with
// the adoption agency algorithm, and foster parenting.
//
// Everything works on node ids rather than node values. That is not a
// style choice: binding a live node to a local and letting it go out of
// scope makes Festina's cycle collector walk everything reachable from
// it, which for a document is the whole document (FINDINGS.md, finding
// 1). Ids keep the tree acyclic and the algorithms allocation-free.

import ../dom/node.f
import tokenizer.f
import decode.f

// ---- insertion modes ---------------------------------------------------

const int IM_INITIAL = 0
const int IM_BEFORE_HTML = 1
const int IM_BEFORE_HEAD = 2
const int IM_IN_HEAD = 3
const int IM_IN_HEAD_NOSCRIPT = 4
const int IM_AFTER_HEAD = 5
const int IM_IN_BODY = 6
const int IM_TEXT = 7
const int IM_IN_TABLE = 8
const int IM_IN_TABLE_TEXT = 9
const int IM_IN_CAPTION = 10
const int IM_IN_COLUMN_GROUP = 11
const int IM_IN_TABLE_BODY = 12
const int IM_IN_ROW = 13
const int IM_IN_CELL = 14
const int IM_IN_TEMPLATE = 17
const int IM_AFTER_BODY = 18
const int IM_IN_FRAMESET = 19
const int IM_AFTER_FRAMESET = 20
const int IM_AFTER_AFTER_BODY = 21
const int IM_AFTER_AFTER_FRAMESET = 22

// A marker in the list of active formatting elements.
const int AFE_MARKER = 0

int insertionMode = IM_INITIAL
int originalInsertionMode = IM_INITIAL
arr[int] openElements = []
arr[int] activeFormatting = []
arr[int] templateModes = []
// frameset-ok as it was when each open template started: a template's
// contents do not decide whether a later <frameset> replaces the body.
arr[bool] templateFramesetOk = []
int documentId = 0
int headElementId = 0
int formElementId = 0
bool framesetOk = true
bool quirksMode = false
bool fosterParenting = false
bool parserDone = false
// A newline immediately after <pre>, <listing> or <textarea> is dropped.
bool skipNextNewline = false
// set when a selectedcontent element is inserted, so the mirroring pass
// below runs only for documents that contain one
bool sawSelectedContent = false
arr[text] pendingTableText = []
bool pendingTableTextNonSpace = false

// The insertion point chosen by the "appropriate place for inserting a
// node" algorithm: a parent and either an index to insert before or -1
// to append. Two globals because a Festina function returns one value
// (FINDINGS.md, "no multiple return values").
int insertParentId = 0
int insertBeforeIndex = -1


// ---- quirks mode ---------------------------------------------------------
//
// The standard's doctype checks, from "the initial insertion mode". Only
// full quirks affects tree construction (a `table` start tag does not
// close an open `p` in quirks mode); limited quirks changes CSS only.

arr[text] quirksPublicIdPrefixes = [
    "+//Silmaril//dtd html Pro v0r11 19970101//",
    "-//AS//DTD HTML 3.0 asWedit + extensions//",
    "-//AdvaSoft Ltd//DTD HTML 3.0 asWedit + extensions//",
    "-//IETF//DTD HTML 2.0 Level 1//",
    "-//IETF//DTD HTML 2.0 Level 2//",
    "-//IETF//DTD HTML 2.0 Strict Level 1//",
    "-//IETF//DTD HTML 2.0 Strict Level 2//",
    "-//IETF//DTD HTML 2.0 Strict//",
    "-//IETF//DTD HTML 2.0//",
    "-//IETF//DTD HTML 2.1E//",
    "-//IETF//DTD HTML 3.0//",
    "-//IETF//DTD HTML 3.2 Final//",
    "-//IETF//DTD HTML 3.2//",
    "-//IETF//DTD HTML 3//",
    "-//IETF//DTD HTML Level 0//",
    "-//IETF//DTD HTML Level 1//",
    "-//IETF//DTD HTML Level 2//",
    "-//IETF//DTD HTML Level 3//",
    "-//IETF//DTD HTML Strict Level 0//",
    "-//IETF//DTD HTML Strict Level 1//",
    "-//IETF//DTD HTML Strict Level 2//",
    "-//IETF//DTD HTML Strict Level 3//",
    "-//IETF//DTD HTML Strict//",
    "-//IETF//DTD HTML//",
    "-//Metrius//DTD Metrius Presentational//",
    "-//Microsoft//DTD Internet Explorer 2.0 HTML Strict//",
    "-//Microsoft//DTD Internet Explorer 2.0 HTML//",
    "-//Microsoft//DTD Internet Explorer 2.0 Tables//",
    "-//Microsoft//DTD Internet Explorer 3.0 HTML Strict//",
    "-//Microsoft//DTD Internet Explorer 3.0 HTML//",
    "-//Microsoft//DTD Internet Explorer 3.0 Tables//",
    "-//Netscape Comm. Corp.//DTD HTML//",
    "-//Netscape Comm. Corp.//DTD Strict HTML//",
    "-//O'Reilly and Associates//DTD HTML 2.0//",
    "-//O'Reilly and Associates//DTD HTML Extended 1.0//",
    "-//O'Reilly and Associates//DTD HTML Extended Relaxed 1.0//",
    "-//SQ//DTD HTML 2.0 HoTMetaL + extensions//",
    "-//SoftQuad Software//DTD HoTMetaL PRO 6.0::19990601::extensions to HTML 4.0//",
    "-//SoftQuad//DTD HoTMetaL PRO 4.0::19971010::extensions to HTML 4.0//",
    "-//Spyglass//DTD HTML 2.0 Extended//",
    "-//Sun Microsystems Corp.//DTD HotJava HTML//",
    "-//Sun Microsystems Corp.//DTD HotJava Strict HTML//",
    "-//W3C//DTD HTML 3 1995-03-24//",
    "-//W3C//DTD HTML 3.2 Draft//",
    "-//W3C//DTD HTML 3.2 Final//",
    "-//W3C//DTD HTML 3.2//",
    "-//W3C//DTD HTML 3.2S Draft//",
    "-//W3C//DTD HTML 4.0 Frameset//",
    "-//W3C//DTD HTML 4.0 Transitional//",
    "-//W3C//DTD HTML Experimental 19960712//",
    "-//W3C//DTD HTML Experimental 970421//",
    "-//W3C//DTD W3 HTML//",
    "-//W3O//DTD W3 HTML 3.0//",
    "-//WebTechs//DTD Mozilla HTML 2.0//",
    "-//WebTechs//DTD Mozilla HTML//",
]

bool func doctypeMeansQuirks(tok:Token) {
    if tok.forceQuirks { return true }
    if tok.name != 'html' { return true }
    text pub = tok.publicId == null ? '' : textLower(tok.publicId)
    text sys = tok.systemId == null ? '' : textLower(tok.systemId)
    if pub == '-//w3o//dtd w3 html strict 3.0//en//' { return true }
    if pub == '-/w3c/dtd html 4.0 transitional/en' { return true }
    if pub == 'html' { return true }
    if sys == 'http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd' { return true }
    ascii p = pub.toAscii()
    if p != null {
        for int i = 0, i < quirksPublicIdPrefixes.length, i++ {
            ascii want = textLower(quirksPublicIdPrefixes[i]).toAscii()
            if want != null && asciiStartsWith(p, want, 0) { return true }
        }
        bool noSystem = tok.systemId == null || tok.systemId == ''
        if noSystem {
            if asciiStartsWith(p, '-//w3c//dtd html 4.01 frameset//', 0) { return true }
            if asciiStartsWith(p, '-//w3c//dtd html 4.01 transitional//', 0) { return true }
        }
    }
    return false
}

// ---- element categories -------------------------------------------------

// The standard's "special" category. `select` is deliberately absent:
// a select now holds ordinary flow content, and treating it as special
// would stop the adoption agency and the implied-end-tag searches at a
// select that should be transparent to them.
bool func isSpecialElement(tag:text) {
    return tag == 'address' || tag == 'applet' || tag == 'area' || tag == 'article'
        || tag == 'aside' || tag == 'base' || tag == 'basefont' || tag == 'bgsound'
        || tag == 'blockquote' || tag == 'body' || tag == 'br' || tag == 'button'
        || tag == 'caption' || tag == 'center' || tag == 'col' || tag == 'colgroup'
        || tag == 'dd' || tag == 'details' || tag == 'dir' || tag == 'div' || tag == 'dl'
        || tag == 'dt' || tag == 'embed' || tag == 'fieldset' || tag == 'figcaption'
        || tag == 'figure' || tag == 'footer' || tag == 'form' || tag == 'frame'
        || tag == 'frameset' || tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4'
        || tag == 'h5' || tag == 'h6' || tag == 'head' || tag == 'header' || tag == 'hgroup'
        || tag == 'hr' || tag == 'html' || tag == 'iframe' || tag == 'img' || tag == 'input'
        || tag == 'keygen' || tag == 'li' || tag == 'link' || tag == 'listing' || tag == 'main'
        || tag == 'marquee' || tag == 'menu' || tag == 'meta' || tag == 'nav'
        || tag == 'noembed' || tag == 'noframes' || tag == 'noscript' || tag == 'object'
        || tag == 'ol' || tag == 'p' || tag == 'param' || tag == 'plaintext' || tag == 'pre'
        || tag == 'script' || tag == 'search' || tag == 'section'
        || tag == 'source' || tag == 'style' || tag == 'summary' || tag == 'table'
        || tag == 'tbody' || tag == 'td' || tag == 'template' || tag == 'textarea'
        || tag == 'tfoot' || tag == 'th' || tag == 'thead' || tag == 'title' || tag == 'tr'
        || tag == 'track' || tag == 'ul' || tag == 'wbr' || tag == 'xmp'
}

bool func isFormattingElement(tag:text) {
    return tag == 'a' || tag == 'b' || tag == 'big' || tag == 'code' || tag == 'em'
        || tag == 'font' || tag == 'i' || tag == 'nobr' || tag == 's' || tag == 'small'
        || tag == 'strike' || tag == 'strong' || tag == 'tt' || tag == 'u'
}

bool func isHeadingTag(tag:text) {
    return tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4' || tag == 'h5' || tag == 'h6'
}

bool func isImpliedEndTag(tag:text) {
    return tag == 'dd' || tag == 'dt' || tag == 'li' || tag == 'optgroup' || tag == 'option'
        || tag == 'p' || tag == 'rb' || tag == 'rp' || tag == 'rt' || tag == 'rtc'
}

bool func isImpliedEndTagThorough(tag:text) {
    return isImpliedEndTag(tag) || tag == 'caption' || tag == 'colgroup' || tag == 'tbody'
        || tag == 'td' || tag == 'tfoot' || tag == 'th' || tag == 'thead' || tag == 'tr'
}

bool func isVoidElement(tag:text) {
    return tag == 'area' || tag == 'base' || tag == 'br' || tag == 'col' || tag == 'embed'
        || tag == 'hr' || tag == 'img' || tag == 'input' || tag == 'keygen' || tag == 'link'
        || tag == 'meta' || tag == 'param' || tag == 'source' || tag == 'track' || tag == 'wbr'
}

// ---- the stack of open elements ------------------------------------------

int func currentNodeId() {
    if openElements.length == 0 { return 0 }
    return openElements[openElements.length - 1]
}

text func currentTag() {
    int id = currentNodeId()
    if id == 0 { return '' }
    if nodeRegistry[id].ns != NS_HTML { return '' }
    return nodeRegistry[id].tag
}

// The current node's tag whatever its namespace.
text func currentTagAnyNs() {
    int id = currentNodeId()
    if id == 0 { return '' }
    return nodeRegistry[id].tag
}

text func tagOf(id:int) {
    if id <= 0 { return '' }
    return nodeRegistry[id].tag
}

int func nsOf(id:int) {
    if id <= 0 { return NS_HTML }
    return nodeRegistry[id].ns
}

// The tag name only when the element is in the HTML namespace. Every
// rule written in terms of a tag name means an HTML element unless the
// standard says otherwise, so the stack and scope helpers use this.
text func htmlTagOf(id:int) {
    if id <= 0 || nodeRegistry[id].ns != NS_HTML { return '' }
    return nodeRegistry[id].tag
}

// An mi, mo, mn, ms or mtext element in the MathML namespace.
bool func isMathTextIntegrationPoint(id:int) {
    if nsOf(id) != NS_MATHML { return false }
    text t = tagOf(id)
    return t == 'mi' || t == 'mo' || t == 'mn' || t == 'ms' || t == 'mtext'
}

// An annotation-xml carrying an HTML encoding, or SVG's foreignObject,
// desc or title.
bool func isHtmlIntegrationPoint(id:int) {
    int ns = nsOf(id)
    text t = tagOf(id)
    if ns == NS_MATHML && t == 'annotation-xml' {
        text enc = nodeRegistry[id].attrs['encoding']
        if enc == null { return false }
        text lower = textLower(enc)
        return lower == 'text/html' || lower == 'application/xhtml+xml'
    }
    if ns == NS_SVG {
        return t == 'foreignobject' || t == 'foreignObject' || t == 'desc' || t == 'title'
    }
    return false
}

void func pushOpenElement(id:int) {
    openElements.push(id)
}

int func popOpenElement() {
    if openElements.length == 0 { return 0 }
    return openElements.pop()
}

int func stackIndexOf(id:int) {
    for int i = openElements.length - 1, i >= 0, i-- {
        if openElements[i] == id { return i }
    }
    return -1
}

bool func stackHasTag(tag:text) {
    for int i = openElements.length - 1, i >= 0, i-- {
        if htmlTagOf(openElements[i]) == tag { return true }
    }
    return false
}

// The scope-terminating elements shared by "have an element in scope"
// and its variants.
bool func isScopeBoundary(tag:text) {
    return tag == 'applet' || tag == 'caption' || tag == 'html' || tag == 'table'
        || tag == 'td' || tag == 'th' || tag == 'marquee' || tag == 'object'
        || tag == 'template'
}

const int SCOPE_DEFAULT = 0
const int SCOPE_LIST_ITEM = 1
const int SCOPE_BUTTON = 2
const int SCOPE_TABLE = 3
const int SCOPE_SELECT = 4

bool func scopeStops(kind:int, tag:text) {
    if kind == SCOPE_TABLE {
        return tag == 'html' || tag == 'table' || tag == 'template'
    }
    if kind == SCOPE_SELECT {
        return tag != 'optgroup' && tag != 'option'
    }
    if isScopeBoundary(tag) { return true }
    if kind == SCOPE_LIST_ITEM { return tag == 'ol' || tag == 'ul' }
    if kind == SCOPE_BUTTON { return tag == 'button' }
    return false
}

bool func hasElementInScope(tag:text, kind:int) {
    for int i = openElements.length - 1, i >= 0, i-- {
        int id = openElements[i]
        if htmlTagOf(id) == tag { return true }
        if nsOf(id) != NS_HTML {
            // foreign integration points also terminate a scope search
            if isMathTextIntegrationPoint(id) || isHtmlIntegrationPoint(id) { return false }
            continue
        }
        if scopeStops(kind, tagOf(id)) { return false }
    }
    return false
}

// True when any of the table-section tags is in table scope.
bool func hasAnyInTableScope(a:text, b:text, c:text) {
    for int i = openElements.length - 1, i >= 0, i-- {
        text t = htmlTagOf(openElements[i])
        if t == a || t == b || t == c { return true }
        if scopeStops(SCOPE_TABLE, t) { return false }
    }
    return false
}

void func generateImpliedEndTags(except:text) {
    while openElements.length > 0 {
        text t = currentTag()
        if t == except || !isImpliedEndTag(t) { break }
        popOpenElement()
    }
}

void func generateImpliedEndTagsThoroughly() {
    while openElements.length > 0 {
        text t = currentTag()
        if !isImpliedEndTagThorough(t) { break }
        popOpenElement()
    }
}

void func popUntilIncludingTag(tag:text) {
    while openElements.length > 0 {
        text t = htmlTagOf(currentNodeId())
        popOpenElement()
        if t == tag { return }
    }
}

// ---- node manipulation ------------------------------------------------------

void func reindexChildren(parentId:int) {
    int count = nodeRegistry[parentId].children.length
    for int i = 0, i < count, i++ {
        nodeRegistry[parentId].children[i].childIndex = i
    }
}

void func detachNode(id:int) {
    int parent = nodeRegistry[id].parentId
    if parent <= 0 { return }
    int index = nodeRegistry[id].childIndex
    int count = nodeRegistry[parent].children.length
    if index < 0 || index >= count || nodeRegistry[parent].children[index].id != id {
        index = -1
        for int i = 0, i < count, i++ {
            if nodeRegistry[parent].children[i].id == id {
                index = i
                break
            }
        }
    }
    if index < 0 { return }
    nodeRegistry[parent].children.splice(index, 1)
    nodeRegistry[id].parentId = 0
    reindexChildren(parent)
}

void func appendNode(parentId:int, childId:int) {
    detachNode(childId)
    nodeRegistry[childId].parentId = parentId
    nodeRegistry[childId].childIndex = nodeRegistry[parentId].children.length
    nodeRegistry[parentId].children.push(nodeRegistry[childId])
}

void func insertNodeAt(parentId:int, index:int, childId:int) {
    detachNode(childId)
    nodeRegistry[childId].parentId = parentId
    arr[Node] one = [nodeRegistry[childId]]
    nodeRegistry[parentId].children.splice(index, 0, one)
    reindexChildren(parentId)
}

// ---- the appropriate place for inserting a node --------------------------

// "The appropriate place for inserting a node", including the foster
// parenting substeps and the template-contents redirect.
void func findInsertionPlace(overrideTarget:int) {
    int target = overrideTarget > 0 ? overrideTarget : currentNodeId()
    insertParentId = target
    insertBeforeIndex = -1
    text t = htmlTagOf(target)
    bool inTableContext = t == 'table' || t == 'tbody' || t == 'tfoot' || t == 'thead' || t == 'tr'
    if fosterParenting && inTableContext {
        int lastTemplate = -1
        int lastTable = -1
        for int i = openElements.length - 1, i >= 0, i-- {
            text n = htmlTagOf(openElements[i])
            if lastTemplate < 0 && n == 'template' { lastTemplate = i }
            if lastTable < 0 && n == 'table' { lastTable = i }
            if lastTemplate >= 0 && lastTable >= 0 { break }
        }
        // a template lower in the stack than the last table takes the
        // node into its contents
        if lastTemplate >= 0 && (lastTable < 0 || lastTemplate > lastTable) {
            int holder = openElements[lastTemplate]
            insertParentId = nodeRegistry[holder].contentId > 0 ? nodeRegistry[holder].contentId : holder
            return
        }
        if lastTable < 0 {
            insertParentId = openElements[0]
            return
        }
        int tableId = openElements[lastTable]
        if nodeRegistry[tableId].parentId > 0 {
            insertParentId = nodeRegistry[tableId].parentId
            insertBeforeIndex = nodeRegistry[tableId].childIndex
            return
        }
        insertParentId = openElements[lastTable - 1]
        return
    }
    // "if the adjusted insertion location is inside a template element,
    // let it instead be inside the template's contents"
    if htmlTagOf(insertParentId) == 'template' && nodeRegistry[insertParentId].contentId > 0 {
        insertParentId = nodeRegistry[insertParentId].contentId
    }
}

void func insertAtPlace(childId:int) {
    if insertBeforeIndex < 0 {
        appendNode(insertParentId, childId)
    } else {
        insertNodeAt(insertParentId, insertBeforeIndex, childId)
    }
}

// ---- inserting tokens ---------------------------------------------------------

int func createElementForToken(tok:Token) {
    Node el = newElement(tok.name)
    el.attrs = tok.attrs
    el.present = tok.present
    el.hasPresHint = tok.hasPresHint
    return el.id
}

int func insertElementForToken(tok:Token) {
    if tok.name == 'selectedcontent' { sawSelectedContent = true }
    int id = createElementForToken(tok)
    findInsertionPlace(0)
    insertAtPlace(id)
    pushOpenElement(id)
    return id
}

void func insertCharacters(data:text) {
    if data == null || data == '' { return }
    findInsertionPlace(0)
    int parent = insertParentId
    if insertBeforeIndex < 0 {
        int count = nodeRegistry[parent].children.length
        if count > 0 && nodeRegistry[parent].children[count - 1].kind == NODE_TEXT {
            nodeRegistry[parent].children[count - 1].data = nodeRegistry[parent].children[count - 1].data + data
            return
        }
    } else if insertBeforeIndex > 0 {
        if nodeRegistry[parent].children[insertBeforeIndex - 1].kind == NODE_TEXT {
            nodeRegistry[parent].children[insertBeforeIndex - 1].data = nodeRegistry[parent].children[insertBeforeIndex - 1].data + data
            return
        }
    }
    Node t = newTextNode(data)
    insertAtPlace(t.id)
}

void func insertCommentNode(data:text, overrideTarget:int) {
    Node c = newComment(data)
    findInsertionPlace(overrideTarget)
    insertAtPlace(c.id)
}

// ---- the list of active formatting elements -------------------------------------

void func pushActiveFormatting(id:int) {
    // the Noah's Ark clause: at most three equal entries survive
    int equal = 0
    int earliest = -1
    for int i = activeFormatting.length - 1, i >= 0, i-- {
        int e = activeFormatting[i]
        if e == AFE_MARKER { break }
        if tagOf(e) != tagOf(id) { continue }
        if !sameAttributes(e, id) { continue }
        equal++
        if earliest < 0 || i < earliest { earliest = i }
    }
    if equal >= 3 && earliest >= 0 { activeFormatting.splice(earliest, 1) }
    activeFormatting.push(id)
}

bool func sameAttributes(a:int, b:int) {
    arr[text] an = nodeRegistry[a].present.keys()
    arr[text] bn = nodeRegistry[b].present.keys()
    if an.length != bn.length { return false }
    for int i = 0, i < an.length, i++ {
        if nodeRegistry[b].present[an[i]] != true { return false }
        text av = nodeRegistry[a].attrs[an[i]]
        text bv = nodeRegistry[b].attrs[an[i]]
        if av == null { av = '' }
        if bv == null { bv = '' }
        if av != bv { return false }
    }
    return true
}

void func clearActiveFormattingToMarker() {
    while activeFormatting.length > 0 {
        int e = activeFormatting.pop()
        if e == AFE_MARKER { return }
    }
}

int func activeFormattingIndexOf(id:int) {
    for int i = activeFormatting.length - 1, i >= 0, i-- {
        if activeFormatting[i] == id { return i }
    }
    return -1
}

// The last entry with this tag name, searching back to the nearest
// marker.
int func activeFormattingFind(tag:text) {
    for int i = activeFormatting.length - 1, i >= 0, i-- {
        int e = activeFormatting[i]
        if e == AFE_MARKER { return -1 }
        if tagOf(e) == tag { return i }
    }
    return -1
}

// Clones an element: the same tag and attributes, no children.
int func cloneElement(id:int) {
    Node el = newElement(nodeRegistry[id].tag)
    arr[text] names = nodeRegistry[id].present.keys()
    for int i = 0, i < names.length, i++ {
        text v = nodeRegistry[id].attrs[names[i]]
        if v == null { v = '' }
        el.attrs[names[i]] = v
        el.present[names[i]] = true
    }
    el.ns = nodeRegistry[id].ns
    return el.id
}

void func reconstructActiveFormatting() {
    int count = activeFormatting.length
    if count == 0 { return }
    int last = activeFormatting[count - 1]
    if last == AFE_MARKER || stackIndexOf(last) >= 0 { return }
    int i = count - 1
    while i > 0 {
        int prev = activeFormatting[i - 1]
        if prev == AFE_MARKER || stackIndexOf(prev) >= 0 { break }
        i--
    }
    while i < count {
        int entry = activeFormatting[i]
        int fresh = cloneElement(entry)
        findInsertionPlace(0)
        insertAtPlace(fresh)
        pushOpenElement(fresh)
        activeFormatting[i] = fresh
        i++
    }
}

// ---- the adoption agency algorithm -----------------------------------------------

// True when the end tag was handled; false when the caller should fall
// through to the "any other end tag" steps.
bool func adoptionAgency(subject:text) {
    int current = currentNodeId()
    if tagOf(current) == subject && activeFormattingIndexOf(current) < 0 {
        popOpenElement()
        return true
    }
    for int outer = 0, outer < 8, outer++ {
        int formattingIndex = activeFormattingFind(subject)
        if formattingIndex < 0 { return false }
        int formattingElement = activeFormatting[formattingIndex]
        int stackIndex = stackIndexOf(formattingElement)
        if stackIndex < 0 {
            activeFormatting.splice(formattingIndex, 1)
            return true
        }
        if !hasElementInScope(subject, SCOPE_DEFAULT) { return true }
        // the furthest block: the nearest special element below the
        // formatting element on the stack
        int furthestBlock = -1
        for int i = stackIndex + 1, i < openElements.length, i++ {
            if isSpecialElement(tagOf(openElements[i])) {
                furthestBlock = i
                break
            }
        }
        if furthestBlock < 0 {
            while openElements.length > stackIndex { popOpenElement() }
            activeFormatting.splice(formattingIndex, 1)
            return true
        }
        int commonAncestor = openElements[stackIndex - 1]
        int bookmark = formattingIndex
        int blockId = openElements[furthestBlock]
        int nodeIndex = furthestBlock
        int nodeId = blockId
        int lastNodeId = blockId
        for int inner = 1, inner <= 64, inner++ {
            nodeIndex--
            if nodeIndex < 0 { break }
            nodeId = openElements[nodeIndex]
            if nodeId == formattingElement { break }
            int afeIndex = activeFormattingIndexOf(nodeId)
            if inner > 3 && afeIndex >= 0 {
                activeFormatting.splice(afeIndex, 1)
                if afeIndex < bookmark { bookmark-- }
                afeIndex = -1
            }
            if afeIndex < 0 {
                openElements.splice(nodeIndex, 1)
                continue
            }
            int fresh = cloneElement(nodeId)
            activeFormatting[afeIndex] = fresh
            openElements[nodeIndex] = fresh
            nodeId = fresh
            if lastNodeId == blockId { bookmark = afeIndex + 1 }
            appendNode(nodeId, lastNodeId)
            lastNodeId = nodeId
        }
        // place the last node at the appropriate place inside the
        // common ancestor, honouring foster parenting
        bool savedFoster = fosterParenting
        text ancestorTag = htmlTagOf(commonAncestor)
        if ancestorTag == 'table' || ancestorTag == 'tbody' || ancestorTag == 'tfoot'
            || ancestorTag == 'thead' || ancestorTag == 'tr' {
            fosterParenting = true
        }
        findInsertionPlace(commonAncestor)
        insertAtPlace(lastNodeId)
        fosterParenting = savedFoster
        // not `newElement`: a local may not share a global function's
        // name -- the function wins and the program miscompiles
        // (FINDINGS.md, "a name cannot shadow a function")
        int replacement = cloneElement(formattingElement)
        // move every child of the furthest block into the new element
        while nodeRegistry[blockId].children.length > 0 {
            appendNode(replacement, nodeRegistry[blockId].children[0].id)
        }
        appendNode(blockId, replacement)
        int oldIndex = activeFormattingIndexOf(formattingElement)
        if oldIndex >= 0 {
            activeFormatting.splice(oldIndex, 1)
            if oldIndex < bookmark { bookmark-- }
        }
        if bookmark > activeFormatting.length { bookmark = activeFormatting.length }
        arr[int] one = [replacement]
        activeFormatting.splice(bookmark, 0, one)
        int oldStack = stackIndexOf(formattingElement)
        if oldStack >= 0 { openElements.splice(oldStack, 1) }
        int blockIndex = stackIndexOf(blockId)
        arr[int] oneStack = [replacement]
        openElements.splice(blockIndex + 1, 0, oneStack)
    }
    return true
}

// ---- resetting the insertion mode ---------------------------------------------------

void func resetInsertionModeAppropriately() {
    for int i = openElements.length - 1, i >= 0, i-- {
        bool last = i == 0
        text t = tagOf(openElements[i])
        if (t == 'td' || t == 'th') && !last {
            insertionMode = IM_IN_CELL
            return
        }
        if t == 'tr' {
            insertionMode = IM_IN_ROW
            return
        }
        if t == 'tbody' || t == 'thead' || t == 'tfoot' {
            insertionMode = IM_IN_TABLE_BODY
            return
        }
        if t == 'caption' {
            insertionMode = IM_IN_CAPTION
            return
        }
        if t == 'colgroup' {
            insertionMode = IM_IN_COLUMN_GROUP
            return
        }
        if t == 'table' {
            insertionMode = IM_IN_TABLE
            return
        }
        if t == 'template' {
            if templateModes.length > 0 { insertionMode = templateModes[templateModes.length - 1] }
            return
        }
        if t == 'head' && !last {
            insertionMode = IM_IN_HEAD
            return
        }
        if t == 'body' {
            insertionMode = IM_IN_BODY
            return
        }
        if t == 'frameset' {
            insertionMode = IM_IN_FRAMESET
            return
        }
        if t == 'html' {
            insertionMode = headElementId == 0 ? IM_BEFORE_HEAD : IM_AFTER_HEAD
            return
        }
        if last {
            insertionMode = IM_IN_BODY
            return
        }
    }
    insertionMode = IM_IN_BODY
}

// ---- small helpers used by the modes --------------------------------------------------

void func closePElement() {
    generateImpliedEndTags('p')
    popUntilIncludingTag('p')
}

bool func isWhitespaceText(t:text) {
    ascii a = t.toAscii()
    if a == null { return false }
    return asciiIsBlank(a)
}

// Splits a character run into its leading whitespace and the rest, so a
// mode can treat the two differently. Results in globals.
text leadingSpace = ''
text remainingText = ''

void func splitLeadingWhitespace(t:text) {
    ascii a = t.toAscii()
    if a == null {
        leadingSpace = ''
        remainingText = t
        return
    }
    int i = 0
    while i < a.length && isSpaceCode(a.charCodeAt(i)) { i++ }
    leadingSpace = a.slice(0, i).toText()
    remainingText = a.slice(i, a.length).toText()
}

void func clearStackBackToTableContext() {
    while openElements.length > 0 {
        text t = currentTag()
        if t == 'table' || t == 'template' || t == 'html' { return }
        popOpenElement()
    }
}

void func clearStackBackToTableBodyContext() {
    while openElements.length > 0 {
        text t = currentTag()
        if t == 'tbody' || t == 'tfoot' || t == 'thead' || t == 'template' || t == 'html' { return }
        popOpenElement()
    }
}

void func clearStackBackToTableRowContext() {
    while openElements.length > 0 {
        text t = currentTag()
        if t == 'tr' || t == 'template' || t == 'html' { return }
        popOpenElement()
    }
}

void func closeCell() {
    generateImpliedEndTags('')
    while openElements.length > 0 {
        text t = currentTag()
        popOpenElement()
        if t == 'td' || t == 'th' { break }
    }
    clearActiveFormattingToMarker()
    insertionMode = IM_IN_ROW
}

// Switches the tokenizer into a raw-text or RCDATA state for this
// element and remembers where to come back to.
void func parseRawText(tok:Token, state:int) {
    insertElementForToken(tok)
    tokenizerSetState(state, tok.name)
    originalInsertionMode = insertionMode
    insertionMode = IM_TEXT
}

// ---- the modes ------------------------------------------------------------------------

// Forward declaration order matters not in Festina: every function is
// hoisted, so the modes can call each other freely.

void func processToken(tok:Token) {
    if useForeignRules(tok) {
        processTokenForeign(tok)
        return
    }
    dispatchToken(tok, insertionMode)
}

void func dispatchToken(tok:Token, mode:int) {
    if mode == IM_INITIAL { modeInitial(tok) }
    else if mode == IM_BEFORE_HTML { modeBeforeHtml(tok) }
    else if mode == IM_BEFORE_HEAD { modeBeforeHead(tok) }
    else if mode == IM_IN_HEAD { modeInHead(tok) }
    else if mode == IM_IN_HEAD_NOSCRIPT { modeInHeadNoscript(tok) }
    else if mode == IM_AFTER_HEAD { modeAfterHead(tok) }
    else if mode == IM_IN_BODY { modeInBody(tok) }
    else if mode == IM_TEXT { modeText(tok) }
    else if mode == IM_IN_TABLE { modeInTable(tok) }
    else if mode == IM_IN_TABLE_TEXT { modeInTableText(tok) }
    else if mode == IM_IN_CAPTION { modeInCaption(tok) }
    else if mode == IM_IN_COLUMN_GROUP { modeInColumnGroup(tok) }
    else if mode == IM_IN_TABLE_BODY { modeInTableBody(tok) }
    else if mode == IM_IN_ROW { modeInRow(tok) }
    else if mode == IM_IN_CELL { modeInCell(tok) }
    else if mode == IM_IN_TEMPLATE { modeInTemplate(tok) }
    else if mode == IM_AFTER_BODY { modeAfterBody(tok) }
    else if mode == IM_IN_FRAMESET { modeInFrameset(tok) }
    else if mode == IM_AFTER_FRAMESET { modeAfterFrameset(tok) }
    else if mode == IM_AFTER_AFTER_BODY { modeAfterAfterBody(tok) }
    else if mode == IM_AFTER_AFTER_FRAMESET { modeAfterAfterFrameset(tok) }
}

void func modeInitial(tok:Token) {
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, documentId)
        return
    }
    if tok.kind == TOK_DOCTYPE {
        Node dt = newDoctype(tok.name, tok.publicId, tok.systemId, tok.hasExternalId)
        appendNode(documentId, dt.id)
        quirksMode = doctypeMeansQuirks(tok)
        insertionMode = IM_BEFORE_HTML
        return
    }
    // no doctype at all
    quirksMode = true
    insertionMode = IM_BEFORE_HTML
    dispatchToken(tok, IM_BEFORE_HTML)
}

void func modeBeforeHtml(tok:Token) {
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, documentId)
        return
    }
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_START && tok.name == 'html' {
        int id = createElementForToken(tok)
        appendNode(documentId, id)
        pushOpenElement(id)
        insertionMode = IM_BEFORE_HEAD
        return
    }
    if tok.kind == TOK_END && tok.name != 'head' && tok.name != 'body' && tok.name != 'html' && tok.name != 'br' {
        return
    }
    Node html = newElement('html')
    appendNode(documentId, html.id)
    pushOpenElement(html.id)
    insertionMode = IM_BEFORE_HEAD
    dispatchToken(tok, IM_BEFORE_HEAD)
}

void func modeBeforeHead(tok:Token) {
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_START && tok.name == 'html' {
        modeInBody(tok)
        return
    }
    if tok.kind == TOK_START && tok.name == 'head' {
        headElementId = insertElementForToken(tok)
        insertionMode = IM_IN_HEAD
        return
    }
    if tok.kind == TOK_END && tok.name != 'head' && tok.name != 'body' && tok.name != 'html' && tok.name != 'br' {
        return
    }
    Token fake = makeToken(TOK_START)
    fake.name = 'head'
    headElementId = insertElementForToken(fake)
    insertionMode = IM_IN_HEAD
    dispatchToken(tok, IM_IN_HEAD)
}

void func modeInHead(tok:Token) {
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if leadingSpace != '' { insertCharacters(leadingSpace) }
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'html' {
            modeInBody(tok)
            return
        }
        if n == 'base' || n == 'basefont' || n == 'bgsound' || n == 'link' || n == 'meta' {
            insertElementForToken(tok)
            popOpenElement()
            return
        }
        if n == 'title' {
            parseRawText(tok, TS_RCDATA)
            return
        }
        if n == 'noframes' || n == 'style' {
            parseRawText(tok, TS_RAWTEXT)
            return
        }
        if n == 'noscript' {
            // the scripting flag is disabled in this browser, so a
            // noscript element's content is ordinary markup
            insertElementForToken(tok)
            insertionMode = IM_IN_HEAD_NOSCRIPT
            return
        }
        if n == 'script' {
            parseRawText(tok, TS_SCRIPT_DATA)
            return
        }
        if n == 'template' {
            int tid = insertElementForToken(tok)
            Node frag = newTemplateContent()
            appendNode(tid, frag.id)
            nodeRegistry[tid].contentId = frag.id
            activeFormatting.push(AFE_MARKER)
            insertionMode = IM_IN_TEMPLATE
            templateModes.push(IM_IN_TEMPLATE)
            templateFramesetOk.push(framesetOk)
            return
        }
        if n == 'head' { return }
    }
    if tok.kind == TOK_END {
        text n = tok.name
        if n == 'head' {
            popOpenElement()
            insertionMode = IM_AFTER_HEAD
            return
        }
        if n == 'template' {
            if !stackHasTag('template') { return }
            generateImpliedEndTagsThoroughly()
            popUntilIncludingTag('template')
            clearActiveFormattingToMarker()
            if templateModes.length > 0 { templateModes.pop() }
            if templateFramesetOk.length > 0 { framesetOk = templateFramesetOk.pop() }
            resetInsertionModeAppropriately()
            return
        }
        if n != 'body' && n != 'html' && n != 'br' { return }
    }
    popOpenElement()
    insertionMode = IM_AFTER_HEAD
    dispatchToken(tok, IM_AFTER_HEAD)
}

void func modeInHeadNoscript(tok:Token) {
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_START && tok.name == 'html' {
        modeInBody(tok)
        return
    }
    if tok.kind == TOK_END && tok.name == 'noscript' {
        popOpenElement()
        insertionMode = IM_IN_HEAD
        return
    }
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if leadingSpace != '' { insertCharacters(leadingSpace) }
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_COMMENT {
        modeInHead(tok)
        return
    }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'basefont' || n == 'bgsound' || n == 'link' || n == 'meta' || n == 'noframes' || n == 'style' {
            modeInHead(tok)
            return
        }
        if n == 'head' || n == 'noscript' { return }
    }
    if tok.kind == TOK_END && tok.name != 'br' { return }
    popOpenElement()
    insertionMode = IM_IN_HEAD
    dispatchToken(tok, IM_IN_HEAD)
}

void func modeAfterHead(tok:Token) {
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if leadingSpace != '' { insertCharacters(leadingSpace) }
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'html' {
            modeInBody(tok)
            return
        }
        if n == 'body' {
            insertElementForToken(tok)
            framesetOk = false
            insertionMode = IM_IN_BODY
            return
        }
        if n == 'frameset' {
            insertElementForToken(tok)
            insertionMode = IM_IN_FRAMESET
            return
        }
        if n == 'base' || n == 'basefont' || n == 'bgsound' || n == 'link' || n == 'meta'
            || n == 'noframes' || n == 'script' || n == 'style' || n == 'template' || n == 'title' {
            if headElementId > 0 { pushOpenElement(headElementId) }
            modeInHead(tok)
            int idx = stackIndexOf(headElementId)
            if idx >= 0 && headElementId > 0 { openElements.splice(idx, 1) }
            return
        }
        if n == 'head' { return }
    }
    if tok.kind == TOK_END {
        text n = tok.name
        if n == 'template' {
            modeInHead(tok)
            return
        }
        if n != 'body' && n != 'html' && n != 'br' { return }
    }
    Token fake = makeToken(TOK_START)
    fake.name = 'body'
    insertElementForToken(fake)
    insertionMode = IM_IN_BODY
    dispatchToken(tok, IM_IN_BODY)
}

void func modeText(tok:Token) {
    if tok.kind == TOK_TEXT {
        insertCharacters(tok.data)
        return
    }
    if tok.kind == TOK_EOF {
        popOpenElement()
        insertionMode = originalInsertionMode
        dispatchToken(tok, insertionMode)
        return
    }
    if tok.kind == TOK_END {
        popOpenElement()
        insertionMode = originalInsertionMode
        return
    }
}

// The body of "in body" is long because the standard's is: it is the
// mode that has a rule for nearly every tag name.
void func modeInBody(tok:Token) {
    if tok.kind == TOK_TEXT {
        reconstructActiveFormatting()
        insertCharacters(tok.data)
        if !isWhitespaceText(tok.data) { framesetOk = false }
        return
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_EOF {
        if templateModes.length > 0 {
            modeInTemplate(tok)
            return
        }
        parserDone = true
        return
    }
    if tok.kind == TOK_START { inBodyStartTag(tok) }
    else if tok.kind == TOK_END { inBodyEndTag(tok) }
}

void func inBodyStartTag(tok:Token) {
    text n = tok.name
    if n == 'html' {
        if stackHasTag('template') { return }
        mergeAttributesInto(openElements[0], tok)
        return
    }
    if n == 'base' || n == 'basefont' || n == 'bgsound' || n == 'link' || n == 'meta'
        || n == 'noframes' || n == 'script' || n == 'style' || n == 'template' || n == 'title' {
        // a template in the body makes a later frameset impossible; one
        // in the head does not
        if n == 'template' { framesetOk = false }
        modeInHead(tok)
        return
    }
    if n == 'body' {
        if openElements.length < 2 || tagOf(openElements[1]) != 'body' { return }
        if stackHasTag('template') { return }
        framesetOk = false
        mergeAttributesInto(openElements[1], tok)
        return
    }
    if n == 'frameset' {
        if openElements.length < 2 || tagOf(openElements[1]) != 'body' { return }
        if !framesetOk { return }
        int bodyId = openElements[1]
        detachNode(bodyId)
        while openElements.length > 1 { popOpenElement() }
        insertElementForToken(tok)
        insertionMode = IM_IN_FRAMESET
        return
    }
    if n == 'address' || n == 'article' || n == 'aside' || n == 'blockquote' || n == 'center'
        || n == 'details' || n == 'dialog' || n == 'dir' || n == 'div' || n == 'dl'
        || n == 'fieldset' || n == 'figcaption' || n == 'figure' || n == 'footer'
        || n == 'header' || n == 'hgroup' || n == 'main' || n == 'menu' || n == 'nav'
        || n == 'ol' || n == 'p' || n == 'search' || n == 'section' || n == 'summary' || n == 'ul' {
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        insertElementForToken(tok)
        return
    }
    if isHeadingTag(n) {
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        if isHeadingTag(currentTag()) { popOpenElement() }
        insertElementForToken(tok)
        return
    }
    if n == 'pre' || n == 'listing' {
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        insertElementForToken(tok)
        skipNextNewline = true
        framesetOk = false
        return
    }
    if n == 'form' {
        bool hasTemplate = stackHasTag('template')
        if formElementId > 0 && !hasTemplate { return }
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        int id = insertElementForToken(tok)
        if !hasTemplate { formElementId = id }
        return
    }
    if n == 'li' {
        framesetOk = false
        for int i = openElements.length - 1, i >= 0, i-- {
            text t = tagOf(openElements[i])
            if t == 'li' {
                generateImpliedEndTags('li')
                popUntilIncludingTag('li')
                break
            }
            if isSpecialElement(t) && t != 'address' && t != 'div' && t != 'p' { break }
        }
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        insertElementForToken(tok)
        return
    }
    if n == 'dd' || n == 'dt' {
        framesetOk = false
        for int i = openElements.length - 1, i >= 0, i-- {
            text t = tagOf(openElements[i])
            if t == 'dd' || t == 'dt' {
                generateImpliedEndTags(t)
                popUntilIncludingTag(t)
                break
            }
            if isSpecialElement(t) && t != 'address' && t != 'div' && t != 'p' { break }
        }
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        insertElementForToken(tok)
        return
    }
    if n == 'plaintext' {
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        insertElementForToken(tok)
        tokenizerSetState(TS_PLAINTEXT, '')
        return
    }
    if n == 'button' {
        if hasElementInScope('button', SCOPE_DEFAULT) {
            generateImpliedEndTags('')
            popUntilIncludingTag('button')
        }
        reconstructActiveFormatting()
        insertElementForToken(tok)
        framesetOk = false
        return
    }
    if n == 'a' {
        int existing = activeFormattingFind('a')
        if existing >= 0 {
            int id = activeFormatting[existing]
            adoptionAgency('a')
            int stillActive = activeFormattingIndexOf(id)
            if stillActive >= 0 { activeFormatting.splice(stillActive, 1) }
            int stillOpen = stackIndexOf(id)
            if stillOpen >= 0 { openElements.splice(stillOpen, 1) }
        }
        reconstructActiveFormatting()
        int id = insertElementForToken(tok)
        pushActiveFormatting(id)
        return
    }
    if isFormattingElement(n) && n != 'nobr' {
        reconstructActiveFormatting()
        int id = insertElementForToken(tok)
        pushActiveFormatting(id)
        return
    }
    if n == 'nobr' {
        reconstructActiveFormatting()
        if hasElementInScope('nobr', SCOPE_DEFAULT) {
            adoptionAgency('nobr')
            reconstructActiveFormatting()
        }
        int id = insertElementForToken(tok)
        pushActiveFormatting(id)
        return
    }
    if n == 'applet' || n == 'marquee' || n == 'object' {
        reconstructActiveFormatting()
        insertElementForToken(tok)
        activeFormatting.push(AFE_MARKER)
        framesetOk = false
        return
    }
    if n == 'table' {
        // in quirks mode a table start tag does not close an open p
        if !quirksMode && hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        insertElementForToken(tok)
        framesetOk = false
        insertionMode = IM_IN_TABLE
        return
    }
    if n == 'area' || n == 'br' || n == 'embed' || n == 'img' || n == 'keygen' || n == 'wbr' {
        reconstructActiveFormatting()
        insertElementForToken(tok)
        popOpenElement()
        framesetOk = false
        return
    }
    if n == 'input' {
        if hasElementInScope('select', SCOPE_DEFAULT) {
            popUntilIncludingTag('select')
            resetInsertionModeAppropriately()
            dispatchToken(tok, insertionMode)
            return
        }
        reconstructActiveFormatting()
        insertElementForToken(tok)
        popOpenElement()
        text ty = tok.attrs['type']
        if ty == null || textLower(ty) != 'hidden' { framesetOk = false }
        return
    }
    if n == 'param' || n == 'source' || n == 'track' {
        insertElementForToken(tok)
        popOpenElement()
        return
    }
    if n == 'hr' {
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        // an hr ends an open option and optgroup, so it separates the
        // groups of a select rather than joining one
        if currentTag() == 'option' { popOpenElement() }
        if currentTag() == 'optgroup' { popOpenElement() }
        insertElementForToken(tok)
        popOpenElement()
        framesetOk = false
        return
    }
    if n == 'textarea' {
        insertElementForToken(tok)
        skipNextNewline = true
        tokenizerSetState(TS_RCDATA, tok.name)
        originalInsertionMode = insertionMode
        framesetOk = false
        insertionMode = IM_TEXT
        return
    }
    if n == 'xmp' {
        if hasElementInScope('p', SCOPE_BUTTON) { closePElement() }
        reconstructActiveFormatting()
        framesetOk = false
        parseRawText(tok, TS_RAWTEXT)
        return
    }
    if n == 'iframe' {
        framesetOk = false
        parseRawText(tok, TS_RAWTEXT)
        return
    }
    if n == 'noembed' {
        parseRawText(tok, TS_RAWTEXT)
        return
    }
    if n == 'noscript' {
        // scripting is disabled here, so noscript's contents are markup
        reconstructActiveFormatting()
        insertElementForToken(tok)
        return
    }
    if n == 'select' {
        // a select inside a select closes the outer one and is dropped;
        // otherwise select content is ordinary body content
        if hasElementInScope('select', SCOPE_DEFAULT) {
            popUntilIncludingTag('select')
            resetInsertionModeAppropriately()
            return
        }
        reconstructActiveFormatting()
        insertElementForToken(tok)
        framesetOk = false
        return
    }
    if n == 'option' {
        if currentTag() == 'option' { popOpenElement() }
        reconstructActiveFormatting()
        insertElementForToken(tok)
        return
    }
    if n == 'optgroup' {
        if currentTag() == 'option' { popOpenElement() }
        if currentTag() == 'optgroup' { popOpenElement() }
        reconstructActiveFormatting()
        insertElementForToken(tok)
        return
    }
    if n == 'rb' || n == 'rtc' {
        if hasElementInScope('ruby', SCOPE_DEFAULT) { generateImpliedEndTags('') }
        insertElementForToken(tok)
        return
    }
    if n == 'rp' || n == 'rt' {
        if hasElementInScope('ruby', SCOPE_DEFAULT) { generateImpliedEndTags('rtc') }
        insertElementForToken(tok)
        return
    }
    if n == 'math' || n == 'svg' {
        reconstructActiveFormatting()
        insertForeignElement(tok, n == 'svg' ? NS_SVG : NS_MATHML)
        if tok.selfClosing { popOpenElement() }
        return
    }
    if n == 'caption' || n == 'col' || n == 'colgroup' || n == 'frame' || n == 'head'
        || n == 'tbody' || n == 'td' || n == 'tfoot' || n == 'th' || n == 'thead' || n == 'tr' {
        return
    }
    reconstructActiveFormatting()
    insertElementForToken(tok)
}

void func mergeAttributesInto(id:int, tok:Token) {
    arr[text] names = tok.present.keys()
    for int i = 0, i < names.length, i++ {
        if nodeRegistry[id].present[names[i]] == true { continue }
        text v = tok.attrs[names[i]]
        if v == null { v = '' }
        nodeRegistry[id].attrs[names[i]] = v
        nodeRegistry[id].present[names[i]] = true
        if isPresentationalAttr(names[i]) { nodeRegistry[id].hasPresHint = true }
    }
}

void func inBodyEndTag(tok:Token) {
    text n = tok.name
    if n == 'template' {
        modeInHead(tok)
        return
    }
    if n == 'body' || n == 'html' {
        if !hasElementInScope('body', SCOPE_DEFAULT) { return }
        insertionMode = IM_AFTER_BODY
        if n == 'html' { dispatchToken(tok, IM_AFTER_BODY) }
        return
    }
    if n == 'address' || n == 'article' || n == 'aside' || n == 'blockquote' || n == 'button'
        || n == 'center' || n == 'details' || n == 'dialog' || n == 'dir' || n == 'div'
        || n == 'dl' || n == 'fieldset' || n == 'figcaption' || n == 'figure' || n == 'footer'
        || n == 'header' || n == 'hgroup' || n == 'listing' || n == 'main' || n == 'menu'
        || n == 'nav' || n == 'ol' || n == 'pre' || n == 'search' || n == 'section'
        || n == 'summary' || n == 'ul' {
        if !hasElementInScope(n, SCOPE_DEFAULT) { return }
        generateImpliedEndTags('')
        popUntilIncludingTag(n)
        return
    }
    if n == 'form' {
        if !stackHasTag('template') {
            int id = formElementId
            formElementId = 0
            if id == 0 || stackIndexOf(id) < 0 { return }
            generateImpliedEndTags('')
            int idx = stackIndexOf(id)
            if idx >= 0 { openElements.splice(idx, 1) }
            return
        }
        if !hasElementInScope('form', SCOPE_DEFAULT) { return }
        generateImpliedEndTags('')
        popUntilIncludingTag('form')
        return
    }
    if n == 'select' {
        if !hasElementInScope('select', SCOPE_DEFAULT) { return }
        popUntilIncludingTag('select')
        resetInsertionModeAppropriately()
        return
    }
    if n == 'p' {
        if !hasElementInScope('p', SCOPE_BUTTON) {
            Token fake = makeToken(TOK_START)
            fake.name = 'p'
            insertElementForToken(fake)
        }
        closePElement()
        return
    }
    if n == 'li' {
        if !hasElementInScope('li', SCOPE_LIST_ITEM) { return }
        generateImpliedEndTags('li')
        popUntilIncludingTag('li')
        return
    }
    if n == 'dd' || n == 'dt' {
        if !hasElementInScope(n, SCOPE_DEFAULT) { return }
        generateImpliedEndTags(n)
        popUntilIncludingTag(n)
        return
    }
    if isHeadingTag(n) {
        bool any = hasElementInScope('h1', SCOPE_DEFAULT) || hasElementInScope('h2', SCOPE_DEFAULT)
            || hasElementInScope('h3', SCOPE_DEFAULT) || hasElementInScope('h4', SCOPE_DEFAULT)
            || hasElementInScope('h5', SCOPE_DEFAULT) || hasElementInScope('h6', SCOPE_DEFAULT)
        if !any { return }
        generateImpliedEndTags('')
        while openElements.length > 0 {
            text t = currentTag()
            popOpenElement()
            if isHeadingTag(t) { break }
        }
        return
    }
    if isFormattingElement(n) {
        if adoptionAgency(n) { return }
        inBodyAnyOtherEndTag(n)
        return
    }
    if n == 'applet' || n == 'marquee' || n == 'object' {
        if !hasElementInScope(n, SCOPE_DEFAULT) { return }
        generateImpliedEndTags('')
        popUntilIncludingTag(n)
        clearActiveFormattingToMarker()
        return
    }
    if n == 'br' {
        Token fake = makeToken(TOK_START)
        fake.name = 'br'
        inBodyStartTag(fake)
        return
    }
    inBodyAnyOtherEndTag(n)
}

void func inBodyAnyOtherEndTag(n:text) {
    for int i = openElements.length - 1, i >= 0, i-- {
        text t = tagOf(openElements[i])
        if t == n {
            generateImpliedEndTags(n)
            while openElements.length > i { popOpenElement() }
            return
        }
        if isSpecialElement(t) { return }
    }
}

void func modeInTable(tok:Token) {
    if tok.kind == TOK_TEXT {
        text t = currentTag()
        if t == 'table' || t == 'tbody' || t == 'template' || t == 'tfoot' || t == 'thead' || t == 'tr' {
            pendingTableText = []
            pendingTableTextNonSpace = false
            originalInsertionMode = insertionMode
            insertionMode = IM_IN_TABLE_TEXT
            dispatchToken(tok, IM_IN_TABLE_TEXT)
            return
        }
        fosterParenting = true
        modeInBody(tok)
        fosterParenting = false
        return
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_EOF {
        modeInBody(tok)
        return
    }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'caption' {
            clearStackBackToTableContext()
            activeFormatting.push(AFE_MARKER)
            insertElementForToken(tok)
            insertionMode = IM_IN_CAPTION
            return
        }
        if n == 'colgroup' {
            clearStackBackToTableContext()
            insertElementForToken(tok)
            insertionMode = IM_IN_COLUMN_GROUP
            return
        }
        if n == 'col' {
            clearStackBackToTableContext()
            Token fake = makeToken(TOK_START)
            fake.name = 'colgroup'
            insertElementForToken(fake)
            insertionMode = IM_IN_COLUMN_GROUP
            dispatchToken(tok, IM_IN_COLUMN_GROUP)
            return
        }
        if n == 'tbody' || n == 'tfoot' || n == 'thead' {
            clearStackBackToTableContext()
            insertElementForToken(tok)
            insertionMode = IM_IN_TABLE_BODY
            return
        }
        if n == 'td' || n == 'th' || n == 'tr' {
            clearStackBackToTableContext()
            Token fake = makeToken(TOK_START)
            fake.name = 'tbody'
            insertElementForToken(fake)
            insertionMode = IM_IN_TABLE_BODY
            dispatchToken(tok, IM_IN_TABLE_BODY)
            return
        }
        if n == 'table' {
            if !hasElementInScope('table', SCOPE_TABLE) { return }
            popUntilIncludingTag('table')
            resetInsertionModeAppropriately()
            dispatchToken(tok, insertionMode)
            return
        }
        if n == 'style' || n == 'script' || n == 'template' {
            modeInHead(tok)
            return
        }
        if n == 'input' {
            text ty = tok.attrs['type']
            if ty != null && textLower(ty) == 'hidden' {
                insertElementForToken(tok)
                popOpenElement()
                return
            }
        }
        if n == 'form' {
            bool hasTemplate = stackHasTag('template')
            if formElementId > 0 && !hasTemplate { return }
            int id = insertElementForToken(tok)
            if !hasTemplate { formElementId = id }
            popOpenElement()
            return
        }
    }
    if tok.kind == TOK_END {
        text n = tok.name
        if n == 'table' {
            if !hasElementInScope('table', SCOPE_TABLE) { return }
            popUntilIncludingTag('table')
            resetInsertionModeAppropriately()
            return
        }
        if n == 'body' || n == 'caption' || n == 'col' || n == 'colgroup' || n == 'html'
            || n == 'tbody' || n == 'td' || n == 'tfoot' || n == 'th' || n == 'thead' || n == 'tr' {
            return
        }
        if n == 'template' {
            modeInHead(tok)
            return
        }
    }
    // anything else: foster parenting
    fosterParenting = true
    modeInBody(tok)
    fosterParenting = false
}

void func modeInTableText(tok:Token) {
    if tok.kind == TOK_TEXT {
        pendingTableText.push(tok.data)
        if !isWhitespaceText(tok.data) { pendingTableTextNonSpace = true }
        return
    }
    text joined = pendingTableText.join('')
    pendingTableText = []
    if pendingTableTextNonSpace {
        Token fake = makeToken(TOK_TEXT)
        fake.data = joined
        fosterParenting = true
        modeInBody(fake)
        fosterParenting = false
    } else if joined != '' {
        insertCharacters(joined)
    }
    pendingTableTextNonSpace = false
    insertionMode = originalInsertionMode
    dispatchToken(tok, insertionMode)
}

void func modeInCaption(tok:Token) {
    if tok.kind == TOK_END && tok.name == 'caption' {
        if !hasElementInScope('caption', SCOPE_TABLE) { return }
        generateImpliedEndTags('')
        popUntilIncludingTag('caption')
        clearActiveFormattingToMarker()
        insertionMode = IM_IN_TABLE
        return
    }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'caption' || n == 'col' || n == 'colgroup' || n == 'tbody' || n == 'td'
            || n == 'tfoot' || n == 'th' || n == 'thead' || n == 'tr' {
            if !hasElementInScope('caption', SCOPE_TABLE) { return }
            generateImpliedEndTags('')
            popUntilIncludingTag('caption')
            clearActiveFormattingToMarker()
            insertionMode = IM_IN_TABLE
            dispatchToken(tok, IM_IN_TABLE)
            return
        }
    }
    if tok.kind == TOK_END && tok.name == 'table' {
        if !hasElementInScope('caption', SCOPE_TABLE) { return }
        generateImpliedEndTags('')
        popUntilIncludingTag('caption')
        clearActiveFormattingToMarker()
        insertionMode = IM_IN_TABLE
        dispatchToken(tok, IM_IN_TABLE)
        return
    }
    if tok.kind == TOK_END {
        text n = tok.name
        if n == 'body' || n == 'col' || n == 'colgroup' || n == 'html' || n == 'tbody'
            || n == 'td' || n == 'tfoot' || n == 'th' || n == 'thead' || n == 'tr' {
            return
        }
    }
    modeInBody(tok)
}

void func modeInColumnGroup(tok:Token) {
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if leadingSpace != '' { insertCharacters(leadingSpace) }
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'html' {
            modeInBody(tok)
            return
        }
        if n == 'col' {
            insertElementForToken(tok)
            popOpenElement()
            return
        }
        if n == 'template' {
            modeInHead(tok)
            return
        }
    }
    if tok.kind == TOK_END {
        text n = tok.name
        if n == 'colgroup' {
            if currentTag() != 'colgroup' { return }
            popOpenElement()
            insertionMode = IM_IN_TABLE
            return
        }
        if n == 'col' { return }
        if n == 'template' {
            modeInHead(tok)
            return
        }
    }
    if tok.kind == TOK_EOF {
        modeInBody(tok)
        return
    }
    if currentTag() != 'colgroup' { return }
    popOpenElement()
    insertionMode = IM_IN_TABLE
    dispatchToken(tok, IM_IN_TABLE)
}

void func modeInTableBody(tok:Token) {
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'tr' {
            clearStackBackToTableBodyContext()
            insertElementForToken(tok)
            insertionMode = IM_IN_ROW
            return
        }
        if n == 'td' || n == 'th' {
            clearStackBackToTableBodyContext()
            Token fake = makeToken(TOK_START)
            fake.name = 'tr'
            insertElementForToken(fake)
            insertionMode = IM_IN_ROW
            dispatchToken(tok, IM_IN_ROW)
            return
        }
        if n == 'caption' || n == 'col' || n == 'colgroup' || n == 'tbody' || n == 'tfoot' || n == 'thead' {
            if !hasAnyInTableScope('tbody', 'thead', 'tfoot') { return }
            clearStackBackToTableBodyContext()
            popOpenElement()
            insertionMode = IM_IN_TABLE
            dispatchToken(tok, IM_IN_TABLE)
            return
        }
    }
    if tok.kind == TOK_END {
        text n = tok.name
        if n == 'tbody' || n == 'tfoot' || n == 'thead' {
            if !hasElementInScope(n, SCOPE_TABLE) { return }
            clearStackBackToTableBodyContext()
            popOpenElement()
            insertionMode = IM_IN_TABLE
            return
        }
        if n == 'table' {
            if !hasAnyInTableScope('tbody', 'thead', 'tfoot') { return }
            clearStackBackToTableBodyContext()
            popOpenElement()
            insertionMode = IM_IN_TABLE
            dispatchToken(tok, IM_IN_TABLE)
            return
        }
        if n == 'body' || n == 'caption' || n == 'col' || n == 'colgroup' || n == 'html'
            || n == 'td' || n == 'th' || n == 'tr' {
            return
        }
    }
    modeInTable(tok)
}

void func modeInRow(tok:Token) {
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'td' || n == 'th' {
            clearStackBackToTableRowContext()
            insertElementForToken(tok)
            insertionMode = IM_IN_CELL
            activeFormatting.push(AFE_MARKER)
            return
        }
        if n == 'caption' || n == 'col' || n == 'colgroup' || n == 'tbody' || n == 'tfoot'
            || n == 'thead' || n == 'tr' {
            if !hasElementInScope('tr', SCOPE_TABLE) { return }
            clearStackBackToTableRowContext()
            popOpenElement()
            insertionMode = IM_IN_TABLE_BODY
            dispatchToken(tok, IM_IN_TABLE_BODY)
            return
        }
    }
    if tok.kind == TOK_END {
        text n = tok.name
        if n == 'tr' {
            if !hasElementInScope('tr', SCOPE_TABLE) { return }
            clearStackBackToTableRowContext()
            popOpenElement()
            insertionMode = IM_IN_TABLE_BODY
            return
        }
        if n == 'table' {
            if !hasElementInScope('tr', SCOPE_TABLE) { return }
            clearStackBackToTableRowContext()
            popOpenElement()
            insertionMode = IM_IN_TABLE_BODY
            dispatchToken(tok, IM_IN_TABLE_BODY)
            return
        }
        if n == 'tbody' || n == 'tfoot' || n == 'thead' {
            if !hasElementInScope(n, SCOPE_TABLE) { return }
            if !hasElementInScope('tr', SCOPE_TABLE) { return }
            clearStackBackToTableRowContext()
            popOpenElement()
            insertionMode = IM_IN_TABLE_BODY
            dispatchToken(tok, IM_IN_TABLE_BODY)
            return
        }
        if n == 'body' || n == 'caption' || n == 'col' || n == 'colgroup' || n == 'html'
            || n == 'td' || n == 'th' {
            return
        }
    }
    modeInTable(tok)
}

void func modeInCell(tok:Token) {
    if tok.kind == TOK_END {
        text n = tok.name
        if n == 'td' || n == 'th' {
            if !hasElementInScope(n, SCOPE_TABLE) { return }
            generateImpliedEndTags('')
            popUntilIncludingTag(n)
            clearActiveFormattingToMarker()
            insertionMode = IM_IN_ROW
            return
        }
        if n == 'body' || n == 'caption' || n == 'col' || n == 'colgroup' || n == 'html' { return }
        if n == 'table' || n == 'tbody' || n == 'tfoot' || n == 'thead' || n == 'tr' {
            if !hasElementInScope(n, SCOPE_TABLE) { return }
            closeCell()
            dispatchToken(tok, IM_IN_ROW)
            return
        }
    }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'caption' || n == 'col' || n == 'colgroup' || n == 'tbody' || n == 'td'
            || n == 'tfoot' || n == 'th' || n == 'thead' || n == 'tr' {
            if !hasAnyInTableScope('td', 'th', 'td') { return }
            closeCell()
            dispatchToken(tok, IM_IN_ROW)
            return
        }
    }
    modeInBody(tok)
}

void func modeInTemplate(tok:Token) {
    if tok.kind == TOK_TEXT || tok.kind == TOK_COMMENT || tok.kind == TOK_DOCTYPE {
        modeInBody(tok)
        return
    }
    if tok.kind == TOK_EOF {
        if !stackHasTag('template') {
            parserDone = true
            return
        }
        generateImpliedEndTagsThoroughly()
        popUntilIncludingTag('template')
        clearActiveFormattingToMarker()
        if templateModes.length > 0 { templateModes.pop() }
        if templateFramesetOk.length > 0 { framesetOk = templateFramesetOk.pop() }
        resetInsertionModeAppropriately()
        dispatchToken(tok, insertionMode)
        return
    }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'base' || n == 'basefont' || n == 'bgsound' || n == 'link' || n == 'meta'
            || n == 'noframes' || n == 'script' || n == 'style' || n == 'template' || n == 'title' {
            modeInHead(tok)
            return
        }
        int target = IM_IN_BODY
        if n == 'caption' || n == 'colgroup' || n == 'tbody' || n == 'tfoot' || n == 'thead' {
            target = IM_IN_TABLE
        } else if n == 'col' {
            target = IM_IN_COLUMN_GROUP
        } else if n == 'tr' {
            target = IM_IN_TABLE_BODY
        } else if n == 'td' || n == 'th' {
            target = IM_IN_ROW
        }
        if templateModes.length > 0 { templateModes[templateModes.length - 1] = target }
        insertionMode = target
        dispatchToken(tok, target)
        return
    }
    if tok.kind == TOK_END {
        if tok.name == 'template' { modeInHead(tok) }
        return
    }
}

void func modeAfterBody(tok:Token) {
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if leadingSpace != '' {
            Token space = makeToken(TOK_TEXT)
            space.data = leadingSpace
            modeInBody(space)
        }
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, openElements.length > 0 ? openElements[0] : 0)
        return
    }
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_EOF {
        parserDone = true
        return
    }
    if tok.kind == TOK_START && tok.name == 'html' {
        modeInBody(tok)
        return
    }
    if tok.kind == TOK_END && tok.name == 'html' {
        insertionMode = IM_AFTER_AFTER_BODY
        return
    }
    insertionMode = IM_IN_BODY
    dispatchToken(tok, IM_IN_BODY)
}

void func modeInFrameset(tok:Token) {
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if leadingSpace != '' { insertCharacters(leadingSpace) }
        return
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_EOF {
        parserDone = true
        return
    }
    if tok.kind == TOK_START {
        text n = tok.name
        if n == 'html' {
            modeInBody(tok)
            return
        }
        if n == 'frameset' {
            insertElementForToken(tok)
            return
        }
        if n == 'frame' {
            insertElementForToken(tok)
            popOpenElement()
            return
        }
        if n == 'noframes' {
            modeInHead(tok)
            return
        }
        return
    }
    if tok.kind == TOK_END && tok.name == 'frameset' {
        if currentTag() == 'html' { return }
        popOpenElement()
        if currentTag() != 'frameset' { insertionMode = IM_AFTER_FRAMESET }
        return
    }
}

void func modeAfterFrameset(tok:Token) {
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if leadingSpace != '' { insertCharacters(leadingSpace) }
        return
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_EOF {
        parserDone = true
        return
    }
    if tok.kind == TOK_START {
        if tok.name == 'html' { modeInBody(tok) }
        else if tok.name == 'noframes' { modeInHead(tok) }
        return
    }
    if tok.kind == TOK_END && tok.name == 'html' {
        insertionMode = IM_AFTER_AFTER_FRAMESET
        return
    }
}

void func modeAfterAfterBody(tok:Token) {
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, documentId)
        return
    }
    if tok.kind == TOK_DOCTYPE {
        modeInBody(tok)
        return
    }
    if tok.kind == TOK_EOF {
        parserDone = true
        return
    }
    if tok.kind == TOK_TEXT {
        splitLeadingWhitespace(tok.data)
        if leadingSpace != '' {
            Token space = makeToken(TOK_TEXT)
            space.data = leadingSpace
            modeInBody(space)
        }
        if remainingText == '' { return }
        tok.data = remainingText
    }
    if tok.kind == TOK_START && tok.name == 'html' {
        modeInBody(tok)
        return
    }
    insertionMode = IM_IN_BODY
    dispatchToken(tok, IM_IN_BODY)
}

void func modeAfterAfterFrameset(tok:Token) {
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, documentId)
        return
    }
    if tok.kind == TOK_EOF {
        parserDone = true
        return
    }
    if tok.kind == TOK_START {
        if tok.name == 'html' { modeInBody(tok) }
        else if tok.name == 'noframes' { modeInHead(tok) }
        return
    }
}


// ---- foreign content -------------------------------------------------------
//
// "The rules for parsing tokens in foreign content", with the name
// adjustments the standard applies when an SVG or MathML element comes
// out of an HTML tokenizer that has already lowercased everything.

map[text] svgTagAdjust = {
    'altglyph': 'altGlyph',
    'altglyphdef': 'altGlyphDef',
    'altglyphitem': 'altGlyphItem',
    'animatecolor': 'animateColor',
    'animatemotion': 'animateMotion',
    'animatetransform': 'animateTransform',
    'clippath': 'clipPath',
    'feblend': 'feBlend',
    'fecolormatrix': 'feColorMatrix',
    'fecomponenttransfer': 'feComponentTransfer',
    'fecomposite': 'feComposite',
    'feconvolvematrix': 'feConvolveMatrix',
    'fediffuselighting': 'feDiffuseLighting',
    'fedisplacementmap': 'feDisplacementMap',
    'fedistantlight': 'feDistantLight',
    'fedropshadow': 'feDropShadow',
    'feflood': 'feFlood',
    'fefunca': 'feFuncA',
    'fefuncb': 'feFuncB',
    'fefuncg': 'feFuncG',
    'fefuncr': 'feFuncR',
    'fegaussianblur': 'feGaussianBlur',
    'feimage': 'feImage',
    'femerge': 'feMerge',
    'femergenode': 'feMergeNode',
    'femorphology': 'feMorphology',
    'feoffset': 'feOffset',
    'fepointlight': 'fePointLight',
    'fespecularlighting': 'feSpecularLighting',
    'fespotlight': 'feSpotLight',
    'fetile': 'feTile',
    'feturbulence': 'feTurbulence',
    'foreignobject': 'foreignObject',
    'glyphref': 'glyphRef',
    'lineargradient': 'linearGradient',
    'radialgradient': 'radialGradient',
    'textpath': 'textPath',
}

map[text] svgAttrAdjust = {
    'attributename': 'attributeName',
    'attributetype': 'attributeType',
    'basefrequency': 'baseFrequency',
    'baseprofile': 'baseProfile',
    'calcmode': 'calcMode',
    'clippathunits': 'clipPathUnits',
    'diffuseconstant': 'diffuseConstant',
    'edgemode': 'edgeMode',
    'filterunits': 'filterUnits',
    'glyphref': 'glyphRef',
    'gradienttransform': 'gradientTransform',
    'gradientunits': 'gradientUnits',
    'kernelmatrix': 'kernelMatrix',
    'kernelunitlength': 'kernelUnitLength',
    'keypoints': 'keyPoints',
    'keysplines': 'keySplines',
    'keytimes': 'keyTimes',
    'lengthadjust': 'lengthAdjust',
    'limitingconeangle': 'limitingConeAngle',
    'markerheight': 'markerHeight',
    'markerunits': 'markerUnits',
    'markerwidth': 'markerWidth',
    'maskcontentunits': 'maskContentUnits',
    'maskunits': 'maskUnits',
    'numoctaves': 'numOctaves',
    'pathlength': 'pathLength',
    'patterncontentunits': 'patternContentUnits',
    'patterntransform': 'patternTransform',
    'patternunits': 'patternUnits',
    'pointsatx': 'pointsAtX',
    'pointsaty': 'pointsAtY',
    'pointsatz': 'pointsAtZ',
    'preservealpha': 'preserveAlpha',
    'preserveaspectratio': 'preserveAspectRatio',
    'primitiveunits': 'primitiveUnits',
    'refx': 'refX',
    'refy': 'refY',
    'repeatcount': 'repeatCount',
    'repeatdur': 'repeatDur',
    'requiredextensions': 'requiredExtensions',
    'requiredfeatures': 'requiredFeatures',
    'specularconstant': 'specularConstant',
    'specularexponent': 'specularExponent',
    'spreadmethod': 'spreadMethod',
    'startoffset': 'startOffset',
    'stddeviation': 'stdDeviation',
    'stitchtiles': 'stitchTiles',
    'surfacescale': 'surfaceScale',
    'systemlanguage': 'systemLanguage',
    'tablevalues': 'tableValues',
    'targetx': 'targetX',
    'targety': 'targetY',
    'textlength': 'textLength',
    'viewbox': 'viewBox',
    'viewtarget': 'viewTarget',
    'xchannelselector': 'xChannelSelector',
    'ychannelselector': 'yChannelSelector',
    'zoomandpan': 'zoomAndPan',
}

// Namespaced attributes, written the way the standard's serialization
// wants them: the namespace designator, a space, then the local name.
map[text] foreignAttrAdjust = {
    'xlink:actuate': 'xlink actuate',
    'xlink:arcrole': 'xlink arcrole',
    'xlink:href': 'xlink href',
    'xlink:role': 'xlink role',
    'xlink:show': 'xlink show',
    'xlink:title': 'xlink title',
    'xlink:type': 'xlink type',
    'xml:lang': 'xml lang',
    'xml:space': 'xml space',
    'xmlns': 'xmlns',
    'xmlns:xlink': 'xmlns xlink',
}

// The HTML start tags that break out of foreign content.
bool func foreignBreakoutTag(tok:Token) {
    text n = tok.name
    if n == 'font' {
        return tok.present['color'] == true || tok.present['face'] == true || tok.present['size'] == true
    }
    return n == 'b' || n == 'big' || n == 'blockquote' || n == 'body' || n == 'br'
        || n == 'center' || n == 'code' || n == 'dd' || n == 'div' || n == 'dl' || n == 'dt'
        || n == 'em' || n == 'embed' || isHeadingTag(n) || n == 'head' || n == 'hr' || n == 'i'
        || n == 'img' || n == 'li' || n == 'listing' || n == 'menu' || n == 'meta' || n == 'nobr'
        || n == 'ol' || n == 'p' || n == 'pre' || n == 'ruby' || n == 's' || n == 'small'
        || n == 'span' || n == 'strong' || n == 'strike' || n == 'sub' || n == 'sup'
        || n == 'table' || n == 'tt' || n == 'u' || n == 'ul' || n == 'var'
}

int func insertForeignElement(tok:Token, ns:int) {
    text name = tok.name
    if ns == NS_SVG {
        text adjusted = svgTagAdjust[name]
        if adjusted != null { name = adjusted }
    }
    Node el = newElement(name)
    el.ns = ns
    arr[text] names = tok.present.keys()
    for int i = 0, i < names.length, i++ {
        text attrName = names[i]
        text mapped = foreignAttrAdjust[attrName]
        if mapped != null {
            attrName = mapped
        } else if ns == NS_SVG {
            text svgName = svgAttrAdjust[attrName]
            if svgName != null { attrName = svgName }
        } else if ns == NS_MATHML && attrName == 'definitionurl' {
            attrName = 'definitionURL'
        }
        text v = tok.attrs[names[i]]
        if v == null { v = '' }
        el.attrs[attrName] = v
        el.present[attrName] = true
        if isPresentationalAttr(attrName) { el.hasPresHint = true }
    }
    findInsertionPlace(0)
    insertAtPlace(el.id)
    pushOpenElement(el.id)
    return el.id
}

void func processTokenForeign(tok:Token) {
    if tok.kind == TOK_TEXT {
        insertCharacters(tok.data)
        if !isWhitespaceText(tok.data) { framesetOk = false }
        return
    }
    if tok.kind == TOK_COMMENT {
        insertCommentNode(tok.data, 0)
        return
    }
    if tok.kind == TOK_DOCTYPE { return }
    if tok.kind == TOK_START {
        if foreignBreakoutTag(tok) {
            // pop back to HTML content, then reprocess
            while openElements.length > 1 {
                int id = currentNodeId()
                if nsOf(id) == NS_HTML || isMathTextIntegrationPoint(id) || isHtmlIntegrationPoint(id) { break }
                popOpenElement()
            }
            processToken(tok)
            return
        }
        int ns = nsOf(currentNodeId())
        insertForeignElement(tok, ns)
        if tok.selfClosing { popOpenElement() }
        return
    }
    if tok.kind == TOK_END {
        // "any other end tag" in foreign content
        int i = openElements.length - 1
        if i < 0 { return }
        if textLower(tagOf(openElements[i])) != tok.name {
            // a parse error, but the search proceeds
        }
        while i >= 0 {
            int id = openElements[i]
            if i == 0 { return }
            if textLower(tagOf(id)) == tok.name {
                while openElements.length > i { popOpenElement() }
                return
            }
            i--
            if nsOf(openElements[i]) == NS_HTML {
                dispatchToken(tok, insertionMode)
                return
            }
        }
        return
    }
}

// The standard's dispatcher: foreign rules apply unless the adjusted
// current node is HTML, or is an integration point that this token
// belongs in.
bool func useForeignRules(tok:Token) {
    if openElements.length == 0 { return false }
    int id = currentNodeId()
    if nsOf(id) == NS_HTML { return false }
    if tok.kind == TOK_EOF { return false }
    if isMathTextIntegrationPoint(id) {
        if tok.kind == TOK_TEXT { return false }
        if tok.kind == TOK_START && tok.name != 'mglyph' && tok.name != 'malignmark' { return false }
    }
    if nsOf(id) == NS_MATHML && tagOf(id) == 'annotation-xml'
        && tok.kind == TOK_START && tok.name == 'svg' { return false }
    if isHtmlIntegrationPoint(id) {
        if tok.kind == TOK_START || tok.kind == TOK_TEXT { return false }
    }
    return true
}


// ---- <selectedcontent> -------------------------------------------------
//
// A selectedcontent element shows a copy of its select's selected
// option. That is an element behaviour rather than tree construction,
// but it is part of the document a parse produces -- the standard's own
// corpus expects the copy in the tree -- so it is applied once, when
// parsing finishes, to documents that contain one.

int func cloneNodeDeep(id:int) {
    int kind = nodeRegistry[id].kind
    if kind == NODE_TEXT {
        Node t = newTextNode(nodeRegistry[id].data)
        return t.id
    }
    if kind == NODE_COMMENT {
        Node c = newComment(nodeRegistry[id].data)
        return c.id
    }
    if kind != NODE_ELEMENT { return 0 }
    int copy = cloneElement(id)
    int count = nodeRegistry[id].children.length
    for int i = 0, i < count, i++ {
        int child = cloneNodeDeep(nodeRegistry[id].children[i].id)
        if child > 0 { appendNode(copy, child) }
    }
    return copy
}

void func collectByTag(id:int, tag:text, out:arr[int]) {
    if nodeRegistry[id].kind == NODE_ELEMENT && nodeRegistry[id].ns == NS_HTML
        && nodeRegistry[id].tag == tag {
        out.push(id)
    }
    int count = nodeRegistry[id].children.length
    for int i = 0, i < count, i++ {
        collectByTag(nodeRegistry[id].children[i].id, tag, out)
    }
}

// The option a select displays: the last one carrying `selected`, or
// else the first one.
int func selectedOptionOf(selectId:int) {
    arr[int] options = []
    collectByTag(selectId, 'option', options)
    if options.length == 0 { return 0 }
    for int i = options.length - 1, i >= 0, i-- {
        if hasAttrOf(options[i], 'selected') { return options[i] }
    }
    return options[0]
}

void func mirrorSelectedContent(doc:int) {
    arr[int] selects = []
    collectByTag(doc, 'select', selects)
    for int i = 0, i < selects.length, i++ {
        int option = selectedOptionOf(selects[i])
        if option == 0 { continue }
        arr[int] targets = []
        collectByTag(selects[i], 'selectedcontent', targets)
        for int j = 0, j < targets.length, j++ {
            int target = targets[j]
            while nodeRegistry[target].children.length > 0 {
                detachNode(nodeRegistry[target].children[0].id)
            }
            int count = nodeRegistry[option].children.length
            for int k = 0, k < count, k++ {
                int copy = cloneNodeDeep(nodeRegistry[option].children[k].id)
                if copy > 0 { appendNode(target, copy) }
            }
        }
    }
}

// ---- the driver -------------------------------------------------------------------

text func dropLeadingNewline(t:text) {
    ascii a = t.toAscii()
    if a == null {
        return t
    }
    if a.length > 0 && a.charCodeAt(0) == CH_LF { return a.slice(1, a.length).toText() }
    return t
}

Node func parseHtml(src:ascii) {
    Node doc = newDocument()
    documentId = doc.id
    insertionMode = IM_INITIAL
    originalInsertionMode = IM_INITIAL
    openElements = []
    activeFormatting = []
    templateModes = []
    templateFramesetOk = []
    headElementId = 0
    formElementId = 0
    framesetOk = true
    quirksMode = false
    fosterParenting = false
    parserDone = false
    skipNextNewline = false
    sawSelectedContent = false
    pendingTableText = []
    pendingTableTextNonSpace = false
    tokenizerInit(src)
    while !parserDone {
        tokAllowCdata = openElements.length > 0 && nsOf(currentNodeId()) != NS_HTML
        Token tok = nextToken()
        if tok.kind == TOK_TEXT {
            if skipNextNewline {
                skipNextNewline = false
                tok.data = dropLeadingNewline(tok.data)
            }
            if tok.data == '' { continue }
        } else {
            skipNextNewline = false
        }
        processToken(tok)
        if tok.kind == TOK_EOF { break }
    }
    if sawSelectedContent { mirrorSelectedContent(doc.id) }
    openElements = []
    activeFormatting = []
    templateModes = []
    templateFramesetOk = []
    return doc
}

Node func parseHtmlBlob(b:blob) {
    text safe = blobToAsciiSafe(b)
    return parseHtml(safe.toAscii())
}

Node func parseHtmlText(t:text) {
    text safe = textToAsciiSafe(t)
    return parseHtml(safe.toAscii())
}
