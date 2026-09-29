// A list item and its marker (CSS Lists 3 §3, CSS2 §12.5). An outside marker
// looks for a baseline in the item's in-flow content -- a line box, or a
// table -- to sit on. Where there is none (an empty item, one holding only
// floats, out-of-flow boxes or empty blocks) the marker is laid out as a
// line of its own, and the item is at least as tall as that line. Every
// expectation is what Chromium answered for the same document: the
// rectangle of every ul, ol, li and div in document order, at 400px with no
// body margin and a 20px line height, because this engine's normal line
// height is 1.2 and Chromium's is about 1.16 (todo.md).
//
// The J fixtures are the margins of an item and its children, which
// collapse through an item as they do through any block.

import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../../src/browser/page.f
import ../assert.f

text func rects(body:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0">' + body, 'about:blank', 400)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'ul', all)
    collectBoxesForTag(p.root, 'ol', all)
    collectBoxesForTag(p.root, 'li', all)
    collectBoxesForTag(p.root, 'div', all)
    for int i = 1, i < all.length, i++ {
        Box k = all[i]
        int j = i - 1
        while j >= 0 && all[j].node.id > k.node.id { all[j + 1] = all[j]  j-- }
        all[j + 1] = k
    }
    text row = ''
    for int i = 0, i < all.length, i++ {
        Box b = all[i]
        row = row + ` (${b.x},${b.y} ${b.w}x${b.h})`
    }
    return row
}

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="float:left;width:50px;height:60px"></div></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 50x60)',
    'I1: float only')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px;list-style:none"><li><div style="float:left;width:50px;height:60px"></div></li></ul>'),
    ' (0,0 400x0) (40,0 360x0) (40,0 50x60)',
    'I2: float only, no marker')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px;list-style-position:inside"><li><div style="float:left;width:50px;height:60px"></div></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 50x60)',
    'I3: float only, inside marker')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li></li></ul>'),
    ' (0,0 400x20) (40,0 360x20)',
    'I4: empty item')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="height:30px"></div></li></ul>'),
    ' (0,0 400x30) (40,0 360x30) (40,0 360x30)',
    'I5: block of 30')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="height:0"></div></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 360x0)',
    'I6: empty block')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="height:10px"></div></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 360x10)',
    'I7: block of 10')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="height:10px"></div><div style="height:10px"></div></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 360x10) (40,10 360x10)',
    'I8: two blocks of 10')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="height:25px"></div></li></ul>'),
    ' (0,0 400x25) (40,0 360x25) (40,0 360x25)',
    'I9: block of 25')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="padding:5px 0"></li></ul>'),
    ' (0,0 400x30) (40,0 360x30)',
    'I10: padding only')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li>   </li></ul>'),
    ' (0,0 400x20) (40,0 360x20)',
    'I11: whitespace only')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><ul style="margin:0;padding:0 0 0 40px;line-height:20px"></ul></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 360x0)',
    'I12: nested empty list')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li></li></ul></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 360x20) (80,0 320x20)',
    'I13: nested list with an item')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="height:0"></li></ul>'),
    ' (0,0 400x0) (40,0 360x0)',
    'I14: height 0')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="height:5px"></li></ul>'),
    ' (0,0 400x5) (40,0 360x5)',
    'I15: height 5')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="min-height:5px"></li></ul>'),
    ' (0,0 400x20) (40,0 360x20)',
    'I16: min-height 5')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><br></li></ul>'),
    ' (0,0 400x20) (40,0 360x20)',
    'I17: br only')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li></li><li></li></ul>'),
    ' (0,0 400x40) (40,0 360x20) (40,20 360x20)',
    'I18: two empty items')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="position:absolute;width:50px;height:60px"></div></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 50x60)',
    'I19: absolute only')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="float:left;width:50px;height:60px"></div>x</li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 50x60)',
    'I20: float then text')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="float:left;width:50px;height:60px"></div><div style="height:30px"></div></li></ul>'),
    ' (0,0 400x30) (40,0 360x30) (40,0 50x60) (40,0 360x30)',
    'I21: float then block of 30')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="height:0"></div>x</li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 360x0)',
    'I22: empty block then text')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="float:left;width:50px">x</div></li></ul>'),
    ' (0,0 400x20) (40,0 360x20) (40,0 50x20)',
    'I23: text only inside a float')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><span></span></li></ul>'),
    ' (0,0 400x20) (40,0 360x20)',
    'I24: empty span')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="margin:10px 0;height:5px"></div></li></ul>'),
    ' (0,10 400x20) (40,10 360x20) (40,10 360x5)',
    'I25: block of 5 with margins')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="height:auto"></li></ul><style>li::marker{content:""}</style>'),
    ' (0,0 400x20) (40,0 360x20)',
    'I26: empty marker content')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px;list-style:none"><li></li></ul><style>li::marker{content:"x"}</style>'),
    ' (0,0 400x20) (40,0 360x20)',
    'I27: marker content on a none list')

checkEq(rects('<div style="display:list-item;margin-left:40px;line-height:20px"><div style="float:left;width:50px;height:60px"></div></div>'),
    ' (40,0 360x20) (40,0 50x60)',
    'I28: display list-item div')

checkEq(rects('<ol style="margin:0;padding:0 0 0 40px;line-height:20px"><li></li></ol>'),
    ' (0,0 400x20) (40,0 360x20)',
    'I29: ordered list')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="margin-top:5px"><div style="margin-top:10px;height:10px"></div></li></ul>'),
    ' (0,10 400x20) (40,10 360x20) (40,10 360x10)',
    'J1: margins of an item and its first child')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="margin-top:12px"><div style="margin-top:4px;height:10px"></div></li></ul>'),
    ' (0,12 400x20) (40,12 360x20) (40,12 360x10)',
    'J2: child margin beyond the item\'s')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="margin-bottom:12px"><div style="margin-bottom:4px;height:10px"></div></li><li><div style="height:10px"></div></li></ul>'),
    ' (0,0 400x52) (40,0 360x20) (40,0 360x10) (40,32 360x20) (40,32 360x10)',
    'J3: bottom margins of an item and its last child')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="margin-bottom:8px;height:10px"></div></li><li><div style="height:10px"></div></li></ul>'),
    ' (0,0 400x48) (40,0 360x20) (40,0 360x10) (40,28 360x20) (40,28 360x10)',
    'J4: bottom margin of a last child alone')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li><div style="margin:6px 0;height:10px"></div><div style="margin:6px 0;height:10px"></div></li></ul>'),
    ' (0,6 400x26) (40,6 360x26) (40,6 360x10) (40,22 360x10)',
    'J5: a nested list with margins')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li style="padding-top:3px"><div style="margin-top:10px;height:10px"></div></li></ul>'),
    ' (0,0 400x23) (40,0 360x23) (40,13 360x10)',
    'J6: padded item keeps its child\'s margin')

checkEq(rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li>x<div style="margin-top:10px;height:10px"></div></li><li>y</li></ul>'),
    ' (0,0 400x60) (40,0 360x40) (40,30 360x10) (40,40 360x20)',
    'J7: text then margin block')

// The instrument: the growth is the marker's, so the same item without a
// marker must not have it, and an item with content of its own must not
// gain it twice.
text withMarker = rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px"><li></li></ul>')
text noMarker = rects('<ul style="margin:0;padding:0 0 0 40px;line-height:20px;list-style:none"><li></li></ul>')
check(withMarker != noMarker, 'an empty item with a marker and one without differ')

finish('list items')
