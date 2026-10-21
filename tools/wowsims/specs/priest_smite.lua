-- tools/wowsims/specs/priest_smite.lua (wowsims packs plan, Task 14): Smite (wowsims.com)'s wowsims/forever request
-- and translation (on the Discipline tree, owner ruling P4).
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever)
-- ui/specs/priest/dps/builds/smite_testing.build.json (the Smite Testing build: Undead, talents
-- 525235031030001001-30515100002-3, Discipline 31; its rotation presets.ts:13 ROTATION_SMITE_DEFAULT) at the pin. The
-- request takes the build's `player` whole (race, gear, consumables, options, reaction 100 ms, 20 yd).
-- Disagreements (P7; floor 0.93), decisions on-GCD 0.932 (44) top [holy_fire -> smite 3] (the only class):
--   holy_fire -> smite (log 48.9, 51.9, 54.9): shared gap "cast a specific rank" (owner ruling 1 on the kit task):
--   below 20% mana wowsims casts Holy Fire rank 5 (15265) while its own rank-5 DoT is down (`dotIsActive` of that
--   rank); with rank 8's DoT still up the rank-5 casts land without a DoT, so it casts three in a row. The translator
--   ignores `rank` (rule 5): the line reads `holy_fire` and its top-rank DoT, up, so ours falls to Smite. Deviation:
--   the down-ranked Holy Fire and Smite (1004, rank 5) lines are translated at the top rank.
-- Deviations: the wand's Shoot (`shoot,if=mana.pct<=10`) is the kit's one-shot channel of a wand speed (wowsims's
-- core/wand.go; owner ruling 2: an in-game check); the log's tagged shots (5019 Tag 1) stay casts in the replay (as
-- procs the tick agreement fell 0.784 -> 0.753). Mana lines read the belief on the secret pool (`mana.pct`). Holy Nova
-- needs Holy Purpose and three targets (never in the solo fight). Penance's `spellCanCast` reads
-- `action.penance.ready`.
-- Omitted: the hidden entries (#6 Devouring Plague, #7 Shadow Word: Death, #8 Mind Blast).
-- Kit notes (owner rulings on the kit task): Power Infusion costs 247 (floor(0.18 x 1376)), wowsims 247.5 (its 20%
-- before Mental Agility); mana regen is declared from the Shadow build (one value per class; this world keeps its own
-- 35.73 / 20.12); talent max ranks at the DB2's Era values where wowsims differs.
return {
    class = "PRIEST",
    pack = "Smite (wowsims.com)",
    spec = "discipline",
    name = "Smite",
    talentTree = "priest",
    build = "ui/specs/priest/dps/builds/smite_testing.build.json",
    map = {},
    -- Ruling P5: the content focus picks (no retired list): the DoT upkeep and Inner Focus
    focus = { shadow_word_pain = 2, holy_fire = 2, inner_focus = 1 },
    leveling = {},
}
