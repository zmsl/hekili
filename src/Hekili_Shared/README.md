Hekili's Forever content, as separate addons beside the core (`src/Hekili/`): this one, `Hekili_Shared` (the shared
auras, consumables and items, and the race packs; always loaded after the core), and one load-on-demand class pack per
class, `src/Hekili_<Class>/` (the core's `Engine/Content.lua` loads the player's at login). Content reaches the
engine only through the public `Hekili` object: the registration API, `Hekili.State`, `Hekili.Class` and
`Hekili.Client` (the game client), plus the belief's `knownRank`, `stat`, `swingBase` and `healthMax` in its functions'
environments (`tests/boundary_spec.lua` checks it). See `docs/dev/layout.md`.
