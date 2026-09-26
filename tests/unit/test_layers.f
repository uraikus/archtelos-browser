// CSS Cascade 5's `@layer`: the order layers are declared in decides
// which of two layered declarations wins, above specificity and above
// source order.
//
// Every expected colour is Chromium 141's, read with getComputedStyle
// off the same stylesheet.
import ../../src/css/cascade.f
import ../../src/html/parser.f
import ../assert.f

int func layerColor(css:text) {
    cascadeReset()
    Node doc = parseHtmlText('<html><head><style>' + css
        + '</style></head><body><p id="t">x</p></body></html>')
    cascadeAddDocumentStyles(doc)
    computeStyles(doc)
    return findElement(doc, 'p').style.color
}

int layerRed = packColor(255, 0, 0, 255)
int layerBlue = packColor(0, 0, 255, 255)
int layerLime = packColor(0, 255, 0, 255)

void func layerIs(css:text, want:int, label:text) {
    int got = layerColor(css)
    if got == want { checksPassed++ } else {
        checksFailed++
        log(`FAIL: ${label}: got rgb(${colorRed(got)}, ${colorGreen(got)}, ${colorBlue(got)})`)
    }
}

// ---- the order of declaration, not of use ------------------------------
// `@layer a, b;` names both before either has a rule, so `b` is the
// later layer whatever order the blocks come in.
layerIs('@layer a, b; @layer b { #t { color: red } } @layer a { #t { color: blue } }',
        layerRed, 'a statement at-rule fixes the order')

// Without that statement, a layer is declared where it is first used.
layerIs('@layer b { #t { color: red } } @layer a { #t { color: blue } }',
        layerBlue, 'a layer is otherwise declared by its first use')

// Reopening a layer does not move it: `a` stays the earlier one.
layerIs('@layer a { #t { color: red } } @layer b { #t { color: blue } } @layer a { #t { color: lime } }',
        layerBlue, 'reopening a layer keeps the place it had')

// ---- layers rank above specificity and above source order --------------
layerIs('@layer a { p#t { color: red } } @layer b { p { color: blue } }',
        layerBlue, 'a later layer beats a higher specificity in an earlier one')
layerIs('@layer a { p { color: red } p#t { color: blue } }',
        layerBlue, 'inside one layer, specificity decides as it always did')

// ---- unlayered beats layered -------------------------------------------
// However early it comes, a declaration in no layer outranks every
// layered one. This is the check that fails for an implementation that
// treats unlayered as a layer declared first.
layerIs('#t { color: blue } @layer a { #t { color: red } }',
        layerBlue, 'an unlayered rule beats a layered one that follows it')
layerIs('@layer a { #t { color: red } } #t { color: blue }',
        layerBlue, 'and one that precedes it')

// ---- !important reverses the whole order -------------------------------
layerIs('@layer a { #t { color: red !important } } @layer b { #t { color: blue !important } }',
        layerRed, 'important makes the earlier layer the stronger one')
layerIs('#t { color: blue !important } @layer a { #t { color: red !important } }',
        layerRed, 'and makes a layered declaration beat an unlayered one')
// An important declaration still beats every normal one, layers or not.
layerIs('@layer a { #t { color: red !important } } @layer b { #t { color: blue } }',
        layerRed, 'any important beats any normal, whatever the layers')

// ---- nested layers -----------------------------------------------------
// `@layer b` inside `@layer a` is the layer `a.b`, so the statement
// at-rule that named `a.c` before `a.b` decides between them.
layerIs('@layer a.c, a.b; @layer a { @layer b { #t { color: blue } } @layer c { #t { color: red } } }',
        layerBlue, 'a nested layer is named for the one it sits in')

// ---- anonymous layers --------------------------------------------------
// Each `@layer {` makes a layer of its own that nothing can name again,
// so the second is the later one.
layerIs('@layer { #t { color: red } } @layer { #t { color: blue } }',
        layerBlue, 'two anonymous layers are two layers')

