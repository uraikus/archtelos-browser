// CSS Containment 1.
//
// Size containment is the one of the four that changes geometry: a box
// with it is laid out as if it had no content at all, so an automatic
// height is zero however much is inside. `contain-intrinsic-size` and
// its four friends put a size back, which is the whole reason they
// exist -- without size containment they do nothing, so every check
// here declares the two together and one check asks what happens when
// only the intrinsic size is given.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func layoutHtml(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, width)
}

Box func findBox(b:Box, tag:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node.tag == tag { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = findBox(b.children[i], tag)
        if f != null { return f }
    }
    return null
}

text head = '<body style="margin:0;font:16px/20px monospace">'
text filling = '<p style="margin:0;height:50px">x</p>'

Box func boxWith(style:text) {
    return findBox(layoutHtml(head + '<div id="t" style="' + style + '">'
        + filling + '</div></body>', 400), 'div')
}

// ---- the control ---------------------------------------------------------

Box plain = boxWith('')
checkEqInt(plain.h, 50, 'an uncontained box is as tall as what is in it')

// ---- size containment ----------------------------------------------------

Box sized = boxWith('contain:size')
checkEqInt(sized.h, 0, 'contain:size lays the box out as if it were empty')

Box sizedH = boxWith('contain:size;contain-intrinsic-height:10px')
checkEqInt(sizedH.h, 10, 'contain-intrinsic-height supplies the height instead')

Box sizedBlock = boxWith('contain:size;contain-intrinsic-block-size:10px')
checkEqInt(sizedBlock.h, sizedH.h, 'contain-intrinsic-block-size is the same edge')
check(sizedBlock.h != plain.h,
      'and is not simply the uncontained height on both, which would make that vacuous')

// The shorthand takes one or two values, the second being the block one.
Box sizedShort = boxWith('contain:size;contain-intrinsic-size:30px 10px')
checkEqInt(sizedShort.h, 10, 'the second value of contain-intrinsic-size is the height')

Box sizedOne = boxWith('contain:size;contain-intrinsic-size:10px')
checkEqInt(sizedOne.h, 10, 'one value is both, so it is the height too')

// An explicit height still wins: the intrinsic size is what `auto`
// resolves to, not an override.
Box explicitH = boxWith('contain:size;contain-intrinsic-height:10px;height:70px')
checkEqInt(explicitH.h, 70, 'an explicit height beats the intrinsic one')

// ---- the intrinsic size does nothing on its own --------------------------
// Without size containment the box measures its content, which is what
// makes this a real check rather than one the property could pass by
// being read and applied everywhere.

Box uncontained = boxWith('contain-intrinsic-height:10px')
checkEqInt(uncontained.h, 50, 'contain-intrinsic-height alone changes nothing')

// ---- the shorthands ------------------------------------------------------
// `strict` is size, layout, paint and style; `content` is all of those
// but size. So one contains the size and the other does not.

Box strict = boxWith('contain:strict')
checkEqInt(strict.h, 0, 'contain:strict contains the size')

Box content = boxWith('contain:content')
checkEqInt(content.h, 50, 'contain:content does not')

Box none = boxWith('contain:none')
checkEqInt(none.h, 50, 'and contain:none contains nothing')

// Naming more than one keyword works, and the order does not matter.
Box both = boxWith('contain:layout size')
checkEqInt(both.h, 0, 'a list of keywords takes each of them')
Box bothRev = boxWith('contain:size layout')
checkEqInt(bothRev.h, both.h, 'in either order')

// A keyword that is not size leaves the height alone, which is the
// check that `contain` is read per keyword rather than as a boolean.
Box layoutOnly = boxWith('contain:layout')
checkEqInt(layoutOnly.h, 50, 'contain:layout does not contain the size')
Box paintOnly = boxWith('contain:paint')
checkEqInt(paintOnly.h, 50, 'nor does contain:paint')

// ---- content-visibility --------------------------------------------------
// `hidden` skips the contents entirely, which carries size containment
// with it, so the box collapses unless an intrinsic size says otherwise.

Box hidden = boxWith('content-visibility:hidden')
checkEqInt(hidden.h, 0, 'content-visibility:hidden skips the contents')

Box hiddenSized = boxWith('content-visibility:hidden;contain-intrinsic-height:10px')
checkEqInt(hiddenSized.h, 10, 'and takes the intrinsic size when there is one')

