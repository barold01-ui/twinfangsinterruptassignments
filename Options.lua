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

local function AddSlider(key, name, minValue, maxValue, step, tooltip)
    local setting = RegisterSetting(key, Settings.VarType.Number, name)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
    Settings.CreateSlider(category, setting, options, tooltip)
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
