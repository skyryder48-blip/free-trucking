--[[
    config/shippers.lua
    All shipper definitions with real GTA V map coordinates.

    Map overlay reference:
        Los Santos   = Chicago
        Sandy Shores = Gary, IN
        Paleto Bay   = Wisconsin
        Grapeseed    = Western Michigan

    Each shipper defines:
        label           string      Display name
        region          string      One of: los_santos, sandy_shores, paleto, grapeseed
        tier_range      {min, max}  Cargo tier range this shipper offers
        cluster         string      One of: luxury, agricultural, industrial, government
        coords          vector3     Real GTA V pickup/interaction coordinates
        cert_required   string?     Required certification key (nil if none)
        destinations    table       3-6 delivery locations with label + coords
]]

Shippers = {}

-- ============================================================================
-- LOS SANTOS (Industrial / Urban)
-- ============================================================================

Shippers['port_of_ls'] = {
    label           = 'Port of Los Santos Freight Authority',
    region          = 'los_santos',
    tier_range      = {0, 2},
    cluster         = 'industrial',
    coords          = vector3(-122.72, -2731.62, 6.01),    -- LS port container yard, Elysian Island
    cert_required   = nil,
    destinations    = {
        { label = 'Davis Industrial Warehouse',         coords = vector3(-18.0, -1660.26, 29.29) },
        { label = 'Cypress Flats Distribution Center',  coords = vector3(790.96, -2160.0, 29.62) },
        { label = 'El Burro Heights Storage',           coords = vector3(1662.39, -2258.68, 95.57) },
        { label = 'Strawberry Commerce Hub',            coords = vector3(56.73, -1388.35, 29.34) },
        { label = 'Sandy Shores Depot',                 coords = vector3(1394.57, 3614.89, 34.98) },
        { label = 'Paleto Bay Receiving',               coords = vector3(160.47, 6397.39, 31.42) },
    },
}

Shippers['vangelico'] = {
    label           = 'Vangelico Fine Goods',
    region          = 'los_santos',
    tier_range      = {1, 3},
    cluster         = 'luxury',
    coords          = vector3(-630.41, -236.71, 38.08),    -- Vangelico store, Portola Dr / Rockford Hills
    cert_required   = 'high_value',
    destinations    = {
        { label = 'Rockford Hills Private Estate',     coords = vector3(-1543.59, 110.05, 56.73) },
        { label = 'Vinewood Casino Receiving',          coords = vector3(924.44, 46.15, 80.90) },
        { label = 'Del Perro Pier Showroom',            coords = vector3(-1659.71, -1014.81, 13.08) },
        { label = 'Burton Luxury Boutique',             coords = vector3(-147.86, -302.90, 38.73) },
        { label = 'Chumash Art Gallery',                coords = vector3(-3243.94, 1005.13, 12.83) },
    },
}

Shippers['bilkington'] = {
    label           = 'Bilkington Research',
    region          = 'los_santos',
    tier_range      = {2, 3},
    cluster         = 'government',
    coords          = vector3(3619.39, 3754.40, 28.69),    -- Humane Labs & Research facility
    cert_required   = 'bilkington_carrier',
    destinations    = {
        { label = 'Pillbox Hill Medical Center',        coords = vector3(299.11, -584.22, 43.26) },
        { label = 'ULSA Campus Research Wing',          coords = vector3(-1095.69, -845.68, 19.89) },
        { label = 'Davis Quartz Lab Annex',             coords = vector3(485.63, -1762.37, 28.40) },
        { label = 'Sandy Shores Medical Clinic',        coords = vector3(1835.57, 3670.43, 34.28) },
        { label = 'Paleto Bay General Hospital',        coords = vector3(-250.92, 6332.29, 32.43) },
    },
}

Shippers['maze_bank'] = {
    label           = 'Maze Bank Logistics',
    region          = 'los_santos',
    tier_range      = {1, 3},
    cluster         = 'luxury',
    coords          = vector3(-75.01, -818.22, 326.17),    -- Maze Bank Tower, downtown LS financial district
    cert_required   = nil,
    destinations    = {
        { label = 'Arcadius Business Center',           coords = vector3(-141.29, -620.91, 168.82) },
        { label = 'FIB Building Secure Dock',           coords = vector3(150.26, -749.24, 258.15) },
        { label = 'Pacific Standard Vault Receiving',   coords = vector3(235.28, 216.43, 106.29) },
        { label = 'Lombank West Loading Bay',           coords = vector3(-1581.07, -556.98, 34.95) },
        { label = 'Vespucci Financial District',        coords = vector3(-1166.30, -1517.82, 4.36) },
        { label = 'Chumash Corporate Retreat',          coords = vector3(-3151.98, 1117.21, 20.70) },
    },
}

