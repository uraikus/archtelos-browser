// Painting: walks the laid-out box tree and draws it on the Festina
// canvas. Backgrounds, borders (rounded through a bezier path), text
// runs at their baselines, underlines, images, list markers and form
// controls. The caller has already translated the canvas so that
// document coordinates land where they should on screen.

import ../layout/layout.f
import ../css/motion.f

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

// `radiusShrink` is in src/css/shapes.f, beside `cornerInset`.

// The `corner-shape` exponent each corner of the next path is drawn
// with, and whether any of them is not `round`. Globals rather than
// four more arguments on a function that already takes twelve
// (FINDINGS.md, "one value out of a function" is the same shape of
// problem going the other way), set by `cornerShapesOf` and left at
// `round` for every caller that does not have a shaped box.
float pathKTL = CORNER_K_ROUND
float pathKTR = CORNER_K_ROUND
float pathKBR = CORNER_K_ROUND
float pathKBL = CORNER_K_ROUND
bool pathAnyShaped = false

// How many straight segments a shaped corner is walked in. Sixteen is
// what the render suite's comparison against Chromium's own corner
// profile passes at, on a 40px radius across all six keywords; the
// error is a pixel at the steepest part of a `bevel`, which is where
// any polyline approximation is worst.
const int CORNER_SLICES = 16

const float HALF_PI = 1.5707963267948966

// A point on one corner's superellipse, `i` of `CORNER_SLICES` of the
// way round it. `cornerPA` is the distance travelled along the edge the
// corner leaves and `cornerPB` the distance from the edge it meets, so
// a caller places both without knowing which corner it is drawing. Two
// values out of a function need globals (FINDINGS.md, "one value out of
// a function").
//
// The angle, not either axis, is the parameter: at `i` of 0 the point
// is where the first straight edge ended and at `i` of CORNER_SLICES it
// is where the next begins, for every exponent. A positive exponent
// gives the convex curve `border-radius` draws, a negative one its
// concave reflection, which is what `scoop` and `notch` are.
float cornerPA = 0.0
float cornerPB = 0.0

void func cornerPointAt(ra:int, rb:int, i:int, k:float) {
    // The two ends are where the straight edges are, exactly. They are
    // not computed, because an extreme exponent magnifies the error in
    // them out of all proportion: `Math.cos` of half pi is 6e-17 rather
    // than zero, and raising that to the 1/500 a `notch` asks for gives
    // 0.93, which puts the end of the corner three pixels from the edge
    // it is supposed to meet.
    if i >= CORNER_SLICES { cornerPA = ra.toFloat()  cornerPB = rb.toFloat()  return }
    if i <= 0 { cornerPA = 0.0  cornerPB = 0.0  return }
    float th = HALF_PI * i.toFloat() / CORNER_SLICES.toFloat()
    float c = Math.cos(th)
    float sn = Math.sin(th)
    if c < 0.0 { c = 0.0 }
    if sn < 0.0 { sn = 0.0 }
    if k < 0.0 {
        float m = 0.0 - k
        cornerPA = ra.toFloat() * (1.0 - Math.pow(c, 2.0 / m))
        cornerPB = rb.toFloat() * Math.pow(sn, 2.0 / m)
        return
    }
    cornerPA = ra.toFloat() * Math.pow(sn, 2.0 / k)
    cornerPB = rb.toFloat() * (1.0 - Math.pow(c, 2.0 / k))
}


// Puts a box's four `corner-shape` exponents where the path builder
// reads them. A box whose corners are all `round` -- which is every box
// on a page that never says the property -- leaves the fast path in
// `roundedRectPathEllipses` switched on.
void func cornerShapesOf(s:Style) {
    if s.cornerShapes == 0 {
        if pathAnyShaped { cornerShapesRound() }
        return
    }
    pathKTL = cornerKAt(s.cornerShapes, 0)
    pathKTR = cornerKAt(s.cornerShapes, 1)
    pathKBR = cornerKAt(s.cornerShapes, 2)
    pathKBL = cornerKAt(s.cornerShapes, 3)
    pathAnyShaped = true
}

void func cornerShapesRound() {
    pathKTL = CORNER_K_ROUND
    pathKTR = CORNER_K_ROUND
    pathKBR = CORNER_K_ROUND
    pathKBL = CORNER_K_ROUND
    pathAnyShaped = false
}

void func resolveCornerRadii(s:Style, w:int, h:int) {
    // The shape travels with the radii, because every place that needs
    // one needs the other: one boolean on a page that never says
    // `corner-shape`, and `shadowShapeRadii` reaches it through here
    // too, so a shadow follows the same curve its box does.
    // A page that says the property leaves the globals wherever the
    // last box left them, so a later box with no shape has to put them
    // back: the shapes are painter state, and stale state is what made
    // an unshaped box come out bevelled.
    if anyCornerShape { cornerShapesOf(s) } else if pathAnyShaped { cornerShapesRound() }
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
        return
    }
    // A layer has no path API (FINDINGS.md, "an image is a drawable
    // surface with a smaller API"), so the shape is filled a row at a
    // time from the same span function the shadows ask for. The corners
    // come out where they belong and hard-edged, rather than square: a
    // `border-radius` inside an `overflow: hidden` box used to be drawn
    // as a rectangle, which is an ordinary thing for a page to ask for
    // and a plain error on the screen.
    fillRoundedOnLayer(x, y, w, h, tlx, tly, trx, trry, brx, bry, blx, bly)
}

void func pFillRounded(x:int, y:int, w:int, h:int, r:int) {
    pFillRoundedCorners(x, y, w, h, r, r, r, r)
}

// ---- CSS Filter Effects 1: the filters in force ----------------------
//
// A filter applies to the element and its descendants, and a filter
// inside a filter composes, so the indices in force are a stack: entry
// zero is the outermost. A colour is filtered by the innermost first,
// because that is the order the raster would have been produced in.
//
// Nothing here is reached on a page with no `filter`. The guard is
// written at each call site as `anyFilter && paintFilters.length > 0`,
// which short-circuits, rather than inside the fill -- a call the
// common case skips still costs the pages that never reach it
// (CLAUDE.md).
arr[int] paintFilters = []

int func filteredColor(c:int) {
    int out = c
    for int i = paintFilters.length - 1, i >= 0, i-- {
        FilterSpec spec = filterSpecOf(paintFilters[i])
        if spec == null { continue }
        for int k = 0, k < spec.kinds.length, k++ {
            out = colorFilterOne(out, spec.kinds[k], spec.amounts[k])
        }
    }
    return out
}

// The box whose filter is already on the stack, so that re-entering
// paintBox for it does not push the same filter for ever. The same
// device `position: sticky` uses.
int filteredBoxId = 0

