// CSS Box Alignment 3 on a block container, and the two interaction
// properties that are readable without an interaction model.
//
// `justify-self` aligns a block-level box in the inline axis of its
// containing block, and `justify-items` on the container is the default
// its children take. Both need the box to be narrower than the
// container, so every fixture gives it a width.
import ../../src/layout/layout.f
import ../../src/paint/paint.f
import ../../src/html/parser.f
import ../assert.f

Box func layoutHtml(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, width)
}

Box func findById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

text head = '<body style="margin:0;font:16px/20px monospace">'

// A 40px box inside a 200px container, aligned however asked.
Box func alignedBox(outer:text, inner:text) {
    Box root = layoutHtml(head + '<div style="width:200px;' + outer + '">'
        + '<div id="t" style="width:40px;height:10px;' + inner + '"></div>'
        + '</div></body>', 400)
    return findById(root, 't')
}

// ---- justify-self --------------------------------------------------------

checkEqInt(alignedBox('', '').x, 0, 'a block box starts at the inline start by default')
checkEqInt(alignedBox('', 'justify-self:center').x, 80, 'justify-self:center centres it')
checkEqInt(alignedBox('', 'justify-self:end').x, 160, 'justify-self:end puts it at the far edge')
checkEqInt(alignedBox('', 'justify-self:start').x, 0, 'and justify-self:start leaves it alone')

// `right` and `left` are the physical spellings of the same two ends.
checkEqInt(alignedBox('', 'justify-self:right').x, alignedBox('', 'justify-self:end').x,
           'justify-self:right is the same end as justify-self:end')
checkEqInt(alignedBox('', 'justify-self:left').x, alignedBox('', 'justify-self:start').x,
           'and left is the same as start')

// ---- justify-items -------------------------------------------------------
// The container's justify-items is what a child with no justify-self of
// its own takes, and the child's own value wins over it.

checkEqInt(alignedBox('justify-items:center', '').x, 80,
           'justify-items on the container centres the child')
checkEqInt(alignedBox('justify-items:center', 'justify-self:start').x, 0,
           "and the child's own justify-self wins over it")
checkEqInt(alignedBox('justify-items:center', 'justify-self:end').x, 160,
           'whichever end it asks for')

// An auto margin still decides it, because the alignment applies to
// what is left after the margins are resolved.
checkEqInt(alignedBox('justify-items:end', 'margin-left:auto;margin-right:auto').x, 80,
           'auto margins centre the box whatever justify-items says')

// ---- text-overflow -------------------------------------------------------
// An ellipsis needs a line that overflows a box that clips, so the
// fixture is the only shape in which the property does anything.

text clipped = 'width:60px;white-space:nowrap;overflow:hidden'

Box tooLong = layoutHtml(head + '<div id="t" style="' + clipped
    + '">xxxxxxxxxxxxxxxxxxxx</div></body>', 400)
Box ellipsis = layoutHtml(head + '<div id="t" style="' + clipped
    + ';text-overflow:ellipsis">xxxxxxxxxxxxxxxxxxxx</div></body>', 400)
Box tPlain = findById(tooLong, 't')
Box tEllip = findById(ellipsis, 't')
check(tPlain.lines.length > 0 && tEllip.lines.length > 0, 'both fixtures have a line')
text plainRun = tPlain.lines[0].frags[0].content
text ellipRun = tEllip.lines[0].frags[0].content
check(plainRun != ellipRun, 'text-overflow:ellipsis changes what is drawn')
check(ellipRun.length < plainRun.length, 'by shortening the run')
checkEq(ellipRun[ellipRun.length - 1], '…', 'and ending it with an ellipsis')
check(tEllip.lines[0].frags[0].w <= 60, 'the shortened run fits the box')

// A line that fits is left alone -- the property truncates an overflow
// rather than every line.
Box fits = layoutHtml(head + '<div id="t" style="' + clipped
    + ';text-overflow:ellipsis">xx</div></body>', 400)
checkEq(findById(fits, 't').lines[0].frags[0].content, 'xx',
        'a line that fits is not truncated')

