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
    if w <= 0 || h <= 0 { return }
    if colorIsPaintable(s.background) {
        paintFill(s.background, s.effectiveOpacity)
        if s.borderRadius > 0 {
            roundedRectPath(x, y, w, h, s.borderRadius)
            fillPath()
        } else {
            drawRect(x, y, w, h)
        }
        fillAlpha(1.0)
    }
    // the background image paints over the colour
    if s.backgroundImage.present {
        paintLinearGradient(x, y, w, h, s.backgroundImage, s.effectiveOpacity)
    }
}

// ---- linear gradients (CSS Images 3) ---------------------------------
//
// The gradient line runs through the centre of the box at the declared
// angle, long enough that the corners furthest along it map to 0 and 1,
// which is what makes `to bottom right` reach the corners exactly
// (CSS Images 3 SS3.4.1).
//
// It is painted as a run of one-pixel bands, each a flat colour. That
// is not how one would like to draw a gradient: Festina's canvas has
// `fillLinearGradient`, but its two colour arguments must be literals
// -- "a color must come from a literal, so the compiler can resolve it
// once" -- and a CSS gradient's colours are known only at run time. It
// also interpolates between exactly two stops, where CSS allows any
// number. See FINDINGS.md, "a gradient cannot be built at run time".
//
// There is no clip region on the canvas either (todo.md), so an
// off-axis band cannot be drawn as a rotated rectangle and clipped; it
// is built as the polygon where the band meets the box and filled as a
// path.

float gradDirX = 0.0
float gradDirY = 1.0

// Unit vector along the gradient line. CSS measures the angle clockwise
// from pointing up, and y grows downwards on the canvas.
void func gradientDirection(angleDeg:float) {
    float rad = angleDeg * 3.14159265358979 / 180.0
    gradDirX = Math.sin(rad)
    gradDirY = 0.0 - Math.cos(rad)
}

float func absFloat(v:float) { return v < 0.0 ? 0.0 - v : v }
float func minFloat(a:float, b:float) { return a < b ? a : b }
float func maxFloat(a:float, b:float) { return a > b ? a : b }

// Stop positions resolved to fractions of the gradient line, which
// needs the line's length and so cannot happen before paint time. A
// stop with no position sits halfway between its neighbours, and the
// first and last default to 0 and 1 (CSS Images 3 SS3.4.3); positions
// never decrease.
arr[float] gradOffsets = []

void func resolveGradientStops(g:Gradient, length:float) {
    arr[float] out = []
    int n = g.stops.length
    for int i = 0, i < n, i++ {
        if g.posKind[i] == GSTOP_PERCENT { out.push(g.posVal[i]) }
        else if g.posKind[i] == GSTOP_PX { out.push(length > 0.0 ? g.posVal[i] / length : 0.0) }
        else { out.push(0.0 - 1.0) }
    }
    if out[0] < 0.0 { out[0] = 0.0 }
    if out[n - 1] < 0.0 { out[n - 1] = 1.0 }
    for int i = 1, i < n - 1, i++ {
        if out[i] >= 0.0 { continue }
        int j = i + 1
        while j < n && out[j] < 0.0 { j++ }
        float lo = out[i - 1]
        float hi = j < n ? out[j] : 1.0
        int gap = j - i + 1
        for int k = i, k < j, k++ {
            out[k] = lo + (hi - lo) * (k - i + 1).toFloat() / gap.toFloat()
        }
        i = j - 1
    }
    for int i = 1, i < n, i++ {
        if out[i] < out[i - 1] { out[i] = out[i - 1] }
    }
    gradOffsets = out
}

