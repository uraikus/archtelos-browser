// The bidirectional algorithm (Unicode Annex #9).
//
// A right-to-left script is stored in the order it is read and drawn in
// the order it appears, and those are not the same order. This turns
// the first into the second: it takes a line's characters in logical
// order and returns them in visual order, left to right, which is the
// order a renderer with no bidi support of its own can draw.
//
// Both halves of the algorithm are here. The implicit half -- the W, N
// and I rules -- resolves a character's direction from its own class
// and its neighbours'. The explicit half -- the X rules -- is the nine
// directional formatting characters a document uses to say what the
// implicit half would get wrong: the embeddings, the overrides and the
// isolates, with their directional status stack, their overflow
// counters and the isolating run sequences the implicit rules then run
// over one at a time.
//
// `unicode-bidi` is the same nine characters under another name. CSS
// Writing Modes 3 §2.2 defines each of its values as the pair the
// element's text is wrapped in -- `embed` is LRE or RLE and a PDF,
// `isolate` is LRI or RLI and a PDI, `plaintext` is an FSI and a PDI --
// so that is how it is implemented, by wrapping and running the one
// algorithm rather than by a second path through it.
//
// Two of the standard's rules are not here. W1 resolves a combining
// mark to the class of the character it sits on, and N0 pairs brackets
// so that one inside a right-to-left run is mirrored with its partner;
// both need the Unicode database this repository does not vendor --
// the combining class and the bracket pairs -- and the character
// classes below come from script ranges for the same reason.
//
// The ranges cover the scripts the algorithm exists for -- Hebrew,
// Arabic, Syriac, Thaana, N'Ko -- and everything outside them is
// left-to-right or neutral, which is what the database says for the
// scripts a browser meets in practice.

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
// The explicit formatting characters (BD2, BD3, BD8).
const int BIDI_LRE = 11     // left-to-right embedding
const int BIDI_RLE = 12     // right-to-left embedding
const int BIDI_LRO = 13     // left-to-right override
const int BIDI_RLO = 14     // right-to-left override
const int BIDI_PDF = 15     // pop directional formatting
const int BIDI_LRI = 16     // left-to-right isolate
const int BIDI_RLI = 17     // right-to-left isolate
const int BIDI_FSI = 18     // first strong isolate
const int BIDI_PDI = 19     // pop directional isolate

const int BIDI_CP_LRE = 8234
const int BIDI_CP_RLE = 8235
const int BIDI_CP_PDF = 8236
const int BIDI_CP_LRO = 8237
const int BIDI_CP_RLO = 8238
const int BIDI_CP_LRI = 8294
const int BIDI_CP_RLI = 8295
const int BIDI_CP_FSI = 8296
const int BIDI_CP_PDI = 8297

// `unicode-bidi`, whose values are the wrappings above under the names
// a stylesheet gives them (CSS Writing Modes 3 §2.2).
const int UBIDI_NORMAL = 0
const int UBIDI_EMBED = 1
const int UBIDI_OVERRIDE = 2
const int UBIDI_ISOLATE = 3
const int UBIDI_ISOLATE_OVERRIDE = 4
const int UBIDI_PLAINTEXT = 5

// Whether any element on this page declared a `unicode-bidi` that does
// anything, so that a page that never mentions the property pays
// nothing for it (CLAUDE.md, "a feature must not cost anything to the
// pages that do not use it").
bool anyUnicodeBidi = false

// X1: an embedding deeper than this overflows rather than nesting.
const int BIDI_MAX_DEPTH = 125

// One formatting character as text, so that a source file can name one
// rather than carry an invisible literal.
text func bidiControl(cp:int) { return cp.toChar() }

// NI, the standard's name for what the N rules resolve: the neutrals
// and the isolate formatting characters, which are treated as neutral
// wherever they survive to the N rules.
bool func bidiIsNeutral(t:int) {
    return t == BIDI_WS || t == BIDI_ON || t == BIDI_B
        || t == BIDI_ES || t == BIDI_ET || t == BIDI_CS
        || t == BIDI_LRI || t == BIDI_RLI || t == BIDI_FSI || t == BIDI_PDI
}

