#!/usr/bin/env python3
"""Vendored libraries: a lock file, an offline check, an update to a tag, and the gate "is this the newest tag?".

usage: vendor_libs.py --check  [--root DIR] [--lock FILE]
       vendor_libs.py --tagged [--root DIR] [--lock FILE]
       vendor_libs.py --update [--root DIR] [--lock FILE] [--only NAME [--tag TAG]]
       vendor_libs.py --latest [--root DIR]

The lock (vendor.lock, JSON) lists libraries: name, repository (a URL, or a path relative to the root), path (the folder
in this tree and in the repository), tag ("untagged" before the first one), sha (the tag's commit) and digest ("sha256:"
over the folder's files). Any host can use this file as it is; it needs Python 3's standard library and git.

--check and --tagged are offline and read the working tree: every folder equals its digest; every entry names a tag.

A release tag is v<major>.<minor>.<patch>: canonical ASCII digits, ordered numerically. On major 0 the middle number is
LibStub's MINOR; from major 1 it is free, and the MINOR in the code never resets. Any other upstream tag that begins
like a version (v or V, then a digit) makes --latest and --update refuse: it is never skipped.

--latest passes only when ALL of these hold for every entry of vendor.lock in HEAD (never the working lock):
  1. the lock has at least one entry;
  2. the newest release tag upstream is the lock's tag;
  3. that tag is valid by content: every tag of major 0 has the MINOR its name says, its own MINOR is at least that of
     every lower tag, and its shipped code equals every tag's of that MINOR (shipped = the folder minus README.md,
     LICENSE and Testing/, the TOC without its comment lines). An invalid tag is refused, never skipped: delete it
     upstream;
  4. that tag's commit is the lock's sha;
  5. the git tree of <path> in HEAD is the tree of <path> in that tag;
  6. the lock and the folder have no uncommitted, untracked, ignored or index-hidden change.

--update takes the newest tag (or --tag) into the working tree and the lock, and commits nothing. Before it chooses, the
lock's tag must be upstream at the lock's sha. It refuses an invalid or older tag, a folder that differs from the lock's
digest, entries that are not plain files, a file this tree's git would convert on commit, changed code with an equal
MINOR and a lower MINOR. Every refusal and every error (network, git, parse) exits non-zero.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

VALID = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
VERSION_LIKE = re.compile(r"[vV][0-9]")
ROW = re.compile(rb"([0-9a-f]{40,64})\trefs/tags/(.+?)(?:\^\{\})?\Z")
NAME = re.compile(r"[A-Za-z0-9_-]+\Z")
ENTRY = re.compile(r"[A-Za-z0-9._ +/-]+\Z")
MINOR = re.compile(r'^local MAJOR, MINOR = "[^"]*", *([0-9]+)', re.M)
REDIRECTS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_NAMESPACE")


class Refused(Exception):
    pass


def git(*args, cwd, stdin=None):
    env = {k: v for k, v in os.environ.items() if k not in REDIRECTS}  # cwd alone names the repository
    env["GIT_NO_REPLACE_OBJECTS"] = "1"  # the real objects: what a push carries
    return subprocess.run(["git", *args], cwd=cwd, env=env, input=stdin, capture_output=True, check=True).stdout


def files(folder):
    """{posix relative path: bytes} of a local folder; a symlink anywhere is refused."""
    if os.path.islink(folder):
        raise Refused("%r is a symlink" % folder)
    out = {}
    for base, dirs, names in os.walk(folder):
        dirs.sort()
        for n in sorted(names + [d for d in dirs if os.path.islink(os.path.join(base, d))]):
            p = os.path.join(base, n)
            if os.path.islink(p):
                raise Refused("%r is a symlink" % os.path.relpath(p, folder))
            if os.path.isfile(p):
                with open(p, "rb") as f:
                    out[os.path.relpath(p, folder).replace(os.sep, "/")] = f.read()
    return out


def digest(tree):
    h = hashlib.sha256()
    for k in sorted(tree):
        h.update(k.encode("utf-8", "surrogateescape") + b"\0" + hashlib.sha256(tree[k]).hexdigest().encode() + b"\n")
    return "sha256:" + h.hexdigest()


def shipped(tree, name):
    """What players run: the folder minus README.md, LICENSE and Testing/, the TOC reduced to its non-comment lines."""
    out = {}
    for k, b in tree.items():
        if k in ("README.md", "LICENSE") or k.startswith("Testing/"):
            continue
        if k == name + ".toc":
            b = b"\n".join(x for x in b.replace(b"\r", b"").split(b"\n") if x and not x.startswith(b"#"))
        out[k] = b
    return out


def minor(tree, name):
    m = MINOR.search(tree.get(name + ".lua", b"").decode("utf-8", "replace"))
    if not m:
        raise Refused("no MINOR in %s.lua" % name)
    return int(m.group(1))


def parse_lock(data):
    def once(pairs):
        if len(dict(pairs)) != len(pairs):
            raise Refused("the lock has a key twice")
        return dict(pairs)

    lock = json.loads(data, object_pairs_hook=once)
    libraries = lock.get("libraries") if isinstance(lock, dict) else None
    if not isinstance(libraries, list) or not libraries:
        raise Refused("no libraries in the lock")
    return lock


def check_name(e):
    if not NAME.match(str(e.get("name", ""))):
        raise Refused("bad library name %r" % e.get("name"))


def check_entry(e, root):
    """The lock's own fields must be safe before anything touches the disk; returns the local folder."""
    p = e.get("path", "")
    if not p or os.path.isabs(p) or ".." in p.replace("\\", "/").split("/"):
        raise Refused("%s: path %r escapes the tree" % (e["name"], p))
    full = os.path.join(root, p)
    if os.path.realpath(full) != os.path.join(os.path.realpath(root), os.path.normpath(p)):
        raise Refused("%s: %r is, or sits under, a symlink or escapes the tree" % (e["name"], p))
    return full


