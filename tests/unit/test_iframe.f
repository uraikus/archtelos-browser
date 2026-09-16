// <iframe> is a nested browsing context, not a container: the standard
// does not render its child nodes, it renders the document its src
// names. The children stay in the DOM -- every engine keeps them -- but
// painting them is what made a page's fallback text show through.

import ../../src/browser/page.f
import ../assert.f

// ---- the element's own children are not laid out ----------------------
Page p1 = pageFromHtml('<!doctype html><body><iframe>FALLBACK SHOULD NOT SHOW</iframe></body>', 'about:blank', 800)
arr[Node] frames = []
collectElements(p1.doc, 'iframe', frames)
checkEqInt(frames.length, 1, 'the iframe element is in the DOM')
checkEq(textContent(frames[0]), 'FALLBACK SHOULD NOT SHOW', 'its fallback text is in the DOM too')

Box fb = findBoxForTag(p1.root, 'iframe')
check(fb != null, 'the iframe generates a box')
checkEqInt(fb.kind, BOX_IFRAME, 'it is a frame box, not a block container')
checkEqInt(fb.children.length, 0, 'the fallback text is not laid out')
check(!boxTreeHasText(p1.root, 'FALLBACK SHOULD NOT SHOW'), 'the fallback text is nowhere in the box tree')

// ---- the default size the standard gives it ---------------------------
checkEqInt(fb.w, 300 + fb.bl + fb.br, 'default width is 300 plus its border')
checkEqInt(fb.h, 150 + fb.bt + fb.bb, 'default height is 150 plus its border')

// ---- width and height attributes are honoured -------------------------
Page p2 = pageFromHtml('<!doctype html><body><iframe width="120" height="60"></iframe></body>', 'about:blank', 800)
Box fb2 = findBoxForTag(p2.root, 'iframe')
checkEqInt(fb2.w, 120 + fb2.bl + fb2.br, 'the width attribute sizes the frame')
checkEqInt(fb2.h, 60 + fb2.bt + fb2.bb, 'the height attribute sizes the frame')

// ---- the document named by src is loaded and laid out -----------------
Page p3 = loadPage('tests/fixtures/frame-outer.html', 800)
Box fb3 = findBoxForTag(p3.root, 'iframe')
check(fb3 != null, 'the outer document has a frame box')
check(fb3.frameKey != null && loadedFrames[fb3.frameKey] != null, 'the frame loaded a document of its own')
check(boxTreeHasText(loadedFrames[fb3.frameKey], 'INNER'), 'the loaded document is laid out inside the frame')
check(!boxTreeHasText(p3.root, 'FALLBACK'), 'the fallback text is still not rendered')

finish('iframe')
