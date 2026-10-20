-- Hekili_Warrior/Warrior.lua
-- The Forever Warrior (Arms, Fury and Protection, one spec a talent tree: Hekili:NewClass): the Classic Warrior kit
-- with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb, a cost of 100 there being 10 rage; the client is 1.60.1.70374, and its export wins where they
-- differ), Forever's Victory Rush and Spearing Strike, rage per hit for both hands, Bloodrage's and Anger Management's
-- rage over time, stances from the belief's Forms source, and the default priorities.
-- Talents: the 52 live nodes (a ForeverProbe export of the client, 1.60.1.70374, 2026-10-15; confirmed by the trait
-- walk of 2026-10-16, docs/research/2026-10-16-warrior-talent-dump.md: no Improved Shield Block, Improved Taunt or
-- Toughness, Defiance max 3, so Shield Block stays 7 s and Taunt 8 s). Only rank 1 of each
-- talent is in the Forever DB2, so a cost modifier is rank 1's value x the rank (Classic's own convention), floored
-- at 0; no cooldown or duration modifier is modelled but Improved Slam's (Slam). The in-game checkpoint compares the
-- costs (Snapshot cost= / read=).
-- Credits: Hekili (registration API and pack format); the abilities, auras, stance swap, queue prediction and the Arms
-- and Fury priorities are ported from Hekili's Classic profile (origin/classic:Classic/Warrior.lua,
-- Classic/APLs/WarriorArms.simc, Classic/APLs/WarriorFury.simc); call shapes from archive/TheWarWithin/WarriorArms.lua.
-- The one- and two-hander rage rates as in Taco Dog Forever's Warrior pack
-- (src/TacoDogForever_Warrior/Warrior.lua:21-24).

local Facade = Hekili.Client
local C_SpellBook, C_Spell, UnitClassBase = Facade.C_SpellBook, Facade.C_Spell, Facade.UnitClassBase
local CombatLogGetCurrentEventInfo, GetTime = Facade.CombatLogGetCurrentEventInfo, Facade.GetTime

if UnitClassBase("player") ~= "WARRIOR" then
    return
end

local state = Hekili.State
local IsSpellKnown, IsCurrentSpell, IsSpellUsable =
    C_SpellBook.IsSpellKnown, C_Spell.IsCurrentSpell, C_Spell.IsSpellUsable
local floor, max, min, sort = math.floor, math.max, math.min, table.sort

-- The class kit and one spec a talent tree (ids the core's: Arms 100011, Fury 100012, Protection 100013; the client's
-- one pseudo-spec, 1491, only keys the legacy profile the core migrates). Icons are the DB2 talent tabs' (wowdb
-- TalentTab.SpellIconID), numeric: Options formats them with %d.
local spec = Hekili:NewClass("WARRIOR", {
    specs = {
        { key = "arms", name = "Arms", tree = 1, icon = 132292, role = "attack", package = "Arms" },
        { key = "fury", name = "Fury", tree = 2, icon = 132347, role = "attack", package = "Fury" },
        { key = "protection", name = "Protection", tree = 3, icon = 134952, role = "tank", package = "Protection" },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's).
local BATTLE_SHOUT = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local REND = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }
local REND_DURATION = { 9, 12, 15, 18, 21, 21, 21 }
local HEROIC_STRIKE = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }
local BLOODTHIRST = { 23881, 23892, 23893, 23894 }
local CHARGE = { 100, 6178, 11578 }
local CHARGE_RAGE = { 9, 12, 15 }
local CLEAVE = { 845, 7369, 11608, 11609, 20569 }
local DEMORALIZING_SHOUT = { 1160, 6190, 11554, 11555, 11556 }
local EXECUTE = { 5308, 20658, 20660, 20661, 20662 }
local HAMSTRING = { 1715, 7372, 7373 }
local INTERCEPT = { 20252, 20616, 20617 }
local MOCKING_BLOW = { 694, 7400, 7402, 20559, 20560 }
local MORTAL_STRIKE = { 12294, 21551, 21552, 21553 }
local OVERPOWER = { 7384, 7887, 11584, 11585 }
local PUMMEL = { 6552, 6554 }
local REVENGE = { 6572, 6574, 7379, 11600, 11601, 25288 }
local SHIELD_BASH = { 72, 1671, 1672 }
local SHIELD_SLAM = { 23922, 23923, 23924, 23925 }
-- Slam: Forever's rank 1 (1240193), then Improved Slam's replacements of each rank (1310196-1310200, the talent's
-- override effects), so a cast of either is ours.
local SLAM = { 1240193, 1464, 8820, 11604, 11605, 1310196, 1310197, 1310198, 1310199, 1310200 }
local SUNDER_ARMOR = { 7386, 7405, 8380, 11596, 11597 }
local THUNDER_CLAP = { 6343, 8198, 8204, 8205, 11580, 11581 }
local THUNDER_CLAP_DURATION = { 10, 14, 18, 22, 26, 30 }
local VICTORY_RUSH = { 402927 }
local WHIRLWIND = { 1680 }
local TACTICAL_MASTERY = 1310185 -- Forever's level 14 passive: rage kept on a stance swap

local function rest(ids)
    local out = {}
    for i = 2, #ids do
        out[#out + 1] = ids[i]
    end
    return out
end

-- The highest known rank of a rank list, from the belief's spellbook (the plain IsSpellKnown reads it keeps): the
-- same answer in the sim's `state` environment and in a `now` handler's (event-facade spec §12a). An upvalue, as this
-- file's plain helpers run in the file's own environment.
local knownRank = state.knownRank

-- Tactical Mastery is a passive, not an ability: declared so the belief's spellbook knows it.
local TACTICAL_MASTERY_IDS = { TACTICAL_MASTERY }
spec:RegisterAbility("tactical_mastery", { id = TACTICAL_MASTERY, passive = true })

-- The rage a stance swap keeps (Tactical Mastery and its improvement): shared by swap_stance and the stances' `now`.
local function stanceKeep(improvedRank)
    return (knownRank(TACTICAL_MASTERY_IDS) > 0 and 10 or 0) + 15 * improvedRank
end

local function knows(ids)
    return function()
        return knownRank(ids) > 0
    end
end

-- A reactive ability's window (Execute, Revenge, Victory Rush) from the plain usability read:
-- usable, or unusable only for lack of rage. The client's answer now, not at the simulated time (as Classic's
-- reset_precast read it).
local function reactive(ids)
    local r = knownRank(ids)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(ids[r])
    return usable == true or noMana == true
end

-- Usable now by the plain read, not merely short of a cost: Overpower's second cost (a combo point a dodge grants)
-- reads as "short" without a dodge. reset_precast's fallback when no dodge row timed the window (event-facade §6).
local function usableNow(ids)
    local r = knownRank(ids)
    return r > 0 and IsSpellUsable(ids[r]) == true
end

-- Rage per white swing, as measured on Forever (build 1.60.1; https://github.com/magey/forever-warrior/issues/3 and
-- the warrior compendium v3.1.0, 2026-10-01, https://ppach-warriorcompendium.share.connect.posit.cloud/rage.html):
-- the weapon's unhasted speed x a rate by hand, independent of damage, level and haste: 3.46 main hand with a
-- one-hander, 4.5 with a two-hander, 1.73 off hand. Misses, dodges and parries give none, glancing blows full rage, a
-- white crit one extra base swing (3.46 x speed main hand, two-hander too; yellow crits none): the swing entries'
-- `crit`. Dual Wield Specialization: the tooltip's +10% off-hand rage a rank (unverified on
-- Forever). Unbridled Wrath: 1 rage a proc (2 with a two-hander) at a measured ~7.5% a rank (36% at 5/5; the tooltip
-- says 60%). The two-hander flag is Hekili's gear scan (main_hand.size from C_Item.GetItemInfo's equip location on
-- PLAYER_EQUIPMENT_CHANGED; the Forever API data marks neither it nor GetInventoryItemID secret).
local function baseSpeed(hand)
    local speed = state.swingBase(hand)
    if speed <= 0 then
        speed = hand == 1 and state.mainhand_speed or state.offhand_speed
    end -- no plain base read yet
    return speed
end

local function rageOf(hand)
    local speed = baseSpeed(hand)
    local twoHand = state.main_hand.size == 2
    local wrath = 0.075 * state.talent.unbridled_wrath.rank * (twoHand and 2 or 1)
    if hand ~= 1 then
        return 1.73 * speed * (1 + 0.1 * state.talent.dual_wield_specialization.rank) + wrath
    end
    return (twoHand and 4.5 or 3.46) * speed + wrath
end

-- Rage from damage taken (Protection design §1.3; magey/forever-warrior issue 3, level 8-9): the hit before every
-- reduction x 10 / maximum health; a blocked hit gives the rage of its unblocked amount; attacker level made no
-- difference. The pre-armor amount is the post-armor one / (1 - armor / (armor + 400 + 85 x attacker level)), with the
-- armor and block value from the belief's out-of-combat stat cache. Defensive Stance's 10% and Shield Wall's
-- reduction come off before the rage too (user ruling 2026-10-16: rage is from the unreduced hit): their factors divide
-- the amount back. Shield Specialization (a 20% chance a rank to gain 5 on a block) and Master of Defense (50% a rank on
-- a dodge or parry with a shield) as their expected values, the band carrying the spread (tooltips read in game
-- 2026-10-16). Not modelled: Berserker Rage's extra rage taken.
-- shortcut: below about 130-170 armor magey's rate was exactly double (checkpoint Q6, design D2); a tank wears more by
-- level 10, so it is not modelled. Upgrade if Q6 reproduces it at the tank's level.
local RAGE_TAKEN_FACTOR = 10
local TAKEN_SPREAD = 0.15 -- the fit's scatter (9.6-11 around 10) and a stale cached armor
local DEFENSIVE_STANCE_TAKEN, SHIELD_WALL_TAKEN = 0.9, 0.4
local PROC_RAGE = 5
local SHIELD_SPECIALIZATION_CHANCE, MASTER_OF_DEFENSE_CHANCE = 0.2, 0.5 -- a rank
local unblockedAvg, UNBLOCKED_WEIGHT = 0, 0.2 -- an EMA of the unblocked post-armor amounts (a full block's estimate)
-- Each fight learns its own mobs' hits: a full block before the fight's first unblocked hit estimates 0.
spec:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    unblockedAvg = 0
end)

