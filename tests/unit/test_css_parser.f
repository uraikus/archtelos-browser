import ../../src/css/parser.f
import ../assert.f

Stylesheet s1 = parseStylesheet('/* c */ p, div.note > b { color: red; margin : 1px 2px !important }\n#x a[href^="http"]:first-child { display:none }')
checkEq(dumpStylesheet(s1), 'p{1}, div.note > b{1026} { color: red; margin: 1px 2px !important; }\n*#x a[href3http]:first-child{1050625} { display: none; }\n', 'rules, specificity, important')

Stylesheet s2 = parseStylesheet('a:hover { x: 1 } li:nth-child(odd) { y: 2 } p::before { z: 3 } h1 + p ~ em { w: 4 } div:not(.a) { v: 5 } .a.b#c { u: 6 }')
// `a:hover` and `p::before` use constructs this engine does not
// support, so those two rules are dropped entirely rather than kept
// with a selector that can never match (Selectors 3 §4).
checkEq(dumpStylesheet(s2), 'li:nth-child:odd{1025} { y: 2; }\nh1 + p ~ em{3} { w: 4; }\ndiv:not(*.a{0}){1025} { v: 5; }\n*#c.a.b{1050624} { u: 6; }\n', 'pseudo classes and combinators')

cssViewportWidth = 500
Stylesheet s3 = parseStylesheet('@charset "utf-8"; @import url(x.css); @media screen and (max-width: 600px) { p { a: 1 } } @media print { p { b: 2 } } @media (min-width: 900px), all { p { c: 3 } } @font-face { font-family: X; src: url(x) } @media not screen { p { d: 4 } } q { e: 5 }')
checkEq(dumpStylesheet(s3), 'p{1} { a: 1; }\np{1} { c: 3; }\nq{1} { e: 5; }\n', 'at-rules and media queries')

Stylesheet s4 = parseStylesheet('p { font-family: "Helvetica; Neue", sans-serif; background: url(a;b.png) no-repeat; -webkit-x: 1; --custom: 2; color: rgb(1, 2, 3); }')
// A custom property is kept -- var() reads it -- while a vendor prefix
// is still dropped.
checkEq(dumpStylesheet(s4), 'p{1} { font-family: "Helvetica; Neue", sans-serif; background: url(a;b.png) no-repeat; --custom: 2; color: rgb(1, 2, 3); }\n', 'semicolons inside quotes and parens')

Stylesheet s5 = parseStylesheet('p { color: red } } div { color: blue } broken { ')
checkEq(dumpStylesheet(s5), 'p{1} { color: red; }\ndiv{1} { color: blue; }\n', 'recovery from stray braces')
finish('css parser')
