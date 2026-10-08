#!/usr/bin/env python3
"""Build complete reader documents without altering retrieval chunks or embeddings.

Requires beautifulsoup4 and PyYAML. Run with --backend ../Aquinas_Backend.
The public-domain source downloads are cached separately from the retrieval corpus.
Outputs are generated resources, with source hashes and structural checks in an audit.
"""

from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import json
import re
import shutil
import tempfile
import time
from pathlib import Path
from urllib.request import Request, urlopen

import yaml
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[2]
ROMANS = [
    "I",
    "II",
    "III",
    "IV",
    "V",
    "VI",
    "VII",
    "VIII",
    "IX",
    "X",
    "XI",
    "XII",
    "XIII",
    "XIV",
    "XV",
    "XVI",
    "XVII",
    "XVIII",
    "XIX",
    "XX",
    "XXI",
    "XXII",
    "XXIII",
    "XXIV",
    "XXV",
    "XXVI",
    "XXVII",
    "XXVIII",
    "XXIX",
    "XXX",
    "XXXI",
    "XXXII",
    "XXXIII",
    "XXXIV",
    "XXXV",
    "XXXVI",
    "XXXVII",
    "XXXVIII",
    "XXXIX",
    "XL",
    "XLI",
    "XLII",
    "XLIII",
    "XLIV",
    "XLV",
]
WORD_NUMBERS = [
    "One",
    "Two",
    "Three",
    "Four",
    "Five",
    "Six",
    "Seven",
    "Eight",
    "Nine",
    "Ten",
]
WEB_CHAPTER_COUNTS = {
    code: int(count)
    for code, count in (
        item.split(":")
        for item in [
            "GEN:50",
            "EXO:40",
            "LEV:27",
            "NUM:36",
            "DEU:34",
            "JOS:24",
            "JDG:21",
            "RUT:4",
            "1SA:31",
            "2SA:24",
            "1KI:22",
            "2KI:25",
            "1CH:29",
            "2CH:36",
            "EZR:10",
            "NEH:13",
            "EST:10",
            "JOB:42",
            "PSA:150",
            "PRO:31",
            "ECC:12",
            "SNG:8",
            "ISA:66",
            "JER:52",
            "LAM:5",
            "EZK:48",
            "DAN:12",
            "HOS:14",
            "JOL:3",
            "AMO:9",
            "OBA:1",
            "JON:4",
            "MIC:7",
            "NAM:3",
            "HAB:3",
            "ZEP:3",
            "HAG:2",
            "ZEC:14",
            "MAL:4",
            "MAT:28",
            "MRK:16",
            "LUK:24",
            "JHN:21",
            "ACT:28",
            "ROM:16",
            "1CO:16",
            "2CO:13",
            "GAL:6",
            "EPH:6",
            "PHP:4",
            "COL:4",
            "1TH:5",
            "2TH:3",
            "1TI:6",
            "2TI:4",
            "TIT:3",
            "PHM:1",
            "HEB:13",
            "JAS:5",
            "1PE:5",
            "2PE:3",
            "1JN:5",
            "2JN:1",
            "3JN:1",
            "JUD:1",
            "REV:22",
            "1ES:9",
            "2ES:16",
            "1MA:16",
            "2MA:15",
            "3MA:7",
            "4MA:18",
            "BAR:6",
            "DAG:14",
            "ESG:10",
            "JDT:16",
            "MAN:1",
            "PS2:1",
            "SIR:51",
            "TOB:14",
            "WIS:19",
        ]
    )
}
OVERRIDES = {
    "gibbon-decline-and-fall": [
        (
            f"gibbon{i}",
            f"https://www.gutenberg.org/cache/epub/{730 + i}/pg{730 + i}.txt",
        )
        for i in range(1, 7)
    ],
    "eusebius-ecclesiastical-history": [
        ("eusebius", "https://www.ccel.org/ccel/s/schaff/npnf201/cache/npnf201.txt")
    ],
    "westminster-confession": [
        (
            "westminster",
            "https://en.wikisource.org/wiki/Confession_of_Faith_Ratification_Act_1690",
        )
    ],
    "plutarch-parallel-lives": [
        ("plutarch", "https://www.gutenberg.org/cache/epub/674/pg674.txt")
    ],
    "boethius-consolation": [
        ("boethius", "https://www.gutenberg.org/cache/epub/14328/pg14328.txt")
    ],
    "adam-smith-wealth-of-nations": [
        ("wealth", "https://www.gutenberg.org/cache/epub/3300/pg3300.txt")
    ],
    "summa-theologica": [
        ("summa", "https://www.ccel.org/ccel/a/aquinas/summa/cache/summa.txt")
    ],
    "us-constitution": [
        ("constitution", "https://www.gutenberg.org/cache/epub/5/pg5.txt"),
        (
            "bill-of-rights",
            "https://www.archives.gov/founding-docs/bill-of-rights-transcript",
        ),
        ("amendments", "https://www.archives.gov/founding-docs/amendments-11-27"),
    ],
    "tacitus-annals-histories": [
        ("tacitus-histories", "https://www.gutenberg.org/cache/epub/16927/pg16927.txt")
    ],
}
EXPECTED_MARKERS = {
    "aristotle-nicomachean-ethics": 10,
    "aristotle-metaphysics": 14,
    "augustine-confessions": 13,
    "augustine-city-of-god": 22,
    "josephus-antiquities": 20,
    "bede-ecclesiastical-history": 5,
    "thucydides-peloponnesian-war": 8,
    "herodotus-histories": 9,
    "livy-history-of-rome": 45,
    "tacitus-annals-histories": 12,
    "irenaeus-against-heresies": 173,
}


