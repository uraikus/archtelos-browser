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
    // What the painter needs to know about this document, taken when
    // its layout finished and put back before it is painted. See
    // DocFlags in paint.f: the questions are globals, and a second
    // document laid out afterwards would otherwise answer them.
    flags:DocFlags
    // Where the document starts scrolled to, which
    // `scroll-initial-target` on an element in its own flow asks for.
    // Layout works it out and the shell applies it, because the shell
    // owns the page's scroll position (todo.md).
    initialScrollY:int
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
    // The painter's per-document questions are answered while the box
    // tree is built, so they belong to this page and not to whichever
    // page is laid out next. See DocFlags in paint.f.
    page.flags = captureDocFlags()
    page.initialScrollY = docInitialScrollY
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
// ---- the page margin boxes --------------------------------------------
//
// Sixteen boxes in the page margin (CSS Paged Media 3 §5), each drawn
// from its own `content`. Measured in todo.md against Chromium's own
// print, read out of the PDF: the five along each of the top and
// bottom edges are vertically centred in their band, the three down
// each side are top-, middle- and bottom-aligned in the side region,
// and the corners align INWARD, toward the page content.
//
// A margin box inherits from the ROOT element rather than from `body`,
// which the measurement settles: `html { font: 16px monospace }`
// reaches the box and `body { ... }` does not, because the page
// context inherits from the root.

// Where one box goes, as (x, y, w, h). Four values out of a function
// need globals (FINDINGS.md, "one value out of a function").
int mbX = 0
int mbY = 0
int mbW = 0
int mbH = 0

void func marginBoxRect(box:PageBox, slot:int) {
    int innerW = maxInt(box.width - box.marginLeft - box.marginRight, 0)
    int innerH = maxInt(box.height - box.marginTop - box.marginBottom, 0)
    int right = box.width - box.marginRight
    int bottom = box.height - box.marginBottom
    if slot == MB_TOP_LEFT_CORNER { mbX = 0  mbY = 0  mbW = box.marginLeft  mbH = box.marginTop  return }
    if slot == MB_TOP_RIGHT_CORNER { mbX = right  mbY = 0  mbW = box.marginRight  mbH = box.marginTop  return }
    if slot == MB_BOTTOM_LEFT_CORNER { mbX = 0  mbY = bottom  mbW = box.marginLeft  mbH = box.marginBottom  return }
    if slot == MB_BOTTOM_RIGHT_CORNER { mbX = right  mbY = bottom  mbW = box.marginRight  mbH = box.marginBottom  return }
    if slot == MB_TOP_LEFT || slot == MB_TOP_CENTER || slot == MB_TOP_RIGHT {
        mbX = box.marginLeft  mbY = 0  mbW = innerW  mbH = box.marginTop  return
    }
    if slot == MB_BOTTOM_LEFT || slot == MB_BOTTOM_CENTER || slot == MB_BOTTOM_RIGHT {
        mbX = box.marginLeft  mbY = bottom  mbW = innerW  mbH = box.marginBottom  return
    }
    if slot == MB_LEFT_TOP || slot == MB_LEFT_MIDDLE || slot == MB_LEFT_BOTTOM {
        mbX = 0  mbY = box.marginTop  mbW = box.marginLeft  mbH = innerH  return
    }
    mbX = right  mbY = box.marginTop  mbW = box.marginRight  mbH = innerH
}

// The style a margin box draws in: the root element's, with whatever
// the box itself declares on top. Only the handful of properties a
// margin box is written for are read; the rest are recorded in todo.md
// rather than half-applied.
Style func marginBoxStyle(rootStyle:Style, decls:arr[PageDecl]) {
    Style s = rootStyle
    for int i = 0, i < decls.length, i++ {
        if decls[i].name == 'color' {
            int c = parseCssColor(decls[i].value, rootStyle.color)
            if c != COLOR_UNSET { s.color = c }
        } else if decls[i].name == 'font-size' {
            int px = pageMarginPx(decls[i].value, rootStyle.fontSize)
            if px > 0 {
                s.fontSize = px
                s.fontKey = `${s.fontSize}|${s.fontBold ? 1 : 0}|${s.fontItalic ? 1 : 0}|${s.fontFamily}`
            }
        }
    }
    return s
}

int func marginBoxAlignOf(decls:arr[PageDecl], slot:int, vertical:bool) {
    int a = vertical ? marginBoxDefaultVAlign(slot) : marginBoxDefaultAlign(slot)
    text want = vertical ? 'vertical-align' : 'text-align'
    for int i = 0, i < decls.length, i++ {
        if decls[i].name != want { continue }
        ascii v = asciiLower(asciiTrim(decls[i].value))
        if v == 'left' || v == 'start' || v == 'top' { a = MBALIGN_START }
        else if v == 'center' || v == 'middle' { a = MBALIGN_CENTER }
        else if v == 'right' || v == 'end' || v == 'bottom' { a = MBALIGN_END }
    }
    return a
}

void func paintPageMarginBoxes(box:PageBox, name:text, index:int, total:int, rootStyle:Style, blank:bool) {
    for int slot = 0, slot < MB_COUNT, slot++ {
        arr[PageDecl] decls = marginBoxDecls(slot, name, index, blank)
        if decls.length == 0 { continue }
        text content = ''
        for int i = 0, i < decls.length, i++ {
            if decls[i].name == 'content' {
                content = marginBoxContent(decls[i].value, index, total)
            }
        }
        if content == '' { continue }
        marginBoxRect(box, slot)
        if mbW <= 0 || mbH <= 0 { continue }
        Style s = marginBoxStyle(rootStyle, decls)
        int w = measureWidth(s, content)
        int lh = lineHeightOf(s)
        int align = marginBoxAlignOf(decls, slot, false)
        int valign = marginBoxAlignOf(decls, slot, true)
        int x = mbX
        if align == MBALIGN_CENTER { x = mbX + Math.floorDiv(mbW - w, 2) }
        else if align == MBALIGN_END { x = mbX + mbW - w }
        int top = mbY
        if valign == MBALIGN_CENTER { top = mbY + Math.floorDiv(mbH - lh, 2) }
        else if valign == MBALIGN_END { top = mbY + mbH - lh }
        setFontFor(s)
        applyFillColor(s.color)
        drawText(content, x, top + fontAscent(s))
    }
    fillAlpha(1.0)
}

void func paintPagedPage(page:Page, box:PageBox, startY:int, endY:int, index:int, total:int) {
    if page.root == null { return }
    restoreDocFlags(page.flags)
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
    // The boxes go on last, over the margins that were just laid back
    // over the content -- which is what puts them in the margin rather
    // than under it. A document that declares none pays one boolean.
    if anyPageMarginBox {
        paintPageMarginBoxes(box, pageNames[index], index + 1, total, page.root.style, pageBlanks[index])
    }
    timing('paint', t0)
}

void func paintPage(page:Page, top:int, scrollY:int, viewHeight:int) {
    if page.root == null { return }
    restoreDocFlags(page.flags)
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
