// Input normalization. The tokenizer works on `ascii` for O(1)
// indexing, but a web page is UTF-8. text.toAscii() answers null for
// any non-ASCII input, so this pass rewrites every multi-byte UTF-8
// sequence in the raw bytes as a numeric character reference (`é`
// becomes `&#233;`), which the entity decoder turns back into UTF-8
// text when it builds a text node. Bytes are read through blob.byteAt,
// the one O(1) byte accessor Festina offers; runs of plain ASCII are
// copied with blob.slice.

import ../util/text.f

text func blobToAsciiSafe(b:blob) {
    int n = b.length
    text out = ''
    int runStart = 0
    int i = 0
    while i < n {
        int c = b.byteAt(i)
        if c < 128 {
            i++
            continue
        }
        if i > runStart {
            text run = b.slice(runStart, i)
            out = out + run
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
        text esc = `&#${cp};`
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

// The same transformation for text already in memory (a stylesheet
// fetched over HTTP arrives the same way, as a blob, so this is only
// for literals in tests). text has no byte access, so this walks code
// points instead -- O(n) per index, so keep the inputs small.
text func textToAsciiSafe(t:text) {
    if t == null { return '' }
    ascii direct = t.toAscii()
    if direct != null { return t }
    text out = ''
    int i = 0
    while true {
        int cp = t.charCodeAt(i)
        if cp == null { break }
        if cp < 128 {
            text ch = cp.toChar()
            out = out + ch
        } else {
            text esc = `&#${cp};`
            out = out + esc
        }
        i++
    }
    return out
}
