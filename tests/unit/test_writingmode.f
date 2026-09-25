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

finish('writing-mode')
