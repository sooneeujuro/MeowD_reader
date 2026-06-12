#!/usr/bin/env python3
"""Lightweight offline Markdown viewer.

Renders a single ``.md`` file to a self-contained HTML document and opens it
in the OS default browser. No network, no server: Markdown -> HTML is done
locally with python-markdown, everything (styles + scripts) is inlined, and
relative image links resolve against the source file's own folder.

Reading features (all client-side, no server):
  - table-of-contents sidebar (toggle)
  - dark / light theme toggle (defaults to OS theme)
  - copy button on code blocks
  - task-list checkboxes
  - click-to-zoom images
  - print / PDF friendly layout

Editing: a "✎ 편집" button opens the file in an external editor via the
``mdedit:`` custom protocol (handled by md_edit.exe). The viewer itself stays
read-only — no in-browser editor, no save server.

Usage: pyw md_view.py path\\to\\file.md
"""

from __future__ import annotations

import hashlib
import html
import sys
import tempfile
import webbrowser
from pathlib import Path
from urllib.parse import quote

try:
    import markdown
except ImportError:  # pragma: no cover
    markdown = None  # type: ignore[assignment]


PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<base href="{base_href}">
<title>{title}</title>
<style>{css}{hl_css}</style>
</head>
<body class="{body_class}">
<div class="toolbar">
  <span class="tb-file">{title}</span>
  <span class="tb-spacer"></span>
  <button class="tb-btn" type="button" onclick="mdvToggleToc()" title="목차 보이기/숨기기">목차</button>
  <a class="tb-btn" href="{edit_href}" title="외부 편집기에서 열기">✎ 편집</a>
  <button class="tb-btn" type="button" onclick="mdvToggleTheme()" title="라이트/다크 전환">◑ 테마</button>
</div>
<div class="layout">
  <aside class="toc-col">{toc}</aside>
  <main class="md-body">
{body}
  </main>
</div>
<div id="mdv-zoom" class="zoom-overlay"><img alt=""></div>
<script>{script}</script>
</body>
</html>
"""

CSS = """
:root {
  --bg:#ffffff; --fg:#1f2328; --muted:#59636e; --border:#d1d9e0;
  --code-bg:#f6f8fa; --link:#0969da; --quote-fg:#59636e; --quote-bar:#d1d9e0;
  --table-stripe:#f6f8fa; --bar-bg:#f6f8faf2; --btn-bg:#ffffff; --btn-hover:#eef1f4;
}
@media (prefers-color-scheme: dark) {
  html:not([data-theme="light"]) {
    --bg:#0d1117; --fg:#e6edf3; --muted:#9198a1; --border:#30363d;
    --code-bg:#161b22; --link:#4493f8; --quote-fg:#9198a1; --quote-bar:#3d444d;
    --table-stripe:#161b22; --bar-bg:#161b22f2; --btn-bg:#21262d; --btn-hover:#30363d;
  }
}
html[data-theme="dark"] {
  --bg:#0d1117; --fg:#e6edf3; --muted:#9198a1; --border:#30363d;
  --code-bg:#161b22; --link:#4493f8; --quote-fg:#9198a1; --quote-bar:#3d444d;
  --table-stripe:#161b22; --bar-bg:#161b22f2; --btn-bg:#21262d; --btn-hover:#30363d;
}
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--fg);
  font-family:-apple-system,"Segoe UI","Malgun Gothic","Apple SD Gothic Neo",Helvetica,Arial,sans-serif;
  font-size:16px; line-height:1.7; }
.toolbar { position:sticky; top:0; z-index:20; display:flex; align-items:center; gap:8px;
  padding:8px 16px; background:var(--bar-bg); backdrop-filter:blur(6px);
  border-bottom:1px solid var(--border); }
.tb-file { font:12px ui-monospace,"Cascadia Code",Consolas,monospace; color:var(--muted);
  overflow:hidden; text-overflow:ellipsis; white-space:nowrap; max-width:50%; }
.tb-spacer { flex:1; }
.tb-btn { font-size:13px; color:var(--fg); background:var(--btn-bg); border:1px solid var(--border);
  border-radius:6px; padding:4px 10px; cursor:pointer; text-decoration:none; line-height:1.4; }
.tb-btn:hover { background:var(--btn-hover); }
.layout { display:flex; gap:24px; max-width:1140px; margin:0 auto; padding:0 24px; align-items:flex-start; }
.toc-col { position:sticky; top:53px; flex:0 0 240px; max-height:calc(100vh - 70px);
  overflow:auto; padding:24px 0 40px; font-size:13.5px; }
.toc-col .toc > ul { margin:0; padding-left:0; list-style:none; }
.toc-col ul { list-style:none; padding-left:14px; margin:.2em 0; }
.toc-col li { margin:.18em 0; }
.toc-col a { color:var(--muted); text-decoration:none; display:block; padding:2px 6px;
  border-radius:5px; border-left:2px solid transparent; }
