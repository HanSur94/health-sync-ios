# Implementation Readiness Review — HealthSync

Reviewer: EGM implementation-readiness (stage 9), fresh context · 2026-10-31
Scope: `design_draft.md` lines 186–274 only. Checked against the four project files, the
sync script and launchd job, `healthstore.mjs`/`server.mjs`, and the live environment.
Standard: a competent engineer with no context must execute the plan on the first attempt,
making zero design choices.

**Verdict: not implementation-ready.** The six-step procedure cannot produce the state it
promises: the first-run permission dialog does not appear in the stated order, no step
triggers the first export, and "correct" is never defined with a number. There is no test
plan and no rollback. The app compiles; the procedure does not yet run.

**Counts: 4 BLOCKER, 9 MAJOR, 4 NIT.**

Premise check: Apple's supported-capabilities table lists HealthKit as available to the free
"Apple Developer" tier, so the account type is not the blocker. What is missing is enabling
the capability on the App ID; XcodeGen writes the entitlement file but does not register the
capability. Do not "fix" this by buying a membership before trying the capability toggle.

---

## BLOCKER

### B1. The first-run sequence cannot happen as written: no permission dialog, no export
**Evidence.** design:228–232 orders the work as: Run → "first launch asks for Health
permission; grant read for all types" → pick folder → point the Mac job at it. The code does
the opposite: `exportNow()` guards on a stored folder first and returns before
`authorize()` (`HealthSyncApp.swift:313–317`); `authorize()` is at `:324`; `setFolder()` only
saves the bookmark (`:303–311`), it does not export. `.task` calls `exportNow()` once on
launch (`:402–404`). On a fresh install there is no folder, so the launch path stops at
"Zuerst einen Ordner wählen" and HealthKit is never asked. After the owner picks a folder,
nothing happens until they tap "Jetzt exportieren" — a button the plan never mentions.
Step 5 then syncs a folder that has never been written.

**Why it fails.** The first-time implementer follows step 3, sees no permission sheet, and
starts debugging signing, entitlements or HealthKit availability. The actual cause is a
plan/code ordering mismatch, not a build failure.

**Fix.** Rewrite steps 3–5 in this order: install and launch → "Ordner wählen (iCloud
Drive)" → create/select `HealthSync` → tap "Jetzt exportieren" → grant "Turn On All" → wait
for "Fertig · HH:MM" → verify two files → only then change the Mac job. Alternatively move
`authorize()` above the folder guard so the permission prompt really is first-launch. Pick
one; the current text is neither.

### B2. No acceptance criteria with numbers: nobody can say whether the export is correct
**Evidence.** design:233 is the only pass condition: "`get_mcp_status` … must report
`ok: true` with a `lastDataDate` of today." `lastDataDate` is the maximum `daily[-1].d`
across metrics (`healthstore.mjs:282–309`), not the write time: a correct 08:00 export with
no sample yet today returns yesterday and fails the stated test. `ok` is
`names.length > 0 && pairing().ok` (`:293`), so a pairing lock also fails it for a reason
unrelated to the export. In this review the live tool returned
`{"ok":false,"source":"file /opt/data/health/.health-cache.json","metricCount":0,...}` —
a different server instance, not the NAS, another way the literal step fails while the file
is fine. design:251–256 asks for "two files appear" and "`--doctor`" with no expected
counts, date range, value comparison, file size or checksum.

**Why it fails.** "Two files appeared" is compatible with a `_meta`-only file, a file with
one metric, a stale file, or 97 stored as 97 instead of 0.97. The owner cannot distinguish a
correct export from a plausible one, which is the exact failure this project is replacing.

**Fix.** Add the pass/fail table in §"Acceptance criteria the plan must add". At minimum:
metric count and names, last date ≥ yesterday, step total and sleep hours versus the Health
app on three named days, percentages ≤ 1, VO₂ max and walking-speed ranges, workout start
offset and count, SHA-256 equality Mac↔NAS, and `source` containing the NAS path.

