--[[
    client/livestock.lua — Livestock Welfare Event Detection
    Free Trucking — QBX Framework

    Responsibilities:
    - Display welfare rating (1-5 stars) on HUD
    - Detect driving events that affect livestock welfare:
        * Hard braking (rapid deceleration)
        * Sharp cornering > 35mph
        * Major collision (GetEntityHealth delta)
        * Off-road driving (not on road surface)
        * Heat exposure (Sandy Shores + vehicle stationary)
    - Report each event to server for authoritative welfare tracking
    - Rest stop interactions at designated truck stop zones
    - Provide Start/Stop lifecycle management

    Authority model:
    - Client detects events and reports to server
    - Server tracks welfare rating, applies changes, validates
    - No payout or reputation logic runs here
]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local livestockMonitoringActive = false

--- Cached welfare rating for HUD display (server-authoritative, display only)
local displayWelfareRating = 5

--- Previous frame values for delta detection
local prevSpeed = 0.0
local prevHeading = 0.0
local prevHealth = 0
local prevOnRoad = true

--- Off-road tracking (accumulate time for per-minute reporting)
local offRoadStartTimer = 0
local offRoadActive = false

--- Heat exposure tracking (Sandy Shores + stationary)
local heatExposureStartTimer = 0
local heatExposureActive = false

--- Smooth driving recovery timer
local lastEventTimer = 0

--- Cooldowns: prevent rapid-fire duplicate events (ms)
local eventCooldowns = {
    hard_braking = 0,
    sharp_corner = 0,
    collision = 0,
    off_road = 0,
    heat_exposure = 0,
}
local COOLDOWN_HARD_BRAKE_MS = 5000
local COOLDOWN_SHARP_CORNER_MS = 3000
local COOLDOWN_COLLISION_MS = 5000
local COOLDOWN_OFFROAD_MS = 60000      -- report once per minute off-road
local COOLDOWN_HEAT_MS = 600000        -- report once per 10 minutes heat

--- Conversion: m/s to mph
local MS_TO_MPH = 2.23694

--- Sharp cornering speed threshold (mph)
local SHARP_CORNER_SPEED_THRESHOLD = 35.0

--- Hard braking deceleration threshold (m/s^2 approximation via speed delta per tick)
--- At 2 ticks/sec, a delta of ~5 m/s corresponds to ~2.5g decel
local HARD_BRAKE_SPEED_DELTA = 5.0

--- Collision health delta threshold (entity health units)
local COLLISION_HEALTH_DELTA = 50

--- Heading change threshold for sharp cornering (degrees per tick at 500ms)
local SHARP_HEADING_DELTA = 15.0

-- ─────────────────────────────────────────────
-- TRUCK STOP REST STOP ZONES
-- ─────────────────────────────────────────────
--- Designated truck stop locations where rest stops are available.
--- These correspond to major truck stops on the map.
local TruckStopZones = {
    { label = 'Harmony Truck Stop',        coords = vector3(1199.23, 2648.30, 37.78),  radius = 30.0 },
    { label = 'Sandy Shores Depot',        coords = vector3(1394.57, 3614.89, 34.98),  radius = 30.0 },
    { label = 'Paleto Bay Truck Stop',     coords = vector3(160.47, 6397.39, 31.42),   radius = 30.0 },
    { label = 'Grapeseed Rest Area',       coords = vector3(1693.47, 4924.77, 42.07),  radius = 30.0 },
    { label = 'Cypress Flats Truck Yard',  coords = vector3(790.96, -2160.0, 29.62),   radius = 30.0 },
    { label = 'Davis Industrial Stop',     coords = vector3(-18.0, -1660.26, 29.29),   radius = 30.0 },
}

local restStopZonesCreated = false
local restStopZoneHandles = {}
local inRestStopZone = false
local restStopTextUIShowing = false

-- ─────────────────────────────────────────────
-- DETECTION HELPERS
-- ─────────────────────────────────────────────

--- Check if the vehicle is on a road surface.
--- Uses GetStreetNameAtCoord — if both street names are 0/"", the
--- vehicle is off any named road (desert, dirt, wilderness).
---@param coords vector3 Vehicle world coordinates
---@return boolean onRoad True if on a named road
local function IsOnRoad(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    -- If both hashes are 0 or the street resolves to empty, we're off-road
    if streetHash == 0 and crossingHash == 0 then
        return false
    end
    local streetName = GetStreetNameFromHashKey(streetHash)
    if not streetName or streetName == '' then
        return false
    end
    return true
end

--- Check if the player is in the Sandy Shores region (heat exposure zone).
---@param coords vector3 Player/vehicle coordinates
---@return boolean inSandyShores
local function IsInSandyShores(coords)
    -- Sandy Shores rough bounding box: Y between 3000 and 4000, X between 1000 and 2500
    return coords.y > 3000.0 and coords.y < 4200.0
        and coords.x > 1000.0 and coords.x < 2800.0
end

--- Check if the vehicle is effectively stationary.
---@param speed number Current speed in m/s
---@return boolean stationary
local function IsStationary(speed)
    return speed < 0.5 -- under ~1 mph
end

--- Check if a cooldown has elapsed.
---@param eventType string The event cooldown key
---@param cooldownMs number The cooldown duration in ms
---@return boolean available True if the event can fire
local function CheckCooldown(eventType, cooldownMs)
    local now = GetGameTimer()
    if (now - (eventCooldowns[eventType] or 0)) >= cooldownMs then
        eventCooldowns[eventType] = now
        return true
    end
    return false
end

-- ─────────────────────────────────────────────
-- CORE MONITORING FUNCTION
-- ─────────────────────────────────────────────

--- Called every 500ms while livestock monitoring is active.
--- Detects driving events and reports them to server.
---@param activeLoad table The active load data
local function UpdateLivestockState(activeLoad)
    if not activeLoad then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return end

    local bolId = activeLoad.bol_id
    local speed = GetEntitySpeed(vehicle) -- m/s
    local speedMph = speed * MS_TO_MPH
    local heading = GetEntityHeading(vehicle)
    local health = GetEntityHealth(vehicle)
    local coords = GetEntityCoords(vehicle)
    local now = GetGameTimer()

    -- ── Hard Braking Detection ──
    -- Compare current speed to previous frame. A large negative delta
    -- indicates rapid deceleration.
    local speedDelta = prevSpeed - speed
    if speedDelta > HARD_BRAKE_SPEED_DELTA and prevSpeed > 3.0 then
        if CheckCooldown('hard_braking', COOLDOWN_HARD_BRAKE_MS) then
            TriggerServerEvent('trucking:server:welfareEvent', bolId, 'hard_braking')
            lib.notify({
                title = 'Livestock Welfare',
                description = 'Hard braking detected! Animals are stressed.',
                type = 'warning',
                duration = 4000,
            })
        end
    end

    -- ── Sharp Cornering Detection ──
    -- Check heading change at speed. Large heading delta while moving fast
    -- indicates a sharp turn.
    if speedMph > SHARP_CORNER_SPEED_THRESHOLD then
        local headingDelta = math.abs(heading - prevHeading)
        -- Normalize for the 360->0 wrap
        if headingDelta > 180.0 then
            headingDelta = 360.0 - headingDelta
        end
        if headingDelta > SHARP_HEADING_DELTA then
            if CheckCooldown('sharp_corner', COOLDOWN_SHARP_CORNER_MS) then
                TriggerServerEvent('trucking:server:welfareEvent', bolId, 'sharp_corner')
                lib.notify({
                    title = 'Livestock Welfare',
                    description = 'Sharp turn at speed! Take corners gently.',
                    type = 'warning',
                    duration = 4000,
                })
            end
        end
    end

    -- ── Major Collision Detection ──
    -- Large health drops between ticks indicate a collision event.
    if prevHealth > 0 then
        local healthDelta = prevHealth - health
        if healthDelta > COLLISION_HEALTH_DELTA then
            if CheckCooldown('collision', COOLDOWN_COLLISION_MS) then
                TriggerServerEvent('trucking:server:welfareEvent', bolId, 'collision')
                lib.notify({
                    title = 'Livestock Welfare',
                    description = 'Major collision! Animals injured.',
                    type = 'error',
                    duration = 5000,
                })
            end
        end
    end

    -- ── Off-Road Detection ──
    -- Accumulate off-road time; report once per minute while off-road.
    local onRoad = IsOnRoad(coords)
    if not onRoad and speed > 1.0 then
        if not offRoadActive then
            offRoadActive = true
            offRoadStartTimer = now
        else
            local offRoadMs = now - offRoadStartTimer
            if offRoadMs >= 60000 then
                if CheckCooldown('off_road', COOLDOWN_OFFROAD_MS) then
                    TriggerServerEvent('trucking:server:welfareEvent', bolId, 'off_road')
                    lib.notify({
                        title = 'Livestock Welfare',
                        description = 'Off-road driving is distressing the animals.',
                        type = 'warning',
                        duration = 4000,
                    })
                end
                offRoadStartTimer = now -- reset for next minute
            end
        end
    else
        offRoadActive = false
        offRoadStartTimer = 0
    end

    -- ── Heat Exposure Detection ──
    -- Sandy Shores + vehicle stationary for extended period.
    if IsInSandyShores(coords) and IsStationary(speed) then
        if not heatExposureActive then
            heatExposureActive = true
            heatExposureStartTimer = now
        else
            local heatMs = now - heatExposureStartTimer
            if heatMs >= 600000 then -- 10 minutes
                if CheckCooldown('heat_exposure', COOLDOWN_HEAT_MS) then
                    TriggerServerEvent('trucking:server:welfareEvent', bolId, 'heat_exposure')
                    lib.notify({
                        title = 'Livestock Welfare',
                        description = 'Heat exposure! Move the animals to a cooler area.',
                        type = 'error',
                        duration = 6000,
                    })
                end
                heatExposureStartTimer = now -- reset for next interval
            end
        end
    else
        heatExposureActive = false
        heatExposureStartTimer = 0
    end

    -- ── Update previous frame values ──
    prevSpeed = speed
    prevHeading = heading
    prevHealth = health
end

-- ─────────────────────────────────────────────
-- REST STOP INTERACTIONS
-- ─────────────────────────────────────────────

--- Perform a rest stop interaction of the specified type.
--- Uses lib.progressBar with cancellation support.
---@param restType string One of: 'quick', 'water', 'full'
local function DoRestStop(restType)
    if not ActiveLoad then return end

    local durations = Config.RestStopDurations or { quick = 30000, water = 120000, full = 300000 }
    local labels = {
        quick = 'Quick rest stop — checking on animals',
        water = 'Water and rest stop — watering livestock',
        full  = 'Full rest stop — feed, water, and rest',
    }
    local welfareGains = {
        quick = '+0.5',
        water = '+1.0',
        full  = '+1.5',
    }

    local duration = durations[restType]
    local label = labels[restType]
    if not duration or not label then return end

    local success = lib.progressBar({
        duration = duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'creatures@rottweiler@tricks@',
            clip = 'petting_franklin',
            flag = 49,
        },
    })

    if success then
        local serverEvent = 'trucking:server:livestockRestStop'
        TriggerServerEvent(serverEvent, ActiveLoad.bol_id, restType)
        lib.notify({
            title = 'Rest Stop Complete',
            description = 'Welfare ' .. (welfareGains[restType] or '') .. ' — animals rested.',
            type = 'success',
            duration = 5000,
        })
    else
        lib.notify({
            title = 'Rest Stop Cancelled',
            description = 'Rest stop interaction was interrupted.',
            type = 'inform',
        })
    end
end

--- Show the rest stop type selection menu.
local function ShowRestStopMenu()
    if not ActiveLoad then return end

    local restOptions = lib.inputDialog('Livestock Rest Stop', {
        {
            type = 'select',
            label = 'Rest Type',
            description = 'Choose a rest stop option for your livestock',
            required = true,
            options = {
                { value = 'quick', label = 'Quick Stop (30 sec) — +0.5 welfare' },
                { value = 'water', label = 'Water Stop (2 min) — +1.0 welfare' },
                { value = 'full',  label = 'Full Rest (5 min) — +1.5 welfare' },
            },
        },
    })

    if restOptions and restOptions[1] then
        DoRestStop(restOptions[1])
    end
end

-- ─────────────────────────────────────────────
-- REST STOP ZONE MANAGEMENT
-- ─────────────────────────────────────────────

--- Create lib.zones for all truck stop rest areas.
local function CreateRestStopZones()
    if restStopZonesCreated then return end
    restStopZonesCreated = true

    for i, stop in ipairs(TruckStopZones) do
        local zone = lib.zones.sphere({
            coords = stop.coords,
            radius = stop.radius,
            debug = false,
            onEnter = function()
                if not livestockMonitoringActive then return end
                if not ActiveLoad then return end
                inRestStopZone = true
                if not restStopTextUIShowing then
                    restStopTextUIShowing = true
                    lib.showTextUI('[E] Livestock Rest Stop — ' .. stop.label, {
                        position = 'right-center',
                        icon = 'paw',
                    })
                end
            end,
            inside = function()
                if livestockMonitoringActive and inRestStopZone then
                    if IsControlJustReleased(0, 38) then -- E key
                        ShowRestStopMenu()
                    end
                end
            end,
            onExit = function()
                inRestStopZone = false
                if restStopTextUIShowing then
                    restStopTextUIShowing = false
                    lib.hideTextUI()
                end
            end,
        })
        restStopZoneHandles[#restStopZoneHandles + 1] = zone
    end
end

--- Remove all rest stop zones.
local function RemoveRestStopZones()
    for _, zone in ipairs(restStopZoneHandles) do
        if zone and zone.remove then
            zone:remove()
        end
    end
    restStopZoneHandles = {}
    restStopZonesCreated = false
    inRestStopZone = false
    if restStopTextUIShowing then
        restStopTextUIShowing = false
        lib.hideTextUI()
    end
end

-- Keybind handling moved to zone `inside` callback above for better performance.

-- ─────────────────────────────────────────────
-- HUD UPDATE
-- ─────────────────────────────────────────────

--- Update the welfare rating display on the HUD.
---@param rating number Welfare rating 1-5
local function UpdateWelfareHUD(rating)
    displayWelfareRating = rating

    SendNUIMessage({
        action = 'welfareStatus',
        data = {
            rating = rating,
            stars = rating, -- 1-5 star display
            monitoring = livestockMonitoringActive,
        },
    })
end

-- ─────────────────────────────────────────────
-- LIFECYCLE MANAGEMENT
-- ─────────────────────────────────────────────

--- Start livestock welfare monitoring for the current active load.
--- Creates detection threads and rest stop zones.
---@param activeLoad table The active load data from server
function StartLivestockMonitoring(activeLoad)
    if livestockMonitoringActive then return end
    if not activeLoad then return end

    -- Only monitor livestock cargo
    if activeLoad.cargo_type ~= 'livestock' then return end

    livestockMonitoringActive = true
    displayWelfareRating = Config.WelfareInitialRating or 5

    -- Reset detection state
    prevSpeed = 0.0
    prevHeading = 0.0
    prevHealth = 0
    offRoadActive = false
    offRoadStartTimer = 0
    heatExposureActive = false
    heatExposureStartTimer = 0
    lastEventTimer = GetGameTimer()

    -- Reset cooldowns
    for key in pairs(eventCooldowns) do
        eventCooldowns[key] = 0
    end

    -- Create rest stop zones
    CreateRestStopZones()

    -- Initial HUD
    UpdateWelfareHUD(displayWelfareRating)

    lib.notify({
        title = 'Livestock Welfare',
        description = 'Welfare monitoring active — drive carefully.',
        type = 'inform',
    })

    -- Initialize previous health
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle and vehicle ~= 0 then
        prevHealth = GetEntityHealth(vehicle)
        prevSpeed = GetEntitySpeed(vehicle)
        prevHeading = GetEntityHeading(vehicle)
    end

    -- Main detection thread: runs every 500ms
    CreateThread(function()
        while livestockMonitoringActive do
            if not ActiveLoad then
                StopLivestockMonitoring()
                return
            end
            UpdateLivestockState(ActiveLoad)
            Wait(500)
        end
    end)
end

--- Stop livestock welfare monitoring and clean up all state.
function StopLivestockMonitoring()
    if not livestockMonitoringActive then return end

    livestockMonitoringActive = false

    -- Remove rest stop zones
    RemoveRestStopZones()

    -- Clear HUD
    SendNUIMessage({
        action = 'welfareStatus',
        data = {
            monitoring = false,
            rating = 0,
            stars = 0,
        },
    })

    -- Reset detection state
    prevSpeed = 0.0
    prevHeading = 0.0
    prevHealth = 0
    offRoadActive = false
    heatExposureActive = false
end

--- Check if livestock monitoring is currently active.
---@return boolean active
function IsLivestockMonitoringActive()
    return livestockMonitoringActive
end

-- ─────────────────────────────────────────────
-- EVENT LISTENERS
-- ─────────────────────────────────────────────

--- Server pushes updated welfare rating to client for HUD display.
RegisterNetEvent('trucking:client:welfareUpdate', function(data)
    if not data then return end
    if data.rating then
        UpdateWelfareHUD(data.rating)
    end

    -- Notify on significant welfare drops
    if data.rating and data.rating <= 2 then
        lib.notify({
            title = 'Welfare Critical',
            description = 'Livestock welfare is critically low! Find a rest stop.',
            type = 'error',
            duration = 8000,
        })
    end
end)

--- Resume livestock monitoring after reconnect.
AddEventHandler('trucking:client:resumeMonitoring', function()
    if ActiveLoad and ActiveLoad.cargo_type == 'livestock' then
        StartLivestockMonitoring(ActiveLoad)
    end
end)

--- Stop all monitoring on state cleanup.
AddEventHandler('trucking:client:stopAllMonitoring', function()
    StopLivestockMonitoring()
end)

-- ─────────────────────────────────────────────
-- RESOURCE CLEANUP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopLivestockMonitoring()
end)
