// CSS Transitions 1: a change of computed value under an element becomes
// a transition between the old value and the new. Every expectation is
// what Chromium 141 answered with each transition paused at a chosen
// `currentTime` (`getAnimations()`, `pause()`, `currentTime = t`) and the
// property read back through getComputedStyle; the rows are in todo.md,
// "CSS Transitions 1, measured".
//
// A transition is a function of the clock, like an animation, and what
// starts one is a restyle that finds a value different from the one the
// last restyle saw. So a state here is a short script: the document is
// styled at clock 0, a class changes at some clock and the document is
// styled again, and then the clock moves and it is styled once more,
// which is what the shell does.
//
// The page has a single `<div id="e">` unless a case supplies its own
// markup, with `margin: 0` and a 20px-high box so that a length is read
// off the box it makes.

import ../../src/browser/page.f
import ../assert.f
import ../propread.f
setClientWidth(400)

const text TR_BASE = 'body{margin:0;font-size:16px}#e{height:20px}'

Node func trNode(p:Page, id:text) {
    arr[text] tags = ['div', 'span']
    for int t = 0, t < tags.length, t++ {
        arr[Node] all = []
        collectElements(p.doc, tags[t], all)
        for int i = 0, i < all.length, i++ {
            if getAttr(all[i], 'id') == id { return all[i] }
        }
    }
    return null
}

void func trRestyle(p:Page, clock:float) {
    animationClock = clock
    restylePage(p, 400)
}

void func trSetClass(p:Page, id:text, cls:text, clock:float) {
    Node n = trNode(p, id)
    setAttr(n, 'class', cls)
    trRestyle(p, clock)
}

// The first document: styled once at clock 0 with `e` carrying `first`,
// which is where a first style of a page is taken.
Page func trPage(css:text, html:text) {
    animationClock = 0.0
    return pageFromHtml(`<!doctype html><style>${TR_BASE}${css}</style>${html}`, 'about:blank', 400)
}

text func trRead(p:Page, id:text, prop:text) {
    Node n = trNode(p, id)
    arr[Box] boxes = []
    collectBoxesForTag(p.root, n.tag, boxes)
    Box b = null
    for int i = 0, i < boxes.length, i++ {
        if getAttr(boxes[i].node, 'id') == id { b = boxes[i] }
    }
    if prop == 'display' { return propText(prop, n.style, b) }
    if b == null { return 'none' }
    return propText(prop, b.style, b)
}

// `cls` is applied at clock 0; then, if `at2` is not negative, `cls2` is
// applied at that clock; and the answer is read `t` milliseconds after the
// last change.
text func trState(css:text, html:text, cls:text, at2:float, cls2:text, t:float, prop:text) {
    Page p = trPage(css, html)
    trSetClass(p, 'e', cls, 0.0)
    float base = 0.0
    if at2 >= 0.0 {
        trRestyle(p, at2)
        trSetClass(p, 'e', cls2, at2)
        base = at2
    }
    trRestyle(p, base + t)
    return trRead(p, 'e', prop)
}

const text TR_DIV = '<div id="e"></div>'

void func trRow(name:text, css:text, t:float, prop:text, expected:text, tol:float) {
    text got = trState(css, TR_DIV, 'b', -1.0, '', t, prop)
    if nearText(got, expected, [tol]) { check(true, name) }
    else { checkEq(got, expected, `${name} at ${t}ms`) }
}

void func trSeries(name:text, css:text, prop:text, times:arr[float], expected:arr[text], tol:float) {
    for int i = 0, i < times.length, i++ { trRow(name, css, times[i], prop, expected[i], tol) }
}

// ---- the curves ------------------------------------------------------------
//
// The same four timing functions the animation suite checks, one-pixel
// tolerance, over a 100px change.

text WIDTH = '#e{width:100px;transition:width 1s TIMING}#e.b{width:200px}'
arr[float] T7 = [0.0, 100.0, 250.0, 500.0, 750.0, 900.0, 1000.0]

trSeries('ease', '#e{width:100px;transition:width 1s}#e.b{width:200px}', 'width', T7,
    ['100px', '109.469px', '140.844px', '180.234px', '196.031px', '199.422px', '200px'], 1.01)
