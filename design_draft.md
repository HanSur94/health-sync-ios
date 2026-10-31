# HealthSync: Apple Health to the local MCP server, without a paid app

Author: Hannes Suhr + Hermes · 2026-10-31 · Status: draft, implementation compiles

## Problem

Apple Health has no remote API. HealthKit data can only be read by an app running on the
iPhone, after the owner grants per-type read permission. Everything downstream of the phone
already works in this household: a `health-export-mcp` server on the NAS exposes 14 query
tools to the agent, and a launchd job copies data from the Mac to the NAS.

The missing piece is the producer. The one that works, MetricBridge, costs €24.99 once. The
free substitutes are either manual (Apple's "Export All Health Data" zip, minutes of
generation, then a converter) or fragile (a Shortcuts graph with a static type picker per
action and no per-day grouping primitive, which gets slow and fails quietly).

What is needed is a small app that reads HealthKit on the phone, aggregates it per local
day, and drops two JSON files into a folder that already syncs to the Mac.

## Overview

HealthSync is a single-screen iOS app, iOS 17 or later, read-only on HealthKit. On launch and
on a best-effort background refresh it:

1. requests HealthKit read permission for 18 quantity types plus sleep analysis and workouts;
2. runs one statistics query per quantity type over the last 730 days, aggregating per local
   calendar day (sum for cumulative metrics, mean for the rest);
3. converts sleep segments into hours per wake day;
4. writes `.health-cache.json` and `.health-workouts-cache.json` into a folder the owner picks
   once, through a security-scoped bookmark;
5. the existing Mac job copies those files to the NAS, where the unchanged MCP server reads
   them.

No account, no server of ours, no dependency, no third-party SDK.

## Goals

- Produce the exact cache schema `healthstore.mjs` already reads, so no server change is needed.
- Work on a free Apple developer account. That excludes an iCloud container entitlement, which
  is why delivery uses a folder the owner picks instead.
- Cover what the MCP tools actually query: steps, energy, distance, heart rate, HRV, resting
  heart rate, respiratory rate, oxygen saturation, body composition, VO₂ max, walking speed,
  exercise and stand time, water, sleep, workouts.
- One aggregation rule per metric, stated in the code, so a number in the agent's answer traces
  back to a rule rather than a guess.

## Non-Goals

- Writing to HealthKit. The app has no write permission, by design.
- The optional context files (`health-events.json`, `health-profile.json`,
  `health-sessions.json`, `health-cycles.json`, `health-days.json`). The server reports their
  absence explicitly; adding them is a separate feature.
- Intraday data (`health-intraday.json`).
- A dashboard, charts, or any UI beyond a folder button, an export button and a status line.
- App Store distribution.
- Replacing the Python converter. Apple's manual export stays as the fallback path.

## Technical Plan

### Data flow

```
iPhone                          iCloud Drive                Mac                  NAS
┌──────────────────────┐        ┌──────────────┐     ┌──────────────┐   ┌────────────────────┐
│ HealthSync           │        │ HealthSync/  │     │ launchd      │   │ /volume1/docker/   │
│  HKStatistics        │ write  │ .health-     │sync │ healthsync-  │tar│ hermes/data/health │
│  CollectionQuery  ───┼───────▶│ cache.json   │────▶│ nas.sh       │──▶│ .health-cache.json │
│  sleep samples       │        │ .health-     │     │ (tar | ssh)  │   │ .health-workouts-  │
│  workouts            │        │ workouts-    │     │              │   │ cache.json         │
└──────────────────────┘        │ cache.json   │     └──────────────┘   └─────────┬──────────┘
                                └──────────────┘                                  │ mount
                                                                        ┌─────────▼──────────┐
                                                                        │ health-export-mcp  │
                                                                        │ 14 MCP tools       │
                                                                        └────────────────────┘
```

The Mac job does not change shape, only its source: it reads `HEALTH_SRC` (default
`~/Tools/health-data`) and the folder the iPhone writes to is pointed at with that variable.
No code change is required for the transport.

### Components

**Metric table (`SPECS`).** 18 rows: HealthKit identifier, cache name, unit, cumulative flag.
One place to add a metric. The cache names are the server's own vocabulary, taken from
`ALIASES` in `healthstore.mjs` and from the demo dataset, not invented: `step_count`,
`walking_running_distance`, `active_energy`, `weight_body_mass`, `exercise_time`,
`heart_rate_variability`, `resting_heart_rate`, … An earlier draft used `distance_walking_running`
and `body_mass`, which the alias map does not know, so `query_health_data("my weight")` would
have failed on a file that looked correct. The unit per metric is a second, smaller mapping in
`Spec.unit(for:)`; it is not derived from the table, and this document says so instead of
claiming a single source of truth.

