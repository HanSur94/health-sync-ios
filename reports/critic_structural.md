# Structural / data-flow critique — HealthSync iOS vs health-export-mcp

Scope: `design_draft.md` §1–163, `HealthSync/HealthSyncApp.swift`, `Info.plist`,
`HealthSync.entitlements`, `project.yml`, and the server contract in
`/Users/you/Tools/health-export-mcp/healthstore.mjs`, plus the proven reference
producer `~/Tools/apple-export-to-cache.py` and the transport `~/Tools/healthsync-nas.sh`.

Verdict: the shape is right — the app produces the two files the server reads, with the
names and units the existing converter already proved. One deterministic value bug and three
contract/coverage mismatches need fixing before this replaces the converter.

Counts: 1 BLOCKER, 4 MAJOR, 6 NIT.

## BLOCKER

### B1 — Percentages are divided by 100 twice; both `%` metrics are 100× too small
`HealthSyncApp.swift:233` converts with `HKUnit.percent()`, and `HealthSyncApp.swift:116`
then does `if spec.percent { v /= 100 }`.

HealthKit's percent unit is already a fraction. From the installed SDK header,
`iPhoneOS27.2.sdk/.../HealthKit.framework/Headers/HKUnit.h:226`:
`+ (instancetype)percentUnit;    // % (0.0 - 1.0)`.
Verified by running HealthKit on this Mac:
`HKQuantity(unit: .percent(), doubleValue: 0.97).doubleValue(for: .percent()) == 0.97`.

So `blood_oxygen_saturation` (SPECS line 33) is written as ~0.0097 and
`body_fat_percentage` (line 35) as ~0.025, i.e. "1 % oxygen" and "2.5 % body fat". The
server stores and serves fractions verbatim — `healthstore.mjs:15-17` ("0–1 FRACTIONS
(0.97 = 97 %) … don't ×100 again") with no read-side normalisation — so nothing downstream
can recover the value.

Root cause is a porting error from the Python converter, which divides by 100 correctly
because it reads `export.xml` where `unit="%"` really is 0..100
(`apple-export-to-cache.py:41,112-113`). The design repeats the wrong premise at
`design_draft.md:97-98` ("HealthKit returns 0..100 for `%` types"), and the "verification
already performed" evidence (`design_draft.md:218-222`, "the percentage handling all
correct") was obtained with the *converter*, a different code path — it never exercised
line 116.

Fix: delete line 116 (and the `percent` column from `Spec`), or drop `percent: true` and
leave the fraction as HealthKit returns it.

## MAJOR

### M1 — Workout distance is read from one hard-coded type, so cycling/swimming workouts export none
`HealthSyncApp.swift:172` only reads `HKQuantityType(.distanceWalkingRunning)`. A ride's
distance lives in `.distanceCycling`, a swim's in `.distanceSwimming`, so those rows carry no
`distanceMeters` at all. `design_draft.md:107` promises "distance" per workout without that
qualification, and the converter gets it right by reading the activity-agnostic
`totalDistance` (`apple-export-to-cache.py:150-152`). The server passes the key through
as-is (`healthstore.mjs:907-912`), so the loss is silent.

Fix: fall back to `w.totalDistance` (present in the SDK, deprecated but functional) or try
`.distanceCycling` / `.distanceSwimming` after the walking one.

### M2 — Workout timestamps are UTC, but the server buckets workout days from the string's first 10 chars as if they were local
`HealthSyncApp.swift:164-165` formats with `ISO8601DateFormatter.local`
(`HealthSyncApp.swift:242-248`), which never sets `timeZone`. `ISO8601DateFormatter` defaults
to GMT — confirmed by running it here: `default tz: GMT`, output `2026-10-31T16:22:19Z` while
`TimeZone.current` is `Europe/Berlin`.

The server does `String(w.start).slice(0, 10)` and documents the assumption explicitly:
"the first 10 chars of its ISO start (which carries the local UTC offset)"
(`healthstore.mjs:880-883`). With a `Z` stamp, any workout starting between 00:00 and 01:59
local (00:00–01:59 in winter, 00:00–02:59 in summer) is dated to the previous day and drops
out of a `start`/`end`-filtered `get_workouts` call for the day it actually happened. It also
makes workout days UTC while `dayKey` (`HealthSyncApp.swift:196-202`) writes local days —
the design's whole "local calendar day" premise (`design_draft.md:13-14` in the server, §Data
flow) is then only true for one of the two files.

Fix: `ISO8601DateFormatter.local.timeZone = .current` in the static initialiser.

### M3 — `SPECS` has 18 rows, the design claims 19 (twice)
`design_draft.md:25` ("19 quantity types"), `design_draft.md:84` ("19 rows"). Counted:
18 `.init(id:` entries (`HealthSyncApp.swift:20-37`). The missing 19th in the reference
producer is `sleep_duration_goal` (`apple-export-to-cache.py:39`). Not a runtime bug, but the
metric table *is* the coverage checklist the rest of the design and the on-device
verification are written against; an off-by-one there is how a metric silently never ships.

Fix: either add `sleepDurationGoal` or change both sentences to 18.

### M4 — A run that returns no data at all overwrites a good cache and reports success
`Exporter.run` (`HealthSyncApp.swift:77-98`) has no minimum-content guard: if every
statistics query returns an empty collection — read permission denied for some or all types,
HealthKit unavailable while locked, fresh install before the permission sheet is answered —
`metrics` still contains `_meta` and is written over the previous file, workouts as `[]`.
The UI then says "Fertig · …" (`HealthSyncApp.swift:300`) because no error was thrown. The
transport then tars that empty pair to the NAS (`healthsync-nas.sh:11-13`), so the served
snapshot is gone until a later run succeeds. HealthKit deliberately does not report read
denial per type, which is exactly why the writer needs a floor.

