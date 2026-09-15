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

// ---- where the painting goes -----------------------------------------
//
// `overflow: hidden` needs a clip region and the canvas has none. What
// Festina does have is images that are themselves drawable surfaces and
// that clip at their own bounds -- rectangles and text alike -- so a
// clipped subtree is painted into one and blitted back.
//
// Every primitive below therefore goes through a wrapper that sends it
// to the canvas or to the current layer. An image's own translate()
// carries the offset, so the wrappers pass document coordinates
// unchanged.
//
// An image is not the canvas's equal: it has no path API at all -- no
// beginPath, moveTo, lineTo or fillPath (FINDINGS.md, "an image is a
// drawable surface with a smaller API"). Inside a clipped subtree a
// rounded rectangle is therefore drawn square. That is recorded rather
// than hidden, and it is why the wrappers for the path calls exist at
// all: they turn a path into its rectangular approximation on a layer
// and leave it exact on the canvas.
img paintLayer = null

bool func paintingToLayer() {
    return paintLayer != null
}

void func pDrawRect(x:int, y:int, w:int, h:int) {
    if paintLayer == null { drawRect(x, y, w, h) }
    else { paintLayer.drawRect(x, y, w, h) }
}

void func pDrawCircle(x:int, y:int, r:int) {
    if paintLayer == null { drawCircle(x, y, r) }
    else { paintLayer.drawCircle(x, y, r) }
}

void func pDrawText(t:text, x:int, y:int) {
    if paintLayer == null { drawText(t, x, y) }
    else { paintLayer.drawText(t, x, y) }
}

void func pDrawImage(i:img, x:int, y:int) {
    if paintLayer == null { drawImage(i, x, y) }
    else { paintLayer.drawImage(i, x, y) }
}

void func pDrawImageScaled(i:img, x:int, y:int, w:int, h:int) {
    if paintLayer == null { drawImage(i, x, y, w, h) }
    else { paintLayer.drawImage(i, x, y, w, h) }
}


// A filled rounded rectangle. On the canvas this is a bezier path; on a
// layer there is no path API, so the corners are square. The shape is
// wrong by a few pixels at each corner and the box is still there,
// which is the better of the two failures available.
void func pFillRounded(x:int, y:int, w:int, h:int, r:int) {
    if paintLayer == null {
        roundedRectPath(x, y, w, h, r)
        fillPath()
    } else {
        paintLayer.drawRect(x, y, w, h)
    }
}

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
            pFillRounded(x, y, w, h, s.borderRadius)
        } else {
            pDrawRect(x, y, w, h)
        }
        fillAlpha(1.0)
    }
    // the background image paints over the colour
    if s.backgroundImage.present {
        paintLinearGradient(x, y, w, h, s.backgroundImage, s.effectiveOpacity)
    } else if s.backgroundUrl != '' {
        paintBackgroundImage(x, y, w, h, s)
    }
}

// One axis of a position, resolved against the space the image leaves
// over: a percentage aligns that much of the image with that much of
// the box, so `100%` puts its right edge on the box's right edge rather
// than pushing it a box-width across. `background-position` and
// `object-position` are the same computation over different leftovers
// -- the box minus the tile, and the box minus the fitted object.
int func resolvePositionAxis(l:Len, leftover:int, fontSize:int) {
    if l.kind == LEN_PERCENT { return roundPx(leftover.toFloat() * l.v) }
    if l.kind == LEN_PX { return roundPx(l.v) }
    return 0
}

