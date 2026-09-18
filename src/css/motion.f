// CSS Motion Path 1: a path, and the point a given distance along it.
//
// Every path becomes a polyline, because the one thing every caller
// wants of it -- the point at an arc length -- is exact on a polyline
// and needs a numeric search on anything else. A polygon and a `path()`
// of straight commands are already polylines and lose nothing; a circle
// and an ellipse are sampled, finely enough that the error is far below
// the pixel the painter rounds to. A ray is not a polyline at all: it
// is a point and a direction, and it answers distances past its end and
// before its start, which a polyline cannot.
//
// The coordinates are the element's own. A `circle(50px at 100px
// 100px)` on a box laid out at (30, 40) has its centre at (130, 140) on
// the page -- measured, and the thing a box at the origin cannot show
// (todo.md, "What CSS Motion Path 1 was measured to be").
import style.f
import shapes.f

const int MOTION_ARC_STEPS = 720

// The answer: where the path is and which way it runs there.
float motionX = 0.0
float motionY = 0.0
float motionDeg = 0.0           // the path's direction, degrees clockwise from +x

// The built path. Festina returns one value from a function, so a
// builder that makes several of them writes them here; see FINDINGS.md,
// "one value out of a function".
arr[float] motionPX = []
arr[float] motionPY = []
arr[float] motionCum = []       // arc length at each point
float motionTotal = 0.0
bool motionClosed = false
int motionKind = MPATH_NONE
float motionRayDx = 0.0
float motionRayDy = 0.0
float motionRayLen = 0.0
float motionOrigX = 0.0
float motionOrigY = 0.0

const float MOTION_PI = 3.14159265358979

// Festina's Math has `atan` and no `atan2`, so the quadrant is put back
// by hand.
float func motionAtan2(y:float, x:float) {
    if x > 0.0 { return Math.atan(y / x) }
    if x < 0.0 {
        if y >= 0.0 { return Math.atan(y / x) + MOTION_PI }
        return Math.atan(y / x) - MOTION_PI
    }
    if y > 0.0 { return MOTION_PI / 2.0 }
    if y < 0.0 { return 0.0 - MOTION_PI / 2.0 }
    return 0.0
}

float func motionDegOf(dx:float, dy:float) {
    return motionAtan2(dy, dx) * 180.0 / MOTION_PI
}

void func motionReset() {
    motionPX = []
    motionPY = []
    motionCum = []
    motionTotal = 0.0
    motionClosed = false
    motionKind = MPATH_NONE
}

// The start of a subpath: the point joins the polyline without the gap
// to it counting as length, so a distance walks the subpaths in order
// and never crosses between them (todo.md has Chromium's numbers).
void func motionMoveTo(x:float, y:float) {
    motionPX.push(x)
    motionPY.push(y)
    motionCum.push(motionTotal)
}

void func motionAddPoint(x:float, y:float) {
    if motionPX.length > 0 {
        float dx = x - motionPX[motionPX.length - 1]
        float dy = y - motionPY[motionPY.length - 1]
        motionTotal = motionTotal + Math.sqrt(dx * dx + dy * dy)
    }
    motionPX.push(x)
    motionPY.push(y)
    motionCum.push(motionTotal)
}

// ---- the shapes ----------------------------------------------------------

// A circle and an ellipse both start at three o'clock and run
// clockwise, which is what Chromium does and not what a reading that
// starts a circle at the top expects. On screen y grows downward, so
// clockwise is `(cos t, sin t)` with t increasing.
void func motionArc(cx:float, cy:float, rx:float, ry:float) {
    for int i = 0, i <= MOTION_ARC_STEPS, i++ {
        float t = 2.0 * MOTION_PI * i.toFloat() / MOTION_ARC_STEPS.toFloat()
        motionAddPoint(cx + rx * Math.cos(t), cy + ry * Math.sin(t))
    }
    motionClosed = true
}

