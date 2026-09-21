// The computed style of one element: every property the renderer
// understands, already resolved to pixels or to a small int code.
// Structs are the natural home for this in Festina -- every field has
// a zero value, so an element with no style at all reads as all-zero
// and only the cascade fills in what changed. There are no enums with
// named integer members, so each `display`/`text-align`/... value is a
// const int with a naming prefix.

import ../util/color.f

// display
// DejaVu Sans metrics (the fonts fontconfig serves for the generic
// families here), in em: ascent 0.93, descent 0.24. Festina exposes
// no ascent/descent API, only the inked height of a string.
const float FONT_ASCENT = 0.93
const float FONT_DESCENT = 0.24
// The other two edges `text-box-edge` can name. Both are measured
// across a range of font sizes rather than at one, because a ratio read
// off a single size is a ratio plus a rounding error of up to a pixel:
// 5% at 20px and 0.5% at 180. Rasterising an `H` through this engine
// and asking Chromium for the same family's cap height both give a
// least-squares `0.733 x size` with an intercept of -0.4; todo.md has
// both tables. That intercept is why the cap height is FLOORED below
// rather than rounded -- 0.733 x 20 is 14.66 and Chromium answers 14 --
// and it is why 0.70 looked right at 20px for as long as it did.
const float FONT_CAP = 0.733
const float FONT_EX = 0.55

const int DISPLAY_NONE = 0
const int DISPLAY_BLOCK = 1
const int DISPLAY_INLINE = 2
const int DISPLAY_INLINE_BLOCK = 3
const int DISPLAY_LIST_ITEM = 4
const int DISPLAY_TABLE = 5
const int DISPLAY_TABLE_ROW = 6
const int DISPLAY_TABLE_CELL = 7
const int DISPLAY_TABLE_ROW_GROUP = 8
const int DISPLAY_FLEX = 9
const int DISPLAY_TABLE_CAPTION = 10
const int DISPLAY_TABLE_COLUMN = 11
const int DISPLAY_TABLE_COLUMN_GROUP = 12
const int DISPLAY_TABLE_HEADER_GROUP = 13
const int DISPLAY_TABLE_FOOTER_GROUP = 14
const int DISPLAY_RUBY = 15
const int DISPLAY_CONTENTS = 16
const int DISPLAY_INLINE_FLEX = 17
const int DISPLAY_GRID = 18
const int DISPLAY_INLINE_GRID = 19
const int DISPLAY_INLINE_TABLE = 20

// CSS Conditional 4 §2: what a container query may ask about this box.
const int CONTAINER_NORMAL = 0
const int CONTAINER_INLINE_SIZE = 1
const int CONTAINER_SIZE = 2

// A grid track's two sizing functions (Grid 1 §7.2). Every track has a
// minimum and a maximum, and the keywords are shorthands for a pair:
// `auto` is minmax(auto, max-content), `100px` is minmax(100px, 100px),
// `1fr` is minmax(auto, 1fr), `min-content` and `max-content` are that
// function twice over, and `fit-content(L)` is a maximum of its own.
//
// TRACK_AUTO is zero so that a Track nobody filled in -- the one
// `trackAt` hands back past the end of a template -- is `auto` on both
// sides, which is what the standard says an implicit track is.
//
// `fr` is not a length: it is a share of what the other tracks leave,
// so it cannot live in a Len and has a field of its own. It is only
// valid as a maximum.
const int TRACK_AUTO = 0
const int TRACK_LEN = 1          // a length or a percentage, in `size`
const int TRACK_FR = 2           // a share, in `fr`
const int TRACK_MIN_CONTENT = 3
const int TRACK_MAX_CONTENT = 4
const int TRACK_FIT_CONTENT = 5  // the clamp is in `size`

struct Track {
    kind:int        // the maximum: what the track may grow to
    size:Len
    fr:float
    minKind:int     // the minimum: what it may not go below
    minSize:Len
}

// One edge of an item's placement on one axis. A line number counts
// from 1; `span n` says how many tracks to cover without saying where
// they start.
// object-view-box (Images 4): a rectangle over a replaced element's own
// pixels, which becomes its natural size. The terms stay unresolved
// because a percentage is of the image's size and the image may not
// have loaded when the style is computed. For `inset` and `rect` the
// four are top, right, bottom and left; for `xywh` they are x, y, width
// and height.
const int VIEWBOX_NONE = 0
const int VIEWBOX_INSET = 1
const int VIEWBOX_RECT = 2
const int VIEWBOX_XYWH = 3

struct ViewBox {
    kind:int
    t:Len
    r:Len
    b:Len
    l:Len
}

const int GRIDLINE_AUTO = 0
const int GRIDLINE_NUMBER = 1
const int GRIDLINE_SPAN = 2
// A line named rather than numbered. Which line that is depends on the
// container's template, so it stays a name until layout, where both the
// item and the grid it sits in are in hand.
const int GRIDLINE_NAME = 3

struct GridLine {
    kind:int
    n:int
    name:text
}

// text-align
const int ALIGN_LEFT = 0
const int ALIGN_CENTER = 1
const int ALIGN_RIGHT = 2

// text-decoration-line (a bit set built with + since there are no
// bitwise ops)
const int DECO_NONE = 0
const int DECO_UNDERLINE = 1
const int DECO_LINE_THROUGH = 2
const int DECO_OVERLINE = 4

// text-decoration-style. The first four are the line styles a border
// has, and are painted by the same code; `wavy` has no border
// counterpart.
const int DECOSTYLE_SOLID = 0
const int DECOSTYLE_DOUBLE = 1
const int DECOSTYLE_DOTTED = 2
const int DECOSTYLE_DASHED = 3
const int DECOSTYLE_WAVY = 4

// white-space-collapse: what happens to a run of spaces and to a
// newline. `white-space` is a shorthand for this and text-wrap-mode,
// and the engine stores the two separately because they are two
// independent questions: `pre-line` preserves newlines while still
// collapsing spaces, which no single enum of the shorthand's values
// can express.
const int WSC_COLLAPSE = 0
const int WSC_PRESERVE = 1
const int WSC_PRESERVE_BREAKS = 2

// text-wrap-mode
const int WRAP_WRAP = 0
const int WRAP_NOWRAP = 1

// word-break and overflow-wrap, which both say a word may be broken
// but disagree about when. `break-word` breaks only a word that would
// not fit on a line of its own; `break-all` breaks any word to fill
// the line it is on.
const int BREAK_NONE = 0
const int BREAK_WORD = 1
const int BREAK_ALL = 2

// list-style-type
const int LIST_NONE = 0
const int LIST_DISC = 1
const int LIST_CIRCLE = 2
const int LIST_SQUARE = 3
const int LIST_DECIMAL = 4
const int LIST_LOWER_ALPHA = 5
const int LIST_UPPER_ALPHA = 6
const int LIST_LOWER_ROMAN = 7
const int LIST_UPPER_ROMAN = 8

// vertical-align (inline-level boxes only)
const int VALIGN_BASELINE = 0
const int VALIGN_MIDDLE = 1
const int VALIGN_TOP = 2
const int VALIGN_BOTTOM = 3

// flex-direction
const int FLEX_ROW = 0
const int FLEX_ROW_REVERSE = 1
const int FLEX_COLUMN = 2
const int FLEX_COLUMN_REVERSE = 3

// justify-content, align-items and align-self, which share a vocabulary
// (Box Alignment 3). The prefix is not `ALIGN_`, which belongs to
// `text-align` above: two runs of `const int` under one prefix is how
// `ALIGN_CENTER` and `ALIGN_CENTRE` would come to mean different things
// one letter apart. See FINDINGS.md, "constants with the same value
// collide silently".
const int BOXALIGN_START = 0
const int BOXALIGN_END = 1
const int BOXALIGN_CENTRE = 2
const int BOXALIGN_STRETCH = 3
const int BOXALIGN_BASELINE = 4
const int BOXALIGN_SPACE_BETWEEN = 5
const int BOXALIGN_SPACE_AROUND = 6
const int BOXALIGN_SPACE_EVENLY = 7
const int BOXALIGN_AUTO = 8

