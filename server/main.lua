--[[
    server/main.lua
    Resource initialization, player lifecycle, maintenance loops, and utility helpers.

    Responsibilities:
      - On resource start: load config, restore ActiveLoads from DB, run maintenance, start board timers
      - GlobalState.serverTime sync every 30 seconds
      - Player loaded handler: reconnect recovery (Section 6.3)
      - Player dropped handler: last_seen update, active load orphaning
      - Maintenance thread: runs every 15 minutes
      - Helper utilities: GetCitizenId, GetPlayerBySource, IsPlayerAdmin, ValidateLoadOwner, etc.
]]

-- ============================================================================
-- IN-MEMORY STATE
-- ActiveLoads is keyed by bol_id for fast lookup during mission events.
-- Synced to truck_active_loads on every mutation.
-- ============================================================================

ActiveLoads = {}                 -- [bol_id] = active load row data
local PlayerDropTimestamps = {}  -- [citizenid] = GetServerTime() when they dropped
local eventCooldowns = {}        -- [src .. ':' .. eventName] = GetGameTimer()
local stationaryTimers = {}      -- [bol_id] = GetServerTime() when vehicle reported stationary

-- Configurable timeout before an orphaned load is marked abandoned (seconds)
local ORPHAN_ABANDON_TIMEOUT = 600 -- 10 minutes

-- ============================================================================
-- HELPER UTILITIES
-- ============================================================================

