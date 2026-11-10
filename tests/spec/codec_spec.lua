local ns, T = ...
local Game, Codec, Search = ns.Game, ns.Codec, ns.Search
local describe, it, eq, ok = T.describe, T.it, T.eq, T.ok

local function same(a, b)
  for k, v in pairs(a) do
    if type(v) == "table" then
      for kk, vv in pairs(v) do eq(b[k][kk], vv, k .. "." .. tostring(kk)) end
    else
      eq(b[k], v, k)
    end
  end
end

describe("codec", function()
  it("round-trips a fresh run", function()
    local g = Game.new({ seed = 99, startLevel = 3 })
    local t = Codec.encode(g)
    eq(#t.cells, 255)
    local g2 = assert(Codec.decode(t))
    same(t, Codec.encode(g2))
  end)

  it("a decoded run plays on exactly like the original", function()
    local a = Game.new({ seed = 12345, startLevel = 5 })
    for _ = 1, 20 do Game.move(a, Search.findMoves(a.board, true)[1]) end
    local b = assert(Codec.decode(Codec.encode(a)))
    for _ = 1, 30 do
      if a.over then break end
      local mv = Search.findMoves(a.board, true)[1]
      Game.move(a, mv)
      Game.move(b, mv)
    end
    same(Codec.encode(a), Codec.encode(b))
  end)

  it("keeps queued drops and stats", function()
    local g = Game.new({ seed = 3 })
    g.drops[4] = { ns.Pieces.star() }
    g.drops[4][1].id = 999
    g.stats.pearls = 2
    local g2 = assert(Codec.decode(Codec.encode(g)))
    eq(g2.drops[4][1].kind, "star")
    eq(g2.stats.pearls, 2)
  end)

  it("rejects damaged saves with a reason", function()
    local t = Codec.encode(Game.new({ seed = 1 }))
    local function bad(mut)
      local c = {}
      for k, v in pairs(t) do c[k] = v end
      mut(c)
      local g, err = Codec.decode(c)
      eq(g, nil)
      ok(type(err) == "string")
    end
    bad(function(c) c.v = 99 end)
    bad(function(c) c.cells = c.cells:sub(4) end)
    bad(function(c) c.cells = "x" .. c.cells:sub(2) end)
    bad(function(c) c.cells = "g9." .. c.cells:sub(4) end)
    bad(function(c) c.level = 8 end)
    bad(function(c) c.rng = 0 end)
    bad(function(c) c.combosLeft = -1 end) -- only level 7 may be endless
    bad(function(c) c.over = "maybe" end)
    eq(Codec.decode(nil), nil)
  end)
end)