// border-image-repeat. The tile is the edge image scaled to the
// border's thickness (Backgrounds and Borders 3 §6.5); the keyword says
// how those tiles fill the edge, and the property takes two of them,
// one for the horizontal edges and one for the vertical.
const int BORDERIMG_STRETCH = 0
const int BORDERIMG_REPEAT = 1
const int BORDERIMG_ROUND = 2
const int BORDERIMG_SPACE = 3

// overflow (CSS Overflow 3 §3). The two axes are separate properties,
// and a `visible` beside a value that is not `visible` computes to
// `auto`: a box cannot clip one axis and let the other spill.
const int OVERFLOW_VISIBLE = 0
const int OVERFLOW_HIDDEN = 1
const int OVERFLOW_CLIP = 2
const int OVERFLOW_SCROLL = 3
const int OVERFLOW_AUTO = 4

// pointer-events. Only `none` changes what this engine does, because
// hit testing is the only interaction it has and a `visibility: hidden`
// box is already never hit; the rest are kept apart so the computed
// value is the one that was asked for.
const int PE_AUTO = 0
const int PE_NONE = 1
const int PE_VISIBLE = 2
const int PE_ALL = 3

// flex-wrap. A container is single-line unless it says otherwise;
// wrap-reverse flips the cross axis, which reverses both the order of
// the lines and the side of its own line an item aligns to.
const int FLEXWRAP_NOWRAP = 0
const int FLEXWRAP_WRAP = 1
const int FLEXWRAP_WRAP_REVERSE = 2

// background-clip and background-origin (Backgrounds and Borders 3
// §3.7, §3.8). Each is numbered so that its own initial value is zero --
// `border-box` for the clip and `padding-box` for the origin -- which is
// why the two do not share a numbering. A style that mentions neither
// then writes nothing, and `noGradient`-style per-element work is
// avoided.
const int BGCLIP_BORDER = 0
const int BGCLIP_PADDING = 1
const int BGCLIP_CONTENT = 2

const int BGORIGIN_PADDING = 0
const int BGORIGIN_BORDER = 1
const int BGORIGIN_CONTENT = 2

// background-size (Backgrounds and Borders 3 §3.9). `auto` is the
// initial value, so it is 0 and a style that never mentions the
// property needs no work -- and neither do the two `Len` fields, whose
// zero value is already `auto`.
const int BGSIZE_AUTO = 0
const int BGSIZE_COVER = 1
const int BGSIZE_CONTAIN = 2
const int BGSIZE_EXPLICIT = 3

// object-fit (CSS Images 3 §5.5): how a replaced element's content is
// sized inside the content box the element's own width and height gave
// it. `fill` is the initial value and stretches to the box, so it is 0
// and a style that never mentions the property needs no work.
const int OBJECTFIT_FILL = 0
const int OBJECTFIT_CONTAIN = 1
const int OBJECTFIT_COVER = 2
const int OBJECTFIT_NONE = 3
const int OBJECTFIT_SCALE_DOWN = 4

// break-before and break-after. Only a column break happens here: a
// page break is a break in a paginated context, which a screen render
// is not, so `page` and its `left`/`right`/`recto`/`verso` variants ask
// for something this engine never makes and change nothing -- which is
// what Chromium does with them on screen too.
// CSS Scrollbars 1 §3: how wide a scroll container's bars are. `auto`
// is whatever the browser's own is, `thin` is narrower, and `none`
// reserves nothing and paints nothing -- the box still scrolls, because
// hiding the bar is not the same as taking the scrolling away.
// Chromium 141 answers a 200x100 `overflow: scroll` box with a client
// width of 185, 190 and 200 for the three, so `thin` is ten pixels.
// CSS Scroll Snap 1 §5: how strictly a scroll container comes to rest on
// one of its snap positions, and §4: which edge of a child a position
// lines up with. `proximity` snaps only when a position is near enough,
// and near enough is a third of the snapport -- measured against
// Chromium rather than chosen (todo.md).
const int SNAP_NONE = 0
const int SNAP_MANDATORY = 1
const int SNAP_PROXIMITY = 2

const int SNAPALIGN_NONE = 0
const int SNAPALIGN_START = 1
const int SNAPALIGN_CENTER = 2
const int SNAPALIGN_END = 3

// `corner-shape`'s keywords, as the superellipse exponents they name
// (CSS Borders 4 §5). The two extremes are large finite numbers rather
// than an infinity the language has no literal for, and they are large
// enough that the curve is flat to well inside a pixel at any radius a
// page uses: at k = 1000 the corner is square to within a thousandth of
// its radius.
// Whether any element on this page asked for a corner that is not
// `round`, so that a page which never says the property never leaves
// the curve the canvas draws natively (CLAUDE.md, "a feature must not
// cost anything to the pages that do not use it").
bool anyCornerShape = false

const float CORNER_K_ROUND = 2.0
const float CORNER_K_SQUARE = 1000.0
const float CORNER_K_NOTCH = -1000.0
const float CORNER_K_BEVEL = 1.0
const float CORNER_K_SCOOP = -2.0
const float CORNER_K_SQUIRCLE = 4.0

// The codes those exponents are packed as. `round` is zero so that a
// `Style` nobody assigned to is every corner round, which is what a box
// with only a `border-radius` has always been.
const int CORNER_CODE_ROUND = 0
const int CORNER_CODE_SQUARE = 1
const int CORNER_CODE_BEVEL = 2
const int CORNER_CODE_SCOOP = 3
const int CORNER_CODE_NOTCH = 4
const int CORNER_CODE_SQUIRCLE = 5
// Six bits a corner, so four fit in one field with room for the
// exponents `superellipse()` names beyond the keywords.
const int CORNER_CODE_CUSTOM = 6
const int CORNER_CODE_BASE = 64

// The arbitrary exponents this page's `superellipse()` declarations
// asked for, in the order they were first seen; a code of
// CORNER_CODE_CUSTOM or more indexes this.
arr[float] cornerCustomK = []

float func cornerKOfCode(code:int) {
    if code == CORNER_CODE_ROUND { return CORNER_K_ROUND }
    if code == CORNER_CODE_SQUARE { return CORNER_K_SQUARE }
    if code == CORNER_CODE_BEVEL { return CORNER_K_BEVEL }
    if code == CORNER_CODE_SCOOP { return CORNER_K_SCOOP }
    if code == CORNER_CODE_NOTCH { return CORNER_K_NOTCH }
    if code == CORNER_CODE_SQUIRCLE { return CORNER_K_SQUIRCLE }
    int i = code - CORNER_CODE_CUSTOM
    if i < 0 || i >= cornerCustomK.length { return CORNER_K_ROUND }
    return cornerCustomK[i]
}

// The code for an exponent, adding it to the page's list when it is one
// no keyword names. A page that runs out of codes gets `round` for the
// rest, which is the initial value rather than a wrong shape.
int func cornerCodeOfK(k:float) {
    if k == CORNER_K_ROUND { return CORNER_CODE_ROUND }
    if k == CORNER_K_SQUARE { return CORNER_CODE_SQUARE }
    if k == CORNER_K_BEVEL { return CORNER_CODE_BEVEL }
    if k == CORNER_K_SCOOP { return CORNER_CODE_SCOOP }
    if k == CORNER_K_NOTCH { return CORNER_CODE_NOTCH }
    if k == CORNER_K_SQUIRCLE { return CORNER_CODE_SQUIRCLE }
    for int i = 0, i < cornerCustomK.length, i++ {
        if cornerCustomK[i] == k { return CORNER_CODE_CUSTOM + i }
    }
    if CORNER_CODE_CUSTOM + cornerCustomK.length >= CORNER_CODE_BASE {
        return CORNER_CODE_ROUND
    }
    cornerCustomK.push(k)
    return CORNER_CODE_CUSTOM + cornerCustomK.length - 1
}

