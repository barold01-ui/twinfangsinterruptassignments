local _, TFIA = ...
local LSM = LibStub("LibSharedMedia-3.0")

-- "Kick #n Side" with your interrupt's icon, shown for LEAD seconds before the first Broodling of
-- your pair starts casting. Counts down to 0, then hides and plays the chosen sound. Your own add
-- is that Broodling or the one 1s later (sides can't be told apart), both inside the 3s cast.
--
-- Wave 1's reminder is due 0.5s before Rouse is even cast, so every wave is scheduled from pull
-- time (Rouse spread is 0.1s post-nerf) and re-synced to the real Rouse when it fires.

local LEAD = 5

local KICK_BY_CLASS = {
    DEATHKNIGHT = 47528,  -- Mind Freeze
    DEMONHUNTER = 183752, -- Disrupt
    EVOKER = 351338,      -- Quell
    MAGE = 2139,          -- Counterspell
    MONK = 116705,        -- Spear Hand Strike
    PALADIN = 96231,      -- Rebuke
    PRIEST = 220543,      -- Silence
    ROGUE = 1766,         -- Kick
    SHAMAN = 57994,       -- Wind Shear
    WARLOCK = 19647,      -- Spell Lock
    WARRIOR = 6552,       -- Pummel
}
local KICK_BY_SPEC = {
    [102] = 97547,  -- Balance: Solar Beam
    [103] = 93985,  -- Feral: Skull Bash
    [104] = 93985,  -- Guardian: Skull Bash
    [253] = 147362, -- Beast Mastery: Counter Shot
    [254] = 147362, -- Marksmanship: Counter Shot
    [255] = 187707, -- Survival: Muzzle
}
local FALLBACK_ICON = "Interface\\Icons\\ability_kick"

local waveTimers = {} -- wave index -> C_Timer handle
local hideAt          -- GetTime() at which the shown reminder ends

local function KickIcon()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex)
    local _, class = UnitClass("player")
    local spellID = KICK_BY_SPEC[specID] or KICK_BY_CLASS[class]
    return spellID and C_Spell.GetSpellTexture(spellID) or FALLBACK_ICON
end

local function PlayReminderSound()
    local name = TFIA.db.reminderSound
    if name == "None" then return end
    local file = LSM:Fetch("sound", name, true)
    if file then
        PlaySoundFile(file, "Master")
    end
end

local frame = CreateFrame("Frame", nil, UIParent)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame.Icon = frame:CreateTexture(nil, "ARTWORK")
frame.Icon:SetPoint("LEFT")
frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- crop the blocky edge baked into spell icons
frame.Border = frame:CreateTexture(nil, "BACKGROUND")
frame.Border:SetColorTexture(0, 0, 0, 1)
frame.Border:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -1, 1)
frame.Border:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 1, -1)
frame.Cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
frame.Cooldown:SetAllPoints(frame.Icon)
frame.Cooldown:SetHideCountdownNumbers(true)
frame.Cooldown:SetDrawEdge(false)
frame.Cooldown:SetReverse(true) -- swipe starts full and drains
-- Text sits on its own frame so it draws above the cooldown swipe.
frame.TextFrame = CreateFrame("Frame", nil, frame)
frame.TextFrame:SetAllPoints()
frame.TextFrame:SetFrameLevel(frame.Cooldown:GetFrameLevel() + 1)
frame.Countdown = frame.TextFrame:CreateFontString(nil, "OVERLAY")
frame.Countdown:SetPoint("CENTER", frame.Icon)
frame.Countdown:SetTextColor(1, 1, 1, 1)
frame.Text = frame.TextFrame:CreateFontString(nil, "OVERLAY")
frame.Text:SetPoint("LEFT", frame.Icon, "RIGHT", 8, 0)
frame:Hide()

local function ReminderText()
    local db = TFIA.db
    if not TFIA:IsAssigned() then
        return "No kick assigned"
    elseif db.side == "None" then
        return string.format("Kick #%d", db.myNumber)
    end
    return string.format("Kick #%d %s", db.myNumber, db.side)
end

