// CSS Counter Styles 3.
//
// A counter style turns a number into the text of a marker. The
// standard defines five systems and builds every predefined style out
// of them, so that is what this does too: a predefined style is a
// built-in definition and `@counter-style` adds another of the same
// shape. There is one generator, and the names differ only in the
// definition they look up.

const int CS_CYCLIC = 0
const int CS_FIXED = 1
const int CS_SYMBOLIC = 2
const int CS_ALPHABETIC = 3
const int CS_NUMERIC = 4
const int CS_ADDITIVE = 5

struct CounterStyle {
    system:int
    symbols:arr[text]
    addValues:arr[int]      // the `additive-symbols` weights
    addSymbols:arr[text]
    suffix:text
    prefix:text
    padTo:int
    padSymbol:text
    negPrefix:text
    negSuffix:text
    firstValue:int          // `system: fixed` may start somewhere else
    // The numbers this style can write. Outside them the standard falls
    // back to decimal, which is why `lower-roman` of 4000 is `4000` and
    // not four thousand M's.
    rangeMin:int
    rangeMax:int
    hasRange:bool
    defined:bool
}

// The styles a page declared with `@counter-style`.
map[CounterStyle] cssCounterStyles = {}

void func cssResetCounterStyles() {
    map[CounterStyle] empty = {}
    cssCounterStyles = empty
}

arr[text] func csSymbolList(s:text) {
    arr[text] out = []
    for int i = 0, i < s.length, i++ { out.push(s[i]) }
    return out
}

// The predefined styles, built out of the same five systems. Returned
// rather than stored, because a page that uses none of them should
// build none of them.
CounterStyle func csPredefined(name:text) {
    CounterStyle c
    c.suffix = '. '
    c.firstValue = 1
    if name == 'decimal' {
        c.system = CS_NUMERIC
        c.symbols = csSymbolList('0123456789')
        c.defined = true
    } else if name == 'decimal-leading-zero' {
        c.system = CS_NUMERIC
        c.symbols = csSymbolList('0123456789')
        c.padTo = 2
        c.padSymbol = '0'
        c.defined = true
    } else if name == 'lower-alpha' || name == 'lower-latin' {
        c.system = CS_ALPHABETIC
        c.symbols = csSymbolList('abcdefghijklmnopqrstuvwxyz')
        c.defined = true
    } else if name == 'upper-alpha' || name == 'upper-latin' {
        c.system = CS_ALPHABETIC
        c.symbols = csSymbolList('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
        c.defined = true
    } else if name == 'lower-greek' {
        // The standard's list: the Greek alphabet without final sigma,
        // which is twenty-four letters.
        c.system = CS_ALPHABETIC
        c.symbols = csSymbolList('αβγδεζηθικλμνξοπρστυφχψω')
        c.defined = true
    } else if name == 'lower-roman' {
        c.system = CS_ADDITIVE
        c.rangeMin = 1
        c.rangeMax = 3999
        c.hasRange = true
        c.addValues = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        c.addSymbols = ['m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i']
        c.defined = true
    } else if name == 'upper-roman' {
        c.system = CS_ADDITIVE
        c.rangeMin = 1
        c.rangeMax = 3999
        c.hasRange = true
        c.addValues = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        c.addSymbols = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I']
        c.defined = true
    } else if name == 'cjk-decimal' {
        c.system = CS_NUMERIC
        c.symbols = csSymbolList('〇一二三四五六七八九')
        c.suffix = '、'
        c.defined = true
    } else if name == 'disc' || name == 'circle' || name == 'square' {
        c.system = CS_CYCLIC
        c.symbols = [name == 'disc' ? '•' : (name == 'circle' ? '◦' : '▪')]
        c.suffix = ' '
        c.defined = true
    }
    return c
}

// The definition a name resolves to: a page's own first, then the
// predefined ones.
CounterStyle func csLookup(name:text) {
    CounterStyle own = cssCounterStyles[name]
    if own != null && own.defined { return own }
    return csPredefined(name)
}

// The body of the number, before the prefix, suffix and sign.
text func csFormat(c:CounterStyle, n:int) {
    int count = c.symbols.length
    if c.system == CS_CYCLIC {
        if count == 0 { return `${n}` }
        // the standard counts from the first symbol, and a number below
        // one still lands somewhere in the cycle
        int idx = ((n - 1) % count + count) % count
        return c.symbols[idx]
    }
    if c.system == CS_FIXED {
        int idx = n - c.firstValue
        if idx < 0 || idx >= count { return `${n}` }
        return c.symbols[idx]
    }
    if c.system == CS_SYMBOLIC {
        if count == 0 || n < 1 { return `${n}` }
        int idx = (n - 1) % count
        int repeats = Math.floorDiv(n - 1, count) + 1
        text out = ''
        for int i = 0, i < repeats, i++ { out = out + c.symbols[idx] }
        return out
    }
    if c.system == CS_ALPHABETIC {
        if count == 0 || n < 1 { return `${n}` }
        // bijective: the value is decremented before the remainder is
        // taken, or 27 in base 26 would come out as `a0`
        text out = ''
        int v = n
        while v > 0 {
            v--
            out = c.symbols[v % count] + out
            v = Math.floorDiv(v, count)
        }
        return out
    }
    if c.system == CS_NUMERIC {
        if count < 2 { return `${n}` }
        int v = n < 0 ? -n : n
        if v == 0 { return c.symbols[0] }
        text out = ''
        while v > 0 {
            out = c.symbols[v % count] + out
            v = Math.floorDiv(v, count)
        }
        return out
    }
    // additive
    int v = n < 0 ? -n : n
    if v == 0 {
        for int i = 0, i < c.addValues.length, i++ {
            if c.addValues[i] == 0 { return c.addSymbols[i] }
        }
        return `${n}`
    }
    text out = ''
    for int i = 0, i < c.addValues.length, i++ {
        int weight = c.addValues[i]
        if weight <= 0 { continue }
        while v >= weight {
            out = out + c.addSymbols[i]
            v = v - weight
        }
    }
    // A number the symbols cannot write exactly is outside the style's
    // range, and the standard's answer for that is decimal.
    if v != 0 { return `${n}` }
    return out
}

// The marker text for a number in a named style, without its suffix.
text func counterStyleLabel(name:text, n:int) {
    CounterStyle c = csLookup(name)
    if !c.defined { return `${n}` }
    // A system that cannot write this number falls back to decimal
    // rather than inventing a symbol, which is the standard's rule and
    // is why `lower-roman` of 4000 is `4000`.
    if c.hasRange && (n < c.rangeMin || n > c.rangeMax) { return `${n}` }
    bool negative = n < 0
    int v = negative ? -n : n
    if (c.system == CS_SYMBOLIC || c.system == CS_ALPHABETIC || c.system == CS_ADDITIVE)
        && n < 1 {
        return `${n}`
    }
    text body = csFormat(c, negative ? v : n)
    if body == `${negative ? -v : n}` && c.system != CS_NUMERIC { return body }
    if c.padTo > 0 && c.padSymbol != '' {
        while body.length < c.padTo { body = c.padSymbol + body }
    }
    if negative { return c.negPrefix + body + c.negSuffix }
    return body
}

// The suffix a style puts after its marker: `. ` for the numeric and
// alphabetic ones, and whatever `@counter-style` said otherwise.
text func counterStyleSuffix(name:text) {
    CounterStyle c = csLookup(name)
    if !c.defined { return '. ' }
    return c.suffix
}
