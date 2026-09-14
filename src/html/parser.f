// The tree builder: a deliberately small subset of the HTML5 tree
// construction algorithm -- void elements, raw-text elements, the
// implied end tags that make untidy real-world markup nest correctly
// (an open <p> closed by a block, <li>/<dt>/<dd>/<tr>/<td> closed by
// their siblings, an unclosed heading), and an html/head/body skeleton
// that always exists. No adoption agency, no foster parenting.

import ../dom/node.f
import tokenizer.f
import decode.f

arr[Node] openStack = []
Node docHtml
Node docHead
Node docBody
bool sawBodyContent = false

bool func isVoidElement(tag:text) {
    return tag == 'area' || tag == 'base' || tag == 'br' || tag == 'col' || tag == 'embed'
        || tag == 'hr' || tag == 'img' || tag == 'input' || tag == 'link' || tag == 'meta'
        || tag == 'param' || tag == 'source' || tag == 'track' || tag == 'wbr'
}

bool func isRawTextElement(tag:text) {
    return tag == 'script' || tag == 'style'
}

bool func isEscapableRawText(tag:text) {
    return tag == 'textarea' || tag == 'title'
}

bool func isHeadElement(tag:text) {
    return tag == 'title' || tag == 'meta' || tag == 'link' || tag == 'style'
        || tag == 'script' || tag == 'base' || tag == 'noscript'
}

// Start tags that implicitly close an open <p>.
bool func closesParagraph(tag:text) {
    return tag == 'address' || tag == 'article' || tag == 'aside' || tag == 'blockquote'
        || tag == 'details' || tag == 'div' || tag == 'dl' || tag == 'fieldset'
        || tag == 'figcaption' || tag == 'figure' || tag == 'footer' || tag == 'form'
        || tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4' || tag == 'h5' || tag == 'h6'
        || tag == 'header' || tag == 'hgroup' || tag == 'hr' || tag == 'main' || tag == 'menu'
        || tag == 'nav' || tag == 'ol' || tag == 'p' || tag == 'pre' || tag == 'section'
        || tag == 'table' || tag == 'ul' || tag == 'summary' || tag == 'center'
}

bool func isHeading(tag:text) {
    return tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4' || tag == 'h5' || tag == 'h6'
}

// Whitespace-only text between these is structure, not content.
bool func dropsBlankText(tag:text) {
    return tag == 'html' || tag == 'head' || tag == 'table' || tag == 'thead' || tag == 'tbody'
        || tag == 'tfoot' || tag == 'tr' || tag == 'select' || tag == 'colgroup' || tag == '#document'
}

// The open element is always read as `openStack[openStack.length - 1]`
// inline rather than through a helper returning it: returning a live
// node releases it afterwards, which costs a collector walk of its
// subtree (the whole body, by the end of a page) per token.
void func pushOpen(n:Node) {
    appendChild(openStack[openStack.length - 1], n)
    openStack.push(n)
}

// Index of the nearest open element with this tag, or -1. The search
// stops at the html/body/table-cell boundary the caller names so an
// end tag never closes across it.
int func findOpen(tag:text, stopAt:text) {
    return findOpen2(tag, stopAt, stopAt)
}

int func findOpen2(tag:text, stopA:text, stopB:text) {
    for int i = openStack.length - 1, i >= 0, i-- {
        text t = openStack[i].tag
        if t == tag { return i }
        if stopA != '' && (t == stopA || t == stopB || t == 'html') { return -1 }
    }
    return -1
}

void func popTo(index:int) {
    while openStack.length > index { openStack.pop() }
}

// Pops through the nearest open `tag` if there is one (within the
// scope boundary), i.e. an implied end tag.
void func closeIfOpen(tag:text, stopAt:text) {
    int i = findOpen(tag, stopAt)
    if i >= 0 { popTo(i) }
}

void func ensureBody() {
    if sawBodyContent { return }
    sawBodyContent = true
    // leave head / html on the stack; body becomes the insertion point
    popTo(1)
    openStack.push(docBody)
}

bool func textIsBlank(t:text) {
    ascii a = t.toAscii()
    if a == null { return false }
    return asciiIsBlank(a)
}

void func insertText(data:text) {
    if data == null || data == '' { return }
    if !sawBodyContent {
        if textIsBlank(data) { return }
        ensureBody()
    }
    int top = openStack.length - 1
    if textIsBlank(data) && dropsBlankText(openStack[top].tag) { return }
    // merge with a preceding text node
    int count = openStack[top].children.length
    if count > 0 && openStack[top].children[count - 1].kind == NODE_TEXT {
        openStack[top].children[count - 1].data = openStack[top].children[count - 1].data + data
        return
    }
    appendChild(openStack[top], newTextNode(data))
}

void func mergeAttrs(target:Node, tok:Token) {
    arr[text] names = tok.present.keys()
    for int i = 0, i < names.length, i++ {
        if !hasAttr(target, names[i]) { setAttr(target, names[i], tok.attrs[names[i]]) }
    }
}