// Corner 0 is the top left, then clockwise.
int func cornerCodeAt(packed:int, which:int) {
    if which == 0 { return packed % CORNER_CODE_BASE }
    if which == 1 { return Math.floorDiv(packed, CORNER_CODE_BASE) % CORNER_CODE_BASE }
    if which == 2 {
        return Math.floorDiv(packed, CORNER_CODE_BASE * CORNER_CODE_BASE) % CORNER_CODE_BASE
    }
    return Math.floorDiv(packed, CORNER_CODE_BASE * CORNER_CODE_BASE * CORNER_CODE_BASE)
        % CORNER_CODE_BASE
}

float func cornerKAt(packed:int, which:int) { return cornerKOfCode(cornerCodeAt(packed, which)) }

int func cornerShapesPacked(tl:float, tr:float, br:float, bl:float) {
    return cornerCodeOfK(tl)
        + cornerCodeOfK(tr) * CORNER_CODE_BASE
        + cornerCodeOfK(br) * CORNER_CODE_BASE * CORNER_CODE_BASE
        + cornerCodeOfK(bl) * CORNER_CODE_BASE * CORNER_CODE_BASE * CORNER_CODE_BASE
}

// `position-try-order` sorts the candidates by the room the region
// offers in one axis. It is not a tie-break inside the overflow retry:
// the sort applies whether or not the original position overflows,
// which Chromium shows by moving a box out of a `bottom` that fits
// (todo.md records the measurement).
// `position-visibility` decides whether an anchored box is painted at
// all, not where it goes. `anchors-visible` is treated as `always`,
// because telling them apart needs the anchor scrolled out of a
// scrollport while the box stays visible and `position-area` ties the
// two together -- a static render has no such state, which todo.md
// records rather than guesses at.
const int POSVIS_ALWAYS = 0
const int POSVIS_NO_OVERFLOW = 1

// The anchored boxes this page hides, by the element id of the box.
// Kept here rather than as a field on `Box`, which is allocated per box
// and pays for a field whether or not anything reads it.
map[bool] anchorHiddenIds = {}
bool anyAnchorHidden = false

const int TRYORDER_NORMAL = 0
const int TRYORDER_MOST_BLOCK = 1
const int TRYORDER_MOST_INLINE = 2

// CSS Anchor Positioning 1. Each axis of `position-area` is one of
// three bands around the anchor, or a span of all three.
const int PAREA_NONE = 0
const int PAREA_BEFORE = 1
const int PAREA_CENTER = 2
const int PAREA_AFTER = 3
const int PAREA_SPAN = 4
// The two axes in one number, block first.
const int PAREA_AXIS = 8

// What the five anchor properties this engine acts on say about one
// element. `anchor-scope` and `position-visibility` are not here: nothing would read them, and a
// property the cascade computes but neither layout nor paint reads is
// not implemented however faithfully it is stored (todo.md says what
// each of them needs). It is
// held off `Style` and indexed from it, because `Style` is read once
// per box throughout layout and a field on it costs time whether or not
// anything reads it -- four floats cost two milliseconds on a page
// using none of them (benchmarks.md). Anchored boxes are rare, so the
// rare data goes in a side table and `Style` carries one int.
struct AnchorInfo {
    name:text            // anchor-name
    anchor:text          // position-anchor
    area:int             // position-area, block * PAREA_AXIS + inline
    fallbacks:text       // position-try-fallbacks, as written
    tryOrder:int         // position-try-order, as a TRYORDER_ value
    visibility:int       // position-visibility, as a POSVIS_ value
    // anchor-scope, lowercased and as written: '' for `none`, 'all',
    // or the comma-separated list of names this element scopes.
    scope:text
    // `anchor()` in the four inset properties, in the order left,
    // right, top, bottom.
    //
    // Every side keyword the function takes is a position along the
    // anchor's box on the property's own axis, so one number carries
    // all of them: `left` and `top` and `start` and `self-start` are 0,
    // `center` is 50, `right` and `bottom` and `end` are 100, and a
    // percentage is itself. It is kept in hundredths of a percent, and
    // -1 means this inset said nothing. An empty name means the one
    // `position-anchor` gave, and a fallback of ANCHOR_NO_FALLBACK
    // means there was none.
    insetNames:arr[text]
    insetPcts:arr[int]
    insetFallbacks:arr[int]
    // `anchor-size()` in the fourteen properties that take it, in the
    // order `width`, `height`, `min-width`, `max-width`, `min-height`,
    // `max-height`, the four margins and the four insets. `padding-*`
    // refuses it, which is measured rather than assumed (todo.md).
    //
    // The dimension is the ANCHOR's rather than the property's --
    // `width: anchor-size(--a height)` is the anchor's height -- so it
    // is kept per slot rather than inferred from which property this
    // is. -1 means the property said nothing. An empty name means the
    // one `position-anchor` gave, and a fallback of ANCHOR_NO_FALLBACK
    // means there was none, which resolves to zero rather than to no
    // effect (todo.md records the measurement).
    sizeNames:arr[text]
    sizeDims:arr[int]
    sizeFallbacks:arr[int]
    // The property's whole value, kept as written, when the function
    // appears inside an expression rather than as the value itself.
    // Both functions resolve to a length, so what an expression needs
    // is the length substituted in and the ordinary parser run over
    // the result -- which is where `calc()`'s arithmetic, precedence
    // and nesting come from rather than being written again here.
    // Empty where this property said nothing, or said the bare form.
    sizeExprs:arr[text]
}

const int ANCHOR_SIZE_WIDTH = 0
const int ANCHOR_SIZE_HEIGHT = 1
const int ANCHOR_SIZE_MINWIDTH = 2
const int ANCHOR_SIZE_MAXWIDTH = 3
const int ANCHOR_SIZE_MINHEIGHT = 4
const int ANCHOR_SIZE_MAXHEIGHT = 5
// The margins and insets take it too, which `anchor()` does not. They
// need no second layout pass of their own -- a margin or an inset can
// be resolved once the anchor's rectangle is known -- but they read the
// same carry, so they are slots on the same list.
const int ANCHOR_SIZE_MARGINLEFT = 6
const int ANCHOR_SIZE_MARGINRIGHT = 7
const int ANCHOR_SIZE_MARGINTOP = 8
const int ANCHOR_SIZE_MARGINBOTTOM = 9
const int ANCHOR_SIZE_LEFT = 10
const int ANCHOR_SIZE_RIGHT = 11
const int ANCHOR_SIZE_TOP = 12
const int ANCHOR_SIZE_BOTTOM = 13
const int ANCHOR_SIZE_SLOTS = 14
const int ANCHOR_DIM_WIDTH = 0
const int ANCHOR_DIM_HEIGHT = 1

const int ANCHOR_INSET_LEFT = 0
const int ANCHOR_INSET_RIGHT = 1
const int ANCHOR_INSET_TOP = 2
const int ANCHOR_INSET_BOTTOM = 3
const int ANCHOR_NO_FALLBACK = -1000000

// This page's anchor declarations; `Style.anchorInfo` is an index into
// it, one past the entry, so that zero means the element said nothing.
arr[AnchorInfo] anchorInfos = []

// Whether any element on this page declared an anchor name at all, so
// that a document with none skips both walks the feature would add.
bool anyAnchorName = false

// Whether any element put an `anchor()` in one of its insets. A page
// with none does not grow the per-inset rectangles below and does not
// test for them while it places its anchored boxes.
bool anyAnchorInset = false
// Whether any element on this document said `anchor-size()` in one of
// the six sizing properties. It is what buys the second layout pass,
// and every page that never says it pays one boolean.
bool anyAnchorSize = false
// The two maps an `anchor-size()` expression resolves into, keyed the
// same way: an expression can carry a percentage of the containing
// block beside the anchor's length, and the containing block is not
// known where the anchor's rectangle is.
map[int] anchorSizePct = {}