.toc-col a:hover { color:var(--fg); background:var(--code-bg); }
.md-body { flex:1 1 auto; min-width:0; max-width:820px; padding:36px 0 96px; }
body.toc-hidden .toc-col, body.no-toc .toc-col { display:none; }
@media (max-width:900px){ .toc-col { display:none; } }
h1,h2,h3,h4,h5,h6 { font-weight:600; line-height:1.3; margin:1.6em 0 .6em; scroll-margin-top:64px; }
h1 { font-size:1.9em; padding-bottom:.3em; border-bottom:1px solid var(--border); margin-top:0; }
h2 { font-size:1.5em; padding-bottom:.3em; border-bottom:1px solid var(--border); }
h3 { font-size:1.25em; } h4 { font-size:1.05em; } h5,h6 { font-size:.95em; color:var(--muted); }
p,ul,ol,blockquote,table,pre { margin:0 0 1em; }
a { color:var(--link); text-decoration:none; } a:hover { text-decoration:underline; }
ul,ol { padding-left:1.6em; } li { margin:.25em 0; }
li.task { list-style:none; margin-left:-1.2em; } li.task input { margin-right:.5em; }
code { font-family:ui-monospace,"Cascadia Code",Consolas,monospace; font-size:85%;
  background:var(--code-bg); padding:.2em .4em; border-radius:6px; }
pre { position:relative; background:var(--code-bg); padding:14px 16px; border-radius:8px;
  overflow-x:auto; border:1px solid var(--border); }
pre code { background:none; padding:0; font-size:88%; }
.copy-btn { position:absolute; top:8px; right:8px; font-size:11px; color:var(--muted);
  background:var(--btn-bg); border:1px solid var(--border); border-radius:5px;
  padding:2px 8px; cursor:pointer; opacity:0; transition:opacity .12s; }
pre:hover .copy-btn { opacity:1; }
blockquote { margin-left:0; padding:.2em 1em; color:var(--quote-fg); border-left:4px solid var(--quote-bar); }
hr { border:none; border-top:1px solid var(--border); margin:2em 0; }
table { border-collapse:collapse; width:100%; display:block; overflow-x:auto; }
th,td { border:1px solid var(--border); padding:6px 13px; } tr:nth-child(2n){ background:var(--table-stripe); }
img { max-width:100%; }
.codehilite { background:var(--code-bg); border-radius:8px; }
.codehilite pre { margin:0; border:1px solid var(--border); border-radius:8px; }
.zoom-overlay { display:none; position:fixed; inset:0; z-index:50; background:rgba(0,0,0,.8);
  align-items:center; justify-content:center; cursor:zoom-out; padding:24px; }
