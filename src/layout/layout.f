// Layout: the styled DOM becomes a tree of boxes with pixel geometry.
// Block formatting (vertical stacking, margin collapsing, auto widths),
// inline formatting (line boxes, word wrapping, vertical alignment,
// text-align), inline-blocks, replaced images, list markers and an
// automatic table layout. Floats and positioned boxes are laid out as
// if static (see FINDINGS.md).
//
// Text is measured with Festina's own measureTextWidth against the
// current canvas font, so every measurement first switches the global
// font to the run's computed font (setFontFor) and is cached per
// (font, word).

import ../css/cascade.f

const int BOX_BLOCK = 1
const int BOX_INLINE = 2
const int BOX_TEXT = 3
const int BOX_INLINE_BLOCK = 4
const int BOX_IMAGE = 5
const int BOX_ANON = 6
const int BOX_TABLE = 7
const int BOX_ROW = 8
const int BOX_CELL = 9
const int BOX_BR = 10
const int BOX_IFRAME = 11
const int BOX_FLEX = 12
const int BOX_AUDIO = 13

// The size Chromium draws an audio element's controls at, which is what
// a page laid out against it expects to find.
const int AUDIO_CONTROLS_W = 300
const int AUDIO_CONTROLS_H = 54

const int FRAG_TEXT = 1
const int FRAG_ATOMIC = 2
const int FRAG_INLINE_BG = 3

// DejaVu Sans metrics (the fonts fontconfig serves for the generic
// families here), in em: ascent 0.93, descent 0.24. Festina exposes
// no ascent/descent API, only the inked height of a string.
const float FONT_ASCENT = 0.93
const float FONT_DESCENT = 0.24
const float LINE_NORMAL = 1.2

int nextBoxId = 1
// every box of the current layout, indexed by id (parentBox looks parents up here)
arr[Box] boxRegistry = [null]

struct Box {
    id:int
    kind:int
    // A flex item's main size, decided by the flex algorithm rather than
    // by the element's own `width`. -1 when unset. This lives on the box
    // rather than being written into the style, because a computed Style
    // is shared between every element that matched the same
    // declarations: writing to one would write to all of them.
    forcedWidthPx:int
    // The words of a text box, after white-space processing and any
    // text-transform. They depend only on the content and the computed
    // style, both fixed once the cascade has run, and they are asked
    // for twice -- once to measure intrinsic widths and once to place
    // the text -- so they are worked out once.
    wordsDone:bool
    words:arr[text]
    node:Node               // the element; id 0 for anonymous boxes
    style:Style
    children:arr[Box]
    parentId:int            // 0 = none; see boxRegistry (no back-pointer, as in node.f)
    x:int
    y:int
    w:int                   // border-box width
    h:int                   // border-box height
    mt:int
    mr:int
    mb:int
    ml:int
    pt:int
    pr:int
    pb:int
    pl:int
    bt:int
    br:int
    bb:int
    bl:int
    content:text               // BOX_TEXT
    lines:arr[Line]         // block containers with inline content
    image:img               // BOX_IMAGE
    imgW:int
    imgH:int
    frameKey:text           // BOX_IFRAME: key into loadedFrames
    isListItem:bool
    listIndex:int
    baseline:int            // distance from the top border edge to the last baseline
    blockLevel:bool         // an image/inline-block that is display:block
    colspan:int
    tableRow:int            // a cell's row and first column, for collapsed borders
    tableCol:int
    depth:int
    // cached intrinsic widths (-1 = not computed)
    minContent:int
    maxContent:int
}

struct Fragment {
    kind:int
    box:Box
    content:text
    x:int
    y:int
    w:int
    h:int
    baseline:int
}

struct Line {
    x:int
    y:int
    w:int
    h:int
    baseline:int
    frags:arr[Fragment]
}

// Images the shell has loaded, keyed by resolved URL; buildBox reads
// them through the node's 'data-resolved-src' attribute.
map[img] loadedImages = {}

// Laid-out documents for the frames on this page, keyed by resolved URL
// exactly as loadedImages is. The box tree is built once per URL and
// shared by every frame naming it.
map[Box] loadedFrames = {}

// The size a frame takes when nothing says otherwise (HTML §14.3.3).
const int FRAME_DEFAULT_W = 300
const int FRAME_DEFAULT_H = 150

int func frameBoxWidth(b:Box, cw:int) {
    Len w = b.style.width
    if !lenIsAuto(w) { return maxInt(resolveLen(w, cw, -1), 0) }
    return FRAME_DEFAULT_W
}

int func frameBoxHeight(b:Box) {
    Len h = b.style.height
    if !lenIsAuto(h) { return maxInt(resolveLen(h, 0, -1), 0) }
    return FRAME_DEFAULT_H
}

// ---- fonts and measurement -------------------------------------------

text currentFontKey = ''
map[int] widthCache = {}

// hot-spot accumulators, reported with ARCHTELOS_TIMING=1
int profMeasureCalls = 0
int profMeasureMisses = 0
int profMeasureMs = 0
int profWordsCalls = 0
int profWordsMs = 0
int profIntrinsicMs = 0
int profFinishMs = 0
int profFontSwitches = 0
int profBuildMs = 0
int profPlaceTextMs = 0

text func layoutProfile() {
    return `[timing] layout detail: measure ${profMeasureCalls} calls, ${profMeasureMisses} misses, ${profMeasureMs} ms; font switches ${profFontSwitches}; wordsOf ${profWordsCalls} calls, ${profWordsMs} ms; intrinsic ${profIntrinsicMs} ms; finishLine ${profFinishMs} ms; placeText ${profPlaceTextMs} ms; box tree ${profBuildMs} ms`
}
regex spaceRun = /[[:space:]]+/g
regex tabChar = regex(9.toChar(), 'g')

void func setFontFor(s:Style) {
    if s.fontKey == currentFontKey { return }
    profFontSwitches++
    currentFontKey = s.fontKey
    text styleText = 'normal'
    if s.fontBold && s.fontItalic { styleText = 'bold italic' }
    else if s.fontBold { styleText = 'bold' }
    else if s.fontItalic { styleText = 'italic' }
    changeFont(s.fontSize, styleText, s.fontFamily)
}

int func measureWidth(s:Style, t:text) {
    int t0 = archtelosTiming ? now() : 0
    profMeasureCalls++
    text key = `${s.fontKey}|${t}`
    int cached = widthCache[key]
    if cached != null {
        if archtelosTiming { profMeasureMs = profMeasureMs + (now() - t0) }
        return cached
    }
    profMeasureMisses++
    setFontFor(s)
    int w = measureTextWidth(t)
    if s.letterSpacing != 0 { w = w + s.letterSpacing * t.length }
    widthCache[key] = w
    if archtelosTiming { profMeasureMs = profMeasureMs + (now() - t0) }
    return w
}

int func spaceWidth(s:Style) {
    return measureWidth(s, ' ') + s.wordSpacing
}

int func fontAscent(s:Style) {
    return roundPx(s.fontSize.toFloat() * FONT_ASCENT)
}

int func fontDescent(s:Style) {
    return roundPx(s.fontSize.toFloat() * FONT_DESCENT)
}

int func lineHeightOf(s:Style) {
    if s.lineHeight > 0 { return s.lineHeight }
    return roundPx(s.fontSize.toFloat() * LINE_NORMAL)
}

// ---- box construction ----------------------------------------------------

// Whether this document contains any positioned or floated box at all.
// Both cost an extra pass over the tree -- layoutPositioned, and the
// two-pass z-index child ordering in the painter -- and most pages have
// neither. The flags are set once while the box tree is built and read
// wherever a pass can be skipped whole.
bool docHasPositioned = false
bool docHasFloats = false

Box func newBox(kind:int, node:Node, style:Style) {
    Box b
    b.id = nextBoxId
    nextBoxId++
    boxRegistry.push(b)
    b.kind = kind
    b.node = node
    b.style = style
    b.content = ''
    b.colspan = 1
    b.minContent = -1
    b.maxContent = -1
    b.forcedWidthPx = -1
    if node != null && kind != BOX_TEXT && kind != BOX_BR && kind != BOX_ANON {
        if positionIsPositioned(style.position) { docHasPositioned = true }
        if style.floatSide != FLOAT_NONE { docHasFloats = true }
    }
    return b
}

void func addChildBox(parent:Box, child:Box) {
    child.parentId = parent.id
    child.depth = parent.depth + 1
    parent.children.push(child)
}

Box func parentBox(b:Box) {
    if b.parentId <= 0 || b.parentId >= boxRegistry.length { return null }
    return boxRegistry[b.parentId]
}

int func parentKind(b:Box) {
    if b.parentId <= 0 || b.parentId >= boxRegistry.length { return 0 }
    return boxRegistry[b.parentId].kind
}

bool func boxHasNode(b:Box) {
    return b.node.id > 0
}

// An anonymous block inherits the inheritable properties of its
// parent and nothing else.
Style func anonymousStyle(parent:Style) {
    Style s
    s.display = DISPLAY_BLOCK
    s.color = parent.color
    s.fontSize = parent.fontSize
    s.fontBold = parent.fontBold
    s.fontItalic = parent.fontItalic
    s.fontFamily = parent.fontFamily
    s.fontKey = parent.fontKey
    s.lineHeight = parent.lineHeight
    s.textAlign = parent.textAlign
    s.textDecoration = parent.textDecoration
    s.textTransform = parent.textTransform
    s.whiteSpace = parent.whiteSpace
    s.listStyle = parent.listStyle
    s.letterSpacing = parent.letterSpacing
    s.textIndent = parent.textIndent
    s.opacity = parent.opacity
    s.hidden = parent.hidden
    s.background = COLOR_TRANSPARENT
    s.width = lenAuto()
    s.height = lenAuto()
    return s
}

// Whether this box is taken out of the flow. A text box shares the
// computed style of the element around it, so `position` reads through
// to it: only a box with a real element of its own can be out of flow,
// or an absolutely positioned <p> would lose its own text.
bool func boxIsOutOfFlow(b:Box) {
    // The document-level flag first: on a page with nothing positioned
    // this is the whole test, and it is asked of every child of every
    // block. See docHasPositioned.
    if !docHasPositioned { return false }
    if b == null { return false }
    if b.kind == BOX_TEXT || b.kind == BOX_BR || b.kind == BOX_ANON { return false }
    if b.node == null { return false }
    return positionIsOutOfFlow(b.style.position)
}

bool func boxIsPositioned(b:Box) {
    if b == null { return false }
    if b.kind == BOX_TEXT || b.kind == BOX_BR || b.kind == BOX_ANON { return false }
    if b.node == null { return false }
    return positionIsPositioned(b.style.position)
}

bool func isInlineLevelBox(b:Box) {
    if b.blockLevel { return false }
    return b.kind == BOX_INLINE || b.kind == BOX_TEXT || b.kind == BOX_INLINE_BLOCK || b.kind == BOX_IMAGE || b.kind == BOX_IFRAME || b.kind == BOX_BR || b.kind == BOX_FLEX || b.kind == BOX_AUDIO
}

// Whether a text box holds nothing but white space, which is the test
// that decides whether it is a box at all. `text` indexes without
// allocating; `t.toAscii()` here built a fresh ascii on every call, and
// the call is made several times for every text child of every element
// while the box tree is built. It also answered false for any text with
// a non-ASCII character in it, which no blank string has.
bool func textIsCollapsibleBlank(t:text) {
    if t == null || t == '' { return false }
    for int i = 0, i < t.length, i++ {
        if !isSpaceCode(t.charCodeAt(i)) { return false }
    }
    return true
}

bool func isFormControl(tag:text) {
    return tag == 'input' || tag == 'button' || tag == 'select' || tag == 'textarea'
}

// The text a form control displays.
text func formControlText(n:Node) {
    if n.tag == 'input' {
        text ty = textLower(getAttr(n, 'type'))
        if ty == null { ty = 'text' }
        if ty == 'submit' { text v = getAttr(n, 'value')  return v == null ? 'Submit' : v }
        if ty == 'reset' { text v = getAttr(n, 'value')  return v == null ? 'Reset' : v }
        if ty == 'button' || ty == 'text' || ty == 'search' || ty == 'email' || ty == 'url' || ty == 'tel' || ty == 'number' || ty == 'password' {
            text v = getAttr(n, 'value')
            if v != null && v != '' { return ty == 'password' ? repeatText('*', v.length) : v }
            text ph = getAttr(n, 'placeholder')
            return ph == null ? '' : ph
        }
        return ''
    }
    if n.tag == 'select' {
        Node opt = findElement(n, 'option')
        if opt == null { return '' }
        return textContent(opt).trim()
    }
    return ''
}

