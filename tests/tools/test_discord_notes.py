"""Offline tests for tools/discord_notes.py: no network, no webhook."""

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import discord_notes as dn  # noqa: E402

URL = "https://github.com/zmsl/forever/releases/tag/v0.2.0"


def rel(body):
    return {"tag_name": "v0.2.0", "html_url": URL, "body": body}


class Message(unittest.TestCase):
    def test_one_message_with_attachment(self):
        body = "Notes \u2014 ok.\n\n### Rogue\n- Fixed."
        meta, name, data = dn.message(rel(body + "\n"))
        self.assertEqual(meta["content"], "**Hekili Forever v0.2.0**\n" + URL)
        self.assertEqual(meta["flags"], 4)
        self.assertEqual(meta["allowed_mentions"], {"parse": []})
        self.assertEqual(meta["attachments"], [{"id": 0, "filename": "release-notes-v0.2.0.txt"}])
        self.assertEqual(name, "release-notes-v0.2.0.txt")
        self.assertEqual(data, body.encode("utf-8"))

    def test_long_body_stays_one_message(self):
        _, _, data = dn.message(rel("\n".join("z" * 90 for _ in range(60))))
        self.assertGreater(len(data), 2000)

    def test_empty_body_header_only(self):
        meta, name, data = dn.message(rel(None))
        self.assertEqual(meta["content"], "**Hekili Forever v0.2.0**\n" + URL)
        self.assertNotIn("attachments", meta)
        self.assertEqual((name, data), (None, b""))

    def test_multipart_well_formed(self):
        meta, name, data = dn.message(rel("Notes."))
        req = dn.request(meta, name, data, "https://discord.invalid/x")
        ctype = req.get_header("Content-type")
        self.assertTrue(ctype.startswith("multipart/form-data; boundary="))
        b = ctype.split("boundary=")[1].encode()
        parts = req.data.split(b"--" + b)
        self.assertEqual(parts[0], b"")
        self.assertEqual(parts[-1], b"--\r\n")
        self.assertEqual(len(parts), 4)
        self.assertIn(b'name="payload_json"', parts[1])
        self.assertIn(b"\r\n\r\n" + json.dumps(meta).encode() + b"\r\n", parts[1])
        self.assertIn(b'name="files[0]"; filename="release-notes-v0.2.0.txt"', parts[2])
        self.assertIn(b"Content-Type: text/plain\r\n\r\nNotes.\r\n", parts[2])

    def test_empty_body_is_plain_json(self):
        meta, name, data = dn.message(rel(""))
        req = dn.request(meta, name, data, "https://discord.invalid/x")
        self.assertEqual(req.get_header("Content-type"), "application/json")
        self.assertEqual(json.loads(req.data), meta)


class Cli(unittest.TestCase):
    def test_dry_run_prints_payload_not_url(self):
        os.environ["DISCORD_RELEASES_WEBHOOK"] = "https://discord.com/api/webhooks/SECRETID/SECRETTOKEN"
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"release": rel("Notes.")}, f)
        out = io.StringIO()
        with redirect_stdout(out):
            dn.main(["--dry-run", f.name])
        os.unlink(f.name)
        os.environ.pop("DISCORD_RELEASES_WEBHOOK")
        self.assertIn('"allowed_mentions"', out.getvalue())
        self.assertIn("attachment: release-notes-v0.2.0.txt (6 bytes)", out.getvalue())
        self.assertNotIn("SECRET", out.getvalue())


if __name__ == "__main__":
    unittest.main()
