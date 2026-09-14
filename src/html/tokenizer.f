// The HTML tokenizer of the WHATWG HTML Living Standard ("Tokenization").
//
// The states are the standard's own, collapsed where a run of
// characters can be scanned at once instead of one at a time: the data
// state emits a whole run of text as one character token, and the
// three raw-text states scan ahead for their appropriate end tag. Every
// branch that changes what a character *means* -- tag names, attribute
// quoting, comments, doctypes, character references, the script data
// escapes -- is written out state by state.
//
// State lives in module globals because Festina has no closures and no
// methods on a struct, so a "tokenizer object" is a set of globals plus
// functions over them (FINDINGS.md, "no closures").

import ../util/text.f
import entities.f

const int TOK_EOF = 0
const int TOK_START = 1
const int TOK_END = 2
const int TOK_TEXT = 3
const int TOK_COMMENT = 4
const int TOK_DOCTYPE = 5

// The content states the tree builder switches the tokenizer into.
const int TS_DATA = 0
const int TS_RCDATA = 1
const int TS_RAWTEXT = 2
const int TS_SCRIPT_DATA = 3
const int TS_PLAINTEXT = 4

struct Token {
    kind:int
    name:text           // lowercase tag name, or the doctype name
    attrs:map[text]
    present:map[bool]   // every attribute name, valued or not (see node.f)
    selfClosing:bool
    data:text           // character run, or comment data
    publicId:text
    systemId:text
    hasExternalId:bool
    forceQuirks:bool
}

ascii tokSrc = ''
int tokPos = 0
int tokLen = 0
int tokState = TS_DATA
text tokAppropriateEndTag = ''
bool tokAllowCdata = false      // set while the parser is in foreign content
// Set when a tag ran to the end of the input without its '>'. The
// standard's "eof in tag" states emit an end-of-file token and discard
// the tag, so the caller drops it.
bool tokTagUnterminated = false

void func tokenizerInit(src:ascii) {
    tokSrc = src.slice(0, src.length)      // a copy: see FINDINGS.md, "ascii aliasing"
    tokPos = 0
    tokLen = src.length
    tokState = TS_DATA
    tokAppropriateEndTag = ''
    tokAllowCdata = false
}

// The tree builder calls these when it inserts an element whose content
// model is not ordinary markup.
void func tokenizerSetState(state:int, endTag:text) {
    tokState = state
    tokAppropriateEndTag = `${endTag}`
}

Token func makeToken(kind:int) {
    Token t
    t.kind = kind
    t.name = ''
    t.data = ''
    return t
}

int func peekCode(at:int) {
    if at < 0 || at >= tokLen { return -1 }
    return tokSrc.charCodeAt(at)
}

bool func isTagTerminator(c:int) {
    return c == -1 || isSpaceCode(c) || c == CH_SLASH || c == CH_GT
}

// ---- tag tokens ------------------------------------------------------

// Reads a tag name starting at `from`, which the caller has checked
// begins with an ASCII letter. Ends at whitespace, '/' or '>'.
int func scanTagNameEnd(from:int) {
    int i = from
    while i < tokLen {
        int c = tokSrc.charCodeAt(i)
        if isSpaceCode(c) || c == CH_SLASH || c == CH_GT { break }
        i++
    }
    return i
}

