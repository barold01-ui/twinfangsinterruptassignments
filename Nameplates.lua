local _, TFIA = ...

-- Each wave Ithraz casts Rouse the Brood and 10 Broodlings spawn, alternating sides.
-- Their first Visceral Burst casts start at Rouse + 4.5s, +5.5s ... +13.5s (22 post-nerf US Mythic
-- kills on Warcraft Logs, jitter ~0.1s). So the moment a plate starts its first cast tells us which
-- Broodling it is, and spawn order maps to pairs: 1, 1, 2, 2 ... 5, 5.
--
-- Nothing about a cast can be read in 12.x (name, spell ID, times are all secret), only *when*
-- the UNIT_SPELLCAST_START event fired. Rouse is found by counting Ithraz's casts instead: he
-- runs a fixed cycle of 7 on Mythic, and Rouse is the 5th (EncounterProgressBars' ordinals).
--
-- GUIDs and names are secret too, so a plate can't be recognised once it leaves the screen.
-- A plate keeps its number while it stays on screen; one that comes back is only recovered if
-- someone is still targeting it.

local ADDS_PER_WAVE = 10 -- 14 before the 2026-09-15 nerf
local FIRST_CAST_OFFSET = 4.5 -- seconds from Rouse cast start to Broodling 1's first cast
local CAST_SPACING = 1.0
local CAST_TOLERANCE = 0.3    -- Spawns of Vexhul cast on the x.0 offsets, 0.5s off the lattice
local WAVE_WINDOW = 25        -- a cast this long after the anchor can't belong to that wave

local ITHRAZ_UNIT = "boss2"
local ITHRAZ_CYCLE = 7
local ROUSE_ORDINAL = 5       -- boss2 casts 5, 12, 19, 26, 33, 40 are Rouse the Brood

-- Rouse cast start per wave, seconds after ENCOUNTER_START (spread up to 1.3s in later waves).
-- Only used when no Rouse has been counted, e.g. joining mid-fight.
local WAVE_ROUSE_TIMES = {33.0, 94.0, 188.0, 249.0, 343.0, 404.0}
TFIA.WAVE_ROUSE_TIMES = WAVE_ROUSE_TIMES

-- Seconds from Rouse cast start to the first cast of pair `number` (Broodling 2n-1).
function TFIA:PairCastOffset(number)
    return FIRST_CAST_OFFSET + (number - 1) * 2 * CAST_SPACING
end

local plateFrame = CreateFrame("Frame", nil, UIParent)
local boxesByUnit = {}      -- nameplate unit token -> box frame
local numbersByHandle = {}  -- "target" / "focus" / "raid5target" -> number the add had when its plate was removed
local waveAnchor            -- GetTime() of the current wave's Rouse cast start
local ithrazCastCount = 0
local active = false

function TFIA:ResetNumbering()
    wipe(numbersByHandle)
    waveAnchor = nil
    ithrazCastCount = 0
end

-- Unit tokens that stay valid while a nameplate is gone.
local function IterateHandles(callback)
    callback("target")
    callback("focus")
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do
        callback(prefix .. i .. "target")
    end
end

local function IsTrackedUnit(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return false end
    if not UnitCanAttack("player", unit) then return false end
    return UnitLevel(unit) >= 0 -- "??" level: a boss. UnitIsUnit against bossN is restricted in combat.
end

-- UnitIsUnit is restricted on enemies in combat (12.x); a raise or a secret result counts as "no".
local function SameUnit(a, b)
    local ok, same = pcall(function() return UnitIsUnit(a, b) == true end)
    return ok and same
end

local function RememberNumberByHandle(unit, number)
    IterateHandles(function(handle)
        if UnitExists(handle) and SameUnit(unit, handle) then
            numbersByHandle[handle] = number
        end
    end)
end

local function RecallNumberByHandle(unit)
    local found
    IterateHandles(function(handle)
        local number = numbersByHandle[handle]
        if number and not found and UnitExists(handle) and SameUnit(unit, handle) then
            found = number
            numbersByHandle[handle] = nil
        end
    end)
    return found
end

local function OnIthrazCastStart()
    ithrazCastCount = ithrazCastCount + 1
    if ithrazCastCount % ITHRAZ_CYCLE ~= ROUSE_ORDINAL % ITHRAZ_CYCLE then return end
    waveAnchor = GetTime()
    if TFIA.db.debug then
        TFIA:Print(string.format("Rouse the Brood (Ithraz cast %d) at %.1fs into the pull",
            ithrazCastCount, waveAnchor - (TFIA.pullTime or waveAnchor)))
    end
    local wave = (ithrazCastCount - ROUSE_ORDINAL) / ITHRAZ_CYCLE + 1
    TFIA:OnRouse(wave, waveAnchor)
end

-- Test mode on trash has no Ithraz to count; the real pull always does.
local function IsTrashTest()
    return TFIA.db.testMode and not TFIA.inEncounter
end

local function GetAnchor(castStart)
    if waveAnchor and castStart - waveAnchor < WAVE_WINDOW then
        return waveAnchor
    end
    if IsTrashTest() then
        -- No boss on trash: the first cast seen starts a wave.
        waveAnchor = castStart - FIRST_CAST_OFFSET
        return waveAnchor
    end
    if TFIA.pullTime then
        for _, rouseTime in ipairs(WAVE_ROUSE_TIMES) do
            local anchor = TFIA.pullTime + rouseTime
            if castStart >= anchor and castStart - anchor < WAVE_WINDOW then
                return anchor
            end
        end
    end
    return nil
end

-- nil means the cast is off the lattice (a re-cast, or not a Broodling) or outside any wave.
local function NumberForCast(castStart)
    local anchor = GetAnchor(castStart)
    if not anchor then return nil end
    local offset = castStart - anchor - FIRST_CAST_OFFSET
    local index = math.floor(offset / CAST_SPACING + 0.5)
    if index < 0 or index >= ADDS_PER_WAVE then return nil end
    if not IsTrashTest() and math.abs(offset - index * CAST_SPACING) > CAST_TOLERANCE then return nil end
    return math.ceil((index + 1) / 2)
end

local function CreateBox()
    local box = CreateFrame("Frame", nil, plateFrame)
    box:SetFrameStrata("HIGH")
    box.Border = box:CreateTexture(nil, "BACKGROUND")
    box.Border:SetColorTexture(0, 0, 0, 1)
    box.Border:SetPoint("TOPLEFT", box, "TOPLEFT", -1, 1)
    box.Border:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 1, -1)
    box.Background = box:CreateTexture(nil, "ARTWORK")
    box.Background:SetAllPoints()
    box.Number = box:CreateFontString(nil, "OVERLAY")
    box.Number:SetPoint("CENTER")
    return box
end

local function GetBox(unit)
    if not boxesByUnit[unit] then
        boxesByUnit[unit] = CreateBox()
    end
    return boxesByUnit[unit]
end

local function StyleBox(box)
    local db = TFIA.db
    local colors = db.colors
    local isMine = box.number == db.myNumber
    box:SetSize(db.boxSize, db.boxSize)
    box.Background:SetColorTexture(unpack(isMine and colors.myBox or colors.box))
    box.Number:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
    box.Number:SetTextColor(unpack(isMine and colors.myText or colors.text))
    box.Number:SetText(box.number)
    box:SetShown(db.showAll or isMine)
end

-- Constant size on purpose: the plate's own scale changes with distance and is not
-- applied yet when NAME_PLATE_UNIT_ADDED fires, so copying it gives inconsistent boxes.
local function AttachBox(box, plate)
    box:ClearAllPoints()
    box:SetPoint("BOTTOM", plate, "TOP", 0, TFIA.db.yOffset)
end

local function ShowBox(unit, plate, number)
    local box = GetBox(unit)
    box.number = number
    AttachBox(box, plate)
    StyleBox(box)
end

local function OnNameplateCastStart(unit)
    local box = boxesByUnit[unit]
    if box and box.number then return end -- keeps its number while on screen
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or not IsTrackedUnit(unit) then return end
    local castStart = GetTime()
    local number = NumberForCast(castStart)
    if TFIA.db.debug then
        local offset = waveAnchor and string.format("%.2f", castStart - waveAnchor) or "none"
        TFIA:Print(string.format("%s level %s cast at Rouse+%s -> %s", unit, tostring(UnitLevel(unit)), offset, tostring(number or "ignored")))
    end
    if number then
        ShowBox(unit, plate, number)
    end
end

local function OnPlateAdded(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or not IsTrackedUnit(unit) then return end
    local recalled = RecallNumberByHandle(unit)
    if recalled then
        ShowBox(unit, plate, recalled)
    end
end

local function OnPlateRemoved(unit)
    local box = boxesByUnit[unit]
    if not box or not box.number then return end
    if TFIA.db.debug then
        local offset = waveAnchor and string.format("%.2f", GetTime() - waveAnchor) or "none"
        TFIA:Print(string.format("%s (#%d) removed at Rouse+%s", unit, box.number, offset))
    end
    RememberNumberByHandle(unit, box.number)
    box:Hide()
    box.number = nil
end

local function HideAllBoxes()
    for _, box in pairs(boxesByUnit) do
        box:Hide()
        box.number = nil
    end
end

-- Re-style every live box, e.g. after a settings change.
function TFIA:RefreshNameplates()
    if not active then return end
    for unit, box in pairs(boxesByUnit) do
        local plate = box.number and C_NamePlate.GetNamePlateForUnit(unit)
        if plate and IsTrackedUnit(unit) then
            AttachBox(box, plate)
            StyleBox(box)
        else
            OnPlateRemoved(unit)
        end
    end
end

function TFIA:StartNameplates()
    if active then return end
    active = true
    plateFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    plateFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    -- Unfiltered: RegisterUnitEvent cannot take nameplate tokens.
    plateFrame:RegisterEvent("UNIT_SPELLCAST_START")
    plateFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    plateFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    plateFrame:RegisterEvent("UNIT_TARGET")
    -- Pick up plates that were already on screen.
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if plate.namePlateUnitToken then
            OnPlateAdded(plate.namePlateUnitToken)
        end
    end
end

function TFIA:StopNameplates()
    if not active then return end
    active = false
    plateFrame:UnregisterAllEvents()
    HideAllBoxes()
end

plateFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        OnPlateAdded(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        OnPlateRemoved(unit)
    elseif event == "UNIT_SPELLCAST_START" then
        if unit:find("^nameplate%d+$") then
            OnNameplateCastStart(unit)
        elseif unit == ITHRAZ_UNIT then
            OnIthrazCastStart()
        end
    -- A handle whose owner retargeted no longer points at the add we remembered.
    elseif event == "PLAYER_TARGET_CHANGED" then
        numbersByHandle.target = nil
    elseif event == "PLAYER_FOCUS_CHANGED" then
        numbersByHandle.focus = nil
    elseif event == "UNIT_TARGET" then
        numbersByHandle[unit .. "target"] = nil
    end
end)
