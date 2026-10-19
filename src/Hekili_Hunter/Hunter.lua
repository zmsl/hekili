-- Hekili_Hunter/Hunter.lua
-- The Forever Hunter (one pseudo-spec, HUNTER_SPEC below; Beast Mastery, Marksmanship and Survival are talent builds,
-- one pack each, D3: Turret Hawk, Turret and Melee): the Hunter kit with Forever's spell data (ranks, costs, cooldowns,
-- cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb), mana under the five-second rule (the
-- Forever Hunter spends mana, never focus), Auto Shot as the ranged clock's anchor (`rangedSwing`, C7; no priority
-- reads it: shots without weaving, D5), Summon Hawk's guardians (two at most, 18 s each: RegisterPets `cap`, C1), the
-- shared cooldowns (Arcane Shot and Summon Hawk; Aimed Shot and Multi-Shot), Raptor Strike on the next swing, Mongoose
-- Bite's window from the plain usability read, and the default priorities (all provisional: no in-game check yet, D5).
-- Research: docs/research/2026-10-15-forever-hunter/research.md and the class-completion research §5.
-- Unmodelled: ranged haste on the auto-shot clock (Rapid Fire, Quick Shots; their haste on Aimed, Multi and Sniper
-- Shot's casts is modelled), the pet and its abilities (D6), Aspect of the Viper and the other runes no priority names,
-- Improved Aimed Shot's +2 s cast, Sniper Shot's range buff, Expose Prey's own Mongoose Bite window (the usability read
-- covers it), percent-of-base-mana costs (priced as a fraction of the maximum: overstated, research Q4).
-- Credits: Hekili (registration API and pack format; the on-next-swing queue read follows the Warrior's Heroic Strike).
-- wowsims/forever (MIT, ui/specs/hunter/dps/apls/turret.apl.json, turret_hawk.apl.json, melee.apl.json and sim/hunter/)
-- is the reference for the priorities and the Summon Hawk, Sniper Shot, Raptor Strike and Mongoose Bite rules; no code
-- is copied.

local Facade = Hekili.Client
local UnitClassBase, GetTime = Facade.UnitClassBase, Facade.GetTime
local IsSpellUsable, IsCurrentSpell = Facade.C_Spell.IsSpellUsable, Facade.C_Spell.IsCurrentSpell

if UnitClassBase("player") ~= "HUNTER" then
    return
end

local state = Hekili.State

-- The pseudo-spec the client reports for a Hunter (Constants.lua's row): Forever's ids run alphabetically by class
-- (Rogue 1488 and Warrior 1491 read in game), so 1484 follows the pattern; to be confirmed at the Hunter checkpoint.
local HUNTER_SPEC = 1484

local spec = Hekili:NewSpecialization(HUNTER_SPEC, true, 135130) -- Aimed Shot's icon (DB2 SpellMisc)
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's; a Forever-only row where it adds a rank), and each rank's mana cost.
local ARCANE_SHOT = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 }
local ARCANE_SHOT_COST = { 25, 35, 50, 80, 105, 135, 160, 190 }
local AIMED_SHOT = { 19434, 20900, 20901, 20902, 20903, 20904 }
local AIMED_SHOT_COST = { 75, 115, 160, 210, 260, 310 }
local SERPENT_STING = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 }
local SERPENT_STING_COST = { 15, 30, 50, 80, 115, 150, 190, 230, 250 }
local HUNTERS_MARK = { 1130, 14323, 14324, 14325, 1213268 } -- 1213268: Forever's rank 4 row
local HUNTERS_MARK_COST = { 15, 30, 45, 60, 60 }
local SNIPER_SHOT = { 1310687, 1310785, 1310786 } -- Forever-only (D4)
local SUMMON_HAWK = { 1293241, 1293525, 1293526, 1293527 } -- Forever-only (D4)
local SUMMON_HAWK_COST = { 80, 105, 135, 190 }
local RAPTOR_STRIKE = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }
local RAPTOR_STRIKE_COST = { 10, 25, 35, 45, 55, 70, 85, 100 }
local MONGOOSE_BITE = { 1495, 14269, 14270, 14271 }
local MONGOOSE_BITE_COST = { 30, 40, 50, 65 }
local WING_CLIP = { 2974, 1310180, 14267, 14268 } -- 1310180: Forever's level 12 row
local WING_CLIP_COST = { 40, 40, 60, 80 }
local ASPECT_OF_THE_HAWK = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }
local ASPECT_OF_THE_HAWK_COST = { 20, 35, 50, 70, 90, 110, 120 }
local ASPECT_OF_THE_BEAST = { 13161, 1299445, 1299446, 1299447 } -- ranks 2-4 Forever-only (D4)
local ASPECT_OF_THE_BEAST_COST = { 50, 70, 90, 110 }

