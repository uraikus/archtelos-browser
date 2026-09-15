#!/usr/bin/env python3
"""Drives headless Chromium so the browser can be compared with a real one.

Two modes, both used by tests/bench.sh:

  conformance  Runs the same web-platform-tests tree-construction corpus
               through Chromium's own HTML parser and reports how many
               cases it passes, so this project's number has a yardstick.

  detail       Reports which individual cases Chromium fails in named
               corpus files, which is how this project finds out whether
               a case it fails is worth chasing.

  parse        Times Chromium's HTML parser on a set of pages, using
               DOMParser inside the page and reporting milliseconds.

  selectors    Reports which element ids each selector in a list matches
               in a fixture document, using querySelectorAll, so this
               project's selector engine can be compared against the
               browser's own rather than against an opinion.

  render       Times parse, style and layout on a set of pages, inside
               the page, so the number excludes process start-up. The
               alternative -- timing the whole command and subtracting a
               start-up baseline -- subtracts two numbers near 500 ms to
               get one near 50, and Chromium's start-up varies by over
               100 ms run to run, so the answer was mostly noise.

Chromium is found via CHROME, or the Playwright browser directory that
ships in this container. Nothing here is part of the browser: it is
benchmark tooling, and it only ever reads the corpus and the pages.
"""

import base64
import glob
import json
import os
import re
import subprocess
import sys
import tempfile


def find_chrome():
    env = os.environ.get("CHROME")
    if env and os.path.exists(env):
        return env
    for pattern in (
        "/opt/pw-browsers/chromium-*/chrome-linux/chrome",
        "/opt/pw-browsers/chromium_headless_shell-*/chrome-linux/headless_shell",
        "/usr/bin/chromium",
        "/usr/bin/google-chrome",
    ):
        hits = sorted(glob.glob(pattern))
        if hits:
            return hits[-1]
    return None


def encode_payload(obj):
    """Base64 so the payload can hold `</script>` and any byte sequence."""
    return base64.b64encode(json.dumps(obj).encode("utf-8")).decode("ascii")


DECODE_JS = ("JSON.parse(new TextDecoder().decode("
             "Uint8Array.from(atob(PAYLOAD), function (c) { return c.charCodeAt(0); })))")

REPORT_JS = """
function report(obj) {
  var bytes = new TextEncoder().encode(JSON.stringify(obj));
  var s = '';
  for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  document.getElementById('out').textContent = 'RESULT' + btoa(s);
}
"""


def read_result(dom):
    match = re.search(r"RESULT([A-Za-z0-9+/=]+)", dom)
    if not match:
        return None
    return json.loads(base64.b64decode(match.group(1)).decode("utf-8"))


def run_chrome(chrome, html, timeout=900):
    """Loads one HTML file headlessly and returns its serialized DOM."""
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as fh:
        fh.write(html)
        path = fh.name
    try:
        out = subprocess.run(
            [chrome, "--headless", "--disable-gpu", "--no-sandbox",
             "--virtual-time-budget=600000", "--dump-dom", "file://" + path],
            capture_output=True, text=True, timeout=timeout,
        )
        return out.stdout
    finally:
        os.unlink(path)


# ---- the corpus -------------------------------------------------------

def read_dat(path):
    """Parses one html5lib .dat file into (data, expected, fragment, script_on)."""
    with open(path, "rb") as fh:
        raw = fh.read()
    if b"\x00" in raw:
        return []
    lines = raw.decode("utf-8", "replace").split("\n")
    cases, section = [], None
    data, doc, fragment, script_on, have = [], [], False, False, False

    def flush():
        if not have:
            return
        d = "\n".join(data)
        while doc and doc[-1] == "":
            doc.pop()
        cases.append((d, "\n".join(doc), fragment, script_on))

    for line in lines + ["#data"]:
        if line == "#data":
            flush()
            data, doc, fragment, script_on, have = [], [], False, False, True
            section = "data"
        elif line in ("#errors", "#new-errors"):
            section = "errors"
        elif line == "#document":
            section = "document"
        elif line == "#document-fragment":
            fragment, section = True, "other"
        elif line == "#script-on":
            script_on, section = True, "other"
        elif line in ("#script-off", "#options"):
            section = "other"
        elif section == "data":
            data.append(line)
        elif section == "document":
            doc.append(line)
    return cases


