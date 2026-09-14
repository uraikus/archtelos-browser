# Findings: building an HTML/CSS renderer in Festina

This is the report the project exists for. Every entry was hit while
writing the renderer; each has a minimal reproduction where one could
be isolated, the workaround the renderer uses, and, where it seemed
useful, a suggestion. Entries are ordered by how much they cost.

Versions: Festina 0.44 at commit `main` of 2026-09-14, Linux x86-64,
clang 18, Cairo 1.18, DejaVu fonts.

## Summary

| # | Finding | Kind | Cost to this project |
|---|---|---|---|
| 1 | Releasing an alias of a live node of a cycle-capable type walks the reachable graph; with back-pointers that is the whole tree | performance | 21 s and 43 s page renders; three days' worth of "why is this slow" in one afternoon |
| 2 | `ascii` aliases are not retained: use-after-free and double free | memory-safety bug | heap corruption in the CSS parser and cascade until every alias was copied |
| 3 | An empty `text` is `null` | semantics | valueless HTML attributes needed a second map |
| 4 | A struct-typed field can never read as `null` | semantics | optional references need flags or ids |
| 5 | A parameter cannot shadow a global function; the function wins silently and type-checks as anything | compiler bug | a garbage CSS property name |
| 6 | `text` has no substring, search or case conversion; `ascii` cannot hold non-ASCII | library gap | a byte-level pre-pass turning UTF-8 into numeric references |
| 7 | Regex escapes inside `[...]` are literal, and `\t` is not recognized | documentation / library gap | `[ \t\n]` silently ate the letters t, n, r, f from every text node |
| 8 | `ascii.toInt()` is rejected although the analyzer has a branch for it | compiler bug | trivial |
| 9 | No way to decode an `img` from a `blob` except through an `http` literal | library gap | an odd idiom |
| 10 | Globals are not hoisted and are invisible to files imported earlier | design | module ordering constraints |
| 11 | `map[T]` cannot hold arrays or maps | design | wrapper structs |
| 12 | No closures; `forEach`/timer callbacks must be bare functions | design | module-level state for the line builder |
| 13 | No bitwise operators, no hexadecimal literals | design | colors packed with `*`, `/` and `%`; a 148-entry table in decimal |
| 14 | No `text.toFloat()` | library gap | a hand-written number parser |
| 15 | No font ascent/descent metrics | library gap | hard-coded DejaVu ratios |
| 16 | Reserved words cannot name fields | design | `content` instead of `text`, `freeSpace` instead of `free` |
| 17 | Host-CPU code generation defeats valgrind on AVX-512 machines | tooling | `tools/festina-generic` |
| 18 | No clipping, no window title, no cursor shapes, no current directory | platform gaps | listed in the browser's limitations |
| 19 | `font` literals leave omitted parts unchanged | documented, surprising | a test measured bold text by accident |

What worked well is at the end.

## 1. Cycle-collector walks make tree code quadratic

**What happened.** Festina reclaims memory by reference counting plus a
synchronous Bacon-Rajan trial deletion "on releases of values whose
type can participate in a cycle" (runtime, `festina_runtime.c`, "cycle
collection"). A DOM node is such a type: it has `children:arr[Node]`,
and the first version also had `parent:Node`. Every time a local that
aliased a live node went out of scope -- `Node c = n.children[i]` in a
loop body, `cur = cur.parent` in a `while` -- the release found the
node still referenced and ran a trial that traversed everything
reachable from it. With a parent pointer, everything reachable from any
node is the whole document. Rendering Festina's own docs index took
21.5 s (17 s of it in the cascade); the API reference took 43 s.

**Reproduction** (`tests/../scratchpad`, kept here as a description):

