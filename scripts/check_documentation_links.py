#!/usr/bin/env python3
"""Check local Markdown links and HTML image/link paths in public documentation."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
LINKS = re.compile(r'\]\(([^)]+)\)|(?:src|srcset|href)="([^"]+)"')


def main():
    documents = [ROOT / "README.md", *sorted((ROOT / "Documentation").rglob("*.md"))]
    failures = []
    checked = 0
    for document in documents:
        for match in LINKS.finditer(document.read_text()):
            target = (match.group(1) or match.group(2)).strip().strip("<>")
            url = urlsplit(target)
            if url.scheme or url.netloc or not url.path:
                continue
            checked += 1
            if not (document.parent / unquote(url.path)).exists():
                line = document.read_text()[:match.start()].count("\n") + 1
                failures.append(f"{document.relative_to(ROOT)}:{line}: missing {target}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Checked {checked} local links in {len(documents)} documents.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
