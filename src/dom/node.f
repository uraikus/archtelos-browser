// The document tree. A Node is a struct with a parent pointer, so the
// tree is a cycle everywhere -- Festina's cycle collector (api.md,
// "A struct can name itself") is what makes that safe to build and
// drop without manual freeing.
//
// Struct identity cannot be compared in Festina (`a == b` on two
// structs is a compile error, specification.md 9.8), so every node
// carries a unique int id and "is this that node" is `a.id == b.id`.
//
// There is deliberately NO parent pointer. A struct graph with
// back-pointers is cycle-capable, and Festina's cycle collector then
// walks the whole reachable graph every time a local alias of any node
// is released while the node lives on -- for a tree that is the entire
// tree, on every loop iteration that binds a child to a local, which
// made the cascade and layout quadratic (FINDINGS.md, "cycle trials").
// Parents are looked up by id in a registry instead, which keeps the
// tree acyclic and every collector walk bounded by a subtree.

import ../css/style.f

const int NODE_ELEMENT = 1
const int NODE_TEXT = 3
const int NODE_DOCUMENT = 9

int nextNodeId = 1

// Every node ever created, indexed by id, so parentOf() is a lookup.
// Reset per page by the browser (nodeRegistryReset); a test that keeps
// several documents alive simply lets it grow.
arr[Node] nodeRegistry = [null]

void func nodeRegistryReset() {
    nodeRegistry = [null]
    nextNodeId = 1
}

void func registerNode(n:Node) {
    nodeRegistry.push(n)
}


struct Node {
    id:int
    kind:int
    tag:text            // lowercase element name; '' for text/document
    attrs:map[text]     // attribute values; an empty value reads as null
    present:map[bool]   // attribute names that exist at all: '' and null
                        // are one value in Festina, so presence needs
                        // its own record (FINDINGS.md, "empty text")
    children:arr[Node]
    parentId:int        // 0 = no parent; see nodeRegistry
    childIndex:int      // position in the parent's children (set by appendChild)
    data:text           // text node contents
    style:Style
    boxId:int
    // the class attribute split into names, computed once on first use
    classes:arr[text]
    classesParsed:bool
}

arr[text] func nodeClasses(n:Node) {
    ensureClassesParsed(n.id)
    return n.classes
}

void func ensureClassesParsed(nid:int) {
    if nodeRegistry[nid].classesParsed { return }
    nodeRegistry[nid].classesParsed = true
    text v = nodeRegistry[nid].attrs['class']
    if v != null {
        ascii av = v.toAscii()
        if av == null {
            nodeRegistry[nid].classes.push(v)
        } else {
            arr[ascii] words = asciiSplitSpace(av)
            for int i = 0, i < words.length, i++ { nodeRegistry[nid].classes.push(words[i].toText()) }
        }
    }
}

bool func hasClassOf(nid:int, cls:text) {
    ensureClassesParsed(nid)
    int count = nodeRegistry[nid].classes.length
    for int i = 0, i < count, i++ {
        if nodeRegistry[nid].classes[i] == cls { return true }
    }
    return false
}

Node func newElement(tag:text) {
    Node n
    n.id = nextNodeId
    nextNodeId++
    registerNode(n)
    n.kind = NODE_ELEMENT
    n.tag = `${tag}`            // a fresh copy: see FINDINGS.md, "text parameters"
    return n
}

Node func newTextNode(data:text) {
    Node n
    n.id = nextNodeId
    nextNodeId++
    registerNode(n)
    n.kind = NODE_TEXT
    n.tag = ''
    n.data = `${data}`
    return n
}

Node func newDocument() {
    Node n
    n.id = nextNodeId
    nextNodeId++
    registerNode(n)
    n.kind = NODE_DOCUMENT
    n.tag = '#document'
    return n
}

void func appendChild(parent:Node, child:Node) {
    child.parentId = parent.id
    child.childIndex = parent.children.length
    parent.children.push(child)
}

// Hot paths refer to nodes by id and read `nodeRegistry[id].field`
// inline: binding a live node to a local, or returning one from a
// function, releases a still-referenced value at scope exit, and each
// such release costs a collector walk of that node's subtree -- from
// <html> or <body>, the whole document (FINDINGS.md, "cycle trials").
Node func parentOf(n:Node) {
    if n.parentId <= 0 || n.parentId >= nodeRegistry.length { return null }
    return nodeRegistry[n.parentId]
}

// The id of the previous / next element sibling, or 0. The id-taking
// forms exist because a function that FORWARDS a struct parameter to
// another call retains it on entry and releases it on exit, and that
// release runs a collector walk over the node's subtree; an int
// parameter costs nothing.
int func prevElementSiblingOf(nid:int) {
    int parent = nodeRegistry[nid].parentId
    if parent <= 0 { return 0 }
    int i = nodeRegistry[nid].childIndex - 1
    while i >= 0 {
        if nodeRegistry[parent].children[i].kind == NODE_ELEMENT { return nodeRegistry[parent].children[i].id }
        i--
    }
    return 0
}

