local addonName, ns = ...

local activeCast = nil
local lastCancel = nil

-- Phase 4: raid member cast tracking via CLEU
local raidCasts = {}
local recentInterrupts = {}
local addonUsers = {}

local ADDON_PREFIX = "CCT"
local CANCEL_EXPIRY = 10.0
local AFFILIATION_RAID_PARTY = 0x6

C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)

local function FormatSpellName(name, rank)
    if rank and rank ~= "" then
        return name .. " (" .. rank .. ")"
    end
    return name
end
ns.FormatSpellName = FormatSpellName

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            ns:InitDB()
            ns:InitAlertFrame()
            ns:StartSession()
            DEFAULT_CHAT_FRAME:AddMessage("|cffcccccc[CCT]|r CancelledCastTracker loaded. Type /cct for commands.")
        end
        return
    end

    if event == "PLAYER_LOGOUT" then
        ns:SaveSession()
        ns:SaveConfig()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ns:HandleCLEU()
        return
    end

    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == ADDON_PREFIX then
            ns:HandleAddonMessage(message, sender)
        end
        return
    end

    -- Phase 1: player unit cast events
    local unit, castGUID, spellID = ...
    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_START" then
        if lastCancel then
            local name, rank = GetSpellInfo(spellID)
            ns:OnNextCastAfterCancel(lastCancel, spellID, name, rank)
            lastCancel = nil
        end
        local name, rank, icon = GetSpellInfo(spellID)
        activeCast = {
            castGUID = castGUID,
            spellID = spellID,
            spellName = name,
            spellRank = rank,
            spellIcon = icon,
            startTime = GetTime(),
            outcome = nil,
        }
        ns:OnCastStart(activeCast)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if activeCast and activeCast.castGUID == castGUID then
            activeCast.outcome = "SUCCESS"
        end
        if lastCancel then
            local name, rank = GetSpellInfo(spellID)
            ns:OnNextCastAfterCancel(lastCancel, spellID, name, rank)
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
                if not UnitIsDeadOrGhost("player") then
                    activeCast.outcome = "CANCELLED"
                    local castTime = GetTime() - activeCast.startTime
                    ns:OnCastCancelled(activeCast, castTime)
                    lastCancel = {
                        spellID = activeCast.spellID,
                        spellName = activeCast.spellName,
                        spellRank = activeCast.spellRank,
                        spellIcon = activeCast.spellIcon,
                        cancelTime = GetTime(),
                    }
                    ns:ShowAlert(activeCast.spellID, FormatSpellName(activeCast.spellName, activeCast.spellRank))
                    ns:BroadcastCancel(activeCast)
                end
            end
            activeCast = nil
        end
    end
end)

C_Timer.NewTicker(1.0, function()
    if lastCancel and (GetTime() - lastCancel.cancelTime) > CANCEL_EXPIRY then
        lastCancel = nil
    end
    local now = GetTime()
    for guid, cast in pairs(raidCasts) do
        if (now - cast.startTime) > 15 then
            raidCasts[guid] = nil
        end
    end
    for guid, expiry in pairs(recentInterrupts) do
        if now > expiry then
            recentInterrupts[guid] = nil
        end
    end
end)

-- Phase 4: CLEU handler for raid member cancel detection
function ns:HandleCLEU()
    local timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, _,
        destGUID, destName, destFlags, _, spellID, spellName, _, extraArg = CombatLogGetCurrentEventInfo()

    if not sourceName or sourceGUID == UnitGUID("player") then return end
    if not sourceFlags or bit.band(sourceFlags, AFFILIATION_RAID_PARTY) == 0 then return end
    -- Skip players reporting via addon comms (their own tracking is more accurate)
    if addonUsers[sourceName] then return end

    if subevent == "SPELL_CAST_START" then
        raidCasts[sourceGUID] = {
            spellID = spellID,
            spellName = spellName,
            startTime = GetTime(),
            sourceName = sourceName,
        }
    elseif subevent == "SPELL_CAST_SUCCESS" then
        raidCasts[sourceGUID] = nil
    elseif subevent == "SPELL_INTERRUPT" then
        -- Mark dest as externally interrupted so SPELL_CAST_FAILED won't count as self-cancel
        recentInterrupts[destGUID] = GetTime() + 0.5
    elseif subevent == "SPELL_CAST_FAILED" then
        if extraArg == "Interrupted" then
            local now = GetTime()
            if recentInterrupts[sourceGUID] and now < recentInterrupts[sourceGUID] then
                recentInterrupts[sourceGUID] = nil
            else
                local cast = raidCasts[sourceGUID]
                if cast then
                    ns:OnRaidMemberCancel(sourceName, cast.spellID, cast.spellName)
                end
            end
        end
        raidCasts[sourceGUID] = nil
    end
end

-- Phase 4: addon comms — broadcast own cancels to group
function ns:BroadcastCancel(cast)
    local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
    if not channel then return end
    local msg = string.format("CANCEL|%d|%s", cast.spellID, cast.spellName)
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, msg, channel)
end

-- Phase 4: receive cancel data from other addon users
function ns:HandleAddonMessage(message, sender)
    local playerName = UnitName("player")
    if sender == playerName or sender:match("^" .. playerName .. "%-") then return end

    local shortName = sender:match("^([^%-]+)")
    addonUsers[shortName] = true

    local msgType, rest = strsplit("|", message, 2)
    if msgType == "CANCEL" and rest then
        local spellIDStr, spellName = strsplit("|", rest)
        local spellID = tonumber(spellIDStr)
        if spellID and spellName then
            ns:OnRaidMemberCancel(shortName, spellID, spellName)
        end
    end
end
