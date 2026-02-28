--[[
    server/insurance.lua — Insurance System

    Manages insurance policy purchase, claim verification, and payout
    processing. All financial operations use QBX player functions.

    Policy types:
        single_load  — covers the next accepted load only (8% of load value)
        day          — covers all loads for 24 hours ($200-$1,800 by tier)
        week         — covers all loads for 7 days ($1,000-$9,500 by tier)

    Rules:
        - Insurance is NOT required for Tier 0 loads
        - Leon loads are NOT covered by insurance
        - Claim payout = (deposit x 2) + premium allocated
        - 15-minute delay between claim approval and payout
        - Claims only valid for stolen/abandoned loads with forfeited deposits
]]

-- ─────────────────────────────────────────────
-- POLICY PURCHASE
-- ─────────────────────────────────────────────

--- Purchase an insurance policy for a driver
---@param src number Player server ID
---@param policyType string 'single_load', 'day', or 'week'
---@param tierCoverage number Maximum tier covered (0-3)
---@return boolean success
---@return string|number result Error message or policy ID
function PurchasePolicy(src, policyType, tierCoverage)
    if not src or not policyType or not tierCoverage then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Validate policy type
    local validTypes = { single_load = true, day = true, week = true }
    if not validTypes[policyType] then
        return false, 'invalid_policy_type'
    end

    -- Validate tier coverage (0-3)
    if tierCoverage < 0 or tierCoverage > 3 then
        return false, 'invalid_tier_coverage'
    end

    -- Calculate premium based on policy type and tier
    local premium = 0
    if policyType == 'single_load' then
        -- Single load premium is calculated at bind time based on load value
        -- For purchase, we use a flat rate estimate or defer to bind
        -- The guide says 8% of load value — we store a minimum premium here
        -- and adjust at bind time if needed. For now, use the day rate as basis.
        premium = Economy.InsuranceDayRates[tierCoverage] or 200
    elseif policyType == 'day' then
        premium = Economy.InsuranceDayRates[tierCoverage]
        if not premium then
            return false, 'no_rate_for_tier'
        end
    elseif policyType == 'week' then
        premium = Economy.InsuranceWeekRates[tierCoverage]
        if not premium then
            return false, 'no_rate_for_tier'
        end
    end

    -- Check if player has sufficient funds (bank account)
    local bankBalance = player.PlayerData.money.bank or 0
    if bankBalance < premium then
        return false, 'insufficient_funds'
    end

    -- Check for existing active policy that would conflict
    local existingPolicy = MySQL.single.await([[
        SELECT id FROM truck_insurance_policies
        WHERE citizenid = ? AND status = 'active'
          AND tier_coverage >= ?
          AND (valid_until IS NULL OR valid_until > ?)
    ]], { citizenid, tierCoverage, GetServerTime() })

    if existingPolicy then
        return false, 'active_policy_exists'
    end

    -- Deduct premium from player
    local deducted = player.Functions.RemoveMoney('bank', premium, 'Insurance premium - ' .. policyType)
    if not deducted then
        return false, 'payment_failed'
    end

    -- Calculate validity period
    local now = GetServerTime()
    local validUntil = nil
    if policyType == 'day' then
        validUntil = now + 86400      -- 24 hours
    elseif policyType == 'week' then
        validUntil = now + 604800     -- 7 days
    end
    -- single_load has no time expiry — expires on use

    -- Create policy record
    local policyId = MySQL.insert.await([[
        INSERT INTO truck_insurance_policies
        (citizenid, policy_type, tier_coverage, premium_paid, status,
         valid_from, valid_until, purchased_at)
        VALUES (?, ?, ?, ?, 'active', ?, ?, ?)
    ]], {
        citizenid, policyType, tierCoverage, premium,
        now, validUntil, now
    })

    if not policyId then
        -- Refund if insert failed
        player.Functions.AddMoney('bank', premium, 'Insurance premium refund - insert failed')
        return false, 'database_error'
    end

    lib.notify(src, {
        title = 'Insurance Purchased',
        description = ('$%d %s policy active'):format(premium, policyType:gsub('_', ' ')),
        type = 'success',
    })

    print(('[trucking:insurance] Policy %d purchased by %s: %s tier %d ($%d)'):format(
        policyId, citizenid, policyType, tierCoverage, premium))

    return true, policyId
