--[[
    config/explosions.lua — Explosion Profile Definitions
    Free Trucking — QBX Framework

    Defines multi-phase explosion sequences for cargo-aware vehicles.
    The enhanced explosion system intercepts native GTA explosions on
    registered flammable vehicles and replaces them with these profiles.

    Profiles are referenced by cargo definitions (config/cargo.lua)
    and registered via exports (see Section 25.3 of the dev guide).

    GTA V Explosion Types (native enum):
        0  = GRENADE             4  = MOLOTOV
        2  = EXPLOSION_SMALL     5  = GAS
        7  = CAR                 8  = PLANE
        10 = TRUCK               11 = TANKER
        16 = TRAIN               21 = DIR_FLAME
        27 = SMOKEGRENADELAUNCHER
        28 = SMOKEGRENADE        33 = BIRD_CRAP
        36 = BLIMP               38 = SUBMARINE_BIG
        70 = SCRIPT_MISSILE      82 = PROGRAMMABLEAR
]]

ExplosionProfiles = {}

-- ─────────────────────────────────────────────
-- FUEL TANKER — FULL (100% fill level)
-- ─────────────────────────────────────────────
-- Five-phase catastrophic explosion sequence.
-- Smoke column visible across the map. Devastating area denial.
-- The signature event of the trucking script.
ExplosionProfiles['fuel_tanker_full'] = {
    label           = 'Fuel Tanker Explosion (Full)',
    description     = 'Catastrophic multi-phase detonation of a fully loaded fuel tanker',
    scalable        = true,             -- phases scale with fill_level
    min_fill_level  = 0.10,             -- below 10% fill, use fuel_tanker_partial
    smoke_column    = true,             -- persistent smoke visible server-wide
    smoke_duration  = 600,              -- 10 minutes of smoke column
    dispatch_alert  = true,             -- fire police/fire dispatch
    dispatch_priority = 'critical',

    phases = {
        -- Phase 1: Initial Ignition
        -- The native vehicle explosion triggers. Fire starts.
        {
            name            = 'initial_ignition',
            delay           = 0,                    -- immediate (0 seconds)
            explosion_type  = 7,                    -- CAR explosion
            radius          = 5.0,                  -- base GTA explosion radius
            damage          = 200,                  -- base damage to entities
            camera_shake    = 0.3,                  -- subtle shake
            fire_trails     = 0,                    -- no extra fire yet
            sound           = 'EXPLOSION_STD',
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_grenade_smoke', scale = 2.0 },
            },
        },

        -- Phase 2: Tank Rupture
        -- Tank integrity fails. Fuel ignites. 3x blast radius.
        {
            name            = 'tank_rupture',
            delay           = 2000,                 -- +2 seconds
            explosion_type  = 11,                   -- TANKER explosion
            radius          = 15.0,                 -- 3x native radius
            damage          = 500,                  -- heavy damage
            camera_shake    = 0.8,                  -- strong shake
            vehicle_launch  = true,                 -- vehicles in radius get launched
            launch_force    = 25.0,                 -- upward force multiplier
            sound           = 'EXPLOSION_TANKER',
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_vehicle_lrg', scale = 3.0 },
                { type = 'ptfx', asset = 'core', name = 'exp_grd_flare', scale = 2.5 },
            },
        },

        -- Phase 3: Pressure Wave
        -- Concussive blast. No fire, just force. Max knockback.
        {
            name            = 'pressure_wave',
            delay           = 3000,                 -- +3 seconds
            explosion_type  = 82,                   -- PROGRAMMABLE_AR (concussive)
            radius          = 25.0,                 -- wide concussive area
            damage          = 100,                  -- moderate direct damage
            camera_shake    = 1.0,                  -- maximum shake
            knockback       = true,                 -- ragdoll all peds in radius
            knockback_force = 15.0,                 -- knockback force
            suppress_fire   = true,                 -- no fire from this phase
            sound           = 'EXPLOSION_LARGE',
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 4.0 },
                { type = 'shockwave', radius = 30.0, distortion = 0.8, duration = 500 },
            },
        },

        -- Phase 4: Fire Column
        -- Persistent fire zone. 180 seconds of active burning.
        -- This is the area-denial phase. No one drives through.
        {
            name            = 'fire_column',
            delay           = 4000,                 -- +4 seconds
            explosion_type  = 5,                    -- GAS explosion (fire-heavy)
            radius          = 20.0,                 -- fire zone radius
            damage          = 50,                   -- low explosion damage
            camera_shake    = 0.2,                  -- mild rumble
            persistent_fire = true,                 -- creates lasting fire zone
            fire_duration   = 180,                  -- 180 seconds (3 minutes)
            fire_density    = 12,                   -- number of fire points
            fire_spread     = 3.0,                  -- spread radius per fire point
            sound           = 'EXPLOSION_FIRE',
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_flare', scale = 5.0, looped = true, duration = 180000 },
                { type = 'fire_zone', radius = 20.0, duration = 180000 },
            },
        },

        -- Phase 5: Secondary Ignitions
        -- Chain explosions in the scorch zone. Delayed, random timing.
        -- Catches anyone who thought the fire was the end.
        {
            name            = 'secondary_ignitions',
            delay           = 5000,                 -- +5 seconds (start of window)
            delay_end       = 15000,                -- +15 seconds (end of window)
            explosion_type  = 2,                    -- EXPLOSION_SMALL
            radius          = 8.0,                  -- per-detonation radius
            damage          = 150,                  -- moderate damage
            camera_shake    = 0.4,
            chain_count     = { 3, 6 },             -- random 3-6 secondary explosions
            chain_interval  = { 1500, 3000 },       -- 1.5-3 seconds between chain blasts
            chain_radius    = 20.0,                 -- max distance from epicenter for chain spawns
            sound           = 'EXPLOSION_STD',
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_grenade_smoke', scale = 1.5 },
            },
        },
    },
}

