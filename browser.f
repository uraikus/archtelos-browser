// Archtelos Browser -- an HTML5/CSS3 renderer written in Festina.
//
//   festina compile browser.f -o browser
//   ./browser https://example.com
//   ./browser examples/hello.html
//   ./browser examples/hello.html --screenshot out.png --width 900
//
// Keys: wheel / Up / Down / PageUp / PageDown / Home / End scroll,
// BackSpace goes back, F5 reloads, F6 (or a click on the address
// bar) edits the address, Return loads it, Escape cancels.

import src/browser/page.f

const int TOOLBAR_H = 36
const int STATUS_H = 22
const int SCROLL_STEP = 60

Page page
arr[text] history = []
int historyIndex = -1
int scrollY = 0
bool editing = false
text editText = ''
text statusText = ''
bool haveWindow = false

color toolbarBg = '#e8e8e8'
color toolbarLine = '#b0b0b0'
color fieldBg = 'white'
color fieldBorder = '#8a8a8a'
color fieldFocus = '#3b7dd8'
color textDark = '#202020'
color textDim = '#606060'
font uiFont = '13px sans-serif'
font uiBold = 'bold 13px sans-serif'

text welcomeHtml = `<!doctype html>
<html><head><title>Archtelos Browser</title>
<style>
  body { font-family: sans-serif; margin: 40px auto; max-width: 640px; color: #222; line-height: 1.5 }
  h1 { color: #2a4d8f; border-bottom: 2px solid #2a4d8f; padding-bottom: 6px }
  kbd { font-family: monospace; background: #eee; border: 1px solid #ccc; border-radius: 3px; padding: 0 4px }
  .tip { background: #fff8dc; border-left: 4px solid #e0b000; padding: 8px 12px }
</style></head>
<body>
<h1>Archtelos Browser</h1>
<p>An HTML5 and CSS3 renderer written entirely in the <b>Festina</b> language:
its own HTML parser, CSS cascade, block and inline layout, tables, lists, images and this window.</p>
<p class="tip">Press <kbd>F6</kbd> or click the address bar, type a URL and press <kbd>Return</kbd>.</p>
<ul>
  <li>Scroll with the mouse wheel, <kbd>Up</kbd>/<kbd>Down</kbd>, <kbd>PageUp</kbd>/<kbd>PageDown</kbd>, <kbd>Home</kbd>/<kbd>End</kbd></li>
  <li><kbd>BackSpace</kbd> goes back, <kbd>F5</kbd> reloads</li>
  <li>Click a link to follow it; hovering shows its target in the status bar</li>
</ul>
<p>Try <a href="https://example.com/">example.com</a> or a local file such as <a href="examples/hello.html">examples/hello.html</a>.</p>
</body></html>`

int func viewportHeight() {
    return maxInt(clientHeight - TOOLBAR_H - STATUS_H, 1)
}

int func maxScroll() {
    return maxInt(page.height - viewportHeight(), 0)
}

void func clampScroll() {
    scrollY = clampInt(scrollY, 0, maxScroll())
}

// Removes the last code point of a text: there is no substring, so
// the text is split per code point, popped and joined.
text func dropLastChar(t:text) {
    if t == null || t == '' { return '' }
    arr[text] cps = t.split('')
    cps.pop()
    return cps.join('')
}

void func drawToolbar() {
    fillStyle(toolbarBg)
    drawRect(0, 0, clientWidth, TOOLBAR_H)
    fillStyle(toolbarLine)
    drawRect(0, TOOLBAR_H - 1, clientWidth, 1)
    // back button
    changeFont(uiBold)
    fillStyle(historyIndex > 0 ? textDark : textDim)
    drawText('<', 12, 23)
    // address field
    int fieldX = 34
    int fieldW = clientWidth - fieldX - 10
    fillStyle(fieldBg)
    borderColor(editing ? fieldFocus : fieldBorder)
    lineWidth(editing ? 2 : 1)
    drawRect(fieldX, 6, fieldW, TOOLBAR_H - 12)
    borderColor(-1, -1, -1)
    changeFont(uiFont)
    fillStyle(textDark)
    text shown = editing ? editText + '|' : page.url
    if shown == null { shown = '' }
    // clip long addresses by dropping characters from the end
    while measureTextWidth(shown) > fieldW - 12 && shown.length > 4 {
        shown = dropLastChar(shown)
    }
    drawText(shown, fieldX + 6, 23)
}

