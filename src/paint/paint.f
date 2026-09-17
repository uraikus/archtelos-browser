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

// How far the document is scrolled, and how tall the viewport is. A
// `background-attachment: fixed` image is positioned against the
// viewport rather than the element, which is the one thing that needs
// to know.
// The canvas is as wide as the viewport, and a fixed background's
// positioning area is the viewport.
int func canvasViewWidth() { return cssViewportWidth }

int paintScrollY = 0
int paintViewHeight = 0

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

void func pSaveState() {
    if paintLayer == null { saveState() } else { paintLayer.saveState() }
}

void func pRestoreState() {
    if paintLayer == null { restoreState() } else { paintLayer.restoreState() }
}

void func pTranslate(x:int, y:int) {
    if paintLayer == null { translate(x, y) } else { paintLayer.translate(x, y) }
}

void func pRotate(deg:float) {
    if paintLayer == null { rotate(deg) } else { paintLayer.rotate(deg) }
}

void func pScale(sx:float, sy:float) {
    if paintLayer == null { scale(sx, sy) } else { paintLayer.scale(sx, sy) }
}

void func pDrawImageScaled(i:img, x:int, y:int, w:int, h:int) {
    if paintLayer == null { drawImage(i, x, y, w, h) }
    else { paintLayer.drawImage(i, x, y, w, h) }
}


// A filled rounded rectangle. On the canvas this is a bezier path; on a
// layer there is no path API, so the corners are square. The shape is
// wrong by a few pixels at each corner and the box is still there,
// which is the better of the two failures available.
// The four corners resolved against a box, in pixels, and scaled back
// where two on one edge would overlap (Backgrounds and Borders 3 §5.5:
// every radius is divided by the same factor, so the shape keeps its
// proportions). Eight numbers out of a function need globals
// (FINDINGS.md, "one value out of a function").
int radTLX = 0
int radTLY = 0
int radTRX = 0
int radTRY = 0
int radBRX = 0
int radBRY = 0
int radBLX = 0
int radBLY = 0

int func radiusPx(l:Len, against:int) {
    if l.kind == LEN_PERCENT { return maxInt(roundPx(l.v * against.toFloat() / 100.0), 0) }
    if l.kind == LEN_PX { return maxInt(roundPx(l.v), 0) }
    return 0
}

float func radiusShrink(sum:int, side:int) {
    if sum <= side || sum <= 0 { return 1.0 }
    return side.toFloat() / sum.toFloat()
}

void func resolveCornerRadii(s:Style, w:int, h:int) {
    radTLX = radiusPx(s.radiusTopLeftX, w)
    radTLY = radiusPx(s.radiusTopLeftY, h)
    radTRX = radiusPx(s.radiusTopRightX, w)
    radTRY = radiusPx(s.radiusTopRightY, h)
    radBRX = radiusPx(s.radiusBottomRightX, w)
    radBRY = radiusPx(s.radiusBottomRightY, h)
    radBLX = radiusPx(s.radiusBottomLeftX, w)
    radBLY = radiusPx(s.radiusBottomLeftY, h)
    float f = minFloat(minFloat(radiusShrink(radTLX + radTRX, w),
                                radiusShrink(radBLX + radBRX, w)),
                       minFloat(radiusShrink(radTLY + radBLY, h),
                                radiusShrink(radTRY + radBRY, h)))
    if f >= 1.0 { return }
    radTLX = roundPx(radTLX.toFloat() * f)
    radTLY = roundPx(radTLY.toFloat() * f)
    radTRX = roundPx(radTRX.toFloat() * f)
    radTRY = roundPx(radTRY.toFloat() * f)
    radBRX = roundPx(radBRX.toFloat() * f)
    radBRY = roundPx(radBRY.toFloat() * f)
    radBLX = roundPx(radBLX.toFloat() * f)
    radBLY = roundPx(radBLY.toFloat() * f)
}

void func pFillRoundedCorners(x:int, y:int, w:int, h:int,
                              tl:int, tr:int, brc:int, bl:int) {
    pFillRoundedEllipses(x, y, w, h, tl, tl, tr, tr, brc, brc, bl, bl)
}

void func pFillRoundedEllipses(x:int, y:int, w:int, h:int,
                               tlx:int, tly:int, trx:int, trry:int,
                               brx:int, bry:int, blx:int, bly:int) {
    if paintLayer == null {
        roundedRectPathEllipses(x, y, w, h, tlx, tly, trx, trry, brx, bry, blx, bly)
        fillPath()
    } else {
        // no path API on a layer, so the corners come out square
        // (FINDINGS.md, "an image is a drawable surface with a smaller
        // API")
        paintLayer.drawRect(x, y, w, h)
    }
}

void func pFillRounded(x:int, y:int, w:int, h:int, r:int) {
    pFillRoundedCorners(x, y, w, h, r, r, r, r)
}

void func paintFill(c:int, opacity:float) {
    applyFillColor(colorWithOpacity(c, opacity))
}

// A rounded-rectangle path; the caller fills or strokes it.
// A rounded rectangle whose four corners may differ. Each radius is
// capped at half the shorter side, as §5.5 requires, so two large radii
// on one edge cannot overlap into each other.
void func roundedRectPathCorners(x:int, y:int, w:int, h:int,
                                 tl:int, tr:int, brc:int, bl:int) {
    roundedRectPathEllipses(x, y, w, h, tl, tl, tr, tr, brc, brc, bl, bl)
}

// A corner may be an ellipse rather than a quarter circle, so each takes
// a horizontal and a vertical radius. The control points are the same
// kappa approximation either way: it is the two radii that differ.
void func roundedRectPathEllipses(x:int, y:int, w:int, h:int,
                                  tlx:int, tly:int, trx:int, trry:int,
                                  brx:int, bry:int, blx:int, bly:int) {
    int capX = Math.floorDiv(w, 2)
    int capY = Math.floorDiv(h, 2)
    int ax = minInt(tlx, capX)
    int ay = minInt(tly, capY)
    int bx = minInt(trx, capX)
    int by = minInt(trry, capY)
    int cx = minInt(brx, capX)
    int cy = minInt(bry, capY)
    int dx = minInt(blx, capX)
    int dy = minInt(bly, capY)
    int kax = roundPx(ax.toFloat() * KAPPA)
    int kay = roundPx(ay.toFloat() * KAPPA)
    int kbx = roundPx(bx.toFloat() * KAPPA)
    int kby = roundPx(by.toFloat() * KAPPA)
    int kcx = roundPx(cx.toFloat() * KAPPA)
    int kcy = roundPx(cy.toFloat() * KAPPA)
    int kdx = roundPx(dx.toFloat() * KAPPA)
    int kdy = roundPx(dy.toFloat() * KAPPA)
    beginPath()
    moveTo(x + ax, y)
    lineTo(x + w - bx, y)
    curveTo(x + w - bx + kbx, y, x + w, y + by - kby, x + w, y + by)
    lineTo(x + w, y + h - cy)
    curveTo(x + w, y + h - cy + kcy, x + w - cx + kcx, y + h, x + w - cx, y + h)
    lineTo(x + dx, y + h)
    curveTo(x + dx - kdx, y + h, x, y + h - dy + kdy, x, y + h - dy)
    lineTo(x, y + ay)
    curveTo(x, y + ay - kay, x + ax - kax, y, x + ax, y)
    closePath()
}

void func roundedRectPath(x:int, y:int, w:int, h:int, rIn:int) {
    roundedRectPathCorners(x, y, w, h, rIn, rIn, rIn, rIn)
}

// The rectangle `background-clip` paints within and the one
// `background-origin` places the image in (Backgrounds and Borders 3
// §3.7, §3.8), chosen from the box's three edges. The caller passes the
// border box and the two inset quadruples rather than a struct, because
// this runs for every box on the page and a struct here would be an
// allocation for each one.
int bgAreaX = 0
int bgAreaY = 0
int bgAreaW = 0
int bgAreaH = 0

void func backgroundArea(which:int, borderEdge:int, contentEdge:int,
                         x:int, y:int, w:int, h:int,
                         bl:int, bt:int, br:int, bb:int,
                         pl:int, pt:int, pr:int, pb:int) {
    if which == borderEdge {
        bgAreaX = x  bgAreaY = y  bgAreaW = w  bgAreaH = h
        return
    }
    if which == contentEdge {
        bgAreaX = x + bl + pl
        bgAreaY = y + bt + pt
        bgAreaW = w - bl - br - pl - pr
        bgAreaH = h - bt - bb - pt - pb
        return
    }
    bgAreaX = x + bl
    bgAreaY = y + bt
    bgAreaW = w - bl - br
    bgAreaH = h - bt - bb
}

// The box's shadows, painted beneath its own background (Backgrounds
// and Borders 3 §6). Each is the border box offset by its two lengths
// and grown by its spread.
//
// The canvas has no blur, so the falloff is computed rather than
// filtered -- which a rectangle allows, because a Gaussian blur of one
// has a closed form. See gaussIntegral and paintBlurredRect below.
//
// `inset` shadows are painted by paintInsetShadows, after the
// background rather than under it.
void func paintShadows(x:int, y:int, w:int, h:int, s:Style) {
    if s.shadows.length == 0 { return }
    for int i = s.shadows.length - 1, i >= 0, i-- {
        Shadow sh = s.shadows[i]
        if sh.inset { continue }
        if !colorIsPaintable(sh.color) { continue }
        int sx = x + sh.dx - sh.spread
        int sy = y + sh.dy - sh.spread
        int sw = w + sh.spread + sh.spread
        int sh2 = h + sh.spread + sh.spread
        if sw <= 0 || sh2 <= 0 { continue }
        if sh.blur <= 0 {
            paintFill(sh.color, s.effectiveOpacity)
            pDrawRect(sx, sy, sw, sh2)
            fillAlpha(1.0)
            continue
        }
        paintBlurredRect(sx, sy, sw, sh2, sh.color, s.effectiveOpacity, sh.blur)
    }
}

// The Gaussian's own integral: the share of a blur's weight that is
// still on one side of a point `z` standard deviations past it. `erf`
// is Abramowitz and Stegun 7.1.26, whose error is below 1.5e-7 -- a
// thousandth of the 1/255 a painted pixel can tell apart.
float func gaussIntegral(z:float) {
    float x = z / 1.4142135623730951
    bool negative = x < 0.0
    float ax = negative ? -x : x
    float t = 1.0 / (1.0 + 0.3275911 * ax)
    float poly = t * (0.254829592 + t * (0.0 - 0.284496736 + t * (1.421413741
               + t * (0.0 - 1.453152027 + t * 1.061405429))))
    float e = 1.0 - poly * Math.exp(0.0 - ax * ax)
    float erf = negative ? 0.0 - e : e
    return 0.5 * (1.0 + erf)
}

// One axis of a blurred rectangle: what a point at `p` keeps of a
// rectangle running from `lo` to `hi`, blurred by `sigma`. A Gaussian
// blur of a rectangle is the difference of the Gaussian's integrals at
// its two edges, and the blur of a two-dimensional rectangle is the two
// axes multiplied -- which is what makes a corner a quarter of the
// colour where an edge is a half of it.
float func blurAxis(p:float, lo:float, hi:float, sigma:float) {
    return gaussIntegral((p - lo) / sigma) - gaussIntegral((p - hi) / sigma)
}

// One axis's profile as a one pixel tall image, so a whole row of a
// blurred corner can be drawn with one blit rather than a pixel at a
// time: `drawImage` multiplies the image's own alpha by `fillAlpha`,
// and a product of the two axes is exactly what a separable blur is.
// The key is everything the answer depends on, so a page whose boxes
// share a shadow builds each ramp once.
map[img] shadowRamps = {}

img func shadowRamp(key:text, n:int, from:float, span:float, sigma:float, c:int) {
    img hit = shadowRamps[key]
    if hit != null { return hit }
    img out = blankImage(n, 1)
    fillStyle(colorRed(c), colorGreen(c), colorBlue(c))
    for int i = 0, i < n, i++ {
        float a = blurAxis(from + i.toFloat() + 0.5, 0.0, span, sigma)
        if a <= 0.002 { continue }
        fillAlpha(a > 1.0 ? 1.0 : a)
        out.drawPixel(i, 0)
    }
    fillAlpha(1.0)
    shadowRamps[key] = out
    return out
}

