#!/usr/bin/env python3
"""Build docs/index.html: cheat sheets on top, the implementation spec below.

Hand-written parts: docs/forth-cheatsheet.txt, docs/forthlisp-cheatsheet.txt.
Everything else comes from the sources, so the page follows the code:
NOTES.md (spec prose), prims.lisp (primitive table), lisp.fs (special forms,
word list with stack comments), host.lisp (commands, demo checks),
build-firmware.sh / demo.sh / stm32-lisp (build and run), transcript.txt.
A source file that is missing or renamed is skipped, not fatal.
"""
import html, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
esc = html.escape


def read(name):
    p = name if os.path.isabs(name) else os.path.join(ROOT, name)
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def inline(s):
    out = []
    for i, part in enumerate(re.split(r"(`[^`]*`)", s)):
        if i % 2:
            out.append("<code>%s</code>" % esc(part[1:-1]))
        else:
            t = esc(part)
            t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
            t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', t)
            out.append(t)
    return "".join(out)


def md(text, toc, prefix, base=2):
    """Small Markdown subset: headings, paragraphs, lists, tables, code."""
    out, lines, i = [], text.splitlines(), 0
    while i < len(lines):
        l = lines[i]
        m = re.match(r"(#+)\s+(.*)", l)
        if m:
            lvl = min(len(m.group(1)) - 1 + base, 6)
            if lvl < base:
                i += 1
                continue
            a = prefix + slug(m.group(2))
            if lvl <= base + 1:
                toc.append((lvl, a, m.group(2)))
            out.append('<h%d id="%s">%s</h%d>' % (lvl, a, inline(m.group(2)), lvl))
            i += 1
        elif l.startswith("```"):
            j = i + 1
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            out.append("<pre>%s</pre>" % esc("\n".join(lines[i + 1:j])))
            i = j + 1
        elif l.startswith("    "):
            j = i
            while j < len(lines) and (lines[j].startswith("    ") or not lines[j].strip()):
                j += 1
            out.append("<pre>%s</pre>" % esc("\n".join(x[4:] for x in lines[i:j]).rstrip()))
            i = j
        elif l.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            h = "".join("<th>%s</th>" % inline(c) for c in rows[0])
            b = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in r) for r in rows[1:])
            out.append('<div class="tw"><table><tr>%s</tr>%s</table></div>' % (h, b))
        elif re.match(r"- ", l):
            items = []
            while i < len(lines) and (lines[i].startswith("- ") or lines[i].startswith("  ")):
                if lines[i].startswith("- "):
                    items.append(lines[i][2:])
                else:
                    items[-1] += " " + lines[i].strip()
                i += 1
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % inline(x) for x in items))
        elif not l.strip():
            i += 1
        else:
            j = i
            while j < len(lines) and lines[j].strip() and not re.match(r"(#|\||- |```|    )", lines[j]):
                j += 1
            out.append("<p>%s</p>" % inline(" ".join(lines[i:j])))
            i = j
    return "\n".join(out)


def table(head, rows):
    h = "".join("<th>%s</th>" % esc(x) for x in head)
    b = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % c for c in r) for r in rows)
    return '<div class="tw"><table><tr>%s</tr>%s</table></div>' % (h, b)


def code(s):
    return "<code>%s</code>" % esc(s)


def prims_section():
    src = read("prims.lisp")
    if not src:
        return ""
    defs = {m.group(1): (m.group(2), m.group(3)) for m in re.finditer(
        r"^\(defun\s+(\S+)\s+\(([^)]*)\)\s+(.*)\)\s*$", src, re.M)}
    reg = re.search(r"\(defprims(.*?)\)\s*$", src, re.S)
    pairs = re.findall(r"\((\S+)\s+(\S+)\)", reg.group(1)) if reg else []
    rows = []
    for name, word in pairs:
        params, body = defs.get(word, ("", ""))
        nargs = len(set(re.findall(r"\(car(?: \(cdr)* a", body)))
        rows.append([code(name), str(nargs), code(word), code(body)])
    fs = read("lisp.fs") or ""
    for m in re.finditer(r"' (\S+) defprim (\S+)", fs):
        rows.append([code(m.group(2)), "0", code(m.group(1)),
                     "defined in Forth in lisp.fs"])
    return ("<p>Generated from <code>prims.lisp</code> (the <code>defprims</code> table and "
            "each <code>defun</code> body) and the <code>defprim</code> lines of "
            "<code>lisp.fs</code>. Arity = distinct list positions the body reads. "
            "Primitives check argument types but not arity.</p>" + table(["Lisp name", "Arity", "Forth word", "Semantics (host-dialect body)"], rows))


