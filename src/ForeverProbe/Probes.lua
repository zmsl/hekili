-- Probes.lua: PR1-PR19, the sampled reads and event counters of the port plan's Phase 0
-- (TacoDogForever docs/research/2026-10-12-hekili-reconciliation/00-reconciliation.md §c).
--
-- Each probe samples on its interval and on its events, in and out of combat. Every value is encoded by
-- Core.lua's Enc(): "S" secret, "nil", "E:<msg>", "-" absent, "=text", or the plain number/boolean. Per key the
-- session keeps a tally (counts of S/N/P/E/A in and out of combat plus examples) and a ring of recent samples.
local _, ns = ...
local Register, IsSecret, Enc, ErrText, Round, G, Code = ns.Register, ns.IsSecret, ns.Enc, ns.ErrText, ns.Round, ns.G, ns.Code

local MANA, RAGE, ENERGY = 0, 1, 3
local MAINHAND = 0

local function Spell(key)
    return ns.spell[key]
end

-- C_Namespace.fn, or nil when either is missing.
local function Ns(name, fn)
    local t = _G[name]
    if type(t) ~= "table" then
        return nil
    end
    return t[fn]
end

-- First action-bar slot holding a spell, or nil (plain only).
local function FirstSlot(spellID)
    local f = Ns("C_ActionBar", "FindSpellActionButtons")
    if not f or not spellID then
        return nil
    end
    local ok, slots = pcall(f, spellID)
    if ok and not IsSecret(slots) and type(slots) == "table" then
        local first = slots[1]
        if not IsSecret(first) and type(first) == "number" then
            return first
        end
    end
    return nil
end

-- PR1 -------------------------------------------------------------------------------------------
Register({
    id = "PR1",
    title = "IsCurrentSpell for the queued swing (HS/Cleave/Maul) + CURRENT_SPELL_CAST_CHANGED",
    sessions = { W = true, D = true },
    interval = 0.5,
    events = { "CURRENT_SPELL_CAST_CHANGED", "ACTIONBAR_UPDATE_STATE" },
    unitEvents = { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" },
    sampleOn = { CURRENT_SPELL_CAST_CHANGED = true, ACTIONBAR_UPDATE_STATE = true, UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_SUCCEEDED = true },
    always = { CURRENT_SPELL_CAST_CHANGED = true },
    keys = {
        ["cur_<sp>"] = "C_Spell.IsCurrentSpell(<sp>) for hs, cl, ml and at (Attack 6603, the control)",
        ["act_<sp>"] = "C_ActionBar.IsCurrentAction(first bar slot holding <sp>)",
        ["slot_<sp>"] = "(facts) that slot",
        a1 = "event arg 1 (CURRENT_SPELL_CAST_CHANGED: cancelledCast; UNIT_*: unit)",
    },
    setup = function(p)
        p.slots = {}
        for _, key in ipairs({ "hs", "cl", "ml" }) do
            local slot = FirstSlot(Spell(key))
            p.slots[key] = slot
            p:Fact("slot_" .. key, slot)
        end
    end,
    sample = function(p)
        local f = Ns("C_Spell", "IsCurrentSpell")
        local act = Ns("C_ActionBar", "IsCurrentAction")
        for _, key in ipairs({ "hs", "cl", "ml" }) do
            local id = Spell(key)
            if id then
                p:Call("cur_" .. key, f, id)
            else
                p:Absent("cur_" .. key)
            end
            if p.slots[key] then
                p:Call("act_" .. key, act, p.slots[key])
            end
        end
        p:Call("cur_at", f, 6603)
    end,
})

-- PR2 -------------------------------------------------------------------------------------------
Register({
    id = "PR2",
    title = "Unit stats in combat: attack speed, weapon damage, attack power",
    sessions = { W = true, D = true },
    interval = 1,
    events = { "PLAYER_EQUIPMENT_CHANGED" },
    unitEvents = { "UNIT_ATTACK_SPEED", "UNIT_ATTACK_POWER", "UNIT_DAMAGE", "UNIT_ATTACK", "UNIT_RANGEDDAMAGE" },
    sampleOn = { UNIT_ATTACK_SPEED = true, UNIT_ATTACK_POWER = true, UNIT_DAMAGE = true, PLAYER_EQUIPMENT_CHANGED = true },
    keys = {
        as_mh = "UnitAttackSpeed mainhand", as_oh = "offhand", as_rg = "ranged",
        dmg_min = "UnitDamage min", dmg_max = "max", dmg_ohmin = "offhand min", dmg_ohmax = "offhand max", dmg_pct = "percent",
        ap = "UnitAttackPower", ap_pos = "posBuff", ap_neg = "negBuff", rap = "UnitRangedAttackPower",
        rdmg_speed = "UnitRangedDamage speed", rdmg_min = "min", rdmg_max = "max",
        statsSecret = "C_Secrets.ShouldUnitStatsBeSecret()",
    },
    sample = function(p)
        p:Call({ "as_mh", "as_oh", "as_rg" }, G("UnitAttackSpeed"), "player")
        p:Call({ "dmg_min", "dmg_max", "dmg_ohmin", "dmg_ohmax", false, false, "dmg_pct" }, G("UnitDamage"), "player")
        p:Call({ "ap", "ap_pos", "ap_neg" }, G("UnitAttackPower"), "player")
        p:Call({ "rdmg_speed", "rdmg_min", "rdmg_max" }, G("UnitRangedDamage"), "player")
        p:Call("rap", G("UnitRangedAttackPower"), "player")
        p:Call("statsSecret", Ns("C_Secrets", "ShouldUnitStatsBeSecret"))
    end,
})

-- PR3 -------------------------------------------------------------------------------------------
Register({
    id = "PR3",
    title = "Swing anchors: PLAYER_SWING, rage power events and HS/Maul success timing",
    sessions = { W = true, D = true },
    interval = 1,
    events = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT" },
    unitEvents = { "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET" },
    keys = {
        swRangeMH = "C_SwingTimer.IsTargetWithinSwingRange(MainHand)",
        swRangeOH = "C_SwingTimer.IsTargetWithinSwingRange(OffHand)",
        anchors = "data.anchors ring (600): {t, k, a, c, ty, dt, ds}: k = SW swing (a = swingDuration, ty = swingType, dt = seconds since the previous swing), "
            .. "PF/PU power event (a = powerType token, ds = seconds since the last swing), CS cast succeeded (a = spellID), SN sent (a = spellID), FL failed, SR swing range (a = isInRange), EC/LC auto-attack on/off",
        enableRange = "(facts) C_SwingTimer.EnableRangeCheck(MainHand, true) succeeded",
    },
    setup = function(p)
        p.lastSwing = nil
        local f = Ns("C_SwingTimer", "EnableRangeCheck")
        if f then
            local ok, err = pcall(f, 0, true)
            p.data.facts.enableRange = ok or ErrText(err)
        else
            p.data.facts.enableRange = "-"
        end
    end,
    teardown = function()
        local f = Ns("C_SwingTimer", "EnableRangeCheck")
        if f then
            pcall(f, 0, false)
        end
    end,
    onEvent = function(p, event, a1, a2, a3, a4)
        local kind, arg
        if event == "PLAYER_SWING" then
            kind, arg = "SW", a1
        elseif event == "PLAYER_SWING_RANGE_UPDATE" then
            kind, arg = "SR", a2
        elseif event == "PLAYER_ENTER_COMBAT" then
            kind = "EC"
        elseif event == "PLAYER_LEAVE_COMBAT" then
            kind = "LC"
        else
            if IsSecret(a1) or a1 ~= "player" then
                return
            end
            if event == "UNIT_POWER_FREQUENT" then
                kind, arg = "PF", a2
            elseif event == "UNIT_POWER_UPDATE" then
                kind, arg = "PU", a2
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                kind, arg = "CS", a3
            elseif event == "UNIT_SPELLCAST_SENT" then
                kind, arg = "SN", a4
            else
                kind, arg = "FL", a3
            end
        end
        local now = GetTime()
        local rec = { t = Round(now), k = kind, a = Enc(arg), c = ns.InCombat() }
        if kind == "SW" then
            rec.ty = Enc(a2)
            if p.lastSwing then
                rec.dt = Round(now - p.lastSwing)
            end
            p.lastSwing = now
        elseif p.lastSwing then
            rec.ds = Round(now - p.lastSwing)
        end
        p:Push("anchors", rec, 600)
    end,
    sample = function(p)
        local f = Ns("C_SwingTimer", "IsTargetWithinSwingRange")
        p:Call("swRangeMH", f, 0)
        p:Call("swRangeOH", f, 1)
    end,
})

-- PR4 -------------------------------------------------------------------------------------------
Register({
    id = "PR4",
    title = "Haste and the GCD length (GetSpellCooldown 29515 / 61304)",
    sessions = { any = true },
    interval = 1,
    events = { "SPELL_UPDATE_COOLDOWN" },
    unitEvents = { "UNIT_SPELL_HASTE", "UNIT_SPELLCAST_SUCCEEDED" },
    sampleOn = { SPELL_UPDATE_COOLDOWN = true, UNIT_SPELL_HASTE = true, UNIT_SPELLCAST_SUCCEEDED = true },
    keys = {
        spellHaste = "UnitSpellHaste('player')", haste = "GetHaste()", meleeHaste = "GetMeleeHaste()", rangedHaste = "GetRangedHaste()",
        ["gcd<id>_<field>"] = "C_Spell.GetSpellCooldown(<id>).<field> for 29515 (Forever GCD spell) and 61304 (retail GCD spell)",
        gcdRemain = "C_Spell.GetSpellCooldownDuration(29515):GetRemainingDuration()",
        gcdDurType = "type of the duration object",
    },
    sample = function(p)
        p:Call("spellHaste", G("UnitSpellHaste"), "player")
        p:Call("haste", G("GetHaste"))
        p:Call("meleeHaste", G("GetMeleeHaste"))
        p:Call({ "rangedHaste", "quiverHaste" }, G("GetRangedHaste"))
        local gsc = Ns("C_Spell", "GetSpellCooldown")
        for _, id in ipairs({ 29515, 61304 }) do
            p:CallFields("gcd" .. id .. "_", { "startTime", "duration", "isActive", "isOnGCD", "isEnabled", "modRate" }, gsc, id)
        end
        local gdur = Ns("C_Spell", "GetSpellCooldownDuration")
        if gdur then
            local ok, d = pcall(gdur, 29515)
            if not ok then
                p:Rec("gcdDurType", ErrText(d))
            elseif IsSecret(d) then
                p:Rec("gcdDurType", d)
            elseif d == nil then
                p:Rec("gcdDurType", nil)
            else
                p:Rec("gcdDurType", type(d))
                p:Call("gcdRemain", d.GetRemainingDuration, d)
            end
        else
            p:Absent("gcdDurType")
        end
    end,
})

-- PR5 -------------------------------------------------------------------------------------------
local TALENTS = {
    W = {
        impHeroicStrike = { 12282, 12663, 12664 }, tacticalMastery = { 12295, 12676, 12677 }, deepWounds = { 12834, 12849, 12867 },
        impOverpower = { 12290, 12963 }, deathWish = { 12292 }, flurry = { 12319, 12971, 12972, 12973, 12974 },
        enrage = { 12317, 13045, 13046, 13047, 13048 }, cruelty = { 12320, 12852, 12853, 12855, 12856 },
    },
    D = {
        ferocity = { 16934, 16935, 16936, 16937, 16938 }, feralAggression = { 16858, 16859, 16860, 16861, 16862 },
        furor = { 17056, 17058, 17059, 17060, 17061 }, omenOfClarity = { 16864 }, naturalShapeshifter = { 16833, 16834, 16835 },
        sharpenedClaws = { 16942, 16943, 16944 }, predatoryStrikes = { 16972, 16974, 16975 }, heartOfTheWild = { 17003, 17004, 17005, 17006, 24894 },
    },
}
local RANKS = {
    W = { rend = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }, heroicStrike = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 } },
    D = { rake = { 1822, 1823, 1824, 9904 }, rip = { 1079, 9492, 9493, 9752, 9894, 9896 }, shred = { 5221, 6800, 8992, 9829, 9830 }, claw = { 1082, 3029, 5201, 9849, 9850 } },
}

