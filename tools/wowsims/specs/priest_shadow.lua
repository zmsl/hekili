-- tools/wowsims/specs/priest_shadow.lua (wowsims packs plan, Task 14): Shadow (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/priest/dps/builds/testing.build.json
-- (the Shadow Testing build: Human, talents 00530320103--50052201251302051, its rotation the spec's default,
-- presets.ts:12 ROTATION_PRESET_DEFAULT) at the pin. The request takes the build's `player` whole (race, gear,
-- consumables, options, reaction 100 ms, channel clip delay 100 ms, 20 yd); its raid buffs and debuffs are not sent.
-- Disagreements (P7; floor 1.00), first run decisions on-GCD 0.859 (85) top [mind_flay -> shadow_word_death 5;
-- devouring_plague -> mind_blast 3; devouring_plague -> mind_flay 2] (and devouring_plague -> shadow_word_death 2):
--   all kit: wowsims's spell data (build 70450) gives Devouring Plague a 24 s and Shadow Word: Death an 18 s category
--   cooldown, the DB2 at 70338 60 s and 15 s; the log recasts Devouring Plague 24.5-26 s apart (log 3.0, 29.0, 55.0,
--   79.5) and Shadow Word: Death 18.3 s apart at the least (wowsims casts Mind Flay at log 39.7, 16.8 s after the 22.9
--   one, where our 15 s read it ready). Fixed in Priest.lua (the Mage lane's ruling M9 precedent: wowsims's newer data
--   where its log casts it; in-game checks): decisions on-GCD 1.000 (85), no disagreement left.
-- Worked (P8): Smite fills below Mind Flay (a talent: the L10 bracket idled 8.0 s on Mind Blast's cooldown); the world's
-- Shadow character knows Smite (P9.4), silent at 60.
-- Deviations: Mind Flay's channelSpell.interruptIf (MF3: clip at its third tick) is dropped by the translator (the
-- Mage lane's shared gap); with three ticks to a channel it is the channel's own end, so no decision moves (1.000).
-- The Dark Sac variable reads `mana.current<=2000` (absolute, as wowsims): the belief answers its floor on the secret
-- pool; the line is for an Undead build (Dark Sacrifice is the Undead's), never this Human one. The replay's mana belief
-- runs about 1000 under the truth after the Demonic Rune and Major Mana Potion (rule 13 lines; the replay emits no cast
-- for an item's use: the Mage lane's shared gap); no decision reads it here.
-- Omitted: the hidden entries (#10 Vampiric Embrace, #11 Starshards on its expected damage, #12 the Inner Focus ->
-- Starshards sequence); the Major Spellblasting Potion (item 250937, rule 13: no such consumable in Hekili_Shared; a
-- potion under Potions, off). Race lines: the Troll's pre-pull Shadowguard (`action.shadowguard.known`), the Night Elf's
-- Elune's Light and the Gnome's Eureka! (wowsims's variables, `time=3|time>=N|known`), the Undead's Dark Sacrifice: each
-- silent for another race (the engine skips an unknown action). The Cooldowns group is empty and unread (no setting).
-- Kit notes (owner rulings on the kit task): mana regen is declared from this build's log (one value per class: the
-- Smite world keeps its own); talent max ranks stay at the DB2's Era values where wowsims differs (per-rank lookups
-- clamp to wowsims's last value).
return {
    class = "PRIEST",
    pack = "Shadow (wowsims.com)",
    spec = "shadow",
    name = "Shadow",
    talentTree = "priest",
    build = "ui/specs/priest/dps/builds/testing.build.json",
    map = { ["item:272438"] = "use_items" }, -- the Weakness Analyzer (ItemSparse 272438: a trinket, InventoryType 12)
    -- Ruling P5: the content focus picks (no retired list): the DoT upkeep and Inner Focus
    focus = { shadow_word_pain = 2, devouring_plague = 2, inner_focus = 1 },
    -- before Mind Flay (a Shadow talent): Smite fills while Mind Blast and the DoTs wait; silent once Mind Flay is known,
    -- and so at 60
    leveling = { "smite,if=!action.mind_flay.known" },
}