-- ─────────────────────────────────────────────
-- FUEL TANKER — PARTIAL (scaled by fill level)
-- ─────────────────────────────────────────────
-- Same five-phase structure but all values scale linearly with fill_level.
-- A 30% full tanker produces 30% of the full sequence intensity.
-- Below 10% fill, only phases 1-2 fire (no pressure wave, no fire column).
ExplosionProfiles['fuel_tanker_partial'] = {
    label           = 'Fuel Tanker Explosion (Partial)',
    description     = 'Scaled explosion based on remaining fuel volume',
    scalable        = true,
    scale_factor    = 'fill_level',     -- multiply radius/damage/duration by fill_level
    smoke_column    = true,
    smoke_duration_base = 600,          -- scales with fill_level
    dispatch_alert  = true,
    dispatch_priority = 'high',

    phases = {
        -- Phase 1: Initial Ignition (always fires)
        {
            name            = 'initial_ignition',
            delay           = 0,
            explosion_type  = 7,                    -- CAR
            radius_base     = 5.0,                  -- scaled: radius = base * max(fill_level, 0.3)
            damage_base     = 200,
            camera_shake    = 0.3,
            always_fire     = true,                 -- fires regardless of fill level
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_grenade_smoke', scale = 2.0 },
            },
        },

        -- Phase 2: Tank Rupture (always fires, scaled)
        {
            name            = 'tank_rupture',
            delay           = 2000,
            explosion_type  = 11,                   -- TANKER
            radius_base     = 15.0,                 -- 15m * fill_level
            damage_base     = 500,
            camera_shake    = 0.8,
            vehicle_launch  = true,
            launch_force_base = 25.0,               -- scales with fill
            always_fire     = true,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_vehicle_lrg', scale = 3.0 },
            },
        },

        -- Phase 3: Pressure Wave (only if fill_level >= 0.3)
        {
            name            = 'pressure_wave',
            delay           = 3000,
            explosion_type  = 82,
            radius_base     = 25.0,
            damage_base     = 100,
            camera_shake    = 1.0,
            knockback       = true,
            knockback_force_base = 15.0,
            suppress_fire   = true,
            min_fill_level  = 0.30,                 -- requires 30%+ fill to trigger
            effects         = {
                { type = 'shockwave', radius_base = 30.0, distortion = 0.8, duration = 500 },
            },
        },

        -- Phase 4: Fire Column (only if fill_level >= 0.2)
        {
            name            = 'fire_column',
            delay           = 4000,
            explosion_type  = 5,                    -- GAS
            radius_base     = 20.0,
            damage_base     = 50,
            persistent_fire = true,
            fire_duration_base = 180,               -- 180 * fill_level seconds
            fire_density_base  = 12,                -- 12 * fill_level fire points
            min_fill_level  = 0.20,
            effects         = {
                { type = 'fire_zone', radius_base = 20.0, duration_base = 180000 },
            },
        },

        -- Phase 5: Secondary Ignitions (only if fill_level >= 0.4)
        {
            name            = 'secondary_ignitions',
            delay           = 5000,
            delay_end       = 15000,
            explosion_type  = 2,
            radius_base     = 8.0,
            damage_base     = 150,
            chain_count_base = { 3, 6 },            -- scaled by fill_level
            chain_interval  = { 1500, 3000 },
            chain_radius_base = 20.0,
            min_fill_level  = 0.40,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_grenade_smoke', scale = 1.5 },
            },
        },
    },
}

