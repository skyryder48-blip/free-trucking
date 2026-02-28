--[[
    server/military.lua — Military Heist System (Section 26)
    Manages military contract availability, convoy spawning, escort behavior,
    breach detection, law enforcement dispatch, and long con consequences.

    - Max 2 military contracts per server restart
    - Only Government Clearance holders can accept
    - Contract classifications: equipment_transport, armory_transfer, restricted_munitions
    - Escort NPCs: Military Patriot, armed, maintain formation
    - Dual dispatch to lb-dispatch and ultimate-le
]]

--- Track how many military contracts have been issued this restart
---@type number
local MilitaryContractsIssued = 0

--- Maximum military contracts per server restart
local MAX_MILITARY_CONTRACTS = 2

--- Active military convoys tracked in memory
---@type table<number, table>
local ActiveConvoys = {}

--- Next convoy ID counter
local NextConvoyId = 1

--- Escort behavior constants
local ESCORT_INVESTIGATE_DELAY = 60   -- seconds stopped before escorts investigate
local ESCORT_PURSUE_RANGE      = 500  -- meters max pursuit distance
local ESCORT_UNGUARDED_WINDOW  = 90   -- seconds after both escorts destroyed
local ESCORT_SPEED             = 40.0 -- mph formation speed

--- Military cargo loot tables (Section 26.4)
local MilitaryCargo = {
    equipment_transport = {
        { item = 'military_armor_vest',     weight = 15, chance = 0.70 },
        { item = 'military_ammunition_box', weight = 20, chance = 0.80 },
        { item = 'military_vehicle_parts',  weight = 25, chance = 0.60 },
        { item = 'military_pistol',         weight = 5,  chance = 0.50 },
    },
    armory_transfer = {
        { item = 'military_armor_vest',       weight = 15, chance = 0.70 },
        { item = 'military_ammunition_box',   weight = 20, chance = 0.80 },
        { item = 'military_vehicle_parts',    weight = 25, chance = 0.60 },
        { item = 'military_pistol',           weight = 5,  chance = 0.50 },
        { item = 'military_rifle',            weight = 8,  chance = 0.60 },
        { item = 'military_explosive_charge', weight = 4,  chance = 0.30 },
        { item = 'classified_documents',      weight = 1,  chance = 0.10 },
    },
    restricted_munitions = {
        { item = 'military_armor_vest',         weight = 15, chance = 0.70 },
        { item = 'military_ammunition_box',     weight = 20, chance = 0.80 },
        { item = 'military_vehicle_parts',      weight = 25, chance = 0.60 },
        { item = 'military_pistol',             weight = 5,  chance = 0.50 },
        { item = 'military_rifle',              weight = 8,  chance = 0.60 },
        { item = 'military_explosive_charge',   weight = 4,  chance = 0.30 },
        { item = 'classified_documents',        weight = 1,  chance = 0.10 },
        { item = 'military_rifle_suppressed',   weight = 6,  chance = 0.40 },
        { item = 'military_lmg',                weight = 12, chance = 0.25 },
    },
}

--- Contract classification descriptions
local ContractClassifications = {
    equipment_transport = {
        label       = 'Equipment Transport',
        description = 'Vehicle parts, field gear, no weapons guaranteed',
        payout_base = 8000,
        payout_max  = 15000,
    },
    armory_transfer = {
        label       = 'Armory Transfer',
        description = '1-2 automatic weapons probable',
        payout_base = 12000,
        payout_max  = 22000,
    },
    restricted_munitions = {
        label       = 'Restricted Munitions',
        description = '3-5 automatic weapons confirmed',
        payout_base = 18000,
        payout_max  = 35000,
    },
}

