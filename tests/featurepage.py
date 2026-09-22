#!/usr/bin/env python3
"""Generates the second benchmark page and its control.

`generated.html` -- the large page every number in benchmarks.md was
taken against -- is headings, paragraphs, lists and tables. It has no
`<img>`, no counter, no grid, no multi-column container, no transform
and no form control, so six features can land and the benchmark cannot
say what any of them cost. Replacing it would throw the history away,
so this is a second page measured beside it.

Two files come out, with the SAME markup and the same element count:

    features.html         grid, multi-column, counters, transforms,
                          form controls and object-fit, all in use
    features-plain.html   the same document with a stylesheet that
                          turns every one of those off where CSS can

so the difference between them is what the features cost on a page
that uses them, the way grad-flat.html is the control for the gradient
rows. The one thing a stylesheet cannot turn off is the `<img>`
elements themselves: both pages fetch and decode the image, so image
loading is in both numbers and therefore in neither difference. It is
in the end-to-end and `images` phase rows instead.

    python3 tests/featurepage.py <output-directory>
    python3 tests/featurepage.py --verify <output-directory> <browser>

The second form is the instrument checking itself. A benchmark page is
a measuring device like any other here, and a page that has quietly
stopped exercising a feature reads exactly like a feature that costs
nothing. So `--verify` renders the page once, then again with each
feature turned off by an appended rule, and requires the pixels or the
document height to move: a feature whose override changes nothing is
not running on this page and the numbers below it mean nothing. Both
of the traps that rule warns about were caught by it here -- the form
controls sat below the probe's canvas, and the image's natural size
was its box's size, which makes every `object-fit` value paint the
same pixels.
"""
import hashlib
import os
import re
import struct
import subprocess
import sys
import zlib

SECTIONS = 24
CARDS = 3
IMAGE = 'bench-image.png'


def png(path, w, h):
    """An 8-bit RGB PNG, written here so no image has to be vendored.

    The pattern is deterministic and has real variety in it: a flat
    image compresses to nothing and decodes in no time, which would
    make the decode half of the measurement unrepresentative.

    Its natural size is 120x60 and the boxes it goes in are 96x64, so
    the two axes scale by different factors. An image whose natural
    size matches its box makes `object-fit` unmeasurable -- `fill`,
    `cover` and `contain` all paint the same pixels -- which is how
    the first version of this page carried the property without
    exercising it.
    """
    rows = bytearray()
    for y in range(h):
        rows.append(0)                       # filter: none
        for x in range(w):
            rows.append((x * 7 + y * 3) % 256)
            rows.append((x * x + y) % 256)
            rows.append((x ^ (y * 5)) % 256)

    def chunk(tag, payload):
        return (struct.pack('>I', len(payload)) + tag + payload
                + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff))

    with open(path, 'wb') as fh:
        fh.write(b'\x89PNG\r\n\x1a\n')
        fh.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
        fh.write(chunk(b'IDAT', zlib.compress(bytes(rows), 9)))
        fh.write(chunk(b'IEND', b''))


# The stylesheet that uses the features. Every rule here is in the
# document's own <style>, so `tests/chromium.py render` -- which adopts
# the head's <style> elements along with the body -- gives both engines
# the same cascade to do.
ZSTACK_CSS = """
.zstack{position:relative;width:220px;height:34px;background:#dde6f0;margin:6px 0}
.zback{position:absolute;z-index:-1;left:0;top:0;width:220px;height:34px;background:#c0392b}
"""

