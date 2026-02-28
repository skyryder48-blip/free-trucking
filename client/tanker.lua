--[[
    client/tanker.lua — Fuel Tanker Drain Mechanic
    Free Trucking — QBX Framework

    Handles the 6 drain use cases for fuel tankers, spill zone creation,
    traction hazards, fire ignition detection, and all visual effects.

    Section 23 of the Development Guide.
]]

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local activeSpillZones    = {}    -- [zoneId] = { zone, particles, coords, radius, growing }
local activeDrainPort     = nil   -- { vehicle, coords, isOpen, startTime }
local drainInProgress     = false -- drain interaction currently active
local spillZoneIdCounter  = 0     -- unique zone ID generator

-- Particle effect handles for cleanup
local activeParticles     = {}    -- [index] = { handle, dict, isLooped }

-- Config references
local DRAIN_SECONDS_PER_DRUM = Config.DrainSecondsPerDrum or 30
local SELF_REFUEL_GALLONS    = Config.SelfRefuelGallons or 50
local SELF_REFUEL_DURATION   = Config.SelfRefuelDuration or 60000
local CANISTER_CAPACITY      = Config.FuelCanisterCapacity or 5
local CANISTER_MAX_CARRY     = Config.FuelCanisterMaxCarry or 4

-- Particle FX
local FUEL_PTFX_DICT         = 'core'
local FUEL_PUDDLE_PTFX       = 'ent_sht_water'          -- liquid pooling effect
local FUEL_DRIP_PTFX         = 'ent_sht_water'          -- drip from drain port
local FIRE_PTFX_DICT         = 'core'
local FIRE_PTFX_NAME         = 'ent_ray_prologue_fire'  -- fire at spill zone

-- Spill zone parameters
local SPILL_INITIAL_RADIUS   = 3.0      -- meters, starting spill radius
local SPILL_MAX_RADIUS       = 25.0     -- meters, maximum spill radius
local SPILL_GROW_RATE        = 0.5      -- meters per 10 seconds when drain port is open
local TRACTION_PENALTY       = 0.3      -- grip reduction (0.0 = no grip, 1.0 = full)

-- Fire detection
local FIRE_CHECK_INTERVAL    = 1000     -- ms between fire source checks
local FIRE_DETECT_RADIUS     = 5.0      -- meters — gunshot/explosion within this triggers ignition

-- ═══════════════════════════════════════════════════════════════
-- DRAIN USE CASE DETECTION
-- ═══════════════════════════════════════════════════════════════

--- Determine the drain use case based on context and inventory.
--- Returns: 'robbery', 'self_refuel', 'emergency_roadside', 'fuel_trap',
---          'property_storage', 'leon_diversion', or nil
---@param targetVehicle number Vehicle entity handle
---@return string|nil useCase
---@return table|nil context Additional context data
local function DetectDrainUseCase(targetVehicle)
    if not targetVehicle or not DoesEntityExist(targetVehicle) then
        return nil, nil
    end

    local playerPed = cache.ped
    local playerCoords = GetEntityCoords(playerPed)

    -- Determine vehicle ownership
    local isOwnVehicle = false
    local vehicleNetId = VehToNet(targetVehicle)

    -- Check via statebag if this is the player's active load vehicle
    local loadPlate = GetVehicleNumberPlateText(targetVehicle)
    if loadPlate then
        isOwnVehicle = lib.callback.await('trucking:server:isMyTanker', false, loadPlate)
    end

    -- Check inventory for required items (protected against missing ox_inventory)
    local function invCount(item)
        local ok, result = pcall(exports.ox_inventory.Search, exports.ox_inventory, 'count', item)
        return ok and result or 0
    end
    local hasHose       = invCount('fuel_hose') > 0
    local hasWrench     = invCount('valve_wrench') > 0
    local hasDrum       = invCount('fuel_drum') > 0
    local hasCanister   = invCount('fuel_canister') > 0
    local canisterCount = invCount('fuel_canister')

    -- Must have fuel_hose for any drain operation
    if not hasHose then
        return nil, nil
    end

    -- Leon fuel diversion: own tanker + drums + active Leon load indicator
    local isLeonDiversion = false
    if isOwnVehicle and hasDrum then
        isLeonDiversion = lib.callback.await('trucking:server:isLeonFuelDiversion', false)
    end

    if isLeonDiversion then
        return 'leon_diversion', { vehicle = targetVehicle, hasDrum = true }
    end

    -- Robbery drain: not own vehicle + valve_wrench + fuel_hose + fuel_drum
    if not isOwnVehicle and hasWrench and hasDrum then
        return 'robbery', { vehicle = targetVehicle }
    end

    -- Self-refuel: own tanker, fuel_hose only, no containers needed
    if isOwnVehicle and not hasDrum and not hasCanister then
        return 'self_refuel', { vehicle = targetVehicle, gallons = SELF_REFUEL_GALLONS }
    end

    -- Emergency roadside: own tanker + fuel_canister
    if isOwnVehicle and hasCanister then
        return 'emergency_roadside', {
            vehicle       = targetVehicle,
            canisterCount = math.min(canisterCount, CANISTER_MAX_CARRY),
        }
    end

    -- Fuel trap: own tanker, no containers at all — intentional spill
    if isOwnVehicle and not hasDrum and not hasCanister then
        return 'fuel_trap', { vehicle = targetVehicle }
    end

    -- Property storage: check if near a property fuel tank (export check)
    local nearProperty = false
    if isOwnVehicle then
        -- Try export to property script; fails gracefully if not available
        local success, result = pcall(function()
            return exports['property']:getNearbyFuelTank(playerCoords, 10.0)
        end)
        if success and result then
            return 'property_storage', { vehicle = targetVehicle, propertyTank = result }
        end
    end

    return nil, nil
