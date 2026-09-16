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
const int COLOR_VISITED = 4283767435    // #551a8b

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

// CSS Color 4's system colors, which name a part of the user interface
// rather than a color. Their values are what this platform's light
// color scheme uses, taken from Chromium's own answer for each, so a
// page styled with them looks the same in both. The standard leaves
// them to the implementation, so these are a choice, not a conversion;
// `accentcolor` and `accentcolortext` are the selected-item pair,
// because the accent this platform selects with is the accent it has.
map[int] cssSystemColors = {
    'accentcolor': 4279855058,           // rgb(25, 103, 210)
    'accentcolortext': 4294967295,       // rgb(255, 255, 255)
    'activetext': 4294901760,            // rgb(255, 0, 0)
    'buttonborder': 4278190080,          // rgb(0, 0, 0)
    'buttonface': 4293914607,            // rgb(239, 239, 239)
    'buttontext': 4278190080,            // rgb(0, 0, 0)
    'canvas': 4294967295,                // rgb(255, 255, 255)
    'canvastext': 4278190080,            // rgb(0, 0, 0)
    'field': 4294967295,                 // rgb(255, 255, 255)
    'fieldtext': 4278190080,             // rgb(0, 0, 0)
    'graytext': 4286611584,              // rgb(128, 128, 128)
    'highlight': 3422568902,             // rgb(0, 65, 198) at 80% alpha
    'highlighttext': 4294967295,         // rgb(255, 255, 255)
    'linktext': 4278190318,              // rgb(0, 0, 238)
    'mark': 4294967040,                  // rgb(255, 255, 0)
    'marktext': 4278190080,              // rgb(0, 0, 0)
    'selecteditem': 4279855058,          // rgb(25, 103, 210)
    'selecteditemtext': 4294967295,      // rgb(255, 255, 255)
    'visitedtext': 4283767435            // rgb(85, 26, 139)
}

// Parses one CSS <color>: named colors, #rgb, #rgba, #rrggbb,
// #rrggbbaa, rgb()/rgba() with commas or spaces and an optional
// alpha, hsl()/hsla(), `transparent`, `currentcolor`, and CSS Color
// 4's wider spaces through parseWideColor below. Anything else
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
        bool isRgb = fn == 'rgb' || fn == 'rgba'
        bool isHsl = fn == 'hsl' || fn == 'hsla'
        if fn == 'color-mix' { return parseColorMix(inner, currentColor) }
        if !isRgb && !isHsl { return parseWideColor(fn, inner) }
        arr[float] nums = parseColorComponents(inner, isHsl)
        if nums.length < 3 { return COLOR_UNSET }
        float alpha = nums.length >= 4 ? nums[3] : 1.0
        if alpha < 0.0 { alpha = 0.0 }
        if alpha > 1.0 { alpha = 1.0 }
        int a = Math.round(alpha * 255.0)
        if isRgb {
            return packColor(clampChannel(nums[0]), clampChannel(nums[1]), clampChannel(nums[2]), a)
        }
        return hslToPacked(nums[0], nums[1] / 100.0, nums[2] / 100.0, a)
    }
    int named = cssNamedColors[s.toText()]
    if named != null { return named + 255 * 16777216 }
    int system = cssSystemColors[s.toText()]
    if system == null { return COLOR_UNSET }
    return system
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

// ---------------------------------------------------------------------
// CSS Color 4's wider color spaces: hwb(), lab(), lch(), oklab(),
// oklch() and color(). Every one of them ends in the same packed sRGB
// int the rest of the engine paints through, so the conversions below
// are the standard's own (CSS Color 4 §17, "Sample code for color
// conversions") transcribed: to XYZ, adapted to D65 where the space is
// defined against D50, through the sRGB primaries and out through the
// transfer function. A component outside the sRGB gamut is clamped per
// channel, which is what Chromium paints too.
//
// None of this runs for a page whose colors are hex, rgb() or a name:
// parseCssColor answers those before it reaches here.

const float CSS_PI = 3.14159265358979323846

// The angle units a <hue> may carry.
const int HUE_PLAIN = 0
const int HUE_DEG = 1
const int HUE_GRAD = 2
const int HUE_RAD = 3
const int HUE_TURN = 4

// scanColorArgs writes here: one entry per component, its raw number,
// whether it carried a '%', and which angle unit followed it. Three
// parallel arrays rather than one of records because the caller wants
// the three questions separately and Festina has no tuples.
arr[float] c4Value = []
arr[bool] c4Percent = []
arr[int] c4Unit = []
bool c4Ok = false