### B3. No test plan and no failure or edge cases; the risky conversions are explicitly untested
**Evidence.** design:249–256 is four manual observations, not cases. It admits `vo2_max`
(`mL/min/kg`) and `walking_speed` (`km/hr`) are "untested until real samples are exported"
(:252–254), yet these are the only hand-built `HKUnit` expressions
(`HealthSyncApp.swift:246–247`) and the two most likely to be silently wrong. There is no
test target, no fixture, no simulator path, and no case for denied permission, locked device,
missing folder, stale bookmark, iCloud eviction, DST, travel timezone, sleep crossing
midnight, an empty metric type, a workout without distance/HR, or a partial permission grant.
The unit-type switch still has a `default: return .count()` (`:248`) that writes plausible
garbage for a new metric; the plan says nothing about it.

**Why it fails.** The only runtime proof is one happy path. A wrong unit or a denied type
produces a file that parses and serves wrong numbers — the server has no way to know.

**Fix.** Add the matrix in §"Test plan the plan must add". A test target is not required;
a recorded fixture plus a `#if DEBUG` self-test, or the manual matrix with exact expected
values, is enough. Delete the `default:` case or make it `fatalError` so a new metric cannot
silently export as counts.

### B4. No rollback and no backup; the assumed baseline is not working
**Evidence.** design:214–221 changes the launchd job's source; design:231–232 runs the sync;
design:268–270 warns that two producers must not share a folder. No step backs up
`/volume1/docker/health-export/data/`, stops the job, restores the previous source, or
re-runs the converter. Observed at review time: the NAS health directory is empty
(`ssh … ls -la /volume1/docker/health-export/data/` → only `.` and `..`);
`~/Tools/health-data` does not exist; `/tmp/healthsync.log` contains
`ERROR: health data dir missing: /Users/you/Tools/health-data` at 17:01, 17:16 and
17:31. Step 5 ("run the sync once") fails before the app is involved, and there is no good
snapshot to roll back to.

**Why it fails.** The first bad app export overwrites the NAS files via `tar` with no copy to
return to. If the app is wrong, the owner has lost the last known-good cache and must
regenerate from a manual Apple Health export, which the plan never explains.

**Fix.** Add a pre-flight: `node server.mjs --doctor` against the current NAS dir, record
`metricCount`/`lastDataDate`; `ssh … 'cp -a health health.bak-$(date +%F)'` before the
switch. Add the rollback commands in §"Rollback procedure the plan must add". If the NAS is
intentionally empty, say so and define what "previous export" means.

---

## MAJOR

### M1. Signing versus the HealthKit capability: the order is left to the implementer, and XcodeGen overwrites the fix
**Evidence.** `project.yml` has no `DEVELOPMENT_TEAM` and no `SystemCapabilities`; the
entitlements file has the key (`HealthSync.entitlements:4–5`). design:208–209 says the
`.xcodeproj` is never edited by hand and is regenerated from `project.yml`; design:225–227
then says to pick the team and "confirm the HealthKit capability has no red errors." If the
capability tile is absent, "confirm" is not an action. If it is red, there is no branch for
"Provisioning profile doesn't include `com.apple.developer.healthkit`." Adding the capability
in Xcode edits the `.pbxproj`, which `xcodegen generate` discards. `xcodebuild
-showBuildSettings` confirms `DEVELOPMENT_TEAM` is empty in the generated project.

**Why it fails.** The most common first-run signing failure is an entitlement the profile
does not contain (`0xe8008015` / "profile doesn't include the HealthKit entitlement"). The
plan gives no remedy, and the stated regeneration rule destroys the usual remedy.

