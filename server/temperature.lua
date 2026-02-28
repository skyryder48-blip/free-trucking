--[[
    server/temperature.lua — Server-Side Temperature and Excursion Tracking

    Handles reefer fault detection, engine-off tracking, and temperature
    excursion lifecycle management. All timing is server-authoritative
    using GetServerTime(). Client reports state changes (reefer fault/restore,
    engine on/off) and server tracks durations for payout impact.

    Temperature states:
        IN RANGE     — reefer operational, temp within BOL spec
        OUT OF RANGE — reefer faulted or engine off 5+ minutes

    Excursion consequences (applied at delivery in payout.lua):
        < 5 minutes   — none (clean)
        5-15 minutes  — minor_excursion (-15% payout)
        15+ minutes   — significant_excursion (-35% payout)

    Reefer fault triggers:
        - Vehicle health drops below threshold (65% standard, 80% pharmaceutical)
        - Engine off for 5+ minutes

    Reefer restoration:
        - Vehicle repaired above health threshold -> auto-restore
        - Engine turned back on -> engine-off timer cleared

    All events validated via ValidateLoadOwner from server/main.lua.
    Server-side health verification cross-checks client-reported values
    with ±50 tolerance for network latency.
]]

-- ─────────────────────────────────────────────
-- IN-MEMORY STATE
-- ─────────────────────────────────────────────

--- Tracks when a reefer fault started (from health drop or engine-off threshold)
--- [bol_id] = GetServerTime() when fault was detected
local reeferFaults = {}

--- Tracks when the engine was turned off for temperature-monitored loads
--- [bol_id] = GetServerTime() when engine turned off
local engineOffTimers = {}

-- ─────────────────────────────────────────────
-- CONSTANTS
-- ─────────────────────────────────────────────

local ENGINE_OFF_THRESHOLD_SECS = 300   -- 5 minutes before engine-off triggers excursion
local HEALTH_TOLERANCE = 50             -- ±50 tolerance for client/server health comparison
local EXCURSION_MINOR_MINS = 5          -- minutes — matches Config.ExcursionMinorMins
local EXCURSION_SIGNIFICANT_MINS = 15   -- minutes — matches Config.ExcursionSignificantMins

-- ─────────────────────────────────────────────
-- EXCURSION LIFECYCLE
-- ─────────────────────────────────────────────

--- Start a temperature excursion event
--- Logs to BOL events and updates the active load record
---@param bolId number The BOL ID experiencing the excursion
function StartExcursion(bolId)
    if not bolId then return end

    -- Update active load record
    if ActiveLoads and ActiveLoads[bolId] then
        ActiveLoads[bolId].excursion_active = true
        ActiveLoads[bolId].excursion_start = GetServerTime()

        -- Persist to database
        MySQL.update.await([[
            UPDATE truck_active_loads
            SET excursion_active = TRUE, excursion_start = ?
            WHERE bol_id = ?
        ]], { GetServerTime(), bolId })
    end

    -- Log BOL event
    local activeLoad = ActiveLoads and ActiveLoads[bolId]
    local citizenid = activeLoad and activeLoad.citizenid or nil
    local bolNumber = activeLoad and activeLoad.bol_number or nil

    if citizenid and bolNumber then
        MySQL.insert.await([[
            INSERT INTO truck_bol_events
            (bol_id, bol_number, citizenid, event_type, event_data, occurred_at)
            VALUES (?, ?, ?, 'temp_excursion_start', ?, ?)
        ]], {
            bolId, bolNumber, citizenid,
            json.encode({ source = reeferFaults[bolId] and 'reefer_fault' or 'engine_off' }),
            GetServerTime()
        })
    end

    -- Notify the player
    if activeLoad and activeLoad.src then
        TriggerClientEvent('trucking:client:excursionStarted', activeLoad.src, bolId)
    end

    print(('[trucking:temperature] Excursion started for BOL %d'):format(bolId))
end

