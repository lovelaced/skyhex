-- Flight.lua
-- Knows when the player takes off and lands. UnitOnTaxi("player") decides; events only
-- say when to look. UnitOnTaxi turns true a moment after the flight master click, and
-- landing events are unreliable, so this polls: fast while boarding, once a second in
-- the air. See notes/research/forever-api.md section 1.

local _, ns = ...
local Flight = {}
ns.Flight = Flight

local state = "ground"   -- ground | boarding | flying
local inWorld = true
local boardingSince
local ticker
local hooks = {}

local function stopTicker()
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
end

local function startTicker(interval)
  stopTicker()
  ticker = C_Timer.NewTicker(interval, function() Flight.Check() end)
end

function Flight.IsFlying()
  return state == "flying"
end

function Flight.Check()
  if not inWorld then return end
  local onTaxi = UnitOnTaxi("player")
  if state ~= "flying" and onTaxi then
    state = "flying"
    startTicker(1)
    if hooks.onTakeoff then hooks.onTakeoff() end
  elseif state == "flying" and not onTaxi then
    state = "ground"
    stopTicker()
    if hooks.onLand then hooks.onLand() end
  elseif state == "boarding" and GetTime() - boardingSince > 10 then
    -- the flight was cancelled or never started
    state = "ground"
    stopTicker()
  end
end

local function boarding()
  if state == "ground" then
    state = "boarding"
    boardingSince = GetTime()
    startTicker(0.2)
  end
end

function Flight.Init(callbacks)
  hooks = callbacks
  if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", boarding) end

  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_CONTROL_LOST")
  f:RegisterEvent("PLAYER_CONTROL_GAINED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_LEAVING_WORLD")
  f:RegisterUnitEvent("UNIT_FLAGS", "player")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then
      inWorld = false
      return
    end
    if event == "PLAYER_ENTERING_WORLD" then
      inWorld = true
      -- after a login or /reload mid-flight, UnitOnTaxi can take a moment to settle
      boarding()
    elseif event == "PLAYER_CONTROL_LOST" then
      boarding()
    end
    Flight.Check()
  end)
end