void func motionPolygon(sh:ClipShape, bw:int, bh:int) {
    for int i = 0, i < sh.pointsX.length, i++ {
        motionAddPoint(resolveLen(sh.pointsX[i], bw, 0).toFloat(),
                       resolveLen(sh.pointsY[i], bh, 0).toFloat())
    }
    // A polygon closes itself: nine tenths of the way round
    // `polygon(0 0, 100px 0, 100px 100px)` is on the edge back to the
    // first point, which only exists if it is drawn.
    if motionPX.length > 1 { motionAddPoint(motionPX[0], motionPY[0]) }
    motionClosed = true
}

// ---- path() --------------------------------------------------------------

int motionScanAt = 0
float motionScanNum = 0.0

bool func motionIsNumChar(c:int) {
    return (c >= CH_0 && c <= CH_9) || c == CH_DOT || c == CH_MINUS || c == CH_PLUS
        || c == 101 || c == 69
}

// Reads the next number of the path data, leaving `motionScanAt` past
// it. Returns false at the end or on anything that is not one.
bool func motionReadNum(d:ascii) {
    while motionScanAt < d.length {
        int c = d.charCodeAt(motionScanAt)
        if isSpaceCode(c) || c == CH_COMMA { motionScanAt++ } else { break }
    }
    if motionScanAt >= d.length { return false }
    int start = motionScanAt
    int c0 = d.charCodeAt(motionScanAt)
    if c0 == CH_MINUS || c0 == CH_PLUS { motionScanAt++ }
    bool any = false
    while motionScanAt < d.length {
        int c = d.charCodeAt(motionScanAt)
        if (c >= CH_0 && c <= CH_9) || c == CH_DOT { motionScanAt++  any = true } else { break }
    }
    if !any { motionScanAt = start  return false }
    motionScanNum = parseFloatAscii(d.slice(start, motionScanAt))
    return true
}

// `M`, `L`, `H`, `V` and `Z`, in either case, which is every command
// that draws a straight line. A curve command ends the path where it
// stands rather than being guessed at (css-2026.md records it).
// The control point the last curve used, and which kind it was, so
// that `S` and `T` can reflect it. A command that is neither leaves
// both false, which makes the reflection the current point itself.
// How many subpaths the path has. A distance wraps round a path that is
// one closed subpath and clamps at the ends of anything else, which is
// measured rather than assumed (todo.md).
int motionSubpaths = 1

float motionCtrlX = 0.0
float motionCtrlY = 0.0
bool motionPrevCubic = false
bool motionPrevQuad = false

// How many segments a curve becomes. The polyline they join is what the
// arc-length lookup walks, so this is the accuracy of every distance
// along the curve as well as of its shape; sixty-four holds a hundred
// pixel curve to well under a pixel.
const int MOTION_CURVE_STEPS = 64

// One cubic Bézier, flattened into the polyline.
void func motionCubic(x0:float, y0:float, x1:float, y1:float,
                      x2:float, y2:float, x3:float, y3:float) {
    for int i = 1, i <= MOTION_CURVE_STEPS, i++ {
        float t = i.toFloat() / MOTION_CURVE_STEPS.toFloat()
        float u = 1.0 - t
        float a = u * u * u
        float b = 3.0 * u * u * t
        float c = 3.0 * u * t * t
        float e = t * t * t
        motionAddPoint(a * x0 + b * x1 + c * x2 + e * x3,
                       a * y0 + b * y1 + c * y2 + e * y3)
    }
}

