local _, ns = ...

local function Msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffcccccc[CCT]|r " .. text)
end

local function PrintHelp()
    Msg("CancelledCastTracker commands:")
    Msg("  |cffffff88/cct stats|r — Session cancel breakdown")
    Msg("  |cffffff88/cct lifetime|r — All-time cancel stats")
    Msg("  |cffffff88/cct history|r — Past session summaries")
    Msg("  |cffffff88/cct reset|r — Reset session stats")
    Msg("  |cffffff88/cct report|r — Send summary to raid/party chat")
    Msg("  |cffffff88/cct raid|r — Show raid member cancels")
    Msg("  |cffffff88/cct alert|r — Toggle on-screen alert")
    Msg("  |cffffff88/cct scale <n>|r — Set alert scale (0.5–2.0)")
    Msg("  |cffffff88/cct test|r — Show a test alert")
end

SLASH_CCT1 = "/cct"
SlashCmdList["CCT"] = function(msg)
    msg = strtrim(msg)
    local cmd, arg = strsplit(" ", msg, 2)
    cmd = (cmd or ""):lower()

    if cmd == "stats" then
        ns:PrintSummary()

    elseif cmd == "lifetime" then
        ns:PrintLifetimeStats()

    elseif cmd == "history" then
        ns:PrintHistory()

    elseif cmd == "reset" then
        ns:ResetSession()
        Msg("Session stats reset.")

    elseif cmd == "report" then
        ns:SendReport()

    elseif cmd == "raid" then
        ns:PrintRaidStats()

    elseif cmd == "alert" then
        local enabled = not ns:GetConfig().alertEnabled
        ns:SetAlertEnabled(enabled)
        Msg("Alert frame " .. (enabled and "enabled" or "disabled") .. ".")

    elseif cmd == "scale" then
        local scale = tonumber(arg)
        if not scale or scale < 0.5 or scale > 2.0 then
            Msg("Usage: /cct scale <0.5–2.0>")
            return
        end
        ns:SetAlertScale(scale)
        Msg(string.format("Alert scale set to %.1f.", scale))

    elseif cmd == "test" then
        ns:TestAlert()

    else
        PrintHelp()
    end
end
