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

finish('clip')
