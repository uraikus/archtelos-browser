// CSS Animations 1 §3: the `@keyframes` rules a document declared.
//
// A rule is kept as the declarations it was written with, not as values:
// a keyframe's `margin: 0 10px` is four longhands by the time it is
// interpolated, and turning it into them takes the cascade's own
// shorthand expansion, which is declared in the file that imports this
// one. What is stored here is the shape -- offsets in ascending order, a
// declaration list at each, and the timing function a keyframe gave.
struct Keyframe {
    offset:float            // 0.0 for `from`, 1.0 for `to`
    names:arr[text]         // as written, lowercased; shorthands included
    values:arr[text]
    timing:text             // this keyframe's `animation-timing-function`, or ''
}

struct KeyframesRule {
    frames:arr[Keyframe]    // ascending by offset, equal offsets kept in source order
    defined:bool
}

// The rules the page declared, by name. A second `@keyframes` of the
// same name replaces the first (§3.1), so this is assigned, not merged.
map[KeyframesRule] cssKeyframes = {}

// Whether any rule was declared, so a page with none never reads a
// property that names an animation.
bool cssSawKeyframes = false

void func cssResetKeyframes() {
    map[KeyframesRule] empty = {}
    cssKeyframes = empty
    cssSawKeyframes = false
}
