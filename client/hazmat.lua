--[[
    client/hazmat.lua — Hazmat Spill and Exposure Handling
    Free Trucking — QBX Framework

    Handles hazmat spill zone creation per class (3, 6, 7, 8),
    class-specific visual/audio/damage effects, cleanup interactions,
    and emergency dispatch notifications.

    Section 24 of the Development Guide.
]]

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local activeHazmatZones = {}    -- [zoneId] = { zone, class, coords, radius, particles, sounds }
local hazmatZoneIdCounter = 0   -- unique zone ID generator
local activeParticles   = {}    -- [index] = { handle, dict, isLooped }
local activeSounds      = {}    -- [index] = soundId
local cleanupInProgress = false

-- ═══════════════════════════════════════════════════════════════
-- CLASS DEFINITIONS
-- ═══════════════════════════════════════════════════════════════

local HAZMAT_CLASSES = {
    [3] = {
        name            = 'Flammable',
        color           = 'orange',
        radius          = 15.0,
        damagePerTick   = 0,           -- no direct damage, fire risk instead
        vehicleDamage   = 0,
        fireRisk        = true,
        ptfxDict        = 'core',
        ptfxName        = 'ent_ray_prologue_fire',
        ptfxScale       = 1.5,
        ptfxColor       = nil,         -- default fire color
        soundSet        = nil,
        soundName       = nil,
        cleanupItem     = 'hazmat_cleanup_kit',
        cleanupDuration = 60000,
    },
    [6] = {
        name            = 'Toxic',
        color           = 'green',
        radius          = 20.0,
        damagePerTick   = 3,           -- health damage per second to players
        vehicleDamage   = 0,
        fireRisk        = false,
        ptfxDict        = 'core',
        ptfxName        = 'ent_sht_smoke',
        ptfxScale       = 2.0,
        ptfxColor       = { r = 0.1, g = 0.9, b = 0.1 },  -- green toxic cloud
        soundSet        = nil,
        soundName       = nil,
        cleanupItem     = 'hazmat_cleanup_kit',
        cleanupDuration = 60000,
    },
    [7] = {
        name            = 'Radioactive',
        color           = 'yellow',
        radius          = 30.0,        -- wide radius
        damagePerTick   = 2,           -- continuous radiation damage
        vehicleDamage   = 0,
        fireRisk        = false,
        ptfxDict        = 'scr_trevor1',
        ptfxName        = 'scr_trev1_trailer_boosh',
        ptfxScale       = 2.5,
        ptfxColor       = { r = 1.0, g = 0.7, b = 0.0 },  -- yellow/orange radiation
        soundSet        = 'dlc_heist_biolab_prep_ambience_sounds',
        soundName       = 'Electrical_Interference',       -- Geiger counter approximation
        cleanupItem     = 'hazmat_cleanup_specialist',     -- specialist item required
        cleanupDuration = 60000,
    },
    [8] = {
        name            = 'Corrosive',
        color           = 'red',
        radius          = 12.0,
        damagePerTick   = 0,           -- no direct player damage
        vehicleDamage   = 5,           -- vehicle body/engine damage per second
        fireRisk        = false,
        ptfxDict        = 'core',
        ptfxName        = 'ent_sht_smoke',
        ptfxScale       = 1.5,
        ptfxColor       = { r = 0.8, g = 0.2, b = 0.2 },  -- red/brown corrosive mist
        soundSet        = nil,
        soundName       = nil,
        cleanupItem     = 'hazmat_cleanup_kit',
        cleanupDuration = 60000,
    },
}

-- ═══════════════════════════════════════════════════════════════
-- PARTICLE EFFECTS
-- ═══════════════════════════════════════════════════════════════

--- Request and wait for a PTFX asset to load.
---@param dict string PTFX dictionary name
---@return boolean loaded
local function LoadPtfxDict(dict)
    if HasNamedPtfxAssetLoaded(dict) then return true end

    RequestNamedPtfxAsset(dict)
    local attempts = 0
    while not HasNamedPtfxAssetLoaded(dict) and attempts < 200 do
        Wait(10)
        attempts = attempts + 1
    end

    return HasNamedPtfxAssetLoaded(dict)
