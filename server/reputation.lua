--[[
    server/reputation.lua — Driver and Shipper Reputation Management

    Handles all reputation score changes, tier transitions, board access
    checks, and shipper relationship tracking. All mutations are server-
    authoritative and logged to truck_driver_reputation_log and
    truck_shipper_reputation_log for audit.

    Driver rep tiers:
        0       = suspended  (24-hour lockout)
        1+      = restricted (Tier 0 only)
        200+    = probationary (Tier 0-1)
        400+    = developing (Tier 0-2)
        600+    = established (full board)
        800+    = professional (full + cross-region)
        1000    = elite (full + early government)

    Shipper rep tiers:
        0       = unknown
        50+     = familiar (+5% rate)
        150+    = established (+10% rate)
        350+    = trusted (+15% rate)
        700+    = preferred (+20% rate, decays after 14 days)
        0 (special) = blacklisted (no loads until reinstatement)
]]

-- ─────────────────────────────────────────────
-- DRIVER REPUTATION TIER THRESHOLDS
-- ─────────────────────────────────────────────

local DriverTierThresholds = {
    { min = 1000, tier = 'elite' },
    { min = 800,  tier = 'professional' },
    { min = 600,  tier = 'established' },
    { min = 400,  tier = 'developing' },
    { min = 200,  tier = 'probationary' },
    { min = 1,    tier = 'restricted' },
    { min = 0,    tier = 'suspended' },
}

--- Maximum tier of load a given driver reputation tier can access
local TierBoardAccess = {
    suspended    = -1,  -- no access
    restricted   = 0,   -- Tier 0 only
    probationary = 1,   -- Tier 0-1
    developing   = 2,   -- Tier 0-2
    established  = 3,   -- full board
    professional = 3,   -- full board + cross-region view
    elite        = 3,   -- full board + early government
}

-- ─────────────────────────────────────────────
-- DELIVERY REPUTATION REWARDS BY TIER
-- ─────────────────────────────────────────────

local DeliveryRepPoints = {
    [0] = 8,
    [1] = 15,
    [2] = 25,
    [3] = 40,
    [4] = 60,  -- military uses pseudo-tier 4
}

-- ─────────────────────────────────────────────
-- FAILURE REPUTATION PENALTIES [event][tier]
-- nil means not applicable for that tier
-- ─────────────────────────────────────────────

local FailureRepPenalties = {
    robbery = {
        [0] = 30,  [1] = 60,  [2] = 100, [3] = 180, [4] = 250,
    },
    integrity_fail = {
        [0] = 20,  [1] = 40,  [2] = 70,  [3] = 120,
    },
    abandonment = {
        [0] = 25,  [1] = 50,  [2] = 90,  [3] = 160,
    },
    window_expired = {
        [0] = 10,  [1] = 20,  [2] = 35,  [3] = 60,
    },
    seal_break = {
        [1] = 15,  [2] = 30,  [3] = 55,
    },
    hazmat_routing = {
        [3] = 40,
    },
}

-- ─────────────────────────────────────────────
-- BONUS REPUTATION REWARDS
-- ─────────────────────────────────────────────

local BonusRepPoints = {
    full_compliance    = 5,
    supplier_contract  = 20,
    cold_chain_clean   = 8,
    livestock_excellent = 10,
}

-- ─────────────────────────────────────────────
-- SHIPPER REPUTATION TIER THRESHOLDS
-- ─────────────────────────────────────────────

local ShipperTierThresholds = {
    { min = 700, tier = 'preferred' },
    { min = 350, tier = 'trusted' },
    { min = 150, tier = 'established' },
    { min = 50,  tier = 'familiar' },
    { min = 0,   tier = 'unknown' },
}

--- Cluster definitions: shippers sharing reputation signals
--- Damage with one shipper reduces progression with cluster partners
local ShipperClusters = {
    luxury       = true,
    agricultural = true,
    industrial   = true,
    government   = true,
}