Box visible = boxWith('content-visibility:visible')
checkEqInt(visible.h, 50, 'content-visibility:visible is the initial value and skips nothing')

// ---- the inline axis -----------------------------------------------------
// A block box fills its container either way, so the inline intrinsic
// size shows on a shrink-to-fit box instead.

Box shrinkPlain = findBox(layoutHtml(head
    + '<div id="t" style="display:inline-block">xxxxxxxxxx</div></body>', 400), 'div')
Box shrinkContained = findBox(layoutHtml(head
    + '<div id="t" style="display:inline-block;contain:size;contain-intrinsic-width:30px">'
    + 'xxxxxxxxxx</div></body>', 400), 'div')
check(shrinkPlain.w > 30, 'the shrink-to-fit fixture is wider than its intrinsic size')
checkEqInt(shrinkContained.w, 30, 'contain-intrinsic-width supplies a contained box its width')

Box shrinkInline = findBox(layoutHtml(head
    + '<div id="t" style="display:inline-block;contain:size;contain-intrinsic-inline-size:30px">'
    + 'xxxxxxxxxx</div></body>', 400), 'div')
checkEqInt(shrinkInline.w, shrinkContained.w, 'contain-intrinsic-inline-size is the same edge')
check(shrinkInline.w != shrinkPlain.w,
      'and is not simply the uncontained width on both')

// ---- one axis at a time -----------------------------------------------
// `contain: size` contains both axes; `contain: inline-size` contains
// only the inline one, so the box is as wide as an empty box would be
// and as tall as its content needs once wrapped into that width.
//
// A float is what makes the difference visible, because a float's width
// is shrink-to-fit -- a block-level box takes its containing block's
// width whether its contents are measured or not, so it cannot show
// this at all. Chromium puts an uncontained float at 145px wide and one
// line tall, and the same float under `contain: inline-size` at 0 wide
// and three lines tall.
text containFloatHead = '<body style="margin:0;font:16px/20px monospace;width:600px">'
Box func containedFloat(css:text) {
    return findBox(layoutHtml(containFloatHead + '<div id="f" style="float:left;' + css
        + '">some words here</div></body>', 600), 'div')
}

Box plainFloat = containedFloat('')
Box inlineContained = containedFloat('contain: inline-size')
Box bothContained = containedFloat('contain: size')

check(plainFloat.w > 0, 'an uncontained float is as wide as its words')
checkEqInt(inlineContained.w, 0, 'inline-size containment makes it as wide as an empty box')
check(inlineContained.h > plainFloat.h,
      'so the words wrap, and it is taller than the uncontained one')
checkEqInt(bothContained.w, 0, 'size containment contains the inline axis too')
checkEqInt(bothContained.h, 0, 'and the block axis, which inline-size leaves alone')
check(inlineContained.h != bothContained.h,
      'which is the whole difference between the two values')

// ---- container-type is that containment, under another name -----------
// `container-type: inline-size` applies inline-size containment, and
// `container-type: size` applies it on both axes. Chromium lays out a
// float under either exactly as it lays out the matching `contain`
// value, so that is what is asserted rather than a number worked out
// again here.
checkEqInt(containedFloat('container-type: inline-size').w, inlineContained.w,
           'container-type: inline-size is inline-size containment, across')
checkEqInt(containedFloat('container-type: inline-size').h, inlineContained.h,
           'and down')
checkEqInt(containedFloat('container-type: size').w, bothContained.w,
           'container-type: size is size containment, across')
checkEqInt(containedFloat('container-type: size').h, bothContained.h,
           'and down')
// `normal` is the initial value and contains nothing.
checkEqInt(containedFloat('container-type: normal').w, plainFloat.w,
           'container-type: normal contains nothing')

// A block-level box shows none of this, because its width comes from
// its containing block either way. This is the row that would catch a
// containment applied to the wrong axis or to the wrong box.
Box blockContainer = findBox(layoutHtml(containFloatHead
    + '<div id="b" style="container-type:inline-size">block text</div></body>', 600), 'div')
Box blockPlain = findBox(layoutHtml(containFloatHead
    + '<div id="b">block text</div></body>', 600), 'div')
checkEqInt(blockContainer.w, blockPlain.w, 'a block container is as wide as it ever was')
checkEqInt(blockContainer.h, blockPlain.h, 'and as tall')

finish('containment')
