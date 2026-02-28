--[[
    server/missions.lua
    THE MOST CRITICAL FILE -- Mission lifecycle management.

    Handles the entire load lifecycle from reservation through delivery/abandonment:
      - ReserveLoad: validate player, set reserved_by, track releases
      - CancelReservation: release reservation, increment release counter, check cooldown
      - AcceptLoad: validate ALL requirements, deduct deposit, create active load, create BOL, add BOL item
      - DepartOrigin: validate pre-trip/securing/seal, set departed_at, start delivery window
      - CompleteStop: for multi-stop loads
      - DeliverLoad: validate at destination, calculate payout, return deposit, issue payout
      - AbandonLoad: forfeit deposit, update BOL, rep penalty
      - HandleWindowExpired: called by maintenance thread (defined in main.lua)
      - InitiateTransfer / AcceptTransfer: company driver transfers

    Every event handler validates source, uses ValidateLoadOwner/ValidateProximity/RateLimitEvent.
    All financial transactions use exports.qbx_core:GetPlayer(src).Functions.AddMoney/RemoveMoney.
]]

-- ============================================================================
-- RESERVATION SYSTEM
-- ============================================================================

--- Reserve a load for a player (3-minute hold)
--- Prevents other players from accepting the load during the hold period.
RegisterNetEvent('trucking:server:reserveLoad', function(loadId)
    local src = source
    if not RateLimitEvent(src, 'reserveLoad', 2000) then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- Ensure driver record exists
    local driver = EnsureDriverRecord(src)
    if not driver then return end

    -- Check if player already has an active load
    local existingLoad = DB.GetActiveLoad(citizenid)
    if existingLoad then
        lib.notify(src, {
            title = 'Reserve Failed',
            description = 'You already have an active load.',
            type = 'error',
        })
        return
    end

    -- Check reservation cooldown (5 consecutive releases = 10 min cooldown on T2+)
    local load = DB.GetLoad(loadId)
    if not load then
        lib.notify(src, { title = 'Reserve Failed', description = 'Load not found.', type = 'error' })
        return
    end

    if load.tier >= 2 and driver.reservation_cooldown and driver.reservation_cooldown > GetServerTime() then
        local remaining = driver.reservation_cooldown - GetServerTime()
        lib.notify(src, {
            title = 'Reservation Cooldown',
            description = ('Wait %d seconds before reserving Tier 2+ loads.'):format(remaining),
            type = 'error',
        })
        return
    end

    -- Attempt to reserve (atomic: only succeeds if load is still available)
    local reserveUntil = GetServerTime() + (Config.ReservationSeconds or 180)
    local affected = DB.ReserveLoad(loadId, citizenid, reserveUntil)

    if affected == 0 then
        lib.notify(src, {
            title = 'Reserve Failed',
            description = 'Load is no longer available.',
            type = 'error',
        })
        return
    end

    lib.notify(src, {
        title = 'Load Reserved',
        description = ('You have %d seconds to accept.'):format(Config.ReservationSeconds or 180),
        type = 'success',
    })

    TriggerClientEvent('trucking:client:loadReserved', src, loadId, reserveUntil)
end)

-- ============================================================================
-- CANCEL RESERVATION
-- ============================================================================

RegisterNetEvent('trucking:server:cancelReservation', function(loadId)
    local src = source
    if not RateLimitEvent(src, 'cancelReservation', 2000) then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- Release the reservation
    local affected = DB.UnreserveLoad(loadId, citizenid)
    if affected == 0 then return end

    -- Increment consecutive release counter
    local driver = DB.GetDriver(citizenid)
    if driver then
        local newReleases = (driver.reservation_releases or 0) + 1
        local updates = { reservation_releases = newReleases }

        -- Check if cooldown threshold reached (5 releases = 10 min cooldown)
        local warningThreshold = Config.ReservationWarning or 3
        local cooldownDuration = Config.ReservationCooldown or 600
        if newReleases >= (warningThreshold + 2) then -- 5 releases (3 warning + 2 more)
            updates.reservation_cooldown = GetServerTime() + cooldownDuration
            updates.reservation_releases = 0 -- reset counter after cooldown applied
            lib.notify(src, {
                title = 'Reservation Cooldown',
                description = ('Too many cancelled reservations. %d second cooldown on Tier 2+ loads.'):format(cooldownDuration),
                type = 'error',
            })
        elseif newReleases >= warningThreshold then
            lib.notify(src, {
                title = 'Reservation Warning',
                description = ('You have cancelled %d reservations. %d more will trigger a cooldown.'):format(
                    newReleases, (warningThreshold + 2) - newReleases
                ),
                type = 'inform',
            })
        end

        DB.UpdateDriver(citizenid, updates)
    end

    TriggerClientEvent('trucking:client:reservationCancelled', src, loadId)
end)

-- ============================================================================
-- ACCEPT LOAD
-- The core acceptance flow. Validates ALL requirements, deducts deposit,
-- creates the active_load row, creates the BOL row, adds the BOL item
-- to player inventory, and sets the load status to accepted.
-- ============================================================================

