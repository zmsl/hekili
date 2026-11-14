-- tools/wiki/boot.lua: one headless boot per class pack (tests/Forever/helpers/enus_text.lua's boot: the real addon
-- under the fake client, the same one the enUS golden walks), cached for the run, with the options tree built.
local enus = require("Forever.helpers.enus_text")
local addons = require("helpers.addons")
local fake = require("Game.State.helpers.fake_api")

local M = {}
local cache = {}

--- The class tokens of the shipped class packs, in load order (tests/helpers/addons.lua).
function M.tokens()
    local out = {}
    for _, name in ipairs(addons.CONTENT) do
        local token = name:match("^Hekili_(%a+)$"):upper()
        if enus.CLASSES[token] then
            out[#out + 1] = token
        end
    end
    return out
end

-- An atlas answers as a texture escape (|T...|t), which the collectors strip; the fake client answers no atlas, so
-- AtlasToString would print the atlas's name into a label.
local ATLAS = { file = "atlas", width = 16, height = 16, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0 }
ATLAS.bottomTexCoord = 1

--- The booted instance of class `token` (the first class pack's when nil), options built.
function M.get(token)
    token = token or M.tokens()[1]
    if not cache[token] then
        local new = fake.new
        fake.new = function(...)
            local api, ctl = new(...)
            api.C_Texture.GetAtlasInfo = function()
                return ATLAS
            end
            return api, ctl
        end
        local names = {} -- the labels' spell names, for this build only (the enUS golden keeps its own list)
        for id, name in pairs(enus.SPELL_NAMES) do
            names[id] = name
        end
        for id, name in pairs(dofile("docs/wiki/data/spells.lua")) do
            enus.SPELL_NAMES[id] = name
        end
        local ok, H = pcall(enus.boot, token)
        fake.new = new
        if ok then
            ok, H = pcall(function()
                H.Hekili:RefreshOptions()
                return H
            end)
        end
        enus.SPELL_NAMES = names
        assert(ok, H)
        cache[token] = H
    end
    return cache[token]
end

return M