// Without a clip there is nothing to ellipsise, so the text stands.
Box noClip = layoutHtml(head
    + '<div id="t" style="width:60px;white-space:nowrap;text-overflow:ellipsis">'
    + 'xxxxxxxxxxxxxxxxxxxx</div></body>', 400)
checkEq(findById(noClip, 't').lines[0].frags[0].content, 'xxxxxxxxxxxxxxxxxxxx',
        'a box that does not clip does not ellipsise either')

// ---- pointer-events ------------------------------------------------------
// One of the two interaction properties this engine can answer, because
// it has hit testing: `none` makes a box invisible to it.

Box hitRoot = layoutHtml(head
    + '<div id="a" style="width:100px;height:40px"></div></body>', 400)
Box plainHit = hitTest(hitRoot, 50, 20)
check(plainHit != null, 'an ordinary box is found by hit testing')

Box noneRoot = layoutHtml(head
    + '<div id="a" style="width:100px;height:40px;pointer-events:none"></div></body>', 400)
Box noneHit = hitTest(noneRoot, 50, 20)
check(noneHit == null || attrOf(noneHit.node.id, 'id') != 'a',
      'pointer-events:none takes the box out of hit testing')

// What is behind it is still found, which is the point of the property
// rather than of hiding the box.
Box behindRoot = layoutHtml(head
    + '<div id="under" style="width:100px;height:40px">'
    + '<span id="over" style="pointer-events:none">xx</span></div></body>', 400)
Box behindHit = hitTest(behindRoot, 5, 5)
check(behindHit != null, 'something behind a pointer-events:none box is still hit')

// ---- interactivity: inert, which is not pointer-events -----------------
// The other one. `inert` takes the box AND its subtree out of hit
// testing, and a descendant cannot undo it -- which is exactly where it
// parts from `pointer-events: none`, whose descendants this engine
// searches on purpose because a child may ask for pointer events back.
// Chromium's rows are in todo.md.

text func hitIdAt(css:text, kidCss:text, x:int, y:int) {
    Box r = layoutHtml(head
        + `<div id="a" style="width:100px;height:40px;${css}">`
        + `<div id="k" style="width:100px;height:40px;${kidCss}"></div>`
        + '</div></body>', 400)
    Box h = hitTest(r, x, y)
    if h == null { return 'none' }
    text id = attrOf(h.node.id, 'id')
    return id == null ? 'anon' : id
}

// The control: with nothing declared the child is what a point over
// both lands on.
checkEq(hitIdAt('', '', 50, 20), 'k', 'the innermost box at the point is what is hit')

// `pointer-events: none` lets a child opt back in.
checkEq(hitIdAt('pointer-events:none', 'pointer-events:auto', 50, 20), 'k',
        'a child of a pointer-events:none box can ask for pointer events back')

// `inert` does not. What the point lands on instead is whatever is
// behind the subtree -- the root element in Chromium, an anonymous box
// here -- so the check is that nothing in the inert subtree is hit
// rather than that nothing at all is.
bool func hitOutsideInert(css:text, kidCss:text) {
    text id = hitIdAt(css, kidCss, 50, 20)
    return id != 'a' && id != 'k'
}

check(hitOutsideInert('interactivity:inert', 'interactivity:auto'),
      'a child of an inert box cannot')
check(hitOutsideInert('interactivity:inert', ''),
      'and an inert box is not hit itself')
check(hitOutsideInert('interactivity:inert;pointer-events:auto', ''),
      'inert beats pointer-events: auto on the same box')
checkEq(hitIdAt('interactivity:auto', '', 50, 20), 'k',
        'interactivity: auto is the initial value and changes nothing')

// The instrument: the two properties have to disagree on the same
// fixture, or this section is testing one of them twice.
check(hitIdAt('pointer-events:none', 'pointer-events:auto', 50, 20)
      != hitIdAt('interactivity:inert', 'interactivity:auto', 50, 20),
      'inert and pointer-events really do differ on a child that opts back in')

finish('alignment')
