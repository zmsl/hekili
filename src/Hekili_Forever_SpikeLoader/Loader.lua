-- Throwaway spike (restructure plan Task 8, docs/research/2026-10-17-content-addon-spike.md): at PLAYER_LOGIN, the
-- moment the core's OnEnable runs, load the load-on-demand content addon the way the core's loader will.
-- Pattern after Taco Dog Forever's Boot.lua class-pack loader (its LoadAddOn under pcall).
-- luacheck: globals CreateFrame C_AddOns
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, "Hekili_Forever_Spike")
    print("Hekili spike: LoadAddOn ->", ok, loaded, reason)
end)
