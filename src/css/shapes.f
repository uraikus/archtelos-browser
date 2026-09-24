// A basic shape resolved against a box, and the horizontal span it
// covers at a given row. Two features need this and they are on
// opposite sides of the engine: the painter cuts a box to a `clip-path`
// shape, and the layout engine pushes line boxes aside from a float's
// `shape-outside`. Neither can call the other -- the painter imports
// the layout engine -- so the geometry lives here, taking the reference
// box as four numbers rather than as a Box.
//
// A pixel or a point belongs to the shape when its centre does. That is
// the rule a rasteriser without antialiasing has to use, and it is the
// rule tests/render/clip.f's expected grids were read from Chromium
// under.

import style.f

// One shape, resolved into document pixels.
struct ShapeGeom {
    kind:int
    // The bounding box, and for a rectangle the rectangle itself. The
    // x range includes x0 and excludes x1, as a pixel range does.
    x0:int
    y0:int
    x1:int
    y1:int
    centreX:float
    centreY:float
    radiusX:float
    radiusY:float
    pointsX:arr[float]
    pointsY:arr[float]
    fillEvenOdd:bool
    // inset()'s `round` radii, in pixels, four corners clockwise from
    // the top left. Empty on a rectangle with square corners, which is
    // the test `shapeSpansAt` makes before it looks at a corner at all.
    cornerRX:arr[int]
    cornerRY:arr[int]
    // shape-margin, which grows the shape on every side. For a
    // rectangle, a circle and an ellipse it is folded into the geometry
    // above; a polygon carries it here, because the true outset of a
    // polygon is not a polygon.
    margin:int
}

// How far a corner's ellipse holds the edge in, `dy` into its band:
// nothing at the band's inner end, the whole radius past its outer one.
//
// This lives here rather than in the painter because two callers ask it
// the same question and the CSS cannot call the painter: the box-shadow
// and border code asks it of a `border-radius`, and `shapeSpansAt` asks
// it of `inset()`'s `round` radius, which is the same quarter ellipse
// on a different rectangle.
float func cornerInset(rx:int, ry:int, dy:float) {
    if rx <= 0 || ry <= 0 || dy <= 0.0 { return 0.0 }
    float fry = ry.toFloat()
    if dy >= fry { return rx.toFloat() }
    float t = dy / fry
    return rx.toFloat() * (1.0 - Math.sqrt(1.0 - t * t))
}

// Backgrounds and Borders 3 §5.5: where two radii on one edge would
// overlap, every radius is divided by the same factor, so the shape
// keeps its proportions. Shared with the painter for the same reason.
float func radiusShrink(sum:int, side:int) {
    if sum <= side || sum <= 0 { return 1.0 }
    return side.toFloat() / sum.toFloat()
}

float func shapeMin(a:float, b:float) {
    return a < b ? a : b
}

float func shapeMax(a:float, b:float) {
    return a > b ? a : b
}

// One radius, which may be a length, a percentage or a keyword. The
// keywords measure from the centre to the nearest or furthest edge of
// the reference box along this axis.
float func shapeRadius(l:Len, kind:int, base:int, centre:float, lo:float, hi:float) {
    if kind == CLIPRAD_CLOSEST { return shapeMin(centre - lo, hi - centre) }
    if kind == CLIPRAD_FARTHEST { return shapeMax(centre - lo, hi - centre) }
    return resolveLen(l, base, 0).toFloat()
}