```festina
struct N { id:int  kids:arr[N]  parent:N }
// build a tree of 8,421 nodes with parent pointers, then
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

| nodes | `visitLocal` with parent pointers | `visitIndex` | `visitLocal` without parent pointers |
|---|---|---|---|
| 1,111 | 30 ms | 0 ms | 0 ms |
| 1,555 | 60 ms | 0 ms | 0 ms |
| 8,421 | 1,645 ms | 0 ms | 1 ms |

The cost is quadratic in the tree size with back-pointers and vanishes
without them, because a trial from a node then only walks its subtree.

The same walk was triggered from a different direction in the selector
matcher: sampling the running process with gdb showed
`__festina_release_struct_Node` on the exit path of `matchCompound` and
`matchFrom`, recursing through `festina_cycle_visit_array` -- the Node
*parameter* was retained on entry and released on exit in those
functions (which forwarded it to other calls), and the ancestor loop
passed `<body>` and `<html>` for every descendant selector it rejected.
A stand-alone benchmark of a forwarded parameter did not reproduce
this, so the exact escape-analysis rule that decided to retain was not
pinned down; the fix was to stop passing nodes at all.

**Workaround in the renderer.** No back-pointers anywhere: `Node` and
`Box` carry `parentId:int` and are looked up in a registry array
(`nodeRegistry[id]`). Hot paths -- selector matching, sibling
navigation, the parser's open-element stack -- work on ids and read
`nodeRegistry[id].field` inline, never binding a node to a local or
passing one to a function. Result: the docs index renders in ~130 ms
(cascade 102 ms, layout 19 ms), the 4,470-element API reference in
~400 ms (cascade 110 ms, layout 247 ms).

**Suggestions.** (a) The deferred-root buffer todo.md already
describes would turn the per-release walk into an amortized one. (b) A
cheaper, targeted fix: a `weak` (or `back`) field modifier that the
traversal functions skip, so a tree with parent pointers costs what a
tree without them costs; a DOM, a scene graph and a doubly linked list
all want it. (c) Document the rule that today's programmer has to
discover: with a cycle-capable type, bind locals to fresh values only,
and pass by index or id in loops.

## 2. `ascii` aliases are not retained

**What happened.** The specification says `ascii b = a` shares one
buffer and that the type is reference counted. The compiler emits the
release for such a local at scope exit but no retain when the local is
initialized from another binding, so the buffer is freed while its
owner still uses it. The CSS parser corrupted the heap
(`malloc(): unsorted double linked list corrupted`) as soon as the
stylesheet was larger than a few hundred bytes.

**Reproductions**, all confirmed with valgrind (invalid read and write
of size 8 in `festina_ascii_release`), each a complete program:

```festina
// (a) a parameter rebound to a local
void func inner(srcIn:ascii) {
    ascii src = srcIn
    log(src)
}
ascii base = 'hello world'
inner(base.slice(0, 6))

// (b) a local aliasing another local
ascii a = base.slice(0, 5)
ascii b = a

// (c) a local aliasing an array element
arr[ascii] t = [base.slice(0, 5), base.slice(6, 11)]
ascii x = t[0]

// (d) a local aliasing a struct field
struct D { value:ascii }
ascii x = d.value

// (e) a local aliasing a map entry
map[ascii] m = {}
ascii x = m['k']

// (f) a parameter stored into a map when the caller's argument was a local
void func setProp(m:map[ascii], k:text, v:ascii) { m[k] = v }
```

Safe shapes, also verified: a local initialized from a literal, a
`slice()` or any call result; a struct field or map entry assigned from
a local or a call result; `arr[ascii].push` of a local; a global
assigned from a local or a parameter; a local aliasing a global; a
`?:` between two array elements (curiously). The same shapes with
`text` are all safe, since `text` copies on every binding.

**Workaround.** `dup(s)` in `src/util/text.f` returns `s.slice(0,
s.length)`, a fresh value the local really owns, and every alias in the
renderer goes through it; the cascade keeps its property map as
`map[text]` and converts on read.

**Suggestion.** This is a compiler bug: the retain that `text` gets by
copying and structs get by `festina_retain` is missing on the
`ascii` local-initialization paths. tests/CONTRACT.md's leak stress
programs would catch it with a two-alias `ascii` case under ASan.

## 3. An empty `text` is `null`

`'' == null` is `true`, in a local, a struct field, an array element
and a map value; `''.length` is 0 and `[''].join('')` is null too. A
NUL-terminated `char*` with no header cannot distinguish the two. For
HTML this matters: `<input checked>` has the attribute `checked` with
the empty value, and `attrs['checked'] == null` says it is absent. The
DOM keeps a second `present:map[bool]` for attribute existence.

**Suggestion.** Document it in specification.md 8.4 next to "`null`
reads 0", and consider a distinct empty-string sentinel (a static
one-byte buffer the runtime recognizes) so `''` can round-trip through
containers.

## 4. A struct-typed field can never read as `null`

Specification 8.9.2 says a struct/array/map field is created empty on
first reach. The consequence is that `if c.notSel != null` is always
true and `x.field = null` followed by `x.field == null` is `false`: the
field re-vivifies on the read. A first version of the selector matcher
recursed forever on `Compound.notSel`. Optional references therefore
need a parallel `bool` (`hasNot`) or an id that is 0 when absent.

**Suggestion.** Either make a null read observable (vivify on write and
on method calls, not on `== null`) or state the consequence in the
specification and the api "Structs" section.

## 5. A parameter cannot shadow a global function

```festina
text func prop(a:int) { return 'the function' }
void func show(prop:text) { log(prop) }
show('the parameter')
// error: log() only supports primitive values right now, found func[int]:text
```

Inside `show`, `prop` resolves to the global function, not the
parameter. In the renderer a helper named `prop` and a parameter named
`prop` coexisted; `addMatch(matches, prop, ...)` passed the function
pointer where a `text` was expected, no type error was raised, and the
"property name" was machine code. Two bugs: name resolution should
prefer the innermost binding (or reject the shadowing outright), and a
`func[...]` value must never satisfy a `text` parameter.

## 6. `text` has no substring, search or case conversion; `ascii` cannot hold non-ASCII

`text` offers `s[i]`, `.length`, `charCodeAt`, `split`, `replace`,
`match`, `trim`, `toInt` -- and no `slice`, `indexOf`, `startsWith`,
`toLowerCase`/`toUpperCase`, or `repeat`. `ascii` has the O(1) indexing
and `slice()` a tokenizer needs, but `toAscii()` answers `null` for
any non-ASCII input, and every web page has an em dash somewhere. The
renderer therefore reads the page as a `blob`, walks its bytes with
`byteAt`, and rewrites each UTF-8 sequence as `&#N;` before tokenizing
in `ascii`; the entity decoder turns them back into `text` with
`toChar()`. It works, and it is the kind of thing nobody should have to
write. `src/util/text.f` holds the missing string functions
(`asciiLower`, `asciiIndexOf`, `asciiStartsWith`, `asciiTrim`, splits,
`parseNumberAt`, `repeatText`).

