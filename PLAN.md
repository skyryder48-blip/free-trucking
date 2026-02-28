# Remaining Work Plan

## Phase A: Remove the Milk Rule (5 code files + guide)

Completely strip Leon's dairy prohibition. All files, all references.

### Files to edit:

1. **config/leon.lua** — Remove lines 53-80:
   - `THE MILK RULE` comment block
   - `Config.LeonDairyBlock = true`
   - `LeonConfig.DairyBlockList` table
   - `LeonConfig.IsDairyCargo()` function

2. **config/config.lua:166** — Remove `Config.LeonMilkRule = true`

3. **config/cargo.lua:419-421** — Remove `drain_item = 'milk_jug_bulk'` and the `leon_available = false` dairy comment. Replace drain_item with a generic item or remove if tanker-only.

4. **client/leon.lua** — Remove:
   - `ShowMilkDismissal()` function (lines 153-168)
   - Dairy check block in interaction loop (lines 359-366)

5. **server/leon.lua** — Remove:
   - Comment "Leon does not deal in dairy — the milk rule" (line 7)
   - `DAIRY_KEYWORDS` table (lines 94-98)
   - `IsDairyCargo()` function (wherever defined)
   - Milk rule check in `GenerateSingleLeonLoad()` (lines 342-345, 355-358)
   - `maxAttempts` comment about milk rule rejections (line 470)
   - Milk rule check in load type registration (lines 907-911)

6. **sql/items.lua:289-299** — Remove `milk_jug_bulk` item definition

7. **DEVELOPMENT_GUIDE TRUCKING.md** — Remove 4 milk/dairy references (lines 258, 2529, 3475-3476, 3479)

---

## Phase B: Replace os.time() with MySQL UNIX_TIMESTAMP() + GetGameTimer()

### Strategy:

**For database timestamps (inserts/updates/queries):**
- Move timestamp generation into SQL using `UNIX_TIMESTAMP()`
- Instead of passing `os.time()` as a bind parameter, use `UNIX_TIMESTAMP()` directly in the SQL string
- Example: `VALUES (?, os.time())` → `VALUES (?, UNIX_TIMESTAMP())`

**For in-memory elapsed time (cooldowns, stationary timers, expiry checks):**
- Use `GetGameTimer()` which returns milliseconds since resource start
- All duration comparisons convert to ms (e.g., `600` seconds → `600000` ms)
- Timer tables store `GetGameTimer()` values instead of `os.time()` values

**For GlobalState.serverTime sync:**
- Fetch `UNIX_TIMESTAMP()` from DB on resource start and periodically
- Push to `GlobalState.serverTime` for client consumption
- Keeps client-side time checks working without os.time()

**For os.date() calls (hour checks, formatting):**
- `os.date()` calls that used `os.time()` as input: feed the DB-sourced timestamp instead
- `os.date('%H')` with no argument: replace with DB-sourced time or game time native

### Files to edit (18 server files + shared/utils + guide):

1. **shared/utils.lua** — Core change:
   - Replace `GlobalState.serverTime = os.time()` with DB-fetched `UNIX_TIMESTAMP()`
   - Replace `GetServerTimestamp()` server branch from `os.time()` to DB-synced value
   - Add startup DB sync + periodic refresh thread
   - Add `GetElapsedTimer()` wrapper around `GetGameTimer()` for clarity

2. **server/database.lua** (~20 os.time calls) — Replace all bind param timestamps with `UNIX_TIMESTAMP()` in SQL

3. **server/main.lua** (~12 calls) — Replace timer tracking, GlobalState sync, reconnect logic

4. **server/missions.lua** (~12 calls) — Replace reservation cooldowns, seal timestamps, delivery timestamps

5. **server/leon.lua** (~12 calls) — Replace load generation timestamps, board refresh, expiry checks

6. **server/admin.lua** (~10 calls) — Replace audit timestamps, suspension calculations

7. **server/insurance.lua** (~7 calls) — Replace policy timestamps, claim processing

8. **server/reputation.lua** (~10 calls) — Replace score update timestamps, decay checks, suspension

9. **server/cdl.lua** (~10 calls) — Replace test timing, license expiry, lockout calculations

10. **server/bol.lua** (~3 calls) — Replace BOL issuance timestamps

11. **server/convoy.lua** (~4 calls) — Replace convoy formation, delivery timestamps

12. **server/company.lua** (~5 calls) — Replace invite expiry, membership timestamps

13. **server/loads.lua** (~5 calls) — Replace board posting, load expiry timestamps

14. **server/temperature.lua** (~12 calls) — Replace excursion tracking, fault timestamps

15. **server/explosions.lua** (~6 calls) — Replace sequence timing, registration timestamps

16. **server/military.lua** (~15 calls) — Replace contract timestamps, escort timing

17. **server/exports.lua** (~4 calls) — Replace lockout timestamps

18. **server/webhooks.lua** (~2 calls) — Replace webhook timestamps

19. **server/payout.lua** (~1 call) — Replace night haul hour check

20. **DEVELOPMENT_GUIDE TRUCKING.md** — Update all os.time() references to new pattern (~20 locations)

---

## Phase C: Fix Blocking Issues

1. **Create `config/cdl.lua`** — 95+ CDL test questions with comedy tone (already referenced in fxmanifest.lua, resource won't start without it)

2. **Add `Config.TruckStops`** to `config/config.lua` — 6 truck stop locations per guide Section 31 (client/interactions.lua:748 reads this)

3. **Fix `MySQL.scalar.await`** in `server/admin.lua` — 6 instances. These are aggregate queries (COUNT, SUM) where `scalar` is technically correct, but the guide says to use `MySQL.single.await`. Align with guide.

---

## Phase D: Update Development Guide

Remove all os.time() from example code and replace with new patterns. Remove milk rule references. Ensure guide matches the actual codebase state.

---

## Execution Order

1. Phase A (milk rule) — smallest scope, clean removal
2. Phase C (blocking fixes) — config/cdl.lua, TruckStops, scalar.await
3. Phase B (os.time replacement) — largest scope, systematic file-by-file
4. Phase D (guide updates) — final alignment pass
