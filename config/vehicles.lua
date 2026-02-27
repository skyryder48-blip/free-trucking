--[[
    config/vehicles.lua — Vehicle Class Mappings
    Free Trucking — QBX Framework

    Maps cargo vehicle_types (from config/cargo.lua) to GTA vehicle model names.
    Default entries use VANILLA GTA V vehicles. Server owners should add addon
    vehicle models at the marked locations.

    Also includes rental vehicle definitions with spawn coords and pricing,
    and vehicle class detection utility functions.
]]

Vehicles = {}

-- ─────────────────────────────────────────────
-- VEHICLE TYPE → MODEL MAPPINGS
-- ─────────────────────────────────────────────
-- Each vehicle_type key matches the values in CargoTypes[x].vehicle_types.
-- Models are arrays — load generation picks randomly from available models.
-- 'trailer' field indicates this is a tractor-trailer combo (Class A).

Vehicles.Types = {

    -- ── Tier 0 — No CDL ────────────────────
    van = {
        tier        = 0,
        label       = 'Cargo Van',
        class       = 'none',          -- no CDL required
        articulated = false,
        models      = {
            'rumpo',                    -- Bravado Rumpo
            'speedo',                   -- Vapid Speedo
            'youga',                    -- Bravado Youga
            -- ADD ADDON VEHICLES HERE
        },
    },

    sprinter = {
        tier        = 0,
        label       = 'Sprinter Van',
        class       = 'none',
        articulated = false,
        models      = {
            'speedo2',                  -- Vapid Speedo Custom
            -- ADD ADDON VEHICLES HERE
        },
    },

    pickup = {
        tier        = 0,
        label       = 'Pickup Truck',
        class       = 'none',
        articulated = false,
        models      = {
            'bison',                    -- Bravado Bison
            -- ADD ADDON VEHICLES HERE
        },
    },

    box_small = {
        tier        = 0,
        label       = 'Small Box Truck',
        class       = 'none',
        articulated = false,
        models      = {
            'boxville',                 -- Brute Boxville
            'boxville2',                -- Brute Boxville (variant)
            -- ADD ADDON VEHICLES HERE
        },
    },

    moto = {
        tier        = 0,
        label       = 'Motorcycle Courier',
        class       = 'none',
        articulated = false,
        courier_only = true,            -- only used for courier cargo type
        models      = {
            'pcj',                      -- Shitzu PCJ 600
            'sanchez',                  -- Maibatsu Sanchez
            -- ADD ADDON VEHICLES HERE
        },
    },

    -- ── Tier 1 — Class B CDL ───────────────
    benson = {
        tier        = 1,
        label       = 'Straight Truck',
        class       = 'class_b',
        articulated = false,
        models      = {
            'benson',                   -- Vapid Benson
            -- ADD ADDON VEHICLES HERE
        },
    },

    flatbed = {
        tier        = 1,
        label       = 'Flatbed Truck',
        class       = 'class_b',
        articulated = false,
        securing_required = true,       -- cargo securing interaction required
        models      = {
            'flatbed',                  -- MTL Flatbed
            -- ADD ADDON VEHICLES HERE
        },
    },

    tipper = {
        tier        = 1,
        label       = 'Tipper / Dump Truck',
        class       = 'class_b',
        articulated = false,
        models      = {
            'tipper',                   -- JoBuilt Tipper
            'tipper2',                  -- JoBuilt Tipper (large)
            -- ADD ADDON VEHICLES HERE
        },
    },

    -- ── Tier 2 — Class A CDL ───────────────
    class_a_reefer = {
        tier        = 2,
        label       = 'Refrigerated Semi',
        class       = 'class_a',
        articulated = true,
        reefer      = true,             -- reefer monitoring active
        tractor     = {
            models  = {
                'hauler',               -- JoBuilt Hauler
                -- ADD ADDON TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'trailers',             -- GTA trailer (reefer skin)
                -- ADD ADDON REEFER TRAILERS HERE
            },
        },
    },

    tanker_fuel = {
        tier        = 2,
        label       = 'Fuel Tanker',
        class       = 'class_a',
        articulated = true,
        tanker      = true,             -- tanker endorsement required
        flammable   = true,             -- explosion system registration
        tractor     = {
            models  = {
                'hauler',               -- JoBuilt Hauler
                -- ADD ADDON TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'tanker',               -- GTA Tanker trailer
                -- ADD ADDON TANKER TRAILERS HERE
            },
        },
    },

    livestock_trailer = {
        tier        = 2,
        label       = 'Livestock Hauler',
        class       = 'class_a',
        articulated = true,
        livestock   = true,             -- welfare monitoring active
        tractor     = {
            models  = {
                'hauler',               -- JoBuilt Hauler
                -- ADD ADDON TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'trailers2',            -- GTA trailer (livestock variant)
                -- ADD ADDON LIVESTOCK TRAILERS HERE
            },
        },
    },

    lowboy = {
        tier        = 2,
        label       = 'Lowboy / Step-Deck',
        class       = 'class_a',
        articulated = true,
        securing_required = true,       -- cargo securing + oversized zone override
        oversized   = true,
        tractor     = {
            models  = {
                'phantom',              -- Brute Phantom
                -- ADD ADDON TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'tr2',                  -- GTA trailer (flatbed/lowboy)
                -- ADD ADDON LOWBOY TRAILERS HERE
            },
        },
    },

    step_deck = {
        tier        = 2,
        label       = 'Step-Deck',
        class       = 'class_a',
        articulated = true,
        securing_required = true,
        oversized   = true,
        tractor     = {
            models  = {
                'phantom',              -- Brute Phantom
                -- ADD ADDON TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'tr2',                  -- GTA trailer (step-deck variant)
                -- ADD ADDON STEP-DECK TRAILERS HERE
            },
        },
    },

    -- ── Tier 3 — Class A + Endorsement ─────
    class_a_enclosed = {
        tier        = 3,
        label       = 'Enclosed Semi (High-Value)',
        class       = 'class_a',
        articulated = true,
        high_security = true,           -- seal required, high-value monitoring
        tractor     = {
            models  = {
                'phantom',              -- Brute Phantom
                -- ADD ADDON TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'trailers',             -- GTA trailer (enclosed)
                -- ADD ADDON ENCLOSED TRAILERS HERE
            },
        },
    },

    -- ── Hazmat Variants (Tier 3) ───────────
    hazmat_tanker = {
        tier        = 3,
        label       = 'Hazmat Tanker',
        class       = 'class_a',
        articulated = true,
        tanker      = true,
        hazmat      = true,             -- hazmat endorsement required
        tractor     = {
            models  = {
                'hauler',               -- JoBuilt Hauler
                -- ADD ADDON TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'tanker2',              -- GTA Tanker (variant)
                -- ADD ADDON HAZMAT TANKER TRAILERS HERE
            },
        },
    },

    hazmat_enclosed = {
        tier        = 3,
        label       = 'Hazmat Enclosed',
        class       = 'class_a',
        articulated = true,
        hazmat      = true,
        tractor     = {
            models  = {
                'phantom',              -- Brute Phantom
                -- ADD ADDON TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'trailers',             -- GTA trailer (hazmat-rated enclosed)
                -- ADD ADDON HAZMAT TRAILERS HERE
            },
        },
    },

    -- ── Military (Tier 3, Gov Clearance) ───
    military_transport = {
        tier        = 3,
        label       = 'Military Transport',
        class       = 'class_a',
        articulated = true,
        military    = true,             -- government clearance required
        tractor     = {
            models  = {
                'phantom',              -- Brute Phantom
                -- ADD ADDON MILITARY TRACTORS HERE
            },
        },
        trailer     = {
            models  = {
                'trailers',             -- GTA trailer (military secure)
                -- ADD ADDON MILITARY TRAILERS HERE
            },
        },
    },
}

