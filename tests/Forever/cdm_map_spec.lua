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
        [199395] = { "Mark of the Wild", "ambiguous, cat 2; auras mark_of_the_wild,gift_of_the_wild; abilities mark_of_the_wild,gift_of_the_wild; no aura has 5287; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [199507] = { "Druid Forms", "ambiguous, cat 2; auras bear_form,cat_form,aquatic_form,travel_form,moonkin_form; abilities bear_form,cat_form,aquatic_form,travel_form,moonkin_form; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [200174] = { "Plainsrunning", "unmapped, cat 2; no aura has any of 1259918; lane shared races (Tauren.lua: a passive, no aura registered)" },
        [200257] = { "Transformative Cocoon", "unmapped, cat 7; no aura has any of 1301167; lane unassigned (category 7, not a class-pack spell)" },
        [200258] = { "Satchel of Potions", "unmapped, cat 7; no aura has any of 1309685; lane unassigned (category 7, not a class-pack spell)" },
    },
    HUNTER = {
        [200355] = { "Deadly Aspects", "ambiguous, cat 2; auras quick_shots; no aura has 1299448; two different procs behind one item (Quick Shots 6150, Quick Strikes 1299448): a family, unobservable roll (no cov-hunter fix)" },
        [200423] = { "Aspects", "ambiguous, cat 2; auras aspect_of_the_beast,aspect_of_the_cheetah,aspect_of_the_hawk; abilities aspect_of_the_beast,aspect_of_the_cheetah,aspect_of_the_hawk; no aura has 13163,13159,20043,20190; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
    },
    MAGE = {
        [199188] = { "Blast Wave", "unmapped, cat 0; no aura has any of 11113,13018,13019,13020,13021; lane cov-mage" },
        [199185] = { "Blink", "unmapped, cat 1; no aura has any of 1953; lane cov-mage" },
        [199199] = { "Fire Ward", "unmapped, cat 1; no aura has any of 543,8457,8458,10223,10225; lane cov-mage" },
        [199243] = { "Frost Ward", "unmapped, cat 1; no aura has any of 6143,8461,8462,10177,28609; lane cov-mage" },
        [199343] = { "Mana Gems", "unmapped, cat 1; no aura has any of 1318827; lane cov-mage" },
        [199344] = { "Polymorph", "unmapped, cat 2; no aura has any of 1320379,1324187,1324188,1324189; lane cov-mage" },
        [199206] = { "Ignite", "unmapped, cat 2; no aura has any of 412538; lane cov-mage" },
        [199326] = { "Frostbite", "unmapped, cat 2; no aura has any of 12494; lane cov-mage" },
        [199330] = { "Improved Counterspell", "unmapped, cat 2; no aura has any of 1324401,1329553; lane cov-mage" },
        [199324] = { "Impact", "unmapped, cat 2; no aura has any of 12355; lane cov-mage" },
        [199325] = { "Improved Blizzard", "unmapped, cat 2; no aura has any of 12484; lane cov-mage" },
        [199269] = { "Chilled", "unmapped, cat 2; no aura has any of 6136; lane cov-mage" },
        [200533] = { "Frost Blast", "unmapped, cat 2; no aura has any of 1326053,1326054,1326055; lane cov-mage" },
        [199248] = { "Frost Ward", "unmapped, cat 2; no aura has any of 8461,8462,10177,28609,6143; lane cov-mage" },
        [199212] = { "Fire Ward", "unmapped, cat 2; no aura has any of 8457,8458,10223,10225,543; lane cov-mage" },
        [199207] = { "Blast Wave", "unmapped, cat 2; no aura has any of 13018,13019,13020,13021,11113; lane cov-mage" },
        [199349] = { "Arcane Intellect", "unmapped, cat 2; no aura has any of 1460,1461,10156,10157,23028,1459; lane cov-mage" },
        [199354] = { "Dampen Magic", "unmapped, cat 2; no aura has any of 8450,8451,10173,10174,604; lane cov-mage" },
        [199359] = { "Amplify Magic", "unmapped, cat 2; no aura has any of 8455,10169,10170,1008; lane cov-mage" },
        [199291] = { "Mana Shield", "unmapped, cat 2; no aura has any of 8494,8495,10191,10192,10193,1463; lane cov-mage" },
    },
    PALADIN = {
        [200339] = { "Seals", "ambiguous, cat 0; auras seal_of_the_crusader,seal_of_righteousness,seal_of_justice,seal_of_wisdom,seal_of_light,seal_of_command,seal_of_fury; abilities seal_of_the_crusader,seal_of_righteousness,seal_of_justice,seal_of_wisdom,seal_of_light,seal_of_command,seal_of_fury; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [200341] = { "Unsealed Wrath", "ambiguous, cat 2; auras echo_of_fury,echo_of_command,echo_of_righteousness,echo_of_justice,echo_of_light,echo_of_wisdom; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
        [200340] = { "Seals", "ambiguous, cat 2; auras seal_of_righteousness,seal_of_fury,seal_of_the_crusader,seal_of_command,seal_of_light,seal_of_wisdom,seal_of_justice; abilities seal_of_righteousness,seal_of_fury,seal_of_the_crusader,seal_of_command,seal_of_light,seal_of_wisdom,seal_of_justice; lane core: one item for a family of auras, ambiguous by the map's one-aura rule" },
    },
    PRIEST = {
        [199929] = { "Holy Purpose", "ambiguous, cat 2; auras holy_purpose; no aura has 14909; lane cov-priest" },
    },
    ROGUE = {},
    SHAMAN = {
        [200334] = { "?", "unmapped, cat 1; no aura has any of 52127; a dead entry: item 200334 links spell 52127, which has no name and no spell on Forever (the owner export); the real Water Shield is 200335" },
        [200330] = { "Lava Burst", "unmapped, cat 0; no aura has any of 408490,1238299,1238300; lane cov-shaman: skipped, the spell is gone from the game (owner 2026-11-07, the sim dropped it)" },
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
