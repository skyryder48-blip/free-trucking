--[[
    config/economy.lua — Economy Configuration
    Free Trucking — QBX Framework

    All payout rates, multipliers, and financial tuning values.
    ServerMultiplier is the single knob for global economy scaling.
    Adjust it live via admin panel without restart.
]]

Economy = {}

-- ─────────────────────────────────────────────
-- GLOBAL SERVER MULTIPLIER
-- ─────────────────────────────────────────────
-- Tune this single value to scale ALL payouts across the board.
-- Start at 1.0, adjust during testing based on your server's economy.
-- 0.7 = 30% less everywhere, 1.3 = 30% more, etc.
-- Applied as Step 11 in payout calculation (after all other modifiers, before floor).
Economy.ServerMultiplier = 1.0

-- ─────────────────────────────────────────────
-- NIGHT HAUL PREMIUM
-- ─────────────────────────────────────────────
-- Deliveries completed during night hours receive a premium.
-- Server time is DB-synced via GetServerTime() on both sides.
Economy.NightHaulPremium = 0.07    -- +7% payout bonus
Economy.NightHaulStart   = 22      -- 22:00 server time
Economy.NightHaulEnd     = 6       -- 06:00 server time

-- ─────────────────────────────────────────────
-- BASE RATES PER MILE BY TIER (REBALANCED)
-- ─────────────────────────────────────────────
-- These are the foundation rates before any cargo modifier.
-- Chicago market rates + 15% COL premium, GTA map scale 1:3.5
Economy.BaseRates = {
    [0] = 25,      -- $25/mi — No CDL, entry level
    [1] = 42,      -- $42/mi — Class B CDL
    [2] = 65,      -- $65/mi — Class A CDL
    [3] = 95,      -- $95/mi — Class A + Endorsement/Certification
}

-- ─────────────────────────────────────────────
-- CARGO RATE MODIFIERS
-- ─────────────────────────────────────────────
-- Multiplied against the tier's base rate to produce effective $/mi.
-- Comments show effective rate: base * modifier = $/mi
Economy.CargoRateModifiers = {

    -- ── Tier 0 ($25 base) ──────────────────
    light_general_freight   = 1.00,    -- $25/mi  — general van/sprinter freight
    food_beverage_small     = 1.00,    -- $25/mi  — small food & beverage
    retail_small            = 1.00,    -- $25/mi  — small retail goods
    courier                 = 1.10,    -- $27/mi  — courier premium, short runs

    -- ── Tier 1 ($42 base) ──────────────────
    general_freight_full    = 1.00,    -- $42/mi  — full-size general freight
    building_materials      = 1.05,    -- $44/mi  — heavy, more vehicle wear
    food_beverage_full      = 1.00,    -- $42/mi  — full-size food & beverage
    food_beverage_reefer    = 1.10,    -- $46/mi  — reefer premium
    retail_full             = 1.00,    -- $42/mi  — full-size retail goods

    -- ── Tier 2 ($65 base) ──────────────────
    cold_chain              = 1.10,    -- $71/mi  — refrigerated cold chain
    pharmaceutical          = 1.55,    -- $101/mi T2, $147/mi T3 — strict temp control, Bilkington cert
    pharmaceutical_biologic = 1.70,    -- $110/mi T2, $161/mi T3 — biologics, ultra-strict
    fuel_tanker             = 1.12,    -- $73/mi  — tanker endorsement required
    liquid_bulk_food        = 1.08,    -- $70/mi  — food-grade liquid bulk
    liquid_bulk_industrial  = 1.05,    -- $68/mi  — industrial liquid bulk
    livestock               = 1.10,    -- $71/mi  — welfare monitoring required
    oversized               = 1.18,    -- $77/mi  — oversized permit, escort considerations
    oversized_heavy         = 1.30,    -- $84/mi  — heavy oversized, max weight bracket

    -- ── Tier 3 ($95 base) ──────────────────
    hazmat                  = 1.20,    -- $114/mi — HAZMAT endorsement required
    hazmat_class7           = 1.40,    -- $133/mi — radioactive, highest hazmat premium
    high_value              = 1.25,    -- $119/mi — high-value cert required
    military                = 1.50,    -- $142/mi — government clearance required
}

-- ─────────────────────────────────────────────
-- WEIGHT MULTIPLIERS
-- ─────────────────────────────────────────────
-- Heavier loads earn more. Brackets are cumulative (first match).
-- Weight in lbs as reported on the BOL.
Economy.WeightMultipliers = {
    { max = 10000,  multiplier = 1.00 },   -- light: no bonus
    { max = 26000,  multiplier = 1.15 },   -- medium: +15%
    { max = 40000,  multiplier = 1.30 },   -- heavy: +30%
    { max = 80001,  multiplier = 1.50 },   -- max legal: +50%
}

-- ─────────────────────────────────────────────
-- OWNER-OPERATOR BONUS BY TIER
-- ─────────────────────────────────────────────
-- Players using their own vehicle (not a rental) receive this bonus.
-- Higher tiers reward vehicle investment more.
Economy.OwnerOpBonus = {
    [0] = 0.20,    -- +20% for using own van/sprinter
    [1] = 0.20,    -- +20% for own straight truck
    [2] = 0.25,    -- +25% for own class A rig
    [3] = 0.30,    -- +30% for own specialized equipment
}

-- ─────────────────────────────────────────────
-- TIME PERFORMANCE MODIFIERS
-- ─────────────────────────────────────────────
-- Based on actual delivery time vs delivery window.
-- timePct = actual_seconds / window_seconds
Economy.TimePerformance = {
    { maxPct = 0.80,  modifier =  0.15 },  -- under 80% of window: +15% early bonus
    { maxPct = 1.00,  modifier =  0.00 },  -- 80-100% of window: on time, no modifier
    { maxPct = 1.20,  modifier = -0.10 },  -- 100-120% of window: -10% late penalty
    { maxPct = 999,   modifier = -0.25 },  -- over 120% of window: -25% very late
}