-- One character per rank: T/F plain, S secret, N nil, E error, - absent.
local function KnownString(fn, ids, ...)
    if type(fn) ~= "function" then
        return "-"
    end
    local out = {}
    for i, id in ipairs(ids) do
        local ok, v = pcall(fn, id, ...)
        local ch
        if not ok then
            ch = "E"
        elseif IsSecret(v) then
            ch = "S"
        elseif v == nil then
            ch = "N"
        elseif v == true then
            ch = "T"
        elseif v == false then
            ch = "F"
        else
            ch = "?"
        end
        out[i] = ch
    end
    return table.concat(out)
end

local function RefreshKnown(p)
    local kind = ns.session.kind
    local known = {}
    local csk = Ns("C_SpellBook", "IsSpellKnown")
    local isk, ips = G("IsSpellKnown"), G("IsPlayerSpell")
    local gsi = Ns("C_Spell", "GetSpellInfo")
    local function InfoKnown(id)
        local info = gsi(id)
        if IsSecret(info) then
            return info
        end
        return info ~= nil
    end
    local function Row(ids)
        return {
            csk = KnownString(csk, ids),
            isk = KnownString(isk, ids),
            ips = KnownString(ips, ids),
            info = gsi and KnownString(InfoKnown, ids) or "-",
        }
    end
    for name, ids in pairs(TALENTS[kind]) do
        known["talent_" .. name] = Row(ids)
    end
    for name, ids in pairs(RANKS[kind]) do
        known["rank_" .. name] = Row(ids)
    end
    p.data.facts.known = known
    p.data.facts.knownAt = date("%H:%M:%S")
end

-- Talent tree walk (the iSealTwist route): C_ClassTalents.GetActiveConfigID -> C_Traits.GetConfigInfo -> GetTreeNodes ->
-- GetNodeInfo -> GetEntryInfo -> GetDefinitionInfo -> C_Spell.GetSpellName. Recorded once per combat state into
-- facts.walkO (out of combat) and facts.walkC (in combat), never per sample. Nothing is compared before IsSecret().
local WALK_MAX_NODES = 250 -- node records stored per walk (the counts still cover every node)
local WALK_TRIES = 3 -- re-walks per state while a walk finds no nodes (the config may not be readable yet)
local GTI_FIELDS = { "talentID", "name", "spellID", "selected", "known", "rank", "maxRank" }

-- pcall(fn, ...). Returns the value when it is plain and of type `want`; otherwise logs why under rec[key]
-- ("S" secret, "nil", "E:<msg>" errored, "-" API absent, a plain value of the wrong type) and returns nil.
local function Step(rec, key, want, fn, ...)
    if type(fn) ~= "function" then
        rec[key] = "-"
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok then
        rec[key] = ErrText(v)
        return nil
    end
    if IsSecret(v) or type(v) ~= want then
        rec[key] = Enc(v)
        return nil
    end
    return v
end

-- Logs Enc(tbl[field]) under rec[key] (a secret or non-table parent logs its own code instead). Returns the
-- value when it is plain and of type `want`.
local function Field(rec, key, tbl, field, want)
    local v = tbl
    if not IsSecret(tbl) and type(tbl) == "table" then
        v = tbl[field]
    end
    rec[key] = Enc(v)
    if not IsSecret(v) and type(v) == want then
        return v
    end
    return nil
end

-- node -> active (else first) entry -> definition -> spell. Logs where it stops; returns the spell ID or nil.
local function ResolveSpell(rec, fns, cfg, node)
    local entryID = Field(rec, "en", node.activeEntry, "entryID", "number")
    if not entryID and rec.en == "nil" then
        entryID = Field(rec, "en", node.entryIDs, 1, "number")
        rec.fb = entryID and true or nil -- the spell came from the first entry, not an active one
    end
    if not entryID then
        return nil
    end
    local entry = Step(rec, "entry", "table", fns.entryInfo, cfg, entryID)
    local defID = entry and Field(rec, "def", entry, "definitionID", "number")
    if not defID then
        return nil
    end
    local def = Step(rec, "defn", "table", fns.defInfo, defID)
    local spellID = def and Field(rec, "spellID", def, "spellID", "number")
    if not spellID then
        return nil
    end
    local name = Step(rec, "name", "string", fns.spellName, spellID)
    if name then
        rec.spell = Enc(name)
    end
    return spellID
end