// A background image, tiled and positioned inside the box. It is
// painted into an image the size of the box and drawn back, because a
// tile that runs off the edge has to be cut off there and Festina's
// canvas has no clip region -- the same reason overflow: hidden works
// the way it does (FINDINGS.md, "an image is a drawable surface with a
// smaller API").
void func paintBackgroundImage(x:int, y:int, w:int, h:int, s:Style) {
    if w <= 0 || h <= 0 { return }
    img src = loadedImages[s.backgroundUrl]
    if src == null { return }
    int iw = src.width
    int ih = src.height
    if iw <= 0 || ih <= 0 { return }
    int ox = resolvePositionAxis(s.backgroundPosX, w - iw, s.fontSize)
    int oy = resolvePositionAxis(s.backgroundPosY, h - ih, s.fontSize)

    // Where the first tile starts. Repeating backwards from the
    // declared position keeps the tile grid anchored to it.
    int startX = ox
    int startY = oy
    if s.backgroundRepeatX { while startX > 0 { startX = startX - iw } }
    if s.backgroundRepeatY { while startY > 0 { startY = startY - ih } }

    img layer = blankImage(w, h)
    int ty = startY
    bool moreY = true
    while moreY {
        int tx = startX
        bool moreX = true
        while moreX {
            layer.drawImage(src, tx, ty)
            if !s.backgroundRepeatX { moreX = false }
            else {
                tx = tx + iw
                if tx >= w { moreX = false }
            }
        }
        if !s.backgroundRepeatY { moreY = false }
        else {
            ty = ty + ih
            if ty >= h { moreY = false }
        }
    }
    // The tiles go into the layer at full alpha and the element's
    // opacity is applied once, to the blit. Setting it before the tiles
    // would apply it twice -- once into the layer's own pixels and
    // again as the layer is composited -- and leaving it unset paints a
    // fully opaque image on a half-transparent box.
    fillAlpha(s.effectiveOpacity)
    pDrawImage(layer, x, y)
    fillAlpha(1.0)
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
                if bw > 0 { pDrawRect(bx, y, bw, h) }
            } else {
                int lo = roundPx(minFloat(b0, b1))
                int hi = roundPx(maxFloat(b0, b1))
                int by = maxInt(lo, y)
                int bh = minInt(hi, y + h) - by
                if bh > 0 { pDrawRect(x, by, w, bh) }
            }
            continue
        }
        // Off-axis. Painting the band as a polygon is the obvious
        // thing and it is wrong: the vertices have to be whole pixels,
        // so abutting diagonal slivers are anti-aliased against each
        // other and the result is stippled rather than smooth -- a
        // 400x300 gradient came out as a 77 KB PNG, which is what a
        // smooth ramp never is.
        //
        // Instead the band is drawn as one-pixel-tall horizontal runs,
        // one per row of the box. Every rectangle then has integer
        // coordinates and covers whole pixels exactly, so nothing is
        // blended with anything, at the cost of a rectangle per band
        // per row.
        float base = dx * 0.5 + dy * 0.5
        float p0 = length * t0
        float p1 = length * t1
        float ox = dx * x0 + dy * y0
        for int row = y, row < y + h, row++ {
            // p = dx*(px + 0.5) + dy*(row + 0.5) - ox, solved for px
            float atRow = dy * (row.toFloat() + 0.5) - ox + dx * 0.5
            float lo = (p0 - atRow) / dx
            float hi = (p1 - atRow) / dx
            if hi < lo { float t = lo  lo = hi  hi = t }
            int xa = maxInt(roundPx(lo), x)
            int xb = minInt(roundPx(hi), x + w)
            if xb > xa { pDrawRect(xa, row, xb - xa, 1) }
        }
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
        if paintLayer == null {
            roundedRectPath(x + half, y + half, w - b.bt, h - b.bt, maxInt(s.borderRadius - half, 1))
            strokePath()
        } else {
            // no path API on a layer: the border is drawn as four sides
            paintLayer.drawRect(x, y, w, b.bt)
            paintLayer.drawRect(x, y + h - b.bb, w, b.bb)
            paintLayer.drawRect(x, y, b.bl, h)
            paintLayer.drawRect(x + w - b.br, y, b.br, h)
        }
        borderColor(-1, -1, -1)
        return
    }
    if b.bt > 0 && colorIsPaintable(s.borderTopColor) && !skipTop {
        paintFill(s.borderTopColor, s.effectiveOpacity)
        pDrawRect(x, y, w, b.bt)
    }
    if b.bb > 0 && colorIsPaintable(s.borderBottomColor) {
        paintFill(s.borderBottomColor, s.effectiveOpacity)
        pDrawRect(x, y + h - b.bb, w, b.bb)
    }
    if b.bl > 0 && colorIsPaintable(s.borderLeftColor) && !skipLeft {
        paintFill(s.borderLeftColor, s.effectiveOpacity)
        pDrawRect(x, y, b.bl, h)
    }
    if b.br > 0 && colorIsPaintable(s.borderRightColor) {
        paintFill(s.borderRightColor, s.effectiveOpacity)
        pDrawRect(x + w - b.br, y, b.br, h)
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
    pDrawRect(b.x - w, b.y - w, b.w + w + w, w)
    pDrawRect(b.x - w, b.y + b.h, b.w + w + w, w)
    pDrawRect(b.x - w, b.y, w, b.h)
    pDrawRect(b.x + b.w, b.y, w, b.h)
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
        pDrawText(label, edge - w - roundPx(fs.toFloat() * 0.5), baseline)
    } else {
        int r = maxInt(roundPx(fs.toFloat() * 0.19), 2)
        int cx = edge - roundPx(fs.toFloat() * 0.9)
        int cy = baseline - roundPx(fs.toFloat() * 0.33)
        if s.listStyle == LIST_DISC {
            pDrawCircle(cx, cy, r)
        } else if s.listStyle == LIST_CIRCLE {
            int c = colorWithOpacity(s.color, s.effectiveOpacity)
            borderColor(colorRed(c), colorGreen(c), colorBlue(c))
            lineWidth(1)
            fillStyle(-1, -1, -1)
            pDrawCircle(cx, cy, r)
            borderColor(-1, -1, -1)
        } else {
            pDrawRect(cx - r, cy - r, r * 2, r * 2)
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
        pDrawText(f.content, f.x, f.baseline)
    } else {
        // letter-spacing: one glyph at a time, each advanced by its
        // own width plus the spacing (drawText has no spacing itself)
        arr[text] chars = f.content.split('')
        int x = f.x
        for int i = 0, i < chars.length, i++ {
            pDrawText(chars[i], x, f.baseline)
            x = x + measureTextWidth(chars[i]) + s.letterSpacing
        }
    }
    int deco = decoUnion(s.textDecoration, s.inheritedDecoration)
    if deco > 0 {
        int thickness = maxInt(1, Math.floorDiv(s.fontSize, 16))
        if deco == DECO_UNDERLINE || deco == DECO_UNDERLINE + DECO_LINE_THROUGH {
            pDrawRect(f.x, f.baseline + 1 + Math.floorDiv(thickness, 2), f.w, thickness)
        }
        if deco >= DECO_LINE_THROUGH {
            pDrawRect(f.x, f.baseline - roundPx(s.fontSize.toFloat() * 0.3), f.w, thickness)
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
            pDrawRect(f.x, f.y, f.w, ib.bt)
        }
        if ib.bb > 0 && colorIsPaintable(s.borderBottomColor) {
            paintFill(s.borderBottomColor, s.effectiveOpacity)
            pDrawRect(f.x, f.y + f.h - ib.bb, f.w, ib.bb)
        }
        fillAlpha(1.0)
    }
}

