# Style and evidence review: Detailed Implementation Plan

Document: `design_draft.md`, lines 186 to 274, the section from `## Detailed Implementation Plan`
to the end. The rest of the document was read for terminology consistency.
Artefacts checked: `HealthSync/HealthSyncApp.swift`, `HealthSync/Info.plist`,
`HealthSync/HealthSync.entitlements`, `project.yml`, `HealthSync.xcodeproj/project.pbxproj`,
`~/Tools/healthsync-nas.sh`, `~/Library/LaunchAgents/com.hannes.healthsync.plist`,
`~/Tools/apple-export-to-cache.py`, `~/Tools/health-export-mcp/healthstore.mjs` and `server.mjs`.

Rules applied: plain English; no marketing adjectives or decorative adverbs; no em dashes or en
dashes; one name per concept; every number measured or tagged as a target; valid markdown; no
benefit asserted without a mechanism; no claim that outruns the evidence.

Result: **3 MAJOR, 16 NIT.** The section's central claim, that compilation is proven and runtime
is not, is accurate and correctly hedged. The failures are three stale or inflated file sizes plus one
contradicted rationale: 423 lines, 18 lines and 400 lines, and a "coexist" clause that contradicts a
trade-off stated later in the same section.

## Number audit

| Line | Claim as written | Checked against | Result |
|------|------------------|-----------------|--------|
| 195 | "423 lines in one file" | `wc -l` on `HealthSyncApp.swift` returns 449 | wrong |
| 177 | "the ~420 lines" | 449 | low by 29, same defect outside the section |
| 192 | "18 readable lines" | `wc -l project.yml` returns 19 | wrong |
| 192 | "a 400-line `project.pbxproj`" | `wc -l` returns 295 | wrong |
| 190 | deployment target 17.0 | `project.yml` | correct |
| 190 | bundle id `de.hannessuhr.healthsync` | `project.yml` | correct |
| 202 | `de.hannessuhr.healthsync.refresh` | `Info.plist` and `REFRESH_ID` in Swift | correct |
| 202 | portrait only | `Info.plist` | correct |
| 244 | "schema 1, 6 metrics, 9 workouts" | cited doctor run, not re-run here | measured by the cited run |
| 247 | "verified by checksum on both ends" | no command or log in the repository | unstated method, see N16 |
| 260 | "every seven days" | Apple's free provisioning limit | external fact |
| 261 | "52 re-signs a year" | 365 / 7 = 52.1 | derived, round to "about 52" |
| 263 | "€99/year, four times the app" | 99 / 24.99 = 3.96, and Apple prices in USD | approximate, tag it |
| 233 | `lastDataDate` | `healthstore.mjs:309` | correct |

## MAJOR findings

### M1. The line count is 26 lines out of date
`design_draft.md:195`

> **`./HealthSync/HealthSyncApp.swift`** [em dash] the whole app, 423 lines in one file: metric table,
> aggregation, sleep, workouts, JSON writing, folder bookmark, UI, background task.

`wc -l HealthSync/HealthSyncApp.swift` returns 449, and the file was last modified at 17:26:48,
15 seconds before the Release build that the same section cites. The document is claiming a
measured number for a file it has already edited. Line 177 repeats the error as `~420`.

Replacement: **`./HealthSync/HealthSyncApp.swift`** is the whole app: 449 lines in one file, holding the metric table, aggregation, sleep, workouts, JSON writing, the folder bookmark, the UI and the background task.
Replacement at 177: `No advantage over owning 449 lines.`

### M2. Both numbers in the XcodeGen rationale are wrong
`design_draft.md:192`

> Rationale: the project file is generated from 18 readable lines instead of a 400-line
> `project.pbxproj` that no one can review.

`project.yml` has 19 lines. `project.pbxproj` has 295. The sentence inflates the generated file by
105 lines and deflates its own spec by one to make the choice look starker than it is, and "no one
can review" is an absolute that the paragraph's own existence contradicts.