**Fix.** Put both in `project.yml` before generating:
`DEVELOPMENT_TEAM: <cert-id>` (the only Apple Development identity on this Mac, verified
with `security find-identity`) and the target attribute
`SystemCapabilities: { com.apple.HealthKit: { enabled: 1 } }`. Regenerate, then confirm the
capability tile. If the bundle ID is already registered to another team, change
`PRODUCT_BUNDLE_IDENTIFIER` and regenerate; do not fight the portal. Delete the hand-written
empty `com.apple.developer.healthkit.access` array (`HealthSync.entitlements:5`) — that is the
HealthKit *capabilities* entitlement (used for Clinical Health Records), not part of basic read
access, and an entitlement absent from the profile is an install-time rejection.

### M2. `HEALTH_SRC` is an unresolved "or"; the persistent job is never actually changed
**Evidence.** design:214–218: "the launchd plist's environment **or** a one-line default
change." Two different edits with different blast radius. The plist currently has no
`EnvironmentVariables` (verified with `plutil -p`); the script defaults to
`$HOME/Tools/health-data` (`healthsync-nas.sh:6`), which is missing. Step 5 says "run the sync
once" — a one-shot `HEALTH_SRC=… script` proves the path for that shell only; the 15-minute
job keeps using the default. The design's claim that the plist is "unchanged in mechanism"
(design:220–221) is false if the env-var route is chosen.

**Fix.** Choose the plist route and write the exact XML:
`EnvironmentVariables → HEALTH_SRC → /Users/you/Library/Mobile Documents/com~apple~CloudDocs/HealthSync`.
Then `launchctl bootout gui/$UID/com.hannes.healthsync`, `launchctl bootstrap
gui/$UID ~/Library/LaunchAgents/com.hannes.healthsync.plist`, `launchctl kickstart -k
gui/$UID/com.hannes.healthsync`, and check `/tmp/healthsync.log` for a clean run. The plist
route leaves the converter's default intact for rollback. Do not also change the script
default.

### M3. iCloud materialisation, folder disappearance and TCC are not handled
**Evidence.** design:214–218 and 231–232 point the Mac at
`~/Library/Mobile Documents/…`; design:247 says transport was verified, but that was a
different path (`~/Tools/health-data` or MetricBridge's folder), not iCloud Drive. The script
only checks `[ -d "$SRC" ]` (`healthsync-nas.sh:8`) and then tars everything (`:11`). If the
JSONs are evicted, the folder still exists and the tar ships `.health-cache.json.icloud`
placeholders or nothing; the NAS keeps the previous JSON and `lastDataDate` freezes with no
error. If the folder is renamed or deleted on the phone, the bookmark resolves to nothing and
`publish` throws (`HealthSyncApp.swift:206–218`); the app has no re-pick flow. A launchd agent
reading iCloud Drive may also need Full Disk Access for `/bin/bash`; the job has no UI to
prompt for it.

**Fix.** Before `tar`: `brctl download "$SRC"`; require
`[ -s "$SRC/.health-cache.json" ] && [ -s "$SRC/.health-workouts-cache.json" ]`, otherwise log
and exit non-zero **without touching the NAS**. Add this to step 5. If the log says "dir
missing" while Finder shows the folder, grant Full Disk Access to `/bin/bash` (or run the
script from a small signed helper) and retry. In the app, treat a failed write as "folder
unavailable — pick it again": surface a button that reopens the picker, and do not let the
background task retry forever with a dead bookmark.

### M4. Denied permission has no recovery path; partial grants silently shrink the cache
**Evidence.** design:228–229 says "grant read for all types." HealthKit does not report
per-type read denial, so a "Don't Allow" or a single toggle off returns no error; the app's
only guard is `metrics.count > 1` (`HealthSyncApp.swift:97–99`), which counts `_meta` plus one
metric as success, and the status line shows "Fehler: no HealthKit data returned, previous
export kept" (`:327–328`) in a German UI. The only fix is Settings → Health → Data Access &
Devices → HealthSync, which the plan never mentions. The same gap applies to workouts: an
empty `[]` from a denied workout type is written as a valid file and the server reports
`workoutCount: 0`.