// The concrete size object-fit gives a replaced element's content,
// from its intrinsic size and the content box (CSS Images 3 §5.5).
// Returned as a scale factor rather than a size so the caller rounds
// once.
float func objectFitScale(fit:int, iw:int, ih:int, w:int, h:int) {
    float sx = w.toFloat() / iw.toFloat()
    float sy = h.toFloat() / ih.toFloat()
    if fit == OBJECTFIT_CONTAIN { return sx < sy ? sx : sy }
    if fit == OBJECTFIT_COVER { return sx > sy ? sx : sy }
    if fit == OBJECTFIT_NONE { return 1.0 }
    // scale-down is the smaller of `none` and `contain`, which is
    // `contain` capped at 1: an image already inside its box is left
    // alone, and a larger one is shrunk to fit.
    float fitted = sx < sy ? sx : sy
    return fitted < 1.0 ? fitted : 1.0
}

// A replaced element's content, sized by object-fit and placed by
// object-position. The object can be larger than the box -- `cover`
// and `none` both allow it -- and a replaced element clips its content
// to the content box, so it is painted into an image that size and
// blitted back, the canvas having no clip region (FINDINGS.md, "an
// image is a drawable surface with a smaller API").
void func paintFittedImage(b:Box, x:int, y:int, w:int, h:int) {
    int iw = b.imgW
    int ih = b.imgH
    if iw <= 0 || ih <= 0 {
        pDrawImageScaled(b.image, x, y, w, h)
        return
    }
    float scale = objectFitScale(b.style.objectFit, iw, ih, w, h)
    int ow = roundPx(iw.toFloat() * scale)
    int oh = roundPx(ih.toFloat() * scale)
    if ow <= 0 || oh <= 0 { return }
    int ox = resolvePositionAxis(b.style.objectPosX, w - ow, b.style.fontSize)
    int oy = resolvePositionAxis(b.style.objectPosY, h - oh, b.style.fontSize)
    // An object that lands exactly inside the box needs no layer: the
    // clip has nothing to cut, and a direct blit avoids allocating and
    // compositing an image the size of the box.
    if ox >= 0 && oy >= 0 && ox + ow <= w && oy + oh <= h {
        pDrawImageScaled(b.image, x + ox, y + oy, ow, oh)
        return
    }
    // The caller has already set the element's opacity for the direct
    // blit above. The layer is drawn into at full alpha and composited
    // at that opacity, so it is applied once rather than to both the
    // layer's pixels and the blit.
    img layer = blankImage(w, h)
    fillAlpha(1.0)
    layer.drawImage(b.image, ox, oy, ow, oh)
    fillAlpha(b.style.opacity)
    pDrawImage(layer, x, y)
}

