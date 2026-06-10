local _, AQG = ...

local PANEL_WIDTH = 350
local PANEL_HEIGHT_DETACHED = 500
local FONT_PATH = "Interface\\AddOns\\AutoQuestGossip\\Media\\font\\JetBrainsMono-Regular.ttf"
local FONT_SIZE = 9
local PAUSE_FONT_SIZE = 12
local PADDING = 8
local BG_COLOR = { 0, 0, 0, 0.85 }
local BORDER_COLOR = { 0, 0.8, 1, 0.6 }
local PAUSE_COLOR = { 1, 0.15, 0.15, 1 }
local PAUSE_FRAME_STRATA = "TOOLTIP"

local detached = false -- true when opened via /aqg debug
local lines = {}
local pauseReason
local TryHookFrames

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

-- User-facing pause reason shown below the active quest/gossip frame.
local pauseFrame = CreateFrame("Frame", "AQGPauseIndicator", UIParent)
pauseFrame:SetHeight(56)
pauseFrame:SetFrameStrata(PAUSE_FRAME_STRATA)
pauseFrame:SetToplevel(true)
pauseFrame:Hide()

local pauseText = pauseFrame:CreateFontString(nil, "OVERLAY")
pauseText:SetDrawLayer("OVERLAY", 7)
pauseText:SetFont(FONT_PATH, PAUSE_FONT_SIZE, "THICKOUTLINE")
pauseText:SetTextColor(unpack(PAUSE_COLOR))
pauseText:SetShadowColor(0, 0, 0, 1)
pauseText:SetShadowOffset(2, -2)
pauseText:SetJustifyH("CENTER")
pauseText:SetJustifyV("TOP")
pauseText:SetWordWrap(true)
pauseText:SetPoint("TOPLEFT", pauseFrame, "TOPLEFT", PADDING, 0)
pauseText:SetPoint("TOPRIGHT", pauseFrame, "TOPRIGHT", -PADDING, 0)

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

-- Scroll child - anchored to BOTTOMLEFT so content grows upward
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
measure:SetPoint("BOTTOMLEFT", scrollChild, "BOTTOMLEFT", 0, 0)

-- Content EditBox (selectable/copyable) - anchored to bottom
local content = CreateFrame("EditBox", nil, scrollChild)
content:SetFont(FONT_PATH, FONT_SIZE, "")
content:SetTextColor(0.9, 0.9, 0.9, 1)
content:SetMultiLine(true)
content:SetAutoFocus(false)
content:SetPoint("BOTTOMLEFT", scrollChild, "BOTTOMLEFT", 0, 0)
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
-- scrollPos 0 = bottom (newest), positive = scrolled up toward older text
local scrollPos = 0

local function UpdateScroll()
    local contentHeight = scrollChild:GetHeight() or 0
    local viewHeight = scrollFrame:GetHeight() or 0
    local maxScroll = math.max(0, contentHeight - viewHeight)

    scrollPos = math.max(0, math.min(scrollPos, maxScroll))

    -- Invert: scrollFrame offset 0 = top of content visible,
    -- we want offset 0 = bottom visible, so offset = maxScroll - scrollPos
    scrollFrame:SetVerticalScroll(maxScroll - scrollPos)
end

scrollFrame:SetScript("OnMouseWheel", function(_, delta)
    local step = FONT_SIZE * 3
    scrollPos = scrollPos + (delta * step) -- scroll up = positive delta = scroll toward older
    UpdateScroll()
end)

local MAX_LINES = 2000

local function CurrentAnchorFrame()
    return (DUIQuestFrame and DUIQuestFrame:IsShown() and DUIQuestFrame)
        or (GossipFrame and GossipFrame:IsShown() and GossipFrame)
        or (QuestFrame and QuestFrame:IsShown() and QuestFrame)
end

function AQG:GetInteractionAnchorFrame()
    if TryHookFrames then
        TryHookFrames()
    end

    return CurrentAnchorFrame()
end