-- ─────────────────────────────────────────────
-- HAZMAT CLASS 3 — FLAMMABLE CHEMICAL
-- ─────────────────────────────────────────────
-- Similar to fuel but with toxic smoke component.
-- Fire burns differently — more smoke, less radiant heat.
-- Chemical fires are harder to extinguish.
ExplosionProfiles['hazmat_class3'] = {
    label           = 'Flammable Chemical Explosion (HAZMAT Class 3)',
    description     = 'Chemical fire with toxic smoke cloud and sustained burning',
    scalable        = false,
    smoke_column    = true,
    smoke_duration  = 300,              -- 5 minutes toxic smoke
    dispatch_alert  = true,
    dispatch_priority = 'critical',
    hazmat_class    = 3,

    phases = {
        -- Phase 1: Chemical Ignition
        {
            name            = 'chemical_ignition',
            delay           = 0,
            explosion_type  = 7,                    -- CAR
            radius          = 6.0,
            damage          = 250,
            camera_shake    = 0.4,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_grenade_smoke', scale = 2.5 },
                { type = 'ptfx', asset = 'core', name = 'exp_grd_flare', scale = 2.0 },
            },
        },

        -- Phase 2: Chemical Fire Spread
        {
            name            = 'fire_spread',
            delay           = 1500,
            explosion_type  = 5,                    -- GAS (fire-heavy)
            radius          = 12.0,
            damage          = 300,
            camera_shake    = 0.6,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_vehicle_lrg', scale = 2.0 },
            },
        },

        -- Phase 3: Toxic Smoke Cloud
        -- Continuous health drain for anyone in the cloud.
        {
            name            = 'toxic_smoke',
            delay           = 3000,
            explosion_type  = nil,                  -- no explosion, smoke only
            radius          = 18.0,
            damage          = 0,                    -- damage via DOT, not explosion
            camera_shake    = 0.1,
            hazard_zone     = true,
            hazard_type     = 'toxic_smoke',
            hazard_radius   = 18.0,
            hazard_duration = 240,                  -- 4 minutes of toxic smoke
            hazard_dot      = 5,                    -- damage per second to exposed players
            hazard_dot_interval = 1000,             -- tick every 1 second
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 6.0, looped = true, duration = 240000 },
                { type = 'screen_effect', name = 'DrugsMichaelAliensFight', duration = 240000 },
            },
        },

        -- Phase 4: Sustained Chemical Fire
        {
            name            = 'sustained_fire',
            delay           = 4000,
            explosion_type  = 5,                    -- GAS
            radius          = 15.0,
            damage          = 30,
            persistent_fire = true,
            fire_duration   = 240,                  -- 4 minutes — chemical fires burn longer
            fire_density    = 8,
            fire_spread     = 4.0,
            effects         = {
                { type = 'fire_zone', radius = 15.0, duration = 240000 },
            },
        },

        -- Phase 5: Secondary Chemical Reactions
        {
            name            = 'secondary_reactions',
            delay           = 8000,
            delay_end       = 20000,
            explosion_type  = 4,                    -- MOLOTOV (fireball)
            radius          = 6.0,
            damage          = 100,
            chain_count     = { 2, 4 },
            chain_interval  = { 2000, 4000 },
            chain_radius    = 15.0,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_flare', scale = 1.0 },
            },
        },
    },
}

