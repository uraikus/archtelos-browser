import ../../src/css/parser.f
import ../assert.f

Stylesheet s1 = parseStylesheet('/* c */ p, div.note > b { color: red; margin : 1px 2px !important }\n#x a[href^="http"]:first-child { display:none }')
checkEq(dumpStylesheet(s1), 'p{1}, div.note > b{1026} { color: red; margin: 1px 2px !important; }\n*#x a[href3http]:first-child{1050625} { display: none; }\n', 'rules, specificity, important')

Stylesheet s2 = parseStylesheet('a:hover { x: 1 } li:nth-child(odd) { y: 2 } p::before { z: 3 } h1 + p ~ em { w: 4 } div:not(.a) { v: 5 } .a.b#c { u: 6 }')
// `a:hover` and `p::before` use constructs this engine does not
// support, so those two rules are dropped entirely rather than kept
// with a selector that can never match (Selectors 3 §4).
//
// `:nth-child(odd)` keeps its An+B form -- 2n+1 -- rather than the word
// it was written as, because that is what the matcher works from.
checkEq(dumpStylesheet(s2), 'li:nth-child:2:1{1025} { y: 2; }\nh1 + p ~ em{3} { w: 4; }\ndiv:not(*.a{0}){1025} { v: 5; }\n*#c.a.b{1050624} { u: 6; }\n', 'pseudo classes and combinators')

cssViewportWidth = 500
Stylesheet s3 = parseStylesheet('@charset "utf-8"; @import url(x.css); @media screen and (max-width: 600px) { p { a: 1 } } @media print { p { b: 2 } } @media (min-width: 900px), all { p { c: 3 } } @font-face { font-family: X; src: url(x) } @media not screen { p { d: 4 } } q { e: 5 }')
checkEq(dumpStylesheet(s3), 'p{1} { a: 1; }\np{1} { c: 3; }\nq{1} { e: 5; }\n', 'at-rules and media queries')

Stylesheet s4 = parseStylesheet('p { font-family: "Helvetica; Neue", sans-serif; background: url(a;b.png) no-repeat; -webkit-x: 1; --custom: 2; color: rgb(1, 2, 3); }')
// A custom property is kept -- var() reads it -- while a vendor prefix
// is still dropped.
checkEq(dumpStylesheet(s4), 'p{1} { font-family: "Helvetica; Neue", sans-serif; background: url(a;b.png) no-repeat; --custom: 2; color: rgb(1, 2, 3); }\n', 'semicolons inside quotes and parens')

Stylesheet s5 = parseStylesheet('p { color: red } } div { color: blue } broken { ')
checkEq(dumpStylesheet(s5), 'p{1} { color: red; }\ndiv{1} { color: blue; }\n', 'recovery from stray braces')

// ---- An+B (Selectors 3 §6.6.5) ---------------------------------------
// The old parser read the argument with toInt(), so `2n` came back as 2
// and `:nth-child(2n)` matched the second child rather than every even
// one -- wrong in a way that looks like it works. These pin the forms
// the grammar allows and, as much, the ones it does not.
void func checkAnb(arg:text, okWanted:bool, a:int, b:int, label:text) {
    bool ok = parseAnPlusB(arg.toAscii())
    if ok != okWanted {
        checksFailed++
        log(`FAIL: ${label}: expected ${okWanted ? 'accepted' : 'rejected'}`)
        return
    }
    if !okWanted { checksPassed++  return }
    if anbA == a && anbB == b { checksPassed++ }
    else {
        checksFailed++
        log(`FAIL: ${label}: expected ${a}n+${b}, got ${anbA}n+${anbB}`)
    }
}

checkAnb('odd', true, 2, 1, 'odd is 2n+1')
checkAnb('even', true, 2, 0, 'even is 2n')
checkAnb('3', true, 0, 3, 'a bare integer is 0n+3')
checkAnb('-3', true, 0, -3, 'and it may be negative')
checkAnb('n', true, 1, 0, 'n alone is 1n+0')
checkAnb('2n', true, 2, 0, '2n is 2n+0, not the integer 2')
checkAnb('-n', true, -1, 0, '-n is -1n')
checkAnb('2n+1', true, 2, 1, '2n+1')
checkAnb('2n-1', true, 2, -1, '2n-1')
checkAnb('-n+3', true, -1, 3, '-n+3')
checkAnb('+3', true, 0, 3, 'a leading plus is allowed')
checkAnb('n+3', true, 1, 3, 'n+3')
checkAnb('', false, 0, 0, 'empty is not An+B')
checkAnb('x', false, 0, 0, 'a letter that is not n')
checkAnb('2n+', false, 0, 0, 'a sign with no integer after it')
checkAnb('2n 1', false, 0, 0, 'a missing sign')
checkAnb('2m+1', false, 0, 0, 'the wrong letter')

finish('css parser')
