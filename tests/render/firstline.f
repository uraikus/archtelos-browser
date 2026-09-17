// `::first-line` restyles the characters that end up on the first line
// of a block (CSS Pseudo-Elements 4 §3.2). The geometry it can change
// is checked in tests/unit/test_pseudo.f against Chromium's numbers;
// what is left is whether the style reaches the canvas, which is a
// pixel question.
//
// Every check here is an agreement between two ways of reaching the
// same pixel rather than a colour worked out by hand:
//
//   p::first-line { color: red }, first line   ==  p { color: red }
//   p::first-line { color: red }, second line  ==  p with no rule
//
// Neither side is known in advance, and a ::first-line that painted
// nothing would fail the first, while one that painted the whole
// paragraph would fail the second. The last pair of checks confirms the
// two references differ at all, because two identical references would
// grade an unimplemented feature as correct.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace">'
text para = '<p id="p" style="width:200px;margin:0">'
    + 'one two three four five six seven eight nine ten</p></body>'

// One painted row of the canvas, so two renders can be compared without
// either one's colours being written down here.
arr[color] func rowOf(y:int, x0:int, x1:int) {
    arr[color] out = []
    for int x = x0, x < x1, x++ { out.push(getPixelColor(x, y)) }
    return out
}

int func rowDiffs(a:arr[color], b:arr[color]) {
    int n = 0
    for int i = 0, i < a.length && i < b.length, i++ {
        if !(a[i] == b[i]) { n++ }
    }
    return n
}

arr[color] func renderRows(html:text, y:int) {
    Page p = pageFromHtml(html, 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
    return rowOf(y, 0, 200)
}

// The band each line is painted in: the glyphs of a 16px/20px line sit
// a few pixels below its top, so a row through the middle of each is
// what carries ink.
const int LINE1 = 12
const int LINE2 = 32

text ruleFirstLine = '<style>p::first-line { color: #ff0000 }</style>'
text ruleWhole = '<style>p { color: #ff0000 }</style>'

arr[color] flLine1 = renderRows(head + ruleFirstLine + para, LINE1)
arr[color] flLine2 = renderRows(head + ruleFirstLine + para, LINE2)
arr[color] redLine1 = renderRows(head + ruleWhole + para, LINE1)
arr[color] redLine2 = renderRows(head + ruleWhole + para, LINE2)
arr[color] plainLine1 = renderRows(head + para, LINE1)
arr[color] plainLine2 = renderRows(head + para, LINE2)

// The instrument first: the two references have to differ, or every
// check below passes whatever the engine does.
check(rowDiffs(redLine1, plainLine1) > 0, 'a red paragraph and a black one differ on the first line')
check(rowDiffs(redLine2, plainLine2) > 0, 'and on the second')

checkEqInt(rowDiffs(flLine1, redLine1), 0, 'the first line paints as a red paragraph does')
checkEqInt(rowDiffs(flLine2, plainLine2), 0, 'the second line paints as a black one does')
check(rowDiffs(flLine1, plainLine1) > 0, 'so the rule reached the first line')
check(rowDiffs(flLine2, redLine2) > 0, 'and stopped there')

// The same question of a rule that changes the metrics: a bigger first
// line must paint where a paragraph set entirely in that size paints,
// on its first line, and nowhere near it on the second.
text bigFirst = '<style>p::first-line { font-size: 24px; line-height: 30px }</style>'
text bigWhole = '<style>p { font-size: 24px; line-height: 30px }</style>'
const int BIG1 = 18
arr[color] bigFlLine1 = renderRows(head + bigFirst + para, BIG1)
arr[color] bigAllLine1 = renderRows(head + bigWhole + para, BIG1)
arr[color] bigPlainLine1 = renderRows(head + para, BIG1)
check(rowDiffs(bigAllLine1, bigPlainLine1) > 0, 'a 24px paragraph and a 16px one differ on the first line')
checkEqInt(rowDiffs(bigFlLine1, bigAllLine1), 0, 'a bigger first line is set exactly as a bigger paragraph is')

finish('first line')
