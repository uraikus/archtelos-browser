// CSS Color 4's wider colour spaces: hwb(), lab(), lch(), oklab(),
// oklch() and color().
//
// The expected values are not read back from this engine. They were
// derived twice, independently: once by implementing the conversion
// pseudocode of CSS Color 4 §17 in a separate script, and once by
// asking headless Chromium for the pixel it paints when that colour is
// a canvas fill. The two agreed to the byte on every case below, so a
// failure here is this engine's, not the expectation's.
import ../../src/util/color.f
import ../assert.f

int c4black = COLOR_BLACK

void func c4is(css:ascii, r:int, g:int, b:int, label:text) {
    int got = parseCssColor(css, c4black)
    int want = packColor(r, g, b, 255)
    if got == want { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: expected rgb(${r}, ${g}, ${b}), got rgb(${colorRed(got)}, ${colorGreen(got)}, ${colorBlue(got)}) a=${colorAlpha(got)}`)
    }
}

// Two ways of naming one colour must land on the same packed int. This
// catches the mistakes a comparison against a number worked out in
// advance cannot: a percentage read on the wrong scale, a hue unit
// dropped, a shorthand and its longhand disagreeing.
void func c4same(a:ascii, b:ascii, label:text) {
    int x = parseCssColor(a, c4black)
    int y = parseCssColor(b, c4black)
    if x == y && x != COLOR_UNSET { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: rgb(${colorRed(x)}, ${colorGreen(x)}, ${colorBlue(x)}) vs rgb(${colorRed(y)}, ${colorGreen(y)}, ${colorBlue(y)})`)
    }
}

// ---- hwb() ------------------------------------------------------------
c4is('hwb(0 0% 0%)', 255, 0, 0, 'hwb red')
c4is('hwb(120 0% 0%)', 0, 255, 0, 'hwb green')
c4is('hwb(240 0% 0%)', 0, 0, 255, 'hwb blue')
c4is('hwb(0 50% 50%)', 128, 128, 128, 'hwb grey')
c4is('hwb(0 25% 25%)', 191, 64, 64, 'hwb tinted')
c4is('hwb(90 20% 10%)', 140, 230, 51, 'hwb hue 90')
// whiteness + blackness over 100% normalises to their ratio, so the
// hue drops out entirely.
c4is('hwb(0 60% 60%)', 128, 128, 128, 'hwb oversaturated')

// ---- lab() and lch() --------------------------------------------------
c4is('lab(100 0 0)', 255, 255, 255, 'lab white')
c4is('lab(0 0 0)', 0, 0, 0, 'lab black')
c4is('lab(54.29 80.8 69.89)', 255, 0, 0, 'lab red')
c4is('lab(50 40 -30)', 165, 91, 171, 'lab purple')
c4is('lch(54.29 106.84 40.85)', 255, 0, 0, 'lch red')
c4is('lch(70 50 200)', 0, 194, 201, 'lch cyan')

// ---- oklab() and oklch() ----------------------------------------------
c4is('oklab(1 0 0)', 255, 255, 255, 'oklab white')
c4is('oklab(0 0 0)', 0, 0, 0, 'oklab black')
c4is('oklab(0.628 0.2249 0.1258)', 255, 0, 0, 'oklab red')
c4is('oklab(0.5 -0.1 0.05)', 32, 117, 68, 'oklab green')
c4is('oklch(0.628 0.2577 29.23)', 255, 0, 0, 'oklch red')
c4is('oklch(0.8 0.15 150)', 110, 216, 137, 'oklch mint')

// ---- color() ----------------------------------------------------------
c4is('color(srgb 1 0 0)', 255, 0, 0, 'color srgb')
c4is('color(srgb 0.5 0.5 0.5)', 128, 128, 128, 'color srgb grey')
c4is('color(srgb-linear 0.5 0.5 0.5)', 188, 188, 188, 'color srgb-linear')
c4is('color(display-p3 1 0 0)', 255, 0, 0, 'color display-p3 red')
c4is('color(display-p3 0 1 0)', 0, 255, 0, 'color display-p3 green')
c4is('color(a98-rgb 1 0 0)', 255, 0, 0, 'color a98-rgb')
c4is('color(prophoto-rgb 1 0 0)', 255, 0, 0, 'color prophoto-rgb')
c4is('color(rec2020 1 0 0)', 255, 0, 0, 'color rec2020')
c4is('color(xyz 0.2 0.3 0.4)', 0, 167, 164, 'color xyz')
c4is('color(xyz-d65 0.2 0.3 0.4)', 0, 167, 164, 'color xyz-d65')
c4is('color(xyz-d50 0.2 0.3 0.4)', 0, 168, 189, 'color xyz-d50')