void func paintFill(c:int, opacity:float) {
    int v = colorWithOpacity(c, opacity)
    // See "the filters in force": the guard short-circuits, so a page
    // with no `filter` on it does not make the call.
    applyFillColor(anyFilter && paintFilters.length > 0 ? filteredColor(v) : v)
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
    if !pathAnyShaped {
        curveTo(x + w - bx + kbx, y, x + w, y + by - kby, x + w, y + by)
        lineTo(x + w, y + h - cy)
        curveTo(x + w, y + h - cy + kcy, x + w - cx + kcx, y + h, x + w - cx, y + h)
        lineTo(x + dx, y + h)
        curveTo(x + dx - kdx, y + h, x, y + h - dy + kdy, x, y + h - dy)
        lineTo(x, y + ay)
        curveTo(x, y + ay - kay, x + ax - kax, y, x + ax, y)
        closePath()
        return
    }
    // A `corner-shape` other than `round` is walked rather than curved:
    // a bezier is not a superellipse and the canvas has no primitive
    // that is. A corner that IS round keeps its bezier even when the box
    // has a shaped corner elsewhere, so `round` is the same pixels
    // whatever its neighbours are -- an invariant the suite checks, and
    // one worth having structurally rather than by convergence.
    //
    // Each corner runs from where one straight edge ends to where the
    // next begins, and is walked in the angle rather than in either
    // axis: `square` and `notch` put everything they do in the last
    // thousandth of an axis parameter and would come out as a diagonal
    // across the corner, where in the angle every exponent is sampled
    // evenly along its own curve.
    if pathKTR == CORNER_K_ROUND {
        curveTo(x + w - bx + kbx, y, x + w, y + by - kby, x + w, y + by)
    } else {
        for int i = 1, i <= CORNER_SLICES, i++ {
            cornerPointAt(bx, by, i, pathKTR)
            lineTo(x + w - bx + roundPx(cornerPA), y + roundPx(by.toFloat() - cornerPB))
        }
    }
    lineTo(x + w, y + h - cy)
    if pathKBR == CORNER_K_ROUND {
        curveTo(x + w, y + h - cy + kcy, x + w - cx + kcx, y + h, x + w - cx, y + h)
    } else {
        for int i = 1, i <= CORNER_SLICES, i++ {
            cornerPointAt(cy, cx, i, pathKBR)
            lineTo(x + w - roundPx(cornerPB), y + h - cy + roundPx(cornerPA))
        }
    }
    lineTo(x + dx, y + h)
    if pathKBL == CORNER_K_ROUND {
        curveTo(x + dx - kdx, y + h, x, y + h - dy + kdy, x, y + h - dy)
    } else {
        for int i = 1, i <= CORNER_SLICES, i++ {
            cornerPointAt(dx, dy, i, pathKBL)
            lineTo(x + dx - roundPx(cornerPA), y + h - roundPx(dy.toFloat() - cornerPB))
        }
    }
    lineTo(x, y + ay)
    if pathKTL == CORNER_K_ROUND {
        curveTo(x, y + ay - kay, x + ax - kax, y, x + ax, y)
    } else {
        for int i = 1, i <= CORNER_SLICES, i++ {
            cornerPointAt(ay, ax, i, pathKTL)
            lineTo(x + roundPx(cornerPB), y + ay - roundPx(cornerPA))
        }
    }
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

// The shadow shape's eight corners, the box's own grown by the spread
// (Backgrounds and Borders 3 §6.2): a corner that is round stays round
// and grows with the shape, one that is square stays square however far
// the shape spreads. Eight values out of a function need globals
// (FINDINGS.md, "one value out of a function"), and keeping the whole of
// it out of paintShadows keeps that function the size it was for a box
// with no radius at all.
int shRadTLX = 0
int shRadTLY = 0
int shRadTRX = 0
int shRadTRY = 0
int shRadBRX = 0
int shRadBRY = 0
int shRadBLX = 0
int shRadBLY = 0

int func shadowRadius(r:int, spread:int) {
    if r <= 0 { return 0 }
    return maxInt(r + spread, 0)
}

void func shadowShapeRadii(s:Style, w:int, h:int, spread:int) {
    resolveCornerRadii(s, w, h)
    shRadTLX = shadowRadius(radTLX, spread)
    shRadTLY = shadowRadius(radTLY, spread)
    shRadTRX = shadowRadius(radTRX, spread)
    shRadTRY = shadowRadius(radTRY, spread)
    shRadBRX = shadowRadius(radBRX, spread)
    shRadBRY = shadowRadius(radBRY, spread)
    shRadBLX = shadowRadius(radBLX, spread)
    shRadBLY = shadowRadius(radBLY, spread)
}

// The box's shadows, painted beneath its own background (Backgrounds
// and Borders 3 §6). Each is the border box offset by its two lengths
// and grown by its spread, with the box's own corner radii.
//
// The canvas has no blur, so the falloff is computed rather than
// filtered -- which this shape allows, because a Gaussian blur of a
// rectangle has a closed form and one of a rounded rectangle is a sum
// over its rows of that form. See gaussIntegral and paintBlurredRect
// below.
//
// A box with no radius asks nothing of any of that and pays nothing for
// it: `borderRadius` is the cascade's own answer to whether any corner
// is round, and the whole of the shape's bookkeeping sits behind it.
//
// `inset` shadows are painted by paintInsetShadows, after the
// background rather than under it.
void func paintShadows(x:int, y:int, w:int, h:int, s:Style) {
    if s.shadows.length == 0 { return }
    bool round = s.borderRadius > 0
    for int i = s.shadows.length - 1, i >= 0, i-- {
        Shadow sh = s.shadows[i]
        if sh.inset { continue }
        if !colorIsPaintable(sh.color) { continue }
        int sx = x + sh.dx - sh.spread
        int sy = y + sh.dy - sh.spread
        int sw = w + sh.spread + sh.spread
        int sh2 = h + sh.spread + sh.spread
        if sw <= 0 || sh2 <= 0 { continue }
        if round { shadowShapeRadii(s, w, h, sh.spread) }
        if sh.blur <= 0 {
            paintFill(sh.color, s.effectiveOpacity)
            if round {
                pFillRoundedEllipses(sx, sy, sw, sh2, shRadTLX, shRadTLY,
                                     shRadTRX, shRadTRY, shRadBRX, shRadBRY,
                                     shRadBLX, shRadBLY)
            } else {
                pDrawRect(sx, sy, sw, sh2)
            }
            fillAlpha(1.0)
            continue
        }
        if !round {
            paintBlurredRect(sx, sy, sw, sh2, sh.color, s.effectiveOpacity, sh.blur,
                             0, 0, 0, 0, 0, 0, 0, 0)
            continue
        }
        paintBlurredRect(sx, sy, sw, sh2, sh.color, s.effectiveOpacity, sh.blur,
                         shRadTLX, shRadTLY, shRadTRX, shRadTRY,
                         shRadBRX, shRadBRY, shRadBLX, shRadBLY)
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

// A row an ellipse crosses is not one span: at the very top of a circle
// the edge goes as the square root of the distance from it, so taking
// the row's middle for the whole of the row makes that row too wide.
// The error lands on the axis the rows run across and not on the one
// they run along, which comes out as a circle casting a darker shadow
// above itself than beside itself -- a thing no circle does.
//
// Slicing the row divides that error, and how far it has to be divided
// is a measurement rather than an opinion. Against a reference of 64
// slices, the worst a circle is out across the shapes measured -- 40x40
// at blurs of 4, 8 and 20, 100x100 at 8, 30x30 at 2, 200x80 at 30 -- is
// 3.7 units of 255 at one slice to the row, 1.8 at four and 0.77 at
// eight. Eight is the first count that holds it under the one unit a
// painted pixel can show.
int SHADOW_SLICES = 8

// The shadow shape's horizontal span at one row, which is where a
// rounded rectangle stops being a rectangle: inside a corner's band the
// edge follows that corner's ellipse, and everywhere else it is the
// shape's own side. Two values out of a function need globals
// (FINDINGS.md, "one value out of a function").
float shadowSpanLo = 0.0
float shadowSpanHi = 0.0

// `cornerInset` is in src/css/shapes.f, because `inset()`'s `round`
// radius asks it the same question and the CSS cannot call the painter.

// The same question of a corner drawn with any `corner-shape`: the
// superellipse `|x/rx|^k + |y/ry|^k = 1` for a positive exponent, and
// its concave reflection for a negative one, which is what `scoop` and
// `notch` are. `dy` is into the band as above -- nothing at the inner
// end, the whole radius at the outer one.
//
// Every keyword is one exponent (CSS Borders 4 §5), so there is one
// curve here and not six: 2 is `round`, 1 is `bevel` -- where the
// formula collapses to `rx * t` and the corner is the straight cut it
// should be -- 4 is `squircle`, -2 is `scoop`, and the two extremes are
// `square` and `notch`. `round` keeps the square root, because it is
// the value nearly every corner has and it is inside the shadow
// painter's per-row loop.
float func cornerInsetShaped(rx:int, ry:int, dy:float, k:float) {
    if k == CORNER_K_ROUND { return cornerInset(rx, ry, dy) }
    if rx <= 0 || ry <= 0 || dy <= 0.0 { return 0.0 }
    float fry = ry.toFloat()
    float frx = rx.toFloat()
    float t = dy >= fry ? 1.0 : dy / fry
    if k < 0.0 {
        float m = 0.0 - k
        return frx * Math.pow(1.0 - Math.pow(1.0 - t, m), 1.0 / m)
    }
    return frx * (1.0 - Math.pow(1.0 - Math.pow(t, k), 1.0 / k))
}

void func shadowSpanAt(vc:float, w:int, h:int,
                       tlx:int, tly:int, trx:int, trys:int,
                       brx:int, brys:int, blx:int, blys:int) {
    shadowSpanLo = maxFloat(cornerInsetShaped(tlx, tly, tly.toFloat() - vc, pathKTL),
                            cornerInsetShaped(blx, blys, vc - (h - blys).toFloat(), pathKBL))
    shadowSpanHi = w.toFloat()
        - maxFloat(cornerInsetShaped(trx, trys, trys.toFloat() - vc, pathKTR),
                   cornerInsetShaped(brx, brys, vc - (h - brys).toFloat(), pathKBR))
}

// A rounded rectangle filled into a layer, a row at a time, from the
// span function above -- which is why it lives here rather than beside
// `pFillRoundedEllipses`: a function is hoisted in Festina and a global
// is not, and this reads `shadowSpanLo`.
void func fillRoundedOnLayer(x:int, y:int, w:int, h:int,
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
    if ax <= 0 && ay <= 0 && bx <= 0 && by <= 0
        && cx <= 0 && cy <= 0 && dx <= 0 && dy <= 0 {
        paintLayer.drawRect(x, y, w, h)
        return
    }
    for int j = 0, j < h, j++ {
        shadowSpanAt(j.toFloat() + 0.5, w, h, ax, ay, bx, by, cx, cy, dx, dy)
        int lo = roundPx(shadowSpanLo)
        int hi = roundPx(shadowSpanHi)
        if hi <= lo { continue }
        paintLayer.drawRect(x + lo, y + j, hi - lo, 1)
    }
}

// One corner of a rounded shadow, as an image carrying the blurred
// shape's alpha, so a page whose cards share a shadow builds each
// corner once and blits it four times over. (x0, y0) is the corner's
// top left in the shape's own coordinates: the top left one starts at
// (-reach, -reach), the bottom right one at (w - rxR, h - ryB).
//
// The sum is the outer integral of the blur: the value at a point is
// the sum, over the rows the shape occupies, of that row's share of the
// vertical Gaussian times the horizontal Gaussian over that row's own
// span. Both factors are worked out once per (column, row) and once per
// (line, row) rather than once per pixel, so the pixel loop is
// multiply-adds over a table.
map[img] shadowCorners = {}

img func shadowCorner(key:text, x0:int, y0:int, cw:int, ch:int,
                      w:int, h:int, sigma:float, reach:int, shade:int, own:float,
                      tlx:int, tly:int, trx:int, trys:int,
                      brx:int, brys:int, blx:int, blys:int) {
    img hit = shadowCorners[key]
    if hit != null { return hit }
    img out = blankImage(cw, ch)
    shadowCorners[key] = out
    // Only the rows within the blur's reach of the corner can reach it.
    int v0 = maxInt(y0 - reach, 0)
    int v1 = minInt(y0 + ch + reach, h)
    if v1 <= v0 { return out }

    // The shape in slices, each one a stretch of rows and the span it
    // holds. A row no ellipse crosses is the full width, and so is every
    // other such row, so a whole run of them is one slice: the vertical
    // Gaussian over a run of rows is the Gaussian over the run.
    arr[float] segT0 = []
    arr[float] segT1 = []
    arr[float] segLo = []
    arr[float] segHi = []
    int topBand = maxInt(tly, trys)
    int botBand = maxInt(brys, blys)
    int runFrom = 0 - 1
    float step = 1.0 / SHADOW_SLICES.toFloat()
    for int v = v0, v < v1, v++ {
        if v >= topBand && v + 1 <= h - botBand {
            if runFrom < 0 { runFrom = v }
            continue
        }
        if runFrom >= 0 {
            shadowSpanAt((runFrom + v).toFloat() / 2.0, w, h,
                         tlx, tly, trx, trys, brx, brys, blx, blys)
            segT0.push(runFrom.toFloat())
            segT1.push(v.toFloat())
            segLo.push(shadowSpanLo)
            segHi.push(shadowSpanHi)
            runFrom = 0 - 1
        }
        for int k = 0, k < SHADOW_SLICES, k++ {
            float t0 = v.toFloat() + step * k.toFloat()
            float t1 = t0 + step
            shadowSpanAt((t0 + t1) / 2.0, w, h,
                         tlx, tly, trx, trys, brx, brys, blx, blys)
            if shadowSpanLo >= shadowSpanHi { continue }
            segT0.push(t0)
            segT1.push(t1)
            segLo.push(shadowSpanLo)
            segHi.push(shadowSpanHi)
        }
    }
    if runFrom >= 0 {
        shadowSpanAt((runFrom + v1).toFloat() / 2.0, w, h,
                     tlx, tly, trx, trys, brx, brys, blx, blys)
        segT0.push(runFrom.toFloat())
        segT1.push(v1.toFloat())
        segLo.push(shadowSpanLo)
        segHi.push(shadowSpanHi)
    }
    int nv = segT0.length
    if nv == 0 { return out }

    arr[float] hf = []
    for int i = 0, i < cw, i++ {
        float px = (x0 + i).toFloat() + 0.5
        for int k = 0, k < nv, k++ {
            hf.push(blurAxis(px, segLo[k], segHi[k], sigma))
        }
    }
    // A slice three standard deviations from a line has 0.0013 of its
    // weight left there, so each line remembers the first and last slice
    // that can still reach it and the pixel loop stops at those.
    arr[float] vw = []
    arr[int] kLo = []
    arr[int] kHi = []
    for int j = 0, j < ch, j++ {
        float py = (y0 + j).toFloat() + 0.5
        int first = nv
        int last = 0 - 1
        for int k = 0, k < nv, k++ {
            float a = blurAxis(py, segT0[k], segT1[k], sigma)
            vw.push(a)
            if a > 0.000001 {
                if k < first { first = k }
                last = k
            }
        }
        kLo.push(first)
        kHi.push(last)
    }

    fillStyle(colorRed(shade), colorGreen(shade), colorBlue(shade))
    for int j = 0, j < ch, j++ {
        int vb = j * nv
        int k0 = kLo[j]
        int k1 = kHi[j]
        for int i = 0, i < cw, i++ {
            int hb = i * nv
            float a = 0.0
            for int k = k0, k <= k1, k++ { a = a + hf[hb + k] * vw[vb + k] }
            a = a * own
            if a <= 0.002 { continue }
            fillAlpha(a > 1.0 ? 1.0 : a)
            out.drawPixel(i, j)
        }
    }
    fillAlpha(1.0)
    return out
}

// The correction a blurred `inset` shadow's rounded corner needs.
//
// Its two strip passes leave `1 - fx*fy`, the complement of the
// *square* hole's blurred coverage. What it wants is the complement of
// the **rounded** hole's, and a rounded hole lies inside the square
// one, so its coverage is the smaller and the shadow belongs darker at
// a corner than the strips make it -- by as much as 59 units of 255 on
// the fixture todo.md records.
//
// Painting over accumulates rather than adds: `a` then `d` gives
// `a + d(1 - a)`. Setting that equal to `1 - round`, with `a` the
// `1 - fx*fy` already there, solves to
//
//     d = 1 - round / (fx*fy)
//
// which is between zero and one precisely because the rounded coverage
// never exceeds the square one. So the correction is paintable, and
// that is what makes this possible at all: the canvas has no operator
// that subtracts (FINDINGS.md, and CSS Compositing is blocked on it).
//
// The sum is the same outer integral `shadowCorner` takes, over the
// hole's own shape; what differs is the pixel written at the end.
map[img] insetCornerFixes = {}

img func insetCornerFix(key:text, x0:int, y0:int, cw:int, ch:int,
                        w:int, h:int, sigma:float, reach:int, shade:int,
                        tlx:int, tly:int, trx:int, trys:int,
                        brx:int, brys:int, blx:int, blys:int) {
    img hit = insetCornerFixes[key]
    if hit != null { return hit }
    img out = blankImage(cw, ch)
    insetCornerFixes[key] = out
    int v0 = maxInt(y0 - reach, 0)
    int v1 = minInt(y0 + ch + reach, h)
    if v1 <= v0 { return out }

    arr[float] segT0 = []
    arr[float] segT1 = []
    arr[float] segLo = []
    arr[float] segHi = []
    int topBand = maxInt(tly, trys)
    int botBand = maxInt(brys, blys)
    int runFrom = 0 - 1
    float step = 1.0 / SHADOW_SLICES.toFloat()
    for int v = v0, v < v1, v++ {
        if v >= topBand && v + 1 <= h - botBand {
            if runFrom < 0 { runFrom = v }
            continue
        }
        if runFrom >= 0 {
            shadowSpanAt((runFrom + v).toFloat() / 2.0, w, h,
                         tlx, tly, trx, trys, brx, brys, blx, blys)
            segT0.push(runFrom.toFloat())
            segT1.push(v.toFloat())
            segLo.push(shadowSpanLo)
            segHi.push(shadowSpanHi)
            runFrom = 0 - 1
        }
        for int k = 0, k < SHADOW_SLICES, k++ {
            float t0 = v.toFloat() + step * k.toFloat()
            float t1 = t0 + step
            shadowSpanAt((t0 + t1) / 2.0, w, h,
                         tlx, tly, trx, trys, brx, brys, blx, blys)
            if shadowSpanLo >= shadowSpanHi { continue }
            segT0.push(t0)
            segT1.push(t1)
            segLo.push(shadowSpanLo)
            segHi.push(shadowSpanHi)
        }
    }
    if runFrom >= 0 {
        shadowSpanAt((runFrom + v1).toFloat() / 2.0, w, h,
                     tlx, tly, trx, trys, brx, brys, blx, blys)
        segT0.push(runFrom.toFloat())
        segT1.push(v1.toFloat())
        segLo.push(shadowSpanLo)
        segHi.push(shadowSpanHi)
    }
    int nv = segT0.length
    if nv == 0 { return out }

    float fw = w.toFloat()
    float fh = h.toFloat()
    arr[float] hf = []
    arr[float] sqx = []
    for int i = 0, i < cw, i++ {
        float px = (x0 + i).toFloat() + 0.5
        sqx.push(blurAxis(px, 0.0, fw, sigma))
        for int k = 0, k < nv, k++ {
            hf.push(blurAxis(px, segLo[k], segHi[k], sigma))
        }
    }
    arr[float] vw = []
    arr[float] sqy = []
    arr[int] kLo = []
    arr[int] kHi = []
    for int j = 0, j < ch, j++ {
        float py = (y0 + j).toFloat() + 0.5
        sqy.push(blurAxis(py, 0.0, fh, sigma))
        int first = nv
        int last = 0 - 1
        for int k = 0, k < nv, k++ {
            float a = blurAxis(py, segT0[k], segT1[k], sigma)
            vw.push(a)
            if a > 0.000001 {
                if k < first { first = k }
                last = k
            }
        }
        kLo.push(first)
        kHi.push(last)
    }

    fillStyle(colorRed(shade), colorGreen(shade), colorBlue(shade))
    for int j = 0, j < ch, j++ {
        int vb = j * nv
        int k0 = kLo[j]
        int k1 = kHi[j]
        float vy = sqy[j]
        for int i = 0, i < cw, i++ {
            // Where the square hole barely covers the pixel there is
            // nothing to correct: the strips already left it opaque.
            float sq = sqx[i] * vy
            if sq <= 0.0005 { continue }
            int hb = i * nv
            float a = 0.0
            for int k = k0, k <= k1, k++ { a = a + hf[hb + k] * vw[vb + k] }
            float d = 1.0 - a / sq
            if d <= 0.002 { continue }
            fillAlpha(d > 1.0 ? 1.0 : d)
            out.drawPixel(i, j)
        }
    }
    fillAlpha(1.0)
    return out
}

// One axis's profile as a one pixel tall image, so a whole row of a
// blurred square corner can be drawn with one blit rather than a pixel
// at a time: `drawImage` multiplies the image's own alpha by
// `fillAlpha`, and a product of the two axes is exactly what a separable
// blur is. The key is everything the answer depends on, so a page whose
// boxes share a shadow builds each ramp once.
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

// A shadow shape blurred by a Gaussian of standard deviation half the
// blur radius, which is what Backgrounds and Borders 3 §7.1 asks a
// shadow's blur to be. The eight radii are the shape's own corners,
// already grown by the spread.
//
// The blur is separable, so the shape divides into nine parts: four
// corners where both axes are still changing, four edges where only one
// is, and the middle where neither is. Only the corners are worked out a
// pixel at a time, and only once per distinct shadow; an edge is one
// row or column per pixel of the reach, and the middle is a single fill.
//
// A rounded shape does not separate, because its horizontal span changes
// with the row, so its corners are the sum over rows that shadowCorner
// works out. Everything past a corner's band is the full width again, so
// widening the bands to hold the radius as well as the reach leaves the
// edges and the middle exactly the separable thing they were. With every
// radius zero the sum telescopes back into the product of the two axes,
// which is why the two paths have to agree where a radius cannot reach
// -- and why the suite asks them to, at the middle of an edge.
void func paintBlurredRect(x:int, y:int, w:int, h:int, c:int, opacity:float, blur:int,
                           tlx:int, tly:int, trx:int, trys:int,
                           brx:int, brys:int, blx:int, blys:int) {
    if w <= 0 || h <= 0 { return }
    float sigma = blur.toFloat() / 2.0
    // Three standard deviations out the Gaussian has 0.0013 of its
    // weight left, which is a third of what a pixel can show.
    int reach = maxInt(roundPx(sigma * 3.0), 1)
    bool rounded = tlx + tly + trx + trys + brx + brys + blx + blys > 0
    int rx = minInt(reach, Math.floorDiv(w, 2))
    int ry = minInt(reach, Math.floorDiv(h, 2))
    int rxR = rx
    int ryB = ry
    if rounded {
        // The bands have to hold the radius as well as the reach, or a
        // row whose span the ellipse has narrowed would land in the part
        // of the shape the separable path calls full width. Where the
        // shape is too small to hold two such bands the corners meet in
        // the middle instead, which is the whole of a circle's shadow.
        int wantX = reach + maxInt(maxInt(tlx, trx), maxInt(brx, blx))
        int wantY = reach + maxInt(maxInt(tly, trys), maxInt(brys, blys))
        if wantX + wantX <= w { rx = wantX  rxR = wantX }
        else { rx = Math.floorDiv(w, 2)  rxR = w - rx }
        if wantY + wantY <= h { ry = wantY  ryB = wantY }
        else { ry = Math.floorDiv(h, 2)  ryB = h - ry }
    }
    int midW = w - rx - rxR
    int midH = h - ry - ryB
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
    // One pass per axis, not one per side: the two sides of an axis are
    // the same distance from their own edge and so share the Gaussian,
    // and computing it twice costs a millisecond on a page of two
    // hundred shadows. Where the two bands differ -- which only a shape
    // too small to hold two of them does -- the shorter side simply
    // stops drawing first.
    int rowsT = reach + ry
    int rowsB = reach + ryB
    int colsL = reach + rx
    int colsR = reach + rxR
    if midW > 0 {
        for int j = 0, j < maxInt(rowsT, rowsB), j++ {
            float fy = blurAxis((j - reach).toFloat() + 0.5, 0.0, fh, sigma)
            float a = fxMid * fy * own
            if a <= 0.002 { continue }
            fillAlpha(a > 1.0 ? 1.0 : a)
            if j < rowsT { pDrawRect(x + rx, y - reach + j, midW, 1) }
            if j < rowsB { pDrawRect(x + rx, y + h + reach - 1 - j, midW, 1) }
        }
    }
    if midH > 0 {
        for int i = 0, i < maxInt(colsL, colsR), i++ {
            float fx = blurAxis((i - reach).toFloat() + 0.5, 0.0, fw, sigma)
            float a = fx * fyMid * own
            if a <= 0.002 { continue }
            fillAlpha(a > 1.0 ? 1.0 : a)
            if i < colsL { pDrawRect(x - reach + i, y + ry, 1, midH) }
            if i < colsR { pDrawRect(x + w + reach - 1 - i, y + ry, 1, midH) }
        }
    }
    fillAlpha(1.0)

    // The four corners, where both axes are still changing.
    int cw = colsL
    int cwR = colsR
    int ch = rowsT
    int chB = rowsB
    if cw <= 0 || ch <= 0 { return }
    if rounded {
        text ck = `${blur}|${shade}|${w}|${h}|${tlx},${tly},${trx},${trys}`
            + `|${brx},${brys},${blx},${blys}|${rx},${rxR},${ry},${ryB}|${reach}`
        img cTL = shadowCorner(ck + '|tl', 0 - reach, 0 - reach, cw, ch,
                               w, h, sigma, reach, shade, own,
                               tlx, tly, trx, trys, brx, brys, blx, blys)
        img cTR = shadowCorner(ck + '|tr', w - rxR, 0 - reach, cwR, ch,
                               w, h, sigma, reach, shade, own,
                               tlx, tly, trx, trys, brx, brys, blx, blys)
        img cBL = shadowCorner(ck + '|bl', 0 - reach, h - ryB, cw, chB,
                               w, h, sigma, reach, shade, own,
                               tlx, tly, trx, trys, brx, brys, blx, blys)
        img cBR = shadowCorner(ck + '|br', w - rxR, h - ryB, cwR, chB,
                               w, h, sigma, reach, shade, own,
                               tlx, tly, trx, trys, brx, brys, blx, blys)
        pDrawImage(cTL, x - reach, y - reach)
        pDrawImage(cTR, x + w - rxR, y - reach)
        pDrawImage(cBL, x - reach, y + h - ryB)
        pDrawImage(cBR, x + w - rxR, y + h - ryB)
        return
    }

    // A square corner separates, so each of its rows is the horizontal
    // profile at that row's own share of the vertical one, which is one
    // blit of the ramp at that alpha: the whole shadow costs a row of
    // work per pixel of the reach rather than a pixel of work per pixel
    // of it.
    text rampKey = `${blur}|${shade}|${cw}|${w}`
    img rampLeft = shadowRamp(rampKey + '|l', cw, (0 - reach).toFloat(),
                              fw, sigma, shade)
    img rampRight = shadowRamp(rampKey + '|r', cw, fw - rx.toFloat(),
                               fw, sigma, shade)
    for int j = 0, j < ch, j++ {
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

// The padding box's own corners: the border box's, less the border on
// each side and floored at zero, which is the inner curve (Backgrounds
// and Borders 3 §5.2). Eight values out of a function need globals
// (FINDINGS.md, "one value out of a function").
int inRadTLX = 0
int inRadTLY = 0
int inRadTRX = 0
int inRadTRY = 0
int inRadBRX = 0
int inRadBRY = 0
int inRadBLX = 0
int inRadBLY = 0

int func innerRadius(r:int, b:int) {
    if r <= 0 { return 0 }
    return maxInt(r - b, 0)
}

// Answers whether any of them is round, so a box whose borders have
// eaten every corner takes the straight path below rather than the
// per-row one.
bool func insetShapeRadii(s:Style, w:int, h:int, bl:int, bt:int, br:int, bb:int) {
    resolveCornerRadii(s, w, h)
    inRadTLX = innerRadius(radTLX, bl)
    inRadTLY = innerRadius(radTLY, bt)
    inRadTRX = innerRadius(radTRX, br)
    inRadTRY = innerRadius(radTRY, bt)
    inRadBRX = innerRadius(radBRX, br)
    inRadBRY = innerRadius(radBRY, bb)
    inRadBLX = innerRadius(radBLX, bl)
    inRadBLY = innerRadius(radBLY, bb)
    return inRadTLX > 0 || inRadTLY > 0 || inRadTRX > 0 || inRadTRY > 0
        || inRadBRX > 0 || inRadBRY > 0 || inRadBLX > 0 || inRadBLY > 0
}

// The span of the inner curve at one row of the padding box, as
// absolute x. Two values out of a function need globals.
int insetRowLo = 0
int insetRowHi = 0

void func insetRowSpan(px:int, py:int, pw:int, ph:int, row:int) {
    shadowSpanAt((row - py).toFloat() + 0.5, pw, ph,
                 inRadTLX, inRadTLY, inRadTRX, inRadTRY,
                 inRadBRX, inRadBRY, inRadBLX, inRadBLY)
    insetRowLo = px + roundPx(shadowSpanLo)
    insetRowHi = px + roundPx(shadowSpanHi)
}

// The band between two rounded rectangles, a row at a time. An inset
// shadow is the padding box minus the hole the offset and the spread
// leave, and where the box is round both of those follow a curve, so
// each row is two runs rather than the four strips a square box needs.
// The hole's radii are the padding box's less the spread, which is what
// Chromium does: 40 less a 12 spread puts the hole's edge where a 40
// would not (todo.md).
void func fillRoundedFrame(px:int, py:int, pw:int, ph:int,
                           hx:int, hy:int, hw:int, hh:int, spread:int) {
    int htlx = innerRadius(inRadTLX, spread)
    int htly = innerRadius(inRadTLY, spread)
    int htrx = innerRadius(inRadTRX, spread)
    int htry = innerRadius(inRadTRY, spread)
    int hbrx = innerRadius(inRadBRX, spread)
    int hbry = innerRadius(inRadBRY, spread)
    int hblx = innerRadius(inRadBLX, spread)
    int hbly = innerRadius(inRadBLY, spread)
    for int j = 0, j < ph, j++ {
        int row = py + j
        insetRowSpan(px, py, pw, ph, row)
        int lo = insetRowLo
        int hi = insetRowHi
        if hi <= lo { continue }
        int cutLo = hi
        int cutHi = hi
        if hw > 0 && hh > 0 && row >= hy && row < hy + hh {
            shadowSpanAt((row - hy).toFloat() + 0.5, hw, hh,
                         htlx, htly, htrx, htry, hbrx, hbry, hblx, hbly)
            cutLo = clampInt(hx + roundPx(shadowSpanLo), lo, hi)
            cutHi = clampInt(hx + roundPx(shadowSpanHi), lo, hi)
        }
        if cutLo > lo { pDrawRect(lo, row, cutLo - lo, 1) }
        if hi > cutHi { pDrawRect(cutHi, row, hi - cutHi, 1) }
    }
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
    // The inner curve, worked out once for the box rather than once per
    // shadow -- and not at all until an `inset` shadow is actually
    // reached, because most boxes that carry a shadow carry an outer
    // one and would otherwise pay for a curve nothing here draws.
    bool round = false
    bool askedRound = false
    for int i = s.shadows.length - 1, i >= 0, i-- {
        Shadow sh = s.shadows[i]
        if !sh.inset { continue }
        if !colorIsPaintable(sh.color) { continue }
        if !askedRound {
            askedRound = true
            round = s.borderRadius > 0 && insetShapeRadii(s, w, h, bl, bt, br, bb)
        }
        int ix = px + sh.dx + sh.spread
        int iy = py + sh.dy + sh.spread
        int iw = pw - sh.spread - sh.spread
        int ih = ph - sh.spread - sh.spread
        if sh.blur > 0 {
            paintInsetBlur(px, py, pw, ph, ix, iy, iw, ih,
                           sh.color, s.effectiveOpacity, sh.blur, round,
                           sh.spread)
            continue
        }
        paintFill(sh.color, s.effectiveOpacity)
        if round { fillRoundedFrame(px, py, pw, ph, ix, iy, iw, ih, sh.spread) }
        else { fillFrame(px, py, pw, ph, ix, iy, iw, ih) }
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
                         c:int, opacity:float, blur:int, round:bool,
                         spread:int) {
    if pw <= 0 || ph <= 0 { return }
    int shade = colorWithOpacity(c, opacity)
    if !colorIsPaintable(shade) { return }
    float own = colorAlpha(shade).toFloat() / 255.0
    float sigma = blur.toFloat() / 2.0
    float fw = maxInt(hw, 0).toFloat()
    float fh = maxInt(hh, 0).toFloat()
    // A round box needs the layer whatever its alpha, because the
    // strips are square and the padding box is not: the layer is what
    // the inner curve cuts them back to, one scanline at a time, the
    // way a `clip-path` is cut. The band's own falloff is still
    // measured from the square hole -- todo.md has what the curved one
    // would take.
    img layer = round || own < 0.999 ? blankImage(pw, ph) : null
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
    // The corners, where the rounded hole and the square one part
    // company. Everything above this is the square answer; each corner
    // is one blit that turns it into the round one.
    if round && layer != null {
        // The strip passes above leave `fillAlpha` wherever their last
        // row put it, and a blit carries it. A corner that has to be
        // BUILT puts it back itself, so only a corner served from the
        // cache would be scaled by it -- which makes the first painting
        // of a shadow differ from every later one.
        fillAlpha(1.0)
        int htlx = innerRadius(inRadTLX, spread)
        int htly = innerRadius(inRadTLY, spread)
        int htrx = innerRadius(inRadTRX, spread)
        int htry = innerRadius(inRadTRY, spread)
        int hbrx = innerRadius(inRadBRX, spread)
        int hbry = innerRadius(inRadBRY, spread)
        int hblx = innerRadius(inRadBLX, spread)
        int hbly = innerRadius(inRadBLY, spread)
        int reach = maxInt(roundPx(sigma * 3.0), 1)
        // Half the hole either way, so two corners' bands can never
        // overlap and correct the same pixel twice.
        int halfW = Math.floorDiv(hw + reach + reach + 1, 2)
        int halfH = Math.floorDiv(hh + reach + reach + 1, 2)
        int colsL = minInt(maxInt(htlx, hblx) + reach, halfW)
        int colsR = minInt(maxInt(htrx, hbrx) + reach, halfW)
        int rowsT = minInt(maxInt(htly, htry) + reach, halfH)
        int rowsB = minInt(maxInt(hbry, hbly) + reach, halfH)
        text ck = `${blur}|${shade}|${hw}|${hh}|${htlx},${htly},${htrx},${htry}`
            + `|${hbrx},${hbry},${hblx},${hbly}|${colsL},${colsR},${rowsT},${rowsB}`
            + `|${reach}`
        int ox = hx - px
        int oy = hy - py
        if colsL > 0 && rowsT > 0 && (htlx > 0 || htly > 0) {
            layer.drawImage(insetCornerFix(ck + '|tl', 0 - reach, 0 - reach,
                                           colsL, rowsT, hw, hh, sigma, reach, shade,
                                           htlx, htly, htrx, htry,
                                           hbrx, hbry, hblx, hbly),
                            ox - reach, oy - reach)
        }
        if colsR > 0 && rowsT > 0 && (htrx > 0 || htry > 0) {
            layer.drawImage(insetCornerFix(ck + '|tr', hw - colsR + reach, 0 - reach,
                                           colsR, rowsT, hw, hh, sigma, reach, shade,
                                           htlx, htly, htrx, htry,
                                           hbrx, hbry, hblx, hbly),
                            ox + hw - colsR + reach, oy - reach)
        }
        if colsL > 0 && rowsB > 0 && (hblx > 0 || hbly > 0) {
            layer.drawImage(insetCornerFix(ck + '|bl', 0 - reach, hh - rowsB + reach,
                                           colsL, rowsB, hw, hh, sigma, reach, shade,
                                           htlx, htly, htrx, htry,
                                           hbrx, hbry, hblx, hbly),
                            ox - reach, oy + hh - rowsB + reach)
        }
        if colsR > 0 && rowsB > 0 && (hbrx > 0 || hbry > 0) {
            layer.drawImage(insetCornerFix(ck + '|br', hw - colsR + reach, hh - rowsB + reach,
                                           colsR, rowsB, hw, hh, sigma, reach, shade,
                                           htlx, htly, htrx, htry,
                                           hbrx, hbry, hblx, hbly),
                            ox + hw - colsR + reach, oy + hh - rowsB + reach)
        }
    }
    if layer != null {
        fillAlpha(own)
        if !round {
            pDrawImage(layer, px, py)
        } else {
            for int j = 0, j < ph, j++ {
                int row = py + j
                insetRowSpan(px, py, pw, ph, row)
                int lo = insetRowLo
                int hi = insetRowHi
                if hi <= lo { continue }
                img piece = cutRegion(layer, lo - px, j, hi - lo, 1)
                if piece != null { pDrawImage(piece, lo, row) }
            }
        }
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

// The curve of the painting area the current layer is clipped to
// (Backgrounds and Borders 3 Sec 3.5). A box with no `border-radius`
// leaves `bgClipRound` false and its image is blitted back whole, so a
// page of square boxes pays one field read per layer painted.
bool bgClipRound = false
int bgClipRTLX = 0
int bgClipRTLY = 0
int bgClipRTRX = 0
int bgClipRTRY = 0
int bgClipRBRX = 0
int bgClipRBRY = 0
int bgClipRBLX = 0
int bgClipRBLY = 0

// The eight radii of the area `clip` names, and whether any of them
// curves. The border box keeps its own; the padding and content boxes
// reduce it by what lies outside them, which is the rule the colour
// applies too -- `paintBackground` works the same two cases out inline,
// and the render suite requires the two to land on the same pixel.
bool func backgroundClipRadii(clip:int, s:Style, w:int, h:int,
                              bl:int, bt:int, br:int, bb:int,
                              pl:int, pt:int, pr:int, pb:int) {
    if s.borderRadius <= 0 { return false }
    if clip == BGCLIP_BORDER {
        resolveCornerRadii(s, w, h)
        bgClipRTLX = radTLX  bgClipRTLY = radTLY
        bgClipRTRX = radTRX  bgClipRTRY = radTRY
        bgClipRBRX = radBRX  bgClipRBRY = radBRY
        bgClipRBLX = radBLX  bgClipRBLY = radBLY
        return radTLX > 0 || radTLY > 0 || radTRX > 0 || radTRY > 0
            || radBRX > 0 || radBRY > 0 || radBLX > 0 || radBLY > 0
    }
    int dl = bl
    int dt = bt
    int dr = br
    int db = bb
    if clip == BGCLIP_CONTENT {
        dl = bl + pl
        dt = bt + pt
        dr = br + pr
        db = bb + pb
    }
    if !insetShapeRadii(s, w, h, dl, dt, dr, db) { return false }
    bgClipRTLX = inRadTLX  bgClipRTLY = inRadTLY
    bgClipRTRX = inRadTRX  bgClipRTRY = inRadTRY
    bgClipRBRX = inRadBRX  bgClipRBRY = inRadBRY
    bgClipRBLX = inRadBLX  bgClipRBLY = inRadBLY
    return true
}

// Blits a layer back cut to that curve, a row at a time, because the
// canvas has no clip region (FINDINGS.md, "an image is a drawable
// surface with a smaller API"). The span function is the one the
// shadows and the clipped colour ask for, so a background image and a
// background colour cannot disagree about where the corner is.
void func pDrawImageRounded(layer:img, x:int, y:int, w:int, h:int) {
    int capX = Math.floorDiv(w, 2)
    int capY = Math.floorDiv(h, 2)
    int ax = minInt(bgClipRTLX, capX)
    int ay = minInt(bgClipRTLY, capY)
    int bx = minInt(bgClipRTRX, capX)
    int by = minInt(bgClipRTRY, capY)
    int cx = minInt(bgClipRBRX, capX)
    int cy = minInt(bgClipRBRY, capY)
    int dx = minInt(bgClipRBLX, capX)
    int dy = minInt(bgClipRBLY, capY)
    // The rows a corner does not reach span the whole width, and they
    // are most of a box: a 6px radius on a 200px card leaves twelve
    // rows curved and 188 straight. Those go back as ONE region rather
    // than 188. It is worth two of the nine milliseconds the cut cost
    // before it and no pixel, and no more than that, because the price
    // is the copying rather than the number of regions: a blit has no
    // source rectangle here, so the box's pixels go through twice
    // whatever shape they are cut into. benchmarks.md has the reading.
    int runFrom = 0 - 1
    for int j = 0, j < h, j++ {
        shadowSpanAt(j.toFloat() + 0.5, w, h, ax, ay, bx, by, cx, cy, dx, dy)
        int lo = roundPx(shadowSpanLo)
        int hi = roundPx(shadowSpanHi)
        if lo <= 0 && hi >= w {
            if runFrom < 0 { runFrom = j }
            continue
        }
        if runFrom >= 0 {
            img band = cutRegion(layer, 0, runFrom, w, j - runFrom)
            if band != null { pDrawImage(band, x, y + runFrom) }
            runFrom = 0 - 1
        }
        if hi <= lo { continue }
        img piece = cutRegion(layer, lo, j, hi - lo, 1)
        if piece != null { pDrawImage(piece, x + lo, y + j) }
    }
    if runFrom >= 0 {
        img band = cutRegion(layer, 0, runFrom, w, h - runFrom)
        if band != null { pDrawImage(band, x, y + runFrom) }
    }
}

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
    // The painting area curves when the box does, and the image is cut
    // to it exactly as the colour under it is. A box with no radius
    // stops at the field read.
    bgClipRound = backgroundClipRadii(bgPaint.clip, s, w, h,
                                      bl, bt, br, bb, pl, pt, pr, pb)
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
        if s.borderRadius <= 0 {
            pDrawRect(clipX, clipY, clipW, clipH)
        } else if colourClip == BGCLIP_BORDER {
            // A percentage radius is of the border box, so the border
            // box's own curve needs no reduction.
            resolveCornerRadii(s, w, h)
            pFillRoundedEllipses(clipX, clipY, clipW, clipH,
                                 radTLX, radTLY, radTRX, radTRY,
                                 radBRX, radBRY, radBLX, radBLY)
        } else {
            // The padding edge's curvature is the border box's less the
            // border on each side, and the content edge's is that less
            // the padding as well (§5.2). Keeping the border box's
            // curve here cuts more away than the box does and leaves
            // the page showing through between the border and the
            // background: on an 80x80 box with a 20px border and a
            // 40px radius it put the background's edge at 48 on row 22
            // where Chromium puts it at 31.
            int dl = bl
            int dt = bt
            int dr = br
            int db = bb
            if colourClip == BGCLIP_CONTENT {
                dl = bl + pl
                dt = bt + pt
                dr = br + pr
                db = bb + pb
            }
            if insetShapeRadii(s, w, h, dl, dt, dr, db) {
                pFillRoundedEllipses(clipX, clipY, clipW, clipH,
                                     inRadTLX, inRadTLY, inRadTRX, inRadTRY,
                                     inRadBRX, inRadBRY, inRadBLX, inRadBLY)
            } else {
                pDrawRect(clipX, clipY, clipW, clipH)
            }
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
    if !bgClipRound && origX == clipX && origY == clipY
        && origW == clipW && origH == clipH {
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
    if bgClipRound { pDrawImageRounded(layer, clipX, clipY, clipW, clipH) }
    else { pDrawImage(layer, clipX, clipY) }
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
    if bgClipRound { pDrawImageRounded(layer, clipX, clipY, clipW, clipH) }
    else { pDrawImage(layer, clipX, clipY) }
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
        applyFillColor(anyFilter && paintFilters.length > 0 ? filteredColor(c) : c)
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
        applyFillColor(anyFilter && paintFilters.length > 0 ? filteredColor(c) : c)
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
            applyFillColor(anyFilter && paintFilters.length > 0 ? filteredColor(c) : c)
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
        applyFillColor(anyFilter && paintFilters.length > 0 ? filteredColor(last) : last)
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
        applyFillColor(anyFilter && paintFilters.length > 0 ? filteredColor(c) : c)
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

// A box is worth painting when it meets the window. Both culls are
// widened by the furthest any inline box on the document reaches
// outside its line, because that ink belongs to the box and is not in
// its rectangle; on a document with no padded or bordered inline the
// number is zero and the test is the plain one.
bool func boxVisible(b:Box) {
    return b.y + b.h + inlineInkOverhang >= paintTop
        && b.y - inlineInkOverhang <= paintBottom
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
    // The marker is drawn in its ::marker style where there is one, so
    // the colour, the font size and the disc's radius all follow from
    // one lookup rather than from three (layout.f).
    Style s = markerStyleOf(b)
    // A `content` on ::marker replaces the label the counter would give.
    text declared = markerContentOf(b)
    if declared != null {
        if declared == '' { return }
        Line dln = firstLineOf(b)
        int dbase = dln != null ? dln.baseline : contentY(b) + fontAscent(s)
        paintFill(s.color, s.effectiveOpacity)
        setFontFor(s)
        int dw = measureTextWidth(declared)
        pDrawText(declared, s.listInside ? contentX(b)
                                         : contentX(b) - dw - roundPx(s.fontSize.toFloat() * 0.5),
                  dbase)
        return
    }
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
// Synthesised small caps, drawn in the same segments `measureSmallCaps`
// measured. The two walk the run through one pair of functions on
// purpose: a segment drawn where the measurer did not put one leaves
// the ink somewhere the layout reserved no room for.
void func drawSmallCaps(f:Fragment, s:Style, caps:int, dx:int, dy:int) {
    int small = smallCapsSize(s)
    ascii a = f.content.toAscii()
    int x = f.x + dx
    int i = 0
    while i < a.length {
        int j = smallCapsRunAt(caps, f.content, i)
        bool isSmall = smallCapsAt(caps, f.content, i)
        if isSmall { setFontAt(s, small) } else { setFontFor(s) }
        text seg = isSmall ? asciiUpper(a.slice(i, j)).toText() : a.slice(i, j).toText()
        if s.letterSpacing == 0 {
            pDrawText(seg, x, f.baseline + dy)
            x = x + measureTextWidth(seg)
        } else {
            arr[text] chars = seg.split('')
            for int k = 0, k < chars.length, k++ {
                pDrawText(chars[k], x, f.baseline + dy)
                x = x + measureTextWidth(chars[k]) + s.letterSpacing
            }
        }
        i = j
    }
    // The canvas is left at a size that is not this style's, so the
    // next thing to draw would believe the font was already right.
    setFontFor(s)
}

void func drawFragmentGlyphs(f:Fragment, s:Style, dx:int, dy:int) {
    int caps = fontCapsOf(s)
    if caps != CAPS_NORMAL {
        drawSmallCaps(f, s, caps, dx, dy)
        return
    }
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

// One line's worth of an inline box. The top and bottom edges are on
// every fragment; the opening side is on the fragment that begins the
// inline and the closing side on the one that ends it, so a fragment
// in the middle of a broken inline has neither (CSS2 8.4). A margin
// takes no paint, so the fragment's rectangle is cut back by it on
// whichever sides the fragment carries.
void func paintInlineBackground(f:Fragment) {
    Box ib = f.box
    Style s = ib.style
    if s.hidden || f.w <= 0 { return }
    bool opens = fragOpens(f)
    bool closes = fragCloses(f)
    int lead = opens ? ib.ml : 0
    int x = f.x + lead
    int w = f.w - lead - (closes ? ib.mr : 0)
    if w <= 0 { return }
    int lw = opens ? ib.bl : 0
    int rw = closes ? ib.br : 0
    paintBackground(x, f.y, w, f.h, lw, ib.bt, rw, ib.bb,
                    opens ? ib.pl : 0, ib.pt, closes ? ib.pr : 0, ib.pb, s)
    if s.borderStyle == BORDER_NONE { return }
    if ib.bt > 0 && colorIsPaintable(s.borderTopColor) {
        paintBorderSide(x, f.y, w, ib.bt, true, true, s.borderTopStyle,
                        s.borderTopColor, s.effectiveOpacity)
    }
    if ib.bb > 0 && colorIsPaintable(s.borderBottomColor) {
        paintBorderSide(x, f.y + f.h - ib.bb, w, ib.bb, true, false,
                        s.borderBottomStyle, s.borderBottomColor, s.effectiveOpacity)
    }
    if lw > 0 && colorIsPaintable(s.borderLeftColor) {
        paintBorderSide(x, f.y, lw, f.h, false, true, s.borderLeftStyle,
                        s.borderLeftColor, s.effectiveOpacity)
    }
    if rw > 0 && colorIsPaintable(s.borderRightColor) {
        paintBorderSide(x + w - rw, f.y, rw, f.h, false, false,
                        s.borderRightStyle, s.borderRightColor, s.effectiveOpacity)
    }
    fillAlpha(1.0)
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
        if ln.y + ln.h + inlineInkOverhang < paintTop
            || ln.y - inlineInkOverhang > paintBottom { continue }
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
    // A rectangle is one blit; a shape is one per scanline. A rectangle
    // that `inset()` gave a `round` radius is not a rectangle for this
    // purpose -- its corners come off -- so it takes the scanline path,
    // and every square one still takes the blit.
    if g.kind == CLIPSHAPE_RECT && g.cornerRX.length == 0 {
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
    // `overflow-clip-margin` moves that edge outward, and only for
    // `overflow: clip` -- a `hidden` box ignores it, which is what
    // Chromium does (todo.md records the measurement). A page that
    // never declares it pays one bool test here.
    if anyClipMargin && (s.overflowX == OVERFLOW_CLIP || s.overflowY == OVERFLOW_CLIP) {
        int packed = clipMarginPacked(s)
        if packed >= 0 {
            int mpx = Math.floorDiv(packed, 8)
            int mbox = packed % 8
            // Where the named box is, before the length pushes it out.
            int cx = px
            int cy = py
            int cw = pw
            int ch = ph
            if mbox == GEOBOX_CONTENT {
                cx = contentX(b)
                cy = contentY(b)
                cw = contentWidth(b)
                ch = b.h - b.pt - b.pb - b.bt - b.bb
            } else if mbox == GEOBOX_BORDER {
                cx = b.x
                cy = b.y
                cw = b.w
                ch = b.h
            } else if mbox == GEOBOX_MARGIN {
                cx = b.x - b.ml
                cy = b.y - b.mt
                cw = b.w + b.ml + b.mr
                ch = b.h + b.mt + b.mb
            }
            px = cx - mpx
            py = cy - mpx
            pw = cw + mpx + mpx
            ph = ch + mpx + mpx
        }
    }
    if pw <= 0 || ph <= 0 { return }

    img layer = blankImage(pw, ph)
    // the layer's own transform carries the offset, so everything
    // painted into it still speaks document coordinates -- and carries
    // the box's scroll position with it, which is what moves the
    // content while the box, its background and its scrollbars stay
    // where they are.
    layer.translate(0 - px - boxScrollLeft(b), 0 - py - boxScrollTop(b))
    paintLayer = layer
    // The layer holds this box's contents, which is §9.9's steps 3, 4
    // and 5 and everything positioned after them -- the same three
    // walks the document gets, over this subtree.
    paintContents(b, false)
    paintLayer = null
    pDrawImage(layer, px, py)
    paintScrollbars(b)
    // Its own outline goes on after the blit, outside the layer it
    // would otherwise have been clipped out of.
    if docHasOutline { paintOutlineFor(b) }
}

// The scrollbars a scroll container reserved room for, drawn inside its
// padding box and over whatever is behind them (CSS Overflow 3 §3.2).
// The thumb is as long a share of the track as the box is of the
// content it scrolls, and never shorter than it can be seen at.

// The two colours a scrollbar is drawn in: `scrollbar-color`'s pair
// where a stylesheet gave one, and the browser's own otherwise (CSS
// Scrollbars 1 §2). Two values out of a function need globals
// (FINDINGS.md, "one value out of a function").
int sbTrackR = 252
int sbTrackG = 252
int sbTrackB = 252
int sbThumbR = 139
int sbThumbG = 139
int sbThumbB = 139

void func scrollbarColors(s:Style) {
    // Chromium's classic scrollbar, so that the pixels can be compared
    // with its own: a #fcfcfc track and a #8b8b8b thumb.
    sbTrackR = 252  sbTrackG = 252  sbTrackB = 252
    sbThumbR = 139  sbThumbG = 139  sbThumbB = 139
    if s.scrollbarThumb == 0 { return }
    sbThumbR = colorRed(s.scrollbarThumb)
    sbThumbG = colorGreen(s.scrollbarThumb)
    sbThumbB = colorBlue(s.scrollbarThumb)
    sbTrackR = colorRed(s.scrollbarTrack)
    sbTrackG = colorGreen(s.scrollbarTrack)
    sbTrackB = colorBlue(s.scrollbarTrack)
}

void func paintScrollbars(b:Box) {
    if b.sbW <= 0 && b.sbH <= 0 { return }
    scrollbarColors(b.style)
    int px = b.x + b.bl
    int py = b.y + b.bt
    int pw = b.w - b.bl - b.br
    int ph = b.h - b.bt - b.bb
    if pw <= 0 || ph <= 0 { return }
    if b.sbW > 0 {
        fillAlpha(1.0)
        fillStyle(sbTrackR, sbTrackG, sbTrackB)
        pDrawRect(px + pw - b.sbW, py, b.sbW, scrollTrackHeight(b))
        // The thumb is drawn from the same four functions the pointer is
        // tested against, so what it looks like and what can be taken
        // hold of are one rectangle (layout.f).
        if scrollThumbShown(b) {
            fillStyle(sbThumbR, sbThumbG, sbThumbB)
            pDrawRect(scrollThumbLeft(b), scrollThumbTop(b),
                      scrollThumbWidth(b), scrollThumbHeight(b))
        }
    }
    if b.sbH > 0 {
        fillAlpha(1.0)
        fillStyle(sbTrackR, sbTrackG, sbTrackB)
        pDrawRect(px, scrollHTrackTop(b), scrollHTrackWidth(b), b.sbH)
        if scrollHThumbShown(b) {
            fillStyle(sbThumbR, sbThumbG, sbThumbB)
            pDrawRect(scrollHThumbLeft(b), scrollHThumbTop(b),
                      scrollHThumbWidth(b), scrollHThumbHeight(b))
        }
    }
    fillAlpha(1.0)
}

// A transform changes where a box and its descendants are painted and
// nothing about where they were laid out (CSS Transforms 1 §3), so it
// is a matrix around the painting of the subtree and touches no
// geometry. The question is asked once per document -- cascadeSawTransform
// -- rather than of every box.
// An anchored box `position-visibility: no-overflow` hid is laid out
// like any other and simply not painted. The page-level flag is the one
// test a document with no such box pays.
bool func anchorHides(b:Box) {
    return anyAnchorHidden && b.node != null && anchorHiddenIds[`${b.node.id}`] != null
}

// CSS Motion Path 1: the box is painted at a point on its own path
// rather than where it was laid out. The whole effect is one
// translation and one rotation:
//
//     painted top-left = laid-out top-left + P - offset-anchor
//
// with the turn taken about P itself. The path's percentages and a
// ray's length want the containing block; the painter carries the
// parent box rather than the containing block, so that is what they
// resolve against, which is the same rectangle whenever the parent is
// the containing block and is recorded where it is not (todo.md).
bool func boxHasOffset(b:Box) {
    return anyOffsetPath && b.style != null
        && motionInfoOf(motionIndexOf(b.style)).pathKind != MPATH_NONE
}

// Leaves the offset's translation and turn on the canvas state. The
// caller has saved it.
void func applyBoxOffset(b:Box) {
    MotionInfo mi = motionInfoOf(motionIndexOf(b.style))
    Box up = parentBox(b)
    int bw = up == null ? b.w : contentWidth(up)
    int bh = up == null ? b.h : up.h - up.pt - up.pb - up.bt - up.bb
    int ex = up == null ? 0 : b.x - contentX(up)
    int ey = up == null ? 0 : b.y - contentY(up)
    motionBuild(mi, ex, ey, bw, bh)
    motionAt(motionDistance(mi))
    // `offset-anchor: auto` is the transform origin, not the box's
    // centre. The two coincide until a `transform-origin` says
    // otherwise, and then they are 20 pixels apart: a box with
    // `transform-origin: 0 0` moves the whole of `P`, where one with
    // the default moves `P` less half its size.
    int ax = resolveLen(b.style.transformOriginX, b.w, Math.floorDiv(b.w, 2))
    int ay = resolveLen(b.style.transformOriginY, b.h, Math.floorDiv(b.h, 2))
    if !mi.anchorAuto {
        ax = resolveLen(mi.anchorX, b.w, 0)
        ay = resolveLen(mi.anchorY, b.h, 0)
    }
    int px = roundPx(motionX)
    int py = roundPx(motionY)
    pTranslate(px - ax, py - ay)
    float turn = motionRotation(mi)
    if turn != 0.0 {
        // The pivot is the anchor point where the box was laid out: the
        // translation above carries it to P, so turning about it there
        // is turning about P.
        pTranslate(b.x + ax, b.y + ay)
        pRotate(turn)
        pTranslate(0 - (b.x + ax), 0 - (b.y + ay))
    }
}

// ---- position: sticky (CSS Positioned Layout 3 §3.5) ------------------
//
// A sticky box keeps the place the flow gave it and is drawn somewhere
// else: it is shifted so that it stays inside the scrollport, and no
// further than its own containing block. Nothing about that shift
// survives a scroll, which is why it is the painter's and not layout's
// -- layout runs once per document and this changes on every wheel
// event.
//
// The shift is worked out from `paintScrollY` and `paintViewHeight`,
// which `paintPage` sets for `background-attachment: fixed` to undo,
// and the rule is the one measured against Chromium in todo.md: a
// `top` inset can only push the box down, a `bottom` inset can only
// pull it up, and the total is clamped to the two distances the box
// can travel before it leaves its containing block.
//
// Reached only through `anySticky`, so a document that never said the
// word pays one boolean per box painted rather than these lookups.
int func stickyOffsetY(b:Box) {
    Style s = b.style
    if s == null { return 0 }
    // The containing block is the parent's content box -- measured with
    // 30px of padding and 30px of border on the parent, which separates
    // that rectangle from its padding box and its border box. It is
    // both what a percentage inset is of and what the shift is clamped
    // to.
    Box up = parentBox(b)
    int cbTop = up == null ? b.y : contentY(up)
    int cbHeight = up == null ? b.h : up.h - up.pt - up.pb - up.bt - up.bb
    int dy = 0
    if !lenIsAuto(s.top) {
        int want = paintScrollY + resolveLen(s.top, cbHeight, 0)
        if want > b.y { dy = want - b.y }
    }
    if !lenIsAuto(s.bottom) {
        int limit = paintScrollY + paintViewHeight - resolveLen(s.bottom, cbHeight, 0)
        if b.y + b.h + dy > limit { dy = limit - b.y - b.h }
    }
    if dy == 0 || up == null { return dy }
    int low = cbTop - b.y
    int high = cbTop + cbHeight - b.y - b.h
    if dy < low { dy = low }
    if dy > high { dy = high }
    return dy
}

// Set to the box `paintSticky` is re-entering `paintBox` for, so its
// shift goes on once and the box then takes the ordinary path -- which
// is what lets a sticky box also carry a transform or an offset path
// without either of them being written out twice here.
int stickyBoxId = 0

void func paintSticky(b:Box) {
    int dy = stickyOffsetY(b)
    if dy == 0 {
        int plain = stickyBoxId
        stickyBoxId = b.id
        paintBox(b)
        stickyBoxId = plain
        return
    }
    pSaveState()
    pTranslate(0, dy)
    // The cull is in document coordinates and this subtree is now drawn
    // `dy` from where it was laid out, so the window moves with it --
    // otherwise a box stuck at the top of the screen is culled for
    // being far above it.
    int savedTop = paintTop
    int savedBottom = paintBottom
    paintTop = paintTop - dy
    paintBottom = paintBottom - dy
    int saved = stickyBoxId
    stickyBoxId = b.id
    paintBox(b)
    stickyBoxId = saved
    paintTop = savedTop
    paintBottom = savedBottom
    pRestoreState()
}

// ---- CSS Masking 1: a mask layer -------------------------------------
//
// A mask is per-pixel alpha, and this engine cannot read a pixel back
// (FINDINGS.md, finding 35). It does not need to. `drawImage` honours
// `fillAlpha` -- measured -- and the clip machinery already paints a
// subtree into a layer and blits it back in pieces. A mask is that loop
// with an alpha per piece instead of a span per row.
//
// The alpha is computed rather than sampled: this engine builds the
// gradient's colours itself, so it knows every alpha in one without
// reading a pixel. Only a linear gradient is painted; a `url()` mask
// would need the bitmap's own alpha, which is the block proper.
//
// These describe the mask in force, set up once per masked box, because
// a Festina function returns one value (FINDINGS.md).
Gradient maskGrad
arr[float] maskOffsets = []
int maskMode = 0
int maskTileX = 0
int maskTileY = 0
float maskTileW = 0.0
float maskTileH = 0.0
bool maskRepX = false
bool maskRepY = false
float maskDirXv = 0.0
float maskDirYv = 1.0
float maskLenV = 0.0
float maskX0v = 0.0
float maskY0v = 0.0
int maskedBoxId = 0
// A radial or conic mask: the centre and, for a radial, the two
// resolved radii. `radialRadii` and `resolveGradientCenter` already
// compute both for the background painter, so neither had to be lifted
// out of anything.
int maskKind = 0
float maskCxv = 0.0
float maskCyv = 0.0
float maskRxv = 0.0
float maskRyv = 0.0
float maskFromDeg = 0.0

const int MASKSHAPE_LINEAR = 0
const int MASKSHAPE_RADIAL = 1
const int MASKSHAPE_CONIC = 2

// CSS Masking 1 §7.1's luminanceToAlpha, in sRGB, which is what
// Chromium's answer for a white-to-black gradient under
// `mask-mode: luminance` matches (todo.md).
float func maskLuminance(c:int) {
    return (0.2125 * colorRed(c).toFloat()
        + 0.7154 * colorGreen(c).toFloat()
        + 0.0721 * colorBlue(c).toFloat()) / 255.0
}

// The mask's alpha at one document pixel, 0 to 255. Outside the tile of
// a mask that does not repeat on that axis the answer is ZERO, not full
// -- the semantic most easily got backwards, and measured.
int func maskAlphaAt(px:int, py:int) {
    float lx = (px - maskTileX).toFloat() + 0.5
    float ly = (py - maskTileY).toFloat() + 0.5
    if maskRepX {
        lx = lx - Math.floor(lx / maskTileW) * maskTileW
    } else if lx < 0.0 || lx >= maskTileW { return 0 }
    if maskRepY {
        ly = ly - Math.floor(ly / maskTileH) * maskTileH
    } else if ly < 0.0 || ly >= maskTileH { return 0 }
    float t = 0.0
    if maskKind == MASKSHAPE_RADIAL {
        // The ellipse's own coordinates: a point is at parameter 1 on
        // the ending shape itself, whatever its two radii are.
        if maskRxv <= 0.0 || maskRyv <= 0.0 { return 0 }
        float ex = (lx - maskCxv) / maskRxv
        float ey = (ly - maskCyv) / maskRyv
        t = Math.sqrt(ex * ex + ey * ey)
    } else if maskKind == MASKSHAPE_CONIC {
        // Clockwise from pointing up, which is `conicFrom`'s own
        // convention in the background painter.
        float deg = motionDegOf(lx - maskCxv, ly - maskCyv) + 90.0 - maskFromDeg
        deg = deg - Math.floor(deg / 360.0) * 360.0
        t = deg / 360.0
    } else {
        t = ((lx - maskX0v) * maskDirXv + (ly - maskY0v) * maskDirYv) / maskLenV
    }
    if t < 0.0 { t = 0.0 }
    if t > 1.0 { t = 1.0 }
    int c = gradientColorAt(maskGrad, maskOffsets, t)
    int a = colorAlpha(c)
    if maskMode == MASKMODE_LUMINANCE {
        return roundPx(a.toFloat() * maskLuminance(c))
    }
    return a
}

// One axis of the tile. `auto` on a gradient is the positioning area,
// because a gradient has no intrinsic size of its own.
int func maskTileSide(kind:int, l:Len, area:int) {
    if kind != BGSIZE_EXPLICIT { return area }
    if l.kind == LEN_PERCENT { return roundPx(area.toFloat() * l.v / 100.0) }
    if l.kind == LEN_PX { return roundPx(l.v) }
    return area
}

void func paintMasked(b:Box) {
    MaskSpec spec = maskSpecOf(b.style.maskIdx)
    if spec == null { return }
    BgLayer ml = spec.layer
    // The clip box is what the layer covers, so `mask-clip` is done by
    // not painting outside it at all.
    int mcx = b.x
    int mcy = b.y
    int mcw = b.w
    int mch = b.h
    if ml.clip == BGCLIP_PADDING || ml.clip == BGCLIP_CONTENT {
        mcx = mcx + b.bl
        mcy = mcy + b.bt
        mcw = mcw - b.bl - b.br
        mch = mch - b.bt - b.bb
    }
    if ml.clip == BGCLIP_CONTENT {
        mcx = mcx + b.pl
        mcy = mcy + b.pt
        mcw = mcw - b.pl - b.pr
        mch = mch - b.pt - b.pb
    }
    if mcw <= 0 || mch <= 0 { return }
    // The positioning area `mask-origin` names. Its initial value is the
    // BORDER box, where `background-origin`'s is the padding box --
    // measured against Chromium, not assumed.
    int mox = b.x
    int moy = b.y
    int mow = b.w
    int moh = b.h
    if ml.origin == BGORIGIN_PADDING || ml.origin == BGORIGIN_CONTENT {
        mox = mox + b.bl
        moy = moy + b.bt
        mow = mow - b.bl - b.br
        moh = moh - b.bt - b.bb
    }
    if ml.origin == BGORIGIN_CONTENT {
        mox = mox + b.pl
        moy = moy + b.pt
        mow = mow - b.pl - b.pr
        moh = moh - b.pt - b.pb
    }
    if mow <= 0 || moh <= 0 { return }
    int mtw = maskTileSide(ml.sizeKind, ml.sizeW, mow)
    int mth = maskTileSide(ml.sizeKind, ml.sizeH, moh)
    if mtw <= 0 || mth <= 0 { return }
    maskTileX = mox + resolvePositionAxis(ml.posX, mow - mtw, b.style.fontSize)
    maskTileY = moy + resolvePositionAxis(ml.posY, moh - mth, b.style.fontSize)
    maskTileW = mtw.toFloat()
    maskTileH = mth.toFloat()
    maskRepX = ml.repeatX
    maskRepY = ml.repeatY
    maskGrad = ml.image
    maskMode = spec.mode
    // A radial or conic mask parameterises the tile differently, and
    // each is one expression over what the background painter's own
    // helpers already resolve.
    if ml.image.radial || ml.image.conic {
        maskKind = ml.image.radial ? MASKSHAPE_RADIAL : MASKSHAPE_CONIC
        maskCxv = resolveGradientCenter(ml.image.radialPosX, mtw, b.style.fontSize)
        maskCyv = resolveGradientCenter(ml.image.radialPosY, mth, b.style.fontSize)
        maskFromDeg = ml.image.conicFrom
        if ml.image.radial {
            radialRadii(ml.image, maskCxv, maskCyv, 0, 0, mtw, mth, b.style.fontSize)
            maskRxv = radRx
            maskRyv = radRy
            if maskRxv <= 0.0 || maskRyv <= 0.0 { return }
            resolveGradientStops(ml.image, maskRxv)
        } else {
            resolveGradientStops(ml.image, 1.0)
        }
        maskOffsets = gradOffsets
        maskGrad = ml.image
        maskBlit(b, mcx, mcy, mcw, mch)
        return
    }
    maskKind = MASKSHAPE_LINEAR
    // The gradient line inside one tile: the same construction
    // `paintLinearGradient` makes over a box.
    gradientDirection(ml.image.angle)
    float mHalfW = maskTileW / 2.0
    float mHalfH = maskTileH / 2.0
    float mHalf = absFloat(mHalfW * gradDirX) + absFloat(mHalfH * gradDirY)
    if mHalf <= 0.0 { return }
    maskDirXv = gradDirX
    maskDirYv = gradDirY
    maskLenV = mHalf + mHalf
    maskX0v = mHalfW - gradDirX * mHalf
    maskY0v = mHalfH - gradDirY * mHalf
    resolveGradientStops(ml.image, maskLenV)
    maskOffsets = gradOffsets
    maskBlit(b, mcx, mcy, mcw, mch)
}

// The subtree into one layer, and back in runs of one alpha. Shared by
// every mask shape, because only the alpha function differs between
// them.
void func maskBlit(b:Box, mcx:int, mcy:int, mcw:int, mch:int) {
    int maskWas = maskedBoxId
    maskedBoxId = b.id
    img maskPrev = paintLayer
    img maskLayer = blankImage(mcw, mch)
    maskLayer.translate(0 - mcx, 0 - mcy)
    paintLayer = maskLayer
    paintBox(b)
    paintLayer = maskPrev
    maskedBoxId = maskWas

    // Back in runs of one alpha. A vertical gradient gives one run a
    // row; a horizontal one gives as many runs as it has distinct
    // alphas, which is what a band decomposition would have cost.
    for int mrow = 0, mrow < mch, mrow++ {
        int my = mcy + mrow
        int runFrom = 0
        int runA = maskAlphaAt(mcx, my)
        for int mi = 1, mi <= mcw, mi++ {
            int ma = mi < mcw ? maskAlphaAt(mcx + mi, my) : 0 - 1
            if ma == runA { continue }
            if runA > 0 {
                // `cutRegion` copies with `drawImage`, which honours
                // `fillAlpha` -- so the alpha has to be back at one
                // before the cut and reset after the blit, or each run
                // is faded by the run before it. A uniform half-alpha
                // mask came out at a quarter, which is what the
                // agreement against `opacity: 0.5` caught.
                img piece = cutRegion(maskLayer, runFrom, mrow, mi - runFrom, 1)
                if piece != null {
                    fillAlpha(runA.toFloat() / 255.0)
                    pDrawImage(piece, mcx + runFrom, my)
                    fillAlpha(1.0)
                }
            }
            runFrom = mi
            runA = ma
        }
    }
    fillAlpha(1.0)
}

void func paintFiltered(b:Box) {
    int was = filteredBoxId
    filteredBoxId = b.id
    paintFilters.push(b.style.filterIdx)
    paintBox(b)
    paintFilters.pop()
    filteredBoxId = was
}

void func paintBox(b:Box) {
    if anyAnchorHidden && anchorHides(b) { return }
    // The mask goes outside the filter: a filter applies to the
    // element's own rendering, and the mask applies to the result.
    if anyMask && b.style != null && b.style.maskIdx > 0
        && b.id != maskedBoxId {
        paintMasked(b)
        return
    }
    if anyFilter && b.style != null && b.style.filterIdx > 0
        && b.id != filteredBoxId {
        paintFiltered(b)
        return
    }
    if anySticky && b.id != stickyBoxId && b.style.position == POS_STICKY {
        paintSticky(b)
        return
    }
    bool offset = anyOffsetPath && boxHasOffset(b)
    if !offset && (!cascadeSawTransform || b.style.transforms.length == 0) {
        paintBoxUntransformed(b)
        return
    }
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return }
    if !boxVisible(b) { return }
    Style s = b.style
    if offset {
        // The offset goes on first, so the element's own `transform`
        // applies inside it: a rotated box still moves the full
        // distance, which is what Chromium does.
        pSaveState()
        applyBoxOffset(b)
        if !cascadeSawTransform || s.transforms.length == 0 {
            paintBoxUntransformed(b)
            pRestoreState()
            return
        }
    }
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
    if offset { pRestoreState() }
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
    // The grabber goes over the box's own content, reserving nothing,
    // which is what the measurement says it does. A page that never
    // says `resize` pays one boolean here.
    if anyResize { paintResizeGrabber(b) }
}

// `resize`'s grabber, drawn from the same three functions the pointer
// is tested against in layout.f, so what it looks like and what can be
// taken hold of are one square rather than two formulas that agree.
// Its colour is Chromium's own, read off the rasterised corner.
// Whether this render omits background graphics, the way a print
// dialog's "background graphics" setting and `printToPDF`'s
// `printBackground: false` do. `print-color-adjust: exact` overrides
// it per element -- the property grants nothing on its own, it
// withdraws this omission (CSS Color Adjustment 1 §3, and the table in
// todo.md). Off by default, so an ordinary `--print` is unchanged.
bool printOmitBackgrounds = false

// Whether this box's background is printed at all. A render that is
// not omitting them -- every ordinary one -- answers yes without
// reading the property, so a page that never says `print-color-adjust`
// pays one boolean here.
bool func printsBackground(s:Style) {
    if !printOmitBackgrounds { return true }
    return printColorAdjustOf(s) == PCA_EXACT
}

const int RESIZE_GRAB_GREY = 102

void func paintResizeGrabber(b:Box) {
    if !resizeGrabberShown(b) { return }
    int cx = resizeGrabberX(b)
    int cy = resizeGrabberY(b)
    fillAlpha(1.0)
    fillStyle(RESIZE_GRAB_GREY, RESIZE_GRAB_GREY, RESIZE_GRAB_GREY)
    int left = cx - RESIZE_GRAB_PX
    int top = cy - RESIZE_GRAB_PX
    for int k = 0, k < RESIZE_GRAB_PX, k++ {
        // the long diagonal, and the short one four pixels nearer the
        // corner, which the same inset cuts to three pixels
        pDrawRect(cx - 1 - k, top + k, 1, 1)
        int sx = cx - 1 - k + 4
        if sx <= cx - 1 && sx > left { pDrawRect(sx, top + k, 1, 1) }
    }
}

// Whether this box establishes a stacking context (CSS2 §9.9, and the
// specifications that have added to the list since). Three of them are
// reachable here and all three were measured to behave identically
// (todo.md): a positioned box with a **declared** `z-index` -- `auto` is
// not one -- a box with a `transform`, and a box with an `opacity` below
// 1. The root is always one, which its caller answers for.
bool func boxIsStackingContext(b:Box) {
    Style s = b.style
    if s.opacity < 1.0 { return true }
    if cascadeSawTransform && s.transforms.length > 0 { return true }
    return boxIsPositioned(b) && zIndexIsExplicit(s)
}

// The negative-`z-index` boxes that belong to this stacking context:
// its positioned descendants with a negative z, and those of every
// descendant that is **not** itself a stacking context -- because a
// negative child of a non-context box is painted by the nearest
// ancestor that is one, which is what puts it behind that box's own
// background.
void func collectNegativeZ(b:Box, out:arr[Box]) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if boxIsPositioned(c) && c.style.zIndex < 0 {
            out.push(c)
            continue
        }
        // A descendant that is a stacking context keeps its own
        // negatives; anything else passes them up to here.
        if boxIsStackingContext(c) { continue }
        collectNegativeZ(c, out)
    }
}

// Them, painted lowest first and in document order within a z.
void func paintNegativeZ(b:Box) {
    arr[Box] neg = []
    collectNegativeZ(b, neg)
    if neg.length == 0 { return }
    int lowest = neg[0].style.zIndex
    for int i = 1, i < neg.length, i++ {
        if neg[i].style.zIndex < lowest { lowest = neg[i].style.zIndex }
    }
    for int z = lowest, z < 0, z++ {
        for int i = 0, i < neg.length, i++ {
            if neg[i].style.zIndex == z { paintBox(neg[i]) }
        }
    }
}

// ---- CSS2 §9.9's steps 3, 4 and 5 ----------------------------------
//
// The standard paints a box's in-flow content in three passes rather
// than one walk in document order: the block-level descendants' own
// decoration at step 3, the non-positioned floats at step 4, and every
// box's inline content at step 5. So a float paints over a block
// written after it, and a line paints over both.
//
// One walk in document order cannot produce that, and neither can
// painting a box's own lines after its own children: step 5 is a
// property of the whole subtree. An anonymous block holding nothing
// but inline content is a block-level descendant, so it is step 3
// while what is in it is step 5 -- which is the ordinary shape of text
// beside a float or beside a block.
//
// The walk is one function run three times, with the phase passed
// down rather than held in a global: a line can hold an atomic inline,
// which is painted whole from inside the walk, and a global would come
// back from that set to whatever the atomic's own subtree left it at.
// A box that paints as one unit takes its whole subtree with it and
// the walk does not descend into it: a float at step 4, a positioned
// box at step 6 and after, a stacking context, a replaced element, and
// anything that paints through a layer -- `overflow`, paint
// containment, a `clip-path` -- because a layer is built and blitted
// once rather than three times.
const int PHASE_BLOCKS = 1
const int PHASE_FLOATS = 2
const int PHASE_INLINES = 3

// What the step 3 walk records on each child it looks at, so that the
// step 4 and step 5 walks read an int rather than asking the same
// questions of the same boxes again. Asking them three times cost
// 23 ms of a 33 ms paint on the feature page and 8 ms of a 19 ms paint
// on generated.html, because `boxIsPositioned`, `boxIsFloated` and
// `boxPaintsWhole` all read a `Style` and a `Style` read is not free.
const int PSTEP_NONE = 0     // not painted from the walk at all
const int PSTEP_SPLIT = 1    // step 3 decoration here, step 5 lines, descend
const int PSTEP_FLOAT = 2    // step 4, painted whole
const int PSTEP_WHOLE = 3    // painted whole at step 3
const int PSTEP_POSITIONED = 4  // step 6 and after, painted whole

// Whether this box is handed over whole rather than split across the
// three phases. A float and a positioned box are whole as well, but
// they are asked for by name because *which* phase paints them differs.
bool func boxPaintsWhole(b:Box) {
    if b.kind == BOX_IMAGE || b.kind == BOX_AUDIO || b.kind == BOX_IFRAME { return true }
    // Every question below this line that is not behind a flag reads a
    // `Style`, and the walk asks this of every box in every phase. The
    // three walks cost **8 ms of a 19 ms paint** on generated.html
    // while it read one unconditionally, and stubbing the predicate out
    // gave back every millisecond of it with the pixels unchanged -- so
    // a page that declares none of these pays six boolean tests.
    if cascadeSawClip && boxClipShape(b).kind != CLIPSHAPE_NONE { return true }
    if anyOffsetPath && boxHasOffset(b) { return true }
    // A `filter` makes the element a stacking context, and this engine
    // needs it to paint whole for a second reason: the filter has to be
    // in force for the box's own background and for every descendant's
    // colour, which is what going through `paintBox` gives it. An
    // ordinary in-flow block never reaches `paintBox` otherwise.
    if anyFilter && b.style.filterIdx > 0 { return true }
    // A mask needs the box to paint whole for the same reason a filter
    // does: the whole subtree has to reach one layer before it can be
    // blitted back through the mask's alpha.
    if anyMask && b.style.maskIdx > 0 { return true }
    if cascadeSawTransform && b.style.transforms.length > 0 { return true }
    // A positioned box is not asked about: every caller steps over one
    // before it gets here, so the `z-index` half of
    // `boxIsStackingContext` would be a `Style` read that can never
    // answer yes.
    if !docHasWholePaint { return false }
    Style s = b.style
    if s.contentHidden { return true }
    return s.overflowHidden || s.containPaint || s.opacity < 1.0
}

// Everything a box paints of itself, before any of its contents: its
// shadows, background, borders and border image, then its outline,
// column rules, the negative stacking layer it owns, its list marker
// and its form control. Answers whether its contents are to be walked
// at all -- a replaced element has painted its own, an empty cell
// hiding its decoration has none to show, and `content-visibility:
// hidden` says there are none.
bool func paintBoxSelf(b:Box) {
    Style s = b.style
    // empty-cells: hide -- a cell with nothing in it draws neither
    // background nor border in the separated borders model (CSS2
    // 17.6.1.1). The cell still takes its space; only its own
    // decoration goes.
    if b.kind == BOX_CELL && s.emptyCellsHide && !s.borderCollapse && cellIsEmpty(b) { return false }
    if b.kind != BOX_ANON && !s.hidden {
        // a shadow is cast by the border box and lies under it
        paintShadows(b.x, b.y, b.w, b.h, s)
        bool bg = printsBackground(s)
        if b.kind == BOX_ROW {
            if bg { paintBackground(b.x, b.y, b.w, b.h, b.bl, b.bt, b.br, b.bb, b.pl, b.pt, b.pr, b.pb, s) }
        } else {
            if bg { paintBackground(b.x, b.y, b.w, b.h, b.bl, b.bt, b.br, b.bb, b.pl, b.pt, b.pr, b.pb, s) }
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
        return false
    }
    if b.kind == BOX_AUDIO {
        paintAudioControls(b)
        return false
    }
    if b.kind == BOX_IFRAME {
        if !s.hidden { paintFrame(b) }
        return false
    }
    // The outline is not drawn here. §9.9 puts it after the whole of
    // this box's in-flow content and before its positioned descendants,
    // measured against all four in todo.md, so it is a pass of its own
    // below.
    if s.columnRuleWidth > 0 && !s.hidden { paintColumnRules(b) }
    // content-visibility: hidden skips the contents entirely
    // (Containment 2 §4). The box's own background, border and outline
    // are not contents, so they are already painted above; everything
    // after this is.
    if s.contentHidden { return false }
    // CSS2 §9.9 step 3: the negative descendants of this stacking
    // context, after its own background and border and before anything
    // of its content. A document that declares no negative `z-index`
    // does none of this.
    if cascadeSawNegativeZ && boxIsStackingContext(b) { paintNegativeZ(b) }
    if b.isListItem && !s.hidden { paintListMarker(b) }
    if !s.hidden { paintFormControl(b) }
    return true
}

// CSS2 §9.9 step 3 over a box's in-flow, non-positioned subtree: each
// block-level descendant's own decoration, in tree order, and none of
// their lines. It answers, for every child it looks at, which step
// paints it, and writes that answer on the box for the two walks below.
void func paintBlocksWalk(b:Box) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        c.paintStep = PSTEP_NONE
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        // Positioned first, and before the inline-level test below it:
        // an out-of-flow box is in no line, so a `position: absolute`
        // inline-block that the inline-level test stepped over would be
        // painted by nothing at all.
        if docHasPositioned && boxIsPositioned(c) {
            c.paintStep = PSTEP_POSITIONED
            continue
        }
        // An in-flow inline-level child is step 5 content reached
        // through the line that holds it, as the atomic it was placed
        // as -- `paintLines` paints it from its own box. Walking into
        // it here as well paints it twice, which is invisible until a
        // `border-radius` blends its antialiased edge against itself.
        // A flex or grid item is block-level however it was declared,
        // so this does not take one of those away from its container.
        if isInlineLevelBox(c) { continue }
        if anyAnchorHidden && anchorHides(c) { continue }
        if !boxVisible(c) { continue }
        if docHasFloats && boxIsFloated(c) {
            c.paintStep = PSTEP_FLOAT
            continue
        }
        if boxPaintsWhole(c) {
            // It takes its own floats and its own lines with it, and
            // its `resize` grabber -- only a box whose `overflow` is
            // not `visible` shows one, and such a box paints whole.
            c.paintStep = PSTEP_WHOLE
            paintBox(c)
            continue
        }
        if !paintBoxSelf(c) { continue }
        c.paintStep = PSTEP_SPLIT
        paintBlocksWalk(c)
    }
}

// Step 4: the non-positioned floats, each painted whole, in tree order.
void func paintFloatsWalk(b:Box) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.paintStep == PSTEP_FLOAT { paintBox(c) }
        else if c.paintStep == PSTEP_SPLIT { paintFloatsWalk(c) }
    }
}

// §9.9's outline pass: this box's outline, if its caller wants it
// drawn here, and then its in-flow descendants', in tree order. A box
// that paints whole drew its own inside its own subtree.
void func paintOutlineFor(b:Box) {
    Style s = b.style
    if s.outlineWidth > 0 && !s.hidden { paintOutline(b) }
}

void func paintOutlineWalk(b:Box) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.paintStep != PSTEP_SPLIT { continue }
        // Recording which boxes ask for an outline, so this pass never
        // reads a `Style`, was tried and measured: paired against this
        // on the feature page it read +1 ms of paint one way and 0 the
        // other, so it bought nothing and is not here.
        paintOutlineFor(c)
        paintOutlineWalk(c)
    }
}

// Step 5: every in-flow box's lines, in tree order.
void func paintInlinesWalk(b:Box) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.paintStep != PSTEP_SPLIT { continue }
        paintLines(c)
        paintInlinesWalk(c)
    }
}

// The positioned descendants this box paints at steps 6 and after: its
// own positioned children and those of every in-flow descendant the
// three walks descend into, because the walks step over a positioned
// box wherever they meet one. A box that paints whole keeps its own,
// and so does a float.
void func collectPositionedIn(b:Box, out:arr[Box]) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if boxIsPositioned(c) {
            out.push(c)
            continue
        }
        if boxIsFloated(c) { continue }
        if boxPaintsWhole(c) { continue }
        collectPositionedIn(c, out)
    }
}

// The same set, read off the marks the step 3 walk left rather than
// asked again. This is the painter's; the one above is the hit
// tester's, which cannot use the marks because a click can arrive on a
// page that was laid out and never painted.
void func collectPositionedPainted(b:Box, out:arr[Box]) {
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.paintStep == PSTEP_POSITIONED { out.push(c) }
        else if c.paintStep == PSTEP_SPLIT { collectPositionedPainted(c, out) }
    }
}

