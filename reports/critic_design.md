# Design critique — HealthSync (feature-spec half)

Scope: `design_draft.md` lines 1–161 (everything before `## Detailed Implementation Plan`),
`concepts_brief.md`, `HealthSync/HealthSyncApp.swift`. Claims were checked against the actual
consumer (`~/Tools/health-export-mcp/healthstore.mjs`, `server.mjs`, `prompts.mjs`), the verified
producer (`~/Tools/apple-export-to-cache.py`), the transport (`~/Tools/healthsync-nas.sh`) and
`HealthSync/Info.plist`.

Counts: **4 BLOCKER · 10 MAJOR · 4 NIT**

## Verdict

The problem is real: Apple Health has no remote API, and the agent's own prompts assume daily
freshness — `prompts.mjs:21` tells the model "if it is older than yesterday, say so plainly",
which a manual export cannot satisfy. So an app is probably justified — but **not by this
document**. It is a justification written after the code ("Status: draft, implementation
compiles", design_draft.md:3), and its load-bearing assumptions (bookmark delivery, cheap 730-day
aggregation, "nothing leaves your devices") are asserted, not measured. The two claims that would
carry the design — HealthKit's source deduplication, and the freshness requirement with a number —
are never made. Reject as written; the app may still be right.

## BLOCKER

**B1. One denied or failed run replaces good data with an empty file, and the unchanged Mac job
ships the wreckage.**
The app writes both files unconditionally (design_draft.md:29–31, `HealthSyncApp.swift:96–97`)
after `authorize()`, which does not throw when the user denies access (`:298–299`). A denial, a
locked device, or a first-launch hiccup therefore produces `{"_meta": …}` (metrics are skipped when
empty, `:83`) and that file is copied to the NAS by the existing tar job. `healthstore.mjs:293`
then reports `ok:false` — after the previous cache is gone; nothing on the NAS is versioned.
The design's only stated failure mode is schema (design_draft.md:134–135); emptiness and partial
denial are unaddressed. *Fix:* refuse to write below a metric-count floor, keep the last-good file,
and validate JSON + `_meta.schema` in `healthsync-nas.sh` before overwriting the NAS copy.

**B2. The free-account expiry is missing from the design draft.**
Goals sell the free account as a pure win (design_draft.md:39–40, 55). The 7-day provisioning
expiry appears only in `concepts_brief.md:46`, and it is the single largest operational cost in the
system: a data pipeline whose producer must be re-signed from Xcode weekly, on an axis (uptime) on
which the rejected Shortcuts alternative was described as "free and permanent"
(design_draft.md:143–146). A spec that omits it is not honest about what is being chosen. *Fix:*
state the expiry as a goal-level constraint, name who re-signs and what happens to the data when
it lapses, and weigh it against MetricBridge's €24.99 on the same axis.

**B3. "No cloud" contradicts the chosen transport.**
Concepts says "no cloud" (`concepts_brief.md:3,26`); the data path is iCloud Drive
(design_draft.md:63–70), and the shipped usage string says "nothing leaves your devices"
(`HealthSync/Info.plist`, `NSHealthShareUsageDescription`). Both statements are false: HealthKit
data transits Apple's servers and requires an Apple ID. The LAN alternative was rejected for
needing "a receiver daemon … token handling and a network route" (design_draft.md:159–161), i.e.
infrastructure this household already runs (NAS Docker + Tailscale). *Fix:* pick one story —
drop the "no cloud" claim as the honest, least-bad hop, or take the LAN route — and correct the
user-facing string either way.

**B4. The delivery mechanism is the whole integration and has no verification.**
Design_draft.md:110–114 calls the security-scoped bookmark "the one unusual choice and it is
deliberate" — deliberate is not verified. No on-device result is reported anywhere. The code saves
a `.minimalBookmark` (the option documented to keep only the path), never starts access on the
picked URL before bookmarking, ignores `stale` and swallows resolution errors with `try?`
(`HealthSyncApp.swift:252–263`). There is no recovery path when the bookmark goes stale (device
restore, container recreation), no check that the chosen folder is actually synced (picking
"On My iPhone" reports success and nothing ever arrives), and no post-write readback. *Fix:* one
paragraph of observed behaviour — write lands, appears on the Mac, survives relaunch and 8 days —
plus a stale/failed-write path that tells the user to re-pick.