end

--- Spawn class-specific particle effects at the spill zone.
---@param zoneId number Zone identifier
---@param classDef table Class definition from HAZMAT_CLASSES
---@param coords vector3 Zone center
---@param radius number Zone radius
---@return table handles Array of particle effect handles
local function SpawnHazmatParticles(zoneId, classDef, coords, radius)
    local handles = {}

    if not LoadPtfxDict(classDef.ptfxDict) then return handles end

    -- Calculate number of particle points based on zone radius
    local pointCount = math.max(4, math.floor(radius / 4.0))

    for i = 1, pointCount do
        local angle = (i / pointCount) * math.pi * 2.0
        local dist = radius * 0.5 * math.random(60, 100) / 100.0
        local offsetX = math.cos(angle) * dist
        local offsetY = math.sin(angle) * dist

        UseParticleFxAsset(classDef.ptfxDict)

        -- Apply color tint if specified
        if classDef.ptfxColor then
            SetParticleFxNonLoopedColour(classDef.ptfxColor.r, classDef.ptfxColor.g, classDef.ptfxColor.b)
        end

        local handle = StartParticleFxLoopedAtCoord(
            classDef.ptfxName,
            coords.x + offsetX, coords.y + offsetY, coords.z,
            0.0, 0.0, 0.0,
            classDef.ptfxScale,
            false, false, false, false
        )

        if handle and handle > 0 then
            -- Apply color to looped particle
            if classDef.ptfxColor then
                SetParticleFxLoopedColour(handle, classDef.ptfxColor.r, classDef.ptfxColor.g, classDef.ptfxColor.b, false)
                SetParticleFxLoopedAlpha(handle, 0.7)
            end

            handles[#handles + 1] = handle
            activeParticles[#activeParticles + 1] = {
                handle  = handle,
                dict    = classDef.ptfxDict,
                isLooped = true,
            }
        end
    end

    -- Center particle (larger, denser)
    UseParticleFxAsset(classDef.ptfxDict)
    local centerHandle = StartParticleFxLoopedAtCoord(
        classDef.ptfxName,
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0,
        classDef.ptfxScale * 1.5,
        false, false, false, false
    )

    if centerHandle and centerHandle > 0 then
        if classDef.ptfxColor then
            SetParticleFxLoopedColour(centerHandle, classDef.ptfxColor.r, classDef.ptfxColor.g, classDef.ptfxColor.b, false)
            SetParticleFxLoopedAlpha(centerHandle, 0.9)
        end
        handles[#handles + 1] = centerHandle
        activeParticles[#activeParticles + 1] = {
            handle  = centerHandle,
            dict    = classDef.ptfxDict,
            isLooped = true,
        }
    end

    return handles
end

-- ═══════════════════════════════════════════════════════════════
-- SOUND EFFECTS
-- ═══════════════════════════════════════════════════════════════

--- Start ambient hazard sounds for a zone.
---@param zoneId number Zone identifier
---@param classDef table Class definition
---@param coords vector3 Zone center
local function StartHazmatSounds(zoneId, classDef, coords)
    if not classDef.soundSet or not classDef.soundName then return end

    -- Use GTA ambient sound system
    local soundId = GetSoundId()
    PlaySoundFromCoord(
        soundId,
        classDef.soundName,
        coords.x, coords.y, coords.z,
        classDef.soundSet,
        true,     -- isNetwork
        0,        -- range
        false     -- p8
    )

    activeSounds[#activeSounds + 1] = soundId

    local zoneData = activeHazmatZones[zoneId]
    if zoneData then
        zoneData.soundId = soundId
    end
end

--- Stop ambient sounds for a zone.
---@param soundId number Sound ID to stop
local function StopHazmatSound(soundId)
    if soundId then
        StopSound(soundId)
        ReleaseSoundId(soundId)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- ZONE CREATION
-- ═══════════════════════════════════════════════════════════════

--- Create a hazmat spill zone with class-specific effects.
---@param hazmatClass number Hazmat class (3, 6, 7, 8)
---@param coords vector3 Spill center coordinates
---@param loadId number|nil Associated load ID
---@return number zoneId Zone identifier
function CreateHazmatZone(hazmatClass, coords, loadId)
    local classDef = HAZMAT_CLASSES[hazmatClass]
    if not classDef then
        lib.notify({
            title       = 'Hazmat',
            description = 'Unknown hazmat class.',
            type        = 'error',
        })
        return -1
    end

    hazmatZoneIdCounter = hazmatZoneIdCounter + 1
    local zoneId = hazmatZoneIdCounter

    -- Create the hazard zone
    local zone = lib.zones.sphere({
        coords = coords,
        radius = classDef.radius,
        debug  = false,

        onEnter = function()
            lib.notify({
                title       = 'HAZMAT WARNING',
                description = string.format('Class %d %s hazard zone! Evacuate immediately!', hazmatClass, classDef.name),
                type        = 'error',
                duration    = 6000,
            })
        end,

        inside = function()
            local playerPed = cache.ped

            -- Class 6 (toxic): continuous health damage to players
            if hazmatClass == 6 and classDef.damagePerTick > 0 then
                local health = GetEntityHealth(playerPed)
                if health > 100 then
                    SetEntityHealth(playerPed, health - classDef.damagePerTick)
                end
            end

            -- Class 7 (radioactive): continuous radiation damage, wider DOT
            if hazmatClass == 7 and classDef.damagePerTick > 0 then
                local health = GetEntityHealth(playerPed)
                if health > 100 then
                    SetEntityHealth(playerPed, health - classDef.damagePerTick)
                end
                -- Screen effect for radiation
                AnimpostfxPlay('DrugsMichaelAliensFight', 0, false)
            end

            -- Class 8 (corrosive): vehicle structural damage
            if hazmatClass == 8 and classDef.vehicleDamage > 0 then
                local playerVeh = cache.vehicle
                if playerVeh and DoesEntityExist(playerVeh) then
                    local bodyHealth = GetVehicleBodyHealth(playerVeh)
                    local engineHealth = GetVehicleEngineHealth(playerVeh)

                    if bodyHealth > 0 then
                        SetVehicleBodyHealth(playerVeh, bodyHealth - classDef.vehicleDamage)
                    end
                    if engineHealth > 0 then
                        SetVehicleEngineHealth(playerVeh, engineHealth - classDef.vehicleDamage)
                    end
                end
            end

            -- Class 3 (flammable): fire risk — check for ignition sources
            if hazmatClass == 3 and classDef.fireRisk then
                local zoneData = activeHazmatZones[zoneId]
                if zoneData and not zoneData.ignited then
                    -- Check for nearby shooting or explosions
                    for _, ped in ipairs(GetGamePool('CPed')) do
                        if DoesEntityExist(ped) and IsPedShooting(ped) then
                            local pedCoords = GetEntityCoords(ped)
                            if #(pedCoords - coords) < classDef.radius + 5.0 then
                                IgniteHazmatZone(zoneId)
                                break
                            end
                        end
                    end

                    -- Check for explosions
                    for explosionType = 0, 12 do
                        if IsExplosionInSphere(explosionType, coords.x, coords.y, coords.z, classDef.radius) then
                            IgniteHazmatZone(zoneId)
                            break
                        end
                    end
                end
            end
        end,

        onExit = function()
            -- Stop radiation screen effect
            if hazmatClass == 7 then
                AnimpostfxStop('DrugsMichaelAliensFight')
            end
        end,
    })

    -- Spawn particles
    local particleHandles = SpawnHazmatParticles(zoneId, classDef, coords, classDef.radius)

    -- Store zone data
    activeHazmatZones[zoneId] = {
        zone       = zone,
        class      = hazmatClass,
        classDef   = classDef,
        coords     = coords,
        radius     = classDef.radius,
        particles  = particleHandles,
        ignited    = false,
        loadId     = loadId,
        soundId    = nil,
    }

    -- Start ambient sounds
    StartHazmatSounds(zoneId, classDef, coords)

    -- Report to server
    TriggerServerEvent('trucking:server:hazmatSpillCreated', {
        zoneId     = zoneId,
        hazmatClass = hazmatClass,
        coords     = coords,
        radius     = classDef.radius,
        loadId     = loadId,
    })

    -- Fire emergency dispatch
    DispatchHazmatEmergency(hazmatClass, coords)

    return zoneId
end

--- Ignite a Class 3 flammable hazmat zone.
---@param zoneId number Zone identifier
function IgniteHazmatZone(zoneId)
    local zoneData = activeHazmatZones[zoneId]
    if not zoneData or zoneData.ignited then return end

    zoneData.ignited = true

    local coords = zoneData.coords
    local radius = zoneData.radius

    -- Add fire explosions across the zone
    local firePoints = math.max(3, math.floor(radius / 5.0))
    for i = 1, firePoints do
        local angle = (i / firePoints) * math.pi * 2.0
        local dist = radius * 0.5
        local fx = coords.x + math.cos(angle) * dist
        local fy = coords.y + math.sin(angle) * dist

        -- Stagger fire ignition for visual effect
        SetTimeout(i * 500, function()
            AddExplosion(fx, fy, coords.z, 12, 1.0, true, false, 1.0)
        end)
    end

    -- Notify server of ignition
    TriggerServerEvent('trucking:server:hazmatIgnited', {
        zoneId = zoneId,
        coords = coords,
    })

    lib.notify({
        title       = 'HAZMAT FIRE',
        description = 'Flammable material ignited! Clear the area!',
        type        = 'error',
        duration    = 8000,
    })
end

-- ═══════════════════════════════════════════════════════════════
-- SPILL TRIGGER DETECTION
-- ═══════════════════════════════════════════════════════════════

--- Monitor active HAZMAT loads for spill trigger conditions.
--- Triggered when major collision occurs or integrity < 15%.
RegisterNetEvent('trucking:client:hazmatSpillTrigger', function(data)
    if not data then return end

    local hazmatClass = data.hazmatClass
    local coords      = data.coords
    local loadId      = data.loadId

    if not hazmatClass or not coords then return end

    local spillCoords = vector3(coords.x, coords.y, coords.z)
    CreateHazmatZone(hazmatClass, spillCoords, loadId)

    lib.notify({
        title       = 'HAZMAT INCIDENT',
        description = string.format('Class %d %s spill detected!',
            hazmatClass, HAZMAT_CLASSES[hazmatClass] and HAZMAT_CLASSES[hazmatClass].name or 'Unknown'),
        type        = 'error',
        duration    = 8000,
    })
end)

--- Local collision-based spill detection for HAZMAT cargo.
--- Monitors the player's vehicle for major impacts.
local lastCollisionCheck = 0

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end

    while true do
        Wait(1000)

        -- Only check if player has active HAZMAT load
        local activeHazmatLoad = LocalPlayer.state.activeHazmatLoad
        if not activeHazmatLoad then goto continue end

        local playerVeh = cache.vehicle
        if not playerVeh or not DoesEntityExist(playerVeh) then goto continue end

        -- Check for major collision
        if HasEntityCollidedWithAnything(playerVeh) then
            local now = GetGameTimer()
            if now - lastCollisionCheck < 5000 then goto continue end
            lastCollisionCheck = now

            local speed = GetEntitySpeed(playerVeh) * 2.236936  -- m/s to mph
            -- Major collision at high speed
            if speed > 30.0 then
                local coords = GetEntityCoords(playerVeh)
                TriggerServerEvent('trucking:server:hazmatCollision', {
                    loadId   = activeHazmatLoad.loadId,
                    coords   = coords,
                    speed    = speed,
                    class    = activeHazmatLoad.hazmatClass,
                })
            end
        end

        -- Check cargo integrity threshold
        local integrity = activeHazmatLoad.integrity or 100
        local threshold = Config.HazmatSpillIntegrityThreshold or 15

        if integrity <= threshold and not activeHazmatLoad.spillTriggered then
            local coords = GetEntityCoords(playerVeh)
            TriggerServerEvent('trucking:server:hazmatIntegritySpill', {
                loadId   = activeHazmatLoad.loadId,
                coords   = coords,
                class    = activeHazmatLoad.hazmatClass,
            })
        end

        ::continue::
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP INTERACTION
-- ═══════════════════════════════════════════════════════════════

--- Attempt cleanup of a hazmat zone.
---@param zoneId number Zone identifier
local function AttemptCleanup(zoneId)
    if cleanupInProgress then
        lib.notify({ title = 'Hazmat', description = 'Cleanup already in progress.', type = 'error' })
        return
    end

    local zoneData = activeHazmatZones[zoneId]
    if not zoneData then return end

    local classDef = zoneData.classDef
    if not classDef then return end

    -- Check for required cleanup item (protected against missing ox_inventory)
    local requiredItem = classDef.cleanupItem
    local itemOk, itemResult = pcall(exports.ox_inventory.Search, exports.ox_inventory, 'count', requiredItem)
    local hasItem = itemOk and itemResult > 0

    if not hasItem then
        local itemLabel = requiredItem == 'hazmat_cleanup_specialist'
            and 'Specialist Cleanup Kit'
            or 'Hazmat Cleanup Kit'

        lib.notify({
            title       = 'Hazmat Cleanup',
            description = string.format('Requires: %s', itemLabel),
            type        = 'error',
            duration    = 4000,
        })
        return
    end

    cleanupInProgress = true

    local completed = lib.progressBar({
        duration = classDef.cleanupDuration or 60000,
        label    = string.format('Cleaning Class %d %s hazard...', zoneData.class, classDef.name),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car    = true,
            move   = true,
            combat = true,
        },
        anim = {
            dict = 'amb@world_human_janitor@male@base',
            clip = 'base',
            flag = 49,
        },
    })

    cleanupInProgress = false

    if not completed then
        lib.notify({ title = 'Hazmat', description = 'Cleanup cancelled.', type = 'error' })
        return
    end

    -- Report cleanup to server (server removes item and validates)
    TriggerServerEvent('trucking:server:hazmatCleanupComplete', {
        zoneId      = zoneId,
        hazmatClass = zoneData.class,
        coords      = zoneData.coords,
        loadId      = zoneData.loadId,
    })

    -- Remove zone locally
    RemoveHazmatZone(zoneId)

    lib.notify({
        title       = 'Hazmat Cleanup',
        description = string.format('Class %d %s hazard neutralized.', zoneData.class, classDef.name),
        type        = 'success',
        duration    = 5000,
    })
end

--- Thread to check if player is near a hazmat zone and offer cleanup.
CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end

    while true do
        Wait(2000)

        local playerCoords = GetEntityCoords(cache.ped)

        for zoneId, zoneData in pairs(activeHazmatZones) do
            local dist = #(playerCoords - zoneData.coords)

            -- Within cleanup range (edge of zone)
            if dist < zoneData.radius + 3.0 and dist > zoneData.radius - 5.0 then
                -- Check if player has cleanup item (protected against missing ox_inventory)
                local requiredItem = zoneData.classDef.cleanupItem
                local cleanupOk, cleanupResult = pcall(exports.ox_inventory.Search, exports.ox_inventory, 'count', requiredItem)
                local hasItem = cleanupOk and cleanupResult > 0

                if hasItem and not cleanupInProgress then
                    lib.showTextUI(string.format('[E] - Clean up Class %d %s hazard', zoneData.class, zoneData.classDef.name), {
                        position = 'right-center',
                    })

                    -- Wait for input or player moves away
                    while dist < zoneData.radius + 5.0 and not cache.vehicle do
                        Wait(0)
                        playerCoords = GetEntityCoords(cache.ped)
                        dist = #(playerCoords - zoneData.coords)

                        if IsControlJustPressed(0, 51) then -- E key
                            lib.hideTextUI()
                            AttemptCleanup(zoneId)
                            break
                        end
                    end

                    lib.hideTextUI()
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- EMERGENCY DISPATCH
-- ═══════════════════════════════════════════════════════════════

--- Fire emergency dispatch notification to police/fire scripts.
---@param hazmatClass number Hazmat class
---@param coords vector3 Incident coordinates
function DispatchHazmatEmergency(hazmatClass, coords)
    -- Try each configured police resource
    local dispatched = false
    if Config.PoliceResources then
        for _, resourceName in ipairs(Config.PoliceResources) do
            if GetResourceState(resourceName) == 'started' then
                local success = pcall(function()
                    exports[resourceName]:dispatchAlert({
                        type        = 'hazmat_incident',
                        priority    = 'high',
                        location    = coords,
                        details     = string.format('HAZMAT Class %d incident — %s',
                            hazmatClass,
                            HAZMAT_CLASSES[hazmatClass] and HAZMAT_CLASSES[hazmatClass].name or 'Unknown'),
                    })
                end)
                if success then
                    dispatched = true
                    break
                end
            end
        end
    end

    if not dispatched then
        -- Fallback: server-side dispatch
        TriggerServerEvent('trucking:server:hazmatDispatch', {
            hazmatClass = hazmatClass,
            coords      = coords,
        })
    end
end

-- ═══════════════════════════════════════════════════════════════
-- ZONE REMOVAL
-- ═══════════════════════════════════════════════════════════════

--- Remove a hazmat zone and all its effects.
---@param zoneId number Zone identifier
function RemoveHazmatZone(zoneId)
    local zoneData = activeHazmatZones[zoneId]
    if not zoneData then return end

    -- Remove zone
    if zoneData.zone then
        zoneData.zone:remove()
    end

    -- Stop particles
    if zoneData.particles then
        for _, handle in ipairs(zoneData.particles) do
            if DoesParticleFxLoopedExist(handle) then
                StopParticleFxLooped(handle, false)
                RemoveParticleFx(handle, false)
            end
        end
    end

    -- Stop sounds
    if zoneData.soundId then
        StopHazmatSound(zoneData.soundId)
    end

    -- Stop screen effects
    if zoneData.class == 7 then
        AnimpostfxStop('DrugsMichaelAliensFight')
    end

    activeHazmatZones[zoneId] = nil
end

-- ═══════════════════════════════════════════════════════════════
-- SERVER EVENTS
-- ═══════════════════════════════════════════════════════════════

--- Server requests zone creation (e.g., another player's spill visible to us).
RegisterNetEvent('trucking:client:createHazmatZone', function(data)
    if not data or not data.coords or not data.hazmatClass then return end

    local coords = vector3(data.coords.x, data.coords.y, data.coords.z)
    local playerCoords = GetEntityCoords(cache.ped)

    -- Only create if within render distance
    if #(playerCoords - coords) > 300.0 then return end

    CreateHazmatZone(data.hazmatClass, coords, data.loadId)
end)

--- Server requests zone removal (cleanup completed by another player).
RegisterNetEvent('trucking:client:removeHazmatZone', function(data)
    if not data then return end

    if data.zoneId then
        RemoveHazmatZone(data.zoneId)
    elseif data.all then
        for id in pairs(activeHazmatZones) do
            RemoveHazmatZone(id)
        end
    end
end)

--- Server updates active hazmat load state.
RegisterNetEvent('trucking:client:setActiveHazmatLoad', function(data)
    LocalPlayer.state:set('activeHazmatLoad', data, false)
end)

--- Server clears active hazmat load.
RegisterNetEvent('trucking:client:clearActiveHazmatLoad', function()
    LocalPlayer.state:set('activeHazmatLoad', nil, false)
end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════

--- Full cleanup of all hazmat effects.
local function CleanupAll()
    -- Remove all zones
    for id in pairs(activeHazmatZones) do
        RemoveHazmatZone(id)
    end
    activeHazmatZones = {}

    -- Remove any remaining particles
    for _, particle in ipairs(activeParticles) do
        if particle.isLooped and DoesParticleFxLoopedExist(particle.handle) then
            StopParticleFxLooped(particle.handle, false)
            RemoveParticleFx(particle.handle, false)
        end
    end
    activeParticles = {}

    -- Stop all sounds
    for _, soundId in ipairs(activeSounds) do
        StopSound(soundId)
        ReleaseSoundId(soundId)
    end
    activeSounds = {}

    -- Stop screen effects
    AnimpostfxStop('DrugsMichaelAliensFight')

    cleanupInProgress = false
    hazmatZoneIdCounter = 0

    lib.hideTextUI()
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    CleanupAll()
end)

RegisterNetEvent('qbx_core:client:onLogout', function()
    CleanupAll()
end)
