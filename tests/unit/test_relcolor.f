// CSS Color 5's relative colour syntax: `rgb(from <color> r g b)` and
// its siblings, where the origin colour's own channels are in scope as
// names.
//
// Every expected pixel is Chromium 141's, read by setting the colour as
// a canvas fill. The strongest checks here need no reference: writing
// each channel back under its own name must give the colour you started
// with, in every function, because the conversion into the space and
// the conversion out of it are inverses.
import ../../src/util/color.f
import ../assert.f

int relBlack = COLOR_BLACK

void func relIs(css:ascii, r:int, g:int, b:int, label:text) {
    int got = parseCssColor(css, relBlack)
    int want = packColor(r, g, b, 255)
    if got == want { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: expected rgb(${r}, ${g}, ${b}), got rgb(${colorRed(got)}, ${colorGreen(got)}, ${colorBlue(got)}) a=${colorAlpha(got)}`)
    }
}

void func relSame(a:ascii, b:ascii, label:text) {
    int x = parseCssColor(a, relBlack)
    int y = parseCssColor(b, relBlack)
    if x == y && x != COLOR_UNSET { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: rgb(${colorRed(x)}, ${colorGreen(x)}, ${colorBlue(x)}) a=${colorAlpha(x)} vs rgb(${colorRed(y)}, ${colorGreen(y)}, ${colorBlue(y)}) a=${colorAlpha(y)}`)
    }
}

// ---- the identity, in every function ------------------------------------
// The channels written back under their own names is the origin colour.
// A conversion wrong in one direction only fails this at once.
relSame('rgb(from red r g b)', 'red', 'rgb passes its channels through')
relSame('hsl(from red h s l)', 'red', 'and so does hsl')
relSame('hwb(from red h w b)', 'red', 'and hwb')
relSame('lab(from red l a b)', 'red', 'and lab')
relSame('lch(from red l c h)', 'red', 'and lch')
relSame('oklab(from red l a b)', 'red', 'and oklab')
relSame('oklch(from red l c h)', 'red', 'and oklch')
relSame('color(from red srgb r g b)', 'red', 'and color() in srgb')
relSame('color(from red srgb-linear r g b)', 'red', 'and in srgb-linear')
// The xyz spaces name their channels x, y and z, so `r g b` is not a
// query about them at all.
relSame('color(from red xyz x y z)', 'red', 'and in xyz, whose channels are x y z')
relSame('color(from red xyz-d50 x y z)', 'red', 'and in xyz-d50')
check(parseCssColor('color(from red xyz r g b)', relBlack) == COLOR_UNSET,
      'xyz has no channel called r')
relSame('color(from red display-p3 r g b)', 'red', 'and in display-p3')
relSame('color(from red a98-rgb r g b)', 'red', 'and in a98-rgb')
relSame('color(from red prophoto-rgb r g b)', 'red', 'and in prophoto-rgb')
relSame('color(from red rec2020 r g b)', 'red', 'and in rec2020')
relSame('rgb(from #336699 r g b)', '#336699', 'a colour that is not a primary too')
relSame('oklch(from rebeccapurple l c h)', 'rebeccapurple', 'in oklch as well')

// ---- the channels are values, and can be moved about ---------------------
relIs('rgb(from red g b r)', 0, 0, 255, 'the channels can be written in another order')
relIs('rgb(from red 0 g b)', 0, 0, 0, 'and replaced by numbers')
relIs('rgb(from rgb(20 40 60) r g b)', 20, 40, 60, 'the origin may be a function itself')
relIs('rgb(from red none g b)', 0, 0, 0, 'and `none` is a channel of zero')

// ---- arithmetic on a channel --------------------------------------------
relIs('rgb(from red calc(r / 2) g b)', 128, 0, 0, 'a channel divided')
relIs('rgb(from red calc(r * 0.5) g b)', 128, 0, 0, 'and multiplied, which is the same')
relIs('hsl(from red calc(h + 120) s l)', 0, 255, 0, 'a hue turned a third of the way round')
relIs('oklch(from red calc(l * 0.5) c h)', 137, 0, 0, 'an Oklab lightness halved')
relSame('rgb(from red calc(r / 2) g b)', 'rgb(from red calc(r * 0.5) g b)',
        'two ways of halving a channel land on one colour')

// ---- the units each function counts its channels in ---------------------
// rgb is out of 255, hsl is out of a hundred, oklch's lightness is out
// of one: a percentage in each means the same fraction of a different
// number, and the check is that replacing a channel with its own value
// written out changes nothing.
relIs('hsl(from red h 50% l)', 191, 64, 64, 'a saturation of half')
relIs('oklch(from red l 0 h)', 136, 136, 136, 'no chroma at all is a grey')
relSame('rgb(from red 255 g b)', 'red', 'rgb counts to 255')
relSame('rgb(from red 100% g b)', 'red', 'which is what a full percentage means')
relSame('hsl(from red h 100% l)', 'red', 'hsl counts to a hundred')
relSame('oklch(from red calc(l * 1) c h)', 'red',
        'and multiplying a channel by one leaves it where it was')

// ---- alpha ---------------------------------------------------------------
check(parseCssColor('rgb(from red r g b / 50%)', relBlack) == packColor(255, 0, 0, 128),
      'an alpha written after the slash')
relSame('rgb(from #ff000080 r g b / alpha)', '#ff000080', 'and the origin alpha under its own name')

// ---- what must be refused ------------------------------------------------
check(parseCssColor('rgb(from bogus r g b)', relBlack) == COLOR_UNSET,
      'an origin colour that is not one')
check(parseCssColor('rgb(from red r g)', relBlack) == COLOR_UNSET,
      'too few channels')
check(parseCssColor('color(from red nonesuch r g b)', relBlack) == COLOR_UNSET,
      'an unknown colour space')
check(parseCssColor('rgb(from red r g nonesuch)', relBlack) == COLOR_UNSET,
      'and a channel name from another function')

finish('relative color')
