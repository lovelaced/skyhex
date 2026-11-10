-- UI/Board.lua
-- The board: one tile frame per piece (keyed by piece id), hover selection with hex
-- math on a single mouse-enabled frame, and the highlight layer.
-- Unit coordinates come from Grid (y grows downward, hex size 1); pixels are unit * size,
-- anchored to the board's TOPLEFT with y negated.

local _, ns = ...
local Grid, Media = ns.Grid, ns.Media
local Board = {}
ns.Board = Board

local ICON_INSET = 0.84   -- the gem icon's hex is this much of the tile, leaving a colored rim
local PICK_SPECIAL = 0.52 -- cursor this close (in hex sizes) to a starflower or pearl picks it

-- spoke angles on screen (degrees, y down) for ring directions N, NE, SE, S, SW, NW
local DIR_ANGLE = { -90, -30, 30, 90, 150, 210 }

function Board.new(parent, size)
  local self = setmetatable({}, { __index = Board })
  self.size = size
  self.tiles, self.cellTile, self.pool = {}, {}, {}

  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(Grid.WIDTH * size, Grid.HEIGHT * size)
  f:SetClipsChildren(true)
  f:EnableMouse(true)
  self.frame = f

  -- highlights sit above every tile
  local hl = CreateFrame("Frame", nil, f)
  hl:SetAllPoints()
  hl:SetFrameLevel(f:GetFrameLevel() + 20)
  self.hlFrame = hl
  self.hl = {}
  for i = 1, 7 do
    local t = hl:CreateTexture(nil, "OVERLAY")
    t:SetTexture(Media.HEX_EDGE)
    t:SetBlendMode("ADD")
    t:SetSize(2 * size, 2 * size)
    t:Hide()
    self.hl[i] = t
  end
  local pivot = hl:CreateTexture(nil, "OVERLAY", nil, 2)
  pivot:SetTexture(Media.PIVOT)
  pivot:SetSize(size * 0.5, size * 0.5)
  pivot:Hide()
  self.pivot = pivot

  f:SetScript("OnEnter", function() self:StartHover() end)
  f:SetScript("OnLeave", function() self:StopHover() end)
  f:SetScript("OnMouseDown", function(_, button)
    if self.onClick and self.selection then self.onClick(self.selection, button) end
  end)
  return self
end

function Board:CellPoint(cell)
  local c = Grid.cells[cell]
  return c.x * self.size, -c.y * self.size
end

-- Anchor offsets are measured in the tile's own scale, so a scaled tile divides them
-- by its scale to stay centered on the same spot.
function Board:PlaceAt(t, ux, uy)
  t.ux, t.uy = ux, uy
  local k = t.scale or 1
  t:ClearAllPoints()
  t:SetPoint("CENTER", self.frame, "TOPLEFT", ux * self.size / k, -uy * self.size / k)
end

function Board:SetTileScale(t, k)
  t.scale = k
  t:SetScale(k)
  if t.ux then self:PlaceAt(t, t.ux, t.uy) end
end

function Board:Place(t, cell)
  local c = Grid.cells[cell]
  self:PlaceAt(t, c.x, c.y)
end

-- tiles ---------------------------------------------------------------------

