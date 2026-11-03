# HealthSync: what "professional" means here

* **Author:** Hannes Suhr + Hermes
* **Date:** 2026-11-02
* **Status:** brainstorm. One Goldfish lens completed and was re-verified; five were lost to a backend failure (see bottom).

## Overview

The ask was a "proper iOS app, more professional, built from the current system". The current
system is `health-sync-ios`: 902 lines in one file, one screen at `HealthSyncApp.swift:634`, a
read-only HealthKit-to-JSON exporter whose output an MCP server on the Mac reads. The proposal
that went to review kept the engine and added a "Heute" screen above the control panel, showing
sleep last night, steps, resting heart rate, workouts and export freshness.

The review rejected the screen. What follows is why, and what to build instead.

## Analysis

**The engine cannot stay untouched.** `run()` builds the entire metrics dictionary and the
sessions array, then returns three counts (`:57-61`, `:118-120`). Any screen showing a number
needs those values handed back out. "Just add a view" is a change to the exporter's contract.

**The content is Apple Health's Summary tab.** Sleep last night, steps, resting heart rate,
workouts. Apple's version is permission-aware and always current; a copy is a worse copy on a
surface no test can reach.

**The export takes about 35 seconds.** The code says so itself (`:857`) and chose
`BGProcessingTask` over `BGAppRefreshTask` because of it. A card filled by the export is empty or
stale for the first half minute of every cold launch. The alternative, a HealthKit query per
launch, does the same aggregation a second time.

**Freshness is already rendered.** `statusTitle` formats `lastExport` with
`RelativeDateTimeFormatter` (`:661-667`), and background runs update `lastExport` too (`:116`,
`:561`). That third of the proposal duplicates existing UI.

**The real gap is different, and it is not a screen.** A failed background run calls
`setTaskCompleted(success: false)` (`:874-876`) and writes nothing the owner ever sees. That is how
50 hours passed unnoticed in October: the failure had no surface. The Mac side had the same defect
in its own layer — `healthsync-cron.sh` printed `FAILED` and exited 0 — fixed 2026-11-02.

**The visual system is four SF Symbols and one helper.** `stat()` at `:678-688`, symbols at
`:702`, `:732`, `:740`, `:769`. An abstraction over that is more code than the call sites it
replaces.

## Goals vs. Non-Goals

**In scope**

1. One number only this app owns: last night's hours, taken from data already in scope where the
   summary is built (`:99-101`).
2. Staleness as a state you can see without opening the app.
3. A visual pass at the existing call sites: the icon (`tools/make-icon.py` already generates it),
   a type scale, honest empty and permission-denied states.
4. Record that the signing decision changed: a paid account is pending, so profiles last a year
   and background delivery stops being a weekly re-sign chore.

**Out of scope**

- A Heute or dashboard screen duplicating HealthKit aggregation.
- Any server, any sync of the cache to the phone, any second data source.

## Alternatives Weighed

- **Heute screen** — rejected. Duplicates Apple Health, needs the exporter to surrender values it
  discards, and is empty for ~35 s after launch.
- **Widget or Lock Screen complication** — kept for the next round. The only form that shows
  freshness without opening the app; a `TimelineProvider` over `Schedule.lastRun` needs no engine
  change.
- **Local notification when a background run fails** — kept, now. The smallest thing that would
  have caught the October stop.
- **A Shortcut reading the health sample** — rejected as the answer. It gives the number, not the
  pipeline state, and has nowhere to show staleness.
- **Restyle only, for screenshots** — rejected. The app would look right and stay silent.

## Key Decisions & Staging for Next Steps

| Severity | Finding | Evidence | Disposition |
| --- | --- | --- | --- |
| BLOCKER | Engine returns counts only; any card needs values it throws away | `:57-61`, `:118-120` | **REJECT** the screen requirement |
| BLOCKER | Proposed content is Apple Health's own Summary tab | product | **REJECT** |
| MAJOR | ~35 s export means an empty card on every cold launch | `:857` | **ACCEPT** (moot once the screen is dropped) |
| MAJOR | A failed background run is invisible to the owner | `:874-876` | **FIX NOW**: local notification on failure |
| MINOR | Freshness already rendered, including background runs | `:661-667`, `:116` | **ACCEPT** |
| MINOR | Last night's hours are already in scope, one field away | `:99-101` | **FIX NOW**: field on `ExportSummary`, one `stat()` cell, one test |
| MINOR | An abstraction over four symbols is more code, not less | `:678-688` | **REJECT**: edit the call sites |
| NOTE | Free-tier signing was acceptable; a paid account is pending | `concepts_brief.export.md` §5 | **ACCEPT**: profiles become 1-year, background stops being a weekly chore |

**Carried forward**

- One target, one file, until it hurts.
- "Professional" here means a visible pipeline state, one honest number, and a real icon. Not more
  screens.
- Rejected on purpose: a widget ships only after the notification proves the failure state is
  worth seeing.

## What is verified and what is not

- The Contrarian lens completed. Every claim it made was re-checked against the cited lines before
  entering the table above.
- Five lenses (runtime cost, UX, migration, observability, debt) died when the delegation owner
  exited mid-run. Their questions are answered above only where the code settles them: no view
  split means nothing migrates; 902 lines is acceptable at this size; the cost argument is the 35 s
  figure. These are my reads, not independent findings, and they are not counted as review.
- The data path was confirmed live: the cache holds 16 metrics and 73 workouts, newest sample
  2026-10-31, 50 hours stale when this was written.