// Them, lowest z first and in document order within a z. The negative
// ones are not here: they belong to the nearest stacking context and
// were painted before any of this box's content.
void func paintPositionedIn(b:Box) {
    arr[Box] pos = []
    collectPositionedPainted(b, pos)
    if pos.length == 0 { return }
    int highest = 0
    for int i = 0, i < pos.length, i++ {
        if pos[i].style.zIndex > highest { highest = pos[i].style.zIndex }
    }
    for int z = 0, z <= highest, z++ {
        for int i = 0, i < pos.length, i++ {
            if pos[i].style.zIndex != z { continue }
            paintBox(pos[i])
        }
    }
}

// A box's contents, in §9.9's order. Run for every box that paints
// whole, so a float and a clipped subtree get the same three passes
// the document does.
// `ownOutline` is false where the caller draws this box's outline
// itself: a clipping box paints its contents into a layer the size of
// its padding box, and an outline lies outside its border box, so an
// outline drawn in there would fall outside the layer and vanish.
void func paintContents(b:Box, ownOutline:bool) {
    paintBlocksWalk(b)
    // Step 4 is skipped outright on a document with no float in it.
    if docHasFloats { paintFloatsWalk(b) }
    paintLines(b)
    paintInlinesWalk(b)
    // The outlines, above everything in flow and below anything
    // positioned. A document that declares none does not walk for them.
    if docHasOutline {
        if ownOutline { paintOutlineFor(b) }
        paintOutlineWalk(b)
    }
    if docHasPositioned { paintPositionedIn(b) }
}

