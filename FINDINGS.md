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

**It keeps happening.** Shape (c) — a local bound to an element of an
`arr[ascii]` — is the natural way to write a loop over the words of a
value, so every new property that splits one reintroduces it:
`background-repeat`, `background-position` and the `flex-flow`
shorthand each arrived with it, and each passed its tests. CSS
Nesting's selector expansion arrived with it too, and there the symptom
was not a quiet leak: the user-agent stylesheet is parsed at the start
of every page, so the double free reached a live buffer and the program
segfaulted before rendering anything. Nothing in
the language, the compiler or the test suite distinguishes the broken
form from the correct one; only valgrind does. The defence is to index
the array at every use — `parts[0] == 'no-repeat'` rather than
`ascii t = parts[0]` — and to run valgrind on any code that splits an
`ascii`, before believing a green suite.

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

**The namespace is global across every imported file (finding 9), so
the two names need never meet in one file, or be written by one
person.** A local named `lineCount` in the layout engine and a
`lineCount` helper in one render suite collided here: nine other suites
that import the same layout engine compiled and ran correctly, and the
tenth failed with

```
LLVM IR parse error: error: global variable reference must have pointer type
  call void @gridMarkOccupied(ptr %t35994, ptr %t35995, i64 @lineCount, i8 %t35996)
```

— the local silently replaced by a reference to the function. Which
programs break depends on which files are linked together, so a name
that is safe today becomes a compile error when an unrelated file gains
a helper, and there is no way to see the collision coming from either
end.

**It is the most frequent obstacle in this codebase.** `lineCount`,
`cell`, `matches` and `doc` each collided while the CSS work below was
being written, and the vocabulary a renderer wants — `cell`, `matches`,
`doc`, `style`, `line`, `row` — is exactly the vocabulary its helper
functions want. Every new helper narrows the set of names the rest of
the program may use for a local, and nothing reports which names are
spent.

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
  decimal integers. The missing literal is not only inconvenient: a
  colour written by hand as a decimal is a colour no reader can check.
  `COLOR_VISITED` stood at `4283761785` under a comment reading
  `#551a8b` for the whole life of the user-agent stylesheet. The two
  disagree — `#551a8b` is `4283767435` — so every visited link was
  painted `rgb(85, 4, 121)`. A hexadecimal literal would have made the
  constant and the comment the same text, and the bug unwritable.

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

## 24 An HTTP response larger than 64 KiB takes thirty seconds

```festina
http req = {'url': 'http://127.0.0.1:8731/bytes65535', 'method': 'GET',
            'headers': {'accept': '*/*'}}
req.send()
log(`${req.toBlob().length} bytes`)
```

Against a local `http.server` answering with `Content-Length` and
HTTP/1.1 keep-alive, the same program measured across a size sweep:

| body | `req.send()` |
|---|---|
| 65 000 bytes | 2 ms |
| 65 535 bytes | 30 521 ms |
| 65 536 bytes | 30 720 ms |
| 320 073 bytes | 31 253 ms |

`curl` fetches the 640 KB case from the same server in 53 ms. The bytes
that come back are correct in every case — it is only the wait that is
wrong, and it is wrong by a factor of about six hundred.

The boundary lies between a 65,000-byte body and a 65,535-byte one,
which is consistent with a 64 KiB limit on the **whole response**,
headers included — the headers here are about 130 bytes. The stall
itself is the runtime's own 30 second socket timeout (`SO_RCVTIMEO`, set
in `runtime/festina_runtime_http.c`). A response that fits in the first
read is returned at once; one that does not is read to completion and
then waited on until the socket times out, because the read loop ends at
EOF rather than at `Content-Length`, and a keep-alive server never sends
EOF.

There is no workaround from Festina. `Connection` is one of the four
headers the runtime always computes itself and never takes from
`headers` (api.md), so a program cannot ask the server to close the
socket, and there is no other lever. For a browser the consequence is
total: the median real web page is well over 64 KiB, so every real page
this browser loads over HTTP costs half a minute. The benchmark server
in `tests/bench.sh` serves under the limit for exactly this reason,
which is a measurement working around a bug rather than measuring it.