// X9 removes the embeddings, the overrides and the PDFs: they take no
// space and take no part in the rules that follow.
bool func bidiRemovedByX9(t:int) {
    return t == BIDI_LRE || t == BIDI_RLE || t == BIDI_LRO
        || t == BIDI_RLO || t == BIDI_PDF
}

bool func bidiIsInitiator(t:int) {
    return t == BIDI_LRI || t == BIDI_RLI || t == BIDI_FSI
}

// Whether a character is one of the nine, none of which is drawn.
bool func bidiIsFormatting(t:int) {
    return bidiRemovedByX9(t) || bidiIsInitiator(t) || t == BIDI_PDI
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
    // The nine formatting characters sit inside the general punctuation
    // block the line after them would otherwise call neutral. They are
    // asked for behind one range test rather than nine equalities,
    // because this runs over every character of every page.
    if cp >= BIDI_CP_LRE && cp <= BIDI_CP_PDI {
        if cp == BIDI_CP_LRE { return BIDI_LRE }
        if cp == BIDI_CP_RLE { return BIDI_RLE }
        if cp == BIDI_CP_PDF { return BIDI_PDF }
        if cp == BIDI_CP_LRO { return BIDI_LRO }
        if cp == BIDI_CP_RLO { return BIDI_RLO }
        if cp == BIDI_CP_LRI { return BIDI_LRI }
        if cp == BIDI_CP_RLI { return BIDI_RLI }
        if cp == BIDI_CP_FSI { return BIDI_FSI }
        if cp == BIDI_CP_PDI { return BIDI_PDI }
    }
    if cp >= 8192 && cp <= 8303 { return BIDI_ON }
    return BIDI_L
}

// Whether a string holds anything that could reorder. A line of Latin
// text never does, so the whole pass is skipped for it -- which is what
// keeps the algorithm off the pages that do not need it. A formatting
// character counts: it is there to change an order.
bool func bidiNeedsReorder(t:text) {
    for int i = 0, i < t.length, i++ {
        int c = bidiClass(t.charCodeAt(i))
        if c == BIDI_R || c == BIDI_AL || c == BIDI_AN { return true }
        // Every formatting class is numbered above BIDI_B, so one
        // comparison asks for all nine -- this loop runs over every
        // text box on every page.
        if c >= BIDI_LRE { return true }
    }
    return false
}

// ---- the resolved state --------------------------------------------------
// The algorithm produces a class and a level for every character, and a
// function returns one value (FINDINGS.md, "one value out of a
// function"), so the pass writes into these and its callers read them.
arr[int] bidiOrig = []       // each character's class, as classified
arr[int] bidiType = []       // and as the rules resolve it
arr[int] bidiLevel = []      // its embedding level
arr[int] bidiPairPDI = []    // an isolate initiator's matching PDI, or -1
arr[int] bidiPairInit = []   // a PDI's matching initiator, or -1

bool func bidiIsEmbedding(t:int) {
    return t == BIDI_LRE || t == BIDI_RLE || t == BIDI_LRO || t == BIDI_RLO
}

int func bidiNextOdd(l:int) { return l % 2 == 0 ? l + 1 : l + 2 }
int func bidiNextEven(l:int) { return l % 2 == 0 ? l + 2 : l + 1 }

// BD9: which PDI closes which isolate initiator. An initiator with none
// runs to the end of the paragraph, and a PDI with none is an ordinary
// neutral.
void func bidiMatchIsolates() {
    int n = bidiOrig.length
    bidiPairPDI = []
    bidiPairInit = []
    for int i = 0, i < n, i++ { bidiPairPDI.push(-1)  bidiPairInit.push(-1) }
    arr[int] open = []
    for int i = 0, i < n, i++ {
        int t = bidiOrig[i]
        if bidiIsInitiator(t) { open.push(i)  continue }
        if t == BIDI_PDI && open.length > 0 {
            int j = open.pop()
            bidiPairPDI[j] = i
            bidiPairInit[i] = j
        }
    }
}