void func paintSubtree(b:Box) {
    paintContents(b, true)
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
    if !paintBoxSelf(b) { return }
    paintSubtree(b)
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
    int fw = anyFilter && paintFilters.length > 0 ? filteredColor(COLOR_WHITE) : COLOR_WHITE
    applyFillColor(fw)
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

// ---- a document's painting flags -------------------------------------
//
// The painter asks a set of per-document questions -- has this document
// a float, a positioned box, a box that paints whole, an outline, a
// transform, a clip, a corner shape, small caps -- and each is a global
// raised while the box tree is **built** or the cascade runs, then read
// while the document is **painted**. One document at a time makes the
// two agree; two documents alive does not, and then a page is painted
// with whichever document was laid out last.
//
// So a page carries its own answers and puts them back before it is
// painted. The list below is bound to be incomplete one day, which is
// why `tests/render/pagestate.f` asks the invariant rather than the
// list: paint a page, build and paint another, paint the first again,
// and require the same pixels. A flag added and forgotten fails that.
struct DocFlags {
    floats:bool
    positioned:bool
    wholePaint:bool
    outline:bool
    rtlText:bool
    sawClip:bool
    sawNegativeZ:bool
    sawTransform:bool
    anchorHidden:bool
    clipMargin:bool
    cornerShape:bool
    crossFade:bool
    offsetPath:bool
    resize:bool
    sticky:bool
    smallCaps:bool
    // Not every answer is a boolean. The values a property keeps by
    // the computed style's serial live in maps that `cascadeReset`
    // REPLACES rather than empties, so holding the old map here keeps
    // this document's answers alive while the next document fills a
    // new one.
    fontCaps:map[int]
}

DocFlags func captureDocFlags() {
    DocFlags f
    f.floats = docHasFloats
    f.positioned = docHasPositioned
    f.wholePaint = docHasWholePaint
    f.outline = docHasOutline
    f.rtlText = anyRtlText
    f.sawClip = cascadeSawClip
    f.sawNegativeZ = cascadeSawNegativeZ
    f.sawTransform = cascadeSawTransform
    f.anchorHidden = anyAnchorHidden
    f.clipMargin = anyClipMargin
    f.cornerShape = anyCornerShape
    f.crossFade = anyCrossFade
    f.offsetPath = anyOffsetPath
    f.resize = anyResize
    f.sticky = anySticky
    f.smallCaps = anySmallCaps
    f.fontCaps = fontCapsOfSerial
    return f
}

void func restoreDocFlags(f:DocFlags) {
    docHasFloats = f.floats
    docHasPositioned = f.positioned
    docHasWholePaint = f.wholePaint
    docHasOutline = f.outline
    anyRtlText = f.rtlText
    cascadeSawClip = f.sawClip
    cascadeSawNegativeZ = f.sawNegativeZ
    cascadeSawTransform = f.sawTransform
    anyAnchorHidden = f.anchorHidden
    anyClipMargin = f.clipMargin
    anyCornerShape = f.cornerShape
    anyCrossFade = f.crossFade
    anyOffsetPath = f.offsetPath
    anyResize = f.resize
    anySticky = f.sticky
    anySmallCaps = f.smallCaps
    fontCapsOfSerial = f.fontCaps
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
// A point mapped out of the transformed space back into the box's own.
//
// The painter composes `translate(origin)`, then each function in the
// order written, then `translate(-origin)`, so the inverse is the same
// functions inverted and applied in the opposite order. Two answers out
// of one function need globals (FINDINGS.md, "one value out of a
// function").
int untransformedX = 0
int untransformedY = 0

void func untransformPoint(b:Box, x:int, y:int) {
    Style s = b.style
    // The same reference box the painter takes its origin in, so the
    // point is undone about exactly the origin it was done about.
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
    float px = (x - ox).toFloat()
    float py = (y - oy).toFloat()
    for int i = s.transforms.length - 1, i >= 0, i-- {
        Transform t = s.transforms[i]
        if t.kind == TX_TRANSLATE {
            px = px - resolveLen(t.x, b.w, 0).toFloat()
            py = py - resolveLen(t.y, b.h, 0).toFloat()
        } else if t.kind == TX_ROTATE {
            float rad = (0.0 - t.angle) * CSS_PI / 180.0
            float c = Math.cos(rad)
            float sn = Math.sin(rad)
            float nx = px * c - py * sn
            float ny = px * sn + py * c
            px = nx
            py = ny
        } else if t.kind == TX_SCALE {
            // A zero scale draws nothing, so nothing can be hit through
            // it and the point is sent somewhere the box is not.
            if t.sx == 0.0 || t.sy == 0.0 {
                untransformedX = b.x - 1
                untransformedY = b.y - 1
                return
            }
            px = px / t.sx
            py = py / t.sy
        }
    }
    untransformedX = ox + roundPx(px)
    untransformedY = oy + roundPx(py)
}

// The out-of-flow boxes, searched topmost first. This is what finds a
// box laid out past every ancestor's rectangle, which the ordinary
// descent cannot reach because it culls by the ancestor's box. Later in
// document order is nearer the top, so the scan runs backwards.
//
// It is declared before `hitTest` and calls it, which is fine because
// functions are hoisted here where globals are not.
Box func hitOutOfFlow(x:int, y:int) {
    if outOfFlowBoxes.length == 0 { return null }
    // In reverse painting order, as the ordinary descent is: highest
    // `z-index` first, and latest in document order within a z.
    int hiZ = outOfFlowBoxes[0].style.zIndex
    int loZ = hiZ
    for int i = 1, i < outOfFlowBoxes.length, i++ {
        int z = outOfFlowBoxes[i].style.zIndex
        if z > hiZ { hiZ = z }
        if z < loZ { loZ = z }
    }
    for int z = hiZ, z >= loZ, z-- {
        for int i = outOfFlowBoxes.length - 1, i >= 0, i-- {
            Box c = outOfFlowBoxes[i]
            if c.style.zIndex != z { continue }
            Box got = hitChild(c, x, y)
            if got != null { return got }
        }
    }
    return null
}

// One child tested against the point, or null for "not this one".
// Shared by the three passes below so the transform and
// `pointer-events` rules cannot drift between them.
Box func hitChild(c:Box, x:int, y:int) {
    if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { return null }
    // A transformed box is drawn somewhere other than where it was laid
    // out, so the pointer is tested against the drawn shape: the point
    // comes back through the inverse transform and everything below it
    // -- this box and its whole subtree -- is searched in that space. A
    // document that never said `transform` pays one boolean here.
    int hx = x
    int hy = y
    // A sticky box is drawn away from where it was laid out, so the
    // pointer comes back the same distance before this box or anything
    // under it is tested. The offset is worked out from the scroll
    // position the painter last drew at, which is the one the click
    // arrived on: a click is answered after a paint, not before one.
    if anySticky && c.style.position == POS_STICKY { hy = hy - stickyOffsetY(c) }
    if cascadeSawTransform && c.style.transforms.length > 0 {
        untransformPoint(c, hx, hy)
        hx = untransformedX
        hy = untransformedY
    }
    if hx < c.x || hx >= c.x + c.w { return null }
    if hy < c.y || hy >= c.y + c.h { return null }
    // pointer-events: none takes a box out of hit testing so that what
    // is behind it is found instead. Its descendants are still
    // searched, because a child may ask for pointer events back.
    Box inner = hitTest(c, hx, hy)
    if inner != null { return inner }
    if c.style.pointerEvents != PE_NONE { return c }
    return null
}

// This box's own inline content, at the point. The fragments are in
// paint order within a line and no two overlap, so the first one the
// point falls in is the answer.
Box func hitLines(b:Box, x:int, y:int) {
    for int i = 0, i < b.lines.length, i++ {
        Line ln = b.lines[i]
        if y < ln.y || y >= ln.y + ln.h { continue }
        for int j = 0, j < ln.frags.length, j++ {
            Fragment f = ln.frags[j]
            if f.kind == FRAG_INLINE_BG { continue }
            // An atomic inline is painted from its own box rather
            // than from the fragment, and a negative margin puts the
            // two in different places: the fragment is the margin box,
            // so `margin-left: -80px` on a 60-wide box gives it a
            // width of -20 at the line's own x. So it is hit through
            // `hitChild` like every other box, against the rectangle
            // the painter drew it in.
            if f.kind == FRAG_ATOMIC {
                Box got = hitChild(f.box, x, y)
                if got != null { return got }
                continue
            }
            if x >= f.x && x < f.x + f.w && y >= f.y && y < f.y + f.h {
                // pointer-events: none takes a box out of hit testing so
                // that what is behind it is found instead.
                if f.box.style.pointerEvents == PE_NONE { continue }
                return f.box
            }
        }
    }
    return null
}

// One of the painter's three phases, read backwards: latest in document
// order first, and a box's subtree before the box itself, because both
// painted later. It is the painter's `paintPhaseWalk` with every
// "paint" replaced by "answer if it is there", so the two cannot drift.
Box func hitPhaseWalk(b:Box, x:int, y:int, phase:int) {
    for int i = b.children.length - 1, i >= 0, i-- {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        // Positioned first, as in the painter: an out-of-flow box is in
        // no line, so the inline-level test must not reach one.
        if docHasPositioned && boxIsPositioned(c) { continue }
        // Reached through the line that holds it, exactly as the
        // painter reaches it.
        if isInlineLevelBox(c) { continue }
        if docHasFloats && boxIsFloated(c) {
            if phase != PHASE_FLOATS { continue }
            Box got = hitChild(c, x, y)
            if got != null { return got }
            continue
        }
        if boxPaintsWhole(c) {
            if phase != PHASE_BLOCKS { continue }
            Box got = hitChild(c, x, y)
            if got != null { return got }
            continue
        }
        if x < c.x || x >= c.x + c.w { continue }
        if y < c.y || y >= c.y + c.h { continue }
        Box deep = hitPhaseWalk(c, x, y, phase)
        if deep != null { return deep }
        if phase == PHASE_INLINES {
            Box own = hitLines(c, x, y)
            if own != null { return own }
        } else if phase == PHASE_BLOCKS {
            // pointer-events: none takes a box out of hit testing so
            // that what is behind it is found instead.
            if c.style.pointerEvents != PE_NONE { return c }
        }
    }
    return null
}

// The positioned descendants this box paints at steps 6 and after,
// topmost first: highest z, and latest in document order within a z.
Box func hitPositionedIn(b:Box, x:int, y:int) {
    arr[Box] pos = []
    collectPositionedIn(b, pos)
    if pos.length == 0 { return null }
    int highest = 0
    for int i = 0, i < pos.length, i++ {
        if pos[i].style.zIndex > highest { highest = pos[i].style.zIndex }
    }
    for int z = highest, z >= 0, z-- {
        for int i = pos.length - 1, i >= 0, i-- {
            if pos[i].style.zIndex != z { continue }
            Box got = hitChild(pos[i], x, y)
            if got != null { return got }
        }
    }
    return null
}

// The negative ones, which this stacking context painted before any of
// its own content, so they are the last thing a click can reach.
Box func hitNegativeIn(b:Box, x:int, y:int) {
    arr[Box] neg = []
    collectNegativeZ(b, neg)
    if neg.length == 0 { return null }
    int lowest = neg[0].style.zIndex
    for int i = 1, i < neg.length, i++ {
        if neg[i].style.zIndex < lowest { lowest = neg[i].style.zIndex }
    }
    for int z = 0 - 1, z >= lowest, z-- {
        for int i = neg.length - 1, i >= 0, i-- {
            if neg[i].style.zIndex != z { continue }
            Box got = hitChild(neg[i], x, y)
            if got != null { return got }
        }
    }
    return null
}

Box func hitTest(b:Box, x:int, y:int) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return null }
    // Inside a scrolled box the content is drawn that much higher than
    // it was laid out, so a point on the screen is that much further
    // down the content. Every box that scrolls nothing answers zero
    // without looking anything up.
    int scrolled = boxScrollTop(b)
    if scrolled > 0 { y = y + scrolled }
    int across = boxScrollLeft(b)
    if across > 0 { x = x + across }
    // CSS2 §9.9 read backwards: the positioned descendants at zero and
    // above, highest z first and latest first within a z; then step 5,
    // the in-flow inline content, deepest and latest first; then step
    // 4, the floats; then step 3, the block-level boxes; then the
    // negative ones this stacking context owns.
    if docHasPositioned {
        Box over = hitPositionedIn(b, x, y)
        if over != null { return over }
    }
    Box deepLine = hitPhaseWalk(b, x, y, PHASE_INLINES)
    if deepLine != null { return deepLine }
    Box ownLine = hitLines(b, x, y)
    if ownLine != null { return ownLine }
    if docHasFloats {
        Box floated = hitPhaseWalk(b, x, y, PHASE_FLOATS)
        if floated != null { return floated }
    }
    Box blockLevel = hitPhaseWalk(b, x, y, PHASE_BLOCKS)
    if blockLevel != null { return blockLevel }
    if cascadeSawNegativeZ && boxIsStackingContext(b) {
        Box behind = hitNegativeIn(b, x, y)
        if behind != null { return behind }
    }
    // Nothing in the tree under this point. A box laid out past every
    // ancestor's rectangle is unreachable by that descent, so the
    // out-of-flow boxes are searched directly -- from the root only,
    // and only once the ordinary answer has come back empty, so no
    // answer this already gave can change.
    if b.parentId == 0 && outOfFlowBoxes.length > 0 {
        Box away = hitOutOfFlow(x, y)
        if away != null { return away }
    }
    return null
}