Replacement (keep the `Rationale:` label): the project file is generated from a 19-line spec instead of a 295-line `project.pbxproj` that is regenerated rather than edited by hand.

### M3. One rationale contradicts the trade-off it depends on
`design_draft.md:217` to `:218`

> Rationale: one knob, already present, so the app and the converter can coexist.

`design_draft.md:268` to `:269`

> The app and `apple-export-to-cache.py` must not share an output folder

The knob selects one source directory for the Mac job. It does not let two writers share a folder,
and the trade-off section says they must not. "Coexist" reads as permission to install both against
one folder, which is the failure the later paragraph warns about.

Replacement: `Rationale: one variable already selects the source, so either producer can feed the Mac sync job, provided each writes to its own folder.`

## NIT findings

### N1. Eight em dashes, all in the Files list
Lines 190, 195, 200, 205, 208, 211, 214 and 220 all use the pattern ``**`path`**`` followed by an
em dash and the description. No other section of the document uses one, so the Files list reads as
a different voice. Replace the separator and start a sentence:

> **`./project.yml`**: XcodeGen spec: one iOS application target ...

or

> **`./project.yml`** is the XcodeGen spec: one iOS application target ...

The diagram's box-drawing characters (U+2500) are not dashes and should stay.

### N2. "Silently fails" is the wrong failure mode
`design_draft.md:200`

> `NSHealthShareUsageDescription` (required or HealthKit access silently fails)

A missing usage description does not fail quietly. On current iOS, the app is terminated at the
first authorization request. The distinction matters because the section is about what a first run will look like.

Replacement: `NSHealthShareUsageDescription` (required; without it the authorization request fails
at runtime)

### N3. `processing` is declared and unused
`design_draft.md:202`

> background modes `fetch` and `processing`

The `Info.plist` does list both, but `HealthSyncApp.swift` registers only `BGAppRefreshTask`
(lines 413 to 435) and never creates a `BGProcessingTaskRequest`. The doc describes a capability the
app does not use. Drop `processing` from the plist and from this list, or say which processing task
will need it.

### N4. The entitlements inventory is incomplete
`design_draft.md:205`

> **`./HealthSync/HealthSync.entitlements`** [em dash] `com.apple.developer.healthkit`.

The file also declares `com.apple.developer.healthkit.access` as an empty array. Empty is harmless,
but a file inventory that omits a key is not an inventory.

Replacement: `com.apple.developer.healthkit`, plus an empty `com.apple.developer.healthkit.access` array.

### N5. The launchd environment does not exist yet
`design_draft.md:215` and `:220`

> the launchd plist's environment or a one-line default change points it at the iCloud folder the
> app writes to

> **`~/Library/LaunchAgents/com.hannes.healthsync.plist`** [em dash] unchanged in mechanism; only the source
> directory resolves differently through `HEALTH_SRC`.

The plist has `Label`, `ProgramArguments`, `RunAtLoad`, `StartInterval` and two log paths. There is
no `EnvironmentVariables` block, so `HEALTH_SRC` is not set by the job today. "Unchanged in
mechanism" is true, but a reader following the steps will look for a variable that is not there.
Both paragraphs also describe the same single edit.

Replacement at 215: `add an EnvironmentVariables block to com.hannes.healthsync.plist, or change the default in the script, to point it at the iCloud folder the app writes to ...`
Replacement at 220: `the plist gains that one EnvironmentVariables entry; the script and its arguments are unchanged.`

### N6. The locked-device test says two opposite things
`design_draft.md:255`

> Background refresh actually firing, and surviving a locked device (expected to skip).

"Surviving" describes a pass. "Expected to skip" describes the opposite, and the Technical Plan
already says a locked run returns nothing. A reviewer cannot tell what result would fail this test.

Replacement: `Background refresh firing while the phone is unlocked. A run while locked is expected to return no samples; the app should then throw and leave the previous file in place.`

### N7. "Only conversions" is not true of the code
`design_draft.md:253`

> These are the only conversions not taken from a constant HealthKit unit

