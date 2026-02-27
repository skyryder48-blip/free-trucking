--[[
    server/payout.lua
    Complete 12-step payout calculation engine (Section 6.2 / Section 8).

    This is the authoritative server-side payout calculator. Every dollar
    issued to a player passes through this function. No payout logic exists
    on the client.

    The 12-step pipeline:
      1. Base rate (tier base x cargo modifier x distance)
      2. Multi-stop premium
      3. Weight multiplier
      4. Owner-op bonus
      5. Time performance modifier
      6. Integrity check (reject if below 40%)
      7. Temperature excursion penalty
      8. Livestock welfare multiplier
      9. Compliance bonuses (capped at 25%)
      10. Night haul premium (+7% if 22:00-06:00)
      11. Server multiplier (Economy.ServerMultiplier)
      12. Floor check (minimum payout by tier)

    Returns: final amount, status ('success'/'rejected'), breakdown table
]]

-- ============================================================================
-- MAIN PAYOUT FUNCTION
-- ============================================================================

--- Calculate the final payout for a delivered load.
--- This is the complete 12-step calculation from the development guide.
---@param activeLoad table  Row from truck_active_loads (or ActiveLoads in-memory)
---@param bolRecord table   Row from truck_bols
---@param deliveryData table  { delivered_at = unix_timestamp }
---@return number finalAmount  Dollar amount to pay the driver
---@return string status  'success' or 'rejected'
---@return table breakdown  Detailed breakdown for receipt display
function CalculatePayout(activeLoad, bolRecord, deliveryData)
    local cargo = CargoTypes and CargoTypes[bolRecord.cargo_type] or {}
    local shipper = Shippers and Shippers[bolRecord.shipper_id] or {}
    local tier = bolRecord.tier or 0
    local distance = bolRecord.distance_miles or 1

    -- Accumulate breakdown data for the receipt
    local breakdown = {
        steps = {},
    }

    -- ========================================================================
    -- STEP 1: Base rate
    -- base = (tier base rate) x (cargo rate modifier) x (distance in miles)
    -- ========================================================================
    local baseRate = Economy.BaseRates[tier] or 25
    local cargoModifierKey = cargo.rate_modifier_key or bolRecord.cargo_type
    local cargoModifier = Economy.CargoRateModifiers[cargoModifierKey] or 1.0
    local ratePerMile = baseRate * cargoModifier
    local base = ratePerMile * distance

    breakdown.base_rate = baseRate
    breakdown.cargo_modifier = cargoModifier
    breakdown.rate_per_mile = ratePerMile
    breakdown.distance = distance
    breakdown.step1_base = base
    breakdown.steps[#breakdown.steps + 1] = {
        step = 1,
        label = 'Base Rate',
        detail = ('$%.2f/mi x %.2f mi'):format(ratePerMile, distance),
        value = base,
    }

    -- ========================================================================
    -- STEP 2: Multi-stop premium
    -- If the load has multiple stops, apply a percentage premium + LTL flat fee
    -- ========================================================================
    local multiStopPremium = 0
    local ltlFlat = 0

    -- Get stop count from the load record or active load
    local stopCount = activeLoad.stop_count
    if not stopCount then
        -- Fetch from the load table if not on activeLoad
        local loadRow = DB.GetLoad(activeLoad.load_id)
        stopCount = loadRow and loadRow.stop_count or 1
    end

    if stopCount and stopCount > 1 then
        local premiumPct = Economy.MultiStopPremium[math.min(stopCount, 6)] or 0.55
        multiStopPremium = base * premiumPct
        ltlFlat = (Economy.LTLFlatPerStop or 150) * stopCount
        base = base + multiStopPremium + ltlFlat

        breakdown.steps[#breakdown.steps + 1] = {
            step = 2,
            label = 'Multi-Stop Premium',
            detail = ('%d stops: +%d%% ($%.0f) + $%d LTL flat'):format(
                stopCount, premiumPct * 100, multiStopPremium, ltlFlat
            ),
            value = multiStopPremium + ltlFlat,
        }
    end
    breakdown.step2_multistop = multiStopPremium + ltlFlat

    -- ========================================================================
    -- STEP 3: Weight multiplier
    -- Heavier loads earn more. Brackets defined in Economy.WeightMultipliers.
    -- ========================================================================
    local weightMult = GetWeightMultiplier(bolRecord.weight_lbs)
    local weightBonus = base * (weightMult - 1)
    base = base * weightMult

    breakdown.weight_lbs = bolRecord.weight_lbs
    breakdown.weight_mult = weightMult
    breakdown.step3_weight = weightBonus
    breakdown.steps[#breakdown.steps + 1] = {
        step = 3,
        label = 'Weight Multiplier',
        detail = ('%d lbs: x%.2f'):format(bolRecord.weight_lbs, weightMult),
        value = weightBonus,
    }

    -- ========================================================================
    -- STEP 4: Owner-operator bonus
    -- Drivers using their own vehicle (not a rental) earn a tier-based bonus.
    -- ========================================================================
    local ownerOpApplied = false
    local ownerOpBonus = 0
    if not activeLoad.is_rental then
        local bonusPct = Economy.OwnerOpBonus[tier] or 0.20
        ownerOpBonus = base * bonusPct
        base = base + ownerOpBonus
        ownerOpApplied = true

        breakdown.steps[#breakdown.steps + 1] = {
            step = 4,
            label = 'Owner-Operator Bonus',
            detail = ('+%d%%'):format(bonusPct * 100),
            value = ownerOpBonus,
        }
    end
    breakdown.owner_op = ownerOpApplied
    breakdown.step4_ownerop = ownerOpBonus

    -- ========================================================================
    -- STEP 5: Time performance modifier
    -- Compare actual delivery time to the allotted window.
    -- Early = bonus, late = penalty.
    -- ========================================================================
    local windowSeconds = activeLoad.window_expires_at - activeLoad.accepted_at
    local actualSeconds = deliveryData.delivered_at - activeLoad.accepted_at
    local timePct = actualSeconds / math.max(windowSeconds, 1) -- prevent division by zero

    local timeModifier = GetTimeModifier(timePct)
    local timeBonus = base * timeModifier
    base = base + timeBonus

    breakdown.time_pct = timePct
    breakdown.time_mod = timeModifier
    breakdown.step5_time = timeBonus
    breakdown.steps[#breakdown.steps + 1] = {
        step = 5,
        label = 'Time Performance',
        detail = ('%.0f%% of window: %s%d%%'):format(
            timePct * 100,
            timeModifier >= 0 and '+' or '',
            timeModifier * 100
        ),
        value = timeBonus,
    }

    -- ========================================================================
    -- STEP 6: Integrity check
    -- If cargo integrity is below the rejection threshold (40%), the load
    -- is refused entirely. No payout, deposit forfeited.
    -- ========================================================================
    local integrity = activeLoad.cargo_integrity or 100
    local rejectionThreshold = Economy.IntegrityRejectionThreshold or 40

    if integrity < rejectionThreshold then
        breakdown.integrity = integrity
        breakdown.rejected = true
        breakdown.rejection_reason = 'integrity_below_threshold'
        breakdown.steps[#breakdown.steps + 1] = {
            step = 6,
            label = 'Integrity Check',
            detail = ('%d%% -- REJECTED (below %d%% threshold)'):format(integrity, rejectionThreshold),
            value = 0,
        }
        return 0, 'rejected', breakdown
    end

    local integrityMod = GetIntegrityModifier(integrity)
    local integrityPenalty = base * integrityMod
    base = base + integrityPenalty

    breakdown.integrity = integrity
    breakdown.integrity_mod = integrityMod
    breakdown.step6_integrity = integrityPenalty
    breakdown.steps[#breakdown.steps + 1] = {
        step = 6,
        label = 'Cargo Integrity',
        detail = ('%d%%: %s%d%%'):format(
            integrity,
            integrityMod >= 0 and '+' or '',
            integrityMod * 100
        ),
        value = integrityPenalty,
    }

    -- ========================================================================
    -- STEP 7: Temperature excursion penalty
    -- For loads requiring temperature control (cold chain, pharmaceutical).
    -- Severity based on total excursion duration.
    -- ========================================================================
    local tempPenalty = 0
    local tempCompliance = bolRecord.temp_compliance or 'not_required'

    if tempCompliance ~= 'not_required' then
        local tempMod = 0
        if tempCompliance == 'clean' then
            tempMod = Economy.ExcursionPenalties.minor or 0 -- clean = no penalty
        elseif tempCompliance == 'minor_excursion' then
            tempMod = Economy.ExcursionPenalties.significant or -0.15
        elseif tempCompliance == 'significant_excursion' then
            tempMod = Economy.ExcursionPenalties.critical or -0.35
        end

        tempPenalty = base * tempMod
        base = base + tempPenalty

        breakdown.steps[#breakdown.steps + 1] = {
            step = 7,
            label = 'Temperature Excursion',
            detail = ('%s: %s%d%%'):format(
                tempCompliance,
                tempMod >= 0 and '' or '',
                tempMod * 100
            ),
            value = tempPenalty,
        }
    end
    breakdown.temp_compliance = tempCompliance
    breakdown.step7_temp = tempPenalty

    -- ========================================================================
    -- STEP 8: Livestock welfare multiplier
    -- For livestock loads, the final welfare rating (1-5) determines a
    -- multiplier that can boost or penalize the payout significantly.
    -- ========================================================================
    local welfareMod = 0
    local welfareBonus = 0

    if activeLoad.welfare_rating and activeLoad.welfare_rating > 0 then
        welfareMod = Economy.WelfareMultipliers[activeLoad.welfare_rating] or 0
        welfareBonus = base * welfareMod
        base = base + welfareBonus

        local welfareLabels = { [1] = 'Critical', [2] = 'Poor', [3] = 'Fair', [4] = 'Good', [5] = 'Excellent' }
        breakdown.steps[#breakdown.steps + 1] = {
            step = 8,
            label = 'Livestock Welfare',
            detail = ('%s (%d/5): %s%d%%'):format(
                welfareLabels[activeLoad.welfare_rating] or '?',
                activeLoad.welfare_rating,
                welfareMod >= 0 and '+' or '',
                welfareMod * 100
            ),
            value = welfareBonus,
        }
    end
    breakdown.welfare_rating = activeLoad.welfare_rating
    breakdown.step8_welfare = welfareBonus

    -- ========================================================================
    -- STEP 9: Compliance bonuses (capped at 25%)
    -- Stackable bonuses for completing optional compliance checks.
    -- ========================================================================
    local complianceTotal = 0
    local bonusList = {}

    -- Weigh station stamp
    if activeLoad.weigh_station_stamped then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.weigh_station or 0.05)
        bonusList[#bonusList + 1] = 'weigh_station'
    end

    -- Seal intact at delivery
    if activeLoad.seal_status == 'sealed' then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.seal_intact or 0.05)
        bonusList[#bonusList + 1] = 'seal_intact'
    end

    -- Clean BOL (no CDL mismatch)
    if bolRecord.license_matched ~= false then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.clean_bol or 0.05)
        bonusList[#bonusList + 1] = 'clean_bol'
    end

    -- Pre-trip inspection completed
    if activeLoad.pre_trip_completed then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.pre_trip or 0.03)
        bonusList[#bonusList + 1] = 'pre_trip'
    end

    -- Manifest verified
    if activeLoad.manifest_verified then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.manifest_verified or 0.03)
        bonusList[#bonusList + 1] = 'manifest_verified'
    end

    -- Shipper reputation bonus
    local shipperRepTier = GetShipperRepTier(bolRecord.citizenid, bolRecord.shipper_id)
    if shipperRepTier == 'established' then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.shipper_rep_t2 or 0.05)
        bonusList[#bonusList + 1] = 'shipper_rep_established'
    elseif shipperRepTier == 'trusted' then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.shipper_rep_t3 or 0.10)
        bonusList[#bonusList + 1] = 'shipper_rep_trusted'
    elseif shipperRepTier == 'preferred' then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.shipper_rep_t4 or 0.15)
        bonusList[#bonusList + 1] = 'shipper_rep_preferred'
    end

    -- Cold chain clean bonus
    if tempCompliance == 'clean' then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.cold_chain_clean or 0.05)
        bonusList[#bonusList + 1] = 'cold_chain_clean'
    end

    -- Livestock excellent bonus
    if activeLoad.welfare_rating and activeLoad.welfare_rating == 5 then
        complianceTotal = complianceTotal + (Economy.ComplianceBonuses.livestock_excellent or 0.10)
        bonusList[#bonusList + 1] = 'livestock_excellent'
    end

    -- Convoy bonus (if applicable)
    if activeLoad.convoy_id then
        local convoySize = GetConvoySize(activeLoad.convoy_id)
        local convoyBonus = 0
        if convoySize >= 4 then
            convoyBonus = Economy.ComplianceBonuses.convoy_4plus or 0.15
            bonusList[#bonusList + 1] = 'convoy_4plus'
        elseif convoySize == 3 then
            convoyBonus = Economy.ComplianceBonuses.convoy_3 or 0.12
            bonusList[#bonusList + 1] = 'convoy_3'
        elseif convoySize >= 2 then
            convoyBonus = Economy.ComplianceBonuses.convoy_2 or 0.08
            bonusList[#bonusList + 1] = 'convoy_2'
        end
        complianceTotal = complianceTotal + convoyBonus
    end

    -- Apply the compliance cap (25% max)
    local maxCompliance = Economy.MaxComplianceStack or 0.25
    local uncappedCompliance = complianceTotal
    complianceTotal = math.min(complianceTotal, maxCompliance)
    local complianceBonus = base * complianceTotal
    base = base + complianceBonus

    breakdown.bonuses_earned = bonusList
    breakdown.compliance_uncapped = uncappedCompliance
    breakdown.compliance_capped = complianceTotal
    breakdown.step9_compliance = complianceBonus
    breakdown.steps[#breakdown.steps + 1] = {
        step = 9,
        label = 'Compliance Bonuses',
        detail = ('%d bonuses: +%d%% (cap %d%%)'):format(
            #bonusList, math.floor(complianceTotal * 100), math.floor(maxCompliance * 100)
        ),
        value = complianceBonus,
        bonuses = bonusList,
    }

    -- ========================================================================
    -- STEP 10: Night haul premium
    -- +7% if the delivery occurs between 22:00 and 06:00 server time.
    -- ========================================================================
    local nightMod = 0
    local nightApplied = false
    local hour = tonumber(os.date('%H'))
    local nightStart = Economy.NightHaulStart or 22
    local nightEnd = Economy.NightHaulEnd or 6

    if hour >= nightStart or hour < nightEnd then
        nightMod = Economy.NightHaulPremium or 0.07
        nightApplied = true
        local nightBonus = base * nightMod
        base = base + nightBonus

        breakdown.steps[#breakdown.steps + 1] = {
            step = 10,
            label = 'Night Haul Premium',
            detail = ('+%d%% (hour: %02d:00)'):format(nightMod * 100, hour),
            value = nightBonus,
        }
    end
    breakdown.night_haul = nightApplied
    breakdown.night_mod = nightMod
    breakdown.step10_night = nightApplied and (base * nightMod / (1 + nightMod)) or 0

    -- ========================================================================
    -- STEP 11: Server multiplier
    -- Global economy tuning knob. Adjusts all payouts uniformly.
    -- Default 1.0 = no change. Set in Economy.ServerMultiplier.
    -- ========================================================================
    local serverMult = Economy.ServerMultiplier or 1.0
    base = base * serverMult

    breakdown.server_mult = serverMult
    breakdown.step11_server = base - (base / serverMult) -- delta from multiplier
    breakdown.steps[#breakdown.steps + 1] = {
        step = 11,
        label = 'Server Multiplier',
        detail = ('x%.2f'):format(serverMult),
        value = breakdown.step11_server,
    }

    -- ========================================================================
    -- STEP 12: Floor check
    -- Ensure the final payout is at least the minimum for this tier.
    -- ========================================================================
    local floor = Config.PayoutFloors[tier] or 150
    local finalAmount = math.max(math.floor(base), floor)
    local floorApplied = finalAmount == floor and math.floor(base) < floor

    breakdown.floor = floor
    breakdown.floor_applied = floorApplied
    breakdown.step12_floor = floorApplied and (floor - math.floor(base)) or 0
    breakdown.steps[#breakdown.steps + 1] = {
        step = 12,
        label = 'Floor Check',
        detail = floorApplied
            and ('Floor applied: $%d (calculated $%d)'):format(floor, math.floor(base))
            or ('$%d (above $%d floor)'):format(finalAmount, floor),
        value = floorApplied and breakdown.step12_floor or 0,
    }

    -- ========================================================================
    -- FINAL RESULT
    -- ========================================================================
    breakdown.final_amount = finalAmount
    breakdown.status = 'success'
    breakdown.tier = tier

    -- Fuel cost estimate (informational only, not deducted)
    local fuelCost = GetFuelCostEstimate(activeLoad, deliveryData)
    breakdown.fuel_cost_estimate = fuelCost
    breakdown.net_after_fuel = finalAmount - fuelCost

    return finalAmount, 'success', breakdown
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--- Get the weight multiplier for a given weight in lbs.
--- Brackets are defined in Economy.WeightMultipliers.
---@param weightLbs number
---@return number multiplier
function GetWeightMultiplier(weightLbs)
    if not Economy or not Economy.WeightMultipliers then return 1.0 end

    for _, bracket in ipairs(Economy.WeightMultipliers) do
        if weightLbs <= bracket.max then
            return bracket.multiplier
        end
    end

    -- If above all defined brackets, use the last one
    local lastBracket = Economy.WeightMultipliers[#Economy.WeightMultipliers]
    return lastBracket and lastBracket.multiplier or 1.50
end

--- Get the time performance modifier based on how fast the delivery was.
--- Brackets are defined in Economy.TimePerformance.
---@param timePct number  Ratio of actual time to window time (0.0 - 999.0)
---@return number modifier  Percentage modifier (-0.25 to +0.15)
function GetTimeModifier(timePct)
    if not Economy or not Economy.TimePerformance then return 0 end

    for _, bracket in ipairs(Economy.TimePerformance) do
        if timePct <= bracket.maxPct then
            return bracket.modifier
        end
    end

    -- Beyond all brackets, use the most punitive
    local lastBracket = Economy.TimePerformance[#Economy.TimePerformance]
    return lastBracket and lastBracket.modifier or -0.25
end

--- Get the cargo integrity modifier based on remaining integrity percentage.
--- Below the rejection threshold, the load is refused entirely (handled in step 6).
---@param integrityPct number  0-100
---@return number modifier  Percentage modifier (-1.0 to 0.0)
function GetIntegrityModifier(integrityPct)
    if not Economy or not Economy.IntegrityModifiers then return 0 end

    for _, bracket in ipairs(Economy.IntegrityModifiers) do
        if integrityPct >= bracket.minPct then
            return bracket.modifier
        end
    end

    -- Should not reach here if rejection threshold is handled first
    return -1.0
end

--- Get the size of a convoy (number of active members).
--- Used for the convoy compliance bonus calculation.
---@param convoyId number
---@return number size
function GetConvoySize(convoyId)
    if not convoyId then return 0 end

    local result = MySQL.single.await(
        'SELECT vehicle_count FROM truck_convoys WHERE id = ?',
        { convoyId }
    )

    return result and result.vehicle_count or 0
end

--- Get estimated fuel cost for the trip (informational only, not deducted from payout).
--- Integrates with the vehicle handling script via exports if available.
---@param activeLoad table
---@param deliveryData table
---@return number fuelCost
function GetFuelCostEstimate(activeLoad, deliveryData)
    -- Skip if fuel cost tracking is disabled
    if not Config or not Config.TrackFuelCosts then return 0 end

    -- Skip if no vehicle handling resource configured
    local fuelResource = Config.VehicleHandlingResource
    if not fuelResource or fuelResource == '' then return 0 end

    -- Attempt to read fuel data from the vehicle handling script
    local success, fuelUsed = pcall(function()
        return exports[fuelResource]:GetTripFuelConsumed(activeLoad.vehicle_plate)
    end)
    if not success or not fuelUsed then return 0 end

    local successPrice, pricePerUnit = pcall(function()
        return exports[fuelResource]:GetFuelPrice()
    end)
    if not successPrice or not pricePerUnit then
        pricePerUnit = 3.50 -- fallback default
    end

    return math.floor(fuelUsed * pricePerUnit)
end