---

## 25 The query string is dropped from every outbound request

```festina
http req = {'url': 'http://127.0.0.1:8731/page?a=1&b=2', 'method': 'GET',
            'headers': {'accept': '*/*'}}
req.send()
// the server logs:  GET /page
```

`req.url` is left untouched and `req.code` is 200, so nothing in the
program can tell that the request it made was not the request it asked
for; the server simply answers a different URL. The runtime parses the
URL into components, keeps the query in one of them
(`festina_url_search_params`), and then builds the request line out of
`festina_url_pathname` alone
(`runtime/festina_runtime_http.c:3893`), so the query is parsed and
discarded in the same breath.

Half the web is behind a query string, and a browser cannot put one
back: there is no path or query field on `http` to set separately, and
the URL is the only input `send()` takes. This is not a workaround that
costs something, it is a capability that is absent.

Silence is the aggravating part. A URL the runtime cannot honour should
throw, the way an unresolvable host does.

---

## 26 A worker's answer cannot be collected synchronously

A thread can be given work and `drain()` blocks until it has finished
it, so a program can wait for a worker. What it cannot do is *read what
the worker produced*, because every route back to the caller goes
through the main event loop:

- `worker.reply(x)` runs a `.callback(fn)` on main's thread — from the
  event loop, which straight-line code never reaches. A callback posted
  during a page load fires after the page is laid out and painted.
- `postMessage(x)` from a worker to main is dispatched to main's
  `on message` handler, from the same loop, with the same consequence.
- `drain()` blocks on the *worker's* queue and does not pump main's, so
  it does not help.

Measured: six messages posted to a pool, every instance drained, then
the reply counter read — zero, and not one callback line logged.

The escape is `T?`. A manually-managed value posted to a thread crosses
**by reference** rather than being deep-copied (specification §20.4), so
both sides share one object: the workers write into its arrays, `drain()`
is the barrier, and main reads them afterwards. That is how
`src/net/preload.f` collects prefetched bodies, and it works — but it is
uncounted shared mutable memory reached through a hole in the ownership
model, chosen because the supported mechanism cannot express "wait here
for the answer".

`arr[T?]` is rejected (`?` may not be an element type), so the shared
object cannot be a list of slots; it has to be one struct whose fields
are ordinary arrays.

A blocking `worker.ask(x):Reply` would remove the need for any of this.

---

## 27 A thread body cannot share code, and a pool instance cannot name itself

Two restrictions compose into duplication with no way out.

A thread body may not call a top-level function:

```festina
void func fill(b:Batch?, me:int) { /* ... */ }
thread w0 { on message(worker:thread, msg:Batch?) { fill(msg, 0) } }
// error: 'fill()' cannot be called from inside a thread body
```

and a pool instance addressed as `NAME[i]` has no way to learn its own
`i`, so a pool whose instances must divide work between them cannot
divide it. Together they mean that N workers doing one job are N
copies of that job's code, differing only in a literal. `src/net/preload.f`
carries the same eleven-line HTTP fetch four times, at offsets 0, 1, 2
and 3.

Either restriction alone would be survivable. A thread body that could
call a pure top-level function would need no duplication; a pool
instance that knew its index would need only one body. As it stands the
only way to write a work-dividing pool is to write it once per worker.

---

## 28 A declared thread makes the program non-terminating

A program that declares a thread and then runs off the end of its
top-level statements never exits:

```festina
thread t { on message(w:thread, m:int) { } }
log('done')
// prints 'done', then hangs forever
```

A live thread keeps the program alive (specification §12.1) and a thread
is live from before the first top-level statement until something kills
it. `close(0)` exits cleanly — every live thread is killed on the way
out — so the fix is to end every program explicitly, which is why
`tests/assert.f`'s `finish()` now calls `close()` on success as well as
on failure, and why each conformance runner ends in `close(0)`.