// ---- a sub-layer is inside its parent, not beside it -------------------
// CSS Cascade 5 nests `a.b` inside `a`: the sub-layer takes `a`'s place
// in the outer order, and within `a` the sub-layers come first and
// `a`'s own rules last -- the implicit outer layer rule applied one
// level down. This engine read `a.b` as another top-level layer whose
// place was where it was first named, so the two sorted as siblings in
// declaration order and got every case below the other way round.
//
// Each expected colour is Chromium 141's, asked of the same stylesheet.
// The first three are one fact written three ways, which is the point:
// a sub-layer loses to its parent's own rules however the two are
// arranged in the source.
layerIs('@layer a { @layer b { #t { color: lime } } #t { color: red } }',
        layerRed, "a layer's own rules come after its nested sub-layer")
layerIs('@layer a { #t { color: red } } @layer a.b { #t { color: lime } }',
        layerRed, 'and the same written flat, the parent first')
layerIs('@layer a.b { #t { color: lime } } @layer a { #t { color: red } }',
        layerRed, 'and the same with the sub-layer first')

// The other half: a sub-layer belongs to its parent's position, so it
// loses to a top-level layer declared after that parent -- where a flat
// reading would give it the place it was named at and let it win.
layerIs('@layer a, b; @layer a.z { #t { color: red } } @layer b { #t { color: lime } }',
        layerLime, 'a sub-layer of an earlier layer loses to a later layer')

// Two sub-layers of one parent keep their own declaration order, which
// a flat reading also gets right -- so this one is here to pin that the
// fix did not reverse it.
layerIs('@layer a.x { #t { color: red } } @layer a.y { #t { color: lime } }',
        layerLime, 'two sub-layers of one parent keep their order')
// And a grandchild is inside its parent in turn.
layerIs('@layer a { @layer b { @layer c { #t { color: lime } } #t { color: red } } }',
        layerRed, "a grandchild loses to its grandparent's own rules")
layerIs('@layer a.b.c { #t { color: lime } } @layer a.b { #t { color: red } }',
        layerRed, 'written flat, the same')

// ---- what the weights say ---------------------------------------------
// The same order, asserted of the numbers the cascade sorts on, so a
// failure says which tier is wrong rather than only which colour won.
check(matchWeight(false, ORIGIN_AUTHOR, 0, 0, 0) < matchWeight(false, ORIGIN_AUTHOR, 1, 0, 0),
      'a later layer outweighs an earlier one')
check(matchWeight(false, ORIGIN_AUTHOR, 1, 0, 0) < matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 0, 0),
      'and no layer outweighs every layer')
check(matchWeight(false, ORIGIN_AUTHOR, 0, 1000000, 0) < matchWeight(false, ORIGIN_AUTHOR, 1, 0, 0),
      'a layer outranks specificity')
check(matchWeight(true, ORIGIN_AUTHOR, 1, 0, 0) < matchWeight(true, ORIGIN_AUTHOR, 0, 0, 0),
      'important reverses the layer order')
check(matchWeight(true, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 0, 0) < matchWeight(true, ORIGIN_AUTHOR, 1, 0, 0),
      'and puts no layer below every layer')
check(matchWeight(false, ORIGIN_AUTHOR, CASCADE_NO_LAYER, 0, 0) < matchWeight(false, ORIGIN_INLINE, CASCADE_NO_LAYER, 0, 0),
      'inline still beats every author rule')
check(matchWeight(false, ORIGIN_INLINE, CASCADE_NO_LAYER, 0, 0) < matchWeight(true, ORIGIN_AUTHOR, 0, 0, 0),
      'and every important beats every normal')
check(matchWeight(true, ORIGIN_INLINE, CASCADE_NO_LAYER, 0, 0) < matchWeight(true, ORIGIN_UA, CASCADE_NO_LAYER, 0, 0),
      'with important UA above them all')

finish('layers')
