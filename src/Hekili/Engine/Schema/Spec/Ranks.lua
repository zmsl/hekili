-- Engine/Schema/Spec/Ranks.lua
-- RegisterAbility's derived fields (Spec/Abilities.lua runs ns.DeriveAbility first on every registration):
-- `ranks = { id1, id2, ... }` (rank order) gives `id` (rank 1), `copy` (ranks 2..n), `known` (any rank known) and lets
-- a field read `{ byRank = { v1, v2, ... } }`: the value of the highest known rank, rank 1's before any is known.
-- `effect = function() return function() ... end end` is called once for each of `handler` (the sim's) and `now` (the
-- belief's) that the ability does not declare: one cast effect written once, two closures, as the two layers set
-- each its own environment on its function. A declared `id`, `copy`, `known`, `handler` or `now` wins.
-- Pure (no game read, no core table): the test loaders run it on their recorded abilities too. Registration only.

local _, ns = ...

--- Fills `data`'s derived fields in place and removes `ranks` and `effect` (neither crosses to the belief).
function ns.DeriveAbility(key, data, knownRank)
    local ranks, name = data.ranks, tostring(key)
    for k, v in pairs(data) do
        if type(v) == "table" and rawget(v, "byRank") ~= nil then -- raw: a field's __index is never asked
            assert(ranks, "RegisterAbility: " .. name .. "'s " .. tostring(k) .. " reads byRank without ranks")
            local values = rawget(v, "byRank")
            data[k] = function()
                return values[knownRank(ranks)] or values[1]
            end
        end
    end
    if ranks ~= nil then
        assert(
            type(ranks) == "table" and type(ranks[1]) == "number",
            "RegisterAbility: " .. name .. "'s ranks must list spell IDs"
        )
        assert(data.id == nil or data.id == ranks[1], "RegisterAbility: " .. name .. "'s id is not its first rank")
        data.id = ranks[1]
        if data.copy == nil then
            local copy = {}
            for i = 2, #ranks do
                copy[i - 1] = ranks[i]
            end
            data.copy = copy
        end
        if data.known == nil then
            data.known = function()
                return knownRank(ranks) > 0
            end
        end
        data.ranks = nil
    end
    local effect = data.effect
    if effect ~= nil then
        assert(type(effect) == "function", "RegisterAbility: " .. name .. "'s effect must be a function")
        if data.handler == nil then
            data.handler = effect()
        end
        if data.now == nil then
            data.now = effect()
        end
        assert(
            type(data.handler) == "function" and type(data.now) == "function" and data.handler ~= data.now,
            "RegisterAbility: " .. name .. "'s effect must return a new function each call"
        )
        data.effect = nil
    end
end
