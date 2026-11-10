-- UI/Window.lua
-- The Skyhex window: a dark movable panel with the score and level on top, the board,
-- and a one-line footer. Overlays (new run, run over) dim the board and take clicks.

local _, ns = ...
local Grid, Media = ns.Grid, ns.Media
local Window = {}
ns.Window = Window

local SIZE = 24          -- hex size in pixels at scale 1
local PAD = 14
local HEADER = 64
local FOOTER = 26

local BG = { 0.075, 0.082, 0.105, 0.96 }
local EDGE = { 0.20, 0.22, 0.28, 1 }
local MUTED = { 0.62, 0.65, 0.72 }

local function font(fs, size, flags)
  fs:SetFont(Media.FONT, size, flags or "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  return fs
end

local function solid(parent, layer, rgba)
  local t = parent:CreateTexture(nil, layer)
  t:SetColorTexture(unpack(rgba))
  return t
end

function Window:Create(hooks)
  self.hooks = hooks
  local boardW, boardH = Grid.WIDTH * SIZE, Grid.HEIGHT * SIZE
  local f = CreateFrame("Frame", "SkyhexFrame", UIParent, "BackdropTemplate")
  f:SetSize(boardW + 2 * PAD, HEADER + boardH + FOOTER + PAD)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
  f:SetScript("OnDragStop", function(frame)
    frame:StopMovingOrSizing()
    if hooks.onMoved then hooks.onMoved(frame:GetPoint()) end
  end)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  f:SetBackdropColor(unpack(BG))
  f:SetBackdropBorderColor(unpack(EDGE))
  f:Hide()
  f:SetScript("OnHide", function() if hooks.onHide then hooks.onHide() end end)
  tinsert(UISpecialFrames, "SkyhexFrame")
  self.frame = f

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() f:Hide() end)

  self.title = font(f:CreateFontString(nil, "ARTWORK"), 12)
  self.title:SetPoint("TOPLEFT", PAD, -10)
  self.title:SetTextColor(unpack(MUTED))
  self.title:SetText("Skyhex")

  self.score = font(f:CreateFontString(nil, "ARTWORK"), 26)
  self.score:SetPoint("TOPLEFT", PAD, -26)
  self.score:SetTextColor(1, 1, 1)

  self.best = font(f:CreateFontString(nil, "ARTWORK"), 11)
  self.best:SetPoint("LEFT", self.score, "RIGHT", 10, -4)
  self.best:SetTextColor(unpack(MUTED))

  self.level = font(f:CreateFontString(nil, "ARTWORK"), 16)
  self.level:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -28)
  self.level:SetJustifyH("RIGHT")
  self.level:SetTextColor(1, 0.86, 0.45)

  self.combos = font(f:CreateFontString(nil, "ARTWORK"), 11)
  self.combos:SetPoint("TOPRIGHT", self.level, "BOTTOMRIGHT", 0, -3)
  self.combos:SetJustifyH("RIGHT")
  self.combos:SetTextColor(unpack(MUTED))

  local well = solid(f, "BACKGROUND", { 0.045, 0.05, 0.065, 1 })
  well:SetPoint("TOPLEFT", PAD - 4, -HEADER + 4)
  well:SetSize(boardW + 8, boardH + 8)

  self.board = ns.Board.new(f, SIZE)
  self.board.frame:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER)

  self.footer = font(f:CreateFontString(nil, "ARTWORK"), 11)
  self.footer:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
  self.footer:SetWidth(boardW)
  self.footer:SetTextColor(unpack(MUTED))

  self:CreateOverlay(boardW, boardH)
  self:CreateFx()
  return f
end

-- header and footer ------------------------------------------------------------

function Window:Refresh(game, opts)
  opts = opts or {}
  if not game then
    self.score:SetText("")
    self.best:SetText("")
    self.level:SetText("")
    self.combos:SetText("")
    return
  end
  self.score:SetText(Media.number(game.score))
  if opts.practice then
    self.best:SetText("practice")
  elseif opts.best and opts.best > 0 then
    self.best:SetText("best " .. Media.number(opts.best))
  else
    self.best:SetText("")
  end
  self.level:SetText("Level " .. game.level)
  if game.combosLeft then
    local n = math.max(0, game.combosLeft)
    self.combos:SetText(n == 1 and "1 match to the next level" or (n .. " matches to the next level"))
  else
    self.combos:SetText("top level, play forever")
  end
end

function Window:SetFooter(text)
  self.footer:SetText(text or "")
end

-- overlay --------------------------------------------------------------------

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 26)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

