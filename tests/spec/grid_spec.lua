local ns, T, H = ...
local Grid, Rng = ns.Grid, ns.Rng
local describe, it, eq, ok = T.describe, T.it, T.eq, T.ok

describe("grid", function()
  it("has 85 cells in 10 columns of 8 and 9", function()
    eq(Grid.N, 85)
    for c = 1, 10 do eq(Grid.rowsIn(c), c % 2 == 1 and 8 or 9, "column " .. c) end
    ok(Grid.id(1, 9) == nil, "short column has no row 9")
    ok(Grid.id(2, 9) ~= nil, "tall column has row 9")
  end)

  it("has 135 triads and 52 interior cells", function()
    eq(#Grid.triads, 135)
    local n = 0
    for _ in pairs(Grid.interior) do n = n + 1 end
    eq(n, 52)
    ok(Grid.interior[H.id(4, 4)], "(4,4) interior")
    ok(not Grid.interior[H.id(3, 1)], "short column top is not interior")
    ok(not Grid.interior[H.id(3, 8)], "short column bottom is not interior")
    ok(not Grid.interior[H.id(1, 4)], "edge column is not interior")
  end)

  it("neighbors are symmetric", function()
    for id = 1, Grid.N do
      for d = 1, 6 do
        local m = Grid.neighbors[id][d]
        if m ~= 0 then eq(Grid.neighbors[m][(d + 2) % 6 + 1], id, "opposite of " .. id .. " dir " .. d) end
      end
    end
  end)

  it("matches the documented neighbor table", function()
    -- even (tall) column (4,4): N (4,3), NE (5,3), SE (5,4), S (4,5), SW (3,4), NW (3,3)
    local ring = H.ring(4, 4)
    local want = { H.id(4, 3), H.id(5, 3), H.id(5, 4), H.id(4, 5), H.id(3, 4), H.id(3, 3) }
    for d = 1, 6 do eq(ring[d], want[d], "even dir " .. d) end
    -- odd (short) column (5,4): N (5,3), NE (6,4), SE (6,5), S (5,5), SW (4,5), NW (4,4)
    ring = H.ring(5, 4)
    want = { H.id(5, 3), H.id(6, 4), H.id(6, 5), H.id(5, 5), H.id(4, 5), H.id(4, 4) }
    for d = 1, 6 do eq(ring[d], want[d], "odd dir " .. d) end
  end)

  it("stores every triad as three mutual neighbors in clockwise order", function()
    for i, t in ipairs(Grid.triads) do
      ok(Grid.isAdjacent(t[1], t[2]) and Grid.isAdjacent(t[2], t[3]) and Grid.isAdjacent(t[1], t[3]), "triad " .. i)
      local a, b, c = Grid.cells[t[1]], Grid.cells[t[2]], Grid.cells[t[3]]
      local cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
      ok(cross > 0, "triad " .. i .. " is clockwise on screen (y down)")
    end
  end)

  it("tricolor is a proper coloring", function()
    for id = 1, Grid.N do
      for d = 1, 6 do
        local m = Grid.neighbors[id][d]
        if m ~= 0 then ok(Grid.tricolor(id) ~= Grid.tricolor(m), "cells " .. id .. "," .. m) end
      end
    end
  end)

  it("rotates a cycle clockwise and back", function()
    local board = { [1] = "a", [2] = "b", [3] = "c" }
    Grid.rotate(board, { 1, 2, 3 }, 1)
    eq(board[2], "a")
    eq(board[3], "b")
    eq(board[1], "c")
    Grid.rotate(board, { 1, 2, 3 }, -1)
    eq(board[1], "a")
  end)

  it("pearl spokes follow the two Y shapes", function()
    local ring = H.ring(4, 4)
    local s1, s2 = Grid.spokes(H.id(4, 4), 1), Grid.spokes(H.id(4, 4), 2)
    eq(s1[1], ring[1]); eq(s1[2], ring[3]); eq(s1[3], ring[5])
    eq(s2[1], ring[2]); eq(s2[2], ring[4]); eq(s2[3], ring[6])
    eq(Grid.spokes(H.id(1, 4), 1), nil, "edge pearl has no spokes")
  end)

  it("board is 15.5 by 9 sqrt 3 hex sizes and every center fits", function()
    eq(Grid.WIDTH, 15.5)
    for id = 1, Grid.N do
      local cell = Grid.cells[id]
      ok(cell.x >= 1 and cell.x <= Grid.WIDTH - 1, "x " .. id)
      ok(cell.y >= Grid.SQRT3 / 2 - 1e-9 and cell.y <= Grid.HEIGHT - Grid.SQRT3 / 2 + 1e-9, "y " .. id)
    end
  end)
end)

describe("rng", function()
  it("is deterministic and in range", function()
    local a, b = Rng.new(42), Rng.new(42)
    for _ = 1, 1000 do
      local x = Rng.int(a, 7)
      eq(x, Rng.int(b, 7))
      ok(x >= 1 and x <= 7)
    end
  end)

  it("covers every value", function()
    local r, seen = Rng.new(5), {}
    for _ = 1, 2000 do seen[Rng.int(r, 7)] = true end
    for i = 1, 7 do ok(seen[i], "value " .. i) end
  end)
end)
