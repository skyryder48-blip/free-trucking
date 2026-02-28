--[[
    config/config.lua — Global Configuration
    Free Trucking — QBX Framework

    All global settings, thresholds, and integration configuration.
    Economy-specific values live in config/economy.lua.
    Board composition lives in config/board.lua.
]]

Config = {}

-- ─────────────────────────────────────────────
-- NUI MODE
-- ─────────────────────────────────────────────
-- Both can be true simultaneously for dual-mode operation.
-- If both are false, only ox_lib context menus are available.
Config.UsePhoneApp      = true    -- lb-phone integration (app inside phone)
Config.UseStandaloneNUI = true    -- standalone NUI panel (hotkey)
Config.NUIKey           = 'F6'    -- keybind for standalone NUI

-- ─────────────────────────────────────────────
-- INTEGRATION RESOURCES
-- ─────────────────────────────────────────────
-- Police/dispatch — array of resource names, first available is used
Config.PoliceResources          = { 'lb-dispatch', 'ultimate-le' }
Config.PhoneResource            = 'lb-phone'
Config.VehicleHandlingResource  = 'lc'         -- vehicle handling / fuel script
Config.TrackFuelCosts           = true         -- show fuel cost on payout receipt

-- ─────────────────────────────────────────────
-- DISCORD WEBHOOKS (set to nil to disable)
-- ─────────────────────────────────────────────
Config.Webhooks = {
    insurance   = nil,   -- insurance claims and payouts
    leon        = nil,   -- criminal system events
    military    = nil,   -- military contract and heist events
    admin       = nil,   -- admin actions and flagged events
    payout      = nil,   -- large payout alerts
    reputation  = nil,   -- suspension and major rep changes
}

-- ─────────────────────────────────────────────
-- BOARD SETTINGS
-- ─────────────────────────────────────────────
Config.BoardRefreshSeconds  = 7200    -- 2 hours between standard board refreshes
Config.RouteRefreshSeconds  = 21600   -- 6 hours between route refreshes
Config.ReservationSeconds   = 180     -- 3-minute reservation hold on load detail view
Config.ReservationWarning   = 3       -- consecutive releases before cooldown warning
Config.ReservationMaxReleases = 5     -- consecutive releases before cooldown triggers
Config.ReservationCooldown  = 600     -- 10-minute cooldown on Tier 2+ reservations

-- ─────────────────────────────────────────────
-- DEPOSIT RATES BY TIER
-- ─────────────────────────────────────────────
-- T0 uses a flat deposit. T1-T3 use percentage of estimated payout.
Config.DepositRates = {
    [0] = 0,       -- flat $300 (see DepositFlatT0)
    [1] = 0.15,    -- 15% of estimated payout
    [2] = 0.20,    -- 20% of estimated payout
    [3] = 0.25,    -- 25% of estimated payout
}
Config.DepositFlatT0 = 300   -- fixed deposit for all Tier 0 loads

-- ─────────────────────────────────────────────
-- PAYOUT FLOORS (REBALANCED)
-- ─────────────────────────────────────────────
-- Minimum payout per tier regardless of modifiers.
-- Applied as final step in payout calculation after all multipliers.
Config.PayoutFloors = {
    [0] = 150,     -- T0 minimum payout
    [1] = 250,     -- T1 minimum payout
    [2] = 400,     -- T2 minimum payout
    [3] = 600,     -- T3 minimum payout
}

-- ─────────────────────────────────────────────
-- DELIVERY ZONE SIZES BY TIER
-- ─────────────────────────────────────────────
-- vec3(length, width, height) — used with lib.zones.box at destination coords.
-- Higher tiers demand precision backing; the CDL tutorial (Stage 5) teaches this.
Config.DeliveryZoneSizes = {
    [0] = vec3(12.0, 8.0, 3.0),   -- T0: Pull-up — large parking area, any angle
    [1] = vec3(8.0, 5.0, 3.0),    -- T1: Loading dock — standard bay, back in or pull alongside
    [2] = vec3(5.0, 3.5, 3.0),    -- T2: Precision dock — tight bay, approach angle matters
    [3] = vec3(4.0, 3.0, 3.0),    -- T3: Restricted bay — precise backing, bollards on sides
}
Config.OversizedZoneOverride = vec3(8.0, 5.0, 3.0)  -- oversized loads (T2-05) use T1-sized zone