FEATURES_CSS = """
body{font-family:sans-serif;margin:20px;line-height:1.5;counter-reset:part}
h2{color:#234;border-bottom:1px solid #ccd;counter-increment:part}
h2::before{content:"Part " counter(part) ". ";color:#667}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:8px 0}
.wide{display:grid;grid-template-columns:120px 1fr;grid-template-areas:"pic note" "pic meta";gap:6px}
.wide .pic{grid-area:pic}
.wide .note{grid-area:note}
.wide .meta{grid-area:meta;color:#667}
figure{margin:0;border:1px solid #ccd;border-radius:6px;padding:6px;background:#f8f8fc}
img{width:96px;height:64px;object-fit:cover;object-position:center}
.tall img{object-fit:contain}
figcaption{font-size:12px;color:#556}
.badge{display:inline-block;padding:1px 6px;background:#dde;border-radius:3px;
       transform:rotate(-4deg) translateY(-1px)}
.stamp{display:inline-block;transform:scale(1.2)}
.cols{column-count:3;column-gap:14px;margin:8px 0}
.cols p{margin:0 0 6px 0}
.steps{counter-reset:step;list-style:none;padding-left:0;margin:4px 0}
.steps li{counter-increment:step;margin:2px 0}
.steps li::before{content:counter(step, decimal-leading-zero) ") ";color:#667}
.controls{margin:6px 0;font-size:13px}
.controls input[type=text]{field-sizing:content}
.controls input{accent-color:#47a}
code{font-family:monospace;background:#eef}
table{border-collapse:collapse;width:100%}td,th{border:1px solid #bbb;padding:3px 6px}
th{background:#dde}
"""

# The control. Same selectors, every feature turned off where a
# stylesheet can turn it off: the grids become blocks, the multi-column
# containers become one column, the transforms become `none`, the
# generated counters become no generated content at all, `object-fit`
# goes back to its initial value and the form controls stop being
# painted as form controls.
FEATURES_CSS = FEATURES_CSS + ZSTACK_CSS

PLAIN_CSS = FEATURES_CSS + """
h2::before{content:none}
.cards{display:block}
.wide{display:block}
img{object-fit:fill;object-position:0 0}
.tall img{object-fit:fill}
.badge{transform:none}
.stamp{transform:none}
.cols{column-count:1}
.steps li::before{content:none}
.controls input{appearance:none;field-sizing:fixed}
"""

# One rule per feature, each turning that feature off, and the whole
# point is that each one must change the rendering. The canvas is tall
# enough to reach the first section's form: a probe that cannot see the
# thing it turns off reports every value as equivalent.
PROBES = (
    ('counters', 'h2::before,.steps li::before{content:none}'),
    ('grid', '.cards,.wide{display:block}'),
    ('grid-template-areas', '.wide{grid-template-areas:none}'),
    ('multi-column', '.cols{column-count:1}'),
    ('transforms', '.badge,.stamp{transform:none}'),
    ('appearance', '.controls input{appearance:none}'),
    ('accent-color', '.controls input{accent-color:#000}'),
    ('field-sizing', '.controls input[type=text]{field-sizing:fixed}'),
    # `::placeholder` paints the user agent's grey. Turning it to the
    # input's own colour is what a page with no placeholder on it cannot
    # tell apart -- which is why the page has one.
    ('placeholder', '.controls input::placeholder{color:#000}'),
    # CSS2 §9.9: the `z-index: -1` box belongs to the nearest ancestor
    # stacking context, so it paints behind its parent's background.
    # Making the parent a context puts it in front, which is the whole
    # of the painting order in one pixel.
    ('stacking-order', '.zstack{z-index:0}'),
    ('object-fit', 'img{object-fit:fill}'),
    ('object-position', 'img{object-position:0 0}'),
    ('images', 'img{display:none}'),
)

PROBE_W = 800
PROBE_H = 3000

WORDS = ('measurement layout cascade selector fragment inline baseline '
         'container counter gradient transform column marker replaced '
         'specificity stacking').split()


def paragraph(seed, n):
    return ' '.join(WORDS[(seed * 7 + i * 5) % len(WORDS)] for i in range(n))


