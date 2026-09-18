// Positioning: CSS2 §9.3 and CSS Positioned Layout 3. Until now
// `position` did not appear in src/css at all and every box was static.
// See css-2026.md, "CSS Level 2".

import ../../src/browser/page.f
import ../assert.f

// ---- the properties are computed at all --------------------------------
Page p0 = pageFromHtml('<!doctype html><body><p style="position: relative; top: 5px; left: 7px; z-index: 3">x</p></body>', 'about:blank', 800)
Node el0 = findElement(p0.doc, 'p')
checkEqInt(el0.style.position, POS_RELATIVE, 'position: relative is computed')
checkEqInt(resolveLen(el0.style.top, 0, -1), 5, 'top is computed')
checkEqInt(resolveLen(el0.style.left, 0, -1), 7, 'left is computed')
checkEqInt(el0.style.zIndex, 3, 'z-index is computed')

// ---- relative offsets the box and leaves the flow alone ---------------
Page p1 = pageFromHtml('<!doctype html><body style="margin:0"><div style="height:20px">a</div><div id="m" style="height:20px; position: relative; top: 30px; left: 15px">b</div><div style="height:20px">c</div></body>', 'about:blank', 800)
arr[Box] divs = []
collectBoxesForTag(p1.root, 'div', divs)
checkEqInt(divs.length, 3, 'three divs')
checkEqInt(divs[0].y, 0, 'the first div is at the top')
checkEqInt(divs[1].y, 50, 'the relative div is offset by top')
checkEqInt(divs[1].x, 15, 'and by left')
checkEqInt(divs[2].y, 40, 'the div after it keeps its in-flow position')

// a relative box carries its descendants with it
Page p1b = pageFromHtml('<!doctype html><body style="margin:0"><div style="position: relative; top: 10px"><p style="margin:0">x</p></div></body>', 'about:blank', 800)
arr[Box] inner = []
collectBoxesForTag(p1b.root, 'p', inner)
checkEqInt(inner[0].y, 10, 'a descendant of a relative box moves with it')

// ---- absolute leaves the flow -----------------------------------------
Page p2 = pageFromHtml('<!doctype html><body style="margin:0"><div style="height:20px">a</div><div style="height:20px; position: absolute; top: 100px; left: 50px">b</div><div style="height:20px">c</div></body>', 'about:blank', 800)
arr[Box] d2 = []
collectBoxesForTag(p2.root, 'div', d2)
checkEqInt(d2[2].y, 20, 'an absolute box takes no space in the flow')
checkEqInt(d2[1].y, 100, 'and sits where top says')
checkEqInt(d2[1].x, 50, 'and where left says')

// ---- absolute resolves against the nearest positioned ancestor --------
// The 40px sits above the div as a gap in the flow, so the absolute
// child resolves against a containing block that starts at 40.
Page p3 = pageFromHtml('<!doctype html><body style="margin:0"><div style="height:40px"></div><div style="position: relative; height: 200px"><p id="a" style="position: absolute; top: 10px; left: 20px; margin: 0">x</p></div></body>', 'about:blank', 800)
arr[Box] ap = []
collectBoxesForTag(p3.root, 'p', ap)
checkEqInt(ap[0].y, 50, 'top is measured from the positioned ancestor, not the page')
checkEqInt(ap[0].x, 20, 'and so is left')

// a static ancestor is not a containing block
Page p4 = pageFromHtml('<!doctype html><body style="margin:0"><div style="margin-top: 40px"><p style="position: absolute; top: 10px; margin: 0">x</p></div></body>', 'about:blank', 800)
arr[Box] ap4 = []
collectBoxesForTag(p4.root, 'p', ap4)
checkEqInt(ap4[0].y, 10, 'a static ancestor is skipped when finding the containing block')