// An elliptical arc, from its two endpoints to its centre and the two
// angles it runs between (SVG 1.1 §F.6.5), then flattened. A radius of
// zero, or two endpoints in the same place, is a straight line.
void func motionArcTo(x0:float, y0:float, rxIn:float, ryIn:float, rotDeg:float,
                      large:bool, sweep:bool, x1:float, y1:float) {
    float rx = rxIn < 0.0 ? 0.0 - rxIn : rxIn
    float ry = ryIn < 0.0 ? 0.0 - ryIn : ryIn
    if rx == 0.0 || ry == 0.0 || (x0 == x1 && y0 == y1) {
        motionAddPoint(x1, y1)
        return
    }
    float phi = rotDeg * 3.14159265358979 / 180.0
    float cosPhi = Math.cos(phi)
    float sinPhi = Math.sin(phi)
    // The endpoints in the ellipse's own frame, halfway between them.
    float dx2 = (x0 - x1) / 2.0
    float dy2 = (y0 - y1) / 2.0
    float px = cosPhi * dx2 + sinPhi * dy2
    float py = 0.0 - sinPhi * dx2 + cosPhi * dy2
    // Radii too small for the chord are scaled up until they fit, which
    // the standard asks for rather than treating the arc as invalid.
    float lam = (px * px) / (rx * rx) + (py * py) / (ry * ry)
    if lam > 1.0 {
        float grow = Math.sqrt(lam)
        rx = rx * grow
        ry = ry * grow
    }
    float num = rx * rx * ry * ry - rx * rx * py * py - ry * ry * px * px
    float den = rx * rx * py * py + ry * ry * px * px
    float scale = den == 0.0 ? 0.0 : Math.sqrt(num < 0.0 ? 0.0 : num / den)
    if large == sweep { scale = 0.0 - scale }
    float cxp = scale * rx * py / ry
    float cyp = 0.0 - scale * ry * px / rx
    float centreX = cosPhi * cxp - sinPhi * cyp + (x0 + x1) / 2.0
    float centreY = sinPhi * cxp + cosPhi * cyp + (y0 + y1) / 2.0
    float startAng = motionAtan2((py - cyp) / ry, (px - cxp) / rx)
    float endAng = motionAtan2((0.0 - py - cyp) / ry, (0.0 - px - cxp) / rx)
    float sweepAng = endAng - startAng
    float TAU = 6.28318530717959
    if !sweep && sweepAng > 0.0 { sweepAng = sweepAng - TAU }
    if sweep && sweepAng < 0.0 { sweepAng = sweepAng + TAU }
    for int i = 1, i <= MOTION_CURVE_STEPS, i++ {
        float ang = startAng + sweepAng * i.toFloat() / MOTION_CURVE_STEPS.toFloat()
        float ex = rx * Math.cos(ang)
        float ey = ry * Math.sin(ang)
        motionAddPoint(centreX + cosPhi * ex - sinPhi * ey,
                       centreY + sinPhi * ex + cosPhi * ey)
    }
}