The cost is that declaring a thread anywhere in a program's imports
changes the meaning of falling off the end, for every entry point that
links it, silently. A `main` thread with nothing left to do and no
handler registered is not waiting for anything; it is the top-level
statements that are finished, not the process.

---

## 29 Declaring a thread taxes every allocation in the program

Four worker threads that are asleep, and have never been sent anything,
make allocation-heavy code about 9% slower — everywhere, for the life of
the process.

The probe builds 300 arrays of 400 structs and a map over each,
allocating and releasing throughout. The two programs are identical
except that one declares four threads none of the work touches:

| program | best | median |
|---|---|---|
| no threads | 53 ms | 54 ms |
| four idle threads declared | 58 ms | 63 ms |
| four threads declared and immediately `kill()`ed | 57 ms | 58 ms |

The third row is the one that closes the door: killing the workers
before the work starts does not give the speed back. Whatever changes,
changes when the thread is *created*, and never changes back.

It is not atomic reference counting. The generated code gains no `lock`
prefixes, and the runtime says so itself — "keeps festina_retain/
festina_release non-atomic plain increments" (`festina_runtime.h`). Nor
is it scheduling: the same experiment on an allocation-free arithmetic
loop shows no difference at all.

| program | best | median |
|---|---|---|
| arithmetic only, no threads | 40 ms | 41 ms |
| arithmetic only, four idle threads | 40 ms | 42 ms |

Allocation slows and computation does not, which is the signature of
the C allocator beneath: glibc's `malloc` takes a lock-free path while
a process is single-threaded and abandons it permanently at the first
`pthread_create`. Festina allocates on almost every operation, so the
whole program pays.

What this costs here is measurable and was nearly missed. The preload
scanner's four workers make the 51 KB benchmark page — a local file
that dispatches no prefetch at all — **4 ms slower to render**, a
paired median over twenty interleaved runs of each build, positive in
17 of 20. That is a feature charging the pages that do not use it,
which this project's own rules forbid, and there is no way to avoid it
from Festina: threads start before the first top-level statement and
cannot be created on demand.

A thread that is created when it is first used would cost nothing until
then. That is the fix, and it is not available.

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

---

## 30 An image destination cannot take drawImage's source rectangle

The canvas takes all three forms of `drawImage`: the whole image at a
point, the whole image scaled into a box, and a source rectangle cut out
of the image and scaled into a destination rectangle. An `img` used as a
destination takes only the first two.

```festina
img src = 'tests/fixtures/fit.png'
img dst = blankImage(40, 40)
drawImage(src, 5, 0, 10, 10, 0, 0, 40, 40)      // fine
dst.drawImage(src, 5, 0, 10, 10, 0, 0, 40, 40)  // error
```

```
error: img.drawImage() expects 3 or 5 argument(s), got 9
```

The source-rectangle form is how a drawable surface clips: it is the
only call that paints part of an image rather than all of it. Because
an image destination lacks it, and because the canvas has no clip region
either (finding 23), clipping a scaled draw *inside a layer* needs a
second image — one the size of the clip, drawn into and then blitted —
where the canvas would need no intermediate at all.

That is what `object-fit: cover` does here. The object is larger than
the box by construction, so the overflow has to be cut off at the
content box; with the nine-argument form on an image this would be one
call and no allocation. Every element painted inside an opacity group or
an `overflow: hidden` ancestor is painting into an image rather than the
canvas, so this is the ordinary case on a real page, not the exotic one.

The asymmetry is in the binding rather than the renderer: the canvas
entry point and the image entry point both reach the same drawing
library, and only the image one is missing its nine-argument
counterpart.

---

## 31 A font has two weights, and no way to load one

`changeFont` takes the weight as part of a style string, and the runtime
decides it by looking for one word:

```c
g_font_weight = festina_contains_ci(style, "bold")
                ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL;
```

`cairo_font_weight_t` has exactly those two members, so there is nowhere
for CSS's nine weights to go. Measuring the same string at each of them
shows it:

```festina
int func widthAt(style:text) {
    changeFont(32, style, 'sans-serif')
    return measureTextWidth('Weight')
}
```