-- ─────────────────────────────────────────────
-- RENTAL VEHICLES
-- ─────────────────────────────────────────────
-- Available at dispatch desks and truck stops.
-- Rental price is per-load (deducted on load acceptance, not returned).
-- Spawn coords are placeholder — set to your dispatch desk parking areas.

Vehicles.Rentals = {
    -- ── Tier 0 Rentals ─────────────────────
    {
        tier        = 0,
        model       = 'rumpo',
        label       = 'Bravado Rumpo (Rental)',
        price       = 200,              -- $200 per load
        spawnCoords = vector4(-16.3, -1441.0, 30.0, 180.0),   -- placeholder: Port of LS
        -- ADD ADDITIONAL SPAWN LOCATIONS HERE
    },
    {
        tier        = 0,
        model       = 'speedo',
        label       = 'Vapid Speedo (Rental)',
        price       = 200,
        spawnCoords = vector4(-16.3, -1445.0, 30.0, 180.0),   -- placeholder
    },
    {
        tier        = 0,
        model       = 'boxville',
        label       = 'Brute Boxville (Rental)',
        price       = 250,
        spawnCoords = vector4(-16.3, -1449.0, 30.0, 180.0),   -- placeholder
    },

    -- ── Tier 1 Rentals ─────────────────────
    {
        tier        = 1,
        model       = 'benson',
        label       = 'Vapid Benson (Rental)',
        price       = 500,              -- $500 per load
        spawnCoords = vector4(-20.0, -1441.0, 30.0, 180.0),   -- placeholder
        requires    = 'class_b',
    },
    {
        tier        = 1,
        model       = 'flatbed',
        label       = 'MTL Flatbed (Rental)',
        price       = 550,
        spawnCoords = vector4(-20.0, -1445.0, 30.0, 180.0),   -- placeholder
        requires    = 'class_b',
    },

    -- ── Tier 2 Rentals (tractor only — trailer spawns with load) ──
    {
        tier        = 2,
        model       = 'hauler',
        label       = 'JoBuilt Hauler (Rental)',
        price       = 1200,             -- $1,200 per load
        spawnCoords = vector4(-24.0, -1441.0, 30.0, 180.0),   -- placeholder
        requires    = 'class_a',
        isTractor   = true,             -- trailer spawns separately with load
    },

    -- ── Tier 3 Rentals (tractor only) ──────
    {
        tier        = 3,
        model       = 'phantom',
        label       = 'Brute Phantom (Rental)',
        price       = 2000,             -- $2,000 per load
        spawnCoords = vector4(-24.0, -1445.0, 30.0, 180.0),   -- placeholder
        requires    = 'class_a',
        isTractor   = true,
    },

    -- ADD ADDON RENTAL VEHICLES HERE
}

