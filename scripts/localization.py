#!/usr/bin/env python3
"""Keeps the app's translations in step with the code.

  scripts/localization.py extract   Writes Resources/Localizations/en.lproj/Localizable.strings from the Swift sources.
  scripts/localization.py check     Checks every language against English: missing keys, extra keys and format
                                    specifiers (%@, %lld) that don't match. Exits 1 on an error.
  scripts/localization.py missing <lang>
                                    Prints the English entries <lang> doesn't have yet, ready to translate.
  scripts/localization.py rtl       Adds the direction marks right-to-left languages need (see RTL_LANGUAGES), in place.
                                    check reports any that are missing.

A string is translatable when it reaches SwiftUI as a literal (Text("…"), Button("…"), .help("…") and the like) or is
wrapped in String(localized: "…") or NSLocalizedString("…", comment: …). Interpolated values become %@ (String) or %lld
(Int); INT_INTERPOLATIONS lists the expressions that are Ints or Doubles.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "Takes"
LOCALIZATIONS = ROOT / "Resources" / "Localizations"
TABLE = "Localizable.strings"

# Debug tools and sample data: their text is never translated.
SKIP = re.compile(r"^(Snapshot.*|Bench|ToneBench|RunLog|AXProbe|main)\.swift$")

# SwiftUI initializers and modifiers whose first argument, given as a literal, is a LocalizedStringKey.
SWIFTUI_CALLS = {"Text", "Button", "Toggle", "Label", "Picker", "TextField", "SecureField", "Link", "Menu", "Section",
                 "LocalizedStringKey", "ProgressView", "LabeledContent", "ContentUnavailableView"}
SWIFTUI_MODIFIERS = {"help", "accessibilityLabel", "accessibilityHint", "accessibilityValue", "navigationTitle",
                     "alert", "confirmationDialog", "accessibilityAction"}

# The app's own helpers whose first parameter is a LocalizedStringKey, by file.
LOCAL_KEY_CALLS: dict[str, set[str]] = {
    "EnglishCoachViews.swift": {"tile", "caption", "column", "group"},
}

# Interpolated expressions that aren't Strings, by file: "File.swift:expression" -> specifier. An Int is %lld; an Int32
# is %d (Swift writes them differently, and a translation has to match the one the code produces).
INT_INTERPOLATIONS: dict[str, str] = {
    "APIEngine.swift:status": "%lld",
    "AppDelegate.swift:lessonsReady": "%lld",
    "ClaudeCodeEngine.swift:minutes": "%lld",
    "ClaudeCodeEngine.swift:status": "%d",
    "Diff.swift:fixes.count": "%lld",
    "Engine.swift:$0": "%lld",
    "Engine.swift:attempt": "%lld",
    "Engine.swift:seconds": "%lld",
    "Engine.swift:minutes": "%lld",
    "EnglishCoachViews.swift:n": "%lld",
    "EnglishCoachViews.swift:offer.found.count": "%lld",
    "EnglishCoachViews.swift:offer.drafts": "%lld",
    "EnglishCoachViews.swift:step": "%lld",
    "EnglishCoachViews.swift:CoachGuide.patterns.count": "%lld",
    "EnglishCoachViews.swift:counted.count": "%lld",
    "EnglishCoachViews.swift:store.presets.count": "%lld",
    "EnglishCoachViews.swift:coach.checks()": "%lld",
    "EnglishCoachViews.swift:drafts": "%lld",
    "EnglishCoachViews.swift:CoachStore.lessonAt - stat.count": "%lld",
    "EnglishCoachViews.swift:CoachStore.lessonAt": "%lld",
    "EnglishCoachViews.swift:since.drafts": "%lld",
    "EnglishCoachViews.swift:since.slips": "%lld",
    "HistoryTab.swift:index + 1": "%lld",
    "LocalEngine.swift:takes": "%lld",
    "LocalEngine.swift:takeCount": "%lld",
    "LocalEngineViews.swift:models.count": "%lld",
    "OnboardingView.swift:number": "%lld",
    "OnboardingView.swift:numbered.count": "%lld",
    "OnboardingView.swift:numbered.index": "%lld",
    "PanelController.swift:number": "%lld",
    "PanelController.swift:index + 1": "%lld",
    "PanelViews.swift:layout.overflow": "%lld",
    "PanelViews.swift:model.takeCount": "%lld",
    "PanelViews.swift:model.wordCount": "%lld",
    "PanelViews.swift:rules": "%lld",
    "PanelViews.swift:examples": "%lld",
    "PanelViews.swift:model.selected + 1": "%lld",
    "PanelViews.swift:index + 1": "%lld",
    "PanelViews.swift:number": "%lld",
    "PanelViews.swift:count": "%lld",
    "PresetGallery.swift:items.count": "%lld",
    "PresetGalleryView.swift:items.count": "%lld",
    "PresetGalleryView.swift:missing.count - 6": "%lld",
    "PresetsTab.swift:index + 1": "%lld",
    "PresetsTab.swift:examples.count": "%lld",
    "PresetsTab.swift:Preset.maxExamples": "%lld",
    "PresetsTab.swift:changes.count - shown": "%lld",
    "PresetsTab.swift:imported": "%lld",
    "PresetsTab.swift:maxPresets": "%lld",
    "PresetsTab.swift:PresetImport.maxPresets": "%lld",
    "PresetsTab.swift:preset.takes": "%lld",
    "PresetsTab.swift:result.skipped": "%lld",
    "PresetsTab.swift:takes": "%lld",
    "PresetsTab.swift:total": "%lld",
    "Proofread.swift:count": "%lld",
    "ProviderEngine.swift:status": "%lld",
    "ReplyContext.swift:words": "%lld",
    "Setup.swift:missing.count": "%lld",
    "Setup.swift:number": "%lld",
    "StepComponents.swift:number": "%lld",
    "Store.swift:takes": "%lld",
    "Theme.swift:number": "%lld",
}


class Literal:
    def __init__(self, file, line, parts, start, end):
        self.file, self.line, self.parts, self.start, self.end = file, line, parts, start, end
        # parts: list of ("text", str) or ("expr", str)

    @property
    def has_interpolation(self):
        return any(kind == "expr" for kind, _ in self.parts)

    def key(self):
        out = []
        for kind, value in self.parts:
            if kind == "text":
                out.append(value.replace("%", "%%") if self.has_interpolation else value)
            else:
                out.append(INT_INTERPOLATIONS.get(f"{self.file}:{value.strip()}", "%@"))
        return "".join(out)


ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}


def parse_literal(src, i, file, line):
    """Parses the string literal starting at src[i] (a quote or #). Returns (Literal, index after it)."""
    start = i
    hashes = 0
    while src[i] == "#":
        hashes += 1
        i += 1
    multiline = src.startswith('"""', i)
    i += 3 if multiline else 1
    if multiline and src[i] == "\n":
        i += 1
    close = ('"""' if multiline else '"') + "#" * hashes
    escape = "\\" + "#" * hashes
    parts, text = [], []
    while True:
        if src.startswith(close, i):
            i += len(close)
            break
        if src.startswith(escape, i):
            j = i + len(escape)
            c = src[j]
            if c == "(":
                # Interpolation: find the matching paren, skipping nested strings.
                depth, k = 1, j + 1
                while depth:
                    ch = src[k]
                    if ch == '"' or (ch == "#" and src[k + 1] in '#"'):
                        _, k = parse_literal(src, k, file, line)
                        continue
                    depth += {"(": 1, ")": -1}.get(ch, 0)
                    k += 1
                if text:
                    parts.append(("text", "".join(text)))
                    text = []
                parts.append(("expr", src[j + 1:k - 1]))
                i = k
                continue
            if c == "u":
                end = src.index("}", j)
                text.append(chr(int(src[j + 2:end], 16)))
                i = end + 1
                continue
            if c == "\n" and multiline:
                i = j + 1
                continue
            text.append(ESCAPES.get(c, c))
            i = j + 1
            continue
        text.append(src[i])
        i += 1
    if text:
        parts.append(("text", "".join(text)))
    if multiline:
        # Strip the closing delimiter's indentation from every line.
        body = "".join(v if k == "text" else "\0" for k, v in parts)
        indent = re.search(r"\n([ \t]*)$", body)
        if indent:
            pad = indent.group(1)
            new_parts = []
            for k, v in parts:
                if k == "text":
                    v = v.replace("\n" + pad, "\n")
                    if v.startswith(pad) and not new_parts:
                        v = v[len(pad):]
                new_parts.append((k, v))
            parts = new_parts
            last = parts[-1]
            if last[0] == "text" and last[1].endswith("\n"):
                parts[-1] = ("text", last[1][:-1])
    return Literal(file, line, parts, start, i), i


class Frame:
    def __init__(self, name, dotted):
        self.name, self.dotted, self.commas, self.label = name, dotted, 0, None


def scan(path):
    """Yields (Literal, comment) for every translatable literal in one Swift file."""
    src = path.read_text()
    file = path.name
    i, line, stack = 0, 1, []
    n = len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
        elif src.startswith("/*", i):
            end = src.find("*/", i)
            line += src.count("\n", i, end)
            i = end + 2
        elif c == '"' or (c == "#" and i + 1 < n and src[i + 1] in '#"'):
            literal, j = parse_literal(src, i, file, line)
            line += src.count("\n", i, j)
            frame = stack[-1] if stack else None
            before = src[:i].rstrip()
            after = src[j:].lstrip()
            label = re.search(r"(\w+)\s*:\s*$", before)
            if frame is not None:
                yield from classify(literal, frame, before, after, label.group(1) if label else None, src, stack)
            i = j
        elif c == "(":
            m = re.search(r"(\.?)(\w+)\s*$", src[max(0, i - 80):i])
            stack.append(Frame(m.group(2) if m else "", bool(m and m.group(1))))
            i += 1
        elif c == ")":
            if stack:
                stack.pop()
            i += 1
        elif c == "[" or c == "{":
            stack.append(Frame(c, False))
            i += 1
        elif c == "]" or c == "}":
            if stack:
                stack.pop()
            i += 1
        elif c == ",":
            if stack:
                stack[-1].commas += 1
            i += 1
        else:
            i += 1


def classify(literal, frame, before, after, label, src, stack):
    if frame.name == "String" and label == "localized" and frame.commas == 0:
        comment = re.match(r',\s*comment:\s*"((?:[^"\\]|\\.)*)"', after)
        yield literal, comment.group(1) if comment else None
    elif frame.name == "NSLocalizedString" and frame.commas == 0:
        comment = re.match(r',\s*comment:\s*"((?:[^"\\]|\\.)*)"', after)
        yield literal, (comment.group(1) or None) if comment else None
    elif frame.commas == 0 and label is None and (
            (not frame.dotted and frame.name in SWIFTUI_CALLS) or (frame.dotted and frame.name in SWIFTUI_MODIFIERS)
            or (not frame.dotted and frame.name in LOCAL_KEY_CALLS.get(literal.file, set()))):
        # The literal itself, or a branch of a ternary between literals. Not "a" + b, x ?? "a", or f("a").
        if before.endswith(("+", "??")) or after.startswith(("+", "??", ".")):
            return
        if before.endswith("(") or before.endswith("?") or (before.endswith(":") and "?" in before[-200:]):
            yield literal, None


def strings_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def extract():
    entries: dict[str, dict] = {}
    for path in sorted(SOURCES.glob("*.swift")):
        if SKIP.match(path.name):
            continue
        for literal, comment in scan(path):
            key = literal.key()
            if not key.strip() or not re.search(r"[A-Za-z]", key):
                continue
            entry = entries.setdefault(key, {"where": [], "comment": None})
            entry["where"].append(f"{literal.file}:{literal.line}")
            entry["comment"] = entry["comment"] or comment
    lines = ["/* English source strings. Generated by scripts/localization.py extract; don't edit by hand. */", ""]
    for key in sorted(entries, key=lambda k: k.lower()):
        entry = entries[key]
        note = entry["comment"] + " · " if entry["comment"] else ""
        lines.append(f"/* {note}{', '.join(sorted(set(entry['where'])))} */")
        lines.append(f'"{strings_escape(key)}" = "{strings_escape(key)}";')
        lines.append("")
    out = LOCALIZATIONS / "en.lproj" / TABLE
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines))
    print(f"{len(entries)} strings → {out.relative_to(ROOT)}")


