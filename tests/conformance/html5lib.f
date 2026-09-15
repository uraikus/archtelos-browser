// The WHATWG HTML standard's own tree-construction conformance suite.
//
// Reads the html5lib-format `.dat` files maintained by web-platform-tests
// (html/syntax/parsing/resources), parses each `#data` section with this
// browser's parser, serializes the result in html5lib's format and
// compares it with the `#document` section.
//
//   WPT_HTML_TESTS=/path/to/wpt/html/syntax/parsing/resources \
//       festina run tests/conformance/html5lib.f [--min N] [--verbose] [--file NAME]
//
// `--min N` fails the run when fewer than N tests pass, which is how
// tests/run.sh keeps the conformance number from regressing.
//
// Three kinds of test are skipped and counted separately, because this
// browser does not implement what they test: `#document-fragment`
// (innerHTML parsing), `#script-on` (script execution changes the tree),
// and any test whose input contains a NUL byte, which a Festina `text`
// cannot hold at all (FINDINGS.md, "no NUL in text").

import ../../src/html/parser.f
import ../../src/dom/serialize.f

int totalCases = 0
int casesPassed = 0
int casesFailed = 0
int skipFragment = 0
int skipScript = 0
int skipNul = 0
arr[text] failureReports = []
bool verbose = false
int maxReports = 12
// `/\n/` matches the letter n, not a newline (FINDINGS.md, "regex
// escapes"), so the pattern is built from the character itself.
regex newlineRe = regex(10.toChar(), 'g')

// Per-file tallies, for the summary table.
arr[text] fileNames = []
arr[int] filePassed = []
arr[int] fileTotal = []

// ---- reading a .dat file -------------------------------------------
//
// Lines come out of the blob's own bytes rather than through
// `text.split`, so that UTF-8 survives in both the input and the
// expectation: blob.slice hands back the raw bytes as text, where the
// tokenizer's own ASCII-safe pre-pass would have rewritten every
// non-ASCII character as a numeric reference.

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

bool func blobHasNul(f:blob) {
    int n = f.length
    for int i = 0, i < n, i++ {
        if f.byteAt(i) == 0 { return true }
    }
    return false
}

// Joins accumulated section lines, dropping the blank line that
// separates one test from the next.
text func joinSection(lines:arr[text]) {
    int end = lines.length
    while end > 0 && lines[end - 1] == '' { end-- }
    arr[text] kept = []
    for int i = 0, i < end, i++ { kept.push(lines[i]) }
    return kept.join('\n')
}

text func truncate(t:text, limit:int) {
    if t == null { return '' }
    if t.length <= limit { return t }
    arr[text] cps = t.split('')
    text out = ''
    for int i = 0, i < limit, i++ { out = out + cps[i] }
    return out + '...'
}

// ---- one test case --------------------------------------------------

void func runCase(fileName:text, index:int, data:text, expected:text, isFragment:bool, scriptOn:bool) {
    if isFragment {
        skipFragment++
        return
    }
    if scriptOn {
        skipScript++
        return
    }
    totalCases++
    nodeRegistryReset()
    Node doc = parseHtmlText(data)
    text actual = serializeDocument(doc)
    if actual == expected {
        casesPassed++
        return
    }
    casesFailed++
    if failureReports.length < maxReports {
        failureReports.push(`${fileName} #${index}\n  input:    ${truncate(data, 90)}\n  expected: ${truncate(expected.replace(newlineRe, ' / '), 200)}\n  actual:   ${truncate(actual.replace(newlineRe, ' / '), 200)}`)
    }
}

// ---- one .dat file ---------------------------------------------------

const int SECTION_NONE = 0
const int SECTION_DATA = 1
const int SECTION_ERRORS = 2
const int SECTION_DOCUMENT = 3
const int SECTION_OTHER = 4

