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


class Split(unittest.TestCase):
    def test_short_is_one(self):
        self.assertEqual(dn.split("a\nb"), ["a\nb"])

    def test_long_splits_on_lines(self):
        text = "\n".join("x" * 99 for _ in range(60))
        chunks = dn.split(text)
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(len(c) <= 2000 for c in chunks))
        self.assertEqual("\n".join(chunks), text)  # cut only at line ends

    def test_overlong_line_cut_hard(self):
        chunks = dn.split("head\n" + "y" * 4500)
        self.assertEqual(chunks, ["head", "y" * 2000, "y" * 2000, "y" * 500])


class Payloads(unittest.TestCase):
    def test_header_and_body(self):
        m = dn.payloads(rel("Notes.\n\n### Rogue\n- Fixed."))
        self.assertEqual(len(m), 1)
        self.assertTrue(m[0]["content"].startswith("**Hekili Forever v0.2.0**\n" + URL))
        self.assertIn("### Rogue", m[0]["content"])

    def test_no_mentions_and_later_chunks_no_embeds(self):
        m = dn.payloads(rel("\n".join("z" * 90 for _ in range(60))))
        self.assertGreater(len(m), 1)
        self.assertTrue(all(p["allowed_mentions"] == {"parse": []} for p in m))
        self.assertNotIn("flags", m[0])
        self.assertTrue(all(p["flags"] == 4 for p in m[1:]))
        self.assertTrue(all(len(p["content"]) <= 2000 for p in m))

    def test_empty_body(self):
        m = dn.payloads(rel(None))
        self.assertEqual(m[0]["content"], "**Hekili Forever v0.2.0**\n" + URL)


class Cli(unittest.TestCase):
    def test_dry_run_prints_payloads_not_url(self):
        os.environ["DISCORD_RELEASES_WEBHOOK"] = "https://discord.com/api/webhooks/SECRETID/SECRETTOKEN"
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"release": rel("Notes.")}, f)
        out = io.StringIO()
        with redirect_stdout(out):
            dn.main(["--dry-run", f.name])
        os.unlink(f.name)
        os.environ.pop("DISCORD_RELEASES_WEBHOOK")
        self.assertEqual(json.loads(out.getvalue())[0]["allowed_mentions"], {"parse": []})
        self.assertNotIn("SECRET", out.getvalue())


if __name__ == "__main__":
    unittest.main()
