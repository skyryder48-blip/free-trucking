--[[
    Free Trucking — Shared Utility Functions
    Loaded by both server and client via shared_scripts.

    Functions are context-aware: server-only code is guarded by
    IsDuplicityVersion() checks. Client helpers use GlobalState
    for server-synced time.
]]

-- ═══════════════════════════════════════════════════════════════
-- SERVER TIME SYNC
-- ═══════════════════════════════════════════════════════════════
-- Server fetches UNIX_TIMESTAMP() from MySQL on resource start
-- and re-syncs every 30 seconds. Between syncs, elapsed time is
-- derived from GetGameTimer() offset. Client reads GlobalState.
-- os.time() is NOT used anywhere in this resource.

if IsDuplicityVersion() then
    local _serverTimeBase = 0   -- UNIX timestamp from last DB sync
    local _gameTimerBase  = 0   -- GetGameTimer() value at last DB sync

    --- Sync server time from MySQL UNIX_TIMESTAMP().
    local function SyncServerTime()
        local dbTime = MySQL.scalar.await('SELECT UNIX_TIMESTAMP()')
        if dbTime then
            _serverTimeBase = dbTime
            _gameTimerBase  = GetGameTimer()
            GlobalState.serverTime = dbTime
        end
    end

    -- Initial sync + periodic refresh
    CreateThread(function()
        -- Wait for oxmysql to be ready
        while not MySQL or not MySQL.scalar then
            Wait(100)
        end
        SyncServerTime()

        while true do
            Wait(30000)
            SyncServerTime()
        end
    end)

    --- Get current UNIX timestamp derived from DB sync + GetGameTimer() offset.
    ---@return number timestamp UNIX epoch seconds
    function GetServerTime()
        if _serverTimeBase == 0 then
            -- Before first sync, do a blocking DB call
            local dbTime = MySQL.scalar.await('SELECT UNIX_TIMESTAMP()')
            if dbTime then
                _serverTimeBase = dbTime
                _gameTimerBase  = GetGameTimer()
                GlobalState.serverTime = dbTime
                return dbTime
            end
            return 0
        end
        return _serverTimeBase + math.floor((GetGameTimer() - _gameTimerBase) / 1000)
    end
else
    --- Client-side: read server-synced timestamp from GlobalState.
    ---@return number timestamp UNIX epoch seconds
    function GetServerTime()
        return GlobalState.serverTime or 0
    end
end

--- Get elapsed milliseconds since a GetGameTimer() start point.
--- Uses the monotonic game timer — safe on both sides but primarily
--- used client-side for UI countdowns and animation timing.
---@param startTimer number Value from GetGameTimer() at start
---@return number elapsed Milliseconds elapsed
function GetElapsed(startTimer)
    return GetGameTimer() - startTimer
end


-- ═══════════════════════════════════════════════════════════════
-- SERVER-SIDE VALIDATION UTILITIES
-- ═══════════════════════════════════════════════════════════════
-- These functions run server-side only. Every server event handler
-- must validate the calling player before processing. No
-- client-reported data is trusted without server cross-check.

if IsDuplicityVersion() then

    --- In-memory active loads table. Populated on resource start
    --- from truck_active_loads, updated on every state mutation,
    --- keyed by bol_id for O(1) lookups.
    ---@type table<number, table>
    ActiveLoads = ActiveLoads or {}

    --- Verify that the source player owns the specified BOL/active load.
    ---@param src number Player server ID
    ---@param bolId number BOL ID being acted on
    ---@return boolean valid True if the player owns this active load
    function ValidateLoadOwner(src, bolId)
        local player = exports.qbx_core:GetPlayer(src)
        if not player then return false end
        local citizenid = player.PlayerData.citizenid

        local activeLoad = ActiveLoads[bolId]
        if not activeLoad then return false end
        if activeLoad.citizenid ~= citizenid then return false end
        return true
    end

    --- Verify that the source player's coordinates are within range
    --- of target coordinates. Used for proximity-gated interactions
    --- (delivery zones, NPC interactions, transfer range checks).
    ---@param src number Player server ID
    ---@param targetCoords vector3 Expected world position
    ---@param maxDistance number Maximum allowed distance in meters
    ---@return boolean valid True if player is within range
    function ValidateProximity(src, targetCoords, maxDistance)
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return false end
        local playerCoords = GetEntityCoords(ped)
        return #(playerCoords - targetCoords) <= maxDistance
    end

    --- Rate-limit events per player to prevent spam and exploits.
    --- Tracks the last invocation time per player+event combination.
    --- Returns false if the event is being called too frequently.
    ---@param src number Player server ID
    ---@param eventName string Identifier for the event being rate-limited
    ---@param cooldownMs number Minimum milliseconds between allowed calls
    ---@return boolean allowed True if the event is not rate-limited
    local eventCooldowns = {} -- [src .. ':' .. eventName] = GetGameTimer()

    function RateLimitEvent(src, eventName, cooldownMs)
        local key = src .. ':' .. eventName
        local now = GetGameTimer()
        if eventCooldowns[key] and (now - eventCooldowns[key]) < cooldownMs then
            return false -- rate limited
        end
        eventCooldowns[key] = now
        return true
    end

    --- Clean up rate-limit entries when a player disconnects.
    --- Prevents memory leaks from accumulated cooldown keys.
    AddEventHandler('playerDropped', function()
        local src = tostring(source)
        for key in pairs(eventCooldowns) do
            if key:find('^' .. src .. ':') then
                eventCooldowns[key] = nil
            end
        end
    end)

