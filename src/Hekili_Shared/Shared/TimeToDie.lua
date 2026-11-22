-- Hekili_Shared/Shared/TimeToDie.lua
-- Each class's default execute line (lane B8, owner L1658): the target health percent below which the class's damage
-- speeds up, without talents (another player's talents cannot be read). The core hints the highest line present in the
-- group to the time-to-die library (Engine/Sim/Targets.lua); the player's own line comes from its pack and replaces
-- its class's default here. Sources: the packs' `healthGate` 0.2 (Warrior.lua execute, Paladin.lua hammer_of_wrath)
-- and wowsims (pin e5a9cd2a2d: sim/warrior/execute.go and sim/paladin/hammer_of_wrath.go, IsExecutePhase20).

local shared = Hekili:NewShared()

if shared.RegisterTtdLines then -- no content API bump: an older core has no such method
    shared:RegisterTtdLines({
        WARRIOR = 20,
        PALADIN = 20,
    })
end