## MAJOR

**M1. 730 days makes the app and its "fallback" mutually destructive.**
The app rewrites the whole file with a 730-day window (design_draft.md:26–27, 40;
`HealthSyncApp.swift:96–97`), while the converter stays as the fallback (design_draft.md:56,
148–150) and produces full history. Whichever ran last wins the history depth: a converter
backfill followed by one app launch silently deletes every day older than two years, and there is
no merge, no `_meta` history marker, no warning. *Fix:* declare one producer per file, or merge on
the Mac before copying; if the app owns it, state "history capped at 2 years" as a goal.

**M2. "HealthKit-side aggregation is why this beats Shortcuts" is the wrong argument, stated
wrongly.** "a two-year window costs roughly the same as a two-day window"
(design_draft.md:89–95) is not true: one *query* per type is constant, but bucket count scales
linearly (730 vs 2) and HealthKit still scans every sample in range. And the app does exactly what
it faults Shortcuts for on the two paths that matter most: sleep is an unbounded per-sample query
over two years (`HealthSyncApp.swift:125–135`) and workouts likewise (`:149–158`); the code
comment "no per-sample loop" (`:100`) holds only for quantity types. The genuine differentiator —
HealthKit deduplicates overlapping iPhone/Watch sources, whereas the verified converter sums raw
XML records and double-counts steps — is never claimed (compare
`apple-export-to-cache.py:108–114`). *Fix:* lead with dedup; demote aggregation to "one query per
type"; measure one real run instead of asserting cost parity.

**M3. No acceptance criteria and no verification step.**
"implementation compiles" (design_draft.md:3) is presented as status, and Goals (36–45) contain no
falsifiable outcome. The rest of this project is strong on verification — "npm test green",
"checksum verified", "step sum matched the XML exactly" (`concepts_brief.md:14–20`) — and the new
producer gets none. *Fix:* one test: same 61-day period through both producers, diff per metric and
day, record the expected deltas (dedup, timezone). That single artifact would also settle M1, M2,
M4, M9.

**M4. The schema is duplicated three ways and the copies have already diverged.**
"One table, one place to add a metric" (design_draft.md:85) is false: the Swift `SPECS`
(`HealthSyncApp.swift:19–38`), the Python `MAP` (`apple-export-to-cache.py:20–40`) and the server's
alias map (`healthstore.mjs`, `ALIASES`) each hold it. The design says "19 rows" twice
(design_draft.md:25, 84); `SPECS` has 18, and the converter's 19th — `sleep_duration_goal`
(`apple-export-to-cache.py:39`) — is missing from the app, so switching producers silently drops a
metric. The only mitigation offered is prose ("both must match", `concepts_brief.md:49–50`).
*Fix:* one `metric-map.json` with the Swift table and the Python `MAP` derived from it, or the M3
parity test.

**M5. Read-permission denial is invisible by construction.**
HealthKit cannot report per-type read authorization, so a denied metric simply disappears
(`HealthSyncApp.swift:83`) with the same shape as "no samples". Goals claim coverage of 19 types
(design_draft.md:25, 41–43); the file records neither which types were requested nor which were
absent, so the agent cannot tell a gap from a quiet week. *Fix:* write `_meta.requested` /
`_meta.missing` and keep the metric out only with a record of why.

**M6. The sleep goal is overstated.**
"Cover what the MCP tools actually query: … sleep" (design_draft.md:41–43) ignores that
`get_sleep_sessions` — the tool two prompts actually use for sleep (`prompts.mjs:42, 47`) — reads
`health-sessions.json` (`server.mjs:200–201`), which is explicitly a non-goal
(design_draft.md:50–52). Daily hours alone cannot answer bedtime spread or split nights. *Fix:*
narrow the goal to "daily sleep hours", or add sessions to scope.