end -- end server-only block


-- ═══════════════════════════════════════════════════════════════
-- FORMATTING UTILITIES (shared, used by both sides)
-- ═══════════════════════════════════════════════════════════════

--- Format a dollar amount with comma separators.
--- Example: FormatMoney(12500) => "$12,500"
---@param amount number Raw dollar amount
---@return string formatted Comma-separated dollar string
function FormatMoney(amount)
    amount = math.floor(amount or 0)
    local negative = amount < 0
    if negative then amount = -amount end

    local formatted = tostring(amount)
    local k
    while true do
        formatted, k = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end

    if negative then
        return '-$' .. formatted
    end
    return '$' .. formatted
end

--- Format a distance in miles with one decimal place.
--- Example: FormatDistance(16.832) => "16.8 mi"
---@param miles number Distance in miles
---@return string formatted Formatted distance string
function FormatDistance(miles)
    if not miles or miles <= 0 then
        return '0.0 mi'
    end
    return string.format('%.1f mi', miles)
end

--- Format seconds into a human-readable time string.
--- Example: FormatTime(4384) => "1:13:04"
---@param seconds number Total seconds
---@return string formatted Time in "H:MM:SS" format
function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours   = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs    = seconds % 60
    return string.format('%d:%02d:%02d', hours, minutes, secs)
end


-- ═══════════════════════════════════════════════════════════════
-- ECONOMY LOOKUP UTILITIES (shared, used by payout engine and UI)
-- ═══════════════════════════════════════════════════════════════
-- These reference Economy.* tables defined in config/economy.lua.
-- They are loaded after config files via the manifest load order.

--- Look up the weight multiplier for a given cargo weight.
--- Walks Economy.WeightMultipliers from lowest to highest bracket
--- and returns the matching multiplier.
---@param weightLbs number Cargo weight in pounds
---@return number multiplier Weight bracket multiplier (1.00 to 1.50)
function GetWeightMultiplier(weightLbs)
    weightLbs = weightLbs or 0
    if not Economy or not Economy.WeightMultipliers then return 1.00 end

    for _, bracket in ipairs(Economy.WeightMultipliers) do
        if weightLbs <= bracket.max then
            return bracket.multiplier
        end
    end
    -- Above all brackets: return the highest multiplier
    return Economy.WeightMultipliers[#Economy.WeightMultipliers].multiplier
end

--- Look up the time performance modifier based on delivery time
--- as a percentage of the allowed window.
--- Under 80% => +15% bonus, 80-100% => no modifier,
--- 100-120% => -10% penalty, over 120% => -25% penalty.
---@param timePct number Actual time / window time (e.g. 0.75 = 75% of window used)
---@return number modifier Signed modifier (e.g. 0.15, 0.00, -0.10, -0.25)
function GetTimeModifier(timePct)
    timePct = timePct or 1.0
    if not Economy or not Economy.TimePerformance then return 0.00 end

    for _, bracket in ipairs(Economy.TimePerformance) do
        if timePct <= bracket.maxPct then
            return bracket.modifier
        end
    end
    -- Beyond all brackets: worst penalty
    return Economy.TimePerformance[#Economy.TimePerformance].modifier
end

--- Look up the cargo integrity modifier based on final integrity
--- percentage at delivery.
--- 90-100% => no penalty, 70-89% => -10%, 50-69% => -25%,
--- below 50% => -100% (rejected).
---@param integrityPct number Cargo integrity 0-100
---@return number modifier Signed modifier (e.g. 0.00, -0.10, -0.25, -1.00)
function GetIntegrityModifier(integrityPct)
    integrityPct = integrityPct or 100
    if not Economy or not Economy.IntegrityModifiers then return 0.00 end

    for _, bracket in ipairs(Economy.IntegrityModifiers) do
        if integrityPct >= bracket.minPct then
            return bracket.modifier
        end
    end
    -- Below all brackets: full penalty
    return Economy.IntegrityModifiers[#Economy.IntegrityModifiers].modifier
end

--- Check if the current server time falls within the night haul
--- premium window (default 22:00 - 06:00).
--- Uses DB-synced GetServerTime() on both sides.
---@return boolean isNight True if current hour is within the night window
function IsNightHaul()
    if not Economy then return false end

    local nightStart = Economy.NightHaulStart or 22
    local nightEnd   = Economy.NightHaulEnd   or 6

    local serverTime = GetServerTime()
    if not serverTime or serverTime == 0 then return false end
    local currentHour = tonumber(os.date('%H', serverTime))

    if not currentHour then return false end

    -- Handle overnight window (e.g. 22:00 to 06:00)
    if nightStart > nightEnd then
        return currentHour >= nightStart or currentHour < nightEnd
    else
        return currentHour >= nightStart and currentHour < nightEnd
    end
end
