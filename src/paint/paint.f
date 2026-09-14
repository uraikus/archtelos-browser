// Painting: walks the laid-out box tree and draws it on the Festina
// canvas. Backgrounds, borders (rounded through a bezier path), text
// runs at their baselines, underlines, images, list markers and form
// controls. The caller has already translated the canvas so that
// document coordinates land where they should on screen.

import ../layout/layout.f

// Boxes entirely outside [paintTop, paintBottom) in document
// coordinates are skipped -- long pages stay cheap to scroll.
int paintTop = -1000000000
int paintBottom = 1000000000

const float KAPPA = 0.5523

void func paintFill(c:int, opacity:float) {
    applyFillColor(colorWithOpacity(c, opacity))
}

// A rounded-rectangle path; the caller fills or strokes it.
void func roundedRectPath(x:int, y:int, w:int, h:int, rIn:int) {
    int r = minInt(rIn, Math.floorDiv(minInt(w, h), 2))
    int k = roundPx(r.toFloat() * KAPPA)
    beginPath()
    moveTo(x + r, y)
    lineTo(x + w - r, y)
    curveTo(x + w - r + k, y, x + w, y + r - k, x + w, y + r)
    lineTo(x + w, y + h - r)
    curveTo(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h)
    lineTo(x + r, y + h)
    curveTo(x + r - k, y + h, x, y + h - r + k, x, y + h - r)
    lineTo(x, y + r)
    curveTo(x, y + r - k, x + r - k, y, x + r, y)
    closePath()
}

void func paintBackground(x:int, y:int, w:int, h:int, s:Style) {
    if !colorIsPaintable(s.background) || w <= 0 || h <= 0 { return }
    paintFill(s.background, s.opacity)
    if s.borderRadius > 0 {
        roundedRectPath(x, y, w, h, s.borderRadius)
        fillPath()
    } else {
        drawRect(x, y, w, h)
    }
    fillAlpha(1.0)
}

void func paintBorders(b:Box) {
    Style s = b.style
    if s.borderStyle == BORDER_NONE { return }
    int x = b.x
    int y = b.y
    int w = b.w
    int h = b.h
    // border-collapse: adjacent cells share one border, so a cell
    // paints its top edge only in the first row and its left edge
    // only in the first column
    bool skipTop = b.kind == BOX_CELL && s.borderCollapse && b.tableRow > 0
    bool skipLeft = b.kind == BOX_CELL && s.borderCollapse && b.tableCol > 0
    if s.borderRadius > 0 && b.bt == b.br && b.bt == b.bb && b.bt == b.bl && b.bt > 0 {
        // a uniform rounded border is stroked along the path's centre
        int c = colorWithOpacity(s.borderTopColor, s.opacity)
        borderColor(colorRed(c), colorGreen(c), colorBlue(c))
        lineWidth(b.bt)
        int half = Math.floorDiv(b.bt, 2)
        roundedRectPath(x + half, y + half, w - b.bt, h - b.bt, maxInt(s.borderRadius - half, 1))
        strokePath()
        borderColor(-1, -1, -1)
        return
    }
    if b.bt > 0 && colorIsPaintable(s.borderTopColor) && !skipTop {
        paintFill(s.borderTopColor, s.opacity)
        drawRect(x, y, w, b.bt)
    }
    if b.bb > 0 && colorIsPaintable(s.borderBottomColor) {
        paintFill(s.borderBottomColor, s.opacity)
        drawRect(x, y + h - b.bb, w, b.bb)
    }
    if b.bl > 0 && colorIsPaintable(s.borderLeftColor) && !skipLeft {
        paintFill(s.borderLeftColor, s.opacity)
        drawRect(x, y, b.bl, h)
    }
    if b.br > 0 && colorIsPaintable(s.borderRightColor) {
        paintFill(s.borderRightColor, s.opacity)
        drawRect(x + w - b.br, y, b.br, h)
    }
    fillAlpha(1.0)
}

bool func boxVisible(b:Box) {
    return b.y + b.h >= paintTop && b.y <= paintBottom
}

// The first line box inside a list item, for placing its marker.
Line func firstLineOf(b:Box) {
    if b.lines.length > 0 { return b.lines[0] }
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR { continue }
        Line ln = firstLineOf(c)
        if ln != null { return ln }
    }
    return null
}

