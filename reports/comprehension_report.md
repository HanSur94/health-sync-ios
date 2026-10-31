# Comprehension report — HealthSync design draft

Reviewer: EGM Goldfish, fresh context. Input: `design_draft.md` only (241 lines). No other
file in the project was treated as context; where I peeked elsewhere to check whether something
was defined *somewhere*, that is stated explicitly and does not count as comprehension.

Split applied: everything before line 163 (`## Detailed Implementation Plan`) is the feature
spec; from that header to the end is the implementation plan. `[guess: …]` markers below are
places I had to invent a fact to keep reading — each is also a finding.

---

## Part 1 — Paraphrase of the feature spec (lines 1–161)

### What the document says the feature does

Apple Health data cannot be read remotely; only an app running on the iPhone can read HealthKit,
and only for the data types the owner has individually allowed. Everything downstream of the
phone already exists in this household: an MCP server on the NAS (`health-export-mcp`) exposing
14 query tools to "the agent", and a launchd job on the Mac that copies files up to the NAS.
The missing piece is the producer on the phone. The producer that used to work is a paid app
(MetricBridge, €24.99). The free options are either manual (Apple's "Export All Health Data" zip
plus a converter, minutes of generation time) or a Shortcuts graph that is slow and fails silently.

So the feature is: a small single-screen iOS 17+ app, read-only on HealthKit, that on launch and
on a best-effort background refresh (1) asks for read permission on 19 quantity types plus sleep
and workouts, (2) runs one statistics query per quantity type over the last 730 days, bucketed
into local calendar days, summing cumulative metrics and averaging the rest, (3) turns sleep
segments into hours per "wake day", (4) writes `.health-cache.json` and
`.health-workouts-cache.json` into a folder the user picks once (held as a security-scoped
bookmark), and (5) leaves those two files to the existing Mac→NAS job and the unchanged server.

Goals: byte-compatible schema with what the server already reads; works on a free Apple developer
account (hence a user-picked folder instead of an iCloud container entitlement); covers the
metrics the tools actually query; one explicit aggregation rule per metric. Non-goals: no writing
to HealthKit, none of the five optional context files, no intraday file, no UI beyond a folder
button / export button / status line, no App Store, no replacement of the Python converter (which
stays as the manual fallback).

### How the data flows, as I understand it

iPhone: HealthSync queries HealthKit → writes two JSON files into `HealthSync/`, a folder inside
the user's iCloud Drive. iCloud syncs that folder to the Mac, where it appears at
`~/Library/Mobile Documents/com~apple~CloudDocs/HealthSync`. A launchd job on the Mac
(`healthsync-nas.sh`) tars them and pipes over ssh to `/volume1/docker/health-export/data/` on
the NAS. The MCP server there reads that directory and serves 14 tools to the agent.

Points in that chain I could not resolve from the text:
`[guess: that the "folder the owner picks once" must be inside iCloud Drive — the Overview says
only "a folder ... that already syncs", the diagram assumes it, and only the build steps pin it
to iCloud Drive]`. `[guess: that HEALTH_SRC is the only coupling and that the job's environment
is where it gets set]`. `[guess: that the Mac has the iCloud folder fully downloaded at the
moment the job runs]`. `[guess: that the app overwrites both files atomically so the job never
tars a half-written file]`.

---

## Part 2 — Paraphrase of the implementation plan (line 163 → end)

### What it says to build

Files: `project.yml` as an XcodeGen spec (one iOS app target, iOS 17.0, bundle id
`de.hannessuhr.healthsync`, explicit Info.plist and entitlements, automatic signing) so the
project file is 18 reviewable lines instead of a 400-line `project.pbxproj`. The entire app in
one file, `HealthSync/HealthSyncApp.swift`, "423 lines": metric table, aggregation, sleep,
workouts, JSON writing, bookmark handling, UI, background task — one file so schema knowledge
stays in one place. `Info.plist` with `NSHealthShareUsageDescription`, background modes `fetch`
and `processing`, `BGTaskSchedulerPermittedIdentifiers` = `de.hannessuhr.healthsync.refresh`,
portrait only. Entitlements with `com.apple.developer.healthkit`. The generated `.xcodeproj`,
never hand-edited. The document itself moves to `docs/designs/health-sync-ios.md` once approved.
`~/Tools/healthsync-nas.sh` and its LaunchAgent plist need, in the plan's words, no change to
their mechanism — only the source directory, reached through `HEALTH_SRC`.