| style passed | width |
|---|---|
| `normal`, `100`, `300`, `500`, `600`, `700`, `900`, `lighter` | 114 |
| `bold`, `bolder` | 129 |

Every numeric weight measures as normal, `700` included, because the
only thing the runtime looks for is the substring `bold` — a program
that asks for `700` gets normal silently, and one that asks for
`semibold` gets bold for the wrong reason.

This browser's cascade computes the weight correctly and then has
nowhere to put it: 400 and 500 render identically, and so do 600 and
900. A page that distinguishes its headings by weight alone loses that
distinction entirely.

The same binding closes `@font-face`. `cairo_select_font_face` is
Cairo's *toy* API: it takes a family name and picks from what the system
already has, and there is no call in Festina that loads a font file. A
web font cannot be fetched and used at all.

---

## 32 Reading past the end of an `arr` is unchecked

An index beyond an `arr`'s length is not a range error. What happens
instead depends on the element type, and neither outcome is a
diagnostic.

```festina
arr[int] empty = []
log(`length: ${empty.length}`)
int v = empty[0]
log(`empty[0]: ${v}`)
arr[text] words = []
text w = words[3]
log(`words[3]: ${w}`)
```

```
length: 0
empty[0]: 0
Segmentation fault
```

An `arr[int]` hands back whatever the word after the buffer holds — `0`
here, and not reliably so; the same read in a longer-running program
returned a pointer-sized number. An `arr[text]` reads a garbage pointer
and hands it to `strdup`, which dies. Under valgrind both reads are
visible before the crash:

```
==21112== Invalid read of size 8
==21112==    at 0x1158F0: __festina_main
==21112==  Address 0x4b7c230 is 0 bytes after a block of size 0 alloc'd
...
==21112== Invalid read of size 1
==21112==    at 0x484F226: strlen
==21112==    by 0x4A1C372: strdup (strdup.c:41)
==21112==    by 0x117F4A: festina_text_own
==21112==  Address 0x40 is not stack'd, malloc'd or (recently) free'd
```

The silent case is the dangerous one, and it is the common one, because
`arr[int]` is how this program carries every list of coordinates. A
function that returns an empty `arr[int]` for "nothing found" and a
caller that reads `[0]` without checking `.length` produce a plausible
number rather than a failure — a test written that way passed while
reporting a pixel row it had never found, which is how this was noticed.
The program had no undefined behaviour of its own: an ordinary index on
an ordinary list is enough.

The workaround is discipline — every index guarded by a `.length` test —
which is what a bounds check exists to make unnecessary, and which
nothing in the language or the tooling enforces.

---

## 33 The canvas matrix has no general form

The canvas composes a transform from three calls — `translate(x, y)`,
`rotate(degrees)` and `scale(sx, sy)` — with `saveState`/`restoreState`
around them and `resetTransform` to clear it. There is no call that
takes a matrix, and no shear.

```festina
saveState()
translate(30, 0)
rotate(45.0)
scale(2.0, 2.0)
drawRect(0, 0, 10, 10)     // all fine
restoreState()
setTransform(1.0, 0.0, 0.5, 1.0, 0.0, 0.0)
```

```
error: unknown function 'setTransform'
```

Cairo has `cairo_transform` and `cairo_set_matrix`, and the runtime
already keeps a `cairo_matrix_t` for the three calls it does expose;
what is missing is the entry point, not the capability.

Two CSS transform functions are the general form and cannot be written
without it. `skew(ax, ay)` is a shear, which no composition of
translate, rotate and scale produces. `matrix(a, b, c, d, e, f)` is the
matrix itself. Both are dropped by this browser rather than
approximated, which is the standard's own answer for a transform that
cannot be applied, but it means two of the specification's functions are
closed to it by the binding.

`translate` also takes integers, so a transform cannot move a box by a
fractional pixel:

```
error: translate()'s argument 1 expects int, found float
```

 Composing a scale with a translate hides this — the
matrix multiplies in floating point — but a bare `translate(0.5, 0)` is
not expressible, and neither is the sub-pixel positioning a text layout
wants.

