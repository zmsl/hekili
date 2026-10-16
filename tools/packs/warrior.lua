-- tools/packs/warrior.lua: the Forever Warrior's priorities for tools/make_pack.lua (its default class): the pack
-- date and pseudo-spec, and each pack's name, description and SimC-style text.
-- The Arms and Fury lists are ported from Hekili's Classic profile (origin/classic:Classic/APLs/WarriorArms.simc,
-- WarriorFury.simc); the Protection list's shape is archive/TheWarWithin/Priorities/WarriorProtection.simc's.

-- Shared by Arms and Fury (Classic's head of both lists). Forever changes: the execute phase is the plain usability
-- read (`execute_phase`), the target's health being secret; `cooldowns` is defined (Classic called it undefined) and
-- called on bosses and on targets 3 levels above (Classic: target.level>=63 at level 60).
local HEAD = [[
actions.precombat=battle_shout,if=!buff.battle_shout.up
actions.precombat+=/charge
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
        simc = HEAD
            .. [[
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
        simc = HEAD
            .. [[
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

return { date = 20261016, spec = 1491, packs = PACKS }