Shippers['fleeca_distribution'] = {
    label           = 'Fleeca Distribution',
    region          = 'los_santos',
    tier_range      = {0, 2},
    cluster         = 'industrial',
    coords          = vector3(900.51, -1046.54, 32.83),    -- La Mesa industrial district, near railyard
    cert_required   = nil,
    destinations    = {
        { label = 'Mirror Park Branch',                 coords = vector3(1176.45, -472.48, 66.73) },
        { label = 'Hawick ATM Distribution Hub',        coords = vector3(313.82, -278.58, 54.16) },
        { label = 'Palomino Freeway Branch',            coords = vector3(2564.60, 2174.91, 16.63) },
        { label = 'Grapeseed Branch Office',            coords = vector3(1655.30, 4851.66, 42.01) },
        { label = 'Great Ocean Highway Branch',         coords = vector3(-2958.88, 479.88, 15.70) },
    },
}

Shippers['lsia_freight'] = {
    label           = 'LSIA Federal Logistics',
    region          = 'los_santos',
    tier_range      = {1, 3},
    cluster         = 'industrial',
    coords          = vector3(-1025.73, -2728.07, 13.76),  -- LSIA cargo/freight area south side of runway
    cert_required   = nil,
    destinations    = {
        { label = 'Strawberry Logistics Yard',          coords = vector3(70.45, -1395.78, 29.38) },
        { label = 'Murrieta Heights Warehouse',         coords = vector3(1088.38, -1993.79, 30.91) },
        { label = 'Harmony Truck Stop',                 coords = vector3(1199.23, 2648.30, 37.78) },
        { label = 'Sandy Shores Airfield',              coords = vector3(1717.45, 3283.72, 41.22) },
        { label = 'Paleto Bay Airstrip',                coords = vector3(2130.90, 4784.13, 40.97) },
    },
}

Shippers['groupe_sechs'] = {
    label           = 'Groupe Sechs Secure Transport',
    region          = 'los_santos',
    tier_range      = {2, 3},
    cluster         = 'luxury',
    coords          = vector3(19.64, -1387.51, 29.34),     -- Groupe Sechs depot, Strawberry / Davis border
    cert_required   = 'high_value',
    destinations    = {
        { label = 'Vangelico Vault Receiving',          coords = vector3(-624.68, -229.85, 38.08) },
        { label = 'Pacific Standard Bank',              coords = vector3(241.36, 225.53, 106.29) },
        { label = 'Maze Bank Secure Floor',             coords = vector3(-75.01, -818.22, 326.17) },
        { label = 'Fort Zancudo Armory Gate',           coords = vector3(-2353.46, 3249.68, 32.81) },
    },
}

Shippers['ls_customs_supply'] = {
    label           = 'Los Santos Customs Supply',
    region          = 'los_santos',
    tier_range      = {0, 1},
    cluster         = 'industrial',
    coords          = vector3(-339.23, -136.86, 39.01),    -- Burton area, near LS Customs
    cert_required   = nil,
    destinations    = {
        { label = 'Benny\'s Original Motorworks',       coords = vector3(-205.80, -1310.53, 31.30) },
        { label = 'Beeker\'s Garage',                   coords = vector3(113.68, 6619.12, 31.86) },
        { label = 'Hayes Autos La Mesa',                coords = vector3(485.79, -1310.25, 29.21) },
        { label = 'Sandy Shores Mod Shop',              coords = vector3(1176.10, 2640.39, 37.75) },
    },
}