// P2 and P3 over one span: the first strong character in it decides the
// direction, and what an isolate inside it encloses is skipped.
bool func bidiFirstStrongRtl(from:int, to:int) {
    int depth = 0
    for int i = from, i < to, i++ {
        int t = bidiOrig[i]
        if bidiIsInitiator(t) { depth++  continue }
        if t == BIDI_PDI { if depth > 0 { depth-- }  continue }
        if depth > 0 { continue }
        if t == BIDI_L { return false }
        if t == BIDI_R || t == BIDI_AL { return true }
    }
    return false
}

// X1 to X8: the directional status stack. Every character comes out
// with the embedding level in force where it stands, and one inside an
// override comes out with that override's class instead of its own.
void func bidiExplicit(paragraphLevel:int) {
    int n = bidiOrig.length
    arr[int] stLevel = []
    arr[int] stOverride = []
    arr[bool] stIsolate = []
    stLevel.push(paragraphLevel)
    stOverride.push(-1)
    stIsolate.push(false)
    // X1's three counters: an embedding past the depth limit, or inside
    // one that already overflowed, is dropped rather than nested, and
    // the matching PDF or PDI has to know that to undo it.
    int overflowIsolate = 0
    int overflowEmbedding = 0
    int validIsolate = 0
    for int i = 0, i < n, i++ {
        int t = bidiOrig[i]
        int last = stLevel.length - 1
        if bidiIsEmbedding(t) {
            // X2 to X5
            bidiLevel[i] = stLevel[last]
            int nl = (t == BIDI_RLE || t == BIDI_RLO)
                ? bidiNextOdd(stLevel[last]) : bidiNextEven(stLevel[last])
            if nl <= BIDI_MAX_DEPTH && overflowIsolate == 0 && overflowEmbedding == 0 {
                stLevel.push(nl)
                stOverride.push(t == BIDI_RLO ? BIDI_R : (t == BIDI_LRO ? BIDI_L : -1))
                stIsolate.push(false)
            } else if overflowIsolate == 0 {
                overflowEmbedding++
            }
            continue
        }
        if t == BIDI_PDF {
            // X7
            bidiLevel[i] = stLevel[last]
            if overflowIsolate > 0 { continue }
            if overflowEmbedding > 0 { overflowEmbedding--  continue }
            if !stIsolate[last] && stLevel.length >= 2 {
                stLevel.pop()
                stOverride.pop()
                stIsolate.pop()
            }
            continue
        }
        if bidiIsInitiator(t) {
            // X5a, X5b and X5c: the initiator itself belongs to the
            // level outside the isolate it opens.
            bidiLevel[i] = stLevel[last]
            if stOverride[last] >= 0 { bidiType[i] = stOverride[last] }
            bool rtl = t == BIDI_RLI
            if t == BIDI_FSI {
                int stop = bidiPairPDI[i] >= 0 ? bidiPairPDI[i] : n
                rtl = bidiFirstStrongRtl(i + 1, stop)
            }
            int nl = rtl ? bidiNextOdd(stLevel[last]) : bidiNextEven(stLevel[last])
            if nl <= BIDI_MAX_DEPTH && overflowIsolate == 0 && overflowEmbedding == 0 {
                validIsolate++
                stLevel.push(nl)
                stOverride.push(-1)
                stIsolate.push(true)
            } else {
                overflowIsolate++
            }
            continue
        }
        if t == BIDI_PDI {
            // X6a: a PDI closes every embedding the isolate opened as
            // well as the isolate, and then belongs to the level
            // outside it, which is the level its initiator had.
            if overflowIsolate > 0 { overflowIsolate-- }
            else if validIsolate > 0 {
                overflowEmbedding = 0
                while !stIsolate[stLevel.length - 1] {
                    stLevel.pop()
                    stOverride.pop()
                    stIsolate.pop()
                }
                stLevel.pop()
                stOverride.pop()
                stIsolate.pop()
                validIsolate--
            }
            int now = stLevel.length - 1
            bidiLevel[i] = stLevel[now]
            if stOverride[now] >= 0 { bidiType[i] = stOverride[now] }
            continue
        }
        if t == BIDI_B {
            // X8
            bidiLevel[i] = paragraphLevel
            continue
        }
        // X6
        bidiLevel[i] = stLevel[last]
        if stOverride[last] >= 0 { bidiType[i] = stOverride[last] }
    }
}

