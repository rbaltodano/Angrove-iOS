#!/usr/bin/env python3
"""Flag raw visual values in feature code that bypass the AngroveTheme design tokens.

Design-system folders (`*/DesignSystem/`) define the tokens and are not checked. A line that
truly needs a raw value can end with `// design-tokens: allow <reason>`.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = ("Shared", "iOS", "macOS")
ALLOW = "design-tokens: allow"

SYSTEM_COLORS = r"(?:white|black|blue|red|green|gray|grey|orange|yellow|purple|pink|cyan|indigo|mint|teal|brown)"
TEXT_STYLES = r"(?:largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)"
STYLE_CALLS = {"foregroundStyle", "foregroundColor", "fill", "stroke", "strokeBorder", "tint", "background", "shadow"}

# Patterns run on whole files with comments and string contents blanked, so `\s*` spans line breaks.
RULES = (
    (
        "raw-color",
        re.compile(
            r"\b(?:Color|UIColor)\s*\(\s*(?:hex|light|red|white)\s*:"
            r"|\bNSColor\s*\(\s*(?:srgbRed|red|calibratedRed|white)\s*:"
        ),
        "use an AngroveTheme.Colors token",
    ),
    (
        "system-color",
        re.compile(rf"\bColor\s*\.\s*{SYSTEM_COLORS}\b|(?<![\w.\s])\s*(\.{SYSTEM_COLORS}\b)(?!\s*[:=(])"),
        "use an AngroveTheme.Colors token, not a system color",
    ),
    (
        "raw-spring",
        re.compile(r"\.\s*(?:spring|interactiveSpring)\s*\("),
        "use a named spring from DesignSystem/Motion.swift",
    ),
    (
        "system-text-style",
        re.compile(rf"\.font\s*\(\s*(?:Font)?\s*\.\s*{TEXT_STYLES}\b"),
        "use an AngroveTheme.Typography token",
    ),
    (
        "system-font",
        re.compile(r"\.font\s*\(\s*(?:Font)?\s*\.\s*system\s*\(|\bFont\s*\.\s*system\s*\("),
        "use .angroveIcon(...) for SF Symbols or an AngroveTheme.Typography token for text",
    ),
    (
        "corner-style",
        re.compile(r"\bRoundedRectangle\s*\(\s*cornerRadius\s*:|\.\s*cornerRadius\s*\("),
        "use RoundedRectangle(cornerRadius:style: .continuous)",
    ),
)


def code_only(text):
    """Blanks comments (including nested block comments) and string literal contents
    (including multiline and raw strings), keeping newlines so offsets map to lines."""
    out = list(text)
    index, length = 0, len(text)

    def blank(start, stop):
        for position in range(start, stop):
            if out[position] != "\n":
                out[position] = " "

    while index < length:
        if text.startswith("//", index):
            stop = text.find("\n", index)
            stop = length if stop == -1 else stop
            blank(index, stop)
            index = stop
        elif text.startswith("/*", index):
            depth, position = 1, index + 2
            while position < length and depth:
                if text.startswith("/*", position):
                    depth, position = depth + 1, position + 2
                elif text.startswith("*/", position):
                    depth, position = depth - 1, position + 2
                else:
                    position += 1
            blank(index, position)
            index = position
        elif text[index] == '"' or (text[index] == "#" and re.match(r'#+"', text[index:])):
            hashes = len(re.match(r"#*", text[index:]).group(0))
            quote_start = index + hashes
            delimiter = '"""' if text.startswith('"""', quote_start) else '"'
            body = quote_start + len(delimiter)
            closing = delimiter + "#" * hashes
            position = body
            while position < length:
                if hashes == 0 and text[position] == "\\":
                    position += 2
                    continue
                if text.startswith(closing, position):
                    break
                if delimiter == '"' and text[position] == "\n":
                    break
                position += 1
            blank(body, position)
            index = min(length, position + len(closing))
        else:
            index += 1
    return "".join(out)


def enclosing_call(code, position):
    """Returns (callee name, opening index) of the innermost parenthesised call around
    `position`, stepping out of array literals, or (None, -1)."""
    depth = 0
    for index in range(position - 1, -1, -1):
        char = code[index]
        if char in ")]":
            depth += 1
        elif char in "([":
            if depth:
                depth -= 1
            elif char == "(":
                name = re.search(r"(\w+)\s*$", code[:index])
                return (name.group(1) if name else None), index
    return None, -1


def top_level_labels(arguments):
    """Yields (label, value) for a call's top-level `label: value` arguments."""
    depth, start, parts = 0, 0, []
    for index, char in enumerate(arguments):
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(arguments[start:index])
            start = index + 1
    parts.append(arguments[start:])
    for part in parts:
        match = re.match(r"\s*(\w+)\s*:(.*)", part, re.S)
        if match:
            yield match.group(1), match.group(2).strip()


def call_arguments(code, open_paren):
    """Returns the text between a call's balanced parentheses."""
    depth = 0
    for index in range(open_paren, len(code)):
        if code[index] == "(":
            depth += 1
        elif code[index] == ")":
            depth -= 1
            if depth == 0:
                return code[open_paren + 1:index]
    return code[open_paren + 1:]


def is_style_color(code, position):
    """A bare `.red` counts as a color only as an argument of a styling call or a `color:` label."""
    callee, open_paren = enclosing_call(code, position)
    if open_paren < 0:
        return False
    if callee in STYLE_CALLS:
        return True
    # The label of the top-level argument holding the color; ternary colons sit mid-argument.
    depth, argument_start = 0, open_paren + 1
    for index in range(open_paren + 1, position):
        char = code[index]
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            argument_start = index + 1
    label = re.match(r"\s*(\w+)\s*:(?!:)", code[argument_start:position])
    return bool(label) and label.group(1) in ("color", "colors")


def violations(path, text):
    lines = text.splitlines()
    code = code_only(text)
    line_starts = [0]
    for line in text.split("\n"):
        line_starts.append(line_starts[-1] + len(line) + 1)
    found = {}
    for name, pattern, advice in RULES:
        for match in pattern.finditer(code):
            position = match.start()
            if name == "system-color" and match.group(1):
                position = match.start(1)
                if not is_style_color(code, position):
                    continue
            if name == "corner-style" and "RoundedRectangle" in match.group(0):
                arguments = call_arguments(code, code.index("(", match.start()))
                if dict(top_level_labels(arguments)).get("style") == ".continuous":
                    continue
            number = next(i for i, start in enumerate(line_starts) if start > position)
            if ALLOW in lines[number - 1]:
                continue
            found.setdefault((number, name), f"{path}:{number}: {name}: {advice}\n    {lines[number - 1].strip()}")
    return [found[key] for key in sorted(found)]


def source_files(root):
    for directory in SOURCE_DIRS:
        for path in sorted((root / directory).rglob("*.swift")):
            if "DesignSystem" not in path.relative_to(root).parts:
                yield path


def main(root=ROOT):
    failures = []
    files = list(source_files(root))
    for path in files:
        failures.extend(violations(path.relative_to(root), path.read_text()))
    if failures:
        print("\n".join(failures), file=sys.stderr)
        print(f"{len(failures)} design-token violations.", file=sys.stderr)
        return 1
    print(f"Checked {len(files)} Swift files: no design-token violations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