// Resolves a shape against a reference box, growing it by `margin` on
// every side.
ShapeGeom func resolveShape(sh:ClipShape, rx:int, ry:int, rw:int, rh:int, margin:int) {
    ShapeGeom g
    g.kind = sh.kind
    if sh.kind == CLIPSHAPE_RECT {
        g.x0 = rx + resolveLen(sh.insetLeft, rw, 0) - margin
        g.y0 = ry + resolveLen(sh.insetTop, rh, 0) - margin
        g.x1 = rx + rw - resolveLen(sh.insetRight, rw, 0) + margin
        g.y1 = ry + rh - resolveLen(sh.insetBottom, rh, 0) + margin
        if sh.insetRoundIdx > 0 { resolveInsetRadii(g, sh.insetRoundIdx) }
        return g
    }
    if sh.kind == CLIPSHAPE_CIRCLE || sh.kind == CLIPSHAPE_ELLIPSE {
        g.centreX = (rx + resolveLen(sh.centreX, rw, 0)).toFloat()
        g.centreY = (ry + resolveLen(sh.centreY, rh, 0)).toFloat()
        float w = rw.toFloat()
        float h = rh.toFloat()
        // A circle's percentage radius is of the reference box's
        // diagonal over root two, which for a square is its side.
        int circleBase = Math.round(Math.sqrt((w * w + h * h) / 2.0))
        int baseX = sh.kind == CLIPSHAPE_CIRCLE ? circleBase : rw
        int baseY = sh.kind == CLIPSHAPE_CIRCLE ? circleBase : rh
        g.radiusX = shapeRadius(sh.radiusX, sh.radiusXKind, baseX,
            g.centreX, rx.toFloat(), (rx + rw).toFloat())
        g.radiusY = shapeRadius(sh.radiusY, sh.radiusYKind, baseY,
            g.centreY, ry.toFloat(), (ry + rh).toFloat())
        if sh.kind == CLIPSHAPE_CIRCLE && sh.radiusXKind != CLIPRAD_LENGTH {
            // A circle has one radius, so the two keywords compare both
            // axes and take the side the keyword asks for.
            float r = sh.radiusXKind == CLIPRAD_CLOSEST
                ? shapeMin(g.radiusX, g.radiusY)
                : shapeMax(g.radiusX, g.radiusY)
            g.radiusX = r
            g.radiusY = r
        }
        g.radiusX = g.radiusX + margin.toFloat()
        g.radiusY = g.radiusY + margin.toFloat()
        g.x0 = Math.floor(g.centreX - g.radiusX)
        g.x1 = Math.ceil(g.centreX + g.radiusX)
        g.y0 = Math.floor(g.centreY - g.radiusY)
        g.y1 = Math.ceil(g.centreY + g.radiusY)
        return g
    }
    if sh.kind == CLIPSHAPE_POLYGON {
        arr[float] xs = []
        arr[float] ys = []
        for int i = 0, i < sh.pointsX.length, i++ {
            xs.push((rx + resolveLen(sh.pointsX[i], rw, 0)).toFloat())
            ys.push((ry + resolveLen(sh.pointsY[i], rh, 0)).toFloat())
        }
        g.pointsX = xs
        g.pointsY = ys
        g.fillEvenOdd = sh.fillEvenOdd
        g.margin = margin
        float lox = xs[0]
        float hix = xs[0]
        float loy = ys[0]
        float hiy = ys[0]
        for int i = 1, i < xs.length, i++ {
            lox = shapeMin(lox, xs[i])
            hix = shapeMax(hix, xs[i])
            loy = shapeMin(loy, ys[i])
            hiy = shapeMax(hiy, ys[i])
        }
        g.x0 = Math.floor(lox) - margin
        g.x1 = Math.ceil(hix) + margin
        g.y0 = Math.floor(loy) - margin
        g.y1 = Math.ceil(hiy) + margin
        return g
    }
    return g
}

// The spans one row of the shape covers, as x ranges that include the
// start and exclude the end. Written to globals because a function
// answers with one value (FINDINGS.md, "one value out of a function").
//
// This is the painter's question -- which pixels a clip keeps -- and a
// clip has no shape-margin, so `margin` plays no part in it. The
// exclusion edge a float needs is a different question, answered
// further down against a continuous band rather than a pixel row.
arr[int] shapeSpanStart = []
arr[int] shapeSpanEnd = []

