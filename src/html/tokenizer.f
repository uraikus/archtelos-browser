// The HTML tokenizer: turns the ASCII-safe source into start tags,
// end tags, text, comments and doctypes. State lives in globals
// (Festina has no closures and no methods on structs, so a "tokenizer
// object" is a set of module-level variables plus functions).

import ../util/text.f
import entities.f

const int TOK_EOF = 0
const int TOK_START = 1
const int TOK_END = 2
const int TOK_TEXT = 3
const int TOK_COMMENT = 4
const int TOK_DOCTYPE = 5

struct Token {
    kind:int
    name:text           // lowercase tag name
    attrs:map[text]
    present:map[bool]   // every attribute name, valued or not (see node.f)
    selfClosing:bool
    data:text           // decoded text / comment body
}

ascii tokSrc = ''
int tokPos = 0
int tokLen = 0

void func tokenizerInit(src:ascii) {
    tokSrc = src.slice(0, src.length)      // a copy: see FINDINGS.md on ascii parameters
    tokPos = 0
    tokLen = src.length
}

Token func makeToken(kind:int) {
    Token t
    t.kind = kind
    t.name = ''
    t.data = ''
    return t
}

int func peekCode(at:int) {
    if at >= tokLen { return -1 }
    return tokSrc.charCodeAt(at)
}

// Reads a tag name / attribute name: up to whitespace, '/', '>' or
// '=' (for attributes).
int func scanNameEnd(from:int, isAttr:bool) {
    int i = from
    while i < tokLen {
        int c = tokSrc.charCodeAt(i)
        if isSpaceCode(c) || c == CH_GT || c == CH_SLASH { break }
        if isAttr && c == CH_EQ && i > from { break }
        i++
    }
    return i
}

// Parses the attributes of a start tag beginning at `from`, filling
// `tok`, and returns the index just past the closing '>'.
int func scanAttributes(from:int, tok:Token) {
    int i = from
    while i < tokLen {
        while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
        if i >= tokLen { break }
        int c = tokSrc.charCodeAt(i)
        if c == CH_GT { return i + 1 }
        if c == CH_SLASH {
            if peekCode(i + 1) == CH_GT {
                tok.selfClosing = true
                return i + 2
            }
            i++
            continue
        }
        int nameEnd = scanNameEnd(i, true)
        if nameEnd == i {
            i++
            continue
        }
        text name = asciiLower(tokSrc.slice(i, nameEnd)).toText()
        i = nameEnd
        while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
        text value = ''
        if i < tokLen && tokSrc.charCodeAt(i) == CH_EQ {
            i++
            while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
            int q = peekCode(i)
            if q == CH_QUOTE || q == CH_APOS {
                int close = i + 1
                while close < tokLen && tokSrc.charCodeAt(close) != q { close++ }
                value = decodeEntities(tokSrc.slice(i + 1, close), false)
                i = close < tokLen ? close + 1 : close
            } else {
                int end = i
                while end < tokLen {
                    int cc = tokSrc.charCodeAt(end)
                    if isSpaceCode(cc) || cc == CH_GT { break }
                    end++
                }
                value = decodeEntities(tokSrc.slice(i, end), false)
                i = end
            }
        }
        if tok.present[name] != true {
            tok.attrs[name] = value
            tok.present[name] = true
        }
    }
    return i
}

Token func nextToken() {
    if tokPos >= tokLen { return makeToken(TOK_EOF) }
    int c = tokSrc.charCodeAt(tokPos)
    if c != CH_LT {
        // text up to the next '<' that starts a tag, comment or
        // end tag; a lone '<' followed by something else is text
        int i = tokPos
        while i < tokLen {
            if tokSrc.charCodeAt(i) == CH_LT && i + 1 < tokLen {
                int nx = tokSrc.charCodeAt(i + 1)
                if isAlphaCode(nx) || nx == CH_SLASH || nx == CH_BANG || nx == CH_QUESTION { break }
            }
            i++
        }
        Token t = makeToken(TOK_TEXT)
        t.data = decodeEntities(tokSrc.slice(tokPos, i), false)
        tokPos = i
        return t
    }
    int nx = peekCode(tokPos + 1)
    if nx == CH_BANG {
        if asciiStartsWith(tokSrc, '<!--', tokPos) {
            int end = asciiIndexOf(tokSrc, '-->', tokPos + 4)
            Token t = makeToken(TOK_COMMENT)
            if end < 0 {
                t.data = tokSrc.slice(tokPos + 4, tokLen).toText()
                tokPos = tokLen
            } else {
                t.data = tokSrc.slice(tokPos + 4, end).toText()
                tokPos = end + 3
            }
            return t
        }
        int end = asciiIndexOf(tokSrc, '>', tokPos)
        Token t = makeToken(TOK_DOCTYPE)
        if asciiStartsWith(tokSrc, '<![CDATA[', tokPos) {
            int cend = asciiIndexOf(tokSrc, ']]>', tokPos)
            t.kind = TOK_TEXT
            t.data = cend < 0 ? tokSrc.slice(tokPos + 9, tokLen).toText() : tokSrc.slice(tokPos + 9, cend).toText()
            tokPos = cend < 0 ? tokLen : cend + 3
            return t
        }
        t.data = end < 0 ? '' : tokSrc.slice(tokPos + 2, end).toText()
        tokPos = end < 0 ? tokLen : end + 1
        return t
    }
    if nx == CH_QUESTION {
        // a processing instruction / bogus comment: skip to '>'
        int end = asciiIndexOf(tokSrc, '>', tokPos)
        tokPos = end < 0 ? tokLen : end + 1
        return makeToken(TOK_COMMENT)
    }
    if nx == CH_SLASH {
        int nameStart = tokPos + 2
        int nameEnd = scanNameEnd(nameStart, false)
        Token t = makeToken(TOK_END)
        t.name = asciiLower(tokSrc.slice(nameStart, nameEnd)).toText()
        int end = asciiIndexOf(tokSrc, '>', nameEnd)
        tokPos = end < 0 ? tokLen : end + 1
        return t
    }
    if isAlphaCode(nx) {
        int nameStart = tokPos + 1
        int nameEnd = scanNameEnd(nameStart, false)
        Token t = makeToken(TOK_START)
        t.name = asciiLower(tokSrc.slice(nameStart, nameEnd)).toText()
        tokPos = scanAttributes(nameEnd, t)
        return t
    }
    // a stray '<': emit it as text
    Token t = makeToken(TOK_TEXT)
    t.data = '<'
    tokPos = tokPos + 1
    return t
}

// Everything up to `</name` (case-insensitively), consumed together
// with that end tag. For <script>/<style> (raw text) only the numeric
// references the input pre-pass produced are decoded; for <textarea>
// and <title> (escapable raw text) every reference is.
text func readRawText(name:ascii, escapable:bool) {
    ascii marker = '</' + name
    int end = asciiIndexOfLower(tokSrc, marker, tokPos)
    int textEnd = end < 0 ? tokLen : end
    text out = decodeEntities(tokSrc.slice(tokPos, textEnd), !escapable)
    if end < 0 {
        tokPos = tokLen
    } else {
        int close = asciiIndexOf(tokSrc, '>', end)
        tokPos = close < 0 ? tokLen : close + 1
    }
    return out
}
