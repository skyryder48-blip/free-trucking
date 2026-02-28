--[[
    server/exports.lua — All Exported Server Functions (Section 29)
    Provides a clean public API for external resources to query trucking state.
    Each export delegates to the actual implementation in its respective module.
]]

-- ─────────────────────────────────────────────
-- LICENSE AND CERTIFICATION EXPORTS
-- ─────────────────────────────────────────────

--- Check if a player has an active trucking license of a given type
---@param citizenid string Player's citizen ID
---@param licenseType string License type: 'class_b', 'class_a', 'tanker', 'hazmat', 'oversized_monthly'
---@return table|nil result { active = bool, issued_at = int, expires_at = int|nil } or nil
exports('GetDriverLicense', function(citizenid, licenseType)
    if not citizenid or not licenseType then return nil end

    local license = MySQL.single.await([[
        SELECT status, issued_at, expires_at, locked_until
        FROM truck_licenses
        WHERE citizenid = ? AND license_type = ?
        ORDER BY issued_at DESC LIMIT 1
    ]], { citizenid, licenseType })

    if not license then return nil end

    local now = GetServerTime()
    local isActive = license.status == 'active'

    -- Check if license is time-locked (failed test cooldown)
    if license.locked_until and license.locked_until > now then
        isActive = false
    end

    -- Check expiration (for monthly licenses)
    if license.expires_at and license.expires_at < now then
        isActive = false
    end

    return {
        active      = isActive,
        status      = license.status,
        issued_at   = license.issued_at,
        expires_at  = license.expires_at,
        locked_until = license.locked_until,
    }
end)

--- Check if a player has an active certification of a given type
---@param citizenid string Player's citizen ID
---@param certType string Cert type: 'bilkington_carrier', 'high_value', 'government_clearance'
---@return table|nil result { active = bool, status = string } or nil
exports('GetDriverCertification', function(citizenid, certType)
    if not citizenid or not certType then return nil end

    local cert = MySQL.single.await([[
        SELECT status, issued_at, expires_at, revoked_reason, reinstatement_eligible
        FROM truck_certifications
        WHERE citizenid = ? AND cert_type = ?
        ORDER BY issued_at DESC LIMIT 1
    ]], { citizenid, certType })

    if not cert then return nil end

    local now = GetServerTime()
    local isActive = cert.status == 'active'

    -- Check expiration
    if cert.expires_at and cert.expires_at < now then
        isActive = false
    end

    return {
        active                  = isActive,
        status                  = cert.status,
        issued_at               = cert.issued_at,
        expires_at              = cert.expires_at,
        revoked_reason          = cert.revoked_reason,
        reinstatement_eligible  = cert.reinstatement_eligible,
    }
end)

-- ─────────────────────────────────────────────
-- REPUTATION EXPORTS
-- ─────────────────────────────────────────────

--- Get a driver's overall reputation score and tier
---@param citizenid string Player's citizen ID
---@return table|nil result { score = int, tier = string } or nil
exports('GetDriverReputationScore', function(citizenid)
    if not citizenid then return nil end

    local driver = MySQL.single.await([[
        SELECT reputation_score, reputation_tier, suspended_until
        FROM truck_drivers
        WHERE citizenid = ?
    ]], { citizenid })

    if not driver then return nil end

    return {
        score           = driver.reputation_score,
        tier            = driver.reputation_tier,
        suspended_until = driver.suspended_until,
    }
end)

--- Get a driver's reputation with a specific shipper
---@param citizenid string Player's citizen ID
---@param shipperId string Shipper identifier
---@return table|nil result { tier = string, points = int } or nil
exports('GetShipperReputation', function(citizenid, shipperId)
    if not citizenid or not shipperId then return nil end

    local rep = MySQL.single.await([[
        SELECT tier, points, deliveries_completed, current_clean_streak,
               last_delivery_at, blacklisted_at, reinstatement_eligible
        FROM truck_shipper_reputation
        WHERE citizenid = ? AND shipper_id = ?
    ]], { citizenid, shipperId })

    if not rep then
        return { tier = 'unknown', points = 0 }
    end

    return {
        tier                    = rep.tier,
        points                  = rep.points,
        deliveries_completed    = rep.deliveries_completed,
        current_clean_streak    = rep.current_clean_streak,
        last_delivery_at        = rep.last_delivery_at,
        blacklisted_at          = rep.blacklisted_at,
        reinstatement_eligible  = rep.reinstatement_eligible,
    }
end)