// The attribute states, from "before attribute name" to the end of the
// tag. Returns the index just past the tag's '>'.
int func scanAttributes(from:int, tok:Token) {
    tokTagUnterminated = false
    int i = from
    while i < tokLen {
        while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
        if i >= tokLen { break }
        int c = tokSrc.charCodeAt(i)
        if c == CH_GT { return i + 1 }
        if c == CH_SLASH {
            // self-closing start tag state
            if peekCode(i + 1) == CH_GT {
                tok.selfClosing = true
                return i + 2
            }
            i++
            continue
        }
        // attribute name state: '=' after the first character ends it
        int nameStart = i
        if c == CH_EQ { i++ }       // a leading '=' is part of the name
        while i < tokLen {
            int nc = tokSrc.charCodeAt(i)
            if isSpaceCode(nc) || nc == CH_SLASH || nc == CH_GT || nc == CH_EQ { break }
            i++
        }
        text name = asciiLower(tokSrc.slice(nameStart, i)).toText()
        // after attribute name state
        while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
        text value = ''
        if i < tokLen && tokSrc.charCodeAt(i) == CH_EQ {
            i++
            while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
            int q = peekCode(i)
            if q == CH_QUOTE || q == CH_APOS {
                int close = i + 1
                while close < tokLen && tokSrc.charCodeAt(close) != q { close++ }
                value = decodeText(tokSrc.slice(i + 1, close), true, true)
                i = close < tokLen ? close + 1 : close
            } else {
                int end = i
                while end < tokLen {
                    int cc = tokSrc.charCodeAt(end)
                    if isSpaceCode(cc) || cc == CH_GT { break }
                    end++
                }
                value = decodeText(tokSrc.slice(i, end), true, true)
                i = end
            }
        }
        // a duplicate attribute keeps the first value
        if name != '' && tok.present[name] != true {
            tok.attrs[name] = value
            tok.present[name] = true
        }
    }
    tokTagUnterminated = true
    return i
}

// ---- comments ---------------------------------------------------------

// The comment states, entered just past `<!--`. Returns the index past
// the comment's end and fills `tok.data`.
int func scanComment(from:int, tok:Token) {
    int i = from
    // comment start state
    if peekCode(i) == CH_GT {
        tok.data = ''
        return i + 1
    }
    if peekCode(i) == CH_MINUS && peekCode(i + 1) == CH_GT {
        tok.data = ''
        return i + 2
    }
    text data = ''
    int runStart = i
    while i < tokLen {
        int c = tokSrc.charCodeAt(i)
        if c != CH_MINUS {
            i++
            continue
        }
        // comment end dash / comment end states
        int dashes = 0
        int j = i
        while j < tokLen && tokSrc.charCodeAt(j) == CH_MINUS {
            dashes++
            j++
        }
        int after = peekCode(j)
        if dashes >= 2 && after == CH_GT {
            if i > runStart {
                text run = tokSrc.slice(runStart, i).toText()
                data = data + run
            }
            // dashes beyond the closing two belong to the comment
            if dashes > 2 {
                text extra = repeatText('-', dashes - 2)
                data = data + extra
            }
            tok.data = decodeText(data.toAscii(), false, false)
            return j + 1
        }
        if dashes >= 2 && after == CH_BANG && peekCode(j + 1) == CH_GT {
            // comment end bang state: `--!>` also closes the comment
            if i > runStart {
                text run = tokSrc.slice(runStart, i).toText()
                data = data + run
            }
            if dashes > 2 {
                text extra = repeatText('-', dashes - 2)
                data = data + extra
            }
            tok.data = decodeText(data.toAscii(), false, false)
            return j + 2
        }
        i = j
    }
    // EOF in comment: everything left is the comment
    if tokLen > runStart {
        text run = tokSrc.slice(runStart, tokLen).toText()
        data = data + run
    }
    tok.data = decodeText(data.toAscii(), false, false)
    return tokLen
}

// The bogus comment state: everything up to the next '>'.
int func scanBogusComment(from:int, tok:Token) {
    int end = asciiIndexOf(tokSrc, '>', from)
    int stop = end < 0 ? tokLen : end
    tok.data = decodeText(tokSrc.slice(from, stop), false, false)
    return end < 0 ? tokLen : end + 1
}

// ---- doctype -----------------------------------------------------------

// Reads a quoted doctype identifier at `from`, whose first character is
// the quote. Leaves the value in `doctypeIdValue`.
text doctypeIdValue = ''

int func scanDoctypeId(from:int) {
    int q = peekCode(from)
    int i = from + 1
    while i < tokLen {
        int c = tokSrc.charCodeAt(i)
        if c == q || c == CH_GT { break }
        i++
    }
    doctypeIdValue = decodeText(tokSrc.slice(from + 1, i), false, false)
    if i < tokLen && tokSrc.charCodeAt(i) == q { i++ }
    return i
}