def download(cache, name, url):
    p = cache / (name + ".txt")
    if not p.exists():
        for attempt in range(4):
            try:
                data = urlopen(
                    Request(
                        url,
                        headers={
                            "User-Agent": "AquinasLibrary/1.0 (public-domain reader)"
                        },
                    ),
                    timeout=60,
                ).read()
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(data)
                break
            except Exception:
                if attempt == 3:
                    raise
                time.sleep(5 * (attempt + 1))
    return p.read_text(encoding="utf-8-sig").replace("\r\n", "\n")


def html_body(text, selector):
    soup = BeautifulSoup(text, "html.parser")
    body = soup.select_one(selector)
    if body is None:
        raise ValueError("Missing document body: " + selector)
    for node in body.select(
        "script, style, nav, .ws-noexport, .licenseContainer, .mw-editsection, #headerContainer, .printfooter"
    ):
        node.decompose()
    for node in body.find_all(["p", "h1", "h2", "h3", "h4", "li", "br"]):
        node.insert_before("\n\n")
        node.insert_after("\n\n")
    return re.sub(r" *\n *", "\n", body.get_text(" ", strip=False))


def gutenberg(text):
    a = re.search(r"^\*\*\* START OF .*?\*\*\*.*?\n", text, re.MULTILINE)
    b = re.search(r"^\*\*\* END OF .*?\*\*\*", text, re.MULTILINE)
    if not a or not b or a.end() >= b.start():
        raise ValueError("Missing Gutenberg edition boundaries")
    return text[a.end() : b.start()].strip()


def between(text, start, end):
    a = re.search(start, text, re.MULTILINE)
    if not a:
        raise ValueError("Missing start boundary " + start)
    b = re.search(end, text[a.start() :], re.MULTILINE)
    if not b:
        raise ValueError("Missing end boundary " + end)
    return text[a.start() : a.start() + b.start()].strip()