-- The rage of a post-armor amount `post` from an attacker of `level`, divided back by `reduced` (the percentage
-- reductions' product). Allocates nothing.
local function rageTaken(post, level, reduced)
    local armor = select(2, state.stat("UnitArmor"))
    local mitigated = armor / (armor + 400 + 85 * level) -- nonzero: 400 + 85 x level > 0
    return post / (1 - mitigated) / reduced * RAGE_TAKEN_FACTOR / state.healthMax("player") -- nonzero: max > 0 (100)
end

-- A proc's expected rage at chance p and its half-width.
local function proc(p)
    p = min(p, 1)
    return p * PROC_RAGE, max(p, 1 - p) * PROC_RAGE
end

spec:RegisterResource(
    Enum.PowerType.Rage,
    {
        mainhand = {
            swing = "mainhand",

            last = function()
                local swing = state.swings.mainhand
                local t = state.query_time
                if state.mainhand_speed == 0 then
                    return 0
                end
                return swing + floor((t - swing) / state.mainhand_speed) * state.mainhand_speed
            end,

            interval = "mainhand_speed",

            stop = function()
                return state.swings.mainhand == 0
            end,
            value = function()
                return rageOf(1)
            end,
            crit = function()
                return 3.46 * baseSpeed(1)
            end,
            -- The belief's rage from a hit on us (kind: "WOUND", "BLOCKED", "BLOCK", "DODGE", "PARRY", "MISS"): the
            -- expected gain and its half-width. Run in the belief's `now` context: `buff`, `talent` and `stat` read the belief
            -- at the hit; the helpers it calls get those values as arguments (their own environment is the file's).
            taken = function(kind, amount, level)
                local reduced = 1
                if buff.defensive_stance.up then
                    reduced = reduced * DEFENSIVE_STANCE_TAKEN
                end
                if buff.shield_wall.up then
                    reduced = reduced * SHIELD_WALL_TAKEN
                end
                local gain, width = 0, 0
                if kind == "WOUND" or kind == "BLOCKED" then
                    local post = amount
                    if kind == "BLOCKED" then
                        post = post + stat("GetShieldBlock") -- the unblocked amount
                    end
                    unblockedAvg = unblockedAvg + UNBLOCKED_WEIGHT * (post - unblockedAvg)
                    gain = rageTaken(post, level, reduced)
                    width = TAKEN_SPREAD * gain
                elseif kind == "BLOCK" then
                    gain = rageTaken(min(stat("GetShieldBlock"), unblockedAvg), level, reduced)
                    width = gain
                end
                local rank = talent.shield_specialization.rank
                if (kind == "BLOCK" or kind == "BLOCKED") and rank > 0 then
                    local g, w = proc(SHIELD_SPECIALIZATION_CHANCE * rank)
                    gain, width = gain + g, width + w
                end
                rank = talent.master_of_defense.rank
                if (kind == "DODGE" or kind == "PARRY") and rank > 0 and state.equipped.shield then
                    gain, width = proc(MASTER_OF_DEFENSE_CHANCE * rank)
                end
                return gain, width
            end,
        },

        offhand = {
            swing = "offhand",

            last = function()
                local swing = state.swings.offhand
                local t = state.query_time
                if state.offhand_speed == 0 then
                    return 0
                end
                return swing + floor((t - swing) / state.offhand_speed) * state.offhand_speed
            end,

            interval = "offhand_speed",

            stop = function()
                return state.swings.offhand == 0
            end,
            value = function()
                return rageOf(2)
            end,
            -- shortcut: the off hand's crit bonus is unmeasured (issue 3); assumed its own base, 1.73 x speed.
            crit = function()
                return 1.73 * baseSpeed(2)
            end,
        },

        -- Anger Management (12296): 1.5 rage every 5 s in combat (DB2 effect 0: aura 85, power regen 15 tenths of rage
        -- per 5 s; m2 = 1, m3 = 3 are only tooltip values), from the combat start, as wowsims/forever's log ticks it.
        anger_management = {
            talent = "anger_management",

            last = function()
                local start = state.combat
                if start == 0 then
                    return state.query_time
                end
                return start + floor((state.query_time - start) / 5) * 5
            end,

            interval = 5,

            stop = function()
                return state.combat == 0
            end,
            value = 1.5,
        },

        -- Bloodrage's aura (29131): 1 rage every second for 10 s (DB2 effect: periodic energize 10 every 1000 ms).
        -- Its ten ticks all land; the tenth, at the expiry, meets the decay's first quantum (the meta table below).
        bloodrage = {
            aura = "bloodrage",
            pausesDecay = true, -- no out-of-combat decay while it is up (in game, user-confirmed)

            last = function()
                local app = state.buff.bloodrage.applied
                return app + floor(state.query_time - app)
            end,

            interval = 1,
            -- shortcut: Improved Bloodrage's +25% (12301) is unmodelled here, the belief's entries take a number fixed at
            -- build; the handler's instant gain carries it. Upgrade if the regen entries learn talent-scaled values.
            value = 1,
        },
    },
    nil,
    {
        -- Out-of-combat rage loss per second, the belief's `decay` (in the meta table: Hekili takes every regen entry for
        -- a model): the client's Rage tooltip, "1.25 Rage is lost every 1 sec" (measured 100 -> 0 in 82.2 s: 80 s plus
        -- reaction time); Anger Management's tooltip: 30% less.
        -- No `max`: rage is 100, and a Gnome's 105 comes from Expansive Mind in the Gnome's race pack
        -- (Hekili_Shared/Races/Gnome.lua, the belief's `maxMods`, event-facade spec §12b).
        decay = function()
            return 1.25 * (1 - 0.3 * state.talent.anger_management.rank)
        end,
        -- Stepped and front-loaded (stepped-decay design): 1.25 lost at once at the start of each 1 s window, the first
        -- when the decay starts (combat end, a tick aura's expiry), so Bloodrage's last tick ends at 10 - 1.25.
        decayInterval = function()
            return 1
        end,
        -- The share of the rage an ability flagged `refundOnAvoid = true` gives back when dodged, parried or missed:
        -- wowsims/forever's MissRefund (spelldata/attributes.go), 0.8 where the DB2 flags Discount Power On Miss and
        -- the spell issues the refund (the log's "Gained 12.000 rage from {OtherID: 8}" after a dodged 15-rage Sunder
        -- Armor); unmeasured in game. Not Cleave, Whirlwind, Thunder Clap, Victory Rush, Intercept or Charge.
        refundOnAvoid = 0.8,
    }
)

-- Talents: { talent tree (1 Arms, 2 Fury, 3 Protection: the dominant tree picks the spec), the definition spell,
-- max rank }: the 52 nodes of Forever's one talent tree, grouped by their columns as the pane shows them. The tree is
-- the DB2's (Talent.TabID; Improved Slam and Improved Thunder Clap sit in another column than their tab), a
-- Forever-only node its section's. Keys are Classic's where the talent exists (Bastion keeps Classic's
-- one_handed_weapon_specialization), snake_case names for the Forever-only ones. Each node reported one definition
-- spell at every rank the export saw (owned nodes at ranks 1-5 report their rank 1 spell; Iron Will and Defiance
-- define themselves by a higher DB2 rank's ID), so there are no rank aliases. The belief maps the trait walk's
-- spells to them.
spec:RegisterTalents({
    -- Arms (16 here, 17 on the tree)
    improved_heroic_strike = { 1, 12282, 3 },
    deflection = { 1, 16462, 5 },
    improved_rend = { 1, 12286, 3 },
    improved_charge = { 1, 12285, 2 },
    improved_tactical_mastery = { 1, 12295, 5 },
    improved_overpower = { 1, 12290, 2 },
    anger_management = { 1, 12296, 1 },
    deep_wounds = { 1, 12834, 3 },
    two_handed_weapon_specialization = { 1, 12163, 3 },
    impale = { 1, 16493, 2 },
    sweeping_strikes = { 1, 12292, 1 },
    improved_hamstring = { 1, 12289, 3 },
    mortal_strike = { 1, 12294, 1 },
    improved_slam = { 2, 12862, 2 }, -- the DB2 tab is Fury
    -- Forever-only; Weaponmaster (in place of the four weapon specializations) and Bloodthrill unmodelled.
    weaponmaster = { 1, 1290261, 5 },
    spearing_strike = { 1, 1310222, 1 },
    bloodthrill = { 1, 1289682, 5 },
    -- Fury (17 here, 18 on the tree)
    booming_voice = { 2, 12321, 5 },
    cruelty = { 2, 12320, 5 },
    unbridled_wrath = { 2, 12322, 5 },
    piercing_howl = { 2, 12323, 1 },
    blood_craze = { 2, 16487, 3 },
    dual_wield_specialization = { 2, 23584, 5 },
    improved_execute = { 2, 20502, 2 },
    enrage = { 2, 12317, 5 },
    death_wish = { 2, 12328, 1 },
    improved_intercept = { 2, 20504, 2 },
    improved_berserker_rage = { 2, 20500, 2 },
    flurry = { 2, 12319, 5 },
    bloodthirst = { 2, 23881, 1 },
    -- Forever-only: Raging Blows (-3 rage on Cleave and Whirlwind); the others unmodelled.
    furious_precision = { 2, 1323963, 3 },
    raging_blows = { 2, 1310315, 1 },
    lingering_rage = { 2, 1323964, 5 },
    gore_drinker = { 2, 1323967, 2 },
    -- Protection (18 here, 17 on the tree)
    shield_specialization = { 3, 12298, 5 },
    anticipation = { 3, 12297, 5 },
    improved_bloodrage = { 3, 12301, 2 },
    improved_thunder_clap = { 1, 12287, 3 }, -- the DB2 tab is Arms
    iron_will = { 3, 12962, 5 },
    last_stand = { 3, 12975, 1 },
    improved_revenge = { 3, 12797, 3 },
    defiance = { 3, 12792, 3 },
    improved_sunder_armor = { 3, 12308, 3 },
    improved_disarm = { 3, 12313, 3 },
    improved_shield_wall = { 3, 12312, 2 },
    concussion_blow = { 3, 12809, 1 },
    improved_shield_bash = { 3, 12311, 2 },
    one_handed_weapon_specialization = { 3, 16538, 5 }, -- "Bastion" on Forever
    shield_slam = { 3, 23922, 1 },
    -- Forever-only: Focused Rage (-3 rage a rank on the offensive abilities), Vanguard (Charge in Defensive Stance),
    -- Master of Defense (rage on a dodge or parry: the rage resource's `taken`).
    focused_rage = { 3, 29787, 3 },
    vanguard = { 3, 1310317, 1 },
    master_of_defense = { 3, 1310316, 2 },
})

spec:RegisterAuras({
    battle_shout = {
        id = 6673,
        copy = rest(BATTLE_SHOUT),
        duration = 180,
        max_stack = 1,
    },
    battle_stance = {
        id = 2457,
        duration = 3600,
        max_stack = 1,
    },
    berserker_rage = {
        id = 18499,
        duration = 10,
        max_stack = 1,
    },
    berserker_stance = {
        id = 2458,
        duration = 3600,
        max_stack = 1,
    },
    blood_craze = {
        id = 16488,
        copy = { 16490, 16491 },
        duration = 6,
        tick_time = 1,
        max_stack = 1,
    },
    bloodrage = {
        id = 29131,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    challenging_shout = {
        id = 1161,
        duration = 6,
        max_stack = 1,
    },
    charge_stun = {
        id = 7922,
        duration = 1,
        max_stack = 1,
    },
    -- Cleave or Heroic Strike queued on the next swing (C_Spell.IsCurrentSpell, applied in reset_precast). A full
    -- swing long, not the time to the swing, so it can outlast the real queue by up to one swing after a reset.
    cleave = {
        duration = function()
            return state.mainhand_speed
        end,
        max_stack = 1,
    },
    concussion_blow = {
        id = 12809,
        duration = 5,
        max_stack = 1,
    },
    death_wish = {
        id = 12328,
        duration = 30,
        max_stack = 1,
    },
    deep_wound = {
        id = 23255,
        copy = { 23256 },
        duration = 12,
        max_stack = 1,
    },
    defensive_stance = {
        id = 71,
        duration = 3600,
        max_stack = 1,
    },
    demoralizing_shout = {
        id = 1160,
        copy = rest(DEMORALIZING_SHOUT),
        duration = 45,
        max_stack = 1,
    },
    disarm = {
        id = 676,
        duration = 10,
        max_stack = 1,
    },
    enrage = {
        id = 12880,
        copy = { 14201, 14202, 14203, 14204 },
        duration = 12,
        max_stack = 1,
    },
    -- A rogue's armor debuff; the Sunder Armor condition skips a target that has it.
    expose_armor = {
        id = 8647,
        copy = { 8649, 8650, 11197, 11198 },
        duration = 30,
        max_stack = 1,
    },
    flurry = {
        id = 12966,
        copy = { 12967, 12968, 12969, 12970 },
        duration = 15,
        max_stack = 1,
    },
    hamstring = {
        id = 1715,
        copy = rest(HAMSTRING),
        duration = 15,
        max_stack = 1,
    },
    heroic_strike = {
        duration = function()
            return state.mainhand_speed
        end,
        max_stack = 1,
    },
    improved_hamstring = {
        id = 23694,
        duration = 5,
        max_stack = 1,
    },
    intercept_stun = {
        id = 20253,
        copy = { 20614, 20615 },
        duration = 3,
        max_stack = 1,
    },
    intimidating_shout = {
        id = 20511,
        copy = { 5246 },
        duration = 8,
        max_stack = 1,
    },
    last_stand = {
        id = 12976,
        duration = 20,
        max_stack = 1,
    },
    mocking_blow = {
        id = 694,
        copy = rest(MOCKING_BLOW),
        duration = 6,
        max_stack = 1,
    },
    mortal_strike = {
        id = 12294,
        copy = rest(MORTAL_STRIKE),
        duration = 10,
        max_stack = 1,
    },
    -- Forever's Overpower window: a 5 s player aura (DB2 1282733, "Overpower"), unseen in combat (checkpoint Q6: the
    -- aura walk raises). Modelled as Classic did, from the dodge in the combat log (reset_precast).
    overpower_ready = {
        id = 1282733,
        duration = 5,
        max_stack = 1,
    },
    piercing_howl = {
        id = 12323,
        duration = 6,
        max_stack = 1,
    },
    recklessness = {
        id = 1719,
        duration = 15,
        max_stack = 1,
    },
    rend = {
        id = 772,
        copy = rest(REND),
        duration = function()
            return REND_DURATION[knownRank(REND)] or 9
        end,
        tick_time = 3,
        max_stack = 1,
    },
    retaliation = {
        id = 20230,
        duration = 15,
        max_stack = 1,
    },
    revenge_stun = {
        id = 12798,
        duration = 3,
        max_stack = 1,
    },
    -- Revenge's window from the block, dodge or parry on us in the combat log, while Revenge is usable (reset_precast).
    revenge_usable = {
        duration = 5,
        max_stack = 1,
    },
    -- Victory Rush's window: 20 s from a kill that yields XP or honor (DB2 402974's PROC_FLAG_KILL triggers 402975).
    -- Timed from the plain usability flip (reset_precast), as the aura walk is secret in combat.
    victorious = {
        id = 402975,
        duration = 20,
        max_stack = 1,
    },
    shield_bash_silenced = {
        id = 18498,
        duration = 3,
        max_stack = 1,
    },
    -- Shield Block's blocks are the aura's charges (DB2: SpellAuraOptions.ProcCharges = 2, no charge category): its
    -- stacks, each block or partial block on us spending one (the belief's `consumedBy`).
    shield_block = {
        id = 2565,
        duration = 7,
        max_stack = 2,
        consumedBy = { BLOCK = true, BLOCKED = true },
    },
    shield_wall = {
        id = 871,
        duration = 12,
        max_stack = 1,
    },
    sunder_armor = {
        id = 7386,
        copy = rest(SUNDER_ARMOR),
        duration = 30,
        max_stack = 5,
    },
    sweeping_strikes = {
        id = 12292,
        duration = 20,
        max_stack = 5,
    },
    taunt = {
        id = 355,
        duration = 3,
        max_stack = 1,
    },
    thunder_clap = {
        id = 6343,
        copy = rest(THUNDER_CLAP),
        duration = function()
            return THUNDER_CLAP_DURATION[knownRank(THUNDER_CLAP)] or 10
        end,
        max_stack = 1,
        shared = "target",
    },
    windfury = {
        id = 8515,
        copy = { 10609, 10612 },
        duration = 300,
        max_stack = 1,
    },
})

-- A stance change drops all rage above what is kept: Forever's Tactical Mastery passive keeps 10, Improved Tactical
-- Mastery 15 more a rank (DB2: 1310185 keeps $m1 + $12295m1; 12295's m1 is 15). Rage tops out at 100, so no cap.
spec:RegisterStateFunction("swap_stance", function(stance)
    removeBuff("battle_stance")
    removeBuff("defensive_stance")
    removeBuff("berserker_stance")

    local lost = rage.current - stanceKeep(talent.improved_tactical_mastery.rank)
    if lost > 0 then
        spend(lost, "rage")
    end

    applyBuff(stance)
end)

-- Focused Rage: -3 rage a rank on the offensive abilities (Forever's tooltip; DB2 29787 -30 at rank 1), floored at 0.
-- shortcut: which abilities count is a guess (every ability that strikes an enemy, and Disarm; not the shouts),
-- unseen until someone buys the talent; correct the offensive_cost calls from the client's costs (Snapshot cost= /
-- read=) then. A file-local reading the caller's `talent`: the belief prices a cast in Families/Now.lua's context,
-- which has `talent` but no state functions.
local function offensive_cost(talent, cost)
    return max(0, cost - 3 * talent.focused_rage.rank)
end

-- The reactive windows from the combat log, as Classic models them (origin/classic:Classic/Warrior.lua:400-456): our
-- dodged swing or ability opens Overpower's, a dodge, parry or block on us opens Revenge's. On Forever the rows come
-- from the belief's event facade (docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md §6).
local enemy_revenge_trigger, enemy_dodged, enemy_dodged_target = 0, 0, nil
local last_overpower = 0
local misses = { DODGE = true, PARRY = true, BLOCK = true }
local overpower_ids = {}
for _, id in ipairs(OVERPOWER) do
    overpower_ids[id] = true
end

spec:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
    local _, subtype, _, sourceGUID, _, _, _, destGUID, _, _, _, actionType, _, _, spellMissType =
        CombatLogGetCurrentEventInfo()

    if
        sourceGUID == state.GUID
        and subtype:match("_MISSED$")
        and (actionType == "DODGE" or spellMissType == "DODGE")
    then
        enemy_dodged = GetTime()
        enemy_dodged_target = destGUID
    elseif destGUID == state.GUID and subtype:match("_MISSED$") and misses[actionType] then
        enemy_revenge_trigger = GetTime()
    elseif sourceGUID == state.GUID and subtype == "SPELL_CAST_SUCCESS" and overpower_ids[actionType] then
        last_overpower = GetTime()
    end
end)

-- Victorious has no plain kill row: IsSpellUsable ignores the cooldown, so its false->true flip is the kill.
local victorious_at, victory_usable = 0, false
spec:RegisterEvent("SPELL_UPDATE_USABLE", function()
    local u = reactive(VICTORY_RUSH)
    if u ~= victory_usable then
        victory_usable = u
        victorious_at = u and GetTime() or 0
    end
end)

spec:RegisterHook("reset_precast", function()
    -- The stance comes from the belief's Forms source (Game/State/Sources/Forms.lua) through the aura walk.
    local hs, cl = knownRank(HEROIC_STRIKE), knownRank(CLEAVE)
    if hs > 0 and IsCurrentSpell(HEROIC_STRIKE[hs]) then
        applyBuff("heroic_strike")
    end
    if cl > 0 and IsCurrentSpell(CLEAVE[cl]) then
        applyBuff("cleave")
    end

    if now == query_time then
        if knownRank(OVERPOWER) > 0 then
            if
                enemy_dodged > 0
                and query_time - enemy_dodged < 6
                and target.unit == enemy_dodged_target
                and (last_overpower == 0 or enemy_dodged - last_overpower > 5)
            then
                applyBuff("overpower_ready", enemy_dodged + 5 - now)
            elseif usableNow(OVERPOWER) then
                applyBuff("overpower_ready")
            end
        end
        if reactive(REVENGE) then
            if enemy_revenge_trigger > 0 and now - enemy_revenge_trigger < 5 then
                applyBuff("revenge_usable", enemy_revenge_trigger + 5 - now)
            else
                applyBuff("revenge_usable")
            end
        end
        -- With an expiry the sim knows the window's end ahead: Victory Rush is refused past it.
        if reactive(VICTORY_RUSH) then
            if victorious_at > 0 and now - victorious_at < 20 then
                applyBuff("victorious", victorious_at + 20 - now)
            else
                applyBuff("victorious")
            end
        end
    end
end)

-- `timeToReady` of the three stances: they share a 1 s category cooldown.
local function stanceReady()
    return max(cooldown.battle_stance.remains, cooldown.defensive_stance.remains, cooldown.berserker_stance.remains)
end

spec:RegisterAbilities({
    battle_shout = {
        id = 6673,
        copy = rest(BATTLE_SHOUT),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = false,
        known = knows(BATTLE_SHOUT),

        now = function()
            applyBuff("battle_shout")
        end,

        handler = function()
            applyBuff("battle_shout")
        end,
    },

    battle_stance = {
        id = 2457,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows({ 2457 }),
        nobuff = "battle_stance",
        timeToReady = stanceReady,

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            removeBuff("defensive_stance")
            removeBuff("berserker_stance")
            local lost = rage.current - stanceKeep(talent.improved_tactical_mastery.rank)
            if lost > 0 then
                spend(lost, "rage")
            end
            applyBuff("battle_stance")
        end,

        handler = function()
            swap_stance("battle_stance")
        end,
    },

    berserker_rage = {
        id = 18499,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        startsCombat = false,
        known = knows({ 18499 }),
        buff = "berserker_stance",

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            applyBuff("berserker_rage")
            if talent.improved_berserker_rage.enabled then
                gain(10 * talent.improved_berserker_rage.rank, "rage")
            end
        end,

        handler = function()
            applyBuff("berserker_rage")
            -- DB2 20500: energize 100 (10 rage) a rank.
            if talent.improved_berserker_rage.enabled then
                gain(10 * talent.improved_berserker_rage.rank, "rage")
            end
        end,
    },

    berserker_stance = {
        id = 2458,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows({ 2458 }),
        nobuff = "berserker_stance",
        timeToReady = stanceReady,

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            removeBuff("battle_stance")
            removeBuff("defensive_stance")
            local lost = rage.current - stanceKeep(talent.improved_tactical_mastery.rank)
            if lost > 0 then
                spend(lost, "rage")
            end
            applyBuff("berserker_stance")
        end,

        handler = function()
            swap_stance("berserker_stance")
        end,
    },

    -- 10 rage now (DB2: energize 100), then 10 over 10 s from its aura (the resource's bloodrage entry). Its health
    -- cost is not simulated: the player's health is secret on Forever.
    bloodrage = {
        id = 2687,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        startsCombat = false,
        known = knows({ 2687 }),
        toggle = "cooldowns",

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            gain(10 * (1 + 0.25 * talent.improved_bloodrage.rank), "rage")
            applyBuff("bloodrage")
        end,

        handler = function()
            -- 12301 (in-game tooltip): +25% of the rage Bloodrage generates a rank.
            gain(10 * (1 + 0.25 * talent.improved_bloodrage.rank), "rage")
            applyBuff("bloodrage")
        end,
    },

    bloodthirst = {
        id = 23881,
        copy = rest(BLOODTHIRST),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 30)
        end,
        spendType = "rage",

        talent = "bloodthirst",
        startsCombat = true,
        refundOnAvoid = true, -- wowsims talents_fury.go; DB2 Discount Power On Miss
        known = knows(BLOODTHIRST),
    },

    challenging_shout = {
        id = 1161,
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        known = knows({ 1161 }),
        toggle = "defensives",

        now = function()
            applyDebuff("target", "challenging_shout")
        end,

        handler = function()
            applyDebuff("target", "challenging_shout")
        end,
    },

    charge = {
        id = 100,
        copy = rest(CHARGE),
        cast = 0,
        cooldown = 15,
        gcd = "off",

        startsCombat = true,
        known = knows(CHARGE),
        -- Vanguard: Charge also in Defensive Stance (Forever, 1310317)
        buff = function()
            if talent.vanguard.enabled and buff.defensive_stance.up then
                return "defensive_stance"
            end
            return "battle_stance"
        end,

        -- The spell's own range check: exact, where target.minR/maxR are only the coarse bracket (VS.TargetRange).
        usable = function()
            return combat == 0 and not action.rend.in_range, "cannot be in combat; target must be outside melee range"
        end,

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            gain((CHARGE_RAGE[knownRank(CHARGE)] or 9) + 3 * talent.improved_charge.rank, "rage")
            applyDebuff("target", "charge_stun")
        end,

        handler = function()
            setDistance(7)
            if not target.is_boss then
                applyDebuff("target", "charge_stun")
            end
            gain((CHARGE_RAGE[knownRank(CHARGE)] or 9) + 3 * talent.improved_charge.rank, "rage")
        end,
    },

    cleave = {
        id = 845,
        copy = rest(CLEAVE),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function()
            return offensive_cost(talent, 20 - 3 * talent.raging_blows.rank)
        end, -- Raging Blows: -3
        spendType = "rage",

        startsCombat = true,
        onNextSwing = true, -- The belief: paid at the main hand's next swing, which then brings no rage
        known = knows(CLEAVE),

        usable = function()
            return not buff.heroic_strike.up and not buff.cleave.up, "a strike is already queued"
        end,

        handler = function()
            applyBuff("cleave")
        end,
    },

    concussion_blow = {
        id = 12809,
        cast = 0,
        cooldown = 45,
        gcd = "off",

        spend = function()
            return offensive_cost(talent, 10)
        end,
        spendType = "rage",

        talent = "concussion_blow",
        startsCombat = true,
        refundOnAvoid = true, -- wowsims talents_protection.go; DB2 Discount Power On Miss
        known = knows({ 12809 }),

        now = function()
            applyDebuff("target", "concussion_blow")
        end,

        handler = function()
            applyDebuff("target", "concussion_blow")
        end,
    },

    death_wish = {
        id = 12328,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        talent = "death_wish",
        startsCombat = true,
        known = knows({ 12328 }),
        toggle = "cooldowns",

        now = function()
            applyBuff("death_wish")
        end,

        handler = function()
            applyBuff("death_wish")
        end,
    },

    defensive_stance = {
        id = 71,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows({ 71 }),
        nobuff = "defensive_stance",
        timeToReady = stanceReady,

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            removeBuff("battle_stance")
            removeBuff("berserker_stance")
            local lost = rage.current - stanceKeep(talent.improved_tactical_mastery.rank)
            if lost > 0 then
                spend(lost, "rage")
            end
            applyBuff("defensive_stance")
        end,

        handler = function()
            swap_stance("defensive_stance")
        end,
    },

    demoralizing_shout = {
        id = 1160,
        copy = rest(DEMORALIZING_SHOUT),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows(DEMORALIZING_SHOUT),

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            applyDebuff("target", "demoralizing_shout")
        end,

        handler = function()
            applyDebuff("target", "demoralizing_shout")
            active_dot.demoralizing_shout = active_enemies
        end,
    },

    disarm = {
        id = 676,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 20)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims disarm.go; DB2 Discount Power On Miss
        known = knows({ 676 }),
        toggle = "cooldowns",
        buff = "defensive_stance",

        now = function()
            applyDebuff("target", "disarm")
        end,

        handler = function()
            applyDebuff("target", "disarm")
        end,
    },

    -- Usable below 20% health: the target's health is secret on Forever, so the window is the plain usability read.
    execute = {
        id = 5308,
        copy = rest(EXECUTE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, max(0, 15 - 5 * talent.improved_execute.rank))
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims execute.go; DB2 Discount Power On Miss
        known = knows(EXECUTE),
        nobuff = "defensive_stance",
        healthGate = 0.2, -- usable at or below 20% of the target's health: the belief's target health reads it

        usable = function()
            return reactive(EXECUTE), "requires target health under 20 percent"
        end,

        handler = function()
            spend(rage.current, "rage") -- the rest of the rage goes into the strike
        end,
    },

    hamstring = {
        id = 1715,
        copy = rest(HAMSTRING),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 10)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims hamstring.go; DB2 Discount Power On Miss
        known = knows(HAMSTRING),
        nobuff = "defensive_stance",

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            applyDebuff("target", "hamstring")
        end,

        handler = function()
            applyDebuff("target", "hamstring")
        end,
    },

    heroic_strike = {
        id = 78,
        copy = rest(HEROIC_STRIKE),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        -- Improved Heroic Strike: -1 a rank
        spend = function()
            return offensive_cost(talent, 15 - talent.improved_heroic_strike.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims heroic_strike_cleave.go; DB2 Discount Power On Miss
        -- The belief: paid at the main hand's next swing, which then brings no rage. Hekili's own simulation ignores
        -- onNextSwing: it spends the cost at the press and still adds the replaced swing's rage, so its forward
        -- projection is one swing of rage optimistic per queued strike until the belief's next drain corrects the
        -- belief (checkpoint Q9). Cleave alike.
        onNextSwing = true,
        known = knows(HEROIC_STRIKE),

        usable = function()
            return not buff.heroic_strike.up and not buff.cleave.up, "a strike is already queued"
        end,

        handler = function()
            applyBuff("heroic_strike")
        end,
    },

    intercept = {
        id = 20252,
        copy = rest(INTERCEPT),
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = function()
            return offensive_cost(talent, 10)
        end,
        spendType = "rage",

        startsCombat = true,
        known = knows(INTERCEPT),
        buff = "berserker_stance",

        -- The spell's own range check: exact, where target.minR/maxR are only the coarse bracket (VS.TargetRange).
        usable = function()
            return action.intercept.in_range, "target must be within Intercept's range"
        end,

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            applyDebuff("target", "intercept_stun")
        end,

        handler = function()
            setDistance(7)
            applyDebuff("target", "intercept_stun")
        end,
    },

    intimidating_shout = {
        id = 5246,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 25,
        spendType = "rage",

        startsCombat = true,
        known = knows({ 5246 }),
        toggle = "cooldowns",

        now = function()
            applyDebuff("target", "intimidating_shout")
        end,

        handler = function()
            applyDebuff("target", "intimidating_shout")
        end,
    },

    -- Classic also raised the simulated maximum health; the player's health is secret on Forever.
    last_stand = {
        id = 12975,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        talent = "last_stand",
        startsCombat = false,
        known = knows({ 12975 }),
        toggle = "defensives",

        now = function()
            applyBuff("last_stand")
        end,

        handler = function()
            applyBuff("last_stand")
        end,
    },

    mocking_blow = {
        id = 694,
        copy = rest(MOCKING_BLOW),
        cast = 0,
        cooldown = 120,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 10)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims mocking_blow.go; DB2 Discount Power On Miss
        known = knows(MOCKING_BLOW),
        toggle = "cooldowns",
        buff = "battle_stance",

        now = function()
            applyDebuff("target", "mocking_blow")
        end,

        handler = function()
            applyDebuff("target", "mocking_blow")
        end,
    },

    mortal_strike = {
        id = 12294,
        copy = rest(MORTAL_STRIKE),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 30)
        end,
        spendType = "rage",

        talent = "mortal_strike",
        startsCombat = true,
        refundOnAvoid = true, -- wowsims talents_arms.go; DB2 Discount Power On Miss
        known = knows(MORTAL_STRIKE),

        now = function()
            applyDebuff("target", "mortal_strike")
        end,

        handler = function()
            applyDebuff("target", "mortal_strike")
        end,
    },

    overpower = {
        id = 7384,
        copy = rest(OVERPOWER),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 5)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims overpower.go; DB2 Discount Power On Miss
        known = knows(OVERPOWER),
        buff = "battle_stance",

        usable = function()
            return buff.overpower_ready.up, "only usable after dodging"
        end,

        now = function()
            removeBuff("overpower_ready")
        end,

        handler = function()
            removeBuff("overpower_ready")
        end,
    },

    piercing_howl = {
        id = 12323,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        talent = "piercing_howl",
        startsCombat = true,
        known = knows({ 12323 }),

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            applyDebuff("target", "piercing_howl")
        end,

        handler = function()
            applyDebuff("target", "piercing_howl")
        end,
    },

    pummel = {
        id = 6552,
        copy = rest(PUMMEL),
        cast = 0,
        cooldown = 10,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        spend = function()
            return offensive_cost(talent, 10)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims pummel.go; DB2 Discount Power On Miss
        known = knows(PUMMEL),
        buff = "berserker_stance",
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function()
            interrupt()
        end,
    },

    recklessness = {
        id = 1719,
        cast = 0,
        cooldown = 1800,
        gcd = "spell",

        startsCombat = false,
        known = knows({ 1719 }),
        toggle = "cooldowns",
        buff = "berserker_stance",

        now = function()
            applyBuff("recklessness")
        end,

        handler = function()
            applyBuff("recklessness")
        end,
    },

    rend = {
        id = 772,
        copy = rest(REND),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 10)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims rend.go; DB2 Discount Power On Miss
        known = knows(REND),
        nobuff = "berserker_stance",

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            applyDebuff("target", "rend", REND_DURATION[knownRank(REND)] or 9)
        end,

        handler = function()
            applyDebuff("target", "rend")
        end,
    },

    retaliation = {
        id = 20230,
        cast = 0,
        cooldown = 900,
        gcd = "spell",

        startsCombat = false,
        known = knows({ 20230 }),
        toggle = "cooldowns",
        buff = "battle_stance",

        now = function()
            applyBuff("retaliation")
        end,

        handler = function()
            applyBuff("retaliation")
        end,
    },

    revenge = {
        id = 6572,
        copy = rest(REVENGE),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 5)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims revenge.go; DB2 Discount Power On Miss
        known = knows(REVENGE),

        buff = function()
            if buff.revenge_usable.up then
                return "defensive_stance"
            end
            return "revenge_usable"
        end,

        handler = function()
            removeBuff("revenge_usable")
        end,
    },

    shield_bash = {
        id = 72,
        copy = rest(SHIELD_BASH),
        cast = 0,
        cooldown = 12,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        spend = function()
            return offensive_cost(talent, 10)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims shield_bash.go; DB2 Discount Power On Miss
        known = knows(SHIELD_BASH),
        toggle = "interrupts",
        buff = function()
            return buff.battle_stance.up and "battle_stance" or "defensive_stance"
        end,
        equipped = "shield",
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        now = function()
            if talent.improved_shield_bash.rank >= 1 then
                applyDebuff("target", "shield_bash_silenced")
            end
        end,

        handler = function()
            interrupt()
            if talent.improved_shield_bash.rank >= 1 then
                applyDebuff("target", "shield_bash_silenced")
            end
        end,
    },

    shield_block = {
        id = 2565,
        cast = 0,
        cooldown = 5,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        startsCombat = false,
        known = knows({ 2565 }),
        buff = "defensive_stance",
        equipped = "shield",

        now = function()
            applyBuff("shield_block", nil, 2)
        end,

        handler = function()
            applyBuff("shield_block", nil, 2)
        end,
    },

    shield_slam = {
        id = 23922,
        copy = rest(SHIELD_SLAM),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 20)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims talents_protection.go; DB2 Discount Power On Miss
        known = knows(SHIELD_SLAM),
        equipped = "shield",
    },

    shield_wall = {
        id = 871,
        cast = 0,
        cooldown = 900,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        startsCombat = false,
        known = knows({ 871 }),
        toggle = "defensives",
        buff = "defensive_stance",
        equipped = "shield",

        now = function()
            applyBuff("shield_wall")
        end,

        handler = function()
            applyBuff("shield_wall")
        end,
    },

    -- Forever gave Slam an 18 s cooldown (DB2 category recovery) and a rank 1 at level 20.
    slam = {
        id = 1240193,
        copy = rest(SLAM),
        -- Improved Slam (12862, Forever DB2): the cast and the GCD 0.5 s and the cooldown 3 s shorter (wowsims's log:
        -- 1 s casts); at 2/2 Slam no longer delays the swing (its tooltip), and this kit models no delay either way
        cast = function()
            return talent.improved_slam.enabled and 1.0 or 1.5
        end,
        cooldown = function()
            return talent.improved_slam.enabled and 15 or 18
        end,
        gcd = "spell",
        gcdTime = function()
            return talent.improved_slam.enabled and 1.0 or nil
        end,

        spend = function()
            return offensive_cost(talent, 15)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims slam.go; DB2 Discount Power On Miss
        known = knows(SLAM),
    },

    -- Forever: a strike with a 20 s cooldown, an Arms talent (node 1310222; the DB2's level 1 is not the gate).
    spearing_strike = {
        id = 1310222,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 15)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims talents_arms.go; DB2 Discount Power On Miss
        talent = "spearing_strike",
        known = knows({ 1310222 }),
        buff = "battle_stance",
    },

    sunder_armor = {
        id = 7386,
        copy = rest(SUNDER_ARMOR),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, max(0, 15 - 3 * talent.improved_sunder_armor.rank))
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims sunder_armor.go; DB2 Discount Power On Miss
        known = knows(SUNDER_ARMOR),

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            applyDebuff("target", "sunder_armor", nil, min(5, debuff.sunder_armor.stack + 1))
        end,

        handler = function()
            applyDebuff("target", "sunder_armor", nil, min(5, debuff.sunder_armor.stack + 1))
        end,
    },

    sweeping_strikes = {
        id = 12292,
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = 30,
        spendType = "rage",

        talent = "sweeping_strikes",
        startsCombat = false,
        known = knows({ 12292 }),
        buff = "battle_stance",

        now = function()
            applyBuff("sweeping_strikes", nil, 5)
        end,

        handler = function()
            applyBuff("sweeping_strikes", nil, 5)
        end,
    },

    taunt = {
        id = 355,
        cast = 0,
        cooldown = 8,
        gcd = "off",

        startsCombat = true,
        known = knows({ 355 }),
        buff = "defensive_stance",

        now = function()
            applyDebuff("target", "taunt")
        end,

        handler = function()
            applyDebuff("target", "taunt")
        end,
    },

    thunder_clap = {
        id = 6343,
        copy = rest(THUNDER_CLAP),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, max(0, 20 - 6 * talent.improved_thunder_clap.rank))
        end,
        spendType = "rage",

        startsCombat = true,
        known = knows(THUNDER_CLAP),
        nobuff = "berserker_stance",

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            applyDebuff("target", "thunder_clap", THUNDER_CLAP_DURATION[knownRank(THUNDER_CLAP)] or 10)
        end,

        handler = function()
            applyDebuff("target", "thunder_clap")
            active_dot.thunder_clap = min(active_enemies, 4 + active_dot.thunder_clap)
        end,
    },

    -- Forever: usable within Victorious (20 s) after a kill that yields experience or honor; free, 30 s cooldown (DB2 402927).
    victory_rush = {
        id = 402927,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        startsCombat = true,
        known = knows(VICTORY_RUSH),

        usable = function()
            return buff.victorious.up, "only usable after a kill"
        end,

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            removeBuff("victorious")
        end,

        handler = function()
            removeBuff("victorious") -- confirmed in game (user, 2026-10-18)
        end,
    },

    whirlwind = {
        id = 1680,
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = function()
            return offensive_cost(talent, 25 - 3 * talent.raging_blows.rank)
        end, -- Raging Blows: -3
        spendType = "rage",

        startsCombat = true,
        known = knows(WHIRLWIND),
        buff = "berserker_stance",
    },
})