Heart rate, resting heart rate, walking heart rate and respiratory rate also use a composed unit,
`count` divided by `minute` (Swift lines 255 to 256). `vo2_max` and `walking_speed` are the only
units composed from more than one base unit, which is the point being made.

Replacement: These are the only units composed from more than one base unit, `vo2_max` (`mL/min/kg`) and `walking_speed` (`km/hr`), and they are untested until real samples are exported.

### N8. The document argues against a promise it never made
`design_draft.md:265`

> "No cloud" is imprecise.

No line in the document says "no cloud". Line 34 says "No account, no server of ours, no
dependency, no third-party SDK". Quoting a claim the document does not make reads as a strawman
and invites the reader to check a promise that is not there.

Replacement: `"No server of ours" is narrower than it sounds: if the picked folder is in iCloud Drive, the health files are stored in iCloud.`

### N9. "The app" changes referent once
`design_draft.md:263`

> which is four times the app that was avoided

Everywhere else "the app" is HealthSync. Here it is MetricBridge. This is the sentence that compares
the two costs, so the ambiguity lands on the point being made.

Replacement: `which is four times MetricBridge's €24.99.`

### N10. A count, a price and a superlative are stated more precisely than they are known
`design_draft.md:261`

> That is 52 re-signs a year against a €24.99 one-time purchase

365 / 7 = 52.1, so "about 52" is the honest form. The €99 figure is Apple's USD price converted, and
the rate moves. "The largest recurring cost in this design" is also a judgement, not a measurement;
either say "largest in human time" or drop the superlative.

Replacement: `That is about 52 re-signs a year against a €24.99 one-time purchase, the largest recurring cost in human time. A paid membership removes it at about €99/year, roughly four times MetricBridge.`

### N11. Three different writes are all called "export"
`design_draft.md:136`, `:251`, `:269`

> leaving the previous export in place ... replaced a good snapshot with a `_meta`-only file

> First run: permission dialog, export completes, two files appear in the picked folder.

> a manual export can silently replace the app's fresher data

Line 136 uses "export" and "snapshot" for the same object in one sentence. Line 251 uses "export"
for the app's write. Line 269 uses "export" for Apple's zip and the converter's run. A reader
cannot tell which producer is being discussed without the surrounding paragraph.

Replacement: use "snapshot" for the two files the app writes, and keep "manual export" only for
Apple's "Export All Health Data" path. Line 136 becomes `leaving the previous snapshot in place`.

### N12. The verification sentence overstates before it corrects itself
`design_draft.md:241`

> The cache contract the app writes was verified end to end against the real server, but with the
> **Python converter's** output as the test subject, not the Swift writer.

The first clause says the thing the app writes was verified. The second says the app's writer was
not the subject. The qualifier is present and bold, so this is a wording problem, not a false
claim, but the subject should be the schema from the start.

Replacement: `The cache schema was verified end to end against the real server using the Python converter's output, not the Swift writer's.`

### N13. "The owner" against "the user"
`design_draft.md:8`, `:29`, `:40` say "the owner". `:124` says "a user chosen". Pick one. "The user"
is the plainer term and matches the rest of the document.

### N14. Four names for the Mac to NAS job
`design_draft.md:10` "a launchd job", `:78` "The Mac job", `:137` and `:270` "the Mac job", `:232`
"the sync". Use "the Mac sync job" everywhere, and name `~/Tools/healthsync-nas.sh` on first use in
the Technical Plan.

### N15. The workouts schema block is not JSON
`design_draft.md:149` to `:153`

> `[ { "id", "name", "activityType", "start", "end", "duration",`
> `    "activeEnergyBurned"?, "distanceMeters"?, ...`

That is a field list in JSON brackets: no colons, no values, and `?` suffixes that JSON does not
allow. A reader who copies it gets a parse error. The metrics block above it is closer to JSON:
it has keys, colons and values, and parses once the ellipses are replaced.

Replacement: label the fence `text` and open it with `workout row (fields; ? marks optional)` or
give one real row in the same style as `{ "d": "2026-10-31", "v": 57.2 }`.