-- ─────────────────────────────────────────────
-- INSURANCE
-- ─────────────────────────────────────────────
-- T0 loads are exempt from insurance requirement.
-- T1+ loads hard-block acceptance without an active policy.
Config.InsuranceExemptTiers     = { [0] = true }   -- tiers that do not require insurance
Config.ClaimPayoutMultiplier    = 2                -- deposit x 2 + premium allocated

-- Insurance terminal locations (standalone offices, separate from truck stop terminals)
Config.InsuranceLocations = {
    { label = 'Vapid Commercial Insurance — LS',   coords = vector3(-157.0, -302.0, 40.0) },
    { label = 'Vapid Commercial Insurance — Sandy', coords = vector3(1862.0, 3690.0, 34.27) },
}
Config.ClaimDelaySeconds        = 900              -- 15-minute payout delay after approval
Config.ClaimCheckIntervalMs     = 60000            -- check pending claims every 60 seconds

-- ─────────────────────────────────────────────
-- SEAL SYSTEM
-- ─────────────────────────────────────────────
Config.SealBreakAlertPriority   = 'low'    -- police dispatch priority for seal breaks
Config.SealAbandonmentMinutes   = 10       -- minutes stationary before seal break / abandonment

-- ─────────────────────────────────────────────
-- INTEGRITY
-- ─────────────────────────────────────────────
Config.IntegrityRejectionThreshold = 40    -- below this %, load is rejected at destination

-- ─────────────────────────────────────────────
-- TEMPERATURE / REEFER
-- ─────────────────────────────────────────────
Config.ReeferHealthThreshold    = 65       -- vehicle health % below which reefer faults (standard)
Config.PharmaHealthThreshold    = 80       -- vehicle health % for pharmaceutical loads (stricter)
Config.EngineOffExcursionMins   = 5        -- minutes engine off before excursion starts

-- Temperature excursion time thresholds (minutes)
Config.ExcursionMinorMins       = 5        -- under this: clean, no penalty
Config.ExcursionSignificantMins = 15       -- 5-15 min: significant (-15%), over 15: critical (-35%)

-- Reefer health verification tolerance (account for network latency)
Config.ReeferHealthTolerance    = 50       -- ± health units allowed between client/server check

-- ─────────────────────────────────────────────
-- LIVESTOCK WELFARE
-- ─────────────────────────────────────────────
Config.WelfarePassiveDecayStart = 30       -- minutes before passive time-based decay begins
Config.WelfareInitialRating     = 5        -- starting welfare rating (1-5 scale)

-- Welfare event impacts
Config.WelfareEvents = {
    hard_braking        = -1.0,     -- per event
    sharp_corner        = -1.0,     -- corner > 35mph
    major_collision     = -2.0,     -- per event
    offroad_per_min     = -1.0,     -- per minute off-road
    heat_idle_per_10m   = -1.0,     -- Sandy Shores idle, per 10 min
    smooth_driving      = 0.25,     -- passive recovery per 10 min
    rest_stop_quick     = 0.5,      -- 30-second quick stop
    rest_stop_water     = 1.0,      -- 2-minute water stop
    rest_stop_full      = 1.5,      -- 5-minute full rest
}

-- Transit time decay brackets (per 30 minutes)
Config.WelfareTransitDecay = {
    { maxMins = 60,  decayPer30 = -0.25 },   -- 30-60 min
    { maxMins = 90,  decayPer30 = -0.50 },   -- 60-90 min
    { maxMins = 999, decayPer30 = -1.00 },   -- 90+ min
}

-- Rest stop interaction durations (ms)
Config.RestStopDurations = {
    quick = 30000,     -- 30 seconds
    water = 120000,    -- 2 minutes
    full  = 300000,    -- 5 minutes
}

-- ─────────────────────────────────────────────
-- LEON (CRIMINAL SYSTEM)
-- ─────────────────────────────────────────────
Config.LeonUnlockDeliveries     = 1        -- Tier 3 deliveries required (unlocks after first T3 completion)
Config.LeonActiveHoursStart     = 22       -- 22:00 server time
Config.LeonActiveHoursEnd       = 4        -- 04:00 server time
Config.LeonBoardSize            = 5        -- loads per refresh
Config.LeonRefreshSeconds       = 10800    -- 3 hours between refreshes
Config.LeonDawnExpiry            = 4        -- hour at which all Leon loads expire (04:00)


