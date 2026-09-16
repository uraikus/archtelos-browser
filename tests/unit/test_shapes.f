// CSS Shapes 1: `shape-outside` and `shape-margin`.
//
// A float pushes line boxes aside. Without a shape the edge it pushes
// them to is its margin box; with one it is the shape, evaluated over
// the band each line box occupies -- so the line that shares a band
// with the widest part of the shape is pushed furthest.
//
// The expected edges are Chromium 141's, read off these same fixtures
// with getBoundingClientRect before any of this was written: the left
// edge of the leftmost word on each line, which is where that line box
// begins.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func shapeLayout(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, width)
}

// Every line box in the tree, in document order.
void func collectLines(b:Box, out:arr[Line]) {
    for int i = 0, i < b.lines.length, i++ {
        if b.lines[i].frags.length > 0 { out.push(b.lines[i]) }
    }
    for int i = 0, i < b.children.length, i++ { collectLines(b.children[i], out) }
}

// Where each of the first `n` lines begins.
arr[int] func lineLefts(root:Box, n:int) {
    arr[Line] lines = []
    collectLines(root, lines)
    arr[int] out = []
    for int i = 0, i < n && i < lines.length, i++ {
        int lo = lines[i].frags[0].x
        for int j = 1, j < lines[i].frags.length, j++ {
            if lines[i].frags[j].x < lo { lo = lines[i].frags[j].x }
        }
        out.push(lo)
    }
    return out
}

text shapeWords = ''
for int i = 0, i < 40, i++ {
    if i > 0 { shapeWords = shapeWords + ' ' }
    shapeWords = shapeWords + 'xxxx'
}

// A 300px container with one left float of the given size and style,
// and enough text to run past it.
Box func floatWith(w:int, h:int, style:text) {
    return shapeLayout('<body style="margin:0;font:16px/20px monospace">'
        + '<div style="width:300px"><div style="float:left;width:' + w.toText()
        + 'px;height:' + h.toText() + 'px;' + style + '"></div>'
        + shapeWords + '</div></body>', 400)
}

// Checks the first `want.length` line starts against Chromium's.
void func shapeCase(label:text, w:int, h:int, style:text, want:arr[int]) {
    arr[int] got = lineLefts(floatWith(w, h, style), want.length)
    if got.length != want.length {
        checksFailed++
        log(`FAIL: ${label}: expected ${want.length} lines, got ${got.length}`)
        return
    }
    for int i = 0, i < want.length, i++ {
        if got[i] != want[i] {
            checksFailed++
            log(`FAIL: ${label}, line ${i}: expected left ${want[i]}, got ${got[i]}`)
            return
        }
    }
    checksPassed++
}

// ---- the control: no shape, so the margin box is the edge -------------
shapeCase('a float with no shape pushes lines to its margin box', 100, 100, '',
    [100, 100, 100, 100, 100, 0, 0, 0])

// ---- circle() ---------------------------------------------------------
// The edge is the shape's widest point within the line's own band, so
// the middle line is pushed furthest and the first and last least.
shapeCase('circle() lets the corners of the float be written into', 100, 100,
    'shape-outside:circle(50px at 50px 50px)',
    [90, 99, 100, 99, 90, 0, 0, 0])

// closest-side on a taller float is the horizontal half-width, and the
// shape then covers only the middle of the float's height.
shapeCase('circle() with no radius is the closest side', 80, 120,
    'shape-outside:circle()',
    [0, 75, 80, 80, 75, 0, 0, 0])

// farthest-side reaches past the float, and the exclusion is clamped to
// the float's own margin box.
shapeCase('a shape wider than the float is clamped to it', 80, 120,
    'shape-outside:circle(farthest-side)',
    [80, 80, 80, 80, 80, 80, 0, 0])

// ---- ellipse() --------------------------------------------------------
shapeCase('ellipse() takes a radius per axis', 100, 100,
    'shape-outside:ellipse(50px 25px at 50px 50px)',
    [0, 96, 100, 96, 0, 0, 0, 0])

