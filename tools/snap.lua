-- tools/snap.lua
-- Boots Skyhex in the perl-infinity harness, sets up a few window states, and dumps
-- what is visible (positions from the harness layout engine) for tools/snap.py to
-- composite with the real textures and icon renders.
--   luajit tools/snap.lua [outDir]

local outDir = arg[1] or "tools/out/snap"
local HARNESS = os.getenv("PI_HARNESS") or (os.getenv("HOME") .. "/git/perl-infinity/tests/harness/init.lua")
local Harness = dofile(HARNESS)
os.execute('mkdir -p "' .. outDir .. '"')

local h = Harness.new({ mode = "open", addonName = "Skyhex" })
h.env.TakeTaxiNode = function() end
h:loadToc("Skyhex/Skyhex.toc")
h:login()
local ns, env, W = h.addon.ns, h.env, h.widgets
local Game, Pieces, Grid = ns.Game, ns.Pieces, ns.Grid
local window = ns.Window
local board = window.board

local function rect(obj)
  local r = W.rect(obj)
  return r and string.format("%.1f %.1f %.1f %.1f", r[1], r[2], r[3], r[4]) or "nil"
end

local function color(fs)
  local r, g, b = fs:GetTextColor()
  return string.format("%.3f,%.3f,%.3f", r or 1, g or 1, b or 1)
end

local function text(out, fs)
  if not W.isVisible(fs) then return end
  local s = fs:GetText()
  if not s or s == "" then return end
  local st = W.state[fs]
  out[#out + 1] = string.format("text|%s|%d|%s|%s|%s", rect(fs), st.fontSize or 12, color(fs),
    st.justifyH or "CENTER", s:gsub("\n", "\\n"))
end

local function dump(name)
  h:advance(0.05)
  local out = { "window|" .. rect(window.frame) .. "|" .. rect(board.frame) }
  -- icon specs for the current gem style: look|key|fileID|rim rgb|tint rgb|desat
  local function spec(key, m)
    local t = m.tint or { 1, 1, 1 }
    out[#out + 1] = string.format("look|%s|%d|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%d", key, m.icon,
      m.rgb[1], m.rgb[2], m.rgb[3], t[1], t[2], t[3], m.desat and 1 or 0)
  end
  for i, m in ipairs(ns.Media.GEMS) do spec("gem" .. i, m) end
  spec("star", ns.Media.STAR)
  spec("pearl", ns.Media.BLACK_PEARL)
  for _, fs in ipairs({ window.title, window.score, window.best, window.level, window.combos, window.footer }) do
    text(out, fs)
  end
  for cell = 1, Grid.N do
    local t = board.cellTile[cell]
    if t and W.isVisible(t) then
      local lk = t.look
      out[#out + 1] = string.format("tile|%s|%s|%s|%s|%s|%s|%.2f", rect(t), lk.kind, tostring(lk.color or 0),
        tostring(lk.bonus and 1 or 0), tostring(lk.bomb or 0), tostring(lk.y or 0), t:GetAlpha())
    end
  end
  for _, hl in ipairs(board.hl) do
    if W.isVisible(hl) then
      local r, g, b = hl:GetVertexColor()
      out[#out + 1] = string.format("hl|%s|%.2f,%.2f,%.2f", rect(hl), r or 1, g or 1, b or 1)
    end
  end
  if W.isVisible(board.pivot) then out[#out + 1] = "pivot|" .. rect(board.pivot) end
  for _, t in pairs(board.tiles) do
    if W.isVisible(t) and W.isVisible(t.alert) then
      out[#out + 1] = string.format("alert|%s|%.2f", rect(t.alert), t.alert:GetAlpha())
    end
  end
  local o = window.overlay
  if W.isVisible(o) then
    out[#out + 1] = "overlay|" .. rect(o)
    text(out, o.title)
    text(out, o.body)
    for _, b in ipairs(o.buttons) do
      if W.isVisible(b) then out[#out + 1] = string.format("button|%s|%s", rect(b), b:GetText()) end
    end
  end
  local f = assert(io.open(outDir .. "/" .. name .. ".txt", "w"))
  f:write(table.concat(out, "\n"), "\n")
  f:close()
  print(outDir .. "/" .. name .. ".txt")
end

-- point the cursor at unit coordinates on the board and let hover run
local function hover(ux, uy)
  local left, top, scale = board.frame:GetLeft(), board.frame:GetTop(), board.frame:GetEffectiveScale()
  env.GetCursorPosition = function() return (left + ux * board.size) * scale, (top - uy * board.size) * scale end
  W.callScript(board.frame, "OnEnter")
  h:frame()
end

-- A: the level picker on first open
env.SlashCmdList.SKYHEX("")
dump("a-picker")

-- B: a level 5 run a few moves in, hovering a triad
W.callScript(window.overlay.buttons[3], "OnClick", "LeftButton")
local g = board.game
for _ = 1, 12 do
  local mv = Game.hint(g)
  ns.Core.OnClick(mv, mv.dir == 1 and "LeftButton" or "RightButton")
  h:advance(3, 1 / 30)
end
local t = Grid.triads[60]
hover(t.x + 0.1, t.y)
dump("b-play")

-- C: specials on the board, hovering the pearl
for _, spec in ipairs({
  { 4, 4, Pieces.pearl(2) }, { 7, 5, Pieces.star() }, { 2, 6, Pieces.bomb(1, 7) }, { 8, 3, Pieces.bomb(4, 2) },
}) do
  Game.place(g, Grid.id(spec[1], spec[2]), spec[3])
end
board:Sync(g)
ns.Core.Refresh()
local c = Grid.cells[Grid.id(4, 4)]
hover(c.x, c.y)
dump("c-specials")

-- E: the same board in classic gems
ns.Core.SetGemStyle("classic")
dump("e-classic")
ns.Core.SetGemStyle("modern")
W.callScript(board.frame, "OnLeave")

-- F: a new bomb mid-shake, its ring spreading
g.bombPending = 1
local mv = Game.hint(g)
ns.Core.OnClick(mv, "LeftButton")
for _ = 1, 300 do
  h:advance(1 / 60, 1 / 60)
  local caught
  for _, tile in pairs(board.tiles) do
    if W.isVisible(tile.alert) and tile.alert:GetAlpha() < 0.7 then caught = true end
  end
  if caught then break end
end
dump("f-bomb")
h:advance(3, 1 / 30)

-- D: a lost run
g.over = "loss"
W.callScript(board.frame, "OnLeave")
ns.Core.ShowOver(g)
dump("d-over")
