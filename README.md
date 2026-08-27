# ClipCastTracker

A World of Warcraft TBC Classic addon that detects when you clip a cast and tracks what you cast next. Includes a Recount-style window for analyzing clip patterns over time.

## Why

Not every clip is a mistake — sometimes you cancel a cast to move out of fire or dodge a mechanic. But the clips that matter are the ones where you immediately start another spell. If you're consistently clipping Fireball to cast Frostbolt, that's a sign your rotation is taking premature actions: starting a cast you know you're going to cancel. The drill-down view makes these patterns visible so you can tighten up your decision-making and stop wasting cast time.

## How It Works

TBC Classic fires `UNIT_SPELLCAST_STOP` for every cast ending, but specific outcome events (`SUCCEEDED`, `INTERRUPTED`, `FAILED`) fire **before** it. If `STOP` fires with no prior outcome, the player clipped.

```
Success:     START → SUCCEEDED → STOP
Clipped:   START → STOP  ← this is what we track
```

When a clip is detected, the addon watches for the next cast and prints:

```
[CCT] Clipped Fireball (Rank 10) → Frostbolt (Rank 13)
```

## Features

### Main Window

Type `/cct` to open the main window — a Recount-style frame showing all your clipped spells.

- **Spell list** — every spell you cast appears in real time, showing icon, name, and clips/casts count (e.g. "0 / 15") with a proportional red bar for clipped spells
- **Session / Lifetime toggle** — switch between current session data and all-time cumulative stats
- **Drill-down** — click any spell to see what you cast next after clipping it (green bars). This hints at *why* you clipped — e.g. "when I clip Fireball, I usually cast Frostbolt"
- **Back button** — return from drill-down to the spell list
- **Reset** — in Session mode, resets the current session (saves to lifetime first). In Lifetime mode, resets all historical data
- **Movable and resizable** — drag the title bar to move, drag the bottom-right corner to resize
- **ESC to close**

### Alerts and Chat

- **Chat alerts** — color-coded clip → next cast messages in your chat frame
- **On-screen alert** — movable frame that flashes the clipped spell icon, fades after 3 seconds

### Tracking

- **Session stats** — total casts, clips, clip rate, per-spell breakdown
- **Lifetime stats** — per-spell clip rates and next-cast relationships saved across sessions
- **Session history** — last 10 session summaries with timestamps and durations

### Raid

- **Raid reporting** — send your summary to raid/party chat (rate-limited to 60s)
- **Raid tracking** — detects raid member clips via combat log events
- **Addon comms** — shares clip data with other addon users in the raid for more accurate tracking

## Slash Commands

| Command | Description |
|---------|-------------|
| `/cct` | Toggle the main window |
| `/cct options` | Show all available commands |
| `/cct stats` | Print session clip breakdown to chat |
| `/cct lifetime` | Print all-time clip stats to chat |
| `/cct history` | Print past session summaries |
| `/cct reset` | Reset session stats (saves to lifetime first) |
| `/cct resetall` | Reset lifetime stats |
| `/cct report` | Send summary to raid/party chat |
| `/cct raid` | Show raid member clips |
| `/cct alert` | Toggle on-screen alert |
| `/cct scale <n>` | Set alert frame scale (0.5–2.0) |
| `/cct test` | Show a test alert |

## Install

Copy the `ClipCastTracker` folder into your `Interface\AddOns\` directory and reload.

## TBC Anniversary

The addon includes a fix for TBC Anniversary where `UNIT_SPELLCAST_INTERRUPTED` fires for both self-clips and external interrupts. It uses CLEU `SPELL_INTERRUPT` events with a 0.5-second window to distinguish the two cases.
