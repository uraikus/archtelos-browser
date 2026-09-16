// `grid-template-areas` and named grid lines (CSS Grid 1 §7.3, §8.3).
//
// A grid 200px wide with two 100px columns and 30px automatic rows.
// Every number below was read off Chromium 141 on that grid, as the
// item's offset from the grid's own content edge and its size:
//
//   areas 'a a' / 'b c', grid-area: a        (0, 0)   200 x 30
//   the same, grid-area: c                   (100,30) 100 x 30
//   areas 'a b' / 'a c', grid-area: a        (0, 0)   100 x 60
//   areas 'a .' / '. c', grid-area: c        (100,30) 100 x 30
//   the same, grid-column: a-start / a-end   (0, 0)   200 x 30
//   [l] 100px [m] 100px [r], column m / r    (100,0)  100 x 30
//   the same with [m mid], column mid / r    (100,0)  100 x 30
//
// The last two pairs are the checks that do not depend on a number
// being known in advance: an area and the `-start`/`-end` lines it
// creates must land on the same cells, and a line carrying two names
// must answer to either of them.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func layoutHtml(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, width)
}

Box func findById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

text gHead = '<body style="margin:0;font:16px/20px monospace">'
text gStyle = 'display:grid;grid-template-columns:100px 100px;grid-auto-rows:30px;width:200px'

// The item's box, and the grid's, read out of one layout before the
// next runs: a box reaches its parent through a registry belonging to
// the most recent layout, so nothing here is kept across calls.
arr[int] func gaPlacement(containerStyle:text, itemStyle:text) {
    Box root = layoutHtml(gHead + `<div id="g" style="${gStyle};${containerStyle}">`
        + `<div id="it" style="${itemStyle}">I</div></div></body>`, 400)
    Box g = findById(root, 'g')
    Box it = findById(root, 'it')
    arr[int] out = []
    if g == null || it == null { return out }
    out.push(it.x - g.x)
    out.push(it.y - g.y)
    out.push(it.w)
    out.push(it.h)
    return out
}

void func gaCheck(got:arr[int], x:int, y:int, w:int, h:int, label:text) {
    if got.length < 4 {
        check(false, label)
        return
    }
    checkEqInt(got[0], x, `${label}: x`)
    checkEqInt(got[1], y, `${label}: y`)
    checkEqInt(got[2], w, `${label}: width`)
    checkEqInt(got[3], h, `${label}: height`)
}

// ---- an item goes where its area is ----------------------------------
arr[int] a1 = gaPlacement("grid-template-areas:'a a' 'b c'", 'grid-area:a')
gaCheck(a1, 0, 0, 200, 30, 'an area spanning two columns')

arr[int] a2 = gaPlacement("grid-template-areas:'a a' 'b c'", 'grid-area:c')
gaCheck(a2, 100, 30, 100, 30, 'an area in the second row and column')

arr[int] a3 = gaPlacement("grid-template-areas:'a b' 'a c'", 'grid-area:a')
gaCheck(a3, 0, 0, 100, 60, 'an area spanning two rows')

arr[int] a4 = gaPlacement("grid-template-areas:'a .' '. c'", 'grid-area:c')
gaCheck(a4, 100, 30, 100, 30, 'a dot is a cell belonging to no area')

// ---- the lines an area creates ---------------------------------------
// `grid-area: a` and the `a-start`/`a-end` lines it makes are two ways
// of naming one rectangle, so they must land on the same one.
arr[int] a5 = gaPlacement("grid-template-areas:'a a' 'b c'", 'grid-column:a-start/a-end;grid-row:1')
gaCheck(a5, 0, 0, 200, 30, 'the lines an area creates name the same cells')
check(a5.length == 4 && a1.length == 4 && a5[0] == a1[0] && a5[2] == a1[2],
      'which is the same rectangle grid-area gave')

// ---- named lines written in the track list ---------------------------
arr[int] a6 = gaPlacement('grid-template-columns:[l] 100px [m] 100px [r]',
                     'grid-column:m/r;grid-row:1')
gaCheck(a6, 100, 0, 100, 30, 'a line named in the track list places an item')

arr[int] a7 = gaPlacement('grid-template-columns:[l] 100px [m mid] 100px [r]',
                     'grid-column:mid/r;grid-row:1')
check(a7.length == 4 && a6.length == 4 && a7[0] == a6[0] && a7[2] == a6[2],
      'a line carrying two names answers to either')

// ---- the rows the strings imply --------------------------------------
// With no `grid-template-rows`, the number of strings is the number of
// rows: the second one exists because the template says so.
arr[int] a8 = gaPlacement("grid-template-areas:'a a' 'b b'", 'grid-area:b')
gaCheck(a8, 0, 30, 200, 30, 'the strings say how many rows the grid has')

// ---- an invalid template is dropped whole ----------------------------
// Rows of different lengths, and an area that is not a rectangle. In
// both Chromium drops the property, so nothing is placed by name and
// the item is certainly not two columns wide.
arr[int] a9 = gaPlacement("grid-template-areas:'a a' 'b'", 'grid-area:a')
check(a9.length == 4 && a9[2] != 200, 'rows of unequal length invalidate the template')
arr[int] a10 = gaPlacement("grid-template-areas:'a b' 'b a'", 'grid-area:a')
check(a10.length == 4 && a10[2] != 200, 'an area that is not a rectangle invalidates it')

finish('grid areas')