trSeries('linear', '#e{width:100px;transition:width 1s linear}#e.b{width:200px}', 'width', T7,
    ['100px', '110px', '125px', '150px', '175px', '190px', '200px'], 1.01)
trSeries('ease-in-out', '#e{width:100px;transition:width 1s ease-in-out}#e.b{width:200px}', 'width', T7,
    ['100px', '101.969px', '112.906px', '150px', '187.078px', '198.016px', '200px'], 1.01)
trSeries('steps(4)', '#e{width:100px;transition:width 1s steps(4)}#e.b{width:200px}', 'width', T7,
    ['100px', '100px', '125px', '150px', '175px', '175px', '200px'], 1.01)
trRow('after the end the value stays', '#e{width:100px;transition:width 1s linear}#e.b{width:200px}', 1500.0, 'width', '200px', 1.01)

// ---- delay -------------------------------------------------------------------

arr[float] TD = [0.0, 250.0, 500.0, 750.0, 1000.0, 1500.0]
trSeries('delay holds the old value', '#e{width:100px;transition:width 1s linear .5s}#e.b{width:200px}', 'width', TD,
    ['100px', '100px', '100px', '125px', '150px', '200px'], 1.01)
trSeries('a negative delay starts part-way', '#e{width:100px;transition:width 1s linear -.5s}#e.b{width:200px}', 'width',
    [0.0, 250.0, 500.0], ['150px', '175px', '200px'], 1.01)
trSeries('a zero duration with a delay jumps at the delay', '#e{width:100px;transition:width 0s 1s}#e.b{width:200px}', 'width',
    [0.0, 500.0, 999.0, 1000.0, 1100.0], ['100px', '100px', '100px', '200px', '200px'], 1.01)
trRow('a zero duration starts nothing', '#e{width:100px;transition:width 0s}#e.b{width:200px}', 0.0, 'width', '200px', 1.01)

// ---- what is interpolated ----------------------------------------------------

arr[float] T4 = [0.0, 250.0, 500.0, 1000.0]
trSeries('opacity', '#e{opacity:0;transition:opacity 1s linear}#e.b{opacity:1}', 'opacity', T4,
    ['0', '0.25', '0.5', '1'], 0.02)
trSeries('colour', '#e{color:rgb(0,0,0);transition:color 1s linear}#e.b{color:rgb(200,100,50)}', 'color', T4,
    ['rgb(0, 0, 0)', 'rgb(50, 25, 13)', 'rgb(100, 50, 25)', 'rgb(200, 100, 50)'], 1.6)
trSeries('background colour', '#e{background-color:rgb(255,0,0);transition:background-color 1s linear}#e.b{background-color:rgb(0,0,255)}', 'background-color', T4,
    ['rgb(255, 0, 0)', 'rgb(191, 0, 64)', 'rgb(128, 0, 128)', 'rgb(0, 0, 255)'], 1.6)
trSeries('font size', '#e{font-size:10px;transition:font-size 1s linear}#e.b{font-size:30px}', 'font-size', T4,
    ['10px', '15px', '20px', '30px'], 1.01)
trSeries('z-index is rounded', '#e{position:relative;z-index:0;transition:z-index 1s linear}#e.b{z-index:10}', 'z-index', T4,
    ['0', '3', '5', '10'], 0.01)
trSeries('line height', '#e{line-height:20px;transition:line-height 1s linear}#e.b{line-height:40px}', 'line-height',
    [0.0, 500.0, 1000.0], ['20px', '30px', '40px'], 1.01)
trSeries('flex-grow', '#e{flex-grow:0;transition:flex-grow 1s linear}#e.b{flex-grow:2}', 'flex-grow',
    [0.0, 500.0, 1000.0], ['0', '1', '2'], 0.02)
trSeries('border radius', '#e{border-radius:0px;transition:border-radius 1s linear}#e.b{border-radius:20px}', 'border-top-left-radius',
    [0.0, 500.0, 1000.0], ['0px', '10px', '20px'], 1.01)
trSeries('a transform through its matrix', '#e{transform:translateX(0px);transition:transform 1s linear}#e.b{transform:translateX(100px) rotate(90deg)}', 'transform', T4,
    ['matrix(1, 0, 0, 1, 0, 0)', 'matrix(0.92388, 0.382683, -0.382683, 0.92388, 25, 0)',
     'matrix(0.707107, 0.707107, -0.707107, 0.707107, 50, 0)', 'matrix(0, 1, -1, 0, 100, 0)'], 0.02)
