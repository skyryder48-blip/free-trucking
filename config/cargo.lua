--[[
    config/cargo.lua
    All cargo type definitions.

    Integrity profiles define damage per event type:
        forgiving   1-8% per event   (light goods, palletized)
        standard    3-15% per event  (general freight, moderate fragility)
        strict      5-25% per event  (pharmaceutical, high-value, fragile)
        liquid      2-12% per event  + liquid agitation mechanic

    Each cargo type defines:
        tier                    number      0-3
        rate_modifier_key       string      Key into Economy.CargoRateModifiers
        integrity_profile       string      forgiving | standard | strict | liquid
        temp_required           boolean     Whether temperature monitoring is required
        temp_min                number?     Minimum temp in Fahrenheit (nil if not required)
        temp_max                number?     Maximum temp in Fahrenheit (nil if not required)
        seal_required           boolean     Whether cargo seal is required
        vehicle_types           table       Allowed vehicle type keys
        weight_range            {min, max}  Weight in lbs
        reefer_required         boolean?    Requires reefer-equipped vehicle
        cert_required           string?     Required certification key
        endorsement_required    string?     Required endorsement (tanker, hazmat, oversized_monthly)
        tanker_required         boolean?    Requires tanker endorsement
        is_flammable            boolean?    Flammable cargo flag
        explosion_profile       string?     Key into config/explosions.lua
        drain_enabled           boolean?    Can be drained (tanker mechanic)
        drain_item              string?     Item produced on drain
        drain_container         string?     Container item required
        leon_available          boolean?    Can appear on Leon's board
        leon_supplier           string?     Default Leon supplier for this cargo type
        capacity_gallons        number?     Tanker capacity in gallons
        reefer_health_threshold number?     Minimum vehicle health % for reefer to function
]]

CargoTypes = {}

-- ============================================================================
-- INTEGRITY PROFILES
-- Defines damage percentage ranges per event type for each profile.
-- Used by the integrity system to calculate damage on collision, cargo shift, etc.
-- ============================================================================

IntegrityProfiles = {
    forgiving = {
        label       = 'Forgiving',
        description = 'Light goods, palletized. Low damage susceptibility.',
        events = {
            minor_collision     = { min = 1, max = 3 },     -- fender bender, low-speed
            major_collision     = { min = 3, max = 8 },     -- high-speed or rollover
            cargo_shift         = { min = 1, max = 4 },     -- straps loose, load shifts
            hard_braking        = { min = 1, max = 2 },     -- panic stop
            rough_terrain       = { min = 1, max = 2 },     -- offroad or pothole
            vehicle_flip        = { min = 4, max = 8 },     -- vehicle rolls
            water_exposure      = { min = 2, max = 5 },     -- rain or water crossing
            fire_proximity      = { min = 5, max = 8 },     -- near fire source
        },
    },
    standard = {
        label       = 'Standard',
        description = 'General freight. Moderate damage susceptibility.',
        events = {
            minor_collision     = { min = 3, max = 6 },
            major_collision     = { min = 8, max = 15 },
            cargo_shift         = { min = 3, max = 8 },
            hard_braking        = { min = 3, max = 5 },
            rough_terrain       = { min = 2, max = 5 },
            vehicle_flip        = { min = 10, max = 15 },
            water_exposure      = { min = 5, max = 10 },
            fire_proximity      = { min = 8, max = 15 },
        },
    },
    strict = {
        label       = 'Strict',
        description = 'Pharmaceutical, high-value, fragile. High damage susceptibility.',
        events = {
            minor_collision     = { min = 5, max = 10 },
            major_collision     = { min = 15, max = 25 },
            cargo_shift         = { min = 5, max = 12 },
            hard_braking        = { min = 5, max = 8 },
            rough_terrain       = { min = 5, max = 10 },
            vehicle_flip        = { min = 20, max = 25 },
            water_exposure      = { min = 8, max = 15 },
            fire_proximity      = { min = 15, max = 25 },
        },
    },
    liquid = {
        label       = 'Liquid',
        description = 'Tanker loads. Agitation mechanic applies on top of base damage.',
        events = {
            minor_collision     = { min = 2, max = 5 },
            major_collision     = { min = 8, max = 12 },
            cargo_shift         = { min = 2, max = 6 },     -- liquid slosh / agitation
            hard_braking        = { min = 3, max = 6 },     -- surge pressure
            rough_terrain       = { min = 2, max = 4 },
            vehicle_flip        = { min = 8, max = 12 },
            water_exposure      = { min = 1, max = 3 },     -- tanker is sealed
            fire_proximity      = { min = 5, max = 10 },
        },
        -- Liquid-specific: agitation builds over time with sharp turns and braking.
        -- Agitation level (0-100) adds a percentage modifier to all liquid damage events.
        agitation = {
            build_rate_turn     = 2,        -- per sharp turn event
            build_rate_brake    = 3,        -- per hard brake event
            decay_rate          = 1,        -- per 10 seconds of smooth driving
            max_agitation       = 100,
            damage_modifier_pct = 0.50,     -- at max agitation, +50% damage to liquid events
        },
    },
}

