// The preload scanner: one pass over the raw bytes of a document,
// before tree construction, reporting the resources it is going to
// want. Fetching them can then overlap parsing instead of following
// it.
//
// This is not a second HTML parser and must not become one. It walks
// bytes, it keeps no stack, it has no opinion about nesting, and it
// stops after `preloadMaxHints` resources or `preloadScanBytes` bytes,
// whichever comes first -- past that point the tree is close enough
// behind that the scan costs more than the head start it buys.
//
// Where it does look at markup it agrees with the tokenizer exactly,
// because a URL it reads differently from the tree builder is a
// request nobody wanted and does not save the request somebody did.

import ../util/text.f

const int PRELOAD_STYLESHEET = 1
const int PRELOAD_IMAGE = 2
const int PRELOAD_SCRIPT = 3

struct PreloadHint {
    url:text
    kind:int
}

int preloadMaxHints = 24
int preloadScanBytes = 65536

// Attribute values wanted from the tag being scanned. Festina has no
// tuples and no multiple return values, so a scan that has to yield
// several strings yields them here -- see FINDINGS.md, "one value out
// of a function".
text preloadAttrSrc = ''
text preloadAttrHref = ''
text preloadAttrRel = ''

// Reads one attribute value starting at `i`, exactly as the
// tokenizer's attribute value states do: a quoted value ends at its
// quote, an unquoted one ends at whitespace or `>` and at nothing
// else. Returns the index just past the value; the value itself is in
// `preloadScanValue`.
text preloadScanValue = ''
int func preloadReadAttrValue(s:ascii, from:int) {
    int n = s.length
    int i = from
    preloadScanValue = ''
    if i >= n { return i }
    int q = s.charCodeAt(i)
    if q == CH_QUOTE || q == CH_APOS {
        i++
        int start = i
        while i < n && s.charCodeAt(i) != q { i++ }
        preloadScanValue = s.slice(start, i).toText()
        if i < n { i++ }
        return i
    }
    int start = i
    while i < n {
        int c = s.charCodeAt(i)
        if isSpaceCode(c) || c == CH_GT { break }
        i++
    }
    preloadScanValue = s.slice(start, i).toText()
    return i
}

// Walks the attributes of a start tag whose name ends at `from`,
// filling preloadAttrSrc / preloadAttrHref / preloadAttrRel. Returns the index just past
// the tag's `>`, or the end of input.
int func preloadScanAttributes(s:ascii, from:int) {
    int n = s.length
    int i = from
    preloadAttrSrc = ''
    preloadAttrHref = ''
    preloadAttrRel = ''
    while i < n {
        int c = s.charCodeAt(i)
        if isSpaceCode(c) { i++  continue }
        if c == CH_GT { return i + 1 }
        if c == CH_SLASH { i++  continue }
        int nameStart = i
        while i < n {
            int d = s.charCodeAt(i)
            if isSpaceCode(d) || d == CH_EQ || d == CH_GT || d == CH_SLASH { break }
            i++
        }
        ascii name = asciiLower(s.slice(nameStart, i))
        while i < n && isSpaceCode(s.charCodeAt(i)) { i++ }
        if i < n && s.charCodeAt(i) == CH_EQ {
            i++
            while i < n && isSpaceCode(s.charCodeAt(i)) { i++ }
            i = preloadReadAttrValue(s, i)
            if name == 'src' { preloadAttrSrc = preloadScanValue }
            else if name == 'href' { preloadAttrHref = preloadScanValue }
            else if name == 'rel' { preloadAttrRel = preloadScanValue }
        }
    }
    return i
}

// The raw text elements, whose contents are bytes rather than markup.
// A scanner that reads them finds URLs that are never requested --
// wrong in the expensive direction.
bool func preloadIsRawTextTag(tag:ascii) {
    return tag == 'script' || tag == 'style' || tag == 'textarea' || tag == 'title'
}

// Skips to just past `</tag`, the way the RAWTEXT and RCDATA states
// leave those elements.
int func preloadSkipRawText(s:ascii, from:int, tag:ascii) {
    int n = s.length
    int i = from
    while i < n {
        int lt = asciiIndexOf(s, '</', i)
        if lt < 0 { return n }
        int after = lt + 2
        if asciiStartsWithLower(s, tag, after) {
            int end = after + tag.length
            if end >= n { return n }
            int c = s.charCodeAt(end)
            if isSpaceCode(c) || c == CH_GT || c == CH_SLASH { return end }
        }
        i = lt + 2
    }
    return n
}

