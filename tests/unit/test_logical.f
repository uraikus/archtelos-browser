// Logical properties (CSS Logical Properties 1, via the box and border
// specifications that define their physical twins).
//
// Every one of these is an alias in a left-to-right horizontal writing
// mode, which is what this engine assumes throughout: `inline-start` is
// the left edge, `block-start` the top. That assumption is recorded in
// css-2026.md under Writing Modes 3, and it is what makes these a
// mapping rather than a layout feature.
//
// So each check asks the question the rule in CLAUDE.md asks of two
// things that must agree: the logical spelling and the physical one
// must compute to the same thing. A check against a number instead
// would pass just as well if both were broken the same way.
import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

// Computes one declaration on a <p> and hands back its style.
Style func styleOf(decl:text) {
    cascadeReset()
    Node doc = parseHtmlText(`<html><body><p id="t" style="${decl}">x</p></body></html>`)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    arr[Node] ps = []
    collectElements(doc, 'p', ps)
    return ps[0].style
}

void func checkSameLen(logical:text, physical:text, read:text, label:text) {
    Style a = styleOf(logical)
    Style b = styleOf(physical)
    int va = 0
    int vb = 0
    if read == 'borderTop' { va = a.borderTop  vb = b.borderTop }
    else if read == 'borderBottom' { va = a.borderBottom  vb = b.borderBottom }
    else if read == 'borderLeft' { va = a.borderLeft  vb = b.borderLeft }
    else if read == 'borderRight' { va = a.borderRight  vb = b.borderRight }
    else if read == 'borderTopColor' { va = a.borderTopColor  vb = b.borderTopColor }
    else if read == 'borderLeftColor' { va = a.borderLeftColor  vb = b.borderLeftColor }
    else if read == 'borderTopStyle' { va = a.borderTopStyle  vb = b.borderTopStyle }
    else if read == 'borderRightStyle' { va = a.borderRightStyle  vb = b.borderRightStyle }
    else if read == 'top' { va = resolveLen(a.top, 0, -1)  vb = resolveLen(b.top, 0, -1) }
    else if read == 'bottom' { va = resolveLen(a.bottom, 0, -1)  vb = resolveLen(b.bottom, 0, -1) }
    else if read == 'left' { va = resolveLen(a.left, 0, -1)  vb = resolveLen(b.left, 0, -1) }
    else if read == 'right' { va = resolveLen(a.right, 0, -1)  vb = resolveLen(b.right, 0, -1) }
    else if read == 'minWidth' { va = resolveLen(a.minWidth, 0, -1)  vb = resolveLen(b.minWidth, 0, -1) }
    else if read == 'maxWidth' { va = resolveLen(a.maxWidth, 0, -1)  vb = resolveLen(b.maxWidth, 0, -1) }
    else if read == 'minHeight' { va = resolveLen(a.minHeight, 0, -1)  vb = resolveLen(b.minHeight, 0, -1) }
    else if read == 'maxHeight' { va = resolveLen(a.maxHeight, 0, -1)  vb = resolveLen(b.maxHeight, 0, -1) }
    else if read == 'paddingTop' { va = resolveLen(a.paddingTop, 0, -1)  vb = resolveLen(b.paddingTop, 0, -1) }
    else if read == 'paddingBottom' { va = resolveLen(a.paddingBottom, 0, -1)  vb = resolveLen(b.paddingBottom, 0, -1) }
    else if read == 'overflowHidden' { va = a.overflowHidden ? 1 : 0  vb = b.overflowHidden ? 1 : 0 }
    else if read == 'radiusTopLeft' { va = a.radiusTopLeft  vb = b.radiusTopLeft }
    else if read == 'radiusTopRight' { va = a.radiusTopRight  vb = b.radiusTopRight }
    else if read == 'radiusBottomLeft' { va = a.radiusBottomLeft  vb = b.radiusBottomLeft }
    else if read == 'radiusBottomRight' { va = a.radiusBottomRight  vb = b.radiusBottomRight }
    checkEqInt(va, vb, label)
    check(va != 0, label + ' (and is not simply the initial value on both)')
}

// ---- border widths ------------------------------------------------------
checkSameLen('border-block-start-width:7px;border-block-start-style:solid',
             'border-top-width:7px;border-top-style:solid',
             'borderTop', 'border-block-start-width is border-top-width')
checkSameLen('border-block-end-width:7px;border-block-end-style:solid',
             'border-bottom-width:7px;border-bottom-style:solid',
             'borderBottom', 'border-block-end-width is border-bottom-width')
