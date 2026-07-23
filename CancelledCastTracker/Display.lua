local _, ns = ...

local COLORS = {
    tag = "|cffcccccc",
    cancel = "|cffff4444",
    next = "|cff44ff44",
    accent = "|cffffff88",
    reset = "|r",
}

-- Phase 1: chat output for cancel → next cast
function ns:OnNextCastAfterCancel(cancel, nextSpellID, nextSpellName, nextSpellRank)
    local cancelLabel = ns.FormatSpellName(cancel.spellName, cancel.spellRank)
    local nextLabel = ns.FormatSpellName(nextSpellName or "Unknown", nextSpellRank)
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "%s[CCT]%s Cancelled %s%s%s → %s%s%s",
        COLORS.tag, COLORS.reset,
        COLORS.cancel, cancelLabel, COLORS.reset,
        COLORS.next, nextLabel, COLORS.reset
    ))
end

function ns:PrintSummary()
    local stats = ns:GetSessionStats()
    local rate = stats.totalCasts > 0
        and string.format("%.1f%%", stats.totalCancels / stats.totalCasts * 100)
        or "0.0%"
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "%s[CCT]%s Session: %d casts, %d cancelled (%s)",
        COLORS.tag, COLORS.reset, stats.totalCasts, stats.totalCancels, rate
    ))
    local sorted = {}
    for _, entry in pairs(stats.spells) do
        if entry.cancels > 0 then
            table.insert(sorted, entry)
        end
    end
    table.sort(sorted, function(a, b) return a.cancels > b.cancels end)
    for _, entry in ipairs(sorted) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %s: %d/%d (%.1f%%)",
            entry.name, entry.cancels, entry.casts, entry.cancels / entry.casts * 100
        ))
    end
end

-- Phase 3: lifetime stats
function ns:PrintLifetimeStats()
    local stats = ns:GetLifetimeStats()
    if #stats == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(COLORS.tag .. "[CCT]" .. COLORS.reset .. " No cancelled casts recorded.")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage(COLORS.tag .. "[CCT]" .. COLORS.reset .. " Lifetime cancel stats:")
    for _, entry in ipairs(stats) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %s: %d/%d (%.1f%%)",
            entry.name, entry.cancels, entry.casts, entry.cancels / entry.casts * 100
        ))
    end
end

-- Phase 3: session history
function ns:PrintHistory()
    local sessions = ns:GetSessionHistory()
    if #sessions == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(COLORS.tag .. "[CCT]" .. COLORS.reset .. " No session history.")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "%s[CCT]%s Session history (last %d):", COLORS.tag, COLORS.reset, #sessions
    ))
    for i = #sessions, 1, -1 do
        local s = sessions[i]
        local rate = s.totalCasts > 0
            and string.format("%.1f%%", s.totalCancels / s.totalCasts * 100)
            or "0.0%"
        local mins = math.floor(s.duration / 60)
        local secs = math.floor(s.duration % 60)
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %s — %d casts, %d cancelled (%s) — %dm%ds",
            date("%m/%d %H:%M", s.timestamp), s.totalCasts, s.totalCancels, rate, mins, secs
        ))
    end
end

-- Phase 4: raid member cancel summary
function ns:PrintRaidStats()
    local raidStats = ns:GetRaidStats()
    local sorted = {}
    for name, data in pairs(raidStats) do
        table.insert(sorted, { name = name, totalCancels = data.totalCancels, spells = data.spells })
    end
    if #sorted == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(COLORS.tag .. "[CCT]" .. COLORS.reset .. " No raid cancel data.")
        return
    end
    table.sort(sorted, function(a, b) return a.totalCancels > b.totalCancels end)
    DEFAULT_CHAT_FRAME:AddMessage(COLORS.tag .. "[CCT]" .. COLORS.reset .. " Raid cancels this session:")
    for _, player in ipairs(sorted) do
        local topSpell, topCount = nil, 0
        for _, spell in pairs(player.spells) do
            if spell.cancels > topCount then
                topCount = spell.cancels
                topSpell = spell.name
            end
        end
        local detail = topSpell and string.format(" (top: %s x%d)", topSpell, topCount) or ""
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  %s%s%s: %d cancels%s",
            COLORS.cancel, player.name, COLORS.reset, player.totalCancels, detail
        ))
    end
end

-- Phase 2: on-screen alert frame
function ns:InitAlertFrame()
    local db = ns:GetConfig()

    local f = CreateFrame("Frame", "CCTAlertFrame", UIParent, "BackdropTemplate")
    f:SetSize(250, 50)
    f:SetPoint(db.alertPoint[1], UIParent, db.alertPoint[1], db.alertPoint[2], db.alertPoint[3])
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.1, 0.05, 0.05, 0.9)
    f:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.9)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetScale(db.alertScale)
    f:Hide()

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns:GetConfig().alertPoint = { point, x, y }
    end)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", 8, 0)

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetPoint("RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)

    local fadeGroup = f:CreateAnimationGroup()
    local fade = fadeGroup:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(1)
    fade:SetStartDelay(2)
    fadeGroup:SetScript("OnFinished", function() f:Hide() end)

    f.icon = icon
    f.text = text
    f.fadeGroup = fadeGroup
    ns.alertFrame = f
end

function ns:ShowAlert(spellID, displayName)
    local db = ns:GetConfig()
    if not db.alertEnabled then return end
    local f = ns.alertFrame
    if not f then return end

    local _, _, spellIcon = GetSpellInfo(spellID)
    f.icon:SetTexture(spellIcon)
    f.text:SetText(COLORS.cancel .. "Cancelled" .. COLORS.reset .. " " .. displayName)

    f.fadeGroup:Stop()
    f:SetAlpha(1)
    f:Show()
    f.fadeGroup:Play()
end

function ns:SetAlertEnabled(enabled)
    ns:GetConfig().alertEnabled = enabled
end

function ns:SetAlertScale(scale)
    ns:GetConfig().alertScale = scale
    if ns.alertFrame then
        ns.alertFrame:SetScale(scale)
    end
end

function ns:TestAlert()
    ns:ShowAlert(133, "Fireball (Test)")
end