void func drawStatus() {
    int y = clientHeight - STATUS_H
    fillStyle(toolbarBg)
    drawRect(0, y, clientWidth, STATUS_H)
    fillStyle(toolbarLine)
    drawRect(0, y, clientWidth, 1)
    changeFont(uiFont)
    fillStyle(textDim)
    text s = statusText
    if s == '' {
        s = page.title == '' ? page.url : page.title
        if page.height > 0 { s = `${s}  -  ${page.height}px` }
    }
    if s == null { s = '' }
    while measureTextWidth(s) > clientWidth - 16 && s.length > 4 { s = dropLastChar(s) }
    drawText(s, 8, y + 15)
}

void func repaint() {
    clearCanvas()
    if page.root != null {
        paintPage(page, TOOLBAR_H, scrollY, viewportHeight())
    }
    drawToolbar()
    drawStatus()
    render()
    haveWindow = true
}

void func showStatusNow(msg:text) {
    statusText = msg
    if haveWindow {
        drawStatus()
        render()
    }
}

void func loadInto(url:text) {
    showStatusNow(`Loading ${url} ...`)
    page = loadPage(url, clientWidth)
    scrollY = 0
    statusText = ''
    editing = false
}

void func navigate(url:text) {
    loadInto(url)
    // a new navigation truncates any forward history
    while history.length > historyIndex + 1 { history.pop() }
    history.push(page.url)
    historyIndex = history.length - 1
    repaint()
}

void func goBack() {
    if historyIndex <= 0 { return }
    historyIndex--
    loadInto(history[historyIndex])
    repaint()
}

void func reload() {
    if page.url == null || page.url == '' { return }
    int keep = scrollY
    loadInto(page.url)
    scrollY = keep
    clampScroll()
    repaint()
}

void func scrollBy(dy:int) {
    int before = scrollY
    scrollY = scrollY + dy
    clampScroll()
    if scrollY != before { repaint() }
}

bool func isNavigableHref(href:text) {
    if href == null || href == '' { return false }
    ascii a = href.toAscii()
    if a == null { return true }
    if a.charCodeAt(0) == CH_HASH { return false }
    return !asciiStartsWithLower(a, 'javascript:', 0) && !asciiStartsWithLower(a, 'mailto:', 0) && !asciiStartsWithLower(a, 'tel:', 0)
}

// A wheel over a scroll container scrolls that container; over anything
// else, or over one that has reached its end in the direction asked
// for, the page takes it. That is what a browser does, and what makes a
// scrollable box inside a page usable at all.
void func wheelAt(x:int, y:int, dy:int) {
    if page != null && page.root != null && y >= TOOLBAR_H {
        Box inner = wheelTargetAt(page.root, x, y - TOOLBAR_H + scrollY, dy)
        if inner != null && boxScrollBy(inner, dy) {
            repaint()
            return
        }
        // a container with `overscroll-behavior` other than `auto` has
        // reached its end, so the page does not take what is left
        if wheelChainBlocked { return }
    }
    scrollBy(dy)
}

on mouseWheelUp(x:int, y:int) { wheelAt(x, y, -SCROLL_STEP) }
on mouseWheelDown(x:int, y:int) { wheelAt(x, y, SCROLL_STEP) }

// A wheel tilted sideways scrolls the container under it across. The
// language has no horizontal wheel event and no event carries a
// modifier, so neither a horizontal wheel nor shift-wheel is
// expressible as such -- see FINDINGS.md, finding 38. What X11 does
// send is a press of button 6 or 7, which `on mouseDown` below hands
// here; a Windows build sends nothing at all, and scrolls across only
// by the thumb.
void func wheelAcrossAt(x:int, y:int, dx:int) {
    if page == null || page.root == null || y < TOOLBAR_H { return }
    Box inner = wheelTargetAcrossAt(page.root, x, y - TOOLBAR_H + scrollY, dx)
    if inner != null && boxScrollLeftBy(inner, dx) { repaint() }
}

// X11's own numbering: 6 is a tilt to the left and 7 to the right.
const int BUTTON_WHEEL_LEFT = 6
const int BUTTON_WHEEL_RIGHT = 7

// The scroll container whose thumb the pointer took hold of, and how far
// down the thumb it pressed, so the content does not jump on the first
// pixel of the drag. The box is held by node id rather than by the Box
// itself: a box tree lasts one layout and a drag outlives several.
int dragThumbNode = 0
int dragThumbGrab = 0
// Which bar the drag is on: a box may have both, and the pointer took
// hold of one of them.
bool dragThumbAcross = false

