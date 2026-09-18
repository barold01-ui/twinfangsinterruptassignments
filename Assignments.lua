local _, TFIA = ...

-- Raid leader window: five names per side, typed or picked from the group. The leader broadcasts
-- them as an addon message; every assigned player's number and side update to match.

local SIDES = {"Left", "Right"}
local SLOTS = 5
local ROW_HEIGHT = 30

local window   -- built on first open
local slots = {} -- side -> {editbox, ...}

local function ClassColorOf(name)
    local found
    TFIA:IterateGroupMembers(function(member, class)
        if not found and strlower(member) == strlower(name) then
            found = C_ClassColor.GetClassColor(class)
        end
    end)
    return found
end

local function Assignments()
    return TFIA.db.assignments
end

local function AllSlotsFilled()
    for _, side in ipairs(SIDES) do
        for i = 1, SLOTS do
            if Assignments()[side][i] == "" then return false end
        end
    end
    return true
end

-- Leader or assistant, or solo (nobody to check against).
function TFIA.CanManageAssignments()
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Sets the player's own number and side from the assignment list, if they are on it.
-- Goes through the Settings API so an open options panel updates too.
local function ApplyToPlayer(sender)
    local me = strlower(UnitName("player"))
    for number = 1, SLOTS do
        for _, side in ipairs(SIDES) do
            if strlower(Assignments()[side][number]) == me then
                TFIA:SetSetting("myNumber", number)
                TFIA:SetSetting("side", side)
                TFIA:Print(string.format("Kick #%d %s, set by %s", number, side, sender))
                return
            end
        end
    end
end

-- Message: "A:" then the ten names, Left 1-5 first, comma separated. Addon messages cap at 255 bytes.
local function Broadcast()
    local names = {}
    for _, side in ipairs(SIDES) do
        for i = 1, SLOTS do
            names[#names + 1] = TFIA.StripRealm(Assignments()[side][i])
        end
    end
    local message = "A:" .. table.concat(names, ",")
    if #message > 255 then
        TFIA:Print("assignments are too long to send; shorten the names")
        return
    end
    TFIA:SendToGroup(message)
    TFIA:Print("assignments sent")
end

local function OnAddonMessage(prefix, message, _, sender)
    if prefix ~= TFIA.MESSAGE_PREFIX or message:sub(1, 2) ~= "A:" then return end
    local names = {strsplit(",", message:sub(3))}
    if #names ~= SLOTS * 2 then return end
    for s, side in ipairs(SIDES) do
        for i = 1, SLOTS do
            Assignments()[side][i] = names[(s - 1) * SLOTS + i]
        end
    end
    if window then
        TFIA:RefreshAssignments()
    end
    ApplyToPlayer(Ambiguate(sender, "short"))
end

-- Window ---------------------------------------------------------------------------------------

local function UpdateSlotColor(editbox)
    local color = ClassColorOf(strtrim(editbox:GetText()))
    if color then
        editbox:SetTextColor(color:GetRGB())
    else
        editbox:SetTextColor(1, 1, 1)
    end
end

local function UpdateBroadcastButton()
    local button = window.Broadcast
    if not button then return end -- still building the window
    if not TFIA.CanManageAssignments() then
        button.reason = "Only the group leader or an assistant can broadcast."
    elseif not AllSlotsFilled() then
        button.reason = "Fill in all ten slots first."
    else
        button.reason = nil
    end
    button:SetEnabled(button.reason == nil)
end

local function CreatePicker(editbox, side, index)
    local picker = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
    picker:SetPoint("LEFT", editbox, "RIGHT", 2, 0)
    picker:SetSize(26, 22)
    picker:SetupMenu(function(_, root)
        root:SetScrollMode(300)
        local members = {}
        TFIA:IterateGroupMembers(function(name, class)
            members[#members + 1] = {name = name, class = class}
        end)
        table.sort(members, function(a, b) return a.name < b.name end)
        for _, member in ipairs(members) do
            local label = C_ClassColor.GetClassColor(member.class):WrapTextInColorCode(member.name)
            root:CreateButton(label, function() editbox:SetText(member.name) end)
        end
    end)
    return picker
end

local function CreateSlot(side, index, x, y)
    local label = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText("Interrupt " .. index)

    local editbox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    editbox:SetPoint("LEFT", label, "LEFT", 78, 0)
    editbox:SetSize(100, 20)
    editbox:SetAutoFocus(false)
    editbox:SetMaxLetters(24)
    editbox:SetScript("OnEnterPressed", editbox.ClearFocus)
    editbox:SetScript("OnEscapePressed", editbox.ClearFocus)
    editbox:SetScript("OnTextChanged", function(self)
        Assignments()[side][index] = strtrim(self:GetText())
        UpdateSlotColor(self)
        UpdateBroadcastButton()
    end)
    CreatePicker(editbox, side, index)
    slots[side][index] = editbox
end

local function CreateWindow()
    window = CreateFrame("Frame", "TFIAAssignmentsWindow", UIParent, "BackdropTemplate")
    window:SetSize(470, 270)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11},
    })
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetScript("OnShow", function() TFIA:RefreshAssignments() end)
    tinsert(UISpecialFrames, window:GetName()) -- close on Escape

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Twin Fangs Interrupt Assignments")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local columnX = {Left = 24, Right = 250}
    for _, side in ipairs(SIDES) do
        slots[side] = {}
        local header = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        header:SetPoint("TOPLEFT", columnX[side], -46)
        header:SetText(side)
        for i = 1, SLOTS do
            CreateSlot(side, i, columnX[side], -70 - (i - 1) * ROW_HEIGHT)
        end
    end

    local broadcast = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    broadcast:SetPoint("BOTTOM", 0, 20)
    broadcast:SetSize(160, 24)
    broadcast:SetText("Broadcast to group")
    broadcast:SetScript("OnClick", Broadcast)
    broadcast:SetMotionScriptsWhileDisabled(true)
    broadcast:SetScript("OnEnter", function(self)
        if self.reason then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.reason)
            GameTooltip:Show()
        end
    end)
    broadcast:SetScript("OnLeave", GameTooltip_Hide)
    window.Broadcast = broadcast

    window:RegisterEvent("GROUP_ROSTER_UPDATE")
    window:SetScript("OnEvent", function() TFIA:RefreshAssignments() end)
    window:Hide() -- so the first Show() runs OnShow
end

-- Reload the boxes from the saved assignments and re-evaluate colours and the broadcast button.
function TFIA:RefreshAssignments()
    for _, side in ipairs(SIDES) do
        for i = 1, SLOTS do
            local editbox = slots[side][i]
            local name = Assignments()[side][i]
            if editbox:GetText() ~= name then
                editbox:SetText(name)
            end
            UpdateSlotColor(editbox)
        end
    end
    UpdateBroadcastButton()
end

function TFIA:OpenAssignments()
    if not window then
        CreateWindow()
    end
    window:Show()
end

local messageFrame = CreateFrame("Frame")
messageFrame:RegisterEvent("CHAT_MSG_ADDON")
messageFrame:SetScript("OnEvent", function(_, _, ...) OnAddonMessage(...) end)
