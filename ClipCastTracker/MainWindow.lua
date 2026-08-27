local _, ns = ...

local ROW_HEIGHT = 18
local MAX_ROWS = 28
local MIN_WIDTH, MAX_WIDTH = 200, 400
local MIN_HEIGHT, MAX_HEIGHT = 200, 500
local TITLE_HEIGHT = 24
local MODE_HEIGHT = 20
local HEADER_HEIGHT = 18
local STATUS_HEIGHT = 20
local SLIDER_WIDTH = 16

local isUpdating = false
local viewMode = "main"
local drilldownSpellID = nil
local drilldownSpellName = nil
local useLifetime = false
local scrollOffset = 0

local mainFrame, titleText, backBtn, sessionBtn, lifetimeBtn, resetBtn
local headerName, headerValue, slider, statusText, scrollArea
local rows = {}
local currentData = {}

local UpdateRows

local function GetVisibleRows()
    local available = scrollArea:GetHeight()
    return math.max(1, math.floor(available / ROW_HEIGHT))
end

local function GetCurrentData()
    if viewMode == "drilldown" then
        return ns:GetDrilldownData(drilldownSpellID, useLifetime)
    elseif useLifetime then
        return ns:GetLifetimeStats()
    else
        return ns:GetSessionSpellList()
    end
end

local function OnRowClick(row)
    if viewMode == "main" and row.spellID then
        viewMode = "drilldown"
        drilldownSpellID = row.spellID
        drilldownSpellName = row.spellName
        scrollOffset = 0
        slider:SetValue(0)
        UpdateRows()
    end
end

local function OnBackClick()
    viewMode = "main"
    drilldownSpellID = nil
    drilldownSpellName = nil
    scrollOffset = 0
    slider:SetValue(0)
    UpdateRows()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

    local bar = row:CreateTexture(nil, "BACKGROUND")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(1)
    bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 4, 0)

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameText:SetPoint("RIGHT", row, "RIGHT", -45, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    valueText:SetJustifyH("RIGHT")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.4)

    row.bar = bar
    row.icon = icon
    row.nameText = nameText
    row.valueText = valueText

    row:SetScript("OnClick", function(self) OnRowClick(self) end)
    row:Hide()

    return row
end

