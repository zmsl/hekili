local _, ns = ...
-- Engine/Driver.lua: the engine's driver frame (HekiliEngine), moved verbatim out of UI/UI.lua (restructure plan,
-- Task 4) so the UI no longer owns the loop that runs Hekili.Update: the frame budget, the OnUpdate that creates and
-- resumes the recommendation thread, and the thread's performance counters.

local Facade = ns.Facade
local CreateFrame = Facade.CreateFrame
local GetFramerate, GetTime, InCombatLockdown = Facade.GetFramerate, Facade.GetTime, Facade.InCombatLockdown
local format = string.format

-- FPS smoothing system for stable budget calculations
local fpsTracker = {
    samples = {}, -- Sliding window of FPS samples
    maxSamples = 30, -- 30 samples for smoothing
    smoothedFPS = 60, -- Current smoothed FPS value
    lastUpdate = 0, -- Last update time
    updateInterval = 0.1, -- Update every 100ms
    index = 1, -- Ring tracker
    count = 0, -- Total samples
    sum = 0, -- Sum of all samples
}

local function updateSmoothedFPS()
    local now = GetTime()
    if now - fpsTracker.lastUpdate >= fpsTracker.updateInterval then
        local currentFPS = GetFramerate()

        -- If overwriting an old sample, subtract it first
        if fpsTracker.count == fpsTracker.maxSamples then
            fpsTracker.sum = fpsTracker.sum - fpsTracker.samples[fpsTracker.index]
        else
            fpsTracker.count = fpsTracker.count + 1
        end

        -- Add to sliding window
        fpsTracker.samples[fpsTracker.index] = currentFPS
        fpsTracker.sum = fpsTracker.sum + currentFPS

        -- Shift the index
        fpsTracker.index = (fpsTracker.index % fpsTracker.maxSamples) + 1

        -- Calculate smoothed average
        fpsTracker.smoothedFPS = fpsTracker.sum / fpsTracker.count
        fpsTracker.lastUpdate = now
    end

    return fpsTracker.smoothedFPS
end

-- Expose smoothed FPS for use in other places
function Hekili.GetSmoothedFPS()
    return updateSmoothedFPS()
end

-- Calculate frame budget based on user percentage
local function calculateFrameBudget()
    local smoothedFPS = updateSmoothedFPS()
    local frameBudget = Hekili.Engine.settings.performance.frameBudget or 0.7
    -- local rawFPS = GetFramerate()

    -- Calculate frame time
    local frameTime = 1000 / math.max(smoothedFPS, 30) -- min 30 FPS

    -- Apply user percentage directly to frame time
    local userBudget = frameTime * frameBudget

    -- Debug output
    -- print(string.format("[Hekili Budget] Setting: %d%%, Raw FPS: %.1f, Smoothed FPS: %.1f, Frame Time: %.2fms, Budget: %.2fms",
    --     frameBudget, rawFPS, smoothedFPS, frameTime, userBudget))

    return userBudget
end

-- Separate the recommendations engine from each display.
ns.EngineFrame = CreateFrame("Frame", "HekiliEngine")

ns.EngineFrame.refreshTimer = 1
ns.EngineFrame.eventsTriggered = {}

local framesUsed = 0
local framesTimes = 0

