# Concepts brief: HealthSync (iOS) — Apple Health to the local MCP server

Status: derived from the session of 2026-10-31. No paid app, no cloud, no account.

## Problem

Apple Health has no API. The only way data leaves the phone is an app that reads HealthKit
on the device. The existing pipeline (`health-export-mcp` on the NAS, 14 MCP tools) reads two
cache files, and its producer was MetricBridge, a €24.99 one-time purchase. Hannes wants the
same result without buying an app and without a cloud service.

## What already exists (measured, not planned)

- `~/Tools/health-export-mcp`: upstream server, unmodified, `npm test` green. Reads
  `.health-cache.json` + `.health-workouts-cache.json` from `HEALTH_DATA_DIR`.
- `~/Tools/apple-export-to-cache.py`: converts Apple's manual `export.zip` into those cache
  files. Verified: 61-day synthetic export produced a cache the server accepted
  (`get_mcp_status` → `ok:true`, 6 metrics, 9 workouts, step sum matched the XML exactly).
- `~/Tools/healthsync-nas.sh`: Mac → NAS transport. Rewritten this session from rsync to
  `tar | ssh` because macOS ships openrsync and the NAS runs rsync 3.4.1; checksum verified.
- `~/Documents/10_Projects/health-sync-ios`: the app described here. Already generated and
  compiling.

## Decisions already taken (do not re-litigate without cause)

1. **No paid app, no cloud.** HealthKit data stays on the phone and the user's own machines.
2. **The app writes the server's cache schema directly.** No converter on the Mac for this path.
3. **Delivery by user-picked folder + security-scoped bookmark**, not an iCloud container:
   an iCloud container entitlement needs a paid developer account, a picked folder does not.
4. **Read-only.** The app never writes to HealthKit.
5. **Free-tier signing is acceptable** (weekly re-sign) rather than €99/yr.

## Alternatives weighed (rejected)

- MetricBridge (€24.99): works, but the whole point was avoiding the purchase.
- Shortcuts-only automation: free and permanent, but the Find action's type is a static picker
  per action, there is no per-day grouping primitive, and heavy queries are slow; a 14-day by
  8-metric daily cache becomes a large fragile graph that fails silently.
- Apple's manual `export.zip` + Python converter: works today, but manual and minutes of
  generation time on the phone.
- Sideloaded OSS apps (Pulso, DataDonor, HealthBridge): they invent their own schemas and
  still need Xcode signing; no advantage over owning ~350 lines.

## Open risks

- Free-tier provisioning expires every 7 days; re-run from Xcode to re-sign.
- `BGAppRefreshTask` is scheduled by iOS, not by us: background export is best-effort.
- HealthKit is unreadable while the device is locked.
- The app duplicates the cache-schema knowledge that the Python converter also holds; both
  must match `healthstore.mjs`.