UpdateRows = function()
    if isUpdating then return end
    isUpdating = true

    currentData = GetCurrentData()
    local visibleRows = GetVisibleRows()

    local maxVal = 0
    for _, entry in ipairs(currentData) do
        local val = viewMode == "drilldown" and entry.count or entry.cancels
        if val > maxVal then maxVal = val end
    end

    local scrollMax = math.max(0, #currentData - visibleRows)
    slider:SetMinMaxValues(0, scrollMax)
    if scrollOffset > scrollMax then
        scrollOffset = scrollMax
    end

    local showSlider = scrollMax > 0
    if showSlider then slider:Show() else slider:Hide() end

    local contentWidth = scrollArea:GetWidth()
    if showSlider then contentWidth = contentWidth - SLIDER_WIDTH end

    local barR, barG, barB, barA
    if viewMode == "drilldown" then
        barR, barG, barB, barA = 0.2, 0.8, 0.2, 0.5
    else
        barR, barG, barB, barA = 0.8, 0.2, 0.2, 0.5
    end

    for i = 1, MAX_ROWS do
        local row = rows[i]
        if i > visibleRows then
            row:Hide()
        else
            local dataIdx = scrollOffset + i
            local entry = currentData[dataIdx]
            if not entry then
                row:Hide()
            else
                row:SetWidth(contentWidth)

                local val, label
                if viewMode == "drilldown" then
                    val = entry.count
                    label = tostring(val)
                else
                    val = entry.cancels
                    local total = entry.casts
                    label = val .. " / " .. total
                end

                local _, _, spellIcon = GetSpellInfo(entry.spellID)
                row.icon:SetTexture(spellIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.nameText:SetText(entry.name)
                row.valueText:SetText(label)

                local barWidth = maxVal > 0 and (val / maxVal * contentWidth) or 0
                row.bar:SetWidth(math.max(1, barWidth))
                row.bar:SetVertexColor(barR, barG, barB, barA)

                row.spellID = entry.spellID
                row.spellName = entry.name
                row:Show()
            end
        end
    end

    if viewMode == "drilldown" then
        titleText:ClearAllPoints()
        titleText:SetPoint("LEFT", backBtn, "RIGHT", 4, 0)
        titleText:SetText("CCT - " .. (drilldownSpellName or ""))
        headerName:SetText("Next Spell")
        headerValue:SetText("Count")
        backBtn:Show()
        sessionBtn:Hide()
        lifetimeBtn:Hide()
        resetBtn:Hide()
        local count = #currentData
        statusText:SetText((drilldownSpellName or "") .. ": " .. count .. " unique next-cast" .. (count ~= 1 and "s" or ""))
    else
        titleText:ClearAllPoints()
        titleText:SetPoint("LEFT", 4, 0)
        titleText:SetText("CCT - Clipped Casts")
        headerName:SetText("Spell")
        headerValue:SetText("Clips / Casts")
        backBtn:Hide()
        sessionBtn:Show()
        lifetimeBtn:Show()
        resetBtn:Show()
        local totalCasts, totalCancels = 0, 0
        for _, entry in ipairs(currentData) do
            totalCasts = totalCasts + (entry.casts or 0)
            totalCancels = totalCancels + (entry.cancels or 0)
        end
        local rate = totalCasts > 0 and string.format("%.1f%%", totalCancels / totalCasts * 100) or "0%"
        local prefix = useLifetime and "Lifetime" or "Session"
        statusText:SetText(prefix .. ": " .. totalCancels .. "/" .. totalCasts .. " (" .. rate .. ")")
    end

    if useLifetime then
        lifetimeBtn.label:SetTextColor(1, 1, 1)
        sessionBtn.label:SetTextColor(0.5, 0.5, 0.5)
        resetBtn.label:SetText("Reset All")
    else
        sessionBtn.label:SetTextColor(1, 1, 1)
        lifetimeBtn.label:SetTextColor(0.5, 0.5, 0.5)
        resetBtn.label:SetText("Reset")
    end

    isUpdating = false
end

function ns:InitMainWindow()
    local db = ns:GetConfig()

    mainFrame = CreateFrame("Frame", "CCTMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(db.windowWidth, db.windowHeight)
    mainFrame:SetPoint(db.windowPoint[1], UIParent, db.windowPoint[1], db.windowPoint[2], db.windowPoint[3])
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    mainFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
    mainFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    if mainFrame.SetResizeBounds then
        mainFrame:SetResizable(true)
        mainFrame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    elseif mainFrame.SetResizable then
        mainFrame:SetResizable(true)
        if mainFrame.SetMinResize then
            mainFrame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
            mainFrame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
        end
    end
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:Hide()

    mainFrame:SetScript("OnSizeChanged", function(self)
        if self:IsShown() then UpdateRows() end
    end)

    local titleBar = CreateFrame("Frame", nil, mainFrame)
    titleBar:SetHeight(TITLE_HEIGHT)
    titleBar:SetPoint("TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", -28, -4)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() mainFrame:StopMovingOrSizing() end)

    titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 4, 0)
    titleText:SetText("CCT - Clipped Casts")

    local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    backBtn = CreateFrame("Button", nil, titleBar)
    backBtn:SetSize(50, TITLE_HEIGHT)
    backBtn:SetPoint("LEFT", 0, 0)
    backBtn:EnableMouse(true)
    local backLabel = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    backLabel:SetAllPoints()
    backLabel:SetText("< Back")
    backLabel:SetTextColor(0.4, 0.8, 1)
    backBtn:SetScript("OnClick", OnBackClick)
    backBtn:SetScript("OnEnter", function() backLabel:SetTextColor(1, 1, 1) end)
    backBtn:SetScript("OnLeave", function() backLabel:SetTextColor(0.4, 0.8, 1) end)
    backBtn:Hide()

    local modeBar = CreateFrame("Frame", nil, mainFrame)
    modeBar:SetHeight(MODE_HEIGHT)
    modeBar:SetPoint("TOPLEFT", 4, -(4 + TITLE_HEIGHT))
    modeBar:SetPoint("TOPRIGHT", -4, -(4 + TITLE_HEIGHT))

    sessionBtn = CreateFrame("Button", nil, modeBar)
    sessionBtn:SetSize(60, MODE_HEIGHT)
    sessionBtn:SetPoint("LEFT", 4, 0)
    sessionBtn:EnableMouse(true)
    sessionBtn.label = sessionBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionBtn.label:SetAllPoints()
    sessionBtn.label:SetText("Session")
    sessionBtn:SetScript("OnClick", function()
        useLifetime = false
        scrollOffset = 0
        slider:SetValue(0)
        UpdateRows()
    end)

    lifetimeBtn = CreateFrame("Button", nil, modeBar)
    lifetimeBtn:SetSize(60, MODE_HEIGHT)
    lifetimeBtn:SetPoint("LEFT", sessionBtn, "RIGHT", 8, 0)
    lifetimeBtn:EnableMouse(true)
    lifetimeBtn.label = lifetimeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lifetimeBtn.label:SetAllPoints()
    lifetimeBtn.label:SetText("Lifetime")
    lifetimeBtn:SetScript("OnClick", function()
        useLifetime = true
        scrollOffset = 0
        slider:SetValue(0)
        UpdateRows()
    end)

    resetBtn = CreateFrame("Button", nil, modeBar)
    resetBtn:SetSize(50, MODE_HEIGHT)
    resetBtn:SetPoint("RIGHT", -4, 0)
    resetBtn:EnableMouse(true)
    resetBtn.label = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetBtn.label:SetAllPoints()
    resetBtn.label:SetText("Reset")
    resetBtn.label:SetTextColor(0.7, 0.4, 0.4)
    resetBtn:SetScript("OnClick", function()
        if useLifetime then
            ns:ResetLifetime()
        else
            ns:ResetSession()
        end
        scrollOffset = 0
        slider:SetValue(0)
        UpdateRows()
    end)
    resetBtn:SetScript("OnEnter", function() resetBtn.label:SetTextColor(1, 0.6, 0.6) end)
    resetBtn:SetScript("OnLeave", function() resetBtn.label:SetTextColor(0.7, 0.4, 0.4) end)

    local headerBar = CreateFrame("Frame", nil, mainFrame)
    headerBar:SetHeight(HEADER_HEIGHT)
    headerBar:SetPoint("TOPLEFT", 4, -(4 + TITLE_HEIGHT + MODE_HEIGHT))
    headerBar:SetPoint("TOPRIGHT", -4, -(4 + TITLE_HEIGHT + MODE_HEIGHT))

    headerName = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerName:SetPoint("LEFT", 24, 0)
    headerName:SetText("Spell")
    headerName:SetTextColor(0.8, 0.8, 0.5)

    headerValue = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerValue:SetPoint("RIGHT", -4, 0)
    headerValue:SetJustifyH("RIGHT")
    headerValue:SetText("Clips / Casts")
    headerValue:SetTextColor(0.8, 0.8, 0.5)

    scrollArea = CreateFrame("Frame", nil, mainFrame)
    scrollArea:SetPoint("TOPLEFT", 4, -(4 + TITLE_HEIGHT + MODE_HEIGHT + HEADER_HEIGHT))
    scrollArea:SetPoint("BOTTOMRIGHT", -4, 4 + STATUS_HEIGHT)

    slider = CreateFrame("Slider", nil, scrollArea)
    slider:SetWidth(SLIDER_WIDTH)
    slider:SetPoint("TOPRIGHT", 0, 0)
    slider:SetPoint("BOTTOMRIGHT", 0, 0)
    slider:SetOrientation("VERTICAL")
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Vertical")
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:SetValueStep(1)
    slider:SetScript("OnValueChanged", function(self, value)
        scrollOffset = math.floor(value)
        if not isUpdating then
            UpdateRows()
        end
    end)

    local sliderBg = slider:CreateTexture(nil, "BACKGROUND")
    sliderBg:SetAllPoints()
    sliderBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    sliderBg:SetVertexColor(0.1, 0.1, 0.1, 0.5)

    slider:Hide()

    for i = 1, MAX_ROWS do
        rows[i] = CreateRow(scrollArea, i)
    end

    scrollArea:EnableMouseWheel(true)
    scrollArea:SetScript("OnMouseWheel", function(self, delta)
        local newVal = slider:GetValue() - (delta * 3)
        local min, max = slider:GetMinMaxValues()
        newVal = math.max(min, math.min(max, newVal))
        slider:SetValue(newVal)
    end)

    local statusBar = CreateFrame("Frame", nil, mainFrame)
    statusBar:SetHeight(STATUS_HEIGHT)
    statusBar:SetPoint("BOTTOMLEFT", 4, 4)
    statusBar:SetPoint("BOTTOMRIGHT", -4, 4)

    statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT", 4, 0)
    statusText:SetTextColor(0.7, 0.7, 0.7)

    local resizer = CreateFrame("Frame", nil, mainFrame)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT")
    resizer:EnableMouse(true)
    resizer:SetScript("OnMouseDown", function()
        if mainFrame.StartSizing then
            mainFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizer:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        local w = math.max(MIN_WIDTH, math.min(MAX_WIDTH, mainFrame:GetWidth()))
        local h = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, mainFrame:GetHeight()))
        mainFrame:SetSize(w, h)
    end)

    local resizerTex = resizer:CreateTexture(nil, "OVERLAY")
    resizerTex:SetAllPoints()
    resizerTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    table.insert(UISpecialFrames, "CCTMainFrame")
end

function ns:ToggleMainWindow()
    if not CCTMainFrame then return end
    if CCTMainFrame:IsShown() then
        CCTMainFrame:Hide()
    else
        viewMode = "main"
        drilldownSpellID = nil
        drilldownSpellName = nil
        scrollOffset = 0
        if slider then slider:SetValue(0) end
        CCTMainFrame:Show()
        UpdateRows()
    end
end

function ns:RefreshMainWindow()
    if CCTMainFrame and CCTMainFrame:IsShown() then
        UpdateRows()
    end
end
