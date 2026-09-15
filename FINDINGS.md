# Findings: what building a browser in Festina reveals

This is the report the project exists for. Each entry describes
[Festina](https://github.com/uraikus/festina) as it is today, with a
minimal reproduction where one could be isolated and the workaround this
repository uses. What Festina should *gain* as a result is
[festina.md](festina.md); this file is the evidence.

Measured against Festina 0.44 on Linux x86-64, clang 18, Cairo 1.18.

## Slicing an ascii that came from a slice

`ascii` values returned by `slice()` and `asciiTrim()` alias the buffer
they came from rather than copying it. Taking one slice from such a
value works; taking a second one after the first has been assigned away
does not. In `substituteVars` it ended the program:

```festina
ascii inside = asciiTrim(out.slice(at + 4, end))
ascii name = asciiTrim(inside.slice(0, comma))            // fine
ascii fallback = asciiTrim(inside.slice(comma + 1, inside.length))
// fail: out of memory allocating an ascii
```

Nothing warns, and the failure surfaces as an allocation of an absurd
size inside `asciiTrim`, several frames from the aliasing that caused
it. The fix is to index into the value the caller still holds and never
slice a derived one:

```festina
ascii name = asciiTrim(out.slice(argStart, comma >= 0 ? comma : end))
ascii fallback = comma >= 0 ? asciiTrim(out.slice(comma + 1, end)) : null
```

The same gap bites on assignment, not only on slicing. A parameter is
an alias of the caller's value, so reassigning it releases the caller's
buffer while the caller still holds it:

```festina
ascii func substituteVars(v:ascii) {
    ascii out = v
    ...
    out = joined.toAscii()   // releases the caller's buffer
```

The tests passed; valgrind reported an invalid read of size 8 in
`festina_ascii_release`, which is how the first two memory findings in
this file surfaced as well. The fix is to copy into a value the
function owns before the first reassignment.

All of this is one ownership gap reached from three directions: a live
alias outliving its buffer, a buffer released while a slice of it is
still read, and a parameter reassigned out from under its caller.

## Constants with the same value collide silently

There are no enums, so every small value type here is a run of
`const int` with a naming prefix. Adding one in the middle of such a run
is how `BOX_IFRAME = 10` came to share its value with `BOX_BR = 10`.
Nothing warned: every frame box was then treated as a line break, laid
out as nothing, and the failure showed up four call levels away as a box
with a width of zero.

A type whose values are named and distinct by construction would have
made it a compile error. The cost is not hypothetical — it is the whole
debugging session that found it.

The second shape of the same problem is two *different* vocabularies
under one prefix. `text-align` and `justify-content` both want a value
called "center", so a single `ALIGN_` run would hold `ALIGN_CENTER = 1`
and `ALIGN_CENTRE = 2` meaning different things one letter apart, and
either would type-check in either place. The flex constants are
`BOXALIGN_` for that reason. An enum type per property would make the
prefix discipline unnecessary and the mistake impossible.

## No integer division, and no bitwise operators

`/` is float division whatever its operands, so integer division is
`Math.floor(a / b)` and there is no `a // b`. Packing a specificity
triple into one integer and unpacking it again therefore reads as
arithmetic on floats that happen to be exact:

```festina
int func specIds(s:int) { return Math.floor(s / (SPEC_BASE * SPEC_BASE)) }
```

There are no bitwise operators either, so a bit set is built with `+`
and read with `%`:

```festina
int func decoUnion(a:int, b:int) {
    int out = 0
    if a % 2 == 1 || b % 2 == 1 { out = out + DECO_UNDERLINE }
    if Math.floor(a / 2) % 2 == 1 || Math.floor(b / 2) % 2 == 1 { out = out + DECO_LINE_THROUGH }
    return out
}
```

Both are correct and both cost a reader more than `a / b` and `a | b`
would. `text-decoration` is a bit set in every engine; so are the flags
in a tokenizer and the class of a Unicode code point.

## Summary

| # | Finding | Kind |
|---|---|---|
| 1 | Releasing an alias of a live node of a cycle-capable type walks the whole reachable graph | performance |
| 2 | An `ascii` alias is released without ever being retained | memory-safety bug |
| 3 | A name cannot shadow a function: as a parameter it miscompiles silently, as a local it emits invalid IR | compiler bug |
| 4 | An empty `text` is `null` | semantics |
| 5 | A struct-typed field can never read as `null` | semantics |
| 6 | `text` has no substring, search or case conversion, and `ascii` cannot hold non-ASCII | library gap |
| 7 | `\n` in a regex literal matches the letter `n` | library gap |
| 8 | A function returns one value, and there are no tuples | design |
| 9 | One global namespace across every imported file, and globals are not hoisted | design |
| 10 | `text` cannot hold a NUL | design |
| 11 | No closures | design |
| 12 | `map[T]` cannot hold arrays or maps | design |
| 13 | No bitwise operators, no hexadecimal literals | design |
| 14 | No font ascent or descent | library gap |
| 15 | `ascii.toInt()` is accepted by the analyzer and rejected by codegen | compiler bug |
| 16 | No way to decode an `img` from a `blob` | library gap |
| 17 | Reserved words cannot name fields | design |
| 18 | The backend compiles for the host CPU, which defeats valgrind | tooling |
| 19 | No clipping, no window title | platform gap |

---

## 1 A collector walk on every release of a live alias

Festina reclaims memory by reference counting plus a synchronous
Bacon-Rajan trial deletion, run "on releases of values whose type can
participate in a cycle" (`festina_runtime.c`, "cycle collection"). A DOM
node's type qualifies: it has `children:arr[Node]`. So every release of
a local that aliases a still-live node traverses everything reachable
from that node.

With a parent pointer, everything reachable from any node is the whole
document, and tree code becomes quadratic:

```festina
struct N { id:int  kids:arr[N]  parent:N }

void func visitLocal(n:N) {
    for int i = 0, i < n.kids.length, i++ {
        N c = n.kids[i]          // released at the end of every iteration
        total = total + c.id
        visitLocal(c)
    }
}
void func visitIndex(n:N) {
    for int i = 0, i < n.kids.length, i++ {
        total = total + n.kids[i].id
        visitIndex(n.kids[i])    // a parameter is borrowed, never released
    }
}
```

| nodes | `visitLocal`, parent pointers | `visitIndex` | `visitLocal`, no parent pointers |
|---|---|---|---|
| 1,111 | 30 ms | 0 ms | 0 ms |
| 1,555 | 60 ms | 0 ms | 0 ms |
| 8,421 | 1,645 ms | 0 ms | 1 ms |

The same walk is reachable from a second direction: a function that
*forwards* a node parameter to another call retains it on entry and
releases it on exit. Sampling the process with gdb during a CSS cascade
shows `__festina_release_struct_Node` on the exit path of the selector
matcher, recursing through `festina_cycle_visit_array` — the ancestor
loop was passing `<body>` and `<html>` for every descendant selector it
rejected. A stand-alone benchmark of a forwarded parameter does not
reproduce it, so the exact escape-analysis rule that decides to retain
was not pinned down.

**Workaround.** No back-pointers anywhere. `Node` and `Box` carry
`parentId:int` and are reached through a registry array
(`nodeRegistry[id]`); the hot paths — selector matching, sibling
navigation, the parser's open-element stack — work on ids and read
`nodeRegistry[id].field` inline, never binding a node to a local or
passing one to a function. This is load-bearing enough that CLAUDE.md
forbids adding a parent pointer back.

---

## 2 `ascii` aliases are not retained

The specification says `ascii b = a` shares one buffer and that the type
is reference counted. The compiler emits the release for such a local at
scope exit but no retain when it is initialized from another binding, so
the buffer is freed while its owner still uses it. Programs print the
right answers and exit 0; valgrind reports an invalid read and an
invalid write of size 8 in `festina_ascii_release`.

Each of these reproduces it:

```festina
// (a) a parameter rebound to a local
void func inner(srcIn:ascii) { ascii src = srcIn  log(src) }
inner(base.slice(0, 6))

// (b) a local aliasing another local
ascii a = base.slice(0, 5)
ascii b = a

// (c) a local aliasing an array element
arr[ascii] t = [base.slice(0, 5), base.slice(6, 11)]
ascii x = t[0]

// (d) a local aliasing a struct field
ascii x = d.value

// (e) a local aliasing a map entry
ascii x = m['k']

// (f) a parameter stored into a map, when the caller's argument was a local
void func setProp(m:map[ascii], k:text, v:ascii) { m[k] = v }
```

Safe, and also verified: a local initialized from a literal, a `slice()`
or any call result; a struct field or map entry assigned from a local or
a call result; `arr[ascii].push` of a local; a global assigned from a
local or a parameter; a local aliasing a global. The same shapes with
`text` are all safe, because `text` copies on every binding.

**Workaround.** `dup(s)` in `src/util/text.f` returns a fresh
`s.slice(0, s.length)`, and every alias goes through it. The CSS cascade
keeps its property map as `map[text]` and converts on read, so that no
`ascii` is ever aliased out of a container.

---

## 3 A name cannot shadow a function

```festina
text func prop(a:int) { return 'the function' }
void func show(prop:text) { log(prop) }
show('the parameter')
// error: log() only supports primitive values right now, found func[int]:text
```

Inside `show`, `prop` resolves to the global function. Two bugs: name
resolution does not prefer the innermost binding, and a `func[...]`
value satisfies a `text` parameter with no type error — so a call like
`addMatch(matches, prop, ...)` passes a code pointer where a string was
expected and the "property name" is machine code.

A **local** with a function's name fails differently: the compile aborts
in the backend with

```
LLVM IR parse error: global variable reference must have pointer type
  call void @appendNode(i64 @newElement, i64 %t8551)
```

naming neither the variable nor the source line.

A **builtin's** name is the one case handled well. `int func f(free:int)`
is rejected by the parser, at the right column, with

```
error: expected a parameter name, found free('free')
```

which is what the other two should do. The machinery to reject the name
is there; it is only consulted for builtins.

---

## 4 An empty `text` is `null`

`'' == null` is `true` — in a local, a struct field, an array element
and a map value. `''.length` is 0 and `[''].join('')` is null too. A
NUL-terminated `char*` with no header cannot distinguish the two.

This matters immediately for HTML: `<input checked>` has an attribute
whose value is the empty string, and `attrs['checked'] == null` says it
is absent.

**Workaround.** Every element and every tokenizer token carries a
parallel `present:map[bool]` recording which attribute names exist.

---

## 5 A struct-typed field can never read as `null`

A struct, array or map field is created empty the first time it is
reached, so `if c.notSel != null` is always true, and `x.field = null`
followed by `x.field == null` is `false`: the read re-vivifies the
field. A selector matcher written the obvious way recurses forever on
`Compound.notSel`.

**Workaround.** Every optional reference is either a parallel `bool`
(`hasNot` beside `notSel`) or an id that is 0 when absent.

---

## 6 `text` has no substring, and `ascii` cannot hold non-ASCII

`text` offers `s[i]`, `.length`, `.charCodeAt`, `.split`, `.replace`,
`.match`, `.trim` and `.toInt` — and no `slice`, `indexOf`,
`startsWith`, `toLowerCase`, `toUpperCase`, `repeat` or `toFloat`.
`ascii` has the O(1) indexing and `slice()` a tokenizer needs, but
`text.toAscii()` answers `null` for any non-ASCII input, and every web
page has an em dash somewhere.

**Workaround.** Two of them. `src/util/text.f` is 334 lines
reimplementing the missing string operations, including a decimal parser
because there is no `toFloat`. And `src/html/decode.f` rewrites the raw
bytes before tokenizing: every multi-byte UTF-8 sequence becomes a
U+0001 escape, the decimal code point, and `;`, which the tokenizer
expands again when it emits text. A byte the source cannot otherwise
carry is used rather than `&#N;` so that a literal `&#233;` inside a
`<style>` element stays undecoded, as the standard requires.

---

## 7 `\n` in a regex literal matches the letter `n`

`t.replace(/[ \t\n\r\f]+/g, ' ')` turns "something" into "somethi g":
in a POSIX bracket expression a backslash is literal, so the class
matches the characters `\`, `t`, `n`, `r` and `f`. Outside brackets,
`/\n/` matches the letter `n` rather than a newline — confirmed by a
replacement that mangles every word containing one.

The specification does say "inside `[...]` a backslash is literal",
which is correct and easy to miss; the outside-brackets behaviour is not
documented. `[[:space:]]` is the answer for whitespace, and a literal
newline pattern has to be built at runtime: `regex(10.toChar(), 'g')`.

---

## 8 One value out of a function

There are no tuples, no out-parameters and no multiple assignment, so
anything computing two results returns them through module globals the
caller reads immediately afterwards: `numValue`/`numEnd`/`numOk` for
number parsing, `refText`/`refEnd`/`refOk` for character references,
`insertParentId`/`insertBeforeIndex` for the parser's insertion point.
Each set is live between the call and the read, and nothing prevents a
second call from clobbering it.

---

## 9 One global namespace, and globals are not hoisted

Every imported file's declarations join one global scope, so two modules
cannot both define `newFragment` — the DOM's template-content
constructor and the layout engine's line-box fragments collided, and one
had to be renamed.

Separately, functions and types are hoisted everywhere but **globals are
not**: a module-level variable must be declared above its first use, and
in the lowest file that uses it, or the compile fails with
`unknown variable`. Moving a profiling counter to the bottom of a file
is enough to break the build.

---

## 10 `text` cannot hold a NUL

`'a\0b'` is a compile error and no `text` can carry a NUL. `blob` can,
but only for reading: `byteAt` and `slice` exist, `[i] =` does not.
98 cases of the HTML standard's conformance corpus are skipped for this
reason alone — their input contains a NUL, and the test data cannot be
represented in order to run them.

---

## 11–13 Closures, maps of arrays, bit operations

- **No closures.** `map.forEach` and the timers take the bare name of a
  declared function, so any traversal that accumulates state does so in
  globals. The inline layout keeps its pen, its open inline boxes and
  its pending space in module globals that are saved and restored around
  nested formatting contexts; the tokenizer and the tree builder are
  sets of globals plus functions over them.
- **`map[arr[T]]` is rejected**, so the CSS rule index is `map[Bucket]`
  with `struct Bucket { refs:arr[RuleRef] }`.
- **No `&`, `|`, `<<` or hexadecimal literals.** Colors are packed as
  `a * 16777216 + r * 65536 + g * 256 + b` and unpacked with
  `Math.floorDiv` and `%`; the 148 CSS color names are generated as
  decimal integers.

---

## 14 No font metrics beyond an inked height

`measureTextWidth` is exact and `measureTextHeight` gives the inked
height of the string. There is no ascent, descent or line gap, so every
baseline is placed with hard-coded ratios for DejaVu (ascent 0.93 em,
descent 0.24 em), and any other font is laid out slightly wrong.

---

## 20 Two struct references cannot be compared

```festina
struct P { x:int }
P a
P c = a
log(a == c ? 'same' : 'different')
// error: LLVM object emission failed:
// LLVM IR parse error: '%t7' defined with type 'ptr' but expected 'i64'
//   %t10 = icmp eq i64 %t7, %t8
```

Structs are references — assigning one and mutating through the copy is
visible through the original — so asking whether two names denote the
same object is a reasonable thing to want. `==` accepts it in the
analyzer and emits `icmp eq i64` against a `ptr`, which is not valid
IR, so the compile dies in the backend naming neither the expression nor
the line. The workaround here is an explicit identity field:
`Style.serial`, assigned from a counter when a style is computed, which
the cache needs anyway.

A reference type needs either a working `==` on identity or a documented
refusal at the point of use. Silently emitting invalid IR is the worst
of the three.

---

## 21 A gradient cannot be built at run time

The canvas has `fillLinearGradient(x0, y0, c0, x1, y1, c1)`, and a
browser cannot use it. Its colour arguments are `color`-typed, and:

```festina
int r = 64
color c = `rgb(${r}, 128, 192)`
// error: a color must come from a literal, so the compiler can resolve
// it once -- write `color name = '...'` and use `name`, or, to choose
// one at runtime, use fillStyle(red, green, blue) with each component
// 0-255
```

A `color` must be a literal. A CSS gradient's colours come from the
document, so they are never literals, and the diagnostic's own advice —
use `fillStyle` — sets a flat colour and cannot reach the gradient call
at all. `fillLinearGradient` is unreachable from any program whose
colours are data.

The second limit is that it interpolates between exactly two stops,
where CSS allows any number, and its runtime uses
`cairo_pattern_add_color_stop_rgb`, so an alpha channel is dropped.

`linear-gradient()` is therefore painted here as a run of one-pixel
bands of flat colour, each set with `fillStyle`. Off the axis it is
worse: there is no clip region on the canvas either, so a band cannot be
drawn as a rotated rectangle and clipped. Drawing it as a polygon does
not work -- `moveTo` and `lineTo` take integers, so abutting diagonal
slivers are anti-aliased against each other and the ramp is stippled --
and it is instead painted as one-pixel-tall horizontal runs, one per row
of the box. Cairo is doing none of the work it is good at.

## 22 A color is opaque

A `color` can be compared for equality and nothing else. It cannot be
interpolated into a string (`error: cannot interpolate a value of type
color`), assigned from an `int`, or read apart into components. So a
test that wants to say "this pixel is within three of that colour"
cannot: it can only ask whether the pixel equals some literal.

The way round is to paint the colour being asked about and read it back:

```festina
fillStyle(r, g, b)              // this does take numbers
drawRect(SCRATCH_X, SCRATCH_Y, 1, 1)
return getPixelColor(SCRATCH_X, SCRATCH_Y) == pixelUnderTest
```

which turns the question into one the language can answer, at the price
of painting a candidate for every value in the tolerance. The gradient
tests do this because two rasterizers disagree by a unit or two: Skia
dithers gradients and Cairo does not.

---

## 23 An image is a drawable surface with a smaller API

An `img` in Festina is not only a picture: it is a surface a program can
draw on, with `drawRect`, `drawText`, `drawCircle`, `drawPixel`,
`drawImage`, a transform and a state stack, and it **clips at its own
bounds** — rectangles and text alike, a glyph cut in half at the edge.
That is how this browser implements `overflow: hidden` even though the
canvas has no clip region: the subtree is painted into an image the size
of the box and blitted back.

What an image does not have is the path API. There is no `beginPath`,
`moveTo`, `lineTo`, `curveTo`, `fillPath` or `strokePath` on one:

```festina
img layer = blankImage(10, 10)
layer.beginPath()
// error: img has no field 'beginPath'
//        (img has .width, .height, .clip() and .resize())
```

So everything drawn through a path is unavailable inside a clipped
subtree, and here that means rounded corners: a `border-radius` inside
an `overflow: hidden` box is drawn square. The fill state *is* shared —
a `fillStyle` set on the canvas applies to a later `img.drawText` — so
it is the geometry that is missing rather than the colour.

The asymmetry is the whole finding. Two surfaces that are drawn on the
same way should be drawn on the same way.

---

## 15–19 Smaller

- **`ascii.toInt()`**: the semantic analyzer accepts it, codegen rejects
  it with `cannot access field 'toInt' on ascii`. `a.toText().toInt()`
  works.
- **Decoding an image from bytes**: an `img` can come from a path, a
  database column or a background load, but not from a `blob` in memory.
  Images fetched over HTTP are decoded by building an `http` literal
  whose body is the blob and calling `.toImg()` on it.
- **Reserved words as field names**: `text`, `free`, `table` and `match`
  cannot name a field or a local, although the specification allows
  reserved words after a `.`. The error is `expected IDENT`.
- **Host-CPU code generation**: `llvm_backend.py` compiles for
  `LLVMGetHostCPUName()` with the host's full feature set. On an
  AVX-512 machine that emits instructions valgrind cannot emulate, so
  every valgrind run dies with SIGILL in something like `vpternlogq`
  before reaching `main` — and valgrind is the only tool that finds
  findings 1 and 2. `tools/festina-generic` patches the two CPU
  accessors to `x86-64` with no features.
- **Platform gaps for a browser**: no clip region, so `overflow: hidden`
  cannot be implemented; no settable window title, so the page title
  lives in the status bar; no cursor shapes; no current directory. Key
  names are the platform's, so Page Down arrives as `Next` on X11.
  Italics need an italic face installed — on a bare Ubuntu container
  DejaVu Sans has none until `fonts-dejavu-extra` is added, which is
  fontconfig's business rather than Festina's.

---

## What holds up

- **`ascii` is the right primitive for a parser**: O(1) indexing,
  compile-time literals for keyword comparisons, and a table of immortal
  single-character values so a character-by-character scan allocates
  nothing.
- **A 2,231-entry map literal** — the standard's complete named
  character reference table — works, and looks up in constant time. It
  is priced at compile time rather than run time: that one table is
  4.2 s of this project's 9.1 s build.
- **Structs with zero values** make a 40-field computed `Style` free to
  create: the cascade writes only what changed.
- **The canvas has what a browser needs**: `translate` for scrolling,
  `fillAlpha` for opacity, paths with `curveTo` for rounded corners,
  `saveCanvas` for headless screenshots, and `getPixelColor` so tests
  can check real pixels with no display.
- **Template literals span lines**, which is how the user-agent
  stylesheet is embedded as readable CSS.
- **Arrow functions as comparators** and a stable `sort()` make
  specificity ordering a one-liner.
- **The HTTP client** handles TLS and chunked responses without
  ceremony, and `try`/`catch` turns a network failure into an error
  page.
- **The compiler is quick and its diagnostics are precise**: 12,978
  lines in 9.5 seconds, `file:line:column` on every error, and a type checker
  that catches mismatched `?:` branches, a `void` used as a value and an
  `int`/`float` mix before anything runs.
