// border-image (Backgrounds and Borders 3 §6).
//
// The source is cut into nine regions by `border-image-slice`: four
// corners drawn at the border's own size, four edges filling the space
// between them, and a middle drawn only when `fill` asks for it.
//
// tests/fixtures/nine.png is nine 3x3 regions in CSS-named colours, so
// a slice of 3 cuts exactly those nine and each region can be named by
// the colour it must put on the box. Its top edge varies across its
// three columns -- lime, white, lime -- because a uniform edge looks
// the same stretched as repeated, and that difference is the whole of
// `border-image-repeat`.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(400)
setClientHeight(300)

color red = 'red'
color lime = 'lime'
color blue = 'blue'
color yellow = 'yellow'
color green = 'green'
color aqua = 'aqua'
color fuchsia = 'fuchsia'
color gray = 'gray'
color black = 'black'
color white = 'white'

text head = '<!doctype html><body style="margin:0">'

// A 30x30 border box with 10px borders, so each corner region is drawn
// at 10x10 and each edge fills the 10px between them.
void func shotBorderImage(style:text) {
    Page p = pageFromHtml(head + '<div style="width:10px;height:10px;'
        + 'border:10px solid transparent;background:white;' + style
        + '"></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

// ---- without a source nothing is drawn ------------------------------------

shotBorderImage('')
check(getPixelColor(2, 2) == white, 'with no border image the corner is not painted')

// ---- the nine regions land where they belong ------------------------------

shotBorderImage('border-image:url(nine.png) 3')
check(getPixelColor(2, 2) == red, 'the top-left region goes in the top-left corner')
check(getPixelColor(27, 2) == blue, 'the top-right region in the top-right corner')
check(getPixelColor(2, 27) == fuchsia, 'the bottom-left region in the bottom-left corner')
check(getPixelColor(27, 27) == black, 'the bottom-right region in the bottom-right corner')
check(getPixelColor(2, 15) == yellow, 'the left region fills the left edge')
check(getPixelColor(27, 15) == aqua, 'the right region fills the right edge')
check(getPixelColor(15, 27) == gray, 'the bottom region fills the bottom edge')

// The middle is not drawn unless `fill` asks, so the box's own
// background shows through.
check(getPixelColor(15, 15) == white, 'the middle region is left out')
shotBorderImage('border-image:url(nine.png) 3 fill')
check(getPixelColor(15, 15) == green, 'and drawn when `fill` asks for it')

// ---- the slice can be a percentage ----------------------------------------
// A third of a 9px source is 3px, so these two must agree.

shotBorderImage('border-image:url(nine.png) 33.333%')
check(getPixelColor(2, 2) == red, 'a percentage slice cuts the same corner')
check(getPixelColor(27, 27) == black, 'and the same opposite corner')

// ---- border-image-repeat, and the scaling it tiles into (§6.5) ----------
// Each edge image is scaled to the thickness of the border it is drawn
// in before any tiling happens: the top edge's height becomes the top
// border width, and its width is scaled by the same factor. A 3px slice
// in a 30px border is therefore a 30x30 tile, and the four keywords
// differ only in how those tiles fill the edge -- `stretch` with one
// tile pulled across it, `repeat` with whole tiles centred on it and cut
// by its two ends, `round` with the tile resized until a whole number
// fits, `space` with whole tiles and the leftover shared out around
// them.
//
// What is checked is where the tiling repeats and where it leaves the
// box's own background showing. Those are the standard's own statements
// and they survive the two engines filtering a scaled blit differently,
// which they do: Chromium leaves runs of the source's lime untouched
// where this engine's blit blends almost every pixel of them, so a
// check that named a colour at a position would be measuring the filter.
//
// Chromium 141 on a box with 30px borders, read with `tests/chromium.py
// pixels`, puts the source's lime runs and its pale middle column here.
// The edge starts at x = 30, and the tile is 30 wide:
//
//   edge 30, repeat  lime 30-34, pale 44-45, lime 55-59
//                    one tile, which is the whole edge
//   edge 60, repeat  lime 40-49, pale 59-60, lime 70-79
//                    a tile centred on the edge, half a tile at each end
//   edge 60, round   pale 44-45 and 74-75
//                    two tiles, laid from the edge's start
//   edge 75, repeat  lime 48-56 and 78-86
//                    tile boundaries at 52.5 and 82.5 -- centred again
//   edge 75, round   pale at 42, 67 and 92 -- three tiles of 25
//   edge 75, space   background 30-34, 65-69 and 100-104 -- two 30px
//                    tiles, with the 15px left over split three ways

color back = '#123456'

// A box whose top edge is `edge` pixels long. The borders are 30px, so
// each edge image is drawn 30px thick and the top edge occupies
// x in [30, 30 + edge) at every y in [0, 30).
void func shotEdgeStyle(edge:int, style:text) {
    Page p = pageFromHtml(head + '<div style="width:' + edge.toText() + 'px;height:10px;'
        + 'border:30px solid transparent;background:#123456;' + style
        + '"></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

void func shotEdge(edge:int, keyword:text) {
    shotEdgeStyle(edge, 'border-image:url(nine.png) 3 ' + keyword)
}

// The pixels of the top edge, so two renders can be compared with each
// other rather than each against a colour.
arr[color] func edgeRow(edge:int) {
    arr[color] out = []
    for int x = 30, x < 30 + edge, x++ { out.push(getPixelColor(x, 10)) }
    return out
}

bool func sameRow(a:arr[color], b:arr[color]) {
    if a.length != b.length { return false }
    for int i = 0, i < a.length, i++ {
        if a[i] != b[i] { return false }
    }
    return true
}

// `a` is `b` slid along by `shift`, wrapping round. Where an edge holds
// a whole number of identical tiles, two tilings that differ only in
// where they start are exactly this.
bool func sameRotated(a:arr[color], b:arr[color], shift:int) {
    if a.length != b.length || a.length == 0 { return false }
    for int i = 0, i < a.length, i++ {
        if a[i] != b[(i + shift) % b.length] { return false }
    }
    return true
}

// How often the row repeats itself: the smallest distance at which
// every pixel equals the pixel that far along, or 0 where there is
// none. A tiling's period is the tile's own width, whatever the filter
// did to the pixels inside it, so this is what says how wide the tiles
// this engine laid down are.
//
// Only distances up to half the row count, because a longer one is
// tested against too little of the row to mean anything: a row that
// ends and begins with the same few pixels would otherwise report a
// period of nearly its whole length.
int func rowPeriod(a:arr[color]) {
    for int p = 1, p <= Math.floorDiv(a.length, 2), p++ {
        bool ok = true
        for int i = 0, i + p < a.length, i++ {
            if a[i] != a[i + p] { ok = false  break }
        }
        if ok { return p }
    }
    return 0
}

bool func runIs(a:arr[color], from:int, to:int, c:color) {
    for int i = from, i <= to, i++ {
        if i < 0 || i >= a.length || a[i] != c { return false }
    }
    return true
}

// An edge as long as the border is thick holds exactly one scaled tile,
// so the three tiling keywords have nothing to differ about -- and the
// edge does not repeat within itself, which a region tiled at its own
// 3px size would do ten times over.
shotEdge(30, 'repeat')
arr[color] row30 = edgeRow(30)
checkEqInt(rowPeriod(row30), 0, 'a 30px edge holds one 30px tile, not ten 3px ones')
shotEdge(30, 'round')
check(sameRow(edgeRow(30), row30),
      '`repeat` and `round` agree where one scaled tile fills the edge')
shotEdge(30, 'space')
check(sameRow(edgeRow(30), row30), 'and `space` agrees with them there')
shotEdge(30, 'stretch')
check(sameRow(edgeRow(30), row30), 'and so does `stretch`, which is the same one tile')

// Twice as long: two whole tiles. `round` and `space` lay them from the
// edge's start; `repeat` centres the tiling instead, which puts a tile
// boundary at the middle of the edge and half a tile at each end -- the
// same tiling slid along by half a tile.
shotEdge(60, 'round')
arr[color] rowRound60 = edgeRow(60)
checkEqInt(rowPeriod(rowRound60), 30, 'two 30px tiles across a 60px edge')
shotEdge(60, 'space')
check(sameRow(edgeRow(60), rowRound60),
      '`space` and `round` agree where whole tiles fill the edge exactly')
shotEdge(60, 'repeat')
arr[color] rowRepeat60 = edgeRow(60)
checkEqInt(rowPeriod(rowRepeat60), 30, '`repeat` lays down the same 30px tile')
check(!sameRow(rowRepeat60, rowRound60), 'but not in the same place')
check(sameRotated(rowRepeat60, rowRound60, 15),
      'because it centres the tiling, which slides it half a tile along')

// Two tiles and a half. `repeat` cuts the two ends, `round` shrinks the
// tile until three fit, `space` lays two whole ones and shares the
// fifteen pixels left over into three gaps.
shotEdge(75, 'repeat')
arr[color] rowRepeat75 = edgeRow(75)
checkEqInt(rowPeriod(rowRepeat75), 30, '`repeat` keeps the tile at 30px and cuts the ends')
shotEdge(75, 'round')
arr[color] rowRound75 = edgeRow(75)
checkEqInt(rowPeriod(rowRound75), 25, '`round` resizes it so three tiles fit exactly')
check(!sameRow(rowRepeat75, rowRound75), 'which is not the tiling `repeat` laid down')

shotEdge(75, 'space')
arr[color] rowSpace75 = edgeRow(75)
check(runIs(rowSpace75, 0, 4, back), '`space` starts the edge with a gap')
check(runIs(rowSpace75, 35, 39, back), 'puts one between the two tiles')
check(runIs(rowSpace75, 70, 74, back), 'and ends with one')
check(rowSpace75[5] != back, 'with a whole tile after the first gap')
check(rowSpace75[69] != back, 'and another before the last')
bool tilesAlike = true
for int i = 0, i < 30, i++ {
    if rowSpace75[5 + i] != rowSpace75[40 + i] { tilesAlike = false }
}
check(tilesAlike, 'the two of them the same tile, 35 pixels apart')

// An edge narrower than one tile.
shotEdge(15, 'space')
arr[color] rowSpace15 = edgeRow(15)
check(runIs(rowSpace15, 0, 14, back), '`space` draws nothing where no whole tile fits')
shotEdge(15, 'round')
arr[color] rowRound15 = edgeRow(15)
check(!runIs(rowRound15, 0, 14, back), '`round` fits one tile to the whole edge')
checkEqInt(rowPeriod(rowRound15), 0, 'which is one tile, so it does not repeat')

// A stretched edge is one tile pulled across it however long it is,
// which is the one keyword that never repeats anything.
shotEdge(75, 'stretch')
arr[color] rowStretch75 = edgeRow(75)
checkEqInt(rowPeriod(rowStretch75), 0, '`stretch` never repeats, however long the edge')
check(!sameRow(rowStretch75, rowRepeat75), 'and is not what `repeat` paints')

// ---- border-image-width ---------------------------------------------------
// The width of the drawn border image, which is the border's own width
// by default and can differ from it.

// A 3x3 corner region scaled into 4x4 is filtered at every pixel, so
// the check asks that the corner is painted at all rather than that it
// is the exact colour -- which it can only be where the scale is large
// enough to leave an unblended interior.
shotBorderImage('border-image:url(nine.png) 3 / 4px')
check(getPixelColor(1, 1) != white, 'a narrower border-image-width still draws the corner')
check(getPixelColor(6, 6) == white, 'but only as far as it was asked to')

shotBorderImage('border-image:url(nine.png) 3')
check(getPixelColor(6, 6) == red, 'where the default width reaches the whole border')

// ---- border-image-outset --------------------------------------------------
// The outset pushes the image beyond the border box, into space the box
// does not occupy.

// The wrapper is padded rather than the box margined, because a top
// margin here collapses through to the root and is dropped, which would
// put the box somewhere other than where the check expects.
void func shotInset(style:text) {
    Page p = pageFromHtml(head + '<div style="padding:10px"><div style="width:10px;'
        + 'height:10px;border:10px solid transparent;background:white;' + style
        + '"></div></div></body>', 'tests/fixtures/page.html', 400)
    clearCanvas()
    paintPage(p, 0, 0, 300)
}

shotInset('border-image:url(nine.png) 3')
check(getPixelColor(12, 12) == red, 'without an outset the image starts at the border box')
check(getPixelColor(7, 7) == white, 'and nothing is painted outside it')
shotInset('border-image:url(nine.png) 3;border-image-outset:5px')
check(getPixelColor(7, 7) != white, 'an outset pushes it outside the border box')

// ---- the longhands say what the shorthand says ----------------------------

shotEdge(75, 'repeat')
arr[color] rowShorthand = edgeRow(75)
shotEdgeStyle(75, 'border-image-source:url(nine.png);border-image-slice:3;'
    + 'border-image-repeat:repeat')
check(sameRow(edgeRow(75), rowShorthand),
      'the border-image longhands draw what the shorthand draws')
check(getPixelColor(2, 2) == red, 'corners included')

finish('border image')
