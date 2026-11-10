-- UI/Player.lua
-- Plays a move's beats on the board. One OnUpdate loop runs only while something is
-- moving. The engine has already settled the game, so Finish() can jump to the end at
-- any time (landing, closing the window) and Sync() makes the board exact.

local _, ns = ...
local Grid = ns.Grid
local Player = {}
ns.Player = Player

local TURN_TIME = { triad = 0.15, ring = 0.17, pearl = 0.17 }
local CLEAR_TIME = 0.2
local SHUFFLE_TIME = 0.4
local ALARM_TIME = 0.7

local function easeInOut(t)
  if t < 0.5 then return 4 * t * t * t end
  local u = -2 * t + 2
  return 1 - u * u * u / 2
end

local function easeIn(t) return t * t end

function Player.new(board, hooks)
  local self = setmetatable({}, { __index = Player })
  self.board, self.hooks = board, hooks or {}
  self.driver = CreateFrame("Frame", nil, board.frame)
  return self
end

function Player:IsBusy() return self.beats ~= nil end

function Player:Play(game, beats, onDone)
  self.game, self.beats, self.index, self.onDone = game, beats, 0, onDone
  self.board.busy = true
  self:Next()
  if self.beats then
    self.driver:SetScript("OnUpdate", function(_, elapsed) self:Update(elapsed) end)
  end
end

function Player:Finish()
  if not self.beats then return end
  self.beats = nil
  self.tweens = nil
  self.driver:SetScript("OnUpdate", nil)
  for _, t in ipairs(self.dying or {}) do self.board:Release(t) end
  self.dying = nil
  self.board:Sync(self.game)
  self.board.busy = false
  self.board:UpdateHover(true)
  local done = self.onDone
  self.onDone = nil
  if done then done() end
end

-- Start the next beat, or finish. A beat sets self.tweens and self.left (seconds).
function Player:Next()
  if self.dying then
    for _, t in ipairs(self.dying) do self.board:Release(t) end
    self.dying = nil
  end
  if self.tweens then
    for _, tw in ipairs(self.tweens) do tw.fn(1) end
  end
  self.tweens = nil
  while self.beats do
    self.index = self.index + 1
    local beat = self.beats[self.index]
    if not beat then
      self:Finish()
      return
    end
    local start = self["beat_" .. beat.t]
    local duration = start and start(self, beat) or 0
    if duration > 0 then
      self.left, self.total = duration, duration
      self.elapsed = 0
      return
    end
  end
end

function Player:Update(elapsed)
  if not self.beats then return end
  self.elapsed = self.elapsed + elapsed
  if self.tweens then
    for _, tw in ipairs(self.tweens) do
      local t = (self.elapsed - (tw.delay or 0)) / tw.dur
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      tw.fn(t)
    end
  end
  if self.elapsed >= self.total then self:Next() end
end

