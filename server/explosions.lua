--[[
    server/explosions.lua — Enhanced Explosion System (Section 25)
    Tracks vehicles with active flammable cargo, intercepts native explosions,
    and replaces them with multi-phase sequences based on cargo profile.

    Features:
    - FlammableVehicles table: track registered vehicles by plate
    - 5-phase fuel tanker explosion sequence
    - Scale effects by fill_level
    - Fire column persistent zone (180 seconds)
    - Secondary ignition chain in scorch zone
    - HAZMAT class-specific profiles (class 3, 6, 7, 8)
    - Sync explosion events to all nearby clients
]]

--- In-memory registry of flammable vehicles indexed by plate
---@type table<string, table>
local FlammableVehicles = {}

--- Active explosion sequences being processed
---@type table<string, table>
local ActiveExplosions = {}

--- Fire column zones currently persisting
---@type table<string, table>
local ActiveFireZones = {}

--- Fire column duration in seconds
local FIRE_COLUMN_DURATION = 180

--- Client sync radius for explosion events (meters)
local EXPLOSION_SYNC_RADIUS = 500.0

--- Explosion profiles defined per cargo type
--- Profiles are referenced by name from config/explosions.lua or cargo definitions
local ExplosionProfiles = {
    --- Full fuel tanker explosion (5-phase sequence)
    fuel_tanker_full = {
        type = 'fuel_tanker',
        phases = {
            {
                name        = 'initial_ignition',
                delay       = 0,
                radius      = 8.0,
                damage      = 100,
                explosion_type = 'EXPLOSION_VEHICLE', -- FiveM native type
                knockback   = 1.0,
                fire        = true,
                camera_shake = 0.5,
            },
            {
                name        = 'tank_rupture',
                delay       = 2000, -- +2 seconds
                radius      = 24.0, -- 3x native
                damage      = 200,
                explosion_type = 'EXPLOSION_TANKER',
                knockback   = 3.0,
                fire        = true,
                vehicle_launch = true,
                camera_shake = 1.5,
            },
            {
                name        = 'pressure_wave',
                delay       = 3000, -- +3 seconds
                radius      = 40.0,
                damage      = 50,   -- Concussive only
                explosion_type = 'EXPLOSION_DIR_GAS_CANISTER',
                knockback   = 5.0,  -- Max knockback
                fire        = false,
                camera_shake = 2.0,
            },
            {
                name        = 'fire_column',
                delay       = 4000, -- +4 seconds
                radius      = 15.0,
                damage      = 80,
                explosion_type = 'EXPLOSION_FIRE',
                knockback   = 0.5,
                fire        = true,
                persistent  = true,
                persist_duration = FIRE_COLUMN_DURATION,
                camera_shake = 0.3,
            },
            {
                name        = 'secondary_ignitions',
                delay       = 5000, -- +5 to +15 seconds (randomized)
                delay_max   = 15000,
                radius      = 12.0,
                damage      = 60,
                explosion_type = 'EXPLOSION_PROPANE',
                knockback   = 1.5,
                fire        = true,
                chain       = true,
                chain_count = 3,     -- 3 secondary explosions
                chain_delay = 2000,  -- 2 seconds between chain blasts
                camera_shake = 0.8,
            },
        },
        scorch_radius = 30.0,
        smoke_visible_distance = 2000.0, -- Visible across the map
    },

    --- HAZMAT Class 3 — Flammable Liquids
    hazmat_class3 = {
        type = 'hazmat_fire',
        phases = {
            {
                name        = 'initial_fire',
                delay       = 0,
                radius      = 10.0,
                damage      = 80,
                explosion_type = 'EXPLOSION_TANKER',
                knockback   = 2.0,
                fire        = true,
                camera_shake = 1.0,
            },
            {
                name        = 'chemical_fire_spread',
                delay       = 2000,
                radius      = 20.0,
                damage      = 60,
                explosion_type = 'EXPLOSION_FIRE',
                knockback   = 1.0,
                fire        = true,
                persistent  = true,
                persist_duration = 120,
                camera_shake = 0.5,
            },
        },
        scorch_radius = 20.0,
    },

    --- HAZMAT Class 6 — Toxic Substances
    hazmat_class6 = {
        type = 'toxic_cloud',
        phases = {
            {
                name        = 'container_breach',
                delay       = 0,
                radius      = 6.0,
                damage      = 40,
                explosion_type = 'EXPLOSION_VEHICLE',
                knockback   = 1.0,
                fire        = false,
                camera_shake = 0.5,
            },
            {
                name        = 'toxic_dispersal',
                delay       = 1500,
                radius      = 25.0,
                damage      = 0,  -- Damage handled by zone effect
                explosion_type = 'EXPLOSION_SMOKEGRENADELAUNCHER',
                knockback   = 0,
                fire        = false,
                zone_effect = 'toxic',
                zone_radius = 25.0,
                zone_damage_per_tick = 5,
                zone_tick_interval = 2000, -- 2 seconds
                persistent  = true,
                persist_duration = 300, -- 5 minutes
                camera_shake = 0.2,
            },
        },
        scorch_radius = 0, -- No scorch, toxic zone instead
    },

    --- HAZMAT Class 7 — Radioactive Materials
    hazmat_class7 = {
        type = 'radiation',
        phases = {
            {
                name        = 'containment_failure',
                delay       = 0,
                radius      = 5.0,
                damage      = 30,
                explosion_type = 'EXPLOSION_VEHICLE',
                knockback   = 0.5,
                fire        = false,
                camera_shake = 0.3,
            },
            {
                name        = 'radiation_release',
                delay       = 2000,
                radius      = 35.0,
                damage      = 0,
                explosion_type = 'EXPLOSION_SMOKEGRENADELAUNCHER',
                knockback   = 0,
                fire        = false,
                zone_effect = 'radiation',
                zone_radius = 35.0,
                zone_damage_per_tick = 3,
                zone_tick_interval = 1500,
                persistent  = true,
                persist_duration = 600, -- 10 minutes
                geiger      = true,     -- Geiger counter sound
                camera_shake = 0.1,
            },
        },
        scorch_radius = 0,
    },

    --- HAZMAT Class 8 — Corrosive Substances
    hazmat_class8 = {
        type = 'corrosion',
        phases = {
            {
                name        = 'container_rupture',
                delay       = 0,
                radius      = 8.0,
                damage      = 50,
                explosion_type = 'EXPLOSION_VEHICLE',
                knockback   = 1.5,
                fire        = false,
                camera_shake = 0.6,
            },
            {
                name        = 'acid_spread',
                delay       = 1000,
                radius      = 18.0,
                damage      = 0,
                explosion_type = 'EXPLOSION_SMOKEGRENADELAUNCHER',
                knockback   = 0,
                fire        = false,
                zone_effect = 'corrosion',
                zone_radius = 18.0,
                zone_damage_per_tick = 0,  -- Damages vehicles, not players directly
                zone_vehicle_damage = 10,
                zone_tick_interval = 3000,
                persistent  = true,
                persist_duration = 240, -- 4 minutes
                camera_shake = 0.2,
            },
        },
        scorch_radius = 15.0,
    },
}