def parse_strings(path):
    """Parses a .strings file (UTF-8). Returns {key: value}; raises ValueError on a syntax error."""
    src = path.read_text(encoding="utf-8")
    result, i, n = {}, 0, len(src)

    def skip(i):
        while i < n:
            if src[i].isspace():
                i += 1
            elif src.startswith("/*", i):
                end = src.find("*/", i)
                if end < 0:
                    raise ValueError("unclosed comment")
                i = end + 2
            elif src.startswith("//", i):
                end = src.find("\n", i)
                i = n if end < 0 else end
            else:
                break
        return i

    def string(i):
        if src[i] != '"':
            raise ValueError(f"expected a quote at line {src.count(chr(10), 0, i) + 1}")
        i += 1
        out = []
        while src[i] != '"':
            if src[i] == "\\":
                c = src[i + 1]
                if c == "U" or c == "u":
                    out.append(chr(int(src[i + 2:i + 6], 16)))
                    i += 6
                    continue
                out.append({"n": "\n", "t": "\t", "r": "\r"}.get(c, c))
                i += 2
            else:
                out.append(src[i])
                i += 1
        return "".join(out), i + 1

    i = skip(i)
    while i < n:
        key, i = string(i)
        i = skip(i)
        if src[i] != "=":
            raise ValueError(f"expected = after {key!r}")
        value, i = string(skip(i + 1))
        i = skip(i)
        if src[i] != ";":
            raise ValueError(f"expected ; after {key!r}")
        if key in result:
            raise ValueError(f"duplicate key {key!r}")
        result[key] = value
        i = skip(i + 1)
    return result


SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+0#]*\d*(?:\.\d+)?(ll|l|h|hh|q|z|t|j)?([@dDuUxXoOfFeEgGcCsSaAp%])")


def specifiers(s):
    """The format specifiers in s by position, as {position: type}. %% doesn't count."""
    found, position = {}, 0
    for m in SPECIFIER.finditer(s):
        if m.group(3) == "%":
            continue
        position += 1
        index = int(m.group(1)) if m.group(1) else position
        found[index] = (m.group(2) or "") + m.group(3)
    return found


# Right-to-left languages. A sentence that starts with a Latin word ("Takes", "Claude"), a number or a placeholder would
# otherwise be laid out left to right, scrambling its line order and punctuation, so it starts with a right-to-left
# mark. A shortcut written in a sentence ("⌘Z") is isolated left to right, or it shows as "Z⌘".
RTL_LANGUAGES = {"ar", "fa", "he", "ur"}
RLM, LRI, PDI = "\u200f", "\u2066", "\u2069"
SHORTCUT = re.compile(r"(?<![\u2066⌃⌥⇧⌘])[⌃⌥⇧⌘]+(?:Space|Return|Tab|Esc|Delete|F\d{1,2}|[A-Za-z0-9,./;'=\[\]\\`←→↑↓⇥↩⌫])?")


