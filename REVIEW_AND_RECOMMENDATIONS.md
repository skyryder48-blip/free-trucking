# Development Guide Review & Recommendations

> Reviewed against: QBX framework standards, existing FiveM trucking scripts (Renewed-Trucking, Wasabi Trucking, JG Trucking, okokTrucking), and realistic RP server expectations.

---

## OVERALL ASSESSMENT

This is one of the most ambitious trucking script designs in the FiveM ecosystem. The scope exceeds every publicly available trucking resource. The tiered progression, BOL system, compliance mechanics, payout engine, and criminal layer would make this a flagship script if executed well.

**Core strengths:**
- Server-authority model is correct and anti-cheat conscious
- Tiered CDL progression mirrors real-world trucking licensing
- The payout engine with 10 calculation steps is the deepest of any FiveM trucking script
- BOL as a physical inventory item is a standout RP mechanic
- Shipper reputation with cluster friction adds meaningful long-term gameplay
- Export/event API is well-designed for ecosystem integration
- Development milestones are logically sequenced

**What follows are recommendations organized by priority: critical issues, gameplay gaps, realism additions, technical fixes, and balance tuning.**

---

## 1. CRITICAL — SECURITY & ANTI-EXPLOIT

### 1.1 Client-Side Timer Spoofing

The seal monitoring (Section 14.3) and temperature monitoring (Section 15.3) both use `os.time()` on the client. This is trivially spoofable with Lua injectors. Cheaters can freeze timers, skip abandonment detection, or fake excursion durations.

**Recommendation:** All timers must be server-authoritative. The client should report *events* (trailer decoupled, engine off, vehicle health changed), and the server tracks elapsed time.

```lua
-- CURRENT (vulnerable)
-- client/seals.lua
abandonmentTimer = os.time()  -- spoofable

-- RECOMMENDED
-- Client reports event, server tracks timing
TriggerServerEvent('trucking:server:vehicleStationary', activeLoad.bol_id)
-- Server records os.time() and checks on its own tick
```

### 1.2 Client-Reported Vehicle Health

Temperature excursions are triggered by client-side `GetEntityHealth()` checks. A cheater can spoof vehicle health to always report 1000, preventing reefer failures.

**Recommendation:** Implement server-side health verification. On each client health report, server does a spot-check via `GetEntityHealth` on the server-side entity. Discrepancies flag the player. Alternatively, use a server-side polling thread for active reefer loads (there will only be a handful at any time).

### 1.3 Robbery Eligibility — Server Enforcement

Section 22.1 states "Robber cannot have active trucking mission" but doesn't specify where this is enforced. If checked client-side only, it's bypassable.

**Recommendation:** All robbery initiation events must pass through server validation. Server checks `truck_active_loads` for the robber's citizenid before allowing any robbery action.

### 1.4 Event Validation Missing

Many `RegisterNetEvent` handlers shown in the guide don't validate the source player. Any player could fire `trucking:server:strapComplete` for any BOL ID without actually being near the vehicle.

**Recommendation:** Every server event handler must:
1. Verify `source` is the driver assigned to that BOL
2. For proximity-dependent actions, verify player coords server-side (get ped coords from server)
3. Rate-limit event calls to prevent spam

---

## 2. CRITICAL — TECHNICAL ISSUES IN CODE SAMPLES

### 2.1 Wrong oxmysql API Usage

Section 19.4 uses `MySQL.scalar.await` to fetch full rows:
```lua
local bol = MySQL.scalar.await(
    'SELECT * FROM truck_bols WHERE bol_number = ? AND citizenid = ?',
    { bolNumber, citizenid }
)
```

`MySQL.scalar.await` returns a **single value** (first column of first row), not a row object. This will silently fail.

**Fix:** Use `MySQL.single.await` for single rows or `MySQL.query.await` for result sets.

### 2.2 QBX vs QB-Core API Mismatch

The insurance payout code references:
```lua
TriggerEvent('qb-banking:server:addMoney', claim.citizenid, claim.claim_amount, ...)
```

