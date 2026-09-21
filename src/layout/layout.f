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
import ../css/shapes.f
import ../util/bidi.f

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
const int BOX_GRID = 14

// The size Chromium draws an audio element's controls at, which is what
// a page laid out against it expects to find.
const int AUDIO_CONTROLS_W = 300
const int AUDIO_CONTROLS_H = 54

const int FRAG_TEXT = 1
const int FRAG_ATOMIC = 2
const int FRAG_INLINE_BG = 3

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
    controlKind:int         // CONTROL_CHECK, CONTROL_FIELD, or neither
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
    // The scrollbars this box reserves room for, and the content they
    // scroll, which is what sizes their thumbs.
    //
    // Whether the box *scrolls* on an axis is a separate question from
    // how much room its bar took, because `scrollbar-width: none` takes
    // no room and still scrolls: it hides the bar rather than the
    // scrolling. Everything that draws a bar or is asked where one was
    // clicked reads `sbW` and `sbH`; everything that scrolls reads these.
    scrollsX:bool
    scrollsY:bool
    sbW:int
    sbH:int
    // The gutter `scrollbar-gutter: stable both-edges` reserves on the
    // inline-start side, which no bar is ever drawn in: it is there so
    // the content sits centred between two equal gutters. contentX adds
    // it, which is the one place a box's content left edge is decided.
    sbLeft:int
    scrollW:int
    scrollH:int
    // The min-content width of the contents alone, before a declared
    // `width` replaces it. Flexible Box 1 §4.5 wants that one: an item's
    // automatic minimum is the smaller of what it declared and what its
    // content needs, so the two have to be kept apart.
    contentMin:int
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
    edges:int
}

// Which of its inline's own side edges a fragment carries. An inline
// broken across lines puts its opening margin, border and padding on
// the fragment that begins it and its closing ones on the fragment
// that ends it; the fragments between carry neither (CSS2 8.4).
const int FRAGEDGE_NONE = 0
const int FRAGEDGE_START = 1
const int FRAGEDGE_END = 2
const int FRAGEDGE_BOTH = 3

bool func fragOpens(f:Fragment) {
    return f.edges == FRAGEDGE_START || f.edges == FRAGEDGE_BOTH
}

bool func fragCloses(f:Fragment) {
    return f.edges == FRAGEDGE_END || f.edges == FRAGEDGE_BOTH
}

struct Line {
    x:int
    y:int
    w:int
    h:int
    baseline:int
    frags:arr[Fragment]
}

// How far any inline box on this document reaches outside the line box
// it sits on. An inline's decorations go on its content area grown by
// its padding and border, which can be taller than the line, so the
// painter widens both of its culls by this rather than trusting a line
// box or a block's own height to contain its ink. A document with no
// padded or bordered inline leaves it at zero, and the culls are then
// exactly what they were.
int inlineInkOverhang = 0

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

// ---- CSS Anchor Positioning: anchor-size() ---------------------------
//
// What each `anchor-size()` resolved to on the pass before this one, in
// pixels, keyed by `<node id>:<slot>`. By NODE id and not box id: a
// second layout rebuilds the box tree from scratch and the box ids
// start again, so a box id carried across a pass names a different box
// or none.
//
// A size cannot wait for the positioning pass the way a placement can.
// `anchor()` in an inset is resolved after the tree is laid out,
// because moving a laid-out box is a shift; a size has to be there
// before the box is laid out at all, and the anchor has no rectangle
// until the layout it is measured from has finished. So this is filled
// in by one layout and read by the next.
map[int] anchorSizePx = {}
bool anchorSizeChanged = false

// The pixels an `anchor-size()` in this slot resolved to, or -1 where
// this box said nothing. Every caller asks `anyAnchorSize` before
// calling rather than leaving the test to the first line here: these
// sites are in the width and height of every box on every page, and a
// call that returns -1 is still a call.
int func anchorSizeFor(b:Box, slot:int) {
    if !anyAnchorSize || b == null || b.node == null || b.node.id <= 0 { return -1 }
    int v = anchorSizePx[`${b.node.id}:${slot}`]
    return v == null ? -1 : v
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

// white-space is two independent questions, and these are the two.
// `preserve-breaks` -- `white-space: pre-line` -- answers them
// differently from each other, which is why the pair cannot be one
// enum: it keeps newlines while still collapsing spaces.
bool func wsKeepsSpaces(s:Style) { return s.whiteSpaceCollapse == WSC_PRESERVE }
bool func wsKeepsBreaks(s:Style) { return s.whiteSpaceCollapse != WSC_COLLAPSE }
bool func wsNoWrap(s:Style) { return s.textWrapMode == WRAP_NOWRAP }

// What a tab expands to. tab-size is either a count of spaces or a
// length; a length is turned back into the nearest whole number of
// spaces, because a tab is expanded into the text before the line is
// measured rather than resolved against the position it lands at.
text func tabAdvance(s:Style) {
    int n = s.tabSize
    if s.tabSizePx >= 0 {
        int sw = spaceWidth(s)
        n = sw > 0 ? Math.floorDiv(s.tabSizePx, sw) : 0
    }
    text out = ''
    for int i = 0, i < n, i++ { out = out + ' ' }
    return out
}

// A whitespace-only text node disappears when whitespace collapses.
// Under `pre-line` it disappears too, unless it holds a newline, which
// is preserved and so still breaks the line.
bool func wsDropsBlank(s:Style, content:text) {
    if s.whiteSpaceCollapse == WSC_COLLAPSE { return true }
    if s.whiteSpaceCollapse == WSC_PRESERVE { return false }
    return content.split('\n').length == 1
}

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

// How far above the baseline `text-box-trim` trims the first line to,
// or -1 when this block does not trim that end. A trim removes all the
// leading, so the answer is a font edge rather than a share of it.
int func textBoxOverEdge(s:Style) {
    int packed = textBoxPacked(s)
    if packed < 0 { return -1 }
    int trim = Math.floorDiv(packed, 16)
    if trim != TBTRIM_START && trim != TBTRIM_BOTH { return -1 }
    int over = Math.floorDiv(packed % 16, 4)
    if over == TBOVER_CAP { return capHeight(s) }
    if over == TBOVER_EX { return roundPx(s.fontSize.toFloat() * FONT_EX) }
    return roundPx(s.fontSize.toFloat() * FONT_ASCENT)
}

// And how far below it trims the last line to, or -1.
int func textBoxUnderEdge(s:Style) {
    int packed = textBoxPacked(s)
    if packed < 0 { return -1 }
    int trim = Math.floorDiv(packed, 16)
    if trim != TBTRIM_END && trim != TBTRIM_BOTH { return -1 }
    if packed % 4 == TBUNDER_ALPHABETIC { return 0 }
    return roundPx(s.fontSize.toFloat() * FONT_DESCENT)
}

// The cap height, floored rather than rounded: see FONT_CAP in
// src/css/style.f for the measurement that says so.
int func capHeight(s:Style) {
    return Math.floor(s.fontSize.toFloat() * FONT_CAP)
}

int func fontDescent(s:Style) {
    return roundPx(s.fontSize.toFloat() * FONT_DESCENT)
}

// ---- box construction ----------------------------------------------------

// Whether this document contains any positioned or floated box at all.
// Both cost an extra pass over the tree -- layoutPositioned, and the
// two-pass z-index child ordering in the painter -- and most pages have
// neither. The flags are set once while the box tree is built and read
// wherever a pass can be skipped whole.
bool docHasPositioned = false

// Where an out-of-flow box would have been in flow, keyed by box id --
// its static position (CSS2 §10.3.7), which is what an `auto` inset
// resolves to. The flow already walks past these boxes; this is the pen
// at the moment it does. A document with nothing positioned never grows
// them, because `docHasPositioned` guards the writes, the read and the
// reset alike.
map[int] staticPosX = {}
map[int] staticPosY = {}
bool docHasFloats = false
// Set while the box tree is built when any text holds a right-to-left
// character. A page with none never runs the bidirectional algorithm
// at all (CLAUDE.md, "a feature must not cost anything to the pages
// that do not use it").
bool anyRtlText = false

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
    s.whiteSpaceCollapse = parent.whiteSpaceCollapse
    s.textWrapMode = parent.textWrapMode
    s.textAlignLast = parent.textAlignLast
    s.wordBreaking = parent.wordBreaking
    s.tabSize = parent.tabSize
    s.tabSizePx = parent.tabSizePx
    s.orphans = parent.orphans
    s.widows = parent.widows
    s.listStyle = parent.listStyle
    s.listStyleName = parent.listStyleName
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
    return b.kind == BOX_INLINE || b.kind == BOX_TEXT || b.kind == BOX_INLINE_BLOCK || b.kind == BOX_IMAGE || b.kind == BOX_IFRAME || b.kind == BOX_BR || b.kind == BOX_FLEX || b.kind == BOX_GRID || b.kind == BOX_TABLE || b.kind == BOX_AUDIO
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

// Which of the two kinds of control this is, for the two things that
// depend on it: the size the user agent supplies for a checkbox or a
// radio, and the field width a text-like input gets when it is not
// sized by its content (CSS UI 4).
const int CONTROL_NONE = 0
const int CONTROL_CHECK = 1     // checkbox or radio: a square the UA draws
const int CONTROL_FIELD = 2     // a text-like field, as wide as `size` says

// A field is twenty characters wide by default, which is what HTML's
// `size` attribute defaults to and what makes an empty text input a
// field rather than a few pixels.
const int FIELD_DEFAULT_CHARS = 20
const int CHECK_CONTROL_PX = 13

int func formControlKind(n:Node) {
    if n.tag != 'input' { return CONTROL_NONE }
    text ty = textLower(getAttr(n, 'type'))
    if ty == null || ty == '' { ty = 'text' }
    if ty == 'checkbox' || ty == 'radio' { return CONTROL_CHECK }
    if ty == 'text' || ty == 'search' || ty == 'email' || ty == 'url'
        || ty == 'tel' || ty == 'number' || ty == 'password' { return CONTROL_FIELD }
    return CONTROL_NONE
}

// How many characters wide a field is: its `size` attribute, or twenty.
int func fieldCharCount(n:Node) {
    text sz = getAttr(n, 'size')
    if sz == null { return FIELD_DEFAULT_CHARS }
    int got = sz.toInt()
    if got == null || got <= 0 { return FIELD_DEFAULT_CHARS }
    return minInt(got, 1000)
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
    if !anyRtlText && bidiNeedsReorder(b.content) { anyRtlText = true }
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
    // CSS Content 3 §2.1: an element whose `content` names an image is
    // a replaced element showing that image. Its own box properties
    // still apply -- this is the element's box, with the element's
    // background, border and declared size -- and its children are not
    // rendered, the same rule as an <iframe>'s. The box is built even
    // when the image did not load, because what the standard replaces
    // is the contents, not the pixels: Chromium 141 gives a block with
    // a failed `content` image no content and no line box either.
    if s.contentUrl != '' {
        Box cb = newBox(BOX_IMAGE, n, s)
        img shown = loadedImages[s.contentUrl]
        if shown != null {
            cb.image = shown
            cb.imgW = shown.width
            cb.imgH = shown.height
        }
        cb.blockLevel = displayIsBlockLevel(d)
        return cb
    }
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
        b.controlKind = formControlKind(n)
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
        blockifyItems(b)
        return b
    }
    if d == DISPLAY_GRID || d == DISPLAY_INLINE_GRID {
        Box b = newBox(BOX_GRID, n, s)
        b.blockLevel = d == DISPLAY_GRID
        buildChildren(b, n, s)
        blockifyItems(b)
        return b
    }
    if d == DISPLAY_TABLE || d == DISPLAY_INLINE_TABLE {
        Box b = newBox(BOX_TABLE, n, s)
        // The inner layout is a table either way; `blockLevel` is the
        // whole of the difference, as it is for flex and grid.
        b.blockLevel = d == DISPLAY_TABLE
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

// A flex or grid item's `display` is blockified (Display 3 §2.7): an
// inline child of a flex container is an item, not a run of inline
// content on a line, so `width` applies to it as it does to a block.
// This is the same conversion an inline that turns out to contain
// block-level content goes through in buildBox.
void func blockifyItems(b:Box) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind != BOX_INLINE { continue }
        c.kind = BOX_BLOCK
        c.blockLevel = true
        wrapInlineRuns(c)
    }
}

void func buildChildren(b:Box, n:Node, s:Style) {
    addGeneratedBox(b, n, 'before')
    appendChildBoxes(b, n, s)
    addGeneratedBox(b, n, 'after')
    applyFirstLetter(b, n)
}

// `display: contents` generates no box of its own: the element's
// children become its parent's, in its place (Display 3 sec. 3.1). Its
// own box properties describe a box that does not exist, and are
// therefore ignored -- but it is still in the tree for inheritance, so
// its children inherit from it and not from its parent.
void func appendChildBoxes(b:Box, n:Node, s:Style) {
    for int i = 0, i < n.children.length, i++ {
        Node child = n.children[i]
        if child.kind == NODE_ELEMENT && child.style.display == DISPLAY_CONTENTS {
            addGeneratedBox(b, child, 'before')
            appendChildBoxes(b, child, child.style)
            addGeneratedBox(b, child, 'after')
            continue
        }
        Box c = buildBox(child, s)
        if c != null { addChildBox(b, c) }
    }
}

// How many characters of `t` make up the first letter, starting at the
// first one that is not whitespace (CSS2 §5.12.2): any punctuation that
// precedes the letter goes with it, and so does any that follows it.
// Returns the index just past them, or -1 when the text holds no letter
// at all and the search must move to the next box.
int func firstLetterEnd(t:text) {
    ascii a = t.toAscii()
    if a == null { return -1 }
    int len = a.length
    int i = 0
    while i < len && isSpaceCode(a.charCodeAt(i)) { i++ }
    if i >= len { return -1 }
    // leading punctuation
    while i < len && !isAlnumCode(a.charCodeAt(i)) && !isSpaceCode(a.charCodeAt(i)) { i++ }
    if i >= len { return -1 }
    if isSpaceCode(a.charCodeAt(i)) { return -1 }
    i++                                  // the letter itself
    // and any punctuation clinging to it
    while i < len && !isAlnumCode(a.charCodeAt(i)) && !isSpaceCode(a.charCodeAt(i)) { i++ }
    return i
}

// Splits the first text box in `b`'s inline content so that its first
// letter sits in a box of the ::first-letter style. Returns true once
// it has done so, which stops the walk: only the first letter of the
// block is styled, not the first of every descendant.
bool func splitFirstLetter(b:Box, ps:Style) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT {
            if textIsCollapsibleBlank(c.content) { continue }
            int end = firstLetterEnd(c.content)
            if end < 0 { continue }
            ascii a = c.content.toAscii()
            if a == null { continue }
            Node lead = newTextNode(a.slice(0, end).toText())
            lead.style = ps
            // A drop cap is a float (CSS Inline 3), and CSS2 §9.7 makes
            // a float block-level -- but a `BOX_BLOCK` here makes the
            // paragraph wrap the rest of its text in an anonymous box,
            // which puts the float outside the formatting context that
            // has to see it. An atomic inline floats without that:
            // `boxIsFloated` accepts it, `placeInline` routes floats
            // before atomics, and the painter reaches it.
            bool drops = initialLetterPacked(ps) != 0
            Box letter = newBox(drops ? BOX_INLINE_BLOCK : BOX_INLINE, c.node, ps)
            // `newBox` raises `docHasFloats` from the box's own node's
            // style, and this box is built from a text node, so the
            // drop cap has to raise it itself.
            if drops { docHasFloats = true }
            addChildBox(letter, buildTextBox(lead, ps))
            letter.parentId = b.id
            letter.depth = b.depth + 1
            c.content = a.slice(end, a.length).toText()
            // An array here has no insert, so the child list is rebuilt
            // with the letter box in front of what is left of the text
            // -- see FINDINGS.md, "one global namespace" for the family
            // of small absences this belongs to.
            arr[Box] rebuilt = []
            for int k = 0, k < b.children.length, k++ {
                if k == i { rebuilt.push(letter) }
                rebuilt.push(b.children[k])
            }
            b.children = rebuilt
            return true
        }
        if c.kind == BOX_INLINE || c.kind == BOX_ANON {
            if splitFirstLetter(c, ps) { return true }
        }
        // A block-level child starts a new block, whose own first
        // letter is not this one's.
        if c.blockLevel { return true }
    }
    return false
}

void func applyFirstLetter(b:Box, n:Node) {
    if !anyFirstLetter { return }
    if n == null || n.id <= 0 { return }
    if pseudoHasFirstLetter[pseudoKey(n.id, 'first-letter')] == null { return }
    splitFirstLetter(b, pseudoStyleOf(n.id, 'first-letter'))
}

// The pieces of a `content` that named a url, in the order written: a
// text box for each string and a replaced image box for each image. An
// image that did not load generates no box, which is what Chromium
// does; the alternative is the broken-image frame an <img> draws, in
// the middle of generated text that is otherwise correct.
//
// Answers whether this pseudo-element had such a run at all, so the
// caller can fall back to the single text box every other one is.
bool func addGeneratedRun(box:Box, n:Node, which:text, ps:Style) {
    ContentRun run = pseudoContentRunOf(n.id, which)
    if run == null { return false }
    for int i = 0, i < run.parts.length, i++ {
        if run.urls[i] == null {
            if run.parts[i] != '' {
                Node fake = newTextNode(run.parts[i])
                fake.style = ps
                addChildBox(box, buildTextBox(fake, ps))
            }
            continue
        }
        img loaded = loadedImages[run.urls[i]]
        if loaded == null { continue }
        // The image is a box of its own inside the generated box, so
        // the pseudo-element's margin, padding and border surround the
        // whole run and are applied once. Its own style is the
        // inherited half of the pseudo-element's with an automatic
        // width and height: a `width` on a pseudo-element whose content
        // is an image does not resize the image, measured against
        // Chromium 141.
        Style gs = anonymousStyle(ps)
        gs.display = DISPLAY_INLINE
        gs.verticalAlign = ps.verticalAlign
        Box gb = newBox(BOX_IMAGE, n, gs)
        gb.image = loaded
        gb.imgW = loaded.width
        gb.imgH = loaded.height
        addChildBox(box, gb)
    }
    return true
}

