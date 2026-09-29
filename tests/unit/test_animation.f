// CSS Animations 1: the value an animation gives a property at a moment.
// Every expectation is what Chromium 141 answered with the animation paused
// at that time (`animation.pause(); animation.currentTime = t`) and the
// property read back through getComputedStyle; the rows are in todo.md,
// "CSS Animations 1, measured". Lengths in this engine are whole pixels, so
// a length is compared to within a pixel, a colour channel to within 1.6 and
// an alpha to within 0.02.

import ../../src/browser/page.f
import ../assert.f
setClientWidth(400)

text func rgbText(c:int) {
    int a = colorAlpha(c)
    if a >= 255 { return `rgb(${colorRed(c)}, ${colorGreen(c)}, ${colorBlue(c)})` }
    return `rgba(${colorRed(c)}, ${colorGreen(c)}, ${colorBlue(c)}, ${a.toFloat() / 255.0})`
}

text func lenText(l:Len) {
    if l.kind == LEN_AUTO { return 'auto' }
    if l.kind == LEN_PERCENT { return `${l.v}%` }
    return `${l.v}px`
}

text func propText(prop:text, s:Style, b:Box) {
    if prop == 'width' { return `${b.w}px` }
    if prop == 'height' { return `${b.h}px` }
    if prop == 'opacity' { return `${s.opacity}` }
    if prop == 'color' { return rgbText(s.color) }
    if prop == 'background-color' { return rgbText(s.background) }
    if prop == 'font-size' { return `${s.fontSize}px` }
    if prop == 'margin-top' { return `${b.y}px` }
    if prop == 'margin-right' { return `${b.mr}px` }
    if prop == 'margin-bottom' { return `${b.mb}px` }
    if prop == 'margin-left' { return `${b.ml}px` }
    if prop == 'padding-left' { return `${b.pl}px` }
    if prop == 'border-top-width' { return `${b.bt}px` }
    if prop == 'top' { return `${b.y}px` }
    if prop == 'left' { return `${b.x}px` }
    if prop == 'z-index' { return `${s.zIndex}` }
    if prop == 'letter-spacing' { return `${s.letterSpacing}px` }
    if prop == 'line-height' { return `${s.lineHeight}px` }
    if prop == 'flex-grow' { return `${s.flexGrow}` }
    if prop == 'order' { return `${s.order}` }
    if prop == 'outline-offset' { return `${s.outlineOffset}px` }
    if prop == 'column-gap' { return `${s.columnGap}px` }
    if prop == 'column-count' { return `${s.columnCount}` }
    if prop == 'flex-basis' { return lenText(s.flexBasis) }
    if prop == 'border-top-color' || prop == 'border-left-color' { return rgbText(s.borderTopColor) }
    if prop == 'border-top-left-radius' { return lenText(s.radiusTopLeftX) }
    if prop == 'aspect-ratio' { return `${s.aspectW} / ${s.aspectH}` }
    if prop == 'background-position' { return `${lenText(s.backgroundPosX)} ${lenText(s.backgroundPosY)}` }
    if prop == 'background-size' { return `${lenText(s.backgroundSizeW)} ${lenText(s.backgroundSizeH)}` }
    if prop == 'filter' {
        text r = ''
        if s.filterIdx > 0 {
            FilterSpec f = filterSpecs[s.filterIdx]
            for int i = 0, i < f.amounts.length, i++ { r = `${r} ${f.amounts[i]}` }
        }
        return r
    }
    if prop == 'visibility' { return b.style.hidden ? 'hidden' : 'visible' }
    if prop == 'transform' {
        float ma = 1.0
        float mb = 0.0
        float mc = 0.0
        float md = 1.0
        float me = 0.0
        float mf = 0.0
        for int i = 0, i < s.transforms.length, i++ {
            Transform t = s.transforms[i]
            float a = 1.0
            float b2 = 0.0
            float c = 0.0
            float d = 1.0
            float e = 0.0
            float f = 0.0
            if t.kind == TX_TRANSLATE {
                e = t.x.kind == LEN_PERCENT ? t.x.v * b.w.toFloat() / 100.0 : t.x.v
                f = t.y.kind == LEN_PERCENT ? t.y.v * b.h.toFloat() / 100.0 : t.y.v
            } else if t.kind == TX_SCALE {
                a = t.sx
                d = t.sy
            } else {
                float r = t.angle * 3.14159265358979 / 180.0
                a = Math.cos(r)
                b2 = Math.sin(r)
                c = 0.0 - Math.sin(r)
                d = Math.cos(r)
            }
            float na = ma * a + mc * b2
            float nb = mb * a + md * b2
            float nc = ma * c + mc * d
            float nd = mb * c + md * d
            float ne = ma * e + mc * f + me
            float nf = mb * e + md * f + mf
            ma = na
            mb = nb
            mc = nc
            md = nd
            me = ne
            mf = nf
        }
        return `matrix(${animNum(ma)}, ${animNum(mb)}, ${animNum(mc)}, ${animNum(md)}, ${animNum(me)}, ${animNum(mf)})`
    }
    if prop == 'box-shadow' {
        text r = ''
        for int i = 0, i < s.shadows.length, i++ {
            Shadow h = s.shadows[i]
            r = `${r} rgba(${colorRed(h.color)}, ${colorGreen(h.color)}, ${colorBlue(h.color)}, ${colorAlpha(h.color).toFloat() / 255.0}) ${h.dx}px ${h.dy}px ${h.blur}px ${h.spread}px`
        }
        return r
    }
    return '?'
}



// The numbers in a text, in order.
arr[float] func animNumsOf(t:text) {
    arr[float] out = []
    ascii a = t.toAscii()
    int i = 0
    while i < a.length {
        int c = a.charCodeAt(i)
        bool digitNext = i + 1 < a.length && isDigitCode(a.charCodeAt(i + 1))
        if isDigitCode(c) || (c == CH_MINUS && digitNext) || (c == CH_DOT && digitNext) {
            parseNumberAt(a, i)
            if numOk {
                out.push(numValue)
                i = numEnd
                continue
            }
        }
        i++
    }
    return out
}

// An opaque colour is `rgb(r, g, b)` in one engine's answer and
// `rgba(r, g, b, 1)` in the other's, depending on where it came from; both
// are written with their alpha so the numbers pair up.
text func animWithAlpha(t:text) {
    text out = ''
    int i = 0
    ascii a = t.toAscii()
    while i < a.length {
        if asciiStartsWith(a, 'rgb(', i) {
            int close = asciiIndexOf(a, ')', i)
            out = `${out}rgba(${a.slice(i + 4, close).toText()}, 1)`
            i = close + 1
            continue
        }
        out = `${out}${a.slice(i, i + 1).toText()}`
        i++
    }
    return out
}

bool func nearText(actual:text, expected:text, tol:arr[float]) {
    arr[float] a = animNumsOf(animWithAlpha(actual))
    arr[float] e = animNumsOf(animWithAlpha(expected))
    if a.length != e.length { return false }
    for int i = 0, i < a.length, i++ {
        float t = tol[i < tol.length ? i : tol.length - 1]
        float d = a[i] - e[i]
        if d < 0.0 { d = 0.0 - d }
        if d > t { return false }
    }
    return true
}

text func animState(css:text, t:float, props:arr[text]) {
    animationClock = t
    Page p = pageFromHtml('<!doctype html><style>body{margin:0;font-size:16px}#e{width:50px;height:20px}' + css + '</style><div id="e"></div>', 'about:blank', 400)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    Box b = all.length > 0 ? all[0] : null
    text row = ''
    for int i = 0, i < props.length, i++ {
        row = `${row}${row == '' ? '' : ' | '}${b == null ? 'none' : propText(props[i], b.style, b)}`
    }
    animationClock = 0.0
    return row
}

void func animRow(name:text, css:text, t:float, props:arr[text], expected:text, tol:arr[float]) {
    text got = animState(css, t, props)
    if nearText(got, expected, tol) { check(true, name) }
    else { checkEq(got, expected, `${name} at ${t}ms`) }
}

