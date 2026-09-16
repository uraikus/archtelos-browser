// Counters (CSS2 §12.4): counter-reset, counter-increment, and the
// counter() and counters() functions inside `content`.
//
// The values below were confirmed against Chromium 141 by measuring the
// width the generated content adds to an inline-block span at 16px
// monospace, which reveals how many characters it produced:
//
//   counter-increment: sec        first span   1 char   "1"
//                                 second       1 char   "2"
//   counter-increment: sec 5      third        1 char   "7"
//   counters(item, ".") nested    outer        1 char   "1"
//                                 inner        3 chars  "1.1", "1.2"
//
// This asserts the generated text itself, which the box tree carries,
// with those widths as the corroboration that the text is right.
import ../../src/browser/page.f
import ../assert.f

// The text of the ::before box generated inside an element.
text func generatedBefore(root:Box, id:text) {
    arr[Box] all = []
    collectBoxesForTag(root, 'span', all)
    for int i = 0, i < all.length, i++ {
        Box b = all[i]
        if b.node == null || getAttr(b.node, 'id') != id { continue }
        if b.children.length == 0 { return null }
        Box first = b.children[0]
        if first.children.length == 0 { return '' }
        return first.children[0].content
    }
    return null
}

text head = '<!doctype html><body style="margin:0;font:16px/20px monospace;width:600px">'

// ---- a counter counts up -------------------------------------------
Page p1 = pageFromHtml(head + '<style>'
    + '.wrap { counter-reset: sec }'
    + '.s { display:inline-block; counter-increment: sec }'
    + '.s::before { content: counter(sec) }'
    + '.t { display:inline-block; counter-increment: sec 5 }'
    + '.t::before { content: counter(sec) }'
    + '</style>'
    + '<div class="wrap"><span class="s" id="c1">a</span><span class="s" id="c2">a</span>'
    + '<span class="t" id="c3">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p1.root, 'c1'), '1', 'the first increment makes it one')
checkEq(generatedBefore(p1.root, 'c2'), '2', 'the second makes it two')
checkEq(generatedBefore(p1.root, 'c3'), '7', 'an increment of five adds five')

// ---- counters() walks the nested instances --------------------------
Page p2 = pageFromHtml(head + '<style>'
    + '.nest { counter-reset: item }'
    + '.li { display:inline-block; counter-increment: item }'
    + '.li::before { content: counters(item, ".") }'
    + '</style>'
    + '<div class="nest"><span class="li" id="n1">a</span>'
    + '<span class="nest"><span class="li" id="n2">a</span>'
    + '<span class="li" id="n3">a</span></span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p2.root, 'n1'), '1', 'the outer counter is one')
checkEq(generatedBefore(p2.root, 'n2'), '1.1', 'a nested instance joins with the separator')
checkEq(generatedBefore(p2.root, 'n3'), '1.2', 'and counts up inside its own scope')

// ---- a counter-reset starts a scope over following siblings ---------
Page p3 = pageFromHtml(head + '<style>'
    + '.g { counter-reset: n }'
    + '.x { display:inline-block; counter-increment: n }'
    + '.x::before { content: counter(n) }'
    + '</style>'
    + '<div><span class="g"></span><span class="x" id="s1">a</span>'
    + '<span class="x" id="s2">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p3.root, 's1'), '1', 'a reset on an earlier sibling is in scope')
checkEq(generatedBefore(p3.root, 's2'), '2', 'for every following sibling')

// ---- incrementing without a reset ----------------------------------
// CSS2 §12.4.3: the counter is created on the root element, so it still
// counts rather than being absent.
Page p4 = pageFromHtml(head + '<style>'
    + '.y { display:inline-block; counter-increment: free }'
    + '.y::before { content: counter(free) }'
    + '</style>'
    + '<div><span class="y" id="f1">a</span><span class="y" id="f2">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p4.root, 'f1'), '1', 'an increment with no reset still counts')
checkEq(generatedBefore(p4.root, 'f2'), '2', 'and keeps counting')

// ---- a counter that was never touched -------------------------------
Page p5 = pageFromHtml(head + '<style>'
    + '.z { display:inline-block }'
    + '.z::before { content: counter(missing) }'
    + '</style>'
    + '<div><span class="z" id="m1">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p5.root, 'm1'), '0', 'an unknown counter reads zero')

// ---- counter text mixes with strings --------------------------------
Page p6 = pageFromHtml(head + '<style>'
    + '.w { counter-reset: k }'
    + '.v { display:inline-block; counter-increment: k }'
    + '.v::before { content: "[" counter(k) "] " }'
    + '</style>'
    + '<div class="w"><span class="v" id="mix">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p6.root, 'mix'), '[1] ', 'strings and counters concatenate')

// ---- counter-reset takes an explicit starting value -----------------
Page p7 = pageFromHtml(head + '<style>'
    + '.r { counter-reset: q 10 }'
    + '.u { display:inline-block; counter-increment: q }'
    + '.u::before { content: counter(q) }'
    + '</style>'
    + '<div class="r"><span class="u" id="r1">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(p7.root, 'r1'), '11', 'a reset to ten then incremented is eleven')

// ---- the same counting, declared two ways ---------------------------
// A counter written in a stylesheet and the same counter written in a
// `style` attribute must number identically. They did not: `anyCounters`
// -- the per-document flag that lets this feature cost nothing to the
// pages without counters -- was raised by walking the stylesheet rules
// and nothing else, so a counter that appeared only in a style
// attribute was dropped and its element numbered nothing at all.
//
// This is the check that does not depend on either answer being known:
// two ways of saying the same thing have to land on the same text.
Page p8 = pageFromHtml(head + '<style>.v { display:inline-block }'
    + '.v::before { content: counter(z) }'
    + '#w { counter-reset: z 0 } #v1 { counter-increment: z } #v2 { counter-increment: z 3 }'
    + '</style>' + '<div id="w"><span class="v" id="v1">a</span>'
    + '<span class="v" id="v2">a</span></div></body>', 'about:blank', 600)
Page p9 = pageFromHtml(head + '<style>.v { display:inline-block }'
    + '.v::before { content: counter(z) }</style>'
    + '<div style="counter-reset: z 0">'
    + '<span class="v" id="v1" style="counter-increment: z">a</span>'
    + '<span class="v" id="v2" style="counter-increment: z 3">a</span></div></body>',
    'about:blank', 600)
checkEq(generatedBefore(p9.root, 'v1'), generatedBefore(p8.root, 'v1'),
        'a counter in a style attribute counts as one in a stylesheet does')
checkEq(generatedBefore(p9.root, 'v2'), generatedBefore(p8.root, 'v2'),
        'and so does one carrying a value')
// The absolute values too, so a regression that broke both forms
// together could not pass the comparison above.
checkEq(generatedBefore(p8.root, 'v1'), '1', 'the stylesheet form numbers one')
checkEq(generatedBefore(p9.root, 'v2'), '4', 'the style-attribute form numbers four')

finish('counters')