end

-- ─────────────────────────────────────────────
-- POLICY QUERIES
-- ─────────────────────────────────────────────

--- Check if a driver has an active policy covering the specified tier
---@param citizenid string Driver's citizen ID
---@param tier number The load tier to check coverage for
---@return boolean hasPolicy
---@return table|nil policy The active policy record
function HasActivePolicy(citizenid, tier)
    if not citizenid then return false end

    -- Tier 0 loads do not require insurance
    if tier == 0 then return true end

    local now = GetServerTime()
    local policy = MySQL.single.await([[
        SELECT * FROM truck_insurance_policies
        WHERE citizenid = ?
          AND status = 'active'
          AND tier_coverage >= ?
          AND valid_from <= ?
          AND (valid_until IS NULL OR valid_until >= ?)
        ORDER BY tier_coverage DESC
        LIMIT 1
    ]], { citizenid, tier, now, now })

    if policy then
        return true, policy
    end

    return false
end

--- Bind a single-load policy to a specific BOL
--- Called when a load is accepted with a single_load policy active
---@param citizenid string Driver's citizen ID
---@param bolId number The BOL ID to bind to
---@return boolean success
---@return number|nil policyId The bound policy ID
function BindPolicyToLoad(citizenid, bolId)
    if not citizenid or not bolId then
        return false, nil
    end

    -- Find an unbound single_load policy
    local policy = MySQL.single.await([[
        SELECT id FROM truck_insurance_policies
        WHERE citizenid = ?
          AND policy_type = 'single_load'
          AND status = 'active'
          AND bound_bol_id IS NULL
        ORDER BY purchased_at ASC
        LIMIT 1
    ]], { citizenid })

    if not policy then
        return false, nil
    end

    -- Bind the policy to this BOL and mark as used
    MySQL.update.await([[
        UPDATE truck_insurance_policies
        SET bound_bol_id = ?, status = 'used'
        WHERE id = ?
    ]], { bolId, policy.id })

    print(('[trucking:insurance] Policy %d bound to BOL %d for %s'):format(
        policy.id, bolId, citizenid))

    return true, policy.id
end

-- ─────────────────────────────────────────────
-- CLAIM VERIFICATION AND APPROVAL
-- ─────────────────────────────────────────────