**Aggregation.** One `HKStatisticsCollectionQuery` per quantity type with a one-day interval
anchored to local midnight. `.cumulativeSum` for steps, distance, energy, flights, exercise and
stand time, water; `.discreteAverage` for heart rate, HRV, resting and walking heart rate,
respiratory rate, oxygen saturation, body mass, body fat, VO₂ max, walking speed. Aggregation
happens inside HealthKit, so a two-year window costs roughly the same as a two-day window. This
is the reason the app exists rather than a Shortcut: Shortcuts has no per-day grouping
primitive and its per-sample loops are the slow part.

**Percentages.** `HKUnit.percent()` is already a 0..1 fraction: `HKQuantity(0.97, .percent)`
returns `0.97`. The cache stores fractions verbatim, so the app performs no conversion for
`%` metrics. The Python converter does divide by 100, and that is correct there: it reads
`export.xml`, where `unit="%"` really is 0..100. The two producers differ because their inputs
differ, not because one of them is being generous.

**Sleep.** Category samples whose value is one of the four "asleep" values, summed in hours and
credited to the local day of the sample's end date (the wake day). Awake and in-bed segments
are ignored. The rule is marked in the code with its ceiling: per-segment attribution would be
needed if sleep-by-hour ever matters.

**Workouts.** `HKSampleQuery` over `HKWorkout`; per workout: activity type raw value (Apple's
own numbers, 37 running, 13 cycling, 52 walking), start and end as ISO 8601 **with the local UTC
offset**, duration in seconds, active energy, distance, average and maximum heart rate,
elevation gain. Distance is read from the type that follows the activity (cycling ride,
swimming session, otherwise walking and running), falling back to the workout's `totalDistance`,
so a ride does not export as a workout without distance. The timestamps carry the local offset
because the server dates a workout by the first ten characters of its start string, and a `Z`
stamp would move any session starting before 02:00 local to the previous day.

**Delivery.** `UIDocumentPickerViewController` in folder mode; the returned URL is turned into
a bookmark stored in `UserDefaults`, resolved and re-scoped on every write. This is the one
unusual choice and it is deliberate: a security-scoped bookmark gives write access to a user
chosen iCloud Drive folder without an iCloud container entitlement, so the app works on a free
Apple ID.

**Background refresh.** `BGAppRefreshTask` with an earliest start six hours out, re-scheduled
on every launch, plus a plain export whenever the app opens. iOS decides when it actually runs,
and HealthKit cannot be read while the device is locked, so a background run on a locked phone
returns nothing. The app reports what happened instead of pretending: an empty result is an
error, not a success.

**Failure behaviour.** HealthKit reports no per-type read denial, so the only visible signal that
permissions were refused or the device was locked is a result with no metrics. In that case the
app throws and writes nothing, leaving the previous export in place; the old behaviour would have
replaced a good snapshot with a `_meta`-only file and the Mac job would have carried that to the
NAS. Both files are written under temporary names and then renamed, so a reader never sees a new
metrics file next to last cycle's workouts file.

### Cache schema produced (contract with the server)

```
.health-cache.json
{ "<metric>": { "unit": "ms", "cumulative": false,
                "daily": [ { "d": "2026-10-31", "v": 57.2 }, … ] }, …,
  "_meta": { "schema": 1, "app": "healthsync-ios",
             "requested": 18, "written": 17, "writtenAt": "…" } }

.health-workouts-cache.json
[ { "id", "name", "activityType", "start", "end", "duration",
    "activeEnergyBurned"?, "distanceMeters"?, "avgHeartRate"?, "maxHeartRate"?,
    "elevationAscendedMeters"?, "distanceSource" } ]
```

`_meta.schema` stays 1. A higher number makes the server refuse the file rather than report
wrong numbers, which is the intended failure mode.

## Alternatives Considered

**Buy MetricBridge (€24.99).** It works; it is what the pipeline was designed around. Rejected
because the request was to not buy an app, not because it is a worse program. Scored honestly it
wins on effort: one purchase, no build step, no re-signing, no maintenance. The design buys
something else with that money and should be judged on whether the trade is wanted.

**Shortcuts-only automation.** Free and permanent, no signing. Rejected after checking the
actual constraints: each Find Health Samples action carries one fixed sample type, so N metrics
mean N actions; there is no per-day grouping primitive, so the day loop is rebuilt in the graph;
heavy queries take minutes and fail quietly; HealthKit needs an unlocked device either way. The
result is a large graph that cannot be read or debugged months later.

