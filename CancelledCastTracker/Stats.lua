local _, ns = ...

local sessionStats = { totalCasts = 0, totalCancels = 0, spells = {} }
local sessionStart = GetTime()
local raidStats = {}

local MAX_SESSIONS = 10
local REPORT_COOLDOWN = 60
local lastReportTime = 0

local DB_DEFAULTS = {
    spells = {},
    sessions = {},
    config = {
        alertEnabled = true,
        alertScale = 1.0,
        alertPoint = { "CENTER", 0, 150 },
    },
}

function ns:InitDB()
    if not CancelledCastCharDB then
        CancelledCastCharDB = {}
    end
    local db = CancelledCastCharDB
    if not db.spells then db.spells = {} end
    if not db.sessions then db.sessions = {} end
    if not db.config then db.config = {} end
    for k, v in pairs(DB_DEFAULTS.config) do
        if db.config[k] == nil then
            if type(v) == "table" then
                db.config[k] = { unpack(v) }
            else
                db.config[k] = v
            end
        end
    end
end

function ns:GetConfig()
    return CancelledCastCharDB and CancelledCastCharDB.config or DB_DEFAULTS.config
end

function ns:SaveConfig()
    if not CancelledCastCharDB then return end
    local f = ns.alertFrame
    if f then
        local point, _, _, x, y = f:GetPoint()
        CancelledCastCharDB.config.alertPoint = { point, x, y }
    end
end

function ns:StartSession()
    sessionStart = GetTime()
end

function ns:SaveSession()
    if not CancelledCastCharDB then return end
    if sessionStats.totalCasts == 0 then return end

    for spellID, entry in pairs(sessionStats.spells) do
        local saved = CancelledCastCharDB.spells[spellID]
        if not saved then
            saved = { name = entry.name, casts = 0, cancels = 0 }
            CancelledCastCharDB.spells[spellID] = saved
        end
        saved.name = entry.name
        saved.casts = saved.casts + entry.casts
        saved.cancels = saved.cancels + entry.cancels
    end

    table.insert(CancelledCastCharDB.sessions, {
        timestamp = time(),
        totalCasts = sessionStats.totalCasts,
        totalCancels = sessionStats.totalCancels,
        duration = GetTime() - sessionStart,
    })

    while #CancelledCastCharDB.sessions > MAX_SESSIONS do
        table.remove(CancelledCastCharDB.sessions, 1)
    end
end

function ns:OnCastStart(cast)
    sessionStats.totalCasts = sessionStats.totalCasts + 1
    local entry = sessionStats.spells[cast.spellID]
    if not entry then
        entry = { name = ns.FormatSpellName(cast.spellName, cast.spellRank), casts = 0, cancels = 0 }
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
    sessionStart = GetTime()
end

-- Phase 3: lifetime stats (saved + current session merged)
function ns:GetLifetimeStats()
    if not CancelledCastCharDB then return {} end
    local merged = {}
    local seen = {}
    for spellID, saved in pairs(CancelledCastCharDB.spells) do
        local session = sessionStats.spells[spellID]
        local entry = {
            name = saved.name,
            casts = saved.casts + (session and session.casts or 0),
            cancels = saved.cancels + (session and session.cancels or 0),
        }
        if entry.cancels > 0 then
            table.insert(merged, entry)
        end
        seen[spellID] = true
    end
    for spellID, entry in pairs(sessionStats.spells) do
        if not seen[spellID] and entry.cancels > 0 then
            table.insert(merged, { name = entry.name, casts = entry.casts, cancels = entry.cancels })
        end
    end
    table.sort(merged, function(a, b) return a.cancels > b.cancels end)
    return merged
end

function ns:GetSessionHistory()
    if not CancelledCastCharDB then return {} end
    return CancelledCastCharDB.sessions
end

-- Phase 3: report to raid/party chat (rate-limited)
function ns:SendReport()
    local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
    if not channel then
        DEFAULT_CHAT_FRAME:AddMessage("|cffcccccc[CCT]|r Not in a group.")
        return
    end
    local now = GetTime()
    if (now - lastReportTime) < REPORT_COOLDOWN then
        local remaining = math.ceil(REPORT_COOLDOWN - (now - lastReportTime))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffcccccc[CCT]|r Report on cooldown (%ds).", remaining))
        return
    end
    lastReportTime = now

    local stats = sessionStats
    local rate = stats.totalCasts > 0
        and string.format("%.1f%%", stats.totalCancels / stats.totalCasts * 100)
        or "0.0%"
    SendChatMessage(
        string.format("[CCT] %d casts, %d cancelled (%s)", stats.totalCasts, stats.totalCancels, rate),
        channel
    )
    local sorted = {}
    for _, entry in pairs(stats.spells) do
        if entry.cancels > 0 then
            table.insert(sorted, entry)
        end
    end
    table.sort(sorted, function(a, b) return a.cancels > b.cancels end)
    for i = 1, math.min(3, #sorted) do
        local entry = sorted[i]
        SendChatMessage(
            string.format("  %s: %d/%d (%.1f%%)", entry.name, entry.cancels, entry.casts, entry.cancels / entry.casts * 100),
            channel
        )
    end
end

-- Phase 4: raid member cancel tracking
function ns:OnRaidMemberCancel(playerName, spellID, spellName)
    if not raidStats[playerName] then
        raidStats[playerName] = { totalCancels = 0, spells = {} }
    end
    local player = raidStats[playerName]
    player.totalCancels = player.totalCancels + 1
    if not player.spells[spellID] then
        player.spells[spellID] = { name = spellName, cancels = 0 }
    end
    player.spells[spellID].cancels = player.spells[spellID].cancels + 1
end

function ns:GetRaidStats()
    return raidStats
end

function ns:ResetRaidStats()
    raidStats = {}
end