shapeCase('ellipse() with no radii is the closest side on each axis', 80, 120,
    'shape-outside:ellipse()',
    [70, 78, 80, 80, 78, 70, 0, 0])

// ---- inset() ----------------------------------------------------------
// A band the shape does not reach is not excluded at all, which is what
// separates a shape from a narrower float.
shapeCase('inset() leaves the bands above and below it clear', 100, 100,
    'shape-outside:inset(20px)',
    [0, 80, 80, 80, 0, 0, 0, 0])

// A percentage inset is of the reference box, so the two axes differ on
// a float that is not square.
shapeCase('inset()s percentage is of the reference box on each axis', 80, 120,
    'shape-outside:inset(10%)',
    [72, 72, 72, 72, 72, 72, 0, 0])

// ---- polygon() --------------------------------------------------------
shapeCase('polygon() slopes the edge with its own edges', 100, 100,
    'shape-outside:polygon(0 0, 100px 100px, 0 100px)',
    [20, 40, 60, 80, 100, 0, 0, 0])

shapeCase('polygon() on a float that is not square', 80, 120,
    'shape-outside:polygon(0 0, 80px 60px, 0 120px)',
    [27, 53, 80, 80, 53, 27, 0, 0])

// ---- a geometry box is a shape too ------------------------------------
shapeCase('content-box is the content edge', 100, 100,
    'padding:20px;box-sizing:border-box;shape-outside:content-box',
    [0, 80, 80, 80, 0, 0, 0, 0])

shapeCase('margin-box is the box the float already used', 100, 100,
    'margin:10px;shape-outside:margin-box',
    [120, 120, 120, 120, 120, 120, 0, 0])

// ---- shape-margin -----------------------------------------------------
shapeCase('shape-margin grows the shape on every side', 100, 100,
    'shape-outside:inset(20px);shape-margin:10px',
    [90, 90, 90, 90, 90, 0, 0, 0])

shapeCase('and the result is still clamped to the float', 100, 100,
    'shape-outside:circle(50px at 50px 50px);shape-margin:10px',
    [100, 100, 100, 100, 100, 0, 0, 0])

// ---- what a shape does not do -----------------------------------------
// shape-outside applies to floats and to nothing else.
Box notFloated = shapeLayout('<body style="margin:0;font:16px/20px monospace">'
    + '<div style="width:300px"><div style="width:100px;height:100px;'
    + 'shape-outside:circle(50px at 50px 50px)"></div>'
    + shapeWords + '</div></body>', 400)
arr[int] notFloatedLefts = lineLefts(notFloated, 3)
check(notFloatedLefts[0] == 0 && notFloatedLefts[1] == 0,
      'shape-outside on a box that does not float changes nothing')

// ---- a right float is the same shape, mirrored ------------------------
// Neither side's answer has to be known for this: a polygon on the
// right must push line ends in from the right exactly as far as its
// mirror image pushes line starts in from the left.
Box leftTri = floatWith(100, 100, 'shape-outside:polygon(0 0, 100px 100px, 0 100px)')
Box rightTri = shapeLayout('<body style="margin:0;font:16px/20px monospace">'
    + '<div style="width:300px"><div style="float:right;width:100px;height:100px;'
    + 'shape-outside:polygon(100px 0, 100px 100px, 0 100px)"></div>'
    + shapeWords + '</div></body>', 400)
arr[Line] rightLines = []
collectLines(rightTri, rightLines)
arr[int] leftEdges = lineLefts(leftTri, 5)
for int i = 0, i < 5, i++ {
    // The right float's line must end where the container's width less
    // the left float's line start puts it.
    int rightLimit = 300 - leftEdges[i]
    int widest = 0
    for int j = 0, j < rightLines[i].frags.length, j++ {
        int edge = rightLines[i].frags[j].x + rightLines[i].frags[j].w
        if edge > widest { widest = edge }
    }
    check(widest <= rightLimit && widest > rightLimit - 48,
          `a right float excludes the mirror of what a left one excludes, line ${i}`)
}

finish('shapes')