-- The execute phase: Execute's plain usability window (the target's health is secret on Forever).
spec:RegisterStateExpr("execute_phase", function()
    return reactive(EXECUTE)
end)

-- Queue prediction, ported from Hekili's Classic profile (Classic/Warrior.lua:462-575, without its debug lines): the
-- time to the next main-hand swing, and whether a strike queued now still leaves rage for the next Mortal Strike (or
-- Bloodthirst) and Whirlwind as they come off cooldown.
spec:RegisterStateExpr("mainhand_remains", function()
    -- out of combat no swing runs (nextMH is 0): anchor it at this evaluation, or its phase free-runs with the clock
    local mh = (nextMH == 0 and combat == 0) and now or nextMH
    if now == query_time then
        local real = mh - now
        return real > 0 and real or 0
    end
    if query_time <= mh then
        return mh - query_time
    end
    if mainhand_speed <= 0 then
        return 0
    end -- no swing speed read yet
    return mainhand_speed - (query_time - mh) % mainhand_speed
end)

local queueEvents = {
    { time = 0, spend = 0, priority = 1 },
    { time = 0, spend = 0, priority = 2 },
    { time = 0, spend = 0, priority = 3 },
}

local function byTime(a, b)
    if a.time == b.time then
        return a.priority < b.priority
    end
    return a.time < b.time
