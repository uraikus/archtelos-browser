// CSS Scroll Snap 1.
//
// A scroll container with `scroll-snap-type` does not come to rest
// wherever a scroll left it: it lands on one of the positions its
// children's `scroll-snap-align` declares. A snap position is one
// subtraction -- the child's edge less the snapport's, per alignment --
// with `scroll-padding` insetting the snapport and `scroll-margin`
// outsetting the child's snap area.
//
// Every number below is Chromium 141's, read off six 30px children in a
// 100px snapport whose `start` positions are 0, 30, 60 and a maximum of
// 80, by setting `scrollTop` on a container of its own for each case --
// a second assignment to one element reads back before its snap:
//
//   start   0->0  5->0  14->0  16->30  35->30  44->30  46->60  75->80  200->80
//   center  0->0  5->0  14->25 16->25  35->25  44->55  46->55  75->80  200->80
//   end     0->0  5->0  14->20 16->20  35->20  44->50  46->50  75->80  200->80
//
// `end` at 35 is the tie -- 20 and 50 are both fifteen away -- and
// Chromium takes the lower.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

Box func snapBoxById(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && attrOf(b.node.id, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = snapBoxById(b.children[i], id)
        if f != null { return f }
    }
    return null
}

// A 200x100 scroll container of `n` children `h` tall, and where a
// scroll of `want` from the top comes to rest. `overflow-x: hidden`
// keeps the horizontal bar off, so the snapport is the full 100.
int func snapTo(container:text, child:text, n:int, h:int, want:int) {
    cascadeReset()
    cssViewportWidth = 600
    text kids = ''
    for int i = 0, i < n, i++ {
        kids = kids + `<div style="height:${h}px;${child}">x</div>`
    }
    Node doc = parseHtmlText('<html><body style="margin:0"><div id="s" style="width:200px;'
        + 'height:100px;overflow-y:scroll;overflow-x:hidden;' + container + '">'
        + kids + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box root = layoutDocument(doc, 600)
    Box s = snapBoxById(root, 's')
    // A box tree lasts one layout and a scroll offset outlives several,
    // so the offset is cleared before each case rather than assumed.
    boxScrollBy(s, 0 - 10000)
    boxScrollBy(s, want)
    return boxScrollTop(s)
}

text Y_MAND = 'scroll-snap-type:y mandatory'

// ---- the three alignments ----------------------------------------------
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 0), 0, 'start: 0 stays')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 5), 0, 'start: 5 falls back')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 14), 0, 'start: 14 is nearer 0')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 16), 30, 'start: 16 is nearer 30')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 35), 30, 'start: 35 holds at 30')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 44), 30, 'start: 44 is still nearer 30')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 46), 60, 'start: 46 crosses to 60')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 75), 80, 'start: 75 takes the last')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 200), 80, 'start: past the end is the end')

checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:center', 6, 30, 5), 0, 'center: 5 falls back')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:center', 6, 30, 14), 25, 'center: 14 reaches 25')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:center', 6, 30, 35), 25, 'center: 35 holds at 25')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:center', 6, 30, 44), 55, 'center: 44 crosses to 55')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:center', 6, 30, 75), 80, 'center: 75 takes the last')

checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:end', 6, 30, 5), 0, 'end: 5 falls back')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:end', 6, 30, 14), 20, 'end: 14 reaches 20')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:end', 6, 30, 35), 20, 'end: a tie takes the lower')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:end', 6, 30, 44), 50, 'end: 44 crosses to 50')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:end', 6, 30, 75), 80, 'end: 75 takes the last')

// The three have to differ from one another, or an implementation that
// answered `start` to everything would pass a third of the checks above.
check(snapTo(Y_MAND, 'scroll-snap-align:center', 6, 30, 14)
      != snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 14), 'center is not start')
check(snapTo(Y_MAND, 'scroll-snap-align:end', 6, 30, 14)
      != snapTo(Y_MAND, 'scroll-snap-align:center', 6, 30, 14), 'and end is not center')

// ---- nothing to snap to -------------------------------------------------
// A container that asks for snapping whose children do not answer is a
// container that does not snap, which is what keeps the property off
// every ordinary scroll.
checkEqInt(snapTo(Y_MAND, '', 6, 30, 46), 46, 'a child with no align is not a snap point')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:none', 6, 30, 46), 46, 'and `none` is not one either')
checkEqInt(snapTo('', 'scroll-snap-align:start', 6, 30, 46), 46, 'nor is a container that never asked')
checkEqInt(snapTo('scroll-snap-type:none', 'scroll-snap-align:start', 6, 30, 46), 46,
           'nor one that asked for none')

// The axis is the one named: a container snapping across does not snap
// what is scrolled down it.
checkEqInt(snapTo('scroll-snap-type:x mandatory', 'scroll-snap-align:start', 6, 30, 46), 46,
           'an x container does not snap the y axis')
checkEqInt(snapTo('scroll-snap-type:both mandatory', 'scroll-snap-align:start', 6, 30, 46), 60,
           'and `both` snaps it')