--- Get citizenid from a player source
---@param src number Player server ID
---@return string|nil citizenid
function GetCitizenId(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end
    return player.PlayerData.citizenid
end

--- Get the full QBX player object by source
---@param src number Player server ID
---@return table|nil player
function GetPlayerBySource(src)
    return exports.qbx_core:GetPlayer(src)
end

--- Get the server source for a player by citizenid (returns nil if offline)
---@param citizenid string
---@return number|nil src
function GetPlayerSource(citizenid)
    local players = exports.qbx_core:GetQBPlayers()
    for src, player in pairs(players) do
        if player.PlayerData.citizenid == citizenid then
            return src
        end
    end
    return nil
end

--- Check if a player has admin permissions
---@param src number Player server ID
---@return boolean
function IsPlayerAdmin(src)
    -- Check QBX admin group or ace permission
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end
    -- QBX uses permission groups; check for admin or god
    if IsPlayerAceAllowed(src, 'command.truckadmin') then
        return true
    end
    -- Fallback: check QBX group
    local group = player.PlayerData.group
    if group == 'admin' or group == 'god' then
        return true
    end
    return false
end

--- Verify source player owns the specified BOL/active load
--- Used by all server event handlers to prevent spoofing
---@param src number Player server ID
---@param bolId number BOL ID being acted on
---@return boolean valid
function ValidateLoadOwner(src, bolId)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end
    local citizenid = player.PlayerData.citizenid

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return false end
    if activeLoad.citizenid ~= citizenid then return false end
    return true
end

--- Verify source player coords are within range of target coords
---@param src number Player server ID
---@param targetCoords vector3 Expected location
---@param maxDistance number Maximum allowed distance in meters
---@return boolean valid
function ValidateProximity(src, targetCoords, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local playerCoords = GetEntityCoords(ped)
    return #(playerCoords - targetCoords) <= maxDistance
end

--- Rate-limit events per player (prevent spam/exploit)
---@param src number Player server ID
---@param eventName string Identifier for the rate-limited action
---@param cooldownMs number Minimum milliseconds between allowed calls
---@return boolean allowed
function RateLimitEvent(src, eventName, cooldownMs)
    local key = src .. ':' .. eventName
    local now = GetGameTimer()
    if eventCooldowns[key] and (now - eventCooldowns[key]) < cooldownMs then
        return false -- rate limited
    end
    eventCooldowns[key] = now
    return true
end

--- Ensure a driver record exists for this player, creating one if needed
---@param src number Player server ID
---@return table|nil driver record
function EnsureDriverRecord(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end
    local citizenid = player.PlayerData.citizenid
    local playerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname

    local driver = DB.GetDriver(citizenid)
    if not driver then
        local driverId = DB.CreateDriver(citizenid, playerName)
        driver = DB.GetDriver(citizenid)
    end
    return driver
end

-- ============================================================================
-- RESOURCE START
-- ============================================================================

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    print('[trucking] Resource starting -- initializing...')

    -- 1. Run maintenance queries to clean stale data
    local expiredReservations = DB.ExpireReservations()
    local expiredLoads = DB.ExpireBoardLoads()
    local expiredSurges = DB.ExpireSurges()
    local expiredPolicies = DB.ExpireInsurancePolicies()
    local liftedSuspensions = DB.LiftExpiredSuspensions()
    DB.DecayPreferredTier()

    print(('[trucking] Maintenance: %d reservations expired, %d loads expired, %d surges expired, %d policies expired, %d suspensions lifted'):format(
        expiredReservations, expiredLoads, expiredSurges, expiredPolicies, liftedSuspensions
    ))

    -- 2. Restore ActiveLoads from database
    local dbActiveLoads = DB.GetAllActiveLoads()
    for _, row in ipairs(dbActiveLoads) do
        ActiveLoads[row.bol_id] = row
    end
    print(('[trucking] Restored %d active loads from database'):format(#dbActiveLoads))

    -- 3. Initialize board state rows if they do not exist, and start refresh timers
    local regions = { 'los_santos', 'sandy_shores', 'paleto', 'grapeseed' }
    for _, region in ipairs(regions) do
        local state = DB.GetBoardState(region)
        if not state then
            DB.UpdateBoardState(region, {
                last_refresh_at = 0,
                next_refresh_at = GetServerTime(),
                refresh_interval_secs = Config.BoardRefreshSeconds or 7200,
                available_t0 = 0,
                available_t1 = 0,
                available_t2 = 0,
                available_t3 = 0,
                surge_active_count = 0,
            })
        end
    end

    -- 4. Start staggered board refresh timers per region
    StartBoardRefreshTimers()

    -- 5. Sync server time immediately
    GlobalState.serverTime = GetServerTime()

    print('[trucking] Initialization complete.')
end)

-- ============================================================================
-- SERVER TIME SYNC
-- GlobalState.serverTime updated every 30 seconds for client-side time display
-- ============================================================================

CreateThread(function()
    while true do
        GlobalState.serverTime = GetServerTime()
        Wait(30000)
    end
end)

-- ============================================================================
-- PLAYER LOADED (Reconnect Recovery -- Section 6.3)
-- When a player loads in, check for an active load. If found, extend the
-- delivery window by the duration of the disconnect and restore state.
-- ============================================================================

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- Ensure driver record exists (creates on first join)
    EnsureDriverRecord(src)

    -- Update last_seen
    DB.UpdateDriver(citizenid, { last_seen = GetServerTime() })

    -- Clear any stored drop timestamp
    local dropTime = PlayerDropTimestamps[citizenid]
    PlayerDropTimestamps[citizenid] = nil

    -- Check for active load in database
    local activeLoad = DB.GetActiveLoad(citizenid)
    if not activeLoad then return end

    -- Calculate disconnect duration for window extension
    local disconnectedSeconds = 0
    if dropTime then
        disconnectedSeconds = GetServerTime() - dropTime
    else
        -- Fallback: use last_seen from driver record (may have been updated by previous drop)
        local driver = DB.GetDriver(citizenid)
        if driver and driver.last_seen then
            disconnectedSeconds = GetServerTime() - driver.last_seen
        end
    end

    -- Extend delivery window by disconnect duration (grace period)
    if disconnectedSeconds > 0 then
        DB.UpdateActiveLoad(activeLoad.id, {
            window_expires_at = activeLoad.window_expires_at + disconnectedSeconds,
            window_reduction_secs = activeLoad.window_reduction_secs + disconnectedSeconds,
        })
        activeLoad.window_expires_at = activeLoad.window_expires_at + disconnectedSeconds
    end

    -- Restore to in-memory ActiveLoads table
    ActiveLoads[activeLoad.bol_id] = activeLoad

    -- Allow the client to fully load before restoring state
    Wait(2000)

    local bol = DB.GetBOL(activeLoad.bol_id)
    if not bol then
        print(('[trucking] WARNING: Active load found for %s but BOL %d missing'):format(citizenid, activeLoad.bol_id))
        return
    end

    TriggerClientEvent('trucking:client:restoreActiveLoad', src, activeLoad, bol)
    lib.notify(src, {
        title = 'Active Load Restored',
        description = 'BOL #' .. bol.bol_number .. ' -- delivery window extended',
        type = 'inform',
    })

    print(('[trucking] Restored active load for %s (BOL #%s, window extended by %ds)'):format(
        citizenid, bol.bol_number, disconnectedSeconds
    ))
end)

-- ============================================================================
-- PLAYER DROPPED
-- Update last_seen, handle active load orphaning
-- ============================================================================

AddEventHandler('playerDropped', function(reason)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- Record drop timestamp for reconnect recovery
    local now = GetServerTime()
    PlayerDropTimestamps[citizenid] = now

    -- Update last_seen in driver record
    DB.UpdateDriver(citizenid, { last_seen = now })

    -- Clear rate limit entries for this source
    for key, _ in pairs(eventCooldowns) do
        if key:find(tostring(src) .. ':') == 1 then
            eventCooldowns[key] = nil
        end
    end

    -- Clear stationary timers for any loads this player owned
    for bolId, activeLoad in pairs(ActiveLoads) do
        if activeLoad.citizenid == citizenid then
            stationaryTimers[bolId] = nil
        end
    end

    -- NOTE: We do NOT immediately abandon the load. The maintenance thread
    -- will handle orphan detection after ORPHAN_ABANDON_TIMEOUT elapses.
    -- This gives the player time to reconnect. The reconnect handler extends
    -- the window to compensate for lost time.
    print(('[trucking] Player dropped: %s (%s) - reason: %s'):format(citizenid, GetPlayerName(src) or 'unknown', reason))
end)

-- ============================================================================
-- MAINTENANCE THREAD
-- Runs every 15 minutes: expire reservations, expire loads, expire surges,
-- expire insurance, lift suspensions, decay preferred tier, handle orphaned loads
-- ============================================================================

CreateThread(function()
    -- Initial wait to let the resource fully start
    Wait(5000)

    while true do
        Wait(900000) -- 15 minutes

        local now = GetServerTime()
        print('[trucking] Running 15-minute maintenance cycle...')

        -- 1. Expire stale reservations
        local expRes = DB.ExpireReservations()

        -- 2. Expire board loads
        local expLoads = DB.ExpireBoardLoads()

        -- 3. Expire surges
        local expSurges = DB.ExpireSurges()

        -- 4. Expire insurance policies
        local expPolicies = DB.ExpireInsurancePolicies()

        -- 5. Lift expired suspensions
        local liftedSusp = DB.LiftExpiredSuspensions()

        -- 6. Preferred tier decay
        DB.DecayPreferredTier()

        -- 7. Handle orphaned active loads
        -- An active load is orphaned if the owning player has been offline
        -- longer than ORPHAN_ABANDON_TIMEOUT
        for bolId, activeLoad in pairs(ActiveLoads) do
            local ownerOnline = GetPlayerSource(activeLoad.citizenid)
            if not ownerOnline then
                local dropTime = PlayerDropTimestamps[activeLoad.citizenid]
                if dropTime and (now - dropTime) >= ORPHAN_ABANDON_TIMEOUT then
                    -- Auto-abandon: forfeit deposit, update BOL, rep penalty
                    print(('[trucking] Auto-abandoning orphaned load BOL #%d for %s'):format(bolId, activeLoad.citizenid))
                    ProcessOrphanedLoad(bolId, activeLoad)
                    PlayerDropTimestamps[activeLoad.citizenid] = nil
                end
            end
        end

        -- 8. Check for expired delivery windows on active loads
        for bolId, activeLoad in pairs(ActiveLoads) do
            if activeLoad.window_expires_at and now >= activeLoad.window_expires_at then
                HandleWindowExpired(bolId)
            end
        end

        print(('[trucking] Maintenance done: %d reservations, %d loads, %d surges expired, %d policies, %d suspensions lifted'):format(
            expRes, expLoads, expSurges, expPolicies, liftedSusp
        ))
    end
end)

--- Process an orphaned load (player offline too long)
--- Forfeits deposit, updates BOL to abandoned, applies rep penalty
---@param bolId number
---@param activeLoad table
function ProcessOrphanedLoad(bolId, activeLoad)
    -- Update BOL status
    DB.UpdateBOL(bolId, {
        bol_status = 'abandoned',
    })

    -- Log the event
    local bol = DB.GetBOL(bolId)
    if bol then
        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = activeLoad.citizenid,
            event_type = 'load_abandoned',
            event_data = { reason = 'orphaned', timeout = ORPHAN_ABANDON_TIMEOUT },
        })
    end

    -- Forfeit deposit
    local deposit = DB.GetDeposit(bolId)
    if deposit and deposit.status == 'held' then
        DB.UpdateDepositStatus(deposit.id, 'forfeited')
    end

    -- Update load board status
    if activeLoad.load_id then
        DB.UpdateLoadStatus(activeLoad.load_id, 'orphaned')
    end

    -- Delete from active loads
    DB.DeleteActiveLoad(activeLoad.id)
    ActiveLoads[bolId] = nil

    -- Reputation penalty will be applied when/if the player reconnects
    -- We store the pending penalty in the BOL event so it can be processed on next login
end

--- Handle an active load whose delivery window has expired
---@param bolId number
function HandleWindowExpired(bolId)
    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    print(('[trucking] Delivery window expired for BOL #%d (citizenid: %s)'):format(bolId, activeLoad.citizenid))

    -- Update BOL status to expired
    DB.UpdateBOL(bolId, {
        bol_status = 'expired',
    })

    -- Log the event
    local bol = DB.GetBOL(bolId)
    if bol then
        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = activeLoad.citizenid,
            event_type = 'window_expired',
            event_data = {
                window_expires_at = activeLoad.window_expires_at,
                accepted_at = activeLoad.accepted_at,
            },
        })
    end

    -- Forfeit deposit
    local deposit = DB.GetDeposit(bolId)
    if deposit and deposit.status == 'held' then
        DB.UpdateDepositStatus(deposit.id, 'forfeited')
    end

    -- Update load board status
    if activeLoad.load_id then
        DB.UpdateLoadStatus(activeLoad.load_id, 'expired')
    end

    -- Delete from active loads
    DB.DeleteActiveLoad(activeLoad.id)
    ActiveLoads[bolId] = nil

    -- Notify the player if they are online
    local playerSrc = GetPlayerSource(activeLoad.citizenid)
    if playerSrc then
        TriggerClientEvent('trucking:client:windowExpired', playerSrc, bolId)
        lib.notify(playerSrc, {
            title = 'Delivery Window Expired',
            description = 'Your load has expired. Deposit forfeited.',
            type = 'error',
        })
    end
