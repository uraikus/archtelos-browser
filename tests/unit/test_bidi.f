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

// ---- the explicit codes (the X rules) ------------------------------------
// The nine directional formatting characters. Every expected string
// below is Chromium 141's, read as the left edge of each character's
// own box and sorted: a character the browser gives no width -- which
// is every one of these nine -- is dropped, which is what this returns
// as well.
text GIMEL = 'ג'
text DALET = 'ד'
text HE_ = 'ה'
text HEB = ALEF + BET + GIMEL
text HEB_R = GIMEL + BET + ALEF
text HEB2 = DALET + HE_
text LRE = bidiControl(BIDI_CP_LRE)
text RLE = bidiControl(BIDI_CP_RLE)
text PDF = bidiControl(BIDI_CP_PDF)
text LRO = bidiControl(BIDI_CP_LRO)
text RLO = bidiControl(BIDI_CP_RLO)
text LRI = bidiControl(BIDI_CP_LRI)
text RLI = bidiControl(BIDI_CP_RLI)
text FSI = bidiControl(BIDI_CP_FSI)
text PDI = bidiControl(BIDI_CP_PDI)

// A control character is not drawn, so it is not in the visual order.
checkEqInt(bidiVisual('a' + RLE + 'b' + PDF + 'c', 0).length, 3,
           'the formatting characters are not drawn')

// RLE opens a right-to-left embedding: inside it the base direction is
// right-to-left, so a Latin word and a Hebrew one swap places. The
// same text without the RLE is the check that the code did the work.
checkEq(bidiVisual('x' + RLE + 'ab ' + HEB + PDF + 'y', 0), 'x' + HEB_R + ' ab' + 'y',
        'RLE makes its content right-to-left')
checkEq(bidiVisual('xab ' + HEB + 'y', 0), 'xab ' + HEB_R + 'y',
        'and without it the paragraph direction stands')
check(bidiVisual('x' + RLE + 'ab ' + HEB + PDF + 'y', 0)
      != bidiVisual('xab ' + HEB + 'y', 0), 'which are not the same order')

// LRE is the mirror of it, inside a right-to-left paragraph.
checkEq(bidiVisual('x' + LRE + HEB + ' ab' + PDF + 'y', 1), 'x' + HEB_R + ' ab' + 'y',
        'LRE makes its content left-to-right')
checkEq(bidiVisual('x' + HEB + ' aby', 1), 'aby ' + HEB_R + 'x',
        'and without it the paragraph direction stands there too')

// An embedding with no PDF runs to the end of the paragraph (X8).
checkEq(bidiVisual('x' + RLE + 'ab ' + HEB, 0), 'x' + HEB_R + ' ab',
        'an unterminated embedding runs to the end')

// The overrides ignore a character's own class: RLO lays Latin out
// backwards, LRO lays Hebrew out forwards.
checkEq(bidiVisual('a' + RLO + 'bcd' + PDF + 'e', 0), 'adcbe',
        'RLO reverses the Latin inside it')
checkEq(bidiVisual('a' + LRO + HEB + PDF + 'b', 0), 'a' + HEB + 'b',
        'and LRO leaves Hebrew in its logical order')

// An isolate does the same to its own content as an embedding.
checkEq(bidiVisual('x' + RLI + 'ab ' + HEB + PDI + 'y', 0), 'x' + HEB_R + ' ab' + 'y',
        'RLI makes its content right-to-left')

// FSI takes its direction from the first strong character inside it,
// which is the whole of rules P2 and P3 applied to a span.
checkEq(bidiVisual('a' + FSI + HEB + '!x' + PDI + 'b', 0), 'ax!' + HEB_R + 'b',
        'FSI on Hebrew content is right-to-left')
checkEq(bidiVisual('a' + FSI + 'bc ' + HEB + PDI + 'd', 0), 'abc ' + HEB_R + 'd',
        'and FSI on Latin content is left-to-right')

