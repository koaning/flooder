-- Headless smoke test: boots main.lua on tests/love_stub.lua under LuaJIT,
-- plays Flooder with keyboard, gamepad and mouse, wins and loses a round, and
-- checks that the stats survive a reboot.
--
-- Run from the repo root:  luajit tests/smoke.lua

package.path = "tests/?.lua;?.lua;" .. package.path
local stub = require("love_stub")
local rules = require("src.rules")

local function best_color(st)
  local best, best_gain = nil, -1
  for c = 1, st.colors do
    local g = rules.gain(st, c)
    if g > best_gain then best, best_gain = c, g end
  end
  return best
end

local g = stub.boot({ seed = 7 })
local game = require("src.game")

assert(game.state.scene == "title", "should boot onto the title screen")
g.frames(10)
assert(g.draw_calls() > 0, "love.draw should have rendered frames")

-- Pick the small board, then start with the keyboard
g.key("left")
assert(game.state.size == 1, "left should pick the small board")
g.key("space")
local st = game.state.st
assert(game.state.scene == "play" and st.w == 10, "space should start a 10x10 game")
assert(st.max_moves == rules.greedy_moves(st), "limit should match the greedy bot")

-- Play greedily, alternating number keys, gamepad and mouse clicks on the palette
local turn = 0
while game.state.scene == "play" do
  local c = best_color(st)
  turn = turn + 1
  if turn % 3 == 0 then
    g.key(tostring(c))
  elseif turn % 3 == 1 then
    -- Move the selection with the D-pad, then confirm with A
    while game.state.sel ~= c do g.gamepad("dpdown") end
    g.gamepad("a")
  else
    -- 640x480 window: virtual coords map 1:1; swatches start at y=150, 48 apart
    g.love.mousepressed(500, 150 + (c - 1) * 48 + 20, 1)
    g.step()
  end
  assert(turn < 100, "game should end")
end
g.frames(30)
assert(game.state.scene == "gameover" and st.won, "greedy play should win")
assert(game.state.stats[1].won == 1 and game.state.stats[1].streak == 1)

-- New board with the gamepad, then burn moves until we lose
g.gamepad("a")
st = game.state.st
assert(game.state.scene == "play" and st.moves == 0, "A should deal a new board")
local a, b = st.grid[1][1] % 6 + 1, (st.grid[1][1] + 1) % 6 + 1
local guard = 0
while game.state.scene == "play" do
  g.key(tostring(st.moves % 2 == 0 and a or b))
  guard = guard + 1
  assert(guard < 200, "game should end")
end
-- Alternating two colours can only win on a tiny board; we expect a loss here.
assert(not st.won, "alternating two colours should run out of moves")
assert(game.state.stats[1].played == 2 and game.state.stats[1].streak == 0)

-- Clicking a board cell picks that cell's colour
g.key("r")
st = game.state.st
local target = st.grid[1][2] ~= st.grid[1][1] and st.grid[1][2] or nil
if target then
  local c = math.floor(416 / st.w)
  local pad = math.floor((416 - c * st.w) / 2)
  g.love.mousepressed(28 + pad + c * 1.5, 32 + pad + c * 0.5, 1)
  assert(st.moves == 1 and st.grid[1][1] == target, "clicking a cell should flood with its colour")
end

-- B goes back to the menu
g.gamepad("b")
assert(game.state.scene == "title")
assert(g.files["stats.txt"] ~= nil, "stats should be saved")

-- Reboot with the saved files and verify persistence
local g2 = stub.boot({ seed = 7, files = g.files })
local game2 = require("src.game")
assert(game2.state.stats[1].played == 2 and game2.state.stats[1].won == 1, "stats should survive a reboot")
assert(game2.state.stats[1].best_streak == 1)

print("Smoke: won and lost Flooder via keyboard, gamepad and mouse; stats saved.")
