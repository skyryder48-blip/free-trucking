--[[
    server/loads.lua
    Load generation, board management, and surge detection.

    Responsibilities:
      - GenerateLoadsForRegion: creates loads per tier based on BoardConfig
      - RefreshBoard: expires old loads, generates new, updates board state, notifies players
      - Surge detection: checks open contract progress, robbery corridor, cold chain failures, etc.
      - Load detail assembly for NUI (combines load data with shipper/cargo metadata)
]]

-- ============================================================================
-- LOAD GENERATION
-- ============================================================================

--- Generate a set of loads for a given region based on BoardConfig composition.
--- Creates loads per tier, randomly selecting shippers, cargo, and destinations.
---@param region string  One of: 'los_santos', 'sandy_shores', 'paleto', 'grapeseed'
---@return number generatedCount  Total loads created
function GenerateLoadsForRegion(region)
    local loadCounts = BoardConfig.StandardLoads[region]
    if not loadCounts then
        print(('[trucking] WARNING: No board config for region: %s'):format(region))
        return 0
    end

    local generatedCount = 0
    local now = GetServerTime()
    local expirySeconds = BoardConfig.LoadExpirySeconds or 7200

    -- Fetch active surges for this region to apply to new loads
    local activeSurges = DB.GetActiveSurges(region)

    -- Generate loads for each tier
    for tier = 0, 3 do
        local count = loadCounts[tier] or 0
        for i = 1, count do
            local load = GenerateSingleLoad(region, tier, activeSurges, now, expirySeconds)
            if load then
                DB.InsertLoad(load)
                generatedCount = generatedCount + 1
            end
        end
    end

    return generatedCount
end