-- One node: id, rp ranksPurchased, ar activeRank, mr maxRanks, en entryID, def definitionID, spellID, spell (name),
-- f = "S" if any value was secret / "E" if any call errored. Returns rec, ranksPurchased, activeRank, spellID.
local function WalkNode(fns, cfg, nodeID)
    local rec = { id = Enc(nodeID) }
    local bought, act, spellID
    local node = Step(rec, "node", "table", fns.nodeInfo, cfg, nodeID)
    if node then
        bought = Field(rec, "rp", node, "ranksPurchased", "number")
        act = Field(rec, "ar", node, "activeRank", "number")
        Field(rec, "mr", node, "maxRanks", "number")
        spellID = ResolveSpell(rec, fns, cfg, node)
    end
    local hasS, hasE = false, false
    for _, v in pairs(rec) do
        local c = Code(v)
        hasS = hasS or c == "S"
        hasE = hasE or c == "E"
    end
    if hasS or hasE then
        rec.f = (hasS and "S" or "") .. (hasE and "E" or "")
    end
    return rec, bought, act, spellID
end

-- Encodes tbl[f] for each field, or one code ("S", "nil", "<type>") when tbl is secret or not a table.
local function Snap(tbl, fields)
    if IsSecret(tbl) or type(tbl) ~= "table" then
        return Enc(tbl)
    end
    local out = {}
    for _, f in ipairs(fields) do
        out[f] = Enc(tbl[f])
    end
    return out
end

