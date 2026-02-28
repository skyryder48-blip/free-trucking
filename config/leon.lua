--[[
    config/leon.lua
    Criminal supplier definitions — Leon and his network.

    Leon is a night operator. He appears at his spot between 22:00 and 04:00 server time.
    He unlocks automatically after a driver completes their first Tier 3 delivery.
    No fanfare. He's just there one night. You either know, or you don't.

    Five suppliers, Chicago-flavored names for the map overlay:
        Los Santos = Chicago's south side and port districts
        Sandy Shores = Gary, IN industrial corridor
        Paleto Bay = Wisconsin cold storage operations
        Grapeseed = Western Michigan import/export

    Supplier progression is organic: first Leon load opens the low-risk supplier,
    then it scales with volume, endorsements, and completion history.
]]

LeonConfig = {}

-- ============================================================================
-- LEON NPC CONFIGURATION
-- ============================================================================

-- Leon's location: under the La Puerta Freeway overpass, south LS industrial.
-- Dark, accessible by truck, away from main foot traffic. A loading bay behind
-- the old warehouse where the freeway shadow covers everything after sundown.
LeonConfig.Location = {
    coords      = vector3(-467.08, -1714.28, 18.96),       -- Under freeway overpass, La Puerta / Davis industrial
    heading     = 142.0,
    model       = 's_m_m_trucker_01',                       -- Trucker ped — blends in
    scenario    = 'WORLD_HUMAN_SMOKING',                    -- Leaning against a wall, smoking
}

-- Leon's operating hours (server time, 24h format)
LeonConfig.Hours = {
    start   = 22,   -- 10:00 PM
    finish  = 4,    -- 4:00 AM
}

-- Leon's board settings
LeonConfig.Board = {
    loads_per_refresh   = 5,
    refresh_hours       = 3,            -- refreshes every 3 hours during operating window
    dawn_expire         = true,         -- all loads expire at 04:00 regardless of post time
}

-- Leon unlock requirement
-- Automatic after first Tier 3 delivery. Config.LeonUnlockDeliveries in config.lua
-- controls the threshold (default: 1).

-- ============================================================================
-- CRIMINAL SUPPLIERS
-- ============================================================================

LeonConfig.Suppliers = {}

-- ---------------------------------------------------------------------------
-- 1. SOUTHSIDE CONSOLIDATED
-- Low risk, low reward. The starter. South LS industrial — the kind of warehouse
-- where nobody asks questions because nobody asks questions.
-- ---------------------------------------------------------------------------
LeonConfig.Suppliers['southside_consolidated'] = {
    label               = 'Southside Consolidated',
    region              = 'los_santos',
    rate_multiplier     = 1.15,             -- 115% of base rate
    risk_tier           = 'low',
    unlock_requirement  = {
        type            = 'leon_loads',
        value           = 1,                -- Unlocks on first Leon load (accept any Leon job)
        description     = 'Complete your first Leon load',
    },
    coords              = vector3(763.44, -1827.52, 29.29),     -- Cypress Flats warehouse, south industrial LS
    heading             = 270.0,
    available_cargo_types = {
        'light_general_freight',
        'food_beverage_small',
        'retail_small',
        'courier',
        'general_freight_full',
        'food_beverage_full',
    },
    fee_range           = { min = 300, max = 600 },
    payout_range        = { min = 1500, max = 3500 },
    available_hours     = { start = 22, finish = 4 },
    -- NPC at supplier location
    npc = {
        model       = 's_m_y_dockwork_01',
        scenario    = 'WORLD_HUMAN_CLIPBOARD',
    },
}