void func motionPathData(data:text) {
    ascii d = data.toAscii()
    motionScanAt = 0
    motionPrevCubic = false
    motionPrevQuad = false
    motionSubpaths = 1
    float cx = 0.0
    float cy = 0.0
    float startX = 0.0
    float startY = 0.0
    bool started = false
    while motionScanAt < d.length {
        int c = d.charCodeAt(motionScanAt)
        if isSpaceCode(c) || c == CH_COMMA { motionScanAt++  continue }
        motionScanAt++
        bool rel = c >= 97 && c <= 122
        int cmd = rel ? c - 32 : c
        if cmd == 90 {                                  // Z
            // `Z` closes the subpath it is in, which is a leg back to
            // that subpath's own start rather than to the path's.
            if started {
                motionAddPoint(startX, startY)
                cx = startX
                cy = startY
                motionClosed = true
            }
            continue
        }
        if cmd == 77 || cmd == 76 {                     // M, L
            bool first = true
            while true {
                if !motionReadNum(d) { break }
                float x = motionScanNum
                if !motionReadNum(d) { break }
                float y = motionScanNum
                cx = rel ? cx + x : x
                cy = rel ? cy + y : y
                // Only the first pair of an `M` moves; the ones after
                // it are a line, which is what SVG §8.3.2 says and what
                // `M 0 60 100 60` reads as.
                if cmd == 77 && first {
                    if started { motionSubpaths++ }
                    motionMoveTo(cx, cy)
                    startX = cx
                    startY = cy
                } else {
                    motionAddPoint(cx, cy)
                }
                if !started { startX = cx  startY = cy  started = true }
                first = false
            }
            continue
        }
        if cmd == 72 || cmd == 86 {                     // H, V
            while motionReadNum(d) {
                if cmd == 72 { cx = rel ? cx + motionScanNum : motionScanNum }
                else { cy = rel ? cy + motionScanNum : motionScanNum }
                motionAddPoint(cx, cy)
                if !started { startX = cx  startY = cy  started = true }
            }
            continue
        }
        if cmd == 67 || cmd == 83 {                     // C, S
            while true {
                float x1 = 0.0
                float y1 = 0.0
                if cmd == 67 {
                    if !motionReadNum(d) { break }
                    x1 = rel ? cx + motionScanNum : motionScanNum
                    if !motionReadNum(d) { break }
                    y1 = rel ? cy + motionScanNum : motionScanNum
                } else {
                    // `S` takes the reflection of the previous cubic's
                    // second control point about the current point, and
                    // the current point itself where the command before
                    // was not a cubic (SVG §8.3.6).
                    x1 = motionPrevCubic ? cx + cx - motionCtrlX : cx
                    y1 = motionPrevCubic ? cy + cy - motionCtrlY : cy
                }
                if !motionReadNum(d) { break }
                float x2 = rel ? cx + motionScanNum : motionScanNum
                if !motionReadNum(d) { break }
                float y2 = rel ? cy + motionScanNum : motionScanNum
                if !motionReadNum(d) { break }
                float ex = rel ? cx + motionScanNum : motionScanNum
                if !motionReadNum(d) { break }
                float ey = rel ? cy + motionScanNum : motionScanNum
                if !started { motionAddPoint(cx, cy)  startX = cx  startY = cy  started = true }
                motionCubic(cx, cy, x1, y1, x2, y2, ex, ey)
                motionCtrlX = x2
                motionCtrlY = y2
                motionPrevCubic = true
                motionPrevQuad = false
                cx = ex
                cy = ey
            }
            continue
        }
        if cmd == 81 || cmd == 84 {                     // Q, T
            while true {
                float x1 = 0.0
                float y1 = 0.0
                if cmd == 81 {
                    if !motionReadNum(d) { break }
                    x1 = rel ? cx + motionScanNum : motionScanNum
                    if !motionReadNum(d) { break }
                    y1 = rel ? cy + motionScanNum : motionScanNum
                } else {
                    x1 = motionPrevQuad ? cx + cx - motionCtrlX : cx
                    y1 = motionPrevQuad ? cy + cy - motionCtrlY : cy
                }
                if !motionReadNum(d) { break }
                float ex = rel ? cx + motionScanNum : motionScanNum
                if !motionReadNum(d) { break }
                float ey = rel ? cy + motionScanNum : motionScanNum
                if !started { motionAddPoint(cx, cy)  startX = cx  startY = cy  started = true }
                // A quadratic is the cubic whose controls are two
                // thirds of the way from each end to it, so there is
                // one sampler rather than two.
                motionCubic(cx, cy,
                            cx + 2.0 * (x1 - cx) / 3.0, cy + 2.0 * (y1 - cy) / 3.0,
                            ex + 2.0 * (x1 - ex) / 3.0, ey + 2.0 * (y1 - ey) / 3.0,
                            ex, ey)
                motionCtrlX = x1
                motionCtrlY = y1
                motionPrevQuad = true
                motionPrevCubic = false
                cx = ex
                cy = ey
            }
            continue
        }
        if cmd == 65 {                                  // A
            while true {
                if !motionReadNum(d) { break }
                float rx = motionScanNum
                if !motionReadNum(d) { break }
                float ry = motionScanNum
                if !motionReadNum(d) { break }
                float rot = motionScanNum
                if !motionReadNum(d) { break }
                bool large = motionScanNum != 0.0
                if !motionReadNum(d) { break }
                bool sweep = motionScanNum != 0.0
                if !motionReadNum(d) { break }
                float ex = rel ? cx + motionScanNum : motionScanNum
                if !motionReadNum(d) { break }
                float ey = rel ? cy + motionScanNum : motionScanNum
                if !started { motionAddPoint(cx, cy)  startX = cx  startY = cy  started = true }
                motionArcTo(cx, cy, rx, ry, rot, large, sweep, ex, ey)
                motionPrevCubic = false
                motionPrevQuad = false
                cx = ex
                cy = ey
            }
            continue
        }
        break                                           // an unknown command
    }
}

