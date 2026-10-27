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
out, in_list = [], False
for line in body.splitlines():
    if line.startswith("- "):
        if not in_list:
            out.append("<ul>"); in_list = True
        out.append(f"<li>{html.escape(line[2:])}</li>")
    else:
        if in_list:
            out.append("</ul>"); in_list = False
        if line.strip():
            out.append(f"<p>{html.escape(line)}</p>")
if in_list:
    out.append("</ul>")
print("\n".join(out))
PY
