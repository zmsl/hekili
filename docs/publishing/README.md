# Publishing Hekili Forever

Hekili Forever is based on the original work by Hekili (https://github.com/Hekili/hekili), published with the
explicit permission of the original author.

## Local package dry run

On a clean tree (`git status --short` empty), run:

```sh
make package-check
```

`make package` downloads the BigWigs packager (`release.sh`, once, into `.lua/`) and runs it with `-d`, so nothing is
uploaded; the zip lands in `.release/`, which is gitignored. `make package-check` then runs `tools/check_package.sh` on
the newest zip: the four addon folders at the zip root, `Hekili/LICENSE`, no dev paths, and every TOC `## Version`
equal to the project version (the zip name without its -forever suffix). Neither target is part of `make check` (they
need the network and a clean commit).
Run them from a plain clone: in a git worktree (`.git` is a file) the packager stops with `No Git, SVN, or Hg
checkout found`.

The packager versions the zip from `git describe`. On a dirty tree, or with no release tag (the first one will be
`v0.1.0`), that is a describe string; it may name an upstream tag such as `v2.5.5-...-g<hash>`, which is harmless for a
dry run.

To try the zip in game, back up and remove the four `mklink /D` links first, or extraction writes into the WSL repo. In
an elevated Windows `cmd` in `_classic_beta_\Interface\AddOns`: `rmdir Hekili Hekili_Shared Hekili_Druid
Hekili_Warrior` (rmdir on a directory link removes only the link). Extract the zip there (from
`\\wsl.localhost\personal\home\zack\src\hekili\.release\`), full client restart, log in a Druid or Warrior: displays
show, `/hekili` opens, General page has the notice, no Lua errors. Then delete the four extracted folders and re-create
the links, one per addon: `mklink /D <Addon> \\wsl.localhost\personal\home\zack\src\hekili\src\<Addon>`.

## Cutting a release

Tags are `vMAJOR.MINOR.PATCH`; the first release is `v0.1.0`.

1. `make check` green on `forever`; write `## vX.Y.Z` with the changes by hand at the top of CHANGELOG.md (under the
   title); commit.
2. `git tag vX.Y.Z && git push origin vX.Y.Z` (push that one tag, never `--tags`), for example
   `git tag v0.1.0 && git push origin v0.1.0`.
3. Watch Actions > release: the one run (`.github/workflows/release.yml`) uploads the zip to CurseForge project 1753387
   with CHANGELOG.md as its changelog and creates the GitHub release for the tag. It fails early if CHANGELOG.md has
   no `## <tag>` heading.

One-time setup (already done for zmsl/hekili): CurseForge > API tokens > create token; GitHub repo > Settings >
Secrets > Actions > `CF_API_KEY`.

The packager maps `## Interface: 16001` to the game version `1.60.1` (the dry run prints `Game version: 1.60.1`), so
the workflow pins none. Optional check that CurseForge lists that version, with the same token:

```sh
curl -fsS -H "X-Api-Token: $CF_API_KEY" https://wow.curseforge.com/api/game/versions | jq '.[] | select(.name | test("^1\\.60")) | {id, name, gameVersionTypeID}'
curl -fsS -H "X-Api-Token: $CF_API_KEY" https://wow.curseforge.com/api/game/version-types | jq '.[] | {id, name, slug}'
```

If `1.60.1` is missing or listed under another name, pin the listed name in the packager step (`with: args: -g <name>`)
and pass the same `-g` in the Makefile's `package` target.