// `inset()`'s `round` radii against the rectangle the inset left, which
// is the rectangle the standard measures them against -- so `50%` of a
// 200px box that was not inset is 100, and the shape is a circle.
//
// Called only where `insetRoundIdx` says there are radii, so a plain
// `inset()` pays one integer test rather than this.
void func resolveInsetRadii(g:ShapeGeom, idx:int) {
    InsetRadii r = insetRadiiOf(idx)
    if r == null { return }
    int w = g.x1 - g.x0
    int h = g.y1 - g.y0
    if w <= 0 || h <= 0 { return }
    arr[int] xs = []
    arr[int] ys = []
    for int i = 0, i < 4, i++ {
        xs.push(maxInt(resolveLen(r.rx[i], w, 0), 0))
        ys.push(maxInt(resolveLen(r.ry[i], h, 0), 0))
    }
    // §5.5's single factor, so two radii on one edge cannot overlap.
    float f = shapeMin(shapeMin(radiusShrink(xs[0] + xs[1], w),
                                radiusShrink(xs[3] + xs[2], w)),
                       shapeMin(radiusShrink(ys[0] + ys[3], h),
                                radiusShrink(ys[1] + ys[2], h)))
    if f < 1.0 {
        for int i = 0, i < 4, i++ {
            xs[i] = Math.round(xs[i].toFloat() * f)
            ys[i] = Math.round(ys[i].toFloat() * f)
        }
    }
    if xs[0] + xs[1] + xs[2] + xs[3] + ys[0] + ys[1] + ys[2] + ys[3] == 0 { return }
    g.cornerRX = xs
    g.cornerRY = ys
}

// One row of a rounded rectangle: the corners hold the left edge in and
// the right edge back, and everywhere between them the row is the
// rectangle's own. Both halves take the larger of the two corners that
// reach the row, which is what lets a tall corner and a short one share
// an edge.
void func shapeRectRow(g:ShapeGeom, y:int) {
    float vc = y.toFloat() + 0.5 - g.y0.toFloat()
    float h = (g.y1 - g.y0).toFloat()
    float lo = shapeMax(cornerInset(g.cornerRX[0], g.cornerRY[0], g.cornerRY[0].toFloat() - vc),
                        cornerInset(g.cornerRX[3], g.cornerRY[3], vc - (h - g.cornerRY[3].toFloat())))
    float hi = shapeMax(cornerInset(g.cornerRX[1], g.cornerRY[1], g.cornerRY[1].toFloat() - vc),
                        cornerInset(g.cornerRX[2], g.cornerRY[2], vc - (h - g.cornerRY[2].toFloat())))
    // A pixel belongs to the shape when its centre does, which is the
    // same rule the circle and the polygon answer by.
    int x0 = Math.ceil(g.x0.toFloat() + lo - 0.5)
    int x1 = Math.ceil(g.x1.toFloat() - hi - 0.5)
    if x1 > x0 {
        shapeSpanStart.push(x0)
        shapeSpanEnd.push(x1)
    }
}

