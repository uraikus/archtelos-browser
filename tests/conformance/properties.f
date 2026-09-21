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
        `${s.inheritedDecoration}`, `${s.decorationColor}`, 
        `${s.decorationStyle}`, `${s.decorationThickness}`, 
        `${s.underlineOffset}`, `${shadowKey(s.textShadows)}`, 
        `${s.directionRtl}`, `${s.unicodeBidi}`, `${s.emphasisMark}`, `${s.emphasisColor}`, `${s.emphasisUnder}`, 
        `${s.underlinePosUnder}`, `${s.textTransform}`, 
        `${s.whiteSpaceCollapse}`, `${s.textWrapMode}`, 
        `${s.textAlignLast}`, `${s.wordBreaking}`, 
        `${s.tabSize}`, `${s.tabSizePx}`, `${s.hyphensNone}`, `${s.hyphenChar}`, 
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
        `${s.borderLeftColor}`, `${s.borderStyle}`, `${s.borderRadius}`, `${lenKey(s.radiusTopLeftX)}`, `${lenKey(s.radiusTopLeftY)}`,
        `${lenKey(s.radiusTopRightX)}`, `${lenKey(s.radiusTopRightY)}`, `${lenKey(s.radiusBottomRightX)}`, `${lenKey(s.radiusBottomRightY)}`, `${lenKey(s.radiusBottomLeftX)}`, `${lenKey(s.radiusBottomLeftY)}`, 
        `${cornerKAt(s.cornerShapes, 0)}`, `${cornerKAt(s.cornerShapes, 1)}`, `${cornerKAt(s.cornerShapes, 2)}`, `${cornerKAt(s.cornerShapes, 3)}`, 
        `${anchorInfoOf(s.anchorInfo).name}`, `${anchorInfoOf(s.anchorInfo).anchor}`, `${anchorInfoOf(s.anchorInfo).area}`, `${anchorInfoOf(s.anchorInfo).fallbacks}`, `${anchorInfoOf(s.anchorInfo).tryOrder}`, `${anchorInfoOf(s.anchorInfo).visibility}`, `${anchorInfoOf(s.anchorInfo).scope}`, `${motionKeyPath(motionInfoOf(motionIndexOf(s)))}`, `${lenKey(motionInfoOf(motionIndexOf(s)).distance)}`, `${motionInfoOf(motionIndexOf(s)).rotateMode}|${motionInfoOf(motionIndexOf(s)).rotateAngle}`, `${motionInfoOf(motionIndexOf(s)).anchorAuto ? 1 : 0}|${lenKey(motionInfoOf(motionIndexOf(s)).anchorX)}|${lenKey(motionInfoOf(motionIndexOf(s)).anchorY)}`, `${motionInfoOf(motionIndexOf(s)).posNormal ? 1 : 0}|${lenKey(motionInfoOf(motionIndexOf(s)).posX)}|${lenKey(motionInfoOf(motionIndexOf(s)).posY)}`, `${clipMarginPacked(s)}`, `${textBoxPacked(s)}`, `${decorationIsClone(s) ? 1 : 0}`, `${overscrollPacked(s)}`, 
        `${s.borderSpacing}`, `${s.borderCollapse}`, `${s.borderTopStyle}`, 
        `${s.borderRightStyle}`, `${s.borderBottomStyle}`, 
        `${s.borderLeftStyle}`, `${s.textIndent}`, `${s.letterSpacing}`, 
        `${s.hidden}`, `${s.fontKey}`, `${s.position}`, `${lenKey(s.top)}`, 
        `${lenKey(s.right)}`, `${lenKey(s.bottom)}`, `${lenKey(s.left)}`, 
        `${s.zIndex}`, `${s.floatSide}`, `${s.clearSide}`, 
        `${lenKey(s.maxHeight)}`, `${s.boxSizing}`, `${s.captionSide}`, 
        `${s.aspectW}/${s.aspectH}/${s.hasAspectRatio}/${s.aspectPrefersNatural}`, 
        `${s.wordSpacing}`, `${s.outlineWidth}`, `${s.outlineStyle}`, `${s.outlineColor}`, 
        `${s.outlineOffset}`, `${s.tableLayoutFixed}`, `${s.emptyCellsHide}`, 
        `${s.borderImageUrl}`, `${lenKey(s.borderImageSliceTop)}`, 
        `${lenKey(s.borderImageSliceRight)}`, `${lenKey(s.borderImageSliceBottom)}`, 
        `${lenKey(s.borderImageSliceLeft)}`, `${s.borderImageFill}`, 
        `${s.borderImageWidthTop}`, `${s.borderImageWidthRight}`, 
        `${s.borderImageWidthBottom}`, `${s.borderImageWidthLeft}`, 
        `${s.borderImageOutset}`, `${s.borderImageRepeat}`, `${s.borderImageRepeatY}`, 
        `${s.columnCount}`, `${lenKey(s.columnWidth)}`, 
        `${s.columnRuleWidth}`, `${s.columnRuleStyle}`, `${s.columnRuleColor}`, 
        `${s.columnSpanAll}`, `${s.columnFillAuto}`, 
        `${s.breakBefore}`, `${s.breakAfter}`, `${s.breakInsideAvoid}`, `${s.pageName}`, 
        `${s.scrollbarWidth}`, `${s.scrollbarGutter}`, `${s.scrollbarThumb}`, `${s.scrollbarTrack}`, 
        `${s.snapX}`, `${s.snapY}`, `${s.snapStrict}`, `${s.snapAlignBlock}`, `${s.snapAlignInline}`, 
        `${lenKey(s.scrollPaddingTop)}`, `${lenKey(s.scrollPaddingRight)}`, `${lenKey(s.scrollPaddingBottom)}`, `${lenKey(s.scrollPaddingLeft)}`, 
        `${lenKey(s.scrollMarginTop)}`, `${lenKey(s.scrollMarginRight)}`, `${lenKey(s.scrollMarginBottom)}`, `${lenKey(s.scrollMarginLeft)}`, 
        `${s.orphans}`, `${s.widows}`, 
        `${clipKey(s.clipShape)}`, `${clipKey(s.clipRect)}`, 
        `${clipKey(s.shapeOutside)}`, `${s.shapeMargin}`, 
        `${trackKey(s.gridCols)}`, `${trackKey(s.gridRows)}`, `${s.gridColsSubgrid}`, `${s.gridRowsSubgrid}`, 
        `${s.gridAreaCols}:${s.gridAreaNames.join(',')}`, 
        `${trackKey(s.gridAutoCols)}`, `${trackKey(s.gridAutoRows)}`, 
        `${s.gridAutoFlowColumn}`, `${lineKey(s.gridColStart)}`, 
        `${lineKey(s.gridColEnd)}`, `${lineKey(s.gridRowStart)}`, 
        `${lineKey(s.gridRowEnd)}`, `${s.justifyItems}`, `${s.justifySelf}`, 
        `${s.textOverflowEllipsis}`, `${s.pointerEvents}`, 
        `${s.containInlineSize}`, `${s.containBlockSize}`, `${s.containLayout}`, `${s.containPaint}`, 
        `${s.containStyle}`, `${s.contentHidden}`, 
        `${lenKey(s.intrinsicWidth)}`, `${lenKey(s.intrinsicHeight)}`, 
        `${transformKey(s.transforms)}`, `${s.transformBoxContent}`, `${s.appearanceAuto}`, `${s.fieldSizingContent}`, `${s.accentColor}`, `${lenKey(s.transformOriginX)}`, 
        `${lenKey(s.transformOriginY)}`, 
        `${s.listInside}`, `${s.listImageUrl}`, `${s.contentUrl}`, `${s.backgroundFixed}`, 
        `${s.flexDirection}`, `${s.justifyContent}`, `${s.alignItems}`, 
        `${s.alignSelf}`, `${s.flexWrap}`, `${s.alignContent}`, 
        `${s.flexGrow}`, `${s.flexShrink}`, `${lenKey(s.flexBasis)}`, 
        `${s.rowGap}`, `${s.columnGap}`, `${s.order}`, 
        `${gradientKey(s.backgroundImage)}`, `${s.overflowHidden}`, `${s.overflowX}`, `${s.overflowY}`, 
        `${s.backgroundUrl}`, `${s.backgroundRepeatX}`, 
        `${s.backgroundRepeatY}`, `${lenKey(s.backgroundPosX)}`, 
        `${lenKey(s.backgroundPosY)}`, `${s.backgroundSizeKind}`, 
        `${lenKey(s.backgroundSizeW)}`, `${lenKey(s.backgroundSizeH)}`, 
        `${s.backgroundClip}`, `${s.backgroundOrigin}`, `${s.objectFit}`, 
        `${lenKey(s.objectPosX)}`, `${lenKey(s.objectPosY)}`,
        `${s.objectViewBox.kind}:${lenKey(s.objectViewBox.t)}:${lenKey(s.objectViewBox.r)}:${lenKey(s.objectViewBox.b)}:${lenKey(s.objectViewBox.l)}`,
        `${shadowKey(s.shadows)}`,
        `${s.counterReset}`, `${s.counterIncrement}`, `${s.counterSet}`, `${s.quotes}`,
        `${s.colorSchemeDark}`, `${s.containerType}`, `${s.containerName}`,
        `${initialLetterPacked(s)}`, `${baselineSourceOf(s)}`, `${resizeOf(s)}`, `${textWrapStyleOf(s)}`]
}

