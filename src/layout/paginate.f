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
// Whether each page is one this generated to reach a side, rather than
// one the document filled. `:blank` selects those and nothing else, and
// a page that carries no content is not the same thing: a page can end
// short because the next box would not fit.
arr[bool] pageBlanks = []

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

// The first page is a right-hand one, so an odd index is a right page
// and an even one a left page (CSS2 §13.2.4) -- the same parity
// `pageRuleMatches` uses for `:left` and `:right`, kept in one place so
// the two cannot drift.
bool func pageIsRight(index:int) {
    return index - Math.floorDiv(index, 2) * 2 == 1
}

// Which side the break just before `units[at]` asked for, or BRK_AUTO.
//
// The value is read back off the boxes rather than carried on the unit.
// A ColumnUnit is built for every line of every multi-column container
// on screen, and a field there would cost every one of those pages a
// struct they never read -- which is what a single `int` on `Style`
// was measured to cost (benchmarks.md, "What one `int` on `Style`
// costs"). This runs once per break of a print instead.
int func pageSideAt(host:Box, units:arr[ColumnUnit], at:int) {
    int v = units[at].box.style.breakBefore
    if v == BRK_LEFT || v == BRK_RIGHT { return v }
    // Otherwise the break is the previous sibling's `break-after`, which
    // the unit collector carried forward in `pendingForce`. The siblings
    // it skips are skipped here in the same order, so the sibling found
    // is the one that set the flag.
    int i = units[at].childIndex - 1
    while i >= 0 {
        Box c = host.children[i]
        if c.kind == BOX_TEXT || c.kind == BOX_BR || boxIsOutOfFlow(c) || boxIsFloated(c) {
            i--
            continue
        }
        int a = c.style.breakAfter
        if a == BRK_LEFT || a == BRK_RIGHT { return a }
        return BRK_AUTO
    }
    return BRK_AUTO
}

// Breaks the document into pages, filling pageStartY, pageEndY,
// pageNames and pageBoxes. Every document has at least one page,
// including an empty one: a sheet with nothing on it is still a sheet.
void func paginateDocument(root:Box) {
    arr[int] ys = []
    arr[int] ends = []
    arr[text] names = []
    arr[PageBox] boxes = []
    arr[bool] blanks = []
    pageStartY = ys
    pageEndY = ends
    pageNames = names
    pageBoxes = boxes
    pageBlanks = blanks
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
        blanks.push(false)
        boxes.push(pageBoxFor('', 1, false))
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
        PageBox box = pageBoxFor(name, index, false)
        int areaH = maxInt(box.height - box.marginTop - box.marginBottom, 1)
        ys.push(top)
        names.push(name)
        blanks.push(false)
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
            // CSS 2 §13.3.1: `left` and `right` force one break or two,
            // whichever it takes for the next page to be formatted as a
            // page of that side. The second one produces a page with
            // nothing on it, which is the only way a blank page is made
            // here and so the only thing `:blank` can select.
            int side = pageSideAt(host, units, at)
            if side != BRK_AUTO && pageIsRight(index) != (side == BRK_RIGHT)
                && index < PAGE_LIMIT {
                ys.push(top)
                ends.push(top)
                names.push('')
                blanks.push(true)
                boxes.push(pageBoxFor('', index, true))
                index++
            }
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