--- Generate a single load for a given region and tier.
--- Selects a random eligible shipper and cargo type, calculates distance, sets rates.
---@param region string
---@param tier number
---@param activeSurges table[]
---@param now number  Current unix timestamp
---@param expirySeconds number
---@return table|nil loadData
function GenerateSingleLoad(region, tier, activeSurges, now, expirySeconds)
    -- 1. Find eligible shippers for this region and tier
    local eligibleShippers = GetEligibleShippers(region, tier)
    if #eligibleShippers == 0 then
        print(('[trucking] No eligible shippers for region=%s tier=%d'):format(region, tier))
        return nil
    end

    -- 2. Select a random shipper
    local shipperEntry = eligibleShippers[math.random(#eligibleShippers)]
    local shipperId = shipperEntry.id
    local shipper = shipperEntry.data

    -- 3. Find eligible cargo types for this tier
    local eligibleCargo = GetEligibleCargoTypes(tier)
    if #eligibleCargo == 0 then
        print(('[trucking] No eligible cargo types for tier=%d'):format(tier))
        return nil
    end

    -- 4. Select a random cargo type
    local cargoEntry = eligibleCargo[math.random(#eligibleCargo)]
    local cargoType = cargoEntry.id
    local cargo = cargoEntry.data

    -- 5. Select a random destination (different region or same-region destination)
    local destination = SelectRandomDestination(region, shipperId)
    if not destination then
        print(('[trucking] No destination available for region=%s shipper=%s'):format(region, shipperId))
        return nil
    end

    -- 6. Calculate distance between origin and destination
    local originCoords = shipper.coords
    local destCoords = destination.coords
    local rawDistance = #(originCoords - destCoords)
    -- Convert GTA units to miles using map scale factor (1:3.5)
    local distanceMiles = math.floor((rawDistance / 1000) * 3.5 * 100) / 100
    -- Minimum 1 mile
    distanceMiles = math.max(distanceMiles, 1.0)

    -- 7. Calculate weight
    local weightRange = cargo.weight_range or { 500, 5000 }
    local weightLbs = math.random(weightRange[1], weightRange[2])

    -- 8. Calculate weight multiplier
    local weightMult = CalculateWeightMultiplier(weightLbs)

    -- 9. Calculate base rate per mile
    local baseRate = Economy.BaseRates[tier] or 25
    local cargoModifier = Economy.CargoRateModifiers[cargo.rate_modifier_key] or 1.0
    local baseRatePerMile = baseRate * cargoModifier

    -- 10. Calculate estimated payouts (rental vs owner-op)
    local baseAmount = baseRatePerMile * distanceMiles * weightMult
    local rentalPayout = math.floor(baseAmount)
    local ownerOpBonus = Economy.OwnerOpBonus[tier] or 0.20
    local ownerOpPayout = math.floor(baseAmount * (1 + ownerOpBonus))

    -- 11. Calculate deposit
    local depositAmount
    if tier == 0 then
        depositAmount = Config.DepositFlatT0 or 300
    else
        local depositRate = Config.DepositRates[tier] or 0.15
        depositAmount = math.floor(rentalPayout * depositRate)
        depositAmount = math.max(depositAmount, 100) -- minimum $100 deposit
    end

    -- 12. Check for active surges that apply to this load
    local surgeActive = false
    local surgePercentage = 0
    local surgeExpires = nil
    for _, surge in ipairs(activeSurges) do
        local matches = true
        if surge.cargo_type_filter and surge.cargo_type_filter ~= cargoType then
            matches = false
        end
        if surge.shipper_filter and surge.shipper_filter ~= shipperId then
            matches = false
        end
        if matches then
            surgeActive = true
            -- Use highest applicable surge
            if surge.surge_percentage > surgePercentage then
                surgePercentage = surge.surge_percentage
                surgeExpires = surge.expires_at
            end
        end
    end

    -- 13. Determine requirements from cargo definition
    local requiredLicense = 'none'
    if tier >= 2 then
        requiredLicense = 'class_a'
    elseif tier >= 1 then
        requiredLicense = 'class_b'
    end

    local requiredEndorsement = cargo.endorsement_required or nil
    local requiredCertification = cargo.cert_required or nil
    local requiresSeal = cargo.seal_required ~= false
    local requiredVehicleType = nil
    if cargo.vehicle_types and #cargo.vehicle_types > 0 then
        requiredVehicleType = cargo.vehicle_types[1] -- primary vehicle type
    end

    local minVehicleClass = 'none'
    if cargo.vehicle_types then
        for _, vt in ipairs(cargo.vehicle_types) do
            if vt:find('class_a') then minVehicleClass = 'class_a'; break end
            if vt:find('class_b') or vt:find('benson') or vt:find('flatbed') then
                minVehicleClass = 'class_b'
            end
        end
    end

    -- 14. Determine multi-stop (occasional for T1+ routes)
    local isMultiStop = false
    local stopCount = 1
    if tier >= 1 and math.random(100) <= 20 then -- 20% chance of multi-stop
        stopCount = math.random(2, math.min(tier + 2, 4))
        isMultiStop = stopCount > 1
    end

    -- 15. Generate BOL number for the load
    local bolNumber = GenerateBOLNumber()

    -- 16. Calculate delivery window (minutes per mile, scaled by tier)
    local windowMinutesPerMile = { [0] = 6, [1] = 5, [2] = 4.5, [3] = 4 }
    local baseWindowMinutes = (windowMinutesPerMile[tier] or 5) * distanceMiles
    if isMultiStop then
        baseWindowMinutes = baseWindowMinutes + (stopCount * 5) -- extra 5 min per stop
    end
    local windowSeconds = math.floor(baseWindowMinutes * 60)

    return {
        bol_number = bolNumber,
        tier = tier,
        cargo_type = cargoType,
        cargo_subtype = nil,
        shipper_id = shipperId,
        shipper_name = shipper.label,
        origin_region = region,
        origin_label = shipper.label,
        origin_coords = originCoords,
        destination_label = destination.label,
        destination_coords = destCoords,
        distance_miles = distanceMiles,
        weight_lbs = weightLbs,
        weight_multiplier = weightMult,
        temp_min_f = cargo.temp_required and cargo.temp_min or nil,
        temp_max_f = cargo.temp_required and cargo.temp_max or nil,
        hazmat_class = cargo.hazmat_class or nil,
        hazmat_un_number = cargo.hazmat_un_number or nil,
        requires_seal = requiresSeal,
        min_vehicle_class = minVehicleClass,
        required_vehicle_type = requiredVehicleType,
        required_license = requiredLicense,
        required_endorsement = requiredEndorsement,
        required_certification = requiredCertification,
        base_rate_per_mile = baseRatePerMile,
        base_payout_rental = rentalPayout,
        base_payout_owner_op = ownerOpPayout,
        deposit_amount = depositAmount,
        surge_active = surgeActive,
        surge_percentage = surgePercentage,
        surge_expires = surgeExpires,
        is_leon_load = false,
        leon_fee = nil,
        leon_risk_tier = nil,
        leon_supplier_id = nil,
        is_multi_stop = isMultiStop,
        stop_count = stopCount,
        posted_at = GetServerTime(),
        expires_at = GetServerTime() + (BoardConfig.LoadExpirySeconds or 7200),
        board_region = region,
        -- Delivery window stored for use at acceptance time
        _window_seconds = windowSeconds,
    }
end

-- ============================================================================
-- HELPER: Get eligible shippers for a region and tier
-- ============================================================================

---@param region string
---@param tier number
---@return table[] Array of { id = shipperId, data = shipperTable }
function GetEligibleShippers(region, tier)
    local result = {}
    if not Shippers then return result end

    for shipperId, shipper in pairs(Shippers) do
        if shipper.region == region then
            local minTier = shipper.tier_range and shipper.tier_range[1] or 0
            local maxTier = shipper.tier_range and shipper.tier_range[2] or 3
            if tier >= minTier and tier <= maxTier then
                result[#result + 1] = { id = shipperId, data = shipper }
            end
        end
    end

    return result
end

-- ============================================================================
-- HELPER: Get eligible cargo types for a tier
-- ============================================================================

---@param tier number
---@return table[] Array of { id = cargoType, data = cargoTable }
function GetEligibleCargoTypes(tier)
    local result = {}
    if not CargoTypes then return result end

    for cargoType, cargo in pairs(CargoTypes) do
        if cargo.tier == tier then
            result[#result + 1] = { id = cargoType, data = cargo }
        end
    end

    return result
end

-- ============================================================================
-- HELPER: Select a random destination
-- Uses other shippers or predefined delivery points as destinations
-- ============================================================================

--- Predefined delivery destinations across regions
local DeliveryDestinations = {
    los_santos = {
        { label = 'LS Industrial District',    coords = vector3(760.0, -820.0, 26.0) },
        { label = 'Elysian Island Warehouse',  coords = vector3(-380.0, -2640.0, 6.0) },
        { label = 'LSIA Cargo Terminal',       coords = vector3(-1088.0, -2908.0, 14.0) },
        { label = 'Davis Distribution Center', coords = vector3(139.0, -1780.0, 29.0) },
        { label = 'Cypress Flats Loading',     coords = vector3(812.0, -2150.0, 29.0) },
    },
    sandy_shores = {
        { label = 'Sandy Shores Airfield',     coords = vector3(1710.0, 3260.0, 41.0) },
        { label = 'Alamo Industrial',          coords = vector3(1105.0, 3100.0, 39.0) },
        { label = 'Harmony Truck Stop',        coords = vector3(1200.0, 2650.0, 38.0) },
    },
    paleto = {
        { label = 'Paleto Bay Lumber Mill',    coords = vector3(-372.0, 6194.0, 31.0) },
        { label = 'Paleto Industrial',         coords = vector3(118.0, 6622.0, 32.0) },
        { label = 'Mt. Chiliad Rest Area',     coords = vector3(425.0, 5614.0, 786.0) },
    },
    grapeseed = {
        { label = 'Grapeseed Grain Elevator',  coords = vector3(1700.0, 4790.0, 42.0) },
        { label = 'Grapeseed Cold Storage',    coords = vector3(2007.0, 4973.0, 41.0) },
        { label = 'McKenzie Field Hangar',     coords = vector3(2130.0, 4790.0, 41.0) },
    },
}

---@param originRegion string
---@param shipperId string
---@return table|nil  { label, coords }
function SelectRandomDestination(originRegion, shipperId)
    -- Build a pool from all regions (including cross-region deliveries)
    local pool = {}

    for region, destinations in pairs(DeliveryDestinations) do
        for _, dest in ipairs(destinations) do
            pool[#pool + 1] = dest
        end
    end

    -- Also include other shippers as potential destinations
    if Shippers then
        for sid, shipper in pairs(Shippers) do
            if sid ~= shipperId then
                pool[#pool + 1] = { label = shipper.label, coords = shipper.coords }
            end
        end
    end

    if #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

-- ============================================================================
-- HELPER: Calculate weight multiplier from Economy config
-- ============================================================================

---@param weightLbs number
---@return number multiplier
function CalculateWeightMultiplier(weightLbs)
    if not Economy or not Economy.WeightMultipliers then return 1.0 end

    for _, bracket in ipairs(Economy.WeightMultipliers) do
        if weightLbs <= bracket.max then
            return bracket.multiplier
        end
    end

    -- Above all brackets, use the highest
    return Economy.WeightMultipliers[#Economy.WeightMultipliers].multiplier
end

-- ============================================================================
-- BOARD REFRESH
-- Called by the staggered timer in main.lua. Expires old loads, generates
-- new ones, updates board state, and notifies connected players.
-- ============================================================================

---@param region string
function RefreshBoard(region)
    local now = GetServerTime()
    print(('[trucking] Refreshing board for region: %s'):format(region))

    -- 1. Expire any loads that are past their expiry time
    local expiredCount = MySQL.update.await([[
        UPDATE truck_loads SET board_status = 'expired'
        WHERE board_region = ? AND board_status = 'available' AND expires_at < ?
    ]], { region, now })

    -- 2. Count how many loads are still available per tier
    local existingCounts = MySQL.query.await([[
        SELECT tier, COUNT(*) as cnt FROM truck_loads
        WHERE board_region = ? AND board_status = 'available' AND expires_at > ?
        GROUP BY tier
    ]], { region, now })

    local currentByTier = {}
    for _, row in ipairs(existingCounts) do
        currentByTier[row.tier] = row.cnt
    end

    -- 3. Generate loads to fill up to target composition
    local targetCounts = BoardConfig.StandardLoads[region] or { [0]=4, [1]=4, [2]=3, [3]=2 }
    local activeSurges = DB.GetActiveSurges(region)
    local generatedCount = 0

    for tier = 0, 3 do
        local target = targetCounts[tier] or 0
        local current = currentByTier[tier] or 0
        local needed = target - current

        for i = 1, needed do
            local load = GenerateSingleLoad(region, tier, activeSurges, now, BoardConfig.LoadExpirySeconds or 7200)
            if load then
                DB.InsertLoad(load)
                generatedCount = generatedCount + 1
            end
        end
    end

    -- 4. Update board state
    local finalCounts = MySQL.query.await([[
        SELECT tier, COUNT(*) as cnt FROM truck_loads
        WHERE board_region = ? AND board_status = 'available' AND expires_at > ?
        GROUP BY tier
    ]], { region, now })

    local t0, t1, t2, t3 = 0, 0, 0, 0
    for _, row in ipairs(finalCounts) do
        if row.tier == 0 then t0 = row.cnt
        elseif row.tier == 1 then t1 = row.cnt
        elseif row.tier == 2 then t2 = row.cnt
        elseif row.tier == 3 then t3 = row.cnt
        end
    end

    local surgeCount = #activeSurges
    local refreshInterval = Config.BoardRefreshSeconds or 7200

    DB.UpdateBoardState(region, {
        last_refresh_at = now,
        next_refresh_at = now + refreshInterval,
        available_t0 = t0,
        available_t1 = t1,
        available_t2 = t2,
        available_t3 = t3,
        surge_active_count = surgeCount,
    })

    -- 5. Notify all connected players about the board refresh
    TriggerClientEvent('trucking:client:boardRefresh', -1, region, {
        available_t0 = t0,
        available_t1 = t1,
        available_t2 = t2,
        available_t3 = t3,
        surge_active = surgeCount > 0,
        next_refresh = now + refreshInterval,
    })

    print(('[trucking] Board refreshed for %s: %d expired, %d generated, total [T0:%d T1:%d T2:%d T3:%d], surges:%d'):format(
        region, expiredCount, generatedCount, t0, t1, t2, t3, surgeCount
    ))
end

-- ============================================================================
-- SURGE DETECTION
-- Check conditions that trigger surge pricing. Called during board refresh
-- and periodically. Surges are inserted into truck_surge_events.
-- ============================================================================

--- Run surge detection for a region and create surge events if conditions are met
---@param region string
function DetectSurges(region)
    local now = GetServerTime()

    -- 1. Open contract progress surge: if any open contract is >50% filled,
    --    add a 20% surge on related cargo type
    local openContracts = DB.GetOpenContracts()
    for _, contract in ipairs(openContracts) do
        local pctFilled = contract.quantity_fulfilled / contract.total_quantity_needed
        if pctFilled >= 0.50 then
            -- Check if a surge for this already exists
            local existing = MySQL.single.await([[
                SELECT id FROM truck_surge_events
                WHERE surge_type = 'open_contract_progress'
                  AND cargo_type_filter = ?
                  AND status = 'active'
            ]], { contract.cargo_type })

            if not existing then
                DB.InsertSurge({
                    region = 'server_wide',
                    surge_type = 'open_contract_progress',
                    cargo_type_filter = contract.cargo_type,
                    surge_percentage = 20,
                    trigger_data = { contract_id = contract.id, fill_pct = pctFilled },
                    expires_at = contract.expires_at, -- expires when contract closes
                })
                print(('[trucking] Surge created: open_contract_progress +20%% for %s'):format(contract.cargo_type))
            end
        end
    end

    -- 2. Shipper backlog: no deliveries to a shipper in 4+ hours
    if Shippers then
        for shipperId, shipper in pairs(Shippers) do
            if shipper.region == region then
                local lastDelivery = MySQL.single.await([[
                    SELECT MAX(delivered_at) as last_del FROM truck_bols
                    WHERE shipper_id = ? AND bol_status = 'delivered'
                ]], { shipperId })

                local lastTime = lastDelivery and lastDelivery.last_del or 0
                if lastTime > 0 and (now - lastTime) >= 14400 then -- 4 hours
                    local existing = MySQL.single.await([[
                        SELECT id FROM truck_surge_events
                        WHERE surge_type = 'shipper_backlog'
                          AND shipper_filter = ?
                          AND status = 'active'
                    ]], { shipperId })

                    if not existing then
                        DB.InsertSurge({
                            region = region,
                            surge_type = 'shipper_backlog',
                            shipper_filter = shipperId,
                            surge_percentage = 35,
                            trigger_data = { shipper_id = shipperId, hours_since = math.floor((now - lastTime) / 3600) },
                            -- Expires on next delivery to this shipper (handled by delivery code)
                            -- or after 6 hours max
                            expires_at = now + 21600,
                        })
                        print(('[trucking] Surge created: shipper_backlog +35%% for %s'):format(shipperId))
                    end
                end
            end
        end
    end

    -- 3. Cold chain failure streak: 3+ consecutive cold chain failures in region
    local recentFailures = MySQL.query.await([[
        SELECT COUNT(*) as cnt FROM truck_bols
        WHERE cargo_type IN ('cold_chain', 'pharmaceutical', 'pharmaceutical_biologic')
          AND bol_status IN ('rejected', 'abandoned')
          AND issued_at > ?
          AND origin_label IN (
              SELECT s.label FROM truck_loads s WHERE s.origin_region = ?
          )
    ]], { now - 7200, region }) -- last 2 hours

    local failCount = recentFailures and recentFailures[1] and recentFailures[1].cnt or 0
    if failCount >= 3 then
        local existing = MySQL.single.await([[
            SELECT id FROM truck_surge_events
            WHERE surge_type = 'cold_chain_failure_streak'
              AND region = ?
              AND status = 'active'
        ]], { region })

        if not existing then
            DB.InsertSurge({
                region = region,
                surge_type = 'cold_chain_failure_streak',
                cargo_type_filter = 'cold_chain',
                surge_percentage = 30,
                trigger_data = { failure_count = failCount },
                -- Expires after 3 successful reefer deliveries (handled by delivery code)
                -- or 4 hours max
                expires_at = now + 14400,
            })
            print(('[trucking] Surge created: cold_chain_failure_streak +30%% for %s'):format(region))
        end
    end

    -- 4. Peak population: check current server player count
    local playerCount = #GetPlayers()
    local peakThreshold = 40 -- configurable
    if playerCount >= peakThreshold then
        local existing = MySQL.single.await([[
            SELECT id FROM truck_surge_events
            WHERE surge_type = 'peak_population'
              AND status = 'active'
        ]], {})

        if not existing then
            DB.InsertSurge({
                region = 'server_wide',
                surge_type = 'peak_population',
                surge_percentage = 10,
                trigger_data = { player_count = playerCount },
                -- Expires when population drops (checked on next cycle), max 2 hours
                expires_at = now + 7200,
            })
            print(('[trucking] Surge created: peak_population +10%% (%d players)'):format(playerCount))
        end
    end
end

-- ============================================================================
-- LOAD DETAIL ASSEMBLY FOR NUI
-- Combines raw load data with shipper info, cargo metadata, and surge info
-- for display in the job board UI.
-- ============================================================================

--- Assemble a detailed load table suitable for NUI rendering
---@param loadRow table  Raw row from truck_loads
---@return table detailTable
function AssembleLoadDetail(loadRow)
    local cargo = CargoTypes and CargoTypes[loadRow.cargo_type] or {}
    local shipper = Shippers and Shippers[loadRow.shipper_id] or {}

    -- Parse JSON coords if stored as strings
    local originCoords = loadRow.origin_coords
    if type(originCoords) == 'string' then
        originCoords = json.decode(originCoords)
    end
    local destCoords = loadRow.destination_coords
    if type(destCoords) == 'string' then
        destCoords = json.decode(destCoords)
    end

    -- Build requirements list for display
    local requirements = {}
    if loadRow.required_license and loadRow.required_license ~= 'none' then
        requirements[#requirements + 1] = {
            type = 'license',
            value = loadRow.required_license,
            label = loadRow.required_license == 'class_a' and 'Class A CDL' or 'Class B CDL',
        }
    end
    if loadRow.required_endorsement then
        requirements[#requirements + 1] = {
            type = 'endorsement',
            value = loadRow.required_endorsement,
            label = loadRow.required_endorsement:gsub('_', ' '):upper() .. ' Endorsement',
        }
    end
    if loadRow.required_certification then
        requirements[#requirements + 1] = {
            type = 'certification',
            value = loadRow.required_certification,
            label = loadRow.required_certification:gsub('_', ' '),
        }
    end
    if loadRow.tier >= 1 then
        requirements[#requirements + 1] = {
            type = 'insurance',
            label = 'Active insurance policy required',
        }
    end

    return {
        id = loadRow.id,
        bol_number = loadRow.bol_number,
        tier = loadRow.tier,
        cargo_type = loadRow.cargo_type,
        cargo_label = cargo.label or loadRow.cargo_type:gsub('_', ' '),
        shipper_id = loadRow.shipper_id,
        shipper_name = loadRow.shipper_name,
        shipper_cluster = shipper.cluster or 'general',
        origin_region = loadRow.origin_region,
        origin_label = loadRow.origin_label,
        origin_coords = originCoords,
        destination_label = loadRow.destination_label,
        destination_coords = destCoords,
        distance_miles = loadRow.distance_miles,
        weight_lbs = loadRow.weight_lbs,
        base_rate_per_mile = loadRow.base_rate_per_mile,
        payout_rental = loadRow.base_payout_rental,
        payout_owner_op = loadRow.base_payout_owner_op,
        deposit_amount = loadRow.deposit_amount,
        requires_seal = loadRow.requires_seal,
        temp_range = loadRow.temp_min_f and {
            min = loadRow.temp_min_f,
            max = loadRow.temp_max_f,
        } or nil,
        hazmat_class = loadRow.hazmat_class,
        is_multi_stop = loadRow.is_multi_stop,
        stop_count = loadRow.stop_count,
        surge_active = loadRow.surge_active,
        surge_percentage = loadRow.surge_percentage,
        requirements = requirements,
        board_status = loadRow.board_status,
        posted_at = loadRow.posted_at,
        expires_at = loadRow.expires_at,
    }
end

--- Get the full board data for a region (called when player opens the board)
---@param region string
---@return table boardData
function GetBoardData(region)
    local loads = DB.GetAvailableLoads(region)
    local assembled = {}
    for _, load in ipairs(loads) do
        assembled[#assembled + 1] = AssembleLoadDetail(load)
    end

    local routes = DB.GetAvailableRoutes(region)
    local contracts = DB.GetAvailableContracts(region)
    local openContracts = DB.GetOpenContracts()
    local surges = DB.GetActiveSurges(region)
    local boardState = DB.GetBoardState(region)

    return {
        region = region,
        loads = assembled,
        routes = routes,
        contracts = contracts,
        open_contracts = openContracts,
        surges = surges,
        board_state = boardState,
    }
end

-- ============================================================================
-- EVENT HANDLER: Player requests board data
-- ============================================================================

RegisterNetEvent('trucking:server:openBoard', function(region)
    local src = source
    if not RateLimitEvent(src, 'openBoard', 2000) then return end

    -- Validate region
    local validRegions = { los_santos = true, sandy_shores = true, paleto = true, grapeseed = true }
    if not validRegions[region] then
        region = 'los_santos' -- fallback
    end

    -- Ensure driver record exists
    EnsureDriverRecord(src)

    -- Get the board data
    local boardData = GetBoardData(region)

    -- Send to client
    TriggerClientEvent('trucking:client:showBoard', src, boardData)
end)

-- ============================================================================
-- SURGE DETECTION PERIODIC CHECK
-- Runs alongside the board refresh but also independently every 30 minutes
-- ============================================================================

CreateThread(function()
    Wait(10000) -- initial delay
    while true do
        Wait(1800000) -- 30 minutes

        local regions = { 'los_santos', 'sandy_shores', 'paleto', 'grapeseed' }
        for _, region in ipairs(regions) do
            DetectSurges(region)
        end
    end
end)
