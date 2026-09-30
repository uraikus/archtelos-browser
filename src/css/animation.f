// CSS Animations 1: the value an animation gives a property at a moment.
//
// An animation is a function from time to computed values, and that is
// all this file is. It runs inside the cascade, after the declarations
// have been applied and before they are read: an element that names an
// animation has the animated value written over the property's entry in
// the declaration map, and everything downstream -- inheritance by the
// children, layout, painting -- sees an ordinary declaration. Nothing
// here knows about boxes.
//
// The clock is a global. The shell sets it and re-runs the cascade; a
// screenshot sets it once. Every rule below was measured against
// Chromium by pausing an animation at a chosen `currentTime` and reading
// `getComputedStyle` back (todo.md, "CSS Animations 1, measured").
//
// Reached only through `cssSawKeyframes`, so a document that declares no
// `@keyframes` never enters it.

// Milliseconds since the document was loaded.
float animationClock = 0.0

// Whether any animation computed in the last cascade can still change: one
// that is running and has not finished. The shell keeps its timer while
// this is true and drops it when it is not.
bool animLive = false

// An iteration count of `infinite`, in a float that arithmetic on stays
// finite (Festina has no infinity: 1.0 / 0.0 is nan).
const float ANIM_FOREVER = 1000000000000.0

// ---- numbers ------------------------------------------------------------

// A float as CSS text: at most four decimals, never an exponent, no
// trailing zeros. `${x}` gives six significant digits and `1e-07`, which
// no length parser reads.
text func animNum(v:float) {
    float mag = v < 0.0 ? 0.0 - v : v
    int scaled = Math.round(mag * 10000.0)
    if scaled == 0 { return '0' }
    int whole = Math.floorDiv(scaled, 10000)
    int frac = scaled - whole * 10000
    text out = v < 0.0 ? `-${whole}` : `${whole}`
    if frac > 0 {
        int digits = 4
        while digits > 0 && frac % 10 == 0 {
            frac = Math.floorDiv(frac, 10)
            digits--
        }
        text f = `${frac}`
        while f.length < digits { f = '0' + f }
        out = `${out}.${f}`
    }
    return out
}

float func animLerp(a:float, b:float, p:float) {
    return a + (b - a) * p
}

// A text lowercased and trimmed. Empty in, empty out, which an `ascii`
// round trip cannot promise (FINDINGS.md, "empty text").
text func animLower(s:text) {
    if s == null || s.length == 0 { return '' }
    ascii a = asciiLower(asciiTrim(s.toAscii()))
    if a == null || a.length == 0 { return '' }
    return a.toText()
}

// The top-level comma-separated items of a value, lowercased and trimmed.
arr[text] func animList(v:text) {
    arr[text] out = []
    if v == null || v.length == 0 { return out }
    arr[ascii] parts = splitTopLevelCommas(v.toAscii())
    for int i = 0, i < parts.length, i++ {
        ascii t = asciiTrim(parts[i])
        out.push(t.length == 0 ? '' : t.toText())
    }
    return out
}

// ---- timing functions (CSS Easing 1) ------------------------------------

const int TF_LINEAR = 0
const int TF_BEZIER = 1
const int TF_STEPS = 2
const int JUMP_START = 0
const int JUMP_END = 1
const int JUMP_NONE = 2
const int JUMP_BOTH = 3

struct Timing {
    kind:int
    x1:float
    y1:float
    x2:float
    y2:float
    n:int
    jump:int
    xs:arr[float]       // linear(): the input of each stop, ascending
    ys:arr[float]
}

map[Timing] animTimingCache = {}

Timing func animBezier(x1:float, y1:float, x2:float, y2:float) {
    Timing t
    t.kind = TF_BEZIER
    t.x1 = x1
    t.y1 = y1
    t.x2 = x2
    t.y2 = y2
    return t
}

// `linear(0, .25 75%, 1)`: stops with optional positions. A stop with no
// position takes one from its neighbours, the first defaulting to 0% and
// the last to 100%, and a position below an earlier one is raised to it.
Timing func animParseLinearStops(inner:ascii) {
    Timing t
    t.kind = TF_LINEAR
    arr[ascii] parts = splitTopLevelCommas(inner)
    arr[float] ys = []
    arr[float] xs = []
    arr[bool] has = []
    for int i = 0, i < parts.length, i++ {
        arr[ascii] toks = cssTokens(parts[i])
        if toks.length == 0 { return t }
        parseNumberAt(toks[0], 0)
        if !numOk || numEnd != toks[0].length { return t }
        ys.push(numValue)
        bool pos = false
        float x = 0.0
        if toks.length > 1 {
            ascii pt = dup(toks[1])
            parseNumberAt(pt, 0)
            if !numOk || numEnd != pt.length - 1 || pt.charCodeAt(pt.length - 1) != CH_PERCENT { return t }
            x = numValue / 100.0
            pos = true
        }
        xs.push(x)
        has.push(pos)
        if toks.length > 2 {
            // `0 25% 75%` is two stops at one output
            ascii pt2 = dup(toks[2])
            parseNumberAt(pt2, 0)
            if !numOk || numEnd != pt2.length - 1 { return t }
            ys.push(ys[ys.length - 1])
            xs.push(numValue / 100.0)
            has.push(true)
        }
    }
    if ys.length < 2 { return t }
    if !has[0] { xs[0] = 0.0  has[0] = true }
    if !has[ys.length - 1] { xs[ys.length - 1] = xs[ys.length - 1] > 1.0 ? xs[ys.length - 1] : 1.0  has[ys.length - 1] = true }
    // raise a position that runs backwards to the largest before it
    float top = xs[0]
    for int i = 1, i < ys.length, i++ {
        if has[i] {
            if xs[i] < top { xs[i] = top }
            top = xs[i]
        }
    }
    // spread the unpositioned stops evenly between their neighbours
    int i = 0
    while i < ys.length {
        if has[i] { i++  continue }
        int lo = i - 1
        int hi = i
        while hi < ys.length && !has[hi] { hi++ }
        for int k = lo + 1, k < hi, k++ {
            xs[k] = xs[lo] + (xs[hi] - xs[lo]) * (k - lo).toFloat() / (hi - lo).toFloat()
        }
        i = hi
    }
    t.xs = xs
    t.ys = ys
    return t
}