-- ─────────────────────────────────────────────
-- CARGO INTEGRITY MODIFIERS
-- ─────────────────────────────────────────────
-- Based on remaining cargo integrity percentage at delivery.
-- Below IntegrityRejectionThreshold (40%), load is rejected entirely.
Economy.IntegrityModifiers = {
    { minPct = 90, modifier =  0.00 },     -- 90-100%: pristine, no modifier
    { minPct = 70, modifier = -0.10 },     -- 70-89%: minor damage, -10%
    { minPct = 50, modifier = -0.25 },     -- 50-69%: significant damage, -25%
    { minPct = 0,  modifier = -1.00 },     -- 0-49%: severe (but above rejection: -100% = $0 effective)
}
Economy.IntegrityRejectionThreshold = 40   -- below 40%: load refused, payout = $0, deposit forfeited

-- ─────────────────────────────────────────────
-- COMPLIANCE BONUSES (STACKABLE)
-- ─────────────────────────────────────────────
-- Each bonus is additive. Total capped at MaxComplianceStack.
-- These reward professional behavior without punishing absence.
Economy.ComplianceBonuses = {
    -- Procedural compliance
    weigh_station       = 0.05,    -- +5% for weigh station stamp
    seal_intact         = 0.05,    -- +5% for unbroken seal at delivery
    clean_bol           = 0.05,    -- +5% for no CDL mismatch or flags
    pre_trip            = 0.03,    -- +3% for pre-trip inspection completed
    manifest_verified   = 0.03,    -- +3% for manifest verification at origin

    -- Shipper relationship bonuses
    shipper_rep_t2      = 0.05,    -- +5% for Established shipper rep
    shipper_rep_t3      = 0.10,    -- +10% for Trusted shipper rep
    shipper_rep_t4      = 0.15,    -- +15% for Preferred shipper rep

    -- Specialty compliance
    cold_chain_clean    = 0.05,    -- +5% for zero temperature excursions
    livestock_excellent = 0.10,    -- +10% for 5-star welfare rating

    -- Convoy bonuses
    convoy_2            = 0.08,    -- +8% for 2-truck convoy
    convoy_3            = 0.12,    -- +12% for 3-truck convoy
    convoy_4plus        = 0.15,    -- +15% for 4+ truck convoy
}
Economy.MaxComplianceStack = 0.25  -- 25% maximum total compliance bonus cap

-- ─────────────────────────────────────────────
-- MULTI-STOP PREMIUM
-- ─────────────────────────────────────────────
-- Additional payout for loads with multiple delivery stops.
-- Plus a flat per-stop LTL (less-than-truckload) bonus.
Economy.MultiStopPremium = {
    [2] = 0.15,    -- 2 stops: +15%
    [3] = 0.25,    -- 3 stops: +25%
    [4] = 0.35,    -- 4 stops: +35%
    [5] = 0.45,    -- 5 stops: +45%
    [6] = 0.55,    -- 6 stops: +55% (cap)
}
Economy.LTLFlatPerStop = 150       -- flat $150 per stop added to base

-- ─────────────────────────────────────────────
-- TEMPERATURE EXCURSION PAYOUT IMPACT
-- ─────────────────────────────────────────────
-- Applied to reefer/cold-chain loads based on excursion duration.
-- Duration thresholds defined in Config.ExcursionMinorMins / ExcursionSignificantMins.
Economy.ExcursionPenalties = {
    minor       =  0.00,   -- under 5 min: resolved quickly, no penalty
    significant = -0.15,   -- 5-15 min: -15% payout reduction
    critical    = -0.35,   -- over 15 min: -35% payout reduction
}

-- ─────────────────────────────────────────────
-- WELFARE MULTIPLIERS (LIVESTOCK)
-- ─────────────────────────────────────────────
-- Final welfare rating (1-5 stars) at delivery determines payout modifier.
-- Rating 5 (Excellent) also qualifies for compliance bonus.
Economy.WelfareMultipliers = {
    [5] =  0.20,   -- Excellent: +20% bonus
    [4] =  0.10,   -- Good: +10% bonus
    [3] =  0.00,   -- Fair: base rate, no modifier
    [2] = -0.15,   -- Poor: -15% penalty
    [1] = -0.40,   -- Critical: -40% penalty
}

-- ─────────────────────────────────────────────
-- INSURANCE RATES
-- ─────────────────────────────────────────────
-- Three policy types: single load, day, week.
-- T0 is exempt from insurance requirement but can still purchase.

-- Single load: percentage of estimated load value
Economy.InsuranceSingleLoadRate = 0.08     -- 8% of load value

-- Day policy: flat rate by tier, covers all loads for 24 hours
Economy.InsuranceDayRates = {
    [0] = 200,     -- $200/day  — T0 (optional)
    [1] = 450,     -- $450/day  — T1
    [2] = 900,     -- $900/day  — T2
    [3] = 1800,    -- $1,800/day — T3
}

-- Week policy: flat rate by tier, covers all loads for 7 days
Economy.InsuranceWeekRates = {
    [0] = 1000,    -- $1,000/week — T0 (optional)
    [1] = 2500,    -- $2,500/week — T1
    [2] = 5000,    -- $5,000/week — T2
    [3] = 9500,    -- $9,500/week — T3
}

-- Claim payout formula: (deposit * multiplier) + premium_allocated
Economy.ClaimPayoutMultiplier = 2          -- deposit x 2 + premium