trSeries('a shadow', '#e{box-shadow:0 0 0 0 rgb(0,0,0);transition:box-shadow 1s linear}#e.b{box-shadow:10px 10px 0 0 rgb(100,0,0)}', 'box-shadow',
    [0.0, 500.0, 1000.0], [' rgba(0, 0, 0, 1) 0px 0px 0px 0px', ' rgba(50, 0, 0, 1) 5px 5px 0px 0px', ' rgba(100, 0, 0, 1) 10px 10px 0px 0px'], 1.6)
trSeries('a margin shorthand starts its four longhands', '#e{margin:0px;transition:margin 1s linear}#e.b{margin:20px}', 'margin-top',
    [0.0, 500.0, 1000.0], ['0px', '10px', '20px'], 1.01)
trSeries('px to percent', '#e{width:100px;transition:width 1s linear}#e.b{width:50%}', 'width',
    [0.0, 500.0, 1000.0], ['100px', '150px', '200px'], 1.01)

// ---- what is not --------------------------------------------------------------

trRow('auto to a length starts nothing', '#e{width:auto;transition:width 1s linear}#e.b{width:200px}', 0.0, 'width', '200px', 1.01)
trRow('and neither does it for height', '#e{height:auto;transition:height 1s linear}#e.b{height:200px}', 500.0, 'height', '200px', 1.01)
trRow('transition: none', '#e{width:100px;transition:none}#e.b{width:200px}', 0.0, 'width', '200px', 1.01)
trRow('a transition only in the old style starts nothing',
    '#e{width:100px;transition:width 1s linear}#e.b{width:200px;transition:none}', 500.0, 'width', '200px', 1.01)
trRow('currentcolor is compared unresolved',
    '#e{color:rgb(0,0,0);border:2px solid;transition:border-color 1s linear}#e.b{color:rgb(100,0,0)}', 500.0, 'border-top-color', 'rgb(100, 0, 0)', 1.6)

// ---- the after-change style says how --------------------------------------

trSeries('a transition declared only in the new style', '#e{width:100px}#e.b{width:200px;transition:width 1s linear}', 'width',
    [0.0, 500.0, 1000.0], ['100px', '150px', '200px'], 1.01)
trSeries('a delay added by the new style', '#e{width:100px;transition:width 1s linear}#e.b{width:200px;transition-delay:.5s}', 'width',
    [0.0, 500.0, 1000.0, 1500.0], ['100px', '100px', '150px', '200px'], 1.01)
trSeries('a duration changed by the new style', '#e{width:100px;transition:width 1s linear}#e.b{width:200px;transition-duration:2s}', 'width',
    [0.0, 1000.0, 2000.0], ['100px', '150px', '200px'], 1.01)

// ---- lists and the shorthand -------------------------------------------------

trSeries('different durations per property', '#e{width:100px;opacity:1;transition:width 1s linear,opacity 2s linear}#e.b{width:200px;opacity:0}', 'opacity',
    [0.0, 500.0, 1000.0, 2000.0], ['1', '0.75', '0.5', '0'], 0.02)
trSeries('all', '#e{width:100px;opacity:1;transition:all 1s linear}#e.b{width:200px;opacity:0}', 'width',
    [0.0, 500.0, 1000.0], ['100px', '150px', '200px'], 1.01)
trSeries('all, for opacity', '#e{width:100px;opacity:1;transition:all 1s linear}#e.b{width:200px;opacity:0}', 'opacity',
    [0.0, 500.0, 1000.0], ['1', '0.5', '0'], 0.02)
trSeries('longhand lists cycle against the properties',
    '#e{width:100px;opacity:1;height:10px;transition-property:width,opacity,height;transition-duration:1s,2s;transition-timing-function:linear}#e.b{width:200px;opacity:0;height:30px}', 'height',
    [0.0, 500.0, 1000.0, 2000.0], ['10px', '20px', '30px', '30px'], 1.01)
trSeries('a later item for a property overrides an earlier', '#e{width:100px;transition:width 2s linear,width 1s linear}#e.b{width:200px}', 'width',
    [0.0, 500.0, 1000.0, 2000.0], ['100px', '150px', '200px', '200px'], 1.01)
