--[[
    client/missions.lua — Active Load Client Tracking
    Free Trucking — QBX Framework

    Responsibilities:
    - Active load state management
    - GPS waypoint management (set on accept, update on multi-stop)
    - Delivery zone creation (lib.zones.box at destination, sized by tier)
    - Delivery window countdown (display via HUD)
    - Distance remaining calculation (client-side, for display only)
    - Multi-stop progression tracking
    - Transfer mechanic (proximity check, initiate/accept UI)
    - Distress signal button
    - Load state transitions triggered by server events
]]

-- ─────────────────────────────────────────────
-- LOCAL STATE
-- ─────────────────────────────────────────────
local deliveryZone = nil
local gpsBlip = nil
local missionThread = nil
local distanceRemaining = 0.0
local windowStartTimer = nil
local transferCooldown = 0

-- ─────────────────────────────────────────────
-- MISSION START
-- ─────────────────────────────────────────────
--- Triggered when a load is accepted. Sets up GPS, delivery zone, and monitoring.
RegisterNetEvent('trucking:client:missionStart', function()
    if not ActiveLoad or not ActiveBOL then return end

    windowStartTimer = GetGameTimer()

    -- Set GPS waypoint to origin (if at_origin) or destination (if in_transit)
    local destination = GetCurrentDestination()
    if destination then
        SetGPSWaypoint(destination)
    end

    -- Create delivery zone at destination
    CreateDeliveryZone()

    -- Start mission tracking thread
    StartMissionThread()
end)

--- Resume monitoring after reconnect
RegisterNetEvent('trucking:client:resumeMonitoring', function()
    if not ActiveLoad or not ActiveBOL then return end

    windowStartTimer = GetGameTimer()

    local destination = GetCurrentDestination()
    if destination then
        SetGPSWaypoint(destination)
    end

    CreateDeliveryZone()
    StartMissionThread()

    -- Resume seal monitoring if applicable
    if ActiveLoad.seal_status == 'sealed' then
        TriggerEvent('trucking:client:startSealMonitoring')
    end

    -- Resume vehicle monitoring
    TriggerEvent('trucking:client:startVehicleMonitoring')

    -- Show HUD
    TriggerEvent('trucking:client:showHUD')
end)

