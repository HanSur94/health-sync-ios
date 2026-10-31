# Intermediate Zoom Out — HealthSync, after the first correction round

Reviewer: EGM Goldfish, fresh context · 2026-10-31 · target: `design_draft.md` (274 lines) and
`HealthSync/HealthSyncApp.swift` (449 lines), both post-correction.
Standard: root problem · simplicity / YAGNI · minimal data flow · anti-weeds · leverage of
existing code · architectural fit.
Checked against: `reports/{zoom_out,comprehension,critic_design,critic_structural}.md`,
`~/Tools/health-export-mcp/{healthstore,prompts}.mjs`, `~/Tools/apple-export-to-cache.py`,
`~/Tools/healthsync-nas.sh`, `HealthSync/Info.plist`, `project.yml`.

Two checks were run rather than read:
- `queryHealthData()` against a synthetic cache carrying the app's exact 18 names (temp
  `HEALTH_DATA_DIR`), to test the alias path the correction claims to have fixed.
- `FileManager.replaceItemAt` with a missing destination (macOS): it succeeds and creates the
  file, so the new `publish()` does not break the first run. iOS not tested.

Verdict: **the accounting is fixed and the contract is mostly fixed; the liveness story is not,
and the correction wrote two sentences the code does not support.** Of 39 round-1 BLOCKER/MAJOR
items: 10 resolved, 16 partial, 13 still open. Three of nine blockers remain open or partial.
The document is now accurate about what it costs and still silent about how anyone learns it has
stopped — which is the one thing the whole feature exists to guarantee.

---

## 1. Round-1 findings: status

Legend: **R** resolved · **P** partial · **O** still open. Evidence cites the current files.

### zoom_out_report.md (1 B · 5 M)

| # | Status | Evidence |
|---|---|---|
| B1 objective unpriced | **R** | design:160-163 ("Scored honestly it wins on effort… no re-signing, no maintenance") and :258-264 (52 re-signs/yr, €24.99 vs €99/yr, "four times the app that was avoided", "if weekly re-signing is unacceptable, this design is the wrong one"). The re-sign cost is now the stated largest recurring cost. Residual: the detection path is still unnamed — `get_mcp_status.lastDataDate` (healthstore.mjs:305-308) plus the daily-brief staleness clause (prompts.mjs:21) is what makes weekly signing survivable, and the doc never says so. |
| M1 alias-name divergence | **R** | code:20 `walking_running_distance`, :21 `active_energy`, :33 `weight_body_mass`; design:86-89. Verified by running `queryHealthData` on a cache with these names: "my weight", "distance last week", "active energy last week" all resolve. The hard `unknown metric` failure is gone. |
| M2 "one table, one place" | **P** | The claim survives three lines above the retraction: design:84 still says "One place to add a metric", design:90-92 then says the unit mapping "is not derived from the table". The 17-case switch is still there (code:248-263) with `default: return .count()` (:262), and the doc does not warn that an unmapped metric writes plausible counts. |
| M3 background not observable | **P** | Empty run now throws (code:97-99), so a locked phone completes `success: false` (code:425-428). But the no-folder path still `return`s from the work task (code:417) and is reported `success: true` (:427), and nothing is persisted or displayed: the delegate still holds no `SyncModel` and writes no `UserDefaults` (code:411-439). Doc:131-132 overstates this as "reports what happened". |
| M4 no snapshot boundary | **P** | `publish()` stages both files then renames (code:206-219); doc:137-139 claims this means "a reader never sees a new metrics file next to last cycle's workouts file". That is false for the actual reader: iCloud uploads the two files independently, the workouts file still has no `_meta` (design:149-153, code:207), and `healthsync-nas.sh` still tars whatever is in the folder (script:12-15). The proposed `writtenAt`-in-both-files + script comparison was not done. |
| M5 spec/build-log mix | **O** | design:195 "423 lines in one file" — the file is 449 (`wc -l`). design:192 "18 readable lines" — `project.yml` is 19. The `BUILD SUCCEEDED` transcript is still at :237-247. The predicted rot happened inside the round that edited the document. |

### comprehension_report.md (3 B · 11 M)