-- Leon supplier unlock requirements
Config.LeonSuppliers = {
    southside_consolidated = {
        label       = 'Southside Consolidated',
        region      = 'los_santos',
        rate        = 1.15,     -- 115% base rate
        risk        = 'low',
        unlock      = 'first_leon_load',
    },
    la_puerta_freight = {
        label       = 'La Puerta Freight Solutions',
        region      = 'los_santos',
        rate        = 1.30,     -- 130% base rate
        risk        = 'medium',
        unlock_loads = 3,       -- 3 Leon loads required
    },
    blaine_salvage = {
        label       = 'Blaine County Salvage & Ag',
        region      = 'sandy_shores',
        rate        = 1.45,     -- 145% base rate
        risk        = 'high',
        unlock      = 'hazmat_endorsement',
    },
    paleto_cold_storage = {
        label       = 'Paleto Bay Cold Storage',
        region      = 'paleto',
        rate        = 1.50,     -- 150% base rate
        risk        = 'medium',
        unlock      = 'tier3_cold_chain_rep',
    },
    pacific_bluffs_import = {
        label       = 'Pacific Bluffs Import/Export',
        region      = 'grapeseed',
        rate        = 1.60,     -- 160% base rate
        risk        = 'critical',
        unlock      = 'two_suppliers_complete',
    },
}

-- ─────────────────────────────────────────────
-- MILITARY SYSTEM
-- ─────────────────────────────────────────────
Config.MilitaryDispatchEnabled      = true
Config.MilitaryMaxPerRestart        = 2        -- maximum military contracts per server restart
Config.MilitaryEscortPursueRange    = 500      -- meters before escorts stop pursuing
Config.MilitaryEscortHoldSeconds    = 90       -- seconds escorts wait before returning to origin
Config.MilitaryEscortInvestigateSec = 60       -- seconds stopped before escort investigates

-- Long Con consequences
Config.LongConReputationHit         = 400      -- reputation points lost
Config.LongConClearanceSuspendDays  = 30       -- days government clearance suspended
Config.LongConT3CertSuspendDays    = 14       -- days all T3 certs suspended

-- Military cargo classifications
Config.MilitaryClassifications = {
    'equipment_transport',     -- vehicle parts, field gear, no weapons guaranteed
    'armory_transfer',         -- 1-2 automatic weapons probable
    'restricted_munitions',    -- 3-5 automatic weapons confirmed
}

-- ─────────────────────────────────────────────
-- ROBBERY SETTINGS
-- ─────────────────────────────────────────────
Config.RobberyMinActiveSeconds  = 90       -- load must be active 90+ seconds
Config.RobberySafeZoneRadius    = 200      -- meters from depot/weigh station/truck stop
Config.RobberyFullStealMinTier  = 2        -- T2+ for full trailer steal, T1 = on-site loot only
Config.CommsJammerDuration      = 180      -- 3 minutes distress signal block

-- ─────────────────────────────────────────────
-- WEIGH STATION
-- ─────────────────────────────────────────────
Config.WeighStationOptionalMaxTier  = 1    -- T0-T1 optional, T2-T3 mandatory routing
Config.WeighStationLocations = {
    { label = 'Route 1 Pacific Bluffs',       coords = vector3(-1640.0, -833.0, 10.0) },  -- placeholder
    { label = 'Route 68 near Harmony',        coords = vector3(542.0, 2670.0, 42.0) },    -- placeholder
    { label = 'Paleto Bay Highway Entrance',  coords = vector3(-354.0, 6170.0, 31.0) },   -- placeholder
}

-- ─────────────────────────────────────────────
-- CARGO SECURING
-- ─────────────────────────────────────────────
Config.StrapDurationMs          = 4000     -- 4 seconds per strap point
Config.FlatbedStrapPoints       = 3        -- standard flatbed strap points
Config.OversizedStrapPoints     = 4        -- oversized load strap points + wheel chock

-- ─────────────────────────────────────────────
-- FUEL TANKER
-- ─────────────────────────────────────────────
Config.StandardTankerGallons    = 9500     -- standard tanker capacity
Config.AviationTankerGallons    = 10500    -- aviation tanker capacity
Config.DrainSecondsPerDrum      = 30       -- seconds per drum during drain
Config.SelfRefuelGallons        = 50       -- gallons for self-refuel
Config.SelfRefuelDuration       = 60000    -- 60 seconds for self-refuel
Config.FuelCanisterCapacity     = 5        -- gallons per canister
Config.FuelCanisterMaxCarry     = 4        -- max canisters a player can carry

-- ─────────────────────────────────────────────
-- HAZMAT
-- ─────────────────────────────────────────────
Config.HazmatSpillIntegrityThreshold = 15  -- integrity % below which spill event triggers
Config.HazmatCleanupDuration    = 60000    -- 60-second cleanup interaction
Config.HazmatZonePersist        = true     -- zone persists until cleanup or restart