// Compares a region of an ascii against a word without slicing it out.
// Everything that reaches the color parser is a slice of a slice --
// parseCssColor lowercases the whole value, takes the inside of the
// parentheses out of that, and hands it here -- and a slice of a
// derived ascii aliases a buffer it does not own (see FINDINGS.md,
// "slicing an ascii that came from a slice"). Reading the characters
// where they lie takes no second slice at all.
bool func asciiRegionEquals(s:ascii, from:int, to:int, word:ascii) {
    if to - from != word.length { return false }
    for int i = 0, i < word.length, i++ {
        if s.charCodeAt(from + i) != word.charCodeAt(i) { return false }
    }
    return true
}

// Splits the inside of a color function into components, starting at
// `from` so color()'s space name can be stepped over without cutting it
// off. Separators are spaces, commas and the alpha slash alike, so both
// the legacy and the modern grammars fall out of the same loop. `none`
// is a component the standard gives no value, which for a color being
// painted rather than interpolated is zero.
void func scanColorArgs(inner:ascii, from:int) {
    c4Value = []
    c4Percent = []
    c4Unit = []
    c4Ok = true
    int n = inner.length
    int i = from
    while i < n {
        int ch = inner.charCodeAt(i)
        if isSpaceCode(ch) || ch == CH_COMMA || ch == CH_SLASH {
            i++
            continue
        }
        if asciiStartsWith(inner, 'none', i) {
            c4Value.push(0.0)
            c4Percent.push(false)
            c4Unit.push(HUE_PLAIN)
            i = i + 4
            continue
        }
        parseNumberAt(inner, i)
        if !numOk {
            c4Ok = false
            return
        }
        float v = numValue
        i = numEnd
        bool pct = false
        if i < n && inner.charCodeAt(i) == CH_PERCENT {
            pct = true
            i++
        }
        int unitStart = i
        while i < n && isAlphaCode(inner.charCodeAt(i)) { i++ }
        int unit = HUE_PLAIN
        if i > unitStart {
            if asciiRegionEquals(inner, unitStart, i, 'deg') { unit = HUE_DEG }
            else if asciiRegionEquals(inner, unitStart, i, 'grad') { unit = HUE_GRAD }
            else if asciiRegionEquals(inner, unitStart, i, 'rad') { unit = HUE_RAD }
            else if asciiRegionEquals(inner, unitStart, i, 'turn') { unit = HUE_TURN }
            else {
                c4Ok = false
                return
            }
        }
        c4Value.push(v)
        c4Percent.push(pct)
        c4Unit.push(unit)
    }
}

// One component as degrees, whatever angle unit it was written in.
float func c4Hue(i:int) {
    float v = c4Value[i]
    int unit = c4Unit[i]
    if unit == HUE_GRAD { return v * 0.9 }
    if unit == HUE_RAD { return v * 180.0 / CSS_PI }
    if unit == HUE_TURN { return v * 360.0 }
    return v
}

// One component, with a percentage read against the value the standard
// says 100% means for it: 100 for a Lab lightness, 125 for its a and b,
// 150 for an LCH chroma, 1 for an Oklab lightness or a color() channel,
// 0.4 for an Oklab a and b and an Oklch chroma.
float func c4Component(i:int, fullScale:float) {
    if c4Percent[i] { return c4Value[i] * fullScale / 100.0 }
    return c4Value[i]
}

// The alpha component, as 0-255. Absent means opaque; a percentage is
// out of 100 and a number out of 1.
int func c4AlphaAt(i:int) {
    if i >= c4Value.length { return 255 }
    float a = c4Percent[i] ? c4Value[i] / 100.0 : c4Value[i]
    if a < 0.0 { a = 0.0 }
    if a > 1.0 { a = 1.0 }
    return Math.round(a * 255.0)
}

// The sRGB transfer function, applied to a linear-light channel. The
// standard defines it for negatives by reflection, which matters
// because an out-of-gamut wide color arrives here with one.
float func srgbEncode(c:float) {
    float sign = c < 0.0 ? -1.0 : 1.0
    float v = Math.abs(c)
    if v <= 0.0031308 { return sign * 12.92 * v }
    return sign * (1.055 * Math.pow(v, 1.0 / 2.4) - 0.055)
}

int func linearToChannel(c:float) {
    return clampChannel(srgbEncode(c) * 255.0)
}

// XYZ with a D65 white point, through the sRGB primaries.
int func xyz65ToPacked(xv:float, yv:float, zv:float, alpha:int) {
    float lr = 3.2409699419045226 * xv - 1.5373831775700940 * yv - 0.4986107602930034 * zv
    float lg = -0.9692436362808796 * xv + 1.8759675015077202 * yv + 0.0415550574071756 * zv
    float lb = 0.0556300796969937 * xv - 0.2039769588889765 * yv + 1.0569715142428786 * zv
    return packColor(linearToChannel(lr), linearToChannel(lg), linearToChannel(lb), alpha)
}

