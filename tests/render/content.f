// `content: url()` on a generated box: CSS2 §12.2 makes a URL one of
// the things `content` may hold, and the box it generates is a replaced
// element at the image's intrinsic size.
//
// Measured against Chromium 141 on the same markup, with the wrapper an
// inline-block so it has a width to read. `base` below is the wrapper
// with no generated content at all; every number is that plus what the
// generated content adds:
//
//   content: url(tile.png)                base + 10   the intrinsic width
//   content: url(tile.png) "XY"           base + 10 + width("XY")
//   content: "XY" url(tile.png)           the same total, other order
//   content: url(tile.png) url(tile.png)  base + 20
//   content: url(tile.png); width: 30px   base + 10   width does not apply
//   content: url(tile.png); margin: 0 4px base + 18   margin does apply
//   content: url(missing.png)             base        no box for a failure
//
// The two orders agreeing on width is deliberate: it is the check that
// does not depend on either number being known in advance. What tells
// them apart is where the image lands, which is what the pixel checks
// below ask.
//
// The fixture is the 10x10 tile whose left half is blue (#0000ff) and
// right half green (#008000), so one pixel says both that the image
// painted and that it painted the right way round.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color blue = 'blue'
color green = 'green'

// The leftmost x in the band carrying `want`, or -1 for none. A scan
// rather than a fixed coordinate because an inline image sits on the
// baseline, and where that is is a font metric.
int func firstXOf(want:color, x0:int, x1:int, y0:int, y1:int) {
    for int x = x0, x < x1, x++ {
        for int y = y0, y < y1, y++ {
            if getPixelColor(x, y) == want { return x }
        }
    }
    return -1
}

Box func contentSpan(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'span', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:400px">'
text ib = ' style="display:inline-block"'
text base = 'tests/fixtures/page.html'

// ---- the widths a generated image adds --------------------------------
text sheet = '<style>'
    + '#u1::before { content: url(tile.png) }'
    + '#u2::before { content: url(tile.png) "XY" }'
    + '#u3::before { content: "XY" url(tile.png) }'
    + '#u4::before { content: url(tile.png) url(tile.png) }'
    + '#u5::before { content: url(tile.png); width: 30px; height: 40px }'
    + '#u6::before { content: url(no-such-file.png) }'
    + '#u7::before { content: url(tile.png); margin: 0 4px }'
    + '#u8::before { content: "XY" }'
    + '#u9::after  { content: url(tile.png) }'
    + '#u10::before { color: #ff0000 }'
    + '</style>'
text spans = ''
for int i = 0, i <= 10, i++ {
    spans = spans + `<div><span${ib} id="u${i}">ab</span></div>`
}

Page p = pageFromHtml(head + sheet + spans + '</body>', base, 400)
Box u0 = contentSpan(p.root, 'u0')
Box u1 = contentSpan(p.root, 'u1')
Box u2 = contentSpan(p.root, 'u2')
Box u3 = contentSpan(p.root, 'u3')
Box u4 = contentSpan(p.root, 'u4')
Box u5 = contentSpan(p.root, 'u5')
Box u6 = contentSpan(p.root, 'u6')
Box u7 = contentSpan(p.root, 'u7')
Box u8 = contentSpan(p.root, 'u8')
Box u9 = contentSpan(p.root, 'u9')
Box u10 = contentSpan(p.root, 'u10')

check(u0 != null && u1 != null, 'the spans are in the box tree')
checkEqInt(u1.w, u0.w + 10, 'content: url() adds the image at its intrinsic width')
checkEqInt(u4.w, u0.w + 20, 'two urls add two images')
checkEqInt(u2.w, u1.w + (u8.w - u0.w), 'a string beside the url adds the string as well')
checkEqInt(u3.w, u2.w, 'and the same string on the other side adds the same width')
checkEqInt(u5.w, u1.w, 'width and height on the pseudo do not resize the image')
checkEqInt(u6.w, u0.w, 'an image that does not load generates no box')
checkEqInt(u7.w, u1.w + 8, 'margin on the pseudo applies to the generated box')
// The pieces of a run are resolved into globals, and #u10 below has a
// ::before rule with no `content` at all: it must leave those globals
// alone rather than inherit the run standing in them, which is #u9's.
// The two elements would otherwise share one pair of arrays, and the
// url in them would be resolved against the page twice -- so it is
// this check, on the element before, that a leak breaks first.
checkEqInt(u9.w, u1.w, '::after generates the image too')
checkEqInt(u10.w, u0.w, 'a ::before rule that sets only a colour generates nothing')

// ---- the image paints, and the order is the one written ---------------
// `vertical-align: top` puts the image's top at the top of the line box,
// so the band to scan is the 10 rows the image occupies.
Page pp = pageFromHtml(head
    + '<style>#d::before { content: url(tile.png); vertical-align: top }</style>'
    + '<div id="d" style="width:100px;height:60px"></div></body>', base, 400)
clearCanvas()
paintPage(pp, 0, 0, 300)
int bx = firstXOf(blue, 0, 100, 0, 20)
check(bx >= 0, 'the generated image paints')
checkEqInt(bx, 0, 'at the start of the line')
int gx = firstXOf(green, 0, 100, 0, 20)
check(gx >= 0, 'both halves of the tile paint')
checkEqInt(gx, bx + 5, 'the green half five pixels right of the blue one')

// The same image after a two-character string starts where the string
// ends, which is the difference the equal widths above cannot see.
Page pa = pageFromHtml(head
    + '<style>#d::before { content: "XY" url(tile.png); vertical-align: top }</style>'
    + '<div id="d" style="width:100px;height:60px"></div></body>', base, 400)
clearCanvas()
paintPage(pa, 0, 0, 300)
int ax = firstXOf(blue, 0, 100, 0, 20)
check(ax >= 0, 'the image after a string paints')
check(ax > bx, 'further along the line than the image that starts it')

// A url that does not load paints nothing at all, which is the pixel
// half of the width check above: an alt-text placeholder box would.
Page pn = pageFromHtml(head
    + '<style>#d::before { content: url(no-such-file.png); vertical-align: top }</style>'
    + '<div id="d" style="width:100px;height:60px"></div></body>', base, 400)
clearCanvas()
paintPage(pn, 0, 0, 300)
checkEqInt(firstXOf(blue, 0, 100, 0, 20), -1, 'a failed image paints nothing')

finish('content-url')