--- End a temperature excursion and calculate severity
--- Updates BOL temp_compliance based on total excursion duration
---@param bolId number The BOL ID
---@param duration number Duration of this excursion in seconds
function EndExcursion(bolId, duration)
    if not bolId then return end

    local durationMins = duration / 60.0

    -- Determine severity
    local severity = 'none'
    local compliance = 'clean'
    if durationMins >= EXCURSION_SIGNIFICANT_MINS then
        severity = 'significant'
        compliance = 'significant_excursion'
    elseif durationMins >= EXCURSION_MINOR_MINS then
        severity = 'minor'
        compliance = 'minor_excursion'
    end
    -- Under 5 minutes: no impact, stays clean

    -- Update active load record
    if ActiveLoads and ActiveLoads[bolId] then
        ActiveLoads[bolId].excursion_active = false
        ActiveLoads[bolId].excursion_start = nil
        -- Accumulate total excursion time
        ActiveLoads[bolId].excursion_total_mins =
            (ActiveLoads[bolId].excursion_total_mins or 0) + math.floor(durationMins)

        -- Persist to database
        MySQL.update.await([[
            UPDATE truck_active_loads
            SET excursion_active = FALSE, excursion_start = NULL,
                excursion_total_mins = ?
            WHERE bol_id = ?
        ]], { ActiveLoads[bolId].excursion_total_mins, bolId })
    end

    -- Update BOL temp_compliance (only escalate, never downgrade)
    -- significant > minor > clean — only update if new severity is worse
    if compliance ~= 'clean' then
        local currentCompliance = nil
        local bol = MySQL.single.await(
            'SELECT temp_compliance FROM truck_bols WHERE id = ?',
            { bolId }
        )
        if bol then
            currentCompliance = bol.temp_compliance
        end

        local complianceOrder = {
            not_required = 0,
            clean = 1,
            minor_excursion = 2,
            significant_excursion = 3,
        }
        local currentLevel = complianceOrder[currentCompliance] or 0
        local newLevel = complianceOrder[compliance] or 0

        if newLevel > currentLevel then
            MySQL.update.await(
                'UPDATE truck_bols SET temp_compliance = ? WHERE id = ?',
                { compliance, bolId }
            )
        end
    end

    -- Log BOL event for excursion end
    local activeLoad = ActiveLoads and ActiveLoads[bolId]
    local citizenid = activeLoad and activeLoad.citizenid or nil
    local bolNumber = activeLoad and activeLoad.bol_number or nil

    if citizenid and bolNumber then
        MySQL.insert.await([[
            INSERT INTO truck_bol_events
            (bol_id, bol_number, citizenid, event_type, event_data, occurred_at)
            VALUES (?, ?, ?, 'temp_excursion_end', ?, ?)
        ]], {
            bolId, bolNumber, citizenid,
            json.encode({
                duration_seconds = duration,
                duration_minutes = math.floor(durationMins * 10) / 10,
                severity = severity,
                compliance = compliance,
            }),
            GetServerTime()
        })
    end

    -- Notify the player
    if activeLoad and activeLoad.src then
        TriggerClientEvent('trucking:client:excursionEnded', activeLoad.src, bolId, {
            duration = duration,
            severity = severity,
        })
    end

    print(('[trucking:temperature] Excursion ended for BOL %d: %d sec (%s)'):format(
        bolId, duration, severity))
end

--- Get the current excursion state for a BOL (for NUI display)
---@param bolId number The BOL ID
---@return table state { active, startTime, elapsedSeconds, totalMinutes }
function GetExcursionStatus(bolId)
    if not bolId then
        return { active = false, startTime = nil, elapsedSeconds = 0, totalMinutes = 0 }
    end

    local isActive = reeferFaults[bolId] ~= nil
    local elapsed = 0
    if isActive and reeferFaults[bolId] then
        elapsed = GetServerTime() - reeferFaults[bolId]
    end

    local totalMins = 0
    if ActiveLoads and ActiveLoads[bolId] then
        totalMins = ActiveLoads[bolId].excursion_total_mins or 0
    end

    return {
        active = isActive,
        startTime = reeferFaults[bolId],
        elapsedSeconds = elapsed,
        totalMinutes = totalMins,
    }
end

-- ─────────────────────────────────────────────
-- NET EVENT HANDLERS
-- All validate source with ValidateLoadOwner
-- ─────────────────────────────────────────────

--- Client reports reefer fault (vehicle health dropped below threshold)
RegisterNetEvent('trucking:server:reeferFault', function(bolId, clientHealth)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end

    -- Server-side health verification: get entity health from server
    -- and compare against client-reported value with ±50 tolerance
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local vehicle = GetVehiclePedIsUsing(ped)
        if vehicle and vehicle ~= 0 then
            local serverHealth = GetEntityHealth(vehicle)
            if math.abs(serverHealth - (clientHealth or 0)) > HEALTH_TOLERANCE then
                -- Health mismatch beyond tolerance — reject event
                print(('[trucking:temperature] Health mismatch for BOL %d: client=%s server=%d'):format(
                    bolId, tostring(clientHealth), serverHealth))
                return
            end
        end
    end

    -- Only register fault if not already faulted
    if reeferFaults[bolId] then return end

    reeferFaults[bolId] = GetServerTime()
    StartExcursion(bolId)

    -- Log reefer failure BOL event
    local activeLoad = ActiveLoads and ActiveLoads[bolId]
    if activeLoad then
        MySQL.insert.await([[
            INSERT INTO truck_bol_events
            (bol_id, bol_number, citizenid, event_type, event_data, occurred_at)
            VALUES (?, ?, ?, 'reefer_failure', ?, ?)
        ]], {
            bolId, activeLoad.bol_number or '', activeLoad.citizenid or '',
            json.encode({ client_health = clientHealth }),
            GetServerTime()
        })

        -- Update active load reefer status
        if ActiveLoads[bolId] then
            ActiveLoads[bolId].reefer_operational = false
        end
        MySQL.update.await(
            'UPDATE truck_active_loads SET reefer_operational = FALSE WHERE bol_id = ?',
            { bolId }
        )
    end

    print(('[trucking:temperature] Reefer fault detected for BOL %d (health: %s)'):format(
        bolId, tostring(clientHealth)))
end)

