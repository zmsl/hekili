<!--
Purpose: How the wiki is built: docs/wiki/, generated tables, wiki-check.
Type: How-to
Audience: contributors
Prerequisites: [Contributing](Contributing).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. How the wiki is built: docs/wiki/, generated tables, wiki-check.

## Where the pages live

- `docs/wiki/`, one file per page; CI publishes it when a release is published. Source: `docs/wiki/README.md`, `.github/workflows/wiki.yml`

## Generated tables

- `make wiki-build` fills the regions between GENERATED markers in a copy under `build/wiki/` (the repo keeps them empty). Source: `tools/wiki/manifest.lua`, `tools/wiki/gen.lua`

## wiki-check

- Part of `make check`. Source: `tools/wiki/check.lua`

## See also

- [Style guide](Style-Guide)
