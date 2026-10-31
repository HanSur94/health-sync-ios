# Critic: style, clarity, and number labelling

Documents: `design_draft.md` (241 lines), `concepts_brief.md` (50 lines).
Cross-checked against: `HealthSync/HealthSyncApp.swift`, `project.yml`,
`HealthSync.xcodeproj/project.pbxproj`, `~/Tools/health-export-mcp/server.mjs`,
`healthstore.mjs`, `~/Tools/healthsync-nas.sh`.

Rules applied: plain English, no marketing adjectives or decorative adverbs, no em or en
dashes, one name per concept, valid tables and fences, no benefit asserted without a
mechanism, every number measured or tagged as a target.

Result: **7 MAJOR, 12 NIT.** The prose is mostly description rather than persuasion, and it
states its own limits in the right places: line 217 says "runtime behaviour is not" proven,
and line 240 says `BGAppRefreshTask` is best effort. The problems cluster in two places:
numbers written from memory instead of measured, and one sentence in the brief that is false.

---

## Number audit

The documents have no labelling convention. `concepts_brief.md` has one heading,
`What already exists (measured, not planned)`, which is the correct idea applied once. Every
number below was checked against the artefact named in the Status column.

| # | Doc:line | Claim as written | Status | Action |
|---|----------|------------------|--------|--------|
| 1 | design:9 | "exposes 14 query tools" | measured, correct (14 registrations in `server.mjs`) | call them "14 MCP tools", not all are queries |
| 2 | design:12, 139 | "€24.99 once" | external fact | none |
| 3 | design:14 | "minutes of generation" | unmeasured estimate | hedge or drop the duration |
| 4 | design:25 | "19 quantity types" | **wrong: 18** in `SPECS` | correct to 18 |
| 5 | design:25 | "iOS 17 or later" | target | tag as target |
| 6 | design:26 | "last 730 days" | target (also `LOOKBACK_DAYS = 730`) | tag as target |
| 7 | design:84 | "19 rows" | **wrong: 18** | correct to 18 |
| 8 | design:89 | "one-day interval" | target | tag as target |
| 9 | design:93 | "two-year window costs roughly the same as a two-day window" | unmeasured | see M3 |
| 10 | design:97 | "0..100 for `%` types", "0.97 is 97 %" | HealthKit documented behaviour | none |
| 11 | design:106 | "37 running, 13 cycling, 52 walking" | matches `HKWorkoutActivityType` raw values | none |
| 12 | design:116 | "earliest start six hours out" | target | tag as target |
| 13 | design:134 | "`_meta.schema` stays 1" | measured (server accepts 1) | none |
| 14 | design:154 | "~420 lines" | measured, rounded (423) | use 423 or drop the "~" |
| 15 | design:169 | "18 readable lines" | **wrong: 19 lines** | correct to 19 |
| 16 | design:170 | "a 400-line `project.pbxproj`" | **wrong: 295 lines** | see M6 |
| 17 | design:172 | "423 lines in one file" | measured, correct | none |
| 18 | design:220 | "schema 1, 6 metrics, 9 workouts" | measured in the cited run | none |
| 19 | design:236 | "every seven days", "€99/year" | Apple's documented limits | none |
| 20 | design:231 | "surviving a locked device (expected to skip)" | assumption, explicitly tagged | none |
| 21 | brief:8 | "14 MCP tools" | measured, correct | none |
| 22 | brief:17 | "61-day synthetic export" | measured | none |
| 23 | brief:18 | "6 metrics, 9 workouts, step sum matched" | measured | none |
| 24 | brief:20 | "rsync 3.4.1" | external, verifiable | none |
| 25 | brief:38 | "a 14-day by 8-metric daily cache" | hypothetical, not tagged | tag as example |
| 26 | brief:42 | "~350 lines" | **wrong: 423** | see M5 |
| 27 | brief:46 | "every 7 days" | external | none |

Net: five rows are wrong, covering four distinct quantities (the metric count, items 4 and
7; the `project.yml` line count, item 15; the `project.pbxproj` line count, item 16; the app
line count in the brief, item 26). Five rows are untagged targets (5, 6, 8, 12, 25). The
rest hold up.

---

## MAJOR findings

### M1. The brief asserts something false about the platform
`concepts_brief.md:7`

> Apple Health has no API.

HealthKit is an API. What Apple Health lacks is a remote, server-side API, and the design
document says exactly that (`design_draft.md:7`, "Apple Health has no remote API"). The
brief drops one word and turns a correct constraint into a false one, and then contradicts
itself two lines later ("The only way data leaves the phone is an app that reads HealthKit").

Replacement: `Apple Health has no remote API. HealthKit is an on-device API that only an app running on the iPhone can read.`

### M2. The metric count is 19 in two places, 18 in the code
`design_draft.md:25`

