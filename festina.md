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

## 3e Give an image the canvas's path API

**Today.** An `img` is a drawable surface — `drawRect`, `drawText`,
`drawCircle`, `drawImage`, transforms, a state stack — and it clips at
its own bounds, which makes it the clip region the canvas does not have.
It has no path API at all: `beginPath`, `moveTo`, `lineTo`, `curveTo`,
`closePath`, `fillPath` and `strokePath` exist only at the canvas level.

**Proposal.** Put the same seven calls on `img`, as `_IMAGE_LAYER_OPS`
already does for `translate`, `saveState` and the rest. They are the
same Cairo calls against a different surface.

**What it removes here.** `overflow: hidden` is implemented by painting
the clipped subtree into an image, and inside such a subtree a
`border-radius` is drawn square because the rounded rectangle is a
bezier path. Nothing else about the clipped subtree is approximate.

A canvas-level clip region would solve the same problem from the other
end, and would be faster — no intermediate surface to allocate and
blit — but the path API is the smaller change and unlocks more.

---

## 3f Read an HTTP body to its `Content-Length`

**Today.** `req.send()` returns the right bytes for any response, and
takes thirty seconds to do it whenever the response exceeds 64 KiB in
total. The read loop ends at EOF; a keep-alive server never sends one;
the 30 second `SO_RCVTIMEO` is what actually ends the read. A 640 KB
page that `curl` fetches in 53 ms costs 30.8 seconds.

**Proposal.** End the read at `Content-Length` when the response
declares one, and at the terminating zero-length chunk when it is
chunked — both already parsed elsewhere in the same file. Keep the
timeout as the backstop it was meant to be.

**What it removes here.** The browser becomes able to load a real web
page. At present every page over 64 KiB — which is most of them — costs
half a minute, and the benchmark server has to stay under the limit to
measure anything at all.

---

## 3g Send the query string

**Today.** `req.send()` builds its request line from the URL's path and
drops the query: `http://host/page?a=1` is sent as `GET /page`. The
query is parsed into the URL value and then not used. `req.code` is 200
and `req.url` is unchanged, so nothing observable says the request was
altered.

**Proposal.** Append the query to the request-line target. Failing that,
throw on a URL carrying a query, the way an unresolvable host throws —
answering a different URL silently is the worst of the options.

**What it removes here.** Every search, every `?v=` cache-buster, every
paginated link. A browser has no way to compensate, because the URL is
the only input `send()` takes.

---

## 3h Let a caller wait for a worker's answer

**Today.** `drain()` waits for a worker to finish but yields nothing;
`reply`/`callback` and worker-to-main `postMessage` both deliver through
main's event loop, which straight-line code never reaches. A program
that wants a worker's result *here* has one option: post a
manually-managed `T?`, which crosses by reference, let the workers write
into it, and use `drain()` as the barrier. That is what this browser's
preload scanner does — uncounted shared mutable memory, reached through
a hole in the ownership model, because the supported mechanism cannot
express the wait.

**Proposal.** A blocking `worker.ask(x):Reply`, and `pool.askAll(xs):arr[Reply]`
for the fan-out case. The runtime already has both halves: `drain()`
blocks, and `reply` types the answer.

**What it removes here.** `src/net/preload.f`'s shared `PreloadBatch?`
and its `free`, and with them the only place in this program where two
threads write the same memory.

---

## 3i Let a thread body call a pure function, and let a pool instance know its index

**Today.** A thread body may not call any top-level function, and
`NAME[i]` cannot learn its own `i`. A pool that divides work between its
instances is therefore impossible, and the fallback — N separately named
threads — is N copies of the same body differing in one literal.

**Proposal.** Either half fixes it. Allow a thread body to call a
top-level function that touches no global (the analyzer already knows
which those are), or expose the instance index to the body as
`self.index`.

**What it removes here.** `src/net/preload.f` carries the same eleven
line HTTP fetch four times, at offsets 0, 1, 2 and 3. One of them would
do.

---

## 3j Start a thread when it is first used