// ---- right and bottom -------------------------------------------------
Page p5 = pageFromHtml('<!doctype html><body style="margin:0"><div style="position: relative; width: 400px; height: 300px"><p style="position: absolute; right: 30px; bottom: 40px; width: 100px; height: 20px; margin: 0">x</p></div></body>', 'about:blank', 800)
arr[Box] ap5 = []
collectBoxesForTag(p5.root, 'p', ap5)
checkEqInt(ap5[0].x, 270, 'right positions from the right edge of the containing block')
checkEqInt(ap5[0].y, 240, 'bottom positions from its bottom edge')

// ---- fixed is measured from the viewport ------------------------------
Page p6 = pageFromHtml('<!doctype html><body style="margin:0"><div style="position: relative; margin-top: 300px; height: 100px"><p style="position: fixed; top: 12px; left: 8px; margin: 0">x</p></div></body>', 'about:blank', 800)
arr[Box] ap6 = []
collectBoxesForTag(p6.root, 'p', ap6)
checkEqInt(ap6[0].y, 12, 'a fixed box ignores its positioned ancestor')
checkEqInt(ap6[0].x, 8, 'in both axes')

// ---- the static position (CSS2 §10.3.7) -------------------------------

// A box with an `auto` inset sits where it would have been in flow, not
// at the corner of its containing block. Every number below is
// Chromium's, in todo.md, as the box's position relative to its
// containing block.

Box func staticBox(inner:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0;font:16px/20px monospace">'
        + '<div id="cb" style="position:relative;width:400px;height:200px">'
        + inner + '</div></body>', 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'i', all)
    return all.length > 0 ? all[0] : null
}

// The box under test is an <i>, so that `collectBoxesForTag` finds it
// whether it was written block-level or inline-level.
text ABS = '<i style="position:absolute;display:block;width:30px;height:20px"></i>'

Box sb1 = staticBox(ABS)
checkEqInt(sb1.x, 0, 'a direct child of the containing block starts at its corner')
checkEqInt(sb1.y, 0, 'in both axes')

Box sb2 = staticBox('<div style="height:50px"></div>' + ABS)
checkEqInt(sb2.y, 50, 'a box after a 50px block sits below it')
checkEqInt(sb2.x, 0, 'and still at the left')

Box sb3 = staticBox('<div style="margin-left:60px">' + ABS + '</div>')
checkEqInt(sb3.x, 60, 'a box inside an indented div is indented with it')
checkEqInt(sb3.y, 0, 'and still at the top')

Box sb4 = staticBox('<div style="height:50px"></div>'
                    + '<div style="margin-left:60px">' + ABS + '</div>')
checkEqInt(sb4.x, 60, 'both at once, across')
checkEqInt(sb4.y, 50, 'and down')

// A block-level box among inline content starts on the line after it.
Box sb5 = staticBox('abcde' + ABS)
checkEqInt(sb5.y, 20, 'a block-level box after text starts on the next line')
checkEqInt(sb5.x, 0, 'at the start of it')

// The flow begins inside the containing block's padding.
Page padded = pageFromHtml('<!doctype html><body style="margin:0;font:16px/20px monospace">'
    + '<div id="cb" style="position:relative;width:400px;height:200px;padding:20px">'
    + '<div style="height:50px"></div>' + ABS + '</div></body>', 'about:blank', 800)
arr[Box] padIt = []
collectBoxesForTag(padded.root, 'i', padIt)
checkEqInt(padIt[0].x, 20, "the containing block's padding moves the static position across")
checkEqInt(padIt[0].y, 70, 'and down')

// An inset that is not `auto` is unaffected, so the two axes are
// decided separately.
Box sb6 = staticBox('<div style="height:50px"></div>'
    + '<div style="margin-left:60px">'
    + '<i style="position:absolute;display:block;width:30px;height:20px;top:5px"></i>'
    + '</div>')
checkEqInt(sb6.x, 60, 'a declared top leaves the static position across alone')
checkEqInt(sb6.y, 5, 'while down it is the inset that decides')

finish('position')
