// The html5lib tree serialization, which is what the WHATWG HTML
// standard's own test corpus compares against (the `#document`
// section of a tree-construction `.dat` file):
//
//     | <html>
//     |   <head>
//     |   <body>
//     |     <p>
//     |       id="x"
//     |       "text"
//
// One line per node: `| `, then two spaces per level of depth, then
// the node. Attributes come first, sorted by name, one per line, one
// level deeper than their element. Foreign elements carry a namespace
// prefix (`<svg circle>`), text is quoted, comments are `<!-- data -->`
// and a doctype prints its external ids only when it has them.

import node.f

text func serializeNamespacePrefix(ns:int) {
    if ns == NS_SVG { return 'svg ' }
    if ns == NS_MATHML { return 'math ' }
    return ''
}

void func serializeNodeInto(n:Node, depth:int, out:arr[text]) {
    text pad = repeatText('  ', depth)
    if n.kind == NODE_TEXT {
        out.push(`| ${pad}"${n.data}"`)
        return
    }
    if n.kind == NODE_COMMENT {
        out.push(`| ${pad}<!-- ${n.data} -->`)
        return
    }
    if n.kind == NODE_DOCTYPE {
        text name = n.data == null ? '' : n.data
        if n.hasExternalId {
            text pub = n.publicId == null ? '' : n.publicId
            text sys = n.systemId == null ? '' : n.systemId
            out.push(`| ${pad}<!DOCTYPE ${name} "${pub}" "${sys}">`)
        } else {
            out.push(`| ${pad}<!DOCTYPE ${name}>`)
        }
        return
    }
    if n.kind == NODE_FRAGMENT {
        out.push(`| ${pad}content`)
    }
    if n.kind == NODE_ELEMENT {
        text prefix = serializeNamespacePrefix(n.ns)
        out.push(`| ${pad}<${prefix}${n.tag}>`)
        arr[text] names = n.present.keys()
        names.sort(int (a:text, b:text) => compareText(a, b))
        text attrPad = repeatText('  ', depth + 1)
        for int i = 0, i < names.length, i++ {
            text v = n.attrs[names[i]]
            if v == null { v = '' }
            out.push(`| ${attrPad}${names[i]}="${v}"`)
        }
    }
    int count = n.children.length
    for int i = 0, i < count, i++ {
        serializeNodeInto(n.children[i], depth + 1, out)
    }
}

// The document's children, serialized. The document node itself has no
// line of its own, so its children start at depth 0.
text func serializeDocument(doc:Node) {
    arr[text] out = []
    int count = doc.children.length
    for int i = 0, i < count, i++ {
        serializeNodeInto(doc.children[i], 0, out)
    }
    return out.join('\n')
}