Box func buildTextBox(n:Node, parentStyle:Style) {
    Box b = newBox(BOX_TEXT, n, parentStyle)
    b.content = n.data
    return b
}

// Builds the box for an element (or null when it generates none) and
// its subtree.
Box func buildBox(n:Node, parentStyle:Style) {
    if n.kind == NODE_TEXT {
        return buildTextBox(n, parentStyle)
    }
    if n.kind != NODE_ELEMENT { return null }
    Style s = n.style
    int d = s.display
    if d == DISPLAY_NONE { return null }
    // A column or column group generates no box; a table reads the
    // width off the element itself.
    if displayIsColumn(d) { return null }
    text tag = n.tag
    if tag == 'br' {
        return newBox(BOX_BR, n, s)
    }
    if tag == 'img' {
        Box b = newBox(BOX_IMAGE, n, s)
        text src = getAttr(n, 'data-resolved-src')
        if src != null {
            img loaded = loadedImages[src]
            if loaded != null {
                b.image = loaded
                b.imgW = loaded.width
                b.imgH = loaded.height
            }
        }
        b.blockLevel = displayIsBlockLevel(d)
        return b
    }
    // A frame renders the document its src names, never its own child
    // nodes: those are fallback content for a UA with no nested
    // browsing context, and this one has one.
    if tag == 'iframe' || tag == 'frame' {
        Box b = newBox(BOX_IFRAME, n, s)
        b.frameKey = getAttr(n, 'data-frame-src')
        b.blockLevel = displayIsBlockLevel(d)
        return b
    }
    // An <audio> asking for controls is a replaced element: it draws a
    // control bar of its own and its children are fallback content for
    // a user agent that cannot play it, so they are not rendered --
    // the same rule as an iframe's children.
    if tag == 'audio' {
        Box b = newBox(BOX_AUDIO, n, s)
        b.blockLevel = displayIsBlockLevel(d)
        return b
    }
    if isFormControl(tag) {
        Box b = newBox(BOX_INLINE_BLOCK, n, s)
        b.blockLevel = displayIsBlockLevel(d)
        if tag == 'button' || tag == 'textarea' {
            buildChildren(b, n, s)
        } else {
            text label = formControlText(n)
            Node fake = newTextNode(label)
            fake.style = s
            addChildBox(b, buildTextBox(fake, s))
        }
        return b
    }
    if d == DISPLAY_FLEX || d == DISPLAY_INLINE_FLEX {
        Box b = newBox(BOX_FLEX, n, s)
        b.blockLevel = d == DISPLAY_FLEX
        buildChildren(b, n, s)
        return b
    }
    if d == DISPLAY_TABLE {
        Box b = newBox(BOX_TABLE, n, s)
        buildTableChildren(b, n, s)
        return b
    }
    if d == DISPLAY_TABLE_ROW {
        Box b = newBox(BOX_ROW, n, s)
        buildChildren(b, n, s)
        return b
    }
    if d == DISPLAY_TABLE_CELL {
        Box b = newBox(BOX_CELL, n, s)
        text cs = getAttr(n, 'colspan')
        if cs != null && cs.toInt() != null && cs.toInt() > 1 { b.colspan = minInt(cs.toInt(), 100) }
        buildChildren(b, n, s)
        return b
    }
    if displayIsRowGroup(d) {
        // rows are lifted into the table by buildTableChildren; a row
        // group met anywhere else behaves as a block
        Box b = newBox(BOX_BLOCK, n, s)
        buildChildren(b, n, s)
        return b
    }
    if d == DISPLAY_INLINE_BLOCK {
        Box b = newBox(BOX_INLINE_BLOCK, n, s)
        buildChildren(b, n, s)
        return b
    }
    if d == DISPLAY_INLINE {
        Box b = newBox(BOX_INLINE, n, s)
        buildChildren(b, n, s)
        // an inline containing block-level content becomes a block
        for int i = 0, i < b.children.length, i++ {
            if !isInlineLevelBox(b.children[i]) {
                b.kind = BOX_BLOCK
                break
            }
        }
        if b.kind == BOX_BLOCK { wrapInlineRuns(b) }
        return b
    }
    Box b = newBox(BOX_BLOCK, n, s)
    if d == DISPLAY_LIST_ITEM {
        b.isListItem = true
    }
    buildChildren(b, n, s)
    wrapInlineRuns(b)
    return b
}

void func buildChildren(b:Box, n:Node, s:Style) {
    addGeneratedBox(b, n, 'before')
    for int i = 0, i < n.children.length, i++ {
        Box c = buildBox(n.children[i], s)
        if c != null { addChildBox(b, c) }
    }
    addGeneratedBox(b, n, 'after')
}

// A ::before or ::after box: the generated content as a text box inside
// a box of the pseudo-element's own style, so `display`, `color` and the
// rest apply to it rather than to the element (CSS2 §12.1). Nothing is
// generated unless the cascade resolved a `content` for it.
void func addGeneratedBox(b:Box, n:Node, which:text) {
    if n == null || n.id <= 0 { return }
    if !hasPseudo(n.id, which) { return }
    Style ps = pseudoStyleOf(n.id, which)
    if ps.display == DISPLAY_NONE { return }
    text content = pseudoContentOf(n.id, which)

    Box box = newBox(displayIsBlockLevel(ps.display) ? BOX_BLOCK : BOX_INLINE, n, ps)
    box.blockLevel = displayIsBlockLevel(ps.display)
    if content != null && content != '' {
        Node fake = newTextNode(content)
        fake.style = ps
        addChildBox(box, buildTextBox(fake, ps))
    }
    addChildBox(b, box)
}

// Rows of a table, flattening thead/tbody/tfoot; anything else (a
// caption, stray text) is hoisted out as a block above the table by
// the parent through wrapInlineRuns.
void func buildTableChildren(b:Box, n:Node, s:Style) {
    for int i = 0, i < n.children.length, i++ {
        Node c = n.children[i]
        if c.kind != NODE_ELEMENT { continue }
        int cd = c.style.display
        if displayIsRowGroup(cd) {
            for int j = 0, j < c.children.length, j++ {
                Node r = c.children[j]
                if r.kind == NODE_ELEMENT && r.style.display == DISPLAY_TABLE_ROW {
                    Box rb = buildBox(r, c.style)
                    if rb != null { addChildBox(b, rb) }
                }
            }
        } else if cd == DISPLAY_TABLE_ROW {
            Box rb = buildBox(c, s)
            if rb != null { addChildBox(b, rb) }
        } else if cd != DISPLAY_NONE && c.tag != 'colgroup' && c.tag != 'col' {
            // a caption or misplaced content: keep it as a block child
            // and let layoutTable put it above the rows
            Box other = buildBox(c, s)
            if other != null {
                if other.kind == BOX_CELL {
                    // a cell without a row: synthesize the row
                    Box row = newBox(BOX_ROW, c, s)
                    addChildBox(row, other)
                    addChildBox(b, row)
                } else {
                    addChildBox(b, other)
                }
            }
        }
    }
    // a row's stray cells could also be text; ignore
    for int i = 0, i < b.children.length, i++ {
        Box row = b.children[i]
        if row.kind != BOX_ROW { continue }
        arr[Box] cells = []
        for int j = 0, j < row.children.length, j++ {
            Box c = row.children[j]
            if c.kind == BOX_CELL { cells.push(c) }
            else if c.kind != BOX_TEXT {
                Box cell = newBox(BOX_CELL, c.node, c.style)
                addChildBox(cell, c)
                cell.parentId = row.id
                cells.push(cell)
            }
        }
        row.children = cells
    }
}

// Wraps runs of inline-level children of a block container into
// anonymous block boxes when block-level siblings are present, and
// drops whitespace-only text between blocks.
void func wrapInlineRuns(b:Box) {
    bool hasBlock = false
    bool hasInline = false
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if isInlineLevelBox(c) {
            if c.kind == BOX_TEXT && textIsCollapsibleBlank(c.content) && c.style.whiteSpace != WS_PRE && c.style.whiteSpace != WS_PRE_WRAP { continue }
            hasInline = true
        } else {
            hasBlock = true
        }
    }
    if !hasBlock || !hasInline {
        if hasBlock {
            // drop blank text between blocks
            arr[Box] kept = []
            for int i = 0, i < b.children.length, i++ {
                Box c = b.children[i]
                if c.kind == BOX_TEXT && textIsCollapsibleBlank(c.content) { continue }
                kept.push(c)
            }
            b.children = kept
        }
        return
    }
    arr[Box] out = []
    Box run = null
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if isInlineLevelBox(c) {
            if c.kind == BOX_TEXT && textIsCollapsibleBlank(c.content) && run == null { continue }
            if run == null {
                run = newBox(BOX_ANON, b.node, anonymousStyle(b.style))
                run.node = newDocument()      // a placeholder with no meaning; id is non-zero but kind is document
                run.parentId = b.id
                run.depth = b.depth + 1
            }
            addChildBox(run, c)
        } else {
            if run != null {
                out.push(run)
                run = null
            }
            out.push(c)
        }
    }
    if run != null { out.push(run) }
    b.children = out
}

// ---- intrinsic widths ------------------------------------------------------

// Words of a text box after white-space processing. Pre-formatted
// text is split only at newlines, each line one unbreakable word.
arr[text] func wordsOf(b:Box) {
    if b.wordsDone { return b.words }
    profWordsCalls++
    int t0 = archtelosTiming ? now() : 0
    arr[text] words = wordsOfUncounted(b)
    if archtelosTiming { profWordsMs = profWordsMs + (now() - t0) }
    b.words = words
    b.wordsDone = true
    return words
}

arr[text] func wordsOfUncounted(b:Box) {
    text t = b.content
    if b.style.textTransform == TT_UPPERCASE { t = textUpper(t) }
    else if b.style.textTransform == TT_LOWERCASE { t = textLower(t) }
    if b.style.whiteSpace == WS_PRE || b.style.whiteSpace == WS_PRE_WRAP {
        return t.replace(tabChar, '    ').split('\n')
    }
    return t.replace(spaceRun, ' ').split(' ')
}

text func textUpper(t:text) {
    ascii a = t.toAscii()
    if a == null { return t }
    text out = ''
    for int i = 0, i < a.length, i++ {
        int c = a.charCodeAt(i)
        if c >= 97 && c <= 122 { c = c - 32 }
        text ch = c.toChar()
        out = out + ch
    }
    return out
}

int func horizontalExtras(b:Box, cw:int) {
    Style s = b.style
    return resolveLen(s.marginLeft, cw, 0) + resolveLen(s.marginRight, cw, 0)
        + resolveLen(s.paddingLeft, cw, 0) + resolveLen(s.paddingRight, cw, 0)
        + s.borderLeft + s.borderRight
}

// Fills b.minContent / b.maxContent (content-box widths plus the
// box's own edges) for shrink-to-fit and table column sizing.
void func computeIntrinsic(b:Box) {
    if b.minContent >= 0 { return }
    int t0 = archtelosTiming ? now() : 0
    computeIntrinsicUncounted(b)
    if archtelosTiming { profIntrinsicMs = profIntrinsicMs + (now() - t0) }
}