// Whether any element scoped a name. A page with none resolves each
// anchor under its bare name, as it did before the property existed,
// and pays nothing for the scope stack -- one bool test per box.
bool anyAnchorScope = false

AnchorInfo func anchorInfoOf(idx:int) {
    if idx <= 0 || idx > anchorInfos.length {
        AnchorInfo none
        none.area = PAREA_NONE
        none.insetNames = ['', '', '', '']
        none.insetPcts = [-1, -1, -1, -1]
        none.insetFallbacks = [ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK,
                               ANCHOR_NO_FALLBACK, ANCHOR_NO_FALLBACK]
        return none
    }
    return anchorInfos[idx - 1]
}

// CSS Motion Path 1. `offset-path` gives a box a path; `offset-distance`
// a point along it; `offset-rotate` which way the box faces there;
// `offset-anchor` which point of the box sits on the path; and
// `offset-position` where the path begins. None of it needs a clock --
// the specification is grouped with the animations in css-2026.md and
// this half of it renders in a still frame.
const int MPATH_NONE = 0
const int MPATH_RAY = 1
const int MPATH_SHAPE = 2       // circle(), ellipse() or polygon()
const int MPATH_PATH = 3        // path('M 0 0 L 100 0')

// How long a ray is, which is what a percentage `offset-distance`
// resolves against. Chromium answers these as though only the top and
// left sides of the containing block existed, so they follow the
// specification here rather than the browser (todo.md records both).
const int RAYSIZE_CLOSEST_SIDE = 0
const int RAYSIZE_CLOSEST_CORNER = 1
const int RAYSIZE_FARTHEST_SIDE = 2
const int RAYSIZE_FARTHEST_CORNER = 3
const int RAYSIZE_SIDES = 4

// offset-rotate. There is no `none`: the grammar is
// `[ auto | reverse ] || <angle>`, so rotation is turned off by writing
// `0deg`, and a declaration saying `none` is dropped.
const int MROT_AUTO = 0
const int MROT_REVERSE = 1
const int MROT_ANGLE = 2

struct MotionInfo {
    pathKind:int
    rayAngle:float          // degrees clockwise from up
    raySize:int
    shape:ClipShape         // MPATH_SHAPE
    pathData:text           // MPATH_PATH, as written
    distance:Len            // offset-distance
    rotateMode:int
    rotateAngle:float       // degrees, added to whatever the mode gives
    anchorX:Len
    anchorY:Len
    anchorAuto:bool         // `auto`, which is the transform origin
    posX:Len
    posY:Len
    posNormal:bool          // `normal`, which is the element's own place
}

// This page's offset declarations, found by the computed style's own
// serial rather than by a field on `Style`. A field there is not free:
// one `int` added to `Style` for this cost the benchmark page a
// measured 1.08 ms of layout -- a page with no `offset-path` on it at
// all -- against a parent-against-parent control of -0.16 ms. A
// computed style is shared between every element that matched the same
// declarations, which is exactly the right grain for this, and the map
// is only ever read behind `anyOffsetPath`.
arr[MotionInfo] motionInfos = []
map[int] motionOfSerial = {}

// Whether any element gave itself a path, so a document with none pays
// one bool test rather than a walk.
bool anyOffsetPath = false

MotionInfo func motionInfoOf(idx:int) {
    if idx <= 0 || idx > motionInfos.length {
        MotionInfo none
        none.pathKind = MPATH_NONE
        none.rotateMode = MROT_AUTO
        none.anchorAuto = true
        none.posNormal = true
        return none
    }
    return motionInfos[idx - 1]
}

const int SCROLLBAR_AUTO = 0
const int SCROLLBAR_THIN = 1
const int SCROLLBAR_NONE = 2

// CSS Overflow 4 §3.3: whether the inline-end gutter is reserved even
// where nothing overflows. `stable` reserves it and `both-edges`
// reserves the inline-start side as well, which is the one value that
// moves a box's content to the right: nothing else here insets a box
// from that side.
const int SCROLLBAR_GUTTER_AUTO = 0
const int SCROLLBAR_GUTTER_STABLE = 1
const int SCROLLBAR_GUTTER_BOTH = 2

const int BRK_AUTO = 0
const int BRK_COLUMN = 1
const int BRK_AVOID = 2
// A page break breaks a column as well, because a column lives on a
// page: the value is separate from BRK_COLUMN so a column context can
// tell which it was asked for, and both force a column to end.
const int BRK_PAGE = 3

// CSS Masking 1's `clip-path`, and the CSS2 `clip` that preceded it.
// A shape is kept as it was written -- lengths and percentages -- and
// resolved against the box at paint time, because the reference box is
// not known until layout has run.
const int CLIPSHAPE_NONE = 0
const int CLIPSHAPE_RECT = 1        // inset(), or a bare geometry box
const int CLIPSHAPE_CIRCLE = 2
const int CLIPSHAPE_ELLIPSE = 3
const int CLIPSHAPE_POLYGON = 4

// Which box a clip resolves against. `clip-path`'s default is the
// border box; `overflow`'s clip is the padding box.
const int GEOBOX_BORDER = 0
const int GEOBOX_PADDING = 1
const int GEOBOX_CONTENT = 2
const int GEOBOX_MARGIN = 3

// A radius written as a keyword rather than a length.
const int CLIPRAD_LENGTH = 0
const int CLIPRAD_CLOSEST = 1
const int CLIPRAD_FARTHEST = 2

struct ClipShape {
    kind:int
    geoBox:int
    // Whether a geometry box was written. `clip-path` resolves against
    // the border box when none was, `shape-outside` against the margin
    // box, so the two need to tell "unsaid" from "border-box".
    geoBoxExplicit:bool
    // inset(): how far in from each edge of the reference box. For the
    // legacy `clip` these hold the same thing, since rect()'s edges are
    // turned into insets when the declaration is read.
    insetTop:Len
    insetRight:Len
    insetBottom:Len
    insetLeft:Len
    // circle() and ellipse(): the centre, and a radius per axis. A
    // circle uses `rx` for both.
    centreX:Len
    centreY:Len
    radiusX:Len
    radiusY:Len
    radiusXKind:int
    radiusYKind:int
    // polygon(): the vertices, x and y in parallel arrays because
    // Festina has no tuples.
    pointsX:arr[Len]
    pointsY:arr[Len]
}

// box-sizing
const int BOX_CONTENT = 0
const int BOX_BORDER = 1

// caption-side
const int CAPTION_TOP = 0
const int CAPTION_BOTTOM = 1

// clear
const int CLEAR_NONE = 0
const int CLEAR_LEFT = 1
const int CLEAR_RIGHT = 2
const int CLEAR_BOTH = 3

// position
const int POS_STATIC = 0
const int POS_RELATIVE = 1
const int POS_ABSOLUTE = 2
const int POS_FIXED = 3
const int POS_STICKY = 4

// border-style
const int BORDER_NONE = 0
const int BORDER_SOLID = 1
const int BORDER_DASHED = 2
const int BORDER_DOTTED = 3
const int BORDER_DOUBLE = 4
const int BORDER_GROOVE = 5
const int BORDER_RIDGE = 6
const int BORDER_INSET = 7
const int BORDER_OUTSET = 8

// text-transform
const int TT_NONE = 0
const int TT_UPPERCASE = 1
const int TT_LOWERCASE = 2
const int TT_CAPITALIZE = 3

// float
const int FLOAT_NONE = 0
const int FLOAT_LEFT = 1
const int FLOAT_RIGHT = 2

// A CSS length after unit resolution: em/rem/pt/px all become px at
// compute time (the font size is known then); percentages stay
// percentages until layout knows the containing block; `auto` and
// `none` are their own kind.
const int LEN_AUTO = 0
const int LEN_PX = 1
const int LEN_PERCENT = 2
// calc() can mix the two -- `calc(100% - 2em)` is the common case -- and
// neither part can be resolved until the containing block is known.
const int LEN_CALC = 3

struct Len {
    kind:int
    v:float     // pixels, or the percentage for LEN_PERCENT
    pct:float   // LEN_CALC only: the percentage part, added to v
}

