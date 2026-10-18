-- Options/Profile.lua (restructure plan, Task 6): Options owns the AceDB profile and hands it to the engine through
-- Hekili.Engine.Configure. Moved from Engine/Sim/Core.lua (OnInitialize's DB block, ReInitialize, Toggle) so the
-- engine never names Hekili.DB.

local addon, ns = ...
local Hekili = _G[ addon ]

local Engine = Hekili.Engine

-- AceDB profile callbacks: the engine sees the new profile before the refresh.
function Hekili:ProfileChanged()
    Engine.Configure( self.DB.profile )
    self:TotalRefresh()
end


-- Called from OnInitialize (1x): the saved variables, LibDualSpec, the profile callbacks and the options table.
function Hekili:InitializeProfile()
    self.DB = LibStub( "AceDB-3.0" ):New( "HekiliDB", self:GetDefaults(), true )

    self.Options = self:GetOptions()
    self.Options.args.profiles = LibStub( "AceDBOptions-3.0" ):GetOptionsTable( self.DB )

    -- Reimplement LibDualSpec; some folks want different layouts w/ specs of the same class
    local LDS = LibStub( "LibDualSpec-1.0" )
    LDS:EnhanceDatabase( self.DB, "Hekili" )
    LDS:EnhanceOptions( self.Options.args.profiles, self.DB )

    -- After EnhanceDatabase: it may switch to the spec's profile before the callbacks below exist.
    Engine.Configure( self.DB.profile )

    self.DB.RegisterCallback( self, "OnProfileChanged", "ProfileChanged" )
    self.DB.RegisterCallback( self, "OnProfileCopied", "ProfileChanged" )
    self.DB.RegisterCallback( self, "OnProfileReset", "ProfileChanged" )

    local AceConfig = LibStub( "AceConfig-3.0" )
    AceConfig:RegisterOptionsTable( "Hekili", self.Options )
end


function Hekili:ReInitialize()
    self:OverrideBinds()
    self:RestoreDefaults()

    self:RunOneTimeFixes()

    self.PendingSpecializationChange = true

    ns.callHook( "onInitialize" )

    if self.DB.profile.enabled == false and self.DB.profile.AutoDisabled then
        self.DB.profile.AutoDisabled = nil
        self.DB.profile.enabled = true
        Engine.Configure( self.DB.profile )
        self:Enable()
    end
end


function Hekili:Toggle()
    self.DB.profile.enabled = not self.DB.profile.enabled
    Engine.Configure( self.DB.profile )

    if self.DB.profile.enabled then
        self:Enable()
    else
        self:Disable()
    end

    self:UpdateDisplayVisibility()
end