void func computeIntrinsicUncounted(b:Box) {
    int minW = 0
    int maxW = 0
    if b.kind == BOX_TEXT {
        arr[text] words = wordsOf(b)
        int sw = spaceWidth(b.style)
        bool pre = b.style.whiteSpace == WS_PRE || b.style.whiteSpace == WS_PRE_WRAP
        bool nowrap = b.style.whiteSpace == WS_NOWRAP
        int lineW = 0
        for int i = 0, i < words.length, i++ {
            text w = words[i]
            if w == '' {
                if pre && i < words.length - 1 {
                    maxW = maxInt(maxW, lineW)
                    lineW = 0
                }
                continue
            }
            int ww = measureWidth(b.style, w)
            if pre {
                minW = maxInt(minW, ww)
                lineW = ww
                maxW = maxInt(maxW, lineW)
            } else {
                if lineW > 0 { lineW = lineW + sw }
                lineW = lineW + ww
                minW = nowrap ? lineW : maxInt(minW, ww)
                maxW = lineW
            }
        }
        b.minContent = minW
        b.maxContent = maxW
        return
    }
    if b.kind == BOX_IMAGE {
        int w = imageBoxWidth(b, 0)
        b.minContent = w + horizontalExtras(b, 0)
        b.maxContent = b.minContent
        return
    }
    if b.kind == BOX_IFRAME {
        int w = frameBoxWidth(b, 0)
        b.minContent = w + horizontalExtras(b, 0)
        b.maxContent = b.minContent
        return
    }
    if b.kind == BOX_BR {
        b.minContent = 0
        b.maxContent = 0
        return
    }
    Style s = b.style
    if b.kind == BOX_TABLE {
        computeTableIntrinsic(b)
        return
    }
    if b.kind == BOX_FLEX {
        // A row's preferred width is every item side by side with the
        // gaps between them; a column's is the widest item. The minimum
        // is the same shape over the items' own minima, which is what
        // lets a row shrink rather than overflow.
        bool fRow = flexIsRow(s)
        int fCount = 0
        for int i = 0, i < b.children.length, i++ {
            Box c = b.children[i]
            if c.kind == BOX_TEXT && textIsCollapsibleBlank(c.content) { continue }
            if boxIsOutOfFlow(c) { continue }
            computeIntrinsic(c)
            if fRow {
                minW = minW + c.minContent
                maxW = maxW + c.maxContent
            } else {
                minW = maxInt(minW, c.minContent)
                maxW = maxInt(maxW, c.maxContent)
            }
            fCount++
        }
        if fRow && fCount > 1 {
            int fGap = s.columnGap * (fCount - 1)
            minW = minW + fGap
            maxW = maxW + fGap
        }
        if s.width.kind == LEN_PX {
            minW = roundPx(s.width.v)
            maxW = minW
        }
        int fExtras = horizontalExtras(b, 0)
        b.minContent = minW + fExtras
        b.maxContent = maxW + fExtras
        return
    }
    bool inlineContent = hasInlineContent(b)
    if inlineContent || b.kind == BOX_INLINE {
        // inline content: max = everything on one line, min = widest piece
        int lineW = 0
        for int i = 0, i < b.children.length, i++ {
            Box c = b.children[i]
            computeIntrinsic(c)
            if c.kind == BOX_BR {
                maxW = maxInt(maxW, lineW)
                lineW = 0
                continue
            }
            minW = maxInt(minW, c.minContent)
            if c.kind == BOX_TEXT && c.style.whiteSpace == WS_NOWRAP { minW = maxInt(minW, c.maxContent) }
            lineW = lineW + c.maxContent
            if c.kind == BOX_TEXT && i > 0 && !textStartsWithSpace(c) { }
            else if i > 0 && c.kind == BOX_TEXT { lineW = lineW + spaceWidth(c.style) }
        }
        maxW = maxInt(maxW, lineW)
        if s.whiteSpace == WS_NOWRAP { minW = maxW }
    } else {
        for int i = 0, i < b.children.length, i++ {
            Box c = b.children[i]
            computeIntrinsic(c)
            minW = maxInt(minW, c.minContent)
            maxW = maxInt(maxW, c.maxContent)
        }
    }
    if s.width.kind == LEN_PX {
        int fixed = roundPx(s.width.v)
        minW = fixed
        maxW = fixed
    }
    if s.maxWidth.kind == LEN_PX {
        int mx = roundPx(s.maxWidth.v)
        maxW = minInt(maxW, mx)
        minW = minInt(minW, mx)
    }
    if s.minWidth.kind == LEN_PX {
        int mn = roundPx(s.minWidth.v)
        maxW = maxInt(maxW, mn)
        minW = maxInt(minW, mn)
    }
    int extras = horizontalExtras(b, 0)
    if b.isListItem { }
    b.minContent = minW + extras
    b.maxContent = maxW + extras
}

bool func textStartsWithSpace(b:Box) {
    if b.content == null || b.content == '' { return false }
    int c = b.content.charCodeAt(0)
    return isSpaceCode(c)
}

bool func hasInlineContent(b:Box) {
    if b.children.length == 0 { return false }
    bool any = false
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        // An out-of-flow box is neither: it does not decide whether its
        // parent runs an inline formatting context.
        if boxIsOutOfFlow(c) || boxIsFloated(c) { continue }
        any = true
        if !isInlineLevelBox(c) { return false }
    }
    return any
}

// ---- geometry helpers ---------------------------------------------------------

void func resolveEdges(b:Box, cw:int) {
    Style s = b.style
    b.mt = resolveLen(s.marginTop, cw, 0)
    b.mr = resolveLen(s.marginRight, cw, 0)
    b.mb = resolveLen(s.marginBottom, cw, 0)
    b.ml = resolveLen(s.marginLeft, cw, 0)
    b.pt = resolveLen(s.paddingTop, cw, 0)
    b.pr = resolveLen(s.paddingRight, cw, 0)
    b.pb = resolveLen(s.paddingBottom, cw, 0)
    b.pl = resolveLen(s.paddingLeft, cw, 0)
    b.bt = s.borderTop
    b.br = s.borderRight
    b.bb = s.borderBottom
    b.bl = s.borderLeft
}

int func contentWidth(b:Box) {
    return b.w - b.pl - b.pr - b.bl - b.br
}

int func contentX(b:Box) {
    return b.x + b.bl + b.pl
}

int func contentY(b:Box) {
    return b.y + b.bt + b.pt
}

// Moves a laid-out subtree, lines and fragments included.
void func offsetBox(b:Box, dx:int, dy:int) {
    if dx == 0 && dy == 0 { return }
    b.x = b.x + dx
    b.y = b.y + dy
    for int i = 0, i < b.lines.length, i++ {
        Line ln = b.lines[i]
        ln.x = ln.x + dx
        ln.y = ln.y + dy
        ln.baseline = ln.baseline + dy
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            f.x = f.x + dx
            f.y = f.y + dy
            f.baseline = f.baseline + dy
        }
    }
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        if c.kind == BOX_INLINE {
            offsetInlineDescendants(c, dx, dy)
            continue
        }
        offsetBox(c, dx, dy)
    }
}

// Atomic boxes nested inside inline boxes have geometry of their own.
void func offsetInlineDescendants(b:Box, dx:int, dy:int) {
    b.x = b.x + dx
    b.y = b.y + dy
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        if c.kind == BOX_INLINE { offsetInlineDescendants(c, dx, dy) }
        else { offsetBox(c, dx, dy) }
    }
}

int func imageBoxWidth(b:Box, cw:int) {
    Style s = b.style
    int natural = b.imgW > 0 ? b.imgW : 0
    int naturalH = b.imgH > 0 ? b.imgH : 0
    if !lenIsAuto(s.width) {
        return maxInt(resolveLen(s.width, cw, natural), 0)
    }
    if !lenIsAuto(s.height) && naturalH > 0 && natural > 0 {
        int h = resolveLen(s.height, 0, naturalH)
        return roundPx(h.toFloat() * natural.toFloat() / naturalH.toFloat())
    }
    if natural == 0 {
        // a missing image: an alt-text sized placeholder
        text alt = getAttr(b.node, 'alt')
        if alt != null && alt != '' { return measureWidth(b.style, alt) + 4 }
        return 16
    }
    return natural
}

int func imageBoxHeight(b:Box, w:int) {
    Style s = b.style
    int natural = b.imgW > 0 ? b.imgW : 0
    int naturalH = b.imgH > 0 ? b.imgH : 0
    if !lenIsAuto(s.height) && s.height.kind == LEN_PX {
        return maxInt(roundPx(s.height.v), 0)
    }
    if natural > 0 && naturalH > 0 {
        return roundPx(w.toFloat() * naturalH.toFloat() / natural.toFloat())
    }
    return 16
}

// ---- block layout -----------------------------------------------------------

// The margin that collapses out through the top of `b`: its own top
// margin joined with its first in-flow child's, when nothing (border,
// padding) separates them.
int func collapsedTopMargin(b:Box, cw:int) {
    int own = resolveLen(b.style.marginTop, cw, 0)
    if b.kind != BOX_BLOCK && b.kind != BOX_ANON { return own }
    if b.style.borderTop > 0 || resolveLen(b.style.paddingTop, cw, 0) > 0 { return own }
    if hasInlineContent(b) || b.children.length == 0 { return own }
    Box first = b.children[0]
    if first.kind != BOX_BLOCK && first.kind != BOX_ANON { return own }
    return maxInt(own, collapsedTopMargin(first, cw))
}

int func collapsedBottomMargin(b:Box, cw:int) {
    int own = resolveLen(b.style.marginBottom, cw, 0)
    if b.kind != BOX_BLOCK && b.kind != BOX_ANON { return own }
    if b.style.borderBottom > 0 || resolveLen(b.style.paddingBottom, cw, 0) > 0 { return own }
    if !lenIsAuto(b.style.height) { return own }
    if hasInlineContent(b) || b.children.length == 0 { return own }
    Box last = b.children[b.children.length - 1]
    if last.kind != BOX_BLOCK && last.kind != BOX_ANON { return own }
    return maxInt(own, collapsedBottomMargin(last, cw))
}

// Lays out a block-level box whose containing block's content area
// starts at (cx, cy) with width cw. `y` is the flow position: the box's
// top border edge lands at y + (its top margin, unless already
// collapsed into the parent). Returns nothing; geometry lives on b.
void func layoutBlock(b:Box, cx:int, y:int, cw:int, topMarginApplied:bool) {
    resolveEdges(b, cw)
    Style s = b.style
    if topMarginApplied { b.mt = 0 }
    if b.kind == BOX_TABLE {
        layoutTable(b, cx, y, cw)
        return
    }
    if b.kind == BOX_AUDIO {
        int aw = lenIsAuto(s.width) ? AUDIO_CONTROLS_W : maxInt(resolveLen(s.width, cw, 0), 0)
        int ah = s.height.kind == LEN_PX ? maxInt(roundPx(s.height.v), 0) : AUDIO_CONTROLS_H
        b.w = aw + b.pl + b.pr + b.bl + b.br
        b.h = ah + b.pt + b.pb + b.bt + b.bb
        b.x = cx + b.ml
        b.y = y + b.mt
        b.baseline = b.h
        return
    }
    if b.kind == BOX_IFRAME {
        int w = frameBoxWidth(b, cw)
        b.w = w + b.pl + b.pr + b.bl + b.br
        b.h = frameBoxHeight(b) + b.pt + b.pb + b.bt + b.bb
        b.x = cx + b.ml
        b.y = y + b.mt
        return
    }
    if b.kind == BOX_IMAGE {
        int w = imageBoxWidth(b, cw)
        b.w = w + b.pl + b.pr + b.bl + b.br
        b.h = imageBoxHeight(b, w) + b.pt + b.pb + b.bt + b.bb
        b.x = cx + b.ml
        b.y = y + b.mt
        if lenIsAuto(s.marginLeft) && lenIsAuto(s.marginRight) && b.blockLevel && s.textAlign == ALIGN_CENTER { }
        b.baseline = b.h
        return
    }
    // width
    int edges = b.pl + b.pr + b.bl + b.br
    int width = 0
    bool autoWidth = lenIsAuto(s.width) && b.forcedWidthPx < 0
    if autoWidth {
        if (b.kind == BOX_INLINE_BLOCK || b.kind == BOX_FLEX) && !b.blockLevel {
            computeIntrinsic(b)
            int avail = cw - b.ml - b.mr
            int pref = b.maxContent - horizontalExtras(b, 0) + edges
            int minw = b.minContent - horizontalExtras(b, 0) + edges
            width = minInt(maxInt(minw, avail), pref) - edges
            if width < 0 { width = 0 }
        } else {
            width = cw - b.ml - b.mr - edges
            if width < 0 { width = 0 }
        }
    } else {
        width = b.forcedWidthPx >= 0 ? b.forcedWidthPx : maxInt(resolveLen(s.width, cw, 0), 0)
        // `box-sizing: border-box` means the declared width IS the
        // border box, so the padding and border come out of it.
        if s.boxSizing == BOX_BORDER { width = maxInt(width - edges, 0) }
    }
    if s.maxWidth.kind != LEN_AUTO {
        int mx = resolveLen(s.maxWidth, cw, width)
        if width > mx { width = mx }
    }
    if s.minWidth.kind != LEN_AUTO {
        int mn = resolveLen(s.minWidth, cw, 0)
        if width < mn { width = mn }
    }
    if !autoWidth || s.maxWidth.kind != LEN_AUTO {
        // auto margins center a box narrower than its container
        int freeSpace = cw - width - edges
        if lenIsAuto(s.marginLeft) && lenIsAuto(s.marginRight) && freeSpace > 0 {
            b.ml = Math.floorDiv(freeSpace, 2)
            b.mr = freeSpace - b.ml
        } else if lenIsAuto(s.marginLeft) && freeSpace > 0 {
            b.ml = freeSpace - b.mr
        }
    }
    b.w = width + edges
    b.x = cx + b.ml
    b.y = y + b.mt

    // A flex container sizes its own box like a block, then hands the
    // children to the flex algorithm rather than stacking them
    // (Flexible Box Layout 1 §9).
    if b.kind == BOX_FLEX {
        int flexEdges = b.pt + b.pb + b.bt + b.bb
        b.h = flexEdges
        if s.height.kind == LEN_PX {
            int fh = maxInt(roundPx(s.height.v), 0)
            if s.boxSizing == BOX_BORDER { fh = maxInt(fh - flexEdges, 0) }
            b.h = fh + flexEdges
        }
        layoutFlex(b, cx, y, cw)
        return
    }

    // children
    int innerX = contentX(b)
    int innerY = contentY(b)
    int contentH = 0
    if hasInlineContent(b) {
        contentH = layoutInlineContent(b, innerX, innerY, width)
    } else {
        contentH = layoutBlockChildren(b, innerX, innerY, width)
    }
    int h = contentH
    int vEdges = b.pt + b.pb + b.bt + b.bb
    if !lenIsAuto(s.height) && s.height.kind == LEN_PX {
        h = maxInt(roundPx(s.height.v), 0)
        // as with the width, a border-box height already includes the
        // padding and border
        if s.boxSizing == BOX_BORDER { h = maxInt(h - vEdges, 0) }
    }
    if s.minHeight.kind == LEN_PX {
        int mn = roundPx(s.minHeight.v)
        if s.boxSizing == BOX_BORDER { mn = maxInt(mn - vEdges, 0) }
        h = maxInt(h, mn)
    }
    if s.maxHeight.kind == LEN_PX {
        int mx = roundPx(s.maxHeight.v)
        if s.boxSizing == BOX_BORDER { mx = maxInt(mx - vEdges, 0) }
        if h > mx { h = mx }
    }
    b.h = h + vEdges
    if b.baseline == 0 { b.baseline = b.h }
}

