--[[
    client/seals.lua — Seal Monitoring (Section 14)
    Free Trucking — QBX Framework

    Responsibilities:
    - StartSealMonitoring(activeLoad): begin 5-second interval check
    - Check trailer coupling: if decoupled during in_transit without transfer authorization,
      report seal break to server
    - Abandonment detection: report stationary/moving state to server
      (server tracks actual timing — client never determines abandonment)
    - StopSealMonitoring(): clear interval on delivery/abandon
    - All timing uses GetGameTimer(), never os.time()
    - Events: trucking:server:sealBreak, trucking:server:vehicleStationary,
      trucking:server:vehicleMoving
]]

-- ─────────────────────────────────────────────
-- LOCAL STATE
-- ─────────────────────────────────────────────
local sealMonitorThread = nil
local abandonmentReported = false         -- whether we reported stationary to server
local lastStationaryCheck = 0             -- GetGameTimer() value
local sealBroken = false                  -- prevent duplicate seal break reports
local transferAuthorized = false          -- set true during authorized transfer window

-- ─────────────────────────────────────────────
-- START SEAL MONITORING
-- ─────────────────────────────────────────────

--- Begin seal monitoring for an active load.
--- Runs a 5-second interval check for trailer decoupling and vehicle stationary state.
--- Only monitors if the load's seal_status is 'sealed'.
---@param activeLoad table Active load data from server
function StartSealMonitoring(activeLoad)
    -- Guard: only monitor sealed loads
    if not activeLoad then return end
    if activeLoad.seal_status ~= 'sealed' then return end

    StopSealMonitoring()

    sealBroken = false
    abandonmentReported = false
    transferAuthorized = false
    lastStationaryCheck = GetGameTimer()

    sealMonitorThread = CreateThread(function()
        while ActiveLoad and not sealBroken do
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            -- ─── TRAILER COUPLING CHECK ───
            if ActiveLoad.status == 'in_transit' or ActiveLoad.status == 'at_stop' then
                if vehicle and vehicle ~= 0 then
                    local hasTrailer, trailer = GetVehicleTrailerVehicle(vehicle)

                    -- Trailer should be coupled during transit.
                    -- If decoupled without transfer authorization, report seal break.
                    if not hasTrailer or not trailer or trailer == 0 then
                        if not transferAuthorized and not sealBroken then
                            sealBroken = true
                            TriggerServerEvent('trucking:server:sealBreak',
                                ActiveLoad.bol_id,
                                'unauthorized_decouple'
                            )

                            lib.notify({
                                title = 'Seal Broken',
                                description = 'Trailer decoupled — seal has been broken',
                                type = 'error',
                                duration = 8000,
                            })
                        end
                    end
                end

                -- ─── ABANDONMENT / STATIONARY DETECTION ───
                -- Report stationary/moving state changes to server.
                -- Server tracks actual abandonment timing (10 minutes).
                -- Client only reports state transitions, never makes abandonment decisions.
                if vehicle and vehicle ~= 0 then
                    local isStationary = GetEntitySpeed(vehicle) < 0.5

                    if isStationary and not abandonmentReported then
                        abandonmentReported = true
                        TriggerServerEvent('trucking:server:vehicleStationary', ActiveLoad.bol_id)
                    elseif not isStationary and abandonmentReported then
                        abandonmentReported = false
                        TriggerServerEvent('trucking:server:vehicleMoving', ActiveLoad.bol_id)
                    end
                else
                    -- Player is not in a vehicle — consider stationary
                    if not abandonmentReported then
                        abandonmentReported = true
                        TriggerServerEvent('trucking:server:vehicleStationary', ActiveLoad.bol_id)
                    end
                end
            end

            Wait(Config.SealCheckInterval or 5000)
        end
    end)
end

-- ─────────────────────────────────────────────
-- STOP SEAL MONITORING
-- ─────────────────────────────────────────────

--- Stop the seal monitoring thread. Called on delivery, abandon, or resource stop.
function StopSealMonitoring()
    sealMonitorThread = nil
    abandonmentReported = false
    sealBroken = false
    transferAuthorized = false
end

-- ─────────────────────────────────────────────
-- EVENT HANDLERS
-- ─────────────────────────────────────────────

--- Start seal monitoring event (from missions.lua or main.lua)
RegisterNetEvent('trucking:client:startSealMonitoring', function()
    if ActiveLoad then
        StartSealMonitoring(ActiveLoad)
    end
end)

--- Stop seal monitoring event
RegisterNetEvent('trucking:client:stopSealMonitoring', function()
    StopSealMonitoring()
end)

--- Authorize transfer — temporarily allow decoupling without seal break.
--- Called when a transfer is initiated and accepted by both drivers.
RegisterNetEvent('trucking:client:authorizeTransfer', function()
    transferAuthorized = true

    -- Auto-revoke after 60 seconds if transfer does not complete
    CreateThread(function()
        Wait(60000)
        if transferAuthorized then
            transferAuthorized = false
        end
    end)
end)

--- Transfer completed — stop monitoring on this client (load transferred away)
RegisterNetEvent('trucking:client:transferCompleted', function(data)
    if not data then return end

    StopSealMonitoring()

    lib.notify({
        title = 'Transfer Complete',
        description = 'BOL #' .. (data.bolNumber or '?') .. ' has been transferred',
        type = 'success',
    })
end)

--- Server notifies that seal was broken (e.g., from robbery or server-side detection)
RegisterNetEvent('trucking:client:sealBroken', function(data)
    if not ActiveLoad then return end

    sealBroken = true
    ActiveLoad.seal_status = 'broken'

    local causeLabels = {
        unauthorized_decouple = 'Trailer decoupled without authorization',
        robbery = 'Seal broken during robbery',
        abandonment = 'Seal broken due to abandonment',
    }

    lib.notify({
        title = 'Seal Status: BROKEN',
        description = causeLabels[data and data.cause] or 'Seal has been broken',
        type = 'error',
        duration = 10000,
    })
end)

-- ─────────────────────────────────────────────
-- CLEANUP ON RESOURCE STOP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopSealMonitoring()
end)
