# WoW: Forever API notes for a flight-path hex puzzle

Research date: 2026-11-09. Primary target: WoW: Forever, client and UI source both at **1.60.1.70862** (TOC 16001, game type `camelot`). Secondary: Classic Era 1.15.9.70576 (11509), TBC Anniversary 2.5.6.70577 (20506), Mists Classic 5.5.4.70631 (50504). Build numbers come from `/Applications/World of Warcraft/.build.info` and the Gethe branch heads.

This builds on `~/git/perl-infinity/notes/research/research-forever-api.md` (cited `PI/`), which covers secret values, project constants and TOC basics in depth. Read its sections 0, 1.4 and 5.1 first; they are not repeated here.

## How to read the citations

| Prefix | Meaning |
|---|---|
| `BZ/` | Blizzard UI source, Gethe/wow-ui-source `forever` branch, commit `9dc84f0 "1.60.1 (70862)"`, `Interface/AddOns/`. Shallow clone at `scratchpad/wow-ui-forever/` (8.4 MB download) |
| `DOC/` | `BZ/Blizzard_APIDocumentationGenerated/` |
| `TAGS` | `~/git/perl-infinity/tests/harness/api_tags.lua` (generated from DOC at 70338; the taxi, input, texture and animation entries quoted here match 70862's DOC) |
| `BIN` | `strings -a` of `/Applications/World of Warcraft/_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft` (70862). Line numbers refer to `scratchpad/bin/forever_strings.txt` |
| `BIN-ERA`, `BIN-ANN`, `BIN-MOP` | the same check on the `_classic_era_`, `_anniversary_` and `_classic_` client binaries |
| `ERA/` | single files fetched from the Gethe `classic_era` branch (1.15.9.70576) |
| `IF/` | InFlight by LudiusMaximus (MIT), `InFlight.lua` at GitHub `main` as of 2026-11-04, TOC `## Interface: 120105, 16001, 50504, 20506, 11509`. The most mature taxi-tracking code that runs on Forever |
| `WEB` | URL inline |

Confidence: **High** = stated in Blizzard source, docs or the binary, or shown by working shipping code. **Medium** = inferred from source plus prior art. **Low** = inference only; verify in game.

---

## 0. The short version

1. **Taxi detection: poll `UnitOnTaxi("player")`, and use events only to decide when to poll.** `UnitOnTaxi` is plain (no secret tags), exists on every flavor, and Blizzard's own code trusts it. It does lag `TakeTaxiNode` by up to a few seconds, and InFlight treats `PLAYER_CONTROL_GAINED` as unreliable for landing. `hooksecurefunc("TakeTaxiNode", ...)` gives you the destination name and hop count while the map is still open. No API returns flight duration.
2. **Hex tiles: ship your own hexagon mask TGA.** Neither the client nor the UI source has a usable hex atlas or texture (the only hex file in the source is an unreferenced dev PNG). `CreateMaskTexture` + `AddMaskTexture` work on all four flavors. Put each tile in its own small frame so the mask moves with the icon. Drive movement with one OnUpdate tween loop that only runs while something is moving.
3. **Icons:** seven vanilla gem icons that differ in outline as well as hue: ruby heart, opal chunk, topaz crown, emerald square, crystal columns, amethyst kite, white pearl. `spell_nature_wispsplode` is the star, `inv_misc_bomb_01` the bomb, and Black Pearl (7971) uses `inv_misc_gem_pearl_01`. All are vanilla files with fileIDs (section 3). Red, orange, yellow and green collapse under red-green colorblindness, so outline does most of the work and a glyph overlay option is worth planning.
4. **Input:** a single board frame with `GetCursorPosition()` / effective scale and hex math beats 100 overlapping rectangular buttons. Mouse and wheel are unrestricted. `SetPropagateKeyboardInput` is blocked for addon code in combat on all flavors, so keyboard support has to degrade gracefully.
5. **Persistence:** SavedVariables are written only on logout, `/reload` and clean exit. A crash mid-flight loses everything since the last write, and there is no flush API.
6. **TOC:** one TOC with `## Interface: 16001, 11509, 20506, 50504` and no `AllowLoadGameType` line loads on all four clients. The Classic binaries don't recognize `camelot` or `forever`, which matters if you ever add Forever-only file lines.

---

## 1. Taxi detection

### 1.1 What exists

| API / event | Status on Forever 70862 | Citation | Conf. |
|---|---|---|---|
| `UnitOnTaxi(unit)` → bool | Documented, no `SecretReturns`/`SecretWhen*` tag. `AllowedWhenUntainted` only concerns secret *arguments*; `"player"` isn't one | `DOC/UnitDocumentation.lua:2570`; `TAGS` | High |
| Blizzard trusts it at control loss | `GameEvent.HandlePlayerControlLost`: `if UnitOnTaxi("player") then return true end; CloseAllWindows_WithExceptions()`. So by the time `PLAYER_CONTROL_LOST` dispatches for a flight, `UnitOnTaxi` is already true (otherwise every flight would close all windows) | `BZ/Blizzard_Game/Shared/EventImplementation.lua:168-174`, routed at `Shared/EventRouting.lua:61`; this Shared file loads on camelot (`Blizzard_Game.toc`) | High (code), Medium (implied ordering) |
| `PLAYER_CONTROL_LOST`, `PLAYER_CONTROL_GAINED` | Documented, no payload, LossOfControl system. Also fire for fear, stun, mind control | `DOC/LossOfControlDocumentation.lua:134,140`; WEB https://warcraft.wiki.gg/wiki/PLAYER_CONTROL_LOST ("when afflicted by fear, mind controlled, or when using a taxi") | High |
| `TAXIMAP_OPENED(system)`, `TAXIMAP_CLOSED` | Documented. `TAXIMAP_CLOSED` fires whether or not a flight was taken, so it can't tell you a flight started | `DOC/TaxiMapDocumentation.lua:70`; `BZ/Blizzard_FlightMap/Blizzard_FlightMap.lua:114`, `BZ/Blizzard_UIPanels_Game/Shared/TaxiFrame.lua:129` | High |
| `TakeTaxiNode(slot)` | Not in DOC (legacy C function) but registered in the binary's `TaxiMapFrame.cpp` cluster with `SetTaxiMap, GetTaxiMapID, NumTaxiNodes, TaxiNodeName, TaxiNodePosition, TaxiNodeCost, TakeTaxiNode, CloseTaxiMap, TaxiNodeGetType, TaxiGetNodeSlot, TaxiGetSrcX/Y, TaxiGetDestX/Y, GetNumRoutes, TaxiIsDirectFlight` | `BIN` 735919-735934 | High |
| Who calls `TakeTaxiNode` on camelot | Both map UIs: the classic-style `TaxiFrame` (`Shared/TaxiFrame.xml:16`, loaded for `mainline, cata, mists` per `Blizzard_UIPanels_Game.toc:134,136`) and the Mainline `FlightMapFrame` pins (`Blizzard_FlightMap/FM_FlightPathDataProvider.lua:233-238`). Which one opens depends on `uiMapSystem` (`Blizzard_Game/Mainline/EventImplementation.lua:735-741`) | as cited | High |
| `TaxiNodeName(slot)`, `TaxiNodeGetType(slot)` (`"CURRENT"`, `"REACHABLE"`, `"DISTANT"`, `"UNREACHABLE"`, `"NONE"`), `GetNumRoutes(slot)`, `TaxiGetNodeSlot(slot, hop, isSource)` | Used by Blizzard's taxi tooltip code on Forever. Valid only while the taxi map is open (slots index the open map) | `BZ/Blizzard_UIPanels_Game/Shared/TaxiFrame.lua:135-182`; `BIN` "Usage: TaxiNodeName(slot)", "Invalid taxi node slot" | High |
| `C_TaxiMap.GetAllTaxiNodes(uiMapID)` → `{nodeID, slotIndex, name, state, ...}`, `GetTaxiMapID()` | Stable `nodeID` per flight master, so you can key learned durations by `src → dst` node IDs | `DOC/TaxiMapDocumentation.lua:11`; `TAGS` `TaxiNodeInfo`; `IF/InFlight.lua:280-287` | High |
| `TaxiRequestEarlyLanding()` | Present; Blizzard's leave-vehicle button calls it when on a taxi | `BZ/Blizzard_ActionBar/Shared/VehicleLeaveButton.lua:55-56` | High |
| `UNIT_FLAGS(unit)` | Documented, plain payload. Whether it fires for the taxi flag change is unverified | `DOC/UnitDocumentation.lua:4269` | Low (as a taxi signal) |
| `PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)`, `PLAYER_LEAVING_WORLD` | Standard | `TAGS` | High |

### 1.2 Timing: is `UnitOnTaxi` delayed after `TakeTaxiNode`?

Yes. InFlight starts its bar on `TakeTaxiNode`, then polls: `if takeoff then -- check if actually in flight after take off (doesn't happen immediately) if UnitOnTaxi("player") then ... elseif totalTime > 5 then <give up>` (`IF/InFlight.lua:1651-1662`). It also re-checks `UnitOnTaxi` every update during the flight with the comment `-- event bug fix` (`:1670`), and only treats `PLAYER_CONTROL_GAINED` as a nudge to run that check (`:1801-1817`). Expect a sub-second to roughly 2 second gap between the click and `UnitOnTaxi` turning true, and don't trust any single event for landing. (Medium: prior art, not measured here.)

A second reason not to trust the hook alone: InFlight **replaces** the global `TakeTaxiNode` with a wrapper that can show a "confirm flight" popup before calling through (`IF/InFlight.lua:1243-1300`). If your `hooksecurefunc` wraps that wrapper, your hook fires even when the player then cancels. Polling `UnitOnTaxi` with a timeout covers it. (High: code.)

### 1.3 Recommended approach

A three-state machine (`ground` → `boarding` → `flying`) where every event just calls `check()`:

```lua
local state, inWorld, pending = "ground", true, nil
local ticker

local function stopTicker() if ticker then ticker:Cancel(); ticker = nil end end
local function startTicker(interval) stopTicker(); ticker = C_Timer.NewTicker(interval, function() Skyhex.Check() end) end

function Skyhex.Check()
  if not inWorld then return end                      -- loading screen: hold state
  local onTaxi = UnitOnTaxi("player")
  if state ~= "flying" and onTaxi then
    state = "flying"; startTicker(1.0)                  -- keep polling for landing
    Skyhex:OnFlightStart(pending)                        -- open board, restore saved game
  elseif state == "flying" and not onTaxi then
    state, pending = "ground", nil; stopTicker()
    Skyhex:OnLanded()                                    -- pause, snapshot, hide board
  elseif state == "boarding" and GetTime() - pending.t > 10 then
    state, pending = "ground", nil; stopTicker()        -- cancelled or never took off
  end
end

hooksecurefunc("TakeTaxiNode", function(slot)            -- post-hook: no taint to Blizzard
  pending = { t = GetTime(), dstName = TaxiNodeName(slot), hops = GetNumRoutes(slot) }
  for i = 1, NumTaxiNodes() do
    if TaxiNodeGetType(i) == "CURRENT" then pending.srcName = TaxiNodeName(i) break end
  end
  if state == "ground" then state = "boarding"; startTicker(0.2) end
end)
-- events: PLAYER_CONTROL_LOST, PLAYER_CONTROL_GAINED -> Check()
--         PLAYER_LEAVING_WORLD -> inWorld = false
--         PLAYER_ENTERING_WORLD -> inWorld = true; Check(); on login also poll ~5 s
--         RegisterUnitEvent("UNIT_FLAGS", "player") -> Check() (cheap extra trigger)
```

Why this mix: `PLAYER_CONTROL_LOST` catches flights that never touch the map (gossip or quest flights), the hook adds destination info, and the poll handles both the takeoff lag and missed landing events. Cost is one `UnitOnTaxi` call per second in flight. (Medium-High.)

### 1.4 Loading screens, `/reload`, logout

| Case | What happens | Citation | Conf. |
|---|---|---|---|
| `/reload` mid-flight | `PLAYER_ENTERING_WORLD(false, true)` fires with `UnitOnTaxi("player")` already true; InFlight recovers its bar on exactly that condition. `GetTime()` keeps running across a reload | `IF/InFlight.lua:1487-1557` | Medium-High |
| Loading screen during a flight | `PLAYER_LEAVING_WORLD` then `PLAYER_ENTERING_WORLD`; InFlight pauses its checks while out of the world and shifts its start time | `IF/InFlight.lua:1782-1797` | Medium (rare or absent on vanilla routes) |
| Logout mid-flight | InFlight: "After a logout the flight is paused while GetTime() is not, and no API tells us how much of the flight is left." On login the flight resumes; `GetTime()` resets on client restart | `IF/InFlight.lua:1495-1510` | Medium |
| Board open before takeoff | If `UnitOnTaxi` were still false when `PLAYER_CONTROL_LOST` dispatched, Blizzard would close all `UISpecialFrames`, including yours. Open the board on detection, not before | `BZ/Blizzard_Game/Shared/EventImplementation.lua:168-174`, `BZ/Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:1133-1188` | Medium |

So: on any `PLAYER_ENTERING_WORLD`, call `Check()`, and after an initial login poll for a few seconds before concluding "not flying". Store wall-clock `time()` rather than `GetTime()` for anything that must survive a restart.

### 1.5 Destination and duration

* **Destination:** yes, from the hook: `TaxiNodeName(slot)` and the source via `TaxiNodeGetType(i) == "CURRENT"`. Stable IDs via `C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())` matched on `slotIndex` (`IF/InFlight.lua:280-287`, `1255-1272`). Not available for flights that skip the map. (High)
* **Hops:** `GetNumRoutes(slot)`; per-hop nodes via `TaxiGetNodeSlot(slot, hop, true)` (`BZ/.../Shared/TaxiFrame.lua:142,176-179`). (High)
* **Duration:** no API. The binary's taxi cluster has no time or speed getter (`BIN` 735919-735934), and InFlight ships a 474 KB table of measured times (`Defaults.lua`) plus per-hop estimation (`IF/InFlight.lua:599-660`). It notes Forever's times "are not known yet at all" (`:897-901`). If the game wants a "landing in about 2 min" hint, record `src nodeID → dst nodeID → seconds` yourself in SavedVariables after each completed flight. InFlight is MIT, so its vanilla table could seed this with attribution, but Forever flight speeds are unconfirmed. (High for "no API"; Low for reusing vanilla times.)

### 1.6 Secrets and taint

Nothing in the taxi path is secret: `UnitOnTaxi` has no secret tags, and the legacy taxi functions predate the secret system and return plain strings and numbers (Blizzard's tooltip code does arithmetic on `TaxiNodePosition` results, `Shared/TaxiFrame.lua:71-73`). `hooksecurefunc` is a post-hook and doesn't taint Blizzard's caller. Don't replace `TakeTaxiNode` the way InFlight does; it is not protected, so that works, but it makes Blizzard's map click run through addon code. None of the six restriction types (`PI/` 1.1) relate to flying. (High)

### 1.7 Classic Era, Anniversary, Mists

All three binaries carry `UnitOnTaxi`, `TakeTaxiNode`, `TaxiNodeName`, `GetNumRoutes`, `TaxiGetNodeSlot`, `TaxiNodeGetType`, `NumTaxiNodes`, `GetTaxiMapID`, `C_TaxiMap`/`GetAllTaxiNodes`, `TaxiRequestEarlyLanding`, `PLAYER_CONTROL_LOST/GAINED` and `TAXIMAP_OPENED/CLOSED` (`BIN-ERA`, `BIN-ANN`, `BIN-MOP`). Their UI uses `Classic/TaxiFrame.lua` plus `Shared/TaxiFrame.lua` (Gethe `classic_era`, `classic_anniversary`, `classic` trees), and InFlight runs the same detection code on 11509/20506/50504. The same state machine works unchanged. (High for presence, Medium for identical behavior.)

---

## 2. Drawing hex tiles

### 2.1 No built-in hex asset

| Search | Result | Conf. |
|---|---|---|
| Every `"..."` string containing `hex` in `BZ/**/*.lua, *.xml` | Only color-hex helpers (`ColorPickerHexBoxMixin`, `ITEM_QUALITY_COLORS[q].hex`). No hex atlas or texture path | High |
| File names containing `hex` in the 4501-file tree | `Blizzard_SharedTalentUI/talents-hexagon-mask.png` (64×64 RGBA, flat-top hexagon). Not referenced by any Lua, XML or TOC, and PNG isn't a texture format the client loads (`BIN` `Texture.cpp` tries `.blp`/`.jpg`; `.tga` sits with the font code; `.png` only appears in an HTTP MIME table at 758202). Treat it as a reference drawing, not an asset | High |
| Masks Blizzard does use | `talents-node-circle-mask`, `talents-node-choice-mask` (octagon), `ui-journeys-delve-rewardicon-octagon-mask`, and the file mask `Interface\CharacterFrame\TempPortraitAlphaMask` (circle, 113 references, present on every flavor) | High |

Atlas names live in client data, not the source. To confirm Forever has no hexagonal atlas, run in game: `/run local n=0 for _,a in ipairs(C_Texture.GetAtlasElements()) do if a:lower():find("hex") then print(a) n=n+1 end end print(n)` (`DOC/TextureUtilsDocumentation.lua:36`).

### 2.2 Masks with an addon-shipped TGA

* `Frame:CreateMaskTexture(name, layer, template, subLevel)` and `Texture:AddMaskTexture(mask)` / `RemoveMaskTexture` are documented on Forever (`DOC/SimpleFrameAPIDocumentation.lua:113`, `DOC/SimpleTextureAPIDocumentation.lua:10`) and present in all three Classic binaries. (High)
* Blizzard's pattern: `mask:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")`, mask created as a sibling region in the same frame, then `icon:AddMaskTexture(mask)` (`BZ/Blizzard_PVPUI/Mainline/Blizzard_PVPUI.xml:346`; pooled creation in `BZ/Blizzard_SharedXMLBase/Pools.lua:594`). The mask's alpha channel is what clips. (High)
* Addon files work as mask textures the same way as any `SetTexture` path; this is common retail practice (Medium-High: not shown in Blizzard source, since Blizzard never loads from addon folders). Use a 32-bit TGA with alpha, power-of-two size (64×64 or 128×128), uncompressed.
* Masks are regions: if you animate only the icon texture, the mask stays put and clips it. Animate or move the parent frame instead. (Medium)
* Forever's talent trees render roughly a hundred masked node icons at once (`Blizzard_SharedTalentUI` loads on camelot, `Blizzard_SharedTalentUI.toc:40`), so ~100 masked tiles is within what Blizzard ships. (Medium)
* Alternative with no custom mask: a hex "socket" TGA behind each tile with the gem icon clipped to a circle by `TempPortraitAlphaMask`. Reads well and works everywhere. (High)
* `Texture:SetSVG(asset)` exists on Forever (`DOC/SimpleTextureBaseAPIDocumentation.lua:539`, `SimpleVectorGraphicsAPIDocumentation.lua:44`) but not on Era (`BIN-ERA` has no `SetSVG`). Whether it accepts an addon `.svg` path is unknown. (Low; don't build on it.)

### 2.3 Shipping your own textures

* Path format: `"Interface\\AddOns\\<AddonFolder>\\Media\\HexMask"` (extension optional; `.tga` or `.blp`). Same format in TOC `## IconTexture:` (perl-infinity uses `Interface\AddOns\PerlInfinity\Media\Icon`). (High)
* New files are only found after a full client restart; `/reload` picks up edits to files the client already knew about. Matches the perl-infinity Makefile note "A full client restart is needed when the TOC or the file list changes". (High)
* `SetTexture` accepts fileIDs (numbers) too; prefer fileIDs for `Interface\Icons` art (section 3). (High)

### 2.4 Rotation and texcoords

* `Texture:SetRotation(radians, normalizedRotationPoint)` on Forever, `AllowedWhenTainted` (`DOC/SimpleTextureBaseAPIDocumentation.lua:527`); present in all Classic binaries. Rotates the quad about its center or the given normalized point. (High for API; Medium for exact Classic signature.)
* `Texture:SetTexCoord(l, r, t, b)` (`:580`). Crop icon borders with `SetTexCoord(0.08, 0.92, 0.08, 0.92)`. If you combine crop and rotation, test the order on a real tile; the two have interacted oddly on past clients. (Medium-Low)
* A hexagon rotated by 60° looks the same, so Triad moves don't need tile rotation at all: move the three tiles along an arc around the shared vertex. Only rotate the icon if you want a visible spin.

### 2.5 AnimationGroup

Available types on Forever: `Alpha`, `Scale`, `Translation`, `Rotation`, `Path` (control points), `FlipBook`, `TextureCoordTranslation`, `VertexColor`, `LineScale/LineTranslation` (`TAGS` `SimpleAnim*API`). Caveats:

| Caveat | Conf. |
|---|---|
| Translation and Scale don't change layout. When the group stops, the region snaps back unless you set the final anchor in `OnFinished`. Only Alpha has `SetToFinalAlpha(true)` | High |
| Trick for "slide into place": set the final anchor first, then play a Translation of `-offset` with `Play(true)` (reverse), or just tween in OnUpdate | Medium |
| Rotation: apply to textures, not frames. Frames have no rotation, and a frame-level Rotation animation won't rotate child regions reliably | Medium-Low (verify) |
| Rotation origin via `anim:SetOrigin(point, x, y)` (`SimpleAnimRotationAPI`) | High |
| Animating a frame moves its masks with it; animating the icon alone doesn't (2.2) | Medium |
| `SetLooping`, `CreateAnimation` refuse secret arguments; irrelevant here since nothing is secret | High |

Use AnimationGroups for fire-and-forget effects (clear pop: Scale 1 → 1.3 plus Alpha 1 → 0; star pulse; bomb throb with `SetLooping("BOUNCE")`). Use one OnUpdate tween loop for gameplay movement (triad rotation along an arc, falling refills), because you need exact end positions and easing.

### 2.6 OnUpdate cost for ~100 textures

* Run OnUpdate only while a tween is active (`SetScript("OnUpdate", nil)` when idle). Moving 3 to 20 tile frames with `SetPoint` per frame is negligible; even 100 is fine at 60 to 144 fps, but there's no reason to. (Medium-High)
* Don't allocate tables or closures per frame. Precompute grid centers once per layout or scale change.
* For smooth sub-pixel motion, `tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)` on moving textures avoids 1 px jitter (`DOC/SimpleTextureBaseAPI`, `TAGS`). (Medium)
* Region count: 100 tiles × (base, icon, mask, overlay) ≈ 400 regions plus about 100 frames. Comparable to a talent tree. (Medium)

### 2.7 Suggested structure

* Board: one Frame, mouse-enabled, does all hit testing (section 4).
* Tile: a Frame per hex (mouse disabled), children: `base` (addon hex TGA, tinted with `SetVertexColor`), `icon` (gem fileID, cropped, masked by the tile's own hex mask), `overlay` (additive hex outline for hover and selection), optional `glyph` for colorblind mode. Pool them with `CreateFramePool`.
* Flat-top axial layout matches the Blizzard reference PNG: center = `size * (1.5*q, sqrt(3)*(r + q/2))`.

---

## 3. Gem, pearl, star and bomb icons

### 3.0 Update, Nov 2026: Forever ships the full modern icon set

Read straight from the local install with `tools/casc.py` (index, encoding and root files for product `wowf`, build `WOW-70862patch1.60.1_Retail`): the root lists 1,245,666 files, and 30,404 of the names in `ManifestInterfaceData.db2` resolve to `Interface\Icons\*.blp`, Dragonflight and The War Within icons included. So the vanilla-only rule below doesn't apply on Forever; every fileID Skyhex uses was checked against this build and decoded to a real `BLP2`. `make snap` renders mockups from these files.

Skyhex now defaults to one matched set of cut gems, with the vanilla set from 3.2 as the "Classic gems" option:

| Role | Icon | fileID | Notes |
|---|---|---|---|
| Red | `inv_jewelcrafting_80_cutgem02_red` | 1990988 | tinted 1, 0.72, 0.72 to pull it off orange |
| Yellow | `inv_jewelcrafting_80_cutgem02_yellow` | 1990989 | |
| Green | `inv_jewelcrafting_80_cutgem02_green` | 1990985 | lime in the art; tinted 0.7, 1, 0.7 |
| Blue | `inv_jewelcrafting_80_cutgem02_blue` | 1990984 | |
| Purple | `inv_jewelcrafting_80_cutgem02_purple` | 1990987 | |
| Silver | `inv_jewelcrafting_80_cutgem02_blue`, desaturated | 1990984 | `Texture:SetDesaturated(true)` |
| Orange | `inv_jewelcrafting_80_cutgem02_orange` | 1990986 | |
| Starflower | `spell_priest_divinestar_holy`, desaturated | 608954 | a silver six-pointed star |
| Black pearl | `inv_fishing_innards_pearlblack` | 970844 | a glossy black sphere |

Other six-color families that ship (red, orange, yellow, green, blue, purple unless noted): `inv_misc_epicgem_01`-`06` (531771-531776; red, cyan, yellow, orange, magenta, green), `inv_misc_cutgemnormal*` (466277-466282, plus pink 463519), `inv_misc_cutgemperfect*` (466642-466647), `inv_misc_gem_x4_*`, `inv_jewelcrafting_70_cutgem02/03_*`, `inv_jewelcrafting_80_cutgem01_*`, `inv_jewelcrafting_90_*`, `inv_jewelcrafting_immactaladite_*`, and the Dragonflight `inv_10_jewelcrafting_gem*_cut_*` (no yellow).

### 3.1 How these were verified

* Item → icon: Wowhead classic tooltip JSON, `https://nether.wowhead.com/tooltip/item/<id>?dataEnv=4&locale=0` (field `icon`).
* fileID and "used by": Wowhead classic icon pages `https://www.wowhead.com/classic/icon=<fileID>`, cross-checked against the wago.tools listfile `https://wago.tools/files?search=interface/icons/<name>`. Wowhead icon IDs are FileDataIDs, and every icon below matched on both. Ignore the 2207xxx to 2208xxx IDs on wago; those are `.blp.meta` files.
* Era test: every icon below is used by a vanilla item or spell and has a `wow_classic 1.13.0.28211` content hash on wago. TBC-era gem icons (for example `diamond_04` to `_07`, `pearl_07`+, the draenite and jewelcrafting families) have no classic hash or are only used by Season of Discovery items. Avoid them.
* Images: 56×56 renders from `https://wow.zamimg.com/images/wow/icons/large/<name>.jpg`, in `scratchpad/icons/`. These are the retail renders; the classic client ships a different file for each (different md5), so colors in game may differ slightly. Which render Forever ships is unverified.
* Colorblind check: Machado 2009 simulation matrices on each icon's mean color, plus a visual pass at 32 px (`scratchpad/scripts/sheet_rec.png`).

Confidence for the whole section: **High** that each fileID and name exists in Classic data (two primary sources agree). **Medium** that Forever 70862 serves the same fileIDs and similar art, since it's a modern client running classic data. Check with `/dump C_Item.GetItemIconByID(7971)` (expect 134120).

### 3.2 Recommended tile set

Use fileIDs with `SetTexture(fileID)`; the path form `Interface\Icons\INV_Misc_Gem_Ruby_01` also works.

| Tile | Icon | fileID | Vanilla source | Outline at 32 px | Notes |
|---|---|---|---|---|---|
| Red | `inv_misc_gem_ruby_01` | 134128 | Mana Ruby 8008 | heart, point down | Pink-red. Goes pale lavender-grey under red-green |
| Orange | `inv_misc_gem_opal_01` | 134116 | Large Opal 12799 | rounded faceted chunk | Saturated copper-orange. The agent's first pick, `opal_03` (134118, Tigerseye), reads as pale peach shards at 32 px, too close to the whites |
| Yellow | `inv_misc_gem_topaz_02` | 134136 | Yellow Power Crystal 11188 | wide crown or trillion | |
| Green | `inv_misc_gem_emerald_02` | 134105 | Moss Agate 1206 | square step cut | |
| Blue (teal) | `inv_misc_gem_crystal_01` | 134087 | Lesser Moonstone 1705 | vertical column cluster | Stays apart from purple under red-green. True blue alternative: `sapphire_02` (134132, Blue Sapphire 12361), but then blue and purple differ only by outline |
| Purple | `inv_misc_gem_amethyst_02` | 134075 | Soul Shard 6265 | tall kite | Magenta-violet |
| White | `inv_misc_gem_pearl_03` | 134122 | Small Lustrous Pearl 5498 | sphere | |

For a six-color board, drop orange: it is the hardest color to separate under red-green colorblindness.

### 3.3 Specials and the requested pearls

| Role | Icon | fileID | Vanilla source | Look |
|---|---|---|---|---|
| Star | `spell_nature_wispsplode` | 136116 | Arcane Explosion | white-blue radial starburst on blue-violet; fills the frame, so it stands apart from gems drawn on black |
| Star, alternative | `spell_holy_holybolt` | 135920 | Holy Light | gold sunburst; sits near topaz and opal under red-green |
| Bomb | `inv_misc_bomb_01` | 133709 | Large Copper Bomb 4370, Big Iron Bomb 4394 | black round bomb with fuse on amber; darker than every gem in every simulation |
| Bomb, alternative | `inv_misc_bomb_02` | 133710 | Mithril Frag Bomb 10514 | grey spiked mine. Use it if the black pearl is on the board, since both others are dark spheres |
| Black Pearl (item 7971) | `inv_misc_gem_pearl_01` | 134120 | also Heart of Obsidion 10446 | dark navy sphere with pink sheen |
| Iridescent Pearl (5500) | `inv_misc_gem_pearl_02` | 134121 | | pinkish-white sphere; too close to `pearl_03` to use both |
| Golden Pearl (13926) | `inv_misc_gem_pearl_04` | 134123 | | glowing gold sphere, sun-like; a candidate "sun" special, but close to topaz in hue |
| Rainbow wildcard | `inv_misc_gem_variety_02` | 134139 | Bright Baubles 6532 | three small gems in red, green and blue |

Avoid `inv_misc_bomb_09` (red cherry bomb; turns olive like the reds), `spell_fire_sunkey` (a key, and no vanilla user), and `spell_holy_powerinfusion` (a face, not a star).

### 3.4 Confusable pairs

| Vision | Pairs that collapse | Mitigation |
|---|---|---|
| Red-green (deuteranopia, protanopia; most common) | Red, orange, yellow and green all shift toward yellow and olive. Worst: `topaz_02` / `emerald_02` / `opal_01`. `ruby_01` turns pale and drifts toward the whites. `sapphire_*` and `amethyst_*` become nearly identical (ΔE 2.3 for `sapphire_02` vs `amethyst_02`) | Distinct outlines (the set above has seven); optional glyph overlay per color; drop orange on six-color boards; use `crystal_01` rather than a sapphire for blue |
| Blue-yellow (tritanopia; rare) | Green, teal, cyan and blue merge into teal (`emerald_*`, `stone_01`, `crystal_*`, `sapphire_02`). Ruby, amethyst and opal read pink-red; `amethyst_02` next to `ruby_01` is a pink kite next to a pink heart | Same: outline plus glyphs |
| Any | `pearl_02` vs `pearl_03` (both pale spheres); `pearl_01` vs `bomb_01` (both dark spheres) | Never put both of either pair on one board |

Other vanilla families were rejected because every color shares one outline: Zul'Gurub Hakkari Bijous (`inv_bijou_red` 132532, `_blue` 132526, `_yellow` 132534, `_orange` 132530, `_green` 132529, `_purple` 132531; items 19707 to 19712) and the Ahn'Qiraj resonating crystals (`inv_misc_qirajicrystal_01` to `_05`, 134395 to 134399). The bijous are the only vivid vanilla orange if one is ever needed.

---

## 4. Input

| Topic | Finding | Citation | Conf. |
|---|---|---|---|
| Hover | One board frame with an OnUpdate that runs only while the cursor is over it (`OnEnter`/`OnLeave`): `local x, y = GetCursorPosition(); local s = self:GetEffectiveScale(); x, y = x/s - self:GetLeft(), y/s - self:GetBottom()`, recompute only when `x, y` change, then axial-round to a hex or nearest triad vertex. `GetCursorPosition` has no secret tags; `GetEffectiveScale` only goes secret if a secret was fed into scale | `DOC/InputDocumentation.lua:30`; `TAGS` | High |
| Why not per-tile buttons | Frames hit-test as rectangles, so neighboring hexes overlap; the game selects vertices, which only math can find | | High |
| Clicks | `EnableMouse(true)`; `OnMouseDown(self, button)` with `"LeftButton"`, `"RightButton"`, `"MiddleButton"`, `"Button4"`, `"Button5"`. On a Mac trackpad, Command+click maps to right-click when CVar `MacUseCommandLeftClickAsRightClick` is on | `TAGS`; `BIN` 755715 | High |
| Wheel | `EnableMouseWheel(true)`; `OnMouseWheel(self, delta)`, delta `+1` up, `-1` down | `DOC/SimpleScriptRegionAPIDocumentation.lua:95`; `TAGS` | High |
| `EnableMouse`, `EnableMouseWheel`, `EnableKeyboard` | `IsProtectedFunction`: only blocked in combat on *protected* frames. Your frames aren't protected | `TAGS` | High |
| Keyboard | `EnableKeyboard(true)` plus `OnKeyDown(self, key)`. `SetPropagateKeyboardInput` is `HasRestrictions` on Forever, and since 10.1.5 "May no longer be called by insecure code while in combat" on all four flavors | `DOC/SimpleFrameAPIDocumentation.lua:1426-1428`; WEB https://warcraft.wiki.gg/wiki/API_Frame_SetPropagateKeyboardInput | High |
| Keyboard pattern | Set `SetPropagateKeyboardInput(true)` once out of combat. In `OnKeyDown`, if the key is yours and `not InCombatLockdown()`, call `SetPropagateKeyboardInput(false)` for that key, else `true`. In combat, leave propagation alone: your handler still sees keys, but they also reach bindings. Always propagate `ESCAPE` so `UISpecialFrames` handles it. Movement keys (WASD, Q/E, arrows, Space) do nothing on a taxi, so they're good defaults | wiki above | Medium-High |
| Chat | A focused edit box receives keys before your frame, so typing in chat isn't intercepted | | Medium |
| Taxi | Nothing blocks UI interaction on a taxi: Blizzard explicitly skips its close-all-windows step when on a taxi (`EventImplementation.lua:168-174`), and no UI mode or roleset filter keys off taxis (no `UnitOnTaxi` use in `Blizzard_UIModes`) | as cited | High |
| Combat on a taxi | You can still be "in combat" for a few seconds after takeoff if a mob was on you. Only keyboard propagation is affected | | Medium |

---

## 5. Sound

On camelot the Mainline `SOUNDKIT` table loads (`BZ/Blizzard_SharedXML/Blizzard_SharedXML.toc:163` `[Family]\SoundKitConstants.lua`, 999 lines). Every key below also exists with the same ID in Classic Era's table (`ERA/Blizzard_SharedXML/Vanilla/SoundKitConstants.lua`). "Used by Forever UI" means Forever's own code plays it, which is good evidence the sound data ships.

| Purpose | Key (ID) | Forever line | Used by Forever UI | Conf. |
|---|---|---|---|---|
| Tile clear | `PUT_DOWN_GEMS` (1204), or `LOOT_WINDOW_COIN_SOUND` (120) for a coin clink | `Mainline/SoundKitConstants.lua:280`, `:3` | 1204 no (item drag sound, vanilla-era); 120 yes (`Blizzard_AuctionHouseUI`) | Medium / High |
| Select or rotate click | `U_CHAT_SCROLL_BUTTON` (1115), `IG_MAINMENU_OPTION_CHECKBOX_ON` (856), `PICK_UP_GEMS` (1221) | `:68`, `:48`, `:281` | yes (58 uses), yes (449 uses), no | High / High / Medium |
| Level up | No `LEVELUP` key in either table. Use `IG_QUEST_LIST_COMPLETE` (878) or `PVP_THROUGH_QUEUE` (8459); try `PlaySound(888)` (the classic level-up kit) in game | `:63`, `:81` | yes, yes | High (878, 8459), Low (888) |
| Bomb tick | `UI_BATTLEGROUND_COUNTDOWN_TIMER` (25477), `ALARM_CLOCK_WARNING_2` (12867) | `:112`, `:94` | yes (`Blizzard_FrameXML/Timer.lua`), yes (`Blizzard_TimeManager`) | High |
| Bomb goes off, game over | `UI_BATTLEGROUND_COUNTDOWN_FINISHED` (25478), `IG_QUEST_LOG_ABANDON_QUEST` (846), `RAID_WARNING` (8959) | `:113`, `:41`, `:84` | yes, yes, yes | High |
| Big combo | `JEWEL_CRAFTING_FINALIZE` (10590, TBC-era but in Era's table), `READY_CHECK` (8960) | `:86`, `:85` | yes, yes | High (Forever), Medium (Era data) |

* `PlaySound(kitID, "SFX")` respects the effects volume slider. Use `SOUNDKIT.X or <id>` so a missing key doesn't pass `nil`. (High)
* `PlaySoundFile("Interface\\AddOns\\<Addon>\\Sounds\\clear.ogg", "SFX")` with addon-shipped `.ogg` or `.mp3` works (`BIN` 725592-725593 lists both; perl-infinity's harness models it at `tests/harness/blizzard.lua:348`). New sound files need a client restart. Since 8.2, game sounds can only be played by fileID, not path; addon paths are unaffected. (Medium-High)
* Neither is secret-restricted (no tags) and both are present in all Classic binaries. (High)
* Keep sounds sparse: clears can chain several times a second. Use `forceNoDuplicates` via `C_Sound.PlaySound` on Forever or throttle yourself. (Medium)

---

## 6. SavedVariables

| Question | Answer | Citation | Conf. |
|---|---|---|---|
| Per-account | `## SavedVariables: SkyhexDB` → `WTF/Account/<ACCOUNT>/SavedVariables/<Addon>.lua` | WEB https://warcraft.wiki.gg/wiki/TOC_format; `BIN` 737348-737350 | High |
| Per-character | `## SavedVariablesPerCharacter: SkyhexCharDB` → `WTF/Account/<ACCOUNT>/<Realm>/<Char>/SavedVariables/<Addon>.lua` | same | High |
| When loaded | Before your `ADDON_LOADED` fires (or before your files with `## LoadSavedVariablesFirst: 1`) | wiki | High |
| When written | Logout, `/reload`, clean quit. The client writes via a `.tmp` file and keeps a `.lua.bak` of the previous copy (`BIN` 737375 `WTF/SavedVariables/%s.lua.bak`, `.tmp` near it) | `BIN` | High (when), Medium (`.tmp` mechanics) |
| Crash or force quit | Not written. Everything since the last logout or reload is lost. There is no API to flush on demand | | High |
| Hook for the final write | `PLAYER_LOGOUT` (fires on logout and reload) is the conventional place to pack live state into the SV table. Forever and all Classic binaries also have `ADDONS_UNLOADING(closingClient)` | `DOC/AddOnsDocumentation.lua:402`; `BIN-ERA/ANN/MOP` | High |
| Size | ~100 tiles packed into a 100-character string plus scores is well under 5 KB. `SAVED_VARIABLES_TOO_LARGE(addOnName)` exists and Blizzard shows a popup (`BZ/Blizzard_Game/Shared/EventImplementation.lua:200-202`); the threshold isn't documented and won't matter at this size | as cited | High |
| Secrets | Forever refuses secrets in SVs (`PI/` 1.4). Nothing this addon stores comes from a secret API | `PI/` | High |
| Forever beta report | ForeverBuddy saw the beta client write SVs but not read them back at login (`PI/` 5.1). Not seen in Threat Plates. Do one logout/login round-trip test on 70862 | `PI/` | Low |

Recommendations:

* Snapshot the board into the SV table on landing and on `PLAYER_LOGOUT`; keep the in-memory board authoritative otherwise. Write a `version` field so the format can change.
* Pack tiles as a string (one character per tile kind) rather than a table of tables: smaller files, faster load, trivially validated.
* Open product question: one shared game per account ("pick up where you left off on any character") or one per character. High scores and settings belong per-account either way.
* Flight crashes lose at most one flight's progress. Say so in any in-game help rather than implying progress is always safe.

---

## 7. Window conventions on Forever

| Topic | Finding | Citation | Conf. |
|---|---|---|---|
| `BackdropTemplate` | Present on Forever and all Classic branches; `frame:SetBackdrop(info)`, presets like `BACKDROP_DIALOG_32_32`, `BACKDROP_DARK_DIALOG_32_32` | `BZ/Blizzard_SharedXML/Backdrop.xml:5`, `Backdrop.lua:17,27,336`; `ERA/` tree has `Blizzard_SharedXML/Backdrop.xml` | High |
| `ButtonFrameTemplate`, `PortraitFrameTemplate`, `DefaultPanelTemplate`, `BasicFrameTemplateWithInset` | Present on Forever (Mainline art, Camelot overrides) and on Era (classic art). Helpers: `ButtonFrameTemplate_HidePortrait`, `ButtonFrameTemplate_HideButtonBar`, `frame:SetTitle(text)` (`TitledPanelMixin`) | `BZ/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:528,658,711`, `SharedUIPanelTemplates.lua:66,111`, `PortraitFrame.lua:12`; `BZ/Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml:602`; `ERA/Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml:545,708,1276` | High |
| Look | Templates will look different per flavor (Dragonflight-style chrome on Forever, 2004-style on Era). A custom `BackdropTemplate` frame with your own art looks the same everywhere and avoids the stock-dialog look | | Medium |
| Movable + saved position | `SetMovable(true)`, `SetClampedToScreen(true)`, `RegisterForDrag("LeftButton")` on a title strip, `StartMoving`/`StopMovingOrSizing`, then save `GetPoint()` to SVs. Avoid relying on `SetUserPlaced`/layout-cache (per character, and Forever's Edit Mode era handles it differently) | `TAGS` | High |
| Strata | `SetFrameStrata("HIGH")` or `"DIALOG"`, `SetToplevel(true)` | `TAGS` | High |
| ESC to close | `tinsert(UISpecialFrames, "SkyhexFrame")` (needs a global name). Blizzard's ESC chain calls `securecall("CloseSpecialWindows")`, which hides each listed frame | `BZ/Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:21-27, 1106-1117, 1168` | High |
| Forever-only ESC API | `RegisterGameMenuEscHandler(GameMenuEscPriority.AddOn, fn)`; handlers run through `securecallfunction`. Not on Classic; `UISpecialFrames` is enough | `BZ/Blizzard_GameMenuEsc/Blizzard_GameMenuEsc.lua:6-62, 76-113` | High |
| Side effect | Loss of control on the ground (fear, stun) runs `CloseAllWindows_WithExceptions`, which hides `UISpecialFrames` too. Harmless here | `UIParentPanelManager.lua:1185-1188` | High |
| Don't use `UIPanelWindows`/`ShowUIPanel` | The panel manager positions frames through a secure delegate (`FramePositionDelegate:SetAttribute`); addon frames in it are a known taint source on Mainline | `UIParentPanelManager.lua:1192-1209` | Medium |
| Addon compartment | Present on Forever: Mainline `AddonCompartment.lua` plus a Camelot restyle (`Blizzard_Minimap.toc:48-51`, `Blizzard_Minimap/Camelot/AddonCompartment.lua`). Reads `AddonCompartmentFunc`, `AddonCompartmentFuncOnEnter/OnLeave`, `IconTexture`/`IconAtlas` from the TOC; calls your global with `forceinsecure()` (`Mainline/AddonCompartment.lua:102-150`). Not present in the Era, Anniversary or Mists UI trees, so pair it with a slash command (or LibDBIcon) there | as cited; Gethe tree listings | High |
| Slash commands | `SLASH_SKYHEX1 = "/skyhex"; SlashCmdList.SKYHEX = fn` works everywhere. Forever also has `RegisterNewSlashCommand(callback, command, alias)` | `BZ/Blizzard_ChatFrameBase/Shared/SlashCommandsRegistry.lua:16, 42-51` | High |
| Combat lockdown | None for insecure frames: `Show`, `Hide`, `SetPoint`, `SetSize`, `SetTexture`, scripts all work in combat. Restrictions only bite on protected frames and `SetPropagateKeyboardInput` | `TAGS` (`IsProtectedFunction` vs `HasRestrictions`) | High |

---

## 8. TOC

### 8.1 Interface numbers

| Client | Build | `## Interface` | Evidence | Conf. |
|---|---|---|---|---|
| Forever | 1.60.1.70862 | 16001 | `PI/` 5.1; Auctionator and InFlight TOCs | High |
| Classic Era | 1.15.9.70576 | 11509 | Auctionator TOC in `_forever_` lists 11509; InFlight; wiki | High |
| TBC Anniversary | 2.5.6.70577 | 20506 | same | High |
| Mists Classic | 5.5.4.70631 | 50504 | same | High |

The addons installed in the Classic folders carry older numbers (11507, 11508, 20505, 50503) and are flagged out of date there; the numbers above follow `major*10000 + minor*100 + patch` and match the wiki's current list (WEB https://warcraft.wiki.gg/wiki/TOC_format). Check in game with `/dump select(4, GetBuildInfo())`.

### 8.2 One TOC or per-flavor suffixes

Recommended start: **one TOC, no game-type gating**.

```
## Interface: 16001, 11509, 20506, 50504
## Title: Skyhex
## Notes: A hex gem puzzle to play while you fly
## Author: lovelaced
## Version: @project-version@
## IconTexture: Interface\AddOns\Skyhex\Media\Icon
## AddonCompartmentFunc: Skyhex_OnAddonCompartmentClick
## AddonCompartmentFuncOnEnter: Skyhex_OnAddonCompartmentEnter
## AddonCompartmentFuncOnLeave: Skyhex_OnAddonCompartmentLeave
## SavedVariables: SkyhexDB
## SavedVariablesPerCharacter: SkyhexCharDB
## X-License: GPL-3.0-or-later
```

(Title and names are placeholders.) Comma-separated Interface lists work on all four clients (added 10.2.7; Auctionator ships one in each client folder). (High)

Facts that drive the choice:

* Forever's TOC parser knows `Interface:`, `IconTexture`, `IconAtlas`, `AddonCompartmentFunc*`, `Category`, `SavedVariables*`, `LoadSavedVariablesFirst`, `AllowLoadGameType`, `ExcludeLoadGameType`, `LoadOnDemand`, `OptionalDep`, `RequiredDep` and more (`BIN` 737380-737407, the directive cluster after "Failed to load ui toc list"). (High)
* Game types Forever recognizes: `mainline, standard, plunderstorm, wowhack, classic, vanilla, wrath, cata, mists, camelot, forever` (`BIN` 722587-722597). The Era, Anniversary and Mists binaries list `mainline, standard, plunderstorm, wowhack, classic, vanilla, wrath, cata, mists` (plus `tbc`) but **not** `camelot` or `forever` (`BIN-ERA/ANN/MOP`). (High)
* The wiki: "If none of the listed game types are recognized by the client, the condition is satisfied." So a file line tagged only `[AllowLoadGameType camelot]` also loads on Classic clients. For a Forever-only file in a shared TOC write `File.lua [AllowLoadGameType camelot][ExcludeLoadGameType classic]`; all three Classic binaries know `ExcludeLoadGameType` and the `classic` family. (High for binary facts, Medium for the combined behavior.)
* Don't copy perl-infinity's header (`AllowLoadGameType: camelot, forever` + `ExcludeLoadGameType: standard, classic`): it exists to keep that addon off Classic.
* Path tokens: `[Game]` expands to `Camelot`, `Vanilla`, `TBC` or `Mists`, so `Compat\[Game].lua` loads one compat file per flavor with no conditions (wiki; Blizzard does the same in `Blizzard_Minimap.toc`). (Medium-High)
* Per-flavor suffix TOCs: `Skyhex_Forever.toc` (or `_Camelot`), `Skyhex_Vanilla.toc`, `Skyhex_TBC.toc` (covers Anniversary), `Skyhex_Mists.toc`; family fallbacks `_Mainline` (includes Forever) and `_Classic`; unsuffixed TOC last. Switch to these only when the file lists diverge enough that inline conditions get messy; the cost is duplicated metadata. (High, wiki and `PI/` 5.1)
* Runtime flavor check: `select(4, GetBuildInfo())`, or `WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` for Forever (`BZ/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua:1-2`). (High)

---

## 9. Risks and open questions

| # | Item | Impact | Mitigation |
|---|---|---|---|
| 1 | Takeoff lag and unreliable landing events (1.2) | Board opens late or never closes | Poll `UnitOnTaxi` as in 1.3 |
| 2 | Flights shorter than ~30 s | Little play time; open/close churn | Product call: minimum flight length before auto-open, or a "keep playing after landing" option |
| 3 | No duration API | No "time left" display on first flights | Learn per route; show nothing until known |
| 4 | Crash mid-flight | Loses progress since last logout or reload | Accept; say so in help text |
| 5 | Keyboard in combat | Keys also trigger bindings for a few seconds after a hot takeoff | Mouse-first design; keyboard as extra |
| 6 | No built-in hex art | Must ship TGA mask and frame art; new files need a client restart | Make art early so the dev loop isn't blocked |
| 7 | Sound kit data for 1204/1221/888 unconfirmed on Forever | Silent effects | Test in game; fall back to kits Forever's UI uses |
| 8 | Forever is five days past launch (2026-11-04) with frequent builds | APIs and behavior may shift | Re-run the one-liners below after each patch |
| 9 | ForeverBuddy's SV read-back report from beta | Lost saves | Round-trip test on live |

### In-game checks (Forever first, then Era)

```
/dump select(4, GetBuildInfo()), WOW_PROJECT_ID
/run local f=CreateFrame("Frame") for _,e in ipairs({"PLAYER_CONTROL_LOST","PLAYER_CONTROL_GAINED","TAXIMAP_CLOSED","PLAYER_LEAVING_WORLD","PLAYER_ENTERING_WORLD"}) do f:RegisterEvent(e) end f:RegisterUnitEvent("UNIT_FLAGS","player") f:SetScript("OnEvent",function(_,e,a,b) print(format("%.2f",GetTime()),e,a,b,"onTaxi",UnitOnTaxi("player")) end) hooksecurefunc("TakeTaxiNode",function(s) print(format("%.2f",GetTime()),"TakeTaxiNode",s,TaxiNodeName(s),GetNumRoutes(s),"onTaxi",UnitOnTaxi("player")) end)
/run local n=0 for _,a in ipairs(C_Texture.GetAtlasElements()) do if a:lower():find("hex") then print(a) n=n+1 end end print(n,"hex atlases")
/dump C_Item.GetItemIconByID(7971), C_Item.GetItemIconByID(13926), C_Item.GetItemIconByID(5500)
/run PlaySound(1204) C_Timer.After(1,function() PlaySound(1221) end) C_Timer.After(2,function() PlaySound(888) end)
```

The second line, taken on one short flight, answers the takeoff lag, the event order, whether `UNIT_FLAGS` fires for taxis and whether `PLAYER_CONTROL_GAINED` fires on landing.

### Reusable tooling

perl-infinity's LuaJIT harness (`~/git/perl-infinity/tests/harness/`) already models `UnitOnTaxi` (`unitapi.lua:111`), `PlaySound`/`PlaySoundFile` (`blizzard.lua:342-348`), mask textures, `SetRotation`, keyboard and mouse-wheel scripts (`widget_types.lua:301-409`) and SavedVariables serialization with secret checks (`savedvars.lua`). It lacks the legacy taxi functions (`TakeTaxiNode`, `TaxiNodeName`, `NumTaxiNodes`, `TaxiNodeGetType`, `GetNumRoutes`), `C_TaxiMap`, and the combat restriction on `SetPropagateKeyboardInput`; add those stubs plus a scripted event sequence (hook → delay → `PLAYER_CONTROL_LOST` → `UnitOnTaxi` true → landing) to test the state machine offline. The Makefile's `deploy` target pattern carries over unchanged.

---

## 10. Sources

Local:

* Blizzard UI source, `forever` @ `9dc84f0` (1.60.1.70862): `scratchpad/wow-ui-forever/Interface/AddOns/`
* Single files from Gethe `classic_era` (1.15.9.70576): `Blizzard_SharedXML/Vanilla/SoundKitConstants.lua`, `Blizzard_SharedXML/Classic/SharedUIPanelTemplates.xml`; tree listings of `classic_era`, `classic_anniversary` (2.5.6.70577), `classic` (5.5.4.70631)
* Client binaries (strings only): `_forever_`, `_classic_era_`, `_anniversary_`, `_classic_` under `/Applications/World of Warcraft/`
* Installed addon TOCs in all four client folders
* InFlight `InFlight.lua` and `InFlight.toc`, https://github.com/LudiusMaximus/InFlight (MIT)
* `~/git/perl-infinity/notes/research/research-forever-api.md`, `tests/harness/`, `Makefile`

Web (fetched 2026-11-09):

* https://warcraft.wiki.gg/wiki/TOC_format
* https://warcraft.wiki.gg/wiki/API_UnitOnTaxi
* https://warcraft.wiki.gg/wiki/API_TakeTaxiNode
* https://warcraft.wiki.gg/wiki/PLAYER_CONTROL_LOST
* https://warcraft.wiki.gg/wiki/API_Frame_SetPropagateKeyboardInput
* https://warcraft.wiki.gg/wiki/UIOBJECT_Rotation (no behavioral notes)
* Icons: `https://nether.wowhead.com/tooltip/item/<id>?dataEnv=4&locale=0` for items 7971, 13926, 5500, 5498, 7910, 12364, 12800, 12361, 12799, 11754, 12363, 3864, 7909, 1529, 1705, 1210, 1206, 818, 774, 4370, 10646; `https://www.wowhead.com/classic/icon=<fileID>` and `https://wago.tools/files?search=interface/icons/<name>` for every fileID in section 3; images from `https://wow.zamimg.com/images/wow/icons/large/`. The scratchpad copies (`scratchpad/icons/`, `scratchpad/scripts/sheet_rec.png`) are temporary; re-download if needed (about 1.5 MB)
