#!/usr/bin/env python3
"""A local HTTP server that answers slowly, for the preload benchmark.

Latency is the only thing a preload scanner hides. On a filesystem
there is none, so measuring the scanner against the local pages the
rest of tests/bench.sh uses would measure nothing. This serves the
same kind of page over a socket with a fixed per-response delay.

  tests/latencyserver.py PORT DELAY_SECONDS

Paths carry their own parameters, because this runtime's HTTP client
drops the query string (FINDINGS.md, "the query string is dropped from
every outbound request"):

  /n8p400     a page with 8 subresources and 400 paragraphs
  /s0.css     one of the stylesheets
  /i0.png     one of the images

Every response is kept under 64 KiB, because a larger one would be read
until the client's own 30 second socket timeout fired (FINDINGS.md, "an
HTTP response larger than 64 KiB takes thirty seconds") and the
benchmark would measure that instead.

Nothing here is part of the browser.
"""
import re
import struct
import sys
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CSS = b"body { margin: 0; font: 16px/20px monospace }\np { color: #0a0 }\n"
JS = b"// a script the preload scanner is meant to notice\n"


def _png(width=8, height=8, rgb=(200, 40, 40)):
    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)
    raw = b''.join(b'\x00' + bytes(rgb) * width for _ in range(height))
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw))
            + chunk(b'IEND', b''))


PNG = _png()
MAX_BODY = 60000          # stay under the client's 64 KiB cliff


def build_page(resources=8, paragraphs=400):
    sheets = resources // 2
    images = resources - sheets
    head = ''.join('<link rel=stylesheet href="/s%d.css">' % i for i in range(sheets))
    imgs = ''.join('<img src="/i%d.png">' % i for i in range(images))
    page = ('<!doctype html><html><head><title>latency</title>%s</head>'
            '<body>%s%s</body></html>')
    # Trim the paragraph count until the whole document fits under the cliff.
    while True:
        body = imgs + '<p>paragraph</p>' * paragraphs
        out = (page % (head, '', body)).encode()
        if len(out) <= MAX_BODY or paragraphs <= 1:
            return out
        paragraphs = paragraphs // 2


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    delay = 0.05

    def do_GET(self):
        time.sleep(self.delay)
        if self.path.endswith('.css'):
            body, ctype = CSS, 'text/css'
        elif self.path.endswith('.png'):
            body, ctype = PNG, 'image/png'
        elif self.path.endswith('.js'):
            body, ctype = JS, 'application/javascript'
        else:
            m = re.match(r'^/n(\d+)p(\d+)', self.path)
            n, paras = (int(m.group(1)), int(m.group(2))) if m else (8, 400)
            body, ctype = build_page(n, paras), 'text/html'
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8731
    Handler.delay = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    print('latency server on %d, %.0f ms per response' % (port, Handler.delay * 1000), flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