// Stacks the block-level children of b; returns the content height.
int func layoutBlockChildren(b:Box, cx:int, cy:int, cw:int) {
    int y = cy
    int prevBottomMargin = 0
    bool first = true
    bool parentAbsorbsTop = b.bt == 0 && b.pt == 0 && (b.kind == BOX_BLOCK || b.kind == BOX_ANON) && b.parentId > 0 && parentKind(b) != BOX_CELL && parentKind(b) != BOX_INLINE_BLOCK && !b.isListItem
    int lastMarginBottom = 0
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        // An absolutely positioned box is out of flow: it takes no
        // space here and is laid out by the positioning pass once the
        // containing block it resolves against is known (CSS2 §9.3).
        if boxIsOutOfFlow(c) { continue }
        if boxIsFloated(c) {
            placeFloat(c, cx, cx + cw, y)
            continue
        }
        // `clear` moves this box below the floats on that side. It does
        // not change the float list, so a later box is unaffected.
        if c.style.clearSide != CLEAR_NONE {
            int cl = clearanceY(c.style.clearSide)
            if cl > y { y = cl  prevBottomMargin = 0 }
        }
        int topM = collapsedTopMargin(c, cw)
        bool applied = false
        if first && parentAbsorbsTop {
            // this margin already collapsed through b (see layoutBlock's
            // caller, which used collapsedTopMargin(b))
            applied = true
        } else if !first {
            // sibling collapse: the gap is the larger margin, not the sum
            int gap = maxInt(prevBottomMargin, topM)
            y = y - prevBottomMargin + gap
            applied = true
        }
        int startY = y
        if !applied { y = y + topM }
        int baseY = applied ? y : startY
        layoutBlock(c, cx, baseY, cw, applied)
        if !applied { c.mt = 0 }
        if c.kind == BOX_IMAGE && c.blockLevel { }
        y = c.y + c.h
        int bottomM = collapsedBottomMargin(c, cw)
        y = y + bottomM
        prevBottomMargin = bottomM
        lastMarginBottom = bottomM
        first = false
        b.baseline = c.y - b.y + c.baseline
    }
    if first { return 0 }
    // the last child's bottom margin collapses through b when nothing
    // separates them; otherwise it stays inside
    bool absorbsBottom = b.bb == 0 && b.pb == 0 && lenIsAuto(b.style.height) && (b.kind == BOX_BLOCK || b.kind == BOX_ANON) && b.parentId > 0 && parentKind(b) != BOX_CELL && parentKind(b) != BOX_INLINE_BLOCK
    if absorbsBottom { y = y - lastMarginBottom }
    return y - cy
}

// ---- inline layout --------------------------------------------------------------

// Line-building state, as globals (no closures): the current line's
// fragments, its pen position and the pending collapsible space.
Box ifcBox
int ifcX = 0            // pen x, document coordinates
// The content edges of the block running the inline formatting
// context, kept so a line can be re-measured against the floats beside
// it. Globals are not hoisted, so these live with the rest of the ifc
// state rather than beside the function that uses them.
int ifcCbLeft = 0
int ifcCbRight = 0
int ifcLineStart = 0    // left edge of the line
int ifcLineRight = 0    // right edge
int ifcY = 0            // top of the current line
arr[Fragment] ifcFrags = []
bool ifcPendingSpace = false
int ifcPendingSpaceWidth = 0     // width of the space the pending flag stands for
bool ifcLineHasContent = false
int ifcLineCount = 0
arr[Box] ifcOpenInlines = []
arr[Fragment] ifcOpenBg = []      // the current line's background fragment of each open inline

int func layoutInlineContent(b:Box, cx:int, cy:int, cw:int) {
    Box savedBox = ifcBox
    int savedX = ifcX
    int savedStart = ifcLineStart
    int savedRight = ifcLineRight
    int savedY = ifcY
    arr[Fragment] savedFrags = ifcFrags
    bool savedPending = ifcPendingSpace
    bool savedHas = ifcLineHasContent
    int savedCount = ifcLineCount
    arr[Box] savedOpen = ifcOpenInlines
    arr[Fragment] savedOpenBg = ifcOpenBg

    ifcBox = b
    b.lines = []
    ifcCbLeft = cx
    ifcCbRight = cx + cw
    ifcLineStart = cx
    ifcLineRight = cx + cw
    ifcY = cy
    ifcLineCount = 0
    ifcOpenInlines = []
    ifcOpenBg = []
    beginLine()
    for int i = 0, i < b.children.length, i++ {
        placeInline(b.children[i])
    }
    finishLine(false)
    int h = ifcY - cy
    if b.lines.length > 0 {
        Line last = b.lines[b.lines.length - 1]
        b.baseline = last.baseline - b.y
    }

    ifcBox = savedBox
    ifcX = savedX
    ifcLineStart = savedStart
    ifcLineRight = savedRight
    ifcY = savedY
    ifcFrags = savedFrags
    ifcPendingSpace = savedPending
    ifcLineHasContent = savedHas
    ifcLineCount = savedCount
    ifcOpenInlines = savedOpen
    ifcOpenBg = savedOpenBg
    return h
}

// A line box is shortened by the floats it sits beside. The band used
// is the block's line height, not the finished line's own height, which
// the line does not know until it is closed; they differ only for a
// line with something unusually tall on it.
void func applyFloatsToLine() {
    // Called once per line box. With no float in the document the line
    // is simply the containing block, and the two edge scans and the
    // line-height lookup are all skipped.
    if !docHasFloats {
        ifcLineStart = ifcCbLeft
        ifcLineRight = ifcCbRight
        if ifcX < ifcLineStart { ifcX = ifcLineStart }
        return
    }
    int band = ifcBox == null ? 0 : lineHeightOf(ifcBox.style)
    if band <= 0 { band = 1 }
    int l = floatLeftEdge(ifcCbLeft, ifcY, ifcY + band)
    int r = floatRightEdge(ifcCbRight, ifcY, ifcY + band)
    if r < l { r = l }
    ifcLineStart = l
    ifcLineRight = r
    if ifcX < l { ifcX = l }
}

void func beginLine() {
    ifcFrags = []
    applyFloatsToLine()
    ifcX = ifcLineStart
    if ifcLineCount == 0 && ifcBox.style.textIndent != 0 { ifcX = ifcX + ifcBox.style.textIndent }
    ifcPendingSpace = false
    ifcLineHasContent = false
    // re-open the inline boxes that continue from the previous line
    ifcOpenBg = []
    for int i = 0, i < ifcOpenInlines.length, i++ {
        Box ib = ifcOpenInlines[i]
        Fragment f = newFragment(FRAG_INLINE_BG, ib, '')
        f.x = ifcX
        f.y = ifcY
        f.w = 0
        f.h = 0
        ifcFrags.push(f)
        ifcOpenBg.push(f)
    }
}

// Content now ends at `endX`: every open inline's background on this
// line extends to cover it.
void func extendOpenInlines(endX:int) {
    for int i = 0, i < ifcOpenBg.length, i++ {
        Fragment f = ifcOpenBg[i]
        if endX - f.x > f.w { f.w = endX - f.x }
    }
}

Fragment func newFragment(kind:int, box:Box, t:text) {
    Fragment f
    f.kind = kind
    f.box = box
    f.content = t
    return f
}

// Closes the current line: computes its height and baseline, aligns
// the fragments vertically and horizontally, records it.
void func finishLine(forced:bool) {
    int t0 = archtelosTiming ? now() : 0
    finishLineUncounted(forced)
    if archtelosTiming { profFinishMs = profFinishMs + (now() - t0) }
}

