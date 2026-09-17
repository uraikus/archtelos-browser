// CSS Color Adjustment 1: `color-scheme` says which of the schemes a
// page is prepared for, and the system colours resolve accordingly.
//
// Every expectation is Chromium 141's, read with getComputedStyle off
// the same stylesheet: the resolution rules from the computed value of
// `color-scheme`, and the colours from a probe span whose `color` is
// set to each system colour name under each scheme.
//
// The user's own preference is what picks from a list, and this browser
// answers `prefers-color-scheme: light` (Media Queries 4, css-2026.md).
// So a list that offers light gets light, whatever order it is in, and
// only a list offering dark and not light is dark.
import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

// ---- 1. the table is what it says it is -------------------------------
// A packed colour is a decimal here, because Festina has no hexadecimal
// literal (FINDINGS.md), and a hand conversion beside a comment is
// exactly how COLOR_VISITED came to be the wrong purple for months.
// Each entry is asserted against the channels its comment names, so the
// two cannot drift apart without a failure.
void func darkIs(name:text, r:int, g:int, b:int) {
    int got = cssDarkSystemColors[name]
    if got == null {
        checksFailed++
        log(`FAIL: no dark ${name}`)
        return
    }
    checkEqInt(got, packColor(r, g, b, 255), `dark ${name} is rgb(${r}, ${g}, ${b})`)
}
darkIs('canvas', 18, 18, 18)
darkIs('canvastext', 255, 255, 255)
darkIs('linktext', 158, 158, 255)
darkIs('visitedtext', 208, 173, 240)
darkIs('buttonface', 107, 107, 107)
darkIs('buttontext', 255, 255, 255)
darkIs('buttonborder', 255, 255, 255)
darkIs('field', 59, 59, 59)
darkIs('fieldtext', 255, 255, 255)
darkIs('selecteditem', 153, 200, 255)
darkIs('selecteditemtext', 59, 59, 59)

// ---- 2. what a scheme resolves to -------------------------------------
// The probe reads `color`, which is a system colour name, off an element
// under a wrapper carrying the scheme.
int func schemeColor(scheme:text, sysColor:text) {
    cascadeReset()
    Node doc = parseHtmlText('<html><head><style>#t { color: ' + sysColor
        + ' } #w { color-scheme: ' + scheme + ' }</style></head>'
        + '<body><div id="w"><p id="t">x</p></div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return findElement(doc, 'p').style.color
}

int schemeWhite = packColor(255, 255, 255, 255)
int schemeBlack = packColor(0, 0, 0, 255)

checkEqInt(schemeColor('dark', 'canvastext'), schemeWhite,
           'under dark, CanvasText is white')
checkEqInt(schemeColor('light', 'canvastext'), schemeBlack,
           'under light, CanvasText is black')
checkEqInt(schemeColor('normal', 'canvastext'), schemeBlack,
           'under normal, CanvasText is black')
// A list is resolved against the user's preference, which is light
// here, so either order of `light dark` gives light.
checkEqInt(schemeColor('light dark', 'canvastext'), schemeBlack,
           'a list offering light resolves light')
checkEqInt(schemeColor('dark light', 'canvastext'), schemeBlack,
           'and the order in the list does not decide it')
// `only` does not change which scheme is picked, just how a user agent
// may override it; `only dark` is still dark.
checkEqInt(schemeColor('only dark', 'canvastext'), schemeWhite,
           '`only dark` is dark')
// An ident nobody knows is carried along and ignored.
checkEqInt(schemeColor('dark mycustom', 'canvastext'), schemeWhite,
           'an unknown scheme beside dark leaves dark standing')
checkEqInt(schemeColor('mycustom', 'canvastext'), schemeBlack,
           'and a list of only unknown schemes is neither, so light')
// An unparseable value is an invalid declaration, dropped.
checkEqInt(schemeColor('!!!', 'canvastext'), schemeBlack,
           'an invalid color-scheme computes normal')

// ---- 3. the eleven colours that change --------------------------------
void func bothSchemes(sysColor:text, lr:int, lg:int, lb:int, dr:int, dg:int, db:int) {
    checkEqInt(schemeColor('light', sysColor), packColor(lr, lg, lb, 255),
               `${sysColor} under light`)
    checkEqInt(schemeColor('dark', sysColor), packColor(dr, dg, db, 255),
               `${sysColor} under dark`)
}
bothSchemes('canvas', 255, 255, 255, 18, 18, 18)
bothSchemes('canvastext', 0, 0, 0, 255, 255, 255)
bothSchemes('linktext', 0, 0, 238, 158, 158, 255)
bothSchemes('visitedtext', 85, 26, 139, 208, 173, 240)
bothSchemes('buttonface', 239, 239, 239, 107, 107, 107)
bothSchemes('buttontext', 0, 0, 0, 255, 255, 255)
bothSchemes('buttonborder', 0, 0, 0, 255, 255, 255)
bothSchemes('field', 255, 255, 255, 59, 59, 59)
bothSchemes('fieldtext', 0, 0, 0, 255, 255, 255)
bothSchemes('selecteditem', 25, 103, 210, 153, 200, 255)
bothSchemes('selecteditemtext', 255, 255, 255, 59, 59, 59)

// ---- 4. the eight that do not -----------------------------------------
// Chromium answers these identically under both schemes, so a table that
// darkened everything would fail here. This is the half of the check
// that stops the feature from being "invert some colours".
void func sameUnderBoth(sysColor:text) {
    checkEqInt(schemeColor('dark', sysColor), schemeColor('light', sysColor),
               `${sysColor} is the same under either scheme`)
}
sameUnderBoth('activetext')
sameUnderBoth('highlight')
sameUnderBoth('highlighttext')
sameUnderBoth('mark')
sameUnderBoth('marktext')
sameUnderBoth('graytext')
sameUnderBoth('accentcolor')
sameUnderBoth('accentcolortext')

// ---- 5. it inherits ----------------------------------------------------
int func nestedColor(outer:text, inner:text) {
    cascadeReset()
    Node doc = parseHtmlText('<html><head><style>#t { color: canvastext }'
        + ' #w { color-scheme: ' + outer + ' }'
        + (inner == '' ? '' : ' #m { color-scheme: ' + inner + ' }')
        + '</style></head>'
        + '<body><div id="w"><div id="m"><p id="t">x</p></div></div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return findElement(doc, 'p').style.color
}
checkEqInt(nestedColor('dark', ''), schemeWhite,
           'a scheme on an ancestor reaches a descendant')
checkEqInt(nestedColor('dark', 'normal'), schemeBlack,
           'and `normal` on something in between takes it back')
checkEqInt(nestedColor('normal', 'dark'), schemeWhite,
           'and a scheme set deeper applies from there')

// ---- 6. a named colour is not a system colour --------------------------
// Only the system colours answer to the scheme. `black` is black under
// either, which is what stops this from being a filter over everything.
checkEqInt(schemeColor('dark', 'black'), schemeBlack,
           'a named colour is unaffected by the scheme')
checkEqInt(schemeColor('dark', '#123456'), packColor(18, 52, 86, 255),
           'and so is a hex colour')

finish('color scheme')
