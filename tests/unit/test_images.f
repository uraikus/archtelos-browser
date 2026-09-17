// Which documents get looked at for images.
//
// An <img> is found by walking the document, and the walk is skipped on
// a document with no image element in it -- 2 ms of a 102 ms render on
// a page that has none. What makes that safe is where the flag is set:
// `newElement` is the one place a node with a tag is made, so no
// insertion path can put an image into a tree without it.
//
// These checks are that claim, one per path that reaches `newElement`
// by a different route. Each uses a DIFFERENT image file, because
// `loadedImages` is a cache keyed by URL that outlives a page: a second
// case naming a file the first case loaded would pass whether its own
// document was walked or not.
import ../../src/browser/page.f
import ../assert.f

Page func imagePage(markup:text) {
    return pageFromHtml('<!doctype html><body style="margin:0">' + markup + '</body>',
                        'tests/fixtures/page.html', 400)
}

// Whether the image this element names was fetched and decoded. The
// resolved URL is the one gatherImages stamped on the element, so this
// asks the cache the same question the painter asks it.
bool func imageLoaded(p:Page, tag:text) {
    arr[Node] found = []
    collectElements(p.doc, tag, found)
    if found.length == 0 { return false }
    text key = getAttr(found[0], 'data-resolved-src')
    if key == null { return false }
    return loadedImages[key] != null
}

// ---- the ordinary path, anchored to something visible -----------------
// tile.png is 10x10, so a 100px-wide box is 100 tall only if the image
// loaded and its natural ratio was read.
Page p1 = imagePage('<img src="tile.png" style="width:100px">')
check(imageLoaded(p1, 'img'), 'an image in the body is loaded')
Box b1 = findBoxForTag(p1.root, 'img')
check(b1 != null, 'and it has a box')
checkEqInt(b1.h, 100, 'whose height comes from the natural ratio of the image that loaded')

// ---- foster parenting -------------------------------------------------
// An <img> between a <table> and its first row is moved out of the table
// by "foster parenting", so the element the walk has to find is not
// where the source put it.
Page p2 = imagePage('<table><img src="red.png" style="width:60px"><tr><td>x</td></tr></table>')
check(imageLoaded(p2, 'img'), 'an image foster-parented out of a table is loaded')
Box b2 = findBoxForTag(p2.root, 'img')
check(b2 != null && b2.h == 60, 'and is sized by the image it loaded')

// ---- foreign content --------------------------------------------------
// Inside <svg> the tree builder takes a different insertion path, and
// the element it makes is in another namespace. It is still an element
// with a src, and this browser still fetches it.
Page p3 = imagePage('<svg><image href="x"></image></svg><img src="fit.png" style="width:40px">')
check(imageLoaded(p3, 'img'), 'an image beside foreign content is loaded')

// ---- a document inside a frame ----------------------------------------
// The outer document has no image at all. The inner one does, and it is
// parsed after the outer document was, so the answer for one document
// must not be the answer for the other.
Page p4 = loadPage('tests/fixtures/frame-outer-image.html', 400)
Box fb = findBoxForTag(p4.root, 'iframe')
check(fb != null && fb.frameKey != null, 'the outer document has a frame')
check(loadedFrames[fb.frameKey] != null, 'and the frame loaded a document')
Box inner = findBoxForTag(loadedFrames[fb.frameKey], 'img')
check(inner != null, 'the framed document has an image box')
checkEqInt(inner.w, 9, 'sized by nine.png, which only a walk of that document could have loaded')

finish('images')
