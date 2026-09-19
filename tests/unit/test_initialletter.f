// `initial-letter` (CSS Inline 3): a drop cap on ::first-letter.
//
// Every number below is Chromium 141 on a 300px paragraph at
// 20px/30px monospace, recorded in todo.md under "What
// `initial-letter` was measured to be". The geometry is two rules:
//
//   - the SIZE is where the letter's baseline sits. Its cap top is the
//     cap top of the block's first line and its baseline is the
//     baseline of line `size`, so its cap height grows by exactly one
//     line-height for each line it spans;
//   - the SINK is how many lines are shortened, and it is not the
//     size. It defaults to floor(size). What is left over goes above
//     the text: the paragraph grows by `size - sink` lines and the
//     text begins that many lines down.
//
// A five-line paragraph is 150 tall at `2` and `3`, 180 at `2 1`, 210
// at `3 1` and `4 2` -- and the lines indented are 2, 3, 1, 1 and 2.
// That table is the assertion, and none of it depends on font metrics.
//
// The letter's ADVANCE does. Chromium's monospace cap ratio is 0.717
// and this engine's FONT_CAP is 0.70, so inverting the constant to
// find a font size overshoots by about four per cent and the letter
// comes out a little wider than Chromium's 36, 61 and 86. What does
// not depend on the constant is that the advance grows by the same
// step for each line the letter spans, because the font size does --
// so that is asserted exactly, and the step itself only within the
// band the ratios imply. Correcting FONT_CAP is a separate
// measurement, recorded in todo.md.

import ../../src/browser/page.f
import ../assert.f

text letterPage = '<!doctype html><html><head><style>'
    + 'body{margin:0;font:20px/30px monospace}'
    + 'p{width:400px;margin:0}'

// Twenty-five four-letter words, at 400px and 12px a character. Every
// word is the same length so that where the lines break is arithmetic
// rather than luck, and there are five lines of them under every
// declaration below -- including the ones where four lines lose 90px
// to the letter. A fixture that gained a line when the text was
// indented would be measuring its own slack rather than the property.
text letterWords = 'aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj '
    + 'kkkk llll mmmm nnnn oooo pppp qqqq rrrr ssss tttt '
    + 'uuuu vvvv wwww xxxx yyyy'

Box func boxById(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'p', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

Page func capPage(decl:text) {
    text rule = decl == null ? '' : 'p::first-letter{initial-letter:' + decl + '}'
    return pageFromHtml(letterPage + rule + '</style></head><body><p id="p">'
                        + letterWords + '</p></body></html>', 'about:blank', 600)
}

// How many of the block's lines are shortened by the letter beside them.
int func indented(p:Box) {
    int n = 0
    for int i = 0, i < p.lines.length, i++ {
        if p.lines[i].x > 0 { n++ }
    }
    return n
}

// The y of the first line with text on it.
int func textTop(p:Box) {
    return p.lines.length == 0 ? -1 : p.lines[0].y
}

// The drop cap's own box: the one floating child of the paragraph.
Box func capBox(p:Box) {
    for int i = 0, i < p.children.length, i++ {
        if p.children[i].w > 0 && p.children[i].h > 0 { return p.children[i] }
    }
    return null
}

// ---- the control -------------------------------------------------------
Box plain = boxById(capPage(null).root, 'p')
checkEqInt(plain.lines.length, 5, 'the words take five lines')
checkEqInt(plain.h, 150, 'which is 150px at a 30px line height')
checkEqInt(indented(plain), 0, 'and none of them is shortened')

Box normalCap = boxById(capPage('normal').root, 'p')
checkEqInt(normalCap.h, plain.h, '`initial-letter: normal` is the control again')
checkEqInt(indented(normalCap), 0, 'and shortens no line')

// ---- the measured table ------------------------------------------------
Box c2 = boxById(capPage('2').root, 'p')
checkEqInt(c2.h, 150, 'size 2 leaves the paragraph five lines tall')
checkEqInt(indented(c2), 2, 'and shortens two of them')
checkEqInt(textTop(c2), 0, 'the text starts on the first line')

Box c3 = boxById(capPage('3').root, 'p')
checkEqInt(c3.h, 150, 'size 3 leaves the paragraph five lines tall')
checkEqInt(indented(c3), 3, 'and shortens three of them')
checkEqInt(textTop(c3), 0, 'the text starts on the first line')

Box c21 = boxById(capPage('2 1').root, 'p')
checkEqInt(c21.h, 180, '`2 1` grows the paragraph by one line')
checkEqInt(indented(c21), 1, 'the sink alone says how many lines are shortened')
checkEqInt(textTop(c21), 30, 'and the text begins one line down')

Box c31 = boxById(capPage('3 1').root, 'p')
checkEqInt(c31.h, 210, '`3 1` grows the paragraph by two lines')
checkEqInt(indented(c31), 1, 'and still shortens only one')
checkEqInt(textTop(c31), 60, 'the text begins two lines down')

Box c42 = boxById(capPage('4 2').root, 'p')
checkEqInt(c42.h, 210, '`4 2` grows the paragraph by two lines as well')
checkEqInt(indented(c42), 2, 'and shortens two')
checkEqInt(textTop(c42), 60, 'the text begins two lines down')

// The two ways of saying the same thing have to agree: the sink
// defaults to floor(size), so `3` and `3 3` are one declaration.
Box c33 = boxById(capPage('3 3').root, 'p')
checkEqInt(c33.h, c3.h, '`3 3` is `3` written out')
checkEqInt(indented(c33), indented(c3), 'and shortens the same lines')
checkEqInt(textTop(c33), textTop(c3), 'and starts its text in the same place')

// ---- the letter's own box ----------------------------------------------
Box cap2 = capBox(c2)
Box cap3 = capBox(c3)
Box cap4 = capBox(boxById(capPage('4').root, 'p'))
check(cap2 != null && cap3 != null && cap4 != null, 'each drop cap has a box')

checkEqInt(cap3.w - cap2.w, cap4.w - cap3.w,
           'the advance grows by the same step for each line the letter spans')
int step = cap3.w - cap2.w
check(step >= 22 && step <= 28,
      `that step is Chromium's 25px within the cap-ratio band, got ${step}`)

// The box is as tall as the lines it spans, which is what puts its
// baseline on the baseline of line `size`.
checkEqInt(cap2.h, 60, 'the size 2 letter is two lines tall')
checkEqInt(cap3.h, 90, 'the size 3 letter is three lines tall')
checkEqInt(cap4.h, 120, 'the size 4 letter is four lines tall')

// It floats at the start, and it rises above the lines it shortens by
// exactly the lines the paragraph grew by.
checkEqInt(cap3.x, 0, 'the letter sits at the start of the paragraph')
checkEqInt(cap3.y, c3.y, 'and at its top when nothing was pushed down')
Box cap31 = capBox(c31)
checkEqInt(cap31.y, c31.y, '`3 1` puts the letter at the top too')
checkEqInt(cap31.h, 90, 'three lines tall, though only one is shortened')

// The lines it does not shorten have the whole paragraph.
checkEqInt(c31.lines[0].x, cap31.w, 'the one shortened line starts past the letter')
check(c31.lines[0].w < 400, 'and is narrower than the paragraph')
checkEqInt(c31.lines[1].w, 400, 'the next line has the whole paragraph')

finish('initial letter')