def is_rtl_letter(c):
    return "\u0590" <= c <= "\u08ff" or "\ufb1d" <= c <= "\ufdff" or "\ufe70" <= c <= "\ufeff"


def rtl_fixed(value):
    """value with the marks a right-to-left language needs."""
    # Text with no right-to-left letters ("claude auth login", "esc") stays as it is: a command may be copied.
    if not any(is_rtl_letter(c) for c in value):
        return value.replace(RLM, "").replace(LRI, "").replace(PDI, "")
    value = SHORTCUT.sub(lambda m: LRI + m.group(0) + PDI, value)
    # Fragments joined to other strings (" · %@") take their direction from the whole line.
    if value and not value[0].isspace() and value[0] not in (RLM, LRI) and not is_rtl_letter(value[0]):
        value = RLM + value
    return value


def rtl():
    entry = re.compile(r'^("(?:[^"\\]|\\.)*"\s*=\s*")((?:[^"\\]|\\.)*)(";)', re.M)
    for lang in sorted(RTL_LANGUAGES):
        path = LOCALIZATIONS / f"{lang}.lproj" / TABLE
        src = path.read_text(encoding="utf-8")
        fixed, count = [], 0

        def fix(m):
            nonlocal count
            value = rtl_fixed(m.group(2))
            count += value != m.group(2)
            return m.group(1) + value + m.group(3)

        path.write_text(entry.sub(fix, src), encoding="utf-8")
        print(f"{lang}: {count} strings marked")


def check():
    english = parse_strings(LOCALIZATIONS / "en.lproj" / TABLE)
    errors = 0
    for folder in sorted(LOCALIZATIONS.glob("*.lproj")):
        if folder.name == "en.lproj":
            continue
        lang = folder.stem
        try:
            table = parse_strings(folder / TABLE)
        except (ValueError, IndexError, FileNotFoundError) as e:
            print(f"{lang}: {e}")
            errors += 1
            continue
        missing = [k for k in english if k not in table]
        extra = [k for k in table if k not in english]
        bad = [k for k, v in table.items() if k in english and specifiers(k) != specifiers(v)]
        for k in bad:
            print(f"{lang}: specifiers differ: {k!r} → {table[k]!r}")
        # Strings joined to others keep their leading and trailing spaces.
        spacing = [k for k, v in table.items() if k in english and v.strip()
                   and ((k[:1] == " ") != (v[:1] == " ") or (k[-1:] == " ") != (v[-1:] == " "))]
        for k in spacing:
            print(f"{lang}: spaces at the ends differ: {k!r} → {table[k]!r}")
        marks = [k for k, v in table.items() if lang in RTL_LANGUAGES and v != rtl_fixed(v)]
        for k in marks:
            print(f"{lang}: needs direction marks (run scripts/localization.py rtl): {k!r}")
        errors += len(bad) + len(spacing) + len(marks)
        status = f"{len(table) - len(extra)}/{len(english)}"
        if missing:
            status += f", {len(missing)} missing"
        if extra:
            status += f", {len(extra)} no longer used"
        print(f"{lang}: {status}")
    sys.exit(1 if errors else 0)


def missing(lang):
    english = parse_strings(LOCALIZATIONS / "en.lproj" / TABLE)
    path = LOCALIZATIONS / f"{lang}.lproj" / TABLE
    table = parse_strings(path) if path.exists() else {}
    for key in english:
        if key not in table:
            print(f'"{strings_escape(key)}" = "{strings_escape(key)}";')


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "extract":
        extract()
    elif command == "check":
        check()
    elif command == "rtl":
        rtl()
    elif command == "missing" and len(sys.argv) > 2:
        missing(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(2)
