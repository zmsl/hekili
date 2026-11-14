<!--
Purpose: Clone, bootstrap, make check, branch, changelog line, translations.
Type: How-to
Audience: contributors
Prerequisites: Git, a Linux shell (WSL on Windows).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Clone, bootstrap, make check, branch, changelog line, translations.

## Clone and bootstrap

- `mise install`, `make bootstrap`, `make check`. Source: `DEVELOPMENT.md` (Clone and bootstrap)

## Make a change

- Branch from `forever`; a failing test first. Source: `DEVELOPMENT.md` (Review and merge)

## Changelog and translations

- One CHANGELOG line under Unreleased per player-visible change; `L["..."]` and `tools/locales.py`. Source: `DEVELOPMENT.md` (section 7)

## Docs

- Wiki pages live in `docs/wiki/` and change in the same commit. See [Contributing docs](Contributing-Docs).

## See also

- [Contributing architecture](Contributing-Architecture)
- [Style guide](Style-Guide)
