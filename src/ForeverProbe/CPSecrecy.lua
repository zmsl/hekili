-- ForeverProbe: is the player's combo-point read secret in combat?
-- /cpsecret start [seconds]   sample every 0.25 s (default 60 s), then print a summary
-- /cpsecret stop               stop early and print
-- /cpsecret                    print the current tallies
--
-- Samples, each tick: UnitPower("player", 4), UnitPower("player", 4, true), GetComboPoints("player", "target"),
-- C_Secrets.GetPowerTypeSecrecy(4) and ShouldUnitPowerBeSecret("player", 4) where they exist, in and out of combat
-- separately. Nothing compares or does maths on a secret: only issecretvalue() and type() are applied to reads.

local CP = 4 -- Enum.PowerType.ComboPoints
local tallies, ticker, started

local function newTally()
    return { n = 0, secret = 0, plain = 0, nilv = 0, min = nil, max = nil }
end

local function reset()
    tallies = {
        combat = { up = newTally(), upUnmod = newTally(), gcp = newTally(), should = newTally(), secrecy = nil },
        ooc    = { up = newTally(), upUnmod = newTally(), gcp = newTally(), should = newTally(), secrecy = nil },
    }
end

local function note(t, v)
    t.n = t.n + 1
    if v == nil then t.nilv = t.nilv + 1 return end
    if issecretvalue and issecretvalue(v) then t.secret = t.secret + 1 return end
    t.plain = t.plain + 1
    if type(v) == "number" then
        if not t.min or v < t.min then t.min = v end
        if not t.max or v > t.max then t.max = v end
    elseif type(v) == "boolean" then
        -- ShouldUnitPowerBeSecret: count trues in max as a flag
        if v then t.max = (t.max or 0) + 1 end
    end
end

local function sample()
    local side = InCombatLockdown() and tallies.combat or tallies.ooc
    local ok, v

    ok, v = pcall(UnitPower, "player", CP);               if ok then note(side.up, v) else note(side.up, nil) end
    ok, v = pcall(UnitPower, "player", CP, true);         if ok then note(side.upUnmod, v) else note(side.upUnmod, nil) end
    if GetComboPoints then
        ok, v = pcall(GetComboPoints, "player", "target"); if ok then note(side.gcp, v) else note(side.gcp, nil) end
    end
    if ShouldUnitPowerBeSecret then
        ok, v = pcall(ShouldUnitPowerBeSecret, "player", CP); if ok then note(side.should, v) else note(side.should, nil) end
    end
    if C_Secrets and C_Secrets.GetPowerTypeSecrecy and side.secrecy == nil then
        ok, v = pcall(C_Secrets.GetPowerTypeSecrecy, CP)
        side.secrecy = ok and tostring(v) or "err"
    end
end

local function line(name, t)
    return string.format("  %s: n=%d plain=%d secret=%d nil=%d range=%s..%s", name, t.n, t.plain, t.secret, t.nilv,
        tostring(t.min), tostring(t.max))
end

local function report()
    for _, k in ipairs({ "combat", "ooc" }) do
        local s = tallies[k]
        print(string.format("|cff00ff00CP secrecy|r %s (power-type secrecy=%s):", k, tostring(s.secrecy)))
        print(line("UnitPower(player,4)", s.up))
        print(line("UnitPower(player,4,true)", s.upUnmod))
        print(line("GetComboPoints", s.gcp))
        print(line("ShouldUnitPowerBeSecret (max=#true)", s.should))
    end
end

SLASH_CPSECRET1 = "/cpsecret"
SlashCmdList.CPSECRET = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "start" then
        reset()
        if ticker then ticker:Cancel() end
        local secs = tonumber(arg) or 60
        started = GetTime()
        ticker = C_Timer.NewTicker(0.25, function()
            sample()
            if GetTime() - started >= secs then ticker:Cancel(); ticker = nil; report() end
        end)
        print(string.format("|cff00ff00CP secrecy|r sampling for %d s; get into combat with combo points.", secs))
    elseif cmd == "stop" then
        if ticker then ticker:Cancel(); ticker = nil end
        if tallies then report() end
    else
        if tallies then report() else print("/cpsecret start [seconds] | stop") end
    end
end
