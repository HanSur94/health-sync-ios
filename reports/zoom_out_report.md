# Zoom Out Review — HealthSync (design_draft.md)

Reviewer: EGM Goldfish, fresh context · 2026-10-31 · target: `design_draft.md` (241 lines)
Standard: root problem vs symptom · YAGNI · minimal data flow · no speculative abstraction ·
no code detail in high-level sections · leverage existing code · architectural fit · anti-patterns.

Verdict: the solution is small and honest, but the document never states *which constraint it is
optimising* and never prices what it chose. One blocker (objective function), five majors (three of
them contract/consistency claims the doc asserts but the files contradict), four nits.

---

## BLOCKER

### B1. The design optimises "no purchase", then pays for it in weekly human labour it never prices
**Evidence.** Problem framing: *"The one that works, MetricBridge, costs €24.99 once"* (design:12) and
*"Rejected because the request was to not buy an app"* (design:139-140). The cost that choice creates is
compressed to one bullet: *"Free-tier provisioning expires every seven days; the app stops launching until
it is re-signed from Xcode"* (design:236-237), followed by *"A paid membership removes this at €99/year,
more than the app that was avoided."* Goals are all producer-side: exact schema (38), free account (39),
metric coverage (41), traceable rules (44). None is "a file arrives every day without me touching it".

**Why it matters at spec altitude.** The root problem is not "MetricBridge costs €24.99". It is "health data
reaches the agent with bounded staleness and near-zero attention". Those are different objectives and they
produce different designs. The doc's own numbers show the substitution cost: 52 mandatory re-signs per year
plus a device run per release, against a one-time €24.99, and the doc stops one sentence short of doing that
arithmetic. A reader cannot tell whether this is a €25-avoidance project or a 420-line producer with a
weekly maintenance schedule — so they cannot accept or reject the design, only admire it.

**Lazy fix (two lines in Known trade-offs).** Annualised interventions: `52 re-signs × ~2 min ≈ 2 h/yr,
plus N device runs`. State the constraint explicitly ("no paid app" is a given, per concepts_brief:24-26 —
this review does not reopen it) and state what it costs. Then one risk line: *who notices when it stops?*
It is already mitigated upstream and the doc never says so — `get_mcp_status` returns `lastDataDate`
(healthstore.mjs:309) and the daily-brief prompt instructs the agent to name staleness plainly
(prompts.mjs:21). Naming that turns an unmanaged weekly chore into a monitored one, which is the only thing
that makes free-tier signing acceptable.

---

## MAJOR

### M1. The contract claim is stronger than the evidence: the app's metric names are not the names the server resolves
**Evidence.** Doc claims *(Cache) names match what `healthstore.mjs` and its alias map already understand
(`step_count`, `heart_rate_variability`, `resting_heart_rate`, …)* (design:85-87) and *"Produce the exact
cache schema `healthstore.mjs` already reads"* (design:38). But the alias map resolves to names the app never
writes: `weight: 'weight_body_mass'`, `distance: 'walking_running_distance'`,
`'active energy': 'active_energy'` (healthstore.mjs:982,984,985), and the server's own dataset uses those
(demo.mjs:82,84,112). The app — following the Python converter — writes `body_mass`
(HealthSyncApp.swift:34), `distance_walking_running` (:21), `active_energy_burned` (:22).
`query_health_data` resolves the alias *first* (healthstore.mjs:994-996), then `getHealthMetrics` throws
`unknown metric "weight_body_mass"` (healthstore.mjs:456).

**Why it matters.** The convenience path is the one an agent actually uses; on this file "weight trend" and
"active energy last week" hard-fail, and "distance last week" fails *because* the alias beats the name match
that would otherwise have worked. The doc's verification (design:218-222) ran against the converter's file and
checked `ok`, a step sum, trends, workouts and percentages — it never asserted the metric-name set or the alias
path, so it could not have caught this.

**Lazy fix.** One canonical name per metric, decided once and written into the doc: either rename the four
divergent rows in `SPECS`, or correct the four alias targets. Then add the missing assertion to verification:
`list_metrics` must return exactly the doc's table. Cheaper than a shared spec file, and it kills the same
class of bug for the converter.

### M2. "One table, one place to add a metric" is false, and the second place is undocumented
**Evidence.** design:84-85: *"19 rows … One table, one place to add a metric."* Adding one actually touches
`SPECS` (HealthSyncApp.swift:19-38) **and** `Spec.unit(for:)` (:223-239), a 17-case switch the Components
section never mentions. That switch is also where the only unverified conversions live —
*"`vo2_max` (`mL/min/kg`) and `walking_speed` (`km/hr`) … untested until real samples are exported"*
(design:228-230).

**Why it matters.** The doc sells a single-source-of-truth invariant it does not have, and hides the risky
function behind the claim. A reviewer who trusts line 85 will not ask about `unit(for:)`; a maintainer who adds
a metric will hit a silent `default: return .count()` (HealthSyncApp.swift:237) that writes plausible garbage.

**Lazy fix.** Put the `HKUnit` on the row (`let hkUnit: HKUnit`), delete the switch, keep the display-unit
string beside it. Same row count, one place, and the `default:` fallback disappears.

### M3. Background refresh is a subsystem the doc itself declares unreliable, with no stated observability
**Evidence.** *"`BGAppRefreshTask` with an earliest start six hours out … iOS decides when it actually runs;
the app is honest about that"* (design:116-118) and *"The app cannot promise a daily file without being
opened"* (design:240). The honesty is not implemented: the delegate holds no reference to `SyncModel`, so a
background run never updates `status` (HealthSyncApp.swift:385-406 vs :269), and a run with no folder saved
returns early from the work task, which then reports `setTaskCompleted(success: true)` (:391, :399-402).