// XYZ with a D50 white point: Bradford-adapted to D65 first.
int func xyz50ToPacked(xv:float, yv:float, zv:float, alpha:int) {
    float x2 = 0.9554734527042182 * xv - 0.0230985368742614 * yv + 0.0632593086610217 * zv
    float y2 = -0.0283697069632081 * xv + 1.0099954580058226 * yv + 0.0210413989669430 * zv
    float z2 = 0.0123140016883199 * xv - 0.0205076964334779 * yv + 1.3303659366080753 * zv
    return xyz65ToPacked(x2, y2, z2, alpha)
}

int func oklabToPacked(okL:float, okA:float, okB:float, alpha:int) {
    float lRoot = okL + 0.3963377774 * okA + 0.2158037573 * okB
    float mRoot = okL - 0.1055613458 * okA - 0.0638541728 * okB
    float sRoot = okL - 0.0894841775 * okA - 1.2914855480 * okB
    float lCone = lRoot * lRoot * lRoot
    float mCone = mRoot * mRoot * mRoot
    float sCone = sRoot * sRoot * sRoot
    float lr = 4.0767416621 * lCone - 3.3077115913 * mCone + 0.2309699292 * sCone
    float lg = -1.2684380046 * lCone + 2.6097574011 * mCone - 0.3413193965 * sCone
    float lb = -0.0041960863 * lCone - 0.7034186147 * mCone + 1.7076147010 * sCone
    return packColor(linearToChannel(lr), linearToChannel(lg), linearToChannel(lb), alpha)
}

// CIE Lab, whose white point is D50.
int func labToPacked(labL:float, labA:float, labB:float, alpha:int) {
    float epsilon = 216.0 / 24389.0
    float kappa = 24389.0 / 27.0
    float fy = (labL + 16.0) / 116.0
    float fx = fy + labA / 500.0
    float fz = fy - labB / 200.0
    float fx3 = fx * fx * fx
    float fz3 = fz * fz * fz
    float xr = fx3 > epsilon ? fx3 : (116.0 * fx - 16.0) / kappa
    float yr = labL > kappa * epsilon ? fy * fy * fy : labL / kappa
    float zr = fz3 > epsilon ? fz3 : (116.0 * fz - 16.0) / kappa
    float whiteX = 0.3457 / 0.3585
    float whiteZ = (1.0 - 0.3457 - 0.3585) / 0.3585
    return xyz50ToPacked(xr * whiteX, yr, zr * whiteZ, alpha)
}

// The polar forms are the rectangular ones with the hue as an angle.
int func lchToPacked(lchL:float, chroma:float, hueDeg:float, alpha:int) {
    float rad = hueDeg * CSS_PI / 180.0
    return labToPacked(lchL, chroma * Math.cos(rad), chroma * Math.sin(rad), alpha)
}

int func oklchToPacked(okL:float, chroma:float, hueDeg:float, alpha:int) {
    float rad = hueDeg * CSS_PI / 180.0
    return oklabToPacked(okL, chroma * Math.cos(rad), chroma * Math.sin(rad), alpha)
}

// hwb() is the hue at full saturation, mixed with white and black. The
// two amounts are read out of a hundred whether or not the '%' is
// written, which is what the standard says a bare number means here.
int func hwbToPacked(hueDeg:float, whiteness:float, blackness:float, alpha:int) {
    float w = clampFloat(whiteness, 0.0, 1.0)
    float k = clampFloat(blackness, 0.0, 1.0)
    if w + k >= 1.0 {
        int grey = clampChannel(w / (w + k) * 255.0)
        return packColor(grey, grey, grey, alpha)
    }
    float h = (hueDeg % 360.0) / 360.0
    if h < 0.0 { h = h + 1.0 }
    float span = 1.0 - w - k
    float r = hueToChannel(0.0, 1.0, h + 1.0 / 3.0) * span + w
    float g = hueToChannel(0.0, 1.0, h) * span + w
    float b = hueToChannel(0.0, 1.0, h - 1.0 / 3.0) * span + w
    return packColor(clampChannel(r * 255.0), clampChannel(g * 255.0), clampChannel(b * 255.0), alpha)
}

float func clampFloat(v:float, lo:float, hi:float) {
    if v < lo { return lo }
    if v > hi { return hi }
    return v
}

// The transfer functions of the color() spaces that have one.
float func a98Linear(c:float) {
    float sign = c < 0.0 ? -1.0 : 1.0
    return sign * Math.pow(Math.abs(c), 563.0 / 256.0)
}

