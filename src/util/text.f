// String helpers the renderer needs and Festina's `text` does not
// provide. `text` is an immutable UTF-8 value whose only per-character
// operations are s[i] and charCodeAt(i), each an O(n) walk, and it has
// no substring, indexOf, startsWith or case conversion at all
// (specification.md 16.3). Everything that scans characters therefore
// runs on `ascii`, whose indexing is O(1) and which has slice().

// ARCHTELOS_TIMING=1 in the environment makes the pipeline log how
// long each phase took, and layout its own hot spots.
bool archtelosTiming = environment.ARCHTELOS_TIMING != null
// Turns the preload scanner off, so the benchmark can measure the same
// page with and without it rather than quoting one number.
bool archtelosNoPreload = environment.ARCHTELOS_NO_PRELOAD != null

const int CH_TAB = 9
const int CH_LF = 10
const int CH_FF = 12
const int CH_CR = 13
const int CH_SPACE = 32
const int CH_BANG = 33
const int CH_QUOTE = 34
const int CH_HASH = 35
const int CH_PERCENT = 37
const int CH_AMP = 38
const int CH_APOS = 39
const int CH_LPAREN = 40
const int CH_RPAREN = 41
const int CH_STAR = 42
const int CH_PLUS = 43
const int CH_COMMA = 44
const int CH_MINUS = 45
const int CH_N_LOWER = 110
const int CH_DOT = 46
const int CH_SLASH = 47
const int CH_0 = 48
const int CH_9 = 57
const int CH_COLON = 58
const int CH_SEMI = 59
const int CH_LT = 60
const int CH_EQ = 61
const int CH_PIPE = 124
const int CH_GT = 62
const int CH_QUESTION = 63
const int CH_AT = 64
const int CH_LBRACKET = 91
const int CH_BACKSLASH = 92
const int CH_RBRACKET = 93
const int CH_UNDERSCORE = 95
const int CH_LBRACE = 123
const int CH_RBRACE = 125
const int CH_TILDE = 126

bool func isSpaceCode(c:int) {
    return c == CH_SPACE || c == CH_TAB || c == CH_LF || c == CH_CR || c == CH_FF
}

bool func isDigitCode(c:int) {
    return c >= CH_0 && c <= CH_9
}

bool func isAlphaCode(c:int) {
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
}

bool func isAlnumCode(c:int) {
    return isAlphaCode(c) || isDigitCode(c)
}

// A CSS identifier character: letters, digits, '-' and '_'. Bytes at
// or above 128 never occur here because the input pre-pass (see
// html/decode.f) has already rewritten them as numeric references.
bool func isNameCode(c:int) {
    return isAlnumCode(c) || c == CH_MINUS || c == CH_UNDERSCORE
}

