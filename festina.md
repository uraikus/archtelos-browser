# What Festina should gain

This browser exists partly to find out where [Festina](https://github.com/uraikus/festina)
runs out. FINDINGS.md records what happened, with reproductions.
This file is the other half: what the language should gain as a result,
written as proposals rather than complaints, each with what it would
remove from this repository.

Ordered by how much a fix would be worth here.

---

## Forward declarations

A function must be defined before the line that mentions it, which makes
two mutually recursive functions awkward: `calcParseTerm` calls
`calcParseSum` and `calcParseSum` calls `calcParseTerm`, and a signature
with no body is a syntax error.

**Proposal.** Either resolve function names across the whole compilation
unit regardless of order, which is what the one global namespace already
implies, or accept a bodiless signature as a declaration.

**What it would delete here.** Nothing yet: the calc() parser is ordered
to avoid the problem. It is a constraint on how the next recursive
grammar can be written, not a workaround already in the tree.

## Enums

Every small value type in this renderer is a run of `const int`:
`DISPLAY_*`, `BOX_*`, `ALIGN_*`, `DECO_*`, `WS_*`, `LIST_*`, `VALIGN_*`,
`BORDER_*`, `TT_*`, `COMB_*`, `ATTR_*`, `FRAG_*`, `ORIGIN_*`,
`CSSWIDE_*`. They are prefixed by hand because nothing scopes them, and
two of them can quietly share a value: `BOX_IFRAME = 10` was added next
to `BOX_IMAGE = 5` and collided with `BOX_BR = 10` further down the same
run, so every frame was laid out as a line break.

**Proposal.** `enum Box { Block, Inline, Text, ... }`, with values
distinct by construction, the name scoped to the type, and a switch over
one required to be exhaustive.

**What it would delete here.** About sixty `const int` declarations and
every naming prefix on them, plus the class of bug above.

## Integer division and bitwise operators

`/` is float division whatever its operands and there are no bitwise
operators, so a packed integer is written and read through `Math.floor`
and `%`:

```festina
int func specIds(s:int) { return Math.floor(s / (SPEC_BASE * SPEC_BASE)) }
int func decoUnion(a:int, b:int) {
    int out = 0
    if a % 2 == 1 || b % 2 == 1 { out = out + DECO_UNDERLINE }
    ...
}
```

**Proposal.** `a // b` for integer division, and `&`, `|`, `^`, `~`,
`<<`, `>>` on `int`. Both are single-instruction operations that every
systems language has, and their absence shows up wherever a value is
packed: a CSS specificity triple, a text-decoration bit set, a Unicode
character class, a tokenizer's flags.

**What it would delete here.** `specIds`, `specClasses`, `specTypes`
and `decoUnion` in `src/css/style.f` and `src/css/parser.f` become one
expression each, and the comments explaining why they are not become
unnecessary.

## 1 Fix the memory-safety bug in `ascii` aliasing

**Today.** `ascii b = a` — where `a` is another local, a parameter, an
array element, a struct field or a map entry — emits the release for `b`
at scope exit without ever emitting the matching retain. The buffer is
freed while `a` still points at it. The program prints correct answers
and exits 0; valgrind reports an invalid read of size 8 in
`festina_ascii_release`. FINDINGS.md, finding 2, has six minimal
reproductions.

**Proposal.** Emit the retain on the same paths `text` gets its copy and
a struct gets `festina_retain`. This is a bug, not a design question.

**What it removes here.** `dup()` in `src/util/text.f`, and every one of
its call sites — each of which is a copy the program does not need,
allocating and memcpy-ing to work around a missing increment. The CSS
cascade also keeps its property map as `map[text]` and converts on every
read, purely so that no `ascii` is ever aliased out of a container.

**How to catch it.** A two-alias `ascii` case in the leak stress suite,
under AddressSanitizer.

---

## 2 Bound the cost of cycle collection

**Today.** Releasing a value whose *type* can participate in a cycle
runs a synchronous trial deletion that traverses everything reachable
from it. A DOM node's type is cycle-capable, so binding a child to a
local inside a loop — `Node c = n.children[i]` — costs a walk of the
whole subtree, per iteration. With a parent pointer, "the whole subtree"
is the whole document, and tree code becomes quadratic: 8,421 nodes took
1,645 ms to walk instead of 1 ms.

**Proposal, in preference order.**

1. **A `weak` field modifier.** `parent:weak Node` — a reference the
   generated traversal functions skip and the refcount ignores. A tree
   with parent pointers then costs what a tree without them costs. Every
   DOM, scene graph, doubly linked list and parent-pointer AST wants
   this, and it is a compile-time concept with no runtime machinery.
2. **The deferred-root buffer** Festina's own todo.md already describes,
   which makes the amortized cost linear instead of per-release.
3. **Failing both, document the rule**: with a cycle-capable type, bind
   locals only to fresh values, and reach into containers by index.

**What it removes here.** The id-registry pattern that `src/dom/node.f`,
`src/html/parser.f` and `src/layout/layout.f` are all built on: nodes
and boxes carry `parentId:int` and are reached through
`nodeRegistry[id]`, never by binding a node to a local or passing one to
a function. It is written that way for speed, not clarity, and it makes
the selector matcher read like C from 1995:

```festina
// what it has to be
int anc = nodeRegistry[nid].parentId
while anc > 0 {
    if matchFrom(anc, sel, index - 1) { return true }
    anc = nodeRegistry[anc].parentId
}

// what it should be
Node anc = n.parent
while anc != null {
    if matchFrom(anc, sel, index - 1) { return true }
    anc = anc.parent
}
```

---

## 3 Make a name resolve to the innermost binding

**Today.** A parameter or local named like a global function resolves to
the *function*. As a parameter it is silent: a `func` value satisfies a
`text` parameter with no type error, and the program passes a code
pointer where a string was meant. As a local it produces invalid LLVM
IR and the compile fails with `global variable reference must have
pointer type`, naming neither the variable nor the line.

**Proposal.** Resolve names innermost-first, as every other block-scoped
language does. If shadowing a global function is meant to be forbidden,
reject it at the declaration with a real diagnostic — which the compiler
already does for a builtin's name, and only for that: `func f(free:int)`
is refused by the parser at the right column, while `func f(prop:int)`
is not. Either way, a `func[...]` value must never satisfy a `text`
parameter.

**What it removes here.** Four renames made under duress — `prop` →
`styleProp`, `newElement` → `replacement`, and in the flex layout
`free` → `spare` and `contentX`/`contentY` → `flexOriginX`/`flexOriginY`
— and the class of bug that cost an afternoon the first time. The
`contentX` case is the sharpest illustration: two locals named after two
functions in the same file compiled to IR that named the functions where
integers belonged, and the only diagnostic was an LLVM parse error four
thousand lines from the mistake.

---

## 3b Make `==` on two struct references work, or refuse it

**Today.** Structs are references. `a == c` for two struct values passes
the analyzer and emits `icmp eq i64` against a `ptr`; the compile dies
in the LLVM backend with `'%t7' defined with type 'ptr' but expected
'i64'`, naming neither the expression nor the source line.

**Proposal.** Compare the references, which is what a reference type
makes natural and what the emitted code was reaching for anyway. If
identity comparison is meant to be unavailable, reject `==` on struct
operands in the analyzer with a real diagnostic.

**What it removes here.** The `Style.serial` field exists partly so the
cascade's tests can ask whether two elements were handed the same
computed style. The cache needs a serial regardless, but the tests
should not have had to learn that.

---

## 3c Let a color be made from numbers, and a gradient from a list

**Today.** `color` values must be literals, so `fillLinearGradient` —
whose two colour arguments are `color`-typed — cannot be called by any
program whose colours come from data. A browser's colours always do. The
diagnostic suggests `fillStyle(r, g, b)` for runtime colours, which is
right for a flat fill and cannot reach the gradient call. The gradient
also takes exactly two stops and drops alpha, where CSS allows any
number of stops with alpha.

A `color` is also opaque in the other direction: it cannot be
interpolated into a string or read apart, so a pixel cannot be compared
to another with a tolerance.

**Proposal.** Three things, in order of how much they unlock:

1. `rgb(r, g, b)` and `rgba(r, g, b, a)` as expressions producing a
   `color` from runtime integers. The literal form stays for the common
   case; this is the escape hatch.
2. `fillGradient(x0, y0, x1, y1, stops)` taking an array of
   `(offset, color)`, so a multi-stop gradient is one call.
3. `.red`, `.green`, `.blue`, `.alpha` on a `color`, and a string form,
   so a colour can be inspected and printed.

**What it removes here.** `linear-gradient()` is painted as hundreds of
one-pixel bands set with `fillStyle`, and off-axis as hundreds of
clipped polygons, because the one call that would do it exactly cannot
be called. It also removes a test helper that paints a candidate colour
and reads it back in order to compare two colours with a tolerance.

A clip region on the canvas would help the same case independently: with
one, an off-axis band would be a rotated rectangle rather than a polygon
computed by hand.

---

## 3d Open the audio device lazily

**Today.** A program that uses `aud` gets ALSA and libmpg123 on its link
line, dynamically, so the binary carries `libasound.so.2` and
`libmpg123.so.0` as runtime `NEEDED` entries. It will not start on a
machine that lacks them, whether or not it ever plays a sound. The
feature split in `festina/cli.py` already keeps these off the link line
for programs that do not use audio at all — the remaining gap is
programs that use it conditionally.

**Proposal.** Load the audio device through `dlopen` at the first
`.play()`, and answer false from `.isPlaying()` and do nothing on
`.play()` when it is unavailable. The same argument applies to Cairo and
X11 for a program that only ever renders offscreen, but audio is the
sharpest case: a browser can be fully useful with no sound at all.

**What it removes here.** This browser draws an `<audio>` element's
controls and cannot play it, because playing would make a sound library
a condition of the browser starting. With a lazy open it would play
where a device exists and stay silent where none does, which is what a
browser should do anyway.

---

## 4 Give `text` the operations every text program needs

**Today.** `text` has `s[i]`, `.length`, `.charCodeAt`, `.split`,
`.replace`, `.match`, `.trim` and `.toInt`. It has no `slice`,
`indexOf`, `startsWith`, `endsWith`, `toLowerCase`, `toUpperCase`,
`repeat` or `toFloat`. `ascii` has O(1) indexing and `slice`, but
`text.toAscii()` answers null for any non-ASCII input, and every real
web page has an em dash in it.

**Proposal.**

```festina
text.slice(start, end):text          // byte-safe over UTF-8
text.indexOf(needle[, from]):int
text.startsWith(prefix):bool
text.endsWith(suffix):bool
text.toLowerCase():text
text.toUpperCase():text
text.repeat(n):text
text.toFloat():float                 // the sibling toInt() already has
```

None needs a scan per index: they are all byte operations on a UTF-8
buffer.

**What it removes here.** Most of `src/util/text.f` — 334 lines of
string primitives that exist only because the language lacks them —
plus the hand-written decimal parser (`parseNumberAt`) that CSS needs
for `1.5em`, and the three globals it returns through.

---

## 5 Let a function return more than one value

**Today.** A function returns one value, and there are no tuples, no
out-parameters and no multiple assignment. Anything that computes two
results returns them through module globals that the caller reads
immediately afterwards.

**Proposal.** Either multiple return values with destructuring —

```festina
(float value, int end, bool ok) func parseNumber(s:ascii, from:int)
(float v, int end, bool ok) = parseNumber(src, i)
```

— or, more in keeping with a language that already has cheap structs,
make it ergonomic to return one: a struct literal, so a two-field result
does not need a named type and three assignments.

**What it removes here.** `numValue`/`numEnd`/`numOk` in
`src/util/text.f`; `refText`/`refEnd`/`refOk` in `src/html/entities.f`;
`insertParentId`/`insertBeforeIndex` in the parser;
`leadingSpace`/`remainingText`. Each pair is a latent bug: the globals
are live between the call and the read, and nothing stops a second call
from clobbering them.

---

## 6 Let `text` hold a NUL, or give the language a byte buffer

**Today.** `text` is NUL-terminated, so `'a\0b'` is a compile error and
no `text` can carry a NUL. `blob` can, but only for reading —
`byteAt` and `slice` exist, `[i] =` does not.

**Proposal.** The writable byte buffer Festina's own todo.md lists as
open: a mutable, indexable `bytes` type with `[i]` assignment. A parser
would then run on bytes throughout and never need the ASCII-safe
pre-pass at all.

**What it removes here.** `src/html/decode.f` entirely — the U+0001
sentinel encoding that rewrites non-ASCII input so it can live in an
`ascii`, and the matching expansion in the tokenizer. It would also
un-skip the 98 conformance cases whose inputs contain a NUL, which are
skipped only because the test data cannot be represented.

---

## 7 Distinguish an empty string from null

**Today.** `'' == null` is `true`, in a local, a struct field, an array
element and a map value. A NUL-terminated `char*` with no header cannot
tell them apart.

**Proposal.** A static empty-string sentinel the runtime recognizes, so
`''` round-trips through containers and compares unequal to `null`. If
that is too costly, say so in the specification next to "`null` reads
0" — it is currently undocumented and surprising.

**What it removes here.** The parallel `present:map[bool]` that every
DOM element and every tokenizer token carries purely to answer "does
this attribute exist", because `<input checked>` has an attribute whose
value is the empty string. That is one extra hash table per element.

---

## 8 Make a struct field readable as null

**Today.** A struct-typed field is created empty the first time it is
reached, so `if node.next != null` is always true, and
`x.field = null` followed by `x.field == null` is `false`.

**Proposal.** Vivify on write and on member access, not on `== null`.
Optional references are ordinary in tree and graph code, and every
workaround for this is a parallel boolean.

**What it removes here.** `hasNot:bool` beside `notSel:Compound` in the
selector parser, and the general rule that every optional reference in
this codebase is an id that is 0 when absent.

---

## 9 Namespaces, or at least a module-private declaration

**Today.** Every imported file's declarations join one global scope.
Two modules cannot both define `newFragment`; the DOM's fragment
constructor and the layout engine's line-box fragments collided, and one
had to be renamed. Globals are also not hoisted, so a module-level
variable must be declared above its first use *and* in the lowest file
that uses it, while functions and types are hoisted everywhere.

**Proposal.** Either real module namespaces (`import dom.node as dom`,
`dom.newFragment()`) or, much cheaper, a `private` modifier that keeps a
declaration out of the global scope. Hoisting globals the way functions
are hoisted would remove the second half of the problem on its own.

**What it removes here.** Nothing structural, but it removes the
category of edit that renames something in one file because an unrelated
file grew a function of the same name.

---

## 10 Smaller things, each a real cost

| Want | Why it came up |
|---|---|
| `blob.toImg()` | An image fetched over HTTP can only be decoded by building an `http` literal whose body is the blob and calling `.toImg()` on it. |
| `fontAscent()` / `fontDescent()` | Text metrics give an advance width and an inked height, and nothing else, so every baseline in `src/layout/layout.f` is placed with hard-coded DejaVu ratios. Any other font is laid out slightly wrong. |
| A clip region on the canvas | `overflow: hidden` cannot be implemented. Everything else the canvas needs for a browser is already there. |
| A settable window title | The page title has to live in the status bar. |
| `ascii.toInt()` | The semantic analyzer accepts it; codegen rejects it with `cannot access field 'toInt' on ascii`. `a.toText().toInt()` works. |
| Bitwise operators and hex literals | Colors are packed with `*`, `/` and `%`, and 148 CSS color constants are generated as decimal because there is no `0xRRGGBB`. |
| `[[:space:]]` documented, and `\n` in a regex literal | `\n` matches the letter `n`. `/[ \t\n]/` matches the letters t, n and backslash, which silently ate characters out of every text node until it was found. |
| `FESTINA_TARGET_CPU=generic` | The backend compiles for the host CPU's exact features. On an AVX-512 machine every valgrind run dies with SIGILL before `main`, and valgrind is the tool that finds items 1 and 2 on this list. `tools/festina-generic` monkeypatches the compiler to work around it. |

---

## What Festina got right

Worth saying, because this document is otherwise a list of gaps.

- **A 2,231-entry map literal works**, and looks up in constant time.
  The generated character reference table is 2,248 lines of source and
  costs nothing at runtime. It is not free at compile time — it accounts
  for 4.2 s of this project's 9.1 s build, against 0.6 s for a one-line
  program — so a faster path for large literal tables would be welcome.
- **`ascii` is the right primitive for a parser.** O(1) indexing,
  compile-time literals for keyword comparisons, and a table of immortal
  single-character values so a scan allocates nothing. The tokenizer is
  a straightforward scanner because of it.
- **Structs with zero values** make a 40-field computed `Style` free to
  create: the cascade writes only what changed, and everything else
  reads as its initial value.
- **The canvas is complete enough for a browser**: `translate` for
  scrolling, `fillAlpha` for opacity, `curveTo` for rounded corners,
  `saveCanvas` for headless screenshots, `getPixelColor` so tests can
  check real pixels with no display.
- **Template literals span lines**, which is how the user-agent
  stylesheet is embedded as plain readable CSS.
- **The compiler is quick and its diagnostics are precise.** 12,978
  lines in 9.5 seconds, over half of which is one generated table, and
  `file:line:column` on every error.
- **The result is one 2.3 MB native binary** that starts in 6 ms,
  against 448 ms for the browser it is measured beside.