end

-- ============================================================================
-- ABANDONMENT TRACKING (Server-authoritative stationary detection)
-- Client reports stationary/moving state. Server tracks actual timing.
-- 10 minutes stationary = seal break (if sealed), handled by seal system.
-- ============================================================================

RegisterNetEvent('trucking:server:vehicleStationary', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not stationaryTimers[bolId] then
        stationaryTimers[bolId] = GetServerTime()
    end
end)

RegisterNetEvent('trucking:server:vehicleMoving', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    stationaryTimers[bolId] = nil
end)

-- Server tick checks abandonment (every 30 seconds)
CreateThread(function()
    while true do
        Wait(30000)
        local now = GetServerTime()
        for bolId, startTime in pairs(stationaryTimers) do
            if (now - startTime) >= 600 then -- 10 minutes
                -- Trigger seal break if the load has a seal
                local activeLoad = ActiveLoads[bolId]
                if activeLoad and activeLoad.seal_status == 'sealed' then
                    -- Seal break due to abandonment -- missions.lua handles the consequences
                    local playerSrc = GetPlayerSource(activeLoad.citizenid)
                    if playerSrc then
                        TriggerEvent('trucking:server:sealBreak', bolId, 'abandonment_timeout')
                    end
                end
                stationaryTimers[bolId] = nil
            end
        end
    end
end)