Timing func animParseTiming(spec:text) {
    Timing cached = animTimingCache[spec]
    if cached != null { return cached }
    Timing t = animBezier(0.25, 0.1, 0.25, 1.0)
    ascii a = asciiLower(asciiTrim(spec.toAscii()))
    if a == 'linear' {
        Timing lin
        lin.kind = TF_LINEAR
        t = lin
    } else if a == 'ease' {
        t = animBezier(0.25, 0.1, 0.25, 1.0)
    } else if a == 'ease-in' {
        t = animBezier(0.42, 0.0, 1.0, 1.0)
    } else if a == 'ease-out' {
        t = animBezier(0.0, 0.0, 0.58, 1.0)
    } else if a == 'ease-in-out' {
        t = animBezier(0.42, 0.0, 0.58, 1.0)
    } else if a == 'step-start' {
        Timing st
        st.kind = TF_STEPS
        st.n = 1
        st.jump = JUMP_START
        t = st
    } else if a == 'step-end' {
        Timing se
        se.kind = TF_STEPS
        se.n = 1
        se.jump = JUMP_END
        t = se
    } else if asciiStartsWith(a, 'cubic-bezier(', 0) && asciiMatchingParen(a, 12) == a.length - 1 {
        arr[ascii] args = splitTopLevelCommas(a.slice(13, a.length - 1))
        if args.length == 4 {
            arr[float] v = []
            bool ok = true
            for int i = 0, i < 4, i++ {
                parseNumberAt(asciiTrim(args[i]), 0)
                if !numOk { ok = false  break }
                v.push(numValue)
            }
            // the two x values must lie in [0, 1]
            if ok && v[0] >= 0.0 && v[0] <= 1.0 && v[2] >= 0.0 && v[2] <= 1.0 {
                t = animBezier(v[0], v[1], v[2], v[3])
            }
        }
    } else if asciiStartsWith(a, 'steps(', 0) && asciiMatchingParen(a, 5) == a.length - 1 {
        arr[ascii] args = splitTopLevelCommas(a.slice(6, a.length - 1))
        if args.length >= 1 && args.length <= 2 {
            parseNumberAt(asciiTrim(args[0]), 0)
            if numOk {
                Timing st
                st.kind = TF_STEPS
                st.n = Math.floor(numValue)
                st.jump = JUMP_END
                bool ok = st.n >= 1
                if args.length == 2 {
                    ascii pos = asciiLower(asciiTrim(args[1]))
                    if pos == 'jump-start' || pos == 'start' { st.jump = JUMP_START }
                    else if pos == 'jump-end' || pos == 'end' { st.jump = JUMP_END }
                    else if pos == 'jump-none' { st.jump = JUMP_NONE  if st.n < 2 { ok = false } }
                    else if pos == 'jump-both' { st.jump = JUMP_BOTH }
                    else { ok = false }
                }
                if ok { t = st }
            }
        }
    } else if asciiStartsWith(a, 'linear(', 0) && asciiMatchingParen(a, 6) == a.length - 1 {
        Timing lt = animParseLinearStops(a.slice(7, a.length - 1))
        if lt.xs.length >= 2 { t = lt }
    }
    animTimingCache[spec] = t
    return t
}

// x(s) or y(s) on a cubic Bezier from (0,0) to (1,1) with two control
// values.
float func animBezierAt(c1:float, c2:float, s:float) {
    float u = 1.0 - s
    return 3.0 * u * u * s * c1 + 3.0 * u * s * s * c2 + s * s * s
}

float func animTimingAt(t:Timing, x:float) {
    if t.kind == TF_LINEAR {
        if t.xs.length < 2 { return x }
        if x <= t.xs[0] { return t.ys[0] }
        int last = t.xs.length - 1
        if x >= t.xs[last] { return t.ys[last] }
        for int i = 1, i <= last, i++ {
            if x <= t.xs[i] {
                float span = t.xs[i] - t.xs[i - 1]
                if span <= 0.0 { return t.ys[i] }
                return animLerp(t.ys[i - 1], t.ys[i], (x - t.xs[i - 1]) / span)
            }
        }
        return t.ys[last]
    }
    if t.kind == TF_STEPS {
        float n = t.n.toFloat()
        int step = Math.floor(x * n + 0.000000001)
        if t.jump == JUMP_START || t.jump == JUMP_BOTH { step = step + 1 }
        float div = t.jump == JUMP_NONE ? n - 1.0 : (t.jump == JUMP_BOTH ? n + 1.0 : n)
        float out = step.toFloat() / div
        if out < 0.0 { out = 0.0 }
        if out > 1.0 { out = 1.0 }
        return out
    }
    // A Bezier: solve x(s) = x by bisection, which is safe because the
    // two control x values are in [0, 1] and so x(s) is monotonic.
    if x <= 0.0 { return 0.0 }
    if x >= 1.0 { return 1.0 }
    float lo = 0.0
    float hi = 1.0
    float s = x
    for int i = 0, i < 40, i++ {
        s = (lo + hi) / 2.0
        if animBezierAt(t.x1, t.x2, s) < x { lo = s } else { hi = s }
    }
    return animBezierAt(t.y1, t.y2, s)
}

// ---- one animation: which of its longhands applies to it ----------------

const int DIR_NORMAL = 0
const int DIR_REVERSE = 1
const int DIR_ALTERNATE = 2
const int DIR_ALT_REVERSE = 3
const int FILL_NONE = 0
const int FILL_FORWARDS = 1
const int FILL_BACKWARDS = 2
const int FILL_BOTH = 3

struct AnimSpec {
    name:text
    duration:float      // milliseconds
    timing:text
    delay:float
    count:float
    direction:int
    fill:int
    paused:bool
    composition:text    // replace, add or accumulate
}

// A time in milliseconds, or the global says it was not a time.
bool animTimeOk = false

float func animParseTime(tok:ascii) {
    animTimeOk = false
    ascii t = asciiLower(asciiTrim(tok))
    parseNumberAt(t, 0)
    if !numOk { return 0.0 }
    float v = numValue
    ascii unit = t.slice(numEnd, t.length)
    if unit == 'ms' { animTimeOk = true  return v }
    if unit == 's' { animTimeOk = true  return v * 1000.0 }
    return 0.0
}

bool func animIsTimingToken(t:ascii) {
    ascii a = asciiLower(t)
    if a == 'linear' || a == 'ease' || a == 'ease-in' || a == 'ease-out' || a == 'ease-in-out'
        || a == 'step-start' || a == 'step-end' { return true }
    return asciiStartsWith(a, 'cubic-bezier(', 0) || asciiStartsWith(a, 'steps(', 0)
        || asciiStartsWith(a, 'linear(', 0)
}

int func animDirectionOf(t:text) {
    if t == 'reverse' { return DIR_REVERSE }
    if t == 'alternate' { return DIR_ALTERNATE }
    if t == 'alternate-reverse' { return DIR_ALT_REVERSE }
    return DIR_NORMAL
}

int func animFillOf(t:text) {
    if t == 'forwards' { return FILL_FORWARDS }
    if t == 'backwards' { return FILL_BACKWARDS }
    if t == 'both' { return FILL_BOTH }
    return FILL_NONE
}

bool func animIsDirection(t:text) {
    return t == 'normal' || t == 'reverse' || t == 'alternate' || t == 'alternate-reverse'
}

bool func animIsFill(t:text) {
    return t == 'none' || t == 'forwards' || t == 'backwards' || t == 'both'
}

// The `animation` shorthand, written out as the longhands it stands for,
// so that the cascade decides between a shorthand and a longhand by
// source order (the same reason every other shorthand here is expanded).
// Each comma-separated item names one animation; its parts come in any
// order. A time goes to the duration and then the delay; a keyword goes
// to the first role it fits that is still free, which is why a name
// cannot also be `normal` or `both`; what is left over is the name. An
// item that cannot be read makes the whole declaration invalid.
void func animExpandShorthand(props:map[text], value:ascii) {
    if declIsCssWide(value) {
        arr[text] all = ['animation-name', 'animation-duration', 'animation-timing-function',
            'animation-delay', 'animation-iteration-count', 'animation-direction',
            'animation-fill-mode', 'animation-play-state']
        for int i = 0, i < all.length, i++ { props[all[i]] = dup(value) }
        return
    }
    arr[ascii] items = splitTopLevelCommas(value)
    arr[text] names = []
    arr[text] durations = []
    arr[text] timings = []
    arr[text] delays = []
    arr[text] counts = []
    arr[text] dirs = []
    arr[text] fills = []
    arr[text] states = []
    for int i = 0, i < items.length, i++ {
        arr[ascii] toks = cssTokens(items[i])
        if toks.length == 0 { return }
        text name = 'none'
        text dur = '0s'
        text easeFn = 'ease'
        text delay = '0s'
        text count = '1'
        text dir = 'normal'
        text fill = 'none'
        text state = 'running'
        bool haveName = false
        bool haveDur = false
        bool haveDelay = false
        bool haveEase = false
        bool haveCount = false
        bool haveDir = false
        bool haveFill = false
        bool haveState = false
        for int k = 0, k < toks.length, k++ {
            ascii tk = asciiLower(toks[k])
            text tt = tk.length == 0 ? '' : tk.toText()
            if tt == '' { return }
            animParseTime(tk)
            if animTimeOk {
                if !haveDur { dur = tt  haveDur = true }
                else if !haveDelay { delay = tt  haveDelay = true }
                else { return }
                continue
            }
            if animIsTimingToken(tk) {
                if haveEase { return }
                easeFn = tt
                haveEase = true
                continue
            }
            if tt == 'infinite' {
                if haveCount { return }
                count = tt
                haveCount = true
                continue
            }
            parseNumberAt(tk, 0)
            if numOk && numEnd == tk.length {
                if haveCount || numValue < 0.0 { return }
                count = tt
                haveCount = true
                continue
            }
            if animIsDirection(tt) && !haveDir { dir = tt  haveDir = true  continue }
            if animIsFill(tt) && !haveFill { fill = tt  haveFill = true  continue }
            if (tt == 'running' || tt == 'paused') && !haveState { state = tt  haveState = true  continue }
            if haveName { return }
            name = tt
            haveName = true
        }
        names.push(name)
        durations.push(dur)
        timings.push(easeFn)
        delays.push(delay)
        counts.push(count)
        dirs.push(dir)
        fills.push(fill)
        states.push(state)
    }
    props['animation-name'] = names.join(', ')
    props['animation-duration'] = durations.join(', ')
    props['animation-timing-function'] = timings.join(', ')
    props['animation-delay'] = delays.join(', ')
    props['animation-iteration-count'] = counts.join(', ')
    props['animation-direction'] = dirs.join(', ')
    props['animation-fill-mode'] = fills.join(', ')
    props['animation-play-state'] = states.join(', ')
}