---

## 34 An unknown escape loses its backslash silently

A string literal accepts `\t` and `\n`. Any other backslash sequence is
neither an escape nor an error: the backslash is dropped and what
follows stands.

```festina
text a = '\u2026'
log(`len=${a.length} last=${a[a.length - 1]}`)
```

```
len=5 last=6
```

`\u2026` is the five characters `u2026`. Nothing warns, and the program
runs; `'\q'` is `q` as well. `\t`, `\n` and `\\` are the escapes the lexer
knows, which is what makes the rest silent rather than absent: the
mechanism is there and an unrecognised sequence falls out of it.

This is finding 7 — `\n` in a regex literal matching the letter `n` —
in the other direction, and it has the same shape: a spelling every
other language in the family reads one way is read another, and reads
it without complaint. The text is ASCII either way, so it passes
through `ascii`, comparisons and the tokenizer looking exactly like
what was intended.

Here it put the literal `u2026` on the end of every line
`text-overflow: ellipsis` truncated, and only a character-by-character
comparison in a test caught it. The workaround is to write the character
itself rather than an escape, which works — `'…'` has a length of 1 —
but it means a non-ASCII constant cannot be written in the form that
survives a copy through a terminal, a patch, or a code review.

Where the character is invisible the workaround stops being merely
inconvenient. The nine directional formatting characters of UAX #9
render as nothing at all, so `src/util/bidi.f` cannot name one in a
literal without putting a character no reader can see into the source,
and a test asserting that an RLE opened an embedding would be a line
whose subject was blank. It names the code points instead —
`BIDI_CP_RLE = 8235`, decimal because there is no hexadecimal literal
either (finding 13) — and turns one into text with `cp.toChar()`,
through a `bidiControl` function that exists only to give the character
a name. An escape the lexer understood would be one expression rather
than a constant, a function and a comment saying why.

---

## 35 A painted pixel can be compared but never read

`img.getPixelColor(x, y)` hands back a `color`, and a `color` supports
equality and nothing else. There is no channel accessor, no conversion
to an integer, no way at all to ask what colour a pixel is:

```festina
img layer = blankImage(4, 4)
fillStyle(200, 100, 50)
layer.drawRect(0, 0, 4, 4)
color c = layer.getPixelColor(1, 1)
int v = c.r          // error: cannot access field 'r' on color
int v = c.toInt()    // error: cannot access field 'toInt' on color
```

`.red`, `.value`, `.packed` and `.rgba` fail the same way. What does
work is comparing two colours, and the comparison is exact — a pixel
painted `rgb(200, 100, 50)` compares equal to another painted the same
and unequal to one painted `rgb(201, 100, 50)`. The bytes are there and
the runtime can tell them apart. The program cannot see them.

Equality is also the only relation, so nothing can be recovered by
searching either: with no ordering there is no binary search, and
finding a pixel's colour by trying candidates means 256³ comparisons for
one pixel.

**What this closes.** Every operation that transforms what has already
been painted. CSS Filter Effects 1 is the whole of it — `grayscale()`,
`sepia()`, `saturate()`, `hue-rotate()`, `invert()`, `brightness()` and
`contrast()` are each a function from a pixel's channels to new ones,
and the subtree is already painted into an image by the same device
`clip-path` and `overflow: hidden` use. The image is there, the pass
over it is three lines, and the channels cannot be got at. The
specification's matrices were derived here and agree with Chromium on
twenty-seven cases across seven functions and three colours (todo.md
keeps the table); the implementation is one accessor away.

**Workaround.** None. `tests/render/gradients.f` works around the other
half of this — a `color` cannot be built from runtime numbers either, so
an expected pixel is checked by painting a candidate into a scratch
pixel and comparing the two. That trick answers "is this pixel that
colour", which is enough for a test and useless for a filter.

**Proposal.** See festina.md: either channel accessors on `color`
(`.r`, `.g`, `.b`, `.a`, as ints from 0 to 255), or a packed-integer
accessor on the image (`img.getPackedPixel(x, y)`), or both. The
browser already carries its own packed-integer colour model in
`src/util/color.f` and would use the second directly.

