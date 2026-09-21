local ADDON_NAME, TFIA = ...

TFIA.ENCOUNTER_ID = 3421 -- The Twin Fangs
TFIA.MYTHIC_DIFFICULTY = 16 -- Heroic has no Broodlings and a different Ithraz cast cycle

TFIA.defaults = {
    enabled = true,
    testMode = false, -- number every hostile nameplate, anywhere
    debug = false,    -- print plate details to chat as they are numbered
    showAll = false,  -- false = only show boxes for my number
    myNumber = 0,     -- 0 = no kick assigned
    boxSize = 50,
    fontSize = 24,
    yOffset = 20,
    reminderEnabled = true, -- "Kick #n Side" countdown before your pair's first cast
    side = "None",          -- "Left" / "Right", which side of the room you kick on
    reminderSound = "None", -- LibSharedMedia sound name, played when the countdown ends
    reminderSize = 48,
    reminderX = 0,          -- offset from the centre of the screen
    reminderY = 150,
    assignments = { -- raid leader's list, also filled in by a received broadcast
        Left = {"", "", "", "", ""},
        Right = {"", "", "", "", ""},
    },
    colors = {
        box = {1, 0, 0, 1},
        text = {1, 1, 1, 1},
        myBox = {0, 1, 0, 1},
        myText = {1, 0, 0, 1},
    },
}

local function CopyDefaults(src, dst)
    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = CopyDefaults(value, type(dst[key]) == "table" and dst[key] or {})
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
    return dst
end

-- Group helpers, shared by Assignments.lua and VersionCheck.lua ------------------------------

TFIA.MESSAGE_PREFIX = "TFIA"
TFIA.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
C_ChatInfo.RegisterAddonMessagePrefix(TFIA.MESSAGE_PREFIX)

-- Solo: whispered to yourself, so receive paths can be tested alone.
function TFIA:SendToGroup(message)
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(self.MESSAGE_PREFIX, message, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(self.MESSAGE_PREFIX, message, "PARTY")
    else
        C_ChatInfo.SendAddonMessage(self.MESSAGE_PREFIX, message, "WHISPER", UnitName("player"))
    end
end

function TFIA.StripRealm(name)
    return (strsplit("-", name))
end

-- callback(name without realm, class token)
function TFIA:IterateGroupMembers(callback)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            if name then
                callback(self.StripRealm(name), class)
            end
        end
    else
        callback(UnitName("player"), select(2, UnitClass("player")))
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            callback(UnitName(unit), select(2, UnitClass(unit)))
        end
    end
end

function TFIA:IsAssigned()
    return self.db.myNumber > 0
end

function TFIA:Print(msg)
    print("|cFF00FF96TFIA:|r " .. msg)
end

-- Boxes should be live during the encounter, or always while test mode is on.
function TFIA:ShouldBeActive()
    return self.db.enabled and (self.db.testMode or self.inEncounter)
end

function TFIA:UpdateActiveState()
    if self:ShouldBeActive() then
        self:StartNameplates()
    else
        self:StopNameplates()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        TwinFangsInterruptAssignmentsDB = CopyDefaults(TFIA.defaults, TwinFangsInterruptAssignmentsDB or {})
        TFIA.db = TwinFangsInterruptAssignmentsDB
        TFIA:InitOptions()
        TFIA:UpdateActiveState()
    elseif event == "ENCOUNTER_START" then
        local encounterID, _, difficultyID = ...
        if encounterID == TFIA.ENCOUNTER_ID and tonumber(difficultyID) == TFIA.MYTHIC_DIFFICULTY then
            TFIA.inEncounter = true
            TFIA.pullTime = GetTime()
            TFIA:ResetNumbering()
            TFIA:UpdateActiveState()
            TFIA:StartReminders()
        end
    elseif event == "ENCOUNTER_END" then
        local encounterID = ...
        if encounterID == TFIA.ENCOUNTER_ID then
            TFIA.inEncounter = false
            TFIA.pullTime = nil
            TFIA:UpdateActiveState()
            TFIA:StopReminders()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A zone change mid-fight never fires ENCOUNTER_END.
        TFIA.inEncounter = false
        TFIA:UpdateActiveState()
        TFIA:StopReminders()
    end
end)

SLASH_TFIA1 = "/tfia"
SlashCmdList.TFIA = function(input)
    local command = strtrim(strlower(input or ""))
    if command == "test" then
        TFIA.db.testMode = not TFIA.db.testMode
        TFIA:Print("test mode " .. (TFIA.db.testMode and "on" or "off"))
        TFIA:ResetNumbering()
        TFIA:UpdateActiveState()
    elseif command == "debug" then
        TFIA.db.debug = not TFIA.db.debug
        TFIA:Print("debug " .. (TFIA.db.debug and "on" or "off"))
    elseif command == "assign" then
        TFIA:OpenAssignments()
    elseif command == "version" then
        TFIA:StartVersionCheck()
    elseif command == "unlock" then
        TFIA:SetSetting("reminderUnlocked", not TFIA.reminderUnlocked)
    elseif command == "remind" then
        TFIA:TestReminder()
    elseif command == "reset" then
        TFIA:ResetNumbering()
        TFIA:RefreshNameplates()
        TFIA:Print("numbering reset")
    elseif tonumber(command) then
        TFIA:SetSetting("myNumber", tonumber(command))
        TFIA:Print("your number is now " .. TFIA.db.myNumber)
    else
        TFIA:OpenOptions()
    end
end
