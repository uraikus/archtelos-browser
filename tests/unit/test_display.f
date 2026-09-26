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

// ---- display: inline-table --------------------------------------------
// A table is a table inside and an inline outside, so it sits on the
// line with the text beside it and takes the width its cells ask for
// rather than its containing block's. Chromium puts the box at x=58
// after six monospace characters, 80px wide for two 40px cells, and
// gives the wrapper a single 25px line -- against 60px of wrapper and
// x=0 for the block-level `table` the same markup makes.
const text TABLE_CELLS = '<tr><td style="padding:0;width:40px;height:20px">x</td>'
    + '<td style="padding:0;width:40px;height:20px">y</td></tr></table>after</div></body>'
const text TABLE_HEAD = displayHead
    + '<style>table { border-spacing:0 } td { padding:0 }</style>'

Box blockTable = displayLayout(TABLE_HEAD
    + '<div id="w">before<table id="t" style="display:table">' + TABLE_CELLS, 400)
Box inlineTable = displayLayout(TABLE_HEAD
    + '<div id="w">before<table id="t" style="display:inline-table">' + TABLE_CELLS, 400)
Box inlineBlock = displayLayout(TABLE_HEAD
    + '<div id="w">before<span id="t" style="display:inline-block;width:80px;height:20px">'
    + '</span>after</div></body>', 400)

// The block-level table is the control: it is what `inline-table` did
// before, so a change that did nothing would make the two agree.
checkEqInt(displayFind(blockTable, 't').x, 0, 'a block-level table starts a line of its own')
checkEqInt(displayFind(inlineTable, 't').x, displayFind(inlineBlock, 't').x,
           'an inline-table sits where an inline-block of its width would')
check(displayFind(inlineTable, 't').x != displayFind(blockTable, 't').x,
      'which is not where the block-level table sits')

// Width comes from the cells either way: a table is shrink-to-fit
// whichever way round its outside is.
checkEqInt(displayFind(inlineTable, 't').w, 80, 'two 40px cells make it 80 wide')
checkEqInt(displayFind(inlineTable, 't').w, displayFind(blockTable, 't').w,
           'and the outer display does not change that')

// One line, not three: the text before and after share it.
checkEqInt(displayFind(inlineTable, 'w').h, displayFind(inlineBlock, 'w').h,
           'the wrapper is one line high, as it is for an inline-block')
check(displayFind(inlineTable, 'w').h < displayFind(blockTable, 'w').h,
      'and shorter than the three the block-level table needs')

// ---- blockification (Display 3 sec. 2.7) -------------------------------
// A floated box, an absolutely positioned one, a flex or grid item and
// the root element all have their `display` blockified: the
// inline-level value is replaced by the block-level one it corresponds
// to. css-2026.md recorded this as missing, and it was: the box tree
// converted a flex item's *box kind* and nothing anywhere touched the
// computed value, so `display: inline; float: left` stayed `inline`
// where Chromium reports `block`.
//
// Every expectation below is Chromium 141's, read with getComputedStyle
// off the same declaration.
int func displayOf(css:text, body:text) {
    cascadeReset()
    Node d = parseHtmlText('<html><head><style>' + css + '</style></head><body>'
        + body + '</body></html>')
    cascadeAddDocumentStyles(d)
    computeStyles(d)
    arr[Node] found = []
    collectElements(d, 'span', found)
    for int i = 0, i < found.length, i++ {
        if attrOf(found[i].id, 'id') == 'q' { return found[i].style.display }
    }
    return 0 - 1
}
text plainParent = '<div id="p"><span id="q">x</span></div>'
text flexParent = '<div id="p" style="display:flex"><span id="q">x</span></div>'
text gridParent = '<div id="p" style="display:grid"><span id="q">x</span></div>'

// A float blockifies, and the inline-level values map onto their
// block-level twins rather than all collapsing to `block`.
checkEqInt(displayOf('#q{display:inline;float:left}', plainParent),
           DISPLAY_BLOCK, 'a floated inline is blockified')
checkEqInt(displayOf('#q{display:inline-block;float:left}', plainParent),
           DISPLAY_BLOCK, 'and a floated inline-block')
checkEqInt(displayOf('#q{display:inline-flex;float:left}', plainParent),
           DISPLAY_FLEX, 'a floated inline-flex becomes a flex container')
checkEqInt(displayOf('#q{display:inline-grid;float:left}', plainParent),
           DISPLAY_GRID, 'and an inline-grid a grid one')
checkEqInt(displayOf('#q{display:inline-table;float:left}', plainParent),
           DISPLAY_TABLE, 'and an inline-table a table')
// The two values a float leaves alone, which is what stops this being
// "set everything to block".
checkEqInt(displayOf('#q{display:none;float:left}', plainParent),
           DISPLAY_NONE, '`none` is not blockified')
checkEqInt(displayOf('#q{display:contents;float:left}', plainParent),
           DISPLAY_CONTENTS, 'and neither is `contents`')

// Absolute and fixed positioning blockify; relative does not, which is
// the pair that stops a test passing on "any position at all".
checkEqInt(displayOf('#q{display:inline;position:absolute}', plainParent),
           DISPLAY_BLOCK, 'an absolutely positioned inline is blockified')
checkEqInt(displayOf('#q{display:inline;position:fixed}', plainParent),
           DISPLAY_BLOCK, 'and a fixed one')
checkEqInt(displayOf('#q{display:inline;position:relative}', plainParent),
           DISPLAY_INLINE, 'but a relatively positioned one is not')

// A flex or grid item is blockified by its parent, not by anything it
// says itself.
checkEqInt(displayOf('#q{display:inline}', flexParent),
           DISPLAY_BLOCK, 'a flex item is blockified')
checkEqInt(displayOf('#q{display:inline-flex}', flexParent),
           DISPLAY_FLEX, 'and an inline-flex item becomes a flex container')
checkEqInt(displayOf('#q{display:inline}', gridParent),
           DISPLAY_BLOCK, 'a grid item is blockified')
checkEqInt(displayOf('#q{display:inline-table}', gridParent),
           DISPLAY_TABLE, 'and an inline-table grid item a table')

finish('display')
