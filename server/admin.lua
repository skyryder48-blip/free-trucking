--[[
    server/admin.lua — Admin Panel (Section 30)
    Provides /truckadmin command and server event handlers for all admin
    operations: player lookup, reputation adjustment, load management,
    economy controls, insurance oversight, and audit logging.

    All actions require ace permission (group.admin) and are logged
    via LogAdminAction webhook.
]]

-- ─────────────────────────────────────────────
-- ADMIN PERMISSION CHECK
-- ─────────────────────────────────────────────

--- Check if a player has admin permission
---@param src number Player server ID
---@return boolean isAdmin
function IsPlayerAdmin(src)
    if not src or src <= 0 then return false end
    return IsPlayerAceAllowed(src, 'group.admin')
end

-- ─────────────────────────────────────────────
-- ADMIN COMMAND
-- ─────────────────────────────────────────────

lib.addCommand('truckadmin', {
    help = 'Open trucking admin panel',
    restricted = 'group.admin',
}, function(source, args)
    local src = source
    if not IsPlayerAdmin(src) then
        lib.notify(src, {
            title       = 'Access Denied',
            description = 'You do not have permission to use this command.',
            type        = 'error',
        })
        return
    end

    TriggerClientEvent('trucking:client:openAdminPanel', src)
end)

-- ─────────────────────────────────────────────
-- PLAYER LOOKUP
-- ─────────────────────────────────────────────

--- Look up a player by citizenid or name
---@param searchTerm string Citizenid or player name
---@return table|nil profile Full player profile or nil
local function PlayerLookup(searchTerm)
    if not searchTerm or searchTerm == '' then return nil end

    -- Try citizenid first (exact match)
    local driver = MySQL.single.await([[
        SELECT * FROM truck_drivers WHERE citizenid = ?
    ]], { searchTerm })

    -- If not found, try name search (partial match)
    if not driver then
        driver = MySQL.single.await([[
            SELECT * FROM truck_drivers WHERE player_name LIKE ?
        ]], { '%' .. searchTerm .. '%' })
    end

    if not driver then return nil end

    local citizenid = driver.citizenid

    -- Fetch licenses
    local licenses = MySQL.query.await([[
        SELECT license_type, status, issued_at, expires_at, locked_until, written_test_attempts
        FROM truck_licenses WHERE citizenid = ? ORDER BY issued_at DESC
    ]], { citizenid }) or {}

    -- Fetch certifications
    local certifications = MySQL.query.await([[
        SELECT cert_type, status, issued_at, expires_at, revoked_reason, reinstatement_eligible
        FROM truck_certifications WHERE citizenid = ? ORDER BY issued_at DESC
    ]], { citizenid }) or {}

    -- Fetch active load
    local activeLoad = MySQL.single.await([[
        SELECT al.*, l.bol_number, l.cargo_type, l.is_leon_load, l.tier,
               l.origin_label, l.destination_label
        FROM truck_active_loads al
        JOIN truck_loads l ON al.load_id = l.id
        WHERE al.citizenid = ?
    ]], { citizenid })

    -- Fetch shipper reputations
    local shipperReps = MySQL.query.await([[
        SELECT shipper_id, tier, points, deliveries_completed, current_clean_streak
        FROM truck_shipper_reputation WHERE citizenid = ? ORDER BY points DESC
    ]], { citizenid }) or {}

    -- Fetch BOL history (last 20)
    local bolHistory = MySQL.query.await([[
        SELECT bol_number, cargo_type, bol_status, final_payout, is_leon,
               origin_label, destination_label, issued_at, delivered_at
        FROM truck_bols WHERE citizenid = ?
        ORDER BY issued_at DESC LIMIT 20
    ]], { citizenid }) or {}

    -- Fetch reputation log (last 20)
    local repLog = MySQL.query.await([[
        SELECT change_type, points_before, points_change, points_after,
               tier_before, tier_after, bol_number, occurred_at
        FROM truck_driver_reputation_log WHERE citizenid = ?
        ORDER BY occurred_at DESC LIMIT 20
    ]], { citizenid }) or {}

    return {
        driver          = driver,
        licenses        = licenses,
        certifications  = certifications,
        active_load     = activeLoad,
        shipper_reps    = shipperReps,
        bol_history     = bolHistory,
        rep_log         = repLog,
    }
end