**Fix.** Add a recovery step: Settings → Health → Data Access & Devices → HealthSync → turn
on the missing types ("Turn On All"), return, tap Export. Define the minimum expected set
(e.g. the nine core names in the acceptance table) and refuse to publish if fewer than N are
present, rather than `> 1`. State explicitly that denying a type removes it from the next
cache and from the server's `list_metrics`.

### M5. Folder choice is ambiguous, and the sync job tars the whole folder
**Evidence.** design:230–231: "create and pick a folder `HealthSync`" — it does not say
**under iCloud Drive**. The picker can select the iCloud Drive root or "On My iPhone." Step 5
assumes `~/Library/Mobile Documents/com~apple~CloudDocs/HealthSync`; "On My iPhone" makes
that path nonexistent. If the root is picked, `tar czf - -C "$SRC" .`
(`healthsync-nas.sh:11`) ships the entire iCloud Drive to the NAS — the iCloud Drive root
contains personal documents (the review listing shows several), so a root pick is a
data-exposure bug.

**Fix.** Specify the exact navigation: Browse → iCloud Drive → New Folder → `HealthSync`; do
not pick "On My iPhone" or the iCloud root. Change the tar to the two-file allowlist:
`tar czf - -C "$SRC" .health-cache.json .health-workouts-cache.json`. This also removes
`.DS_Store` and any unrelated file from the payload.

### M6. `get_mcp_status` and `--doctor` are not executable as written
**Evidence.** design:233, 256. `lastDataDate` is the max daily date, not `writtenAt`
(`healthstore.mjs:282–309`); a correct morning export returns yesterday. `ok` requires
`pairing().ok` (`:293`); if the NAS server has `PAIRING_SECRET`, `ok` is false until paired,
and HealthSync has no pairing UI. `doctor()` reads `HEALTH_DATA_DIR` (`server.mjs:399–436`,
`healthstore.mjs:31–39`), so `node server.mjs --doctor` in the repo reports the repo, not the
NAS. This review's live tool returned `source: file /opt/data/health/.health-cache.json` — a
different instance, `ok:false`, with no indication which server the plan meant.

**Fix.** Give the exact command, e.g.
`HEALTH_DATA_DIR=/volume1/docker/health-export/data node server.mjs --doctor` on the NAS (or
the `docker exec` equivalent), and assert `source` contains
`/volume1/docker/health-export/data/.health-cache.json`. Define `lastDataDate >= yesterday`,
not `== today`. Check `paired`/`locked` before interpreting `ok`. Add a
`node server.mjs status --max-age 36` gate so staleness is a non-zero exit, not a sentence.

### M7. Background refresh is not tested, and "firing" versus "expected to skip" is contradictory
**Evidence.** design:255: "Background refresh actually firing, and surviving a locked device
(expected to skip)." Those are two different outcomes with no way to force either. The app
registers in `didFinishLaunching` (`HealthSyncApp.swift:413`) and schedules 6 h out (`:436–437`)
— the mechanism is right — but the plan gives no debug trigger, no log, and no assertion.
design:273–274 admits it is best effort.

**Fix.** Test in LLDB with the app foregrounded:
`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"de.hannessuhr.healthsync.refresh"]`;
assert `writtenAt` moved. Then lock
the device and repeat: assert the previous files' mtimes are unchanged and the task completes
`false`. Add a last-run/status line the UI shows, so the owner can tell "not scheduled" from
"ran and failed."

### M8. The seven-day expiry has no maintenance step
**Evidence.** design:260–264 acknowledges 52 re-signs a year but the implementation plan has
no procedure. After expiry the app stops launching; the Mac job keeps shipping the last files
and `lastDataDate` ages. The folder bookmark survives a reinstall over the existing app, but
the plan does not say so, and the owner may re-pick unnecessarily.

**Fix.** Add a "day 6" step: connect the iPhone, open the project, select the device, Run;
launch the app and confirm the folder name still appears (bookmark intact); tap Export; check
`writtenAt`. Add the `status --max-age` gate so a missed re-sign is noticed by the agent, not
by a wrong answer weeks later.

