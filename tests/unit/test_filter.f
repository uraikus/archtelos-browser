// CSS Filter Effects 1 §8, the colour functions. Run with:
// festina run tests/unit/test_filter.f
//
// Every row below is Chromium 141's own answer, taken from a canvas
// with `ctx.filter` and `getImageData`, which needs no screenshot. The
// table is ground truth from another engine rather than from this one,
// so it can fail: an arithmetic slip, a transposed matrix or the wrong
// rounding rule each show up as a channel out by one or more.
import ../../src/util/color.f
import ../assert.f

// Computed rather than written out. A hand-packed constant was wrong
// here by 64,000 on the first run -- the input checks below caught it,
// which is what they are for, but packing them is cheaper than having
// the check.
int C_ORANGE = packColor(200, 100, 50, 255)
int C_RED = packColor(255, 0, 0, 255)
int C_BLUE = packColor(0, 128, 255, 255)

void func checkFilter(c:int, kind:int, amt:float, r:int, g:int, b:int, label:text) {
    int got = colorFilterOne(c, kind, amt)
    checkEqInt(colorRed(got), r, `${label}: red`)
    checkEqInt(colorGreen(got), g, `${label}: green`)
    checkEqInt(colorBlue(got), b, `${label}: blue`)
}

// The three inputs, unfiltered, so a mistake in the constants above
// cannot be mistaken for a mistake in the filters.
checkEqInt(colorRed(C_ORANGE), 200, 'the orange input is 200 red')
checkEqInt(colorGreen(C_ORANGE), 100, 'and 100 green')
checkEqInt(colorBlue(C_ORANGE), 50, 'and 50 blue')
checkEqInt(colorAlpha(C_ORANGE), 255, 'and opaque')
checkEqInt(colorRed(C_RED), 255, 'the red input is 255 red')
checkEqInt(colorGreen(C_BLUE), 128, 'the blue input is 128 green')
checkEqInt(colorBlue(C_BLUE), 255, 'and 255 blue')

// grayscale
checkFilter(C_ORANGE, CFILTER_GRAYSCALE, 1.0, 118, 118, 118, 'grayscale(1) on orange')
checkFilter(C_RED, CFILTER_GRAYSCALE, 1.0, 54, 54, 54, 'grayscale(1) on red')
checkFilter(C_BLUE, CFILTER_GRAYSCALE, 1.0, 110, 110, 110, 'grayscale(1) on blue')
checkFilter(C_ORANGE, CFILTER_GRAYSCALE, 0.5, 159, 109, 84, 'grayscale(.5) on orange')
checkFilter(C_RED, CFILTER_GRAYSCALE, 0.5, 155, 27, 27, 'grayscale(.5) on red')
checkFilter(C_BLUE, CFILTER_GRAYSCALE, 0.5, 55, 119, 182, 'grayscale(.5) on blue')

// sepia
checkFilter(C_ORANGE, CFILTER_SEPIA, 1.0, 165, 147, 114, 'sepia(1) on orange')
checkFilter(C_RED, CFILTER_SEPIA, 1.0, 100, 89, 69, 'sepia(1) on red')
checkFilter(C_BLUE, CFILTER_SEPIA, 1.0, 147, 131, 102, 'sepia(1) on blue')

// saturate
checkFilter(C_ORANGE, CFILTER_SATURATE, 0.0, 118, 118, 118, 'saturate(0) on orange')
checkFilter(C_ORANGE, CFILTER_SATURATE, 2.0, 255, 82, 0, 'saturate(2) on orange')
checkFilter(C_BLUE, CFILTER_SATURATE, 2.0, 0, 146, 255, 'saturate(2) on blue')

// hue-rotate
checkFilter(C_ORANGE, CFILTER_HUEROTATE, 90.0, 50, 146, 35, 'hue-rotate(90deg) on orange')
checkFilter(C_RED, CFILTER_HUEROTATE, 90.0, 0, 91, 0, 'hue-rotate(90deg) on red')
checkFilter(C_BLUE, CFILTER_HUEROTATE, 90.0, 255, 56, 220, 'hue-rotate(90deg) on blue')