-- ---------------------------------------------------------------------------
-- 2. LA PUERTA FREIGHT SOLUTIONS
-- Medium risk. Port-adjacent. Containers that fell off the manifest, goods
-- that never cleared customs, electronics that "arrived damaged."
-- ---------------------------------------------------------------------------
LeonConfig.Suppliers['la_puerta_freight'] = {
    label               = 'La Puerta Freight Solutions',
    region              = 'los_santos',
    rate_multiplier     = 1.30,             -- 130% of base rate
    risk_tier           = 'medium',
    unlock_requirement  = {
        type            = 'leon_loads',
        value           = 3,                -- 3 completed Leon loads
        description     = 'Complete 3 Leon loads',
    },
    coords              = vector3(-352.31, -2585.26, 6.00),    -- Elysian Island port area, container yard
    heading             = 180.0,
    available_cargo_types = {
        'general_freight_full',
        'building_materials',
        'retail_full',
        'high_value',
    },
    fee_range           = { min = 500, max = 1000 },
    payout_range        = { min = 3000, max = 7000 },
    available_hours     = { start = 22, finish = 4 },
    npc = {
        model       = 's_m_m_lathandy_01',
        scenario    = 'WORLD_HUMAN_SMOKING',
    },
}

-- ---------------------------------------------------------------------------
-- 3. BLAINE COUNTY SALVAGE & AG
-- High risk. Sandy Shores desert industrial. Chemicals, solvents, fuel —
-- things that are expensive to dispose of legally and profitable to move illegally.
-- Requires HAZMAT endorsement because even criminals don't want to melt.
-- ---------------------------------------------------------------------------
LeonConfig.Suppliers['blaine_salvage_ag'] = {
    label               = 'Blaine County Salvage & Ag',
    region              = 'sandy_shores',
    rate_multiplier     = 1.45,             -- 145% of base rate
    risk_tier           = 'high',
    unlock_requirement  = {
        type            = 'endorsement',
        value           = 'hazmat',         -- Requires HAZMAT endorsement
        description     = 'Hold an active HAZMAT endorsement',
    },
    coords              = vector3(2669.66, 3263.87, 55.24),    -- East Sandy Shores, industrial scrapyard area
    heading             = 340.0,
    available_cargo_types = {
        'fuel_tanker',
        'liquid_bulk_industrial',
        'hazmat',                            -- all hazmat subtypes
        'building_materials',
    },
    fee_range           = { min = 800, max = 1500 },
    payout_range        = { min = 5000, max = 12000 },
    available_hours     = { start = 22, finish = 4 },
    npc = {
        model       = 's_m_y_garbage',
        scenario    = 'WORLD_HUMAN_WELDING',
    },
}

-- ---------------------------------------------------------------------------
-- 4. PALETO BAY COLD STORAGE
-- Medium risk. Paleto Bay — pharmaceutical and cold-chain product that didn't
-- pass QA, expired stock rerouted for "secondary markets," biologics that
-- need to move before they lose viability.
-- Requires Tier 3 cold chain reputation (Bilkington carrier experience).
-- ---------------------------------------------------------------------------
LeonConfig.Suppliers['paleto_cold_storage'] = {
    label               = 'Paleto Bay Cold Storage',
    region              = 'paleto',
    rate_multiplier     = 1.50,             -- 150% of base rate
    risk_tier           = 'medium',
    unlock_requirement  = {
        type            = 'cold_chain_rep',
        value           = 'tier3',          -- Tier 3 cold chain shipper reputation
        description     = 'Achieve Tier 3 cold chain reputation',
    },
    coords              = vector3(-117.22, 6372.82, 31.49),    -- Paleto Bay, behind cold storage units near main road
    heading             = 225.0,
    available_cargo_types = {
        'cold_chain',
        'pharmaceutical',
        'pharmaceutical_biologic',
        'food_beverage_reefer',
    },
    fee_range           = { min = 1000, max = 2000 },
    payout_range        = { min = 6000, max = 15000 },
    available_hours     = { start = 22, finish = 4 },
    npc = {
        model       = 's_m_m_doctor_01',
        scenario    = 'WORLD_HUMAN_CLIPBOARD',
    },
}

