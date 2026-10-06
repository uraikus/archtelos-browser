// CSS Transitions 1: a change of computed value under an element becomes
// a transition between the old value and the new.
//
// A transition is a function of the clock, like an animation, and this
// file shares its clock, its timing functions and its interpolation with
// animation.f. What is different is where it gets its two values. An
// animation's come from keyframes. A transition's come from two styles of
// the same element: the declared values the previous restyle saw, and the
// ones this restyle found. The previous ones are kept per element, which
// is why a document that says nothing about `transition` keeps nothing
// and never enters this file.
//
// What the rules below are is what Chromium answered, with each
// transition paused at a chosen `currentTime` (todo.md, "CSS Transitions
// 1, measured"):
//
//   * it is the *after-change* style that says which properties
//     transition and how long they take;
//   * a running transition whose end value is still the declared one
//     keeps running, one whose end value is not is cancelled, and a change
//     back to the value it started from is a *reversal*: from the current
//     value to that start, shortened by how much of the way it had got
//     (the eased progress, not the time);
//   * a property that cannot be interpolated transitions only with
//     `allow-discrete`, and then flips half way -- except `visibility`,
//     which needs no keyword, and `display`, which keeps the visible side
//     for the whole of the interval;
//   * the first style of an element has no before-change style, so
//     nothing transitions from it.
//
// The declared value, not the computed one, is what is compared: it is
// the text the cascade has in its map, and the same text is what an
// interpolated value is written back as. So `1em` and `16px` read as
// different where a browser would read them as equal -- the transition
// then runs between two values that look the same -- and an `em` length
// whose font size changes in the same restyle does not start one.

// Raised when a stylesheet or a style attribute says `transition` or
// `transition-duration`: a transition needs a duration above zero, which
// is its initial value, so a document that declares neither cannot have
// one.
bool cascadeSawTransition = false

// One item of the element's `transition-property` list, with the other
// longhands cycled against it. A shorthand name has been written out as
// the longhands it stands for, and `all` is kept as itself.
struct TrSpec {
    prop:text
    dur:float
    delay:float
    timing:text
    discrete:bool
}

// A running transition. `revStart` is the value a change back to ends it
// at (the start of the way it is on) and `gStart` how much of that way was
// already behind it when it began -- 0 for one that began from the old
// value, and for a reversal what the transition it replaced had not yet
// covered. Between them a reversal's shortening factor needs no distance:
// it is how much of the way the old transition had got.
struct TrRec {
    prop:text
    from:text
    to:text
    start:float
    dur:float
    delay:float
    timing:text
    revStart:text
    gStart:float
}

struct TrElem {
    vals:map[text]      // the declared values the last restyle found
    recs:arr[TrRec]
}

map[TrElem] trElems = {}

void func trReset() {
    map[TrElem] empty = {}
    trElems = empty
}

// ---- the shorthand ---------------------------------------------------------

// `transition`, written out as the longhands it stands for, so that the
// cascade decides between it and a longhand by source order. Each item
// names one property; its parts come in any order. A first time is the
// duration and a second the delay, `allow-discrete` and `normal` are the
// behaviour, a timing keyword or function is the timing function, and
// what is left is the property -- `all` when there is none.
void func trExpandShorthand(props:map[text], value:ascii) {
    if declIsCssWide(value) {
        arr[text] every = ['transition-property', 'transition-duration', 'transition-timing-function',
            'transition-delay', 'transition-behavior']
        for int i = 0, i < every.length, i++ { props[every[i]] = dup(value) }
        return
    }
    arr[ascii] items = splitTopLevelCommas(value)
    arr[text] names = []
    arr[text] durations = []
    arr[text] timings = []
    arr[text] delays = []
    arr[text] behaviors = []
    for int i = 0, i < items.length, i++ {
        arr[ascii] toks = cssTokens(items[i])
        if toks.length == 0 { return }
        text name = 'all'
        text dur = '0s'
        text easeFn = 'ease'
        text delay = '0s'
        text behavior = 'normal'
        bool haveName = false
        bool haveDur = false
        bool haveDelay = false
        bool haveEase = false
        bool haveBehavior = false
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
            if (tt == 'allow-discrete' || tt == 'normal') && !haveBehavior {
                behavior = tt
                haveBehavior = true
                continue
            }
            if haveName { return }
            name = tt
            haveName = true
        }
        names.push(name)
        durations.push(dur)
        timings.push(easeFn)
        delays.push(delay)
        behaviors.push(behavior)
    }
    props['transition-property'] = names.join(', ')
    props['transition-duration'] = durations.join(', ')
    props['transition-timing-function'] = timings.join(', ')
    props['transition-delay'] = delays.join(', ')
    props['transition-behavior'] = behaviors.join(', ')
}

