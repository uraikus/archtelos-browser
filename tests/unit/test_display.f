// CSS Display 3's box-generation rules, where they differ from CSS2's.
//
// The expected geometry is Chromium 141's, read off the same fixtures
// with getBoundingClientRect.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func displayLayout(html:text, width:int) {
    cascadeReset()
    cssViewportWidth = width
    Node doc = parseHtmlText(html)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return layoutDocument(doc, width)
}

Box func displayFind(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = displayFind(b.children[i], id)
        if f != null { return f }
    }
    return null
}

text displayHead = '<body style="margin:0;font:16px/20px monospace">'

// ---- display: contents ------------------------------------------------
// The element generates no box at all. Its children are laid out where
// it was, as children of its parent, and its own box properties -- a
// height, a border, a background -- describe a box that does not exist.

Box contentsWrap = displayLayout(displayHead
    + '<div id="c" style="width:300px">'
    + '<div id="w" style="display:contents">'
    + '<div id="a" style="height:30px"></div><div id="b" style="height:40px"></div>'
    + '</div></div></body>', 400)
check(displayFind(contentsWrap, 'w') == null, 'display:contents generates no box')
checkEqInt(displayFind(contentsWrap, 'a').y, 0, 'its first child starts where it would have')
checkEqInt(displayFind(contentsWrap, 'b').y, 30, 'and the second under that')
checkEqInt(displayFind(contentsWrap, 'a').w, 300, 'at the width of the box that remains')
checkEqInt(displayFind(contentsWrap, 'c').h, 70, 'the container is the two children stacked')

// A wrapper with no box properties of its own lays out identically
// whether it generates a box or not, so the two must agree.
Box plainWrap = displayLayout(displayHead
    + '<div id="c" style="width:300px">'
    + '<div id="w">'
    + '<div id="a" style="height:30px"></div><div id="b" style="height:40px"></div>'
    + '</div></div></body>', 400)
checkEqInt(displayFind(contentsWrap, 'c').h, displayFind(plainWrap, 'c').h,
           'a wrapper with no box of its own gives the same height either way')
checkEqInt(displayFind(contentsWrap, 'b').y, displayFind(plainWrap, 'b').y,
           'and puts the children in the same place')

// Its own height, border and background describe nothing.
Box contentsStyled = displayLayout(displayHead
    + '<div id="c" style="width:300px">'
    + '<div id="w" style="display:contents;height:100px;border:10px solid blue;background:red">'
    + '<div id="a" style="height:30px"></div>'
    + '</div></div></body>', 400)
checkEqInt(displayFind(contentsStyled, 'c').h, 30, 'a height on a contents box is not a box')
checkEqInt(displayFind(contentsStyled, 'a').x, 0, 'nor is a border, which would have inset the child')
checkEqInt(displayFind(contentsStyled, 'a').w, 300, 'at the full width')

// What it does keep is inheritance: its children inherit from it, so a
// font size set on a box that does not exist still reaches them.
Box contentsInherit = displayLayout(displayHead
    + '<div id="c" style="width:300px">'
    + '<div style="display:contents;font-size:40px"><div id="a">x</div></div>'
    + '</div></body>', 400)
checkEqInt(displayFind(contentsInherit, 'a').style.fontSize, 40,
           'a contents element still passes its inherited values down')

// Nested contents elements collapse through both.
Box contentsNested = displayLayout(displayHead
    + '<div id="c" style="width:300px">'
    + '<div style="display:contents"><div style="display:contents">'
    + '<div id="a" style="height:30px"></div></div></div>'
    + '</div></body>', 400)
checkEqInt(displayFind(contentsNested, 'a').y, 0, 'two contents elements deep is still no box')
checkEqInt(displayFind(contentsNested, 'c').h, 30, 'and the container is its one real child')

// ---- an unknown display value -----------------------------------------
// It is not a value of the property, so the declaration is invalid and
// dropped -- the element keeps the display it would have had. A div is
// a block; a span is an inline.

Box unknownDisplay = displayLayout(displayHead
    + '<div id="c" style="width:300px">'
    + '<div id="a" style="display:bogus;height:30px"></div>'
    + '<div id="b" style="height:40px"></div>'
    + '</div></body>', 400)
checkEqInt(displayFind(unknownDisplay, 'a').w, 300, 'an unknown display leaves a div a block')
checkEqInt(displayFind(unknownDisplay, 'b').y, 30, 'stacking as a block does')
checkEqInt(displayFind(unknownDisplay, 'c').h, 70, 'and the container is both of them')

finish('display')
