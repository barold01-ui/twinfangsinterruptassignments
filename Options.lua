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

-- `values` is a list of strings; each is both the stored value and the label.
local function AddDropdown(key, name, values, tooltip)
    local setting = RegisterSetting(key, Settings.VarType.String, name)
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        for _, value in ipairs(values) do
            container:Add(value, value)
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
    AddSlider("myNumber", "My number", 1, 5, 1, "The Broodling pair you are assigned to interrupt.")
    AddDropdown("side", "My side", {"Left", "Right"}, "Which side of the room you kick on.")
    AddSlider("boxSize", "Box size", 10, 100, 1, "Size of the number box.")
    AddSlider("fontSize", "Font size", 8, 60, 1, "Size of the number text.")
    AddSlider("yOffset", "Y offset", -100, 100, 1, "Vertical distance from the top of the nameplate.")

    AddHeader("Interrupt Reminder")
    AddCheckbox("reminderEnabled", "Show reminder", "Count down the 5s before your pair's first cast.")
    AddDropdown("reminderSound", "Sound", LSM:List("sound"), "Played when the countdown ends. /tfia remind to preview.")
    AddSlider("reminderSize", "Reminder size", 16, 128, 1, "Icon size; the text scales with it.")
    AddSlider("reminderX", "Reminder X", -1000, 1000, 1, "Horizontal offset from the centre of the screen.")
    AddSlider("reminderY", "Reminder Y", -600, 600, 1, "Vertical offset from the centre of the screen.")

    AddHeader("Raid Leader")
    AddButton("Assignments", "Open", "Assign players to each kick and broadcast them to the group. Leader and assistants only.",
        function() TFIA:OpenAssignments() end, TFIA.CanManageAssignments, {"GROUP_ROSTER_UPDATE"})
    AddButton("Version check", "Check", "Ask everyone in the group which version of the addon they have.",
        function() TFIA:StartVersionCheck() end)

    Settings.RegisterAddOnCategory(category)
end

function TFIA:OpenOptions()
    Settings.OpenToCategory(category:GetID())
end
