// The page pipeline shared by the windowed browser and the offscreen
// tests: fetch, parse, gather stylesheets and images, compute styles,
// lay out at a width, paint onto the canvas.

import ../paint/paint.f
import ../net/fetch.f
import ../html/parser.f

struct Page {
    url:text
    title:text
    doc:Node
    root:Box
    width:int
    height:int          // document height after layout
    error:text
    loaded:bool
}

int maxImagesPerPage = 60
int maxStylesheetsPerPage = 20

// Stylesheets in document order: <style> elements and
// <link rel=stylesheet>, both honoring a media attribute.
void func gatherStylesheets(page:Page, n:Node, count:arr[int]) {
    if n.kind != NODE_ELEMENT {
        for int i = 0, i < n.children.length, i++ { gatherStylesheets(page, n.children[i], count) }
        return
    }
    if n.tag == 'style' {
        text media = getAttr(n, 'media')
        if media == null || media.toAscii() == null || evaluateMediaQuery(media.toAscii()) {
            text css = textContent(n)
            ascii a = css.toAscii()
            if a == null { a = textToAsciiSafeForCss(css) }
            cascadeAddAuthorSheet(parseStylesheet(a))
        }
        return
    }
    if n.tag == 'link' {
        text rel = textLower(getAttr(n, 'rel'))
        text href = getAttr(n, 'href')
        if rel != null && href != null && count[0] < maxStylesheetsPerPage {
            ascii relA = rel.toAscii()
            bool isSheet = relA != null && asciiIndexOf(relA, 'stylesheet', 0) >= 0 && asciiIndexOf(relA, 'alternate', 0) < 0
            text media = getAttr(n, 'media')
            bool mediaOk = media == null || media.toAscii() == null || evaluateMediaQuery(media.toAscii())
            if isSheet && mediaOk {
                count[0] = count[0] + 1
                text target = resolveUrl(page.url, href)
                Resource r = fetchUrl(target)
                if r.ok {
                    cascadeAddAuthorSheet(parseStylesheet(blobToAsciiSafe(r.data).toAscii()))
                }
            }
        }
        return
    }
    for int i = 0, i < n.children.length, i++ { gatherStylesheets(page, n.children[i], count) }
}

// Loads every <img src>, storing the decoded image under its resolved
// URL and stamping that URL on the element for layout to find.
void func gatherImages(page:Page) {
    arr[Node] imgs = []
    collectElements(page.doc, 'img', imgs)
    int loaded = 0
    for int i = 0, i < imgs.length, i++ {
        Node n = imgs[i]
        text src = getAttr(n, 'src')
        if src == null || src == '' { continue }
        ascii a = src.toAscii()
        if a == null { continue }
        if asciiStartsWithLower(a, 'data:', 0) { continue }
        text target = resolveUrl(page.url, src)
        setAttr(n, 'data-resolved-src', target)
        if loadedImages[target] != null { continue }
        if loaded >= maxImagesPerPage { continue }
        loaded++
        Resource r = fetchUrl(target)
        if !r.ok { continue }
        http holder = {'url': 'http://localhost/', 'body': r.data}
        img decoded = holder.toImg()
        if decoded != null { loadedImages[target] = decoded }
    }
}

Page func loadPage(url:text, width:int) {
    Page page
    page.url = url
    page.title = ''
    page.width = width
    page.error = ''
    page.loaded = false
    int t0 = now()
    Resource r = fetchUrl(url)
    timing('fetch', t0)
    int t1 = now()
    nodeRegistryReset()
    if !r.ok {
        page.error = r.error
        page.doc = errorDocument(url, r.error)
    } else {
        page.url = r.finalUrl
        page.doc = parseHtmlBlob(r.data)
    }
    timing('parse', t1)
    preparePage(page, width)
    page.loaded = r.ok
    return page
}

// A page from HTML already in memory (tests, error pages).
Page func pageFromHtml(html:text, baseUrl:text, width:int) {
    Page page
    page.url = baseUrl
    page.title = ''
    page.width = width
    page.error = ''
    nodeRegistryReset()
    page.doc = parseHtmlText(html)
    preparePage(page, width)
    page.loaded = true
    return page
}

Node func errorDocument(url:text, error:text) {
    return parseHtmlText(`<html><head><title>Cannot load page</title></head><body style="font-family: sans-serif; margin: 40px"><h1 style="color:#b00">Cannot load page</h1><p>The page at <b>${url}</b> could not be loaded.</p><p><code>${error}</code></p></body></html>`)
}

void func timing(label:text, since:int) {
    if archtelosTiming { log(`[timing] ${label}: ${now() - since} ms`) }
}

void func preparePage(page:Page, width:int) {
    int t0 = now()
    cascadeReset()
    setCssViewport(width, cssViewportHeight)
    arr[int] count = [0]
    gatherStylesheets(page, page.doc, count)
    timing('stylesheets', t0)
    int t1 = now()
    gatherImages(page)
    timing('images', t1)
    Node titleNode = findElement(page.doc, 'title')
    page.title = titleNode == null ? '' : textContent(titleNode).replace(spaceRun, ' ').trim()
    int t2 = now()
    computeStyles(page.doc)
    timing('cascade', t2)
    int t3 = now()
    layoutPage(page, width)
    timing('layout', t3)
    if archtelosTiming { log(layoutProfile()) }
}

void func layoutPage(page:Page, width:int) {
    page.width = width
    cssViewportWidth = width
    page.root = layoutDocument(page.doc, width)
    if page.root == null {
        page.height = 0
        return
    }
    numberListItems(page.root)
    page.height = page.root.h + page.root.mt + page.root.mb
}

// Paints the document into the canvas region starting at screen row
// `top`, scrolled by `scrollY`, for `viewHeight` rows.
void func paintPage(page:Page, top:int, scrollY:int, viewHeight:int) {
    if page.root == null { return }
    int t0 = now()
    int bg = canvasBackground(page.root)
    applyFillColor(bg)
    drawRect(0, top, page.width, viewHeight)
    fillAlpha(1.0)
    saveState()
    translate(0, top - scrollY)
    paintDocument(page.root, scrollY, scrollY + viewHeight)
    restoreState()
    timing('paint', t0)
}