// ---- which properties a name covers ---------------------------------------

arr[text] func trSides(prefix:text, suffix:text) {
    return [`${prefix}-top${suffix}`, `${prefix}-right${suffix}`, `${prefix}-bottom${suffix}`, `${prefix}-left${suffix}`]
}

// The longhands a name in `transition-property` stands for: itself, or,
// for a shorthand, what the cascade writes it out as (measured: `margin`
// starts four transitions and `border-radius` four).
arr[text] func trLonghands(name:text) {
    if name == 'margin' || name == 'padding' { return trSides(name, '') }
    if name == 'border-width' { return trSides('border', '-width') }
    if name == 'border-color' { return trSides('border', '-color') }
    if name == 'border-style' { return trSides('border', '-style') }
    if name == 'inset' { return ['top', 'right', 'bottom', 'left'] }
    if name == 'scroll-margin' || name == 'scroll-padding' { return trSides(name, '') }
    if name == 'border-radius' {
        return ['border-top-left-radius', 'border-top-right-radius', 'border-bottom-right-radius', 'border-bottom-left-radius']
    }
    if name == 'border-top' || name == 'border-right' || name == 'border-bottom' || name == 'border-left' {
        return [`${name}-width`, `${name}-style`, `${name}-color`]
    }
    if name == 'border' {
        arr[text] out = []
        arr[text] sides = ['top', 'right', 'bottom', 'left']
        for int i = 0, i < sides.length, i++ {
            out.push(`border-${sides[i]}-width`)
            out.push(`border-${sides[i]}-style`)
            out.push(`border-${sides[i]}-color`)
        }
        return out
    }
    if name == 'background' {
        return ['background-color', 'background-position-x', 'background-position-y', 'background-size']
    }
    if name == 'background-position' { return ['background-position-x', 'background-position-y'] }
    if name == 'gap' { return ['row-gap', 'column-gap'] }
    if name == 'flex' { return ['flex-grow', 'flex-shrink', 'flex-basis'] }
    if name == 'outline' { return ['outline-width', 'outline-style', 'outline-color'] }
    if name == 'font' { return ['font-style', 'font-weight', 'font-size', 'line-height'] }
    return [name]
}

// ---- the element's transition-* lists -------------------------------------

float func trTimeOf(t:text, fallback:float) {
    float v = animParseTime(t.toAscii())
    return animTimeOk ? v : fallback
}

arr[TrSpec] func trSpecsOf(props:map[text]) {
    arr[TrSpec] out = []
    // The duration is initially zero, so an element that never gave one
    // has nothing that can start.
    if props['transition-duration'] == null { return out }
    text names = props['transition-property']
    if names == null { names = 'all' }
    arr[text] list = animList(names)
    for int i = 0, i < list.length, i++ {
        text nm = list[i]
        if nm == '' || nm == 'none' { continue }
        float dur = trTimeOf(animItem(props, 'transition-duration', i, '0s'), 0.0)
        if dur < 0.0 { dur = 0.0 }
        float delay = trTimeOf(animItem(props, 'transition-delay', i, '0s'), 0.0)
        bool discrete = animItem(props, 'transition-behavior', i, 'normal') == 'allow-discrete'
        arr[text] targets = trLonghands(nm)
        for int k = 0, k < targets.length, k++ {
            TrSpec s
            s.prop = targets[k]
            s.dur = dur
            s.delay = delay
            // read here and not into a local above: a `text` local stored
            // into the structs of a nested loop read back as machine code
            // (FINDINGS.md, finding 43)
            s.timing = animItem(props, 'transition-timing-function', i, 'ease')
            s.discrete = discrete
            out.push(s)
        }
    }
    return out
}