**Suggestion.** Give `text` `slice`, `indexOf`, `startsWith`,
`endsWith`, `toLowerCase`, `toUpperCase` and `repeat` (all byte-level
operations on UTF-8, none needing a scan per index), and give `ascii`
a sibling that stores code points in fixed-width cells, or let `ascii`
carry bytes above 127 as opaque.

## 7. Regex escapes inside brackets are literal

`t.replace(/[ \t\n\r\f]+/g, ' ')` turned "world" into "wo ld": in a
POSIX bracket expression a backslash is literal, so the class matched
`\`, `t`, `n`, `r`, `f`. `/\t/` outside brackets matched nothing
either. The specification says "inside `[...]` a backslash is literal",
which is correct and easy to miss; `[[:space:]]` is the answer and
should be named in api.md's regex section. A literal tab had to be
built at runtime: `regex(9.toChar(), 'g')`.

## 8. `ascii.toInt()` is rejected

semantic.py accepts `toInt` on an `ascii` receiver, but compiling
`a.toInt()` fails with `cannot access field 'toInt' on ascii`; the
call is routed through a later branch. `a.toText().toInt()` works.

## 9. Decoding an image from bytes

An `img` can be declared from a path, a database column or a
background load, but not from a `blob` already in memory. Images that
arrive over HTTP are decoded with an `http` literal whose body is the
blob: `{'url': 'http://localhost/', 'body': r.data}.toImg()`. It
works; `blob.toImg()` would be the obvious spelling.

## 10. Globals are not hoisted and are invisible to earlier files

A function in an imported file cannot mention a global the entry file
declares later (`error: unknown variable`), and a global used above
its declaration in the same file fails the same way, although
functions and types are hoisted everywhere. Module-level state
(tokenizer position, line-builder pen, profiling counters) therefore
has to sit in the lowest file that uses it and above its first use.
Reasonable, but the error message could say "declared later in the
unit" rather than "unknown".

## 11–13. Maps of arrays, closures, bit operations

- `map[arr[T]]` is rejected, so the rule index is `map[Bucket]` with
  `struct Bucket { refs:arr[RuleRef] }`.
- Without closures, `map.forEach` and timers take bare function names,
  and any traversal that accumulates state does so in globals. The
  inline layout keeps its pen, open inline boxes and pending space in
  module globals that are saved and restored around nested formatting
  contexts. It reads like 1990s C, but it is honest about cost.
- Colors are packed as `a * 16777216 + r * 65536 + g * 256 + b` and
  unpacked with `Math.floorDiv` and `%`; the 148 CSS color names are
  generated from Festina's own `colors.py` as decimal integers because
  there is no `0xRRGGBB` literal. `&`, `|`, `<<` and hex literals would
  make every binary-format program read better and cost nothing.

## 14. No `text.toFloat()`

`toInt()` exists; CSS needs `1.5em` and `0.5`. `parseNumberAt` in
`src/util/text.f` parses a decimal at an offset and reports the value,
the end index and success through three globals, because there are no
tuples or out-parameters either.

## 15. No font metrics beyond an inked height

`measureTextWidth` is exact, `measureTextHeight` is the inked height of
the string, and there is no ascent, descent or line gap. Baselines are
placed with hard-coded ratios for DejaVu (ascent 0.93 em, descent 0.24
em). `fontAscent()`/`fontDescent()` builtins, or a `measureFont()`
answering both, would make text layout correct for any font.

## 16. Reserved words as field names

`text:text`, `free`, `table` and `match` cannot name a field or a
local, although the specification allows reserved words after a `.`.
Renamed; a friendlier error than `expected IDENT` would help.

## 17. Host-CPU code generation defeats valgrind

`llvm_backend.py` compiles for `LLVMGetHostCPUName()` with the host's
features. On this machine that means AVX-512, which valgrind cannot
emulate, so every valgrind run died with SIGILL in a `vpternlogq` --
and valgrind was the only tool that found finding 2.
`tools/festina-generic` monkeypatches the binding to `x86-64` with no
features; a `FESTINA_TARGET_CPU=generic` environment variable would be
better.

## 18. Platform gaps for a browser

- No clipping region: `overflow: hidden` is not implemented (drawing
  into a `blankImage` layer and compositing it would emulate one).
- The window title cannot be set, so the page title lives in the
  status bar.
- Key names are the platform's: Page Down arrives as `Next`, Page Up
  as `Prior`, on X11.
- No cursor shapes (a pointer over a link), no clipboard, no text
  input widget; the address bar is drawn and edited by hand.
- No current directory or path normalization, so a local page keeps a
  relative path and its resources resolve relative to it.
- Italics need an italic face installed; the default Ubuntu container
  has none for DejaVu Sans until `fonts-dejavu-extra` is added.

## 19. `font` literals leave omitted parts unchanged

`font base = '16px sans-serif'` after `changeFont(16, 'bold', ...)`
measures bold text: an omitted style means "unchanged", as api.md
says. A test measured a table column in bold and failed by two pixels
before this was understood. `changeFont(px, 'normal', family)` resets.

## What worked well

- **The result is one native binary.** 1.9 MB, linking only Cairo,
  X11, libjpeg, mbedTLS and libc: an HTML/CSS renderer with an HTTPS
  client and a window, and nothing to install to run it. Festina
  compiles the 6,000 lines in about ten seconds.
- **It is fast once the collector is kept out of the loop.** A
  4,470-element, 97,000-pixel-tall page: parse 22 ms, cascade 110 ms,
  layout 247 ms, paint 19 ms. Measuring 35,000 words through the
  canvas font cost 27 ms.
- **The canvas is complete enough for a browser.** `translate` gives
  scrolling, `fillAlpha` gives opacity, paths with `curveTo` give
  rounded corners, `saveCanvas` gives headless screenshots,
  `getPixelColor` lets the tests check real pixels without a display,
  and text metrics work without a window. The direct-fill fast path
  makes thousands of rectangles cheap.
- **`ascii` made the parsers cheap.** O(1) indexing, `slice()`, and
  compile-time literals for every keyword comparison; the HTML
  tokenizer and the CSS parser are straightforward scanners.
- **Template literals span lines**, which is how the user-agent
  stylesheet and the welcome page are embedded as plain text.
- **Structs with zero values.** A `Style` with forty fields starts as
  all zeros, so the cascade only writes what changed; a `Len` reads as
  `auto` until set.
- **Arrow functions as comparators** (`names.sort(int (a:text, b:text)
  => compareText(a, b))`) and stable `sort()` made specificity ordering
  a one-liner.
- **The HTTP client** handled TLS, redirects (by hand, from the
  `location` header), and `toBlob()`/`toImg()` for bodies with no
  ceremony; `try`/`catch` turns a network failure into an error page.
- **The event model** is simple and sufficient: nine window events,
  synchronous handlers, `setClientWidth` before `render()` for the
  initial size, and the program is the event loop.
- **Diagnostics** are precise (`file:line:col`) and the type checker
  caught real mistakes early: mismatched `?:` branch types, a `void`
  used as a value, an `int`/`float` mix.

## Suggestions, in priority order

1. Make aliasing an `ascii` safe (finding 2).
2. Bound the cycle trials: a deferred root buffer, or a `weak` field
   modifier that traversals skip (finding 1).
3. Reject or correctly resolve a parameter that shadows a function,
   and never let a `func` satisfy a `text` (finding 5).
4. `text.slice/indexOf/startsWith/endsWith/toLowerCase/toUpperCase/
   repeat/toFloat` (findings 6, 14).
5. Name `[[:space:]]` and the bracket-escape rule in api.md; consider
   translating `\t`, `\n` in regex literals before `regcomp` (finding 7).
6. `blob.toImg()`, `fontAscent()`/`fontDescent()`, a settable window
   title, a clip rectangle (findings 9, 15, 18).
7. A generic-CPU switch for the backend (finding 17).