### M9. Producer exclusivity is stated as a trade-off but not implemented
**Evidence.** design:268–270: "Pick one producer per folder." No step enforces it. The
converter writes `~/Tools/health-data` (`apple-export-to-cache.py:16`); the app writes the
iCloud folder. Switching `HEALTH_SRC` makes the job read one, but a manual converter run, a
restored default, or a stale `healthsync-nas.sh.bak` can put the old files back in the NAS
path. The plan does not say to disable the old output or mark the chosen producer.

**Fix.** After the NAS checksum passes, move `~/Tools/health-data` to
`~/Tools/health-data.disabled-$(date +%F)` (keep it for rollback) and leave the converter's
`-o` pointing there for manual use only. Add a one-line assertion in the script that
`$SRC` is the expected path (or a marker file) and refuse to run otherwise. Never run both
producers against the same folder.

---

## NIT

**N1.** design:196 says "423 lines"; `wc -l HealthSync/HealthSyncApp.swift` is 449. Update the
number or drop it — a line count is the first thing a reader checks and the first thing that
drifts.

**N2.** `com.apple.developer.healthkit.access` with an empty array
(`HealthSync.entitlements:5`) is not part of the basic HealthKit capability; Xcode adds it only
for Clinical Health Records. Remove it unless clinical records are wanted (they are a non-goal).

**N3.** `distanceSource` is `w.sourceRevision.source.name` (`HealthSyncApp.swift:169`), while
the server's fixtures use `'watch'` (`demo.mjs:143`). The plan's schema
(design:149–152) does not define the vocabulary. Either document it as a free-form device name
or write `watch`/`phone`; do not leave the server and the fixtures disagreeing.

**N4.** `UIBackgroundModes` contains `processing` (`Info.plist`) but there is no
`BGProcessingTask`; design:201 presents both as used. Drop `processing` or say why it is there.
Also use iOS's exact label "Turn On All" rather than "grant read for all types."

---

## Acceptance criteria the plan must add

These are the numbers and commands that turn "it exported" into "it is correct." Run them on
the Mac after the phone reports "Fertig", before changing the Mac job.

| # | Check | Command | Pass |
|---|-------|---------|------|
| 1 | Both files exist, non-trivial | `ls -l "$C" "$W"` where `C="$HOME/Library/Mobile Documents/com~apple~CloudDocs/HealthSync/.health-cache.json"` | both > 10 KB |
| 2 | Schema and producer | `jq -e '._meta.schema==1 and ._meta.app=="healthsync-ios"' "$C"` | exit 0 |
| 3 | Metric set | `jq -r '[to_entries[]|select(.key!="_meta")|.key]|length' "$C"` | ≥ 15, and includes `step_count`, `heart_rate`, `resting_heart_rate`, `heart_rate_variability`, `respiratory_rate`, `blood_oxygen_saturation`, `sleep_analysis`, `active_energy`, `walking_running_distance` |
| 4 | Date range | `jq -r '[to_entries[]|select(.key!="_meta")|.value.daily[-1].d]|max' "$C"` | ≥ yesterday (`date -v-1d +%F`), ≤ today |
| 5 | Steps vs Health app | `jq -r '."step_count".daily[]|select(.d=="YYYY-MM-DD")|.v' "$C"` | equals the Health app's day total within 1% (at least 3 days checked) |
| 6 | Sleep vs Health app | `jq -r '."sleep_analysis".daily[]|select(.d=="YYYY-MM-DD")|.v' "$C"` | last night within 0.1 h of the Health app's "asleep" total; wake-day attribution |
| 7 | Percentages | `jq -e '[(."blood_oxygen_saturation".daily // []), (."body_fat_percentage".daily // [])] | flatten | all(.v <= 1)' "$C"` | exit 0; latest SpO₂ ≈ Health app 97% / 100 |
| 8 | Hand-built units | `jq -r '."vo2_max".daily[-1].v // "absent", ."walking_speed".daily[-1].v // "absent"' "$C"` | VO₂ 20–60 mL/min/kg; speed 2–8 km/h; both equal the Health app's latest value |
| 9 | Workouts | `jq 'length' "$W"`; `jq -r '.[-1] | [.start,.name] | @tsv' "$W"` | count equals the Health app's workout count; the five newest match by start and activity; every `start` ends `+01:00`/`+02:00`, never `Z` |
| 10 | Workout optional keys | `jq -e 'all(.[]; has("start") and has("end") and has("duration"))' "$W"` | exit 0; a ride has `distanceMeters`, a strength session may omit it (absent is not 0) |
| 11 | Mac↔NAS checksum | `shasum -a 256 "$C"` vs `ssh … 'sha256sum /volume1/docker/health-export/data/.health-cache.json'` | equal |
| 12 | Server | `HEALTH_DATA_DIR=/volume1/docker/health-export/data node server.mjs --doctor` (or `docker exec`) | `cache schema: 1 (app healthsync-ios)`, `metrics: ≥ 15`, `last data date: ≥ yesterday` |
| 13 | Live tool | `get_mcp_status` | `ok:true`, `source` contains `/volume1/docker/health-export/data/`, `metricCount ≥ 15`, `workoutCount` matches, `lastDataDate ≥ yesterday` |
| 14 | Tool semantics | `get_health_metrics` step sum for a named day; `query_health_data("my weight")`; `get_workouts` | step sum equals #5; weight resolves (no `unknown metric "weight_body_mass"`); workouts return the newest row |