// The last item that names the property, or `all`: a later one wins
// whatever it names (`color 2s, all 1s` is 1s for colour; measured).
TrSpec func trSpecFor(specs:arr[TrSpec], prop:text) {
    for int i = specs.length - 1, i >= 0, i-- {
        if specs[i].prop == 'all' || specs[i].prop == prop { return specs[i] }
    }
    return null
}

bool func trSkipsProp(k:text) {
    ascii a = k.toAscii()
    return asciiStartsWith(a, 'transition', 0) || asciiStartsWith(a, 'animation', 0)
        || asciiStartsWith(a, '--', 0)
}

// ---- values ----------------------------------------------------------------

bool func trSame(a:text, b:text) {
    if a == b { return true }
    if a == null || b == null { return false }
    return animLower(a) == animLower(b)
}

// The value part of the way through, which is `from` and `to` mixed by
// the eased progress where the property can be mixed and a flip at half
// way where it cannot. `display` keeps the visible end for the whole of
// the interval, as `visibility` does.
text func trMix(prop:text, a:text, b:text, e:float, cur:int) {
    if prop == 'display' {
        if animLower(a) == 'none' { return e > 0.0 ? b : a }
        if animLower(b) == 'none' { return e < 1.0 ? a : b }
        return e >= 0.5 ? b : a
    }
    text v = animInterpolate(prop, a, b, e, cur)
    if v != null { return v }
    return e >= 0.5 ? b : a
}

// Whether a change from one value to another starts a transition: they
// have to differ, and either mix or be allowed to flip.
bool func trCanStart(prop:text, from:text, to:text, discreteOk:bool, cur:int) {
    if trSame(from, to) { return false }
    if prop == 'display' { return discreteOk }
    text mid = animInterpolate(prop, from, to, 0.5, cur)
    if mid == null { return discreteOk }
    // two spellings of one value (`0` and `0px`) mix to the same thing at
    // both ends, and a transition between them is not a change
    text lo = animInterpolate(prop, from, to, 0.0, cur)
    text hi = animInterpolate(prop, from, to, 1.0, cur)
    if lo != null && hi != null && trSame(lo, hi) { return false }
    return true
}

float func trLocal(r:TrRec, clock:float) {
    return clock - r.start - r.delay
}

bool func trFinished(r:TrRec, clock:float) {
    return trLocal(r, clock) >= r.dur
}

// The eased progress of a transition, 0 until its delay is over.
float func trEased(r:TrRec, clock:float) {
    float local = trLocal(r, clock)
    if local < 0.0 { return 0.0 }
    if r.dur <= 0.0 || local >= r.dur { return 1.0 }
    return animTimingAt(animParseTiming(r.timing), local / r.dur)
}

text func trValueAt(r:TrRec, clock:float, cur:int) {
    float local = trLocal(r, clock)
    if local < 0.0 { return r.from }
    if r.dur <= 0.0 || local >= r.dur { return r.to }
    return trMix(r.prop, r.from, r.to, trEased(r, clock), cur)
}

// How much of the way from `revStart` to `to` the transition has covered.
float func trCovered(r:TrRec, clock:float) {
    return r.gStart + (1.0 - r.gStart) * trEased(r, clock)
}

TrRec func trStartRec(prop:text, from:text, to:text, s:TrSpec, clock:float) {
    TrRec r
    r.prop = prop
    r.from = from
    r.to = to
    r.start = clock
    r.dur = s.dur
    r.delay = s.delay
    r.timing = s.timing
    r.revStart = from
    r.gStart = 0.0
    return r
}

int func trRecIndex(el:TrElem, prop:text) {
    for int i = 0, i < el.recs.length, i++ {
        if el.recs[i].prop == prop { return i }
    }
    return -1
}

// ---- the cascade's entry ----------------------------------------------------