-- ─────────────────────────────────────────────
-- ACTIVE LOAD EXPORT
-- ─────────────────────────────────────────────

--- Check if a driver has an active load and return its data
---@param citizenid string Player's citizen ID
---@return table|nil activeLoad Active load data or nil
exports('GetActiveLoad', function(citizenid)
    if not citizenid then return nil end

    -- Check in-memory first (fastest path)
    if ActiveLoads then
        for id, load in pairs(ActiveLoads) do
            if load.citizenid == citizenid then
                return {
                    id                  = id,
                    load_id             = load.load_id,
                    bol_id              = load.bol_id,
                    bol_number          = load.bol_number,
                    citizenid           = load.citizenid,
                    status              = load.status,
                    cargo_type          = load.cargo_type,
                    is_leon             = load.is_leon or false,
                    is_military         = load.is_military or false,
                    payout              = load.payout or load.estimated_payout,
                    accepted_at         = load.accepted_at,
                    window_expires      = load.window_expires,
                }
            end
        end
    end

    -- Fallback to database
    local activeLoad = MySQL.single.await([[
        SELECT al.*, l.bol_number, l.cargo_type, l.is_leon_load
        FROM truck_active_loads al
        JOIN truck_loads l ON al.load_id = l.id
        WHERE al.citizenid = ?
        LIMIT 1
    ]], { citizenid })

    if not activeLoad then return nil end

    return {
        id              = activeLoad.id,
        load_id         = activeLoad.load_id,
        bol_id          = activeLoad.bol_id,
        bol_number      = activeLoad.bol_number,
        citizenid       = activeLoad.citizenid,
        status          = activeLoad.status,
        cargo_type      = activeLoad.cargo_type,
        is_leon         = activeLoad.is_leon_load or false,
        is_military     = activeLoad.cargo_type == 'military',
        payout          = activeLoad.estimated_payout,
        accepted_at     = activeLoad.accepted_at,
        window_expires  = activeLoad.window_expires_at,
    }
end)

-- ─────────────────────────────────────────────
-- FLAMMABLE VEHICLE EXPORTS
-- ─────────────────────────────────────────────

--- Check if a vehicle plate is registered as flammable
---@param plate string Vehicle license plate
---@return boolean isFlammable
exports('IsFlammableVehicle', function(plate)
    if not plate then return false end
    -- Delegate to explosions.lua
    if IsFlammableVehicle then
        return IsFlammableVehicle(plate)
    end
    return false
end)

--- Get the flammable vehicle data for a plate
---@param plate string Vehicle license plate
---@return table|nil data { profile = string, fill_level = float } or nil
exports('GetFlammableVehicleData', function(plate)
    if not plate then return nil end
    -- Delegate to explosions.lua
    if GetFlammableVehicleData then
        return GetFlammableVehicleData(plate)
    end
    return nil
end)

--- Register an external vehicle as flammable for enhanced explosion tracking
---@param plate string Vehicle license plate
---@param data table { profile, fill_level, cargo_type }
exports('RegisterFlammableVehicle', function(plate, data)
    if not plate or not data then return false end
    -- Delegate to explosions.lua
    if RegisterFlammableVehicle then
        return RegisterFlammableVehicle(plate, data)
    end
    return false
end)

--- Deregister a flammable vehicle
---@param plate string Vehicle license plate
exports('DeregisterFlammableVehicle', function(plate)
    if not plate then return false end
    -- Delegate to explosions.lua
    if DeregisterFlammableVehicle then
        return DeregisterFlammableVehicle(plate)
    end
    return false
end)

-- ─────────────────────────────────────────────
-- LEON EXPORT
-- ─────────────────────────────────────────────