| # | Status | Evidence |
|---|---|---|
| B1 metric table never enumerated | **P** | Count fixed: design:25 and :84 say 18, `SPECS` has 18 (code:18-37). But the table is still not in the document: design:87-88 gives six names and an ellipsis; 12 names, all 18 units and all cumulative flags are absent. `sleep_duration_goal` (apple-export-to-cache.py:39) is still dropped without a stated decision. |
| B2 workout `id`/`name`/`distanceSource` undefined | **O** | design:113-120 still describes only activity type, timestamps, duration, energy, distance, HR, elevation. The three fields remain in the schema block (design:149-153) with no producer rule. |
| B3 schema of record located nowhere | **O** | design:38, :86, :271 still say `healthstore.mjs`; :244 and :256 still say `node server.mjs --doctor`; no path appears anywhere in the doc (`grep` for `~/Tools` finds only the local script at :214). |
| M1 empty days / ordering | **O** | design:145-147 still shows one `daily` element. The code skips empty days (code:82) and sorts ascending (:84, :89); neither rule is stated. |
| M2 "local" unpinned, ISO offset | **P** | Workout half fixed and explained: design:114-120 pins the local offset and the reason. Day-bucket half still unpinned: design:94-96 does not say the 730 days are re-bucketed into the phone's *current* zone, nor what that does to history after travel (the converter uses each record's own offset, apple-export-to-cache.py:52-54). |
| M3 atomicity / partial read | **P** | Stated at design:137-139; overstated (see new M1). |
| M4 iCloud materialisation | **O** | design:214-218 points the job at `~/Library/Mobile Documents/…/HealthSync` and says "no change needed to the script itself"; the script has no placeholder/`brctl download` check (healthsync-nas.sh:8-15). A dataless `.health-cache.json.icloud` is tarred, the NAS keeps the previous file, and fresher data silently never arrives. |
| M5 "no change" / launchd env hand-wave | **P** | design:214-218 is now parseable and names both routes, but still shows neither edit and still presents "the launchd plist's environment or a one-line default change" as equivalent. A LaunchAgent inherits no shell exports; only the plist works. |
| M6 permission partial/denied | **P** | All-empty now throws and keeps the old pair: design:134-139, code:97-99. Partial denial is still indistinguishable from "no samples": no `_meta.requested`/`_meta.missing` anywhere (design:143-153). |
| M7 BG task one-shot | **P** | Code re-submits from inside the handler (code:415), so it recurs. Doc:129 still says only "re-scheduled on every launch", so the reader cannot tell. |
| M8 workout query window | **P** | Code bounds it: `predicateForSamples(withStart: start…)` (code:156) with `start` = 730 days back (:77). Doc:113 still omits the window. |
| M9 verification evidence contradictory | **R** | design:241-247 now names the converter as the test subject, says "same shape, different code path", and :239-240 disclaims runtime. Honest. |
| M10 LaunchAgent access to iCloud folder | **O** | Doc silent (design:214-221). Whether the job can read `~/Library/Mobile Documents` without a TCC prompt cannot be settled from these files; the doc should say which it is, because "tarred nothing" and "not yet synced" look identical at step 5. |
| M11 "the agent" undefined | **O** | design:10 and :233. Unchanged. |

### critic_design.md (4 B · 10 M)

| # | Status | Evidence |
|---|---|---|
| B1 empty run replaces good data; no NAS-side validation | **P** | Guard added (code:97-99, design:134-139), but it passes with a single metric (`metrics.count > 1` counts `_meta`, set at :91), and `healthsync-nas.sh` still has no JSON/schema check before overwriting the live directory (script:12-15). The "keep last good on the NAS" half is untouched. |
| B2 free-account expiry omitted | **R** | design:258-264, with the arithmetic and the comparison. |
| B3 "no cloud" contradiction | **P** | Doc now honest (design:265-267). The user-facing string was not corrected: Info.plist still reads "Read-only, nothing leaves your devices" — false whenever the picked folder is in iCloud Drive. |
| B4 delivery unverified / bookmark code weak | **O** | code:280 still `.minimalBookmark`; :287 still `try?` with `stale` discarded; no re-pick path, no post-write readback, no device evidence. design:122-126 unchanged. This is the load-bearing mechanism of the whole design and it is still asserted. |
| M1 730 days vs converter history | **R** | Policy now stated: design:268-270, one producer per folder, `HEALTH_SRC` selects. The "history capped at 2 years" acceptance is still not in Goals, only implied at :26. |
| M2 wrong aggregation argument, dedup unclaimed | **O** | design:98-100 unchanged: "a two-year window costs roughly the same as a two-day window", and the reason given is still Shortcuts' per-sample loops. The doc's own Sleep and Workouts sections describe per-sample loops (design:108-113, code:130-202), and the real differentiator — HealthKit source dedup vs the converter summing raw XML — is still never claimed. |
| M3 no acceptance criteria | **P** | design:249-256 adds a device checklist including server acceptance. Still no falsifiable parity test (same period through both producers, diffed) and no numeric target for any metric. |
| M4 schema duplicated three ways, 19th metric dropped | **P** | Duplication declared as a decision (design:271-272). `SPECS` still lacks `sleep_duration_goal` (code:18-37 vs apple-export-to-cache.py:39) and the doc never says the omission is deliberate. |
| M5 read denial invisible | **O** | No `_meta.requested` / `_meta.missing` in the schema (design:143-153) or the writer (code:91-92). |
| M6 sleep goal overstated | **O** | design:41-43 still promises "sleep"; design:50-52 still excludes `health-sessions.json`, which is what `get_sleep_sessions` reads. No narrowing to "daily hours only". |
| M7 BG expected to fail | **R** | design:130-131 states the locked-device failure; the code now throws instead of writing (code:97-99). |
| M8 transport cannot detect a placeholder | **O** | Same as comprehension M4. design:78-80 "No code change is required for the transport" is still the claim; the script still tars the directory blind. |
| M9 day boundaries vs converter | **O** | design:94-96 states the bucket and nothing about time-zone change re-slicing 730 days of history. The server ships `excludeTravelDays` built on the opposite assumption. |
| M10 alternatives never scored on cost/failure | **P** | design:160-163 and :258-264 now price the app honestly against MetricBridge. Shortcuts (:165-169) and manual export (:171-173) are still scored only on capability, not on uptime or history depth. |