end

spec:RegisterStateFunction("should_queue", function(queue_cost)
    -- An unlearned strike or Whirlwind reserves no rage (none is at the beta cap of 30).
    local ms = knownRank(MORTAL_STRIKE) > 0
    local bt = knownRank(BLOODTHIRST) > 0
    local ww = knownRank(WHIRLWIND) > 0
    for i = 1, #queueEvents do
        local e = queueEvents[i]
        if e.priority == 1 then
            e.time = query_time + (ms and cooldown.mortal_strike.remains or cooldown.bloodthirst.remains)
            e.spend = ms and action.mortal_strike.cost or bt and action.bloodthirst.cost or 0
        elseif e.priority == 2 then
            e.time = query_time + cooldown.whirlwind.remains
            e.spend = ww and action.whirlwind.cost or 0
        else
            e.time = query_time + mainhand_remains
            e.spend = queue_cost
        end
    end
    sort(queueEvents, byTime)

    local spent = 0
    for i = 1, #queueEvents - 1 do
        spent = spent + queueEvents[i].spend
        local nextEvent = queueEvents[i + 1]
        if query_time + state:TimeToResource(rage, nextEvent.spend + spent) > nextEvent.time then
            return false
        end
    end
    return true
end)

spec:RegisterStateExpr("should_hs", function()
    return should_queue(action.heroic_strike.cost)
end)

