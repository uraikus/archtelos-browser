// A box cut by a column break, in pixels (CSS Fragmentation 3, CSS
// Multi-column 1 §3.3).
//
// A fixed-height block that does not fit what is left of its column is
// split: the box keeps the first part and `frags` holds the rest, and
// both parts paint. The geometry is checked in tests/unit/test_multicol.f;
// what only pixels can say is that the part in the next column paints its
// background at all, and which of its edges carries a border.
//
// Chromium's own pixels are in todo.md, read with tests/chromium.py on
// the same fixture. `box-decoration-break: slice`, the initial value,
// paints no border across the break and lets the background run to the
// column's end; `clone` paints one. So the two must AGREE everywhere but
// the break edge and differ exactly there, which is the check that earns
// its place: it does not depend on either answer being known in advance
// (CLAUDE.md).
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color red = '#ff0000'
color blue = '#0000ff'
color green = '#00aa00'

// 210 wide, two columns of 100 with a 10 gap, filling to a height of 25:
// the 20-tall block takes the top of the first column and the 30-tall one
// is cut, five at the bottom of the first and twenty-five at the top of
// the second.
text func cutPage(extra:text) {
    return '<!doctype html><body style="margin:0;font:16px/20px monospace">'
        + '<div style="width:210px;column-count:2;column-gap:10px;'
        + 'column-fill:auto;height:25px">'
        + '<div style="height:20px;background:#ff0000"></div>'
        + `<div style="height:30px;background:#0000ff;${extra}"></div>`
        + '</div></body>'
}

void func paintCut(extra:text) {
    Page p = pageFromHtml(cutPage(extra), 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// ---- both parts paint -------------------------------------------------

paintCut('')
check(getPixelColor(50, 10) == red, 'the short block is at the top of the first column')
check(getPixelColor(50, 22) == blue, 'the tall block takes what is left of that column')
check(getPixelColor(150, 2) == blue, 'and its second part paints at the top of the next')
check(getPixelColor(150, 24) == blue, 'down to the end of the twenty-five it holds')
check(getPixelColor(150, 26) != blue, 'and no further')
// The two parts are one box, so they are one colour. A check that reads
// the same pixel value twice cannot be satisfied by a painter that
// invented a colour for the part it did not have a style for.
check(getPixelColor(150, 10) == getPixelColor(50, 22),
      'both parts being the same box, they are the same colour')

// ---- the break edge, sliced and cloned --------------------------------
// A 2px border, box-sizing: border-box so the parts are still 5 and 25.

text bord = 'border:2px solid #00aa00;box-sizing:border-box'

paintCut(bord)
check(getPixelColor(1, 22) == green, 'the sliced part keeps its left border')
check(getPixelColor(111, 10) == green, 'and the part after the break keeps its own')
check(getPixelColor(150, 1) == blue, 'but carries no border across the break')
check(getPixelColor(150, 24) == green, 'and closes at the block\'s real bottom')
check(getPixelColor(50, 21) == green, 'the first part opening with a border')
check(getPixelColor(50, 24) == blue, 'and not closing with one, for the same reason')

paintCut(bord + ';box-decoration-break:clone')
check(getPixelColor(150, 1) == green, '`clone` puts a border across the break')
check(getPixelColor(50, 24) == green, 'on the first part as well as the second')
check(getPixelColor(1, 22) == green, 'while the left border is where it was')
check(getPixelColor(150, 24) == green, 'and so is the real bottom')

// ---- a part answers the pointer ---------------------------------------
// Chromium's `elementFromPoint` names the tall block at every point in
// both of its parts, and the root past the container's end. A part that
// paints and cannot be clicked is half a box.

Page hitPage = pageFromHtml(cutPage(''), 'tests/fixtures/page.html', 400)
Box hit1 = hitTest(hitPage.root, 50, 22)
Box hit2 = hitTest(hitPage.root, 150, 2)
Box hit3 = hitTest(hitPage.root, 150, 24)
check(hit1 != null && hit2 != null, 'both parts of the cut block are hit')
checkEqInt(hit2.id, hit1.id, 'and the point in the second names the same box')
checkEqInt(hit3.id, hit1.id, 'at the bottom of that part as well as the top')
Box hitPast = hitTest(hitPage.root, 150, 40)
check(hitPast == null || hitPast.id != hit1.id,
      'and a point past the part is not the block')

finish('column fragments')