Criterion 14 is the regression the earlier verification could not catch: the alias map
resolves `weight` to `weight_body_mass` (`healthstore.mjs:979–989`), so a file with
`body_mass` would parse but fail the convenience path. The app now writes
`weight_body_mass` (`HealthSyncApp.swift:34`), but the plan's verification never asserts it.

---

## Test plan the plan must add

| # | Case | Setup | Expected |
|---|------|-------|----------|
| 1 | Happy path | fresh install, all types granted, phone unlocked | two files, schema 1, ≥ 15 metrics, `Fertig` status |
| 2 | Permission denied | first run, tap "Don't Allow" (or toggle one type off) | no files written; status names the failure; Settings recovery works; a partial grant removes only the denied metric |
| 3 | Locked device | start export, lock immediately | error, previous files unchanged (mtimes), no `_meta`-only file |
| 4 | No folder | fresh install, tap Export before picking | "Zuerst einen Ordner wählen", no crash, no permission prompt (or prompt first if B1 is fixed that way) |
| 5 | Folder deleted/renamed | delete `HealthSync` in Files, export | clear "folder unavailable" error, previous files intact, re-pick succeeds |
| 6 | iCloud evicted | on the Mac, `brctl evict` both files (or remove the local copy while iCloud holds it), run the job | job downloads first (`brctl download`) or exits non-zero without changing the NAS; after download, checksums match |
| 7 | Empty metric type | a type with no samples (e.g. water) | key omitted, not `daily: []`; server `list_metrics` does not list it |
| 8 | Sleep crosses midnight | 23:00–07:00 segment | 8.0 h on the wake day, not split or credited to the start day |
| 9 | DST day | export over a 23 h/25 h local day | exactly one `d` key for the date, sum/mean unchanged, no duplicate or missing day |
| 10 | Travel timezone | workout starting 01:30 local after a timezone change | `start` carries the local offset; server dates it to the local day, not the UTC previous day |
| 11 | Workout without distance/HR | strength session | `distanceMeters`/`avgHeartRate` absent, not 0; server returns the row |
| 12 | Percentage | SpO₂ 97%, body fat 22% | stored 0.97 / 0.22, never 97 / 22 |
| 13 | Hand-built units | VO₂ and walking speed with real samples | values match the Health app's displayed numbers in the stated units |
| 14 | Background | Xcode `_simulateLaunchForTaskWithIdentifier`; then locked | writes once; locked run completes `false` and leaves files untouched |
| 15 | Rollback | stop the job, restore the previous producer, run it | NAS returns the previous `metricCount`/`lastDataDate`; the app folder is not read |