// The box a drag is on, found again in the tree laid out most recently.
Box func dragThumbBox(b:Box) {
    if b.node != null && b.node.id == dragThumbNode
        && (dragThumbAcross ? b.sbH > 0 : b.sbW > 0) { return b }
    for int i = 0, i < b.children.length, i++ {
        Box found = dragThumbBox(b.children[i])
        if found != null { return found }
    }
    return null
}

on mouseDown(x:int, y:int, button:int) {
    if button == BUTTON_WHEEL_LEFT { wheelAcrossAt(x, y, -SCROLL_STEP)  return }
    if button == BUTTON_WHEEL_RIGHT { wheelAcrossAt(x, y, SCROLL_STEP)  return }
    if button != 1 { return }
    if y < TOOLBAR_H {
        if x < 30 {
            goBack()
        } else {
            editing = true
            editText = page.url == null ? '' : page.url
            repaint()
        }
        return
    }
    if editing {
        editing = false
        repaint()
    }
    if y >= clientHeight - STATUS_H || page.root == null { return }
    // A press on a scrollbar's thumb takes hold of it, and nothing else
    // happens with that press: it is not a click on what is behind it.
    int docY = y - TOOLBAR_H + scrollY
    Box thumb = scrollThumbAt(page.root, x, docY)
    if thumb != null {
        dragThumbNode = thumb.node.id
        dragThumbAcross = false
        dragThumbGrab = docY - scrollThumbTop(thumb)
        return
    }
    Box hthumb = scrollHThumbAt(page.root, x, docY)
    if hthumb != null {
        dragThumbNode = hthumb.node.id
        dragThumbAcross = true
        dragThumbGrab = x - scrollHThumbLeft(hthumb)
        return
    }
    text href = linkAt(page.root, x, y - TOOLBAR_H + scrollY)
    if isNavigableHref(href) {
        navigate(resolveUrl(page.url, href))
    }
}

on mouseUp(x:int, y:int, button:int) {
    if button == 1 { dragThumbNode = 0 }
}

on mouse(x:int, y:int) {
    if page.root == null { return }
    // A drag in progress moves the thumb and nothing else: the pointer
    // may leave the bar, and the thumb still follows it, which is what
    // every scrollbar does.
    if dragThumbNode != 0 {
        Box held = dragThumbBox(page.root)
        if held == null { dragThumbNode = 0 }
        else {
            bool moved = dragThumbAcross
                ? scrollHThumbDragTo(held, x - dragThumbGrab)
                : scrollThumbDragTo(held, y - TOOLBAR_H + scrollY - dragThumbGrab)
            if moved { repaint() }
            return
        }
    }
    text before = statusText
    text href = null
    if y >= TOOLBAR_H && y < clientHeight - STATUS_H {
        href = linkAt(page.root, x, y - TOOLBAR_H + scrollY)
    }
    statusText = href == null ? '' : resolveUrl(page.url, href)
    if statusText != before {
        drawStatus()
        render()
    }
}

on keyDown(key:text) {
    if editing {
        if key == 'Return' {
            text target = editText.trim()
            editing = false
            if target != '' {
                ascii a = target.toAscii()
                if a != null && !hasScheme(a) && asciiIndexOf(a, '.', 0) >= 0 && asciiIndexOf(a, '/', 0) != 0 && asciiIndexOf(a, ' ', 0) < 0 {
                    blob probe = target
                    if !probe.exists() { target = 'https://' + target }
                }
                navigate(target)
            } else {
                repaint()
            }
        } else if key == 'Escape' {
            editing = false
            repaint()
        } else if key == 'BackSpace' {
            editText = dropLastChar(editText)
            repaint()
        } else if key.length == 1 {
            editText = editText + key
            repaint()
        }
        return
    }
    if key == 'Down' { scrollBy(SCROLL_STEP) }
    else if key == 'Up' { scrollBy(-SCROLL_STEP) }
    else if key == 'Page_Down' || key == 'Next' || key == ' ' { scrollBy(viewportHeight() - 40) }
    else if key == 'Page_Up' || key == 'Prior' { scrollBy(-(viewportHeight() - 40)) }
    else if key == 'Home' { scrollBy(-scrollY) }
    else if key == 'End' { scrollBy(maxScroll() - scrollY) }
    else if key == 'BackSpace' { goBack() }
    else if key == 'F5' { reload() }
    else if key == 'F6' {
        editing = true
        editText = page.url == null ? '' : page.url
        repaint()
    }
}

on resize() {
    setCssViewport(clientWidth, viewportHeight())
    if page.doc == null { return }
    layoutPage(page, clientWidth)
    clampScroll()
    repaint()
}

on close() { }

// ---- command line ------------------------------------------------------------