-- ─────────────────────────────────────────────
-- REPUTATION THRESHOLDS
-- ─────────────────────────────────────────────
Config.ReputationTiers = {
    { name = 'elite',         minScore = 1000, boardAccess = { 0, 1, 2, 3 }, extra = 'early_government' },
    { name = 'professional',  minScore = 800,  boardAccess = { 0, 1, 2, 3 }, extra = 'cross_region' },
    { name = 'established',   minScore = 600,  boardAccess = { 0, 1, 2, 3 } },
    { name = 'developing',    minScore = 400,  boardAccess = { 0, 1, 2 } },
    { name = 'probationary',  minScore = 200,  boardAccess = { 0, 1 } },
    { name = 'restricted',    minScore = 1,    boardAccess = { 0 } },
    { name = 'suspended',     minScore = 0,    boardAccess = {},            lockoutHours = 24 },
}

-- Reputation changes — delivery successes
Config.ReputationGains = {
    [0] = 8,       -- T0 delivery
    [1] = 15,      -- T1 delivery
    [2] = 25,      -- T2 delivery
    [3] = 40,      -- T3 delivery
    military            = 60,
    full_compliance     = 5,
    supplier_contract   = 20,
    cold_chain_clean    = 8,
    livestock_excellent = 10,
}

-- Reputation changes — failures (negative values)
Config.ReputationLosses = {
    robbery     = { [0] = -30,  [1] = -60,  [2] = -100, [3] = -180, military = -250 },
    integrity   = { [0] = -20,  [1] = -40,  [2] = -70,  [3] = -120 },
    abandonment = { [0] = -25,  [1] = -50,  [2] = -90,  [3] = -160 },
    expired     = { [0] = -10,  [1] = -20,  [2] = -35,  [3] = -60  },
    seal_break  = { [0] = 0,    [1] = -15,  [2] = -30,  [3] = -55  },
    hazmat_routing = -40,   -- T3 only
}

-- Shipper reputation tiers
Config.ShipperRepTiers = {
    { name = 'preferred',    minPoints = 700, rateBonus = 0.20, access = 'exclusive_loads' },
    { name = 'trusted',      minPoints = 350, rateBonus = 0.15, access = 'all_loads_surge_notice' },
    { name = 'established',  minPoints = 150, rateBonus = 0.10, access = 'tier2_exclusives' },
    { name = 'familiar',     minPoints = 50,  rateBonus = 0.05, access = 'priority_queue' },
    { name = 'unknown',      minPoints = 0,   rateBonus = 0.00, access = 'standard' },
}
Config.ShipperPreferredDecayDays    = 14   -- days inactive before Preferred drops to Trusted
Config.ShipperClusterFrictionRate   = 0.125 -- 10-15% avg penalty on cluster partners when damaged

-- ─────────────────────────────────────────────
-- CDL AND CERTIFICATION
-- ─────────────────────────────────────────────
Config.CDLWrittenTestPassScore      = 80    -- percentage to pass written test
Config.CDLMaxWrittenAttempts        = 3     -- attempts before lockout
Config.CDLWrittenLockoutMinutes     = 60    -- lockout duration after max attempts
Config.CDLPracticalRequired         = true  -- require practical test after written

-- CDL license fees
Config.CDLFees = {
    class_b             = 500,
    class_a             = 1500,
    tanker              = 800,
    hazmat              = 1200,
    oversized_monthly   = 2000,
}

-- Certification fees
Config.CertificationFees = {
    bilkington_carrier      = 3000,
    high_value              = 2500,
    government_clearance    = 5000,
}

-- ─────────────────────────────────────────────
-- CONVOY SYSTEM
-- ─────────────────────────────────────────────
Config.ConvoyMaxSize            = 6        -- maximum vehicles in a convoy
Config.ConvoyProximityRadius    = 150      -- meters to maintain convoy formation
Config.ConvoyDisconnectTimeout  = 120      -- seconds before dropped from convoy

-- ─────────────────────────────────────────────
-- TIMING AND MAINTENANCE
-- ─────────────────────────────────────────────
Config.ServerTimeSyncInterval   = 30000    -- ms between GlobalState.serverTime updates
Config.AbandonmentCheckInterval = 30000    -- ms between server-side abandonment checks
Config.SealCheckInterval        = 5000     -- ms between client-side seal status checks