void func shapeSpansAt(g:ShapeGeom, y:int) {
    shapeSpanStart = []
    shapeSpanEnd = []
    if g.kind == CLIPSHAPE_RECT {
        if y < g.y0 || y >= g.y1 { return }
        if g.cornerRX.length == 0 {
            shapeSpanStart.push(g.x0)
            shapeSpanEnd.push(g.x1)
            return
        }
        shapeRectRow(g, y)
        return
    }
    float cy = y.toFloat() + 0.5
    if g.kind == CLIPSHAPE_CIRCLE || g.kind == CLIPSHAPE_ELLIPSE {
        if g.radiusX <= 0.0 || g.radiusY <= 0.0 { return }
        float dy = (cy - g.centreY) / g.radiusY
        if dy < -1.0 || dy > 1.0 { return }
        float half = g.radiusX * Math.sqrt(1.0 - dy * dy)
        shapeSpanStart.push(Math.ceil(g.centreX - half - 0.5))
        shapeSpanEnd.push(Math.floor(g.centreX + half - 0.5) + 1)
        return
    }
    if g.kind != CLIPSHAPE_POLYGON { return }
    float row = cy
    // Where the row crosses each edge, sorted, with the direction the
    // edge was travelling in beside it. The crossings alone answer
    // `evenodd` -- fill between the pairs -- and the directions answer
    // `nonzero`, which is the initial value: fill wherever the running
    // sum of the directions crossed so far is not zero. The two agree
    // on every polygon that does not cross itself, and a star is the
    // figure that separates them (todo.md).
    arr[float] hits = []
    arr[int] dirs = []
    int n = g.pointsX.length
    for int i = 0, i < n, i++ {
        int j = i + 1 < n ? i + 1 : 0
        float ay = g.pointsY[i]
        float by = g.pointsY[j]
        if ay == by { continue }
        float lo = shapeMin(ay, by)
        float hi = shapeMax(ay, by)
        if row < lo || row >= hi { continue }
        float t = (row - ay) / (by - ay)
        hits.push(g.pointsX[i] + t * (g.pointsX[j] - g.pointsX[i]))
        dirs.push(by > ay ? 1 : -1)
    }
    if hits.length < 2 { return }
    for int i = 1, i < hits.length, i++ {
        float v = hits[i]
        int d = dirs[i]
        int k = i - 1
        while k >= 0 && hits[k] > v {
            hits[k + 1] = hits[k]
            dirs[k + 1] = dirs[k]
            k--
        }
        hits[k + 1] = v
        dirs[k + 1] = d
    }
    if g.fillEvenOdd {
        for int i = 0, i + 1 < hits.length, i = i + 2 {
            shapePushSpan(hits[i], hits[i + 1])
        }
        return
    }
    // Nonzero. The span from one crossing to the next is inside when
    // the winding number there is not zero, and neighbouring inside
    // spans are joined rather than pushed separately, so a star comes
    // out as one span a row rather than three.
    int wind = 0
    float spanFrom = 0.0
    bool open = false
    for int i = 0, i + 1 < hits.length, i++ {
        wind = wind + dirs[i]
        if wind != 0 {
            if !open {
                spanFrom = hits[i]
                open = true
            }
        } else if open {
            shapePushSpan(spanFrom, hits[i])
            open = false
        }
    }
    if open { shapePushSpan(spanFrom, hits[hits.length - 1]) }
}

// ---- the exclusion edge of a float ----------------------------------
//
// A line box is a rectangle, so it must clear the widest part of
// whatever it shares a band with. The band is continuous here rather
// than a run of pixel centres: a line box from y to y+h is excluded by
// the shape's extreme anywhere in [y, y+h], endpoints included, which
// is what Chromium's own line starts show.

// One span of a row, rounded to the pixel centres it covers. Both fill
// rules push through here, so a pixel on the boundary is decided the
// same way whichever rule asked.
void func shapePushSpan(fromX:float, toX:float) {
    int lo = Math.ceil(fromX - 0.5)
    int hi = Math.floor(toX - 0.5) + 1
    if hi > lo {
        shapeSpanStart.push(lo)
        shapeSpanEnd.push(hi)
    }
}

// The furthest left and right the polygon reaches at one row.
bool polyRowHit = false
float polyRowMinX = 0.0
float polyRowMaxX = 0.0

void func polygonRowAt(g:ShapeGeom, y:float) {
    polyRowHit = false
    polyRowMinX = 0.0
    polyRowMaxX = 0.0
    int n = g.pointsX.length
    for int i = 0, i < n, i++ {
        int j = i + 1 < n ? i + 1 : 0
        float ay = g.pointsY[i]
        float by = g.pointsY[j]
        float lo = shapeMin(ay, by)
        float hi = shapeMax(ay, by)
        if y < lo || y > hi { continue }
        float x = g.pointsX[i]
        if ay != by {
            float t = (y - ay) / (by - ay)
            x = g.pointsX[i] + t * (g.pointsX[j] - g.pointsX[i])
        }
        if !polyRowHit {
            polyRowMinX = x
            polyRowMaxX = x
            polyRowHit = true
        } else {
            polyRowMinX = shapeMin(polyRowMinX, x)
            polyRowMaxX = shapeMax(polyRowMaxX, x)
        }
        // A horizontal edge lies entirely on this row, so both of its
        // ends count.
        if ay == by {
            polyRowMinX = shapeMin(polyRowMinX, g.pointsX[j])
            polyRowMaxX = shapeMax(polyRowMaxX, g.pointsX[j])
        }
    }
}