Shippers['ls_gas_supply'] = {
    label           = 'Los Santos Gas & Supply Co.',
    region          = 'los_santos',
    tier_range      = {1, 2},
    cluster         = 'industrial',
    coords          = vector3(816.96, -1936.16, 29.24),    -- Cypress Flats, near industrial gas storage
    cert_required   = nil,
    destinations    = {
        { label = 'LTD Gasoline, Davis',                coords = vector3(-48.19, -1756.66, 29.42) },
        { label = 'RON Station, Little Seoul',          coords = vector3(-536.66, -1222.14, 18.45) },
        { label = 'Globe Oil, Mirror Park',             coords = vector3(1207.96, -335.07, 69.09) },
        { label = 'Xero Gas, Grand Senora',             coords = vector3(2551.28, 384.33, 108.62) },
        { label = 'RON Station, Harmony',               coords = vector3(1209.84, 2656.58, 37.82) },
    },
}

-- ============================================================================
-- SANDY SHORES (Industrial / Desert)
-- ============================================================================

Shippers['ron_petroleum'] = {
    label           = 'RON Petroleum',
    region          = 'sandy_shores',
    tier_range      = {1, 2},
    cluster         = 'industrial',
    coords          = vector3(1698.14, 3583.34, 35.62),    -- RON Alternates Wind Farm / Refinery, Sandy Shores
    cert_required   = nil,
    destinations    = {
        { label = 'Elysian Island Fuel Terminal',       coords = vector3(-282.59, -2663.63, 6.00) },
        { label = 'El Burro Heights Gas Depot',         coords = vector3(1660.91, -2270.38, 95.57) },
        { label = 'Catfish View Pump Station',          coords = vector3(1541.65, 3833.53, 34.46) },
        { label = 'LSIA Aviation Fuel Depot',           coords = vector3(-993.78, -2748.16, 13.76) },
        { label = 'Paleto Bay Fuel Dock',               coords = vector3(-148.47, 6336.55, 31.41) },
    },
}

Shippers['alamo_industrial'] = {
    label           = 'Alamo Industrial Supply',
    region          = 'sandy_shores',
    tier_range      = {0, 2},
    cluster         = 'industrial',
    coords          = vector3(1329.78, 4337.39, 37.37),    -- North of Alamo Sea, industrial structures
    cert_required   = nil,
    destinations    = {
        { label = 'Harmony Repair Depot',               coords = vector3(1195.44, 2643.51, 37.78) },
        { label = 'Grapeseed Equipment Yard',           coords = vector3(1665.72, 4770.59, 42.01) },
        { label = 'Sandy Shores Mechanic',              coords = vector3(1176.10, 2640.39, 37.75) },
        { label = 'Murrieta Heights Industrial',        coords = vector3(1088.38, -1993.79, 30.91) },
        { label = 'Paleto Bay Hardware',                coords = vector3(91.38, 6397.31, 31.42) },
    },
}

Shippers['cliffford_agrochem'] = {
    label           = 'Cliffford Agrochemical',
    region          = 'sandy_shores',
    tier_range      = {1, 3},
    cluster         = 'industrial',
    coords          = vector3(2681.36, 3278.36, 55.24),    -- Desert industrial area east of Sandy Shores airfield
    cert_required   = nil,
    destinations    = {
        { label = 'Grapeseed Farm Supply',              coords = vector3(1700.43, 4784.11, 41.81) },
        { label = 'Blaine County Crop Dusting Strip',   coords = vector3(1736.71, 3289.42, 41.22) },
        { label = 'Harmony Chemical Storage',           coords = vector3(1201.42, 2651.33, 37.78) },
        { label = 'Davis Quartz Processing',            coords = vector3(483.28, -1762.37, 28.40) },
    },
}

Shippers['sandy_freight_depot'] = {
    label           = 'Sandy Shores Freight Depot',
    region          = 'sandy_shores',
    tier_range      = {0, 1},
    cluster         = 'industrial',
    coords          = vector3(1390.61, 3607.51, 34.98),    -- Sandy Shores main freight/warehouse area
    cert_required   = nil,
    destinations    = {
        { label = 'Paleto Bay General Store',           coords = vector3(161.30, 6641.93, 31.58) },
        { label = 'Strawberry Wholesale',               coords = vector3(70.45, -1395.78, 29.38) },
        { label = 'Grapeseed Convenience',              coords = vector3(1697.12, 4919.88, 42.07) },
        { label = 'Chumash Market',                     coords = vector3(-3243.94, 1005.13, 12.83) },
    },
}

