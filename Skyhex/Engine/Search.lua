-- Engine/Search.lua
-- Finds moves that would make a match. Used to reshuffle a board with no possible
-- match and to show a hint when the player is stuck.

local _, ns = ...
local Grid, Detect = ns.Grid, ns.Detect
local Search = {}
ns.Search = Search

local rotate, anyNear = Grid.rotate, Detect.anyNear

-- Rotate a cycle one step, check, rotate back. Returns true if that step matches.
local function tryStep(board, cycle, dir)
  rotate(board, cycle, dir)
  local hit = anyNear(board, cycle)
  rotate(board, cycle, -dir)
  return hit
end

-- Returns a list of { kind, index | cell, dir } that would make a match. A triad press
-- keeps turning, so a triad counts if either of its two non-trivial positions matches;
-- dir is whichever direction reaches the match in one step.
function Search.findMoves(board, firstOnly)
  local found = {}
  for i, t in ipairs(Grid.triads) do
    local dir
    if tryStep(board, t, 1) then
      dir = 1
    elseif tryStep(board, t, -1) then
      dir = -1
    end
    if dir then
      found[#found + 1] = { kind = "triad", index = i, dir = dir }
      if firstOnly then return found end
    end
  end
  for id = 1, Grid.N do
    local p = board[id]
    if Grid.interior[id] and p and (p.kind == "star" or p.kind == "pearl") then
      local cycle = p.kind == "star" and Grid.rings[id] or Grid.spokes(id, p.y)
      local kind = p.kind == "star" and "ring" or "pearl"
      for _, dir in ipairs({ 1, -1 }) do
        if tryStep(board, cycle, dir) then
          found[#found + 1] = { kind = kind, cell = id, dir = dir }
          if firstOnly then return found end
          break
        end
      end
    end
  end
  return found
end

function Search.hasMove(board)
  return #Search.findMoves(board, true) > 0
end
