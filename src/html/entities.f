// Character references, per the WHATWG HTML standard's "Character
// reference state" and the states that follow it.
//
// The named table itself is generated into named_refs.f. What lives
// here is the matching: longest-match over that table, the legacy
// no-semicolon forms, the attribute-value rule that leaves
// `?a=1&copy=2` alone, and numeric references with the standard's
// replacements for NUL, surrogates, out-of-range values and the
// C1 block.

import ../util/text.f
import named_refs.f
import decode.f

// The C1 replacements the standard gives for numeric references in
// 0x80-0x9F, which are the windows-1252 characters at those bytes.
int func cp1252(cp:int) {
    if cp == 128 { return 8364 }
    if cp == 130 { return 8218 }
    if cp == 131 { return 402 }
    if cp == 132 { return 8222 }
    if cp == 133 { return 8230 }
    if cp == 134 { return 8224 }
    if cp == 135 { return 8225 }
    if cp == 136 { return 710 }
    if cp == 137 { return 8240 }
    if cp == 138 { return 352 }
    if cp == 139 { return 8249 }
    if cp == 140 { return 338 }
    if cp == 142 { return 381 }
    if cp == 145 { return 8216 }
    if cp == 146 { return 8217 }
    if cp == 147 { return 8220 }
    if cp == 148 { return 8221 }
    if cp == 149 { return 8226 }
    if cp == 150 { return 8211 }
    if cp == 151 { return 8212 }
    if cp == 152 { return 732 }
    if cp == 153 { return 8482 }
    if cp == 154 { return 353 }
    if cp == 155 { return 8250 }
    if cp == 156 { return 339 }
    if cp == 158 { return 382 }
    if cp == 159 { return 376 }
    return cp
}

text func codePointToText(cpIn:int) {
    int cp = cpIn
    if cp >= 128 && cp <= 159 { cp = cp1252(cp) }
    if cp == 0 || cp > 1114111 || (cp >= 55296 && cp <= 57343) { cp = 65533 }
    return cp.toChar()
}

// Results of matchCharacterReference, read by the caller straight
// after the call: Festina has no tuples and no out-parameters
// (FINDINGS.md, "no multiple return values").
text refText = ''      // the replacement, or '' when nothing matched
int refEnd = 0         // index just past the reference
bool refOk = false

// Matches a character reference whose `&` is at `start`. `inAttribute`
// selects the rule that keeps a legacy reference literal when it is
// followed by `=` or an alphanumeric, so that a query string in an
// attribute survives unchanged.
void func matchCharacterReference(s:ascii, start:int, inAttribute:bool) {
    refOk = false
    refText = ''
    refEnd = start
    int n = s.length
    int i = start + 1
    if i >= n { return }
    int c = s.charCodeAt(i)
    if c == CH_HASH {
        i++
        bool hex = false
        if i < n {
            int x = s.charCodeAt(i)
            if x == 120 || x == 88 {
                hex = true
                i++
            }
        }
        int value = 0
        int digits = 0
        while i < n {
            int d = s.charCodeAt(i)
            if hex && isHexCode(d) { value = value * 16 + hexValue(d) }
            else if !hex && isDigitCode(d) { value = value * 10 + (d - CH_0) }
            else { break }
            if value > 1114111 { value = 1114112 }     // clamped; becomes U+FFFD
            digits++
            i++
        }
        if digits == 0 { return }
        if i < n && s.charCodeAt(i) == CH_SEMI { i++ }
        refOk = true
        refText = codePointToText(value)
        refEnd = i
        return
    }
    if !isAlnumCode(c) { return }
    // Longest match over the named table. Names run to 32 characters,
    // so this tries at most that many lookups and stops at the first
    // hit, which is the longest by construction.
    int limit = minInt(n - i, MAX_ENTITY_NAME)
    for int len = limit, len >= 2, len-- {
        ascii candidate = s.slice(i, i + len)
        text replacement = namedRefs[candidate.toText()]
        if replacement == null { continue }
        bool hasSemi = candidate.charCodeAt(len - 1) == CH_SEMI
        if !hasSemi && inAttribute {
            int after = i + len < n ? s.charCodeAt(i + len) : -1
            if after == CH_EQ || (after >= 0 && isAlnumCode(after)) { return }
        }
        refOk = true
        refText = replacement
        refEnd = i + len
        return
    }
}

// Expands the escapes decode.f introduced, and -- when `references` is
// true -- character references as well. Raw text (`script`, `style`)
// passes false: the standard never decodes references there, and the
// escapes are this implementation's own, so they are always expanded.
text func decodeText(s:ascii, references:bool, inAttribute:bool) {
    int n = s.length
    if n == 0 { return '' }
    bool anyEscape = asciiIndexOf(s, ESCAPE_BYTE.toChar().toAscii(), 0) >= 0
    bool anyAmp = references && asciiIndexOf(s, '&', 0) >= 0
    if !anyEscape && !anyAmp { return s.toText() }
    text out = ''
    int runStart = 0
    int i = 0
    while i < n {
        int c = s.charCodeAt(i)
        if c == ESCAPE_BYTE {
            if i > runStart {
                text run = s.slice(runStart, i).toText()
                out = out + run
            }
            int j = i + 1
            if j < n && s.charCodeAt(j) == ESCAPE_BYTE {
                text lit = ESCAPE_BYTE.toChar()
                out = out + lit
                i = j + 1
                runStart = i
                continue
            }
            int value = 0
            while j < n && isDigitCode(s.charCodeAt(j)) {
                value = value * 10 + (s.charCodeAt(j) - CH_0)
                j++
            }
            if j < n && s.charCodeAt(j) == CH_SEMI { j++ }
            text ch = value.toChar()
            if ch == null { ch = 65533.toChar() }
            out = out + ch
            i = j
            runStart = j
            continue
        }
        if c == CH_AMP && references {
            matchCharacterReference(s, i, inAttribute)
            if !refOk {
                i++
                continue
            }
            if i > runStart {
                text run = s.slice(runStart, i).toText()
                out = out + run
            }
            text repl = refText
            out = out + repl
            i = refEnd
            runStart = refEnd
            continue
        }
        i++
    }
    if n > runStart {
        text tail = s.slice(runStart, n).toText()
        out = out + tail
    }
    return out
}
