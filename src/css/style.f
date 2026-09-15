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

// text-decoration (a bit set built with + since there are no bitwise ops)
const int DECO_NONE = 0
const int DECO_UNDERLINE = 1
const int DECO_LINE_THROUGH = 2

// white-space
const int WS_NORMAL = 0
const int WS_PRE = 1
const int WS_NOWRAP = 2
const int WS_PRE_WRAP = 3

// list-style-type
const int LIST_NONE = 0
const int LIST_DISC = 1
const int LIST_CIRCLE = 2
const int LIST_SQUARE = 3
const int LIST_DECIMAL = 4

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

struct Gradient {
    present:bool
    repeating:bool
    angle:float          // degrees, clockwise from pointing up
    stops:arr[int]       // packed colours
    posKind:arr[int]     // GSTOP_*
    posVal:arr[float]    // a fraction for PERCENT, pixels for PX
}

Gradient func noGradient() {
    Gradient g
    g.present = false
    g.repeating = false
    g.angle = 180.0
    g.stops = []
    g.posKind = []
    g.posVal = []
    return g
}

struct Style {
    serial:int
    backgroundImage:Gradient
    // The declared values, not the running counts: two elements that
    // matched the same rules share this Style and still stand at
    // different counts, which live in the cascade's counter stack.
    counterReset:text
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
    whiteSpace:int
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
    borderStyle:int
    borderRadius:int
    borderSpacing:int
    borderCollapse:bool
    textIndent:int
    letterSpacing:int
    hidden:bool             // visibility: hidden
    overflowHidden:bool
    fontKey:text            // cache key for the text measurer
    customProps:map[text]   // custom properties in scope, inherited
}

// text-decoration is a bit set built with +, so a union has to check
// each bit rather than use an operator (FINDINGS.md, "no bitwise ops").
int func decoUnion(a:int, b:int) {
    int out = 0
    if a % 2 == 1 || b % 2 == 1 { out = out + DECO_UNDERLINE }
    if Math.floor(a / 2) % 2 == 1 || Math.floor(b / 2) % 2 == 1 { out = out + DECO_LINE_THROUGH }
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
