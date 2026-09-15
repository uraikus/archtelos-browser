// Which CSS selectors this engine matches the way Chromium does.
//
// tests/conformance/css-selectors.txt lists selectors; this runs each
// against tests/fixtures/selectors.html, collects the ids it matches,
// and compares that set with the one Chromium's querySelectorAll
// produced for the same selector on the same document. A selector
// counts only when the two sets are identical: parsing it, or matching
// some of the right elements, is not implementing it.
//
//   festina run tests/conformance/selectors.f [--min N] [--verbose]
//
// The expected sets come from tests/conformance/chromium-selectors.txt,
// which tests/run.sh regenerates with `tests/chromium.py selectors`
// when Chromium is present and otherwise takes as checked in.

import ../../src/css/cascade.f
import ../../src/html/parser.f

arr[text] func fileLines(f:blob) {
    arr[text] lines = []
    int n = f.length
    int start = 0
    for int i = 0, i <= n, i++ {
        if i == n || f.byteAt(i) == 10 {
            if i > start { lines.push(f.slice(start, i)) }
            start = i + 1
        }
    }
    return lines
}

// Every element id the selector matches, in document order, space
// separated -- the same shape the Chromium side prints.
void func collectAll(n:Node, out:arr[Node]) {
    if n.kind == NODE_ELEMENT { out.push(n) }
    for int i = 0, i < n.children.length, i++ { collectAll(n.children[i], out) }
}

text func idsMatching(doc:Node, selectorText:text) {
    arr[Selector] sels = parseSelectorList(selectorText.toAscii())
    if sels.length == 0 { return 'INVALID' }
    arr[Node] all = []
    collectAll(doc, all)
    arr[text] hits = []
    for int i = 0, i < all.length, i++ {
        bool matched = false
        for int j = 0, j < sels.length, j++ {
            if selectorMatchesNode(all[i], sels[j]) { matched = true  break }
        }
        if matched {
            text id = getAttr(all[i], 'id')
            hits.push(id == null || id == '' ? '?' : id)
        }
    }
    return hits.join(' ')
}

bool verbose = false
int minimum = -1
for int i = 1, i < argv.length, i++ {
    text arg = argv[i]
    if arg == '--verbose' { verbose = true }
    else if arg == '--min' && i + 1 < argv.length {
        int m = argv[i + 1].toInt()
        if m != null { minimum = m }
        i++
    }
}

blob fixture = 'tests/fixtures/selectors.html'
blob expected = 'tests/conformance/chromium-selectors.txt'
if !fixture.exists() || !expected.exists() {
    log('selectors: skipped -- fixture or expectations not found')
    close(0)
}

cascadeReset()
Node doc = parseHtmlBlob(fixture)

arr[text] lines = fileLines(expected)
int total = 0
int agreed = 0
arr[text] wrong = []
for int i = 0, i < lines.length, i++ {
    text line = lines[i]
    if line == null || line == '' { continue }
    arr[text] parts = line.split('\t')
    if parts.length < 1 { continue }
    text sel = parts[0]
    text want = parts.length > 1 ? parts[1] : ''
    if want == null { want = '' }
    // A selector that matches nothing in the fixture proves nothing:
    // an engine that drops it agrees with one that implements it. That
    // is how `:has()` first counted as working here.
    if want == '' {
        log(`selectors: FAILED -- ${sel} matches nothing in the fixture, so it cannot measure anything`)
        close(1)
    }
    total++
    text got = idsMatching(doc, sel)
    if got == null { got = '' }
    if got == want { agreed++ }
    else { wrong.push(`${sel}\n      chromium: ${want}\n      this one: ${got}`) }
}

if verbose {
    log('  selectors that disagree with Chromium:')
    for int i = 0, i < wrong.length, i++ { log(`    ${wrong[i]}`) }
}
log(`selectors: ${agreed}/${total} CSS selectors match the same elements as Chromium`)
if minimum >= 0 && agreed < minimum {
    log(`selectors: FAILED -- expected at least ${minimum}`)
    close(1)
}