text func motionKeyPath(mi:MotionInfo) {
    if mi.pathKind == MPATH_NONE { return '' }
    if mi.pathKind == MPATH_RAY { return `ray ${mi.rayAngle} ${mi.raySize}` }
    if mi.pathKind == MPATH_PATH { return `path ${mi.pathData}` }
    ClipShape sh = mi.shape
    text pts = ''
    for int i = 0, i < sh.pointsX.length, i++ {
        pts = pts + `${lenKey(sh.pointsX[i])},${lenKey(sh.pointsY[i])};`
    }
    return `shape ${sh.kind} ${lenKey(sh.centreX)} ${lenKey(sh.centreY)} `
        + `${lenKey(sh.radiusX)} ${lenKey(sh.radiusY)} ${pts}`
}

text func styleDigest(s:Style) {
    return styleDigestFields(s).join('\u0001')
}

// The names of the digest's fields, in the order `styleDigest` writes
// them. Two lists that must agree is a hazard, so they are checked
// against each other at startup rather than trusted: a field added to
// one and not the other stops the instrument instead of silently
// mislabelling every property after it.
// The digest a pseudo-element row is graded on has one field more than
// an element's, so the names do too.
arr[text] func pseudoFieldNames() {
    arr[text] names = styleDigestFieldNames()
    names.push('content')
    return names
}