// The colour at `t` along the line, interpolated in sRGB between the
// two stops that bracket it -- which is what both Chromium and the
// standard do for an ordinary gradient.
int func gradientColorAt(g:Gradient, offsets:arr[float], tIn:float) {
    float t = tIn
    int n = g.stops.length
    if n == 0 { return COLOR_TRANSPARENT }
    if n == 1 { return g.stops[0] }
    if g.repeating {
        float first = offsets[0]
        float last = offsets[n - 1]
        float span = last - first
        if span > 0.0 {
            float rel = (t - first) / span
            rel = rel - Math.floor(rel).toFloat()
            t = first + rel * span
        }
    }
    if t <= offsets[0] { return g.stops[0] }
    if t >= offsets[n - 1] { return g.stops[n - 1] }
    for int i = 0, i + 1 < n, i++ {
        float a = offsets[i]
        float b = offsets[i + 1]
        if t < a || t > b { continue }
        if b <= a { return g.stops[i + 1] }
        float f = (t - a) / (b - a)
        int c0 = g.stops[i]
        int c1 = g.stops[i + 1]
        return packColor(
            lerpChannel(colorRed(c0), colorRed(c1), f),
            lerpChannel(colorGreen(c0), colorGreen(c1), f),
            lerpChannel(colorBlue(c0), colorBlue(c1), f),
            lerpChannel(colorAlpha(c0), colorAlpha(c1), f))
    }
    return g.stops[n - 1]
}

int func lerpChannel(a:int, b:int, f:float) {
    int v = roundPx(a.toFloat() + (b.toFloat() - a.toFloat()) * f)
    if v < 0 { return 0 }
    if v > 255 { return 255 }
    return v
}

// Clips a convex polygon to the half-plane nx*x + ny*y <= c.
arr[float] clipOutX = []
arr[float] clipOutY = []

void func clipHalfPlane(xs:arr[float], ys:arr[float], nx:float, ny:float, c:float) {
    arr[float] ox = []
    arr[float] oy = []
    int n = xs.length
    for int i = 0, i < n, i++ {
        int j = (i + 1) % n
        float xi = xs[i]
        float yi = ys[i]
        float xj = xs[j]
        float yj = ys[j]
        float di = nx * xi + ny * yi - c
        float dj = nx * xj + ny * yj - c
        if di <= 0.0 { ox.push(xi)  oy.push(yi) }
        if (di < 0.0 && dj > 0.0) || (di > 0.0 && dj < 0.0) {
            float f = di / (di - dj)
            ox.push(xi + (xj - xi) * f)
            oy.push(yi + (yj - yi) * f)
        }
    }
    clipOutX = ox
    clipOutY = oy
}

