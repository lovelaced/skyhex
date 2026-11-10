-- luacheck config for Skyhex (run from the repo root: `make lint`)

stds.wow_lua = {
  read_globals = {
    table = { fields = { "wipe" } },
  },
}

std = "lua51+wow_lua"
max_line_length = 130
codes = true
-- 212: unused arguments (handlers keep WoW's signatures)
ignore = { "212" }
exclude_files = { "tools/out/**", ".release/**" }

files["Skyhex/**"] = {
  globals = {
    "SkyhexDB", "SLASH_SKYHEX1", "SlashCmdList",
    "Skyhex_OnAddonCompartmentClick", "Skyhex_OnAddonCompartmentEnter", "Skyhex_OnAddonCompartmentLeave",
  },
  read_globals = {
    "CreateFrame", "UIParent", "UISpecialFrames", "GameTooltip", "DEFAULT_CHAT_FRAME",
    "C_Timer", "GetTime", "time", "GetCursorPosition", "UnitOnTaxi", "TakeTaxiNode", "hooksecurefunc",
    "PlaySound", "BreakUpLargeNumbers", "tinsert", "unpack", "Settings", "MinimalSliderWithSteppersMixin",
  },
}

files["tests/**"] = { std = "luajit", globals = { "arg" }, max_line_length = false }
files["tools/**"] = { std = "luajit", globals = { "arg" }, max_line_length = false }