arr[text] func styleDigestFieldNames() {
    return ['display', 'color', 'background', 'fontSize', 'fontBold', 
        'fontItalic', 'fontFamily', 'lineHeight', 'textAlign', 
        'textDecoration', 'inheritedDecoration', 'decorationColor', 
        'decorationStyle', 'decorationThickness', 'underlineOffset', 
        'textShadows', 'directionRtl', 'unicodeBidi', 'emphasisMark', 'emphasisColor', 
        'emphasisUnder', 'underlinePosUnder', 'textTransform', 
        'whiteSpaceCollapse', 'textWrapMode', 'textAlignLast', 
        'wordBreaking', 'tabSize', 'tabSizePx', 'hyphensNone', 'hyphenChar', 
        'listStyle', 'verticalAlign', 'opacity', 
        'effectiveOpacity', 'width', 'height', 'minWidth', 'maxWidth', 
        'minHeight', 'marginTop', 'marginRight', 'marginBottom', 
        'marginLeft', 'paddingTop', 'paddingRight', 'paddingBottom', 
        'paddingLeft', 'borderTop', 'borderRight', 'borderBottom', 
        'borderLeft', 'borderTopColor', 'borderRightColor', 
        'borderBottomColor', 'borderLeftColor', 'borderStyle', 
        'borderRadius', 'radiusTopLeftX', 'radiusTopLeftY', 'radiusTopRightX', 'radiusTopRightY',
        'radiusBottomRightX', 'radiusBottomRightY', 'radiusBottomLeftX', 'radiusBottomLeftY',
        'cornerTopLeftShape', 'cornerTopRightShape', 'cornerBottomRightShape', 'cornerBottomLeftShape',
        'anchorName', 'positionAnchor', 'positionArea', 'positionTryFallbacks', 'positionTryOrder', 'positionVisibility', 'anchorScope',
        'offsetPath', 'offsetDistance', 'offsetRotate', 'offsetAnchor', 'offsetPosition', 'overflowClipMargin', 'textBox', 'boxDecorationBreak', 'overscrollBehavior',
        'borderSpacing', 'borderCollapse', 
        'borderTopStyle', 'borderRightStyle', 'borderBottomStyle', 
        'borderLeftStyle', 'textIndent', 'letterSpacing', 'hidden', 
        'fontKey', 'position', 'top', 'right', 'bottom', 'left', 'zIndex', 
        'floatSide', 'clearSide', 'maxHeight', 'boxSizing', 'captionSide',
        'aspectRatio', 
        'wordSpacing', 'outlineWidth', 'outlineStyle', 'outlineColor', 'outlineOffset', 
        'tableLayoutFixed', 'emptyCellsHide', 'borderImageUrl', 'borderImageSliceTop', 'borderImageSliceRight', 
        'borderImageSliceBottom', 'borderImageSliceLeft', 'borderImageFill', 
        'borderImageWidthTop', 'borderImageWidthRight', 'borderImageWidthBottom', 
        'borderImageWidthLeft', 'borderImageOutset', 'borderImageRepeat', 'borderImageRepeatY', 
        'columnCount', 'columnWidth', 'columnRuleWidth', 
        'columnRuleStyle', 'columnRuleColor', 'columnSpanAll', 'columnFillAuto', 
        'breakBefore', 'breakAfter', 'breakInsideAvoid', 'pageName', 
        'scrollbarWidth', 'scrollbarGutter', 'scrollbarThumb', 'scrollbarTrack', 
        'snapX', 'snapY', 'snapStrict', 'snapAlignBlock', 'snapAlignInline', 
        'scrollPaddingTop', 'scrollPaddingRight', 'scrollPaddingBottom', 'scrollPaddingLeft', 
        'scrollMarginTop', 'scrollMarginRight', 'scrollMarginBottom', 'scrollMarginLeft', 
        'orphans', 'widows', 
        'clipShape', 'clipRect', 'shapeOutside', 'shapeMargin', 
        'gridCols', 'gridRows', 'gridColsSubgrid', 'gridRowsSubgrid', 'gridAreas', 'gridAutoCols', 'gridAutoRows', 
        'gridAutoFlowColumn', 'gridColStart', 'gridColEnd', 
        'gridRowStart', 'gridRowEnd', 'justifyItems', 'justifySelf', 'textOverflowEllipsis', 
        'pointerEvents', 'containInlineSize', 'containBlockSize', 'containLayout', 
        'containPaint', 'containStyle', 'contentHidden', 
        'intrinsicWidth', 'intrinsicHeight', 'transforms', 
        'transformBoxContent', 'appearanceAuto', 'fieldSizingContent', 'accentColor', 'transformOriginX', 'transformOriginY', 'listInside', 'listImageUrl', 'contentUrl', 'backgroundFixed', 'flexDirection', 
        'justifyContent', 'alignItems', 'alignSelf', 'flexWrap', 
        'alignContent', 'flexGrow', 'flexShrink', 'flexBasis', 'rowGap', 
        'columnGap', 'order', 'backgroundImage', 'overflowHidden', 'overflowX', 'overflowY', 
        'backgroundUrl', 'backgroundRepeatX', 'backgroundRepeatY', 
        'backgroundPosX', 'backgroundPosY', 'backgroundSizeKind', 
        'backgroundSizeW', 'backgroundSizeH', 'backgroundClip', 
        'backgroundOrigin', 'objectFit', 'objectPosX', 'objectPosY', 'objectViewBox', 'shadows',
        'counterReset', 'counterIncrement', 'counterSet', 'quotes', 'colorSchemeDark',
        'containerType', 'containerName', 'initialLetterPacked', 'baselineSource',
        'resize', 'textWrapStyle']
}