---

## 36 An image is always scaled smoothly

`drawImage(img, x, y, w, h)` scales its source into the destination box,
and the scaling is bilinear. There is no way to ask for anything else:

```festina
setClientWidth(200)
setClientHeight(200)
img tile = blankImage(2, 1)
fillStyle(0, 0, 0)
tile.drawRect(0, 0, 1, 1)
fillStyle(255, 255, 255)
tile.drawRect(1, 0, 1, 1)
clearCanvas()
drawImage(tile, 0, 0, 64, 64)        // a 32x upscale of two pixels

color black = '#000000'
color white = '#ffffff'
int neither = 0
for int x = 0, x < 64, x++ {
    color c = getPixelColor(x, 32)
    if c != black && c != white { neither++ }
}
log(`across the seam, neither black nor white: ${neither} of 64 pixels`)
// across the seam, neither black nor white: 32 of 64 pixels
```

Half the row is a blend of the two source pixels. That is the right
default and the only one available: no argument to `drawImage`, no
setting on the image, no canvas state chooses the filter.

**What this closes.** CSS Images 3's `image-rendering`, whose whole
purpose is to choose between them: `pixelated` and `crisp-edges` ask for
nearest-neighbour, which is what a magnified sprite, a QR code or a
pixel-art asset needs, and `smooth` asks for what this always does. The
property is storable and would change no pixel, so it is not
implemented here — a property that computes and renders nothing is the
`outline-style` mistake this project has already made once.

**Workaround.** None worth having. Nearest-neighbour could be done by
hand, one `drawRect` per source pixel, which turns a 64x64 blit into
4,096 calls and is slower than the image it replaces.

**Proposal.** See festina.md §3q. Cairo already has the control
(`cairo_pattern_set_filter`, with `CAIRO_FILTER_NEAREST` and
`CAIRO_FILTER_BILINEAR`); what is missing is a way to reach it.

## 37 Two struct values cannot be compared with `==`

A struct value can be compared against `null` and against nothing else.
Asking whether two names refer to the same struct is a compile error,
and not one the compiler words as such -- it emits LLVM IR that fails to
parse:

```festina
struct P { v:int }
P func mk(v:int) { P p  p.v = v  return p }
P a = mk(1)
P b = a
log(`nullcmp=${a == null}`)      // fine: false
log(`same=${a == b}`)            // LLVM IR parse error
```

```
LLVM IR parse error: eqs.f:446:22: error: '%t22' defined with type
'ptr' but expected 'i64'
  %t25 = icmp eq i64 %t22, %t23
```

The comparison against `null` is special-cased and compiles; the general
one falls through to the integer path, which is handed a pointer. A
struct is a pointer at runtime, so identity is exactly what `icmp eq` on
the two pointers would answer -- the code to do it is there, one type
check away from being reached.

**What this costs here.** Every "is this the same box" question is asked
through a field instead. `scrollContainerAt` answers which scroll
container is under the pointer, and the test that it answers *the right
one* compares `found.node.id` against the box's own, which is a proxy: a
box with no element behind it has no id to compare, and two boxes
generated for one element share one. Hit testing, the box registry and
the flex item sort would each be plainer with identity.

**Workaround.** Compare a field that stands in for identity -- an id
where the value has one -- and name this finding beside it.

**Proposal.** See festina.md §3r.


## 38 The wheel has one axis, and no event carries a modifier

`on mouseWheelUp` and `on mouseWheelDown` are the whole of the wheel.
There is no horizontal pair, and no event of any kind reports whether a
modifier key was held while it fired:

```festina
on mouseWheelUp(x:int, y:int)   { log(`up at ${x},${y}`) }
on mouseWheelDown(x:int, y:int) { log(`down at ${x},${y}`) }
on mouseDown(x:int, y:int, button:int) { log(`button ${button}`) }
```

Tilting a wheel left or right, or scrolling a trackpad sideways, reaches
that program as `button 6` and `button 7` on X11 -- the runtime maps
buttons 4 and 5 to the two wheel events and lets every other button
through as a press and a release:

