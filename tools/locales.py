"""Keep Hekili's translation files in step with the code (docs/dev/architecture.md, "Localization").

Every piece of text a player sees is written L["English text"] in the addons' .lua files (src/Hekili/Locales/
Locales.lua). The key is a string literal, or literals joined with `..` (L["first part " .. "second part"]); never a
variable, so this script can read every key. It collects them from every addon TOC, in load order, and rewrites
src/Hekili/Locales/<locale>.lua for each language:

  - translated keys stay as they are:          L["Reset"] = "重置"
  - keys still to translate become comments:   -- L["Reset"] = ""
  - translations whose English no longer appears in the code (reworded or removed) move to a section at the end,
    so they can be reused or deleted.

Keys are grouped by the file that first uses them, so a translator can see where each one shows. Run from the
repository root after changing any text:

    python3 tools/locales.py            write src/Hekili/Locales/enUS.lua and update every
                                        src/Hekili/Locales/<locale>.lua
    python3 tools/locales.py --check    change nothing; exit 1 if a file is out of date, a key is not a literal, or a
                                        translation drops a format code (%s, %d...), a colour (|c...|r) or a line break

tests/tools/test_locales.py runs the check in `make tools-test`.
"""

import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "src")
LOCALES = os.path.join(SRC, "Hekili", "Locales")
CORE = "Hekili"
SKIP = ("Locales.lua", "enUS.lua")  # files in Locales/ that are not a translation
UNUSED_MARK = "-- No longer used"

NAMES = {
    "zhCN": "Simplified Chinese",
    "zhTW": "Traditional Chinese",
    "koKR": "Korean",
    "deDE": "German",
    "frFR": "French",
    "esES": "Spanish (Spain)",
    "esMX": "Spanish (Mexico)",
    "ptBR": "Portuguese (Brazil)",
    "ruRU": "Russian",
    "itIT": "Italian",
}

HEADER = """\
-- Locales/{locale}.lua
-- {name} ({locale}) translation of Hekili Forever ({app}). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("{app}", "{locale}")
if not L then
    return
end
"""

ENUS_HEADER = """\
-- Locales/enUS.lua
-- The English string table of {app} (AceLocale-3.0, silent): every L[...] key its code uses, each its own text.
-- Written by tools/locales.py: do not edit. It loads first, so its NewLocale is the app's first (the one whose
-- `silent` counts): a key no table holds answers itself.

local L = LibStub("AceLocale-3.0"):NewLocale("{app}", "enUS", true, true)
"""

# ---------------------------------------------------------------------------------------------------------------------
# Lua strings


def lua_unescape(body):
    """The value of a quoted Lua 5.1 string literal's body (between the quotes)."""
    out, i = [], 0
    simple = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\\": "\\", '"': '"', "'": "'"}
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = body[i + 1]
        if nxt in simple:
            out.append(simple[nxt])
            i += 2
        elif nxt == "\n":
            out.append("\n")
            i += 2
        elif nxt.isdigit():
            m = re.match(r"\d{1,3}", body[i + 1 :])
            out.append(chr(int(m.group(0))))
            i += 1 + len(m.group(0))
        else:
            raise ValueError("unknown escape \\" + nxt)
    return "".join(out)


def lua_quote(s):
    """A Lua literal for `s`, quoted as StyLua writes it (quote_style = AutoPreferDouble)."""
    body = s.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    if s.count('"') > s.count("'"):
        return "'" + body.replace("'", "\\'") + "'"
    return '"' + body.replace('"', '\\"') + '"'


def scan_literal(src, i):
    """(value, end) of the string literal starting at src[i], or None if none starts there."""
    c = src[i] if i < len(src) else ""
    if c in "\"'":
        j = i + 1
        while src[j] != c:
            if src[j] == "\n":
                raise ValueError("unfinished string")
            j += 2 if src[j] == "\\" else 1
        return lua_unescape(src[i + 1 : j]), j + 1
    m = re.match(r"\[(=*)\[", src[i:])
    if m:
        close = "]" + m.group(1) + "]"
        start = i + len(m.group(0))
        end = src.index(close, start)
        body = src[start:end]
        if body.startswith("\r\n"):
            body = body[2:]
        elif body.startswith("\n"):
            body = body[1:]
        return body, end + len(close)
    return None


def skip_space(src, i):
    """Past whitespace and comments."""
    while i < len(src):
        if src[i].isspace():
            i += 1
        elif src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                i = src.index("]" + m.group(1) + "]", i) + len(m.group(1)) + 2
            else:
                j = src.find("\n", i)
                i = len(src) if j < 0 else j
        else:
            break
    return i


def keys_in(src, path):
    """[(key, line)] of every L[...] in a Lua source, and [(line, problem)] for each L[...] that is not literal."""
    keys, problems = [], []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            i = skip_space(src, i)
            continue
        if c in "\"'" or (c == "[" and re.match(r"\[=*\[", src[i:])):
            i = scan_literal(src, i)[1]
            continue
        if c == "L" and (i == 0 or not re.match(r"[\w.:]", src[i - 1])) and not re.match(r"\w", src[i + 1 : i + 2]):
            j = skip_space(src, i + 1)
            if j < n and src[j] == "[" and not re.match(r"\[=*\[", src[j:]):
                line = src.count("\n", 0, i) + 1
                k = skip_space(src, j + 1)
                parts = []
                lit = scan_literal(src, k)
                while lit:
                    parts.append(lit[0])
                    k = skip_space(src, lit[1])
                    if src.startswith("..", k):
                        k = skip_space(src, k + 2)
                        lit = scan_literal(src, k)
                        if not lit:
                            break
                    else:
                        lit = None
                if parts and src[k] == "]":
                    keys.append(("".join(parts), line))
                    i = k + 1
                    continue
                problems.append((line, "L[...] key is not a string literal"))
                i = j + 1
                continue
        i += 1
    return keys, problems


