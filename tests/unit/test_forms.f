// The form-control properties: `appearance`, `accent-color` and
// `field-sizing`.
//
// Read off Chromium 141, at its default form font:
//
//   <input type=checkbox>                       13 x 13
//   the same with appearance: none               0 x  0
//   <input type=text>                          185 x 21
//   <input type=text value="ab">               185 x 21   the value does not size it
//   the same with field-sizing: content       22.8 x 21   and now it does
//   accent-color: red                    computes to rgb(255, 0, 0)
//
// The absolute widths are Chromium's font rather than this one's, so
// what is checked here are the relations they stand for: a fixed field
// is the same width whatever is in it, a content field is not, and a
// checkbox told not to look like one takes no room.
import ../../src/browser/page.f
import ../assert.f

text fHead = '<!doctype html><body style="margin:0;font:16px/20px monospace">'

Box func formBox(markup:text, tag:text) {
    Page p = pageFromHtml(fHead + markup + '</body>', 'tests/fixtures/page.html', 400)
    arr[Box] all = []
    collectBoxesForTag(p.root, tag, all)
    return all.length > 0 ? all[0] : null
}

// ---- field-sizing ------------------------------------------------------
// The initial value is `fixed`: the control is as wide as it would be
// empty, whatever it holds. This engine used to shrink-wrap every text
// input to its value, which made an empty one fourteen pixels wide.

Box fEmpty = formBox('<input type="text">', 'input')
Box fShort = formBox('<input type="text" value="ab">', 'input')
Box fLong = formBox('<input type="text" value="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">', 'input')
check(fEmpty != null, 'a text input has a box')
check(fEmpty.w > 100, 'an empty text input is a field wide rather than a few pixels')
checkEqInt(fShort.w, fEmpty.w, 'a short value does not shrink a fixed field')
checkEqInt(fLong.w, fEmpty.w, 'and a long one does not stretch it')

Box cShort = formBox('<input type="text" style="field-sizing:content" value="ab">', 'input')
Box cLong = formBox('<input type="text" style="field-sizing:content" '
    + 'value="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">', 'input')
Box cEmpty = formBox('<input type="text" style="field-sizing:content">', 'input')
check(cShort.w < fEmpty.w, '`field-sizing: content` sizes a short value smaller than a field')
check(cLong.w > cShort.w, 'and a long value larger than a short one')
check(cEmpty.w < cShort.w, 'and an empty one smallest of all')

// An explicit width beats both, which is what tells this from a
// default that is simply always applied.
Box fWidth = formBox('<input type="text" style="width:60px">', 'input')
Box cWidth = formBox('<input type="text" style="width:60px;field-sizing:content" value="ab">',
                     'input')
checkEqInt(fWidth.w, cWidth.w, 'a declared width wins over either sizing')

// ---- appearance --------------------------------------------------------
// A checkbox is given its size by the user agent, and `appearance: none`
// is what says not to draw a checkbox -- so the size goes with it.

Box aBox = formBox('<input type="checkbox">', 'input')
Box aNone = formBox('<input type="checkbox" style="appearance:none">', 'input')
Box aRadio = formBox('<input type="radio">', 'input')
Box aRadioNone = formBox('<input type="radio" style="appearance:none">', 'input')
check(aBox.w > 0 && aBox.h > 0, 'a checkbox has a size of its own')
checkEqInt(aNone.w, 0, '`appearance: none` takes the width away')
checkEqInt(aNone.h, 0, 'and the height')
check(aRadio.w > 0, 'a radio has one too')
checkEqInt(aRadioNone.w, 0, 'and loses it the same way')

// A declared size is still honoured: `appearance: none` drops what the
// user agent supplied, not what the author asked for.
Box aSized = formBox('<input type="checkbox" style="appearance:none;width:30px;height:30px">',
                     'input')
Box aSizedAuto = formBox('<input type="checkbox" style="width:30px;height:30px">', 'input')
checkEqInt(aSized.w, aSizedAuto.w, 'a declared width survives appearance: none')
checkEqInt(aSized.h, aSizedAuto.h, 'and so does a declared height')
check(aSized.w >= 30, 'and is at least the width that was declared')

// A text input keeps its geometry, as it does in Chromium: there is no
// native chrome here for `none` to take away.
Box aText = formBox('<input type="text">', 'input')
Box aTextNone = formBox('<input type="text" style="appearance:none">', 'input')
checkEqInt(aTextNone.w, aText.w, 'a text input is unchanged by appearance: none')