--- Scale explosion parameters based on fill level
---@param phase table The explosion phase definition
---@param fillLevel number Fill level between 0.0 and 1.0
---@return table scaledPhase The phase with scaled values
local function ScaleByFillLevel(phase, fillLevel)
    if not fillLevel or fillLevel <= 0 then
        fillLevel = 0.1 -- Minimum 10% effect even for nearly empty
    end

    local scaled = {}
    for k, v in pairs(phase) do
        scaled[k] = v
    end

    -- Scale radius, damage, and knockback by fill level
    scaled.radius = phase.radius * math.max(0.3, fillLevel)
    scaled.damage = math.floor(phase.damage * math.max(0.2, fillLevel))
    scaled.knockback = phase.knockback * math.max(0.3, fillLevel)

    -- Camera shake scales with fill level
    if phase.camera_shake then
        scaled.camera_shake = phase.camera_shake * math.max(0.4, fillLevel)
    end

    return scaled
end

--- Get all players within a radius of coordinates
---@param coords vector3 Center point
---@param radius number Radius in meters
---@return number[] players Array of server IDs
local function GetNearbyPlayers(coords, radius)
    local players = GetPlayers()
    local nearby = {}

    for i = 1, #players do
        local playerId = tonumber(players[i])
        if playerId then
            local ped = GetPlayerPed(playerId)
            if ped and ped > 0 then
                local playerCoords = GetEntityCoords(ped)
                if #(playerCoords - coords) <= radius then
                    nearby[#nearby + 1] = playerId
                end
            end
        end
    end

    return nearby
end

--- Register a vehicle as flammable for enhanced explosion tracking
---@param plate string Vehicle license plate
---@param data table Vehicle data { profile, fill_level, cargo_type, hazmat_class? }
---@return boolean success
function RegisterFlammableVehicle(plate, data)
    if not plate or plate == '' then
        print('[Trucking Explosions] RegisterFlammableVehicle called with empty plate')
        return false
    end

    if not data then
        print('[Trucking Explosions] RegisterFlammableVehicle called with nil data')
        return false
    end

    -- Validate profile exists
    local profile = data.profile or 'fuel_tanker_full'
    if not ExplosionProfiles[profile] then
        print(('[Trucking Explosions] Unknown explosion profile: %s, defaulting to fuel_tanker_full'):format(profile))
        profile = 'fuel_tanker_full'
    end

    local registrationData = {
        plate       = plate,
        profile     = profile,
        fill_level  = data.fill_level or 1.0,
        cargo_type  = data.cargo_type or 'unknown',
        hazmat_class = data.hazmat_class or nil,
        registered_at = GetServerTime(),
    }

    FlammableVehicles[plate] = registrationData

    print(('[Trucking Explosions] Registered flammable vehicle: %s (profile: %s, fill: %.0f%%)')
        :format(plate, profile, (registrationData.fill_level or 1.0) * 100))

    return true
end

--- Deregister a vehicle from flammable tracking
---@param plate string Vehicle license plate
---@return boolean success True if the vehicle was found and removed
function DeregisterFlammableVehicle(plate)
    if not plate or plate == '' then return false end

    if FlammableVehicles[plate] then
        FlammableVehicles[plate] = nil
        print(('[Trucking Explosions] Deregistered flammable vehicle: %s'):format(plate))
        return true
    end

    return false
end

--- Check if a vehicle is registered as flammable
---@param plate string Vehicle license plate
---@return boolean isFlammable
function IsFlammableVehicle(plate)
    if not plate or plate == '' then return false end
    return FlammableVehicles[plate] ~= nil
end

--- Get flammable vehicle data
---@param plate string Vehicle license plate
---@return table|nil data Vehicle data or nil if not registered
function GetFlammableVehicleData(plate)
    if not plate or plate == '' then return nil end
    return FlammableVehicles[plate]
end

--- Update the fill level of a registered flammable vehicle
---@param plate string Vehicle license plate
---@param fillLevel number New fill level (0.0 to 1.0)
function UpdateFillLevel(plate, fillLevel)
    if FlammableVehicles[plate] then
        FlammableVehicles[plate].fill_level = math.max(0, math.min(1.0, fillLevel))
    end
end

--- Execute a single explosion phase and sync to nearby clients
---@param phase table The explosion phase definition (already scaled)
---@param coords vector3 Explosion center coordinates
---@param plate string Vehicle plate (for tracking)
---@param sequenceId string Unique sequence identifier
local function ExecutePhase(phase, coords, plate, sequenceId)
    local nearbyPlayers = GetNearbyPlayers(coords, EXPLOSION_SYNC_RADIUS)

    -- Build the event payload for clients
    local phaseEvent = {
        sequence_id     = sequenceId,
        phase_name      = phase.name,
        coords          = { x = coords.x, y = coords.y, z = coords.z },
        radius          = phase.radius,
        damage          = phase.damage,
        explosion_type  = phase.explosion_type,
        knockback       = phase.knockback,
        fire            = phase.fire,
        vehicle_launch  = phase.vehicle_launch or false,
        camera_shake    = phase.camera_shake or 0,
        persistent      = phase.persistent or false,
        persist_duration = phase.persist_duration or 0,
        zone_effect     = phase.zone_effect or nil,
        zone_radius     = phase.zone_radius or nil,
        zone_damage_per_tick = phase.zone_damage_per_tick or nil,
        zone_vehicle_damage  = phase.zone_vehicle_damage or nil,
        zone_tick_interval   = phase.zone_tick_interval or nil,
        geiger          = phase.geiger or false,
    }

    -- Sync to all nearby players
    for i = 1, #nearbyPlayers do
        TriggerClientEvent('trucking:client:explosionPhase', nearbyPlayers[i], phaseEvent)
    end

    -- Set up persistent fire zone if needed
    if phase.persistent and phase.persist_duration and phase.persist_duration > 0 then
        local zoneId = sequenceId .. '_' .. phase.name
        ActiveFireZones[zoneId] = {
            coords          = coords,
            radius          = phase.radius,
            effect          = phase.zone_effect or 'fire',
            damage_per_tick = phase.zone_damage_per_tick or 0,
            vehicle_damage  = phase.zone_vehicle_damage or 0,
            tick_interval   = phase.zone_tick_interval or 2000,
            expires_at      = GetServerTime() + (phase.persist_duration),
            created_at      = GetServerTime(),
        }
    end
end

--- Handle a vehicle explosion by looking up its profile and triggering the sequence
---@param plate string Vehicle license plate
---@param coords vector3|nil Optional override coordinates (defaults to vehicle position)
---@return boolean handled True if an enhanced explosion was triggered
function HandleVehicleExplosion(plate, coords)
    if not plate or plate == '' then return false end

    local vehicleData = FlammableVehicles[plate]
    if not vehicleData then return false end

    local profile = ExplosionProfiles[vehicleData.profile]
    if not profile then
        print(('[Trucking Explosions] Profile not found for plate %s: %s'):format(plate, vehicleData.profile))
        return false
    end

    -- Prevent duplicate explosion sequences for the same vehicle
    if ActiveExplosions[plate] then
        print(('[Trucking Explosions] Explosion already active for plate: %s'):format(plate))
        return false
    end

    local fillLevel = vehicleData.fill_level or 1.0
    local sequenceId = plate .. '_' .. GetServerTime()

    -- Use provided coords or try to find the vehicle
    if not coords then
        -- Attempt to find vehicle entity by plate (may not always work server-side)
        coords = vector3(0, 0, 0)
        print('[Trucking Explosions] No coords provided for explosion — client should provide these')
    end

    ActiveExplosions[plate] = {
        sequence_id = sequenceId,
        profile     = vehicleData.profile,
        fill_level  = fillLevel,
        coords      = coords,
        started_at  = GetServerTime(),
        phases_completed = 0,
        total_phases = #profile.phases,
    }

    print(('[Trucking Explosions] Initiating %s explosion sequence for %s (fill: %.0f%%)')
        :format(vehicleData.profile, plate, fillLevel * 100))

    -- Execute each phase with timing
    CreateThread(function()
        for i = 1, #profile.phases do
            local phase = profile.phases[i]
            local scaledPhase = ScaleByFillLevel(phase, fillLevel)

            -- Calculate delay
            local delay = scaledPhase.delay or 0
            if scaledPhase.delay_max then
                delay = math.random(scaledPhase.delay, scaledPhase.delay_max)
            end

            if delay > 0 then
                Wait(delay)
            end

            -- Check if explosion was cancelled (vehicle deregistered during sequence)
            if not ActiveExplosions[plate] then
                print(('[Trucking Explosions] Sequence %s cancelled mid-phase'):format(sequenceId))
                return
            end

            -- Execute the phase
            ExecutePhase(scaledPhase, coords, plate, sequenceId)
            ActiveExplosions[plate].phases_completed = i

            -- Handle chain explosions (secondary ignitions)
            if scaledPhase.chain and scaledPhase.chain_count then
                for c = 1, scaledPhase.chain_count do
                    Wait(scaledPhase.chain_delay or 2000)

                    -- Randomize chain explosion position within scorch zone
                    local scorchRadius = profile.scorch_radius or 20.0
                    local offsetX = (math.random() * 2 - 1) * scorchRadius * 0.8
                    local offsetY = (math.random() * 2 - 1) * scorchRadius * 0.8
                    local chainCoords = vector3(
                        coords.x + offsetX,
                        coords.y + offsetY,
                        coords.z
                    )

                    local chainPhase = {
                        name            = 'chain_' .. c,
                        radius          = scaledPhase.radius * 0.6,
                        damage          = math.floor(scaledPhase.damage * 0.5),
                        explosion_type  = scaledPhase.explosion_type,
                        knockback       = scaledPhase.knockback * 0.4,
                        fire            = scaledPhase.fire,
                        camera_shake    = (scaledPhase.camera_shake or 0.5) * 0.3,
                    }

                    ExecutePhase(chainPhase, chainCoords, plate, sequenceId)
                end
            end
        end

        -- Sequence complete — clean up
        ActiveExplosions[plate] = nil
        DeregisterFlammableVehicle(plate)

        print(('[Trucking Explosions] Sequence %s completed for %s'):format(sequenceId, plate))
    end)

    return true
end

--- Get the appropriate HAZMAT explosion profile name for a given class
---@param hazmatClass number The HAZMAT class number
---@return string profileName The explosion profile key
function GetHazmatProfile(hazmatClass)
    local mapping = {
        [3] = 'hazmat_class3',
        [6] = 'hazmat_class6',
        [7] = 'hazmat_class7',
        [8] = 'hazmat_class8',
    }

    return mapping[hazmatClass] or 'fuel_tanker_full'
end

--- Get all currently active fire/hazard zones
---@return table<string, table> zones
function GetActiveFireZones()
    return ActiveFireZones
end

--- Get all registered flammable vehicles (for admin panel)
---@return table<string, table> vehicles
function GetAllFlammableVehicles()
    return FlammableVehicles
end

-- ─────────────────────────────────────────────
-- EVENT HANDLERS
-- ─────────────────────────────────────────────

--- Client reports a vehicle explosion for a flammable vehicle
RegisterNetEvent('trucking:server:vehicleExplosion', function(plate, coords)
    local src = source
    if not plate then return end

    -- Validate the plate is registered
    if not FlammableVehicles[plate] then return end

    -- Validate coordinates if provided
    local explosionCoords = coords
    if coords and type(coords) == 'table' then
        explosionCoords = vector3(coords.x or 0, coords.y or 0, coords.z or 0)
    elseif not coords then
        -- Try to get from player position as fallback
        local ped = GetPlayerPed(src)
        if ped then
            explosionCoords = GetEntityCoords(ped)
        end
    end

    HandleVehicleExplosion(plate, explosionCoords)
end)

--- Client requests current fire zones (on resource start or area enter)
RegisterNetEvent('trucking:server:requestFireZones', function()
    local src = source
    local ped = GetPlayerPed(src)
    if not ped then return end

    local playerCoords = GetEntityCoords(ped)
    local nearbyZones = {}

    for zoneId, zone in pairs(ActiveFireZones) do
        if zone.coords and #(playerCoords - zone.coords) <= EXPLOSION_SYNC_RADIUS then
            nearbyZones[zoneId] = zone
        end
    end

    if next(nearbyZones) then
        TriggerClientEvent('trucking:client:syncFireZones', src, nearbyZones)
    end
end)

--- Update fill level from drain mechanic
RegisterNetEvent('trucking:server:updateFillLevel', function(plate, fillLevel)
    local src = source
    if not plate or not fillLevel then return end

    -- Validate the player is near the vehicle they claim to be draining
    if not FlammableVehicles[plate] then return end

    UpdateFillLevel(plate, fillLevel)
end)

-- ─────────────────────────────────────────────
-- FIRE ZONE CLEANUP THREAD
-- ─────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(10000) -- Check every 10 seconds

        local now = GetServerTime()
        local expired = {}

        for zoneId, zone in pairs(ActiveFireZones) do
            if zone.expires_at and zone.expires_at <= now then
                expired[#expired + 1] = zoneId
            end
        end

        -- Remove expired zones and notify clients
        for i = 1, #expired do
            local zoneId = expired[i]
            local zone = ActiveFireZones[zoneId]

            if zone then
                -- Notify all nearby players to remove the zone
                local nearbyPlayers = GetNearbyPlayers(zone.coords, EXPLOSION_SYNC_RADIUS)
                for j = 1, #nearbyPlayers do
                    TriggerClientEvent('trucking:client:removeFireZone', nearbyPlayers[j], zoneId)
                end

                ActiveFireZones[zoneId] = nil
                print(('[Trucking Explosions] Fire zone expired: %s'):format(zoneId))
            end
        end
    end
end)

--- Zone damage tick thread — applies damage to entities in active zones
CreateThread(function()
    while true do
        Wait(1000) -- 1 second tick

        local now = GetServerTime()

        for zoneId, zone in pairs(ActiveFireZones) do
            if zone.coords and zone.effect and zone.effect ~= 'fire' then
                -- Toxic, radiation, and corrosion zones apply periodic effects
                -- The actual damage application is handled client-side via zone events
                -- Server just maintains authoritative zone state and broadcasts updates
                local nearbyPlayers = GetNearbyPlayers(zone.coords, zone.radius or 25.0)

                if #nearbyPlayers > 0 then
                    for i = 1, #nearbyPlayers do
                        TriggerClientEvent('trucking:client:hazardZoneTick', nearbyPlayers[i], {
                            zone_id     = zoneId,
                            effect      = zone.effect,
                            coords      = { x = zone.coords.x, y = zone.coords.y, z = zone.coords.z },
                            radius      = zone.radius,
                            damage      = zone.damage_per_tick or 0,
                            vehicle_damage = zone.vehicle_damage or 0,
                        })
                    end
                end
            end
        end
    end
end)