-- ─────────────────────────────────────────────
-- HAZMAT CLASS 6 — TOXIC (Poison / Infectious)
-- ─────────────────────────────────────────────
-- No fire. Persistent toxic cloud with continuous health drain.
-- Visual: green/yellow haze. Requires hazmat_cleanup_kit.
ExplosionProfiles['hazmat_class6'] = {
    label           = 'Toxic Release (HAZMAT Class 6)',
    description     = 'Persistent toxic cloud causing continuous health damage',
    scalable        = false,
    smoke_column    = false,
    dispatch_alert  = true,
    dispatch_priority = 'critical',
    hazmat_class    = 6,
    cleanup_item    = 'hazmat_cleanup_kit',

    phases = {
        -- Phase 1: Container Breach
        -- Small pop as the container fails. Minimal explosion.
        {
            name            = 'container_breach',
            delay           = 0,
            explosion_type  = 2,                    -- EXPLOSION_SMALL
            radius          = 3.0,
            damage          = 50,
            camera_shake    = 0.2,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_grenade_smoke', scale = 1.0 },
            },
        },

        -- Phase 2: Initial Toxic Release
        -- Cloud begins forming. Immediate area becomes hazardous.
        {
            name            = 'initial_release',
            delay           = 1000,
            explosion_type  = nil,
            radius          = 10.0,
            damage          = 0,
            camera_shake    = 0.0,
            hazard_zone     = true,
            hazard_type     = 'toxic_cloud',
            hazard_radius   = 10.0,
            hazard_duration = 30,                   -- initial cloud: 30 seconds
            hazard_dot      = 8,                    -- 8 damage/sec — more lethal than smoke
            hazard_dot_interval = 1000,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 3.0, looped = true, duration = 30000, color = { r = 120, g = 200, b = 50 } },
                { type = 'screen_effect', name = 'DrugsMichaelAliensFight', duration = 30000 },
            },
        },

        -- Phase 3: Full Toxic Cloud
        -- Cloud expands to maximum radius. Persists until cleanup.
        {
            name            = 'full_cloud',
            delay           = 5000,
            explosion_type  = nil,
            radius          = 25.0,
            damage          = 0,
            hazard_zone     = true,
            hazard_type     = 'toxic_cloud',
            hazard_radius   = 25.0,
            hazard_duration = -1,                   -- persists until cleanup or restart
            hazard_dot      = 10,                   -- 10 damage/sec at full concentration
            hazard_dot_interval = 1000,
            hazard_vehicle_damage = 2,              -- damage to vehicle health per second
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 8.0, looped = true, duration = -1, color = { r = 100, g = 220, b = 40 } },
                { type = 'screen_effect', name = 'DrugsMichaelAliensFight', duration = -1 },
                { type = 'sound', name = 'TOXIC_HISS', looped = true },
            },
        },
    },
}

