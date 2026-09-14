// Unit checks for the HTML tokenizer and tree construction.
//
// The WPT corpus in tests/conformance covers the standard exhaustively,
// but it needs a checkout of web-platform-tests and skips without one,
// so the behaviours this browser most depends on are pinned here too.
// Expectations use the standard's own serialization format, the same one
// the corpus compares against.

import ../../src/html/parser.f
import ../../src/dom/serialize.f
import ../assert.f

text func parseAndDump(html:text) {
    nodeRegistryReset()
    Node doc = parseHtmlText(html)
    return serializeDocument(doc)
}

// The body's children, serialized -- most tests only care about those.
text func body(html:text) {
    nodeRegistryReset()
    Node doc = parseHtmlText(html)
    Node b = findElement(doc, 'body')
    arr[text] out = []
    for int i = 0, i < b.children.length, i++ {
        serializeNodeInto(b.children[i], 0, out)
    }
    // drop the leading '| ' the standard's format puts on every line.
    // `text` has no slice, and a line holding non-ascii cannot become an
    // `ascii` at all, so this goes through code points (FINDINGS.md,
    // "text has no substring")
    arr[text] trimmed = []
    for int i = 0, i < out.length, i++ {
        arr[text] cps = out[i].split('')
        arr[text] rest = cps.splice(2, cps.length - 2)
        trimmed.push(rest.join(''))
    }
    return trimmed.join('\n')
}

// ---- the document skeleton ------------------------------------------

checkEq(parseAndDump('<p>Hello <b>bold</b> world</p>'),
'| <html>\n|   <head>\n|   <body>\n|     <p>\n|       "Hello "\n|       <b>\n|         "bold"\n|       " world"',
'html, head and body always exist')

checkEq(parseAndDump('<!DOCTYPE html><title>T</title>'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|     <title>\n|       "T"\n|   <body>',
'a doctype and a head element')

checkEq(parseAndDump('<!DOCTYPE html PUBLIC "a" "b">'),
'| <!DOCTYPE html "a" "b">\n| <html>\n|   <head>\n|   <body>',
'doctype public and system identifiers')

// ---- implied end tags ------------------------------------------------

checkEq(body('<p>one<div>two</div>'), '<p>\n  "one"\n<div>\n  "two"',
'a block start tag closes an open p')

checkEq(body('<ul><li>a<li>b</ul>'), '<ul>\n  <li>\n    "a"\n  <li>\n    "b"',
'li closes li')

checkEq(body('<dl><dt>a<dd>b</dl>'), '<dl>\n  <dt>\n    "a"\n  <dd>\n    "b"',
'dt and dd close each other')

checkEq(body('<h1>h<h2>i'), '<h1>\n  "h"\n<h2>\n  "i"',
'a heading closes an open heading')

// ---- the list of active formatting elements --------------------------

checkEq(body('<b>1<p>2</b>3</p>'), '<b>\n  "1"\n<p>\n  <b>\n    "2"\n  "3"',
'formatting is reconstructed across a block boundary')

checkEq(body('<b><i>bold italic</b> italic</i>'),
'<b>\n  <i>\n    "bold italic"\n<i>\n  " italic"',
'misnested formatting is repaired by the adoption agency')

checkEq(body('<a href="x">1<a href="y">2'),
'<a>\n  href="x"\n  "1"\n<a>\n  href="y"\n  "2"',
'a second a element closes the first')

// ---- tables ------------------------------------------------------------

checkEq(body('<table><tr><td>1<td>2</table>'),
'<table>\n  <tbody>\n    <tr>\n      <td>\n        "1"\n      <td>\n        "2"',
'tbody is synthesized and cells close each other')

checkEq(body('<table><td>x</table>'),
'<table>\n  <tbody>\n    <tr>\n      <td>\n        "x"',
'a bare td synthesizes both tbody and tr')

checkEq(body('<table><b>stray</b><tr><td>x</table>'),
'<b>\n  "stray"\n<table>\n  <tbody>\n    <tr>\n      <td>\n        "x"',
'content misnested in a table is foster parented before it')

checkEq(body('<!DOCTYPE html><p><table>'), '<p>\n<table>',
'a table closes an open p in standards mode')

checkEq(body('<p><table>'), '<p>\n  <table>',
'a table does not close an open p in quirks mode')

// ---- template contents --------------------------------------------------

checkEq(body('<body><template>Hello</template>'), '<template>\n  content\n    "Hello"',
'template children go into its content fragment')

checkEq(body('<body><template><tr><td>x</table></template>'),
'<template>\n  content\n    <tr>\n      <td>\n        "x"',
'a template holds table rows with no table around them')

// ---- raw text and escapable raw text -------------------------------------

checkEq(body('<body><script>if (a<b) { x("</p>") }</script>'),
'<script>\n  "if (a<b) { x("</p>") }"',
'script content is raw text')

checkEq(body('<body><style>p > b { content: "&amp;" }</style>'),
'<style>\n  "p > b { content: "&amp;" }"',
'style content is raw text and keeps its ampersands undecoded')

checkEq(body('<textarea>a &amp; b</textarea>'), '<textarea>\n  "a & b"',
'textarea is escapable raw text')

checkEq(body('<pre>\nkept</pre>'), '<pre>\n  "kept"',
'a newline straight after pre is dropped')

// ---- character references -------------------------------------------------

checkEq(body('AT&T &copy; &lt;ok&gt; &nosuch; &#65; &#x42;'),
'"AT&T © <ok> &nosuch; A B"',
'named, legacy, unknown and numeric references')

checkEq(body('<a href="?a=1&copy=2">x</a>'),
'<a>\n  href="?a=1&copy=2"\n  "x"',
'a legacy reference in an attribute is left alone when = follows')

checkEq(body('&notin;&notit;'), '"∉¬it;"',
'the longest matching reference wins')

checkEq(body('&NotEqualTilde;'), '"≂̸"',
'a reference whose replacement is two code points')

// ---- comments and bogus markup ----------------------------------------------

checkEq(body('<body><!-- c --><? pi >'), '<!--  c  -->\n<!-- ? pi  -->',
'a comment, and a processing instruction parsed as a comment')

// ---- foreign content ----------------------------------------------------------

checkEq(body('<svg><circle/><foreignObject><p>html</p></foreignObject></svg>'),
'<svg svg>\n  <svg circle>\n  <svg foreignObject>\n    <p>\n      "html"',
'svg is namespaced and foreignObject is an html integration point')

checkEq(body('<svg><textpath></textpath></svg>'), '<svg svg>\n  <svg textPath>',
'an svg tag name is restored to its camel case')

checkEq(body('<math><mi>x</mi></math>'), '<math math>\n  <math mi>\n    "x"',
'mathml elements are namespaced')

checkEq(body('<svg><path transform="x" clippathunits="y"/></svg>'),
'<svg svg>\n  <svg path>\n    clipPathUnits="y"\n    transform="x"',
'an svg attribute name is restored to its camel case')

// ---- utf-8 ----------------------------------------------------------------------

blob utf = 'tests/fixtures/utf8.html'
nodeRegistryReset()
Node d4 = parseHtmlBlob(utf)
checkEq(textContent(findElement(d4, 'p')), 'café — “quotes” ✓',
'utf-8 survives the ascii-safe pre-pass')

checkEq(body('<body><style>/* café */</style>'), '<style>\n  "/* café */"',
'non-ascii survives inside raw text too')

finish('html')