local function newTile(self)
  local s = self.size
  local t = CreateFrame("Frame", nil, self.frame)
  t:SetSize(2 * s, 2 * s)

  t.base = t:CreateTexture(nil, "BACKGROUND")
  t.base:SetTexture(Media.HEX_BASE)
  t.base:SetAllPoints()

  t.mask = t:CreateMaskTexture()
  t.mask:SetTexture(Media.HEX_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  t.mask:SetSize(2 * s * ICON_INSET, 2 * s * ICON_INSET)
  t.mask:SetPoint("CENTER")

  t.icon = t:CreateTexture(nil, "ARTWORK")
  t.icon:SetSize(2 * s * ICON_INSET, 2 * s * ICON_INSET)
  t.icon:SetPoint("CENTER")
  t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  t.icon:AddMaskTexture(t.mask)

  t.fuse = t:CreateTexture(nil, "OVERLAY", nil, 1)
  t.fuse:SetTexture(Media.HEX_GLOW)
  t.fuse:SetAllPoints()
  t.fuse:SetBlendMode("ADD")
  t.fuse:SetVertexColor(unpack(Media.BOMB_RGB))
  t.fuse:Hide()
  local pulse = t.fuse:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local a = pulse:CreateAnimation("Alpha")
  a:SetFromAlpha(1)
  a:SetToAlpha(0.25)
  a:SetDuration(0.6)
  t.fusePulse = pulse

  t.count = t:CreateFontString(nil, "OVERLAY", nil)
  t.count:SetFont(Media.FONT, math.floor(s * 0.9), "THICKOUTLINE")
  t.count:SetPoint("CENTER", 0, -1)
  t.count:Hide()

  -- bonus gems carry a star in the middle, the way the original marks them
  t.badge = t:CreateTexture(nil, "OVERLAY", nil, 2)
  t.badge:SetTexture(Media.STAR_BADGE)
  t.badge:SetSize(s, s)
  t.badge:SetPoint("CENTER")
  t.badge:SetVertexColor(unpack(Media.BONUS_RGB))
  t.badge:Hide()

  -- a red ring that spreads out from a bomb as it lands (Player:BombArrives)
  t.alert = t:CreateTexture(nil, "OVERLAY", nil, 4)
  t.alert:SetTexture(Media.HEX_EDGE)
  t.alert:SetBlendMode("ADD")
  t.alert:SetPoint("CENTER")
  t.alert:SetSize(2 * s, 2 * s)
  t.alert:SetVertexColor(unpack(Media.BOMB_RGB))
  t.alert:Hide()

  t.spokes = {}
  for i = 1, 3 do
    local l = t:CreateLine(nil, "OVERLAY", nil, 3)
    l:SetThickness(math.max(2, s * 0.16))
    l:SetColorTexture(0.85, 0.72, 1, 0.95)
    l:Hide()
    t.spokes[i] = l
  end
  return t
end

function Board:Acquire(id)
  local t = table.remove(self.pool) or newTile(self)
  t.pieceId = id
  t:SetAlpha(1)
  t.scale = 1
  t:SetScale(1)
  t:Show()
  self.tiles[id] = t
  return t
end

function Board:Release(t)
  if self.tiles[t.pieceId] == t then self.tiles[t.pieceId] = nil end
  t.fusePulse:Stop()
  t.alert:Hide()
  t:Hide()
  self.pool[#self.pool + 1] = t
end

-- look is a piece snapshot: { kind, color, bonus, bomb, y }
function Board:SetLook(t, look)
  t.look = look
  local m
  if look.kind == "gem" then
    m = Media.GEMS[look.color] or Media.GEMS[1]
  elseif look.kind == "star" then
    m = Media.STAR
  else
    m = Media.BLACK_PEARL
  end
  local rgb, tint = m.rgb, m.tint
  t.icon:SetTexture(m.icon)
  t.icon:SetDesaturated(m.desat and true or false)
  t.base:SetVertexColor(rgb[1] * 0.78, rgb[2] * 0.78, rgb[3] * 0.78)
  t.badge:SetShown(look.bonus and true or false)

  if look.bomb then
    t.count:SetText(look.bomb)
    if look.bomb <= 3 then t.count:SetTextColor(1, 0.45, 0.4) else t.count:SetTextColor(1, 1, 1) end
    t.count:Show()
    t.fuse:Show()
    if not t.fusePulse:IsPlaying() then t.fusePulse:Play() end
    local k = 0.72
    if tint then t.icon:SetVertexColor(tint[1] * k, tint[2] * k, tint[3] * k) else t.icon:SetVertexColor(k, k, k) end
  else
    t.count:Hide()
    t.fuse:Hide()
    t.fusePulse:Stop()
    if tint then t.icon:SetVertexColor(tint[1], tint[2], tint[3]) else t.icon:SetVertexColor(1, 1, 1) end
  end

  if look.kind == "pearl" then
    local s = self.size
    for i, d in ipairs(Grid.PEARL_DIRS[look.y] or Grid.PEARL_DIRS[1]) do
      local a = math.rad(DIR_ANGLE[d])
      local cx, cy = math.cos(a), -math.sin(a)
      local l = t.spokes[i]
      l:SetStartPoint("CENTER", t, cx * s * 0.55, cy * s * 0.55)
      l:SetEndPoint("CENTER", t, cx * s * 0.9, cy * s * 0.9)
      l:Show()
    end
  else
    for i = 1, 3 do t.spokes[i]:Hide() end
  end
end

local function snapshot(p)
  return { kind = p.kind, color = p.color, bonus = p.bonus, bomb = p.bomb, y = p.y }
end
Board.snapshot = snapshot

-- Make every tile match the game exactly. Used after playback and on load.
function Board:Sync(game)
  local used = {}
  for cell = 1, Grid.N do
    local p = game.board[cell]
    local t = self.tiles[p.id] or self:Acquire(p.id)
    used[p.id] = true
    t:SetAlpha(1)
    t.alert:Hide()
    self:SetTileScale(t, 1)
    self:SetLook(t, snapshot(p))
    self:Place(t, cell)
    self.cellTile[cell] = t
  end
  for id, t in pairs(self.tiles) do
    if not used[id] then self:Release(t) end
  end
end

-- selection -----------------------------------------------------------------

-- What the cursor at unit coordinates (ux, uy) would turn.
function Board:Pick(game, ux, uy)
  local best, bd = nil, math.huge
  for cell = 1, Grid.N do
    local c = Grid.cells[cell]
    local d = (c.x - ux) ^ 2 + (c.y - uy) ^ 2
    if d < bd then best, bd = cell, d end
  end
  local p = game.board[best]
  if p and bd < PICK_SPECIAL ^ 2 and Grid.interior[best] and (p.kind == "star" or p.kind == "pearl") then
    return { kind = p.kind == "star" and "ring" or "pearl", cell = best }
  end
  local bi, bt = nil, math.huge
  for i, t in ipairs(Grid.triads) do
    local d = (t.x - ux) ^ 2 + (t.y - uy) ^ 2
    if d < bt then bi, bt = i, d end
  end
  return { kind = "triad", index = bi }
end

function Board:ShowSelection(game, sel, hint)
  for i = 1, 7 do self.hl[i]:Hide() end
  self.pivot:Hide()
  if not sel then return end
  local cells, px, py
  if sel.kind == "triad" then
    local t = Grid.triads[sel.index]
    cells, px, py = { t[1], t[2], t[3] }, t.x, t.y
  else
    local c = Grid.cells[sel.cell]
    local p = game.board[sel.cell]
    cells = sel.kind == "ring" and Grid.rings[sel.cell] or Grid.spokes(sel.cell, p.y)
    px, py = c.x, c.y
  end
  local r, g, b = 1, 1, 1
  if hint then r, g, b = 0.55, 0.85, 1 end
  for i, cell in ipairs(cells) do
    local t = self.hl[i]
    local x, y = self:CellPoint(cell)
    t:ClearAllPoints()
    t:SetPoint("CENTER", self.frame, "TOPLEFT", x, y)
    t:SetVertexColor(r, g, b, hint and 0.7 or 0.95)
    t:Show()
  end
  self.pivot:ClearAllPoints()
  self.pivot:SetPoint("CENTER", self.frame, "TOPLEFT", px * self.size, -py * self.size)
  self.pivot:SetVertexColor(r, g, b, 1)
  self.pivot:Show()
end

function Board:CursorUnits()
  local f = self.frame
  local left, top = f:GetLeft(), f:GetTop()
  if not left then return nil end
  local x, y = GetCursorPosition()
  local s = f:GetEffectiveScale()
  return (x / s - left) / self.size, (top - y / s) / self.size
end

-- Hover runs only while the cursor is over the board and nothing is animating.
function Board:StartHover()
  self.hovering = true
  self.lastX = nil
  self.frame:SetScript("OnUpdate", function() self:UpdateHover() end)
end

function Board:StopHover()
  self.hovering = false
  self.hinting = false
  self.frame:SetScript("OnUpdate", nil)
  self.selection = nil
  self:ShowSelection(nil, nil)
end

function Board:UpdateHover(force)
  if not self.hovering or not self.game then return end
  if self.busy then
    if self.selection then
      self.selection = nil
      self:ShowSelection(nil, nil)
    end
    return
  end
  local ux, uy = self:CursorUnits()
  if not ux then return end
  if not force and self.lastX == ux and self.lastY == uy then return end
  self.lastX, self.lastY = ux, uy
  local sel = self:Pick(self.game, ux, uy)
  local cur = self.selection
  if force or not cur or cur.kind ~= sel.kind or cur.index ~= sel.index or cur.cell ~= sel.cell then
    self.selection = sel
    self:ShowSelection(self.game, sel)
  end
end
