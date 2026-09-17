// The bidirectional algorithm (UAX #9).
//
// Hebrew and Arabic render here -- the decoder, the DOM, layout and the
// painter all carry them -- but in logical order, which for a
// right-to-left script is backwards on the screen. This is the pass
// that puts a line into visual order.
//
// Every check is a rule of the standard asked directly, because the
// rules are what the algorithm is: a check that "שלום" comes out
// reversed would pass for an implementation that reverses everything.
import ../../src/util/bidi.f
import ../assert.f

// Two Hebrew letters, two Arabic, and the ASCII the rules mix them with.
text ALEF = 'א'
text BET = 'ב'
text ARABIC_ALEF = 'ا'

// ---- classification ------------------------------------------------------

checkEqInt(bidiClass('a'.charCodeAt(0)), BIDI_L, 'a Latin letter is strongly left-to-right')
checkEqInt(bidiClass(ALEF.charCodeAt(0)), BIDI_R, 'a Hebrew letter is strongly right-to-left')
checkEqInt(bidiClass(ARABIC_ALEF.charCodeAt(0)), BIDI_AL, 'an Arabic letter is Arabic-letter')
checkEqInt(bidiClass('5'.charCodeAt(0)), BIDI_EN, 'an ASCII digit is a European number')
checkEqInt(bidiClass('٠'.charCodeAt(0)), BIDI_AN, 'an Arabic-Indic digit is an Arabic number')
checkEqInt(bidiClass(' '.charCodeAt(0)), BIDI_WS, 'a space is whitespace')
checkEqInt(bidiClass('!'.charCodeAt(0)), BIDI_ON, 'punctuation is other-neutral')
checkEqInt(bidiClass('日'.charCodeAt(0)), BIDI_L, 'a CJK ideograph is left-to-right')

// ---- levels --------------------------------------------------------------
// The level decides the direction: even is left-to-right, odd is
// right-to-left.

arr[int] latin = bidiLevels('abc', 0)
checkEqInt(latin.length, 3, 'a level for every character')
checkEqInt(latin[0], 0, 'Latin in a left-to-right paragraph is level 0')
checkEqInt(latin[2], 0, 'throughout')

arr[int] hebrew = bidiLevels(ALEF + BET, 0)
checkEqInt(hebrew[0], 1, 'Hebrew in a left-to-right paragraph is level 1')
checkEqInt(hebrew[1], 1, 'throughout')

arr[int] latinInRtl = bidiLevels('abc', 1)
checkEqInt(latinInRtl[0], 2, 'Latin in a right-to-left paragraph is level 2')

arr[int] hebrewInRtl = bidiLevels(ALEF + BET, 1)
checkEqInt(hebrewInRtl[0], 1, 'and Hebrew in one is level 1')

// W7: a European number after a left-to-right strong type becomes
// left-to-right itself, so it does not break the run.
arr[int] afterLatin = bidiLevels('a1', 0)
checkEqInt(afterLatin[1], 0, 'a digit after Latin stays at the Latin level')

// W2 and I1: a European number after an Arabic letter is an Arabic
// number, which in a left-to-right paragraph sits at level 2 -- inside
// the right-to-left run but read left to right itself.
arr[int] afterArabic = bidiLevels(ARABIC_ALEF + '1', 0)
checkEqInt(afterArabic[0], 1, 'the Arabic letter is level 1')
checkEqInt(afterArabic[1], 2, 'and the number after it level 2')

// N1: neutrals between two strongs of the same direction take it.
arr[int] neutralBetween = bidiLevels(ALEF + ' ' + BET, 0)
checkEqInt(neutralBetween[1], 1, 'a space between two Hebrew letters is right-to-left')

// N2: neutrals between strongs of different directions take the
// paragraph's own direction instead.
arr[int] neutralBetweenBoth = bidiLevels('a ' + ALEF, 0)
checkEqInt(neutralBetweenBoth[1], 0, 'a space between Latin and Hebrew takes the paragraph')
arr[int] neutralRtl = bidiLevels('a ' + ALEF, 1)
checkEqInt(neutralRtl[1], 1, 'which in a right-to-left paragraph is the other way')

// ---- reordering (L2) -----------------------------------------------------
// The visual order of the character positions, highest level first.

checkEq(bidiVisual('abc', 0), 'abc', 'left-to-right text is not reordered')
checkEq(bidiVisual(ALEF + BET, 0), BET + ALEF, 'a Hebrew run is reversed')
checkEq(bidiVisual(ALEF + BET, 1), BET + ALEF, 'in either paragraph direction')

// A Latin run between two Hebrew ones: each Hebrew run reverses in
// place and the Latin keeps its own order. A single Hebrew letter
// either side would not show this, because reversing a run of one is
// no reordering at all.
checkEq(bidiVisual(ALEF + BET + 'ab' + ALEF + BET, 0), BET + ALEF + 'ab' + BET + ALEF,
        'each Hebrew run reverses while the Latin between them does not')

// The case that needs the levels rather than a single reversal: a
// Latin run inside a right-to-left paragraph. The whole line reverses
// at level 1 and the Latin reverses again at level 2, which puts it
// back in its own order -- a plain reversal of the line would leave it
// backwards.
checkEq(bidiVisual(ALEF + BET + 'ab', 1), 'ab' + BET + ALEF,
        'a Latin run in a right-to-left paragraph keeps its order while the line reverses')

// Two runs in a left-to-right paragraph: the Latin stays put and the
// Hebrew reverses in place.
checkEq(bidiVisual('ab' + ALEF + BET, 0), 'ab' + BET + ALEF,
        'the runs keep their places in a left-to-right paragraph')

// The same content in a right-to-left paragraph: the runs swap.
checkEq(bidiVisual('ab' + ALEF + BET, 1), BET + ALEF + 'ab',
        'and swap in a right-to-left one')

// A number inside Hebrew reads left to right even though the letters
// around it read right to left.
checkEq(bidiVisual(ALEF + '12' + BET, 0), BET + '12' + ALEF,
        'a number inside a Hebrew run keeps its digits in order')

// Reordering never loses or repeats a character.
text mixed = 'ab ' + ALEF + BET + ' 12!'
text visual = bidiVisual(mixed, 0)
checkEqInt(visual.length, mixed.length, 'reordering is a permutation, so the length is the same')

// A string with nothing right-to-left in it is returned untouched,
// which is the check that the common case costs nothing.
check(!bidiNeedsReorder('hello, world 123'), 'plain text needs no reordering')
check(bidiNeedsReorder('hello ' + ALEF), 'and text with a Hebrew letter does')
check(bidiNeedsReorder('hello ' + ARABIC_ALEF), 'as does text with an Arabic one')

// ---- unicode-bidi: bidi-override -----------------------------------------
// An override ignores every character's own class, so even Latin comes
// out backwards in a right-to-left paragraph. This is the one case
// where reversing the line outright is right, and the check that it is
// not what the ordinary algorithm does.

checkEq(bidiVisualOverride('abc', 1), 'cba', 'an override reverses Latin in a right-to-left run')
checkEq(bidiVisualOverride('abc', 0), 'abc', 'and leaves it alone in a left-to-right one')
check(bidiVisual('abc', 1) != bidiVisualOverride('abc', 1),
      'which is not what the algorithm does without the override')

finish('bidi')