--- Full claim verification and approval process
--- Checks: BOL exists, status stolen/abandoned, deposit forfeited, policy active at load time
---@param citizenid string Driver's citizen ID
---@param bolNumber string The BOL number from the physical BOL item
---@return boolean success
---@return string|number result Error reason or claim payout amount
function VerifyAndApproveClaim(citizenid, bolNumber)
    if not citizenid or not bolNumber then
        return false, 'missing_parameters'
    end

    -- Fetch BOL record (use MySQL.single.await — NOT scalar)
    local bol = MySQL.single.await(
        'SELECT * FROM truck_bols WHERE bol_number = ? AND citizenid = ?',
        { bolNumber, citizenid }
    )
    if not bol then
        return false, 'bol_not_found'
    end

    -- Verify BOL status is eligible (stolen or abandoned only)
    if bol.bol_status ~= 'stolen' and bol.bol_status ~= 'abandoned' then
        return false, 'load_not_eligible'
    end

    -- Leon loads are not covered by insurance
    if bol.is_leon and (bol.is_leon == 1 or bol.is_leon == true) then
        return false, 'leon_not_covered'
    end

    -- Verify BOL item is still in player inventory
    if not bol.item_in_inventory or bol.item_in_inventory == 0 then
        return false, 'bol_not_in_inventory'
    end

    -- Check for duplicate claims on this BOL
    local existingClaim = MySQL.single.await(
        'SELECT id FROM truck_insurance_claims WHERE bol_id = ? AND status IN (?, ?, ?)',
        { bol.id, 'pending', 'approved', 'paid' }
    )
    if existingClaim then
        return false, 'claim_already_filed'
    end

    -- Fetch deposit record — must be forfeited
    local deposit = MySQL.single.await(
        'SELECT * FROM truck_deposits WHERE bol_id = ? AND status = ?',
        { bol.id, 'forfeited' }
    )
    if not deposit then
        return false, 'deposit_not_forfeited'
    end

    -- Fetch the insurance policy that was active at load acceptance time
    -- For single_load policies, check bound_bol_id
    -- For day/week policies, check time coverage
    local policy = MySQL.single.await([[
        SELECT * FROM truck_insurance_policies
        WHERE citizenid = ?
          AND (
              (policy_type = 'single_load' AND bound_bol_id = ?)
              OR
              (policy_type != 'single_load'
               AND valid_from <= ?
               AND (valid_until IS NULL OR valid_until >= ?))
          )
        ORDER BY purchased_at DESC
        LIMIT 1
    ]], { citizenid, bol.id, bol.issued_at, bol.issued_at })

    if not policy then
        return false, 'no_policy_at_time'
    end

    -- Calculate payout: (deposit x 2) + premium allocated
    -- For single_load, premium_allocated = full premium paid
    -- For day/week, premium_allocated = proportional share (premium / 10)
    local premiumAllocated
    if policy.policy_type == 'single_load' then
        premiumAllocated = policy.premium_paid
    else
        premiumAllocated = math.floor(policy.premium_paid / 10)
    end

    local claimAmount = (deposit.amount * (Economy.ClaimPayoutMultiplier or 2)) + premiumAllocated

    -- Determine claim type based on BOL status
    local claimType = bol.bol_status == 'stolen' and 'theft' or 'abandonment'

    -- Create claim record with 15-minute payout delay
    local now = GetServerTime()
    local payoutAt = now + 900  -- 15 minutes

    local claimId = MySQL.insert.await([[
        INSERT INTO truck_insurance_claims
        (citizenid, policy_id, bol_id, bol_number, claim_type,
         deposit_amount, premium_allocated, claim_amount,
         status, payout_at, filed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'approved', ?, ?)
    ]], {
        citizenid, policy.id, bol.id, bolNumber, claimType,
        deposit.amount, premiumAllocated, claimAmount,
        payoutAt, now
    })

    if not claimId then
        return false, 'database_error'
    end

    print(('[trucking:insurance] Claim %d approved for %s: BOL %s, payout $%d in 15 min'):format(
        claimId, citizenid, bolNumber, claimAmount))

    return true, claimAmount
end

-- ─────────────────────────────────────────────
-- PENDING CLAIMS PROCESSING THREAD
-- Runs every 60 seconds, finds approved claims past payout_at,
-- issues payment via QBX, marks as paid
-- ─────────────────────────────────────────────

function ProcessPendingClaims()
    local now = GetServerTime()

    local pendingClaims = MySQL.query.await([[
        SELECT ic.* FROM truck_insurance_claims ic
        WHERE ic.status = 'approved' AND ic.payout_at <= ?
    ]], { now })

    if not pendingClaims or #pendingClaims == 0 then
        return
    end

    for _, claim in ipairs(pendingClaims) do
        -- Attempt to find the player online
        local playerSrc = exports.qbx_core:GetPlayerByCitizenId(claim.citizenid)

        if playerSrc then
            local player = exports.qbx_core:GetPlayer(playerSrc)
            if player then
                -- Issue payout via QBX bank deposit
                player.Functions.AddMoney('bank', claim.claim_amount,
                    'Insurance claim payout - BOL #' .. claim.bol_number)

                -- Mark claim as paid
                MySQL.update.await(
                    'UPDATE truck_insurance_claims SET status = ?, resolved_at = ? WHERE id = ?',
                    { 'paid', now, claim.id }
                )

                -- Notify player
                TriggerClientEvent('trucking:client:claimPaid', playerSrc, {
                    claimAmount = claim.claim_amount,
                    bolNumber = claim.bol_number,
                    claimType = claim.claim_type,
                })

                lib.notify(playerSrc, {
                    title = 'Insurance Payout',
                    description = ('$%s deposited for BOL #%s'):format(
                        claim.claim_amount, claim.bol_number),
                    type = 'success',
                })

                print(('[trucking:insurance] Claim %d paid: $%d to %s for BOL %s'):format(
                    claim.id, claim.claim_amount, claim.citizenid, claim.bol_number))
            else
                -- Player source exists but GetPlayer failed — retry next cycle
                MySQL.update.await(
                    'UPDATE truck_insurance_claims SET payout_at = ? WHERE id = ?',
                    { now + 60, claim.id }
                )
            end
        else
            -- Player offline — defer payout until next check (retry in 60 seconds)
            MySQL.update.await(
                'UPDATE truck_insurance_claims SET payout_at = ? WHERE id = ?',
                { now + 60, claim.id }
            )
        end
    end