**Today.** Every declared thread starts before the first top-level
statement, whether the program goes on to use it or not. Because glibc's
`malloc` gives up its single-threaded fast path permanently at the first
`pthread_create`, that start makes allocation-heavy code about 9% slower
for the life of the process — measured on an allocation-only probe, and
not reproduced on an allocation-free one. Killing the threads
afterwards does not give it back.

**Proposal.** Create a declared thread lazily, on the first
`postMessage`, `giveRequest` or `live` addressed to it. `on load()`
runs then rather than at start-up, which is the only visible change and
is what "the thread started" already means. A program that declares a
worker for a case that does not arise would pay nothing.

**What it removes here.** The preload scanner's four workers cost the
51 KB benchmark page 4 ms, and that page is a local file that dispatches
no prefetch at all. Every `file://` page in this browser pays for a
network feature it never reaches. There is no way to write around it:
the declaration is what starts the thread.

---

## 3k Give an image `drawImage`'s source rectangle

**Today.** The canvas takes three forms of `drawImage`: the whole image
at a point, the whole image scaled into a box, and a source rectangle
scaled into a destination rectangle. An `img` used as a destination
takes only the first two — `img.drawImage() expects 3 or 5 argument(s),
got 9`.

**Proposal.** Add the nine-argument entry to `_IMAGE_LAYER_OPS`
alongside the three- and five-argument ones it already has. The runtime
call it needs is the image-surface counterpart of the canvas's own, and
nothing about the drawing differs.

**What it removes here.** The source rectangle is how a drawable surface
paints part of an image rather than all of it, so without it on an image
destination, clipping a scaled draw inside a layer needs a whole extra
image to draw into and blit back. `object-fit: cover` and `object-fit:
none` both put content outside the content box by construction and have
to cut it off there; with the nine-argument form this would be one call
and no allocation. Painting into an image rather than the canvas is the
ordinary case, not the exotic one — every element inside an opacity
group or an `overflow: hidden` ancestor is doing it.

---

## 3l Give a font a real weight, and a way to load one

**Today.** `changeFont(px, style, family)` decides the weight by
searching the style string for `bold`, and stores it in a
`cairo_font_weight_t`, which has two members. Every numeric weight
measures identically to `normal` — `700` included — and `semibold`
comes out bold because the word contains `bold`. `cairo_select_font_face`
is Cairo's toy API, so the family is whatever the system already has and
no font file can be loaded.

**Proposal.** An overload taking the weight as a number —
`changeFont(px, weight, italic, family)` — resolved through FontConfig or
`cairo_ft_font_face_create_for_ft_face`, which is also the call that
would let a font be loaded from a file or a blob.

**What it removes here.** CSS has nine font weights and this browser can
render two of them, so 400 and 500 look the same and so do 600 and 900.
The cascade already computes the right number; there is nowhere to put
it. And `@font-face` — a page shipping its own typeface, which is most
of the modern web — cannot be implemented at all, which is why CSS Fonts
3 is the one roadmap item blocked outright rather than merely unstarted.

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
| A clip region on the canvas | `overflow: hidden`, background tiling, `object-fit` and `background-clip` all clip by painting into an intermediate image the size of the clip and blitting it back, because an image clips at its own bounds and the canvas cannot. Each one costs an allocation and a composite that a clip region would not, and each new feature that needs a clip adds another. |
| A settable window title | The page title has to live in the status bar. |
| `ascii.toInt()` | The semantic analyzer accepts it; codegen rejects it with `cannot access field 'toInt' on ascii`. `a.toText().toInt()` works. |
| Bitwise operators and hex literals | Colors are packed with `*`, `/` and `%`, and 148 CSS color constants are generated as decimal because there is no `0xRRGGBB`. A decimal colour constant is one no reader can check: `COLOR_VISITED` sat at `4283761785` beneath a comment reading `#551a8b`, which is `4283767435`, and every visited link was painted the wrong purple until a test compared the constant against the standard's `VisitedText`. |
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

---

## 3m Check an `arr` index