--- Client reports reefer restored (vehicle repaired above threshold)
RegisterNetEvent('trucking:server:reeferRestored', function(bolId, clientHealth)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end

    if not reeferFaults[bolId] then return end

    local duration = GetServerTime() - reeferFaults[bolId]
    reeferFaults[bolId] = nil

    -- Also clear engine-off timer if present (reefer is working again)
    engineOffTimers[bolId] = nil

    EndExcursion(bolId, duration)

    -- Log reefer restored BOL event
    local activeLoad = ActiveLoads and ActiveLoads[bolId]
    if activeLoad then
        MySQL.insert.await([[
            INSERT INTO truck_bol_events
            (bol_id, bol_number, citizenid, event_type, event_data, occurred_at)
            VALUES (?, ?, ?, 'reefer_restored', ?, ?)
        ]], {
            bolId, activeLoad.bol_number or '', activeLoad.citizenid or '',
            json.encode({ client_health = clientHealth, duration_seconds = duration }),
            GetServerTime()
        })

        -- Update active load reefer status
        if ActiveLoads[bolId] then
            ActiveLoads[bolId].reefer_operational = true
        end
        MySQL.update.await(
            'UPDATE truck_active_loads SET reefer_operational = TRUE WHERE bol_id = ?',
            { bolId }
        )
    end

    print(('[trucking:temperature] Reefer restored for BOL %d (duration: %d sec)'):format(
        bolId, duration))
end)

--- Client reports engine turned off
RegisterNetEvent('trucking:server:engineOff', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end

    -- Only track for temperature-monitored loads
    if ActiveLoads and ActiveLoads[bolId] then
        if not ActiveLoads[bolId].temp_monitoring_active then
            return
        end
    end

    engineOffTimers[bolId] = GetServerTime()

    print(('[trucking:temperature] Engine off detected for BOL %d'):format(bolId))
end)

--- Client reports engine turned back on
RegisterNetEvent('trucking:server:engineOn', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end

    engineOffTimers[bolId] = nil

    print(('[trucking:temperature] Engine on for BOL %d'):format(bolId))
end)

-- ─────────────────────────────────────────────
-- ENGINE-OFF CHECK THREAD
-- Runs every 30 seconds. If engine has been off for 5+ minutes
-- and no reefer fault is already active, trigger an excursion
-- by backdating the fault to the engine-off time.
-- ─────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(30000)  -- 30 seconds
        local now = GetServerTime()

        for bolId, offTime in pairs(engineOffTimers) do
            local elapsed = now - offTime
            if elapsed >= ENGINE_OFF_THRESHOLD_SECS and not reeferFaults[bolId] then
                -- Backdate the reefer fault to engine-off time so the full
                -- duration is captured when the engine is eventually turned on
                -- or the reefer is otherwise restored
                reeferFaults[bolId] = offTime
                StartExcursion(bolId)

                print(('[trucking:temperature] Engine-off excursion triggered for BOL %d (off for %d sec)'):format(
                    bolId, elapsed))
            end
        end
    end
end)

-- ─────────────────────────────────────────────
-- NUI QUERY
-- ─────────────────────────────────────────────

RegisterNetEvent('trucking:server:getExcursionStatus', function(bolId)
    local src = source
    if not bolId then return end

    local status = GetExcursionStatus(bolId)
    TriggerClientEvent('trucking:client:excursionStatus', src, bolId, status)
end)

-- ─────────────────────────────────────────────
-- CLEANUP
-- Called when a load is completed, abandoned, or stolen
-- ─────────────────────────────────────────────

--- Clean up temperature tracking state for a BOL
--- Called by delivery/failure handlers in missions.lua
---@param bolId number The BOL ID to clean up
function CleanupTemperatureTracking(bolId)
    if not bolId then return end

    -- If there's an active excursion, end it now
    if reeferFaults[bolId] then
        local duration = GetServerTime() - reeferFaults[bolId]
        reeferFaults[bolId] = nil
        EndExcursion(bolId, duration)
    end

    engineOffTimers[bolId] = nil

    print(('[trucking:temperature] Cleaned up temperature tracking for BOL %d'):format(bolId))
end

-- ─────────────────────────────────────────────
-- CLEANUP ON PLAYER DROP
-- ─────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- Find any active loads belonging to this player and handle excursions
    if ActiveLoads then
        for bolId, load in pairs(ActiveLoads) do
            if load.citizenid == citizenid then
                -- If excursion is active, the load abandonment handler will
                -- call CleanupTemperatureTracking. We just clear engine-off
                -- timers here to prevent orphaned entries.
                engineOffTimers[bolId] = nil
            end
        end
    end
end)

print('[trucking:temperature] Temperature monitoring system initialized')
