-- tests/Forever/helpers/pack_entries.lua: a built pack list's entries for a check that walks every line. `flat(entries)`
-- gives each entry and, right after a sequence line, its members (make_pack's `steps`, as Options.lua ParseActionList
-- builds them), so a member is checked like any line. `LINE`: the engine's window-line actions, never an ability.
return {
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
