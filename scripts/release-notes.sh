#!/bin/zsh
# Prints the CHANGELOG.md section for a version ("## 0.1.0 …" up to the next "## ").
# Usage: scripts/release-notes.sh <version> [--html]
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "$1" "${2:-}" <<'PY'
import html, re, sys
version, fmt = sys.argv[1], sys.argv[2]
text = open("CHANGELOG.md", encoding="utf-8").read()
match = re.search(rf"^## {re.escape(version)}\b.*?$(.*?)(?=^## |\Z)", text, re.M | re.S)
if not match:
    sys.exit(f"CHANGELOG.md has no '## {version}' section. Add release notes before releasing.")
body = match.group(1).strip()
if fmt != "--html":
    print(body)
    sys.exit()
def inline(text):
    """Escapes the text, then turns the Markdown the changelog uses into HTML: `code`, **bold**, *italic*, [links](url)."""
    codes = []
    def keep(m):
        codes.append(f"<code>{html.escape(m.group(1))}</code>")
        return f"\x00{len(codes) - 1}\x00"
    text = html.escape(re.sub(r"`([^`]+)`", keep, text), quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", text)
    text = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>', text)
    return re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)

out, in_list = [], False
for line in body.splitlines():
    if line.startswith("- "):
        if not in_list:
            out.append("<ul>"); in_list = True
        out.append(f"<li>{inline(line[2:])}</li>")
    else:
        if in_list:
            out.append("</ul>"); in_list = False
        if line.strip():
            out.append(f"<p>{inline(line)}</p>")
if in_list:
    out.append("</ul>")
print("\n".join(out))
PY