// W2 to W7, N1, N2 and I1, I2 over one isolating run sequence. `sos`
// and `eos` stand in for the strong types either side of it, which is
// what makes a sequence resolvable on its own.
void func bidiImplicit(chars:arr[int], level:int, sos:int, eos:int) {
    int n = chars.length
    // W2: a European number takes its direction from the last strong
    // type before it, becoming an Arabic number after an Arabic letter.
    int lastStrong = sos
    for int i = 0, i < n, i++ {
        int ty = bidiType[chars[i]]
        if ty == BIDI_L || ty == BIDI_R || ty == BIDI_AL { lastStrong = ty }
        else if ty == BIDI_EN && lastStrong == BIDI_AL { bidiType[chars[i]] = BIDI_AN }
    }
    // W3: an Arabic letter is right-to-left from here on.
    for int i = 0, i < n, i++ {
        if bidiType[chars[i]] == BIDI_AL { bidiType[chars[i]] = BIDI_R }
    }
    // W4: a single separator between two numbers of the same kind joins
    // them.
    for int i = 1, i < n - 1, i++ {
        int ty = bidiType[chars[i]]
        int before = bidiType[chars[i-1]]
        int after = bidiType[chars[i+1]]
        if ty == BIDI_ES && before == BIDI_EN && after == BIDI_EN { bidiType[chars[i]] = BIDI_EN }
        else if ty == BIDI_CS && before == BIDI_EN && after == BIDI_EN { bidiType[chars[i]] = BIDI_EN }
        else if ty == BIDI_CS && before == BIDI_AN && after == BIDI_AN { bidiType[chars[i]] = BIDI_AN }
    }
    // W5: a run of terminators beside a European number joins it.
    for int i = 0, i < n, i++ {
        if bidiType[chars[i]] != BIDI_ET { continue }
        int runEnd = i
        while runEnd < n && bidiType[chars[runEnd]] == BIDI_ET { runEnd++ }
        bool before = i > 0 && bidiType[chars[i-1]] == BIDI_EN
        bool after = runEnd < n && bidiType[chars[runEnd]] == BIDI_EN
        if before || after {
            for int k = i, k < runEnd, k++ { bidiType[chars[k]] = BIDI_EN }
        }
        i = runEnd - 1
    }
    // W6: whatever separators and terminators are left are neutral.
    for int i = 0, i < n, i++ {
        int ty = bidiType[chars[i]]
        if ty == BIDI_ES || ty == BIDI_ET || ty == BIDI_CS { bidiType[chars[i]] = BIDI_ON }
    }
    // W7: a European number after a left-to-right strong type is
    // left-to-right itself.
    lastStrong = sos
    for int i = 0, i < n, i++ {
        int ty = bidiType[chars[i]]
        if ty == BIDI_L || ty == BIDI_R { lastStrong = ty }
        else if ty == BIDI_EN && lastStrong == BIDI_L { bidiType[chars[i]] = BIDI_L }
    }
    // N1 and N2: a run of neutrals between two strongs of the same
    // direction takes it, and otherwise takes the sequence's own.
    int seqDir = level % 2 == 1 ? BIDI_R : BIDI_L
    for int i = 0, i < n, i++ {
        if !bidiIsNeutral(bidiType[chars[i]]) { continue }
        int runEnd = i
        while runEnd < n && bidiIsNeutral(bidiType[chars[runEnd]]) { runEnd++ }
        int before = i > 0 ? bidiDirOf(bidiType[chars[i-1]]) : sos
        int after = runEnd < n ? bidiDirOf(bidiType[chars[runEnd]]) : eos
        if before < 0 { before = seqDir }
        if after < 0 { after = seqDir }
        int resolved = before == after ? before : seqDir
        for int k = i, k < runEnd, k++ { bidiType[chars[k]] = resolved }
        i = runEnd - 1
    }
    // I1 and I2: the levels themselves.
    for int i = 0, i < n, i++ {
        int ty = bidiType[chars[i]]
        int lv = level
        if level % 2 == 0 {
            if ty == BIDI_R { lv = level + 1 }
            else if ty == BIDI_AN || ty == BIDI_EN { lv = level + 2 }
        } else {
            if ty == BIDI_L || ty == BIDI_EN || ty == BIDI_AN { lv = level + 1 }
        }
        bidiLevel[chars[i]] = lv
    }
}