local function TalentWalk(p)
    local w = { at = date("%H:%M:%S"), combat = p.inCombat, nodes = 0, active = 0, bought = 0, secret = 0, errors = 0, list = {} }
    local fns = {
        nodeInfo = Ns("C_Traits", "GetNodeInfo"), entryInfo = Ns("C_Traits", "GetEntryInfo"),
        defInfo = Ns("C_Traits", "GetDefinitionInfo"), spellName = Ns("C_Spell", "GetSpellName"),
    }
    local hsr = Ns("C_Secrets", "HasSecretRestrictions")
    if hsr then
        local ok, v = pcall(hsr)
        w.restr = ok and Enc(v) or ErrText(v)
    end
    local firstSpells = {}
    local cfg = Step(w, "cfgErr", "number", Ns("C_ClassTalents", "GetActiveConfigID"))
    if cfg then
        w.cfg = cfg
        local info = Step(w, "infoErr", "table", Ns("C_Traits", "GetConfigInfo"), cfg)
        local ids = Field(w, "trees", info, "treeIDs", "table")
        if ids then
            w.trees = #ids
            for _, treeID in ipairs(ids) do
                local nodeIDs = Step(w, "treeErr", "table", Ns("C_Traits", "GetTreeNodes"), treeID)
                for _, nodeID in ipairs(nodeIDs or {}) do
                    w.nodes = w.nodes + 1
                    local rec, bought, act, spellID = WalkNode(fns, cfg, nodeID)
                    if bought and bought > 0 then
                        w.bought = w.bought + 1
                    end
                    if act and act > 0 then
                        w.active = w.active + 1
                    end
                    if rec.f and string.find(rec.f, "S", 1, true) then
                        w.secret = w.secret + 1
                    end
                    if rec.f and string.find(rec.f, "E", 1, true) then
                        w.errors = w.errors + 1
                    end
                    if spellID and #firstSpells < 3 then
                        table.insert(firstSpells, { id = spellID, rp = rec.rp })
                    end
                    if #w.list < WALK_MAX_NODES then
                        table.insert(w.list, rec)
                    else
                        w.truncated = (w.truncated or 0) + 1
                    end
                end
            end
        end
    end

    -- C_SpecializationInfo.GetTalentInfo for a couple of query shapes.
    local gti = Ns("C_SpecializationInfo", "GetTalentInfo")
    if gti then
        w.gti = {}
        local queries = { idx1 = { talentIndex = 1 }, idx2 = { talentIndex = 2 }, g1t1c1 = { groupIndex = 1, tier = 1, column = 1 } }
        for name, query in pairs(queries) do
            local ok, v = pcall(gti, query)
            w.gti[name] = ok and Snap(v, GTI_FIELDS) or ErrText(v)
        end
    else
        w.gti = "-"
    end

    -- IsPlayerSpell for the first three talent spells the walk returned (rp = that node's ranksPurchased).
    local ips = G("IsPlayerSpell")
    w.ips = {}
    for i, s in ipairs(firstSpells) do
        local row = { id = s.id, rp = s.rp }
        if ips then
            local ok, v = pcall(ips, s.id)
            row.isps = ok and Enc(v) or ErrText(v)
        else
            row.isps = "-"
        end
        w.ips[i] = row
    end
    return w
end

-- Walks once per combat state: the first sample out of combat (session start) and the first in combat. A walk
-- that finds no nodes is retried on later samples, up to WALK_TRIES.
local function WalkOnce(p)
    local key = p.inCombat and "walkC" or "walkO"
    local tries = p.walkTries[key] or 0
    local prev = p.data.facts[key]
    if tries >= WALK_TRIES or (prev and (prev.nodes or 0) > 0) then
        return
    end
    p.walkTries[key] = tries + 1
    local ok, w = pcall(TalentWalk, p)
    if not ok then
        w = { err = ErrText(w) }
    end
    w.tries = tries + 1
    p.data.facts[key] = w
end

Register({
    id = "PR5",
    title = "Talent ranks, spec points, known rank spells, engraved runes, C_Traits talent walk",
    sessions = { W = true, D = true },
    interval = 15,
    events = { "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "LEARNED_SPELL_IN_TAB", "RUNE_UPDATED", "ENGRAVING_MODE_CHANGED", "PLAYER_REGEN_DISABLED" },
    sampleOn = { PLAYER_TALENT_UPDATE = true, CHARACTER_POINTS_CHANGED = true, SPELLS_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true, PLAYER_REGEN_DISABLED = true },
    always = { PLAYER_REGEN_DISABLED = true }, -- the first in-combat sample (the talent walk) is not rate-limited
    keys = {
        specIdx = "C_SpecializationInfo.GetSpecialization()", activeGroup = "GetActiveSpecGroup()", canUseSpecUI = "CanPlayerUseTalentSpecUI()",
        ["spec<i>_id/name/points"] = "GetSpecializationInfo(i): specId, name, pointsSpent",
        ["tal<tab>_1_1_<f>"] = "C_SpecializationInfo.GetTalentInfo{specializationIndex=tab, tier=1, column=1}.<f>",
        ["talIdx1_<f>"] = "C_SpecializationInfo.GetTalentInfo{talentIndex=1}.<f>",
        numTabs = "legacy GetNumTalentTabs()", ["tab1_*"] = "legacy GetTalentTabInfo(1)", ["tal1_1_*"] = "legacy GetTalentInfo(1, 1)",
        engravingEnabled = "C_Engraving.IsEngravingEnabled()", runeHead = "C_Engraving.GetRuneForEquipmentSlot(1)", numRunes = "C_Engraving.GetNumRunesKnown()",
        known = "(facts) per talent / rank ladder: one char per rank spell for C_SpellBook.IsSpellKnown (csk), IsSpellKnown (isk), IsPlayerSpell (ips), GetSpellInfo non-nil (info): T/F plain, S secret, N nil, E error, - absent",
        ["walkO / walkC"] = "(facts) the C_Traits talent walk once out of / in combat: at, combat, restr, cfg, trees, nodes, active (activeRank>0), bought (ranksPurchased>0), "
            .. "secret / errors (nodes with a secret value / an errored call), truncated, tries, list = nodes {id, rp ranksPurchased, ar activeRank, mr maxRanks, en entryID, def definitionID, "
            .. "spellID, spell name, fb (spell from the first entry), f = S|E|SE}, gti = C_SpecializationInfo.GetTalentInfo{talentIndex=1|2, groupIndex=1/tier=1/column=1} fields, "
            .. "ips = IsPlayerSpell for the first 3 walk spells {id, rp, isps}; step failures sit under cfgErr / infoErr / treeErr or the node's node / entry / defn / name",
    },
    setup = function(p)
        p.walkTries = {}
        local ok, err = pcall(RefreshKnown, p)
        if not ok then
            p.data.facts.knownErr = ErrText(err)
        end
    end,
    onEvent = function(p, event)
        if event ~= "RUNE_UPDATED" and event ~= "PLAYER_REGEN_DISABLED" then
            pcall(RefreshKnown, p)
        end
    end,
    sample = function(p)
        WalkOnce(p)
        p:Call("specIdx", Ns("C_SpecializationInfo", "GetSpecialization"))
        p:Call("activeGroup", Ns("C_SpecializationInfo", "GetActiveSpecGroup"))
        p:Call({ "canUseSpecUI", "specUIReason" }, Ns("C_SpecializationInfo", "CanPlayerUseTalentSpecUI"))
        local gsi = Ns("C_SpecializationInfo", "GetSpecializationInfo")
        for i = 1, 3 do
            p:Call({ "spec" .. i .. "_id", "spec" .. i .. "_name", false, false, false, false, "spec" .. i .. "_points" }, gsi, i)
        end
        local gti = Ns("C_SpecializationInfo", "GetTalentInfo")
        local fields = { "talentID", "name", "rank", "maxRank", "known", "spellID", "tier", "column" }
        for tab = 1, 3 do
            p:CallFields("tal" .. tab .. "_1_1_", fields, gti, { specializationIndex = tab, tier = 1, column = 1 })
        end
        p:CallFields("talIdx1_", fields, gti, { talentIndex = 1 })
        p:Call("numTabs", G("GetNumTalentTabs"))
        p:Call({ "tab1_name", "tab1_icon", "tab1_points" }, G("GetTalentTabInfo"), 1)
        p:Call({ "tal1_1_name", "tal1_1_icon", "tal1_1_tier", "tal1_1_col", "tal1_1_rank", "tal1_1_max" }, G("GetTalentInfo"), 1, 1)
        p:Call("engravingEnabled", Ns("C_Engraving", "IsEngravingEnabled"))
        p:Call("runeHead", Ns("C_Engraving", "GetRuneForEquipmentSlot"), 1)
        p:Call("numRunes", Ns("C_Engraving", "GetNumRunesKnown"))
    end,
})

-- PR6 -------------------------------------------------------------------------------------------
Register({
    id = "PR6",
    title = "Nameplates in combat: units, hostility, threat, range",
    sessions = { W = true, D = true },
    interval = 0.5,
    events = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" },
    unitEvents = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" },
    keys = {
        np = "#C_NamePlate.GetNamePlates()", hostile = "plates whose UnitCanAttack('player', unit) is plainly true", secretAttack = "plates where it was secret",
        threatPlain = "plates with a plain non-nil UnitThreatSituation('player', unit)", unitSecret = "plates whose namePlateUnitToken was secret",
        ["p<i>_*"] = "first 3 plates: unit, guid, canAttack, dead, combat (UnitAffectingCombat), threat, isTarget (UnitIsUnit), health, exists, "
            .. "spellRange (C_Spell.IsSpellInRange(melee spell, unit)), interact3 (CheckInteractDistance(unit, 3)), idSecret, threatSecret",
    },
    sample = function(p)
        local f = Ns("C_NamePlate", "GetNamePlates")
        if not f then
            p:Absent("np")
            return
        end
        local ok, plates = pcall(f)
        if not ok then
            p:Rec("np", ErrText(plates))
            return
        end
        if IsSecret(plates) or type(plates) ~= "table" then
            p:Rec("np", plates)
            return
        end
        p:Rec("np", #plates)
        local hostile, secret, threatPlain, unitSecret = 0, 0, 0, 0
        local melee = ns.RoleSpell("melee")
        local range = Ns("C_Spell", "IsSpellInRange")
        for i, plate in ipairs(plates) do
            local unit = plate.namePlateUnitToken
            if IsSecret(unit) then
                unitSecret = unitSecret + 1
            elseif type(unit) == "string" then
                local okA, can = pcall(UnitCanAttack, "player", unit)
                if okA then
                    if IsSecret(can) then
                        secret = secret + 1
                    elseif can == true then
                        hostile = hostile + 1
                    end
                end
                local okT, thr = pcall(UnitThreatSituation, "player", unit)
                if okT and not IsSecret(thr) and thr ~= nil then
                    threatPlain = threatPlain + 1
                end
                if i <= 3 then
                    local pre = "p" .. i .. "_"
                    p:Rec(pre .. "unit", unit)
                    p:Call(pre .. "guid", UnitGUID, unit)
                    p:Call(pre .. "canAttack", UnitCanAttack, "player", unit)
                    p:Call(pre .. "dead", UnitIsDead, unit)
                    p:Call(pre .. "combat", UnitAffectingCombat, unit)
                    p:Call(pre .. "threat", UnitThreatSituation, "player", unit)
                    p:Call(pre .. "isTarget", UnitIsUnit, unit, "target")
                    p:Call(pre .. "health", UnitHealth, unit)
                    p:Call(pre .. "exists", UnitExists, unit)
                    if melee then
                        p:Call(pre .. "spellRange", range, melee, unit)
                    end
                    p:Call(pre .. "interact3", G("CheckInteractDistance"), unit, 3)
                    p:Call(pre .. "idSecret", Ns("C_Secrets", "ShouldUnitIdentityBeSecret"), unit)
                    p:Call(pre .. "threatSecret", Ns("C_Secrets", "ShouldUnitThreatStateBeSecret"), "player", unit)
                end
            end
        end
        p:Rec("hostile", hostile)
        p:Rec("secretAttack", secret)
        p:Rec("threatPlain", threatPlain)
        p:Rec("unitSecret", unitSecret)
    end,
})

-- PR7 -------------------------------------------------------------------------------------------
Register({
    id = "PR7",
    title = "Range: IsSpellInRange, IsActionInRange + ACTION_RANGE_CHECK_UPDATE, swing range, tint from a secret boolean",
    sessions = { W = true, D = true },
    interval = 0.5,
    events = { "ACTION_RANGE_CHECK_UPDATE", "PLAYER_TARGET_CHANGED" },
    sampleOn = { ACTION_RANGE_CHECK_UPDATE = true, PLAYER_TARGET_CHANGED = true },
    always = { ACTION_RANGE_CHECK_UPDATE = true },
    keys = {
        ["range_<sp>"] = "C_Spell.IsSpellInRange(<sp>, 'target') for the session's range spells",
        ["actRange_<sp>"] = "C_ActionBar.IsActionInRange(first slot holding <sp>)", ["hasRangeReq_<sp>"] = "C_ActionBar.HasRangeRequirements(slot)",
        swingRange = "C_SwingTimer.IsTargetWithinSwingRange(MainHand)", interact3 = "CheckInteractDistance('target', 3) (10 yd)", interact2 = "(…, 2) (trade, 11 yd)",
        unitInRange = "UnitInRange('target') (party only)", tintOK = "Texture:SetVertexColorFromBoolean(IsSpellInRange result, green, red) on the panel: true, 'nil' (no target) or E:…",
        a2 = "ACTION_RANGE_CHECK_UPDATE isInRange", a3 = "checksRange",
    },
    setup = function(p)
        p.slots = {}
        local en = Ns("C_ActionBar", "EnableActionRangeCheck")
        for _, key in ipairs(ns.role.rangeList) do
            local slot = FirstSlot(Spell(key))
            if slot then
                p.slots[key] = slot
                p:Fact("slot_" .. key, slot)
                if en then
                    local ok, err = pcall(en, slot, true)
                    p.data.facts["enableRangeCheck_" .. key] = ok or ErrText(err)
                end
            end
        end
    end,
    teardown = function(p)
        local en = Ns("C_ActionBar", "EnableActionRangeCheck")
        if en then
            for _, slot in pairs(p.slots) do
                pcall(en, slot, false)
            end
        end
    end,
    sample = function(p)
        local range = Ns("C_Spell", "IsSpellInRange")
        local actRange = Ns("C_ActionBar", "IsActionInRange")
        local hasReq = Ns("C_ActionBar", "HasRangeRequirements")
        for _, key in ipairs(ns.role.rangeList) do
            local id = Spell(key)
            if id then
                p:Call("range_" .. key, range, id, "target")
            end
            local slot = p.slots[key]
            if slot then
                p:Call("actRange_" .. key, actRange, slot)
                p:Call("hasRangeReq_" .. key, hasReq, slot)
            end
        end
        p:Call("swingRange", Ns("C_SwingTimer", "IsTargetWithinSwingRange"), 0)
        p:Call("interact3", G("CheckInteractDistance"), "target", 3)
        p:Call("interact2", G("CheckInteractDistance"), "target", 2)
        p:Call({ "unitInRange", "unitInRangeChecked" }, G("UnitInRange"), "target")
        local melee = ns.RoleSpell("melee")
        if range and melee and ns.Display then
            local ok, v = pcall(range, melee, "target")
            if ok then
                p:Rec("tintOK", ns.Display.RangeTint(v))
            else
                p:Rec("tintOK", ErrText(v))
            end
        end
    end,
})

-- PR8 / PR9 -------------------------------------------------------------------------------------
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_SUCCEEDED",
}
local function CastSampleOn()
    local t = {}
    for _, ev in ipairs(CAST_EVENTS) do
        t[ev] = true
    end
    return t
end
local function CastSampler(unit)
    return function(p)
        p:Call({ "cast_name", "cast_display", "cast_tex", "cast_start", "cast_end", "cast_trade", "cast_guid", "cast_noInt", "cast_spell", "cast_barID", "cast_delay" }, G("UnitCastingInfo"), unit)
        p:Call({ "chan_name", false, false, "chan_start", "chan_end", false, "chan_noInt", "chan_spell", "chan_empowered", "chan_stages" }, G("UnitChannelInfo"), unit)
        p:Call("castingSecret", Ns("C_Secrets", "ShouldUnitSpellCastingBeSecret"), unit)
    end
end
local CAST_KEYS = {
    ["cast_*"] = "UnitCastingInfo(unit): name, display, tex, start, end (ms), trade, guid, noInt (notInterruptible), spell, barID, delay (ms)",
    ["chan_*"] = "UnitChannelInfo(unit): name, start, end (ms), noInt, spell, empowered, stages",
    castingSecret = "C_Secrets.ShouldUnitSpellCastingBeSecret(unit)",
    a1 = "event unit", a2 = "castGUID", a3 = "spellID", a4 = "interruptedBy / castBarID",
}

Register({
    id = "PR8",
    title = "Target casts and channels (notInterruptible, end time) + their events",
    sessions = { W = true, D = true },
    interval = 0.5,
    unitEvents = CAST_EVENTS,
    unitFilter = "target",
    sampleOn = CastSampleOn(),
    always = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_INTERRUPTED = true },
    keys = CAST_KEYS,
    sample = CastSampler("target"),
})

Register({
    id = "PR9",
    title = "Own casts and channels: channel end time, CHANNEL_UPDATE, DELAYED pushback",
    sessions = { W = true, D = true },
    interval = 0.5,
    unitEvents = CAST_EVENTS,
    unitFilter = "player",
    sampleOn = CastSampleOn(),
    always = CastSampleOn(),
    keys = CAST_KEYS,
    sample = CastSampler("player"),
})

-- PR10 ------------------------------------------------------------------------------------------
Register({
    id = "PR10",
    title = "Keybinds and action slots: GetBindingKey, C_KeyBindings, C_ActionBar.GetSpell, bar pages",
    sessions = { any = true },
    interval = 30,
    events = { "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UPDATE_BONUS_ACTIONBAR" },
    sampleOn = { UPDATE_BINDINGS = true, ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_SHAPESHIFT_FORM = true, UPDATE_BONUS_ACTIONBAR = true },
    keys = {
        ["key_ab<i>"] = "GetBindingKey('ACTIONBUTTON<i>')", key_mb1b1 = "GetBindingKey('MULTIACTIONBAR1BUTTON1')", key_shape1 = "GetBindingKey('SHAPESHIFTBUTTON1')",
        action_1 = "GetBindingAction('1')", byKey_1 = "C_KeyBindings.GetBindingByKey('1')", bindIdx_ab1 = "C_KeyBindings.GetBindingIndex('ACTIONBUTTON1')",
        page = "C_ActionBar.GetActionBarPage()", bonusOffset = "GetBonusBarOffset()", bonusIdx = "GetBonusBarIndex()", hasBonus = "HasBonusActionBar()",
        tempShapeIdx = "GetTempShapeshiftBarIndex()", hasTempShape = "HasTempShapeshiftActionBar()",
        ["slot<i>_spell"] = "C_ActionBar.GetSpell(i) for slots 1-12", ["slot<i>_text"] = "C_ActionBar.GetActionText(i) (macros)",
        ["act1_*"] = "legacy GetActionInfo(1): type, id, subType", meleeSlot = "first slot holding the melee spell", meleeSlotKey = "GetBindingKey for that slot if it is 1-12",
    },
    sample = function(p)
        local gbk = G("GetBindingKey")
        for i = 1, 12 do
            p:Call("key_ab" .. i, gbk, "ACTIONBUTTON" .. i)
        end
        p:Call("key_mb1b1", gbk, "MULTIACTIONBAR1BUTTON1")
        p:Call("key_shape1", gbk, "SHAPESHIFTBUTTON1")
        p:Call("action_1", G("GetBindingAction"), "1")
        p:Call("byKey_1", Ns("C_KeyBindings", "GetBindingByKey"), "1")
        p:Call("bindIdx_ab1", Ns("C_KeyBindings", "GetBindingIndex"), "ACTIONBUTTON1")
        p:Call("page", Ns("C_ActionBar", "GetActionBarPage"))
        p:Call("bonusOffset", Ns("C_ActionBar", "GetBonusBarOffset"))
        p:Call("bonusIdx", Ns("C_ActionBar", "GetBonusBarIndex"))
        p:Call("hasBonus", Ns("C_ActionBar", "HasBonusActionBar"))
        p:Call("tempShapeIdx", Ns("C_ActionBar", "GetTempShapeshiftBarIndex"))
        p:Call("hasTempShape", Ns("C_ActionBar", "HasTempShapeshiftActionBar"))
        local gs, gt = Ns("C_ActionBar", "GetSpell"), Ns("C_ActionBar", "GetActionText")
        for i = 1, 12 do
            p:Call("slot" .. i .. "_spell", gs, i)
            p:Call("slot" .. i .. "_text", gt, i)
        end
        p:Call({ "act1_type", "act1_id", "act1_sub" }, G("GetActionInfo"), 1)
        local slot = FirstSlot(ns.RoleSpell("melee"))
        p:Rec("meleeSlot", slot)
        if slot and slot <= 12 then
            p:Call("meleeSlotKey", gbk, "ACTIONBUTTON" .. slot)
        end
    end,
})

-- PR11 ------------------------------------------------------------------------------------------
Register({
    id = "PR11",
    title = "Proc overlay glow, cooldown duration objects, SetCooldown with secret times",
    sessions = { W = true, D = true },
    interval = 0.5,
    events = { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "SPELL_UPDATE_COOLDOWN" },
    sampleOn = { SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true, SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true, SPELL_UPDATE_COOLDOWN = true },
    always = { SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true, SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true },
    keys = {
        ["ovl_<sp>"] = "C_SpellActivationOverlay.IsSpellOverlayed(<sp>)", a1 = "GLOW_SHOW/HIDE spellID",
        cdSpell = "(facts) the cooldown spell key used below", durType = "type of C_Spell.GetSpellCooldownDuration(cd spell)",
        durRemain = "duration:GetRemainingDuration()", durStarted = "duration:HasStarted()", durTotal = "duration:GetTotalDuration()",
        setFromDurOK = "panel Cooldown:SetCooldownFromDurationObject(duration): true or E:…",
        cd_start = "C_Spell.GetSpellCooldown(cd spell).startTime", cd_dur = ".duration", cd_active = ".isActive",
        setCooldownRawOK = "panel Cooldown:SetCooldown(startTime, duration) with those (maybe secret) numbers: true or E:…",
        allocDurC = "(facts) bytes per GetSpellCooldownDuration call measured in combat", allocDurO = "(facts) …out of combat",
    },
    setup = function(p)
        local _, key = ns.RoleSpell("cd")
        p:Fact("cdSpell", key)
    end,
    sample = function(p)
        local ovl = Ns("C_SpellActivationOverlay", "IsSpellOverlayed")
        for _, key in ipairs(ns.role.overlayList) do
            local id = Spell(key)
            if id then
                p:Call("ovl_" .. key, ovl, id)
            end
        end
        local cd = ns.RoleSpell("cd")
        if not cd then
            p:Absent("durType")
            return
        end
        local gdur = Ns("C_Spell", "GetSpellCooldownDuration")
        if gdur then
            local ok, d = pcall(gdur, cd)
            if not ok then
                p:Rec("durType", ErrText(d))
            elseif IsSecret(d) then
                p:Rec("durType", d)
            elseif d == nil then
                p:Rec("durType", nil)
            else
                p:Rec("durType", type(d))
                p:Call("durRemain", d.GetRemainingDuration, d)
                p:Call("durStarted", d.HasStarted, d)
                p:Call("durTotal", d.GetTotalDuration, d)
                if ns.Display then
                    p:Rec("setFromDurOK", ns.Display.SetDurationObject(d))
                end
            end
            if ns.Display then
                local side = p.inCombat and "allocDurC" or "allocDurO"
                if p.data.facts[side] == nil then
                    p.data.facts[side] = ns.Display.MeasureAlloc(false, gdur, cd)
                end
            end
        else
            p:Absent("durType")
        end
        local gsc = Ns("C_Spell", "GetSpellCooldown")
        if gsc then
            local ok, info = pcall(gsc, cd)
            if not ok then
                p:Rec("cd_start", ErrText(info))
            elseif IsSecret(info) or type(info) ~= "table" then
                p:Rec("cd_start", info)
            else
                p:Rec("cd_start", info.startTime)
                p:Rec("cd_dur", info.duration)
                p:Rec("cd_active", info.isActive)
                if ns.Display then
                    p:Rec("setCooldownRawOK", ns.Display.SetCooldownRaw(info.startTime, info.duration))
                end
            end
        end
    end,
})

-- PR12 ------------------------------------------------------------------------------------------
Register({
    id = "PR12",
    title = "Pets and totems (opportunistic: needs a Hunter/Warlock/Shaman)",
    sessions = { any = true },
    interval = 2,
    events = { "PLAYER_TOTEM_UPDATE", "PET_BAR_UPDATE" },
    unitEvents = { "UNIT_PET" },
    sampleOn = { PLAYER_TOTEM_UPDATE = true, UNIT_PET = true },
    keys = {
        petExists = "UnitExists('pet')", petGUID = "UnitGUID('pet')", petDead = "UnitIsDead('pet')", petPowerType = "UnitPowerType('pet')",
        petPower = "UnitPower('pet')", petHealth = "UnitHealth('pet')", happiness = "C_PetInfo.GetPetHappiness()", legacyHappiness = "GetPetHappiness()",
        ["totem<i>_*"] = "GetTotemInfo(i): have, name, start, dur, spell", ["totem<i>_secret"] = "C_Secrets.ShouldTotemSlotBeSecret(i)",
    },
    sample = function(p)
        p:Call("petExists", UnitExists, "pet")
        p:Call("petGUID", UnitGUID, "pet")
        p:Call("petDead", UnitIsDead, "pet")
        p:Call({ "petPowerType", "petPowerToken" }, UnitPowerType, "pet")
        p:Call("petPower", UnitPower, "pet")
        p:Call("petHealth", UnitHealth, "pet")
        p:Call({ "happiness", "happinessDmg", "happinessLoyalty" }, Ns("C_PetInfo", "GetPetHappiness"))
        p:Call("legacyHappiness", G("GetPetHappiness"))
        local gti = G("GetTotemInfo")
        local secret = Ns("C_Secrets", "ShouldTotemSlotBeSecret")
        for slot = 1, 4 do
            local pre = "totem" .. slot .. "_"
            p:Call({ pre .. "have", pre .. "name", pre .. "start", pre .. "dur", false, false, pre .. "spell" }, gti, slot)
            p:Call(pre .. "secret", secret, slot)
        end
    end,
})

-- PR13 ------------------------------------------------------------------------------------------
local INV = { head = 1, hands = 10, trinket1 = 13, trinket2 = 14, mainhand = 16, offhand = 17, ranged = 18 }
local POTIONS = { 929, 1710, 3928, 13446 } -- Healing Potion, Greater, Superior, Major
Register({
    id = "PR13",
    title = "Gear and items: inventory IDs, IsEquippedItem, item cooldowns/counts/usability, weapon enchants",
    sessions = { W = true, D = true },
    interval = 2,
    events = { "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_COOLDOWN" },
    unitEvents = { "UNIT_INVENTORY_CHANGED" },
    sampleOn = { PLAYER_EQUIPMENT_CHANGED = true, BAG_UPDATE_COOLDOWN = true, UNIT_INVENTORY_CHANGED = true },
    keys = {
        ["inv_<slot>"] = "GetInventoryItemID('player', slot) for head, hands, trinket1/2, mainhand, offhand, ranged",
        isEquippedHead = "C_Item.IsEquippedItem(head item id read plainly earlier)", ["headCd*"] = "C_Item.GetItemCooldown(head id)", ["trinket1Cd*"] = "C_Item.GetItemCooldown(trinket 1 id)",
        ["count_<item>"] = "C_Item.GetItemCount(potion id)", ["cd_<item>_*"] = "C_Item.GetItemCooldown(potion)", ["ccd_<item>_*"] = "C_Container.GetItemCooldown(potion)", ["usable_<item>"] = "C_Item.IsUsableItem(potion)",
        ["mhEnch_*"] = "C_Item.GetWeaponEnchantInfo(MainHand)[1]: hasEnchant, timeLeft, charges, enchantID", ["wei_*"] = "legacy GetWeaponEnchantInfo(): hasMH, mhExpiration, mhCharges, mhEnchantID",
    },
    sample = function(p)
        local gii = G("GetInventoryItemID")
        for name, slot in pairs(INV) do
            p:Call("inv_" .. name, gii, "player", slot)
        end
        if gii then
            local ok, head = pcall(gii, "player", 1)
            if ok and not IsSecret(head) and type(head) == "number" then
                p.headID = head
            end
            local okT, trink = pcall(gii, "player", 13)
            if okT and not IsSecret(trink) and type(trink) == "number" then
                p.trinketID = trink
            end
        end
        local icd = Ns("C_Item", "GetItemCooldown")
        if p.headID then
            p:Call("isEquippedHead", Ns("C_Item", "IsEquippedItem"), p.headID)
            p:Call({ "headCdStart", "headCdDur", "headCdEnable" }, icd, p.headID)
        end
        if p.trinketID then
            p:Call({ "trinket1CdStart", "trinket1CdDur", "trinket1CdEnable" }, icd, p.trinketID)
            p:Call({ "trinket1Usable", "trinket1NoMana" }, Ns("C_Item", "IsUsableItem"), p.trinketID)
        end
        for _, id in ipairs(POTIONS) do
            p:Call("count_" .. id, Ns("C_Item", "GetItemCount"), id)
            p:Call({ "cd_" .. id .. "_start", "cd_" .. id .. "_dur", "cd_" .. id .. "_en" }, icd, id)
            p:Call({ "ccd_" .. id .. "_start", "ccd_" .. id .. "_dur" }, Ns("C_Container", "GetItemCooldown"), id)
            p:Call({ "usable_" .. id, "noMana_" .. id }, Ns("C_Item", "IsUsableItem"), id)
        end
        local wei = Ns("C_Item", "GetWeaponEnchantInfo")
        if wei then
            local ok, list = pcall(wei, MAINHAND)
            if not ok then
                p:Rec("mhEnch_hasEnchant", ErrText(list))
            elseif IsSecret(list) or type(list) ~= "table" then
                p:Rec("mhEnch_hasEnchant", list)
            else
                p:Fields("mhEnch_", list[1], { "hasEnchant", "timeLeft", "charges", "enchantID" })
            end
        else
            p:Absent("mhEnch_hasEnchant")
        end
        p:Call({ "wei_hasMH", "wei_mhExp", "wei_mhCharges", "wei_mhID" }, G("GetWeaponEnchantInfo"))
    end,
})

-- PR14 ------------------------------------------------------------------------------------------
Register({
    id = "PR14",
    title = "Context: movement, target classification/level/type, threat, mounted/taxi/vehicle, encounter events",
    sessions = { any = true },
    interval = 1,
    events = { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_TARGET_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    unitEvents = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" },
    sampleOn = { PLAYER_STARTED_MOVING = true, PLAYER_STOPPED_MOVING = true, ENCOUNTER_START = true, ENCOUNTER_END = true, PLAYER_TARGET_CHANGED = true, UNIT_THREAT_SITUATION_UPDATE = true, PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true },
    keys = {
        speed = "GetUnitSpeed('player') current", runSpeed = "run", moving = "IsPlayerMoving()", tClass = "UnitClassification('target')", tLevel = "UnitLevel('target')", pLevel = "UnitLevel('player')",
        tCreature = "UnitCreatureType('target') name", tCreatureID = "id", tThreat = "UnitThreatSituation('player','target')", tTanking = "UnitDetailedThreatSituation isTanking", tThreatStatus = "status", tThreatPct = "scaledPercentage",
        mounted = "IsMounted()", taxi = "UnitOnTaxi('player')", vehicle = "UnitInVehicle('player')", vehicleUI = "UnitHasVehicleUI('player')",
        tCanAttack = "UnitCanAttack('player','target')", tDead = "UnitIsDead('target')", tDeadOrGhost = "UnitIsDeadOrGhost", tEnemy = "UnitIsEnemy", tPlayer = "UnitIsPlayer", tName = "UnitName", tGUID = "UnitGUID", tTapDenied = "UnitIsTapDenied", tExists = "UnitExists",
        tIdSecret = "C_Secrets.ShouldUnitIdentityBeSecret('target')", tThreatSecret = "ShouldUnitThreatStateBeSecret('player','target')",
        tHealth = "UnitHealth('target')", tHealthMax = "UnitHealthMax", tHealthPct = "UnitHealthPercent('target', true)", affectingCombat = "UnitAffectingCombat('player')", tAffectingCombat = "…('target')",
    },
    sample = function(p)
        p:Call({ "speed", "runSpeed" }, G("GetUnitSpeed"), "player")
        p:Call("moving", G("IsPlayerMoving"))
        p:Call("tClass", G("UnitClassification"), "target")
        p:Call("tLevel", UnitLevel, "target")
        p:Call("pLevel", UnitLevel, "player")
        p:Call({ "tCreature", "tCreatureID" }, G("UnitCreatureType"), "target")
        p:Call("tThreat", G("UnitThreatSituation"), "player", "target")
        p:Call({ "tTanking", "tThreatStatus", "tThreatPct" }, G("UnitDetailedThreatSituation"), "player", "target")
        p:Call("mounted", G("IsMounted"))
        p:Call("taxi", G("UnitOnTaxi"), "player")
        p:Call("vehicle", G("UnitInVehicle"), "player")
        p:Call("vehicleUI", G("UnitHasVehicleUI"), "player")
        p:Call("tCanAttack", UnitCanAttack, "player", "target")
        p:Call("tDead", UnitIsDead, "target")
        p:Call("tDeadOrGhost", G("UnitIsDeadOrGhost"), "target")
        p:Call("tEnemy", G("UnitIsEnemy"), "player", "target")
        p:Call("tPlayer", G("UnitIsPlayer"), "target")
        p:Call("tName", UnitName, "target")
        p:Call("tGUID", UnitGUID, "target")
        p:Call("tTapDenied", G("UnitIsTapDenied"), "target")
        p:Call("tExists", UnitExists, "target")
        p:Call("tIdSecret", Ns("C_Secrets", "ShouldUnitIdentityBeSecret"), "target")
        p:Call("tThreatSecret", Ns("C_Secrets", "ShouldUnitThreatStateBeSecret"), "player", "target")
        p:Call("tHealth", UnitHealth, "target")
        p:Call("tHealthMax", UnitHealthMax, "target")
        p:Call("tHealthPct", G("UnitHealthPercent"), "target", true)
        p:Call("affectingCombat", UnitAffectingCombat, "player")
        p:Call("tAffectingCombat", UnitAffectingCombat, "target")
    end,
})

-- PR15 ------------------------------------------------------------------------------------------
Register({
    id = "PR15",
    title = "Specialization API meaning on Forever, talent groups (dual spec)",
    sessions = { any = true },
    interval = 30,
    events = { "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE" },
    unitEvents = { "PLAYER_SPECIALIZATION_CHANGED" },
    sampleOn = { ACTIVE_TALENT_GROUP_CHANGED = true, ACTIVE_PLAYER_SPECIALIZATION_CHANGED = true, PLAYER_SPECIALIZATION_CHANGED = true, PLAYER_TALENT_UPDATE = true },
    keys = {
        specIdx = "C_SpecializationInfo.GetSpecialization()", specSystem = "GetSpecializationSystem()", activeGroup = "C_SpecializationInfo.GetActiveSpecGroup()",
        numSpecs = "C_SpecializationInfo.GetNumSpecializationsForClassID(player classID)", ["spec<i>_*"] = "GetSpecializationInfo(i): id, name, points",
        legacyNumGroups = "GetNumTalentGroups()", legacyActiveGroup = "GetActiveTalentGroup()", classID = "UnitClass('player') classID",
    },
    sample = function(p)
        p:Call("specIdx", Ns("C_SpecializationInfo", "GetSpecialization"))
        p:Call("specSystem", G("GetSpecializationSystem"))
        p:Call("activeGroup", Ns("C_SpecializationInfo", "GetActiveSpecGroup"))
        local okC, _, _, classID = pcall(UnitClass, "player")
        if okC then
            p:Rec("classID", classID)
        else
            p:Rec("classID", ErrText(classID))
        end
        if okC and not IsSecret(classID) and type(classID) == "number" then
            p:Call("numSpecs", Ns("C_SpecializationInfo", "GetNumSpecializationsForClassID"), classID)
        end
        local gsi = Ns("C_SpecializationInfo", "GetSpecializationInfo")
        for i = 1, 3 do
            p:Call({ "spec" .. i .. "_id", "spec" .. i .. "_name", false, false, false, false, "spec" .. i .. "_points" }, gsi, i)
        end
        p:Call("legacyNumGroups", G("GetNumTalentGroups"))
        p:Call("legacyActiveGroup", G("GetActiveTalentGroup"))
    end,
})

-- PR16 ------------------------------------------------------------------------------------------
Register({
    id = "PR16",
    title = "Power max and regen for mana, rage and energy",
    sessions = { any = true },
    interval = 0.5,
    events = { "UPDATE_SHAPESHIFT_FORM" },
    unitEvents = { "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
    sampleOn = { UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true, UPDATE_SHAPESHIFT_FORM = true },
    keys = {
        ["max_<pt>"] = "UnitPowerMax('player', pt)", ["cur_<pt>"] = "UnitPower('player', pt)", ["pct_<pt>"] = "UnitPowerPercent('player', pt) (no curve)",
        ["maxSecret_<pt>"] = "C_Secrets.ShouldUnitPowerMaxBeSecret('player', pt)", ["regen_<pt>"] = "GetPowerRegenForPowerType(pt) base", ["regenCast_<pt>"] = "…casting",
        manaRegen = "GetManaRegen() base", manaRegenCast = "casting", powerRegen = "GetPowerRegen() base", powerRegenCast = "casting", spiritRegen = "GetManaRegenFromSpirit()",
        powerType = "UnitPowerType('player')", powerToken = "its token", hasMana = "UnitHasPowerType('player', Mana)",
    },
    sample = function(p)
        for name, pt in pairs({ mana = MANA, rage = RAGE, energy = ENERGY }) do
            p:Call("max_" .. name, UnitPowerMax, "player", pt)
            p:Call("cur_" .. name, UnitPower, "player", pt)
            p:Call("pct_" .. name, G("UnitPowerPercent"), "player", pt)
            p:Call("maxSecret_" .. name, Ns("C_Secrets", "ShouldUnitPowerMaxBeSecret"), "player", pt)
            p:Call({ "regen_" .. name, "regenCast_" .. name }, G("GetPowerRegenForPowerType"), pt)
        end
        p:Call({ "manaRegen", "manaRegenCast" }, G("GetManaRegen"))
        p:Call({ "powerRegen", "powerRegenCast" }, G("GetPowerRegen"))
        p:Call({ "spiritRegen", "spiritRegenCombat" }, G("GetManaRegenFromSpirit"))
        p:Call({ "powerType", "powerToken" }, UnitPowerType, "player")
        p:Call("hasMana", G("UnitHasPowerType"), "player", MANA)
    end,
})

-- PR17 ------------------------------------------------------------------------------------------
Register({
    id = "PR17",
    title = "UI_ERROR_MESSAGE in combat: error type ids and texts (behind, range, line of sight)",
    sessions = { any = true },
    events = { "UI_ERROR_MESSAGE" },
    keys = {
        msgs = "data.msgs[errorType] = {n, nC, text, name (GetGameMessageInfo)}; secretCount counts secret errorType payloads",
    },
    onEvent = function(p, _, errType, msg)
        local d = p.data
        d.msgs = d.msgs or {}
        local key = Enc(errType)
        if key == "S" then
            d.secretCount = (d.secretCount or 0) + 1
            return
        end
        key = tostring(key)
        local m = d.msgs[key]
        if not m then
            local count = 0
            for _ in pairs(d.msgs) do
                count = count + 1
            end
            if count >= 40 then
                d.overflow = (d.overflow or 0) + 1
                return
            end
            local name = "-"
            local ggmi = G("GetGameMessageInfo")
            if ggmi and type(errType) == "number" then
                local ok, n = pcall(ggmi, errType)
                if ok then
                    name = Enc(n)
                else
                    name = ErrText(n)
                end
            end
            m = { n = 0, nC = 0, text = Enc(msg), name = name }
            d.msgs[key] = m
        end
        m.n = m.n + 1
        if ns.InCombat() then
            m.nC = m.nC + 1
        end
    end,
})

-- PR18 ------------------------------------------------------------------------------------------
Register({
    id = "PR18",
    title = "Tooltip lines (C_TooltipInfo.GetSpellByID) and loss of control data",
    sessions = { any = true },
    interval = 5,
    unitEvents = { "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE" },
    sampleOn = { LOSS_OF_CONTROL_ADDED = true, LOSS_OF_CONTROL_UPDATE = true },
    keys = {
        ["tip_<sp>_<i>"] = "(facts) tooltip line i of the melee / cd spell: {l = leftText, r = rightText, type}",
        locCount = "C_LossOfControl.GetActiveLossOfControlDataCount()", ["loc1_*"] = "GetActiveLossOfControlData(1) fields",
        ["locCd_*"] = "C_Spell.GetSpellLossOfControlCooldownInfo(melee spell) fields",
    },
    setup = function(p)
        local gsb = Ns("C_TooltipInfo", "GetSpellByID")
        if not gsb then
            p.data.facts.tooltip = "-"
            return
        end
        for _, role in ipairs({ "melee", "cd" }) do
            local id, key = ns.RoleSpell(role)
            if id then
                local ok, data = pcall(gsb, id)
                if not ok then
                    p.data.facts["tip_" .. key] = ErrText(data)
                elseif IsSecret(data) or type(data) ~= "table" then
                    p.data.facts["tip_" .. key] = Enc(data)
                else
                    local lines = data.lines
                    if IsSecret(lines) or type(lines) ~= "table" then
                        p.data.facts["tip_" .. key] = Enc(lines)
                    else
                        for i = 1, math.min(#lines, 8) do
                            local l = lines[i]
                            if IsSecret(l) or type(l) ~= "table" then
                                p.data.facts["tip_" .. key .. "_" .. i] = Enc(l)
                            else
                                p.data.facts["tip_" .. key .. "_" .. i] = { l = Enc(l.leftText), r = Enc(l.rightText), type = Enc(l.type) }
                            end
                        end
                    end
                end
            end
        end
    end,
    sample = function(p)
        p:Call("locCount", Ns("C_LossOfControl", "GetActiveLossOfControlDataCount"))
        p:CallFields("loc1_", { "locType", "spellID", "displayText", "startTime", "timeRemaining", "duration", "lockoutSchool", "priority" }, Ns("C_LossOfControl", "GetActiveLossOfControlData"), 1)
        local melee = ns.RoleSpell("melee")
        if melee then
            p:CallFields("locCd_", { "startTime", "duration", "isEnabled", "modRate" }, Ns("C_Spell", "GetSpellLossOfControlCooldownInfo"), melee)
        end
    end,
})

-- PR19 ------------------------------------------------------------------------------------------
local menuAnchor
function ns.MenuTest()
    local sess = ns.session
    local F = sess and sess.PR19 and sess.PR19.facts or {}
    menuAnchor = menuAnchor or CreateFrame("Frame", "ForeverProbeMenuAnchor", UIParent)
    menuAnchor:SetSize(1, 1)
    menuAnchor:SetPoint("CENTER")
    local tried = false
    if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
        tried = true
        local ok, err = pcall(MenuUtil.CreateContextMenu, menuAnchor, function(_, root)
            root:CreateTitle("ForeverProbe PR19")
            root:CreateButton("MenuUtil works", function()
                ns.Print("MenuUtil button clicked")
            end)
        end)
        F.menuUtilOpenOK = ok or ErrText(err)
        ns.Print("MenuUtil.CreateContextMenu: " .. tostring(F.menuUtilOpenOK))
    end
    local init = G("UIDropDownMenu_Initialize")
    local toggle = G("ToggleDropDownMenu")
    if type(init) == "function" and type(toggle) == "function" then
        tried = true
        local ok, err = pcall(function()
            local dd = _G.ForeverProbeDropDown or CreateFrame("Frame", "ForeverProbeDropDown", UIParent, "UIDropDownMenuTemplate")
            init(dd, function(_, level)
                local info = G("UIDropDownMenu_CreateInfo")()
                info.text = "UIDropDownMenu works"
                info.notCheckable = true
                info.func = function()
                    ns.Print("dropdown button clicked")
                end
                G("UIDropDownMenu_AddButton")(info, level)
            end, "MENU")
            toggle(1, nil, dd, "cursor", 0, 0)
        end)
        F.dropDownOpenOK = ok or ErrText(err)
        ns.Print("UIDropDownMenu: " .. tostring(F.dropDownOpenOK))
    end
    if not tried then
        ns.Print("neither MenuUtil nor UIDropDownMenu is present")
    end
end

Register({
    id = "PR19",
    title = "Launcher and menu plumbing: LibDataBroker/LibDBIcon, AddonCompartment, UIDropDownMenu vs MenuUtil, UIFrameFadeOut",
    sessions = { any = true },
    interval = 3600,
    keys = { facts = "presence of each piece; fadeOutOK / dropdownTemplateOK are functional pcalls; /fprobe menu fills menuUtilOpenOK / dropDownOpenOK" },
    setup = function(p)
        local F = p.data.facts
        local function Has(name)
            local v = _G[name]
            return v ~= nil and type(v) or false
        end
        F.LibStub = Has("LibStub")
        if LibStub then
            for _, lib in ipairs({ "LibDataBroker-1.1", "LibDBIcon-1.0", "AceAddon-3.0", "LibSharedMedia-3.0" }) do
                local ok, obj = pcall(LibStub.GetLibrary, LibStub, lib, true)
                if ok then
                    F["lib_" .. lib] = obj ~= nil
                else
                    F["lib_" .. lib] = ErrText(obj)
                end
            end
        end
        F.AddonCompartmentFrame = Has("AddonCompartmentFrame")
        F.AddonCompartment_RegisterAddon = AddonCompartmentFrame ~= nil and type(AddonCompartmentFrame.RegisterAddon) == "function"
        for _, name in ipairs({ "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton", "ToggleDropDownMenu", "EasyMenu",
            "UIFrameFadeOut", "UIFrameFadeIn", "UIFrameFade", "UIFrameFadeRemoveFrame", "CreateColor", "Mixin", "CreateFromMixins",
            "InterfaceOptions_AddCategory", "GetAddOnMetadata", "Minimap", "MinimapCluster", "BackdropTemplateMixin", "GameTooltip", "ColorMixin", "PixelUtil" }) do
            F[name] = Has(name)
        end
        F.MenuUtil = Has("MenuUtil")
        F.MenuUtil_CreateContextMenu = MenuUtil ~= nil and type(MenuUtil.CreateContextMenu) == "function"
        F.Settings = Has("Settings")
        F.Settings_RegisterCanvasLayoutCategory = Settings ~= nil and type(Settings.RegisterCanvasLayoutCategory) == "function"
        F.Settings_RegisterAddOnCategory = Settings ~= nil and type(Settings.RegisterAddOnCategory) == "function"
        F.C_Timer_After = C_Timer ~= nil and type(C_Timer.After) == "function"
        F.C_AddOns_GetAddOnMetadata = C_AddOns ~= nil and type(C_AddOns.GetAddOnMetadata) == "function"
        F.ActionButtonSpellAlertManager = Has("ActionButtonSpellAlertManager")
        F.ActionButton_ShowOverlayGlow = Has("ActionButton_ShowOverlayGlow")
        if LibStub then
            local okG, glow = pcall(LibStub.GetLibrary, LibStub, "LibCustomGlow-1.0", true)
            F.LibCustomGlow = okG and glow ~= nil
        end
        -- Functional: fade a tiny frame; create a dropdown from its template.
        local fade = G("UIFrameFadeOut")
        if type(fade) == "function" then
            local f = CreateFrame("Frame", nil, UIParent)
            f:SetSize(1, 1)
            f:SetPoint("CENTER")
            local ok, err = pcall(fade, f, 1, 1, 0)
            F.fadeOutOK = ok or ErrText(err)
        end
        local ok, err = pcall(CreateFrame, "Frame", "ForeverProbeDropDown", UIParent, "UIDropDownMenuTemplate")
        F.dropdownTemplateOK = ok or ErrText(err)
        local okB, errB = pcall(CreateFrame, "Frame", nil, UIParent, "BackdropTemplate")
        F.backdropTemplateOK = okB or ErrText(errB)
    end,
})