end

-- ═══════════════════════════════════════════════════════════════
-- DRAIN INTERACTIONS
-- ═══════════════════════════════════════════════════════════════

--- Execute the drain progress bar with appropriate duration and label.
---@param useCase string The drain use case
---@param context table Additional context
---@return boolean completed True if drain completed without cancel
local function ExecuteDrain(useCase, context)
    if drainInProgress then
        lib.notify({ title = 'Tanker', description = 'Already draining.', type = 'error' })
        return false
    end

    drainInProgress = true

    local duration, label
    local anim = {
        dict  = 'mini@repair',
        clip  = 'fixing_a_ped',
        flag  = 49,
    }

    if useCase == 'robbery' then
        duration = DRAIN_SECONDS_PER_DRUM * 1000
        label    = 'Draining into drum...'
    elseif useCase == 'self_refuel' then
        duration = SELF_REFUEL_DURATION
        label    = 'Self-refueling...'
    elseif useCase == 'emergency_roadside' then
        -- Variable duration based on canister count
        local count = context.canisterCount or 1
        duration = math.floor((CANISTER_CAPACITY / SELF_REFUEL_GALLONS) * SELF_REFUEL_DURATION * count)
        duration = math.max(duration, 10000) -- minimum 10 seconds
        label    = string.format('Filling %d canister(s)...', count)
    elseif useCase == 'fuel_trap' then
        duration = 10000  -- 10 seconds to open the port
        label    = 'Opening drain port...'
    elseif useCase == 'property_storage' then
        duration = DRAIN_SECONDS_PER_DRUM * 1000
        label    = 'Draining into property tank...'
    elseif useCase == 'leon_diversion' then
        duration = DRAIN_SECONDS_PER_DRUM * 1000
        label    = 'Diverting fuel...'
    else
        drainInProgress = false
        return false
    end

    local completed = lib.progressBar({
        duration = duration,
        label    = label,
        useWhileDead = false,
        canCancel = true,
        disable = {
            car    = true,
            move   = true,
            combat = true,
        },
        anim = anim,
    })

    drainInProgress = false
    return completed
end