void func finishLineUncounted(forced:bool) {
    // drop a trailing space
    bool any = false
    for int i = 0, i < ifcFrags.length, i++ {
        if ifcFrags[i].kind != FRAG_INLINE_BG { any = true }
    }
    if !any && !forced {
        // an empty line at the end of the content contributes nothing
        if ifcLineCount == 0 && ifcBox.children.length > 0 && !ifcLineHasContent { }
        ifcFrags = []
        return
    }
    // vertical metrics
    int above = 0
    int below = 0
    Style bs = ifcBox.style
    int strutAbove = 0
    int strutBelow = 0
    {
        int lh = lineHeightOf(bs)
        int content = fontAscent(bs) + fontDescent(bs)
        int half = Math.floorDiv(lh - content, 2)
        strutAbove = half + fontAscent(bs)
        strutBelow = lh - strutAbove
    }
    if any || forced {
        above = strutAbove
        below = strutBelow
    }
    for int i = 0, i < ifcFrags.length, i++ {
        Fragment f = ifcFrags[i]
        if f.kind == FRAG_TEXT {
            Style fs = f.box.style
            int lh = lineHeightOf(fs)
            int content = fontAscent(fs) + fontDescent(fs)
            int half = Math.floorDiv(lh - content, 2)
            int a = half + fontAscent(fs)
            int d = lh - a
            int va = fs.verticalAlign
            if va == VALIGN_TOP || va == VALIGN_BOTTOM {
                // approximate: keep on the line, no shift
            }
            above = maxInt(above, a)
            below = maxInt(below, d)
        } else if f.kind == FRAG_ATOMIC {
            Box ab = f.box
            int total = ab.h + ab.mt + ab.mb
            int va = ab.style.verticalAlign
            if va == VALIGN_MIDDLE {
                int mid = roundPx(bs.fontSize.toFloat() * 0.25)
                int a = Math.floorDiv(total, 2) + mid
                above = maxInt(above, a)
                below = maxInt(below, total - a)
            } else if va == VALIGN_TOP || va == VALIGN_BOTTOM {
                int need = total - (above + below)
                if need > 0 { below = below + need }
            } else {
                int a = ab.baseline + ab.mt
                above = maxInt(above, a)
                below = maxInt(below, total - a)
            }
        }
    }
    int lineH = above + below
    int baseline = ifcY + above
    // horizontal alignment
    int used = ifcX - ifcLineStart
    int freeSpace = (ifcLineRight - ifcLineStart) - used
    int shift = 0
    if freeSpace > 0 {
        if bs.textAlign == ALIGN_CENTER { shift = Math.floorDiv(freeSpace, 2) }
        else if bs.textAlign == ALIGN_RIGHT { shift = freeSpace }
    }
    for int i = 0, i < ifcFrags.length, i++ {
        Fragment f = ifcFrags[i]
        f.x = f.x + shift
        if f.kind == FRAG_TEXT {
            Style fs = f.box.style
            int lh = lineHeightOf(fs)
            int content = fontAscent(fs) + fontDescent(fs)
            int half = Math.floorDiv(lh - content, 2)
            f.baseline = baseline
            f.y = baseline - half - fontAscent(fs)
            f.h = lh
            if fs.verticalAlign == VALIGN_TOP {
                f.y = ifcY
                f.baseline = ifcY + half + fontAscent(fs)
            } else if fs.verticalAlign == VALIGN_BOTTOM {
                f.y = ifcY + lineH - lh
                f.baseline = f.y + half + fontAscent(fs)
            }
        } else if f.kind == FRAG_ATOMIC {
            Box ab = f.box
            int total = ab.h + ab.mt + ab.mb
            int top = 0
            int va = ab.style.verticalAlign
            if va == VALIGN_MIDDLE {
                int mid = roundPx(bs.fontSize.toFloat() * 0.25)
                top = baseline - mid - Math.floorDiv(total, 2)
            } else if va == VALIGN_TOP {
                top = ifcY
            } else if va == VALIGN_BOTTOM {
                top = ifcY + lineH - total
            } else {
                top = baseline - ab.baseline - ab.mt
            }
            offsetBox(ab, f.x + ab.ml - ab.x, top + ab.mt - ab.y)
            f.y = top
            f.h = total
            f.baseline = baseline
        } else {
            f.y = ifcY
            f.h = lineH
            f.baseline = baseline
            // shrink vertically to the inline's own font box when the
            // line is taller than it, as CSS does for inline backgrounds
            Style is = f.box.style
            int own = lineHeightOf(is)
            if own < lineH {
                int content = fontAscent(is) + fontDescent(is)
                int half = Math.floorDiv(own - content, 2)
                f.y = baseline - half - fontAscent(is)
                f.h = own
            }
        }
    }
    // inline backgrounds were extended as content was placed; a
    // fragment that never got content (an inline that continued onto
    // the next line with nothing on this one) has no width and is
    // skipped by the painter
    Line ln
    ln.x = ifcLineStart
    ln.y = ifcY
    ln.w = ifcLineRight - ifcLineStart
    ln.h = lineH
    ln.baseline = baseline
    ln.frags = ifcFrags
    ifcBox.lines.push(ln)
    ifcY = ifcY + lineH
    ifcLineCount++
    ifcFrags = []
}

bool func boxIsWithin(b:Box, ancestor:Box) {
    Box cur = b
    int guard = 0
    while cur.id > 0 && guard < 200 {
        if cur.id == ancestor.id { return true }
        if cur.parentId == 0 { return false }
        cur = parentBox(cur)
        guard++
    }
    return false
}

void func breakLine() {
    finishLine(true)
    beginLine()
}

void func placeInline(b:Box) {
    if boxIsOutOfFlow(b) { return }
    if boxIsFloated(b) {
        placeFloat(b, ifcCbLeft, ifcCbRight, ifcY)
        // the float may have narrowed the line that is open
        applyFloatsToLine()
        return
    }
    if b.kind == BOX_TEXT {
        placeText(b)
        return
    }
    if b.kind == BOX_BR {
        breakLine()
        return
    }
    if b.kind == BOX_INLINE {
        resolveEdges(b, ifcLineRight - ifcLineStart)
        // start edge: margin + border + padding
        int startEdge = b.ml + b.bl + b.pl
        Fragment f = newFragment(FRAG_INLINE_BG, b, '')
        if ifcPendingSpace && ifcLineHasContent {
            ifcX = ifcX + ifcPendingSpaceWidth
            ifcPendingSpace = false
        }
        f.x = ifcX
        f.w = startEdge
        f.y = ifcY
        ifcFrags.push(f)
        ifcX = ifcX + startEdge
        extendOpenInlines(ifcX)
        b.x = ifcX
        b.y = ifcY
        ifcOpenInlines.push(b)
        ifcOpenBg.push(f)
        for int i = 0, i < b.children.length, i++ {
            placeInline(b.children[i])
        }
        int endEdge = b.pr + b.br + b.mr
        // the closing edge belongs to the line the content ended on:
        // extend this inline's fragment on the current line
        ifcX = ifcX + endEdge
        extendOpenInlines(ifcX)
        ifcOpenInlines.pop()
        ifcOpenBg.pop()
        if endEdge > 0 { ifcLineHasContent = true }
        return
    }
    // atomic: inline-block or image
    int cw = ifcLineRight - ifcLineStart
    layoutBlock(b, 0, 0, cw, false)
    int total = b.w + b.ml + b.mr
    if ifcPendingSpace && ifcLineHasContent {
        int sw = ifcPendingSpaceWidth
        if ifcX + sw + total > ifcLineRight && ifcBox.style.whiteSpace != WS_NOWRAP {
            breakLine()
        } else {
            ifcX = ifcX + sw
        }
        ifcPendingSpace = false
    } else if ifcLineHasContent && ifcX + total > ifcLineRight && ifcBox.style.whiteSpace != WS_NOWRAP {
        breakLine()
    }
    Fragment f = newFragment(FRAG_ATOMIC, b, '')
    f.x = ifcX
    f.y = ifcY
    f.w = total
    f.h = b.h + b.mt + b.mb
    ifcFrags.push(f)
    ifcX = ifcX + total
    extendOpenInlines(ifcX)
    ifcLineHasContent = true
    ifcPendingSpace = false
}

void func placeText(b:Box) {
    int t0 = archtelosTiming ? now() : 0
    placeTextUncounted(b)
    if archtelosTiming { profPlaceTextMs = profPlaceTextMs + (now() - t0) }
}

void func placeTextUncounted(b:Box) {
    Style s = b.style
    text t = b.content
    if t == null || t == '' { return }
    bool pre = s.whiteSpace == WS_PRE || s.whiteSpace == WS_PRE_WRAP
    bool nowrap = s.whiteSpace == WS_NOWRAP || s.whiteSpace == WS_PRE
    arr[text] words = wordsOf(b)
    int sw = spaceWidth(s)
    if pre {
        for int i = 0, i < words.length, i++ {
            if i > 0 { breakLine() }
            text w = words[i]
            if w == '' { continue }
            int ww = measureWidth(s, w)
            if s.whiteSpace == WS_PRE_WRAP && ifcX + ww > ifcLineRight && ifcLineHasContent {
                placeWrappedWords(b, w.split(' '), sw)
                continue
            }
            appendWord(b, w, ww)
        }
        return
    }
    // leading whitespace
    if words.length > 0 && words[0] == '' {
        if ifcLineHasContent {
            ifcPendingSpace = true
            ifcPendingSpaceWidth = sw
        }
    }
    for int i = 0, i < words.length, i++ {
        text w = words[i]
        if w == '' { continue }
        int ww = measureWidth(s, w)
        int needed = ww
        bool spaceBefore = ifcPendingSpace && ifcLineHasContent
        int spaceW = ifcPendingSpaceWidth
        if spaceBefore { needed = needed + spaceW }
        if ifcLineHasContent && ifcX + needed > ifcLineRight && !nowrap {
            breakLine()
            spaceBefore = false
        }
        if spaceBefore { ifcX = ifcX + spaceW }
        ifcPendingSpace = false
        appendWord(b, w, ww)
        // a space follows every word except the last
        if i < words.length - 1 {
            ifcPendingSpace = true
            ifcPendingSpaceWidth = sw
        }
    }
    // trailing whitespace
    if words.length > 1 && words[words.length - 1] == '' {
        ifcPendingSpace = true
        ifcPendingSpaceWidth = sw
    }
}

void func placeWrappedWords(b:Box, words:arr[text], sw:int) {
    Style s = b.style
    for int i = 0, i < words.length, i++ {
        text w = words[i]
        int ww = w == '' ? 0 : measureWidth(s, w)
        int needed = ww + (i > 0 ? sw : 0)
        if ifcLineHasContent && ifcX + needed > ifcLineRight {
            breakLine()
            needed = ww
        } else if i > 0 {
            ifcX = ifcX + sw
        }
        if w != '' { appendWord(b, w, ww) }
    }
}

// Adds a word to the line, merging with a preceding run of the same
// text box (separated by the space already advanced over).
void func appendWord(b:Box, w:text, ww:int) {
    if ifcFrags.length > 0 {
        Fragment last = ifcFrags[ifcFrags.length - 1]
        if last.kind == FRAG_TEXT && last.box.id == b.id && last.x + last.w <= ifcX {
            int gap = ifcX - (last.x + last.w)
            if gap == 0 {
                last.content = last.content + w
            } else {
                last.content = `${last.content} ${w}`
            }
            last.w = ifcX + ww - last.x
            ifcX = ifcX + ww
            extendOpenInlines(ifcX)
            ifcLineHasContent = true
            return
        }
    }
    Fragment f = newFragment(FRAG_TEXT, b, w)
    f.x = ifcX
    f.y = ifcY
    f.w = ww
    ifcFrags.push(f)
    ifcX = ifcX + ww
    extendOpenInlines(ifcX)
    ifcLineHasContent = true
}

// ---- tables -----------------------------------------------------------------------

struct ColumnInfo {
    minW:int
    maxW:int
    fixedW:int          // px width from a cell, or -1
    pctW:float          // percent width from a cell, or -1
}

int func tableColumnCount(b:Box) {
    int cols = 0
    for int i = 0, i < b.children.length, i++ {
        Box row = b.children[i]
        if row.kind != BOX_ROW { continue }
        int n = 0
        for int j = 0, j < row.children.length, j++ { n = n + row.children[j].colspan }
        cols = maxInt(cols, n)
    }
    return cols
}

arr[ColumnInfo] func tableColumns(b:Box) {
    int cols = tableColumnCount(b)
    arr[ColumnInfo] out = []
    for int i = 0, i < cols, i++ {
        ColumnInfo ci
        ci.fixedW = -1
        ci.pctW = -1.0
        out.push(ci)
    }
    for int i = 0, i < b.children.length, i++ {
        Box row = b.children[i]
        if row.kind != BOX_ROW { continue }
        int col = 0
        for int j = 0, j < row.children.length, j++ {
            Box cell = row.children[j]
            computeIntrinsic(cell)
            int span = cell.colspan
            int minEach = Math.floorDiv(cell.minContent + span - 1, span)
            int maxEach = Math.floorDiv(cell.maxContent + span - 1, span)
            for int k = 0, k < span && col + k < cols, k++ {
                ColumnInfo ci = out[col + k]
                ci.minW = maxInt(ci.minW, minEach)
                ci.maxW = maxInt(ci.maxW, maxEach)
                if span == 1 {
                    if cell.style.width.kind == LEN_PX {
                        int fw = roundPx(cell.style.width.v) + horizontalExtras(cell, 0)
                        ci.fixedW = maxInt(ci.fixedW, fw)
                        ci.maxW = maxInt(ci.maxW, fw)
                    } else if cell.style.width.kind == LEN_PERCENT {
                        ci.pctW = maxInt(roundPx(ci.pctW), roundPx(cell.style.width.v)).toFloat()
                    }
                }
            }
            col = col + span
        }
    }
    return out
}

void func computeTableIntrinsic(b:Box) {
    arr[ColumnInfo] cols = tableColumns(b)
    int spacing = b.style.borderCollapse ? 0 : b.style.borderSpacing
    int minW = spacing
    int maxW = spacing
    for int i = 0, i < cols.length, i++ {
        minW = minW + cols[i].minW + spacing
        maxW = maxW + maxInt(cols[i].maxW, cols[i].fixedW) + spacing
    }
    if b.style.width.kind == LEN_PX {
        int fixed = roundPx(b.style.width.v)
        maxW = maxInt(fixed, minW)
        minW = maxW
    }
    int extras = horizontalExtras(b, 0)
    b.minContent = minW + extras
    b.maxContent = maxW + extras
}