int func nextElementSiblingOf(nid:int) {
    int parent = nodeRegistry[nid].parentId
    if parent <= 0 { return 0 }
    int count = nodeRegistry[parent].children.length
    int i = nodeRegistry[nid].childIndex + 1
    while i < count {
        if nodeRegistry[parent].children[i].kind == NODE_ELEMENT { return nodeRegistry[parent].children[i].id }
        i++
    }
    return 0
}

int func previousElementSiblingId(n:Node) {
    return prevElementSiblingOf(n.id)
}

int func nextElementSiblingId(n:Node) {
    return nextElementSiblingOf(n.id)
}

// The attribute value of node `nid`, or null (also when present but empty).
text func attrOf(nid:int, name:text) {
    if nodeRegistry[nid].kind != NODE_ELEMENT { return null }
    return nodeRegistry[nid].attrs[name]
}

bool func hasAttrOf(nid:int, name:text) {
    if nodeRegistry[nid].kind != NODE_ELEMENT { return false }
    return nodeRegistry[nid].present[name] == true
}

// The id of the nearest ancestor-or-self element with this tag, or 0.
int func closestElementId(n:Node, tag:text) {
    int cur = n.id
    while cur > 0 {
        if nodeRegistry[cur].kind == NODE_ELEMENT && nodeRegistry[cur].tag == tag { return cur }
        cur = nodeRegistry[cur].parentId
    }
    return 0
}

bool func isElement(n:Node) {
    return n != null && n.kind == NODE_ELEMENT
}

bool func isText(n:Node) {
    return n != null && n.kind == NODE_TEXT
}

// null when the attribute is absent, '' when present but empty.
text func getAttr(n:Node, name:text) {
    if n == null || n.kind != NODE_ELEMENT { return null }
    return n.attrs[name]
}

bool func hasAttr(n:Node, name:text) {
    if n == null || n.kind != NODE_ELEMENT { return false }
    return n.present[name] == true
}

void func setAttr(n:Node, name:text, value:text) {
    n.attrs[name] = value
    n.present[name] = true
}

bool func hasParent(n:Node) {
    return n.parentId > 0
}

int func indexInParent(n:Node) {
    if !hasParent(n) { return -1 }
    return n.childIndex
}

Node func previousElementSibling(n:Node) {
    int id = previousElementSiblingId(n)
    return id == 0 ? null : nodeRegistry[id]
}

Node func nextElementSibling(n:Node) {
    int id = nextElementSiblingId(n)
    return id == 0 ? null : nodeRegistry[id]
}

bool func isFirstElementChild(n:Node) {
    return previousElementSiblingId(n) == 0
}

bool func isLastElementChild(n:Node) {
    return nextElementSiblingId(n) == 0
}

Node func firstChildElement(n:Node, tag:text) {
    for int i = 0, i < n.children.length, i++ {
        Node c = n.children[i]
        if c.kind == NODE_ELEMENT && c.tag == tag { return c }
    }
    return null
}

// Depth-first search for the first element with this tag.
Node func findElement(n:Node, tag:text) {
    if n.kind == NODE_ELEMENT && n.tag == tag { return n }
    for int i = 0, i < n.children.length, i++ {
        Node found = findElement(n.children[i], tag)
        if found != null { return found }
    }
    return null
}

void func collectElements(n:Node, tag:text, out:arr[Node]) {
    if n.kind == NODE_ELEMENT && n.tag == tag { out.push(n) }
    for int i = 0, i < n.children.length, i++ {
        collectElements(n.children[i], tag, out)
    }
}

// Nearest ancestor-or-self with this tag, or null.
Node func closestElement(n:Node, tag:text) {
    int id = closestElementId(n, tag)
    return id == 0 ? null : nodeRegistry[id]
}

// The concatenated text of every descendant text node.
text func textContent(n:Node) {
    if n.kind == NODE_TEXT { return n.data }
    text out = ''
    for int i = 0, i < n.children.length, i++ {
        text piece = textContent(n.children[i])
        out = out + piece
    }
    return out
}

// A readable dump of the tree, used by the tests to pin down exactly
// what the tree builder produced.
text func dumpTree(n:Node, indent:int) {
    text pad = repeatText('  ', indent)
    text out = ''
    if n.kind == NODE_TEXT {
        out = `${pad}"${n.data}"\n`
        return out
    }
    text attrText = ''
    arr[text] names = n.present.keys()
    names.sort(int (a:text, b:text) => compareText(a, b))
    for int i = 0, i < names.length, i++ {
        text v = n.attrs[names[i]]
        if v == null { v = '' }
        attrText = `${attrText} ${names[i]}="${v}"`
    }
    out = `${pad}<${n.tag}${attrText}>\n`
    for int i = 0, i < n.children.length, i++ {
        text child = dumpTree(n.children[i], indent + 1)
        out = out + child
    }
    return out
}

// Ordering for text values: `<` is numeric-only in Festina, so a
// comparator has to walk code points.
int func compareText(a:text, b:text) {
    int i = 0
    while true {
        int ca = a.charCodeAt(i)
        int cb = b.charCodeAt(i)
        if ca == null && cb == null { return 0 }
        if ca == null { return -1 }
        if cb == null { return 1 }
        if ca != cb { return ca - cb }
        i++
    }
    return 0
}