.zoom-overlay img { max-width:96vw; max-height:96vh; border-radius:8px; }
@media print {
  .toolbar,.toc-col,.copy-btn { display:none !important; }
  .layout { display:block; padding:0; max-width:none; } .md-body { max-width:none; padding:0; }
  a { color:inherit; }
}
"""

SCRIPT = """
(function(){
  var root=document.documentElement;
  try{var t=localStorage.getItem('mdv-theme'); if(t) root.setAttribute('data-theme',t);}catch(e){}
  window.mdvToggleTheme=function(){
    var cur=root.getAttribute('data-theme');
    var dark=window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches;
    var next=cur==='dark'?'light':(cur==='light'?'dark':(dark?'light':'dark'));
    root.setAttribute('data-theme',next);
    try{localStorage.setItem('mdv-theme',next);}catch(e){}
  };
  window.mdvToggleToc=function(){document.body.classList.toggle('toc-hidden');};
  function copy(txt,btn){
    function done(){var o=btn.textContent;btn.textContent='복사됨';setTimeout(function(){btn.textContent=o;},1200);}
    if(navigator.clipboard&&navigator.clipboard.writeText){
      navigator.clipboard.writeText(txt).then(done,function(){fallback(txt);done();});
    } else { fallback(txt); done(); }
  }
  function fallback(txt){var ta=document.createElement('textarea');ta.value=txt;
    ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();
    try{document.execCommand('copy');}catch(e){}document.body.removeChild(ta);}
  document.querySelectorAll('pre').forEach(function(pre){
    var code=pre.querySelector('code'); var txt=(code?code.innerText:pre.innerText);
    var b=document.createElement('button'); b.className='copy-btn'; b.type='button'; b.textContent='복사';
    b.onclick=function(){copy(txt,b);}; pre.appendChild(b);
  });
  var ov=document.getElementById('mdv-zoom'); var ovi=ov?ov.querySelector('img'):null;
  document.querySelectorAll('.md-body img').forEach(function(img){
    img.style.cursor='zoom-in';
    img.onclick=function(){ if(ovi){ovi.src=img.currentSrc||img.src; ov.style.display='flex';} };
  });
  if(ov) ov.onclick=function(){ov.style.display='none';};
  // In-page anchor links (TOC sidebar, [x](#section)). Because the page sets
  // <base href> for relative images, a bare "#id" would otherwise resolve
  // against the source folder and navigate to its directory listing. Intercept
  // and scroll within the document instead.
  document.querySelectorAll('a[href^="#"]').forEach(function(a){
    a.addEventListener('click',function(e){
      var raw=a.getAttribute('href').slice(1); if(!raw) return;
      var id; try{id=decodeURIComponent(raw);}catch(_){id=raw;}
      var el=document.getElementById(id)||document.getElementById(raw)||document.getElementsByName(id)[0];
      if(el){e.preventDefault(); el.scrollIntoView({behavior:'smooth',block:'start'});}
    });
  });
})();
"""

import re

_TASK_RE = re.compile(r"<li>\s*\[([ xX])\]\s+")


def _apply_task_lists(body: str) -> str:
    def repl(m: "re.Match[str]") -> str:
        checked = " checked" if m.group(1).lower() == "x" else ""
        return f'<li class="task"><input type="checkbox" disabled{checked}> '
    return _TASK_RE.sub(repl, body)


def _build_highlight_css() -> str:
    try:
        from pygments.formatters import HtmlFormatter
    except ImportError:
        return ""
    light = HtmlFormatter(style="default").get_style_defs(".codehilite")
    try:
        dfmt = HtmlFormatter(style="github-dark")
    except Exception:
        dfmt = HtmlFormatter(style="monokai")
    dark_media = dfmt.get_style_defs('html:not([data-theme="light"]) .codehilite')
    dark_forced = dfmt.get_style_defs('html[data-theme="dark"] .codehilite')
    # Pygments' default style draws a red box around "Error" tokens
    # (.err { border:1px solid #F00 }). When a code fence contains text the
    # lexer can't tokenize (e.g. Korean inside a code block), every such
    # char gets that red border. Harmless but ugly — neutralize it.
    err_fix = (
        ".codehilite .err { border: none !important;"
        " background: transparent !important; }\n"
    )
    return (
        "\n" + light
        + "\n@media (prefers-color-scheme: dark){\n" + dark_media + "\n}\n"
        + dark_forced + "\n"
        + err_fix
    )


HIGHLIGHT_CSS = _build_highlight_css()


def render_html(md_text: str, title: str, base_href: str, edit_href: str) -> str:
    toc_html = ""
    has_toc = False
    if markdown is not None:
        md = markdown.Markdown(
            extensions=["fenced_code", "tables", "toc", "sane_lists",
                        "attr_list", "footnotes"],
            extension_configs={"codehilite": {}},
            output_format="html5",
        )
        try:
            import pygments  # noqa: F401
            md.registerExtensions(["codehilite"], {})
        except ImportError:
            pass
        body = md.convert(md_text)
        body = _apply_task_lists(body)
        toc_html = getattr(md, "toc", "") or ""
        has_toc = bool(getattr(md, "toc_tokens", []))
    else:
        body = "<pre>" + html.escape(md_text) + "</pre>"

    return PAGE_TEMPLATE.format(
        base_href=html.escape(base_href, quote=True),
        title=html.escape(title),
        css=CSS,
        hl_css=HIGHLIGHT_CSS,
        edit_href=html.escape(edit_href, quote=True),
        toc=toc_html,
        body=body,
        body_class="" if has_toc else "no-toc",
        script=SCRIPT,
    )


def _edit_href(src: Path) -> str:
    try:
        target = str(src.resolve())
    except OSError:
        target = str(src)
    return "mdedit:" + quote(target, safe="")


def main(argv: list[str]) -> int:
    if not argv:
        _open_message("열 .md 파일이 지정되지 않았습니다.", "md_view.py <file.md>")
        return 2

    src = Path(argv[0])
    try:
        md_text = src.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        md_text = src.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        _open_message("파일을 열 수 없습니다", f"{src}\n\n{exc}")
        return 1

    try:
        base_href = src.resolve().parent.as_uri() + "/"
    except OSError:
        base_href = ""

    html_text = render_html(md_text, src.name, base_href, _edit_href(src))
    _open_html(html_text, src)
    return 0


def _open_html(html_text: str, src: Path) -> None:
    out_dir = Path(tempfile.gettempdir()) / "md-viewer"
    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        key = str(src.resolve())
    except OSError:
        key = str(src)
    stem = hashlib.sha1(key.encode("utf-8", "replace")).hexdigest()[:12]
    out = out_dir / f"{stem}.html"
    out.write_text(html_text, encoding="utf-8")
    webbrowser.open(out.as_uri())


def _open_message(title: str, detail: str) -> None:
    fake_md = f"# {title}\n\n```\n{detail}\n```"
    out_dir = Path(tempfile.gettempdir()) / "md-viewer"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "_message.html"
    out.write_text(render_html(fake_md, title, "", "mdedit:"), encoding="utf-8")
    webbrowser.open(out.as_uri())


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