// Starts, keeps, reverses and cancels the element's transitions against
// what the last restyle saw, then writes the value each running one is at
// over the declaration. `props` is the declaration map the rest of the
// cascade reads, `dest` the declared values this restyle found (the same
// map unless an animation is about to be written over it). Answers
// whether the style now depends on the clock, which is what keeps it out
// of the shared style cache.
bool func applyTransitions(key:text, props:map[text], dest:map[text], parent:Style) {
    TrElem el = trElems[key]
    if el == null {
        TrElem fresh
        fresh.vals = copyProps(dest)
        fresh.recs = []
        trElems[key] = fresh
        return false
    }
    float clock = animationClock
    arr[TrSpec] specs = trSpecsOf(dest)
    int cur = COLOR_BLACK
    text own = dest['color']
    if own != null {
        int c = parseCssColor(own.toAscii(), parent != null ? parent.color : COLOR_BLACK)
        cur = c != COLOR_UNSET ? c : (parent != null ? parent.color : COLOR_BLACK)
    } else if parent != null {
        cur = parent.color
    }
    // The properties to ask about: those the list names, or every one
    // either style has when it says `all`, and those already running.
    arr[text] cands = []
    map[bool] seen = {}
    bool wantsAll = false
    for int i = 0, i < specs.length, i++ {
        if specs[i].prop == 'all' { wantsAll = true  continue }
        if seen[specs[i].prop] == null { seen[specs[i].prop] = true  cands.push(specs[i].prop) }
    }
    if wantsAll {
        arr[text] now = dest.keys()
        for int i = 0, i < now.length, i++ {
            if seen[now[i]] == null && !trSkipsProp(now[i]) { seen[now[i]] = true  cands.push(now[i]) }
        }
        arr[text] was = el.vals.keys()
        for int i = 0, i < was.length, i++ {
            if seen[was[i]] == null && !trSkipsProp(was[i]) { seen[was[i]] = true  cands.push(was[i]) }
        }
    }
    for int i = 0, i < el.recs.length, i++ {
        if seen[el.recs[i].prop] == null { seen[el.recs[i].prop] = true  cands.push(el.recs[i].prop) }
    }
    for int i = 0, i < cands.length, i++ {
        text prop = cands[i]
        if trSkipsProp(prop) { continue }
        int at = trRecIndex(el, prop)
        if at >= 0 && trFinished(el.recs[at], clock) {
            el.recs.splice(at, 1)
            at = -1
        }
        TrSpec s = trSpecFor(specs, prop)
        bool governed = s != null && s.dur + s.delay > 0.0
        if !governed {
            if at >= 0 { el.recs.splice(at, 1) }
            continue
        }
        text after = animUnderlying(prop, dest, parent)
        if after == null { continue }
        if at < 0 {
            text before = animUnderlying(prop, el.vals, parent)
            if before != null && trCanStart(prop, before, after, s.discrete, cur) {
                el.recs.push(trStartRec(prop, before, after, s, clock))
            }
            continue
        }
        TrRec old = el.recs[at]
        // still on its way to the declared value: leave it running
        if trSame(old.to, after) { continue }
        text now = trValueAt(old, clock, cur)
        float covered = trCovered(old, clock)
        bool back = trSame(after, old.revStart)
        el.recs.splice(at, 1)
        if !trCanStart(prop, now, after, s.discrete, cur) { continue }
        TrRec next = trStartRec(prop, now, after, s, clock)
        if back {
            // a reversal is as long as the way it had got, and has that
            // much less of the way left to cover
            float factor = covered < 0.0 ? 0.0 : (covered > 1.0 ? 1.0 : covered)
            next.dur = s.dur * factor
            if s.delay < 0.0 { next.delay = s.delay * factor }
            next.revStart = old.to
            next.gStart = 1.0 - covered
        }
        el.recs.push(next)
    }
    el.vals = copyProps(dest)
    bool depends = false
    for int i = 0, i < el.recs.length, i++ {
        TrRec r = el.recs[i]
        text v = trValueAt(r, clock, cur)
        if v != null { props[r.prop] = v }
        depends = true
        animLive = true
    }
    return depends
}
