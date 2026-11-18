#!/usr/bin/env python3
"""Posts a published release's notes to Discord #releases (docs/publishing/README.md, "One-time setup").

usage: discord_notes.py [--dry-run] <event.json>     (the publish event payload; DISCORD_RELEASES_WEBHOOK in the env)
--dry-run prints the JSON payloads and posts nothing. Python 3 standard library only. Never prints the webhook URL.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

LIMIT = 2000  # Discord's message length
NO_EMBEDS = 4  # message flag SUPPRESS_EMBEDS
NO_MENTIONS = {"parse": []}  # notes can never ping @everyone, @here or a role


def split(text, limit=LIMIT):
    """Chunks of at most `limit` characters, cut at line ends; a single longer line is cut hard.
    shortcut: a code fence open across a cut is not reopened; the notes carry none, upgrade if they start to."""
    out, cur = [], ""
    for line in text.split("\n"):
        while len(line) > limit:
            if cur:
                out.append(cur)
                cur = ""
            out.append(line[:limit])
            line = line[limit:]
        if cur and len(cur) + 1 + len(line) > limit:
            out.append(cur)
            cur = line
        else:
            cur = cur + "\n" + line if cur else line
    if cur:
        out.append(cur)
    return out


def payloads(release):
    head = "**Hekili Forever %s**\n%s" % (release["tag_name"], release["html_url"])
    body = (release.get("body") or "").strip()
    chunks = split(head + "\n\n" + body if body else head)
    return [
        dict({"content": c, "allowed_mentions": NO_MENTIONS}, **({"flags": NO_EMBEDS} if i else {}))
        for i, c in enumerate(chunks)
    ]


def post(url, payload):
    data = json.dumps(payload).encode()
    for _ in range(5):
        req = urllib.request.Request(url, data, {"Content-Type": "application/json", "User-Agent": "hekili-release"})
        try:
            urllib.request.urlopen(req, timeout=30).close()
            return
        except urllib.error.HTTPError as e:
            if e.code != 429:
                sys.exit("discord_notes: the post failed with HTTP %d" % e.code)
            try:
                wait = float(json.load(e).get("retry_after", 1))
            except (ValueError, TypeError):
                wait = 1.0
            time.sleep(min(wait, 30) + 0.1)
        except (urllib.error.URLError, OSError) as e:
            sys.exit("discord_notes: the post failed (%s)" % type(e).__name__)  # the reason can echo the URL
    sys.exit("discord_notes: rate limited on every try")


def main(argv):
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if len(args) != 1:
        sys.exit(__doc__)
    with open(args[0], encoding="utf-8") as f:
        msgs = payloads(json.load(f)["release"])
    if dry:
        print(json.dumps(msgs, indent=2, ensure_ascii=False))
        return
    url = os.environ.get("DISCORD_RELEASES_WEBHOOK", "")
    if not url:
        sys.exit("discord_notes: DISCORD_RELEASES_WEBHOOK is not set")
    for i, m in enumerate(msgs):
        if i:
            time.sleep(1)
        post(url, m)
    print("discord_notes: posted %d message(s)" % len(msgs))


if __name__ == "__main__":
    main(sys.argv[1:])