// The doctype states, entered just past `<!DOCTYPE`.
int func scanDoctype(from:int, tok:Token) {
    int i = from
    tok.forceQuirks = false
    while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
    if i >= tokLen || tokSrc.charCodeAt(i) == CH_GT {
        tok.forceQuirks = true
        tok.name = ''
        return i < tokLen ? i + 1 : tokLen
    }
    int nameStart = i
    while i < tokLen {
        int c = tokSrc.charCodeAt(i)
        if isSpaceCode(c) || c == CH_GT { break }
        i++
    }
    tok.name = asciiLower(tokSrc.slice(nameStart, i)).toText()
    while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
    if i < tokLen && tokSrc.charCodeAt(i) == CH_GT { return i + 1 }
    // after doctype name state: PUBLIC or SYSTEM, else bogus doctype
    if asciiStartsWithLower(tokSrc, 'public', i) {
        i = i + 6
        while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
        int q = peekCode(i)
        if q == CH_QUOTE || q == CH_APOS {
            i = scanDoctypeId(i)
            tok.publicId = doctypeIdValue
            tok.hasExternalId = true
        } else {
            tok.forceQuirks = true
        }
        while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
        int q2 = peekCode(i)
        if q2 == CH_QUOTE || q2 == CH_APOS {
            i = scanDoctypeId(i)
            tok.systemId = doctypeIdValue
            tok.hasExternalId = true
        }
    } else if asciiStartsWithLower(tokSrc, 'system', i) {
        i = i + 6
        while i < tokLen && isSpaceCode(tokSrc.charCodeAt(i)) { i++ }
        int q = peekCode(i)
        if q == CH_QUOTE || q == CH_APOS {
            i = scanDoctypeId(i)
            tok.systemId = doctypeIdValue
            tok.hasExternalId = true
        } else {
            tok.forceQuirks = true
        }
    } else {
        tok.forceQuirks = true
    }
    // bogus doctype state: skip to '>'
    int end = asciiIndexOf(tokSrc, '>', i)
    return end < 0 ? tokLen : end + 1
}

// ---- raw text ------------------------------------------------------------

// Finds where the appropriate end tag starts, from `from`, honouring the
// script data escaped and double escaped states. Answers tokLen when the
// element runs to the end of the input.
int func findRawTextEnd(from:int) {
    ascii name = tokAppropriateEndTag.toAscii()
    if name == null { return tokLen }
    int i = from
    bool escaped = false
    bool doubleEscaped = false
    bool script = tokState == TS_SCRIPT_DATA
    while i < tokLen {
        int c = tokSrc.charCodeAt(i)
        if script {
            // script data escaped / double escaped states
            if !escaped && c == CH_LT && asciiStartsWith(tokSrc, '!--', i + 1) {
                escaped = true
                i = i + 4
                continue
            }
            if escaped && c == CH_MINUS && asciiStartsWith(tokSrc, '->', i + 1) {
                escaped = false
                doubleEscaped = false
                i = i + 3
                continue
            }
            if escaped && !doubleEscaped && c == CH_LT && asciiStartsWithLower(tokSrc, 'script', i + 1)
                    && isTagTerminator(peekCode(i + 7)) {
                doubleEscaped = true
                i = i + 7
                continue
            }
            if doubleEscaped && c == CH_LT && peekCode(i + 1) == CH_SLASH
                    && asciiStartsWithLower(tokSrc, 'script', i + 2) && isTagTerminator(peekCode(i + 8)) {
                doubleEscaped = false
                i = i + 8
                continue
            }
        }
        if c == CH_LT && peekCode(i + 1) == CH_SLASH && !doubleEscaped {
            if asciiStartsWithLower(tokSrc, name, i + 2) && isTagTerminator(peekCode(i + 2 + name.length)) {
                return i
            }
        }
        i++
    }
    return tokLen
}

Token func rawTextToken() {
    int end = findRawTextEnd(tokPos)
    if end > tokPos {
        Token t = makeToken(TOK_TEXT)
        // RCDATA decodes character references; RAWTEXT, script data and
        // plaintext never do. Both expand this implementation's escapes.
        t.data = decodeText(tokSrc.slice(tokPos, end), tokState == TS_RCDATA, false)
        tokPos = end
        return t
    }
    // at the end tag
    Token t = makeToken(TOK_END)
    int nameStart = tokPos + 2
    int nameEnd = scanTagNameEnd(nameStart)
    t.name = asciiLower(tokSrc.slice(nameStart, nameEnd)).toText()
    tokPos = scanAttributes(nameEnd, t)
    tokState = TS_DATA
    tokAppropriateEndTag = ''
    if tokTagUnterminated { return makeToken(TOK_EOF) }
    return t
}

