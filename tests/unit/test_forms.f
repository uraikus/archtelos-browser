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

finish('forms')