-- ─────────────────────────────────────────────
-- GPS WAYPOINT MANAGEMENT
-- ─────────────────────────────────────────────
--- Set GPS blip at specified coordinates
---@param coords vector3 Destination coordinates
function SetGPSWaypoint(coords)
    ClearGPSWaypoint()

    -- Set map waypoint
    SetNewWaypoint(coords.x, coords.y)

    -- Create blip for minimap
    gpsBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(gpsBlip, 477)           -- truck icon
    SetBlipColour(gpsBlip, 47)            -- Bears orange
    SetBlipScale(gpsBlip, 0.9)
    SetBlipAsShortRange(gpsBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Delivery Destination')
    EndTextCommandSetBlipName(gpsBlip)
end

--- Clear GPS blip and waypoint
function ClearGPSWaypoint()
    if gpsBlip then
        if DoesBlipExist(gpsBlip) then
            RemoveBlip(gpsBlip)
        end
        gpsBlip = nil
    end
end

--- Listen for GPS clear event
RegisterNetEvent('trucking:client:clearGPS', function()
    ClearGPSWaypoint()
    DeleteWaypoint()
end)

--- Get current destination coordinates based on load status and multi-stop state
---@return vector3|nil coords
function GetCurrentDestination()
    if not ActiveLoad or not ActiveBOL then return nil end

    -- Multi-stop: get current stop destination
    if ActiveLoad.is_multi_stop and ActiveLoad.stops then
        local currentStopIdx = ActiveLoad.current_stop or 1
        local stop = ActiveLoad.stops[currentStopIdx]
        if stop and stop.coords then
            return vector3(stop.coords.x, stop.coords.y, stop.coords.z)
        end
    end

    -- Single stop: use main destination
    if ActiveBOL.destination_coords then
        local dc = ActiveBOL.destination_coords
        -- Handle both table and vector3 formats
        if type(dc) == 'vector3' then
            return dc
        elseif type(dc) == 'table' then
            return vector3(dc.x or dc[1], dc.y or dc[2], dc.z or dc[3])
        end
    end

    return nil
end

-- ─────────────────────────────────────────────
-- DELIVERY ZONE
-- ─────────────────────────────────────────────
--- Create delivery zone at destination based on tier and cargo type.
function CreateDeliveryZone()
    RemoveDeliveryZone()

    local destination = GetCurrentDestination()
    if not destination then return end

    local tier = ActiveBOL.tier or 0
    local cargoType = ActiveBOL.cargo_type or ''

    -- Determine zone size
    local zoneSize
    if IsOversizedCargo(cargoType) then
        zoneSize = Config.OversizedZoneOverride or vec3(8.0, 5.0, 3.0)
    else
        zoneSize = Config.DeliveryZoneSizes and Config.DeliveryZoneSizes[tier]
            or vec3(12.0, 8.0, 3.0)
    end

    -- Get heading for the zone (from stop data if available, else 0)
    local heading = 0
    if ActiveLoad.is_multi_stop and ActiveLoad.stops then
        local stop = ActiveLoad.stops[ActiveLoad.current_stop or 1]
        if stop and stop.heading then
            heading = stop.heading
        end
    end

    deliveryZone = lib.zones.box({
        coords = destination,
        size = zoneSize,
        rotation = heading,
        debug = false,
        onEnter = function()
            if ActiveLoad and (ActiveLoad.status == 'in_transit' or ActiveLoad.status == 'at_stop') then
                ActiveLoad.status = 'at_destination'
                TriggerServerEvent('trucking:server:arrivedAtDestination', ActiveLoad.bol_id)

                lib.showTextUI('[E] Talk to Receiving Dock', {
                    icon = 'fas fa-warehouse',
                })
            end
        end,
        onExit = function()
            lib.hideTextUI()
        end,
        inside = function()
            if ActiveLoad and IsControlJustReleased(0, 38) then -- E key
                OpenDeliveryInteraction()
            end
        end,
    })
end

--- Remove delivery zone
function RemoveDeliveryZone()
    if deliveryZone then
        deliveryZone:remove()
        deliveryZone = nil
    end
end

--- Listen for delivery zone removal event
RegisterNetEvent('trucking:client:removeDeliveryZone', function()
    RemoveDeliveryZone()
end)

-- ─────────────────────────────────────────────
-- MISSION TRACKING THREAD
-- ─────────────────────────────────────────────
--- Main thread that runs every second while a load is active.
--- Updates distance remaining and delivery window countdown.
function StartMissionThread()
    StopMissionThread()

    missionThread = CreateThread(function()
        while ActiveLoad and ActiveBOL do
            local destination = GetCurrentDestination()

            -- Calculate distance remaining
            if destination then
                local playerCoords = GetEntityCoords(PlayerPedId())
                distanceRemaining = #(playerCoords - destination)
            end

            -- Calculate time remaining
            local windowRemainingMs = CalculateWindowRemaining()

            -- Determine border state for HUD
            local borderState = 'normal'
            if ActiveLoad.cargo_integrity and ActiveLoad.cargo_integrity < 50 then
                borderState = 'critical'
            elseif windowRemainingMs > 0 then
                local windowTotalMs = CalculateWindowTotal()
                local windowPct = windowRemainingMs / windowTotalMs
                if windowPct < 0.10 then
                    borderState = 'critical'
                elseif windowPct < 0.25 then
                    borderState = 'warning'
                end
            elseif windowRemainingMs <= 0 then
                borderState = 'critical'
            end

            -- Send data to HUD
            TriggerEvent('trucking:client:hudData', {
                bolNumber = ActiveBOL.bol_number,
                cargoType = ActiveBOL.cargo_type,
                destination = GetCurrentDestinationLabel(),
                distanceRemaining = distanceRemaining,
                windowRemainingMs = windowRemainingMs,
                temperature = ActiveLoad.current_temp_f,
                tempRequired = ActiveBOL.temp_required_min ~= nil,
                integrity = ActiveLoad.cargo_integrity or 100,
                borderState = borderState,
                currentStop = ActiveLoad.current_stop,
                totalStops = ActiveLoad.stop_count,
                isMultiStop = ActiveLoad.is_multi_stop,
            })

            Wait(1000)
        end
    end)
end

--- Stop mission tracking thread
function StopMissionThread()
    if missionThread then
        missionThread = nil
    end
end

--- Calculate remaining delivery window time in milliseconds
---@return number milliseconds remaining
function CalculateWindowRemaining()
    if not ActiveLoad then return 0 end

    local serverNow = GetServerTime()
    local expiresAt = ActiveLoad.window_expires_at or 0

    if serverNow <= 0 or expiresAt <= 0 then return 0 end

    local remainingSecs = expiresAt - serverNow
    return math.max(remainingSecs * 1000, 0)
end

--- Calculate total delivery window duration in milliseconds
---@return number milliseconds total
function CalculateWindowTotal()
    if not ActiveLoad then return 1 end

    local acceptedAt = ActiveLoad.accepted_at or 0
    local expiresAt = ActiveLoad.window_expires_at or 0

    if acceptedAt <= 0 or expiresAt <= 0 then return 1 end

    return math.max((expiresAt - acceptedAt) * 1000, 1)
end

--- Get human-readable destination label
---@return string
function GetCurrentDestinationLabel()
    if not ActiveLoad or not ActiveBOL then return 'Unknown' end

    if ActiveLoad.is_multi_stop and ActiveLoad.stops then
        local stop = ActiveLoad.stops[ActiveLoad.current_stop or 1]
        if stop and stop.label then
            return stop.label
        end
    end

    return ActiveBOL.destination_label or 'Unknown'
end

--- Get distance remaining in miles (GTA map scale 1:3.5)
---@return number miles
function GetDistanceMiles()
    -- Convert GTA units (meters) to miles with 1:3.5 map scale
    return (distanceRemaining / 1609.34) * 3.5
end

-- ─────────────────────────────────────────────
-- MULTI-STOP PROGRESSION
-- ─────────────────────────────────────────────
--- Server notifies that a stop has been completed; advance to next stop.
RegisterNetEvent('trucking:client:stopCompleted', function(data)
    if not ActiveLoad or not data then return end

    ActiveLoad.current_stop = data.nextStop
    ActiveLoad.status = 'in_transit'

    -- Update GPS to next destination
    local nextDest = GetCurrentDestination()
    if nextDest then
        SetGPSWaypoint(nextDest)
    end

    -- Recreate delivery zone at next stop
    CreateDeliveryZone()

    lib.notify({
        title = 'Stop ' .. (data.completedStop or '?') .. '/' .. (ActiveLoad.stop_count or '?') .. ' Complete',
        description = 'Proceed to next destination: ' .. GetCurrentDestinationLabel(),
        type = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- TRANSFER MECHANIC
-- ─────────────────────────────────────────────
--- Initiate load transfer to nearby driver. Both drivers must be within 15m.
function InitiateTransfer()
    if not ActiveLoad then
        lib.notify({ title = 'No Active Load', type = 'error' })
        return
    end

    -- Cooldown check
    if GetGameTimer() < transferCooldown then
        lib.notify({ title = 'Transfer Cooldown', description = 'Please wait before trying again', type = 'error' })
        return
    end

    -- Find nearby players within 15m
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local nearbyPlayers = {}

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local targetPed = GetPlayerPed(playerId)
            local targetCoords = GetEntityCoords(targetPed)
            local dist = #(playerCoords - targetCoords)
            if dist <= 15.0 then
                table.insert(nearbyPlayers, {
                    id = GetPlayerServerId(playerId),
                    name = GetPlayerName(playerId),
                    distance = dist,
                })
            end
        end
    end

    if #nearbyPlayers == 0 then
        lib.notify({
            title = 'No Drivers Nearby',
            description = 'Another driver must be within 15 meters to transfer',
            type = 'error',
        })
        return
    end

    -- Build selection menu
    local options = {}
    for _, player in ipairs(nearbyPlayers) do
        table.insert(options, {
            title = player.name,
            description = string.format('%.1f meters away', player.distance),
            icon = 'fas fa-user',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'Transfer Load?',
                    content = 'Transfer BOL #' .. (ActiveBOL.bol_number or '?')
                        .. ' to **' .. player.name .. '**?\n\n'
                        .. 'Payout will be split based on distance driven.',
                    centered = true,
                    cancel = true,
                })
                if confirm == 'confirm' then
                    TriggerServerEvent('trucking:server:initiateTransfer', ActiveLoad.bol_id, player.id)
                    transferCooldown = GetGameTimer() + 10000
                end
            end,
        })
    end

    lib.registerContext({
        id = 'trucking_transfer',
        title = 'Transfer Load',
        options = options,
    })
    lib.showContext('trucking_transfer')
end

-- ─────────────────────────────────────────────
-- DISTRESS SIGNAL
-- ─────────────────────────────────────────────
--- Send distress signal if being robbed. Notifies server for police dispatch.
function SendDistressSignal()
    if not ActiveLoad then
        lib.notify({ title = 'No Active Load', type = 'error' })
        return
    end

    if ActiveLoad.status == 'distress_active' then
        lib.notify({ title = 'Distress Already Active', type = 'inform' })
        return
    end

    local confirm = lib.alertDialog({
        header = 'Send Distress Signal?',
        content = 'This will alert dispatch that you are being robbed.\n\n'
            .. 'Only use this if you are in genuine danger.\n'
            .. 'False distress signals may result in reputation penalties.',
        centered = true,
        cancel = true,
    })

    if confirm == 'confirm' then
        local playerCoords = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('trucking:server:distressSignal', ActiveLoad.bol_id, {
            x = playerCoords.x,
            y = playerCoords.y,
            z = playerCoords.z,
        })

        lib.notify({
            title = 'Distress Signal Sent',
            description = 'Dispatch has been notified of your situation',
            type = 'inform',
            duration = 5000,
        })
    end
end

--- Server confirms distress signal activation
RegisterNetEvent('trucking:client:distressActive', function(data)
    if not ActiveLoad then return end
    ActiveLoad.status = 'distress_active'

    lib.notify({
        title = 'Distress Active',
        description = 'Help is on the way. Stay safe.',
        type = 'inform',
        duration = 8000,
    })
end)

--- Server confirms departure (BOL signed, status now in_transit)
RegisterNetEvent('trucking:client:departed', function(data)
    if not ActiveLoad then return end
    ActiveLoad.status = 'in_transit'
    if data and data.departed_at then
        ActiveLoad.departed_at = data.departed_at
    end
    lib.notify({
        title = 'Departed',
        description = 'Load is now in transit. Proceed to destination.',
        type = 'success',
    })
end)

--- Server confirms load was accepted from the board
RegisterNetEvent('trucking:client:loadAccepted', function(data)
    if not data then return end
    lib.notify({
        title = 'Load Accepted',
        description = 'BOL #' .. (data.bolNumber or '?') .. ' confirmed.',
        type = 'success',
    })
end)

--- Server confirms load was abandoned
RegisterNetEvent('trucking:client:loadAbandoned', function(data)
    lib.notify({
        title = 'Load Abandoned',
        description = data and data.reason or 'Load has been abandoned.',
        type = 'error',
        duration = 6000,
    })
    CleanupState()
end)

--- Server confirms load was delivered
RegisterNetEvent('trucking:client:loadDelivered', function(data)
    if not data then return end
    lib.notify({
        title = 'Load Delivered',
        description = 'BOL #' .. (data.bolNumber or '?') .. ' — Payout: $' .. (data.payout or 0),
        type = 'success',
        duration = 8000,
    })
end)

--- Server confirms load was rejected at destination
RegisterNetEvent('trucking:client:loadRejected', function(data)
    lib.notify({
        title = 'Load Rejected',
        description = data and data.reason or 'Load was rejected by the receiver.',
        type = 'error',
        duration = 8000,
    })
end)

--- Server confirms load was reserved from the board
RegisterNetEvent('trucking:client:loadReserved', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'loadReserved',
        data = data,
    })
    lib.notify({
        title = 'Load Reserved',
        description = 'BOL #' .. (data.bolNumber or '?') .. ' reserved for '
            .. (data.reservationMinutes or 5) .. ' minutes.',
        type = 'success',
    })
end)