--- Handle the complete drain interaction for a given use case.
---@param targetVehicle number Target tanker vehicle
local function HandleDrainInteraction(targetVehicle)
    local useCase, context = DetectDrainUseCase(targetVehicle)

    if not useCase then
        lib.notify({
            title       = 'Tanker',
            description = 'You need a fuel hose to drain this tanker.',
            type        = 'error',
        })
        return
    end

    -- Show confirmation for destructive actions
    if useCase == 'robbery' or useCase == 'fuel_trap' then
        local confirm = lib.alertDialog({
            header  = useCase == 'robbery' and 'Drain Tanker' or 'Open Drain Port',
            content = useCase == 'robbery'
                and 'Drain fuel into drums. This is theft — proceed?'
                or 'Opening the drain with no container will create a fuel spill. Proceed?',
            centered = true,
            cancel   = true,
        })
        if confirm ~= 'confirm' then return end
    end

    -- Execute the drain
    local completed = ExecuteDrain(useCase, context)

    if not completed then
        lib.notify({ title = 'Tanker', description = 'Drain cancelled.', type = 'error' })
        return
    end

    -- Report to server based on use case
    local vehiclePlate = GetVehicleNumberPlateText(targetVehicle)
    local drainCoords  = GetEntityCoords(cache.ped)

    TriggerServerEvent('trucking:server:drainComplete', {
        useCase  = useCase,
        plate    = vehiclePlate,
        coords   = drainCoords,
        context  = context,
    })

    -- Use case specific post-drain handling
    if useCase == 'robbery' then
        -- Open the drain port — fuel will spill continuously
        OpenDrainPort(targetVehicle, drainCoords)

        lib.notify({
            title       = 'Tanker',
            description = 'Drum filled. Drain port is open — fuel is spilling.',
            type        = 'warning',
            duration    = 6000,
        })

    elseif useCase == 'self_refuel' then
        lib.notify({
            title       = 'Tanker',
            description = string.format('%d gallons transferred to your tank.', SELF_REFUEL_GALLONS),
            type        = 'success',
        })

    elseif useCase == 'emergency_roadside' then
        lib.notify({
            title       = 'Tanker',
            description = string.format('%d canister(s) filled.', context.canisterCount or 1),
            type        = 'success',
        })

    elseif useCase == 'fuel_trap' then
        -- Open drain port with no collection — immediate spill
        OpenDrainPort(targetVehicle, drainCoords)

        lib.notify({
            title       = 'Tanker',
            description = 'Drain port open. Fuel is pooling on the ground.',
            type        = 'warning',
            duration    = 6000,
        })

    elseif useCase == 'property_storage' then
        lib.notify({
            title       = 'Tanker',
            description = 'Fuel transferred to property tank.',
            type        = 'success',
        })

    elseif useCase == 'leon_diversion' then
        lib.notify({
            title       = 'Tanker',
            description = 'Drums filled for Leon\'s contact.',
            type        = 'success',
        })
    end
end

-- ═══════════════════════════════════════════════════════════════
-- DRAIN PORT AND SPILL ZONES
-- ═══════════════════════════════════════════════════════════════

--- Open a drain port on a vehicle. Fuel will spill continuously.
---@param vehicle number Vehicle handle
---@param coords vector3 Drain port location
function OpenDrainPort(vehicle, coords)
    if activeDrainPort and activeDrainPort.isOpen then
        -- Port already open — spill grows faster
        return
    end

    activeDrainPort = {
        vehicle   = vehicle,
        coords    = coords,
        isOpen    = true,
        startTime = GetGameTimer(),
    }

    -- Create initial spill zone
    local zoneId = CreateSpillZone(coords, SPILL_INITIAL_RADIUS)

    -- Spawn drip particle at drain point
    SpawnDripParticle(coords)

    -- Start spill growth thread
    CreateThread(function()
        while activeDrainPort and activeDrainPort.isOpen do
            Wait(10000) -- every 10 seconds

            if not activeDrainPort or not activeDrainPort.isOpen then break end

            -- Check if vehicle still exists
            if not DoesEntityExist(vehicle) then
                activeDrainPort.isOpen = false
                break
            end

            -- Grow the spill zone
            local zone = activeSpillZones[zoneId]
            if zone and zone.growing then
                local newRadius = math.min(zone.radius + SPILL_GROW_RATE, SPILL_MAX_RADIUS)
                UpdateSpillZoneRadius(zoneId, newRadius)
                -- Grow puddle particle
                SpawnPuddleParticle(coords, newRadius)
            end
        end
    end)
end

--- Create a fuel spill zone at the given coordinates.
---@param coords vector3 Center of spill
---@param radius number Initial radius in meters
---@return number zoneId Unique zone identifier
function CreateSpillZone(coords, radius)
    spillZoneIdCounter = spillZoneIdCounter + 1
    local zoneId = spillZoneIdCounter

    local zone = lib.zones.sphere({
        coords = coords,
        radius = radius,
        debug  = false,

        inside = function()
            -- Apply traction penalty to vehicles in zone
            local playerVeh = cache.vehicle
            if playerVeh and DoesEntityExist(playerVeh) then
                SetVehicleReduceGrip(playerVeh, true)
                SetVehicleReduceGripLevel(playerVeh, math.floor(TRACTION_PENALTY * 3))
            end
        end,

        onExit = function()
            -- Restore traction
            local playerVeh = cache.vehicle
            if playerVeh and DoesEntityExist(playerVeh) then
                SetVehicleReduceGrip(playerVeh, false)
            end
        end,
    })

    -- Spawn initial puddle particle
    SpawnPuddleParticle(coords, radius)

    activeSpillZones[zoneId] = {
        zone     = zone,
        coords   = coords,
        radius   = radius,
        growing  = true,
        ignited  = false,
        particles = {},
    }

    -- Start fire source detection for this zone
    StartFireDetection(zoneId)

    return zoneId