--- Register a custom Leon load type from an external resource
---@param loadTypeData table { supplier_id, label, risk_tier, fee_range, payout_range, delivery_event }
exports('RegisterLeonLoadType', function(loadTypeData)
    if not loadTypeData then return false end
    -- Delegate to leon.lua
    if RegisterLeonLoadType then
        return RegisterLeonLoadType(loadTypeData)
    end
    return false
end)

-- ─────────────────────────────────────────────
-- REPUTATION EVENT EXPORT
-- ─────────────────────────────────────────────

--- Trigger a reputation event from an external resource
---@param citizenid string Player's citizen ID
---@param eventType string Event type matching change_type values
---@param context table|nil { bol_number, tier_of_load, notes }
exports('TriggerReputationEvent', function(citizenid, eventType, context)
    if not citizenid or not eventType then return false end

    context = context or {}

    -- Get current driver data
    local driver = MySQL.single.await([[
        SELECT id, reputation_score, reputation_tier FROM truck_drivers
        WHERE citizenid = ?
    ]], { citizenid })

    if not driver then
        print(('[Trucking Exports] TriggerReputationEvent: driver not found for %s'):format(citizenid))
        return false
    end

    -- Define reputation changes by event type
    local repChanges = {
        -- Positive events
        tier0_delivery      = 8,
        tier1_delivery      = 15,
        tier2_delivery      = 25,
        tier3_delivery      = 40,
        military_delivery   = 60,
        full_compliance     = 5,
        supplier_contract   = 20,
        cold_chain_clean    = 8,
        livestock_excellent = 10,

        -- Negative events
        robbery             = -100,
        integrity_fail      = -40,
        abandonment         = -50,
        window_expired      = -20,
        seal_break          = -15,
        hazmat_routing      = -40,
        military_long_con   = -(Config.LongConReputationHit or 400),
    }

    -- Scale negative events by tier if context provides it
    local tierScaling = {
        [0] = 0.3,
        [1] = 0.6,
        [2] = 1.0,
        [3] = 1.8,
    }

    local baseChange = repChanges[eventType]
    if not baseChange then
        print(('[Trucking Exports] Unknown reputation event type: %s'):format(eventType))
        return false
    end

    -- Apply tier scaling for negative events
    local pointsChange = baseChange
    if baseChange < 0 and context.tier_of_load then
        local scale = tierScaling[context.tier_of_load] or 1.0
        pointsChange = math.floor(baseChange * scale)
    end

    local newScore = math.max(0, math.min(1200, driver.reputation_score + pointsChange))

    -- Determine new tier
    local newTier = 'suspended'
    if newScore >= 1000 then newTier = 'elite'
    elseif newScore >= 800 then newTier = 'professional'
    elseif newScore >= 600 then newTier = 'established'
    elseif newScore >= 400 then newTier = 'developing'
    elseif newScore >= 200 then newTier = 'probationary'
    elseif newScore >= 1 then newTier = 'restricted'
    end

    -- Handle suspension
    local suspendedUntil = nil
    if newScore == 0 then
        suspendedUntil = GetServerTime() + 86400 -- 24-hour lockout
    end

    -- Update driver record
    MySQL.update.await([[
        UPDATE truck_drivers
        SET reputation_score = ?,
            reputation_tier = ?,
            suspended_until = COALESCE(?, suspended_until)
        WHERE citizenid = ?
    ]], { newScore, newTier, suspendedUntil, citizenid })

    -- Log the change
    MySQL.insert([[
        INSERT INTO truck_driver_reputation_log
        (driver_id, citizenid, change_type, points_before, points_change,
         points_after, tier_before, tier_after, bol_number, tier_of_load, occurred_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        driver.id,
        citizenid,
        eventType,
        driver.reputation_score,
        pointsChange,
        newScore,
        driver.reputation_tier,
        newTier,
        context.bol_number,
        context.tier_of_load,
        GetServerTime(),
    })

    -- Notify player if online
    local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if playerSrc then
        local src = type(playerSrc) == 'number' and playerSrc or nil
        if src then
            TriggerClientEvent('trucking:client:reputationUpdate', src, {
                score   = newScore,
                tier    = newTier,
                change  = pointsChange,
                reason  = eventType,
            })
        end
    end

    return true
end)