spec:RegisterStateExpr("should_cleave", function()
    return should_queue(action.cleave.cost)
end)

-- The Classic settings the Arms and Fury priorities read (Classic/Warrior.lua:1574-1734, same defaults). Each
-- preference shows on the specs whose priority reads it (the trailing spec keys; none: every spec). Left out:
-- adaptive Whirlwind and Bloodthirst-in-execute (they need attack power and weapon damage, secret on Forever), the
-- unused queueing threshold, and the Overpower stance-swap settings (the dodge is unseen from another stance).
spec:RegisterSetting("adaptive_queueing_enabled", true, {
    type = "toggle",
    name = "Use Queue Prediction",
    desc = "When enabled, recommendations will use swing timers and rage calculations to determine if Heroic Strike or Cleave should be queued.",
    width = "full",
}, "arms")

spec:RegisterSetting("execute_queueing_enabled", true, {
    type = "toggle",
    name = "Queue During Execute",
    desc = "When enabled, recommendations will always queue Heroic Strike or Cleave during the execute phase.",
    width = "full",
}, "arms")

spec:RegisterSetting("ww_min_enemies", 2, {
    type = "range",
    name = "Minimum Enemies For Whirlwind",
    desc = "Select the minimum number of enemies before recommending Whirlwind over Bloodthirst or Mortal Strike.",
    width = "full",
    min = 0,
    softMax = 4,
    max = 10,
    step = 1,
}, "arms")

