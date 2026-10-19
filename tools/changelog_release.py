#!/usr/bin/env python3
"""Writes a published final release into CHANGELOG.md (docs/publishing/README.md, "Cutting a release").

usage: changelog_release.py <tag> <body-file> [CHANGELOG.md]

Run by publish.yml on `forever` after the CurseForge upload. Inserts "## <tag>" (a "_Released YYYY-MM-DD_" line, then
the published release body verbatim) directly below "## Unreleased" and resets Unreleased to the five empty headings.
Lines added to Unreleased after the tag (not in `git show <tag>:CHANGELOG.md`'s Unreleased) stay where they are.
Idempotent: a changelog that already has "## <tag>" is left alone. Python 3 standard library only.
"""

import datetime
import re
import subprocess
import sys

HEADINGS = ["New", "Changed", "Fixed", "Known issues", "Upgrade notes"]


def fail(msg):
    print("changelog_release: " + msg, file=sys.stderr)
    raise SystemExit(2)


def unreleased(text):
    """(start, end, body) of the "## Unreleased" section: its heading line through the next "## " heading."""
    m = re.search(r"^## Unreleased[ \t]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        fail("no ## Unreleased section")
    return m.start(), m.end(), m.group(1)


def entries(body):
    """{heading: [line, ...]} of the non-blank lines under each "### " heading (None: before the first)."""
    out, cur = {}, None
    for line in body.split("\n"):
        h = re.match(r"^### (.*?)\s*$", line)
        if h:
            cur = h.group(1)
        elif line.strip():
            out.setdefault(cur, []).append(line)
    return out


def released_already(text, tag):
    return re.search(r"^## " + re.escape(tag) + r"[ \t]*$", text, re.M) is not None


def rewrite(text, tag, body, released_unreleased, date):
    if "-" in tag:
        fail("%s is a pre-release; its notes stay in Unreleased" % tag)
    body = body.replace("\r\n", "\n").strip()  # a body edited on github.com comes back with CRLF
    if not body:
        fail("the release body is empty")
    if re.search(r"^#{1,2} ", body, re.M):
        fail("the release body has a # or ## heading; it would split the changelog")
    if released_already(text, tag):
        return text
    start, end, current = unreleased(text)
    shipped = {line for lines in entries(released_unreleased).values() for line in lines}
    kept = {h: [line for line in lines if line not in shipped] for h, lines in entries(current).items()}
    parts = ["## Unreleased\n\n"] + ["%s\n" % line for line in kept.get(None, [])]
    for h in HEADINGS:
        parts.append("### %s\n" % h + "".join("%s\n" % line for line in kept.get(h, [])) + "\n")
    parts.append("## %s\n\n_Released %s_\n\n%s\n\n" % (tag, date, body))
    return text[:start] + "".join(parts) + text[end:].lstrip("\n")


def main(argv, run=subprocess.run):
    if len(argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    tag, body_path = argv[1], argv[2]
    path = argv[3] if len(argv) == 4 else "CHANGELOG.md"
    with open(body_path) as f:
        body = f.read()
    with open(path) as f:
        text = f.read()
    if released_already(text, tag):
        return 0
    if "-" not in tag and body.strip():
        got = run(["git", "show", tag + ":CHANGELOG.md"], capture_output=True, text=True)
        if got.returncode != 0:  # without it, lines merged after the tag would be wiped with the released ones
            fail("cannot read %s:CHANGELOG.md (fetch the tag first): %s" % (tag, got.stderr.strip()))
        released = unreleased(got.stdout)[2]
    else:
        released = ""  # rewrite() refuses these
    new = rewrite(text, tag, body, released, datetime.date.today().isoformat())
    with open(path, "w") as f:
        f.write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
