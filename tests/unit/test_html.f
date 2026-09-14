// Unit checks for the HTML tokenizer and tree builder.
import ../../src/html/parser.f
import ../assert.f

Node d1 = parseHtmlText('<p>Hello <b>bold</b> world</p>')
checkEq(dumpTree(d1, 0), '<#document>\n  <html>\n    <head>\n    <body>\n      <p>\n        "Hello "\n        <b>\n          "bold"\n        " world"\n', 'simple paragraph')

// implied end tags: p closed by div, li by li, unclosed heading
Node d2 = parseHtmlText('<p>one<div>two</div><ul><li>a<li>b</ul><h1>h<h2>i')
checkEq(dumpTree(findElement(d2, 'body'), 0), '<body>\n  <p>\n    "one"\n  <div>\n    "two"\n  <ul>\n    <li>\n      "a"\n    <li>\n      "b"\n  <h1>\n    "h"\n  <h2>\n    "i"\n', 'implied end tags')

// head elements, raw text, attributes, entities, void elements
Node d3 = parseHtmlText('<!DOCTYPE html><html lang="en"><head><title>T &amp; U</title><style>p > b { x: "&amp;" }</style></head><body class=main><img src="a.png" alt=\'it&#39;s\'><br/>AT&T &copy;<!-- c --> &lt;ok&gt;</body></html>')
Node html3 = findElement(d3, 'html')
checkEq(getAttr(html3, 'lang'), 'en', 'html attrs merged')
checkEq(textContent(findElement(d3, 'title')), 'T & U', 'title is escapable raw text')
checkEq(textContent(findElement(d3, 'style')), 'p > b { x: "&amp;" }', 'style is raw text')
checkEq(getAttr(findElement(d3, 'body'), 'class'), 'main', 'unquoted attribute')
Node img3 = findElement(d3, 'img')
checkEq(getAttr(img3, 'alt'), "it's", 'numeric entity in attribute')
checkEqInt(img3.children.length, 0, 'void element has no children')
checkEq(textContent(findElement(d3, 'body')), "AT&T © <ok>", 'entities in text')

// UTF-8 round trip through the ASCII-safe pre-pass
blob utf = 'tests/fixtures/utf8.html'
Node d4 = parseHtmlBlob(utf)
checkEq(textContent(findElement(d4, 'p')), 'café — “quotes” ✓', 'utf-8 round trip')

// tables: whitespace between rows dropped, cells closed by siblings
Node d5 = parseHtmlText('<table>\n <tr><td>1<td>2\n <tr><td>3</td></tr>\n</table>')
Node tbl = findElement(d5, 'table')
checkEqInt(tbl.children.length, 2, 'blank text dropped inside table')
checkEqInt(tbl.children[0].children.length, 2, 'td closed by td')
checkEq(tbl.children[0].children[1].children[0].data, '2\n ', 'cell text keeps trailing whitespace')

// stray end tags are ignored; nested formatting pops correctly
Node d6 = parseHtmlText('<div><span>a</b>b</span></div></p>c')
checkEq(dumpTree(findElement(d6, 'body'), 0), '<body>\n  <div>\n    <span>\n      "ab"\n  "c"\n', 'stray end tags')

// a lone < in text, and script content with tags inside
Node d7 = parseHtmlText('<p>1 < 2</p><script>if (a<b) { document.write("<p>x</p>") }</script>')
checkEq(textContent(findElement(d7, 'p')), '1 < 2', 'lone < is text')
checkEq(textContent(findElement(d7, 'script')), 'if (a<b) { document.write("<p>x</p>") }', 'script raw text')

// dt/dd and nested lists
Node d8 = parseHtmlText('<dl><dt>a<dd>b<dt>c</dl><ol><li>x<ul><li>y</ul><li>z</ol>')
checkEq(dumpTree(findElement(d8, 'body'), 0), '<body>\n  <dl>\n    <dt>\n      "a"\n    <dd>\n      "b"\n    <dt>\n      "c"\n  <ol>\n    <li>\n      "x"\n      <ul>\n        <li>\n          "y"\n    <li>\n      "z"\n', 'dl and nested lists')

finish('html')