void func paintImage(b:Box) {
    int x = contentX(b)
    int y = contentY(b)
    int w = contentWidth(b)
    int h = b.h - b.pt - b.pb - b.bt - b.bb
    if w <= 0 || h <= 0 { return }
    if b.image != null {
        fillAlpha(b.style.opacity)
        // `fill` is the initial value and stretches the content to the
        // box, which is one blit and the only thing a page that does
        // not mention object-fit ever reaches.
        if b.style.objectFit == OBJECTFIT_FILL { pDrawImageScaled(b.image, x, y, w, h) }
        else { paintFittedImage(b, x, y, w, h) }
        fillAlpha(1.0)
        return
    }
    // a broken image: a thin frame and the alt text
    fillStyle(192, 192, 192)
    pDrawRect(x, y, w, 1)
    pDrawRect(x, y + h - 1, w, 1)
    pDrawRect(x, y, 1, h)
    pDrawRect(x + w - 1, y, 1, h)
    text alt = getAttr(b.node, 'alt')
    if alt != null && alt != '' && h >= b.style.fontSize {
        setFontFor(b.style)
        paintFill(b.style.color, b.style.opacity)
        pDrawText(alt, x + 2, y + fontAscent(b.style) + 1)
        fillAlpha(1.0)
    }
}

// An audio element's controls. Chromium draws a rounded bar with a play
// button, a timeline and a volume control; this draws the same shape at
// the same size, so a page laid out around it looks right, without
// pretending to be pixel-identical to another browser's widget.
void func paintAudioControls(b:Box) {
    int x = b.x + b.bl + b.pl
    int y = b.y + b.bt + b.pt
    int w = b.w - b.bl - b.br - b.pl - b.pr
    int h = b.h - b.bt - b.bb - b.pt - b.pb
    if w <= 0 || h <= 0 { return }

    fillStyle(241, 243, 244)
    pFillRounded(x, y, w, h, Math.floorDiv(h, 2))

    // the play triangle
    int cy = y + Math.floorDiv(h, 2)
    int px = x + 16
    int r = 7
    fillStyle(60, 64, 67)
    beginPath()
    moveTo(px, cy - r)
    lineTo(px + 12, cy)
    lineTo(px, cy + r)
    closePath()
    fillPath()

    // the timeline, and the elapsed part of it
    int tx = px + 26
    int tw = w - (tx - x) - 60
    if tw > 0 {
        fillStyle(189, 193, 198)
        pDrawRect(tx, cy - 1, tw, 3)
        fillStyle(60, 64, 67)
        pDrawCircle(tx, cy, 5)
    }

    // the speaker
    int vx = x + w - 34
    fillStyle(60, 64, 67)
    pDrawRect(vx, cy - 4, 5, 8)
    beginPath()
    moveTo(vx + 5, cy - 4)
    lineTo(vx + 11, cy - 9)
    lineTo(vx + 11, cy + 9)
    lineTo(vx + 5, cy + 4)
    closePath()
    fillPath()
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
            pDrawCircle(x + r, y + r, r - 1)
            borderColor(-1, -1, -1)
            if checked {
                fillStyle(0, 0, 0)
                pDrawCircle(x + r, y + r, maxInt(r - 4, 2))
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

// Whether a box with `overflow: hidden` has anything inside worth
// clipping. A box whose content fits needs no layer, and a layer is the
// expensive part -- an image the size of the box, painted and blitted.
bool func boxClipsAnything(b:Box) {
    int w = b.w - b.bl - b.br
    int h = b.h - b.bt - b.bb
    if w <= 0 || h <= 0 { return true }
    return b.children.length > 0
}

// Paints a box whose descendants are clipped: the box itself onto the
// current target, then its children into a layer the size of its
// padding box, which is blitted back. An image clips at its own bounds,
// which is the clip region the canvas does not have.
void func paintClipped(b:Box) {
    Style s = b.style
    if b.kind != BOX_ANON && !s.hidden {
        paintBackground(b.x, b.y, b.w, b.h, s)
        paintBorders(b)
    }
    int px = b.x + b.bl
    int py = b.y + b.bt
    int pw = b.w - b.bl - b.br
    int ph = b.h - b.bt - b.bb
    if pw <= 0 || ph <= 0 { return }

    img layer = blankImage(pw, ph)
    // the layer's own transform carries the offset, so everything
    // painted into it still speaks document coordinates
    layer.translate(0 - px, 0 - py)
    paintLayer = layer
    paintLines(b)
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        paintBox(c)
    }
    paintLayer = null
    pDrawImage(layer, px, py)
}

void func paintBox(b:Box) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return }
    if !boxVisible(b) { return }
    // `overflow: hidden` clips this box's descendants to its padding box
    // (CSS2 §11.1.1). The box itself -- its background and border -- is
    // not clipped, so it paints normally and only the inside goes to a
    // layer.
    if b.style.overflowHidden && !paintingToLayer() && boxClipsAnything(b) {
        paintClipped(b)
        return
    }
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
    if b.kind == BOX_AUDIO {
        paintAudioControls(b)
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
    pDrawRect(cx, cy, cw, ch)
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