// ---- the data state --------------------------------------------------------

Token func nextToken() {
    if tokState == TS_PLAINTEXT {
        if tokPos >= tokLen { return makeToken(TOK_EOF) }
        Token t = makeToken(TOK_TEXT)
        t.data = decodeText(tokSrc.slice(tokPos, tokLen), false, false)
        tokPos = tokLen
        return t
    }
    if tokState != TS_DATA {
        if tokPos >= tokLen { return makeToken(TOK_EOF) }
        return rawTextToken()
    }
    while true {
        if tokPos >= tokLen { return makeToken(TOK_EOF) }
        int c = tokSrc.charCodeAt(tokPos)
        if c != CH_LT {
            // character run, to the next '<' that begins real markup
            int i = tokPos
            while i < tokLen {
                if tokSrc.charCodeAt(i) == CH_LT {
                    int nx = peekCode(i + 1)
                    if isAlphaCode(nx) || nx == CH_SLASH || nx == CH_BANG || nx == CH_QUESTION { break }
                }
                i++
            }
            Token t = makeToken(TOK_TEXT)
            t.data = decodeText(tokSrc.slice(tokPos, i), true, false)
            tokPos = i
            return t
        }
        int nx = peekCode(tokPos + 1)
        if nx == CH_BANG {
            // markup declaration open state
            if asciiStartsWith(tokSrc, '--', tokPos + 2) {
                Token t = makeToken(TOK_COMMENT)
                tokPos = scanComment(tokPos + 4, t)
                return t
            }
            if asciiStartsWithLower(tokSrc, 'doctype', tokPos + 2) {
                Token t = makeToken(TOK_DOCTYPE)
                tokPos = scanDoctype(tokPos + 9, t)
                return t
            }
            if asciiStartsWith(tokSrc, '[CDATA[', tokPos + 2) {
                if tokAllowCdata {
                    int close = asciiIndexOf(tokSrc, ']]>', tokPos + 9)
                    Token t = makeToken(TOK_TEXT)
                    int stop = close < 0 ? tokLen : close
                    t.data = decodeText(tokSrc.slice(tokPos + 9, stop), false, false)
                    tokPos = close < 0 ? tokLen : close + 3
                    return t
                }
                Token t = makeToken(TOK_COMMENT)
                tokPos = scanBogusComment(tokPos + 2, t)
                return t
            }
            Token t = makeToken(TOK_COMMENT)
            tokPos = scanBogusComment(tokPos + 2, t)
            return t
        }
        if nx == CH_QUESTION {
            // bogus comment state, keeping the '?'
            Token t = makeToken(TOK_COMMENT)
            tokPos = scanBogusComment(tokPos + 1, t)
            return t
        }
        if nx == CH_SLASH {
            int after = peekCode(tokPos + 2)
            if after == CH_GT {
                // `</>` is a parse error and produces nothing
                tokPos = tokPos + 3
                continue
            }
            if !isAlphaCode(after) {
                Token t = makeToken(TOK_COMMENT)
                tokPos = scanBogusComment(tokPos + 2, t)
                return t
            }
            Token t = makeToken(TOK_END)
            int nameStart = tokPos + 2
            int nameEnd = scanTagNameEnd(nameStart)
            t.name = asciiLower(tokSrc.slice(nameStart, nameEnd)).toText()
            tokPos = scanAttributes(nameEnd, t)
            if tokTagUnterminated { return makeToken(TOK_EOF) }
            return t
        }
        if isAlphaCode(nx) {
            Token t = makeToken(TOK_START)
            int nameStart = tokPos + 1
            int nameEnd = scanTagNameEnd(nameStart)
            t.name = asciiLower(tokSrc.slice(nameStart, nameEnd)).toText()
            tokPos = scanAttributes(nameEnd, t)
            if tokTagUnterminated { return makeToken(TOK_EOF) }
            return t
        }
        // a '<' that begins nothing: character data
        Token t = makeToken(TOK_TEXT)
        t.data = '<'
        tokPos = tokPos + 1
        return t
    }
    return makeToken(TOK_EOF)
}