// A ::before or ::after box: the generated content inside a box of the
// pseudo-element's own style, so `display`, `color` and the rest apply
// to it rather than to the element (CSS2 §12.1). Nothing is generated
// unless the cascade resolved a `content` for it.
void func addGeneratedBox(b:Box, n:Node, which:text) {
    if n == null || n.id <= 0 { return }
    if !hasPseudo(n.id, which) { return }
    Style ps = pseudoStyleOf(n.id, which)
    if ps.display == DISPLAY_NONE { return }
    text content = pseudoContentOf(n.id, which)

    Box box = newBox(displayIsBlockLevel(ps.display) ? BOX_BLOCK : BOX_INLINE, n, ps)
    box.blockLevel = displayIsBlockLevel(ps.display)
    // A document whose generated content names no image never asks for
    // a run, which is every document but the few that do.
    if anyContentUrl && addGeneratedRun(box, n, which, ps) {
        addChildBox(b, box)
        return
    }
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
            if c.kind == BOX_TEXT && textIsCollapsibleBlank(c.content) && wsDropsBlank(c.style, c.content) { continue }
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
    if wsKeepsSpaces(b.style) {
        return t.replace(tabChar, tabAdvance(b.style)).split('\n')
    }
    if wsKeepsBreaks(b.style) {
        // pre-line: newlines survive, every other run of whitespace
        // collapses to one space. Splitting on the newline first keeps
        // the collapse from eating it.
        arr[text] lines = t.split('\n')
        arr[text] out = []
        for int i = 0, i < lines.length, i++ {
            out.push(lines[i].replace(spaceRun, ' '))
        }
        return out
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
    // Size containment: the box's intrinsic widths are those of an
    // empty box, so its content is never measured and
    // contain-intrinsic-width stands in for it (Containment 1 §3.1).
    // This is also where the pass is skipped rather than run and
    // ignored, which is half of what the property is for.
    if b.style.containInlineSize {
        int iw = b.style.intrinsicWidth.kind == LEN_PX
            ? maxInt(roundPx(b.style.intrinsicWidth.v), 0) : 0
        int extras = horizontalExtras(b, 0)
        b.minContent = iw + extras
        b.maxContent = iw + extras
        return
    }
    if b.kind == BOX_TEXT {
        arr[text] words = wordsOf(b)
        int sw = spaceWidth(b.style)
        bool pre = wsKeepsBreaks(b.style)
        bool nowrap = wsNoWrap(b.style) && !wsKeepsBreaks(b.style)
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
        // A space between two pieces of inline content is a space
        // whether the pieces are text or elements: `a <em>b</em>` is as
        // wide as `a b`. The space lives at the end of one text box or
        // the start of the next and is not part of either one's own
        // measured width, so it is carried across as a flag. Two
        // collapsing spaces are still one space.
        bool spacePending = false
        int spacePendingWidth = 0
        for int i = 0, i < b.children.length, i++ {
            Box c = b.children[i]
            computeIntrinsic(c)
            if c.kind == BOX_BR {
                maxW = maxInt(maxW, lineW)
                lineW = 0
                spacePending = false
                continue
            }
            // A text box that is nothing but whitespace is the space
            // between its neighbours, not a piece of content with a
            // width of its own; counting both would separate them by
            // two spaces.
            if c.kind == BOX_TEXT && textIsCollapsibleBlank(c.content)
                && wsDropsBlank(c.style, c.content) {
                if !spacePending {
                    spacePending = true
                    spacePendingWidth = spaceWidth(c.style)
                }
                continue
            }
            minW = maxInt(minW, c.minContent)
            if c.kind == BOX_TEXT && wsNoWrap(c.style) && !wsKeepsBreaks(c.style) { minW = maxInt(minW, c.maxContent) }
            if c.kind == BOX_TEXT && textStartsWithSpace(c) && !spacePending {
                spacePending = true
                spacePendingWidth = spaceWidth(c.style)
            }
            if spacePending && i > 0 {
                lineW = lineW + spacePendingWidth
            }
            spacePending = false
            lineW = lineW + c.maxContent
            if c.kind == BOX_TEXT && textEndsWithSpace(c) {
                spacePending = true
                spacePendingWidth = spaceWidth(c.style)
            }
        }
        maxW = maxInt(maxW, lineW)
        if wsNoWrap(s) && !wsKeepsBreaks(s) { minW = maxW }
    } else {
        for int i = 0, i < b.children.length, i++ {
            Box c = b.children[i]
            computeIntrinsic(c)
            minW = maxInt(minW, c.minContent)
            maxW = maxInt(maxW, c.maxContent)
        }
    }
    // `width`, `min-width` and `max-width` do not apply to a
    // non-replaced inline box (CSS2 §10.3.1), and placeInline does not
    // apply them: it lays the inline's children out and takes whatever
    // width they come to. Letting them through here made the two passes
    // disagree -- an inline-block wrapping `<span style="width:30px">b</span>`
    // reserved 30 pixels for a box that then drew ten. The kind is
    // asked second, so a box with no declared width pays nothing for
    // the question.
    int ownMin = minW
    if s.width.kind == LEN_PX && b.kind != BOX_INLINE {
        int fixed = roundPx(s.width.v)
        minW = fixed
        maxW = fixed
    }
    if s.maxWidth.kind == LEN_PX && b.kind != BOX_INLINE {
        int mx = roundPx(s.maxWidth.v)
        maxW = minInt(maxW, mx)
        minW = minInt(minW, mx)
    }
    if s.minWidth.kind == LEN_PX && b.kind != BOX_INLINE {
        int mn = roundPx(s.minWidth.v)
        maxW = maxInt(maxW, mn)
        minW = maxInt(minW, mn)
    }
    int extras = horizontalExtras(b, 0)
    if b.isListItem { }
    b.minContent = minW + extras
    b.maxContent = maxW + extras
    b.contentMin = ownMin + extras
}

bool func textStartsWithSpace(b:Box) {
    if b.content == null || b.content == '' { return false }
    int c = b.content.charCodeAt(0)
    return isSpaceCode(c)
}

bool func textEndsWithSpace(b:Box) {
    if b.content == null || b.content == '' { return false }
    int c = b.content.charCodeAt(b.content.length - 1)
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
    // An `anchor-size()` margin is the length the function resolved to,
    // put in the property as if it had been written out. `padding-*`
    // refuses the function, so the padding above is untouched.
    //
    // Out of line, and not four lookups written here: `resolveEdges` is
    // called for every box of every page, and putting the body inside
    // it cost two milliseconds of layout on a page with no
    // `anchor-size()` on it -- measured, and recovered by this.
    if anyAnchorSize { applyAnchorSizeMargins(b) }
}

void func applyAnchorSizeMargins(b:Box) {
    int amL = anchorSizeFor(b, ANCHOR_SIZE_MARGINLEFT)
    if amL >= 0 { b.ml = amL }
    int amR = anchorSizeFor(b, ANCHOR_SIZE_MARGINRIGHT)
    if amR >= 0 { b.mr = amR }
    int amT = anchorSizeFor(b, ANCHOR_SIZE_MARGINTOP)
    if amT >= 0 { b.mt = amT }
    int amB = anchorSizeFor(b, ANCHOR_SIZE_MARGINBOTTOM)
    if amB >= 0 { b.mb = amB }
}

int func contentWidth(b:Box) {
    return b.w - b.pl - b.pr - b.bl - b.br
}

int func contentX(b:Box) {
    return b.x + b.bl + b.pl + b.sbLeft
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

// The rectangle `object-view-box` names over an image `natW` by `natH`,
// in the image's own pixels (Images 4). It may reach outside the image,
// which a negative inset asks for and which leaves those pixels empty.
// The four answers come back in globals because a Festina function
// returns one value (FINDINGS.md, "one value out of a function").
int viewBoxX = 0
int viewBoxY = 0
int viewBoxW = 0
int viewBoxH = 0

bool func resolveViewBox(s:Style, natW:int, natH:int) {
    viewBoxX = 0
    viewBoxY = 0
    viewBoxW = natW
    viewBoxH = natH
    if s.objectViewBox.kind == VIEWBOX_NONE || natW <= 0 || natH <= 0 { return false }
    int t = resolveLen(s.objectViewBox.t, natH, 0)
    int r = resolveLen(s.objectViewBox.r, natW, 0)
    int bo = resolveLen(s.objectViewBox.b, natH, 0)
    int l = resolveLen(s.objectViewBox.l, natW, 0)
    if s.objectViewBox.kind == VIEWBOX_XYWH {
        // t r b l hold x y w h for this form.
        viewBoxX = t
        viewBoxY = r
        viewBoxW = bo
        viewBoxH = l
    } else if s.objectViewBox.kind == VIEWBOX_RECT {
        viewBoxX = l
        viewBoxY = t
        viewBoxW = r - l
        viewBoxH = bo - t
    } else {
        viewBoxX = l
        viewBoxY = t
        viewBoxW = natW - l - r
        viewBoxH = natH - t - bo
    }
    if viewBoxW <= 0 || viewBoxH <= 0 {
        viewBoxX = 0
        viewBoxY = 0
        viewBoxW = natW
        viewBoxH = natH
        return false
    }
    return true
}

// The natural size a replaced box has after its view box: the whole
// image when there is none.
int func naturalImageWidth(b:Box) {
    if b.imgW <= 0 { return 0 }
    resolveViewBox(b.style, b.imgW, b.imgH)
    return viewBoxW
}

int func naturalImageHeight(b:Box) {
    if b.imgH <= 0 { return 0 }
    resolveViewBox(b.style, b.imgW, b.imgH)
    return viewBoxH
}

int func imageBoxWidth(b:Box, cw:int) {
    Style s = b.style
    int natural = naturalImageWidth(b)
    int naturalH = naturalImageHeight(b)
    if !lenIsAuto(s.width) {
        return maxInt(resolveLen(s.width, cw, natural), 0)
    }
    if s.hasAspectRatio && !(s.aspectPrefersNatural && natural > 0 && naturalH > 0) {
        int fixedH = definiteContentHeight(b)
        if fixedH >= 0 { return aspectWidthFromHeight(b, fixedH) }
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
    int natural = naturalImageWidth(b)
    int naturalH = naturalImageHeight(b)
    if !lenIsAuto(s.height) && s.height.kind == LEN_PX {
        return maxInt(roundPx(s.height.v), 0)
    }
    // A declared ratio replaces the image's natural one; `auto <ratio>`
    // gives way to it, which is the whole difference between the two
    // forms (Sizing 4 §4). `auto 2` on a square image leaves it square.
    if s.hasAspectRatio && !(s.aspectPrefersNatural && natural > 0 && naturalH > 0) {
        return aspectHeightFromWidth(b, w)
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
// Whether an automatic width is shrink-to-fit rather than the
// containing block's: min(max(min-content, available), max-content).
//
// A float is in this set (CSS2 §10.3.5) and was not, so a float with no
// declared width was laid out as an ordinary block and took the whole
// column. The text meant to wrap beside it then had nothing to wrap in
// and went underneath, which is the visible half of the bug.
bool func widthIsShrinkToFit(b:Box) {
    if b.style.floatSide != FLOAT_NONE { return true }
    return (b.kind == BOX_INLINE_BLOCK || b.kind == BOX_FLEX || b.kind == BOX_GRID)
        && !b.blockLevel
}

// ---- aspect-ratio ----------------------------------------------------------
// The box the ratio describes is the content box, or the border box
// under `box-sizing: border-box` (Sizing 4 §4) -- `aspect-ratio: 2;
// width: 100px; padding: 10px` is 120 by 70 one way and 100 by 50 the
// other, which is how Chromium 141 answers it.
//
// A zero on either side of the ratio is degenerate and makes the
// derived dimension zero; Chromium gives both `0 / 1` and `2 / 0` a
// height of nothing, which is why the two terms are kept apart rather
// than divided once in the cascade.

int func aspectHeightFromWidth(b:Box, contentW:int) {
    Style s = b.style
    if s.aspectW <= 0.0 || s.aspectH <= 0.0 { return 0 }
    if s.boxSizing == BOX_BORDER {
        int hEdges = b.pt + b.pb + b.bt + b.bb
        int wEdges = b.pl + b.pr + b.bl + b.br
        int outer = roundPx((contentW + wEdges).toFloat() * s.aspectH / s.aspectW)
        return maxInt(outer - hEdges, 0)
    }
    return maxInt(roundPx(contentW.toFloat() * s.aspectH / s.aspectW), 0)
}

int func aspectWidthFromHeight(b:Box, contentH:int) {
    Style s = b.style
    if s.aspectW <= 0.0 || s.aspectH <= 0.0 { return 0 }
    if s.boxSizing == BOX_BORDER {
        int hEdges = b.pt + b.pb + b.bt + b.bb
        int wEdges = b.pl + b.pr + b.bl + b.br
        int outer = roundPx((contentH + hEdges).toFloat() * s.aspectW / s.aspectH)
        return maxInt(outer - wEdges, 0)
    }
    return maxInt(roundPx(contentH.toFloat() * s.aspectW / s.aspectH), 0)
}

// A container whose height a ratio fixes takes it from the ratio rather
// than from the lines or tracks its children came to, with the content
// still an automatic minimum unless the box clips: the same rule a
// block follows, and what Chromium 141 does for flex and grid alike.
void func applyContainerAspect(b:Box) {
    Style s = b.style
    if !s.hasAspectRatio || s.height.kind == LEN_PX { return }
    int vEdges = b.pt + b.pb + b.bt + b.bb
    int arh = aspectHeightFromWidth(b, b.w - b.pl - b.pr - b.bl - b.br) + vEdges
    b.h = s.overflowHidden ? arh : maxInt(arh, b.h)
}

// The content height a declared `height` fixes, or -1 when it fixes
// none. Only a box with one definite dimension takes the other from
// the ratio, so this is the question the width code has to ask first.
// How far each scroll container has been scrolled, by the id of the
// element it belongs to. The box tree is rebuilt on every layout and
// the offset has to outlive it; the node registry is what does. A page
// that scrolls nothing never touches the map.
map[int] boxScrollTops = {}
// And how far across, for the axis a horizontal bar scrolls.
map[int] boxScrollLefts = {}

void func boxScrollReset() {
    boxScrollTops = {}
    boxScrollLefts = {}
}

// How far a box can be scrolled: what its content comes to, less what
// is visible of it.
int func boxScrollRange(b:Box) {
    if !b.scrollsY { return 0 }
    int visible = maxInt(b.h - b.bt - b.bb - b.pt - b.pb - b.sbH, 1)
    return maxInt(b.scrollH - visible, 0)
}

int func boxScrollTop(b:Box) {
    if !b.scrollsY || b.node == null || b.node.id == 0 { return 0 }
    int v = boxScrollTops[b.node.id.toText()]
    if v == null { return 0 }
    return clampInt(v, 0, boxScrollRange(b))
}

// The same three, across. A horizontal bar scrolls what a vertical one
// does not, and the two axes keep their offsets apart: a box may have
// one bar, the other, or both.
int func boxScrollLeftRange(b:Box) {
    if !b.scrollsX { return 0 }
    int visible = maxInt(b.w - b.bl - b.br - b.pl - b.pr - b.sbW - b.sbLeft, 1)
    return maxInt(b.scrollW - visible, 0)
}

int func boxScrollLeft(b:Box) {
    if !b.scrollsX || b.node == null || b.node.id == 0 { return 0 }
    int v = boxScrollLefts[b.node.id.toText()]
    if v == null { return 0 }
    return clampInt(v, 0, boxScrollLeftRange(b))
}

bool func boxScrollLeftBy(b:Box, dx:int) {
    if !b.scrollsX || b.node == null || b.node.id == 0 { return false }
    int was = boxScrollLeft(b)
    int now = snapPosition(b, clampInt(was + dx, 0, boxScrollLeftRange(b)), false)
    if now == was { return false }
    boxScrollLefts[b.node.id.toText()] = now
    return true
}

// Scrolls a box, and answers whether it moved -- which is what tells a
// wheel over a box that has reached its end from one that scrolled, so
// the page can take the rest.
// ---- scroll snapping (CSS Scroll Snap 1) -------------------------------
//
// A scroll container with `scroll-snap-type` comes to rest on one of the
// positions its children's `scroll-snap-align` declares, rather than
// wherever the scroll left it. A position is one subtraction -- the
// child's edge less the snapport's, per alignment -- with
// `scroll-padding` insetting the snapport and `scroll-margin` outsetting
// the child's snap area.
//
// The children looked at are the container's own, which is the depth
// everything else here fragments and measures at.
//
// Where a child's snap area is larger than the snapport it is a *range*
// of valid positions rather than a point (§6.1): a position inside it is
// already showing that child and is left alone, and one past it is
// pulled only as far as the child's own end. Chromium does this, and a
// nearest-point implementation that did not would jump a tall child's
// middle to its top.
int snapBest = 0
bool snapFound = false

int func absInt(v:int) { return v < 0 ? 0 - v : v }

// Keeps the nearer of the candidate and what is held, with a tie going
// to the lower -- which Chromium does, and which the `end` alignment of
// the suite's fixture pins at 35, where 20 and 50 are both fifteen away.
void func snapConsider(want:int, pos:int) {
    if !snapFound { snapBest = pos  snapFound = true  return }
    int dNew = absInt(pos - want)
    int dOld = absInt(snapBest - want)
    if dNew < dOld || dNew == dOld && pos < snapBest { snapBest = pos }
}

int func snapAlignedPosition(align:int, areaStart:int, areaEnd:int,
                             portStart:int, portEnd:int) {
    if align == SNAPALIGN_START { return areaStart - portStart }
    if align == SNAPALIGN_END { return areaEnd - portEnd }
    // The two centres, which is the two midpoints subtracted. Doubling
    // before halving keeps the odd case off the floor twice.
    return Math.floorDiv(areaStart + areaEnd, 2) - Math.floorDiv(portStart + portEnd, 2)
}

// Where a scroll of this container should come to rest on one axis.
// `want` is the position the scroll asked for, already clamped.
int func snapPosition(b:Box, want:int, vertical:bool) {
    Style s = b.style
    if s.snapStrict == SNAP_NONE { return want }
    if vertical ? !s.snapY : !s.snapX { return want }
    int range = vertical ? boxScrollRange(b) : boxScrollLeftRange(b)
    if range <= 0 { return want }

    // The snapport: the container's content box, inset by scroll-padding.
    int portStart = vertical ? contentY(b) : contentX(b)
    int portSize = vertical ? scrollVisibleHeight(b) : scrollHVisibleWidth(b)
    int padNear = vertical ? resolveLen(s.scrollPaddingTop, portSize, 0)
                           : resolveLen(s.scrollPaddingLeft, portSize, 0)
    int padFar = vertical ? resolveLen(s.scrollPaddingBottom, portSize, 0)
                          : resolveLen(s.scrollPaddingRight, portSize, 0)
    portStart = portStart + padNear
    int portEnd = portStart + portSize - padNear - padFar
    if portEnd <= portStart { return want }

    snapFound = false
    snapBest = 0
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        int align = vertical ? c.style.snapAlignBlock : c.style.snapAlignInline
        if align == SNAPALIGN_NONE { continue }
        int mNear = vertical ? resolveLen(c.style.scrollMarginTop, 0, 0)
                             : resolveLen(c.style.scrollMarginLeft, 0, 0)
        int mFar = vertical ? resolveLen(c.style.scrollMarginBottom, 0, 0)
                            : resolveLen(c.style.scrollMarginRight, 0, 0)
        int areaStart = (vertical ? c.y : c.x) - mNear
        int areaEnd = (vertical ? c.y + c.h : c.x + c.w) + mFar
        int pos = snapAlignedPosition(align, areaStart, areaEnd, portStart, portEnd)
        if areaEnd - areaStart > portEnd - portStart {
            // A snap area larger than the snapport is a range: anywhere
            // that keeps the snapport inside it will do, so a position
            // already inside asks for nothing.
            int lo = clampInt(areaStart - portStart, 0, range)
            int hi = clampInt(areaEnd - portEnd, 0, range)
            if lo > hi { int t = lo  lo = hi  hi = t }
            if want >= lo && want <= hi { return want }
            snapConsider(want, want < lo ? lo : hi)
            continue
        }
        snapConsider(want, clampInt(pos, 0, range))
    }
    if !snapFound { return want }
    // `proximity` snaps only what is near, and near is a third of the
    // snapport: Chromium snaps from 32 and not 34 in a hundred pixels,
    // and from 66 and not 68 in two hundred (todo.md).
    if s.snapStrict == SNAP_PROXIMITY
        && absInt(snapBest - want) > Math.floorDiv(portEnd - portStart, 3) {
        return want
    }
    return snapBest
}

bool func boxScrollBy(b:Box, dy:int) {
    if !b.scrollsY || b.node == null || b.node.id == 0 { return false }
    int was = boxScrollTop(b)
    int now = snapPosition(b, clampInt(was + dy, 0, boxScrollRange(b)), true)
    if now == was { return false }
    boxScrollTops[b.node.id.toText()] = now
    return true
}

// How thick a scrollbar is. The standard leaves it to the browser;
// this one takes Chromium's classic fifteen pixels, so that a box's
// content geometry can be compared with Chromium's directly.
const int SCROLLBAR_PX = 15
// `scrollbar-width: thin` is ten pixels and `none` is none at all,
// which is what Chromium 141 reserves: a 200x100 `overflow: scroll` box
// has a client width of 185, 190 and 200 for `auto`, `thin` and `none`.
const int SCROLLBAR_THIN_PX = 10

int func scrollbarPx(s:Style) {
    if s.scrollbarWidth == SCROLLBAR_NONE { return 0 }
    return s.scrollbarWidth == SCROLLBAR_THIN ? SCROLLBAR_THIN_PX : SCROLLBAR_PX
}

// The shortest a thumb gets, however long the content is, so that a very
// long document still leaves something to take hold of.
const int SCROLLBAR_MIN_THUMB = 12

// How far the thumb is inset from the two long sides of its track.
const int SCROLLBAR_THUMB_INSET = 4

// The vertical thumb's geometry, in document coordinates. The painter
// draws the thumb from these and the pointer is tested against them, so
// where it looks and where it can be taken hold of are the same
// rectangle by construction rather than by two formulas that agree.
int func scrollTrackTop(b:Box) { return b.y + b.bt }

int func scrollTrackHeight(b:Box) { return b.h - b.bt - b.bb - b.sbH }

int func scrollVisibleHeight(b:Box) {
    return maxInt(b.h - b.bt - b.bb - b.pt - b.pb - b.sbH, 1)
}

// A bar with nothing to scroll is an empty track, which is what Chromium
// draws and what says at a glance that there is nothing below the fold.
bool func scrollThumbShown(b:Box) {
    return b.sbW > 0 && b.scrollH > scrollVisibleHeight(b)
}

int func scrollThumbHeight(b:Box) {
    int trackH = scrollTrackHeight(b)
    int thumbH = maxInt(Math.floorDiv(trackH * scrollVisibleHeight(b), maxInt(b.scrollH, 1)),
                        SCROLLBAR_MIN_THUMB)
    return thumbH > trackH ? trackH : thumbH
}

// The thumb sits as far down its own run as the content is through what
// there is of it, so it reaches the bottom exactly when the content
// does.
int func scrollThumbTop(b:Box) {
    int run = scrollTrackHeight(b) - scrollThumbHeight(b)
    int range = maxInt(boxScrollRange(b), 1)
    return scrollTrackTop(b) + Math.floorDiv(run * boxScrollTop(b), range)
}

int func scrollThumbLeft(b:Box) {
    return b.x + b.bl + (b.w - b.bl - b.br) - b.sbW + SCROLLBAR_THUMB_INSET
}

int func scrollThumbWidth(b:Box) { return b.sbW - 2 * SCROLLBAR_THUMB_INSET }

// The horizontal thumb, the same eight answers over the other axis.
int func scrollHTrackLeft(b:Box) { return b.x + b.bl }

int func scrollHTrackWidth(b:Box) { return b.w - b.bl - b.br - b.sbW }

int func scrollHVisibleWidth(b:Box) {
    return maxInt(b.w - b.bl - b.br - b.pl - b.pr - b.sbW, 1)
}

bool func scrollHThumbShown(b:Box) {
    return b.sbH > 0 && b.scrollW > scrollHVisibleWidth(b)
}

int func scrollHThumbWidth(b:Box) {
    int trackW = scrollHTrackWidth(b)
    int thumbW = maxInt(Math.floorDiv(trackW * scrollHVisibleWidth(b), maxInt(b.scrollW, 1)),
                        SCROLLBAR_MIN_THUMB)
    return thumbW > trackW ? trackW : thumbW
}

int func scrollHThumbLeft(b:Box) {
    int run = scrollHTrackWidth(b) - scrollHThumbWidth(b)
    int range = maxInt(boxScrollLeftRange(b), 1)
    return scrollHTrackLeft(b) + Math.floorDiv(run * boxScrollLeft(b), range)
}

int func scrollHTrackTop(b:Box) {
    return b.y + b.bt + (b.h - b.bt - b.bb) - b.sbH
}

int func scrollHThumbTop(b:Box) { return scrollHTrackTop(b) + SCROLLBAR_THUMB_INSET }

int func scrollHThumbHeight(b:Box) { return b.sbH - 2 * SCROLLBAR_THUMB_INSET }

// One pass of a block's own content, which an `auto` scroll container
// does twice: once to find out whether it overflows, and again with the
// scrollbar's room taken out.
int func layoutBlockContent(b:Box, innerX:int, innerY:int, width:int) {
    // A multi-column container lays its content out once, at the column
    // width, and then breaks that one flow into columns (CSS
    // Multi-column 1 §3). Nothing there is laid out twice, so the cost
    // is the walk that moves the content, not a second layout.
    int usedColumns = usedColumnCount(b.style, width)
    if usedColumns > 1 { return layoutColumns(b, innerX, innerY, width, usedColumns) }
    if hasInlineContent(b) { return layoutInlineContent(b, innerX, innerY, width) }
    return layoutBlockChildren(b, innerX, innerY, width)
}

// How far the children reach past a point, and how far they reach at
// all -- the horizontal half of the scrollable overflow area. Only the
// boxes are asked, not the lines inside them, which is why a single
// unbreakable word wider than its box does not raise a scrollbar here.
// How far the content of a box reaches past its own content edge. Both
// walks below are asked only by a scroll container, so what they cost is
// paid by the boxes that have one and by nothing else.
//
// A line counts as well as a child box: a word with nowhere to break is
// wider than its container, and there is nothing layout can do about it
// but let it overflow. The fragments carry their own positions in
// document coordinates, so the rightmost edge of the rightmost fragment
// is the whole of the measurement -- and the walk goes to the lines
// rather than to the text boxes, because a text box has no geometry of
// its own here.
int func linesReachRight(b:Box) {
    int right = 0
    for int i = 0, i < b.lines.length, i++ {
        Line ln = b.lines[i]
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            if f.kind == FRAG_INLINE_BG { continue }
            if f.x + f.w > right { right = f.x + f.w }
        }
    }
    return right
}

bool func childrenReachPast(b:Box, edge:int) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT { continue }
        if c.x + c.w + c.mr > edge { return true }
        // An anonymous box holds the inline content of a block that
        // also has block-level children, and its lines are where that
        // content's width is.
        if c.kind == BOX_ANON && linesReachRight(c) > edge { return true }
    }
    return linesReachRight(b) > edge
}

int func childrenReach(b:Box, innerX:int) {
    int reach = 0
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT { continue }
        int r = c.x + c.w + c.mr - innerX
        if r > reach { reach = r }
        if c.kind == BOX_ANON {
            int lr = linesReachRight(c) - innerX
            if lr > reach { reach = lr }
        }
    }
    int own = linesReachRight(b) - innerX
    if own > reach { reach = own }
    return reach
}

