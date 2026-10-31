# Consolidated Goldfish review — HealthSync (stages 5-9, one pass)

Target: `design_draft.md` (321 lines) and the implementation in `HealthSync/`.
Reviews run in fresh contexts: zoom-out, comprehension, design, structural, style (round 1);
intermediate zoom-out, implementation readiness, codebase details, style (round 2).
Reports: `reports/*.md`.

## Verdict

The design survives; it was not clean. Round 1 found 17 blocker-class and major defects, of which
four were real code defects that would have shipped wrong numbers. Round 2 checked the correction
and found that some of the corrected prose claimed more than the code does.

## Defects found and fixed in code

| Defect | Evidence it was real | Fix |
|---|---|---|
| Percentages divided by 100 twice (`0.97` → `0.0097`) | `HKUnit.h`: percent is 0..1; header quoted by the structural reviewer | division removed from `HealthSyncApp.swift` |
| Metric names invented (`body_mass`, `active_energy_burned`, `distance_walking_running`) | `ALIASES` in `healthstore.mjs` maps only to `weight_body_mass`, `active_energy`, `walking_running_distance`, `exercise_time` | renamed in the app **and** the Python converter |
| An empty or denied run replaced a good cache and reported success | `Exporter.run` had no floor | `guard metrics.count > 1` throws, nothing written |
| Workout timestamps UTC while the server dates by the local string | `ISO8601DateFormatter` defaults to GMT | `timeZone = .current` |
| Cycling and swimming workouts carried no distance | distance read only from `distanceWalkingRunning` | distance type follows the activity, `totalDistance` fallback |
| First launch never showed the Health permission sheet | `exportNow` returned before `authorize()` without a folder | authorize first, then the folder check |
| Background run with no folder reported success | `guard let folder ... else { return }` completed normally | throws `ExportError.noFolder`, task reports failure |
| launchd never received `HEALTH_SRC` | plist had no `EnvironmentVariables` block | block added with an absolute path; `~` expanded in the script |

## Findings accepted as documented trade-offs

- The pair is atomic per file, not across the pair: iCloud syncs the two files independently.
  Documented instead of solved; a generation stamp would need a server change.
- Background runs persist no visible status. Only the foreground shows what happened.
- Two producers (app, converter) must not share an output folder. `HEALTH_SRC` picks one.
- Schema knowledge exists twice. Named as a cost, not fixed.
- Free-tier signing: 52 re-signs a year against a €24.99 purchase. The design does not claim this
  is cheaper in human time; it states the trade so the owner can reject the design on it.

## Still open

- Blockers from round 1 that remain partial or open (3 of 9): liveness/staleness of the pipeline
  is not bounded by any Goal, so a silent stop has no owner; the comprehension gaps in the
  detailed steps were only partly closed by the acceptance criteria.
- 16 partial and 13 open items across both rounds are prose precision, terminology and
  minor terminology drift. They do not change behaviour and are not worth another review cycle
  under the one-re-audit rule.

## Traceability

| Round | Items | Resolved | Partial | Open |
|---|---|---|---|---|
| 1 (stages 5-7) | 39 | 10 | 16 | 13 |
| 2 (stages 8-9) new findings | 4 majors | 3 | 1 | 0 |

Severity counts per round: round 1 — 9 BLOCKER, 22 MAJOR, 26 NIT. Round 2 — 1 BLOCKER, 6 MAJOR,
20 NIT across four reports.

## What the reviewers could not verify

On-device behaviour: the permission sheet, background scheduling, iCloud materialisation and the
two hand-built units (`vo2_max`, `walking_speed`). No reviewer had a device; the acceptance criteria
in the plan are written to be checked by the owner in one sitting.