### critic_structural.md (1 B · 4 M)

| # | Status | Evidence |
|---|---|---|
| B1 percentages divided twice | **R** | code:119-122 (fraction kept, comment names the bug); design:102-106 explains both producers correctly. |
| M1 workout distance hard-coded | **R** | code:178-188 switches cycling/swimming/walking and falls back to `totalDistance`; design:116-118 states it. |
| M2 UTC workout timestamps | **R** | code:271 `f.timeZone = .current`; design:114-120 explains why. |
| M3 18 vs 19 | **R** | design:25, :84 and code:18-37 agree on 18. The dropped 19th is tracked under critic_design M4. |
| M4 empty run overwrites, reports success | **P** | Same guard; the UI path reports the error correctly (code:327-329), the background path still reports success when no folder is set (code:417, :427). |

**Totals: 10 resolved · 16 partial · 13 still open (of 39).** By severity: blockers 3 R / 3 P / 3 O.

---

## 2. New problems

### B1 (new, synthesis). The correction asserts liveness twice and specifies it nowhere
The root problem was never "produce a file". It was "health data reaches the agent with bounded
staleness and near-zero attention" — the server's own prompt says so: *"if it is older than
yesterday, say so plainly"* (prompts.mjs:21). Goals (design:38-45) still contain no freshness,
uptime or "who notices" target; the four goals are schema, free account, coverage, traceability.

Three independent paths can now stop the file without anyone being told:
1. 7-day provisioning expiry (design:260-261) — the app stops launching;
2. an iCloud placeholder that the Mac job tars as a `.icloud` stub (design:78-80, comprehension M4);
3. a background run on a locked phone (design:130-131) — now correctly a failure, but invisible.

The only check in the document is build step 6, "`get_mcp_status` in the agent must report
`ok: true` with a `lastDataDate` of today" (design:233) — a one-time manual action during setup.
And the correction then spends two sentences claiming the gap is handled (:131-132 reporting,
:137-139 pair atomicity) when neither is implemented. A reader can no longer tell what the
staleness bound is supposed to be, so they still cannot accept or reject the design on its own
terms; they can only check it after it has already gone quiet. **Fix:** one goal line with a
number ("a file younger than 48 h, or the agent says so") and one alarm line naming
`lastDataDate`, then delete the two claims below.

### M1 (new). `publish()` cannot deliver the pair guarantee the document now makes
design:137-139: *"Both files are written under temporary names and then renamed, so a reader
never sees a new metrics file next to last cycle's workouts file."*
Code:206-219 stages both files, then calls `replaceItemAt` twice in a loop (:216-218). Three
ways the claim fails: the two renames are sequential, so a throw or a kill between them leaves
exactly the forbidden state; the rename loop has no rollback; and the reader is the Mac, which
sees two independent iCloud uploads, not the phone's directory. There is still no generation
stamp — the workouts file remains a bare array (design:149-153). The correction improved the
window from "two writes" to "two renames" and then described it as zero. Either drop the
sentence to "each file is replaced atomically" or add `writtenAt` to both and one comparison in
the script, which is what round 1 asked for.