void func layoutTable(b:Box, cx:int, y:int, cw:int) {
    Style s = b.style
    int spacing = s.borderCollapse ? 0 : s.borderSpacing
    arr[ColumnInfo] cols = tableColumns(b)
    int n = cols.length
    int edges = b.pl + b.pr + b.bl + b.br
    int totalMin = spacing
    int totalMax = spacing
    for int i = 0, i < n, i++ {
        totalMin = totalMin + cols[i].minW + spacing
        totalMax = totalMax + maxInt(cols[i].maxW, cols[i].fixedW) + spacing
    }
    int avail = cw - b.ml - b.mr - edges
    int target = 0
    bool fixedWidth = !lenIsAuto(s.width)
    if fixedWidth {
        target = maxInt(resolveLen(s.width, cw, 0), totalMin)
    } else {
        target = minInt(totalMax, avail)
        if target < totalMin { target = totalMin }
    }
    // percent columns first, then distribute what remains
    arr[int] widths = []
    int assigned = spacing
    int flexMax = 0
    int flexMin = 0
    for int i = 0, i < n, i++ {
        ColumnInfo ci = cols[i]
        int w = -1
        if ci.pctW >= 0.0 {
            w = maxInt(roundPx(target.toFloat() * ci.pctW / 100.0), ci.minW)
        } else if ci.fixedW >= 0 {
            w = maxInt(ci.fixedW, ci.minW)
        }
        if w >= 0 {
            assigned = assigned + w + spacing
        } else {
            flexMax = flexMax + maxInt(ci.maxW, 1)
            flexMin = flexMin + ci.minW
        }
        widths.push(w)
    }
    int remaining = target - assigned - (n - countAssigned(widths)) * spacing
    int flexCount = n - countAssigned(widths)
    for int i = 0, i < n, i++ {
        if widths[i] >= 0 { continue }
        ColumnInfo ci = cols[i]
        int w = 0
        if remaining <= flexMin || flexMax == 0 {
            w = ci.minW
        } else if remaining >= flexMax {
            // extra space: share proportionally to max widths
            int extra = remaining - flexMax
            w = maxInt(ci.maxW, 1) + roundPx(extra.toFloat() * maxInt(ci.maxW, 1).toFloat() / flexMax.toFloat())
        } else {
            float f = (remaining - flexMin).toFloat() / maxInt(flexMax - flexMin, 1).toFloat()
            w = ci.minW + roundPx((maxInt(ci.maxW, 1) - ci.minW).toFloat() * f)
        }
        widths[i] = w
    }
    if !fixedWidth && flexCount == 0 { }
    int tableContentW = spacing
    for int i = 0, i < n, i++ { tableContentW = tableContentW + widths[i] + spacing }
    if fixedWidth { tableContentW = maxInt(tableContentW, target) }
    b.w = tableContentW + edges
    // auto margins center the table
    int freeSpace = cw - b.w
    if lenIsAuto(s.marginLeft) && lenIsAuto(s.marginRight) && freeSpace > 0 && (fixedWidth || hasAttr(b.node, 'align')) {
        b.ml = Math.floorDiv(freeSpace, 2)
        b.mr = freeSpace - b.ml
    }
    b.x = cx + b.ml
    b.y = y + b.mt
    int innerX = contentX(b)
    int rowY = contentY(b)
    // A caption goes above the rows or below them, and anything else
    // hoisted in here goes above (CSS Tables 3, `caption-side`).
    bool captionBelow = b.style.captionSide == CAPTION_BOTTOM
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_ROW { continue }
        if captionBelow && c.node != null && htmlTagOf(c.node.id) == 'caption' { continue }
        layoutBlock(c, innerX, rowY, tableContentW, false)
        rowY = c.y + c.h + c.mb
    }
    rowY = rowY + spacing
    int rowIndex = 0
    for int i = 0, i < b.children.length, i++ {
        Box row = b.children[i]
        if row.kind != BOX_ROW { continue }
        resolveEdges(row, tableContentW)
        row.x = innerX
        row.y = rowY
        row.w = tableContentW
        int x = innerX + spacing
        int rowH = 0
        int col = 0
        for int j = 0, j < row.children.length, j++ {
            Box cell = row.children[j]
            int span = cell.colspan
            int w = 0
            for int k = 0, k < span && col + k < n, k++ {
                w = w + widths[col + k]
                if k > 0 { w = w + spacing }
            }
            cell.tableRow = rowIndex
            cell.tableCol = col
            layoutCell(cell, x, rowY, w)
            rowH = maxInt(rowH, cell.h)
            x = x + w + spacing
            col = col + span
        }
        rowIndex++
        text rh = getAttr(row.node, 'height')
        if rh != null && rh.toInt() != null { rowH = maxInt(rowH, rh.toInt()) }
        if row.style.height.kind == LEN_PX { rowH = maxInt(rowH, roundPx(row.style.height.v)) }
        // stretch cells to the row height and apply vertical alignment
        for int j = 0, j < row.children.length, j++ {
            Box cell = row.children[j]
            int extra = rowH - cell.h
            if extra > 0 {
                int va = cell.style.verticalAlign
                text valign = textLower(getAttr(cell.node, 'valign'))
                if valign == 'top' { va = VALIGN_TOP }
                else if valign == 'bottom' { va = VALIGN_BOTTOM }
                else if valign == 'middle' { va = VALIGN_MIDDLE }
                int shift = 0
                if va == VALIGN_MIDDLE || va == VALIGN_BASELINE { shift = Math.floorDiv(extra, 2) }
                else if va == VALIGN_BOTTOM { shift = extra }
                if shift > 0 {
                    for int k = 0, k < cell.children.length, k++ { offsetBox(cell.children[k], 0, shift) }
                    for int k = 0, k < cell.lines.length, k++ {
                        Line ln = cell.lines[k]
                        ln.y = ln.y + shift
                        ln.baseline = ln.baseline + shift
                        for int m = 0, m < ln.frags.length, m++ {
                            Fragment f = ln.frags[m]
                            f.y = f.y + shift
                            f.baseline = f.baseline + shift
                        }
                    }
                }
                cell.h = rowH
            }
        }
        row.h = rowH
        rowY = rowY + rowH + spacing
    }
    // the caption that was held back goes under the last row
    if captionBelow {
        for int i = 0, i < b.children.length, i++ {
            Box c = b.children[i]
            if c.kind == BOX_ROW { continue }
            if c.node == null || htmlTagOf(c.node.id) != 'caption' { continue }
            layoutBlock(c, innerX, rowY, tableContentW, false)
            rowY = c.y + c.h + c.mb
        }
    }
    b.h = rowY - b.y + b.pb + b.bb
    b.baseline = b.h
}

int func countAssigned(widths:arr[int]) {
    int c = 0
    for int i = 0, i < widths.length, i++ { if widths[i] >= 0 { c++ } }
    return c
}

// A cell is a block with a fixed border-box width.
void func layoutCell(cell:Box, x:int, y:int, w:int) {
    resolveEdges(cell, w)
    cell.ml = 0
    cell.mr = 0
    cell.mt = 0
    cell.mb = 0
    cell.x = x
    cell.y = y
    cell.w = w
    int inner = maxInt(w - cell.pl - cell.pr - cell.bl - cell.br, 0)
    int contentH = 0
    if hasInlineContent(cell) {
        contentH = layoutInlineContent(cell, contentX(cell), contentY(cell), inner)
    } else {
        contentH = layoutBlockChildren(cell, contentX(cell), contentY(cell), inner)
    }
    int h = contentH
    if cell.style.height.kind == LEN_PX { h = maxInt(h, roundPx(cell.style.height.v)) }
    text ha = getAttr(cell.node, 'height')
    if ha != null && ha.toInt() != null { h = maxInt(h, ha.toInt()) }
    cell.h = h + cell.pt + cell.pb + cell.bt + cell.bb
    cell.baseline = cell.h
}

// ---- flex layout ------------------------------------------------------
//
// Flexible Box Layout 1, single-line: the items are laid along a main
// axis chosen by flex-direction, grown or shrunk to fill it, spaced by
// justify-content, and aligned across it by align-items. `flex-wrap` is
// not implemented, so every item stays on one line (todo.md).
//
// The axes are handled by asking, once, whether the direction is a row,
// and then reading width-or-height through that answer, which keeps one
// copy of the algorithm rather than two.

bool func flexIsRow(s:Style) {
    return s.flexDirection == FLEX_ROW || s.flexDirection == FLEX_ROW_REVERSE
}

bool func flexIsReverse(s:Style) {
    return s.flexDirection == FLEX_ROW_REVERSE || s.flexDirection == FLEX_COLUMN_REVERSE
}

// The item's base size along the main axis, before growing or shrinking.
int func flexBaseSize(item:Box, row:bool, inner:int) {
    Style s = item.style
    if s.flexBasis.kind != LEN_AUTO {
        return maxInt(resolveLen(s.flexBasis, inner, 0), 0)
    }
    Len own = row ? s.width : s.height
    if !lenIsAuto(own) { return maxInt(resolveLen(own, inner, 0), 0) }
    if row {
        computeIntrinsic(item)
        return maxInt(item.maxContent, 0)
    }
    return 0
}

// Where item `index` starts, relative to where the items would start if
// they were packed flush at the main-start edge. `spare` is the space
// left over once every item's outer main size and every gap is spent.
// (The name avoids `free`, which is a function: see FINDINGS.md,
// "a parameter cannot shadow a function".)
int func flexOffsetFor(justify:int, spare:int, count:int, index:int, gap:int) {
    if spare <= 0 || count <= 0 { return 0 }
    if justify == BOXALIGN_END { return spare }
    if justify == BOXALIGN_CENTRE { return Math.floorDiv(spare, 2) }
    if justify == BOXALIGN_SPACE_BETWEEN {
        // A single item packs to the main-start edge, unlike
        // space-around and space-evenly, which centre it.
        if count < 2 { return 0 }
        return Math.floorDiv(spare * index, count - 1)
    }
    if justify == BOXALIGN_SPACE_AROUND {
        return Math.floorDiv(spare * (index + index + 1), count + count)
    }
    if justify == BOXALIGN_SPACE_EVENLY {
        return Math.floorDiv(spare * (index + 1), count + 1)
    }
    return 0
}

// True when the container has no definite height to distribute, which
// is the case for an auto height and, because this engine resolves no
// percentage heights, for a percentage one too.
bool func flexHeightIndefinite(s:Style) {
    return s.height.kind != LEN_PX
}

// How many of an item's main-axis margins are `auto`. An auto margin
// eats the line's free space before justify-content is consulted, and
// when several are auto they share it equally (Flexbox 1 §8.1).
int func flexAutoMainMargins(it:Box, row:bool) {
    int n = 0
    if row {
        if it.style.marginLeft.kind == LEN_AUTO { n++ }
        if it.style.marginRight.kind == LEN_AUTO { n++ }
    } else {
        if it.style.marginTop.kind == LEN_AUTO { n++ }
        if it.style.marginBottom.kind == LEN_AUTO { n++ }
    }
    return n
}

// Where the lines of a multi-line container sit in the cross axis.
// Same distribution as justify-content, over lines rather than items.
int func flexLineOffsetFor(align:int, spare:int, lines:int, index:int) {
    if spare <= 0 || lines <= 0 { return 0 }
    if align == BOXALIGN_END { return spare }
    if align == BOXALIGN_CENTRE { return Math.floorDiv(spare, 2) }
    if align == BOXALIGN_SPACE_BETWEEN {
        if lines < 2 { return 0 }
        return Math.floorDiv(spare * index, lines - 1)
    }
    if align == BOXALIGN_SPACE_AROUND {
        return Math.floorDiv(spare * (index + index + 1), lines + lines)
    }
    if align == BOXALIGN_SPACE_EVENLY {
        return Math.floorDiv(spare * (index + 1), lines + 1)
    }
    return 0
}

