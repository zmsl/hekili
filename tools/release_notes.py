#!/usr/bin/env python3
"""Drafts the player-facing release notes for a tag (docs/publishing/README.md, "Cutting a release").

Gathers the change material between the previous release tag and <ref> (commits touching src/, the CHANGELOG.md
"Unreleased" section, or the tag's own section when Unreleased has no entries, and the "Open after" sections of plans
changed since the previous tag), asks the Anthropic Messages API to write the notes in the house style, and writes them
to <out>.

usage: release_notes.py <ref> <out.md>       (ANTHROPIC_API_KEY in the environment)
       release_notes.py --material <ref>     (print the request's user message; no network)
Python 3 standard library only. Never prints the request headers or the key.
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API_URL = "https://api.anthropic.com/v1/messages"
MODEL = "claude-opus-5-5"
PLANS = "docs/superpowers/plans"

SYSTEM = """\
You write the release notes players read for Hekili Forever, a World of Warcraft addon for the WoW Forever client \
that shows the next abilities to press. Players read the notes on CurseForge, GitHub and Discord.

The material is written by and for developers: changelog lines, commit messages and open-issue lists that name files, \
functions, tasks, test worlds, checkpoints and internal ids. Write only what a player would notice in game. Leave out \
anything a player cannot see (tests, tooling, refactors, documentation, internal models with no visible effect). Never \
write file, function or variable names, task, day, checkpoint or plan numbers, spell or spec ids, commit hashes, or \
internal terms such as belief, facade, harness, gate, oracle, family, hand, content API or pack API. Say each change \
in player terms: the class and specialization, the ability, and the situation where the recommendation or display \
now differs.

Format, GitHub markdown, under 60 lines in all:
- No title. Start with one sentence that sums up the release.
- One "### <Class>" section per class with changes, classes in alphabetical order, then "### Core and display" for \
changes every class sees. One bullet per change, one line each. Leave out empty sections.
- "### Known issues": the open issues a player could run into, one line each, written as what the player sees; leave \
out items that are only test gaps or developer to-dos. Leave the section out when there are none.
- "### Upgrade notes" only when the changelog's Upgrade notes say settings, profiles or saved priorities change; \
otherwise leave it out.
Do not invent changes. When the material does not make a change's effect on players clear, leave it out. Output only \
the notes."""


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def previous_tag(ref, run=git):
    """The newest non-prerelease v* tag before ref (so a final's notes span its release candidates), or None."""
    try:
        return run("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", "--exclude", "*-*", ref + "^").strip()
    except subprocess.CalledProcessError:
        return None


def section(text, heading):
    """The body under "## <heading>" up to the next "## ", stripped; "" when absent."""
    m = re.search(r"^## " + re.escape(heading) + r"[ \t]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1).strip() if m else ""


def open_after(text):
    """Every "## Open after ..." section of a plan, heading included, joined by blank lines."""
    text = re.sub(r"^(`{3,}).*?^\1[^\n]*\n?", "", text, flags=re.M | re.S)  # headings inside code fences are not sections
    found = re.findall(r"^(## Open after[^\n]*\n.*?)(?=^## |\Z)", text, re.M | re.S)
    return "\n\n".join(s.strip() for s in found)


def gather(ref, run=git):
    prev = previous_tag(ref, run)
    span = prev + ".." + ref if prev else ref
    commits = run("log", "--no-merges", "--format=--- %s%n%b", span, "--", "src")
    commits = re.sub(r"^(Co-Authored-By|Claude-Session):.*\n?", "", commits, flags=re.M | re.I).strip()
    changelog = run("show", ref + ":CHANGELOG.md")
    # a final's "## <tag>" is written by publish.yml after the notes, so Unreleased leads; the tag's own section is the
    # fallback for tags cut before publish.yml wrote the changelog (v0.1.0, renamed by hand)
    pending = section(changelog, "Unreleased")
    entry = pending if re.search(r"^(?!###)\S", pending, re.M) else section(changelog, ref)
    known = []
    if prev:
        for path in run("diff", "--name-only", "--diff-filter=AM", prev, ref, "--", PLANS).split():
            body = open_after(run("show", ref + ":" + path))
            if body:
                known.append(body)
    return {"tag": ref, "previous": prev, "commits": commits, "changelog": entry, "known": "\n\n".join(known)}


def user_message(m):
    if not m["commits"] and not m["changelog"]:
        raise SystemExit("release_notes: no commits under src/ and no changelog entry since %s" % m["previous"])
    return (
        "Release %s (previous release: %s).\n\n"
        "<changelog>\n%s\n</changelog>\n\n"
        "<commits>\n%s\n</commits>\n\n"
        "<open_issues>\n%s\n</open_issues>\n\n"
        "Write the release notes for %s."
    ) % (m["tag"], m["previous"] or "none", m["changelog"], m["commits"], m["known"], m["tag"])


def build_request(m):
    return {
        "model": MODEL,
        "max_tokens": 16000,
        "output_config": {"effort": "high"},
        "system": SYSTEM,
        "messages": [{"role": "user", "content": user_message(m)}],
    }


def call_api(request, key, opener=urllib.request.urlopen):
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(request).encode(),
        method="POST",
        headers={
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
    )
    try:
        with opener(req, timeout=600) as resp:
            body = json.load(resp)
    except urllib.error.HTTPError as e:
        raise SystemExit("release_notes: API error %d: %s" % (e.code, e.read().decode(errors="replace")[:500]))
    if body.get("stop_reason") in ("refusal", "max_tokens"):
        raise SystemExit("release_notes: no notes (stop_reason %s)" % body["stop_reason"])
    text = "".join(b.get("text", "") for b in body.get("content", []) if b.get("type") == "text").strip()
    if not text:
        raise SystemExit("release_notes: the API returned no text")
    return text + "\n"


def main(argv):
    if len(argv) == 3 and argv[1] == "--material":
        print(user_message(gather(argv[2])))
        return 0
    if len(argv) != 3:
        raise SystemExit(__doc__)
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        raise SystemExit("release_notes: ANTHROPIC_API_KEY is not set")
    notes = call_api(build_request(gather(argv[1])), key)
    with open(argv[2], "w") as f:
        f.write(notes)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
