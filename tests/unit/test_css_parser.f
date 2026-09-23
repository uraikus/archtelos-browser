import ../../src/css/parser.f
import ../assert.f

Stylesheet s1 = parseStylesheet('/* c */ p, div.note > b { color: red; margin : 1px 2px !important }\n#x a[href^="http"]:first-child { display:none }')
checkEq(dumpStylesheet(s1), 'p{1}, div.note > b{1026} { color: red; margin: 1px 2px !important; }\n*#x a[href3http]:first-child{1050625} { display: none; }\n', 'rules, specificity, important')

Stylesheet s2 = parseStylesheet('a:hover { x: 1 } li:nth-child(odd) { y: 2 } p::before { z: 3 } h1 + p ~ em { w: 4 } div:not(.a) { v: 5 } .a.b#c { u: 6 }')
// `a:hover` names a state this engine cannot know, so that rule is
// dropped entirely rather than kept with a selector that can never
// match (Selectors 3 §4). `p::before` is kept: it names a box to
// generate, and its specificity counts the pseudo-element as a type,
// so `p::before` weighs two types.
//
// `:nth-child(odd)` keeps its An+B form -- 2n+1 -- rather than the word
// it was written as, because that is what the matcher works from.
checkEq(dumpStylesheet(s2), 'li:nth-child:2:1{1025} { y: 2; }\np::before{2} { z: 3; }\nh1 + p ~ em{3} { w: 4; }\ndiv:not(*.a{0}){1025} { v: 5; }\n*#c.a.b{1050624} { u: 6; }\n', 'pseudo classes and combinators')

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

// ---- CSS Syntax 3 §4.3: where a `/*` is not a comment ------------------
// Comments are consumed by the tokenizer, so a `/*` inside a string or
// inside an unquoted `url()` is ordinary characters. The scan that
// strips them runs before anything else and has to know the same three
// places the semicolon scan above already knows.
//
// The rule AFTER the one holding it is what these assert on: a comment
// opened by mistake runs to the next `*/`, and where the sheet has none
// it takes everything to the end -- so it is the second rule surviving
// that says the scan stopped where it should.
Stylesheet sq1 = parseStylesheet('p { font-family: "/*" } q { color: red }')
checkEq(dumpStylesheet(sq1), 'p{1} { font-family: "/*"; }\nq{1} { color: red; }\n',
        'a comment opener inside a double-quoted string is not a comment')
Stylesheet sq2 = parseStylesheet("p { font-family: '/*' } q { color: red }")
checkEq(dumpStylesheet(sq2), 'p{1} { font-family: \'/*\'; }\nq{1} { color: red; }\n',
        'nor inside a single-quoted one')
Stylesheet sq3 = parseStylesheet('p { background: url(a/*b.png) } q { color: red }')
checkEq(dumpStylesheet(sq3), 'p{1} { background: url(a/*b.png); }\nq{1} { color: red; }\n',
        'nor inside an unquoted url()')
// The other direction, which is the one a fix can get wrong: a quote
// inside a comment is ordinary text, and a comment ends at the FIRST
// `*/` whatever follows it. So `/* " */` is a whole comment and the
// rule after it survives...
Stylesheet sq4 = parseStylesheet('p { a: 1 } /* " */ q { color: red }')
checkEq(dumpStylesheet(sq4), 'p{1} { a: 1; }\nq{1} { color: red; }\n',
        'a quote inside a comment is part of the comment')
// ...while `/* "*/` ends at that `*/` and leaves a `"` open, which
// swallows the rest of the sheet. Chromium loses the rule there too,
// measured -- so this is what the scan must NOT fix.
Stylesheet sq4b = parseStylesheet('p { a: 1 } /* "*/" */ q { color: red }')
checkEq(dumpStylesheet(sq4b), 'p{1} { a: 1; }\n',
        'and a comment ends at the first terminator, open quote or not')
// A backslash escapes the next character, so the quote here does not
// end the string and the `/*` after it is still inside one.
Stylesheet sq5 = parseStylesheet('p { font-family: "a\\"/*" } q { color: red }')
checkEq(dumpStylesheet(sq5), 'p{1} { font-family: "a\\"/*"; }\nq{1} { color: red; }\n',
        'an escaped quote does not end the string the scan is in')
// The ordinary case still works: a comment between two declarations is
// removed, and one spanning a rule boundary takes what is between.
Stylesheet sq6 = parseStylesheet('p { a: 1; /* gone */ b: 2 } /* r */ q { color: red }')
checkEq(dumpStylesheet(sq6), 'p{1} { a: 1; b: 2; }\nq{1} { color: red; }\n',
        'and a comment that is one is still stripped')

// ---- CSS Syntax 3 §5.4.1: `<!--` and `-->` at the top level ------------
// A CDO and a CDC are ignored where a rule is read. They are the
// wrapper pages once put round a `<style>` element so a browser that
// did not know the tag would not print its contents, and a sheet still
// written that way has to parse as though they were not there.
//
// The rule BESIDE each one is what these assert on: unrecognised, the
// token is swept into the selector next to it and that rule is lost.
Stylesheet cdo1 = parseStylesheet('<!-- p { a: 1 } q { b: 2 } -->')
checkEq(dumpStylesheet(cdo1), 'p{1} { a: 1; }\nq{1} { b: 2; }\n',
        'a sheet wrapped in an HTML comment parses as though it were not')
Stylesheet cdo2 = parseStylesheet('p { a: 1 }\n--> q { b: 2 }')
checkEq(dumpStylesheet(cdo2), 'p{1} { a: 1; }\nq{1} { b: 2; }\n',
        'and a stray CDC between two rules takes neither')
Stylesheet cdo3 = parseStylesheet('p { a: 1 } <!-- q { b: 2 }')
checkEq(dumpStylesheet(cdo3), 'p{1} { a: 1; }\nq{1} { b: 2; }\n',
        'nor a stray CDO')
// A `-->` that follows name characters is not a CDC at all: the ident
// takes the two hyphens, because both are name code points, and the
// `>` that is left is a child combinator. Chromium's `selectorText`
// for `a-->b` is `a-- > b`, asked of it directly rather than inferred
// from a render -- and this is the check that stops a CDC skip from
// cutting such a selector in half.
Stylesheet cdo4 = parseStylesheet('a-->b { c: 3 }')
checkEq(dumpStylesheet(cdo4), 'a-- > b{2} { c: 3; }\n',
        'a `-->` after name characters is a hyphen pair and a combinator')

finish('css parser')