// A linear gradient, as CSS Images 3 defines it: a line through the box
// at `angle` degrees clockwise from "up", and colour stops along it.
// `stops` and `offsets` are parallel; an offset is a fraction of the
// line's length, already resolved so the painter has only to draw.
//
// Festina's canvas fills a linear gradient between exactly two colours
// (`fillLinearGradient`), so a gradient with more stops is painted as a
// band per adjacent pair. See FINDINGS.md, "a gradient has two stops".
// A stop's position may be a percentage, a length, or absent, and a
// length can only be turned into a fraction once the gradient line's
// length is known -- which is at paint time, not cascade time. So the
// position is kept as it was written.
const int GSTOP_AUTO = 0
const int GSTOP_PERCENT = 1
const int GSTOP_PX = 2

// How far a radial gradient's ray reaches (CSS Images 3 §3.4.2).
// `farthest-corner` is the initial value, so it is 0 and a gradient that
// names no size needs no work.
const int RADEXT_FARTHEST_CORNER = 0
const int RADEXT_CLOSEST_SIDE = 1
const int RADEXT_CLOSEST_CORNER = 2
const int RADEXT_FARTHEST_SIDE = 3
const int RADEXT_EXPLICIT = 4

// One `box-shadow` (Backgrounds and Borders 3 §6). A style with no
// shadow has an empty list, which is the zero value, so nothing is
// written per element.
// One transform function. Festina's canvas composes a matrix from
// translate, rotate and scale and has no call that takes a matrix, so
// `skew()` and `matrix()` cannot be expressed and are dropped rather
// than approximated (FINDINGS.md, "the canvas matrix has no general
// form"). A dropped function is the standard's own fallback for one
// that cannot be applied.
const int TX_TRANSLATE = 0
const int TX_ROTATE = 1
const int TX_SCALE = 2

struct Transform {
    kind:int
    x:Len       // translate: the two offsets, a percentage being of the box
    y:Len
    angle:float // rotate: degrees
    sx:float    // scale: the two factors
    sy:float
}

struct Shadow {
    dx:int
    dy:int
    blur:int
    spread:int
    color:int
    inset:bool
}

// One background layer past the first (Backgrounds and Borders 3
// §3.10). The first layer stays in the `background*` fields of `Style`,
// unchanged, so a page with one background or none -- which is almost
// every page -- allocates nothing and the painter's ordinary path is
// untouched. The layers paint back to front in the reverse of the order
// they are written, so the first one written is on top.
struct BgLayer {
    url:text
    // cross-fade(): the second image and how much of it shows. `fade`
    // is -1 on every layer that is not one, which is what keeps the
    // second pass off the pages that do not use it.
    fadeUrl:text
    fade:float
    image:Gradient
    repeatX:bool
    repeatY:bool
    posX:Len
    posY:Len
    sizeKind:int
    sizeW:Len
    sizeH:Len
    clip:int
    origin:int
    fixed:bool
}

struct Gradient {
    present:bool
    repeating:bool
    angle:float          // degrees, clockwise from pointing up; linear only
    stops:arr[int]       // packed colours
    posKind:arr[int]     // GSTOP_*
    posVal:arr[float]    // a fraction for PERCENT, pixels for PX
    // An interpolation hint (Images 3 §3.4.4) is a bare position
    // between two stops saying where the colour is halfway between
    // them. One entry per stop: the hint that follows it, or
    // GSTOP_AUTO for none.
    hintKind:arr[int]
    hintVal:arr[float]
    // A radial gradient runs out from a centre rather than along a
    // line. The stop list above means the same thing either way: a
    // fraction of the ray instead of a fraction of the line.
    radial:bool
    radialCircle:bool    // `circle`; otherwise an ellipse, the initial shape
    radialExtent:int     // RADEXT_*
    radialRx:Len         // RADEXT_EXPLICIT only
    radialRy:Len
    radialPosX:Len       // the centre, as a fraction of the box, not of any leftover
    radialPosY:Len
    // A conic gradient sweeps around a centre instead of running out
    // from one: a stop's position is an angle rather than a distance,
    // so the stop list means a fraction of the turn. The centre is the
    // radial pair above, which says the same thing.
    conic:bool
    conicFrom:float      // degrees, clockwise from pointing up
}

// The label a list marker shows for its position (CSS2 §12.6).
//
// The alphabetic system is bijective base 26: there is no zero digit, so
// 26 is `z` and 27 is `aa`. Taking the remainder before the decrement
// gives `a0` instead, which is the usual way to get this wrong.
//
// The roman system is the subtractive one -- 4 is `iv`, not `iiii` --
// and it can write neither zero nor a negative nor anything above 3999.
// A counter style that cannot represent its value falls back to decimal,
// which the standard asks for and which is also the only answer that
// leaves the list readable.
text func listMarkerLabel(n:int, style:int) {
    if style == LIST_LOWER_ALPHA || style == LIST_UPPER_ALPHA {
        if n < 1 { return `${n}` }
        text out = ''
        int v = n
        while v > 0 {
            v--
            int digit = v % 26
            text letter = style == LIST_LOWER_ALPHA
                ? 'abcdefghijklmnopqrstuvwxyz'[digit]
                : 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[digit]
            out = letter + out
            v = Math.floorDiv(v, 26)
        }
        return out
    }
    if style == LIST_LOWER_ROMAN || style == LIST_UPPER_ROMAN {
        if n < 1 || n > 3999 { return `${n}` }
        arr[int] values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        arr[text] lower = ['m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i']
        arr[text] upper = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I']
        text out = ''
        int v = n
        for int i = 0, i < values.length, i++ {
            while v >= values[i] {
                out = out + (style == LIST_LOWER_ROMAN ? lower[i] : upper[i])
                v = v - values[i]
            }
        }
        return out
    }
    return `${n}`
}

Gradient func noGradient() {
    Gradient g
    g.present = false
    g.repeating = false
    g.angle = 180.0
    g.stops = []
    g.posKind = []
    g.posVal = []
    g.hintKind = []
    g.hintVal = []
    // The radial fields are left at their zero values, which are already
    // the initial ones: not radial, not a circle, farthest-corner, and a
    // centre that `resolveGradientCenter` reads an unset length as. This
    // runs once per element, so four `Len` structs written here to say
    // what the zero value already says would be four allocations on
    // every element of every page.
    return g
}

