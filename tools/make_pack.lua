-- tools/make_pack.lua: prints the Forever Warrior's priorities in the share format RegisterPack takes ("Hekili:" +
-- LibDeflate print encoding of the AceSerializer'd package), one line per pack in PACKS order, built headless with the
-- vendored libraries. Run from the repository root:
--   lua5.1 tools/make_pack.lua
-- Edit a pack's SimC-style text below, run it, and paste each printed string into its spec:RegisterPack( ... [[ ]] )
-- in Forever/Classes/Warrior.lua (Forever/spec/warrior_spec.lua fails until they match). Loaded with the argument
-- "lists" (loadfile(...)("lists")) it returns PACKS with each pack's parsed lists instead, for that spec.
-- The Arms and Fury lists are ported from Hekili's Classic profile (origin/classic:Classic/APLs/WarriorArms.simc,
-- WarriorFury.simc); the Protection list's shape is archive/TheWarWithin/Priorities/WarriorProtection.simc's.

local DATE = 20261016

-- Shared by Arms and Fury (Classic's head of both lists). Forever changes: the execute phase is the plain usability
-- read (`execute_phase`), the target's health being secret; `cooldowns` is defined (Classic called it undefined) and
-- called on bosses and on targets 3 levels above (Classic: target.level>=63 at level 60).
local HEAD = [[
actions.precombat=battle_shout,if=!buff.battle_shout.up
actions=sunder_armor,if=settings.debuff_sunder_enabled&debuff.sunder_armor.stack<settings.debuff_sunder_max_stack&!debuff.expose_armor.up&target.level>=settings.debuff_sunder_min_level
actions+=/demoralizing_shout,if=settings.debuff_demoshout_enabled&!debuff.demoralizing_shout.up
actions+=/call_action_list,name=cooldowns,if=boss|target.level>=level+3
actions+=/run_action_list,name=execute,if=execute_phase
actions+=/run_action_list,name=rotation
]]

local PACKS = {
    {
        name = "Arms",
        desc = "Forever Arms Warrior, ported from Hekili's Classic Arms priority.",
        simc = HEAD .. [[
actions.cooldowns=sweeping_strikes,if=active_enemies>1
actions.cooldowns+=/death_wish
actions.cooldowns+=/recklessness
actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
actions.execute+=/execute
actions.rotation=victory_rush
actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
actions.rotation+=/overpower
actions.rotation+=/whirlwind,if=active_enemies>=settings.ww_min_enemies|(!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=settings.ww_cd_diff|settings.adaptive_queueing_enabled&rage.time_to_55<cooldown.mortal_strike.remains+settings.ww_cd_diff)
actions.rotation+=/mortal_strike
actions.rotation+=/spearing_strike
actions.rotation+=/slam,if=!talent.mortal_strike.enabled
actions.rotation+=/rend,if=!debuff.rend.up&!talent.mortal_strike.enabled
actions.rotation+=/hamstring,if=cooldown.mortal_strike.remains>=settings.hamstring_cd_diff&cooldown.whirlwind.remains>=settings.hamstring_cd_diff&rage.current>settings.hamstring_threshold
actions.rotation+=/bloodrage,if=rage.current<90
actions.rotation+=/battle_shout,if=!up
actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
]],
    },
    {
        name = "Fury",
        desc = "Forever Fury Warrior, ported from Hekili's Classic Fury priority.",
        simc = HEAD .. [[
actions.cooldowns=death_wish
actions.cooldowns+=/recklessness
actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
actions.execute+=/execute
actions.rotation=victory_rush
actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
actions.rotation+=/overpower
actions.rotation+=/whirlwind,if=active_enemies>=settings.ww_min_enemies
actions.rotation+=/bloodthirst
actions.rotation+=/whirlwind,if=!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=settings.ww_cd_diff|settings.adaptive_queueing_enabled&rage.time_to_55<cooldown.bloodthirst.remains&cooldown.bloodthirst.remains>=settings.ww_cd_diff
actions.rotation+=/spearing_strike
actions.rotation+=/slam,if=!talent.bloodthirst.enabled
actions.rotation+=/rend,if=!debuff.rend.up&!talent.bloodthirst.enabled
actions.rotation+=/hamstring,if=cooldown.bloodthirst.remains>=settings.hamstring_cd_diff&cooldown.whirlwind.remains>=settings.hamstring_cd_diff&rage.current>settings.hamstring_threshold
actions.rotation+=/bloodrage,if=rage.current<90
actions.rotation+=/battle_shout,if=!up
actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
]],
    },
    {
        name = "Protection",
        desc = "Forever Protection Warrior (provisional): Defensive Stance, Shield Block up, Revenge and Shield Slam, "
            .. "Sunder Armor stacked to 5, Heroic Strike or Cleave with spare rage.",
        simc = [[
actions.precombat=battle_shout,if=!buff.battle_shout.up
actions.precombat+=/defensive_stance,if=!buff.defensive_stance.up
actions=shield_bash
actions+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
actions+=/victory_rush
actions+=/shield_block,use_off_gcd=1,if=!buff.shield_block.up
actions+=/bloodrage,use_off_gcd=1,if=rage.current<20
actions+=/battle_shout,if=!buff.battle_shout.up
actions+=/run_action_list,name=aoe,if=active_enemies>=3
actions+=/call_action_list,name=generic
actions.aoe=demoralizing_shout,if=!debuff.demoralizing_shout.up
actions.aoe+=/revenge
actions.aoe+=/shield_slam
actions.aoe+=/cleave,use_off_gcd=1,if=rage.current>=40
actions.aoe+=/sunder_armor
actions.generic=revenge
actions.generic+=/shield_slam
actions.generic+=/sunder_armor,if=debuff.sunder_armor.stack<5|debuff.sunder_armor.remains<3
actions.generic+=/heroic_strike,use_off_gcd=1,if=rage.current>=50
actions.generic+=/sunder_armor
]],
    },
}

-- One SimC-style line into its list and entry: actions[.list](=|+=/)action[,name=list][,use_off_gcd=1][,if=criteria].
local function parse(simc)
    local lists = {}
    for line in simc:gmatch("[^\n]+") do
        local list, body = line:match("^actions%.?([%w_]*)%+?=/?(.+)$")
        assert(body, "bad line: " .. line)
        list = list == "" and "default" or list
        local action, opts = body:match("^([%w_]+),?(.*)$")
        local e = { action = action, enabled = true }
        local criteria = opts:match("if=(.*)$")
        opts = opts:gsub(",?if=.*$", "")
        for k, v in opts:gmatch("([%w_]+)=([^,]+)") do
            if k == "name" then
                e.list_name = v
            elseif k == "use_off_gcd" then
                e.use_off_gcd = tonumber(v)
            end
        end
        e.criteria = criteria
        lists[list] = lists[list] or {}
        table.insert(lists[list], e)
    end
    return lists
end

for _, p in ipairs(PACKS) do
    p.lists = parse(p.simc)
end

if ... == "lists" then
    return PACKS
end

_G.strbyte, _G.strchar, _G.strsub, _G.strfind, _G.format = string.byte, string.char, string.sub, string.find, string.format
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
local LibDeflate, Serializer = LibStub("LibDeflate"), LibStub("AceSerializer-3.0")

for _, p in ipairs(PACKS) do
    local pack = {
        type = "package",
        name = p.name,
        date = DATE,
        payload = {
            spec = 1491,
            builtIn = false,
            hidden = false,
            date = DATE,
            version = DATE,
            author = "Hekili (Forever)",
            desc = p.desc,
            profile = p.simc,
            lists = p.lists,
        },
    }
    print("Hekili:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(Serializer:Serialize(pack), { level = 5 })))
end