--- Player lookup event handler
RegisterNetEvent('trucking:server:admin:playerLookup', function(searchTerm)
    local src = source
    if not IsPlayerAdmin(src) then return end
    if not searchTerm then return end

    local profile = PlayerLookup(searchTerm)

    if profile then
        TriggerClientEvent('trucking:client:adminPlayerProfile', src, profile)
    else
        lib.notify(src, {
            title       = 'Admin',
            description = 'Player not found: ' .. tostring(searchTerm),
            type        = 'error',
        })
    end
end)

-- ─────────────────────────────────────────────
-- REPUTATION ADJUSTMENT
-- ─────────────────────────────────────────────

--- Adjust a player's reputation score with reason logging
RegisterNetEvent('trucking:server:admin:adjustReputation', function(citizenid, change, reason)
    local src = source
    if not IsPlayerAdmin(src) then return end
    if not citizenid or not change then return end

    change = tonumber(change)
    if not change then return end
    reason = reason or 'Admin adjustment'

    -- Get current state
    local driver = MySQL.single.await([[
        SELECT id, reputation_score, reputation_tier FROM truck_drivers
        WHERE citizenid = ?
    ]], { citizenid })

    if not driver then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Driver not found.',
            type        = 'error',
        })
        return
    end

    local newScore = math.max(0, math.min(1200, driver.reputation_score + change))

    -- Determine new tier
    local newTier = 'suspended'
    if newScore >= 1000 then newTier = 'elite'
    elseif newScore >= 800 then newTier = 'professional'
    elseif newScore >= 600 then newTier = 'established'
    elseif newScore >= 400 then newTier = 'developing'
    elseif newScore >= 200 then newTier = 'probationary'
    elseif newScore >= 1 then newTier = 'restricted'
    end

    -- Update database
    MySQL.update.await([[
        UPDATE truck_drivers SET reputation_score = ?, reputation_tier = ?
        WHERE citizenid = ?
    ]], { newScore, newTier, citizenid })

    -- Log the change
    MySQL.insert([[
        INSERT INTO truck_driver_reputation_log
        (driver_id, citizenid, change_type, points_before, points_change,
         points_after, tier_before, tier_after, occurred_at)
        VALUES (?, ?, 'admin_adjustment', ?, ?, ?, ?, ?, ?)
    ]], {
        driver.id,
        citizenid,
        driver.reputation_score,
        change,
        newScore,
        driver.reputation_tier,
        newTier,
        os.time(),
    })

    -- Notify target player if online
    local targetSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if targetSrc then
        local tSrc = type(targetSrc) == 'number' and targetSrc or nil
        if tSrc then
            TriggerClientEvent('trucking:client:reputationUpdate', tSrc, {
                score   = newScore,
                tier    = newTier,
                change  = change,
                reason  = 'admin_adjustment',
            })
        end
    end

    LogAdminAction(src, 'adjust_reputation', {
        citizenid   = citizenid,
        change      = change,
        old_score   = driver.reputation_score,
        new_score   = newScore,
        old_tier    = driver.reputation_tier,
        new_tier    = newTier,
        reason      = reason,
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Reputation adjusted: %s %s%d → %d (%s)')
            :format(citizenid, change >= 0 and '+' or '', change, newScore, newTier),
        type        = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- SUSPEND / UNSUSPEND DRIVER
-- ─────────────────────────────────────────────

--- Suspend a driver
RegisterNetEvent('trucking:server:admin:suspendDriver', function(citizenid, durationHours, reason)
    local src = source
    if not IsPlayerAdmin(src) then return end
    if not citizenid then return end

    durationHours = tonumber(durationHours) or 24
    reason = reason or 'Admin suspension'

    local suspendedUntil = os.time() + (durationHours * 3600)

    MySQL.update.await([[
        UPDATE truck_drivers
        SET reputation_tier = 'suspended',
            reputation_score = 0,
            suspended_until = ?
        WHERE citizenid = ?
    ]], { suspendedUntil, citizenid })

    -- Notify target
    local targetSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if targetSrc then
        local tSrc = type(targetSrc) == 'number' and targetSrc or nil
        if tSrc then
            lib.notify(tSrc, {
                title       = 'Trucking License',
                description = ('Your trucking privileges have been suspended for %d hours. Reason: %s')
                    :format(durationHours, reason),
                type        = 'error',
                duration    = 10000,
            })
        end
    end

    LogAdminAction(src, 'suspend_driver', {
        citizenid       = citizenid,
        duration_hours  = durationHours,
        suspended_until = suspendedUntil,
        reason          = reason,
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Driver %s suspended for %d hours.'):format(citizenid, durationHours),
        type        = 'success',
    })
end)

--- Unsuspend a driver
RegisterNetEvent('trucking:server:admin:unsuspendDriver', function(citizenid)
    local src = source
    if not IsPlayerAdmin(src) then return end
    if not citizenid then return end

    MySQL.update.await([[
        UPDATE truck_drivers
        SET reputation_tier = 'restricted',
            reputation_score = 1,
            suspended_until = NULL
        WHERE citizenid = ?
    ]], { citizenid })

    -- Notify target
    local targetSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if targetSrc then
        local tSrc = type(targetSrc) == 'number' and targetSrc or nil
        if tSrc then
            lib.notify(tSrc, {
                title       = 'Trucking License',
                description = 'Your trucking suspension has been lifted.',
                type        = 'success',
            })
        end
    end

    LogAdminAction(src, 'unsuspend_driver', {
        citizenid = citizenid,
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Driver %s unsuspended.'):format(citizenid),
        type        = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- FORCE-COMPLETE ACTIVE LOAD
-- ─────────────────────────────────────────────

--- Force-complete a stuck active load (return deposit, pay floor payout)
RegisterNetEvent('trucking:server:admin:forceComplete', function(bolId, reason)
    local src = source
    if not IsPlayerAdmin(src) then return end

    bolId = tonumber(bolId)
    if not bolId then return end
    reason = reason or 'Admin force-complete'

    -- Find the active load
    local activeLoad = nil
    if ActiveLoads then
        activeLoad = ActiveLoads[bolId]
    end

    -- If not in memory, check database
    if not activeLoad then
        activeLoad = MySQL.single.await([[
            SELECT al.*, l.tier, l.bol_number
            FROM truck_active_loads al
            JOIN truck_loads l ON al.load_id = l.id
            WHERE al.id = ?
        ]], { bolId })
    end

    if not activeLoad then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Active load not found.',
            type        = 'error',
        })
        return
    end

    local citizenid = activeLoad.citizenid
    local tier = activeLoad.tier or 0

    -- Return deposit
    local deposit = MySQL.single.await([[
        SELECT * FROM truck_deposits
        WHERE citizenid = ? AND status = 'held'
        ORDER BY posted_at DESC LIMIT 1
    ]], { citizenid })

    if deposit then
        MySQL.update.await([[
            UPDATE truck_deposits SET status = 'returned', resolved_at = ? WHERE id = ?
        ]], { os.time(), deposit.id })

        local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
        if playerSrc then
            local pSrc = type(playerSrc) == 'number' and playerSrc or nil
            if pSrc then
                local player = exports.qbx_core:GetPlayer(pSrc)
                if player then
                    player.Functions.AddMoney('bank', deposit.amount, 'Deposit returned - admin force-complete')
                end
            end
        end
    end

    -- Pay floor payout
    local basePayout = Config.PayoutFloors and Config.PayoutFloors[tier] or 200
    local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
    if playerSrc then
        local pSrc = type(playerSrc) == 'number' and playerSrc or nil
        if pSrc then
            local player = exports.qbx_core:GetPlayer(pSrc)
            if player then
                player.Functions.AddMoney('bank', basePayout, 'Admin force-complete: ' .. reason)
            end
        end
    end

    -- Update BOL status
    local bolNumber = activeLoad.bol_number or ''
    if bolNumber ~= '' then
        MySQL.update([[
            UPDATE truck_bols
            SET bol_status = 'delivered', delivered_at = ?, final_payout = ?
            WHERE bol_number = ?
        ]], { os.time(), basePayout, bolNumber })
    end

    -- Update load status
    MySQL.update([[
        UPDATE truck_loads SET board_status = 'completed'
        WHERE id = ?
    ]], { activeLoad.load_id })

    -- Remove active load from database
    MySQL.update([[
        DELETE FROM truck_active_loads WHERE id = ?
    ]], { bolId })

    -- Clean up in-memory
    if ActiveLoads then
        ActiveLoads[bolId] = nil
    end

    LogAdminAction(src, 'force_complete', {
        bol_id      = bolId,
        citizenid   = citizenid,
        payout      = basePayout,
        deposit_returned = deposit and deposit.amount or 0,
        reason      = reason,
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Load %s force-completed. Payout: $%d'):format(tostring(bolId), basePayout),
        type        = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- FORCE-ABANDON ACTIVE LOAD
-- ─────────────────────────────────────────────

--- Force-abandon a stuck active load (return deposit, no rep penalty)
RegisterNetEvent('trucking:server:admin:forceAbandon', function(bolId, reason)
    local src = source
    if not IsPlayerAdmin(src) then return end

    bolId = tonumber(bolId)
    if not bolId then return end
    reason = reason or 'Admin force-abandon'

    -- Find the active load
    local activeLoad = nil
    if ActiveLoads then
        activeLoad = ActiveLoads[bolId]
    end

    if not activeLoad then
        activeLoad = MySQL.single.await([[
            SELECT al.*, l.bol_number
            FROM truck_active_loads al
            JOIN truck_loads l ON al.load_id = l.id
            WHERE al.id = ?
        ]], { bolId })
    end

    if not activeLoad then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Active load not found.',
            type        = 'error',
        })
        return
    end

    local citizenid = activeLoad.citizenid

    -- Return deposit
    local deposit = MySQL.single.await([[
        SELECT * FROM truck_deposits
        WHERE citizenid = ? AND status = 'held'
        ORDER BY posted_at DESC LIMIT 1
    ]], { citizenid })

    if deposit then
        MySQL.update.await([[
            UPDATE truck_deposits SET status = 'returned', resolved_at = ? WHERE id = ?
        ]], { os.time(), deposit.id })

        local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
        if playerSrc then
            local pSrc = type(playerSrc) == 'number' and playerSrc or nil
            if pSrc then
                local player = exports.qbx_core:GetPlayer(pSrc)
                if player then
                    player.Functions.AddMoney('bank', deposit.amount, 'Deposit returned - admin force-abandon')
                end
            end
        end
    end

    -- Update BOL status
    local bolNumber = activeLoad.bol_number or ''
    if bolNumber ~= '' then
        MySQL.update([[
            UPDATE truck_bols SET bol_status = 'abandoned' WHERE bol_number = ?
        ]], { bolNumber })
    end

    -- Update load status
    MySQL.update([[
        UPDATE truck_loads SET board_status = 'expired'
        WHERE id = ?
    ]], { activeLoad.load_id })

    -- Remove active load
    MySQL.update([[
        DELETE FROM truck_active_loads WHERE id = ?
    ]], { bolId })

    -- Clean up in-memory
    if ActiveLoads then
        ActiveLoads[bolId] = nil
    end

    LogAdminAction(src, 'force_abandon', {
        bol_id      = bolId,
        citizenid   = citizenid,
        deposit_returned = deposit and deposit.amount or 0,
        reason      = reason,
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Load %s force-abandoned. No rep penalty.'):format(tostring(bolId)),
        type        = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- ECONOMY CONTROLS
-- ─────────────────────────────────────────────

--- Live adjustment of Economy.ServerMultiplier
RegisterNetEvent('trucking:server:admin:setServerMultiplier', function(multiplier)
    local src = source
    if not IsPlayerAdmin(src) then return end

    multiplier = tonumber(multiplier)
    if not multiplier or multiplier < 0.1 or multiplier > 5.0 then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Invalid multiplier. Must be between 0.1 and 5.0.',
            type        = 'error',
        })
        return
    end

    local oldMultiplier = Economy and Economy.ServerMultiplier or 1.0
    if Economy then
        Economy.ServerMultiplier = multiplier
    end

    LogAdminAction(src, 'set_server_multiplier', {
        old_multiplier = oldMultiplier,
        new_multiplier = multiplier,
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Server multiplier updated: %.2f → %.2f'):format(oldMultiplier, multiplier),
        type        = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- SURGE MANAGEMENT
-- ─────────────────────────────────────────────

--- Manual surge creation
RegisterNetEvent('trucking:server:admin:createSurge', function(data)
    local src = source
    if not IsPlayerAdmin(src) then return end

    if not data or not data.region or not data.percentage then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Missing required surge parameters.',
            type        = 'error',
        })
        return
    end

    local percentage = tonumber(data.percentage)
    local durationMinutes = tonumber(data.durationMinutes) or 60

    if not percentage or percentage < 1 or percentage > 100 then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Surge percentage must be between 1 and 100.',
            type        = 'error',
        })
        return
    end

    local now = os.time()
    local expiresAt = now + (durationMinutes * 60)

    local surgeId = MySQL.insert.await([[
        INSERT INTO truck_surge_events
        (region, surge_type, cargo_type_filter, surge_percentage,
         status, started_at, expires_at)
        VALUES (?, 'manual', ?, ?, 'active', ?, ?)
    ]], {
        data.region,
        data.cargoFilter or nil,
        percentage,
        now,
        expiresAt,
    })

    -- Update board state surge count
    MySQL.update([[
        UPDATE truck_board_state
        SET surge_active_count = surge_active_count + 1, updated_at = ?
        WHERE region = ?
    ]], { now, data.region })

    -- Trigger board refresh for the region
    if RefreshBoardForRegion then
        RefreshBoardForRegion(data.region)
    end

    -- Notify all connected players about the surge
    TriggerClientEvent('trucking:client:surgeAlert', -1, {
        region      = data.region,
        percentage  = percentage,
        cargo_type  = data.cargoFilter,
        expires_at  = expiresAt,
    })

    LogAdminAction(src, 'create_surge', {
        surge_id        = surgeId,
        region          = data.region,
        percentage      = percentage,
        cargo_filter    = data.cargoFilter,
        duration_minutes = durationMinutes,
    })

    SendSurgeWebhook('manual_surge_created', {
        region              = data.region,
        percentage          = percentage,
        cargo_type          = data.cargoFilter,
        duration_minutes    = durationMinutes,
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Surge created: %s +%d%% for %d minutes')
            :format(data.region, percentage, durationMinutes),
        type        = 'success',
    })
end)

--- Cancel an active surge
RegisterNetEvent('trucking:server:admin:cancelSurge', function(surgeId)
    local src = source
    if not IsPlayerAdmin(src) then return end

    surgeId = tonumber(surgeId)
    if not surgeId then return end

    local surge = MySQL.single.await([[
        SELECT * FROM truck_surge_events WHERE id = ? AND status = 'active'
    ]], { surgeId })

    if not surge then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Active surge not found.',
            type        = 'error',
        })
        return
    end

    MySQL.update.await([[
        UPDATE truck_surge_events SET status = 'cancelled', ended_at = ? WHERE id = ?
    ]], { os.time(), surgeId })

    -- Decrement board surge count
    MySQL.update([[
        UPDATE truck_board_state
        SET surge_active_count = GREATEST(0, surge_active_count - 1), updated_at = ?
        WHERE region = ?
    ]], { os.time(), surge.region })

    LogAdminAction(src, 'cancel_surge', {
        surge_id    = surgeId,
        region      = surge.region,
        percentage  = surge.surge_percentage,
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Surge %d cancelled in %s.'):format(surgeId, surge.region),
        type        = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- BOARD MANAGEMENT
-- ─────────────────────────────────────────────

--- Force board refresh for a specific region
RegisterNetEvent('trucking:server:admin:forceRefresh', function(region)
    local src = source
    if not IsPlayerAdmin(src) then return end
    if not region then return end

    local validRegions = {
        los_santos = true, sandy_shores = true, paleto = true, grapeseed = true
    }

    if not validRegions[region] then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Invalid region: ' .. tostring(region),
            type        = 'error',
        })
        return
    end

    -- Call the board refresh function if available
    if RefreshBoardForRegion then
        RefreshBoardForRegion(region)
    end

    -- Update board state
    MySQL.update([[
        UPDATE truck_board_state SET last_refresh_at = ?, updated_at = ? WHERE region = ?
    ]], { os.time(), os.time(), region })

    -- Notify all players to refresh their board views
    TriggerClientEvent('trucking:client:boardRefresh', -1, { region = region })

    LogAdminAction(src, 'force_refresh', { region = region })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Board refreshed for %s.'):format(region),
        type        = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- VIEW ACTIVE LOADS SERVER-WIDE
-- ─────────────────────────────────────────────

--- Get all active loads across the server
RegisterNetEvent('trucking:server:admin:getActiveLoads', function()
    local src = source
    if not IsPlayerAdmin(src) then return end

    local loads = {}

    -- Collect from in-memory state first
    if ActiveLoads then
        for id, load in pairs(ActiveLoads) do
            loads[#loads + 1] = {
                id              = id,
                citizenid       = load.citizenid,
                bol_number      = load.bol_number or load.load_id,
                cargo_type      = load.cargo_type,
                status          = load.status,
                is_leon         = load.is_leon or false,
                is_military     = load.is_military or false,
                payout          = load.payout or load.estimated_payout,
                accepted_at     = load.accepted_at,
                window_expires  = load.window_expires,
            }
        end
    end

    -- Also check database for any missed entries
    if #loads == 0 then
        local dbLoads = MySQL.query.await([[
            SELECT al.id, al.citizenid, al.status, al.accepted_at, al.window_expires_at,
                   al.estimated_payout, l.bol_number, l.cargo_type, l.is_leon_load, l.tier
            FROM truck_active_loads al
            JOIN truck_loads l ON al.load_id = l.id
            ORDER BY al.accepted_at DESC
        ]], {}) or {}

        for i = 1, #dbLoads do
            local load = dbLoads[i]
            loads[#loads + 1] = {
                id              = load.id,
                citizenid       = load.citizenid,
                bol_number      = load.bol_number,
                cargo_type      = load.cargo_type,
                status          = load.status,
                is_leon         = load.is_leon_load == 1 or load.is_leon_load == true,
                is_military     = load.cargo_type == 'military',
                payout          = load.estimated_payout,
                accepted_at     = load.accepted_at,
                window_expires  = load.window_expires_at,
            }
        end
    end

    TriggerClientEvent('trucking:client:adminActiveLoads', src, loads)
end)

-- ─────────────────────────────────────────────
-- INSURANCE OVERSIGHT
-- ─────────────────────────────────────────────

--- View pending insurance claims
RegisterNetEvent('trucking:server:admin:getPendingClaims', function()
    local src = source
    if not IsPlayerAdmin(src) then return end

    local claims = MySQL.query.await([[
        SELECT ic.*, b.bol_number, b.cargo_type, b.origin_label, b.destination_label,
               d.player_name
        FROM truck_insurance_claims ic
        JOIN truck_bols b ON ic.bol_id = b.id
        JOIN truck_drivers d ON ic.citizenid = d.citizenid
        WHERE ic.status IN ('pending', 'approved')
        ORDER BY ic.filed_at DESC
    ]], {}) or {}

    TriggerClientEvent('trucking:client:adminPendingClaims', src, claims)
end)

--- Approve a pending insurance claim
RegisterNetEvent('trucking:server:admin:approveClaim', function(claimId)
    local src = source
    if not IsPlayerAdmin(src) then return end

    claimId = tonumber(claimId)
    if not claimId then return end

    local claim = MySQL.single.await([[
        SELECT * FROM truck_insurance_claims WHERE id = ? AND status = 'pending'
    ]], { claimId })

    if not claim then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Pending claim not found.',
            type        = 'error',
        })
        return
    end

    -- Approve with 15-minute payout delay
    MySQL.update.await([[
        UPDATE truck_insurance_claims
        SET status = 'approved', payout_at = ?
        WHERE id = ?
    ]], { os.time() + 900, claimId })

    LogAdminAction(src, 'approve_claim', {
        claim_id    = claimId,
        citizenid   = claim.citizenid,
        bol_number  = claim.bol_number,
        amount      = claim.claim_amount,
    })

    SendInsuranceWebhook('claim_approved', {
        citizenid       = claim.citizenid,
        bol_number      = claim.bol_number,
        claim_amount    = claim.claim_amount,
        status          = 'approved',
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Claim %d approved. Payout: $%d in 15 minutes.')
            :format(claimId, claim.claim_amount),
        type        = 'success',
    })
end)

--- Deny a pending insurance claim
RegisterNetEvent('trucking:server:admin:denyClaim', function(claimId, reason)
    local src = source
    if not IsPlayerAdmin(src) then return end

    claimId = tonumber(claimId)
    if not claimId then return end
    reason = reason or 'Denied by admin'

    local claim = MySQL.single.await([[
        SELECT * FROM truck_insurance_claims WHERE id = ? AND status IN ('pending', 'approved')
    ]], { claimId })

    if not claim then
        lib.notify(src, {
            title       = 'Admin',
            description = 'Claim not found or already resolved.',
            type        = 'error',
        })
        return
    end

    MySQL.update.await([[
        UPDATE truck_insurance_claims
        SET status = 'denied', resolved_at = ?
        WHERE id = ?
    ]], { os.time(), claimId })

    -- Notify the claimant if online
    local targetSrc = exports.qbx_core:GetPlayerByCitizenId(claim.citizenid)
    if targetSrc then
        local tSrc = type(targetSrc) == 'number' and targetSrc or nil
        if tSrc then
            lib.notify(tSrc, {
                title       = 'Insurance',
                description = 'Your insurance claim has been denied. Reason: ' .. reason,
                type        = 'error',
                duration    = 10000,
            })
        end
    end

    LogAdminAction(src, 'deny_claim', {
        claim_id    = claimId,
        citizenid   = claim.citizenid,
        bol_number  = claim.bol_number,
        amount      = claim.claim_amount,
        reason      = reason,
    })

    SendInsuranceWebhook('claim_denied', {
        citizenid       = claim.citizenid,
        bol_number      = claim.bol_number,
        claim_amount    = claim.claim_amount,
        status          = 'denied',
    })

    lib.notify(src, {
        title       = 'Admin',
        description = ('Claim %d denied.'):format(claimId),
        type        = 'success',
    })
end)

-- ─────────────────────────────────────────────
-- ADMIN DATA RETRIEVAL
-- ─────────────────────────────────────────────

--- Get current board state for all regions
RegisterNetEvent('trucking:server:admin:getBoardState', function()
    local src = source
    if not IsPlayerAdmin(src) then return end

    local boardState = MySQL.query.await([[
        SELECT * FROM truck_board_state ORDER BY region
    ]], {}) or {}

    TriggerClientEvent('trucking:client:adminBoardState', src, boardState)
end)

--- Get active surges
RegisterNetEvent('trucking:server:admin:getActiveSurges', function()
    local src = source
    if not IsPlayerAdmin(src) then return end

    local surges = MySQL.query.await([[
        SELECT * FROM truck_surge_events
        WHERE status = 'active'
        ORDER BY started_at DESC
    ]], {}) or {}

    TriggerClientEvent('trucking:client:adminActiveSurges', src, surges)
end)

--- Get current economy settings
RegisterNetEvent('trucking:server:admin:getEconomySettings', function()
    local src = source
    if not IsPlayerAdmin(src) then return end

    local settings = {
        server_multiplier   = Economy and Economy.ServerMultiplier or 1.0,
        night_haul_premium  = Economy and Economy.NightHaulPremium or 0.07,
        base_rates          = Economy and Economy.BaseRates or {},
        payout_floors       = Config and Config.PayoutFloors or {},
    }

    TriggerClientEvent('trucking:client:adminEconomySettings', src, settings)
end)

--- Get server-wide stats summary for admin dashboard
RegisterNetEvent('trucking:server:admin:getServerStats', function()
    local src = source
    if not IsPlayerAdmin(src) then return end

    local totalDrivers = MySQL.scalar.await([[
        SELECT COUNT(*) FROM truck_drivers
    ]], {}) or 0

    local activeLoadsCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM truck_active_loads
    ]], {}) or 0

    local totalCompletedToday = MySQL.scalar.await([[
        SELECT COUNT(*) FROM truck_bols
        WHERE bol_status = 'delivered' AND delivered_at >= ?
    ]], { os.time() - 86400 }) or 0

    local totalPayoutsToday = MySQL.scalar.await([[
        SELECT COALESCE(SUM(final_payout), 0) FROM truck_bols
        WHERE bol_status = 'delivered' AND delivered_at >= ?
    ]], { os.time() - 86400 }) or 0

    local pendingClaims = MySQL.scalar.await([[
        SELECT COUNT(*) FROM truck_insurance_claims
        WHERE status IN ('pending', 'approved')
    ]], {}) or 0

    local activeSurges = MySQL.scalar.await([[
        SELECT COUNT(*) FROM truck_surge_events WHERE status = 'active'
    ]], {}) or 0

    TriggerClientEvent('trucking:client:adminServerStats', src, {
        total_drivers       = totalDrivers,
        active_loads        = activeLoadsCount,
        completed_today     = totalCompletedToday,
        payouts_today       = totalPayoutsToday,
        pending_claims      = pendingClaims,
        active_surges       = activeSurges,
        server_multiplier   = Economy and Economy.ServerMultiplier or 1.0,
    })
end)
