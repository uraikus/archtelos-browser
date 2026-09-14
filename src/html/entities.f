// Character references. The named table covers HTML 4's entity set
// (the ones real pages use); numeric references cover everything
// else, including the ones html/decode.f synthesizes for non-ASCII
// input. int.toChar() does the UTF-8 encoding.

import ../util/text.f

map[int] namedEntities = {
    'amp': 38, 'lt': 60, 'gt': 62, 'quot': 34, 'apos': 39, 'nbsp': 160,
    'iexcl': 161, 'cent': 162, 'pound': 163, 'curren': 164, 'yen': 165,
    'brvbar': 166, 'sect': 167, 'uml': 168, 'copy': 169, 'ordf': 170,
    'laquo': 171, 'not': 172, 'shy': 173, 'reg': 174, 'macr': 175,
    'deg': 176, 'plusmn': 177, 'sup2': 178, 'sup3': 179, 'acute': 180,
    'micro': 181, 'para': 182, 'middot': 183, 'cedil': 184, 'sup1': 185,
    'ordm': 186, 'raquo': 187, 'frac14': 188, 'frac12': 189, 'frac34': 190,
    'iquest': 191, 'Agrave': 192, 'Aacute': 193, 'Acirc': 194, 'Atilde': 195,
    'Auml': 196, 'Aring': 197, 'AElig': 198, 'Ccedil': 199, 'Egrave': 200,
    'Eacute': 201, 'Ecirc': 202, 'Euml': 203, 'Igrave': 204, 'Iacute': 205,
    'Icirc': 206, 'Iuml': 207, 'ETH': 208, 'Ntilde': 209, 'Ograve': 210,
    'Oacute': 211, 'Ocirc': 212, 'Otilde': 213, 'Ouml': 214, 'times': 215,
    'Oslash': 216, 'Ugrave': 217, 'Uacute': 218, 'Ucirc': 219, 'Uuml': 220,
    'Yacute': 221, 'THORN': 222, 'szlig': 223, 'agrave': 224, 'aacute': 225,
    'acirc': 226, 'atilde': 227, 'auml': 228, 'aring': 229, 'aelig': 230,
    'ccedil': 231, 'egrave': 232, 'eacute': 233, 'ecirc': 234, 'euml': 235,
    'igrave': 236, 'iacute': 237, 'icirc': 238, 'iuml': 239, 'eth': 240,
    'ntilde': 241, 'ograve': 242, 'oacute': 243, 'ocirc': 244, 'otilde': 245,
    'ouml': 246, 'divide': 247, 'oslash': 248, 'ugrave': 249, 'uacute': 250,
    'ucirc': 251, 'uuml': 252, 'yacute': 253, 'thorn': 254, 'yuml': 255,
    'OElig': 338, 'oelig': 339, 'Scaron': 352, 'scaron': 353, 'Yuml': 376,
    'fnof': 402, 'circ': 710, 'tilde': 732,
    'Alpha': 913, 'Beta': 914, 'Gamma': 915, 'Delta': 916, 'Epsilon': 917,
    'Zeta': 918, 'Eta': 919, 'Theta': 920, 'Iota': 921, 'Kappa': 922,
    'Lambda': 923, 'Mu': 924, 'Nu': 925, 'Xi': 926, 'Omicron': 927, 'Pi': 928,
    'Rho': 929, 'Sigma': 931, 'Tau': 932, 'Upsilon': 933, 'Phi': 934,
    'Chi': 935, 'Psi': 936, 'Omega': 937,
    'alpha': 945, 'beta': 946, 'gamma': 947, 'delta': 948, 'epsilon': 949,
    'zeta': 950, 'eta': 951, 'theta': 952, 'iota': 953, 'kappa': 954,
    'lambda': 955, 'mu': 956, 'nu': 957, 'xi': 958, 'omicron': 959, 'pi': 960,
    'rho': 961, 'sigmaf': 962, 'sigma': 963, 'tau': 964, 'upsilon': 965,
    'phi': 966, 'chi': 967, 'psi': 968, 'omega': 969,
    'ensp': 8194, 'emsp': 8195, 'thinsp': 8201, 'zwnj': 8204, 'zwj': 8205,
    'lrm': 8206, 'rlm': 8207, 'ndash': 8211, 'mdash': 8212, 'lsquo': 8216,
    'rsquo': 8217, 'sbquo': 8218, 'ldquo': 8220, 'rdquo': 8221, 'bdquo': 8222,
    'dagger': 8224, 'Dagger': 8225, 'bull': 8226, 'hellip': 8230,
    'permil': 8240, 'prime': 8242, 'Prime': 8243, 'lsaquo': 8249,
    'rsaquo': 8250, 'oline': 8254, 'frasl': 8260, 'euro': 8364,
    'image': 8465, 'weierp': 8472, 'real': 8476, 'trade': 8482,
    'alefsym': 8501, 'larr': 8592, 'uarr': 8593, 'rarr': 8594, 'darr': 8595,
    'harr': 8596, 'crarr': 8629, 'lArr': 8656, 'uArr': 8657, 'rArr': 8658,
    'dArr': 8659, 'hArr': 8660, 'forall': 8704, 'part': 8706, 'exist': 8707,
    'empty': 8709, 'nabla': 8711, 'isin': 8712, 'notin': 8713, 'ni': 8715,
    'prod': 8719, 'sum': 8721, 'minus': 8722, 'lowast': 8727, 'radic': 8730,
    'prop': 8733, 'infin': 8734, 'ang': 8736, 'and': 8743, 'or': 8744,
    'cap': 8745, 'cup': 8746, 'int': 8747, 'there4': 8756, 'sim': 8764,
    'cong': 8773, 'asymp': 8776, 'ne': 8800, 'equiv': 8801, 'le': 8804,
    'ge': 8805, 'sub': 8834, 'sup': 8835, 'nsub': 8836, 'sube': 8838,
    'supe': 8839, 'oplus': 8853, 'otimes': 8855, 'perp': 8869, 'sdot': 8901,
    'lceil': 8968, 'rceil': 8969, 'lfloor': 8970, 'rfloor': 8971,
    'lang': 9001, 'rang': 9002, 'loz': 9674, 'spades': 9824, 'clubs': 9827,
    'hearts': 9829, 'diams': 9830, 'check': 10003, 'star': 9734, 'starf': 9733,
    'hyphen': 8208, 'dash': 8208,
}

