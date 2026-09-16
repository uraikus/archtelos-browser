#!/usr/bin/env python3
"""Generates the three pages the gradient benchmark compares.

Same markup and same layout in all three; only the background differs,
so the difference between them is the cost of painting a gradient.

    python3 tests/gradpages.py <output-directory>
"""
import os
import sys


def page(background):
    rows = ['<!DOCTYPE html><html><head><meta charset="utf-8">',
            '<title>Gradient benchmark page</title>',
            '<style>body{margin:0}div{width:760px;height:60px;margin:4px 20px}</style>',
            '</head><body>']
    for i in range(60):
        rows.append('<div style="background:%s"></div>' % background(i))
    rows.append('</body></html>')
    return '\n'.join(rows)


def two_colors(i):
    """Two colours far apart, so the page is a fair test of the painting.

    A pair that differs only slightly would be painted in the same
    number of bands but would compress to almost nothing, which makes
    the PNG-writing half of the measurement unrepresentative.
    """
    a = ((i * 97) % 256, (i * 151) % 256, (i * 211) % 256)
    b = (255 - a[0], 255 - a[1], 255 - a[2])
    return a[0] << 16 | a[1] << 8 | a[2], b[0] << 16 | b[1] << 8 | b[2]


def main():
    if len(sys.argv) < 2:
        sys.exit('usage: gradpages.py <output-directory>')
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    cases = {
        'grad-flat.html': lambda i: '#%06x' % two_colors(i)[0],
        'grad-on.html': lambda i: 'linear-gradient(to right, #%06x, #%06x)' % two_colors(i),
        'grad-off.html': lambda i: 'linear-gradient(37deg, #%06x, #%06x)' % two_colors(i),
    }
    for name, bg in cases.items():
        with open(os.path.join(out, name), 'w') as fh:
            fh.write(page(bg))
    return 0


if __name__ == '__main__':
    sys.exit(main())