function Window:CreateOverlay(w, h)
  local o = CreateFrame("Frame", nil, self.frame)
  o:SetPoint("TOPLEFT", self.board.frame, "TOPLEFT")
  o:SetSize(w, h)
  o:SetFrameLevel(self.board.frame:GetFrameLevel() + 40)
  o:EnableMouse(true)
  o:Hide()
  local dim = solid(o, "BACKGROUND", { 0.03, 0.035, 0.05, 0.84 })
  dim:SetAllPoints()

  o.title = font(o:CreateFontString(nil, "ARTWORK"), 20)
  o.title:SetPoint("TOP", o, "TOP", 0, -70)
  o.title:SetWidth(w - 40)
  o.title:SetTextColor(1, 1, 1)

  o.body = font(o:CreateFontString(nil, "ARTWORK"), 12)
  o.body:SetPoint("TOP", o.title, "BOTTOM", 0, -12)
  o.body:SetWidth(w - 70)
  o.body:SetSpacing(3)
  o.body:SetTextColor(0.82, 0.84, 0.88)

  o.buttons = {}
  self.overlay = o
end

-- spec: { title, body, buttons = { { text, onClick } } }
function Window:ShowOverlay(spec)
  local o = self.overlay
  o.title:SetText(spec.title)
  o.body:SetText(spec.body or "")
  for _, b in ipairs(o.buttons) do b:Hide() end
  local n = #spec.buttons
  local width = n >= 3 and 92 or 150
  local gap = 10
  local total = n * width + (n - 1) * gap
  for i, info in ipairs(spec.buttons) do
    local b = o.buttons[i]
    if not b then
      b = button(o, "", width, nil)
      o.buttons[i] = b
    end
    b:SetSize(width, 26)
    b:SetText(info.text)
    b:SetScript("OnClick", info.onClick)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", o, "BOTTOM", -total / 2 + (i - 1) * (width + gap), 130)
    b:Show()
  end
  o:Show()
  self.board:StopHover()
end

function Window:HideOverlay()
  self.overlay:Hide()
end

function Window:OverlayShown()
  return self.overlay:IsShown()
end

-- toasts and score popups --------------------------------------------------------

function Window:CreateFx()
  local fx = CreateFrame("Frame", nil, self.frame)
  fx:SetAllPoints(self.board.frame)
  fx:SetFrameLevel(self.board.frame:GetFrameLevel() + 30)
  self.fx = fx

  local toast = font(fx:CreateFontString(nil, "OVERLAY"), 30, "OUTLINE")
  toast:SetPoint("CENTER", fx, "CENTER", 0, 20)
  toast:SetTextColor(1, 0.88, 0.5)
  toast:SetAlpha(0)
  local ag = toast:CreateAnimationGroup()
  local a1 = ag:CreateAnimation("Alpha")
  a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.18); a1:SetOrder(1)
  local a2 = ag:CreateAnimation("Alpha")
  a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.5); a2:SetStartDelay(0.9); a2:SetOrder(2)
  ag:SetScript("OnFinished", function() toast:SetAlpha(0) end)
  ag:SetScript("OnPlay", function() toast:SetAlpha(1) end)
  self.toast, self.toastAnim = toast, ag

  self.popups, self.popupNext = {}, 1
  for i = 1, 8 do
    local p = font(fx:CreateFontString(nil, "OVERLAY"), 15, "OUTLINE")
    p:SetAlpha(0)
    local g = p:CreateAnimationGroup()
    local mv = g:CreateAnimation("Translation")
    mv:SetOffset(0, 26); mv:SetDuration(0.9); mv:SetSmoothing("OUT")
    local fade = g:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(0.45); fade:SetStartDelay(0.45)
    g:SetScript("OnPlay", function() p:SetAlpha(1) end)
    g:SetScript("OnFinished", function() p:SetAlpha(0) end)
    p.anim = g
    self.popups[i] = p
  end
end

function Window:Toast(text, r, g, b)
  self.toast:SetText(text)
  self.toast:SetTextColor(r or 1, g or 0.88, b or 0.5)
  self.toastAnim:Stop()
  self.toastAnim:Play()
end

-- one floating "+points" per scoring event, at the middle of its cells
function Window:Popups(beat)
  for _, ev in ipairs(beat.events) do
    if ev.points and ev.points > 0 then
      local sx, sy, n = 0, 0, 0
      local cells = ev.cells or {}
      if ev.center then cells = { ev.center } end
      for _, cell in ipairs(cells) do
        local c = Grid.cells[cell]
        sx, sy, n = sx + c.x, sy + c.y, n + 1
      end
      if n > 0 then
        local p = self.popups[self.popupNext]
        self.popupNext = self.popupNext % #self.popups + 1
        p.anim:Stop()
        p:ClearAllPoints()
        p:SetPoint("CENTER", self.fx, "TOPLEFT", sx / n * SIZE, -sy / n * SIZE)
        p:SetText("+" .. Media.number(ev.points))
        if ev.kind == "flower" or ev.kind == "star" then
          p:SetTextColor(0.75, 0.85, 1)
        elseif ev.kind == "pearl" then
          p:SetTextColor(0.85, 0.7, 1)
        elseif ev.kind == "bonus" then
          p:SetTextColor(unpack(Media.BONUS_RGB))
        else
          p:SetTextColor(1, 1, 1)
        end
        p.anim:Play()
      end
    end
  end
end
