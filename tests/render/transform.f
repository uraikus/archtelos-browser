// CSS Transforms 1.
//
// A transform changes where a box is painted and nothing about where it
// was laid out, which is what makes it checkable this way: the same
// document is laid out once and painted twice, and only the pixels
// differ. Each check names a pixel the transform must move ink to and a
// pixel it must move ink away from, because a transform that did
// nothing would satisfy only the second.
//
// Festina's canvas has translate, rotate and scale and no call that
// takes a matrix, so `skew()` and `matrix()` are not expressible here
// (FINDINGS.md). The checks cover what the canvas can express.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color red = 'red'
color white = 'white'

text head = '<!doctype html><body style="margin:0">'

// A 40x40 red box at the origin, with whatever transform is asked for.
void func shotBoxAt(style:text) {
    Page p = pageFromHtml(head + '<div style="width:40px;height:40px;background:red;'
        + style + '"></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// The box's own laid-out geometry, which a transform must never change.
Box func layoutOf(style:text) {
    Page p = pageFromHtml(head + '<div id="t" style="width:40px;height:40px;background:red;'
        + style + '"></div><div id="after" style="height:10px"></div></body>',
        'tests/fixtures/page.html', 400)
    return p.root
}

int func countRed(x0:int, y0:int, x1:int, y1:int) {
    int n = 0
    for int y = y0, y < y1, y++ {
        for int x = x0, x < x1, x++ {
            if getPixelColor(x, y) == red { n++ }
        }
    }
    return n
}

// ---- no transform is the control -----------------------------------------

shotBoxAt('')
check(getPixelColor(5, 5) == red, 'an untransformed box paints at the origin')
check(getPixelColor(105, 5) == white, 'and not 100 pixels to the right')
int plainInk = countRed(0, 0, 300, 200)
check(plainInk > 0, 'the control paints something')

// ---- translate -----------------------------------------------------------

shotBoxAt('transform:translate(100px, 50px)')
check(getPixelColor(105, 55) == red, 'translate moves the box')
check(getPixelColor(5, 5) == white, 'and leaves where it was')
checkEqInt(countRed(0, 0, 300, 200), plainInk, 'without changing how much of it there is')

shotBoxAt('transform:translateX(100px)')
check(getPixelColor(105, 5) == red, 'translateX moves it along x')
check(getPixelColor(5, 5) == white, 'and off its old place')

shotBoxAt('transform:translateY(50px)')
check(getPixelColor(5, 55) == red, 'translateY moves it along y')
check(getPixelColor(5, 5) == white, 'and off its old place')

// A percentage in translate is of the box's own size, not the container's.
shotBoxAt('transform:translateX(100%)')
check(getPixelColor(45, 5) == red, 'a percentage translate is of the box itself')
check(getPixelColor(5, 5) == white, 'so 100% moves it exactly its own width')

// The individual `translate` property says the same as the function.
shotBoxAt('translate:100px 50px')
check(getPixelColor(105, 55) == red, 'the translate property moves it too')
check(getPixelColor(5, 5) == white, 'and off its old place')

// ---- scale ---------------------------------------------------------------
// Scaling is about the box's centre by default, so a doubled 40x40 box
// at the origin covers -20..60 on both axes.

shotBoxAt('transform:scale(2)')
check(getPixelColor(55, 55) == red, 'scale(2) reaches past the box it was')
check(countRed(0, 0, 300, 200) > plainInk, 'and covers more than the box did')

shotBoxAt('transform:scaleX(2)')
check(getPixelColor(55, 5) == red, 'scaleX stretches along x')
check(getPixelColor(5, 55) == white, 'and not along y')

// transform-origin moves what the scaling is about.
shotBoxAt('transform:scale(2);transform-origin:0 0')
check(getPixelColor(75, 75) == red, 'transform-origin:0 0 scales about the corner')
check(getPixelColor(5, 5) == red, 'so the corner itself stays put')

// The individual `scale` property.
shotBoxAt('scale:2')
check(getPixelColor(55, 55) == red, 'the scale property scales it too')

// ---- rotate --------------------------------------------------------------
// A square turned 45 degrees about its centre reaches further from the
// centre on the axes and no longer covers its own corners.

shotBoxAt('transform:rotate(45deg)')
check(getPixelColor(20, 20) == red, 'a rotated box still covers its centre')
check(getPixelColor(1, 1) == white, 'and no longer covers the corner it did')
// The square's bottom edge was y=40; turned about its centre its
// lowest point is the half-diagonal, 20*sqrt(2) = 28 below the centre.
check(getPixelColor(20, 44) == red, 'reaching past the edge it had, on the diagonal')
check(getPixelColor(20, 52) == white, 'but not past the diagonal itself')

shotBoxAt('rotate:45deg')
check(getPixelColor(1, 1) == white, 'the rotate property turns it too')
check(getPixelColor(20, 20) == red, 'about the same centre')

// A whole turn is no turn at all: the two must land on the same pixels.
shotBoxAt('transform:rotate(360deg)')
int turnedInk = countRed(0, 0, 300, 200)
check(getPixelColor(5, 5) == red, 'a full turn leaves the box where it was')
shotBoxAt('')
checkEqInt(turnedInk, countRed(0, 0, 300, 200), 'and covers exactly what it covered')

// ---- more than one function ----------------------------------------------
// The functions apply left to right, so translate-then-scale is not
// scale-then-translate. Checking they differ is the check that the list
// is applied in order rather than only its last member.

shotBoxAt('transform:translateX(100px) scale(2);transform-origin:0 0')
int translateThenScale = countRed(0, 0, 120, 200)
shotBoxAt('transform:scale(2) translateX(100px);transform-origin:0 0')
int scaleThenTranslate = countRed(0, 0, 120, 200)
check(translateThenScale != scaleThenTranslate,
      'the functions apply in the order they are written')

// Two translates compose into their sum, which is the same list read
// as one translate -- two ways of saying one thing.
shotBoxAt('transform:translateX(60px) translateX(40px)')
check(getPixelColor(105, 5) == red, 'two translates add up')
shotBoxAt('transform:translateX(100px)')
check(getPixelColor(105, 5) == red, 'to the single translate that says the same')

// ---- a transform does not affect layout ----------------------------------
// The standard is explicit: a transformed box takes the space it would
// have taken untransformed, and its siblings do not move.

Box plainRoot = layoutOf('')
Box movedRoot = layoutOf('transform:translate(100px,50px) scale(3)')
arr[Box] plainDivs = []
collectBoxesForTag(plainRoot, 'div', plainDivs)
arr[Box] movedDivs = []
collectBoxesForTag(movedRoot, 'div', movedDivs)
check(plainDivs.length == 2 && movedDivs.length == 2, 'the layout fixture has two boxes')
checkEqInt(movedDivs[0].w, plainDivs[0].w, 'a transform does not change the box width')
checkEqInt(movedDivs[0].h, plainDivs[0].h, 'nor its height')
checkEqInt(movedDivs[1].y, plainDivs[1].y, 'nor where the next box goes')

// ---- what is left alone --------------------------------------------------
// `none` is the initial value and must behave as no transform at all,
// and a function the canvas cannot express is dropped rather than
// applied wrongly.

shotBoxAt('transform:none')
checkEqInt(countRed(0, 0, 300, 200), plainInk, 'transform:none paints the untransformed box')
check(getPixelColor(5, 5) == red, 'exactly where it was')

shotBoxAt('transform:skewX(30deg)')
check(getPixelColor(5, 5) == red, 'a skew, which this canvas cannot express, is dropped')
checkEqInt(countRed(0, 0, 300, 200), plainInk, 'rather than applied as something else')

// ---- transform-box (Transforms 1 §6) -------------------------------------
// Which box a percentage `transform-origin` resolves against. On a box
// with padding and a border the content box and the border box have
// different top-left corners, so rotating about `0 0` puts the result
// in two different places.
//
// Chromium 141, on 60 content + 10 padding + 5 border a side (a 90x50
// border box) rotated 90 degrees about its reference box's top-left,
// measures the rotated box's left edge from its container:
//
//   initial, border-box, stroke-box, view-box   -50
//   content-box, fill-box                       -20
//
// The initial value computes to `view-box`, which for an element that
// is not SVG is the border box. So the pair that must differ is
// content-box against border-box, and the three that must agree with
// the initial value are the other three.

// A bordered, padded box at a known place, rotated about its reference
// box's top-left, and the leftmost column its ink reaches.
int func rotatedLeftEdge(style:text) {
    Page p = pageFromHtml(head
        + '<div style="margin-left:150px;width:60px;height:20px;padding:10px;'
        + 'border:5px solid red;background:red;transform-origin:0 0;'
        + `transform:rotate(90deg);${style}"></div></body>`,
        'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
    for int x = 0, x < 300, x++ {
        for int y = 0, y < 200, y++ {
            if getPixelColor(x, y) == red { return x }
        }
    }
    return -1
}

int tbInitial = rotatedLeftEdge('')
int tbContent = rotatedLeftEdge('transform-box:content-box')
int tbBorder = rotatedLeftEdge('transform-box:border-box')
int tbFill = rotatedLeftEdge('transform-box:fill-box')
int tbStroke = rotatedLeftEdge('transform-box:stroke-box')
int tbView = rotatedLeftEdge('transform-box:view-box')

check(tbInitial >= 0 && tbContent >= 0, 'both boxes paint somewhere')
check(tbContent != tbBorder, 'the content box and the border box are different origins')
checkEqInt(tbContent - tbBorder, 30,
           'and they differ by the border and padding on that side, twice over')
checkEqInt(tbBorder, tbInitial, 'the initial value resolves against the border box')
checkEqInt(tbView, tbInitial, '`view-box` is that same box outside SVG')
checkEqInt(tbStroke, tbInitial, 'and so is `stroke-box`')
checkEqInt(tbFill, tbContent, '`fill-box` is the content box outside SVG')

finish('transform')
