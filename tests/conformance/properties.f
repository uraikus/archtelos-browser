// Which CSS properties this engine actually implements.
//
// tests/conformance/css-properties.txt lists every property Chromium
// reports on a computed style, with a value chosen so that an engine
// implementing the property must produce a different computed Style.
// This sets each one on an element, computes, and compares the result
// with the same element without the declaration. A property that
// changes nothing is not implemented, whatever the parser accepts.
//
//   festina run tests/conformance/properties.f [--min N] [--verbose]
//
// `--verbose` lists the properties that do nothing, which is the work
// list css-2026.md and todo.md are built from.

import ../../src/css/cascade.f
import ../../src/html/parser.f

arr[text] func blobLines(f:blob) {
    arr[text] lines = []
    int n = f.length
    int start = 0
    for int i = 0, i <= n, i++ {
        if i == n || f.byteAt(i) == 10 {
            if i > start || i < n { lines.push(f.slice(start, i)) }
            start = i + 1
        }
    }
    return lines
}

// Every field of a computed Style that something reads, in one string.
// Every field here is one something reads. `overflowHidden` was left
// out while the cascade computed it and nothing looked; the painter
// clips by it now, so it counts.
text func styleDigest(s:Style) {
    return `${s.display}|${s.color}|${s.background}|${s.fontSize}|${s.fontBold}|${s.fontItalic}`
        + `|${s.fontFamily}|${s.lineHeight}|${s.textAlign}|${s.textDecoration}|${s.inheritedDecoration}`
        + `|${s.textTransform}|${s.whiteSpace}|${s.listStyle}|${s.verticalAlign}`
        + `|${s.opacity}|${s.effectiveOpacity}|${lenKey(s.width)}|${lenKey(s.height)}`
        + `|${lenKey(s.minWidth)}|${lenKey(s.maxWidth)}|${lenKey(s.minHeight)}`
        + `|${lenKey(s.marginTop)}|${lenKey(s.marginRight)}|${lenKey(s.marginBottom)}|${lenKey(s.marginLeft)}`
        + `|${lenKey(s.paddingTop)}|${lenKey(s.paddingRight)}|${lenKey(s.paddingBottom)}|${lenKey(s.paddingLeft)}`
        + `|${s.borderTop}|${s.borderRight}|${s.borderBottom}|${s.borderLeft}`
        + `|${s.borderTopColor}|${s.borderRightColor}|${s.borderBottomColor}|${s.borderLeftColor}`
        + `|${s.borderStyle}|${s.borderRadius}|${s.borderSpacing}|${s.borderCollapse}`
        + `|${s.textIndent}|${s.letterSpacing}|${s.hidden}|${s.fontKey}`
        + `|${s.position}|${lenKey(s.top)}|${lenKey(s.right)}|${lenKey(s.bottom)}|${lenKey(s.left)}|${s.zIndex}`
        + `|${s.floatSide}|${s.clearSide}`
        + `|${lenKey(s.maxHeight)}|${s.boxSizing}|${s.captionSide}|${s.wordSpacing}`
        + `|${s.outlineWidth}|${s.outlineColor}`
        + `|${s.flexDirection}|${s.justifyContent}|${s.alignItems}|${s.alignSelf}`
        + `|${s.flexWrap}|${s.alignContent}`
        + `|${s.flexGrow}|${s.flexShrink}|${lenKey(s.flexBasis)}|${s.rowGap}|${s.columnGap}|${s.order}`
        + `|${gradientKey(s.backgroundImage)}|${s.overflowHidden}`
}

text func gradientKey(g:Gradient) {
    if !g.present { return '-' }
    arr[text] parts = []
    for int i = 0, i < g.stops.length, i++ {
        parts.push(`${g.stops[i]}@${g.posKind[i]}:${g.posVal[i]}`)
    }
    return `${g.repeating}/${g.angle}/${parts.join(',')}`
}

text func lenKey(l:Len) {
    return `${l.kind}:${l.v}`
}

text func digestFor(decl:text) {
    cascadeReset()
    Node doc = parseHtmlText(`<html><body><table><tr><td><p id="t" style="${decl}">x</p></td></tr></table></body></html>`)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    arr[Node] ps = []
    collectElements(doc, 'p', ps)
    if ps.length == 0 { return 'MISSING' }
    return styleDigest(ps[0].style)
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

blob f = 'tests/conformance/css-properties.txt'
if !f.exists() {
    log('properties: skipped -- css-properties.txt not found')
    close(0)
}

text baseline = digestFor('')
arr[text] lines = blobLines(f)
int total = 0
int implemented = 0
arr[text] inert = []

for int i = 0, i < lines.length, i++ {
    text line = lines[i]
    if line == null || line == '' { continue }
    if line.split('')[0] == '#' { continue }
    arr[text] parts = line.split('\t')
    if parts.length < 2 { continue }
    text prop = parts[0]
    text val = parts[1]
    total++
    if digestFor(`${prop}: ${val}`) != baseline { implemented++ }
    else { inert.push(prop) }
}

if verbose {
    log('  properties that change nothing:')
    for int i = 0, i < inert.length, i++ { log(`    ${inert[i]}`) }
}
log(`properties: ${implemented}/${total} CSS properties change the computed style`)
if minimum >= 0 && implemented < minimum {
    log(`properties: FAILED -- expected at least ${minimum}`)
    close(1)
}
close(0)