**Why it matters.** The feature exists to remove the human from the loop, but its success is unobservable and
its failure is reported as success. That is the exact anti-pattern the doc rejects Shortcuts for —
*"fails quietly"* (design:15, 145). Either the component earns its plist keys or it does not belong in v1.

**Lazy fix.** Ship launch-export only; add `BGAppRefreshTask` when a measured staleness complaint exists
(one-line YAGNI note in Non-Goals). If kept: persist `lastRun`+`lastResult` to `UserDefaults`, display it, and
make the no-folder path complete `success: false`.

### M4. Two files, one dataset, no snapshot boundary
**Evidence.** The app writes the pair back to back — `write(metrics, …)` then `write(workouts, …)`
(HealthSyncApp.swift:96-97) — while the Mac job copies whatever is in the folder (*"the existing Mac job
copies those files to the NAS"*, design:31-32; diagram design:63-75). `_meta.writtenAt` exists only in the
metrics file (design:126), so nothing on either side can tell whether the two files came from the same export.

**Why it matters.** `get_mcp_status` reports `metricCount` and `workoutCount` as one status
(healthstore.mjs:305-308), and `get_workouts` and `get_health_metrics` are routinely called in the same answer.
A copy that lands between the two writes ships mismatched halves and there is no field to detect it. Per-file
`.atomic` (HealthSyncApp.swift:193) protects each file, not the pair.

**Lazy fix.** Write a `writtenAt` into both files and have `healthsync-nas.sh` skip the copy when they differ
(retry next run — the sync is not latency-critical). One comparison in a script that already exists.

### M5. The document is a spec and a build log at once, and the build log is what will rot
**Evidence.** design:163-240 is a file inventory with line counts and rationale — *"423 lines in one file"*
(:172), *"18 readable lines instead of a 400-line `project.pbxproj`"* (:169-170) — followed by
*"Verification already performed"* with a `BUILD SUCCEEDED` transcript (:212-223). design:188 says this same
text becomes `docs/designs/health-sync-ios.md`.

**Why it matters.** Line counts are wrong after the first commit; `BUILD SUCCEEDED` is a claim about today,
not a decision. Keeping them in the canonical design record means the next reader cannot tell which statements
are invariants and which are timestamps — and the two architectural questions that needed review (B1, M3) get
one bullet each while the file list gets thirty lines. The zoom-out inversion: the durable decisions are
under-written and the transient details are over-written.

**Lazy fix.** Move :212-232 to a dated `reports/` file. In the spec keep: what each file is *for*, and drop
counts and rationale prose that repeats itself ("rationale: the project file is generated … no one can review").

---

## NIT

**N1. "19 quantity types" is wrong and the discrepancy is informative.** design:25 and design:84 say 19 rows;
`SPECS` has 18 (HealthSyncApp.swift:19-38), and the missing one is `sleep_duration_goal`, which the verified
converter does write (apple-export-to-cache.py:39). So the doc's count came from the converter's `MAP` (19
rows) and quietly describes a table that is one metric short. Either drop `sleep_duration_goal` from the
contract on purpose (say so) or add it.

**N2. A declared background mode with nothing behind it.** *"background modes `fetch` and `processing`"*
(design:178; Info.plist:15), and `BGProcessingTask` appears nowhere in the app (0 matches). `processing` is
dead capability. Worth also confirming `fetch` against Apple's docs for `BGAppRefreshTask`, which keys off
`BGTaskSchedulerPermittedIdentifiers` — I did not verify that requirement from the files, so treat it as a
question rather than a finding.

**N3. The performance claim is stated as fact, and the sleep path is the loop it argues against.**
*"a two-year window costs roughly the same as a two-day window"* (design:93) is unmeasured, and
*"its per-sample loops are the slow part"* (design:94-95) is followed by exactly that for sleep and workouts
(HealthSyncApp.swift:125-158, `HKObjectQueryNoLimit` over 730 days). Not a bug — but mark the claim as an
expectation, or time one export and put the number in.

**N4. Source selection is a second, unstated rule.** design:100-103 defines the sleep day-attribution rule and
nothing about *which* source wins. HealthKit returns samples from every source, so a `.discreteAverage` heart
rate mixes Watch and iPhone estimates, and summing all asleep samples double-counts when two apps record the
same night. That collides with *"a number … traces back to a rule rather than a guess"* (design:44-45). I could
not verify whether duplication actually occurs in this dataset from the files — flagging it as an unaddressed
rule, not a proven defect.

---

## What holds (do not change)

- **Single file, no dependency, no abstraction.** No protocol around `Exporter`, no view-model layer for one
  screen, no config for `LOOKBACK_DAYS`. At 18 metrics this is the right size; splitting it would be the
  over-engineering this review exists to prevent.
- **Transport reuse.** *"The Mac job does not change shape, only its source"* (design:78-80) with `HEALTH_SRC`
  already in the script (design:191-195) is the cheapest possible delivery path, and the right rejection of the
  LAN-push option (design:159-161).
- **The folder bookmark decision** (design:110-114) is the one genuinely load-bearing insight in the doc: it
  buys free-tier signing, and it is stated with its reason.

## Not verifiable from these files

- Whether `startAccessingSecurityScopedResource()` actually returns write access for an iCloud Drive folder
  picked via `UIDocumentPickerViewController` on a free account — the doc asserts it (design:110-114), the code
  assumes it (HealthSyncApp.swift:295-296), and only a device run settles it.
- Whether iCloud Drive on the Mac materialises the two dotfiles for the launchd job when "Optimize Mac Storage"
  is on. Not mentioned anywhere in the doc; the Mac→NAS checksum verification (design:223) proves the transport,
  not the iCloud hop.