// The item of a longhand's comma list an animation uses: the lists repeat
// against the name list, so a short one is cycled and a long one is cut.
text func animItem(props:map[text], prop:text, i:int, fallback:text) {
    text v = props[prop]
    if v == null { return fallback }
    arr[text] items = animList(v)
    if items.length == 0 { return fallback }
    text one = items[i % items.length]
    return one == '' ? fallback : one
}

// Every animation the element names, in order. A name that is `none` or
// has no `@keyframes` rule is dropped later, where the rule is looked up.
arr[AnimSpec] func animSpecs(props:map[text]) {
    arr[AnimSpec] out = []
    text names = props['animation-name']
    if names == null { return out }
    arr[text] list = animList(names)
    for int i = 0, i < list.length, i++ {
        if list[i] == '' || list[i] == 'none' { continue }
        AnimSpec a
        a.name = list[i]
        // A name may be a quoted string
        ascii nm = list[i].toAscii()
        if nm.length >= 2 {
            int q = nm.charCodeAt(0)
            if (q == CH_QUOTE || q == CH_APOS) && nm.charCodeAt(nm.length - 1) == q {
                a.name = nm.length == 2 ? '' : nm.slice(1, nm.length - 1).toText()
            }
        }
        a.duration = 0.0
        text d = animItem(props, 'animation-duration', i, '0s')
        float dv = animParseTime(d.toAscii())
        if animTimeOk && dv >= 0.0 { a.duration = dv }
        a.timing = animItem(props, 'animation-timing-function', i, 'ease')
        a.delay = 0.0
        text dl = animItem(props, 'animation-delay', i, '0s')
        float dlv = animParseTime(dl.toAscii())
        if animTimeOk { a.delay = dlv }
        a.count = 1.0
        text ic = animItem(props, 'animation-iteration-count', i, '1')
        if ic == 'infinite' { a.count = ANIM_FOREVER }
        else {
            parseNumberAt(ic.toAscii(), 0)
            if numOk && numValue >= 0.0 { a.count = numValue }
        }
        a.direction = animDirectionOf(animItem(props, 'animation-direction', i, 'normal'))
        a.fill = animFillOf(animItem(props, 'animation-fill-mode', i, 'none'))
        a.paused = animItem(props, 'animation-play-state', i, 'running') == 'paused'
        a.composition = animItem(props, 'animation-composition', i, 'replace')
        if a.name != '' { out.push(a) }
    }
    return out
}

// ---- time (Web Animations 1 §4, as CSS Animations 1 uses it) ------------

// Whether the animation contributes at all at this moment, and how far
// through its keyframes it is (0..1, direction applied, no timing
// function yet).
bool animEffect = false
float animProgress = 0.0

void func animLocalProgress(a:AnimSpec) {
    animEffect = false
    animProgress = 0.0
    float count = a.count
    if count <= 0.0 { return }
    bool infinite = count >= ANIM_FOREVER
    // an endless animation of no duration has nothing to be at
    if infinite && a.duration <= 0.0 { return }
    float local = (a.paused ? 0.0 : animationClock) - a.delay
    float active = infinite ? ANIM_FOREVER : a.duration * count
    if !a.paused && (infinite || local < active) { animLive = true }
    int iter = 0
    float within = 0.0
    if local < 0.0 {
        // before the active interval: only a backwards fill applies
        if a.fill != FILL_BACKWARDS && a.fill != FILL_BOTH { return }
    } else if !infinite && local >= active {
        // after it: only a forwards fill holds the last value
        if a.fill != FILL_FORWARDS && a.fill != FILL_BOTH { return }
        float whole = Math.floor(count).toFloat()
        float frac = count - whole
        if frac == 0.0 {
            iter = Math.floor(count) - 1
            within = 1.0
        } else {
            iter = Math.floor(count)
            within = frac
        }
    } else {
        float q = local / a.duration
        iter = Math.floor(q)
        within = q - iter.toFloat()
    }
    bool odd = iter % 2 == 1
    bool reversed = a.direction == DIR_REVERSE
        || (a.direction == DIR_ALTERNATE && odd)
        || (a.direction == DIR_ALT_REVERSE && !odd)
    animProgress = reversed ? 1.0 - within : within
    animEffect = true
}

// ---- keyframes, as one track per property -------------------------------

// A property's keyframes: the offsets it appears at, ascending, and the
// value and timing function it was given at each. §3.2: an interval runs
// between two keyframes *that have the property*, so height listed only
// at 50% is interpolated between the underlying value and that.
struct AnimTrack {
    offsets:arr[float]
    values:arr[text]
    timings:arr[text]   // the keyframe's own function, or '' for the animation's
    comps:arr[text]     // the keyframe's own `animation-composition`, or ''
}

struct AnimTracks {
    props:arr[text]
    tracks:arr[AnimTrack]
    defined:bool
}

map[AnimTracks] animTrackCache = {}

void func animResetCache() {
    map[AnimTracks] empty = {}
    animTrackCache = empty
}

// A property that no keyframe can animate here: the `animation-*` and
// `transition-*` families are read from the element, not the keyframe, and
// `display` does not animate in Chromium (a `block` to `none` keyframe
// reads `block` throughout, measured).
bool func animSkipsProp(k:text) {
    if k == 'display' { return true }
    return asciiStartsWith(k.toAscii(), 'animation', 0) || asciiStartsWith(k.toAscii(), 'transition', 0)
}

