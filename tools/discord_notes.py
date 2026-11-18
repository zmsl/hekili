#!/usr/bin/env python3
"""Posts a published release to Discord #releases: one message, the notes attached as a .txt
(docs/publishing/README.md, "One-time setup").

usage: discord_notes.py [--dry-run] <event.json>     (the publish event payload; DISCORD_RELEASES_WEBHOOK in the env)
--dry-run prints the payload_json and the attachment's name and size, and posts nothing.
Python 3 standard library only. Never prints the webhook URL.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

import cf_upload

NO_EMBEDS = 4  # message flag SUPPRESS_EMBEDS
NO_MENTIONS = {"parse": []}  # notes can never ping @everyone, @here or a role


def message(release):
    """(payload_json, filename, bytes): one message, the notes attached as a .txt; no attachment for an empty body."""
    tag = release["tag_name"]
    meta = {
        "content": "**Hekili Forever %s**\n%s" % (tag, release["html_url"]),
        "flags": NO_EMBEDS,
        "allowed_mentions": NO_MENTIONS,
    }
    body = (release.get("body") or "").strip().encode("utf-8")
    if not body:
        return meta, None, b""
    name = "release-notes-%s.txt" % tag
    meta["attachments"] = [{"id": 0, "filename": name}]
    return meta, name, body


def request(meta, name, body, url):
    if not name:
        return urllib.request.Request(
            url, json.dumps(meta).encode(), {"Content-Type": "application/json", "User-Agent": "hekili-release"}
        )
    boundary = uuid.uuid4().hex
    data = cf_upload.multipart(meta, name, body, boundary, "payload_json", "files[0]", "text/plain")
    headers = {"Content-Type": "multipart/form-data; boundary=" + boundary, "User-Agent": "hekili-release"}
    return urllib.request.Request(url, data, headers)


def post(url, meta, name, body):
    for _ in range(5):
        req = request(meta, name, body, url)
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
        meta, name, body = message(json.load(f)["release"])
    if dry:
        print(json.dumps(meta, indent=2, ensure_ascii=False))
        print("attachment: %s (%d bytes)" % (name, len(body)) if name else "attachment: none")
        return
    url = os.environ.get("DISCORD_RELEASES_WEBHOOK", "")
    if not url:
        sys.exit("discord_notes: DISCORD_RELEASES_WEBHOOK is not set")
    post(url, meta, name, body)
    print("discord_notes: posted")


if __name__ == "__main__":
    main(sys.argv[1:])