text startUrl = ''
text screenshotPath = ''
text printPath = ''
int requestedWidth = 1024
int requestedHeight = 768
bool screenshotHeightGiven = false

for int i = 1, i < argv.length, i++ {
    text arg = argv[i]
    if arg == '--screenshot' && i + 1 < argv.length {
        screenshotPath = argv[i + 1]
        i++
    } else if arg == '--print' && i + 1 < argv.length {
        printPath = argv[i + 1]
        i++
    } else if arg == '--width' && i + 1 < argv.length {
        int w = argv[i + 1].toInt()
        if w != null && w > 0 { requestedWidth = w }
        i++
    } else if arg == '--height' && i + 1 < argv.length {
        int h = argv[i + 1].toInt()
        if h != null && h > 0 {
            requestedHeight = h
            screenshotHeightGiven = true
        }
        i++
    } else if arg == '--help' || arg == '-h' {
        log('usage: browser [url-or-file] [--screenshot out.png] [--print out.png] [--width W] [--height H]')
        log('  --print paginates the document and writes out-1.png, out-2.png, ...')
        close(0)
    } else {
        startUrl = arg
    }
}

setClientWidth(requestedWidth)
setClientHeight(requestedHeight)
// `vh` and the height media features resolve against this. A screenshot
// has no window, so the requested height is the viewport; the canvas may
// later be grown to the whole document, which is a canvas, not a
// viewport.
setCssViewport(requestedWidth, requestedHeight)

// `out.png` page 3 is `out-3.png`: the number goes before the extension
// so the files sort and open as the pictures they are.
text func printPageName(path:text, n:int) {
    ascii a = path.toAscii()
    int dot = 0 - 1
    for int i = 0, i < a.length, i++ {
        if a.charCodeAt(i) == CH_DOT { dot = i }
    }
    if dot <= 0 { return `${path}-${n}` }
    return `${a.slice(0, dot).toText()}-${n}${a.slice(dot, a.length).toText()}`
}

if printPath != '' {
    // A paginated render is the print medium, so the document's print
    // stylesheet is the one that applies -- and the `@page` rules almost
    // always inside it.
    cssMediaPrint = true
    if startUrl == '' {
        page = pageFromHtml(welcomeHtml, 'about:welcome', PAGE_DEFAULT_W)
    } else {
        page = loadPage(startUrl, PAGE_DEFAULT_W)
    }
    // The width to lay out at is the page area's, and the page box comes
    // out of the document's own stylesheet, so it is not known until the
    // document has been read once. It is laid out again at that width
    // rather than guessed at.
    PageBox firstBox = pageBoxFor('', 1)
    int areaW = pageAreaWidth(firstBox)
    setCssViewport(areaW, pageAreaHeight(firstBox))
    preparePage(page, areaW)
    paginateDocument(page.root)
    int written = 0
    for int i = 0, i < pageStartY.length, i++ {
        PageBox pbox = pageBoxes[i]
        setClientWidth(pbox.width)
        setClientHeight(pbox.height)
        clearCanvas()
        paintPagedPage(page, pbox, pageStartY[i], pageEndY[i])
        text out = printPageName(printPath, i + 1)
        if saveCanvas(out) { written++ } else { log(`could not write ${out}`) }
    }
    log(`wrote ${written} page(s) of ${pageStartY.length}, ${firstBox.width}x${firstBox.height}`)
    if page.error != '' { log(`load error: ${page.error}`) }
    close(written > 0 && written == pageStartY.length ? 0 : 1)
}

if screenshotPath != '' {
    // headless: lay out at the requested width, size the canvas to the
    // document (or the requested height) and write a PNG
    if startUrl == '' {
        page = pageFromHtml(welcomeHtml, 'about:welcome', requestedWidth)
    } else {
        page = loadPage(startUrl, requestedWidth)
    }
    int h = screenshotHeightGiven ? requestedHeight : clampInt(page.height, 1, 8000)
    setClientHeight(h)
    clearCanvas()
    paintPage(page, 0, 0, h)
    bool ok = saveCanvas(screenshotPath)
    log(ok ? `wrote ${screenshotPath} (${requestedWidth}x${h}, document ${page.height}px)` : `could not write ${screenshotPath}`)
    if page.error != '' { log(`load error: ${page.error}`) }
    close(ok ? 0 : 1)
}

setCssViewport(clientWidth, viewportHeight())
if startUrl == '' {
    page = pageFromHtml(welcomeHtml, 'about:welcome', clientWidth)
    history.push('about:welcome')
    historyIndex = 0
    repaint()
} else {
    navigate(startUrl)
}