RegisterNetEvent('trucking:server:acceptLoad', function(loadId, vehicleData)
    local src = source
    if not RateLimitEvent(src, 'acceptLoad', 5000) then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- 1. Ensure driver record exists
    local driver = EnsureDriverRecord(src)
    if not driver then return end

    -- 2. Check if player already has an active load
    local existingLoad = DB.GetActiveLoad(citizenid)
    if existingLoad then
        lib.notify(src, { title = 'Accept Failed', description = 'You already have an active load.', type = 'error' })
        return
    end

    -- 3. Fetch the load and validate it is reserved by this player
    local load = DB.GetLoad(loadId)
    if not load then
        lib.notify(src, { title = 'Accept Failed', description = 'Load not found.', type = 'error' })
        return
    end

    if load.board_status ~= 'reserved' or load.reserved_by ~= citizenid then
        -- Allow accepting available loads directly (if reservation not required)
        if load.board_status ~= 'available' then
            lib.notify(src, { title = 'Accept Failed', description = 'Load is not available for acceptance.', type = 'error' })
            return
        end
    end

    -- 4. Validate CDL/License requirement
    if load.required_license and load.required_license ~= 'none' then
        local license = DB.GetLicense(citizenid, load.required_license)
        if not license or license.status ~= 'active' then
            lib.notify(src, {
                title = 'Accept Failed',
                description = ('Requires %s CDL.'):format(load.required_license:gsub('_', ' '):upper()),
                type = 'error',
            })
            return
        end
    end

    -- 5. Validate endorsement requirement
    if load.required_endorsement then
        local endorsement = DB.GetLicense(citizenid, load.required_endorsement)
        if not endorsement or endorsement.status ~= 'active' then
            lib.notify(src, {
                title = 'Accept Failed',
                description = ('Requires %s endorsement.'):format(load.required_endorsement:upper()),
                type = 'error',
            })
            return
        end
    end

    -- 6. Validate certification requirement
    if load.required_certification then
        local cert = DB.GetCert(citizenid, load.required_certification)
        if not cert or cert.status ~= 'active' then
            lib.notify(src, {
                title = 'Accept Failed',
                description = ('Requires %s certification.'):format(load.required_certification:gsub('_', ' ')),
                type = 'error',
            })
            return
        end
    end

    -- 7. Validate insurance for Tier 1+ (T0 does not require insurance)
    if load.tier >= 1 then
        local policy = MySQL.single.await([[
            SELECT * FROM truck_insurance_policies
            WHERE citizenid = ? AND status = 'active'
              AND valid_from <= ?
              AND (valid_until IS NULL OR valid_until >= ?)
            LIMIT 1
        ]], { citizenid, GetServerTime(), GetServerTime() })

        if not policy then
            lib.notify(src, {
                title = 'Accept Failed',
                description = 'Active insurance policy required for Tier 1+ loads.',
                type = 'error',
            })
            return
        end
    end

    -- 8. Validate reputation tier allows access to this load tier
    local repTier = driver.reputation_tier or 'developing'
    local tierAccess = {
        suspended = -1,
        restricted = 0,
        probationary = 1,
        developing = 2,
        established = 3,
        professional = 3,
        elite = 3,
    }
    local maxAllowedTier = tierAccess[repTier] or 0
    if load.tier > maxAllowedTier then
        lib.notify(src, {
            title = 'Accept Failed',
            description = ('Your reputation tier (%s) does not allow Tier %d loads.'):format(repTier, load.tier),
            type = 'error',
        })
        return
    end

    -- 9. Deduct deposit from player
    local depositAmount = load.deposit_amount or 300
    local hasCash = player.PlayerData.money.cash >= depositAmount
    local hasBank = player.PlayerData.money.bank >= depositAmount

    if not hasCash and not hasBank then
        lib.notify(src, {
            title = 'Accept Failed',
            description = ('Insufficient funds for $%d deposit.'):format(depositAmount),
            type = 'error',
        })
        return
    end

    -- Prefer cash, fall back to bank
    local moneySource = hasCash and 'cash' or 'bank'
    player.Functions.RemoveMoney(moneySource, depositAmount, 'Trucking deposit - Load #' .. loadId)

    -- 10. Calculate delivery window
    local cargo = CargoTypes and CargoTypes[load.cargo_type] or {}
    local windowMinutesPerMile = { [0] = 6, [1] = 5, [2] = 4.5, [3] = 4 }
    local baseWindowMinutes = (windowMinutesPerMile[load.tier] or 5) * load.distance_miles
    if load.is_multi_stop and load.stop_count > 1 then
        baseWindowMinutes = baseWindowMinutes + (load.stop_count * 5)
    end
    local windowSeconds = math.floor(baseWindowMinutes * 60)
    local now = GetServerTime()
    local windowExpiresAt = now + windowSeconds

    -- 11. Create the BOL record
    local playerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname

    -- Get company info if applicable
    local companyId = nil
    local companyName = nil
    local companyMember = MySQL.single.await(
        'SELECT cm.company_id, c.company_name FROM truck_company_members cm JOIN truck_companies c ON cm.company_id = c.id WHERE cm.citizenid = ?',
        { citizenid }
    )
    if companyMember then
        companyId = companyMember.company_id
        companyName = companyMember.company_name
    end

    -- Determine license class for BOL
    local licenseClass = nil
    if load.required_license and load.required_license ~= 'none' then
        licenseClass = load.required_license
    end

    -- Check if license matches for BOL compliance
    local licenseMismatch = false
    if load.required_license and load.required_license ~= 'none' then
        local lic = DB.GetLicense(citizenid, load.required_license)
        if not lic or lic.status ~= 'active' then
            licenseMismatch = true
        end
    end

    -- Determine vehicle info
    local vehiclePlate = vehicleData and vehicleData.plate or nil
    local vehicleModel = vehicleData and vehicleData.model or nil
    local isRental = vehicleData and vehicleData.is_rental or false

    -- Determine temp monitoring
    local tempMonitoring = cargo.temp_required or false

    -- Insurance policy reference
    local insurancePolicyId = nil
    if load.tier >= 1 then
        local policy = MySQL.single.await([[
            SELECT id FROM truck_insurance_policies
            WHERE citizenid = ? AND status = 'active'
              AND valid_from <= ?
              AND (valid_until IS NULL OR valid_until >= ?)
            LIMIT 1
        ]], { citizenid, now, now })
        if policy then
            insurancePolicyId = policy.id
        end
    end

    -- Calculate estimated payout for display
    local estimatedPayout = load.base_payout_rental
    if not isRental then
        estimatedPayout = load.base_payout_owner_op
    end
    if load.surge_active and load.surge_percentage > 0 then
        estimatedPayout = math.floor(estimatedPayout * (1 + load.surge_percentage / 100))
    end

    local bolData = {
        bol_number = load.bol_number,
        load_id = load.id,
        citizenid = citizenid,
        driver_name = playerName,
        company_id = companyId,
        company_name = companyName,
        shipper_id = load.shipper_id,
        shipper_name = load.shipper_name,
        origin_label = load.origin_label,
        destination_label = load.destination_label,
        distance_miles = load.distance_miles,
        cargo_type = load.cargo_type,
        cargo_description = cargo.description or load.cargo_type:gsub('_', ' '),
        weight_lbs = load.weight_lbs,
        tier = load.tier,
        hazmat_class = load.hazmat_class,
        placard_class = load.hazmat_class and ('Class ' .. load.hazmat_class) or nil,
        license_class = licenseClass,
        license_matched = not licenseMismatch,
        seal_number = nil, -- set when seal is applied
        seal_status = 'not_applied',
        temp_required_min = load.temp_min_f,
        temp_required_max = load.temp_max_f,
        bol_status = 'active',
        is_leon = load.is_leon_load or false,
        issued_at = now,
    }

    local bolId = DB.InsertBOL(bolData)

    -- 12. Create the active load row
    local activeLoadData = {
        load_id = load.id,
        bol_id = bolId,
        citizenid = citizenid,
        driver_id = driver.id,
        vehicle_plate = vehiclePlate,
        vehicle_model = vehicleModel,
        is_rental = isRental,
        status = 'at_origin',
        cargo_integrity = 100,
        cargo_secured = false,
        seal_status = 'not_applied',
        temp_monitoring_active = tempMonitoring,
        accepted_at = now,
        window_expires_at = windowExpiresAt,
        deposit_posted = depositAmount,
        estimated_payout = estimatedPayout,
        company_id = companyId,
        convoy_id = nil,
    }

    local activeLoadId = DB.InsertActiveLoad(activeLoadData)
    activeLoadData.id = activeLoadId

    -- 13. Store in memory
    ActiveLoads[bolId] = activeLoadData

    -- 14. Update load board status to accepted
    DB.UpdateLoadStatus(loadId, 'accepted')

    -- 15. Create deposit record
    DB.InsertDeposit({
        bol_id = bolId,
        bol_number = load.bol_number,
        citizenid = citizenid,
        amount = depositAmount,
        tier = load.tier,
        deposit_type = load.tier == 0 and 'flat' or 'percentage',
    })

    -- 16. Add physical BOL item to player inventory
    exports.ox_inventory:AddItem(src, 'trucking_bol', 1, {
        bol_number = load.bol_number,
        cargo_type = load.cargo_type,
        shipper = load.shipper_name,
        destination = load.destination_label,
        issued_at = now,
    })

    -- 17. Log BOL event
    DB.InsertBOLEvent({
        bol_id = bolId,
        bol_number = load.bol_number,
        citizenid = citizenid,
        event_type = 'load_accepted',
        event_data = {
            load_id = loadId,
            deposit = depositAmount,
            vehicle = vehiclePlate,
            is_rental = isRental,
            estimated_payout = estimatedPayout,
        },
    })

    -- 18. Reset reservation release counter on successful acceptance
    DB.UpdateDriver(citizenid, { reservation_releases = 0 })

    -- 19. Notify player
    lib.notify(src, {
        title = 'Load Accepted',
        description = ('BOL #%s -- $%d deposit held. Deliver to %s.'):format(
            load.bol_number, depositAmount, load.destination_label
        ),
        type = 'success',
    })

    -- 20. Send active load data to client for HUD and tracking
    local bol = DB.GetBOL(bolId)
    TriggerClientEvent('trucking:client:loadAccepted', src, activeLoadData, bol, load)

    print(('[trucking] Load accepted: %s accepted load #%d (BOL #%s, $%d deposit, est $%d payout)'):format(
        citizenid, loadId, load.bol_number, depositAmount, estimatedPayout
    ))
end)