trSeries('all overrides an earlier named item', '#e{width:100px;color:rgb(0,0,0);transition:color 2s linear,all 1s linear}#e.b{width:200px;color:rgb(100,0,0)}', 'color',
    [0.0, 500.0, 1000.0, 2000.0], ['rgb(0, 0, 0)', 'rgb(50, 0, 0)', 'rgb(100, 0, 0)', 'rgb(100, 0, 0)'], 1.6)
trSeries('the delay in the shorthand', '#e{width:100px;transition:width 1s .5s linear}#e.b{width:200px}', 'width',
    [0.0, 500.0, 1000.0, 1500.0], ['100px', '100px', '150px', '200px'], 1.01)
trSeries('the parts in any order', '#e{width:100px;transition:ease-in 1s width}#e.b{width:200px}', 'width',
    [0.0, 500.0, 1000.0], ['100px', '131.531px', '200px'], 1.01)
trSeries('a lone time is all', '#e{width:100px;transition:1s}#e.b{width:200px}', 'width',
    [0.0, 500.0, 1000.0], ['100px', '180.234px', '200px'], 1.01)
// Two ways to say the same: the shorthand and its longhands.
for int i = 0, i < T7.length, i++ {
    text viaShort = trState('#e{width:100px;transition:width 1s .5s ease-in-out}#e.b{width:200px}', TR_DIV, 'b', -1.0, '', T7[i] + 250.0, 'width')
    text viaLong = trState('#e{width:100px;transition-property:width;transition-duration:1s;transition-delay:.5s;transition-timing-function:ease-in-out}#e.b{width:200px}', TR_DIV, 'b', -1.0, '', T7[i] + 250.0, 'width')
    checkEq(viaShort, viaLong, `shorthand and longhands agree at ${T7[i] + 250.0}`)
}
// And a negative delay is the same as starting part-way through.
for int i = 0, i < 5, i++ {
    float at = 200.0 * i.toFloat()
    text delayed = trState('#e{width:100px;transition:width 1s linear -.5s}#e.b{width:200px}', TR_DIV, 'b', -1.0, '', at, 'width')
    text shifted = trState('#e{width:100px;transition:width 1s linear}#e.b{width:200px}', TR_DIV, 'b', -1.0, '', at + 500.0, 'width')
    if at + 500.0 <= 1000.0 { checkEq(delayed, shifted, `a -.5s delay is a 500 ms head start at ${at}`) }
}

// ---- discrete properties -----------------------------------------------------

arr[float] TS = [0.0, 499.0, 501.0, 1000.0]
trSeries('discrete properties do not transition by default', '#e{text-align:left;transition:text-align 1s linear}#e.b{text-align:right}', 'text-align',
    TS, ['right', 'right', 'right', 'right'], 0.0)
text DISCRETE = '#e{text-align:left;transition:text-align 1s linear allow-discrete}#e.b{text-align:right}'
trRow('allow-discrete flips at half way', DISCRETE, 0.0, 'text-align', 'left', 0.0)
trRow('and still has not at 499', DISCRETE, 499.0, 'text-align', 'left', 0.0)
trRow('and has by 501', DISCRETE, 501.0, 'text-align', 'right', 0.0)
trRow('and at the end', DISCRETE, 1000.0, 'text-align', 'right', 0.0)
trRow('all leaves discrete properties out', '#e{text-align:left;width:100px;transition:all 1s linear}#e.b{text-align:right;width:200px}', 0.0, 'text-align', 'right', 0.0)
trRow('and takes them with the keyword', '#e{text-align:left;width:100px;transition:all 1s linear allow-discrete}#e.b{text-align:right;width:200px}', 0.0, 'text-align', 'left', 0.0)
trRow('transition-behavior lists cycle', '#e{text-align:left;width:100px;transition-property:text-align,width;transition-duration:1s;transition-timing-function:linear;transition-behavior:allow-discrete,normal}#e.b{text-align:right;width:200px}', 499.0, 'text-align', 'left', 0.0)
trRow('visibility needs no keyword', '#e{visibility:visible;transition:visibility 1s linear}#e.b{visibility:hidden}', 500.0, 'visibility', 'visible', 0.0)
trRow('and is hidden at the end', '#e{visibility:visible;transition:visibility 1s linear}#e.b{visibility:hidden}', 1000.0, 'visibility', 'hidden', 0.0)
trRow('display is not transitioned by default', '#e{display:block;transition:display 1s linear}#e.b{display:none}', 0.0, 'display', 'none', 0.0)
trRow('and with the keyword stays until the end', '#e{display:block;transition:display 1s linear allow-discrete}#e.b{display:none}', 999.0, 'display', 'block', 0.0)
trRow('and then is gone', '#e{display:block;transition:display 1s linear allow-discrete}#e.b{display:none}', 1000.0, 'display', 'none', 0.0)