void func handleStartTag(tok:Token) {
    text tag = tok.name
    if tag == 'html' {
        mergeAttrs(docHtml, tok)
        return
    }
    if tag == 'head' {
        mergeAttrs(docHead, tok)
        return
    }
    if tag == 'body' {
        mergeAttrs(docBody, tok)
        ensureBody()
        return
    }
    if !sawBodyContent && !isHeadElement(tag) { ensureBody() }
    if !sawBodyContent {
        // a head element: insert under head
        Node el = newElement(tag)
        el.attrs = tok.attrs
        el.present = tok.present
        appendChild(docHead, el)
        if isRawTextElement(tag) {
            text raw = readRawText(tag.toAscii(), false)
            if raw != '' { appendChild(el, newTextNode(raw)) }
        } else if isEscapableRawText(tag) {
            text raw = readRawText(tag.toAscii(), true)
            if raw != '' { appendChild(el, newTextNode(raw)) }
        }
        return
    }
    // implied end tags
    if closesParagraph(tag) { closeIfOpen('p', 'body') }
    if tag == 'li' {
        int li = findOpen2('li', 'ul', 'ol')
        if li >= 0 { popTo(li) }
    }
    if tag == 'dt' || tag == 'dd' {
        closeIfOpen('dt', 'dl')
        closeIfOpen('dd', 'dl')
    }
    if isHeading(tag) {
        if isHeading(openStack[openStack.length - 1].tag) { openStack.pop() }
    }
    if tag == 'option' { closeIfOpen('option', 'select') }
    if tag == 'tr' {
        closeIfOpen('td', 'table')
        closeIfOpen('th', 'table')
        closeIfOpen('tr', 'table')
    }
    if tag == 'td' || tag == 'th' {
        closeIfOpen('td', 'tr')
        closeIfOpen('th', 'tr')
    }
    if tag == 'thead' || tag == 'tbody' || tag == 'tfoot' {
        closeIfOpen('td', 'table')
        closeIfOpen('th', 'table')
        closeIfOpen('tr', 'table')
        closeIfOpen('thead', 'table')
        closeIfOpen('tbody', 'table')
        closeIfOpen('tfoot', 'table')
    }
    if tag == 'table' {
        // nested table start inside an unclosed cell is fine; but a
        // <table> while a <tr> is open with no cell means a stray one
    }
    Node el = newElement(tag)
    el.attrs = tok.attrs
    el.present = tok.present
    if isVoidElement(tag) {
        appendChild(openStack[openStack.length - 1], el)
        return
    }
    if isRawTextElement(tag) {
        appendChild(openStack[openStack.length - 1], el)
        text raw = readRawText(tag.toAscii(), false)
        if raw != '' { appendChild(el, newTextNode(raw)) }
        return
    }
    if isEscapableRawText(tag) {
        appendChild(openStack[openStack.length - 1], el)
        text raw = readRawText(tag.toAscii(), true)
        if raw != '' { appendChild(el, newTextNode(raw)) }
        return
    }
    pushOpen(el)
    if tok.selfClosing && (tag == 'svg' || tag == 'math') { openStack.pop() }
}

void func handleEndTag(tok:Token) {
    text tag = tok.name
    if tag == 'html' || tag == 'body' { return }
    if tag == 'head' {
        if !sawBodyContent { popTo(1) }
        return
    }
    if tag == 'br' {
        // </br> is treated as <br> by browsers
        Token fake = makeToken(TOK_START)
        fake.name = 'br'
        handleStartTag(fake)
        return
    }
    int i = findOpen(tag, '')
    if i <= 1 { return }      // never pop html or body
    popTo(i)
}

// Parses ASCII-safe HTML (see html/decode.f) into a document node.
Node func parseHtml(src:ascii) {
    Node doc = newDocument()
    docHtml = newElement('html')
    docHead = newElement('head')
    docBody = newElement('body')
    appendChild(doc, docHtml)
    appendChild(docHtml, docHead)
    appendChild(docHtml, docBody)
    openStack = [docHtml]
    sawBodyContent = false
    tokenizerInit(src)
    while true {
        Token tok = nextToken()
        if tok.kind == TOK_EOF { break }
        if tok.kind == TOK_START {
            handleStartTag(tok)
        } else if tok.kind == TOK_END {
            handleEndTag(tok)
        } else if tok.kind == TOK_TEXT {
            insertText(tok.data)
        }
        // comments and doctypes are dropped
    }
    openStack = []
    return doc
}

Node func parseHtmlBlob(b:blob) {
    text safe = blobToAsciiSafe(b)
    return parseHtml(safe.toAscii())
}

Node func parseHtmlText(t:text) {
    text safe = textToAsciiSafe(t)
    return parseHtml(safe.toAscii())
}