bool func preloadIsDataUrl(u:text) {
    ascii a = u.toAscii()
    if a == null { return false }
    return asciiStartsWithLower(a, 'data:', 0)
}

bool func preloadRelIsStylesheet(rel:text) {
    ascii a = rel.toAscii()
    if a == null { return false }
    if asciiIndexOfLower(a, 'alternate', 0) >= 0 { return false }
    return asciiIndexOfLower(a, 'stylesheet', 0) >= 0
}

void func preloadAddHint(hints:arr[PreloadHint], seen:map[bool], url:text, kind:int) {
    if url == null || url == '' { return }
    if preloadIsDataUrl(url) { return }
    if seen[url] != null { return }
    seen[url] = true
    PreloadHint h
    h.url = url
    h.kind = kind
    hints.push(h)
}

arr[PreloadHint] func scanPreloads(s:ascii) {
    arr[PreloadHint] hints = []
    map[bool] seen = {}
    if s == null { return hints }
    int n = s.length
    if n > preloadScanBytes { n = preloadScanBytes }
    int i = 0
    while i < n && hints.length < preloadMaxHints {
        int lt = asciiIndexOf(s, '<', i)
        if lt < 0 || lt >= n { break }
        i = lt + 1
        if i >= n { break }
        // Comments, doctypes, CDATA and end tags carry no resource.
        if asciiStartsWith(s, '!--', i) {
            int end = asciiIndexOf(s, '-->', i)
            i = end < 0 ? n : end + 3
            continue
        }
        int c = s.charCodeAt(i)
        if c == CH_BANG || c == CH_QUESTION || c == CH_SLASH {
            int gt = asciiIndexOf(s, '>', i)
            i = gt < 0 ? n : gt + 1
            continue
        }
        if !isAlphaCode(c) { continue }
        int nameStart = i
        while i < n && isAlnumCode(s.charCodeAt(i)) { i++ }
        ascii tag = asciiLower(s.slice(nameStart, i))
        i = preloadScanAttributes(s, i)
        if tag == 'img' { preloadAddHint(hints, seen, preloadAttrSrc, PRELOAD_IMAGE) }
        else if tag == 'script' { preloadAddHint(hints, seen, preloadAttrSrc, PRELOAD_SCRIPT) }
        else if tag == 'link' {
            if preloadRelIsStylesheet(preloadAttrRel) { preloadAddHint(hints, seen, preloadAttrHref, PRELOAD_STYLESHEET) }
        }
        if preloadIsRawTextTag(tag) { i = preloadSkipRawText(s, i, tag) }
    }
    return hints
}

// ---------------------------------------------------------------------
// Prefetching what the scan found.
//
// The scan is only worth doing if the requests it starts overlap the
// parse that follows it, so the fetches run on four worker threads
// while the main thread tokenizes and builds the tree.
//
// Collecting the results is the hard part. A worker answers with
// `reply`, and the reply runs a callback on the main thread -- from
// the event loop, which straight-line code never reaches, so a
// callback posted during a page load fires after the page has been
// laid out and painted. `drain()` blocks until a worker has finished
// its queue but does not pump main's loop, so it does not help either.
//
// What does work is a manually-managed value. A `T?` posted to a
// thread crosses by reference rather than being deep-copied
// (specification §20.4), so main and the workers share one `Batch`:
// the workers write into its arrays, `drain()` is the barrier, and
// main reads them afterwards. See FINDINGS.md, "a worker's answer
// cannot be collected synchronously".
//
// The four bodies below are the same code four times because a thread
// body may not call a top-level function and a pool instance cannot
// learn its own index -- see FINDINGS.md, "a thread body cannot share
// code". They differ only in the offset they start at.

struct PreloadBatch {
    urls:arr[text]
    bodies:arr[blob]
    status:arr[int]
    types:arr[text]
    stride:int
    ua:text
}

const int PRELOAD_WORKERS = 4