// The containing block's own content height while its children are
// being laid out, or -1 where that height is not definite. A percentage
// height is a percentage of this (CSS2 §10.5), and computes to `auto`
// where there is nothing to take a percentage of -- which is what makes
// `height: 100%` do nothing inside a box that is as tall as its
// content. A global rather than a parameter because every one of the
// dozen calls that lay out children would otherwise carry it; each
// caller saves it and puts it back, as the layout recurses.
int layoutCBHeight = -1

// The box's own content height where that is definite: a length, or a
// percentage of a containing block that is itself definite.
int func definiteContentHeight(b:Box) {
    Style s = b.style
    int h = 0
    if s.height.kind == LEN_PX { h = maxInt(roundPx(s.height.v), 0) }
    else if s.height.kind == LEN_PERCENT && layoutCBHeight >= 0 {
        h = maxInt(roundPx(layoutCBHeight.toFloat() * s.height.v / 100.0), 0)
    } else { return -1 }
    if s.boxSizing == BOX_BORDER { h = maxInt(h - (b.pt + b.pb + b.bt + b.bb), 0) }
    return h
}

// One of `min-height` and `max-height` as a number of content pixels,
// or -1 where it says nothing this engine can resolve.
int func heightLimitPx(l:Len, vEdges:int, boxSizing:int) {
    int v = 0
    if l.kind == LEN_PX { v = roundPx(l.v) }
    else if l.kind == LEN_PERCENT && layoutCBHeight >= 0 {
        v = maxInt(roundPx(layoutCBHeight.toFloat() * l.v / 100.0), 0)
    } else { return -1 }
    if boxSizing == BOX_BORDER { v = maxInt(v - vEdges, 0) }
    return maxInt(v, 0)
}

// Whether the box's height is one of those definite heights at all,
// which is the question every place that used to ask whether the
// declared height was a length.
bool func hasDefiniteHeight(b:Box) {
    Style s = b.style
    return s.height.kind == LEN_PX
        || (s.height.kind == LEN_PERCENT && layoutCBHeight >= 0)
}

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
    // The size the user agent supplies for a control it draws. It is not
    // a declared width -- `appearance: none` is exactly the request not
    // to draw the control, and it has to be able to take the size away
    // with it, which it could not do if this were a declaration.
    if b.controlKind != CONTROL_NONE && lenIsAuto(s.width) && b.forcedWidthPx < 0 {
        if b.controlKind == CONTROL_CHECK && s.appearanceAuto {
            b.forcedWidthPx = CHECK_CONTROL_PX
        } else if b.controlKind == CONTROL_FIELD && !s.fieldSizingContent {
            b.forcedWidthPx = fieldCharCount(b.node) * maxInt(measureWidth(s, '0'), 1)
        }
    }
    // An `anchor-size()` width behaves exactly as a declared length
    // does, which is what this hook already means.
    if anyAnchorSize && b.forcedWidthPx < 0 {
        int asWidth = anchorSizeFor(b, ANCHOR_SIZE_WIDTH)
        if asWidth >= 0 { b.forcedWidthPx = asWidth }
    }
    bool autoWidth = lenIsAuto(s.width) && b.forcedWidthPx < 0
    // A definite height and a ratio give the width, block-level or not:
    // Chromium makes `aspect-ratio: 2; height: 40px` eighty pixels wide
    // rather than letting it fill its containing block. The field is
    // read straight off the style the box already holds, so a box
    // without the property pays one boolean and no lookup.
    int arHeight = -1
    if autoWidth && s.hasAspectRatio { arHeight = definiteContentHeight(b) }
    if autoWidth {
        if arHeight >= 0 {
            width = aspectWidthFromHeight(b, arHeight)
        } else if widthIsShrinkToFit(b) {
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
    int asMaxW = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_MAXWIDTH) : -1
    if asMaxW >= 0 {
        if width > asMaxW { width = asMaxW }
    } else if s.maxWidth.kind != LEN_AUTO {
        int mx = resolveLen(s.maxWidth, cw, width)
        if width > mx { width = mx }
    }
    int asMinW = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_MINWIDTH) : -1
    if asMinW >= 0 {
        if width < asMinW { width = asMinW }
    } else if s.minWidth.kind != LEN_AUTO {
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
        int fh = definiteContentHeight(b)
        if fh >= 0 { b.h = fh + flexEdges }
        int savedFlexCB = layoutCBHeight
        layoutCBHeight = fh
        layoutFlex(b, cx, y, cw)
        layoutCBHeight = savedFlexCB
        return
    }
    // A grid container sizes its tracks and places its items into them
    // rather than stacking its children (CSS Grid 1 §7, §8).
    if b.kind == BOX_GRID {
        int gridEdges = b.pt + b.pb + b.bt + b.bb
        b.h = gridEdges
        int gh = definiteContentHeight(b)
        if gh >= 0 { b.h = gh + gridEdges }
        int savedGridCB = layoutCBHeight
        layoutCBHeight = gh
        layoutGrid(b, cx, y, cw, width)
        layoutCBHeight = savedGridCB
        return
    }

    // A scroll container's scrollbar is drawn inside the padding box and
    // takes its room from the content, so a box that shows one has a
    // narrower content box than the same box without (CSS Overflow 3
    // §3.2). `scroll` shows one whether or not there is anything to
    // scroll; `auto` shows it only where the content overflows, which
    // is not known until the content has been laid out once.
    int sbPx = scrollbarPx(s)
    b.scrollsY = s.overflowY == OVERFLOW_SCROLL
    b.scrollsX = s.overflowX == OVERFLOW_SCROLL
    b.sbW = b.scrollsY ? sbPx : 0
    b.sbH = b.scrollsX ? sbPx : 0
    // `scrollbar-gutter: stable` reserves the inline-end gutter on a
    // scroll container whether or not anything overflows (CSS Overflow 4
    // §3.3), so the content box does not change width when it starts to.
    // It is the inline axis's gutter only: Chromium answers an
    // `overflow: auto` box with a client width of 185 and a client
    // height of 100, where without it both are the full box.
    if b.sbW == 0 && s.scrollbarGutter != SCROLLBAR_GUTTER_AUTO
        && s.overflowY == OVERFLOW_AUTO {
        b.sbW = sbPx
    }
    // `both-edges` reserves the same width again on the side no bar is
    // drawn on, so the content sits between two equal gutters: Chromium
    // answers a 200px box with a client width of 170 rather than 185.
    bool scrollsOnY = s.overflowY == OVERFLOW_SCROLL || s.overflowY == OVERFLOW_AUTO
    b.sbLeft = s.scrollbarGutter == SCROLLBAR_GUTTER_BOTH && scrollsOnY ? sbPx : 0
    width = maxInt(width - b.sbW - b.sbLeft, 0)

    // children, with this box standing as their containing block: a
    // percentage height among them is a percentage of the height
    // declared here, and `auto` where none is (CSS2 §10.5).
    int innerX = contentX(b)
    int innerY = contentY(b)
    int savedCB = layoutCBHeight
    int ownDefinite = definiteContentHeight(b)
    if ownDefinite >= 0 { ownDefinite = maxInt(ownDefinite - b.sbH, 0) }
    layoutCBHeight = ownDefinite
    int contentH = layoutBlockContent(b, innerX, innerY, width)

    // The second pass an `auto` axis needs. A vertical bar appears when
    // the content is taller than the box; a horizontal one when a child
    // box or a line of text reaches past its right edge.
    if s.overflowY == OVERFLOW_AUTO && !b.scrollsY && ownDefinite >= 0
        && contentH > ownDefinite {
        b.scrollsY = true
        // A bar of no width takes no room, so there is nothing to lay
        // out again for: the box scrolls and the content stays where it
        // was.
        if b.sbW == 0 && sbPx > 0 {
            b.sbW = sbPx
            width = maxInt(width - sbPx, 0)
            contentH = layoutBlockContent(b, innerX, innerY, width)
        }
    }
    if s.overflowX == OVERFLOW_AUTO && !b.scrollsX && childrenReachPast(b, innerX + width) {
        b.scrollsX = true
        if sbPx > 0 {
            b.sbH = sbPx
            if ownDefinite >= 0 {
                ownDefinite = maxInt(ownDefinite - sbPx, 0)
                layoutCBHeight = ownDefinite
                contentH = layoutBlockContent(b, innerX, innerY, width)
            }
        }
    }
    // Only a scroll container needs to know what it scrolls, and the
    // walk that measures the width is paid by nothing else: the flag is
    // asked first and `&&` does not evaluate what follows it.
    if b.scrollsY || b.scrollsX {
        b.scrollH = contentH
        b.scrollW = childrenReach(b, innerX)
    }
    layoutCBHeight = savedCB
    int h = contentH
    // Size containment: the box is sized as if it had no content, so
    // the height its children came to is discarded and
    // contain-intrinsic-height, if there is one, stands in its place
    // (Containment 1 §3.1). An explicit height still wins, because the
    // intrinsic size is what an automatic size resolves to rather than
    // an override.
    if s.containBlockSize {
        h = s.intrinsicHeight.kind == LEN_PX ? maxInt(roundPx(s.intrinsicHeight.v), 0) : 0
    }
    int vEdges = b.pt + b.pb + b.bt + b.bb
    if ownDefinite >= 0 {
        // definiteContentHeight has already taken the padding and
        // border out of a border-box height, and the horizontal
        // scrollbar's room out of what is left.
        h = ownDefinite
    } else if b.controlKind == CONTROL_CHECK && s.appearanceAuto {
        // and as tall as it is wide, which is what makes it a square
        h = CHECK_CONTROL_PX
    } else if s.hasAspectRatio {
        int arh = aspectHeightFromWidth(b, width)
        // The content is an automatic minimum in the block axis, and
        // only while the box does not clip: Chromium gives three lines
        // in a 100px box with `aspect-ratio: 2` a height of 60 where
        // the ratio says 50, and 50 once `overflow: hidden` is added.
        h = s.overflowHidden ? arh : maxInt(arh, h)
    }
    // A percentage minimum or maximum height is of the same containing
    // block a percentage height would be of, and is ignored where that
    // is not definite -- `layoutCBHeight` is the parent's again by this
    // point, the children having been laid out and put it back.
    // An `anchor-size()` height is a definite height, as a declared
    // length is, and takes the same box-sizing subtraction.
    int asHeight = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_HEIGHT) : -1
    if asHeight >= 0 {
        h = s.boxSizing == BOX_BORDER ? maxInt(asHeight - vEdges, 0) : asHeight
    }
    int asMinH = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_MINHEIGHT) : -1
    int minH = asMinH >= 0 ? (s.boxSizing == BOX_BORDER ? maxInt(asMinH - vEdges, 0) : asMinH)
                           : heightLimitPx(s.minHeight, vEdges, s.boxSizing)
    if minH >= 0 { h = maxInt(h, minH) }
    int asMaxH = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_MAXHEIGHT) : -1
    int maxH = asMaxH >= 0 ? (s.boxSizing == BOX_BORDER ? maxInt(asMaxH - vEdges, 0) : asMaxH)
                           : heightLimitPx(s.maxHeight, vEdges, s.boxSizing)
    if maxH >= 0 && h > maxH { h = maxH }
    b.h = h + vEdges + b.sbH
    if b.baseline == 0 { b.baseline = b.h }
}

// Stacks the block-level children of b; returns the content height.
// justify-self aligns a block-level box in its containing block's
// inline axis, and justify-items on the container is what a child with
// no answer of its own takes (CSS Box Alignment 3 §6, §7). It moves the
// box after it has been laid out and sized, and only into space the
// box is not already using, so a box that fills its container is
// unaffected -- which is why most boxes never notice the property.
//
// Auto margins have already centred or pushed the box by the time this
// runs, and the standard gives them precedence, so a box with one is
// left alone.
void func justifyBlockChild(parent:Box, c:Box, cx:int, cw:int) {
    int align = c.style.justifySelf
    if align == BOXALIGN_AUTO { align = parent.style.justifyItems }
    if align != BOXALIGN_CENTRE && align != BOXALIGN_END { return }
    if lenIsAuto(c.style.marginLeft) || lenIsAuto(c.style.marginRight) { return }
    int slack = cw - (c.w + c.ml + c.mr)
    if slack <= 0 { return }
    offsetBox(c, align == BOXALIGN_CENTRE ? Math.floorDiv(slack, 2) : slack, 0)
}

// How many columns this box has, given the space it has to fill. A
// count alone is that count; a width alone is as many columns of at
// least that width as fit; both together make the count a maximum
// (CSS Multi-column 1 §3.3).
int func usedColumnCount(s:Style, width:int) {
    bool hasCount = s.columnCount > 0
    bool hasWidth = s.columnWidth.kind == LEN_PX
    if !hasCount && !hasWidth { return 1 }
    if !hasWidth { return maxInt(s.columnCount, 1) }
    int cw = maxInt(roundPx(s.columnWidth.v), 1)
    int gap = s.columnGap
    int fit = maxInt(Math.floorDiv(width + gap, cw + gap), 1)
    if hasCount { return maxInt(minInt(s.columnCount, fit), 1) }
    return fit
}

// One thing that can be moved into a column on its own: a line box of a
// child that holds lines, or a whole child that does not. Nothing
// deeper is broken, so a subtree nested below the container's own
// children stays whole -- css-2026.md records that.
struct ColumnUnit {
    box:Box             // the child this belongs to
    line:Line
    hasLine:bool        // whether `line` means anything
    top:int
    bottom:int
    // Where a break just before this unit stands with the standard.
    // `forceBefore` is break-before: column on this child or
    // break-after: column on the one before; `avoidBefore` is the same
    // pair with `avoid`. Orphans and widows are answered per column, so
    // they cannot be decided here: what is recorded is where this line
    // sits in its child's run, and what that child asked for.
    forceBefore:bool
    avoidBefore:bool
    // Which child this came from, as an index rather than the box
    // itself: two struct references cannot be compared (FINDINGS.md,
    // "two struct references cannot be compared"), and the orphans rule
    // has to ask whether two units are lines of the same paragraph.
    childIndex:int
    lineIndex:int
    lineTotal:int
    orphans:int
    widows:int
}

// Lays a multi-column container out. A child with `column-span: all`
// is not in any column: it splits the container into the run before it,
// itself at the full width, and the run after. With no spanner -- which
// is every multi-column container on almost every page -- this is one
// call to layoutColumnRun and nothing else.
//
// Only a direct child can span. The standard lets a spanner sit deeper
// and breaks its ancestors around it; that needs the fragment boxes
// css-2026.md records as missing.
int func layoutColumns(b:Box, innerX:int, innerY:int, width:int, count:int) {
    if hasInlineContent(b) {
        return layoutColumnRun(b, innerX, innerY, width, count, 0, b.children.length)
    }
    arr[int] spanners = []
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        if boxIsOutOfFlow(c) || boxIsFloated(c) { continue }
        if c.style.columnSpanAll { spanners.push(i) }
    }
    if spanners.length == 0 {
        return layoutColumnRun(b, innerX, innerY, width, count, 0, b.children.length)
    }
    int y = innerY
    int start = 0
    for int k = 0, k < spanners.length, k++ {
        int at = spanners[k]
        if at > start { y = y + layoutColumnRun(b, innerX, y, width, count, start, at) }
        y = y + layoutBlockChildrenRange(b, innerX, y, width, at, at + 1)
        start = at + 1
    }
    if start < b.children.length {
        y = y + layoutColumnRun(b, innerX, y, width, count, start, b.children.length)
    }
    return y - innerY
}

// One run of children laid out at the column width and then moved into
// columns of equal height. Returns the height of the tallest column,
// which is the run's height.
int func layoutColumnRun(b:Box, innerX:int, innerY:int, width:int, count:int, from:int, to:int) {
    Style s = b.style
    int gap = s.columnGap
    int colW = Math.floorDiv(width - gap * (count - 1), count)
    if colW < 1 { colW = 1 }
    int flowH = hasInlineContent(b)
        ? layoutInlineContent(b, innerX, innerY, colW)
        : layoutBlockChildrenRange(b, innerX, innerY, colW, from, to)

    arr[ColumnUnit] units = []
    collectColumnUnits(b, units, from, to)
    if units.length == 0 { return flowH }

    // `column-fill: auto` fills each column to the container's height
    // before starting the next, so with no height to fill to there is
    // nothing to break at: the content stays in the first column and
    // the container grows to hold it (Multi-column 1 §3.3). Chromium
    // 141 puts twelve 20px blocks in one 240px column that way, against
    // three columns of 80 when balancing. Given a definite height the
    // two agree, and the balancing below is what produces it.
    if s.columnFillAuto && s.height.kind != LEN_PX { return flowH }

    // Balance: aim for an equal share and grow the target until every
    // unit fits in the columns there are. A unit taller than the target
    // sets its own column's height, which is why this is a loop rather
    // than one division.
    int target = Math.floorDiv(flowH + count - 1, count)
    int guard = 0
    arr[int] breaks = columnBreaks(units, target)
    while guard < 64 {
        if breaks.length + 1 <= count { break }
        target = target + maxInt(Math.floorDiv(target, 8), 1)
        breaks = columnBreaks(units, target)
        guard++
    }

    // Move each unit into its column. A unit's offset is the column's
    // x step and the top of the run it belongs to.
    int col = 0
    int nextBreak = 0
    int colTop = units[0].top
    int tallest = 0
    for int i = 0, i < units.length, i++ {
        ColumnUnit u = units[i]
        if nextBreak < breaks.length && breaks[nextBreak] == i {
            col++
            nextBreak++
            colTop = u.top
        }
        int dx = col * (colW + gap)
        int dy = innerY - colTop
        // `hasLine` rather than a null test: a struct-typed field can
        // never read as null, so `u.line == null` is always false and
        // every unit would take the line branch (FINDINGS.md,
        // finding 5).
        if u.hasLine { offsetLine(u.line, dx, dy) }
        else { offsetBox(u.box, dx, dy) }
        tallest = maxInt(tallest, u.bottom - colTop)
    }
    // A child whose lines were split no longer occupies one rectangle.
    // Its box is cut back to the part that stayed in the first column
    // it appears in, so its background does not smear across the gap.
    for int i = from, i < to, i++ { refitFragmentedChild(b.children[i]) }
    return tallest
}

