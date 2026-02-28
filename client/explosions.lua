--[[
    client/explosions.lua — Explosion Phase Sequencer
    Free Trucking — QBX Framework

    Receives explosion sequence data from the server and executes
    multi-phase explosion effects with timing. Handles fuel tanker
    5-phase sequences and HAZMAT class-specific explosion profiles.
    All effects scale by fill_level.

    Section 25 of the Development Guide.
]]

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local activeExplosions     = {}    -- [seqId] = { phases, particles, fires, startTime }
local explosionSeqCounter  = 0
local activeLoopedPtfx     = {}    -- [index] = handle (looped particle effects)
local activeFireZones      = {}    -- [index] = { zone, particles, expiresAt }
local activeScorchZones    = {}    -- [index] = { zone, expiresAt }

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════

-- Explosion types (native GTA)
local EXP_GRENADE       = 2
local EXP_MOLOTOV       = 5
local EXP_GAS_CANISTER  = 8
local EXP_TANKER        = 11
local EXP_PLANE_ROCKET  = 20
local EXP_VEHICLE       = 7

-- Particle FX
local SMOKE_PTFX_DICT   = 'scr_trevor1'
local SMOKE_PTFX_NAME   = 'scr_trev1_trailer_boosh'
local FIRE_PTFX_DICT    = 'core'
local FIRE_PTFX_NAME    = 'ent_ray_prologue_fire'
local SMOKE_COL_DICT    = 'scr_exile2'
local SMOKE_COL_NAME    = 'scr_ex2_jeep_crash_smoke'

-- Timings
local FIRE_ZONE_DURATION     = 180000  -- 180 seconds persistent fire
local SCORCH_ZONE_DURATION   = 180000  -- 180 seconds persistent scorch
local CHAIN_EXPLOSION_RADIUS = 30.0    -- meters for chain explosion detection

-- ═══════════════════════════════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════════════════════════════

--- Load a PTFX asset dictionary with timeout.
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

--- Scale a value by fill level (0.0 to 1.0).
---@param value number Base value
---@param fillLevel number Fill level 0.0 to 1.0
---@param minScale number|nil Minimum scale factor (default 0.3)
---@return number scaled Scaled value
local function ScaleByFill(value, fillLevel, minScale)
    minScale = minScale or 0.3
    local scale = math.max(minScale, fillLevel or 1.0)
    return value * scale
end

-- ═══════════════════════════════════════════════════════════════
-- SMOKE COLUMN
-- ═══════════════════════════════════════════════════════════════