// ---- changing it again -------------------------------------------------------

text LIN = '#e{width:100px;transition:width 1s linear}#e.b{width:200px}#e.c{width:300px}'
text EASE = '#e{width:100px;transition:width 1s}#e.b{width:200px}'

void func trTwice(name:text, css:text, at2:float, cls2:text, t:float, expected:text) {
    text got = trState(css, TR_DIV, 'b', at2, cls2, t, 'width')
    if nearText(got, expected, [1.01]) { check(true, name) }
    else { checkEq(got, expected, `${name} at ${t}ms`) }
}

// Back to where it started, half way: a 500 ms transition from 150.
trTwice('a reversal at half way starts from the current value', LIN, 500.0, '', 0.0, '150px')
trTwice('and is shortened to the part covered', LIN, 500.0, '', 100.0, '140px')
trTwice('so it arrives at 500 ms', LIN, 500.0, '', 250.0, '125px')
trTwice('at the original value', LIN, 500.0, '', 500.0, '100px')
trTwice('and stays', LIN, 500.0, '', 1000.0, '100px')
trTwice('a reversal at a quarter lasts a quarter', LIN, 250.0, '', 0.0, '125px')
trTwice('and is over by then', LIN, 250.0, '', 250.0, '100px')
trTwice('at three quarters, three quarters', LIN, 750.0, '', 0.0, '175px')
trTwice('and half way along it', LIN, 750.0, '', 250.0, '150px')
trTwice('and finished', LIN, 750.0, '', 750.0, '100px')
// Under ease the shortening is by the eased progress, not the time.
trTwice('an eased reversal starts from the current value', EASE, 500.0, '', 0.0, '180.234px')
trTwice('and is shortened by the eased progress', EASE, 500.0, '', 100.0, '169.297px')
trTwice('and runs a fresh ease', EASE, 500.0, '', 250.0, '137.25px')
trTwice('at 500', EASE, 500.0, '', 500.0, '108px')
trTwice('at 750', EASE, 500.0, '', 750.0, '100.188px')
trTwice('and has arrived by 1000', EASE, 500.0, '', 1000.0, '100px')
// Reversed after it finished: a plain transition.
trTwice('a reversal after the end is a full transition', LIN, 1000.0, '', 0.0, '200px')
trTwice('from the end value', LIN, 1000.0, '', 500.0, '150px')
trTwice('over the whole duration', LIN, 1000.0, '', 1000.0, '100px')
// A third value is a full-length transition from where it was.
trTwice('a third value starts from the current value', LIN, 500.0, 'c', 0.0, '150px')
trTwice('and takes the whole duration', LIN, 500.0, 'c', 250.0, '187.5px')
trTwice('half way', LIN, 500.0, 'c', 500.0, '225px')
trTwice('and arrives', LIN, 500.0, 'c', 1000.0, '300px')
trTwice('and stays', LIN, 500.0, 'c', 1500.0, '300px')
// A reversal inside the delay: the value never moved, so there is nothing
// to transition.
text DELAYED = '#e{width:100px;transition:width 1s linear 1s}#e.b{width:200px}'
trTwice('a reversal inside the delay starts nothing', DELAYED, 500.0, '', 0.0, '100px')
trTwice('and nothing later', DELAYED, 500.0, '', 1500.0, '100px')

// ---- who it reaches -----------------------------------------------------------

