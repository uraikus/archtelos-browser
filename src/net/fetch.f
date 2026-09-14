// URL resolution and resource fetching. `http` is Festina's built-in
// client (api.md, "Making outbound requests"); a local path is read
// as a blob. There is no way to ask for the current directory, so a
// relative page path stays relative and its resources resolve
// relative to it.

import ../util/text.f

struct Resource {
    ok:bool
    status:int
    data:blob
    finalUrl:text
    contentType:text
    error:text
}

text userAgent = 'Mozilla/5.0 (X11; Linux x86_64) ArchtelosBrowser/0.1 Festina'

bool func hasScheme(u:ascii) {
    int colon = asciiIndexOf(u, ':', 0)
    if colon <= 0 { return false }
    for int i = 0, i < colon, i++ {
        int c = u.charCodeAt(i)
        if !(isAlphaCode(c) || isDigitCode(c) || c == CH_PLUS || c == CH_MINUS || c == CH_DOT) { return false }
    }
    return true
}

bool func isHttpUrl(u:text) {
    ascii a = u.toAscii()
    if a == null { return false }
    return asciiStartsWithLower(a, 'http://', 0) || asciiStartsWithLower(a, 'https://', 0)
}

// Removes '.' and '..' segments from a path.
ascii func normalizePath(path:ascii) {
    arr[ascii] segs = []
    int n = path.length
    int start = 0
    bool absolute = n > 0 && path.charCodeAt(0) == CH_SLASH
    for int i = 0, i <= n, i++ {
        if i == n || path.charCodeAt(i) == CH_SLASH {
            ascii seg = path.slice(start, i)
            start = i + 1
            if seg == '.' || (seg == '' && i < n) { continue }
            if seg == '..' {
                if segs.length > 0 { segs.pop() }
                continue
            }
            segs.push(seg)
        }
    }
    text out = absolute ? '/' : ''
    for int i = 0, i < segs.length, i++ {
        text s = segs[i].toText()
        if i > 0 { out = out + '/' }
        out = out + s
    }
    if n > 0 && path.charCodeAt(n - 1) == CH_SLASH && segs.length > 0 && out != '/' { out = out + '/' }
    return out.toAscii()
}

// Resolves `rel` against `base` per RFC 3986's common cases.
text func resolveUrl(base:text, rel:text) {
    if rel == null { return base }
    ascii r = asciiTrim(rel.toAscii())
    ascii b = base == null ? null : base.toAscii()
    if r == null { return rel }
    if b == null { b = '' }
    if r.length == 0 { return base }
    if hasScheme(r) { return r.toText() }
    // the base's parts
    int schemeEnd = -1
    ascii scheme = ''
    ascii authority = ''
    ascii path = dup(b)
    if hasScheme(b) {
        schemeEnd = asciiIndexOf(b, ':', 0)
        scheme = b.slice(0, schemeEnd + 1)
        ascii rest = b.slice(schemeEnd + 1, b.length)
        if asciiStartsWith(rest, '//', 0) {
            int pathStart = asciiIndexOf(rest, '/', 2)
            if pathStart < 0 {
                authority = rest.slice(2, rest.length)
                path = '/'
            } else {
                authority = rest.slice(2, pathStart)
                path = rest.slice(pathStart, rest.length)
            }
        } else {
            path = rest
        }
    }
    // strip query and fragment from the base path
    int q = asciiIndexOf(path, '?', 0)
    if q >= 0 { path = path.slice(0, q) }
    int hsh = asciiIndexOf(path, '#', 0)
    if hsh >= 0 { path = path.slice(0, hsh) }
    ascii prefix = ''
    if scheme.length > 0 { prefix = scheme + '//' + authority }
    if asciiStartsWith(r, '//', 0) {
        ascii sch = 'https:'
        if scheme.length > 0 { sch = scheme }
        return sch + r
    }
    if r.charCodeAt(0) == CH_HASH || r.charCodeAt(0) == CH_QUESTION {
        return prefix + path + r
    }
    if r.charCodeAt(0) == CH_SLASH {
        return prefix + normalizePath(r)
    }
    // relative to the base's directory
    int lastSlash = -1
    for int i = path.length - 1, i >= 0, i-- {
        if path.charCodeAt(i) == CH_SLASH {
            lastSlash = i
            break
        }
    }
    ascii dir = ''
    if lastSlash >= 0 { dir = path.slice(0, lastSlash + 1) }
    if scheme.length > 0 && dir.length == 0 { dir = '/' }
    ascii joined = dir + r
    // keep a query/fragment out of the normalizer
    ascii tail = ''
    int cut = asciiIndexOf(joined, '?', 0)
    int cutH = asciiIndexOf(joined, '#', 0)
    if cutH >= 0 && (cut < 0 || cutH < cut) { cut = cutH }
    if cut >= 0 {
        tail = joined.slice(cut, joined.length)
        joined = joined.slice(0, cut)
    }
    return prefix + normalizePath(joined) + tail
}

// Strips a fragment identifier.
text func withoutFragment(u:text) {
    ascii a = u.toAscii()
    if a == null { return u }
    int h = asciiIndexOf(a, '#', 0)
    if h < 0 { return u }
    return a.slice(0, h).toText()
}

text func lowerHeader(r:http, name:text) {
    text v = r.headers[name]
    return v
}

Resource func fetchUrl(urlIn:text) {
    Resource res
    res.ok = false
    res.status = 0
    res.finalUrl = urlIn
    res.contentType = ''
    res.error = ''
    text url = withoutFragment(urlIn)
    if !isHttpUrl(url) {
        text path = url
        ascii a = url.toAscii()
        if a != null && asciiStartsWithLower(a, 'file://', 0) {
            path = a.slice(7, a.length).toText()
        }
        blob f = path
        if !f.exists() {
            res.error = `cannot read ${path}`
            return res
        }
        res.ok = true
        res.status = 200
        res.data = f
        res.finalUrl = url
        return res
    }
    text current = url
    for int hop = 0, hop < 6, hop++ {
        http req = {'url': current, 'method': 'GET', 'headers': {'user-agent': userAgent, 'accept': 'text/html,application/xhtml+xml,image/png,image/jpeg,text/css,*/*;q=0.8', 'accept-language': 'en'}}
        try {
            req.send()
        } catch (e:text) {
            res.error = e
            res.finalUrl = current
            return res
        }
        int code = req.code
        if code == null {
            res.error = 'no response'
            return res
        }
        if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) && hop < 5 {
            text loc = req.headers['location']
            if loc != null && loc != '' {
                current = withoutFragment(resolveUrl(current, loc))
                continue
            }
        }
        res.status = code
        res.ok = code >= 200 && code < 400
        res.data = req.toBlob()
        res.finalUrl = current
        text ct = req.headers['content-type']
        res.contentType = ct == null ? '' : ct
        if !res.ok { res.error = `HTTP ${code}` }
        return res
    }
    res.error = 'too many redirects'
    return res
}