void func paintLinearGradient(x:int, y:int, w:int, h:int, g:Gradient, opacity:float) {
    if g.stops.length < 2 || w <= 0 || h <= 0 { return }
    gradientDirection(g.angle)
    float dx = gradDirX
    float dy = gradDirY

    float halfW = w.toFloat() / 2.0
    float halfH = h.toFloat() / 2.0
    float half = absFloat(halfW * dx) + absFloat(halfH * dy)
    if half <= 0.0 { return }
    float length = half + half
    float cxf = x.toFloat() + halfW
    float cyf = y.toFloat() + halfH
    float x0 = cxf - dx * half
    float y0 = cyf - dy * half

    resolveGradientStops(g, length)
    arr[float] offsets = gradOffsets
    fillAlpha(opacity)
    bool horizontal = absFloat(dy) < 0.001
    bool vertical = absFloat(dx) < 0.001
    int steps = roundPx(length)
    if steps < 1 { steps = 1 }

    for int i = 0, i < steps, i++ {
        float t0 = i.toFloat() / steps.toFloat()
        float t1 = (i + 1).toFloat() / steps.toFloat()
        int c = gradientColorAt(g, offsets, (t0 + t1) / 2.0)
        if colorAlpha(c) == 0 { continue }
        applyFillColor(c)
        if horizontal || vertical {
            // the band is a rectangle, so no polygon is needed
            float a0 = x0 + dx * length * t0 + dy * 0.0
            float b0 = y0 + dy * length * t0
            float a1 = x0 + dx * length * t1
            float b1 = y0 + dy * length * t1
            if horizontal {
                int lo = roundPx(minFloat(a0, a1))
                int hi = roundPx(maxFloat(a0, a1))
                int bx = maxInt(lo, x)
                int bw = minInt(hi, x + w) - bx
                if bw > 0 { drawRect(bx, y, bw, h) }
            } else {
                int lo = roundPx(minFloat(b0, b1))
                int hi = roundPx(maxFloat(b0, b1))
                int by = maxInt(lo, y)
                int bh = minInt(hi, y + h) - by
                if bh > 0 { drawRect(x, by, w, bh) }
            }
            continue
        }
        // Off-axis: the band meets the box in a polygon. The polygon's
        // vertices have to be whole pixels -- moveTo and lineTo take
        // integers -- so a band one pixel wide rounds to a sliver with
        // anti-aliased edges, and consecutive slivers leave seams of
        // background showing through. Each band therefore starts a
        // pixel earlier than it should and overwrites the tail of its
        // predecessor, which closes the seam at the cost of biasing a
        // boundary pixel towards the later colour by less than a unit.
        arr[float] px = [x.toFloat(), (x + w).toFloat(), (x + w).toFloat(), x.toFloat()]
        arr[float] py = [y.toFloat(), y.toFloat(), (y + h).toFloat(), (y + h).toFloat()]
        float base = dx * x0 + dy * y0
        float p0 = base + length * t0 - 1.0
        float p1 = base + length * t1
        // keep dx*x + dy*y >= p0, i.e. -dx*x - dy*y <= -p0
        clipHalfPlane(px, py, 0.0 - dx, 0.0 - dy, 0.0 - p0)
        if clipOutX.length < 3 { continue }
        clipHalfPlane(clipOutX, clipOutY, dx, dy, p1)
        if clipOutX.length < 3 { continue }
        beginPath()
        moveTo(roundPx(clipOutX[0]), roundPx(clipOutY[0]))
        for int k = 1, k < clipOutX.length, k++ {
            lineTo(roundPx(clipOutX[k]), roundPx(clipOutY[k]))
        }
        closePath()
        fillPath()
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
        int c = colorWithOpacity(s.borderTopColor, s.effectiveOpacity)
        borderColor(colorRed(c), colorGreen(c), colorBlue(c))
        lineWidth(b.bt)
        int half = Math.floorDiv(b.bt, 2)
        roundedRectPath(x + half, y + half, w - b.bt, h - b.bt, maxInt(s.borderRadius - half, 1))
        strokePath()
        borderColor(-1, -1, -1)
        return
    }
    if b.bt > 0 && colorIsPaintable(s.borderTopColor) && !skipTop {
        paintFill(s.borderTopColor, s.effectiveOpacity)
        drawRect(x, y, w, b.bt)
    }
    if b.bb > 0 && colorIsPaintable(s.borderBottomColor) {
        paintFill(s.borderBottomColor, s.effectiveOpacity)
        drawRect(x, y + h - b.bb, w, b.bb)
    }
    if b.bl > 0 && colorIsPaintable(s.borderLeftColor) && !skipLeft {
        paintFill(s.borderLeftColor, s.effectiveOpacity)
        drawRect(x, y, b.bl, h)
    }
    if b.br > 0 && colorIsPaintable(s.borderRightColor) {
        paintFill(s.borderRightColor, s.effectiveOpacity)
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

// An outline is drawn just outside the border box and takes no space,
// so it can overlap whatever is next to it (CSS Basic User Interface 3).
// Every outline style paints solid, as every border style does.
void func paintOutline(b:Box) {
    Style s = b.style
    int w = s.outlineWidth
    if w <= 0 || b.w <= 0 || b.h <= 0 { return }
    applyFillColor(colorWithOpacity(s.outlineColor, s.effectiveOpacity))
    drawRect(b.x - w, b.y - w, b.w + w + w, w)
    drawRect(b.x - w, b.y + b.h, b.w + w + w, w)
    drawRect(b.x - w, b.y, w, b.h)
    drawRect(b.x + b.w, b.y, w, b.h)
    fillAlpha(1.0)
}

void func paintListMarker(b:Box) {
    Style s = b.style
    if s.listStyle == LIST_NONE { return }
    Line ln = firstLineOf(b)
    int baseline = ln != null ? ln.baseline : contentY(b) + fontAscent(s)
    int fs = s.fontSize
    paintFill(s.color, s.effectiveOpacity)
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
            int c = colorWithOpacity(s.color, s.effectiveOpacity)
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
    paintFill(s.color, s.effectiveOpacity)
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
    int deco = decoUnion(s.textDecoration, s.inheritedDecoration)
    if deco > 0 {
        int thickness = maxInt(1, Math.floorDiv(s.fontSize, 16))
        if deco == DECO_UNDERLINE || deco == DECO_UNDERLINE + DECO_LINE_THROUGH {
            drawRect(f.x, f.baseline + 1 + Math.floorDiv(thickness, 2), f.w, thickness)
        }
        if deco >= DECO_LINE_THROUGH {
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
            paintFill(s.borderTopColor, s.effectiveOpacity)
            drawRect(f.x, f.y, f.w, ib.bt)
        }
        if ib.bb > 0 && colorIsPaintable(s.borderBottomColor) {
            paintFill(s.borderBottomColor, s.effectiveOpacity)
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
    if b.kind == BOX_IFRAME {
        if !s.hidden { paintFrame(b) }
        return
    }
    if s.outlineWidth > 0 && !s.hidden { paintOutline(b) }
    if b.isListItem && !s.hidden { paintListMarker(b) }
    if !s.hidden { paintFormControl(b) }
    paintLines(b)
    // In-flow children first, then the positioned ones in z-index order:
    // a positioned box paints above its in-flow siblings whatever the
    // document order (CSS2 §9.9). This is the painting order for the
    // common case, not the full stacking-context algorithm -- there is
    // no opacity or transform layer to sort against yet.
    // A document with no positioned box anywhere needs neither the
    // skip test nor the second pass: one loop in document order is the
    // whole painting order.
    if !docHasPositioned {
        for int i = 0, i < b.children.length, i++ {
            Box c = b.children[i]
            if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
            paintBox(c)
        }
        return
    }
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if boxIsPositioned(c) { continue }
        paintBox(c)
    }
    int lowest = 0
    int highest = 0
    bool anyPositioned = false
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if !boxIsPositioned(c) { continue }
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if !anyPositioned || c.style.zIndex < lowest { lowest = c.style.zIndex }
        if !anyPositioned || c.style.zIndex > highest { highest = c.style.zIndex }
        anyPositioned = true
    }
    if !anyPositioned { return }
    for int z = lowest, z <= highest, z++ {
        for int i = 0, i < b.children.length, i++ {
            Box c = b.children[i]
            if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
            if !boxIsPositioned(c) { continue }
            if c.style.zIndex != z { continue }
            paintBox(c)
        }
    }
}

// A frame paints the document it loaded, translated into its content
// box. The tree is reached through loadedFrames by key rather than held
// on the box: a field of the box's own type is the back-pointer shape
// CLAUDE.md §6 rules out. There is no clip region on the canvas
// (todo.md), so the vertical extent is enforced by the same cull
// paintDocument already does and wider content can still spill.
void func paintFrame(b:Box) {
    int cx = b.x + b.bl + b.pl
    int cy = b.y + b.bt + b.pt
    int cw = b.w - b.bl - b.br - b.pl - b.pr
    int ch = b.h - b.bt - b.bb - b.pt - b.pb
    if cw <= 0 || ch <= 0 { return }
    applyFillColor(COLOR_WHITE)
    drawRect(cx, cy, cw, ch)
    fillAlpha(1.0)
    if b.frameKey == null { return }
    Box inner = loadedFrames[b.frameKey]
    if inner == null { return }
    int savedTop = paintTop
    int savedBottom = paintBottom
    text savedFont = currentFontKey
    saveState()
    translate(cx, cy)
    paintTop = 0
    paintBottom = ch
    currentFontKey = ''
    paintBox(inner)
    restoreState()
    paintTop = savedTop
    paintBottom = savedBottom
    currentFontKey = savedFont
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
