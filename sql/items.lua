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
    -- CDL LICENSE ITEMS
    -- ─────────────────────────────────────────────

    ['cdl_class_b'] = {
        label    = 'CDL Class B License',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Commercial Driver\'s License — Class B. Authorizes operation of single-unit commercial vehicles.',
        client = {
            image = 'cdl_class_b.png',
        },
    },

    ['cdl_class_a'] = {
        label    = 'CDL Class A License',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Commercial Driver\'s License — Class A. Authorizes operation of combination vehicles and tractor-trailers.',
        client = {
            image = 'cdl_class_a.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- ENDORSEMENTS
    -- ─────────────────────────────────────────────

    ['tanker_endorsement'] = {
        label    = 'Tanker Endorsement',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'CDL tanker endorsement. Required for fuel tanker and liquid bulk hauls.',
        client = {
            image = 'tanker_endorsement.png',
        },
    },

    ['hazmat_endorsement'] = {
        label    = 'HAZMAT Endorsement',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'CDL hazardous materials endorsement. Required for all HAZMAT-classified cargo.',
        client = {
            image = 'hazmat_endorsement.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- PERMITS
    -- ─────────────────────────────────────────────

    ['oversized_permit'] = {
        label    = 'Oversized Load Permit',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Monthly oversized load permit. Required for oversized and heavy haul cargo.',
        client = {
            image = 'oversized_permit.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- CERTIFICATIONS
    -- ─────────────────────────────────────────────

    ['bilkington_cert'] = {
        label    = 'Bilkington Carrier Certification',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Bilkington Research carrier certification. Required for pharmaceutical and biologic loads.',
        client = {
            image = 'bilkington_cert.png',
        },
    },

    ['high_value_cert'] = {
        label    = 'High-Value Goods Certification',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Vangelico high-value goods carrier certification. Required for high-value freight.',
        client = {
            image = 'high_value_cert.png',
        },
    },

    ['government_clearance'] = {
        label    = 'Government Security Clearance',
        weight   = 50,
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'San Andreas government security clearance. Required for military and government cargo.',
        client = {
            image = 'government_clearance.png',
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

    ['fuel_canister'] = {
        label    = 'Fuel Canister',
        weight   = 500,       -- 0.5 kg empty
        stack    = true,
        close    = true,
        consume  = 0,
        description = '5-gallon fuel canister. Used for roadside fuel delivery.',
        client = {
            image = 'fuel_canister.png',
        },
    },

    ['fuel_drum'] = {
        label    = 'Fuel Drum',
        weight   = 5000,      -- 5 kg empty
        stack    = true,
        close    = true,
        consume  = 0,
        description = '55-gallon fuel drum. Used for bulk fuel storage from tanker drain operations.',
        client = {
            image = 'fuel_drum.png',
        },
    },

    ['stolen_fuel'] = {
        label    = 'Fuel Drum (Unmarked)',
        weight   = 20000,     -- 20 kg (55 gal of fuel ~160 kg, scaled for gameplay)
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'An unmarked 55-gallon drum of fuel. No manifest documentation.',
        client = {
            image = 'stolen_fuel.png',
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
    -- HAZMAT CLEANUP ITEMS
    -- ─────────────────────────────────────────────

    ['hazmat_cleanup_kit'] = {
        label    = 'HAZMAT Cleanup Kit',
        weight   = 8000,      -- 8 kg
        stack    = true,
        close    = true,
        consume  = 1,
        description = 'General hazardous materials cleanup kit. Neutralizes Class 3, 6, and 8 spills.',
        client = {
            image = 'hazmat_cleanup_kit.png',
        },
    },

    ['hazmat_cleanup_specialist'] = {
        label    = 'Specialist Cleanup Kit',
        weight   = 12000,     -- 12 kg
        stack    = true,
        close    = true,
        consume  = 1,
        description = 'Specialized decontamination kit. Required for Class 7 (radioactive) incidents.',
        client = {
            image = 'hazmat_cleanup_specialist.png',
        },
    },

    -- ─────────────────────────────────────────────
    -- MILITARY CARGO ITEMS
    -- ─────────────────────────────────────────────

    ['military_armor_vest'] = {
        label    = 'Military Armor Vest',
        weight   = 15000,     -- 15 kg
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'Military-issue ballistic vest. Stamped property of San Andreas National Guard.',
        client = {
            image = 'military_armor_vest.png',
        },
    },

    ['military_ammunition_box'] = {
        label    = 'Military Ammunition Box',
        weight   = 20000,     -- 20 kg
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'Sealed military ammunition crate. Contents classified.',
        client = {
            image = 'military_ammunition_box.png',
        },
    },

    ['military_vehicle_parts'] = {
        label    = 'Military Vehicle Parts',
        weight   = 25000,     -- 25 kg
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'Assorted military vehicle components. Serialized and tracked.',
        client = {
            image = 'military_vehicle_parts.png',
        },
    },

    ['military_pistol'] = {
        label    = 'Military Sidearm',
        weight   = 5000,      -- 5 kg (with case)
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'Military-issue sidearm. Serial number filed.',
        client = {
            image = 'military_pistol.png',
        },
    },

    ['military_rifle'] = {
        label    = 'Military Rifle',
        weight   = 8000,      -- 8 kg
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'Military-issue automatic rifle. Property of San Andreas National Guard.',
        client = {
            image = 'military_rifle.png',
        },
    },

    ['military_explosive_charge'] = {
        label    = 'Military Explosive Charge',
        weight   = 4000,      -- 4 kg
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'Military demolition charge. Handle with extreme caution.',
        client = {
            image = 'military_explosive_charge.png',
        },
    },

    ['classified_documents'] = {
        label    = 'Classified Documents',
        weight   = 1000,      -- 1 kg
        stack    = false,
        close    = true,
        consume  = 0,
        description = 'Sealed classified document pouch. Eyes only.',
        client = {
            image = 'classified_documents.png',
        },
    },

    ['military_rifle_suppressed'] = {
        label    = 'Suppressed Military Rifle',
        weight   = 6000,      -- 6 kg
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'Military-issue rifle with integrated suppressor. Restricted munitions.',
        client = {
            image = 'military_rifle_suppressed.png',
        },
    },

    ['military_lmg'] = {
        label    = 'Military Light Machine Gun',
        weight   = 12000,     -- 12 kg
        stack    = true,
        close    = true,
        consume  = 0,
        description = 'Military-issue light machine gun. Restricted munitions classification.',
        client = {
            image = 'military_lmg.png',
        },
    },
}