def clean_raw(text):
    text = re.sub(r"[\u200b-\u200d\ufeff]", "", text)
    # Remove site navigation and licensing appended to EACH fetched page, preserving prose.
    text = re.sub(
        r"(?ms)^This work (?:was published|is in the public domain).*?(?=^\[|\Z)",
        "",
        text,
    )
    text = re.sub(r"(?ms)^About this page\s*$.*?(?=^\[\d+\]|\Z)", "", text)
    lines = []
    for line in text.splitlines():
        if re.match(
            r"^(?:Search:\s*Submit|Home\s*>|Please help support|Copyright ©|CONTACT US|Public domainPublic|Digitized by|Retrieved from|For other versions of this work)",
            line,
        ):
            continue
        if re.match(r"^\s*[_]{5,}\s*$", line):
            continue
        lines.append(line)
    return "\n".join(lines)


def paragraphs(text):
    # Reader paragraphs retain their original boundaries. They are never sliced at a word quota.
    result = [" ".join(p.split()) for p in re.split(r"\n\s*\n", text) if p.strip()]
    return [p for p in result if not re.fullmatch(r"[_\-.]{8,}", p)]


def numbered_sections(text, pattern, expected=None):
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    parts = []
    if expected is not None and len(matches) != expected:
        raise ValueError(
            f"Expected {expected} headings, found {len(matches)}: {pattern}"
        )
    if matches and text[: matches[0].start()].strip():
        parts.append(("Introduction", text[: matches[0].start()]))
    for i, m in enumerate(matches):
        parts.append(
            (
                m.group().strip(),
                text[
                    m.start() : matches[i + 1].start()
                    if i + 1 < len(matches)
                    else len(text)
                ],
            )
        )
    return parts or [("Complete text", text)]


def marker_sections(text, source_id):
    pattern = (
        r"^\[(\d+)\]\s*$"
        if source_id.startswith("augustine-")
        or source_id == "irenaeus-against-heresies"
        else r"^\[([^\]\n]+/[^\]\n]+)\]\s*$"
    )
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    parts = []
    for i, m in enumerate(matches):
        name = m.group(1)
        label = name.rsplit("/", 1)[-1]
        if name.isdigit():
            n = int(name[-2:])
            label = (
                ("Book " + str(n))
                if source_id.startswith("augustine-")
                else "Book "
                + str(int(name[3]))
                + (": Preface" if n == 0 else ": Chapter " + str(n))
            )
        parts.append(
            (
                label,
                text[
                    m.end() : matches[i + 1].start()
                    if i + 1 < len(matches)
                    else len(text)
                ],
            )
        )
    if source_id in EXPECTED_MARKERS:
        if source_id == "irenaeus-against-heresies" or source_id.startswith(
            "augustine-"
        ):
            eligible = parts
        else:
            eligible = [
                p
                for p in parts
                if re.match(
                    r"^Book (?:\d+|[IVXLCDM]+|" + "|".join(WORD_NUMBERS) + r")$", p[0]
                )
            ]
        if len(eligible) != EXPECTED_MARKERS[source_id]:
            raise ValueError(f"{source_id}: missing books ({len(eligible)})")

    def order(p):
        label = p[0]
        m = re.match(
            r"(?:Book|Chapter) (\d+|[IVXLCDM]+|" + "|".join(WORD_NUMBERS) + r")\b",
            label,
        )
        if m:
            v = m.group(1)
            n = (
                int(v)
                if v.isdigit()
                else ROMANS.index(v) + 1
                if v in ROMANS
                else WORD_NUMBERS.index(v) + 1
            )
            sub = re.search(r"Chapter (\d+)", label)
            return (1, n, int(sub.group(1)) if sub else 0)
        return (
            (2, 0, 0)
            if label.casefold()
            in [
                "end matter",
                "appendix",
                "notes",
                "references to quotations in the text",
            ]
            else (0, 0, 0)
        )

    # Prefaces first, numeric book order next. Python's stable sort retains chapter order.
    return sorted(parts, key=order) if parts else [("Complete text", text)]