--- Military convoy route definitions (placeholder coordinates)
local ConvoyRoutes = {
    {
        label       = 'Fort Zancudo - Sandy Shores',
        waypoints   = {
            vector3(-2239.0, 3228.0, 32.8),
            vector3(-1628.0, 3072.0, 32.8),
            vector3(-600.0, 2925.0, 16.3),
            vector3(380.0, 2627.0, 44.7),
            vector3(1395.0, 3608.0, 35.0),
        },
    },
    {
        label       = 'Fort Zancudo - LS Port',
        waypoints   = {
            vector3(-2239.0, 3228.0, 32.8),
            vector3(-1990.0, 2566.0, 3.0),
            vector3(-1540.0, 1489.0, 2.6),
            vector3(-665.0, -145.0, 37.8),
            vector3(156.0, -3209.0, 5.9),
        },
    },
    {
        label       = 'Humane Labs - Fort Zancudo',
        waypoints   = {
            vector3(3525.0, 3663.0, 28.1),
            vector3(2540.0, 4103.0, 38.0),
            vector3(1395.0, 3608.0, 35.0),
            vector3(-600.0, 2925.0, 16.3),
            vector3(-2239.0, 3228.0, 32.8),
        },
    },
}

--- Check if a player holds active Government Clearance certification
---@param citizenid string Player's citizen ID
---@return boolean hasAccess True if player has government clearance
local function HasGovernmentClearance(citizenid)
    if not citizenid then return false end

    local cert = MySQL.single.await([[
        SELECT id, status FROM truck_certifications
        WHERE citizenid = ? AND cert_type = 'government_clearance' AND status = 'active'
    ]], { citizenid })

    return cert ~= nil
end

--- Dispatch alert to law enforcement via both lb-dispatch and ultimate-le
---@param alertData table Alert data including type, priority, location, description
local function DispatchToPolice(alertData)
    if not alertData then return end

    -- Try lb-dispatch
    local lbSuccess = pcall(function()
        exports['lb-dispatch']:dispatchAlert(alertData)
    end)

    if not lbSuccess then
        -- Silently handle — resource may not be running
        print('[Trucking Military] lb-dispatch not available for alert dispatch')
    end

    -- Try ultimate-le
    local uleSuccess = pcall(function()
        exports['ultimate-le']:dispatchAlert(alertData)
    end)

    if not uleSuccess then
        print('[Trucking Military] ultimate-le not available for alert dispatch')
    end

    -- Also try configured police resource as fallback
    if Config.PoliceResource and Config.PoliceResource ~= '' then
        local configSuccess = pcall(function()
            exports[Config.PoliceResource]:dispatchAlert(alertData)
        end)

        if not configSuccess then
            print(('[Trucking Military] %s not available for alert dispatch'):format(Config.PoliceResource))
        end
    end
end

--- Generate a random military contract classification
---@return string classification The contract classification key
local function RandomClassification()
    local classifications = { 'equipment_transport', 'armory_transfer', 'restricted_munitions' }
    -- Weight towards equipment_transport (more common)
    local roll = math.random(100)
    if roll <= 50 then
        return 'equipment_transport'
    elseif roll <= 80 then
        return 'armory_transfer'
    else
        return 'restricted_munitions'
    end
end

--- Generate loot from a military cargo breach based on classification
---@param classification string The contract classification
---@return table[] loot Array of { item, amount } for looted items
local function GenerateMilitaryLoot(classification)
    local lootTable = MilitaryCargo[classification]
    if not lootTable then return {} end

    local loot = {}

    for i = 1, #lootTable do
        local entry = lootTable[i]
        local roll = math.random()
        if roll <= entry.chance then
            local amount = 1
            -- Some items can drop multiples
            if entry.item == 'military_ammunition_box' then
                amount = math.random(1, 3)
            end

            loot[#loot + 1] = {
                item    = entry.item,
                amount  = amount,
                weight  = entry.weight,
            }
        end
    end

    return loot
end

