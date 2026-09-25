// CSS Writing Modes 4: a vertical `writing-mode`.
//
// The geometry Chromium gives is in todo.md, "A vertical writing mode,
// measured". Its shape is that a vertical block is the horizontal
// layout turned ninety degrees clockwise -- the same inline lengths,
// the same line thicknesses, the two axes exchanged. So the checks here
// are written the way CLAUDE.md asks of two things that must agree: the
// same content is laid out in both modes and the boxes must come out
// transposed. A check against a number this engine's own metrics
// produce would pass just as well if both modes were broken the same
// way, and would have to be rewritten the next time a font metric
// moves.
import ../../src/browser/page.f
import ../assert.f

text CONTENT = '<div class=k>one</div><div class=k>two</div>'
// The same two children with different block sizes, so that a wrong
// block direction cannot land on the right answer by symmetry.
text SIZED = '<div class=k style="width:40px">one</div><div class=k style="width:25px">two</div>'

Box func containerOf(style:text, outer:text, content:text) {
    Page p = pageFromHtml(
        `<!doctype html><html><head><style>body{margin:0;font-size:16px}` +
        `.o{width:400px;${outer}}.k{margin:0}</style></head><body>` +
        `<div class="o"><div id="v" style="${style}">${content}</div></div>` +
        `</body></html>`, 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    return all[1]
}

arr[Box] func kidsOf(style:text, outer:text) {
    Page p = pageFromHtml(
        `<!doctype html><html><head><style>body{margin:0;font-size:16px}` +
        `.o{width:400px;${outer}}.k{margin:0}</style></head><body>` +
        `<div class="o"><div id="v" style="${style}">${SIZED}</div></div>` +
        `</body></html>`, 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    arr[Box] out = []
    out.push(all[1])
    out.push(all[2])
    out.push(all[3])
    return out
}

// ---- the two axes are exchanged ---------------------------------------
// A horizontal container of this content is as tall as its two lines and
// as wide as it is allowed to be; the vertical one must be as wide as
// those same two lines are tall. Neither number is written down here.
Box hb = containerOf('writing-mode: horizontal-tb', 'height:200px', CONTENT)
Box vrl = containerOf('writing-mode: vertical-rl', 'height:200px', CONTENT)
checkEqInt(vrl.w, hb.h, 'a vertical container is as wide as the horizontal one is tall')

// The inline extent is the content's max-content size, which is what a
// shrink-to-fit horizontal box measures. Asking the same question twice.
Box shrink = containerOf('display: inline-block', 'height:200px', CONTENT)
checkEqInt(vrl.h, shrink.w, 'and is as tall as the content is wide')

// ---- the block axis runs right to left --------------------------------
// The two children are given different block sizes on purpose. With
// equal ones every arrangement puts them at the same coordinate and the
// checks would pass whatever the engine did.
arr[Box] kv = kidsOf('writing-mode: vertical-rl', 'height:200px')
checkEqInt(kv[1].w, 40, 'the first child takes the block size it asked for')
checkEqInt(kv[1].x + kv[1].w, kv[0].x + kv[0].w, 'and sits against the right edge')
checkEqInt(kv[2].x + kv[2].w, kv[1].x, 'the second ends where the first begins')
checkEqInt(kv[2].x, kv[0].x, 'and reaches the far edge')
checkEqInt(kv[1].y, kv[2].y, 'both start at the same inline position')

// vertical-lr stacks them the other way.
arr[Box] kl = kidsOf('writing-mode: vertical-lr', 'height:200px')
checkEqInt(kl[1].x, kl[0].x, 'in vertical-lr the first block is at the left edge')
checkEqInt(kl[2].x, kl[1].x + kl[1].w, 'and the second begins where it ends')

// ---- width and height stay physical -----------------------------------
Page pw = pageFromHtml(
    '<!doctype html><html><head><style>body{margin:0;font-size:16px}' +
    '.o{width:400px;height:200px}</style></head><body><div class="o">' +
    '<div style="writing-mode: vertical-rl">' +
    '<div id="a" style="width:60px;height:30px;margin:0">x</div></div>' +
    '</div></body></html>', 'about:blank', 800)
arr[Box] pwd = []
collectBoxesForTag(pw.root, 'div', pwd)
checkEqInt(pwd[2].w, 60, 'width is the horizontal extent in a vertical mode too')
checkEqInt(pwd[2].h, 30, 'and height the vertical one')

// ---- the logical properties follow the mode ---------------------------
// inline-size is the height and block-size the width, which is the same
// table the horizontal mode uses with the axes exchanged. Each is
// checked against its physical twin in the other mode rather than
// against a number.
Box vIn = containerOf('writing-mode: vertical-rl; inline-size: 120px', 'height:300px', CONTENT)
checkEqInt(vIn.h, 120, 'inline-size is the height in a vertical mode')
Box vBl = containerOf('writing-mode: vertical-rl; block-size: 120px', 'height:300px', CONTENT)
checkEqInt(vBl.w, 120, 'and block-size is the width')
Box hIn = containerOf('writing-mode: horizontal-tb; inline-size: 120px', 'height:300px', CONTENT)
checkEqInt(hIn.w, 120, 'where in a horizontal mode inline-size is the width')

// margin-inline-start is the top margin in vertical-rl, so it eats into
// the inline extent the same way margin-left does horizontally. The
// content is long enough for the containing block's clamp to bind,
// which is what makes the margin visible in the box's size at all: with
// a short line the box shrinks to fit and a margin changes nothing.
text LONG = 'ab cd ef gh ij kl mn op qr st uv wx yz ab cd ef gh ij kl mn op'
Box vNoM = containerOf('writing-mode: vertical-rl', 'height:150px', LONG)
Box vM = containerOf('writing-mode: vertical-rl; margin-inline-start: 20px', 'height:150px', LONG)
checkEqInt(vNoM.h, 150, 'a clamped orthogonal flow fills the block size it is given')
checkEqInt(vM.y, 20, 'and margin-inline-start puts its top edge that far down')
checkEqInt(vM.h, vNoM.h - 20, 'taking exactly that much out of the inline extent')

// ---- an orthogonal flow shrinks to fit, clamped -----------------------
// A long line wants more inline size than the containing block's block
// size allows, and is clamped to it; a short one is not.
Page plong = pageFromHtml(
    '<!doctype html><html><head><style>body{margin:0;font-size:16px}' +
    '.o{width:400px;height:150px}</style></head><body><div class="o">' +
    '<div id="v" style="writing-mode: vertical-rl">' +
    'ab cd ef gh ij kl mn op qr st uv wx yz ab cd ef gh ij kl mn op' +
    '</div></div></body></html>', 'about:blank', 800)
arr[Box] pl = []
collectBoxesForTag(plong.root, 'div', pl)
checkEqInt(pl[1].h, 150, 'an orthogonal flow is clamped to the containing block it is in')

// How many lines that clamp implies is not a number to be guessed: it
// is the same text's max-content width divided by the clamp, and the
// block extent is that many line thicknesses. Both terms are measured
// from the horizontal mode on the same text.
Page pwide = pageFromHtml(
    '<!doctype html><html><head><style>body{margin:0;font-size:16px}' +
    '.o{width:400px;height:150px}</style></head><body><div class="o">' +
    '<div id="v" style="display:inline-block;white-space:nowrap">' +
    'ab cd ef gh ij kl mn op qr st uv wx yz ab cd ef gh ij kl mn op' +
    '</div></div></body></html>', 'about:blank', 800)
arr[Box] pw2 = []
collectBoxesForTag(pwide.root, 'div', pw2)
int oneLine = Math.floorDiv(hb.h, 2)
int wanted = Math.floorDiv(pw2[1].w + 149, 150)
check(wanted >= 4, 'the long line really does need several columns')
checkEqInt(pl[1].w, wanted * oneLine, 'and the block extent is that many line thicknesses')

// ---- text-orientation -------------------------------------------------
// `upright` gives each character its own cell along the inline axis
// (Writing Modes 4 §5.1). Chromium's cell is measured in todo.md; what
// is asked here is the RULE rather than the number -- that n characters
// take n times what one takes, that a space takes one too, and that
// `sideways` and `mixed` agree on Latin, which they do in Chromium.
int func uprightExtent(orient:text, content:text) {
    Page p = pageFromHtml(
        `<!doctype html><html><head><style>body{margin:0;font-size:16px}` +
        `.o{width:400px}</style></head><body><div class="o">` +
        `<div id="v" style="writing-mode:vertical-rl;text-orientation:${orient}">` +
        `${content}</div></div></body></html>`, 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    return all[1].h
}

// The instrument first: on an engine that ignores the property every
// check below would hold, because all three keywords would measure the
// same run the same way.
int oneUp = uprightExtent('upright', 'A')
int oneMixed = uprightExtent('mixed', 'A')
check(oneUp != oneMixed, 'upright measures a single character differently from mixed')

checkEqInt(uprightExtent('upright', 'ABC'), 3 * oneUp, 'three upright characters take three cells')
checkEqInt(uprightExtent('upright', 'ill'), 3 * oneUp, 'and the cell does not depend on the character')
checkEqInt(uprightExtent('upright', 'A B'), 3 * oneUp, 'a space takes a cell of its own')
checkEqInt(uprightExtent('sideways', 'ABC'), uprightExtent('mixed', 'ABC'),
    'sideways and mixed agree on Latin, as they do in Chromium')

// The cell does not follow line-height, which is what told it apart
// from the line box in the first place.
int func uprightWithLineHeight(lh:text) {
    Page p = pageFromHtml(
        `<!doctype html><html><head><style>body{margin:0;font-size:16px}` +
        `.o{width:400px}</style></head><body><div class="o">` +
        `<div id="v" style="writing-mode:vertical-rl;text-orientation:upright;` +
        `line-height:${lh}">ABC</div></div></body></html>`, 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    return all[1].h
}
checkEqInt(uprightWithLineHeight('2'), uprightWithLineHeight('normal'),
    'the cell does not follow line-height')

// ---- the two sideways modes -------------------------------------------
// No box moves: the block axis is the same in all four vertical modes,
// which is what Chromium says (todo.md) and is the whole of what a unit
// test can see -- the difference between them is the glyph's turn and
// the direction the run advances, and the render suite asks that.
arr[Box] func kidsOfMode(mode:text) {
    return kidsOf(`writing-mode: ${mode}`, 'height:200px')
}

arr[Box] krl = kidsOfMode('vertical-rl')
arr[Box] ksr = kidsOfMode('sideways-rl')
checkEqInt(ksr[0].w, krl[0].w, 'sideways-rl gives the container the same block extent')
checkEqInt(ksr[1].x - ksr[0].x, krl[1].x - krl[0].x, 'and puts the first child where vertical-rl does')
checkEqInt(ksr[2].x - ksr[0].x, krl[2].x - krl[0].x, 'and the second')

arr[Box] klr = kidsOfMode('vertical-lr')
arr[Box] ksl = kidsOfMode('sideways-lr')
checkEqInt(ksl[0].w, klr[0].w, 'sideways-lr gives the container the same block extent')
checkEqInt(ksl[1].x - ksl[0].x, klr[1].x - klr[0].x, 'and puts the first child where vertical-lr does')
checkEqInt(ksl[2].x - ksl[0].x, klr[2].x - klr[0].x, 'and the second')

// The instrument: the two pairs must not be the same pair, or every
// check above would hold on an engine that treated all four alike.
check(krl[1].x != klr[1].x, 'the rl modes and the lr modes really do differ')

// ---- an indefinite containing block clamps to the viewport ------------
// Chromium's table is in todo.md: the inline size of an orthogonal flow
// whose containing block has no definite block size is the viewport's
// height, at every height measured. The check sets two different
// viewports and asks for the number back, so it cannot be satisfied by
// a constant.
text WMLONG = 'ab cd ef gh ij kl mn op qr st uv wx yz ' +
              'ab cd ef gh ij kl mn op qr st uv wx yz ' +
              'ab cd ef gh ij kl mn op qr st uv wx yz ' +
              'ab cd ef gh ij kl mn op qr st uv wx yz '

int func wmUnboundedExtent(vh:int) {
    setCssViewport(800, vh)
    Page p = pageFromHtml(
        `<!doctype html><html><head><style>body{margin:0;font-size:16px}` +
        `</style></head><body><div style="width:400px">` +
        `<div id="v" style="writing-mode:vertical-rl">${WMLONG}</div>` +
        `</div></body></html>`, 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    return all[1].h
}

int at250 = wmUnboundedExtent(250)
int at500 = wmUnboundedExtent(500)
setCssViewport(800, 600)
checkEqInt(at250, 250, 'an indefinite containing block clamps to the viewport')
checkEqInt(at500, 500, 'and follows it when it changes')

// ---- the other formatting contexts -------------------------------------
// Chromium's table is in todo.md, "The other formatting contexts,
// measured": every vertical rectangle is the horizontal one turned a
// quarter turn. The fixture below sizes the container and its items with
// the *logical* properties, so the logical layout is identical in all
// three modes and every difference in the physical result is the turn
// and nothing else. That is the agreement CLAUDE.md asks two things to
// be tested against, rather than this engine's own numbers written down:
// a flex algorithm reading `width` where it means the inline size fails
// it, and so does one that reads the right length and stacks the wrong
// way.
//
// Each fixture is chosen so that its two items differ on both axes.
// Where they do not -- a table whose cells fill the whole block extent,
// a grid whose items share a row -- `vertical-rl` and `vertical-lr`
// come out identical and the checks would pass on an engine that could
// not tell one from the other.

arr[Box] func fcBoxes(mode:text, style:text, inner:text) {
    Page p = pageFromHtml(
        `<!doctype html><html><head><style>body{margin:0;font-size:16px}` +
        `.o{width:400px;height:200px}.z{margin:0}</style></head><body>` +
        `<div class="o"><div id="v" style="writing-mode:${mode};${style}">` +
        `${inner}</div></div>` +
        `</body></html>`, 'about:blank', 800)
    arr[Box] divs = []
    collectBoxesForTag(p.root, 'div', divs)
    arr[Box] out = []
    out.push(divs[1])
    collectBoxesForTag(p.root, 'p', out)
    return out
}

void func fcCheck(label:text, style:text, inner:text) {
    arr[Box] h = fcBoxes('horizontal-tb', style, inner)
    arr[Box] r = fcBoxes('vertical-rl', style, inner)
    arr[Box] l = fcBoxes('vertical-lr', style, inner)
    checkEqInt(h.length, 3, `${label}: the fixture makes one box per item`)
    checkEqInt(r.length, 3, `${label}: in vertical-rl too`)
    checkEqInt(l.length, 3, `${label}: and in vertical-lr`)
    checkEqInt(r[0].w, h[0].h, `${label}: the container is as wide as the horizontal one is tall`)
    checkEqInt(r[0].h, h[0].w, `${label}: and as tall as it is wide`)
    for int i = 1, i < 3, i++ {
        checkEqInt(r[i].h, h[i].w, `${label}: item ${i}'s inline extent becomes its height`)
        checkEqInt(r[i].w, h[i].h, `${label}: and its block extent its width`)
        checkEqInt(r[i].y - r[0].y, h[i].x - h[0].x, `${label}: item ${i} keeps its inline offset`)
        checkEqInt((r[i].x - r[0].x) + r[i].w, r[0].w - (h[i].y - h[0].y),
            `${label}: and lies that far from the block-start edge, which is the right one`)
        checkEqInt(l[i].h, h[i].w, `${label}: vertical-lr agrees on item ${i}'s inline extent`)
        checkEqInt(l[i].w, h[i].h, `${label}: and on its block extent`)
        checkEqInt(l[i].y - l[0].y, h[i].x - h[0].x, `${label}: and on its inline offset`)
        checkEqInt(l[i].x - l[0].x, h[i].y - h[0].y,
            `${label}: and puts item ${i} that far from the left, its block-start edge`)
    }
    // A fixture whose two vertical modes come out identical cannot tell
    // a block direction from its reverse, and every check above would
    // hold on an engine that treated them alike. One item is enough to
    // tell them apart; a fixture that stretches an item across the whole
    // block extent hides the difference in that one.
    check(r[1].x - r[0].x != l[1].x - l[0].x || r[2].x - r[0].x != l[2].x - l[0].x,
        `${label}: the two block directions really do differ`)
}

fcCheck('flex', 'display:flex;inline-size:100px;block-size:60px',
    '<p class=z style="inline-size:40px;block-size:20px"></p>' +
    '<p class=z style="inline-size:25px;block-size:30px"></p>')

fcCheck('grid', 'display:grid;grid-template-columns:40px 25px;grid-template-rows:20px 25px;' +
    'inline-size:100px;block-size:60px',
    '<p class=z style="grid-column:1;grid-row:1"></p>' +
    '<p class=z style="grid-column:2;grid-row:2"></p>')

fcCheck('table', 'display:table;inline-size:100px;block-size:60px',
    '<div style="display:table-row"><p class=z style="display:table-cell;block-size:20px"></p></div>' +
    '<div style="display:table-row"><p class=z style="display:table-cell;block-size:30px"></p></div>')

fcCheck('multicol', 'columns:2;column-gap:10px;column-fill:auto;inline-size:100px;block-size:60px',
    '<p class=z style="block-size:20px"></p>' +
    '<p class=z style="block-size:30px"></p>')

// The two cases above leave grid's own length reads untouched, because
// tracks size items that declare nothing. These two make them matter:
// the first gives an item a logical size of its own inside a larger
// track and leaves the second's block size to be stretched to its row,
// the second leaves the container's block size to be found from the
// tracks.
fcCheck('grid sized',
    'display:grid;grid-template-columns:60px 40px;grid-template-rows:30px 25px;' +
    'inline-size:100px;block-size:60px',
    '<p class=z style="grid-column:1;grid-row:1;inline-size:40px;block-size:20px"></p>' +
    '<p class=z style="grid-column:2;grid-row:2;inline-size:25px"></p>')

fcCheck('grid auto',
    'display:grid;grid-template-columns:60px 40px;inline-size:100px',
    '<p class=z style="grid-column:1;block-size:20px"></p>' +
    '<p class=z style="grid-column:2;block-size:35px"></p>')

// Flex, likewise, is graded by three more fixtures: a column container,
// whose main axis is the block one and whose lengths therefore exchange
// the other way; an item with no block size of its own, which stretches
// to the line's cross size; and two items that grow, so that the
// resolved main size is not simply what was declared.
fcCheck('flex column', 'display:flex;flex-direction:column;inline-size:100px;block-size:60px',
    '<p class=z style="inline-size:40px;block-size:20px"></p>' +
    '<p class=z style="inline-size:25px;block-size:30px"></p>')

fcCheck('flex stretch', 'display:flex;inline-size:100px;block-size:60px',
    '<p class=z style="inline-size:40px"></p>' +
    '<p class=z style="inline-size:25px;block-size:30px;align-self:start"></p>')

fcCheck('flex grow', 'display:flex;inline-size:100px;block-size:60px',
    '<p class=z style="flex:1 1 20px;block-size:20px"></p>' +
    '<p class=z style="flex:2 1 20px;block-size:30px"></p>')

// ---- an auto margin on an orthogonal flow ------------------------------
// Chromium's twelve rows are in todo.md, "An auto margin on an
// orthogonal flow, measured". What they say is that nothing here is
// special: a logical margin property maps through the element's own
// writing mode, and an auto margin resolves against the CONTAINING
// BLOCK's inline axis -- which for an orthogonal flow is the page's
// horizontal, not the axis the flow was laid out along. So the check is
// the agreement that follows. A turned box whose physical side margins
// are auto must land exactly where an ordinary block of the same
// physical size and the same physical margins lands, whichever
// property was written to produce them.

int func amPlaced(style:text, mode:text, sizes:text) {
    Page p = pageFromHtml(
        `<!doctype html><html><head><style>body{margin:0;font-size:16px}` +
        `.o{width:200px;height:100px}</style></head><body>` +
        `<div class="o"><div style="writing-mode:${mode};${style};${sizes}">a` +
        `</div></div></body></html>`, 'about:blank', 800)
    arr[Box] all = []
    collectBoxesForTag(p.root, 'div', all)
    return all[1].x - all[0].x
}

// The reference: an ordinary horizontal block, 30 wide and 40 tall.
int func amRef(style:text) {
    return amPlaced(style, 'horizontal-tb', 'width:30px;height:40px')
}
// The flow: the same physical box, arrived at by turning a 40x30 one.
int func amFlow(style:text) {
    return amPlaced(style, 'vertical-rl', 'inline-size:40px;block-size:30px')
}

// The reference is anchored to Chromium's own numbers, so the agreement
// below cannot be satisfied by two engines being wrong together.
checkEqInt(amRef('margin:0 auto'), 85, 'two auto side margins centre a 30-wide block in a 200-wide one')
checkEqInt(amRef('margin-left:auto'), 170, 'one auto side margin pushes it to the far edge')
checkEqInt(amRef('margin-top:auto'), 0, 'an auto top margin moves it sideways not at all')

// The instrument: three references that are all the same number would
// grade a broken engine and a working one alike.
check(amRef('margin:0 auto') != amRef('margin-left:auto'), 'the three references differ')
check(amRef('margin:0 auto') != amRef('margin-top:auto'), 'and the third differs from the first')

// `margin: 0 auto` names the physical sides, and they are the
// containing block's inline axis whatever the flow inside is doing.
checkEqInt(amFlow('margin:0 auto'), amRef('margin:0 auto'),
    'a turned box with two auto side margins centres where a block does')
checkEqInt(amFlow('margin-left:auto'), amRef('margin-left:auto'),
    'and with one it reaches the same far edge')

// `margin-block` on a vertical box IS its left and right margins, so it
// must land in the same place as writing them physically.
checkEqInt(amFlow('margin-block:auto'), amRef('margin-left:auto;margin-right:auto'),
    'margin-block on a vertical box is the side pair, and centres')

// `margin-inline` on a vertical box is its top and bottom margins,
// which the containing block's block axis does not centre.
checkEqInt(amFlow('margin-inline:auto'), amRef('margin-top:auto;margin-bottom:auto'),
    'margin-inline on a vertical box is the other pair, and does not')
checkEqInt(amFlow('margin-inline-start:auto'), amRef('margin-top:auto'),
    'and margin-inline-start is its top margin')
checkEqInt(amFlow('margin-top:auto'), amRef('margin-top:auto'),
    'an auto top margin still moves it sideways not at all')

finish('writing-mode')
