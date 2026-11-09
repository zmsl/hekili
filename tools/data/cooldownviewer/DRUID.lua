-- tools/data/cooldownviewer/DRUID.lua: the Forever client's Cooldown Manager entries for the Druid, from the owner's
-- probe of 2026-11-07 (level 21; ~/src/hekili-central-needs/druid-probe-2026-11-07.txt): section 2, the TrackedBuff set
-- (category 2, allowUnlearned, 40 IDs: spellID only, no override or links dumped), and section 8, the owner's layout
-- (its Essential and Utility entries; its Buff icon entries are all in section 2; its two Buff bar slots unconfigured).
-- Omen of Clarity's links from section 7 (linkedSpellIDs 16870, Clearcasting). Dev-only: tools/check_cooldown_viewer.lua
-- and the loops' viewer-fixture arm (tests/Game/harness/scenarios.lua viewerLayout) read it. Rank-1 IDs (a level 21
-- character): items of a higher rank's aura stay dark in the fake (exact-ID matching).
-- stylua: ignore
return {
    -- [cooldownID] = { category, spellID, overrideSpellID, { linkedSpellIDs } }
    [199545] = { 0, 8926, nil, {} }, -- Moonfire (layout, section 8)
    [200548] = { 0, 770, nil, {} }, -- Faerie Fire (layout, section 8)
    [199530] = { 0, 1079, nil, {} }, -- Rip (layout, section 8)
    [199846] = { 0, 6808, nil, {} }, -- Maul (layout, section 8)
    [199525] = { 1, 1238122, nil, {} }, -- Feral Charge (layout, section 8)
    [199363] = { 1, 5211, nil, {} }, -- Bash (layout, section 8)
    [199385] = { 1, 6795, nil, {} }, -- Growl (layout, section 8)
    [199382] = { 1, 5229, nil, {} }, -- Enrage (layout, section 8)
    [199402] = { 1, 20484, nil, {} }, -- Rebirth (layout, section 8)
    [199480] = { 2, 16864, nil, { 16870 } }, -- Omen of Clarity
    [199506] = { 2, 408248, nil, {} }, -- Eclipse
    [199845] = { 2, 16880, nil, {} }, -- Nature's Grace
    [199455] = { 2, 8926, nil, {} }, -- Moonfire
    [199450] = { 2, 5570, nil, {} }, -- Insect Swarm
    [199443] = { 2, 770, nil, {} }, -- Faerie Fire
    [199437] = { 2, 1062, nil, {} }, -- Entangling Roots
    [199505] = { 2, 16850, nil, {} }, -- Improved Starfire
    [199447] = { 2, 2637, nil, {} }, -- Hibernate
    [199471] = { 2, 2908, nil, {} }, -- Soothe Animal
    [199436] = { 2, 22812, nil, {} }, -- Barkskin
    [199465] = { 2, 16810, nil, {} }, -- Nature's Grasp
    [199387] = { 2, 5215, nil, {} }, -- Prowl
    [199495] = { 2, 1822, nil, {} }, -- Rake
    [199499] = { 2, 1079, nil, {} }, -- Rip
    [199554] = { 2, 414647, nil, {} }, -- Lacerate
    [199494] = { 2, 9005, nil, {} }, -- Pounce
    [199384] = { 2, 22842, nil, {} }, -- Frenzied Regeneration
    [199376] = { 2, 1735, nil, {} }, -- Demoralizing Roar
    [199386] = { 2, 6795, nil, {} }, -- Growl
    [199368] = { 2, 5209, nil, {} }, -- Challenging Roar
    [199381] = { 2, 5229, nil, {} }, -- Enrage
    [199486] = { 2, 417141, nil, {} }, -- Berserk
    [199510] = { 2, 1238122, nil, {} }, -- Feral Charge
    [199364] = { 2, 5211, nil, {} }, -- Bash
    [199374] = { 2, 1850, nil, {} }, -- Dash
    [199392] = { 2, 2893, nil, {} }, -- Abolish Poison
    [199395] = { 2, 5232, nil, {} }, -- Mark of the Wild
    [199474] = { 2, 782, nil, {} }, -- Thorns
    [199416] = { 2, 2090, nil, {} }, -- Rejuvenation
    [199407] = { 2, 8938, nil, {} }, -- Regrowth
    [199491] = { 2, 408120, nil, {} }, -- Wild Growth
    [199431] = { 2, 740, nil, {} }, -- Tranquility
    [199489] = { 2, 17116, nil, {} }, -- Nature's Swiftness
    [199394] = { 2, 29166, nil, {} }, -- Innervate
    [199507] = { 2, 1319289, nil, {} }, -- Druid Forms
    [199509] = { 2, 17007, nil, {} }, -- Leader of the Pack
    [200451] = { 2, 24907, nil, {} }, -- Moonkin Aura
    [200174] = { 2, 1259918, nil, {} }, -- Plainsrunning
    [200175] = { 2, 20549, nil, {} }, -- War Stomp
}