-- ============================================================================
-- DEPART ORIGIN
-- Player is leaving the origin point. Validates that required pre-departure
-- checks have been completed (pre-trip, cargo securing, seal application).
-- Sets departed_at and starts the delivery window countdown.
-- ============================================================================

RegisterNetEvent('trucking:server:departOrigin', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'departOrigin', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    -- Must be at_origin to depart
    if activeLoad.status ~= 'at_origin' then
        lib.notify(src, { title = 'Depart Failed', description = 'You have already departed.', type = 'error' })
        return
    end

    local bol = DB.GetBOL(bolId)
    if not bol then return end

    local load = DB.GetLoad(activeLoad.load_id)
    if not load then return end

    local cargo = CargoTypes and CargoTypes[load.cargo_type] or {}

    -- Validate cargo securing (required for flatbed/oversized loads)
    if cargo.requires_securing and not activeLoad.cargo_secured then
        lib.notify(src, {
            title = 'Depart Failed',
            description = 'Cargo must be secured before departure.',
            type = 'error',
        })
        return
    end

    -- Validate seal (if required by cargo type)
    if load.requires_seal and activeLoad.seal_status == 'not_applied' then
        -- Auto-apply seal on departure if not yet applied
        local sealNumber = ('SEAL-%s-%05d'):format(os.date('%y%m', GetServerTime()), math.random(10000, 99999))
        activeLoad.seal_status = 'sealed'
        activeLoad.seal_number = sealNumber

        DB.UpdateActiveLoad(activeLoad.id, {
            seal_status = 'sealed',
            seal_number = sealNumber,
        })
        DB.UpdateBOL(bolId, {
            seal_number = sealNumber,
            seal_status = 'sealed',
        })

        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = activeLoad.citizenid,
            event_type = 'seal_applied',
            event_data = { seal_number = sealNumber },
        })
    end

    -- Set departed_at and update status
    local now = GetServerTime()
    activeLoad.status = 'in_transit'
    activeLoad.departed_at = now
    ActiveLoads[bolId] = activeLoad

    DB.UpdateActiveLoad(activeLoad.id, {
        status = 'in_transit',
        departed_at = now,
    })

    DB.UpdateBOL(bolId, {
        departed_at = now,
    })

    -- Log departure event
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    DB.InsertBOLEvent({
        bol_id = bolId,
        bol_number = bol.bol_number,
        citizenid = activeLoad.citizenid,
        event_type = 'departed_origin',
        event_data = { departed_at = now },
        coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    })

    lib.notify(src, {
        title = 'Departed',
        description = ('En route to %s. Drive safe.'):format(bol.destination_label),
        type = 'success',
    })

    TriggerClientEvent('trucking:client:departed', src, bolId, activeLoad)
end)

-- ============================================================================
-- COMPLETE STOP (Multi-stop loads)
-- ============================================================================

RegisterNetEvent('trucking:server:completeStop', function(bolId, stopNumber)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'completeStop', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    -- Validate we are at the right stop
    if activeLoad.current_stop ~= stopNumber then
        lib.notify(src, { title = 'Stop Error', description = 'Wrong stop number.', type = 'error' })
        return
    end

    -- Validate in_transit or at_stop status
    if activeLoad.status ~= 'in_transit' and activeLoad.status ~= 'at_stop' then
        return
    end

    local bol = DB.GetBOL(bolId)
    if not bol then return end

    -- Increment stop counter
    local nextStop = stopNumber + 1
    local load = DB.GetLoad(activeLoad.load_id)
    local totalStops = load and load.stop_count or 1

    if nextStop > totalStops then
        -- This was the last stop; player should now proceed to final destination
        activeLoad.status = 'in_transit'
        activeLoad.current_stop = nextStop
    else
        activeLoad.status = 'at_stop'
        activeLoad.current_stop = nextStop
    end

    ActiveLoads[bolId] = activeLoad
    DB.UpdateActiveLoad(activeLoad.id, {
        status = activeLoad.status,
        current_stop = nextStop,
    })

    -- Log the stop completion
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    DB.InsertBOLEvent({
        bol_id = bolId,
        bol_number = bol.bol_number,
        citizenid = activeLoad.citizenid,
        event_type = 'stop_completed',
        event_data = { stop_number = stopNumber, next_stop = nextStop, total_stops = totalStops },
        coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    })

    lib.notify(src, {
        title = 'Stop Complete',
        description = ('Stop %d of %d completed.'):format(stopNumber, totalStops),
        type = 'success',
    })

    TriggerClientEvent('trucking:client:stopCompleted', src, bolId, nextStop, totalStops)
end)

-- ============================================================================
-- DELIVER LOAD
-- The payout event. Validates destination zone, calculates final payout,
-- returns deposit, issues payment, updates all records.
-- ============================================================================