--- Server sends load detail response (board preview)
RegisterNetEvent('trucking:client:loadDetailResponse', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'loadDetailResponse',
        data = data,
    })
end)

--- Server cancels a reservation (timeout or server-side cancel)
RegisterNetEvent('trucking:client:reservationCancelled', function(data)
    SendNUIMessage({
        action = 'reservationCancelled',
        data = data,
    })
    lib.notify({
        title = 'Reservation Cancelled',
        description = data and data.reason or 'Your reservation has expired.',
        type = 'inform',
    })
end)

--- Nearby driver distress alert (broadcast to other players)
RegisterNetEvent('trucking:client:distressAlert', function(data)
    if not data then return end
    lib.notify({
        title = 'Distress Signal',
        description = 'A driver is in distress at ' .. (data.location or 'unknown location'),
        type = 'error',
        duration = 10000,
    })
    if data.coords then
        SetNewWaypoint(data.coords.x or data.coords[1], data.coords.y or data.coords[2])
    end
end)

-- ─────────────────────────────────────────────
-- MONITORING START/STOP EVENTS
-- ─────────────────────────────────────────────
--- Start all monitoring systems (called after BOL signed and departure)
RegisterNetEvent('trucking:client:startMonitoring', function()
    if not ActiveLoad then return end

    -- Start seal monitoring if load has seal
    if ActiveLoad.seal_status == 'sealed' then
        TriggerEvent('trucking:client:startSealMonitoring')
    end

    -- Start vehicle health monitoring
    TriggerEvent('trucking:client:startVehicleMonitoring')

    -- Show HUD
    TriggerEvent('trucking:client:showHUD')

    -- Start mission thread
    StartMissionThread()
end)

--- Stop all monitoring systems
RegisterNetEvent('trucking:client:stopAllMonitoring', function()
    StopMissionThread()
    TriggerEvent('trucking:client:stopSealMonitoring')
    TriggerEvent('trucking:client:stopVehicleMonitoring')
end)

-- ─────────────────────────────────────────────
-- KEYBINDS FOR MISSION ACTIONS
-- ─────────────────────────────────────────────
--- Transfer load keybind
RegisterCommand('trucking_transfer', function()
    if not IsPlayerLoggedIn() or not ActiveLoad then return end
    InitiateTransfer()
end, false)

--- Distress signal keybind
RegisterCommand('trucking_distress', function()
    if not IsPlayerLoggedIn() or not ActiveLoad then return end
    SendDistressSignal()
end, false)

-- ─────────────────────────────────────────────
-- CLEANUP ON RESOURCE STOP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopMissionThread()
    RemoveDeliveryZone()
    ClearGPSWaypoint()
    DeleteWaypoint()
end)