// The innermost scroll container under a point that has anything left
// to scroll in the direction asked for, or null where there is none --
// which is what hands the wheel back to the page.
// Whether the wheel that `wheelTargetAt` could not place should go on
// to the page. A scroll container that has reached its end normally
// passes the wheel outward; `overscroll-behavior` stops it there and
// sets this instead.
bool wheelChainBlocked = false

// The box a wheel at (x, y) scrolls, or null -- and then
// `wheelChainBlocked` says whether the page may take what is left.
Box func wheelTargetAt(root:Box, x:int, y:int, dy:int) {
    wheelChainBlocked = false
    return scrollContainerAt(root, x, y, dy)
}

// The same, across.
Box func wheelTargetAcrossAt(root:Box, x:int, y:int, dx:int) {
    wheelChainBlocked = false
    return scrollContainerAcrossAt(root, x, y, dx)
}

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
            // a descendant contained the chain: this box does not get
            // the wheel and neither does anything outside it
            if wheelChainBlocked { return null }
        }
    }
    if b.sbW <= 0 { return null }
    int range = boxScrollRange(b)
    // This container cannot take the wheel -- it has nothing to scroll,
    // or it has reached its end in the direction asked for -- so the
    // wheel would pass outward. `overscroll-behavior` on the axis asked
    // for stops it here instead (CSS Overscroll Behavior 1 §3). A box
    // with nothing to scroll is at both of its ends at once, so it
    // contains the chain exactly as one scrolled to its end does.
    if range <= 0 || (dy > 0 && scrolled >= range) || (dy < 0 && scrolled <= 0) {
        if overscrollY(b.style) != OSB_AUTO { wheelChainBlocked = true }
        return null
    }
    return b
}