**M7. The background refresh is expected to fail, by the design's own admission.**
Design_draft.md:116–118 offers "iOS decides when it actually runs" as the only caveat, while
`concepts_brief.md:48` states HealthKit is unreadable while locked — and `BGAppRefreshTask` is
precisely the kind that fires when the device is idle. So the background path is not merely
best-effort; it is likely to fail systematically, and a failed run still writes (B1).
*Fix:* say the background path is unproven, guard it against writing, or drop it and own
"foreground only, triggered when you open the app".

**M8. The Mac transport did change shape, and the script cannot tell a placeholder from data.**
"the existing Mac job does not change shape, only its source" (design_draft.md:78–80) ignores that
`healthsync-nas.sh` tars the whole source directory (`tar czf - -C "$SRC" .`) to the live data
directory. An iCloud file the Mac has not materialised is a `.health-cache.json.icloud`
placeholder; tar will happily ship it. *Fix:* a pre-copy check (`brctl download`, or `jq -e` on
both files) — the script already exits on a missing dir, so the pattern exists.

**M9. Day boundaries change meaning versus the verified converter, silently.**
Design_draft.md:26, 89–95 says "local calendar day" without stating that HealthKit re-buckets all
730 days in the phone's *current* timezone, while the converter uses each record's own UTC offset
(`apple-export-to-cache.py:52–54, 97`). After travel, historical days get resliced and the numbers
move. The server ships tooling built on the opposite assumption (`excludeTravelDays`,
`prompts.mjs:99`: "a day on which the timezone changed was not 24 hours long"). *Fix:* state the
rule as a known delta from both the converter and the server's travel tooling.

**M10. The alternatives table compares capability, never cost or failure.**
MetricBridge is dismissed honestly ("the request was to not buy an app",
design_draft.md:139–140) — fine. But Shortcuts is judged only on graph shape and speed, while the
app is called "free" with no mention of weekly re-signing; LAN push is rejected for infrastructure
that exists; the manual export is kept as "fallback" without noting M1. No option is scored on
uptime, maintenance or history depth, which are the only axes that differ. *Fix:* a 4-row table
(app / Shortcut / manual / MetricBridge) × {build cost, weekly cost, failure mode, history depth}.

## NIT

**N1.** "19 quantity types" / "19 rows" (design_draft.md:25, 84) vs 18 in `SPECS`
(`HealthSyncApp.swift:19–38`). Fix the number or add the row (see M4).
**N2.** Workouts collapse everything outside 11 types to `Other` (`HealthSyncApp.swift:204–217`),
so `get_workouts({activityType:"Tennis"})` fails and `byActivityType` lumps the rest; the converter
keeps the HealthKit type name (`apple-export-to-cache.py:137,145`). Cheap fix: `snake` the raw type
name for `name`, keep the numeric `activityType` as the join key.
**N3.** Every launch rewrites 730 days × 18 metrics into iCloud with no freshness check
(`HealthSyncApp.swift:376–378`). Skip when `_meta.writtenAt` is already today, or restrict the
launch export to a short window.
**N4.** The percentage rule is stated twice as "one conversion in one place"
(design_draft.md:97–98, `HealthSyncApp.swift:116`) while the unit table duplicates units already in
the schema string (design_draft.md:124–125) — two spellings of the same contract that can drift.

## What would make this defensible

1. A stated freshness requirement with a number (the prompts already imply <24 h) — that is the
   goal the whole app exists to meet, and the only fair yardstick against manual export.
2. One acceptance test: both producers over the same 61-day period, diffed per metric and day.
3. A write guard + last-good file + a JSON/schema check in `healthsync-nas.sh` (kills B1, M8).
4. A single metric map, generated into Swift and Python (kills M4, N1, N4).
5. One honest paragraph on cost of ownership: 7-day re-sign, locked-device background failure, and
   history capped at 2 years — with the decision to accept them stated, not implied.