-- ---------------------------------------------------------------------------
-- 5. PACIFIC BLUFFS IMPORT/EXPORT
-- Critical risk. Grapeseed coastal. High-value goods, electronics, luxury items
-- moved through Pacific Bluffs coastal route. The premium tier — highest
-- payout, highest exposure. You don't get here without proving yourself.
-- Requires 2 other Leon suppliers completed (any combination).
-- ---------------------------------------------------------------------------
LeonConfig.Suppliers['pacific_bluffs_ie'] = {
    label               = 'Pacific Bluffs Import/Export',
    region              = 'grapeseed',
    rate_multiplier     = 1.60,             -- 160% of base rate
    risk_tier           = 'critical',
    unlock_requirement  = {
        type            = 'suppliers_completed',
        value           = 2,                -- Must have completed loads from 2 other suppliers
        description     = 'Complete loads from 2 different Leon suppliers',
    },
    coords              = vector3(2490.64, 4966.27, 44.78),    -- East Grapeseed coast, near dock/warehouse area
    heading             = 135.0,
    available_cargo_types = {
        'high_value',
        'pharmaceutical',
        'pharmaceutical_biologic',
        'general_freight_full',
        'retail_full',
    },
    fee_range           = { min = 1500, max = 3000 },
    payout_range        = { min = 8000, max = 22000 },
    available_hours     = { start = 22, finish = 4 },
    npc = {
        model       = 'ig_claypain',
        scenario    = 'WORLD_HUMAN_STAND_IMPATIENT',
    },
}

-- ============================================================================
-- LEON DELIVERY DESTINATIONS
-- Criminal loads use separate destination pools from legitimate shippers.
-- These are back-alley drops, warehouse bays, container yards, and dark lots.
-- ============================================================================

LeonConfig.Destinations = {
    los_santos = {
        { label = 'Textile City Garage',                coords = vector3(718.32, -1066.75, 22.34) },
        { label = 'East Vinewood Lot',                  coords = vector3(1036.97, -2153.17, 30.90) },
        { label = 'Elysian Island Container Row',       coords = vector3(-178.61, -2658.05, 6.00) },
        { label = 'La Mesa Railyard',                   coords = vector3(903.27, -1046.54, 32.83) },
        { label = 'Davis Alley Drop',                   coords = vector3(106.49, -1960.52, 20.78) },
        { label = 'Rancho Storage Unit',                coords = vector3(463.25, -1893.87, 26.00) },
    },
    sandy_shores = {
        { label = 'Grand Senora Back Lot',              coords = vector3(2345.18, 3052.99, 48.15) },
        { label = 'Sandy Shores Airfield Hangar',       coords = vector3(1717.45, 3283.72, 41.22) },
        { label = 'Catfish View Shed',                  coords = vector3(1541.65, 3833.53, 34.46) },
        { label = 'Stab City Perimeter',                coords = vector3(68.79, 3704.18, 39.74) },
    },
    paleto = {
        { label = 'Paleto Bay Industrial Rear',         coords = vector3(91.38, 6397.31, 31.42) },
        { label = 'Cluckin\' Bell Farm Outbuilding',    coords = vector3(306.64, 6497.24, 29.85) },
        { label = 'Procopio Beach Parking',             coords = vector3(-363.23, 6185.71, 31.48) },
    },
    grapeseed = {
        { label = 'East Grapeseed Barn',                coords = vector3(2416.98, 4993.38, 46.29) },
        { label = 'Raton Canyon Trail End',             coords = vector3(-1124.41, 4907.22, 218.66) },
        { label = 'Mount Chiliad Staging Area',         coords = vector3(1608.88, 6422.39, 32.04) },
    },
}

-- ============================================================================
-- RISK TIER CONFIGURATION
-- Defines encounter probability and heat escalation per risk level.
-- ============================================================================

LeonConfig.RiskTiers = {
    low = {
        label               = 'Low Risk',
        police_encounter_pct = 5,           -- 5% chance of police encounter en route
        ambush_chance_pct    = 0,           -- no ambush at this tier
        wanted_level_cap     = 1,           -- max 1 star if detected
        heat_per_load        = 1,           -- heat accumulation (resets over time)
    },
    medium = {
        label               = 'Medium Risk',
        police_encounter_pct = 15,
        ambush_chance_pct    = 5,
        wanted_level_cap     = 2,
        heat_per_load        = 3,
    },
    high = {
        label               = 'High Risk',
        police_encounter_pct = 30,
        ambush_chance_pct    = 15,
        wanted_level_cap     = 3,
        heat_per_load        = 5,
    },
    critical = {
        label               = 'Critical Risk',
        police_encounter_pct = 50,
        ambush_chance_pct    = 30,
        wanted_level_cap     = 4,
        heat_per_load        = 8,
    },
}