def check_tagged(e):
    if not VALID.match(str(e.get("tag"))):
        raise Refused("%s is %r in the lock, not at a release tag" % (e["name"], e.get("tag")))


def tag_key(tag):
    return tuple(int(x) for x in VALID.match(tag).groups())


def list_tags(e, root, tmp):
    """(repository, {release tag: commit}); refuses before any choice an unknown version, and a lock tag deleted or moved."""
    repo = e["repository"]
    if not repo or repo.startswith("-"):
        raise Refused("%s: repository %r is empty or looks like an option" % (e["name"], repo))
    if ":" not in repo:
        repo = os.path.abspath(os.path.join(root, repo))  # a path: git runs in tmp
    git("init", "-q", cwd=tmp)
    try:
        rows = git("ls-remote", "--tags", "--", repo, cwd=tmp)
    except subprocess.CalledProcessError as c:
        raise Refused("could not list the tags of %s: %r" % (repo, (c.stderr or b"").decode("utf-8", "replace").strip()[:300]))
    tags = {}
    for row in filter(None, rows.split(b"\n")):  # "\n" only: other separators are legal inside a tag name
        m = ROW.match(row)
        if not m:
            raise Refused("%s: cannot read the tag list line %r" % (e["name"], row[:120]))
        name = m.group(2).decode("utf-8", "surrogateescape")
        if VALID.match(name):
            tags[name] = m.group(1).decode()  # an annotated tag's "^{}" row (its commit) follows its own
        elif VERSION_LIKE.match(name):
            raise Refused("%s: %r looks like a version and is not a release tag (v<major>.<minor>.<patch>): delete the tag upstream" % (e["name"], name))
    if not tags:
        raise Refused("%s: the repository has no release tag" % e["name"])
    locked = e.get("tag")
    if locked != "untagged":
        if locked not in tags:
            raise Refused("%s: the locked tag %r is deleted upstream" % (e["name"], locked))
        if e.get("sha") != tags[locked]:
            raise Refused("%s: the tag %s moved: the lock recorded %r, the repository has %s" % (e["name"], locked, e.get("sha"), tags[locked]))
    return repo, tags


