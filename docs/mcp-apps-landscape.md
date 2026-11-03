# Apple Health → MCP apps: feature landscape

Surveyed 2026-11-02 via the App Store search API (de+us, six queries) and each
project's own listing, README or docs. Prices are the listings' own numbers;
"free" means the App Store price, not the absence of in-app purchases.

## The two architectures

Every app in this category is one of these, and the choice explains most of the
differences between them.

1. **The phone hosts the MCP endpoint.** Works only while the app is in the
   foreground and the agent is on the same network. Nothing leaves the phone,
   but "ask your AI while your phone is in your pocket" does not work.
2. **The phone pushes to a destination; a companion server reads it.** Works
   always, but the destination is a second place your health data now lives —
   a folder, a database, or a vendor relay.

## Feature table

| App | Architecture | Where data lands | Auth / pairing | Coverage | Write-back | Price | Open source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Marrow** | Phone MCP + optional self-hosted mirror | On-device; mirror on your tailnet | Bearer token | 170+ types | Yes, opt-in ("Allow AI write") | Free for agent access; Cloud MCP $4.99/mo | Server MIT |
| **MetricBridge** | Push to destination | Folder, LAN, or webhook | Companion server config | 194 metrics | No | Free (was €24.99) | Server MIT |
| **Health Export Pro** | Phone hosts MCP | On device only | Built-in server | Not published | No | €5.99 one-time | No |
| **Health MCP (Private Sync)** | Vendor relay + TEE | Vendor cloud, E2E, key on device | Remote MCP URL | Not published | No | Free tier | No |
| **Vaultbeat** | Vendor relay to *your* server | Your Mac/VPS, E2E | Server config | Sleep, cycle, heart, activity | State of Mind only | Pro $9.99/mo | Server MIT |
| **HealthAPI** | Hosted connector | Vendor service | QR / link / 6-char code, revocable | Not published | No | Free | No |
| **Health Sync for AI Agents** | Push to agent | Your agent's endpoint, E2E | QR onboarding | Body, nutrition, activity | No | Free | No |
| **Open Vitals** | Push, local or relay | Your server or cloud relay | QR from the agent | 70+ | No | Free | No |
| **HealthKite MCP** | Phone hosts LAN endpoint | Phone only | TLS-PSK pairing, Bonjour | HealthKit-native | No | Free | MCP server MIT, app closed |
| **HealthMirror** | Push to iCloud | Your iCloud Drive (JSONL) | None (file drop) | Broad | No | Free | MCP server open |
| **health4.ai** | Push to your database | Your Google Sheet or Supabase | Project URL + key | 150+ | No | Free | MIT |
| **Health MCP Sync** | Push to your server | Self-hosted server | Login | Sleep only | No | Free | No |
| **Somvia** | Push | Vendor | Agent connection | Training load, sleep, HRV | No | Free | No |
| **Sport MCP** | Phone MCP | Phone | Agent connection | Strength log | **Yes, write** | Free | No |
| **HealthSync** (yours) | Push to folder | Your iCloud folder | None (file drop) | 18 quantity types, sleep, workouts | No | — | Yes |

## What the table shows

**Coverage is table stakes, not a differentiator.** 170, 194, 150, 70 — the
numbers are marketing. A context window cannot hold raw samples, so the useful
axis is whether the app ships daily aggregates an agent can read without a
summarising step. Yours does; so do most of these.

**Auth is where they actually differ.** QR pairing (Health Sync for AI, Open
Vitals, HealthAPI), PSK pairing (HealthKite), bearer tokens (Marrow), file drops
(yours, HealthMirror). A file drop means no pairing step and no token to leak —
and also no way to revoke access, because access is possession of the folder.

**Exactly one app sells freshness.** Vitalbrücke's listing leads with "Claude
knows your data up to today, 14:32 — current, not updated for days, or failed".
That is the same defect the October incident exposed in your pipeline: everything
looked green while the producer had stopped. Independent confirmation that this
is the visible gap, not a nicety.

**Write-back is the new frontier.** Sport MCP writes workouts; Marrow allows AI
write to HealthKit. Both are about the agent *logging* things (lifts, weight),
which is a different product from reading history.

**Pricing clusters at free + IAP.** €5.99 one-time (Health Export Pro), $4.99 to
$9.99 a month for hosted cloud (Marrow, Vaultbeat), free with a paid tier for
more history. MetricBridge — the app the original brief avoided buying at €24.99
— now lists as free and is the closest thing to a direct competitor.

## What this means for HealthSync

1. **You already occupy the honest niche.** Free, local, no account, no vendor,
   writing the same cache schema MetricBridge's open-source server reads. That is
   a defensible position precisely because the paid ones need a server someone
   else operates.
2. **Two things are missing to be competitive, and neither is a screen.** Sober
   freshness state (the one thing only Vitalbrücke markets) and a pairing story
   that does not involve "pick a folder and hope" (QR of a LAN URL, or just a
   status page the Mac reads).
3. **Do not chase metric counts.** Adding the 19th metric does not change whether
   the agent can answer a question. Adding the 176th does not either.
