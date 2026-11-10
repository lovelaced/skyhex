-- Options.lua
-- The Skyhex page in the game's Options > AddOns panel. Each setting reads and writes
-- SkyhexDB directly, and the slash commands change the same fields.

local _, ns = ...
local Options = {}
ns.Options = Options

local GEM_LABELS = {
  modern = { "Modern gems", "Glossy cut gems that fill the whole tile. Color tells them apart." },
  classic = { "Classic gems", "The original World of Warcraft gem icons. Each color has its own shape." },
}

-- hooks: onGems(style), onScale(scale)
function Options.Register(db, hooks)
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
  local category = Settings.RegisterVerticalLayoutCategory("Skyhex")
  Options.category = category
  local VT = Settings.VarType

  local function setting(key, varType, name, default)
    return Settings.RegisterAddOnSetting(category, "Skyhex_" .. key, key, db, varType, name, default)
  end

  Settings.CreateCheckbox(category, setting("auto", VT.Boolean, "Open when you take a flight", true),
    "The board opens by itself as your flight takes off.")
  Settings.CreateCheckbox(category, setting("hideOnLand", VT.Boolean, "Hide when you land", false),
    "Put the board away when your flight lands. Your board is saved either way.")

  local gems = setting("gems", VT.String, "Gem style", "modern")
  Settings.CreateDropdown(category, gems, function()
    local c = Settings.CreateControlTextContainer()
    for _, style in ipairs(ns.Media.GEM_STYLES) do
      c:Add(style, GEM_LABELS[style][1], GEM_LABELS[style][2])
    end
    return c:GetData()
  end, "How the gems on the board look.")
  gems:SetValueChangedCallback(function(_, value) hooks.onGems(value) end)

  Settings.CreateCheckbox(category, setting("sound", VT.Boolean, "Sound effects", true),
    "Turns, clears, bomb ticks and level-ups.")

  local scale = setting("scale", VT.Number, "Window size", 1)
  local opts = Settings.CreateSliderOptions(0.7, 1.5, 0.05)
  if opts.SetLabelFormatter and MinimalSliderWithSteppersMixin then
    opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
      return math.floor(v * 100 + 0.5) .. "%"
    end)
  end
  Settings.CreateSlider(category, scale, opts, "Make the board window bigger or smaller.")
  scale:SetValueChangedCallback(function(_, value) hooks.onScale(value) end)

  Settings.RegisterAddOnCategory(category)
end

function Options.Open()
  if not (Options.category and Settings and Settings.OpenToCategory) then return false end
  Settings.OpenToCategory(Options.category:GetID())
  return true
end
