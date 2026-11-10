-- UI/Media.lua
-- Icons, colors, textures and sounds. Every icon is a fileID that Forever's own data
-- ships (checked against the client's CASC root, see notes/research/forever-api.md
-- section 3).

local _, ns = ...
local Media = {}
ns.Media = Media

local PATH = "Interface\\AddOns\\Skyhex\\Media\\"
Media.HEX_MASK = PATH .. "HexMask"
Media.HEX_BASE = PATH .. "HexBase"
Media.HEX_EDGE = PATH .. "HexEdge"
Media.HEX_GLOW = PATH .. "HexGlow"
Media.STAR_BADGE = PATH .. "StarBadge"
Media.PIVOT = PATH .. "Pivot"
Media.SPARK = PATH .. "Spark"
Media.FONT = "Fonts\\FRIZQT__.TTF"

-- Two gem styles, picked in Options > AddOns > Skyhex. Colors 1 to 5 are in play from
-- level 1, 6 from level 4, 7 from level 6; the last one sits closest to its neighbors.
-- icon: fileID; rgb: the hex rim; tint: multiplies the icon; desat: draw it in grays
Media.GEM_SETS = {
  -- one matched set of cut gems (inv_jewelcrafting_80_cutgem02_*), so color tells them apart
  modern = {
    { name = "Red", icon = 1990988, rgb = { 0.86, 0.16, 0.16 }, tint = { 1, 0.72, 0.72 } },
    { name = "Yellow", icon = 1990989, rgb = { 0.96, 0.78, 0.16 } },
    { name = "Green", icon = 1990985, rgb = { 0.30, 0.72, 0.20 }, tint = { 0.7, 1, 0.7 } }, -- pulled off lime
    { name = "Blue", icon = 1990984, rgb = { 0.18, 0.52, 0.92 } },
    { name = "Purple", icon = 1990987, rgb = { 0.66, 0.30, 0.84 } },
    { name = "Silver", icon = 1990984, rgb = { 0.80, 0.80, 0.84 }, desat = true },          -- the blue gem in grays
    { name = "Orange", icon = 1990986, rgb = { 0.95, 0.50, 0.12 } },
  },
  -- vanilla gem icons; each color also has its own outline, which helps colorblind players
  classic = {
    -- inv_misc_gem_ruby_01, heart. The art is pink-red; the tint pulls it away from amethyst.
    { name = "Ruby", icon = 134128, rgb = { 0.86, 0.16, 0.20 }, tint = { 1, 0.78, 0.6 } },
    { name = "Topaz", icon = 134136, rgb = { 0.96, 0.78, 0.16 } },     -- inv_misc_gem_topaz_02, crown
    { name = "Emerald", icon = 134105, rgb = { 0.24, 0.70, 0.30 } },   -- inv_misc_gem_emerald_02, square
    { name = "Moonstone", icon = 134087, rgb = { 0.16, 0.70, 0.78 } }, -- inv_misc_gem_crystal_01, columns
    { name = "Amethyst", icon = 134075, rgb = { 0.62, 0.32, 0.86 } },  -- inv_misc_gem_amethyst_02, kite
    { name = "Pearl", icon = 134122, rgb = { 0.92, 0.91, 0.86 } },     -- inv_misc_gem_pearl_03, sphere
    { name = "Opal", icon = 134116, rgb = { 0.93, 0.48, 0.17 } },      -- inv_misc_gem_opal_01, chunk
  },
}
Media.GEM_STYLES = { "modern", "classic" }
Media.style = "modern"
Media.GEMS = Media.GEM_SETS.modern

function Media.SetStyle(style)
  if not Media.GEM_SETS[style] then style = "modern" end
  Media.style = style
  Media.GEMS = Media.GEM_SETS[style]
  return style
end

-- spell_priest_divinestar_holy in grays: a silver six-pointed star
Media.STAR = { icon = 608954, rgb = { 0.78, 0.80, 0.86 }, desat = true }
Media.BLACK_PEARL = { icon = 970844, rgb = { 0.30, 0.18, 0.42 } }    -- inv_fishing_innards_pearlblack
Media.BOMB_RGB = { 1.00, 0.22, 0.18 }
Media.BONUS_RGB = { 1.00, 0.95, 0.80 }

-- PlaySound kit IDs that Forever's own UI plays (research section 5)
local SOUNDS = {
  turn = 856,          -- IG_MAINMENU_OPTION_CHECKBOX_ON
  clear = 1204,        -- PUT_DOWN_GEMS
  star = 878,          -- IG_QUEST_LIST_COMPLETE
  pearl = 10590,       -- JEWEL_CRAFTING_FINALIZE
  tick = 25477,        -- UI_BATTLEGROUND_COUNTDOWN_TIMER
  lose = 25478,        -- UI_BATTLEGROUND_COUNTDOWN_FINISHED
  bomb = 12867,        -- ALARM_CLOCK_WARNING_2, a new bomb lands
  level = 8459,        -- PVP_THROUGH_QUEUE
  win = 8960,          -- READY_CHECK
}

local last = {}
function Media.play(name)
  local db = ns.db
  if db and db.sound == false then return end
  local id = SOUNDS[name]
  if not id then return end
  local now = GetTime()
  if last[name] and now - last[name] < 0.09 then return end
  last[name] = now
  PlaySound(id, "SFX")
end

function Media.number(n)
  n = math.floor(n or 0)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  local s = tostring(n)
  while true do
    local k
    s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    if k == 0 then return s end
  end
end
