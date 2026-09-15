// Every HTML element's default `display`, checked against Chromium's.
//
// tests/conformance/element-display.txt holds one row per element: the
// tag, a fragment of markup that puts it somewhere it is valid, and the
// display Chromium 141 computes for it. This runner parses each
// fragment, runs the cascade and compares.
//
//   festina run tests/conformance/elements.f [--min N] [--verbose]
//
// `--min N` fails the run when fewer than N elements match, which is
// how tests/run.sh keeps the count from regressing. A mismatch is a
// real gap in the user-agent stylesheet or in `display` parsing, and
// the verbose listing names every one.

import ../../src/css/cascade.f
import ../../src/html/parser.f

// Reading a file line by line, as html5lib.f does: a blob has
// byteAt and slice, and nothing splits one on newlines.
arr[text] func blobLines(f:blob) {
    arr[text] lines = []
    int n = f.length
    int start = 0
    for int i = 0, i <= n, i++ {
        if i == n || f.byteAt(i) == 10 {
            if i > start || i < n {
                lines.push(f.slice(start, i))
            }
            start = i + 1
        }
    }
    return lines
}

text func displayName(d:int) {
    if d == DISPLAY_NONE { return 'none' }
    if d == DISPLAY_BLOCK { return 'block' }
    if d == DISPLAY_INLINE { return 'inline' }
    if d == DISPLAY_INLINE_BLOCK { return 'inline-block' }
    if d == DISPLAY_LIST_ITEM { return 'list-item' }
    if d == DISPLAY_TABLE { return 'table' }
    if d == DISPLAY_TABLE_ROW { return 'table-row' }
    if d == DISPLAY_TABLE_CELL { return 'table-cell' }
    if d == DISPLAY_TABLE_ROW_GROUP { return 'table-row-group' }
    if d == DISPLAY_TABLE_HEADER_GROUP { return 'table-header-group' }
    if d == DISPLAY_TABLE_FOOTER_GROUP { return 'table-footer-group' }
    if d == DISPLAY_TABLE_CAPTION { return 'table-caption' }
    if d == DISPLAY_TABLE_COLUMN { return 'table-column' }
    if d == DISPLAY_TABLE_COLUMN_GROUP { return 'table-column-group' }
    if d == DISPLAY_RUBY { return 'ruby' }
    if d == DISPLAY_CONTENTS { return 'contents' }
    if d == DISPLAY_FLEX { return 'flex' }
    return `?${d}`
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

blob f = 'tests/conformance/element-display.txt'
if !f.exists() { f = `${environment.ARCHTELOS_ROOT}/tests/conformance/element-display.txt` }
if !f.exists() {
    log('elements: skipped -- element-display.txt not found')
    close(0)
}

arr[text] lines = blobLines(f)
int total = 0
int passed = 0
arr[text] misses = []

for int i = 0, i < lines.length, i++ {
    text line = lines[i]
    if line == null || line == '' { continue }
    if line.split('')[0] == '#' { continue }
    arr[text] parts = line.split('\t')
    if parts.length < 3 { continue }
    text tag = parts[0]
    text markup = parts[1]
    text want = parts[2]
    total++
    cascadeReset()
    Node doc = parseHtmlText(markup)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    arr[Node] found = []
    collectElements(doc, tag, found)
    if found.length == 0 {
        misses.push(`${tag}: no element in the tree (expected ${want})`)
        continue
    }
    text got = displayName(found[0].style.display)
    if got == want { passed++ }
    else { misses.push(`${tag}: expected ${want}, got ${got}`) }
}

if verbose {
    for int i = 0, i < misses.length, i++ { log(`  ${misses[i]}`) }
}
log(`elements: ${passed}/${total} default displays match Chromium`)
if minimum >= 0 && passed < minimum {
    log(`elements: FAILED -- expected at least ${minimum}`)
    close(1)
}
