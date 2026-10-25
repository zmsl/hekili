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

    def test_every_string_table_loads_first_and_before_the_code(self):
        for name, toc in locales.addons():
            if not os.path.isdir(locales.locales_dir(name)):
                continue
            with open(toc, encoding="utf-8") as f:
                lines = [l.strip() for l in f if l.strip() and not l.startswith("#")]
            block = ["Locales\\enUS.lua"] + ["Locales\\%s.lua" % loc for loc in locales.languages(name)]
            if name == locales.CORE:
                block.append("Locales\\Locales.lua")
            start = lines.index(block[0])
            self.assertEqual(lines[start : start + len(block)], block, name)
            first_code = next(i for i, l in enumerate(lines) if l.endswith(".lua") and not l.startswith("Locales\\"))
            if name == locales.CORE:  # after the facade, before Hekili.lua
                first_code = lines.index("Hekili.lua")
            self.assertLess(start + len(block) - 1, first_code, name)

    def test_the_shared_content_has_no_text(self):
        self.assertFalse(os.path.isdir(locales.locales_dir("Hekili_Shared")))


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


class Render(unittest.TestCase):
    def test_enus_is_every_key_as_true_under_a_silent_default_locale(self):
        text = locales.render_enus("Hekili_Warrior", {"src/Hekili_Warrior/Warrior.lua": ["Arms", 'say "hi"']})
        self.assertIn('local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Warrior", "enUS", true, true)\n', text)
        self.assertIn('-- Hekili_Warrior/Warrior.lua\nL["Arms"] = true\nL[\'say "hi"\'] = true\n', text)

    def test_a_language_file_registers_its_own_locale_and_returns_elsewhere(self):
        text = locales.render("Hekili_Warrior", "zhCN", {"src/Hekili_Warrior/Warrior.lua": ["Arms", "Fury"]}, {"Arms": "武器"})
        self.assertIn('local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Warrior", "zhCN")\nif not L then\n    return\nend\n', text)
        self.assertIn('L["Arms"] = "武器"\n-- L["Fury"] = ""\n', text)


class Adopt(unittest.TestCase):
    def test_a_new_pack_file_takes_every_key_the_core_translates(self):
        core = {"Arms": "武器", "Combat": "战斗", "Other": "x"}
        self.assertEqual(locales.adopt(["Arms", "Combat"], {}, core, {"Arms"}), {"Arms": "武器", "Combat": "战斗"})

    def test_an_existing_file_takes_only_the_pack_s_own_keys_from_the_core(self):
        core = {"Arms": "武器", "Combat": "战斗"}
        self.assertEqual(locales.adopt(["Arms", "Combat"], {"Fury": "狂怒"}, core, {"Arms"}), {"Fury": "狂怒", "Arms": "武器"})
        self.assertEqual(locales.adopt(["Arms"], {"Arms": "臂"}, core, {"Arms"}), {"Arms": "臂"})  # its own wins


class PackNames(unittest.TestCase):
    def test_register_pack_first_arguments(self):
        src = 'spec:RegisterPack(\n    "Arms (wowsims.com)",\n    1,\n    [[x]]\n)\nspec:RegisterPack( name, 1, "" )'
        self.assertEqual(locales.pack_names_in(src), [("Arms (wowsims.com)", 2)])

    def test_a_label_that_reads_as_another_priority_is_a_problem(self):
        packs = ["Arms (wowsims.com)", "Fury (wowsims.com)"]
        self.assertEqual(locales.label_problems("Hekili_Warrior", packs, {"Arms (wowsims.com)": "武器"}, "zhCN"), [])
        self.assertTrue(locales.label_problems("Hekili_Warrior", packs, {"Arms (wowsims.com)": "Fury (wowsims.com)"}, "zhCN"))
        self.assertTrue(locales.label_problems("Hekili_Warrior", packs, {"Arms (wowsims.com)": "X", "Fury (wowsims.com)": "X"}, "zhCN"))


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