// X10 and BD13: the level runs, joined into isolating run sequences,
// and the implicit rules run over each one. A run ending in an isolate
// initiator is joined to the run its matching PDI starts, so an
// isolate's content resolves without the text around it and the text
// around it resolves without the content.
void func bidiSequences(paragraphLevel:int) {
    int n = bidiOrig.length
    // The characters X9 leaves, in order.
    arr[int] kept = []
    for int i = 0, i < n, i++ {
        if !bidiRemovedByX9(bidiOrig[i]) { kept.push(i) }
    }
    if kept.length == 0 { return }
    // Level runs over them.
    arr[int] runFrom = []
    arr[int] runTo = []
    int k = 0
    while k < kept.length {
        int e = k + 1
        while e < kept.length && bidiLevel[kept[e]] == bidiLevel[kept[k]] { e++ }
        runFrom.push(k)
        runTo.push(e)
        k = e
    }
    // Which run a character starts, so that a matching PDI can be
    // followed to the run it begins.
    arr[int] runAt = []
    for int i = 0, i < n, i++ { runAt.push(-1) }
    for int r = 0, r < runFrom.length, r++ { runAt[kept[runFrom[r]]] = r }
    arr[bool] used = []
    for int r = 0, r < runFrom.length, r++ { used.push(false) }

    for int r = 0, r < runFrom.length, r++ {
        if used[r] { continue }
        int firstChar = kept[runFrom[r]]
        // A run beginning with a matched PDI belongs to the sequence
        // that PDI's initiator is in, not to one of its own.
        if bidiOrig[firstChar] == BIDI_PDI && bidiPairInit[firstChar] >= 0 { continue }
        arr[int] chars = []
        int cur = r
        int lastPos = -1
        while true {
            used[cur] = true
            for int i = runFrom[cur], i < runTo[cur], i++ { chars.push(kept[i]) }
            lastPos = runTo[cur] - 1
            int lastChar = kept[lastPos]
            if !bidiIsInitiator(bidiOrig[lastChar]) { break }
            if bidiPairPDI[lastChar] < 0 { break }
            int nr = runAt[bidiPairPDI[lastChar]]
            if nr < 0 || used[nr] { break }
            cur = nr
        }
        if chars.length == 0 { continue }
        int level = bidiLevel[chars[0]]
        // sos and eos: the higher of the sequence's level and the level
        // on the other side of its edge decides the strong type there.
        int posFirst = runFrom[r]
        int beforeLevel = posFirst > 0 ? bidiLevel[kept[posFirst - 1]] : paragraphLevel
        int sosLevel = level > beforeLevel ? level : beforeLevel
        int lastChar = chars[chars.length - 1]
        int afterLevel = paragraphLevel
        if !(bidiIsInitiator(bidiOrig[lastChar]) && bidiPairPDI[lastChar] < 0) {
            // the kept character after the sequence's last one
            afterLevel = lastPos + 1 < kept.length
                ? bidiLevel[kept[lastPos + 1]] : paragraphLevel
        }
        int lastLevel = bidiLevel[lastChar]
        int eosLevel = lastLevel > afterLevel ? lastLevel : afterLevel
        bidiImplicit(chars, level, sosLevel % 2 == 1 ? BIDI_R : BIDI_L,
                     eosLevel % 2 == 1 ? BIDI_R : BIDI_L)
    }
}

