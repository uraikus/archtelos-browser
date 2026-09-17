// The page pipeline shared by the windowed browser and the offscreen
// tests: fetch, parse, gather stylesheets and images, compute styles,
// lay out at a width, paint onto the canvas.

import ../paint/paint.f
import ../layout/paginate.f
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

// Runs the preload scanner over the decoded source and starts fetching
// what it found. Returns immediately: the requests run on the worker
// threads while this thread parses, which is the whole point of
// scanning before the parse rather than after it.
void func startPreload(base:text, src:ascii) {
    preloadReset()
    if archtelosNoPreload { return }
    if !isHttpUrl(base) { return }
    arr[PreloadHint] hints = scanPreloads(src)
    arr[text] urls = []
    for int i = 0, i < hints.length, i++ {
        text abs = withoutFragment(resolveUrl(base, hints[i].url))
        // A worker speaks HTTP and nothing else; a local file costs
        // nothing to read on the thread that needs it.
        if isHttpUrl(abs) { urls.push(abs) }
    }
    preloadDispatch(urls)
}

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
    if !sawImageElement { return }
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

// Fetches every background image a computed style names, storing it
// under its resolved URL and rewriting the style to hold that URL so
// the painter can find it. Styles are shared between elements that
// matched the same rules, so this may see one twice; resolving an
// already-absolute URL returns it unchanged.
// Fetches one image a style names and returns the URL it was stored
// under, which is what the painter looks it up by.
text func fetchStyleImage(page:Page, raw:text) {
    ascii a = raw.toAscii()
    if a == null || asciiStartsWithLower(a, 'data:', 0) { return raw }
    text target = resolveUrl(page.url, raw)
    if loadedImages[target] == null {
        Resource r = fetchUrl(target)
        if r.ok {
            http holder = {'url': 'http://localhost/', 'body': r.data}
            img decoded = holder.toImg()
            if decoded != null { loadedImages[target] = decoded }
        }
    }
    return target
}

// The images a ::before or ::after names in its `content`, resolved and
// loaded in place so the generated box can find them under the same key
// as any other image.
void func gatherContentImages(page:Page, nid:int, which:text) {
    ContentRun run = pseudoContentRunOf(nid, which)
    if run == null { return }
    for int i = 0, i < run.urls.length, i++ {
        if run.urls[i] == null { continue }
        run.urls[i] = fetchStyleImage(page, run.urls[i])
    }
}

void func gatherBackgroundImages(page:Page, n:Node) {
    if anyContentUrl && n.kind == NODE_ELEMENT && n.id > 0 {
        gatherContentImages(page, n.id, 'before')
        gatherContentImages(page, n.id, 'after')
    }
    // CSS Content 3 §2.1: the image an ordinary element's `content`
    // names, loaded under the same key as any other so the box built
    // for it can find it.
    if n.kind == NODE_ELEMENT && n.style.contentUrl != '' {
        n.style.contentUrl = fetchStyleImage(page, n.style.contentUrl)
    }
    if n.kind == NODE_ELEMENT && n.style.listImageUrl != '' {
        n.style.listImageUrl = fetchStyleImage(page, n.style.listImageUrl)
    }
    if n.kind == NODE_ELEMENT && n.style.borderImageUrl != '' {
        n.style.borderImageUrl = fetchStyleImage(page, n.style.borderImageUrl)
    }
    // Every layer past the first, which the style keeps in its own list.
    if n.kind == NODE_ELEMENT && n.style.bgExtra.length > 0 {
        for int i = 0, i < n.style.bgExtra.length, i++ {
            // Read, resolve, write back: assigning to a field of an
            // array element in place writes to a copy in Festina, and
            // the layer's url would stay the unresolved one the
            // stylesheet gave.
            BgLayer l = n.style.bgExtra[i]
            if l.url == '' { continue }
            l.url = fetchStyleImage(page, l.url)
            if l.fadeUrl != '' { l.fadeUrl = fetchStyleImage(page, l.fadeUrl) }
            n.style.bgExtra[i] = l
        }
    }
    if n.kind == NODE_ELEMENT && n.style.backgroundUrl != '' {
        n.style.backgroundUrl = fetchStyleImage(page, n.style.backgroundUrl)
    }
    // cross-fade()'s second image, on the first layer.
    if n.kind == NODE_ELEMENT && n.style.backgroundFadeUrl != '' {
        n.style.backgroundFadeUrl = fetchStyleImage(page, n.style.backgroundFadeUrl)
    }
    for int i = 0, i < n.children.length, i++ { gatherBackgroundImages(page, n.children[i]) }
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
        // Decoded once and used twice: the scanner reads the same
        // bytes the tokenizer is about to.
        ascii src = blobToAsciiSafe(r.data).toAscii()
        int tp = now()
        startPreload(page.url, src)
        timing('preload scan', tp)
        page.doc = parseHtml(src)
        int tc = now()
        preloadCollect()
        timing('preload wait', tc)
    }
    timing('parse', t1)
    gatherFrames(page)
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
    // No scan: there is no base to resolve against and nothing was
    // fetched. Clearing the cache keeps a resource fetched for an
    // earlier page from being served to this one unrevalidated.
    preloadReset()
    page.doc = parseHtmlText(html)
    gatherFrames(page)
    preparePage(page, width)
    page.loaded = true
    return page
}