float func srgbLinear(c:float) {
    float sign = c < 0.0 ? -1.0 : 1.0
    float v = Math.abs(c)
    if v <= 0.04045 { return sign * v / 12.92 }
    return sign * Math.pow((v + 0.055) / 1.055, 2.4)
}

float func prophotoLinear(c:float) {
    float sign = c < 0.0 ? -1.0 : 1.0
    float v = Math.abs(c)
    if v < 16.0 / 512.0 { return sign * v / 16.0 }
    return sign * Math.pow(v, 1.8)
}

float func rec2020Linear(c:float) {
    float alpha = 1.09929682680944
    float beta = 0.018053968510807
    float sign = c < 0.0 ? -1.0 : 1.0
    float v = Math.abs(c)
    if v < beta * 4.5 { return sign * v / 4.5 }
    return sign * Math.pow((v + alpha - 1.0) / alpha, 1.0 / 0.45)
}

// color(<space> c1 c2 c3 [/ a]) for the predefined spaces. A space this
// does not know answers COLOR_UNSET, so `color(--custom ...)` falls
// back rather than painting something invented.
int func colorFunctionToPacked(src:ascii, from:int, to:int, alpha:int) {
    float c1 = c4Component(0, 1.0)
    float c2 = c4Component(1, 1.0)
    float c3 = c4Component(2, 1.0)
    if asciiRegionEquals(src, from, to, 'srgb') {
        return packColor(clampChannel(c1 * 255.0), clampChannel(c2 * 255.0), clampChannel(c3 * 255.0), alpha)
    }
    if asciiRegionEquals(src, from, to, 'srgb-linear') {
        return packColor(linearToChannel(c1), linearToChannel(c2), linearToChannel(c3), alpha)
    }
    if asciiRegionEquals(src, from, to, 'display-p3') {
        float r = srgbLinear(c1)
        float g = srgbLinear(c2)
        float b = srgbLinear(c3)
        return xyz65ToPacked(
            0.4865709486482162 * r + 0.2656676931690931 * g + 0.1982172852343625 * b,
            0.2289745640697488 * r + 0.6917385218365064 * g + 0.0792869140937450 * b,
            0.0000000000000000 * r + 0.0451133818589026 * g + 1.0439443689009760 * b, alpha)
    }
    if asciiRegionEquals(src, from, to, 'a98-rgb') {
        float r = a98Linear(c1)
        float g = a98Linear(c2)
        float b = a98Linear(c3)
        return xyz65ToPacked(
            0.5766690429101305 * r + 0.1855582379065463 * g + 0.1882286462349947 * b,
            0.2973449752505361 * r + 0.6273635662554661 * g + 0.0752914584939979 * b,
            0.0270313613864123 * r + 0.0706888525358272 * g + 0.9913375368376388 * b, alpha)
    }
    if asciiRegionEquals(src, from, to, 'prophoto-rgb') {
        float r = prophotoLinear(c1)
        float g = prophotoLinear(c2)
        float b = prophotoLinear(c3)
        return xyz50ToPacked(
            0.7977604896723027 * r + 0.1351858371757403 * g + 0.0313493495815248 * b,
            0.2880711282292934 * r + 0.7118432178101014 * g + 0.0000856539606053 * b,
            0.0000000000000000 * r + 0.0000000000000000 * g + 0.8251046025104601 * b, alpha)
    }
    if asciiRegionEquals(src, from, to, 'rec2020') {
        float r = rec2020Linear(c1)
        float g = rec2020Linear(c2)
        float b = rec2020Linear(c3)
        return xyz65ToPacked(
            0.6369580483012914 * r + 0.1446169035862083 * g + 0.1688809751641721 * b,
            0.2627002120112671 * r + 0.6779980715188708 * g + 0.0593017164698620 * b,
            0.0000000000000000 * r + 0.0280726930490874 * g + 1.0609850577107910 * b, alpha)
    }
    if asciiRegionEquals(src, from, to, 'xyz') || asciiRegionEquals(src, from, to, 'xyz-d65') { return xyz65ToPacked(c1, c2, c3, alpha) }
    if asciiRegionEquals(src, from, to, 'xyz-d50') { return xyz50ToPacked(c1, c2, c3, alpha) }
    return COLOR_UNSET
}