// ---- ray() ---------------------------------------------------------------

// The reference rectangle in the element's own coordinates: the
// containing block's corner is as far back as the element sits inside
// it.
float func motionRaySize(size:int, ox:float, oy:float,
                         bx:float, by:float, bw:float, bh:float) {
    float l = ox - bx
    float r = bx + bw - ox
    float t = oy - by
    float b = by + bh - oy
    if size == RAYSIZE_CLOSEST_SIDE || size == RAYSIZE_FARTHEST_SIDE {
        float best = l
        if size == RAYSIZE_CLOSEST_SIDE {
            if r < best { best = r }
            if t < best { best = t }
            if b < best { best = b }
        } else {
            if r > best { best = r }
            if t > best { best = t }
            if b > best { best = b }
        }
        return best < 0.0 ? 0.0 : best
    }
    if size == RAYSIZE_CLOSEST_CORNER || size == RAYSIZE_FARTHEST_CORNER {
        float best = -1.0
        for int i = 0, i < 4, i++ {
            float px = i == 0 || i == 2 ? bx : bx + bw
            float py = i < 2 ? by : by + bh
            float dx = px - ox
            float dy = py - oy
            float d = Math.sqrt(dx * dx + dy * dy)
            if best < 0.0 { best = d }
            else if size == RAYSIZE_CLOSEST_CORNER { if d < best { best = d } }
            else { if d > best { best = d } }
        }
        return best < 0.0 ? 0.0 : best
    }
    // `sides`: how far the ray itself reaches before leaving the box.
    float best = -1.0
    if motionRayDx > 0.0001 { best = r / motionRayDx }
    else if motionRayDx < -0.0001 { best = l / (0.0 - motionRayDx) }
    if motionRayDy > 0.0001 {
        float d = b / motionRayDy
        if best < 0.0 || d < best { best = d }
    } else if motionRayDy < -0.0001 {
        float d = t / (0.0 - motionRayDy)
        if best < 0.0 || d < best { best = d }
    }
    return best < 0.0 ? 0.0 : best
}

// ---- building and sampling ----------------------------------------------

// `bw` and `bh` are the box the path's percentages resolve against, and
// `ex`/`ey` how far the element sits inside it.
void func motionBuild(mi:MotionInfo, ex:int, ey:int, bw:int, bh:int) {
    motionReset()
    if mi == null || mi.pathKind == MPATH_NONE { return }
    motionKind = mi.pathKind
    motionOrigX = mi.posNormal ? 0.0 : resolveLen(mi.posX, bw, 0).toFloat()
    motionOrigY = mi.posNormal ? 0.0 : resolveLen(mi.posY, bh, 0).toFloat()
    if mi.pathKind == MPATH_RAY {
        // 0deg points up, and the angle runs clockwise from there.
        float t = mi.rayAngle * MOTION_PI / 180.0
        motionRayDx = Math.sin(t)
        motionRayDy = 0.0 - Math.cos(t)
        motionRayLen = motionRaySize(mi.raySize, motionOrigX, motionOrigY,
                                     0.0 - ex.toFloat(), 0.0 - ey.toFloat(),
                                     bw.toFloat(), bh.toFloat())
        return
    }
    if mi.pathKind == MPATH_PATH {
        motionPathData(mi.pathData)
        return
    }
    ClipShape sh = mi.shape
    if sh.kind == CLIPSHAPE_CIRCLE || sh.kind == CLIPSHAPE_ELLIPSE {
        float cx = resolveLen(sh.centreX, bw, Math.floorDiv(bw, 2)).toFloat()
        float cy = resolveLen(sh.centreY, bh, Math.floorDiv(bh, 2)).toFloat()
        // A circle's one radius serves both axes.
        float rx = shapeRadius(sh.radiusX, sh.radiusXKind, bw, cx, 0.0, bw.toFloat())
        float ry = sh.kind == CLIPSHAPE_CIRCLE ? rx
            : shapeRadius(sh.radiusY, sh.radiusYKind, bh, cy, 0.0, bh.toFloat())
        motionArc(cx, cy, rx, ry)
        return
    }
    if sh.kind == CLIPSHAPE_POLYGON { motionPolygon(sh, bw, bh) }
}

