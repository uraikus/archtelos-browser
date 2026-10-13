// CSS Easing 1: the timing functions an animation and a transition use.
// Every number is what Chromium 141 answered, read as the eased progress of
// an animation paused at each time of a 1000 ms duration
// (`el.animate([...], {duration: 1000, easing: ...})`, `pause()`,
// `currentTime = t`, `effect.getComputedTiming().progress`), to the four
// decimals it rounds to. A function Chromium refuses -- `el.animate` throws --
// must be refused here too, because a declaration that is not valid is dropped
// and the one before it stands.
//
// The second half asks the same of the cascade: what a declaration with a
// function that is not valid does, in a declaration, in a keyframe and in a
// shorthand (todo.md, "CSS Easing 1, measured").

import ../../src/browser/page.f
import ../assert.f
import ../propread.f
setClientWidth(400)

arr[float] EZ_X = [0.0, 0.05, 0.1, 0.25, 0.333, 0.5, 0.667, 0.75, 0.9, 1.0]

void func ezRow(spec:text, expected:arr[float]) {
    check(animTimingValid(spec), `${spec} is a valid timing function`)
    Timing t = animParseTiming(spec)
    for int i = 0, i < EZ_X.length, i++ {
        float got = animTimingAt(t, EZ_X[i])
        float d = got - expected[i]
        if d < 0.0 { d = 0.0 - d }
        if d <= 0.0011 { check(true, spec) }
        else { check(false, `${spec} at ${EZ_X[i]}: expected ${expected[i]}, got ${got}`) }
    }
}

void func ezInvalid(spec:text) {
    check(!animTimingValid(spec), `${spec} is not a valid timing function`)
}