// Dispatches one of the wider-gamut color functions. `fn` is already
// lowercased and `inner` is what stood between its parentheses. Neither
// is cut up: color()'s space name is found as a pair of offsets into
// `inner` and compared where it lies, because `inner` is itself a slice
// and slicing a slice aliases a buffer it does not own (FINDINGS.md,
// "slicing an ascii that came from a slice").
int func parseWideColor(fn:ascii, inner:ascii) {
    if fn == 'color' {
        int n = inner.length
        int spaceStart = 0
        while spaceStart < n && isSpaceCode(inner.charCodeAt(spaceStart)) { spaceStart++ }
        int spaceEnd = spaceStart
        while spaceEnd < n && !isSpaceCode(inner.charCodeAt(spaceEnd)) { spaceEnd++ }
        if spaceEnd <= spaceStart || spaceEnd >= n { return COLOR_UNSET }
        scanColorArgs(inner, spaceEnd)
        if !c4Ok || c4Value.length < 3 { return COLOR_UNSET }
        return colorFunctionToPacked(inner, spaceStart, spaceEnd, c4AlphaAt(3))
    }
    scanColorArgs(inner, 0)
    if !c4Ok || c4Value.length < 3 { return COLOR_UNSET }
    int alpha = c4AlphaAt(3)
    if fn == 'hwb' {
        return hwbToPacked(c4Hue(0), c4Value[1] / 100.0, c4Value[2] / 100.0, alpha)
    }
    if fn == 'lab' {
        return labToPacked(c4Component(0, 100.0), c4Component(1, 125.0), c4Component(2, 125.0), alpha)
    }
    if fn == 'lch' {
        return lchToPacked(c4Component(0, 100.0), c4Component(1, 150.0), c4Hue(2), alpha)
    }
    if fn == 'oklab' {
        return oklabToPacked(c4Component(0, 1.0), c4Component(1, 0.4), c4Component(2, 0.4), alpha)
    }
    if fn == 'oklch' {
        return oklchToPacked(c4Component(0, 1.0), c4Component(1, 0.4), c4Hue(2), alpha)
    }
    return COLOR_UNSET
}

// ---------------------------------------------------------------------
// CSS Color 5's `color-mix()`.
//
// Two colours are mixed on the components of the space they are mixed
// in, which is why the same pair gives a different colour in each: sRGB
// mixes gamma-encoded channels, srgb-linear and XYZ mix light, Lab and
// Oklab mix perceptual axes, and the polar spaces mix an angle. Every
// one of those needs the conversion the wider colour spaces above do
// not: sRGB *into* the space rather than out of it.
//
// Mixing is done premultiplied, so a transparent colour contributes its
// alpha and nothing else (CSS Color 4 sec. 12.3). A hue is not
// premultiplied, being an angle rather than a quantity.

const int MIXSPACE_SRGB = 0
const int MIXSPACE_SRGB_LINEAR = 1
const int MIXSPACE_XYZ65 = 2
const int MIXSPACE_XYZ50 = 3
const int MIXSPACE_LAB = 4
const int MIXSPACE_OKLAB = 5
const int MIXSPACE_HSL = 6
const int MIXSPACE_HWB = 7
const int MIXSPACE_LCH = 8
const int MIXSPACE_OKLCH = 9

// How a hue travels from one angle to the other.
const int HUEWAY_SHORTER = 0
const int HUEWAY_LONGER = 1
const int HUEWAY_INCREASING = 2
const int HUEWAY_DECREASING = 3

// Whether the space's first component is an angle. Every polar space
// here keeps the hue first, as its own syntax writes it.
bool func mixSpaceIsPolar(space:int) {
    return space == MIXSPACE_HSL || space == MIXSPACE_HWB
        || space == MIXSPACE_LCH || space == MIXSPACE_OKLCH
}

int func mixSpaceNamed(t:ascii) {
    if t == 'srgb' { return MIXSPACE_SRGB }
    if t == 'srgb-linear' { return MIXSPACE_SRGB_LINEAR }
    if t == 'xyz' || t == 'xyz-d65' { return MIXSPACE_XYZ65 }
    if t == 'xyz-d50' { return MIXSPACE_XYZ50 }
    if t == 'lab' { return MIXSPACE_LAB }
    if t == 'oklab' { return MIXSPACE_OKLAB }
    if t == 'hsl' { return MIXSPACE_HSL }
    if t == 'hwb' { return MIXSPACE_HWB }
    if t == 'lch' { return MIXSPACE_LCH }
    if t == 'oklch' { return MIXSPACE_OKLCH }
    return -1
}

// A cube root that keeps the sign, which Math has no call for.
float func cubeRoot(v:float) {
    if v < 0.0 { return 0.0 - Math.pow(0.0 - v, 1.0 / 3.0) }
    return Math.pow(v, 1.0 / 3.0)
}

