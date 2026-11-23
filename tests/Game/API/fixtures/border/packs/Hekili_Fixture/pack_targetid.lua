-- tools/check_border.sh must fail this pack stand-in on line 3: content reads the facade as Hekili.Client
local Hekili = _G.Hekili
local id = Hekili.Client.TargetID()
