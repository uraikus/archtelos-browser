// The URL's fragment (HTML, "navigate to a fragment"): the element it names
// is `:target`, and the document starts scrolled to it, less the root's
// `scroll-padding-top` and the element's own `scroll-margin-top`. Every
// expectation is what Chromium 141 answered for the same document loaded
// as file.html#fragment -- its scrollY after the load, and which element
// `:target` matched -- from the rows todo.md keeps.

import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../../src/browser/page.f
import ../assert.f

int green = packColor(0, 255, 0, 255)

// A page with `sp` pixels above and below one element, loaded at `frag`.
Page func pageAt(css:text, sp:int, body:text, frag:text) {
    return pageFromHtml('<!doctype html><style>body{margin:0}' + css
        + `.sp{height:${sp}px} :target{background:rgb(0,255,0)}</style><div class="sp"></div>` + body
        + '<div class="sp"></div>', `about:blank#${frag}`, 800)
}

// The tag of the first element `:target` turned green, or '' for none.
text func targetTag(p:Page) {
    for int k = 0, k < 2, k++ {
        arr[Box] all = []
        collectBoxesForTag(p.root, k == 0 ? 'div' : 'a', all)
        for int i = 0, i < all.length, i++ {
            if all[i].style.background == green && getAttr(all[i].node, 'class') != 'sp' {
                return k == 0 ? 'div' : 'a'
            }
        }
    }
    return ''
}

text T = '<div id="t" style="height:50px">x</div>'

Page a1 = pageAt('', 1000, T, 't')
checkEq(targetTag(a1), 'div', 'the element whose id is the fragment is :target')
checkEqInt(a1.initialScrollY, 1000, 'and the page starts scrolled to it')

Page a2 = pageAt('', 1000, T, 'zzz')
checkEq(targetTag(a2), '', 'a fragment naming nothing matches nothing')
checkEqInt(a2.initialScrollY, 0, 'and scrolls nowhere')

Page a3 = pageAt('', 1000, T, '')
checkEq(targetTag(a3), '', 'an empty fragment is no target')
checkEqInt(a3.initialScrollY, 0, 'and scrolls nowhere')

Page a4 = pageAt('', 1000, T, 'top')
checkEq(targetTag(a4), '', 'the fragment `top` with no element of that name is no target')
checkEqInt(a4.initialScrollY, 0, 'and is the top of the page')

Page a5 = pageAt('', 1000, '<a name="t">x</a>', 't')
checkEq(targetTag(a5), 'a', 'an <a name> answers a fragment no id does')
checkEqInt(a5.initialScrollY, 1000, 'and is scrolled to')

Page a6 = pageAt('#t{scroll-margin-top:30px}', 1000, T, 't')
checkEqInt(a6.initialScrollY, 970, 'the target\'s scroll-margin-top is left above it')

Page a7 = pageAt('html{scroll-padding-top:40px}', 1000, T, 't')
checkEqInt(a7.initialScrollY, 960, 'the root\'s scroll-padding-top is too')

Page a8 = pageAt('html{scroll-padding-top:40px}#t{scroll-margin-top:30px}', 1000, T, 't')
checkEqInt(a8.initialScrollY, 930, 'and the two add')

Page a9 = pageAt('', 1000, T, '%74')
checkEq(targetTag(a9), 'div', 'the fragment is percent-decoded')
checkEqInt(a9.initialScrollY, 1000, 'before it is compared')

Page a10 = pageAt('', 1000, T, 'T')
checkEq(targetTag(a10), '', 'and compared as it is, in case')
checkEqInt(a10.initialScrollY, 0, 'so a different case names nothing')

Page a11 = pageAt('#t{display:none}', 1000, T, 't')
checkEqInt(a11.initialScrollY, 0, 'an element with no box has nothing to scroll to')

Page a12 = pageAt('#t{position:fixed;top:5px}', 1000, T, 't')
checkEqInt(a12.initialScrollY, 0, 'a fixed one is where it is on every scroll')

// Inside a scroll container the container scrolls first, and the page then
// to where the target has come to: 300px into a 100px box at y=500.
Page a13 = pageAt('', 500, '<div id="sc" style="height:100px;overflow:auto"><div style="height:300px"></div><div id="t" style="height:50px">x</div><div style="height:300px"></div></div>', 't')
arr[Box] scBoxes = []
collectBoxesForTag(a13.root, 'div', scBoxes)
Box scBox = null
for int i = 0, i < scBoxes.length, i++ {
    if getAttr(scBoxes[i].node, 'id') == 'sc' { scBox = scBoxes[i] }
}
checkEqInt(boxScrollTop(scBox), 300, 'a container holding the target scrolls to it')
checkEqInt(a13.initialScrollY, 500, 'and the page to the container')

// The instrument: the same document with no fragment at all must have
// none of it, or every check above would hold for a page that always
// scrolled to #t.
Page b0 = pageFromHtml('<!doctype html><style>body{margin:0}.sp{height:1000px} :target{background:rgb(0,255,0)}</style><div class="sp"></div>' + T + '<div class="sp"></div>', 'about:blank', 800)
checkEq(targetTag(b0), '', 'with no fragment nothing is the target')
checkEqInt(b0.initialScrollY, 0, 'and the page is at the top')

// A link to a fragment keeps everything else of the address it is on, the
// query included.
checkEq(resolveUrl('http://h/a/b.html?q=1#old', '#x'), 'http://h/a/b.html?q=1#x', 'a fragment link keeps the query')
checkEq(resolveUrl('file:///a/b.html', '#x'), 'file:///a/b.html#x', 'and a file path')
checkEq(urlFragmentOf('http://h/a#a%20b'), 'a b', 'a fragment is percent-decoded')

finish('fragment targets')