```c
if (ev.xbutton.button == 4 || ev.xbutton.button == 5) {
    if (ev.type == ButtonRelease) continue;
    wev.kind = ev.xbutton.button == 4
        ? FESTINA_WEVENT_MOUSE_WHEEL_UP : FESTINA_WEVENT_MOUSE_WHEEL_DOWN;
} else {
    wev.kind = ev.type == ButtonPress ? FESTINA_WEVENT_MOUSE_DOWN : ...;
    wev.button = ev.xbutton.button;
}
```

So the information is there on X11 and arrives under a name that means
something else. It is not there on Windows: that backend reads
`WM_MOUSEWHEEL` and nothing reads `WM_MOUSEHWHEEL`, so a horizontal
scroll on a Windows build produces no event at all.

**What this costs here.** A browser scrolls a box sideways two ways: a
horizontal wheel, and a vertical wheel with shift held. Neither is
expressible. This browser reads buttons 6 and 7 in `on mouseDown`
instead, which works where X11 does and nowhere else, and cannot offer
shift-wheel at all because no event says whether shift was down.

**Workaround.** Treat `mouseDown` with button 6 or 7 as a horizontal
wheel notch, and name this finding beside it.

**Proposal.** See festina.md §3s.

## 39 A map cannot hold an array

A `map` value lives in one fixed-size slot, so an `arr` does not fit in
one. The compiler says so plainly:

```
error: map values cannot be arr[Box] -- a map value is stored in a
single fixed-size slot, which an array or another map doesn't fit in
```

That rules out the shape a grouping wants — "these boxes belong to that
one" — and the way round it is two parallel arrays, one of the values
and one of the keys, scanned together. It costs a linear scan where a
lookup would do, which is fine while the list is short and is the reason
CSS2 §9.9's negative-`z-index` boxes are kept that way here
(`src/paint/paint.f`).

A minimal reproduction:

```festina
struct Thing { n:int }
map[arr[Thing]] byOwner = {}     // refused
```

**What would close it.** Either a map value that can be a handle to a
heap object of any size, or a standard multimap. The first is the
smaller change and would also allow `map[map[...]]`, which is refused
for the same reason.

## 40 Reading a struct out of a registry costs a walk of everything it reaches

Finding 1 records that a back-pointer makes every release of a live
alias walk the whole document. The same cost arrives without any
back-pointer, through an ordinary indexed read: `boxRegistry[id]`
returns a retained temporary, and releasing it after the expression
walks everything reachable from it.

It is easy to pay by accident and hard to see. Marking twenty-five boxes
through the registry —

```festina
Box ob = boxRegistry[owner]
if ob != null { ob.ownsNegativeZ = true }
```

— measured **a hundred milliseconds of layout** on a page whose layout
is seventy (benchmarks.md, "What CSS2 §9.9's painting order cost"). The
same twenty-five marks, written on a box the code already held, cost
nothing measurable. Twenty-five reads, each releasing a temporary that
walks a box graph of thousands.

So a registry read is not the cheap array index it looks like, and a
loop that does one per iteration is the shape to watch for.

**What would close it.** A borrowed read — an indexing form that hands
back a reference without retaining it, as the existing "the bucket
travels as a borrowed parameter" comment in `src/css/cascade.f` already
works around by hand.

## 41 Putting a node in a second place costs a walk of everything under it

Finding 1 records that a back-pointer makes every release of a live
alias walk the whole document, and finding 40 that an indexed read out
of a registry does the same. The third face of it needs neither: an
ordinary `push` of a node into an ordinary array costs a walk of that
node's subtree, and a traversal that collects a tree is therefore
quadratic in the size of the tree.

```festina
struct Node {
    id:int
    kids:arr[Node]
}

void func collectNodes(n:Node, out:arr[Node]) {
    out.push(n)
    for int i = 0, i < n.kids.length, i++ { collectNodes(n.kids[i], out) }
}

void func collectIds(n:Node, out:arr[int]) {
    out.push(n.id)
    for int i = 0, i < n.kids.length, i++ { collectIds(n.kids[i], out) }
}
```