**Today.** An index past the end of an `arr` is unchecked. `arr[int]`
returns whatever follows the buffer, which is often a plausible number;
`arr[text]` reads a garbage pointer and `strdup` segfaults on it
(FINDINGS.md, finding 32). Neither is a diagnostic, and the silent one
is the common one.

**Proposal.** Bounds-check the index and abort with the index, the
length and the source position — the same shape of message the compiler
already produces for a type error. Where the cost matters, an explicit
unchecked accessor, or a build flag that removes the check, keeps it
opt-in rather than absent; the check is a compare and a branch against a
length the runtime already stores beside the buffer.

**What it removes here.** A test in this repository asked a helper for
the rows a decoration painted on, got an empty list because the feature
was not implemented yet, read `[0]` from it and reported a row number it
had never found. The failure it printed named a number in the trillions,
which is the only reason anybody looked. Every list of coordinates in
the layout and paint code is an `arr[int]`, and every one of them is one
unguarded index away from the same thing.

---

## 3n Give the canvas a matrix

**Today.** The canvas composes its transform from `translate`, `rotate`
and `scale`, and nothing takes a matrix (FINDINGS.md, finding 33). The
runtime already holds a `cairo_matrix_t`; Cairo already has
`cairo_transform` and `cairo_set_matrix`. `translate` also takes
integers, so a fractional offset cannot be expressed on its own.

**Proposal.** `transform(a, b, c, d, e, f)` to multiply the current
matrix by another and `setTransform(a, b, c, d, e, f)` to replace it,
both taking floats, and a float-taking `translate`. Six doubles straight
into `cairo_matrix_init` and one call each.

**What it removes here.** CSS has six two-dimensional transform
functions and this browser can render four. `skew()` is a shear, which
no composition of the three available calls produces, and `matrix()` is
the matrix itself; both are dropped. A page that lays a heading out on a
slant, or that ships a matrix straight from a design tool, renders
upright.

---

## 3o Reject an unknown escape, and accept `\u`

**Today.** `\t`, `\n` and `\\` are the escapes the lexer knows; every
other backslash sequence silently loses its backslash, so `'\u2026'` is
the five characters `u2026` (FINDINGS.md, finding 34). There is no
diagnostic.

**Proposal.** Two changes, either of which alone is worth having. Make
an unrecognised escape an error, which is what the silent case costs
nothing to catch. And accept `\uXXXX` and `\u{XXXXXX}`, encoding to
UTF-8 — `text` already holds UTF-8, so this is lexer work and no
runtime change.

**What it removes here.** This browser writes the ellipsis `text-overflow`
appends, the quote characters the user-agent stylesheet supplies, and
every character reference in `named_refs.f` as literal bytes. Each is a
non-ASCII constant that cannot survive a terminal that mangles it or a
patch applied with the wrong encoding, and the language offers no way to
spell it that does.

The nine directional formatting characters of UAX #9 are the case where
literal bytes are not an option at all, because they render as nothing:
a literal holding one is a blank space in the source, and a test whose
subject is an RLE would read as a test of an empty string. `bidi.f`
names their code points as decimal constants and turns one into text
with `cp.toChar()`, through a `bidiControl` function whose only purpose
is to give the character a name a reader can see. `\u202b` would be
that name.

---

## 3p Let a program read a pixel's channels

**Today.** `img.getPixelColor(x, y)` returns a `color`, and a `color`
supports equality and nothing else — no `.r`, no `.toInt()`, no packed
form (FINDINGS.md, finding 35). A program can ask whether a pixel is a
particular colour and can never ask what colour it is. Equality is also
the only relation, so no search recovers it: with no ordering there is
no binary search, and trying candidates is 256³ comparisons per pixel.

**Proposal.** Either of these, and ideally both:

```festina
color c = layer.getPixelColor(x, y)
int r = c.r          // 0..255
int g = c.g
int b = c.b
int a = c.a

int packed = layer.getPackedPixel(x, y)   // 0xAARRGGBB
```