thread preloadWorker0 {
    on message(worker:thread, msg:PreloadBatch?) {
        for int i = 0, i < msg.urls.length, i = i + msg.stride {
            http req = {'url': msg.urls[i], 'method': 'GET', 'headers': {'user-agent': msg.ua, 'accept': '*/*'}}
            try { req.send() } catch (e:text) { msg.status[i] = -1  continue }
            if req.code == null { msg.status[i] = -1  continue }
            msg.status[i] = req.code
            msg.bodies[i] = req.toBlob()
            text ct = req.headers['content-type']
            msg.types[i] = ct == null ? '' : ct
        }
    }
}
thread preloadWorker1 {
    on message(worker:thread, msg:PreloadBatch?) {
        for int i = 1, i < msg.urls.length, i = i + msg.stride {
            http req = {'url': msg.urls[i], 'method': 'GET', 'headers': {'user-agent': msg.ua, 'accept': '*/*'}}
            try { req.send() } catch (e:text) { msg.status[i] = -1  continue }
            if req.code == null { msg.status[i] = -1  continue }
            msg.status[i] = req.code
            msg.bodies[i] = req.toBlob()
            text ct = req.headers['content-type']
            msg.types[i] = ct == null ? '' : ct
        }
    }
}
thread preloadWorker2 {
    on message(worker:thread, msg:PreloadBatch?) {
        for int i = 2, i < msg.urls.length, i = i + msg.stride {
            http req = {'url': msg.urls[i], 'method': 'GET', 'headers': {'user-agent': msg.ua, 'accept': '*/*'}}
            try { req.send() } catch (e:text) { msg.status[i] = -1  continue }
            if req.code == null { msg.status[i] = -1  continue }
            msg.status[i] = req.code
            msg.bodies[i] = req.toBlob()
            text ct = req.headers['content-type']
            msg.types[i] = ct == null ? '' : ct
        }
    }
}
thread preloadWorker3 {
    on message(worker:thread, msg:PreloadBatch?) {
        for int i = 3, i < msg.urls.length, i = i + msg.stride {
            http req = {'url': msg.urls[i], 'method': 'GET', 'headers': {'user-agent': msg.ua, 'accept': '*/*'}}
            try { req.send() } catch (e:text) { msg.status[i] = -1  continue }
            if req.code == null { msg.status[i] = -1  continue }
            msg.status[i] = req.code
            msg.bodies[i] = req.toBlob()
            text ct = req.headers['content-type']
            msg.types[i] = ct == null ? '' : ct
        }
    }
}

// What the workers brought back, by absolute URL. `fetchUrl` looks
// here before it opens a connection.
map[blob] preloadBodies = {}
map[int] preloadStatus = {}
map[text] preloadTypes = {}

PreloadBatch? preloadPending
bool preloadInFlight = false
int preloadRequested = 0
int preloadServed = 0
text preloadUserAgent = ''

void func preloadReset() {
    preloadBodies = {}
    preloadTypes = {}
    preloadStatus = {}
}

// Hands a batch of absolute http(s) URLs to the workers and returns
// at once. Nothing else may touch the batch until preloadCollect.
void func preloadDispatch(urls:arr[text]) {
    if preloadInFlight { preloadCollect() }
    if urls.length == 0 { return }
    PreloadBatch? batch
    batch.urls = []
    batch.bodies = []
    batch.status = []
    batch.types = []
    batch.stride = PRELOAD_WORKERS
    batch.ua = preloadUserAgent
    for int i = 0, i < urls.length, i++ {
        batch.urls.push(urls[i])
        blob empty
        batch.bodies.push(empty)
        batch.status.push(0)
        batch.types.push('')
    }
    preloadRequested = preloadRequested + urls.length
    preloadPending = batch
    preloadInFlight = true
    preloadWorker0.postMessage(batch)
    preloadWorker1.postMessage(batch)
    preloadWorker2.postMessage(batch)
    preloadWorker3.postMessage(batch)
}

// Waits for the workers and moves what they fetched into the cache.
void func preloadCollect() {
    if !preloadInFlight { return }
    preloadWorker0.drain()
    preloadWorker1.drain()
    preloadWorker2.drain()
    preloadWorker3.drain()
    PreloadBatch? batch = preloadPending
    for int i = 0, i < batch.urls.length, i++ {
        if batch.status[i] < 200 || batch.status[i] >= 400 { continue }
        preloadBodies[batch.urls[i]] = batch.bodies[i]
        preloadStatus[batch.urls[i]] = batch.status[i]
        preloadTypes[batch.urls[i]] = batch.types[i]
    }
    preloadInFlight = false
    free batch
}

// The program will not exit while a thread is alive, so whoever owns
// the process has to say when the workers are finished with.
void func preloadShutdown() {
    if preloadInFlight { preloadCollect() }
    preloadWorker0.kill()
    preloadWorker1.kill()
    preloadWorker2.kill()
    preloadWorker3.kill()
}