def sections_for(source, text, cache):
    sid = source["id"]
    provenance = []
    downloaded = {}
    for name, url in OVERRIDES.get(sid, []):
        t = download(cache, name, url)
        downloaded[name] = t
        provenance.append(
            {"url": url, "sha256": hashlib.sha256(t.encode()).hexdigest()}
        )
    if sid == "gibbon-decline-and-fall":
        parts = [
            ("Volume " + str(i), gutenberg(downloaded["gibbon" + str(i)]))
            for i in range(1, 7)
        ]
        nums = {
            m.group(1)
            for _, t in parts
            for m in re.finditer(r"^\s*Chapter ([IVXLCDM]+):", t, re.MULTILINE)
        }
        if len(nums) != 71:
            raise ValueError("Gibbon must contain all 71 chapters")
    elif sid == "eusebius-ecclesiastical-history":
        t = between(
            downloaded["eusebius"],
            r"^\s*The Church History of Eusebius\.\s*$",
            r"^\s*the life of constantine,\s*$",
        )
        t = re.sub(r"\[\d+\]", "", t)
        parts = numbered_sections(t, r"^\s*Book [IVXLCDM]+\.\s*$", 10)
    elif sid == "westminster-confession":
        t = html_body(downloaded["westminster"], ".mw-parser-output")
        parts = numbered_sections(t, r"^Chap\. [ivxlcdm]+\. Of[^\n]+", 33)
    elif sid == "plutarch-parallel-lives":
        t = gutenberg(downloaded["plutarch"])
        start = t.find(
            "\nTHESEUS",
            t.find(
                "*********************************************************************"
            ),
        )
        if start < 0:
            raise ValueError("Missing Plutarch body")
        t = t[start:]
        parts = numbered_sections(t, r"^[A-Z][A-Z ,\-\.]+$")
        if len([p for p in parts if not p[0].startswith("COMPAR")]) != 50:
            raise ValueError("Plutarch must contain all 50 lives")
    elif sid == "boethius-consolation":
        t = gutenberg(downloaded["boethius"])
        matches = list(re.finditer(r"^BOOK ([IVX]+)\.\s*$", t, re.MULTILINE))
        starts = {}
        for m in matches[5:]:
            starts.setdefault(m.group(1), m.start())
        if list(starts) != ROMANS[:5]:
            raise ValueError("Missing Boethius book sequence")
        points = [("Introduction", 0)] + [("Book " + n, starts[n]) for n in ROMANS[:5]]
        parts = [
            (label, t[lo : points[i + 1][1] if i + 1 < len(points) else len(t)])
            for i, (label, lo) in enumerate(points)
        ]
        if not all("BOOK " + n + "." in t for n in ROMANS[:5]):
            raise ValueError("Missing Boethius book")
    elif sid == "adam-smith-wealth-of-nations":
        t = gutenberg(downloaded["wealth"])
        parts = numbered_sections(t, r"^BOOK [IVX]+\.\s*$", 5)
    elif sid == "summa-theologica":
        t = between(downloaded["summa"], r"^\s*FIRST PART \(FP:", r"^\s*Indexes\s*$")
        t = re.sub(r"\[\d+\]", "", t)
        parts = numbered_sections(
            t,
            r"^(?:[ ]*(?:FIRST PART \(FP:|FIRST PART OF THE SECOND PART|SECOND PART OF THE SECOND PART|THIRD PART \(TP\)|SUPPLEMENT \(XP\):)[^\n]*)$",
            5,
        )
    elif sid == "us-constitution":
        t = gutenberg(downloaded["constitution"])
        t = t[t.lower().index("we the people") :]
        parts = numbered_sections(
            t, r"^(?:Article 1|ARTICLE (?:2|THREE|FOUR|FIVE|SIX|SEVEN))\s*$", 7
        )
        for name in ["bill-of-rights", "amendments"]:
            t = html_body(downloaded[name], "#block-system-main")
            pattern = (
                r"^Amendment [IVX]+\s*$"
                if name == "bill-of-rights"
                else r"^AMENDMENT [IVX]+\s*$"
            )
            blocks = numbered_sections(
                t, pattern, 10 if name == "bill-of-rights" else 17
            )
            parts += [p for p in blocks if p[0] != "Introduction"]
    elif sid == "tacitus-annals-histories":
        parts = [
            ("Annals: " + label, t)
            for label, t in marker_sections(clean_raw(text), sid)
        ]
        t = gutenberg(downloaded["tacitus-histories"])
        parts += [
            ("Histories: " + label, t)
            for label, t in numbered_sections(t, r"^BOOK [IVX]+\s*$", 5)
        ]
    elif sid == "web-bible":
        # Full publisher export includes 66 canonical books and the ecumenical deuterocanon.
        matches = list(
            re.finditer(r"^\[([A-Z0-9]{3})(\d{2,3})?\]\s*$", text, re.MULTILINE)
        )
        parts = []
        chapters = collections.defaultdict(set)
        for i, m in enumerate(matches):
            code, num = m.group(1), m.group(2)
            if code in ["FRT", "GLO"] or not num:
                continue
            chapters[code].add(int(num))
            parts.append(
                (
                    code + " Chapter " + str(int(num)),
                    clean_raw(
                        text[
                            m.end() : matches[i + 1].start()
                            if i + 1 < len(matches)
                            else len(text)
                        ]
                    ),
                )
            )
        if len(chapters) != 81:
            raise ValueError("Missing WEB books " + str(len(chapters)))
        for code, ns in chapters.items():
            if ns != set(range(min(ns), max(ns) + 1)):
                raise ValueError("Missing chapter " + code)
            if ns - {0} != set(range(1, WEB_CHAPTER_COUNTS[code] + 1)):
                raise ValueError("Incomplete Bible book " + code)
    elif sid in {
        "didache",
        "justin-martyr-first-apology",
        "augsburg-confession",
        "heidelberg-catechism",
        "belgic-confession",
        "thirty-nine-articles",
    }:
        patterns = {
            "didache": (r"^Chapter \d+\.[^\n]+", 16),
            "justin-martyr-first-apology": (r"^Chapter \d+\.[^\n]+", 68),
            "augsburg-confession": (r"^Article [IVXLCDM]+:[^\n]+", 28),
            "heidelberg-catechism": (
                r"^\*?(?:Question 1.—|\d+\. |35 )[^\n]*\?[^\n]*",
                129,
            ),
            "belgic-confession": (r"^(?:Article )?[IVXLCDM]+\.[^\n]*", 37),
            "thirty-nine-articles": (r"^[IVXLCDM]+\. [^\n]+", 39),
        }
        pattern, count = patterns[sid]
        parts = numbered_sections(clean_raw(text), pattern, count)
    else:
        parts = marker_sections(clean_raw(text), sid)
    # Short title-only front matter belongs with the first readable section.
    if (
        len(parts) > 1
        and parts[0][0] == "Introduction"
        and len(parts[0][1].split()) < 30
    ):
        parts[1] = (parts[1][0], parts[0][1] + "\n\n" + parts[1][1])
        parts = parts[1:]
    if not provenance:
        provenance = [
            {
                "url": source.get("url") or source.get("local_path"),
                "sha256": hashlib.sha256(text.encode()).hexdigest(),
            }
        ]
    return parts, provenance


