"""Offline tests for tools/locales.py: the translation files match the code, and the key reader is exact."""

import contextlib
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import locales  # noqa: E402


class Repository(unittest.TestCase):
    def test_translation_files_are_up_to_date(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = locales.main(["--check"])
        self.assertEqual(rc, 0, out.getvalue())

    def test_every_language_file_is_loaded_by_the_toc(self):
        with open(os.path.join(locales.SRC, "Hekili", "Hekili.toc"), encoding="utf-8") as f:
            toc = f.read()
        self.assertIn("Locales\\Locales.lua", toc)
        for locale in locales.languages():
            self.assertIn("Locales\\%s.lua" % locale, toc)
        self.assertLess(toc.index("Locales\\Locales.lua"), toc.index("Hekili.lua"))


class Keys(unittest.TestCase):
    def keys(self, src):
        keys, problems = locales.keys_in(src, "t.lua")
        return [k for k, _ in keys], [p for _, p in problems]

    def test_literals_and_literal_chains(self):
        keys, problems = self.keys('a = L["One"] b = L[ "Two " .. -- note\n "parts" ] c = L[\'it\\\'s\']')
        self.assertEqual(keys, ["One", "Two parts", "it's"])
        self.assertEqual(problems, [])

    def test_escapes_are_decoded(self):
        keys, _ = self.keys('x = L["a\\nb \\"q\\" \\124cFFFFFFFF"]')
        self.assertEqual(keys, ['a\nb "q" |cFFFFFFFF'])

    def test_a_variable_key_is_a_problem(self):
        keys, problems = self.keys("x = L[ name ] y = L[ \"a\" .. name ]")
        self.assertEqual(keys, [])
        self.assertEqual(len(problems), 2)

    def test_strings_comments_and_other_names_are_ignored(self):
        keys, problems = self.keys('-- L["no"]\ns = "L[\\"no\\"]" t.L["no"] XL["no"] L2["no"]')
        self.assertEqual(keys, [])
        self.assertEqual(problems, [])


class Codes(unittest.TestCase):
    def test_format_codes_colours_and_breaks_must_survive(self):
        self.assertEqual(locales.code_problems("%s is %d\n|cFFFFD100x|r", "%s 为 %d\n|cFFFFD100x|r"), [])
        self.assertTrue(locales.code_problems("%s is %d", "%s 为"))
        self.assertTrue(locales.code_problems("|cFFFFD100x|r", "x"))
        self.assertTrue(locales.code_problems("a\nb", "ab"))

    def test_reordered_arguments_count_as_the_same_codes(self):
        self.assertEqual(locales.code_problems("%s at %d", "%2$d 处的 %1$s"), [])


class Quoting(unittest.TestCase):
    def test_quotes_as_stylua_does(self):
        self.assertEqual(locales.lua_quote("plain"), '"plain"')
        self.assertEqual(locales.lua_quote('say "hi"'), "'say \"hi\"'")
        self.assertEqual(locales.lua_quote("it's \"x\""), "'it\\'s \"x\"'")
        self.assertEqual(locales.lua_quote("a'b'c \"x\""), '"a\'b\'c \\"x\\""')
        self.assertEqual(locales.lua_quote("a\nb\\c"), '"a\\nb\\\\c"')

    def test_round_trip(self):
        for s in ["plain", 'say "hi"', "it's \"x\"", "a\nb\\c", "|cFFFFD100中文|r"]:
            self.assertEqual(locales.scan_literal(locales.lua_quote(s), 0)[0], s)


if __name__ == "__main__":
    unittest.main()
