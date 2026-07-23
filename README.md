# CancelledCastTracker

A World of Warcraft TBC Classic (2.5.x) addon that detects when you cancel a cast and shows what you cast next. Gives real-time feedback on cancellation habits during raids — no more waiting for WarcraftLogs.

## How It Works

TBC Classic fires `UNIT_SPELLCAST_STOP` for every cast ending, but specific outcome events (`SUCCEEDED`, `INTERRUPTED`, `FAILED`) fire **before** it. If `STOP` fires with no prior outcome, the player cancelled.

```
Success:     START → SUCCEEDED → STOP
Cancelled:   START → STOP  ← this is what we track
```

When a cancel is detected, the addon watches for the next cast and prints:

```
[CCT] Cancelled Fireball (Rank 10) → Frostbolt (Rank 13)
```

## Features

- **Chat alerts** — color-coded cancel → next cast messages
- **On-screen alert** — movable frame that flashes the cancelled spell icon, fades after 3s
- **Session stats** — total casts, cancels, cancel rate, per-spell breakdown
- **Persistent tracking** — per-spell cancel rates and session history saved across sessions
- **Raid reporting** — send your summary to raid/party chat (rate-limited)
- **Raid tracking** — detects raid member cancels via combat log events
- **Addon comms** — shares cancel data with other addon users in the raid for accurate tracking

## Slash Commands

| Command | Description |
|---------|-------------|
| `/cct` | Show help |
| `/cct stats` | Session cancel breakdown |
| `/cct lifetime` | All-time cancel stats |
| `/cct history` | Past session summaries |
| `/cct reset` | Reset session stats |
| `/cct report` | Send summary to raid/party chat |
| `/cct raid` | Show raid member cancels |
| `/cct alert` | Toggle on-screen alert |
| `/cct scale <n>` | Set alert frame scale (0.5–2.0) |
| `/cct test` | Show a test alert |

## Install

Copy the `CancelledCastTracker` folder into your `Interface/AddOns/` directory and reload.
