# CDM verdict + options panel: task plan (2026-11-09, Fable lead)

Spec: `docs/superpowers/specs/2026-11-09-cdm-verdict-design.md` (decisions 116-124) and the panel decisions in
`~/src/hekili-central-needs/cdm-panel-brief.md` (binding). Base 38daebe33; branch `cdm-verdict`. Global constraints as in
`2026-11-07-cdm-default.md` (border: Drain/Build/SetLog only; secrets guarded; no allocation in recurring paths; Lua 5.1;
x/0 raises; dim never promote; no user toggles beyond the panel's per-aura switch).

| Lane | Files | Tests | Arms / gates | Review |
|---|---|---|---|---|
| 0 panel (ported from cdm-panel, reviewed) | Engine/Schema/Tracked.lua (cdmOf, Hekili:CdmSwitchChanged), Game/State/Belief.lua (cdmGen), Presence/CooldownViewer.lua build() skip, Options/Options.lua (CdmWalk, EmbedCdmOptions, `cdm` group), UI/UI.lua, Locales | tests/Forever/cdm_panel_spec.lua (6), cdm_coverage, plain_records, viewer, router | check | lead's own read; the final batch review |
| 1 leaf | Presence/CooldownViewer.lua: provenCd/provenU/strikesCd/seenCd/seenUnitCd per cooldownID (build), sDarkN per slot, cDark counters, Counts 7th value, Strike(j,u), re-point inheritance, swap handling, repoints/struck counters, NeverLit(out) | tests/Game/State/viewer_spec.lua (+ proof, dark count, re-point inheritance, settle, swap, strike), alloc_spec (0 bytes in the sweep) | check; viewer arms identical where pdark never fires | Opus read-only |
| 2 router | Presence/Router.lua: fact.pdark, R.Strike | router_spec | check | same Opus reviewer |
| 3 verdict | Sources/Auras.lua: W per key, verdictAt/verdictN/strikeN, the poll-15 rule, strikes, I.verdictOff, snapshot lines; Families/Now.lua: travel to I.AuraOurs | auras_spec (+ the scenario list of spec §2.7), now_spec (travel), cdm_engine_spec | check; gate body default arm IDENTICAL | Opus read-only |
| 4 harness | tests/Game/harness: fake_api (ViewerReshuffle), observer/world (`auraOnAvoid`, target swap knob), ab.lua arms, loop.lua (edgestats on the new arms, I.verdictOff for `-novd`), scenarios | harness specs (fake_viewer_spec, loop_spec) | the new arms recorded; no default-arm change | Sonnet/Opus read-only |
| 5 pack audit | src/Hekili_*/ aura rank tables; tests/Forever/cdm_ranks_spec.lua | the spec test | check | report |
| 6 A/B | none | — | `make -i gate-ab` on head and on the 38daebe33 worktree; `scripts/results.sh` | lead |
| 7 ForeverProbe | ~/src/ForeverProbe-wt-cdm-verdict: DruidSession stages P1 (latency tail), P3 (reshuffle), P2 (resist rows), partner filter | wow_lua_lint | local branch only | lead |
| 8 docs/report | this plan, the spec, cdm-fable-report.md | — | — | Fable batch review (controller) |

Amended 2026-11-10 (the Fable 5.2 review's fix lanes and the batch review; the spec is the authority where this table
differs): lane 0's panel is ONE grid with no groups (owner 2026-11-09) and its cards pass AceConfig's validation; lane
1 has no `seenCd`/`seenUnitCd`, no `sDarkN` and no re-point inheritance: per slot `sDarkT` (the start of the watched
dark), per thing `tDark`, per cooldownID `silentCd` (silent verdicts suspend a proof) and `builds`; lane 2 carries
`fact.pdarkT` and `R.Silent`; lane 3's close is the read kind `ReadOf.AuraVerdict` naming its application, verdicts are
counted at the fold, the strike test is `oursAp >= verdictAt`; lane 4 adds `viewer-late`, `viewer-recast`,
`viewer-swap-dark` (+`-novd`), edgestats without forms, `gate-body` / `gate-ab-body`, `scripts/ab_delta.sh`; lane 6 is
`make gate-ab-body` on the head, the six arms' bodies on the base, then `scripts/ab_delta.sh`. Acceptance: spec §5.

Acceptance (ship): default arm identical to 38daebe33; viewer arms flicker within +-0.3/min and agreement no regression;
`viewer-nonland` phantom seconds lower with the verdict on than `-novd`; strikes per fight <= 2 per item in every arm;
`make check` at 3555+new ok / 1 failure / 1 error (known); border rc 0; alloc specs 0 bytes.

Task 10 (owner, in game) gains: P1 latency tail (n >= 300, 99th percentile), P3 what a re-pointed frame reads in the swap
frames and how often frames re-point, P2 RESIST row shape, P4 partner filter (one run), `presence-verdict` /
`presence-proof` snapshot lines after three pulls, the options panel look (gold/grey, one grid, Reset, states).