SERIALIZER = r"""
function nsPrefix(el) {
  var ns = el.namespaceURI;
  if (ns === 'http://www.w3.org/2000/svg') return 'svg ';
  if (ns === 'http://www.w3.org/1998/Math/MathML') return 'math ';
  return '';
}
function attrName(a) {
  var ns = a.namespaceURI;
  if (ns === 'http://www.w3.org/1999/xlink') return 'xlink ' + a.localName;
  if (ns === 'http://www.w3.org/XML/1998/namespace') return 'xml ' + a.localName;
  if (ns === 'http://www.w3.org/2000/xmlns/') return 'xmlns ' + a.localName;
  return a.localName;
}
function ser(node, depth, out) {
  var pad = new Array(depth + 1).join('  ');
  switch (node.nodeType) {
    case 3: out.push('| ' + pad + '"' + node.data + '"'); return;
    case 8: out.push('| ' + pad + '<!-- ' + node.data + ' -->'); return;
    case 10: {
      var s = '| ' + pad + '<!DOCTYPE ' + node.name;
      if (node.publicId || node.systemId)
        s += ' "' + node.publicId + '" "' + node.systemId + '"';
      out.push(s + '>'); return;
    }
    case 1: {
      out.push('| ' + pad + '<' + nsPrefix(node) + node.localName + '>');
      var names = [];
      for (var i = 0; i < node.attributes.length; i++) names.push(node.attributes[i]);
      names.sort(function (a, b) {
        var x = attrName(a), y = attrName(b);
        return x < y ? -1 : (x > y ? 1 : 0);
      });
      for (var i = 0; i < names.length; i++)
        out.push('| ' + pad + '  ' + attrName(names[i]) + '="' + names[i].value + '"');
      if (node.localName === 'template' && node.content) {
        out.push('| ' + pad + '  content');
        for (var c = node.content.firstChild; c; c = c.nextSibling) ser(c, depth + 2, out);
        return;
      }
      break;
    }
  }
  for (var c = node.firstChild; c; c = c.nextSibling) ser(c, depth + 1, out);
}
function serializeDoc(doc) {
  var out = [];
  for (var c = doc.firstChild; c; c = c.nextSibling) ser(c, 0, out);
  return out.join('\n');
}
"""


def conformance(corpus_dir):
    chrome = find_chrome()
    if not chrome:
        print("chromium: not found; skipping", file=sys.stderr)
        return 1
    cases = []
    for path in sorted(glob.glob(os.path.join(corpus_dir, "*.dat"))):
        name = os.path.basename(path)
        for i, (data, expected, fragment, script_on) in enumerate(read_dat(path)):
            if fragment or script_on:
                continue
            cases.append({"f": name, "i": i, "d": data, "e": expected})
    harness = """<!doctype html><body><iframe id=f></iframe><pre id=out></pre><script>
%s
%s
var PAYLOAD = "%s";
var CASES = %s;
var passed = 0, failed = 0, perFile = {};
var frame = document.getElementById('f');
for (var k = 0; k < CASES.length; k++) {
  var c = CASES[k];
  var d = frame.contentDocument;
  d.open(); d.write(c.d); d.close();
  var actual = serializeDoc(d);
  perFile[c.f] = perFile[c.f] || [0, 0];
  perFile[c.f][1]++;
  if (actual === c.e) { passed++; perFile[c.f][0]++; } else { failed++; }
}
report({passed: passed, total: passed + failed, perFile: perFile});
</script>""" % (SERIALIZER, REPORT_JS, encode_payload(cases), DECODE_JS)
    dom = run_chrome(chrome, harness)
    result = read_result(dom)
    if result is None:
        print("chromium: no result from the harness", file=sys.stderr)
        return 1
    print("chromium-conformance %d %d" % (result["passed"], result["total"]))
    for name, (p, t) in sorted(result["perFile"].items()):
        if p != t:
            print("chromium-file %s %d %d" % (name, p, t))
    return 0