// One colour in one space: three components and an alpha out of one.
// Globals, because a function answers with one value (FINDINGS.md).
float mixA1 = 0.0
float mixA2 = 0.0
float mixA3 = 0.0
float mixAlpha = 1.0

// The inverse of srgbEncode: a gamma-encoded channel back to light.
float func srgbDecode(c:float) {
    float sign = c < 0.0 ? -1.0 : 1.0
    float v = Math.abs(c)
    if v <= 0.04045 { return sign * v / 12.92 }
    return sign * Math.pow((v + 0.055) / 1.055, 2.4)
}

// Linear-light sRGB to XYZ with a D65 white point.
float xyzX = 0.0
float xyzY = 0.0
float xyzZ = 0.0

void func linearToXyz65(r:float, g:float, b:float) {
    xyzX = 0.41239079926595934 * r + 0.35758433938387800 * g + 0.18048078840183430 * b
    xyzY = 0.21263900587151027 * r + 0.71516867876775600 * g + 0.07219231536073371 * b
    xyzZ = 0.01933081871559182 * r + 0.11919477979462598 * g + 0.95053215224966070 * b
}

// D65 to D50, the Bradford adaptation the other way round.
void func xyz65ToXyz50(x:float, y:float, z:float) {
    xyzX = 1.04792982084054880 * x + 0.02294679334101909 * y - 0.05019222954313557 * z
    xyzY = 0.02962781568815934 * x + 0.99043448457324900 * y - 0.01707382502938514 * z
    xyzZ = -0.00924305815259118 * x + 0.01505514489657790 * y + 0.75187428995800080 * z
}

// Reads a packed colour into the space's own components.
void func colorIntoSpace(c:int, space:int) {
    mixAlpha = colorAlpha(c).toFloat() / 255.0
    float r = colorRed(c).toFloat() / 255.0
    float g = colorGreen(c).toFloat() / 255.0
    float b = colorBlue(c).toFloat() / 255.0
    if space == MIXSPACE_SRGB {
        mixA1 = r
        mixA2 = g
        mixA3 = b
        return
    }
    if space == MIXSPACE_HSL || space == MIXSPACE_HWB {
        srgbToHueSpace(r, g, b, space)
        return
    }
    float lr = srgbDecode(r)
    float lg = srgbDecode(g)
    float lb = srgbDecode(b)
    if space == MIXSPACE_SRGB_LINEAR {
        mixA1 = lr
        mixA2 = lg
        mixA3 = lb
        return
    }
    if space == MIXSPACE_OKLAB || space == MIXSPACE_OKLCH {
        srgbToOklab(lr, lg, lb)
        if space == MIXSPACE_OKLCH { rectToPolar() }
        return
    }
    linearToXyz65(lr, lg, lb)
    if space == MIXSPACE_XYZ65 {
        mixA1 = xyzX
        mixA2 = xyzY
        mixA3 = xyzZ
        return
    }
    xyz65ToXyz50(xyzX, xyzY, xyzZ)
    if space == MIXSPACE_XYZ50 {
        mixA1 = xyzX
        mixA2 = xyzY
        mixA3 = xyzZ
        return
    }
    xyz50ToLab(xyzX, xyzY, xyzZ)
    if space == MIXSPACE_LCH { rectToPolar() }
}

// Lab and Oklab hold lightness first and a rectangular pair after it;
// their polar forms keep the lightness and turn the pair into a chroma
// and an angle. The angle goes first here, because that is where every
// polar space in this engine keeps it.
void func rectToPolar() {
    float l = mixA1
    float a = mixA2
    float b = mixA3
    float chroma = Math.sqrt(a * a + b * b)
    float hue = Math.atan2(b, a) * 180.0 / CSS_PI
    if hue < 0.0 { hue = hue + 360.0 }
    mixA1 = hue
    mixA2 = chroma
    mixA3 = l
}

void func polarToRect() {
    float hue = mixA1 * CSS_PI / 180.0
    float chroma = mixA2
    float l = mixA3
    mixA1 = l
    mixA2 = chroma * Math.cos(hue)
    mixA3 = chroma * Math.sin(hue)
}

void func srgbToOklab(lr:float, lg:float, lb:float) {
    float l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
    float m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
    float s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
    float lr3 = cubeRoot(l)
    float mr3 = cubeRoot(m)
    float sr3 = cubeRoot(s)
    mixA1 = 0.2104542553 * lr3 + 0.7936177850 * mr3 - 0.0040720468 * sr3
    mixA2 = 1.9779984951 * lr3 - 2.4285922050 * mr3 + 0.4505937099 * sr3
    mixA3 = 0.0259040371 * lr3 + 0.7827717662 * mr3 - 0.8086757660 * sr3
}

