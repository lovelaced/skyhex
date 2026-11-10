-- Core.lua
-- Saved data, the run's lifecycle, input to moves, practice boards, flights and slash
-- commands. The run is account-wide: SkyhexDB.run is the engine's settled state, written
-- after every move so /reload and logout always have the latest board.

local addonName, ns = ...
local Game, Codec, Scenes, Grid, Media = ns.Game, ns.Codec, ns.Scenes, ns.Grid, ns.Media
local Core = {}
ns.Core = Core

local RECORD_KEYS = { "best", "bestLevel", "stars", "pearls", "defused", "wins", "losses", "runs", "flights", "moves" }

local db
local game                      -- the real run
local practice, practiceName, practiceMove
local window, board, player
local lastMove, shownScore = 0, 0

local function say(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff9fd3ffSkyhex|r " .. msg)
end
Core.say = say

local function active() return practice or game end

local function save()
  if db then db.run = game and Codec.encode(game) or nil end
end
Core.save = save

local function newSeed()
  return (time() * 1000 + math.floor(GetTime() * 1000)) % 2147483646 + 1
end

-- Lifetime totals take a run's stats when it ends or is abandoned.
local function bank(g)
  local r = db.records
  r.stars = r.stars + g.stats.stars
  r.pearls = r.pearls + g.stats.pearls
  r.defused = r.defused + g.stats.defused
  if g.over == "win" then r.wins = r.wins + 1 elseif g.over == "loss" then r.losses = r.losses + 1 end
end

-- footer: one useful line for what's on the board right now
local function tip(g)
  if practice then return Scenes.info[practiceName] .. " Close the window to go back to your run." end
  if not g or g.over then return "" end
  local lowBomb, star, pearl = false, false, false
  for id = 1, Grid.N do
    local p = g.board[id]
    if p.bomb and p.bomb <= 3 then lowBomb = true end
    if Grid.interior[id] then
      if p.kind == "star" then star = true elseif p.kind == "pearl" then pearl = true end
    end
  end
  if lowBomb then return "Match a bomb's color before its counter hits zero." end
  if pearl then return "Point at a black pearl to turn the three tiles its spokes touch." end
  if star then return "Point at a starflower to turn the six tiles around it." end
  if db.records.moves < 40 then return "Left click turns clockwise, right click the other way." end
  return ""
end

function Core.Refresh()
  local g = active()
  board.game = g
  window:Refresh(g, { practice = practice ~= nil, best = db.records.best })
  window:SetFooter(tip(g))
  if g then shownScore = g.score end
end

-- overlays ---------------------------------------------------------------------

function Core.AskNewRun(confirm)
  local buttons = {}
  for _, level in ipairs(Game.RULES.startLevels) do
    buttons[#buttons + 1] = { text = "Level " .. level, onClick = function() Core.NewRun(level) end }
  end
  local title, body
  if confirm then
    title = "Start over?"
    body = string.format("Your current run ends here with %s points. Pick a level to start a new one.", Media.number(game.score))
    buttons[#buttons + 1] = { text = "Keep playing", onClick = function() window:HideOverlay() end }
  else
    title = "Pick a starting level"
    body = "Level 1 eases you in. Bombs show up from level 3, and higher levels bring more colors and bigger scores."
  end
  window:ShowOverlay({ title = title, body = body, buttons = buttons })
end

local function count(n, one, many)
  return n .. " " .. (n == 1 and one or many)
end

local function runSummary(g)
  local r = db.records
  local s = g.stats
  local lines = {
    string.format("Final score %s on level %d.", Media.number(g.score), g.level),
    string.format("This run: %s, %s, %s.", count(s.stars, "starflower", "starflowers"),
      count(s.pearls, "black pearl", "black pearls"), count(s.defused, "bomb defused", "bombs defused")),
    string.format("Your best: %s.", Media.number(r.best)),
  }
  return table.concat(lines, "\n")
end

function Core.ShowOver(g)
  local title = g.over == "win" and "Black pearls touched. You won the run!" or "A bomb went off"
  window:ShowOverlay({
    title = title,
    body = runSummary(g),
    buttons = { { text = "Start a new run", onClick = function() Core.AskNewRun(false) end } },
  })
end

function Core.ShowPracticeOver(g)
  local title, body
  if g.over == "win" then
    title = "That's a win"
    body = "In a real run, touching black pearls end the run with a big bonus. Your real run is waiting."
  else
    title = "Boom"
    body = "In a real run, that bomb would end it. Your real run is safe."
  end
  window:ShowOverlay({
    title = title,
    body = body,
    buttons = {
      { text = "Try again", onClick = function() Core.Try(practiceName) end },
      { text = "Back to my run", onClick = function() Core.EndPractice() end },
    },
  })
end

-- runs ---------------------------------------------------------------------------

function Core.NewRun(level)
  player:Finish()
  if game and not game.over then bank(game) end
  game = Game.new({ seed = newSeed(), startLevel = level })
  db.records.runs = db.records.runs + 1
  lastMove = GetTime()
  save()
  window:HideOverlay()
  Core.ShowBoard()
end

function Core.ShowBoard()
  local g = active()
  board.game = g
  if g then board:Sync(g) end
  Core.Refresh()
  if not g then
    Core.AskNewRun(false)
  elseif g.over then
    if practice then Core.ShowPracticeOver(g) else Core.ShowOver(g) end
  else
    window:HideOverlay()
    if practice then board:ShowSelection(g, practiceMove, true) end
  end
end

function Core.OnClick(sel, button)
  local g = active()
  if not g or g.over or player:IsBusy() or window:OverlayShown() then return end
  local mv = { kind = sel.kind, index = sel.index, cell = sel.cell, dir = button == "RightButton" and -1 or 1 }
  local before = g.score
  local beats = Game.move(g, mv)
  if not beats then return end
  lastMove = GetTime()
  if g == game then
    local r = db.records
    r.moves = r.moves + 1
    if g.score > r.best then r.best = g.score end
    if g.level > r.bestLevel then r.bestLevel = g.level end
    if g.over then bank(g) end
    save()
  end
  shownScore = before
  player:Play(g, beats, function()
    Core.Refresh()
    if g.over and active() == g then
      if g == game then Core.ShowOver(g) else Core.ShowPracticeOver(g) end
    end
  end)
end

-- practice -----------------------------------------------------------------------

function Core.Try(name)
  if not Scenes.build[name] then
    say("Practice boards: " .. table.concat(Scenes.order, ", ") .. ". Try /skyhex try pearl")
    return
  end
  player:Finish()
  practice, practiceMove = Scenes.build[name](newSeed())
  practiceName = name
  if not window.frame:IsShown() then window.frame:Show() end
  Core.ShowBoard()
end

function Core.EndPractice()
  player:Finish()
  practice, practiceName, practiceMove = nil, nil, nil
  Core.ShowBoard()
end

-- window ---------------------------------------------------------------------------

function Core.Open()
  if window.frame:IsShown() then return end
  window.frame:Show()
  lastMove = GetTime()
  Core.ShowBoard()
end

function Core.Close()
  window.frame:Hide()
end

function Core.Toggle()
  if window.frame:IsShown() then Core.Close() else Core.Open() end
end

local function onHide()
  player:Finish()
  practice, practiceName, practiceMove = nil, nil, nil
  save()
end

-- after 20 quiet seconds, gently show a move that works
local function idleHint()
  if not window.frame:IsShown() or board.hovering or player:IsBusy() or window:OverlayShown() then return end
  local g = active()
  if not g or g.over or practice then return end
  if GetTime() - lastMove > 20 and not board.hinting then
    local mv = Game.hint(g)
    if mv then
      board:ShowSelection(g, mv, true)
      board.hinting = true
    end
  elseif GetTime() - lastMove <= 20 and board.hinting then
    board.hinting = false
  end
end

-- slash commands -------------------------------------------------------------------

local HELP = {
  "/skyhex  open or close the board",
  "/skyhex options  open Skyhex in the game's Options panel",
  "/skyhex auto on|off  open on its own when you take a flight",
  "/skyhex land hide|stay  put the board away when you land, or keep it open",
  "/skyhex gems modern|classic  pick a gem style",
  "/skyhex new  start a new run",
  "/skyhex scale 0.7-1.5  resize the window",
  "/skyhex sound on|off",
  "/skyhex reset  put the window back in the middle",
  "/skyhex try flower|pearl|bomb|wipe|win  practice boards that don't touch your run",
  "WoW writes your board to disk when you /reload or log out, so a game crash loses the moves since then.",
}

-- redraw every tile in the chosen gem style
function Core.SetGemStyle(style)
  db.gems = Media.SetStyle(style)
  for _, t in pairs(board.tiles) do
    if t.look then board:SetLook(t, t.look) end
  end
end

local function setScale(n)
  db.scale = n
  window.frame:SetScale(n)
end

local function slash(msg)
  local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" then
    Core.Toggle()
  elseif cmd == "auto" then
    if arg == "on" then
      db.auto = true
      say("will open on its own when you take a flight.")
    elseif arg == "off" then
      db.auto = false
      say("won't open on its own anymore. Type /skyhex to play.")
    else
      say("opens on its own when you fly: " .. (db.auto and "on" or "off") .. ". Use /skyhex auto on or /skyhex auto off.")
    end
  elseif cmd == "options" or cmd == "settings" then
    if not ns.Options.Open() then for _, line in ipairs(HELP) do say(line) end end
  elseif cmd == "land" then
    if arg == "hide" then
      db.hideOnLand = true
      say("will put the board away when you land.")
    elseif arg == "stay" then
      db.hideOnLand = false
      say("will keep the board open when you land.")
    else
      say("when you land, the board " .. (db.hideOnLand and "hides" or "stays open")
        .. ". Use /skyhex land hide or /skyhex land stay.")
    end
  elseif cmd == "gems" then
    if Media.GEM_SETS[arg] then
      Core.SetGemStyle(arg)
      say(arg .. " gems it is.")
    else
      say("gem style: " .. db.gems .. ". Use /skyhex gems modern or /skyhex gems classic.")
    end
  elseif cmd == "new" then
    Core.Open()
    if practice then Core.EndPractice() end
    if game and not game.over then Core.AskNewRun(true) else Core.AskNewRun(false) end
  elseif cmd == "scale" then
    local n = tonumber(arg)
    if n and n >= 0.7 and n <= 1.5 then
      setScale(n)
    else
      say("pick a scale from 0.7 to 1.5, like /skyhex scale 1.2")
    end
  elseif cmd == "sound" then
    db.sound = arg ~= "off"
    say("sound " .. (db.sound and "on" or "off") .. ".")
  elseif cmd == "reset" then
    db.point, db.scale = nil, 1
    window.frame:SetScale(1)
    window.frame:ClearAllPoints()
    window.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  elseif cmd == "try" then
    Core.Try(arg)
  else
    for _, line in ipairs(HELP) do say(line) end
  end
end

-- startup ------------------------------------------------------------------------

local function initDB()
  SkyhexDB = type(SkyhexDB) == "table" and SkyhexDB or {}
  db = SkyhexDB
  ns.db = db
  if db.auto == nil then db.auto = true end
  if db.sound == nil then db.sound = true end
  if type(db.hideOnLand) ~= "boolean" then db.hideOnLand = false end
  db.gems = Media.SetStyle(db.gems)
  if type(db.scale) ~= "number" or db.scale < 0.7 or db.scale > 1.5 then db.scale = 1 end
  db.records = type(db.records) == "table" and db.records or {}
  for _, k in ipairs(RECORD_KEYS) do
    if type(db.records[k]) ~= "number" then db.records[k] = 0 end
  end
  if db.run then
    local g, err = Codec.decode(db.run)
    if g then
      game = g
    else
      say("couldn't load your saved board (" .. tostring(err) .. "), so the next game starts fresh.")
      db.brokenRun, db.run = db.run, nil
    end
  end
end

local function build()
  window = ns.Window
  window:Create({
    onHide = onHide,
    onMoved = function(point, _, relPoint, x, y) db.point = { point, relPoint, x, y } end,
  })
  board = window.board
  board.onClick = Core.OnClick
  player = ns.Player.new(board, {
    onScore = function(beat)
      window:Popups(beat)
      shownScore = shownScore + (beat.points or 0)
      window.score:SetText(Media.number(shownScore))
    end,
    onLevel = function(level) window:Toast("Level " .. level) end,
    onShuffle = function() window:Toast("No matches left, reshuffled", 0.75, 0.85, 1) end,
  })
  local f = window.frame
  f:SetScale(db.scale)
  f:ClearAllPoints()
  local p = db.point
  if type(p) == "table" and p[1] then
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  C_Timer.NewTicker(1, idleHint)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" and name == addonName then
    self:UnregisterEvent("ADDON_LOADED")
    initDB()
    build()
    ns.Flight.Init({
      onTakeoff = function()
        db.records.flights = db.records.flights + 1
        if db.auto then Core.Open() end
      end,
      -- the board stays up after landing unless "Hide when you land" is on
      onLand = function()
        if db.hideOnLand and window.frame:IsShown() then Core.Close() end
        save()
      end,
    })
    ns.Options.Register(db, { onGems = Core.SetGemStyle, onScale = setScale })
    SLASH_SKYHEX1 = "/skyhex"
    SlashCmdList.SKYHEX = slash
  elseif event == "PLAYER_LOGOUT" then
    if db then save() end
  end
end)

-- addon compartment (TOC AddonCompartmentFunc*)
function Skyhex_OnAddonCompartmentClick()
  Core.Toggle()
end

function Skyhex_OnAddonCompartmentEnter(_, button)
  GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
  GameTooltip:SetText("Skyhex")
  local line = (db and db.auto) and "Click to play. Opens on its own when you fly." or "Click to play."
  GameTooltip:AddLine(line, 1, 1, 1, true)
  GameTooltip:Show()
end

function Skyhex_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end