def read_tag(repo, path, tag, commit, tmp):
    """{relative name: bytes} of <path> at the exact tag, from git objects only."""
    git("fetch", "-q", "--no-tags", "--", repo, "+refs/tags/%s:refs/tags/%s" % (tag, tag), cwd=tmp)
    if git("rev-parse", "--verify", "refs/tags/%s^{commit}" % tag, cwd=tmp).decode().strip() != commit:
        raise Refused("the tag %s moved while it was read" % tag)
    try:
        listing = git("ls-tree", "-r", "-z", "%s:%s" % (commit, path), cwd=tmp)
    except subprocess.CalledProcessError:
        raise Refused("%s has no plain folder %s (a symlink, or missing)" % (tag, path))
    tree = {}
    for row in filter(None, listing.split(b"\0")):
        head, name = row.split(b"\t", 1)
        mode, _, oid = head.split(b" ")
        shown = os.fsdecode(name)
        if mode != b"100644":  # not b"100755" either: the copy would lose it, and rule 5 could never hold
            raise Refused("%r has mode %s: a symlink, a submodule or an executable, not a plain file" % (shown, mode.decode()))
        parts = shown.split("/")
        if any(x.lower().startswith(".git") for x in parts):
            raise Refused("%r is git metadata (.git*)" % shown)
        if not ENTRY.match(shown) or any(x in ("", ".", "..") for x in parts):
            raise Refused("%r is not a plain file name" % shown)
        tree[shown] = git("cat-file", "blob", oid.decode(), cwd=tmp)
    return tree


def read_release(e, repo, tags, tag, tmp):
    """The tag's folder, once the tag is valid by content beside every other tag (rule 3)."""
    name, path = e["name"], e["path"]

    def named_right(t):
        try:
            tree = read_tag(repo, path, t, tags[t], tmp)
            have = minor(tree, name)
        except Refused as x:
            raise Refused("%s %s: %s" % (name, t, x))
        major, middle, _ = tag_key(t)
        if major == 0 and have != middle:
            raise Refused("%s %s is invalid, its code has MINOR %d: delete the tag upstream" % (name, t, have))
        return tree, have

    tree, have = named_right(tag)
    for other in sorted(set(tags) - {tag}, key=tag_key):
        theirs, their_minor = named_right(other)
        if their_minor > have and tag_key(other) < tag_key(tag):
            raise Refused("%s %s is invalid, MINOR %d is lower than %s's %d: delete the wrong tag upstream" % (name, tag, have, other, their_minor))
        if their_minor == have and shipped(theirs, name) != shipped(tree, name):
            raise Refused("%s %s is invalid, changed code with an equal MINOR (differs from %s): delete the tag upstream" % (name, tag, other))
    return tree


def latest_entry(e, root, head, tmp):
    check_entry(e, root)
    check_tagged(e)
    repo, tags = list_tags(e, root, tmp)  # rule 4
    newest = max(tags, key=tag_key)
    read_release(e, repo, tags, newest, tmp)  # rule 3
    if e["tag"] != newest:
        raise Refused("%s is at %s, the newest is %s" % (e["name"], e["tag"], newest))
    theirs = git("rev-parse", "--verify", "%s:%s" % (tags[newest], e["path"]), cwd=tmp)
    if git("rev-parse", "--verify", "%s:./%s" % (head, e["path"]), cwd=root) != theirs:
        raise Refused("%s: %s in HEAD differs from the tree of %s" % (e["name"], e["path"], newest))
    paths = ("--", "vendor.lock", e["path"])
    changed = git("status", "--porcelain", "--untracked-files=all", "--ignored", *paths, cwd=root)
    hidden = re.findall(rb"^[^H].*", git("ls-files", "-v", *paths, cwd=root), re.M)  # what status was told to skip
    if changed or hidden:
        shown = (changed.splitlines() + hidden)[:5]
        raise Refused("%s: an uncommitted, untracked, ignored or hidden change: %r" % (e["name"], shown))
    print("ok: %s is at the newest tag (%s)" % (e["name"], newest))


