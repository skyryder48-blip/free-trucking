--[[
    client/vehicles.lua — Vehicle Detection and Monitoring
    Free Trucking — QBX Framework

    Responsibilities:
    - DetectVehicleClass(vehicle): check model against config/vehicles.lua mappings
    - IsOwnerOperator(vehicle): check plate against player's owned vehicles
    - MonitorVehicleHealth(vehicle): thread that checks entity health every 2 seconds
    - Cargo integrity event detection (collision, rollover, sharp cornering, off-road)
    - Integrity loss calculation per event (based on cargo integrity_profile)
    - Report integrity events to server
    - Vehicle rental detection
    - Trailer coupling detection
]]

-- ─────────────────────────────────────────────
-- LOCAL STATE
-- ─────────────────────────────────────────────
local vehicleMonitorThread = nil
local lastHealthBody = 0
local lastHealthEngine = 0
local lastSpeed = 0.0
local lastHeading = 0.0
local wasOnRoad = true
local wasRolledOver = false
local monitoredVehicle = nil
local integrityEventCooldown = 0

--- Integrity loss profiles: maps profile name to loss ranges per event type
--- These are client-side estimates. Server is authoritative on final values.
local IntegrityProfiles = {
    forgiving = {
        collision_minor    = { 1, 3 },
        collision_moderate = { 2, 5 },
        collision_major    = { 4, 8 },
        rollover           = { 5, 8 },
        sharp_cornering    = { 1, 2 },
        off_road           = { 0, 1 },
    },
    standard = {
        collision_minor    = { 2, 5 },
        collision_moderate = { 5, 10 },
        collision_major    = { 8, 15 },
        rollover           = { 10, 18 },
        sharp_cornering    = { 1, 3 },
        off_road           = { 1, 2 },
    },
    strict = {
        collision_minor    = { 3, 7 },
        collision_moderate = { 7, 14 },
        collision_major    = { 12, 22 },
        rollover           = { 15, 25 },
        sharp_cornering    = { 2, 5 },
        off_road           = { 2, 4 },
    },
    liquid = {
        collision_minor    = { 2, 5 },
        collision_moderate = { 5, 10 },
        collision_major    = { 10, 18 },
        rollover           = { 12, 22 },
        sharp_cornering    = { 3, 6 },    -- liquid slosh
        off_road           = { 1, 3 },
    },
}

-- ─────────────────────────────────────────────
-- VEHICLE CLASS DETECTION
-- ─────────────────────────────────────────────

--- Vehicle class mappings by model hash.
--- These map GTA vehicle models to trucking system vehicle types.
--- Full mappings should be defined in config/vehicles.lua; this provides defaults.
local DefaultVehicleClasses = {
    -- Tier 0 vehicles (no CDL required)
    [`speedo`]      = 'van',
    [`speedo2`]     = 'van',
    [`speedo4`]     = 'van',
    [`burrito`]     = 'van',
    [`burrito2`]    = 'van',
    [`burrito3`]    = 'van',
    [`rumpo`]       = 'van',
    [`rumpo2`]      = 'van',
    [`rumpo3`]      = 'van',
    [`surfer`]      = 'van',
    [`youga`]       = 'van',
    [`youga2`]      = 'van',
    [`minivan`]     = 'van',
    [`pony`]        = 'van',
    [`pony2`]       = 'van',
    [`boxville`]    = 'sprinter',
    [`boxville2`]   = 'sprinter',
    [`boxville3`]   = 'sprinter',
    [`boxville4`]   = 'sprinter',
    [`boxville5`]   = 'sprinter',
    [`taco`]        = 'sprinter',

    -- Pickups
    [`bison`]       = 'pickup',
    [`bison2`]      = 'pickup',
    [`bison3`]      = 'pickup',
    [`bobcatxl`]    = 'pickup',
    [`sadler`]      = 'pickup',
    [`sadler2`]     = 'pickup',

    -- Tier 1 vehicles (Class B CDL)
    [`benson`]      = 'box_truck',
    [`benson2`]     = 'box_truck',
    [`pounder`]     = 'box_truck',
    [`pounder2`]    = 'box_truck',
    [`mule`]        = 'box_truck',
    [`mule2`]       = 'box_truck',
    [`mule3`]       = 'box_truck',
    [`mule4`]       = 'box_truck',
    [`flatbed`]     = 'flatbed',
    [`tipper`]      = 'tipper',
    [`tipper2`]     = 'tipper',

    -- Tier 2+ vehicles (Class A CDL)
    [`packer`]      = 'class_a_cab',
    [`phantom`]     = 'class_a_cab',
    [`phantom2`]    = 'class_a_cab',
    [`phantom3`]    = 'class_a_cab',
    [`hauler`]      = 'class_a_cab',
    [`hauler2`]     = 'class_a_cab',

    -- Trailers
    [`trailers`]    = 'dry_van_trailer',
    [`trailers2`]   = 'dry_van_trailer',
    [`trailers3`]   = 'flatbed_trailer',
    [`trailers4`]   = 'tanker_trailer',
    [`tanker`]      = 'tanker_fuel',
    [`tanker2`]     = 'tanker_fuel',
    [`trailerlogs`] = 'flatbed_trailer',
    [`tr2`]         = 'dry_van_trailer',
    [`tr3`]         = 'flatbed_trailer',
    [`tr4`]         = 'tanker_trailer',
    [`trflat`]      = 'flatbed_trailer',
    [`armytrailer`] = 'military_trailer',
    [`armytrailer2`]= 'military_trailer',
    [`freighttrailer`] = 'freight_trailer',
}