// Whether a column may break just before unit `i`, given the unit the
// current column started at. A break between two children is always
// allowed; inside one child's run of lines it has to leave `orphans`
// lines behind and take `widows` lines with it. `relaxWidows` drops the
// second of those, which is what the standard asks for when the pair
// cannot both be honoured -- five orphans and five widows of six lines
// is a contradiction, and the answer is not to refuse to break.
bool func columnBreakAllowed(units:arr[ColumnUnit], i:int, colStart:int, relaxWidows:bool) {
    if units[i].forceBefore { return true }
    if units[i].avoidBefore { return false }
    if !units[i].hasLine || units[i].lineIndex == 0 { return true }
    int above = units[i].lineIndex
    if units[colStart].hasLine && units[colStart].childIndex == units[i].childIndex {
        above = units[i].lineIndex - units[colStart].lineIndex
    }
    if above < units[i].orphans { return false }
    if !relaxWidows && units[i].lineTotal - units[i].lineIndex < units[i].widows { return false }
    return true
}

// The unit each column after the first starts at, for a given column
// height. The balancing loop and the placement loop both read this one
// answer rather than each deciding for itself, because they must agree:
// a target that says two columns and a placement that makes three would
// be a container the height of a column it does not contain.
arr[int] func columnBreaks(units:arr[ColumnUnit], target:int) {
    arr[int] out = []
    int colStart = 0
    int colTop = units[0].top
    int i = 1
    while i < units.length {
        bool overflow = units[i].bottom - colTop > target && units[i].top > colTop
        if !units[i].forceBefore && !overflow {
            i++
            continue
        }
        int at = columnBreakPoint(units, i, colStart)
        if at < 0 { break }
        out.push(at)
        colStart = at
        colTop = units[at].top
        i = at + 1
    }
    return out
}

// The break to take when the column has run out of room before unit
// `i`. The first allowed point from `i` onwards, since a forbidden
// break means the content carries on into the column it did not fit;
// failing that the last allowed point before it, which is how `widows`
// pulls a break earlier when no later one can satisfy it; failing that
// the same two searches with widows dropped. Answers -1 when this
// column cannot be ended at all.
int func columnBreakPoint(units:arr[ColumnUnit], i:int, colStart:int) {
    for int pass = 0, pass < 2, pass++ {
        bool relax = pass == 1
        for int j = i, j < units.length, j++ {
            if columnBreakAllowed(units, j, colStart, relax) { return j }
        }
        for int k = i - 1, k > colStart, k-- {
            if columnBreakAllowed(units, k, colStart, relax) { return k }
        }
    }
    return -1
}

// Which container the units are being collected for. A `column` ends a
// column and a `page` ends a page, and neither ends the other: Chromium
// leaves a column exactly where it was when a child inside it asks for
// `break-before: page`, because on screen there is no page to break.
bool fragForPage = false

void func collectColumnUnits(b:Box, out:arr[ColumnUnit], from:int, to:int) {
    bool pendingForce = false
    bool pendingAvoid = false
    int forces = fragForPage ? BRK_PAGE : BRK_COLUMN
    text pendingPage = ''
    bool havePage = false
    for int i = from, i < to, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        if boxIsOutOfFlow(c) || boxIsFloated(c) { continue }
        bool force = pendingForce || c.style.breakBefore == forces
        bool avoid = pendingAvoid || c.style.breakBefore == BRK_AVOID
        // A change of `page` between two siblings forces a break, since
        // the two belong on differently named pages (Paged Media 3
        // §3.4). On screen there are no named pages and nothing to do.
        if fragForPage {
            if havePage && c.style.pageName != pendingPage { force = true }
            pendingPage = c.style.pageName
            havePage = true
        }
        pendingForce = c.style.breakAfter == forces
        pendingAvoid = c.style.breakAfter == BRK_AVOID
        // A child that may not be broken goes in as one unit, however
        // many lines it holds: a unit is the smallest thing a column
        // takes, so making it the whole child is what `avoid` means.
        if c.lines.length > 0 && !c.style.breakInsideAvoid {
            for int j = 0, j < c.lines.length, j++ {
                ColumnUnit u
                u.box = c
                u.line = c.lines[j]
                u.hasLine = true
                u.top = c.lines[j].y
                u.bottom = c.lines[j].y + c.lines[j].h
                // The last line carries whatever of the child sits
                // below it -- a declared height, a bottom padding, a
                // margin -- because that space is in the container too,
                // and a fragmenter that measured the text alone would
                // fit four 120px blocks into 80px of column.
                if j == c.lines.length - 1 {
                    u.bottom = maxInt(u.bottom, c.y + c.h + c.mb)
                }
                u.forceBefore = j == 0 && force
                u.avoidBefore = j == 0 && avoid
                u.childIndex = i
                u.lineIndex = j
                u.lineTotal = c.lines.length
                u.orphans = c.style.orphans
                u.widows = c.style.widows
                out.push(u)
            }
            continue
        }
        ColumnUnit u
        u.box = c
        u.top = c.y - c.mt
        u.bottom = c.y + c.h + c.mb
        if c.lines.length > 0 {
            // A whole child that holds lines still covers them, so its
            // own rectangle is the union rather than its laid-out box.
            u.top = minInt(u.top, c.lines[0].y)
            u.bottom = maxInt(u.bottom, c.lines[c.lines.length - 1].y + c.lines[c.lines.length - 1].h)
        }
        u.forceBefore = force
        u.avoidBefore = avoid
        u.childIndex = i
        out.push(u)
    }
}

void func offsetLine(ln:Line, dx:int, dy:int) {
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

// After the lines have moved, a child that holds them may cover several
// columns. Its own rectangle is refitted to the lines that share its
// first column, so its background and border stay in one place.
void func refitFragmentedChild(c:Box) {
    if c.lines.length == 0 { return }
    int firstX = c.lines[0].x
    int top = c.lines[0].y
    int bottom = c.lines[0].y + c.lines[0].h
    for int i = 0, i < c.lines.length, i++ {
        if c.lines[i].x != firstX { continue }
        top = minInt(top, c.lines[i].y)
        bottom = maxInt(bottom, c.lines[i].y + c.lines[i].h)
    }
    c.x = firstX
    c.y = top
    c.h = maxInt(bottom - top, 0)
}

int func layoutBlockChildren(b:Box, cx:int, cy:int, cw:int) {
    return layoutBlockChildrenRange(b, cx, cy, cw, 0, b.children.length)
}

// The same, over a run of the children rather than all of them, which
// is what a multi-column container needs once a `column-span: all`
// child has split it into sections.
int func layoutBlockChildrenRange(b:Box, cx:int, cy:int, cw:int, from:int, to:int) {
    int y = cy
    int prevBottomMargin = 0
    bool first = true
    bool parentAbsorbsTop = b.bt == 0 && b.pt == 0 && (b.kind == BOX_BLOCK || b.kind == BOX_ANON) && b.parentId > 0 && parentKind(b) != BOX_CELL && parentKind(b) != BOX_INLINE_BLOCK && !b.isListItem
    int lastMarginBottom = 0
    for int i = from, i < to, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        // An absolutely positioned box is out of flow: it takes no
        // space here and is laid out by the positioning pass once the
        // containing block it resolves against is known (CSS2 §9.3).
        // Where the flow had reached is its static position, which an
        // `auto` inset resolves to, so it is noted on the way past.
        if boxIsOutOfFlow(c) {
            if docHasPositioned {
                staticPosX[`${c.id}`] = cx
                staticPosY[`${c.id}`] = y
            }
            continue
        }
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
        justifyBlockChild(b, c, cx, cw)
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
bool ifcHardBreak = false         // the line being closed ends at a break the content asked for
// Whether the block being laid out has a ::first-line rule. False on
// every page that names no such rule, which is what keeps the lookup
// below off the hot path.
bool ifcFirstLine = false
// The element whose ::first-line rule is in force. It is the block
// being laid out, except where that block's inline content sits in an
// anonymous box -- a block with both inline and block-level children --
// and the rule belongs to the element the anonymous box stands in for.
Box ifcFirstLineBlock = null
// The stand-in boxes the first line's fragments point at, by the id of
// the box they stand for. A fragment carries a Box and every reader --
// the line metrics, the painter, hit testing -- asks it for a style, so
// giving the first line its own boxes restyles it everywhere at once
// without a second field on Fragment or a test in any of those loops.
map[Box] firstLineBoxes = {}

// The style this box wears right now: the ::first-line variant while
// the first line of such a block is being filled, and its own style
// otherwise. One boolean rules the whole thing out on a page that names
// no ::first-line.
Style func firstLineStyleFor(b:Box) {
    if !ifcFirstLine || ifcLineCount != 0 { return b.style }
    if b.node == null || b.node.id <= 0 { return b.style }
    Style fls = firstLineStyles[`${b.node.id}`]
    return fls == null ? b.style : fls
}

// The style the line box itself takes: the ::first-line rule sets the
// strut of the first line, so a rule that only shrinks the line height
// is obeyed as well as one that grows it.
Style func firstLineStrutStyle() {
    if !ifcFirstLine || ifcLineCount != 0 { return ifcBox.style }
    Style fls = firstLineStyles[`${ifcFirstLineBlock.node.id}`]
    return fls == null ? ifcBox.style : fls
}

// The box a fragment placed right now should point at: a stand-in
// carrying the first-line style, or the box itself.
Box func firstLineBoxFor(b:Box) {
    Style fls = firstLineStyleFor(b)
    // Two Styles are compared by serial: one struct value against
    // another does not compile (FINDINGS.md, finding 37), and every
    // computed style carries a serial for exactly this.
    if fls.serial == b.style.serial { return b }
    text key = `${b.id}`
    Box cached = firstLineBoxes[key]
    if cached != null { return cached }
    Box fb = newBox(b.kind, b.node, fls)
    fb.content = b.content
    fb.parentId = b.parentId
    fb.depth = b.depth
    firstLineBoxes[key] = fb
    return fb
}

// The drop cap in this block's inline content, or null. Guarded by
// `anyInitialLetter` at its one caller, so a page that names no
// `initial-letter` never walks a child list for one.
Box func initialLetterBox(b:Box) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        // The drop cap's own text box carries the same style, so the
        // test is that this box is the float, not merely that it has
        // the property: otherwise the letter pushes its own content
        // down by the space it is supposed to rise into.
        if boxIsFloated(c) && initialLetterPacked(c.style) != 0 { return c }
        if c.kind == BOX_INLINE || c.kind == BOX_ANON {
            Box r = initialLetterBox(c)
            if r != null { return r }
        }
    }
    return null
}