spec:RegisterSetting("ww_cd_diff", 1.5, {
    type = "range",
    name = "Whirlwind Cooldown Differential",
    desc = "Select the remaining time on Bloodthirst or Mortal Strike before Whirlwind can be recommended.",
    width = "full",
    min = 0,
    softMax = 2,
    max = 5,
    step = 0.1,
}, "arms")

spec:RegisterSetting("hamstring_threshold", 80, {
    type = "range",
    name = "Hamstring Rage Threshold",
    desc = "Select the rage threshold after which Hamstring will be recommended.",
    width = "full",
    min = 0,
    softMax = 100,
    max = 100,
    step = 1,
}, "arms")

spec:RegisterSetting("hamstring_cd_diff", 1.5, {
    type = "range",
    name = "Hamstring Cooldown Differential",
    desc = "Select the remaining time on Bloodthirst or Mortal Strike and Whirlwind before Hamstring can be recommended.",
    width = "full",
    min = 0,
    softMax = 2,
    max = 5,
    step = 0.1,
}, "arms")

spec:RegisterSetting("debuff_sunder_enabled", true, {
    type = "toggle",
    name = "Maintain Sunder Armor",
    desc = "When enabled, the Arms and Fury priorities will include Sunder Armor.",
    width = "full",
}, "arms", "fury")

spec:RegisterSetting("debuff_sunder_max_stack", 1, {
    type = "range",
    name = "Max Sunders",
    desc = "Select the maximum number of Sunder Armor stacks for Sunder Armor recommendations.",
    width = "full",
    min = 1,
    max = 5,
    step = 1,
}, "arms", "fury")

-- Forever default: Sunder Armor's own level in the DB2 (7386, level 10), so Sunder is on from the start; Classic's 61
-- kept it to raid bosses at level 60.
spec:RegisterSetting("debuff_sunder_min_level", 10, {
    type = "range",
    name = "Minimum Sunder Level",
    desc = "Select the minimum target level before recommending Sunder Armor.",
    width = "full",
    min = 0,
    max = 63,
    step = 1,
}, "arms", "fury")

spec:RegisterSetting("debuff_demoshout_enabled", false, {
    type = "toggle",
    name = "Maintain Demoralizing Shout",
    desc = "When enabled, the Arms and Fury priorities will include Demoralizing Shout.",
    width = "full",
})

spec:RegisterSetting("maintain_thunder_clap", false, {
    type = "toggle",
    name = "Maintain Thunder Clap",
    desc = "When enabled, the Fury priority keeps Thunder Clap on the target (Battle or Defensive Stance only).",
    width = "full",
}, "fury")