Shippers['trevor_enterprises'] = {
    label           = 'Trevor Philips Enterprises',
    region          = 'sandy_shores',
    tier_range      = {0, 2},
    cluster         = 'industrial',
    coords          = vector3(1981.56, 3816.39, 32.18),    -- Trevor's trailer park / meth lab area
    cert_required   = nil,
    destinations    = {
        { label = 'Grand Senora Salvage',               coords = vector3(2345.18, 3052.99, 48.15) },
        { label = 'Stab City Recycling',                coords = vector3(68.79, 3704.18, 39.74) },
        { label = 'Harmony General Warehouse',          coords = vector3(1195.44, 2643.51, 37.78) },
        { label = 'Grapeseed Bulk Drop',                coords = vector3(1693.47, 4790.35, 41.82) },
        { label = 'Cypress Flats Receiving',            coords = vector3(790.96, -2160.0, 29.62) },
    },
}

-- ============================================================================
-- PALETO BAY (Rural / Cold Chain)
-- ============================================================================

Shippers['paleto_lumber'] = {
    label           = 'Paleto Bay Lumber',
    region          = 'paleto',
    tier_range      = {0, 2},
    cluster         = 'industrial',
    coords          = vector3(-549.26, 5308.73, 74.17),    -- Paleto sawmill / lumber yard
    cert_required   = nil,
    destinations    = {
        { label = 'Mirror Park Construction Site',      coords = vector3(1081.21, -447.84, 67.06) },
        { label = 'LSIA Terminal Expansion',            coords = vector3(-1025.73, -2728.07, 13.76) },
        { label = 'Sandy Shores Building Supply',       coords = vector3(1390.61, 3607.51, 34.98) },
        { label = 'Chumash Housing Development',        coords = vector3(-3151.98, 1117.21, 20.70) },
        { label = 'Vinewood Hills Custom Homes',        coords = vector3(-760.83, 617.38, 144.36) },
    },
}

Shippers['humane_labs_cold'] = {
    label           = 'Humane Labs Cold Chain',
    region          = 'paleto',
    tier_range      = {2, 3},
    cluster         = 'government',
    coords          = vector3(3592.20, 3669.78, 33.92),    -- Humane Labs & Research perimeter
    cert_required   = 'bilkington_carrier',
    destinations    = {
        { label = 'Pillbox Hill Medical Center',        coords = vector3(299.11, -584.22, 43.26) },
        { label = 'Central LS Hospital',                coords = vector3(340.23, -1396.98, 32.51) },
        { label = 'Mount Zonah Medical',                coords = vector3(-449.52, -340.89, 34.50) },
        { label = 'Sandy Shores Clinic',                coords = vector3(1835.57, 3670.43, 34.28) },
    },
}

Shippers['blaine_livestock'] = {
    label           = 'Blaine County Livestock Exchange',
    region          = 'paleto',
    tier_range      = {1, 2},
    cluster         = 'agricultural',
    coords          = vector3(428.21, 6469.98, 29.33),     -- Paleto Bay rural area, north of town near pastures
    cert_required   = nil,
    destinations    = {
        { label = 'LS Meat Packing, Cypress Flats',     coords = vector3(810.52, -2189.83, 29.62) },
        { label = 'Sandy Shores Stockyard',             coords = vector3(1393.55, 3614.41, 34.98) },
        { label = 'Grapeseed Auction Barn',             coords = vector3(1684.78, 4826.81, 42.01) },
        { label = 'Harmony Feedlot',                    coords = vector3(1180.50, 2638.89, 37.78) },
    },
}

Shippers['paleto_forest_products'] = {
    label           = 'Paleto Forest Products',
    region          = 'paleto',
    tier_range      = {0, 1},
    cluster         = 'agricultural',
    coords          = vector3(-760.78, 5534.77, 33.48),    -- Paleto Forest area, north of Paleto
    cert_required   = nil,
    destinations    = {
        { label = 'Vinewood Boulevard Gallery',         coords = vector3(345.20, 159.40, 103.59) },
        { label = 'Del Perro Pier Gift Shop',           coords = vector3(-1659.71, -1014.81, 13.08) },
        { label = 'Grapeseed General Store',            coords = vector3(1697.12, 4919.88, 42.07) },
        { label = 'Mirror Park Arts District',          coords = vector3(1081.21, -447.84, 67.06) },
    },
}

