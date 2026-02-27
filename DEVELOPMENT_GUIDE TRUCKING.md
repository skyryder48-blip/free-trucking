# FiveM QBox Trucking Script — Full Development Guide

> **Stack:** QBox · ox_lib · ox_inventory · oxmysql · lb-phone (optional)  
> **Map:** Los Santos = Chicago · Sandy Shores = Gary · Paleto = Wisconsin · Grapeseed = Western MI  
> **Economy:** Chicago market rates + 15% COL premium · GTA map scale 1:3.5

---

## TABLE OF CONTENTS

1. [Architecture Overview](#1-architecture-overview)
2. [File Structure](#2-file-structure)
3. [Dependencies](#3-dependencies)
4. [Database Schema](#4-database-schema)
5. [Configuration Reference](#5-configuration-reference)
6. [Core Systems](#6-core-systems)
7. [Cargo Tier Reference](#7-cargo-tier-reference)
8. [Payout Engine](#8-payout-engine)
9. [CDL and Certification System](#9-cdl-and-certification-system)
10. [Company and Dispatcher System](#10-company-and-dispatcher-system)
11. [Convoy System](#11-convoy-system)
12. [Job Board](#12-job-board)
13. [BOL System](#13-bol-system)
14. [Seal System](#14-seal-system)
15. [Temperature Monitoring](#15-temperature-monitoring)
16. [Livestock Welfare](#16-livestock-welfare)
17. [Cargo Securing](#17-cargo-securing)
18. [Weigh Station System](#18-weigh-station-system)
19. [Insurance System](#19-insurance-system)
20. [Reputation Systems](#20-reputation-systems)
21. [Criminal Systems — Leon and Suppliers](#21-criminal-systems--leon-and-suppliers)
22. [Robbery Mechanics](#22-robbery-mechanics)
23. [Fuel Tanker Systems](#23-fuel-tanker-systems)
24. [Hazmat Incident System](#24-hazmat-incident-system)
25. [Enhanced Explosion System](#25-enhanced-explosion-system)
26. [Military Heist](#26-military-heist)
27. [NUI and HUD](#27-nui-and-hud)
28. [NPC Conversation System](#28-npc-conversation-system)
29. [Exports and Events](#29-exports-and-events)
30. [Development Milestones](#30-development-milestones)

---

## 1. ARCHITECTURE OVERVIEW

```
trucking/
  server/          — All database calls, payout logic, state authority
  client/          — Vehicle detection, NUI triggers, world interactions
  shared/          — Config, cargo definitions, shipper definitions
  nui/             — React or HTML UI (standalone mode)
  locales/         — en.json and expansion language files
```

**Authority model:**
All financial transactions, reputation changes, BOL state mutations, and payout calculations run server-side. Client is responsible for proximity checks, NUI open/close, vehicle detection, and NPC interaction triggers. No payout or reputation logic runs client-side.

**Event naming convention:**
```
trucking:server:eventName     — server events
trucking:client:eventName     — client events  
trucking:nui:eventName        — NUI callbacks
```

**State management:**
Active loads stored in server-side table `ActiveLoads` (in-memory, synced to `truck_active_loads` on change). On resource restart, active loads are reloaded from database and mission state is restored for connected players.

---

## 2. FILE STRUCTURE

```
trucking/
├── fxmanifest.lua
├── config/
│   ├── config.lua              — Global settings
│   ├── economy.lua             — Rates, multipliers, payout formula
│   ├── shippers.lua            — All shipper definitions
│   ├── cargo.lua               — All cargo type definitions
│   ├── board.lua               — Board composition and refresh timing
│   ├── vehicles.lua            — Vehicle class mappings
│   ├── cdl.lua                 — Test question pools
│   ├── leon.lua                — Criminal supplier definitions
│   └── explosions.lua          — Explosion profile definitions
├── server/
│   ├── main.lua                — Resource start, state init
│   ├── database.lua            — All oxmysql queries (functions only)
│   ├── loads.lua               — Load generation, board management
│   ├── missions.lua            — Mission accept, transfer, complete
│   ├── payout.lua              — Payout calculation engine
│   ├── bol.lua                 — BOL generation and lifecycle
│   ├── reputation.lua          — Driver and shipper rep management
│   ├── insurance.lua           — Policy checks and claim processing
│   ├── company.lua             — Company and dispatcher logic
│   ├── convoy.lua              — Convoy formation and tracking
│   ├── cdl.lua                 — License issuance, test results
│   ├── leon.lua                — Criminal board management
│   ├── military.lua            — Military contract and heist handling
│   ├── explosions.lua          — Enhanced explosion event handler
│   ├── webhooks.lua            — Discord webhook dispatch
│   └── exports.lua             — All exported functions
├── client/
│   ├── main.lua                — Resource init, player state
│   ├── interactions.lua        — ox_lib zone and NPC interactions
│   ├── missions.lua            — Active load tracking, HUD updates
│   ├── vehicles.lua            — Vehicle detection, health monitoring
│   ├── bol.lua                 — Physical BOL item interactions
│   ├── seals.lua               — Seal monitoring, break detection
│   ├── temperature.lua         — Reefer monitoring, excursion detection
│   ├── livestock.lua           — Welfare event detection
│   ├── securing.lua            — Cargo securing interactions
│   ├── weighstation.lua        — Weigh station zone and interaction
│   ├── cdl.lua                 — CDL test and tutorial NUI triggers
│   ├── company.lua             — Company/dispatcher client state
│   ├── convoy.lua              — Convoy proximity tracking
│   ├── leon.lua                — Leon interaction client
│   ├── military.lua            — Convoy following, breach detection
│   ├── tanker.lua              — Drain mechanic, spill zones
│   ├── hazmat.lua              — Hazmat spill and exposure handling
│   ├── explosions.lua          — Explosion phase sequencer
│   └── hud.lua                 — Active load HUD overlay
├── shared/
│   └── utils.lua               — Shared utility functions
├── nui/
│   ├── index.html
│   ├── css/
│   │   └── main.css            — Bears palette, typography
│   ├── js/
│   │   ├── app.js              — Main NUI controller
│   │   ├── board.js            — Board screen
│   │   ├── activeload.js       — Active load screen
│   │   ├── profile.js          — Profile and credentials
│   │   ├── insurance.js        — Insurance screen
│   │   └── company.js          — Company dashboard
│   └── fonts/
│       ├── BarlowCondensed-Bold.woff2
│       └── Inter-Regular.woff2
└── locales/
    └── en.json
```

---

## 3. DEPENDENCIES

```lua
-- fxmanifest.lua
fx_version 'cerulean'
game 'gta5'

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'qb-core',          -- or qbx_core
}

-- Optional — lb-phone integration
-- Config.UsePhoneApp = true enables phone mode
-- Config.UseStandaloneNUI = true enables standalone
```

**ox_lib usage:**
- `lib.zones` — Loading zones, weigh station zones, Leon interaction zone
- `lib.notify` — All player notifications
- `lib.inputDialog` — Manifest verification inputs
- `lib.alertDialog` — Confirmation prompts (accept load, abandon load)
- `lib.progressBar` — Cargo securing, drain interactions, hold-to-confirm
- `lib.registerContext` / `lib.showContext` — NPC conversation menus

**ox_inventory usage:**
- Physical BOL items
- CDL license items  
- Certification items
- Fuel drum items (`stolen_fuel`, `milk_jug_bulk`)
- Drain items (`fuel_hose`, `valve_wrench`, `fuel_canister`)
- Criminal items (`military_bolt_cutters`, `military_explosive_charge`)

---

## 4. DATABASE SCHEMA

### 4.1 Complete Table List (24 tables)

```
DRIVER CORE
  truck_drivers
  truck_licenses
  truck_certifications

LOAD SYSTEM
  truck_loads
  truck_active_loads
  truck_bols
  truck_bol_events
  truck_supplier_contracts
  truck_open_contracts
  truck_open_contract_contributions
  truck_routes

FINANCIAL
  truck_deposits
  truck_insurance_policies
  truck_insurance_claims

REPUTATION
  truck_driver_reputation_log
  truck_shipper_reputation
  truck_shipper_reputation_log

COMPANY
  truck_companies
  truck_company_members
  truck_convoys

CARGO TRACKING
  truck_integrity_events
  truck_weigh_station_records
  truck_livestock_welfare_logs

SYSTEM
  truck_board_state
  truck_surge_events
  truck_webhook_log
```

### 4.2 Full DDL

```sql
-- ─────────────────────────────────────────────
-- DRIVER CORE
-- ─────────────────────────────────────────────

CREATE TABLE truck_drivers (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    citizenid               VARCHAR(50) NOT NULL UNIQUE,
    player_name             VARCHAR(100) NOT NULL,
    reputation_score        SMALLINT UNSIGNED NOT NULL DEFAULT 500,
    reputation_tier         ENUM('suspended','restricted','probationary',
                                 'developing','established',
                                 'professional','elite')
                            NOT NULL DEFAULT 'developing',
    suspended_until         INT UNSIGNED DEFAULT NULL,
    total_loads_completed   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    total_loads_failed      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    total_loads_stolen      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    total_distance_driven   INT UNSIGNED NOT NULL DEFAULT 0,
    total_earnings          INT UNSIGNED NOT NULL DEFAULT 0,
    reservation_releases    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    reservation_cooldown    INT UNSIGNED DEFAULT NULL,
    leon_access             BOOLEAN NOT NULL DEFAULT FALSE,
    leon_tier3_deliveries   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    leon_total_loads        SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    first_seen              INT UNSIGNED NOT NULL,
    last_seen               INT UNSIGNED NOT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_reputation_tier (reputation_tier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_licenses (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    driver_id               BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    license_type            ENUM('class_b','class_a','tanker',
                                 'hazmat','oversized_monthly') NOT NULL,
    status                  ENUM('active','suspended','revoked')
                            NOT NULL DEFAULT 'active',
    written_test_attempts   TINYINT UNSIGNED NOT NULL DEFAULT 0,
    practical_passed_at     INT UNSIGNED DEFAULT NULL,
    locked_until            INT UNSIGNED DEFAULT NULL,
    fee_paid                SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    issued_at               INT UNSIGNED NOT NULL,
    expires_at              INT UNSIGNED DEFAULT NULL,
    UNIQUE KEY uq_driver_license (driver_id, license_type),
    INDEX idx_citizenid (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_certifications (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    driver_id               BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    cert_type               ENUM('bilkington_carrier','high_value',
                                 'government_clearance') NOT NULL,
    status                  ENUM('active','suspended','revoked','expired')
                            NOT NULL DEFAULT 'active',
    revoked_reason          VARCHAR(255) DEFAULT NULL,
    revoked_at              INT UNSIGNED DEFAULT NULL,
    reinstatement_eligible  INT UNSIGNED DEFAULT NULL,
    background_fee_paid     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    issued_at               INT UNSIGNED NOT NULL,
    expires_at              INT UNSIGNED DEFAULT NULL,
    UNIQUE KEY uq_driver_cert (driver_id, cert_type),
    INDEX idx_citizenid (citizenid),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────
-- LOAD SYSTEM
-- ─────────────────────────────────────────────

CREATE TABLE truck_loads (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bol_number              VARCHAR(20) NOT NULL UNIQUE,
    tier                    TINYINT UNSIGNED NOT NULL,
    cargo_type              VARCHAR(50) NOT NULL,
    cargo_subtype           VARCHAR(50) DEFAULT NULL,
    shipper_id              VARCHAR(50) NOT NULL,
    shipper_name            VARCHAR(100) NOT NULL,
    origin_region           ENUM('los_santos','sandy_shores',
                                 'paleto','grapeseed') NOT NULL,
    origin_label            VARCHAR(100) NOT NULL,
    origin_coords           JSON NOT NULL,
    destination_label       VARCHAR(100) NOT NULL,
    destination_coords      JSON NOT NULL,
    distance_miles          DECIMAL(6,2) NOT NULL,
    weight_lbs              INT UNSIGNED NOT NULL DEFAULT 0,
    weight_multiplier       DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    temp_min_f              TINYINT DEFAULT NULL,
    temp_max_f              TINYINT DEFAULT NULL,
    hazmat_class            TINYINT UNSIGNED DEFAULT NULL,
    hazmat_un_number        VARCHAR(10) DEFAULT NULL,
    requires_seal           BOOLEAN NOT NULL DEFAULT TRUE,
    min_vehicle_class       ENUM('none','class_b','class_a')
                            NOT NULL DEFAULT 'none',
    required_vehicle_type   VARCHAR(50) DEFAULT NULL,
    required_license        ENUM('none','class_b','class_a')
                            NOT NULL DEFAULT 'none',
    required_endorsement    VARCHAR(50) DEFAULT NULL,
    required_certification  VARCHAR(50) DEFAULT NULL,
    base_rate_per_mile      DECIMAL(8,2) NOT NULL,
    base_payout_rental      INT UNSIGNED NOT NULL DEFAULT 0,
    base_payout_owner_op    INT UNSIGNED NOT NULL DEFAULT 0,
    deposit_amount          INT UNSIGNED NOT NULL DEFAULT 300,
    board_status            ENUM('available','reserved','accepted',
                                 'completed','expired','orphaned')
                            NOT NULL DEFAULT 'available',
    reserved_by             VARCHAR(50) DEFAULT NULL,
    reserved_until          INT UNSIGNED DEFAULT NULL,
    surge_active            BOOLEAN NOT NULL DEFAULT FALSE,
    surge_percentage        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    surge_expires           INT UNSIGNED DEFAULT NULL,
    is_leon_load            BOOLEAN NOT NULL DEFAULT FALSE,
    leon_fee                INT UNSIGNED DEFAULT NULL,
    leon_risk_tier          ENUM('low','medium','high','critical')
                            DEFAULT NULL,
    leon_supplier_id        VARCHAR(50) DEFAULT NULL,
    is_multi_stop           BOOLEAN NOT NULL DEFAULT FALSE,
    stop_count              TINYINT UNSIGNED NOT NULL DEFAULT 1,
    posted_at               INT UNSIGNED NOT NULL,
    expires_at              INT UNSIGNED NOT NULL,
    board_region            ENUM('los_santos','sandy_shores',
                                 'paleto','grapeseed') NOT NULL,
    INDEX idx_board_status (board_status),
    INDEX idx_board_region (board_region),
    INDEX idx_tier (tier),
    INDEX idx_expires_at (expires_at),
    INDEX idx_reserved_by (reserved_by)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_active_loads (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    load_id                 BIGINT UNSIGNED NOT NULL,
    bol_id                  BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    driver_id               BIGINT UNSIGNED NOT NULL,
    vehicle_plate           VARCHAR(20) DEFAULT NULL,
    vehicle_model           VARCHAR(50) DEFAULT NULL,
    is_rental               BOOLEAN NOT NULL DEFAULT FALSE,
    status                  ENUM('at_origin','in_transit','at_stop',
                                 'at_destination','distress_active')
                            NOT NULL DEFAULT 'at_origin',
    current_stop            TINYINT UNSIGNED NOT NULL DEFAULT 1,
    cargo_integrity         TINYINT UNSIGNED NOT NULL DEFAULT 100,
    cargo_secured           BOOLEAN NOT NULL DEFAULT FALSE,
    seal_status             ENUM('sealed','broken','not_applied')
                            NOT NULL DEFAULT 'not_applied',
    seal_number             VARCHAR(30) DEFAULT NULL,
    seal_broken_at          INT UNSIGNED DEFAULT NULL,
    temp_monitoring_active  BOOLEAN NOT NULL DEFAULT FALSE,
    current_temp_f          DECIMAL(5,2) DEFAULT NULL,
    excursion_active        BOOLEAN NOT NULL DEFAULT FALSE,
    excursion_start         INT UNSIGNED DEFAULT NULL,
    excursion_total_mins    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    reefer_operational      BOOLEAN NOT NULL DEFAULT TRUE,
    welfare_rating          TINYINT UNSIGNED DEFAULT NULL,
    permit_number           VARCHAR(30) DEFAULT NULL,
    route_violations        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    weigh_station_stamped   BOOLEAN NOT NULL DEFAULT FALSE,
    pre_trip_completed      BOOLEAN NOT NULL DEFAULT FALSE,
    manifest_verified       BOOLEAN NOT NULL DEFAULT FALSE,
    accepted_at             INT UNSIGNED NOT NULL,
    window_expires_at       INT UNSIGNED NOT NULL,
    window_reduction_secs   INT UNSIGNED NOT NULL DEFAULT 0,
    departed_at             INT UNSIGNED DEFAULT NULL,
    deposit_posted          INT UNSIGNED NOT NULL DEFAULT 0,
    insurance_policy_id     BIGINT UNSIGNED DEFAULT NULL,
    estimated_payout        INT UNSIGNED NOT NULL DEFAULT 0,
    company_id              BIGINT UNSIGNED DEFAULT NULL,
    convoy_id               BIGINT UNSIGNED DEFAULT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_load_id (load_id),
    INDEX idx_company_id (company_id),
    INDEX idx_convoy_id (convoy_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_bols (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bol_number              VARCHAR(20) NOT NULL UNIQUE,
    load_id                 BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    driver_name             VARCHAR(100) NOT NULL,
    company_id              BIGINT UNSIGNED DEFAULT NULL,
    company_name            VARCHAR(100) DEFAULT NULL,
    shipper_id              VARCHAR(50) NOT NULL,
    shipper_name            VARCHAR(100) NOT NULL,
    origin_label            VARCHAR(100) NOT NULL,
    destination_label       VARCHAR(100) NOT NULL,
    distance_miles          DECIMAL(6,2) NOT NULL,
    cargo_type              VARCHAR(50) NOT NULL,
    cargo_description       TEXT DEFAULT NULL,
    weight_lbs              INT UNSIGNED NOT NULL,
    tier                    TINYINT UNSIGNED NOT NULL,
    hazmat_class            TINYINT UNSIGNED DEFAULT NULL,
    placard_class           VARCHAR(50) DEFAULT NULL,
    license_class           VARCHAR(20) DEFAULT NULL,
    license_matched         BOOLEAN NOT NULL DEFAULT TRUE,
    seal_number             VARCHAR(30) DEFAULT NULL,
    seal_status             ENUM('sealed','broken','not_applied',
                                 'delivered_intact')
                            NOT NULL DEFAULT 'not_applied',
    temp_required_min       TINYINT DEFAULT NULL,
    temp_required_max       TINYINT DEFAULT NULL,
    temp_compliance         ENUM('not_required','clean',
                                 'minor_excursion','significant_excursion')
                            DEFAULT 'not_required',
    weigh_station_stamp     BOOLEAN NOT NULL DEFAULT FALSE,
    manifest_verified       BOOLEAN NOT NULL DEFAULT FALSE,
    pre_trip_completed      BOOLEAN NOT NULL DEFAULT FALSE,
    welfare_final_rating    TINYINT UNSIGNED DEFAULT NULL,
    bol_status              ENUM('active','delivered','rejected',
                                 'stolen','abandoned','expired','partial')
                            NOT NULL DEFAULT 'active',
    item_in_inventory       BOOLEAN NOT NULL DEFAULT TRUE,
    item_disposed_at        INT UNSIGNED DEFAULT NULL,
    final_payout            INT UNSIGNED DEFAULT NULL,
    payout_breakdown        JSON DEFAULT NULL,
    deposit_returned        BOOLEAN NOT NULL DEFAULT FALSE,
    is_leon                 BOOLEAN NOT NULL DEFAULT FALSE,
    issued_at               INT UNSIGNED NOT NULL,
    departed_at             INT UNSIGNED DEFAULT NULL,
    delivered_at            INT UNSIGNED DEFAULT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_bol_status (bol_status),
    INDEX idx_shipper_id (shipper_id),
    INDEX idx_issued_at (issued_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_bol_events (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bol_id                  BIGINT UNSIGNED NOT NULL,
    bol_number              VARCHAR(20) NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    event_type              ENUM(
        'load_accepted','departed_origin','seal_applied','seal_broken',
        'cargo_secured','cargo_shift','cargo_shift_resolved',
        'integrity_event','temp_excursion_start','temp_excursion_end',
        'reefer_failure','reefer_restored','welfare_event',
        'weigh_station_stamped','weigh_station_violation',
        'route_violation','stop_completed','distress_signal',
        'robbery_initiated','robbery_completed','load_delivered',
        'load_rejected','load_abandoned','load_stolen',
        'window_expired','window_reduced','transfer_completed',
        'cdl_mismatch_noted','manifest_discrepancy'
    ) NOT NULL,
    event_data              JSON DEFAULT NULL,
    coords                  JSON DEFAULT NULL,
    occurred_at             INT UNSIGNED NOT NULL,
    INDEX idx_bol_id (bol_id),
    INDEX idx_event_type (event_type),
    INDEX idx_occurred_at (occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_supplier_contracts (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    client_id               VARCHAR(50) NOT NULL,
    client_name             VARCHAR(100) NOT NULL,
    region                  ENUM('los_santos','sandy_shores',
                                 'paleto','grapeseed') NOT NULL,
    required_item           VARCHAR(50) NOT NULL,
    required_quantity       INT UNSIGNED NOT NULL,
    destination_label       VARCHAR(100) NOT NULL,
    destination_coords      JSON NOT NULL,
    window_hours            TINYINT UNSIGNED NOT NULL DEFAULT 4,
    base_payout             INT UNSIGNED NOT NULL,
    partial_allowed         BOOLEAN NOT NULL DEFAULT TRUE,
    contract_status         ENUM('available','accepted',
                                 'fulfilled','expired')
                            NOT NULL DEFAULT 'available',
    accepted_by             VARCHAR(50) DEFAULT NULL,
    accepted_at             INT UNSIGNED DEFAULT NULL,
    window_expires_at       INT UNSIGNED DEFAULT NULL,
    quantity_delivered      INT UNSIGNED NOT NULL DEFAULT 0,
    posted_at               INT UNSIGNED NOT NULL,
    expires_at              INT UNSIGNED NOT NULL,
    is_leon                 BOOLEAN NOT NULL DEFAULT FALSE,
    INDEX idx_contract_status (contract_status),
    INDEX idx_region (region)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_open_contracts (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    client_id               VARCHAR(50) NOT NULL,
    client_name             VARCHAR(100) NOT NULL,
    cargo_type              VARCHAR(50) NOT NULL,
    total_quantity_needed   INT UNSIGNED NOT NULL,
    quantity_fulfilled      INT UNSIGNED NOT NULL DEFAULT 0,
    total_payout_pool       INT UNSIGNED NOT NULL,
    min_contribution_pct    DECIMAL(4,2) NOT NULL DEFAULT 0.10,
    contract_status         ENUM('active','fulfilled','expired')
                            NOT NULL DEFAULT 'active',
    posted_at               INT UNSIGNED NOT NULL,
    expires_at              INT UNSIGNED NOT NULL,
    fulfilled_at            INT UNSIGNED DEFAULT NULL,
    INDEX idx_contract_status (contract_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_open_contract_contributions (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    contract_id             BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    company_id              BIGINT UNSIGNED DEFAULT NULL,
    quantity_contributed    INT UNSIGNED NOT NULL DEFAULT 0,
    contribution_pct        DECIMAL(6,4) NOT NULL DEFAULT 0.0000,
    payout_earned           INT UNSIGNED DEFAULT NULL,
    payout_issued           BOOLEAN NOT NULL DEFAULT FALSE,
    last_contribution_at    INT UNSIGNED DEFAULT NULL,
    UNIQUE KEY uq_contract_driver (contract_id, citizenid),
    INDEX idx_citizenid (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_routes (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    route_name              VARCHAR(100) NOT NULL,
    shipper_id              VARCHAR(50) NOT NULL,
    region                  ENUM('los_santos','sandy_shores',
                                 'paleto','grapeseed') NOT NULL,
    tier                    TINYINT UNSIGNED NOT NULL,
    cargo_type              VARCHAR(50) NOT NULL,
    stop_count              TINYINT UNSIGNED NOT NULL,
    stops                   JSON NOT NULL,
    total_distance_miles    DECIMAL(6,2) NOT NULL,
    required_license        ENUM('none','class_b','class_a')
                            NOT NULL DEFAULT 'none',
    base_payout_rental      INT UNSIGNED NOT NULL,
    base_payout_owner_op    INT UNSIGNED NOT NULL,
    multi_stop_premium_pct  DECIMAL(4,2) NOT NULL,
    deposit_amount          INT UNSIGNED NOT NULL,
    window_minutes          SMALLINT UNSIGNED NOT NULL,
    route_status            ENUM('available','accepted',
                                 'completed','expired')
                            NOT NULL DEFAULT 'available',
    accepted_by             VARCHAR(50) DEFAULT NULL,
    accepted_at             INT UNSIGNED DEFAULT NULL,
    posted_at               INT UNSIGNED NOT NULL,
    expires_at              INT UNSIGNED NOT NULL,
    INDEX idx_region (region),
    INDEX idx_route_status (route_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────
-- FINANCIAL
-- ─────────────────────────────────────────────

CREATE TABLE truck_deposits (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bol_id                  BIGINT UNSIGNED NOT NULL,
    bol_number              VARCHAR(20) NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    amount                  INT UNSIGNED NOT NULL,
    tier                    TINYINT UNSIGNED NOT NULL,
    deposit_type            ENUM('flat','percentage')
                            NOT NULL DEFAULT 'percentage',
    status                  ENUM('held','returned','forfeited')
                            NOT NULL DEFAULT 'held',
    resolved_at             INT UNSIGNED DEFAULT NULL,
    posted_at               INT UNSIGNED NOT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_bol_id (bol_id),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_insurance_policies (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    citizenid               VARCHAR(50) NOT NULL,
    policy_type             ENUM('single_load','day','week') NOT NULL,
    tier_coverage           TINYINT UNSIGNED NOT NULL DEFAULT 0,
    premium_paid            INT UNSIGNED NOT NULL,
    status                  ENUM('active','expired','used')
                            NOT NULL DEFAULT 'active',
    valid_from              INT UNSIGNED NOT NULL,
    valid_until             INT UNSIGNED DEFAULT NULL,
    bound_bol_id            BIGINT UNSIGNED DEFAULT NULL,
    purchased_at            INT UNSIGNED NOT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_status (status),
    INDEX idx_valid_until (valid_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_insurance_claims (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    citizenid               VARCHAR(50) NOT NULL,
    policy_id               BIGINT UNSIGNED NOT NULL,
    bol_id                  BIGINT UNSIGNED NOT NULL,
    bol_number              VARCHAR(20) NOT NULL,
    claim_type              ENUM('theft','abandonment') NOT NULL,
    deposit_amount          INT UNSIGNED NOT NULL,
    premium_allocated       INT UNSIGNED NOT NULL,
    claim_amount            INT UNSIGNED NOT NULL,
    status                  ENUM('pending','approved','paid','denied')
                            NOT NULL DEFAULT 'pending',
    payout_at               INT UNSIGNED DEFAULT NULL,
    filed_at                INT UNSIGNED NOT NULL,
    resolved_at             INT UNSIGNED DEFAULT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_bol_number (bol_number),
    INDEX idx_status (status),
    INDEX idx_payout_at (payout_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────
-- REPUTATION
-- ─────────────────────────────────────────────

CREATE TABLE truck_driver_reputation_log (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    driver_id               BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    change_type             VARCHAR(50) NOT NULL,
    points_before           SMALLINT UNSIGNED NOT NULL,
    points_change           SMALLINT NOT NULL,
    points_after            SMALLINT UNSIGNED NOT NULL,
    tier_before             VARCHAR(20) DEFAULT NULL,
    tier_after              VARCHAR(20) DEFAULT NULL,
    bol_id                  BIGINT UNSIGNED DEFAULT NULL,
    bol_number              VARCHAR(20) DEFAULT NULL,
    tier_of_load            TINYINT UNSIGNED DEFAULT NULL,
    occurred_at             INT UNSIGNED NOT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_occurred_at (occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_shipper_reputation (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    driver_id               BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    shipper_id              VARCHAR(50) NOT NULL,
    points                  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    tier                    ENUM('unknown','familiar','established',
                                 'trusted','preferred','blacklisted')
                            NOT NULL DEFAULT 'unknown',
    deliveries_completed    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    current_clean_streak    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    last_delivery_at        INT UNSIGNED DEFAULT NULL,
    preferred_decay_warned  BOOLEAN NOT NULL DEFAULT FALSE,
    blacklisted_at          INT UNSIGNED DEFAULT NULL,
    reinstatement_eligible  INT UNSIGNED DEFAULT NULL,
    UNIQUE KEY uq_driver_shipper (driver_id, shipper_id),
    INDEX idx_citizenid (citizenid),
    INDEX idx_shipper_id (shipper_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_shipper_reputation_log (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    driver_id               BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    shipper_id              VARCHAR(50) NOT NULL,
    change_type             VARCHAR(50) NOT NULL,
    points_before           SMALLINT UNSIGNED NOT NULL,
    points_change           SMALLINT NOT NULL,
    points_after            SMALLINT UNSIGNED NOT NULL,
    tier_before             VARCHAR(20) DEFAULT NULL,
    tier_after              VARCHAR(20) DEFAULT NULL,
    bol_id                  BIGINT UNSIGNED DEFAULT NULL,
    occurred_at             INT UNSIGNED NOT NULL,
    INDEX idx_citizenid (citizenid),
    INDEX idx_shipper_id (shipper_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────
-- COMPANY
-- ─────────────────────────────────────────────

CREATE TABLE truck_companies (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    company_name            VARCHAR(100) NOT NULL UNIQUE,
    owner_citizenid         VARCHAR(50) NOT NULL,
    dispatcher_citizenid    VARCHAR(50) DEFAULT NULL,
    founded_at              INT UNSIGNED NOT NULL,
    INDEX idx_owner (owner_citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_company_members (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    company_id              BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    role                    ENUM('owner','driver') NOT NULL DEFAULT 'driver',
    joined_at               INT UNSIGNED NOT NULL,
    UNIQUE KEY uq_company_driver (company_id, citizenid),
    INDEX idx_citizenid (citizenid),
    INDEX idx_company_id (company_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_convoys (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    initiated_by            VARCHAR(50) NOT NULL,
    company_id              BIGINT UNSIGNED DEFAULT NULL,
    convoy_type             ENUM('open','invite','company') NOT NULL,
    status                  ENUM('forming','active','completed','disbanded')
                            NOT NULL DEFAULT 'forming',
    vehicle_count           TINYINT UNSIGNED NOT NULL DEFAULT 1,
    started_at              INT UNSIGNED DEFAULT NULL,
    completed_at            INT UNSIGNED DEFAULT NULL,
    created_at              INT UNSIGNED NOT NULL,
    INDEX idx_status (status),
    INDEX idx_initiated_by (initiated_by)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────
-- CARGO TRACKING
-- ─────────────────────────────────────────────

CREATE TABLE truck_integrity_events (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bol_id                  BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    event_cause             ENUM('collision_minor','collision_moderate',
                                 'collision_major','rollover',
                                 'sharp_cornering','off_road',
                                 'cargo_shift','liquid_agitation',
                                 'spill_damage','temperature_damage')
                            NOT NULL,
    integrity_before        TINYINT UNSIGNED NOT NULL,
    integrity_loss          TINYINT UNSIGNED NOT NULL,
    integrity_after         TINYINT UNSIGNED NOT NULL,
    vehicle_speed           TINYINT UNSIGNED DEFAULT NULL,
    vehicle_coords          JSON DEFAULT NULL,
    occurred_at             INT UNSIGNED NOT NULL,
    INDEX idx_bol_id (bol_id),
    INDEX idx_citizenid (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_weigh_station_records (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bol_id                  BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    station_id              VARCHAR(50) NOT NULL,
    station_label           VARCHAR(100) NOT NULL,
    station_region          ENUM('los_santos','sandy_shores',
                                 'paleto','grapeseed') NOT NULL,
    inspection_result       ENUM('passed','warning',
                                 'violation','impound') NOT NULL DEFAULT 'passed',
    stamp_issued            BOOLEAN NOT NULL DEFAULT FALSE,
    violations_noted        JSON DEFAULT NULL,
    inspected_at            INT UNSIGNED NOT NULL,
    INDEX idx_bol_id (bol_id),
    INDEX idx_citizenid (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_livestock_welfare_logs (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bol_id                  BIGINT UNSIGNED NOT NULL,
    citizenid               VARCHAR(50) NOT NULL,
    welfare_rating          TINYINT UNSIGNED NOT NULL,
    event_type              ENUM('sample','hard_brake','sharp_corner',
                                 'collision','off_road','heat_exposure',
                                 'rest_stop_quick','rest_stop_water',
                                 'rest_stop_full','time_decay','recovery')
                            NOT NULL DEFAULT 'sample',
    rating_change           TINYINT NOT NULL DEFAULT 0,
    occurred_at             INT UNSIGNED NOT NULL,
    INDEX idx_bol_id (bol_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────
-- SYSTEM
-- ─────────────────────────────────────────────

CREATE TABLE truck_board_state (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    region                  ENUM('los_santos','sandy_shores',
                                 'paleto','grapeseed','server_wide')
                            NOT NULL UNIQUE,
    last_refresh_at         INT UNSIGNED DEFAULT NULL,
    next_refresh_at         INT UNSIGNED DEFAULT NULL,
    refresh_interval_secs   SMALLINT UNSIGNED NOT NULL DEFAULT 7200,
    available_t0            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    available_t1            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    available_t2            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    available_t3            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    surge_active_count      TINYINT UNSIGNED NOT NULL DEFAULT 0,
    updated_at              INT UNSIGNED NOT NULL,
    INDEX idx_region (region)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_surge_events (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    region                  ENUM('los_santos','sandy_shores',
                                 'paleto','grapeseed','server_wide') NOT NULL,
    surge_type              ENUM('open_contract_progress','weather_event',
                                 'robbery_corridor','cold_chain_failure_streak',
                                 'peak_population','shipper_backlog','manual')
                            NOT NULL,
    cargo_type_filter       VARCHAR(50) DEFAULT NULL,
    shipper_filter          VARCHAR(50) DEFAULT NULL,
    surge_percentage        TINYINT UNSIGNED NOT NULL,
    trigger_data            JSON DEFAULT NULL,
    status                  ENUM('active','expired','cancelled')
                            NOT NULL DEFAULT 'active',
    started_at              INT UNSIGNED NOT NULL,
    expires_at              INT UNSIGNED NOT NULL,
    ended_at                INT UNSIGNED DEFAULT NULL,
    INDEX idx_status (status),
    INDEX idx_expires_at (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE truck_webhook_log (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    webhook_channel         ENUM('insurance','leon','military',
                                 'claims','surge','admin') NOT NULL,
    event_type              VARCHAR(100) NOT NULL,
    citizenid               VARCHAR(50) DEFAULT NULL,
    bol_number              VARCHAR(20) DEFAULT NULL,
    payload                 JSON NOT NULL,
    delivered               BOOLEAN NOT NULL DEFAULT FALSE,
    delivery_attempts       TINYINT UNSIGNED NOT NULL DEFAULT 0,
    delivered_at            INT UNSIGNED DEFAULT NULL,
    created_at              INT UNSIGNED NOT NULL,
    INDEX idx_delivered (delivered),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 4.3 Maintenance Queries

Run on server restart and every 15 minutes via scheduled event:

```sql
-- Expire stale reservations (3-minute hold expired)
UPDATE truck_loads
SET board_status = 'available', reserved_by = NULL, reserved_until = NULL
WHERE board_status = 'reserved' AND reserved_until < UNIX_TIMESTAMP();

-- Expire board loads
UPDATE truck_loads SET board_status = 'expired'
WHERE board_status = 'available' AND expires_at < UNIX_TIMESTAMP();

-- Expire surges
UPDATE truck_surge_events SET status = 'expired', ended_at = UNIX_TIMESTAMP()
WHERE status = 'active' AND expires_at < UNIX_TIMESTAMP();

-- Expire insurance policies
UPDATE truck_insurance_policies SET status = 'expired'
WHERE status = 'active' AND valid_until < UNIX_TIMESTAMP();

-- Issue pending claim payouts
SELECT ic.id, ic.citizenid, ic.claim_amount FROM truck_insurance_claims ic
WHERE ic.status = 'approved' AND ic.payout_at <= UNIX_TIMESTAMP();

-- Lift suspensions
UPDATE truck_drivers
SET reputation_tier = 'restricted', reputation_score = 1, suspended_until = NULL
WHERE reputation_tier = 'suspended' AND suspended_until < UNIX_TIMESTAMP();

-- Preferred tier decay (14 days inactive)
UPDATE truck_shipper_reputation
SET tier = 'trusted', points = LEAST(points, 699)
WHERE tier = 'preferred'
  AND last_delivery_at < (UNIX_TIMESTAMP() - 1209600)
  AND preferred_decay_warned = TRUE;
```

---

## 5. CONFIGURATION REFERENCE

### 5.1 config/config.lua

```lua
Config = {}

-- NUI mode
Config.UsePhoneApp        = false   -- lb-phone integration
Config.UseStandaloneNUI   = true    -- standalone NUI (F6)
Config.NUIKey             = 'F6'

-- Integration
Config.PoliceResource     = 'your-police-script'
Config.PhoneResource      = 'lb-phone'

-- Discord webhooks (set to nil to disable)
Config.Webhooks = {
    insurance   = nil,
    leon        = nil,
    military    = nil,
    admin       = nil,
}

-- Board settings
Config.BoardRefreshSeconds = 7200   -- 2 hours
Config.RouteRefreshSeconds = 21600  -- 6 hours
Config.ReservationSeconds  = 180    -- 3 minutes
Config.ReservationWarning  = 3      -- releases before cooldown
Config.ReservationCooldown = 600    -- 10 minutes

-- Deposit percentage by tier
Config.DepositRates = {
    [0] = 0,       -- flat $300
    [1] = 0.15,
    [2] = 0.20,
    [3] = 0.25,
}
Config.DepositFlatT0 = 300

-- Minimum floors by tier
Config.PayoutFloors = {
    [0] = 200,
    [1] = 350,
    [2] = 500,
    [3] = 750,
}

-- Seal break trooper alert priority
Config.SealBreakAlertPriority = 'low'

-- Military dispatch
Config.MilitaryDispatchEnabled = true

-- Reefer vehicle health threshold
Config.ReeferHealthThreshold  = 65
Config.PharmaHealthThreshold   = 80

-- Temperature excursion thresholds
Config.ExcursionMinorMins      = 5
Config.ExcursionSignificantMins = 15

-- Livestock welfare decay
Config.WelfarePassiveDecayStart = 30  -- minutes before decay begins

-- Leon access threshold
Config.LeonUnlockDeliveries    = 15   -- Tier 3 deliveries required

-- Military convoy
Config.MilitaryEscortPursueRange = 500   -- meters
Config.MilitaryEscortHoldSeconds = 90    -- before returning to origin
Config.LongConReputationHit      = 400
Config.LongConClearanceSuspendDays = 30
```

### 5.2 config/economy.lua

```lua
Economy = {}

-- Base rates per mile by tier
Economy.BaseRates = {
    [0] = 35,
    [1] = 55,
    [2] = 80,
    [3] = 115,
}

-- Cargo type rate modifiers (multiplied by base)
Economy.CargoRateModifiers = {
    light_general_freight   = 1.00,
    food_beverage_small     = 1.00,
    retail_small            = 1.00,
    courier                 = 1.00,
    general_freight_full    = 1.00,
    building_materials      = 1.00,
    food_beverage_full      = 1.00,
    food_beverage_reefer    = 1.09,  -- $60/mi T1 reefer
    retail_full             = 1.00,
    cold_chain              = 1.125, -- $90/mi T2 cold chain
    pharmaceutical          = 1.69,  -- $135/mi standard pharma
    pharmaceutical_biologic = 1.875, -- $150/mi biologic
    fuel_tanker             = 1.15,
    liquid_bulk_food        = 1.10,
    liquid_bulk_industrial  = 1.0625,
    livestock               = 1.10,
    oversized               = 1.1875,
    oversized_heavy         = 1.3125,
    hazmat                  = 1.2175,
    hazmat_class7           = 1.435,
    high_value              = 1.2609,
    military                = 1.522,
}

-- Weight multipliers
Economy.WeightMultipliers = {
    { max = 10000,  multiplier = 1.00 },
    { max = 26000,  multiplier = 1.15 },
    { max = 40000,  multiplier = 1.30 },
    { max = 80001,  multiplier = 1.50 },
}

-- Owner-operator bonus by tier
Economy.OwnerOpBonus = {
    [0] = 0.20,
    [1] = 0.20,
    [2] = 0.25,
    [3] = 0.30,
}

-- Time performance modifiers
Economy.TimePerformance = {
    { maxPct = 0.80,  modifier = 0.15  },  -- under 80% ETA: +15%
    { maxPct = 1.00,  modifier = 0.00  },  -- 80-100%: no mod
    { maxPct = 1.20,  modifier = -0.10 },  -- 100-120%: -10%
    { maxPct = 999,   modifier = -0.25 },  -- over 120%: -25%
}

-- Cargo integrity modifiers
Economy.IntegrityModifiers = {
    { minPct = 90, modifier = 0.00  },
    { minPct = 70, modifier = -0.10 },
    { minPct = 50, modifier = -0.25 },
    { minPct = 0,  modifier = -1.00 }, -- rejected
}
Economy.IntegrityRejectionThreshold = 40

-- Compliance bonuses (stackable)
Economy.ComplianceBonuses = {
    weigh_station       = 0.05,
    seal_intact         = 0.05,
    clean_bol           = 0.05,
    pre_trip            = 0.03,
    manifest_verified   = 0.03,
    shipper_rep_t2      = 0.05,  -- Established
    shipper_rep_t3      = 0.10,  -- Trusted
    shipper_rep_t4      = 0.15,  -- Preferred
    cold_chain_clean    = 0.05,
    livestock_excellent = 0.10,
    convoy_2            = 0.08,
    convoy_3            = 0.12,
    convoy_4plus        = 0.15,
}
Economy.MaxComplianceStack = 0.36

-- Multi-stop premium
Economy.MultiStopPremium = {
    [2] = 0.15,
    [3] = 0.25,
    [4] = 0.35,
    [5] = 0.45,
    [6] = 0.55,  -- cap
}
Economy.LTLFlatPerStop = 150

-- Temperature excursion payout impact
Economy.ExcursionPenalties = {
    minor       = 0.00,  -- under 5 min: no penalty
    significant = -0.15, -- 5-15 min: -15%
    critical    = -0.35, -- over 15 min: -35%
}

-- Welfare multipliers
Economy.WelfareMultipliers = {
    [5] = 0.20,   -- Excellent: +20%
    [4] = 0.10,   -- Good: +10%
    [3] = 0.00,   -- Fair: base
    [2] = -0.15,  -- Poor: -15%
    [1] = -0.40,  -- Critical: -40%
}

-- Insurance
Economy.InsuranceSingleLoadRate = 0.08  -- 8% of load value
Economy.InsuranceDayRates = {
    [0] = 200,
    [1] = 450,
    [2] = 900,
    [3] = 1800,
}
Economy.InsuranceWeekRates = {
    [0] = 1000,
    [1] = 2500,
    [2] = 5000,
    [3] = 9500,
}
Economy.ClaimPayoutMultiplier = 2  -- deposit × 2 + premium
```

### 5.3 config/shippers.lua (excerpt)

```lua
Shippers = {}

Shippers['port_of_ls'] = {
    label       = 'Port of Los Santos Freight Authority',
    region      = 'los_santos',
    tier_range  = {0, 2},
    cluster     = 'industrial',
    coords      = vector3(-16.3, -1441.0, 30.0),  -- placeholder
}

Shippers['vangelico'] = {
    label       = 'Vangelico Fine Goods',
    region      = 'los_santos',
    tier_range  = {1, 3},
    cluster     = 'luxury',
    coords      = vector3(-630.0, -237.0, 38.0),  -- placeholder
    cert_required = 'high_value',
}

Shippers['bilkington'] = {
    label       = 'Bilkington Research',
    region      = 'los_santos',
    tier_range  = {2, 3},
    cluster     = 'government',
    coords      = vector3(297.0, -584.0, 43.0),   -- placeholder
    cert_required = 'bilkington_carrier',
}

Shippers['ron_petroleum'] = {
    label       = 'RON Petroleum',
    region      = 'sandy_shores',
    tier_range  = {1, 2},
    cluster     = 'industrial',
    coords      = vector3(1698.0, 3786.0, 34.0),  -- placeholder
}

Shippers['grapeseed_collective'] = {
    label       = 'Grapeseed Agricultural Collective',
    region      = 'grapeseed',
    tier_range  = {0, 2},
    cluster     = 'agricultural',
    coords      = vector3(1693.0, 4925.0, 42.0),  -- placeholder
}

-- Full list: maze_bank, fleeca_distribution, alamo_industrial,
-- blaine_livestock, paleto_lumber, humane_labs_cold,
-- blaine_growers, cliffford_agrochem, brute_equipment,
-- lsia_freight, san_andreas_national_guard, fib_logistics
```

### 5.4 config/cargo.lua (excerpt)

```lua
CargoTypes = {}

CargoTypes['light_general_freight'] = {
    tier                = 0,
    rate_modifier_key   = 'light_general_freight',
    integrity_profile   = 'forgiving',  -- max 1-8% per event
    temp_required       = false,
    seal_required       = false,
    vehicle_types       = {'van','sprinter','pickup','box_small'},
    weight_range        = {500, 5000},
    leon_available      = true,
}

CargoTypes['cold_chain'] = {
    tier                = 2,
    rate_modifier_key   = 'cold_chain',
    integrity_profile   = 'standard',
    temp_required       = true,
    temp_min            = 34,
    temp_max            = 40,
    seal_required       = true,
    vehicle_types       = {'class_a_reefer'},
    weight_range        = {10000, 44000},
    reefer_required     = true,
    cert_required       = nil,
    leon_supplier       = 'vespucci_cold_chain',
}

CargoTypes['fuel_tanker'] = {
    tier                = 2,
    rate_modifier_key   = 'fuel_tanker',
    integrity_profile   = 'liquid',
    temp_required       = false,
    seal_required       = true,
    vehicle_types       = {'tanker_fuel'},
    weight_range        = {35000, 80000},
    tanker_required     = true,
    endorsement_required = 'tanker',
    is_flammable        = true,
    capacity_gallons    = 9500,
    explosion_profile   = 'fuel_tanker_full',
    drain_enabled       = true,
    drain_item          = 'stolen_fuel',
    drain_container     = 'fuel_drum',
}

CargoTypes['pharmaceutical'] = {
    tier                = 3,
    rate_modifier_key   = 'pharmaceutical',
    integrity_profile   = 'strict',
    temp_required       = true,
    temp_min            = 36,
    temp_max            = 46,
    seal_required       = true,
    vehicle_types       = {'class_a_reefer'},
    weight_range        = {5000, 20000},
    reefer_required     = true,
    cert_required       = 'bilkington_carrier',
    reefer_health_threshold = 80,
    leon_supplier       = 'vespucci_cold_chain',
}

-- Full list: food_beverage_small, retail_small, courier,
-- general_freight_full, building_materials, food_beverage_reefer,
-- retail_full, liquid_bulk_food, liquid_bulk_industrial,
-- livestock, oversized, hazmat (per class), high_value, military
```

---

## 6. CORE SYSTEMS

### 6.1 Load Lifecycle

```
GENERATED → AVAILABLE → RESERVED → ACCEPTED → IN_TRANSIT → DELIVERED
                                                         ↘ STOLEN
                                                         ↘ ABANDONED
                                                         ↘ EXPIRED
                                       ↘ ORPHANED (driver disconnects)
```

**Generation:** Server generates loads on board refresh. Loads are written to `truck_loads` with `board_status = 'available'`. Load count per region per tier set in `config/board.lua`.

**Reservation:** Player taps load detail — server sets `reserved_by` and `reserved_until` (+180 seconds). Other players cannot accept during hold. Reservation expires automatically via maintenance query.

**Acceptance:** Player confirms → server validates requirements (CDL, certification, insurance, deposit balance) → deposit deducted → `truck_active_loads` row created → `truck_bols` row created → physical BOL item added to player inventory → load status set to `accepted`.

**In transit:** Client monitors vehicle health, integrity, temperature, seal. Server updates `truck_active_loads` on each significant event.

**Delivery:** Player arrives at destination zone → NPC interaction → server calculates final payout → deposit returned → payout issued → `truck_bols` updated → `truck_active_loads` deleted → reputation updated → shipper reputation updated.

### 6.2 Payout Calculation

```lua
-- server/payout.lua
function CalculatePayout(activeLoad, bolRecord, deliveryData)
    local cargo    = CargoTypes[bolRecord.cargo_type]
    local shipper  = Shippers[bolRecord.shipper_id]
    local tier     = bolRecord.tier
    local distance = bolRecord.distance_miles

    -- Step 1: Base
    local baseRate = Economy.BaseRates[tier]
                   * Economy.CargoRateModifiers[cargo.rate_modifier_key]
    local base     = baseRate * distance

    -- Step 2: Multi-stop premium
    if activeLoad.stop_count > 1 then
        local stopPremium = Economy.MultiStopPremium[
            math.min(activeLoad.stop_count, 6)
        ] or 0.55
        base = base * (1 + stopPremium)
        -- LTL flat
        base = base + (Economy.LTLFlatPerStop * activeLoad.stop_count)
    end

    -- Step 3: Weight multiplier
    local weightMult = GetWeightMultiplier(bolRecord.weight_lbs)
    base = base * weightMult

    -- Step 4: Owner-op bonus
    if not activeLoad.is_rental then
        base = base * (1 + Economy.OwnerOpBonus[tier])
    end

    -- Step 5: Time performance
    local windowSeconds = activeLoad.window_expires_at - activeLoad.accepted_at
    local actualSeconds = deliveryData.delivered_at - activeLoad.accepted_at
    local timePct = actualSeconds / windowSeconds
    local timeModifier = GetTimeModifier(timePct)
    base = base * (1 + timeModifier)

    -- Step 6: Integrity
    local integrity = activeLoad.cargo_integrity
    if integrity < Config.IntegrityRejectionThreshold then
        return 0, 'rejected'  -- load refused entirely
    end
    local integrityMod = GetIntegrityModifier(integrity)
    base = base * (1 + integrityMod)

    -- Step 7: Temperature
    if bolRecord.temp_compliance ~= 'not_required' then
        local tempMod = Economy.ExcursionPenalties[
            bolRecord.temp_compliance == 'clean' and 'minor'
            or bolRecord.temp_compliance
        ] or 0
        base = base * (1 + tempMod)
    end

    -- Step 8: Welfare (livestock)
    if activeLoad.welfare_rating then
        base = base * (1 + (Economy.WelfareMultipliers[activeLoad.welfare_rating] or 0))
    end

    -- Step 9: Compliance bonuses
    local complianceTotal = 0
    local bonuses = {}

    if activeLoad.weigh_station_stamped then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.weigh_station
        table.insert(bonuses, 'weigh_station')
    end
    if activeLoad.seal_status == 'sealed' then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.seal_intact
        table.insert(bonuses, 'seal_intact')
    end
    if not bolRecord.cdl_mismatch then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.clean_bol
        table.insert(bonuses, 'clean_bol')
    end
    if activeLoad.pre_trip_completed then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.pre_trip
        table.insert(bonuses, 'pre_trip')
    end
    if activeLoad.manifest_verified then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.manifest_verified
        table.insert(bonuses, 'manifest_verified')
    end

    -- Shipper rep bonus
    local shipperRep = GetShipperRepTier(bolRecord.citizenid, bolRecord.shipper_id)
    if shipperRep == 'established' then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.shipper_rep_t2
    elseif shipperRep == 'trusted' then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.shipper_rep_t3
    elseif shipperRep == 'preferred' then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.shipper_rep_t4
    end

    -- Cold chain and livestock bonuses
    if bolRecord.temp_compliance == 'clean' then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.cold_chain_clean
    end
    if activeLoad.welfare_rating == 5 then
        complianceTotal = complianceTotal + Economy.ComplianceBonuses.livestock_excellent
    end

    -- Convoy bonus
    if activeLoad.convoy_id then
        local convoySize = GetConvoySize(activeLoad.convoy_id)
        local convoyBonus = convoySize >= 4 and Economy.ComplianceBonuses.convoy_4plus
                          or convoySize == 3 and Economy.ComplianceBonuses.convoy_3
                          or Economy.ComplianceBonuses.convoy_2
        complianceTotal = complianceTotal + convoyBonus
    end

    -- Cap compliance
    complianceTotal = math.min(complianceTotal, Economy.MaxComplianceStack)
    base = base * (1 + complianceTotal)

    -- Step 10: Floor
    local floor = Config.PayoutFloors[tier]
    local final = math.max(math.floor(base), floor)

    return final, 'success', {
        base_rate       = baseRate,
        distance        = distance,
        weight_mult     = weightMult,
        owner_op        = not activeLoad.is_rental,
        time_mod        = timeModifier,
        integrity_mod   = integrityMod,
        compliance      = complianceTotal,
        bonuses_earned  = bonuses,
        floor_applied   = final == floor,
    }
end
```

---

## 7. CARGO TIER REFERENCE

### Tier 0 — No CDL

| ID | Cargo Type | Vehicle | Rate | Deposit |
|----|-----------|---------|------|---------|
| T0-01 | Light General Freight | Van/Sprinter/Pickup | $35/mi | $300 flat |
| T0-02 | Small Food & Beverage | Van/Sprinter | $35/mi | $300 flat |
| T0-03 | Small Retail Goods | Van/Sprinter | $35/mi | $300 flat |
| T0-04 | Small Package / Courier | Van/Sprinter/Moto | $35/mi | $300 flat |

### Tier 1 — Class B CDL

| ID | Cargo Type | Vehicle | Rate | Deposit |
|----|-----------|---------|------|---------|
| T1-01 | General Freight Full | Benson/Flatbed | $55/mi | 15% |
| T1-02 | Building Materials | Flatbed/Tipper | $55/mi | 15% |
| T1-03 | Food & Beverage Full | Benson/Benson Reefer | $55-60/mi | 15% |
| T1-04 | Retail Goods Full | Benson (enclosed only) | $55/mi | 15% |

### Tier 2 — Class A CDL

| ID | Cargo Type | Vehicle | Rate | Deposit |
|----|-----------|---------|------|---------|
| T2-01 | Refrigerated / Cold Chain | Class A Reefer | $90/mi | 20% |
| T2-02 | Fuel Tanker | Brute Tanker | $92/mi | 20% |
| T2-03 | Liquid Bulk Non-Fuel | Food/Chemical Tanker | $85-88/mi | 20% |
| T2-04 | Livestock | Livestock Trailer | $88/mi | 20% |
| T2-05 | Oversized Equipment | Lowboy/Step-deck | $95/mi | 20% |

### Tier 3 — Class A + Endorsement

| ID | Cargo Type | Vehicle | Rate | Endorsement | Deposit |
|----|-----------|---------|------|------------|---------|
| T3-01 | Pharmaceutical | Class A Reefer | $135-150/mi | Bilkington Cert | 25% |
| T3-02 | Hazmat / Chemical | Hazmat-rated | $140-165/mi | HAZMAT | 25% |
| T3-03 | High-Value Goods | Class A Enclosed | $145/mi | High-Value Cert | 25% |
| T3-05 | Military / Government | Varies | $175/mi | Gov Clearance | 25% |

---

## 8. PAYOUT ENGINE

*See Section 6.2 for full implementation.*

**Board composition per region:**
- Tier 0: 4 loads
- Tier 1: 4 loads
- Tier 2: 3 loads
- Tier 3: 2 loads (gated by certification)
- Supplier contracts: 3 per region
- Routes: 2 per region
- Open contracts: 2 server-wide

**Refresh schedule (staggered):**
- Los Santos: every 2 hours at :00
- Sandy Shores: offset +30 min
- Paleto: offset +15 min
- Grapeseed: offset +45 min

---

## 9. CDL AND CERTIFICATION SYSTEM

### 9.1 License Progression

```
No license → Tier 0 access only
Class B CDL → Tier 0 + Tier 1
Class A CDL → All tiers (endorsements still required)
Tanker Endorsement → Fuel tanker + liquid bulk
HAZMAT Endorsement → Hazmat cargo
Oversized Monthly Permit → Oversized loads
Bilkington Carrier Cert → Pharmaceutical loads
High-Value Cert → High-value goods
Government Clearance → Military / government loads
```

### 9.2 Written Tests

**Class B:** 10 questions from 40-question pool. 80% pass. $150 fee. 3-fail lockout 1 hour. No retake cooldown.

**Class A:** 10 questions from 40-question pool. 80% pass. $300 fee. Same lockout.

**Tanker Endorsement:** 15 questions from specialized pool. 80% pass. $500 fee.

**HAZMAT Endorsement:** Briefing only (5-topic narrative). $750 fee + $500 background check. No pass/fail — completion grants endorsement.

**Test question pools:** Defined in `config/cdl.lua`. Each entry: `{ question, options = {a,b,c,d}, correct = 'b' }`. Comedy-adjacent tone, observational humor, accurate content.

### 9.3 CDL Tutorial (Class A Practical)

The Class A practical exam serves as the trucking script onboarding tutorial.

**Stage 1 — Pre-Trip Inspection**
Teaches: pre-trip mechanic, vehicle health awareness.
5 checkpoints, forgiving, no failure. 
Duration: ~3 minutes.

**Stage 2 — Coupling**
Teaches: trailer coupling, seal application, cargo securing.
Generous coupling zone, 5 attempts, 3 strap points.
Duration: ~4 minutes.

**Stage 3 — City Navigation**
Teaches: manifest verification, urban driving, CDL awareness.
LSIA → Industrial, 1.5 mi. No speeding/lights/curbs.
Duration: ~5 minutes.

**Stage 4 — Highway Run**
Teaches: weight multipliers, delivery windows, HUD introduction.
Industrial → Route 1 Harmony, 4 mi.
Duration: ~6 minutes.

**Stage 5 — Backing and Dock**
Teaches: dock delivery, BOL signing, payout display.
5 backing attempts. Real $850 payout on completion.
Duration: ~4 minutes.

**Total time:** ~20 minutes. Class A CDL issued on completion.

**Standalone path:** Resource `player-licensing` registers stage definitions. Trucking script provides CDL stage implementations. Other scripts register motorcycle/pilot/maritime stages. Licensing resource is the framework only.

### 9.4 Certifications

**Bilkington Carrier Certification:**
- Class A CDL active
- 10+ cold chain deliveries
- No critical excursions in last 5 cold chain deliveries
- No violations in 14 days
- Fee: included in LSDOT application
- Valid: 30 days, renewable with clean record
- Vehicle threshold raised to 80% health for pharmaceutical loads

**High-Value Certification:**
- Class A CDL active
- 7-day clean record
- No theft claims in 30 days
- Background fee: $1,000
- NPC interview at Vangelico HQ — 5 questions, 4/5 required
- Valid: 30 days

**Government Clearance:**
- Class A CDL + High-Value Cert both active
- 30-day clean record (zero violations)
- Tier 3 reputation with 3+ different shippers
- Application fee: $5,000
- Issued instantly on meeting all requirements
- Any violation: 30-day clean record reset required

---

## 10. COMPANY AND DISPATCHER SYSTEM

### 10.1 Structure

Three roles: Owner, Dispatcher, Driver.

**Owner:** Creates company, invites/removes members, assigns dispatcher role, sees all active loads, receives completion notifications.

**Dispatcher:** Monitors all active driver loads in real time. Assigns board loads to drivers. Initiates convoy formation. Authorizes load transfers. Cannot drive loads while in dispatch mode.

**Driver:** Accepts assigned loads. Participates in convoys. Sees company drivers' active status.

### 10.2 Dispatcher Mode

```lua
-- client/company.lua
RegisterNetEvent('trucking:client:enableDispatchMode', function()
    DispatchModeActive = true
    -- Open dispatcher tablet UI
    -- Cannot accept loads while active
    TriggerEvent('trucking:client:openDispatcherUI')
end)

-- Dispatcher assigns load to driver
RegisterNetEvent('trucking:client:assignLoad', function(loadId, targetCitizenId)
    TriggerServerEvent('trucking:server:assignLoadToDriver', loadId, targetCitizenId)
end)

-- Driver receives assignment notification
RegisterNetEvent('trucking:client:loadAssigned', function(loadData, dispatcherName)
    lib.alertDialog({
        header = 'Dispatch Assignment',
        content = string.format('%s has assigned you a load.\n%s — %s\n%s mi',
            dispatcherName, loadData.cargo_type, 
            loadData.destination_label, loadData.distance_miles),
        cancel  = true,
    }, function(confirmed)
        if confirmed then
            TriggerServerEvent('trucking:server:acceptAssignment', loadData.load_id)
        end
    end)
end)
```

### 10.3 Load Transfer Between Company Drivers

Both drivers within 15m of trailer. Driver A initiates transfer. Driver B accepts. BOL updates instantly. Seal remains intact. Payout splits by distance driven.

```lua
-- server/missions.lua
RegisterNetEvent('trucking:server:initiateTransfer', function(targetCitizenId)
    local src = source
    local driver = GetPlayerBySource(src)
    local activeLoad = GetActiveLoad(driver.citizenid)

    -- Validate both in same company
    -- Validate within 15m (client checks coords, server validates)
    -- Calculate split ratio
    local driverDistance = activeLoad.departed_at 
        and CalculateDistanceTraveled(activeLoad)
        or 0
    local remainingDistance = activeLoad.load.distance_miles - driverDistance
    
    -- Notify target driver
    TriggerClientEvent('trucking:client:transferOffer', 
        GetPlayerSource(targetCitizenId),
        { 
            from        = driver.citizenid,
            fromName    = driver.name,
            activeLoad  = activeLoad,
            splitRatio  = {
                from = driverDistance / activeLoad.load.distance_miles,
                to   = remainingDistance / activeLoad.load.distance_miles,
            }
        }
    )
end)
```

---

## 11. CONVOY SYSTEM

### 11.1 Formation

Any driver can initiate. Company or solo. Minimum 2, maximum 6 (configurable).

```lua
-- server/convoy.lua
RegisterNetEvent('trucking:server:createConvoy', function(convoyType)
    local src = source
    local citizenid = GetCitizenId(src)
    
    local convoyId = MySQL.insert.await(
        'INSERT INTO truck_convoys (initiated_by, convoy_type, created_at) VALUES (?,?,?)',
        { citizenid, convoyType, os.time() }
    )
    
    -- Notify region players if open convoy
    if convoyType == 'open' then
        NotifyRegionPlayers(citizenid, convoyId)
    end
    
    return convoyId
end)
```

### 11.2 Payout Bonus

Convoy bonus applied at delivery if all vehicles arrive within 15 minutes of each other.

```lua
-- In CalculatePayout — Step 9 compliance bonuses
if activeLoad.convoy_id then
    local allArrived = CheckConvoyArrivalWindow(activeLoad.convoy_id, 900) -- 15 min
    if allArrived then
        local convoySize = GetConvoySize(activeLoad.convoy_id)
        -- bonus applied as shown in economy.lua
    end
end
```

### 11.3 HUD

Minimal convoy overlay alongside active load HUD. Shows each convoy member's distance from convoy lead. Updated every 5 seconds. No enforced formation.

---

## 12. JOB BOARD

### 12.1 Board Behavior

**Standard loads:** Posted on refresh. First-come-first-served with 3-minute reservation hold. Load counts per region in `config/board.lua`.

**Reservation abuse:** Track consecutive releases in `truck_drivers.reservation_releases`. 5 consecutive releases → 10-minute cooldown on Tier 2+ reservations.

**Surge pricing:** `truck_surge_events` checked at every board load. Surge percentage added to payout estimate display. Triggers defined in Section 12.2.

**Expiry:** Unclaimed loads expire at board refresh. Accepted loads with expired windows enter orphan state.

### 12.2 Surge Triggers

| Trigger | Effect | Duration |
|---------|--------|----------|
| Open contract >50% filled | +20% on related cargo | Until contract closes |
| Multiple robberies same corridor | +25% danger premium | 2 hours |
| Cold chain delivery failures ×3 | +30% reefer loads that region | Until 3 successful reefer deliveries |
| Server peak population | +10% all tiers | During peak |
| Shipper backlog (no deliveries 4+ hours) | +35% that shipper | Until delivery |

### 12.3 Board Composition (config/board.lua)

```lua
BoardConfig = {}

BoardConfig.StandardLoads = {
    los_santos   = { [0]=4, [1]=4, [2]=3, [3]=2 },
    sandy_shores = { [0]=4, [1]=4, [2]=3, [3]=2 },
    paleto       = { [0]=4, [1]=3, [2]=2, [3]=1 },
    grapeseed    = { [0]=4, [1]=3, [2]=2, [3]=1 },
}

BoardConfig.SupplierContracts    = 3   -- per region
BoardConfig.Routes               = 2   -- per region
BoardConfig.OpenContracts        = 2   -- server-wide

BoardConfig.RefreshOffsets = {   -- seconds offset from hour
    los_santos   = 0,
    sandy_shores = 1800,
    paleto       = 900,
    grapeseed    = 2700,
}

BoardConfig.LoadExpirySeconds    = 7200   -- 2 hours
BoardConfig.RouteExpirySeconds   = 21800  -- 6 hours
BoardConfig.SupplierExpiryHours  = { 4, 6, 8 }  -- random range
```

---

## 13. BOL SYSTEM

### 13.1 BOL Item

Physical ox_inventory item: `trucking_bol`. Metadata contains the BOL number. Player carries it in inventory. Required for insurance claims. Never auto-removed — player disposes manually.

```lua
-- On load acceptance
exports.ox_inventory:addItem(src, 'trucking_bol', 1, {
    bol_number  = bolNumber,
    cargo_type  = cargoType,
    shipper     = shipperName,
    destination = destinationLabel,
    issued_at   = os.time(),
})
```

### 13.2 BOL States

```
ACTIVE        — Load in progress
DELIVERED     — Successful delivery
REJECTED      — Integrity too low, refused at destination
STOLEN        — Load taken by robbery
ABANDONED     — Driver left load / disconnected
EXPIRED       — Window closed without delivery
PARTIAL       — Multi-stop with incomplete stops
```

### 13.3 BOL Event Logging

Every significant state change appends a row to `truck_bol_events`. This is the audit trail for disputes, insurance claims, and trooper interactions. Never deleted.

---

## 14. SEAL SYSTEM

### 14.1 Simplified Binary Seal

The seal is either SEALED or BROKEN. No tiers. No approved zones.

**Applied:** At trailer coupling at origin.

**Broken when:**
- Trailer decoupled outside active load transfer
- Cargo accessed via bolt cutters (robbery)
- Trailer abandoned 10+ minutes

**Consequence of break (one outcome):**
- BOL flagged SEAL BROKEN
- +5% seal compliance bonus lost
- Shipper reputation: -20 points
- Police script notification (low priority)

### 14.2 Authorized Transfer

Both drivers within 15m → Driver A initiates → Driver B accepts → BOL updates → seal remains intact → payout splits by distance.

### 14.3 Client Detection

```lua
-- client/seals.lua
local sealCheckInterval = nil

function StartSealMonitoring(activeLoad)
    if not activeLoad.seal_status == 'sealed' then return end
    
    sealCheckInterval = SetInterval(function()
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        local trailer = GetVehicleTrailerVehicle(vehicle)
        
        -- Check if trailer is still coupled
        if not trailer or trailer == 0 then
            if activeLoad.status == 'in_transit' then
                -- Trailer decoupled without transfer authorization
                TriggerServerEvent('trucking:server:sealBreak', 
                    activeLoad.bol_id, 'unauthorized_decouple')
            end
        end
        
        -- Check abandonment (vehicle stationary 10+ minutes)
        if IsVehicleStationary(vehicle) then
            if not abandonmentTimer then
                abandonmentTimer = os.time()
            elseif (os.time() - abandonmentTimer) > 600 then
                TriggerServerEvent('trucking:server:loadAbandoned', activeLoad.bol_id)
            end
        else
            abandonmentTimer = nil
        end
    end, 5000)
end
```

---

## 15. TEMPERATURE MONITORING

### 15.1 Two States Only

IN RANGE or OUT OF RANGE. Single temperature range per load shown on BOL.

**Excursion triggers:**
- Vehicle health drops below threshold (65% standard, 80% pharmaceutical)
- Engine off > 5 minutes

**Reefer restoration:**
Vehicle repaired above health threshold → reefer restores automatically.

### 15.2 Excursion Consequences

| Duration | Payout Impact | BOL Record |
|---------|---------------|------------|
| Resolved in < 5 min | None | clean |
| 5–15 minutes | -15% | minor_excursion |
| 15+ minutes | -35% | significant_excursion |

### 15.3 Client Detection

```lua
-- client/temperature.lua
local excursionStart = nil

function UpdateTemperatureState(activeLoad)
    -- Check reefer operational (vehicle health)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    local health = GetEntityHealth(vehicle)
    local threshold = activeLoad.pharma and 
        Config.PharmaHealthThreshold or Config.ReeferHealthThreshold
    
    local reeferOk = health >= threshold
    
    if not reeferOk and not excursionStart then
        excursionStart = os.time()
        TriggerServerEvent('trucking:server:excursionStart', activeLoad.bol_id)
        lib.notify({ 
            title = 'Reefer Fault', 
            description = 'Temperature control lost. Vehicle requires service.',
            type = 'error' 
        })
    elseif reeferOk and excursionStart then
        local duration = os.time() - excursionStart
        excursionStart = nil
        TriggerServerEvent('trucking:server:excursionEnd', activeLoad.bol_id, duration)
    end
    
    -- Engine off check
    if not GetIsVehicleEngineRunning(vehicle) then
        if not engineOffTime then
            engineOffTime = os.time()
        elseif (os.time() - engineOffTime) > 300 then
            -- 5 minutes engine off — trigger excursion
            if not excursionStart then
                excursionStart = os.time()
                TriggerServerEvent('trucking:server:excursionStart', 
                    activeLoad.bol_id, 'engine_off')
            end
        end
    else
        engineOffTime = nil
    end
end
```

---

## 16. LIVESTOCK WELFARE

### 16.1 Welfare Rating (1–5 stars)

Replaces cargo integrity for livestock hauls. Final rating determines payout multiplier.

### 16.2 Events That Change Welfare

| Event | Change |
|-------|--------|
| Hard braking | -1 |
| Sharp corner > 35mph | -1 |
| Major collision | -2 |
| Off-road driving | -1 per minute |
| Heat (Sandy Shores idle) | -1 per 10 min |
| Smooth driving | passive recovery +0.25/10 min |
| Rest stop (quick, 2 min) | +0.5 |
| Rest stop (water, 8 min) | +1.0 |
| Rest stop (full, 15 min) | +1.5 |
| Transit time 30-60 min | -0.25 per 30 min |
| Transit time 60-90 min | -0.5 per 30 min |
| Transit time 90+ min | -1.0 per 30 min |

### 16.3 Rest Stop Interaction

ox_lib progressBar hold interaction at any designated truck stop:

```lua
lib.progressBar({
    duration = 480000, -- 8 minutes for water stop
    label    = 'Water and rest stop',
    canCancel = true,
}, function(cancelled)
    if not cancelled then
        TriggerServerEvent('trucking:server:livestockRestStop', 
            activeLoad.bol_id, 'water')
    end
end)
```

---

## 17. CARGO SECURING

Flatbed and oversized loads require securing before departure.

**Standard flatbed (T1-02):** 3 strap points × 4 seconds = 12 seconds minimum.

**Oversized (T2-05):** 4 strap points × 4 seconds + wheel chock check (wheeled equipment).

**Implementation:** ox_lib progressBar hold interaction at each strap point. Each point must complete before the next is available. Departure GPS not set until all points complete. Skipping causes BOL flag: cargo not secured, seal not applied.

---

## 18. WEIGH STATION SYSTEM

### 18.1 Locations

- Route 1 Pacific Bluffs
- Route 68 near Harmony  
- Paleto Bay highway entrance

### 18.2 Mechanics

**Optional for Tier 0–1.** Mandatory routing for Tier 2–3 regulated cargo (GPS auto-routes through them).

**Interaction:** Driver pulls into scale pad zone → ox_lib zone trigger → NPC inspection sequence → BOL reviewed → stamp issued → +5% compliance bonus.

**For HAZMAT and cold chain:** Inspector checks placard field on BOL (HAZMAT) or temperature compliance field (cold chain). Minor excursion noted in record but not penalized retroactively.

**Weigh station stamp:** Sets `weigh_station_stamped = true` on `truck_active_loads`. Recorded as `weigh_station_stamp = true` on final BOL.

---

## 19. INSURANCE SYSTEM

### 19.1 Policy Types

| Type | Cost | Coverage |
|------|------|----------|
| Single Load | 8% of load value | Next accepted load only |
| Day Policy | $200–$1,800 by tier | All loads for 24 hours |
| Week Policy | $1,000–$9,500 by tier | All loads for 7 days |

Purchased at any dispatch desk or via app. Hard block on load acceptance if no active policy.

### 19.2 Coverage

Insurance covers: cargo theft, load abandonment.

Insurance does NOT cover: time penalties, CDL mismatch violations, integrity degradation, Leon loads.

### 19.3 Claim Process

1. Driver takes physical BOL item to Vapid Commercial Insurance office
2. Selects BOL from ox_inventory in NPC interaction
3. Server verifies: BOL = undelivered load, policy was active at load acceptance, deposit was forfeited
4. All checks pass → claim approved → payout queued 15 minutes → bank deposit
5. Any check fails → denied, no reason given

**Payout formula:** `(Deposit × 2) + Premium Paid`

### 19.4 Server Implementation

```lua
-- server/insurance.lua

function VerifyAndApproveClaim(citizenid, bolNumber)
    -- Fetch BOL
    local bol = MySQL.scalar.await(
        'SELECT * FROM truck_bols WHERE bol_number = ? AND citizenid = ?',
        { bolNumber, citizenid }
    )
    if not bol then return false, 'bol_not_found' end
    if bol.bol_status ~= 'stolen' and bol.bol_status ~= 'abandoned' then
        return false, 'load_not_eligible'
    end
    if not bol.item_in_inventory then return false, 'bol_not_in_inventory' end

    -- Fetch deposit
    local deposit = MySQL.scalar.await(
        'SELECT * FROM truck_deposits WHERE bol_id = ? AND status = ?',
        { bol.id, 'forfeited' }
    )
    if not deposit then return false, 'deposit_not_forfeited' end

    -- Fetch policy
    local policy = MySQL.scalar.await([[
        SELECT * FROM truck_insurance_policies 
        WHERE citizenid = ? AND status = 'active'
        AND valid_from <= ? 
        AND (valid_until IS NULL OR valid_until >= ?)
    ]], { citizenid, bol.issued_at, bol.issued_at })
    if not policy then return false, 'no_policy_at_time' end

    -- Calculate payout
    local premiumAllocated = policy.policy_type == 'single_load' and
        policy.premium_paid or
        math.floor(policy.premium_paid / 10) -- proportional day/week allocation
    local claimAmount = (deposit.amount * Config.ClaimPayoutMultiplier) 
        + premiumAllocated

    -- Create claim record
    local claimId = MySQL.insert.await([[
        INSERT INTO truck_insurance_claims 
        (citizenid, policy_id, bol_id, bol_number, claim_type,
         deposit_amount, premium_allocated, claim_amount, status, 
         payout_at, filed_at)
        VALUES (?,?,?,?,?,?,?,?,'approved',?,?)
    ]], {
        citizenid, policy.id, bol.id, bolNumber,
        bol.bol_status == 'stolen' and 'theft' or 'abandonment',
        deposit.amount, premiumAllocated, claimAmount,
        os.time() + 900,  -- 15 minute delay
        os.time()
    })

    return true, claimAmount
end

-- Scheduled check every minute
CreateThread(function()
    while true do
        Wait(60000)
        local pendingClaims = MySQL.query.await([[
            SELECT ic.*, b.citizenid FROM truck_insurance_claims ic
            JOIN truck_bols b ON ic.bol_id = b.id
            WHERE ic.status = 'approved' AND ic.payout_at <= ?
        ]], { os.time() })
        
        for _, claim in ipairs(pendingClaims) do
            -- Issue payout via QBox banking
            TriggerEvent('qb-banking:server:addMoney', 
                claim.citizenid, claim.claim_amount, 'Insurance claim payout')
            
            MySQL.update.await(
                'UPDATE truck_insurance_claims SET status = ?, resolved_at = ? WHERE id = ?',
                { 'paid', os.time(), claim.id }
            )
            
            -- Notify player if online
            local playerSrc = GetPlayerByIdentifier(claim.citizenid)
            if playerSrc then
                TriggerClientEvent('trucking:client:claimPaid', playerSrc, claim.claim_amount)
            end
        end
    end
end)
```

---

## 20. REPUTATION SYSTEMS

### 20.1 Driver Reputation Score

Global score tracking professional standing. Affects board access tier.

| Score | Tier | Board Access |
|-------|------|-------------|
| 1000 | Elite | Full + early government contracts |
| 800+ | Professional | Full board + cross-region view |
| 600+ | Established | Full board |
| 400+ | Developing | Tier 0–2 only |
| 200+ | Probationary | Tier 0–1 only |
| 1+ | Restricted | Tier 0 only |
| 0 | Suspended | 24-hour lockout |

**Reputation changes — failures:**

| Event | T0 | T1 | T2 | T3 | Military |
|-------|----|----|----|----|---------|
| Robbery | -30 | -60 | -100 | -180 | -250 |
| Integrity fail | -20 | -40 | -70 | -120 | — |
| Abandonment | -25 | -50 | -90 | -160 | — |
| Window expired | -10 | -20 | -35 | -60 | — |
| Seal break | — | -15 | -30 | -55 | — |
| HAZMAT routing | — | — | — | -40 | — |

**Reputation changes — successes:**

| Event | Points |
|-------|--------|
| Tier 0 delivery | +8 |
| Tier 1 delivery | +15 |
| Tier 2 delivery | +25 |
| Tier 3 delivery | +40 |
| Military delivery | +60 |
| Full compliance bonus | +5 |
| Supplier contract | +20 |
| Cold chain clean | +8 |
| Livestock excellent | +10 |

### 20.2 Shipper Reputation

Per-driver, per-shipper. Five tiers.

| Tier | Points | Rate Bonus | Access |
|------|--------|------------|--------|
| Unknown | 0 | — | Standard loads |
| Familiar | 50+ | +5% | Priority queue |
| Established | 150+ | +10% | Tier 2 exclusives, urgent contact |
| Trusted | 350+ | +15% | All loads, surge advance notice |
| Preferred | 700+ | +20% | Exclusive loads (direct offer) |
| Blacklisted | 0 | — | No loads until reinstatement |

**Preferred decay:** 14 days inactive → drops to Trusted. Only tier that decays.

**Cluster friction:** Related shippers in same cluster (luxury, agricultural, industrial, government) share reputation signals. Damage with one = -10 to -15% progression rate with cluster partners.

---

## 21. CRIMINAL SYSTEMS — LEON AND SUPPLIERS

### 21.1 Leon Unlock

Automatic unlock after 15 Tier 3 deliveries. No fanfare. Leon is simply at his spot at 22:00 one night.

**Discovery:** Three optional approaches (dialogue-based). No script gates on which approach — players find him through server knowledge, word of mouth, or exploration.

**Hours:** 22:00–04:00 server time only.

### 21.2 Leon's Board

5 loads per refresh. Refreshes every 3 hours. All loads expire at 04:00 (dawn) regardless.

**Board shows:** Risk tier + fee only.

**Pay fee → Details revealed:**
- Pickup location
- Delivery location
- Vague cargo description
- Cash payout
- Window

**No BOL generated.** No seal. No GPS. Cash payout on arrival.

**Leon's milk rule:** Leon does not deal in dairy. If somehow presented with dairy-related criminal load opportunity, he declines.

### 21.3 Criminal Suppliers

Five suppliers accessible via Leon relationship progression:

| Supplier | Region | Rate | Risk | Unlock |
|---------|--------|------|------|--------|
| Chamberlain Distribution | Los Santos | 115% | Low | First Leon load |
| Ancelotti Freight Solutions | Los Santos | 130% | Medium | 3 Leon loads |
| Aztecas Agricultural Supply | Sandy Shores | 145% | High | HAZMAT endorsement req. |
| Vespucci Cold Chain | Paleto | 150% | Medium | Tier 3 cold chain rep |
| Jade River Import/Export | Grapeseed | 160% | Critical | 2 other suppliers done |

**Expansion hook:**
```lua
-- Any resource can register Leon load types
exports['trucking']:registerLeonLoadType({
    supplier_id     = 'my_supplier',
    label           = 'Custom Criminal Load',
    risk_tier       = 'medium',
    fee_range       = { 700, 1200 },
    payout_range    = { 4000, 8000 },
    -- Custom delivery logic handled by calling script
    delivery_event  = 'my_resource:criminalDelivery',
})
```

---

## 22. ROBBERY MECHANICS

### 22.1 Eligibility

- Tier 2/3 cargo only for full trailer steal
- Tier 1 cargo: on-site loot only, no trailer steal
- Load active 90+ seconds
- NOT within 200m of depot/weigh station/truck stop (safe zones)
- Robber cannot have active trucking mission

### 22.2 Required Items

| Item | Purpose | Source |
|------|---------|--------|
| `spike_strip` | Stop vehicle | Craftable / black market |
| `comms_jammer` | Block distress signal 3 min | Black market $800, single-use |
| `bolt_cutters` | Open standard trailer | Hardware / black market |
| `military_bolt_cutters` | Open military cargo | Rare black market |

### 22.3 On-Site Loot

Bolt cutters → skill check → doors open → cargo spawns as ox_inventory items. Carry weight applies. Multi-trip vehicle loading.

Items are flagged `stolen = true` in metadata. Existing server fence systems handle liquidation.

### 22.4 Full Trailer Steal

No additional script mechanics beyond driving to fence location. Trailer is a GTA vehicle — standard driving. Full trailer steal completes when fence location is reached. Server validates: active stolen load ≠ player actively delivering.

---

## 23. FUEL TANKER SYSTEMS

### 23.1 Realistic Capacity

- Standard tanker: 9,500 gallons
- Aviation tanker: 10,500 gallons
- At 55 gal/drum: 172 drums in a standard tanker

### 23.2 Drain Mechanic — Six Uses

**1. Robbery drain:** valve_wrench + fuel_hose + fuel_drum items. 30 sec/drum. Port stays open after crew leaves. Spill grows continuously.

**2. Self-refuel:** Driver drains ~50 gallons into personal tank. 60 seconds, fuel_hose only. BOL notes operational fuel use. No violation.

**3. Emergency roadside assistance:** Tanker driver drains into fuel_canister (5-gal item, 4 max capacity). Delivers to stranded vehicle. Player-to-player transaction.

**4. Fuel trap:** Intentional drain on road — no drums. Creates traction hazard. Ignition risk. Driver takes abandonment consequences + major rep hit.

**5. Property storage delivery:** If server supports player property fuel tanks — drain directly into property storage. Arranged player-to-player. Trucking script handles drain interaction, property script handles storage.

**6. Leon fuel diversion:** Partial drain at waypoint, deliver drums to Leon contact. Original load arrives short. BOL shows quantity discrepancy. Leon payout covers shortage and margin.

### 23.3 Spill Zone

Active spill creates an ox_lib zone. Any vehicle in zone: traction penalty applied via SetVehicleReduceGrip. Any fire source (gunshot, collision spark, explosion) within radius: ignition event → fire spreads → tanker explosion sequence.

No emergency valve. No intervention possible. When the fire reaches the tanker, the explosion sequence begins.

---

## 24. HAZMAT INCIDENT SYSTEM

### 24.1 Spill Events

Triggered on major collision with HAZMAT cargo or cargo integrity < 15%.

**Class 3 (flammable):** Fire risk, treated as fuel spill variant.

**Class 6 (toxic):** Persistent hazard zone. Continuous damage to players/vehicles inside. Requires cleanup kit.

**Class 7 (radioactive):** Radiation field. Geiger counter sound (native GTA). Wide damage-over-time radius. Requires specialized cleanup item.

**Class 8 (corrosive):** Vehicle structural damage in spill zone.

### 24.2 Cleanup

`hazmat_cleanup_kit` item (general). `hazmat_cleanup_specialist` item (class 7). 60-second interaction. Zone despawns on cleanup. Without cleanup, zone persists until server restart.

### 24.3 Emergency Notifications

HAZMAT incident fires to police script and fire script (if available) via configured exports:

```lua
exports[Config.PoliceResource]:dispatchAlert({
    type     = 'hazmat_incident',
    priority = 'high',
    location = incidentCoords,
    details  = string.format('HAZMAT Class %d incident', hazmatClass),
})
```

---

## 25. ENHANCED EXPLOSION SYSTEM

### 25.1 Cargo-Aware Explosion Profiles

System tracks any vehicle with active flammable cargo. Native explosion is intercepted and replaced with a multi-phase sequence.

Profiles defined in `config/explosions.lua`. Fuel tanker uses `fuel_tanker_full` profile (scales with fill level). HAZMAT cargo uses class-specific profiles.

### 25.2 Five-Phase Fuel Tanker Sequence

| Phase | Timing | Effect |
|-------|--------|--------|
| 1 — Initial ignition | 0 sec | Native vehicle explosion, base radius |
| 2 — Tank rupture | +2 sec | 3× native radius, vehicle launch |
| 3 — Pressure wave | +3 sec | Concussive only, max knockback |
| 4 — Fire column | +4 sec | Persistent fire zone 180 seconds |
| 5 — Secondary ignitions | +5–15 sec | Chain explosions in scorch zone |

Server visibility: smoke column visible across the map.

### 25.3 Vehicle Registration

```lua
-- Register any vehicle for enhanced explosion
exports['trucking']:registerFlammableVehicle(plate, {
    profile     = 'fuel_tanker_full',
    fill_level  = 0.85,
    cargo_type  = 'fuel_tanker',
})

-- Deregister on delivery or abandonment
exports['trucking']:deregisterFlammableVehicle(plate)
```

Other resources can register their own vehicles. This is the extraction path to standalone.

---

## 26. MILITARY HEIST

### 26.1 Contract Availability

2 military contracts maximum per server restart. Rare board posting outside normal refresh cycle. Only Government Clearance holders can accept.

**Contract classifications:**
- Equipment Transport — vehicle parts, field gear, no weapons guaranteed
- Armory Transfer — 1-2 automatic weapons probable
- Restricted Munitions — 3-5 automatic weapons confirmed

### 26.2 Convoy Composition

Lead escort (Military Patriot, armed NPC) → Cargo vehicle (player) → Trail escort (Military Patriot, armed NPC).

**Escort behavior:**
- Maintain formation at fixed speed
- After 60-second vehicle stop: investigate
- Engage hostiles attacking convoy
- Do not pursue beyond 500m from cargo vehicle
- Both escorts destroyed: 90-second unguarded window

### 26.3 Intelligence Phase

**Observation only.** No scanner mechanic. Military convoys follow predictable GPS-restricted routes. Players who watch learn the patterns.

**Long Con:** Government Clearance driver accepts legitimate contract. Provides route intelligence or stops convoy at predetermined point. Crew accesses cargo.

**Long Con consequences:**
- -400 reputation points
- Government Clearance suspended (30-day clean record to reinstate)
- All Tier 3 certs suspended 14 days
- Recoverable — not permanent

### 26.4 Cargo Items

```lua
MilitaryCargo = {
    equipment_transport = {
        { item='military_armor_vest',     weight=15, chance=0.70 },
        { item='military_ammunition_box', weight=20, chance=0.80 },
        { item='military_vehicle_parts',  weight=25, chance=0.60 },
        { item='military_pistol',         weight=5,  chance=0.50 },
    },
    armory_transfer = {
        -- All equipment items plus:
        { item='military_rifle',          weight=8,  chance=0.60 },
        { item='military_explosive_charge',weight=4, chance=0.30 },
        { item='classified_documents',    weight=1,  chance=0.10 },
    },
    restricted_munitions = {
        -- All above plus:
        { item='military_rifle_suppressed',weight=6, chance=0.40 },
        { item='military_lmg',            weight=12, chance=0.25 },
    },
}
```

### 26.5 Law Enforcement Dispatch

```lua
-- Fires on cargo breach (not on convoy stop)
exports[Config.PoliceResource]:dispatchAlert({
    type        = 'military_cargo_theft',
    priority    = 'high',
    location    = lastKnownCoords,
    description = 'Military contract cargo reported stolen',
})
```

---

## 27. NUI AND HUD

### 27.1 Chicago Bears Palette

```css
:root {
    --navy:         #0B1F45;
    --navy-dark:    #051229;
    --navy-mid:     #132E5C;
    --orange:       #C83803;
    --orange-dim:   #8A2702;
    --white:        #FFFFFF;
    --muted:        #A8B4C8;
    --border:       #1E3A6E;
    --success:      #2D7A3E;
    --warning:      #C87B03;
    --disabled:     #3A4A5C;
}
```

### 27.2 Typography

```css
@font-face {
    font-family: 'Barlow Condensed';
    font-weight: 700;
    src: url('fonts/BarlowCondensed-Bold.woff2');
}

body {
    font-family: 'Inter', sans-serif;
    font-size: 15px;
}
h1, h2, .label, .tier-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    letter-spacing: 0.05em;
    text-transform: uppercase;
}
.mono, .bol-number, .payout-figure {
    font-family: 'JetBrains Mono', monospace;
}
```

### 27.3 Dual Mode

```lua
-- config/config.lua
Config.UsePhoneApp      = false  -- lb-phone
Config.UseStandaloneNUI = true   -- standalone (F6)
```

Single codebase. Layout conditional at render time.

### 27.4 Screens

1. **Home** — Active load summary, standing, insurance status, nearby board summary
2. **Board** — Tabs: Standard / Supplier / Open / Routes. Filtered card list.
3. **Load Detail** — Route, cargo, payout breakdown (collapsible), requirements, accept buttons
4. **Active Load** — Destination, window, distance, live meters (temp/integrity), seal status, payout tracker
5. **Profile** — Credentials tab + Standings tab
6. **Insurance** — Policy status, purchase options, claim reminder
7. **Company** — Fleet status (owner/dispatcher), driver rows, active claims

### 27.5 Active Load HUD (In-World Overlay)

```
┌──────────────────────────────┐
│  BOL #2041  ·  Cold Chain    │
│  → Humane Labs  ·  16.8 mi   │
│  ⏱ 1:12:44  🌡 37°F ✓  94% │
└──────────────────────────────┘
```

Three lines. Thin #1E3A6E border normal, #C87B03 warning, #C83803 critical. Position: top-right corner.

### 27.6 NPC Conversation Component

Bottom-anchored panel. 580px fixed width. ox_lib scaffolding with full CSS override.

```css
.npc-panel {
    position: fixed;
    bottom: 40px;
    left: 50%;
    transform: translateX(-50%);
    width: 580px;
    background: var(--navy);
    border: 2px solid var(--orange);
    border-radius: 4px;
    font-family: 'Inter', sans-serif;
}
.npc-name {
    color: var(--orange);
    font-family: 'Barlow Condensed', sans-serif;
    font-size: 14px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
}
.npc-btn-primary {
    background: var(--orange);
    color: var(--white);
}
.npc-btn-primary:hover {
    background: var(--orange-dim);
}
.npc-btn-secondary {
    background: var(--navy-mid);
    color: var(--muted);
}
```

---

## 28. NPC CONVERSATION SYSTEM

All NPC interactions use ox_lib context menus and progress bars. CSS overridden to match Bears palette.

### 28.1 Standard Loading Interaction

```lua
-- client/interactions.lua
lib.registerContext({
    id = 'truck_loading_cold_chain',
    title = 'Dock Supervisor · ' .. shipperName,
    options = {
        {
            title = '"Reefer set to 36°F?"',
            description = '',
            disabled = true,
        },
        {
            title = 'Confirm temperature',
            onSelect = function()
                TriggerEvent('trucking:client:confirmReeferTemp')
            end,
        },
        {
            title = 'Sign BOL',
            disabled = not reeferConfirmed,
            onSelect = function()
                TriggerServerEvent('trucking:server:signBOL', loadId)
            end,
        },
    }
})
lib.showContext('truck_loading_cold_chain')
```

### 28.2 Hold-to-Confirm (Cargo Securing)

```lua
lib.progressBar({
    duration    = 4000,
    label       = 'Securing strap point ' .. pointNumber .. ' of ' .. totalPoints,
    useWhileDead = false,
    canCancel   = true,
    anim = {
        dict   = 'anim@heists@ornate_bank@hack',
        clip   = 'hack_enter',
        flag   = 49,
    },
}, function(cancelled)
    if not cancelled then
        TriggerServerEvent('trucking:server:strapComplete', bolId, pointNumber)
    end
end)
```

### 28.3 Leon Interaction

```lua
lib.registerContext({
    id = 'leon_board',
    title = 'Leon',
    options = {
        {
            title = '"' .. leonQuote .. '"',
            description = 'Risk: ' .. riskDisplay .. '  ·  Fee: $' .. fee,
            disabled = true,
        },
        {
            title = 'Pay $' .. fee,
            onSelect = function()
                TriggerServerEvent('trucking:server:payLeonFee', loadId)
            end,
        },
        {
            title = 'Walk away',
            onSelect = function()
                lib.hideContext()
            end,
        },
    }
})
```

---

## 29. EXPORTS AND EVENTS

### 29.1 Exported Functions

```lua
-- server/exports.lua

-- Check if player has active trucking license
exports('GetDriverLicense', function(citizenid, licenseType)
    -- returns: { active = bool, issued_at = int, expires_at = int|nil }
end)

-- Check if player has active certification
exports('GetDriverCertification', function(citizenid, certType)
    -- returns: { active = bool, status = string } or nil
end)

-- Get driver overall reputation score
exports('GetDriverReputationScore', function(citizenid)
    -- returns: { score = int, tier = string }
end)

-- Get driver's shipper reputation
exports('GetShipperReputation', function(citizenid, shipperId)
    -- returns: { tier = string, points = int }
end)

-- Check if driver has active load
exports('GetActiveLoad', function(citizenid)
    -- returns: activeLoad table or nil
end)

-- Check if vehicle is registered as flammable (for explosion system)
exports('IsFlammableVehicle', function(plate)
    -- returns: bool
end)

-- Get flammable vehicle data
exports('GetFlammableVehicleData', function(plate)
    -- returns: { profile = string, fill_level = float } or nil
end)

-- Register external vehicle as flammable
exports('RegisterFlammableVehicle', function(plate, data)
    -- data: { profile, fill_level, cargo_type }
end)

-- Deregister flammable vehicle
exports('DeregisterFlammableVehicle', function(plate)
end)

-- Register Leon load type from external resource
exports('RegisterLeonLoadType', function(loadTypeData)
    -- loadTypeData: { supplier_id, label, risk_tier, fee_range,
    --                 payout_range, delivery_event }
end)

-- Trigger reputation event from external resource
exports('TriggerReputationEvent', function(citizenid, eventType, context)
    -- eventType: string matching change_type ENUM
    -- context: { bol_number, tier_of_load, notes }
end)
```

### 29.2 Key Server Events

```lua
-- Internal events (server → server)
'trucking:server:signBOL'
'trucking:server:loadAccepted'
'trucking:server:loadDelivered'
'trucking:server:loadAbandoned'
'trucking:server:sealBreak'
'trucking:server:excursionStart'
'trucking:server:excursionEnd'
'trucking:server:integrityEvent'
'trucking:server:welfareEvent'
'trucking:server:weighStationStamp'
'trucking:server:payLeonFee'
'trucking:server:militaryBreachDetected'

-- Client → Server
'trucking:server:openBoard'
'trucking:server:reserveLoad'
'trucking:server:acceptLoad'
'trucking:server:cancelReservation'
'trucking:server:initiateTransfer'
'trucking:server:acceptTransfer'
'trucking:server:distressSignal'
'trucking:server:assignLoadToDriver'
'trucking:server:createConvoy'
'trucking:server:joinConvoy'
'trucking:server:drainStart'
'trucking:server:drainComplete'
'trucking:server:livestockRestStop'
'trucking:server:strapComplete'
'trucking:server:insurancePurchase'
'trucking:server:filingClaim'

-- Server → Client
'trucking:client:loadAssigned'
'trucking:client:transferOffer'
'trucking:client:convoyUpdate'
'trucking:client:directOffer'
'trucking:client:reputationUpdate'
'trucking:client:claimPaid'
'trucking:client:surgeAlert'
'trucking:client:boardRefresh'
```

### 29.3 External Dispatch Export

```lua
-- Called for seal break (low priority)
-- Called for HAZMAT incident (high priority)
-- Called for military cargo theft (high priority)

local function DispatchAlert(alertData)
    if Config.PoliceResource and Config.PoliceResource ~= '' then
        exports[Config.PoliceResource]:dispatchAlert(alertData)
    end
end
```

---

## 30. DEVELOPMENT MILESTONES

### Phase 1 — Foundation (Milestone 1)

**Goal:** Functional Tier 0 load loop with basic board.

```
[ ] Database tables created (all 24)
[ ] Config files populated (shippers, cargo, economy)
[ ] truck_drivers: create on first interaction
[ ] truck_loads: board generation for Tier 0
[ ] Board NUI — Standard tab, Tier 0 only
[ ] Load card display — collapsed and expanded
[ ] Load reservation — 3-minute hold
[ ] Load acceptance — deposit deduction
[ ] BOL generation — truck_bols insert
[ ] BOL item → ox_inventory
[ ] Active load HUD — 3-line overlay
[ ] Delivery interaction — basic NPC, BOL sign
[ ] Payout calculation — Tier 0 (base rate + floor)
[ ] Deposit return on delivery
[ ] truck_active_loads: create and delete
[ ] truck_bol_events: append on key events
[ ] Resource start/stop handling
```

**Test:** Accept a van load, drive to destination, deliver, receive payout, deposit returned.

---

### Phase 2 — Progression Systems (Milestone 2)

**Goal:** CDL system functional. Tier 1 loads available. Board full.

```
[ ] CDL written test NUI (Class B)
[ ] CDL question pool — config/cdl.lua
[ ] Class B license issuance — item + database
[ ] Tier 1 loads added to board
[ ] Board filtering — tier filter
[ ] Cargo securing interaction (flatbed)
[ ] Manifest verification interaction
[ ] Reputation system — driver score
[ ] Reputation system — shipper rep
[ ] Rep update on delivery and failure
[ ] Board access gating by reputation tier
[ ] Cross-region view unlock (Professional+)
[ ] Multi-stop load support
[ ] Multi-stop payout premium
[ ] Supplier contracts tab
[ ] Route tab
[ ] Board refresh — staggered by region
[ ] 15-minute refresh notification
[ ] NUI screens: Profile (Credentials + Standings)
```

**Test:** Earn Class B CDL, complete T1 load, verify rep update, verify board access.

---

### Phase 3 — Class A and Tier 2 (Milestone 3)

**Goal:** Full CDL progression. Tier 2 functional. Tutorial complete.

```
[ ] Class A written test NUI
[ ] CDL Tutorial — 5 stages
[ ] Stage 1: Pre-trip inspection
[ ] Stage 2: Coupling + securing
[ ] Stage 3: City navigation + manifest
[ ] Stage 4: Highway run + HUD intro
[ ] Stage 5: Backing + dock + BOL + payout
[ ] Class A license issuance
[ ] Tanker endorsement written test + briefing
[ ] HAZMAT endorsement briefing (no test)
[ ] Tier 2 loads: T2-01 cold chain
[ ] Temperature monitoring — 2-state system
[ ] Reefer vehicle health check
[ ] Tier 2: T2-02 fuel tanker
[ ] Tier 2: T2-03 liquid bulk
[ ] Tier 2: T2-04 livestock welfare
[ ] Tier 2: T2-05 oversized + permit system
[ ] Weigh station locations + interactions
[ ] Weigh station compliance bonus
[ ] Seal system — binary
[ ] Seal break → police dispatch export
[ ] Open contracts tab
[ ] Surge events — detection + board display
[ ] Insurance system — all 3 policy types
[ ] Insurance hard block on load acceptance
[ ] NUI: Insurance screen
[ ] Vapid office claim interaction
[ ] Claim verification + 15-minute payout queue
```

**Test:** Full cold chain run with excursion event, weigh station stop, delivery. Test insurance claim.

---

### Phase 4 — Certifications and Tier 3 (Milestone 4)

**Goal:** Tier 3 fully gated and functional.

```
[ ] Bilkington Carrier Certification
[ ] High-Value Certification + Vangelico interview
[ ] Government Clearance — instant on qualification
[ ] Tier 3: T3-01 pharmaceutical
[ ] Pharmaceutical reefer threshold (80%)
[ ] Tier 3: T3-02 HAZMAT
[ ] HAZMAT routing restrictions + GPS
[ ] HAZMAT routing violation → auto dispatch
[ ] HAZMAT spill system
[ ] Hazmat cleanup kit interaction
[ ] Tier 3: T3-03 high-value goods
[ ] Tier 3: T3-05 military / government
[ ] Military convoy NPC spawning
[ ] Military escort behavior
[ ] Military breach detection
[ ] Long Con consequence chain
[ ] Military dispatch export (breach only)
[ ] Military cargo item table
[ ] Government contract rare board posting
```

**Test:** Full pharmaceutical run. HAZMAT run with routing compliance. Military contract clean delivery.

---

### Phase 5 — Criminal Tier (Milestone 5)

**Goal:** Leon functional. Robbery mechanics complete.

```
[ ] Leon location and hours gate
[ ] Leon unlock threshold (15 Tier 3 deliveries)
[ ] Leon board — 5 loads, 3-hour refresh
[ ] Leon NUI — risk/fee only, reveal on payment
[ ] Leon fee deduction (cash, not bank)
[ ] Criminal supplier definitions
[ ] Criminal supplier reputation system
[ ] Supplier unlock progression
[ ] Leon load delivery — no BOL, no seal, cash payout
[ ] RegisterLeonLoadType export (extension hook)
[ ] Robbery eligibility checks
[ ] Spike strip interaction
[ ] Bolt cutters + skill check
[ ] Cargo item spawning on breach
[ ] Full trailer steal mechanics
[ ] Robbery → driver notification
[ ] Distress signal → company dispatch
[ ] Comms jammer mechanic
[ ] Fuel drain robbery mechanic
[ ] All 6 fuel drain use cases
[ ] Drain spill zone (traction hazard)
[ ] Dairy tanker steal (milk_jug_bulk)
[ ] Milk spill zone (comedy hazard)
```

**Test:** Complete Leon load. Rob a Tier 2 tanker. Drain fuel. Verify milk spill.

---

### Phase 6 — Company and Convoy (Milestone 6)

**Goal:** Company system, dispatcher tablet, convoy operational.

```
[ ] Company creation and member management
[ ] Dispatcher role assignment
[ ] Dispatcher mode — cannot accept loads
[ ] Dispatcher NUI — fleet monitor
[ ] Live driver status visible to dispatcher
[ ] Load assignment (dispatcher → driver)
[ ] Driver assignment accept/decline
[ ] Load transfer (company driver → company driver)
[ ] Convoy creation — 3 types
[ ] Convoy join mechanic
[ ] Convoy HUD overlay
[ ] Convoy arrival window check
[ ] Convoy payout bonus
[ ] Company NUI — simplified dashboard
[ ] Shipper preferred tier — direct offers
[ ] Direct offer notification
[ ] Preferred decay (14-day inactive)
[ ] Cluster friction system
```

**Test:** Company of 3 drivers runs convoy with dispatcher coordinating. Verify convoy bonus.

---

### Phase 7 — Explosions and HAZMAT (Milestone 7)

**Goal:** Enhanced explosion system and HAZMAT incidents polished.

```
[ ] Active vehicle tracking by plate
[ ] Explosion profile definitions (config/explosions.lua)
[ ] Phase sequencer — 5-phase fuel tanker
[ ] Fire column persistent zone
[ ] Secondary ignition chain
[ ] Explosion profile scaling by fill level
[ ] RegisterFlammableVehicle export
[ ] HAZMAT class-specific explosion profiles
[ ] Spill ignition trigger (fire source near spill)
[ ] Ground scorch zone
[ ] Smoke column (server-visible)
[ ] All HAZMAT class spill behaviors
[ ] Radiation zone (Class 7)
[ ] Corrosion damage (Class 8)
[ ] Emergency service notifications
[ ] Cleanup kit interactions
```

**Test:** Full tanker explosion sequence. HAZMAT spill cleanup. Chain explosion.

---

### Phase 8 — Polish and Standalone NUI (Milestone 8)

**Goal:** Full NUI polish, lb-phone integration, standalone mode, all screens complete.

```
[ ] All NUI screens complete (7 screens)
[ ] Bears palette fully applied
[ ] Barlow Condensed + Inter fonts
[ ] lb-phone app registration
[ ] Standalone mode (F6 keybind)
[ ] Config toggle between modes
[ ] NPC conversation CSS overrides
[ ] Hold-to-confirm button component
[ ] Leon NUI styling (minimal, distinct)
[ ] Vapid Insurance NUI
[ ] All notification types
[ ] Notification priority system
[ ] HUD overlay — 3 border states
[ ] Convoy HUD overlay
[ ] Dispatcher tablet layout
[ ] Performance pass — minimize NUI re-renders
[ ] Locales file (en.json) — all strings
[ ] Config documentation pass
[ ] Webhook implementation (all channels)
[ ] Maintenance query scheduling
[ ] Resource restart load recovery
[ ] Full QA pass — all systems end-to-end
```

---

### Phase 9 — Standalone Licensing Resource (Milestone 9, Optional)

**Goal:** Extract CDL tutorial into standalone `player-licensing` framework.

```
[ ] player-licensing resource scaffold
[ ] Stage registration API
[ ] Test question pool registration API  
[ ] License issuance via export
[ ] CDL stages migrated from trucking script
[ ] Trucking script calls licensing exports
[ ] Documentation for other script integration
[ ] Class B, motorcycle, and pilot as reference implementations
```

---

## APPENDIX A — LEON'S CRIMINAL SUPPLIER REFERENCE

| Supplier | Background | Available Loads | Rate |
|---------|-----------|----------------|------|
| Chamberlain Distribution | African-American organized distribution | Consumer goods, clothing, electronics off-book | 115% |
| Ancelotti Freight Solutions | Italian-American | Sealed containers, electronics, pharma forgeries | 130% |
| Aztecas Agricultural Supply | Latino | Agricultural chemicals, bulk drums, HAZMAT no-docs | 145% |
| Vespucci Cold Chain | Russian | Sealed reefer cargo, cold chain pharma concealment | 150% |
| Jade River Import/Export | Asian | Produce with concealed goods, highest payout | 160% |

---

## APPENDIX B — SHIPPER CLUSTER REFERENCE

| Cluster | Members | Friction on damage |
|---------|---------|-------------------|
| Luxury | Vangelico, Maze Bank Logistics, Groupe Sechs | -10% progression rate with partners |
| Agricultural | Grapeseed Agricultural, Blaine County Growers, Blaine County Livestock | -10% |
| Industrial | Alamo Industrial, RON Petroleum, Cliffford Agrochemical | -10% |
| Government | Bilkington Research, Port of LS Freight, LSIA Federal Logistics | -15% |

---

## APPENDIX C — DEPENDENCY VERSIONS (at time of writing)

```
oxmysql         — latest stable
ox_lib          — latest stable  
ox_inventory    — latest stable
qb-core         — latest stable (or qbx_core equivalent)
lb-phone        — optional, specify version if integrating
```

---

*End of Development Guide*  
*Version: 1.0 — Post-design-review*