// A rectangle blurred by a Gaussian of standard deviation half the blur
// radius, which is what Backgrounds and Borders 3 §7.1 asks a shadow's
// blur to be.
//
// The blur is separable, so the rectangle divides into nine parts: four
// corners where both axes are still changing, four edges where only one
// is, and the middle where neither is. Only the corners are worked out a
// pixel at a time, and only once per distinct shadow; an edge is one
// row or column per pixel of the reach, and the middle is a single fill.
void func paintBlurredRect(x:int, y:int, w:int, h:int, c:int, opacity:float, blur:int) {
    if w <= 0 || h <= 0 { return }
    float sigma = blur.toFloat() / 2.0
    // Three standard deviations out the Gaussian has 0.0013 of its
    // weight left, which is a third of what a pixel can show.
    int reach = maxInt(roundPx(sigma * 3.0), 1)
    int rx = minInt(reach, Math.floorDiv(w, 2))
    int ry = minInt(reach, Math.floorDiv(h, 2))
    int midW = w - rx - rx
    int midH = h - ry - ry
    float fw = w.toFloat()
    float fh = h.toFloat()
    int shade = colorWithOpacity(c, opacity)
    if !colorIsPaintable(shade) { return }
    float own = colorAlpha(shade).toFloat() / 255.0

    // The middle, at the one alpha the whole of it has.
    float fxMid = midW > 0
        ? blurAxis((rx + Math.floorDiv(midW, 2)).toFloat() + 0.5, 0.0, fw, sigma)
        : 0.0
    float fyMid = midH > 0
        ? blurAxis((ry + Math.floorDiv(midH, 2)).toFloat() + 0.5, 0.0, fh, sigma)
        : 0.0
    fillStyle(colorRed(shade), colorGreen(shade), colorBlue(shade))
    if midW > 0 && midH > 0 {
        float a = fxMid * fyMid * own
        fillAlpha(a > 1.0 ? 1.0 : a)
        pDrawRect(x + rx, y + ry, midW, midH)
    }

    // The four edges: one row or column per pixel, from the reach
    // outside to the inner corner.
    if midW > 0 {
        for int j = 0, j < reach + ry, j++ {
            float fy = blurAxis((j - reach).toFloat() + 0.5, 0.0, fh, sigma)
            float a = fxMid * fy * own
            if a <= 0.002 { continue }
            fillAlpha(a > 1.0 ? 1.0 : a)
            pDrawRect(x + rx, y - reach + j, midW, 1)
            pDrawRect(x + rx, y + h + reach - 1 - j, midW, 1)
        }
    }
    if midH > 0 {
        for int i = 0, i < reach + rx, i++ {
            float fx = blurAxis((i - reach).toFloat() + 0.5, 0.0, fw, sigma)
            float a = fx * fyMid * own
            if a <= 0.002 { continue }
            fillAlpha(a > 1.0 ? 1.0 : a)
            pDrawRect(x - reach + i, y + ry, 1, midH)
            pDrawRect(x + w + reach - 1 - i, y + ry, 1, midH)
        }
    }
    fillAlpha(1.0)

    // The four corners, where both axes are still changing. Each row of
    // one is the horizontal profile at that row's own share of the
    // vertical one, which is one blit of the ramp at that alpha: the
    // whole shadow costs a row of work per pixel of the reach rather
    // than a pixel of work per pixel of it.
    int cw = reach + rx
    if cw <= 0 || reach + ry <= 0 { return }
    text rampKey = `${blur}|${shade}|${cw}|${w}`
    img rampLeft = shadowRamp(rampKey + '|l', cw, (0 - reach).toFloat(),
                              fw, sigma, shade)
    img rampRight = shadowRamp(rampKey + '|r', cw, fw - rx.toFloat(),
                               fw, sigma, shade)
    for int j = 0, j < reach + ry, j++ {
        float a = blurAxis((j - reach).toFloat() + 0.5, 0.0, fh, sigma) * own
        if a <= 0.002 { continue }
        fillAlpha(a > 1.0 ? 1.0 : a)
        pDrawImage(rampLeft, x - reach, y - reach + j)
        pDrawImage(rampRight, x + w - rx, y - reach + j)
        pDrawImage(rampLeft, x - reach, y + h + reach - 1 - j)
        pDrawImage(rampRight, x + w - rx, y + h + reach - 1 - j)
    }
    fillAlpha(1.0)
}

// The area between two rectangles -- the outer one minus the inner --
// as four rectangles. The inner is clamped to the outer first, so a
// shadow offset further than the box is wide fills it rather than
// painting a negative band.
void func fillFrame(ox:int, oy:int, ow:int, oh:int, ix:int, iy:int, iw:int, ih:int) {
    int left = maxInt(ix, ox)
    int top = maxInt(iy, oy)
    int right = minInt(ix + iw, ox + ow)
    int bottom = minInt(iy + ih, oy + oh)
    if right < left { right = left }
    if bottom < top { bottom = top }
    if top > oy { pDrawRect(ox, oy, ow, top - oy) }
    if bottom < oy + oh { pDrawRect(ox, bottom, ow, oy + oh - bottom) }
    if left > ox { pDrawRect(ox, top, left - ox, bottom - top) }
    if right < ox + ow { pDrawRect(right, top, ox + ow - right, bottom - top) }
}

// `inset` shadows (Backgrounds and Borders 3 §6). The shadow is the
// padding box minus that box offset by the shadow's lengths and shrunk
// by its spread, so it reads as a band inside an edge rather than a
// shape outside the box. It paints over the background and under the
// content, which is why it is a second pass rather than part of the one
// that puts the outer shadows underneath.
//
// The blur works the way the outer one does and inwards: a frame per
// pixel of reach, each at a small alpha, so the alpha accumulates
// against the edge and thins towards the middle.
void func paintInsetShadows(x:int, y:int, w:int, h:int,
                            bl:int, bt:int, br:int, bb:int, s:Style) {
    if s.shadows.length == 0 { return }
    int px = x + bl
    int py = y + bt
    int pw = w - bl - br
    int ph = h - bt - bb
    if pw <= 0 || ph <= 0 { return }
    for int i = s.shadows.length - 1, i >= 0, i-- {
        Shadow sh = s.shadows[i]
        if !sh.inset { continue }
        if !colorIsPaintable(sh.color) { continue }
        int ix = px + sh.dx + sh.spread
        int iy = py + sh.dy + sh.spread
        int iw = pw - sh.spread - sh.spread
        int ih = ph - sh.spread - sh.spread
        if sh.blur > 0 {
            paintInsetBlur(px, py, pw, ph, ix, iy, iw, ih,
                           sh.color, s.effectiveOpacity, sh.blur)
            continue
        }
        paintFill(sh.color, s.effectiveOpacity)
        fillFrame(px, py, pw, ph, ix, iy, iw, ih)
        fillAlpha(1.0)
    }
}

// The inside of a blurred shadow is the outside of its hole. An outer
// shadow's alpha is the two axes multiplied; an inset one's is one
// minus that, and painting `1 - fx` and then `1 - fy` over it
// accumulates to exactly that -- one minus (1 - (1 - fx)) times
// (1 - (1 - fy)) is one minus fx times fy. So an inset shadow is two
// passes of plain strips: no per-pixel work, and not even the ramp
// images an outer shadow's corners need.
//
// Two passes only accumulate to the right answer at full alpha, so a
// shadow that is not fully opaque is painted into an image at full
// alpha and that image blitted at the alpha it wanted -- which is also
// how the strips are kept inside the padding box without a clip region.
void func paintInsetBlur(px:int, py:int, pw:int, ph:int,
                         hx:int, hy:int, hw:int, hh:int,
                         c:int, opacity:float, blur:int) {
    if pw <= 0 || ph <= 0 { return }
    int shade = colorWithOpacity(c, opacity)
    if !colorIsPaintable(shade) { return }
    float own = colorAlpha(shade).toFloat() / 255.0
    float sigma = blur.toFloat() / 2.0
    float fw = maxInt(hw, 0).toFloat()
    float fh = maxInt(hh, 0).toFloat()
    img layer = own >= 0.999 ? null : blankImage(pw, ph)
    fillStyle(colorRed(shade), colorGreen(shade), colorBlue(shade))
    for int i = 0, i < pw, i++ {
        float a = 1.0 - blurAxis((px + i - hx).toFloat() + 0.5, 0.0, fw, sigma)
        if a <= 0.002 { continue }
        fillAlpha(a > 1.0 ? 1.0 : a)
        if layer == null { pDrawRect(px + i, py, 1, ph) }
        else { layer.drawRect(i, 0, 1, ph) }
    }
    for int j = 0, j < ph, j++ {
        float a = 1.0 - blurAxis((py + j - hy).toFloat() + 0.5, 0.0, fh, sigma)
        if a <= 0.002 { continue }
        fillAlpha(a > 1.0 ? 1.0 : a)
        if layer == null { pDrawRect(px, py + j, pw, 1) }
        else { layer.drawRect(0, j, pw, 1) }
    }
    if layer != null {
        fillAlpha(own)
        pDrawImage(layer, px, py)
    }
    fillAlpha(1.0)
}

// The layer being painted. A global rather than a parameter because the
// three functions below read seven of its fields between them, and
// because filling one reusable struct per layer costs no allocation --
// which matters: this runs for every box on the page that has a
// background.
BgLayer bgPaint

// How much of the layer's image shows. One for every layer that is not
// the second image of a cross-fade, so nothing else pays for it.
float bgFadeAlpha = 1.0

void func bgLayerOfStyle(s:Style) {
    bgPaint.url = s.backgroundUrl
    if anyCrossFade {
        bgPaint.fadeUrl = s.backgroundFadeUrl
        bgPaint.fade = s.backgroundFade
    }
    bgPaint.image = s.backgroundImage
    bgPaint.repeatX = s.backgroundRepeatX
    bgPaint.repeatY = s.backgroundRepeatY
    bgPaint.posX = s.backgroundPosX
    bgPaint.posY = s.backgroundPosY
    bgPaint.sizeKind = s.backgroundSizeKind
    bgPaint.sizeW = s.backgroundSizeW
    bgPaint.sizeH = s.backgroundSizeH
    bgPaint.clip = s.backgroundClip
    bgPaint.origin = s.backgroundOrigin
    bgPaint.fixed = s.backgroundFixed
}

void func bgLayerOf(l:BgLayer) {
    bgPaint.url = l.url
    if anyCrossFade {
        bgPaint.fadeUrl = l.fadeUrl
        bgPaint.fade = l.fade
    }
    bgPaint.image = l.image
    bgPaint.repeatX = l.repeatX
    bgPaint.repeatY = l.repeatY
    bgPaint.posX = l.posX
    bgPaint.posY = l.posY
    bgPaint.sizeKind = l.sizeKind
    bgPaint.sizeW = l.sizeW
    bgPaint.sizeH = l.sizeH
    bgPaint.clip = l.clip
    bgPaint.origin = l.origin
    bgPaint.fixed = l.fixed
}

// One layer's image, placed in its own origin area and clipped to its
// own painting area. `bgPaint` says which layer.
void func paintBackgroundLayer(x:int, y:int, w:int, h:int,
                               bl:int, bt:int, br:int, bb:int,
                               pl:int, pt:int, pr:int, pb:int, s:Style) {
    bool hasImage = bgPaint.image.present || bgPaint.url != ''
    if !hasImage { return }
    int clipX = x
    int clipY = y
    int clipW = w
    int clipH = h
    if bgPaint.clip != BGCLIP_BORDER {
        backgroundArea(bgPaint.clip, BGCLIP_BORDER, BGCLIP_CONTENT,
                       x, y, w, h, bl, bt, br, bb, pl, pt, pr, pb)
        clipX = bgAreaX  clipY = bgAreaY  clipW = bgAreaW  clipH = bgAreaH
        if clipW <= 0 || clipH <= 0 { return }
    }
    backgroundArea(bgPaint.origin, BGORIGIN_BORDER, BGORIGIN_CONTENT,
                   x, y, w, h, bl, bt, br, bb, pl, pt, pr, pb)
    int origX = bgAreaX
    int origY = bgAreaY
    int origW = bgAreaW
    int origH = bgAreaH
    if origW <= 0 || origH <= 0 { origX = clipX  origY = clipY  origW = clipW  origH = clipH }
    // `background-attachment: fixed` positions the image against the
    // viewport rather than the element, so it stays where it is while
    // the page scrolls under it. The clip is still the element's own
    // area, so the image shows only where the element is.
    if bgPaint.fixed {
        origX = 0
        origY = paintScrollY
        origW = clipW > 0 ? canvasViewWidth() : origW
        origH = paintViewHeight > 0 ? paintViewHeight : origH
    }
    if bgPaint.image.present {
        paintGradientClipped(clipX, clipY, clipW, clipH, origX, origY, origW, origH, s)
    } else {
        paintBackgroundImage(clipX, clipY, clipW, clipH, origX, origY, origW, origH, s)
        // cross-fade(): the second image goes over the first at its own
        // share, which for two opaque images is exactly the standard's
        // mix -- the first is already down at full alpha, so the blit
        // leaves (1 - p) of it. One field test per layer painted is what
        // a page without one pays.
        if anyCrossFade && bgPaint.fadeUrl != '' {
            text second = bgPaint.fadeUrl
            float share = bgPaint.fade
            bgPaint.url = second
            bgPaint.fadeUrl = ''
            bgFadeAlpha = share
            paintBackgroundImage(clipX, clipY, clipW, clipH, origX, origY, origW, origH, s)
            bgFadeAlpha = 1.0
        }
    }
}