checkSameLen('border-inline-start-width:7px;border-inline-start-style:solid',
             'border-left-width:7px;border-left-style:solid',
             'borderLeft', 'border-inline-start-width is border-left-width')
checkSameLen('border-inline-end-width:7px;border-inline-end-style:solid',
             'border-right-width:7px;border-right-style:solid',
             'borderRight', 'border-inline-end-width is border-right-width')

// ---- border colours ------------------------------------------------------
checkSameLen('border-block-start-color:#123456;border-block-start-style:solid',
             'border-top-color:#123456;border-top-style:solid',
             'borderTopColor', 'border-block-start-color is border-top-color')
checkSameLen('border-inline-start-color:#123456;border-inline-start-style:solid',
             'border-left-color:#123456;border-left-style:solid',
             'borderLeftColor', 'border-inline-start-color is border-left-color')

// ---- border styles -------------------------------------------------------
checkSameLen('border-block-start-style:dashed', 'border-top-style:dashed',
             'borderTopStyle', 'border-block-start-style is border-top-style')
checkSameLen('border-inline-end-style:dotted', 'border-right-style:dotted',
             'borderRightStyle', 'border-inline-end-style is border-right-style')

// ---- insets ---------------------------------------------------------------
checkSameLen('position:relative;inset-block-start:11px', 'position:relative;top:11px',
             'top', 'inset-block-start is top')
checkSameLen('position:relative;inset-block-end:11px', 'position:relative;bottom:11px',
             'bottom', 'inset-block-end is bottom')
checkSameLen('position:relative;inset-inline-start:11px', 'position:relative;left:11px',
             'left', 'inset-inline-start is left')
checkSameLen('position:relative;inset-inline-end:11px', 'position:relative;right:11px',
             'right', 'inset-inline-end is right')

// ---- sizes -----------------------------------------------------------------
checkSameLen('min-inline-size:33px', 'min-width:33px', 'minWidth', 'min-inline-size is min-width')
checkSameLen('max-inline-size:33px', 'max-width:33px', 'maxWidth', 'max-inline-size is max-width')
checkSameLen('min-block-size:33px', 'min-height:33px', 'minHeight', 'min-block-size is min-height')
checkSameLen('max-block-size:33px', 'max-height:33px', 'maxHeight', 'max-block-size is max-height')

// ---- padding ----------------------------------------------------------------
checkSameLen('padding-block-start:9px', 'padding-top:9px', 'paddingTop', 'padding-block-start is padding-top')
checkSameLen('padding-block-end:9px', 'padding-bottom:9px', 'paddingBottom', 'padding-block-end is padding-bottom')

// ---- overflow -----------------------------------------------------------------
checkSameLen('overflow-block:hidden', 'overflow:hidden', 'overflowHidden', 'overflow-block is overflow')
checkSameLen('overflow-inline:hidden', 'overflow:hidden', 'overflowHidden', 'overflow-inline is overflow')

// ---- the shorthands ------------------------------------------------------------
checkSameLen('border-block-start:3px solid red', 'border-top:3px solid red',
             'borderTop', 'the border-block-start shorthand is border-top')
checkSameLen('border-inline-end:3px solid red', 'border-right:3px solid red',
             'borderRight', 'the border-inline-end shorthand is border-right')
checkSameLen('border-block:3px solid red', 'border-top:3px solid red;border-bottom:3px solid red',
             'borderBottom', 'the border-block shorthand sets both block edges')
checkSameLen('border-inline:3px solid red', 'border-left:3px solid red;border-right:3px solid red',
             'borderLeft', 'the border-inline shorthand sets both inline edges')

// ---- the logical corners ---------------------------------------------
// `start-start` is the corner where the block and inline starts meet,
// which in this writing mode is the top left.
checkSameLen('border-start-start-radius:9px', 'border-top-left-radius:9px',
             'radiusTopLeft', 'border-start-start-radius is the top-left corner')
checkSameLen('border-start-end-radius:9px', 'border-top-right-radius:9px',
             'radiusTopRight', 'border-start-end-radius is the top-right corner')
checkSameLen('border-end-start-radius:9px', 'border-bottom-left-radius:9px',
             'radiusBottomLeft', 'border-end-start-radius is the bottom-left corner')
checkSameLen('border-end-end-radius:9px', 'border-bottom-right-radius:9px',
             'radiusBottomRight', 'border-end-end-radius is the bottom-right corner')

finish('logical properties')
