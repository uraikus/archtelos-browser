// The preload scanner.
//
// A browser that waits for tree construction to finish before it asks
// the network for a stylesheet has already wasted the parse. The
// scanner walks the raw bytes once, before the tokenizer sees them,
// and reports the resource URLs a document is going to want.
//
// It is deliberately not a parser. It does not build a tree, it does
// not care whether the markup is well formed, and it is allowed to be
// wrong in the cheap direction: a URL it misses is merely fetched
// later, at the speed of a browser without a scanner. It is not
// allowed to be wrong in the expensive direction -- a URL it invents
// is a request the page never asked for.
import ../../src/net/preload.f
import ../assert.f

arr[PreloadHint] func scan(html:text) {
    return scanPreloads(html.toAscii())
}

void func checkOne(html:text, url:text, kind:int, label:text) {
    arr[PreloadHint] hits = scan(html)
    if hits.length != 1 {
        check(false, `${label}: expected 1 hint, got ${hits.length}`)
        return
    }
    checkEq(hits[0].url, url, label)
    checkEqInt(hits[0].kind, kind, `${label} (kind)`)
}

void func checkNone(html:text, label:text) {
    arr[PreloadHint] hits = scan(html)
    if hits.length == 0 { check(true, label)  return }
    check(false, `${label}: expected nothing, got ${hits[0].url}`)
}

// ---- the three kinds ------------------------------------------------
checkOne('<link rel=stylesheet href=a.css>', 'a.css', PRELOAD_STYLESHEET, 'a stylesheet link is found')
checkOne('<img src=b.png>', 'b.png', PRELOAD_IMAGE, 'an image is found')
checkOne('<script src=c.js></script>', 'c.js', PRELOAD_SCRIPT, 'a script is found')

// ---- attribute value syntax -----------------------------------------
checkOne('<img src="d.png">', 'd.png', PRELOAD_IMAGE, 'a double-quoted value')
checkOne("<img src='e.png'>", 'e.png', PRELOAD_IMAGE, 'a single-quoted value')
checkOne('<img   src = "f.png" >', 'f.png', PRELOAD_IMAGE, 'spaces around the equals sign')
checkOne('<IMG SRC=G.png>', 'G.png', PRELOAD_IMAGE, 'an upper-case tag and attribute name')
checkOne('<img alt="a > b" src=h.png>', 'h.png', PRELOAD_IMAGE, 'a quoted value containing a greater-than')
checkOne('<img src=i.png?a=1&b=2>', 'i.png?a=1&b=2', PRELOAD_IMAGE, 'a query string in an unquoted value')
checkOne('<img data-x src=j.png>', 'j.png', PRELOAD_IMAGE, 'a valueless attribute before the one wanted')
// The tokenizer's unquoted attribute value state ends on whitespace or
// `>` and on nothing else, so a trailing slash belongs to the value.
// Chromium 141 agrees: `<img src=k.png/>` requests `k.png/`. The
// scanner has to make the same request the tree is going to make, or
// the one it makes is wasted and the real one happens anyway.
checkOne('<img src=k.png/>', 'k.png/', PRELOAD_IMAGE, 'a trailing slash belongs to an unquoted value')
checkOne('<img src=k2.png />', 'k2.png', PRELOAD_IMAGE, 'but a space before it ends the value')
checkOne('<img src="k3.png"/>', 'k3.png', PRELOAD_IMAGE, 'and a quoted value ends at its quote')

// ---- what is not a resource -----------------------------------------
checkNone('<img>', 'an image with no src')
checkNone('<img src="">', 'an image with an empty src')
checkNone('<link rel=icon href=fav.ico>', 'a link that is not a stylesheet')
checkNone('<link href=orphan.css>', 'a link with no rel')
checkNone('<link rel="alternate stylesheet" href=alt.css>', 'an alternate stylesheet')
checkNone('<script>var x = 1</script>', 'an inline script')
checkNone('<img src="data:image/png;base64,AAAA">', 'a data: URL')
checkNone('Plain prose with no markup in it at all.', 'text with no tag at all')

// ---- places a URL-shaped thing is not a URL --------------------------
checkNone('<!-- <img src=commented.png> -->', 'markup inside a comment')
checkNone('<script>document.write("<img src=written.png>")</script>', 'markup inside a script body')
checkNone('<style>/* <img src=styled.png> */</style>', 'markup inside a style body')
checkNone('<textarea><img src=typed.png></textarea>', 'markup inside a textarea')
checkNone('<title><img src=titled.png></title>', 'markup inside a title')

// ---- several, in document order --------------------------------------
arr[PreloadHint] many = scan('<link rel=stylesheet href=1.css><img src=2.png><script src=3.js></script><img src=4.png>')
checkEqInt(many.length, 4, 'four resources are found')
checkEq(many[0].url, '1.css', 'the first is the stylesheet')
checkEq(many[1].url, '2.png', 'the second is the image')
checkEq(many[2].url, '3.js', 'the third is the script')
checkEq(many[3].url, '4.png', 'the fourth is the second image')

// A page that names the same sprite forty times wants one request.
arr[PreloadHint] dupes = scan('<img src=same.png><img src=same.png><img src=other.png><img src=same.png>')
checkEqInt(dupes.length, 2, 'a repeated URL is reported once')
checkEq(dupes[0].url, 'same.png', 'the first occurrence is the one kept')
checkEq(dupes[1].url, 'other.png', 'and the distinct one survives')

// ---- the scanner stops being useful past a point ---------------------
// Scanning the whole of a large document costs more than the requests
// it would start. Everything past the cap is left to the tree.
text wide = ''
for int i = 0, i < 40, i++ { wide = wide + `<img src=n${i}.png>` }
arr[PreloadHint] capped = scan(wide)
check(capped.length <= preloadMaxHints, 'the scanner reports no more than its cap')
check(capped.length > 0, 'and still reports something')

// ---- a real document head --------------------------------------------
text doc = '<!doctype html><html><head><meta charset=utf-8><title>A page</title>' +
           '<link rel="stylesheet" href="/style/main.css">' +
           '<link rel=preconnect href=//cdn.example>' +
           '<script src="/js/app.js" defer></script>' +
           '</head><body><h1>Hi</h1><img src="/img/hero.jpg" alt="a hero"></body></html>'
arr[PreloadHint] headHits = scan(doc)
checkEqInt(headHits.length, 3, 'a realistic head yields three resources')
checkEq(headHits[0].url, '/style/main.css', 'the stylesheet')
checkEq(headHits[1].url, '/js/app.js', 'the script')
checkEq(headHits[2].url, '/img/hero.jpg', 'the image')

finish('preload')