void func paintBackground(x:int, y:int, w:int, h:int,
                          bl:int, bt:int, br:int, bb:int,
                          pl:int, pt:int, pr:int, pb:int, s:Style) {
    if w <= 0 || h <= 0 { return }
    // This runs for every box on the page, so neither area is worked
    // out unless it is asked for: the clip only when it is not the
    // border box it defaults to, and the origin only when there is an
    // image to place in it.
    int clipX = x
    int clipY = y
    int clipW = w
    int clipH = h
    // The colour goes under every image, clipped by the LAST layer's
    // `background-clip` (§3.5) -- which is the first layer's only when
    // there is one.
    int colourClip = s.bgExtra.length > 0
        ? s.bgExtra[s.bgExtra.length - 1].clip : s.backgroundClip
    if colourClip != BGCLIP_BORDER {
        backgroundArea(colourClip, BGCLIP_BORDER, BGCLIP_CONTENT,
                       x, y, w, h, bl, bt, br, bb, pl, pt, pr, pb)
        clipX = bgAreaX  clipY = bgAreaY  clipW = bgAreaW  clipH = bgAreaH
        if clipW <= 0 || clipH <= 0 { return }
    }

    if colorIsPaintable(s.background) {
        paintFill(s.background, s.effectiveOpacity)
        if s.borderRadius > 0 {
            // The radii are the border box's, and a percentage is of it:
            // a clipped background keeps that curve rather than deriving
            // the smaller inner one.
            resolveCornerRadii(s, w, h)
            pFillRoundedEllipses(clipX, clipY, clipW, clipH,
                                 radTLX, radTLY, radTRX, radTRY,
                                 radBRX, radBRY, radBLX, radBLY)
        } else {
            pDrawRect(clipX, clipY, clipW, clipH)
        }
        fillAlpha(1.0)
    }
    // The images paint over the colour, back to front: the layers are
    // written front to back, so the last one goes down first and the
    // first one written ends up on top.
    for int k = 0, k < s.bgExtra.length, k++ {
        bgLayerOf(s.bgExtra[s.bgExtra.length - 1 - k])
        paintBackgroundLayer(x, y, w, h, bl, bt, br, bb, pl, pt, pr, pb, s)
    }
    // The first layer last, so it ends up on top. Asked before the
    // twelve fields are copied, because this runs for every box on the
    // page and most of them have no image at all.
    if s.backgroundImage.present || s.backgroundUrl != '' {
        bgLayerOfStyle(s)
        paintBackgroundLayer(x, y, w, h, bl, bt, br, bb, pl, pt, pr, pb, s)
    }
}

// A gradient takes its geometry from the positioning area and must not
// paint outside the painting area. When the two are the same rectangle
// -- which they are unless `background-clip` says otherwise -- it paints
// straight onto the target. Otherwise it goes through an image the size
// of the painting area, the clip region the canvas does not have.
void func paintGradientClipped(clipX:int, clipY:int, clipW:int, clipH:int,
                               origX:int, origY:int, origW:int, origH:int, s:Style) {
    if origX == clipX && origY == clipY && origW == clipW && origH == clipH {
        if bgPaint.image.conic {
            paintConicGradient(clipX, clipY, clipW, clipH, bgPaint.image, s.effectiveOpacity)
        } else if bgPaint.image.radial {
            paintRadialGradient(clipX, clipY, clipW, clipH, bgPaint.image, s.effectiveOpacity)
        } else {
            paintLinearGradient(clipX, clipY, clipW, clipH, bgPaint.image, s.effectiveOpacity)
        }
        return
    }
    img prev = paintLayer
    img layer = blankImage(clipW, clipH)
    // the layer carries the offset, so the gradient is still painted in
    // document coordinates
    layer.translate(0 - clipX, 0 - clipY)
    paintLayer = layer
    if bgPaint.image.conic {
        paintConicGradient(origX, origY, origW, origH, bgPaint.image, s.effectiveOpacity)
    } else if bgPaint.image.radial {
        paintRadialGradient(origX, origY, origW, origH, bgPaint.image, s.effectiveOpacity)
    } else {
        paintLinearGradient(origX, origY, origW, origH, bgPaint.image, s.effectiveOpacity)
    }
    paintLayer = prev
    fillAlpha(s.effectiveOpacity)
    pDrawImage(layer, clipX, clipY)
    fillAlpha(1.0)
}

// One axis of a position, resolved against the space the image leaves
// over: a percentage aligns that much of the image with that much of
// the box, so `100%` puts its right edge on the box's right edge rather
// than pushing it a box-width across. `background-position` and
// `object-position` are the same computation over different leftovers
// -- the box minus the tile, and the box minus the fitted object.
int func resolvePositionAxis(l:Len, leftover:int, fontSize:int) {
    if l.kind == LEN_PERCENT { return roundPx(leftover.toFloat() * l.v / 100.0) }
    if l.kind == LEN_PX { return roundPx(l.v) }
    return 0
}

// A background image, tiled and positioned inside the box. It is
// painted into an image the size of the box and drawn back, because a
// tile that runs off the edge has to be cut off there and Festina's
// canvas has no clip region -- the same reason overflow: hidden works
// the way it does (FINDINGS.md, "an image is a drawable surface with a
// smaller API").
// The size a background image is drawn at (Backgrounds and Borders 3
// §3.9), from its intrinsic size and the box. `auto` on one axis takes
// its size from the other through the image's own ratio; `auto` on both
// is the intrinsic size. A percentage is of the box.
int bgTileW = 0
int bgTileH = 0

void func backgroundTileSize(s:Style, iw:int, ih:int, w:int, h:int) {
    bgTileW = iw
    bgTileH = ih
    if bgPaint.sizeKind == BGSIZE_AUTO { return }
    float fw = w.toFloat() / iw.toFloat()
    float fh = h.toFloat() / ih.toFloat()
    if bgPaint.sizeKind == BGSIZE_COVER || bgPaint.sizeKind == BGSIZE_CONTAIN {
        float scale = bgPaint.sizeKind == BGSIZE_COVER
            ? (fw > fh ? fw : fh)
            : (fw < fh ? fw : fh)
        bgTileW = roundPx(iw.toFloat() * scale)
        bgTileH = roundPx(ih.toFloat() * scale)
        return
    }
    bool autoW = bgPaint.sizeW.kind != LEN_PX && bgPaint.sizeW.kind != LEN_PERCENT
    bool autoH = bgPaint.sizeH.kind != LEN_PX && bgPaint.sizeH.kind != LEN_PERCENT
    if autoW && autoH { return }
    if !autoW { bgTileW = roundPx(lenToPx(bgPaint.sizeW, w, s.fontSize)) }
    if !autoH { bgTileH = roundPx(lenToPx(bgPaint.sizeH, h, s.fontSize)) }
    if autoW { bgTileW = roundPx(iw.toFloat() * bgTileH.toFloat() / ih.toFloat()) }
    if autoH { bgTileH = roundPx(ih.toFloat() * bgTileW.toFloat() / iw.toFloat()) }
}