// ---- percentages, hue units and alpha, each against the plain form ----
c4same('lab(50% 40 -30)', 'lab(50 40 -30)', 'lab lightness percent')
c4same('lab(50 32% -24%)', 'lab(50 40 -30)', 'lab a/b percent is out of 125')
c4same('oklab(62.8% 0.2249 0.1258)', 'oklab(0.628 0.2249 0.1258)', 'oklab lightness percent')
c4same('oklab(0.5 50% 25%)', 'oklab(0.5 0.2 0.1)', 'oklab a/b percent is out of 0.4')
c4same('lch(54.29% 106.84 40.85)', 'lch(54.29 106.84 40.85)', 'lch lightness percent')
c4same('oklch(62.8% 0.2577 29.23)', 'oklch(0.628 0.2577 29.23)', 'oklch lightness percent')
c4same('oklch(0.628 100% 29.23)', 'oklch(0.628 0.4 29.23)', 'oklch chroma percent is out of 0.4')
c4same('color(srgb 100% 0% 50%)', 'color(srgb 1 0 0.5)', 'color() component percent')
c4same('oklch(0.8 0.15 0.4167turn)', 'oklch(0.8 0.15 150)', 'oklch hue in turns')
c4same('lch(70 50 3.4907rad)', 'lch(70 50 200)', 'lch hue in radians')
c4same('hwb(90deg 20% 10%)', 'hwb(90 20% 10%)', 'hwb hue with deg')

// The same colour reached through two spaces must give the same pixel.
c4same('hwb(0 0% 0%)', 'red', 'hwb red is red')
c4same('color(srgb 1 0 0)', '#ff0000', 'color(srgb) red is #ff0000')
c4same('lab(54.29 80.8 69.89)', 'lch(54.29 106.84 40.85)', 'lab and lch agree')
c4same('oklab(0.628 0.2249 0.1258)', 'oklch(0.628 0.2577 29.23)', 'oklab and oklch agree')
c4same('color(xyz 0.2 0.3 0.4)', 'color(xyz-d65 0.2 0.3 0.4)', 'xyz is xyz-d65')
c4same('color(srgb 0.5 0.5 0.5)', 'rgb(128, 128, 128)', 'color(srgb) grey is rgb() grey')

// ---- alpha -------------------------------------------------------------
check(parseCssColor('lab(54.29 80.8 69.89 / 0.5)', c4black) == packColor(255, 0, 0, 128), 'lab alpha')
check(parseCssColor('oklch(0.628 0.2577 29.23 / 50%)', c4black) == packColor(255, 0, 0, 128), 'oklch alpha percent')
check(parseCssColor('color(display-p3 1 0 0 / 0.25)', c4black) == packColor(255, 0, 0, 64), 'color() alpha')
check(parseCssColor('hwb(0 0% 0% / 0.5)', c4black) == packColor(255, 0, 0, 128), 'hwb alpha')
check(parseCssColor('color(srgb 1 0 0 / 100%)', c4black) == packColor(255, 0, 0, 255), 'color() alpha 100%')

// ---- `none`, which the standard gives no value ------------------------
c4same('lab(none 40 -30)', 'lab(0 40 -30)', 'lab none lightness')
c4same('oklch(0.8 0.15 none)', 'oklch(0.8 0.15 0)', 'oklch none hue')
c4same('hwb(0 none none)', 'hwb(0 0% 0%)', 'hwb none amounts')
c4same('color(srgb none 0 0)', 'color(srgb 0 0 0)', 'color() none channel')
check(parseCssColor('lab(50 40 -30 / none)', c4black) == packColor(165, 91, 171, 0), 'none alpha is zero')

// ---- out of range, which clamps rather than failing --------------------
c4same('lab(-10 0 0)', 'lab(0 0 0)', 'lab lightness below zero')
c4same('oklch(1.5 0 0)', 'oklch(1 0 0)', 'oklch lightness above one')
c4same('color(srgb 1.5 -0.2 0.5)', 'color(srgb 1 0 0.5)', 'color() channel out of gamut')
check(parseCssColor('lab(50 40 -30 / 1.5)', c4black) == packColor(165, 91, 171, 255), 'alpha above one')

// ---- a bare number in hwb() means the same as the percentage ----------
c4same('hwb(90 20 10)', 'hwb(90 20% 10%)', 'hwb bare number is a percentage')

// ---- case, which is not significant ------------------------------------
c4same('LAB(50 40 -30)', 'lab(50 40 -30)', 'function name case')
c4same('color(SRGB 1 0 0)', 'color(srgb 1 0 0)', 'color() space case')

// ---- system colors -----------------------------------------------------
c4is('Canvas', 255, 255, 255, 'Canvas')
c4is('CanvasText', 0, 0, 0, 'CanvasText')
c4is('ButtonFace', 239, 239, 239, 'ButtonFace')
c4is('GrayText', 128, 128, 128, 'GrayText')
c4is('LinkText', 0, 0, 238, 'LinkText')
c4is('VisitedText', 85, 26, 139, 'VisitedText')
c4is('Mark', 255, 255, 0, 'Mark')
c4is('SelectedItem', 25, 103, 210, 'SelectedItem')
check(parseCssColor('Highlight', c4black) == packColor(0, 65, 198, 204), 'Highlight carries alpha')
c4same('canvastext', 'CanvasText', 'system color case')
// The user-agent stylesheet's own link colors are the same two the
// standard names, so they must be the same packed int.
check(COLOR_LINK == parseCssColor('LinkText', c4black), 'COLOR_LINK is LinkText')
check(COLOR_VISITED == parseCssColor('VisitedText', c4black), 'COLOR_VISITED is VisitedText')

// ---- what must still be refused ---------------------------------------
check(parseCssColor('color(nonesuch 1 0 0)', c4black) == COLOR_UNSET, 'unknown color() space')
check(parseCssColor('oklch(0.5 0.1)', c4black) == COLOR_UNSET, 'oklch needs three components')
check(parseCssColor('lab(bogus 1 2)', c4black) == COLOR_UNSET, 'lab rejects a non-number')

finish('color 4')