struct Style {
    serial:int
    backgroundImage:Gradient
    // A background image from url(). The URL is resolved and fetched by
    // the page pipeline, which stores the decoded image under it.
    backgroundUrl:text
    backgroundFadeUrl:text      // cross-fade()'s second image on the first layer
    backgroundFade:float        // how much of it shows; -1 when there is none
    // border-image. The slices are fractions of the source, held as
    // Len so a number and a percentage keep their meaning; the widths
    // and outsets are px, with -1 meaning "the border's own width",
    // which is the initial value.
    borderImageUrl:text
    borderImageSliceTop:Len
    borderImageSliceRight:Len
    borderImageSliceBottom:Len
    borderImageSliceLeft:Len
    borderImageFill:bool
    borderImageWidthTop:int
    borderImageWidthRight:int
    borderImageWidthBottom:int
    borderImageWidthLeft:int
    borderImageOutset:int
    borderImageRepeat:int
    borderImageRepeatY:int
    backgroundRepeatX:bool
    backgroundRepeatY:bool
    backgroundPosX:Len
    backgroundPosY:Len
    backgroundSizeKind:int
    backgroundSizeW:Len
    backgroundSizeH:Len
    backgroundClip:int
    backgroundOrigin:int
    shadows:arr[Shadow]
    // object-fit and object-position, which move a replaced element's
    // content inside its content box and change no geometry.
    objectFit:int
    objectViewBox:ViewBox
    objectPosX:Len
    objectPosY:Len
    // The declared values, not the running counts: two elements that
    // matched the same rules share this Style and still stand at
    // different counts, which live in the cascade's counter stack.
    // CSS Color Adjustment 1. The resolved answer, not the declared
    // list: nothing here can observe the list, and what the system
    // colours need is the one bit.
    colorSchemeDark:bool
    counterReset:text
    counterSet:text
    quotes:text
    counterIncrement:text
    display:int
    color:int
    background:int
    fontSize:int
    fontBold:bool
    fontItalic:bool
    fontFamily:text
    lineHeight:int          // px; 0 = normal
    textAlign:int
    textDecoration:int
    textTransform:int
    whiteSpaceCollapse:int
    textWrapMode:int
    textAlignLast:int       // -1 = unset, so text-align stands
    wordBreaking:int        // BREAK_NONE / BREAK_WORD / BREAK_ALL
    tabSize:int             // a tab's advance in spaces
    tabSizePx:int           // or in px, when a length was given; -1 otherwise
    hyphensNone:bool        // `hyphens: none` suppresses the soft hyphen
    // hyphenate-character: the string a break shows. Empty means the
    // initial `auto`, which is a hyphen here; it is stored empty rather
    // than as "-" so that a page which never declares it allocates
    // nothing and inherits a zero value.
    hyphenChar:text
    listStyle:int
    // The name list-style-type was given, so a marker can be generated
    // by the counter-style engine. Empty means the built-in bullet the
    // listStyle constant names.
    listStyleName:text
    listImageUrl:text       // list-style-image; empty = the marker the type names
    // CSS Content 3 §2.1: a `content` on an ordinary element that
    // names an image replaces the element's contents with it, which
    // makes the element a replaced element. Empty for every other
    // value, because a string replaces nothing -- measured against
    // Chromium 141, which renders the element's own text for
    // `content: "a string"` and replaces it for `content: url()`.
    // `content` on ::before and ::after is a different thing and is
    // kept beside the pseudo-element's style, not here.
    contentUrl:text
    backgroundFixed:bool    // background-attachment: fixed
    // The layers after the first, in the order they were written. The
    // shared empty list until a page declares a second one.
    bgExtra:arr[BgLayer]
    verticalAlign:int
    floatSide:int
    clearSide:int
    position:int
    top:Len
    right:Len
    bottom:Len
    left:Len
    zIndex:int
    opacity:float           // the element's own computed opacity
    effectiveOpacity:float  // it, multiplied by every ancestor's: paint uses this
    inheritedDecoration:int // decoration propagated from ancestors, for paint
    // How that propagated decoration is drawn. The standard draws an
    // ancestor's decoration across its descendants in the ancestor's
    // own colour, style and thickness, not the descendant's, so those
    // travel with the bits. Where two ancestors decorate the same text
    // differently only the nearer one's appearance survives, since one
    // set of fields cannot hold two answers; css-2026.md records it.
    inheritedDecoColor:int
    inheritedDecoStyle:int
    inheritedDecoThickness:int  // px; 0 = from the font size
    inheritedDecoOffset:int     // px; 0 = auto
    decorationColor:int         // COLOR_UNSET = the text's own colour
    decorationStyle:int
    decorationThickness:int     // px; 0 = from the font size
    underlineOffset:int         // px; 0 = auto
    textShadows:arr[Shadow]
    // text-emphasis: a mark drawn beside every character. The style is
    // kept as the string to draw, which is empty for `none` and so is
    // the initial value and the zero value both.
    emphasisMark:text
    emphasisColor:int       // COLOR_UNSET = the text's own colour
    emphasisUnder:bool
    underlinePosUnder:bool
    // direction. `rtl` is the paragraph's base level for the
    // bidirectional algorithm, and it is what `start` and `end` mean
    // for text-align. It inherits.
    directionRtl:bool
    // Whether text-align was given a side rather than an end. `start`
    // and `end` -- and the initial value, which is `start` -- follow
    // each element's own direction, so they cannot be resolved once and
    // inherited; `left` and `right` can.
    textAlignExplicit:bool
    unicodeBidi:int         // unicode-bidi, as one of the UBIDI_ values
    width:Len
    height:Len
    minWidth:Len
    maxWidth:Len
    minHeight:Len
    maxHeight:Len
    boxSizing:int
    // aspect-ratio (Sizing 4 §4), as the two terms rather than their
    // quotient: `0 / 1` and `2 / 0` are both degenerate and a single
    // float cannot hold the second. `hasAspectRatio` is what says the
    // property was declared at all, since a degenerate ratio is a
    // declared one. `aspectPrefersNatural` is the `auto <ratio>` form,
    // where a natural ratio wins and this is only the fallback.
    aspectW:float
    aspectH:float
    hasAspectRatio:bool
    aspectPrefersNatural:bool
    flexDirection:int
    justifyContent:int
    // Box Alignment 3 on a block container: justifyItems is the
    // default its children take, justifySelf is a child's own answer.
    // BOXALIGN_AUTO on the child means "whatever the parent says",
    // which is its initial value and its zero value both.
    // CSS Multi-column. `columnCount` is 0 for `auto`, and
    // `columnWidth` unset means auto, so the initial value of both is
    // the zero value and a page with no columns writes nothing.
    columnCount:int
    columnWidth:Len
    columnRuleWidth:int
    columnRuleStyle:int
    columnRuleColor:int
    // column-span: all, which takes a child out of the columns and lays
    // it across every one of them, splitting the container in two.
    columnSpanAll:bool
    // column-fill: `balance` is the initial value, so the flag names
    // the other one and a page that never says it carries a false.
    columnFillAuto:bool
    // CSS Fragmentation 3 and CSS2 orphans/widows, which decide where a
    // column may break. `breakBefore` and `breakAfter` are BRK_*;
    // `breakInsideAvoid` is the only value of break-inside that changes
    // anything here. Orphans and widows are the standard's initial 2.
    // CSS Masking 1. `clipShape.kind` is CLIPSHAPE_NONE on a box with
    // no clip, which is every box on almost every page. `clipRect` is
    // the CSS2 `clip`, kept separately because it computes on every box
    // and applies only to a positioned one (CSS2 11.1.2).
    clipShape:ClipShape
    clipRect:ClipShape
    // CSS Shapes 1. A float's exclusion follows this shape rather than
    // its margin box, grown on every side by `shapeMargin`.
    shapeOutside:ClipShape
    shapeMargin:int
    breakBefore:int
    breakAfter:int
    breakInsideAvoid:bool
    // The page this element belongs on (Paged Media 3 §3.4), empty for
    // `auto`. It does not inherit -- Chromium computes `auto` on the
    // child of an element that named a page -- so a named page is the
    // elements that asked for it and the ones laid out between them.
    pageName:text
    // CSS Scrollbars 1. The width and the gutter do not inherit and the
    // colours do, which is what Chromium answers -- the standard makes
    // the width inherited too, and this follows the browser it is
    // measured against. A colour of zero is `auto`: no declared colour,
    // so the painter uses its own.
    // CSS Scroll Snap 1. The type and the padding belong to the scroll
    // container; the align and the margin to the children it snaps to.
    snapX:bool
    snapY:bool
    snapStrict:int
    snapAlignBlock:int
    snapAlignInline:int
    scrollPaddingTop:Len
    scrollPaddingRight:Len
    scrollPaddingBottom:Len
    scrollPaddingLeft:Len
    scrollMarginTop:Len
    scrollMarginRight:Len
    scrollMarginBottom:Len
    scrollMarginLeft:Len
    scrollbarWidth:int
    scrollbarGutter:int
    scrollbarThumb:int
    scrollbarTrack:int
    orphans:int
    widows:int
    justifyItems:int
    // CSS Grid. An empty template is a grid with no explicit tracks in
    // that axis, which is the initial value and costs no allocation.
    // `grid-template-columns: subgrid` takes the tracks from the
    // parent grid's own lines rather than declaring any (CSS Grid 2 §3).
    gridColsSubgrid:bool
    gridRowsSubgrid:bool
    gridCols:arr[Track]
    gridRows:arr[Track]
    // grid-template-areas: the cell names row-major with the row width
    // beside them. Festina rejects `map[arr[T]]` (FINDINGS.md 11-13)
    // and a template is a rectangle, so one flat array and a width is
    // the whole of it. An empty name is a cell belonging to no area.
    gridAreaNames:arr[text]
    // repeat(auto-fill | auto-fit, <list>) cannot be expanded when the
    // template is parsed, because how many times it repeats depends on
    // the space the container turns out to have. The track list holds
    // ONE copy of the repeated group; these say where that copy sits,
    // how long it is, and whether the empty tracks collapse. A length
    // of zero means there is no auto-repeat, which is what a style
    // nobody filled in reads as.
    gridColsAutoAt:int
    gridColsAutoLen:int
    gridColsAutoFit:bool
    gridRowsAutoAt:int
    gridRowsAutoLen:int
    gridRowsAutoFit:bool
    // grid-auto-flow: dense. Sparse packing never moves the cursor
    // backwards; dense starts each item's search over.
    gridAutoFlowDense:bool
    gridAreaCols:int
    // The names a track list writes in brackets: name i sits at line
    // number `gridColLineAt[i]`. Two arrays rather than a map, because
    // one line may carry several names and one name several lines.
    gridColLineNames:arr[text]
    gridColLineAt:arr[int]
    gridRowLineNames:arr[text]
    gridRowLineAt:arr[int]
    gridAutoCols:arr[Track]
    gridAutoRows:arr[Track]
    gridAutoFlowColumn:bool
    gridColStart:GridLine
    gridColEnd:GridLine
    gridRowStart:GridLine
    gridRowEnd:GridLine
    justifySelf:int
    textOverflowEllipsis:bool
    pointerEvents:int
    alignItems:int
    alignSelf:int
    alignContent:int
    flexWrap:int
    flexGrow:float
    flexShrink:float
    flexBasis:Len
    rowGap:int
    columnGap:int
    order:int
    captionSide:int
    wordSpacing:int
    outlineWidth:int
    outlineStyle:int
    outlineOffset:int
    // Containment. Size containment is the one that changes geometry:
    // the box is laid out as if it had no content, and the two
    // intrinsic sizes are what an automatic size resolves to instead.
    // Size containment is per axis: `contain: size` contains both,
    // `contain: inline-size` only the inline one, and CSS Conditional
    // 4's `container-type` is the same containment under another name.
    containInlineSize:bool
    containBlockSize:bool
    containLayout:bool
    containPaint:bool
    containStyle:bool
    // CSS Conditional 4. `container-type` is the containment a query
    // needs in order to be answerable; `container-name` is what a
    // `@container` rule names to pick this one out.
    containerType:int
    containerName:text
    contentHidden:bool      // content-visibility: hidden
    intrinsicWidth:Len
    intrinsicHeight:Len
    transforms:arr[Transform]
    // transform-box: which box a transform-origin resolves against.
    // `content-box` and `fill-box` name the content box; `border-box`,
    // `stroke-box` and `view-box` name the border box, and `view-box`
    // is the initial value, so the flag names the other case and a page
    // that never says it carries a false.
    transformBoxContent:bool
    // CSS UI 4. `appearance`'s initial value is `none`, and the user
    // agent stylesheet is what puts `auto` on the controls it draws --
    // so the flag names `auto`, not `none`, and an element that says
    // nothing carries the initial value rather than the opposite of it.
    // `appearance: none` on a control is then simply the absence of
    // `auto`, which takes away both the drawing and the size the user
    // agent would have supplied.
    appearanceAuto:bool
    fieldSizingContent:bool
    // accent-color, as a packed colour; 0 is `auto`, which is the mark
    // the control would draw anyway.
    accentColor:int
    transformOriginX:Len    // an unset Len is auto, which reads as 50%
    transformOriginY:Len
    tableLayoutFixed:bool
    emptyCellsHide:bool
    listInside:bool
    outlineColor:int
    minHeightSet:bool
    marginTop:Len
    marginRight:Len
    marginBottom:Len
    marginLeft:Len
    paddingTop:Len
    paddingRight:Len
    paddingBottom:Len
    paddingLeft:Len
    borderTop:int
    borderRight:int
    borderBottom:int
    borderLeft:int
    borderTopColor:int
    borderRightColor:int
    borderBottomColor:int
    borderLeftColor:int
    // `borderStyle` is only whether the box has any border at all, kept
    // for the early-out; each side carries its own style, because a box
    // may be solid on one edge and dashed on the next.
    borderStyle:int
    borderTopStyle:int
    borderRightStyle:int
    borderBottomStyle:int
    borderLeftStyle:int
    // Whether any corner is rounded at all: the one test the painter
    // makes before deciding whether a box needs a curved path. The
    // corners themselves are below, and they are kept unresolved
    // because a percentage radius is of the box -- the horizontal of
    // its width, the vertical of its height (Backgrounds and Borders 3
    // §5.1) -- and the box is not known until paint time.
    borderRadius:int
    radiusTopLeftX:Len
    radiusTopLeftY:Len
    radiusTopRightX:Len
    radiusTopRightY:Len
    radiusBottomRightX:Len
    radiusBottomRightY:Len
    radiusBottomLeftX:Len
    radiusBottomLeftY:Len
    // `corner-shape` (CSS Borders 4): the four corners' shapes packed
    // into one field, six bits each, because `Style` is read once per
    // box in layout and four more floats on it cost two milliseconds on
    // a page with no corner shaped at all -- measured, and the reason
    // this is a bitfield rather than four readable members
    // (benchmarks.md). Code zero is `round`, so an unset field is what
    // `border-radius` has always drawn, and codes past the keywords
    // index the exponents `superellipse()` named.
    cornerShapes:int
    anchorInfo:int          // index into anchorInfos, one past the entry
    borderSpacing:int
    borderCollapse:bool
    textIndent:int
    letterSpacing:int
    hidden:bool             // visibility: hidden
    // Whether the box clips its content at all, which every one of
    // `hidden`, `clip`, `scroll` and `auto` does.
    overflowHidden:bool
    overflowX:int
    overflowY:int
    fontKey:text            // cache key for the text measurer
    customProps:map[text]   // custom properties in scope, inherited
}