> requests HealthKit read permission for 19 quantity types plus sleep analysis and workouts

`design_draft.md:84`

> **Metric table (`SPECS`).** 19 rows: HealthKit identifier, cache name, unit, cumulative flag,
> percentage flag.

`grep -c '.init(id:' HealthSync/HealthSyncApp.swift` returns 18. The document states a
permission request the code does not make. The Goals list compounds this: it describes the
coverage in prose and omits `flights_climbed` and `basal_energy_burned`, both of which
`SPECS` requests.

Replacement at 25: `requests HealthKit read permission for 18 quantity types plus sleep analysis and workouts;`
Replacement at 84: `**Metric table (`SPECS`).** 18 rows: ...`
Replacement at 41-43: add `flights climbed, basal energy` to the coverage list.

### M3. Unmeasured performance claim presented as a consequence
`design_draft.md:93`

> Aggregation happens inside HealthKit, so a two-year window costs roughly the same as a
> two-day window. This is the reason the app exists rather than a Shortcut.

The mechanism is stated, which is good, but the cost comparison has never been timed. No
run of the app was measured; the Verification section only proves compilation. "Roughly the
same" is doing persuasive work that no evidence supports, and it is the sentence the whole
architecture choice leans on.

Replacement: `Aggregation runs inside HealthKit rather than in the app, so the cost is a fixed number of statistics queries per metric rather than a loop over samples. The 730-day export has not been timed.`

### M4. Shortcuts limitations stated as measured findings without a measurement
`design_draft.md:145`

> heavy queries take minutes and fail quietly

`concepts_brief.md:38`

> a 14-day by 8-metric daily cache becomes a large fragile graph that fails silently

