// Block formatting contexts (CSS2 9.4.1): a float belongs to one and cannot
// leave it, and a box that establishes one neither contains a float nor is
// contained by another's. Every expectation below is what Chromium answered
// for the same document -- the rectangle of every div, in document order,
// at 400px with no body margin -- from the fixtures todo.md keeps.

import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../../src/browser/page.f
import ../assert.f

text func rects(body:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0">' + body, 'about:blank', 400)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    text row = ''
    for int i = 0, i < all.length, i++ {
        Box b = all[i]
        row = row + ` (${b.x},${b.y} ${b.w}x${b.h})`
    }
    return row
}

checkEq(rects('<div style="overflow:hidden"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 400x50) (0,0 100x50) (0,50 400x10)',
    'F1: overflow:hidden contains a float')

checkEq(rects('<div><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 400x0) (0,0 100x50) (0,0 400x10)',
    'F2: plain div does not')

checkEq(rects('<div style="display:flow-root"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 400x50) (0,0 100x50) (0,50 400x10)',
    'F3: flow-root contains a float')

checkEq(rects('<div style="display:inline-block"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 100x50) (0,0 100x50) (0,54 400x10)',
    'F4: inline-block contains a float')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div style="overflow:hidden"><div style="float:left;width:50px;height:20px"></div></div>'),
    ' (0,0 100x100) (100,0 300x20) (100,0 50x20)',
    'F5: BFC beside an outer float')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div style="overflow:hidden"><div style="clear:left;height:10px"></div></div>'),
    ' (0,0 100x100) (100,0 300x10) (100,0 300x10)',
    'F6: clear inside a BFC ignores outer floats')

checkEq(rects('<table style="border-collapse:collapse"><tr><td style="padding:0"><div style="float:left;width:100px;height:50px"></div></td></tr></table><div style="height:10px"></div>'),
    ' (0,0 100x50) (0,50 400x10)',
    'F7: table cell contains a float')

checkEq(rects('<div style="overflow:hidden"><div><div style="float:left;width:100px;height:50px"></div></div></div><div style="height:10px"></div>'),
    ' (0,0 400x50) (0,0 400x0) (0,0 100x50) (0,50 400x10)',
    'F8: float inside nested block in a BFC')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div><div style="height:10px;width:300px"></div></div>'),
    ' (0,0 100x100) (0,0 400x10) (0,0 300x10)',
    'F9: an outer float leaks into a plain sibling')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div><div style="clear:left;height:10px"></div></div>'),
    ' (0,0 100x100) (0,0 400x110) (0,100 400x10)',
    'F10: clear in a plain div does clear')

checkEq(rects('<div style="overflow:auto"><div style="float:right;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 400x50) (300,0 100x50) (0,50 400x10)',
    'F11: float in overflow:auto')

checkEq(rects('<div style="float:right;width:100px;height:100px"></div><div style="overflow:hidden;height:30px"></div>'),
    ' (300,0 100x100) (0,0 300x30)',
    'F12: BFC beside a right float')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div style="overflow:hidden;margin-left:20px;height:30px"></div>'),
    ' (0,0 100x100) (100,0 300x30)',
    'F13: BFC margin-left smaller than the float')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div style="overflow:hidden;margin-left:150px;height:30px"></div>'),
    ' (0,0 100x100) (150,0 250x30)',
    'F14: BFC margin-left larger than the float')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div style="overflow:hidden;width:200px;height:30px"></div>'),
    ' (0,0 100x100) (100,0 200x30)',
    'F15: explicit width that fits beside')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div style="overflow:hidden;width:350px;height:30px"></div><div style="height:10px"></div>'),
    ' (0,0 100x100) (0,100 350x30) (0,130 400x10)',
    'F16: explicit width that does not fit')

checkEq(rects('<div style="float:left;width:200px"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px;clear:left"></div>'),
    ' (0,0 200x50) (0,0 100x50) (0,50 400x10)',
    'F17: a float contains its own floats')

checkEq(rects('<div style="position:absolute;width:200px"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 200x50) (0,0 100x50) (0,0 400x10)',
    'F18: abs-pos box contains a float')

checkEq(rects('<div style="float:left;width:100px;height:100px"></div><div style="overflow:hidden;height:30px"></div><div style="overflow:hidden;height:30px"></div>'),
    ' (0,0 100x100) (100,0 300x30) (100,30 300x30)',
    'F19: two BFCs beside one float')

checkEq(rects('<div style="float:left;width:100px;height:20px"></div><div style="overflow:hidden;height:30px"></div><div style="overflow:hidden;height:30px"></div>'),
    ' (0,0 100x20) (100,0 300x30) (0,30 400x30)',
    'F20: BFC taller than the float')

checkEq(rects('<div style="overflow:hidden"><div style="float:left;width:100px;height:50px;margin:10px 0 15px"></div></div><div style="height:10px"></div>'),
    ' (0,0 400x75) (0,10 100x50) (0,75 400x10)',
    'F21: float margins count')

checkEq(rects('<div style="overflow:hidden;height:20px"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 400x20) (0,0 100x50) (0,20 400x10)',
    'F22: BFC with a fixed height clips nothing')

checkEq(rects('<div style="overflow:hidden;min-height:80px"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 400x80) (0,0 100x50) (0,80 400x10)',
    'F23: min-height wins over floats when larger')

checkEq(rects('<div style="overflow:hidden;padding:5px;border:2px solid"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>'),
    ' (0,0 400x64) (7,7 100x50) (0,64 400x10)',
    'F24: padding and border around contained floats')

checkEq(rects('<div style="display:grid"><div><div style="float:left;width:100px;height:50px"></div></div></div><div style="height:10px"></div>'),
    ' (0,0 400x50) (0,0 400x50) (0,0 100x50) (0,50 400x10)',
    'F25: grid item contains a float')

checkEq(rects('<div style="display:flex"><div><div style="float:left;width:100px;height:50px"></div></div></div><div style="height:10px"></div>'),
    ' (0,0 400x50) (0,0 100x50) (0,0 100x50) (0,50 400x10)',
    'F26: flex item contains a float')

// The instrument: three ways of establishing a block formatting context
// must give the same rectangles, and a plain block, which establishes
// none, must not. Every check above would hold on an engine that contained
// floats in every block, or in none, only if the fixtures were the wrong
// ones; these say the two are different things.
text hidden = rects('<div style="overflow:hidden"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>')
text flowRoot = rects('<div style="display:flow-root"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>')
text auto = rects('<div style="overflow:auto"><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>')
text plain = rects('<div><div style="float:left;width:100px;height:50px"></div></div><div style="height:10px"></div>')
checkEq(hidden, flowRoot, 'overflow:hidden and flow-root establish the same context')
checkEq(hidden, auto, 'and so does overflow:auto')
check(hidden != plain, 'while a plain block establishes none, and the two differ')

finish('block formatting contexts')