--- Detect vehicle class from model hash.
--- Checks config/vehicles.lua mappings first, then falls back to defaults.
---@param vehicle number Vehicle entity handle
---@return string|nil vehicleClass
function DetectVehicleClass(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    if not DoesEntityExist(vehicle) then return nil end

    local model = GetEntityModel(vehicle)

    -- Check config mappings first (if VehicleClasses exists from config/vehicles.lua)
    if VehicleClasses and VehicleClasses[model] then
        return VehicleClasses[model]
    end

    -- Fall back to defaults
    if DefaultVehicleClasses[model] then
        return DefaultVehicleClasses[model]
    end

    -- Unknown vehicle — check GTA vehicle class as fallback
    local gtaClass = GetVehicleClass(vehicle)
    if gtaClass == 20 then return 'class_a_cab' end   -- Commercial
    if gtaClass == 11 then return 'van' end            -- Vans
    if gtaClass == 14 then return 'pickup' end         -- Utility (some pickups)

    return nil
end

--- Get the CDL requirement for a vehicle class
---@param vehicleClass string Vehicle class identifier
---@return string cdlRequired 'none', 'class_b', or 'class_a'
function GetCDLRequirement(vehicleClass)
    if not vehicleClass then return 'none' end

    local classACDL = {
        class_a_cab = true,
        class_a_reefer = true,
        tanker_fuel = true,
        tanker_trailer = true,
        livestock_trailer = true,
        lowboy_trailer = true,
        military_trailer = true,
    }

    local classBCDL = {
        box_truck = true,
        flatbed = true,
        tipper = true,
    }

    if classACDL[vehicleClass] then return 'class_a' end
    if classBCDL[vehicleClass] then return 'class_b' end
    return 'none'
end

-- ─────────────────────────────────────────────
-- OWNER-OPERATOR DETECTION
-- ─────────────────────────────────────────────

--- Check if the vehicle plate matches one of the player's owned vehicles.
--- Uses qbx_core vehicle ownership exports.
---@param vehicle number Vehicle entity handle
---@return boolean isOwner
function IsOwnerOperator(vehicle)
    if not vehicle or vehicle == 0 then return false end

    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate then return false end
    plate = plate:gsub('%s+', '')

    -- Check via qbx_core or your vehicle management resource
    local citizenid = GetCitizenId()
    if not citizenid then return false end

    -- Use server callback to verify ownership
    local isOwned = lib.callback.await('trucking:server:checkVehicleOwnership', false, plate, citizenid)
    return isOwned == true
end

-- ─────────────────────────────────────────────
-- VEHICLE RENTAL DETECTION
-- ─────────────────────────────────────────────

--- Check if current vehicle is a rental (not owned by player).
--- Returns true if vehicle is detected and not owned.
---@param vehicle number Vehicle entity handle
---@return boolean isRental
function IsRentalVehicle(vehicle)
    if not vehicle or vehicle == 0 then return false end
    return not IsOwnerOperator(vehicle)
end

-- ─────────────────────────────────────────────
-- TRAILER COUPLING DETECTION
-- ─────────────────────────────────────────────

--- Check if the player's vehicle has a trailer attached.
---@return number|nil trailerEntity
function GetAttachedTrailer()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then return nil end

    local hasTrailer, trailer = GetVehicleTrailerVehicle(vehicle)
    if hasTrailer and trailer and trailer ~= 0 then
        return trailer
    end

    return nil
end

--- Check if a trailer is currently coupled to a specific vehicle.
---@param vehicle number Vehicle entity handle
---@return boolean isCoupled
function IsTrailerCoupled(vehicle)
    if not vehicle or vehicle == 0 then return false end
    local hasTrailer, trailer = GetVehicleTrailerVehicle(vehicle)
    return hasTrailer and trailer and trailer ~= 0
end

-- ─────────────────────────────────────────────
-- VEHICLE HEALTH MONITORING
-- ─────────────────────────────────────────────

--- Start health monitoring thread for the current vehicle.
--- Checks entity health every 2 seconds, reports significant changes to server.
RegisterNetEvent('trucking:client:startVehicleMonitoring', function()
    StopVehicleMonitoring()

    if not ActiveLoad or not ActiveBOL then return end

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then return end

    monitoredVehicle = vehicle
    lastHealthBody = GetVehicleBodyHealth(vehicle)
    lastHealthEngine = GetVehicleEngineHealth(vehicle)
    lastSpeed = GetEntitySpeed(vehicle) * 2.236936  -- m/s to mph
    lastHeading = GetEntityHeading(vehicle)
    wasOnRoad = IsVehicleOnAllWheels(vehicle)
    wasRolledOver = IsEntityUpsidedown(vehicle)

    vehicleMonitorThread = CreateThread(function()
        while ActiveLoad and monitoredVehicle do
            local veh = monitoredVehicle
            if not DoesEntityExist(veh) then break end

            local currentHealthBody = GetVehicleBodyHealth(veh)
            local currentHealthEngine = GetVehicleEngineHealth(veh)
            local currentSpeed = GetEntitySpeed(veh) * 2.236936  -- mph
            local currentHeading = GetEntityHeading(veh)
            local playerCoords = GetEntityCoords(PlayerPedId())

            -- Collision detection: check for sudden health drops
            local bodyDrop = lastHealthBody - currentHealthBody
            local engineDrop = lastHealthEngine - currentHealthEngine
            local healthDrop = math.max(bodyDrop, engineDrop)

            if healthDrop > 0 and GetGameTimer() > integrityEventCooldown then
                local cause = nil
                if healthDrop >= 200 then
                    cause = 'collision_major'
                elseif healthDrop >= 80 then
                    cause = 'collision_moderate'
                elseif healthDrop >= 25 then
                    cause = 'collision_minor'
                end

                if cause then
                    ReportIntegrityEvent(cause, lastSpeed, playerCoords)
                end
            end

            -- Rollover detection
            local isRolledOver = IsEntityUpsidedown(veh)
            if isRolledOver and not wasRolledOver then
                ReportIntegrityEvent('rollover', currentSpeed, playerCoords)
            end
            wasRolledOver = isRolledOver

            -- Sharp cornering detection: heading change at speed
            local headingDelta = math.abs(currentHeading - lastHeading)
            if headingDelta > 180 then headingDelta = 360 - headingDelta end

            if currentSpeed > 35 and headingDelta > 15 then
                -- Sharp turn at speed
                if GetGameTimer() > integrityEventCooldown then
                    ReportIntegrityEvent('sharp_cornering', currentSpeed, playerCoords)
                end
            end

            -- Off-road detection
            local isOnRoad = IsVehicleOnAllWheels(veh) and not IsEntityInWater(veh)
            -- Use a road check: check if on paved surface
            local onRoad = IsPointOnRoad(playerCoords.x, playerCoords.y, playerCoords.z, veh)

            if not onRoad and wasOnRoad and currentSpeed > 10 then
                if GetGameTimer() > integrityEventCooldown then
                    ReportIntegrityEvent('off_road', currentSpeed, playerCoords)
                end
            end
            wasOnRoad = onRoad

            -- Update tracking vars
            lastHealthBody = currentHealthBody
            lastHealthEngine = currentHealthEngine
            lastSpeed = currentSpeed
            lastHeading = currentHeading

            Wait(2000)
        end
    end)
end)

--- Stop vehicle health monitoring
function StopVehicleMonitoring()
    monitoredVehicle = nil
    vehicleMonitorThread = nil
end

RegisterNetEvent('trucking:client:stopVehicleMonitoring', function()
    StopVehicleMonitoring()
end)

-- ─────────────────────────────────────────────
-- INTEGRITY EVENT REPORTING
-- ─────────────────────────────────────────────

--- Report an integrity event to the server.
--- Client calculates estimated loss; server is authoritative on final values.
---@param cause string Event cause identifier
---@param speed number Vehicle speed at time of event (mph)
---@param coords vector3 Player coordinates at time of event
function ReportIntegrityEvent(cause, speed, coords)
    if not ActiveLoad or not ActiveBOL then return end

    -- Apply cooldown to prevent event spam (3 seconds)
    integrityEventCooldown = GetGameTimer() + 3000

    -- Calculate estimated integrity loss based on cargo profile
    local profile = 'standard'
    if CargoTypes and ActiveBOL.cargo_type and CargoTypes[ActiveBOL.cargo_type] then
        profile = CargoTypes[ActiveBOL.cargo_type].integrity_profile or 'standard'
    end

    local lossRange = IntegrityProfiles[profile] and IntegrityProfiles[profile][cause]
    local estimatedLoss = 0
    if lossRange then
        estimatedLoss = math.random(lossRange[1], lossRange[2])
    end

    -- Report to server — server validates and applies authoritative loss
    TriggerServerEvent('trucking:server:integrityEvent',
        ActiveLoad.bol_id,
        cause,
        estimatedLoss,
        math.floor(speed),
        { x = coords.x, y = coords.y, z = coords.z }
    )

    -- Client-side notification
    local causeLabels = {
        collision_minor    = 'Minor Impact',
        collision_moderate = 'Moderate Collision',
        collision_major    = 'Major Collision',
        rollover           = 'Vehicle Rollover',
        sharp_cornering    = 'Sharp Cornering',
        off_road           = 'Off-Road Detected',
    }

    local severity = 'inform'
    if cause == 'collision_major' or cause == 'rollover' then
        severity = 'error'
    elseif cause == 'collision_moderate' then
        severity = 'warning'
    end

    lib.notify({
        title = 'Cargo Integrity',
        description = (causeLabels[cause] or cause) .. ' — estimated -' .. estimatedLoss .. '%',
        type = severity,
    })
end

--- Server confirms integrity update
RegisterNetEvent('trucking:client:integrityUpdated', function(data)
    if not ActiveLoad or not data then return end
    ActiveLoad.cargo_integrity = data.newIntegrity or ActiveLoad.cargo_integrity
end)

-- ─────────────────────────────────────────────
-- UTILITY FUNCTIONS
-- ─────────────────────────────────────────────

--- Check if a point is on a paved road surface.
---@param x number
---@param y number
---@param z number
---@param vehicle number Vehicle entity handle
---@return boolean
function IsPointOnRoad(x, y, z, vehicle)
    -- Use native to check if vehicle is on a road node
    local result, _ = GetClosestRoad(x, y, z, 1, 0, false)

    -- Also check using GetNthClosestVehicleNode
    local roadFound, roadPos = GetNthClosestVehicleNode(x, y, z, 1, 0, 0, 0)
    if roadFound then
        local dist = #(vector3(x, y, z) - roadPos)
        return dist < 15.0
    end

    return true  -- default to on-road if uncertain
end

--- Check if entity is submerged in water using native.
---@param entity number Entity handle
---@return boolean
function CheckEntityInWater(entity)
    return IsEntityInWater(entity)
end

-- ─────────────────────────────────────────────
-- CLEANUP ON RESOURCE STOP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopVehicleMonitoring()
end)
