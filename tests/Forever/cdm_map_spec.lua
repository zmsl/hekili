-- tests/Forever/cdm_map_spec.lua: every Cooldown Manager entry of the owner's live export (tests/Forever/fixtures/cdm,
-- tools/cdm_fixtures.lua) against its class pack, the way the belief maps it. Each class boots headless (the real
-- Tracked def: the class pack, Hekili_Shared and the character's race pack), the fake C_CooldownViewer answers the
-- fixture (every entry as unlearned, GetOverrideSpell from the export's own read), and the leaf's real build
-- (Presence/CooldownViewer.lua build/candidates) makes the map: its verdict is the classification. This spec's own walk
-- (`walk`, mirroring candidates()) only names what an entry hit, for the messages.
-- Kinds: mapped (one aura), ambiguous (several auras, or one aura and an ID no aura has), ability-only (no aura, but a
-- pack ability's ID), unmapped (neither), spell-less (no spell ID at all: the client's category 5-8 placeholders).
-- Every ambiguous and unmapped entry must be in GAPS below with a reason; one that is not fails, and so does a GAPS line
-- whose entry is no longer ambiguous or unmapped (delete the line: the list shrinks as the coverage lanes land).
-- The same export's talent tree (fixture `talents`) against the pack's RegisterTalents (the def's talents: key, spell,
-- max), matched by spell ID, else by name as a key: every live talent the pack lacks, every pack talent absent live,
-- and every spell-ID or max-rank difference must be in TALENT_GAPS, under the same shrinking-list rule.
-- A failure prints the missing lines ready to paste.
local headless = require("Game.harness.headless")

-- token, classID and the client's pseudo-spec (the class world helpers' M.CLASS_ID, M.CLIENT_SPEC), the race token:
-- not in the export, read off its racial entries (War Stomp 20549 Tauren, Blood Fury 20572 Orc, Will of the Forsaken
-- 7744 Scourge, Berserking 20554 Troll)
local CLASSES = {
    { "DRUID", 11, 1483, "Tauren" },
    { "HUNTER", 3, 1484, "Orc" },
    { "MAGE", 8, 1485, "Scourge" },
    { "PALADIN", 2, 1486, "Scourge" },
    { "PRIEST", 5, 1487, "Scourge" },
    { "ROGUE", 4, 1488, "Scourge" },
    { "SHAMAN", 7, 1489, "Troll" },
    { "WARLOCK", 9, 1490, "Scourge" },
    { "WARRIOR", 1, 1491, "Tauren" },
}

-- [cooldownID] = { entry name, why it is a gap / the lane expected to close it }
-- stylua: ignore
local GAPS = {
    DRUID = {
        [199490] = { "Wild Growth", "unmapped, cat 0; no aura has any of 408120,1238214,1238215; lane cov-druid" },
        [199487] = { "Swiftmend", "unmapped, cat 0; no aura has any of 18562; lane cov-druid" },
        [199525] = { "Feral Charge", "ambiguous, cat 1; auras feral_charge_effect; no aura has 414923; lane cov-druid" },
        [199383] = { "Frenzied Regeneration", "unmapped, cat 1; no aura has any of 22845; lane cov-druid" },
        [199427] = { "Tranquility", "unmapped, cat 1; no aura has any of 740; lane cov-druid" },
        [199402] = { "Rebirth", "unmapped, cat 1; no aura has any of 20484,20739,20742,20747,20748; lane cov-druid" },
        [199505] = { "Improved Starfire", "unmapped, cat 2; no aura has any of 16922; lane cov-druid" },
        [199447] = { "Hibernate", "unmapped, cat 2; no aura has any of 2637,18657,18658; lane cov-druid" },
        [199471] = { "Soothe Animal", "unmapped, cat 2; no aura has any of 2908,8955,9901; lane cov-druid" },
        [199384] = { "Frenzied Regeneration", "unmapped, cat 2; no aura has any of 22845; lane cov-druid" },
        [199510] = { "Feral Charge", "ambiguous, cat 2; auras feral_charge_effect; no aura has 414923; lane cov-druid" },
        [199364] = { "Bash", "ambiguous, cat 2; auras bash; abilities bash; no aura has 1324487,1324488,1324490; lane cov-druid" },
        [199392] = { "Abolish Poison", "unmapped, cat 2; no aura has any of 2893; lane cov-druid" },
        [199395] = { "Mark of the Wild", "ambiguous, cat 2; auras mark_of_the_wild,gift_of_the_wild; abilities mark_of_the_wild,gift_of_the_wild; no aura has 5287; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [199491] = { "Wild Growth", "unmapped, cat 2; no aura has any of 1238215,1238214,408120; lane cov-druid" },
        [199431] = { "Tranquility", "unmapped, cat 2; no aura has any of 740,8918,9862,9863; lane cov-druid" },
        [199507] = { "Druid Forms", "ambiguous, cat 2; auras bear_form,cat_form,aquatic_form,travel_form,moonkin_form; abilities bear_form,cat_form,aquatic_form,travel_form,moonkin_form; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [199509] = { "Leader of the Pack", "unmapped, cat 2; no aura has any of 24932; lane cov-druid" },
        [200451] = { "Moonkin Aura", "unmapped, cat 2; no aura has any of 24907; lane cov-druid" },
        [200174] = { "Plainsrunning", "unmapped, cat 2; no aura has any of 1259918; lane shared races (Tauren.lua: a passive, no aura registered)" },
        [200257] = { "Transformative Cocoon", "unmapped, cat 7; no aura has any of 1301167; lane unassigned (category 7, not a class-pack spell)" },
        [200258] = { "Satchel of Potions", "unmapped, cat 7; no aura has any of 1309685; lane unassigned (category 7, not a class-pack spell)" },
    },
    HUNTER = {
        [200397] = { "Sniper Shot", "ambiguous, cat 0; auras sniper_shot; abilities sniper_shot; no aura has 1310687,1310785; lane cov-hunter" },
        [200402] = { "Explosive Trap", "unmapped, cat 0; no aura has any of 13813,14316,14317; lane cov-hunter" },
        [200421] = { "Scorpid Sting", "unmapped, cat 1; no aura has any of 3043; lane cov-hunter" },
        [200419] = { "Viper Sting", "unmapped, cat 1; no aura has any of 3034,14279,14280; lane cov-hunter" },
        [200390] = { "Concussive Shot", "unmapped, cat 1; no aura has any of 5116; lane cov-hunter" },
        [200359] = { "Scatter Shot", "unmapped, cat 1; no aura has any of 19503; lane cov-hunter" },
        [200404] = { "Freezing Trap", "unmapped, cat 1; no aura has any of 1324500,1324501,1324502,3355,14308,14309; lane cov-hunter" },
        [200407] = { "Frost Trap", "unmapped, cat 1; no aura has any of 13810; lane cov-hunter" },
        [200351] = { "Intimidation", "unmapped, cat 1; no aura has any of 19577; lane cov-hunter" },
        [200399] = { "Counterattack", "unmapped, cat 1; no aura has any of 19306,1242634,20909,20910; lane cov-hunter" },
        [200401] = { "Disengage", "unmapped, cat 1; no aura has any of 781,14272,14273; lane cov-hunter" },
        [200392] = { "Distracting Shot", "unmapped, cat 1; no aura has any of 20736,14274,15629,15630,15631,15632; lane cov-hunter" },
        [200403] = { "Feign Death", "unmapped, cat 1; no aura has any of 5384; lane cov-hunter" },
        [200413] = { "Deterrence", "unmapped, cat 1; no aura has any of 19263; lane cov-hunter" },
        [200522] = { "Flare", "unmapped, cat 1; no aura has any of 1543; lane cov-hunter" },
        [200532] = { "Scare Beast", "unmapped, cat 1; no aura has any of 1513,14326,14327; lane cov-hunter" },
        [200355] = { "Deadly Aspects", "ambiguous, cat 2; auras quick_shots; no aura has 1299448; lane cov-hunter" },
        [200356] = { "Frenzy", "unmapped, cat 2; no aura has any of 19621; lane cov-hunter" },
        [200412] = { "Entrapment", "unmapped, cat 2; no aura has any of 19185; lane cov-hunter" },
        [200414] = { "Deterrence", "unmapped, cat 2; no aura has any of 19263; lane cov-hunter" },
        [200400] = { "Counterattack", "unmapped, cat 2; no aura has any of 20909,20910,1242634,19306; lane cov-hunter" },
        [200360] = { "Scatter Shot", "unmapped, cat 2; no aura has any of 1324499; lane cov-hunter" },
        [200391] = { "Concussive Shot", "unmapped, cat 2; no aura has any of 5116; lane cov-hunter" },
        [200430] = { "Improved Concussive Shot", "unmapped, cat 2; no aura has any of 1324511; lane cov-hunter" },
        [200422] = { "Scorpid Sting", "unmapped, cat 2; no aura has any of 3043; lane cov-hunter" },
        [200423] = { "Aspects", "ambiguous, cat 2; auras aspect_of_the_beast,aspect_of_the_cheetah,aspect_of_the_hawk; abilities aspect_of_the_beast,aspect_of_the_cheetah,aspect_of_the_hawk; no aura has 13163,13159,20043,20190; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [200353] = { "Scare Beast", "unmapped, cat 2; no aura has any of 1324506,1324507,1324510; lane cov-hunter" },
        [200409] = { "Immolation Trap", "ambiguous, cat 2; auras immolation_trap; no aura has 13797,14298,14299,14300; lane cov-hunter" },
        [200352] = { "Intimidation", "unmapped, cat 2; no aura has any of 1324494; lane cov-hunter" },
        [200398] = { "Sniper Shot", "ambiguous, cat 2; auras sniper_shot; abilities sniper_shot; no aura has 1310785,1310687; lane cov-hunter" },
        [200361] = { "Trueshot Aura", "unmapped, cat 2; no aura has any of 1299346,1299348,19506,20905,20906; lane cov-hunter" },
        [200420] = { "Viper Sting", "unmapped, cat 2; no aura has any of 14280,3034,14279; lane cov-hunter" },
        [200549] = { "Freezing Trap", "unmapped, cat 2; no aura has any of 1324501,14308,3355,1324500,14309,1324502; lane cov-hunter" },
    },
    MAGE = {
        [199223] = { "Cone of Cold", "unmapped, cat 0; no aura has any of 120,8492,10159,10160,10161; lane cov-mage" },
        [199188] = { "Blast Wave", "unmapped, cat 0; no aura has any of 11113,13018,13019,13020,13021; lane cov-mage" },
        [199185] = { "Blink", "unmapped, cat 1; no aura has any of 1953; lane cov-mage" },
        [199235] = { "Frost Nova", "unmapped, cat 1; no aura has any of 122,865,6131,10230; lane cov-mage" },
        [199199] = { "Fire Ward", "unmapped, cat 1; no aura has any of 543,8457,8458,10223,10225; lane cov-mage" },
        [199243] = { "Frost Ward", "unmapped, cat 1; no aura has any of 6143,8461,8462,10177,28609; lane cov-mage" },
        [199256] = { "Ice Barrier", "unmapped, cat 1; no aura has any of 11426,13031,13032,13033; lane cov-mage" },
        [199343] = { "Mana Gems", "unmapped, cat 1; no aura has any of 1318827; lane cov-mage" },
        [199253] = { "Ice Block", "unmapped, cat 1; no aura has any of 11958; lane cov-mage" },
        [199255] = { "Cold Snap", "unmapped, cat 1; no aura has any of 12472; lane cov-mage" },
        [199344] = { "Polymorph", "unmapped, cat 2; no aura has any of 1320379,1324187,1324188,1324189; lane cov-mage" },
        [199206] = { "Ignite", "unmapped, cat 2; no aura has any of 412538; lane cov-mage" },
        [199326] = { "Frostbite", "unmapped, cat 2; no aura has any of 12494; lane cov-mage" },
        [199272] = { "Winter's Chill", "unmapped, cat 2; no aura has any of 12579; lane cov-mage" },
        [199330] = { "Improved Counterspell", "unmapped, cat 2; no aura has any of 1324401,1329553; lane cov-mage" },
        [199324] = { "Impact", "unmapped, cat 2; no aura has any of 12355; lane cov-mage" },
        [199325] = { "Improved Blizzard", "unmapped, cat 2; no aura has any of 12484; lane cov-mage" },
        [199269] = { "Chilled", "unmapped, cat 2; no aura has any of 6136; lane cov-mage" },
        [199254] = { "Ice Block", "unmapped, cat 2; no aura has any of 11958; lane cov-mage" },
        [200533] = { "Frost Blast", "unmapped, cat 2; no aura has any of 1326053,1326054,1326055; lane cov-mage" },
        [199228] = { "Cone of Cold", "unmapped, cat 2; no aura has any of 8492,10159,10160,10161,120; lane cov-mage" },
        [199239] = { "Frost Nova", "unmapped, cat 2; no aura has any of 865,6131,10230,122; lane cov-mage" },
        [199248] = { "Frost Ward", "unmapped, cat 2; no aura has any of 8461,8462,10177,28609,6143; lane cov-mage" },
        [199260] = { "Ice Barrier", "unmapped, cat 2; no aura has any of 13031,13032,13033,11426; lane cov-mage" },
        [199212] = { "Fire Ward", "unmapped, cat 2; no aura has any of 8457,8458,10223,10225,543; lane cov-mage" },
        [199207] = { "Blast Wave", "unmapped, cat 2; no aura has any of 13018,13019,13020,13021,11113; lane cov-mage" },
        [199349] = { "Arcane Intellect", "unmapped, cat 2; no aura has any of 1460,1461,10156,10157,23028,1459; lane cov-mage" },
        [199354] = { "Dampen Magic", "unmapped, cat 2; no aura has any of 8450,8451,10173,10174,604; lane cov-mage" },
        [199359] = { "Amplify Magic", "unmapped, cat 2; no aura has any of 8455,10169,10170,1008; lane cov-mage" },
        [199291] = { "Mana Shield", "unmapped, cat 2; no aura has any of 8494,8495,10191,10192,10193,1463; lane cov-mage" },
    },
    PALADIN = {
        [200339] = { "Seals", "ambiguous, cat 0; auras seal_of_the_crusader,seal_of_righteousness,seal_of_justice,seal_of_wisdom,seal_of_light,seal_of_command,seal_of_fury; abilities seal_of_the_crusader,seal_of_righteousness,seal_of_justice,seal_of_wisdom,seal_of_light,seal_of_command,seal_of_fury; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [200307] = { "Light's Vigil", "unmapped, cat 0; no aura has any of 1310911,1311590,1311595; lane cov-paladin" },
        [200303] = { "Holy Wrath", "unmapped, cat 0; no aura has any of 2812,10318; lane cov-paladin" },
        [200274] = { "Blessing of Freedom", "unmapped, cat 1; no aura has any of 1044; lane cov-paladin" },
        [200306] = { "Turn Undead", "unmapped, cat 1; no aura has any of 10326,2878,5627; lane cov-paladin" },
        [200287] = { "Hammer of Justice", "unmapped, cat 1; no aura has any of 853,5588,5589,10308; lane cov-paladin" },
        [200267] = { "Repentance", "unmapped, cat 1; no aura has any of 20066; lane cov-paladin" },
        [200278] = { "Blessing of Sacrifice", "unmapped, cat 1; no aura has any of 6940,20729; lane cov-paladin" },
        [200276] = { "Blessing of Protection", "unmapped, cat 1; no aura has any of 1022,10278,5599; lane cov-paladin" },
        [200284] = { "Divine Protection", "unmapped, cat 1; no aura has any of 498,642,5573,1020; lane cov-paladin" },
        [200304] = { "Lay on Hands", "unmapped, cat 1; no aura has any of 633,2800,10310; lane cov-paladin" },
        [200282] = { "Divine Intervention", "unmapped, cat 1; no aura has any of 19752; lane cov-paladin" },
        [200341] = { "Unsealed Wrath", "ambiguous, cat 2; auras echo_of_fury,echo_of_command,echo_of_righteousness,echo_of_justice,echo_of_light,echo_of_wisdom; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [200383] = { "Iron Creed", "unmapped, cat 2; no aura has any of 440668; lane cov-paladin" },
        [200268] = { "Repentance", "unmapped, cat 2; no aura has any of 1324538; lane cov-paladin" },
        [200388] = { "Redoubt", "ambiguous, cat 2; auras redoubt; no aura has 20127; lane cov-paladin" },
        [200291] = { "Reckoning", "ambiguous, cat 2; auras reckoning; no aura has 20177; lane cov-paladin" },
        [200288] = { "Hammer of Justice", "unmapped, cat 2; no aura has any of 1324513,1324515,1324516,1324517; lane cov-paladin" },
        [200305] = { "Turn Undead", "unmapped, cat 2; no aura has any of 1324543,1324545,1324546; lane cov-paladin" },
        [200340] = { "Seals", "ambiguous, cat 2; auras seal_of_righteousness,seal_of_fury,seal_of_the_crusader,seal_of_command,seal_of_light,seal_of_wisdom,seal_of_justice; abilities seal_of_righteousness,seal_of_fury,seal_of_the_crusader,seal_of_command,seal_of_light,seal_of_wisdom,seal_of_justice; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [200272] = { "Blessing of Freedom", "unmapped, cat 2; no aura has any of 1044; lane cov-paladin" },
        [200277] = { "Blessing of Sacrifice", "unmapped, cat 2; no aura has any of 6940,20729; lane cov-paladin" },
        [200275] = { "Blessing of Protection", "unmapped, cat 2; no aura has any of 1022,5599,10278; lane cov-paladin" },
        [200283] = { "Divine Protection", "unmapped, cat 2; no aura has any of 498,5573,642,1020; lane cov-paladin" },
    },
    PRIEST = {
        [199885] = { "Prayer of Mending", "unmapped, cat 0; no aura has any of 401877,1240848,1240849,401859,1240826,1240827; lane cov-priest" },
        [200048] = { "Shackle Undead", "unmapped, cat 1; no aura has any of 9484,9485,10955; lane cov-priest" },
        [199972] = { "Psychic Scream", "unmapped, cat 1; no aura has any of 8122,8124,10888,10890; lane cov-priest" },
        [200001] = { "Silence", "unmapped, cat 1; no aura has any of 15487; lane cov-priest" },
        [199883] = { "Fear Ward", "unmapped, cat 1; no aura has any of 6346; lane cov-priest" },
        [200022] = { "Power Word: Fortitude", "ambiguous, cat 2; auras power_word_fortitude; no aura has 21562,21564; lane cov-priest" },
        [199882] = { "Abolish Disease", "unmapped, cat 2; no aura has any of 552; lane cov-priest" },
        [199884] = { "Fear Ward", "unmapped, cat 2; no aura has any of 6346; lane cov-priest" },
        [199926] = { "Blessed Recovery", "unmapped, cat 2; no aura has any of 27811,27813; lane cov-priest" },
        [199927] = { "Inspiration", "unmapped, cat 2; no aura has any of 14892,14893; lane cov-priest" },
        [199929] = { "Holy Purpose", "ambiguous, cat 2; auras holy_purpose; no aura has 14909; lane cov-priest" },
        [199928] = { "Spirit of Redemption", "unmapped, cat 2; no aura has any of 27827,20711; lane cov-priest" },
        [199996] = { "Blackout", "unmapped, cat 2; no aura has any of 15326,15269; lane cov-priest" },
        [199997] = { "Spirit Tap", "ambiguous, cat 2; auras spirit_tap; no aura has 15270; lane cov-priest" },
        [200000] = { "Shadow Weaving", "ambiguous, cat 2; auras shadow_weaving; no aura has 15257; lane cov-priest" },
        [200002] = { "Silence", "unmapped, cat 2; no aura has any of 1324427; lane cov-priest" },
        [200060] = { "Martyrdom", "unmapped, cat 2; no aura has any of 27828; lane cov-priest" },
        [200058] = { "Divine Aegis", "ambiguous, cat 2; auras divine_aegis; no aura has 431622; lane cov-priest" },
        [199888] = { "Prayer of Mending", "unmapped, cat 2; no aura has any of 401877,1240849,1240848; lane cov-priest" },
        [199966] = { "Mind Soothe", "unmapped, cat 2; no aura has any of 453,8192,10953; lane cov-priest" },
        [199969] = { "Shadow Protection", "unmapped, cat 2; no aura has any of 976,10957,10958,27683; lane cov-priest" },
        [199976] = { "Psychic Scream", "unmapped, cat 2; no aura has any of 8122,10890,8124,10888; lane cov-priest" },
        [200008] = { "Divine Spirit", "unmapped, cat 2; no aura has any of 14752,14818,14819,27841,27681; lane cov-priest" },
        [200051] = { "Shackle Undead", "unmapped, cat 2; no aura has any of 1324415,1324420,1324422; lane cov-priest" },
        [200213] = { "Touch of Weakness", "unmapped, cat 2; no aura has any of 19252,2943,19254,19253,19249,19251; lane cov-priest" },
    },
    ROGUE = {
        [200225] = { "Sprint", "unmapped, cat 1; no aura has any of 2983,8696,11305; lane cov-rogue" },
        [200228] = { "Blind", "unmapped, cat 1; no aura has any of 2094; lane cov-rogue" },
        [200222] = { "Gouge", "unmapped, cat 1; no aura has any of 1776,1777,8629,11285,11286; lane cov-rogue" },
        [200256] = { "Kidney Shot", "unmapped, cat 1; no aura has any of 408,8643; lane cov-rogue" },
        [200220] = { "Feint", "unmapped, cat 1; no aura has any of 1966,6768,8637,11303,25302; lane cov-rogue" },
        [200217] = { "Evasion", "unmapped, cat 1; no aura has any of 5277; lane cov-rogue" },
        [200234] = { "Vanish", "ambiguous, cat 1; auras vanish; abilities vanish; no aura has 1856,1857; lane cov-rogue" },
        [200230] = { "Distract", "unmapped, cat 1; no aura has any of 1725; lane cov-rogue" },
        [200218] = { "Evasion", "unmapped, cat 2; no aura has any of 5277; lane cov-rogue" },
        [200364] = { "Silenced - Kick", "unmapped, cat 2; no aura has any of 1324485; lane cov-rogue" },
        [200229] = { "Blind", "unmapped, cat 2; no aura has any of 1324477; lane cov-rogue" },
        [200231] = { "Distract", "unmapped, cat 2; no aura has any of 1725; lane cov-rogue" },
        [200241] = { "Cheap Shot", "unmapped, cat 2; no aura has any of 1833; lane cov-rogue" },
        [200250] = { "Remorseless Attacks", "ambiguous, cat 2; auras remorseless; no aura has 14144; lane cov-rogue" },
        [200221] = { "Feint", "unmapped, cat 2; no aura has any of 11303,6768,8637,1966,25302; lane cov-rogue" },
        [200223] = { "Gouge", "unmapped, cat 2; no aura has any of 1324481; lane cov-rogue" },
        [200255] = { "Sprint", "unmapped, cat 2; no aura has any of 11305,2983,8696; lane cov-rogue" },
        [200235] = { "Vanish", "ambiguous, cat 2; auras vanish; abilities vanish; no aura has 1857,1856; lane cov-rogue" },
        [200232] = { "Sap", "unmapped, cat 2; no aura has any of 1324482,1324483,1324484; lane cov-rogue" },
        [200243] = { "Kidney Shot", "unmapped, cat 2; no aura has any of 1324474,1324475; lane cov-rogue" },
    },
    SHAMAN = {
        [200315] = { "Stormstrike", "unmapped, cat 0; no aura has any of 410156; lane cov-shaman" },
        [200325] = { "Frost Shock", "unmapped, cat 0; no aura has any of 8056,8058,10472,10473; lane cov-shaman" },
        [200330] = { "Lava Burst", "unmapped, cat 0; no aura has any of 408490,1238299,1238300; lane cov-shaman" },
        [200332] = { "Riptide", "unmapped, cat 0; no aura has any of 408521,1239242,1239243; lane cov-shaman" },
        [200480] = { "Flametongue Totem", "ambiguous, cat 0; auras flametongue; abilities flametongue_totem; no aura has 8227,8249,10526,16387; lane cov-shaman" },
        [200482] = { "Grace of Air Totem", "ambiguous, cat 0; auras grace_of_air; abilities grace_of_air_totem; no aura has 8835,10627,25359; lane cov-shaman" },
        [200484] = { "Strength of Earth Totem", "ambiguous, cat 0; auras strength_of_earth; abilities strength_of_earth_totem; no aura has 8075,8160,8161,10442,25361; lane cov-shaman" },
        [200485] = { "Windfury Totem", "ambiguous, cat 0; auras windfury; abilities windfury_totem; no aura has 8512,10613,10614; lane cov-shaman" },
        [200334] = { "?", "unmapped, cat 1; no aura has any of 52127; lane cov-shaman" },
        [200501] = { "Totemic Call", "unmapped, cat 1; no aura has any of 437009; lane cov-shaman" },
        [200479] = { "Fire Resistance", "ambiguous, cat 1; auras fire_resistance; abilities fire_resistance_totem; no aura has 8184,10537,10538; lane cov-shaman" },
        [200481] = { "Frost Resistance Totem", "ambiguous, cat 1; auras frost_resistance; abilities frost_resistance_totem; no aura has 8181,10478,10479; lane cov-shaman" },
        [200483] = { "Grounding Totem", "unmapped, cat 1; no aura has any of 8178,8179; lane cov-shaman" },
        [200486] = { "Windwall Totem", "ambiguous, cat 1; auras windwall; abilities windwall_totem; no aura has 15107,15111,15112; lane cov-shaman" },
        [200488] = { "Mana Spring Totem", "ambiguous, cat 1; auras mana_spring; abilities mana_spring_totem; no aura has 5678,10495,10496,10497; lane cov-shaman" },
        [200506] = { "Mana Tide", "ambiguous, cat 1; auras mana_tide; abilities mana_tide_totem; no aura has 16190,17354,17359,1325256; lane cov-shaman" },
        [200503] = { "Elemental Devastation", "ambiguous, cat 2; auras elemental_devastation; no aura has 30160; lane cov-shaman" },
        [200521] = { "Earthbound", "unmapped, cat 2; no aura has any of 1238289; lane cov-shaman" },
        [200264] = { "Ghost Wolf", "unmapped, cat 2; no aura has any of 2645,1238640; lane cov-shaman" },
        [200320] = { "Improved Stormstrike", "unmapped, cat 2; no aura has any of 1223031; lane cov-shaman" },
        [200321] = { "Flurry", "unmapped, cat 2; no aura has any of 16256; lane cov-shaman" },
        [200328] = { "Frost Shock", "unmapped, cat 2; no aura has any of 8056,10472,10473,8058; lane cov-shaman" },
        [200333] = { "Riptide", "unmapped, cat 2; no aura has any of 408521,1239242,1239243; lane cov-shaman" },
        [200338] = { "Ancestral Healing", "unmapped, cat 2; no aura has any of 16177; lane cov-shaman" },
        [200491] = { "Mana Spring Totem", "ambiguous, cat 2; auras mana_spring; abilities mana_spring_totem; no aura has 10495,5678,10496,10497; lane cov-shaman" },
        [200492] = { "Windwall", "ambiguous, cat 2; auras windwall; abilities windwall_totem; no aura has 15107,15111,15112; lane cov-shaman" },
        [200493] = { "Grounding Totem", "unmapped, cat 2; no aura has any of 8179,8178; lane cov-shaman" },
        [200494] = { "Frost Resistance", "ambiguous, cat 2; auras frost_resistance; abilities frost_resistance_totem; no aura has 8181,10478,10479; lane cov-shaman" },
        [200495] = { "Fire Resistance Totem", "ambiguous, cat 2; auras fire_resistance; abilities fire_resistance_totem; no aura has 10538,10537,8184; lane cov-shaman" },
        [200497] = { "Windfury Totem", "ambiguous, cat 2; auras windfury; abilities windfury_totem; no aura has 8512,10614,10613; lane cov-shaman" },
        [200498] = { "Strength of Earth", "ambiguous, cat 2; auras strength_of_earth; abilities strength_of_earth_totem; no aura has 8160,10442,8161,25361,8075; lane cov-shaman" },
        [200499] = { "Grace of Air", "ambiguous, cat 2; auras grace_of_air; abilities grace_of_air_totem; no aura has 25359,8835,10627; lane cov-shaman" },
        [200500] = { "Flametongue Totem", "ambiguous, cat 2; auras flametongue; abilities flametongue_totem; no aura has 16387,8249,10526,8227; lane cov-shaman" },
        [200507] = { "Mana Tide", "ambiguous, cat 2; auras mana_tide; abilities mana_tide_totem; no aura has 17359,16190,1325256,17354; lane cov-shaman" },
    },
    WARLOCK = {
        [200525] = { "Bane of Havoc", "unmapped, cat 0; no aura has any of 1324473; lane cov-warlock" },
        [199871] = { "Curses", "ambiguous, cat 0; auras curse_of_the_elements,curse_of_recklessness,curse_of_weakness; abilities curse_of_the_elements,curse_of_recklessness,curse_of_weakness; no aura has 11719,1714,18223; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [199787] = { "Howl of Terror", "unmapped, cat 1; no aura has any of 5484,17928; lane cov-warlock" },
        [199743] = { "Shadow Ward", "unmapped, cat 1; no aura has any of 11739,6229,11740; lane cov-warlock" },
        [199739] = { "Inferno", "unmapped, cat 1; no aura has any of 1122; lane cov-warlock" },
        [199719] = { "Healthstone", "unmapped, cat 1; no aura has any of 6262,6263,5720,5723,11732; lane cov-warlock" },
        [199724] = { "Soulstone Resurrection", "unmapped, cat 1; no aura has any of 20707,20762,20763,20764,20765; lane cov-warlock" },
        [199776] = { "Curses", "ambiguous, cat 2; auras curse_of_recklessness,curse_of_the_elements,curse_of_weakness; abilities curse_of_recklessness,curse_of_the_elements,curse_of_weakness; no aura has 18223,1714,11719; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [199817] = { "Soul Harvest", "ambiguous, cat 2; auras soul_harvest; no aura has 437032; lane cov-warlock" },
        [199820] = { "Nightfall", "ambiguous, cat 2; auras shadow_trance; no aura has 18094; lane cov-warlock" },
        [199824] = { "Aftermath", "unmapped, cat 2; no aura has any of 18119,18118; lane cov-warlock" },
        [199822] = { "Decimation", "unmapped, cat 2; no aura has any of 440870; lane cov-warlock" },
        [199821] = { "Demonic Sacrifice", "ambiguous, cat 2; auras fel_energy,burning_shadow,fel_stamina,touch_of_fire; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [199784] = { "Fear", "unmapped, cat 2; no aura has any of 1324448,1324451,1324453; lane cov-warlock" },
        [199789] = { "Howl of Terror", "unmapped, cat 2; no aura has any of 17928,5484; lane cov-warlock" },
        [199783] = { "Death Coil", "unmapped, cat 2; no aura has any of 1324459; lane cov-warlock" },
        [199717] = { "Banish", "unmapped, cat 2; no aura has any of 1324462,1324463; lane cov-warlock" },
        [199729] = { "Demon Skin", "unmapped, cat 2; no aura has any of 687,696; lane cov-warlock" },
        [199731] = { "Demon Armor", "ambiguous, cat 2; auras demon_armor; no aura has 706,1086,11733,11734; lane cov-warlock" },
        [199736] = { "Detect Invisibility", "unmapped, cat 2; no aura has any of 132,2970,11743; lane cov-warlock" },
        [199740] = { "Shadow Ward", "unmapped, cat 2; no aura has any of 6229,11739,11740; lane cov-warlock" },
        [200427] = { "Subjugate Demon", "unmapped, cat 2; no aura has any of 1324468; lane cov-warlock" },
        [200428] = { "Bane of Havoc", "unmapped, cat 2; no aura has any of 1324473; lane cov-warlock" },
    },
    WARRIOR = {
        [199695] = { "Bloodthrill", "unmapped, cat 2; no aura has any of 1289681; lane cov-warrior" },
        [199667] = { "Disarm", "unmapped, cat 2; no aura has any of 1324558; lane cov-warrior" },
        [199699] = { "Concussion Blow", "unmapped, cat 2; no aura has any of 1324556; lane cov-warrior" },
        [199677] = { "Improved Shield Bash", "unmapped, cat 2; no aura has any of 1324551; lane cov-warrior" },
        [199716] = { "Stances", "ambiguous, cat 2; auras battle_stance,defensive_stance,berserker_stance; abilities battle_stance,defensive_stance,berserker_stance; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [200174] = { "Plainsrunning", "unmapped, cat 2; no aura has any of 1259918; lane shared races (Tauren.lua: a passive, no aura registered)" },
    },
}

-- [live spellID] (live-only, spell ID differs, max ranks differ) or ["pack key"] (pack-only) = { name, why / lane }
-- stylua: ignore
local TALENT_GAPS = {
    DRUID = {},
    HUNTER = {
        [19464] = { "Improved Serpent Sting", "live-only (node 105003, max 5); lane cov-hunter (node off the visible tree: posY 39300)" },
    },
    MAGE = {},
    PALADIN = {},
    PRIEST = {},
    ROGUE = {},
    SHAMAN = {},
    WARLOCK = {},
    WARRIOR = {},
}

-- The entry's candidate IDs (CooldownViewer.lua candidates(): the links when any, else spellID, overrideSpellID and
-- overrideTooltipSpellID, each also through GetOverrideSpell; the export read that for spellID only).
local function candidateIds(e)
    local ids = {}
    if e.linked then
        for i, l in ipairs(e.linked) do
            ids[i] = l[1]
        end
        return ids
    end
    for _, x in ipairs({ e.spellID, e.overrideSpellID, e.overrideTooltipSpellID }) do
        ids[#ids + 1] = x
    end
    if e.spellID and e.override and e.override ~= e.spellID then
        ids[#ids + 1] = e.override
    end
    return ids
end

-- What the candidates hit (annotation only): the live auras' keys, the switched-off auras' keys (cdm = false), the
-- abilities' keys, and the IDs no aura has.
local function walk(def, ids)
    local auras, off, abilities, stray, seen = {}, {}, {}, {}, {}
    local function add(list, v)
        if not seen[list] then
            seen[list] = {}
        end
        if not seen[list][v] then
            seen[list][v] = true
            list[#list + 1] = v
        end
    end
    for _, id in ipairs(ids) do
        local hit = false
        for j, list in ipairs(def.auraIds) do
            for _, sid in ipairs(list) do
                if sid == id then
                    hit = true
                    add(def.auras[j].cdm == false and off or auras, def.auras[j].key)
                end
            end
        end
        if not hit then
            add(stray, id)
        end
        for i, list in ipairs(def.abilityIds) do
            for _, sid in ipairs(list) do
                if sid == id then
                    add(abilities, def.abilities[i].key)
                end
            end
        end
    end
    return auras, off, abilities, stray
end

-- One class booted, the fixture fed to the fake viewer, the map built; returns the fixture and the def.
local function boot(c)
    local fx = dofile("tests/Forever/fixtures/cdm/" .. c[1]:lower() .. ".lua")
    local H = headless.new({ character = { class = c[1], classID = c[2], specID = c[3], race = c[4], level = 60 } })
    assert(#H.loadErrors == 0, table.concat(H.loadErrors, "; "))
    local ctl, I = H.ctl, H.ns.VirtualStateInternal
    for cat = 0, 8 do
        ctl.viewer.sets[cat], ctl.viewer.unlearned[cat] = {}, {}
    end
    for _, e in ipairs(fx.entries) do
        local set = ctl.viewer.unlearned[e.cat]
        set[#set + 1] = e.id
        local links = {}
        for i, l in ipairs(e.linked or {}) do
            links[i] = l[1]
        end
        ctl.viewer.infos[e.id] = {
            spellID = e.spellID,
            overrideSpellID = e.overrideSpellID,
            overrideTooltipSpellID = e.overrideTooltipSpellID,
            linkedSpellIDs = links,
        }
        if e.spellID and e.override then
            ctl.overrides[e.spellID] = e.override
        end
    end
    local Q = I.PRESENCE.viewer
    local builds = Q.builds
    H.Fire("COOLDOWN_VIEWER_DATA_LOADED")
    H.ns.VirtualState.Drain(ctl.now)
    assert(Q.builds > builds, c[1] .. ": the Cooldown Manager map was not rebuilt")
    return fx, I.def, Q.map
end

-- Each Cooldown Manager entry as { key = cooldownID, name, kind, detail, gap }.
local function entryRows(fx, def, map)
    local rows = {}
    for n, e in ipairs(fx.entries) do
        local ids = candidateIds(e)
        local auras, off, abilities, stray = walk(def, ids)
        local j = map[e.id]
        local kind
        if #ids == 0 then
            kind = "spell-less"
        elseif j and j > 0 then
            kind = "mapped"
        elseif j then
            kind = "ambiguous"
        elseif #abilities > 0 then
            kind = "ability-only"
        else
            kind = "unmapped"
        end
        local d = { kind .. ", cat " .. e.cat }
        if #auras > 0 then
            d[#d + 1] = "auras " .. table.concat(auras, ",")
        end
        if #off > 0 then
            d[#d + 1] = "switched-off auras " .. table.concat(off, ",")
        end
        if #abilities > 0 then
            d[#d + 1] = "abilities " .. table.concat(abilities, ",")
        end
        if #stray > 0 then
            d[#d + 1] = (#auras + #off > 0 and "no aura has " or "no aura has any of ") .. table.concat(stray, ",")
        end
        rows[n] = {
            key = e.id,
            name = e.name or "?",
            kind = kind,
            detail = table.concat(d, "; "),
            gap = kind == "ambiguous" or kind == "unmapped",
        }
    end
    return rows
end

-- A talent name as a pack key: "Nature's Grace" -> natures_grace.
local function keyOf(name)
    return (name:lower():gsub("'", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

-- The live tree against the pack's talents (def.talents: { key, spell, max }), matched by spell ID, else by name. Rows
-- keyed by the live spell ID (live-only, spell ID differs, max ranks differ) or the pack key (pack-only); every row
-- is a gap.
local function talentRows(fx, def)
    local bySpell, byKey, used, rows = {}, {}, {}, {}
    for _, t in ipairs(def.talents) do
        bySpell[t.spell], byKey[t.key] = t, t
    end
    for _, l in ipairs(fx.talents or {}) do
        local p, kinds = bySpell[l.spellID], {}
        if not p then
            p = byKey[keyOf(l.name)]
            if p then
                kinds[#kinds + 1] = "spell ID differs (pack " .. p.key .. " " .. p.spell .. ")"
            end
        end
        if p then
            used[p.key] = true
            if l.max and p.max ~= l.max then
                kinds[#kinds + 1] = ("max ranks differ (live %d, pack %s %d)"):format(l.max, p.key, p.max)
            end
        else
            kinds[#kinds + 1] = ("live-only (node %d, max %s)"):format(l.node, tostring(l.max))
        end
        if #kinds > 0 then
            rows[#rows + 1] = { key = l.spellID, name = l.name, detail = table.concat(kinds, "; "), gap = true }
        end
    end
    for _, t in ipairs(def.talents) do
        if not used[t.key] then
            rows[#rows + 1] = {
                key = t.key,
                name = t.key,
                detail = ("pack-only (spell %d, max %d)"):format(t.spell, t.max),
                gap = true,
            }
        end
    end
    return rows
end

local function keyText(k)
    return type(k) == "number" and ("[%d]"):format(k) or ("[%q]"):format(k)
end

-- The shrinking-list rule: every gap row is in `gaps`, every `gaps` line still a gap row. Returns the line count.
local function check(label, rows, gaps)
    local extra, gone, found, n = {}, {}, {}, 0
    for _, r in ipairs(rows) do
        if r.gap then
            found[r.key] = true
            if not gaps[r.key] then
                extra[#extra + 1] = ("        %s = { %q, %q },"):format(keyText(r.key), r.name, r.detail)
            end
        end
    end
    for k, g in pairs(gaps) do
        n = n + 1
        if not found[k] then
            gone[#gone + 1] = keyText(k) .. " " .. g[1]
        end
    end
    table.sort(gone)
    assert(
        #extra == 0,
        label .. ": gaps not listed (fix the pack, or add the line with a reason):\n" .. table.concat(extra, "\n")
    )
    assert(#gone == 0, label .. ": listed gaps that are gaps no more (delete the line): " .. table.concat(gone, ", "))
    return n
end

for _, c in ipairs(CLASSES) do
    describe("the live export against the " .. c[1] .. " pack", function()
        local fx, def, map
        setup(function()
            fx, def, map = boot(c)
        end)

        it("every ambiguous or unmapped Cooldown Manager entry is in GAPS, every GAPS line still one", function()
            local rows, count = entryRows(fx, def, map), {}
            for _, r in ipairs(rows) do
                count[r.kind] = (count[r.kind] or 0) + 1
            end
            local n = #rows
            local ok, err = pcall(function()
                n = check(c[1] .. " Cooldown Manager", rows, GAPS[c[1]])
            end)
            print(
                ("CDM map %s (level %s, export %s): mapped %d / ambiguous %d / ability-only %d / unmapped %d / spell-less %d; known gaps %s"):format(
                    c[1],
                    tostring(fx.level),
                    fx.date,
                    count.mapped or 0,
                    count.ambiguous or 0,
                    count["ability-only"] or 0,
                    count.unmapped or 0,
                    count["spell-less"] or 0,
                    ok and n or "?"
                )
            )
            assert(ok, err)
        end)

        it("every live talent the pack lacks or differs on is in TALENT_GAPS, every line still one", function()
            local rows = talentRows(fx, def)
            local n = "?"
            local ok, err = pcall(function()
                n = check(c[1] .. " talents", rows, TALENT_GAPS[c[1]])
            end)
            print(
                ("Talents %s: live %d, pack %d, gap rows %d; known gaps %s"):format(
                    c[1],
                    #(fx.talents or {}),
                    #def.talents,
                    #rows,
                    tostring(n)
                )
            )
            assert(ok, err)
        end)
    end)
end
