// CSS Color 5's `color-mix()`.
//
// Every expected pixel is Chromium 141's, read by setting the colour as
// a canvas fill and reading the pixel back, before any of this was
// written. Mixing is defined on the interpolation space's own
// components, so the same two colours mixed in different spaces are
// different colours, and that is most of what these checks are about.
import ../../src/util/color.f
import ../assert.f

int mixBlack = COLOR_BLACK

void func mixIs(css:ascii, r:int, g:int, b:int, label:text) {
    int got = parseCssColor(css, mixBlack)
    int want = packColor(r, g, b, 255)
    if got == want { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: expected rgb(${r}, ${g}, ${b}), got rgb(${colorRed(got)}, ${colorGreen(got)}, ${colorBlue(got)}) a=${colorAlpha(got)}`)
    }
}

void func mixSame(a:ascii, b:ascii, label:text) {
    int x = parseCssColor(a, mixBlack)
    int y = parseCssColor(b, mixBlack)
    if x == y && x != COLOR_UNSET { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: rgb(${colorRed(x)}, ${colorGreen(x)}, ${colorBlue(x)}) a=${colorAlpha(x)} vs rgb(${colorRed(y)}, ${colorGreen(y)}, ${colorBlue(y)}) a=${colorAlpha(y)}`)
    }
}

// ---- the rectangular spaces -------------------------------------------
mixIs('color-mix(in srgb, red, blue)', 128, 0, 128, 'srgb, halfway')
mixIs('color-mix(in srgb, red 25%, blue)', 64, 0, 191, 'srgb, a quarter of the way')
mixIs('color-mix(in srgb, red 75%, blue)', 191, 0, 64, 'srgb, three quarters')
mixIs('color-mix(in srgb, red 0%, blue)', 0, 0, 255, 'none of the first colour')
mixIs('color-mix(in srgb, white, black)', 128, 128, 128, 'srgb grey is the encoded midpoint')
mixIs('color-mix(in srgb-linear, white, black)', 188, 188, 188, 'and linear grey is not')
mixIs('color-mix(in srgb-linear, red 20%, blue)', 124, 0, 231, 'srgb-linear, a fifth')
mixIs('color-mix(in xyz, red, blue)', 188, 0, 188, 'xyz, halfway')
mixIs('color-mix(in xyz, red 20%, blue)', 124, 0, 231, 'xyz, a fifth')
mixIs('color-mix(in xyz-d50, red, blue)', 188, 0, 188, 'xyz-d50 lands in the same place')
mixIs('color-mix(in lab, red, blue)', 193, 0, 136, 'lab, halfway')
mixIs('color-mix(in lab, red 20%, blue)', 132, 0, 206, 'lab, a fifth')
mixIs('color-mix(in lab, white, black)', 119, 119, 119, 'lab grey is lighter than srgb linear')
mixIs('color-mix(in oklab, red, blue)', 140, 83, 162, 'oklab, halfway')
mixIs('color-mix(in oklab, red 20%, blue)', 68, 65, 219, 'oklab, a fifth')
mixIs('color-mix(in oklab, white, black)', 99, 99, 99, 'and oklab grey is darker still')

// ---- the polar spaces --------------------------------------------------
// A hue is an angle, so mixing takes the shorter way round unless told
// otherwise: red and blue are 240 degrees apart the long way and 120
// the short way, and the short way passes through magenta.
mixIs('color-mix(in hsl, red, blue)', 255, 0, 255, 'hsl takes the shorter arc')
mixIs('color-mix(in hwb, red, blue)', 255, 0, 255, 'and so does hwb')
mixIs('color-mix(in hsl, red 20%, blue)', 102, 0, 255, 'hsl, a fifth of the way round')
mixIs('color-mix(in hwb, red 20%, blue)', 102, 0, 255, 'hwb, the same')
mixIs('color-mix(in lch, red, blue)', 245, 0, 134, 'lch, halfway')
mixIs('color-mix(in lch, red 20%, blue)', 169, 0, 213, 'lch, a fifth')
mixIs('color-mix(in oklch, red, blue)', 186, 0, 194, 'oklch, halfway')
mixIs('color-mix(in oklch, red 20%, blue)', 107, 0, 250, 'oklch, a fifth')