void func layoutFlex(b:Box, cx:int, y:int, cw:int) {
    Style s = b.style
    bool row = flexIsRow(s)
    bool wrap = s.flexWrap != FLEXWRAP_NOWRAP
    bool wrapReverse = s.flexWrap == FLEXWRAP_WRAP_REVERSE
    int innerMain = row ? b.w - b.pl - b.pr - b.bl - b.br : 0
    int flexOriginX = b.x + b.bl + b.pl
    int flexOriginY = b.y + b.bt + b.pt

    // the items, in `order`, skipping anything out of flow
    arr[Box] items = []
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT && textIsCollapsibleBlank(c.content) { continue }
        if boxIsOutOfFlow(c) { continue }
        items.push(c)
    }
    // a stable insertion sort by `order`
    for int i = 1, i < items.length, i++ {
        Box cur = items[i]
        int j = i - 1
        while j >= 0 && items[j].style.order > cur.style.order {
            items[j + 1] = items[j]
            j--
        }
        items[j + 1] = cur
    }

    int mainGap = row ? s.columnGap : s.rowGap
    int crossGap = row ? s.rowGap : s.columnGap
    int count = items.length
    if count == 0 {
        if row && flexHeightIndefinite(s) { b.h = b.pt + b.pb + b.bt + b.bb }
        b.baseline = b.h
        return
    }

    // a first pass to size and measure every item
    arr[int] mainSize = []
    for int i = 0, i < count, i++ {
        Box it = items[i]
        resolveEdges(it, innerMain > 0 ? innerMain : cw)
        mainSize.push(flexBaseSize(it, row, row ? innerMain : cw))
    }

    // The main axis's available size. A column of auto height has none,
    // and a container with none never wraps: there is no size to
    // overflow.
    int mainAvail = row ? innerMain : (flexHeightIndefinite(s) ? -1 : b.h - b.pt - b.pb - b.bt - b.bb)

    // ---- break the items into lines ----------------------------------
    arr[int] lineFirst = []
    arr[int] lineLast = []
    if !wrap || mainAvail < 0 {
        lineFirst.push(0)
        lineLast.push(count - 1)
    } else {
        int start = 0
        int run = 0
        for int i = 0, i < count, i++ {
            Box it = items[i]
            int outer = mainSize[i] + (row ? it.ml + it.mr : it.mt + it.mb)
            int add = i > start ? mainGap + outer : outer
            if i > start && run + add > mainAvail {
                lineFirst.push(start)
                lineLast.push(i - 1)
                start = i
                run = outer
            } else {
                run = run + add
            }
        }
        lineFirst.push(start)
        lineLast.push(count - 1)
    }
    int lines = lineFirst.length

    int crossAvail = row
        ? (flexHeightIndefinite(s) ? -1 : b.h - b.pt - b.pb - b.bt - b.bb)
        : b.w - b.pl - b.pr - b.bl - b.br

    // ---- resolve each line's flexible lengths, and lay its items out --
    // Growing and shrinking happen within a line, never across the
    // container: an item alone on the last line takes all of its own
    // free space.
    arr[int] lineCross = []
    arr[int] lineBaseline = []
    arr[int] lineLeftover = []
    arr[int] lineAutoMargins = []
    for int li = 0, li < lines, li++ {
        int first = lineFirst[li]
        int last = lineLast[li]
        int n = last - first + 1
        int totalMain = 0
        float totalGrow = 0.0
        float totalShrink = 0.0
        int autos = 0
        for int i = first, i <= last, i++ {
            Box it = items[i]
            totalMain = totalMain + mainSize[i] + (row ? it.ml + it.mr : it.mt + it.mb)
            totalGrow = totalGrow + it.style.flexGrow
            totalShrink = totalShrink + it.style.flexShrink
            autos = autos + flexAutoMainMargins(it, row)
        }
        int gapTotal = mainGap * (n - 1)
        int spare = mainAvail < 0 ? 0 : mainAvail - totalMain - gapTotal
        // An auto margin absorbs the free space, so nothing is left for
        // flex-grow to take.
        // Distribute by rounding the running total rather than each
        // share on its own: three items sharing 400px are 133, 134, 133
        // and start at 0, 133 and 267, which is where a browser puts
        // them. Rounding each share alone loses a pixel off the end.
        if spare > 0 && autos == 0 && totalGrow > 0.0 {
            float acc = 0.0
            int handed = 0
            for int i = first, i <= last, i++ {
                acc = acc + items[i].style.flexGrow / totalGrow
                int upto = i == last ? spare : roundPx(spare.toFloat() * acc)
                mainSize[i] = mainSize[i] + (upto - handed)
                handed = upto
            }
            spare = 0
        } else if spare < 0 && totalShrink > 0.0 {
            int owed = 0 - spare
            float acc = 0.0
            int taken = 0
            for int i = first, i <= last, i++ {
                acc = acc + items[i].style.flexShrink / totalShrink
                int upto = i == last ? owed : roundPx(owed.toFloat() * acc)
                int cut = upto - taken
                if cut > mainSize[i] { cut = mainSize[i] }
                mainSize[i] = mainSize[i] - cut
                taken = taken + cut
            }
            spare = 0
        }
        if spare < 0 { spare = 0 }
        lineLeftover.push(spare)
        lineAutoMargins.push(autos)

        // lay the items out at their resolved main size, and measure
        // how far the line reaches across. Baseline-aligned items are
        // measured twice over: the line has to be deep enough for the
        // deepest baseline plus whatever hangs below the deepest of
        // those, which is not the same as the tallest item.
        int maxCross = 0
        int maxBase = 0
        int maxBelow = 0
        for int i = first, i <= last, i++ {
            Box item = items[i]
            if row {
                item.forcedWidthPx = mainSize[i]
                layoutBlock(item, flexOriginX, flexOriginY, mainSize[i] + item.ml + item.mr, false)
                item.forcedWidthPx = -1
                int outer = item.h + item.mt + item.mb
                if outer > maxCross { maxCross = outer }
                int al = item.style.alignSelf == BOXALIGN_AUTO ? s.alignItems : item.style.alignSelf
                if al == BOXALIGN_BASELINE {
                    int base = item.baseline + item.mt
                    if base > maxBase { maxBase = base }
                    if outer - base > maxBelow { maxBelow = outer - base }
                }
            } else {
                layoutBlock(item, flexOriginX, flexOriginY, crossAvail, false)
                if !lenIsAuto(item.style.height) || item.style.flexBasis.kind != LEN_AUTO {
                    item.h = mainSize[i]
                } else {
                    mainSize[i] = item.h
                }
                int outer = item.w + item.ml + item.mr
                if outer > maxCross { maxCross = outer }
            }
        }
        if maxBase + maxBelow > maxCross { maxCross = maxBase + maxBelow }
        lineCross.push(maxCross)
        lineBaseline.push(maxBase)
    }

    // ---- give the lines their share of the cross axis -----------------
    int crossUsed = 0
    for int li = 0, li < lines, li++ { crossUsed = crossUsed + lineCross[li] }
    crossUsed = crossUsed + crossGap * (lines - 1)
    int crossSpare = crossAvail < 0 ? 0 : crossAvail - crossUsed
    if crossSpare < 0 { crossSpare = 0 }
    // align-content stretch hands the free cross space to the lines
    // themselves, which is what makes a line of height-less items fill
    // half a container.
    if crossSpare > 0 && s.alignContent == BOXALIGN_STRETCH {
        int handed = 0
        for int li = 0, li < lines, li++ {
            int upto = li == lines - 1
                ? crossSpare
                : roundPx(crossSpare.toFloat() * (li + 1).toFloat() / lines.toFloat())
            lineCross[li] = lineCross[li] + (upto - handed)
            handed = upto
        }
        crossSpare = 0
    }

    // ---- place every line, and every item within its line -------------
    int crossCursor = 0
    for int li = 0, li < lines, li++ {
        int first = lineFirst[li]
        int last = lineLast[li]
        int n = last - first + 1
        int thisCross = lineCross[li]
        int lineOffset = flexLineOffsetFor(s.alignContent, crossSpare, lines, li)
        int crossStart = crossCursor + lineOffset
        // wrap-reverse flips the cross axis: the first line ends up
        // furthest from the cross-start edge.
        if wrapReverse && crossAvail >= 0 {
            crossStart = crossAvail - crossStart - thisCross
        }

        int leftover = lineLeftover[li]
        int autos = lineAutoMargins[li]
        int autoShare = autos > 0 ? Math.floorDiv(leftover, autos) : 0
        int cursor = 0
        int autoSeen = 0
        for int k = 0, k < n, k++ {
            int idx = flexIsReverse(s) ? last - k : first + k
            Box item = items[idx]
            int size = mainSize[idx]
            int align = item.style.alignSelf == BOXALIGN_AUTO ? s.alignItems : item.style.alignSelf
            int leadAuto = 0
            if autos > 0 {
                bool leadIsAuto = row
                    ? item.style.marginLeft.kind == LEN_AUTO
                    : item.style.marginTop.kind == LEN_AUTO
                if leadIsAuto {
                    autoSeen++
                    leadAuto = autoSeen == autos ? leftover - autoShare * (autos - 1) : autoShare
                }
            }

            // stretch fills the line's own cross size, not the container's
            if align == BOXALIGN_STRETCH && thisCross > 0 {
                if row && lenIsAuto(item.style.height) {
                    item.h = thisCross - item.mt - item.mb
                } else if !row && lenIsAuto(item.style.width) {
                    item.w = thisCross - item.ml - item.mr
                }
            }

            int offset = autos > 0 ? 0 : flexOffsetFor(s.justifyContent, leftover, n, k, mainGap)
            int mainPos = cursor + offset + leadAuto
            int crossPos = 0
            int itemCross = row ? item.h + item.mt + item.mb : item.w + item.ml + item.mr
            if align == BOXALIGN_BASELINE && row {
                // sit so this item's baseline meets the line's
                crossPos = lineBaseline[li] - item.baseline - item.mt
                if crossPos < 0 { crossPos = 0 }
            } else if thisCross > 0 && itemCross < thisCross {
                if align == BOXALIGN_CENTRE { crossPos = Math.floorDiv(thisCross - itemCross, 2) }
                else if align == BOXALIGN_END { crossPos = thisCross - itemCross }
                // wrap-reverse also flips which end of its own line an
                // item aligns to.
                if wrapReverse && (align == BOXALIGN_START || align == BOXALIGN_STRETCH) {
                    crossPos = thisCross - itemCross
                } else if wrapReverse && align == BOXALIGN_END {
                    crossPos = 0
                }
            }
            if row {
                shiftBoxTree(item, flexOriginX + mainPos + item.ml - item.x,
                                   flexOriginY + crossStart + crossPos + item.mt - item.y)
            } else {
                shiftBoxTree(item, flexOriginX + crossStart + crossPos + item.ml - item.x,
                                   flexOriginY + mainPos + item.mt - item.y)
            }
            int trailAuto = 0
            if autos > 0 {
                bool trailIsAuto = row
                    ? item.style.marginRight.kind == LEN_AUTO
                    : item.style.marginBottom.kind == LEN_AUTO
                if trailIsAuto {
                    autoSeen++
                    trailAuto = autoSeen == autos ? leftover - autoShare * (autos - 1) : autoShare
                }
            }
            cursor = cursor + size + mainGap + leadAuto + trailAuto
                   + (row ? item.ml + item.mr : item.mt + item.mb)
        }
        crossCursor = crossCursor + thisCross + crossGap
    }

    // an auto cross size fits the lines
    if flexHeightIndefinite(s) {
        if row {
            b.h = crossUsed + b.pt + b.pb + b.bt + b.bb
        } else {
            int total = 0
            for int i = 0, i < count, i++ {
                Box it = items[i]
                total = total + mainSize[i] + it.mt + it.mb
            }
            b.h = total + mainGap * (count - 1) + b.pt + b.pb + b.bt + b.bb
        }
    }
    b.baseline = b.h
}

// ---- floats -----------------------------------------------------------
//
// A float is taken out of the flow but not out of the picture: it is
// placed at an edge of its containing block, and the LINE boxes beside
// it are shortened so text wraps around it. A block box's own position
// and width ignore floats entirely, which is why a block can sit
// underneath one, and `clear` is what moves a block below them
// (CSS2 §9.5).
//
// Every rectangle here is in document coordinates, like every other
// box, so one list serves the whole block formatting context.