The second is the one this browser would use directly, its own colour
model already being a packed integer (`src/util/color.f`). Neither asks
the runtime for anything it does not have: the bytes are in the surface,
and `getPixelColor` already reaches them accurately enough to
distinguish `rgb(200, 100, 50)` from `rgb(201, 100, 50)`.

**What it unlocks here.** CSS Filter Effects 1, entirely. `grayscale()`,
`sepia()`, `saturate()`, `hue-rotate()`, `invert()`, `brightness()` and
`contrast()` are each a function from a pixel's channels to new ones,
and every other piece is already in place: the subtree is painted into
an image by the same device `clip-path` and `overflow: hidden` use, the
specification's matrices have been derived and checked against Chromium
on twenty-seven cases (todo.md keeps the table), and `img.drawPixel`
writes the result back. The pass over the pixels is a dozen lines. It is
one accessor away, and it is the only specification in the CSS snapshot
that this browser is prevented from implementing by the language rather
than by the work.

## 3q Let a program choose how an image is scaled

`drawImage` scales bilinearly and nothing can change that (FINDINGS.md,
finding 36). The runtime already sets a Cairo pattern to do the blit,
and Cairo's filters are one call away:

```c
cairo_pattern_set_filter(pattern, CAIRO_FILTER_NEAREST);
```

What a program needs is a way to say which. Either a canvas-state call,
matching how `fillStyle` and `fillAlpha` already work —

```festina
imageFilter('nearest')      // or 'smooth', the default
drawImage(sprite, 0, 0, 64, 64)
imageFilter('smooth')
```

— or a trailing argument on `drawImage`, matching how `drawRect` takes
an optional border colour. The state call is the better fit for this
browser, which paints many images in one pass and would set it once per
box from the computed style.

**What it unlocks.** `image-rendering`, whose three values are exactly
this choice, and any program that magnifies a small image on purpose:
sprite sheets, tile maps, pixel art, a zoomed screenshot. A blurred
32x upscale of a 2x2 image is not a stylistic preference, it is the
wrong picture.

## 3r Let two struct values be compared

`a == null` compiles and `a == b` does not (FINDINGS.md, finding 37):
the null comparison is special-cased, and the general one reaches the
integer path, which is handed a pointer and emits LLVM IR that will not
parse. The error a program sees is not about its own code at all:

```
LLVM IR parse error: '%t22' defined with type 'ptr' but expected 'i64'
```

A struct value is a pointer at runtime, so identity is what `icmp eq` on
the two pointers already answers. What is missing is the type check that
routes a struct-to-struct comparison there rather than to the integer
one — the same dispatch the null case already has, with the other
operand a struct instead of a literal.

**Two things would make this whole.** Identity, which is the cheap one
above; and the loud failure in its absence, because a comparison the
language does not support should say so where it is written rather than
in the backend's own parser. An unsupported comparison is a semantic
error with a line number, not IR that fails to load.

**What it unlocks.** Every "is this the same object" question: a hit
test answering which box was found, a cache answering whether it handed
back the value it was given, a test asserting that a lookup returned the
node it was looking for. This browser asks all three through an id field
and calls that a proxy, because a box without an element behind it has
no id and two boxes generated for one element share one.


## 3s Give the wheel its other axis, and every input event its modifiers

`on mouseWheelUp` and `on mouseWheelDown` are the whole of the wheel,
and no event of any kind says whether a modifier key was held while it
fired. Two ordinary gestures are therefore inexpressible: a horizontal
scroll, and any shortcut built on shift-, control- or alt-click.

**The horizontal half is already arriving.** The X11 backend maps
buttons 4 and 5 to the two wheel events and lets everything else through
as an ordinary press and release, so a wheel tilted sideways — or a
trackpad scrolled sideways — reaches the program as `mouseDown` with
button 6 or 7. The data is there under a name that means something else,
and a program that wants it has to know that X11 numbers buttons that
way. The Windows backend reads `WM_MOUSEWHEEL` and nothing reads
`WM_MOUSEHWHEEL`, so the same gesture produces nothing at all there.
Two backends disagreeing about whether an event exists is the part worth
fixing first.