def update_entry(e, root, tag, tmp):
    """The folder and the entry change only after every refusal had its chance."""
    dst = check_entry(e, root)
    if tag is not None and not VALID.match(tag):
        raise Refused("%r is not a release tag (v<major>.<minor>.<patch>)" % tag)
    repo, tags = list_tags(e, root, tmp)
    locked, name = e.get("tag"), e["name"]
    if tag is None:
        tag = max(tags, key=tag_key)
    if tag not in tags:
        raise Refused("tag %s not found in %s" % (tag, repo))
    if locked != "untagged" and tag_key(tag) < tag_key(locked):
        raise Refused("%s %s is older than the lock's %s" % (name, tag, locked))
    new = read_release(e, repo, tags, tag, tmp)
    old = files(dst) if os.path.isdir(dst) else {}
    if old and digest(old) != e.get("digest"):
        raise Refused("%s: %s has a local change (it differs from the lock's digest)" % (name, e["path"]))
    for k, data in new.items():
        as_committed = git("hash-object", "--stdin", "--path=%s/%s" % (e["path"], k), cwd=root, stdin=data)
        if as_committed != git("hash-object", "--stdin", "--no-filters", cwd=root, stdin=data):
            raise Refused("%s %s: git here would convert %r on commit (CRLF under .gitattributes or core.autocrlf)" % (name, tag, k))
    if digest(new) == digest(old):
        note = "up to date" if (locked, e.get("sha")) == (tag, tags[tag]) else "up to date (lock rewritten for %s)" % tag
    else:
        a, b = minor(old, name) if old else -1, minor(new, name)
        if b < a:
            raise Refused("%s %s: MINOR %d is lower than ours (%d)" % (name, tag, b, a))
        if b == a and shipped(new, name) != shipped(old, name):
            raise Refused("%s %s: code changed with an equal MINOR (%d)" % (name, tag, a))
        shutil.rmtree(dst, ignore_errors=True)
        for k, data in new.items():
            os.makedirs(os.path.dirname(os.path.join(dst, k)), exist_ok=True)
            with open(os.path.join(dst, k), "wb") as f:
                f.write(data)
        note = "MINOR %d -> %d" % (a, b)
    e["tag"], e["sha"], e["digest"] = tag, tags[tag], digest(new)
    print("%s: %s -> %s (commit %s): %s" % (name, locked, tag, tags[tag], note))


def check_folder(e, root):
    if digest(files(check_entry(e, root))) != e["digest"]:
        raise Refused("%s: %s differs from the lock's digest (a local edit, or a lock not updated)" % (e["name"], e["path"]))
    print("ok: %s matches the lock (%s)" % (e["name"], e["tag"]))


def fail(x):
    if isinstance(x, Refused):
        print("REFUSED: %s" % x, file=sys.stderr)
    elif isinstance(x, subprocess.CalledProcessError):
        print("vendor_libs: git failed: %r" % (x.stderr or b"").decode("utf-8", "replace").strip()[:300], file=sys.stderr)
    else:
        print("vendor_libs: failed: %r" % x, file=sys.stderr)
    return 1


def run(a):
    path = a.lock or os.path.join(a.root, "vendor.lock")
    if a.latest:
        head = git("rev-parse", "--verify", "HEAD^{commit}", cwd=a.root).decode().strip()
        lock = parse_lock(git("cat-file", "blob", head + ":./vendor.lock", cwd=a.root))
    else:
        with open(path, "rb") as f:
            lock = parse_lock(f.read())
    entries = [e for e in lock["libraries"] if a.only is None or e.get("name") == a.only]
    if not entries:
        raise Refused("%r is not in the lock" % a.only)
    before, bad = json.dumps(lock), 0
    for e in entries:
        try:
            check_name(e)
            if a.check:
                check_folder(e, a.root)
            elif a.tagged:
                check_tagged(e)
            else:
                with tempfile.TemporaryDirectory() as tmp:
                    if a.latest:
                        latest_entry(e, a.root, head, tmp)
                    else:
                        update_entry(e, a.root, a.tag, tmp)
        except Exception as x:  # whatever it is, this entry did not pass
            bad = fail(x)
    if a.update and json.dumps(lock) != before:
        with open(path, "w") as f:
            json.dump(lock, f, indent=2)
            f.write("\n")
    return bad


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    for m in ("check", "update", "tagged", "latest"):
        mode.add_argument("--" + m, action="store_true")
    ap.add_argument("--root", default=".")
    ap.add_argument("--lock")
    ap.add_argument("--only")
    ap.add_argument("--tag")
    a = ap.parse_args(argv)
    if a.only is not None and not a.update:
        ap.error("--only goes with --update: a check looks at every entry")
    if a.tag is not None and a.only is None:
        ap.error("--tag goes with --update --only NAME")
    if a.lock is not None and a.latest:
        ap.error("--latest reads vendor.lock in HEAD")
    try:
        return run(a)
    except Exception as x:
        return fail(x)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