-- ─────────────────────────────────────────────
-- SURGE PRICING
-- ─────────────────────────────────────────────
Config.SurgeTriggers = {
    open_contract_threshold     = 0.50,    -- open contract > 50% filled
    open_contract_bonus         = 0.20,    -- +20% on related cargo
    robbery_corridor_bonus      = 0.25,    -- +25% danger premium
    robbery_corridor_duration   = 7200,    -- 2 hours
    cold_chain_failure_bonus    = 0.30,    -- +30% reefer loads in region
    cold_chain_failure_count    = 3,       -- failures required to trigger
    peak_population_bonus       = 0.10,    -- +10% all tiers during peak
    shipper_backlog_bonus       = 0.35,    -- +35% that shipper
    shipper_backlog_hours       = 4,       -- hours without delivery to trigger
}

-- ─────────────────────────────────────────────
-- ADMIN
-- ─────────────────────────────────────────────
Config.AdminPermission          = 'admin'  -- QBX permission level for admin commands
Config.AdminLiveEconomyTuning   = true     -- allow live ServerMultiplier adjustment

-- ─────────────────────────────────────────────
-- TRUCK STOP NETWORK (Section 31)
-- ─────────────────────────────────────────────
-- 6 locations: 4 full-service, 2 basic.
-- Full-service: board terminal, repair bay, insurance terminal.
-- Basic: board terminal only (some with livestock rest).
-- All full-service stops are robbery safe zones.

Config.TruckStops = {
    -- ── Full Service ─────────────────────────────
    {
        label            = 'Route 68 Truck Plaza',
        region           = 'sandy_shores',
        coords           = vector3(1196.50, 2648.20, 37.82),
        hasTerminal      = true,
        terminalCoords   = vector3(1199.23, 2648.30, 37.78),
        terminalHeading  = 315,
        hasRepairBay     = true,
        repairCoords     = vector3(1185.40, 2640.50, 37.80),
        hasInsurance     = true,
        insuranceCoords  = vector3(1202.10, 2655.80, 37.82),
        safezone         = true,
        safezoneRadius   = 200,
    },
    {
        label            = 'Paleto Highway Stop',
        region           = 'paleto',
        coords           = vector3(110.20, 6620.40, 31.85),
        hasTerminal      = true,
        terminalCoords   = vector3(112.50, 6623.10, 31.85),
        terminalHeading  = 45,
        hasRepairBay     = true,
        repairCoords     = vector3(105.30, 6612.80, 31.85),
        hasInsurance     = true,
        insuranceCoords  = vector3(118.70, 6628.50, 31.85),
        safezone         = true,
        safezoneRadius   = 200,
    },
    {
        label            = 'LSIA Commercial Yard',
        region           = 'los_santos',
        coords           = vector3(-1032.50, -2729.80, 13.76),
        hasTerminal      = true,
        terminalCoords   = vector3(-1029.20, -2733.40, 13.76),
        terminalHeading  = 150,
        hasRepairBay     = true,
        repairCoords     = vector3(-1040.60, -2722.30, 13.76),
        hasInsurance     = true,
        insuranceCoords  = vector3(-1025.80, -2740.10, 13.76),
        safezone         = true,
        safezoneRadius   = 200,
    },
    {
        label            = 'Port of LS Staging',
        region           = 'los_santos',
        coords           = vector3(168.50, -3090.20, 5.90),
        hasTerminal      = true,
        terminalCoords   = vector3(172.30, -3087.50, 5.90),
        terminalHeading  = 270,
        hasRepairBay     = true,
        repairCoords     = vector3(160.40, -3095.60, 5.90),
        hasInsurance     = true,
        insuranceCoords  = vector3(178.90, -3082.30, 5.90),
        safezone         = true,
        safezoneRadius   = 200,
    },

    -- ── Basic Service ────────────────────────────
    {
        label            = 'Harmony Rest Area',
        region           = 'sandy_shores',
        coords           = vector3(1222.10, 2730.50, 38.00),
        hasTerminal      = true,
        terminalCoords   = vector3(1224.80, 2732.30, 38.00),
        terminalHeading  = 0,
        hasRepairBay     = false,
        hasInsurance     = false,
        hasLivestockRest = true,
        livestockRestCoords = vector3(1230.50, 2740.10, 38.00),
    },
    {
        label            = 'Grapeseed Co-op Fuel',
        region           = 'grapeseed',
        coords           = vector3(1700.20, 4920.60, 42.06),
        hasTerminal      = true,
        terminalCoords   = vector3(1703.50, 4923.40, 42.06),
        terminalHeading  = 90,
        hasRepairBay     = false,
        hasInsurance     = false,
        hasLivestockRest = true,
        livestockRestCoords = vector3(1710.80, 4930.20, 42.06),
    },
}