// The scroll container whose vertical thumb is under the pointer, or
// null. The same walk `scrollContainerAt` does, against the thumb's own
// rectangle rather than the box's: a press on the thumb takes hold of it
// and a press anywhere else does not.
Box func scrollThumbAt(b:Box, x:int, y:int) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return null }
    int scrolled = boxScrollTop(b)
    int inner = scrolled > 0 ? y + scrolled : y
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if x >= c.x && x < c.x + c.w && inner >= c.y && inner < c.y + c.h {
            Box found = scrollThumbAt(c, x, inner)
            if found != null { return found }
        }
    }
    if !scrollThumbShown(b) { return null }
    int tx = scrollThumbLeft(b)
    int ty = scrollThumbTop(b)
    if x < tx || x >= tx + scrollThumbWidth(b) { return null }
    if y < ty || y >= ty + scrollThumbHeight(b) { return null }
    return b
}

// Puts the thumb's top at `top`, in the track's own coordinates, and
// scrolls the box to match. The offset the pointer had inside the thumb
// when it was pressed is the caller's to subtract, so the content does
// not jump on the first pixel of the drag.
//
// Answers whether the box moved, which is what tells a drag that reached
// an end from one that did not.
bool func scrollThumbDragTo(b:Box, top:int) {
    if !scrollThumbShown(b) { return false }
    int run = scrollTrackHeight(b) - scrollThumbHeight(b)
    if run <= 0 { return false }
    int want = top - scrollTrackTop(b)
    int range = boxScrollRange(b)
    int to = clampInt(Math.floorDiv(want * range, run), 0, range)
    return boxScrollBy(b, to - boxScrollTop(b))
}

