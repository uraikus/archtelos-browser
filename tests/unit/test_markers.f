// List marker numbering (CSS2 §12.6, Counter Styles 3).
//
// `lower-alpha`, `upper-alpha`, `lower-roman` and `upper-roman` all used
// to be parsed as `decimal`, so an ordered list asking for letters or
// roman numerals counted 1, 2, 3.
//
// The alphabetic system is bijective base 26, which is the part that
// invites an off-by-one: there is no zero digit, so 26 is `z` and 27 is
// `aa` rather than `a0`. The roman system is the subtractive one, where
// 4 is `iv` and not `iiii`, and it has no way to write zero or a
// negative, so those fall back to decimal as the standard requires of a
// counter style that cannot represent its value.
import ../../src/css/style.f
import ../assert.f

// ---- decimal -----------------------------------------------------------
checkEq(listMarkerLabel(1, LIST_DECIMAL), '1', 'decimal counts from one')
checkEq(listMarkerLabel(10, LIST_DECIMAL), '10', 'and keeps counting')
checkEq(listMarkerLabel(0, LIST_DECIMAL), '0', 'decimal can write zero')
checkEq(listMarkerLabel(0 - 3, LIST_DECIMAL), '-3', 'and a negative')

// ---- lower-alpha, which is bijective base 26 ---------------------------
checkEq(listMarkerLabel(1, LIST_LOWER_ALPHA), 'a', 'the first letter')
checkEq(listMarkerLabel(2, LIST_LOWER_ALPHA), 'b', 'the second')
checkEq(listMarkerLabel(26, LIST_LOWER_ALPHA), 'z', 'the twenty-sixth is z')
checkEq(listMarkerLabel(27, LIST_LOWER_ALPHA), 'aa', 'and the twenty-seventh is aa, not a0')
checkEq(listMarkerLabel(28, LIST_LOWER_ALPHA), 'ab', 'counting on from there')
checkEq(listMarkerLabel(52, LIST_LOWER_ALPHA), 'az', 'to the end of the second run')
checkEq(listMarkerLabel(53, LIST_LOWER_ALPHA), 'ba', 'which carries into the third')
checkEq(listMarkerLabel(702, LIST_LOWER_ALPHA), 'zz', 'the last of the two-letter labels')
checkEq(listMarkerLabel(703, LIST_LOWER_ALPHA), 'aaa', 'and the first of the three')

// ---- upper-alpha is the same system, in capitals ------------------------
checkEq(listMarkerLabel(1, LIST_UPPER_ALPHA), 'A', 'upper-alpha starts at A')
checkEq(listMarkerLabel(27, LIST_UPPER_ALPHA), 'AA', 'and carries the same way')

// ---- a value the alphabet cannot write falls back to decimal ------------
checkEq(listMarkerLabel(0, LIST_LOWER_ALPHA), '0', 'there is no zeroth letter')
checkEq(listMarkerLabel(0 - 1, LIST_LOWER_ALPHA), '-1', 'nor a negative one')

// ---- lower-roman, subtractive -------------------------------------------
checkEq(listMarkerLabel(1, LIST_LOWER_ROMAN), 'i', 'one')
checkEq(listMarkerLabel(3, LIST_LOWER_ROMAN), 'iii', 'three')
checkEq(listMarkerLabel(4, LIST_LOWER_ROMAN), 'iv', 'four is subtractive, not iiii')
checkEq(listMarkerLabel(9, LIST_LOWER_ROMAN), 'ix', 'and so is nine')
checkEq(listMarkerLabel(14, LIST_LOWER_ROMAN), 'xiv', 'fourteen')
checkEq(listMarkerLabel(40, LIST_LOWER_ROMAN), 'xl', 'forty')
checkEq(listMarkerLabel(90, LIST_LOWER_ROMAN), 'xc', 'ninety')
checkEq(listMarkerLabel(400, LIST_LOWER_ROMAN), 'cd', 'four hundred')
checkEq(listMarkerLabel(900, LIST_LOWER_ROMAN), 'cm', 'nine hundred')
checkEq(listMarkerLabel(1990, LIST_LOWER_ROMAN), 'mcmxc', 'a year with two subtractions')
checkEq(listMarkerLabel(2024, LIST_LOWER_ROMAN), 'mmxxiv', 'and one with a trailing four')
checkEq(listMarkerLabel(3999, LIST_LOWER_ROMAN), 'mmmcmxcix', 'the largest the letters reach')

// ---- upper-roman is the same, in capitals --------------------------------
checkEq(listMarkerLabel(4, LIST_UPPER_ROMAN), 'IV', 'upper-roman capitalises')
checkEq(listMarkerLabel(1990, LIST_UPPER_ROMAN), 'MCMXC', 'throughout')

// ---- and what roman cannot write -----------------------------------------
checkEq(listMarkerLabel(0, LIST_LOWER_ROMAN), '0', 'roman has no zero, so decimal answers')
checkEq(listMarkerLabel(0 - 5, LIST_LOWER_ROMAN), '-5', 'and no negative')
checkEq(listMarkerLabel(4000, LIST_LOWER_ROMAN), '4000', 'and nothing above 3999')

finish('list markers')
