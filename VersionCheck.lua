local _, TFIA = ...

-- "Version check" in the options: asks the group ("V?"), every copy of the addon whispers back
-- "V:<version>", and a window lists each member with what they answered.

local ROW_HEIGHT = 18
local NO_RESPONSE = "|cff808080No response|r"

local window   -- built on first check
local rows = {}
local versions = {} -- name without realm -> version, for the current check

local function VersionText(version)
    if not version then
        return NO_RESPONSE
    elseif version == TFIA.VERSION then
        return "|cff40ff40" .. version .. "|r"
    else
        return "|cffff8000" .. version .. "|r"
    end
end

local function GetRow(index)
    if not rows[index] then
        local name = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("TOPLEFT", 24, -50 - (index - 1) * ROW_HEIGHT)
        local version = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        version:SetPoint("TOPLEFT", 190, -50 - (index - 1) * ROW_HEIGHT)
        rows[index] = {Name = name, Version = version}
    end
    return rows[index]
end

local function RefreshWindow()
    local members = {}
    TFIA:IterateGroupMembers(function(name, class)
        members[#members + 1] = {name = name, class = class}
    end)
    table.sort(members, function(a, b) return a.name < b.name end)

    for i, member in ipairs(members) do
        local row = GetRow(i)
        row.Name:SetText(C_ClassColor.GetClassColor(member.class):WrapTextInColorCode(member.name))
        row.Version:SetText(VersionText(versions[member.name]))
        row.Name:Show()
        row.Version:Show()
    end
    for i = #members + 1, #rows do
        rows[i].Name:Hide()
        rows[i].Version:Hide()
    end
    window:SetHeight(70 + #members * ROW_HEIGHT)
end

local function CreateWindow()
    window = CreateFrame("Frame", "TFIAVersionWindow", UIParent, "BackdropTemplate")
    window:SetSize(300, 100)
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
    window:RegisterEvent("GROUP_ROSTER_UPDATE")
    window:SetScript("OnEvent", RefreshWindow)
    tinsert(UISpecialFrames, window:GetName()) -- close on Escape

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("TFIA Versions")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
end

function TFIA:StartVersionCheck()
    if not window then
        CreateWindow()
    end
    wipe(versions)
    RefreshWindow()
    window:Show()
    self:SendToGroup("V?")
end

local function OnAddonMessage(prefix, message, _, sender)
    if prefix ~= TFIA.MESSAGE_PREFIX then return end
    if message == "V?" then
        C_ChatInfo.SendAddonMessage(TFIA.MESSAGE_PREFIX, "V:" .. TFIA.VERSION, "WHISPER", sender)
    elseif message:sub(1, 2) == "V:" then
        versions[Ambiguate(sender, "short")] = message:sub(3)
        if window and window:IsShown() then
            RefreshWindow()
        end
    end
end

local messageFrame = CreateFrame("Frame")
messageFrame:RegisterEvent("CHAT_MSG_ADDON")
messageFrame:SetScript("OnEvent", function(_, _, ...) OnAddonMessage(...) end)