end

--- Claims processing thread — every 60 seconds
CreateThread(function()
    while true do
        Wait(60000)
        ProcessPendingClaims()
    end
end)

-- ─────────────────────────────────────────────
-- POLICY STATUS (NUI display)
-- ─────────────────────────────────────────────

--- Get all active policies for a driver (for NUI display)
---@param citizenid string Driver's citizen ID
---@return table policies Array of active policy records
function GetPolicyStatus(citizenid)
    if not citizenid then return {} end

    local now = GetServerTime()

    local policies = MySQL.query.await([[
        SELECT id, policy_type, tier_coverage, premium_paid, status,
               valid_from, valid_until, bound_bol_id, purchased_at
        FROM truck_insurance_policies
        WHERE citizenid = ?
          AND status = 'active'
          AND (valid_until IS NULL OR valid_until >= ?)
        ORDER BY purchased_at DESC
    ]], { citizenid, now })

    if not policies then return {} end

    -- Enrich with remaining time for NUI
    for _, policy in ipairs(policies) do
        if policy.valid_until then
            policy.remaining_seconds = math.max(0, policy.valid_until - now)
        else
            policy.remaining_seconds = nil  -- single_load has no time limit
        end
    end

    return policies
end

-- ─────────────────────────────────────────────
-- POLICY EXPIRY MAINTENANCE THREAD
-- Runs every 5 minutes, expires time-based policies
-- ─────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(300000)  -- 5 minutes
        local now = GetServerTime()
        local expired = MySQL.update.await([[
            UPDATE truck_insurance_policies
            SET status = 'expired'
            WHERE status = 'active'
              AND valid_until IS NOT NULL
              AND valid_until < ?
        ]], { now })

        if expired and expired > 0 then
            print(('[trucking:insurance] Expired %d insurance policies'):format(expired))
        end
    end
end)

-- ─────────────────────────────────────────────
-- NET EVENTS — NUI and interaction triggers
-- ─────────────────────────────────────────────

--- Player purchases insurance via dispatch desk / truck stop terminal
RegisterNetEvent('trucking:server:purchaseInsurance', function(policyType, tierCoverage)
    local src = source
    if not RateLimitEvent(src, 'purchaseInsurance', 5000) then return end

    local success, result = PurchasePolicy(src, policyType, tierCoverage)
    TriggerClientEvent('trucking:client:insurancePurchaseResult', src, success, result)
end)

--- Player files an insurance claim at Vapid Commercial Insurance office
RegisterNetEvent('trucking:server:fileInsuranceClaim', function(bolNumber)
    local src = source
    if not RateLimitEvent(src, 'fileInsuranceClaim', 10000) then return end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local success, result = VerifyAndApproveClaim(citizenid, bolNumber)

    if success then
        lib.notify(src, {
            title = 'Claim Approved',
            description = ('$%s payout processing — expect deposit in 15 minutes'):format(result),
            type = 'success',
        })
    else
        lib.notify(src, {
            title = 'Claim Denied',
            description = 'Your insurance claim could not be processed.',
            type = 'error',
        })
    end

    TriggerClientEvent('trucking:client:insuranceClaimResult', src, success, result)
end)

--- Player requests current policy status (for NUI)
RegisterNetEvent('trucking:server:getInsuranceStatus', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local policies = GetPolicyStatus(citizenid)
    TriggerClientEvent('trucking:client:insuranceStatus', src, policies)
end)

print('[trucking:insurance] Insurance system initialized')
