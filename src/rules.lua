-- Pure Lua Flooder rules (no love.* dependencies) so tests/test_rules.lua can
-- run them directly under luajit.
--
-- The board is a w x h grid of colour indices 1..colors. The player owns the
-- region connected to the top-left cell by matching colour. Each move repaints
-- that region with a new colour, which absorbs every neighbouring cell of that
-- colour. Fill the whole board within max_moves to win.

local rules = {}

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- rng(n) should return an integer in [1, n] (defaults to math.random).
function rules.new(w, h, colors, max_moves, rng)
  rng = rng or math.random
  local grid = {}
  for y = 1, h do
    grid[y] = {}
    for x = 1, w do
      grid[y][x] = rng(colors)
    end
  end
  return {
    w = w,
    h = h,
    colors = colors,
    max_moves = max_moves,
    grid = grid,
    moves = 0,
    over = false,
    won = false,
  }
end

-- Breadth-first walk outward from `seeds` (list of {x, y}) through cells of
-- colour c. Returns the visited set keyed by (y - 1) * w + x, the newly
-- reached cells as {x, y, d} (d = steps from the seeds) and the set's size.
local function spread(st, seeds, seen, c)
  local w, h, grid = st.w, st.h, st.grid
  local reached = {}
  local frontier = seeds
  local d = 0
  while #frontier > 0 do
    d = d + 1
    local nxt = {}
    for _, p in ipairs(frontier) do
      for _, dir in ipairs(DIRS) do
        local nx, ny = p[1] + dir[1], p[2] + dir[2]
        if nx >= 1 and ny >= 1 and nx <= w and ny <= h then
          local k = (ny - 1) * w + nx
          if not seen[k] and grid[ny][nx] == c then
            seen[k] = true
            reached[#reached + 1] = { x = nx, y = ny, d = d }
            nxt[#nxt + 1] = { nx, ny }
          end
        end
      end
    end
    frontier = nxt
  end
  return reached
end

-- Returns the flooded region as a set keyed by (y - 1) * w + x, plus its size.
function rules.region(st)
  local seen = { [1] = true }
  local reached = spread(st, { { 1, 1 } }, seen, st.grid[1][1])
  return seen, #reached + 1
end

function rules.size(st)
  local _, n = rules.region(st)
  return n
end

-- Cells that picking colour c would add to the region, as {x, y, d}.
-- Empty for the region's own colour. Does not change st.
function rules.preview(st, c)
  if c == st.grid[1][1] then return {} end
  local region = rules.region(st)
  local seeds, seen = {}, {}
  for k in pairs(region) do
    seen[k] = true
    seeds[#seeds + 1] = { (k - 1) % st.w + 1, math.floor((k - 1) / st.w) + 1 }
  end
  return spread(st, seeds, seen, c)
end

function rules.gain(st, c)
  return #rules.preview(st, c)
end

-- Repaints the region with colour c. Returns:
--   "over"  the round is already finished
--   "same"  c is already the region's colour (not counted as a move)
--   "win"   the board is now one colour
--   "lose"  out of moves
--   "move"  a normal move
-- The second return value lists the absorbed cells as {x, y, d}, where d is
-- the distance from the old region (used for the ripple animation).
function rules.flood(st, c)
  if st.over then return "over", {} end
  if c == st.grid[1][1] then return "same", {} end

  local gained = rules.preview(st, c)
  local region = rules.region(st)
  for k in pairs(region) do
    st.grid[math.floor((k - 1) / st.w) + 1][(k - 1) % st.w + 1] = c
  end

  st.moves = st.moves + 1
  if rules.size(st) == st.w * st.h then
    st.over, st.won = true, true
    return "win", gained
  end
  if st.moves >= st.max_moves then
    st.over = true
    return "lose", gained
  end
  return "move", gained
end

local function copy_state(st)
  local copy = {
    w = st.w, h = st.h, colors = st.colors, max_moves = math.huge,
    grid = {}, moves = 0, over = false, won = false,
  }
  for y = 1, st.h do
    copy.grid[y] = {}
    for x = 1, st.w do copy.grid[y][x] = st.grid[y][x] end
  end
  return copy
end

-- Greedy solver: keeps picking the colour that adds the most cells. Returns
-- the number of moves it needed. Used for hints and to sanity-check limits.
function rules.greedy_moves(st)
  local copy = copy_state(st)
  while not copy.over do
    local best, best_gain = nil, -1
    for c = 1, copy.colors do
      local g = rules.gain(copy, c)
      if g > best_gain then best, best_gain = c, g end
    end
    rules.flood(copy, best)
  end
  return copy.moves
end

return rules