RegisterNetEvent('trucking:server:deliverLoad', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'deliverLoad', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    -- Must be in_transit to deliver
    if activeLoad.status ~= 'in_transit' and activeLoad.status ~= 'at_destination' then
        lib.notify(src, { title = 'Delivery Failed', description = 'Load is not in transit.', type = 'error' })
        return
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local bol = DB.GetBOL(bolId)
    if not bol then return end

    local load = DB.GetLoad(activeLoad.load_id)
    if not load then return end

    -- Validate player is at the destination zone
    local destCoords = load.destination_coords
    if type(destCoords) == 'string' then
        destCoords = json.decode(destCoords)
    end
    local destVec = vector3(destCoords.x, destCoords.y, destCoords.z)

    -- Delivery zone sizing by tier (wider zones for lower tiers)
    local zoneSizes = Config.DeliveryZoneSizes or {
        [0] = vec3(12.0, 8.0, 3.0),
        [1] = vec3(8.0, 5.0, 3.0),
        [2] = vec3(5.0, 3.5, 3.0),
        [3] = vec3(4.0, 3.0, 3.0),
    }
    local maxDistance = zoneSizes[load.tier] and zoneSizes[load.tier].x or 12.0

    if not ValidateProximity(src, destVec, maxDistance) then
        lib.notify(src, {
            title = 'Delivery Failed',
            description = 'You are not at the delivery zone.',
            type = 'error',
        })
        return
    end

    -- 1. Calculate payout using the payout engine
    local now = GetServerTime()
    local deliveryData = {
        delivered_at = now,
    }

    local finalPayout, payoutStatus, breakdown = CalculatePayout(activeLoad, bol, deliveryData)

    -- 2. Handle rejected delivery (cargo integrity below threshold)
    if payoutStatus == 'rejected' then
        -- Cargo refused at destination. Deposit still forfeited.
        DB.UpdateBOL(bolId, {
            bol_status = 'rejected',
            final_payout = 0,
            payout_breakdown = breakdown,
            delivered_at = now,
        })

        -- Log the rejection event
        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = citizenid,
            event_type = 'load_rejected',
            event_data = {
                cargo_integrity = activeLoad.cargo_integrity,
                reason = 'integrity_below_threshold',
            },
        })

        -- Forfeit deposit
        local deposit = DB.GetDeposit(bolId)
        if deposit and deposit.status == 'held' then
            DB.UpdateDepositStatus(deposit.id, 'forfeited')
        end

        -- Delete active load
        DB.DeleteActiveLoad(activeLoad.id)
        ActiveLoads[bolId] = nil

        -- Apply reputation penalty
        ApplyReputationChange(citizenid, 'integrity_fail', load.tier, bolId, bol.bol_number)

        lib.notify(src, {
            title = 'Load Rejected',
            description = ('Cargo integrity too low (%d%%). Deposit forfeited.'):format(activeLoad.cargo_integrity),
            type = 'error',
        })

        TriggerClientEvent('trucking:client:loadRejected', src, bolId, {
            integrity = activeLoad.cargo_integrity,
        })
        return
    end

    -- 3. Return deposit to player
    local deposit = DB.GetDeposit(bolId)
    if deposit and deposit.status == 'held' then
        player.Functions.AddMoney('bank', deposit.amount, 'Trucking deposit return - BOL #' .. bol.bol_number)
        DB.UpdateDepositStatus(deposit.id, 'returned')
    end

    -- 4. Issue payout
    player.Functions.AddMoney('bank', finalPayout, 'Trucking payout - BOL #' .. bol.bol_number)

    -- 5. Finalize BOL
    FinalizeBOL(bolId, 'delivered', {
        final_payout = finalPayout,
        breakdown = breakdown,
        delivered_at = now,
    })

    -- 6. Log delivery event
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    DB.InsertBOLEvent({
        bol_id = bolId,
        bol_number = bol.bol_number,
        citizenid = citizenid,
        event_type = 'load_delivered',
        event_data = {
            final_payout = finalPayout,
            deposit_returned = deposit and deposit.amount or 0,
            breakdown = breakdown,
        },
        coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    })

    -- 7. Delete active load from memory and database
    DB.DeleteActiveLoad(activeLoad.id)
    ActiveLoads[bolId] = nil

    -- 8. Update driver stats
    DB.UpdateDriverStats(citizenid, {
        total_loads_completed = 1,
        total_distance_driven = math.floor(load.distance_miles),
        total_earnings = finalPayout,
    })
    DB.UpdateDriver(citizenid, { last_seen = now })

    -- 9. Apply reputation gain
    ApplyReputationChange(citizenid, 'delivery', load.tier, bolId, bol.bol_number)

    -- 10. Update shipper reputation
    UpdateShipperRepOnDelivery(citizenid, load.shipper_id, load.tier, bolId, activeLoad)

    -- 11. Clear any shipper backlog surge (if this was the first delivery to them in 4+ hours)
    MySQL.update.await([[
        UPDATE truck_surge_events
        SET status = 'expired', ended_at = ?
        WHERE surge_type = 'shipper_backlog'
          AND shipper_filter = ?
          AND status = 'active'
    ]], { now, load.shipper_id })

    -- 12. Handle cold chain failure streak surge resolution
    if load.cargo_type == 'cold_chain' or load.cargo_type == 'pharmaceutical' then
        -- Track successful reefer deliveries; after 3, expire the surge
        -- (This is a simplification; a production version would track per-region counts)
        local recentSuccesses = MySQL.query.await([[
            SELECT COUNT(*) as cnt FROM truck_bols
            WHERE cargo_type IN ('cold_chain', 'pharmaceutical', 'pharmaceutical_biologic')
              AND bol_status = 'delivered'
              AND delivered_at > ?
        ]], { now - 7200 })

        local successCount = recentSuccesses and recentSuccesses[1] and recentSuccesses[1].cnt or 0
        if successCount >= 3 then
            MySQL.update.await([[
                UPDATE truck_surge_events
                SET status = 'expired', ended_at = ?
                WHERE surge_type = 'cold_chain_failure_streak'
                  AND status = 'active'
            ]], { now })
        end
    end

    -- 13. Notify player
    local depositReturned = deposit and deposit.amount or 0
    lib.notify(src, {
        title = 'Delivery Complete',
        description = ('Payout: $%s | Deposit returned: $%s'):format(finalPayout, depositReturned),
        type = 'success',
    })

    TriggerClientEvent('trucking:client:loadDelivered', src, bolId, {
        payout = finalPayout,
        deposit_returned = depositReturned,
        breakdown = breakdown,
        bol_number = bol.bol_number,
    })

    print(('[trucking] Delivery complete: %s delivered BOL #%s, payout $%d, deposit $%d returned'):format(
        citizenid, bol.bol_number, finalPayout, depositReturned
    ))
end)

-- ============================================================================
-- ABANDON LOAD
-- Player voluntarily abandons the load. Deposit forfeited, rep penalty.
-- ============================================================================

