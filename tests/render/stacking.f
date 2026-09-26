// CSS2 §9.9's painting order, asked in pixels.
//
// Within a stacking context the order is: the context element's own
// background and border, then its negative-`z-index` descendants, then
// the in-flow block descendants, the floats, the inline content, and
// finally the positioned descendants at zero and above. The part that
// is not obvious is what happens to a negative child of a box that is
// *not* a stacking context: it belongs to the nearest ancestor that is,
// so it paints **behind that box's own background**.
//
// Measured in Chromium (todo.md), with everything stacked at one spot
// and `elementFromPoint` naming the winner:
//
//   parent not a context   over the parent's background alone -> the parent
//   parent a context       over the same spot                 -> the child
//   either                 over an in-flow block sibling      -> the block
//
// and the three things that make a context -- a declared `z-index` on a
// positioned box, a `transform`, an `opacity` below 1 -- all answer the
// same way.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(400)

color green = '#00ff00'
color magenta = '#ff00ff'
color blue = '#0088ff'
color white = 'white'

// A 200x200 green parent, a magenta `z-index: -1` child covering all of
// it, and a 200x60 blue in-flow block across its top. Three questions in
// one picture: (30,150) is the parent's background against the negative
// child, and (30,30) is the in-flow block against both.
text stackBody = '<div id="p"><div id="neg"></div><div id="flow"></div></div>'

