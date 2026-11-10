local ns, T, H = ...
local Scenes, Game, Detect = ns.Scenes, ns.Game, ns.Detect
local describe, it, eq, ok = T.describe, T.it, T.eq, T.ok

describe("practice scenes", function()
  for _, name in ipairs(Scenes.order) do
    it(name .. " starts settled and its move does the thing", function()
      local g, mv = Scenes.build[name](42)
      ok(not Detect.find(g.board).any, "no match before the move")
      local color1 = {}
      for id = 1, ns.Grid.N do
        local p = g.board[id]
        if p.kind == "gem" and p.color == 1 then color1[#color1 + 1] = p.id end
      end
      ok(Scenes.info[name], "has help text")
      local beats = assert(Game.move(g, mv))
      local steps = #H.beats(beats, "step")
      eq(steps, 1, "the suggested direction gets there in one step")
      if name == "flower" then eq(g.stats.stars, 1) end
      if name == "pearl" then eq(g.stats.pearls, 1) end
      if name == "bomb" then
        eq(g.stats.defused, 1)
        local dropped = false
        for _, b in ipairs(H.beats(beats, "fall")) do
          for _, sp in ipairs(b.spawns) do
            if sp.piece.bomb then dropped = true end
          end
        end
        ok(dropped, "a new bomb drops in as the old one is defused")
      end
      if name == "wipe" then
        local events = H.beats(beats, "clear")[1].events
        eq(events[#events].kind, "wipe")
        eq(#color1, 8)
        for _, pid in ipairs(color1) do eq(H.where(g, pid), nil, "color-1 gem " .. pid .. " wiped") end
      end
      if name == "win" then eq(g.over, "win") end
    end)
  end
end)
