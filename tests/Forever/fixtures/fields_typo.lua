-- tests/Forever/fixtures/fields_typo.lua: a pack's registrations with one deliberate mistake each (refactor plan lane 3,
-- the plan's four examples and one per kind), for tests/Forever/fields_spec.lua. Each entry: the Register* method, its
-- arguments, and the check and field the failure must name; `at = "finish"`: it fails at the end of the load
-- (Fields.Finish), not in the call; `listed`: it fails nothing and is listed; `passes`: a valid one, neither failed nor
-- listed by V5; `pre`: a registration made first ({ method, args }).
return {
    {
        what = "an expects value not in the list",
        call = "RegisterAbility",
        args = { "typo_strike", { id = 990001, startsCombat = true, expects = "debuf" } },
        check = "V2",
        field = "expects",
    },
    {
        what = "a field one edit from a registered name (two letters swapped)",
        call = "RegisterAbility",
        args = { "typo_refund", { id = 990002, startsCombat = true, expects = "none", refundOnAviod = true } },
        check = "V1",
        field = "refundOnAviod",
    },
    {
        what = "a regen entry naming an aura no registration declares",
        call = "RegisterResource",
        args = { 1, { typo_pause = { aura = "bear_from", mult = 0 } }, nil, nil },
        check = "V3",
        field = "aura",
        at = "finish",
    },
    {
        what = "a combat-starting ability left on the default landing evidence",
        call = "RegisterAbility",
        args = { "typo_default", { id = 990004, startsCombat = true } },
        listed = "unlanded",
    },
    {
        what = "an unknown key on a regen entry (a belief-only table)",
        call = "RegisterResource",
        args = { 1, { typo_tick = { value = 1, intervall = 2 } }, nil, nil },
        check = "V1",
        field = "intervall",
    },
    {
        what = "an unknown key on an fsr (a belief-only table), two edits from any name",
        call = "RegisterResource",
        args = { 0, nil, nil, { fsr = { spiritual = 1 } } },
        check = "V1",
        field = "spiritual",
    },
    {
        what = "an aura field of the wrong type",
        call = "RegisterAura",
        args = { "typo_aura", { id = 990005, duration = "long" } },
        check = "V2",
        field = "duration",
    },
    {
        what = "a meta share above its bound",
        call = "RegisterResource",
        args = { 3, nil, nil, { refundOnAvoid = 1.5 } },
        check = "V2",
        field = "refundOnAvoid",
    },
    {
        what = "a declared landing evidence its fields contradict",
        call = "RegisterAbility",
        args = { "typo_travel", { id = 990006, startsCombat = true, expects = "travel", school = "fire" } },
        check = "V4",
        field = "expects",
        at = "finish",
    },
    {
        what = "ticks on an aura that declares no tick_time",
        pre = { "RegisterAura", { "typo_dot", { id = 990010, dot = "debuff" } } },
        call = "RegisterAbility",
        args = { "typo_ticks", { id = 990011, startsCombat = true, expects = "ticks", aura = "typo_dot" } },
        check = "V4",
        field = "expects",
        at = "finish",
    },
    {
        what = 'debuff on an aura that ticks as a dot = "debuff"',
        pre = { "RegisterAura", { "typo_tick_dot", { id = 990012, dot = "debuff", tick_time = 3 } } },
        call = "RegisterAbility",
        args = { "typo_wound", { id = 990013, startsCombat = true, expects = "debuff", aura = "typo_tick_dot" } },
        check = "V4",
        field = "expects",
        at = "finish",
    },
    {
        what = "channel on an aura whose tick_time is a function",
        pre = {
            "RegisterAura",
            {
                "typo_channel",
                {
                    id = 990014,
                    tick_time = function()
                        return 1
                    end,
                },
            },
        },
        call = "RegisterAbility",
        args = { "typo_channel", { id = 990015, startsCombat = true, expects = "channel" } },
        at = "finish",
        passes = true,
    },
    {
        what = "a combat-starting variant, not listed by V5 (the belief compiles only its original)",
        call = "RegisterAbility",
        args = { "typo_variant", { id = 990016, startsCombat = true, variantOf = "rip" } },
        at = "finish",
        passes = true,
    },
    {
        what = "an unknown key on an ability, far from any registered name",
        call = "RegisterAbility",
        args = { "typo_extra", { id = 990007, startsCombat = true, expects = "none", someNewThing = 1 } },
        listed = "findings",
    },
}
