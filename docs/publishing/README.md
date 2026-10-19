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
equal to the zip version. Neither target is part of `make check` (they need the network and a clean commit).

The packager versions the zip from `git describe`. On a dirty tree, or with no release tag (the first one will be
`v0.1.0`), that is a describe string; it may name an upstream tag such as `v2.5.5-...-g<hash>`, which is harmless for a
dry run.

To try the zip in game, back up and remove the four `mklink /D` links first, or extraction writes into the WSL repo. In
an elevated Windows `cmd` in `_classic_beta_\Interface\AddOns`: `rmdir Hekili Hekili_Shared Hekili_Druid
Hekili_Warrior` (rmdir on a directory link removes only the link). Extract the zip there (from
`\\wsl.localhost\personal\home\zack\src\hekili\.release\`), full client restart, log in a Druid or Warrior: displays
show, `/hekili` opens, General page has the notice, no Lua errors. Then delete the four extracted folders and re-create
the links, one per addon: `mklink /D <Addon> \\wsl.localhost\personal\home\zack\src\hekili\src\<Addon>`.