void func paintListMarker(b:Box) {
    Style s = b.style
    if s.listStyle == LIST_NONE { return }
    Line ln = firstLineOf(b)
    int baseline = ln != null ? ln.baseline : contentY(b) + fontAscent(s)
    int fs = s.fontSize
    paintFill(s.color, s.opacity)
    int edge = contentX(b)
    if s.listStyle == LIST_DECIMAL {
        text label = `${b.listIndex}.`
        setFontFor(s)
        int w = measureTextWidth(label)
        drawText(label, edge - w - roundPx(fs.toFloat() * 0.5), baseline)
    } else {
        int r = maxInt(roundPx(fs.toFloat() * 0.19), 2)
        int cx = edge - roundPx(fs.toFloat() * 0.9)
        int cy = baseline - roundPx(fs.toFloat() * 0.33)
        if s.listStyle == LIST_DISC {
            drawCircle(cx, cy, r)
        } else if s.listStyle == LIST_CIRCLE {
            int c = colorWithOpacity(s.color, s.opacity)
            borderColor(colorRed(c), colorGreen(c), colorBlue(c))
            lineWidth(1)
            fillStyle(-1, -1, -1)
            drawCircle(cx, cy, r)
            borderColor(-1, -1, -1)
        } else {
            drawRect(cx - r, cy - r, r * 2, r * 2)
        }
    }
    fillAlpha(1.0)
}

void func paintTextFragment(f:Fragment) {
    Style s = f.box.style
    if s.hidden { return }
    setFontFor(s)
    paintFill(s.color, s.opacity)
    if s.letterSpacing == 0 {
        drawText(f.content, f.x, f.baseline)
    } else {
        // letter-spacing: one glyph at a time, each advanced by its
        // own width plus the spacing (drawText has no spacing itself)
        arr[text] chars = f.content.split('')
        int x = f.x
        for int i = 0, i < chars.length, i++ {
            drawText(chars[i], x, f.baseline)
            x = x + measureTextWidth(chars[i]) + s.letterSpacing
        }
    }
    if s.textDecoration > 0 {
        int thickness = maxInt(1, Math.floorDiv(s.fontSize, 16))
        if s.textDecoration == DECO_UNDERLINE || s.textDecoration == DECO_UNDERLINE + DECO_LINE_THROUGH {
            drawRect(f.x, f.baseline + 1 + Math.floorDiv(thickness, 2), f.w, thickness)
        }
        if s.textDecoration >= DECO_LINE_THROUGH {
            drawRect(f.x, f.baseline - roundPx(s.fontSize.toFloat() * 0.3), f.w, thickness)
        }
    }
    fillAlpha(1.0)
}

void func paintInlineBackground(f:Fragment) {
    Box ib = f.box
    Style s = ib.style
    if s.hidden || f.w <= 0 { return }
    paintBackground(f.x, f.y, f.w, f.h, s)
    if s.borderStyle != BORDER_NONE {
        if ib.bt > 0 && colorIsPaintable(s.borderTopColor) {
            paintFill(s.borderTopColor, s.opacity)
            drawRect(f.x, f.y, f.w, ib.bt)
        }
        if ib.bb > 0 && colorIsPaintable(s.borderBottomColor) {
            paintFill(s.borderBottomColor, s.opacity)
            drawRect(f.x, f.y + f.h - ib.bb, f.w, ib.bb)
        }
        fillAlpha(1.0)
    }
}

void func paintImage(b:Box) {
    int x = contentX(b)
    int y = contentY(b)
    int w = contentWidth(b)
    int h = b.h - b.pt - b.pb - b.bt - b.bb
    if w <= 0 || h <= 0 { return }
    if b.image != null {
        fillAlpha(b.style.opacity)
        drawImage(b.image, x, y, w, h)
        fillAlpha(1.0)
        return
    }
    // a broken image: a thin frame and the alt text
    fillStyle(192, 192, 192)
    drawRect(x, y, w, 1)
    drawRect(x, y + h - 1, w, 1)
    drawRect(x, y, 1, h)
    drawRect(x + w - 1, y, 1, h)
    text alt = getAttr(b.node, 'alt')
    if alt != null && alt != '' && h >= b.style.fontSize {
        setFontFor(b.style)
        paintFill(b.style.color, b.style.opacity)
        drawText(alt, x + 2, y + fontAscent(b.style) + 1)
        fillAlpha(1.0)
    }
}

