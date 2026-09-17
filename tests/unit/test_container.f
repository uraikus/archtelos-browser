// CSS Conditional 4: `@container` asks about the size of an ancestor
// rather than the viewport, so the same component can lay itself out
// differently in a wide column and a narrow one.
//
// Every expectation is Chromium 141's, read with getBoundingClientRect
// off the same stylesheet: the probe is a paragraph whose height a
// matching rule sets to 50px, against the 20px line it is otherwise.
//
// Answering a query needs the container's size, which is known only
// after layout, so this is the one feature here that lays the document
// out twice. What makes one extra pass enough rather than a loop is
// `container-type` itself: it contains the container's size, so the
// answer cannot change because of what the rules it gates then do.
import ../../src/layout/layout.f
import ../../src/html/parser.f
import ../assert.f

const text CQ_HEAD = '<!doctype html><html><head><style>'
    + 'body{margin:0;font:16px/20px monospace;width:600px} p{margin:0}'

Box func cqFind(b:Box, id:text) {
    if b.kind != BOX_TEXT && b.kind != BOX_ANON && b.node != null
        && getAttr(b.node, 'id') == id { return b }
    for int i = 0, i < b.children.length, i++ {
        Box f = cqFind(b.children[i], id)
        if f != null { return f }
    }
    return null
}

