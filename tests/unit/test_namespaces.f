// CSS Namespaces 3.
//
// Every element in an HTML document is in the XHTML namespace, so the
// whole of this specification comes down to one question asked four
// ways: does a selector's namespace part accept that namespace or not.
// The checks are the four spellings against each other, because each
// one alone would pass for a parser that ignored the syntax entirely.
import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

text XHTML = 'http://www.w3.org/1999/xhtml'

// Whether a rule with this selector reaches the <p>, asked by giving
// the rule a colour nothing else sets.
bool func selectorReaches(sheet:text) {
    cascadeReset()
    Node doc = parseHtmlText('<html><body><p id="t">x</p></body></html>')
    cascadeAddAuthorSheet(parseStylesheet((sheet + ' #never { color: #010203 }').toAscii()))
    computeStyles(doc)
    arr[Node] ps = []
    collectElements(doc, 'p', ps)
    // The colour as a number, because the language has no
    // hexadecimal literal (FINDINGS.md, finding 13): #654321.
    return ps[0].style.color == parseCssColor('#654321'.toAscii(), 0)
}

// ---- a selector with no namespace part -----------------------------------
// With no default namespace declared it matches in any namespace, which
// is what makes an ordinary stylesheet work.

check(selectorReaches('p { color: #654321 }'), 'a plain type selector matches')

// A default namespace that is the document's own still matches.
check(selectorReaches('@namespace url(' + XHTML + '); p { color: #654321 }'),
      'and still does under a default namespace the element is in')

// A default namespace the element is not in does not.
check(!selectorReaches('@namespace url(http://example.com/ns); p { color: #654321 }'),
      'but not under a default namespace it is not in')

// ---- a prefixed selector -------------------------------------------------

check(selectorReaches('@namespace h url(' + XHTML + '); h|p { color: #654321 }'),
      'a prefix bound to the document namespace matches')

check(!selectorReaches('@namespace h url(http://example.com/ns); h|p { color: #654321 }'),
      'a prefix bound to another namespace does not')

// An undeclared prefix makes the selector invalid, so it matches
// nothing -- rather than being read as a type selector called `h`.
check(!selectorReaches('q|p { color: #654321 }'), 'an undeclared prefix matches nothing')

// ---- the two wildcards ---------------------------------------------------

check(selectorReaches('*|p { color: #654321 }'), '*|p matches whatever the namespace')
check(selectorReaches('@namespace url(http://example.com/ns); *|p { color: #654321 }'),
      'even under a default namespace the element is not in')

// `|p` is the no-namespace selector, and every element in an HTML
// document has one, so it matches nothing.
check(!selectorReaches('|p { color: #654321 }'), '|p matches nothing in an HTML document')

// ---- the namespace part does not eat the rest of the selector ------------
// A parser that mishandled `|` could drop the class or the combinator
// with it, so both are asked for.

check(selectorReaches('*|p#t { color: #654321 }'), 'a wildcard namespace keeps the id beside it')
check(selectorReaches('body *|p { color: #654321 }'), 'and the combinator before it')

// `*|*` is every element in every namespace.
check(selectorReaches('*|* { color: #654321 }'), '*|* matches everything')

finish('namespaces')