local function StyleReminder()
    local db = TFIA.db
    local size = db.reminderSize
    frame.Icon:SetSize(size, size)
    frame.Icon:SetTexture(KickIcon())
    frame.Countdown:SetFont(STANDARD_TEXT_FONT, size * 0.6, "OUTLINE")
    frame.Text:SetFont(STANDARD_TEXT_FONT, size * 0.5, "OUTLINE")
    frame.Text:SetText(ReminderText())
    frame:SetSize(size + 8 + frame.Text:GetStringWidth(), size)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", db.reminderX, db.reminderY)
end

-- Unlocked: a static preview that can be dragged; a green border marks it.
local function ShowPreview()
    StyleReminder()
    frame.Border:SetColorTexture(0, 1, 0, 1)
    frame.Cooldown:Clear()
    frame.Countdown:SetText(LEAD)
    frame:Show()
end

local function EndReminder()
    hideAt = nil
    if TFIA.reminderUnlocked then
        ShowPreview()
    else
        frame:Hide()
    end
end

frame:SetScript("OnUpdate", function()
    if not hideAt then return end -- unlocked preview, nothing to count
    local remaining = hideAt - GetTime()
    if remaining <= 0 then
        EndReminder()
        PlayReminderSound()
        return
    end
    frame.Countdown:SetText(math.ceil(remaining))
end)

local function ShowReminder(castAt)
    hideAt = castAt
    StyleReminder()
    frame.Border:SetColorTexture(0, 0, 0, 1)
    frame.Cooldown:SetCooldown(castAt - LEAD, LEAD)
    frame:Show()
end

-- Dragging -----------------------------------------------------------------------------------

frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function()
    if TFIA.reminderUnlocked then
        frame:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    -- Save the new centre offset; the setters re-anchor the frame to the same spot.
    local x, y = frame:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    TFIA:SetSetting("reminderX", math.floor(x - centerX + 0.5))
    TFIA:SetSetting("reminderY", math.floor(y - centerY + 0.5))
end)
frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        TFIA:SetSetting("reminderUnlocked", false)
    end
end)
-- RegisterForDrag and mouse scripts switch the mouse on; it stays off until unlocked.
frame:EnableMouse(false)

-- Not saved: a reload always starts locked.
function TFIA:SetReminderUnlocked(unlocked)
    self.reminderUnlocked = unlocked
    frame:EnableMouse(unlocked)
    if unlocked then
        if not hideAt then
            ShowPreview()
        end
    elseif not hideAt then
        frame:Hide()
    end
end

-- Scheduling ---------------------------------------------------------------------------------

-- (Re)schedules one wave's reminder from its Rouse time. Shows straight away if the lead time
-- has already started, which is how a re-sync updates a reminder that is already on screen.
local function ScheduleWave(wave, rouseTime)
    if waveTimers[wave] then
        waveTimers[wave]:Cancel()
    end
    local castAt = rouseTime + TFIA:PairCastOffset(TFIA.db.myNumber)
    if castAt <= GetTime() then return end
    local delay = math.max(castAt - LEAD - GetTime(), 0)
    waveTimers[wave] = C_Timer.NewTimer(delay, function() ShowReminder(castAt) end)
end

local function RemindersWanted()
    return TFIA.db.reminderEnabled and TFIA:IsAssigned()
end

function TFIA:StartReminders()
    if not RemindersWanted() then return end
    for wave, rouseTime in ipairs(self.WAVE_ROUSE_TIMES) do
        ScheduleWave(wave, self.pullTime + rouseTime)
    end
end

function TFIA:StopReminders()
    for wave, timer in pairs(waveTimers) do
        timer:Cancel()
        waveTimers[wave] = nil
    end
    EndReminder()
end

-- Called by Nameplates.lua with the real Rouse cast start.
function TFIA:OnRouse(wave, rouseTime)
    if self.inEncounter and RemindersWanted() then
        ScheduleWave(wave, rouseTime)
    end
end

function TFIA:TestReminder()
    ShowReminder(GetTime() + LEAD)
end

-- Re-style a reminder that is on screen, e.g. after a settings change.
function TFIA:RefreshReminder()
    if not frame:IsShown() then return end
    if hideAt then
        StyleReminder()
    else
        ShowPreview()
    end
end