void func xyz50ToLab(x:float, y:float, z:float) {
    float whiteX = 0.3457 / 0.3585
    float whiteZ = (1.0 - 0.3457 - 0.3585) / 0.3585
    float fx = labF(x / whiteX)
    float fy = labF(y)
    float fz = labF(z / whiteZ)
    mixA1 = 116.0 * fy - 16.0
    mixA2 = 500.0 * (fx - fy)
    mixA3 = 200.0 * (fy - fz)
}

float func labF(t:float) {
    float epsilon = 216.0 / 24389.0
    float kappa = 24389.0 / 27.0
    if t > epsilon { return cubeRoot(t) }
    return (kappa * t + 16.0) / 116.0
}

// sRGB to HSL or HWB, both of which are read off the gamma-encoded
// channels rather than off light.
void func srgbToHueSpace(r:float, g:float, b:float, space:int) {
    float mx = r > g ? (r > b ? r : b) : (g > b ? g : b)
    float mn = r < g ? (r < b ? r : b) : (g < b ? g : b)
    float hue = 0.0
    float d = mx - mn
    if d > 0.0 {
        if mx == r { hue = (g - b) / d }
        else if mx == g { hue = (b - r) / d + 2.0 }
        else { hue = (r - g) / d + 4.0 }
        hue = hue * 60.0
        if hue < 0.0 { hue = hue + 360.0 }
    }
    mixA1 = hue
    if space == MIXSPACE_HWB {
        mixA2 = mn
        mixA3 = 1.0 - mx
        return
    }
    float l = (mx + mn) / 2.0
    float sat = 0.0
    if d > 0.0 && l > 0.0 && l < 1.0 { sat = d / (1.0 - Math.abs(2.0 * l - 1.0)) }
    mixA2 = sat
    mixA3 = l
}

// The components back to a packed colour.
int func colorFromSpace(space:int, alpha:int) {
    if space == MIXSPACE_SRGB {
        return packColor(clampChannel(mixA1 * 255.0), clampChannel(mixA2 * 255.0),
                         clampChannel(mixA3 * 255.0), alpha)
    }
    if space == MIXSPACE_SRGB_LINEAR {
        return packColor(linearToChannel(mixA1), linearToChannel(mixA2),
                         linearToChannel(mixA3), alpha)
    }
    if space == MIXSPACE_HSL {
        return hslToPacked(mixA1, mixA2, mixA3, alpha)
    }
    if space == MIXSPACE_HWB {
        return hwbToPacked(mixA1, mixA2, mixA3, alpha)
    }
    if space == MIXSPACE_LCH {
        polarToRect()
        return labToPacked(mixA1, mixA2, mixA3, alpha)
    }
    if space == MIXSPACE_OKLCH {
        polarToRect()
        return oklabToPacked(mixA1, mixA2, mixA3, alpha)
    }
    if space == MIXSPACE_LAB { return labToPacked(mixA1, mixA2, mixA3, alpha) }
    if space == MIXSPACE_OKLAB { return oklabToPacked(mixA1, mixA2, mixA3, alpha) }
    if space == MIXSPACE_XYZ50 { return xyz50ToPacked(mixA1, mixA2, mixA3, alpha) }
    return xyz65ToPacked(mixA1, mixA2, mixA3, alpha)
}

// The second hue moved so that interpolating towards it travels the way
// the method asks (CSS Color 4 sec. 12.4).
float func hueEndpoint(h1:float, h2In:float, way:int) {
    float h2 = h2In
    float d = h2 - h1
    if way == HUEWAY_SHORTER {
        if d > 180.0 { h2 = h2 - 360.0 }
        else if d < -180.0 { h2 = h2 + 360.0 }
        return h2
    }
    if way == HUEWAY_LONGER {
        if d > -180.0 && d < 180.0 {
            h2 = d > 0.0 ? h2 - 360.0 : h2 + 360.0
        }
        // a difference of exactly zero has no longer way round
        return h2
    }
    if way == HUEWAY_INCREASING {
        if d < 0.0 { h2 = h2 + 360.0 }
        return h2
    }
    if d > 0.0 { h2 = h2 - 360.0 }
    return h2
}