end

--- Update a spill zone's radius (zone grows over time).
---@param zoneId number Zone identifier
---@param newRadius number New radius in meters
function UpdateSpillZoneRadius(zoneId, newRadius)
    local spillData = activeSpillZones[zoneId]
    if not spillData then return end

    -- Remove old zone and create new one with updated radius
    if spillData.zone then
        spillData.zone:remove()
    end

    spillData.radius = newRadius

    spillData.zone = lib.zones.sphere({
        coords = spillData.coords,
        radius = newRadius,
        debug  = false,

        inside = function()
            local playerVeh = cache.vehicle
            if playerVeh and DoesEntityExist(playerVeh) then
                SetVehicleReduceGrip(playerVeh, true)
                SetVehicleReduceGripLevel(playerVeh, math.floor(TRACTION_PENALTY * 3))
            end
        end,

        onExit = function()
            local playerVeh = cache.vehicle
            if playerVeh and DoesEntityExist(playerVeh) then
                SetVehicleReduceGrip(playerVeh, false)
            end
        end,
    })
end

--- Remove a spill zone and all its effects.
---@param zoneId number Zone identifier
function RemoveSpillZone(zoneId)
    local spillData = activeSpillZones[zoneId]
    if not spillData then return end

    -- Remove zone
    if spillData.zone then
        spillData.zone:remove()
    end

    -- Remove particles
    if spillData.particles then
        for _, particleHandle in ipairs(spillData.particles) do
            if DoesParticleFxLoopedExist(particleHandle) then
                StopParticleFxLooped(particleHandle, false)
                RemoveParticleFx(particleHandle, false)
            end
        end
    end

    activeSpillZones[zoneId] = nil
end

-- ═══════════════════════════════════════════════════════════════
-- PARTICLE EFFECTS
-- ═══════════════════════════════════════════════════════════════

--- Spawn a fuel puddle particle effect at the given coords.
---@param coords vector3 Center of puddle
---@param radius number Current puddle radius (affects scale)
function SpawnPuddleParticle(coords, radius)
    RequestNamedPtfxAsset(FUEL_PTFX_DICT)
    local attempts = 0
    while not HasNamedPtfxAssetLoaded(FUEL_PTFX_DICT) and attempts < 100 do
        Wait(10)
        attempts = attempts + 1
    end

    if not HasNamedPtfxAssetLoaded(FUEL_PTFX_DICT) then return end

    UseParticleFxAsset(FUEL_PTFX_DICT)
    local scale = math.min(radius / SPILL_MAX_RADIUS * 3.0, 3.0)
    local handle = StartParticleFxLoopedAtCoord(
        FUEL_PUDDLE_PTFX,
        coords.x, coords.y, coords.z - 0.5,
        0.0, 0.0, 0.0,
        scale, false, false, false, false
    )

    if handle and handle > 0 then
        activeParticles[#activeParticles + 1] = {
            handle  = handle,
            dict    = FUEL_PTFX_DICT,
            isLooped = true,
        }
    end
end

--- Spawn a fuel drip particle at the drain port.
---@param coords vector3 Drain port location
function SpawnDripParticle(coords)
    RequestNamedPtfxAsset(FUEL_PTFX_DICT)
    local attempts = 0
    while not HasNamedPtfxAssetLoaded(FUEL_PTFX_DICT) and attempts < 100 do
        Wait(10)
        attempts = attempts + 1
    end

    if not HasNamedPtfxAssetLoaded(FUEL_PTFX_DICT) then return end

    UseParticleFxAsset(FUEL_PTFX_DICT)
    local handle = StartParticleFxLoopedAtCoord(
        FUEL_DRIP_PTFX,
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0,
        0.5, false, false, false, false
    )

    if handle and handle > 0 then
        activeParticles[#activeParticles + 1] = {
            handle  = handle,
            dict    = FUEL_PTFX_DICT,
            isLooped = true,
        }
    end
end

-- ═══════════════════════════════════════════════════════════════
-- FIRE DETECTION AND IGNITION
-- ═══════════════════════════════════════════════════════════════

