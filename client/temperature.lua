--[[
    client/temperature.lua — Reefer Temperature Monitoring
    Free Trucking — QBX Framework

    Responsibilities:
    - Track reefer fault state and engine-off state (booleans)
    - Report state CHANGES to server (server tracks all timing/excursions)
    - Display temperature status on HUD (in-range vs out-of-range)
    - Notify player on fault and restoration
    - Provide Start/Stop lifecycle management

    Authority model:
    - Client detects vehicle health vs threshold, engine running state
    - Client reports state transitions only (not periodic polling)
    - Server validates health cross-check, tracks all excursion timing
    - No payout or reputation logic runs here
]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local reeferFaulted = false
local engineOffReported = false
local tempMonitoringActive = false
local monitorThread = nil

-- ─────────────────────────────────────────────
-- HEALTH THRESHOLD RESOLUTION
-- ─────────────────────────────────────────────

--- Determine the correct reefer health threshold for the current load.
--- Pharmaceutical loads use a stricter threshold (80%), standard cold
--- chain uses the default (65%).
---@param activeLoad table The active load data from server
---@return number threshold Health percentage threshold (0-100 scale mapped to entity health)
local function GetReeferThreshold(activeLoad)
    if activeLoad.pharma or activeLoad.cargo_type == 'pharmaceutical'
        or activeLoad.cargo_type == 'pharmaceutical_biologic' then
        return Config.PharmaHealthThreshold or 80
    end
    return Config.ReeferHealthThreshold or 65
end

--- Convert entity health (0-1000) to a percentage (0-100).
--- GetEntityHealth returns 0-1000 for vehicles; 0 is destroyed, 1000 is pristine.
---@param vehicle number Vehicle entity handle
---@return number healthPct Health as percentage 0-100
local function GetVehicleHealthPercent(vehicle)
    if not vehicle or vehicle == 0 then return 0 end
    local health = GetEntityHealth(vehicle)
    local maxHealth = GetEntityMaxHealth(vehicle)
    if maxHealth <= 0 then maxHealth = 1000 end
    return math.floor((health / maxHealth) * 100)
end

-- ─────────────────────────────────────────────
-- CORE UPDATE FUNCTION
-- ─────────────────────────────────────────────

--- Called every 2 seconds while temp monitoring is active.
--- Checks vehicle health against the load's reefer threshold and
--- engine running state. Fires server events ONLY on state transitions.
---@param activeLoad table The active load data
function UpdateTemperatureState(activeLoad)
    if not activeLoad then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return end

    local healthPct = GetVehicleHealthPercent(vehicle)
    local threshold = GetReeferThreshold(activeLoad)
    local reeferOk = healthPct >= threshold

    -- ── Reefer fault detection (state change only) ──
    if not reeferOk and not reeferFaulted then
        reeferFaulted = true
        TriggerServerEvent('trucking:server:reeferFault', activeLoad.bol_id, healthPct)

        lib.notify({
            title = 'Reefer Fault',
            description = 'Temperature control lost — vehicle health below '
                .. threshold .. '%. Seek repairs immediately.',
            type = 'error',
            duration = 8000,
        })

        -- Update HUD to out-of-range state
        SendNUIMessage({
            action = 'tempStatus',
            data = {
                inRange = false,
                faulted = true,
                healthPct = healthPct,
                threshold = threshold,
            },
        })

    elseif reeferOk and reeferFaulted then
        reeferFaulted = false
        TriggerServerEvent('trucking:server:reeferRestored', activeLoad.bol_id, healthPct)

        lib.notify({
            title = 'Reefer Restored',
            description = 'Temperature control online — reefer operating normally.',
            type = 'success',
            duration = 5000,
        })

        -- Update HUD to in-range state
        SendNUIMessage({
            action = 'tempStatus',
            data = {
                inRange = true,
                faulted = false,
                healthPct = healthPct,
                threshold = threshold,
            },
        })
    end

    -- ── Engine off detection (state change only) ──
    local engineRunning = GetIsVehicleEngineRunning(vehicle)

    if not engineRunning and not engineOffReported then
        engineOffReported = true
        TriggerServerEvent('trucking:server:engineOff', activeLoad.bol_id)

    elseif engineRunning and engineOffReported then
        engineOffReported = false
        TriggerServerEvent('trucking:server:engineOn', activeLoad.bol_id)
    end

    -- ── Periodic HUD update (non-fault state) ──
    if not reeferFaulted then
        SendNUIMessage({
            action = 'tempStatus',
            data = {
                inRange = true,
                faulted = false,
                healthPct = healthPct,
                threshold = threshold,
                engineRunning = engineRunning,
            },
        })
    end
end

-- ─────────────────────────────────────────────
-- LIFECYCLE MANAGEMENT
-- ─────────────────────────────────────────────

--- Start temperature monitoring for the current active load.
--- Creates a polling thread that calls UpdateTemperatureState every 2 seconds.
--- Safe to call multiple times — will not create duplicate threads.
---@param activeLoad table The active load data from server
function StartTempMonitoring(activeLoad)
    if tempMonitoringActive then return end
    if not activeLoad then return end

    -- Only monitor loads that require temperature control
    if not activeLoad.temp_monitoring_active and not activeLoad.temp_required then
        return
    end

    tempMonitoringActive = true
    reeferFaulted = false
    engineOffReported = false

    lib.notify({
        title = 'Reefer Monitoring',
        description = 'Temperature monitoring active',
        type = 'inform',
    })

    -- Initial HUD state
    SendNUIMessage({
        action = 'tempStatus',
        data = {
            inRange = true,
            faulted = false,
            monitoring = true,
        },
    })

    -- Monitoring thread: runs every 2 seconds while active
    CreateThread(function()
        while tempMonitoringActive do
            -- Ensure we still have an active load
            if not ActiveLoad then
                StopTempMonitoring()
                return
            end

            UpdateTemperatureState(ActiveLoad)
            Wait(2000)
        end
    end)
end

--- Stop temperature monitoring and reset all state.
--- Safe to call even if monitoring is not active.
function StopTempMonitoring()
    if not tempMonitoringActive then return end

    tempMonitoringActive = false
    reeferFaulted = false
    engineOffReported = false

    -- Clear HUD temperature display
    SendNUIMessage({
        action = 'tempStatus',
        data = {
            monitoring = false,
            inRange = false,
            faulted = false,
        },
    })
end

--- Check if temperature monitoring is currently active.
---@return boolean active
function IsTempMonitoringActive()
    return tempMonitoringActive
end

-- ─────────────────────────────────────────────
-- EVENT LISTENERS
-- ─────────────────────────────────────────────

--- Resume temp monitoring after reconnect or resource restart.
--- Called by the main client monitoring resume system.
AddEventHandler('trucking:client:resumeMonitoring', function()
    if ActiveLoad and (ActiveLoad.temp_monitoring_active or ActiveLoad.temp_required) then
        StartTempMonitoring(ActiveLoad)
    end
end)

--- Stop all monitoring on state cleanup.
AddEventHandler('trucking:client:stopAllMonitoring', function()
    StopTempMonitoring()
end)

--- Server notifies client that excursion classification changed.
--- Display-only: server is authoritative on excursion status.
RegisterNetEvent('trucking:client:excursionUpdate', function(data)
    if not data then return end

    if data.status == 'minor_excursion' then
        lib.notify({
            title = 'Temperature Excursion',
            description = 'Minor excursion detected — resolve within '
                .. (Config.ExcursionSignificantMins or 15) .. ' minutes to avoid payout penalty.',
            type = 'warning',
            duration = 8000,
        })
    elseif data.status == 'significant_excursion' then
        lib.notify({
            title = 'Significant Excursion',
            description = 'Temperature excursion exceeds threshold — payout penalty applied.',
            type = 'error',
            duration = 10000,
        })
    end

    -- Update HUD with server-authoritative excursion state
    SendNUIMessage({
        action = 'excursionUpdate',
        data = data,
    })
end)

-- ─────────────────────────────────────────────
-- RESOURCE CLEANUP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopTempMonitoring()
end)