int func layoutInlineContent(b:Box, cx:int, cy:int, cw:int) {
    Box savedBox = ifcBox
    int savedX = ifcX
    int savedStart = ifcLineStart
    int savedRight = ifcLineRight
    int savedY = ifcY
    // The containing block's edges belong to this formatting context
    // and are restored with the rest of it. A float in inline content
    // is laid out from inside the line it interrupts, so its own
    // inline content runs through here and would otherwise leave the
    // outer context wrapping its text in the FLOAT's containing block.
    int savedCbLeft = ifcCbLeft
    int savedCbRight = ifcCbRight
    arr[Fragment] savedFrags = ifcFrags
    bool savedPending = ifcPendingSpace
    bool savedHas = ifcLineHasContent
    int savedCount = ifcLineCount
    arr[Box] savedOpen = ifcOpenInlines
    arr[Fragment] savedOpenBg = ifcOpenBg
    bool savedFirstLine = ifcFirstLine
    Box savedFirstLineBlock = ifcFirstLineBlock

    // An anonymous box holds the inline content of a block that also
    // has block-level children, and the first of those anonymous boxes
    // carries that block's first line.
    ifcFirstLineBlock = b
    if anyFirstLine && b.kind == BOX_ANON && b.parentId > 0 {
        Box par = parentBox(b)
        if par.children.length > 0 && par.children[0].id == b.id { ifcFirstLineBlock = par }
    }
    ifcFirstLine = anyFirstLine && ifcFirstLineBlock.node != null
        && ifcFirstLineBlock.node.id > 0
        && pseudoHasFirstLine[pseudoKey(ifcFirstLineBlock.node.id, 'first-line')] != null

    ifcBox = b
    b.lines = []
    ifcCbLeft = cx
    ifcCbRight = cx + cw
    ifcLineStart = cx
    ifcLineRight = cx + cw
    ifcY = cy
    // CSS Inline 3: a drop cap spans `size` lines but only shortens
    // `sink` of them, and what is left over goes ABOVE the text. So
    // the block grows by `size - sink` lines and its text begins that
    // many lines down; the letter itself is lifted back up into them
    // in `placeDropCap`.
    if anyInitialLetter {
        Box cap = initialLetterBox(b)
        if cap != null {
            int capLh = lineHeightOf(b.style)
            int above = Math.floorDiv(initialLetterSize100(cap.style) * capLh, 100)
                        - initialLetterSink(cap.style) * capLh
            if above > 0 { ifcY = ifcY + above }
        }
    }
    ifcLineCount = 0
    ifcOpenInlines = []
    ifcOpenBg = []
    beginLine()
    for int i = 0, i < b.children.length, i++ {
        placeInline(b.children[i])
    }
    finishLine(false)
    // The other half of `text-box-trim`: the last line's bottom, now
    // that there is a last line. Trimming it shortens the block by what
    // it removes, which is what the height below picks up.
    if anyTextBoxTrim && b.lines.length > 0 {
        int under = textBoxUnderEdge(b.style)
        if under >= 0 {
            int li = b.lines.length - 1
            int lAbove = b.lines[li].baseline - b.lines[li].y
            int lBelow = b.lines[li].h - lAbove
            b.lines[li].h = lAbove + under
            ifcY = ifcY - (lBelow - under)
        }
    }
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
    ifcCbLeft = savedCbLeft
    ifcCbRight = savedCbRight
    ifcFrags = savedFrags
    ifcPendingSpace = savedPending
    ifcLineHasContent = savedHas
    ifcLineCount = savedCount
    ifcOpenInlines = savedOpen
    ifcOpenBg = savedOpenBg
    ifcFirstLine = savedFirstLine
    ifcFirstLineBlock = savedFirstLineBlock
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

// The horizontal space an inside marker takes at the start of the first
// line. The painter draws the marker into exactly this space, so the
// two agree by construction rather than by two formulas that look
// alike.
// The style a list item's marker is drawn in: its ::marker rule where
// there is one, and the item's own style otherwise. The pseudo-element's
// style is computed with the item as its parent, so an inherited
// property -- `list-style-type`, `list-style-position`, `color` -- is
// already the item's unless the rule changed it.
//
// A page that names no ::marker pays one boolean.
Style func markerStyleOf(b:Box) {
    if !anyMarker || b.node == null || b.node.id <= 0 { return b.style }
    if pseudoHasMarker[pseudoKey(b.node.id, 'marker')] == null { return b.style }
    return pseudoStyleOf(b.node.id, 'marker')
}

// What the marker says. A `content` on ::marker replaces the counter
// label with its own string, which is what `content: counter(list-item)`
// is for -- and an empty one draws nothing at all.
text func markerContentOf(b:Box) {
    if !anyMarker || b.node == null || b.node.id <= 0 { return null }
    if pseudoHasMarker[pseudoKey(b.node.id, 'marker')] == null { return null }
    return pseudoContentOf(b.node.id, 'marker')
}

int func listMarkerAdvance(s:Style, index:int) {
    if s.listStyle == LIST_NONE { return 0 }
    int fs = s.fontSize
    if s.listStyle == LIST_DISC || s.listStyle == LIST_CIRCLE || s.listStyle == LIST_SQUARE {
        return roundPx(fs.toFloat() * 1.3)
    }
    text label = s.listStyleName != ''
        ? counterStyleLabel(s.listStyleName, index) + counterStyleSuffix(s.listStyleName)
        : `${listMarkerLabel(index, s.listStyle)}.`
    return measureWidth(s, label) + roundPx(fs.toFloat() * 0.5)
}

void func beginLine() {
    ifcFrags = []
    applyFloatsToLine()
    ifcX = ifcLineStart
    if ifcLineCount == 0 && ifcBox.style.textIndent != 0 { ifcX = ifcX + ifcBox.style.textIndent }
    // An inside marker is part of the first line and pushes the content
    // along; an outside one hangs in the margin and costs nothing here.
    if ifcLineCount == 0 && ifcBox.isListItem && ifcBox.style.listInside {
        Style ms = markerStyleOf(ifcBox)
        text mc = markerContentOf(ifcBox)
        ifcX = ifcX + (mc == null ? listMarkerAdvance(ms, ifcBox.listIndex)
                                  : measureWidth(ms, mc))
    }
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
        // `box-decoration-break: clone` gives every fragment the whole
        // box, so a continuation opens with the margin, border and
        // padding the first fragment had, and its content starts after
        // them.
        if decorationIsClone(ib.style) {
            int se = ib.ml + ib.bl + ib.pl
            f.w = se
            f.edges = FRAGEDGE_START
            ifcX = ifcX + se
        }
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
    f.edges = FRAGEDGE_NONE
    return f
}

// Closes the current line: computes its height and baseline, aligns
// the fragments vertically and horizontally, records it.
void func finishLine(forced:bool) {
    int t0 = archtelosTiming ? now() : 0
    finishLineUncounted(forced)
    if archtelosTiming { profFinishMs = profFinishMs + (now() - t0) }
}

// Cuts the line back to the ellipsis. Characters are dropped from the
// end until what is left plus the ellipsis fits, which is a measurement
// per character dropped -- paid only by a line that actually overflows
// a clipping box.
void func ellipsiseLine() {
    // The character itself, not `\u2026`: Festina drops an unknown
    // escape's backslash silently, so that spelling is the five
    // characters `u2026` (FINDINGS.md, finding 34).
    text dots = '…'
    int limit = ifcLineRight
    for int i = ifcFrags.length - 1, i >= 0, i-- {
        Fragment f = ifcFrags[i]
        if f.kind != FRAG_TEXT { continue }
        int dw = measureWidth(f.box.style, dots)
        if f.x + dw > limit {
            // this fragment has no room even for the ellipsis: drop it
            // and try the one before
            f.content = ''
            f.w = 0
            continue
        }
        arr[text] chars = f.content.split('')
        for int n = chars.length, n > 0, n-- {
            text cut = ''
            for int k = 0, k < n, k++ { cut = cut + chars[k] }
            int w = measureWidth(f.box.style, cut + dots)
            if f.x + w <= limit {
                f.content = cut + dots
                f.w = w
                ifcX = f.x + w
                return
            }
        }
        f.content = dots
        f.w = dw
        ifcX = f.x + dw
        return
    }
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
        // The strut of the first line is the ::first-line style's, so a
        // rule that only shrinks the line height is obeyed as well as
        // one that grows it.
        Style ss = firstLineStrutStyle()
        int lh = lineHeightOf(ss)
        int content = fontAscent(ss) + fontDescent(ss)
        int half = Math.floorDiv(lh - content, 2)
        strutAbove = half + fontAscent(ss)
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
    // CSS Inline 3: `text-box-trim` takes the leading off the first
    // line's top. The last line's bottom is trimmed once the block's
    // lines are all in, since which one is last is not known here.
    if anyTextBoxTrim && ifcLineCount == 0 {
        // Set to the edge rather than shrink to it: at a line height
        // below the content height the leading is negative, and
        // trimming it then makes the line taller. That is what the
        // measurement shows -- 24 at line-height 1, 2 and 3 alike.
        int over = textBoxOverEdge(bs)
        if over >= 0 { above = over }
    }
    int lineH = above + below
    int baseline = ifcY + above
    // The bidirectional algorithm runs on the finished line, because it
    // is a line's characters that are put into visual order and the
    // line is not known until it is broken. A fragment holds all of one
    // text box's characters on this line, so reordering it is the whole
    // line for the ordinary case of a paragraph of one script; a line
    // that mixes two inline boxes is reordered within each of them and
    // not across the two, which css-2026.md records.
    // `unicode-bidi` belongs to the element the text is in rather than
    // to the block, so it is read off the fragment's own box -- a text
    // box carries its element's style, which is where an inline's value
    // is.
    if bs.directionRtl || anyRtlText || anyUnicodeBidi {
        int baseLevel = bs.directionRtl ? 1 : 0
        for int i = 0, i < ifcFrags.length, i++ {
            Fragment f = ifcFrags[i]
            if f.kind != FRAG_TEXT { continue }
            int mode = f.box == null ? UBIDI_NORMAL : f.box.style.unicodeBidi
            if mode == UBIDI_NORMAL && !bidiNeedsReorder(f.content) && !bs.directionRtl { continue }
            bool rtl = f.box == null ? bs.directionRtl : f.box.style.directionRtl
            f.content = bidiVisualStyled(f.content, baseLevel, mode, rtl)
        }
    }
    // text-overflow: ellipsis replaces the end of a line that runs out
    // of its box with an ellipsis. It needs a box that clips, because
    // there is nothing to hide otherwise, which is why a box with no
    // `overflow` keeps its whole line.
    if bs.textOverflowEllipsis && bs.overflowHidden && ifcX > ifcLineRight {
        ellipsiseLine()
    }
    // horizontal alignment
    int used = ifcX - ifcLineStart
    int freeSpace = (ifcLineRight - ifcLineStart) - used
    int shift = 0
    // text-align-last governs the last line of the block and any line
    // the content broke itself; every other line takes text-align.
    int align = bs.textAlign
    if bs.textAlignLast >= 0 && (!forced || ifcHardBreak) { align = bs.textAlignLast }
    if freeSpace > 0 {
        if align == ALIGN_CENTER { shift = Math.floorDiv(freeSpace, 2) }
        else if align == ALIGN_RIGHT { shift = freeSpace }
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
            // An inline's decorations go on its content area -- the
            // font's ascent and descent about the baseline, which is
            // neither the line box nor the inline's own line-height --
            // grown by its padding and border. None of that changes
            // the line height: the box paints outside the line and the
            // block is no taller for it.
            Box ib = f.box
            Style is = ib.style
            f.baseline = baseline
            f.y = baseline - fontAscent(is) - ib.pt - ib.bt
            f.h = fontAscent(is) + fontDescent(is) + ib.pt + ib.bt + ib.pb + ib.bb
            // and how far outside the line box that reaches, which is
            // what the painter widens its culls by
            int above = ifcY - f.y
            if above > inlineInkOverhang { inlineInkOverhang = above }
            int below = f.y + f.h - (ifcY + lineH)
            if below > inlineInkOverhang { inlineInkOverhang = below }
        }
    }
    // `clone` closes every fragment of an inline that breaks, and the
    // closing edge overflows the line rather than forcing an earlier
    // break -- which is what Chromium does: the same characters stay on
    // the same lines. Innermost first, so an outer inline's box still
    // ends outside the inner one's closing edge. A document with no
    // inline open across this break never enters the loop.
    int cloneEnd = 0
    for int i = ifcOpenBg.length - 1, i >= 0, i-- {
        Fragment f = ifcOpenBg[i]
        if f.w <= 0 { continue }
        f.w = f.w + cloneEnd
        Box cb = f.box
        if !decorationIsClone(cb.style) { continue }
        int ee = cb.pr + cb.br + cb.mr
        f.w = f.w + ee
        cloneEnd = cloneEnd + ee
        f.edges = f.edges == FRAGEDGE_START ? FRAGEDGE_BOTH : FRAGEDGE_END
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

// A break the content asked for -- a <br>, or a newline in preserved
// text -- rather than one the line ran out of room for. The line it
// closes is a last line, so it takes text-align-last.
void func hardBreakLine() {
    ifcHardBreak = true
    finishLine(true)
    ifcHardBreak = false
    beginLine()
}

void func placeInline(b:Box) {
    if boxIsOutOfFlow(b) {
        // An inline-level out-of-flow box takes its static position
        // from the pen on the line it was written on.
        if docHasPositioned {
            staticPosX[`${b.id}`] = ifcX
            staticPosY[`${b.id}`] = ifcY
        }
        return
    }
    if boxIsFloated(b) {
        if initialLetterPacked(b.style) != 0 {
            placeDropCap(b)
        } else {
            placeFloat(b, ifcCbLeft, ifcCbRight, ifcY)
        }
        // the float may have narrowed the line that is open
        applyFloatsToLine()
        return
    }
    if b.kind == BOX_TEXT {
        placeText(b)
        return
    }
    if b.kind == BOX_BR {
        hardBreakLine()
        return
    }
    if b.kind == BOX_INLINE {
        resolveEdges(b, ifcLineRight - ifcLineStart)
        // start edge: margin + border + padding
        int startEdge = b.ml + b.bl + b.pl
        Fragment f = newFragment(FRAG_INLINE_BG, b, '')
        // this fragment begins the inline, so it carries the opening
        // margin, border and padding that startEdge just reserved
        f.edges = FRAGEDGE_START
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
        // extend this inline's fragment on the current line, and mark
        // it as the one carrying the closing margin, border and padding
        Fragment closing = ifcOpenBg[ifcOpenBg.length - 1]
        closing.edges = closing.edges == FRAGEDGE_START ? FRAGEDGE_BOTH : FRAGEDGE_END
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
        if ifcX + sw + total > ifcLineRight && !wsNoWrap(ifcBox.style) {
            breakLine()
        } else {
            ifcX = ifcX + sw
        }
        ifcPendingSpace = false
    } else if ifcLineHasContent && ifcX + total > ifcLineRight && !wsNoWrap(ifcBox.style) {
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
    Style s = firstLineStyleFor(b)
    text t = b.content
    if t == null || t == '' { return }
    bool keepBreaks = wsKeepsBreaks(s)
    bool nowrap = wsNoWrap(s)
    arr[text] words = wordsOf(b)
    int sw = spaceWidth(s)
    if keepBreaks {
        // each element is one preserved line; the break between two of
        // them is one the content asked for, so it ends a last line
        for int i = 0, i < words.length, i++ {
            if i > 0 { hardBreakLine() }
            text w = words[i]
            if w == '' { continue }
            int ww = measureWidth(s, w)
            if !nowrap && ifcX + ww > ifcLineRight {
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
            // The word has left the first line, so it is no longer
            // wearing ::first-line's font: measure it again in the one
            // it will actually be set in.
            if ifcFirstLine {
                s = firstLineStyleFor(b)
                sw = spaceWidth(s)
                ww = measureWidth(s, w)
            }
        }
        if spaceBefore { ifcX = ifcX + spaceW }
        ifcPendingSpace = false
        if hasSoftHyphen(w) { placeSoftHyphenated(b, w) }
        else if wordMustBreak(s, ww) { placeWordInPieces(b, w) }
        else { appendWord(b, w, ww) }
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

void func placeWrappedWords(b:Box, words:arr[text], swIn:int) {
    Style s = firstLineStyleFor(b)
    int sw = swIn
    for int i = 0, i < words.length, i++ {
        text w = words[i]
        int ww = w == '' ? 0 : measureWidth(s, w)
        int needed = ww + (i > 0 ? sw : 0)
        if ifcLineHasContent && ifcX + needed > ifcLineRight {
            breakLine()
            if ifcFirstLine {
                s = firstLineStyleFor(b)
                sw = spaceWidth(s)
                ww = w == '' ? 0 : measureWidth(s, w)
            }
            needed = ww
        } else if i > 0 {
            ifcX = ifcX + sw
        }
        if w == '' { continue }
        if wordMustBreak(s, ww) { placeWordInPieces(b, w) }
        else { appendWord(b, w, ww) }
    }
}

// A soft hyphen (U+00AD) shows nothing unless the line breaks at it,
// and then shows a hyphen. Written as the code point because the
// language has no way to spell a non-ASCII escape (FINDINGS.md,
// findings 13 and 34).
const int SOFT_HYPHEN = 173

bool func hasSoftHyphen(w:text) {
    for int i = 0, i < w.length, i++ {
        if w.charCodeAt(i) == SOFT_HYPHEN { return true }
    }
    return false
}

text func stripSoftHyphens(w:text) {
    text out = ''
    for int i = 0, i < w.length, i++ {
        if w.charCodeAt(i) != SOFT_HYPHEN { out = out + w[i] }
    }
    return out
}

// `text` has no substring of its own (FINDINGS.md, finding 6), and a
// soft hyphen puts the word outside what `ascii` can hold, so the two
// halves are built a character at a time.
text func textRange(w:text, from:int, to:int) {
    text out = ''
    for int i = from, i < to && i < w.length, i++ { out = out + w[i] }
    return out
}

// Places a word holding soft hyphens, breaking at the last one whose
// prefix still fits with a hyphen after it. The parts that are not
// broken at contribute nothing, which is what makes the hyphen soft.
// What a hyphenation break draws. `hyphenate-character` names it and
// the initial `auto` leaves it to the browser, which is a hyphen here
// (CSS Text 4). The string counts towards the width of the prefix that
// has to fit, so a longer one can move the break.
text func hyphenStringOf(s:Style) {
    return s.hyphenChar == '' ? '-' : s.hyphenChar
}

void func placeSoftHyphenated(b:Box, w:text) {
    Style s = firstLineStyleFor(b)
    text pending = w
    while true {
        if ifcFirstLine { s = firstLineStyleFor(b) }
        text plain = stripSoftHyphens(pending)
        int plainW = measureWidth(s, plain)
        if ifcX + plainW <= ifcLineRight || s.hyphensNone {
            appendWord(b, plain, plainW)
            return
        }
        // the last break point that fits, hyphen included
        int best = -1
        int bestW = 0
        text prefix = ''
        for int i = 0, i < pending.length, i++ {
            if pending.charCodeAt(i) != SOFT_HYPHEN { continue }
            text candidate = stripSoftHyphens(textRange(pending, 0, i)) + hyphenStringOf(s)
            int cw = measureWidth(s, candidate)
            if ifcX + cw <= ifcLineRight {
                best = i
                bestW = cw
                prefix = candidate
            }
        }
        if best < 0 {
            // nothing fits on what is left of this line; a fresh line
            // is the only thing that can change that
            if ifcLineHasContent { breakLine()  continue }
            appendWord(b, plain, plainW)
            return
        }
        appendWord(b, prefix, bestW)
        breakLine()
        pending = textRange(pending, best + 1, pending.length)
    }
}

// Whether this word has to be broken inside itself to be placed.
// `break-all` breaks any word that does not fit in the room left on
// the line; `break-word` waits until the word would not fit on a line
// of its own, which is the whole difference between the two.
bool func wordMustBreak(s:Style, ww:int) {
    if s.wordBreaking == BREAK_NONE || wsNoWrap(s) { return false }
    if ifcX + ww <= ifcLineRight { return false }
    if s.wordBreaking == BREAK_ALL { return true }
    return ww > ifcLineRight - ifcLineStart
}

// Places a word one character at a time, breaking wherever the next
// character would not fit. Each character is measured on its own, so a
// pair the font kerns is measured slightly wide; appendWord merges the
// run back into one fragment per line, so only the break position is
// affected.
void func placeWordInPieces(b:Box, w:text) {
    Style s = firstLineStyleFor(b)
    arr[text] chars = w.split('')
    for int i = 0, i < chars.length, i++ {
        int cw = measureWidth(s, chars[i])
        if ifcLineHasContent && ifcX + cw > ifcLineRight {
            breakLine()
            if ifcFirstLine {
                s = firstLineStyleFor(b)
                cw = measureWidth(s, chars[i])
            }
        }
        appendWord(b, chars[i], cw)
    }
}

// Adds a word to the line, merging with a preceding run of the same
// text box (separated by the space already advanced over).
void func appendWord(bIn:Box, w:text, ww:int) {
    // One boolean on the hottest path in inline layout: a page that
    // names no ::first-line never reaches the lookup.
    Box b = ifcFirstLine ? firstLineBoxFor(bIn) : bIn
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

// table-layout: fixed -- the column widths come from the first row and
// nothing else (CSS2 17.5.2.1). A cell with a width gets it; the rest
// share what is left equally. No cell's content is measured, which is
// the whole point of the algorithm and the reason it is a separate
// pass rather than a flag inside the automatic one.
arr[int] func fixedTableColumnWidths(b:Box, target:int, spacing:int) {
    int cols = tableColumnCount(b)
    arr[int] widths = []
    for int i = 0, i < cols, i++ { widths.push(-1) }
    int available = target - spacing * (cols + 1)
    for int i = 0, i < b.children.length, i++ {
        Box row = b.children[i]
        if row.kind != BOX_ROW { continue }
        int col = 0
        for int j = 0, j < row.children.length, j++ {
            Box cell = row.children[j]
            int span = cell.colspan
            if span == 1 && col < cols {
                if cell.style.width.kind == LEN_PX {
                    widths[col] = maxInt(roundPx(cell.style.width.v), 0)
                } else if cell.style.width.kind == LEN_PERCENT {
                    widths[col] = maxInt(roundPx(available.toFloat() * cell.style.width.v / 100.0), 0)
                }
            }
            col = col + span
        }
        break
    }
    int assigned = 0
    int flexible = 0
    for int i = 0, i < cols, i++ {
        if widths[i] >= 0 { assigned = assigned + widths[i] } else { flexible++ }
    }
    int left = maxInt(available - assigned, 0)
    if flexible > 0 {
        int each = Math.floorDiv(left, flexible)
        // the last flexible column takes the remainder, so the columns
        // add up to the table's width exactly rather than to a pixel less
        int placed = 0
        int seen = 0
        for int i = 0, i < cols, i++ {
            if widths[i] >= 0 { continue }
            seen++
            widths[i] = seen == flexible ? left - placed : each
            placed = placed + widths[i]
        }
    }
    return widths
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
    bool fixedLayout = s.tableLayoutFixed
    // the automatic algorithm's intrinsic pass is skipped entirely when
    // the widths do not depend on the cells
    arr[ColumnInfo] cols = []
    if !fixedLayout { cols = tableColumns(b) }
    int n = fixedLayout ? tableColumnCount(b) : cols.length
    int edges = b.pl + b.pr + b.bl + b.br
    int totalMin = spacing
    int totalMax = spacing
    for int i = 0, i < cols.length, i++ {
        totalMin = totalMin + cols[i].minW + spacing
        totalMax = totalMax + maxInt(cols[i].maxW, cols[i].fixedW) + spacing
    }
    int avail = cw - b.ml - b.mr - edges
    int target = 0
    bool fixedWidth = !lenIsAuto(s.width)
    if fixedLayout {
        // with no intrinsic widths to fall back on, an auto width is
        // the space available
        target = fixedWidth ? resolveLen(s.width, cw, 0) : avail
    } else if fixedWidth {
        target = maxInt(resolveLen(s.width, cw, 0), totalMin)
    } else {
        target = minInt(totalMax, avail)
        if target < totalMin { target = totalMin }
    }
    if fixedLayout {
        arr[int] fw = fixedTableColumnWidths(b, target, spacing)
        layoutTableWithWidths(b, cx, y, cw, fw, spacing, edges, target, true)
        return
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
    layoutTableWithWidths(b, cx, y, cw, widths, spacing, edges, target, fixedWidth)
}

// Everything after the column widths are known: the table's own width,
// its margins, then the rows and cells placed into those widths. Both
// column algorithms end here, which is what keeps `table-layout: fixed`
// a different way of choosing widths rather than a second table layout.
void func layoutTableWithWidths(b:Box, cx:int, y:int, cw:int, widths:arr[int],
                                spacing:int, edges:int, target:int, fixedWidth:bool) {
    Style s = b.style
    int n = widths.length
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

// How far an item may shrink along the main axis (Flexible Box 1 §4.5).
//
// An item whose `min-width` is `auto` -- the initial value -- does not
// shrink below what its content needs: the smaller of its own declared
// size and its min-content size, so an unbreakable word keeps the item
// as wide as the word and the item overflows rather than the word being
// cut. A declared minimum takes that away, and so does the item being a
// scroll container, whose automatic minimum the standard puts at zero
// because the content can scroll instead.
int func flexMinMainSize(item:Box, row:bool, inner:int) {
    Style s = item.style
    Len declared = row ? s.minWidth : s.minHeight
    if declared.kind != LEN_AUTO { return maxInt(resolveLen(declared, inner, 0), 0) }
    if s.overflowHidden { return 0 }
    if !row { return 0 }
    computeIntrinsic(item)
    int content = maxInt(item.contentMin, 0)
    Len own = s.width
    if !lenIsAuto(own) {
        int specified = maxInt(resolveLen(own, inner, 0), 0)
        if specified < content { return specified }
    }
    return content
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

// ---- CSS Grid -------------------------------------------------------------
//
// Three passes, in the order the standard puts them: place every item
// on the two axes, size the tracks those placements imply, then lay
// each item out inside the area it occupies.
//
// An item's placement is a half-open range of track indices on each
// axis. Both are resolved before any track is sized, because a track's
// size can depend on the items in it and an item's track cannot depend
// on any size.
struct GridArea {
    box:Box
    col:int
    colSpan:int
    row:int
    rowSpan:int
}

// The track index an edge pair resolves to, as a start and a span.
// A line number counts from 1 and may be negative, counting back from
// the end; `span n` fixes the width without fixing the position, which
// is what leaves the item to auto-placement.
int gridResolvedStart = 0
int gridResolvedSpan = 1
bool gridResolvedAuto = false

// ---- named grid lines ------------------------------------------------------
//
// A line name is resolved against the container's template, not the
// item's own style, so it stays a name in the cascade and is looked up
// here. Two sources: the names a track list wrote in brackets, and the
// `<name>-start` and `<name>-end` lines every area of
// `grid-template-areas` creates around itself (Grid 1 §7.3).
//
// `grid-row-start: foo` prefers a line named `foo-start` and falls back
// to one named `foo`, which is what makes `grid-area: foo` land on the
// area rather than on a line that happens to share its name; the end
// edge prefers `foo-end` the same way.

// The line a name sits at in `s`'s template for one axis, or 0 for
// none. Lines count from 1.
int func gridNamedLine(s:Style, name:text, inline:bool) {
    arr[text] names = inline ? s.gridColLineNames : s.gridRowLineNames
    arr[int] at = inline ? s.gridColLineAt : s.gridRowLineAt
    for int i = 0, i < names.length, i++ {
        if names[i] == name { return at[i] }
    }
    return 0
}

// The line an area's edge sits at: `edgeStart` asks for the first line
// of the area, otherwise the line after its last track.
int func gridAreaLine(s:Style, name:text, inline:bool, edgeStart:bool) {
    int cols = s.gridAreaCols
    if cols <= 0 || name == '' { return 0 }
    int found = -1
    int minAt = -1
    int maxAt = -1
    for int i = 0, i < s.gridAreaNames.length, i++ {
        if s.gridAreaNames[i] != name { continue }
        int at = inline ? i % cols : Math.floorDiv(i, cols)
        if found < 0 { minAt = at  maxAt = at  found = i }
        else {
            if at < minAt { minAt = at }
            if at > maxAt { maxAt = at }
        }
    }
    if found < 0 { return 0 }
    return edgeStart ? minAt + 1 : maxAt + 2
}

// One edge, named: the `-start`/`-end` line an area makes, then a line
// of that exact name. 0 when the template knows neither, which leaves
// the edge automatic.
int func gridResolveName(s:Style, name:text, inline:bool, edgeStart:bool) {
    if name == null || name == '' { return 0 }
    // The bare name of an area: `grid-area: a` on a start edge is the
    // area's first line, on an end edge the line after its last.
    int fromArea = gridAreaLine(s, name, inline, edgeStart)
    if fromArea > 0 { return fromArea }
    // The area also creates lines literally named `a-start` and
    // `a-end`, which is how `grid-column: a-start / a-end` reaches the
    // same rectangle by another route.
    ascii lowered = name.toAscii()
    if asciiEndsWith(lowered, '-start'.toAscii()) {
        int n = gridAreaLine(s, lowered.slice(0, lowered.length - 6).toText(), inline, true)
        if n > 0 { return n }
    }
    if asciiEndsWith(lowered, '-end'.toAscii()) {
        int n = gridAreaLine(s, lowered.slice(0, lowered.length - 4).toText(), inline, false)
        if n > 0 { return n }
    }
    int suffixed = gridNamedLine(s, edgeStart ? `${name}-start` : `${name}-end`, inline)
    if suffixed > 0 { return suffixed }
    return gridNamedLine(s, name, inline)
}

// A copy of `g` with any name resolved to a number against `s`.
GridLine func gridLineResolved(g:GridLine, s:Style, inline:bool, edgeStart:bool) {
    if g.kind != GRIDLINE_NAME { return g }
    GridLine out
    out.kind = GRIDLINE_AUTO
    int n = gridResolveName(s, g.name, inline, edgeStart)
    if n > 0 {
        out.kind = GRIDLINE_NUMBER
        out.n = n
    }
    return out
}

void func resolveGridEdges(startL:GridLine, endL:GridLine, explicitCount:int) {
    gridResolvedAuto = false
    gridResolvedSpan = 1
    gridResolvedStart = 0
    int startN = -1
    int endN = -1
    if startL.kind == GRIDLINE_NUMBER { startN = gridLineIndex(startL.n, explicitCount) }
    if endL.kind == GRIDLINE_NUMBER { endN = gridLineIndex(endL.n, explicitCount) }
    if startN >= 0 && endN >= 0 {
        gridResolvedStart = minInt(startN, endN)
        gridResolvedSpan = maxInt(maxInt(startN, endN) - gridResolvedStart, 1)
        return
    }
    if startN >= 0 {
        gridResolvedStart = startN
        gridResolvedSpan = endL.kind == GRIDLINE_SPAN ? maxInt(endL.n, 1) : 1
        return
    }
    if endN >= 0 {
        int span = startL.kind == GRIDLINE_SPAN ? maxInt(startL.n, 1) : 1
        gridResolvedStart = maxInt(endN - span, 0)
        gridResolvedSpan = span
        return
    }
    // no line named on either edge: the position is for auto-placement
    // to decide, and only the span is known
    gridResolvedAuto = true
    if startL.kind == GRIDLINE_SPAN { gridResolvedSpan = maxInt(startL.n, 1) }
    else if endL.kind == GRIDLINE_SPAN { gridResolvedSpan = maxInt(endL.n, 1) }
}

// Line 1 is the start of track 0. A negative line counts back from the
// end of the explicit grid, so -1 is the line after its last track.
int func gridLineIndex(n:int, explicitCount:int) {
    if n > 0 { return n - 1 }
    return maxInt(explicitCount + 1 + n, 0)
}

// The size of one track, in px, given the space the axis has. An `fr`
// track has no size of its own and is resolved afterwards.
int func trackBaseSize(t:Track, axisSize:int) {
    if t.kind == TRACK_LEN { return maxInt(resolveLen(t.size, axisSize, 0), 0) }
    return 0
}

// The track list an axis uses at index i: the explicit template while
// it lasts, then the auto list repeating, then auto. TRACK_AUTO is zero
// on both sizing functions, so the Track built here is `auto` without
// having to say so.
Track func trackAt(explicit:arr[Track], auto:arr[Track], i:int) {
    if i < explicit.length { return explicit[i] }
    if auto.length > 0 { return auto[(i - explicit.length) % auto.length] }
    Track t
    t.kind = TRACK_AUTO
    t.minKind = TRACK_AUTO
    return t
}

// Whether a track's size depends on what is in it. A track that is a
// length on both sides does not, which is what lets a grid with
// declared tracks skip measuring its items entirely.
bool func trackIsIntrinsic(t:Track) {
    return t.kind != TRACK_LEN || t.minKind != TRACK_LEN
}

// The size a track counts as while the repetitions of an auto-repeat
// are being counted (§7.2.3.2): its maximum where that is a definite
// length, otherwise its minimum. A track that is neither counts as
// nothing, which makes the repeat one copy.
int func trackFixedSize(t:Track, axisSize:int) {
    if t.kind == TRACK_LEN { return maxInt(resolveLen(t.size, axisSize, 0), 0) }
    if t.minKind == TRACK_LEN { return maxInt(resolveLen(t.minSize, axisSize, 0), 0) }
    return 0
}

// How many times an auto-repeat group fits: the largest N with
// F + N*G + (K + N*L - 1)*gap <= S, and never less than one. With no
// definite size to fill -- the block axis of a grid with no height --
// the standard makes it one repetition.
int func gridAutoRepeatCount(list:arr[Track], at:int, len:int, axisSize:int, gap:int) {
    if axisSize < 0 { return 1 }
    int outside = 0
    int others = 0
    for int i = 0, i < list.length, i++ {
        if i >= at && i < at + len { continue }
        others++
        outside = outside + trackFixedSize(list[i], axisSize)
    }
    int group = 0
    for int k = 0, k < len, k++ { group = group + trackFixedSize(list[at + k], axisSize) }
    int per = group + len * gap
    if group <= 0 || per <= 0 { return 1 }
    int room = axisSize - outside - (others - 1) * gap
    return maxInt(Math.floorDiv(room, per), 1)
}

// How many tracks the expanded repeat occupies, which the auto-fit
// collapse needs and a function cannot return beside the list
// (FINDINGS.md, "one value out of a function"). Zero where there is no
// auto-repeat.
int gridRepeatSpan = 0

// The track list with its auto-repeat expanded. A list without one is
// handed straight back, so a page whose grids do not use it allocates
// nothing.
arr[Track] func gridExpandRepeat(list:arr[Track], at:int, len:int, axisSize:int, gap:int) {
    gridRepeatSpan = 0
    if at < 0 || len <= 0 || at + len > list.length { return list }
    int n = gridAutoRepeatCount(list, at, len, axisSize, gap)
    gridRepeatSpan = n * len
    if n == 1 { return list }
    arr[Track] out = []
    for int i = 0, i < at, i++ { out.push(list[i]) }
    for int r = 0, r < n, r++ {
        for int k = 0, k < len, k++ { out.push(list[at + k]) }
    }
    for int i = at + len, i < list.length, i++ { out.push(list[i]) }
    return out
}

// The shared empty answer: almost every grid has no collapsed track, and
// nothing writes to this.
arr[bool] gridNoCollapse = []

bool func gridCollapsedAt(collapsed:arr[bool], i:int) {
    if i < 0 || i >= collapsed.length { return false }
    return collapsed[i]
}

// `auto-fit` collapses every track of its repeat that no item occupies
// (§7.2.3.2). A collapsed track is a 0px track whose gutters go with it.
arr[bool] func gridCollapsedTracks(areas:arr[GridArea], count:int, from:int, span:int,
                                   inline:bool) {
    if span <= 0 || from < 0 { return gridNoCollapse }
    arr[bool] out = []
    for int i = 0, i < count, i++ { out.push(i >= from && i < from + span) }
    for int i = 0, i < areas.length, i++ {
        int at = inline ? areas[i].col : areas[i].row
        int sp = maxInt(inline ? areas[i].colSpan : areas[i].rowSpan, 1)
        for int k = 0, k < sp, k++ {
            int t = at + k
            if t >= 0 && t < count { out[t] = false }
        }
    }
    return out
}

// The tracks a parent grid hands to a subgrid item: the sizes of the
// lines it spans, and the gap between them (CSS Grid 2 §3). A grid that
// is not a subgrid item finds them empty, and every grid clears them
// before laying out its own items, so a subgrid inside a subgrid gets
// its own parent's lines and not its grandparent's.
arr[int] subgridColSizes = []
arr[int] subgridRowSizes = []
int subgridColGap = 0
int subgridRowGap = 0

// A track list of fixed sizes, which is what a subgrid's handed-down
// tracks become: a track that may neither grow nor shrink is exactly a
// line of its parent's.
arr[Track] func gridFixedTracks(sizes:arr[int]) {
    arr[Track] out = []
    for int i = 0, i < sizes.length, i++ {
        Track t
        t.kind = TRACK_LEN
        t.size = lenPx(sizes[i].toFloat())
        t.minKind = TRACK_LEN
        t.minSize = lenPx(sizes[i].toFloat())
        out.push(t)
    }
    return out
}

// The sizes of `span` tracks from `at`, which is what a subgrid item is
// handed.
arr[int] func gridSpannedSizes(sizes:arr[int], at:int, span:int) {
    arr[int] out = []
    for int i = at, i < at + span && i < sizes.length, i++ { out.push(sizes[i]) }
    return out
}

void func layoutGrid(b:Box, cx:int, y:int, cw:int, width:int) {
    Style s = b.style
    // What this box was handed as a subgrid item, taken before anything
    // else can overwrite it.
    arr[int] givenCols = subgridColSizes
    arr[int] givenRows = subgridRowSizes
    int givenColGap = subgridColGap
    int givenRowGap = subgridRowGap
    subgridColSizes = []
    subgridRowSizes = []
    b.x = cx + b.ml
    b.y = y + b.mt
    int innerX = contentX(b)
    int innerY = contentY(b)
    int colGap = s.columnGap
    int rowGap = s.rowGap

    // ---- pass 1: place every item ----------------------------------
    // `grid-template-areas` declares tracks of its own: the strings say
    // how many rows there are and how many cells each has, whether or
    // not a template names their sizes.
    int areaRows = s.gridAreaCols > 0
        ? Math.floorDiv(s.gridAreaNames.length, s.gridAreaCols) : 0
    // `repeat(auto-fill | auto-fit, ...)` repeats as many times as this
    // container has room for, so the template becomes a real track list
    // here rather than in the cascade. A template without one is handed
    // back unchanged and nothing is allocated.
    int innerW = b.w - b.pl - b.pr - b.bl - b.br
    arr[Track] colTracks = gridExpandRepeat(s.gridCols, s.gridColsAutoAt, s.gridColsAutoLen,
                                            innerW, colGap)
    int colRepeatSpan = gridRepeatSpan
    arr[Track] rowTracks = gridExpandRepeat(s.gridRows, s.gridRowsAutoAt, s.gridRowsAutoLen,
                                            -1, rowGap)
    int rowRepeatSpan = gridRepeatSpan
    // A subgrid's tracks are its parent's, not its own (CSS Grid 2 §3):
    // the sizes of the lines it spans were handed down with the gap
    // between them, and they stand in for the template here -- before
    // the items are placed, because how many tracks there are is what
    // the placement wraps at.
    if s.gridColsSubgrid && givenCols.length > 0 {
        colTracks = gridFixedTracks(givenCols)
        colGap = givenColGap
    }
    if s.gridRowsSubgrid && givenRows.length > 0 {
        rowTracks = gridFixedTracks(givenRows)
        rowGap = givenRowGap
    }
    int explicitCols = maxInt(colTracks.length, s.gridAreaCols)
    int explicitRows = maxInt(rowTracks.length, areaRows)
    arr[GridArea] areas = []
    arr[Box] autoItems = []
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        if boxIsOutOfFlow(c) { continue }
        GridArea a
        a.box = c
        a.colSpan = 1
        a.rowSpan = 1
        resolveGridEdges(gridLineResolved(c.style.gridColStart, s, true, true),
                         gridLineResolved(c.style.gridColEnd, s, true, false), explicitCols)
        bool colAuto = gridResolvedAuto
        a.col = gridResolvedStart
        a.colSpan = gridResolvedSpan
        resolveGridEdges(gridLineResolved(c.style.gridRowStart, s, false, true),
                         gridLineResolved(c.style.gridRowEnd, s, false, false), explicitRows)
        bool rowAuto = gridResolvedAuto
        a.row = gridResolvedStart
        a.rowSpan = gridResolvedSpan
        if colAuto { a.col = -1 }
        if rowAuto { a.row = -1 }
        areas.push(a)
    }
    // Auto-placement: the cursor walks the grid in the flow's order and
    // takes the first run of free cells wide enough for the item. An
    // item that named one axis keeps it and only the other is chosen.
    bool columnFlow = s.gridAutoFlowColumn
    // Named for the flow rather than `lineCount`: a local that shares
    // a name with a function anywhere in the program emits invalid IR,
    // and the namespace is global across every imported file
    // (FINDINGS.md, findings 3 and 9).
    int flowLines = columnFlow
        ? maxInt(explicitRows, 1)
        : maxInt(explicitCols, 1)
    // A line named past the explicit grid creates implicit tracks (§8.1),
    // and the flow wraps at the whole grid rather than at its explicit
    // part. Without this a one-column grid holding an item at
    // `grid-column: 2` searched a row one cell wide for a free cell at
    // index 1, and gridRunIsFree calls any run reaching past the row
    // occupied: the search below never ended and the layout never
    // returned.
    for int i = 0, i < areas.length, i++ {
        int alongAt = columnFlow ? areas[i].row : areas[i].col
        int alongBy = maxInt(columnFlow ? areas[i].rowSpan : areas[i].colSpan, 1)
        if alongAt >= 0 { flowLines = maxInt(flowLines, alongAt + alongBy) }
    }
    arr[bool] occupied = []
    int cursor = 0
    for int i = 0, i < areas.length, i++ {
        GridArea a = areas[i]
        if a.col >= 0 && a.row >= 0 {
            gridMarkOccupied(occupied, a, flowLines, columnFlow)
            continue
        }
        // The two axes are not symmetrical here: one runs along the
        // flow and wraps at flowLines, the other is the cross axis and
        // grows without limit. An item that named one of them keeps it
        // and only the other is searched.
        int alongPos = columnFlow ? a.row : a.col
        int crossPos = columnFlow ? a.col : a.row
        int alongSpan = minInt(maxInt(columnFlow ? a.rowSpan : a.colSpan, 1), flowLines)
        int crossSpan = maxInt(columnFlow ? a.colSpan : a.rowSpan, 1)
        if alongPos >= 0 {
            // the position along the flow is fixed: take the first
            // cross line where it is free
            int d = crossPos >= 0 ? crossPos : 0
            while !gridRunIsFree(occupied, flowLines, alongPos, alongSpan, d, crossSpan) { d++ }
            crossPos = d
            // The cursor moves to where this item landed (§8.5, step 4:
            // an item naming a line sets the cursor to it). An item
            // placed automatically after one that named a column goes to
            // the row below rather than back to the cells the named one
            // skipped, which is what Chromium does.
            if !s.gridAutoFlowDense { cursor = maxInt(cursor, crossPos * flowLines + alongPos) }
        } else {
            // walk the flow from the cursor until a free run fits.
            // `dense` starts every item's search over instead, which is
            // what fills a hole an earlier item was too wide for.
            int from = s.gridAutoFlowDense ? 0 : cursor
            int at = maxInt(from, crossPos >= 0 ? crossPos * flowLines : 0)
            while true {
                int cAt = Math.floorDiv(at, flowLines)
                int aAt = at % flowLines
                if aAt + alongSpan > flowLines { at = (cAt + 1) * flowLines  continue }
                if crossPos >= 0 && cAt != crossPos {
                    if cAt > crossPos { break }
                    at = crossPos * flowLines
                    continue
                }
                if gridRunIsFree(occupied, flowLines, aAt, alongSpan, cAt, crossSpan) {
                    alongPos = aAt
                    crossPos = cAt
                    if crossPos < 0 { crossPos = cAt }
                    if !s.gridAutoFlowDense { cursor = at }
                    break
                }
                at++
            }
            if alongPos < 0 { alongPos = 0 }
        }
        if crossPos < 0 { crossPos = 0 }
        if columnFlow { a.row = alongPos  a.col = crossPos }
        else { a.col = alongPos  a.row = crossPos }
        gridMarkOccupied(occupied, a, flowLines, columnFlow)
    }

    // ---- pass 2: size the tracks -----------------------------------
    int colCount = maxInt(explicitCols, 1)
    int rowCount = maxInt(explicitRows, 1)
    for int i = 0, i < areas.length, i++ {
        colCount = maxInt(colCount, areas[i].col + areas[i].colSpan)
        rowCount = maxInt(rowCount, areas[i].row + areas[i].rowSpan)
    }
    // `auto-fit` collapses the tracks of its repeat that hold no item,
    // which can only be known once the items are placed.
    arr[bool] colCollapsed = s.gridColsAutoFit
        ? gridCollapsedTracks(areas, colCount, s.gridColsAutoAt, colRepeatSpan, true)
        : gridNoCollapse
    arr[bool] rowCollapsed = s.gridRowsAutoFit
        ? gridCollapsedTracks(areas, rowCount, s.gridRowsAutoAt, rowRepeatSpan, false)
        : gridNoCollapse
    arr[int] colSizes = gridSizeAxis(b, areas, colTracks, s.gridAutoCols, colCount,
                                     width, colGap, true, colCollapsed)
    // The rows are sized after the columns, because an auto row's
    // height is the height of items laid out at their column widths --
    // and an item has no height until something lays it out, so the
    // ones that decide such a row are measured here, at the column
    // width pass 3 will give them. Without this every automatic row was
    // zero and a grid with no declared rows had no height at all.
    //
    // Only the items an automatic row depends on are measured: a grid
    // whose rows are all declared lays nothing out twice, and neither
    // does an item spanning more than one row, which contributes to no
    // track's size.
    for int i = 0, i < areas.length, i++ {
        GridArea a = areas[i]
        if a.rowSpan != 1 || a.row < 0 || a.row >= rowCount { continue }
        if !trackIsIntrinsic(trackAt(rowTracks, s.gridAutoRows, a.row)) { continue }
        int measureW = gridSpanSize(colSizes, colGap, a.col, a.colSpan, colCollapsed)
        Box c = a.box
        c.forcedWidthPx = lenIsAuto(c.style.width) ? measureW : -1
        layoutBlock(c, 0, 0, measureW, false)
        c.forcedWidthPx = -1
    }
    arr[int] rowSizes = gridSizeAxis(b, areas, rowTracks, s.gridAutoRows, rowCount,
                                     -1, rowGap, false, rowCollapsed)

    // ---- pass 3: place the items in their areas --------------------
    arr[int] colPos = gridTrackPositions(colSizes, colGap, colCollapsed)
    arr[int] rowPos = gridTrackPositions(rowSizes, rowGap, rowCollapsed)
    for int i = 0, i < areas.length, i++ {
        GridArea a = areas[i]
        int ax = innerX + colPos[a.col]
        int ay = innerY + rowPos[a.row]
        int aw = gridSpanSize(colSizes, colGap, a.col, a.colSpan, colCollapsed)
        int ah = gridSpanSize(rowSizes, rowGap, a.row, a.rowSpan, rowCollapsed)
        Box c = a.box
        c.forcedWidthPx = lenIsAuto(c.style.width) ? aw : -1
        // An item that is itself a subgrid takes the lines it spans
        // here, where they are known. The two assignments cost a page
        // without a subgrid on it nothing but the flags being false.
        if c.style.gridColsSubgrid {
            subgridColSizes = gridSpannedSizes(colSizes, a.col, a.colSpan)
            subgridColGap = colGap
        }
        if c.style.gridRowsSubgrid {
            subgridRowSizes = gridSpannedSizes(rowSizes, a.row, a.rowSpan)
            subgridRowGap = rowGap
        }
        layoutBlock(c, ax, ay, aw, false)
        subgridColSizes = []
        subgridRowSizes = []
        if lenIsAuto(c.style.height) && ah > c.h { c.h = ah }
        c.forcedWidthPx = -1
    }

    int totalH = 0
    for int i = 0, i < rowSizes.length, i++ {
        totalH = totalH + rowSizes[i] + (i > 0 ? rowGap : 0)
    }
    int gridEdges = b.pt + b.pb + b.bt + b.bb
    if lenIsAuto(s.height) { b.h = totalH + gridEdges }
    b.w = width + b.pl + b.pr + b.bl + b.br
    applyContainerAspect(b)
    if b.baseline == 0 { b.baseline = b.h }
}

// Whether the rectangle of cells an item would take is entirely free.
bool func gridRunIsFree(occupied:arr[bool], flowLines:int, along:int, alongSpan:int,
                        cross:int, crossSpan:int) {
    if along + alongSpan > flowLines { return false }
    for int d = 0, d < crossSpan, d++ {
        for int k = 0, k < alongSpan, k++ {
            if gridOccupiedAt(occupied, (cross + d) * flowLines + along + k) { return false }
        }
    }
    return true
}

bool func gridOccupiedAt(occupied:arr[bool], at:int) {
    if at < 0 || at >= occupied.length { return false }
    return occupied[at]
}

void func gridMarkOccupied(occupied:arr[bool], a:GridArea, flowLines:int, columnFlow:bool) {
    int along = columnFlow ? a.row : a.col
    int cross = columnFlow ? a.col : a.row
    int alongSpan = columnFlow ? a.rowSpan : a.colSpan
    int crossSpan = columnFlow ? a.colSpan : a.rowSpan
    for int d = 0, d < crossSpan, d++ {
        for int k = 0, k < alongSpan, k++ {
            int at = (cross + d) * flowLines + along + k
            if at < 0 { continue }
            while occupied.length <= at { occupied.push(false) }
            occupied[at] = true
        }
    }
}

// The start offset of each track, from the content edge.
arr[int] func gridTrackPositions(sizes:arr[int], gap:int, collapsed:arr[bool]) {
    arr[int] pos = []
    int at = 0
    for int i = 0, i < sizes.length, i++ {
        pos.push(at)
        // A collapsed track takes no space and neither does the gutter
        // after it, so a run of them plus their gutters comes to one
        // gutter -- measured against Chromium 141, which puts the item
        // after two collapsed tracks one gap along, not three.
        at = at + sizes[i] + (gridCollapsedAt(collapsed, i) ? 0 : gap)
    }
    pos.push(at)
    return pos
}

// The size an item spanning `span` tracks from `at` occupies, gaps
// between them included.
int func gridSpanSize(sizes:arr[int], gap:int, at:int, span:int, collapsed:arr[bool]) {
    int total = 0
    for int i = at, i < at + span && i < sizes.length, i++ {
        total = total + sizes[i]
                + (i > at && !gridCollapsedAt(collapsed, i - 1) ? gap : 0)
    }
    return total
}

// One axis of track sizing. `axisSize` is the space the axis has, or -1
// when it has none fixed -- which is the block axis of a grid whose
// height is automatic, where `fr` has nothing to share and an auto
// track is as big as its content.
// Sizing one axis (Grid 1 §12). Every track has a minimum and a
// maximum sizing function; the minimum gives the base size it may not
// go below, the maximum the growth limit it may not pass. Free space is
// then handed out three times over: to grow the tracks towards their
// limits in equal shares, each freezing as it arrives (§12.5); to the
// `fr` tracks, which take what the others left (§12.7); and, where no
// `fr` track took it, to stretch the tracks whose maximum is `auto`
// (§12.8). `justify-content` does not position tracks here, so a
// `normal` that stretches and a `start` that does not cannot be told
// apart yet -- todo.md carries it.
arr[int] func gridSizeAxis(b:Box, areas:arr[GridArea], explicit:arr[Track],
                           auto:arr[Track], count:int, axisSize:int,
                           gap:int, inline:bool, collapsed:arr[bool]) {
    int pct = axisSize < 0 ? 0 : axisSize
    // What each track has to hold: the largest contribution of the
    // single-span items in it. An item spanning several tracks
    // contributes to none of them, which is the standard's first pass
    // and keeps this from needing a second. Nothing is measured at all
    // unless some track's size depends on it.
    arr[int] minC = []
    arr[int] maxC = []
    bool anyIntrinsic = false
    for int i = 0, i < count, i++ {
        minC.push(0)
        maxC.push(0)
        if trackIsIntrinsic(trackAt(explicit, auto, i)) { anyIntrinsic = true }
    }
    if anyIntrinsic {
        for int i = 0, i < areas.length, i++ {
            GridArea a = areas[i]
            int at = inline ? a.col : a.row
            int span = inline ? a.colSpan : a.rowSpan
            if span != 1 || at < 0 || at >= count { continue }
            int mn = 0
            int mx = 0
            if inline {
                computeIntrinsic(a.box)
                mn = a.box.minContent
                mx = a.box.maxContent
            } else {
                // In the block axis an item has one contribution: the
                // height it was laid out to at its column width.
                mn = a.box.h + a.box.mt + a.box.mb
                mx = mn
            }
            if mn > minC[at] { minC[at] = mn }
            if mx > maxC[at] { maxC[at] = mx }
        }
    }

    arr[int] sizes = []
    arr[int] limits = []
    arr[float] frs = []
    arr[bool] stretchy = []
    float totalFr = 0.0
    for int i = 0, i < count, i++ {
        Track t = trackAt(explicit, auto, i)
        int base = 0
        if t.minKind == TRACK_LEN { base = maxInt(resolveLen(t.minSize, pct, 0), 0) }
        else if t.minKind == TRACK_MAX_CONTENT { base = maxC[i] }
        else { base = minC[i] }
        int limit = base
        // Whether the maximum is a length this axis can resolve. A
        // percentage against an indefinite axis is not one: it behaves
        // as `auto`, so it must not be taken for a definite limit below.
        bool definiteLimit = false
        if t.kind == TRACK_LEN {
            limit = maxInt(resolveLen(t.size, pct, 0), 0)
            definiteLimit = axisSize >= 0 || t.size.kind == LEN_PX
        } else if t.kind == TRACK_MIN_CONTENT {
            limit = minC[i]
        } else if t.kind == TRACK_MAX_CONTENT {
            limit = maxC[i]
        } else if t.kind == TRACK_FIT_CONTENT {
            // The max-content size, clamped to the argument but never
            // below what the minimum already demands.
            limit = minInt(maxC[i], maxInt(base, maxInt(resolveLen(t.size, pct, 0), 0)))
        } else if t.kind == TRACK_FR {
            limit = base
        } else {
            limit = maxC[i]
        }
        if limit < base { limit = base }
        float fr = 0.0
        if t.kind == TRACK_FR && axisSize >= 0 && !gridCollapsedAt(collapsed, i) {
            fr = t.fr
            totalFr = totalFr + t.fr
        }
        int size = base
        // §12.5: where the roomLeft space is indefinite, a track whose
        // maximum is a definite length takes that length. It is why a
        // `minmax(80px, 120px)` row is 120 tall in a container with no
        // height of its own.
        if axisSize < 0 && definiteLimit && limit > size { size = limit }
        // A collapsed auto-fit track is a 0px track: no base, no limit,
        // no share of anything.
        bool gone = gridCollapsedAt(collapsed, i)
        if gone {
            size = 0
            limit = 0
            fr = 0.0
        }
        sizes.push(size)
        limits.push(limit)
        frs.push(fr)
        stretchy.push(t.kind == TRACK_AUTO && !gone)
    }

    // A collapsed track's gutter goes with it, so the gaps are counted
    // one by one rather than as (count - 1) of them.
    int gaps = 0
    for int i = 0, i + 1 < count, i++ {
        if !gridCollapsedAt(collapsed, i) { gaps = gaps + gap }
    }
    // §12.5 maximize tracks: equal shares, each track freezing as it
    // reaches its growth limit and the rest going to those still growable.
    if axisSize >= 0 {
        int used = 0
        for int i = 0, i < count, i++ { used = used + sizes[i] }
        int roomLeft = axisSize - used - gaps
        while roomLeft > 0 {
            int growable = 0
            for int i = 0, i < count, i++ {
                if frs[i] <= 0.0 && sizes[i] < limits[i] { growable++ }
            }
            if growable == 0 { break }
            int share = maxInt(Math.floorDiv(roomLeft, growable), 1)
            bool moved = false
            for int i = 0, i < count, i++ {
                if roomLeft <= 0 { break }
                if frs[i] > 0.0 || sizes[i] >= limits[i] { continue }
                int add = minInt(minInt(share, limits[i] - sizes[i]), roomLeft)
                sizes[i] = sizes[i] + add
                roomLeft = roomLeft - add
                if add > 0 { moved = true }
            }
            if !moved { break }
        }
    }
    // §12.7 expand flexible tracks: an fr track takes its share of what
    // the others left, and never less than its own base size.
    if axisSize >= 0 && totalFr > 0.0 {
        int fixed = 0
        for int i = 0, i < count, i++ { if frs[i] <= 0.0 { fixed = fixed + sizes[i] } }
        int spare = maxInt(axisSize - fixed - gaps, 0)
        int handed = 0
        int lastFr = -1
        for int i = 0, i < count, i++ { if frs[i] > 0.0 { lastFr = i } }
        for int i = 0, i < count, i++ {
            if frs[i] <= 0.0 { continue }
            // the last fr track takes the remainder, so the tracks add
            // up to the space exactly rather than to a pixel less
            int share = i == lastFr ? spare - handed
                      : roundPx(spare.toFloat() * frs[i] / totalFr)
            if share < sizes[i] { share = sizes[i] }
            sizes[i] = share
            handed = handed + share
        }
    }
    // §12.8 stretch auto tracks: anything still spare is shared equally
    // by the tracks whose maximum is `auto`. An fr track has already
    // taken everything, so this only runs where there is none.
    if axisSize >= 0 && totalFr <= 0.0 {
        int used = 0
        for int i = 0, i < count, i++ { used = used + sizes[i] }
        int spare = axisSize - used - gaps
        if spare > 0 {
            int n = 0
            int last = -1
            for int i = 0, i < count, i++ { if stretchy[i] { n++  last = i } }
            if n > 0 {
                int handed = 0
                int each = Math.floorDiv(spare, n)
                for int i = 0, i < count, i++ {
                    if !stretchy[i] { continue }
                    int add = i == last ? spare - handed : each
                    sizes[i] = sizes[i] + add
                    handed = handed + add
                }
            }
        }
    }
    return sizes
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
        applyContainerAspect(b)
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
    // How much main axis each line actually uses, which is what a
    // reverse direction measures its positions back from where the
    // container's own main size is indefinite.
    arr[int] lineUsedMain = []
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
            // §9.7: hand out the space to shrink by in proportion, clamp
            // every item to its own minimum, and repeat with the clamped
            // ones frozen -- which is what makes an item that cannot
            // shrink any further push the shrinking onto its neighbours
            // rather than swallowing it.
            arr[bool] frozen = []
            arr[int] minMain = []
            for int i = first, i <= last, i++ {
                frozen.push(false)
                minMain.push(flexMinMainSize(items[i], row, mainAvail))
            }
            int owed = 0 - spare
            int rounds = 0
            while owed > 0 && rounds <= n {
                rounds++
                float liveShrink = 0.0
                for int i = 0, i < n, i++ {
                    if !frozen[i] { liveShrink = liveShrink + items[first + i].style.flexShrink }
                }
                if liveShrink <= 0.0 { break }
                float acc = 0.0
                int taken = 0
                int over = 0
                int lastLive = -1
                for int i = 0, i < n, i++ {
                    if !frozen[i] { lastLive = i }
                }
                for int i = 0, i < n, i++ {
                    if frozen[i] { continue }
                    acc = acc + items[first + i].style.flexShrink / liveShrink
                    int upto = i == lastLive ? owed : roundPx(owed.toFloat() * acc)
                    int cut = upto - taken
                    taken = taken + cut
                    int want = mainSize[first + i] - cut
                    if want < minMain[i] {
                        over = over + (minMain[i] - want)
                        want = minMain[i]
                        frozen[i] = true
                    }
                    mainSize[first + i] = want
                }
                owed = over
            }
            spare = 0
        }
        if spare < 0 { spare = 0 }
        int usedMain = mainGap * (n - 1)
        for int i = first, i <= last, i++ {
            Box it = items[i]
            usedMain = usedMain + mainSize[i] + (row ? it.ml + it.mr : it.mt + it.mb)
        }
        lineUsedMain.push(usedMain)
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
        // A reverse direction runs the main axis the other way: the
        // items keep their order and the whole of it is measured from
        // the far edge, so the first item is the rightmost (or the
        // lowest). Laying them out forwards and mirroring each position
        // is what puts `justify-content: flex-start` against that far
        // edge, which reversing the sequence alone does not.
        bool reversed = flexIsReverse(s)
        int mirrorBase = mainAvail >= 0 ? mainAvail : lineUsedMain[li]
        for int k = 0, k < n, k++ {
            int idx = first + k
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
            if reversed {
                int outerMain = size + (row ? item.ml + item.mr : item.mt + item.mb)
                mainPos = mirrorBase - mainPos - outerMain
            }
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
    applyContainerAspect(b)
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

// One of the four boxes a shape may resolve against, written to
// globals because a function answers with one value (FINDINGS.md). Both
// `clip-path` and `shape-outside` ask for it, and they are in different
// files, so it lives with the Box it is about.
int boxRefX = 0
int boxRefY = 0
int boxRefW = 0
int boxRefH = 0

void func boxReferenceBox(b:Box, which:int) {
    if which == GEOBOX_MARGIN {
        boxRefX = b.x - b.ml
        boxRefY = b.y - b.mt
        boxRefW = b.w + b.ml + b.mr
        boxRefH = b.h + b.mt + b.mb
        return
    }
    boxRefX = b.x
    boxRefY = b.y
    boxRefW = b.w
    boxRefH = b.h
    if which == GEOBOX_BORDER { return }
    boxRefX = boxRefX + b.bl
    boxRefY = boxRefY + b.bt
    boxRefW = boxRefW - b.bl - b.br
    boxRefH = boxRefH - b.bt - b.bb
    if which == GEOBOX_PADDING { return }
    boxRefX = boxRefX + b.pl
    boxRefY = boxRefY + b.pt
    boxRefW = boxRefW - b.pl - b.pr
    boxRefH = boxRefH - b.pt - b.pb
}

struct FloatRect {
    left:int
    top:int
    right:int
    bottom:int
    side:int
    // CSS Shapes 1: the float's exclusion follows this shape rather
    // than the rectangle above, which stays the margin box the float
    // itself occupies and the edge the shape is clamped to.
    hasShape:bool
    shape:ShapeGeom
}

arr[FloatRect] bfcFloats = []

void func resetFloats() {
    bfcFloats = []
}

// The left edge available to content in the band [top, bottom).
// How far in from the left a band [top, bottom) is pushed. A shaped
// float is asked for the furthest right its shape reaches anywhere in
// the band -- a line box is a rectangle, so it must clear the widest
// part of what it shares a band with -- and that answer is clamped to
// the float's own margin box, which is as far as an exclusion goes.
int func floatLeftEdge(cbLeft:int, top:int, bottom:int) {
    int edge = cbLeft
    for int i = 0, i < bfcFloats.length, i++ {
        FloatRect f = bfcFloats[i]
        if f.side != FLOAT_LEFT { continue }
        if f.hasShape {
            // The exclusion cannot leave the float's own margin box:
            // there is no float above or below it to exclude anything.
            shapeRightEdgeOver(f.shape, maxInt(top, f.top), minInt(bottom, f.bottom))
            if !shapeEdgeFound { continue }
            int e = minInt(shapeEdgeValue, f.right)
            if e > edge { edge = e }
            continue
        }
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
        if f.hasShape {
            shapeLeftEdgeOver(f.shape, maxInt(top, f.top), minInt(bottom, f.bottom))
            if !shapeEdgeFound { continue }
            int e = maxInt(shapeEdgeValue, f.left)
            if e < edge { edge = e }
            continue
        }
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
            // The shape is resolved now, against the box this float has
            // just been given. A document with no shape in it never
            // reaches this and never grows a FloatRect that carries one.
            if cascadeSawShape && b.style.shapeOutside.kind != CLIPSHAPE_NONE {
                boxReferenceBox(b, b.style.shapeOutside.geoBox)
                rect.shape = resolveShape(b.style.shapeOutside, boxRefX, boxRefY,
                                          boxRefW, boxRefH, b.style.shapeMargin)
                rect.hasShape = true
            }
            bfcFloats.push(rect)
            return
        }
        int nb = nextFloatBottom(y)
        if nb <= y { nb = y + 1 }
        y = nb
    }
}

// A drop cap floats like anything else, but only the bottom `sink`
// lines of it exclude text: the rest of it rises above the first line,
// into the space `layoutInlineContent` has already pushed the text
// down by. So it is placed where the text starts, lifted back by that
// difference, and the rectangle it excludes with is cut to the sink.
void func placeDropCap(b:Box) {
    placeFloat(b, ifcCbLeft, ifcCbRight, ifcY)
    if bfcFloats.length == 0 { return }
    FloatRect r = bfcFloats[bfcFloats.length - 1]
    int lh = ifcBox == null ? 0 : lineHeightOf(ifcBox.style)
    int sinkH = initialLetterSink(b.style) * lh
    int above = (r.bottom - r.top) - sinkH
    if above <= 0 { return }
    shiftBoxTree(b, 0, -above)
    r.bottom = r.top + sinkH
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
        // With both insets on an axis `auto` the box sits where it
        // would have been in flow, which the flow noted on its way past
        // (CSS2 §10.3.7). A fixed box has no such place: it resolves
        // against the viewport and stays at its corner.
        int wantX = b.x
        int wantY = b.y
        if b.style.position != POS_FIXED && staticPosX[`${b.id}`] != null {
            wantX = staticPosX[`${b.id}`] + b.ml
            wantY = staticPosY[`${b.id}`] + b.mt
        }
        // An `anchor-size()` inset is a declared inset: it is the length
        // the function resolved to, and it takes the same precedence a
        // written-out one would, the start side before the end side.
        int asL = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_LEFT) : -1
        int asR = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_RIGHT) : -1
        int asT = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_TOP) : -1
        int asB = anyAnchorSize ? anchorSizeFor(b, ANCHOR_SIZE_BOTTOM) : -1
        if asL >= 0 {
            wantX = useX + asL + b.ml
        } else if !lenIsAuto(s.left) {
            wantX = useX + resolveLen(s.left, useW, 0) + b.ml
        } else if asR >= 0 {
            wantX = useX + useW - asR - w + b.ml
        } else if !lenIsAuto(s.right) {
            wantX = useX + useW - resolveLen(s.right, useW, 0) - w + b.ml
        }
        if asT >= 0 {
            wantY = useY + asT + b.mt
        } else if !lenIsAuto(s.top) {
            wantY = useY + resolveLen(s.top, useH, 0) + b.mt
        } else if asB >= 0 {
            wantY = useY + useH - asB - h + b.mt
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

// ---- CSS Anchor Positioning 1 ---------------------------------------------
//
// `position-anchor` names another element's box to resolve against, and
// `position-area` says which of nine regions around that box the
// positioned one goes in. Each axis is one of three bands -- before the
// anchor, its own extent, or after it -- or a span of all three.
//
// This runs after the ordinary positioning pass rather than inside it,
// because an anchor may itself be absolutely positioned and so has no
// final rectangle until that pass is done. An anchor that is itself
// anchored would need a second round; the standard forbids the cycle
// that would make one necessary.
// The walk keeps, for each anchor name, the rectangle of the last
// element carrying it that it has passed, and resolves each anchored
// box against that as it reaches the box. So an anchor is a candidate
// only when it comes before the box in tree order, and of the ones
// that do, the last wins -- which is what Chromium does and what one
// rectangle per name for the whole document cannot express, since the
// document's last writer is the only answer such a registry has.
map[int] anchorLiveX = {}
map[int] anchorLiveY = {}
map[int] anchorLiveW = {}
map[int] anchorLiveH = {}
// The answer, per box, so the placement pass does not resolve again.
// The rectangle each `anchor()` inset resolved to, keyed by the box's
// id and which inset it is. A named `anchor()` looks its own name up
// rather than borrowing the one `position-anchor` found, which is what
// lets one box anchor its left edge to one element and its top to
// another. Grown only by a page that says the function.
map[int] anchorInsetX = {}
map[int] anchorInsetY = {}
map[int] anchorInsetW = {}
map[int] anchorInsetH = {}

map[int] anchorBoxX = {}
map[int] anchorBoxY = {}
map[int] anchorBoxW = {}
map[int] anchorBoxH = {}
bool anchorBoxFound = false

// `anchor-scope` makes a name mean different anchors in different parts
// of the document, so the live rectangles are keyed by the scope a name
// is in rather than by the name alone. The scope of a name at a point in
// the walk is the nearest enclosing element that scopes it, itself
// included, or nothing; an anchor and a box see each other only when
// they agree on that element. That is a boundary in *both* directions:
// a box inside a scope of `--a` is cut off from every `--a` outside it
// as well, even when the scope holds none of its own (todo.md records
// the measurement). A page that scopes nothing keys by the bare name and
// never touches the stack below.
map[int] scopeNameId = {}       // name -> the element scoping it
map[int] scopeNameDepth = {}    // and how deep that element is
// `all` is held under a key no dashed identifier can spell, so one
// lookup pair serves both spellings of the property.
const text SCOPE_ALL_KEY = '*'
// The walk's undo log: what each push overwrote. A push returns how
// many entries it added, and leaving the element pops exactly that many.
arr[text] scopeSavedName = []
arr[int] scopeSavedId = []
arr[int] scopeSavedDepth = []

int func anchorScopeDepthOf(name:text) {
    if scopeNameDepth[name] == null { return -1 }
    return scopeNameDepth[name]
}

// The deeper of the two candidates wins, which is what makes an inner
// `anchor-scope: --a` override an outer `anchor-scope: all` and the
// other way round.
text func anchorScopeKey(name:text) {
    if !anyAnchorScope { return name }
    int byName = anchorScopeDepthOf(name)
    int byAll = anchorScopeDepthOf(SCOPE_ALL_KEY)
    if byName < 0 && byAll < 0 { return `0 ${name}` }
    if byName > byAll { return `${scopeNameId[name]} ${name}` }
    return `${scopeNameId[SCOPE_ALL_KEY]} ${name}`
}

void func anchorScopeEnter(name:text, id:int, depth:int) {
    scopeSavedName.push(name)
    scopeSavedId.push(scopeNameId[name] == null ? 0 : scopeNameId[name])
    scopeSavedDepth.push(anchorScopeDepthOf(name))
    scopeNameId[name] = id
    scopeNameDepth[name] = depth
}

// How many names this element scopes, having entered each of them.
int func anchorScopePush(sc:text, id:int, depth:int) {
    if sc == 'all' {
        anchorScopeEnter(SCOPE_ALL_KEY, id, depth)
        return 1
    }
    int n = 0
    arr[ascii] parts = asciiSplitChar(sc.toAscii(), CH_COMMA)
    for int i = 0, i < parts.length, i++ {
        ascii nm = asciiTrim(parts[i])
        if nm == '' { continue }
        anchorScopeEnter(nm.toText(), id, depth)
        n = n + 1
    }
    return n
}

void func anchorScopePop(n:int) {
    for int i = 0, i < n, i++ {
        text nm = scopeSavedName.pop()
        scopeNameId[nm] = scopeSavedId.pop()
        scopeNameDepth[nm] = scopeSavedDepth.pop()
    }
}

void func collectAnchors(b:Box, depth:int) {
    if b == null { return }
    int pushed = 0
    if b.style != null && b.style.anchorInfo > 0 {
        AnchorInfo ai = anchorInfoOf(b.style.anchorInfo)
        // The scope covers the element declaring it, so it goes up
        // before this element's own name and anchor are looked at.
        if anyAnchorScope && ai.scope != '' {
            pushed = anchorScopePush(ai.scope, b.id, depth)
        }
        // Resolving before declaring is what stops an element that both
        // names an anchor and is one from anchoring to itself.
        if ai.anchor != '' && boxIsOutOfFlow(b) {
            text key = anchorScopeKey(ai.anchor)
            if anchorLiveW[key] != null {
                anchorBoxX[`${b.id}`] = anchorLiveX[key]
                anchorBoxY[`${b.id}`] = anchorLiveY[key]
                anchorBoxW[`${b.id}`] = anchorLiveW[key]
                anchorBoxH[`${b.id}`] = anchorLiveH[key]
                anchorBoxFound = true
            }
        }
        // Each `anchor()` inset resolves its own name, against the
        // anchors this walk has already passed -- the same rule
        // `position-anchor` follows, and for the same reason.
        if anyAnchorInset && boxIsOutOfFlow(b) {
            for int i = 0, i < 4, i++ {
                if ai.insetPcts[i] < 0 { continue }
                // A box with an inset to resolve is a box to place,
                // whether or not its anchor was found: a fallback is
                // still an answer.
                anchorBoxFound = true
                text nm = ai.insetNames[i] != '' ? ai.insetNames[i] : ai.anchor
                if nm == '' { continue }
                text ikey = anchorScopeKey(nm)
                if anchorLiveW[ikey] == null { continue }
                anchorInsetX[`${b.id}:${i}`] = anchorLiveX[ikey]
                anchorInsetY[`${b.id}:${i}`] = anchorLiveY[ikey]
                anchorInsetW[`${b.id}:${i}`] = anchorLiveW[ikey]
                anchorInsetH[`${b.id}:${i}`] = anchorLiveH[ikey]
            }
        }
        // What each `anchor-size()` resolves to, for the layout after
        // this one. Recorded against the anchors this walk has already
        // passed, the same rule `position-anchor` and `anchor()` follow.
        if anyAnchorSize && boxIsOutOfFlow(b) && b.node != null && b.node.id > 0 {
            for int i = 0, i < ANCHOR_SIZE_SLOTS, i++ {
                if ai.sizeDims[i] < 0 { continue }
                // No fallback and no anchor is ZERO rather than no
                // effect, which is where this differs from `anchor()`
                // in an inset (todo.md records the measurement).
                int v = ai.sizeFallbacks[i] != ANCHOR_NO_FALLBACK ? ai.sizeFallbacks[i] : 0
                text snm = ai.sizeNames[i] != '' ? ai.sizeNames[i] : ai.anchor
                if snm != '' {
                    text skey = anchorScopeKey(snm)
                    if anchorLiveW[skey] != null {
                        v = ai.sizeDims[i] == ANCHOR_DIM_WIDTH
                            ? anchorLiveW[skey] : anchorLiveH[skey]
                    }
                }
                text pkey = `${b.node.id}:${i}`
                if anchorSizePx[pkey] == null || anchorSizePx[pkey] != v {
                    anchorSizePx[pkey] = v
                    anchorSizeChanged = true
                }
            }
        }
        if ai.name != '' {
            text key = anchorScopeKey(ai.name)
            anchorLiveX[key] = b.x
            anchorLiveY[key] = b.y
            anchorLiveW[key] = b.w
            anchorLiveH[key] = b.h
        }
    }
    for int i = 0, i < b.children.length, i++ { collectAnchors(b.children[i], depth + 1) }
    if pushed > 0 { anchorScopePop(pushed) }
}

// Where a box of `size` goes in one axis, given the anchor's two edges
// on it. A band before the anchor end-aligns the box, so its far edge
// meets the anchor's near one; a band after start-aligns it; and the
// anchor's own band centres it. `span-all` centres on the anchor as
// well, rather than on the region it spans -- which is what Chromium
// does and what a region-first reading of the standard gets wrong
// (todo.md records the measurement).
int func anchorBandPos(band:int, a0:int, a1:int, size:int, fallback:int) {
    if band == PAREA_BEFORE { return a0 - size }
    if band == PAREA_AFTER { return a1 }
    if band == PAREA_CENTER || band == PAREA_SPAN {
        return a0 + Math.floorDiv(a1 - a0 - size, 2)
    }
    return fallback
}

// `position-try-fallbacks`: a candidate area, either named outright or
// reached by flipping the one in force. A flip swaps a band for the one
// opposite it rather than naming a region of its own, so `flip-block`
// turns a `top` into a `bottom` whatever `top` was written as.
int func flipBand(band:int) {
    if band == PAREA_BEFORE { return PAREA_AFTER }
    if band == PAREA_AFTER { return PAREA_BEFORE }
    return band
}

int func tryCandidateArea(current:int, spec:ascii) {
    int blockBand = Math.floorDiv(current, PAREA_AXIS)
    int inlineBand = current % PAREA_AXIS
    if spec == 'flip-block' { return flipBand(blockBand) * PAREA_AXIS + inlineBand }
    if spec == 'flip-inline' { return blockBand * PAREA_AXIS + flipBand(inlineBand) }
    if spec == 'flip-start' { return inlineBand * PAREA_AXIS + blockBand }
    return positionAreaValue(spec)
}

// Whether a box at (x, y) would fall outside the containing block it
// resolves against, which is the whole of the test Chromium applies
// before moving on to the next candidate.
bool func anchorOverflows(x:int, y:int, w:int, h:int,
                          cbX:int, cbY:int, cbW:int, cbH:int) {
    return x < cbX || y < cbY || x + w > cbX + cbW || y + h > cbY + cbH
}

// Where one area puts the box. Two values out of a function need
// globals (FINDINGS.md, "one value out of a function").
int anchorTryX = 0
int anchorTryY = 0

void func anchorPlaceAt(area:int, ax:int, ay:int, aw:int, ah:int, b:Box) {
    anchorTryX = anchorBandPos(area % PAREA_AXIS, ax, ax + aw, b.w, b.x)
    anchorTryY = anchorBandPos(Math.floorDiv(area, PAREA_AXIS), ay, ay + ah, b.h, b.y)
}

// How much room one band of one axis offers, which is what
// `position-try-order` sorts the candidates by: the space between the
// containing block's edge and the anchor's for a band beyond it, the
// anchor's own extent for its band, and the whole block for a span.
int func anchorBandRoom(band:int, a0:int, a1:int, cb0:int, cbSize:int) {
    if band == PAREA_BEFORE { return a0 - cb0 }
    if band == PAREA_AFTER { return cb0 + cbSize - a1 }
    if band == PAREA_CENTER { return a1 - a0 }
    return cbSize
}

int func anchorAreaRoom(area:int, order:int, ax:int, ay:int, aw:int, ah:int,
                        cbX:int, cbY:int, cbW:int, cbH:int) {
    if order == TRYORDER_MOST_BLOCK {
        return anchorBandRoom(Math.floorDiv(area, PAREA_AXIS), ay, ay + ah, cbY, cbH)
    }
    return anchorBandRoom(area % PAREA_AXIS, ax, ax + aw, cbX, cbW)
}

// Where one `anchor()` inset puts the box, as the x or y of its border
// box -- or the fallback measured from the containing block where the
// anchor was not found, or where the box already is where there is
// neither. `i` is which inset, in the order left, right, top, bottom,
// and the side keyword has already become a position along the anchor
// (src/css/style.f).
//
// It is the box's *margin* edge that lands on the anchor, which is
// measured and is what an ordinary inset does too, so each side takes
// its own margin back out to give the border box.
int func anchorInsetEdge(b:Box, ai:AnchorInfo, i:int, cbX:int, cbY:int,
                         cbW:int, cbH:int, have:int) {
    bool vertical = i >= ANCHOR_INSET_TOP
    int size = vertical ? b.h : b.w
    int near = vertical ? b.mt : b.ml
    int far = vertical ? b.mb : b.mr
    text k = `${b.id}:${i}`
    if anchorInsetW[k] != null {
        int at = vertical ? anchorInsetY[k] : anchorInsetX[k]
        int span = vertical ? anchorInsetH[k] : anchorInsetW[k]
        int edge = at + Math.floorDiv(span * ai.insetPcts[i], 10000)
        // A near inset puts the box's near edge there and a far inset
        // its far edge, which is what makes `right: anchor(--a left)`
        // hang the box off the anchor's left rather than start there.
        if i == ANCHOR_INSET_RIGHT || i == ANCHOR_INSET_BOTTOM {
            return edge - size - far
        }
        return edge + near
    }
    int fb = ai.insetFallbacks[i]
    if fb == ANCHOR_NO_FALLBACK { return have }
    if i == ANCHOR_INSET_RIGHT { return cbX + cbW - fb - size - far }
    if i == ANCHOR_INSET_BOTTOM { return cbY + cbH - fb - size - far }
    return (vertical ? cbY : cbX) + fb + near
}

void func placeAnchored(b:Box, cbX:int, cbY:int, cbW:int, cbH:int) {
    if b == null { return }
    // `anchor()` in an inset, which is resolved here rather than where
    // the insets usually are because an anchor's rectangle is not known
    // until the whole tree has been laid out.
    if anyAnchorInset && b.style != null && b.style.anchorInfo > 0 && boxIsOutOfFlow(b) {
        AnchorInfo ai = anchorInfoOf(b.style.anchorInfo)
        int wantX = b.x
        int wantY = b.y
        // A near inset wins over the far one on its axis, as it does
        // for any absolutely positioned box.
        if ai.insetPcts[ANCHOR_INSET_LEFT] >= 0 {
            wantX = anchorInsetEdge(b, ai, ANCHOR_INSET_LEFT, cbX, cbY, cbW, cbH, b.x)
        } else if ai.insetPcts[ANCHOR_INSET_RIGHT] >= 0 {
            wantX = anchorInsetEdge(b, ai, ANCHOR_INSET_RIGHT, cbX, cbY, cbW, cbH, b.x)
        }
        if ai.insetPcts[ANCHOR_INSET_TOP] >= 0 {
            wantY = anchorInsetEdge(b, ai, ANCHOR_INSET_TOP, cbX, cbY, cbW, cbH, b.y)
        } else if ai.insetPcts[ANCHOR_INSET_BOTTOM] >= 0 {
            wantY = anchorInsetEdge(b, ai, ANCHOR_INSET_BOTTOM, cbX, cbY, cbW, cbH, b.y)
        }
        if wantX != b.x || wantY != b.y { shiftBoxTree(b, wantX - b.x, wantY - b.y) }
    }
    if b.style != null && b.style.anchorInfo > 0 && boxIsOutOfFlow(b) {
        AnchorInfo ai = anchorInfoOf(b.style.anchorInfo)
        if ai.area != PAREA_NONE && anchorBoxW[`${b.id}`] != null {
            int ax = anchorBoxX[`${b.id}`]
            int ay = anchorBoxY[`${b.id}`]
            int aw = anchorBoxW[`${b.id}`]
            int ah = anchorBoxH[`${b.id}`]
            anchorPlaceAt(ai.area, ax, ay, aw, ah, b)
            int wantX = anchorTryX
            int wantY = anchorTryY
            // The candidates: the area the element asked for, then the
            // fallbacks in written order.
            arr[int] areas = []
            if ai.fallbacks != '' || ai.tryOrder != TRYORDER_NORMAL {
                areas.push(ai.area)
                arr[ascii] cands = asciiSplitChar(ai.fallbacks.toAscii(), CH_COMMA)
                for int i = 0, i < cands.length, i++ {
                    int area = tryCandidateArea(ai.area, asciiLower(asciiTrim(cands[i])))
                    if area != PAREA_NONE { areas.push(area) }
                }
            }
            // `position-try-order` sorts them by the room each region
            // offers, most first, and that sort applies whether or not
            // the original position overflows -- it is a choice among
            // the candidates, not a repair of a bad one. A selection
            // sort keeps it stable, so equal rooms hold their order.
            if ai.tryOrder != TRYORDER_NORMAL && areas.length > 1 {
                for int i = 0, i < areas.length - 1, i++ {
                    int best = i
                    int bestRoom = anchorAreaRoom(areas[i], ai.tryOrder, ax, ay, aw, ah,
                                                  cbX, cbY, cbW, cbH)
                    for int j = i + 1, j < areas.length, j++ {
                        int room = anchorAreaRoom(areas[j], ai.tryOrder, ax, ay, aw, ah,
                                                  cbX, cbY, cbW, cbH)
                        if room > bestRoom { best = j  bestRoom = room }
                    }
                    if best != i {
                        int t = areas[i]
                        areas[i] = areas[best]
                        areas[best] = t
                    }
                }
            }
            // Walk them and take the first that fits. Without an order
            // the first candidate is the area the element asked for, so
            // a position that fits is kept and the rest are never
            // reached; when none fits, the original stands rather than
            // the last one tried.
            for int i = 0, i < areas.length, i++ {
                anchorPlaceAt(areas[i], ax, ay, aw, ah, b)
                if !anchorOverflows(anchorTryX, anchorTryY, b.w, b.h, cbX, cbY, cbW, cbH) {
                    wantX = anchorTryX
                    wantY = anchorTryY
                    break
                }
            }
            if wantX != b.x || wantY != b.y { shiftBoxTree(b, wantX - b.x, wantY - b.y) }
            // `position-visibility: no-overflow` hides a box that still
            // overflows once every candidate has been tried. It hides
            // the whole box rather than clipping it harder, which is
            // what Chromium does and what the render suite checks by
            // straddling the box across the edge: a stricter clip would
            // leave the part that falls inside.
            if ai.visibility == POSVIS_NO_OVERFLOW && b.node != null
                && anchorOverflows(b.x, b.y, b.w, b.h, cbX, cbY, cbW, cbH) {
                anchorHiddenIds[`${b.node.id}`] = true
                anyAnchorHidden = true
            }
        }
    }
    // The containing block for the descendants, tracked the way the
    // positioning pass tracks it rather than stored on every box.
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
    for int i = 0, i < b.children.length, i++ { placeAnchored(b.children[i], nx, ny, nw, nh) }
}

// ---- entry points ----------------------------------------------------------------

// Lays out a styled document in a viewport `width` px wide. Returns
// the root box; its height is the document height.
// ---- CSS Conditional 4: answering the container queries ---------------
//
// A query asks about an ancestor's size, which is layout's to know, so
// the document is laid out, the queries are answered from that box
// tree, and if any answer changed the cascade and the layout are run
// again. One extra pass is enough rather than a loop because
// `container-type` contains the container's size: what the query gates
// cannot change what the query asked about.
//
// The stack is the enclosing containers, innermost last. A query with a
// name takes the innermost container carrying it; one without takes the
// innermost container of any name.
arr[text] cqStackNames = []
arr[int] cqStackWidths = []
arr[int] cqStackHeights = []
arr[int] cqStackTypes = []
bool cqAnswerChanged = false

void func cqEvaluateFor(nid:int) {
    for int q = 0, q < cssContainerQueryConds.length, q++ {
        // A nested query holds only if the one enclosing it does.
        bool holds = true
        int qq = q
        while qq != CQ_NONE && holds {
            holds = cqQueryHoldsHere(qq)
            qq = cssContainerQueryParent[qq]
        }
        text key = `${nid}:${q}`
        int was = containerQueryAnswers[key]
        int now = holds ? 1 : 0
        if was == null || was != now {
            if now == 1 || was != null { cqAnswerChanged = true }
            if now == 1 { containerQueryAnswers[key] = 1 }
            else if was != null { containerQueryAnswers[key] = 0 }
        }
    }
}

bool func cqQueryHoldsHere(q:int) {
    int at = -1
    for int i = cqStackNames.length - 1, i >= 0, i-- {
        if cssContainerQueryNames[q] == '' || cqStackNames[i] == cssContainerQueryNames[q] {
            at = i
            break
        }
    }
    if at < 0 { return false }
    if cqStackTypes[at] != CONTAINER_SIZE && conditionNeedsBlockAxis(cssContainerQueryConds[q]) {
        return false
    }
    int savedW = cssViewportWidth
    int savedH = cssViewportHeight
    cssViewportWidth = cqStackWidths[at]
    cssViewportHeight = cqStackHeights[at]
    cssAnsweringContainer = true
    bool got = evaluateMediaCondition(cssContainerQueryConds[q].toAscii())
    cssAnsweringContainer = false
    cssViewportWidth = savedW
    cssViewportHeight = savedH
    return got
}

void func cqWalk(b:Box) {
    bool real = b.kind != BOX_TEXT && b.kind != BOX_ANON
    // An element is asked about the containers *above* it, so its own
    // answers are taken before it is pushed. A container is not inside
    // itself, and a query never styles the element that established it.
    if real && b.node != null && b.node.id > 0 { cqEvaluateFor(b.node.id) }
    bool pushed = false
    if real && b.style.containerType != CONTAINER_NORMAL {
        // The content box is what a query measures: 320px of content
        // inside 20px of padding answers 320, not 360, which is what
        // Chromium answers and what `box-sizing: border-box` confirms.
        cqStackNames.push(b.style.containerName)
        cqStackWidths.push(maxInt(b.w - b.pl - b.pr - b.bl - b.br, 0))
        cqStackHeights.push(maxInt(b.h - b.pt - b.pb - b.bt - b.bb, 0))
        cqStackTypes.push(b.style.containerType)
        pushed = true
    }
    for int i = 0, i < b.children.length, i++ { cqWalk(b.children[i]) }
    if pushed {
        cqStackNames.pop()
        cqStackWidths.pop()
        cqStackHeights.pop()
        cqStackTypes.pop()
    }
}

bool func answerContainerQueries(root:Box) {
    arr[text] emptyNames = []
    arr[int] emptyW = []
    arr[int] emptyH = []
    arr[int] emptyT = []
    cqStackNames = emptyNames
    cqStackWidths = emptyW
    cqStackHeights = emptyH
    cqStackTypes = emptyT
    cqAnswerChanged = false
    cqWalk(root)
    return cqAnswerChanged
}

// How many times the queries may be answered again before the answer is
// taken as final. A query on an outer container can change the size of
// an inner one, whose own query then has to be asked again -- Chromium
// resolves that to a fixed point and so does this. Each pass answers
// from the sizes the last one produced, so an ordinary stylesheet
// settles in one or two; the bound is for one written to make two
// queries flip each other for ever.
const int CQ_MAX_PASSES = 8

Box func layoutDocument(doc:Node, width:int) {
    // The sizes `anchor-size()` resolved to on a previous call belong
    // to that call; a fresh layout of the document starts without them.
    if anyAnchorSize {
        map[int] emptyAnchorSizes = {}
        anchorSizePx = emptyAnchorSizes
    }
    anchorSizeChanged = false
    Box laid = layoutDocumentOnce(doc, width)
    // Every page that never says `@container` skips this, having done
    // exactly what it did before this existed: one bool, once.
    if cssSawContainerQuery && laid != null {
        int pass = 0
        while pass < CQ_MAX_PASSES && answerContainerQueries(laid) {
            pass++
            computeStyles(doc)
            laid = layoutDocumentOnce(doc, width)
        }
    }
    // And every page that never says `anchor-size()` skips this for the
    // same one boolean. A pass that changes no resolved size is the
    // fixed point: the sizes come off the anchors' own boxes, and an
    // anchor that did not move gives the same answer again. The bound
    // is for a stylesheet written to make two of them chase each other.
    if !anyAnchorSize || laid == null { return laid }
    int spass = 0
    while spass < CQ_MAX_PASSES && anchorSizeChanged {
        anchorSizeChanged = false
        spass++
        laid = layoutDocumentOnce(doc, width)
    }
    return laid
}

Box func layoutDocumentOnce(doc:Node, width:int) {
    nextBoxId = 1
    boxRegistry = [null]
    // The stand-in boxes are keyed by box id, which starts again here.
    firstLineBoxes = {}
    // One float list for the document. Properly a float belongs to its
    // block formatting context and cannot escape it, but nothing here
    // establishes one yet (todo.md); what matters for now is that a
    // second layout does not inherit the first one's floats.
    resetFloats()
    // The static positions of the layout before this one, cleared only
    // if it had any, so a document that positions nothing allocates
    // nothing here. The flag is still the previous layout's until the
    // line below clears it, which is what makes the test right.
    if docHasPositioned {
        map[int] emptyStaticX = {}
        map[int] emptyStaticY = {}
        staticPosX = emptyStaticX
        staticPosY = emptyStaticY
    }
    docHasPositioned = false
    anyRtlText = false
    docHasFloats = false
    inlineInkOverhang = 0
    currentFontKey = ''         // the canvas font may have been changed behind our back
    Node html = findElement(doc, 'html')
    if html == null { return null }
    int t0 = archtelosTiming ? now() : 0
    Box root = buildBox(html, html.style)
    if archtelosTiming { profBuildMs = profBuildMs + (now() - t0) }
    if root == null { return null }
    // The items are numbered as soon as the tree exists rather than
    // after it is laid out, because an inside marker is part of the
    // first line and its width is the width of its own label: "10." is
    // wider than "9.", and layout cannot reserve the space without
    // knowing which one it is.
    numberListItems(root)
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
        // An anchored box resolves against another element's finished
        // rectangle, so it is placed after every other positioned box
        // has one. A page that names no anchor never walks the tree.
        if anyAnchorName {
            map[int] emptyX = {}
            map[int] emptyY = {}
            map[int] emptyW = {}
            map[int] emptyH = {}
            map[int] emptyBX = {}
            map[int] emptyBY = {}
            map[int] emptyBW = {}
            map[int] emptyBH = {}
            anchorLiveX = emptyX
            anchorLiveY = emptyY
            anchorLiveW = emptyW
            anchorLiveH = emptyH
            map[int] emptyIX = {}
            map[int] emptyIY = {}
            map[int] emptyIW = {}
            map[int] emptyIH = {}
            anchorInsetX = emptyIX
            anchorInsetY = emptyIY
            anchorInsetW = emptyIW
            anchorInsetH = emptyIH
            anchorBoxX = emptyBX
            anchorBoxY = emptyBY
            anchorBoxW = emptyBW
            anchorBoxH = emptyBH
            anchorBoxFound = false
            if anyAnchorScope {
                map[int] emptySId = {}
                map[int] emptySDepth = {}
                scopeNameId = emptySId
                scopeNameDepth = emptySDepth
                scopeSavedName = []
                scopeSavedId = []
                scopeSavedDepth = []
            }
            collectAnchors(root, 0)
            if anchorBoxFound { placeAnchored(root, 0, 0, width, root.h) }
        }
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