**Apple's manual export plus the existing Python converter.** Works today and is verified. Kept
as the fallback, not as the answer, because "Export All Health Data" is manual and takes minutes
of generation on the phone.

**Sideloaded open-source apps (Pulso, DataDonor, HealthBridge).** Same Xcode signing burden, and
each writes its own schema, which would mean writing a converter for a format someone else
controls. No advantage over owning the ~420 lines.

**Writing to an iCloud container instead of a picked folder.** Cleaner, and impossible on a free
account: the iCloud entitlement requires a paid developer membership.

**LAN HTTP push from the app to the NAS.** Removes the Mac from the path, but needs a receiver
daemon on the NAS, token handling and a network route. The folder route reuses the transport that
is already in place and already verified.

## Detailed Implementation Plan

### Files

**`./project.yml`** — XcodeGen spec: one iOS application target, deployment target 17.0, bundle
id `de.hannessuhr.healthsync`, explicit Info.plist and entitlements files, code signing
automatic. Rationale: the project file is generated from a short readable spec instead of a
`project.pbxproj` nobody reviews by hand.

**`./HealthSync/HealthSyncApp.swift`** — the whole app, one file of about 450 lines: metric table,
aggregation, sleep, workouts, JSON writing, folder bookmark, UI, background task. Rationale: a
single file keeps the schema knowledge in one place; splitting it would add files without adding
clarity at this size.

**`./HealthSync/Info.plist`** — `NSHealthShareUsageDescription` (required or HealthKit access
silently fails), background mode `fetch` (the app uses no `processing` task),
`BGTaskSchedulerPermittedIdentifiers`
with `de.hannessuhr.healthsync.refresh`, portrait only. Rationale: the identifiers string must
match the constant in the Swift file exactly; mismatches crash at registration.

**`./HealthSync/HealthSync.entitlements`** — `com.apple.developer.healthkit`. Rationale: without
the entitlement, `requestAuthorization` fails regardless of the Info.plist string.

**`./HealthSync.xcodeproj/`** — generated by `xcodegen generate`. Not edited by hand; regenerated
whenever `project.yml` changes.

**`./docs/designs/health-sync-ios.md`** — this document, once approved. Rationale: the project
directory is the canonical home; `design_draft.md` is the scratch copy.

**`~/Tools/healthsync-nas.sh`** — one change: expand a leading `~` in `HEALTH_SRC`, because
launchd does not expand environment values. The source stays `${HEALTH_SRC:-$HOME/Tools/health-data}`.
Rationale: one knob selects the producer; it must survive being set by launchd as well as by a
shell.

**`~/Library/LaunchAgents/com.hannes.healthsync.plist`** — add an `EnvironmentVariables` block with
an absolute `HEALTH_SRC`. Rationale: without it the variable never reaches the job, so the
documented knob does nothing and the job reads a default directory that may not be the one the
app writes to.

### Build and signing

1. `cd ~/Documents/10_Projects/health-sync-ios && xcodegen generate`
2. Open `HealthSync.xcodeproj`, select the target's Signing & Capabilities, pick the personal
   team, and confirm the HealthKit capability has no red errors.
3. Connect the iPhone, select it as the run destination, Run. First launch asks for Health
   permission; grant read for all types.
4. In the app: "Ordner wählen (iCloud Drive)", create and pick a folder `HealthSync`.
5. On the Mac: point the sync source at
   `~/Library/Mobile Documents/com~apple~CloudDocs/HealthSync` and run the sync once.
6. `get_mcp_status` in the agent must report `ok: true` with a `lastDataDate` of today.

### Acceptance criteria

The export counts as working only when all of these hold, checked on the Mac after one sync:

- `node server.mjs --doctor` with `HEALTH_DATA_DIR` on the synced directory prints `cache schema 1`
  and a metric count of at least 10 (18 is the full table; a fresh phone may have no data for some).
- `get_mcp_status` returns `ok: true`, `metricCount` equal to the doctor count, and a
  `lastDataDate` equal to the export day in local time.
- `get_health_metrics` for `step_count` with `agg: sum` returns a number within 10 % of the Health
  app's own step total for the same day, on a day with ordinary activity. A larger deviation means
  the sum rule, not the data, is wrong.
- `get_health_metrics` for `blood_oxygen_saturation` returns a value between 0.90 and 1.00. A value
  below 0.5 is the double-conversion bug, fixed here, reappearing.
- A workout created in the last three days appears in `get_workouts` with a `distanceMeters` value
  above zero when the activity was a run, walk or ride.
- The launchd job's log is empty and its exit status is 0 on the next scheduled run.

### Test plan

Checks that must be run, each with the failure it catches:

