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
    objectPosX:Len
    objectPosY:Len
    // The declared values, not the running counts: two elements that
    // matched the same rules share this Style and still stand at
    // different counts, which live in the cascade's counter stack.
    counterReset:text
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
    listStyle:int
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
    width:Len
    height:Len
    minWidth:Len
    maxWidth:Len
    minHeight:Len
    maxHeight:Len
    boxSizing:int
    flexDirection:int
    justifyContent:int
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
    containSize:bool
    containLayout:bool
    containPaint:bool
    containStyle:bool
    contentHidden:bool      // content-visibility: hidden
    intrinsicWidth:Len
    intrinsicHeight:Len
    transforms:arr[Transform]
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

bool func displayIsInlineLevel(d:int) {
    return d == DISPLAY_INLINE || d == DISPLAY_INLINE_BLOCK
        || d == DISPLAY_RUBY || d == DISPLAY_CONTENTS || d == DISPLAY_INLINE_FLEX
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
