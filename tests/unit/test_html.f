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

// ---- select content -------------------------------------------------------------
//
// A select holds ordinary flow content: it is not a restricted
// insertion mode of its own.

checkEq(body('<select><div>x</div><button>b</button></select>'),
'<select>\n  <div>\n    "x"\n  <button>\n    "b"',
'a select keeps flow content')

checkEq(body('<select><div><i></div><option>o'),
'<select>\n  <div>\n    <i>\n  <i>\n    <option>\n      "o"',
'formatting is reconstructed inside a select')

checkEq(body('<select><option>a</select><p>x'),
'<select>\n  <option>\n    "a"\n<p>\n  "x"',
'an end tag closes the select')

checkEq(body('<select><div><select><p>x'),
'<select>\n  <div>\n<p>\n  "x"',
'a nested select closes the outer one instead of nesting')

checkEq(body('<select>x<input>y'),
'<select>\n  "x"\n<input>\n"y"',
'an input breaks out of a select')

checkEq(body('<select><option>a<option>b'),
'<select>\n  <option>\n    "a"\n  <option>\n    "b"',
'an option closes an open option')

checkEq(body('<select><optgroup>a<optgroup>b'),
'<select>\n  <optgroup>\n    "a"\n  <optgroup>\n    "b"',
'an optgroup closes an open optgroup')

checkEq(body('<select><optgroup><option><hr>'),
'<select>\n  <optgroup>\n    <option>\n  <hr>',
'an hr closes an open option and optgroup')

checkEq(body('<font><select><option>a</option></font></select>'),
'<font>\n  <select>\n    <option>\n      "a"',
'a select is not a special element, so it does not stop the adoption agency')

checkEq(body('<select><button><selectedcontent></button><option>X<option selected>Y'),
'<select>\n  <button>\n    <selectedcontent>\n      "Y"\n  <option>\n    "X"\n  <option>\n    selected=""\n    "Y"',
'selectedcontent mirrors the selected option')

// ---- insertion location -----------------------------------------------------------

checkEq(body('<body><template><tr><div></div></tr></template>'),
'<template>\n  content\n    <tr>\n    <div>',
'content misnested in a template row stays inside the template')

checkEq(body('<body><template><i><menu>Foo</i>'),
'<template>\n  content\n    <i>\n    <menu>\n      <i>\n        "Foo"',
'the adoption agency keeps its result inside the template')