-- ─────────────────────────────────────────────
-- VEHICLE CLASS DETECTION FUNCTIONS
-- ─────────────────────────────────────────────

--- Build a reverse lookup table: model hash → vehicle type key
---@return table<number, string> hashToType
function Vehicles.BuildModelLookup()
    local lookup = {}
    for typeKey, typeDef in pairs(Vehicles.Types) do
        if typeDef.articulated then
            -- Register tractor models
            if typeDef.tractor and typeDef.tractor.models then
                for _, model in ipairs(typeDef.tractor.models) do
                    local hash = GetHashKey(model)
                    if not lookup[hash] then
                        lookup[hash] = {}
                    end
                    table.insert(lookup[hash], { type = typeKey, role = 'tractor' })
                end
            end
            -- Register trailer models
            if typeDef.trailer and typeDef.trailer.models then
                for _, model in ipairs(typeDef.trailer.models) do
                    local hash = GetHashKey(model)
                    if not lookup[hash] then
                        lookup[hash] = {}
                    end
                    table.insert(lookup[hash], { type = typeKey, role = 'trailer' })
                end
            end
        else
            -- Non-articulated: register main models
            if typeDef.models then
                for _, model in ipairs(typeDef.models) do
                    local hash = GetHashKey(model)
                    if not lookup[hash] then
                        lookup[hash] = {}
                    end
                    table.insert(lookup[hash], { type = typeKey, role = 'vehicle' })
                end
            end
        end
    end
    return lookup
end

