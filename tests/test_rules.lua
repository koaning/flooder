-- Pure LuaJIT unit tests for src/rules.lua (Flooder).
--
-- Run from the repo root:  luajit tests/test_rules.lua

package.path = "?.lua;src/?.lua;" .. package.path
local rules = require("src.rules")

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    io.stderr:write("FAIL " .. name .. "\n  " .. tostring(err) .. "\n")
    os.exit(1)
  end
  passed = passed + 1
end

local function make_rng(seed)
  local state = seed % 2147483648
  return function(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return math.floor((state / 2147483648) * n) + 1
  end
end

-- Builds a state from rows of digits, e.g. { "112", "233" }.
local function board(rows, max_moves)
  local st = rules.new(#rows[1], #rows, 6, max_moves or 10, function() return 1 end)
  for y, row in ipairs(rows) do
    for x = 1, #row do st.grid[y][x] = tonumber(row:sub(x, x)) end
  end
  return st
end

test("new boards use colours 1..colors", function()
  for seed = 1, 20 do
    local st = rules.new(14, 14, 6, 25, make_rng(seed))
    for y = 1, 14 do
      for x = 1, 14 do
        local c = st.grid[y][x]
        assert(c >= 1 and c <= 6 and c == math.floor(c))
      end
    end
    assert(st.moves == 0 and not st.over)
  end
end)

test("region follows matching colour from the top-left", function()
  local st = board({
    "1123",
    "2133",
    "1111",
  })
  local _, n = rules.region(st)
  assert(n == 7, "expected 7 cells, got " .. n)
end)

test("gain counts the cells a colour would absorb", function()
  local st = board({
    "1123",
    "2133",
    "1111",
  })
  assert(rules.gain(st, 1) == 0)
  assert(rules.gain(st, 2) == 2, "two 2s touch the region")
  assert(rules.gain(st, 3) == 3, "the 3 cluster touches the region")
  assert(rules.gain(st, 4) == 0)
end)

test("flooding repaints the region and absorbs neighbours", function()
  local st = board({
    "1123",
    "2133",
    "1111",
  })
  local outcome, gained = rules.flood(st, 3)
  assert(outcome == "move" and st.moves == 1)
  assert(#gained == 3)
  assert(st.grid[1][1] == 3 and st.grid[3][1] == 3)
  assert(rules.size(st) == 10)
end)

test("picking the current colour is not a move", function()
  local st = board({ "12", "21" })
  assert(rules.flood(st, 1) == "same" and st.moves == 0)
end)

test("filling the board wins", function()
  local st = board({ "12", "22" })
  assert(rules.flood(st, 2) == "win")
  assert(st.over and st.won)
  assert(rules.flood(st, 1) == "over")
end)

test("running out of moves loses", function()
  local st = board({ "123", "456", "123" }, 2)
  assert(rules.flood(st, 2) == "move")
  assert(rules.flood(st, 3) == "lose")
  assert(st.over and not st.won)
end)

test("gained cells are ordered by distance from the region", function()
  local st = board({ "1222" })
  local _, gained = rules.flood(st, 2)
  assert(#gained == 3)
  for i, p in ipairs(gained) do
    assert(p.x == i + 1 and p.d == i)
  end
end)

test("greedy solver always finishes without touching the board", function()
  for seed = 1, 30 do
    local st = rules.new(10, 10, 6, 1, make_rng(seed))
    local before = st.grid[5][5]
    local m = rules.greedy_moves(st)
    assert(m >= 1 and m < 100)
    assert(st.moves == 0 and st.grid[5][5] == before)
  end
end)

test("the greedy move count is enough to win", function()
  local st = rules.new(8, 8, 6, 1, make_rng(42))
  st.max_moves = rules.greedy_moves(st)
  local outcome
  repeat
    local best, best_gain = nil, -1
    for c = 1, 6 do
      local g = rules.gain(st, c)
      if g > best_gain then best, best_gain = c, g end
    end
    outcome = rules.flood(st, best)
  until outcome ~= "move"
  assert(outcome == "win", "greedy replay should win, got " .. outcome)
end)

print("Rules: " .. passed .. " tests passed.")