### M2 (new). "The app reports what happened" is only true in the foreground
design:131-132. The exporter now throws on an empty result, which is real progress. But the
background handler (`code:411-439`) writes nothing anywhere: no `UserDefaults`, no `status`
update, no notification. Its no-folder path returns from the work task (:417) and is scored
`success: true` (:427). So the one path that exists to remove the human from the loop is still
the one path with no reporter, and it still reports success for the case the doc says it no
longer pretends about. **Fix (lazy):** persist `lastRun` + `lastError` in `UserDefaults` from
`run()`, show them in the status line, and make :417 throw `noFolder` like `exportNow` does.
Three lines; otherwise delete the feature (round 1's M3 recommendation, still the cheaper one).

### M3 (new). The write floor is one metric, so the doc's "the only signal is no metrics" is false
design:135-136: *"the only visible signal that permissions were refused or the device was locked
is a result with no metrics."* The guard is `metrics.count > 1` (code:97) — one metric plus
`_meta` passes. A user who denies 17 of 18 types, or a device that returns only steps, replaces
an 18-metric snapshot with a 1-metric one, silently: the server's `metricCount` drops and
`ok` stays true (healthstore.mjs:305-308). Round 1 asked for a floor; the floor chosen is the
minimum that compiles. Either set it ("fewer than 10 metrics is an error") or, better, write
`_meta.requested` and `_meta.missing` so a thin file explains itself and the next round can tell
denial from a quiet week.

### NITs

- **N1. The line counts are already wrong.** design:195 says 423 lines (449 actual); design:192
  says 18 lines of `project.yml` (19 actual). This is M5 recurring within one round — move the
  inventory counts out of the spec.
- **N2. "The cache names are the server's own vocabulary, taken from `ALIASES` … and from the
  demo dataset" (design:86-87) is true for 6 of 18.** `basal_energy_burned`, `flights_climbed`,
  `apple_stand_time`, `dietary_water`, `walking_heart_rate_average`, `body_fat_percentage`,
  `walking_speed` appear in neither; they are the converter's names. Consequence is small but
  real, measured with the app's exact names: "how much stand time" and "water intake" resolve to
  nothing, and "basal energy" is captured by the `energy → active_energy` alias
  (healthstore.mjs:985) and confidently returns the wrong metric. The sentence should cite
  `apple-export-to-cache.py` as the origin.
- **N3. "before 02:00 local" (design:119-120) is right only in summer.** With a `Z` stamp the
  previous-day cut is 01:00 local in CET, 02:00 in CEST. Say "before 01:00 (02:00 in summer)" or
  drop the number.
- **N4. `unit(for type:)` takes an `HKQuantityType` it never uses** (code:248), switches on
  `id`, and sits beside a third spelling of the same contract, `Spec.unit` (code:14). The doc
  calls it "a second, smaller mapping" (design:90-91) when there are three; the "smaller" claim
  is also hard to defend for a 17-case switch.
- **N5. `publish()` now leaves `*.json.tmp` in the synced folder** if the second stage throws
  (code:211-218), and `healthsync-nas.sh` tars the whole directory, so the NAS accumulates
  `.tmp` files. Harmless to the server, but it is litter the previous `write(.atomic)` did not
  create.
- **N6. The document now contains its own change log.** design:88-90 ("An earlier draft used
  `distance_walking_running` … would have failed") is review history in the canonical design
  record, the same class as the build transcript M5 flagged. State the rule; delete the diff.

---

## 3. What the correction got right (do not reopen)

- The four alias targets, the percent fraction, the local-offset workout stamps and the
  per-activity distance lookup are all fixed in code and explained in the doc. Verified by
  running the server's own `queryHealthData` against a cache carrying the app's names — that is
  the first time the corrected contract has been exercised, and it holds.
- The re-sign arithmetic is now stated with numbers and a decision rule (design:258-264). That
  was the round-1 blocker and it is genuinely closed.
- `publish()` writes both payloads before either rename, so a JSON-encoding failure cannot
  half-publish. The remaining problem is the cross-device claim, not the local ordering.
- Still correct and still not to be touched: one file, no dependency, no protocol, no view model,
  `HEALTH_SRC` as the only transport coupling.

## 4. What cannot be verified from these files

- Whether `.minimalBookmark` preserves write scope on iOS 17 for a folder picked via
  `UIDocumentPickerViewController` — code:280 assumes it, design:122-126 asserts it, and B4 has
  been open for two rounds. One device run (write, relaunch, wait 8 days, write again) settles it.
- Whether the launchd job can read `~/Library/Mobile Documents` without a TCC prompt.
- Whether `replaceItemAt` on iOS behaves like the macOS test above when the destination is
  missing. It does on macOS; the first device run will confirm.
- Whether the background task ever fires in practice. The doc says "iOS decides"; nothing here
  measures it.

## 5. Next pass, in order, smallest first

1. Goal line: a staleness bound and the alarm that enforces it (`lastDataDate`). Kills B1.
2. `writtenAt` in both files + one comparison in `healthsync-nas.sh`, or delete the atomicity
   sentence. Kills M1.
3. Persist `lastRun`/`lastError` and make the no-folder background path fail. Kills M2 — or
   delete the background task, which is fewer lines and what round 1 recommended.
4. Raise the write floor and add `_meta.requested`/`missing`. Kills M3 and critic_design M5.
5. `brctl download` (or `jq -e` on both files) in the sync script; one sentence in the doc.
   Kills comprehension M4 / critic_design M8, which is the last silent-stop path.
6. Then the device run for the bookmark (B4) — nothing above is worth much if delivery is
   unproven.
