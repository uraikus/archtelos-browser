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

struct Len {
    kind:int
    v:float
}

struct Style {
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
    opacity:float
    width:Len
    height:Len
    minWidth:Len
    maxWidth:Len
    minHeight:Len
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
    return roundPx(l.v)
}

bool func lenIsAuto(l:Len) {
    return l == null || l.kind == LEN_AUTO
}

bool func displayIsBlockLevel(d:int) {
    return d == DISPLAY_BLOCK || d == DISPLAY_LIST_ITEM || d == DISPLAY_TABLE || d == DISPLAY_FLEX
}

bool func displayIsInlineLevel(d:int) {
    return d == DISPLAY_INLINE || d == DISPLAY_INLINE_BLOCK
}