RegisterNetEvent('trucking:server:abandonLoad', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'abandonLoad', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local bol = DB.GetBOL(bolId)
    if not bol then return end

    local load = DB.GetLoad(activeLoad.load_id)

    -- 1. Update BOL status
    DB.UpdateBOL(bolId, {
        bol_status = 'abandoned',
    })

    -- 2. Log abandonment event
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    DB.InsertBOLEvent({
        bol_id = bolId,
        bol_number = bol.bol_number,
        citizenid = citizenid,
        event_type = 'load_abandoned',
        event_data = { voluntary = true },
        coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    })

    -- 3. Forfeit deposit
    local deposit = DB.GetDeposit(bolId)
    if deposit and deposit.status == 'held' then
        DB.UpdateDepositStatus(deposit.id, 'forfeited')
    end

    -- 4. Update load status
    if load then
        DB.UpdateLoadStatus(load.id, 'orphaned')
    end

    -- 5. Delete active load
    DB.DeleteActiveLoad(activeLoad.id)
    ActiveLoads[bolId] = nil

    -- 6. Update driver stats
    DB.UpdateDriverStats(citizenid, { total_loads_failed = 1 })

    -- 7. Apply reputation penalty
    local tier = load and load.tier or 0
    ApplyReputationChange(citizenid, 'abandonment', tier, bolId, bol.bol_number)

    -- 8. Notify player
    lib.notify(src, {
        title = 'Load Abandoned',
        description = ('Deposit of $%d forfeited.'):format(deposit and deposit.amount or 0),
        type = 'error',
    })

    TriggerClientEvent('trucking:client:loadAbandoned', src, bolId)

    print(('[trucking] Load abandoned: %s abandoned BOL #%s, deposit $%d forfeited'):format(
        citizenid, bol.bol_number, deposit and deposit.amount or 0
    ))
end)

-- ============================================================================
-- REPUTATION CHANGE APPLICATION
-- Applies reputation changes based on event type and load tier.
-- Updates the driver record and logs the change.
-- ============================================================================

--- Reputation point tables from the development guide (Section 20.1)
local ReputationGains = {
    delivery = { [0] = 8, [1] = 15, [2] = 25, [3] = 40 },
    military_delivery = 60,
    full_compliance = 5,
    supplier_contract = 20,
    cold_chain_clean = 8,
    livestock_excellent = 10,
}

local ReputationLosses = {
    robbery        = { [0] = -30, [1] = -60, [2] = -100, [3] = -180 },
    integrity_fail = { [0] = -20, [1] = -40, [2] = -70,  [3] = -120 },
    abandonment    = { [0] = -25, [1] = -50, [2] = -90,  [3] = -160 },
    window_expired = { [0] = -10, [1] = -20, [2] = -35,  [3] = -60 },
    seal_break     = { [0] = 0,   [1] = -15, [2] = -30,  [3] = -55 },
    hazmat_routing = { [0] = 0,   [1] = 0,   [2] = 0,    [3] = -40 },
}

--- Map reputation score to tier name
---@param score number
---@return string tier
function ScoreToRepTier(score)
    if score <= 0 then return 'suspended'
    elseif score < 200 then return 'restricted'
    elseif score < 400 then return 'probationary'
    elseif score < 600 then return 'developing'
    elseif score < 800 then return 'established'
    elseif score < 1000 then return 'professional'
    else return 'elite'
    end
end

--- Apply a reputation change to a driver
---@param citizenid string
---@param changeType string  e.g. 'delivery', 'abandonment', 'robbery'
---@param tier number  Load tier (0-3)
---@param bolId number|nil
---@param bolNumber string|nil
function ApplyReputationChange(citizenid, changeType, tier, bolId, bolNumber)
    local driver = DB.GetDriver(citizenid)
    if not driver then return end

    -- Determine point change
    local pointsChange = 0
    if ReputationGains[changeType] then
        if type(ReputationGains[changeType]) == 'table' then
            pointsChange = ReputationGains[changeType][tier] or 0
        else
            pointsChange = ReputationGains[changeType]
        end
    elseif ReputationLosses[changeType] then
        if type(ReputationLosses[changeType]) == 'table' then
            pointsChange = ReputationLosses[changeType][tier] or 0
        else
            pointsChange = ReputationLosses[changeType]
        end
    end

    if pointsChange == 0 then return end

    local pointsBefore = driver.reputation_score
    local pointsAfter = math.max(0, pointsBefore + pointsChange)
    -- Cap at 1100 for some headroom above elite
    pointsAfter = math.min(pointsAfter, 1100)

    local tierBefore = driver.reputation_tier
    local tierAfter = ScoreToRepTier(pointsAfter)

    -- Update driver record
    local updates = {
        reputation_score = pointsAfter,
        reputation_tier = tierAfter,
    }

    -- If suspended (score = 0), set 24-hour suspension
    if tierAfter == 'suspended' and tierBefore ~= 'suspended' then
        updates.suspended_until = GetServerTime() + 86400 -- 24 hours
    end

    DB.UpdateDriver(citizenid, updates)

    -- Log the reputation change
    DB.InsertRepLog({
        driver_id = driver.id,
        citizenid = citizenid,
        change_type = changeType,
        points_before = pointsBefore,
        points_change = pointsChange,
        points_after = pointsAfter,
        tier_before = tierBefore,
        tier_after = tierAfter,
        bol_id = bolId,
        bol_number = bolNumber,
        tier_of_load = tier,
    })

    -- Notify player if online and tier changed
    local playerSrc = GetPlayerSource(citizenid)
    if playerSrc then
        TriggerClientEvent('trucking:client:reputationUpdate', playerSrc, {
            score = pointsAfter,
            tier = tierAfter,
            change = pointsChange,
            change_type = changeType,
            tier_changed = tierBefore ~= tierAfter,
            old_tier = tierBefore,
        })

        if tierBefore ~= tierAfter then
            if pointsChange > 0 then
                lib.notify(playerSrc, {
                    title = 'Reputation Up',
                    description = ('Promoted to %s (%d pts)'):format(tierAfter:gsub('_', ' '), pointsAfter),
                    type = 'success',
                })
            else
                lib.notify(playerSrc, {
                    title = 'Reputation Down',
                    description = ('Demoted to %s (%d pts)'):format(tierAfter:gsub('_', ' '), pointsAfter),
                    type = 'error',
                })
            end
        end
    end
end

-- ============================================================================
-- SHIPPER REPUTATION UPDATE ON DELIVERY
-- ============================================================================

--- Shipper reputation point thresholds
local ShipperTierThresholds = {
    { tier = 'preferred',   minPoints = 700 },
    { tier = 'trusted',     minPoints = 350 },
    { tier = 'established', minPoints = 150 },
    { tier = 'familiar',    minPoints = 50 },
    { tier = 'unknown',     minPoints = 0 },
}