// ---- ::placeholder (CSS Pseudo-Elements 4 §3.5) ------------------------
//
// The placeholder attribute was already laid out as the control's text;
// what this adds is the pseudo-element that styles it. Measured in
// Chromium (todo.md): the grey is `rgb(117, 117, 117)` and the input's
// own `color` does not reach it, because the grey is a declaration in
// the user agent's stylesheet on the pseudo-element itself and an
// inherited value loses to any declaration whatever its origin. Font
// properties inherit from the input, a declaration on the
// pseudo-element wins, and `display` is ignored.

// Derived rather than hand-encoded: a colour here carries its alpha,
// so a literal would be asserting the packing as well as the value.
int PLACEHOLDER_GREY = parseCssColor('#757575'.toAscii(), 0)

// The style the placeholder's own text box is wearing.
Style func phStyle(markup:text) {
    Box b = formBox(markup, 'input')
    if b == null || b.children.length == 0 { return null }
    return b.children[0].style
}

Style phPlain = phStyle('<input placeholder="HELLO">')
check(phPlain != null, 'a placeholder gives the control a text box')
checkEqInt(phPlain.color, PLACEHOLDER_GREY, 'a placeholder is grey, not the text colour')

// The input's own colour does not reach it.
Style phInputColor = phStyle('<input placeholder="HELLO" style="color:#cc0000">')
checkEqInt(phInputColor.color, PLACEHOLDER_GREY,
           'the input colour does not reach the placeholder')

// A value is the input's text rather than a placeholder, so it does
// take the input's colour -- which is what says the grey belongs to the
// pseudo-element rather than to every text box a control makes.
Page pv = pageFromHtml(fHead + '<input value="ab" style="color:#cc0000">'
    + '</body>', 'tests/fixtures/page.html', 400)
arr[Box] vall = []
collectBoxesForTag(pv.root, 'input', vall)
checkEqInt(vall[0].children[0].style.color, parseCssColor('#cc0000'.toAscii(), 0),
           'a value does take the input colour')

// A declaration on the pseudo-element wins over the user agent's.
Page pb = pageFromHtml('<!doctype html><head><style>'
    + 'input::placeholder { color: #0000ff }</style>'
    + '<body style="margin:0;font:16px/20px monospace">'
    + '<input placeholder="HELLO">' + '</body>', 'tests/fixtures/page.html', 400)
arr[Box] ball = []
collectBoxesForTag(pb.root, 'input', ball)
checkEqInt(ball[0].children[0].style.color, parseCssColor('#0000ff'.toAscii(), 0),
           'a declared colour wins over the grey')

// Font size inherits from the input, and a declaration on the
// pseudo-element wins over what it inherited.
Style phFs = phStyle('<input placeholder="HELLO" style="font-size:20px">')
checkEqInt(phFs.fontSize, 20, 'the placeholder inherits the font size')

Page pf = pageFromHtml('<!doctype html><head><style>'
    + 'input::placeholder { font-size: 9px }</style>'
    + '<body style="margin:0;font:16px/20px monospace">'
    + '<input placeholder="HELLO" style="font-size:20px">' + '</body>',
    'tests/fixtures/page.html', 400)
arr[Box] fall = []
collectBoxesForTag(pf.root, 'input', fall)
checkEqInt(fall[0].children[0].style.fontSize, 9, 'and a declared size wins over that')

// `display` is ignored: Chromium reports `block` under `display: none`,
// and the placeholder is still there.
Page pd = pageFromHtml('<!doctype html><head><style>'
    + 'input::placeholder { display: none }</style>'
    + '<body style="margin:0;font:16px/20px monospace">'
    + '<input placeholder="HELLO">' + '</body>', 'tests/fixtures/page.html', 400)
arr[Box] dall = []
collectBoxesForTag(pd.root, 'input', dall)
check(dall[0].children.length > 0, 'display: none does not remove the placeholder')

// A rule with no pseudo-element does not style the placeholder, and one
// with it does not style the input -- the two passes have opposite
// filters, which is what the ::before and ::after code already relies on.
Page ps2 = pageFromHtml('<!doctype html><head><style>'
    + 'input { letter-spacing: 3px }</style>'
    + '<body style="margin:0;font:16px/20px monospace">'
    + '<input placeholder="HELLO">' + '</body>', 'tests/fixtures/page.html', 400)
arr[Box] sall = []
collectBoxesForTag(ps2.root, 'input', sall)
checkEqInt(sall[0].children[0].style.letterSpacing, 3,
           'an inherited property does reach the placeholder')

finish('forms')