# ---------------------------------------------------------------------------------------------------------------------
# The addons


def toc_files(toc):
    """The .lua files a TOC loads, in order, repository-relative (XML includes and Libs skipped)."""
    base = os.path.dirname(toc)
    out = []
    with open(toc, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            path = os.path.normpath(os.path.join(base, line.replace("\\", os.sep)))
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            if rel.endswith(".lua") and "/Libs/" not in rel and "/Locales/" not in rel:
                out.append(rel)
    return out


def addon_tocs():
    """Hekili first, then Hekili_Shared, then the class packs alphabetically."""
    tocs = []
    for name in sorted(os.listdir(SRC)):
        toc = os.path.join(SRC, name, name + ".toc")
        if os.path.isfile(toc):
            tocs.append(toc)
    order = {"Hekili": 0, "Hekili_Shared": 1}
    return sorted(tocs, key=lambda t: (order.get(os.path.basename(os.path.dirname(t)), 2), t))


def lua_files():
    files = []
    for toc in addon_tocs():
        for f in toc_files(toc):
            if f not in files:
                files.append(f)
    return files


# A file takes part once it names the table: `local L = ns.L` (core) or `local L = Hekili.L` (the class packs).
USES_L = re.compile(r"^local L = (?:ns|Hekili)\.L\b", re.M)


def collect():
    """({file: [keys first used there]} in load order, [problems])."""
    seen, grouped, problems = set(), {}, []
    for rel in lua_files():
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            src = f.read()
        if not USES_L.search(src):
            continue
        keys, bad = keys_in(src, rel)
        problems += ["%s:%d: %s" % (rel, line, why) for line, why in bad]
        for key, _ in keys:
            if key not in seen:
                seen.add(key)
                grouped.setdefault(rel, []).append(key)
    return grouped, problems


# ---------------------------------------------------------------------------------------------------------------------
# Language files

TRANSLATED = re.compile(r"""^L\[(".*"|'.*')\]\s*=\s*(".*"|'.*')\s*$""")


def read_translations(path):
    """{key: translation} of a language file's uncommented L[...] lines."""
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = TRANSLATED.match(line.rstrip("\n"))
            if m:
                key = scan_literal(m.group(1), 0)[0]
                out[key] = scan_literal(m.group(2), 0)[0]
    return out


def render_enus(app, grouped):
    lines = [ENUS_HEADER.format(app=app).rstrip("\n")]
    for rel, keys in grouped.items():
        lines.append("")
        lines.append("-- " + rel[len("src/") :])
        for key in keys:
            lines.append("L[%s] = true" % lua_quote(key))
    return "\n".join(lines) + "\n"


def render(app, locale, grouped, translations):
    lines = [HEADER.format(app=app, locale=locale, name=NAMES.get(locale, locale)).rstrip("\n")]
    used = set()
    for rel, keys in grouped.items():
        lines.append("")
        lines.append("-- " + rel[len("src/") :])
        for key in keys:
            used.add(key)
            if key in translations:
                lines.append("L[%s] = %s" % (lua_quote(key), lua_quote(translations[key])))
            else:
                lines.append('-- L[%s] = ""' % lua_quote(key))
    unused = [k for k in translations if k not in used]
    if unused:
        lines.append("")
        lines.append(UNUSED_MARK + " (the English changed or went away): reuse or delete")
        for key in unused:
            lines.append("L[%s] = %s" % (lua_quote(key), lua_quote(translations[key])))
    return "\n".join(lines) + "\n"


# Codes a translation keeps from its English: format specifiers, colours, textures, atlases, line breaks.
CODES = [
    ("format code", re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?[sdifgxXcq%]")),
    ("colour", re.compile(r"\|c[0-9A-Fa-f]{8}|\|r")),
    ("texture", re.compile(r"\|T[^|]*\|t|\|A[^|]*\|a")),
    ("line break", re.compile(r"\n")),
]


def code_problems(key, value):
    out = []
    for what, rx in CODES:
        want = sorted(re.sub(r"%\d+\$", "%", m) for m in rx.findall(key))
        got = sorted(re.sub(r"%\d+\$", "%", m) for m in rx.findall(value))
        if want != got:
            out.append("%s %s: %r has %s, translation has %s" % (what, "differs", key[:60], want, got))
    return out


def languages():
    return sorted(f[:-4] for f in os.listdir(LOCALES) if f.endswith(".lua") and f not in SKIP)


def sync(path, text, check, stale):
    """Writes `text` to `path` unless --check; a difference is stale."""
    current = None
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            current = f.read()
    if current != text:
        if check:
            stale.append(os.path.relpath(path, ROOT).replace(os.sep, "/"))
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)


def main(argv):
    check = "--check" in argv
    grouped, problems = collect()
    stale = []
    total = sum(len(k) for k in grouped.values())
    sync(os.path.join(LOCALES, "enUS.lua"), render_enus(CORE, grouped), check, stale)
    for locale in languages():
        path = os.path.join(LOCALES, locale + ".lua")
        translations = read_translations(path)
        for key, value in translations.items():
            problems += ["%s.lua: %s" % (locale, p) for p in code_problems(key, value)]
        sync(path, render(CORE, locale, grouped, translations), check, stale)
        done = sum(1 for keys in grouped.values() for k in keys if k in translations)
        print("%s: %d of %d translated" % (locale, done, total))
    for p in problems:
        print(p)
    for rel in stale:
        print("%s is out of date: run python3 tools/locales.py and commit the result" % rel)
    return 1 if problems or stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
