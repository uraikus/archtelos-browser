// CSS Counter Styles 3.
//
// A counter style turns a number into the text of a marker. The
// predefined ones are named systems with fixed symbol lists;
// `@counter-style` lets a page define its own out of the same five
// systems, which is why they share one implementation here: a
// predefined style is a built-in definition and nothing more.
//
// Each check names the value the standard gives for a number, because
// that is the whole content of a numbering system -- and because a
// check that the marker "is not decimal" would pass for any wrong
// answer.
import ../../src/css/cascade.f
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

// A style's marker for a number, by name, the way a stylesheet asks
// for it.
text func markerOf(style:text, n:int) {
    return counterStyleLabel(style, n)
}

// ---- the predefined numeric styles ---------------------------------------

checkEq(markerOf('decimal', 7), '7', 'decimal is the number itself')

checkEq(markerOf('decimal-leading-zero', 7), '07', 'decimal-leading-zero pads to two digits')
checkEq(markerOf('decimal-leading-zero', 10), '10', 'and stops padding once there are two')
checkEq(markerOf('decimal-leading-zero', 100), '100', 'and never truncates')

// ---- the alphabetic styles -----------------------------------------------
// Alphabetic numbering is bijective: after the last letter it starts
// again with two, so 26 is the last single letter and 27 the first
// double.

checkEq(markerOf('lower-alpha', 1), 'a', 'lower-alpha starts at a')
checkEq(markerOf('lower-alpha', 26), 'z', 'and ends its first round at z')
checkEq(markerOf('lower-alpha', 27), 'aa', 'then carries into two letters')
checkEq(markerOf('upper-alpha', 27), 'AA', 'as does upper-alpha')

checkEq(markerOf('lower-greek', 1), 'α', 'lower-greek starts at alpha')
checkEq(markerOf('lower-greek', 24), 'ω', 'and ends its round at omega, which is the 24th')
checkEq(markerOf('lower-greek', 25), 'αα', 'then carries')

// ---- the additive styles -------------------------------------------------
// Roman numerals are an additive system: each value is written by
// taking the largest symbol not greater than what is left.

checkEq(markerOf('lower-roman', 4), 'iv', 'four is the subtractive form')
checkEq(markerOf('lower-roman', 1990), 'mcmxc', 'and so are the larger ones')
checkEq(markerOf('upper-roman', 1990), 'MCMXC', 'in either case')

// Beyond the range a system can write, the standard falls back to
// decimal rather than inventing a symbol.
checkEq(markerOf('lower-roman', 4000), '4000', 'a number past the roman range falls back to decimal')
checkEq(markerOf('lower-roman', 0), '0', 'as does one below it')

// ---- a style a page defined itself ---------------------------------------

void func defineStyle(rule:text) {
    cascadeReset()
    cascadeAddAuthorSheet(parseStylesheet(rule.toAscii()))
}

// `cyclic` repeats its symbols for ever.
defineStyle('@counter-style ticks { system: cyclic; symbols: "*" "+"; suffix: " " }')
checkEq(markerOf('ticks', 1), '*', 'a cyclic style starts at its first symbol')
checkEq(markerOf('ticks', 2), '+', 'then its second')
checkEq(markerOf('ticks', 3), '*', 'then round again')

// `fixed` runs out and falls back to decimal.
defineStyle('@counter-style two { system: fixed; symbols: "A" "B" }')
checkEq(markerOf('two', 1), 'A', 'a fixed style uses its symbols in turn')
checkEq(markerOf('two', 2), 'B', 'to the end of the list')
checkEq(markerOf('two', 3), '3', 'and then falls back to decimal')

// `symbolic` repeats the symbol rather than the list.
defineStyle('@counter-style sym { system: symbolic; symbols: "*" "+" }')
checkEq(markerOf('sym', 3), '**', 'a symbolic style repeats its symbol on the second round')
checkEq(markerOf('sym', 4), '++', 'for each symbol in turn')

// `alphabetic` is the bijective numbering the letters use.
defineStyle('@counter-style ab { system: alphabetic; symbols: "a" "b" }')
checkEq(markerOf('ab', 3), 'aa', 'an alphabetic style carries after its last symbol')

// `numeric` is positional, so its first symbol is a zero digit.
defineStyle('@counter-style bin { system: numeric; symbols: "0" "1" }')
checkEq(markerOf('bin', 5), '101', 'a numeric style writes the number in its own base')

// `additive` writes a number as a sum of its symbols.
defineStyle('@counter-style add { system: additive; additive-symbols: 5 "V", 1 "I" }')
checkEq(markerOf('add', 7), 'VII', 'an additive style adds its symbols largest first')

// `pad` fills to a width with a symbol, and `negative` wraps a
// negative number.
defineStyle('@counter-style padded { system: numeric; symbols: "0" "1" "2" "3" "4" '
    + '"5" "6" "7" "8" "9"; pad: 3 "0" }')
checkEq(markerOf('padded', 7), '007', 'pad fills to the width it names')
checkEq(markerOf('padded', 1234), '1234', 'and never truncates')

defineStyle('@counter-style neg { system: numeric; symbols: "0" "1" "2" "3" "4" '
    + '"5" "6" "7" "8" "9"; negative: "(" ")" }')
checkEq(markerOf('neg', -5), '(5)', 'negative wraps a negative number in both its parts')

// An undefined name falls back to decimal rather than drawing nothing.
cascadeReset()
checkEq(markerOf('nosuchstyle', 9), '9', 'an undefined counter style falls back to decimal')

// ---- the marker a list item actually gets --------------------------------
// The engine above is only half of it: the marker has to reach the box
// that draws it, which is a different question and the one that would
// catch the generator being right and unwired.

text func markerDrawnFor(sheet:text) {
    cascadeReset()
    cssViewportWidth = 400
    Node doc = parseHtmlText('<html><body><ol><li>x</li><li>x</li></ol></body></html>')
    cascadeAddAuthorSheet(parseStylesheet(sheet.toAscii()))
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box root = layoutDocument(doc, 400)
    arr[Box] items = []
    collectBoxesForTag(root, 'li', items)
    Style s = items[1].style
    if s.listStyleName == '' { return '' }
    return counterStyleLabel(s.listStyleName, items[1].listIndex)
}

checkEq(markerDrawnFor('ol { list-style-type: decimal-leading-zero }'), '02',
        'a predefined counter style reaches the second list item')
checkEq(markerDrawnFor('@counter-style ticks { system: cyclic; symbols: "*" "+" } '
    + 'ol { list-style-type: ticks }'), '+',
        'and so does one the page defined itself')

finish('counter styles')