// Mixes two colours, `w1` of the first and one less of it of the
// second, premultiplied.
int func mixColors(c1:int, c2:int, space:int, way:int, w1:float, alphaScale:float) {
    float w2 = 1.0 - w1
    colorIntoSpace(c1, space)
    float p1 = mixA1
    float q1 = mixA2
    float r1 = mixA3
    float alpha1 = mixAlpha
    colorIntoSpace(c2, space)
    float p2 = mixA1
    float q2 = mixA2
    float r2 = mixA3
    float alpha2 = mixAlpha
    float alpha = alpha1 * w1 + alpha2 * w2
    bool polar = mixSpaceIsPolar(space)
    if polar { p2 = hueEndpoint(p1, p2, way) }
    // Premultiplication is by alpha, and a hue is an angle rather than
    // a quantity, so it is interpolated as it stands.
    float m1 = polar ? p1 * w1 + p2 * w2
                     : (p1 * alpha1 * w1 + p2 * alpha2 * w2)
    float m2 = q1 * alpha1 * w1 + q2 * alpha2 * w2
    float m3 = r1 * alpha1 * w1 + r2 * alpha2 * w2
    if alpha > 0.0 {
        if !polar { m1 = m1 / alpha }
        m2 = m2 / alpha
        m3 = m3 / alpha
    }
    mixA1 = m1
    mixA2 = m2
    mixA3 = m3
    float outAlpha = alpha * alphaScale
    if outAlpha < 0.0 { outAlpha = 0.0 }
    if outAlpha > 1.0 { outAlpha = 1.0 }
    return colorFromSpace(space, Math.round(outAlpha * 255.0))
}

// Splits on commas that are not inside parentheses, which `rgb(1, 2, 3)`
// as an argument makes necessary.
arr[ascii] func splitTopCommas(v:ascii) {
    arr[ascii] out = []
    int depth = 0
    int start = 0
    for int i = 0, i < v.length, i++ {
        int c = v.charCodeAt(i)
        if c == CH_LPAREN { depth++ }
        else if c == CH_RPAREN { depth-- }
        else if c == CH_COMMA && depth == 0 {
            out.push(asciiTrim(v.slice(start, i)))
            start = i + 1
        }
    }
    out.push(asciiTrim(v.slice(start, v.length)))
    return out
}

// One `<color> <percentage>?` argument. The percentage comes back in a
// global, negative when it was not written.
float mixArgPercent = -1.0

int func parseMixArgument(arg:ascii, currentColor:int) {
    mixArgPercent = -1.0
    // The percentage is the last token, and a colour function may hold
    // spaces of its own, so the split is from the right.
    int end = arg.length
    if end > 0 && arg.charCodeAt(end - 1) == CH_PERCENT {
        int at = end - 1
        while at > 0 && !isSpaceCode(arg.charCodeAt(at - 1)) { at-- }
        parseNumberAt(arg, at)
        if numOk && numEnd == end - 1 {
            mixArgPercent = numValue
            return parseCssColor(asciiTrim(arg.slice(0, at)), currentColor)
        }
    }
    return parseCssColor(arg, currentColor)
}

// `color-mix( in <space> <hue-method>? , <color> <pct>? , <color> <pct>? )`
int func parseColorMix(inner:ascii, currentColor:int) {
    arr[ascii] args = splitTopCommas(inner)
    if args.length != 3 { return COLOR_UNSET }
    // The first argument is `in <space>` and, for a polar space, how the
    // hue travels.
    arr[ascii] head = asciiSplitSpace(args[0])
    if head.length < 2 || head[0] != 'in' { return COLOR_UNSET }
    int space = mixSpaceNamed(head[1])
    if space < 0 { return COLOR_UNSET }
    int way = HUEWAY_SHORTER
    if head.length >= 4 && head[3] == 'hue' {
        if head[2] == 'shorter' { way = HUEWAY_SHORTER }
        else if head[2] == 'longer' { way = HUEWAY_LONGER }
        else if head[2] == 'increasing' { way = HUEWAY_INCREASING }
        else if head[2] == 'decreasing' { way = HUEWAY_DECREASING }
        else { return COLOR_UNSET }
    }
    int c1 = parseMixArgument(args[1], currentColor)
    float p1 = mixArgPercent
    int c2 = parseMixArgument(args[2], currentColor)
    float p2 = mixArgPercent
    if c1 == COLOR_UNSET || c2 == COLOR_UNSET { return COLOR_UNSET }
    // An absent percentage is whatever the other one leaves.
    if p1 < 0.0 && p2 < 0.0 {
        p1 = 50.0
        p2 = 50.0
    } else if p1 < 0.0 {
        p1 = 100.0 - p2
    } else if p2 < 0.0 {
        p2 = 100.0 - p1
    }
    float sum = p1 + p2
    if sum <= 0.0 { return COLOR_UNSET }
    // Percentages that do not add to a hundred are normalised, and the
    // result's alpha carries what they came to.
    float scale = sum < 100.0 ? sum / 100.0 : 1.0
    return mixColors(c1, c2, space, way, p1 / sum, scale)
}
