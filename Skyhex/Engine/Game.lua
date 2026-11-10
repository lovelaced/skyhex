-- Engine/Game.lua
-- One run of the endless mode. Game.move() resolves a whole move synchronously and
-- returns a list of beats for the UI to play back; the game table is always left in a
-- settled state, so saving can happen at any time.
--
-- Beats:
--   { t = "step",  kind, cycle, dir, center | index, n }     one rotation step
--   { t = "clear", cleared = {{cell, id}}, events, transforms, points }
--   { t = "fall",  falls = {{id, from, to}}, spawns = {{id, to, depth, piece}} }
--   { t = "tick",  bombs = {{cell, id, count}} }
--   { t = "level", level }
--   { t = "shuffle", moves = {{id, from, to}}, recolors = {{id, color}} }
--   { t = "over",  result = "win" | "loss", cells | cell, points, score }

local _, ns = ...
local Grid, Pieces, Detect, Search, Rng = ns.Grid, ns.Pieces, ns.Detect, ns.Search, ns.Rng
local Game = {}
ns.Game = Game

local RULES = {
  maxLevel = 7,
  levelCombos = { 50, 60, 70, 80, 90, 100 },   -- level 7 is endless
  -- PROPOSAL: sources only pin 5 colors early and 7 at level 7
  colors = { 5, 5, 5, 6, 6, 7, 7 },
  -- PROPOSAL: levels 4 to 6 interpolate between the documented 9 (level 3) and 5 (level 7)
  bombStart = { [3] = 9, [4] = 8, [5] = 7, [6] = 6, [7] = 5 },
  bombEvery = { [3] = 15, [4] = 10, [5] = 10, [6] = 10, [7] = 10 },   -- player-made combos per bomb
  bonusFrom = 2,
  -- PROPOSAL: about 6 of 85 pieces were bonus gems on a level 3 screenshot
  bonusChance = 0.06,
  startLevels = { 1, 3, 5 },
}
Game.RULES = RULES

local SCORE = {
  cluster = 5,              -- x (n - 2) x 2^bonus x level
  bonusCluster = 100,       -- x (n - 2) x level
  starCluster = 2500,       -- x (n - 2) x level
  pearlCluster = 25000,     -- x (n - 2) x level, wins
  flowerGem = 1000,         -- color flower by center kind, x 2^bonus in ring x level
  flowerStar = 1500,
  flowerPearl = 2500,
  starRing = 10000,         -- six starflowers make a pearl, x level
  starRingPearl = 15000,
  pearlRingGem = 200000,    -- six pearls, wins
  pearlRingSpecial = 250000,
}
Game.SCORE = SCORE

function Game.clusterPoints(n, bonus, level)
  return SCORE.cluster * (n - 2) * 2 ^ bonus * level
end

local N = Grid.N

local function newId(game)
  local id = game.nextId
  game.nextId = id + 1
  return id
end

local function spawn(game)
  local p
  if game.spawn then
    p = game.spawn(game)
  else
    local L = game.level
    local color = Rng.int(game.rng, RULES.colors[L])
    local bonus = L >= RULES.bonusFrom and Rng.float(game.rng) < RULES.bonusChance
    p = Pieces.gem(color, bonus)
  end
  p.id = newId(game)
  return p
end

-- Put a piece on a cell (tests and sandbox boards)
function Game.place(game, cell, piece)
  piece.id = newId(game)
  game.board[cell] = piece
  return piece
end

local function fillFresh(game)
  local board = game.board
  for attempt = 1, 50 do
    for id = 1, N do board[id] = nil end
    for id = 1, N do
      for _ = 1, 30 do
        board[id] = spawn(game)
        if not Detect.anyNear(board, { id }) then break end
      end
    end
    if not Detect.find(board).any and Search.hasMove(board) then return end
    if attempt == 50 then error("Skyhex: could not build a starting board") end
  end
end

