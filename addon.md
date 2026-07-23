# CancelledCastTracker — TBC Classic Addon Design

## Goal

An in-game addon for TBC Classic (2.5.x) that detects when the player cancels a cast and shows what they cast next, mirroring the "Next Cast" analysis from WarcraftLogs. Gives real-time feedback so players can identify bad cancellation habits during the raid rather than after.

## How Cast Cancellation Detection Works

TBC Classic fires `UNIT_SPELLCAST_*` events in a predictable order. The key insight:

- `UNIT_SPELLCAST_STOP` fires for **every** cast ending (success, cancel, interrupt, fail)
- Specific outcome events (`SUCCEEDED`, `INTERRUPTED`, `FAILED`) fire **before** `STOP`
- If `STOP` fires with no prior outcome for that `castGUID`, the player cancelled it themselves

```
Success:     START → SUCCEEDED → STOP
Interrupted: START → INTERRUPTED → STOP
Failed:      START → FAILED → STOP
Cancelled:   START → STOP  (no outcome event — this is what we track)
```

All events provide `(unitTarget, castGUID, spellID)` in TBC Classic 2.5.x.

## Features

### Phase 1 — Core Detection + Chat Output

- Track player casts via `UNIT_SPELLCAST_START/STOP/SUCCEEDED/INTERRUPTED/FAILED`
- On cancellation, record the spell and timestamp
- When the next cast begins (`UNIT_SPELLCAST_START`) or instant fires (`UNIT_SPELLCAST_SUCCEEDED` with no prior `START`), record it as the "next cast"
- Print to chat: `[CCT] Cancelled Fireball (Rank 10) → started Frostbolt (Rank 13)`
- Per-session counters: total casts, cancelled casts, cancel rate %
- Slash command `/cct` to show session summary, `/cct reset` to clear

### Phase 2 — On-Screen Alert

- Small movable frame that flashes when a cast is cancelled
- Shows the cancelled spell icon + name
- Fades after 3 seconds
- Configurable: enable/disable, scale, position (saved per character)

### Phase 3 — Statistics & Saved Data

- Per-spell cancel rates tracked across sessions via `SavedVariablesPerCharacter`
- `/cct stats` shows a breakdown: spell name, total casts, cancels, cancel rate
- `/cct report` outputs a summary to raid chat (opt-in, rate-limited)
- Persist last N sessions with timestamps for trend tracking

### Phase 4 — Raid Integration (Optional)

- Track raid member cancels via `COMBAT_LOG_EVENT_UNFILTERED` (`SPELL_CAST_START` + `SPELL_CAST_FAILED` subevents)
- `SPELL_CAST_FAILED` with `failedType` distinguishes cancels from other failures
- Addon-to-addon comms via `C_ChatInfo.SendAddonMessage` to share cancel data with raid leaders running the addon
- Raid leader view: per-player cancel summaries

## File Structure

```
CancelledCastTracker/
├── CancelledCastTracker.toc
├── Core.lua              -- Event handling, cast state machine, detection logic
├── Display.lua           -- Alert frame, chat output, formatting
├── Stats.lua             -- Per-spell tracking, session aggregation, SavedVariables
├── Config.lua            -- Slash commands, options
└── README.md
```

## TOC File

```toc
## Interface: 20504
## Title: CancelledCastTracker
## Notes: Tracks cancelled casts and shows what you cast next
## Author: Leigh
## Version: 1.0.0
## SavedVariablesPerCharacter: CancelledCastCharDB
## X-Category: Combat

Core.lua
Stats.lua
Display.lua
Config.lua
```

## Core Detection Logic (Core.lua)