-- ============================================================================
-- BOARD REFRESH TIMERS (Staggered per region)
-- Each region refreshes on a 2-hour cycle with an offset from config.
-- ============================================================================

function StartBoardRefreshTimers()
    local regions = { 'los_santos', 'sandy_shores', 'paleto', 'grapeseed' }
    local offsets = BoardConfig and BoardConfig.RefreshOffsets or {
        los_santos   = 0,
        sandy_shores = 1800,
        paleto       = 900,
        grapeseed    = 2700,
    }
    local interval = (Config and Config.BoardRefreshSeconds) or 7200 -- 2 hours in seconds

    for _, region in ipairs(regions) do
        local offset = offsets[region] or 0

        CreateThread(function()
            -- Calculate initial wait: align to the refresh cycle with offset
            local now = GetServerTime()
            local cyclePosition = (now % interval)
            local initialWait = offset - cyclePosition
            if initialWait < 0 then
                initialWait = initialWait + interval
            end

            -- Wait for the staggered offset
            if initialWait > 0 then
                Wait(initialWait * 1000)
            end

            -- First refresh immediately after offset alignment
            RefreshBoard(region)

            -- Then refresh on the regular interval
            while true do
                Wait(interval * 1000)
                RefreshBoard(region)
            end
        end)

        print(('[trucking] Board refresh timer started for %s (offset: %ds, interval: %ds)'):format(
            region, offset, interval
        ))
    end
end

-- ============================================================================
-- PRE-TRIP COMPLETION HANDLER
-- ============================================================================

RegisterNetEvent('trucking:server:preTripComplete', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'preTripComplete', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end
    if activeLoad.pre_trip_completed then return end -- already done

    -- Update active load
    activeLoad.pre_trip_completed = true
    ActiveLoads[bolId] = activeLoad
    DB.UpdateActiveLoad(activeLoad.id, { pre_trip_completed = true })

    -- Update BOL
    DB.UpdateBOL(bolId, { pre_trip_completed = true })

    -- Log the event
    local bol = DB.GetBOL(bolId)
    if bol then
        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = activeLoad.citizenid,
            event_type = 'load_accepted', -- pre-trip is part of acceptance flow
            event_data = { pre_trip_completed = true },
        })
    end
end)

-- ============================================================================
-- RESOURCE STOP (cleanup)
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    print('[trucking] Resource stopping -- saving state...')

    -- Update last_seen for all online players
    local players = exports.qbx_core:GetQBPlayers()
    for src, player in pairs(players) do
        if player and player.PlayerData then
            DB.UpdateDriver(player.PlayerData.citizenid, { last_seen = GetServerTime() })
        end
    end

    print('[trucking] State saved. Resource stopped.')
end)
