local _, TFIA = ...
local LSM = LibStub("LibSharedMedia-3.0")

local category

local function OnSettingChanged()
    TFIA:UpdateActiveState()
    TFIA:RefreshNameplates()
    TFIA:RefreshReminder()
end

local function RegisterSetting(key, varType, name)
    return Settings.RegisterProxySetting(category, "TFIA_" .. key, varType, name, TFIA.defaults[key],
        function() return TFIA.db[key] end,
        function(value) TFIA.db[key] = value; OnSettingChanged() end)
end

local function AddHeader(name)
    local layout = SettingsPanel:GetLayout(category)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
end

local function AddCheckbox(key, name, tooltip)
    local setting = RegisterSetting(key, Settings.VarType.Boolean, name)
    Settings.CreateCheckbox(category, setting, tooltip)
end

-- Settings rows are pooled across every addon's panel, so a row keeps its value box but only
-- shows it while it belongs to one of our sliders.
local valueBoxes = {} -- slider row frame -> its edit box

local function GetValueBox(row)
    local box = valueBoxes[row]
    if not box then
        box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetSize(44, 20)
        box:SetAutoFocus(false)
        box:SetJustifyH("CENTER")
        -- Where the slider's own value label would sit.
        box:SetPoint("LEFT", row.SliderWithSteppers.Slider, "RIGHT", 30, 0)
        valueBoxes[row] = box
    end
    return box
end

-- Replaces the slider's value label with a box you can type an exact value into.
local function AddValueBox(initializer, setting, minValue, maxValue, step)
    local valueChanged = MinimalSliderWithSteppersMixin.Event.OnValueChanged

    local function Snap(value)
        return Clamp(minValue + math.floor((value - minValue) / step + 0.5) * step, minValue, maxValue)
    end
    local function ShowValue(box)
        box:SetText(tostring(Snap(setting:GetValue())))
    end
    -- Bad input just puts the current value back.
    local function Commit(box)
        local value = tonumber(box:GetText())
        if value then
            setting:SetValue(Snap(value))
        end
        ShowValue(box)
    end

    local baseInitFrame, baseResetter = initializer.InitFrame, initializer.Resetter
    function initializer:InitFrame(row)
        baseInitFrame(self, row)
        local box = GetValueBox(row)
        box:SetScript("OnEnterPressed", box.ClearFocus)
        box:SetScript("OnEscapePressed", function()
            ShowValue(box)
            box:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", Commit)
        row.SliderWithSteppers.RightText:Hide()
        row.SliderWithSteppers:RegisterCallback(valueChanged, function()
            if not box:HasFocus() then
                ShowValue(box)
            end
        end, box)
        ShowValue(box)
        box:Show()
    end
    function initializer:Resetter(row)
        local box = valueBoxes[row]
        row.SliderWithSteppers:UnregisterCallback(valueChanged, box)
        box:ClearFocus()
        box:Hide()
        baseResetter(self, row)
    end
end

local function AddSlider(key, name, minValue, maxValue, step, tooltip)
    local setting = RegisterSetting(key, Settings.VarType.Number, name)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    local initializer = Settings.CreateSlider(category, setting, options, tooltip)
    AddValueBox(initializer, setting, minValue, maxValue, step)
end

-- `options` is a list of {value, label}; a plain string is both value and label.
local function AddDropdown(key, name, varType, options, tooltip)
    local setting = RegisterSetting(key, varType, name)
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        for _, option in ipairs(options) do
            if type(option) == "table" then
                container:Add(option[1], option[2])
            else
                container:Add(option, option)
            end
        end
        return container:GetData()
    end
    Settings.CreateDropdown(category, setting, GetOptions, tooltip)
end

-- `enabledPredicate` greys the button out; it is re-checked on each event in `enabledEvents`.
local function AddButton(name, buttonText, tooltip, onClick, enabledPredicate, enabledEvents)
    local initializer = CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true)
    if enabledPredicate then
        initializer:AddModifyPredicate(enabledPredicate)
        for _, event in ipairs(enabledEvents) do
            initializer:AddEvaluateStateFrameEvent(event)
        end
    end
    local layout = SettingsPanel:GetLayout(category)
    layout:AddInitializer(initializer)
end

-- The Settings API has no colour picker, so a button row opens Blizzard's and gets a swatch.
-- Rows are pooled like the slider rows, so the swatch is only shown while the row is ours.
local swatches = {} -- button row frame -> its colour swatch

local function GetSwatch(row)
    local swatch = swatches[row]
    if not swatch then
        swatch = CreateFrame("Frame", nil, row)
        swatch:SetSize(20, 20)
        swatch:SetPoint("LEFT", row.Button, "RIGHT", 10, 0)
        swatch.Border = swatch:CreateTexture(nil, "BACKGROUND")
        swatch.Border:SetColorTexture(0, 0, 0, 1)
        swatch.Border:SetPoint("TOPLEFT", -1, 1)
        swatch.Border:SetPoint("BOTTOMRIGHT", 1, -1)
        swatch.Color = swatch:CreateTexture(nil, "ARTWORK")
        swatch.Color:SetAllPoints()
        swatches[row] = swatch
    end
    return swatch