-- ─────────────────────────────────────────────
-- HAZMAT CLASS 7 — RADIOACTIVE
-- ─────────────────────────────────────────────
-- No fire or explosion. Radiation field with Geiger counter audio.
-- Wide DOT radius. Requires hazmat_cleanup_kit.
-- Most dangerous persistent hazard — lasts until cleanup.
ExplosionProfiles['hazmat_class7'] = {
    label           = 'Radiation Release (HAZMAT Class 7)',
    description     = 'Invisible radiation field with Geiger counter detection and persistent DOT',
    scalable        = false,
    smoke_column    = false,
    dispatch_alert  = true,
    dispatch_priority = 'critical',
    hazmat_class    = 7,
    cleanup_item    = 'hazmat_cleanup_kit',

    phases = {
        -- Phase 1: Containment Failure
        -- Nearly silent. Small puff of dust. The danger is invisible.
        {
            name            = 'containment_failure',
            delay           = 0,
            explosion_type  = 2,                    -- EXPLOSION_SMALL
            radius          = 2.0,                  -- tiny visual
            damage          = 25,                   -- minimal blast
            camera_shake    = 0.1,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_grenade_smoke', scale = 0.5 },
            },
        },

        -- Phase 2: Initial Radiation Field
        -- Geiger counter begins. Inner zone with high DOT.
        {
            name            = 'initial_radiation',
            delay           = 2000,
            explosion_type  = nil,
            radius          = 8.0,
            damage          = 0,
            hazard_zone     = true,
            hazard_type     = 'radiation',
            hazard_radius   = 8.0,
            hazard_duration = 60,                   -- expands to full after 60 seconds
            hazard_dot      = 15,                   -- 15 damage/sec — extremely lethal
            hazard_dot_interval = 1000,
            geiger_counter  = true,                 -- enable Geiger counter audio
            geiger_intensity = 0.8,                 -- high tick rate
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 1.0, looped = true, duration = 60000, color = { r = 200, g = 200, b = 50 }, opacity = 0.3 },
                { type = 'screen_effect', name = 'DrugsMichaelAliensFightIn', duration = -1 },
                { type = 'sound', name = 'GEIGER_COUNTER', looped = true },
            },
        },

        -- Phase 3: Full Radiation Field
        -- Maximum radius established. Persists until specialist cleanup.
        -- Geiger counter audible from approach distance.
        {
            name            = 'full_radiation',
            delay           = 60000,                -- +60 seconds (1 minute buildup)
            explosion_type  = nil,
            radius          = 35.0,                 -- wide radiation field
            damage          = 0,
            hazard_zone     = true,
            hazard_type     = 'radiation',
            hazard_radius   = 35.0,
            hazard_duration = -1,                   -- persists until cleanup
            hazard_dot      = 12,                   -- outer zone: 12 damage/sec
            hazard_dot_interval = 1000,
            hazard_inner_radius = 10.0,             -- inner zone radius
            hazard_inner_dot    = 25,               -- inner zone: 25 damage/sec (near-instant death)
            geiger_counter  = true,
            geiger_intensity = 1.0,
            geiger_approach_radius = 50.0,          -- Geiger clicks start at 50m
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 2.0, looped = true, duration = -1, color = { r = 180, g = 180, b = 40 }, opacity = 0.15 },
                { type = 'screen_effect', name = 'DrugsMichaelAliensFightIn', duration = -1, intensity = 0.5 },
                { type = 'sound', name = 'GEIGER_COUNTER', looped = true },
            },
        },
    },
}