// The whole of it, over one string, leaving the answer in bidiLevel.
void func bidiResolve(t:text, paragraphLevel:int) {
    int base = paragraphLevel % 2
    bidiOrig = []
    bidiType = []
    bidiLevel = []
    for int i = 0, i < t.length, i++ {
        int c = bidiClass(t.charCodeAt(i))
        bidiOrig.push(c)
        bidiType.push(c)
        bidiLevel.push(base)
    }
    bidiMatchIsolates()
    bidiExplicit(base)
    bidiSequences(base)
}

// The embedding level of every character, given the paragraph's own.
arr[int] func bidiLevels(t:text, paragraphLevel:int) {
    bidiResolve(t, paragraphLevel)
    arr[int] out = []
    for int i = 0, i < bidiLevel.length, i++ { out.push(bidiLevel[i]) }
    return out
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

// A line's characters in the order they are drawn. None of the nine
// formatting characters is drawn, so none of them is in the answer.
text func bidiVisual(t:text, paragraphLevel:int) {
    if t == null || t.length == 0 { return t }
    bidiResolve(t, paragraphLevel)
    arr[int] shown = []
    arr[int] levels = []
    for int i = 0, i < t.length, i++ {
        if bidiIsFormatting(bidiOrig[i]) { continue }
        shown.push(i)
        levels.push(bidiLevel[i])
    }
    arr[int] order = bidiReorder(levels)
    text out = ''
    for int i = 0, i < order.length, i++ { out = out + t[shown[order[i]]] }
    return out
}

// `unicode-bidi` as the standard defines it: the formatting characters
// the element's text is wrapped in (CSS Writing Modes 3 §2.2).
text func bidiWrapped(t:text, mode:int, rtl:bool) {
    if mode == UBIDI_EMBED {
        return bidiControl(rtl ? BIDI_CP_RLE : BIDI_CP_LRE) + t + bidiControl(BIDI_CP_PDF)
    }
    if mode == UBIDI_OVERRIDE {
        return bidiControl(rtl ? BIDI_CP_RLO : BIDI_CP_LRO) + t + bidiControl(BIDI_CP_PDF)
    }
    if mode == UBIDI_ISOLATE {
        return bidiControl(rtl ? BIDI_CP_RLI : BIDI_CP_LRI) + t + bidiControl(BIDI_CP_PDI)
    }
    if mode == UBIDI_ISOLATE_OVERRIDE {
        return bidiControl(rtl ? BIDI_CP_RLI : BIDI_CP_LRI)
            + bidiControl(rtl ? BIDI_CP_RLO : BIDI_CP_LRO)
            + t + bidiControl(BIDI_CP_PDF) + bidiControl(BIDI_CP_PDI)
    }
    if mode == UBIDI_PLAINTEXT {
        return bidiControl(BIDI_CP_FSI) + t + bidiControl(BIDI_CP_PDI)
    }
    return t
}

// One run of text in visual order, under the `unicode-bidi` its element
// declared and the direction that value opens an embedding in.
text func bidiVisualStyled(t:text, paragraphLevel:int, mode:int, rtl:bool) {
    if mode == UBIDI_NORMAL { return bidiVisual(t, paragraphLevel) }
    return bidiVisual(bidiWrapped(t, mode, rtl), paragraphLevel)
}