local function add(self, dur, fn, delay)
  self.tweens = self.tweens or {}
  self.tweens[#self.tweens + 1] = { dur = dur, fn = fn, delay = delay }
end

-- beats ---------------------------------------------------------------------

function Player:beat_step(beat)
  local board, cycle, k = self.board, beat.cycle, #beat.cycle
  local px, py
  if beat.kind == "triad" then
    local t = Grid.triads[beat.index]
    px, py = t.x, t.y
  else
    local c = Grid.cells[beat.center]
    px, py = c.x, c.y
  end
  local moved = {}
  for i = 1, k do
    local from = cycle[i]
    local to = cycle[(i - 1 + beat.dir) % k + 1]
    local tile = board.cellTile[from]
    if tile then
      local c = Grid.cells[from]
      local a0 = math.atan2(c.y - py, c.x - px)
      local r = math.sqrt((c.x - px) ^ 2 + (c.y - py) ^ 2)
      local delta = beat.dir * 2 * math.pi / k
      add(self, TURN_TIME[beat.kind], function(t)
        local a = a0 + delta * easeInOut(t)
        board:PlaceAt(tile, px + r * math.cos(a), py + r * math.sin(a))
      end)
      moved[to] = tile
    end
  end
  for i = 1, k do board.cellTile[cycle[i]] = moved[cycle[i]] end
  ns.Media.play("turn")
  return TURN_TIME[beat.kind] + 0.02
end

function Player:beat_clear(beat)
  local board = self.board
  self.dying = {}
  for _, c in ipairs(beat.cleared) do
    local tile = board.tiles[c.id]
    if tile then
      if board.cellTile[c.cell] == tile then board.cellTile[c.cell] = nil end
      self.dying[#self.dying + 1] = tile
      add(self, CLEAR_TIME, function(t)
        board:SetTileScale(tile, 1 + 0.3 * t)
        tile:SetAlpha(1 - t)
      end)
    end
  end
  local sound = "clear"
  for _, tr in ipairs(beat.transforms) do
    local tile = board.tiles[tr.id]
    if tile then
      board:SetLook(tile, { kind = tr.to, y = tr.y })
      add(self, CLEAR_TIME, function(t)
        board:SetTileScale(tile, 1 + 0.25 * math.sin(t * math.pi))
      end)
    end
    sound = tr.to == "pearl" and "pearl" or "star"
  end
  for _, ev in ipairs(beat.events) do
    if ev.kind == "star" and sound == "clear" then sound = "star" end
  end
  ns.Media.play(sound)
  if self.hooks.onScore then self.hooks.onScore(beat) end
  return CLEAR_TIME + 0.03
end

function Player:beat_fall(beat)
  local board = self.board
  local longest = 0
  local SQ = Grid.SQRT3
  local function drop(tile, x, y0, y1)
    local cells = (y1 - y0) / SQ
    local dur = 0.12 + 0.05 * math.sqrt(math.max(cells, 0)) * 2
    if dur > longest then longest = dur end
    add(self, dur, function(t)
      board:PlaceAt(tile, x, y0 + (y1 - y0) * easeIn(t))
    end)
    return dur
  end
  for _, f in ipairs(beat.falls) do
    local tile = board.tiles[f.id]
    if tile then
      local a, b = Grid.cells[f.from], Grid.cells[f.to]
      if board.cellTile[f.from] == tile then board.cellTile[f.from] = nil end
      board.cellTile[f.to] = tile
      drop(tile, a.x, a.y, b.y)
    end
  end
  for _, s in ipairs(beat.spawns) do
    local tile = board.tiles[s.id] or board:Acquire(s.id)
    board:SetLook(tile, s.piece)
    local b = Grid.cells[s.to]
    -- new pieces enter stacked above the top of their column
    local y0 = b.y - s.depth * SQ - SQ
    board:PlaceAt(tile, b.x, y0)
    board.cellTile[s.to] = tile
    local dur = drop(tile, b.x, y0, b.y)
    if s.piece.bomb then
      self:BombArrives(tile, b.x, b.y, dur)
      longest = math.max(longest, dur + ALARM_TIME)
    end
  end
  return longest + 0.02
end

-- A bomb that just dropped in pops, shakes side to side and sends out a red ring, so a
-- new countdown never slips by unnoticed. Starts once the bomb has landed.
function Player:BombArrives(tile, x, y, delay)
  local board, ring, size = self.board, tile.alert, self.board.size
  local landed = false
  add(self, ALARM_TIME, function(t)
    if t <= 0 then return end
    if not landed then
      landed = true
      ns.Media.play("bomb")
    end
    if t >= 1 then
      ring:Hide()
      board:SetTileScale(tile, 1)
      board:PlaceAt(tile, x, y)
      return
    end
    board:SetTileScale(tile, 1 + 0.2 * math.sin(math.min(t / 0.3, 1) * math.pi))
    local fade = (1 - t) * (1 - t)
    board:PlaceAt(tile, x + 0.16 * fade * math.sin(t * math.pi * 9), y)
    local grow = 2 * size * (1 + 0.9 * (1 - (1 - t) ^ 3))
    ring:SetSize(grow, grow)
    ring:SetAlpha((1 - t) ^ 1.5)
    ring:Show()
  end, delay)
end

function Player:beat_tick(beat)
  local board = self.board
  for _, b in ipairs(beat.bombs) do
    local tile = board.tiles[b.id]
    if tile and tile.look then
      local look = tile.look
      look.bomb = b.count
      board:SetLook(tile, look)
      add(self, 0.18, function(t) board:SetTileScale(tile, 1 + 0.18 * math.sin(t * math.pi)) end)
    end
  end
  ns.Media.play("tick")
  return 0.2
end

function Player:beat_level(beat)
  ns.Media.play("level")
  if self.hooks.onLevel then self.hooks.onLevel(beat.level) end
  return 0
end

function Player:beat_shuffle(beat)
  local board = self.board
  for _, m in ipairs(beat.moves) do
    local tile = board.tiles[m.id]
    if tile then
      local a, b = Grid.cells[m.from], Grid.cells[m.to]
      add(self, SHUFFLE_TIME, function(t)
        local e = easeInOut(t)
        board:PlaceAt(tile, a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e)
      end)
    end
  end
  if self.hooks.onShuffle then self.hooks.onShuffle() end
  return SHUFFLE_TIME + 0.05
end

function Player:beat_over(beat)
  if beat.result == "win" then
    ns.Media.play("win")
  else
    ns.Media.play("lose")
    local board = self.board
    local tile = board.cellTile[beat.cell]
    if tile then
      add(self, 0.5, function(t)
        board:SetTileScale(tile, 1 + 0.6 * t)
        tile:SetAlpha(1 - t * 0.8)
      end)
      return 0.5
    end
  end
  return 0
end