void func paintFormControl(b:Box) {
    Node n = b.node
    if n.tag != 'input' { return }
    text ty = textLower(getAttr(n, 'type'))
    if ty == 'checkbox' || ty == 'radio' {
        int x = b.x
        int y = b.y
        int w = b.w
        int h = b.h
        bool checked = hasAttr(n, 'checked')
        if ty == 'radio' {
            int r = Math.floorDiv(minInt(w, h), 2)
            borderColor(118, 118, 118)
            lineWidth(1)
            fillStyle(255, 255, 255)
            drawCircle(x + r, y + r, r - 1)
            borderColor(-1, -1, -1)
            if checked {
                fillStyle(0, 0, 0)
                drawCircle(x + r, y + r, maxInt(r - 4, 2))
            }
        } else if checked {
            fillStyle(0, 0, 0)
            beginPath()
            moveTo(x + 3, y + Math.floorDiv(h, 2))
            lineTo(x + Math.floorDiv(w, 2) - 1, y + h - 3)
            lineTo(x + w - 3, y + 3)
            lineTo(x + w - 5, y + 2)
            lineTo(x + Math.floorDiv(w, 2) - 1, y + h - 6)
            lineTo(x + 4, y + Math.floorDiv(h, 2) - 2)
            closePath()
            fillPath()
        }
    }
}

void func paintLines(b:Box) {
    for int i = 0, i < b.lines.length, i++ {
        Line ln = b.lines[i]
        if ln.y + ln.h < paintTop || ln.y > paintBottom { continue }
        // inline backgrounds first, outermost first
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            if f.kind == FRAG_INLINE_BG { paintInlineBackground(f) }
        }
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            if f.kind == FRAG_TEXT { paintTextFragment(f) }
            else if f.kind == FRAG_ATOMIC { paintBox(f.box) }
        }
    }
}

void func paintBox(b:Box) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return }
    if !boxVisible(b) { return }
    Style s = b.style
    if b.kind != BOX_ANON && !s.hidden {
        if b.kind == BOX_ROW {
            paintBackground(b.x, b.y, b.w, b.h, s)
        } else {
            paintBackground(b.x, b.y, b.w, b.h, s)
            paintBorders(b)
        }
    }
    if b.kind == BOX_IMAGE {
        if !s.hidden { paintImage(b) }
        return
    }
    if b.isListItem && !s.hidden { paintListMarker(b) }
    if !s.hidden { paintFormControl(b) }
    paintLines(b)
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        paintBox(c)
    }
}

// The document's canvas background: the body's background propagates
// to the canvas when html has none, as in CSS.
int func canvasBackground(root:Box) {
    if colorIsPaintable(root.style.background) { return root.style.background }
    for int i = 0, i < root.children.length, i++ {
        Box c = root.children[i]
        if c.node.tag == 'body' && colorIsPaintable(c.style.background) { return c.style.background }
    }
    return COLOR_WHITE
}

// Paints the whole document; the caller sets any transform first.
void func paintDocument(root:Box, viewTop:int, viewBottom:int) {
    paintTop = viewTop
    paintBottom = viewBottom
    currentFontKey = ''
    paintBox(root)
}

// ---- hit testing ---------------------------------------------------------------

// The innermost box under a document point, preferring text runs so
// links resolve to the element the text belongs to.
Box func hitTest(b:Box, x:int, y:int) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return null }
    for int i = 0, i < b.lines.length, i++ {
        Line ln = b.lines[i]
        if y < ln.y || y >= ln.y + ln.h { continue }
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            if f.kind == FRAG_INLINE_BG { continue }
            if x >= f.x && x < f.x + f.w && y >= f.y && y < f.y + f.h {
                if f.kind == FRAG_ATOMIC {
                    Box inner = hitTest(f.box, x, y)
                    return inner != null ? inner : f.box
                }
                return f.box
            }
        }
    }
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if x >= c.x && x < c.x + c.w && y >= c.y && y < c.y + c.h {
            Box inner = hitTest(c, x, y)
            return inner != null ? inner : c
        }
    }
    return null
}

// The href of the nearest enclosing link of a box, or null.
text func linkAt(root:Box, x:int, y:int) {
    Box hit = hitTest(root, x, y)
    if hit == null { return null }
    Node n = hit.node
    if n.id == 0 { return null }
    Node a = closestElement(n, 'a')
    if a == null { return null }
    return getAttr(a, 'href')
}
