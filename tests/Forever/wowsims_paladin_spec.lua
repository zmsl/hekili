-- tests/Forever/wowsims_paladin_spec.lua (wowsims packs plan, Task 9): the Paladin wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local pw = require("Forever.helpers.paladin_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("PALADIN"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- `base` as wowsims's character: without the spells in `drop` (by ID: ws.content only adds) and `world` over its WORLD.
local function wowsims(base, drop, world)
    return setmetatable({
        WORLD = setmetatable(world, { __index = base.WORLD }),
        character = function()
            local c, known = base.character(), {}
            for _, id in ipairs(c.known) do
                if not drop[id] then
                    known[#known + 1] = id
                end
            end
            c.known = known
            return c
        end,
    }, { __index = base })
end

local function set(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, id in ipairs(list) do
            out[id] = true
        end
    end
    return out
end

-- wowsims's Paladin knows the 879 ranks of Exorcism only (Undead or Demon targets; its target is Mechanical).
local EXORCISM_ANY = { 415068, 415069, 415070, 415071, 415072, 415073 }
-- The seals' hits (Seal of Command 20424, Seal of Righteousness 25713, Seal of Fury 20418, Vindication 440667) log
-- under their own IDs, never a seal's: no kit key, nothing to list in `procs`.
local REPLAY = {}

describe("the Paladin wowsims.com packs #slow #wowsims", function()
    pw.Retribution.character() -- fills IDS
    pw.Protection.character()

    -- Mana: its regen per second, { from 5 s after the last spend, inside the five-second rule }
    -- (Retribution: 2.19 and 0.825 each 0.1 s; Protection: 1.738 and none).
    local RET = wowsims(pw.Retribution, set(EXORCISM_ANY), { fsr = { [0] = { 21.9, 8.25 } } })
    local RET_LIVE = wowsims(pw.Retribution, set(EXORCISM_ANY), {})

    it("Retribution (wowsims.com) follows wowsims's casts", function()
        local C = content("paladin_retribution", RET, "Retribution (wowsims.com)", 60)
        -- 0.56 (0.561), lowered from 0.57 (0.579) by central fix 12's mana tick padding: with the tick's phase unknown
        -- (a secret pool) the icon for a mana-gated seal comes one tick late, so one decision of 57 (Seal of Command on
        -- the tick that pays for it) shows Seal of Righteousness. Recover after the in-game UNIT_POWER_FREQUENT-for-mana
        -- checkpoint by rounding up to the observed tick; the belief's precision at near-ties is GAP AB.
        ws.gate("Retribution (wowsims.com)", C, "paladin_retribution", 0.56, REPLAY)
    end)
    -- the pack's own worst idle at 60: wowsims's priority spends itself dry (its own Retribution is out of mana from 60 s
    -- of its log), so its longest wait is for mana. 4.4 before central fix 8, while
    -- the collapsed mana lower bound kept Consecration's and Exorcism's `mana.pct>=10` from passing.
    local RET_LIVE60 = 8.4
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Retribution (wowsims.com) stays live at level " .. level, function()
            local C = content("paladin_retribution", RET_LIVE, "Retribution (wowsims.com)", level)
            ws.live("Retribution (wowsims.com)", C, math.max(6, RET_LIVE60))
        end)
    end

    -- The build takes no Holy Shock.
    local PROT_DROP = set(pw.Protection.IDS.holy_shock, EXORCISM_ANY)
    local PROT = wowsims(pw.Protection, PROT_DROP, { fsr = { [0] = { 17.38, 0 } } })
    local PROT_LIVE = wowsims(pw.Protection, PROT_DROP, {})

    it("Protection (wowsims.com) follows wowsims's casts", function()
        local C = content("paladin_protection", PROT, "Protection (wowsims.com)", 60)
        -- 0.96: 0.964 on central fix 12 (GAP R, the five-second rule's mana forecast), from 0.75
        ws.gate("Protection (wowsims.com)", C, "paladin_protection", 0.96, REPLAY)
    end)
    -- the pack's own worst idle at 60: wowsims's priority spends itself dry (its own Protection is out of mana from 24 s),
    -- so its longest wait is for mana
    local PROT_LIVE60 = 17.8
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Protection (wowsims.com) stays live at level " .. level, function()
            local C = content("paladin_protection", PROT_LIVE, "Protection (wowsims.com)", level)
            ws.live("Protection (wowsims.com)", C, math.max(6, PROT_LIVE60))
        end)
    end
end)