def detail(corpus_dir, filenames):
    """Reports which individual cases Chromium fails in the named files."""
    chrome = find_chrome()
    if not chrome:
        print("chromium: not found; skipping", file=sys.stderr)
        return 1
    cases = []
    for name in filenames:
        path = os.path.join(corpus_dir, name)
        for i, (data, expected, fragment, script_on) in enumerate(read_dat(path)):
            if fragment or script_on:
                continue
            cases.append({"f": name, "i": i, "d": data, "e": expected})
    harness = """<!doctype html><body><iframe id=f></iframe><pre id=out></pre><script>
%s
%s
var PAYLOAD = "%s";
var CASES = %s;
var bad = [];
var frame = document.getElementById('f');
for (var k = 0; k < CASES.length; k++) {
  var c = CASES[k];
  var d = frame.contentDocument;
  d.open(); d.write(c.d); d.close();
  var actual = serializeDoc(d);
  if (actual !== c.e) bad.push({f: c.f, i: c.i, d: c.d, e: c.e, a: actual});
}
report(bad);
</script>""" % (SERIALIZER, REPORT_JS, encode_payload(cases), DECODE_JS)
    result = read_result(run_chrome(chrome, harness))
    if result is None:
        print("chromium: no result from the harness", file=sys.stderr)
        return 1
    for b in result:
        print("=== %s #%d" % (b["f"], b["i"]))
        print("  input:    %s" % b["d"][:120].replace("\n", "\\n"))
        print("  expected: %s" % b["e"].replace("\n", " / ")[:220])
        print("  chromium: %s" % b["a"].replace("\n", " / ")[:220])
    print("chromium fails %d of the cases in %s" % (len(result), ", ".join(filenames)))
    return 0


def parse_timing(paths, iterations):
    chrome = find_chrome()
    if not chrome:
        print("chromium: not found; skipping", file=sys.stderr)
        return 1
    docs = {}
    for p in paths:
        with open(p, "rb") as fh:
            docs[os.path.basename(p)] = fh.read().decode("utf-8", "replace")
    harness = """<!doctype html><body><pre id=out></pre><script>
%s
var PAYLOAD = "%s";
var DOCS = %s, N = %d, res = {};
for (var name in DOCS) {
  var html = DOCS[name], best = Infinity;
  for (var i = 0; i < N; i++) {
    var t0 = performance.now();
    var d = new DOMParser().parseFromString(html, 'text/html');
    var t1 = performance.now();
    if (!d.documentElement) throw new Error('parse failed');
    if (t1 - t0 < best) best = t1 - t0;
  }
  res[name] = best;
}
report(res);
</script>""" % (REPORT_JS, encode_payload(docs), DECODE_JS, iterations)
    dom = run_chrome(chrome, harness)
    result = read_result(dom)
    if result is None:
        print("chromium: no result from the harness", file=sys.stderr)
        return 1
    for name, ms in result.items():
        print("chromium-parse %s %.3f" % (name, ms))
    return 0