Build and signing: `xcodegen generate`, open the project, pick the personal team, confirm the
HealthKit capability is clean, run on a connected iPhone, grant read for all types, then in the
app press "Ordner wählen (iCloud Drive)" and create/pick `HealthSync`, point the Mac sync source
at the iCloud path, run the sync once, and check that `get_mcp_status` in the agent returns
`ok: true` with `lastDataDate` of today.

Verification already done: a `xcodebuild` Release build with `CODE_SIGNING_ALLOWED=NO` succeeded
(compilation and linking proven, runtime not). The cache contract was proven indirectly: the
Python converter's output of the same shape was accepted by `node server.mjs --doctor`
(schema 1, 6 metrics, 9 workouts) and by live tool calls, with a step sum matching source data
and percentage handling correct. The Mac→NAS transport was checksum-verified on both ends.

Still to verify on device: first run and file appearance, the two hand-built unit conversions
(`vo2_max` in `mL/min/kg`, `walking_speed` in `km/hr`), background refresh firing (and being
skipped while locked), and server acceptance of a real synced file.

Known trade-offs: free provisioning expires weekly and the app stops launching until re-signed
(paid membership is €99/yr, more than the app being avoided); schema knowledge is duplicated
between `apple-export-to-cache.py` and `SPECS`, so a `healthstore.mjs` change must be applied
twice; `BGAppRefreshTask` is best effort, so no daily file can be promised.

### Where the plan stopped being followable

The plan is precise about *files* and *build steps* and vague about the *contract values*: the
19 metric rows, the workout field producers, the day-fill rule, the time zone, and the exact
place the schema of record lives are all absent or contradictory. A reader can build and sign
the app from this plan, but cannot write `SPECS` or the workout writer from it, and cannot
predict whether the Mac job will read complete, non-stale files.

---

## Findings

3 BLOCKER · 11 MAJOR · 8 NIT.

### BLOCKER

**B1 — The metric table is never enumerated, and the stated count contradicts the stated contents.**
Quote: "19 rows: HealthKit identifier, cache name, unit, cumulative flag, percentage flag" and
"Cache names match what `healthstore.mjs` and its alias map already understand (`step_count`,
`heart_rate_variability`, `resting_heart_rate`, …)".
Counting the types the document itself names in the aggregation paragraph gives 17, not 19:
cumulative — steps, distance, energy, "flights", exercise time, stand time, water (7); discrete —
heart rate, HRV, resting heart rate, walking heart rate, respiratory rate, oxygen saturation,
body mass, body fat, VO₂ max, walking speed (10). The Goals list instead says "body composition"
as one item, which would make the gap three. The other two rows appear nowhere, and the cache
names are given as three examples plus an ellipsis. "flights" occurs exactly once in the whole
document (in the `.cumulativeSum` list) and is in no other enumeration. The unit strings are part
of the cache (`"unit": "ms"`) but no unit list exists either.
Missing: the 19 rows, their cache names, units, cumulative and percentage flags. Without them the
central deliverable ("the exact cache schema") cannot be produced or checked.

**B2 — The workout contract requires three fields the document never defines.**
Quote, from the schema block: `[ { "id", "name", "activityType", "start", "end", "duration",`
… `"elevationAscendedMeters"?, "distanceSource" } ]`.
The Workouts paragraph lists "activity type raw value …, start and end as ISO 8601, duration in
seconds, active energy, distance, average and maximum heart rate, elevation gain" — it never says
what `id` is (HealthKit UUID? a synthesized key?), what `name` is (a localized display string? the
raw type cast to text?), or what `distanceSource` is or how to compute it. Two of the three are
non-optional in the schema. Field names are asserted to be "the ones the server's workout tools
read", so a wrong guess is a silent contract break.
Missing: producer rule for `id`, `name`, `distanceSource`.