local function rest(ids)
    local out = {}
    for i = 2, #ids do
        out[#out + 1] = ids[i]
    end
    return out
end

-- The highest known rank of a rank list, from the belief's spellbook: the same answer in the sim's `state`
-- environment and in a `now` handler's (event-facade spec §12a).
local knownRank = state.knownRank

local function knows(ids)
    return function()
        return knownRank(ids) > 0
    end
end

local function cost(costs, ids)
    return function()
        return costs[knownRank(ids)] or costs[1]
    end
end

-- A shot's cast time under Rapid Fire's +40% and Quick Shots' +30% ranged haste (DB2 3045 and 6150 aura 140), which
-- the engine's spell haste (stale in combat) does not see.
local function rangedCast(base)
    return function()
        return base / ((buff.rapid_fire.up and 1.4 or 1) * (buff.quick_shots.up and 1.3 or 1))
    end
end

-- One aspect at a time (wowsims aspects.go): each removes the other.
local function aspectEffect(key, other)
    return function()
        removeBuff(other)
        applyBuff(key)
    end
end

local function aspect(key, other, ids, costs)
    return {
        id = ids[1],
        copy = rest(ids),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(costs, ids),
        spendType = "mana",

        startsCombat = false,
        known = knows(ids),

        now = aspectEffect(key, other),
        handler = aspectEffect(key, other),
    }
end

-- Two abilities on one category cooldown (DB2: Arcane Shot and Summon Hawk category 1173, Aimed Shot and Multi-Shot
-- category 2; 6 s each): each sets the other's. `hawk`: the cast also summons a hawk for 18 s. (A new closure for
-- each of `now` and `handler`: each runs in its own environment.)
local function shares(other, hawk)
    return function()
        setCooldown(other, 6)
        if hawk then
            summonPet("hawk", 18)
        end
    end
end

-- A `now` or `handler` that applies `key`: debuff on the target (`debuff` true) or buff on us; or removes buff `key`.
local function applies(key, debuff)
    return function()
        if debuff then
            applyDebuff("target", key)
        else
            applyBuff(key)
        end
    end
end
local function removes(key)
    return function()
        removeBuff(key)
    end
end

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace. UNMEASURED: a level 60 Hunter's spirit regen and a little mp5 from gear.
spec:RegisterResource(Enum.PowerType.Mana, nil, nil, {
    fsr = { spirit = 15, mp5 = 2 },
})

-- Summon Hawk's guardians (C1): 2 up at most (DB2 1293527 effect 3), 18 s each (1293248's duration); the oldest gives
-- way to a third.
spec:RegisterPets({
    hawk = { spell = "summon_hawk", duration = 18, cap = 2 },
})

spec:RegisterAuras({
    aspect_of_the_hawk = { id = 13165, copy = rest(ASPECT_OF_THE_HAWK), duration = 3600, max_stack = 1 },
    aspect_of_the_beast = { id = 13161, copy = rest(ASPECT_OF_THE_BEAST), duration = 3600, max_stack = 1 },
    rapid_fire = { id = 3045, duration = 15, max_stack = 1 },
    -- Aspect of the Hawk's proc (Deadly Aspects) on an Auto Shot: +30% ranged haste.
    quick_shots = { id = 6150, duration = 12, max_stack = 1 },
    -- Mongoose Bite's window after we dodge (Defensive State, 5 s), timed from the plain usability flip (reset_precast).
    defensive_state = { id = 5302, duration = 5, max_stack = 1 },
    -- Raptor Strike queued on the next main-hand swing (C_Spell.IsCurrentSpell, applied in reset_precast).
    raptor_strike = {
        duration = function()
            return state.mainhand_speed
        end,
        max_stack = 1,
    },
    -- The target's debuffs, modelled from our casts (target auras are unreadable in combat).
    serpent_sting = { id = 1978, copy = rest(SERPENT_STING), duration = 15, tick_time = 3, max_stack = 1 },
    hunters_mark = { id = 1130, copy = rest(HUNTERS_MARK), duration = 120, max_stack = 1 },
})