// A run of them nested inside one another.
checkEq(bidiVisual('a' + RLE + 'b ' + HEB + ' ' + LRE + HEB2 + ' c' + PDF + ' d' + PDF + 'e', 0),
        'a' + HE_ + DALET + ' c d ' + HEB_R + ' be',
        'an embedding inside an embedding')

// ---- unicode-bidi --------------------------------------------------------
// CSS Writing Modes 3 defines each value as the formatting characters
// it wraps the element's text in, and that is how it is implemented:
// one algorithm, and a property that speaks to it in its own terms.
// Chromium answers the six values on a `direction: rtl` inline inside a
// left-to-right block, and on a `direction: ltr` one inside a
// right-to-left block.

// `normal` opens no embedding at all, so the inline's own `direction`
// does not reach the ordering: the paragraph's stands.
checkEq(bidiVisualStyled('ab ' + HEB, 0, UBIDI_NORMAL, true), 'ab ' + HEB_R,
        'normal leaves the paragraph direction alone')
checkEq(bidiVisualStyled(HEB + ' ab', 1, UBIDI_NORMAL, false), 'ab ' + HEB_R,
        'in either direction')

// `embed` opens one, so it does.
checkEq(bidiVisualStyled('ab ' + HEB, 0, UBIDI_EMBED, true), HEB_R + ' ab',
        'embed opens a right-to-left embedding')
checkEq(bidiVisualStyled(HEB + ' ab', 1, UBIDI_EMBED, false), HEB_R + ' ab',
        'and a left-to-right one the other way about')
check(bidiVisualStyled('ab ' + HEB, 0, UBIDI_EMBED, true)
      != bidiVisualStyled('ab ' + HEB, 0, UBIDI_NORMAL, true),
      'which is the difference between embed and normal')

// `isolate` orders its own content exactly as `embed` does; what it
// changes is how the text around it sees it, which is a line this
// engine reorders one fragment at a time.
checkEq(bidiVisualStyled('ab ' + HEB, 0, UBIDI_ISOLATE, true),
        bidiVisualStyled('ab ' + HEB, 0, UBIDI_EMBED, true),
        'isolate orders its own content as embed does')

// The two overrides ignore every character's class.
checkEq(bidiVisualStyled('ab ' + HEB, 0, UBIDI_OVERRIDE, true), HEB_R + ' ba',
        'bidi-override lays everything out right-to-left')
checkEq(bidiVisualStyled(HEB + ' ab', 1, UBIDI_OVERRIDE, false), HEB + ' ab',
        'and left-to-right the other way about')
checkEq(bidiVisualStyled('ab ' + HEB, 0, UBIDI_ISOLATE_OVERRIDE, true),
        bidiVisualStyled('ab ' + HEB, 0, UBIDI_OVERRIDE, true),
        'isolate-override orders its own content as bidi-override does')

// `plaintext` ignores the inline's direction and the paragraph's alike,
// and takes the first strong character instead. In a left-to-right
// paragraph holding Hebrew first, that is the one value that differs
// from every other.
checkEq(bidiVisualStyled(HEB + ' ab', 0, UBIDI_PLAINTEXT, false), 'ab ' + HEB_R,
        'plaintext takes its direction from the first strong character')
checkEq(bidiVisualStyled(HEB + ' ab', 0, UBIDI_NORMAL, false), HEB_R + ' ab',
        'where normal takes the paragraph')
check(bidiVisualStyled(HEB + ' ab', 0, UBIDI_PLAINTEXT, false)
      != bidiVisualStyled(HEB + ' ab', 0, UBIDI_NORMAL, false),
      'so the two differ on the same text')
checkEq(bidiVisualStyled('ab ' + HEB, 0, UBIDI_PLAINTEXT, true), 'ab ' + HEB_R,
        'and a Latin first character makes it left-to-right whatever direction says')

finish('bidi')