end

-- Edits `TFIA.db.colors[colorKey]` live; Cancel puts the old colour back.
local function OpenColorPicker(colorKey, onChange)
    local color = TFIA.db.colors[colorKey]
    local previous = {color[1], color[2], color[3]}
    local function Apply(r, g, b)
        color[1], color[2], color[3] = r, g, b
        onChange()
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = color[1], g = color[2], b = color[3],
        swatchFunc = function() Apply(ColorPickerFrame:GetColorRGB()) end,
        cancelFunc = function() Apply(unpack(previous)) end,
    })
end

local function AddColorPicker(colorKey, name, tooltip)
    local shownSwatch -- our row's swatch while the row is on screen
    local function ShowColor()
        if shownSwatch then
            shownSwatch.Color:SetColorTexture(unpack(TFIA.db.colors[colorKey]))
        end
    end
    local function OnClick()
        OpenColorPicker(colorKey, function()
            ShowColor()
            TFIA:RefreshNameplates()
        end)
    end

    local initializer = CreateSettingsButtonInitializer(name, "Pick", OnClick, tooltip, true)
    local baseInitFrame, baseResetter = initializer.InitFrame, initializer.Resetter
    function initializer:InitFrame(row)
        baseInitFrame(self, row)
        shownSwatch = GetSwatch(row)
        ShowColor()
        shownSwatch:Show()
    end
    function initializer:Resetter(row)
        shownSwatch = nil
        swatches[row]:Hide()
        baseResetter(self, row)
    end
    local layout = SettingsPanel:GetLayout(category)
    layout:AddInitializer(initializer)
end

-- Change a setting from outside the panel so an open panel updates live.
function TFIA:SetSetting(key, value)
    Settings.SetValue("TFIA_" .. key, value)
end

function TFIA:InitOptions()
    category = Settings.RegisterVerticalLayoutCategory("Twin Fangs Interrupts")

    AddCheckbox("enabled", "Enabled", "Show numbers above add nameplates during The Twin Fangs.")
    AddCheckbox("testMode", "Test mode", "Number every hostile nameplate anywhere, not just during the encounter.")
    AddCheckbox("showAll", "Show all numbers", "Off = only show the boxes for your own number.")
    AddDropdown("myNumber", "My number", Settings.VarType.Number,
        {{0, "None"}, {1, "1"}, {2, "2"}, {3, "3"}, {4, "4"}, {5, "5"}},
        "The Broodling pair you are assigned to interrupt. None = not assigned, no reminder.")
    AddDropdown("side", "My side", Settings.VarType.String, {"None", "Left", "Right"}, "Which side of the room you kick on.")
    AddSlider("boxSize", "Box size", 10, 100, 1, "Size of the number box.")
    AddSlider("fontSize", "Font size", 8, 60, 1, "Size of the number text.")
    AddSlider("yOffset", "Y offset", -100, 100, 1, "Vertical distance from the top of the nameplate.")
    AddColorPicker("myBox", "Assigned colour", "Colour of the box with your number. Default green is hex 00ff00.")
    AddColorPicker("box", "Non-assigned colour", "Colour of the boxes with other numbers. Default red is hex ff0000.")

    AddHeader("Interrupt Reminder")
    AddCheckbox("reminderEnabled", "Show reminder", "Count down the 5s before your pair's first cast.")
    -- Not a saved setting: the preview always starts locked after a reload.
    local unlock = Settings.RegisterProxySetting(category, "TFIA_reminderUnlocked", Settings.VarType.Boolean,
        "Unlock reminder", false,
        function() return TFIA.reminderUnlocked or false end,
        function(value) TFIA:SetReminderUnlocked(value) end)
    Settings.CreateCheckbox(category, unlock, "Show the reminder so you can drag it into place. Right-click it to lock. /tfia unlock does the same.")
    AddDropdown("reminderSound", "Sound", Settings.VarType.String, LSM:List("sound"), "Played when the countdown ends. /tfia remind to preview.")
    AddSlider("reminderSize", "Reminder size", 16, 128, 1, "Icon size; the text scales with it.")
    AddSlider("reminderX", "Reminder X", -1000, 1000, 1, "Horizontal offset from the centre of the screen.")
    AddSlider("reminderY", "Reminder Y", -600, 600, 1, "Vertical offset from the centre of the screen.")

    AddHeader("Raid Leader")
    AddButton("Assignments", "Open", "See who kicks what. The leader and assistants can edit and broadcast the list.",
        function() TFIA:OpenAssignments() end)
    AddButton("Version check", "Check", "Ask everyone in the group which version of the addon they have.",
        function() TFIA:StartVersionCheck() end)

    Settings.RegisterAddOnCategory(category)
end

function TFIA:OpenOptions()
    Settings.OpenToCategory(category:GetID())
end