animRow('opacity linear', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear}', 0.0, ['opacity'], '0', [0.02])
animRow('opacity linear', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear}', 250.0, ['opacity'], '0.25', [0.02])
animRow('opacity linear', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear}', 500.0, ['opacity'], '0.5', [0.02])
animRow('opacity linear', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear}', 750.0, ['opacity'], '0.75', [0.02])
animRow('opacity linear', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear}', 1000.0, ['opacity'], '1', [0.02])
animRow('opacity linear', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear}', 1500.0, ['opacity'], '1', [0.02])
animRow('opacity linear forwards', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear forwards}', 0.0, ['opacity'], '0', [0.02])
animRow('opacity linear forwards', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear forwards}', 500.0, ['opacity'], '0.5', [0.02])
animRow('opacity linear forwards', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear forwards}', 1000.0, ['opacity'], '1', [0.02])
animRow('opacity linear forwards', '@keyframes k{from{opacity:0}to{opacity:1}}#e{animation:k 1000ms linear forwards}', 1500.0, ['opacity'], '1', [0.02])
animRow('width ease', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms}', 0.0, ['width'], '100px', [1.01])
animRow('width ease', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms}', 100.0, ['width'], '109.469px', [1.01])
animRow('width ease', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms}', 250.0, ['width'], '140.844px', [1.01])
animRow('width ease', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms}', 500.0, ['width'], '180.234px', [1.01])
animRow('width ease', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms}', 750.0, ['width'], '196.031px', [1.01])
animRow('width ease', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms}', 900.0, ['width'], '199.422px', [1.01])
animRow('width ease', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms}', 1000.0, ['width'], '50px', [1.01])
animRow('ease-in', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-in}', 250.0, ['width'], '109.344px', [1.01])
animRow('ease-in', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-in}', 500.0, ['width'], '131.531px', [1.01])
animRow('ease-in', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-in}', 750.0, ['width'], '162.172px', [1.01])
animRow('ease-out', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-out}', 250.0, ['width'], '137.812px', [1.01])
animRow('ease-out', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-out}', 500.0, ['width'], '168.453px', [1.01])
animRow('ease-out', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-out}', 750.0, ['width'], '190.641px', [1.01])
animRow('ease-in-out', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-in-out}', 250.0, ['width'], '112.906px', [1.01])
animRow('ease-in-out', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-in-out}', 500.0, ['width'], '150px', [1.01])
animRow('ease-in-out', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms ease-in-out}', 750.0, ['width'], '187.078px', [1.01])
animRow('cubic-bezier', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms cubic-bezier(.1,.7,.9,.2)}', 250.0, ['width'], '137.797px', [1.01])
animRow('cubic-bezier', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms cubic-bezier(.1,.7,.9,.2)}', 500.0, ['width'], '146.25px', [1.01])
animRow('cubic-bezier', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms cubic-bezier(.1,.7,.9,.2)}', 750.0, ['width'], '155.812px', [1.01])
animRow('cubic-bezier overshoot', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms cubic-bezier(.5,-1,.5,2)}', 100.0, ['width'], '84.375px', [1.01])
animRow('cubic-bezier overshoot', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms cubic-bezier(.5,-1,.5,2)}', 250.0, ['width'], '81.7656px', [1.01])
animRow('cubic-bezier overshoot', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms cubic-bezier(.5,-1,.5,2)}', 500.0, ['width'], '150px', [1.01])
animRow('cubic-bezier overshoot', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms cubic-bezier(.5,-1,.5,2)}', 750.0, ['width'], '218.219px', [1.01])
animRow('cubic-bezier overshoot', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms cubic-bezier(.5,-1,.5,2)}', 900.0, ['width'], '215.609px', [1.01])
animRow('steps(4)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4)}', 100.0, ['width'], '100px', [1.01])
animRow('steps(4)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4)}', 250.0, ['width'], '125px', [1.01])
animRow('steps(4)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4)}', 300.0, ['width'], '125px', [1.01])
animRow('steps(4)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4)}', 500.0, ['width'], '150px', [1.01])
animRow('steps(4)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4)}', 999.0, ['width'], '175px', [1.01])
animRow('steps(4,jump-start)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4,jump-start)}', 100.0, ['width'], '125px', [1.01])
animRow('steps(4,jump-start)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4,jump-start)}', 250.0, ['width'], '150px', [1.01])
animRow('steps(4,jump-start)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4,jump-start)}', 500.0, ['width'], '175px', [1.01])
animRow('steps(4,jump-start)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4,jump-start)}', 999.0, ['width'], '200px', [1.01])
animRow('steps(4,jump-none)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4,jump-none)}', 100.0, ['width'], '100px', [1.01])
animRow('steps(4,jump-none)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4,jump-none)}', 250.0, ['width'], '133.328px', [1.01])
animRow('steps(4,jump-none)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4,jump-none)}', 500.0, ['width'], '166.656px', [1.01])
animRow('steps(4,jump-none)', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms steps(4,jump-none)}', 999.0, ['width'], '200px', [1.01])
animRow('step-start', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms step-start}', 1.0, ['width'], '200px', [1.01])
animRow('step-start', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms step-start}', 500.0, ['width'], '200px', [1.01])
animRow('step-end', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms step-end}', 500.0, ['width'], '100px', [1.01])
animRow('step-end', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms step-end}', 999.0, ['width'], '100px', [1.01])
animRow('linear()', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms linear(0, .25 75%, 1)}', 250.0, ['width'], '108.328px', [1.01])
animRow('linear()', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms linear(0, .25 75%, 1)}', 500.0, ['width'], '116.656px', [1.01])
animRow('linear()', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms linear(0, .25 75%, 1)}', 750.0, ['width'], '125px', [1.01])
animRow('linear()', '@keyframes k{from{width:100px}to{width:200px}}#e{animation:k 1000ms linear(0, .25 75%, 1)}', 900.0, ['width'], '170px', [1.01])
animRow('percent keyframes linear', '@keyframes k{0%{width:0px}25%{width:100px}100%{width:20px}}#e{animation:k 1000ms linear}', 100.0, ['width'], '40px', [1.01])
animRow('percent keyframes linear', '@keyframes k{0%{width:0px}25%{width:100px}100%{width:20px}}#e{animation:k 1000ms linear}', 250.0, ['width'], '100px', [1.01])
animRow('percent keyframes linear', '@keyframes k{0%{width:0px}25%{width:100px}100%{width:20px}}#e{animation:k 1000ms linear}', 600.0, ['width'], '62.6562px', [1.01])
animRow('percent keyframes linear', '@keyframes k{0%{width:0px}25%{width:100px}100%{width:20px}}#e{animation:k 1000ms linear}', 1000.0, ['width'], '50px', [1.01])
animRow('percent keyframes ease', '@keyframes k{0%{width:0px}25%{width:100px}100%{width:20px}}#e{animation:k 1000ms}', 100.0, ['width'], '68.25px', [1.01])
animRow('percent keyframes ease', '@keyframes k{0%{width:0px}25%{width:100px}100%{width:20px}}#e{animation:k 1000ms}', 250.0, ['width'], '100px', [1.01])
animRow('percent keyframes ease', '@keyframes k{0%{width:0px}25%{width:100px}100%{width:20px}}#e{animation:k 1000ms}', 600.0, ['width'], '38.625px', [1.01])
animRow('keyframe timing-function', '@keyframes k{0%{width:0px;animation-timing-function:linear}50%{width:100px}100%{width:20px}}#e{animation:k 1000ms ease-in}', 250.0, ['width'], '50px', [1.01])
animRow('keyframe timing-function', '@keyframes k{0%{width:0px;animation-timing-function:linear}50%{width:100px}100%{width:20px}}#e{animation:k 1000ms ease-in}', 750.0, ['width'], '74.7656px', [1.01])
animRow('only to (underlying 50px)', '@keyframes k{to{width:150px}}#e{animation:k 1000ms linear}', 0.0, ['width'], '50px', [1.01])
animRow('only to (underlying 50px)', '@keyframes k{to{width:150px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '100px', [1.01])
animRow('only to (underlying 50px)', '@keyframes k{to{width:150px}}#e{animation:k 1000ms linear}', 1000.0, ['width'], '50px', [1.01])
animRow('only from (underlying 50px)', '@keyframes k{from{width:150px}}#e{animation:k 1000ms linear}', 0.0, ['width'], '150px', [1.01])
animRow('only from (underlying 50px)', '@keyframes k{from{width:150px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '100px', [1.01])
animRow('only from (underlying 50px)', '@keyframes k{from{width:150px}}#e{animation:k 1000ms linear}', 1000.0, ['width'], '50px', [1.01])
animRow('unsorted keyframes', '@keyframes k{100%{width:200px}0%{width:100px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '150px', [1.01])
animRow('duplicate offsets', '@keyframes k{0%{width:100px}50%{width:150px}50%{height:40px}100%{width:200px}}#e{animation:k 1000ms linear}', 250.0, ['width', 'height'], '125px | 30px', [1.01])
animRow('duplicate offsets', '@keyframes k{0%{width:100px}50%{width:150px}50%{height:40px}100%{width:200px}}#e{animation:k 1000ms linear}', 500.0, ['width', 'height'], '150px | 40px', [1.01])
animRow('duplicate offsets', '@keyframes k{0%{width:100px}50%{width:150px}50%{height:40px}100%{width:200px}}#e{animation:k 1000ms linear}', 750.0, ['width', 'height'], '175px | 30px', [1.01])
animRow('comma selector', '@keyframes k{0%,100%{width:100px}50%{width:200px}}#e{animation:k 1000ms linear}', 0.0, ['width'], '100px', [1.01])
animRow('comma selector', '@keyframes k{0%,100%{width:100px}50%{width:200px}}#e{animation:k 1000ms linear}', 250.0, ['width'], '150px', [1.01])
animRow('comma selector', '@keyframes k{0%,100%{width:100px}50%{width:200px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '200px', [1.01])
animRow('comma selector', '@keyframes k{0%,100%{width:100px}50%{width:200px}}#e{animation:k 1000ms linear}', 1000.0, ['width'], '50px', [1.01])
animRow('animation:k 1000ms linear 2', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 2', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2}', 500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 2', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2}', 1000.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 2', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2}', 1500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 2', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2}', 2000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 2', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2}', 2500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5}', 500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5}', 1000.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5}', 2000.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5}', 2250.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5}', 2500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5}', 3000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5 forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5 forwards}', 2250.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5 forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5 forwards}', 2500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5 forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5 forwards}', 3000.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear infinite', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear infinite}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear infinite', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear infinite}', 500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear infinite', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear infinite}', 1000.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear infinite', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear infinite}', 1500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear infinite', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear infinite}', 12500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 reverse}', 0.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 reverse}', 250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 reverse}', 1000.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 reverse}', 1250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 reverse}', 2000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate}', 250.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate}', 1000.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate}', 1250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate}', 2000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate}', 2500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate-reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate-reverse}', 0.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate-reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate-reverse}', 250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate-reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate-reverse}', 1000.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate-reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate-reverse}', 1250.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate-reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate-reverse}', 2000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 2 alternate-reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2 alternate-reverse}', 2500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 3 alternate forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 3 alternate forwards}', 2500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 3 alternate forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 3 alternate forwards}', 3000.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 3 alternate forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 3 alternate forwards}', 3500.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5 alternate forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5 alternate forwards}', 2250.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5 alternate forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5 alternate forwards}', 2500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 2.5 alternate forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 2.5 alternate forwards}', 3000.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 1.5 reverse forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 1.5 reverse forwards}', 1250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation:k 1000ms linear 1.5 reverse forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 1.5 reverse forwards}', 1500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 1.5 reverse forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 1.5 reverse forwards}', 2000.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms}', 0.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms}', 250.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms}', 500.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms}', 750.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms}', 1500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms}', 1600.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards}', 250.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards}', 500.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards}', 750.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards}', 1500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards}', 1600.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms forwards}', 0.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms forwards}', 250.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms forwards}', 500.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms forwards}', 750.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms forwards}', 1500.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms forwards}', 1600.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both}', 250.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both}', 500.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both}', 750.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both}', 1500.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both}', 1600.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms}', 0.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms}', 250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms}', 500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms}', 750.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms}', 1000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms both}', 0.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms both}', 250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms both}', 500.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms both}', 750.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear -500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -500ms both}', 1000.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear -1500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -1500ms both}', 0.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear -1500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -1500ms both}', 250.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear -1500ms both', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear -1500ms both}', 500.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards reverse}', 0.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards reverse}', 250.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms backwards reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms backwards reverse}', 500.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both alternate}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both alternate}', 250.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both alternate}', 1500.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 1000ms linear 500ms both alternate', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1000ms linear 500ms both alternate}', 2000.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 0s linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s linear}', 0.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 0s linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s linear}', 100.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 0s linear forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s linear forwards}', 0.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 0s linear forwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s linear forwards}', 100.0, ['width', 'height'], '200px | 20px', [1.01])
animRow('animation:k 0s 500ms linear backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s 500ms linear backwards}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 0s 500ms linear backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s 500ms linear backwards}', 100.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 0s 500ms linear backwards', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s 500ms linear backwards}', 600.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 0s linear infinite', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s linear infinite}', 0.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 0s linear infinite', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 0s linear infinite}', 100.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation-name:k;animation-duration:2s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k;animation-duration:2s;animation-timing-function:linear}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation-name:k;animation-duration:2s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k;animation-duration:2s;animation-timing-function:linear}', 500.0, ['width', 'height'], '125px | 20px', [1.01])
animRow('animation-name:k;animation-duration:2s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k;animation-duration:2s;animation-timing-function:linear}', 1000.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation-name:k;animation-duration:2s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k;animation-duration:2s;animation-timing-function:linear}', 2000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1s linear;animation-duration:2s', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1s linear;animation-duration:2s}', 0.0, ['width', 'height'], '100px | 20px', [1.01])
animRow('animation:k 1s linear;animation-duration:2s', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1s linear;animation-duration:2s}', 1000.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 1s linear;animation-duration:2s', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1s linear;animation-duration:2s}', 2000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 2s linear;animation-duration:1s', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 2s linear;animation-duration:1s}', 500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation:k 2s linear;animation-duration:1s', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 2s linear;animation-duration:1s}', 1000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 2s linear;animation-duration:1s', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 2s linear;animation-duration:1s}', 1500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation-duration:2s;animation:k 1s linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-duration:2s;animation:k 1s linear}', 500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation-duration:2s;animation:k 1s linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-duration:2s;animation:k 1s linear}', 1000.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation-duration:2s;animation:k 1s linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-duration:2s;animation:k 1s linear}', 1500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1s linear;animation-name:none', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1s linear;animation-name:none}', 500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:none', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:none}', 500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1s linear 1s paused', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1s linear 1s paused}', 0.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation:k 1s linear 1s paused', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1s linear 1s paused}', 500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation: linear 1s k', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation: linear 1s k}', 500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation: 1s 2s linear k', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation: 1s 2s linear k}', 500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation: 1s 2s linear k', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation: 1s 2s linear k}', 2500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation: k 1s 2s 3s', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation: k 1s 2s 3s}', 500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation-duration:1s;animation-name:k;animation-timing-function:linear;animation-iteration-count:2;animation-direction:reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-duration:1s;animation-name:k;animation-timing-function:linear;animation-iteration-count:2;animation-direction:reverse}', 250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation-duration:1s;animation-name:k;animation-timing-function:linear;animation-iteration-count:2;animation-direction:reverse', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-duration:1s;animation-name:k;animation-timing-function:linear;animation-iteration-count:2;animation-direction:reverse}', 1250.0, ['width', 'height'], '175px | 20px', [1.01])
animRow('animation-name:missing', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:missing}', 500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation-name:k,k2;animation-duration:1s,3s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k,k2;animation-duration:1s,3s;animation-timing-function:linear}', 500.0, ['width', 'height'], '11.6562px | 11.6562px', [1.01])
animRow('animation-name:k,k2;animation-duration:1s,3s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k,k2;animation-duration:1s,3s;animation-timing-function:linear}', 1500.0, ['width', 'height'], '15px | 15px', [1.01])
animRow('animation-name:k,k2;animation-duration:1s,3s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k,k2;animation-duration:1s,3s;animation-timing-function:linear}', 2500.0, ['width', 'height'], '18.3281px | 18.3281px', [1.01])
animRow('animation-name:k;animation-duration:1s,3s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k;animation-duration:1s,3s;animation-timing-function:linear}', 500.0, ['width', 'height'], '150px | 20px', [1.01])
animRow('animation-name:k;animation-duration:1s,3s;animation-timing-function:linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k;animation-duration:1s,3s;animation-timing-function:linear}', 1500.0, ['width', 'height'], '50px | 20px', [1.01])
animRow('animation-name:k,k;animation-duration:1s;animation-timing-function:linear,ease-in;animation-delay:0s', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation-name:k,k;animation-duration:1s;animation-timing-function:linear,ease-in;animation-delay:0s}', 500.0, ['width', 'height'], '131.531px | 20px', [1.01])
animRow('animation:k 1s linear, k2 2s linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1s linear, k2 2s linear}', 500.0, ['width', 'height'], '12.5px | 12.5px', [1.01])
animRow('animation:k 1s linear, k2 2s linear', '@keyframes k{from{width:100px}to{width:200px}}@keyframes k2{from{width:10px;height:10px}to{width:20px;height:20px}}#e{animation:k 1s linear, k2 2s linear}', 1500.0, ['width', 'height'], '17.5px | 17.5px', [1.01])
animRow('color rgb', '@keyframes k{from{color:rgb(255,0,0)}to{color:rgb(0,0,255)}}#e{animation:k 1000ms linear}', 0.0, ['color'], 'rgb(255, 0, 0)', [1.6, 1.6, 1.6, 0.02])
animRow('color rgb', '@keyframes k{from{color:rgb(255,0,0)}to{color:rgb(0,0,255)}}#e{animation:k 1000ms linear}', 250.0, ['color'], 'rgb(191, 0, 64)', [1.6, 1.6, 1.6, 0.02])
animRow('color rgb', '@keyframes k{from{color:rgb(255,0,0)}to{color:rgb(0,0,255)}}#e{animation:k 1000ms linear}', 500.0, ['color'], 'rgb(128, 0, 128)', [1.6, 1.6, 1.6, 0.02])
animRow('color rgb', '@keyframes k{from{color:rgb(255,0,0)}to{color:rgb(0,0,255)}}#e{animation:k 1000ms linear}', 999.0, ['color'], 'rgb(0, 0, 255)', [1.6, 1.6, 1.6, 0.02])
animRow('color named', '@keyframes k{from{color:red}to{color:blue}}#e{animation:k 1000ms linear}', 0.0, ['color'], 'rgb(255, 0, 0)', [1.6, 1.6, 1.6, 0.02])
animRow('color named', '@keyframes k{from{color:red}to{color:blue}}#e{animation:k 1000ms linear}', 250.0, ['color'], 'rgb(191, 0, 64)', [1.6, 1.6, 1.6, 0.02])
animRow('color named', '@keyframes k{from{color:red}to{color:blue}}#e{animation:k 1000ms linear}', 500.0, ['color'], 'rgb(128, 0, 128)', [1.6, 1.6, 1.6, 0.02])
animRow('color named', '@keyframes k{from{color:red}to{color:blue}}#e{animation:k 1000ms linear}', 999.0, ['color'], 'rgb(0, 0, 255)', [1.6, 1.6, 1.6, 0.02])
animRow('color hex', '@keyframes k{from{color:#ff0000}to{color:#00ff0080}}#e{animation:k 1000ms linear}', 0.0, ['color'], 'rgb(255, 0, 0)', [1.6, 1.6, 1.6, 0.02])
animRow('color hex', '@keyframes k{from{color:#ff0000}to{color:#00ff0080}}#e{animation:k 1000ms linear}', 250.0, ['color'], 'rgba(218, 37, 0, 0.875)', [1.6, 1.6, 1.6, 0.02])
animRow('color hex', '@keyframes k{from{color:#ff0000}to{color:#00ff0080}}#e{animation:k 1000ms linear}', 500.0, ['color'], 'rgba(170, 85, 0, 0.753)', [1.6, 1.6, 1.6, 0.02])
animRow('color hex', '@keyframes k{from{color:#ff0000}to{color:#00ff0080}}#e{animation:k 1000ms linear}', 999.0, ['color'], 'rgba(1, 254, 0, 0.5)', [1.6, 1.6, 1.6, 0.02])
animRow('color alpha', '@keyframes k{from{background-color:rgba(255,0,0,.2)}to{background-color:rgba(255,0,0,1)}}#e{animation:k 1000ms linear}', 0.0, ['background-color'], 'rgba(255, 0, 0, 0.2)', [1.6, 1.6, 1.6, 0.02])
animRow('color alpha', '@keyframes k{from{background-color:rgba(255,0,0,.2)}to{background-color:rgba(255,0,0,1)}}#e{animation:k 1000ms linear}', 250.0, ['background-color'], 'rgba(255, 0, 0, 0.4)', [1.6, 1.6, 1.6, 0.02])
animRow('color alpha', '@keyframes k{from{background-color:rgba(255,0,0,.2)}to{background-color:rgba(255,0,0,1)}}#e{animation:k 1000ms linear}', 500.0, ['background-color'], 'rgba(255, 0, 0, 0.6)', [1.6, 1.6, 1.6, 0.02])
animRow('color alpha', '@keyframes k{from{background-color:rgba(255,0,0,.2)}to{background-color:rgba(255,0,0,1)}}#e{animation:k 1000ms linear}', 999.0, ['background-color'], 'rgba(255, 0, 0, 1)', [1.6, 1.6, 1.6, 0.02])
animRow('color premultiplied', '@keyframes k{from{background-color:rgba(255,0,0,0)}to{background-color:rgba(0,0,255,1)}}#e{animation:k 1000ms linear}', 0.0, ['background-color'], 'rgba(0, 0, 0, 0)', [1.6, 1.6, 1.6, 0.02])
animRow('color premultiplied', '@keyframes k{from{background-color:rgba(255,0,0,0)}to{background-color:rgba(0,0,255,1)}}#e{animation:k 1000ms linear}', 250.0, ['background-color'], 'rgba(0, 0, 255, 0.25)', [1.6, 1.6, 1.6, 0.02])
animRow('color premultiplied', '@keyframes k{from{background-color:rgba(255,0,0,0)}to{background-color:rgba(0,0,255,1)}}#e{animation:k 1000ms linear}', 500.0, ['background-color'], 'rgba(0, 0, 255, 0.5)', [1.6, 1.6, 1.6, 0.02])
animRow('color premultiplied', '@keyframes k{from{background-color:rgba(255,0,0,0)}to{background-color:rgba(0,0,255,1)}}#e{animation:k 1000ms linear}', 999.0, ['background-color'], 'rgba(0, 0, 255, 1)', [1.6, 1.6, 1.6, 0.02])
animRow('color transparent to red', '@keyframes k{from{background-color:transparent}to{background-color:red}}#e{animation:k 1000ms linear}', 0.0, ['background-color'], 'rgba(0, 0, 0, 0)', [1.6, 1.6, 1.6, 0.02])
animRow('color transparent to red', '@keyframes k{from{background-color:transparent}to{background-color:red}}#e{animation:k 1000ms linear}', 250.0, ['background-color'], 'rgba(255, 0, 0, 0.25)', [1.6, 1.6, 1.6, 0.02])
animRow('color transparent to red', '@keyframes k{from{background-color:transparent}to{background-color:red}}#e{animation:k 1000ms linear}', 500.0, ['background-color'], 'rgba(255, 0, 0, 0.5)', [1.6, 1.6, 1.6, 0.02])
animRow('color transparent to red', '@keyframes k{from{background-color:transparent}to{background-color:red}}#e{animation:k 1000ms linear}', 999.0, ['background-color'], 'rgba(255, 0, 0, 1)', [1.6, 1.6, 1.6, 0.02])
animRow('color hsl', '@keyframes k{from{color:hsl(0,100%,50%)}to{color:hsl(240,100%,50%)}}#e{animation:k 1000ms linear}', 0.0, ['color'], 'rgb(255, 0, 0)', [1.6, 1.6, 1.6, 0.02])
animRow('color hsl', '@keyframes k{from{color:hsl(0,100%,50%)}to{color:hsl(240,100%,50%)}}#e{animation:k 1000ms linear}', 250.0, ['color'], 'rgb(191, 0, 64)', [1.6, 1.6, 1.6, 0.02])
animRow('color hsl', '@keyframes k{from{color:hsl(0,100%,50%)}to{color:hsl(240,100%,50%)}}#e{animation:k 1000ms linear}', 500.0, ['color'], 'rgb(128, 0, 128)', [1.6, 1.6, 1.6, 0.02])
animRow('color hsl', '@keyframes k{from{color:hsl(0,100%,50%)}to{color:hsl(240,100%,50%)}}#e{animation:k 1000ms linear}', 999.0, ['color'], 'rgb(0, 0, 255)', [1.6, 1.6, 1.6, 0.02])
animRow('color currentcolor', '@keyframes k{from{background-color:currentcolor}to{background-color:blue}}#e{color:red;animation:k 1000ms linear}', 0.0, ['background-color'], 'rgb(255, 0, 0)', [1.6, 1.6, 1.6, 0.02])
animRow('color currentcolor', '@keyframes k{from{background-color:currentcolor}to{background-color:blue}}#e{color:red;animation:k 1000ms linear}', 250.0, ['background-color'], 'rgb(191, 0, 64)', [1.6, 1.6, 1.6, 0.02])
animRow('color currentcolor', '@keyframes k{from{background-color:currentcolor}to{background-color:blue}}#e{color:red;animation:k 1000ms linear}', 500.0, ['background-color'], 'rgb(128, 0, 128)', [1.6, 1.6, 1.6, 0.02])
animRow('color currentcolor', '@keyframes k{from{background-color:currentcolor}to{background-color:blue}}#e{color:red;animation:k 1000ms linear}', 999.0, ['background-color'], 'rgb(0, 0, 255)', [1.6, 1.6, 1.6, 0.02])
animRow('border-color', '@keyframes k{from{border-color:red}to{border-color:blue}}#e{border:2px solid;animation:k 1000ms linear}', 0.0, ['border-top-color', 'border-left-color'], 'rgb(255, 0, 0) | rgb(255, 0, 0)', [1.6, 1.6, 1.6, 0.02])
animRow('border-color', '@keyframes k{from{border-color:red}to{border-color:blue}}#e{border:2px solid;animation:k 1000ms linear}', 250.0, ['border-top-color', 'border-left-color'], 'rgb(191, 0, 64) | rgb(191, 0, 64)', [1.6, 1.6, 1.6, 0.02])
animRow('border-color', '@keyframes k{from{border-color:red}to{border-color:blue}}#e{border:2px solid;animation:k 1000ms linear}', 500.0, ['border-top-color', 'border-left-color'], 'rgb(128, 0, 128) | rgb(128, 0, 128)', [1.6, 1.6, 1.6, 0.02])
animRow('border-color', '@keyframes k{from{border-color:red}to{border-color:blue}}#e{border:2px solid;animation:k 1000ms linear}', 999.0, ['border-top-color', 'border-left-color'], 'rgb(0, 0, 255) | rgb(0, 0, 255)', [1.6, 1.6, 1.6, 0.02])
animRow('length px', '@keyframes k{from{width:0px}to{width:200px}}#e{animation:k 1000ms linear}', 0.0, ['width'], '0px', [1.01])
animRow('length px', '@keyframes k{from{width:0px}to{width:200px}}#e{animation:k 1000ms linear}', 250.0, ['width'], '50px', [1.01])
animRow('length px', '@keyframes k{from{width:0px}to{width:200px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '100px', [1.01])
animRow('length px', '@keyframes k{from{width:0px}to{width:200px}}#e{animation:k 1000ms linear}', 999.0, ['width'], '199.797px', [1.01])
animRow('length em', '@keyframes k{from{width:1em}to{width:10em}}#e{animation:k 1000ms linear}', 0.0, ['width'], '16px', [1.01])
animRow('length em', '@keyframes k{from{width:1em}to{width:10em}}#e{animation:k 1000ms linear}', 250.0, ['width'], '52px', [1.01])
animRow('length em', '@keyframes k{from{width:1em}to{width:10em}}#e{animation:k 1000ms linear}', 500.0, ['width'], '88px', [1.01])
animRow('length em', '@keyframes k{from{width:1em}to{width:10em}}#e{animation:k 1000ms linear}', 999.0, ['width'], '159.844px', [1.01])
animRow('length px to em', '@keyframes k{from{width:100px}to{width:10em}}#e{animation:k 1000ms linear}', 0.0, ['width'], '100px', [1.01])
animRow('length px to em', '@keyframes k{from{width:100px}to{width:10em}}#e{animation:k 1000ms linear}', 250.0, ['width'], '115px', [1.01])
animRow('length px to em', '@keyframes k{from{width:100px}to{width:10em}}#e{animation:k 1000ms linear}', 500.0, ['width'], '130px', [1.01])
animRow('length px to em', '@keyframes k{from{width:100px}to{width:10em}}#e{animation:k 1000ms linear}', 999.0, ['width'], '159.938px', [1.01])
animRow('length px to percent', '@keyframes k{from{width:100px}to{width:50%}}#e{animation:k 1000ms linear}', 0.0, ['width'], '100px', [1.01])
animRow('length px to percent', '@keyframes k{from{width:100px}to{width:50%}}#e{animation:k 1000ms linear}', 250.0, ['width'], '125px', [1.01])
animRow('length px to percent', '@keyframes k{from{width:100px}to{width:50%}}#e{animation:k 1000ms linear}', 500.0, ['width'], '150px', [1.01])
animRow('length px to percent', '@keyframes k{from{width:100px}to{width:50%}}#e{animation:k 1000ms linear}', 999.0, ['width'], '199.891px', [1.01])
animRow('length percent', '@keyframes k{from{width:10%}to{width:50%}}#e{animation:k 1000ms linear}', 0.0, ['width'], '40px', [1.01])
animRow('length percent', '@keyframes k{from{width:10%}to{width:50%}}#e{animation:k 1000ms linear}', 250.0, ['width'], '80px', [1.01])
animRow('length percent', '@keyframes k{from{width:10%}to{width:50%}}#e{animation:k 1000ms linear}', 500.0, ['width'], '120px', [1.01])
animRow('length percent', '@keyframes k{from{width:10%}to{width:50%}}#e{animation:k 1000ms linear}', 999.0, ['width'], '199.828px', [1.01])
animRow('length to auto', '@keyframes k{from{width:100px}to{width:auto}}#e{animation:k 1000ms linear}', 0.0, ['width'], '100px', [1.01])
animRow('length to auto', '@keyframes k{from{width:100px}to{width:auto}}#e{animation:k 1000ms linear}', 250.0, ['width'], '100px', [1.01])
animRow('length to auto', '@keyframes k{from{width:100px}to{width:auto}}#e{animation:k 1000ms linear}', 500.0, ['width'], '400px', [1.01])
animRow('length to auto', '@keyframes k{from{width:100px}to{width:auto}}#e{animation:k 1000ms linear}', 999.0, ['width'], '400px', [1.01])
animRow('length calc', '@keyframes k{from{width:calc(10px + 10%)}to{width:calc(50px + 20%)}}#e{animation:k 1000ms linear}', 0.0, ['width'], '50px', [1.01])
animRow('length calc', '@keyframes k{from{width:calc(10px + 10%)}to{width:calc(50px + 20%)}}#e{animation:k 1000ms linear}', 250.0, ['width'], '70px', [1.01])
animRow('length calc', '@keyframes k{from{width:calc(10px + 10%)}to{width:calc(50px + 20%)}}#e{animation:k 1000ms linear}', 500.0, ['width'], '90px', [1.01])
animRow('length calc', '@keyframes k{from{width:calc(10px + 10%)}to{width:calc(50px + 20%)}}#e{animation:k 1000ms linear}', 999.0, ['width'], '129.906px', [1.01])
animRow('margin shorthand', '@keyframes k{from{margin:0px 10px}to{margin:40px 50px}}#e{animation:k 1000ms linear}', 0.0, ['margin-top', 'margin-right', 'margin-bottom', 'margin-left'], '0px | 10px | 0px | 10px', [1.01])
animRow('margin shorthand', '@keyframes k{from{margin:0px 10px}to{margin:40px 50px}}#e{animation:k 1000ms linear}', 250.0, ['margin-top', 'margin-right', 'margin-bottom', 'margin-left'], '10px | 20px | 10px | 20px', [1.01])
animRow('margin shorthand', '@keyframes k{from{margin:0px 10px}to{margin:40px 50px}}#e{animation:k 1000ms linear}', 500.0, ['margin-top', 'margin-right', 'margin-bottom', 'margin-left'], '20px | 30px | 20px | 30px', [1.01])
animRow('margin shorthand', '@keyframes k{from{margin:0px 10px}to{margin:40px 50px}}#e{animation:k 1000ms linear}', 999.0, ['margin-top', 'margin-right', 'margin-bottom', 'margin-left'], '39.96px | 49.96px | 39.96px | 49.96px', [1.01])
animRow('padding', '@keyframes k{from{padding:0}to{padding:40px}}#e{animation:k 1000ms linear}', 0.0, ['padding-left'], '0px', [1.01])
animRow('padding', '@keyframes k{from{padding:0}to{padding:40px}}#e{animation:k 1000ms linear}', 250.0, ['padding-left'], '10px', [1.01])
animRow('padding', '@keyframes k{from{padding:0}to{padding:40px}}#e{animation:k 1000ms linear}', 500.0, ['padding-left'], '20px', [1.01])
animRow('padding', '@keyframes k{from{padding:0}to{padding:40px}}#e{animation:k 1000ms linear}', 999.0, ['padding-left'], '39.96px', [1.01])
animRow('border-width', '@keyframes k{from{border:0px solid}to{border:8px solid}}#e{animation:k 1000ms linear}', 0.0, ['border-top-width'], '0px', [1.01])
animRow('border-width', '@keyframes k{from{border:0px solid}to{border:8px solid}}#e{animation:k 1000ms linear}', 250.0, ['border-top-width'], '2px', [1.01])
animRow('border-width', '@keyframes k{from{border:0px solid}to{border:8px solid}}#e{animation:k 1000ms linear}', 500.0, ['border-top-width'], '4px', [1.01])
animRow('border-width', '@keyframes k{from{border:0px solid}to{border:8px solid}}#e{animation:k 1000ms linear}', 999.0, ['border-top-width'], '7px', [1.01])
animRow('border-radius', '@keyframes k{from{border-radius:0px}to{border-radius:40px}}#e{animation:k 1000ms linear}', 0.0, ['border-top-left-radius'], '0px', [1.01])
animRow('border-radius', '@keyframes k{from{border-radius:0px}to{border-radius:40px}}#e{animation:k 1000ms linear}', 250.0, ['border-top-left-radius'], '10px', [1.01])
animRow('border-radius', '@keyframes k{from{border-radius:0px}to{border-radius:40px}}#e{animation:k 1000ms linear}', 500.0, ['border-top-left-radius'], '20px', [1.01])
animRow('border-radius', '@keyframes k{from{border-radius:0px}to{border-radius:40px}}#e{animation:k 1000ms linear}', 999.0, ['border-top-left-radius'], '39.96px', [1.01])
animRow('font-size', '@keyframes k{from{font-size:10px}to{font-size:30px}}#e{animation:k 1000ms linear}', 0.0, ['font-size'], '10px', [1.01])
animRow('font-size', '@keyframes k{from{font-size:10px}to{font-size:30px}}#e{animation:k 1000ms linear}', 250.0, ['font-size'], '15px', [1.01])
animRow('font-size', '@keyframes k{from{font-size:10px}to{font-size:30px}}#e{animation:k 1000ms linear}', 500.0, ['font-size'], '20px', [1.01])
animRow('font-size', '@keyframes k{from{font-size:10px}to{font-size:30px}}#e{animation:k 1000ms linear}', 999.0, ['font-size'], '29.98px', [1.01])
animRow('line-height number', '@keyframes k{from{line-height:1}to{line-height:3}}#e{animation:k 1000ms linear}', 0.0, ['line-height'], '16px', [1.01])
animRow('line-height number', '@keyframes k{from{line-height:1}to{line-height:3}}#e{animation:k 1000ms linear}', 250.0, ['line-height'], '24px', [1.01])
animRow('line-height number', '@keyframes k{from{line-height:1}to{line-height:3}}#e{animation:k 1000ms linear}', 500.0, ['line-height'], '32px', [1.01])
animRow('line-height number', '@keyframes k{from{line-height:1}to{line-height:3}}#e{animation:k 1000ms linear}', 999.0, ['line-height'], '47.968px', [1.01])
animRow('letter-spacing', '@keyframes k{from{letter-spacing:0px}to{letter-spacing:8px}}#e{animation:k 1000ms linear}', 0.0, ['letter-spacing'], '0px', [1.01])
animRow('letter-spacing', '@keyframes k{from{letter-spacing:0px}to{letter-spacing:8px}}#e{animation:k 1000ms linear}', 250.0, ['letter-spacing'], '2px', [1.01])
animRow('letter-spacing', '@keyframes k{from{letter-spacing:0px}to{letter-spacing:8px}}#e{animation:k 1000ms linear}', 500.0, ['letter-spacing'], '4px', [1.01])
animRow('letter-spacing', '@keyframes k{from{letter-spacing:0px}to{letter-spacing:8px}}#e{animation:k 1000ms linear}', 999.0, ['letter-spacing'], '7.992px', [1.01])
animRow('z-index', '@keyframes k{from{z-index:0}to{z-index:10}}#e{position:relative;animation:k 1000ms linear}', 0.0, ['z-index'], '0', [0.02])
animRow('z-index', '@keyframes k{from{z-index:0}to{z-index:10}}#e{position:relative;animation:k 1000ms linear}', 250.0, ['z-index'], '3', [0.02])
animRow('z-index', '@keyframes k{from{z-index:0}to{z-index:10}}#e{position:relative;animation:k 1000ms linear}', 500.0, ['z-index'], '5', [0.02])
animRow('z-index', '@keyframes k{from{z-index:0}to{z-index:10}}#e{position:relative;animation:k 1000ms linear}', 999.0, ['z-index'], '10', [0.02])
animRow('flex-grow', '@keyframes k{from{flex-grow:0}to{flex-grow:4}}#e{animation:k 1000ms linear}', 0.0, ['flex-grow'], '0', [0.02])
animRow('flex-grow', '@keyframes k{from{flex-grow:0}to{flex-grow:4}}#e{animation:k 1000ms linear}', 250.0, ['flex-grow'], '1', [0.02])
animRow('flex-grow', '@keyframes k{from{flex-grow:0}to{flex-grow:4}}#e{animation:k 1000ms linear}', 500.0, ['flex-grow'], '2', [0.02])
animRow('flex-grow', '@keyframes k{from{flex-grow:0}to{flex-grow:4}}#e{animation:k 1000ms linear}', 999.0, ['flex-grow'], '3.996', [0.02])
animRow('opacity', '@keyframes k{from{opacity:.2}to{opacity:.8}}#e{animation:k 1000ms linear}', 0.0, ['opacity'], '0.2', [0.02])
animRow('opacity', '@keyframes k{from{opacity:.2}to{opacity:.8}}#e{animation:k 1000ms linear}', 250.0, ['opacity'], '0.35', [0.02])
animRow('opacity', '@keyframes k{from{opacity:.2}to{opacity:.8}}#e{animation:k 1000ms linear}', 500.0, ['opacity'], '0.5', [0.02])
animRow('opacity', '@keyframes k{from{opacity:.2}to{opacity:.8}}#e{animation:k 1000ms linear}', 999.0, ['opacity'], '0.7994', [0.02])
animRow('top/left', '@keyframes k{from{top:0px;left:0px}to{top:100px;left:200px}}#e{position:absolute;animation:k 1000ms linear}', 0.0, ['top', 'left'], '0px | 0px', [1.01])
animRow('top/left', '@keyframes k{from{top:0px;left:0px}to{top:100px;left:200px}}#e{position:absolute;animation:k 1000ms linear}', 250.0, ['top', 'left'], '25px | 50px', [1.01])
animRow('top/left', '@keyframes k{from{top:0px;left:0px}to{top:100px;left:200px}}#e{position:absolute;animation:k 1000ms linear}', 500.0, ['top', 'left'], '50px | 100px', [1.01])
animRow('top/left', '@keyframes k{from{top:0px;left:0px}to{top:100px;left:200px}}#e{position:absolute;animation:k 1000ms linear}', 999.0, ['top', 'left'], '99.9px | 199.8px', [1.01])
animRow('visibility', '@keyframes k{from{visibility:hidden}to{visibility:visible}}#e{animation:k 1000ms linear}', 0.0, ['visibility'], 'hidden', [0.0])
animRow('visibility', '@keyframes k{from{visibility:hidden}to{visibility:visible}}#e{animation:k 1000ms linear}', 250.0, ['visibility'], 'visible', [0.0])
animRow('visibility', '@keyframes k{from{visibility:hidden}to{visibility:visible}}#e{animation:k 1000ms linear}', 500.0, ['visibility'], 'visible', [0.0])
animRow('visibility', '@keyframes k{from{visibility:hidden}to{visibility:visible}}#e{animation:k 1000ms linear}', 999.0, ['visibility'], 'visible', [0.0])
animRow('visibility both visible', '@keyframes k{from{visibility:visible}to{visibility:hidden}}#e{animation:k 1000ms linear}', 0.0, ['visibility'], 'visible', [0.0])
animRow('visibility both visible', '@keyframes k{from{visibility:visible}to{visibility:hidden}}#e{animation:k 1000ms linear}', 250.0, ['visibility'], 'visible', [0.0])
animRow('visibility both visible', '@keyframes k{from{visibility:visible}to{visibility:hidden}}#e{animation:k 1000ms linear}', 500.0, ['visibility'], 'visible', [0.0])
animRow('visibility both visible', '@keyframes k{from{visibility:visible}to{visibility:hidden}}#e{animation:k 1000ms linear}', 999.0, ['visibility'], 'visible', [0.0])
animRow('display', '@keyframes k{from{display:block}to{display:none}}#e{animation:k 1000ms linear}', 0.0, ['display'], 'block', [0.02])
animRow('display', '@keyframes k{from{display:block}to{display:none}}#e{animation:k 1000ms linear}', 250.0, ['display'], 'block', [0.02])
animRow('display', '@keyframes k{from{display:block}to{display:none}}#e{animation:k 1000ms linear}', 500.0, ['display'], 'block', [0.02])
animRow('display', '@keyframes k{from{display:block}to{display:none}}#e{animation:k 1000ms linear}', 999.0, ['display'], 'block', [0.02])
animRow('position discrete', '@keyframes k{from{position:relative}to{position:absolute}}#e{animation:k 1000ms linear}', 0.0, ['position'], 'relative', [0.02])
animRow('position discrete', '@keyframes k{from{position:relative}to{position:absolute}}#e{animation:k 1000ms linear}', 250.0, ['position'], 'relative', [0.02])
animRow('position discrete', '@keyframes k{from{position:relative}to{position:absolute}}#e{animation:k 1000ms linear}', 500.0, ['position'], 'absolute', [0.02])
animRow('position discrete', '@keyframes k{from{position:relative}to{position:absolute}}#e{animation:k 1000ms linear}', 999.0, ['position'], 'absolute', [0.02])
animRow('text-align', '@keyframes k{from{text-align:left}to{text-align:right}}#e{animation:k 1000ms linear}', 0.0, ['text-align'], 'left', [0.02])
animRow('text-align', '@keyframes k{from{text-align:left}to{text-align:right}}#e{animation:k 1000ms linear}', 250.0, ['text-align'], 'left', [0.02])
animRow('text-align', '@keyframes k{from{text-align:left}to{text-align:right}}#e{animation:k 1000ms linear}', 500.0, ['text-align'], 'right', [0.02])
animRow('text-align', '@keyframes k{from{text-align:left}to{text-align:right}}#e{animation:k 1000ms linear}', 999.0, ['text-align'], 'right', [0.02])
animRow('box-shadow', '@keyframes k{from{box-shadow:0 0 0 0 red}to{box-shadow:10px 20px 30px 4px blue}}#e{animation:k 1000ms linear}', 0.0, ['box-shadow'], 'rgb(255, 0, 0) 0px 0px 0px 0px', [1.6, 1.6, 1.6, 1.01])
animRow('box-shadow', '@keyframes k{from{box-shadow:0 0 0 0 red}to{box-shadow:10px 20px 30px 4px blue}}#e{animation:k 1000ms linear}', 250.0, ['box-shadow'], 'rgb(191, 0, 64) 2.5px 5px 7.5px 1px', [1.6, 1.6, 1.6, 1.01])
animRow('box-shadow', '@keyframes k{from{box-shadow:0 0 0 0 red}to{box-shadow:10px 20px 30px 4px blue}}#e{animation:k 1000ms linear}', 500.0, ['box-shadow'], 'rgb(128, 0, 128) 5px 10px 15px 2px', [1.6, 1.6, 1.6, 1.01])
animRow('box-shadow', '@keyframes k{from{box-shadow:0 0 0 0 red}to{box-shadow:10px 20px 30px 4px blue}}#e{animation:k 1000ms linear}', 999.0, ['box-shadow'], 'rgb(0, 0, 255) 9.99px 19.98px 29.97px 3.996px', [1.6, 1.6, 1.6, 1.01])
animRow('box-shadow lists mismatched', '@keyframes k{from{box-shadow:0 0 0 0 red}to{box-shadow:10px 20px 30px 4px blue, 1px 1px 1px 1px black}}#e{animation:k 1000ms linear}', 0.0, ['box-shadow'], 'rgb(255, 0, 0) 0px 0px 0px 0px, rgba(0, 0, 0, 0) 0px 0px 0px 0px', [1.6, 1.6, 1.6, 1.01])
animRow('box-shadow lists mismatched', '@keyframes k{from{box-shadow:0 0 0 0 red}to{box-shadow:10px 20px 30px 4px blue, 1px 1px 1px 1px black}}#e{animation:k 1000ms linear}', 250.0, ['box-shadow'], 'rgb(191, 0, 64) 2.5px 5px 7.5px 1px, rgba(0, 0, 0, 0.25) 0.25px 0.25px 0.25px 0.25px', [1.6, 1.6, 1.6, 1.01])
animRow('box-shadow lists mismatched', '@keyframes k{from{box-shadow:0 0 0 0 red}to{box-shadow:10px 20px 30px 4px blue, 1px 1px 1px 1px black}}#e{animation:k 1000ms linear}', 500.0, ['box-shadow'], 'rgb(128, 0, 128) 5px 10px 15px 2px, rgba(0, 0, 0, 0.5) 0.5px 0.5px 0.5px 0.5px', [1.6, 1.6, 1.6, 1.01])
animRow('box-shadow lists mismatched', '@keyframes k{from{box-shadow:0 0 0 0 red}to{box-shadow:10px 20px 30px 4px blue, 1px 1px 1px 1px black}}#e{animation:k 1000ms linear}', 999.0, ['box-shadow'], 'rgb(0, 0, 255) 9.99px 19.98px 29.97px 3.996px, rgba(0, 0, 0, 1) 0.999px 0.999px 0.999px 0.999px', [1.6, 1.6, 1.6, 1.01])
animRow('background-position', '@keyframes k{from{background-position:0px 0px}to{background-position:100px 50px}}#e{animation:k 1000ms linear}', 0.0, ['background-position'], '0px 0px', [1.01])
animRow('background-position', '@keyframes k{from{background-position:0px 0px}to{background-position:100px 50px}}#e{animation:k 1000ms linear}', 250.0, ['background-position'], '25px 12.5px', [1.01])
animRow('background-position', '@keyframes k{from{background-position:0px 0px}to{background-position:100px 50px}}#e{animation:k 1000ms linear}', 500.0, ['background-position'], '50px 25px', [1.01])
animRow('background-position', '@keyframes k{from{background-position:0px 0px}to{background-position:100px 50px}}#e{animation:k 1000ms linear}', 999.0, ['background-position'], '99.9px 49.95px', [1.01])
animRow('background-size', '@keyframes k{from{background-size:10px 10px}to{background-size:50px 30px}}#e{animation:k 1000ms linear}', 0.0, ['background-size'], '10px 10px', [1.01])
animRow('background-size', '@keyframes k{from{background-size:10px 10px}to{background-size:50px 30px}}#e{animation:k 1000ms linear}', 250.0, ['background-size'], '20px 15px', [1.01])
animRow('background-size', '@keyframes k{from{background-size:10px 10px}to{background-size:50px 30px}}#e{animation:k 1000ms linear}', 500.0, ['background-size'], '30px 20px', [1.01])
animRow('background-size', '@keyframes k{from{background-size:10px 10px}to{background-size:50px 30px}}#e{animation:k 1000ms linear}', 999.0, ['background-size'], '49.96px 29.98px', [1.01])
animRow('width min()', '@keyframes k{from{width:min(10px,20px)}to{width:100px}}#e{animation:k 1000ms linear}', 0.0, ['width'], '10px', [1.01])
animRow('width min()', '@keyframes k{from{width:min(10px,20px)}to{width:100px}}#e{animation:k 1000ms linear}', 250.0, ['width'], '32.5px', [1.01])
animRow('width min()', '@keyframes k{from{width:min(10px,20px)}to{width:100px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '55px', [1.01])
animRow('width min()', '@keyframes k{from{width:min(10px,20px)}to{width:100px}}#e{animation:k 1000ms linear}', 999.0, ['width'], '99.9062px', [1.01])
animRow('var()', '@keyframes k{from{--w:100px;width:var(--w)}to{--w:200px;width:var(--w)}}#e{animation:k 1000ms linear}', 0.0, ['width'], '100px', [1.01])
animRow('var()', '@keyframes k{from{--w:100px;width:var(--w)}to{--w:200px;width:var(--w)}}#e{animation:k 1000ms linear}', 250.0, ['width'], '100px', [1.01])
animRow('var()', '@keyframes k{from{--w:100px;width:var(--w)}to{--w:200px;width:var(--w)}}#e{animation:k 1000ms linear}', 500.0, ['width'], '200px', [1.01])
animRow('var()', '@keyframes k{from{--w:100px;width:var(--w)}to{--w:200px;width:var(--w)}}#e{animation:k 1000ms linear}', 999.0, ['width'], '200px', [1.01])
animRow('inherit keyword', '@keyframes k{from{width:inherit}to{width:100px}}#e{animation:k 1000ms linear}', 0.0, ['width'], '400px', [1.01])
animRow('inherit keyword', '@keyframes k{from{width:inherit}to{width:100px}}#e{animation:k 1000ms linear}', 250.0, ['width'], '400px', [1.01])
animRow('inherit keyword', '@keyframes k{from{width:inherit}to{width:100px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '100px', [1.01])
animRow('inherit keyword', '@keyframes k{from{width:inherit}to{width:100px}}#e{animation:k 1000ms linear}', 999.0, ['width'], '100px', [1.01])
animRow('initial keyword', '@keyframes k{from{width:initial}to{width:100px}}#e{animation:k 1000ms linear}', 0.0, ['width'], '400px', [1.01])
animRow('initial keyword', '@keyframes k{from{width:initial}to{width:100px}}#e{animation:k 1000ms linear}', 250.0, ['width'], '400px', [1.01])
animRow('initial keyword', '@keyframes k{from{width:initial}to{width:100px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '100px', [1.01])
animRow('initial keyword', '@keyframes k{from{width:initial}to{width:100px}}#e{animation:k 1000ms linear}', 999.0, ['width'], '100px', [1.01])
animRow('!important in keyframe ignored', '@keyframes k{from{width:100px !important}to{width:200px}}#e{animation:k 1000ms linear}', 0.0, ['width'], '50px', [1.01])
animRow('!important in keyframe ignored', '@keyframes k{from{width:100px !important}to{width:200px}}#e{animation:k 1000ms linear}', 250.0, ['width'], '87.5px', [1.01])
animRow('!important in keyframe ignored', '@keyframes k{from{width:100px !important}to{width:200px}}#e{animation:k 1000ms linear}', 500.0, ['width'], '125px', [1.01])
animRow('!important in keyframe ignored', '@keyframes k{from{width:100px !important}to{width:200px}}#e{animation:k 1000ms linear}', 999.0, ['width'], '199.844px', [1.01])
animRow('aspect-ratio', '@keyframes k{from{aspect-ratio:1}to{aspect-ratio:3}}#e{animation:k 1000ms linear}', 0.0, ['aspect-ratio'], '1 / 1', [0.02])
animRow('aspect-ratio', '@keyframes k{from{aspect-ratio:1}to{aspect-ratio:3}}#e{animation:k 1000ms linear}', 250.0, ['aspect-ratio'], '1.31607 / 1', [0.02])
animRow('aspect-ratio', '@keyframes k{from{aspect-ratio:1}to{aspect-ratio:3}}#e{animation:k 1000ms linear}', 500.0, ['aspect-ratio'], '1.73205 / 1', [0.02])
animRow('aspect-ratio', '@keyframes k{from{aspect-ratio:1}to{aspect-ratio:3}}#e{animation:k 1000ms linear}', 999.0, ['aspect-ratio'], '2.99671 / 1', [0.02])
animRow('outline-offset', '@keyframes k{from{outline-offset:0px}to{outline-offset:20px}}#e{animation:k 1000ms linear}', 0.0, ['outline-offset'], '0px', [1.01])
animRow('outline-offset', '@keyframes k{from{outline-offset:0px}to{outline-offset:20px}}#e{animation:k 1000ms linear}', 250.0, ['outline-offset'], '5px', [1.01])
animRow('outline-offset', '@keyframes k{from{outline-offset:0px}to{outline-offset:20px}}#e{animation:k 1000ms linear}', 500.0, ['outline-offset'], '10px', [1.01])
animRow('outline-offset', '@keyframes k{from{outline-offset:0px}to{outline-offset:20px}}#e{animation:k 1000ms linear}', 999.0, ['outline-offset'], '19.9688px', [1.01])
animRow('gap', '@keyframes k{from{gap:0px}to{gap:20px}}#e{display:flex;animation:k 1000ms linear}', 0.0, ['column-gap'], '0px', [1.01])
animRow('gap', '@keyframes k{from{gap:0px}to{gap:20px}}#e{display:flex;animation:k 1000ms linear}', 250.0, ['column-gap'], '5px', [1.01])
animRow('gap', '@keyframes k{from{gap:0px}to{gap:20px}}#e{display:flex;animation:k 1000ms linear}', 500.0, ['column-gap'], '10px', [1.01])
animRow('gap', '@keyframes k{from{gap:0px}to{gap:20px}}#e{display:flex;animation:k 1000ms linear}', 999.0, ['column-gap'], '19.98px', [1.01])
animRow('flex-basis', '@keyframes k{from{flex-basis:10px}to{flex-basis:110px}}#e{animation:k 1000ms linear}', 0.0, ['flex-basis'], '10px', [1.01])
animRow('flex-basis', '@keyframes k{from{flex-basis:10px}to{flex-basis:110px}}#e{animation:k 1000ms linear}', 250.0, ['flex-basis'], '35px', [1.01])
animRow('flex-basis', '@keyframes k{from{flex-basis:10px}to{flex-basis:110px}}#e{animation:k 1000ms linear}', 500.0, ['flex-basis'], '60px', [1.01])
animRow('flex-basis', '@keyframes k{from{flex-basis:10px}to{flex-basis:110px}}#e{animation:k 1000ms linear}', 999.0, ['flex-basis'], '109.9px', [1.01])
animRow('order integer', '@keyframes k{from{order:0}to{order:5}}#e{animation:k 1000ms linear}', 0.0, ['order'], '0', [0.02])
animRow('order integer', '@keyframes k{from{order:0}to{order:5}}#e{animation:k 1000ms linear}', 250.0, ['order'], '1', [0.02])
animRow('order integer', '@keyframes k{from{order:0}to{order:5}}#e{animation:k 1000ms linear}', 500.0, ['order'], '3', [0.02])
animRow('order integer', '@keyframes k{from{order:0}to{order:5}}#e{animation:k 1000ms linear}', 999.0, ['order'], '5', [0.02])
animRow('column-count', '@keyframes k{from{column-count:1}to{column-count:5}}#e{animation:k 1000ms linear}', 0.0, ['column-count'], '1', [0.02])
animRow('column-count', '@keyframes k{from{column-count:1}to{column-count:5}}#e{animation:k 1000ms linear}', 250.0, ['column-count'], '2', [0.02])
animRow('column-count', '@keyframes k{from{column-count:1}to{column-count:5}}#e{animation:k 1000ms linear}', 500.0, ['column-count'], '3', [0.02])
animRow('column-count', '@keyframes k{from{column-count:1}to{column-count:5}}#e{animation:k 1000ms linear}', 999.0, ['column-count'], '5', [0.02])
animRow('translateX', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translateX', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1, 0, 0, 1, 25, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translateX', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1, 0, 0, 1, 50, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translateX', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1, 0, 0, 1, 99.9, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translate 2', '@keyframes k{from{transform:translate(0px,0px)}to{transform:translate(100px,40px)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translate 2', '@keyframes k{from{transform:translate(0px,0px)}to{transform:translate(100px,40px)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1, 0, 0, 1, 25, 10)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translate 2', '@keyframes k{from{transform:translate(0px,0px)}to{transform:translate(100px,40px)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1, 0, 0, 1, 50, 20)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translate 2', '@keyframes k{from{transform:translate(0px,0px)}to{transform:translate(100px,40px)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1, 0, 0, 1, 99.9, 39.96)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translate px to %', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(50%)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translate px to %', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(50%)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1, 0, 0, 1, 6.25, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translate px to %', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(50%)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1, 0, 0, 1, 12.5, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translate px to %', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(50%)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1, 0, 0, 1, 24.975, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scale', '@keyframes k{from{transform:scale(1)}to{transform:scale(2)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scale', '@keyframes k{from{transform:scale(1)}to{transform:scale(2)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1.25, 0, 0, 1.25, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scale', '@keyframes k{from{transform:scale(1)}to{transform:scale(2)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1.5, 0, 0, 1.5, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scale', '@keyframes k{from{transform:scale(1)}to{transform:scale(2)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1.999, 0, 0, 1.999, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scale 2', '@keyframes k{from{transform:scale(1,1)}to{transform:scale(3,2)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scale 2', '@keyframes k{from{transform:scale(1,1)}to{transform:scale(3,2)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1.5, 0, 0, 1.25, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scale 2', '@keyframes k{from{transform:scale(1,1)}to{transform:scale(3,2)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(2, 0, 0, 1.5, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scale 2', '@keyframes k{from{transform:scale(1,1)}to{transform:scale(3,2)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(2.998, 0, 0, 1.999, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate', '@keyframes k{from{transform:rotate(0deg)}to{transform:rotate(90deg)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate', '@keyframes k{from{transform:rotate(0deg)}to{transform:rotate(90deg)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(0.92388, 0.382683, -0.382683, 0.92388, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate', '@keyframes k{from{transform:rotate(0deg)}to{transform:rotate(90deg)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(0.707107, 0.707107, -0.707107, 0.707107, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate', '@keyframes k{from{transform:rotate(0deg)}to{transform:rotate(90deg)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(0.0015708, 0.999999, -0.999999, 0.0015708, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate turn to deg', '@keyframes k{from{transform:rotate(0turn)}to{transform:rotate(180deg)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate turn to deg', '@keyframes k{from{transform:rotate(0turn)}to{transform:rotate(180deg)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(0.707107, 0.707107, -0.707107, 0.707107, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate turn to deg', '@keyframes k{from{transform:rotate(0turn)}to{transform:rotate(180deg)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(0, 1, -1, 0, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate turn to deg', '@keyframes k{from{transform:rotate(0turn)}to{transform:rotate(180deg)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(-0.999995, 0.00314159, -0.00314159, -0.999995, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate 360', '@keyframes k{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate 360', '@keyframes k{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(0, 1, -1, 0, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate 360', '@keyframes k{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(-1, 0, 0, -1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('rotate 360', '@keyframes k{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(0.99998, -0.00628314, 0.00628314, 0.99998, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('matched list', '@keyframes k{from{transform:translateX(0px) rotate(0deg)}to{transform:translateX(100px) rotate(90deg)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('matched list', '@keyframes k{from{transform:translateX(0px) rotate(0deg)}to{transform:translateX(100px) rotate(90deg)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(0.92388, 0.382683, -0.382683, 0.92388, 25, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('matched list', '@keyframes k{from{transform:translateX(0px) rotate(0deg)}to{transform:translateX(100px) rotate(90deg)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(0.707107, 0.707107, -0.707107, 0.707107, 50, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('matched list', '@keyframes k{from{transform:translateX(0px) rotate(0deg)}to{transform:translateX(100px) rotate(90deg)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(0.0015708, 0.999999, -0.999999, 0.0015708, 99.9, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('mismatched fns', '@keyframes k{from{transform:translateX(0px)}to{transform:rotate(90deg)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('mismatched fns', '@keyframes k{from{transform:translateX(0px)}to{transform:rotate(90deg)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(0.92388, 0.382683, -0.382683, 0.92388, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('mismatched fns', '@keyframes k{from{transform:translateX(0px)}to{transform:rotate(90deg)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(0.707107, 0.707107, -0.707107, 0.707107, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('mismatched fns', '@keyframes k{from{transform:translateX(0px)}to{transform:rotate(90deg)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(0.0015708, 0.999999, -0.999999, 0.0015708, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('mismatched order', '@keyframes k{from{transform:translateX(0px) rotate(0deg)}to{transform:rotate(90deg) translateX(100px)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('mismatched order', '@keyframes k{from{transform:translateX(0px) rotate(0deg)}to{transform:rotate(90deg) translateX(100px)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(0.92388, 0.382683, -0.382683, 0.92388, 0, 25)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('mismatched order', '@keyframes k{from{transform:translateX(0px) rotate(0deg)}to{transform:rotate(90deg) translateX(100px)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(0.707107, 0.707107, -0.707107, 0.707107, 0, 50)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('mismatched order', '@keyframes k{from{transform:translateX(0px) rotate(0deg)}to{transform:rotate(90deg) translateX(100px)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(0.0015708, 0.999999, -0.999999, 0.0015708, 0, 99.9)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('none to fn', '@keyframes k{from{transform:none}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('none to fn', '@keyframes k{from{transform:none}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1, 0, 0, 1, 25, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('none to fn', '@keyframes k{from{transform:none}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1, 0, 0, 1, 50, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('none to fn', '@keyframes k{from{transform:none}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1, 0, 0, 1, 99.9, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('fn to none', '@keyframes k{from{transform:scale(2)}to{transform:none}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(2, 0, 0, 2, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('fn to none', '@keyframes k{from{transform:scale(2)}to{transform:none}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1.75, 0, 0, 1.75, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('fn to none', '@keyframes k{from{transform:scale(2)}to{transform:none}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1.5, 0, 0, 1.5, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('fn to none', '@keyframes k{from{transform:scale(2)}to{transform:none}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1.001, 0, 0, 1.001, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('longer list', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(100px) rotate(90deg)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('longer list', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(100px) rotate(90deg)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(0.92388, 0.382683, -0.382683, 0.92388, 25, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('longer list', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(100px) rotate(90deg)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(0.707107, 0.707107, -0.707107, 0.707107, 50, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('longer list', '@keyframes k{from{transform:translateX(0px)}to{transform:translateX(100px) rotate(90deg)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(0.0015708, 0.999999, -0.999999, 0.0015708, 99.9, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('prefix list', '@keyframes k{from{transform:translateX(0px) scale(1)}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('prefix list', '@keyframes k{from{transform:translateX(0px) scale(1)}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1, 0, 0, 1, 25, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('prefix list', '@keyframes k{from{transform:translateX(0px) scale(1)}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1, 0, 0, 1, 50, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('prefix list', '@keyframes k{from{transform:translateX(0px) scale(1)}to{transform:translateX(100px)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1, 0, 0, 1, 99.9, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translateY vs translate', '@keyframes k{from{transform:translateY(0px)}to{transform:translate(100px,100px)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translateY vs translate', '@keyframes k{from{transform:translateY(0px)}to{transform:translate(100px,100px)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1, 0, 0, 1, 25, 25)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translateY vs translate', '@keyframes k{from{transform:translateY(0px)}to{transform:translate(100px,100px)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1, 0, 0, 1, 50, 50)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('translateY vs translate', '@keyframes k{from{transform:translateY(0px)}to{transform:translate(100px,100px)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1, 0, 0, 1, 99.9, 99.9)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scaleX vs scale', '@keyframes k{from{transform:scaleX(1)}to{transform:scale(2)}}#e{animation:k 1000ms linear}', 0.0, ['transform'], 'matrix(1, 0, 0, 1, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scaleX vs scale', '@keyframes k{from{transform:scaleX(1)}to{transform:scale(2)}}#e{animation:k 1000ms linear}', 250.0, ['transform'], 'matrix(1.25, 0, 0, 1.25, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scaleX vs scale', '@keyframes k{from{transform:scaleX(1)}to{transform:scale(2)}}#e{animation:k 1000ms linear}', 500.0, ['transform'], 'matrix(1.5, 0, 0, 1.5, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])
animRow('scaleX vs scale', '@keyframes k{from{transform:scaleX(1)}to{transform:scale(2)}}#e{animation:k 1000ms linear}', 999.0, ['transform'], 'matrix(1.999, 0, 0, 1.999, 0, 0)', [0.02, 0.02, 0.02, 0.02, 1.01, 1.01])

finish('animations')