// text-decoration-line is a bit set built with +, so reading a bit and
// taking a union both have to divide rather than use an operator
// (FINDINGS.md, "no bitwise ops").
bool func decoHas(set:int, bit:int) {
    return Math.floorDiv(set, bit) % 2 == 1
}

int func decoUnion(a:int, b:int) {
    int out = 0
    if decoHas(a, DECO_UNDERLINE) || decoHas(b, DECO_UNDERLINE) { out = out + DECO_UNDERLINE }
    if decoHas(a, DECO_LINE_THROUGH) || decoHas(b, DECO_LINE_THROUGH) { out = out + DECO_LINE_THROUGH }
    if decoHas(a, DECO_OVERLINE) || decoHas(b, DECO_OVERLINE) { out = out + DECO_OVERLINE }
    return out
}

Len func lenPx(px:float) {
    Len l
    l.kind = LEN_PX
    l.v = px
    return l
}

Len func lenAuto() {
    Len l
    l.kind = LEN_AUTO
    return l
}

Len func lenPercent(pct:float) {
    Len l
    l.kind = LEN_PERCENT
    l.v = pct
    return l
}

// Resolves a length against a containing size; `auto` answers `dflt`.
// CSS Inline 3. A line box is taller than its text by the leading, half
// above and half below. `text-box-trim` says which of those halves to
// drop, and `text-box-edge` which two of the font's edges the height
// then runs between. Measured: `trim-both` leaves ascent plus descent
// whatever the line height is, so it removes all the leading rather
// than a fixed amount (todo.md).
const int TBTRIM_NONE = 0
const int TBTRIM_START = 1
const int TBTRIM_END = 2
const int TBTRIM_BOTH = 3