// The scroll container under the pointer that can still be scrolled
// across in the direction asked for, or null -- the same question
// `scrollContainerAt` answers down.
Box func scrollContainerAcrossAt(b:Box, x:int, y:int, dx:int) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return null }
    int inner = boxScrollTop(b) > 0 ? y + boxScrollTop(b) : y
    int innerX = boxScrollLeft(b) > 0 ? x + boxScrollLeft(b) : x
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if innerX >= c.x && innerX < c.x + c.w && inner >= c.y && inner < c.y + c.h {
            Box found = scrollContainerAcrossAt(c, innerX, inner, dx)
            if found != null { return found }
            if wheelChainBlocked { return null }
        }
    }
    if b.sbH <= 0 { return null }
    int range = boxScrollLeftRange(b)
    int at = boxScrollLeft(b)
    if range <= 0 || (dx > 0 && at >= range) || (dx < 0 && at <= 0) {
        if overscrollX(b.style) != OSB_AUTO { wheelChainBlocked = true }
        return null
    }
    return b
}

// The same two, across.
Box func scrollHThumbAt(b:Box, x:int, y:int) {
    if b.kind == BOX_TEXT || b.kind == BOX_BR { return null }
    int inner = boxScrollTop(b) > 0 ? y + boxScrollTop(b) : y
    int innerX = boxScrollLeft(b) > 0 ? x + boxScrollLeft(b) : x
    for int i = 0, i < b.children.length, i++ {
        Box c = b.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || c.kind == BOX_INLINE { continue }
        if innerX >= c.x && innerX < c.x + c.w && inner >= c.y && inner < c.y + c.h {
            Box found = scrollHThumbAt(c, innerX, inner)
            if found != null { return found }
        }
    }
    if !scrollHThumbShown(b) { return null }
    int tx = scrollHThumbLeft(b)
    int ty = scrollHTrackTop(b)
    if x < tx || x >= tx + scrollHThumbWidth(b) { return null }
    if y < ty || y >= ty + b.sbH { return null }
    return b
}

bool func scrollHThumbDragTo(b:Box, left:int) {
    if !scrollHThumbShown(b) { return false }
    int run = scrollHTrackWidth(b) - scrollHThumbWidth(b)
    if run <= 0 { return false }
    int want = left - scrollHTrackLeft(b)
    int range = boxScrollLeftRange(b)
    int to = clampInt(Math.floorDiv(want * range, run), 0, range)
    return boxScrollLeftBy(b, to - boxScrollLeft(b))
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
