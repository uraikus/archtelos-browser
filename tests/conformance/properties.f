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

// Every field of a computed Style that something reads, one per entry.
// Every field here is one something reads. `overflowHidden` was left
// out while the cascade computed it and nothing looked; the painter
// clips by it now, so it counts.
//
// This is a list rather than a joined string because a value can
// contain whatever character the join would use -- `fontKey` holds a
// pipe -- and splitting it back would then misalign every field after
// it against its name.
arr[text] func styleDigestFields(s:Style) {
    return [`${s.display}`, `${s.color}`, `${s.background}`, `${s.fontSize}`, 
        `${s.fontBold}`, `${s.fontItalic}`, `${s.fontFamily}`, 
        `${s.lineHeight}`, `${s.textAlign}`, `${s.textDecoration}`, 
        `${s.inheritedDecoration}`, `${s.textTransform}`, 
        `${s.whiteSpaceCollapse}`, `${s.textWrapMode}`, 
        `${s.textAlignLast}`, `${s.wordBreaking}`, 
        `${s.tabSize}`, `${s.tabSizePx}`, 
        `${s.listStyle}`, `${s.verticalAlign}`, `${s.opacity}`, 
        `${s.effectiveOpacity}`, `${lenKey(s.width)}`, `${lenKey(s.height)}`, 
        `${lenKey(s.minWidth)}`, `${lenKey(s.maxWidth)}`, 
        `${lenKey(s.minHeight)}`, `${lenKey(s.marginTop)}`, 
        `${lenKey(s.marginRight)}`, `${lenKey(s.marginBottom)}`, 
        `${lenKey(s.marginLeft)}`, `${lenKey(s.paddingTop)}`, 
        `${lenKey(s.paddingRight)}`, `${lenKey(s.paddingBottom)}`, 
        `${lenKey(s.paddingLeft)}`, `${s.borderTop}`, `${s.borderRight}`, 
        `${s.borderBottom}`, `${s.borderLeft}`, `${s.borderTopColor}`, 
        `${s.borderRightColor}`, `${s.borderBottomColor}`, 
        `${s.borderLeftColor}`, `${s.borderStyle}`, `${s.borderRadius}`, `${s.radiusTopLeft}`,
        `${s.radiusTopRight}`, `${s.radiusBottomRight}`, `${s.radiusBottomLeft}`, 
        `${s.borderSpacing}`, `${s.borderCollapse}`, `${s.borderTopStyle}`, 
        `${s.borderRightStyle}`, `${s.borderBottomStyle}`, 
        `${s.borderLeftStyle}`, `${s.textIndent}`, `${s.letterSpacing}`, 
        `${s.hidden}`, `${s.fontKey}`, `${s.position}`, `${lenKey(s.top)}`, 
        `${lenKey(s.right)}`, `${lenKey(s.bottom)}`, `${lenKey(s.left)}`, 
        `${s.zIndex}`, `${s.floatSide}`, `${s.clearSide}`, 
        `${lenKey(s.maxHeight)}`, `${s.boxSizing}`, `${s.captionSide}`, 
        `${s.wordSpacing}`, `${s.outlineWidth}`, `${s.outlineColor}`, 
        `${s.flexDirection}`, `${s.justifyContent}`, `${s.alignItems}`, 
        `${s.alignSelf}`, `${s.flexWrap}`, `${s.alignContent}`, 
        `${s.flexGrow}`, `${s.flexShrink}`, `${lenKey(s.flexBasis)}`, 
        `${s.rowGap}`, `${s.columnGap}`, `${s.order}`, 
        `${gradientKey(s.backgroundImage)}`, `${s.overflowHidden}`, 
        `${s.backgroundUrl}`, `${s.backgroundRepeatX}`, 
        `${s.backgroundRepeatY}`, `${lenKey(s.backgroundPosX)}`, 
        `${lenKey(s.backgroundPosY)}`, `${s.backgroundSizeKind}`, 
        `${lenKey(s.backgroundSizeW)}`, `${lenKey(s.backgroundSizeH)}`, 
        `${s.backgroundClip}`, `${s.backgroundOrigin}`, `${s.objectFit}`, 
        `${lenKey(s.objectPosX)}`, `${lenKey(s.objectPosY)}`,
        `${shadowKey(s.shadows)}`]
}

