// Media Queries 3's feature set, evaluated against a viewport.
//
// The expected answers are Chromium 141's, read with `window.matchMedia`
// and then restated against this engine's viewport: a query about a
// width is a question about a number both engines have, so the check is
// Chromium's rule rather than Chromium's window.
//
// What this engine calls the device is its own viewport. It has no
// screen metrics to ask for, and a query about the device is asked by a
// page deciding whether it is on a phone, which the window size answers
// as well as the screen does.
import ../../src/css/parser.f
import ../assert.f

void func mqIs(query:text, want:bool, label:text) {
    bool got = evaluateMediaQuery(query.toAscii())
    if got == want { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: ${query} answered ${got}, expected ${want}`)
    }
}

setCssViewport(800, 600)

// ---- media types --------------------------------------------------------
mqIs('all', true, 'all')
mqIs('screen', true, 'screen')
mqIs('print', false, 'print')
mqIs('speech', false, 'speech')
mqIs('tty', false, 'tty')
mqIs('tv', false, 'tv')
mqIs('not screen', false, 'not screen')
mqIs('not print', true, 'not print')
mqIs('only screen', true, 'only screen')
mqIs('screen and (min-width: 100px)', true, 'a type and a feature')
mqIs('(min-width: 100px), print', true, 'a comma list needs one alternative')
mqIs('print, (min-width: 10000px)', false, 'and matches neither here')

// ---- width and height ---------------------------------------------------
mqIs('(min-width: 800px)', true, 'min-width at the viewport width')
mqIs('(min-width: 801px)', false, 'min-width above it')
mqIs('(max-width: 800px)', true, 'max-width at it')
mqIs('(max-width: 799px)', false, 'max-width below it')
mqIs('(width: 800px)', true, 'an exact width')
mqIs('(width: 799px)', false, 'and not a different one')
mqIs('(min-height: 600px)', true, 'min-height at the viewport height')
mqIs('(max-height: 599px)', false, 'max-height below it')
mqIs('(height: 600px)', true, 'an exact height')
mqIs('(min-width: 50em)', true, '50em is 800px at the initial font size')
mqIs('(min-width: 51em)', false, 'and 51em is more than the viewport')

// ---- the device, which here is the viewport -----------------------------
mqIs('(device-width: 800px)', true, 'device-width')
mqIs('(min-device-width: 800px)', true, 'min-device-width')
mqIs('(max-device-width: 799px)', false, 'max-device-width')
mqIs('(device-height: 600px)', true, 'device-height')

// ---- orientation --------------------------------------------------------
mqIs('(orientation: landscape)', true, '800 by 600 is landscape')
mqIs('(orientation: portrait)', false, 'and not portrait')
mqIs('(orientation)', true, 'orientation on its own is true')
setCssViewport(600, 800)
mqIs('(orientation: portrait)', true, '600 by 800 is portrait')
mqIs('(orientation: landscape)', false, 'and not landscape')
setCssViewport(600, 600)
mqIs('(orientation: landscape)', true, 'a square viewport is landscape')
setCssViewport(800, 600)

// ---- aspect-ratio -------------------------------------------------------
mqIs('(aspect-ratio: 4/3)', true, '800 by 600 is four thirds')
mqIs('(aspect-ratio: 16/9)', false, 'and not sixteen ninths')
mqIs('(min-aspect-ratio: 1/1)', true, 'wider than square')
mqIs('(max-aspect-ratio: 1/1)', false, 'so not narrower')
mqIs('(min-aspect-ratio: 2/1)', false, 'and not twice as wide as tall')
mqIs('(aspect-ratio)', true, 'aspect-ratio on its own is true')
mqIs('(device-aspect-ratio: 4/3)', true, 'the device has the same ratio')

// ---- colour -------------------------------------------------------------
// Eight bits a component, which is what the canvas has.
mqIs('(color)', true, 'there is colour')
mqIs('(color: 8)', true, 'eight bits of it a component')
mqIs('(min-color: 8)', true, 'at least eight')
mqIs('(min-color: 9)', false, 'and not nine')
mqIs('(color-index)', false, 'there is no colour lookup table')
mqIs('(color-index: 0)', true, 'which is a table of no entries')
mqIs('(monochrome)', false, 'the display is not monochrome')
mqIs('(monochrome: 0)', true, 'which is zero bits a pixel')

// ---- resolution ---------------------------------------------------------
mqIs('(resolution: 96dpi)', true, 'ninety-six dots to the inch')
mqIs('(min-resolution: 96dpi)', true, 'at least that')
mqIs('(min-resolution: 1dppx)', true, 'one device pixel to the CSS pixel')
mqIs('(min-resolution: 2dppx)', false, 'and not two')
mqIs('(max-resolution: 96dpi)', true, 'and no more than that')
mqIs('(resolution)', true, 'resolution on its own is true')

// ---- the features of a device this is not -------------------------------
mqIs('(grid)', false, 'this is not a grid device')
mqIs('(grid: 0)', true, 'which is what grid: 0 asks')
mqIs('(grid: 1)', false, 'and not grid: 1')
mqIs('(scan: progressive)', false, 'scan is about a television')
mqIs('(scan: interlace)', false, 'in either of its values')

// ---- input, which is a statement about this browser ---------------------
// It opens a window with a pointer in it, so it says so. Headless
// Chromium answers the other way because it has no input device at all,
// which is a fact about that process rather than about the standard.
mqIs('(hover: hover)', true, 'there is a pointer that can hover')
mqIs('(hover: none)', false, 'so hover: none is false')
mqIs('(pointer: fine)', true, 'and it is a fine one')
mqIs('(pointer: coarse)', false, 'not a coarse one')
mqIs('(any-hover: hover)', true, 'any-hover says the same')
mqIs('(any-pointer: fine)', true, 'and so does any-pointer')

// ---- what must still be refused -----------------------------------------
mqIs('(nonesuch: 5)', false, 'an unknown feature matches nothing')
mqIs('(min-width: bogus)', false, 'nor does a value that is not a length')
mqIs('screen and (nonesuch)', false, 'and an unknown feature fails the whole term')

// ---- Media Queries 4: the range syntax --------------------------------
// `(width >= 400px)` says what `(min-width: 400px)` says, and the two
// must answer alike -- a check that needs neither answer known.

mqIs('(width >= 800px)', true, 'width >= at the viewport width')
mqIs('(width >= 801px)', false, 'and not above it')
mqIs('(width > 800px)', false, 'the strict form excludes equality')
mqIs('(width > 799px)', true, 'but not the value below')
mqIs('(width <= 800px)', true, 'width <= at it')
mqIs('(width < 800px)', false, 'and the strict form again')
mqIs('(width = 800px)', true, 'an exact width with =')
mqIs('(height >= 600px)', true, 'height reads the same way')

// The value may be written first, which reverses the comparison.
mqIs('(800px <= width)', true, 'a value first reverses the operator')
mqIs('(801px <= width)', false, 'and still means what it says')
mqIs('(800px >= width)', true, 'in both directions')
mqIs('(799px >= width)', false, 'without changing the answer')

// Two ends at once.
mqIs('(400px <= width <= 900px)', true, 'a range with both ends')
mqIs('(900px <= width <= 1000px)', false, 'a range this viewport is below')
mqIs('(100px <= width <= 400px)', false, 'and one it is above')
mqIs('(400px < width < 900px)', true, 'the strict form of a range')
mqIs('(800px < width < 900px)', false, 'which excludes its own end')

// Ratio and resolution read the same way.
mqIs('(aspect-ratio >= 1/1)', true, 'a ratio compared with >=')
mqIs('(aspect-ratio < 1/1)', false, 'and with <')
mqIs('(resolution >= 1dppx)', true, 'a resolution compared with >=')
mqIs('(resolution > 1dppx)', false, 'and its strict form')
mqIs('(color >= 8)', true, 'and a plain number')

// The range form and the prefix form are two ways of saying one thing.
mqIs('(width >= 640px)', evaluateMediaQuery('(min-width: 640px)'.toAscii()),
     'width >= says what min-width says')
mqIs('(width <= 640px)', evaluateMediaQuery('(max-width: 640px)'.toAscii()),
     'and width <= says what max-width says')

// ---- `or`, `not` and grouping ------------------------------------------
mqIs('(width >= 100px) or (width >= 10000px)', true, 'or needs one side')
mqIs('(width >= 10000px) or (width >= 20000px)', false, 'and matches neither here')
mqIs('(width >= 100px) and (height >= 100px)', true, 'and needs both')
mqIs('(width >= 100px) and (height >= 10000px)', false, 'and fails on one')
mqIs('not (width >= 10000px)', true, 'not inverts a condition')
mqIs('(not (width >= 10000px))', true, 'inside parentheses as well')
mqIs('screen and (not (width >= 10000px))', true, 'and after a media type')
mqIs('((width >= 100px) and (height >= 100px))', true, 'a group of two')
mqIs('((width >= 10000px) or (height >= 100px))', true, 'an or inside a group')
mqIs('((width >= 10000px) and (height >= 100px))', false, 'and an and inside one')

finish('media')