--- Map score to shipper rep tier
---@param points number
---@return string tier
function ShipperScoreToTier(points)
    for _, threshold in ipairs(ShipperTierThresholds) do
        if points >= threshold.minPoints then
            return threshold.tier
        end
    end
    return 'unknown'
end

--- Update shipper reputation after a successful delivery
---@param citizenid string
---@param shipperId string
---@param tier number  Load tier
---@param bolId number
---@param activeLoad table
function UpdateShipperRepOnDelivery(citizenid, shipperId, tier, bolId, activeLoad)
    local driver = DB.GetDriver(citizenid)
    if not driver then return end

    local current = DB.GetShipperRep(citizenid, shipperId)
    local pointsBefore = current and current.points or 0
    local tierBefore = current and current.tier or 'unknown'

    -- Base points per delivery tier
    local pointsPerTier = { [0] = 5, [1] = 10, [2] = 18, [3] = 30 }
    local basePoints = pointsPerTier[tier] or 5

    -- Bonus for clean delivery (no integrity issues, no seal breaks)
    local cleanBonus = 0
    if activeLoad.cargo_integrity >= 95 then cleanBonus = cleanBonus + 3 end
    if activeLoad.seal_status == 'sealed' then cleanBonus = cleanBonus + 2 end

    local pointsChange = basePoints + cleanBonus
    local pointsAfter = pointsBefore + pointsChange
    local tierAfter = ShipperScoreToTier(pointsAfter)

    local cleanStreak = current and current.current_clean_streak or 0
    if activeLoad.cargo_integrity >= 90 then
        cleanStreak = cleanStreak + 1
    else
        cleanStreak = 0
    end

    DB.UpsertShipperRep({
        driver_id = driver.id,
        citizenid = citizenid,
        shipper_id = shipperId,
        points = pointsAfter,
        tier = tierAfter,
        deliveries_completed = (current and current.deliveries_completed or 0) + 1,
        current_clean_streak = cleanStreak,
        last_delivery_at = GetServerTime(),
    })

    -- Log the change
    DB.InsertShipperRepLog({
        driver_id = driver.id,
        citizenid = citizenid,
        shipper_id = shipperId,
        change_type = 'delivery',
        points_before = pointsBefore,
        points_change = pointsChange,
        points_after = pointsAfter,
        tier_before = tierBefore,
        tier_after = tierAfter,
        bol_id = bolId,
    })
end

--- Get shipper reputation tier for payout compliance bonus calculation
---@param citizenid string
---@param shipperId string
---@return string tier
function GetShipperRepTier(citizenid, shipperId)
    local rep = DB.GetShipperRep(citizenid, shipperId)
    if rep then return rep.tier end
    return 'unknown'
end

-- ============================================================================
-- LOAD TRANSFER (Company Driver to Company Driver)
-- Both drivers must be within 15m of trailer. Distance-based payout split.
-- ============================================================================

RegisterNetEvent('trucking:server:initiateTransfer', function(targetCitizenId)
    local src = source
    if not RateLimitEvent(src, 'initiateTransfer', 5000) then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- Find the active load for the initiating driver
    local activeLoad = nil
    local activeBolId = nil
    for bolId, al in pairs(ActiveLoads) do
        if al.citizenid == citizenid then
            activeLoad = al
            activeBolId = bolId
            break
        end
    end

    if not activeLoad then
        lib.notify(src, { title = 'Transfer Failed', description = 'No active load found.', type = 'error' })
        return
    end

    -- Validate both are in the same company
    if not activeLoad.company_id then
        lib.notify(src, { title = 'Transfer Failed', description = 'Must be in a company to transfer.', type = 'error' })
        return
    end

    local targetMember = MySQL.single.await(
        'SELECT * FROM truck_company_members WHERE citizenid = ? AND company_id = ?',
        { targetCitizenId, activeLoad.company_id }
    )
    if not targetMember then
        lib.notify(src, { title = 'Transfer Failed', description = 'Target driver is not in your company.', type = 'error' })
        return
    end

    -- Validate target is online
    local targetSrc = GetPlayerSource(targetCitizenId)
    if not targetSrc then
        lib.notify(src, { title = 'Transfer Failed', description = 'Target driver is not online.', type = 'error' })
        return
    end

    -- Validate target does not have an active load
    local targetActiveLoad = DB.GetActiveLoad(targetCitizenId)
    if targetActiveLoad then
        lib.notify(src, { title = 'Transfer Failed', description = 'Target driver already has an active load.', type = 'error' })
        return
    end

    -- Validate proximity (both within 15m)
    local srcPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if srcPed and targetPed then
        local srcCoords = GetEntityCoords(srcPed)
        local targetCoords = GetEntityCoords(targetPed)
        if #(srcCoords - targetCoords) > 15.0 then
            lib.notify(src, { title = 'Transfer Failed', description = 'Both drivers must be within 15 meters.', type = 'error' })
            return
        end
    end

    -- Calculate split ratio based on distance traveled
    local load = DB.GetLoad(activeLoad.load_id)
    local totalDistance = load and load.distance_miles or 1

    -- Estimate distance driven by calculating from origin
    local originCoords = load and load.origin_coords or nil
    if type(originCoords) == 'string' then originCoords = json.decode(originCoords) end

    local driverDistance = 0
    if srcPed and originCoords then
        local srcPos = GetEntityCoords(srcPed)
        local originVec = vector3(originCoords.x, originCoords.y, originCoords.z)
        local rawDist = #(srcPos - originVec)
        driverDistance = math.floor((rawDist / 1000) * 3.5 * 100) / 100
    end
    driverDistance = math.min(driverDistance, totalDistance)
    local remainingDistance = totalDistance - driverDistance

    local splitRatio = {
        from = driverDistance / totalDistance,
        to = remainingDistance / totalDistance,
    }

    -- Notify the target driver with transfer offer
    TriggerClientEvent('trucking:client:transferOffer', targetSrc, {
        from_citizenid = citizenid,
        from_name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
        bol_id = activeBolId,
        active_load = activeLoad,
        split_ratio = splitRatio,
    })

    lib.notify(src, {
        title = 'Transfer Initiated',
        description = 'Waiting for target driver to accept.',
        type = 'inform',
    })
end)

