// A named page may declare a sheet of its own size, and the content on it is
// laid out at that sheet's width (Paged Media 3 §3, named pages). Every
// number here is Chromium's, from `Page.printToPDF` with `preferCSSPageSize`
// on `tests/chromium.py`'s DevTools pipe: a document of three 100px blocks,
// the middle one on a named page whose sheet is 800px wide where the others
// are 400px, printed three pages whose media boxes are 300, 600 and 300
// points -- 400, 800 and 400 pixels -- and whose blocks, filled with a
// colour so the content stream shows their rectangle, are 360, 760 and 360
// wide: the sheet less 20px of margin each side, and not one width for all
// three.
import ../../src/browser/page.f
import ../assert.f

text SIZES = '@page { size: 400px 300px; margin: 20px } @page wide { size: 800px 300px; margin: 20px }'
    + ' body { margin: 0 } .a { height: 100px } .w { page: wide; height: 100px }'

void func printOf(css:text, body:text) {
    cssMediaPrint = true
    resetPageRules()
    Page p = pageFromHtml('<!doctype html><html><head><style>' + css
        + '</style></head><body>' + body + '</body></html>', 'test.html', 360)
    paginatePage(p)
    cssMediaPrint = false
}

Box func blockIn(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = blockIn(b.children[i], id)
        if f != null { return f }
    }
    return null
}

printOf(SIZES, '<div class="a" id="a1"></div><div class="w" id="w"></div><div class="a" id="a2"></div>')
checkEqInt(pageBoxes.length, 3, 'a named run on its own sheet makes three pages')
checkEqInt(pageBoxes[0].width, 400, 'the first sheet is 400 wide')
checkEqInt(pageBoxes[1].width, 800, 'the named page is 800')
checkEqInt(pageBoxes[2].width, 400, 'and the one after it is 400 again')
check(pageLayoutNo[0] != pageLayoutNo[1], 'each width has a layout of its own')
checkEqInt(pageLayoutNo[0], pageLayoutNo[2], 'and the widths that match share one')
checkEqInt(pageBoxes[1].height, 300, 'at the height it declared')
checkEqInt(blockIn(pageRoots[0], 'a1').w, 360, 'the first block is laid out at 360')
checkEqInt(blockIn(pageRoots[1], 'w').w, 760, 'the named page\'s block at 760, its sheet less its margins')
checkEqInt(blockIn(pageRoots[2], 'a2').w, 360, 'and the last at 360 again')

// What is on a page is the part of ITS layout the page begins at, so a page
// does not begin where another layout put the block.
checkEqInt(pageStartY[0], 0, 'page one begins at the top')
checkEqInt(pageStartY[1], blockIn(pageRoots[1], 'w').y, 'page two where its own layout put the block')
checkEqInt(pageStartY[2], blockIn(pageRoots[2], 'a2').y, 'and page three where its')

// Text wraps at the width of the sheet it is on: forty words that are
// 40x20 boxes are nineteen to a line at 760 -- three lines, 60px -- and nine
// to a line at 360 -- five lines, 100px.
text func sizeWords(n:int) {
    text out = ''
    for int i = 0, i < n, i++ {
        out = out + '<span style="display:inline-block;width:40px;height:20px;vertical-align:top"></span>'
    }
    return out
}
printOf(SIZES, `<div class="a" id="a1"></div><div class="w" id="w" style="height:auto">${sizeWords(40)}</div><div class="a" id="a2"></div>`)
checkEqInt(blockIn(pageRoots[1], 'w').h, 60, 'forty words on the wide sheet are three lines')
printOf(SIZES, `<div class="a" id="a1"></div><div class="a" id="w" style="height:auto">${sizeWords(40)}</div>`)
checkEqInt(pageBoxes.length, 1, 'with no named page there is one sheet')
checkEqInt(blockIn(pageRoots[0], 'w').h, 100, 'and the same words on the narrow sheet are five lines')

// Pages that are all one size need one layout and nothing else: the roots
// are the page's own.
printOf('@page { size: 400px 300px; margin: 20px } body { margin: 0 } .a { height: 100px }',
    '<div class="a" id="a1"></div><div class="a" id="a2" style="break-before:page"></div>')
checkEqInt(pageBoxes.length, 2, 'two pages of one size')
checkEqInt(blockIn(pageRoots[0], 'a1').w, 360, 'laid out at the sheet')
checkEqInt(pageLayoutNo[0], pageLayoutNo[1], 'in one layout')

// A named page of the same width as the rest needs no layout of its own.
printOf('@page { size: 400px 300px; margin: 20px } @page same { size: 400px 200px; margin: 20px }'
    + ' body { margin: 0 } .a { height: 100px } .s { page: same; height: 50px }',
    '<div class="a" id="a1"></div><div class="s" id="s"></div>')
checkEqInt(pageBoxes.length, 2, 'a named page of another height is a page')
checkEqInt(pageBoxes[1].height, 200, 'of its own height')
checkEqInt(pageLayoutNo[0], pageLayoutNo[1], 'and in the same layout')

finish('page sizes')
