--[[
    Free Trucking — ox_inventory Item Definitions

    Usage: Copy these entries into your ox_inventory items configuration,
    or place this file in ox_inventory/data/items/ if your setup supports
    modular item loading.

    All items referenced in the trucking script are defined here.
]]

return {

    -- ─────────────────────────────────────────────
    -- BOL (Bill of Lading)
    -- ─────────────────────────────────────────────

    ['trucking_bol'] = {
        label    = 'Bill of Lading',
        weight   = 100,       -- 0.1 kg (100g)
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Official freight document. Required for delivery and insurance claims.',
        client = {
            image = 'trucking_bol.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- CDL (Commercial Driver's License)
    -- Single item — metadata stores all licenses,
    -- endorsements, permits, and certifications.
    --
    -- Metadata fields:
    --   license_class    string|nil   'class_b' or 'class_a'
    --   endorsements     table        { tanker = true, hazmat = true }
    --   permits          table        { oversized = timestamp_expires }
    --   certifications   table        { bilkington = true, high_value = true, government = true }
    --   citizenid        string       Owner's citizen ID
    --   issued_at        number       Unix timestamp
    -- ─────────────────────────────────────────────

    ['cdl'] = {
        label    = 'Commercial Driver\'s License',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'San Andreas CDL wallet card. Contains license class, endorsements, permits, and carrier certifications.',
        client = {
            image = 'cdl.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- FUEL / DRAIN ITEMS
    -- ─────────────────────────────────────────────

    ['fuel_hose'] = {
        label    = 'Fuel Transfer Hose',
        weight   = 2000,      -- 2 kg
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Industrial fuel transfer hose with fittings. Used for tanker drain operations.',
        client = {
            image = 'fuel_hose.png',
        },
    },

    ['valve_wrench'] = {
        label    = 'Valve Wrench',
        weight   = 1500,      -- 1.5 kg
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Heavy-duty valve wrench for tanker fittings.',
        client = {
            image = 'valve_wrench.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- BARREL DRUM
    -- Single drum item — metadata tracks fill amount.
    --
    -- Metadata fields:
    --   fill_level   number   0-100 (percentage full)
    --   contents     string   'fuel', 'hazmat', etc.
    --   capacity     number   gallons (default 55)
    -- ─────────────────────────────────────────────

    ['barrel_drum'] = {
        label    = 'Barrel Drum',
        weight   = 5000,      -- 5 kg empty, weight scales with fill in code
        stack    = true,
        close    = true,
        consume  = 0,
        description = '55-gallon barrel drum. Fill level and contents tracked via manifest.',
        client = {
            image = 'barrel_drum.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- ROBBERY ITEMS
    -- ─────────────────────────────────────────────

    ['spike_strip'] = {
        label    = 'Spike Strip',
        weight   = 5000,      -- 5 kg
        stack    = true,
        close    = true,
        consume  = 1,
        description = 'Deployable spike strip. Punctures tires on contact. Single use.',
        client = {
            image = 'spike_strip.png',
        },
    },

    ['comms_jammer'] = {
        label    = 'Communications Jammer',
        weight   = 2000,      -- 2 kg
        stack    = false,
        close    = true,
        consume  = 1,
        description = 'Portable radio jammer. Blocks distress signals for 3 minutes. Single use.',
        client = {
            image = 'comms_jammer.png',
        },
    },

    ['bolt_cutters'] = {
        label    = 'Bolt Cutters',
        weight   = 3000,      -- 3 kg
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Heavy-duty bolt cutters. Can breach standard trailer seals.',
        client = {
            image = 'bolt_cutters.png',
        },
    },

    ['military_bolt_cutters'] = {
        label    = 'Reinforced Bolt Cutters',
        weight   = 4000,      -- 4 kg
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Military-grade reinforced bolt cutters. Required for secured military cargo containers.',
        client = {
            image = 'military_bolt_cutters.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- HAZMAT CLEANUP
    -- ─────────────────────────────────────────────

    ['hazmat_cleanup_kit'] = {
        label    = 'HAZMAT Cleanup Kit',
        weight   = 8000,      -- 8 kg
        stack    = true,
        close    = true,
        consume  = 1,
        description = 'Universal hazardous materials cleanup kit. Neutralizes all hazmat spill classes.',
        client = {
            image = 'hazmat_cleanup_kit.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- MILITARY CARGO ITEMS
    -- Uses standard GTA armor and weapons from
    -- ox_inventory (no custom items needed).
    -- Loot tables reference: armour, weapon_pistol,
    -- weapon_carbinerifle, weapon_smg, weapon_combatmg,
    -- weapon_specialcarbine, ammo-rifle, ammo-9
    -- ─────────────────────────────────────────────
}
