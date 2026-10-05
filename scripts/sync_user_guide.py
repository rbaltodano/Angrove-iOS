#!/usr/bin/env python3
"""Bundle the local website's guide as a self-contained, offline app resource.

Usage: python3 scripts/sync_user_guide.py --website-root '/path/to/site'
No network access, packages, or changes to the website checkout are needed.
"""

import argparse
import base64
import mimetypes
from pathlib import Path
import re


APP_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_ROOT = Path(__file__).resolve().parent


def data_url(path: Path) -> str:
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def bundle(website: Path) -> str:
    html = (website / "guide.html").read_text()
    # Native Settings navigation replaces the site's navigation and download promotion. site.js stays:
    # its nav and footer parts skip themselves, and it runs the headline reveal.
    html = re.sub(r'<header class="nav">.*?</header>', "", html, flags=re.S)
    html = re.sub(r'<section class="cta">.*?</section>', "", html, flags=re.S)
    html = re.sub(r'<footer class="footer">.*?</footer>', "", html, flags=re.S)
    html = re.sub(r'<link rel="(?:icon|apple-touch-icon)"[^>]*>\n?', "", html)
    html = re.sub(r'<script src="js/murmuration\.js[^"\n]*"></script>\n?', "", html)
    html = re.sub(r'<a href="#([a-z-]+)">(.*?)</a>',
                  r'<button type="button" data-guide-topic="\1">\2</button>', html, flags=re.S)
    html = html.replace('stop-color="rgb(74, 50, 28)"', 'stop-color="var(--brown)"')
    html = html.replace('stop-color="rgb(134, 128, 62)"', 'stop-color="var(--light-green)"')
    # Configure one native page before any website script initializes its examples.
    bridge = (SCRIPT_ROOT / "user_guide_app.js").read_text()
    html = html.replace('<script src="js/app-windows.js">', '<script>\n' + bridge + '\n</script>\n<script src="js/app-windows.js">', 1)

    def stylesheet(match: re.Match) -> str:
        css_path = website / match[1].split("?")[0]
        css = re.sub(r"@import\s+url\([^)]*\)\s*;", "", css_path.read_text())
        for rgb, token in [("74,50,28", "ink"), ("134,128,62", "green"),
                           ("34,15,1", "border"), ("243,238,226", "canvas"),
                           ("255,250,240", "cream")]:
            pattern = r"rgba\(\s*" + r"\s*,\s*".join(rgb.split(",")) + r"\s*,"
            css = re.sub(pattern, f"rgba(var(--guide-{token}-rgb),", css)
        # Keep fallback token declarations; replace literal colors in component rules.
        root_end = css.find("\n}") + 2 if ":root {" in css else 0
        defaults, components = css[:root_end], css[root_end:]
        for color, token in [("#4A321C", "brown"), ("#614C40", "heading"),
                             ("#86803E", "light-green"), ("#F3EEE2", "canvas"),
                             ("#FFFAF0", "canvas-secondary"), ("#F0E9DA", "canvas-secondary")]:
            components = re.sub(re.escape(color), f"var(--{token})", components, flags=re.I)
        css = defaults + components
        css = css.replace('.guide-list a', '.guide-list [data-guide-topic]')

        def css_asset(asset: re.Match) -> str:
            url = asset[1].strip("\"'")
            if url.startswith(("data:", "#")):
                return asset[0]
            return 'url("' + data_url((css_path.parent / url).resolve()) + '")'

        css = re.sub(r"url\(([^)]+)\)", css_asset, css)
        return "<style>\n" + css + "\n</style>"

    html = re.sub(r'<link rel="stylesheet" href="([^"]+)">', stylesheet, html)

    def script(match: re.Match) -> str:
        js = (website / match[1].split("?")[0]).read_text()
        if match[1].startswith("js/insight-tree.js"):
            old = "var BROWN = scrollStudy ? '255, 250, 240' : '74, 50, 28';"
            assert old in js, "Website tree palette changed; update the theme adapter."
            js = js.replace(old, """function guideRGB(name) {
    return getComputedStyle(document.documentElement).getPropertyValue('--guide-' + name + '-rgb').trim();
  }
  var BROWN = guideRGB('ink');
  document.addEventListener('guide:appearance', function () { BROWN = guideRGB('ink'); });""")
            js = js.replace("var GREEN = '134, 128, 62', INK = 'rgb(74, 50, 28)', PARA = 'rgba(74, 50, 28, 0.75)';",
                            "var GREEN = guideRGB('green'), INK = 'rgb(' + BROWN + ')', PARA = 'rgba(' + BROWN + ',0.75)';")
            js = js.replace("'rgba(134, 128, 62,'", "'rgba(' + guideRGB('green') + ','")
        if match[1].startswith("js/app-windows.js"):
            old = "var saved = {}, current = null, timer = null;"
            assert old in js, "Website bookmark state changed; update the state adapter."
            js = js.replace(old, old + """
      function restoreSaved() {
        saved = {};
        (window.angroveSaved || []).forEach(function (key) { saved[key] = true; });
        if (current) save.setAttribute('aria-pressed', String(!!saved[current]));
      }
      restoreSaved();
      document.addEventListener('guide:restore-saved', restoreSaved);""")
        js = re.sub(r"assets/[a-zA-Z0-9/_-]+\.(?:svg|png|jpg)",
                    lambda asset: data_url(website / asset[0]), js)
        # Copy stays a user-initiated action; file URLs have no browser Clipboard API.
        js = js.replace("navigator.clipboard.writeText(",
                        "window.webkit.messageHandlers.guideCopy.postMessage(")
        return "<script>\n" + js.replace("</script", "<\\/script") + "\n</script>"

    html = re.sub(r'<script src="([^"]+)"></script>', script, html)
    html = re.sub(r'src="(assets/[^"]+)"',
                  lambda asset: 'src="' + data_url(website / asset[1]) + '"', html)

    fonts = []
    for family, name, weight, style in [
        ("Libre Baskerville", "LibreBaskerville-Regular", 400, "normal"),
        ("Libre Baskerville", "LibreBaskerville-Italic", 400, "italic"),
        ("Figtree", "Figtree-Regular", 400, "normal"),
        ("Figtree", "Figtree-SemiBold", 600, "normal"),
        ("Figtree", "Figtree-Bold", 700, "normal"),
    ]:
        font = data_url(APP_ROOT / "Angrove-iOS" / "Fonts" / (name + ".ttf"))
        fonts.append(f'@font-face {{ font-family: "{family}"; src: url("{font}"); '
                     f'font-weight: {weight}; font-style: {style}; font-display: block; }}')

    fonts.append((SCRIPT_ROOT / "user_guide_app.css").read_text())
    policy = ("default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
              "img-src data:; font-src data:; connect-src 'none'; base-uri 'none'; form-action 'none'")
    html = html.replace("<head>", '<head>\n<meta http-equiv="Content-Security-Policy" '
                        f'content="{policy}">', 1)
    html = html.replace("</head>", "<style>\n" + "\n".join(fonts) + "\n</style>\n</head>")
    return html


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--website-root", type=Path, required=True)
    args = parser.parse_args()
    output = APP_ROOT / "Angrove-iOS" / "Resources" / "UserGuide.html"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(bundle(args.website_root.resolve()))
    print(f"Bundled offline User Guide: {output} ({output.stat().st_size:,} bytes)")
