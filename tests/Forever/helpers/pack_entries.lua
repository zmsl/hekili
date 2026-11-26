-- tests/Forever/helpers/pack_entries.lua: a built pack list's entries for a check that walks every line. `flat(entries)`
-- gives each entry and, right after a sequence line, its members (make_pack's `steps`, as Options.lua ParseActionList
-- builds them), so a member is checked like any line. `LINE`: the engine's window-line actions, never an ability.
-- `SHARED`: the shared content's lines every pack carries (translator rule 25, L1808) and the settings they read, which
-- a class-file-only registry lacks; and the on-use trinkets (Hekili_Shared/Shared/Items.lua ON_USE, lane gear-1), the
-- translator's direct lines for a mapped trinket cast.
return {
    SHARED = {
        healthstone = true,
        healing_potion = true,
        healthstone_health = true,
        healing_potion_health = true,
        weakness_analyzer = true,
        talisman_of_ephemeral_power = true,
        mind_quickening_gem = true,
        everlook_pathcarver = true,
        eye_of_the_beast = true,
        blackhands_breadth = true,
    },
    LINE = { sequence = true, strict_sequence = true, restart_sequence = true, open_window = true, close_window = true },
    flat = function(entries)
        local out = {}
        for _, e in ipairs(entries) do
            out[#out + 1] = e
            for _, m in ipairs(e.steps or {}) do
                out[#out + 1] = m
            end
        end
        return out
    end,
}