text func styleDigest(s:Style) {
    return styleDigestFields(s).join('\u0001')
}

// The names of the digest's fields, in the order `styleDigest` writes
// them. Two lists that must agree is a hazard, so they are checked
// against each other at startup rather than trusted: a field added to
// one and not the other stops the instrument instead of silently
// mislabelling every property after it.
arr[text] func styleDigestFieldNames() {
    return ['display', 'color', 'background', 'fontSize', 'fontBold', 
        'fontItalic', 'fontFamily', 'lineHeight', 'textAlign', 
        'textDecoration', 'inheritedDecoration', 'textTransform', 
        'whiteSpaceCollapse', 'textWrapMode', 'textAlignLast', 
        'wordBreaking', 'tabSize', 'tabSizePx', 
        'listStyle', 'verticalAlign', 'opacity', 
        'effectiveOpacity', 'width', 'height', 'minWidth', 'maxWidth', 
        'minHeight', 'marginTop', 'marginRight', 'marginBottom', 
        'marginLeft', 'paddingTop', 'paddingRight', 'paddingBottom', 
        'paddingLeft', 'borderTop', 'borderRight', 'borderBottom', 
        'borderLeft', 'borderTopColor', 'borderRightColor', 
        'borderBottomColor', 'borderLeftColor', 'borderStyle', 
        'borderRadius', 'radiusTopLeft', 'radiusTopRight', 'radiusBottomRight',
        'radiusBottomLeft', 'borderSpacing', 'borderCollapse', 
        'borderTopStyle', 'borderRightStyle', 'borderBottomStyle', 
        'borderLeftStyle', 'textIndent', 'letterSpacing', 'hidden', 
        'fontKey', 'position', 'top', 'right', 'bottom', 'left', 'zIndex', 
        'floatSide', 'clearSide', 'maxHeight', 'boxSizing', 'captionSide', 
        'wordSpacing', 'outlineWidth', 'outlineColor', 'flexDirection', 
        'justifyContent', 'alignItems', 'alignSelf', 'flexWrap', 
        'alignContent', 'flexGrow', 'flexShrink', 'flexBasis', 'rowGap', 
        'columnGap', 'order', 'backgroundImage', 'overflowHidden', 
        'backgroundUrl', 'backgroundRepeatX', 'backgroundRepeatY', 
        'backgroundPosX', 'backgroundPosY', 'backgroundSizeKind', 
        'backgroundSizeW', 'backgroundSizeH', 'backgroundClip', 
        'backgroundOrigin', 'objectFit', 'objectPosX', 'objectPosY', 'shadows']
}

