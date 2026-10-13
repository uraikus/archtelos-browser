// Reading a computed value back as the text a browser's `getComputedStyle`
// gives, and comparing two such texts number by number. Shared by the
// suites that check this engine against values Chromium answered at a
// chosen moment of an animation or a transition.
//
// Lengths in this engine are whole pixels, so a length is compared to
// within a pixel, a colour channel to within 1.6 and an alpha to within
// 0.02.

import ../src/browser/page.f

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
    if prop == 'text-align' { return s.textAlign == ALIGN_RIGHT ? 'right' : (s.textAlign == ALIGN_CENTER ? 'center' : 'left') }
    if prop == 'display' { return s.display == DISPLAY_NONE ? 'none' : 'block' }
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