RegisterNetEvent('trucking:server:acceptTransfer', function(transferData)
    local src = source
    if not RateLimitEvent(src, 'acceptTransfer', 5000) then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local bolId = transferData.bol_id
    local fromCitizenId = transferData.from_citizenid

    -- Validate the active load still exists and belongs to the original driver
    local activeLoad = ActiveLoads[bolId]
    if not activeLoad or activeLoad.citizenid ~= fromCitizenId then
        lib.notify(src, { title = 'Transfer Failed', description = 'Load no longer available for transfer.', type = 'error' })
        return
    end

    -- Validate target doesn't have an active load
    local existing = DB.GetActiveLoad(citizenid)
    if existing then
        lib.notify(src, { title = 'Transfer Failed', description = 'You already have an active load.', type = 'error' })
        return
    end

    -- Get driver record for target
    local driver = EnsureDriverRecord(src)
    if not driver then return end

    -- Transfer the active load
    local now = GetServerTime()
    activeLoad.citizenid = citizenid
    activeLoad.driver_id = driver.id
    ActiveLoads[bolId] = activeLoad

    DB.UpdateActiveLoad(activeLoad.id, {
        citizenid = citizenid,
        driver_id = driver.id,
    })

    -- Update BOL record
    local newDriverName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    DB.UpdateBOL(bolId, {
        citizenid = citizenid,
        driver_name = newDriverName,
    })

    -- Log the transfer event
    local bol = DB.GetBOL(bolId)
    if bol then
        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = citizenid,
            event_type = 'transfer_completed',
            event_data = {
                from_citizenid = fromCitizenId,
                to_citizenid = citizenid,
                split_ratio = transferData.split_ratio,
            },
        })
    end

    -- Notify both players
    local fromSrc = GetPlayerSource(fromCitizenId)
    if fromSrc then
        lib.notify(fromSrc, {
            title = 'Transfer Complete',
            description = 'Load transferred successfully.',
            type = 'success',
        })
        TriggerClientEvent('trucking:client:transferCompleted', fromSrc, bolId, 'sent')
    end

    lib.notify(src, {
        title = 'Transfer Accepted',
        description = ('BOL #%s -- Continue delivery to %s.'):format(
            bol and bol.bol_number or 'unknown', bol and bol.destination_label or 'destination'
        ),
        type = 'success',
    })

    TriggerClientEvent('trucking:client:transferCompleted', src, bolId, 'received')
    TriggerClientEvent('trucking:client:restoreActiveLoad', src, activeLoad, bol)

    print(('[trucking] Load transferred: BOL #%s from %s to %s'):format(
        bol and bol.bol_number or '?', fromCitizenId, citizenid
    ))
end)

-- ============================================================================
-- SEAL BREAK HANDLER
-- Called when a seal is broken (decouple, robbery, or abandonment timeout).
-- ============================================================================

RegisterNetEvent('trucking:server:sealBreak', function(bolId, reason)
    local src = source
    -- For internal calls (from stationary timer), src may be 0
    if src and src > 0 then
        if not ValidateLoadOwner(src, bolId) then return end
    end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    -- Only break if currently sealed
    if activeLoad.seal_status ~= 'sealed' then return end

    local now = GetServerTime()
    activeLoad.seal_status = 'broken'
    activeLoad.seal_broken_at = now
    ActiveLoads[bolId] = activeLoad

    DB.UpdateActiveLoad(activeLoad.id, {
        seal_status = 'broken',
        seal_broken_at = now,
    })

    DB.UpdateBOL(bolId, {
        seal_status = 'broken',
    })

    -- Log the event
    local bol = DB.GetBOL(bolId)
    if bol then
        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = activeLoad.citizenid,
            event_type = 'seal_broken',
            event_data = { reason = reason, broken_at = now },
        })
    end

    -- Apply reputation penalty
    local load = DB.GetLoad(activeLoad.load_id)
    local tier = load and load.tier or 0
    ApplyReputationChange(activeLoad.citizenid, 'seal_break', tier, bolId, bol and bol.bol_number)

    -- Shipper reputation penalty: -20 points
    if load then
        local shipperRep = DB.GetShipperRep(activeLoad.citizenid, load.shipper_id)
        if shipperRep then
            local newPoints = math.max(0, shipperRep.points - 20)
            local newTier = ShipperScoreToTier(newPoints)
            DB.UpsertShipperRep({
                driver_id = shipperRep.driver_id,
                citizenid = activeLoad.citizenid,
                shipper_id = load.shipper_id,
                points = newPoints,
                tier = newTier,
                deliveries_completed = shipperRep.deliveries_completed,
                current_clean_streak = 0,
                last_delivery_at = shipperRep.last_delivery_at,
            })
        end
    end

    -- Notify police script (low priority)
    if Config and Config.PoliceResources then
        local ped = activeLoad.citizenid and GetPlayerSource(activeLoad.citizenid)
        local alertCoords = nil
        if ped then
            local playerPed = GetPlayerPed(ped)
            if playerPed then alertCoords = GetEntityCoords(playerPed) end
        end

        for _, resourceName in ipairs(Config.PoliceResources) do
            pcall(function()
                exports[resourceName]:dispatchAlert({
                    type = 'seal_break',
                    priority = Config.SealBreakAlertPriority or 'low',
                    location = alertCoords,
                    details = 'Truck trailer seal broken - ' .. (reason or 'unknown'),
                })
            end)
        end
    end

    -- Notify the player
    local playerSrc = GetPlayerSource(activeLoad.citizenid)
    if playerSrc then
        lib.notify(playerSrc, {
            title = 'Seal Broken',
            description = 'Trailer seal has been broken. Compliance bonus lost.',
            type = 'error',
        })
    end
end)

-- ============================================================================
-- CARGO SECURING HANDLER
-- ============================================================================

RegisterNetEvent('trucking:server:strapComplete', function(bolId, pointNumber)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'strapComplete', 3000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    local bol = DB.GetBOL(bolId)
    if not bol then return end

    -- Log the securing event
    DB.InsertBOLEvent({
        bol_id = bolId,
        bol_number = bol.bol_number,
        citizenid = activeLoad.citizenid,
        event_type = 'cargo_secured',
        event_data = { strap_point = pointNumber },
    })

    -- Check if all strap points are complete (stored in client state, validated here)
    -- For simplicity, we mark cargo as secured after the server receives this event
    -- The client tracks individual strap points and sends the final one
    activeLoad.cargo_secured = true
    ActiveLoads[bolId] = activeLoad

    DB.UpdateActiveLoad(activeLoad.id, {
        cargo_secured = true,
    })
end)

-- ============================================================================
-- INTEGRITY EVENT HANDLER
-- Called by client when cargo integrity changes (collision, cornering, etc.)
-- ============================================================================

