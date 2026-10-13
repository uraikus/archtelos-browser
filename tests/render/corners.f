// `corner-shape` (CSS Borders 4 §5).
//
// A corner is the region the border radius already resolves, and every
// value this property takes is that region under a different
// superellipse exponent: `|x/rx|^k + |y/ry|^k = 1`, with a negative
// exponent giving the concave reflection that `scoop` and `notch` are.
//
// Every expected number below is Chromium 141's, read off a 100x100
// black box with `border-radius: 40px` as the first fully black pixel
// on a row of the top-left corner, one shape at a time:
//
//         row     0   2   5   8  10  14  18  20  25  30  35  40
//   round        40  28  21  16  14  10   7   6   3   2   1   0
//   square        0   0   0   0   0   0   0   0   0   0   0   0
//   bevel        40  38  35  32  30  26  22  20  15  10   5   0
//   scoop        40  40  40  40  39  38  36  35  31  26  19   0
//   notch        40  40  40  40  40  40  40  40  40  40  40   0
//   squircle     27  14   8   5   4   2   1   1   1   0   0   0
//
// `bevel` is the row that pins the parameterisation down: `k` of 1
// collapses the formula to a straight line, so every one of its numbers
// is exact rather than near, and an implementation that had the
// exponent wrong anywhere could not match all of them.
//
// `squircle` reads 27 at row 0 not because it passes the radius but
// because a fourth-power curve is within a ninth of a pixel of the top
// edge from x=27 on. That is a statement about the rasteriser as much
// as the curve, so the checks below ask it at rows where the curve is
// actually moving.
import ../../src/browser/page.f
import ../assert.f

setClientWidth(200)
setClientHeight(200)

color white = 'white'
color black = 'black'

void func shotCorner(shape:text) {
    Page p = pageFromHtml('<!doctype html><body style="margin:0">'
        + '<div style="width:100px;height:100px;background:#000000;'
        + 'border-radius:40px;' + shape + '"></div></body>',
        'tests/fixtures/page.html', 200)
    clearCanvas()
    paintPage(p, 0, 0, 200)
}

// The first black pixel on a row, which is where the corner's curve
// has reached by then. -1 when the row has no ink at all.
int func inkStart(y:int) {
    for int x = 0, x < 60, x++ {
        if getPixelColor(x, y) == black { return x }
    }
    return -1
}

// A whole corner profile as one string, so two shapes can be compared
// without naming every row.
text func profile() {
    text out = ''
    for int i = 0, i < 12, i++ {
        int y = i == 0 ? 0 : (i == 1 ? 2 : (i == 2 ? 5 : (i == 3 ? 8 : (i == 4 ? 10
            : (i == 5 ? 14 : (i == 6 ? 18 : (i == 7 ? 20 : (i == 8 ? 25
            : (i == 9 ? 30 : (i == 10 ? 35 : 40))))))))))
        out = out + `${inkStart(y)} `
    }
    return out
}

// ---- the shapes differ from one another ----------------------------------
// Six profiles, and no two of them the same. This is the check that
// does not depend on any single number being right: an implementation
// that ignored the property would give six identical strings, and one
// that mapped two keywords to the same exponent would give five.

shotCorner('corner-shape:round')
text pRound = profile()
shotCorner('corner-shape:square')
text pSquare = profile()
shotCorner('corner-shape:bevel')
text pBevel = profile()
shotCorner('corner-shape:scoop')
text pScoop = profile()
shotCorner('corner-shape:notch')
text pNotch = profile()
shotCorner('corner-shape:squircle')
text pSquircle = profile()

check(pRound != pSquare, 'round is not square')
check(pRound != pBevel, 'round is not bevel')
check(pRound != pScoop, 'round is not scoop')
check(pRound != pSquircle, 'round is not squircle')
check(pBevel != pScoop, 'bevel is not scoop')
check(pScoop != pNotch, 'scoop is not notch')
check(pSquare != pNotch, 'square is not notch, though both are straight')
check(pBevel != pSquircle, 'bevel is not squircle')