AnimTracks func animTracksFor(name:text) {
    AnimTracks cached = animTrackCache[name]
    if cached != null { return cached.defined ? cached : null }
    AnimTracks out
    out.defined = false
    KeyframesRule rule = cssKeyframes[name]
    if rule == null || !rule.defined {
        animTrackCache[name] = out
        return null
    }
    out.defined = true
    map[int] index = {}
    for int fi = 0, fi < rule.frames.length, fi++ {
        Keyframe f = rule.frames[fi]
        // The keyframe's declarations, written out as longhands the way a
        // rule's would be: `margin: 0 10px` is four properties.
        map[text] tmp = {}
        for int j = 0, j < f.names.length, j++ {
            text nm = f.names[j]
            if asciiStartsWith(nm.toAscii(), '--', 0) { tmp[nm] = f.values[j] }
            else { applyDecl(tmp, nm, f.values[j].toAscii()) }
        }
        arr[text] keys = tmp.keys()
        for int ki = 0, ki < keys.length, ki++ {
            text k = keys[ki]
            if animSkipsProp(k) { continue }
            text v = tmp[k]
            if v == null { continue }
            int at = index[k]
            if at == null {
                AnimTrack tr
                at = out.props.length
                index[k] = at
                out.props.push(k)
                out.tracks.push(tr)
            }
            AnimTrack track = out.tracks[at]
            int last = track.offsets.length - 1
            if last >= 0 && track.offsets[last] == f.offset {
                // a later block at the same offset wins the property
                track.values[last] = v
                track.timings[last] = f.timing
                track.comps[last] = f.composition
            } else {
                track.offsets.push(f.offset)
                track.values.push(v)
                track.timings.push(f.timing)
                track.comps.push(f.composition)
            }
        }
    }
    animTrackCache[name] = out
    return out
}

// ---- values -------------------------------------------------------------

// A colour as the `rgb()` or `rgba()` text the cascade parses back.
text func animColorText(c:int) {
    int a = colorAlpha(c)
    if a >= 255 { return `rgb(${colorRed(c)}, ${colorGreen(c)}, ${colorBlue(c)})` }
    return `rgba(${colorRed(c)}, ${colorGreen(c)}, ${colorBlue(c)}, ${animNum(a.toFloat() / 255.0)})`
}

// Two colours, premultiplied by alpha, which is how a colour fades to
// transparent without passing through black: `transparent` to red is
// `rgba(255, 0, 0, 0.25)` a quarter of the way (measured).
text func animLerpColor(ca:int, cb:int, p:float) {
    float aa = colorAlpha(ca).toFloat() / 255.0
    float ab = colorAlpha(cb).toFloat() / 255.0
    float a = animLerp(aa, ab, p)
    if a <= 0.0 { return 'rgba(0, 0, 0, 0)' }
    float r = animLerp(colorRed(ca).toFloat() * aa, colorRed(cb).toFloat() * ab, p) / a
    float g = animLerp(colorGreen(ca).toFloat() * aa, colorGreen(cb).toFloat() * ab, p) / a
    float b = animLerp(colorBlue(ca).toFloat() * aa, colorBlue(cb).toFloat() * ab, p) / a
    return animColorText(packColor(clampChannel(r), clampChannel(g), clampChannel(b), Math.round(a * 255.0)))
}

// A colour as its four channels, red, green and blue out of 255 and alpha
// out of 1, or nothing where the text is not one. An `rgb()` keeps the
// channels it was written with, past 255 included, because a sum of two
// colours is interpolated before it is clamped.
arr[float] func animRgbaOf(t:ascii, cur:int) {
    arr[float] out = []
    ascii low = asciiLower(asciiTrim(t))
    if asciiStartsWith(low, 'rgb(', 0) || asciiStartsWith(low, 'rgba(', 0) {
        int open = asciiIndexOf(low, '(', 0)
        arr[float] nums = parseColorComponents(low.slice(open + 1, low.length - 1), false)
        if nums.length >= 3 {
            out.push(nums[0])
            out.push(nums[1])
            out.push(nums[2])
            out.push(nums.length >= 4 ? nums[3] : 1.0)
            return out
        }
    }
    int c = parseCssColor(low, cur)
    if c == COLOR_UNSET { return out }
    out.push(colorRed(c).toFloat())
    out.push(colorGreen(c).toFloat())
    out.push(colorBlue(c).toFloat())
    out.push(colorAlpha(c).toFloat() / 255.0)
    return out
}

// Two colours as channels, premultiplied by alpha, which is how a colour
// fades to transparent without passing through black: `transparent` to red
// is `rgba(255, 0, 0, 0.25)` a quarter of the way (measured).
text func animLerpRgba(fa:arr[float], fb:arr[float], p:float) {
    float aa = fa[3]
    float ab = fb[3]
    float a = animLerp(aa, ab, p)
    if a <= 0.0 { return 'rgba(0, 0, 0, 0)' }
    float r = animLerp(fa[0] * aa, fb[0] * ab, p) / a
    float g = animLerp(fa[1] * aa, fb[1] * ab, p) / a
    float b = animLerp(fa[2] * aa, fb[2] * ab, p) / a
    return animColorText(packColor(clampChannel(r), clampChannel(g), clampChannel(b), Math.round(a * 255.0)))
}

// The properties whose numbers are integers.
bool func animIsIntegerProp(prop:text) {
    return prop == 'z-index' || prop == 'order' || prop == 'column-count'
        || prop == 'orphans' || prop == 'widows'
}

// Angle units to degrees, or -1 for a unit that is not one.
float func animAngleUnitDeg(unit:ascii) {
    if unit == 'deg' { return 1.0 }
    if unit == 'grad' { return 0.9 }
    if unit == 'rad' { return 180.0 / 3.14159265358979 }
    if unit == 'turn' { return 360.0 }
    return -1.0
}

bool func animIsLengthUnit(unit:ascii) {
    return unit == '' || unit == 'px' || unit == '%' || unit == 'em' || unit == 'rem'
        || unit == 'ex' || unit == 'ch' || unit == 'vw' || unit == 'vh' || unit == 'vmin'
        || unit == 'vmax' || unit == 'pt' || unit == 'pc' || unit == 'in' || unit == 'cm'
        || unit == 'mm' || unit == 'q' || unit == 'lh' || unit == 'rlh'
}

bool func animIsCalcish(t:ascii) {
    return asciiStartsWith(t, 'calc(', 0) || asciiStartsWith(t, 'min(', 0)
        || asciiStartsWith(t, 'max(', 0) || asciiStartsWith(t, 'clamp(', 0)
}

// The weights of a `calc()` that lerps two lengths: `a * (1 - p) + b * p`.
// It is written out as one expression for the length parser, which
// evaluates mixed units and a percentage the way it does any `calc()`.
text func animCalcMix(a:text, b:text, p:float) {
    return `calc((${a}) * ${animNum(1.0 - p)} + (${b}) * ${animNum(p)})`
}

// One token of a value against its counterpart, or null where the two
// cannot be interpolated and the property flips at 50% instead.
text func animLerpToken(prop:text, ta:text, tb:text, p:float, cur:int) {
    if ta == tb { return ta }
    ascii a = asciiLower(asciiTrim(ta.toAscii()))
    ascii b = asciiLower(asciiTrim(tb.toAscii()))
    if a == b { return ta }
    parseNumberAt(a, 0)
    bool aNum = numOk
    float av = numValue
    int aEnd = numEnd
    parseNumberAt(b, 0)
    bool bNum = numOk
    float bv = numValue
    int bEnd = numEnd
    if aNum && bNum {
        ascii ua = a.slice(aEnd, a.length)
        ascii ub = b.slice(bEnd, b.length)
        if ua == '' && ub == '' {
            float v = animLerp(av, bv, p)
            if animIsIntegerProp(prop) { return `${Math.round(v)}` }
            if prop == 'opacity' { v = v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v) }
            return animNum(v)
        }
        if ua == ub { return `${animNum(animLerp(av, bv, p))}${ua.toText()}` }
        float fa = animAngleUnitDeg(ua)
        float fb = animAngleUnitDeg(ub)
        if fa > 0.0 && fb > 0.0 {
            return `${animNum(animLerp(av * fa, bv * fb, p))}deg`
        }
        // a zero with no unit takes the other side's
        if ua == '' && av == 0.0 && animIsLengthUnit(ub) {
            return `${animNum(animLerp(0.0, bv, p))}${ub.toText()}`
        }
        if ub == '' && bv == 0.0 && animIsLengthUnit(ua) {
            return `${animNum(animLerp(av, 0.0, p))}${ua.toText()}`
        }
        if animIsLengthUnit(ua) && animIsLengthUnit(ub) {
            return animCalcMix(ta, tb, p)
        }
        return null
    }
    if (aNum || animIsCalcish(a)) && (bNum || animIsCalcish(b)) {
        if aNum && animIsLengthUnit(a.slice(aEnd, a.length)) == false { return null }
        if bNum && animIsLengthUnit(b.slice(bEnd, b.length)) == false { return null }
        return animCalcMix(ta, tb, p)
    }
    if aNum || bNum { return null }
    arr[float] ra = animRgbaOf(a, cur)
    arr[float] rb = animRgbaOf(b, cur)
    if ra.length == 4 && rb.length == 4 { return animLerpRgba(ra, rb, p) }
    return null
}

