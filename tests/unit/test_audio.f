// The audio element.
//
// Chromium 141, on the same markup:
//
//   <audio src=...>              display none, no box at all
//   <audio src=... controls>     display inline, 300 x 54
//   <audio controls><source>     display inline, 300 x 54, and the
//                                fallback text is not rendered
//
// An <audio> is invisible until it is asked for controls, which is what
// Chromium's own user-agent stylesheet says and what this one now says
// too -- a rule that needs an attribute selector inside :not().
import ../../src/browser/page.f
import ../assert.f

Box func boxFor(root:Box, tag:text, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, tag, all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

bool func treeHasText(b:Box, needle:text) {
    if b.kind == BOX_TEXT && b.content != null && b.content.split(needle).length > 1 { return true }
    for int i = 0, i < b.children.length, i++ {
        if treeHasText(b.children[i], needle) { return true }
    }
    return false
}

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:600px">'

// ---- without controls, nothing is generated -------------------------
Page p1 = pageFromHtml(head + '<audio id="a1" src="x.mp3"></audio><p id="after">after</p></body>', 'about:blank', 600)
check(boxFor(p1.root, 'audio', 'a1') == null, 'an audio with no controls generates no box')

// ---- with controls, a control bar of Chromium's size ----------------
Page p2 = pageFromHtml(head + '<audio id="a2" src="x.mp3" controls></audio></body>', 'about:blank', 600)
Box a2 = boxFor(p2.root, 'audio', 'a2')
check(a2 != null, 'an audio with controls generates a box')
checkEqInt(a2.w, 300, 'as wide as Chromium draws its controls')
checkEqInt(a2.h, 54, 'and as tall')

// ---- the fallback content is not rendered ---------------------------
// Like an iframe's children, the content of an audio element is what a
// user agent that cannot play it shows instead. This one draws controls,
// so the fallback is not shown.
Page p3 = pageFromHtml(head + '<audio id="a3" controls><source src="x.mp3" type="audio/mpeg">fallback text</audio></body>', 'about:blank', 600)
Box a3 = boxFor(p3.root, 'audio', 'a3')
check(a3 != null, 'an audio with a source child still generates a box')
checkEqInt(a3.w, 300, 'of the same width')
check(!treeHasText(p3.root, 'fallback'), 'and the fallback text is not rendered')

// ---- it is inline, so it sits on a line with text -------------------
Page p4 = pageFromHtml(head + '<p id="p">before <audio id="a4" src="x.mp3" controls></audio></p></body>', 'about:blank', 600)
Box a4 = boxFor(p4.root, 'audio', 'a4')
check(a4 != null, 'an audio inside a paragraph generates a box')
check(a4.x > 0, 'and follows the text on the line rather than starting a block')

finish('audio')