Node func errorDocument(url:text, error:text) {
    return parseHtmlText(`<html><head><title>Cannot load page</title></head><body style="font-family: sans-serif; margin: 40px"><h1 style="color:#b00">Cannot load page</h1><p>The page at <b>${url}</b> could not be loaded.</p><p><code>${error}</code></p></body></html>`)
}

// How deep a frame may nest before this stops following src. A page
// that frames itself would otherwise recurse until the stack gives out.
const int MAX_FRAME_DEPTH = 3
int frameDepth = 0

// Lays out the document a frame names, into its own box tree.
//
// This deliberately does NOT reset the node registry: the frame's nodes
// have to coexist with the nodes of the document that contains them.
// It does reset the cascade, because a stylesheet inside a frame must
// not reach the page around it -- and the caller runs it before its own
// cascade for exactly that reason.
Box func loadFrameDocument(url:text, width:int, height:int) {
    if frameDepth >= MAX_FRAME_DEPTH { return null }
    Resource r = fetchUrl(url)
    if !r.ok { return null }
    frameDepth++
    Node doc = parseHtmlBlob(r.data)
    Page inner
    inner.url = r.finalUrl
    inner.doc = doc
    inner.width = width
    cascadeReset()
    setCssViewport(width, height)
    arr[int] count = [0]
    gatherStylesheets(inner, doc, count)
    gatherImages(inner)
    computeStyles(doc)
    Box root = layoutDocument(doc, width)
    frameDepth--
    return root
}

// Resolves every frame's src and lays its document out, before the
// containing page's own cascade runs.
void func gatherFrames(page:Page) {
    if !sawFrameElement { return }
    arr[Node] frames = []
    collectElements(page.doc, 'iframe', frames)
    collectElements(page.doc, 'frame', frames)
    for int i = 0, i < frames.length, i++ {
        Node n = frames[i]
        text src = getAttr(n, 'src')
        if src == null || src == '' { continue }
        text target = resolveUrl(page.url, src)
        if target == page.url { continue }
        setAttr(n, 'data-frame-src', target)
        if loadedFrames[target] != null { continue }
        int w = attrPx(n, 'width', FRAME_DEFAULT_W)
        int h = attrPx(n, 'height', FRAME_DEFAULT_H)
        Box root = loadFrameDocument(target, w, h)
        if root != null { loadedFrames[target] = root }
    }
}

// A frame's width/height attribute in pixels, or the default.
int func attrPx(n:Node, name:text, dflt:int) {
    text v = getAttr(n, name)
    if v == null { return dflt }
    int px = v.trim().toInt()
    if px == null || px <= 0 { return dflt }
    return px
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
    // Background images come from computed styles, so they cannot be
    // collected with the <img> elements before the cascade has run.
    if anyBackgroundUrl || anyContentUrl {
        int tb = now()
        gatherBackgroundImages(page, page.doc)
        timing('background images', tb)
    }
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
    page.height = page.root.h + page.root.mt + page.root.mb
}

// Paints the document into the canvas region starting at screen row
// `top`, scrolled by `scrollY`, for `viewHeight` rows.
// One page of a paginated render: the strip of the document that begins
// at `startY`, placed inside the page box's margins.
//
// Nothing is moved to make a page. The document is laid out once, at the
// page area's width, and a page is that document drawn at an offset --
// which is the same thing a scroll position is, and uses the same
// painter.
//
// A box that straddles a page boundary is painted whole, because the
// painter culls by box and not by pixel, so the margins are laid back
// over it afterwards in the page's own colour. The page box's background
// is the root element's, propagated to it (CSS2 §13.2).
void func paintPagedPage(page:Page, box:PageBox, startY:int, endY:int) {
    if page.root == null { return }
    int t0 = now()
    int areaW = pageAreaWidth(box)
    // How much of the sheet this page actually carries: a page that ends
    // at a break before its area is full leaves the rest of the sheet
    // blank, rather than showing the content the next page begins with.
    int areaH = minInt(pageAreaHeight(box), maxInt(endY - startY, 0))
    int bg = canvasBackground(page.root)
    applyFillColor(bg)
    drawRect(0, 0, box.width, box.height)
    fillAlpha(1.0)
    paintScrollY = startY
    paintViewHeight = areaH
    saveState()
    translate(box.marginLeft, box.marginTop - startY)
    paintDocument(page.root, startY, startY + areaH)
    restoreState()
    applyFillColor(bg)
    drawRect(0, 0, box.width, box.marginTop)
    drawRect(0, box.marginTop + areaH, box.width, box.height - box.marginTop - areaH)
    drawRect(0, 0, box.marginLeft, box.height)
    drawRect(box.marginLeft + areaW, 0, box.width - box.marginLeft - areaW, box.height)
    fillAlpha(1.0)
    timing('paint', t0)
}

void func paintPage(page:Page, top:int, scrollY:int, viewHeight:int) {
    if page.root == null { return }
    int t0 = now()
    int bg = canvasBackground(page.root)
    applyFillColor(bg)
    drawRect(0, top, page.width, viewHeight)
    fillAlpha(1.0)
    // The scroll offset is what a fixed background undoes, so the
    // painter is told about it rather than inferring it from the
    // transform it is drawing under.
    paintScrollY = scrollY
    paintViewHeight = viewHeight
    saveState()
    translate(0, top - scrollY)
    paintDocument(page.root, scrollY, scrollY + viewHeight)
    restoreState()
    timing('paint', t0)
}