def forms_section():
    fs = read("lisp.fs")
    if not fs:
        return ""
    rows = [[code(n), code(w)] for w, n in re.findall(r"' (\S+) defform (\S+)", fs)]
    return ("<p>Extracted from the <code>defform</code> lines of <code>lisp.fs</code>. A special "
            "form name is bound to a marker value, so a local variable of the same name shadows it.</p>"
            + table(["Special form", "Forth handler"], rows))


def prelude_section():
    s = read("prelude.scm")
    if not s:
        return ""
    names = re.findall(r"^\(define \((\S+)", s, re.M)
    return ("<p>Procedures written in the chip Scheme itself (<code>prelude.scm</code>), loaded "
            "through the REPL at boot:</p><p>%s</p>" % " ".join(code(n) for n in names))


def conformance_section():
    t = read("r7rs-tests.scm")
    if not t:
        return ""
    rows = []
    for l in t.splitlines():
        if not l.strip() or l.startswith(";"):
            continue
        e, _, w = l.partition("==>")
        rows.append([code(e.strip()), code(w.strip())])
    res = read("conformance.txt") or ""
    m = re.search(r"conformance: .*", res)
    head = ("<p><b>Last run on the emulated chip: %s</b> (<code>conformance.txt</code>).</p>"
            % esc(m.group(0))) if m else ""
    return head + "<details><summary>All %d cases (<code>r7rs-tests.scm</code>)</summary>%s</details>" % (
        len(rows), table(["Expression", "Expected print"], rows))


def words_section():
    fs = read("lisp.fs")
    if not fs:
        return ""
    rows, group = [], ""
    for l in fs.splitlines():
        g = re.match(r"\\ --- (.*) ---", l)
        if g:
            group = g.group(1)
        m = re.match(r": (\S+)\s*(\([^)]*\))?\s*(.*)", l)
        if m:
            note = re.search(r"\\\s*(.*)$", l)
            rows.append([esc(group), code(m.group(1)), code(m.group(2) or ""),
                         esc(note.group(1) if note else "")])
    return ("<p>Every colon definition in <code>lisp.fs</code>, in load order, with its stack "
            "comment.</p>" + table(["Section", "Word", "Stack effect", "Comment"], rows))


def header_comment(name, mark):
    s = read(name)
    if not s:
        return ""
    lines = []
    for l in s.splitlines():
        if l.startswith("#!"):
            continue
        if l.startswith(mark):
            lines.append(l[len(mark):].strip())
        elif lines:
            break
    return " ".join(lines)


def build_section():
    rows = []
    for f in ("build-firmware.sh", "demo.sh", "stm32-lisp", "docs/deploy.sh"):
        if read(f) is not None:
            rows.append([code(f), esc(header_comment(f, "#"))])
    host = read("host.lisp") or ""
    cmds = re.findall(r";;;\s{3}(\S+(?: \S+)?)\s{2,}(.*)", host)
    out = table(["File", "Purpose (from its header comment)"], rows)
    if cmds:
        out += "<h3 id=\"spec-host-commands\">host.lisp commands</h3>" + table(
            ["sbcl --script host.lisp ...", "What"], [[code(a), esc(b)] for a, b in cmds])
    for f in ("build-firmware.sh", "demo.sh", "stm32-lisp"):
        s = read(f)
        if s:
            out += "<details><summary><code>%s</code></summary><pre>%s</pre></details>" % (f, esc(s))
    return out


def demo_section():
    host = read("host.lisp") or ""
    checks = re.findall(r'\("((?:[^"\\]|\\.)*)" "((?:[^"\\]|\\.)*)"\)', host)
    out = ""
    if checks:
        out += ("<p>The expressions <code>demo.sh</code> sends to the chip and the answers it "
                "requires (from <code>host.lisp</code>). Any mismatch fails the demo.</p>"
                + table(["Expression", "Expected"], [[code(e), code(w)] for e, w in checks]))
    t = read("transcript.txt")
    if t:
        out += "<details><summary>Last recorded transcript.txt</summary><pre>%s</pre></details>" % esc(t)
    return out


def results_section():
    rows = []
    for layer, f, pat in (("1-2 assembler vs GNU as", "asm-tests.txt", r"asm-test: .*"),
                          ("3 Forth kernel words", "kernel-tests.txt", r"kernel tests: .*"),
                          ("4 Scheme: chibi-scheme R7RS suite (pass / fail / skip / total)",
                           "tests/r7rs/results.txt", r"r7rs suite: .*"),
                          ("4 Scheme: our own regression suite", "conformance.txt", r"conformance: .*"),
                          ("CI: all three public repos in a clean ubuntu:24.04 container", "ci-summary.txt", r"CI: .*")):
        m = re.search(pat, read(f) or "")
        if m:
            rows.append([esc(layer), code(f), esc(m.group(0))])
    return ("<p>Measured on the current stack (own kernel, no third-party Forth). Each file is "
            "written by its test run and committed with the code.</p>"
            + table(["Layer", "File", "Last result"], rows)) if rows else ""


