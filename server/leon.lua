--[[
    server/leon.lua — Leon Criminal Board Management
    Manages the criminal load board, supplier progression, fee payments,
    and Leon-specific delivery completion logic.

    Leon board: 5 loads per refresh, refreshes every 3 hours, all expire at 04:00.
    Leon does not deal in dairy — the milk rule.
    No BOL, no seal, no insurance, no GPS on Leon loads.
]]

--- In-memory Leon board state
---@type table[]
local LeonBoard = {}

--- Timestamp of last board refresh
---@type number
local LastLeonRefresh = 0

--- Leon board refresh interval in seconds (3 hours)
local LEON_REFRESH_INTERVAL = 10800

--- Max loads on Leon board per refresh
local LEON_BOARD_SIZE = 5

--- Registered external Leon load types (from other resources)
---@type table<string, table>
local ExternalLeonLoadTypes = {}

--- Supplier definitions matching Section 21.3
local LeonSuppliers = {
    southside_consolidated = {
        id          = 'southside_consolidated',
        label       = 'Southside Consolidated',
        region      = 'los_santos',
        rate_mult   = 1.15,
        risk_tier   = 'low',
        unlock_type = 'first_leon_load',
        unlock_req  = 1,
    },
    la_puerta_freight = {
        id          = 'la_puerta_freight',
        label       = 'La Puerta Freight Solutions',
        region      = 'los_santos',
        rate_mult   = 1.30,
        risk_tier   = 'medium',
        unlock_type = 'leon_loads_completed',
        unlock_req  = 3,
    },
    blaine_county_salvage = {
        id          = 'blaine_county_salvage',
        label       = 'Blaine County Salvage & Ag',
        region      = 'sandy_shores',
        rate_mult   = 1.45,
        risk_tier   = 'high',
        unlock_type = 'hazmat_endorsement',
        unlock_req  = 1,
    },
    paleto_cold_storage = {
        id          = 'paleto_cold_storage',
        label       = 'Paleto Bay Cold Storage',
        region      = 'paleto',
        rate_mult   = 1.50,
        risk_tier   = 'medium',
        unlock_type = 'cold_chain_rep',
        unlock_req  = 1,
    },
    pacific_bluffs_import = {
        id          = 'pacific_bluffs_import',
        label       = 'Pacific Bluffs Import/Export',
        region      = 'grapeseed',
        rate_mult   = 1.60,
        risk_tier   = 'critical',
        unlock_type = 'two_suppliers_done',
        unlock_req  = 2,
    },
}

--- Fee ranges by risk tier
local FeeRanges = {
    low         = { 300, 600 },
    medium      = { 500, 1000 },
    high        = { 800, 1500 },
    critical    = { 1200, 2500 },
}

--- Payout ranges by risk tier
local PayoutRanges = {
    low         = { 2000, 4000 },
    medium      = { 3500, 7000 },
    high        = { 6000, 12000 },
    critical    = { 10000, 20000 },
}

--- Dairy/milk cargo keywords — Leon's milk rule
local DAIRY_KEYWORDS = {
    'dairy', 'milk', 'cheese', 'butter', 'cream', 'yogurt', 'yoghurt',
    'ice_cream', 'whey', 'lactose', 'casein', 'curds',
}

--- Per-player supplier progression tracking (in-memory, synced from DB)
---@type table<string, table>
local SupplierProgression = {}

--- Check if a cargo type or description contains dairy references
---@param cargoType string The cargo type identifier
---@param cargoDesc string|nil Optional cargo description
---@return boolean isDairy True if the cargo involves dairy
local function IsDairyCargo(cargoType, cargoDesc)
    if not cargoType then return false end

    local lowerType = cargoType:lower()
    local lowerDesc = cargoDesc and cargoDesc:lower() or ''

    for i = 1, #DAIRY_KEYWORDS do
        local keyword = DAIRY_KEYWORDS[i]
        if lowerType:find(keyword, 1, true) or lowerDesc:find(keyword, 1, true) then
            return true
        end
    end

    return false
end

--- Generate a random integer within a range (inclusive)
---@param min number Minimum value
---@param max number Maximum value
---@return number result Random integer between min and max
local function RandomRange(min, max)
    return math.random(min, max)
end

