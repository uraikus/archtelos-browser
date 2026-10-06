// `scroll-behavior` (CSSOM View): a scroll the page asks for -- here a
// click on a link to a fragment -- takes time where the root element says
// `smooth`. Every number below is what Chromium answered, from
// `tests/chromium.py sample`, which reads window.scrollY once a frame in a
// live headless browser:
//
//   distance   arrives   position at 100, 200, 300, 400 ms (1000px only)
//   100        165 ms
//   250        265 ms
//   500        375 ms
//   1000       520 ms    73, 300, 618, 880
//   2000       695 ms
//   10000      700 ms
//
// The curve is cubic-bezier(.42, 0, .58, 1) over that duration. A page
// takes its answer from the ROOT element: `scroll-behavior` on the body
// alone left Chromium's viewport scrolling instantly, and it does not
// inherit.

import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

Style func rootStyleOf(css:text) {
    cascadeReset()
    Node doc = parseHtmlText(`<html><head><style>${css}</style></head><body><p id="p">x</p></body></html>`)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return findElement(doc, 'html').style
}

Style func elementStyleOf(css:text, tag:text) {
    cascadeReset()
    Node doc = parseHtmlText(`<html><head><style>${css}</style></head><body><p id="p">x</p></body></html>`)
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return findElement(doc, tag).style
}

check(!smoothScrollOf(rootStyleOf('')), 'a document that says nothing scrolls instantly')
check(smoothScrollOf(rootStyleOf('html{scroll-behavior:smooth}')), '`smooth` on the root element')
check(!smoothScrollOf(rootStyleOf('html{scroll-behavior:auto}')), '`auto` is instant')
check(!smoothScrollOf(rootStyleOf('body{scroll-behavior:smooth}')), 'on the body alone the root is still instant')
check(smoothScrollOf(elementStyleOf('body{scroll-behavior:smooth}', 'body')), 'and the body itself is smooth')
check(!smoothScrollOf(elementStyleOf('html{scroll-behavior:smooth}', 'p')), 'it does not inherit')
check(smoothScrollOf(rootStyleOf('html{scroll-behavior:auto}html{scroll-behavior:smooth}')), 'the last declaration wins')

// The time a scroll takes grows with the distance and stops growing at 700.
checkNear(smoothScrollDuration(100), 165, 8, 'a 100px scroll takes 165 ms')
checkNear(smoothScrollDuration(250), 265, 8, '250px: 265 ms')
checkNear(smoothScrollDuration(500), 375, 8, '500px: 375 ms')
checkNear(smoothScrollDuration(1000), 520, 8, '1000px: 520 ms')
checkNear(smoothScrollDuration(2000), 695, 8, '2000px: 695 ms')
checkNear(smoothScrollDuration(10000), 700, 1, '10000px: the 700 ms ceiling')
checkNear(smoothScrollDuration(-1000), smoothScrollDuration(1000), 0, 'a scroll upward takes as long as one downward')

// The position along 1000 pixels, against the frames Chromium drew.
checkNear(smoothScrollAt(0, 1000, 100.0), 73, 8, 'at 100 ms: 73px')
checkNear(smoothScrollAt(0, 1000, 200.0), 300, 8, 'at 200 ms: 300px')
checkNear(smoothScrollAt(0, 1000, 300.0), 618, 8, 'at 300 ms: 618px')
checkNear(smoothScrollAt(0, 1000, 400.0), 880, 8, 'at 400 ms: 880px')
checkEqInt(smoothScrollAt(0, 1000, 0.0), 0, 'it starts where it was')
checkEqInt(smoothScrollAt(0, 1000, 600.0), 1000, 'and ends where it was sent')
checkEqInt(smoothScrollAt(0, 1000, 5000.0), 1000, 'and stays there')
// The same path run backward.
checkNear(smoothScrollAt(1000, 0, 200.0), 700, 8, 'upward, at 200 ms: 700px')
checkEqInt(smoothScrollAt(400, 400, 100.0), 400, 'no distance, no movement')

finish('scroll behavior')
