// The bidirectional algorithm (Unicode Annex #9).
//
// A right-to-left script is stored in the order it is read and drawn in
// the order it appears, and those are not the same order. This turns
// the first into the second: it takes a line's characters in logical
// order and returns them in visual order, left to right, which is the
// order a renderer with no bidi support of its own can draw.
//
// What is implemented is the implicit algorithm -- the W, N, I and L2
// rules -- with the paragraph level taken from `direction` rather than
// detected. The explicit embedding and isolate codes (the X rules) are
// not: they are the controls a document uses to override the implicit
// result, and a document that uses none of them gets the same answer
// either way. css-2026.md records that.
//
// The character classes come from ranges rather than from the Unicode
// database, which is a table this repository would have to vendor. The
// ranges cover the scripts the algorithm exists for -- Hebrew, Arabic,
// Syriac, Thaana, N'Ko -- and everything outside them is left-to-right
// or neutral, which is what the database says for the scripts a browser
// meets in practice.

// The code points are decimal because the language has no
// hexadecimal literal (FINDINGS.md, finding 13), which is why a
// range that reads as 0590..05FF in the standard is written 1424
// to 1535 here.
const int BIDI_L = 0        // strongly left-to-right
const int BIDI_R = 1        // strongly right-to-left
const int BIDI_AL = 2       // an Arabic letter, which is right-to-left
const int BIDI_EN = 3       // a European number
const int BIDI_AN = 4       // an Arabic number
const int BIDI_ES = 5       // a European number separator: + -
const int BIDI_ET = 6       // a European number terminator: $ % degree
const int BIDI_CS = 7       // a common separator: , . : and friends
const int BIDI_WS = 8       // whitespace
const int BIDI_ON = 9       // any other neutral
const int BIDI_B = 10       // a paragraph separator

bool func bidiIsNeutral(t:int) {
    return t == BIDI_WS || t == BIDI_ON || t == BIDI_B
        || t == BIDI_ES || t == BIDI_ET || t == BIDI_CS
}

// A strong type as a direction: numbers count as right-to-left when the
// neutrals around them are resolved (rule N1).
int func bidiDirOf(t:int) {
    if t == BIDI_L { return BIDI_L }
    if t == BIDI_R || t == BIDI_AL || t == BIDI_EN || t == BIDI_AN { return BIDI_R }
    return -1
}

int func bidiClass(cp:int) {
    if cp >= 48 && cp <= 57 { return BIDI_EN }
    // Hebrew, and its presentation forms
    if cp >= 1424 && cp <= 1535 { return BIDI_R }
    if cp >= 64285 && cp <= 64335 { return BIDI_R }
    // Arabic-Indic and extended Arabic-Indic digits
    if cp >= 1632 && cp <= 1641 { return BIDI_AN }
    if cp >= 1776 && cp <= 1785 { return BIDI_AN }
    // Arabic, and its presentation forms
    if cp >= 1536 && cp <= 1791 { return BIDI_AL }
    if cp >= 1872 && cp <= 1919 { return BIDI_AL }
    if cp >= 2208 && cp <= 2303 { return BIDI_AL }
    if cp >= 64336 && cp <= 65023 { return BIDI_AL }
    if cp >= 65136 && cp <= 65279 { return BIDI_AL }
    // Syriac, Thaana, N'Ko and Samaritan
    if cp >= 1792 && cp <= 1871 { return BIDI_R }
    if cp >= 1920 && cp <= 1983 { return BIDI_R }
    if cp >= 1984 && cp <= 2207 { return BIDI_R }
    if cp == 10 || cp == 13 { return BIDI_B }
    if cp == 9 || cp == 11 || cp == 32 { return BIDI_WS }
    if cp == 43 || cp == 45 { return BIDI_ES }
    if cp == 35 || cp == 36 || cp == 37 { return BIDI_ET }
    if cp == 163 || cp == 165 || cp == 176 { return BIDI_ET }
    if cp == 44 || cp == 46 || cp == 47 || cp == 58 { return BIDI_CS }
    // Letters and everything above the Latin ranges that is not named
    // above -- Greek, Cyrillic, the Indic scripts, CJK -- are
    // left-to-right; ASCII punctuation is neutral.
    if cp >= 65 && cp <= 90 { return BIDI_L }
    if cp >= 97 && cp <= 122 { return BIDI_L }
    if cp < 128 { return BIDI_ON }
    if cp >= 8192 && cp <= 8303 { return BIDI_ON }
    return BIDI_L
}

// Whether a string holds anything that could reorder. A line of Latin
// text never does, so the whole pass is skipped for it -- which is what
// keeps the algorithm off the pages that do not need it.
bool func bidiNeedsReorder(t:text) {
    for int i = 0, i < t.length, i++ {
        int c = bidiClass(t.charCodeAt(i))
        if c == BIDI_R || c == BIDI_AL || c == BIDI_AN { return true }
    }
    return false
}