def body():
    rows = ['<h1>Feature benchmark page</h1>']
    for s in range(SECTIONS):
        rows.append('<h2>Section %d</h2>' % s)
        rows.append('<div class="wide"><img class="pic" src="%s" alt="">'
                    '<p class="note">%s</p><p class="meta">'
                    '<span class="badge">badge %d</span> '
                    '<span class="stamp">%d</span></p></div>' % (IMAGE, paragraph(s, 14), s, s))
        rows.append('<div class="cards">')
        for c in range(CARDS):
            rows.append('<figure class="%s"><img src="%s" alt="">'
                        '<figcaption>Figure %d.%d, <code>object-fit</code></figcaption>'
                        '</figure>' % ('tall' if c % 2 else 'wide-fit', IMAGE, s, c))
        rows.append('</div>')
        rows.append('<div class="cols">')
        for p in range(3):
            rows.append('<p>%s</p>' % paragraph(s * 3 + p, 26))
        rows.append('</div>')
        rows.append('<ol class="steps">'
                    + ''.join('<li>Step %d of section %d: %s</li>'
                              % (i, s, paragraph(s + i, 5)) for i in range(4))
                    + '</ol>')
        rows.append('<form class="controls">'
                    '<label><input type="checkbox" checked> keep</label> '
                    '<label><input type="checkbox"> drop</label> '
                    '<label><input type="radio" name="m%d" checked> best</label> '
                    '<label><input type="radio" name="m%d"> mean</label> '
                    '<input type="text" value="section %d"> '
                    '<input type="text" placeholder="search section %d"> '
                    '<button type="button">run</button></form>' % (s, s, s, s)),
        rows.append('<div class="zstack"><div class="zback"></div>'
                    'behind and in front</div>')
        rows.append('<table><tr><th>Name</th><th>Kind</th><th>Value</th></tr>')
        for i in range(6):
            rows.append('<tr><td>row %d.%d</td><td>kind %d</td><td>%d</td></tr>'
                        % (s, i, i % 4, i * 37))
        rows.append('</table>')
    return rows


def page(css):
    return '\n'.join(
        ['<!DOCTYPE html><html><head><meta charset="utf-8">',
         '<title>Feature benchmark page</title>',
         '<style>%s</style></head><body>' % css.strip()]
        + body() + ['</body></html>'])


def render(browser, page_path, shot):
    """One render, reported as the pair a feature has to move."""
    proc = subprocess.run([browser, page_path, '--screenshot', shot,
                           '--width', str(PROBE_W), '--height', str(PROBE_H)],
                          capture_output=True, text=True)
    found = re.search(r'document (\d+)px', proc.stdout + proc.stderr)
    with open(shot, 'rb') as fh:
        digest = hashlib.md5(fh.read()).hexdigest()[:12]
    return (found.group(1) if found else '?', digest)


def verify(out, browser):
    """Requires every feature on the page to change the rendering."""
    base = render(browser, os.path.join(out, 'features.html'),
                  os.path.join(out, 'probe-base.png'))
    with open(os.path.join(out, 'features.html')) as fh:
        source = fh.read()
    dead = []
    for label, css in PROBES:
        probe = os.path.join(out, 'probe.html')
        with open(probe, 'w') as fh:
            fh.write(source.replace('</body>', '<style>%s</style></body>' % css))
        if render(browser, probe, os.path.join(out, 'probe.png')) == base:
            dead.append(label)
    if dead:
        print('features.html does not exercise: ' + ', '.join(dead))
        print('  turning each of those off changed neither the pixels nor the document '
              'height, so nothing measured on this page is measuring them.')
        return 1
    print('features.html exercises all %d features: turning any one off changes the render'
          % len(PROBES))
    return 0


def main():
    args = sys.argv[1:]
    checking = args and args[0] == '--verify'
    if checking:
        args = args[1:]
    if not args or (checking and len(args) < 2):
        sys.exit('usage: featurepage.py [--verify] <output-directory> [browser]')
    out = args[0]
    os.makedirs(out, exist_ok=True)
    png(os.path.join(out, IMAGE), 120, 60)
    for name, css in (('features.html', FEATURES_CSS), ('features-plain.html', PLAIN_CSS)):
        with open(os.path.join(out, name), 'w') as fh:
            fh.write(page(css))
    if checking:
        return verify(out, args[1])
    return 0


if __name__ == '__main__':
    sys.exit(main())