// Windows-1252 remaps for the numeric references 128-159, which
// browsers treat as cp1252 rather than C1 controls.
int func cp1252(cp:int) {
    if cp == 128 { return 8364 }
    if cp == 130 { return 8218 }
    if cp == 131 { return 402 }
    if cp == 132 { return 8222 }
    if cp == 133 { return 8230 }
    if cp == 134 { return 8224 }
    if cp == 135 { return 8225 }
    if cp == 136 { return 710 }
    if cp == 137 { return 8240 }
    if cp == 138 { return 352 }
    if cp == 139 { return 8249 }
    if cp == 140 { return 338 }
    if cp == 142 { return 381 }
    if cp == 145 { return 8216 }
    if cp == 146 { return 8217 }
    if cp == 147 { return 8220 }
    if cp == 148 { return 8221 }
    if cp == 149 { return 8226 }
    if cp == 150 { return 8211 }
    if cp == 151 { return 8212 }
    if cp == 152 { return 732 }
    if cp == 153 { return 8482 }
    if cp == 154 { return 353 }
    if cp == 155 { return 8250 }
    if cp == 156 { return 339 }
    if cp == 158 { return 382 }
    if cp == 159 { return 376 }
    return cp
}

text func codePointToText(cpIn:int) {
    int cp = cpIn
    if cp >= 128 && cp <= 159 { cp = cp1252(cp) }
    if cp == 0 || cp > 1114111 || (cp >= 55296 && cp <= 57343) { cp = 65533 }
    return cp.toChar()
}

// Replaces every character reference in `s` with the character it
// names. With `numericOnly`, named references are left alone (raw
// text such as a <style> body, where `&amp;` means those five bytes).
// The result is `text`, since the decoded characters are UTF-8.
text func decodeEntities(s:ascii, numericOnly:bool) {
    int n = s.length
    if asciiIndexOf(s, '&', 0) < 0 { return s.toText() }
    text out = ''
    int runStart = 0
    int i = 0
    while i < n {
        if s.charCodeAt(i) != CH_AMP {
            i++
            continue
        }
        int j = i + 1
        int cp = -1
        int end = -1
        if j < n && s.charCodeAt(j) == CH_HASH {
            j++
            bool hex = j < n && (s.charCodeAt(j) == 120 || s.charCodeAt(j) == 88)
            if hex { j++ }
            int v = 0
            int digits = 0
            while j < n {
                int c = s.charCodeAt(j)
                if hex && isHexCode(c) {
                    v = v * 16 + hexValue(c)
                } else if !hex && isDigitCode(c) {
                    v = v * 10 + (c - CH_0)
                } else {
                    break
                }
                if v > 1114111 { v = 65533 }
                digits++
                j++
            }
            if digits > 0 {
                cp = v
                end = j
                if end < n && s.charCodeAt(end) == CH_SEMI { end++ }
            }
        } else if !numericOnly {
            int k = j
            while k < n && isAlnumCode(s.charCodeAt(k)) && k - j < 32 { k++ }
            if k > j {
                text name = s.slice(j, k).toText()
                int found = namedEntities[name]
                bool semi = k < n && s.charCodeAt(k) == CH_SEMI
                // Without a terminating ';' only the legacy handful
                // are recognized, so 'AT&T' and '?a=1&copy=2' behave
                // like a browser.
                if found != null && (semi || name == 'amp' || name == 'lt' || name == 'gt' || name == 'quot' || name == 'nbsp' || name == 'copy' || name == 'reg') {
                    cp = found
                    end = semi ? k + 1 : k
                }
            }
        }
        if cp < 0 {
            i++
            continue
        }
        if i > runStart {
            text run = s.slice(runStart, i).toText()
            out = out + run
        }
        text ch = codePointToText(cp)
        out = out + ch
        i = end
        runStart = end
    }
    if n > runStart {
        text tail = s.slice(runStart, n).toText()
        out = out + tail
    }
    return out
}