--- Check if a vehicle model hash belongs to a specific vehicle type
---@param modelHash number Vehicle model hash
---@param vehicleType string Vehicle type key (e.g. 'van', 'class_a_reefer')
---@return boolean matches
function Vehicles.IsVehicleType(modelHash, vehicleType)
    local typeDef = Vehicles.Types[vehicleType]
    if not typeDef then return false end

    if typeDef.articulated then
        -- Check tractor models
        if typeDef.tractor and typeDef.tractor.models then
            for _, model in ipairs(typeDef.tractor.models) do
                if GetHashKey(model) == modelHash then return true end
            end
        end
        -- Check trailer models
        if typeDef.trailer and typeDef.trailer.models then
            for _, model in ipairs(typeDef.trailer.models) do
                if GetHashKey(model) == modelHash then return true end
            end
        end
    else
        if typeDef.models then
            for _, model in ipairs(typeDef.models) do
                if GetHashKey(model) == modelHash then return true end
            end
        end
    end

    return false
end

--- Check if a vehicle matches any of the allowed vehicle types for a cargo
---@param modelHash number Vehicle model hash
---@param allowedTypes string[] Array of vehicle type keys from cargo definition
---@return boolean matches
---@return string|nil matchedType The vehicle type that matched
function Vehicles.MatchesCargo(modelHash, allowedTypes)
    for _, vType in ipairs(allowedTypes) do
        if Vehicles.IsVehicleType(modelHash, vType) then
            return true, vType
        end
    end
    return false, nil
end

--- Get the tier for a vehicle by model hash
---@param modelHash number Vehicle model hash
---@return number|nil tier The tier (0-3) or nil if not a trucking vehicle
function Vehicles.GetVehicleTier(modelHash)
    for _, typeDef in pairs(Vehicles.Types) do
        if typeDef.articulated then
            if typeDef.tractor and typeDef.tractor.models then
                for _, model in ipairs(typeDef.tractor.models) do
                    if GetHashKey(model) == modelHash then return typeDef.tier end
                end
            end
        else
            if typeDef.models then
                for _, model in ipairs(typeDef.models) do
                    if GetHashKey(model) == modelHash then return typeDef.tier end
                end
            end
        end
    end
    return nil
end

--- Get the CDL class required for a vehicle type
---@param vehicleType string Vehicle type key
---@return string class 'none', 'class_b', or 'class_a'
function Vehicles.GetRequiredClass(vehicleType)
    local typeDef = Vehicles.Types[vehicleType]
    if not typeDef then return 'none' end
    return typeDef.class or 'none'
end

--- Check if a vehicle type requires a reefer unit
---@param vehicleType string Vehicle type key
---@return boolean hasReefer
function Vehicles.IsReefer(vehicleType)
    local typeDef = Vehicles.Types[vehicleType]
    return typeDef and typeDef.reefer == true
end

--- Check if a vehicle type is flammable (explosion system registration)
---@param vehicleType string Vehicle type key
---@return boolean isFlammable
function Vehicles.IsFlammable(vehicleType)
    local typeDef = Vehicles.Types[vehicleType]
    return typeDef and typeDef.flammable == true
end

--- Check if a vehicle type requires cargo securing
---@param vehicleType string Vehicle type key
---@return boolean requiresSecuring
function Vehicles.RequiresSecuring(vehicleType)
    local typeDef = Vehicles.Types[vehicleType]
    return typeDef and typeDef.securing_required == true
end

--- Check if a vehicle type is articulated (tractor-trailer)
---@param vehicleType string Vehicle type key
---@return boolean isArticulated
function Vehicles.IsArticulated(vehicleType)
    local typeDef = Vehicles.Types[vehicleType]
    return typeDef and typeDef.articulated == true
end

--- Check if vehicle is player-owned (not a rental)
--- Must be cross-referenced with the player's owned vehicles
---@param plate string Vehicle plate text
---@param citizenid string Player citizen ID
---@return boolean isOwned
function Vehicles.IsPlayerOwned(plate, citizenid)
    -- This queries the QBX vehicle ownership table
    -- Implementation depends on your framework's vehicle system
    local result = MySQL.single.await(
        'SELECT id FROM player_vehicles WHERE plate = ? AND citizenid = ?',
        { plate, citizenid }
    )
    return result ~= nil
end