--- Calculate the 04:00 server time expiry for Leon loads
---@return number timestamp Unix timestamp of next 04:00
local function GetLeonExpiry()
    local now = os.time()
    local date = os.date('*t', now)

    -- If current hour >= 4, expiry is tomorrow at 04:00
    -- If current hour < 4, expiry is today at 04:00
    if date.hour >= 4 then
        date.day = date.day + 1
    end
    date.hour = 4
    date.min = 0
    date.sec = 0

    return os.time(date)
end

--- Check if current server time is within Leon's operating hours (22:00-04:00)
---@return boolean active True if Leon is active
local function IsLeonActiveHours()
    local hour = tonumber(os.date('%H', os.time()))
    return hour >= 22 or hour < 4
end

--- Check if a player has Leon access unlocked
---@param citizenid string Player's citizen ID
---@return boolean unlocked True if player has Leon access
function CheckLeonAccess(citizenid)
    if not citizenid then return false end

    local driver = MySQL.single.await([[
        SELECT leon_access, leon_tier3_deliveries FROM truck_drivers
        WHERE citizenid = ?
    ]], { citizenid })

    if not driver then return false end

    -- Already flagged as having access
    if driver.leon_access then return true end

    -- Check if they meet the unlock threshold
    if driver.leon_tier3_deliveries >= (Config.LeonUnlockDeliveries or 1) then
        -- Grant access
        MySQL.update.await([[
            UPDATE truck_drivers SET leon_access = TRUE WHERE citizenid = ?
        ]], { citizenid })
        return true
    end

    return false
end

--- Load supplier progression data for a player from database
---@param citizenid string Player's citizen ID
---@return table progression Supplier progression data
local function LoadSupplierProgression(citizenid)
    if SupplierProgression[citizenid] then
        return SupplierProgression[citizenid]
    end

    -- Query leon-related delivery stats
    local driver = MySQL.single.await([[
        SELECT leon_total_loads, leon_tier3_deliveries FROM truck_drivers
        WHERE citizenid = ?
    ]], { citizenid })

    if not driver then
        SupplierProgression[citizenid] = { total_leon = 0, suppliers_completed = {} }
        return SupplierProgression[citizenid]
    end

    -- Check which suppliers have had deliveries
    local completedSuppliers = MySQL.query.await([[
        SELECT DISTINCT leon_supplier_id FROM truck_loads
        WHERE reserved_by = ? AND is_leon_load = TRUE AND board_status = 'completed'
          AND leon_supplier_id IS NOT NULL
    ]], { citizenid })

    local suppliersMap = {}
    if completedSuppliers then
        for i = 1, #completedSuppliers do
            suppliersMap[completedSuppliers[i].leon_supplier_id] = true
        end
    end

    -- Check for hazmat endorsement
    local hasHazmat = MySQL.single.await([[
        SELECT id FROM truck_licenses
        WHERE citizenid = ? AND license_type = 'hazmat' AND status = 'active'
    ]], { citizenid })

    -- Check for cold chain reputation (Tier 3 shipper rep with any cold chain shipper)
    local hasColdChainRep = MySQL.single.await([[
        SELECT id FROM truck_shipper_reputation
        WHERE citizenid = ? AND tier IN ('trusted', 'preferred')
    ]], { citizenid })

    SupplierProgression[citizenid] = {
        total_leon           = driver.leon_total_loads or 0,
        suppliers_completed  = suppliersMap,
        has_hazmat           = hasHazmat ~= nil,
        has_cold_chain_rep   = hasColdChainRep ~= nil,
    }

    return SupplierProgression[citizenid]
end

--- Check if a player has unlocked a specific supplier
---@param citizenid string Player's citizen ID
---@param supplierId string Supplier identifier
---@return boolean unlocked True if supplier is accessible
local function IsSupplierUnlocked(citizenid, supplierId)
    local supplier = LeonSuppliers[supplierId]
    if not supplier then return false end

    local prog = LoadSupplierProgression(citizenid)

    if supplier.unlock_type == 'first_leon_load' then
        return prog.total_leon >= supplier.unlock_req

    elseif supplier.unlock_type == 'leon_loads_completed' then
        return prog.total_leon >= supplier.unlock_req

    elseif supplier.unlock_type == 'hazmat_endorsement' then
        return prog.has_hazmat == true

    elseif supplier.unlock_type == 'cold_chain_rep' then
        return prog.has_cold_chain_rep == true

    elseif supplier.unlock_type == 'two_suppliers_done' then
        local count = 0
        for _ in pairs(prog.suppliers_completed) do
            count = count + 1
        end
        return count >= supplier.unlock_req
    end

    return false