// The four ways round the circle.
mixIs('color-mix(in hsl shorter hue, red, blue)', 255, 0, 255, 'shorter hue is the default')
mixIs('color-mix(in hsl longer hue, red, blue)', 0, 255, 0, 'longer hue goes the other way')
mixIs('color-mix(in hsl increasing hue, red, blue)', 0, 255, 0, 'increasing hue counts up')
mixIs('color-mix(in hsl decreasing hue, red, blue)', 255, 0, 255, 'decreasing hue counts down')
mixIs('color-mix(in oklch shorter hue, lime, blue)', 0, 187, 227, 'oklch the short way')
mixIs('color-mix(in oklch longer hue, lime, blue)', 255, 0, 34, 'and the long way')

// ---- alpha --------------------------------------------------------------
// Mixing is done on premultiplied components, which is what keeps a
// transparent colour from dragging the result towards black.
check(parseCssColor('color-mix(in srgb, transparent, blue)', mixBlack) == packColor(0, 0, 255, 128),
      'a transparent colour contributes alpha and nothing else')
check(parseCssColor('color-mix(in srgb, #ff000080, blue)', mixBlack) == packColor(85, 0, 170, 192),
      'a half-transparent red mixes premultiplied')
// Percentages that do not add to a hundred scale the result's alpha.
check(parseCssColor('color-mix(in srgb, red 30%, blue 30%)', mixBlack) == packColor(128, 0, 128, 153),
      'percentages summing to sixty give six tenths alpha')

// ---- things that must agree --------------------------------------------
// None of these needs the answer known in advance.
mixSame('color-mix(in srgb, red 50%, blue)', 'color-mix(in srgb, red, blue)',
        'fifty per cent is what halfway means')
mixSame('color-mix(in srgb, red 25%, blue 75%)', 'color-mix(in srgb, red 25%, blue)',
        'the second percentage is the first one complemented')
mixSame('color-mix(in srgb, red 100%, blue)', 'red', 'all of the first colour is that colour')
mixSame('color-mix(in srgb, red 0%, blue)', 'blue', 'and none of it is the other')
mixSame('color-mix(in xyz, red, blue)', 'color-mix(in xyz-d65, red, blue)', 'xyz is xyz-d65')
mixSame('color-mix(in srgb-linear, red 20%, blue)', 'color-mix(in xyz, red 20%, blue)',
        'two linear-light spaces mix to the same colour')
mixSame('color-mix(in oklab, oklch(0.628 0.2577 29.23), blue)', 'color-mix(in oklab, red, blue)',
        'a colour written in oklch mixes as the red it is')

// A colour mixed with itself is itself, in every space. This is the
// check that needs no reference at all, and the one that a conversion
// wrong in both directions would still fail.
mixSame('color-mix(in srgb, red, red)', 'red', 'srgb: red mixed with red is red')
mixSame('color-mix(in srgb-linear, red, red)', 'red', 'srgb-linear likewise')
mixSame('color-mix(in xyz, red, red)', 'red', 'xyz likewise')
mixSame('color-mix(in xyz-d50, red, red)', 'red', 'xyz-d50 likewise')
mixSame('color-mix(in lab, red, red)', 'red', 'lab likewise')
mixSame('color-mix(in oklab, red, red)', 'red', 'oklab likewise')
mixSame('color-mix(in hsl, red, red)', 'red', 'hsl likewise')
mixSame('color-mix(in hwb, red, red)', 'red', 'hwb likewise')
mixSame('color-mix(in lch, red, red)', 'red', 'lch likewise')
mixSame('color-mix(in oklch, red, red)', 'red', 'oklch likewise')
mixSame('color-mix(in oklab, rebeccapurple, rebeccapurple)', 'rebeccapurple',
        'and a colour that is not a primary comes back unchanged')

// ---- currentcolor ------------------------------------------------------
check(parseCssColor('color-mix(in srgb, currentcolor, blue)', mixBlack) == packColor(0, 0, 128, 255),
      'currentcolor resolves before the mix')

// ---- what must be refused ----------------------------------------------
check(parseCssColor('color-mix(in nonesuch, red, blue)', mixBlack) == COLOR_UNSET,
      'an unknown interpolation space')
check(parseCssColor('color-mix(red, blue)', mixBlack) == COLOR_UNSET,
      'no space named at all')
check(parseCssColor('color-mix(in srgb, red)', mixBlack) == COLOR_UNSET,
      'only one colour to mix')
check(parseCssColor('color-mix(in srgb, bogus, blue)', mixBlack) == COLOR_UNSET,
      'and a colour that is not one')

finish('color mix')