Shippers['paleto_cold_chain_supply'] = {
    label           = 'Paleto Bay Cold Chain Supply',
    region          = 'paleto',
    tier_range      = {1, 2},
    cluster         = 'agricultural',
    coords          = vector3(152.96, 6373.49, 31.13),     -- Paleto Bay main street, near cold storage facilities
    cert_required   = nil,
    destinations    = {
        { label = 'LS Wholesale Market',                coords = vector3(70.45, -1395.78, 29.38) },
        { label = 'Vespucci Seafood Restaurant Row',    coords = vector3(-1165.17, -1520.34, 4.36) },
        { label = 'Vinewood Hills Catering',            coords = vector3(-760.83, 617.38, 144.36) },
        { label = 'Sandy Shores Diner Supply',          coords = vector3(1893.18, 3730.14, 32.82) },
        { label = 'Grapeseed Market',                   coords = vector3(1697.12, 4919.88, 42.07) },
    },
}

-- ============================================================================
-- GRAPESEED (Agricultural)
-- ============================================================================

Shippers['grapeseed_collective'] = {
    label           = 'Grapeseed Agricultural Collective',
    region          = 'grapeseed',
    tier_range      = {0, 2},
    cluster         = 'agricultural',
    coords          = vector3(1693.47, 4924.77, 42.07),    -- Grapeseed main farm area
    cert_required   = nil,
    destinations    = {
        { label = 'LS Farmers Market, Davis',           coords = vector3(-18.0, -1660.26, 29.29) },
        { label = 'Vespucci Organic Market',            coords = vector3(-1165.17, -1520.34, 4.36) },
        { label = 'Paleto Bay Grocery',                 coords = vector3(161.30, 6641.93, 31.58) },
        { label = 'Sandy Shores General',               coords = vector3(1893.18, 3730.14, 32.82) },
        { label = 'Vinewood Hills Private Chef',        coords = vector3(-760.83, 617.38, 144.36) },
        { label = 'Little Seoul Market',                coords = vector3(-548.75, -901.17, 24.88) },
    },
}

Shippers['blaine_growers'] = {
    label           = 'Blaine County Growers Cooperative',
    region          = 'grapeseed',
    tier_range      = {0, 2},
    cluster         = 'agricultural',
    coords          = vector3(2416.98, 4993.38, 46.29),    -- East Grapeseed farmland, near the barns
    cert_required   = nil,
    destinations    = {
        { label = 'Paleto Cold Storage',                coords = vector3(152.96, 6373.49, 31.13) },
        { label = 'Sandy Shores Feed & Grain',          coords = vector3(1390.61, 3607.51, 34.98) },
        { label = 'LS Central Produce Market',          coords = vector3(70.45, -1395.78, 29.38) },
        { label = 'Del Perro Restaurant Supply',        coords = vector3(-1659.71, -1014.81, 13.08) },
    },
}

Shippers['brute_equipment'] = {
    label           = 'Brute Heavy Equipment',
    region          = 'grapeseed',
    tier_range      = {1, 2},
    cluster         = 'industrial',
    coords          = vector3(2709.01, 4324.70, 45.99),    -- East of Grapeseed near construction/quarry area
    cert_required   = nil,
    destinations    = {
        { label = 'LSIA Runway Extension Site',         coords = vector3(-1025.73, -2728.07, 13.76) },
        { label = 'Mirror Park Overpass Project',       coords = vector3(1081.21, -447.84, 67.06) },
        { label = 'Sandy Shores Road Crew',             coords = vector3(1390.61, 3607.51, 34.98) },
        { label = 'Paleto Bay Bridge Repair',           coords = vector3(-549.26, 5308.73, 74.17) },
        { label = 'Route 68 Construction Zone',         coords = vector3(1201.42, 2651.33, 37.78) },
    },
}

Shippers['grapeseed_dairy'] = {
    label           = 'Grapeseed Dairy Cooperative',
    region          = 'grapeseed',
    tier_range      = {1, 2},
    cluster         = 'agricultural',
    coords          = vector3(2556.78, 4664.48, 34.08),    -- East Grapeseed dairy farm area
    cert_required   = nil,
    destinations    = {
        { label = 'LS Wholesale Dairy Cooler',          coords = vector3(70.45, -1395.78, 29.38) },
        { label = 'Paleto Bay Creamery',                coords = vector3(161.30, 6641.93, 31.58) },
        { label = 'Sandy Shores Grocery Cooler',        coords = vector3(1893.18, 3730.14, 32.82) },
        { label = 'Vinewood Artisan Cheese Shop',       coords = vector3(345.20, 159.40, 103.59) },
    },
}

