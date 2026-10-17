-- Throwaway spike (restructure plan Task 8, docs/research/2026-10-17-content-addon-spike.md): a separate,
-- load-on-demand addon registers a spec through the public Hekili object only.
-- luacheck: globals CreateFrame
local FAKE_SPEC = 999001 -- no Constants row, so it cannot collide with a real or Forever spec

-- NewSpecialization asks GetSpecializationInfoByID for a non-Forever spec when IsRetail() (Forever reports Retail),
-- which knows no fake id; the spike takes the non-retail branch (id and icon as given) for this one call.
local isRetail = Hekili.IsRetail
Hekili.IsRetail = function()
    return false
end
local ok, err = pcall(Hekili.NewSpecialization, Hekili, FAKE_SPEC, true, "Interface\\Icons\\INV_Misc_QuestionMark")
Hekili.IsRetail = isRetail
print("Hekili spike: spec registered", ok, ok and "" or err)

-- Registered after the core's own PLAYER_ENTERING_WORLD handler (this addon loads at PLAYER_LOGIN), so it fires later.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
    print(
        "Hekili spike: class.specs[999001] =",
        Hekili.Class.specs[FAKE_SPEC] ~= nil,
        "activeSpec =",
        tostring(Hekili.State and Hekili.State.spec and Hekili.State.spec.id)
    )
end)
