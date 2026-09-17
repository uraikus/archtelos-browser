// The computed style of one element: every property the renderer
// understands, already resolved to pixels or to a small int code.
// Structs are the natural home for this in Festina -- every field has
// a zero value, so an element with no style at all reads as all-zero
// and only the cascade fills in what changed. There are no enums with
// named integer members, so each `display`/`text-align`/... value is a
// const int with a naming prefix.

import ../util/color.f

// display
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

// border-image-repeat. `round` and `space` differ from `repeat` only in
// how the last tile is handled, which this engine does not distinguish.
const int BORDERIMG_STRETCH = 0
const int BORDERIMG_REPEAT = 1

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
const int BRK_AUTO = 0
const int BRK_COLUMN = 1
const int BRK_AVOID = 2

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

struct Gradient {
    present:bool
    repeating:bool
    angle:float          // degrees, clockwise from pointing up; linear only
    stops:arr[int]       // packed colours
    posKind:arr[int]     // GSTOP_*
    posVal:arr[float]    // a fraction for PERCENT, pixels for PX
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
    bidiOverride:bool       // unicode-bidi: bidi-override
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
    orphans:int
    widows:int
    justifyItems:int
    // CSS Grid. An empty template is a grid with no explicit tracks in
    // that axis, which is the initial value and costs no allocation.
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
    // The largest of the four corner radii, kept as the one test the
    // painter makes before deciding whether a box needs a curved path at
    // all; the corners themselves are below.
    borderRadius:int
    radiusTopLeft:int
    radiusTopRight:int
    radiusBottomRight:int
    radiusBottomLeft:int
    borderSpacing:int
    borderCollapse:bool
    textIndent:int
    letterSpacing:int
    hidden:bool             // visibility: hidden
    overflowHidden:bool
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
