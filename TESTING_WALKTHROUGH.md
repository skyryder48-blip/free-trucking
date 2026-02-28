# Free Trucking — Testing & Walkthrough Guide

Complete step-by-step guide for installing, configuring, testing, and validating
every system in the Free Trucking resource.

---

## Table of Contents

1. [Prerequisites & Installation](#1-prerequisites--installation)
2. [Database Setup](#2-database-setup)
3. [Configuration Checklist](#3-configuration-checklist)
4. [Admin Commands](#4-admin-commands)
5. [System-by-System Testing](#5-system-by-system-testing)
   - 5.1 [Core Load Lifecycle (Tier 0)](#51-core-load-lifecycle-tier-0)
   - 5.2 [CDL Written Tests & Practical Tutorial](#52-cdl-written-tests--practical-tutorial)
   - 5.3 [Board & Load Selection](#53-board--load-selection)
   - 5.4 [Deposit & Payout System](#54-deposit--payout-system)
   - 5.5 [BOL (Bill of Lading)](#55-bol-bill-of-lading)
   - 5.6 [Seal System](#56-seal-system)
   - 5.7 [Cargo Securing](#57-cargo-securing)
   - 5.8 [Pre-Trip Inspection](#58-pre-trip-inspection)
   - 5.9 [Weigh Stations](#59-weigh-stations)
   - 5.10 [Temperature Monitoring & Reefer](#510-temperature-monitoring--reefer)
   - 5.11 [Livestock Welfare](#511-livestock-welfare)
   - 5.12 [Insurance System](#512-insurance-system)
   - 5.13 [Reputation System](#513-reputation-system)
   - 5.14 [Surge Pricing](#514-surge-pricing)
   - 5.15 [Company & Dispatcher](#515-company--dispatcher)
   - 5.16 [Convoy System](#516-convoy-system)
   - 5.17 [Fuel Tanker & Drain](#517-fuel-tanker--drain)
   - 5.18 [HAZMAT System](#518-hazmat-system)
   - 5.19 [Explosion System](#519-explosion-system)
   - 5.20 [Leon (Criminal System)](#520-leon-criminal-system)
   - 5.21 [Military Contracts](#521-military-contracts)
   - 5.22 [Robbery System](#522-robbery-system)
   - 5.23 [Truck Stop Network](#523-truck-stop-network)
   - 5.24 [NUI Screens](#524-nui-screens)
   - 5.25 [Admin Panel](#525-admin-panel)
   - 5.26 [Reconnect Recovery](#526-reconnect-recovery)
6. [Payout Calculation Walkthrough](#6-payout-calculation-walkthrough)
7. [Economy Tuning](#7-economy-tuning)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Prerequisites & Installation

### Required Resources

| Resource | Version | Purpose |
|----------|---------|---------|
| `qbx_core` | Latest | Framework core |
| `ox_lib` | Latest | UI utilities, zones, callbacks, progress bars |
| `ox_inventory` | Latest | Item management, search, metadata |
| `oxmysql` | Latest | Database driver |

### Optional Integrations

| Resource | Config Key | Purpose |
|----------|-----------|---------|
| `lb-phone` | `Config.PhoneResource` | Phone app mode (NUI inside phone) |
| `lb-dispatch` or `ultimate-le` | `Config.PoliceResources` | Police dispatch alerts |
| `lc` (or other fuel script) | `Config.VehicleHandlingResource` | Fuel cost tracking |

### Installation Steps

```
1.  Place `free-trucking` folder in your server's `resources/` directory

2.  Add to server.cfg:
        ensure oxmysql
        ensure ox_lib
        ensure ox_inventory
        ensure qbx_core
        ensure free-trucking

3.  Import the database schema (see Section 2)

4.  Copy items from sql/items.lua into your ox_inventory item definitions
    (either data/items.lua or the relevant modular items file)

5.  Restart server
```

### Item Registration

Items from `sql/items.lua` that must be registered in ox_inventory:

| Item | Type | Purpose |
|------|------|---------|
| `trucking_bol` | Document | Bill of Lading — issued on load acceptance |
| `cdl` | Document | Single CDL card with metadata for all credentials |
| `barrel_drum` | Container | 55-gallon drum, metadata tracks fill level/contents |
| `fuel_hose` | Tool | Required for all tanker drain operations |
| `valve_wrench` | Tool | Required for robbery drain |
| `spike_strip` | Weapon | Robbery — deploys tire spikes |
| `comms_jammer` | Tool | Robbery — blocks distress signal 3 min |
| `bolt_cutters` | Tool | Robbery — breach standard trailer seals |
| `military_bolt_cutters` | Tool | Robbery — breach military cargo containers |
| `hazmat_cleanup_kit` | Consumable | Universal hazmat spill cleanup |

Military loot uses standard GTA items already in ox_inventory:
`armour`, `weapon_pistol`, `weapon_carbinerifle`, `weapon_specialcarbine`,
`weapon_combatmg`, `ammo-9`, `ammo-rifle`

---

## 2. Database Setup

Run `sql/schema.sql` against your MySQL/MariaDB database:

```sql
mysql -u root -p your_database < sql/schema.sql
```

This creates **24 tables**:

| Category | Tables |
|----------|--------|
| Driver Core | `truck_drivers`, `truck_licenses`, `truck_certifications` |
| Load System | `truck_loads`, `truck_active_loads`, `truck_bols`, `truck_bol_events`, `truck_supplier_contracts`, `truck_open_contracts`, `truck_open_contract_contributions`, `truck_routes` |
| Financial | `truck_deposits`, `truck_insurance_policies`, `truck_insurance_claims` |
| Reputation | `truck_driver_reputation_log`, `truck_shipper_reputation`, `truck_shipper_reputation_log` |
| Company | `truck_companies`, `truck_company_members`, `truck_convoys` |
| Cargo Tracking | `truck_integrity_events`, `truck_weigh_station_records`, `truck_livestock_welfare_logs` |
| System | `truck_board_state`, `truck_surge_events`, `truck_webhook_log` |

The schema also seeds `truck_board_state` with the 4 region rows + `server_wide`.

### Verify Database

```sql
SELECT COUNT(*) FROM truck_board_state;
-- Expected: 5 rows (los_santos, sandy_shores, paleto, grapeseed, server_wide)
```

---

## 3. Configuration Checklist

All values are pre-configured with tested defaults. Review these before going live:

### config/config.lua

| Setting | Default | Description |
|---------|---------|-------------|
| `Config.UsePhoneApp` | `true` | lb-phone app integration |
| `Config.UseStandaloneNUI` | `true` | Standalone NUI via hotkey |
| `Config.NUIKey` | `'F6'` | Keybind for standalone NUI |
| `Config.PoliceResources` | `{'lb-dispatch','ultimate-le'}` | Police dispatch integration |
| `Config.Webhooks.*` | `nil` | Set Discord webhook URLs to enable logging |

### config/economy.lua

| Setting | Default | Description |
|---------|---------|-------------|
| `Economy.ServerMultiplier` | `1.0` | Global payout scaler — tune this first |
| `Economy.NightHaulPremium` | `0.07` | +7% for deliveries 22:00-06:00 |
| `Economy.BaseRates` | `{25, 42, 65, 95}` | $/mile per tier |
| `Economy.MaxComplianceStack` | `0.25` | 25% compliance bonus cap |

### Coordinate Validation

All coordinates use real GTA V map positions. Validate these in-game:

- **Truck Stops**: 6 locations in `Config.TruckStops` (config/config.lua:391-475)
- **Weigh Stations**: 3 locations in `Config.WeighStationLocations` (config/config.lua:246-250)
- **Insurance Offices**: 2 locations in `Config.InsuranceLocations` (config/config.lua:98-101)
- **Shippers**: 12+ shippers with pickup coords + 3-6 destinations each (config/shippers.lua)
- **Rental Spawn Points**: `Vehicles.Rentals` entries (config/vehicles.lua:317-383)

---

## 4. Admin Commands

| Command | Permission | Opens |
|---------|-----------|-------|
| `/truckadmin` | `group.admin` | Admin panel NUI |

The admin panel provides:
- Player lookup (by citizenid or name)
- Reputation adjustment with reason logging
- Driver suspension / unsuspension
- Force-complete or force-abandon stuck loads
- Server economy multiplier live tuning (0.1-5.0)
- Manual surge creation and cancellation
- Board refresh per region
- Active loads view (server-wide)
- Pending insurance claims review
- Board state and surge dashboard
- Server stats overview

---

## 5. System-by-System Testing

### 5.1 Core Load Lifecycle (Tier 0)

This is the foundational flow. Every other system layers on top of this.

#### Test: Complete a basic Tier 0 delivery

```
SETUP
  - New character, no CDL, no reputation record

STEP 1 — Open Board
  - Go to any truck stop terminal (see Config.TruckStops coords)
  - Press [E] to interact with terminal
  - Board opens showing Standard/Supplier/Open/Routes tabs
  - Filter to Tier 0 loads — should see 4 per region

STEP 2 — Reserve a Load
  - Click a Tier 0 load card
  - Load Detail screen appears (3-minute reservation timer starts)
  - Verify: shipper, origin, destination, distance, weight, payout estimate, deposit

STEP 3 — Accept the Load
  - Click Accept
  - Verify: deposit deducted from bank (T0 = flat $300)
  - Verify: BOL item added to inventory (trucking_bol)
  - Verify: notification confirms acceptance
  - Verify: HUD overlay appears (cargo type, integrity %, timer)

STEP 4 — Pre-Trip Inspection (Optional)
  - At origin, prompt appears for pre-trip
  - Complete the inspection (progress bar)
  - Verify: +3% compliance bonus will apply to payout

STEP 5 — Depart Origin
  - Drive away from origin
  - Verify: delivery window timer starts
  - Verify: GPS waypoint set to destination

STEP 6 — Drive to Destination
  - Collisions reduce cargo integrity (visible on HUD)
  - Drive carefully to maintain >90% integrity

STEP 7 — Deliver
  - Arrive at destination zone (T0 = 12m x 8m zone)
  - Press [E] to deliver
  - Verify: payout deposited to bank
  - Verify: deposit returned to bank ($300)
  - Verify: BOL updated to 'delivered'
  - Verify: reputation gained (+8 for T0)
  - Verify: payout receipt notification shows breakdown

EXPECTED DATABASE STATE
  truck_drivers:  1 row created (rep=508, total_loads_completed=1)
  truck_bols:     1 row (bol_status='delivered', final_payout > 0)
  truck_deposits: 1 row (status='returned')
  truck_loads:    1 row (board_status='completed')
```

#### Test: Abandon a load

```
  - Accept a T0 load
  - Drive away from origin then stop for 10+ minutes
  - OR trigger server event: trucking:server:abandonLoad
  - Verify: deposit forfeited (status='forfeited')
  - Verify: reputation loss (-25 for T0 abandonment)
  - Verify: BOL status = 'abandoned'
```

#### Test: Delivery window expires

```
  - Accept a T0 load
  - Do not deliver before the window expires
  - Verify: maintenance thread auto-expires the load (every 15 min check)
  - Verify: deposit forfeited
  - Verify: reputation loss (-10 for T0 expiry)
```

---

### 5.2 CDL Written Tests & Practical Tutorial

#### Test: Class B Written Test

```
STEP 1 — Access LSDOT Terminal
  - Approach CDL testing terminal
  - Select "Class B CDL Written Test"

STEP 2 — Pay Fee
  - Verify: $150 deducted from bank

STEP 3 — Take Test
  - 10 questions selected randomly from 40-question pool
  - Answer at least 8/10 correctly (80% pass)
  - Verify: answers validated server-side (answer key never sent to client)

STEP 4 — Pass
  - Verify: Class B license issued
  - Verify: CDL item added/updated in inventory with metadata.license_class = 'class_b'
  - Verify: truck_licenses row created (status='active')
  - Verify: Tier 1 loads now visible on board

LOCKOUT TEST
  - Fail the test 3 times consecutively
  - Verify: 1-hour lockout applied (locked_until set in DB)
  - Verify: cannot start another test until lockout expires
```

#### Test: Class A CDL (Tutorial / Practical)

```
  - Pass Class B written test first
  - Pass Class A written test ($300 fee, 10 questions from separate pool)
  - Complete 5 tutorial stages (practical driving)
  - Stage 5 completion issues Class A CDL + $850 payout
  - Verify: CDL item metadata updated to license_class = 'class_a'
  - Verify: Tier 2 loads now accessible (with rep ≥ 400)
```

#### Test: Endorsements

```
TANKER ENDORSEMENT
  - Requires Class A CDL
  - 15 questions from tanker pool, 80% pass, $500 fee
  - Verify: CDL item metadata.endorsements.tanker = true
  - Verify: fuel tanker and liquid bulk loads accessible

HAZMAT ENDORSEMENT
  - Requires Class A CDL
  - Briefing format: 5 topics, no pass/fail, $750 + $500 background check
  - Complete all 5 topics
  - Verify: CDL item metadata.endorsements.hazmat = true
  - Verify: HAZMAT loads accessible
```

#### Test: Certifications

```
BILKINGTON CARRIER
  Prerequisites: Class A + 10 cold chain deliveries + 5 clean streak
  Fee: $3,000
  Verify: CDL item metadata.certifications.bilkington = true
  Verify: pharmaceutical loads accessible

HIGH-VALUE
  Prerequisites: Class A + 7-day clean record + no theft claims 30 days
  Fee: $2,500 background check
  Includes NPC interview (5 questions, pass 4/5)
  Verify: CDL item metadata.certifications.high_value = true

GOVERNMENT CLEARANCE
  Prerequisites: Class A + High-Value cert + 30 clean days + 3 trusted shippers + $5,000
  Verify: CDL item metadata.certifications.government = true
  Verify: military contracts accessible
```

---

### 5.3 Board & Load Selection

#### Test: Board refresh cycle

```
  - Board refreshes every 2 hours (Config.BoardRefreshSeconds = 7200)
  - Regions stagger: LS at :00, Paleto at :15, Sandy at :30, Grapeseed at :45
  - Verify load counts per region match BoardConfig.StandardLoads
    (e.g., LS = 4/4/3/2 for T0/T1/T2/T3)
```

#### Test: Board tabs

```
  Standard — individual spot loads
  Supplier — shipper-specific contracts (3 per region per refresh)
  Open     — community goals (2 active server-wide)
  Routes   — multi-stop scheduled runs (2 per region, 6-hour cycle)
```

#### Test: Reservation system

```
  - Click load detail → 3-minute reservation hold
  - Other players cannot accept the same load
  - Let reservation expire → load returns to 'available'
  - Release 5 loads consecutively → reservation cooldown (10 min on T2+)
```

#### Test: Tier access by reputation

```
  Suspended (0):     no access
  Restricted (1+):   T0 only
  Probationary (200+): T0-T1
  Developing (400+): T0-T2
  Established (600+): T0-T3
  Professional (800+): T0-T3 + cross-region
  Elite (1000+):     T0-T3 + early government
```

---

### 5.4 Deposit & Payout System

#### Test: Deposit calculations

```
  T0: flat $300 (Config.DepositFlatT0)
  T1: 15% of estimated payout
  T2: 20% of estimated payout
  T3: 25% of estimated payout

  Verify deposit deducted on acceptance, returned on successful delivery
  Verify deposit forfeited on abandonment/expiry/rejection
```

#### Test: Payout floor enforcement

```
  T0 minimum: $150
  T1 minimum: $250
  T2 minimum: $400
  T3 minimum: $600

  Create a scenario where payout would be below floor
  (e.g., heavy integrity damage, late delivery)
  Verify floor kicks in as the minimum
```

---

### 5.5 BOL (Bill of Lading)

```
  - BOL created on load acceptance
  - BOL number format: unique alphanumeric
  - BOL item (trucking_bol) added to inventory
  - BOL tracks: shipper, origin, destination, cargo, weight, seal, temp, welfare
  - BOL status transitions: active → delivered / rejected / stolen / abandoned / expired
  - BOL events logged to truck_bol_events for every lifecycle event
```

---

### 5.6 Seal System

```
APPLY SEAL
  - After accepting a load that requires sealing
  - Progress bar interaction at trailer rear
  - Seal number generated and recorded on BOL + active load

SEAL INTEGRITY
  - Seal status monitored every 5 seconds (client)
  - Stationary 10+ minutes → seal break (server-side abandonment check)
  - Seal break triggers police dispatch (low priority)
  - Broken seal → -15 to -55 reputation loss (by tier)

DELIVERY WITH INTACT SEAL
  - +5% compliance bonus (Economy.ComplianceBonuses.seal_intact)
```

---

### 5.7 Cargo Securing

```
APPLICABLE VEHICLES
  - Flatbed (3 strap points, Config.FlatbedStrapPoints)
  - Oversized/lowboy/step-deck (4 strap points + wheel chock)

TEST FLOW
  - Accept a load requiring a flatbed
  - At origin, [E] prompt for cargo securing
  - Progress bar per strap point (4 sec each, Config.StrapDurationMs)
  - Must complete all strap points before departing
  - Verify: active load cargo_secured = true
```

---

### 5.8 Pre-Trip Inspection

```
  - Available at origin after accepting any load
  - [E] prompt to begin inspection
  - Progress bar interaction
  - Verify: pre_trip_completed = true on active load
  - Verify: +3% compliance bonus applied at payout
```

---

### 5.9 Weigh Stations

```
3 LOCATIONS (Config.WeighStationLocations)
  - Route 1 Pacific Bluffs
  - Route 68 near Harmony
  - Paleto Bay Highway Entrance

MANDATORY vs OPTIONAL
  - T0-T1: optional (Config.WeighStationOptionalMaxTier = 1)
  - T2-T3: mandatory routing — skipping is a route violation

TEST FLOW
  - Drive into weigh station zone
  - Inspection interaction (progress bar)
  - Result: passed / warning / violation / impound
  - Stamp issued on pass → +5% compliance bonus at payout
  - Violation → reputation penalty, event logged to truck_bol_events
```

---

### 5.10 Temperature Monitoring & Reefer

```
APPLICABLE CARGO
  - cold_chain, pharmaceutical, pharmaceutical_biologic
  - Any cargo with temp_min_f / temp_max_f on the BOL

REEFER HEALTH THRESHOLDS
  - Standard: vehicle health < 65% → reefer fault (Config.ReeferHealthThreshold)
  - Pharmaceutical: vehicle health < 80% (Config.PharmaHealthThreshold)

EXCURSION TEST
  Step 1: Accept a cold chain load
  Step 2: Damage the vehicle until health < 65%
  Step 3: Verify: server fires trucking:client:excursionStarted
  Step 4: Excursion timer begins
  Step 5: Repair vehicle above 65%
  Step 6: Verify: excursion ends, duration evaluated:
    - < 5 min:  clean (no penalty)
    - 5-15 min: significant (-15% payout)
    - > 15 min: critical (-35% payout)

ENGINE-OFF TEST
  - Turn engine off for 5+ minutes on a temp-monitored load
  - Verify: excursion starts automatically

CLEAN COLD CHAIN BONUS
  - Deliver with zero excursions → +5% compliance bonus
  - Also triggers +8 reputation bonus (cold_chain_clean)
```

---

### 5.11 Livestock Welfare

```
APPLICABLE CARGO
  - livestock (Tier 2, requires Class A CDL)

WELFARE RATING (1-5 scale, starts at 5)
  Events that DECREASE welfare:
    - Hard braking: -1.0 per event
    - Sharp corner (>35 mph): -1.0 per event
    - Major collision: -2.0 per event
    - Off-road driving: -1.0 per minute
    - Heat idle (Sandy Shores): -1.0 per 10 min

  Events that INCREASE welfare:
    - Smooth driving: +0.25 per 10 min
    - Quick rest stop (30 sec): +0.5
    - Water rest stop (2 min): +1.0
    - Full rest stop (5 min): +1.5

TRANSIT DECAY (passive, after 30 min)
  - 30-60 min: -0.25 per 30 min
  - 60-90 min: -0.50 per 30 min
  - 90+ min: -1.00 per 30 min

REST STOPS
  - Available at truck stops with hasLivestockRest = true
    (Harmony Rest Area, Grapeseed Co-op)
  - [E] prompt near livestock rest coords
  - Choose: quick (30s) / water (2m) / full (5m)

PAYOUT IMPACT
  Rating 5 (Excellent): +20% bonus + compliance bonus
  Rating 4 (Good):      +10% bonus
  Rating 3 (Fair):       0% (base rate)
  Rating 2 (Poor):      -15% penalty
  Rating 1 (Critical):  -40% penalty
```

---

### 5.12 Insurance System

```
COVERAGE REQUIREMENT
  - T0: exempt (optional purchase)
  - T1+: MUST have active policy to accept loads (hard block)

POLICY TYPES
  Single Load: 8% of estimated load value
  Day Policy:  $200-$1,800 by tier (24 hours, all loads)
  Week Policy: $1,000-$9,500 by tier (7 days, all loads)

PURCHASE TEST
  - Visit insurance terminal (2 standalone offices + truck stops with insurance)
  - Select policy type and tier
  - Verify: premium deducted, policy created (status='active')
  - Verify: policy bound to load on acceptance (bound_bol_id set)

CLAIM TEST
  Step 1: Accept a load with active insurance
  Step 2: Have the load stolen or abandoned (BOL status = 'stolen'/'abandoned')
  Step 3: File claim (trucking:server:fileInsuranceClaim with BOL number)
  Step 4: Verify: claim created (status='pending')
  Step 5: Admin approves claim via admin panel
  Step 6: Verify: 15-minute payout delay applied
  Step 7: After 15 min, claims processing thread issues payout:
          payout = (deposit × 2) + premium_allocated

POLICY EXPIRY TEST
  - Purchase a day policy
  - Wait 24 hours (or adjust time)
  - Verify: policy status changes to 'expired'
  - Verify: cannot accept T1+ loads without new policy
```

---

### 5.13 Reputation System

```
DRIVER REPUTATION (0-1200 scale)

Starting score: 500 (developing tier)

GAINS
  T0 delivery:        +8
  T1 delivery:        +15
  T2 delivery:        +25
  T3 delivery:        +40
  Military delivery:  +60
  Full compliance:    +5
  Supplier contract:  +20
  Cold chain clean:   +8
  Livestock excellent: +10

LOSSES
  Robbery:     -30 (T0) to -250 (military)
  Integrity:   -20 (T0) to -120 (T3)
  Abandonment: -25 (T0) to -160 (T3)
  Expired:     -10 (T0) to  -60 (T3)
  Seal break:   -0 (T0) to  -55 (T3)
  Hazmat routing: -40 (T3 only)

TIER TRANSITIONS
  Score hits 0: 24-hour suspension, locked out of all loads
  Suspension lifted: score set to 1 (restricted tier)

SHIPPER REPUTATION (separate per driver + shipper pair)
  Unknown (0) → Familiar (50) → Established (150) → Trusted (350) → Preferred (700)
  Rate bonuses: 0%/5%/10%/15%/20%
  Preferred decays to Trusted after 14 days inactivity (with warning)
```

---

### 5.14 Surge Pricing

```
AUTOMATIC TRIGGERS (checked every 30 min)
  - Open contract > 50% filled:      +20% on related cargo
  - Shipper backlog (4+ hrs no delivery): +35% that shipper
  - 3+ cold chain failures in 2 hrs: +30% reefer loads
  - 40+ players online:              +10% all tiers

MANUAL SURGES (admin panel)
  - Set region, percentage, duration
  - Alert broadcast to all players

DISPLAY
  - Surge badge shown on board load cards (orange, configurable color)
  - Percentage visible if BoardConfig.ShowSurgePercentage = true
```

---

### 5.15 Company & Dispatcher

```
CREATE COMPANY
  - Player creates company → becomes owner
  - Owner invites members (60-second invite expiry)
  - Max size: not hard-capped, but practical for convoy coordination

DISPATCHER ROLE
  Step 1: Owner assigns one member as dispatcher
  Step 2: Dispatcher enables dispatch mode
  Step 3: Dispatcher can:
    - View all company members (online/offline status)
    - View all company active loads
    - Assign board loads to specific drivers
    - Cannot accept loads personally while in dispatch mode
  Step 4: Assigned driver receives notification
  Step 5: Driver accepts/declines assignment
  Step 6: Accepted assignment follows normal load acceptance flow

DISPATCHER NUI
  - Dispatcher.svelte screen
  - Left panel: members list with status
  - Right panel: active loads map/list
  - Board access with "Assign to Driver" button on load cards
```

---

### 5.16 Convoy System

```
CONVOY TYPES
  Open:    any driver can join
  Invite:  creator must invite
  Company: company members only

FORMATION
  Step 1: Player creates convoy (selecting type)
  Step 2: Players join (min 2 required to start)
  Step 3: Creator starts convoy (max 6 vehicles)

PROXIMITY
  - 150m radius to maintain formation (Config.ConvoyProximityRadius)
  - Disconnect timeout: 120 seconds (Config.ConvoyDisconnectTimeout)

BONUS
  - All members must deliver within 15-minute window
  - 2 trucks: +8% payout bonus
  - 3 trucks: +12% payout bonus
  - 4+ trucks: +15% payout bonus
  - Bonus applied as compliance modifier (subject to 25% cap)

POSITION UPDATES
  - Client broadcasts position every 5 seconds
  - HUD shows member positions (convoy HUD overlay)
```

---

### 5.17 Fuel Tanker & Drain

```
REQUIRED ITEMS
  - fuel_hose: required for ALL drain operations
  - valve_wrench: required for robbery drain (not own vehicle)
  - barrel_drum: required for robbery drain and Leon diversion

USE CASES (4 remaining after fuel_canister removal)
  1. Robbery:       Not own vehicle + wrench + hose + barrel_drum
  2. Self-Refuel:   Own tanker + hose only (no drum) → 50 gallons
  3. Fuel Trap:     Own tanker + no drum → intentional spill
  4. Leon Diversion: Own tanker + drums + active Leon load

DRAIN TIMING
  - Robbery: 30 seconds per drum (Config.DrainSecondsPerDrum)
  - Self-refuel: 60 seconds (Config.SelfRefuelDuration)

SPILL MECHANICS
  - Initial radius: 3m, grows to 25m at 0.5m per 10 sec
  - Traction penalty: 0.3 grip reduction
  - Fire detection: 5m radius for ignition sources
  - Fire spread: proportional to distance
```

---

### 5.18 HAZMAT System

```
HAZMAT CLASSES

  Class 3 — Flammable
    Radius: 15m, no direct damage, fire risk on ignition
    Particle: orange fire particles
    Cleanup: hazmat_cleanup_kit

  Class 6 — Toxic
    Radius: 20m, 3 hp/sec damage to players
    Particle: green smoke cloud
    Cleanup: hazmat_cleanup_kit

  Class 7 — Radioactive
    Radius: 30m, 2 hp/sec damage, Geiger counter sound
    Particle: yellow/orange, screen distortion effect
    Cleanup: hazmat_cleanup_kit

  Class 8 — Corrosive
    Radius: 12m, 5 damage/sec to vehicle body+engine
    Particle: red/brown mist
    Cleanup: hazmat_cleanup_kit

SPILL TRIGGERS
  - Major collision at >30 mph
  - Cargo integrity drops below 15% (Config.HazmatSpillIntegrityThreshold)

CLEANUP
  - Approach spill zone edge (within radius + 3m)
  - Must have hazmat_cleanup_kit in inventory
  - [E] prompt to begin cleanup (60 seconds)
  - Progress bar with janitor animation
  - Kit consumed on completion

IGNITION (Class 3 only)
  - Gunfire within radius + 5m
  - Explosion within radius
  - Triggers staggered fire explosions across zone
```

---

### 5.19 Explosion System

```
FLAMMABLE VEHICLE REGISTRATION
  - Fuel tankers auto-register when load accepted
  - Server tracks: plate, fill_level, cargo_type, hazmat_class

EXPLOSION PROFILES (config/explosions.lua)
  - fuel_tanker_full: 3-phase cascade (initial, fuel eruption, secondary)
  - fuel_tanker_empty: single moderate explosion
  - hazmat_class3: fire cascade with burn zone
  - hazmat_class6: toxic cloud release (no explosion)
  - hazmat_class7: radiation release (invisible, persistent)
  - hazmat_class8: corrosive burst with mist zone
  - military_ordnance: multi-phase military explosion

FIRE ZONES
  - Created by explosions, persist until cleanup (10-second expiry check)
  - Damage ticks every 1 second to players in zone
  - Synced to all nearby clients
```

---

### 5.20 Leon (Criminal System)

```
ACCESS REQUIREMENTS
  - Complete 1 Tier 3 delivery (Config.LeonUnlockDeliveries = 1)
  - Active hours: 22:00-04:00 server time

SUPPLIERS (5, progressively unlocked)
  Southside Consolidated:    115% rate, low risk, first Leon load
  La Puerta Freight:         130% rate, medium risk, 3 Leon loads
  Blaine County Salvage:     145% rate, high risk, hazmat endorsement
  Paleto Bay Cold Storage:   150% rate, medium risk, T3 cold chain rep
  Pacific Bluffs Import:     160% rate, critical risk, 2 suppliers complete

FLOW
  Step 1: Access Leon board (NPC interaction, night only)
  Step 2: Board shows risk tier + fee only (no details)
  Step 3: Pay fee (CASH only) → reveals pickup, delivery, cargo, payout
  Step 4: Accept load
  Step 5: Deliver → paid in CASH (not bank)

KEY DIFFERENCES FROM STANDARD
  - No BOL document
  - No seal
  - No insurance
  - No reputation gain
  - Cash-only economy
  - All loads expire at 04:00 server time (dawn)
  - Board refreshes every 3 hours, max 5 loads per refresh
```

---

### 5.21 Military Contracts

```
REQUIREMENTS
  - Government Clearance certification (active)
  - Class A CDL

CONTRACT POSTING
  - Max 2 per server restart
  - 15% chance every 20-40 minutes
  - 3 classifications: equipment_transport, armory_transfer, restricted_munitions

ESCORT CONVOY
  - 2 Patriot (Insurgent) escort vehicles
  - Lead: 25m ahead, Trail: 25m behind
  - Formation speed: 40 mph

ESCORT BEHAVIOR
  - Investigation: 60 sec stationary → escorts investigate driver
  - Destruction: both destroyed → 90-second unguarded window
  - Breach detection: monitors for hostile actions

LEGITIMATE DELIVERY TEST
  - Accept military contract
  - Drive with escort convoy to destination
  - Deliver normally → bank payout + reputation (+60)
  - Escorts despawn on delivery

LONG CON TEST
  - Accept military contract
  - Intentionally stop for crew to breach
  - Verify consequences:
    - -400 reputation
    - Government clearance suspended 30 days
    - All T3 certs suspended 14 days

LOOT TABLES (GTA standard items)
  equipment_transport: armour, ammo-9, weapon_pistol
  armory_transfer:     + ammo-rifle, weapon_carbinerifle
  restricted_munitions: + weapon_specialcarbine, weapon_combatmg
```

---

### 5.22 Robbery System

```
PREREQUISITES
  - Load active for 90+ seconds (Config.RobberyMinActiveSeconds)
  - Not within 200m of depot/weigh station/truck stop safe zone
  - T2+ for full trailer steal; T1 = on-site loot only

TOOLS
  - spike_strip: deploy ahead of target vehicle
  - comms_jammer: block distress signal for 3 minutes
  - bolt_cutters: breach standard trailer seals
  - military_bolt_cutters: breach military cargo containers

FLOW
  - Intercept target vehicle
  - Deploy spike strip to stop them
  - Use comms jammer to block distress signal
  - Use bolt cutters to break seal
  - Steal cargo (loot interaction or drive away with trailer)
  - Police dispatch fires if no jammer active

CONSEQUENCES FOR VICTIM
  - BOL status → 'stolen'
  - Deposit forfeited
  - Reputation loss (robbery tier)
  - Insurance claim eligible if policy active
```

---

### 5.23 Truck Stop Network

```
6 LOCATIONS (Config.TruckStops)

FULL-SERVICE (4 locations, all are robbery safe zones):
  1. Route 68 Truck Plaza (Sandy Shores)
  2. Paleto Highway Stop (Paleto)
  3. LSIA Commercial Yard (Los Santos)
  4. Port of LS Staging (Los Santos)
  Services: board terminal, repair bay, insurance terminal

BASIC SERVICE (2 locations):
  5. Harmony Rest Area (Sandy Shores) — board + livestock rest
  6. Grapeseed Co-op Fuel (Grapeseed) — board + livestock rest

TEST EACH LOCATION
  - Travel to coords
  - Verify terminal interaction works ([E] prompt)
  - Verify repair bay (if full-service): deducts cost, applies repair
  - Verify insurance terminal (if full-service)
  - Verify livestock rest (if basic with livestock rest)
  - Verify safe zone radius (200m) prevents robberies at full-service stops
```

---

### 5.24 NUI Screens

Open the trucking NUI with the configured key (default: F6).

```
8 SCREENS

1. Home          — Dashboard, quick stats, recent loads
2. Board         — Load browser with Standard/Supplier/Open/Routes tabs
3. Load Detail   — Reserved load details, accept/decline, requirements
4. Active Load   — Current load HUD: integrity, timer, seal, temp, welfare
5. Profile       — Driver stats, reputation, licenses, certifications, shipper rep
6. Insurance     — Policy purchase, active policies, claim filing
7. Company       — Company management, members, invites
8. Dispatcher    — Dispatcher mode (assign loads to drivers, view active loads)

NAVIGATION
  - Sidebar navigation between screens
  - Board → Load Detail → Active Load is the primary flow
  - Profile shows all earned credentials on the single CDL item
```

---

### 5.25 Admin Panel

Accessed via `/truckadmin` command (requires group.admin).

```
TEST EACH FUNCTION

PLAYER LOOKUP
  - Search by citizenid or partial name
  - Verify: returns driver profile with rep, licenses, certs, stats

REPUTATION ADJUSTMENT
  - Adjust a driver's score by ±N points with reason
  - Verify: reputation_log entry created
  - Verify: tier transitions trigger correctly

DRIVER SUSPENSION
  - Suspend driver for N hours
  - Verify: driver cannot access any loads
  - Unsuspend driver
  - Verify: score set to 1 (restricted tier), access restored

FORCE-COMPLETE STUCK LOAD
  - Create a stuck scenario (active load, driver offline)
  - Force-complete from admin panel
  - Verify: deposit returned, floor payout issued, BOL completed

FORCE-ABANDON STUCK LOAD
  - Same as above but force-abandon
  - Verify: deposit returned, no penalty, BOL abandoned

ECONOMY MULTIPLIER
  - Set Economy.ServerMultiplier to 1.5
  - Accept and deliver a load
  - Verify: payout is 50% higher than base
  - Reset to 1.0

MANUAL SURGE
  - Create surge: region=los_santos, percentage=25, duration=3600
  - Verify: surge badge appears on LS board loads
  - Verify: affected loads pay +25%
  - Cancel surge from admin panel
  - Verify: badge removed, normal rates resume

BOARD REFRESH
  - Force refresh a region
  - Verify: old loads expired, new loads generated per BoardConfig.StandardLoads

INSURANCE CLAIMS
  - View pending claims
  - Approve a claim
  - Verify: 15-minute payout delay, then bank deposit
  - Deny a claim with reason
  - Verify: claim status='denied', player notified

SERVER STATS
  - View dashboard
  - Verify: shows total drivers, active loads, completed today, revenue, etc.
```

---

### 5.26 Reconnect Recovery

```
TEST FLOW
  Step 1: Accept a load and begin delivery
  Step 2: Disconnect (close game / lose connection)
  Step 3: Reconnect within 10 minutes
  Step 4: Verify: server fires trucking:client:restoreActiveLoad
  Step 5: Verify: active load state restored (HUD, waypoint, timers)
  Step 6: Continue delivery normally

ORPHAN TEST (disconnect > 10 min)
  Step 1: Accept a load
  Step 2: Disconnect for 10+ minutes
  Step 3: Maintenance thread processes orphaned load
  Step 4: Verify: BOL status='abandoned', deposit forfeited
  Step 5: Reconnect — no load restored (it was orphaned)
```

---

## 6. Payout Calculation Walkthrough

The payout calculation is a 12-step pipeline. Here is a worked example:

```
SCENARIO
  Tier 2 cold_chain load, 12.5 miles, 28,000 lbs
  Own vehicle, delivered early (75% of window)
  Intact seal, weigh station stamped, pre-trip done
  No temperature excursions
  Familiar shipper rep (+5%)

STEP 1 — Base Rate
  $65/mi (Economy.BaseRates[2])

STEP 2 — Cargo Modifier
  cold_chain = 1.10 → $65 × 1.10 = $71.50/mi

STEP 3 — Distance
  $71.50 × 12.5 mi = $893.75

STEP 4 — Multi-Stop Premium
  Single stop → +0% → $893.75

STEP 5 — Weight Multiplier
  28,000 lbs → medium bracket → ×1.15 → $1,027.81

STEP 6 — Owner-Op Bonus
  T2 own vehicle → +25% → $1,027.81 × 1.25 = $1,284.77

STEP 7 — Time Performance
  75% of window → early bonus → +15% → $1,284.77 × 1.15 = $1,477.48

STEP 8 — Integrity Check
  100% → pristine → +0% → $1,477.48

STEP 9 — Temperature Excursion
  No excursion → +0% → $1,477.48

STEP 10 — Livestock Welfare
  Not livestock → skip → $1,477.48

STEP 11 — Compliance Bonuses (additive, cap 25%)
  Seal intact:       +5%
  Weigh stamp:       +5%
  Pre-trip:          +3%
  Clean BOL:         +5%
  Cold chain clean:  +5%
  Shipper familiar:  +5%
  Total:             +28% → capped at +25%
  $1,477.48 × 1.25 = $1,846.85

STEP 12 — Night Haul Premium
  Delivered at 14:00 → not night → +0% → $1,846.85

STEP 13 — Server Multiplier
  Economy.ServerMultiplier = 1.0 → $1,846.85

STEP 14 — Floor Check
  T2 floor = $400 → $1,846.85 > $400 → PASS

FINAL PAYOUT: $1,847 (rounded)
DEPOSIT RETURNED: $369 (20% of estimated)
```

---

## 7. Economy Tuning

### Quick-Start Recommendations

```
TEST SERVER (generous payouts for testing):
  Economy.ServerMultiplier = 2.0

BALANCED SERVER (standard economy):
  Economy.ServerMultiplier = 1.0

HARDCORE SERVER (tight economy):
  Economy.ServerMultiplier = 0.6

RICH SERVER (established economy, lots of cash):
  Economy.ServerMultiplier = 0.4
```

### Live Tuning via Admin Panel

```
  /truckadmin → Economy Settings → Set Server Multiplier
  Range: 0.1 to 5.0
  Applied immediately, no restart required
  Affects all payouts calculated AFTER the change
```

### Per-Cargo Tuning

Adjust individual cargo modifiers in `config/economy.lua`:
```
  Economy.CargoRateModifiers.cold_chain = 1.10  -- increase/decrease this
```

### Insurance Rate Tuning

If insurance feels too expensive:
```
  Economy.InsuranceSingleLoadRate = 0.05   -- lower from 8% to 5%
  Economy.InsuranceDayRates[1] = 300       -- lower T1 day rate
```

---

## 8. Troubleshooting

### Resource won't start

```
SYMPTOM: Error on resource start
CHECK:
  1. All 4 dependencies running (oxmysql, ox_lib, ox_inventory, qbx_core)
  2. Database schema imported (24 tables, 5 board_state rows)
  3. All items registered in ox_inventory
  4. config/cdl.lua exists (CDL question pools)
```

### Board shows no loads

```
CHECK:
  1. Board state seeded: SELECT * FROM truck_board_state
  2. Refresh has occurred: wait for first cycle (staggered by region)
  3. Force refresh: /truckadmin → Board Refresh → select region
  4. Check server console for [trucking] board refresh messages
```

### CDL test shows "no question pool"

```
CHECK:
  1. config/cdl.lua exists and loads without errors
  2. CDLQuestionPools table is defined with class_b, class_a, tanker keys
  3. Each pool has at least 10 questions
```

### Payout seems too high/low

```
CHECK:
  1. Economy.ServerMultiplier value (admin panel shows current)
  2. Active surges inflating rates
  3. Compliance bonuses stacking (25% cap)
  4. Owner-op bonus applying (20-30% by tier)
  5. Time performance modifier (+15% early, -25% very late)
```

### Insurance blocks load acceptance

```
CHECK:
  1. T0 loads are exempt — should never block
  2. T1+ requires active policy: SELECT * FROM truck_insurance_policies
     WHERE citizenid = ? AND status = 'active'
  3. Policy may have expired — check valid_until timestamp
  4. Policy tier_coverage must match or exceed load tier
```

### Leon board not appearing

```
CHECK:
  1. Server time between 22:00-04:00 (Leon hours)
  2. Player has leon_access = TRUE in truck_drivers
  3. Player completed at least 1 T3 delivery (leon_tier3_deliveries ≥ 1)
  4. Leon board refresh cycle (3 hours between refreshes)
```

### Military contracts not posting

```
CHECK:
  1. Config.MilitaryDispatchEnabled = true
  2. Max 2 per restart (Config.MilitaryMaxPerRestart)
  3. 15% chance per 20-40 min interval — may take time
  4. Server console: [Trucking Military] messages
```

### Player stuck with active load

```
ADMIN FIX:
  /truckadmin → Active Loads → select player → Force Complete or Force Abandon
  Force Complete: returns deposit + floor payout
  Force Abandon: returns deposit, no penalty
```

### Reputation stuck at suspended

```
CHECK:
  1. suspended_until timestamp in truck_drivers
  2. Suspension lift thread runs every 60 seconds
  3. After lift: score set to 1 (restricted), access to T0 only
  4. Manual fix: /truckadmin → Unsuspend Driver
```

---

*Free Trucking v1.0.0 — Testing Guide*