-- ============================================================================
-- TIER 0 — No CDL Required
-- Vans, sprinters, pickups. Light loads. Entry-level.
-- ============================================================================

CargoTypes['light_general_freight'] = {
    tier                    = 0,
    rate_modifier_key       = 'light_general_freight',
    integrity_profile       = 'forgiving',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = false,
    vehicle_types           = { 'van', 'sprinter', 'pickup', 'box_small' },
    weight_range            = { 500, 5000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'southside_consolidated',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['food_beverage_small'] = {
    tier                    = 0,
    rate_modifier_key       = 'food_beverage_small',
    integrity_profile       = 'forgiving',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = false,
    vehicle_types           = { 'van', 'sprinter' },
    weight_range            = { 300, 4000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'southside_consolidated',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['retail_small'] = {
    tier                    = 0,
    rate_modifier_key       = 'retail_small',
    integrity_profile       = 'forgiving',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = false,
    vehicle_types           = { 'van', 'sprinter' },
    weight_range            = { 200, 3500 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'southside_consolidated',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['courier'] = {
    tier                    = 0,
    rate_modifier_key       = 'courier',
    integrity_profile       = 'forgiving',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = false,
    vehicle_types           = { 'van', 'sprinter', 'motorcycle' },
    weight_range            = { 10, 500 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'southside_consolidated',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

-- ============================================================================
-- TIER 1 — Class B CDL
-- Bensons, flatbeds, box trucks. Full loads. Moderate skill.
-- ============================================================================

CargoTypes['general_freight_full'] = {
    tier                    = 1,
    rate_modifier_key       = 'general_freight_full',
    integrity_profile       = 'standard',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = true,
    vehicle_types           = { 'benson', 'flatbed', 'box_large' },
    weight_range            = { 5000, 26000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'southside_consolidated',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['building_materials'] = {
    tier                    = 1,
    rate_modifier_key       = 'building_materials',
    integrity_profile       = 'standard',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = false,
    vehicle_types           = { 'flatbed', 'tipper' },
    weight_range            = { 8000, 40000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'la_puerta_freight',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['food_beverage_full'] = {
    tier                    = 1,
    rate_modifier_key       = 'food_beverage_full',
    integrity_profile       = 'standard',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = true,
    vehicle_types           = { 'benson', 'benson_reefer' },
    weight_range            = { 5000, 20000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'southside_consolidated',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['food_beverage_reefer'] = {
    tier                    = 1,
    rate_modifier_key       = 'food_beverage_reefer',
    integrity_profile       = 'standard',
    temp_required           = true,
    temp_min                = 34,
    temp_max                = 40,
    seal_required           = true,
    vehicle_types           = { 'benson_reefer' },
    weight_range            = { 5000, 20000 },
    reefer_required         = true,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'paleto_cold_storage',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['retail_full'] = {
    tier                    = 1,
    rate_modifier_key       = 'retail_full',
    integrity_profile       = 'standard',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = true,
    vehicle_types           = { 'benson' },
    weight_range            = { 4000, 18000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'la_puerta_freight',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

-- ============================================================================
-- TIER 2 — Class A CDL
-- Class A rigs, tankers, livestock trailers, lowboys. Specialized.
-- ============================================================================

CargoTypes['cold_chain'] = {
    tier                    = 2,
    rate_modifier_key       = 'cold_chain',
    integrity_profile       = 'standard',
    temp_required           = true,
    temp_min                = 34,
    temp_max                = 40,
    seal_required           = true,
    vehicle_types           = { 'class_a_reefer' },
    weight_range            = { 10000, 44000 },
    reefer_required         = true,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'paleto_cold_storage',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['fuel_tanker'] = {
    tier                    = 2,
    rate_modifier_key       = 'fuel_tanker',
    integrity_profile       = 'liquid',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = true,
    vehicle_types           = { 'tanker_fuel' },
    weight_range            = { 35000, 80000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = 'tanker',
    tanker_required         = true,
    is_flammable            = true,
    explosion_profile       = 'fuel_tanker_full',
    drain_enabled           = true,
    drain_item              = 'stolen_fuel',
    drain_container         = 'fuel_drum',
    leon_available          = true,
    leon_supplier           = 'blaine_salvage_ag',
    capacity_gallons        = 9500,
    reefer_health_threshold = nil,
}

CargoTypes['liquid_bulk_food'] = {
    tier                    = 2,
    rate_modifier_key       = 'liquid_bulk_food',
    integrity_profile       = 'liquid',
    temp_required           = true,
    temp_min                = 34,
    temp_max                = 45,
    seal_required           = true,
    vehicle_types           = { 'tanker_food' },
    weight_range            = { 30000, 70000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = 'tanker',
    tanker_required         = true,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = true,
    drain_item              = 'food_grade_drum',
    drain_container         = 'food_grade_drum',
    leon_available          = true,
    leon_supplier           = nil,
    capacity_gallons        = 6500,
    reefer_health_threshold = nil,
}

CargoTypes['liquid_bulk_industrial'] = {
    tier                    = 2,
    rate_modifier_key       = 'liquid_bulk_industrial',
    integrity_profile       = 'liquid',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = true,
    vehicle_types           = { 'tanker_chemical' },
    weight_range            = { 30000, 75000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = 'tanker',
    tanker_required         = true,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = true,
    drain_item              = 'industrial_solvent',
    drain_container         = 'chemical_drum',
    leon_available          = true,
    leon_supplier           = 'blaine_salvage_ag',
    capacity_gallons        = 7000,
    reefer_health_threshold = nil,
}

CargoTypes['livestock'] = {
    tier                    = 2,
    rate_modifier_key       = 'livestock',
    integrity_profile       = 'standard',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = false,
    vehicle_types           = { 'livestock_trailer' },
    weight_range            = { 15000, 50000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = false,      -- livestock is live cargo, not fenceable
    leon_supplier           = nil,
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['oversized'] = {
    tier                    = 2,
    rate_modifier_key       = 'oversized',
    integrity_profile       = 'standard',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = false,
    vehicle_types           = { 'lowboy', 'step_deck' },
    weight_range            = { 20000, 60000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = 'oversized_monthly',
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = false,      -- oversized is too conspicuous for criminal work
    leon_supplier           = nil,
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['oversized_heavy'] = {
    tier                    = 2,
    rate_modifier_key       = 'oversized_heavy',
    integrity_profile       = 'standard',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = false,
    vehicle_types           = { 'lowboy' },
    weight_range            = { 40000, 80000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = 'oversized_monthly',
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = false,
    leon_supplier           = nil,
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

-- ============================================================================
-- TIER 3 — Class A + Endorsement / Certification
-- Highest-value, highest-risk loads. Full compliance required.
-- ============================================================================

CargoTypes['pharmaceutical'] = {
    tier                    = 3,
    rate_modifier_key       = 'pharmaceutical',
    integrity_profile       = 'strict',
    temp_required           = true,
    temp_min                = 36,
    temp_max                = 46,
    seal_required           = true,
    vehicle_types           = { 'class_a_reefer' },
    weight_range            = { 5000, 20000 },
    reefer_required         = true,
    cert_required           = 'bilkington_carrier',
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'paleto_cold_storage',
    capacity_gallons        = nil,
    reefer_health_threshold = 80,
}

CargoTypes['pharmaceutical_biologic'] = {
    tier                    = 3,
    rate_modifier_key       = 'pharmaceutical_biologic',
    integrity_profile       = 'strict',
    temp_required           = true,
    temp_min                = 35,
    temp_max                = 39,          -- tighter range for biologics
    seal_required           = true,
    vehicle_types           = { 'class_a_reefer' },
    weight_range            = { 2000, 12000 },
    reefer_required         = true,
    cert_required           = 'bilkington_carrier',
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'paleto_cold_storage',
    capacity_gallons        = nil,
    reefer_health_threshold = 80,
}

-- ---------------------------------------------------------------------------
-- HAZMAT — Subtypes per class
-- All hazmat requires Class A CDL + HAZMAT endorsement.
-- Each class has different risk profiles and explosion behavior.
-- ---------------------------------------------------------------------------

CargoTypes['hazmat'] = {
    -- Base hazmat definition (generic / Class 3 flammable liquid default)
    tier                    = 3,
    rate_modifier_key       = 'hazmat',
    integrity_profile       = 'liquid',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = true,
    vehicle_types           = { 'hazmat_tanker', 'hazmat_flatbed' },
    weight_range            = { 10000, 50000 },
    reefer_required         = false,
    cert_required           = nil,
    endorsement_required    = 'hazmat',
    tanker_required         = true,
    is_flammable            = true,
    explosion_profile       = 'hazmat_class3',
    drain_enabled           = true,
    drain_item              = 'hazmat_chemical',
    drain_container         = 'hazmat_drum',
    leon_available          = true,
    leon_supplier           = 'blaine_salvage_ag',
    capacity_gallons        = 5500,
    reefer_health_threshold = nil,
}

-- Hazmat subtypes — used when cargo_subtype is set on the load.
-- The base 'hazmat' type is used for shared fields. Subtypes override specific fields.

HazmatSubtypes = {}

HazmatSubtypes['class3'] = {
    label               = 'Class 3 — Flammable Liquid',
    hazmat_class        = 3,
    un_number_range     = { 'UN1203', 'UN1993', 'UN2398' },     -- gasoline, flammable liquid NOS, etc.
    placard             = 'FLAMMABLE',
    is_flammable        = true,
    explosion_profile   = 'hazmat_class3',
    integrity_profile   = 'liquid',
    spill_effect        = 'fire_risk',
    drain_enabled       = true,
    drain_item          = 'hazmat_flammable',
    drain_container     = 'hazmat_drum',
    capacity_gallons    = 5500,
}

HazmatSubtypes['class6'] = {
    label               = 'Class 6 — Toxic Substance',
    hazmat_class        = 6,
    un_number_range     = { 'UN2810', 'UN3288', 'UN1851' },     -- toxic solid NOS, etc.
    placard             = 'TOXIC',
    is_flammable        = false,
    explosion_profile   = 'hazmat_class6',
    integrity_profile   = 'strict',
    spill_effect        = 'toxic_zone',
    drain_enabled       = false,
    drain_item          = nil,
    drain_container     = nil,
    capacity_gallons    = nil,
}

HazmatSubtypes['class7'] = {
    label               = 'Class 7 — Radioactive Material',
    hazmat_class        = 7,
    un_number_range     = { 'UN2982', 'UN3321', 'UN2912' },     -- radioactive material, type B, LSA, etc.
    placard             = 'RADIOACTIVE',
    is_flammable        = false,
    explosion_profile   = 'hazmat_class7',
    integrity_profile   = 'strict',
    spill_effect        = 'radiation_field',
    drain_enabled       = false,
    drain_item          = nil,
    drain_container     = nil,
    capacity_gallons    = nil,
    -- Class 7 uses the elevated rate modifier from Economy.CargoRateModifiers
    rate_modifier_override = 'hazmat_class7',
}

HazmatSubtypes['class8'] = {
    label               = 'Class 8 — Corrosive Substance',
    hazmat_class        = 8,
    un_number_range     = { 'UN1789', 'UN1830', 'UN2796' },     -- hydrochloric acid, sulfuric acid, etc.
    placard             = 'CORROSIVE',
    is_flammable        = false,
    explosion_profile   = 'hazmat_class8',
    integrity_profile   = 'liquid',
    spill_effect        = 'corrosive_zone',
    drain_enabled       = true,
    drain_item          = 'hazmat_corrosive',
    drain_container     = 'hazmat_drum',
    capacity_gallons    = 4800,
}

CargoTypes['high_value'] = {
    tier                    = 3,
    rate_modifier_key       = 'high_value',
    integrity_profile       = 'strict',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = true,
    vehicle_types           = { 'class_a_enclosed' },
    weight_range            = { 5000, 25000 },
    reefer_required         = false,
    cert_required           = 'high_value',
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = nil,
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = true,
    leon_supplier           = 'pacific_bluffs_ie',
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

CargoTypes['military'] = {
    tier                    = 3,
    rate_modifier_key       = 'military',
    integrity_profile       = 'strict',
    temp_required           = false,
    temp_min                = nil,
    temp_max                = nil,
    seal_required           = true,
    vehicle_types           = { 'class_a_enclosed', 'military_flatbed' },
    weight_range            = { 10000, 45000 },
    reefer_required         = false,
    cert_required           = 'government_clearance',
    endorsement_required    = nil,
    tanker_required         = false,
    is_flammable            = false,
    explosion_profile       = 'military_ordnance',
    drain_enabled           = false,
    drain_item              = nil,
    drain_container         = nil,
    leon_available          = false,      -- military loads come through government contracts only
    leon_supplier           = nil,
    capacity_gallons        = nil,
    reefer_health_threshold = nil,
}

-- ============================================================================
-- CARGO HELPER FUNCTIONS
-- ============================================================================

--- Get a cargo type definition by key
---@param cargoKey string
---@return table|nil
function GetCargoType(cargoKey)
    return CargoTypes[cargoKey]
end

--- Get all cargo types for a specific tier
---@param tier number
---@return table
function GetCargoTypesByTier(tier)
    local result = {}
    for key, cargo in pairs(CargoTypes) do
        if cargo.tier == tier then
            result[key] = cargo
        end
    end
    return result
end

--- Get hazmat subtype overrides (merged with base hazmat)
---@param subtypeKey string  e.g. 'class3', 'class6', 'class7', 'class8'
---@return table|nil  Merged cargo definition with subtype overrides
function GetHazmatVariant(subtypeKey)
    local base = CargoTypes['hazmat']
    local subtype = HazmatSubtypes[subtypeKey]
    if not base or not subtype then return nil end

    -- Shallow merge: subtype overrides base
    local merged = {}
    for k, v in pairs(base) do
        merged[k] = v
    end
    for k, v in pairs(subtype) do
        merged[k] = v
    end

    -- If subtype has a rate modifier override, swap it in
    if subtype.rate_modifier_override then
        merged.rate_modifier_key = subtype.rate_modifier_override
    end

    return merged
end

--- Get the integrity profile definition for a cargo type
---@param cargoKey string
---@return table|nil
function GetIntegrityProfile(cargoKey)
    local cargo = CargoTypes[cargoKey]
    if not cargo then return nil end
    return IntegrityProfiles[cargo.integrity_profile]
end

--- Calculate damage for a specific event on a specific cargo type
---@param cargoKey string
---@param eventType string
---@return number  Damage percentage (0-25)
function RollIntegrityDamage(cargoKey, eventType)
    local profile = GetIntegrityProfile(cargoKey)
    if not profile then return 0 end

    local event = profile.events[eventType]
    if not event then return 0 end

    -- Random damage within the profile's range for this event type
    return math.random(event.min, event.max)
end

--- Get all cargo types available through Leon's network
---@return table
function GetLeonAvailableCargo()
    local result = {}
    for key, cargo in pairs(CargoTypes) do
        if cargo.leon_available then
            result[key] = cargo
        end
    end
    return result
end

--- Get all cargo types that require a specific endorsement
---@param endorsement string
---@return table
function GetCargoByEndorsement(endorsement)
    local result = {}
    for key, cargo in pairs(CargoTypes) do
        if cargo.endorsement_required == endorsement then
            result[key] = cargo
        end
    end
    return result
end

--- Get all cargo types that require a specific certification
---@param cert string
---@return table
function GetCargoByCert(cert)
    local result = {}
    for key, cargo in pairs(CargoTypes) do
        if cargo.cert_required == cert then
            result[key] = cargo
        end
    end
    return result
end

--- Check if a cargo type requires reefer equipment
---@param cargoKey string
---@return boolean
function IsReeferRequired(cargoKey)
    local cargo = CargoTypes[cargoKey]
    return cargo and cargo.reefer_required == true
end

--- Check if a cargo type is flammable
---@param cargoKey string
---@return boolean
function IsFlammable(cargoKey)
    local cargo = CargoTypes[cargoKey]
    return cargo and cargo.is_flammable == true
end

--- Check if a cargo type can be drained (tanker mechanic)
---@param cargoKey string
---@return boolean
function IsDrainable(cargoKey)
    local cargo = CargoTypes[cargoKey]
    return cargo and cargo.drain_enabled == true
end
