// `font-size-adjust` (CSS Fonts 4 §6).
//
// The used font size is the specified one times `<number> / aspect`,
// where the aspect is the named metric as a fraction of the em.
// `ex-height` is the default, so a bare number means it.
//
// Chromium 141 prints each aspect in the computed value of
// `<metric> from-font`, which is how they were read: for the monospace
// face here at 16px, ex-height 0.5625, cap-height 0.75, ch-width
// 0.602051, and ic-width and ic-height 1. todo.md has the whole table.
//
// **This engine diverges, by a known amount.** Chromium's aspect is
// the HINTED metric and changes with the size -- at 8px the x-height
// is 5 pixels rather than 9, so the aspect is 5/8 rather than 9/16 --
// and this engine carries one ratio per metric, the same constants the
// `ex`, `ch` and `cap` units read. So `font-size-adjust: 1` at 16px is
// 29px here against Chromium's 28.44, 2.8% apart, and at 8px it is 15
// against 12.8. The alternative is a hinted metric per size, which the
// runtime does not report.
import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

Node func fsaNodeById(n:Node, id:text) {
    if n.kind == NODE_ELEMENT && attrOf(n.id, 'id') == id { return n }
    for int i = 0, i < n.children.length, i++ {
        Node f = fsaNodeById(n.children[i], id)
        if f != null { return f }
    }
    return null
}

// The computed style of a span carrying `decls`, inside a 400px block
// at 16px, so a declaration that does nothing reads as 16.
Style func fsaStyle(decls:text) {
    cascadeReset()
    cssViewportWidth = 600
    Node doc = parseHtmlText('<html><body style="margin:0">'
        + '<div style="width:400px;font-size:16px">'
        + '<span id="t" style="' + decls + '">MMMMMMMMMM</span>'
        + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return fsaNodeById(doc, 't').style
}

int func fsaSize(decls:text) {
    Style s = fsaStyle(decls)
    return s == null ? -1 : s.fontSize
}

// ---- the four metrics, each against this engine's own ratio ---------
checkEqInt(fsaSize(''), 16, 'no declaration leaves the specified size')
checkEqInt(fsaSize('font-size-adjust:none'), 16, 'and `none` is the same')
checkEqInt(fsaSize('font-size-adjust:from-font'), 16,
           '`from-font` asks for the font\'s own aspect, which changes nothing')

checkEqInt(fsaSize('font-size-adjust:0.5'), 15,
           'half an x-height, where Chromium gives 14.22 from its hinted 0.5625')
checkEqInt(fsaSize('font-size-adjust:1'), 29,
           'a full one, where Chromium gives 28.44')
checkEqInt(fsaSize('font-size-adjust:2'), 59, 'and twice it')
checkEqInt(fsaSize('font-size-adjust:0'), 0, 'zero is a zero-sized font, not a no-op')

checkEqInt(fsaSize('font-size-adjust:cap-height 0.5'), 11,
           'against the cap height instead, where Chromium gives 10.67')
checkEqInt(fsaSize('font-size-adjust:ch-width 0.5'), 13,
           'and the zero advance, where Chromium gives 13.29')
checkEqInt(fsaSize('font-size-adjust:ic-width 0.5'), 8,
           'and the ideograph advance, which is an em, so half of it is half the size')

// ---- the checks that need no number of their own --------------------
checkEqInt(fsaSize('font-size-adjust:ex-height 0.5'), fsaSize('font-size-adjust:0.5'),
           'a bare number is an x-height adjustment written out')
checkEqInt(fsaSize('font-size-adjust:ic-height 0.5'), fsaSize('font-size-adjust:ic-width 0.5'),
           'the two ideograph metrics share an aspect of one')
checkEqInt(fsaSize('font-size-adjust:from-font'), fsaSize(''),
           '`from-font` and no declaration are the same font')
// Linear in the specified size, which is what says the adjustment is a
// factor rather than a size of its own. Asked of `ic-width`, whose
// aspect is exactly one, because a used size is an integer and an
// aspect that does not divide evenly cannot be exactly linear through
// two roundings: 16 gives 14.63 and rounds to 15, 32 gives 29.25 and
// rounds to 29, and 29 is not twice 15. That is the rounding, and it
// is here rather than hidden in a band.
checkEqInt(fsaSize('font-size:32px;font-size-adjust:ic-width 0.5'),
           2 * fsaSize('font-size:16px;font-size-adjust:ic-width 0.5'),
           'twice the specified size is twice the used one')
checkEqInt(fsaSize('font-size:32px;font-size-adjust:0.5'), 29,
           'and at 32px an x-height of a half is 29, where Chromium gives 28.44')

// ---- what it does not touch -----------------------------------------
// `em` resolves against the SPECIFIED size, which is measured: Chromium
// gives `width: 2em` under an adjust of 1 as 32px rather than 57.
checkEqInt(resolveLen(fsaStyle('font-size-adjust:1;width:2em').width, 0, -1), 32,
           'an em beside the adjustment is the specified size, not the used one')
checkEqInt(resolveLen(fsaStyle('font-size-adjust:1;width:2em').width, 0, -1),
           resolveLen(fsaStyle('width:2em').width, 0, -1),
           'which is the same em it would have been without the declaration')
// `line-height: normal` follows the USED size, also measured: the
// control's line box is 19 tall and an adjust of 1 makes it 33.
check(lineHeightOf(fsaStyle('font-size-adjust:1')) > lineHeightOf(fsaStyle('')),
      'but a normal line height follows the used size and grows')
checkEqInt(lineHeightOf(fsaStyle('font-size-adjust:1')),
           lineHeightOf(fsaStyle(`font-size:${fsaSize('font-size-adjust:1')}px`)),
           'exactly as though that size had been declared')
// An explicit line height is a length like any other and does not.
checkEqInt(lineHeightOf(fsaStyle('font-size-adjust:1;line-height:1em')), 16,
           'an em line height stays the specified em')

// ---- the invalid forms, all measured as computing to `none` ---------
checkEqInt(fsaSize('font-size-adjust:-1'), 16, 'a negative number is invalid')
checkEqInt(fsaSize('font-size-adjust:0.5 0.5'), 16, 'and two numbers')
checkEqInt(fsaSize('font-size-adjust:ex-height'), 16, 'and a metric with no number')
checkEqInt(fsaSize('font-size-adjust:50%'), 16, 'and a percentage')
checkEqInt(fsaSize('font-size-adjust:banana'), 16, 'and anything else')

finish('font size adjust')