The task asks specifically about failure behaviour: a *thrown* query error is handled well —
nothing is written, so the previous pair survives. The empty-result case is the unhandled
one.

Fix: `guard metrics.count > 1 else { throw ExportError.writeFailed("no HealthKit data returned — keeping the previous export") }`
before the writes.

## NIT

- **N1 — the pair is not atomic.** `write` is atomic per file (`HealthSyncApp.swift:191-194`),
  and both payloads are fully built before the first write (`:95-97`), so a throw leaves the
  old pair intact. But between the two renames — and, more relevantly, across iCloud's
  per-file sync — a reader can see new metrics with last cycle's workouts. The only consumer
  that touches both files is `status()` (`healthstore.mjs:285,308`), and it only counts, so the
  blast radius is one stale workout list. A shared generation stamp (the workouts file has no
  `_meta` at all) would make the mismatch detectable without a server change.
- **N2 — legacy sleep value dropped.** `HealthSyncApp.swift:136-139` lists
  `asleepUnspecified/Core/Deep/REM` but not the pre-iOS-16 `HKCategoryValueSleepAnalysis.asleep`
  (raw 2), which the converter does include (`apple-export-to-cache.py:43-47`). If any older
  samples survive on the device those nights under-count. One line.
- **N3 — workout `id` can collide.** `HealthSyncApp.swift:161` uses the start instant only;
  the server's cursor key is `start#id` precisely because two workouts can share a start
  (`healthstore.mjs:851-854`). Add the activity type or a counter.
- **N4 — `distanceSource` is written but nothing reads it** (`HealthSyncApp.swift:167`,
  absent from `healthstore.mjs`). Harmless; it just is not part of the contract the design
  says the field names come from.
- **N5 — the design's alias-map claim is false.** `design_draft.md:85-87` says the cache names
  match "what `healthstore.mjs` and its alias map already understand". They match the
  converter, but `ALIASES` maps `weight → weight_body_mass` and
  `distance → walking_running_distance` (`healthstore.mjs:982-984`), while the app writes
  `body_mass` and `distance_walking_running`. `query_health_data("my weight")` therefore
  throws "unknown metric". Pre-existing with the converter's output, so not a regression —
  but the sentence is wrong and will mislead the next reader.
- **N6 — small stuff.** `UIBackgroundModes` declares `processing` with no `BGProcessingTask`
  (`Info.plist:15`). The background task reports `success: true` when there is no folder at all
  (`HealthSyncApp.swift:391-401`, early `return` looks like success). `dayKey` allocates a
  `DateFormatter` per point (~13k per export, `:197`). And the plan's on-device check "two
  files appear in the picked folder" (`design_draft.md` step 5) is not observable in Files —
  both filenames start with a dot.

## What checks out

- **Schema and `_meta`.** `metrics["_meta"] = {schema: 1, …}` (`HealthSyncApp.swift:92-93`)
  is stripped on read (`healthstore.mjs:141-144`) and `SUPPORTED_SCHEMA = 1` matches
  (`healthstore.mjs:114,122-129`), so the "a higher number is refused loudly" claim at
  `design_draft.md:134-135` is real.
- **The two hand-built units are correct.** Ran HealthKit on this Mac:
  `HKUnit.literUnit(with: .milli).unitDivided(by: kg.unitMultiplied(by: .minute()))`
  → `mL/min·kg` (identical to the `mL/min/kg` string in SPECS and to the converter's
  `apple-export-to-cache.py:37`), and
  `HKUnit.meterUnit(with: .kilo).unitDivided(by: .hour())` → `km/hr`, matching
  `apple-export-to-cache.py:38`. Values are identity conversions, not double-converted.
- **The rest of the unit table** (`HealthSyncApp.swift:221-239`) matches
  `apple-export-to-cache.py:20-39` metric for metric: names, cumulative flags, and units.
- **Sleep attribution** — endDate day, four asleep values, hours, `cumulative: true`
  (`HealthSyncApp.swift:136-146`) matches the converter (`apple-export-to-cache.py:104-105`)
  and the server's roll-up rule.
- **Workouts** — seconds for `duration`, numeric `activityType` plus a display `name`; the
  server accepts either form for filtering (`healthstore.mjs:871-878`) and passes rows
  through unchanged.
- **Info.plist / entitlements / code agree.** `BGTaskSchedulerPermittedIdentifiers` contains
  `de.hannessuhr.healthsync.refresh` (`Info.plist:16`), byte-identical to `REFRESH_ID`
  (`HealthSyncApp.swift:42`); `com.apple.developer.healthkit` is present
  (`HealthSync.entitlements:4`); `NSHealthShareUsageDescription` is present and
  `NSHealthUpdateUsageDescription` is correctly absent for a read-only app; `UIBackgroundModes`
  contains `fetch`, which `BGAppRefreshTask` needs.
- **Transport.** `healthsync-nas.sh` tars `-C "$SRC" .`, so the dot-prefixed cache files are
  included (a `*.json` glob would have silently skipped them), and `HEALTH_SRC` is honoured —
  `design_draft.md:78-80` is accurate.

## Bottom line

The architecture reproduces the converter's contract rather than inventing one; the defects
are in the ported details, not the shape. Ship-blocking: B1. Fix M1–M4 in the same pass —
each is a handful of lines — then do the on-device unit check the design already lists, this
time against the *app's* output rather than the converter's.