--- Create a massive smoke column visible across the map.
---@param coords vector3 Base coordinates
---@param fillLevel number Fill level 0.0 to 1.0
---@return number|nil handle Looped particle handle
local function CreateSmokeColumn(coords, fillLevel)
    if not LoadPtfxDict(SMOKE_COL_DICT) then
        -- Fallback to core smoke
        if not LoadPtfxDict(SMOKE_PTFX_DICT) then return nil end
        UseParticleFxAsset(SMOKE_PTFX_DICT)
        local handle = StartParticleFxLoopedAtCoord(
            SMOKE_PTFX_NAME,
            coords.x, coords.y, coords.z + 5.0,
            0.0, 0.0, 0.0,
            ScaleByFill(8.0, fillLevel, 0.4),
            false, false, false, false
        )
        if handle and handle > 0 then
            activeLoopedPtfx[#activeLoopedPtfx + 1] = handle
            return handle
        end
        return nil
    end

    UseParticleFxAsset(SMOKE_COL_DICT)
    local scale = ScaleByFill(6.0, fillLevel, 0.4)
    local handle = StartParticleFxLoopedAtCoord(
        SMOKE_COL_NAME,
        coords.x, coords.y, coords.z + 5.0,
        0.0, 0.0, 0.0,
        scale, false, false, false, false
    )

    if handle and handle > 0 then
        activeLoopedPtfx[#activeLoopedPtfx + 1] = handle
        return handle
    end

    return nil
end

-- ═══════════════════════════════════════════════════════════════
-- FIRE ZONE (PERSISTENT)
-- ═══════════════════════════════════════════════════════════════

--- Create a persistent fire zone that damages entities for 180 seconds.
---@param coords vector3 Center of fire zone
---@param radius number Fire zone radius
---@param duration number Duration in ms
---@return number zoneIndex Index in activeFireZones
local function CreateFireZone(coords, radius, duration)
    local particles = {}

    -- Spawn fire particles across the zone
    if LoadPtfxDict(FIRE_PTFX_DICT) then
        local fireCount = math.max(4, math.floor(radius / 3.0))
        for i = 1, fireCount do
            local angle = (i / fireCount) * math.pi * 2.0
            local dist = radius * 0.6 * (0.5 + math.random() * 0.5)
            local fx = coords.x + math.cos(angle) * dist
            local fy = coords.y + math.sin(angle) * dist

            UseParticleFxAsset(FIRE_PTFX_DICT)
            local handle = StartParticleFxLoopedAtCoord(
                FIRE_PTFX_NAME,
                fx, fy, coords.z,
                0.0, 0.0, 0.0,
                2.0, false, false, false, false
            )

            if handle and handle > 0 then
                particles[#particles + 1] = handle
                activeLoopedPtfx[#activeLoopedPtfx + 1] = handle
            end
        end
    end

    -- Create damage zone
    local zone = lib.zones.sphere({
        coords = coords,
        radius = radius,
        debug  = false,

        inside = function()
            -- Damage player in fire zone
            local playerPed = cache.ped
            local health = GetEntityHealth(playerPed)
            if health > 100 then
                SetEntityHealth(playerPed, health - 5)
            end

            -- Set player on fire if in center
            local playerCoords = GetEntityCoords(playerPed)
            if #(playerCoords - coords) < radius * 0.3 then
                if not IsEntityOnFire(playerPed) then
                    StartEntityFire(playerPed)
                end
            end
        end,
    })

    local expiresAt = GetGameTimer() + duration

    local index = #activeFireZones + 1
    activeFireZones[index] = {
        zone      = zone,
        particles = particles,
        coords    = coords,
        radius    = radius,
        expiresAt = expiresAt,
    }

    -- Auto-cleanup thread
    CreateThread(function()
        Wait(duration)

        local fireData = activeFireZones[index]
        if fireData then
            -- Remove zone
            if fireData.zone then
                fireData.zone:remove()
            end

            -- Remove particles
            for _, handle in ipairs(fireData.particles) do
                if DoesParticleFxLoopedExist(handle) then
                    StopParticleFxLooped(handle, false)
                    RemoveParticleFx(handle, false)
                end
            end

            activeFireZones[index] = nil
        end
    end)

    return index
end

-- ═══════════════════════════════════════════════════════════════
-- SCORCH ZONE (PERSISTENT)
-- ═══════════════════════════════════════════════════════════════

--- Create a ground scorch zone that persists visually.
---@param coords vector3 Center
---@param radius number Scorch radius
---@param duration number Duration in ms
local function CreateScorchZone(coords, radius, duration)
    -- Use decal or dark ground effect
    -- Native ground scorch via StartScriptFire
    local fires = {}
    local fireCount = math.max(2, math.floor(radius / 5.0))

    for i = 1, fireCount do
        local angle = (i / fireCount) * math.pi * 2.0
        local dist = radius * 0.4
        local fx = coords.x + math.cos(angle) * dist
        local fy = coords.y + math.sin(angle) * dist

        local fireHandle = StartScriptFire(fx, fy, coords.z, 5, false)
        fires[#fires + 1] = fireHandle
    end

    local index = #activeScorchZones + 1
    activeScorchZones[index] = {
        fires     = fires,
        coords    = coords,
        radius    = radius,
        expiresAt = GetGameTimer() + duration,
    }

    -- Auto-cleanup
    CreateThread(function()
        Wait(duration)

        local scorchData = activeScorchZones[index]
        if scorchData then
            for _, fireHandle in ipairs(scorchData.fires) do
                RemoveScriptFire(fireHandle)
            end
            activeScorchZones[index] = nil
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- CHAIN EXPLOSIONS
-- ═══════════════════════════════════════════════════════════════

--- Find and detonate vehicles within the scorch zone.
---@param coords vector3 Explosion center
---@param radius number Scorch zone radius
---@param fillLevel number Fill level scale factor
local function TriggerChainExplosions(coords, radius, fillLevel)
    local searchRadius = ScaleByFill(radius, fillLevel, 0.5)

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and not IsEntityDead(vehicle) then
            local vehCoords = GetEntityCoords(vehicle)
            local dist = #(vehCoords - coords)

            if dist < searchRadius and dist > 3.0 then
                -- Stagger chain explosions over 5-15 seconds
                local delay = math.random(0, 10000)

                SetTimeout(delay, function()
                    if DoesEntityExist(vehicle) and not IsEntityDead(vehicle) then
                        -- Damage vehicle first, then explode
                        SetVehicleEngineHealth(vehicle, -1.0)
                        NetworkExplodeVehicle(vehicle, true, false, false)
                    end
                end)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- FUEL TANKER 5-PHASE SEQUENCE
-- ═══════════════════════════════════════════════════════════════

--- Execute the 5-phase fuel tanker explosion sequence.
---@param coords vector3 Explosion center
---@param fillLevel number Fuel fill level 0.0 to 1.0
---@param vehicleNetId number|nil Network ID of the tanker vehicle
local function ExecuteFuelTankerSequence(coords, fillLevel, vehicleNetId)
    fillLevel = fillLevel or 1.0

    local baseRadius = ScaleByFill(10.0, fillLevel)
    local vehicle = nil

    if vehicleNetId then
        vehicle = NetToVeh(vehicleNetId)
    end

    -- ── Phase 1 (0s): Initial ignition ──────────────────────
    -- Native vehicle explosion at base radius
    AddExplosion(coords.x, coords.y, coords.z, EXP_TANKER, baseRadius, true, false, 1.0)

    if vehicle and DoesEntityExist(vehicle) then
        SetVehicleEngineHealth(vehicle, -1.0)
    end

    -- Start smoke column immediately
    CreateSmokeColumn(coords, fillLevel)

    -- ── Phase 2 (+2s): Tank rupture ─────────────────────────
    -- 3x radius explosion, vehicle launch force
    SetTimeout(2000, function()
        local expandedRadius = ScaleByFill(30.0, fillLevel)
        AddExplosion(coords.x, coords.y, coords.z, EXP_PLANE_ROCKET, expandedRadius * 0.5, true, false, 1.0)

        -- Launch nearby vehicles
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(veh) then
                local vehCoords = GetEntityCoords(veh)
                local dist = #(vehCoords - coords)

                if dist < expandedRadius then
                    local forceMag = ScaleByFill(80.0, fillLevel) * (1.0 - dist / expandedRadius)
                    local dirX = (vehCoords.x - coords.x) / math.max(dist, 1.0)
                    local dirY = (vehCoords.y - coords.y) / math.max(dist, 1.0)

                    ApplyForceToEntity(veh, 1,
                        dirX * forceMag, dirY * forceMag, forceMag * 0.5,
                        0.0, 0.0, 0.0,
                        0, false, true, true, false, true
                    )
                end
            end
        end
    end)

    -- ── Phase 3 (+3s): Pressure wave ────────────────────────
    -- Concussive blast, max knockback on nearby peds
    SetTimeout(3000, function()
        local waveRadius = ScaleByFill(40.0, fillLevel)

        -- Invisible explosion for concussion
        AddExplosion(coords.x, coords.y, coords.z, EXP_GRENADE, 0.0, false, true, ScaleByFill(3.0, fillLevel))

        -- Knock back all peds in range
        for _, ped in ipairs(GetGamePool('CPed')) do
            if DoesEntityExist(ped) then
                local pedCoords = GetEntityCoords(ped)
                local dist = #(pedCoords - coords)

                if dist < waveRadius and dist > 1.0 then
                    local forceMag = ScaleByFill(50.0, fillLevel) * (1.0 - dist / waveRadius)
                    local dirX = (pedCoords.x - coords.x) / dist
                    local dirY = (pedCoords.y - coords.y) / dist

                    SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
                    ApplyForceToEntity(ped, 1,
                        dirX * forceMag, dirY * forceMag, forceMag * 0.3,
                        0.0, 0.0, 0.0,
                        0, false, true, true, false, true
                    )
                end
            end
        end

        -- Camera shake for nearby players
        local playerDist = #(GetEntityCoords(cache.ped) - coords)
        if playerDist < waveRadius * 2.0 then
            local shakeIntensity = ScaleByFill(8.0, fillLevel) * (1.0 - playerDist / (waveRadius * 2.0))
            ShakeGameplayCam('MEDIUM_EXPLOSION_SHAKE', shakeIntensity)
        end
    end)

    -- ── Phase 4 (+4s): Fire column ──────────────────────────
    -- Persistent fire zone, 180 seconds duration
    SetTimeout(4000, function()
        local fireRadius = ScaleByFill(20.0, fillLevel)
        CreateFireZone(coords, fireRadius, FIRE_ZONE_DURATION)
        CreateScorchZone(coords, fireRadius * 1.5, SCORCH_ZONE_DURATION)
    end)

    -- ── Phase 5 (+5-15s): Secondary ignitions ───────────────
    -- Chain explosions on nearby vehicles in scorch zone
    SetTimeout(5000, function()
        local chainRadius = ScaleByFill(CHAIN_EXPLOSION_RADIUS, fillLevel)
        TriggerChainExplosions(coords, chainRadius, fillLevel)
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- HAZMAT CLASS-SPECIFIC EXPLOSION PROFILES
-- ═══════════════════════════════════════════════════════════════

--- Execute a Class 3 (flammable) explosion — similar to fuel but smaller.
---@param coords vector3 Explosion center
---@param fillLevel number Fill level 0.0 to 1.0
local function ExecuteClass3Explosion(coords, fillLevel)
    fillLevel = (fillLevel or 1.0) * 0.6  -- smaller scale than fuel tanker

    -- Phase 1: Initial fire burst
    AddExplosion(coords.x, coords.y, coords.z, EXP_MOLOTOV, ScaleByFill(8.0, fillLevel), true, false, 1.0)

    -- Phase 2: Secondary burst
    SetTimeout(1500, function()
        AddExplosion(coords.x, coords.y, coords.z, EXP_GAS_CANISTER, ScaleByFill(5.0, fillLevel), true, false, 0.8)
    end)

    -- Phase 3: Fire zone (shorter duration)
    SetTimeout(2500, function()
        local fireRadius = ScaleByFill(12.0, fillLevel)
        CreateFireZone(coords, fireRadius, FIRE_ZONE_DURATION * 0.5)
    end)

    -- Smoke column (smaller)
    CreateSmokeColumn(coords, fillLevel * 0.5)
end

--- Execute a Class 6 (toxic) explosion — toxic cloud, no fire.
---@param coords vector3 Explosion center
---@param fillLevel number Fill level 0.0 to 1.0
local function ExecuteClass6Explosion(coords, fillLevel)
    fillLevel = fillLevel or 1.0

    -- No explosion — just expanding toxic cloud
    local cloudRadius = ScaleByFill(25.0, fillLevel)

    -- Spawn toxic cloud particles
    if LoadPtfxDict('core') then
        local cloudPoints = math.max(6, math.floor(cloudRadius / 3.0))

        for i = 1, cloudPoints do
            local angle = (i / cloudPoints) * math.pi * 2.0
            local dist = cloudRadius * 0.5 * (0.3 + math.random() * 0.7)
            local fx = coords.x + math.cos(angle) * dist
            local fy = coords.y + math.sin(angle) * dist

            UseParticleFxAsset('core')
            local handle = StartParticleFxLoopedAtCoord(
                'ent_sht_smoke',
                fx, fy, coords.z,
                0.0, 0.0, 0.0,
                ScaleByFill(3.0, fillLevel),
                false, false, false, false
            )

            if handle and handle > 0 then
                SetParticleFxLoopedColour(handle, 0.1, 0.9, 0.1, false)
                SetParticleFxLoopedAlpha(handle, 0.6)
                activeLoopedPtfx[#activeLoopedPtfx + 1] = handle
            end
        end
    end

    -- Create toxic damage zone
    local zone = lib.zones.sphere({
        coords = coords,
        radius = cloudRadius,
        debug  = false,

        inside = function()
            local health = GetEntityHealth(cache.ped)
            if health > 100 then
                SetEntityHealth(cache.ped, health - ScaleByFill(4, fillLevel, 0.5))
            end
        end,
    })

    local index = #activeFireZones + 1
    activeFireZones[index] = {
        zone      = zone,
        particles = {},
        coords    = coords,
        radius    = cloudRadius,
        expiresAt = GetGameTimer() + FIRE_ZONE_DURATION,
    }

    -- Auto-cleanup
    CreateThread(function()
        Wait(FIRE_ZONE_DURATION)
        local data = activeFireZones[index]
        if data then
            if data.zone then data.zone:remove() end
            activeFireZones[index] = nil
        end
    end)
end

--- Execute a Class 7 (radioactive) explosion — radiation burst, no explosion.
---@param coords vector3 Explosion center
---@param fillLevel number Fill level 0.0 to 1.0
local function ExecuteClass7Explosion(coords, fillLevel)
    fillLevel = fillLevel or 1.0

    -- Radiation burst — visual flash but no destructive explosion
    local radRadius = ScaleByFill(35.0, fillLevel)

    -- Screen flash effect
    AnimpostfxPlay('DrugsMichaelAliensFight', 0, false)
    SetTimeout(3000, function()
        AnimpostfxStop('DrugsMichaelAliensFight')
    end)

    -- Spawn radiation particles (yellow/orange)
    if LoadPtfxDict(SMOKE_PTFX_DICT) then
        local particleCount = math.max(8, math.floor(radRadius / 3.0))

        for i = 1, particleCount do
            local angle = (i / particleCount) * math.pi * 2.0
            local dist = radRadius * 0.4 * (0.3 + math.random() * 0.7)
            local fx = coords.x + math.cos(angle) * dist
            local fy = coords.y + math.sin(angle) * dist

            UseParticleFxAsset(SMOKE_PTFX_DICT)
            local handle = StartParticleFxLoopedAtCoord(
                SMOKE_PTFX_NAME,
                fx, fy, coords.z,
                0.0, 0.0, 0.0,
                ScaleByFill(2.5, fillLevel),
                false, false, false, false
            )

            if handle and handle > 0 then
                SetParticleFxLoopedColour(handle, 1.0, 0.7, 0.0, false)
                SetParticleFxLoopedAlpha(handle, 0.5)
                activeLoopedPtfx[#activeLoopedPtfx + 1] = handle
            end
        end
    end

    -- Persistent radiation damage zone
    local zone = lib.zones.sphere({
        coords = coords,
        radius = radRadius,
        debug  = false,

        onEnter = function()
            -- Start Geiger counter sound
            PlaySoundFromCoord(-1, 'Electrical_Interference',
                coords.x, coords.y, coords.z,
                'dlc_heist_biolab_prep_ambience_sounds',
                true, 0, false)
            AnimpostfxPlay('DrugsMichaelAliensFight', 0, true)
        end,

        inside = function()
            local health = GetEntityHealth(cache.ped)
            if health > 100 then
                SetEntityHealth(cache.ped, health - ScaleByFill(3, fillLevel, 0.5))
            end
        end,

        onExit = function()
            AnimpostfxStop('DrugsMichaelAliensFight')
        end,
    })

    local index = #activeFireZones + 1
    activeFireZones[index] = {
        zone      = zone,
        particles = {},
        coords    = coords,
        radius    = radRadius,
        expiresAt = GetGameTimer() + FIRE_ZONE_DURATION,
    }

    CreateThread(function()
        Wait(FIRE_ZONE_DURATION)
        local data = activeFireZones[index]
        if data then
            if data.zone then data.zone:remove() end
            AnimpostfxStop('DrugsMichaelAliensFight')
            activeFireZones[index] = nil
        end
    end)
end

--- Execute a Class 8 (corrosive) explosion — corrosive mist, no fire.
---@param coords vector3 Explosion center
---@param fillLevel number Fill level 0.0 to 1.0
local function ExecuteClass8Explosion(coords, fillLevel)
    fillLevel = fillLevel or 1.0

    -- Corrosive mist — no fire, vehicle damage over time
    local mistRadius = ScaleByFill(15.0, fillLevel)

    -- Spawn corrosive mist particles (reddish-brown)
    if LoadPtfxDict('core') then
        local mistPoints = math.max(5, math.floor(mistRadius / 3.0))

        for i = 1, mistPoints do
            local angle = (i / mistPoints) * math.pi * 2.0
            local dist = mistRadius * 0.5 * (0.4 + math.random() * 0.6)
            local fx = coords.x + math.cos(angle) * dist
            local fy = coords.y + math.sin(angle) * dist

            UseParticleFxAsset('core')
            local handle = StartParticleFxLoopedAtCoord(
                'ent_sht_smoke',
                fx, fy, coords.z,
                0.0, 0.0, 0.0,
                ScaleByFill(2.0, fillLevel),
                false, false, false, false
            )

            if handle and handle > 0 then
                SetParticleFxLoopedColour(handle, 0.8, 0.2, 0.2, false)
                SetParticleFxLoopedAlpha(handle, 0.5)
                activeLoopedPtfx[#activeLoopedPtfx + 1] = handle
            end
        end
    end

    -- Create corrosive damage zone (vehicle damage only)
    local zone = lib.zones.sphere({
        coords = coords,
        radius = mistRadius,
        debug  = false,

        inside = function()
            local playerVeh = cache.vehicle
            if playerVeh and DoesEntityExist(playerVeh) then
                local bodyHealth = GetVehicleBodyHealth(playerVeh)
                local engineHealth = GetVehicleEngineHealth(playerVeh)
                local dmg = ScaleByFill(8, fillLevel, 0.5)

                if bodyHealth > 0 then
                    SetVehicleBodyHealth(playerVeh, bodyHealth - dmg)
                end
                if engineHealth > 0 then
                    SetVehicleEngineHealth(playerVeh, engineHealth - dmg)
                end
            end
        end,
    })

    local index = #activeFireZones + 1
    activeFireZones[index] = {
        zone      = zone,
        particles = {},
        coords    = coords,
        radius    = mistRadius,
        expiresAt = GetGameTimer() + FIRE_ZONE_DURATION,
    }

    CreateThread(function()
        Wait(FIRE_ZONE_DURATION)
        local data = activeFireZones[index]
        if data then
            if data.zone then data.zone:remove() end
            activeFireZones[index] = nil
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- MAIN EVENT HANDLER
-- ═══════════════════════════════════════════════════════════════

--- Execute an explosion sequence based on data from the server.
--- This is the main entry point for all explosion effects.
---@param data table Explosion data from server
---  data.profile:      string - 'fuel_tanker_full', 'hazmat_class3', etc.
---  data.coords:       table  - {x, y, z} explosion center
---  data.fill_level:   number - 0.0 to 1.0 fill/cargo level
---  data.vehicleNetId: number - network ID of source vehicle (optional)
---  data.hazmat_class: number - hazmat class for class-specific profiles (optional)
RegisterNetEvent('trucking:client:executeExplosion', function(data)
    if not data or not data.coords then return end

    local coords = vector3(
        data.coords.x or data.coords[1],
        data.coords.y or data.coords[2],
        data.coords.z or data.coords[3]
    )

    local fillLevel    = data.fill_level or 1.0
    local profile      = data.profile or 'fuel_tanker_full'
    local vehicleNetId = data.vehicleNetId
    local hazmatClass  = data.hazmat_class

    -- Distance check — only render effects within reasonable range
    local playerCoords = GetEntityCoords(cache.ped)
    local dist = #(playerCoords - coords)

    -- Always render smoke column (visible across map)
    -- But skip detailed effects if too far
    if dist > 500.0 then
        -- Only render smoke column at distance
        CreateSmokeColumn(coords, fillLevel)
        return
    end

    -- Route to appropriate explosion profile
    if profile == 'fuel_tanker_full' or profile == 'fuel_tanker' then
        ExecuteFuelTankerSequence(coords, fillLevel, vehicleNetId)

    elseif profile == 'hazmat_class3' or hazmatClass == 3 then
        ExecuteClass3Explosion(coords, fillLevel)

    elseif profile == 'hazmat_class6' or hazmatClass == 6 then
        ExecuteClass6Explosion(coords, fillLevel)

    elseif profile == 'hazmat_class7' or hazmatClass == 7 then
        ExecuteClass7Explosion(coords, fillLevel)

    elseif profile == 'hazmat_class8' or hazmatClass == 8 then
        ExecuteClass8Explosion(coords, fillLevel)

    else
        -- Default: generic vehicle explosion
        AddExplosion(coords.x, coords.y, coords.z, EXP_VEHICLE, ScaleByFill(5.0, fillLevel), true, false, 1.0)
        CreateSmokeColumn(coords, fillLevel * 0.3)
    end
end)

--- Server triggers a specific explosion phase (for multi-phase sequences)
RegisterNetEvent('trucking:client:explosionPhase', function(data)
    if not data or not data.coords then return end
    local coords = vector3(data.coords.x or data.coords[1], data.coords.y or data.coords[2], data.coords.z or data.coords[3])
    local expType = data.explosionType or 2
    local radius = data.radius or 5.0
    AddExplosion(coords.x, coords.y, coords.z, expType, radius, true, false, data.cameraShake or 1.0)
end)

--- Server creates a fuel fire zone at location
RegisterNetEvent('trucking:client:fuelFireZone', function(data)
    if not data or not data.coords then return end
    local coords = vector3(data.coords.x or data.coords[1], data.coords.y or data.coords[2], data.coords.z or data.coords[3])
    local radius = data.radius or 15.0
    local duration = data.duration or FIRE_ZONE_DURATION
    CreateFireZone(coords, radius, duration)
end)

--- Server sends periodic hazard zone damage tick
RegisterNetEvent('trucking:client:hazardZoneTick', function(data)
    if not data then return end
    local playerCoords = GetEntityCoords(cache.ped)
    if data.coords then
        local zoneCoords = vector3(data.coords.x or data.coords[1], data.coords.y or data.coords[2], data.coords.z or data.coords[3])
        local dist = #(playerCoords - zoneCoords)
        if dist < (data.radius or 30.0) then
            local health = GetEntityHealth(cache.ped)
            if health > 100 then
                SetEntityHealth(cache.ped, health - (data.damage or 2))
            end
        end
    end
end)

--- Server notifies HAZMAT zone has been cleaned up (by another player)
RegisterNetEvent('trucking:client:hazmatCleanedUp', function(data)
    if not data then return end
    lib.notify({
        title = 'Hazmat Cleaned',
        description = 'A hazmat zone has been neutralized.',
        type = 'success',
    })
end)

--- Server notifies HAZMAT fire ignition
RegisterNetEvent('trucking:client:hazmatFire', function(data)
    if not data or not data.coords then return end
    local coords = vector3(data.coords.x or data.coords[1], data.coords.y or data.coords[2], data.coords.z or data.coords[3])
    AddExplosion(coords.x, coords.y, coords.z, 12, data.radius or 5.0, true, false, 1.0)
    lib.notify({
        title = 'HAZMAT Fire',
        description = 'Hazardous material has ignited!',
        type = 'error',
        duration = 6000,
    })
end)

--- Server creates a HAZMAT spill zone visible to nearby players
RegisterNetEvent('trucking:client:hazmatSpillZone', function(data)
    if not data or not data.coords or not data.hazmatClass then return end
    local coords = vector3(data.coords.x or data.coords[1], data.coords.y or data.coords[2], data.coords.z or data.coords[3])
    local playerCoords = GetEntityCoords(cache.ped)
    if #(playerCoords - coords) > 300.0 then return end
    CreateHazmatZone(data.hazmatClass, coords, data.loadId)
end)

--- Server requests removal of a fire zone
RegisterNetEvent('trucking:client:removeFireZone', function(data)
    if not data then return end
    local index = data.zoneIndex
    if index and activeFireZones[index] then
        local fireData = activeFireZones[index]
        if fireData.zone then fireData.zone:remove() end
        if fireData.particles then
            for _, handle in ipairs(fireData.particles) do
                if DoesParticleFxLoopedExist(handle) then
                    StopParticleFxLooped(handle, false)
                    RemoveParticleFx(handle, false)
                end
            end
        end
        activeFireZones[index] = nil
    end
end)

--- Server syncs all active fire zones on join/reconnect
RegisterNetEvent('trucking:client:syncFireZones', function(data)
    if not data or not data.zones then return end
    local playerCoords = GetEntityCoords(cache.ped)
    for _, zoneData in ipairs(data.zones) do
        if zoneData.coords then
            local coords = vector3(zoneData.coords.x or zoneData.coords[1], zoneData.coords.y or zoneData.coords[2], zoneData.coords.z or zoneData.coords[3])
            if #(playerCoords - coords) <= 300.0 then
                local radius = zoneData.radius or 15.0
                local remaining = zoneData.remainingMs or FIRE_ZONE_DURATION
                CreateFireZone(coords, radius, remaining)
            end
        end
    end
end)

--- Server alerts nearby players about a tanker fire
RegisterNetEvent('trucking:client:tankerFireAlert', function(data)
    if not data then return end
    lib.notify({
        title = 'Tanker Fire Alert',
        description = 'A fuel tanker fire has been reported nearby. Avoid the area!',
        type = 'error',
        duration = 10000,
    })
    if data.coords then
        local coords = data.coords
        SetNewWaypoint(coords.x or coords[1], coords.y or coords[2])
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════

--- Full cleanup of all explosion-related effects.
local function CleanupAll()
    -- Stop all looped particles
    for _, handle in ipairs(activeLoopedPtfx) do
        if DoesParticleFxLoopedExist(handle) then
            StopParticleFxLooped(handle, false)
            RemoveParticleFx(handle, false)
        end
    end
    activeLoopedPtfx = {}

    -- Remove fire zones
    for index, fireData in pairs(activeFireZones) do
        if fireData.zone then
            fireData.zone:remove()
        end

        if fireData.particles then
            for _, handle in ipairs(fireData.particles) do
                if DoesParticleFxLoopedExist(handle) then
                    StopParticleFxLooped(handle, false)
                    RemoveParticleFx(handle, false)
                end
            end
        end

        activeFireZones[index] = nil
    end

    -- Remove scorch zones
    for index, scorchData in pairs(activeScorchZones) do
        if scorchData.fires then
            for _, fireHandle in ipairs(scorchData.fires) do
                RemoveScriptFire(fireHandle)
            end
        end
        activeScorchZones[index] = nil
    end

    -- Stop screen effects
    AnimpostfxStop('DrugsMichaelAliensFight')

    activeExplosions = {}
    explosionSeqCounter = 0
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    CleanupAll()
end)

RegisterNetEvent('qbx_core:client:onLogout', function()
    CleanupAll()
end)
