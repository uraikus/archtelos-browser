// CSS Masking 1's `clip-path` and CSS2's `clip`, in pixels.
//
// Each case paints a 100x100 red box on white and reads back a ten by
// ten grid of pixels, five apart from the box's edges. The expected
// grid is Chromium 141's: `document.elementFromPoint` respects both
// properties, so asking it at each pixel's centre is asking that engine
// which pixels the clip keeps, with no screenshot to decode.
//
// A `?` in an expected row is a pixel Chromium's own answer changes
// within three pixels of -- the boundary itself, where a rasteriser
// that antialiases and one that does not are entitled to differ. Those
// are copied from the actual grid rather than compared, so the check is
// about the shape and not about its edge.
//
// The canvas has no clip region and no path API, so a shape is painted
// by putting the subtree into an image and blitting it back one
// scanline at a time (FINDINGS.md).
import ../../src/browser/page.f
import ../assert.f

setClientWidth(200)
setClientHeight(200)

color clipRed = 'red'

text clipHead = '<!doctype html><body style="margin:0">'

// Paints one case and compares its grid against Chromium's.
void func clipCase(label:text, style:text, want:arr[text]) {
    Page p = pageFromHtml(clipHead
        + '<div style="position:absolute;left:0;top:0;width:100px;height:100px;'
        + 'background:red;' + style + '"></div></body>', 'test.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 200)
    for int row = 0, row < want.length, row++ {
        int y = 5 + row * 10
        text got = ''
        text expect = ''
        ascii wanted = want[row].toAscii()
        for int col = 0, col < 10, col++ {
            int x = 5 + col * 10
            text cell = getPixelColor(x, y) == clipRed ? '#' : '.'
            // 63 is '?' and 35 is '#'; a '?' cell takes whatever was
            // painted, because Chromium's own answer moves there.
            int w = wanted.charCodeAt(col)
            got = got + cell
            expect = expect + (w == 63 ? cell : (w == 35 ? '#' : '.'))
        }
        checkEq(got, expect, `${label}, row ${row}`)
    }
}

clipCase('inset() with one length insets every side',
    'clip-path:inset(10px)',
    ['..........',
     '.########.',
     '.########.',
     '.########.',
     '.########.',
     '.########.',
     '.########.',
     '.########.',
     '.########.',
     '..........'])

clipCase('inset()s four lengths are top, right, bottom and left',
    'clip-path:inset(10px 20px 30px 40px)',
    ['..........',
     '....####..',
     '....####..',
     '....####..',
     '....####..',
     '....####..',
     '....####..',
     '..........',
     '..........',
     '..........'])

clipCase('circle() with a length radius and a centre',
    'clip-path:circle(40px at 50px 50px)',
    ['..........',
     '..??##??..',
     '.?######?.',
     '.?######?.',
     '.########.',
     '.########.',
     '.?######?.',
     '.?#####??.',
     '..??##??..',
     '..........'])

clipCase('circle()s percentage radius is of the diagonal, centred by default',
    'clip-path:circle(50%)',
    ['..??##??..',
     '.?######?.',
     '?########?',
     '?########?',
     '##########',
     '##########',
     '?########?',
     '?########?',
     '.?######?.',
     '..??##??..'])

clipCase('ellipse() takes a radius per axis',
    'clip-path:ellipse(50px 25px at 50px 50px)',
    ['..........',
     '..........',
     '..??????..',
     '??######??',
     '#########?',
     '?########?',
     '??######??',
     '..?????...',
     '..........',
     '..........'])

clipCase('polygon() fills between its edges',
    'clip-path:polygon(50% 0%, 100% 100%, 0% 100%)',
    ['....??....',
     '....??....',
     '...?##?...',
     '...?##?...',
     '..?####?..',
     '..?####?..',
     '.?######?.',
     '.?######?.',
     '?########?',
     '?########?'])

clipCase('content-box clips to the content edge',
    'padding:25px;box-sizing:border-box;clip-path:content-box',
    ['..........',
     '..........',
     '..??????..',
     '..?####?..',
     '..?####?..',
     '..?####?..',
     '..?####?..',
     '..??????..',
     '..........',
     '..........'])

clipCase('padding-box clips to the padding edge, which here is the whole box',
    'padding:25px;box-sizing:border-box;clip-path:padding-box',
    ['##########',
     '##########',
     '##########',
     '##########',
     '##########',
     '##########',
     '##########',
     '##########',
     '##########',
     '##########'])

clipCase('the legacy clip is a rectangle in border-box coordinates',
    'clip:rect(10px,80px,70px,20px)',
    ['..........',
     '..######..',
     '..######..',
     '..######..',
     '..######..',
     '..######..',
     '..######..',
     '..........',
     '..........',
     '..........'])

// ---- two ways of saying one shape must give one grid -----------------
// A rectangle reached through inset(), through a geometry box and
// through the legacy `clip` is the same rectangle, and a circle written
// as an ellipse with two equal radii is the same circle. Neither check
// depends on knowing what the right answer is.

text func clipGrid(style:text) {
    Page p = pageFromHtml(clipHead
        + '<div style="position:absolute;left:0;top:0;width:100px;height:100px;'
        + 'background:red;' + style + '"></div></body>', 'test.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 200)
    text out = ''
    for int y = 5, y < 100, y = y + 10 {
        for int x = 5, x < 100, x = x + 10 {
            out = out + (getPixelColor(x, y) == clipRed ? '#' : '.')
        }
    }
    return out
}

checkEq(clipGrid('clip-path:circle(40px at 50px 50px)'),
        clipGrid('clip-path:ellipse(40px 40px at 50px 50px)'),
        'a circle is an ellipse with two equal radii')
checkEq(clipGrid('clip-path:inset(25px)'),
        clipGrid('clip-path:polygon(25px 25px, 75px 25px, 75px 75px, 25px 75px)'),
        'a rectangle is a four-sided polygon')
checkEq(clipGrid('padding:25px;box-sizing:border-box;clip-path:content-box'),
        clipGrid('clip-path:inset(25px)'),
        'the content box of this element is inset 25px from its border box')
checkEq(clipGrid('clip:rect(25px,75px,75px,25px)'),
        clipGrid('clip-path:inset(25px)'),
        'and the legacy clip reaches the same rectangle from the other side')
checkEq(clipGrid('clip-path:inset(0)'), clipGrid(''),
        'a clip that takes nothing away changes nothing')
checkEq(clipGrid('clip-path:inset(50% 50% 50% 50%)'), clipGrid('clip-path:inset(50px)'),
        'a percentage inset is of the reference box')

// ---- what the clip takes with it -------------------------------------
// clip-path clips the box itself -- its background and border -- and
// everything inside it, which is what separates it from overflow.

Page clipChild = pageFromHtml(clipHead
    + '<div style="position:absolute;left:0;top:0;width:100px;height:100px;'
    + 'clip-path:inset(40px);border:10px solid red">'
    + '<div style="width:200px;height:200px;background:red"></div></div></body>',
    'test.html', 200)
clearCanvas()
paintPage(clipChild, 0, 0, 200)
check(getPixelColor(50, 50) == clipRed, 'inside the clip the child paints')
check(getPixelColor(5, 5) != clipRed, 'and the border is clipped away with it')
check(getPixelColor(150, 150) != clipRed, 'an overflowing child is clipped too')

// ---- a page with no clip is untouched ---------------------------------

Page clipNone = pageFromHtml(clipHead
    + '<div style="width:100px;height:100px;background:red"></div></body>', 'test.html', 200)
clearCanvas()
paintPage(clipNone, 0, 0, 200)
check(getPixelColor(50, 50) == clipRed, 'a box with no clip paints whole')
check(getPixelColor(99, 99) == clipRed, 'to its last pixel')
check(getPixelColor(101, 50) != clipRed, 'and no further')

// ---- polygon()'s fill rule (CSS Masking 1 §4.2) -----------------------
//
// A five-pointed star, its points joined in {5/2} order so the pentagon
// in the middle is enclosed twice and the five arms once. That is the
// only figure where the two fill rules disagree, and they disagree
// about exactly one region: `nonzero` -- CSS's initial value -- keeps
// the middle, `evenodd` cuts it out. An arm is enclosed once and is
// kept by both, which is the control: a `polygon()` that had failed to
// parse would lose that pixel too, and every check below would pass on
// a box that painted nothing at all.
//
// Chromium 141 on this geometry, read with tests/chromium.py pixels:
// the centre is red under `polygon(...)` and under
// `polygon(nonzero, ...)`, white under `polygon(evenodd, ...)`, and the
// arm is red under all three.
text STAR = '80px 10px, 121.1px 136.6px, 13.4px 58.4px, 146.6px 58.4px, 38.9px 136.6px'

bool func starFilled(rule:text, x:int, y:int) {
    Page p = pageFromHtml(clipHead
        + `<div style="width:160px;height:160px;background:red;clip-path:polygon(${rule}${STAR})"></div></body>`,
        'tests/fixtures/page.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 200)
    return getPixelColor(x, y) == clipRed
}

// The instrument first: the two rules have to disagree somewhere, or
// every check below passes whichever one the engine draws.
check(starFilled('', 80, 80) != starFilled('evenodd, ', 80, 80),
    'the two fill rules disagree about the middle of a star')
// And the star has to be there at all.
check(starFilled('', 80, 25), 'an arm of the star is painted')
check(!starFilled('', 5, 5), 'and the box outside it is not')

// The default is nonzero, so the middle is kept.
check(starFilled('', 80, 80), 'polygon() keeps the middle of a star by default')
check(starFilled('nonzero, ', 80, 80), 'and nonzero says the same thing')
// Two ways of asking for the same region must land on the same pixel,
// rather than each matching a colour written down here.
check(starFilled('', 80, 80) == starFilled('nonzero, ', 80, 80),
    'the default and nonzero agree in the middle')
check(starFilled('', 80, 25) == starFilled('nonzero, ', 80, 25),
    'and on an arm')

// evenodd cuts the middle out and leaves the arms.
check(!starFilled('evenodd, ', 80, 80), 'evenodd cuts the middle of a star out')
check(starFilled('evenodd, ', 80, 25), 'and keeps an arm')

// ---- inset()'s round radius (CSS Masking 1 §4.1) ----------------------
//
// The radius cuts the corner off the rectangle. Every check here is an
// agreement between two ways of reaching the same region rather than a
// column worked out by hand, because this engine does not antialias and
// Chromium does, so a boundary column copied from one would not survive
// the other:
//
//   inset(10px round 0)  ==  inset(10px)      a zero radius is a square
//                                             corner
//   inset(0 round 50%)   ==  circle(50%)      half the box on both axes
//                        ==  ellipse(50% 50%) IS an ellipse, and this
//                                             engine reaches that shape
//                                             down a different branch
//
// Chromium agrees with both, checked before they were written down: all
// three of the second group start their red at x=19 on row 40, and both
// of the first at x=10.
//
// The row past the corner is the control. A rounded inset that had
// stopped clipping, or clipped everything, would move that one too.

// The first column on a row that the box's colour reaches, or -1.
int func insetFirst(shape:text, row:int) {
    Page p = pageFromHtml(clipHead
        + `<div style="width:200px;height:200px;background:red;clip-path:${shape}"></div></body>`,
        'tests/fixtures/page.html', 220)
    clearCanvas()
    paintPage(p, 0, 0, 220)
    for int x = 0, x < 220, x++ {
        if getPixelColor(x, row) == clipRed { return x }
    }
    return -1
}

// The instrument first: a radius has to do something, and it has to cut
// the corner inward rather than merely differ.
check(insetFirst('inset(10px round 40px)', 12) > insetFirst('inset(10px)', 12),
    'a round radius cuts the corner in')
check(insetFirst('inset(10px)', 12) >= 0, 'the square inset is painted at all')
check(insetFirst('inset(10px round 40px)', 100) >= 0,
    'and the rounded one is painted past its corner')

// A zero radius is a square corner.
checkEqInt(insetFirst('inset(10px round 0)', 12), insetFirst('inset(10px)', 12),
    'inset(10px round 0) is inset(10px) at the corner')
checkEqInt(insetFirst('inset(10px round 0)', 100), insetFirst('inset(10px)', 100),
    'and past it')

// Half the box on both axes is an ellipse, which this engine reaches
// down a different branch entirely.
checkEqInt(insetFirst('inset(0 round 50%)', 40), insetFirst('circle(50%)', 40),
    'inset(0 round 50%) is a circle')
checkEqInt(insetFirst('inset(0 round 50%)', 40), insetFirst('ellipse(50% 50%)', 40),
    'and an ellipse of the same radii')
checkEqInt(insetFirst('inset(0 round 50%)', 80), insetFirst('circle(50%)', 80),
    'at a second row')
checkEqInt(insetFirst('inset(0 round 50%)', 100), insetFirst('circle(50%)', 100),
    'and across the middle')

// Past the corner a rounded inset is the plain one.
checkEqInt(insetFirst('inset(10px round 40px)', 100), insetFirst('inset(10px)', 100),
    'past its corner a rounded inset is the square one')

finish('clip')