function Game.new(opts)
  opts = opts or {}
  local level = opts.startLevel or 1
  local game = {
    board = {},
    rng = Rng.new(opts.seed or 1),
    level = level,
    startLevel = level,
    score = 0,
    combosLeft = RULES.levelCombos[level],
    bombCombo = 0,
    bombPending = 0,
    moves = 0,
    nextId = 1,
    drops = {},
    stats = { clusters = 0, flowers = 0, stars = 0, pearls = 0, defused = 0, bestChain = 0, bestMove = 0 },
    spawn = opts.spawn,          -- tests: replaces random new pieces
    noShuffle = opts.noShuffle,  -- tests: skip the no-move reshuffle
  }
  if not opts.empty then fillFresh(game) end
  return game
end

local function queueDrop(game, cell, piece)
  piece.id = newId(game)
  local c = Grid.cells[cell].c
  local q = game.drops[c]
  if not q then
    q = {}
    game.drops[c] = q
  end
  q[#q + 1] = piece
end

-- Clears one detection pass. Returns true if the run was won.
local function resolvePass(game, found, direct, beats)
  local board, L, stats = game.board, game.level, game.stats

  -- A pearl cluster or pearl flower ends the run. PROPOSAL: score only the best one.
  local best, bestCells = 0, nil
  for _, f in ipairs(found.flowers) do
    if f.cat == "pearl" then
      local pts = (board[f.center].kind == "gem" and SCORE.pearlRingGem or SCORE.pearlRingSpecial) * L
      if pts > best then
        best, bestCells = pts, { f.center, unpack(f.ring) }
      end
    end
  end
  for _, g in ipairs(found.clusters) do
    if g.cat == "pearl" then
      local pts = SCORE.pearlCluster * (#g.cells - 2) * L
      if pts > best then best, bestCells = pts, g.cells end
    end
  end
  if best > 0 then
    game.score = game.score + best
    game.over = "win"
    beats[#beats + 1] = { t = "over", result = "win", cells = bestCells, points = best, score = game.score }
    return true
  end

  local clear, cleared = {}, {}
  local function mark(id)
    if not clear[id] then
      clear[id] = true
      cleared[#cleared + 1] = id
    end
  end
  local events, transforms, total = {}, {}, 0
  local centers = {}
  for _, f in ipairs(found.flowers) do centers[f.center] = true end

  for _, f in ipairs(found.flowers) do
    local center = board[f.center]
    local pts
    if f.cat == "color" then
      local bonus = 0
      for i = 1, 6 do
        if board[f.ring[i]].bonus then bonus = bonus + 1 end
      end
      local base = (center.kind == "gem" and SCORE.flowerGem) or (center.kind == "star" and SCORE.flowerStar)
        or SCORE.flowerPearl
      pts = base * 2 ^ bonus * L
      if center.kind == "gem" then
        -- PROPOSAL: a bomb at the center is defused; a bonus at the center is lost
        if center.bomb then stats.defused = stats.defused + 1 end
        center.kind, center.color, center.bonus, center.bomb = "star", nil, nil, nil
        transforms[#transforms + 1] = { cell = f.center, id = center.id, to = "star" }
      else
        -- a starflower center stays and a new one drops in; PROPOSAL: same for a pearl center
        queueDrop(game, f.center, Pieces.star())
      end
      stats.stars = stats.stars + 1
      events[#events + 1] = { kind = "flower", points = pts, center = f.center, cells = f.ring, color = f.color }
    else -- six starflowers
      if center.kind == "pearl" then
        pts = SCORE.starRingPearl * L
        queueDrop(game, f.center, Pieces.pearl(Rng.int(game.rng, 2)))
      else
        pts = SCORE.starRing * L
        -- PROPOSAL: each pearl's Y or upside-down Y is random at creation
        center.kind, center.color, center.bonus, center.bomb = "pearl", nil, nil, nil
        center.y = Rng.int(game.rng, 2)
        transforms[#transforms + 1] = { cell = f.center, id = center.id, to = "pearl", y = center.y }
      end
      stats.pearls = stats.pearls + 1
      events[#events + 1] = { kind = "pearl", points = pts, center = f.center, cells = f.ring }
    end
    for i = 1, 6 do
      if not centers[f.ring[i]] then mark(f.ring[i]) end
    end
    total = total + pts
  end
  stats.flowers = stats.flowers + #found.flowers

  local wipes = {}
  for _, g in ipairs(found.clusters) do
    local n, pts = #g.cells, 0
    if g.cat == "color" then
      local bonus, bomb = 0, false
      for _, id in ipairs(g.cells) do
        local p = board[id]
        if p.bonus then bonus = bonus + 1 end
        if p.bomb then bomb = true end
      end
      pts = Game.clusterPoints(n, bonus, L)
      -- defusing a bomb with a bonus gem of its color wipes that color off the board
      if bomb and bonus > 0 then wipes[g.color] = true end
    elseif g.cat == "bonus" then
      pts = SCORE.bonusCluster * (n - 2) * L
      if g.mono then
        -- PROPOSAL: bonus gems of one color also clear every gem touching them
        for _, id in ipairs(g.cells) do
          local nb = Grid.neighbors[id]
          for d = 1, 6 do
            local m = nb[d]
            if m ~= 0 and board[m].kind == "gem" and not centers[m] then mark(m) end
          end
        end
      end
    elseif g.cat == "star" then
      pts = SCORE.starCluster * (n - 2) * L
    end
    for _, id in ipairs(g.cells) do mark(id) end
    events[#events + 1] = { kind = g.cat, points = pts, cells = g.cells, color = g.color, mono = g.mono }
    total = total + pts
  end
  stats.clusters = stats.clusters + #found.clusters

  for color = 1, 7 do
    if wipes[color] then
      for id = 1, N do
        local p = board[id]
        if p.kind == "gem" and p.color == color and not centers[id] then mark(id) end
      end
      events[#events + 1] = { kind = "wipe", points = 0, color = color }
    end
  end

  local out = {}
  for i, id in ipairs(cleared) do
    local p = board[id]
    if p.bomb then stats.defused = stats.defused + 1 end
    out[i] = { cell = id, id = p.id }
    board[id] = nil
  end

  local combos = #found.flowers + #found.clusters
  if direct then
    local every = RULES.bombEvery[L]
    if every then
      game.bombCombo = game.bombCombo + combos
      while game.bombCombo >= every do
        game.bombCombo = game.bombCombo - every
        game.bombPending = game.bombPending + 1
      end
    end
  end
  if game.combosLeft then game.combosLeft = game.combosLeft - combos end

  game.score = game.score + total
  beats[#beats + 1] = { t = "clear", cleared = out, events = events, transforms = transforms, points = total }
  return false
end

-- Gravity, then refill from the top. Queued starflowers and pearls enter first in
-- their column; a bomb that is due turns one of the new gems into a bomb.
local function settle(game, beats)
  local board = game.board
  local falls, spawns = {}, {}
  for c = 1, Grid.COLS do
    local rows = Grid.rowsIn(c)
    local write = rows
    for r = rows, 1, -1 do
      local id = Grid.id(c, r)
      local p = board[id]
      if p then
        if r ~= write then
          local to = Grid.id(c, write)
          board[to], board[id] = p, nil
          falls[#falls + 1] = { id = p.id, from = id, to = to }
        end
        write = write - 1
      end
    end
    local q, depth = game.drops[c], write
    for r = write, 1, -1 do
      local p = (q and #q > 0) and table.remove(q, 1) or spawn(game)
      local to = Grid.id(c, r)
      board[to] = p
      spawns[#spawns + 1] = { id = p.id, to = to, depth = depth }
    end
  end
  while game.bombPending > 0 do
    local pool = {}
    for _, s in ipairs(spawns) do
      local p = board[s.to]
      if p.kind == "gem" and not p.bomb then pool[#pool + 1] = p end
    end
    if #pool == 0 then break end
    local p = pool[Rng.int(game.rng, #pool)]
    p.bomb, p.bonus = RULES.bombStart[game.level] or 9, nil
    game.bombPending = game.bombPending - 1
  end
  for _, s in ipairs(spawns) do s.piece = Pieces.copy(board[s.to]) end
  beats[#beats + 1] = { t = "fall", falls = falls, spawns = spawns }
end

local function shuffle(game, beats)
  local board = game.board
  local cells, from = {}, {}
  for id = 1, N do
    local p = board[id]
    if p.kind == "gem" and not p.bomb then
      cells[#cells + 1] = id
      from[p] = id
    end
  end
  local recolors = {}
  local ok = false
  for attempt = 1, 200 do
    local pieces = {}
    for i, id in ipairs(cells) do pieces[i] = board[id] end
    Rng.shuffle(game.rng, pieces)
    for i, id in ipairs(cells) do board[id] = pieces[i] end
    if attempt > 60 then
      -- the colors themselves can't work out; reroll them
      for _, id in ipairs(cells) do
        board[id].color = Rng.int(game.rng, RULES.colors[game.level])
      end
    end
    if not Detect.find(board).any and Search.hasMove(board) then
      ok = true
      break
    end
  end
  local moves = {}
  for _, id in ipairs(cells) do
    local p = board[id]
    if from[p] ~= id then moves[#moves + 1] = { id = p.id, from = from[p], to = id } end
    recolors[#recolors + 1] = { id = p.id, color = p.color }
  end
  beats[#beats + 1] = { t = "shuffle", moves = moves, recolors = recolors, ok = ok }
end

-- The cells a move turns and how many steps one press may take.
function Game.cycleFor(game, mv)
  if mv.kind == "triad" then
    local t = Grid.triads[mv.index]
    if t then return t, 3 end
  elseif mv.kind == "ring" then
    local p = game.board[mv.cell]
    if p and p.kind == "star" and Grid.interior[mv.cell] then return Grid.rings[mv.cell], 1 end
  elseif mv.kind == "pearl" then
    local p = game.board[mv.cell]
    -- PROPOSAL: a pearl turns its three spokes one step per press
    if p and p.kind == "pearl" and Grid.interior[mv.cell] then return Grid.spokes(mv.cell, p.y), 1 end
  end
  return nil
end

function Game.move(game, mv)
  if game.over then return nil, "over" end
  local cycle, steps = Game.cycleFor(game, mv)
  if not cycle then return nil, "invalid" end
  local dir = (mv.dir == -1) and -1 or 1
  local board, beats = game.board, {}

  local before = {}
  for id = 1, N do
    if board[id].bomb then before[board[id]] = true end
  end

  local matched = false
  for n = 1, steps do
    Grid.rotate(board, cycle, dir)
    beats[#beats + 1] = { t = "step", kind = mv.kind, cycle = cycle, dir = dir, index = mv.index, center = mv.cell, n = n }
    if Detect.anyNear(board, cycle) then
      matched = true
      break
    end
  end
  game.moves = game.moves + 1

  local scoreBefore, passes = game.score, 0
  if matched then
    while passes < 100 do
      local found = Detect.find(board)
      if not found.any then break end
      passes = passes + 1
      if resolvePass(game, found, passes == 1, beats) then return beats end
      settle(game, beats)
    end
  end
  local stats = game.stats
  if passes > stats.bestChain then stats.bestChain = passes end
  if game.score - scoreBefore > stats.bestMove then stats.bestMove = game.score - scoreBefore end

  -- every bomb that was on the board before this move ticks once, matched or not
  local ticks, exploded = {}, nil
  for id = 1, N do
    local p = board[id]
    if p.bomb and before[p] then
      p.bomb = p.bomb - 1
      ticks[#ticks + 1] = { cell = id, id = p.id, count = p.bomb }
      if p.bomb <= 0 and not exploded then exploded = id end
    end
  end
  if #ticks > 0 then beats[#beats + 1] = { t = "tick", bombs = ticks } end
  if exploded then
    game.over = "loss"
    beats[#beats + 1] = { t = "over", result = "loss", cell = exploded, points = 0, score = game.score }
    return beats
  end

  if game.combosLeft and game.combosLeft <= 0 then
    game.level = game.level + 1
    local need = RULES.levelCombos[game.level]
    game.combosLeft = need and math.max(1, need + game.combosLeft) or nil
    beats[#beats + 1] = { t = "level", level = game.level }
  end

  -- PROPOSAL: with no possible match anywhere, normal gems reshuffle for free
  if not game.noShuffle and not Search.hasMove(board) then shuffle(game, beats) end
  return beats
end

function Game.hint(game)
  if game.over then return nil end
  return Search.findMoves(game.board, true)[1]
end