**B3 — The schema of record is named three different ways and located nowhere.**
Quotes: "Produce the exact cache schema `healthstore.mjs` already reads"; "`node server.mjs
--doctor`"; "A change to `healthstore.mjs` must be applied to both."
`healthstore.mjs` and `server.mjs` are never related to each other or to "the server" /
`health-export-mcp`, and no path is given for either (the doc never says where the server checkout
lives — on the NAS, on the Mac, in `~/Tools/…`). The same applies to "its alias map", which is
cited as the authority for cache names but never identified. A reader who wants to resolve B1 and
B2 by reading the source is not told what to read.

### MAJOR

**M1 — No rule for days with no samples, and no ordering rule for `daily`.**
Quote: `"daily": [ { "d": "2026-10-31", "v": 57.2 }, … ]`. The contract shows one element. It
never says whether a day without samples is omitted or emitted as `0`, nor whether the array is
ascending by date. Both choices change every downstream `get_trends` / `compare_periods` result
and cannot be recovered from a one-element example.

**M2 — "local" is never pinned, and ISO 8601 timestamps have no stated offset.**
Quotes: "aggregating per local calendar day"; "a one-day interval anchored to local midnight";
"start and end as ISO 8601". Local to what — the device's time zone at export time, or a fixed
zone stored with the file? What happens to a 730-day backfill after travel or a DST change? And
does "ISO 8601" mean `2026-10-31T08:00:00Z` or `…+01:00`? The server's day-bucketing depends on
this; the reader has to pick.

**M3 — Nothing says the two files are written atomically, or how the Mac job avoids reading a
partial/newly-synced file.**
Quote: "writes `.health-cache.json` and `.health-workouts-cache.json` into a folder" plus
"tar | ssh" on a schedule. There is no temp-file-and-rename step, no statement about whether the
two files are consistent with each other, and no statement about when the launchd job runs
relative to an export. A reader cannot tell whether a half-written cache can reach the NAS.

**M4 — The iCloud handoff assumes the Mac has the bytes; nothing guarantees it.**
Quote: "drops two JSON files into a folder that already syncs to the Mac". The plan never says the
Mac must be signed into the same Apple ID, that iCloud Drive must be enabled, or that the files
must be materialized (not dataless placeholders) before the job tars them. Given "Optimize Mac
Storage" is on by default on many Macs, `tar` may read placeholders. Missing: a precondition or a
download step.

**M5 — "No change is required" and "a one-line change" are both asserted, and the environment
route is hand-waved.**
Quotes: "The Mac job does not change shape, only its source: it reads `HEALTH_SRC` (default
`~/Tools/health-data`) and the folder the iPhone writes to is pointed at with that variable."
That sentence is not parseable as written — the second clause has no clear subject or verb
relationship to the first. Then: "no change needed to the script itself. Its source is already
`${HEALTH_SRC:-$HOME/Tools/health-data}`; the launchd plist's environment or a one-line default
change points it at the iCloud folder". A LaunchAgent does not inherit a login shell's exports, so
"the launchd plist's environment" is the only route that works, but the doc presents editing the
default as an equally valid alternative and never shows either edit. The reader cannot tell how
many changes to make or where.

**M6 — No behaviour is specified when HealthKit permission is partial or denied.**
Quote: "grant read for all types". HealthKit lets the user allow some types and deny others, and
the app cannot detect read denial reliably. Does the export then omit those keys, emit empty
`daily` arrays, or write nothing at all? Does it still write `_meta`? Without this, a reader
cannot say what the server sees on a partially-authorized phone, and an omitted key may be worse
than an empty one.

**M7 — The background task is scheduled on launch only, which makes it fire at most once.**
Quote: "`BGAppRefreshTask` with an earliest start six hours out, re-scheduled on every launch,
plus a plain export whenever the app opens." A refresh task that is not re-submitted from inside
its own handler is not recurring. Either the doc means "re-scheduled on every launch and after
every run" or the described behaviour is one-shot — the reader has to guess which, and the two
produce different reliability claims (and different text for the trade-offs section).

**M8 — The workout query has no time window.**
Quote: "`HKSampleQuery` over `HKWorkout`". The 730-day window is stated only for the statistics
queries ("over the last 730 days" in the Overview, and in Aggregation). Workouts may therefore be
all-time or 730 days; on a phone with a decade of history the two differ by file size and by what
the tools report. Missing: the predicate.

**M9 — The verification evidence contradicts the metric count.**
Quotes: "(schema 1, 6 metrics, 9 workouts)" against "19 rows" and "19 quantity types". The text
says "an earlier artefact of the same shape" — "artefact" is never defined as the Python
converter's output, and nothing says the artefact was a 61-day synthetic export. A reader
reasonably concludes either that the real cache holds 6 metrics (contradiction) or that the
contract was never tested at full width (also a finding). Either way the evidence cannot be
weighed as written.

**M10 — Nothing says the LaunchAgent can read the picked folder.**
Quote: "`~/Library/LaunchAgents/com.hannes.healthsync.plist` — unchanged in mechanism; only the
source directory resolves differently through `HEALTH_SRC`." The new source is inside
`~/Library/Mobile Documents`, a protected location; the doc never says whether this job needs
Full Disk Access, will hit a prompt, or will silently tar nothing. Step 5 ("point the sync source
… and run the sync once") has no expected-failure mode, so a reader cannot distinguish "not yet
synced" from "not permitted".

**M11 — "The agent" is never defined, and the final verification step assumes access the reader
does not have.**
Quotes: "exposes 14 query tools to the agent"; "`get_mcp_status` in the agent must report
`ok: true` with a `lastDataDate` of today." Which program is "the agent", how does it reach the
NAS server, and where do you type `get_mcp_status`? `lastDataDate` is introduced here for the
first time, as a field name with no owner (a field of that tool's response, presumably). The
document's author line says "Hannes Suhr + Hermes", which is the only hint, and it is not a
definition.

### NIT

**N1 — An API is used in the diagram before it is introduced.** Quote: "HKStatistics /
CollectionQuery ───". The concept is only explained 20 lines later under Aggregation. Harmless
for an iOS reader, but it is the first thing on the page after the Overview.

**N2 — "MCP" is never expanded.** Quote: "a `health-export-mcp` server on the NAS exposes 14 query
tools". A reader outside this household cannot tell whether MCP is a protocol, a product, or the
name of a script. Likewise "HealthKit" is used from line 7 without ever being defined as Apple
Health's on-device data framework.

**N3 — `_meta` is under-specified.** Quote: `"writtenAt": "…"`. Format unstated (ISO 8601 with
offset? epoch ms?), and "`_meta.schema` stays 1" never says who would ever raise it or what the
app should do if it reads a higher value from an existing file.

**N4 — The percentage flag is used before it is defined, and then vanishes from the contract.**
Quote: "cumulative flag, percentage flag" (line 84), explained 13 lines later, and absent from
the cache schema block — so the reader must infer it is a conversion-time-only flag.

**N5 — The BG identifier is asserted to need an exact match with an unnamed constant.** Quote:
"the identifiers string must match the constant in the Swift file exactly". Which constant? The
reader is told a mismatch crashes but not what to compare against.

**N6 — A background mode is declared with no matching task.** Quote: "background modes `fetch` and
`processing`". The app only registers a refresh task; `processing` implies a
`BGProcessingTask` that is never described. Either drop it or say why it is there.

**N7 — The UI language flips for one string.** Quote: "Ordner wählen (iCloud Drive)". The
Overview calls it "a folder button"; the build step is the only place the actual label appears,
in German, inside an English document. A reader implementing the UI has to guess the string
language.

**N8 — The on-device check names files the reader cannot see.** Quote: "two files appear in the
picked folder". The file names begin with a dot; in the iOS Files app and in Finder they are
hidden by default. The verification step as written will look like a failure on a correct run.

---

## Residual doubt

I could not separate two of the document's claims without outside knowledge: whether a free
personal team can carry the HealthKit capability at all, and whether `BGAppRefreshTask` survives
a locked device (the doc marks this "expected to skip", which is an admission, not a spec). Both
affect whether the build steps can be followed by someone else, and neither is answerable from
the text.
