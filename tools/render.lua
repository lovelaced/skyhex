-- tools/render.lua
-- Renders engine boards to SVG/PNG for checking geometry and rules by eye.
--   luajit tools/render.lua [outDir]
-- Writes one PNG per scene (before and after side by side) using rsvg-convert.

package.path = "tests/?.lua;" .. package.path
local outDir = arg[1] or "tools/out/render"

local function loadEngine()
  local ns = {}
  for line in io.lines("Skyhex/Skyhex.toc") do
    local path = line:match("^(Engine[\\/][%w_]+%.lua)")
    if path then assert(loadfile("Skyhex/" .. path:gsub("\\", "/")))("Skyhex", ns) end
  end
  return ns
end

local ns = loadEngine()
local Grid, Game, Pieces, Search = ns.Grid, ns.Game, ns.Pieces, ns.Search
local H = dofile("tests/helpers.lua")(ns, {})

-- rough gem hues, in the order UI/Media.lua assigns icons
local COLORS = { "#d8364a", "#f0c419", "#3fae49", "#2bb3c0", "#9b4fd1", "#ece8e0", "#e8792b" }
local S = 22

local function hexPoints(cx, cy, s)
  local pts = {}
  for k = 0, 5 do
    local a = math.rad(60 * k)
    pts[#pts + 1] = string.format("%.1f,%.1f", cx + s * math.cos(a), cy + s * math.sin(a))
  end
  return table.concat(pts, " ")
end

local function star5(cx, cy, r)
  local pts = {}
  for k = 0, 9 do
    local a = math.rad(-90 + 36 * k)
    local rr = (k % 2 == 0) and r or r * 0.45
    pts[#pts + 1] = string.format("%.1f,%.1f", cx + rr * math.cos(a), cy + rr * math.sin(a))
  end
  return table.concat(pts, " ")
end

local function board(out, g, ox, oy, title, marks)
  out[#out + 1] = string.format('<text x="%d" y="%d" font-family="Helvetica" font-size="14" fill="#ddd">%s</text>', ox, oy - 8, title)
  marks = marks or {}
  for id = 1, Grid.N do
    local cell, p = Grid.cells[id], g.board[id]
    local cx, cy = ox + cell.x * S, oy + cell.y * S
    local fill = "#333"
    if p and p.kind == "gem" then fill = COLORS[p.color] or "#555" end
    if p and p.kind == "star" then fill = "#3a4fa8" end
    if p and p.kind == "pearl" then fill = "#1d1b26" end
    local stroke = marks[id] and "#fff" or "#111"
    local sw = marks[id] and 3 or 1.5
    out[#out + 1] = string.format('<polygon points="%s" fill="%s" stroke="%s" stroke-width="%s"/>', hexPoints(cx, cy, S - 1), fill, stroke, sw)
    if p and p.bonus then
      out[#out + 1] = string.format('<polygon points="%s" fill="#fff" fill-opacity="0.85"/>', star5(cx, cy, S * 0.45))
    end
    if p and p.bomb then
      out[#out + 1] = string.format('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#111" stroke="#f33" stroke-width="2"/>', cx, cy, S * 0.5)
      out[#out + 1] = string.format('<text x="%.1f" y="%.1f" text-anchor="middle" font-family="Helvetica" font-weight="bold" font-size="13" fill="#fff">%d</text>', cx, cy + 5, p.bomb)
    end
    if p and p.kind == "star" then
      for k = 0, 5 do
        local a = math.rad(60 * k + 30)
        out[#out + 1] = string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#fff" stroke-width="2.5"/>', cx, cy, cx + S * 0.55 * math.cos(a), cy + S * 0.55 * math.sin(a))
      end
    end
    if p and p.kind == "pearl" then
      out[#out + 1] = string.format('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#000" stroke="#c9a7ff" stroke-width="1.5"/>', cx, cy, S * 0.55)
      -- spokes toward the three cells this pearl turns
      local dirs = Grid.PEARL_DIRS[p.y]
      local angle = { [1] = -90, [2] = -30, [3] = 30, [4] = 90, [5] = 150, [6] = 210 }
      for _, d in ipairs(dirs) do
        local a = math.rad(angle[d])
        out[#out + 1] = string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#c9a7ff" stroke-width="2"/>', cx, cy, cx + S * 0.8 * math.cos(a), cy + S * 0.8 * math.sin(a))
      end
    end
    if p and p.kind == "gem" and not p.bomb and p.color > 7 then
      out[#out + 1] = string.format('<circle cx="%.1f" cy="%.1f" r="2" fill="#666"/>', cx, cy)
    end
  end
end

local function scene(name, panels)
  local W, Hh = math.ceil(Grid.WIDTH * S) + 30, math.ceil(Grid.HEIGHT * S) + 40
  local out = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', W * #panels + 10, Hh + 10),
    string.format('<rect width="100%%" height="100%%" fill="#15171c"/>') }
  for i, p in ipairs(panels) do board(out, p.game, 10 + (i - 1) * W, 30, p.title, p.marks) end
  out[#out + 1] = "</svg>"
  local svg = outDir .. "/" .. name .. ".svg"
  local f = assert(io.open(svg, "w"))
  f:write(table.concat(out, "\n"))
  f:close()
  os.execute(string.format('rsvg-convert "%s" -o "%s/%s.png"', svg, outDir, name))
  print(outDir .. "/" .. name .. ".png")
end

-- board-only copy (spec boards use made-up colors the codec would reject)
local function clone(g)
  local c = { board = {}, score = g.score, level = g.level }
  for id = 1, Grid.N do c.board[id] = Pieces.copy(g.board[id]) end
  return c
end

local function marksOf(list)
  local m = {}
  for _, id in ipairs(list) do m[id] = true end
  return m
end

local function triadCells(i)
  local t = Grid.triads[i]
  return marksOf({ t[1], t[2], t[3] })
end

os.execute('mkdir -p "' .. outDir .. '"')

-- fresh boards at the three start levels
do
  local panels = {}
  for _, lv in ipairs({ 1, 3, 5 }) do
    panels[#panels + 1] = { game = Game.new({ seed = 2026, startLevel = lv }), title = "fresh board, level " .. lv }
  end
  scene("01-fresh", panels)
end

-- a flower makes a starflower
do
  local g = H.blank()
  H.put(g, 4, 4, Pieces.gem(5))
  for _, cell in ipairs(H.ring(4, 4)) do
    if cell ~= H.id(4, 5) then Game.place(g, cell, Pieces.gem(3)) end
  end
  H.put(g, 4, 5, Pieces.gem(1)); H.put(g, 4, 6, Pieces.gem(3))
  local i = H.triad(H.id(4, 5), H.id(4, 6), H.id(5, 5))
  local before = clone(g)
  local beats = Game.move(g, { kind = "triad", index = i, dir = 1 })
  scene("02-flower", { { game = before, title = "before: turn the marked triad", marks = triadCells(i) },
    { game = g, title = string.format("after: starflower, +%d (%d steps)", g.score, #H.beats(beats, "step")) } })
end

-- six starflowers make a black pearl
do
  local g = H.blank()
  H.put(g, 4, 4, Pieces.gem(2))
  for _, cell in ipairs(H.ring(4, 4)) do
    if cell ~= H.id(4, 5) then Game.place(g, cell, Pieces.star()) end
  end
  H.put(g, 4, 5, Pieces.gem(1)); H.put(g, 4, 6, Pieces.star())
  local i = H.triad(H.id(4, 5), H.id(4, 6), H.id(5, 5))
  local before = clone(g)
  Game.move(g, { kind = "triad", index = i, dir = 1 })
  scene("03-pearl", { { game = before, title = "before", marks = triadCells(i) },
    { game = g, title = string.format("after: black pearl, +%d", g.score) } })
end

-- pearl and starflower rotations
do
  local g = H.blank()
  H.put(g, 4, 4, Pieces.pearl(1))
  H.put(g, 4, 3, Pieces.gem(1)); H.put(g, 5, 4, Pieces.gem(2)); H.put(g, 3, 4, Pieces.gem(3))
  H.put(g, 7, 4, Pieces.star())
  for i, cell in ipairs(H.ring(7, 4)) do Game.place(g, cell, Pieces.gem(i)) end
  local before = clone(g)
  Game.move(g, { kind = "pearl", cell = H.id(4, 4), dir = 1 })
  local mid = clone(g)
  Game.move(g, { kind = "ring", cell = H.id(7, 4), dir = 1 })
  scene("04-rotations", { { game = before, title = "before" }, { game = mid, title = "pearl turned clockwise" },
    { game = g, title = "starflower ring turned clockwise" } })
end

-- bomb defused with a bonus gem wipes its color
do
  local g = H.blank(3)
  H.put(g, 4, 5, Pieces.bomb(4, 3)); H.put(g, 4, 6, Pieces.gem(4, true)); H.put(g, 5, 6, Pieces.gem(4))
  H.put(g, 1, 1, Pieces.gem(4)); H.put(g, 9, 7, Pieces.gem(4)); H.put(g, 8, 2, Pieces.gem(4, true))
  local i = H.triad(H.id(5, 5), H.id(5, 6), H.id(6, 6))
  local before = clone(g)
  Game.move(g, { kind = "triad", index = i, dir = 1 })
  scene("05-bomb-wipe", { { game = before, title = "before", marks = triadCells(i) },
    { game = g, title = string.format("after: color wiped, +%d", g.score) } })
end

-- a real game: hint move on a fresh level 5 board
do
  local g = Game.new({ seed = 77, startLevel = 5 })
  for _ = 1, 25 do Game.move(g, Search.findMoves(g.board, true)[1]) end
  local hint = Game.hint(g)
  local before = clone(g)
  Game.move(g, hint)
  scene("06-play", { { game = before, title = "level " .. before.level .. ", hint marked", marks = triadCells(hint.index or 1) },
    { game = g, title = string.format("after: score %d, level %d", g.score, g.level) } })
end