-- Mongoose Bite's window from the plain usability read (the player aura walk may be secret in combat; the Rogue's
-- Cutthroat precedent): usable, or short only of mana, is the window; its 5 s from the flip's time.
local biteAt, biteOpen = 0, false
local function biteUsable()
    local r = knownRank(MONGOOSE_BITE)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(MONGOOSE_BITE[r])
    return usable == true or noMana == true
end
spec:RegisterEvent("SPELL_UPDATE_USABLE", function()
    local u = biteUsable()
    if u ~= biteOpen then
        biteOpen = u
        biteAt = u and GetTime() or 0
    end
end)

spec:RegisterHook("reset_precast", function()
    local r = knownRank(RAPTOR_STRIKE)
    if r > 0 and IsCurrentSpell(RAPTOR_STRIKE[r]) then
        applyBuff("raptor_strike")
    end
    if now == query_time and biteUsable() then
        if biteAt > 0 and now - biteAt < 5 then
            applyBuff("defensive_state", biteAt + 5 - now)
        else
            applyBuff("defensive_state")
        end
    end
end)

spec:RegisterAbilities({
    -- The ranged auto attack: its success is the ranged hand's shot (C7; whether Forever sends it per shot is a
    -- checkpoint). Never recommended.
    auto_shot = {
        id = 75,
        cast = 0,
        cooldown = 0,
        gcd = "off",
        rangedSwing = true,

        startsCombat = true,
        known = knows({ 75 }),
    },

    hunters_mark = {
        id = 1130,
        copy = rest(HUNTERS_MARK),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(HUNTERS_MARK_COST, HUNTERS_MARK),
        spendType = "mana",

        startsCombat = false,
        known = knows(HUNTERS_MARK),

        now = applies("hunters_mark", true),
        handler = applies("hunters_mark", true),
    },

    aspect_of_the_hawk = aspect(
        "aspect_of_the_hawk",
        "aspect_of_the_beast",
        ASPECT_OF_THE_HAWK,
        ASPECT_OF_THE_HAWK_COST
    ),
    aspect_of_the_beast = aspect(
        "aspect_of_the_beast",
        "aspect_of_the_hawk",
        ASPECT_OF_THE_BEAST,
        ASPECT_OF_THE_BEAST_COST
    ),

    rapid_fire = {
        id = 3045,
        cast = 0,
        cooldown = 300,
        gcd = "off",

        spend = 100,
        spendType = "mana",

        toggle = "cooldowns",
        startsCombat = false,
        known = knows({ 3045 }),

        now = applies("rapid_fire"),
        handler = applies("rapid_fire"),
    },

    serpent_sting = {
        id = 1978,
        copy = rest(SERPENT_STING),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(SERPENT_STING_COST, SERPENT_STING),
        spendType = "mana",

        startsCombat = true,
        known = knows(SERPENT_STING),

        now = applies("serpent_sting", true),
        handler = applies("serpent_sting", true),
    },

    arcane_shot = {
        id = 3044,
        copy = rest(ARCANE_SHOT),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = cost(ARCANE_SHOT_COST, ARCANE_SHOT),
        spendType = "mana",

        startsCombat = true,
        known = knows(ARCANE_SHOT),

        now = shares("summon_hawk"),
        handler = shares("summon_hawk"),
    },

    -- The dive, then a hawk for 18 s (wowsims summon_hawk.go).
    summon_hawk = {
        id = 1293241,
        copy = rest(SUMMON_HAWK),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = cost(SUMMON_HAWK_COST, SUMMON_HAWK),
        spendType = "mana",

        startsCombat = true,
        known = knows(SUMMON_HAWK),

        now = shares("arcane_shot", true),
        handler = shares("arcane_shot", true),
    },

    aimed_shot = {
        id = 19434,
        copy = rest(AIMED_SHOT),
        cast = rangedCast(2),
        cooldown = 6,
        gcd = "spell",

        spend = cost(AIMED_SHOT_COST, AIMED_SHOT),
        spendType = "mana",

        startsCombat = true,
        known = knows(AIMED_SHOT),

        now = shares("multi_shot"),
        handler = shares("multi_shot"),
    },

    -- 13.9% of base mana (DB2 PowerCostPct), priced as a fraction of the maximum (overstated: research Q4).
    multi_shot = {
        id = 2643,
        cast = rangedCast(0.5),
        cooldown = 6,
        gcd = "spell",

        spend = 0.139,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 2643 }),

        now = shares("aimed_shot"),
        handler = shares("aimed_shot"),
    },

    sniper_shot = {
        id = 1310687,
        copy = rest(SNIPER_SHOT),
        cast = rangedCast(4),
        cooldown = 15,
        gcd = "spell",

        spend = 365,
        spendType = "mana",

        startsCombat = true,
        known = knows(SNIPER_SHOT),
    },

    -- On the next main-hand swing (wowsims raptor_strike.go), paid there; its 6 s category cooldown.
    raptor_strike = {
        id = 2973,
        copy = rest(RAPTOR_STRIKE),
        cast = 0,
        cooldown = 6,
        gcd = "off",

        spend = cost(RAPTOR_STRIKE_COST, RAPTOR_STRIKE),
        spendType = "mana",

        startsCombat = true,
        onNextSwing = true,
        known = knows(RAPTOR_STRIKE),

        usable = function()
            return not buff.raptor_strike.up, "a strike is already queued"
        end,

        handler = function()
            applyBuff("raptor_strike")
        end,
    },

    mongoose_bite = {
        id = 1495,
        copy = rest(MONGOOSE_BITE),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = cost(MONGOOSE_BITE_COST, MONGOOSE_BITE),
        spendType = "mana",

        startsCombat = true,
        known = knows(MONGOOSE_BITE),

        usable = function()
            return buff.defensive_state.up, "only usable after dodging"
        end,

        now = removes("defensive_state"),
        handler = removes("defensive_state"),
    },

    -- Forever-only (D4): 5.81% of base mana (DB2 PowerCostPct), priced as a fraction of the maximum (research Q4).
    strider_kick = {
        id = 1317257,
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend = 0.0581,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 1317257 }),
    },

    wing_clip = {
        id = 2974,
        copy = rest(WING_CLIP),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(WING_CLIP_COST, WING_CLIP),
        spendType = "mana",

        startsCombat = true,
        known = knows(WING_CLIP),
    },
})