--- Cluster friction percentage range (applied to progression rate)
local CLUSTER_FRICTION_MIN = 0.10  -- 10%
local CLUSTER_FRICTION_MAX = 0.15  -- 15%

-- ─────────────────────────────────────────────
-- DRIVER REPUTATION — CORE FUNCTIONS
-- ─────────────────────────────────────────────

--- Determine the reputation tier name for a given score
---@param score number The driver's reputation score
---@return string tier The tier name
function GetReputationTier(score)
    if not score or type(score) ~= 'number' then
        return 'suspended'
    end
    for _, entry in ipairs(DriverTierThresholds) do
        if score >= entry.min then
            return entry.tier
        end
    end
    return 'suspended'
end

--- Update a driver's reputation score, handle tier transitions, and log
---@param citizenid string Driver's citizen ID
---@param changeType string Description of the change (e.g. 'delivery_t1', 'robbery')
---@param points number Points to add (positive) or subtract (negative)
---@param bolId number|nil Associated BOL ID if applicable
---@param tierOfLoad number|nil Tier of the load if applicable
---@return boolean success
---@return string|nil error
function UpdateDriverReputation(citizenid, changeType, points, bolId, tierOfLoad)
    if not citizenid or not changeType or not points then
        return false, 'missing_parameters'
    end

    -- Fetch current driver record
    local driver = MySQL.single.await(
        'SELECT id, reputation_score, reputation_tier, suspended_until FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then
        return false, 'driver_not_found'
    end

    -- Do not modify reputation while suspended (unless lifting suspension)
    if driver.reputation_tier == 'suspended' and points > 0 then
        return false, 'driver_suspended'
    end

    local scoreBefore = driver.reputation_score
    local tierBefore = driver.reputation_tier

    -- Calculate new score (clamp 0-1000)
    local newScore = math.max(0, math.min(1000, scoreBefore + points))
    local newTier = GetReputationTier(newScore)

    -- Check if score hit 0 — trigger suspension
    if newScore <= 0 then
        SuspendDriver(citizenid)
        newScore = 0
        newTier = 'suspended'
    end

    -- Update driver record
    MySQL.update.await(
        'UPDATE truck_drivers SET reputation_score = ?, reputation_tier = ? WHERE citizenid = ?',
        { newScore, newTier, citizenid }
    )

    -- Fetch BOL number for logging if bolId provided
    local bolNumber = nil
    if bolId then
        local bol = MySQL.single.await(
            'SELECT bol_number FROM truck_bols WHERE id = ?',
            { bolId }
        )
        if bol then
            bolNumber = bol.bol_number
        end
    end

    -- Log the reputation change
    MySQL.insert.await([[
        INSERT INTO truck_driver_reputation_log
        (driver_id, citizenid, change_type, points_before, points_change,
         points_after, tier_before, tier_after, bol_id, bol_number,
         tier_of_load, occurred_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        driver.id, citizenid, changeType,
        scoreBefore, points, newScore,
        tierBefore, newTier,
        bolId, bolNumber, tierOfLoad,
        os.time()
    })

    -- Notify player of tier transition if changed
    if tierBefore ~= newTier then
        local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
        if playerSrc then
            if points > 0 then
                lib.notify(playerSrc, {
                    title = 'Reputation Promoted',
                    description = ('Advanced to %s tier'):format(newTier),
                    type = 'success',
                })
            else
                lib.notify(playerSrc, {
                    title = 'Reputation Demoted',
                    description = ('Dropped to %s tier'):format(newTier),
                    type = 'error',
                })
            end
        end
    end

    return true
end

--- Check if a player's reputation tier allows access to the requested load tier
---@param citizenid string Driver's citizen ID
---@param loadTier number The tier of the load being requested (0-3)
---@return boolean allowed
---@return string|nil reason
function CheckBoardAccess(citizenid, loadTier)
    if not citizenid or not loadTier then
        return false, 'missing_parameters'
    end

    local driver = MySQL.single.await(
        'SELECT reputation_score, reputation_tier, suspended_until FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then
        return false, 'driver_not_found'
    end

    -- Check suspension
    if driver.reputation_tier == 'suspended' then
        if driver.suspended_until and os.time() < driver.suspended_until then
            return false, 'suspended'
        end
    end

    local maxTier = TierBoardAccess[driver.reputation_tier]
    if not maxTier then
        return false, 'invalid_tier'
    end

    if loadTier > maxTier then
        return false, 'tier_too_high'
    end

    return true
end

-- ─────────────────────────────────────────────
-- DRIVER REPUTATION — DELIVERY HANDLER
-- ─────────────────────────────────────────────

--- Award reputation points for a successful delivery
--- Includes base points for tier + conditional bonuses
---@param citizenid string Driver's citizen ID
---@param bolRecord table The BOL database record
---@param activeLoad table The active load record
---@return number totalPoints Total points awarded
function HandleDeliveryRep(citizenid, bolRecord, activeLoad)
    if not citizenid or not bolRecord or not activeLoad then
        return 0
    end

    local tier = bolRecord.tier or 0
    local totalPoints = 0

    -- Base delivery points by tier
    local isMilitary = (bolRecord.cargo_type == 'military')
    local baseTier = isMilitary and 4 or tier
    local basePoints = DeliveryRepPoints[baseTier] or DeliveryRepPoints[0]
    totalPoints = totalPoints + basePoints

    -- Full compliance bonus: weigh station stamped + seal intact + manifest verified + pre-trip
    local fullCompliance = true
    if bolRecord.weigh_station_stamp ~= 1 and bolRecord.weigh_station_stamp ~= true then
        fullCompliance = false
    end
    if bolRecord.seal_status ~= 'delivered_intact' and bolRecord.seal_status ~= 'not_applied' then
        fullCompliance = false
    end
    if not bolRecord.manifest_verified or bolRecord.manifest_verified == 0 then
        fullCompliance = false
    end
    if not bolRecord.pre_trip_completed or bolRecord.pre_trip_completed == 0 then
        fullCompliance = false
    end
    if fullCompliance then
        totalPoints = totalPoints + BonusRepPoints.full_compliance
    end

    -- Cold chain clean bonus: temp compliance is 'clean' (no excursions)
    if bolRecord.temp_compliance == 'clean' then
        totalPoints = totalPoints + BonusRepPoints.cold_chain_clean
    end

    -- Livestock excellent bonus: welfare rating 5
    if bolRecord.welfare_final_rating and bolRecord.welfare_final_rating >= 5 then
        totalPoints = totalPoints + BonusRepPoints.livestock_excellent
    end

    -- Apply the total reputation gain
    UpdateDriverReputation(citizenid, 'delivery', totalPoints, bolRecord.id, tier)

    return totalPoints
end

-- ─────────────────────────────────────────────
-- DRIVER REPUTATION — FAILURE HANDLER
-- ─────────────────────────────────────────────

--- Deduct reputation points for a failure event, scaled by tier and event type
---@param citizenid string Driver's citizen ID
---@param eventType string The failure event type (robbery, integrity_fail, abandonment, window_expired, seal_break, hazmat_routing)
---@param tier number The load tier (0-3, or 4 for military)
---@param bolId number|nil Associated BOL ID
---@return number pointsLost Points deducted (as positive number)
function HandleFailureRep(citizenid, eventType, tier, bolId)
    if not citizenid or not eventType or not tier then
        return 0
    end

    local penaltyTable = FailureRepPenalties[eventType]
    if not penaltyTable then
        print(('[trucking:reputation] WARNING: Unknown failure event type: %s'):format(eventType))
        return 0
    end

    local penalty = penaltyTable[tier]
    if not penalty then
        -- Event not applicable for this tier (e.g., seal_break on T0)
        return 0
    end

    -- Apply as negative points
    UpdateDriverReputation(citizenid, eventType, -penalty, bolId, tier)

    return penalty
end

-- ─────────────────────────────────────────────
-- DRIVER SUSPENSION
-- ─────────────────────────────────────────────

--- Suspend a driver for 24 hours (score drops to 0)
---@param citizenid string Driver's citizen ID
---@return boolean success
function SuspendDriver(citizenid)
    if not citizenid then return false end

    local suspendUntil = os.time() + 86400  -- +24 hours

    MySQL.update.await([[
        UPDATE truck_drivers
        SET reputation_score = 0,
            reputation_tier = 'suspended',
            suspended_until = ?
        WHERE citizenid = ?
    ]], { suspendUntil, citizenid })

    -- Notify player if online
    local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if playerSrc then
        lib.notify(playerSrc, {
            title = 'License Suspended',
            description = 'Your trucking privileges have been suspended for 24 hours.',
            type = 'error',
        })
    end

    print(('[trucking:reputation] Driver %s suspended until %d'):format(citizenid, suspendUntil))
    return true
end

--- Lift a driver's suspension (called by maintenance thread)
--- Sets score to 1 and tier to restricted so they can rebuild
---@param citizenid string Driver's citizen ID
---@return boolean success
function LiftSuspension(citizenid)
    if not citizenid then return false end

    MySQL.update.await([[
        UPDATE truck_drivers
        SET reputation_score = 1,
            reputation_tier = 'restricted',
            suspended_until = NULL
        WHERE citizenid = ?
    ]], { citizenid })

    -- Notify player if online
    local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if playerSrc then
        lib.notify(playerSrc, {
            title = 'Suspension Lifted',
            description = 'Your trucking privileges have been restored at restricted tier.',
            type = 'inform',
        })
    end

    print(('[trucking:reputation] Suspension lifted for driver %s'):format(citizenid))
    return true
end

-- ─────────────────────────────────────────────
-- SUSPENSION MAINTENANCE THREAD
-- Runs every 60 seconds, lifts expired suspensions
-- ─────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()

        local suspended = MySQL.query.await([[
            SELECT citizenid FROM truck_drivers
            WHERE reputation_tier = 'suspended'
              AND suspended_until IS NOT NULL
              AND suspended_until <= ?
        ]], { now })

        if suspended then
            for _, row in ipairs(suspended) do
                LiftSuspension(row.citizenid)
            end
        end
    end
end)

-- ─────────────────────────────────────────────
-- SHIPPER REPUTATION — CORE FUNCTIONS
-- ─────────────────────────────────────────────

--- Determine the shipper reputation tier for a given score
---@param score number The shipper reputation score
---@return string tier The tier name
function GetShipperRepTier(score)
    if not score or type(score) ~= 'number' then
        return 'unknown'
    end
    for _, entry in ipairs(ShipperTierThresholds) do
        if score >= entry.min then
            return entry.tier
        end
    end
    return 'unknown'
end

--- Update a driver's reputation with a specific shipper
---@param citizenid string Driver's citizen ID
---@param shipperId string Shipper identifier
---@param changeType string Description of the change
---@param points number Points to add (positive) or subtract (negative)
---@param bolId number|nil Associated BOL ID
---@return boolean success
---@return string|nil error
function UpdateShipperRep(citizenid, shipperId, changeType, points, bolId)
    if not citizenid or not shipperId or not changeType or not points then
        return false, 'missing_parameters'
    end

    -- Fetch driver record for driver_id
    local driver = MySQL.single.await(
        'SELECT id FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then
        return false, 'driver_not_found'
    end

    -- Fetch or create shipper reputation record
    local shipperRep = MySQL.single.await(
        'SELECT * FROM truck_shipper_reputation WHERE driver_id = ? AND shipper_id = ?',
        { driver.id, shipperId }
    )

    if not shipperRep then
        -- Create new record
        MySQL.insert.await([[
            INSERT INTO truck_shipper_reputation
            (driver_id, citizenid, shipper_id, points, tier, deliveries_completed,
             current_clean_streak, last_delivery_at)
            VALUES (?, ?, ?, 0, 'unknown', 0, 0, NULL)
        ]], { driver.id, citizenid, shipperId })

        shipperRep = MySQL.single.await(
            'SELECT * FROM truck_shipper_reputation WHERE driver_id = ? AND shipper_id = ?',
            { driver.id, shipperId }
        )
        if not shipperRep then
            return false, 'failed_to_create_record'
        end
    end

    -- Blacklisted drivers cannot gain rep with that shipper
    if shipperRep.tier == 'blacklisted' and points > 0 then
        return false, 'blacklisted'
    end

    local scoreBefore = shipperRep.points
    local tierBefore = shipperRep.tier

    -- Calculate new score (clamp 0-1000)
    local newScore = math.max(0, math.min(1000, scoreBefore + points))
    local newTier = GetShipperRepTier(newScore)

    -- Preserve blacklisted status (special case: only cleared via reinstatement)
    if tierBefore == 'blacklisted' then
        newTier = 'blacklisted'
        newScore = 0
    end

    -- Update delivery stats for positive changes (deliveries)
    local updateQuery
    local updateParams
    if points > 0 and changeType == 'delivery' then
        updateQuery = [[
            UPDATE truck_shipper_reputation
            SET points = ?, tier = ?, deliveries_completed = deliveries_completed + 1,
                current_clean_streak = current_clean_streak + 1, last_delivery_at = ?,
                preferred_decay_warned = FALSE
            WHERE driver_id = ? AND shipper_id = ?
        ]]
        updateParams = { newScore, newTier, os.time(), driver.id, shipperId }
    elseif points < 0 then
        -- Negative event resets clean streak
        updateQuery = [[
            UPDATE truck_shipper_reputation
            SET points = ?, tier = ?, current_clean_streak = 0
            WHERE driver_id = ? AND shipper_id = ?
        ]]
        updateParams = { newScore, newTier, driver.id, shipperId }
    else
        updateQuery = [[
            UPDATE truck_shipper_reputation
            SET points = ?, tier = ?
            WHERE driver_id = ? AND shipper_id = ?
        ]]
        updateParams = { newScore, newTier, driver.id, shipperId }
    end

    MySQL.update.await(updateQuery, updateParams)

    -- Log the shipper reputation change
    MySQL.insert.await([[
        INSERT INTO truck_shipper_reputation_log
        (driver_id, citizenid, shipper_id, change_type, points_before,
         points_change, points_after, tier_before, tier_after, bol_id, occurred_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        driver.id, citizenid, shipperId, changeType,
        scoreBefore, points, newScore,
        tierBefore, newTier,
        bolId, os.time()
    })

    -- Notify on tier change
    if tierBefore ~= newTier then
        local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
        if playerSrc then
            local shipperLabel = shipperId
            if Shippers and Shippers[shipperId] then
                shipperLabel = Shippers[shipperId].label or shipperId
            end

            if points > 0 then
                lib.notify(playerSrc, {
                    title = 'Shipper Reputation',
                    description = ('Now %s with %s'):format(newTier, shipperLabel),
                    type = 'success',
                })
            else
                lib.notify(playerSrc, {
                    title = 'Shipper Reputation',
                    description = ('Dropped to %s with %s'):format(newTier, shipperLabel),
                    type = 'error',
                })
            end
        end
    end

    return true
end

--- Check if a driver meets the shipper rep tier for a load
---@param citizenid string Driver's citizen ID
---@param shipperId string Shipper identifier
---@param requiredTier string Required shipper tier name
---@return boolean allowed
function CheckShipperAccess(citizenid, shipperId, requiredTier)
    if not citizenid or not shipperId then return false end
    if not requiredTier or requiredTier == 'unknown' then return true end

    local driver = MySQL.single.await(
        'SELECT id FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then return false end

    local shipperRep = MySQL.single.await(
        'SELECT tier FROM truck_shipper_reputation WHERE driver_id = ? AND shipper_id = ?',
        { driver.id, shipperId }
    )

    if not shipperRep then return false end
    if shipperRep.tier == 'blacklisted' then return false end

    -- Build tier hierarchy for comparison
    local tierOrder = {
        unknown = 0,
        familiar = 1,
        established = 2,
        trusted = 3,
        preferred = 4,
    }

    local currentLevel = tierOrder[shipperRep.tier] or 0
    local requiredLevel = tierOrder[requiredTier] or 0

    return currentLevel >= requiredLevel
end

-- ─────────────────────────────────────────────
-- PREFERRED DECAY CHECK
-- Called by maintenance thread — decays preferred tier
-- after 14 days of inactivity with that shipper
-- ─────────────────────────────────────────────

--- Check and process preferred tier decay for all shippers
--- Preferred status decays to trusted after 14 days with no deliveries
---@return number decayed Count of records decayed
function CheckPreferredDecay()
    local decayThreshold = os.time() - 1209600  -- 14 days in seconds
    local count = 0

    -- First pass: warn drivers approaching decay (haven't been warned yet)
    local warnable = MySQL.query.await([[
        SELECT sr.citizenid, sr.shipper_id
        FROM truck_shipper_reputation sr
        WHERE sr.tier = 'preferred'
          AND sr.last_delivery_at < ?
          AND sr.preferred_decay_warned = FALSE
    ]], { os.time() - 1036800 })  -- 12 days — warn 2 days early

    if warnable then
        for _, row in ipairs(warnable) do
            MySQL.update.await([[
                UPDATE truck_shipper_reputation
                SET preferred_decay_warned = TRUE
                WHERE citizenid = ? AND shipper_id = ?
            ]], { row.citizenid, row.shipper_id })

            local playerSrc = exports.qbx_core:GetPlayerByCitizenId(row.citizenid)
            if playerSrc then
                local shipperLabel = row.shipper_id
                if Shippers and Shippers[row.shipper_id] then
                    shipperLabel = Shippers[row.shipper_id].label or row.shipper_id
                end
                lib.notify(playerSrc, {
                    title = 'Shipper Warning',
                    description = ('Preferred status with %s will decay in 2 days'):format(shipperLabel),
                    type = 'inform',
                })
            end
        end
    end

    -- Second pass: actually decay those past 14 days AND already warned
    local decayable = MySQL.query.await([[
        SELECT sr.driver_id, sr.citizenid, sr.shipper_id, sr.points
        FROM truck_shipper_reputation sr
        WHERE sr.tier = 'preferred'
          AND sr.last_delivery_at < ?
          AND sr.preferred_decay_warned = TRUE
    ]], { decayThreshold })

    if decayable then
        for _, row in ipairs(decayable) do
            -- Cap points at 699 (just below preferred threshold) and set tier to trusted
            local newPoints = math.min(row.points, 699)
            MySQL.update.await([[
                UPDATE truck_shipper_reputation
                SET tier = 'trusted', points = ?, preferred_decay_warned = FALSE
                WHERE driver_id = ? AND shipper_id = ?
            ]], { newPoints, row.driver_id, row.shipper_id })

            -- Log the decay
            MySQL.insert.await([[
                INSERT INTO truck_shipper_reputation_log
                (driver_id, citizenid, shipper_id, change_type, points_before,
                 points_change, points_after, tier_before, tier_after, bol_id, occurred_at)
                VALUES (?, ?, ?, 'preferred_decay', ?, ?, ?, 'preferred', 'trusted', NULL, ?)
            ]], {
                row.driver_id, row.citizenid, row.shipper_id,
                row.points, newPoints - row.points, newPoints,
                os.time()
            })

            count = count + 1
        end
    end

    if count > 0 then
        print(('[trucking:reputation] Preferred decay processed: %d records'):format(count))
    end

    return count
end

-- ─────────────────────────────────────────────
-- CLUSTER FRICTION
-- When a driver damages reputation with one shipper,
-- reduce the progression rate with all cluster partners
-- by 10-15%
-- ─────────────────────────────────────────────

--- Apply cluster friction to all shippers in the same cluster as the damaged shipper
--- Reduces progression rate by 10-15% (tracked as negative points proportional to friction)
---@param citizenid string Driver's citizen ID
---@param shipperId string The shipper that was damaged
---@param damagePoints number The damage points (positive) applied to the source shipper
---@return number affectedCount Number of cluster partners affected
function ApplyClusterFriction(citizenid, shipperId, damagePoints)
    if not citizenid or not shipperId or not damagePoints or damagePoints <= 0 then
        return 0
    end

    -- Determine the cluster of the damaged shipper
    if not Shippers or not Shippers[shipperId] then
        return 0
    end

    local cluster = Shippers[shipperId].cluster
    if not cluster or not ShipperClusters[cluster] then
        return 0
    end

    -- Calculate friction amount: 10-15% of the damage, randomized
    local frictionPct = CLUSTER_FRICTION_MIN + (math.random() * (CLUSTER_FRICTION_MAX - CLUSTER_FRICTION_MIN))
    local frictionPoints = math.floor(damagePoints * frictionPct)
    if frictionPoints < 1 then
        frictionPoints = 1
    end

    local driver = MySQL.single.await(
        'SELECT id FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then return 0 end

    local affectedCount = 0

    -- Find all other shippers in the same cluster
    for otherShipperId, shipperDef in pairs(Shippers) do
        if otherShipperId ~= shipperId and shipperDef.cluster == cluster then
            -- Only apply friction if the driver has an existing relationship
            local existingRep = MySQL.single.await(
                'SELECT id, points, tier FROM truck_shipper_reputation WHERE driver_id = ? AND shipper_id = ?',
                { driver.id, otherShipperId }
            )

            if existingRep and existingRep.points > 0 and existingRep.tier ~= 'blacklisted' then
                local newPoints = math.max(0, existingRep.points - frictionPoints)
                local newTier = GetShipperRepTier(newPoints)

                MySQL.update.await(
                    'UPDATE truck_shipper_reputation SET points = ?, tier = ? WHERE id = ?',
                    { newPoints, newTier, existingRep.id }
                )

                -- Log friction event
                MySQL.insert.await([[
                    INSERT INTO truck_shipper_reputation_log
                    (driver_id, citizenid, shipper_id, change_type, points_before,
                     points_change, points_after, tier_before, tier_after, bol_id, occurred_at)
                    VALUES (?, ?, ?, 'cluster_friction', ?, ?, ?, ?, ?, NULL, ?)
                ]], {
                    driver.id, citizenid, otherShipperId,
                    existingRep.points, -frictionPoints, newPoints,
                    existingRep.tier, newTier,
                    os.time()
                })

                affectedCount = affectedCount + 1
            end
        end
    end

    if affectedCount > 0 then
        print(('[trucking:reputation] Cluster friction applied: %d partners in %s cluster for driver %s'):format(
            affectedCount, cluster, citizenid))
    end

    return affectedCount
end

-- ─────────────────────────────────────────────
-- PREFERRED DECAY MAINTENANCE THREAD
-- Runs every 15 minutes alongside the main maintenance loop
-- ─────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(900000)  -- 15 minutes
        CheckPreferredDecay()
    end
end)

print('[trucking:reputation] Reputation system initialized')