The design document says these constraints were checked ("Rejected after checking the actual
constraints"), then gives no numbers and no failure. "Minutes" is a duration estimate,
"fails quietly" and "fails silently" are predictions about a graph that, as far as the
documents show, was never built. The static type picker and the missing per-day grouping
primitive are the real, checkable constraints and they carry the argument on their own.

Replacement (design:145): `each Find Health Samples action carries one fixed sample type, so N metrics need N actions, and there is no per-day grouping primitive, so the day loop has to be built out of filters.`
Replacement (brief:38): delete `becomes a large fragile graph that fails silently`; end the sentence at `there is no per-day grouping primitive`.

### M5. Two documents give two different sizes for the same file
`concepts_brief.md:42`

> no advantage over owning ~350 lines

`design_draft.md:154`, `design_draft.md:172`

> the ~420 lines
> the whole app, 423 lines in one file

`wc -l` says 423. The brief understates it by 17 %, and both figures sit in a document set that
claims to distinguish measured from planned. This is the kind of number a reader checks
first, and finding it wrong costs credibility for the ones they cannot check.

Replacement (brief:42): `no advantage over owning 423 lines.`

### M6. Inflated file size used to argue for a tool choice
`design_draft.md:170`

> the project file is generated from 18 readable lines instead of a 400-line `project.pbxproj`
> that no one can review

`wc -l HealthSync.xcodeproj/project.pbxproj` returns 295. `wc -l project.yml` returns 19.
Two numbers, both wrong, both on the same line, both aimed at making XcodeGen look like the
obvious choice. "That no one can review" is also unarguable: the file exists and this project
generated it.

Replacement: `the project file is generated from a 19-line spec instead of a 295-line `project.pbxproj` that must be regenerated rather than edited by hand.`

### M7. "The one that works" excludes a path the document later endorses
`design_draft.md:12`

> The one that works, MetricBridge, costs €24.99 once.

Line 148 says of the free manual export: "Works today and is verified." Two lines apart in
argument, opposite claims about the same fact. The intended meaning is "the one that works
unattended", and it should say so.

Replacement: `The option that works without manual steps, MetricBridge, costs €24.99 once.`

---

## NIT findings

### N1. Em dashes: 9 total
Eight in `design_draft.md` (lines 167, 172, 177, 182, 185, 188, 191, 197), one in
`concepts_brief.md:1`. No en dashes anywhere; the box drawing in the data-flow diagram uses
`─` (U+2500), which is correct and should stay.

Fix: in the Files section replace `** — ` with `**: ` and start the sentence lower case, or
restructure as `**path**. Definition: ...`.

> `**`./project.yml`** — XcodeGen spec:`

becomes

> `**`./project.yml`** is the XcodeGen spec:`

Title at `concepts_brief.md:1`: `# Concepts brief: HealthSync (iOS) — Apple Health to the local MCP server`
becomes `# Concepts brief: HealthSync (iOS), Apple Health to the local MCP server`

### N2. "the app is honest about that"
`design_draft.md:118`

> iOS decides when it actually runs; the app is honest about that and the manual button is
> always available.

An app cannot be honest. This is the one place the document reaches for personality instead
of mechanism.

Replacement: `iOS decides when it actually runs, so the app cannot guarantee a refresh, and the manual export button is always available.`

### N3. "Cleaner" as a reason
`design_draft.md:156`

> Cleaner, and impossible on a free account

"Cleaner" is a judgement with no criterion attached, and the sentence then explains why the
option is unavailable, so the adjective adds nothing.

Replacement: `A container removes the folder picker, and it is impossible on a free account:`

### N4. "Free and permanent"
`design_draft.md:142`

> Free and permanent, no signing.

Nothing about a Shortcuts graph is permanent; iOS releases change Shortcuts, and the document
itself notes HealthKit needs an unlocked device either way.

Replacement: `Free, and no signing required.`

### N5. Unverifiable prediction about future readability
`design_draft.md:146`

> The result is a large graph that cannot be read or debugged months later.

Replacement: `The result is a graph whose per-metric actions and day loop have to be reconstructed before it can be changed.`

### N6. Four names for the Mac to NAS job
`design_draft.md:10` "a launchd job", `:31` "the existing Mac job", `:78` "The Mac job",
`:191` "`healthsync-nas.sh`", `:197` "the launchd plist".

Pick one and use it everywhere: `the Mac sync job`, naming the script
`~/Tools/healthsync-nas.sh` on first use.

### N7. "the owner" against "the user"
`design_draft.md` uses "the owner" at lines 8, 30, 40 and "user chosen" at 111; the brief uses
"the user" at 26 and "Hannes" at 10. Pick `the user` in both documents; use `Hannes` only
where a decision is attributed to him.

### N8. "14 query tools" against "14 MCP tools"
`design_draft.md:9` says query tools, `:74` says MCP tools. `get_mcp_status` is not a query.
Use `14 MCP tools` in both.

### N9. Status line undersells and overstates at once
`design_draft.md:3`

> Status: draft, implementation compiles

"implementation compiles" is not a status a reader can act on, and the body is careful to say
compilation is proven and runtime is not. The line should carry that distinction.

Replacement: `Status: draft. Release build succeeds; not yet run on a device.`

### N10. Redundant negatives
`design_draft.md:34`

> No account, no server of ours, no dependency, no third-party SDK.

"no dependency" and "no third-party SDK" say the same thing, and the app does depend on
HealthKit and SwiftUI. Drop one clause and scope the other.

Replacement: `No account, no server of ours, no third-party SDK.`

### N11. The workout schema block is not JSON
`design_draft.md:129-131`

> `[ { "id", "name", "activityType", "start", "end", ... } ]`

That is a field list wearing JSON syntax: no colons or values. A reader who copies it gets a
parse error, and the same fence style two blocks earlier does parse. Either label it or give
one real row.

Replacement: open the fence as `jsonc` and write `[ { "id": "...", "name": "Running", "activityType": 37, "start": "2026-10-31T07:12:00+01:00", "end": "...", "duration": 1830, "distanceSource": "healthkit" } ]`, with a comment line above it saying the remaining fields are optional.

### N12. The document lists itself under a path it does not have
`design_draft.md:188`

> **`./docs/designs/health-sync-ios.md`** — this document, once approved.

`./docs/designs/` exists and is empty, and the file under review is
`design_draft.md`. "This document, once approved" is doing the work of a file that is not
there yet.

Replacement: `**`./docs/designs/health-sync-ios.md`** will be the canonical copy of this document once approved; `design_draft.md` is the working copy.`

---

## Format checks

- Markdown tables: neither document contains one, so nothing to validate. The table above is
  the only one in the set and uses a consistent five-column layout.
- Code fences: 4 fence markers in `design_draft.md`, so 2 balanced blocks; none in the brief.
  The data-flow diagram fence is language-less by choice and renders correctly.
- Headings: consistent `##`/`###` levels, Title Case throughout. `Non-Goals` is the only
  hyphenated heading and is fine as written.
- Terminology otherwise holds: `cache schema` and `cache name` are used consistently, the
  bundle id, the `REFRESH_ID` string and the launchd label match across both documents and
  the source files.

## Claims that held up

Checked and correct, so nobody needs to re-verify them: 14 MCP tools (`server.mjs`), 423
lines in `HealthSyncApp.swift`, 295-line generated project file, `HEALTH_SRC` with the
`~/Tools/health-data` default (`healthsync-nas.sh:6`), the `--doctor` flag, the
`com.hannes.healthsync.plist` label, and `HEALTH_DATA_DIR` as the server's variable.

## Verdict

Not approvable as written. M2 and M5 are the ones that matter: a count that disagrees with the
shipped code and a file size that disagrees with itself across two documents both undermine the
document's central method, which is to separate what was measured from what is planned.
Fixing M1 through M7 and N1 through N5 is a short edit; the rest can wait for review.