// A value that is one or more space-separated tokens, or a comma list of
// those, interpolated token by token. Lists of different lengths, and
// tokens that do not pair up, make the whole value discrete.
text func animLerpGeneric(prop:text, a:text, b:text, p:float, cur:int) {
    arr[ascii] la = splitTopLevelCommas(a.toAscii())
    arr[ascii] lb = splitTopLevelCommas(b.toAscii())
    if la.length != lb.length { return null }
    arr[text] items = []
    for int i = 0, i < la.length, i++ {
        arr[ascii] ta = cssTokens(la[i])
        arr[ascii] tb = cssTokens(lb[i])
        if ta.length == 0 || ta.length != tb.length { return null }
        arr[text] toks = []
        for int k = 0, k < ta.length, k++ {
            text x = ta[k].length == 0 ? '' : ta[k].toText()
            text y = tb[k].length == 0 ? '' : tb[k].toText()
            text one = animLerpToken(prop, x, y, p, cur)
            if one == null { return null }
            toks.push(one)
        }
        items.push(toks.join(' '))
    }
    return items.join(', ')
}

// ---- transform (CSS Transforms 1 §9) -------------------------------------

const int TXK_TRANSLATE = 0
const int TXK_SCALE = 1
const int TXK_ROTATE = 2

// A transform function in the one form this engine draws: a translation
// (two lengths as written), a scale (two factors) or a rotation in degrees.
struct TxFn {
    kind:int
    ax:text
    ay:text
    f1:float
    f2:float
}

// Set by animParseTransform: false where the value uses a function this
// engine does not draw (skew, matrix, anything three-dimensional), which
// leaves the property discrete.
bool animTxOk = true

TxFn func animTxIdentity(kind:int) {
    TxFn t
    t.kind = kind
    t.ax = '0px'
    t.ay = '0px'
    t.f1 = kind == TXK_SCALE ? 1.0 : 0.0
    t.f2 = t.f1
    return t
}

arr[TxFn] func animParseTransform(v:text) {
    arr[TxFn] out = []
    animTxOk = true
    ascii t = asciiTrim(v.toAscii())
    if asciiLower(t) == 'none' || t.length == 0 { return out }
    int i = 0
    while i < t.length {
        int open = asciiIndexOf(t, '(', i)
        if open < 0 { animTxOk = false  return out }
        int close = asciiMatchingParen(t, open)
        if close < 0 { animTxOk = false  return out }
        ascii name = asciiLower(asciiTrim(t.slice(i, open)))
        arr[ascii] args = splitTopLevelCommas(t.slice(open + 1, close))
        TxFn f
        f.ax = '0px'
        f.ay = '0px'
        f.f1 = 1.0
        f.f2 = 1.0
        if name == 'translate' || name == 'translatex' || name == 'translatey' {
            f.kind = TXK_TRANSLATE
            text first = asciiTrim(args[0]).length == 0 ? '0px' : asciiTrim(args[0]).toText()
            if name == 'translatey' { f.ay = first }
            else {
                f.ax = first
                if name == 'translate' && args.length > 1 && asciiTrim(args[1]).length > 0 {
                    f.ay = asciiTrim(args[1]).toText()
                }
            }
        } else if name == 'scale' || name == 'scalex' || name == 'scaley' {
            f.kind = TXK_SCALE
            parseNumberAt(asciiTrim(args[0]), 0)
            if !numOk { animTxOk = false  return out }
            float s = numValue
            float s2 = s
            if name == 'scale' && args.length > 1 {
                parseNumberAt(asciiTrim(args[1]), 0)
                if !numOk { animTxOk = false  return out }
                s2 = numValue
            }
            if name == 'scalex' { f.f1 = s  f.f2 = 1.0 }
            else if name == 'scaley' { f.f1 = 1.0  f.f2 = s }
            else { f.f1 = s  f.f2 = s2 }
        } else if name == 'rotate' || name == 'rotatez' {
            f.kind = TXK_ROTATE
            arr[bool] ok = [false]
            f.f1 = parseAngleDegrees(args[0], ok)
            if !ok[0] { animTxOk = false  return out }
        } else {
            animTxOk = false
            return out
        }
        out.push(f)
        i = close + 1
    }
    return out
}

text func animTxText(list:arr[TxFn]) {
    if list.length == 0 { return 'none' }
    arr[text] parts = []
    for int i = 0, i < list.length, i++ {
        TxFn f = list[i]
        if f.kind == TXK_TRANSLATE { parts.push(`translate(${f.ax}, ${f.ay})`) }
        else if f.kind == TXK_SCALE { parts.push(`scale(${animNum(f.f1)}, ${animNum(f.f2)})`) }
        else { parts.push(`rotate(${animNum(f.f1)}deg)`) }
    }
    return parts.join(' ')
}

// A list as one 2D matrix [a b c d e f], the product of its functions left
// to right. A translation by a percentage of the box cannot be resolved
// here, which is why `animTxPercent` is asked first.
arr[float] func animTxMatrix(list:arr[TxFn]) {
    arr[float] m = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
    for int i = 0, i < list.length, i++ {
        TxFn f = list[i]
        float a = 1.0
        float b = 0.0
        float c = 0.0
        float d = 1.0
        float e = 0.0
        float g = 0.0
        if f.kind == TXK_TRANSLATE {
            Len lx = parseLength(f.ax.toAscii(), 16)
            Len ly = parseLength(f.ay.toAscii(), 16)
            e = lx.kind == LEN_PX ? lx.v : 0.0
            g = ly.kind == LEN_PX ? ly.v : 0.0
        } else if f.kind == TXK_SCALE {
            a = f.f1
            d = f.f2
        } else {
            float r = f.f1 * 3.14159265358979 / 180.0
            a = Math.cos(r)
            b = Math.sin(r)
            c = 0.0 - Math.sin(r)
            d = Math.cos(r)
        }
        float na = m[0] * a + m[2] * b
        float nb = m[1] * a + m[3] * b
        float nc = m[0] * c + m[2] * d
        float nd = m[1] * c + m[3] * d
        float ne = m[0] * e + m[2] * g + m[4]
        float nf = m[1] * e + m[3] * g + m[5]
        m = [na, nb, nc, nd, ne, nf]
    }
    return m
}

bool func animTxHasPercent(list:arr[TxFn]) {
    for int i = 0, i < list.length, i++ {
        if list[i].kind != TXK_TRANSLATE { continue }
        if asciiIndexOf(list[i].ax.toAscii(), '%', 0) >= 0 { return true }
        if asciiIndexOf(list[i].ay.toAscii(), '%', 0) >= 0 { return true }
    }
    return false
}