checkEq(parseAndDump('<!DOCTYPE html><template><table><form></table></template>'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|     <template>\n|       content\n|         <table>\n|           <form>\n|   <body>',
'a form is kept in a table inside a template')

checkEq(parseAndDump('<!DOCTYPE html><template></template><p><frameset>'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|     <template>\n|       content\n|   <frameset>',
'a template in the head leaves a later frameset possible')

checkEq(parseAndDump('<!DOCTYPE html><p><template></template><frameset>'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <body>\n|     <p>\n|       <template>\n|         content',
'a template in the body rules a later frameset out')

// ---- an end tag that runs to the end of the input ---------------------
// The standard's end tag name state emits the `</` and the name it had
// buffered as CHARACTER tokens when what follows is not a matching `>`,
// whitespace or `/`, and at the end of the input the same buffer has to
// reach the text. So a script whose content ends in an unterminated end
// tag keeps it as text rather than losing it: ten cases of tests16.dat,
// each appearing once with a doctype and once without.

checkEq(parseAndDump('<script></script'),
'| <html>\n|   <head>\n|     <script>\n|       "</script"\n|   <body>',
'an unterminated end tag at the end of a script is its text')

checkEq(parseAndDump('<script></SCRIPT'),
'| <html>\n|   <head>\n|     <script>\n|       "</SCRIPT"\n|   <body>',
'and keeps the case it was written in, because it is text and not a name')

checkEq(parseAndDump('<script><!--</script'),
'| <html>\n|   <head>\n|     <script>\n|       "<!--</script"\n|   <body>',
'the escaped state does not change that')

checkEq(parseAndDump('<script><!--<script </script </script'),
'| <html>\n|   <head>\n|     <script>\n|       "<!--<script </script </script"\n|   <body>',
'nor does the double escaped state, which the first `</script ` leaves')

checkEq(parseAndDump('<script><!--<script --></script'),
'| <html>\n|   <head>\n|     <script>\n|       "<!--<script --></script"\n|   <body>',
'and an unterminated end tag after the escape closed is text as well')

// The instrument: a TERMINATED end tag must still end the script, or every
// check above would hold on an engine that never closed one.
checkEq(parseAndDump('<script></script>x'),
'| <html>\n|   <head>\n|     <script>\n|   <body>\n|     "x"',
'a terminated end tag still closes the script and takes nothing with it')

checkEq(parseAndDump('<title></title'),
'| <html>\n|   <head>\n|     <title>\n|       "</title"\n|   <body>',
'the same holds for RCDATA, where the text is decoded rather than raw')

// ---- </p> and </br> break out of foreign content ----------------------
// An end tag named `p` or `br` inside SVG or MathML pops the foreign
// elements and is then handled by the HTML rules; any other unmatched end
// tag is not. Mapped against Chromium on thirteen fixtures (todo.md has
// them), because the four corpus cases alone would not have said where the
// popping stops.

checkEq(parseAndDump('<svg></p><foo>'),
'| <html>\n|   <head>\n|   <body>\n|     <svg svg>\n|     <p>\n|     <foo>',
'`</p>` in SVG pops it, and what follows is HTML beside it')

checkEq(parseAndDump('<svg></br><foo>'),
'| <html>\n|   <head>\n|   <body>\n|     <svg svg>\n|     <br>\n|     <foo>',
'`</br>` does the same, and becomes a `<br>` as the HTML rules say')

checkEq(parseAndDump('<math></p><foo>'),
'| <html>\n|   <head>\n|   <body>\n|     <math math>\n|     <p>\n|     <foo>',
'and MathML is no different')

checkEq(parseAndDump('<svg><circle></p>x'),
'| <html>\n|   <head>\n|   <body>\n|     <svg svg>\n|       <svg circle>\n|     <p>\n|     "x"',
'it pops all the way out rather than one level')

checkEq(parseAndDump('<div><svg></p><foo>'),
'| <html>\n|   <head>\n|   <body>\n|     <div>\n|       <svg svg>\n|       <p>\n|       <foo>',
'stopping at the nearest HTML element, which here is the div and not the body')

checkEq(parseAndDump('<p><svg></p><foo>'),
'| <html>\n|   <head>\n|   <body>\n|     <p>\n|       <svg svg>\n|     <foo>',
'and once out, `</p>` closes the p that was already open rather than making one')

checkEq(parseAndDump('<math><mtext><svg></p>x'),
'| <html>\n|   <head>\n|   <body>\n|     <math math>\n|       <math mtext>\n|         <svg svg>\n|         <p>\n|         "x"',
'an integration point is already HTML content, so the popping stops there')

checkEq(parseAndDump('<svg><desc><svg></p>x'),
'| <html>\n|   <head>\n|   <body>\n|     <svg svg>\n|       <svg desc>\n|         <svg svg>\n|         <p>\n|         "x"',
'which holds for SVG\'s own integration points as well')

// The instrument: any OTHER unmatched end tag must not break out, or every
// check above would hold on an engine that left foreign content on each of
// them.
checkEq(parseAndDump('<svg></div>x'),
'| <html>\n|   <head>\n|   <body>\n|     <svg svg>\n|       "x"',
'`</div>` in SVG breaks out of nothing, and the text stays inside')

checkEq(parseAndDump('<svg></svg>x'),
'| <html>\n|   <head>\n|   <body>\n|     <svg svg>\n|     "x"',
'while the matching end tag closes it, as it always did')

// ---- whitespace in and after a frameset -------------------------------
// The tokenizer emits a run of characters as one token; the standard's
// "in frameset" and "after frameset" modes are written per character, and
// insert every whitespace one while ignoring every other one. So the
// whitespace a run keeps is all of it, not the leading part: ` te st`
// reaches the tree as two spaces, not one.

checkEq(parseAndDump('<!DOCTYPE html><frameset> te st'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <frameset>\n|     "  "',
'every whitespace character in a frameset is inserted, and the rest dropped')

checkEq(parseAndDump('<!DOCTYPE html><frameset></frameset> te st'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <frameset>\n|   "  "',
'and after the frameset the same rule puts them beside it')

checkEq(parseAndDump('<!DOCTYPE html><frameset>  '),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <frameset>\n|     "  "',
'a run that is only whitespace is unchanged by that')

checkEq(parseAndDump('<!DOCTYPE html><html><frameset></frameset></html>  '),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <frameset>\n|   "  "',
'and once `</html>` has been seen the rule still holds')

checkEq(parseAndDump('<html><frameset></frameset></html> te st'),
'| <html>\n|   <head>\n|   <frameset>\n|   "  "',
'there too it is every whitespace character and nothing else')

// The instrument: a run with no whitespace in it must insert nothing, or
// every check above would hold on an engine that inserted the whole run.
checkEq(parseAndDump('<!DOCTYPE html><frameset>test'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <frameset>',
'and a run with no whitespace in it reaches the tree as nothing at all')

checkEq(parseAndDump('<!DOCTYPE html><html><frameset></frameset></html>abc'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <frameset>',
'which holds after `</html>` as well')

// ---- `<image>` is renamed to `img` -----------------------------------
// The standard's "in body" rules give the tag one line: change the
// token's tag name to `img` and reprocess it. So the element in the tree
// is an `img`, void and carrying the attributes the token had.

checkEq(body('<p><image></p>'), '<p>\n  <img>',
'an `image` start tag builds an `img`')

checkEq(parseAndDump('<!DOCTYPE html><image/>'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <body>\n|     <img>',
'and its self-closing form does the same')

checkEq(body('<image src="x">y'), '<img>\n  src="x"\n"y"',
'it keeps the attributes, and is void, so the text lands beside it')

// The instrument: the rename is that one name and not a prefix of it, or
// the checks above would hold on an engine that renamed anything starting
// `image`.
checkEq(body('<imagex>y'), '<imagex>\n  "y"',
'a tag that merely starts with `image` is left as it was written')

// ---- two states that reach the end of the input -----------------------
// The end tag open state emits the `<` and the `/` as characters when the
// input ends there, rather than opening a bogus comment; and a comment
// that ends with the input is emitted without the one or two dashes that
// took the tokenizer into its comment end dash and comment end states.

checkEq(body('</'), '"</"',
'`</` at the end of the input is text, not a comment')

checkEq(parseAndDump('<!DOCTYPE html><!--x--'),
'| <!DOCTYPE html>\n| <!-- x -->\n| <html>\n|   <head>\n|   <body>',
'the two dashes that end a comment are not part of it at the end of input')

checkEq(parseAndDump('<!DOCTYPE html><!--x-'),
'| <!DOCTYPE html>\n| <!-- x -->\n| <html>\n|   <head>\n|   <body>',
'nor is a single trailing dash')

checkEq(parseAndDump('<!DOCTYPE html><!--x---'),
'| <!DOCTYPE html>\n| <!-- x- -->\n| <html>\n|   <head>\n|   <body>',
'while a third dash is data, because only two are consumed by the states')

// The instrument: a dash run in the middle of a comment is data, all of
// it, or the checks above would hold on an engine that dropped dashes
// wherever they appeared.
checkEq(parseAndDump('<!DOCTYPE html><!--x--y-->'),
'| <!DOCTYPE html>\n| <!-- x--y -->\n| <html>\n|   <head>\n|   <body>',
'dashes that are not at the end of the input stay in the comment')

checkEq(body('</x'), '',
'and an end tag that merely runs out of input still opens a tag')

// ---- whitespace a table ends with -------------------------------------
// The "in table text" mode collects a run and, when all of it is
// whitespace, inserts it into the table. The corpus asks this of
// `<!doctype html><table>` followed by a newline, and the conformance
// runner had been trimming that newline out of the `#data` section before
// the parser saw it, so the case could not pass however the engine
// behaved. Pinned here, where the input is written out.

checkEq(parseAndDump('<!DOCTYPE html><table>\n'),
'| <!DOCTYPE html>\n| <html>\n|   <head>\n|   <body>\n|     <table>\n|       "\n"',
'a table that ends in whitespace keeps it as a text child')

finish('html')