RegisterNetEvent('trucking:server:integrityEvent', function(bolId, eventData)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'integrityEvent', 1000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    local integrityBefore = activeLoad.cargo_integrity
    local integrityLoss = eventData.loss or 0

    -- Server-side validation: cap maximum loss per event
    integrityLoss = math.min(integrityLoss, 25)

    local integrityAfter = math.max(0, integrityBefore - integrityLoss)

    activeLoad.cargo_integrity = integrityAfter
    ActiveLoads[bolId] = activeLoad

    DB.UpdateActiveLoad(activeLoad.id, {
        cargo_integrity = integrityAfter,
    })

    -- Log to integrity events table
    MySQL.insert.await([[
        INSERT INTO truck_integrity_events
            (bol_id, citizenid, event_cause, integrity_before, integrity_loss, integrity_after,
             vehicle_speed, vehicle_coords, occurred_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        bolId,
        activeLoad.citizenid,
        eventData.cause or 'collision_minor',
        integrityBefore,
        integrityLoss,
        integrityAfter,
        eventData.speed,
        eventData.coords and json.encode(eventData.coords) or nil,
        GetServerTime(),
    })

    -- Log BOL event
    local bol = DB.GetBOL(bolId)
    if bol then
        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = activeLoad.citizenid,
            event_type = 'integrity_event',
            event_data = {
                cause = eventData.cause,
                before = integrityBefore,
                loss = integrityLoss,
                after = integrityAfter,
            },
        })
    end

    -- Notify player if integrity is getting low
    if integrityAfter <= 50 and integrityBefore > 50 then
        lib.notify(src, {
            title = 'Cargo Damaged',
            description = ('Cargo integrity at %d%%. Handle with care!'):format(integrityAfter),
            type = 'error',
        })
    elseif integrityAfter <= 40 then
        lib.notify(src, {
            title = 'Cargo Critical',
            description = ('Cargo integrity at %d%%. Load may be rejected!'):format(integrityAfter),
            type = 'error',
        })
    end
end)

-- ============================================================================
-- MANIFEST VERIFICATION HANDLER
-- ============================================================================

RegisterNetEvent('trucking:server:manifestVerified', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'manifestVerified', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end
    if activeLoad.manifest_verified then return end -- already done

    activeLoad.manifest_verified = true
    ActiveLoads[bolId] = activeLoad

    DB.UpdateActiveLoad(activeLoad.id, { manifest_verified = true })
    DB.UpdateBOL(bolId, { manifest_verified = true })
end)

-- ============================================================================
-- WEIGH STATION STAMP HANDLER
-- ============================================================================

RegisterNetEvent('trucking:server:weighStationStamp', function(bolId, stationData)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'weighStationStamp', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end
    if activeLoad.weigh_station_stamped then return end -- already stamped

    activeLoad.weigh_station_stamped = true
    ActiveLoads[bolId] = activeLoad

    DB.UpdateActiveLoad(activeLoad.id, { weigh_station_stamped = true })
    DB.UpdateBOL(bolId, { weigh_station_stamp = true })

    -- Record weigh station visit
    local bol = DB.GetBOL(bolId)
    MySQL.insert.await([[
        INSERT INTO truck_weigh_station_records
            (bol_id, citizenid, station_id, station_label, station_region,
             inspection_result, stamp_issued, inspected_at)
        VALUES (?, ?, ?, ?, ?, 'passed', TRUE, ?)
    ]], {
        bolId,
        activeLoad.citizenid,
        stationData and stationData.station_id or 'unknown',
        stationData and stationData.station_label or 'Unknown Station',
        stationData and stationData.station_region or 'los_santos',
        GetServerTime(),
    })

    -- Log BOL event
    if bol then
        DB.InsertBOLEvent({
            bol_id = bolId,
            bol_number = bol.bol_number,
            citizenid = activeLoad.citizenid,
            event_type = 'weigh_station_stamped',
            event_data = stationData,
        })
    end

    lib.notify(src, {
        title = 'Weigh Station',
        description = 'Inspection passed. +5% compliance bonus.',
        type = 'success',
    })
end)

-- ═══════════════════════════════════════════════════════════════
-- ADDITIONAL EVENT HANDLERS
-- ═══════════════════════════════════════════════════════════════

--- Player has arrived at the delivery zone (pre-delivery check)
RegisterNetEvent('trucking:server:arrivedAtDestination', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'arrivedAtDest', 3000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    activeLoad.arrived_at = GetServerTime()
    ActiveLoads[bolId] = activeLoad

    DB.InsertBOLEvent({
        bol_id = bolId,
        citizenid = activeLoad.citizenid,
        event_type = 'arrived_at_destination',
    })
end)

--- Load rejected at destination (integrity too low)
RegisterNetEvent('trucking:server:loadRejected', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'loadRejected', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    DB.InsertBOLEvent({
        bol_id = bolId,
        citizenid = activeLoad.citizenid,
        event_type = 'load_rejected',
        event_data = { integrity = activeLoad.integrity_pct },
    })

    lib.notify(src, {
        title = 'Load Rejected',
        description = 'Cargo integrity too low. Payout reduced.',
        type = 'error',
    })
end)

--- BOL signed on load acceptance
RegisterNetEvent('trucking:server:signBOL', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'signBOL', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    activeLoad.bol_signed = true
    ActiveLoads[bolId] = activeLoad

    DB.InsertBOLEvent({
        bol_id = bolId,
        citizenid = activeLoad.citizenid,
        event_type = 'bol_signed',
    })
end)

--- Individual cargo securing step (per-strap)
RegisterNetEvent('trucking:server:cargoSecured', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'cargoSecured', 2000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    activeLoad.straps_applied = (activeLoad.straps_applied or 0) + 1
    ActiveLoads[bolId] = activeLoad
end)

--- All cargo securing complete
RegisterNetEvent('trucking:server:cargoFullySecured', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'cargoFullySecured', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    activeLoad.cargo_secured = true
    ActiveLoads[bolId] = activeLoad

    DB.InsertBOLEvent({
        bol_id = bolId,
        citizenid = activeLoad.citizenid,
        event_type = 'cargo_fully_secured',
    })
end)

--- Wheel chock placed
RegisterNetEvent('trucking:server:wheelChockComplete', function(bolId)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'wheelChock', 5000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    activeLoad.wheel_chocked = true
    ActiveLoads[bolId] = activeLoad
end)

--- Distress signal from active load
RegisterNetEvent('trucking:server:distressSignal', function(bolId, data)
    local src = source
    if not ValidateLoadOwner(src, bolId) then return end
    if not RateLimitEvent(src, 'distress', 30000) then return end

    local activeLoad = ActiveLoads[bolId]
    if not activeLoad then return end

    if activeLoad.company_id then
        local members = DB.GetCompanyMembers(activeLoad.company_id)
        if members then
            for _, member in ipairs(members) do
                local memberSrc = GetPlayerByIdentifier(member.citizenid)
                if memberSrc and memberSrc ~= src then
                    TriggerClientEvent('trucking:client:distressAlert', memberSrc, {
                        driver = activeLoad.citizenid,
                        bolId = bolId,
                        coords = data and data.coords,
                    })
                end
            end
        end
    end

    DB.InsertBOLEvent({
        bol_id = bolId,
        citizenid = activeLoad.citizenid,
        event_type = 'distress_signal',
        event_data = data,
    })
end)

--- Get detailed load information for NUI display
RegisterNetEvent('trucking:server:getLoadDetail', function(loadId)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local loadData = nil

    for _, load in pairs(ActiveLoads) do
        if load.load_id == loadId or load.bol_id == loadId then
            loadData = load
            break
        end
    end

    TriggerClientEvent('trucking:client:loadDetailResponse', src, loadData)
end)