text func shadowKey(list:arr[Shadow]) {
    if list.length == 0 { return '-' }
    arr[text] parts = []
    for int i = 0, i < list.length, i++ {
        parts.push(`${list[i].dx},${list[i].dy},${list[i].blur},${list[i].spread},${list[i].color},${list[i].inset}`)
    }
    return parts.join(';')
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

arr[text] func digestFieldsFor(decl:text) {
    cascadeReset()
    Node doc = parseHtmlText(`<html><body><table><tr><td><p id="t" style="${decl}">x</p></td></tr></table></body></html>`)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    arr[Node] ps = []
    collectElements(doc, 'p', ps)
    arr[text] missing = ['MISSING']
    if ps.length == 0 { return missing }
    return styleDigestFields(ps[0].style)
}

bool verbose = false
bool showFields = false
int minimum = -1
for int i = 1, i < argv.length, i++ {
    text arg = argv[i]
    if arg == '--verbose' { verbose = true }
    else if arg == '--fields' { showFields = true }
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

arr[text] baseFields = digestFieldsFor('')
text baseline = baseFields.join('\u0001')
arr[text] fieldNames = styleDigestFieldNames()
if baseFields.length != fieldNames.length {
    log(`properties: FAILED -- styleDigest writes ${baseFields.length} fields and `
        + `styleDigestFieldNames lists ${fieldNames.length}; they must agree`)
    close(1)
}
arr[text] lines = blobLines(f)
int total = 0
int gradeable = 0
int implemented = 0
arr[text] inert = []
arr[text] ungradeable = []

for int i = 0, i < lines.length, i++ {
    text line = lines[i]
    if line == null || line == '' { continue }
    if line.split('')[0] == '#' { continue }
    arr[text] parts = line.split('\t')
    if parts.length < 2 { continue }
    text prop = parts[0]
    text val = parts[1]
    total++
    // A row that cannot show a difference is not a measurement of this
    // engine at all; it is a gap in the instrument. Counted in the
    // denominator it reads as a property this engine has not
    // implemented, and listed among the properties that "change
    // nothing" it hides in the work list, so it is reported separately.
    //
    // Two shapes of it: a CSS-wide keyword, which computes to the
    // initial value by definition, and a row whose third column gives
    // the reason Chromium itself cannot tell the value from the initial
    // one on this probe.
    if val == 'initial' || val == 'inherit' || val == 'unset' || val == 'revert' {
        ungradeable.push(`${prop} (a CSS-wide keyword computes to the initial value)`)
        continue
    }
    if parts.length >= 3 && parts[2] != '' {
        ungradeable.push(`${prop} (${parts[2]})`)
        continue
    }
    gradeable++
    // A row may carry declarations beyond the property under test,
    // because some properties do nothing without one: a border width
    // computes to zero unless that side has a style. Those extras are
    // context, and the row is graded against a baseline that already
    // has them -- otherwise the context alone moves the digest and the
    // row registers whether or not the property itself is implemented.
    arr[text] halves = val.split(';')
    text own = halves[0]
    text context = ''
    for int hi = 1, hi < halves.length, hi++ {
        if halves[hi] == '' { continue }
        context = context + halves[hi] + ';'
    }
    arr[text] rowBaseFields = baseFields
    if context != '' { rowBaseFields = digestFieldsFor(context) }
    text rowBaseline = rowBaseFields.join('\u0001')
    arr[text] gotFields = digestFieldsFor(`${prop}: ${own};${context}`)
    if gotFields.join('\u0001') == rowBaseline { inert.push(prop)  continue }
    implemented++
    if showFields {
        // Which fields moved, not just that something did. A property
        // that registers only through a field belonging to a different
        // property is being scored for a side effect: `border-top-style`
        // used to move nothing but the border's *width*, because
        // declaring a style gives that side the medium width. The
        // instrument cannot judge which field means which property, so
        // it prints the mapping and leaves the reading to a person.
        arr[text] moved = []
        for int k = 0, k < fieldNames.length && k < gotFields.length, k++ {
            if gotFields[k] != rowBaseFields[k] { moved.push(fieldNames[k]) }
        }
        log(`    ${prop} -> ${moved.join(', ')}`)
    }
}

if verbose {
    log('  properties that are gradeable and change nothing -- the work list:')
    for int i = 0, i < inert.length, i++ { log(`    ${inert[i]}`) }
    log('  rows whose value cannot show a difference -- the instrument work list:')
    for int i = 0, i < ungradeable.length, i++ { log(`    ${ungradeable[i]}`) }
}
log(`properties: ${implemented}/${gradeable} CSS properties change the computed style`)
if ungradeable.length > 0 {
    log(`properties: ${ungradeable.length} of ${total} rows carry a value that could never show a difference (--verbose lists them)`)
}
if minimum >= 0 && implemented < minimum {
    log(`properties: FAILED -- expected at least ${minimum}`)
    close(1)
}
close(0)