-- The filler lines' mana floors (D7: a percent of the maximum, one setting a line). Off by default: mana is secret and
-- `mana.pct` reads the belief's low-biased lower bound, which reaches the maximum only after an out-of-combat rest
-- (about 5-6 minutes), so a floor is honest after that rest (Retribution's and Enhancement's precedent).
local function manaSetting(key, name, desc)
    spec:RegisterSetting(key, 0, {
        type = "range",
        name = name,
        desc = desc,
        min = 0,
        max = 100,
        step = 1,
        width = "full",
    })
end
manaSetting(
    "arcane_shot_mana",
    "Arcane Shot Mana Floor",
    "Arcane Shot only while your mana is at least this percent of its maximum. Mana is estimated low until you rest out of combat. 0 turns the floor off."
)
manaSetting(
    "wing_clip_mana",
    "Wing Clip Mana Floor",
    "Wing Clip as a filler only while your mana is at least this percent of its maximum. Mana is estimated low until you rest out of combat. 0 turns the floor off."
)

spec:RegisterOptions({ package = "Marksmanship" })

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/hunter_spec.lua checks it matches). Provisional (each description says why).
spec:RegisterPack(
    "BeastMastery",
    20261019217,
    [[Hekili:9AvtVnUnq0Fl9utqZQDTB631lG3dlsl2euuTNPeT0qBIirkqsfd3d63EFdPJTSSD7cuGEib0CM5nV5nZqBXmXNf51YajEA(7M)9ZE3SFA(SFqKh21rI8oz1ZY14Gr2I))bs6dpI)i3o24UgRSMbyvVUj8BgXQlILVJQepn7(F8Er(gDDnLCK8vI8pAD0lKBOmI9q5E0hkFO3Gd3nu(5ENJGLhKBFEO8MoN9fTxBnYMFEO0yhk1M3Sg0BOSAdvbx2rHFzO0VXg8dLB1Hn2Ee(ws(I2Sgag2aF3a0GzPPE)fbPBnf(ACxnTQxPWHwBn10qWdLZ2ouA7bpRab93IuVKllaSvThHebJiMipd2JshUCfPqDIGTTRKm7M6G1Gir5qBFLj7rkNCDKbFkpa2JYydbx14IANTJRaCmOzfCoW9pLDAe1h1C2yqRS2MA7wdSf2cXkVVTLVpr219sxTwAao9DjPb2w6QKgeFoKWek4ETJ1uPJLJxbfrSu3Y3KCnY4h7Bc63Cm22yLNkkKNBKQaZ2T2TEDR)TQ0aalfN2Px(hFc47if5itvSCA2DBwkx(0h5EsWRRP9TGAsw)xwM73SSpyFLxAqdN0SM4WhxDCwBLgO8QgRfSs7J9bpfcPHfRcT3v7yOvsuzzyU3zv6gSoiRcyo0N15OuJDHmotuyvfGof8m2DA1IVINNYo3wwF3WVFgiFZI3UjoD4lAXSreG0iz247hh8)H8onBkBvVFX8VKSIqD84wHctB317jKdvX6Q6fZg7tLSPPi9XIgTpCh)wYI46jNLKLmjAxf8LzAtrSxDuAI(UWhNCpuCDuilwmvwWVFD(e3rILXgDeuoaUpN1vfE)I9DxF2ipkIJbNHHpT(v4JJdxqCoXHtAOhObVHeZX52A5DLdmKT(cvqgQvt(3dvuKJvd(XUjVOY6ONF4nceo8u8DCYixH3ReF41zt4WrvtKx50OtQLygEI6jcidxbIrQ0yi(c0tg1VDcQhb4As4iYp2Iipk)mpbS3FnYEqTzV(UR41rDFmHMQ)cgJ89l()tI85RyNuNxFn8sY(5c0KfWJ5DSHtLNPQ(OTtUmoGWXf4ljQNknxCl9iut3ZttPfPF5qAonQNhEO7)nf9YY1)Uohsegf9gRtK)a9SUrJVAz)Vz52OzXFp]]
)
spec:RegisterPack(
    "Marksmanship",
    20261019551,
    [[Hekili:9AvxVTTom0Fl3NUTyDEZDTxSpqgq2ddDdBfBx3NLTInvSqTL8vsobz4c)BFKsj2oUoDfya7Le9b5HKhEOsyXS7yjfChWU9YxE5)e)Y43C91XSe3UgGL0WZVNVgxO414NFLBU3wZv2szdD5UknVGayvRSY9jfB1SyzBGC2TXx96RyjLYIciyiyZzjFuBGnGPlBm2Dz30QCG5IUS7AngW1LDwJrVrALAfV6TDzkDxMu981yA1LLxc533LTdCVRlZwQD2USTsxPUfDClW3ivRrOCLOToUzn4(B0IcyvRqGlQ1fqvfu0Ljm66UmDlMo5CRZEogPLu2J4Of7r4g(wmyCvXHSKaJY(USvGalh0zD9koLmtnqRqpXSh2Eit2JucyAafUlXHjlM1LaAQepOWOBq)54sNKiQlrC)xEJe96JskAeO5ADvHERcVBPSMQLeKhWIorjBiVOTDzTQcAZXUJh89wjXGjbUBiwXicln5Cf0dOpD)ABLt(8aMu4R9LDOIqaoJlCK7B1BTYA7leHMmXdh6Nl)2xqWmGamGk3xfv7opQphOTuRWzLfWEMVa4f)qt5YzlBD6dfLetadxTgi3hNTu8qffs4IknvMsRN(TGZfKeAb2vxTJGwWXAkcv1gTqwHIDEUdvB2Ogde6Nl4EPqQwKIPtAjQdUqkw8xKmk6H3f12095haYZw8IsVOWMwJscpabLy04Zh78VrCNgnHoV1U4YNsurxnKmjvGQKlATagdr668IfXJTjNxvLg2MwjTUlOxkw4hcPOeUjIJTRu6WiPk13RgOgVTl4KQ1BYKBWyyddhPwFxBMA4idoI37HWpg4XFpaXeaEVhkt01)3F0)rZdERTZch3RYcWHWqISOMC37xSxAzJgzrQxd(amQPzOEiOB3aPGcQLG99ihZsWrg6bVjVMsSSLE01deU4w)B4GIVcFeJ9Hdkx87EoL5qqMyvUrInEjNLCkACaPJUHL4zqcre2xDsyNHCNJDhfLHMuFmIPyC1PkWbsECGFcTdc1RpbQdnMXGoTbXisnz)7gpAx4btOhX9NEk(P10Mm)oe3Xx84TSrd3uz0JWqVBUMWXuZSd5dqn9zIGmon83kcczpF2)o5FmgDE66xZZUqcJfDP2WsUbUxwjXFzA)FO5C)1SFc]]
)
spec:RegisterPack(
    "Survival",
    20261019438,
    [[Hekili:LAvuVTTnq4Fl7PLG5Qg7em0TwnGKbmK0TgmuvG9MePKoktyksnsk75x4V9DhPITsItAb6djwM3DF399Xps5YLLFPSOL7HY7xDXQFE5fl)LRU8DLf(9dqzXaVzdVdFqZ7X)xmA3k3YvuG9kdVLkUEuQ83PlRpjoUbOP8(Lx9URklwlBBHuIGRPS4pmwylydShWnWUDu7b7Ia7tGcGa7SbRzR0jnAU6xdmTjWK630HttG1SgA2ey7b)7dSpZh8gckVvUbd(VJWi0gygDG5xJlOH)ZhyUDsDhbVr3zmoC9BKE4hDbggO1SlWewt)ujJoETuj97dmlWBxmT8A(UnybCD70cEUTd8ei9Clor9MwqPOUNaZmIdwd35DNJC4AssWrXiMk)gadnHxI)euFkcvniqrcR20xZFnEUBnOtIjnQ7NG7X0K0o8p)m2YXg7Luzlx88UtIhNKUDpqY5vS69rcOtdtlT0FkB2qY0odTP23taClkxbw3i32k56heU)b3hcSFxjhWfCtkHqIYgcZzCHN(CNzNt27ERizuIdwYxC9F)xliQkalOBaAuv7X55oSNkUxsn(lwocUceKyp6ppdxI6sFccxubDPstsZuelx3bzZNX0ERg1cHYqYV0fvgh49jdLrGBN1ioTGGpQ8z4zeRbjeESH3qdKlBWcP9XCE0duzeviVRQjdWcPi)hQhfIStemBCi8XNbZpL)21XDmxfz8Ii0crmMV(8IZTr)tvI8lgDa2hrvxtB(YfctZOlF5HKr8)Eg0NoEj4x9TmMyPnCLQk91kLeBlDfuEChIqifj7r0jtQRI7Dh1Qy(59thdQQXtbpJMPKWw6s24QnOl(erJ(5k60pnadGpJEoRXGK4dREEb0vnvnO7HsNCpzdn(FlFYZ4YoeVkAT(yzb6XPR6EYvOe7D0nTrGXhUpEPnO514LmL38GbdtyopllIeLY2Ji(cLmNZuEx(s5DK9LfnweFRKJE8NOceex9cqCGVZb4RQliIE6fgXtvNI8Z8WuWdT7rwJVnX4eg65Z6R56pL2nRYt73p255bomRNunpc6REe4i0p9GuYqvLEJEYsfL4dxR8AoSVtf6Le(ht)VUU5tJmF0V2yllUf2GVNgFVX0VO48y4Y)p]]
)
