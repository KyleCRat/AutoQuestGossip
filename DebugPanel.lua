local _, AQG = ...

local PANEL_WIDTH = 350
local PANEL_HEIGHT_DETACHED = 500
local FONT_PATH = "Interface\\AddOns\\AutoQuestGossip\\Media\\font\\JetBrainsMono-Regular.ttf"
local FONT_SIZE = 9
local PADDING = 8
local BG_COLOR = { 0, 0, 0, 0.85 }
local BORDER_COLOR = { 0, 0.8, 1, 0.6 }

local detached = false -- true when opened via /aqg debug
local lines = {}

-- Create the main panel frame
local panel = CreateFrame("Frame", "AQGDebugPanel", UIParent, "BackdropTemplate")
panel:SetWidth(PANEL_WIDTH)
panel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
panel:SetBackdropColor(unpack(BG_COLOR))
panel:SetBackdropBorderColor(unpack(BORDER_COLOR))
panel:SetFrameStrata("HIGH")
panel:Hide()

-- Title bar
local title = panel:CreateFontString(nil, "OVERLAY")
title:SetFont(FONT_PATH, FONT_SIZE + 1, "")
title:SetTextColor(0, 0.8, 1, 1)
title:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -PADDING)
title:SetText("AQG Debug")

-- Close button
local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
closeBtn:SetScript("OnClick", function()
    if AQG.ToggleDetachedPanel then
        AQG:ToggleDetachedPanel()
    else
        panel:Hide()
    end
end)

-- Scroll frame
local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -(PADDING * 2 + FONT_SIZE + 2))
scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING, PADDING)
scrollFrame:EnableMouseWheel(true)

-- Scroll child
local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetWidth(PANEL_WIDTH - PADDING * 2)
scrollChild:SetHeight(1) -- grows dynamically
scrollFrame:SetScrollChild(scrollChild)

-- Hidden FontString for height measurement
local measure = scrollChild:CreateFontString(nil, "OVERLAY")
measure:SetFont(FONT_PATH, FONT_SIZE, "")
measure:SetJustifyH("LEFT")
measure:SetWordWrap(true)
measure:SetWidth(PANEL_WIDTH - PADDING * 2)
measure:SetAlpha(0)
measure:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)

-- Content EditBox (selectable/copyable)
local content = CreateFrame("EditBox", nil, scrollChild)
content:SetFont(FONT_PATH, FONT_SIZE, "")
content:SetTextColor(0.9, 0.9, 0.9, 1)
content:SetMultiLine(true)
content:SetAutoFocus(false)
content:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
content:SetWidth(PANEL_WIDTH - PADDING * 2)
content:SetText("")
content:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)

content:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        self:SetText(table.concat(lines, "\n"))
    end
end)

-- Mouse wheel scrolling
local scrollPos = 0

local function UpdateScroll()
    local contentHeight = measure:GetStringHeight() or 0
    local viewHeight = scrollFrame:GetHeight() or 0
    local maxScroll = math.max(0, contentHeight - viewHeight)
    scrollPos = math.max(0, math.min(scrollPos, maxScroll))
    scrollFrame:SetVerticalScroll(scrollPos)
end

scrollFrame:SetScript("OnMouseWheel", function(_, delta)
    local step = FONT_SIZE * 3
    scrollPos = scrollPos - (delta * step)
    UpdateScroll()
end)

local MAX_LINES = 2000

function AQG:PanelPrint(text)
    table.insert(lines, text)
    if #lines > MAX_LINES then
        table.remove(lines, 1)
    end

    local joined = table.concat(lines, "\n")
    measure:SetText(joined)
    content:SetText(joined)

    -- Resize scroll child to fit content
    local contentHeight = measure:GetStringHeight() or 0
    scrollChild:SetHeight(contentHeight)
    content:SetHeight(contentHeight)

    -- Auto-scroll to bottom (deferred so layout is calculated)
    C_Timer.After(0, function()
        local viewHeight = scrollFrame:GetHeight() or 0
        local totalHeight = measure:GetStringHeight() or 0
        scrollPos = math.max(0, totalHeight - viewHeight)
        UpdateScroll()
    end)
end

function AQG:PanelClear()
    lines = {}
    measure:SetText("")
    content:SetText("")
    scrollChild:SetHeight(1)
    content:SetHeight(1)
    scrollPos = 0
    scrollFrame:SetVerticalScroll(0)
end

function AQG:ShowPanel(anchorFrame)
    if detached then return end
    if not anchorFrame then return end
    -- Re-parent to the anchor frame so we survive UIParent alpha/visibility changes
    -- (e.g. DialogueUI fades UIParent to 0 when its quest frame opens)
    panel:SetParent(anchorFrame)
    panel:SetMovable(false)
    panel:EnableMouse(false)
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -10, 0)
    panel:SetHeight(anchorFrame:GetHeight())
    panel:SetFrameStrata("HIGH")
    -- Re-apply font after re-parenting (invalidates nested font objects)
    measure:SetFont(FONT_PATH, FONT_SIZE, "")
    content:SetFont(FONT_PATH, FONT_SIZE, "")
    panel:Show()
end

function AQG:HidePanel()
    if detached then return end
    panel:Hide()
    panel:SetParent(UIParent)
end

function AQG:ToggleDetachedPanel()
    if detached then
        -- Close detached mode
        detached = false
        panel:SetScale(1)
        panel:SetMovable(false)
        panel:EnableMouse(false)
        panel:RegisterForDrag()
        panel:Hide()
        panel:SetParent(UIParent)
    else
        -- Open in detached mode
        detached = true
        panel:SetParent(UIParent)
        panel:SetScale(1.5)
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER")
        panel:SetHeight(PANEL_HEIGHT_DETACHED)
        panel:SetFrameStrata("HIGH")
        panel:SetMovable(true)
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:RegisterForDrag("LeftButton")
        panel:Show()
    end
end

panel:SetScript("OnDragStart", function(self)
    if detached then self:StartMoving() end
end)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

-- Hook QuestFrame and GossipFrame show/hide to manage the panel
local framesHooked = {}

local function HookFrame(frame)
    if not frame or framesHooked[frame] then return end
    framesHooked[frame] = true

    frame:HookScript("OnShow", function(self)
        if AutoQuestGossipDB and AutoQuestGossipDB.debugEnabled then
            AQG:ShowPanel(self)
        end
    end)

    frame:HookScript("OnHide", function()
        AQG:HidePanel()
    end)

    frame:HookScript("OnSizeChanged", function(self)
        if not detached and panel:IsShown() then
            panel:SetHeight(self:GetHeight())
        end
    end)
end

local function TryHookFrames()
    HookFrame(QuestFrame)
    HookFrame(GossipFrame)
    -- DialogueUI addon (YUI-Dialogue) replaces the quest/gossip frames with DUIQuestFrame
    HookFrame(DUIQuestFrame)
end

-- Hook on init (frames may exist already)
AQG:OnInit(TryHookFrames)

-- Also try hooking when panel is shown (fallback for load-on-demand frames)
local origShowPanel = AQG.ShowPanel
function AQG:ShowPanel(anchorFrame)
    TryHookFrames()
    origShowPanel(self, anchorFrame)
end