// Two lists whose functions do not correspond, interpolated as matrices:
// each is decomposed into a translation, a rotation, a scale and a skew
// (Transforms 2, "Decomposing a 2D matrix"), the parts are interpolated
// and put back as the three functions this engine draws. A skew it has no
// function for leaves the value discrete.
text func animTxMatrixMix(la:arr[TxFn], lb:arr[TxFn], p:float) {
    if animTxHasPercent(la) || animTxHasPercent(lb) { return null }
    arr[float] ma = animTxMatrix(la)
    arr[float] mb = animTxMatrix(lb)
    arr[float] da = animDecompose(ma)
    arr[float] db = animDecompose(mb)
    if da.length == 0 || db.length == 0 { return null }
    // [tx, ty, angle, sx, sy, skew]
    if da[5] > 0.001 || da[5] < -0.001 || db[5] > 0.001 || db[5] < -0.001 { return null }
    float aa = da[2]
    float ab = db[2]
    if aa - ab > 180.0 { ab = ab + 360.0 }
    else if ab - aa > 180.0 { aa = aa + 360.0 }
    float tx = animLerp(da[0], db[0], p)
    float ty = animLerp(da[1], db[1], p)
    float ang = animLerp(aa, ab, p)
    float sx = animLerp(da[3], db[3], p)
    float sy = animLerp(da[4], db[4], p)
    return `translate(${animNum(tx)}px, ${animNum(ty)}px) rotate(${animNum(ang)}deg) scale(${animNum(sx)}, ${animNum(sy)})`
}

arr[float] func animDecompose(m:arr[float]) {
    arr[float] out = []
    float r0x = m[0]
    float r0y = m[1]
    float r1x = m[2]
    float r1y = m[3]
    float sx = Math.sqrt(r0x * r0x + r0y * r0y)
    if sx == 0.0 { return out }
    r0x = r0x / sx
    r0y = r0y / sx
    float skew = r0x * r1x + r0y * r1y
    r1x = r1x - r0x * skew
    r1y = r1y - r0y * skew
    float sy = Math.sqrt(r1x * r1x + r1y * r1y)
    if sy == 0.0 { return out }
    r1x = r1x / sy
    r1y = r1y / sy
    skew = skew / sy
    if r0x * r1y - r0y * r1x < 0.0 {
        sx = 0.0 - sx
        sy = 0.0 - sy
        r0x = 0.0 - r0x
        r0y = 0.0 - r0y
        skew = 0.0 - skew
    }
    float ang = Math.atan(r0y / (r0x == 0.0 ? 0.000000001 : r0x)) * 180.0 / 3.14159265358979
    if r0x < 0.0 { ang = ang + (r0y >= 0.0 ? 180.0 : -180.0) }
    else if r0x == 0.0 { ang = r0y >= 0.0 ? 90.0 : -90.0 }
    out.push(m[4])
    out.push(m[5])
    out.push(ang)
    out.push(sx)
    out.push(sy)
    out.push(skew)
    return out
}

text func animLerpTransform(a:text, b:text, p:float, cur:int) {
    arr[TxFn] la = animParseTransform(a)
    if !animTxOk { return null }
    arr[TxFn] lb = animParseTransform(b)
    if !animTxOk { return null }
    // `none` is the identity, and a list may be a prefix of the other, the
    // missing functions standing for their identities
    int common = la.length < lb.length ? la.length : lb.length
    bool paired = true
    for int i = 0, i < common, i++ {
        if la[i].kind != lb[i].kind { paired = false }
    }
    if paired {
        arr[TxFn] out = []
        int n = la.length > lb.length ? la.length : lb.length
        for int i = 0, i < n, i++ {
            TxFn x = i < la.length ? la[i] : animTxIdentity(lb[i].kind)
            TxFn y = i < lb.length ? lb[i] : animTxIdentity(la[i].kind)
            TxFn r
            r.kind = x.kind
            r.ax = '0px'
            r.ay = '0px'
            r.f1 = 1.0
            r.f2 = 1.0
            if x.kind == TXK_TRANSLATE {
                text rx = animLerpToken('', x.ax, y.ax, p, cur)
                text ry = animLerpToken('', x.ay, y.ay, p, cur)
                if rx == null || ry == null { paired = false  break }
                r.ax = rx
                r.ay = ry
            } else if x.kind == TXK_SCALE {
                r.f1 = animLerp(x.f1, y.f1, p)
                r.f2 = animLerp(x.f2, y.f2, p)
            } else {
                r.f1 = animLerp(x.f1, y.f1, p)
            }
            out.push(r)
        }
        if paired { return animTxText(out) }
    }
    return animTxMatrixMix(la, lb, p)
}

// ---- box-shadow and text-shadow -------------------------------------------

struct AnimShadow {
    inset:bool
    x:float
    y:float
    blur:float
    spread:float
    color:int
    ok:bool
}

AnimShadow func animZeroShadow(inset:bool) {
    AnimShadow s
    s.inset = inset
    s.color = COLOR_TRANSPARENT
    s.ok = true
    return s
}

// One shadow of a list: an optional `inset`, a colour anywhere, and two to
// four lengths in pixels. Anything else (an em, a var()) is not one this
// can interpolate, and the list stays discrete.
AnimShadow func animParseShadow(item:ascii, cur:int, forText:bool) {
    AnimShadow s = animZeroShadow(false)
    s.ok = false
    s.color = cur
    arr[ascii] toks = cssTokens(item)
    arr[float] lens = []
    for int i = 0, i < toks.length, i++ {
        ascii t = asciiLower(toks[i])
        if t == 'inset' { s.inset = true  continue }
        parseNumberAt(t, 0)
        if numOk {
            ascii unit = t.slice(numEnd, t.length)
            if unit != '' && unit != 'px' { return s }
            if unit == '' && numValue != 0.0 { return s }
            lens.push(numValue)
            continue
        }
        int c = parseCssColor(t, cur)
        if c == COLOR_UNSET { return s }
        s.color = c
    }
    if lens.length < 2 || lens.length > (forText ? 3 : 4) { return s }
    s.x = lens[0]
    s.y = lens[1]
    s.blur = lens.length > 2 ? lens[2] : 0.0
    s.spread = lens.length > 3 ? lens[3] : 0.0
    s.ok = true
    return s
}

text func animLerpShadows(a:text, b:text, p:float, cur:int, forText:bool) {
    arr[ascii] la = splitTopLevelCommas(a.toAscii())
    arr[ascii] lb = splitTopLevelCommas(b.toAscii())
    bool aNone = asciiLower(asciiTrim(a.toAscii())) == 'none'
    bool bNone = asciiLower(asciiTrim(b.toAscii())) == 'none'
    arr[AnimShadow] sa = []
    arr[AnimShadow] sb = []
    if !aNone {
        for int i = 0, i < la.length, i++ {
            AnimShadow s = animParseShadow(la[i], cur, forText)
            if !s.ok { return null }
            sa.push(s)
        }
    }
    if !bNone {
        for int i = 0, i < lb.length, i++ {
            AnimShadow s = animParseShadow(lb[i], cur, forText)
            if !s.ok { return null }
            sb.push(s)
        }
    }
    int n = sa.length > sb.length ? sa.length : sb.length
    if n == 0 { return 'none' }
    arr[text] out = []
    for int i = 0, i < n, i++ {
        AnimShadow x = i < sa.length ? sa[i] : animZeroShadow(i < sb.length ? sb[i].inset : false)
        AnimShadow y = i < sb.length ? sb[i] : animZeroShadow(x.inset)
        if x.inset != y.inset { return null }
        text col = animLerpColor(x.color, y.color, p)
        text one = `${col} ${animNum(animLerp(x.x, y.x, p))}px ${animNum(animLerp(x.y, y.y, p))}px ${animNum(animLerp(x.blur, y.blur, p))}px`
        if !forText { one = `${one} ${animNum(animLerp(x.spread, y.spread, p))}px` }
        if x.inset { one = `${one} inset` }
        out.push(one)
    }
    return out.join(', ')
}

// ---- filter ----------------------------------------------------------------

// The value a filter function has when it does nothing.
text func animFilterIdentity(name:text) {
    if name == 'blur' { return '0px' }
    if name == 'hue-rotate' { return '0deg' }
    if name == 'saturate' || name == 'contrast' || name == 'brightness' || name == 'opacity' { return '1' }
    return '0'
}

