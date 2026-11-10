local ns, T, H = ...
local Detect, Pieces = ns.Detect, ns.Pieces
local describe, it, eq, ok = T.describe, T.it, T.eq, T.ok
local gem, star, pearl = Pieces.gem, Pieces.star, Pieces.pearl

local function clustersOf(found, cat)
  local out = {}
  for _, g in ipairs(found.clusters) do
    if g.cat == cat then out[#out + 1] = g end
  end
  return out
end

describe("detect", function()
  it("finds nothing on a blank board", function()
    local g = H.blank()
    ok(not Detect.find(g.board).any)
  end)

  it("a triangle of one color is a cluster of 3", function()
    local g = H.blank()
    H.put(g, 4, 5, gem(4)); H.put(g, 4, 6, gem(4)); H.put(g, 5, 5, gem(4))
    local found = Detect.find(g.board)
    local cs = clustersOf(found, "color")
    eq(#cs, 1)
    eq(#cs[1].cells, 3)
    eq(cs[1].color, 4)
  end)

  it("three in a straight line are not a cluster", function()
    local g = H.blank()
    H.put(g, 4, 3, gem(4)); H.put(g, 4, 4, gem(4)); H.put(g, 4, 5, gem(4))
    ok(not Detect.find(g.board).any)
  end)

  it("triangles sharing an edge merge into one cluster", function()
    local g = H.blank()
    H.put(g, 4, 5, gem(4)); H.put(g, 4, 6, gem(4)); H.put(g, 5, 5, gem(4)); H.put(g, 3, 5, gem(4))
    local cs = clustersOf(Detect.find(g.board), "color")
    eq(#cs, 1)
    eq(#cs[1].cells, 4)
  end)

  it("triangles sharing one piece merge too (proposal)", function()
    local g = H.blank()
    H.put(g, 4, 5, gem(4)); H.put(g, 4, 6, gem(4)); H.put(g, 5, 5, gem(4))
    H.put(g, 6, 5, gem(4)); H.put(g, 6, 6, gem(4))
    local cs = clustersOf(Detect.find(g.board), "color")
    eq(#cs, 1)
    eq(#cs[1].cells, 5)
  end)

  it("six of one color around a different center is a flower, not a cluster", function()
    local g = H.blank()
    H.put(g, 4, 4, gem(5))
    for _, cell in ipairs(H.ring(4, 4)) do ns.Game.place(g, cell, gem(4)) end
    local found = Detect.find(g.board)
    eq(#found.flowers, 1)
    eq(found.flowers[1].cat, "color")
    eq(found.flowers[1].center, H.id(4, 4))
    eq(#found.clusters, 0)
  end)

  it("a same-color center makes a 7-piece cluster instead (proposal)", function()
    local g = H.blank()
    H.put(g, 4, 4, gem(4))
    for _, cell in ipairs(H.ring(4, 4)) do ns.Game.place(g, cell, gem(4)) end
    local found = Detect.find(g.board)
    eq(#found.flowers, 0)
    eq(#found.clusters, 1)
    eq(#found.clusters[1].cells, 7)
  end)

  it("a flower claims its ring before clusters", function()
    local g = H.blank()
    H.put(g, 4, 4, gem(5))
    for _, cell in ipairs(H.ring(4, 4)) do ns.Game.place(g, cell, gem(4)) end
    H.put(g, 5, 2, gem(4)) -- touches N and NE of the ring, making a triangle with them
    local found = Detect.find(g.board)
    eq(#found.flowers, 1)
    eq(#found.clusters, 0)
  end)

  it("six starflowers around any center make a star ring", function()
    local g = H.blank()
    for _, cell in ipairs(H.ring(4, 4)) do ns.Game.place(g, cell, star()) end
    local found = Detect.find(g.board)
    eq(#found.flowers, 1)
    eq(found.flowers[1].cat, "star")
  end)

  it("six pearls around any center make a pearl ring", function()
    local g = H.blank()
    H.put(g, 4, 4, star())
    for _, cell in ipairs(H.ring(4, 4)) do ns.Game.place(g, cell, pearl(1)) end
    local found = Detect.find(g.board)
    eq(#found.flowers, 1)
    eq(found.flowers[1].cat, "pearl")
  end)

  it("three bonus gems of mixed colors are a bonus cluster only", function()
    local g = H.blank()
    H.put(g, 4, 5, gem(4, true)); H.put(g, 4, 6, gem(5, true)); H.put(g, 5, 5, gem(6, true))
    local found = Detect.find(g.board)
    eq(#clustersOf(found, "color"), 0)
    local b = clustersOf(found, "bonus")
    eq(#b, 1)
    eq(b[1].mono, nil)
  end)

  it("three bonus gems of one color are both a color and a bonus cluster", function()
    local g = H.blank()
    H.put(g, 4, 5, gem(4, true)); H.put(g, 4, 6, gem(4, true)); H.put(g, 5, 5, gem(4, true))
    local found = Detect.find(g.board)
    eq(#clustersOf(found, "color"), 1)
    local b = clustersOf(found, "bonus")
    eq(#b, 1)
    eq(b[1].mono, 4)
  end)

  it("starflower and pearl triangles are their own clusters", function()
    local g = H.blank()
    H.put(g, 4, 5, star()); H.put(g, 4, 6, star()); H.put(g, 5, 5, star())
    H.put(g, 7, 2, pearl(1)); H.put(g, 7, 3, pearl(2)); H.put(g, 8, 3, pearl(1))
    local found = Detect.find(g.board)
    eq(#clustersOf(found, "star"), 1)
    eq(#clustersOf(found, "pearl"), 1)
  end)

  it("anyNear agrees with find for a single change", function()
    local g = H.blank()
    H.put(g, 4, 5, gem(4)); H.put(g, 4, 6, gem(4))
    ok(not Detect.anyNear(g.board, { H.id(5, 5) }))
    H.put(g, 5, 5, gem(4))
    ok(Detect.anyNear(g.board, { H.id(5, 5) }))
  end)
end)