end

--- Get list of eligible suppliers for a player
---@param citizenid string Player's citizen ID
---@return table[] suppliers List of available supplier definitions
local function GetAvailableSuppliers(citizenid)
    local available = {}
    for id, supplier in pairs(LeonSuppliers) do
        if IsSupplierUnlocked(citizenid, id) then
            available[#available + 1] = supplier
        end
    end

    -- Always include external load types (they define their own access)
    for id, loadType in pairs(ExternalLeonLoadTypes) do
        available[#available + 1] = {
            id          = loadType.supplier_id,
            label       = loadType.label,
            risk_tier   = loadType.risk_tier,
            is_external = true,
            fee_range   = loadType.fee_range,
            payout_range = loadType.payout_range,
            delivery_event = loadType.delivery_event,
        }
    end

    return available
end

--- Generate a single Leon load entry
---@param supplier table Supplier definition
---@return table|nil load The generated load, or nil if rejected (milk rule)
local function GenerateSingleLeonLoad(supplier)
    local riskTier = supplier.risk_tier or 'low'
    local feeRange = supplier.fee_range or FeeRanges[riskTier] or FeeRanges.low
    local payoutRange = supplier.payout_range or PayoutRanges[riskTier] or PayoutRanges.low

    local fee = RandomRange(feeRange[1], feeRange[2])
    local payout = RandomRange(payoutRange[1], payoutRange[2])

    -- Generate a vague cargo description for after fee payment
    local cargoDescriptions = {
        low = {
            'Unmarked boxes - light freight',
            'Wrapped pallets - general goods',
            'Sealed crates - miscellaneous',
            'Bagged materials - non-perishable',
        },
        medium = {
            'Temperature-sensitive containers',
            'Sealed drums - industrial',
            'Reinforced crates - handle with care',
            'Specialty goods - fragile',
        },
        high = {
            'Chemical containers - hazardous',
            'Pressurized tanks - volatile',
            'Industrial solvents - restricted',
            'Agricultural chemicals - controlled',
        },
        critical = {
            'Military-grade containers',
            'Restricted materials - classified',
            'High-value secured cargo',
            'Armored cases - do not inspect',
        },
    }

    local descPool = cargoDescriptions[riskTier] or cargoDescriptions.low
    local cargoDesc = descPool[math.random(#descPool)]

    -- Apply milk rule — reject dairy cargo
    if IsDairyCargo(cargoDesc, nil) then
        return nil
    end

    -- Generate random cargo type that is NOT dairy
    local cargoTypes = {
        'contraband_general', 'contraband_electronics', 'contraband_weapons_parts',
        'contraband_chemicals', 'contraband_pharmaceuticals', 'contraband_luxury',
        'diverted_freight', 'grey_market_goods', 'restricted_materials',
    }
    local cargoType = cargoTypes[math.random(#cargoTypes)]

    -- Final milk rule check on generated cargo type
    if IsDairyCargo(cargoType, cargoDesc) then
        return nil
    end

    local expiry = GetLeonExpiry()

    -- Generate a unique load ID
    local loadId = 'LEON-' .. os.time() .. '-' .. math.random(1000, 9999)

    return {
        load_id         = loadId,
        supplier_id     = supplier.id,
        supplier_label  = supplier.label or supplier.id,
        risk_tier       = riskTier,
        fee             = fee,
        payout          = payout,
        cargo_type      = cargoType,
        cargo_desc      = cargoDesc,
        region          = supplier.region or 'los_santos',
        rate_mult       = supplier.rate_mult or 1.0,
        expires_at      = expiry,
        posted_at       = os.time(),
        fee_paid        = false,
        accepted        = false,
        accepted_by     = nil,
        is_external     = supplier.is_external or false,
        delivery_event  = supplier.delivery_event or nil,
        -- Hidden until fee is paid:
        pickup_coords   = nil,
        delivery_coords = nil,
        pickup_label    = nil,
        delivery_label  = nil,
        window_minutes  = nil,
    }
end

--- Populate hidden load details (revealed after fee payment)
---@param load table The Leon load to populate
local function PopulateLoadDetails(load)
    -- Pickup and delivery coordinates by region
    -- These are placeholder coords — real implementation maps to config/leon.lua locations
    local pickupsByRegion = {
        los_santos = {
            { coords = vector3(76.0, -1945.0, 21.0),  label = 'South LS Industrial' },
            { coords = vector3(-1082.0, -1336.0, 5.0), label = 'Elysian Fields Docks' },
            { coords = vector3(1210.0, -3115.0, 5.5),  label = 'Terminal Yard' },
        },
        sandy_shores = {
            { coords = vector3(1395.0, 3608.0, 35.0), label = 'Desert Scrapyard' },
            { coords = vector3(2540.0, 4103.0, 38.0), label = 'Grand Senora Depot' },
        },
        paleto = {
            { coords = vector3(109.0, 6627.0, 31.7),  label = 'Paleto Bay Warehouse' },
            { coords = vector3(-125.0, 6397.0, 31.5),  label = 'Bay Cold Storage Unit' },
        },
        grapeseed = {
            { coords = vector3(2222.0, 5163.0, 57.7), label = 'Coastal Route Staging' },
            { coords = vector3(1700.0, 4790.0, 42.0), label = 'Grapeseed Outskirts' },
        },
    }

    local deliveryPoints = {
        { coords = vector3(-59.0, -1761.0, 29.0),     label = 'South Central Drop' },
        { coords = vector3(884.0, -2146.0, 32.0),     label = 'Cypress Flats Lot' },
        { coords = vector3(156.0, -3209.0, 5.9),      label = 'Terminal Island Contact' },
        { coords = vector3(1538.0, 3791.0, 34.0),     label = 'Sandy Shores Dropoff' },
        { coords = vector3(-279.0, 6286.0, 31.5),     label = 'Paleto Contact Point' },
        { coords = vector3(2697.0, 4324.0, 45.7),     label = 'Remote Meeting Point' },
    }

    local region = load.region or 'los_santos'
    local pickups = pickupsByRegion[region] or pickupsByRegion.los_santos
    local pickup = pickups[math.random(#pickups)]
    local delivery = deliveryPoints[math.random(#deliveryPoints)]

    load.pickup_coords   = pickup.coords
    load.pickup_label    = pickup.label
    load.delivery_coords = delivery.coords
    load.delivery_label  = delivery.label
    load.window_minutes  = RandomRange(25, 60)
end

--- Generate the full Leon board with 5 loads
---@param citizenid string|nil Optional citizenid to tailor supplier availability
---@return table[] board Array of Leon load entries
function GenerateLeonBoard(citizenid)
    -- Get all possible suppliers (if citizenid given, filter by progression)
    local allSuppliers = {}
    for _, supplier in pairs(LeonSuppliers) do
        allSuppliers[#allSuppliers + 1] = supplier
    end

    -- Include external load types
    for _, loadType in pairs(ExternalLeonLoadTypes) do
        allSuppliers[#allSuppliers + 1] = {
            id              = loadType.supplier_id,
            label           = loadType.label,
            risk_tier       = loadType.risk_tier,
            region          = 'los_santos',
            rate_mult       = 1.0,
            is_external     = true,
            fee_range       = loadType.fee_range,
            payout_range    = loadType.payout_range,
            delivery_event  = loadType.delivery_event,
        }
    end

    if #allSuppliers == 0 then
        print('[Trucking Leon] No suppliers available for board generation')
        return {}
    end

    local board = {}
    local attempts = 0
    local maxAttempts = LEON_BOARD_SIZE * 3 -- Account for milk rule rejections

    while #board < LEON_BOARD_SIZE and attempts < maxAttempts do
        attempts = attempts + 1
        local supplier = allSuppliers[math.random(#allSuppliers)]
        local load = GenerateSingleLeonLoad(supplier)

        if load then
            -- Pre-populate details (stored server-side, hidden from client)
            PopulateLoadDetails(load)
            board[#board + 1] = load
        end
    end

    LeonBoard = board
    LastLeonRefresh = os.time()

    -- Persist to database
    for i = 1, #board do
        local load = board[i]
        MySQL.insert([[
            INSERT INTO truck_loads
            (bol_number, tier, cargo_type, cargo_subtype, shipper_id, shipper_name,
             origin_region, origin_label, origin_coords, destination_label, destination_coords,
             distance_miles, weight_lbs, base_rate_per_mile, base_payout_rental,
             board_status, is_leon_load, leon_fee, leon_risk_tier, leon_supplier_id,
             posted_at, expires_at, board_region, requires_seal)
            VALUES (?, 3, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0,
                    'available', TRUE, ?, ?, ?, ?, ?, ?, FALSE)
        ]], {
            load.load_id,
            load.cargo_type,
            load.cargo_desc,
            load.supplier_id,
            load.supplier_label,
            load.region,
            load.pickup_label or 'Unknown',
            load.pickup_coords and json.encode({
                x = load.pickup_coords.x,
                y = load.pickup_coords.y,
                z = load.pickup_coords.z,
            }) or '{}',
            load.delivery_label or 'Unknown',
            load.delivery_coords and json.encode({
                x = load.delivery_coords.x,
                y = load.delivery_coords.y,
                z = load.delivery_coords.z,
            }) or '{}',
            load.fee,
            load.risk_tier,
            load.supplier_id,
            load.posted_at,
            load.expires_at,
            load.region,
        })
    end

    print(('[Trucking Leon] Board refreshed: %d loads generated'):format(#board))

    SendLeonWebhook('board_refresh', {
        load_count = #board,
    })

    return board
end

--- Get the current Leon board (public-facing, fee-gated data)
---@param citizenid string Player's citizen ID
---@return table[] board Board entries (risk tier + fee only for unpaid loads)
function GetLeonBoard(citizenid)
    if not citizenid then return {} end

    -- Check if board needs refresh
    local now = os.time()
    if now - LastLeonRefresh >= LEON_REFRESH_INTERVAL or #LeonBoard == 0 then
        GenerateLeonBoard(citizenid)
    end

    -- Filter expired loads
    local activeBoard = {}
    for i = 1, #LeonBoard do
        local load = LeonBoard[i]
        if load.expires_at > now and not load.accepted then
            -- Build the client-visible entry
            local entry = {
                load_id     = load.load_id,
                risk_tier   = load.risk_tier,
                fee         = load.fee,
                fee_paid    = load.fee_paid,
                supplier_id = load.supplier_id,
                supplier_label = load.supplier_label,
                expires_at  = load.expires_at,
            }

            -- Reveal details only if fee was paid
            if load.fee_paid then
                entry.pickup_label      = load.pickup_label
                entry.delivery_label    = load.delivery_label
                entry.cargo_desc        = load.cargo_desc
                entry.payout            = load.payout
                entry.window_minutes    = load.window_minutes
            end

            -- Check supplier accessibility for this player
            entry.supplier_unlocked = IsSupplierUnlocked(citizenid, load.supplier_id)

            activeBoard[#activeBoard + 1] = entry
        end
    end

    return activeBoard
end

--- Pay the fee to reveal Leon load details
---@param src number Player server ID
---@param loadId string Leon load identifier
---@return boolean success Whether the fee was successfully paid
---@return string|nil reason Failure reason if applicable
function PayLeonFee(src, loadId)
    if not src or not loadId then
        return false, 'invalid_params'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false, 'player_not_found' end

    local citizenid = player.PlayerData.citizenid

    -- Validate Leon access
    if not CheckLeonAccess(citizenid) then
        return false, 'leon_access_denied'
    end

    -- Validate Leon hours
    if not IsLeonActiveHours() then
        return false, 'leon_closed'
    end

    -- Find the load on the board
    local load = nil
    local loadIndex = nil
    for i = 1, #LeonBoard do
        if LeonBoard[i].load_id == loadId then
            load = LeonBoard[i]
            loadIndex = i
            break
        end
    end

    if not load then return false, 'load_not_found' end
    if load.fee_paid then return false, 'fee_already_paid' end
    if load.accepted then return false, 'load_already_accepted' end
    if load.expires_at <= os.time() then return false, 'load_expired' end

    -- Check supplier is unlocked for this player
    if not load.is_external and not IsSupplierUnlocked(citizenid, load.supplier_id) then
        return false, 'supplier_locked'
    end

    -- Deduct CASH (not bank) for Leon fee
    local cashBalance = player.PlayerData.money.cash or 0
    if cashBalance < load.fee then
        return false, 'insufficient_cash'
    end

    local removed = player.Functions.RemoveMoney('cash', load.fee, 'Leon info fee - ' .. loadId)
    if not removed then
        return false, 'payment_failed'
    end

    -- Mark fee as paid and reveal details
    LeonBoard[loadIndex].fee_paid = true

    -- Notify webhook
    SendLeonWebhook('fee_paid', {
        citizenid   = citizenid,
        supplier_id = load.supplier_id,
        risk_tier   = load.risk_tier,
        fee         = load.fee,
    })

    -- Return revealed details to the player
    local revealedData = {
        load_id         = load.load_id,
        pickup_label    = load.pickup_label,
        delivery_label  = load.delivery_label,
        cargo_desc      = load.cargo_desc,
        payout          = load.payout,
        window_minutes  = load.window_minutes,
        risk_tier       = load.risk_tier,
        supplier_label  = load.supplier_label,
    }

    lib.notify(src, {
        title       = 'Leon',
        description = ('Fee paid: $%d — load details revealed'):format(load.fee),
        type        = 'success',
    })

    return true, revealedData
end

--- Accept a Leon load after fee has been paid
---@param src number Player server ID
---@param loadId string Leon load identifier
---@return boolean success Whether the load was accepted
---@return string|nil reason Failure reason or active load data
function AcceptLeonLoad(src, loadId)
    if not src or not loadId then
        return false, 'invalid_params'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false, 'player_not_found' end

    local citizenid = player.PlayerData.citizenid

    -- Validate Leon access
    if not CheckLeonAccess(citizenid) then
        return false, 'leon_access_denied'
    end

    -- Find the load
    local load = nil
    local loadIndex = nil
    for i = 1, #LeonBoard do
        if LeonBoard[i].load_id == loadId then
            load = LeonBoard[i]
            loadIndex = i
            break
        end
    end

    if not load then return false, 'load_not_found' end
    if not load.fee_paid then return false, 'fee_not_paid' end
    if load.accepted then return false, 'load_already_accepted' end
    if load.expires_at <= os.time() then return false, 'load_expired' end

    -- Check player doesn't already have an active load
    local existingLoad = MySQL.single.await([[
        SELECT id FROM truck_active_loads WHERE citizenid = ?
    ]], { citizenid })

    if existingLoad then
        return false, 'active_load_exists'
    end

    -- Mark as accepted — NO BOL, NO seal, NO insurance
    LeonBoard[loadIndex].accepted = true
    LeonBoard[loadIndex].accepted_by = citizenid

    -- Update database status
    MySQL.update([[
        UPDATE truck_loads SET board_status = 'accepted', reserved_by = ?
        WHERE bol_number = ? AND is_leon_load = TRUE
    ]], { citizenid, loadId })

    -- Create active load entry (minimal — no BOL, no seal, no insurance)
    local activeLoadId = MySQL.insert.await([[
        INSERT INTO truck_active_loads
        (load_id, bol_id, citizenid, driver_id, status, cargo_integrity,
         seal_status, accepted_at, window_expires_at, estimated_payout)
        VALUES (
            (SELECT id FROM truck_loads WHERE bol_number = ? LIMIT 1),
            0, ?, 0, 'at_origin', 100, 'not_applied', ?, ?, ?
        )
    ]], {
        loadId,
        citizenid,
        os.time(),
        os.time() + (load.window_minutes * 60),
        load.payout,
    })

    -- Store active leon load in memory for tracking
    if ActiveLoads then
        ActiveLoads[activeLoadId] = {
            id              = activeLoadId,
            load_id         = loadId,
            citizenid       = citizenid,
            is_leon         = true,
            supplier_id     = load.supplier_id,
            pickup_coords   = load.pickup_coords,
            pickup_label    = load.pickup_label,
            delivery_coords = load.delivery_coords,
            delivery_label  = load.delivery_label,
            cargo_type      = load.cargo_type,
            cargo_desc      = load.cargo_desc,
            payout          = load.payout,
            risk_tier       = load.risk_tier,
            window_expires  = os.time() + (load.window_minutes * 60),
            accepted_at     = os.time(),
            status          = 'at_origin',
        }
    end

    SendLeonWebhook('load_accepted', {
        citizenid   = citizenid,
        supplier_id = load.supplier_id,
        risk_tier   = load.risk_tier,
    })

    lib.notify(src, {
        title       = 'Leon',
        description = 'Load accepted. No paperwork. Get moving.',
        type        = 'inform',
    })

    return true, {
        active_load_id  = activeLoadId,
        pickup_coords   = load.pickup_coords,
        pickup_label    = load.pickup_label,
        delivery_coords = load.delivery_coords,
        delivery_label  = load.delivery_label,
        window_minutes  = load.window_minutes,
        payout          = load.payout,
    }
end

--- Complete a Leon delivery and issue cash payout
---@param src number Player server ID
---@param loadId string|number Leon load or active load identifier
---@return boolean success Whether the delivery was completed
---@return number|nil payout The cash amount paid out
function CompleteLeonDelivery(src, loadId)
    if not src then return false, nil end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false, nil end

    local citizenid = player.PlayerData.citizenid

    -- Find the active Leon load
    local activeLoad = nil
    if ActiveLoads then
        for id, load in pairs(ActiveLoads) do
            if load.citizenid == citizenid and load.is_leon then
                activeLoad = load
                activeLoad.id = id
                break
            end
        end
    end

    if not activeLoad then
        -- Try looking up by loadId directly
        if ActiveLoads and ActiveLoads[loadId] then
            activeLoad = ActiveLoads[loadId]
            if activeLoad.citizenid ~= citizenid or not activeLoad.is_leon then
                return false, nil
            end
        end
    end

    if not activeLoad then return false, nil end

    local payout = activeLoad.payout or 0

    -- Pay in CASH (not bank)
    player.Functions.AddMoney('cash', payout, 'Leon delivery - ' .. tostring(activeLoad.load_id))

    -- Update driver stats
    MySQL.update([[
        UPDATE truck_drivers
        SET leon_total_loads = leon_total_loads + 1,
            total_loads_completed = total_loads_completed + 1,
            total_earnings = total_earnings + ?,
            last_seen = ?
        WHERE citizenid = ?
    ]], { payout, os.time(), citizenid })

    -- Update load status
    MySQL.update([[
        UPDATE truck_loads SET board_status = 'completed'
        WHERE bol_number = ? AND is_leon_load = TRUE
    ]], { activeLoad.load_id })

    -- Remove active load
    MySQL.update([[
        DELETE FROM truck_active_loads WHERE citizenid = ? AND status != 'completed'
    ]], { citizenid })

    -- Clean up in-memory state
    if ActiveLoads and activeLoad.id then
        ActiveLoads[activeLoad.id] = nil
    end

    -- Invalidate supplier progression cache
    SupplierProgression[citizenid] = nil

    -- Webhook notification
    SendLeonWebhook('delivery_complete', {
        citizenid   = citizenid,
        supplier_id = activeLoad.supplier_id,
        risk_tier   = activeLoad.risk_tier,
        payout      = payout,
    })

    lib.notify(src, {
        title       = 'Leon',
        description = ('Delivery complete. $%s cash.'):format(payout),
        type        = 'success',
    })

    return true, payout
end

--- Register an external Leon load type from another resource
---@param loadTypeData table Load type configuration
---@return boolean success Whether registration succeeded
function RegisterLeonLoadType(loadTypeData)
    if not loadTypeData then
        print('[Trucking Leon] RegisterLeonLoadType called with nil data')
        return false
    end

    if not loadTypeData.supplier_id then
        print('[Trucking Leon] RegisterLeonLoadType missing supplier_id')
        return false
    end

    -- Validate required fields
    local required = { 'supplier_id', 'label', 'risk_tier' }
    for i = 1, #required do
        if not loadTypeData[required[i]] then
            print(('[Trucking Leon] RegisterLeonLoadType missing required field: %s'):format(required[i]))
            return false
        end
    end

    -- Validate risk tier
    local validTiers = { low = true, medium = true, high = true, critical = true }
    if not validTiers[loadTypeData.risk_tier] then
        print(('[Trucking Leon] Invalid risk tier: %s'):format(tostring(loadTypeData.risk_tier)))
        return false
    end

    -- Apply milk rule check on label
    if IsDairyCargo(loadTypeData.label, loadTypeData.supplier_id) then
        print('[Trucking Leon] Rejected load type registration — milk rule violation')
        return false
    end

    -- Set defaults for optional fields
    loadTypeData.fee_range = loadTypeData.fee_range or FeeRanges[loadTypeData.risk_tier]
    loadTypeData.payout_range = loadTypeData.payout_range or PayoutRanges[loadTypeData.risk_tier]

    ExternalLeonLoadTypes[loadTypeData.supplier_id] = loadTypeData

    print(('[Trucking Leon] Registered external load type: %s (%s)')
        :format(loadTypeData.label, loadTypeData.supplier_id))

    return true
end

-- ─────────────────────────────────────────────
-- EVENT HANDLERS
-- ─────────────────────────────────────────────

--- Open Leon board
RegisterNetEvent('trucking:server:openLeonBoard', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid

    if not CheckLeonAccess(citizenid) then
        lib.notify(src, {
            title       = 'Leon',
            description = 'You don\'t have access to Leon\'s board.',
            type        = 'error',
        })
        return
    end

    if not IsLeonActiveHours() then
        lib.notify(src, {
            title       = 'Leon',
            description = 'Leon isn\'t around right now. Come back after 10 PM.',
            type        = 'error',
        })
        return
    end

    local board = GetLeonBoard(citizenid)

    TriggerClientEvent('trucking:client:showLeonBoard', src, board)
end)

--- Pay Leon fee event
RegisterNetEvent('trucking:server:payLeonFee', function(loadId)
    local src = source
    if not loadId then return end

    local success, result = PayLeonFee(src, loadId)

    if success then
        -- Refresh board view for the player
        local player = exports.qbx_core:GetPlayer(src)
        if player then
            local board = GetLeonBoard(player.PlayerData.citizenid)
            TriggerClientEvent('trucking:client:showLeonBoard', src, board)
        end
    else
        local errorMessages = {
            leon_access_denied  = 'You don\'t have access to Leon\'s board.',
            leon_closed         = 'Leon isn\'t around right now.',
            load_not_found      = 'That load is no longer available.',
            fee_already_paid    = 'Fee already paid for this load.',
            load_already_accepted = 'This load has already been taken.',
            load_expired        = 'This load has expired.',
            supplier_locked     = 'You haven\'t unlocked this supplier yet.',
            insufficient_cash   = 'Not enough cash. Leon deals in cash only.',
            payment_failed      = 'Payment failed. Try again.',
        }

        lib.notify(src, {
            title       = 'Leon',
            description = errorMessages[result] or 'Something went wrong.',
            type        = 'error',
        })
    end
end)

--- Accept Leon load event
RegisterNetEvent('trucking:server:acceptLeonLoad', function(loadId)
    local src = source
    if not loadId then return end

    local success, result = AcceptLeonLoad(src, loadId)

    if success and type(result) == 'table' then
        TriggerClientEvent('trucking:client:leonLoadAssigned', src, result)
    else
        local errorMessages = {
            leon_access_denied  = 'Access denied.',
            load_not_found      = 'Load no longer available.',
            fee_not_paid        = 'Pay the fee first.',
            load_already_accepted = 'Someone beat you to it.',
            load_expired        = 'Load expired.',
            active_load_exists  = 'Finish your current load first.',
        }

        lib.notify(src, {
            title       = 'Leon',
            description = errorMessages[result] or 'Could not accept load.',
            type        = 'error',
        })
    end
end)

--- Complete Leon delivery event
RegisterNetEvent('trucking:server:completeLeonDelivery', function(loadId)
    local src = source
    CompleteLeonDelivery(src, loadId)
end)

-- ─────────────────────────────────────────────
-- BOARD REFRESH THREAD
-- ─────────────────────────────────────────────

CreateThread(function()
    -- Initial board generation on resource start
    Wait(5000)
    if IsLeonActiveHours() then
        GenerateLeonBoard()
    end

    -- Periodic refresh check
    while true do
        Wait(60000) -- Check every minute

        local now = os.time()

        -- Expire the board at 04:00
        local hour = tonumber(os.date('%H', now))
        if hour == 4 and #LeonBoard > 0 then
            -- Expire all remaining Leon loads
            for i = 1, #LeonBoard do
                if not LeonBoard[i].accepted then
                    MySQL.update([[
                        UPDATE truck_loads SET board_status = 'expired'
                        WHERE bol_number = ? AND is_leon_load = TRUE
                    ]], { LeonBoard[i].load_id })
                end
            end
            LeonBoard = {}
            LastLeonRefresh = 0
            print('[Trucking Leon] Board expired at 04:00')
        end

        -- Refresh board if interval elapsed and within active hours
        if IsLeonActiveHours() and (now - LastLeonRefresh) >= LEON_REFRESH_INTERVAL then
            GenerateLeonBoard()
        end
    end
end)
