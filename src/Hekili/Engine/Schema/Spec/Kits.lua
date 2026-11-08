-- Engine/Schema/Spec/Kits.lua
-- Spec construction: buildSpec (the spec record plus a copy of every ns.SpecMixin method, read at call time), spec 0's
-- NewSpecialization, a class pack's NewClass (the class kit and one spec per tree) and GetSpecialization. Loads before
-- Spec/All.lua, which builds spec 0 at load.

local addon, ns = ...
local Facade = ns.Facade
local GetSpecializationInfoByID, UnitClass = Facade.GetSpecializationInfoByID, Facade.UnitClass
local Hekili = _G[ addon ]
local class = Hekili.Class
local getSpecializationKey = ns.getSpecializationKey

local function buildSpec( id, key, name, texture, role, pClass, melee )
    local spec = class.specs[ id ] or {
        id = id,
        key = key,
        name = name,
        texture = texture,
        role = role,
        class = pClass,
        melee = melee,

        resources = {},
        resourceAuras = {},
        primaryResource = nil,
        primaryStat = nil,

        talents = {},
        pvptalents = {},
        powers = {},

        auras = {},
        pseudoAuras = 0,

        abilities = {},
        pseudoAbilities = 0,
        itemAbilities = 0,
        pendingItemSpells = {},

        pets = {},
        totems = {},
        windows = {}, -- RegisterWindow's records by name
        reactions = {}, -- RegisterReaction's records by name

        potions = {},

        ranges = {},
        settings = {},

        stateExprs = {}, -- expressions are returned as values and take no args.
        stateFuncs = {}, -- functions can take arguments and can be used as helper functions in handlers.
        stateTables = {}, -- tables are... tables.

        gear = {},
        setBonuses = {},

        hooks = {},
        funcHooks = {},
        phases = {},
        interrupts = {},

        dual_cast = {},

        packs = {},
        options = {},

        variables = {}
    }

    class.num = class.num + 1

    for k, func in pairs( ns.SpecMixin ) do
        spec[ k ] = func
    end

    class.specs[ id ] = spec
    return spec
end

--- Spec 0 (`all`) only; class packs call Hekili:NewClass.
function Hekili:NewSpecialization( specID, isRanged, icon )

    if not specID or specID < 0 then return end

    isRanged = isRanged or ns.Specializations[ specID ].ranged

    local id, name, _, texture, role, pClass

    if Hekili.IsForever() and specID > 0 then id, name, _, texture, role, pClass = GetSpecializationInfoByID( specID )
    else
        id = specID
        texture = icon
    end

    if not id then
        Hekili:Error( "Unable to generate specialization DB for spec ID #" .. specID .. "." )
        return nil
    end

    if specID ~= 0 then
        class.initialized = true
    end

    local token = getSpecializationKey( id )
    return buildSpec( id, token, name, texture, role, pClass, not isRanged )
end

--- (per-spec plan) A class pack's entry point. Returns the class kit: every Register* call on it (abilities, auras,
--- talents as { tree (1-3, 0 unknown), spell, max rank }, resources, hooks, packs, settings) is the class's, read by
--- each of its specs. `def.specs` lists the specs in order, each { key, name, tree (the talent tree it rides), icon,
--- role ("attack"|"tank"|"healer": shown, not simulated), ranged, package (its default priority), movement (true: its
--- priorities read the Movement toggle, whose options row it then shows), unsupported (true: no
--- priorities on Forever; the engine idles and the options page says so) }. Ids are ours: ns.TreeSpecID(client class
--- id, slot), the kit at slot 0. Nil when `token` is not the player's class.
function Hekili:NewClass( token, def )
    local _, playerToken, classID = UnitClass( "player" )
    if token ~= playerToken or type( classID ) ~= "number" or type( def ) ~= "table" or type( def.specs ) ~= "table" then return end

    class.initialized = true
    local kit = buildSpec( ns.TreeSpecID( classID, 0 ), "kit", token, nil, nil, token, true )
    kit.token, kit.trees, kit.specs = token, {}, {}

    for slot, d in ipairs( def.specs ) do
        local id = ns.TreeSpecID( classID, slot )
        local s = setmetatable( {
            id = id,
            key = d.key,
            name = d.name,
            texture = d.icon,
            role = d.role,
            tree = d.tree or 0,
            slot = slot,
            unsupported = d.unsupported or nil,
            melee = not d.ranged,
            kit = kit,
            settings = {},
            options = { package = d.package, movement = d.movement }, -- per spec: the kit's RegisterOptions reaches every tree
        }, { __index = kit } )
        if d.unsupported then s.options.enabled = false end -- no priorities: no displays

        class.specs[ id ] = s
        kit.trees[ slot ] = s
        kit.specs[ d.key ] = s
        class.specByShare[ token .. ":" .. d.key ] = id
    end

    class.kit = kit
    return kit
end

function Hekili:GetSpecialization( specID )
    if not specID then return class.specs[ 0 ] end
    return class.specs[ specID ]
end