```lua
local addonName, ns = ...

local activeCast = nil   -- { castGUID, spellID, spellName, startTime, outcome }
local lastCancel = nil   -- { spellID, spellName, cancelTime }

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")

frame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_START" then
        -- If we had a pending cancel waiting for "next cast", resolve it now
        if lastCancel then
            local spellName = GetSpellInfo(spellID)
            ns:OnNextCastAfterCancel(lastCancel, spellID, spellName)
            lastCancel = nil
        end
        -- Track this new cast
        activeCast = {
            castGUID = castGUID,
            spellID = spellID,
            spellName = GetSpellInfo(spellID),
            startTime = GetTime(),
            outcome = nil,
        }
        ns:OnCastStart(activeCast)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if activeCast and activeCast.castGUID == castGUID then
            activeCast.outcome = "SUCCESS"
        end
        -- An instant cast after a cancel (no START event)
        if lastCancel then
            local spellName = GetSpellInfo(spellID)
            ns:OnNextCastAfterCancel(lastCancel, spellID, spellName)
            lastCancel = nil
        end

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if activeCast and activeCast.castGUID == castGUID then
            activeCast.outcome = "INTERRUPTED"
        end

    elseif event == "UNIT_SPELLCAST_FAILED" then
        if activeCast and activeCast.castGUID == castGUID then
            activeCast.outcome = "FAILED"
        end

    elseif event == "UNIT_SPELLCAST_STOP" then
        if activeCast and activeCast.castGUID == castGUID then
            if activeCast.outcome == nil then
                -- No outcome event fired → player cancelled
                activeCast.outcome = "CANCELLED"
                local castTime = GetTime() - activeCast.startTime
                ns:OnCastCancelled(activeCast, castTime)
                lastCancel = {
                    spellID = activeCast.spellID,
                    spellName = activeCast.spellName,
                    cancelTime = GetTime(),
                }
            end
            activeCast = nil
        end
    end
end)

-- Expire stale lastCancel after 10s (combat ended, player idle, etc.)
local CANCEL_EXPIRY = 10.0
C_Timer.NewTicker(1.0, function()
    if lastCancel and (GetTime() - lastCancel.cancelTime) > CANCEL_EXPIRY then
        lastCancel = nil
    end
end)
```

## Statistics Tracking (Stats.lua)

```lua
local _, ns = ...

-- SavedVariablesPerCharacter: CancelledCastCharDB
-- Structure: { spells = { [spellID] = { name, casts, cancels } }, sessions = { ... } }

local sessionStats = { totalCasts = 0, totalCancels = 0, spells = {} }

function ns:OnCastStart(cast)
    sessionStats.totalCasts = sessionStats.totalCasts + 1
    local entry = sessionStats.spells[cast.spellID]
    if not entry then
        entry = { name = cast.spellName, casts = 0, cancels = 0 }
        sessionStats.spells[cast.spellID] = entry
    end
    entry.casts = entry.casts + 1
end

function ns:OnCastCancelled(cast, castTime)
    sessionStats.totalCancels = sessionStats.totalCancels + 1
    local entry = sessionStats.spells[cast.spellID]
    if entry then
        entry.cancels = entry.cancels + 1
    end
end

function ns:GetSessionStats()
    return sessionStats
end

function ns:ResetSession()
    sessionStats = { totalCasts = 0, totalCancels = 0, spells = {} }
end
```

## Display (Display.lua)

```lua
local _, ns = ...

local COLORS = { cancel = "|cffff4444", next = "|cff44ff44", reset = "|r" }

function ns:OnNextCastAfterCancel(cancel, nextSpellID, nextSpellName)
    local msg = string.format(
        "%s[CCT]%s Cancelled %s%s%s → %s%s%s",
        "|cffcccccc", "|r",
        COLORS.cancel, cancel.spellName, COLORS.reset,
        COLORS.next, nextSpellName or "Unknown", COLORS.reset
    )
    DEFAULT_CHAT_FRAME:AddMessage(msg)
end

function ns:PrintSummary()
    local stats = ns:GetSessionStats()
    local rate = stats.totalCasts > 0
        and string.format("%.1f%%", stats.totalCancels / stats.totalCasts * 100)
        or "0.0%"
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cffcccccc[CCT]|r Session: %d casts, %d cancelled (%s)",
        stats.totalCasts, stats.totalCancels, rate
    ))
    -- Per-spell breakdown
    local sorted = {}
    for spellID, entry in pairs(stats.spells) do
        if entry.cancels > 0 then
            table.insert(sorted, entry)
        end
    end
    table.sort(sorted, function(a, b) return a.cancels > b.cancels end)
    for _, entry in ipairs(sorted) do
        local spellRate = string.format("%.1f%%", entry.cancels / entry.casts * 100)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %s: %d/%d (%s)",
            entry.name, entry.cancels, entry.casts, spellRate
        ))
    end
end
```

