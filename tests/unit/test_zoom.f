// `zoom` (CSS Viewport 1 §4, and the oldest non-standard property in
// CSS to have been standardised).
//
// Every length zooms exactly ONCE. A declared `100px` is 200 device
// pixels at zoom 2, and so are the paddings, borders, margins and the
// height. `em`, `rem` and `vw` resolve against the unzoomed font size,
// root font size and viewport and then zoom. A PERCENTAGE needs
// nothing, because the containing block is already in device pixels.
// An `auto` width still fills its containing block, so a zoomed box
// with no declared width is the same width and a different height.
//
// `zoom` compounds down the tree, and zero and a negative compute to
// `1`. Every number below is Chromium 141's, in todo.md.
import ../../src/browser/page.f
import ../assert.f

Box func zoomById(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'div', all)
    for int i = 0, i < all.length, i++ {
        if all[i].node != null && getAttr(all[i].node, 'id') == id { return all[i] }
    }
    return null
}

text zhead = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:400px">'

// A block in a containing block 400 wide at 16px/20px, holding ten
// `M`s so an unzoomed line of it is 20 tall.
Box func zoomed(decls:text) {
    Page p = pageFromHtml(zhead
        + '<div id="cb" style="width:400px;height:200px">'
        + '<div id="t" style="' + decls + '">MMMMMMMMMM</div>'
        + '</div></body>', 'about:blank', 400)
    return zoomById(p.root, 't')
}

int func zoomW(decls:text) { Box b = zoomed(decls)  return b == null ? -1 : b.w }
int func zoomH(decls:text) { Box b = zoomed(decls)  return b == null ? -1 : b.h }
int func zoomX(decls:text) { Box b = zoomed(decls)  return b == null ? -1 : b.x }

// ---- an auto width fills, and only the height changes ---------------
checkEqInt(zoomW(''), 400, 'an auto width fills the containing block')
checkEqInt(zoomH(''), 20, 'and one line is one line high')
checkEqInt(zoomW('zoom:2'), 400, 'a zoomed auto width still fills it')
checkEqInt(zoomH('zoom:2'), 40, 'and its line is twice as tall')
checkEqInt(zoomW('zoom:0.5'), 400, 'and at a half it still fills it')
checkEqInt(zoomH('zoom:0.5'), 10, 'with a line half as tall')

// ---- every declared length zooms once -------------------------------
checkEqInt(zoomW('zoom:2;width:100px'), 200, 'a declared width doubles')
checkEqInt(zoomH('zoom:2;height:50px'), 100, 'and a declared height')
checkEqInt(zoomW('zoom:2;width:100px;padding:10px'), 240, 'the paddings zoom with it')
checkEqInt(zoomW('zoom:2;width:100px;border:4px solid'), 216, 'and the borders')
checkEqInt(zoomX('zoom:2;width:100px;margin-left:10px'), 20, 'and a margin moves it twice as far')

// ---- the relative units resolve unzoomed, then zoom ------------------
checkEqInt(zoomW('zoom:2;width:10em'), 320, 'an em is the unzoomed font size, then zoomed')
checkEqInt(zoomW('zoom:2;font-size:10px;width:10em'), 200, 'against the element\'s own size')
checkEqInt(zoomW('zoom:2;width:10rem'), 320, 'and a rem the unzoomed root size')

// ---- a percentage needs nothing --------------------------------------
checkEqInt(zoomW('zoom:2;width:50%'), 200,
           'a percentage of a containing block already in device pixels')

// ---- `normal`, and the invalid values --------------------------------
checkEqInt(zoomW('zoom:normal;width:100px'), 100, '`normal` is no zoom at all')
checkEqInt(zoomW('zoom:0;width:100px'), 100, 'zero is invalid and computes to one')
checkEqInt(zoomW('zoom:-1;width:100px'), 100, 'and so is a negative')
checkEqInt(zoomW('zoom:banana;width:100px'), 100, 'and anything that is not a number')