--- Post a military contract to the board
---@return table|nil contract The generated contract, or nil if limit reached
function PostMilitaryContract()
    if MilitaryContractsIssued >= MAX_MILITARY_CONTRACTS then
        print('[Trucking Military] Maximum military contracts reached for this restart')
        return nil
    end

    local classification = RandomClassification()
    local classInfo = ContractClassifications[classification]
    local route = ConvoyRoutes[math.random(#ConvoyRoutes)]
    local payout = math.random(classInfo.payout_base, classInfo.payout_max)

    local bolNumber = 'MIL-' .. GetServerTime() .. '-' .. math.random(100, 999)

    local contractData = {
        bol_number          = bolNumber,
        classification      = classification,
        classification_label = classInfo.label,
        description         = classInfo.description,
        route               = route,
        payout              = payout,
        posted_at           = GetServerTime(),
        expires_at          = GetServerTime() + 7200, -- 2 hour window to accept
        status              = 'available',
        accepted_by         = nil,
    }

    -- Insert into truck_loads
    MySQL.insert.await([[
        INSERT INTO truck_loads
        (bol_number, tier, cargo_type, cargo_subtype, shipper_id, shipper_name,
         origin_region, origin_label, origin_coords, destination_label, destination_coords,
         distance_miles, weight_lbs, base_rate_per_mile, base_payout_rental,
         board_status, is_leon_load, required_certification,
         posted_at, expires_at, board_region, requires_seal)
        VALUES (?, 3, 'military', ?, 'san_andreas_national_guard',
                'SA National Guard', 'los_santos', ?, ?, ?, ?,
                0, 0, 0, ?, 'available', FALSE, 'government_clearance',
                ?, ?, 'los_santos', TRUE)
    ]], {
        bolNumber,
        classification,
        route.label:match('^(.-)%s*%-') or route.label,
        json.encode({ x = route.waypoints[1].x, y = route.waypoints[1].y, z = route.waypoints[1].z }),
        route.label:match('%-(.+)$') and route.label:match('%-(.+)$'):match('^%s*(.-)%s*$') or 'Classified',
        json.encode({
            x = route.waypoints[#route.waypoints].x,
            y = route.waypoints[#route.waypoints].y,
            z = route.waypoints[#route.waypoints].z,
        }),
        payout,
        GetServerTime(),
        GetServerTime() + 7200,
    })

    MilitaryContractsIssued = MilitaryContractsIssued + 1

    SendMilitaryWebhook('contract_posted', {
        classification = classification,
        bol_number     = bolNumber,
    })

    print(('[Trucking Military] Contract posted: %s (%s) — %d of %d')
        :format(bolNumber, classification, MilitaryContractsIssued, MAX_MILITARY_CONTRACTS))

    return contractData
end

--- Accept a military contract
---@param src number Player server ID
---@param bolNumber string The military contract BOL number
---@return boolean success
---@return string|table reason Error reason or contract data
function AcceptMilitaryContract(src, bolNumber)
    if not src or not bolNumber then return false, 'invalid_params' end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false, 'player_not_found' end

    local citizenid = player.PlayerData.citizenid

    -- Check Government Clearance
    if not HasGovernmentClearance(citizenid) then
        return false, 'no_clearance'
    end

    -- Check for active load
    local existingLoad = MySQL.single.await([[
        SELECT id FROM truck_active_loads WHERE citizenid = ?
    ]], { citizenid })

    if existingLoad then return false, 'active_load_exists' end

    -- Find the contract
    local contract = MySQL.single.await([[
        SELECT * FROM truck_loads
        WHERE bol_number = ? AND cargo_type = 'military' AND board_status = 'available'
    ]], { bolNumber })

    if not contract then return false, 'contract_not_found' end
    if contract.expires_at <= GetServerTime() then return false, 'contract_expired' end

    -- Accept the contract
    MySQL.update.await([[
        UPDATE truck_loads SET board_status = 'accepted', reserved_by = ?
        WHERE id = ?
    ]], { citizenid, contract.id })

    -- Create BOL for military contract (unlike Leon, military has BOL)
    local bolId = MySQL.insert.await([[
        INSERT INTO truck_bols
        (bol_number, load_id, citizenid, driver_name, shipper_id, shipper_name,
         origin_label, destination_label, distance_miles, cargo_type,
         cargo_description, weight_lbs, tier, seal_number, seal_status,
         bol_status, issued_at)
        VALUES (?, ?, ?, ?, 'san_andreas_national_guard', 'SA National Guard',
                ?, ?, 0, 'military', ?, 0, 3, NULL, 'not_applied', 'active', ?)
    ]], {
        bolNumber,
        contract.id,
        citizenid,
        GetPlayerName(src) or 'Unknown',
        contract.origin_label,
        contract.destination_label,
        contract.cargo_subtype or 'Military Cargo',
        GetServerTime(),
    })

    -- Create active load
    local activeLoadId = MySQL.insert.await([[
        INSERT INTO truck_active_loads
        (load_id, bol_id, citizenid, driver_id, status, cargo_integrity,
         seal_status, accepted_at, window_expires_at, estimated_payout)
        VALUES (?, ?, ?, 0, 'at_origin', 100, 'sealed', ?, ?, ?)
    ]], {
        contract.id,
        bolId,
        citizenid,
        GetServerTime(),
        GetServerTime() + 5400, -- 90 minute window
        contract.base_payout_rental,
    })

    -- Store in ActiveLoads
    if ActiveLoads then
        ActiveLoads[activeLoadId] = {
            id                  = activeLoadId,
            load_id             = contract.id,
            bol_id              = bolId,
            bol_number          = bolNumber,
            citizenid           = citizenid,
            is_military         = true,
            classification      = contract.cargo_subtype,
            payout              = contract.base_payout_rental,
            status              = 'at_origin',
            accepted_at         = GetServerTime(),
            window_expires      = GetServerTime() + 5400,
            convoy_id           = nil,
            origin_coords       = json.decode(contract.origin_coords),
            destination_coords  = json.decode(contract.destination_coords),
        }
    end

    SendMilitaryWebhook('contract_accepted', {
        citizenid       = citizenid,
        classification  = contract.cargo_subtype,
    })

    lib.notify(src, {
        title       = 'Military Contract',
        description = 'Contract accepted. Report to origin for convoy assignment.',
        type        = 'success',
    })

    return true, {
        active_load_id  = activeLoadId,
        bol_id          = bolId,
        bol_number      = bolNumber,
        classification  = contract.cargo_subtype,
        payout          = contract.base_payout_rental,
    }
end

--- Spawn a military convoy with lead and trail escort NPCs
---@param loadData table Active load data including route information
---@return table|nil convoyData Convoy tracking data or nil on failure
function SpawnMilitaryConvoy(loadData)
    if not loadData then
        print('[Trucking Military] SpawnMilitaryConvoy called with nil loadData')
        return nil
    end

    local convoyId = NextConvoyId
    NextConvoyId = NextConvoyId + 1

    -- Find the appropriate route
    local route = nil
    for i = 1, #ConvoyRoutes do
        -- Match route by origin coordinates if possible
        route = ConvoyRoutes[i]
        break
    end

    if not route then
        route = ConvoyRoutes[1] -- Default fallback
    end

    local convoyData = {
        id                  = convoyId,
        load_id             = loadData.load_id or loadData.id,
        citizenid           = loadData.citizenid,
        classification      = loadData.classification,
        route               = route,
        waypoints           = route.waypoints,
        current_waypoint    = 1,
        status              = 'forming',
        spawned_at          = GetServerTime(),

        -- Escort state
        lead_escort = {
            alive       = true,
            vehicle     = nil, -- Network ID set by client
            ped         = nil, -- Network ID set by client
            model       = 'insurgent',
            weapon      = 'WEAPON_CARBINERIFLE',
            destroyed_at = nil,
        },
        trail_escort = {
            alive       = true,
            vehicle     = nil,
            ped         = nil,
            model       = 'insurgent',
            weapon      = 'WEAPON_CARBINERIFLE',
            destroyed_at = nil,
        },

        -- Timing state
        stopped_since           = nil,
        investigating           = false,
        unguarded_window_start  = nil,
        breach_detected         = false,

        -- Formation parameters
        formation_speed     = ESCORT_SPEED,
        pursue_range        = ESCORT_PURSUE_RANGE,
    }

    ActiveConvoys[convoyId] = convoyData

    -- Notify all clients near the convoy spawn to create the entities
    local src = nil
    if loadData.citizenid then
        local playerSrc = exports.qbx_core:GetPlayerByCitizenId(loadData.citizenid)
        if playerSrc then
            src = type(playerSrc) == 'number' and playerSrc or playerSrc.PlayerData and playerSrc.PlayerData.source
        end
    end

    if src then
        TriggerClientEvent('trucking:client:spawnMilitaryConvoy', src, {
            convoy_id       = convoyId,
            route           = route,
            waypoints       = route.waypoints,
            lead_model      = 'insurgent',
            trail_model     = 'insurgent',
            lead_weapon     = 'WEAPON_CARBINERIFLE',
            trail_weapon    = 'WEAPON_CARBINERIFLE',
            formation_speed = ESCORT_SPEED,
        })
    end

    print(('[Trucking Military] Convoy %d spawned for %s'):format(convoyId, loadData.citizenid or 'unknown'))

    return convoyData
end

--- Update escort entity network IDs after client spawns them
---@param convoyId number Convoy identifier
---@param escortType string 'lead' or 'trail'
---@param vehicleNetId number Vehicle network ID
---@param pedNetId number Ped network ID
function RegisterConvoyEscort(convoyId, escortType, vehicleNetId, pedNetId)
    local convoy = ActiveConvoys[convoyId]
    if not convoy then return end

    local key = escortType .. '_escort'
    if convoy[key] then
        convoy[key].vehicle = vehicleNetId
        convoy[key].ped = pedNetId
    end
end

--- Handle escort destruction
---@param convoyId number Convoy identifier
---@param escortType string 'lead' or 'trail'
function HandleEscortDestroyed(convoyId, escortType)
    local convoy = ActiveConvoys[convoyId]
    if not convoy then return end

    local key = escortType .. '_escort'
    if convoy[key] then
        convoy[key].alive = false
        convoy[key].destroyed_at = GetServerTime()
    end

    -- Check if both escorts are destroyed
    if not convoy.lead_escort.alive and not convoy.trail_escort.alive then
        convoy.unguarded_window_start = GetServerTime()

        print(('[Trucking Military] Both escorts destroyed for convoy %d — %d second window')
            :format(convoyId, ESCORT_UNGUARDED_WINDOW))

        -- Notify the driver about the unguarded window
        local playerSrc = exports.qbx_core:GetPlayerByCitizenId(convoy.citizenid)
        if playerSrc then
            local src = type(playerSrc) == 'number' and playerSrc or nil
            if src then
                TriggerClientEvent('trucking:client:convoyUnguarded', src, {
                    convoy_id = convoyId,
                    window_seconds = ESCORT_UNGUARDED_WINDOW,
                })
            end
        end
    end
end

--- Handle vehicle stop detection for convoy investigation behavior
---@param convoyId number Convoy identifier
---@param isStopped boolean Whether the cargo vehicle is stopped
function HandleConvoyStopState(convoyId, isStopped)
    local convoy = ActiveConvoys[convoyId]
    if not convoy then return end

    if isStopped then
        if not convoy.stopped_since then
            convoy.stopped_since = GetServerTime()
        elseif (GetServerTime() - convoy.stopped_since) >= ESCORT_INVESTIGATE_DELAY and not convoy.investigating then
            convoy.investigating = true

            -- Tell client escorts to investigate
            local playerSrc = exports.qbx_core:GetPlayerByCitizenId(convoy.citizenid)
            if playerSrc then
                local src = type(playerSrc) == 'number' and playerSrc or nil
                if src then
                    TriggerClientEvent('trucking:client:escortsInvestigate', src, {
                        convoy_id = convoyId,
                    })
                end
            end
        end
    else
        convoy.stopped_since = nil
        convoy.investigating = false
    end
end

--- Detect and handle a military cargo breach (not convoy stop — actual cargo access)
---@param src number Player server ID triggering the breach
---@param loadId number Active load ID
---@return boolean dispatched Whether police dispatch was sent
function HandleMilitaryBreach(src, loadId)
    if not src then return false end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end

    local citizenid = player.PlayerData.citizenid
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)

    -- Find the active military load
    local activeLoad = nil
    if ActiveLoads then
        activeLoad = ActiveLoads[loadId]
        if activeLoad and not activeLoad.is_military then
            activeLoad = nil
        end
    end

    if not activeLoad then
        -- Search all active loads for this military contract
        if ActiveLoads then
            for id, load in pairs(ActiveLoads) do
                if load.is_military and load.citizenid == citizenid then
                    activeLoad = load
                    break
                end
            end
        end
    end

    -- Dispatch to law enforcement on cargo breach
    local alertData = {
        type        = 'military_cargo_theft',
        priority    = 'high',
        location    = coords,
        description = 'Military contract cargo reported stolen',
        coords      = { x = coords.x, y = coords.y, z = coords.z },
    }

    -- Dispatch to both lb-dispatch and ultimate-le
    DispatchToPolice(alertData)

    -- Mark convoy as breached
    for convoyId, convoy in pairs(ActiveConvoys) do
        if convoy.citizenid == citizenid then
            convoy.breach_detected = true
            break
        end
    end

    -- Log the breach event
    if activeLoad then
        MySQL.insert([[
            INSERT INTO truck_bol_events
            (bol_id, bol_number, citizenid, event_type, event_data, coords, occurred_at)
            VALUES (?, ?, ?, 'robbery_initiated', ?, ?, ?)
        ]], {
            activeLoad.bol_id or 0,
            activeLoad.bol_number or '',
            citizenid,
            json.encode({ classification = activeLoad.classification }),
            json.encode({ x = coords.x, y = coords.y, z = coords.z }),
            GetServerTime(),
        })
    end

    SendMilitaryWebhook('cargo_breach', {
        citizenid       = citizenid,
        classification  = activeLoad and activeLoad.classification or 'unknown',
        location        = { x = coords.x, y = coords.y, z = coords.z },
    })

    print(('[Trucking Military] Cargo breach detected — dispatch sent, player: %s')
        :format(citizenid))

    return true
end

--- Apply long con consequences to a driver who betrayed a military contract
---@param citizenid string Player's citizen ID
---@return boolean success
function LongConConsequences(citizenid)
    if not citizenid then return false end

    local now = GetServerTime()
    local repHit = Config.LongConReputationHit or 400
    local clearanceSuspendDays = Config.LongConClearanceSuspendDays or 30
    local t3SuspendDays = 14

    -- Get current rep
    local driver = MySQL.single.await([[
        SELECT id, reputation_score, reputation_tier FROM truck_drivers
        WHERE citizenid = ?
    ]], { citizenid })

    if not driver then return false end

    local newScore = math.max(0, driver.reputation_score - repHit)

    -- Determine new tier based on score
    local newTier = 'suspended'
    if newScore >= 1000 then newTier = 'elite'
    elseif newScore >= 800 then newTier = 'professional'
    elseif newScore >= 600 then newTier = 'established'
    elseif newScore >= 400 then newTier = 'developing'
    elseif newScore >= 200 then newTier = 'probationary'
    elseif newScore >= 1 then newTier = 'restricted'
    end

    -- Apply reputation hit
    MySQL.update.await([[
        UPDATE truck_drivers
        SET reputation_score = ?, reputation_tier = ?
        WHERE citizenid = ?
    ]], { newScore, newTier, citizenid })

    -- Log the rep change
    MySQL.insert([[
        INSERT INTO truck_driver_reputation_log
        (driver_id, citizenid, change_type, points_before, points_change,
         points_after, tier_before, tier_after, occurred_at)
        VALUES (?, ?, 'military_long_con', ?, ?, ?, ?, ?, ?)
    ]], {
        driver.id,
        citizenid,
        driver.reputation_score,
        -repHit,
        newScore,
        driver.reputation_tier,
        newTier,
        now,
    })

    -- Suspend Government Clearance for 30 days
    MySQL.update.await([[
        UPDATE truck_certifications
        SET status = 'suspended',
            revoked_reason = 'Military long con — government clearance suspended',
            revoked_at = ?,
            reinstatement_eligible = ?
        WHERE citizenid = ? AND cert_type = 'government_clearance' AND status = 'active'
    ]], { now, now + (clearanceSuspendDays * 86400), citizenid })

    -- Suspend ALL Tier 3 certifications for 14 days
    MySQL.update.await([[
        UPDATE truck_certifications
        SET status = 'suspended',
            revoked_reason = 'Military long con — T3 certs suspended 14 days',
            revoked_at = ?,
            reinstatement_eligible = ?
        WHERE citizenid = ? AND status = 'active'
    ]], { now, now + (t3SuspendDays * 86400), citizenid })

    -- Notify the player if online
    local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if playerSrc then
        local src = type(playerSrc) == 'number' and playerSrc or nil
        if src then
            lib.notify(src, {
                title       = 'Military Contract Violation',
                description = ('Reputation -%d. Government Clearance suspended %d days. All T3 certs suspended %d days.')
                    :format(repHit, clearanceSuspendDays, t3SuspendDays),
                type        = 'error',
                duration    = 10000,
            })

            TriggerClientEvent('trucking:client:reputationUpdate', src, {
                score       = newScore,
                tier        = newTier,
                change      = -repHit,
                reason      = 'military_long_con',
            })
        end
    end

    SendMilitaryWebhook('long_con', {
        citizenid       = citizenid,
        consequence     = ('Rep -%d, Gov clearance suspended %d days, T3 certs suspended %d days')
            :format(repHit, clearanceSuspendDays, t3SuspendDays),
    })

    print(('[Trucking Military] Long con consequences applied to %s: -%d rep')
        :format(citizenid, repHit))

    return true
end

--- Complete a legitimate military delivery
---@param src number Player server ID
---@param loadId number Active load ID
---@return boolean success
---@return number|nil payout
function CompleteMilitaryDelivery(src, loadId)
    if not src then return false, nil end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false, nil end

    local citizenid = player.PlayerData.citizenid
    local activeLoad = ActiveLoads and ActiveLoads[loadId]

    if not activeLoad then return false, nil end
    if activeLoad.citizenid ~= citizenid then return false, nil end
    if not activeLoad.is_military then return false, nil end

    local payout = activeLoad.payout or 0

    -- Pay to bank (legitimate contract)
    player.Functions.AddMoney('bank', payout, 'Military contract delivery - ' .. (activeLoad.bol_number or ''))

    -- Update driver stats
    MySQL.update([[
        UPDATE truck_drivers
        SET total_loads_completed = total_loads_completed + 1,
            total_earnings = total_earnings + ?,
            last_seen = ?
        WHERE citizenid = ?
    ]], { payout, GetServerTime(), citizenid })

    -- Update BOL status
    if activeLoad.bol_id then
        MySQL.update([[
            UPDATE truck_bols
            SET bol_status = 'delivered', delivered_at = ?, final_payout = ?
            WHERE id = ?
        ]], { GetServerTime(), payout, activeLoad.bol_id })
    end

    -- Update load status
    MySQL.update([[
        UPDATE truck_loads SET board_status = 'completed'
        WHERE id = ?
    ]], { activeLoad.load_id })

    -- Clean up active load
    MySQL.update([[
        DELETE FROM truck_active_loads WHERE id = ?
    ]], { loadId })

    -- Clean up convoy
    for convoyId, convoy in pairs(ActiveConvoys) do
        if convoy.citizenid == citizenid then
            ActiveConvoys[convoyId] = nil

            -- Tell client to despawn convoy
            TriggerClientEvent('trucking:client:despawnMilitaryConvoy', src, {
                convoy_id = convoyId,
            })
            break
        end
    end

    -- Clean up memory
    if ActiveLoads then
        ActiveLoads[loadId] = nil
    end

    SendMilitaryWebhook('delivery_complete', {
        citizenid       = citizenid,
        classification  = activeLoad.classification,
    })

    lib.notify(src, {
        title       = 'Military Contract',
        description = ('Contract completed. $%s deposited.'):format(payout),
        type        = 'success',
    })

    return true, payout
end

--- Get the cargo loot table for a specific classification
---@param classification string Contract classification
---@return table[] lootTable The cargo items with chances
function GetMilitaryCargoTable(classification)
    return MilitaryCargo[classification] or {}
end

--- Clean up a convoy from memory
---@param convoyId number Convoy identifier
function CleanupConvoy(convoyId)
    if ActiveConvoys[convoyId] then
        ActiveConvoys[convoyId] = nil
        print(('[Trucking Military] Convoy %d cleaned up'):format(convoyId))
    end
end

--- Get all active convoys (for admin panel)
---@return table<number, table> convoys
function GetActiveConvoys()
    return ActiveConvoys
end

-- ─────────────────────────────────────────────
-- EVENT HANDLERS
-- ─────────────────────────────────────────────

--- Accept military contract event
RegisterNetEvent('trucking:server:acceptMilitaryContract', function(bolNumber)
    local src = source
    if not bolNumber then return end

    local success, result = AcceptMilitaryContract(src, bolNumber)

    if success and type(result) == 'table' then
        TriggerClientEvent('trucking:client:loadAssigned', src, result)
    else
        local errorMessages = {
            no_clearance        = 'Government Clearance required.',
            active_load_exists  = 'Complete your current load first.',
            contract_not_found  = 'Contract no longer available.',
            contract_expired    = 'Contract has expired.',
        }

        lib.notify(src, {
            title       = 'Military Contract',
            description = errorMessages[result] or 'Could not accept contract.',
            type        = 'error',
        })
    end
end)

--- Convoy escort registration from client
RegisterNetEvent('trucking:server:registerConvoyEscort', function(convoyId, escortType, vehicleNetId, pedNetId)
    local src = source
    if not convoyId or not escortType then return end
    RegisterConvoyEscort(convoyId, escortType, vehicleNetId, pedNetId)
end)

--- Escort destroyed event from client
RegisterNetEvent('trucking:server:escortDestroyed', function(convoyId, escortType)
    local src = source
    if not convoyId or not escortType then return end
    HandleEscortDestroyed(convoyId, escortType)
end)

--- Convoy stop state update from client
RegisterNetEvent('trucking:server:convoyStopState', function(convoyId, isStopped)
    local src = source
    if not convoyId then return end
    HandleConvoyStopState(convoyId, isStopped)
end)

--- Military breach detected event
RegisterNetEvent('trucking:server:militaryBreachDetected', function(loadId)
    local src = source
    if not loadId then return end
    HandleMilitaryBreach(src, loadId)
end)

--- Spawn convoy request from client
RegisterNetEvent('trucking:server:requestConvoySpawn', function(activeLoadId)
    local src = source
    if not activeLoadId then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local activeLoad = ActiveLoads and ActiveLoads[activeLoadId]

    if not activeLoad or activeLoad.citizenid ~= citizenid or not activeLoad.is_military then
        return
    end

    local convoyData = SpawnMilitaryConvoy(activeLoad)
    if convoyData then
        activeLoad.convoy_id = convoyData.id
    end
end)

--- Complete military delivery event
RegisterNetEvent('trucking:server:completeMilitaryDelivery', function(loadId)
    local src = source
    if not loadId then return end
    CompleteMilitaryDelivery(src, loadId)
end)

--- Long con detection — driver intentionally stops convoy for crew
RegisterNetEvent('trucking:server:militaryLongCon', function(loadId)
    local src = source
    if not src then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid

    -- Apply consequences
    LongConConsequences(citizenid)

    -- Also trigger breach dispatch
    HandleMilitaryBreach(src, loadId)
end)

-- ─────────────────────────────────────────────
-- PERIODIC MILITARY CONTRACT POSTING
-- ─────────────────────────────────────────────

CreateThread(function()
    -- Military contracts are rare — random posting at intervals
    Wait(math.random(300000, 900000)) -- 5-15 minute initial delay

    while true do
        if MilitaryContractsIssued < MAX_MILITARY_CONTRACTS then
            -- Random chance to post a contract (low probability)
            local roll = math.random(100)
            if roll <= 15 then -- 15% chance per check
                PostMilitaryContract()
            end
        end

        -- Check every 20-40 minutes
        Wait(math.random(1200000, 2400000))
    end
end)

-- ─────────────────────────────────────────────
-- CONVOY MONITORING THREAD
-- ─────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(5000) -- Check every 5 seconds

        local now = GetServerTime()

        for convoyId, convoy in pairs(ActiveConvoys) do
            -- Check unguarded window expiry
            if convoy.unguarded_window_start then
                local elapsed = now - convoy.unguarded_window_start
                if elapsed >= ESCORT_UNGUARDED_WINDOW and not convoy.breach_detected then
                    -- Window expired without breach — respawn escorts or end event
                    convoy.unguarded_window_start = nil

                    print(('[Trucking Military] Convoy %d unguarded window expired without breach')
                        :format(convoyId))
                end
            end
        end
    end
end)