| Case | Expected | Catches |
|---|---|---|
| Fresh install, no folder chosen | permission sheet appears on first tap | authorize-after-folder-guard ordering |
| Deny Health permission, tap export | status shows an error, no file written | a `_meta`-only file replacing good data |
| Phone locked during a background run | nothing written, previous files intact | empty-result overwrite |
| Delete the picked folder, tap export | error, no crash | missing-folder handling |
| Two workouts with the same start second | both rows present, distinct `id` | id collision |
| Sync while the app is writing | NAS receives a complete pair or the previous pair | half-updated pair |
| Run the converter and the app into the same folder | last writer wins, both valid | producer collision (accepted, documented) |
| First export into an empty folder | both files created | `replaceItemAt` needing an existing destination |
| Debug build launched with `-seed` | writes a fixed sample cache through the same `publish()` path | the writer, where HealthKit cannot run |

The Debug build accepts a `-seed` launch argument that writes four metrics and one workout through
`publish()`. It exists because HealthKit cannot execute in the simulator on a free account: an
unsigned build launches but has no HealthKit entitlement, and every entitled build is refused at
launch by `SBMainWorkspace`. The seeded output was accepted by the server (`--doctor`: schema 1,
4 metrics, 1 workout) and served correct values, including `blood_oxygen_saturation` as 0.97 and a
workout timestamp carrying `+01:00`.

The statistics/aggregation logic has no unit test framework here: it is a HealthKit query, not
pure code, so the acceptance numbers above are the test. The Python converter keeps its built-in
`--selftest` for the same schema rules it shares.

### Verification performed

- `xcodebuild -project HealthSync.xcodeproj -scheme HealthSync -sdk iphoneos
  -destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO build`
  → `BUILD SUCCEEDED`, app bundle in DerivedData. Compilation and linking are proven. Nothing
  about on-device behaviour is.
- The cache shape the app writes was accepted by the real server, tested with the **Python
  converter's** output, not the Swift writer: `node server.mjs --doctor` printed `cache schema 1`,
  6 metrics, 9 workouts, and live tool calls returned `get_mcp_status` `ok:true`, a step sum
  matching the source data exactly, a working `get_trends`, 9 workouts, and a percentage served as
  a fraction. Those numbers came from a synthetic export in `/tmp`, so they prove the contract and
  the server, not the live pipeline.
- Transport Mac → NAS verified by checksum on both ends, with throwaway test data that was deleted
  afterwards and never touched `/volume1/docker/health-export/data`.

### Verification still required, on device

- First run: permission sheet, export completes, both files appear in the picked folder.
- The acceptance criteria above, against real data.
- `vo2_max` (`mL/min/kg`) and `walking_speed` (`km/hr`) are the only units built by hand rather
  than taken from a HealthKit constant; they stay unverified until a sample arrives.
- Background refresh actually firing. HealthKit cannot be read while locked, so a run on a locked
  phone is expected to fail and to leave the previous files in place.

### Rollback

The previous producer is untouched. To go back: set `HEALTH_SRC` in the launchd plist to
`/Users/you/Tools/health-data`, export from the Health app, run
`python3 ~/Tools/apple-export-to-cache.py ~/Downloads/export.zip`, and let the job sync. No server
change and no data migration is involved, because both producers write the same two filenames.

### Known trade-offs

- Free-tier provisioning expires every seven days; the app stops launching until it is re-signed
  from Xcode. That is 52 re-signs a year against a €24.99 one-time purchase, and it is the largest
  recurring cost in this design. A paid membership removes it at €99/year, four times the app that
  was avoided. If weekly re-signing is unacceptable, this design is the wrong one.
- "No cloud" is imprecise. If the picked folder is in iCloud Drive, the health files are stored in
  iCloud; the promise is only that no third party and no server of ours is in the path. Choosing
  "On My iPhone" avoids even that, at the cost of no automatic handoff to the Mac.
- Two producers write the same two filenames. They must not share an output folder: the last writer
  wins, and a manual export can silently replace fresher app data. Pick one producer per folder;
  `HEALTH_SRC` selects which one the Mac job reads.
- The schema knowledge exists twice: in `apple-export-to-cache.py` and in `SPECS`. A change to
  `healthstore.mjs` must be applied to both. Stated here so it is a decision, not a surprise.
- `BGAppRefreshTask` is best effort. The app cannot promise a daily file without being opened; iOS
  decides, and the manual button is the fallback.
- The app writes the pair as two renames, which is atomic per file, not across the pair. iCloud
  syncs the two files independently, so a reader can briefly see new metrics beside old workouts.
  A shared generation stamp would make that detectable; it is not worth a server change today.