## Slash Commands (Config.lua)

```lua
local _, ns = ...

SLASH_CCT1 = "/cct"
SlashCmdList["CCT"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "reset" then
        ns:ResetSession()
        DEFAULT_CHAT_FRAME:AddMessage("|cffcccccc[CCT]|r Session stats reset.")
    elseif msg == "stats" then
        ns:PrintSummary()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffcccccc[CCT]|r Commands: /cct stats | /cct reset")
    end
end
```

## Key TBC API References

| Function | Purpose |
|----------|---------|
| `GetSpellInfo(spellID)` | Returns `name, rank, icon, castTime, minRange, maxRange, spellID` |
| `UnitCastingInfo("player")` | Returns current cast info including `startTimeMS, endTimeMS` |
| `GetTime()` | Game time in seconds with ms precision |
| `C_Timer.After(sec, fn)` | One-shot timer |
| `C_Timer.NewTicker(sec, fn)` | Repeating timer |
| `CombatLogGetCurrentEventInfo()` | CLEU event args (for Phase 4 raid tracking) |
| `C_ChatInfo.SendAddonMessage(prefix, msg, type, target)` | Addon comms (Phase 4) |

## Event Flow — Complete Example

Player starts casting Fireball, cancels by moving, then casts Frostbolt:

```
1. UNIT_SPELLCAST_START("player", "guid-1", 133)
   → activeCast = { castGUID="guid-1", spellID=133, spellName="Fireball", outcome=nil }
   → sessionStats: Fireball casts +1

2. UNIT_SPELLCAST_STOP("player", "guid-1", 133)
   → outcome is nil → CANCELLED
   → lastCancel = { spellID=133, spellName="Fireball" }
   → sessionStats: Fireball cancels +1

3. UNIT_SPELLCAST_START("player", "guid-2", 116)
   → lastCancel is set → resolve: "Cancelled Fireball → started Frostbolt"
   → chat output: [CCT] Cancelled Fireball → Frostbolt
   → lastCancel = nil
   → activeCast = { castGUID="guid-2", spellID=116, spellName="Frostbolt", outcome=nil }
```

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Instant cast after cancel | Caught by `SUCCEEDED` when `lastCancel` is set (no `START` fires for instants) |
| Cancel followed by no cast (idle/AFK) | `lastCancel` expires after 10s via ticker |
| Channel spells | Not tracked in Phase 1 — add `CHANNEL_START/STOP` events in a later phase |
| Rapid double-cancel | Each `STOP` without outcome creates a new `lastCancel`, overwriting the previous one |
| GCD-locked spell attempts | `FAILED` fires with `failedType`, sets outcome so `STOP` won't treat it as cancel |
| Death during cast | `STOP` fires, but `outcome` may be nil — filter by checking `UnitIsDeadOrGhost("player")` |

## Implementation Order

1. **Core.lua** — event registration, state machine, cancel detection
2. **Stats.lua** — session counters, per-spell tracking
3. **Display.lua** — chat output for cancel → next cast
4. **Config.lua** — slash commands
5. **Test in-game** — cast, cancel, verify chat output
6. **Phase 2** — alert frame (CreateFrame + animation)
7. **Phase 3** — SavedVariables persistence
8. **Phase 4** — CLEU-based raid tracking + addon comms
