--[[
    client/weighstation.lua — Weigh Station Zones and Interactions
    Free Trucking — QBX Framework

    Responsibilities:
    - 3 weigh station locations via lib.zones.box
    - On zone enter with active load: textUI prompt "[E] Pull onto scale"
    - NPC inspection sequence (8-second lib.progressBar)
    - Report stamp to server: trucking:server:weighStationStamp
    - Additional dialogue for HAZMAT (placard check) and cold chain (temp check)
    - Optional for T0-T1, GPS auto-routes through them for T2-T3
    - Provide Start/Stop lifecycle management

    Authority model:
    - Client manages zone interactions and UI prompts
    - Server validates stamp, updates active load and BOL records
    - Compliance bonus (+5%) tracked server-side only
]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local weighStationActive = false
local stationZoneHandles = {}
local stationZonesCreated = false
local inStationZone = false
local currentStationId = nil
local currentStationLabel = nil
local textUIShowing = false
local inspectionInProgress = false

--- Station stamps already received this load (prevent double-stamp)
local stationsStamped = {}

-- ─────────────────────────────────────────────
-- STATION DEFINITIONS
-- ─────────────────────────────────────────────
--- Weigh station locations from Config, with zone sizing and IDs.
--- Each station has a scale pad zone (lib.zones.box) where the
--- truck must stop for inspection.
local WeighStations = {
    {
        id = 'pacific_bluffs',
        label = 'Route 1 Pacific Bluffs',
        coords = vector3(-1640.0, -833.0, 10.0),
        size = vec3(12.0, 6.0, 4.0),
        heading = 320.0,
    },
    {
        id = 'harmony',
        label = 'Route 68 near Harmony',
        coords = vector3(542.0, 2670.0, 42.0),
        size = vec3(12.0, 6.0, 4.0),
        heading = 45.0,
    },
    {
        id = 'paleto_bay',
        label = 'Paleto Bay Highway Entrance',
        coords = vector3(-354.0, 6170.0, 31.0),
        size = vec3(12.0, 6.0, 4.0),
        heading = 315.0,
    },
}

-- Override from Config if available
if Config.WeighStationLocations then
    for i, cfgStation in ipairs(Config.WeighStationLocations) do
        if WeighStations[i] then
            WeighStations[i].coords = cfgStation.coords
            WeighStations[i].label = cfgStation.label
        end
    end
end

-- ─────────────────────────────────────────────
-- INSPECTION INTERACTIONS
-- ─────────────────────────────────────────────

--- Check if the current load requires HAZMAT placard verification.
---@param activeLoad table The active load data
---@return boolean isHazmat
local function IsHazmatLoad(activeLoad)
    if not activeLoad then return false end
    return activeLoad.hazmat_class ~= nil
        or activeLoad.cargo_type == 'hazmat'
        or activeLoad.cargo_type == 'hazmat_class7'
end

--- Check if the current load requires cold chain temperature verification.
---@param activeLoad table The active load data
---@return boolean isColdChain
local function IsColdChainLoad(activeLoad)
    if not activeLoad then return false end
    return activeLoad.temp_required
        or activeLoad.temp_monitoring_active
        or activeLoad.cargo_type == 'cold_chain'
        or activeLoad.cargo_type == 'pharmaceutical'
        or activeLoad.cargo_type == 'pharmaceutical_biologic'
end

--- Perform the HAZMAT placard check dialogue.
--- This is an additional inspection step for hazmat cargo.
---@param activeLoad table The active load data
---@return boolean passed
local function DoHazmatPlacardCheck(activeLoad)
    local placardClass = activeLoad.hazmat_class or 'N/A'
    local unNumber = activeLoad.hazmat_un_number or 'N/A'

    local result = lib.alertDialog({
        header = locale('weighstation.hazmat_placard_header'),
        content = locale('weighstation.hazmat_placard_content'):format(tostring(placardClass), tostring(unNumber)),
        centered = true,
        cancel = false,
    })

    -- Placard check progress bar
    local success = lib.progressBar({
        duration = 4000,
        label = locale('weighstation.hazmat_verifying_label'),
        useWhileDead = false,
        canCancel = false,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
    })

    lib.notify({
        title = locale('weighstation.hazmat_check_title'),
        description = locale('weighstation.hazmat_check_verified'),
        type = 'success',
        duration = 4000,
    })

    return true
end

--- Perform the cold chain temperature compliance check dialogue.
---@param activeLoad table The active load data
---@return boolean passed
local function DoColdChainTempCheck(activeLoad)
    local tempMin = activeLoad.temp_min_f or '?'
    local tempMax = activeLoad.temp_max_f or '?'
    local currentTemp = activeLoad.current_temp_f or 'Reading...'

    local result = lib.alertDialog({
        header = locale('weighstation.temp_compliance_header'),
        content = locale('weighstation.temp_compliance_content'):format(tostring(tempMin), tostring(tempMax), tostring(currentTemp)),
        centered = true,
        cancel = false,
    })

    -- Temp check progress bar
    local success = lib.progressBar({
        duration = 3000,
        label = locale('weighstation.temp_checking_label'),
        useWhileDead = false,
        canCancel = false,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
    })

    lib.notify({
        title = locale('weighstation.temp_check_title'),
        description = locale('weighstation.temp_check_verified'),
        type = 'success',
        duration = 4000,
    })

    return true
end

--- Run the full weigh station inspection sequence.
---@param stationId string Station identifier
---@param stationLabel string Station display name
local function RunInspection(stationId, stationLabel)
    if inspectionInProgress then return end
    if not ActiveLoad then return end
    if stationsStamped[stationId] then
        lib.notify({
            title = locale('weighstation.title'),
            description = locale('weighstation.already_stamped_at'):format(stationLabel),
            type = 'inform',
        })
        return
    end

    inspectionInProgress = true

    -- Hide the textUI while inspecting
    if textUIShowing then
        lib.hideTextUI()
        textUIShowing = false
    end

    lib.notify({
        title = locale('weighstation.title'),
        description = locale('weighstation.pulling_onto_scale'):format(stationLabel),
        type = 'inform',
    })

    -- Main DOT inspection progress bar (8 seconds)
    local success = lib.progressBar({
        duration = 8000,
        label = locale('weighstation.dot_reviewing'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'mp_common',
            clip = 'givetake1_a',
            flag = 49,
        },
    })

    if not success then
        lib.notify({
            title = locale('weighstation.inspection_cancelled_title'),
            description = locale('weighstation.left_inspection_area'),
            type = 'warning',
        })
        inspectionInProgress = false
        return
    end

    -- Additional checks for special cargo types
    if IsHazmatLoad(ActiveLoad) then
        DoHazmatPlacardCheck(ActiveLoad)
    end

    if IsColdChainLoad(ActiveLoad) then
        DoColdChainTempCheck(ActiveLoad)
    end

    -- Report stamp to server
    TriggerServerEvent('trucking:server:weighStationStamp', ActiveLoad.bol_id, stationId)

    -- Mark this station as stamped locally
    stationsStamped[stationId] = true

    lib.notify({
        title = locale('weighstation.stamp_issued_title'),
        description = locale('weighstation.stamp_issued_desc'),
        type = 'success',
        duration = 6000,
    })

    PlaySoundFrontend(-1, 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', true)

    inspectionInProgress = false
end

-- ─────────────────────────────────────────────
-- ZONE MANAGEMENT
-- ─────────────────────────────────────────────

--- Create lib.zones.box for each weigh station scale pad.
local function CreateStationZones()
    if stationZonesCreated then return end
    stationZonesCreated = true

    for _, station in ipairs(WeighStations) do
        local zone = lib.zones.box({
            coords = station.coords,
            size = station.size,
            rotation = station.heading,
            debug = false,
            onEnter = function()
                if not weighStationActive then return end
                if not ActiveLoad then return end
                if inspectionInProgress then return end

                inStationZone = true
                currentStationId = station.id
                currentStationLabel = station.label

                if stationsStamped[station.id] then
                    lib.showTextUI(locale('weighstation.already_stamped_label'):format(station.label), {
                        position = 'right-center',
                        icon = 'check',
                    })
                    textUIShowing = true
                else
                    lib.showTextUI(locale('weighstation.pull_onto_scale_prompt'):format(station.label), {
                        position = 'right-center',
                        icon = 'weight-hanging',
                    })
                    textUIShowing = true
                end
            end,
            inside = function()
                if weighStationActive and inStationZone and not inspectionInProgress then
                    if IsControlJustReleased(0, 38) then -- E key
                        if currentStationId then
                            RunInspection(currentStationId, currentStationLabel or 'Unknown')
                        end
                    end
                end
            end,
            onExit = function()
                inStationZone = false
                currentStationId = nil
                currentStationLabel = nil
                if textUIShowing then
                    lib.hideTextUI()
                    textUIShowing = false
                end
            end,
        })
        stationZoneHandles[#stationZoneHandles + 1] = zone
    end
end

--- Remove all weigh station zones.
local function RemoveStationZones()
    for _, zone in ipairs(stationZoneHandles) do
        if zone and zone.remove then
            zone:remove()
        end
    end
    stationZoneHandles = {}
    stationZonesCreated = false
    inStationZone = false
    currentStationId = nil
    currentStationLabel = nil
    if textUIShowing then
        lib.hideTextUI()
        textUIShowing = false
    end
end

-- Keybind handling moved to zone `inside` callback above for better performance.

-- ─────────────────────────────────────────────
-- GPS ROUTING (T2-T3 auto-route through stations)
-- ─────────────────────────────────────────────

--- Set GPS waypoint to the nearest weigh station on the route.
--- Called for T2-T3 loads that require mandatory weigh station routing.
---@param destCoords vector3 Final destination coordinates
function RouteToNearestWeighStation(destCoords)
    if not ActiveLoad then return end

    local tier = ActiveLoad.tier or 0
    local optionalMaxTier = Config.WeighStationOptionalMaxTier or 1

    -- Only auto-route for tiers above the optional threshold
    if tier <= optionalMaxTier then return end

    -- Already stamped at any station?
    if ActiveLoad.weigh_station_stamped then return end

    -- Find nearest station between current position and destination
    local playerCoords = GetEntityCoords(PlayerPedId())
    local nearestDist = math.huge
    local nearestStation = nil

    for _, station in ipairs(WeighStations) do
        if not stationsStamped[station.id] then
            local distToStation = #(playerCoords - station.coords)
            if distToStation < nearestDist then
                nearestDist = distToStation
                nearestStation = station
            end
        end
    end

    if nearestStation then
        SetNewWaypoint(nearestStation.coords.x, nearestStation.coords.y)
        lib.notify({
            title = locale('weighstation.required_title'),
            description = locale('weighstation.gps_set_mandatory'):format(nearestStation.label, tier),
            type = 'inform',
            duration = 6000,
        })
    end
end

-- ─────────────────────────────────────────────
-- LIFECYCLE MANAGEMENT
-- ─────────────────────────────────────────────

--- Start weigh station monitoring. Creates station zones and
--- enables player interaction with scale pads.
---@param activeLoad table The active load data from server
function StartWeighStationMonitoring(activeLoad)
    if weighStationActive then return end
    if not activeLoad then return end

    weighStationActive = true
    stationsStamped = {}

    -- Restore any existing stamps from the active load
    if activeLoad.weigh_station_stamped then
        -- Server tracks which station, but client just needs the flag
        -- for repeated visits prevention
    end

    CreateStationZones()

    -- Auto-route for T2-T3
    local tier = activeLoad.tier or 0
    local optionalMaxTier = Config.WeighStationOptionalMaxTier or 1
    if tier > optionalMaxTier then
        -- Delayed GPS to nearest station (allow mission systems to initialize)
        SetTimeout(3000, function()
            if ActiveLoad and ActiveLoad.destination_coords then
                local destCoords = vector3(
                    ActiveLoad.destination_coords.x or 0,
                    ActiveLoad.destination_coords.y or 0,
                    ActiveLoad.destination_coords.z or 0
                )
                RouteToNearestWeighStation(destCoords)
            end
        end)
    end
end

--- Stop weigh station monitoring and clean up all state.
function StopWeighStationMonitoring()
    if not weighStationActive then return end

    weighStationActive = false
    inspectionInProgress = false
    stationsStamped = {}

    RemoveStationZones()
end

--- Check if weigh station monitoring is currently active.
---@return boolean active
function IsWeighStationMonitoringActive()
    return weighStationActive
end

-- ─────────────────────────────────────────────
-- EVENT LISTENERS
-- ─────────────────────────────────────────────

--- Server confirms weigh station stamp was applied.
RegisterNetEvent('trucking:client:weighStationConfirm', function(data)
    if not data then return end
    if data.stationId then
        stationsStamped[data.stationId] = true
    end
end)

--- Resume weigh station monitoring after reconnect.
AddEventHandler('trucking:client:resumeMonitoring', function()
    if ActiveLoad then
        StartWeighStationMonitoring(ActiveLoad)
    end
end)

--- Stop all monitoring on state cleanup.
AddEventHandler('trucking:client:stopAllMonitoring', function()
    StopWeighStationMonitoring()
end)

-- ─────────────────────────────────────────────
-- RESOURCE CLEANUP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopWeighStationMonitoring()
end)