def render_timing(paths, iterations):
    """Parse, style and lay out each page, inside the page.

    The document is parsed with DOMParser, adopted into a sized
    container in the live document, and then a layout is forced by
    reading offsetHeight -- which is what makes style resolution and
    layout actually happen rather than being deferred. Painting and PNG
    encoding are not included, and neither is process start-up: this is
    the phase this project's cascade and layout are compared against.
    """
    chrome = find_chrome()
    if not chrome:
        print("chromium: not found; skipping", file=sys.stderr)
        return 1
    docs = {}
    for p in paths:
        with open(p, "rb") as fh:
            docs[os.path.basename(p)] = fh.read().decode("utf-8", "replace")
    harness = """<!doctype html><body><pre id=out></pre><div id=host style="width:800px"></div><script>
%s
var PAYLOAD = "%s";
var DOCS = %s, N = %d, res = {};
var host = document.getElementById('host');
for (var name in DOCS) {
  var html = DOCS[name], best = Infinity;
  for (var i = 0; i < N; i++) {
    host.textContent = '';
    var t0 = performance.now();
    var d = new DOMParser().parseFromString(html, 'text/html');
    if (!d.documentElement) throw new Error('parse failed');
    // adopting the body's children keeps the page's own <style> rules,
    // so the cascade has the same work to do as the real load
    var head = d.head ? Array.prototype.slice.call(d.head.children) : [];
    for (var h = 0; h < head.length; h++) {
      if (head[h].tagName === 'STYLE') host.appendChild(document.adoptNode(head[h]));
    }
    while (d.body && d.body.firstChild) host.appendChild(document.adoptNode(d.body.firstChild));
    var h2 = host.offsetHeight;          // forces style and layout
    var t1 = performance.now();
    if (!h2) throw new Error('laid out to nothing');
    if (t1 - t0 < best) best = t1 - t0;
  }
  res[name] = best;
}
report(res);
</script>""" % (REPORT_JS, encode_payload(docs), DECODE_JS, iterations)
    dom = run_chrome(chrome, harness)
    result = read_result(dom)
    if result is None:
        print("chromium: no result from the harness", file=sys.stderr)
        return 1
    for name, ms in result.items():
        print("chromium-render %s %.3f" % (name, ms))
    return 0


def selector_matches(fixture, selector_file):
    """Which element ids each selector matches, according to Chromium.

    The fixture is loaded as a real document and each selector is run
    through querySelectorAll, so the answer is the browser's own
    matching rather than a reimplementation of it. Prints one line per
    selector: the selector, a tab, then the matched ids separated by
    spaces (empty when none matched, the word INVALID when Chromium
    rejects the selector).
    """
    chrome = find_chrome()
    if not chrome:
        print("chromium: not found; skipping", file=sys.stderr)
        return 1
    with open(fixture, "rb") as fh:
        doc = fh.read().decode("utf-8", "replace")
    selectors = []
    with open(selector_file, "rb") as fh:
        for raw in fh.read().decode("utf-8", "replace").split("\n"):
            line = raw.strip()
            # A comment is "# " or a bare "#": an id selector is "#name"
            # with no space, and treating every leading # as a comment
            # silently dropped every id selector from the list.
            if not line or line == "#" or line.startswith("# "):
                continue
            selectors.append(line)
    harness = """<!doctype html><body><pre id=out></pre><script>
%s
var PAYLOAD = "%s";
var DATA = %s, res = {};
var parser = new DOMParser();
var doc = parser.parseFromString(DATA.doc, 'text/html');
for (var i = 0; i < DATA.selectors.length; i++) {
  var sel = DATA.selectors[i];
  try {
    var hits = doc.querySelectorAll(sel);
    var ids = [];
    for (var j = 0; j < hits.length; j++) ids.push(hits[j].id || '?');
    res[sel] = ids.join(' ');
  } catch (e) {
    res[sel] = 'INVALID';
  }
}
report(res);
</script>""" % (REPORT_JS, encode_payload({"doc": doc, "selectors": selectors}), DECODE_JS)
    dom = run_chrome(chrome, harness)
    result = read_result(dom)
    if result is None:
        print("chromium: no result from the harness", file=sys.stderr)
        return 1
    for sel in selectors:
        print("%s\t%s" % (sel, result.get(sel, "INVALID")))
    return 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    if sys.argv[1] == "conformance":
        return conformance(sys.argv[2])
    if sys.argv[1] == "detail":
        return detail(sys.argv[2], sys.argv[3:])
    if sys.argv[1] == "parse":
        return parse_timing(sys.argv[3:], int(sys.argv[2]))
    if sys.argv[1] == "render":
        return render_timing(sys.argv[3:], int(sys.argv[2]))
    if sys.argv[1] == "selectors":
        return selector_matches(sys.argv[2], sys.argv[3])
    if sys.argv[1] == "which":
        chrome = find_chrome()
        print(chrome or "")
        return 0 if chrome else 1
    print("unknown mode %r" % sys.argv[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