// Where the built path is at `dist`, and which way it runs there.
// A closed path wraps -- 125% of a circle is 25% of it -- and an open
// one stops at each end, except a ray, which runs on in both
// directions.
void func motionAt(dist:float) {
    motionX = 0.0
    motionY = 0.0
    motionDeg = 0.0
    if motionKind == MPATH_RAY {
        motionX = motionOrigX + motionRayDx * dist
        motionY = motionOrigY + motionRayDy * dist
        motionDeg = motionDegOf(motionRayDx, motionRayDy)
        return
    }
    if motionPX.length == 0 { return }
    if motionPX.length == 1 || motionTotal <= 0.0 {
        motionX = motionPX[0]
        motionY = motionPY[0]
        return
    }
    float d = dist
    if motionClosed && motionSubpaths == 1 {
        d = d - motionTotal * Math.floor(d / motionTotal)
    } else if d < 0.0 {
        d = 0.0
    } else if d > motionTotal {
        d = motionTotal
    }
    int lo = 0
    int hi = motionCum.length - 1
    while lo < hi - 1 {
        int mid = Math.floorDiv(lo + hi, 2)
        if motionCum[mid] <= d { lo = mid } else { hi = mid }
    }
    // A distance that lands exactly on the join between two subpaths
    // belongs to the one before it rather than the one after, which is
    // what Chromium answers. The search takes the last index whose
    // distance is not past `d`, so at a join that is the start of the
    // next subpath; stepping back over the gap -- a segment of no
    // length -- puts it on the end of the one before.
    while lo > 0 && motionCum[lo] == motionCum[lo - 1] && d <= motionCum[lo] {
        lo = lo - 1
    }
    float seg = motionCum[lo + 1] - motionCum[lo]
    float f = seg <= 0.0 ? 0.0 : (d - motionCum[lo]) / seg
    float dx = motionPX[lo + 1] - motionPX[lo]
    float dy = motionPY[lo + 1] - motionPY[lo]
    motionX = motionPX[lo] + dx * f
    motionY = motionPY[lo] + dy * f
    motionDeg = motionDegOf(dx, dy)
}

// The distance `offset-distance` asks for. A percentage is of the
// path's own length, and of the ray's for a ray.
float func motionDistance(mi:MotionInfo) {
    Len l = mi.distance
    if l == null || l.kind == LEN_AUTO { return 0.0 }
    float base = motionKind == MPATH_RAY ? motionRayLen : motionTotal
    if l.kind == LEN_PERCENT { return base * l.v / 100.0 }
    if l.kind == LEN_CALC { return l.v + base * l.pct / 100.0 }
    return l.v
}

// How far the box turns: the path's own direction under `auto`, that
// direction reversed under `reverse`, or nothing but the angle written.
float func motionRotation(mi:MotionInfo) {
    if mi.rotateMode == MROT_ANGLE { return mi.rotateAngle }
    if mi.rotateMode == MROT_REVERSE { return motionDeg + 180.0 + mi.rotateAngle }
    return motionDeg + mi.rotateAngle
}
