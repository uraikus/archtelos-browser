// CSS colors at runtime. Festina's own `color` type is resolved by the
// compiler from a literal and there is deliberately no way to build one
// from a runtime text (api.md, "Computing a color or font at runtime"),
// so a renderer meeting `color: #336699` in a downloaded stylesheet
// has to parse it itself and paint through fillStyle(r, g, b).
//
// A color here is one int packing alpha and RGB:
//     a * 16777216 + r * 65536 + g * 256 + b
// with two sentinels: COLOR_UNSET (-1) for "no value / inherit" and
// COLOR_TRANSPARENT (0). There are no bitwise operators in Festina,
// so packing and unpacking are done with * / % (specification.md 7.6).

import text.f
import named_colors.f

const int COLOR_UNSET = -1
const int COLOR_TRANSPARENT = 0
const int COLOR_BLACK = 4278190080
const int COLOR_WHITE = 4294967295
const int COLOR_LINK = 4278190318       // #0000ee
const int COLOR_VISITED = 4283761785    // #551a8b

int func packColor(r:int, g:int, b:int, a:int) {
    return a * 16777216 + r * 65536 + g * 256 + b
}

int func colorAlpha(c:int) {
    if c < 0 { return 0 }
    return Math.floorDiv(c, 16777216) % 256
}
int func colorRed(c:int) {
    if c < 0 { return 0 }
    return Math.floorDiv(c, 65536) % 256
}
int func colorGreen(c:int) {
    if c < 0 { return 0 }
    return Math.floorDiv(c, 256) % 256
}
int func colorBlue(c:int) {
    if c < 0 { return 0 }
    return c % 256
}

bool func colorIsPaintable(c:int) {
    return c > 0 && colorAlpha(c) > 0
}

// Sets the canvas fill from a packed color, including its alpha.
void func applyFillColor(c:int) {
    fillStyle(colorRed(c), colorGreen(c), colorBlue(c))
    fillAlpha(colorAlpha(c).toFloat() / 255.0)
}

// Blends a color's own alpha with an inherited opacity multiplier.
int func colorWithOpacity(c:int, opacity:float) {
    if c <= 0 { return c }
    int a = roundPx(colorAlpha(c).toFloat() * opacity)
    return packColor(colorRed(c), colorGreen(c), colorBlue(c), clampInt(a, 0, 255))
}

int func clampChannel(v:float) {
    if v < 0.0 { return 0 }
    if v > 255.0 { return 255 }
    return Math.round(v)
}

// Parses one CSS <color>: named colors, #rgb, #rgba, #rrggbb,
// #rrggbbaa, rgb()/rgba() with commas or spaces and an optional
// alpha, hsl()/hsla(), `transparent` and `currentcolor`. Anything else
// answers COLOR_UNSET so the caller can fall back.
int func parseCssColor(raw:ascii, currentColor:int) {
    ascii s = asciiLower(asciiTrim(raw))
    if s == null || s.length == 0 { return COLOR_UNSET }
    if s == 'transparent' { return COLOR_TRANSPARENT }
    if s == 'currentcolor' { return currentColor }
    int c0 = s.charCodeAt(0)
    if c0 == CH_HASH {
        int n = s.length - 1
        for int i = 1, i <= n, i++ {
            if !isHexCode(s.charCodeAt(i)) { return COLOR_UNSET }
        }
        if n == 3 || n == 4 {
            int r = hexValue(s.charCodeAt(1)) * 17
            int g = hexValue(s.charCodeAt(2)) * 17
            int b = hexValue(s.charCodeAt(3)) * 17
            int a = n == 4 ? hexValue(s.charCodeAt(4)) * 17 : 255
            return packColor(r, g, b, a)
        }
        if n == 6 || n == 8 {
            int r = hexValue(s.charCodeAt(1)) * 16 + hexValue(s.charCodeAt(2))
            int g = hexValue(s.charCodeAt(3)) * 16 + hexValue(s.charCodeAt(4))
            int b = hexValue(s.charCodeAt(5)) * 16 + hexValue(s.charCodeAt(6))
            int a = n == 8 ? hexValue(s.charCodeAt(7)) * 16 + hexValue(s.charCodeAt(8)) : 255
            return packColor(r, g, b, a)
        }
        return COLOR_UNSET
    }
    int paren = asciiIndexOf(s, '(', 0)
    if paren > 0 && asciiEndsWith(s, ')') {
        ascii fn = s.slice(0, paren)
        ascii inner = s.slice(paren + 1, s.length - 1)
        arr[float] nums = parseColorComponents(inner, fn == 'hsl' || fn == 'hsla')
        if nums.length < 3 { return COLOR_UNSET }
        float alpha = nums.length >= 4 ? nums[3] : 1.0
        if alpha < 0.0 { alpha = 0.0 }
        if alpha > 1.0 { alpha = 1.0 }
        int a = Math.round(alpha * 255.0)
        if fn == 'rgb' || fn == 'rgba' {
            return packColor(clampChannel(nums[0]), clampChannel(nums[1]), clampChannel(nums[2]), a)
        }
        if fn == 'hsl' || fn == 'hsla' {
            return hslToPacked(nums[0], nums[1] / 100.0, nums[2] / 100.0, a)
        }
        return COLOR_UNSET
    }
    int named = cssNamedColors[s.toText()]
    if named == null { return COLOR_UNSET }
    return named + 255 * 16777216
}

// The numbers inside rgb(...)/hsl(...): separated by commas, spaces or
// a slash; a trailing '%' on a channel scales it to 0-255, on an
// alpha to 0-1.
arr[float] func parseColorComponents(inner:ascii, isHsl:bool) {
    arr[float] out = []
    int n = inner.length
    int i = 0
    while i < n {
        int c = inner.charCodeAt(i)
        if isSpaceCode(c) || c == CH_COMMA || c == CH_SLASH {
            i++
            continue
        }
        parseNumberAt(inner, i)
        if !numOk { return [] }
        float v = numValue
        i = numEnd
        bool percent = false
        if i < n && inner.charCodeAt(i) == CH_PERCENT {
            percent = true
            i++
        }
        // skip a unit such as "deg"
        while i < n && isAlphaCode(inner.charCodeAt(i)) { i++ }
        if percent {
            if out.length == 3 { v = v / 100.0 }
            else if !isHsl { v = v * 255.0 / 100.0 }
        }
        out.push(v)
    }
    return out
}

float func hueToChannel(p:float, q:float, tIn:float) {
    float t = tIn
    if t < 0.0 { t = t + 1.0 }
    if t > 1.0 { t = t - 1.0 }
    if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
    if t < 0.5 { return q }
    if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
    return p
}

int func hslToPacked(hDeg:float, s:float, l:float, a:int) {
    float h = (hDeg % 360.0) / 360.0
    if h < 0.0 { h = h + 1.0 }
    float r = l
    float g = l
    float b = l
    if s > 0.0 {
        float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
        float p = 2.0 * l - q
        r = hueToChannel(p, q, h + 1.0 / 3.0)
        g = hueToChannel(p, q, h)
        b = hueToChannel(p, q, h - 1.0 / 3.0)
    }
    return packColor(clampChannel(r * 255.0), clampChannel(g * 255.0), clampChannel(b * 255.0), a)
}
