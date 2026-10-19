"""Offline tests for tools/cf_upload.py (approved-release plan): no network, no token."""

import email.parser
import email.policy
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import cf_upload as cf  # noqa: E402

VERSIONS = [
    {"id": 1, "name": "1.60.1", "gameVersionTypeID": 67408},  # same name, classic type: not ours
    {"id": 2, "name": "1.60.0", "gameVersionTypeID": 88568},
    {"id": 3, "name": "1.60.1", "gameVersionTypeID": 88568},
]


def release(**kw):
    r = {"tag_name": "v0.2.0", "body": "Notes.\n\n### Rogue\n- Fixed.\n", "prerelease": False, "draft": False}
    r.update(kw)
    return r


class VersionId(unittest.TestCase):
    def test_matches_name_and_forever_type(self):
        self.assertEqual(cf.version_id(VERSIONS), 3)

    def test_missing_or_ambiguous_stops(self):
        with self.assertRaises(SystemExit):
            cf.version_id(VERSIONS[:2])
        with self.assertRaises(SystemExit):
            cf.version_id(VERSIONS + [{"id": 4, "name": "1.60.1", "gameVersionTypeID": 88568}])


class Metadata(unittest.TestCase):
    def test_release(self):
        self.assertEqual(
            cf.metadata(release(), 3),
            {
                "changelog": "Notes.\n\n### Rogue\n- Fixed.",
                "changelogType": "markdown",
                "displayName": "v0.2.0",
                "gameVersions": [3],
                "releaseType": "release",
            },
        )

    def test_prerelease_is_beta(self):
        self.assertEqual(cf.metadata(release(tag_name="v0.2.0-rc.1", prerelease=True), 3)["releaseType"], "beta")

    def test_empty_body_stops(self):
        for body in (None, "", "  \n"):
            with self.assertRaises(SystemExit):
                cf.metadata(release(body=body), 3)


class Multipart(unittest.TestCase):
    def test_parses_back_into_metadata_and_file(self):
        meta = cf.metadata(release(), 3)
        data = b"PK\x03\x04\r\n--not-a-boundary\x00"
        body = cf.multipart(meta, "Hekili-v0.2.0-forever.zip", data, "BOUNDARY123")
        head = b"Content-Type: multipart/form-data; boundary=BOUNDARY123\r\n\r\n"
        msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(head + body)
        parts = list(msg.iter_parts())
        self.assertEqual([p.get_param("name", header="content-disposition") for p in parts], ["metadata", "file"])
        self.assertEqual(json.loads(parts[0].get_content()), meta)
        self.assertEqual(parts[1].get_filename(), "Hekili-v0.2.0-forever.zip")
        self.assertEqual(parts[1].get_payload(decode=True), data)


class Upload(unittest.TestCase):
    def test_looks_up_the_version_then_posts_the_file(self):
        calls = []

        class Resp(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        def opener(req, timeout):
            calls.append(req)
            return Resp(json.dumps(VERSIONS if req.get_method() == "GET" else {"id": 99}).encode())

        with tempfile.NamedTemporaryFile(suffix=".zip") as z:
            z.write(b"zipbytes")
            z.flush()
            meta, result = cf.upload(release(), z.name, "tok", opener)
        self.assertEqual(result, {"id": 99})
        self.assertEqual(calls[0].full_url, "https://wow.curseforge.com/api/game/versions")
        self.assertEqual(calls[1].full_url, "https://wow.curseforge.com/api/projects/1753387/upload-file")
        self.assertEqual(calls[1].get_header("X-api-token"), "tok")
        self.assertTrue(calls[1].get_header("Content-type").startswith("multipart/form-data; boundary="))
        self.assertIn(b"zipbytes", calls[1].data)

    def test_http_error_stops_without_the_token(self):
        def opener(req, timeout):
            raise urllib.error.HTTPError(req.full_url, 400, "Bad", {}, io.BytesIO(b'{"errorMessage":"duplicate"}'))

        with self.assertRaises(SystemExit) as cm:
            cf.call(cf.API + "/game/versions", "tok-secret", opener=opener)
        self.assertIn("duplicate", cm.exception.code)
        self.assertNotIn("tok-secret", cm.exception.code)


if __name__ == "__main__":
    unittest.main()