-- ─────────────────────────────────────────────
-- HAZMAT CLASS 8 — CORROSIVE
-- ─────────────────────────────────────────────
-- Liquid spill that damages vehicle structure. Minor health DOT.
-- Vehicles driving through take suspension and body damage.
-- Requires hazmat_cleanup_kit.
ExplosionProfiles['hazmat_class8'] = {
    label           = 'Corrosive Spill (HAZMAT Class 8)',
    description     = 'Corrosive liquid spill causing vehicle structural damage and minor health DOT',
    scalable        = false,
    smoke_column    = false,
    dispatch_alert  = true,
    dispatch_priority = 'high',
    hazmat_class    = 8,
    cleanup_item    = 'hazmat_cleanup_kit',

    phases = {
        -- Phase 1: Container Rupture
        -- Pressurized container bursts. Small splash zone.
        {
            name            = 'container_rupture',
            delay           = 0,
            explosion_type  = 2,                    -- EXPLOSION_SMALL
            radius          = 4.0,
            damage          = 75,
            camera_shake    = 0.2,
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_grenade_smoke', scale = 1.5 },
                { type = 'ptfx', asset = 'core', name = 'ent_sht_water', scale = 3.0 },
            },
        },

        -- Phase 2: Corrosive Spread
        -- Liquid spreads across the road surface. Fumes begin.
        {
            name            = 'corrosive_spread',
            delay           = 2000,
            explosion_type  = nil,
            radius          = 12.0,
            damage          = 0,
            hazard_zone     = true,
            hazard_type     = 'corrosive',
            hazard_radius   = 12.0,
            hazard_duration = 120,                  -- 2 minutes initial spread
            hazard_dot      = 3,                    -- low player damage
            hazard_dot_interval = 2000,             -- tick every 2 seconds
            hazard_vehicle_damage = 8,              -- significant vehicle body damage per second
            hazard_tire_damage = true,              -- pops tires if driven through
            hazard_tire_damage_time = 5,            -- seconds of exposure before tire pops
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 2.0, looped = true, duration = 120000, color = { r = 200, g = 150, b = 50 }, opacity = 0.4 },
                { type = 'decal', name = 'corrosive_puddle', radius = 12.0, duration = -1 },
            },
        },

        -- Phase 3: Persistent Corrosive Zone
        -- Full spill established. Persists until cleanup.
        -- Vehicles corrode rapidly. Pedestrians take minor burns.
        {
            name            = 'persistent_zone',
            delay           = 10000,
            explosion_type  = nil,
            radius          = 18.0,
            damage          = 0,
            hazard_zone     = true,
            hazard_type     = 'corrosive',
            hazard_radius   = 18.0,
            hazard_duration = -1,                   -- persists until cleanup
            hazard_dot      = 5,                    -- moderate player damage
            hazard_dot_interval = 1500,
            hazard_vehicle_damage = 12,             -- heavy vehicle damage per second
            hazard_tire_damage = true,
            hazard_tire_damage_time = 3,            -- faster tire pop at full concentration
            hazard_grip_reduction = 0.3,            -- traction penalty (slippery surface)
            effects         = {
                { type = 'ptfx', asset = 'core', name = 'exp_grd_bzgas_smoke', scale = 3.0, looped = true, duration = -1, color = { r = 220, g = 160, b = 30 }, opacity = 0.3 },
                { type = 'decal', name = 'corrosive_puddle', radius = 18.0, duration = -1 },
                { type = 'sound', name = 'ACID_HISS', looped = true },
            },
        },
    },
}

-- ─────────────────────────────────────────────
-- UTILITY: Get profile by cargo type
-- ─────────────────────────────────────────────

--- Get the explosion profile for a given cargo type
---@param cargoType string The cargo type key from CargoTypes
---@param fillLevel number|nil Fill level (0.0-1.0) for tanker cargo, nil for others
---@return table|nil profile The explosion profile, or nil if none
function GetExplosionProfile(cargoType, fillLevel)
    -- Fuel tanker: select full or partial based on fill level
    if cargoType == 'fuel_tanker' then
        if fillLevel and fillLevel < 0.10 then
            return ExplosionProfiles['fuel_tanker_partial']
        elseif fillLevel and fillLevel < 1.0 then
            return ExplosionProfiles['fuel_tanker_partial']
        else
            return ExplosionProfiles['fuel_tanker_full']
        end
    end

    -- HAZMAT: map class to profile
    local hazmatClassMap = {
        ['hazmat']          = 'hazmat_class3',      -- default hazmat = flammable
        ['hazmat_class3']   = 'hazmat_class3',
        ['hazmat_class6']   = 'hazmat_class6',
        ['hazmat_class7']   = 'hazmat_class7',
        ['hazmat_class8']   = 'hazmat_class8',
    }

    local profileKey = hazmatClassMap[cargoType]
    if profileKey then
        return ExplosionProfiles[profileKey]
    end

    return nil
end

--- Scale a profile's phase values by fill level
---@param phase table A phase definition from a profile
---@param fillLevel number Fill level (0.0-1.0)
---@return table scaledPhase Copy of phase with scaled values
function ScalePhaseByFill(phase, fillLevel)
    local scaled = {}
    for k, v in pairs(phase) do
        if type(k) == 'string' and k:find('_base$') then
            local baseKey = k:gsub('_base$', '')
            if type(v) == 'number' then
                scaled[baseKey] = v * math.max(fillLevel, 0.1)
            elseif type(v) == 'table' then
                -- Scale table values (e.g. chain_count_base = {3, 6})
                scaled[baseKey] = {}
                for i, val in ipairs(v) do
                    scaled[baseKey][i] = math.floor(val * math.max(fillLevel, 0.1))
                end
            end
        else
            scaled[k] = v
        end
    end
    return scaled
end