// What Chromium answered: the eased progress at each of those inputs, from
// `animation.effect.getComputedTiming().progress` with the animation paused at
// each time of a 1000 ms duration.
ezRow('linear', [0.0, 0.05, 0.1, 0.25, 0.333, 0.5, 0.667, 0.75, 0.9, 1.0])
ezRow('ease', [0.0, 0.033, 0.0948, 0.4085, 0.5753, 0.8024, 0.925, 0.9605, 0.9943, 1.0])
ezRow('ease-in', [0.0, 0.0045, 0.017, 0.0935, 0.1559, 0.3154, 0.5121, 0.6219, 0.8394, 1.0])
ezRow('ease-out', [0.0, 0.0822, 0.1606, 0.3781, 0.4879, 0.6846, 0.8441, 0.9065, 0.983, 1.0])
ezRow('ease-in-out', [0.0, 0.0048, 0.0197, 0.1292, 0.2313, 0.5, 0.7687, 0.8708, 0.9803, 1.0])
ezRow('step-start', [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
ezRow('step-end', [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0])
ezRow('cubic-bezier(.1,.7,.9,.2)', [0.0, 0.1774, 0.2592, 0.378, 0.4127, 0.4625, 0.517, 0.5581, 0.6995, 1.0])
ezRow('cubic-bezier(0,0,1,1)', [0.0, 0.05, 0.1, 0.25, 0.333, 0.5, 0.667, 0.75, 0.9, 1.0])
ezRow('cubic-bezier(.5,-1,.5,2)', [0.0, -0.0895, -0.1561, -0.1823, -0.0564, 0.5, 1.0564, 1.1823, 1.1561, 1.0])
ezRow('cubic-bezier(1,0,0,1)', [0.0, 0.0009, 0.0038, 0.0297, 0.0631, 0.5, 0.9369, 0.9703, 0.9962, 1.0])
ezRow('cubic-bezier(0,0,0,0)', [0.0, 0.05, 0.1, 0.25, 0.333, 0.5, 0.667, 0.75, 0.9, 1.0])
ezRow('steps(1)', [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0])
ezRow('steps(3)', [0.0, 0.0, 0.0, 0.0, 0.0, 0.3333, 0.6667, 0.6667, 0.6667, 1.0])
ezRow('steps(3,start)', [0.3333, 0.3333, 0.3333, 0.3333, 0.3333, 0.6667, 1.0, 1.0, 1.0, 1.0])
ezRow('steps(3,end)', [0.0, 0.0, 0.0, 0.0, 0.0, 0.3333, 0.6667, 0.6667, 0.6667, 1.0])
ezRow('steps(3,jump-start)', [0.3333, 0.3333, 0.3333, 0.3333, 0.3333, 0.6667, 1.0, 1.0, 1.0, 1.0])
ezRow('steps(3,jump-end)', [0.0, 0.0, 0.0, 0.0, 0.0, 0.3333, 0.6667, 0.6667, 0.6667, 1.0])
ezRow('steps(3,jump-none)', [0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0, 1.0])
ezRow('steps(3,jump-both)', [0.25, 0.25, 0.25, 0.25, 0.25, 0.5, 0.75, 0.75, 0.75, 1.0])
ezRow('steps(1,jump-both)', [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1.0])
ezRow('steps(2,jump-none)', [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0])
ezRow('linear(0,1)', [0.0, 0.05, 0.1, 0.25, 0.333, 0.5, 0.667, 0.75, 0.9, 1.0])
ezRow('linear(0,.25 75%,1)', [0.0, 0.0167, 0.0333, 0.0833, 0.111, 0.1667, 0.2223, 0.25, 0.7, 1.0])
ezRow('linear(0 25% 75%,1)', [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 1.0])
ezRow('linear(0,.5 25% 75%,1)', [0.0, 0.1, 0.2, 0.5, 0.5, 0.5, 0.5, 0.5, 0.8, 1.0])
ezRow('linear(0,1 50%,0.2)', [0.0, 0.1, 0.2, 0.5, 0.666, 1.0, 0.7328, 0.6, 0.36, 0.2])
ezRow('linear(0 20%,1 80%)', [-0.3333, -0.25, -0.1667, 0.0833, 0.2217, 0.5, 0.7783, 0.9167, 1.1667, 1.3333])
ezRow('linear(0 50%,1 20%)', [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
ezRow('linear(0,.5,.5,1)', [0.0, 0.075, 0.15, 0.375, 0.4995, 0.5, 0.5005, 0.625, 0.85, 1.0])
ezRow('linear(0,2,0)', [0.0, 0.2, 0.4, 1.0, 1.332, 2.0, 1.332, 1.0, 0.4, 0.0])
ezRow('linear(-1,2)', [-1.0, -0.85, -0.7, -0.25, -0.001, 0.5, 1.001, 1.25, 1.7, 2.0])
ezRow('linear(0 10%,.5,1 90%)', [-0.125, -0.0625, 0.0, 0.1875, 0.2913, 0.5, 0.7088, 0.8125, 1.0, 1.125])
ezRow('linear(0,1 150%)', [0.0, 0.0333, 0.0667, 0.1667, 0.222, 0.3333, 0.4447, 0.5, 0.6, 0.6667])
ezRow('linear(0 -20%,1)', [0.1667, 0.2083, 0.25, 0.375, 0.4442, 0.5833, 0.7225, 0.7917, 0.9167, 1.0])
ezRow('linear(0 25%,0.5 25%,1)', [0.5, 0.5, 0.5, 0.5, 0.5553, 0.6667, 0.778, 0.8333, 0.9333, 1.0])
ezRow('linear(0,1 0%)', [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
ezRow('linear(0 0%, 0 100%)', [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

// And what it refused: `el.animate` throws on each of these.
ezInvalid('cubic-bezier(1.5,0,.5,1)')
ezInvalid('cubic-bezier(.2,.3,.4)')
ezInvalid('steps(0)')
ezInvalid('steps(1,jump-none)')
ezInvalid('steps(-1)')
ezInvalid('steps(2.5)')
ezInvalid('steps(3,bogus)')
ezInvalid('linear()')
ezInvalid('linear(0)')
ezInvalid('linear(1)')

// ---- in a declaration --------------------------------------------------------
//
// A declaration that is not valid is dropped whole, and what came before it
// stands. A list with one bad item is not valid either.

const text EZ_KF = '@keyframes k{from{width:0px}to{width:100px}}'

text func ezWidthAt(css:text, t:float) {
    animationClock = t
    Page p = pageFromHtml('<!doctype html><style>body{margin:0;font-size:16px}#e{width:50px;height:20px}' + css + '</style><div id="e"></div>', 'about:blank', 400)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    animationClock = 0.0
    return propText('width', all[0].style, all[0])
}

void func ezAnim(name:text, css:text, expected:arr[text]) {
    arr[float] at = [250.0, 500.0, 750.0]
    for int i = 0, i < at.length, i++ {
        text got = ezWidthAt(EZ_KF + css, at[i])
        if nearText(got, expected[i], [1.01]) { check(true, name) }
        else { checkEq(got, expected[i], `${name} at ${at[i]}ms`) }
    }
}

ezAnim('a bad function after a good one is dropped, and the good one stands',
    '#e{animation:k 1s;animation-timing-function:linear;animation-timing-function:bogus}', ['25px', '50px', '75px'])
ezAnim('a list with one bad item is dropped whole, leaving ease',
    '#e{animation:k 1s;animation-timing-function:linear,bogus}', ['40.8438px', '80.2344px', '96.0312px'])
ezAnim('a bad function in a keyframe is ignored and the animation\'s is used',
    '#e{animation:k 1s linear}@keyframes j{from{width:0px;animation-timing-function:bogus}to{width:100px}}#e{animation-name:j}', ['25px', '50px', '75px'])
ezAnim('and so is steps(2.5)',
    '#e{animation:j 1s linear}@keyframes j{from{width:0px;animation-timing-function:steps(2.5)}to{width:100px}}', ['25px', '50px', '75px'])
ezAnim('a good one in a keyframe is used',
    '#e{animation:j 1s linear}@keyframes j{from{width:0px;animation-timing-function:steps(2)}to{width:100px}}', ['0px', '50px', '50px'])
// The shorthand with a bad function is not valid, so no animation is named.
ezAnim('an animation shorthand with a bad function is dropped', '#e{animation:k 1s steps(2.5)}', ['50px', '50px', '50px'])

void func ezTransition(name:text, css:text, expected:arr[text]) {
    arr[float] at = [0.0, 500.0, 1000.0]
    for int i = 0, i < at.length, i++ {
        animationClock = 0.0
        Page p = pageFromHtml('<!doctype html><style>body{margin:0}#e{height:20px}' + css + '</style><div id="e"></div>', 'about:blank', 400)
        arr[Node] ds = []
        collectElements(p.doc, 'div', ds)
        setAttr(ds[0], 'class', 'b')
        restylePage(p, 400)
        animationClock = at[i]
        restylePage(p, 400)
        arr[Box] all = []
        collectBoxesForTag(p.root, 'div', all)
        text got = propText('width', all[0].style, all[0])
        animationClock = 0.0
        if nearText(got, expected[i], [1.01]) { check(true, name) }
        else { checkEq(got, expected[i], `${name} at ${at[i]}ms`) }
    }
}

ezTransition('a bad transition function after a good one is dropped',
    '#e{width:100px;transition:width 1s;transition-timing-function:linear;transition-timing-function:bogus}#e.b{width:200px}',
    ['100px', '150px', '200px'])
ezTransition('a transition shorthand with a bad function is dropped',
    '#e{width:100px;transition:width 1s steps(2.5)}#e.b{width:200px}', ['200px', '200px', '200px'])
ezTransition('and the earlier transition stands',
    '#e{width:100px;transition:width 1s linear;transition:width 2s steps(2.5)}#e.b{width:200px}', ['100px', '150px', '200px'])

finish('easing')