text func trackKey(list:arr[Track]) {
    text out = ''
    for int i = 0, i < list.length, i++ {
        out = out + `${list[i].kind}:${lenKey(list[i].size)}/${list[i].fr};`
    }
    return out
}

// Every field of a clip shape, so a change to any part of it registers.
text func clipKey(sh:ClipShape) {
    text out = `${sh.kind}:${sh.geoBox}`
    out = out + `:${lenKey(sh.insetTop)}/${lenKey(sh.insetRight)}`
    out = out + `/${lenKey(sh.insetBottom)}/${lenKey(sh.insetLeft)}`
    out = out + `:${lenKey(sh.centreX)}/${lenKey(sh.centreY)}`
    out = out + `:${lenKey(sh.radiusX)}/${lenKey(sh.radiusY)}`
    out = out + `:${sh.radiusXKind}/${sh.radiusYKind}`
    for int i = 0, i < sh.pointsX.length, i++ {
        out = out + `;${lenKey(sh.pointsX[i])},${lenKey(sh.pointsY[i])}`
    }
    return out
}

text func lineKey(g:GridLine) {
    return `${g.kind}:${g.n}`
}

text func transformKey(list:arr[Transform]) {
    text out = ''
    for int i = 0, i < list.length, i++ {
        Transform t = list[i]
        out = out + `${t.kind}:${lenKey(t.x)}/${lenKey(t.y)}/${t.angle}/${t.sx}/${t.sy};`
    }
    return out
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

// A property whose whole effect is on a pseudo-element cannot register
// against an element's computed style, however complete it is: nothing
// the declaration does reaches the element. `initial-letter` is of
// that shape -- it restyles `::first-letter` and touches nothing on the
// element -- and it sat in `supportsExempt`, which silenced the
// @supports cross-check without making it measurable.
//
// So a row may name a pseudo-element, and then the declaration goes
// into a rule rather than a style attribute and the digest is taken
// from the pseudo's own computed style. The content is digested beside
// it, because `content` lives outside `Style` here and the row would
// otherwise be graded on fields it does not set.
arr[text] func digestFieldsForPseudo(decl:text, pseudo:text) {
    cascadeReset()
    Node doc = parseHtmlText(`<html><head><style>#t::${pseudo}{${decl}}</style></head><body><table><tr><td><p id="t">Hxy text</p></td></tr></table></body></html>`)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    arr[Node] ps = []
    collectElements(doc, 'p', ps)
    arr[text] missing = ['MISSING']
    if ps.length == 0 { return missing }
    Style s = pseudoStyleOf(ps[0].id, pseudo)
    // No style at all means the engine did not compute this
    // pseudo-element for the rule, which is an instrument fault rather
    // than a reading of the property. The caller says so.
    if s == null { return ['NOPSEUDO'] }
    arr[text] fields = styleDigestFields(s)
    text c = pseudoContentOf(ps[0].id, pseudo)
    fields.push(c == null ? '' : c)
    return fields
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
arr[text] pseudoNames = pseudoFieldNames()

arr[text] lines = blobLines(f)
int total = 0
int gradeable = 0
int implemented = 0
arr[text] inert = []
arr[text] ungradeable = []
// `@supports` answers from `supportedProperties` in the CSS parser,
// and that list is written by hand while this instrument measures the
// engine, so the two drift apart silently and in both directions. They
// must agree: a property this engine implements that `@supports`
// denies sends a page down a fallback path it does not need, and one
// `@supports` claims that changes nothing is the lie `@supports` exists
// to prevent.
//
// The two can disagree honestly in one direction only. `@supports`
// answers for the engine, this instrument for an ordinary element, so
// a property implemented somewhere an ordinary element cannot reach it
// registers as changing nothing here: `content` works on `::before`
// and `::after` and does nothing on a `<p>`. Each such property is
// named here with its reason; every other disagreement fails the run.
// Nothing needs exempting from the @supports cross-check: a property
// this engine implements but the digest cannot see is a row that should
// name its pseudo-element instead.
arr[text] supportsExempt = []
arr[text] supportsDenied = []
arr[text] supportsOverclaimed = []

for int i = 0, i < lines.length, i++ {
    text line = lines[i]
    if line == null || line == '' { continue }
    if line.split('')[0] == '#' { continue }
    arr[text] parts = line.split('\t')
    if parts.length < 2 { continue }
    text prop = parts[0]
    text val = parts[1]
    // A fourth column names the pseudo-element the row is graded on.
    // The third already means "ungradeable, and here is why", so it is
    // left empty on a pseudo row rather than overloaded.
    text pseudo = parts.length >= 4 && parts[3] != '' ? parts[3] : null
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
    arr[text] gotFields = []
    arr[text] rowFieldNames = fieldNames
    if pseudo != null {
        rowBaseFields = digestFieldsForPseudo(context, pseudo)
        gotFields = digestFieldsForPseudo(`${prop}: ${own};${context}`, pseudo)
        rowFieldNames = pseudoNames
        // Either side missing its pseudo-element means the fixture did
        // not produce one to grade, which is the instrument failing
        // rather than the property.
        if rowBaseFields[0] == 'NOPSEUDO' || gotFields[0] == 'NOPSEUDO' {
            gradeable--
            ungradeable.push(`${prop} (the ::${pseudo} did not compute; the row needs a context declaration that creates it)`)
            continue
        }
    } else {
        if context != '' { rowBaseFields = digestFieldsFor(context) }
        gotFields = digestFieldsFor(`${prop}: ${own};${context}`)
    }
    text rowBaseline = rowBaseFields.join('\u0001')
    bool known = cssKnownProperty(prop.toAscii())
    if gotFields.join('\u0001') == rowBaseline {
        inert.push(prop)
        if known {
            bool exempt = false
            for int e = 0, e < supportsExempt.length, e++ {
                if supportsExempt[e] == prop { exempt = true }
            }
            if !exempt { supportsOverclaimed.push(prop) }
        }
        continue
    }
    implemented++
    if !known { supportsDenied.push(prop) }
    if showFields {
        // Which fields moved, not just that something did. A property
        // that registers only through a field belonging to a different
        // property is being scored for a side effect: `border-top-style`
        // used to move nothing but the border's *width*, because
        // declaring a style gives that side the medium width. The
        // instrument cannot judge which field means which property, so
        // it prints the mapping and leaves the reading to a person.
        arr[text] moved = []
        for int k = 0, k < rowFieldNames.length && k < gotFields.length, k++ {
            if gotFields[k] != rowBaseFields[k] { moved.push(rowFieldNames[k]) }
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
if supportsDenied.length > 0 || supportsOverclaimed.length > 0 {
    log('properties: FAILED -- @supports and this instrument disagree')
    for int i = 0, i < supportsDenied.length, i++ {
        log(`    ${supportsDenied[i]}: changes the computed style, and @supports says no`)
    }
    for int i = 0, i < supportsOverclaimed.length, i++ {
        log(`    ${supportsOverclaimed[i]}: @supports says yes, and it changes nothing`)
    }
    log('    add it to supportedProperties in src/css/parser.f, remove it from there,')
    log('    or name it in supportsExempt with the reason an ordinary element cannot show it')
    close(1)
}
if ungradeable.length > 0 {
    log(`properties: ${ungradeable.length} of ${total} rows carry a value that could never show a difference (--verbose lists them)`)
}
if minimum >= 0 && implemented < minimum {
    log(`properties: FAILED -- expected at least ${minimum}`)
    close(1)
}
close(0)
