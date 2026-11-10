-- tests/boot.lua
-- Boots the whole addon in the perl-infinity offline WoW harness (referenced in place,
-- not copied) and walks the real flows: first open, a move with playback, takeoff and
-- landing, auto-open off, /reload, and a practice board.
--   luajit tests/boot.lua            (PI_HARNESS=/path/to/init.lua to override)

local HARNESS = os.getenv("PI_HARNESS") or (os.getenv("HOME") .. "/git/perl-infinity/tests/harness/init.lua")
local Harness = dofile(HARNESS)

local failures, passes = 0, 0
local function check(cond, what)
  if cond then
    passes = passes + 1
  else
    failures = failures + 1
    print("FAIL " .. what)
  end
end

local function problems(h, where)
  local list = h:problems()
  for _, p in ipairs(list) do print("PROBLEM (" .. where .. ") " .. p) end
  check(#list == 0, where .. ": no harness problems")
  h:clearProblems()
end

local function boot(saved, isReload)
  local h = Harness.new({ mode = "strict", addonName = "Skyhex" })
  h.env.TakeTaxiNode = h.env.TakeTaxiNode or function() end
  h:loadToc("Skyhex/Skyhex.toc")
  h:login(saved, isReload)
  return h
end

local function visible(h, obj) return h.widgets.isVisible(obj) end

-- 1. first login: hidden until asked, then asks for a starting level
local h = boot()
local ns = h.addon.ns
local env = h.env
local frame = env.SkyhexFrame
check(frame ~= nil, "SkyhexFrame exists")
check(not visible(h, frame), "window starts hidden")
env.SlashCmdList.SKYHEX("")
h:advance(0.1)
check(visible(h, frame), "/skyhex opens the window")
local window = ns.Window
check(window:OverlayShown(), "first open asks for a starting level")
check(window.overlay.title:GetText() == "Pick a starting level", "level picker title")
h.widgets.callScript(window.overlay.buttons[1], "OnClick", "LeftButton")
h:advance(0.1)
check(not window:OverlayShown(), "picking level 1 starts a run")
check(env.SkyhexDB.run ~= nil and env.SkyhexDB.run.level == 1, "run saved at level 1")
local shownTiles = 0
for _, t in pairs(window.board.tiles) do if visible(h, t) then shownTiles = shownTiles + 1 end end
check(shownTiles == 85, "85 tiles on the board (got " .. shownTiles .. ")")
problems(h, "first open")

-- 2. hover picks a triad under the cursor; a click makes a move that plays back
local board = window.board
local game = board.game
local hint = ns.Game.hint(game)
local t = ns.Grid.triads[hint.index]
local left, top = board.frame:GetLeft(), board.frame:GetTop()
local scale = board.frame:GetEffectiveScale()
env.GetCursorPosition = function()
  return (left + t.x * board.size) * scale, (top - t.y * board.size) * scale
end
h.widgets.callScript(board.frame, "OnEnter")
h:frame()
check(board.selection and board.selection.kind == "triad" and board.selection.index == hint.index,
  "hover selects the triad under the cursor")
h.widgets.callScript(board.frame, "OnMouseDown", hint.dir == 1 and "LeftButton" or "RightButton")
check(game.moves == 1, "click made a move")
check(board.busy, "playback running")
h:advance(3, 1 / 60)
check(not board.busy, "playback finished")
check(game.score > 0, "the hinted move scored")
for cell = 1, ns.Grid.N do
  local tile = board.cellTile[cell]
  if not tile or tile.pieceId ~= game.board[cell].id then
    check(false, "tile at cell " .. cell .. " matches the game")
    break
  end
end
check(env.SkyhexDB.run.moves == 1, "move saved")

-- a bomb that drops in shakes side to side and rings, then settles on its cell
game.bombPending = 1
local mv2 = ns.Game.hint(game)
ns.Core.OnClick(mv2, mv2.dir == 1 and "LeftButton" or "RightButton")
local sawRing, lo, hi = false, math.huge, -math.huge
for _ = 1, 300 do
  h:advance(1 / 60, 1 / 60)
  for _, tile in pairs(board.tiles) do
    if visible(h, tile.alert) then
      sawRing = true
      lo, hi = math.min(lo, tile.ux), math.max(hi, tile.ux)
    end
  end
  if not board.busy then break end
end
check(not board.busy, "bomb playback finished")
check(sawRing, "a new bomb sends out a ring as it lands")
check(hi - lo > 0.1, "a new bomb shakes (moved " .. string.format("%.3f", hi - lo) .. " hexes)")
local ringsLeft = 0
for _, tile in pairs(board.tiles) do if visible(h, tile.alert) then ringsLeft = ringsLeft + 1 end end
check(ringsLeft == 0, "no ring is left behind")

-- the settings page: gem style redraws every tile
check(env.Settings.GetSetting("Skyhex_gems") ~= nil, "settings page registered")
local gcell
for cell = 1, ns.Grid.N do
  if game.board[cell].kind == "gem" then gcell = cell break end
end
local gcolor = game.board[gcell].color
check(board.cellTile[gcell].icon:GetTexture() == ns.Media.GEM_SETS.modern[gcolor].icon, "modern gems by default")
env.Settings.SetValue("Skyhex_gems", "classic")
check(board.cellTile[gcell].icon:GetTexture() == ns.Media.GEM_SETS.classic[gcolor].icon, "classic gems redraw the board")
check(env.SkyhexDB.gems == "classic", "gem style saved")
env.SlashCmdList.SKYHEX("gems modern")
check(board.cellTile[gcell].icon:GetTexture() == ns.Media.GEM_SETS.modern[gcolor].icon, "/skyhex gems modern")
env.Settings.SetValue("Skyhex_scale", 1.2)
check(math.abs(frame:GetScale() - 1.2) < 1e-6, "window size setting applies")
env.Settings.SetValue("Skyhex_scale", 1)

-- every tile sits exactly on its cell, and stays there while scaled for an effect
-- harness rects are in the frame's own scaled units; convert to screen units
local function centerOf(obj)
  local r, e = h.widgets.rect(obj), h.widgets.effectiveScale(obj)
  return (r[1] + r[3] / 2) * e, (r[2] + r[4] / 2) * e
end
local function cellCenter(cell)
  local c = ns.Grid.cells[cell]
  return left + c.x * board.size, top - c.y * board.size
end
local worst = 0
for cell = 1, ns.Grid.N do
  local x, y = centerOf(board.cellTile[cell])
  local cx, cy = cellCenter(cell)
  worst = math.max(worst, math.abs(x - cx), math.abs(y - cy))
end
check(worst < 0.01, "tiles are centered on their cells (off by " .. worst .. ")")
local probe = board.cellTile[40]
board:SetTileScale(probe, 1.4)
local sx, sy = centerOf(probe)
local cx, cy = cellCenter(40)
check(math.abs(sx - cx) < 0.01 and math.abs(sy - cy) < 0.01, "a scaled tile stays centered on its cell")
board:SetTileScale(probe, 1)
problems(h, "move")

-- 3. takeoff opens the board; landing keeps it open unless "Hide when you land" is on
env.SlashCmdList.SKYHEX("")
check(not visible(h, frame), "/skyhex closes the window")
local player = h.world:get("player")
local function fly()
  player.onTaxi = true
  h:fire("PLAYER_CONTROL_LOST")
  h:advance(0.5)
end
local function land()
  player.onTaxi = false
  h:fire("PLAYER_CONTROL_GAINED")
  h:advance(1.5)
end
fly()
check(visible(h, frame), "taking a flight opens the board")
check(env.SkyhexDB.records.flights == 1, "flight counted")
land()
check(visible(h, frame), "the board stays open after landing by default")
env.Settings.SetValue("Skyhex_hideOnLand", true)
fly()
land()
check(env.SkyhexDB.records.flights == 2, "second flight counted")
check(not visible(h, frame), "with hide on land, landing hides the board")
env.Settings.SetValue("Skyhex_hideOnLand", false)
problems(h, "flight")

-- 4. auto-open off
env.SlashCmdList.SKYHEX("auto off")
player.onTaxi = true
h:fire("PLAYER_CONTROL_LOST")
h:advance(1.5)
check(not visible(h, frame), "with auto off, a flight leaves the board closed")
player.onTaxi = false
h:advance(1.5)
env.SlashCmdList.SKYHEX("auto on")

-- 5. /reload keeps the board exactly
local cellsBefore = env.SkyhexDB.run.cells
local scoreBefore = env.SkyhexDB.run.score
local h2 = h:reload()
local ns2 = h2.addon.ns
h2.env.SlashCmdList.SKYHEX("")
h2:advance(0.1)
local g2 = ns2.Window.board.game
check(g2 ~= nil, "reloaded run is shown")
check(ns2.Codec.encode(g2).cells == cellsBefore, "reloaded board is identical")
check(g2.score == scoreBefore, "reloaded score is identical")
problems(h2, "reload")

-- 6. reload while flying reopens the board
local saved = h2:saveVariables()
local SV = dofile((HARNESS:gsub("init%.lua$", "savedvars.lua")))
local h3 = Harness.new({ mode = "strict", addonName = "Skyhex" })
h3.env.TakeTaxiNode = function() end
h3:loadToc("Skyhex/Skyhex.toc")
h3.world:get("player").onTaxi = true
h3:login(SV.parse(saved), true)
h3:advance(0.5)
check(visible(h3, h3.env.SkyhexFrame), "a /reload mid-flight reopens the board")
problems(h3, "reload mid-flight")

-- 7. practice boards don't touch the run
local env2 = h2.env
local runCells = env2.SkyhexDB.run.cells
env2.SlashCmdList.SKYHEX("try pearl")
h2:advance(0.1)
local pg = ns2.Window.board.game
check(pg ~= g2, "practice shows its own board")
local _, mv = ns2.Scenes.build.pearl(1)
ns2.Core.OnClick(mv, "LeftButton")
h2:advance(3, 1 / 60)
check(pg.stats.pearls == 1, "the practice move made a black pearl")
check(env2.SkyhexDB.run.cells == runCells, "practice left the saved run alone")
env2.SlashCmdList.SKYHEX("")
env2.SlashCmdList.SKYHEX("")
check(ns2.Window.board.game == g2, "reopening goes back to the real run")
problems(h2, "practice")

-- 8. every practice board and a run to its end
for _, name in ipairs(ns2.Scenes.order) do
  env2.SlashCmdList.SKYHEX("try " .. name)
  local _, m = ns2.Scenes.build[name](1)
  ns2.Core.OnClick(m, "LeftButton")
  h2:advance(3, 1 / 60)
end
check(ns2.Window:OverlayShown(), "the win practice ends with an overlay")
problems(h2, "all practice boards")

print(string.format("boot: %d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
