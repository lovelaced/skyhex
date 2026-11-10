-- Engine/Rng.lua
-- Park-Miller minimal standard PRNG. The whole state is one integer, so it saves with
-- the run and a reloaded game keeps rolling the same pieces it would have rolled.
-- Products stay below 2^46, so plain Lua 5.1 doubles are exact.

local _, ns = ...
local Rng = {}
ns.Rng = Rng

local M = 2147483647

function Rng.new(seed)
  local s = math.floor(math.abs(tonumber(seed) or 1)) % M
  if s == 0 then s = 1 end
  return { s = s }
end

function Rng.next(r)
  r.s = (r.s * 16807) % M
  return r.s
end

-- uniform float in [0, 1)
function Rng.float(r)
  return (Rng.next(r) - 1) / (M - 1)
end

-- uniform integer in [1, n]
function Rng.int(r, n)
  return math.floor(Rng.float(r) * n) + 1
end

-- in-place Fisher-Yates shuffle of an array
function Rng.shuffle(r, t)
  for i = #t, 2, -1 do
    local j = Rng.int(r, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end