-- Fury's rage floors for the on-next-swing strikes (wowsims/forever's Fury APL dumps at 40 rage for both).
spec:RegisterSetting("rage_cap_threshold", 80, {
    type = "range",
    name = "Rage Cap",
    desc = "At or above this much rage the Fury priority dumps rage into Heroic Strike (one target) or Cleave (more), "
        .. "without holding rage for Bloodthirst or Whirlwind.",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "fury")

spec:RegisterSetting("hs_threshold", 40, {
    type = "range",
    name = "Heroic Strike Rage",
    desc = "The Fury priority recommends Heroic Strike on one target at or above this much rage.",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "fury")

spec:RegisterSetting("cleave_threshold", 40, {
    type = "range",
    name = "Cleave Rage",
    desc = "The Fury priority recommends Cleave on two or more targets at or above this much rage.",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "fury")

spec:RegisterSetting("prot_heroic_strike_rage", 50, {
    type = "range",
    name = "Heroic Strike Rage",
    desc = "The Protection priority recommends Heroic Strike in the single-target list at or above this much rage.",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "protection")

spec:RegisterSetting("prot_cleave_rage", 40, {
    type = "range",
    name = "Cleave Rage",
    desc = "The Protection priority recommends Cleave on three or more targets at or above this much rage.",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "protection")

spec:RegisterSetting("challenging_shout_loose", 3, {
    type = "range",
    name = "Challenging Shout Enemies",
    desc = "The Protection priority recommends Challenging Shout when at least this many enemies attack someone else.",
    width = "full",
    min = 1,
    max = 10,
    step = 1,
}, "protection")

spec:RegisterSetting("wowsims_recklessness", false, {
    type = "toggle",
    name = "Recklessness (wowsims.com)",
    desc = "The wowsims.com priority's Recklessness ON/OFF switch (its default in wowsims's own APL).",
    width = "full",
}, "arms")

spec:RegisterSetting("wowsims_stance_dance", false, {
    type = "toggle",
    name = "Stance Dance (wowsims.com)",
    desc = "The wowsims.com priority's Stance Dance ON/OFF switch (its default in wowsims's own APL).",
    width = "full",
}, "arms")

spec:RegisterSetting("wowsims_hamstring_weave", true, {
    type = "toggle",
    name = "Hamstring Weave (wowsims.com)",
    desc = "The wowsims.com priority's Hamstring Weave ON/OFF switch (its default in wowsims's own APL).",
    width = "full",
}, "arms")

-- The four priorities (Arms has two, Arms (wowsims.com) and Arms, until the swap), written by `make packs`
-- (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and run it, never these blocks
-- (tests/Forever/warrior_spec.lua checks they match). Pick one with /hekili priority <name>.
spec:RegisterPack(
    "Arms (wowsims.com)",
    20261020165,
    [[Hekili:1Mv3UTTnu4NLCJNnAMSDCs3squaYWWWYWw3qDb2DsMwKoIZYscKuXlaf(zFhsjlrslklLMDrnuTo878)HFhNG5bFjyjgjibF6Qzx9X5ZUA28pEtWsXR5KGL5OOTONHhsr7GpFKTJFy149z750DCVOSDtKY8AsgclXzDbnr8uAW6wHKNtIcw(3p(5p)0F(57qawblJPymP8aeEuRA4UdReXKdRQ(UPBYyKxiSdRWKnOIeXHvp(x)(HvWxdpvE8c6uPY4t3JymAgBkoNpfLNaFac4bp59p8S0jxcqZqP8eWyXWZzsvrbeqyCw63bpSL8k37WQFgjq31Ijm(pE6laiXcro)UPtFMkIlwlT6PwIobWeSu8If3UygE21ZwmZdcDSSn0eiWIIe0SuUxoJahEns4VMW4e2wclKbjGlHxKxKKecV5AVBo8BNCGp4pncjfq9IWekxCPmP5dseQokxGsJiTF01jzzyLIk4KWSnBcFoc7pxxTlCCsKqKqc5XzfIEi(zSXDzV0yH(TlmVifdHfitMXUKUXxkWlKqskzhLW9NxFENQlcdb1ikkHRllMGeXH7P8y9VfS9Tjeopf(NuBCIqqtFM7vLGd1fq)G89esoije3z0TeUvK9ed)bdd)yyvLZo9OJV4e7Ou0qS8ZrxSUyZgpdq8kYNORbi6jqjvwxREMoIMHKu8LBYIk4(xvAmK)LeviGCymItgn(IszT0)20S9PFTDdBeMOEHeA4JDiAk)E)5E3yyYqXblpBpHvP9QqXG1wNHHUJSgz4CcI1KHFNcfgwxZuaNvcDxi8gmGQIN6GnuHJWVcVz0ydN7RJRGwL0ui2wA8bzw00RG5T76QaQcxPyEriU4E7cHHcWdYsPrJL2tmkfhczoc(7R)Vvw6K79hp7dZ8wyAT7JPSK9uOMFinjvgK8mg22qAYptpURsnRAgJKT97K57XoY39mbx2NAgZIsiOxAZLSN5nsEPJxubdqestxpZaMyclJgDS)QLPGMHatSU1elxxXb4OFU7VDwBPi11BsvoUooBm5OkihLLLGHhSE5XwbvKA0zgExh2Rl8QI91G38cdGNmzKrhT0M1ssdk02HtAfMxyeVa(pQBNJsq5NdNlQkM0pJCmJDjHrNV1L)DGVbbeDkq(NPVRN3a4zWAXpkgXAR46nmb2Hka3NMkiSisUOl9mW()gT1WlYx1TeUPG9QPMAt4M7PGGwVeNuWiBr9t0KcGzfqE75yHRdOxuCc9WQIm9V2dC(OT3d0Odwct94aiwRQi5kYvBgvUJb84NuBkrsrRti4GFkyzeJcjdkQK9Uod0J85bzS4FwICy52u6MuGaSalf0lqAcwsiw4aIgUTsPU2Hu6uz19Vo58kb8gla1YtY4wTcS5e7oi(WCjUFSN4A0bPd6BKNSu3)GJGKXKMoJs6AsI4p6SaAq0ghmfA9eCkoyPI4KSCdSPB7WMgUn0OPA2e1QtLqNpBOr1UtGkmTBmRR2m5N)EhWvvjZTBADwIAn51WA(g4W)TsIVNK8QyXRCz7HmUdRvqBsKxlbbFVz54C7rt9h7bZXVt7WEI2rrRPEnOo)52dYocxLlPdMHxQoS9KOHpf8DDrI3YMe9Sk74Qek32ECPl3UCxdd)1(UKt3YqPb7HFU0Gbx5UQjpzbe1162Z8CM)oUHIUkS2nrbORbE6e)nmZUxA59zRL))wBr5Z9DoRZC1q2OrPrxCP0xxPVkOVR6OuSl6zg8f7NIb8eYFM5QFa22OX28B2ced9UPTBSu1KVvcQwlFvZs1obQBhlATPOrZTWH11X1BjAHP6WCb5wyLHuJCrlr1ZLZ6yRK6CMMoBrdohhQ2d9BMjxlPBxASEP02v6qVfP0)12RzaoFZARdXbA2EnOLDOCDQYLyBRw05j02L1klx1Cmex11T9NLXSsZOcrSSK8xjBPj0dRg)lv)HQuVo4)(d]]
)
spec:RegisterPack(
    "Arms",
    20261020413,
    [[Hekili:LN1wVTTnu4Fl5fVeKunRCPBDiYaDdyyTp0bepG(MKPLoYIW0IAKuXjdg(3(i1fkQ7kPjBdlpKwfXZLVZHhYZNoX129pCxgGeG7xUC(LV3E(LZV2(k3LIhta3Lji)TOnYhIr7K)7hz74Qx(iHIcukUofteFk2DDN2GNa(Ul)6hV7Up9739tOmLJWbbqUcaxU6VszW9a74kLTpU6RigdtzxCCvcLjGGJRcz0Dhx9BWwmb)Dsj(fcIZX(LkKOehlE0sIlgnetKWe5lW0yUvcd8P7wJeoYFeeWJhrtfxGdDwNggAz(slgSdHJ536yp)4NBzGZD(E)ieBdCrkh8OHHEB8dCS1s6WtJdaMNmgLGx6aoie44nCRaq5lVI1Hy0Aceml)TwMAzXfYK9T9O4o0dEzcm7KcDHhsOsSKRBAYmHcEclImBsw0N)3HJ9YKqJCzKfastGi4)sQqvkQPfusLTOoikrsB9L4X0b(icXl)x9iyU4cv1KJpLscO7J5zBiuo)q9qi7)o)ktdXsJBBh4bWpvakRu8OxseIdJQiJkqQxvTFRHKdFpajzXJGH3c8677kFP05EqMmGDyGVWUdRKLBrIiV9yEu3RllW2saopw(tLefXHteWOy)cmmgeCSND6PNO32qbOKSL)ZuifuHs5(wP)TKBBcePW8LNaw4WKN4Te4DGNG6D9LhMGjv76KaVi(zhoT2MWmTYLVUPUNDwR4wvYqa09JgYlEvc5BM)ec5CG(sf2fpvTuznQZ9yFbL9Ohl1SuQCzPQ4ybW8Her7Kw(TDaJdSTYlbK3Je7dQ7mYnJLwv5tEmu8gy2jflXG4a9B70VV1Qrnc93ufPgXTQO4IqQFk35YwDt1fxfDhYQGQ6UADtNMKk5aKq3dSc7A3Pu7JWmYES07TZYvnS2VpRpxXchErY9Mg3pWlahgoL8F9TSBUDy3CEhEP7DGAQ3PesUxiwvdSULHG2zUpQarekoWtQmeSy(m9l05H6I8U5wxn70Y7kQhtBJLX5HrYRfAQaILpIloKLW8tzYQgX7QTkLlw40PNul1DAkcTtjt8gDvQQ4jmL9OQa9Bb4Qc5ZQSGUWSP2vlutZXr7y(xxQO1QSIz2qoFa1mt9l6qoredK3Nqc6e8RjuAGYeTVo00W3(H5DR(ZJGUPfA0FRnooPV(Gh)S7s59pCPHA8fmkYIC1h6u6i5ZFj7tMkoH7(ZLFUH0egTODfsl1qodaPmIwpD7x3L(YpLbyyK6lREz6zRaYvtei1ALBcM)HAIpLBun6I)mANPYgxpXSrEtZ(tdVA91FcPHYg7pZuXnnsfnl)MAl9QKMAj3Lz9uuhaK(499CAr3XxlUTs8FOhX13LnWgsVuaE94amL9QxasaQmZp2tMPMvuc(HEeSbLaLO2Z7Tc4vGmWynvBXg45thWiQLIxVI0UVlW196ADsyY0gglehH3WOehYWFZgldI)Xa0)IejYcMP2CstWWm4AqTiZGnVFxBad2e9EvxtQgzwS51K9cXgTRn9sVKpKEqOggAikLigIEH5WcnTSod)F0rn2fvOYyQ9OdhkYEIJGSlQpgB7Qjo29ihn4a0yYL5mc9YNgUEoEDXQOYr16mB0PS(ijRz5cv6Qf9uuxtwnR0spe7HkUE2hoMkj38XNNJOYWRd882MA6KtM))NAAZdULHE1rdH5jWNqPuZr7puAC47UkhT)q41Ca)zGwcBuQisDhE(FuRJRoT4pc2zzl7(3d]]
)
spec:RegisterPack(
    "Fury",
    20261020900,
    [[Hekili:nNvuZTjoq4FlPp4lzAmX29AV2oHmt7dDU2h6nt9ntFdSmimAmGyKe2jDYWV9Bxbgeyi2yNETp4uBPD)2pTRy1NOotD(xN5(ef15RZMm7ntNmBY7MmXzU6HuQZ8uI3AYk4ljKy4VFkt8ao4drCIp64YmwK6Zjol7edzk1Zz(3)W3(2N)NV9(aTZHmFFAHdujm7N4c6gQiFbID(IVtecgx8(8fQqA(Imjv8hY8fP4GmfyWLyegpDY4PV9QRZxei4X5l(ivagUgHzUIK4rHz2YuH5lqSbVilzrA33Y3kzXYBckclIDrGfCfrX4j5l8isfm8L(Cp5ncQKseEH3uh2X4cz8g54sSSI9HW9IpaRl)DeQCQxCLfKUe8aweK9iEyaKwPcQhpEjrzdFuruxziptDnlWEzwqGL5GwcAmHLiV1E6K8VShaV0(gVqIyf9Air5YdcCx55BpTBlzjkQWJMQAACDC3LeDL6COvw6OcCSQCf(MRGKSIo6IYPe0e)QrRcS9gMNIlEWvKjdVoG7LjnOfqgoK8t5BPIDtU3YFhhm9cRzqy2ZhFAanrY20JBHubN5bZjyRRDEVSa6aabnHgZOGfJeWw)7SLuLILSsAH)01JK6QcHTfH8i)dfKzdpiHYA4hD5US8Yio3xfYesL16e(2Kh94GbWxAmv5UL7W)gss8Dlh4rmiwEzcOAPgxIzdcB5XLQ7S7iC4exvZKTWOrBzqrVfpQN45If1iQ5GzY2lIs2C0LY7gyPSb6hSgUp6f())vDSiA)YkGDf(NOYH9lWC4f92Z5cFQEoDNLMpilZs8bBjIyUabPkJx4IB580eYYiQ)OsGm9YcIJ36B7XXyY9UAdQib9(uou(l8fiNc72QSIGgrr31x8JH(HAlASPIef5w8t3iMuDnEKQ9USVu3lJlLp2mc6)5LVYeivyru8IiPnscynsbFCnTy0Ht0MM3kH7tH1njI9dia1ht1EzJwPNSkZVd699Vvam2OAoC1giZbP3t9YuuKbLF1nnKiPn6ctIXwjjRQoBarbpXwVIB43j)yP9uRxFAprP9SX6VvDP7MnDrXrpffV1EI10h7MFJ6NFA32R8Gp1VpVm7fC77M09Is7kySIebMzXIbXqBO(UnTWA32MFhkidrs2VCcBv1)Wglqmfnw2XK6NKjQq3Tmzy3Zl3sPP6Ns1Nelp8PE5FXzoOItcq1s3p2EtIxpOkaWp(Q(MgLvANpUtoSZ8kI7OaC6XOA6Jw9QwwzWvmovE1ErbmcUfbvWif2yUCaCvyCcizrQNIVMsBDMRfjGg3b5RdwNkBRHSsnCt8AVmBHxhQERHSuQCta)ZEwsneHz4YEj2(sFhJyzKaVEqey25qGJvi9avGnurSdqj2GKInuE0ssgwmEtpfJcfDNY2GJrOng5)64I8aQ)NNi8NJ9aNPm8ZV4FecXXC)B7j3JYTnZVhw3yPaDe031dOMsVnb)3DH74AA6K(B)Ic17wPUXM5wc(lox0T4nPvFYigP(oQXuzENPVNjj)As0)rVT1W)uvYbExaDKBFo3UiB84J2U(o(QAxU2Q(oJPu7Vj5BCDaTZ91tS6Ef7Dk8PD)IZsE4b1hQxkTBY2NiP27tA3K9eV8XjE7dn1B3JQxQV76jMCU1ft0a2x)PM3dXeLZ)gl)8lXZA3HQAzzCFLELHoKlZ8tFTOW3tE57Q(PeFFsRSU0M33wQI3N(qUKr1lhFF(C(VrDDQbqMKPcXJq)B6AwelFXLL))MuK7C(Vd]]
)
spec:RegisterPack(
    "Protection",
    20261020023,
    [[Hekili:9IvBVTTnq4Fl9lzjyzQ2ojDBbrbODdfPdDzfrbiFts0s0weHw0GKkgEiq)23DKYYuVg71HHI2gtE3ZD85EoYZjCA4JHbPenn8(ztM9HPtMnzYSlcd0BxtddwtsEMSe(HCYk4F)MuOPjAMih3Alxqsr3NxW46VKhoVxKuRPjHbp9XhE4l)1dxV2bImwAk16gvb28zHK(cvwgVpoLXprKsMqEDz8VtxqZvSxOLXbAsEc98Y4hjf56Y4nzuWuDgSLMixsHL0fYCvzmzdzlyhelkpTm(tCrYZLXptxdMuSg25biK5lbhj5P7TlGtwHUvKNIj0hLReW)P0aFqHT1IY4RG9VJkfSemFKSNbmqJ(noLG54gMoRkNKemazmnKqZLS8LELX3dqKU7ePGJ3xjkT9KL6KWpr48QC7okHRZuArofpysAf6R5KTu5paRLym(0nInk2k4ZlHQHYy1ki3agkZabaVIMirwcxSI2pdsQplfGLv()(f2nqKDRiF8BFfcIeYDjfQciiCKJt4eL6NseRwZPwlFKOaY(QZUUtbGaX(Yj7ygK2S0vD1iNsGfLus62QJVH92WYtfBG8pRqBkE4o2QFUyxjDxvdsrjvLHfmmEtH4PSbJtvQZRW1QAYGqb2WzgY9060LOq66pHKgkBM0FZoz3zwyxiskaxM6b9esXcghAuigQs5Twsb(yor7d)vZPrQmbK4Sf(VBEXIfEUR6vSU8p644p6)(KmusFEHIgjwSiAzsQ)0(TSwpfPSnin8zFyBBNBO9vMJE0C8KBoBordIXklvenhzIQ9rKTmOhxaQyhZ)ViLay0iHxhUoy4e8tExk1GOBI2cnGr5CqNHBxxrQXqOO36ROAnSTYRJTrglCHBhJHs7U5MjzCnXZCnYnZo5uu97LuiH(i9T(xo5vlxiTnbrfkYCoYeNKieCq3NVBl4)xry5QB8N6D1zU5YlSeTqUnswOYCxhISifJx3e0nlUz2KgEDuQwWbzrEK9trCMsFo(UHprqrNX1H6lnNUIrv36FXB6OciD(EQ2Z(z)ksO967Rek427E2foGPMtrLcb)CJUU94yUbjIGx7JEu5G7YvvXRETV92xEM0d66mRTWfMRDZh317pVsPa6eo7VBOCR1QwCIqRSsvAoQGsR7j66F)XjrKdDAkSAy6Zh4UNA7ZmVdcTU4ZGJRWCATWzbIA4AK59GXRh73g0v(hix(AL4lvOBS1nnfLnWEq((aztleDeR2L7vPA3kXmaXXXIwFArFvrQb3fgaVOJf2wtPHnDkCyolNd)09MrdRuqHFA3JAHbvNOqnaXaM4C6qZUyqKYtddsKmnvYiHbTAmrxVCOi4CQCHySo13QvfJ3vdepxrtFPCl9gc1hgaQUYgxa)oBMXa)ZTcSJscRQ1jsRUC01F5aDTrxRB6FCT6yi)1dPcRH)ea65X0Lhzj61d8oHX05JxkFZc1W9f1DydQ)B2H1w2oyj3CpXHwWCUvzmbD3kfmnhPGRhRA5mMzyGzWo02E469PQZuE7XXDmVMa1MDhItAp6zJs4qdNowTXmSQtU0jY9EKgAW1XUvQZWP9I9bnqBFf4Hym3PzDJ4XmQ7)YzD77(TDPL7SVhZLz1ZgpuFbmv8y3u5opCxXtRPLrGGNAgsJ38UhyizNBfAoIS9n7i7Vzg8Qre4bFZEeFREX304w)TjhR19OpVTBPh82jZ309)JEx77jf6mC6H7OpZ4m4B9V73eIz7W)j]]
)