function ns.EngineFrame:UpdatePerformance(wasted)
    -- Only track in combat.
    if not (self.firstThreadCompleted and InCombatLockdown()) then
        self.activeThreadTime = 0
        framesUsed = 0
        framesTimes = 0
        return
    end

    if self.firstThreadCompleted then
        local now = debugprofilestop()
        local timeSince = now - self.activeThreadStart

        self.lastUpdate = now

        if self.threadUpdates then
            local updates = self.threadUpdates.updates
            local total = updates + 1

            if framesUsed > 0 then
                local frameCount = (self.threadUpdates.framesWorked or 0) + framesUsed
                self.threadUpdates.meanFrameTime = (
                    self.threadUpdates.meanFrameTime * self.threadUpdates.framesWorked + framesTimes
                ) / frameCount
                self.threadUpdates.framesWorked = frameCount
            end

            if wasted then
                -- Capture thrown away computation time due to forced resets.
                self.threadUpdates.meanWasted = (self.threadUpdates.meanWasted * updates + self.activeThreadTime)
                    / total
                self.threadUpdates.totalWasted = (self.threadUpdates.totalWasted + self.activeThreadTime)

                if self.activeThreadTime > self.threadUpdates.peakWasted then
                    self.threadUpdates.peakWasted = self.activeThreadTime
                end
            else
                self.threadUpdates.meanClockTime = (self.threadUpdates.meanClockTime * updates + timeSince) / total
                self.threadUpdates.meanWorkTime = (self.threadUpdates.meanWorkTime * updates + self.activeThreadTime)
                    / total
                self.threadUpdates.meanFrames = (self.threadUpdates.meanFrames * updates + self.activeThreadFrames)
                    / total

                if timeSince > self.threadUpdates.peakClockTime then
                    self.threadUpdates.peakClockTime = timeSince
                end
                if self.activeThreadTime > self.threadUpdates.peakWorkTime then
                    self.threadUpdates.peakWorkTime = self.activeThreadTime
                end
                if self.activeThreadFrames > self.threadUpdates.peakFrames then
                    self.threadUpdates.peakFrames = self.activeThreadFrames
                end

                self.threadUpdates.updates = total
                self.threadUpdates.updatesPerSec = 1000 * total / (now - self.threadUpdates.firstUpdate)
            end
        else
            self.threadUpdates = {
                meanClockTime = timeSince,
                meanWorkTime = self.activeThreadTime,
                meanFrames = self.activeThreadFrames or 1,
                meanFrameTime = framesTimes > 0 and framesTimes or (1000 / GetFramerate()),
                meanWasted = 0,

                firstUpdate = now,
                updates = 1,
                framesWorked = framesUsed > 0 and framesUsed or 1,
                updatesPerSec = 1000 / (self.activeThreadTime > 0 and self.activeThreadTime or 1),

                peakClockTime = timeSince,
                peakWorkTime = self.activeThreadTime,
                peakFrames = self.activeThreadFrames or 1,
                peakWasted = 0,

                totalWasted = 0,
            }
        end
    end

    self.activeThreadTime = 0
end

ns.EngineFrame:SetScript("OnUpdate", function(self, elapsed)
    if not self.activeThread then
        self.refreshTimer = self.refreshTimer + elapsed
    end

    if Hekili.Engine.settings.enabled and not Hekili.Pause then
        -- Set refresh rates to default values
        self.refreshRate = self.refreshRate or 0.25
        self.combatRate = self.combatRate or 0.2

        local thread = self.activeThread

        -- If there's no thread, then see if we have a reason to update.
        if
            (not thread or coroutine.status(thread) == "dead")
            and self.refreshTimer > (self.criticalUpdate and self.combatRate or self.refreshRate)
        then
            --[[ if thread and coroutine.status( thread ) == "suspended" then
                -- We're going to break the thread and start over from the current display in progress.
                self:UpdatePerformance( true )
            end ]]

            self.criticalUpdate = false
            self.superUpdate = false
            self.refreshTimer = 0

            self.activeThread = coroutine.create(Hekili.Update)

            self.activeThreadTime = 0
            self.activeThreadStart = debugprofilestop()
            self.activeThreadFrames = 0

            -- Use new frame budget calculation
            Hekili.maxFrameTime = calculateFrameBudget()

            thread = self.activeThread
        end

        -- If there's a thread, process for up to user preferred limits.
        if thread and coroutine.status(thread) == "suspended" then
            framesUsed = framesUsed + 1
            framesTimes = framesTimes + elapsed * 1000

            self.activeThreadFrames = self.activeThreadFrames + 1
            Hekili.activeFrameStart = debugprofilestop()

            -- if ns.EngineFrame.threadUpdates then print( 1000 * elapsed, Hekili.maxFrameTime, ns.EngineFrame.threadUpdates.meanWorkTime, ns.EngineFrame.threadUpdates.meanFrames ) end
            local ok, err = coroutine.resume(thread)

            if not ok then
                err = err .. "\n\n" .. debugstack(thread)
                Hekili:Error("Update: " .. err)

                if Hekili.ActiveDebug then
                    Hekili:Debug(
                        format(
                            "Recommendation thread terminated due to error: %s",
                            err and err:gsub("%%", "%%%%") or "Unknown"
                        )
                    )
                    Hekili:SaveDebugSnapshot(self.id)
                    Hekili.ActiveDebug = nil
                end

                pcall(error, err)
            end

            self.activeThreadTime = self.activeThreadTime + debugprofilestop() - Hekili.activeFrameStart

            if coroutine.status(thread) == "dead" or err then
                self.activeThread = nil

                self.refreshRate = 0.5
                self.combatRate = 0.2

                if ok then
                    if self.firstThreadCompleted and not self.DontProfile then
                        self:UpdatePerformance()
                    end
                    self.firstThreadCompleted = true
                end
            end

            if ok and err == "AutoSnapshot" then
                self.DontProfile = true
                Hekili.Engine.Snapshot(true)
                self.DontProfile = false
            end
        end
    end
end)
Hekili:ProfileFrame("HekiliEngine", ns.EngineFrame)

function ns.EngineFrame:IsThreadActive()
    return self.activeThread and coroutine.status(self.activeThread) == "suspended"
end
