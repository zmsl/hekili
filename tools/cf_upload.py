#!/usr/bin/env python3
"""Uploads a published GitHub release's zip to CurseForge (docs/publishing/README.md, "Cutting a release").

usage: cf_upload.py <release-event.json> <zip>      (CF_API_KEY in the environment)

The event is the workflow's $GITHUB_EVENT_PATH for `release: published`: the tag is the file's display name, the
release body (markdown) its changelog, and a prerelease uploads as a beta. Python 3 standard library only. Never
prints the token or the request.
"""

import json
import os
import sys
import urllib.error
import urllib.request
import uuid

API = "https://wow.curseforge.com/api"
PROJECT = 1753387
GAME_VERSION = "1.60.1"
FOREVER_TYPE = 88568  # CurseForge's game version type for WoW Forever (BigWigs packager release.sh, upload_curseforge)


def version_id(versions, name=GAME_VERSION, type_id=FOREVER_TYPE):
    ids = [v["id"] for v in versions if v.get("name") == name and v.get("gameVersionTypeID") == type_id]
    if len(ids) != 1:
        raise SystemExit("cf_upload: %d CurseForge game versions named %s of type %d" % (len(ids), name, type_id))
    return ids[0]


def metadata(release, game_version):
    body = (release.get("body") or "").strip()
    if not body:
        raise SystemExit("cf_upload: the release body is empty; edit the release notes, then publish again")
    return {
        "changelog": body,
        "changelogType": "markdown",
        "displayName": release["tag_name"],
        "gameVersions": [game_version],
        "releaseType": "beta" if release.get("prerelease") else "release",
    }


def multipart(meta, filename, data, boundary):
    """The multipart/form-data body CurseForge's upload-file takes: a `metadata` JSON field and the `file`."""
    b = boundary.encode()
    return b"".join(
        [
            b"--" + b + b"\r\n",
            b'Content-Disposition: form-data; name="metadata"\r\n',
            b"Content-Type: application/json\r\n\r\n",
            json.dumps(meta).encode(),
            b"\r\n--" + b + b"\r\n",
            b'Content-Disposition: form-data; name="file"; filename="' + filename.encode() + b'"\r\n',
            b"Content-Type: application/zip\r\n\r\n",
            data,
            b"\r\n--" + b + b"--\r\n",
        ]
    )


def call(url, token, data=None, content_type=None, opener=urllib.request.urlopen):
    headers = {"X-Api-Token": token}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data is not None else "GET")
    try:
        with opener(req, timeout=300) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        raise SystemExit("cf_upload: %s -> %d: %s" % (url, e.code, e.read().decode(errors="replace")[:500]))


def upload(release, zip_path, token, opener=urllib.request.urlopen):
    game_version = version_id(call(API + "/game/versions", token, opener=opener))
    meta = metadata(release, game_version)
    with open(zip_path, "rb") as f:
        data = f.read()
    boundary = uuid.uuid4().hex
    body = multipart(meta, os.path.basename(zip_path), data, boundary)
    url = "%s/projects/%d/upload-file" % (API, PROJECT)
    result = call(url, token, body, "multipart/form-data; boundary=" + boundary, opener)
    return meta, result


def main(argv):
    if len(argv) != 3:
        raise SystemExit(__doc__)
    token = os.environ.get("CF_API_KEY")
    if not token:
        raise SystemExit("cf_upload: CF_API_KEY is not set")
    with open(argv[1]) as f:
        release = json.load(f)["release"]
    meta, result = upload(release, argv[2], token)
    print("cf_upload: %s (%s) uploaded as CurseForge file %s" % (meta["displayName"], meta["releaseType"], result.get("id")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