void func runFile(dir:text, name:text) {
    blob f = `${dir}/${name}`
    if !f.exists() { return }
    if blobHasNul(f) {
        // The whole file is skipped: a NUL in any test's input cannot
        // round-trip through `text`, and these files exist to test
        // exactly that byte.
        int count = 0
        arr[text] probe = blobLines(f)
        for int i = 0, i < probe.length, i++ {
            if probe[i] == '#data' { count++ }
        }
        skipNul = skipNul + count
        return
    }
    arr[text] lines = blobLines(f)
    int section = SECTION_NONE
    arr[text] dataLines = []
    arr[text] docLines = []
    bool isFragment = false
    bool scriptOn = false
    bool haveCase = false
    int index = 0
    int startPassed = casesPassed
    int startTotal = totalCases

    for int i = 0, i <= lines.length, i++ {
        text line = i < lines.length ? lines[i] : '#data'
        bool isHeader = line.length > 0 && line.charCodeAt(0) == CH_HASH
        text header = isHeader ? line : ''
        if header == '#data' {
            if haveCase {
                runCase(name, index, joinSection(dataLines), joinSection(docLines), isFragment, scriptOn)
                index++
            }
            if i >= lines.length { break }
            haveCase = true
            dataLines = []
            docLines = []
            isFragment = false
            scriptOn = false
            section = SECTION_DATA
            continue
        }
        if header == '#errors' || header == '#new-errors' {
            section = SECTION_ERRORS
            continue
        }
        if header == '#document' {
            section = SECTION_DOCUMENT
            continue
        }
        if header == '#document-fragment' {
            isFragment = true
            section = SECTION_OTHER
            continue
        }
        if header == '#script-on' {
            scriptOn = true
            section = SECTION_OTHER
            continue
        }
        if header == '#script-off' || header == '#options' {
            section = SECTION_OTHER
            continue
        }
        if section == SECTION_DATA { dataLines.push(line) }
        else if section == SECTION_DOCUMENT { docLines.push(line) }
    }
    fileNames.push(name)
    filePassed.push(casesPassed - startPassed)
    fileTotal.push(totalCases - startTotal)
}

// ---- entry point -----------------------------------------------------

text onlyFile = ''
int minimum = -1

for int i = 1, i < argv.length, i++ {
    text arg = argv[i]
    if arg == '--verbose' { verbose = true }
    else if arg == '--min' && i + 1 < argv.length {
        int m = argv[i + 1].toInt()
        if m != null { minimum = m }
        i++
    } else if arg == '--file' && i + 1 < argv.length {
        onlyFile = argv[i + 1]
        i++
    }
}

text dir = environment.WPT_HTML_TESTS
if dir == null || dir == '' {
    log('conformance: skipped -- set WPT_HTML_TESTS to the web-platform-tests')
    log('             html/syntax/parsing/resources directory (see CLAUDE.md)')
    close(0)
}

arr[text] entries = ls(dir)
entries.sort(int (a:text, b:text) => compareText(a, b))
int files = 0
for int i = 0, i < entries.length, i++ {
    text name = entries[i]
    ascii a = name.toAscii()
    if a == null || !asciiEndsWith(a, '.dat') { continue }
    if onlyFile != '' && name != onlyFile { continue }
    files++
    runFile(dir, name)
}

if files == 0 {
    log(`conformance: no .dat files found in ${dir}`)
    close(1)
}

if verbose {
    for int i = 0, i < fileNames.length, i++ {
        if fileTotal[i] == 0 { continue }
        if filePassed[i] == fileTotal[i] { continue }
        log(`  ${fileNames[i]}: ${filePassed[i]}/${fileTotal[i]}`)
    }
    for int i = 0, i < failureReports.length, i++ {
        log(failureReports[i])
    }
}

int skippedTotal = skipFragment + skipScript + skipNul
log(`conformance: ${casesPassed}/${totalCases} WHATWG tree-construction tests passed (${files} files, ${skippedTotal} skipped: ${skipFragment} fragment, ${skipScript} scripted, ${skipNul} NUL-bearing)`)
if minimum >= 0 && casesPassed < minimum {
    log(`conformance: REGRESSION -- ${casesPassed} passed, at least ${minimum} required`)
    close(1)
}