def tokens(s):
    return re.findall(r"[\w]+", s.casefold())


def passage_map(original, reader):
    # Find unchanged prose rather than reusing word-quota indices in complete documents.
    anchors = {}
    for p in reader:
        ts = tokens(p["text"])
        for i in range(len(ts) - 7):
            anchors.setdefault(tuple(ts[i : i + 8]), p["chunkIndex"])
    locations = {}
    for p in original:
        ts = tokens(p["text"])
        # Try prose away from page headers first, then the beginning and end.
        offsets = list(range(24, max(24, len(ts) - 7), 8)) + list(
            range(min(24, len(ts) - 7))
        )
        for i in offsets:
            found = anchors.get(tuple(ts[i : i + 8]))
            if found is not None:
                locations[str(p["chunkIndex"])] = found
                break
    return locations


def build_into(args):
    sources = yaml.safe_load((args.backend / "corpus/sources.yaml").read_text())[
        "sources"
    ]
    corpus = json.loads((ROOT / "Angrove-iOS/LocalGrounding/passages.json").read_text())
    groups = collections.defaultdict(list)
    for p in corpus:
        groups[p["sourceId"]].append(p)
    metadata = []
    audit = []
    args.output.mkdir(parents=True, exist_ok=True)
    for source in sources:
        sid = source["id"]
        if sid not in groups:
            continue
        if source["license_status"] != "confirmed_pd":
            raise ValueError("Unapproved edition " + sid)
        text = (
            (args.backend / "data/corpus/raw" / (sid + ".txt"))
            .read_text()
            .replace("\r\n", "\n")
        )
        parts, provenance = sections_for(source, text, args.cache)
        reader = []
        sections = []
        for i, (label, body) in enumerate(parts):
            ps = paragraphs(body)
            if sid == "web-bible":
                ps = [
                    p
                    for p in ps
                    if p not in {"<", ">"}
                    and not p.isdecimal()
                    and not p.startswith("World English Bible Classic ")
                ]
            elif sid == "westminster-confession":
                # The ratification prints numbered clauses on their own lines.
                ps = [
                    p + " " + ps[i + 1] if p.isdecimal() and i + 1 < len(ps) else p
                    for i, p in enumerate(ps)
                    if i == 0 or not ps[i - 1].isdecimal()
                ]
            if not ps:
                raise ValueError("Empty section " + sid + " " + label)
            lo = len(reader)
            for p in ps:
                reader.append(
                    {
                        "text": p,
                        "title": source["title"],
                        "sourceId": sid,
                        "chunkIndex": len(reader),
                    }
                )
            sections.append(
                {
                    "id": "section-" + str(i),
                    "title": label,
                    "lowerBound": lo,
                    "upperBound": len(reader) - 1,
                    "children": [],
                }
            )
        if sid == "web-bible":
            names = dict(
                re.findall(
                    r'\("([A-Z0-9]{3})(?:\d{2,3})", "([^"]+)"\)',
                    (
                        ROOT / "Angrove-iOS/Features/Library/LibraryView.swift"
                    ).read_text(),
                )
            )
            grouped = {}
            for section in sections:
                code, chapter = section["title"].split(" Chapter ")
                section["title"] = (
                    "Introduction" if chapter == "0" else "Chapter " + chapter
                )
                if code not in names:
                    raise ValueError("Unknown Bible book " + code)
                grouped.setdefault(code, []).append(section)
            order = [
                "GEN",
                "EXO",
                "LEV",
                "NUM",
                "DEU",
                "JOS",
                "JDG",
                "RUT",
                "1SA",
                "2SA",
                "1KI",
                "2KI",
                "1CH",
                "2CH",
                "EZR",
                "NEH",
                "EST",
                "JOB",
                "PSA",
                "PRO",
                "ECC",
                "SNG",
                "ISA",
                "JER",
                "LAM",
                "EZK",
                "DAN",
                "HOS",
                "JOL",
                "AMO",
                "OBA",
                "JON",
                "MIC",
                "NAM",
                "HAB",
                "ZEP",
                "HAG",
                "ZEC",
                "MAL",
                "MAT",
                "MRK",
                "LUK",
                "JHN",
                "ACT",
                "ROM",
                "1CO",
                "2CO",
                "GAL",
                "EPH",
                "PHP",
                "COL",
                "1TH",
                "2TH",
                "1TI",
                "2TI",
                "TIT",
                "PHM",
                "HEB",
                "JAS",
                "1PE",
                "2PE",
                "1JN",
                "2JN",
                "3JN",
                "JUD",
                "REV",
            ]
            # Reorder reader paragraphs too, retaining a contiguous range for each book.
            reordered = []
            book_sections = []
            for code in order + [c for c in grouped if c not in order]:
                children = grouped[code]
                book_lo = len(reordered)
                for child in children:
                    ps = reader[child["lowerBound"] : child["upperBound"] + 1]
                    child["lowerBound"] = len(reordered)
                    for paragraph in ps:
                        paragraph["chunkIndex"] = len(reordered)
                        reordered.append(paragraph)
                    child["upperBound"] = len(reordered) - 1
                book_sections.append(
                    {
                        "id": "book-" + code,
                        "title": names[code],
                        "lowerBound": book_lo,
                        "upperBound": len(reordered) - 1,
                        "children": children,
                    }
                )
            reader = reordered
            sections = book_sections
        locations = passage_map(groups[sid], reader)
        filename = "library-" + sid + ".json"
        data = json.dumps(reader, ensure_ascii=False, separators=(",", ":")).encode()
        (args.output / filename).write_bytes(data)
        context = "Complete text of the bundled edition."
        if sid in ["tacitus-annals-histories", "livy-history-of-rome"]:
            context = "Complete surviving text; ancient lost books cannot be restored."
        if sid == "tacitus-annals-histories":
            context += (
                " Annals: Church and Brodribb; Histories: W. Hamilton Fyfe (1912)."
            )
        if sid == "westminster-confession":
            context += " Scottish Parliament’s 1690 ratification of the confession, all 33 chapters."
        if sid == "ecumenical-creeds-schaff":
            context = "Complete Oecumenical Symbols section of Schaff’s Creeds of Christendom II."
        entry = {
            "id": sid,
            "title": source["title"],
            "context": context,
            "filename": filename,
            "paragraphCount": len(reader),
            "sections": sections,
            "retrievalLocations": locations,
            "sha256": hashlib.sha256(data).hexdigest(),
        }
        metadata.append(entry)
        audit.append(
            {
                "id": sid,
                "sections": [s["title"] for s in sections],
                "words": sum(len(p["text"].split()) for p in reader),
                "paragraphs": len(reader),
                "retrievalLocations": len(locations),
                "retrievalPassages": len(groups[sid]),
                "sources": provenance,
                "sha256": entry["sha256"],
                "structuralChecks": "Passed expected book/chapter boundaries; all source paragraphs retained",
            }
        )
        print(
            sid,
            len(sections),
            "sections",
            len(reader),
            "paragraphs",
            len(locations),
            "mapped",
            flush=True,
        )
    if {m["id"] for m in metadata} != set(groups):
        raise ValueError("Missing catalog works")
    (args.output / "library-index.json").write_text(
        json.dumps(
            {"schemaVersion": 1, "documents": metadata},
            ensure_ascii=False,
            separators=(",", ":"),
        )
    )
    args.audit.write_text(
        json.dumps(
            {"schemaVersion": 1, "documents": audit}, ensure_ascii=False, indent=2
        )
    )


def build(args):
    # Failed chapter checks leave the previous complete bundle intact.
    with tempfile.TemporaryDirectory(prefix="aquinas-library-") as temporary:
        staged = copy.copy(args)
        staged.output = Path(temporary) / "documents"
        staged.audit = Path(temporary) / "audit.json"
        build_into(staged)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        backup = Path(temporary) / "previous"
        if args.output.exists():
            shutil.move(str(args.output), backup)
        try:
            shutil.move(str(staged.output), args.output)
        except Exception:
            if backup.exists():
                shutil.move(str(backup), args.output)
            raise
        args.audit.parent.mkdir(parents=True, exist_ok=True)
        args.audit.write_bytes(staged.audit.read_bytes())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", type=Path, required=True)
    parser.add_argument(
        "--cache", type=Path, default=ROOT / "output/library-source-cache"
    )
    parser.add_argument(
        "--output", type=Path, default=ROOT / "Angrove-iOS/LibraryDocuments"
    )
    parser.add_argument(
        "--audit",
        type=Path,
        default=ROOT / "Documentation/Library-Completeness-Audit.json",
    )
    build(parser.parse_args())