```festina
on mouseWheelLeft(x:int, y:int)  { ... }
on mouseWheelRight(x:int, y:int) { ... }
```

Those two, mapped from X11's buttons 6 and 7 and from `WM_MOUSEHWHEEL`,
would be the whole of it — and would retire a program's need to know
either numbering.

**The modifiers are a separate, larger question**, and the cheap form
would do: a `modifiers:int` on every mouse and key event, a bitmask of
shift, control, alt and the platform's own. Every backend already has it
— `ev.xbutton.state` on X11, `wParam`'s low word on Win32, `NSEvent`'s
`modifierFlags` on Cocoa — and none of it reaches a handler. Adding a
parameter would break every existing handler, so it wants either a new
event shape or a `modifierState()` the handler can call.

**What it unlocks.** Scrolling a box sideways, which is what this
browser wanted it for: a scroll container with a horizontal bar can be
dragged by its thumb but not scrolled by the wheel, and shift-wheel —
the gesture every browser offers for exactly this — cannot be read at
all. Beyond that: shift-click to extend a selection, control-click to
open in a new tab, alt-drag to pan. A browser is made of these.

## 3t Let a list observe a node without owning its subtree

FINDINGS.md, finding 41.

`out.push(node)` costs a walk of everything under `node`. Ten
traversals of a ternary tree, collecting every node into an `arr`, go
1 ms at 40 nodes, 4 at 121, 34 at 364 and **306 at 1093** — three times
the nodes for nine times the time. Collecting the same nodes' `id`
fields into an `arr[int]` is 0 ms at every size, and ten rounds of four
thousand pushes into an `arr[int]`, an `arr[text]` or an `arr` of a
two-field struct are 0, 2 and 5 ms, so neither `push` nor the array's
growth is the cost. It is the ownership the push takes.

It is the same cost findings 1 and 40 record, reached a third way, and
it has the same consequence: a program that works on a graph cannot
gather part of it into a list. This browser wanted the boxes CSS2
§9.9's later steps paint, collected once during its first pass rather
than found again by two more walks of the tree. Written that way it
turned a 20 ms paint into 543. It now writes an integer on each box
instead and has the later passes read it, which works but is a
hand-rolled second index into a structure the language already has.

**Proposal.** An element type that observes rather than owns:

```festina
arr[weak Box] later = []
later.push(c)            // no retain of c's subtree
Box b = later[i]         // null if it has gone
```

`weak` is one spelling; a `borrowed` qualifier scoped to a block would
do as well, and would compose with the borrowed read finding 40 asks
for — the two are the same missing idea, one for a variable and one for
a container. What matters is that a program can name a part of a graph
it is walking without paying for the whole of it, because the walk
already holds it alive.

The alternative Festina leaves is a list of ids and a registry to
resolve them, which is finding 40's cost paid on the way back out.

## 3u Let a local shadow a function of the same name

FINDINGS.md, finding 42. A local variable whose name matches a
top-level function anywhere in the program is replaced by that
function, and the program stops compiling at LLVM IR emission:

```
LLVM IR parse error: main.f:395:20: error: global variable reference
must have pointer type
  %t1 = icmp ne i8 @flagX, 0
```

A global *variable* of the same name is shadowed correctly, so the
resolver already does the right thing for one kind of top-level binding
and not for the other.

**The proposal is the smaller of the two obvious ones.** Make a local
declaration shadow a function binding exactly as it shadows a global
variable — the scope rule the language already implements once, applied
to the other table. That keeps every existing program working, because
a program in which a local currently resolves to a function does not
compile today.

The alternative, rejecting the collision at name resolution with a
message naming both declarations, would be an improvement on the
current diagnostic but a worse language: it would make one module's
choice of function name an error in another module's unrelated local,
which is the coupling the shadowing rule exists to prevent.

Either way the diagnostic is worth fixing on its own. The present one
names a mangled symbol and a line of generated IR, and mentions neither
the local variable, the function, nor the two files involved. A reader
who has not seen it before has no way in but to grep the program for
the symbol.