void func shotStack(extra:text) {
    Page p = pageFromHtml('<!doctype html><head><style>'
        + 'body{margin:0}'
        + '#p{position:relative;width:200px;height:200px;background:#00ff00;' + extra + '}'
        + '#flow{width:200px;height:60px;background:#0088ff}'
        + '#neg{position:absolute;z-index:-1;left:0;top:0;width:200px;height:200px;'
        + 'background:#ff00ff}'
        + '</style><body>' + stackBody + '</body>', 'test.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 400)
}

// ---- a parent that is not a stacking context ---------------------------
// `position: relative` with no `z-index` is not one, so the negative
// child is hoisted past it and paints behind its background.
shotStack('')
check(getPixelColor(30, 150) == green, 'a negative child is behind a non-context parent')
check(getPixelColor(30, 30) == blue, 'and behind the in-flow block as well')

// ---- a declared z-index makes one --------------------------------------
shotStack('z-index:0')
check(getPixelColor(30, 150) == magenta, 'a declared z-index makes a stacking context')
check(getPixelColor(30, 30) == blue, 'the in-flow block still paints over the negative child')

// ---- and so does a transform -------------------------------------------
shotStack('transform:translateX(0px)')
check(getPixelColor(30, 150) == magenta, 'a transform makes a stacking context')
check(getPixelColor(30, 30) == blue, 'with the same order inside it')

// The two spellings of a context must agree, which needs no number.
shotStack('z-index:0')
color zeroAt150 = getPixelColor(30, 150)
color zeroAt30 = getPixelColor(30, 30)
shotStack('transform:rotate(0deg)')
check(getPixelColor(30, 150) == zeroAt150, 'an identity transform is a context like a z-index')
check(getPixelColor(30, 30) == zeroAt30, 'on both points')

// `z-index: auto` is not a declared z-index, so it must agree with
// declaring nothing at all rather than with declaring zero.
shotStack('')
color plainAt150 = getPixelColor(30, 150)
shotStack('z-index:auto')
check(getPixelColor(30, 150) == plainAt150, 'z-index: auto is not a stacking context')

// ---- a page with no negative z-index is untouched ----------------------
// The whole pass is behind a per-document flag, so a document that never
// says a negative z-index must paint exactly as it did. Two stacks of
// positioned boxes, one drawn with the flag down and one that would
// raise it elsewhere on the page, must agree where they overlap.
Page pz = pageFromHtml('<!doctype html><head><style>body{margin:0}'
    + '#a{position:absolute;left:0;top:0;width:100px;height:100px;background:#00ff00;z-index:0}'
    + '#b{position:absolute;left:0;top:0;width:100px;height:100px;background:#ff00ff}'
    + '</style><body><div id="a"></div><div id="b"></div></body>', 'test.html', 400)
clearCanvas()
paintPage(pz, 0, 0, 400)
check(getPixelColor(30, 30) == magenta,
      'a later z-index: auto box paints over an earlier z-index: 0 one')

// ---- §9.9's steps 3, 4 and 5 -------------------------------------------
//
// The three in-flow steps are separate: the block-level descendants'
// own decoration at step 3, the non-positioned floats at step 4, and
// the inline-level content at step 5 -- so a float paints over a block
// written after it, and inline content paints over both.
//
// Chromium's row 60 of the fixture below, read with
// `tests/chromium.py pixels` at 300x300 and every rectangle checked
// with `getBoundingClientRect` first (todo.md):
//
//   0-19 blue (the float)      20-79 green (the inline-block)
//   80-99 blue                 100-299 red (the block written after it)

color red = '#ff0000'

text floatOrderBody = '<div id="f"></div><div id="r"></div>'
    + '<div id="w"><span id="i"></span></div>'
Page pfo = pageFromHtml('<!doctype html><head><style>'
    + 'body{margin:0;width:300px}'
    + '#f{float:left;width:100px;height:100px;background:#0088ff}'
    + '#r{height:100px;background:#ff0000}'
    + '#w{margin-top:-60px}'
    + '#i{display:inline-block;width:60px;height:60px;background:#00ff00;'
    + 'margin-left:-80px}'
    + '</style><body>' + floatOrderBody + '</body>', 'test.html', 400)
clearCanvas()
paintPage(pfo, 0, 0, 400)
check(getPixelColor(10, 60) == blue, 'a float paints over a block written after it')
check(getPixelColor(90, 60) == blue, 'on the far side of the float as well')
check(getPixelColor(50, 60) == green, 'and under the in-flow inline content')
check(getPixelColor(150, 60) == red, 'the block shows where nothing covers it')

// What a pixel says is on top and what a click lands on are two ways of
// saying the same thing, and this change moves both -- so they are
// asked of the same four points rather than each against a number.
Box hitFloat = hitTest(pfo.root, 10, 60)
check(hitFloat != null && getAttr(hitFloat.node, 'id') == 'f',
      'the click at 10,60 lands where the pixel is the float')
Box hitFloatFar = hitTest(pfo.root, 90, 60)
check(hitFloatFar != null && getAttr(hitFloatFar.node, 'id') == 'f',
      'and at 90,60 the same way')
Box hitInline = hitTest(pfo.root, 50, 60)
check(hitInline != null && getAttr(hitInline.node, 'id') == 'i',
      'the click at 50,60 lands where the pixel is the inline-block')
// Away from the float the two part company, and Chromium says they
// should: at 150,60 the pixel is the earlier block's red because the
// later block has no background, while `elementFromPoint` names the
// later block -- hit testing is about the box, not the ink in it. At
// 150,20 only the earlier block is there and both name it.
Box hitLater = hitTest(pfo.root, 150, 60)
check(hitLater != null && getAttr(hitLater.node, 'id') == 'w',
      'a later in-flow block takes the click where it has no ink')
Box hitBlock = hitTest(pfo.root, 150, 20)
check(hitBlock != null && getAttr(hitBlock.node, 'id') == 'r',
      'and at 150,20 the block below it does')

// It is not only about floats. A 100x60 inline-block and a block after
// it pulled over it by a negative margin, no float anywhere: Chromium
// gives green 0-99 and red 100-299 at row 30.
Page pio = pageFromHtml('<!doctype html><head><style>'
    + 'body{margin:0;width:300px;line-height:0}'
    + '#i{display:inline-block;width:100px;height:60px;background:#00ff00}'
    + '#r{height:100px;background:#ff0000;margin-top:-40px}'
    + '</style><body><div id="wr"><span id="i"></span></div>'
    + '<div id="r"></div></body>',
    'test.html', 400)
clearCanvas()
paintPage(pio, 0, 0, 400)
check(getPixelColor(50, 30) == green, 'inline content paints over a block that overlaps it')
check(getPixelColor(150, 30) == red, 'and the block shows beside it')
Box hitOverlap = hitTest(pio.root, 50, 30)
check(hitOverlap != null && getAttr(hitOverlap.node, 'id') == 'i',
      'the click agrees with the pixel there too')
Box hitBeside = hitTest(pio.root, 150, 30)
check(hitBeside != null && getAttr(hitBeside.node, 'id') == 'r',
      'and beside it')
Box hitAbove = hitTest(pio.root, 150, 10)
check(hitAbove != null && getAttr(hitAbove.node, 'id') == 'wr',
      'and above it the wrapper the inline content sits in')


// ---- §9.9's outlines ---------------------------------------------------
//
// An outline is drawn after everything else in its stacking context's
// in-flow content and before the positioned descendants. Chromium's
// answers for a 200x60 blue box with `outline: 6px solid red`, against
// something laid over the band the outline occupies (todo.md):
//
//   an in-flow block written after it   the outline
//   a float                             the outline
//   an inline-block pulled over it      the outline
//   an absolutely positioned box        the positioned box

Page func outlinePage(body:text, extra:text) {
    return pageFromHtml('<!doctype html><head><style>'
        + 'body{margin:0;width:300px}'
        + '#a{width:200px;height:60px;background:#0088ff;'
        + 'outline:6px solid #ff0000}'
        + '#t{line-height:0}'
        + '#i{display:inline-block;width:200px;height:20px;background:#ff00ff}'
        + '#f{float:left;width:100px;height:100px;background:#00ff00}'
        + '#p{position:absolute;left:0;top:56px;width:200px;height:40px;'
        + 'background:#00ff00}'
        + extra
        + '</style><body>' + body + '</body>', 'test.html', 400)
}

// A block written after it, whose background reaches the outline's band.
Page poBlock = outlinePage('<div id="a"></div><div id="b"></div>',
    '#b{width:200px;height:60px;background:#00ff00}')
clearCanvas()
paintPage(poBlock, 0, 0, 400)
check(getPixelColor(100, 62) == red, 'an outline paints over a block written after it')

// An inline-block on the line below, reaching up into the band.
Page poInline = outlinePage('<div id="a"></div><div id="t"><span id="i"></span></div>', '')
clearCanvas()
paintPage(poInline, 0, 0, 400)
check(getPixelColor(100, 62) == red, 'and over the in-flow inline content')

// A float beside it, and a spacer to put the outlined box's top edge
// twenty pixels down so the outline's band crosses the float. The
// spacer is a box rather than a `margin-top`, because a margin that
// collapses all the way through to the root is dropped here and moves
// the document down in Chromium -- a divergence of its own, and one
// this fixture must not be asking about.
Page poFloat = outlinePage(
    '<div id="f"></div><div id="s"></div><div id="a"></div>',
    '#s{height:20px}')
clearCanvas()
paintPage(poFloat, 0, 0, 400)
check(getPixelColor(50, 16) == red, 'and over a float')
check(getPixelColor(50, 40) == green, 'while the float still covers the box itself')

// And under a positioned box, which is the row that says the outline is
// a pass between step 5 and step 8 rather than the last thing of all.
Page poPos = outlinePage('<div id="a"></div><div id="p"></div>',
    'body{position:relative}')
clearCanvas()
paintPage(poPos, 0, 0, 400)
check(getPixelColor(100, 62) == green, 'a positioned box paints over an outline')
check(getPixelColor(202, 62) == red, 'which still shows where the positioned box does not reach')


// A float's own outline is not hoisted into that pass: it travels with
// the float, at step 4, so in-flow inline content pulled over it covers
// it. Chromium draws the inline-block across 0-199 on both the float's
// rows and its outline's band, which is what says the outline pass is
// over the in-flow content rather than over everything (todo.md).
Page poFloatOwn = pageFromHtml('<!doctype html><head><style>'
    + 'body{margin:0;width:300px}'
    + '#f{float:left;width:100px;height:60px;background:#0088ff;'
    + 'outline:6px solid #ff0000}'
    + '#s{height:40px}#t{line-height:0}'
    + '#i{display:inline-block;width:200px;height:40px;background:#ff00ff;'
    + 'margin-left:-100px}'
    + '</style><body><div id="f"></div><div id="s"></div>'
    + '<div id="t"><span id="i"></span></div></body>', 'test.html', 400)
clearCanvas()
paintPage(poFloatOwn, 0, 0, 400)
check(getPixelColor(50, 45) == magenta, 'inline content covers a float it is pulled over')
check(getPixelColor(50, 62) == magenta, "and covers that float's own outline with it")


// ---- will-change (CSS Will Change 1) -----------------------------------
// A `will-change` naming a property that WOULD create a stacking
// context creates one before the property is ever set. Chromium's
// seventeen names are in todo.md; the checks here are the agreement
// that says so without a colour of its own: a `will-change` that
// qualifies must paint what `z-index: 0` paints, and one that does not
// must paint what declaring nothing paints.

shotStack('z-index:0')
color wcContext150 = getPixelColor(30, 150)
color wcContext30 = getPixelColor(30, 30)
shotStack('')
color wcPlain150 = getPixelColor(30, 150)

// The instrument: the two have to differ, or every check below holds
// on an engine that ignores the property.
check(wcContext150 != wcPlain150, 'a stacking context and no stacking context differ')

shotStack('will-change:transform')
check(getPixelColor(30, 150) == wcContext150, 'will-change: transform makes a stacking context')
check(getPixelColor(30, 30) == wcContext30, 'with the same order inside it')
shotStack('will-change:opacity')
check(getPixelColor(30, 150) == wcContext150, 'and so does will-change: opacity')
shotStack('will-change:view-transition-name')
check(getPixelColor(30, 150) == wcContext150, 'and a name this engine has no other use for')
shotStack('will-change:TRANSFORM')
check(getPixelColor(30, 150) == wcContext150, 'the names are case-insensitive')
shotStack('will-change:left, transform')
check(getPixelColor(30, 150) == wcContext150, 'and one qualifying name in a list is enough')

shotStack('will-change:left')
check(getPixelColor(30, 150) == wcPlain150, 'will-change: left makes no stacking context')
shotStack('will-change:auto')
check(getPixelColor(30, 150) == wcPlain150, 'nor does the initial value')
shotStack('will-change:color, width')
check(getPixelColor(30, 150) == wcPlain150, 'nor a list of names that do not qualify')

// ---- view-transition-name ----------------------------------------------
// The transition itself needs a clock, which nothing here has. What it
// does statically is create a stacking context, measured in Chromium
// against the same fixture as `will-change`'s (todo.md), and that this
// engine has.
shotStack('view-transition-name:hero')
check(getPixelColor(30, 150) == wcContext150,
      'view-transition-name creates a stacking context')
check(getPixelColor(30, 30) == wcContext30, 'with the same order inside it')

// `none` is the initial value and asks for nothing, which is the check
// that says the name rather than the property is what counts.
shotStack('view-transition-name:none')
check(getPixelColor(30, 150) == wcPlain150, 'and none does not')

finish('stacking')
