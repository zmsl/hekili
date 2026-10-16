-- tools/packs/druid.lua: the Forever Druid's priorities for tools/make_pack.lua (lua5.1 tools/make_pack.lua druid): the
-- pack date and pseudo-spec (Forever/Classes/Druid.lua's DRUID_SPEC; regenerate the strings when it changes), and each
-- pack's name, description and SimC-style text.
-- Ported from Taco Dog Forever's src/TacoDogForever_Druid/APLs/feral.simc (Nerdegghead's priority, via the user),
-- bear.simc and balance.simc (after the guides they cite), with Classic's precombat buffs
-- (origin/classic:Classic/APLs/DruidFeral.simc). Left out on purpose: Tiger's Fury, powershifting and the
-- cat_ps/innervate_or_shift lists, Omen of Clarity's precombat line, `ttd` guards (target health is secret), Faerie
-- Fire in cat, the ranged Moonfire opener, and the consumables.

local PACKS = {
    {
        name = "Feral",
        desc = "Forever Feral Druid (cat): Shifting Power below 50 energy, Rip at the set combo points and Rake as they "
            .. "fall off, never clipping, the rest into Shred (Claw when the target faces you), holding the energy the "
            .. "refreshes need (excess_e).",
        simc = [[
actions.precombat=mark_of_the_wild,if=settings.buffs&!buff.mark_of_the_wild.up&!buff.gift_of_the_wild.up
actions.precombat+=/thorns,if=settings.buffs&!buff.thorns.up
actions.precombat+=/cat_form,if=!buff.cat_form.up
actions=cat_form,if=!buff.cat_form.up
actions+=/shifting_power,if=energy.current<50
actions+=/use_items
actions+=/berserk,use_off_gcd=1
actions+=/rip,if=combo_points.current>=settings.rip_cp&!debuff.rip.up
actions+=/rake,if=!debuff.rake.up
actions+=/ferocious_bite,if=settings.bite_finisher&combo_points.current>=5&debuff.rip.up&excess_e>=energy.current
actions+=/shred,if=shred_ok&excess_e>=action.shred.cost
actions+=/claw,if=!shred_ok&excess_e>=action.claw.cost
]],
    },
    {
        name = "Guardian",
        desc = "Forever Guardian Druid (bear, provisional: bear rage income and decay are unmeasured): Demoralizing "
            .. "Roar, Lacerate to 5, Primal Bite on cooldown, Maul and Swipe with spare rage.",
        simc = [[
actions.precombat=bear_form,if=!buff.bear_form.up
actions=bear_form,if=!buff.bear_form.up
actions+=/run_action_list,name=aoe,if=active_enemies>=2
actions+=/berserk,use_off_gcd=1
actions+=/use_items
actions+=/demoralizing_roar,if=!debuff.demoralizing_roar.up
actions+=/lacerate,if=debuff.lacerate.stack>=5&debuff.lacerate.remains<=4.5
actions+=/primal_bite
actions+=/faerie_fire,if=!debuff.faerie_fire.up
actions+=/lacerate,if=boss&debuff.lacerate.stack<5
actions+=/maul,use_off_gcd=1,if=rage.current>=action.maul.cost+action.primal_bite.cost|!action.primal_bite.known
actions+=/swipe_bear,if=rage.current>=settings.dump_rage
actions+=/enrage,use_off_gcd=1,if=settings.use_enrage&rage.current<action.primal_bite.cost
actions+=/frenzied_regeneration
actions.aoe=demoralizing_roar,if=!debuff.demoralizing_roar.up
actions.aoe+=/berserk,use_off_gcd=1,if=active_enemies>=3
actions.aoe+=/use_items
actions.aoe+=/primal_bite
actions.aoe+=/swipe_bear
actions.aoe+=/maul,use_off_gcd=1,if=rage.current>=action.maul.cost+action.swipe_bear.cost+action.primal_bite.cost|!action.primal_bite.known&rage.current>=action.maul.cost+action.swipe_bear.cost
actions.aoe+=/faerie_fire,if=!debuff.faerie_fire.up
]],
    },
    {
        name = "Balance",
        desc = "Forever Balance Druid (provisional: mana is never readable and Eclipse's charge rule is unconfirmed): "
            .. "Moonkin Form, Moonfire and Insect Swarm kept up, Starfire on Eclipse charges, Wrath to fill, Hurricane "
            .. "on many targets.",
        simc = [[
actions.precombat=moonkin_form,if=settings.moonkin&!buff.moonkin_form.up
actions.precombat+=/mark_of_the_wild,if=settings.buffs&!buff.mark_of_the_wild.up&!buff.gift_of_the_wild.up
actions.precombat+=/thorns,if=settings.buffs&!buff.thorns.up
actions=innervate,if=settings.innervate&mana.current<action.starfire.cost*2
actions+=/use_items
actions+=/call_action_list,name=aoe,if=settings.hurricane_targets>0&active_enemies>=settings.hurricane_targets
actions+=/moonfire,if=!debuff.moonfire.up&(boss|settings.trash_dots)
actions+=/insect_swarm,if=!debuff.insect_swarm.up&boss
actions+=/starfire,if=!moving&buff.eclipse.stack>=1
actions+=/starfire,if=!moving&settings.starfire_filler
actions+=/wrath,if=!moving
actions.aoe=moonfire,if=!debuff.moonfire.up
actions.aoe+=/hurricane,if=!moving
]],
    },
}

return { date = 20261015, spec = 1499, packs = PACKS }