checkEqInt(snapTo('scroll-snap-type:block mandatory', 'scroll-snap-align:start', 6, 30, 46), 60,
           'as does `block`, which is the y axis here')

// ---- proximity ----------------------------------------------------------
// `proximity` snaps only when a position is near enough, and near enough
// is one third of the snapport -- not a fixed distance. Chromium snaps
// to 0 from 32 and not from 34 in a 100px snapport, and from 66 and not
// 68 in a 200px one, with the next position 500 away.
text FAR = 'scroll-snap-type:y proximity'
checkEqInt(snapTo(FAR, 'scroll-snap-align:start', 6, 30, 5), 0, 'proximity snaps what is near')
checkEqInt(snapTo(FAR, 'scroll-snap-align:start', 6, 30, 16), 30, 'and to the nearer of two')
// With the snap points 30 apart, everything is inside a third of 100, so
// `proximity` and `mandatory` agree -- which is what Chromium does, and
// why the threshold needed a fixture whose points are far apart.
checkEqInt(snapTo(FAR, 'scroll-snap-align:start', 6, 30, 44),
           snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 44),
           'and agrees with mandatory where every point is near')

// ---- scroll-padding and scroll-margin ------------------------------------
// `scroll-padding` insets the snapport, so a `start` position moves up
// by the inset: the child's edge now aligns with the padded edge.
checkEqInt(snapTo('scroll-snap-type:y mandatory;scroll-padding-top:10px',
                  'scroll-snap-align:start', 6, 30, 46), 50,
           'scroll-padding-top moves a start position up by its inset')
checkEqInt(snapTo('scroll-snap-type:y mandatory;scroll-padding:10px',
                  'scroll-snap-align:start', 6, 30, 46), 50,
           'and the shorthand sets it the same way')

// `scroll-margin` outsets the child's snap area, which moves a `start`
// position the other way.
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start;scroll-margin-top:10px', 6, 30, 46), 50,
           'scroll-margin-top moves it too')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start;scroll-margin:10px', 6, 30, 46), 50,
           'and its shorthand as well')

// ---- the logical longhands ----------------------------------------------
// `scroll-padding-block-start` and its seven siblings are the physical
// eight under the names a writing mode gives them, which in the
// left-to-right horizontal mode this engine lays out in is a renaming.
// Each is checked against the physical one it stands for, so a rename
// that went to the wrong edge would show as a different landing.
checkEqInt(snapTo('scroll-snap-type:y mandatory;scroll-padding-block-start:10px',
                  'scroll-snap-align:start', 6, 30, 46),
           snapTo('scroll-snap-type:y mandatory;scroll-padding-top:10px',
                  'scroll-snap-align:start', 6, 30, 46),
           'scroll-padding-block-start is scroll-padding-top')
checkEqInt(snapTo(Y_MAND, 'scroll-snap-align:start;scroll-margin-block-start:10px', 6, 30, 46),
           snapTo(Y_MAND, 'scroll-snap-align:start;scroll-margin-top:10px', 6, 30, 46),
           'and scroll-margin-block-start is scroll-margin-top')
// Both of those would also pass if neither declaration did anything, so
// the pair has to differ from the undeclared case as well.
check(snapTo('scroll-snap-type:y mandatory;scroll-padding-block-start:10px',
             'scroll-snap-align:start', 6, 30, 46)
      != snapTo(Y_MAND, 'scroll-snap-align:start', 6, 30, 46),
      'and each of them moves the landing at all')

// ---- a snap area taller than the snapport --------------------------------
// A child that overflows the snapport is a *range* of valid positions
// rather than a point (§6.1), so a position inside it is left alone and
// one past it is pulled only as far as the child's own end. Chromium on
// four 100px children in an 85px snapport -- the bar takes fifteen --
// answers 10->10, 40->15, 60->100, 120->115, 199->200 and 400->315.
int func snapTall(want:int) {
    cascadeReset()
    cssViewportWidth = 600
    text kids = ''
    for int i = 0, i < 4, i++ { kids = kids + '<div style="height:100px;scroll-snap-align:start">x</div>' }
    Node doc = parseHtmlText('<html><body style="margin:0"><div id="s" style="width:200px;'
        + 'height:100px;overflow:scroll;scroll-snap-type:y mandatory">' + kids
        + '</div></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box s = snapBoxById(layoutDocument(doc, 600), 's')
    boxScrollBy(s, 0 - 10000)
    boxScrollBy(s, want)
    return boxScrollTop(s)
}

checkEqInt(snapTall(10), 10, 'a position inside an overflowing child is left alone')
checkEqInt(snapTall(40), 15, 'and one past it is pulled back to that child end')
checkEqInt(snapTall(60), 100, 'while one nearer the next child takes its start')
checkEqInt(snapTall(120), 115, 'the same going down')
checkEqInt(snapTall(199), 200, 'and across the boundary')
checkEqInt(snapTall(400), 315, 'with the maximum still the maximum')

finish('scroll snap')