// invert
checkFilter(C_ORANGE, CFILTER_INVERT, 1.0, 55, 155, 205, 'invert(1) on orange')
checkFilter(C_ORANGE, CFILTER_INVERT, 0.25, 163, 113, 88, 'invert(.25) on orange')
checkFilter(C_RED, CFILTER_INVERT, 0.25, 191, 63, 63, 'invert(.25) on red')
checkFilter(C_BLUE, CFILTER_INVERT, 0.25, 63, 127, 191, 'invert(.25) on blue')

// brightness
checkFilter(C_ORANGE, CFILTER_BRIGHTNESS, 0.5, 100, 50, 25, 'brightness(.5) on orange')
checkFilter(C_RED, CFILTER_BRIGHTNESS, 0.5, 127, 0, 0, 'brightness(.5) on red')
checkFilter(C_ORANGE, CFILTER_BRIGHTNESS, 1.5, 255, 150, 75, 'brightness(1.5) on orange')
checkFilter(C_BLUE, CFILTER_BRIGHTNESS, 1.5, 0, 192, 255, 'brightness(1.5) on blue')

// contrast
checkFilter(C_ORANGE, CFILTER_CONTRAST, 2.0, 255, 72, 0, 'contrast(2) on orange')
checkFilter(C_ORANGE, CFILTER_CONTRAST, 0.5, 163, 113, 88, 'contrast(.5) on orange')
checkFilter(C_RED, CFILTER_CONTRAST, 0.5, 191, 63, 63, 'contrast(.5) on red')
checkFilter(C_BLUE, CFILTER_CONTRAST, 0.5, 63, 127, 191, 'contrast(.5) on blue')

// The two rounding rules are the thing most easily got wrong, and
// brightness(.5) on red is where they part: 255 * 0.5 is 127.5, which
// truncates to 127 and rounds to 128. A matrix filter at the same
// half-way point goes the other way.
checkEqInt(colorRed(colorFilterOne(C_RED, CFILTER_BRIGHTNESS, 0.5)), 127,
    'a component transfer truncates at the half')

// opacity is a transfer on the alpha channel, and truncates too:
// 255 * 0.5 is 127, 255 * 0.25 is 63 and 255 * 0.7 is 178, all measured.
checkEqInt(colorAlpha(colorFilterOne(C_ORANGE, CFILTER_OPACITY, 0.5)), 127, 'opacity(.5)')
checkEqInt(colorAlpha(colorFilterOne(C_ORANGE, CFILTER_OPACITY, 0.25)), 63, 'opacity(.25)')
checkEqInt(colorAlpha(colorFilterOne(C_ORANGE, CFILTER_OPACITY, 0.7)), 178, 'opacity(.7)')
checkEqInt(colorRed(colorFilterOne(C_ORANGE, CFILTER_OPACITY, 0.5)), 200,
    'and opacity leaves the colour alone')

// An identity amount is the identity, for each function that has one.
checkFilter(C_ORANGE, CFILTER_GRAYSCALE, 0.0, 200, 100, 50, 'grayscale(0) changes nothing')
checkFilter(C_ORANGE, CFILTER_SEPIA, 0.0, 200, 100, 50, 'sepia(0) changes nothing')
checkFilter(C_ORANGE, CFILTER_SATURATE, 1.0, 200, 100, 50, 'saturate(1) changes nothing')
checkFilter(C_ORANGE, CFILTER_INVERT, 0.0, 200, 100, 50, 'invert(0) changes nothing')
checkFilter(C_ORANGE, CFILTER_BRIGHTNESS, 1.0, 200, 100, 50, 'brightness(1) changes nothing')
checkFilter(C_ORANGE, CFILTER_CONTRAST, 1.0, 200, 100, 50, 'contrast(1) changes nothing')
checkFilter(C_ORANGE, CFILTER_HUEROTATE, 0.0, 200, 100, 50, 'hue-rotate(0) changes nothing')

finish('colour filters')