QBX does not use this event. QBX banking is handled through:
```lua
local player = exports.qbx_core:GetPlayer(source)
player.Functions.AddMoney('bank', amount, reason)
```

The fxmanifest also lists `qb-core` as a dependency — should be `qbx_core` for QBX framework.

**Recommendation:** Audit all money transactions to use the correct QBX API. Consider wrapping money operations in a single utility function for easy framework swapping:
```lua
-- shared/utils.lua
function AddMoney(source, moneyType, amount, reason)
    local player = exports.qbx_core:GetPlayer(source)
    if player then
        player.Functions.AddMoney(moneyType, amount, reason)
    end
end
```

### 2.3 Client-Side `os.time()` in FiveM

FiveM's client-side Lua `os.time()` can behave inconsistently across clients and is easily manipulated. Several code samples use it for timing logic.

**Recommendation:** Use `GetGameTimer()` for client-side elapsed time measurements (returns milliseconds, monotonic, harder to spoof). For absolute timestamps, always defer to the server.

### 2.4 Missing Foreign Key Constraints

The schema has 24 tables with clear relationships but zero `FOREIGN KEY` constraints. This is likely intentional for insert performance, but it means orphaned records are possible (e.g., deleting a driver won't cascade to their loads, BOLs, reputation logs, etc.).

**Recommendation:** Document this as an intentional design choice. Add a cleanup/orphan detection query to the maintenance cycle. Consider adding FK constraints to critical relationships at minimum (e.g., `truck_active_loads.load_id → truck_loads.id`).

---

## 3. GAMEPLAY GAPS — MISSING FROM COMPETITIVE SCRIPTS

These are features found in top-tier FiveM trucking scripts that are absent from the guide. Adding them would make this script unquestionably best-in-class.

### 3.1 Fuel Consumption & Operating Costs

**Gap:** No fuel system. Every competitive trucking script factors fuel into the gameplay loop. Without it, there's no cost-of-doing-business pressure and no reason to plan routes efficiently.

**Recommendation:** Integrate with your server's fuel script (LegacyFuel, ox_fuel, cdn-fuel, etc.). Track fuel consumed per load. Optionally display fuel cost on the payout breakdown as a deduction. This adds a realistic economic layer — long hauls through Sandy Shores should cost more fuel than urban LS runs.

```lua
-- config/economy.lua addition
Economy.FuelCostPerMile = {
    van       = 3,    -- ~$3/mile fuel cost
    class_b   = 5,    -- medium trucks
    class_a   = 8,    -- semis
    tanker    = 10,   -- heavy loads
}
-- Shown in payout breakdown as informational (not deducted from payout,
-- but displayed so players understand net profit)
```

### 3.2 Vehicle Repair Costs

**Gap:** No mention of repair costs. Cargo integrity tracks damage but there's no financial consequence for vehicle wear.

**Recommendation:** On delivery, if vehicle health is below a threshold, show estimated repair cost on the payout receipt. This doesn't need to be deducted automatically — just displaying it reinforces realism. Players learn that rough driving costs money.

### 3.3 Weather Effects on Driving

**Gap:** Weather is only mentioned for surge pricing triggers. No gameplay impact.

**Recommendation:** Add weather-aware driving conditions:
- Rain: reduced traction for tankers and livestock trailers (increased cargo shift chance)
- Fog: reduced visibility — time window extended by 10% as a grace
- Snow (if modded): mandatory chain requirement for mountain routes, speed penalty

This pairs naturally with your existing cold chain and livestock systems.

### 3.4 Random DOT Roadside Inspections

**Gap:** Weigh stations are the only inspection point. Real trucking involves random roadside stops.

**Recommendation:** Add a low-probability random inspection event that triggers when a Tier 2/3 truck passes certain highway zones. Same mechanics as weigh station but triggered randomly. Pass = +3% bonus (stacks with weigh station). Fail = warning logged to BOL. This creates tension on every highway segment, not just at fixed weigh stations.

### 3.5 Admin Panel / Economy Tuning Tools

**Gap:** No admin tools mentioned. On a live server, you'll need to adjust rates, trigger manual surges, investigate player disputes, and manage suspensions.

**Recommendation:** Add an admin system (even if Phase 9+):
- `/truckadmin` command for staff
- View any player's trucking profile, active load, reputation
- Manual surge creation/cancellation
- Economy rate overrides (multiplier that applies on top of config values)
- Force-complete or force-abandon stuck loads
- View BOL audit trail for dispute resolution
- Discord webhook for admin actions

### 3.6 Persistent Truck Ownership / Garage Integration

**Gap:** Owner-operator bonus exists (20-30%) but there's no mention of how vehicle ownership is determined or how it integrates with your server's garage system.

**Recommendation:** Define the `is_rental` detection logic. Most QBX servers use `jg-advancedgarages` or `qbx_garages`. The script should check vehicle ownership via your garage export. Document the expected export signature so server owners can adapt.

```lua
-- server/missions.lua
function IsOwnerOperator(source, vehiclePlate)
    -- Option 1: Check QBX owned vehicles
    local player = exports.qbx_core:GetPlayer(source)
    local vehicles = MySQL.query.await(
        'SELECT plate FROM player_vehicles WHERE citizenid = ?',
        { player.PlayerData.citizenid }
    )
    for _, v in ipairs(vehicles) do
        if v.plate == vehiclePlate then return true end
    end
    return false
end
```

---

## 4. REALISM ENHANCEMENTS FOR RP

### 4.1 Pre-Trip Inspection as Repeatable Compliance Action

**Current:** Pre-trip inspection only exists in the CDL tutorial (Stage 1). After that, `pre_trip_completed` is referenced in the compliance bonus but there's no described mechanic for doing it on regular loads.

**Recommendation:** Make pre-trip a quick optional interaction at origin before departure. 3-4 checkpoints, ~45 seconds total. Awards the +3% compliance bonus. Skipping it is fine — you just miss the bonus. This gives veteran drivers a meaningful micro-ritual before every haul without being tedious.

```lua
-- client/interactions.lua
function StartPreTrip(activeLoad)
    local checkpoints = { 'tires', 'lights', 'brakes', 'coupling' }
    for i, check in ipairs(checkpoints) do
        local success = lib.progressBar({
            duration = 3000,
            label = 'Inspecting: ' .. check,
            canCancel = true,
        })
        if not success then return end -- cancelled, no bonus
    end
    TriggerServerEvent('trucking:server:preTripComplete', activeLoad.bol_id)
end
```

### 4.2 Backing/Docking Difficulty at Delivery

**Current:** Delivery is described as "arrives at destination zone → NPC interaction." No mention of actual docking difficulty.

**Recommendation:** Add delivery zone size variation by tier:
- T0: Large zone (easy pull-up, van parking)
- T1: Medium zone (standard loading dock)
- T2: Smaller zone (precision dock, must back in)
- T3: Tight zone (requires skilled backing)

This is the biggest differentiator between casual and skilled truckers in RP. The CDL tutorial teaches backing (Stage 5) — this is where that skill pays off in real gameplay.

### 4.3 CB Radio / Trucker Channel

**Recommendation:** Add a proximity-based or channel-based communication layer for truckers. This could be as simple as:
- Truckers with active loads auto-join a shared radio channel
- Convoy members get a private channel
- Dispatchers broadcast to company channel

Integration point: export to your server's radio script (pma-voice, mumble-voip, etc.). This creates organic social interaction without forcing players into Discord.

### 4.4 Truck Stop Amenities

**Current:** Rest stops exist only for livestock welfare recovery.

**Recommendation:** Expand truck stops as social hubs:
- Fuel (integration with fuel script)
- Repair (basic repair, cheaper than LS Customs)
- Food/coffee (if your server has a needs system — optional integration)
- Board access terminal (check board without returning to dispatch)
- Insurance purchase terminal
- Other trucker proximity — encourages organic RP

### 4.5 Night Hauling Consideration

**Recommendation:** Add a time-of-day modifier to the payout engine. Night runs (22:00–06:00) could receive a +5-8% premium. This is realistic (night freight pays more IRL) and incentivizes playing during off-peak hours, which helps server population balance.

```lua
-- config/economy.lua addition
Economy.NightHaulPremium = 0.07  -- +7% between 22:00-06:00
Economy.NightHaulStart = 22
Economy.NightHaulEnd = 6
```

---

## 5. BALANCE & ECONOMY TUNING

### 5.1 Payout Rate Sanity Check

The rates need stress-testing against your server's economy. Here are some example calculations:

**Tier 0 — Van delivery:**
- $35/mi × 8 miles = $280 → floor of $300 applies
- Time: ~5-8 minutes of driving
- Effective hourly rate: ~$2,250-$3,600/hr

**Tier 2 — Cold chain with full compliance:**
- $90/mi × 16 miles = $1,440
- Weight mult (30,000 lbs): ×1.30 = $1,872
- Owner-op: ×1.25 = $2,340
- Time bonus (under 80% window): ×1.15 = $2,691
- Compliance (weigh + seal + BOL + pre-trip + manifest + cold chain clean): +26% → ×1.26 = $3,390
- Time: ~20-25 minutes
- Effective hourly rate: ~$8,136-$10,170/hr

**Question:** Is $8,000-$10,000/hr appropriate for your server economy? Compare against other jobs (police salary, mechanic income, drug runs). If other legal jobs pay $3,000-$5,000/hr, trucking at Tier 2 is already very lucrative. The compliance stacking is powerful.

**Recommendation:** Add a global `Economy.ServerMultiplier` that scales all payouts. This lets you tune the entire economy with one number during testing without touching individual rates:

```lua
Economy.ServerMultiplier = 1.0  -- Tune this during testing
-- Applied as final step: payout = math.floor(payout * Economy.ServerMultiplier)
```

### 5.2 Compliance Stack Cap May Be Too Generous

`MaxComplianceStack = 0.36` (36% max bonus) is achievable by any skilled solo driver doing cold chain with a weigh station stop. Combined with owner-op bonus and time bonus, a perfect run stacks to roughly +76% above base. This may make imperfect runs feel punishing by comparison.

**Recommendation:** Consider reducing the cap to 0.25 (25%) or making the individual bonuses slightly smaller. The goal is that compliance feels rewarding but not mandatory. A clean, no-bonus run should still feel worthwhile.

### 5.3 Insurance Hard Block — New Player Friction

Requiring insurance before accepting any load is realistic but creates a cold-start problem. A new player who just wants to try trucking has to: find dispatch desk → understand insurance → spend money → then take first load.

**Recommendation:** Exempt Tier 0 from insurance requirements. T0 has a flat $300 deposit with no percentage — the financial exposure is low. Let new players jump straight into van deliveries. Once they get their Class B CDL and move to T1, they've learned the system and can handle the insurance requirement.

### 5.4 Livestock Rest Stop Duration

8 minutes for a water stop and 15 minutes for a full rest stop are very long in gameplay terms. A player standing still for 8 minutes watching a progress bar is not engaging content.

**Recommendation:** Cut durations significantly:
- Quick stop: 30 seconds (currently 2 min)
- Water stop: 2 minutes (currently 8 min)
- Full rest: 5 minutes (currently 15 min)

Alternatively, allow the player to do other things during the rest stop (check phone, interact with truck stop services) with the rest timer running in the background rather than as a held progress bar.

### 5.5 Leon Unlock Threshold

15 Tier 3 deliveries is a very high bar. T3 loads require Class A CDL + endorsements/certs, which already require significant T1/T2 grinding. By the time a player has 15 T3 deliveries, they've likely been trucking for weeks of real-time play.

**Recommendation:** Consider 8-10 T3 deliveries, or alternatively, count a combination (e.g., 20 total T2+ deliveries). The criminal content is engaging endgame content — you want players to reach it while still excited about the script, not after they're already burnt out on the grind.

---

## 6. STRUCTURAL / ARCHITECTURAL RECOMMENDATIONS

### 6.1 State Recovery on Player Reconnect

Section 1 mentions "On resource restart, active loads are reloaded from database and mission state is restored." But there's no mention of **player reconnect** handling. What happens when a single player crashes and rejoins mid-delivery?

**Recommendation:** On `playerConnecting` or `QBCore:Server:PlayerLoaded`, check `truck_active_loads` for the player's citizenid. If an active load exists:
1. Restore the HUD overlay
2. Resume all monitoring (seal, temp, welfare)
3. Notify the player: "Active load restored — BOL #XXXX"
4. Do NOT penalize the player for the disconnect gap (freeze timers during disconnect)

This is critical for player experience. Crashes happen. Losing a 20-minute delivery to a crash feels terrible.

### 6.2 Board Load Generation — Variety

The guide describes board composition by count per tier per region but doesn't discuss how loads are generated to ensure variety. If the generation is purely random from the cargo pool, players may see repetitive loads.

**Recommendation:** Implement a "no-repeat" rule: on board refresh, track the previous board's cargo types. New board must include at least 2 cargo types not present on the previous board. This ensures variety across refreshes.

### 6.3 Database Growth Management

Several tables will grow indefinitely:
- `truck_bol_events` (every state change, never deleted)
- `truck_driver_reputation_log`
- `truck_shipper_reputation_log`
- `truck_webhook_log`
- `truck_integrity_events`

**Recommendation:** Add a retention policy. Archive or delete records older than 30-60 days for log tables. Keep `truck_bols` and `truck_loads` indefinitely (they're the core audit trail) but prune event logs. Add this to the maintenance cycle:

```sql
-- Monthly cleanup (add to maintenance queries)
DELETE FROM truck_bol_events WHERE occurred_at < UNIX_TIMESTAMP() - 2592000; -- 30 days
DELETE FROM truck_webhook_log WHERE created_at < UNIX_TIMESTAMP() - 604800; -- 7 days
DELETE FROM truck_integrity_events WHERE occurred_at < UNIX_TIMESTAMP() - 2592000;
```

### 6.4 NUI Framework Choice

The guide mentions "React or HTML UI." For FiveM NUI, React has significant bundle overhead.

**Recommendation:** Use **Svelte** or **Vue 3** (with Vite). Both produce smaller bundles, faster initial render, and are the standard in modern FiveM UI development. The ox_lib ecosystem uses Svelte internally. React works but is overkill for the 7 screens described.

### 6.5 Localization Architecture

`locales/en.json` is mentioned but not how it's consumed.

**Recommendation:** Use ox_lib's built-in locale system (`lib.locale`). It's already a dependency and handles fallback languages, interpolation, and is the QBX ecosystem standard. Don't build a custom locale loader.

---

## 7. CONTENT CONCERN — APPENDIX A

### 7.1 Criminal Supplier Ethnic Stereotyping

Appendix A explicitly ties criminal suppliers to real-world ethnic groups ("African-American organized distribution," "Italian-American," "Latino," "Russian," "Asian"). While GTA's world is satirical, tying criminal enterprise directly to ethnicity in a multiplayer RP context is different from Rockstar's single-player satire.

**Recommendation:** Rework the suppliers to use GTA-lore organizations or fictional backgrounds:
- Chamberlain → Families-affiliated (GTA gang, already in-lore)
- Ancelotti → Keep as-is (GTA IV Ancelotti family reference works)
- Aztecas → Varrios Los Aztecas (already a GTA gang, drop "Latino" label)
- Vespucci → Generic eastern European syndicate or just "private cold chain operator"
- Jade River → "Pacific Import/Export consortium" (remove ethnic reference)

The loads and mechanics stay identical — just remove the ethnic descriptors from the background text. The server owner can add their own lore flavor.

---

## 8. FEATURE ADDITIONS FOR COMPETITIVE EDGE

These go beyond parity with existing scripts and would make this the definitive trucking resource.

### 8.1 Dynamic Route Hazards

Add random events during transit that force decision-making:
- **Road closure** — Reroute adds distance but keeps you on schedule vs. wait
- **Accident scene** — Slow zone, optional stop to help (small rep bonus)
- **Police checkpoint** — BOL inspection, pass if clean (ties into existing system)
- **Mechanical issue** — Pull over for 60-second repair minigame or lose integrity over time

These break up the "drive from A to B" monotony that plagues every trucking script.

### 8.2 Seasonal/Weekly Cargo Demand

Rotate which cargo types are in high demand on a weekly basis. One week, cold chain is surging; the next, building materials are hot. This creates a reason to diversify skills rather than grinding one cargo type.

### 8.3 Achievement/Milestone System

Track milestones beyond reputation:
- "First 100 deliveries" badge
- "Million-mile driver"
- "Zero-incident month"
- "All shippers at Trusted+"

Display on profile. Optional Discord webhook on achievement. Gives long-term goals beyond the payout grind.

### 8.4 Mentor/Ride-Along System

Allow experienced drivers (Professional+ rep) to invite new players on a ride-along. The mentor gets a small bonus per delivery during the ride-along. The mentee learns the systems. This solves the onboarding problem organically through RP.

---

## 9. DEVELOPMENT MILESTONE ADJUSTMENTS

### 9.1 Phase 1 May Be Too Large

Phase 1 includes 17 tasks including a full NUI board, payout calculation, deposit system, BOL system, and HUD overlay. That's a lot for a "foundation" milestone.

**Recommendation:** Split Phase 1:
- **Phase 1a — Database & Backend:** Tables, configs, load generation, board state (server-only, testable via commands)
- **Phase 1b — Player Loop:** NUI board, load acceptance, HUD, delivery, payout

This lets you validate the backend logic before building UI, catching economy bugs early.

### 9.2 Move Insurance Earlier

Insurance is in Phase 3 but it's a hard block on load acceptance. If you're testing T1 loads in Phase 2, you'll be bypassing the insurance check or not having it — which means Phase 3 integration may break Phase 2 flows.

**Recommendation:** Move insurance to Phase 2, at least the basic single-load policy. The claim system and Vapid office can stay in Phase 3.

### 9.3 Add a Testing/QA Phase After Each Milestone

Each milestone ends with a test case but no dedicated QA phase. In practice, integration bugs surface when systems interact (e.g., convoy + cold chain + weigh station all active simultaneously).

**Recommendation:** After each milestone, add a "regression test" step: replay all previous milestone test cases to ensure nothing broke. This is especially critical after Phase 4 (certifications change board access rules) and Phase 5 (criminal system interacts with reputation).

---

## 10. SUMMARY — PRIORITY ACTIONS

| Priority | Item | Section |
|----------|------|---------|
| **Critical** | Fix client-side timer spoofing — move all timing to server | 1.1 |
| **Critical** | Fix `MySQL.scalar.await` → `MySQL.single.await` | 2.1 |
| **Critical** | Fix QBX API usage (not qb-core events) | 2.2 |
| **Critical** | Add server-side event validation to all handlers | 1.4 |
| **High** | Add fuel consumption integration | 3.1 |
| **High** | Add pre-trip inspection as repeatable action | 4.1 |
| **High** | Add player reconnect state recovery | 6.1 |
| **High** | Add admin panel to milestones | 3.5 |
| **High** | Rework criminal supplier ethnic descriptions | 7.1 |
| **Medium** | Add delivery zone size scaling by tier | 4.2 |
| **Medium** | Reduce livestock rest stop durations | 5.4 |
| **Medium** | Add `Economy.ServerMultiplier` for tuning | 5.1 |
| **Medium** | Exempt T0 from insurance requirement | 5.3 |
| **Medium** | Add database retention policy | 6.3 |
| **Medium** | Lower Leon unlock to 8-10 T3 deliveries | 5.5 |
| **Low** | Add weather driving conditions | 4.3 |
| **Low** | Add night haul premium | 4.5 |
| **Low** | Add dynamic route hazards | 8.1 |
| **Low** | Add achievement system | 8.3 |
| **Low** | Consider Svelte over React for NUI | 6.4 |

---

*This script has the potential to be the most comprehensive trucking resource in the FiveM ecosystem. The foundation is excellent — the recommendations above are about hardening it for production, filling competitive gaps, and ensuring the economy holds up under real player behavior.*