bool func animFilterKnown(name:text) {
    return name == 'blur' || name == 'hue-rotate' || name == 'saturate' || name == 'contrast'
        || name == 'brightness' || name == 'opacity' || name == 'grayscale' || name == 'sepia'
        || name == 'invert'
}

// `filter: a(x) b(y)` as its function names and arguments; a percentage
// argument is the number it stands for, which is how they compute.
arr[text] animFilterNames = []
arr[text] animFilterArgs = []
bool animFilterOk = true

void func animParseFilter(v:text) {
    arr[text] names = []
    arr[text] args = []
    animFilterOk = true
    ascii t = asciiTrim(v.toAscii())
    if asciiLower(t) != 'none' && t.length > 0 {
        int i = 0
        while i < t.length {
            int open = asciiIndexOf(t, '(', i)
            if open < 0 { animFilterOk = false  break }
            int close = asciiMatchingParen(t, open)
            if close < 0 { animFilterOk = false  break }
            text name = animLower(t.slice(i, open).toText())
            if !animFilterKnown(name) { animFilterOk = false  break }
            ascii inner = asciiTrim(t.slice(open + 1, close))
            text arg = animFilterIdentity(name)
            if inner.length > 0 {
                parseNumberAt(inner, 0)
                if numOk && numEnd == inner.length - 1 && inner.charCodeAt(inner.length - 1) == CH_PERCENT {
                    arg = animNum(numValue / 100.0)
                } else {
                    arg = inner.toText()
                }
            }
            names.push(name)
            args.push(arg)
            i = close + 1
        }
    }
    animFilterNames = names
    animFilterArgs = args
}

text func animLerpFilter(a:text, b:text, p:float, cur:int) {
    animParseFilter(a)
    if !animFilterOk { return null }
    arr[text] na = animFilterNames
    arr[text] xa = animFilterArgs
    animParseFilter(b)
    if !animFilterOk { return null }
    arr[text] nb = animFilterNames
    arr[text] xb = animFilterArgs
    int common = na.length < nb.length ? na.length : nb.length
    for int i = 0, i < common, i++ {
        if na[i] != nb[i] { return null }
    }
    int n = na.length > nb.length ? na.length : nb.length
    if n == 0 { return 'none' }
    arr[text] out = []
    for int i = 0, i < n, i++ {
        text name = i < na.length ? na[i] : nb[i]
        text x = i < na.length ? xa[i] : animFilterIdentity(name)
        text y = i < nb.length ? xb[i] : animFilterIdentity(name)
        text v = animLerpToken('', x, y, p, cur)
        if v == null { return null }
        out.push(`${name}(${v})`)
    }
    return out.join(' ')
}

// A ratio, `w / h` or one number, is interpolated geometrically:
// `1` to `3` is 1.732 halfway (measured), which is what makes a ratio
// halfway between 1:1 and 3:1 the same shape either way round.
float func animRatioOf(v:text) {
    arr[ascii] parts = splitTopLevelSlash(asciiTrim(v.toAscii()))
    if parts.length < 1 || parts.length > 2 { return -1.0 }
    parseNumberAt(asciiTrim(parts[0]), 0)
    if !numOk { return -1.0 }
    float w = numValue
    float h = 1.0
    if parts.length == 2 {
        parseNumberAt(asciiTrim(parts[1]), 0)
        if !numOk || numValue <= 0.0 { return -1.0 }
        h = numValue
    }
    if w <= 0.0 { return -1.0 }
    return w / h
}

text func animLerpRatio(a:text, b:text, p:float) {
    float ra = animRatioOf(a)
    float rb = animRatioOf(b)
    if ra <= 0.0 || rb <= 0.0 { return null }
    float r = Math.exp(animLerp(Math.log(ra), Math.log(rb), p))
    return `${animNum(r)} / 1`
}

// ---- composition (CSS Animations 2, `animation-composition`) -------------

// The sum of an underlying value and a keyframe's: numbers and lengths add
// (unlike units through one `calc()`), a colour adds by channel, and a
// transform list is the underlying one followed by the keyframe's. Null for
// anything else -- a keyword, `auto`, `visibility` -- which is then replaced
// rather than added to, as Chromium does. `accumulate` differs from `add`
// only in how two transform functions of one kind combine, which is
// visible in `scale`: `scale(2)` accumulated with `scale(3)` is `scale(4)`,
// where added it is `scale(6)` (measured).
text func animAddToken(prop:text, tu:text, tv:text, cur:int) {
    ascii a = asciiLower(asciiTrim(tu.toAscii()))
    ascii b = asciiLower(asciiTrim(tv.toAscii()))
    parseNumberAt(a, 0)
    bool aNum = numOk
    float av = numValue
    int aEnd = numEnd
    parseNumberAt(b, 0)
    bool bNum = numOk
    float bv = numValue
    int bEnd = numEnd
    if aNum && bNum {
        ascii ua = a.slice(aEnd, a.length)
        ascii ub = b.slice(bEnd, b.length)
        if ua == '' && ub == '' {
            float v = av + bv
            if animIsIntegerProp(prop) { return `${Math.round(v)}` }
            return animNum(v)
        }
        if ua == ub { return `${animNum(av + bv)}${ua.toText()}` }
        float fa = animAngleUnitDeg(ua)
        float fb = animAngleUnitDeg(ub)
        if fa > 0.0 && fb > 0.0 { return `${animNum(av * fa + bv * fb)}deg` }
        if ua == '' && av == 0.0 && animIsLengthUnit(ub) { return tv }
        if ub == '' && bv == 0.0 && animIsLengthUnit(ua) { return tu }
        if animIsLengthUnit(ua) && animIsLengthUnit(ub) { return `calc(${tu} + ${tv})` }
        return null
    }
    if (aNum || animIsCalcish(a)) && (bNum || animIsCalcish(b)) {
        if aNum && animIsLengthUnit(a.slice(aEnd, a.length)) == false { return null }
        if bNum && animIsLengthUnit(b.slice(bEnd, b.length)) == false { return null }
        return `calc(${tu} + ${tv})`
    }
    if aNum || bNum { return null }
    arr[float] fa2 = animRgbaOf(a, cur)
    arr[float] fb2 = animRgbaOf(b, cur)
    if fa2.length == 4 && fb2.length == 4 {
        // Not clamped: the sum is interpolated with its neighbour before it
        // is, so `250 + 50` is 300 on the way there (measured).
        float al = fa2[3] + fb2[3]
        if al > 1.0 { al = 1.0 }
        return `rgba(${animNum(fa2[0] + fb2[0])}, ${animNum(fa2[1] + fb2[1])}, ${animNum(fa2[2] + fb2[2])}, ${animNum(al)})`
    }
    return null
}

