local ns, T, H = ...
local Game, Pieces, Grid = ns.Game, ns.Pieces, ns.Grid
local describe, it, eq, ok = T.describe, T.it, T.eq, T.ok
local gem, star, pearl, bomb = Pieces.gem, Pieces.star, Pieces.pearl, Pieces.bomb

-- Shared layout: center X = (4,4) with ring N (4,3), NE (5,3), SE (5,4), S (4,5),
-- SW (3,4), NW (3,3). Triad T = (4,5) (4,6) (5,5) can swap a piece into the ring's S
-- slot from (4,6). Triad T2 = (5,5) (5,6) (6,6) can bring a piece into (5,5).
local function T1() return H.triad(H.id(4, 5), H.id(4, 6), H.id(5, 5)) end
local function T2() return H.triad(H.id(5, 5), H.id(5, 6), H.id(6, 6)) end

-- five ring pieces made by make(), S slot left for the move, sixth waiting at (4,6)
local function almostRing(g, make, center)
  H.put(g, 4, 4, center)
  for _, cell in ipairs(H.ring(4, 4)) do
    if cell ~= H.id(4, 5) then Game.place(g, cell, make()) end
  end
  H.put(g, 4, 5, gem(6))
  H.put(g, 4, 6, make())
end

-- (4,5) and (4,6) set, third piece at (5,6) that T2 turns into (5,5)
local function almostTriangle(g, a, b, c)
  H.put(g, 4, 5, a); H.put(g, 4, 6, b); H.put(g, 5, 6, c)
end

describe("scoring formulas", function()
  it("cluster points: 5 x (n-2) x 2^bonus x level", function()
    eq(Game.clusterPoints(3, 0, 1), 5)
    eq(Game.clusterPoints(4, 0, 1), 10)
    eq(Game.clusterPoints(5, 0, 1), 15)
    eq(Game.clusterPoints(22, 16, 7), 45875200)
  end)
end)