// Both answers come back in globals: whether the shape reaches the band
// at all, and how far.
bool shapeEdgeFound = false
int shapeEdgeValue = 0

// The rows a polygon's own vertices occupy, before shape-margin.
float polyLoY = 0.0
float polyHiY = 0.0

void func polygonYRange(g:ShapeGeom) {
    polyLoY = g.pointsY[0]
    polyHiY = g.pointsY[0]
    for int i = 1, i < g.pointsY.length, i++ {
        polyLoY = shapeMin(polyLoY, g.pointsY[i])
        polyHiY = shapeMax(polyHiY, g.pointsY[i])
    }
}

// Sets shapeEdgeValue to the extreme x the shape reaches anywhere in
// [top, bottom]; `wantRight` picks which extreme.
void func shapeEdgeOver(g:ShapeGeom, top:int, bottom:int, wantRight:bool) {
    shapeEdgeFound = false
    shapeEdgeValue = 0
    if bottom <= top { return }
    float ftop = top.toFloat()
    float fbottom = bottom.toFloat()
    if g.kind == CLIPSHAPE_RECT {
        if bottom <= g.y0 || top >= g.y1 { return }
        shapeEdgeValue = wantRight ? g.x1 : g.x0
        shapeEdgeFound = true
        return
    }
    if g.kind == CLIPSHAPE_CIRCLE || g.kind == CLIPSHAPE_ELLIPSE {
        if g.radiusX <= 0.0 || g.radiusY <= 0.0 { return }
        float lo = g.centreY - g.radiusY
        float hi = g.centreY + g.radiusY
        if fbottom <= lo || ftop >= hi { return }
        // The widest row of an ellipse is its centre, so the extreme
        // over a band is at whichever row in the band is nearest it.
        float row = g.centreY
        if row < ftop { row = ftop }
        if row > fbottom { row = fbottom }
        float dy = (row - g.centreY) / g.radiusY
        float half = g.radiusX * Math.sqrt(1.0 - dy * dy)
        shapeEdgeValue = Math.round(wantRight ? g.centreX + half : g.centreX - half)
        shapeEdgeFound = true
        return
    }
    if g.kind != CLIPSHAPE_POLYGON { return }
    if bottom <= g.y0 || top >= g.y1 { return }
    polygonYRange(g)
    // The extreme over a band is at one of its ends or at a vertex
    // inside it, because between vertices every edge is straight.
    arr[float] rows = []
    rows.push(shapeMax(polyLoY, shapeMin(polyHiY, ftop)))
    rows.push(shapeMax(polyLoY, shapeMin(polyHiY, fbottom)))
    for int i = 0, i < g.pointsY.length, i++ {
        if g.pointsY[i] > ftop && g.pointsY[i] < fbottom { rows.push(g.pointsY[i]) }
    }
    float best = 0.0
    for int i = 0, i < rows.length, i++ {
        polygonRowAt(g, rows[i])
        if !polyRowHit { continue }
        float v = wantRight ? polyRowMaxX : polyRowMinX
        if !shapeEdgeFound {
            best = v
            shapeEdgeFound = true
        } else if wantRight {
            best = shapeMax(best, v)
        } else {
            best = shapeMin(best, v)
        }
    }
    if !shapeEdgeFound { return }
    shapeEdgeValue = Math.round(best) + (wantRight ? g.margin : 0 - g.margin)
}

void func shapeRightEdgeOver(g:ShapeGeom, top:int, bottom:int) {
    shapeEdgeOver(g, top, bottom, true)
}

void func shapeLeftEdgeOver(g:ShapeGeom, top:int, bottom:int) {
    shapeEdgeOver(g, top, bottom, false)
}
