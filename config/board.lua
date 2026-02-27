--[[
    config/board.lua — Board Composition and Refresh Configuration
    Free Trucking — QBX Framework

    Controls how many loads appear per region per tier on each board refresh,
    supplier contract counts, route counts, open contracts, refresh offsets,
    and expiry timings.

    Board refresh interval is set in config/config.lua (Config.BoardRefreshSeconds).
]]

BoardConfig = {}

-- ─────────────────────────────────────────────
-- STANDARD LOAD COUNTS PER REGION PER TIER
-- ─────────────────────────────────────────────
-- Generated on each board refresh cycle.
-- First-come-first-served with 3-minute reservation hold.
-- Major hubs (LS, Sandy) get more T2/T3 loads.
BoardConfig.StandardLoads = {
    los_santos = {
        [0] = 4,       -- 4 Tier 0 loads
        [1] = 4,       -- 4 Tier 1 loads
        [2] = 3,       -- 3 Tier 2 loads
        [3] = 2,       -- 2 Tier 3 loads
    },
    sandy_shores = {
        [0] = 4,       -- 4 Tier 0 loads
        [1] = 4,       -- 4 Tier 1 loads
        [2] = 3,       -- 3 Tier 2 loads
        [3] = 2,       -- 2 Tier 3 loads
    },
    paleto = {
        [0] = 4,       -- 4 Tier 0 loads
        [1] = 3,       -- 3 Tier 1 loads
        [2] = 2,       -- 2 Tier 2 loads
        [3] = 1,       -- 1 Tier 3 load
    },
    grapeseed = {
        [0] = 4,       -- 4 Tier 0 loads
        [1] = 3,       -- 3 Tier 1 loads
        [2] = 2,       -- 2 Tier 2 loads
        [3] = 1,       -- 1 Tier 3 load
    },
}

-- ─────────────────────────────────────────────
-- SUPPLIER CONTRACTS, ROUTES, OPEN CONTRACTS
-- ─────────────────────────────────────────────
-- Supplier contracts: per-region, shipper-specific loads with relationship bonuses.
-- Routes: multi-stop scheduled runs, longer refresh cycle.
-- Open contracts: server-wide community goals (multiple drivers contribute).
BoardConfig.SupplierContracts   = 3    -- supplier contracts generated per region per refresh
BoardConfig.Routes              = 2    -- routes generated per region per route refresh
BoardConfig.OpenContracts       = 2    -- active open contracts server-wide

-- ─────────────────────────────────────────────
-- REFRESH OFFSETS PER REGION
-- ─────────────────────────────────────────────
-- Seconds offset from the hour mark. Staggers refreshes so not all
-- regions update simultaneously, preventing server load spikes and
-- giving drivers a rolling wave of new loads.
BoardConfig.RefreshOffsets = {
    los_santos   = 0,       -- refreshes on the hour
    sandy_shores = 1800,    -- refreshes at :30
    paleto       = 900,     -- refreshes at :15
    grapeseed    = 2700,    -- refreshes at :45
}

-- ─────────────────────────────────────────────
-- EXPIRY TIMINGS
-- ─────────────────────────────────────────────
-- Unclaimed loads expire at board refresh. These are the maximum lifetimes.
BoardConfig.LoadExpirySeconds       = 7200      -- 2 hours — standard loads
BoardConfig.RouteExpirySeconds      = 21800     -- ~6 hours — routes (slightly longer than refresh)
BoardConfig.SupplierExpiryHours     = { 4, 6, 8 }  -- random range in hours for supplier contracts

-- ─────────────────────────────────────────────
-- BOARD TABS
-- ─────────────────────────────────────────────
-- Defines the tab structure shown in the NUI board screen.
-- Each tab filters loads by their source type.
BoardConfig.Tabs = {
    { id = 'standard',  label = 'Standard',  icon = 'truck' },
    { id = 'supplier',  label = 'Supplier',  icon = 'handshake' },
    { id = 'open',      label = 'Open',      icon = 'users' },
    { id = 'routes',    label = 'Routes',    icon = 'route' },
}

-- ─────────────────────────────────────────────
-- SURGE EVENT BOARD DISPLAY
-- ─────────────────────────────────────────────
-- Loads with active surge show the percentage on the board card.
-- Surge triggers are defined in Config.SurgeTriggers (config.lua).
BoardConfig.ShowSurgePercentage     = true     -- display surge % on load cards
BoardConfig.SurgeBadgeColor         = '#C87B03' -- warning orange from Bears palette