describe("triad moves", function()
  it("a full turn with no match puts everything back and still counts as a move", function()
    local g = H.blank()
    local before = H.snapshot(g)
    local beats = Game.move(g, { kind = "triad", index = 1, dir = 1 })
    eq(#H.beats(beats, "step"), 3)
    eq(#H.beats(beats, "clear"), 0)
    eq(g.moves, 1)
    local after = H.snapshot(g)
    for id = 1, Grid.N do eq(after[id], before[id], "cell " .. id) end
  end)

  it("stops at the first step that makes a match", function()
    local g = H.blank()
    almostTriangle(g, gem(4), gem(4), gem(4))
    local hint = Game.hint(g)
    ok(hint, "a hint exists")
    local beats = Game.move(g, hint)
    eq(#H.beats(beats, "step"), 1)
    eq(#H.beats(beats, "clear"), 1)
    eq(g.score, 5)
  end)

  it("both directions reach the match within two steps", function()
    for _, dir in ipairs({ 1, -1 }) do
      local g = H.blank()
      almostTriangle(g, gem(4), gem(4), gem(4))
      local beats = Game.move(g, { kind = "triad", index = T2(), dir = dir })
      ok(#H.beats(beats, "step") <= 2, "dir " .. dir)
      eq(g.score, 5, "dir " .. dir)
    end
  end)

  it("a bonus gem doubles the cluster and level multiplies it", function()
    local g = H.blank(3)
    almostTriangle(g, gem(4, true), gem(4), gem(4))
    Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(g.score, 5 * 2 * 3)
  end)

  it("rejects bad moves and moves after the run ends", function()
    local g = H.blank()
    local r, err = Game.move(g, { kind = "triad", index = 999, dir = 1 })
    eq(r, nil); eq(err, "invalid")
    local _, err2 = Game.move(g, { kind = "ring", cell = H.id(4, 4), dir = 1 })
    eq(err2, "invalid", "ring needs a starflower")
    g.over = "loss"
    local _, err3 = Game.move(g, { kind = "triad", index = 1, dir = 1 })
    eq(err3, "over")
  end)
end)

describe("cascades", function()
  it("pieces that fall into a new match clear again at full value", function()
    local g = H.blank()
    almostTriangle(g, gem(4), gem(4), gem(4))
    H.put(g, 4, 3, gem(7)); H.put(g, 4, 4, gem(7)); H.put(g, 5, 4, gem(7))
    local beats = Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(#H.beats(beats, "clear"), 2)
    eq(g.score, 10)
    eq(g.stats.bestChain, 2)
    ok(H.settled(g))
  end)
end)

describe("flowers", function()
  it("six gems around a gem turn the center into a starflower", function()
    for _, dir in ipairs({ 1, -1 }) do
      local g = H.blank()
      almostRing(g, function() return gem(4) end, gem(5))
      local centerId = g.board[H.id(4, 4)].id
      local beats = Game.move(g, { kind = "triad", index = T1(), dir = dir })
      eq(g.score, 1000, "dir " .. dir)
      local at = H.where(g, centerId)
      eq(at, H.id(4, 5), "the new starflower falls into the cleared S slot")
      eq(g.board[at].kind, "star")
      eq(#H.beats(beats, "clear")[1].transforms, 1)
      eq(g.stats.stars, 1)
      eq(g.combosLeft, 49)
      ok(H.settled(g))
    end
  end)

  it("bonus gems in the ring double the flower", function()
    local g = H.blank()
    local n = 0
    almostRing(g, function()
      n = n + 1
      return gem(4, n <= 2)
    end, gem(5))
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(g.score, 4000)
  end)

  it("around a starflower: it stays and a new one drops in", function()
    local g = H.blank()
    almostRing(g, function() return gem(4) end, star())
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(g.score, 1500)
    eq(H.countKind(g, "star"), 2)
  end)

  it("around a pearl: the pearl stays and a starflower drops in (proposal)", function()
    local g = H.blank()
    almostRing(g, function() return gem(4) end, pearl(1))
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(g.score, 2500)
    eq(H.countKind(g, "star"), 1)
    eq(H.countKind(g, "pearl"), 1)
  end)

  it("a bomb at the center is defused and becomes the starflower (proposal)", function()
    local g = H.blank(3)
    almostRing(g, function() return gem(4) end, bomb(5, 4))
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(#H.bombs(g), 0)
    eq(H.countKind(g, "star"), 1)
    eq(g.stats.defused, 1)
  end)
end)

describe("black pearls", function()
  it("six starflowers around a gem make a black pearl", function()
    local g = H.blank()
    almostRing(g, star, gem(5))
    local centerId = g.board[H.id(4, 4)].id
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(g.score, 10000)
    local at = H.where(g, centerId)
    eq(g.board[at].kind, "pearl")
    ok(g.board[at].y == 1 or g.board[at].y == 2, "pearl has a Y type")
    eq(H.countKind(g, "star"), 0)
    eq(g.stats.pearls, 1)
  end)

  it("six starflowers around a starflower make a pearl too", function()
    local g = H.blank()
    almostRing(g, star, star())
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(g.score, 10000)
    eq(H.countKind(g, "pearl"), 1)
    eq(H.countKind(g, "star"), 0)
  end)

  it("six starflowers around a pearl drop a new pearl", function()
    local g = H.blank()
    almostRing(g, star, pearl(2))
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(g.score, 15000)
    eq(H.countKind(g, "pearl"), 2)
  end)

  it("a pearl turns its three spokes one step", function()
    local g = H.blank()
    H.put(g, 4, 4, pearl(1))
    local ring = H.ring(4, 4)
    local n_ = H.put(g, 4, 3, gem(1)).id
    local se = H.put(g, 5, 4, gem(2)).id
    local sw = H.put(g, 3, 4, gem(3)).id
    local beats = Game.move(g, { kind = "pearl", cell = H.id(4, 4), dir = 1 })
    eq(#H.beats(beats, "step"), 1)
    eq(H.where(g, n_), ring[3], "N went to SE")
    eq(H.where(g, se), ring[5], "SE went to SW")
    eq(H.where(g, sw), ring[1], "SW went to N")
    eq(g.board[H.id(4, 4)].kind, "pearl")
    eq(g.moves, 1)
  end)

  it("the other pearl type turns NE, S, NW", function()
    local g = H.blank()
    H.put(g, 4, 4, pearl(2))
    local ring = H.ring(4, 4)
    local ne = g.board[ring[2]].id
    Game.move(g, { kind = "pearl", cell = H.id(4, 4), dir = -1 })
    eq(H.where(g, ne), ring[6], "counterclockwise NE went to NW")
  end)

  it("three touching pearls win the run", function()
    local g = H.blank()
    almostTriangle(g, pearl(1), pearl(2), pearl(1))
    local beats = Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(g.over, "win")
    eq(g.score, 25000)
    eq(beats[#beats].t, "over")
    eq(beats[#beats].result, "win")
  end)

  it("a ring of six pearls wins: 200,000 around a gem, 250,000 around a special", function()
    local g = H.blank()
    almostRing(g, function() return pearl(1) end, gem(5))
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(g.over, "win")
    eq(g.score, 200000)

    g = H.blank(2)
    almostRing(g, function() return pearl(1) end, star())
    Game.move(g, { kind = "triad", index = T1(), dir = 1 })
    eq(g.score, 500000)
  end)
end)

describe("starflower ring moves", function()
  it("turns all six neighbors one step", function()
    local g = H.blank()
    H.put(g, 4, 4, star())
    local ring, ids = H.ring(4, 4), {}
    for i, cell in ipairs(ring) do ids[i] = Game.place(g, cell, gem(i)).id end
    local beats = Game.move(g, { kind = "ring", cell = H.id(4, 4), dir = 1 })
    eq(#H.beats(beats, "step"), 1)
    for i = 1, 6 do eq(H.where(g, ids[i]), ring[i % 6 + 1], "piece " .. i) end
  end)

  it("does nothing for a starflower on the edge", function()
    local g = H.blank()
    H.put(g, 1, 4, star())
    local r, err = Game.move(g, { kind = "ring", cell = H.id(1, 4), dir = 1 })
    eq(r, nil); eq(err, "invalid")
  end)

  it("three touching starflowers clear for 2,500 each extra piece", function()
    local g = H.blank()
    almostTriangle(g, star(), star(), star())
    Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(g.score, 2500)
    eq(H.countKind(g, "star"), 0)
  end)
end)

describe("bonus gems", function()
  it("three of one color score as cluster and bonus cluster and blast their neighbors (proposal)", function()
    local g = H.blank()
    almostTriangle(g, gem(4, true), gem(4, true), gem(4, true))
    local beats = Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(g.score, 40 + 100)
    local tri, touched = { H.id(4, 5), H.id(4, 6), H.id(5, 5) }, {}
    for _, id in ipairs(tri) do
      touched[id] = true
      for d = 1, 6 do
        local m = Grid.neighbors[id][d]
        if m ~= 0 then touched[m] = true end
      end
    end
    local n = 0
    for _ in pairs(touched) do n = n + 1 end
    eq(#H.beats(beats, "clear")[1].cleared, n)
  end)

  it("three of mixed colors only score", function()
    local g = H.blank()
    almostTriangle(g, gem(4, true), gem(5, true), gem(6, true))
    local beats = Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(g.score, 100)
    eq(#H.beats(beats, "clear")[1].cleared, 3)
  end)
end)

describe("bombs", function()
  it("tick once per move and end the run at zero", function()
    local g = H.blank(3)
    local b = H.put(g, 8, 4, bomb(4, 2))
    Game.move(g, { kind = "triad", index = 1, dir = 1 })
    eq(b.bomb, 1)
    eq(g.over, nil)
    local beats = Game.move(g, { kind = "triad", index = 1, dir = 1 })
    eq(g.over, "loss")
    eq(beats[#beats].t, "over")
    eq(beats[#beats].cell, H.id(8, 4))
  end)

  it("are defused by matching their color", function()
    local g = H.blank(3)
    almostTriangle(g, bomb(4, 3), gem(4), gem(4))
    Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(#H.bombs(g), 0)
    eq(g.stats.defused, 1)
    eq(g.over, nil)
  end)

  it("defused with a bonus gem of their color wipe that color off the board", function()
    local g = H.blank(3)
    almostTriangle(g, bomb(4, 3), gem(4, true), gem(4))
    local far = { H.put(g, 1, 1, gem(4)).id, H.put(g, 9, 7, gem(4)).id, H.put(g, 8, 2, gem(4, true)).id }
    local beats = Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    for _, id in ipairs(far) do eq(H.where(g, id), nil, "far gem " .. id .. " wiped") end
    local events = H.beats(beats, "clear")[1].events
    eq(events[#events].kind, "wipe")
    eq(g.score, 10 * 3, "wiped gems give no points")
  end)

  it("arrive after the combo interval with a fresh countdown that skips this move", function()
    local g = H.blank(3)
    g.bombCombo = 14
    almostTriangle(g, gem(4), gem(4), gem(4))
    Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    local bombs = H.bombs(g)
    eq(#bombs, 1)
    eq(bombs[1].bomb, 9)
    eq(g.bombCombo, 0)
    Game.move(g, { kind = "triad", index = 1, dir = 1 })
    eq(bombs[1].bomb, 8)
  end)

  it("do not arrive before level 3", function()
    local g = H.blank(2)
    g.bombCombo = 14
    almostTriangle(g, gem(4), gem(4), gem(4))
    Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(#H.bombs(g), 0)
  end)
end)

describe("levels", function()
  it("level up when the combo count runs out", function()
    local g = H.blank()
    g.combosLeft = 1
    almostTriangle(g, gem(4), gem(4), gem(4))
    local beats = Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(g.level, 2)
    eq(g.combosLeft, 60)
    eq(#H.beats(beats, "level"), 1)
  end)

  it("level 7 is endless", function()
    local g = H.blank(6)
    g.combosLeft = 1
    almostTriangle(g, gem(4), gem(4), gem(4))
    Game.move(g, { kind = "triad", index = T2(), dir = 1 })
    eq(g.level, 7)
    eq(g.combosLeft, nil)
  end)
end)

describe("no possible match", function()
  it("reshuffles normal gems for free and leaves specials in place", function()
    local g = H.blank(3)
    g.noShuffle = nil
    local s = H.put(g, 4, 4, star())
    local b = H.put(g, 8, 4, bomb(4, 5))
    local beats = Game.move(g, { kind = "triad", index = 1, dir = 1 })
    local sh = H.beats(beats, "shuffle")
    eq(#sh, 1)
    ok(sh[1].ok, "found a playable layout")
    eq(H.where(g, s.id), H.id(4, 4), "starflower stays")
    eq(H.where(g, b.id), H.id(8, 4), "bomb stays")
    ok(H.settled(g))
    ok(Game.hint(g), "has a move after the shuffle")
  end)
end)

describe("fresh boards", function()
  it("start settled with a possible move and the right colors", function()
    for seed = 1, 30 do
      for _, level in ipairs({ 1, 3, 5 }) do
        local g = Game.new({ seed = seed, startLevel = level })
        local okSettled, why = H.settled(g)
        ok(okSettled, why)
        ok(Game.hint(g), "has a move")
        for id = 1, Grid.N do
          local p = g.board[id]
          ok(p.kind == "gem" and p.color >= 1 and p.color <= Game.RULES.colors[level], "color in range")
          if level == 1 then ok(not p.bonus, "no bonus gems on level 1") end
        end
      end
    end
  end)
end)