text func animAddValue(prop:text, u:text, v:text, cur:int, accumulate:bool) {
    if prop == 'transform' {
        arr[TxFn] lu = animParseTransform(u)
        if !animTxOk { return null }
        arr[TxFn] lv = animParseTransform(v)
        if !animTxOk { return null }
        arr[TxFn] both = []
        for int i = 0, i < lu.length, i++ { both.push(lu[i]) }
        for int i = 0, i < lv.length, i++ {
            TxFn f = lv[i]
            // Accumulated, a function meeting one of its own kind at the end
            // of the list is summed into it rather than following it.
            if accumulate && both.length > 0 && both[both.length - 1].kind == f.kind {
                TxFn last = both[both.length - 1]
                if f.kind == TXK_SCALE {
                    last.f1 = last.f1 + f.f1 - 1.0
                    last.f2 = last.f2 + f.f2 - 1.0
                    continue
                }
                if f.kind == TXK_ROTATE {
                    last.f1 = last.f1 + f.f1
                    continue
                }
            }
            both.push(f)
        }
        return animTxText(both)
    }
    if prop == 'visibility' || asciiStartsWith(prop.toAscii(), '--', 0) { return null }
    arr[ascii] la = splitTopLevelCommas(u.toAscii())
    arr[ascii] lb = splitTopLevelCommas(v.toAscii())
    if la.length != lb.length { return null }
    arr[text] items = []
    for int i = 0, i < la.length, i++ {
        arr[ascii] ta = cssTokens(la[i])
        arr[ascii] tb = cssTokens(lb[i])
        if ta.length == 0 || ta.length != tb.length { return null }
        arr[text] toks = []
        for int k = 0, k < ta.length, k++ {
            text x = ta[k].length == 0 ? '' : ta[k].toText()
            text y = tb[k].length == 0 ? '' : tb[k].toText()
            text one = animAddToken(prop, x, y, cur)
            if one == null { return null }
            toks.push(one)
        }
        items.push(toks.join(' '))
    }
    return items.join(', ')
}

// ---- one property, two values, a progress --------------------------------

text func animInterpolate(prop:text, a:text, b:text, p:float, cur:int) {
    if prop == 'transform' { return animLerpTransform(a, b, p, cur) }
    if prop == 'box-shadow' { return animLerpShadows(a, b, p, cur, false) }
    if prop == 'text-shadow' { return animLerpShadows(a, b, p, cur, true) }
    if prop == 'filter' || prop == 'backdrop-filter' { return animLerpFilter(a, b, p, cur) }
    if prop == 'visibility' {
        // visible for the whole of an interval where either end is
        text la = animLower(a)
        text lb = animLower(b)
        if p <= 0.0 { return a }
        if p >= 1.0 { return b }
        if la == 'visible' || lb == 'visible' { return 'visible' }
        return null
    }
    if prop == 'font-weight' {
        text wa = animLower(a)
        text wb = animLower(b)
        if wa == 'normal' { a = '400' }
        else if wa == 'bold' { a = '700' }
        if wb == 'normal' { b = '400' }
        else if wb == 'bold' { b = '700' }
    }
    if asciiStartsWith(prop.toAscii(), '--', 0) { return null }
    if prop == 'aspect-ratio' { return animLerpRatio(a, b, p) }
    return animLerpGeneric(prop, a, b, p, cur)
}

// What a property is when the cascade said nothing about it: the value an
// implicit `from` or `to` keyframe interpolates against. The inherited
// ones come from the parent, the rest are initial values; anything not
// listed is null and its missing end takes the keyframe's own value.
text func animUnderlying(prop:text, orig:map[text], parent:Style) {
    text own = orig[prop]
    if own != null { return own }
    if prop == 'opacity' || prop == 'flex-shrink' || prop == 'scale' { return '1' }
    if prop == 'flex-grow' || prop == 'order' { return '0' }
    if prop == 'width' || prop == 'height' || prop == 'top' || prop == 'right'
        || prop == 'bottom' || prop == 'left' || prop == 'flex-basis' || prop == 'z-index' { return 'auto' }
    if prop == 'min-width' || prop == 'min-height' { return '0px' }
    if prop == 'transform' || prop == 'filter' || prop == 'box-shadow' || prop == 'text-shadow' { return 'none' }
    if prop == 'background-color' { return 'transparent' }
    if prop == 'rotate' { return '0deg' }
    if prop == 'translate' { return '0px 0px' }
    if prop == 'visibility' { return 'visible' }
    if prop == 'font-weight' { return '400' }
    if asciiStartsWith(prop.toAscii(), 'margin-', 0) || asciiStartsWith(prop.toAscii(), 'padding-', 0)
        || prop == 'letter-spacing' || prop == 'word-spacing' || prop == 'outline-offset'
        || prop == 'row-gap' || prop == 'column-gap' || prop == 'text-indent' { return '0px' }
    if asciiStartsWith(prop.toAscii(), 'border-', 0) {
        if asciiIndexOf(prop.toAscii(), 'radius', 0) >= 0 { return '0px' }
        if asciiIndexOf(prop.toAscii(), 'width', 0) >= 0 { return '0px' }
    }
    if prop == 'color' { return animColorText(parent != null ? parent.color : COLOR_BLACK) }
    if prop == 'font-size' { return `${parent != null ? parent.fontSize : 16}px` }
    return null
}

// The value of one property at one progress through one animation.
text func animTrackValue(track:AnimTrack, prop:text, p:float, defaultTiming:text, defaultComp:text, underlying:text, cur:int) {
    arr[float] offs = []
    arr[text] vals = []
    arr[text] tims = []
    int n = track.offsets.length
    if n == 0 { return null }
    if track.offsets[0] > 0.0 {
        offs.push(0.0)
        vals.push(underlying == null ? track.values[0] : underlying)
        tims.push('')
    }
    for int i = 0, i < n, i++ {
        offs.push(track.offsets[i])
        // A keyframe composited with the underlying value is that value
        // plus its own; an implicit one stays the underlying value.
        text comp = track.comps[i] == '' ? defaultComp : track.comps[i]
        text composed = null
        if underlying != null && (comp == 'add' || comp == 'accumulate') {
            composed = animAddValue(prop, underlying, track.values[i], cur, comp == 'accumulate')
        }
        vals.push(composed != null ? composed : track.values[i])
        tims.push(track.timings[i])
    }
    if track.offsets[n - 1] < 1.0 {
        offs.push(1.0)
        vals.push(underlying == null ? track.values[n - 1] : underlying)
        tims.push('')
    }
    // the interval p is in: left-closed, so a keyframe's own offset gives
    // exactly its value, and the last one takes p = 1
    int at = offs.length - 2
    for int i = 0, i + 1 < offs.length, i++ {
        if p < offs[i + 1] { at = i  break }
    }
    if at < 0 { return vals[0] }
    float span = offs[at + 1] - offs[at]
    float local = span <= 0.0 ? 1.0 : (p - offs[at]) / span
    if local < 0.0 { local = 0.0 }
    if local > 1.0 { local = 1.0 }
    text fn = tims[at] == '' ? defaultTiming : tims[at]
    float eased = animTimingAt(animParseTiming(fn), local)
    text got = animInterpolate(prop, vals[at], vals[at + 1], eased, cur)
    if got != null { return got }
    return eased >= 0.5 ? vals[at + 1] : vals[at]
}

// ---- the cascade's entry ---------------------------------------------------

// Writes the animated value of every property an element's animations
// reach over the declarations it matched. Animations apply in the order
// they are listed and a later one wins the property, but each is
// interpolated against the value the cascade gave, not against an earlier
// animation's (`k, k` under `linear, ease-in` reads the ease-in one).
void func applyAnimations(props:map[text], parent:Style) {
    arr[AnimSpec] specs = animSpecs(props)
    if specs.length == 0 { return }
    map[text] orig = copyProps(props)
    int cur = COLOR_BLACK
    text own = orig['color']
    if own != null {
        int c = parseCssColor(own.toAscii(), parent != null ? parent.color : COLOR_BLACK)
        cur = c != COLOR_UNSET ? c : (parent != null ? parent.color : COLOR_BLACK)
    } else if parent != null {
        cur = parent.color
    }
    for int i = 0, i < specs.length, i++ {
        AnimSpec a = specs[i]
        AnimTracks tr = animTracksFor(a.name)
        if tr == null { continue }
        animLocalProgress(a)
        if !animEffect { continue }
        float p = animProgress
        for int k = 0, k < tr.props.length, k++ {
            text prop = tr.props[k]
            text v = animTrackValue(tr.tracks[k], prop, p, a.timing, a.composition, animUnderlying(prop, props, parent), cur)
            if v != null { props[prop] = v }
        }
    }
}