// The embedding level of every character, given the paragraph's own.
arr[int] func bidiLevels(t:text, paragraphLevel:int) {
    int base = paragraphLevel % 2
    arr[int] types = []
    for int i = 0, i < t.length, i++ { types.push(bidiClass(t.charCodeAt(i))) }
    int n = types.length

    // W2: a European number takes its direction from the last strong
    // type before it, becoming an Arabic number after an Arabic letter.
    int lastStrong = base == 1 ? BIDI_R : BIDI_L
    for int i = 0, i < n, i++ {
        int ty = types[i]
        if ty == BIDI_L || ty == BIDI_R || ty == BIDI_AL { lastStrong = ty }
        else if ty == BIDI_EN && lastStrong == BIDI_AL { types[i] = BIDI_AN }
    }
    // W3: an Arabic letter is right-to-left from here on.
    for int i = 0, i < n, i++ { if types[i] == BIDI_AL { types[i] = BIDI_R } }
    // W4: a single separator between two numbers of the same kind joins
    // them.
    for int i = 1, i < n - 1, i++ {
        int ty = types[i]
        if ty == BIDI_ES && types[i-1] == BIDI_EN && types[i+1] == BIDI_EN { types[i] = BIDI_EN }
        else if ty == BIDI_CS && types[i-1] == BIDI_EN && types[i+1] == BIDI_EN { types[i] = BIDI_EN }
        else if ty == BIDI_CS && types[i-1] == BIDI_AN && types[i+1] == BIDI_AN { types[i] = BIDI_AN }
    }
    // W5: a run of terminators beside a European number joins it.
    for int i = 0, i < n, i++ {
        if types[i] != BIDI_ET { continue }
        int runEnd = i
        while runEnd < n && types[runEnd] == BIDI_ET { runEnd++ }
        bool before = i > 0 && types[i-1] == BIDI_EN
        bool after = runEnd < n && types[runEnd] == BIDI_EN
        if before || after {
            for int k = i, k < runEnd, k++ { types[k] = BIDI_EN }
        }
        i = runEnd - 1
    }
    // W6: whatever separators and terminators are left are neutral.
    for int i = 0, i < n, i++ {
        if types[i] == BIDI_ES || types[i] == BIDI_ET || types[i] == BIDI_CS {
            types[i] = BIDI_ON
        }
    }
    // W7: a European number after a left-to-right strong type is
    // left-to-right itself.
    lastStrong = base == 1 ? BIDI_R : BIDI_L
    for int i = 0, i < n, i++ {
        int ty = types[i]
        if ty == BIDI_L || ty == BIDI_R { lastStrong = ty }
        else if ty == BIDI_EN && lastStrong == BIDI_L { types[i] = BIDI_L }
    }
    // N1 and N2: a run of neutrals between two strongs of the same
    // direction takes it, and otherwise takes the paragraph's.
    int baseDir = base == 1 ? BIDI_R : BIDI_L
    for int i = 0, i < n, i++ {
        if !bidiIsNeutral(types[i]) { continue }
        int runEnd = i
        while runEnd < n && bidiIsNeutral(types[runEnd]) { runEnd++ }
        int before = i > 0 ? bidiDirOf(types[i-1]) : baseDir
        int after = runEnd < n ? bidiDirOf(types[runEnd]) : baseDir
        if before < 0 { before = baseDir }
        if after < 0 { after = baseDir }
        int resolved = before == after ? before : baseDir
        for int k = i, k < runEnd, k++ { types[k] = resolved }
        i = runEnd - 1
    }
    // I1 and I2: the levels themselves.
    arr[int] levels = []
    for int i = 0, i < n, i++ {
        int ty = types[i]
        int lv = base
        if base % 2 == 0 {
            if ty == BIDI_R { lv = base + 1 }
            else if ty == BIDI_AN || ty == BIDI_EN { lv = base + 2 }
        } else {
            if ty == BIDI_L || ty == BIDI_EN || ty == BIDI_AN { lv = base + 1 }
        }
        levels.push(lv)
    }
    return levels
}

// L2: from the highest level down to the lowest odd one, every
// contiguous run at or above that level is reversed. Doing it level by
// level is what makes a Latin run inside a Hebrew one come out forwards
// while the Hebrew around it comes out backwards.
arr[int] func bidiReorder(levels:arr[int]) {
    arr[int] order = []
    for int i = 0, i < levels.length, i++ { order.push(i) }
    int highest = 0
    int lowestOdd = 63
    for int i = 0, i < levels.length, i++ {
        if levels[i] > highest { highest = levels[i] }
        if levels[i] % 2 == 1 && levels[i] < lowestOdd { lowestOdd = levels[i] }
    }
    if lowestOdd > highest { return order }
    for int lv = highest, lv >= lowestOdd, lv-- {
        int i = 0
        while i < levels.length {
            if levels[i] < lv { i++  continue }
            int runEnd = i
            while runEnd < levels.length && levels[runEnd] >= lv { runEnd++ }
            // reverse order[i .. runEnd)
            int a = i
            int b = runEnd - 1
            while a < b {
                int tmp = order[a]
                order[a] = order[b]
                order[b] = tmp
                a++
                b--
            }
            i = runEnd
        }
    }
    return order
}

// unicode-bidi: bidi-override. Every character takes the paragraph's
// own direction whatever its own class, so a Latin run inside a
// right-to-left override comes out backwards too -- which is the whole
// point of the value, and the one case where reversing the line
// outright is the correct answer.
text func bidiVisualOverride(t:text, paragraphLevel:int) {
    if t == null || paragraphLevel % 2 == 0 { return t }
    text out = ''
    for int i = t.length - 1, i >= 0, i-- { out = out + t[i] }
    return out
}

// A line's characters in the order they are drawn.
text func bidiVisual(t:text, paragraphLevel:int) {
    if t == null || t.length < 2 { return t }
    arr[int] levels = bidiLevels(t, paragraphLevel)
    arr[int] order = bidiReorder(levels)
    text out = ''
    for int i = 0, i < order.length, i++ { out = out + t[order[i]] }
    return out
}