--- Monitor a spill zone for fire sources (gunshots, explosions).
--- Triggers ignition -> fire spread -> tanker explosion sequence.
---@param zoneId number Zone identifier
function StartFireDetection(zoneId)
    CreateThread(function()
        while activeSpillZones[zoneId] and not activeSpillZones[zoneId].ignited do
            Wait(FIRE_CHECK_INTERVAL)

            local spillData = activeSpillZones[zoneId]
            if not spillData then break end

            local spillCoords = spillData.coords
            local detectRadius = spillData.radius + FIRE_DETECT_RADIUS

            -- Check for gunshots near spill
            local playerCoords = GetEntityCoords(cache.ped)
            if #(playerCoords - spillCoords) < detectRadius + 50.0 then

                -- Check if any ped is shooting near the spill
                for _, ped in ipairs(GetGamePool('CPed')) do
                    if DoesEntityExist(ped) and IsPedShooting(ped) then
                        local pedCoords = GetEntityCoords(ped)
                        if #(pedCoords - spillCoords) < detectRadius then
                            IgniteSpillZone(zoneId)
                            goto ignited
                        end
                    end
                end

                -- Check for existing fires or explosions near spill
                -- Use IsExplosionInSphere for native explosion detection
                for explosionType = 0, 12 do
                    if IsExplosionInSphere(explosionType, spillCoords.x, spillCoords.y, spillCoords.z, detectRadius) then
                        IgniteSpillZone(zoneId)
                        goto ignited
                    end
                end
            end
        end

        ::ignited::
    end)
end

