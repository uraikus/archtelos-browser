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

// ---- an item whose first baseline is a table's ---------------------------
// A table has a baseline -- its first row's, which is the bottom of the cell's
// content edge when the cell holds no line of text -- and an outside marker
// sits on it. The marker's own line is 15px above its baseline at a 20px line
// height and a 16px font, so a table whose baseline is nearer its top than
// that is pushed down until it is level with the marker, and the item grows by
// the push: `<li><table><td style="height:10px">` is 15px tall with the table
// at y=5, where the table's own height would make it 10 with the table at 0.
// A baseline lower than the marker's pushes nothing. Every number is
// Chromium's, with the item's `li` and the table's rectangle, at 800px.

text func liTableOf(listCss:text, inner:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0">'
        + `<ul style="margin:0;padding:0 0 0 40px;line-height:20px${listCss}">${inner}</ul>`, 'about:blank', 800)
    arr[Box] items = []
    collectBoxesForTag(p.root, 'li', items)
    arr[Box] tables = []
    collectBoxesForTag(p.root, 'table', tables)
    Box li = items[0]
    Box t = tables.length > 0 ? tables[0] : null
    return t == null ? `li ${li.y}+${li.h}` : `li ${li.y}+${li.h} table ${t.y - li.y}+${t.h}`
}

text func liCell(h:int, pad:text) {
    return `<table style="border-spacing:0"><tr><td style="padding:${pad};height:${h}px"></td></tr></table>`
}

checkEq(liTableOf('', '<li>' + liCell(10, '0') + '</li>'), 'li 0+15 table 5+10',
    'K1: an empty cell 10 tall has its baseline 10 down, 5 short of the marker')
checkEq(liTableOf('', '<li>' + liCell(30, '0') + '</li>'), 'li 0+30 table 0+30',
    'K2: one 30 tall has it below the marker, and nothing is pushed')
checkEq(liTableOf('', '<li>' + liCell(5, '0') + '</li>'), 'li 0+15 table 10+5',
    'K3: one 5 tall is pushed down 10')
checkEq(liTableOf('', '<li><table style="border-spacing:0"><tr><td style="padding:0;height:10px">x</td></tr></table></li>'),
    'li 0+20 table 0+20',
    'K4: a cell with a line of text has that line\'s baseline, level with the marker already')
checkEq(liTableOf('', '<li><table style="border-spacing:0"><tr><td style="padding:0;height:10px"></td></tr>'
    + '<tr><td style="padding:0;height:10px"></td></tr></table></li>'), 'li 0+25 table 5+20',
    'K5: the first row\'s baseline, not the last')
checkEq(liTableOf('', '<li><table style="border-spacing:0"><tr><td style="padding:0;height:10px;vertical-align:top"></td></tr></table></li>'),
    'li 0+15 table 5+10',
    'K6: vertical-align on the cell does not move the baseline')
checkEq(liTableOf('', '<li>' + liCell(10, '3px') + '</li>'), 'li 0+18 table 2+16',
    'K7: the cell\'s padding is inside its content edge, so the baseline is 13 down')
checkEq(liTableOf('', '<li>a' + liCell(10, '0') + '</li>'), 'li 0+30 table 20+10',
    'K8: a line before the table is the baseline, and the table is below it')
checkEq(liTableOf('', '<li><div>' + liCell(10, '0') + '</div></li>'), 'li 0+15 table 5+10',
    'K9: the table is found through a block around it')
checkEq(liTableOf(';list-style:none', '<li>' + liCell(10, '0') + '</li>'), 'li 0+10 table 0+10',
    'K10: with no marker nothing is seated')
checkEq(liTableOf(';font-size:30px;line-height:40px', '<li>' + liCell(10, '0') + '</li>'), 'li 0+30 table 20+10',
    'K11: the marker\'s ascent follows its own font and line height, 30 here')

// The marker itself is drawn on the table's baseline, not above it.
Page kp = pageFromHtml('<!doctype html><body style="margin:0">'
    + '<ul style="margin:0;padding:0 0 0 40px;line-height:20px;list-style-type:square;color:red"><li>'
    + '<table style="border-spacing:0"><tr><td style="padding:0;height:10px"></td></tr></table></li></ul>',
    'about:blank', 200)
arr[Box] kitems = []
collectBoxesForTag(kp.root, 'li', kitems)
checkEqInt(listMarkerBaselineY(kitems[0]) - kitems[0].y, 15, 'K12: the marker\'s baseline is 15 down, where the table\'s now is')

// ---- an inside marker followed by a block ----------------------------------
// The marker is an inline box, and a block after it cannot share its line, so
// it makes a line box of its own -- the item is that line plus the block.
// (An item whose first content is text is the ordinary case, and is already
// right.) Chromium's: `<li><div style="height:10px">` inside is 30 tall with
// the div at y=20.

checkEq(liTableOf(';list-style-position:inside', '<li>' + liCell(10, '0') + '</li>'), 'li 0+30 table 20+10',
    'L1: inside, then a table')
text func liDivOf(listCss:text, inner:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0">'
        + `<ul style="margin:0;padding:0 0 0 40px;line-height:20px${listCss}">${inner}</ul>`, 'about:blank', 800)
    arr[Box] items = []
    collectBoxesForTag(p.root, 'li', items)
    arr[Box] divs = []
    collectBoxesForTag(p.root, 'div', divs)
    Box li = items[0]
    return divs.length == 0 ? `li ${li.y}+${li.h}` : `li ${li.y}+${li.h} div ${divs[0].y - li.y}+${divs[0].h}`
}
checkEq(liDivOf(';list-style-position:inside', '<li><div style="height:10px"></div></li>'), 'li 0+30 div 20+10',
    'L2: inside, then a block of 10')
checkEq(liDivOf(';list-style-position:inside', '<li><div>x</div></li>'), 'li 0+40 div 20+20',
    'L3: inside, then a block holding a line')
checkEq(liDivOf(';list-style-position:inside', '<li>x<div style="height:10px"></div></li>'), 'li 0+30 div 20+10',
    'L4: inside, text, then a block: the marker shares the text\'s line')
checkEq(liDivOf(';list-style-position:inside', '<li>x</li>'), 'li 0+20', 'L5: inside, text only')
checkEq(liDivOf(';list-style-position:inside', '<li></li>'), 'li 0+20', 'L6: inside and empty')
checkEq(liDivOf(';list-style-position:inside', '<li><div><div>x</div></div></li>'), 'li 0+40 div 20+20',
    'L7: inside, then blocks nested')
checkEq(liDivOf(';list-style-position:inside;list-style-type:none', '<li><div style="height:10px"></div></li>'), 'li 0+10 div 0+10',
    'L8: no marker, no line of its own')

finish('list items')