Shippers['grapeseed_winery'] = {
    label           = 'Grapeseed Valley Winery',
    region          = 'grapeseed',
    tier_range      = {0, 1},
    cluster         = 'agricultural',
    coords          = vector3(1873.84, 5068.56, 45.12),    -- North Grapeseed vineyard hills
    cert_required   = nil,
    destinations    = {
        { label = 'Vinewood Celebrity Lounge',          coords = vector3(345.20, 159.40, 103.59) },
        { label = 'Del Perro Pier Wine Bar',            coords = vector3(-1659.71, -1014.81, 13.08) },
        { label = 'Rockford Hills Wine Shop',           coords = vector3(-1543.59, 110.05, 56.73) },
        { label = 'Paleto Bay Inn',                     coords = vector3(161.30, 6641.93, 31.58) },
    },
}

-- ============================================================================
-- GOVERNMENT / MILITARY
-- ============================================================================

Shippers['san_andreas_national_guard'] = {
    label           = 'San Andreas National Guard',
    region          = 'los_santos',
    tier_range      = {2, 3},
    cluster         = 'government',
    coords          = vector3(-2350.79, 3270.43, 32.81),   -- Fort Zancudo front gate / staging area
    cert_required   = 'government_clearance',
    destinations    = {
        { label = 'Fort Zancudo Armory',                coords = vector3(-2295.57, 3389.51, 31.01) },
        { label = 'LS National Guard Depot',            coords = vector3(483.28, -1762.37, 28.40) },
        { label = 'Sandy Shores FOB',                   coords = vector3(1717.45, 3283.72, 41.22) },
        { label = 'Paleto Bay Coast Guard Station',     coords = vector3(-148.47, 6336.55, 31.41) },
        { label = 'Naval Port, Elysian Island',         coords = vector3(-178.61, -2658.05, 6.00) },
    },
}

Shippers['fib_logistics'] = {
    label           = 'FIB Logistics',
    region          = 'los_santos',
    tier_range      = {3, 3},
    cluster         = 'government',
    coords          = vector3(150.26, -749.24, 258.15),    -- FIB Building, downtown LS
    cert_required   = 'government_clearance',
    destinations    = {
        { label = 'IAA Building Secure Loading',        coords = vector3(94.32, -618.83, 206.05) },
        { label = 'Fort Zancudo Secure Storage',        coords = vector3(-2295.57, 3389.51, 31.01) },
        { label = 'Humane Labs Restricted Wing',        coords = vector3(3619.39, 3754.40, 28.69) },
        { label = 'NOOSE HQ Evidence Lockup',           coords = vector3(2520.71, -384.81, 93.14) },
    },
}

-- ============================================================================
-- SHIPPER HELPER FUNCTIONS
-- ============================================================================

--- Get all shippers for a specific region
---@param region string
---@return table
function GetShippersByRegion(region)
    local result = {}
    for id, shipper in pairs(Shippers) do
        if shipper.region == region then
            result[id] = shipper
        end
    end
    return result
end

--- Get all shippers within a tier range
---@param tier number
---@return table
function GetShippersForTier(tier)
    local result = {}
    for id, shipper in pairs(Shippers) do
        if tier >= shipper.tier_range[1] and tier <= shipper.tier_range[2] then
            result[id] = shipper
        end
    end
    return result
end

--- Get all shippers requiring a specific certification
---@param cert string
---@return table
function GetShippersByCert(cert)
    local result = {}
    for id, shipper in pairs(Shippers) do
        if shipper.cert_required == cert then
            result[id] = shipper
        end
    end
    return result
end

--- Get a random destination for a shipper
---@param shipperId string
---@return table|nil {label, coords}
function GetRandomDestination(shipperId)
    local shipper = Shippers[shipperId]
    if not shipper or not shipper.destinations or #shipper.destinations == 0 then
        return nil
    end
    return shipper.destinations[math.random(#shipper.destinations)]
end