// Two elements that match the same rules share one computed style. A
// transition is one element's, so the one it is running on must not be
// handed to the other.
void func trSharing() {
    Page p = trPage('.x{width:100px;transition:width 1s linear}.x.b{width:200px}', '<div id="e" class="x"></div><div id="f" class="x"></div>')
    trSetClass(p, 'e', 'x b', 0.0)
    trRestyle(p, 500.0)
    checkEq(trRead(p, 'e', 'width'), '150px', 'the element that changed is part of the way')
    checkEq(trRead(p, 'f', 'width'), '100px', 'the one that matched the same rules is not')
    trRestyle(p, 1000.0)
    checkEq(trRead(p, 'e', 'width'), '200px', 'and it arrives')
    checkEq(trRead(p, 'f', 'width'), '100px', 'while the other has not moved')
}
trSharing()

// An inline style says `transition` as well as a sheet does, and the
// restyle sees it.
void func trInline() {
    Page p = trPage('#e.b{width:200px}', '<div id="e" style="width:100px;transition:width 1s linear"></div>')
    trSetClass(p, 'e', 'b', 0.0)
    trRestyle(p, 500.0)
    // the sheet's #e.b loses to the style attribute, so nothing changes
    checkEq(trRead(p, 'e', 'width'), '100px', 'an inline declaration still beats the class rule, so there is no change')
    Page q = trPage('#e{transition:width 1s linear}#e.b{width:200px}', '<div id="e" style="width:100px"></div>')
    check(cascadeSawTransition, 'a sheet that says transition raises the flag with the element styled inline')
    Page r = trPage('', '<div id="e" style="width:100px;transition:width 1s linear" class="a"></div>')
    check(cascadeSawTransition, 'and so does a style attribute')
}
trInline()

// A child that has no transition of its own follows its parent's animated
// value, because it inherits it.
void func trInherit() {
    Page p = trPage('#p{color:rgb(0,0,0);transition:color 1s linear}#p.b{color:rgb(100,0,0)}', '<div id="p"><span id="e">x</span></div>')
    trSetClass(p, 'p', 'b', 0.0)
    trRestyle(p, 500.0)
    checkEq(trRead(p, 'e', 'color'), 'rgb(50, 0, 0)', 'a child inherits the parent mid-transition')
    trRestyle(p, 1000.0)
    checkEq(trRead(p, 'e', 'color'), 'rgb(100, 0, 0)', 'and its end')
}
trInherit()

// ---- from a fragment ---------------------------------------------------------
//
// The one thing in this browser that changes a style under a page is a
// navigation to a fragment, which changes `:target`. It is a change of
// computed value like any other.

void func trTarget() {
    animationClock = 0.0
    Page p = pageFromHtml(`<!doctype html><style>${TR_BASE}#e{width:100px;transition:width 1s linear}#e:target{width:200px}</style><div id="e"></div>`, 'about:blank', 400)
    check(trRead(p, 'e', 'width') == '100px', 'before the fragment the box is its own width')
    setTargetFragment(p, 'about:blank#e')
    trRestyle(p, 0.0)
    checkEq(trRead(p, 'e', 'width'), '100px', 'the moment :target matches it has not moved')
    trRestyle(p, 500.0)
    checkEq(trRead(p, 'e', 'width'), '150px', 'half way through the transition :target started')
    check(animLive, 'a running transition keeps the clock live')
    trRestyle(p, 1000.0)
    checkEq(trRead(p, 'e', 'width'), '200px', 'and it arrives')
    check(!animLive, 'when it has finished the clock is not needed')
}
trTarget()

// ---- what it costs a page that has none ---------------------------------------

Page plain = trPage('#e{width:100px}', TR_DIV)
check(!cascadeSawTransition, 'a document that never says transition does not raise the flag')
Page declared = trPage('#e{width:100px;transition:width 1s}', TR_DIV)
check(cascadeSawTransition, 'one that does, does')
Page durationOnly = trPage('#e{width:100px;transition-duration:1s}', TR_DIV)
check(cascadeSawTransition, 'and so does a longhand that sets a duration')
// A document is styled from nothing: the first style of a page has no
// before-change style, so nothing transitions from it.
Page first = pageFromHtml(`<!doctype html><style>${TR_BASE}#e{width:200px;transition:width 1s linear}</style><div id="e"></div>`, 'about:blank', 400)
checkEq(trRead(first, 'e', 'width'), '200px', 'a first style does not transition')
check(!animLive, 'and has nothing running')

finish('transitions')