Ten traversals of a ternary tree, the same walk and the same number of
pushes, differing only in what is pushed:

| nodes | `push(node)` | `push(node.id)` |
|---|---|---|
| 40 | 1 ms | 0 ms |
| 121 | 4 ms | 0 ms |
| 364 | 34 ms | 0 ms |
| 1093 | **306 ms** | 0 ms |

Three times the nodes is nine times the time, which is the signature of
a per-push cost proportional to the subtree. Pushing values rather than
nodes is flat: ten rounds of four thousand pushes into an `arr[int]`,
an `arr[text]` or an `arr` of a two-field struct are 0, 2 and 5 ms, so
`push` itself is not the problem and neither is the array's growth.

It cost this browser 523 ms of paint. CSS2 §9.9's steps 3, 4 and 5 want
three passes over one subtree, and collecting the boxes the later two
want during the first pass is the obvious way to avoid walking the tree
three times. A couple of thousand boxes collected that way turned
generated.html's 20 ms paint into 543. What works instead is to write an int on each
box as the first pass goes and have the later passes read it, which is
the same shape finding 1 forces on the box tree's parents.

**Binding an element to a local is the same cost in miniature.**
`walk(n.kids[i])` and `Node c = n.kids[i]` followed by `walk(c)` do the
same work, and the second is not free: twenty walks of a 1,093-node
tree are 0 ms passing the element straight to the call and **3 ms**
binding it first, which is about 0.14 microseconds a bind. Unlike the
push it is a flat cost rather than a walk -- a struct of 52 fields, ten
of them arrays and ten `text`, binds in exactly the same 3 ms as one of
two. So it is a retain and a release rather than a traversal, and it is
worth knowing where a loop over a tree binds a child it uses once.

And it is worth saying what this is *not*: reading a struct-valued
field is free. A `Style` here has 244 fields, 16 of them `text` and 14
of them arrays, and forty thousand reads of one that size --
`Big s = n.big`, the shape `Style s = b.style` takes all over this
engine -- do not register at millisecond resolution. The cost is in
holding the node, not in looking at it.

**What would close it.** The same borrowed reference finding 40 asks
for, extended to a container: a way to put a node in a list that
observes it without taking ownership of everything under it. An
explicit weak or borrowed element type would do, since the alternative
-- a list of ids and a registry to resolve them -- is finding 40's cost
paid on the way back out.

## 42 A global function captures a same-named local in another module

Declaring a function at the top level of one module makes every *local
variable* of that name, in every module, refer to the function instead.
The program does not miscompile silently — it fails at LLVM IR emission
with a message that names neither the local nor the two files — but
nothing before that point objects.

```festina
// lib.f
void func useLocal() {
    bool flagX = true
    if flagX { log('the local won') }
    else { log('the local LOST') }
}
```

```festina
// main.f
import lib.f

void func flagX() { }

useLocal()
close(0)
```

```
$ festina compile main.f -o main
main.f:0:0: error: LLVM object emission failed:
LLVM IR parse error: main.f:395:20: error: global variable reference
must have pointer type
  %t1 = icmp ne i8 @flagX, 0
```

`lib.f`'s `if flagX` has become a truthiness test on the *function*
`@flagX`. The local declared two lines above it is gone.

**A global variable does not do this**, which is the useful half of the
finding: replacing `void func flagX()` with `int flagX = 99` compiles,
`useLocal` prints `the local won`, and the global keeps its own value.
So locals shadow global variables correctly and only functions capture
them, which points at the resolver treating a function name as a binding
that a local declaration does not displace.

The error is loud rather than silent, so no rendering can be wrong
because of it. What it costs is the diagnosis: the message names the
mangled symbol and a line number in generated IR, so the reader has to
grep the whole program for the name before the two-module collision is
visible. Found when a render suite declared a helper `fRow` and the flex
code's own `bool fRow = flexIsRow(s)`, in a file the suite merely
imports, stopped compiling.