struct FloatRect {
    left:int
    top:int
    right:int
    bottom:int
    side:int
}

arr[FloatRect] bfcFloats = []

void func resetFloats() {
    bfcFloats = []
}

// The left edge available to content in the band [top, bottom).
int func floatLeftEdge(cbLeft:int, top:int, bottom:int) {
    int edge = cbLeft
    for int i = 0, i < bfcFloats.length, i++ {
        FloatRect f = bfcFloats[i]
        if f.side != FLOAT_LEFT { continue }
        if f.bottom <= top || f.top >= bottom { continue }
        if f.right > edge { edge = f.right }
    }
    return edge
}

int func floatRightEdge(cbRight:int, top:int, bottom:int) {
    int edge = cbRight
    for int i = 0, i < bfcFloats.length, i++ {
        FloatRect f = bfcFloats[i]
        if f.side != FLOAT_RIGHT { continue }
        if f.bottom <= top || f.top >= bottom { continue }
        if f.left < edge { edge = f.left }
    }
    return edge
}

// The next y at which the band gets wider than it is at `top`.
int func nextFloatBottom(top:int) {
    int best = -1
    for int i = 0, i < bfcFloats.length, i++ {
        FloatRect f = bfcFloats[i]
        if f.bottom <= top { continue }
        if best < 0 || f.bottom < best { best = f.bottom }
    }
    return best
}

// The lowest bottom edge of the floats on the given side, which is
// where `clear` puts a box.
int func clearanceY(side:int) {
    int y = -1
    for int i = 0, i < bfcFloats.length, i++ {
        FloatRect f = bfcFloats[i]
        if side == CLEAR_LEFT && f.side != FLOAT_LEFT { continue }
        if side == CLEAR_RIGHT && f.side != FLOAT_RIGHT { continue }
        if f.bottom > y { y = f.bottom }
    }
    return y
}

// Lays a floated box out and places it: at the top of the band it fits
// in, against the near edge, after anything already floated there.
void func placeFloat(b:Box, cbLeft:int, cbRight:int, startY:int) {
    int avail = cbRight - cbLeft
    layoutBlock(b, cbLeft, startY, avail, false)
    int w = b.w + b.ml + b.mr
    int h = b.h + b.mt + b.mb
    int y = startY
    // `clear` on a float applies to the float itself.
    if b.style.clearSide != CLEAR_NONE {
        int c = clearanceY(b.style.clearSide)
        if c > y { y = c }
    }
    int guard = 0
    while guard < 100 {
        guard++
        int bandBottom = h > 0 ? y + h : y + 1
        int l = floatLeftEdge(cbLeft, y, bandBottom)
        int r = floatRightEdge(cbRight, y, bandBottom)
        if r - l >= w || r - l >= avail {
            int x = b.style.floatSide == FLOAT_LEFT ? l : r - w
            shiftBoxTree(b, x + b.ml - b.x, y + b.mt - b.y)
            FloatRect rect
            rect.left = x
            rect.top = y
            rect.right = x + w
            rect.bottom = y + h
            rect.side = b.style.floatSide
            bfcFloats.push(rect)
            return
        }
        int nb = nextFloatBottom(y)
        if nb <= y { nb = y + 1 }
        y = nb
    }
}

bool func boxIsFloated(b:Box) {
    if !docHasFloats { return false }
    if b == null { return false }
    if b.kind == BOX_TEXT || b.kind == BOX_BR || b.kind == BOX_ANON { return false }
    if b.node == null { return false }
    if boxIsOutOfFlow(b) { return false }
    return b.style.floatSide != FLOAT_NONE
}

// ---- positioned boxes -------------------------------------------------
//
// Everything above lays out the ordinary flow. This pass walks the
// finished tree once and does what `position` asks for (CSS2 §9.3):
//
//   relative  the box keeps its place in the flow and is drawn offset
//             from it, carrying its descendants along.
//   absolute  the box is out of flow and resolves against the padding
//             box of its nearest positioned ancestor.
//   fixed     the same, against the viewport.
//
// Left and top win over right and bottom when both are given, which is
// what the standard says for left-to-right writing.

void func shiftBoxTree(b:Box, dx:int, dy:int) {
    if b == null { return }
    b.x = b.x + dx
    b.y = b.y + dy
    for int i = 0, i < b.lines.length, i++ {
        Line ln = b.lines[i]
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            f.x = f.x + dx
            f.y = f.y + dy
            f.baseline = f.baseline + dy
        }
    }
    for int i = 0, i < b.children.length, i++ { shiftBoxTree(b.children[i], dx, dy) }
}

// The containing block an absolutely positioned box resolves against:
// the padding box of the nearest positioned ancestor. These four are
// threaded as globals through the recursion rather than as a struct,
// for the reason recorded in FINDINGS.md about forwarded structs.
int posCbX = 0
int posCbY = 0
int posCbW = 0
int posCbH = 0

void func layoutPositioned(b:Box, cbX:int, cbY:int, cbW:int, cbH:int,
                           viewW:int, viewH:int) {
    if b == null { return }

    // An out-of-flow box has no geometry yet: give it one against its
    // containing block before deciding where to put it.
    if boxIsOutOfFlow(b) {
        int useX = b.style.position == POS_FIXED ? 0 : cbX
        int useY = b.style.position == POS_FIXED ? 0 : cbY
        int useW = b.style.position == POS_FIXED ? viewW : cbW
        int useH = b.style.position == POS_FIXED ? viewH : cbH
        layoutBlock(b, useX, useY, useW, false)
        Style s = b.style
        int w = b.w + b.ml + b.mr
        int h = b.h + b.mt + b.mb
        int wantX = b.x
        int wantY = b.y
        if !lenIsAuto(s.left) {
            wantX = useX + resolveLen(s.left, useW, 0) + b.ml
        } else if !lenIsAuto(s.right) {
            wantX = useX + useW - resolveLen(s.right, useW, 0) - w + b.ml
        }
        if !lenIsAuto(s.top) {
            wantY = useY + resolveLen(s.top, useH, 0) + b.mt
        } else if !lenIsAuto(s.bottom) {
            wantY = useY + useH - resolveLen(s.bottom, useH, 0) - h + b.mt
        }
        // The line fragments inside were placed where the box was laid
        // out, so the whole subtree moves rather than just the box.
        if wantX != b.x || wantY != b.y { shiftBoxTree(b, wantX - b.x, wantY - b.y) }
    }

    // A relatively positioned box moves, with everything inside it.
    if b.style.position == POS_RELATIVE && boxIsPositioned(b) {
        Style s = b.style
        int dx = 0
        int dy = 0
        if !lenIsAuto(s.left) { dx = resolveLen(s.left, cbW, 0) }
        else if !lenIsAuto(s.right) { dx = 0 - resolveLen(s.right, cbW, 0) }
        if !lenIsAuto(s.top) { dy = resolveLen(s.top, cbH, 0) }
        else if !lenIsAuto(s.bottom) { dy = 0 - resolveLen(s.bottom, cbH, 0) }
        if dx != 0 || dy != 0 { shiftBoxTree(b, dx, dy) }
    }

    // This box becomes the containing block for its descendants if it
    // is positioned at all.
    int nx = cbX
    int ny = cbY
    int nw = cbW
    int nh = cbH
    if boxIsPositioned(b) {
        nx = b.x + b.bl
        ny = b.y + b.bt
        nw = b.w - b.bl - b.br
        nh = b.h - b.bt - b.bb
    }
    for int i = 0, i < b.children.length, i++ {
        layoutPositioned(b.children[i], nx, ny, nw, nh, viewW, viewH)
    }
}

// ---- entry points ----------------------------------------------------------------

// Lays out a styled document in a viewport `width` px wide. Returns
// the root box; its height is the document height.
Box func layoutDocument(doc:Node, width:int) {
    nextBoxId = 1
    boxRegistry = [null]
    // One float list for the document. Properly a float belongs to its
    // block formatting context and cannot escape it, but nothing here
    // establishes one yet (todo.md); what matters for now is that a
    // second layout does not inherit the first one's floats.
    resetFloats()
    docHasPositioned = false
    docHasFloats = false
    currentFontKey = ''         // the canvas font may have been changed behind our back
    Node html = findElement(doc, 'html')
    if html == null { return null }
    int t0 = archtelosTiming ? now() : 0
    Box root = buildBox(html, html.style)
    if archtelosTiming { profBuildMs = profBuildMs + (now() - t0) }
    if root == null { return null }
    root.depth = 0
    // the root box: the top margin of body collapses into it
    // NOTE: topM is the margin that collapses into the root, and it is
    // dropped when it collapses all the way through -- see todo.md,
    // "a margin that collapses through to the root". Applying it here
    // double-counts the ordinary case, where layoutBlock already does.
    int topM = collapsedTopMargin(root, width)
    layoutBlock(root, 0, 0, width, false)
    // The initial containing block is the viewport: as wide as the
    // layout and as tall as the document turned out to be. A document
    // with no positioned box skips the walk entirely.
    if docHasPositioned {
        layoutPositioned(root, 0, 0, width, root.h, width, cssViewportHeight)
    }
    return root
}

// Assigns list ordinals to list-item boxes (after building).
void func numberListItems(b:Box) {
    int n = 0
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.isListItem {
            n++
            text v = getAttr(c.node, 'value')
            if v != null && v.toInt() != null { n = v.toInt() }
            c.listIndex = n
        }
        numberListItems(c)
    }
}

// A geometry dump for tests: one line per box and per text fragment.
text func dumpLayout(b:Box, indent:int) {
    text pad = repeatText('  ', indent)
    text name = b.kind == BOX_ANON ? '(anon)' : (b.kind == BOX_TEXT ? '#text' : b.node.tag)
    text out = `${pad}${name} ${b.x},${b.y} ${b.w}x${b.h}\n`
    for int i = 0, i < b.lines.length, i++ {
        Line ln = b.lines[i]
        text lineOut = `${pad}  line ${ln.y} h=${ln.h} base=${ln.baseline}\n`
        out = out + lineOut
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            if f.kind == FRAG_TEXT {
                text fo = `${pad}    "${f.content}" ${f.x},${f.y} ${f.w}x${f.h}\n`
                out = out + fo
            } else if f.kind == FRAG_ATOMIC {
                text fo = `${pad}    [${f.box.node.tag}] ${f.x},${f.y} ${f.w}x${f.h}\n`
                out = out + fo
            } else if f.w > 0 {
                text fo = `${pad}    <${f.box.node.tag}> ${f.x},${f.y} ${f.w}x${f.h}\n`
                out = out + fo
            }
        }
    }
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        if c.kind == BOX_INLINE {
            text sub = dumpInlineAtomics(c, indent + 1)
            out = out + sub
            continue
        }
        text child = dumpLayout(c, indent + 1)
        out = out + child
    }
    return out
}

text func dumpInlineAtomics(b:Box, indent:int) {
    text out = ''
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        if c.kind == BOX_INLINE {
            text sub = dumpInlineAtomics(c, indent)
            out = out + sub
        } else {
            text child = dumpLayout(c, indent)
            out = out + child
        }
    }
    return out
}


// ---- helpers for the tests --------------------------------------------

Box func findBoxForTag(root:Box, tag:text) {
    if root == null { return null }
    if root.node != null && htmlTagOf(root.node.id) == tag { return root }
    for int i = 0, i < root.children.length, i++ {
        Box f = findBoxForTag(root.children[i], tag)
        if f != null { return f }
    }
    return null
}

bool func boxTreeHasText(root:Box, needle:text) {
    if root == null { return false }
    if root.kind == BOX_TEXT && root.content != null {
        ascii hay = root.content.toAscii()
        ascii nd = needle.toAscii()
        if hay != null && nd != null && asciiIndexOf(hay, nd, 0) >= 0 { return true }
    }
    for int i = 0, i < root.children.length, i++ {
        if boxTreeHasText(root.children[i], needle) { return true }
    }
    return false
}

// Collects every box generated by a given tag, in tree order.
void func collectBoxesForTag(root:Box, tag:text, out:arr[Box]) {
    if root == null { return }
    if root.node != null && htmlTagOf(root.node.id) == tag { out.push(root) }
    for int i = 0, i < root.children.length, i++ {
        collectBoxesForTag(root.children[i], tag, out)
    }
}