--- Ignite a fuel spill zone. Triggers fire spread and eventual tanker explosion.
---@param zoneId number Zone identifier
function IgniteSpillZone(zoneId)
    local spillData = activeSpillZones[zoneId]
    if not spillData or spillData.ignited then return end

    spillData.ignited = true
    spillData.growing = false

    local coords = spillData.coords
    local radius = spillData.radius

    -- Spawn fire particles across the spill zone
    RequestNamedPtfxAsset(FIRE_PTFX_DICT)
    local attempts = 0
    while not HasNamedPtfxAssetLoaded(FIRE_PTFX_DICT) and attempts < 100 do
        Wait(10)
        attempts = attempts + 1
    end

    if HasNamedPtfxAssetLoaded(FIRE_PTFX_DICT) then
        -- Create fire points across the zone
        local firePoints = math.max(3, math.floor(radius / 3.0))
        for i = 1, firePoints do
            local angle = (i / firePoints) * math.pi * 2.0
            local offsetX = math.cos(angle) * (radius * 0.6)
            local offsetY = math.sin(angle) * (radius * 0.6)

            UseParticleFxAsset(FIRE_PTFX_DICT)
            local handle = StartParticleFxLoopedAtCoord(
                FIRE_PTFX_NAME,
                coords.x + offsetX, coords.y + offsetY, coords.z,
                0.0, 0.0, 0.0,
                1.5, false, false, false, false
            )

            if handle and handle > 0 then
                spillData.particles[#spillData.particles + 1] = handle
                activeParticles[#activeParticles + 1] = {
                    handle  = handle,
                    dict    = FIRE_PTFX_DICT,
                    isLooped = true,
                }
            end
        end
    end

    -- Create fire damage using native AddExplosion for heat/damage
    AddExplosion(coords.x, coords.y, coords.z, 12, 0.0, true, false, 0.0)  -- visible fire, no damage initially

    -- Notify server of ignition
    TriggerServerEvent('trucking:server:fuelSpillIgnited', {
        zoneId = zoneId,
        coords = coords,
        radius = radius,
    })

    lib.notify({
        title       = 'DANGER',
        description = 'Fuel spill ignited! Get clear!',
        type        = 'error',
        duration    = 8000,
    })

    -- Fire spread toward tanker if drain port is still open
    if activeDrainPort and activeDrainPort.isOpen and activeDrainPort.vehicle then
        CreateThread(function()
            -- Fire reaches tanker after a delay proportional to distance
            local tankerCoords = GetEntityCoords(activeDrainPort.vehicle)
            local distToTanker = #(coords - tankerCoords)
            local spreadDelay = math.max(3000, math.floor(distToTanker / 2.0) * 1000)

            Wait(spreadDelay)

            if activeDrainPort and activeDrainPort.vehicle and DoesEntityExist(activeDrainPort.vehicle) then
                -- Fire reached the tanker — trigger explosion sequence
                local plate = GetVehicleNumberPlateText(activeDrainPort.vehicle)
                TriggerServerEvent('trucking:server:tankerIgnition', {
                    plate  = plate,
                    coords = GetEntityCoords(activeDrainPort.vehicle),
                })
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- TANKER INTERACTION TARGET
-- ═══════════════════════════════════════════════════════════════

--- Check if a vehicle is a tanker model.
---@param vehicle number Vehicle entity handle
---@return boolean isTanker
local function IsTankerVehicle(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    local model = GetEntityModel(vehicle)
    -- Common tanker models in GTA V
    local tankerModels = {
        [`tanker`]  = true,
        [`tanker2`] = true,
        [`trailer`] = true,  -- can be tanker variant
    }
    return tankerModels[model] or false
end

--- Thread that monitors for nearby tanker vehicles and offers drain interaction.
CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end

    while true do
        Wait(2500)

        local playerPed    = cache.ped
        local playerCoords = GetEntityCoords(playerPed)

        -- Only check when on foot, not in a vehicle
        if cache.vehicle then goto continue end

        -- Check nearby vehicles for tankers (distance pre-filter before model check)
        local nearbyVehicle = nil
        local nearestDist   = 5.0  -- interaction range

        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(vehicle) then
                local vehCoords = GetEntityCoords(vehicle)
                local dist = #(playerCoords - vehCoords)
                if dist < nearestDist and IsTankerVehicle(vehicle) then
                    nearestDist   = dist
                    nearbyVehicle = vehicle
                end
            end
        end

        if nearbyVehicle then
            -- Check if player has fuel_hose (protected against missing ox_inventory)
            local hoseOk, hoseResult = pcall(exports.ox_inventory.Search, exports.ox_inventory, 'count', 'fuel_hose')
            local hasHose = hoseOk and hoseResult > 0
            if hasHose then
                -- Show interaction hint
                lib.showTextUI('[E] - Drain Tanker', { position = 'right-center' })

                -- Wait for key press
                while nearbyVehicle and DoesEntityExist(nearbyVehicle) do
                    Wait(0)
                    local currentDist = #(GetEntityCoords(cache.ped) - GetEntityCoords(nearbyVehicle))
                    if currentDist > nearestDist + 2.0 or cache.vehicle then
                        break
                    end

                    if IsControlJustPressed(0, 51) then -- E key
                        lib.hideTextUI()
                        HandleDrainInteraction(nearbyVehicle)
                        break
                    end
                end

                lib.hideTextUI()
            end
        end

        ::continue::
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- SERVER EVENTS
-- ═══════════════════════════════════════════════════════════════

--- Server confirms drain complete — update local state.
RegisterNetEvent('trucking:client:drainConfirmed', function(data)
    if data and data.message then
        lib.notify({
            title       = 'Tanker',
            description = data.message,
            type        = 'success',
        })
    end
end)

--- Server triggers external spill zone creation (e.g., from another player's drain).
RegisterNetEvent('trucking:client:createSpillZone', function(data)
    if not data or not data.coords then return end
    local coords = vector3(data.coords.x, data.coords.y, data.coords.z)
    local radius = data.radius or SPILL_INITIAL_RADIUS

    -- Only create if player is within render distance
    local playerCoords = GetEntityCoords(cache.ped)
    if #(playerCoords - coords) > 300.0 then return end

    CreateSpillZone(coords, radius)
end)

--- Server triggers spill zone removal (e.g., cleanup completed).
RegisterNetEvent('trucking:client:removeSpillZone', function(data)
    if not data or not data.zoneId then
        -- Remove all spill zones
        for id in pairs(activeSpillZones) do
            RemoveSpillZone(id)
        end
        return
    end
    RemoveSpillZone(data.zoneId)
end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════

--- Clean up all tanker-related effects and zones.
local function CleanupAll()
    -- Remove all spill zones
    for id in pairs(activeSpillZones) do
        RemoveSpillZone(id)
    end
    activeSpillZones = {}

    -- Remove all particles
    for _, particle in ipairs(activeParticles) do
        if particle.isLooped and DoesParticleFxLoopedExist(particle.handle) then
            StopParticleFxLooped(particle.handle, false)
            RemoveParticleFx(particle.handle, false)
        end
    end
    activeParticles = {}

    -- Reset drain port
    activeDrainPort = nil
    drainInProgress = false
    spillZoneIdCounter = 0

    lib.hideTextUI()
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    CleanupAll()
end)

RegisterNetEvent('qbx_core:client:onLogout', function()
    CleanupAll()
end)