// The over edge, and the under edge. A single keyword is not a value of
// `text-box-edge` -- Chromium computes `cap` alone back to `auto` --
// so only `auto`, `text` and a pair are taken.
const int TBOVER_TEXT = 0
const int TBOVER_CAP = 1
const int TBOVER_EX = 2
const int TBUNDER_TEXT = 0
const int TBUNDER_ALPHABETIC = 1

// Packed as trim * 16 + over * 4 + under, in a map keyed by the
// computed style's serial rather than a field on `Style`, for the
// reason benchmarks.md records.
map[int] textBoxOf = {}
bool anyTextBoxTrim = false

// CSS Overflow 4 §3.3. The edge an `overflow: clip` box clips to is its
// padding box, and `overflow-clip-margin` moves that edge outward: by a
// length, or by naming the box to start from. Held in a page-level map
// keyed by the computed style's serial rather than a field on `Style`,
// for the reason benchmarks.md records -- one `int` there cost the
// benchmark page 1.08 ms of layout, on a page that used none of it.
//
// The value is the pixel length times eight plus the `GEOBOX_` code, so
// one map carries both and a page that never says it carries nothing.
map[int] clipMarginOf = {}
bool anyClipMargin = false

// The packed value, or -1 when this style said nothing.
int func clipMarginPacked(s:Style) {
    if s == null { return -1 }
    text k = `${s.serial}`
    if clipMarginOf[k] == null { return -1 }
    return clipMarginOf[k]
}

// CSS Fragmentation 3 §4.2. `box-decoration-break: clone` puts the
// whole box -- margin, border, padding and background -- on every
// fragment of a broken box, where the initial `slice` puts the opening
// edge on the first fragment and the closing one on the last. Kept in a
// map keyed by the computed style's serial rather than a field on
// `Style`, for the reason benchmarks.md records.
map[int] decoCloneOf = {}
bool anyDecorationClone = false

// Whether this style asked for `clone`. The flag is false on every
// document that never says the property, and `&&` short-circuits, so
// such a document never reaches the map.
bool func decorationIsClone(s:Style) {
    if !anyDecorationClone || s == null { return false }
    return decoCloneOf[`${s.serial}`] != null
}

// CSS Inline 3 §5. `initial-letter: <size> <sink>?` on ::first-letter.
// The size is where the letter's baseline sits -- its cap top is the
// cap top of the first line and its baseline is the baseline of line
// `size` -- so the cap height grows by one line-height for each line
// the letter spans. The sink defaults to the size rounded down, and it
// is the sink that says how many lines are shortened; what is left over
// goes above the text, making the block `size - sink` lines taller.
// Every number of that is measured, in todo.md.
//
// Packed as the size in hundredths times 64 plus the sink, in a map
// keyed by the computed style's serial rather than a field on `Style`,
// for the reason benchmarks.md records.
map[int] initialLetterOf = {}
bool anyInitialLetter = false

int func initialLetterPacked(s:Style) {
    if !anyInitialLetter || s == null { return 0 }
    text k = `${s.serial}`
    if initialLetterOf[k] == null { return 0 }
    return initialLetterOf[k]
}

// The size in hundredths of a line, or 0 where this style said nothing.
int func initialLetterSize100(s:Style) {
    return Math.floorDiv(initialLetterPacked(s), 64)
}

int func initialLetterSink(s:Style) { return initialLetterPacked(s) % 64 }

// CSS Overscroll Behavior 1. A scroll container that has reached its
// end normally passes the scroll outward, to the nearest ancestor that
// can still take it and then to the page. `contain` and `none` stop
// that chain at the box that declares them; they differ only in that
// `none` also suppresses the overscroll affordance, and this browser
// has none to suppress.
const int OSB_AUTO = 0
const int OSB_CONTAIN = 1
const int OSB_NONE = 2

// Packed as x * 4 + y, in a map keyed by the computed style's serial
// rather than a field on `Style`, for the reason benchmarks.md records.
map[int] overscrollOf = {}
bool anyOverscrollBehavior = false

int func overscrollPacked(s:Style) {
    if !anyOverscrollBehavior || s == null { return 0 }
    text k = `${s.serial}`
    if overscrollOf[k] == null { return 0 }
    return overscrollOf[k]
}

int func overscrollX(s:Style) { return Math.floorDiv(overscrollPacked(s), 4) }

int func overscrollY(s:Style) { return overscrollPacked(s) % 4 }

// The packed `text-box` value, or -1 when this style said nothing.
int func textBoxPacked(s:Style) {
    if s == null { return -1 }
    text k = `${s.serial}`
    if textBoxOf[k] == null { return -1 }
    return textBoxOf[k]
}

int func motionIndexOf(s:Style) {
    if s == null { return 0 }
    text k = `${s.serial}`
    if motionOfSerial[k] == null { return 0 }
    return motionOfSerial[k]
}

int func resolveLen(l:Len, base:int, dflt:int) {
    if l == null || l.kind == LEN_AUTO { return dflt }
    if l.kind == LEN_PERCENT { return roundPx(base.toFloat() * l.v / 100.0) }
    if l.kind == LEN_CALC { return roundPx(l.v + base.toFloat() * l.pct / 100.0) }
    return roundPx(l.v)
}

Len func lenCalc(px:float, pct:float) {
    Len l
    l.kind = LEN_CALC
    l.v = px
    l.pct = pct
    return l
}

bool func lenIsAuto(l:Len) {
    return l == null || l.kind == LEN_AUTO
}

bool func displayIsBlockLevel(d:int) {
    return d == DISPLAY_BLOCK || d == DISPLAY_LIST_ITEM || d == DISPLAY_TABLE
        || d == DISPLAY_FLEX || d == DISPLAY_TABLE_CAPTION
}

// DISPLAY_CONTENTS is not here: an element with it generates no box at
// all, so nothing ever asks what level its box is.
bool func displayIsInlineLevel(d:int) {
    return d == DISPLAY_INLINE || d == DISPLAY_INLINE_BLOCK
        || d == DISPLAY_RUBY || d == DISPLAY_INLINE_FLEX
        || d == DISPLAY_INLINE_TABLE
}

// A positioned box is one that `position` takes out of the ordinary
// flow rules: it establishes a containing block for its absolutely
// positioned descendants, and it paints above its in-flow siblings.
bool func positionIsPositioned(p:int) {
    return p != POS_STATIC
}

// Absolute and fixed are the two that leave the flow entirely.
bool func positionIsOutOfFlow(p:int) {
    return p == POS_ABSOLUTE || p == POS_FIXED
}

// The three row-group values differ only in where a table puts them,
// which this engine does not reorder, so layout treats them alike.
bool func displayIsRowGroup(d:int) {
    return d == DISPLAY_TABLE_ROW_GROUP || d == DISPLAY_TABLE_HEADER_GROUP
        || d == DISPLAY_TABLE_FOOTER_GROUP
}

// A column box generates no box of its own; a table reads its width.
bool func displayIsColumn(d:int) {
    return d == DISPLAY_TABLE_COLUMN || d == DISPLAY_TABLE_COLUMN_GROUP
}

// `line-height: normal` has no declared length, so the line box takes a
// multiple of the font size. 1.2 is what the fonts fontconfig serves
// here come out at, and it is what Chromium measures for them: `1lh`
// under `normal` at 16px is 19px in both.
//
// This lives beside the Style rather than in the layout engine because
// the cascade needs the same number: `lh` is a length unit, and a unit
// is resolved where a length is parsed.
const float LINE_NORMAL = 1.2

// Taken as two ints rather than the Style they come from, because a
// forwarded struct parameter is released on exit with a collector walk
// of its subtree (FINDINGS.md, "cycle trials") -- and the cascade asks
// this once per computed style, where the walk would be paid.
int func lineHeightFor(declared:int, fontSize:int) {
    if declared > 0 { return declared }
    return roundPx(fontSize.toFloat() * LINE_NORMAL)
}

int func lineHeightOf(s:Style) {
    return lineHeightFor(s.lineHeight, s.fontSize)
}
