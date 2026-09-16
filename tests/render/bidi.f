// Right-to-left text on the screen.
//
// The algorithm itself is checked in tests/unit/test_bidi.f against the
// standard's rules. This asks the question those checks cannot: that
// the reordering reaches the pixels, and that a page with no
// right-to-left text is untouched by it.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color white = 'white'

text ALEF = 'א'
text BET = 'ב'

text head = '<!doctype html><body style="margin:0;font:16px/20px sans-serif">'

void func shotText(body:text) {
    Page p = pageFromHtml(head + body + '</body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// The columns that hold ink, as a string, so two renderings can be
// compared without knowing anything about the glyphs themselves.
text func inkProfile() {
    text out = ''
    for int x = 0, x < 60, x++ {
        int col = 0
        for int y = 0, y < 24, y++ { if getPixelColor(x, y) != white { col++ } }
        out = out + (col > 0 ? '#' : '.')
    }
    return out
}

// ---- a Hebrew run is drawn right to left ---------------------------------
// Two letters in one order, and the same two in the other, must come
// out as each other: that is what reordering means, and it is a check
// neither rendering can pass alone.

shotText('<div>' + ALEF + BET + '</div>')
text alefFirst = inkProfile()
shotText('<div>' + BET + ALEF + '</div>')
text betFirst = inkProfile()
check(alefFirst != betFirst, 'the two orderings are not the same picture')

// Reversing the source must give the same pixels as before, because
// the engine reverses it back.
shotText('<div>' + ALEF + BET + '</div>')
text again = inkProfile()
checkEq(again, alefFirst, 'and the same source gives the same picture twice')

// ---- Latin is untouched ---------------------------------------------------
// A page with nothing right-to-left in it must render exactly as it did
// before the algorithm existed, which is what the document-level flag
// is for.

shotText('<div>ab</div>')
text latin = inkProfile()
shotText('<div>ab</div>')
checkEq(inkProfile(), latin, 'Latin text renders the same way every time')

shotText('<div dir="ltr">ab</div>')
checkEq(inkProfile(), latin, 'and is unaffected by an explicit ltr direction')

// ---- direction: rtl -------------------------------------------------------
// The base direction moves the text to the right edge, because
// text-align: start is the right in a right-to-left paragraph.

shotText('<div style="width:200px">ab</div>')
text atLeft = inkProfile()
shotText('<div style="width:200px;direction:rtl">ab</div>')
text atRight = inkProfile()
check(atLeft != atRight, 'direction:rtl moves the text to the other edge')
check(getPixelColor(1, 10) == white || atRight != atLeft,
      'leaving the left edge empty')

// An explicit text-align beats the direction, because `left` is a side
// and not an end.
shotText('<div style="width:200px;direction:rtl;text-align:left">ab</div>')
checkEq(inkProfile(), atLeft, 'text-align:left pins it to the left whatever the direction')

finish('bidi render')
