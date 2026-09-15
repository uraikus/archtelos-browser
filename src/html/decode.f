// Input normalization.
//
// The tokenizer works on `ascii` for O(1) indexing, but a web page is
// UTF-8 and `text.toAscii()` answers null for anything outside ASCII
// (FINDINGS.md, "no non-ASCII in ascii"). So the raw bytes are rewritten
// here: every multi-byte UTF-8 sequence becomes an ESCAPE byte, the
// decimal code point, and a terminating `;`.
//
// The escape byte is U+0001, not `&`, on purpose. A `&#233;` written
// literally in a `<style>` or `<script>` element is *not* a character
// reference -- raw text is never decoded -- so rewriting non-ASCII as
// `&#233;` would make the two indistinguishable and force raw text to
// be decoded anyway. A byte the source could not otherwise carry keeps
// them apart: the tokenizer expands escapes everywhere and character
// references only where the standard says to.
//
// A literal U+0001 in the input is doubled, so the transformation is
// reversible for any byte sequence.

import ../util/text.f

const int ESCAPE_BYTE = 1

text func encodeCodePoint(cp:int) {
    return `${ESCAPE_BYTE.toChar()}${cp};`
}

text func blobToAsciiSafe(b:blob) {
    int n = b.length
    text out = ''
    int runStart = 0
    int i = 0
    while i < n {
        int c = b.byteAt(i)
        if c < 128 && c != ESCAPE_BYTE {
            i++
            continue
        }
        if i > runStart {
            text run = b.slice(runStart, i)
            out = out + run
        }
        if c == ESCAPE_BYTE {
            // a literal U+0001: double it
            text esc = `${ESCAPE_BYTE.toChar()}${ESCAPE_BYTE.toChar()}`
            out = out + esc
            i++
            runStart = i
            continue
        }
        int cp = 0
        int extra = 0
        if c >= 240 {
            cp = c - 240
            extra = 3
        } else if c >= 224 {
            cp = c - 224
            extra = 2
        } else if c >= 192 {
            cp = c - 192
            extra = 1
        } else {
            cp = 65533       // a stray continuation byte
            extra = 0
        }
        int j = i + 1
        int consumed = 0
        while consumed < extra && j < n {
            int cc = b.byteAt(j)
            if cc < 128 || cc >= 192 { break }
            cp = cp * 64 + (cc - 128)
            j++
            consumed++
        }
        if consumed < extra { cp = 65533 }
        text esc = encodeCodePoint(cp)
        out = out + esc
        i = j
        runStart = j
    }
    if n > runStart {
        text tail = b.slice(runStart, n)
        out = out + tail
    }
    return out
}

// The same transformation for text already in memory. `text` has no
// byte access, so this walks code points, which is O(n) per index --
// fine for the small inputs (tests, generated error pages) that use it.
text func textToAsciiSafe(t:text) {
    if t == null { return '' }
    ascii direct = t.toAscii()
    if direct != null && asciiIndexOf(direct, ESCAPE_BYTE.toChar().toAscii(), 0) < 0 { return t }
    text out = ''
    int i = 0
    while true {
        int cp = t.charCodeAt(i)
        if cp == null { break }
        if cp == ESCAPE_BYTE {
            text esc = `${ESCAPE_BYTE.toChar()}${ESCAPE_BYTE.toChar()}`
            out = out + esc
        } else if cp < 128 {
            text ch = cp.toChar()
            out = out + ch
        } else {
            text esc = encodeCodePoint(cp)
            out = out + esc
        }
        i++
    }
    return out
}