### N16. The heading scopes one test to the wrong machine
`design_draft.md:249` and `:256`

> ### Verification still required, on device
> ...
> - Server acceptance of a real file: `node server.mjs --doctor` against the synced directory.

`--doctor` runs on the Mac or the NAS, not on the phone. Rename the heading to "Verification still
required" and tag the last bullet "on the Mac". While there: "verified by checksum on both ends"
(line 247) names no command, so either give the check (`shasum` on the source and the NAS copy) or
drop "by checksum".

## Terminology table

| Concept | Names in the document | Use |
|---------|-----------------------|-----|
| the iOS app | `HealthSync` (1, 22, 65), "the app" (29, 125, 137, 251, 265) | `HealthSync` at first mention, then "the app" |
| the paid app | `MetricBridge` (12, 160), "the app that was avoided" (263) | `MetricBridge` only |
| the Mac to NAS job | "a launchd job" (10), "the Mac job" (78, 137, 270), "the sync" (232) | "the Mac sync job" |
| the person | "the owner" (8, 29, 40), "a user chosen" (124) | "the user" |
| what the app writes | "export" (136, 251), "snapshot" (137), "the app's fresher data" (270) | "snapshot" |
| the metrics file | `.health-cache.json` (29, 144), "cache schema" (141), "metrics file" (139) | consistent: the file is named once and "metrics file" refers back to it |

The cache naming is consistent. No line calls it a "metrics cache" or a "health cache", and the two
filenames appear in full at first use, so a reader can follow which file is meant. The overload is
in "export", not in the cache names.

## Markdown checks

- Four fence markers, two balanced blocks. Both are unlabelled; the metrics block parses once the
  ellipses are replaced with values, the workouts block is a field list and not JSON (N15).
- No tables and no links in the document, so nothing to validate there.
- Heading levels are consistent (`##` then `###`), and the five `###` headings in the section are
  parallel in form.
- The `xcodebuild` command at lines 237 to 238 is one inline code span wrapped across two source
  lines. CommonMark renders it correctly, but the wrapped command is awkward to copy. Put it in a
  fenced block or keep it on one line.
- Bullet markers are consistently `-`, and the Files list uses ``**`path`**`` labels throughout.
  That structure is sound; only the separator inside it is the problem (N1).

## Claims that held up

- The build claim is current. `HealthSync.app` in DerivedData has mtime 17:27:03, the Swift source
  17:26:48, so the cited Release build postdates the last edit. "Compilation and linking are
  proven; runtime behaviour is not" is the correct reading of that evidence.
- The 18 quantity types claimed at lines 25 and 84 match the 18 entries in `SPECS`.
- Deployment target 17.0, bundle id, target name, `REFRESH_ID` and
  `BGTaskSchedulerPermittedIdentifiers` agree across `project.yml`, `Info.plist` and
  `HealthSyncApp.swift`.
- `HEALTH_SRC` with the `~/Tools/health-data` default is in `healthsync-nas.sh` line 7, as quoted.
- `get_mcp_status` does return `ok` and `lastDataDate` (`healthstore.mjs` lines 293 and 309), so
  step 6 checks a field that exists.
- `apple-export-to-cache.py` writes the same two filenames (lines 183 and 184), so the two-producer
  warning at line 268 is correct and the converter really does divide percentages by 100.
- The workout field list matches the keys the Swift writer sets, including `distanceSource` and the
  optional energy, distance, heart rate and elevation fields.
- The button label in step 4 matches the Swift UI string at line 378.

## Verdict

Not approvable until M1 to M3 are fixed. The section is otherwise careful, and the one place where
it could overstate, the verification list, is hedged in the right direction and survives checking.
The three MAJOR findings are all numbers or a contradicted capability: 423 against 449, 18 and 400
against 19 and 295, and "coexist" against "must not share an output folder". That is the same
failure mode as the earlier style review, file sizes written from memory after the file changed.
Two of the three are one-line edits; the third is a clause.