local function AnchorPauseFrame(anchorFrame)
    if not anchorFrame then return false end

    local width = 420
    if anchorFrame.GetWidth then
        width = anchorFrame:GetWidth() or width
    end

    pauseFrame:SetParent(anchorFrame)
    pauseFrame:SetWidth(width)
    pauseFrame:ClearAllPoints()
    pauseFrame:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -8)
    pauseFrame:SetFrameStrata(PAUSE_FRAME_STRATA)
    pauseFrame:SetToplevel(true)

    if anchorFrame.GetFrameLevel then
        pauseFrame:SetFrameLevel((anchorFrame:GetFrameLevel() or 1) + 100)
    end

    -- Re-apply after re-parenting; nested FontStrings can lose font settings.
    pauseText:SetFont(FONT_PATH, PAUSE_FONT_SIZE, "THICKOUTLINE")
    pauseText:SetTextColor(unpack(PAUSE_COLOR))

    return true
end

local function PauseDisplayText(reason)
    return "AQG Paused: " .. reason
end

function AQG:ShowPauseReason(reason, anchorFrame)
    if not reason or reason == "" then
        if self.HidePauseReason then
            self:HidePauseReason()
        end
        return
    end

    pauseReason = reason
    if TryHookFrames then
        TryHookFrames()
    end

    anchorFrame = anchorFrame or CurrentAnchorFrame()

    if not AnchorPauseFrame(anchorFrame) then
        return
    end

    pauseText:SetText(PauseDisplayText(reason))
    pauseFrame:Show()
end

function AQG:RefreshPauseReason(anchorFrame)
    if not pauseReason then return end

    anchorFrame = anchorFrame or CurrentAnchorFrame()
    if AnchorPauseFrame(anchorFrame) then
        pauseText:SetText(PauseDisplayText(pauseReason))
        pauseFrame:Show()
    end
end

function AQG:HidePauseReason()
    pauseReason = nil
    pauseFrame:Hide()
    pauseFrame:SetParent(UIParent)
end

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

    -- Stay pinned to bottom unless user has scrolled up
    if scrollPos <= FONT_SIZE then
        scrollPos = 0
    end

    C_Timer.After(0, function()
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

function AQG:PanelScrollToBottom()
    scrollPos = 0

    C_Timer.After(0, function()
        UpdateScroll()
    end)
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
        if AQG.RefreshPauseReason then
            AQG:RefreshPauseReason(self)
        end

        if AutoQuestGossipDB and AutoQuestGossipDB.debugEnabled then
            AQG:ShowPanel(self)
        end
    end)

    frame:HookScript("OnHide", function()
        AQG:HidePanel()
        if AQG.HidePauseReason then
            AQG:HidePauseReason()
        end
    end)

    frame:HookScript("OnSizeChanged", function(self)
        if not detached and panel:IsShown() then
            panel:SetHeight(self:GetHeight())
        end

        if AQG.RefreshPauseReason then
            AQG:RefreshPauseReason(self)
        end
    end)
end

local function ResetPauseReason()
    if AQG.HidePauseReason then
        AQG:HidePauseReason()
    end
end

TryHookFrames = function()
    HookFrame(QuestFrame)
    HookFrame(GossipFrame)
    -- DialogueUI addon (YUI-Dialogue) replaces the quest/gossip frames with DUIQuestFrame
    HookFrame(DUIQuestFrame)
end

-- Hook on init (frames may exist already)
AQG:OnInit(TryHookFrames)

AQG:RegisterEvent("GOSSIP_SHOW", ResetPauseReason)
AQG:RegisterEvent("QUEST_GREETING", ResetPauseReason)
AQG:RegisterEvent("QUEST_ACCEPT_CONFIRM", ResetPauseReason)
AQG:RegisterEvent("QUEST_DETAIL", ResetPauseReason)
AQG:RegisterEvent("QUEST_PROGRESS", ResetPauseReason)
AQG:RegisterEvent("QUEST_COMPLETE", ResetPauseReason)
AQG:RegisterEvent("QUEST_AUTOCOMPLETE", ResetPauseReason)

-- Also try hooking when panel is shown (fallback for load-on-demand frames)
local origShowPanel = AQG.ShowPanel
function AQG:ShowPanel(anchorFrame)
    TryHookFrames()
    origShowPanel(self, anchorFrame)
end