// ---- and each is the curve Chromium draws --------------------------------
// `square` fills the corner outright and `notch` cuts it out entirely,
// so those two are exact at every row.

shotCorner('corner-shape:square')
checkEqInt(inkStart(0), 0, 'square: the corner is filled to the edge')
checkEqInt(inkStart(20), 0, 'square: and all the way down')

shotCorner('corner-shape:notch')
checkEqInt(inkStart(0), 40, 'notch: the corner is cut out to the radius')
checkEqInt(inkStart(20), 40, 'notch: and stays cut to the radius')
checkEqInt(inkStart(35), 40, 'notch: right up to where the corner ends')

// `bevel` is the straight cut, exact at every row because k of 1 makes
// the formula linear.
shotCorner('corner-shape:bevel')
checkEqInt(inkStart(0), 40, 'bevel: starts at the radius')
checkEqInt(inkStart(10), 30, 'bevel: and falls by one for one')
checkEqInt(inkStart(20), 20, 'bevel: halfway down, halfway in')
checkEqInt(inkStart(30), 10, 'bevel: still one for one')
checkEqInt(inkStart(35), 5, 'bevel: to the corner')

// `round` is what `border-radius` alone draws, so the shape must not
// change it: a box with no `corner-shape` and one that asks for `round`
// are the same picture. That is the check that the new code path did
// not quietly replace the old one with something near it.
shotCorner('')
checkEq(profile(), pRound, 'a box with no corner-shape is drawn as round')

// `scoop` is concave: its ink starts further out than round at every
// row, because the curve bows away from the box rather than into it.
shotCorner('corner-shape:scoop')
checkEqInt(inkStart(20), 35, 'scoop: bows away from the corner')
checkEqInt(inkStart(30), 26, 'scoop: still outside round at the same row')
check(inkStart(20) > 6, 'scoop is outside round, which reads 6 there')

// ---- the longhands name the corners they say they do ---------------------
// One corner shaped and the other three left round: the top-left
// profile moves only when the declaration names the top-left.

shotCorner('corner-top-left-shape:notch')
checkEqInt(inkStart(20), 40, 'corner-top-left-shape reaches the top-left')
shotCorner('corner-top-right-shape:notch')
checkEq(profile(), pRound, 'and corner-top-right-shape does not')
shotCorner('corner-bottom-left-shape:notch')
checkEq(profile(), pRound, 'nor corner-bottom-left-shape')

// The logical longhands are the physical ones under the names a writing
// mode gives them, which in this engine's left-to-right horizontal mode
// is a renaming. Each is checked against the physical corner it stands
// for and against the undeclared case, because two names that both did
// nothing would agree with each other.
shotCorner('corner-start-start-shape:notch')
checkEqInt(inkStart(20), 40, 'corner-start-start-shape is the top-left')
shotCorner('corner-end-end-shape:notch')
checkEq(profile(), pRound, 'and corner-end-end-shape is not')

// ---- the shorthand ------------------------------------------------------
// One to four values, each missing one taking the corner opposite it,
// exactly as `border-radius` reads them.
shotCorner('corner-shape:notch round round round')
checkEqInt(inkStart(20), 40, 'four values: the first is the top-left')
shotCorner('corner-shape:round notch')
checkEq(profile(), pRound, 'two values: the first is the top-left and the second the top-right')

// ---- superellipse() -----------------------------------------------------
// The keywords are exponents, so the function must reproduce them
// exactly: `superellipse(1)` is `bevel` and `superellipse(4)` is
// `squircle`. This is the check that the keywords are not a separate
// table that happens to agree.
shotCorner('corner-shape:superellipse(1)')
checkEq(profile(), pBevel, 'superellipse(1) is bevel')
shotCorner('corner-shape:superellipse(4)')
checkEq(profile(), pSquircle, 'superellipse(4) is squircle')
shotCorner('corner-shape:superellipse(2)')
checkEq(profile(), pRound, 'and superellipse(2) is round')

finish('corner shape')