// ---- it compounds down the tree --------------------------------------
int func zoomKidW(parentDecls:text, kidDecls:text) {
    Page p = pageFromHtml(zhead
        + '<div id="cb" style="width:400px;height:200px">'
        + '<div id="t" style="' + parentDecls + '">'
        + '<div id="k" style="' + kidDecls + '">x</div></div>'
        + '</div></body>', 'about:blank', 400)
    Box k = zoomById(p.root, 'k')
    return k == null ? -1 : k.w
}

checkEqInt(zoomKidW('zoom:2;width:100px', 'zoom:2;width:50px'), 200,
           'two zooms of two are a zoom of four')
checkEqInt(zoomKidW('zoom:2;width:100px', 'zoom:0.5;width:50px'), 50,
           'and a half under a two is no zoom at all')
checkEqInt(zoomKidW('zoom:2;width:100px', 'width:50%'), 100,
           'a percentage inside a zoomed box is already in device pixels')

// ---- the checks that need no number of their own ---------------------
// A zoom of two on a declared length is the same box as twice the
// length unzoomed. That holds for every length at once, which is what
// makes it worth more than any single row above.
checkEqInt(zoomW('zoom:2;width:100px;padding:10px;border:4px solid'),
           zoomW('width:200px;padding:20px;border:8px solid'),
           'zoom two of a box is the box with every length doubled')
checkEqInt(zoomH('zoom:2;height:50px'), zoomH('height:100px'),
           'down the block axis as well')
checkEqInt(zoomX('zoom:2;width:100px;margin-left:10px'),
           zoomX('width:200px;margin-left:20px'),
           'and where it sits')
// And a zoom of one changes nothing at all, whatever is declared.
checkEqInt(zoomW('zoom:1;width:100px;padding:7px'), zoomW('width:100px;padding:7px'),
           'a zoom of one is no zoom')

// ---- and the text zooms with it --------------------------------------
//
// Every check above is a declared length or a line height. A box that
// shrinks to fit is what puts the FONT on the scale: Chromium's ten
// `M`s are 96.33 wide unzoomed, 192.66 at zoom 2 and 48.17 at a half,
// while `getComputedStyle().width` stays 96.33 throughout.
int func zoomFitW(decls:text) {
    Page p = pageFromHtml(zhead
        + '<div id="cb" style="width:400px">'
        + '<div id="t" style="display:inline-block;' + decls + '">MMMMMMMMMM</div>'
        + '</div></body>', 'about:blank', 400)
    Box b = zoomById(p.root, 't')
    return b == null ? -1 : b.w
}

// 100 rather than Chromium's 96.33 because this engine rounds a
// glyph's advance to whole pixels before multiplying -- ten advances
// of 10 against ten of 9.633 -- which is older than `zoom` and has
// nothing to do with it. What matters here is that the number moves
// with the zoom, which the three checks below ask without it.
checkEqInt(zoomFitW(''), 100, 'ten monospace Ms at 16px')
// The check that earns its place, and it is exact: a zoom of two is
// the same ink as twice the font size. Twice the WIDTH is not, and
// cannot be -- this engine rounds a glyph's advance to whole pixels,
// so ten of them at 16px come to 100 and ten at 32px to 190, where
// Chromium's 96.33 and 192.66 are exactly double. That is the
// rounding the check above names, and asserting `2 *` here would be
// asserting the font's arithmetic rather than the property's.
checkEqInt(zoomFitW('zoom:2'), zoomFitW('font-size:32px'),
           'a zoom of two is the same ink as twice the font size')
checkEqInt(zoomFitW('zoom:0.5'), zoomFitW('font-size:8px'),
           'and a half is half the font size')
checkEqInt(zoomFitW('zoom:2'), 190, 'which is 190 here, against Chromium\'s 192.66')
check(zoomFitW('zoom:2') > zoomFitW(''), 'and it is wider than no zoom at all')
check(zoomFitW('zoom:0.5') < zoomFitW(''), 'and a half is narrower')

// The font size the text is set in zooms, and the one the cascade
// computes does not -- so a zoom of two and a font size of eight is
// the same ink as no zoom and a font size of sixteen.
checkEqInt(zoomFitW('zoom:2;font-size:8px'), zoomFitW('font-size:16px'),
           'a zoom of two on 8px text is 16px text')

finish('zoom')