Cases 2, 3, 5, 6 and 15 are the ones that decide whether this is a reliable producer; the
current plan has none of them.

---

## Rollback procedure the plan must add

Run in this order; do not skip the backup.

```bash
# 0. Record the baseline (if any) and back it up on the NAS.
ssh -i ~/.ssh/id_nas you@your-nas \
  'cp -a /volume1/docker/health-export/data /volume1/docker/health-export/data.bak-$(date +%F)'

# 1. Stop the job so nothing overwrites the NAS while you work.
launchctl bootout gui/$UID/com.hannes.healthsync

# 2. Restore the previous producer's source. Either:
#    a) MetricBridge: restore the .bak script and its iCloud folder, or
#    b) Python converter: run the manual export + converter into ~/Tools/health-data:
python3 ~/Tools/apple-export-to-cache.py "$HOME/Downloads/export.zip" -o "$HOME/Tools/health-data"
#    (export.zip is Apple Health → profile → Export All Health Data)

# 3. Re-point the job at the default and restart it.
#    If you chose the plist env var, remove HEALTH_SRC from the plist first.
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.hannes.healthsync.plist
launchctl kickstart -k gui/$UID/com.hannes.healthsync

# 4. Verify, don't assume.
HEALTH_DATA_DIR=/volume1/docker/health-export/data node server.mjs --doctor
# expect: cache schema 1, metrics >= 15, last data date >= yesterday
```

Also: rename the app's iCloud folder to `HealthSync.disabled-YYYY-MM-DD` or delete it, so the
two producers cannot write the same filenames. Keep the NAS backup until the next successful
daily run.

---

## Step most likely to fail for a first-time implementer

**Step 3, "Run. First launch asks for Health permission; grant read for all types."** It will
not ask. With no folder stored, `exportNow()` returns at `HealthSyncApp.swift:314–317` before
`authorize()` at `:324`; the launch `.task` (`:402–404`) only shows "Zuerst einen Ordner
wählen." The implementer sees no permission sheet, assumes the entitlement or signing is
broken, and spends the next hour in Signing & Capabilities — while the actual fix is to pick
a folder and tap "Jetzt exportieren." Step 2 (signing/capability) is the second most likely,
because the plan never says to add the capability tile and `xcodegen generate` would discard
that edit anyway.

---

## What I verified

- `xcodegen 2.46.0` is installed; `xcodebuild -list` shows the `HealthSync` scheme; the exact
  design:237–239 command still returns `** BUILD SUCCEEDED **` (signing disabled).
- `xcodebuild -showBuildSettings` shows `CODE_SIGN_STYLE = Automatic` and no
  `DEVELOPMENT_TEAM`; `security find-identity` shows one Apple Development identity, team
  `<cert-id>`; no provisioning profiles are installed yet.
- `project.yml` and `Info.plist` match the design's file list (bundle id, iOS 17, background
  modes, `BGTaskSchedulerPermittedIdentifiers`); the entitlements file has the extra empty
  `.access` key.
- `healthsync-nas.sh:6` defaults to `~/Tools/health-data`, which does not exist;
  `healthsync-nas.sh:8` logs and exits 1; `/tmp/healthsync.log` shows the failure at 17:01,
  17:16 and 17:31. The NAS health directory is empty.
- `get_mcp_status` in this review returned `ok:false`,
  `source:"file /opt/data/health/.health-cache.json"`, `metricCount:0` — not the NAS instance.
- `healthstore.mjs` `status()` reports `lastDataDate` from `daily[-1].d` (`:282–309`), and
  `ok` requires `pairing().ok` (`:293`); `--doctor` reads `HEALTH_DATA_DIR`
  (`server.mjs:399–436`). These are the details that make design:233/256 false as written.
- The app compiles, but no runtime path was executed on a device in this review; the B1
  ordering and the missing acceptance/test/rollback sections are plan defects, not build
  defects.