bool func isHexCode(c:int) {
    return isDigitCode(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
}

int func hexValue(c:int) {
    if isDigitCode(c) { return c - CH_0 }
    if c >= 65 && c <= 70 { return c - 55 }
    if c >= 97 && c <= 102 { return c - 87 }
    return 0
}

int func lowerCode(c:int) {
    if c >= 65 && c <= 90 { return c + 32 }
    return c
}

// Lowercases the ASCII letters of `s`. A value with no uppercase
// letter is returned as-is (an ascii is reference counted, so that
// costs nothing); otherwise the result is rebuilt one character at a
// time. int.toChar() is the only way to turn a code back into a
// character, and it yields a `text`, so the rebuild goes through a
// text accumulator and converts at the end.
ascii func asciiLower(s:ascii) {
    if s == null { return s }
    int n = s.length
    bool hasUpper = false
    for int i = 0, i < n, i++ {
        int c = s.charCodeAt(i)
        if c >= 65 && c <= 90 {
            hasUpper = true
            break
        }
    }
    if !hasUpper { return s }
    text out = ''
    for int i = 0, i < n, i++ {
        int c = lowerCode(s.charCodeAt(i))
        text ch = c.toChar()
        out = out + ch
    }
    return out.toAscii()
}

text func textLower(t:text) {
    if t == null { return t }
    ascii a = t.toAscii()
    if a == null { return t }
    return asciiLower(a).toText()
}

// First index of `needle` in `s` at or after `from`, or -1.
int func asciiIndexOf(s:ascii, needle:ascii, from:int) {
    int n = s.length
    int m = needle.length
    if m == 0 { return from <= n ? from : -1 }
    int first = needle.charCodeAt(0)
    for int i = from, i + m <= n, i++ {
        if s.charCodeAt(i) == first {
            bool all = true
            for int j = 1, j < m, j++ {
                if s.charCodeAt(i + j) != needle.charCodeAt(j) {
                    all = false
                    break
                }
            }
            if all { return i }
        }
    }
    return -1
}

// Case-insensitive variant: `needle` must already be lowercase.
int func asciiIndexOfLower(s:ascii, needle:ascii, from:int) {
    int n = s.length
    int m = needle.length
    if m == 0 { return from <= n ? from : -1 }
    int first = needle.charCodeAt(0)
    for int i = from, i + m <= n, i++ {
        if lowerCode(s.charCodeAt(i)) == first {
            bool all = true
            for int j = 1, j < m, j++ {
                if lowerCode(s.charCodeAt(i + j)) != needle.charCodeAt(j) {
                    all = false
                    break
                }
            }
            if all { return i }
        }
    }
    return -1
}

bool func asciiStartsWith(s:ascii, prefix:ascii, at:int) {
    int m = prefix.length
    if at < 0 || at + m > s.length { return false }
    for int j = 0, j < m, j++ {
        if s.charCodeAt(at + j) != prefix.charCodeAt(j) { return false }
    }
    return true
}

bool func asciiStartsWithLower(s:ascii, prefix:ascii, at:int) {
    int m = prefix.length
    if at < 0 || at + m > s.length { return false }
    for int j = 0, j < m, j++ {
        if lowerCode(s.charCodeAt(at + j)) != prefix.charCodeAt(j) { return false }
    }
    return true
}

bool func asciiEndsWith(s:ascii, suffix:ascii) {
    int m = suffix.length
    int n = s.length
    if m > n { return false }
    return asciiStartsWith(s, suffix, n - m)
}

ascii func asciiTrim(s:ascii) {
    if s == null { return s }
    int a = 0
    int b = s.length
    while a < b && isSpaceCode(s.charCodeAt(a)) { a++ }
    while b > a && isSpaceCode(s.charCodeAt(b - 1)) { b-- }
    if a == 0 && b == s.length { return s }
    return s.slice(a, b)
}

bool func asciiIsBlank(s:ascii) {
    if s == null { return true }
    for int i = 0, i < s.length, i++ {
        if !isSpaceCode(s.charCodeAt(i)) { return false }
    }
    return true
}

// Splits on a single separator character, trimming each piece and
// dropping empty ones -- the shape CSS value lists and class
// attributes take. (text.split() exists but answers arr[text], and
// every piece would then need converting back to ascii to scan.)
arr[ascii] func asciiSplitChar(s:ascii, sep:int) {
    arr[ascii] out = []
    int start = 0
    int n = s.length
    for int i = 0, i <= n, i++ {
        if i == n || s.charCodeAt(i) == sep {
            ascii piece = asciiTrim(s.slice(start, i))
            if piece.length > 0 { out.push(piece) }
            start = i + 1
        }
    }
    return out
}

// Splits on runs of whitespace.
// Whether every character is a full stop, which is how a grid template
// writes a cell belonging to no area: `.` and `...` mean the same.
bool func asciiIsAllDots(s:ascii) {
    if s == null || s.length == 0 { return false }
    for int i = 0, i < s.length, i++ {
        if s.charCodeAt(i) != CH_DOT { return false }
    }
    return true
}

arr[ascii] func asciiSplitSpace(s:ascii) {
    arr[ascii] out = []
    int n = s.length
    int i = 0
    while i < n {
        while i < n && isSpaceCode(s.charCodeAt(i)) { i++ }
        int start = i
        while i < n && !isSpaceCode(s.charCodeAt(i)) { i++ }
        if i > start { out.push(s.slice(start, i)) }
    }
    return out
}

// ---- number parsing ----------------------------------------------
// `text.toInt()` exists but there is no toFloat(); CSS lengths need
// both a fractional value and to know where the number ended so the
// unit can be read. Festina has no tuples and no out-parameters, so
// the three results travel through globals that the caller reads
// straight after the call.
float numValue = 0.0
int numEnd = 0
bool numOk = false

void func parseNumberAt(s:ascii, from:int) {
    int n = s.length
    int i = from
    float sign = 1.0
    numOk = false
    numValue = 0.0
    numEnd = from
    if i < n && s.charCodeAt(i) == CH_PLUS { i++ }
    else if i < n && s.charCodeAt(i) == CH_MINUS {
        sign = -1.0
        i++
    }
    float v = 0.0
    bool digits = false
    while i < n && isDigitCode(s.charCodeAt(i)) {
        v = v * 10.0 + (s.charCodeAt(i) - CH_0).toFloat()
        digits = true
        i++
    }
    if i < n && s.charCodeAt(i) == CH_DOT {
        int j = i + 1
        float scale = 0.1
        bool frac = false
        while j < n && isDigitCode(s.charCodeAt(j)) {
            v = v + (s.charCodeAt(j) - CH_0).toFloat() * scale
            scale = scale / 10.0
            frac = true
            j++
        }
        if frac {
            i = j
            digits = true
        }
    }
    if !digits { return }
    numOk = true
    numValue = sign * v
    numEnd = i
}

float func parseFloatAscii(s:ascii) {
    parseNumberAt(asciiTrim(s), 0)
    return numOk ? numValue : 0.0
}

// Rounds a float to the nearest int; Math.round refuses a null (NaN)
// float, which the arithmetic above never produces, but callers pass
// computed values that might be huge -- clamp so the layout never
// receives a null int.
int func roundPx(v:float) {
    if v > 100000000.0 { return 100000000 }
    if v < -100000000.0 { return -100000000 }
    return Math.round(v)
}

// A fresh copy of an ascii. Needed wherever an ascii local would
// otherwise ALIAS another binding -- another local, an array element,
// a struct field or a parameter -- because the compiler releases such
// a local at scope exit without ever having retained it, which frees
// the original binding's buffer out from under it (FINDINGS.md,
// "ascii aliasing"). A slice is a fresh value the local really owns.
ascii func dup(s:ascii) {
    if s == null { return null }
    return s.slice(0, s.length)
}

int func maxInt(a:int, b:int) { return a > b ? a : b }
int func minInt(a:int, b:int) { return a < b ? a : b }
int func clampInt(v:int, lo:int, hi:int) {
    if v < lo { return lo }
    if v > hi { return hi }
    return v
}

// Repeats `piece` n times -- there is no text.repeat().
text func repeatText(piece:text, n:int) {
    text out = ''
    for int i = 0, i < n, i++ { out = out + piece }
    return out
}

// The text form of an ascii, or '' for null: a null text renders as
// the word "null" in a template, which is never what a renderer wants.
text func asciiToTextOrEmpty(s:ascii) {
    if s == null { return '' }
    return s.toText()
}