void func paintBackgroundImage(clipX:int, clipY:int, clipW:int, clipH:int,
                               x:int, y:int, w:int, h:int, s:Style) {
    if w <= 0 || h <= 0 || clipW <= 0 || clipH <= 0 { return }
    img src = loadedImages[bgPaint.url]
    if src == null { return }
    int srcW = src.width
    int srcH = src.height
    if srcW <= 0 || srcH <= 0 { return }
    backgroundTileSize(s, srcW, srcH, w, h)
    int iw = bgTileW
    int ih = bgTileH
    if iw <= 0 || ih <= 0 { return }
    // The drawn size, not the intrinsic one, is what the position
    // distributes the leftover of and what the repeat steps by.
    bool scaled = iw != srcW || ih != srcH
    int ox = resolvePositionAxis(bgPaint.posX, w - iw, s.fontSize)
    int oy = resolvePositionAxis(bgPaint.posY, h - ih, s.fontSize)

    // Where the first tile starts. Repeating backwards from the
    // declared position keeps the tile grid anchored to it.
    int startX = ox
    int startY = oy
    if bgPaint.repeatX { while startX > 0 { startX = startX - iw } }
    if bgPaint.repeatY { while startY > 0 { startY = startY - ih } }

    // The tiles are laid out in the positioning area and painted into
    // an image the size of the painting area, so `background-clip` cuts
    // them off wherever it says. The offset between the two carries the
    // difference; it is zero unless the clip and the origin disagree.
    int shiftX = x - clipX
    int shiftY = y - clipY
    // An unscaled blit is exact to the pixel and a scaled one is
    // filtered, so the tile is only scaled when it has to be -- and
    // then once, into an image every copy is blitted from, because a
    // scaled blit fades at its own edges and a row of them would show
    // the box through the seam between one tile and the next.
    img tile = null
    if scaled {
        tile = scaledTile(paddedRegionEdges(src, bgPaint.repeatX, bgPaint.repeatY),
                          srcW, srcH, iw, ih)
    }
    img layer = blankImage(clipW, clipH)
    int ty = startY
    bool moreY = true
    while moreY {
        int tx = startX
        bool moreX = true
        while moreX {
            if scaled { layer.drawImage(tile, tx + shiftX, ty + shiftY) }
            else { layer.drawImage(src, tx + shiftX, ty + shiftY) }
            if !bgPaint.repeatX { moreX = false }
            else {
                tx = tx + iw
                if tx >= w { moreX = false }
            }
        }
        if !bgPaint.repeatY { moreY = false }
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
    fillAlpha(bgFadeAlpha == 1.0 ? s.effectiveOpacity : s.effectiveOpacity * bgFadeAlpha)
    pDrawImage(layer, clipX, clipY)
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
// The hints beside them, resolved the same way: the position of the
// hint that follows each stop, or -1 where there is none. A global for
// the same reason the offsets are one (FINDINGS.md, "one value out of a
// function"), and read by gradientColorAt below.
arr[float] gradHintOffsets = []

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
    arr[float] hints = []
    for int i = 0, i < n, i++ {
        if i >= g.hintKind.length || g.hintKind[i] == GSTOP_AUTO { hints.push(0.0 - 1.0) }
        else if g.hintKind[i] == GSTOP_PERCENT { hints.push(g.hintVal[i]) }
        else { hints.push(length > 0.0 ? g.hintVal[i] / length : 0.0 - 1.0) }
    }
    gradHintOffsets = hints
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
        // An interpolation hint bends the ramp so that the colour
        // halfway between the two stops falls at the hint rather than at
        // the middle (§3.4.4): weight = P ^ (log 0.5 / log H), for P the
        // fraction of the way between the stops and H the hint's own.
        if i < gradHintOffsets.length {
            float hint = gradHintOffsets[i]
            if hint > a && hint < b && f > 0.0 {
                float hf = (hint - a) / (b - a)
                if hf > 0.0 && hf < 1.0 {
                    f = Math.pow(f, Math.log(0.5) / Math.log(hf))
                }
            }
        }
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

// ---- conic gradients (CSS Images 3 §3.4.3) ---------------------------
//
// A conic gradient gives every point the colour of its own angle about
// a centre, measured clockwise from pointing up. The stop list means a
// fraction of the turn instead of a fraction of a line, so the stop
// machinery above is shared unchanged; what differs is the geometry.
//
// It is painted as wedges, for the same reason the linear one is
// painted as bands: the canvas's own gradient fill takes only literal
// colours (FINDINGS.md, "a gradient cannot be built at run time").
//
// A wedge is not a rectangle, so it is drawn a row at a time, and the
// row's span is computed rather than searched for. A ray at angle `a`
// from the centre meets the row `ry` where
//
//     x = cx - dy * tan(a),    dy = ry - cy
//
// and only when it points towards that row at all -- rays with
// cos a > 0 reach the rows above the centre and rays with cos a < 0 the
// rows below. So one tangent per wedge edge, computed once for the
// whole box, gives every row's span by a multiply: no atan2 per pixel,
// and every rectangle covers whole pixels exactly, which is what keeps
// abutting wedges from being blended against each other into stipple.
void func paintConicGradient(x:int, y:int, w:int, h:int, g:Gradient, opacity:float) {
    if g.stops.length < 2 || w <= 0 || h <= 0 { return }
    float cxf = x.toFloat() + resolveLen(g.radialPosX, w, 0).toFloat()
    float cyf = y.toFloat() + resolveLen(g.radialPosY, h, 0).toFloat()

    // One wedge per pixel of the circumference, which is as fine as the
    // result can show, bounded so a huge box does not pay for detail
    // nobody sees and a tiny one still gets a smooth sweep.
    float dxMax = maxFloat(absFloat(cxf - x.toFloat()), absFloat(x.toFloat() + w.toFloat() - cxf))
    float dyMax = maxFloat(absFloat(cyf - y.toFloat()), absFloat(y.toFloat() + h.toFloat() - cyf))
    float radius = Math.sqrt(dxMax * dxMax + dyMax * dyMax)
    int wedges = roundPx(6.2831853071795864 * radius)
    if wedges < 24 { wedges = 24 }
    if wedges > 1440 { wedges = 1440 }

    resolveGradientStops(g, 1.0)
    arr[float] offsets = gradOffsets
    fillAlpha(opacity)

    float step = 360.0 / wedges.toFloat()
    float rad = 3.14159265358979 / 180.0
    // Where a ray at this angle crosses a row, and which rows it can
    // reach at all, are fixed for the whole box: a ray with cos a > 0
    // reaches the rows above the centre, one with cos a < 0 the rows
    // below, and one within a millionth of horizontal reaches neither.
    arr[float] tans = []
    arr[float] sins = []
    arr[int] reaches = []
    for int k = 0, k <= wedges, k++ {
        float a = (g.conicFrom + step * k.toFloat()) * rad
        float ca = Math.cos(a)
        float sa = Math.sin(a)
        sins.push(sa)
        if absFloat(ca) < 0.000001 {
            tans.push(0.0)
            reaches.push(0)
        } else {
            tans.push(sa / ca)
            reaches.push(ca > 0.0 ? 1 : 0 - 1)
        }
    }

    float big = 1000000.0
    for int k = 0, k < wedges, k++ {
        int c = gradientColorAt(g, offsets, (k.toFloat() + 0.5) / wedges.toFloat())
        if colorAlpha(c) == 0 { continue }
        applyFillColor(c)
        for int row = y, row < y + h, row++ {
            float dy = row.toFloat() + 0.5 - cyf
            int want = dy < 0.0 ? 1 : 0 - 1
            bool r0 = reaches[k] == want
            bool r1 = reaches[k + 1] == want
            // A wedge neither of whose edges points at this row does not
            // cover any of it. Getting this wrong paints the whole row,
            // which is how the first version of this came out uniformly
            // the colour of its last wedge.
            if !r0 && !r1 { continue }
            float e0 = 0.0
            float e1 = 0.0
            if r0 && r1 {
                e0 = cxf - dy * tans[k]
                e1 = cxf - dy * tans[k + 1]
            } else if r0 {
                // The wedge straddles the horizontal, so its far edge is
                // off the end of the row on the side it leans to: right
                // where the edge ray points right, left where it points
                // left.
                e0 = cxf - dy * tans[k]
                e1 = sins[k + 1] > 0.0 ? big : 0.0 - big
            } else {
                e0 = cxf - dy * tans[k + 1]
                e1 = sins[k] > 0.0 ? big : 0.0 - big
            }
            int xa = maxInt(roundPx(minFloat(e0, e1)), x)
            int xb = minInt(roundPx(maxFloat(e0, e1)), x + w)
            if xb > xa { pDrawRect(xa, row, xb - xa, 1) }
        }
    }
    fillAlpha(1.0)
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

// ---- radial gradients (CSS Images 3 §3.4.2) --------------------------
//
// The ray runs from the centre outwards, and a stop's position is a
// fraction of it exactly as it is a fraction of the line for a linear
// gradient, so the stop machinery above is shared unchanged. What
// differs is the geometry: how long the ray is, which the size keyword
// decides, and what shape its ends trace.
//
// It is painted as concentric bands for the same reason the linear one
// is painted as parallel ones -- the canvas's own gradient fill takes
// only literal colours (FINDINGS.md, "a gradient cannot be built at run
// time"). A band is drawn as one-pixel-tall horizontal runs, one per
// row, for the same reason the off-axis linear bands are: every
// rectangle then covers whole pixels, so abutting bands are not
// anti-aliased against each other into a stipple.

// The centre of a radial gradient. A percentage here is a fraction of
// the box, not of any leftover space -- `at 50% 50%` is the middle of
// the box whatever the gradient's size, which is why this is not
// resolvePositionAxis.
float func resolveGradientCenter(l:Len, extent:int, fontSize:int) {
    if l.kind == LEN_PERCENT { return extent.toFloat() * l.v / 100.0 }
    if l.kind == LEN_PX { return l.v }
    return extent.toFloat() / 2.0
}

// The ray's two radii, from the size keyword and the centre's distance
// to the sides. An ellipse takes each axis on its own; a circle takes
// one radius for both. A corner keyword is the side one scaled so the
// ellipse passes through that corner, which for equal aspect ratios is
// the side distance times the square root of two.
float radRx = 0.0
float radRy = 0.0

void func radialRadii(g:Gradient, cx:float, cy:float, x:int, y:int, w:int, h:int, fontSize:int) {
    float leftD = cx - x.toFloat()
    float rightD = (x + w).toFloat() - cx
    float topD = cy - y.toFloat()
    float bottomD = (y + h).toFloat() - cy
    float closeX = minFloat(absFloat(leftD), absFloat(rightD))
    float farX = maxFloat(absFloat(leftD), absFloat(rightD))
    float closeY = minFloat(absFloat(topD), absFloat(bottomD))
    float farY = maxFloat(absFloat(topD), absFloat(bottomD))
    float root2 = 1.41421356237309

    if g.radialExtent == RADEXT_EXPLICIT {
        radRx = lenToPx(g.radialRx, w, fontSize)
        radRy = lenToPx(g.radialRy, h, fontSize)
        return
    }
    if g.radialCircle {
        float r = 0.0
        if g.radialExtent == RADEXT_CLOSEST_SIDE { r = minFloat(closeX, closeY) }
        else if g.radialExtent == RADEXT_FARTHEST_SIDE { r = maxFloat(farX, farY) }
        else if g.radialExtent == RADEXT_CLOSEST_CORNER {
            r = Math.sqrt(closeX * closeX + closeY * closeY)
        } else {
            r = Math.sqrt(farX * farX + farY * farY)
        }
        radRx = r
        radRy = r
        return
    }
    if g.radialExtent == RADEXT_CLOSEST_SIDE { radRx = closeX  radRy = closeY }
    else if g.radialExtent == RADEXT_FARTHEST_SIDE { radRx = farX  radRy = farY }
    else if g.radialExtent == RADEXT_CLOSEST_CORNER { radRx = closeX * root2  radRy = closeY * root2 }
    else { radRx = farX * root2  radRy = farY * root2 }
}

// A length against the axis it is measured along; a percentage of that
// axis, as an explicit radius takes.
float func lenToPx(l:Len, extent:int, fontSize:int) {
    if l.kind == LEN_PERCENT { return extent.toFloat() * l.v / 100.0 }
    if l.kind == LEN_PX { return l.v }
    return 0.0
}

void func paintRadialGradient(x:int, y:int, w:int, h:int, g:Gradient, opacity:float) {
    if g.stops.length < 2 || w <= 0 || h <= 0 { return }
    float cx = x.toFloat() + resolveGradientCenter(g.radialPosX, w, 0)
    float cy = y.toFloat() + resolveGradientCenter(g.radialPosY, h, 0)
    radialRadii(g, cx, cy, x, y, w, h, 0)
    float rx = radRx
    float ry = radRy
    // An ending shape with zero height and a width of its own is not a
    // gradient line of zero length: the standard renders it as a linear
    // gradient mirrored about the centre, horizontally (CSS Images 3
    // §3.4.2.3). The bands are rectangles the height of the box, two per
    // band, one each side of the centre.
    if ry <= 0.0 && rx > 0.0 {
        resolveGradientStops(g, rx)
        arr[float] mirrored = gradOffsets
        fillAlpha(opacity)
        float reach = maxFloat(absFloat(x.toFloat() - cx), absFloat((x + w).toFloat() - cx))
        float tEnd = reach / rx
        int bands = roundPx(reach)
        if bands < 1 { bands = 1 }
        if bands > 4096 { bands = 4096 }
        for int i = 0, i < bands, i++ {
            float t0 = tEnd * i.toFloat() / bands.toFloat()
            float t1 = tEnd * (i + 1).toFloat() / bands.toFloat()
            int c = gradientColorAt(g, mirrored, (t0 + t1) / 2.0)
            if colorAlpha(c) == 0 { continue }
            applyFillColor(c)
            int ra = maxInt(roundPx(cx + t0 * rx), x)
            int rb = minInt(roundPx(cx + t1 * rx), x + w)
            if rb > ra { pDrawRect(ra, y, rb - ra, h) }
            int la = maxInt(roundPx(cx - t1 * rx), x)
            int lb = minInt(roundPx(cx - t0 * rx), x + w)
            if lb > la { pDrawRect(la, y, lb - la, h) }
        }
        fillAlpha(1.0)
        return
    }
    // Any other degenerate shape -- a zero width, or both radii zero,
    // which `closest-side` centred on an edge produces -- renders as a
    // gradient line of zero length, and that is a solid fill of the last
    // stop (CSS Images 3 §3.4.2.3, via §3.4.1).
    if rx <= 0.0 || ry <= 0.0 {
        int last = g.stops[g.stops.length - 1]
        if colorAlpha(last) == 0 { return }
        fillAlpha(opacity)
        applyFillColor(last)
        pDrawRect(x, y, w, h)
        fillAlpha(1.0)
        return
    }

    // A stop given in pixels is a distance along the ray, so the ray's
    // own length is what a percentage is measured against. The ray runs
    // to the ellipse, so it is rx long in the horizontal direction; that
    // is the length the standard resolves a length-valued stop against.
    resolveGradientStops(g, rx)
    arr[float] offsets = gradOffsets
    fillAlpha(opacity)

    // How far out the box reaches, in ray fractions: the largest
    // normalised distance to any corner. Bands beyond 1 paint the last
    // stop for a plain gradient and repeat for a repeating one, so both
    // are covered by running the bands all the way out.
    float tMax = 0.0
    for int i = 0, i < 4, i++ {
        float px = i < 2 ? x.toFloat() : (x + w).toFloat()
        float py = (i == 0 || i == 2) ? y.toFloat() : (y + h).toFloat()
        float ndx = (px - cx) / rx
        float ndy = (py - cy) / ry
        float d = Math.sqrt(ndx * ndx + ndy * ndy)
        if d > tMax { tMax = d }
    }
    if tMax <= 0.0 { return }

    // One band per pixel of the longer radius, so a band is about a
    // pixel wide where the gradient is widest.
    int steps = roundPx(maxFloat(rx, ry) * tMax)
    if steps < 1 { steps = 1 }
    if steps > 4096 { steps = 4096 }

    for int i = 0, i < steps, i++ {
        float t0 = tMax * i.toFloat() / steps.toFloat()
        float t1 = tMax * (i + 1).toFloat() / steps.toFloat()
        int c = gradientColorAt(g, offsets, (t0 + t1) / 2.0)
        if colorAlpha(c) == 0 { continue }
        applyFillColor(c)
        // On each row the band is the pair of intervals where the
        // normalised distance falls between t0 and t1: solving
        // ((px-cx)/rx)^2 + ((row-cy)/ry)^2 = t^2 for px gives a half
        // width of rx*sqrt(t^2 - ndy^2), one interval each side of the
        // centre.
        for int row = y, row < y + h, row++ {
            float ndy = (row.toFloat() + 0.5 - cy) / ry
            float sq = ndy * ndy
            float in0 = t0 * t0 - sq
            float in1 = t1 * t1 - sq
            if in1 <= 0.0 { continue }
            float half1 = rx * Math.sqrt(in1)
            float half0 = in0 > 0.0 ? rx * Math.sqrt(in0) : 0.0
            // right of the centre
            int xa = maxInt(roundPx(cx + half0), x)
            int xb = minInt(roundPx(cx + half1), x + w)
            if xb > xa { pDrawRect(xa, row, xb - xa, 1) }
            // and left of it
            int xc = maxInt(roundPx(cx - half1), x)
            int xd = minInt(roundPx(cx - half0), x + w)
            if xd > xc { pDrawRect(xc, row, xd - xc, 1) }
        }
    }
    fillAlpha(1.0)
}

// One side of a border, in its own style (Backgrounds and Borders 3
// §4.3). `horizontal` says which way the line runs: a top or bottom
// edge is `w` long and `thick` deep, a left or right edge the other way
// about, and the two differ only in which axis the pattern steps along.
//
// The standard fixes `double` exactly -- two lines and a gap, each as
// near a third of the width as the width allows -- and leaves the dash
// and dot lengths to the user agent. These follow the usual convention:
// a dash three times the border's thickness, a dot square, each
// separated by a gap of its own length, and the run is stretched so a
// whole number of them spans the edge rather than leaving a stub.
// The darker of the two shades the relief styles use. CSS2 §8.5.3 fixes
// only that the colours are "based on" the border colour and leaves the
// rest to the user agent; half brightness is the usual choice and is
// what makes a `groove` read as carved rather than as two arbitrary
// colours.
int func borderShadeDark(c:int) {
    return packColor(Math.floorDiv(colorRed(c), 2), Math.floorDiv(colorGreen(c), 2),
                     Math.floorDiv(colorBlue(c), 2), colorAlpha(c))
}

// `inset`, `outset`, `groove` and `ridge` shade an edge to suggest
// relief. `inset` darkens the top and left so the box reads as sunken
// and `outset` does the reverse; `groove` and `ridge` split each edge in
// half and shade the halves oppositely, which is what carves a line into
// the surface rather than tilting the whole box.
//
// `leading` says which end of the box this edge is: the top and the left
// take one shade, the bottom and the right the other.
void func paintBorderRelief(x:int, y:int, w:int, h:int, horizontal:bool,
                            leading:bool, style:int, base:int, opacity:float) {
    int thick = horizontal ? h : w
    bool outerDark = false
    bool innerDark = false
    if style == BORDER_INSET { outerDark = leading  innerDark = leading }
    else if style == BORDER_OUTSET { outerDark = !leading  innerDark = !leading }
    else if style == BORDER_GROOVE { outerDark = leading  innerDark = !leading }
    else { outerDark = !leading  innerDark = leading }

    int half = Math.floorDiv(thick, 2)
    if half < 1 || outerDark == innerDark {
        // one shade for the whole edge: inset and outset, and any edge
        // too thin to split
        paintFill(outerDark ? borderShadeDark(base) : base, opacity)
        pDrawRect(x, y, w, h)
        return
    }
    // The outer half is the one against the outside of the box, which is
    // the near side for a top or left edge and the far side for the
    // others.
    int outerOffset = leading ? 0 : thick - half
    int innerOffset = leading ? half : 0
    int innerThick = thick - half
    paintFill(outerDark ? borderShadeDark(base) : base, opacity)
    if horizontal { pDrawRect(x, y + outerOffset, w, half) }
    else { pDrawRect(x + outerOffset, y, half, h) }
    paintFill(innerDark ? borderShadeDark(base) : base, opacity)
    if horizontal { pDrawRect(x, y + innerOffset, w, innerThick) }
    else { pDrawRect(x + innerOffset, y, innerThick, h) }
}

void func paintBorderSide(x:int, y:int, w:int, h:int, horizontal:bool, leading:bool,
                          style:int, base:int, opacity:float) {
    if w <= 0 || h <= 0 { return }
    int thick = horizontal ? h : w
    int along = horizontal ? w : h
    if style == BORDER_GROOVE || style == BORDER_RIDGE
        || style == BORDER_INSET || style == BORDER_OUTSET {
        paintBorderRelief(x, y, w, h, horizontal, leading, style, base, opacity)
        return
    }
    paintFill(base, opacity)
    if style == BORDER_SOLID || style == BORDER_NONE {
        pDrawRect(x, y, w, h)
        return
    }
    if style == BORDER_DOUBLE {
        // A width that does not divide by three gives the extra pixels
        // to the lines rather than the gap, which keeps a 2px double
        // border visible as two 1px lines with no gap to spare.
        int line = Math.floorDiv(thick + 2, 3)
        int gap = thick - line - line
        if gap < 1 || line < 1 {
            pDrawRect(x, y, w, h)
            return
        }
        if horizontal {
            pDrawRect(x, y, w, line)
            pDrawRect(x, y + thick - line, w, line)
        } else {
            pDrawRect(x, y, line, h)
            pDrawRect(x + thick - line, y, line, h)
        }
        return
    }
    // dashed and dotted: a run of marks with an equal gap after each.
    int mark = style == BORDER_DOTTED ? thick : thick * 3
    if mark < 1 { mark = 1 }
    int period = mark + mark
    int count = Math.floorDiv(along + period - 1, period)
    if count < 1 { count = 1 }
    // stretch the period so the marks end flush with the edge
    for int i = 0, i < count, i++ {
        int start = Math.floorDiv(along * i, count)
        int end = Math.floorDiv(along * (i + 1), count)
        int len = Math.floorDiv(end - start + 1, 2)
        if len < 1 { len = 1 }
        if horizontal { pDrawRect(x + start, y, len, h) }
        else { pDrawRect(x, y + start, w, len) }
    }
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
            resolveCornerRadii(s, w, h)
            roundedRectPathEllipses(x + half, y + half, w - b.bt, h - b.bt,
                                    maxInt(radTLX - half, 1), maxInt(radTLY - half, 1),
                                    maxInt(radTRX - half, 1), maxInt(radTRY - half, 1),
                                    maxInt(radBRX - half, 1), maxInt(radBRY - half, 1),
                                    maxInt(radBLX - half, 1), maxInt(radBLY - half, 1))
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
        paintBorderSide(x, y, w, b.bt, true, true, s.borderTopStyle,
                        s.borderTopColor, s.effectiveOpacity)
    }
    if b.bb > 0 && colorIsPaintable(s.borderBottomColor) {
        paintBorderSide(x, y + h - b.bb, w, b.bb, true, false, s.borderBottomStyle,
                        s.borderBottomColor, s.effectiveOpacity)
    }
    if b.bl > 0 && colorIsPaintable(s.borderLeftColor) && !skipLeft {
        paintBorderSide(x, y, b.bl, h, false, true, s.borderLeftStyle,
                        s.borderLeftColor, s.effectiveOpacity)
    }
    if b.br > 0 && colorIsPaintable(s.borderRightColor) {
        paintBorderSide(x + w - b.br, y, b.br, h, false, false, s.borderRightStyle,
                        s.borderRightColor, s.effectiveOpacity)
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

// The rule between each pair of columns: a line centred in the gap,
// painted through the same code as a border side so every style paints
// as itself. It takes no space, so it is drawn over the gap the columns
// already left rather than pushing them apart (CSS Multi-column 1 §4).
void func paintColumnRules(b:Box) {
    Style s = b.style
    int count = usedColumnCount(s, contentWidth(b))
    if count < 2 || s.columnRuleStyle == BORDER_NONE { return }
    int gap = s.columnGap
    int colW = Math.floorDiv(contentWidth(b) - gap * (count - 1), count)
    if colW < 1 { return }
    int w = minInt(s.columnRuleWidth, maxInt(gap, 1))
    int c = colorWithOpacity(s.columnRuleColor, s.effectiveOpacity)
    int top = contentY(b)
    int h = b.h - b.pt - b.pb - b.bt - b.bb
    if h <= 0 { return }
    for int i = 1, i < count, i++ {
        int centre = contentX(b) + i * (colW + gap) - Math.floorDiv(gap, 2)
        paintBorderSide(centre - Math.floorDiv(w, 2), top, w, h, false, true,
                        s.columnRuleStyle, c, s.effectiveOpacity)
    }
    fillAlpha(1.0)
}

// Whether a cell has anything in it. A cell holding only collapsible
// whitespace is empty, and the layout has already dropped that text, so
// a cell with no child boxes and no line boxes is the question.
bool func cellIsEmpty(b:Box) {
    for int i = 0, i < b.lines.length, i++ {
        if b.lines[i].frags.length > 0 { return false }
    }
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT {
            if !textIsCollapsibleBlank(c.content) { return false }
            continue
        }
        if c.kind == BOX_ANON {
            if !cellIsEmpty(c) { return false }
            continue
        }
        return false
    }
    return true
}

// border-image (Backgrounds and Borders 3 §6): the source cut into
// nine regions by the slices, with the four corners drawn at the
// border's own size, the four edges filling the space between them, and
// the middle drawn only when `fill` asks.
//
// Each region is cut by blitting the source into a blank image at a
// negative offset, because an image destination has no source-rectangle
// `drawImage` (FINDINGS.md, finding 30) and a border image inside an
// `overflow: hidden` subtree is painting into one.
img func cutRegion(src:img, sx:int, sy:int, sw:int, sh:int) {
    if sw <= 0 || sh <= 0 { return null }
    img out = blankImage(sw, sh)
    out.drawImage(src, -sx, -sy)
    return out
}

// Where the tiles of one axis go, as a position and a length each.
// Two arrays out of a function need globals (FINDINGS.md, "one value
// out of a function"), and the caller copies them before laying out the
// other axis.
arr[int] tileAt = []
arr[int] tileLen = []

arr[int] func intsCopy(a:arr[int]) {
    arr[int] out = []
    for int i = 0, i < a.length, i++ { out.push(a[i]) }
    return out
}

// The four keywords of border-image-repeat, along one axis of one
// region (Backgrounds and Borders 3 §6.5). `tile` is the length the
// edge image has once it is scaled to the border's thickness, which is
// the size every keyword but `stretch` lays down.
void func layTiles(dstLen:int, tile:int, mode:int) {
    tileAt = []
    tileLen = []
    if dstLen <= 0 { return }
    if mode == BORDERIMG_STRETCH || tile <= 0 {
        tileAt.push(0)
        tileLen.push(dstLen)
        return
    }
    if mode == BORDERIMG_ROUND {
        // Resized so a whole number of tiles fills the area, and never
        // fewer than one: the boundaries are rounded rather than the
        // lengths, so the tiles abut exactly and add up to the area.
        int n = maxInt(roundPx(dstLen.toFloat() / tile.toFloat()), 1)
        float step = dstLen.toFloat() / n.toFloat()
        for int i = 0, i < n, i++ {
            int from = roundPx(step * i.toFloat())
            int to = roundPx(step * (i + 1).toFloat())
            tileAt.push(from)
            tileLen.push(to - from)
        }
        return
    }
    if mode == BORDERIMG_SPACE {
        // Whole tiles only, with what is left over shared out around
        // them -- a gap before the first and after the last as well as
        // between them. Where not even one tile fits, nothing is drawn.
        int n = Math.floorDiv(dstLen, tile)
        if n < 1 { return }
        float gap = (dstLen - n * tile).toFloat() / (n + 1).toFloat()
        for int i = 0, i < n, i++ {
            tileAt.push(roundPx(gap * (i + 1).toFloat()) + tile * i)
            tileLen.push(tile)
        }
        return
    }
    // repeat: whole tiles with one of them centred on the area, so the
    // two ends cut a tile each wherever the area is not a whole number
    // of them.
    int from = Math.floorDiv(dstLen - tile, 2)
    while from > 0 { from = from - tile }
    for int at = from, at < dstLen, at = at + tile {
        tileAt.push(at)
        tileLen.push(tile)
    }
}

// A region with a one pixel border around it, taken from its own edge
// or from the edge opposite.
//
// A scaled blit samples half a source pixel beyond the rectangle it
// fills, and with nothing there it fades to transparent: enlarging a
// 3px slice into a 30px border left five pixels of the page showing
// through between one tile and the next, and between the corner and
// the edge beside it. The padding gives the sampler something to
// reach, and is drawn outside the tile so none of it is seen.
//
// Which edge it copies is what the tile's neighbour will be. A border
// image's regions each stand alone, so the padding repeats the edge
// itself; a background tiled along an axis has its own opposite edge
// next to it, so on that axis the padding comes from there and the two
// tiles blend into each other exactly as one continuous tiling would.
img func paddedRegionEdges(region:img, wrapX:bool, wrapY:bool) {
    int sw = region.width
    int sh = region.height
    img out = blankImage(sw + 2, sh + 2)
    int left = wrapX ? sw - 1 : 0
    int right = wrapX ? 0 : sw - 1
    int top = wrapY ? sh - 1 : 0
    int bottom = wrapY ? 0 : sh - 1
    out.drawImage(cutRegion(region, 0, top, sw, 1), 1, 0)
    out.drawImage(cutRegion(region, 0, bottom, sw, 1), 1, sh + 1)
    out.drawImage(cutRegion(region, left, 0, 1, sh), 0, 1)
    out.drawImage(cutRegion(region, right, 0, 1, sh), sw + 1, 1)
    out.drawImage(cutRegion(region, left, top, 1, 1), 0, 0)
    out.drawImage(cutRegion(region, right, top, 1, 1), sw + 1, 0)
    out.drawImage(cutRegion(region, left, bottom, 1, 1), 0, sh + 1)
    out.drawImage(cutRegion(region, right, bottom, 1, 1), sw + 1, sh + 1)
    out.drawImage(region, 1, 1)
    return out
}

img func paddedRegion(region:img) {
    return paddedRegionEdges(region, false, false)
}

// One tile at its drawn size: the padded region scaled so that its
// border of copied edge pixels lands outside the tile, into an image
// that is exactly the tile and so cuts that border off.
img func scaledTile(padded:img, sw:int, sh:int, tw:int, th:int) {
    img tile = blankImage(tw, th)
    int padX = maxInt(roundPx(tw.toFloat() / sw.toFloat()), 1)
    int padY = maxInt(roundPx(th.toFloat() / sh.toFloat()), 1)
    tile.drawImage(padded, -padX, -padY, tw + padX + padX, th + padY + padY)
    return tile
}

// Draws one region into a box: stretched to fill it, or laid down as
// tiles of the size §6.5 scales the region to.
void func paintImageRegion(src:img, sx:int, sy:int, sw:int, sh:int,
                           dx:int, dy:int, dw:int, dh:int,
                           modeX:int, tileW:int, modeY:int, tileH:int) {
    if sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0 { return }
    img region = cutRegion(src, sx, sy, sw, sh)
    if region == null { return }
    img padded = paddedRegion(region)
    if modeX == BORDERIMG_STRETCH && modeY == BORDERIMG_STRETCH {
        pDrawImage(scaledTile(padded, sw, sh, dw, dh), dx, dy)
        return
    }
    layTiles(dw, tileW, modeX)
    arr[int] xs = intsCopy(tileAt)
    arr[int] ws = intsCopy(tileLen)
    layTiles(dh, tileH, modeY)
    arr[int] ys = intsCopy(tileAt)
    arr[int] hs = intsCopy(tileLen)
    if xs.length == 0 || ys.length == 0 { return }
    // Into a layer, because a tile can hang over either end of the area
    // and the canvas has no clip region. Every tile of one size is the
    // same image, blitted unscaled, so the tiling repeats exactly.
    img layer = blankImage(dw, dh)
    int haveW = -1
    int haveH = -1
    img tile = null
    for int j = 0, j < ys.length, j++ {
        for int i = 0, i < xs.length, i++ {
            if ws[i] != haveW || hs[j] != haveH {
                tile = scaledTile(padded, sw, sh, ws[i], hs[j])
                haveW = ws[i]
                haveH = hs[j]
            }
            layer.drawImage(tile, xs[i], ys[j])
        }
    }
    pDrawImage(layer, dx, dy)
}

// One slice, as a number of source pixels. A bare number is already
// that; a percentage is of the source's own size.
int func slicePx(l:Len, sourceSize:int) {
    if l.kind == LEN_PERCENT { return maxInt(roundPx(sourceSize.toFloat() * l.v / 100.0), 0) }
    if l.kind == LEN_PX { return maxInt(roundPx(l.v), 0) }
    return 0
}

// One region's length once it is scaled to the border's thickness:
// the region is `srcLen` long and `srcThick` thick, and the border it
// fills is `thick` thick, so the whole tile grows by the same factor in
// both directions. A tile is never narrower than a pixel, because a
// zero-length one has no whole number of copies that fills anything.
int func tileLength(srcLen:int, thick:int, srcThick:int) {
    if srcThick <= 0 || thick <= 0 { return maxInt(srcLen, 1) }
    return maxInt(roundPx(srcLen.toFloat() * thick.toFloat() / srcThick.toFloat()), 1)
}

void func paintBorderImage(b:Box) {
    Style s = b.style
    if s.borderImageUrl == '' { return }
    img src = loadedImages[s.borderImageUrl]
    if src == null { return }
    int iw = src.width
    int ih = src.height
    if iw <= 0 || ih <= 0 { return }
    int st = slicePx(s.borderImageSliceTop, ih)
    int sr = slicePx(s.borderImageSliceRight, iw)
    int sb = slicePx(s.borderImageSliceBottom, ih)
    int sl = slicePx(s.borderImageSliceLeft, iw)
    if st + sb > ih || sl + sr > iw { return }

    // The area the image is drawn into: the border box, pushed out by
    // the outset. The widths default to the border's own.
    int o = s.borderImageOutset
    int ax = b.x - o
    int ay = b.y - o
    int aw = b.w + o + o
    int ah = b.h + o + o
    int wt = s.borderImageWidthTop >= 0 ? s.borderImageWidthTop : b.bt
    int wr = s.borderImageWidthRight >= 0 ? s.borderImageWidthRight : b.br
    int wb = s.borderImageWidthBottom >= 0 ? s.borderImageWidthBottom : b.bb
    int wl = s.borderImageWidthLeft >= 0 ? s.borderImageWidthLeft : b.bl
    if aw <= 0 || ah <= 0 { return }
    // A border image wider than the box it is drawn into would have its
    // edges overlap, so the widths are cut back in proportion, which is
    // the standard's own reduction.
    if wl + wr > aw {
        int total = maxInt(wl + wr, 1)
        wl = Math.floorDiv(wl * aw, total)
        wr = Math.floorDiv(wr * aw, total)
    }
    if wt + wb > ah {
        int total = maxInt(wt + wb, 1)
        wt = Math.floorDiv(wt * ah, total)
        wb = Math.floorDiv(wb * ah, total)
    }
    int repX = s.borderImageRepeat
    int repY = s.borderImageRepeatY
    int midW = aw - wl - wr
    int midH = ah - wt - wb
    int srcMidW = iw - sl - sr
    int srcMidH = ih - st - sb

    // §6.5 scales every edge image to the thickness of the border it
    // fills -- the top edge vertically to the top border width -- and
    // scales the other dimension by the same factor. The tile a
    // repeated edge lays down is that scaled size, not the region's own:
    // a 3px slice in a 10px border tiles at 10px.
    int topTile = tileLength(srcMidW, wt, st)
    int bottomTile = tileLength(srcMidW, wb, sb)
    int leftTile = tileLength(srcMidH, wl, sl)
    int rightTile = tileLength(srcMidH, wr, sr)

    // the four corners, each at its own border size
    paintImageRegion(src, 0, 0, sl, st, ax, ay, wl, wt,
                     BORDERIMG_STRETCH, 0, BORDERIMG_STRETCH, 0)
    paintImageRegion(src, iw - sr, 0, sr, st, ax + aw - wr, ay, wr, wt,
                     BORDERIMG_STRETCH, 0, BORDERIMG_STRETCH, 0)
    paintImageRegion(src, 0, ih - sb, sl, sb, ax, ay + ah - wb, wl, wb,
                     BORDERIMG_STRETCH, 0, BORDERIMG_STRETCH, 0)
    paintImageRegion(src, iw - sr, ih - sb, sr, sb,
                     ax + aw - wr, ay + ah - wb, wr, wb,
                     BORDERIMG_STRETCH, 0, BORDERIMG_STRETCH, 0)
    // the four edges, filling what the corners leave: each tiles along
    // its own length and is scaled to its thickness across it
    paintImageRegion(src, sl, 0, srcMidW, st, ax + wl, ay, midW, wt,
                     repX, topTile, BORDERIMG_STRETCH, 0)
    paintImageRegion(src, sl, ih - sb, srcMidW, sb,
                     ax + wl, ay + ah - wb, midW, wb,
                     repX, bottomTile, BORDERIMG_STRETCH, 0)
    paintImageRegion(src, 0, st, sl, srcMidH, ax, ay + wt, wl, midH,
                     BORDERIMG_STRETCH, 0, repY, leftTile)
    paintImageRegion(src, iw - sr, st, sr, srcMidH,
                     ax + aw - wr, ay + wt, wr, midH,
                     BORDERIMG_STRETCH, 0, repY, rightTile)
    // and the middle, only when `fill` asks for it. It is scaled by the
    // top edge's factor across and the left edge's down, falling back to
    // the opposite edge's where one of them has nothing to scale by.
    if s.borderImageFill {
        int midTileW = st > 0 && wt > 0 ? tileLength(srcMidW, wt, st)
                                        : tileLength(srcMidW, wb, sb)
        int midTileH = sl > 0 && wl > 0 ? tileLength(srcMidH, wl, sl)
                                        : tileLength(srcMidH, wr, sr)
        paintImageRegion(src, sl, st, srcMidW, srcMidH,
                         ax + wl, ay + wt, midW, midH,
                         repX, midTileW, repY, midTileH)
    }
}

// An outline is drawn just outside the border box and takes no space,
// so it can overlap whatever is next to it (CSS Basic User Interface 3).
// It is a line with a style, painted through the same code as a border
// side, so every style paints as itself here too.
void func paintOutline(b:Box) {
    Style s = b.style
    int w = s.outlineWidth
    if w <= 0 || b.w <= 0 || b.h <= 0 || s.outlineStyle == BORDER_NONE { return }
    int c = colorWithOpacity(s.outlineColor, s.effectiveOpacity)
    float o = s.effectiveOpacity
    // outline-offset moves the outline away from the border box and
    // leaves the gap empty, so the outline surrounds a rectangle
    // inflated by the offset rather than the border box itself.
    int off = s.outlineOffset
    int rx = b.x - off
    int ry = b.y - off
    int rw = b.w + off + off
    int rh = b.h + off + off
    if rw <= 0 || rh <= 0 { return }
    // The relief styles shade an edge against its opposite, so each
    // side says whether it is the leading one -- top and left are.
    paintBorderSide(rx - w, ry - w, rw + w + w, w, true, true, s.outlineStyle, c, o)
    paintBorderSide(rx - w, ry + rh, rw + w + w, w, true, false, s.outlineStyle, c, o)
    paintBorderSide(rx - w, ry, w, rh, false, true, s.outlineStyle, c, o)
    paintBorderSide(rx + rw, ry, w, rh, false, false, s.outlineStyle, c, o)
    fillAlpha(1.0)
}

void func paintListMarker(b:Box) {
    Style s = b.style
    // list-style-image replaces the marker entirely, at the image's own
    // size, and falls back to the type's marker when the image could
    // not be fetched (Lists 3 §3.1).
    if s.listImageUrl != '' {
        img marker = loadedImages[s.listImageUrl]
        if marker != null {
            Line ln0 = firstLineOf(b)
            int base = ln0 != null ? ln0.baseline : contentY(b) + fontAscent(s)
            int iw = marker.width
            int ih = marker.height
            int mx = s.listInside ? contentX(b) : contentX(b) - iw - roundPx(s.fontSize.toFloat() * 0.3)
            pDrawImage(marker, mx, base - ih)
            return
        }
    }
    if s.listStyle == LIST_NONE { return }
    Line ln = firstLineOf(b)
    int baseline = ln != null ? ln.baseline : contentY(b) + fontAscent(s)
    int fs = s.fontSize
    paintFill(s.color, s.effectiveOpacity)
    int edge = contentX(b)
    // An inside marker sits in the space layout reserved for it at the
    // start of the first line; an outside one hangs to the left of the
    // content edge and takes no space at all.
    bool inside = s.listInside
    if s.listStyle != LIST_DISC && s.listStyle != LIST_CIRCLE && s.listStyle != LIST_SQUARE {
        // The counter-style engine supplies both the number and the
        // suffix that follows it, so `decimal-leading-zero` and a
        // page's own `@counter-style` reach the marker the same way the
        // built-in keywords do.
        text label = s.listStyleName != ''
            ? counterStyleLabel(s.listStyleName, b.listIndex)
              + counterStyleSuffix(s.listStyleName)
            : `${listMarkerLabel(b.listIndex, s.listStyle)}.`
        setFontFor(s)
        int w = measureTextWidth(label)
        pDrawText(label, inside ? edge : edge - w - roundPx(fs.toFloat() * 0.5), baseline)
    } else {
        int r = maxInt(roundPx(fs.toFloat() * 0.19), 2)
        int cx = inside ? edge + roundPx(fs.toFloat() * 0.4) : edge - roundPx(fs.toFloat() * 0.9)
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

// The fragment's glyphs, at an offset from where the fragment sits.
void func drawFragmentGlyphs(f:Fragment, s:Style, dx:int, dy:int) {
    if s.letterSpacing == 0 {
        pDrawText(f.content, f.x + dx, f.baseline + dy)
        return
    }
    // letter-spacing: one glyph at a time, each advanced by its
    // own width plus the spacing (drawText has no spacing itself)
    arr[text] chars = f.content.split('')
    int x = f.x + dx
    for int i = 0, i < chars.length, i++ {
        pDrawText(chars[i], x, f.baseline + dy)
        x = x + measureTextWidth(chars[i]) + s.letterSpacing
    }
}

// text-emphasis (Text Decoration 3 §8): a mark beside every character,
// over the text by default and under it when asked. The mark is a
// character of its own, so the standard's five shapes need no drawing
// code and a `<string>` value needs no special case.
void func paintEmphasisMarks(f:Fragment, s:Style) {
    if s.emphasisMark == '' { return }
    int c = s.emphasisColor == COLOR_UNSET ? s.color : s.emphasisColor
    paintFill(c, s.effectiveOpacity)
    int markW = measureTextWidth(s.emphasisMark)
    // over the ascender, or below the descender
    int y = s.emphasisUnder
        ? f.baseline + fontDescent(s) + roundPx(s.fontSize.toFloat() * 0.6)
        : f.baseline - fontAscent(s) - roundPx(s.fontSize.toFloat() * 0.1)
    arr[text] chars = f.content.split('')
    int x = f.x
    for int i = 0, i < chars.length, i++ {
        int cw = measureTextWidth(chars[i]) + s.letterSpacing
        if chars[i] != ' ' {
            pDrawText(s.emphasisMark, x + Math.floorDiv(cw - markW, 2), y)
        }
        x = x + cw
    }
    paintFill(s.color, s.effectiveOpacity)
}

// text-shadow (Text Decoration 3 §5): a copy of the text behind it,
// offset and blurred. The canvas has no blur, so as with box-shadow the
// falloff is approximated -- here by drawing the copy several times
// around the offset at a fraction of the alpha, which is the same
// accumulation the box shadows use and is honest about being an
// approximation rather than a Gaussian.
void func paintTextShadows(f:Fragment, s:Style) {
    if s.textShadows.length == 0 { return }
    // last first, so the first shadow in the list ends up on top
    for int i = s.textShadows.length - 1, i >= 0, i-- {
        Shadow sh = s.textShadows[i]
        int c = colorWithOpacity(sh.color, s.effectiveOpacity)
        if sh.blur <= 0 {
            paintFill(c, s.effectiveOpacity)
            drawFragmentGlyphs(f, s, sh.dx, sh.dy)
            paintDecorationsAt(f, s, sh.color, sh.dx, sh.dy, s.effectiveOpacity)
            continue
        }
        int r = maxInt(1, Math.floorDiv(sh.blur, 2))
        int steps = 0
        for int oy = -r, oy <= r, oy++ {
            for int ox = -r, ox <= r, ox++ { steps++ }
        }
        float a = s.effectiveOpacity / steps.toFloat()
        for int oy = -r, oy <= r, oy++ {
            for int ox = -r, ox <= r, ox++ {
                paintFill(c, a)
                drawFragmentGlyphs(f, s, sh.dx + ox, sh.dy + oy)
                paintDecorationsAt(f, s, sh.color, sh.dx + ox, sh.dy + oy, a)
            }
        }
    }
    fillAlpha(1.0)
}

void func paintTextFragment(f:Fragment) {
    Style s = f.box.style
    if s.hidden { return }
    setFontFor(s)
    paintTextShadows(f, s)
    paintFill(s.color, s.effectiveOpacity)
    drawFragmentGlyphs(f, s, 0, 0)
    paintEmphasisMarks(f, s)
    // The box's own decoration and the one propagated into it are two
    // decorations, not one: the standard draws each in the colour and
    // style of the box that asked for it, so they cannot be unioned
    // into a single set of bits and painted once.
    if s.textDecoration != DECO_NONE {
        int dc = s.decorationColor == COLOR_UNSET ? s.color : s.decorationColor
        paintDecorationLines(f, s, s.textDecoration, dc, s.decorationStyle,
                             s.decorationThickness, s.underlineOffset, 0, 0, s.effectiveOpacity)
    }
    if s.inheritedDecoration != DECO_NONE {
        int ic = s.inheritedDecoColor == COLOR_UNSET ? s.color : s.inheritedDecoColor
        paintDecorationLines(f, s, s.inheritedDecoration, ic, s.inheritedDecoStyle,
                             s.inheritedDecoThickness, s.inheritedDecoOffset, 0, 0, s.effectiveOpacity)
    }
    fillAlpha(1.0)
}

// One decoration: whichever of the three lines it names, drawn in its
// own colour and style. The line styles a border has are painted by the
// border code; `wavy` has no border counterpart and is drawn here.
void func paintDecorationLines(f:Fragment, s:Style, lines:int, c:int, style:int,
                               thicknessIn:int, offset:int, dx:int, dy:int, alpha:float) {
    int thickness = thicknessIn > 0 ? thicknessIn : maxInt(1, Math.floorDiv(s.fontSize, 16))
    int col = colorWithOpacity(c, s.effectiveOpacity)
    if decoHas(lines, DECO_UNDERLINE) {
        // text-underline-position: under drops the line below the
        // descenders instead of sitting it on the baseline.
        int under = s.underlinePosUnder ? fontDescent(s) : 1
        paintDecorationLine(f.x + dx, f.baseline + under + Math.floorDiv(thickness, 2) + offset + dy,
                            f.w, thickness, style, col, alpha)
    }
    if decoHas(lines, DECO_OVERLINE) {
        paintDecorationLine(f.x + dx, f.baseline - fontAscent(s) + dy, f.w, thickness,
                            style, col, alpha)
    }
    if decoHas(lines, DECO_LINE_THROUGH) {
        paintDecorationLine(f.x + dx, f.baseline - roundPx(s.fontSize.toFloat() * 0.3) + dy,
                            f.w, thickness, style, col, alpha)
    }
}

// Every line this fragment carries -- its own and the one propagated
// into it -- at an offset, in one colour. This is how a shadow draws
// them: the standard casts the shadow of the text decorations along
// with the text (Text Decoration 3 §5).
void func paintDecorationsAt(f:Fragment, s:Style, c:int, dx:int, dy:int, alpha:float) {
    if s.textDecoration != DECO_NONE {
        paintDecorationLines(f, s, s.textDecoration, c, s.decorationStyle,
                             s.decorationThickness, s.underlineOffset, dx, dy, alpha)
    }
    if s.inheritedDecoration != DECO_NONE {
        paintDecorationLines(f, s, s.inheritedDecoration, c, s.inheritedDecoStyle,
                             s.inheritedDecoThickness, s.inheritedDecoOffset, dx, dy, alpha)
    }
}

void func paintDecorationLine(x:int, y:int, w:int, thickness:int, style:int,
                              c:int, opacity:float) {
    if w <= 0 || thickness <= 0 { return }
    if style == DECOSTYLE_WAVY {
        paintWavyLine(x, y, w, thickness, c, opacity)
        return
    }
    int border = BORDER_SOLID
    if style == DECOSTYLE_DOUBLE { border = BORDER_DOUBLE }
    else if style == DECOSTYLE_DOTTED { border = BORDER_DOTTED }
    else if style == DECOSTYLE_DASHED { border = BORDER_DASHED }
    // `double` splits the thickness it is given into two lines and a
    // gap, so it needs three times the thickness to draw two lines of
    // it -- which is what makes a double underline read as double.
    int h = style == DECOSTYLE_DOUBLE ? thickness * 3 : thickness
    paintBorderSide(x, y, w, h, true, true, border, c, opacity)
}

// A wave, drawn as a run of short steps alternating above and below the
// line. The canvas has no curve this could follow (FINDINGS.md, "an
// image is a drawable surface with a smaller API"), and the standard
// fixes only that the line is wavy, so the amplitude is the thickness.
void func paintWavyLine(x:int, y:int, w:int, thickness:int, c:int, opacity:float) {
    paintFill(c, opacity)
    int step = maxInt(2, thickness * 2)
    int amp = maxInt(1, thickness)
    bool up = true
    for int px = x, px < x + w, px = px + step {
        int seg = minInt(step, x + w - px)
        pDrawRect(px, up ? y - amp : y + amp, seg, thickness)
        up = !up
    }
}

void func paintInlineBackground(f:Fragment) {
    Box ib = f.box
    Style s = ib.style
    if s.hidden || f.w <= 0 { return }
    // an inline fragment carries no padding or border of its own, so
    // its three background areas are all the fragment's own rectangle
    paintBackground(f.x, f.y, f.w, f.h, 0, 0, 0, 0, 0, 0, 0, 0, s)
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
// The image a box paints, which is the whole of it unless
// `object-view-box` names a rectangle: then it is that rectangle, cut
// out at its own size, with anything reaching outside the image left
// empty. The canvas cannot take a source rectangle (FINDINGS.md, "an
// image destination cannot take drawImage's source rectangle"), so the
// region is blitted into a blank image at a negative offset, which is
// what `border-image` already does.
img func viewBoxSource(b:Box) {
    if b.image == null { return null }
    if !resolveViewBox(b.style, b.imgW, b.imgH) { return b.image }
    return cutRegion(b.image, viewBoxX, viewBoxY, viewBoxW, viewBoxH)
}

void func paintFittedImage(b:Box, x:int, y:int, w:int, h:int) {
    img source = viewBoxSource(b)
    if source == null { return }
    int iw = source.width
    int ih = source.height
    if iw <= 0 || ih <= 0 {
        pDrawImageScaled(source, x, y, w, h)
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
        pDrawImageScaled(source, x + ox, y + oy, ow, oh)
        return
    }
    // The caller has already set the element's opacity for the direct
    // blit above. The layer is drawn into at full alpha and composited
    // at that opacity, so it is applied once rather than to both the
    // layer's pixels and the blit.
    img layer = blankImage(w, h)
    fillAlpha(1.0)
    layer.drawImage(source, ox, oy, ow, oh)
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
        // `fill` stretches the content to the box, which is one blit --
        // and `objectFitScale` cannot express it, since filling scales
        // the two axes by different amounts and that function answers
        // with one number. A view box only changes which pixels are
        // stretched, so it takes the same path with the region cut out.
        if b.style.objectFit == OBJECTFIT_FILL {
            img filled = viewBoxSource(b)
            if filled != null { pDrawImageScaled(filled, x, y, w, h) }
        } else { paintFittedImage(b, x, y, w, h) }
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

// The colour a control's own mark is drawn in: `accent-color` when the
// page named one, and the black this draws otherwise (CSS UI 4). The
// control chrome here is this engine's own rather than a copy of any
// browser's, so the accent colours the mark it does draw.
void func accentFill(s:Style) {
    if s.accentColor == 0 {
        fillStyle(0, 0, 0)
        return
    }
    fillStyle(colorRed(s.accentColor), colorGreen(s.accentColor), colorBlue(s.accentColor))
}

void func paintFormControl(b:Box) {
    Node n = b.node
    if n.tag != 'input' { return }
    // `appearance: none` asks for no control to be drawn (CSS UI 4).
    if !b.style.appearanceAuto { return }
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
                accentFill(b.style)
                pDrawCircle(x + r, y + r, maxInt(r - 4, 2))
            }
        } else if checked {
            accentFill(b.style)
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

// ---- clip-path ------------------------------------------------------
//
// The canvas has no clip region and no path API, so a shape is cut the
// way every other clip here is cut: the subtree is painted into an
// image, and the image is blitted back. What differs is that a shape is
// not a rectangle, so the blit goes one scanline at a time, each with
// the span the shape covers at that row (FINDINGS.md, "an image
// destination cannot take drawImage's source rectangle" and "a clip
// region on the canvas").
//
// A pixel belongs to the shape when its centre does. That is the rule a
// rasteriser without antialiasing has to use, and it is the rule the
// expected grids in tests/render/clip.f were read from Chromium under.

// Which shape clips this box: its `clip-path`, or the CSS2 `clip` that
// applies only where the box is positioned.
ClipShape func boxClipShape(b:Box) {
    if b.style.clipShape.kind != CLIPSHAPE_NONE { return b.style.clipShape }
    if b.style.position == POS_ABSOLUTE || b.style.position == POS_FIXED {
        return b.style.clipRect
    }
    ClipShape none
    none.kind = CLIPSHAPE_NONE
    return none
}

ShapeGeom func resolveClipShape(b:Box) {
    ClipShape sh = boxClipShape(b)
    boxReferenceBox(b, sh.geoBox)
    return resolveShape(sh, boxRefX, boxRefY, boxRefW, boxRefH, 0)
}

// Paints a box through its clip shape. The layer is the shape's
// bounding box, because nothing outside it survives the clip.
void func paintShaped(b:Box) {
    ShapeGeom g = resolveClipShape(b)
    int lx = g.x0
    int ly = g.y0
    int lw = g.x1 - g.x0
    int lh = g.y1 - g.y0
    if lw <= 0 || lh <= 0 { return }
    img layer = blankImage(lw, lh)
    layer.translate(0 - lx, 0 - ly)
    paintLayer = layer
    paintBoxInner(b)
    paintLayer = null
    // A rectangle is one blit; a shape is one per scanline.
    if g.kind == CLIPSHAPE_RECT {
        pDrawImage(layer, lx, ly)
        return
    }
    for int row = 0, row < lh, row++ {
        shapeSpansAt(g, ly + row)
        for int i = 0, i < shapeSpanStart.length, i++ {
            int sx = maxInt(shapeSpanStart[i], lx)
            int ex = minInt(shapeSpanEnd[i], lx + lw)
            if ex <= sx { continue }
            img piece = cutRegion(layer, sx - lx, row, ex - sx, 1)
            if piece != null { pDrawImage(piece, sx, ly + row) }
        }
    }
}

// Paints a box whose descendants are clipped: the box itself onto the
// current target, then its children into a layer the size of its
// padding box, which is blitted back. An image clips at its own bounds,
// which is the clip region the canvas does not have.
void func paintClipped(b:Box) {
    Style s = b.style
    if b.kind != BOX_ANON && !s.hidden {
        paintShadows(b.x, b.y, b.w, b.h, s)
        paintBackground(b.x, b.y, b.w, b.h, b.bl, b.bt, b.br, b.bb, b.pl, b.pt, b.pr, b.pb, s)
        paintBorders(b)
        paintInsetShadows(b.x, b.y, b.w, b.h, b.bl, b.bt, b.br, b.bb, s)
    }
    int px = b.x + b.bl
    int py = b.y + b.bt
    int pw = b.w - b.bl - b.br
    int ph = b.h - b.bt - b.bb
    if pw <= 0 || ph <= 0 { return }

    img layer = blankImage(pw, ph)
    // the layer's own transform carries the offset, so everything
    // painted into it still speaks document coordinates -- and carries
    // the box's scroll position with it, which is what moves the
    // content while the box, its background and its scrollbars stay
    // where they are.
    layer.translate(0 - px, 0 - py - boxScrollTop(b))
    paintLayer = layer
    paintLines(b)
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        paintBox(c)
    }
    paintLayer = null
    pDrawImage(layer, px, py)
    paintScrollbars(b)
}

// The scrollbars a scroll container reserved room for, drawn inside its
// padding box and over whatever is behind them (CSS Overflow 3 §3.2).
// The thumb is as long a share of the track as the box is of the
// content it scrolls, and never shorter than it can be seen at.
const int SCROLLBAR_MIN_THUMB = 12

void func paintScrollbars(b:Box) {
    if b.sbW <= 0 && b.sbH <= 0 { return }
    int px = b.x + b.bl
    int py = b.y + b.bt
    int pw = b.w - b.bl - b.br
    int ph = b.h - b.bt - b.bb
    if pw <= 0 || ph <= 0 { return }
    // Chromium's classic scrollbar, so that the pixels can be compared
    // with its own: a #fcfcfc track and a #8b8b8b thumb.
    if b.sbW > 0 {
        int trackH = ph - b.sbH
        fillAlpha(1.0)
        fillStyle(252, 252, 252)
        pDrawRect(px + pw - b.sbW, py, b.sbW, trackH)
        int visible = maxInt(ph - b.pt - b.pb - b.sbH, 1)
        // A bar with nothing to scroll is an empty track, which is what
        // Chromium draws and what says at a glance that there is
        // nothing below the fold.
        if b.scrollH > visible {
            int thumbH = maxInt(Math.floorDiv(trackH * visible, b.scrollH), SCROLLBAR_MIN_THUMB)
            if thumbH > trackH { thumbH = trackH }
            // The thumb sits as far down its own run as the content is
            // through what there is of it, so it reaches the bottom
            // exactly when the content does.
            int range = maxInt(boxScrollRange(b), 1)
            int thumbY = Math.floorDiv((trackH - thumbH) * boxScrollTop(b), range)
            fillStyle(139, 139, 139)
            pDrawRect(px + pw - b.sbW + 4, py + thumbY, b.sbW - 8, thumbH)
        }
    }
    if b.sbH > 0 {
        int trackW = pw - b.sbW
        fillAlpha(1.0)
        fillStyle(252, 252, 252)
        pDrawRect(px, py + ph - b.sbH, trackW, b.sbH)
        int visible = maxInt(pw - b.pl - b.pr - b.sbW, 1)
        if b.scrollW > visible {
            int thumbW = maxInt(Math.floorDiv(trackW * visible, b.scrollW), SCROLLBAR_MIN_THUMB)
            if thumbW > trackW { thumbW = trackW }
            fillStyle(139, 139, 139)
            pDrawRect(px, py + ph - b.sbH + 4, thumbW, b.sbH - 8)
        }
    }
    fillAlpha(1.0)
}

// A transform changes where a box and its descendants are painted and
// nothing about where they were laid out (CSS Transforms 1 §3), so it
// is a matrix around the painting of the subtree and touches no
// geometry. The question is asked once per document -- cascadeSawTransform
// -- rather than of every box.
void func paintBox(b:Box) {
    if !cascadeSawTransform || b.style.transforms.length == 0 {
        paintBoxUntransformed(b)
        return
    }
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return }
    if !boxVisible(b) { return }
    Style s = b.style
    // Every function is about the transform origin, which is the box's
    // centre unless it says otherwise. Moving the origin to (0,0),
    // transforming and moving back is what makes that so.
    // The reference box `transform-box` names: the border box unless it
    // asked for the content one (Transforms 1 §6). An origin is a
    // position within that box, so both its corner and its size move.
    int rx = b.x
    int ry = b.y
    int rw = b.w
    int rh = b.h
    if s.transformBoxContent {
        rx = contentX(b)
        ry = contentY(b)
        rw = contentWidth(b)
        rh = b.h - b.pt - b.pb - b.bt - b.bb
    }
    int ox = rx + resolveLen(s.transformOriginX, rw, Math.floorDiv(rw, 2))
    int oy = ry + resolveLen(s.transformOriginY, rh, Math.floorDiv(rh, 2))
    pSaveState()
    pTranslate(ox, oy)
    for int i = 0, i < s.transforms.length, i++ {
        Transform t = s.transforms[i]
        if t.kind == TX_TRANSLATE {
            // a percentage translate is of the box's own size
            pTranslate(resolveLen(t.x, b.w, 0), resolveLen(t.y, b.h, 0))
        } else if t.kind == TX_ROTATE {
            pRotate(t.angle)
        } else if t.kind == TX_SCALE {
            pScale(t.sx, t.sy)
        }
    }
    pTranslate(-ox, -oy)
    paintBoxUntransformed(b)
    pRestoreState()
}

void func paintBoxUntransformed(b:Box) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return }
    if !boxVisible(b) { return }
    // A clip-path (or the legacy `clip`) clips the box itself as well
    // as its contents, so everything goes into the layer -- which is
    // what separates it from `overflow`, below. The question is asked
    // once per document rather than of every box.
    if cascadeSawClip && !paintingToLayer() && boxClipShape(b).kind != CLIPSHAPE_NONE {
        paintShaped(b)
        return
    }
    paintBoxInner(b)
}

void func paintBoxInner(b:Box) {
    // `overflow: hidden` clips this box's descendants to its padding box
    // (CSS2 §11.1.1). The box itself -- its background and border -- is
    // not clipped, so it paints normally and only the inside goes to a
    // layer.
    // Paint containment clips a box's descendants to its padding box,
    // which is what `overflow: hidden` does, so it goes through the
    // same layer (Containment 1 §3.3).
    // A box whose contents are not rendered at all has nothing to clip,
    // so it never needs the layer.
    if (b.style.overflowHidden || b.style.containPaint) && !b.style.contentHidden
        && !paintingToLayer() && boxClipsAnything(b) {
        paintClipped(b)
        return
    }
    Style s = b.style
    // empty-cells: hide -- a cell with nothing in it draws neither
    // background nor border in the separated borders model (CSS2
    // 17.6.1.1). The cell still takes its space; only its own
    // decoration goes.
    if b.kind == BOX_CELL && s.emptyCellsHide && !s.borderCollapse && cellIsEmpty(b) { return }
    if b.kind != BOX_ANON && !s.hidden {
        // a shadow is cast by the border box and lies under it
        paintShadows(b.x, b.y, b.w, b.h, s)
        if b.kind == BOX_ROW {
            paintBackground(b.x, b.y, b.w, b.h, b.bl, b.bt, b.br, b.bb, b.pl, b.pt, b.pr, b.pb, s)
        } else {
            paintBackground(b.x, b.y, b.w, b.h, b.bl, b.bt, b.br, b.bb, b.pl, b.pt, b.pr, b.pb, s)
            // A border image replaces the border's own styles where it
            // is drawn, so it goes over them (Backgrounds and Borders 3
            // §6.1).
            paintBorders(b)
            paintBorderImage(b)
        }
        paintInsetShadows(b.x, b.y, b.w, b.h, b.bl, b.bt, b.br, b.bb, s)
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
    if s.columnRuleWidth > 0 && !s.hidden { paintColumnRules(b) }
    // content-visibility: hidden skips the contents entirely
    // (Containment 2 §4). The box's own background, border and outline
    // are not contents, so they are already painted above; everything
    // below this line is.
    if s.contentHidden { return }
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
    // Inside a scrolled box the content is drawn that much higher than
    // it was laid out, so a point on the screen is that much further
    // down the content. Every box that scrolls nothing answers zero
    // without looking anything up.
    int scrolled = boxScrollTop(b)
    if scrolled > 0 { y = y + scrolled }
    for int i = 0, i < b.lines.length, i++ {
        Line ln = b.lines[i]
        if y < ln.y || y >= ln.y + ln.h { continue }
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            if f.kind == FRAG_INLINE_BG { continue }
            if x >= f.x && x < f.x + f.w && y >= f.y && y < f.y + f.h {
                // pointer-events: none takes a box out of hit testing so
                // that what is behind it is found instead. Its
                // descendants are still searched, because a child may
                // ask for pointer events back.
                if f.kind == FRAG_ATOMIC {
                    Box inner = hitTest(f.box, x, y)
                    if inner != null { return inner }
                    if f.box.style.pointerEvents != PE_NONE { return f.box }
                    continue
                }
                if f.box.style.pointerEvents == PE_NONE { continue }
                return f.box
            }
        }
    }
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if x >= c.x && x < c.x + c.w && y >= c.y && y < c.y + c.h {
            Box inner = hitTest(c, x, y)
            if inner != null { return inner }
            if c.style.pointerEvents != PE_NONE { return c }
        }
    }
    return null
}

// The innermost scroll container under a point that has anything left
// to scroll in the direction asked for, or null where there is none --
// which is what hands the wheel back to the page.
Box func scrollContainerAt(b:Box, x:int, y:int, dy:int) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return null }
    int scrolled = boxScrollTop(b)
    int inner = scrolled > 0 ? y + scrolled : y
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if x >= c.x && x < c.x + c.w && inner >= c.y && inner < c.y + c.h {
            Box found = scrollContainerAt(c, x, inner, dy)
            if found != null { return found }
        }
    }
    if b.sbW <= 0 { return null }
    int range = boxScrollRange(b)
    if range <= 0 { return null }
    if dy > 0 && scrolled >= range { return null }
    if dy < 0 && scrolled <= 0 { return null }
    return b
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
