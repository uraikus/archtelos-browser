// The user-agent stylesheet: what an element looks like before any
// author CSS. A Festina template literal may span lines, which is
// what makes embedding a stylesheet in source practical.

text uaStylesheetText = `
html, body, div, p, h1, h2, h3, h4, h5, h6, ul, ol, dl, dt, dd, blockquote, pre,
hr, table, form, fieldset, legend, address, article, aside, footer, header, main,
nav, section, figure, figcaption, details, summary, center, menu, dir, hgroup,
frameset, optgroup, option, select { display: block }
iframe { display: inline; border: 1px solid #808080 }
frame { display: block; border: 1px solid #808080 }
head, script, style, title, meta, link, template, base, param,
datalist, dialog, rp, [hidden], input[type=hidden] { display: none }
/* An audio element is invisible until it is asked for controls, which
   is what Chromium's own user-agent sheet says. Expressing it needs an
   attribute selector inside :not(), which this engine gained with
   Selectors 3. */
audio:not([controls]) { display: none }
area, noscript { display: inline }
marquee, meter, progress { display: inline-block }
slot { display: contents }
ruby { display: ruby }
/* HTML's Rendering section: the annotation is set at half the size and
   takes its own line height rather than the one it would inherit, which
   is what makes the band it sits in the height of its own text and not
   of the base's. Chromium reports 8px and a 9-pixel box for a 16px/20px
   element, which is what this reproduces. */
rt { font-size: 50%; line-height: normal }
col { display: table-column }
colgroup { display: table-column-group }
li { display: list-item }
table { display: table; border-spacing: 2px; border-collapse: separate; text-indent: 0 }
tbody { display: table-row-group; vertical-align: middle }
thead { display: table-header-group; vertical-align: middle }
tfoot { display: table-footer-group; vertical-align: middle }
tr { display: table-row; vertical-align: middle }
td, th { display: table-cell; padding: 1px; vertical-align: inherit }
th { font-weight: bold; text-align: center }
caption { display: table-caption; text-align: center }
body { margin: 8px }
p, dl, blockquote, figure { margin: 1em 0 }
pre { margin: 1em 0; white-space: pre; font-family: monospace }
h1 { font-size: 2em; margin: 0.67em 0; font-weight: bold }
h2 { font-size: 1.5em; margin: 0.83em 0; font-weight: bold }
h3 { font-size: 1.17em; margin: 1em 0; font-weight: bold }
h4 { font-size: 1em; margin: 1.33em 0; font-weight: bold }
h5 { font-size: 0.83em; margin: 1.67em 0; font-weight: bold }
h6 { font-size: 0.67em; margin: 2.33em 0; font-weight: bold }
ul, ol, menu, dir { margin: 1em 0; padding-left: 40px }
ul { list-style-type: disc }
ol { list-style-type: decimal }
ul ul, ol ul { list-style-type: circle; margin: 0 }
ul ul ul, ol ul ul { list-style-type: square }
ul ol, ol ol { margin: 0 }
dd { margin-left: 40px }
blockquote { margin: 1em 40px }
figure { margin: 1em 40px }
fieldset { margin: 0 2px; padding: 0.35em 0.75em 0.625em; border: 2px solid #c0c0c0 }
legend { padding: 0 2px }
hr { display: block; margin: 0.5em auto; border: 1px solid #808080; height: 0 }
b, strong { font-weight: bold }
i, em, cite, var, dfn, address { font-style: italic }
u, ins { text-decoration: underline }
s, strike, del { text-decoration: line-through }
a[href] { color: #0000ee; text-decoration: underline }
code, kbd, samp, tt { font-family: monospace }
small { font-size: smaller }
big { font-size: larger }
sub { vertical-align: bottom; font-size: smaller }
sup { vertical-align: top; font-size: smaller }
center { text-align: center }
mark { background-color: yellow; color: black }
input, button, select, textarea { display: inline-block; border: 1px solid #767676; padding: 2px 6px; background-color: white; font-size: 13px; color: black; appearance: auto }
input[type=checkbox], input[type=radio] { border: 0; padding: 0; background-color: transparent }
button, input[type=submit], input[type=button], input[type=reset] { background-color: #efefef; padding: 2px 8px; text-align: center }
textarea { white-space: pre-wrap; display: inline-block }
img { display: inline }
nobr { white-space: nowrap }
abbr[title], acronym[title] { text-decoration: underline }
q { quotes: '"' '"' "'" "'" }
input::placeholder { color: #757575 }
q::before { content: open-quote }
q::after { content: close-quote }
`