CSS = """
:root{--bg:#fdfdfb;--fg:#1d1d1b;--mut:#666;--line:#ddd;--code:#f2f1ec;--acc:#1f5fbf}
@media (prefers-color-scheme:dark){:root{--bg:#16171a;--fg:#e6e6e3;--mut:#9a9a9a;--line:#33353a;--code:#202227;--acc:#7fb0ff}}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0 auto;max-width:72rem;padding:1rem 16px 4rem;background:var(--bg);color:var(--fg);
font:16px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif}
a{color:var(--acc)}h1{font-size:1.7rem;margin:.2rem 0}h2{border-bottom:1px solid var(--line);padding-bottom:.2rem;margin-top:2.5rem}
code,pre{font-family:ui-monospace,"SFMono-Regular",Menlo,Consolas,monospace;font-size:.88em}
code{background:var(--code);padding:.05em .3em;border-radius:3px}
pre{background:var(--code);padding:.8rem;overflow-x:auto;border-radius:6px;line-height:1.4}
pre code{background:none;padding:0}
.tw{overflow-x:auto}table{border-collapse:collapse;margin:.6rem 0;font-size:.92em}
th,td{border:1px solid var(--line);padding:.3rem .5rem;text-align:left;vertical-align:top}
th{background:var(--code)}.cs{display:grid;gap:1rem;grid-template-columns:repeat(auto-fit,minmax(min(100%,34rem),1fr))}
.cs pre{margin:0;font-size:.82em}nav ol{padding-left:1.2rem}nav li{margin:.1rem 0}.mut{color:var(--mut);font-size:.9em}
details{margin:.5rem 0}summary{cursor:pointer}
"""


def main():
    toc, body = [], []

    def sec(lvl, title, content):
        if not content:
            return
        a = slug(title)
        toc.append((lvl, a, title))
        body.append('<h%d id="%s">%s</h%d>\n%s' % (lvl, a, esc(title), lvl, content))

    # TOP: cheat sheets
    cs = []
    for f, t in (("docs/forth-cheatsheet.txt", "Mecrisp Forth"), ("docs/forthlisp-cheatsheet.txt", "Chip Lisp")):
        s = read(f)
        if s:
            cs.append('<div><h3 id="cheat-%s">%s</h3><pre>%s</pre></div>' % (slug(t), t, esc(s)))
    sec(2, "Cheat sheets", '<div class="cs">%s</div>' % "".join(cs))

    # BELOW: spec
    toc.append((2, "spec", "Implementation spec"))
    body.append('<h2 id="spec">Implementation spec</h2>')
    notes = read("NOTES.md")
    if notes:
        body.append(md(notes, toc, "spec-", base=3))
    sec(3, "Special forms (from lisp.fs)", forms_section())
    sec(3, "Primitives (from prims.lisp)", prims_section())
    sec(3, "Library procedures (from prelude.scm)", prelude_section())
    sec(3, "R7RS conformance subset", conformance_section())
    sec(3, "Forth words of the interpreter (from lisp.fs)", words_section())
    sec(3, "Build, flash, run", build_section())
    sec(3, "Test results by layer", results_section())
    sec(3, "Verified examples", demo_section())
    z = read("z80/NOTES.md")
    if z:
        sec(2, "Z80 version (z80/NOTES.md)", md(z, [], "z80-", base=3))

    try:
        rev = subprocess.run(["git", "-C", ROOT, "log", "-1", "--format=%h %cd", "--date=short"],
                             capture_output=True, text=True).stdout.strip()
    except OSError:
        rev = ""
    nav = "<nav><b>Contents</b><ol>%s</ol></nav>" % "".join(
        '<li style="margin-left:%drem"><a href="#%s">%s</a></li>' % ((lvl - 2) * 1.2, a, inline(t))
        for lvl, a, t in toc)
    page = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>Forth + Lisp on STM32</title><style>%s</style></head><body>
<h1>Assembly &rarr; SBCL &rarr; Forth &rarr; Lisp on STM32</h1>
<p>Source: <a href="https://github.com/equwal/forthlisp">equwal/forthlisp</a> (core: host Lisp, Scheme, R7RS harness) &middot; <a href="https://github.com/equwal/forthlisp-stm32">equwal/forthlisp-stm32</a> (Thumb-2 kernel, QEMU) &middot; <a href="https://github.com/equwal/forthlisp-z80">equwal/forthlisp-z80</a> (Z80 kernel, cpmsim). MIT licence.</p>
<p class="mut">Generated at %s by <code>docs/build-docs.py</code>. Do not edit the HTML; edit the sources.</p>
%s
%s
</body></html>
""" % (CSS, esc(rev or "working tree"), nav, "\n".join(body))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "index.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    print(out)


if __name__ == "__main__":
    main()