// The height of #t, given the extra CSS and the markup.
int func cqHeight(css:text, markup:text) {
    cascadeReset()
    cssViewportWidth = 600
    Node doc = parseHtmlText(CQ_HEAD + css + '</style></head><body>'
        + markup + '</body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    Box root = layoutDocument(doc, 600)
    Box t = cqFind(root, 't')
    return t == null ? -1 : t.h
}

const text CQ_WIDE = '<div style="width:400px;container-type:inline-size"><p id="t">x</p></div>'
const text CQ_NARROW = '<div style="width:200px;container-type:inline-size"><p id="t">x</p></div>'
const text CQ_MIN300 = '@container (min-width: 300px) { #t { height: 50px } }'

// ---- 1. the query is answered against the container -------------------
checkEqInt(cqHeight(CQ_MIN300, CQ_WIDE), 50, 'a container wide enough matches')
checkEqInt(cqHeight(CQ_MIN300, CQ_NARROW), 20, 'and a narrower one does not')
// The unmatched height is the line box, which is what says the rule was
// dropped rather than applied with a different value.
checkEqInt(cqHeight('', CQ_WIDE), 20, 'with no rule at all it is one line')

// ---- 2. it takes a container to ask ------------------------------------
checkEqInt(cqHeight(CQ_MIN300,
    '<div style="width:400px"><p id="t">x</p></div>'), 20,
    'an ancestor that is not a container answers nothing')
checkEqInt(cqHeight(CQ_MIN300,
    '<div style="width:400px;container-type:normal"><p id="t">x</p></div>'), 20,
    'and `container-type: normal` is not one')
// The container is not inside itself, so a query never styles it.
checkEqInt(cqHeight(CQ_MIN300,
    '<div id="t" style="width:400px;container-type:inline-size">x</div>'), 20,
    'a container is not queried about itself')

// ---- 3. the nearest container answers ----------------------------------
checkEqInt(cqHeight(CQ_MIN300,
    '<div style="width:400px;container-type:inline-size">'
    + '<div style="width:100px;container-type:inline-size"><p id="t">x</p></div></div>'), 20,
    'the nearest container answers, even when a wider one encloses it')

// ---- 4. names --------------------------------------------------------
const text CQ_NAMED = '@container card (min-width: 300px) { #t { height: 50px } }'
checkEqInt(cqHeight(CQ_NAMED,
    '<div style="width:400px;container-type:inline-size;container-name:card">'
    + '<p id="t">x</p></div>'), 50, 'a named query matches the container of that name')
checkEqInt(cqHeight(CQ_NAMED,
    '<div style="width:400px;container-type:inline-size;container-name:other">'
    + '<p id="t">x</p></div>'), 20, 'and not one of another name')
checkEqInt(cqHeight(CQ_MIN300,
    '<div style="width:400px;container-type:inline-size;container-name:card">'
    + '<p id="t">x</p></div>'), 50, 'an unnamed query matches a named container')
// A named query looks past a nearer container that does not carry the
// name, which is the whole point of naming one.
checkEqInt(cqHeight(CQ_NAMED,
    '<div style="width:400px;container-type:inline-size;container-name:card">'
    + '<div style="width:100px;container-type:inline-size"><p id="t">x</p></div></div>'), 50,
    'a named query skips a nearer container without the name')

// ---- 5. the content box is what is measured ----------------------------
// 320px of content inside 20px of padding each side is a 360px border
// box. Chromium answers 320: a query at 310 matches and one at 340 does
// not, and with `box-sizing: border-box` the content is 280 and a query
// at 300 does not match either.
const text CQ_PADDED = '<div style="width:320px;padding:20px;container-type:inline-size">'
    + '<p id="t">x</p></div>'
checkEqInt(cqHeight('@container (min-width: 310px) { #t { height: 50px } }', CQ_PADDED), 50,
           'the content box is wide enough at 310')
checkEqInt(cqHeight('@container (min-width: 340px) { #t { height: 50px } }', CQ_PADDED), 20,
           'and not at 340, which only the border box would reach')
checkEqInt(cqHeight(CQ_MIN300,
    '<div style="width:320px;padding:20px;box-sizing:border-box;container-type:inline-size">'
    + '<p id="t">x</p></div>'), 20,
    'a border-box width leaves 280 of content, which 300 does not reach')

// ---- 6. which axes a container can answer about ------------------------
// `inline-size` contains one axis, so it can only answer about that one;
// a height query against it never matches however tall it is.
const text CQ_MINH = '@container (min-height: 300px) { #t { height: 50px } }'
checkEqInt(cqHeight(CQ_MINH,
    '<div style="width:400px;height:400px;container-type:inline-size">'
    + '<p id="t">x</p></div>'), 20,
    'an inline-size container cannot answer a height query')
checkEqInt(cqHeight(CQ_MINH,
    '<div style="width:400px;height:400px;container-type:size">'
    + '<p id="t">x</p></div>'), 50,
    'and a size container can')

// ---- 7. the condition syntax is Media Queries 4's ----------------------
checkEqInt(cqHeight('@container (width > 300px) { #t { height: 50px } }', CQ_WIDE), 50,
           'the range form works')
checkEqInt(cqHeight('@container (width < 300px) { #t { height: 50px } }', CQ_WIDE), 20,
           'and answers the other way round')
checkEqInt(cqHeight('@container (300px < width < 500px) { #t { height: 50px } }', CQ_WIDE), 50,
           'and with both ends')
checkEqInt(cqHeight('@container (min-width: 300px) and (max-width: 500px) { #t { height: 50px } }',
           CQ_WIDE), 50, '`and` joins two conditions')
checkEqInt(cqHeight('@container (min-width: 900px) or (min-width: 300px) { #t { height: 50px } }',
           CQ_WIDE), 50, '`or` takes either')

// ---- 8. a rule inside cascades as any other rule does ------------------
// `@container` gates a rule; it adds nothing to its weight. A selector
// outside it with a higher specificity wins either way round.
checkEqInt(cqHeight('#t { height: 30px } @container (min-width: 300px) { .c { height: 50px } }',
    '<div style="width:400px;container-type:inline-size"><p id="t" class="c">x</p></div>'), 30,
    'a higher specificity outside the query beats a lower one inside it')
checkEqInt(cqHeight('@container (min-width: 300px) { .c { height: 50px } } #t { height: 30px }',
    '<div style="width:400px;container-type:inline-size"><p id="t" class="c">x</p></div>'), 30,
    'whichever order they are written in')
checkEqInt(cqHeight(CQ_MIN300 + ' @container (min-width: 200px) { #t { height: 70px } }',
    CQ_WIDE), 70, 'and of two matching queries the later rule wins')

// ---- 9. nested containers settle ---------------------------------------
// A query on an outer container can change the size of an inner one,
// and the inner one's own query then has to be asked again against the
// size it ended up with. Chromium resolves that; one pass of answering
// would not, because it would have measured the inner container before
// the outer query had widened it.
const text CQ_NEST = '<div class="outer"><div id="mid" class="mid"><p id="t">x</p></div></div>'
const text CQ_NEST_BASE = '.outer{width:400px;container-type:inline-size}'
    + '.mid{width:100px;container-type:inline-size}'

checkEqInt(cqHeight(CQ_NEST_BASE + CQ_MIN300, CQ_NEST), 20,
           'a narrow inner container does not satisfy the query')
checkEqInt(cqHeight(CQ_NEST_BASE
    + '@container (min-width: 300px) { .mid { width: 350px } }' + CQ_MIN300, CQ_NEST), 50,
    'and once an outer query has widened it, it does')
// The other direction: an outer query that narrows a wide inner
// container takes the inner query back off again.
checkEqInt(cqHeight('.outer{width:400px;container-type:inline-size}'
    + '.mid{width:350px;container-type:inline-size}'
    + '@container (min-width: 300px) { .mid { width: 100px } }' + CQ_MIN300, CQ_NEST), 20,
    'and one that narrows it takes the answer back')

finish('container queries')