-- Heat decays at a rate of 1 point per real hour. At 20+ heat, Leon warns you.
-- At 30+ heat, Leon refuses new loads until heat drops below 15.
LeonConfig.HeatDecayPerHour = 1
LeonConfig.HeatWarningThreshold = 20
LeonConfig.HeatLockoutThreshold = 30
LeonConfig.HeatLockoutClearAt   = 15

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--- Check if the current server time is within Leon's operating hours
---@return boolean
function IsLeonAvailable()
    local hour = tonumber(os.date('%H', GetServerTime()))
    if LeonConfig.Hours.start > LeonConfig.Hours.finish then
        -- Wraps midnight: e.g., 22:00 - 04:00
        return hour >= LeonConfig.Hours.start or hour < LeonConfig.Hours.finish
    else
        return hour >= LeonConfig.Hours.start and hour < LeonConfig.Hours.finish
    end
end

--- Get a supplier definition by ID
---@param supplierId string
---@return table|nil
function GetLeonSupplier(supplierId)
    return LeonConfig.Suppliers[supplierId]
end

--- Check if a player meets the unlock requirement for a supplier
---@param supplierId string
---@param playerData table  Player's trucking data (leon_total_loads, endorsements, etc.)
---@return boolean unlocked
---@return string|nil reason  Reason if locked
function CheckSupplierUnlock(supplierId, playerData)
    local supplier = LeonConfig.Suppliers[supplierId]
    if not supplier then return false, 'Supplier not found' end

    local req = supplier.unlock_requirement

    if req.type == 'leon_loads' then
        if (playerData.leon_total_loads or 0) >= req.value then
            return true, nil
        end
        return false, string.format('Need %d Leon loads (have %d)',
            req.value, playerData.leon_total_loads or 0)

    elseif req.type == 'endorsement' then
        if playerData.endorsements and playerData.endorsements[req.value] then
            return true, nil
        end
        return false, string.format('Need %s endorsement', req.value)

    elseif req.type == 'cold_chain_rep' then
        if playerData.cold_chain_tier and playerData.cold_chain_tier >= 3 then
            return true, nil
        end
        return false, 'Need Tier 3 cold chain reputation'

    elseif req.type == 'suppliers_completed' then
        local completedCount = 0
        if playerData.leon_suppliers_completed then
            for _, _ in pairs(playerData.leon_suppliers_completed) do
                completedCount = completedCount + 1
            end
        end
        if completedCount >= req.value then
            return true, nil
        end
        return false, string.format('Need %d suppliers completed (have %d)',
            req.value, completedCount)
    end

    return false, 'Unknown requirement type'
end

--- Get a random criminal delivery destination for a region
---@param region string
---@return table|nil {label, coords}
function GetLeonDestination(region)
    local pool = LeonConfig.Destinations[region]
    if not pool or #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

--- Get all suppliers unlocked for a given player
---@param playerData table
---@return table  { supplierId = supplierDef, ... }
function GetUnlockedSuppliers(playerData)
    local result = {}
    for id, supplier in pairs(LeonConfig.Suppliers) do
        local unlocked, _ = CheckSupplierUnlock(id, playerData)
        if unlocked then
            result[id] = supplier
        end
    end
    return result
end

--- Calculate Leon's fee for a load based on supplier and risk
---@param supplierId string
---@return number fee
function RollLeonFee(supplierId)
    local supplier = LeonConfig.Suppliers[supplierId]
    if not supplier then return 0 end
    return math.random(supplier.fee_range.min, supplier.fee_range.max)
end

--- Calculate Leon's payout for a load based on supplier
---@param supplierId string
---@return number payout
function RollLeonPayout(supplierId)
    local supplier = LeonConfig.Suppliers[supplierId]
    if not supplier then return 0 end
    return math.random(supplier.payout_range.min, supplier.payout_range.max)
end
