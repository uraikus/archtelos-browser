// Pagination: a laid-out document poured through a page box, one page's
// worth at a time (CSS2 §13).
//
// A page is a fragmentation container like a column, and the engine
// already has one of those, so this is the column algorithm over a
// different container: the same units, the same rules about where a
// break is allowed -- forced, forbidden, orphans, widows -- and the same
// search for the nearest allowed point when the container has run out of
// room. What differs is that every page may be a different size, because
// `@page :first` and a named page can each declare their own, so the
// height is asked for one page at a time rather than fixed in advance.
//
// The document is laid out once, at the first page's area width, and
// each page is a strip of it. Nothing is moved: a page knows where it
// begins in the document, and painting it is the same painting with a
// different offset.
import layout.f

// The document offset each page begins at, the page name in force on
// it, and the box it is drawn into. Three answers out of a function need
// globals (FINDINGS.md, "one value out of a function").
arr[int] pageStartY = []
arr[int] pageEndY = []
arr[text] pageNames = []
arr[PageBox] pageBoxes = []

// A document that will not break is still a document, and a runaway
// would be a file per page: a page that takes no content ends the walk.
const int PAGE_LIMIT = 2000

// The box whose children are the document's top-level blocks: the
// body's, because the fragmentation here is one level deep as the column
// engine's is, and the level that holds a document's blocks is the body.
//
// Descending by "the box with one child" instead looked equivalent and
// was not: a document whose body holds a single block descends past the
// body into that block, which has no children, and a document of one
// block came out one page however tall the block was.
Box func paginationHost(root:Box) {
    Box b = findBoxByTag(root, 'body')
    return b == null ? root : b
}

Box func findBoxByTag(b:Box, tag:text) {
    if b == null { return null }
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null && b.node.tag == tag {
        return b
    }
    for int i = 0, i < b.children.length, i++ {
        Box f = findBoxByTag(b.children[i], tag)
        if f != null { return f }
    }
    return null
}

// Breaks the document into pages, filling pageStartY, pageEndY,
// pageNames and pageBoxes. Every document has at least one page,
// including an empty one: a sheet with nothing on it is still a sheet.
void func paginateDocument(root:Box) {
    arr[int] ys = []
    arr[int] ends = []
    arr[text] names = []
    arr[PageBox] boxes = []
    pageStartY = ys
    pageEndY = ends
    pageNames = names
    pageBoxes = boxes
    if root == null { return }

    arr[ColumnUnit] units = []
    Box host = paginationHost(root)
    // The units are collected for a page rather than a column, so a
    // `break-before: page` forces one and a `break-before: column` does
    // not. On screen it is the other way about, which is what Chromium
    // does: a page break inside a multi-column container leaves the
    // column where it was, because on screen there is no page to break.
    fragForPage = true
    collectColumnUnits(host, units, 0, host.children.length)
    fragForPage = false

    if units.length == 0 {
        ys.push(0)
        ends.push(root.h)
        names.push('')
        boxes.push(pageBoxFor('', 1))
        return
    }
    int docBottom = 0
    for int k = 0, k < units.length, k++ {
        docBottom = maxInt(docBottom, units[k].bottom)
    }

    int i = 0
    int index = 1
    int top = 0
    while index <= PAGE_LIMIT {
        // The name is the one this page's first unit asked for, which is
        // what keeps this from being circular: the box decides how much
        // fits, and the name that decides the box is known before it.
        text name = units[i].box.style.pageName
        PageBox box = pageBoxFor(name, index)
        int areaH = maxInt(box.height - box.marginTop - box.marginBottom, 1)
        ys.push(top)
        names.push(name)
        boxes.push(box)

        int at = 0 - 1
        int j = i + 1
        while j < units.length {
            bool overflow = units[j].bottom - top > areaH && units[j].top > top
            if !units[j].forceBefore && !overflow {
                j++
                continue
            }
            at = columnBreakPoint(units, j, i)
            break
        }
        if at > i {
            ends.push(units[at].top)
            i = at
            top = units[at].top
            index++
            continue
        }
        // Nothing here may be broken, so either the rest fits or it is
        // a box taller than the sheet. A box taller than the sheet is
        // cut at the page's edge rather than left to run off it, which
        // is what Chromium does: a 700px block on a 500px page prints
        // two pages and a 1200px block prints three.
        if docBottom > top + areaH {
            ends.push(top + areaH)
            top = top + areaH
            index++
            while i + 1 < units.length && units[i + 1].top < top { i++ }
            continue
        }
        ends.push(docBottom)
        return
    }
}

// The area of a page, which is the page box less its margins.
int func pageAreaWidth(box:PageBox) {
    return maxInt(box.width - box.marginLeft - box.marginRight, 1)
}

int func pageAreaHeight(box:PageBox) {
    return maxInt(box.height - box.marginTop - box.marginBottom, 1)
}
