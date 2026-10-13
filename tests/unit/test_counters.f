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

// ---- counter-set (CSS Lists 3 §4.2) ----------------------------------
// `counter-set` sets the counter that is already in scope; it does not
// create a new instance the way `counter-reset` does. The pair below is
// the check that tells them apart and does not depend on either number
// being known in advance: the same markup with `counter-set` and with
// `counter-reset` on the inner element must disagree on what the
// element *after* it counts, because a reset's instance dies with the
// element that made it and a set's change outlives it.
//
// Every value here was read off Chromium 141, by rendering
// `counter(c)` into a ::before and comparing its width against spans
// whose ::before is a literal one, two, three or four characters long
// -- so each case's candidates were chosen to differ in length.

text cHead = head + '<style>.v { display:inline-block } .v::before { content: counter(c) }'
    + '.b::before { content: counter(b) }</style>'

Page cs1 = pageFromHtml(cHead + '<div style="counter-set: c 55">'
    + '<span class="v" id="x">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(cs1.root, 'x'), '55', 'counter-set sets the value it names')

Page cs2 = pageFromHtml(cHead + '<div style="counter-set: c">'
    + '<span class="v" id="x">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(cs2.root, 'x'), '0', 'and with no value it sets zero')

// The discriminating pair.
Page cs3 = pageFromHtml(cHead + '<div style="counter-reset: c 1000">'
    + '<div style="counter-set: c 7">x</div>'
    + '<span class="v" id="x">a</span></div></body>', 'about:blank', 600)
Page cs4 = pageFromHtml(cHead + '<div style="counter-reset: c 1000">'
    + '<div style="counter-reset: c 7">x</div>'
    + '<span class="v" id="x">a</span></div></body>', 'about:blank', 600)
check(generatedBefore(cs3.root, 'x') != generatedBefore(cs4.root, 'x'),
      'counter-set and counter-reset do not do the same thing to what follows')
checkEq(generatedBefore(cs3.root, 'x'), '7',
        'a set changes the instance in scope, so the next sibling sees it')
checkEq(generatedBefore(cs4.root, 'x'), '1000',
        'a reset makes an instance of its own, which dies with its element')

// On one element the order is reset, then increment, then set.
Page cs5 = pageFromHtml(cHead + '<div style="counter-reset: c 100; counter-set: c 5">'
    + '<span class="v" id="x">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(cs5.root, 'x'), '5', 'a set on the same element runs after the reset')

Page cs6 = pageFromHtml(cHead + '<div style="counter-reset: c 0">'
    + '<div style="counter-increment: c 500; counter-set: c 1">'
    + '<span class="v" id="x">a</span></div></div></body>', 'about:blank', 600)
checkEq(generatedBefore(cs6.root, 'x'), '1', 'and after the increment')

// With nothing in scope it creates a counter, scoped as a reset would.
Page cs7 = pageFromHtml(cHead + '<div><div style="counter-set: c 777">'
    + '<span class="v" id="x">a</span></div></div></body>', 'about:blank', 600)
checkEq(generatedBefore(cs7.root, 'x'), '777',
        'a set with nothing in scope creates the counter')
Page cs8 = pageFromHtml(cHead + '<div><div style="counter-set: c 777">y</div>'
    + '<span class="v" id="x">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(cs8.root, 'x'), '777',
        'and the counter it created is in scope for the following siblings')

Page cs9 = pageFromHtml(cHead + '<div style="counter-set: a 77 b 888">'
    + '<span class="b" id="x" style="display:inline-block">a</span></div></body>',
    'about:blank', 600)
checkEq(generatedBefore(cs9.root, 'x'), '888', 'a set takes a list of names, as the others do')

Page cs10 = pageFromHtml(cHead + '<div style="counter-set: c -55">'
    + '<span class="v" id="x">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(cs10.root, 'x'), '-55', 'and a negative value')

// The same trap as counter-reset: `anyCounters` is what makes counters
// free for the pages without them, and a property named only in a style
// attribute is in no stylesheet rule to be found by walking them.
Page cs11 = pageFromHtml(head + '<style>.v { display:inline-block }'
    + '.v::before { content: counter(c) } #q { counter-set: c 42 }</style>'
    + '<div id="q"><span class="v" id="x">a</span></div></body>', 'about:blank', 600)
checkEq(generatedBefore(cs11.root, 'x'), '42', 'a set written in a stylesheet counts')
Page cs12 = pageFromHtml(head + '<style>.v { display:inline-block }'
    + '.v::before { content: counter(c) }</style>'
    + '<div style="counter-set: c 42"><span class="v" id="x">a</span></div></body>',
    'about:blank', 600)
checkEq(generatedBefore(cs12.root, 'x'), generatedBefore(cs11.root, 'x'),
        'and one written in a style attribute counts the same')

// ---- attr() in content (CSS Values and Units 3 §6) -------------------
//
// Values 3 allows `attr()` in `content` and nowhere else -- the typed
// form that reaches other properties is Values 5 -- so this is the
// whole of that feature, and it had no check until now.
Page pa1 = pageFromHtml(head
    + '<style>span::before{content:attr(data-x)}</style>'
    + '<span id="x" data-x="hello"></span></body>', 'about:blank', 600)
checkEq(generatedBefore(pa1.root, 'x'), 'hello', 'attr() generates the attribute\'s value')

// An attribute that is not there is the empty string, not the word
// `null` and not a dropped declaration.
Page pa2 = pageFromHtml(head
    + '<style>span::before{content:attr(data-missing)}</style>'
    + '<span id="x" data-x="hello"></span></body>', 'about:blank', 600)
checkEq(generatedBefore(pa2.root, 'x'), '', 'a missing attribute generates nothing')

// It composes with the strings beside it, in the order written.
Page pa3 = pageFromHtml(head
    + '<style>span::before{content:"[" attr(data-x) "]"}</style>'
    + '<span id="x" data-x="mid"></span></body>', 'about:blank', 600)
checkEq(generatedBefore(pa3.root, 'x'), '[mid]', 'and sits among the strings in order')

// The attribute name is matched case-insensitively, as HTML attribute
// names are, and its VALUE is not folded.
Page pa4 = pageFromHtml(head
    + '<style>span::before{content:attr(DATA-X)}</style>'
    + '<span id="x" data-x="MiXeD"></span></body>', 'about:blank', 600)
checkEq(generatedBefore(pa4.root, 'x'), 'MiXeD',
        'the name folds and the value does not')

// The check that needs no number: an attribute holding exactly what a
// string would have said must generate what that string generates.
Page pa5 = pageFromHtml(head
    + '<style>#a::before{content:attr(data-x)}#b::before{content:"same"}</style>'
    + '<span id="a" data-x="same"></span><span id="b"></span></body>', 'about:blank', 600)
checkEq(generatedBefore(pa5.root, 'a'), generatedBefore(pa5.root, 'b'),
        'attr() and the string it holds generate the same content')

finish('counters')
