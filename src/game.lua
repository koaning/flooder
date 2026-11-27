-- Flooder: repaint the top-left region until the whole board is one colour.

local rules = require("src.rules")

local game = {}

local W, H = 640, 480
local COLORS = 6
local SAVE_FILE = "stats.txt"

local SIZES = {
  { name = "SMALL", n = 10 },
  { name = "MEDIUM", n = 14 },
  { name = "LARGE", n = 18 },
}

local PALETTE = {
  { 0.94, 0.33, 0.38 }, -- red
  { 0.98, 0.70, 0.25 }, -- amber
  { 0.40, 0.82, 0.45 }, -- green
  { 0.30, 0.66, 0.96 }, -- blue
  { 0.66, 0.45, 0.92 }, -- purple
  { 0.96, 0.56, 0.82 }, -- pink
}

-- Board and side-panel geometry (virtual pixels).
local BOARD_X, BOARD_Y, BOARD_PX = 28, 32, 416
local PANEL_X = 474
local SWATCH_Y, SWATCH_H, SWATCH_GAP = 150, 40, 8

local fonts = {}

game.state = {
  scene = "title",
  st = nil,
  size = 2,
  sel = 1,
  elapsed = 0,
  pop = {},
  stats = {},
}

local function rng(n)
  return love.math.random(n)
end

local function blank_stats()
  local t = {}
  for i = 1, #SIZES do
    t[i] = { played = 0, won = 0, streak = 0, best_streak = 0, best_spare = -1 }
  end
  return t
end

-- stats.txt holds lines like "2 played 5" (size index, field, value).
local function load_stats()
  local t = blank_stats()
  if not love.filesystem.getInfo(SAVE_FILE) then return t end
  local raw = love.filesystem.read(SAVE_FILE) or ""
  for i, k, v in raw:gmatch("(%d+) (%a[%w_]*) (%-?%d+)") do
    i = tonumber(i)
    if t[i] and t[i][k] ~= nil then t[i][k] = tonumber(v) end
  end
  return t
end

local function save_stats()
  local lines = {}
  for i, s in ipairs(game.state.stats) do
    for _, k in ipairs({ "played", "won", "streak", "best_streak", "best_spare" }) do
      lines[#lines + 1] = i .. " " .. k .. " " .. s[k]
    end
  end
  love.filesystem.write(SAVE_FILE, table.concat(lines, "\n") .. "\n")
end

local function cell_px()
  return math.floor(BOARD_PX / game.state.st.w)
end

local function board_origin()
  local n = game.state.st.w
  local c = cell_px()
  local pad = math.floor((BOARD_PX - c * n) / 2)
  return BOARD_X + pad, BOARD_Y + pad, c
end

local function start_round()
  local s = game.state
  local n = SIZES[s.size].n
  local st = rules.new(n, n, COLORS, 1, rng)
  -- The move limit is what a greedy bot needs, so every board is winnable.
  st.max_moves = rules.greedy_moves(st)
  s.st = st
  s.scene = "play"
  s.pop = {}
  s.sel = st.grid[1][1] % COLORS + 1
end

local function finish_round(won)
  local s = game.state
  local stat = s.stats[s.size]
  stat.played = stat.played + 1
  if won then
    stat.won = stat.won + 1
    stat.streak = stat.streak + 1
    stat.best_streak = math.max(stat.best_streak, stat.streak)
    stat.best_spare = math.max(stat.best_spare, s.st.max_moves - s.st.moves)
  else
    stat.streak = 0
  end
  save_stats()
  s.scene = "gameover"
end

local function pick(c)
  local s = game.state
  if s.scene ~= "play" or not s.st then return end
  local outcome, gained = rules.flood(s.st, c)
  if outcome == "same" or outcome == "over" then return end
  for _, p in ipairs(gained) do
    s.pop[(p.y - 1) * s.st.w + p.x] = s.elapsed + p.d * 0.035
  end
  if outcome == "win" then
    finish_round(true)
  elseif outcome == "lose" then
    finish_round(false)
  end
end

local function move_sel(delta)
  local s = game.state
  s.sel = (s.sel - 1 + delta) % COLORS + 1
end

local function request_quit()
  if love.system.getOS() == "Web" then
    game.state.scene = "title"
  else
    love.event.quit()
  end
end

-- Input is mapped to a few actions shared by keyboard, gamepad and mouse.
local function action(a, arg)
  local s = game.state
  if a == "quit" then
    request_quit()
  elseif s.scene == "title" then
    if a == "left" or a == "up" then
      s.size = (s.size - 2) % #SIZES + 1
    elseif a == "right" or a == "down" then
      s.size = s.size % #SIZES + 1
    elseif a == "ok" then
      start_round()
    end
  elseif s.scene == "play" then
    if a == "up" or a == "left" then
      move_sel(-1)
    elseif a == "down" or a == "right" then
      move_sel(1)
    elseif a == "ok" then
      pick(s.sel)
    elseif a == "color" then
      s.sel = arg
      pick(arg)
    elseif a == "new" then
      start_round()
    elseif a == "back" then
      s.scene = "title"
    end
  elseif s.scene == "gameover" then
    if a == "ok" or a == "new" then
      start_round()
    elseif a == "back" then
      s.scene = "title"
    end
  end
end

function game.load()
  love.graphics.setBackgroundColor(0.06, 0.08, 0.14)
  fonts.title = love.graphics.newFont(44)
  fonts.big = love.graphics.newFont(28)
  fonts.hud = love.graphics.newFont(20)
  fonts.body = love.graphics.newFont(15)
  fonts.small = love.graphics.newFont(12)
  game.state.scene = "title"
  game.state.st = nil
  game.state.elapsed = 0
  game.state.pop = {}
  game.state.stats = load_stats()
end

function game.update(dt)
  game.state.elapsed = game.state.elapsed + dt
end

local KEYS = {
  escape = "quit",
  left = "left", a = "left",
  right = "right", d = "right",
  up = "up", w = "up",
  down = "down", s = "down",
  space = "ok", ["return"] = "ok", kpenter = "ok", z = "ok",
  r = "new", n = "new",
  backspace = "back", x = "back",
}

function game.keypressed(key)
  local n = tonumber(key)
  if n and n >= 1 and n <= COLORS then
    action("color", n)
  elseif KEYS[key] then
    action(KEYS[key])
  end
end

local PAD = {
  back = "quit",
  dpleft = "left", dpright = "right", dpup = "up", dpdown = "down",
  a = "ok", start = "ok",
  b = "back",
  y = "new",
}

function game.gamepadpressed(_, button)
  if PAD[button] then action(PAD[button]) end
end

-- Maps window coordinates to the virtual 640x480 canvas.
local function to_virtual(x, y)
  local sw, sh = love.graphics.getDimensions()
  local scale = math.min(sw / W, sh / H)
  local ox, oy = math.floor((sw - W * scale) / 2), math.floor((sh - H * scale) / 2)
  return (x - ox) / scale, (y - oy) / scale
end

function game.mousepressed(x, y, button)
  if button ~= 1 then return end
  local s = game.state
  local vx, vy = to_virtual(x, y)
  if s.scene ~= "play" then
    action("ok")
    return
  end
  -- Clicking a board cell picks that cell's colour.
  local ox, oy, c = board_origin()
  local cx, cy = math.floor((vx - ox) / c) + 1, math.floor((vy - oy) / c) + 1
  if cx >= 1 and cy >= 1 and cx <= s.st.w and cy <= s.st.h then
    action("color", s.st.grid[cy][cx])
    return
  end
  -- Clicking a palette swatch picks that colour.
  for i = 1, COLORS do
    local sy = SWATCH_Y + (i - 1) * (SWATCH_H + SWATCH_GAP)
    if vx >= PANEL_X and vx <= W - 20 and vy >= sy and vy <= sy + SWATCH_H then
      action("color", i)
      return
    end
  end
end

-- Small glyph per colour so the palette also reads without colour vision.
local function draw_glyph(i, cx, cy, r)
  love.graphics.setColor(0.06, 0.08, 0.14, 0.85)
  love.graphics.setLineWidth(2)
  if i == 1 then
    love.graphics.circle("fill", cx, cy, r * 0.55)
  elseif i == 2 then
    love.graphics.polygon("fill", cx, cy - r * 0.7, cx + r * 0.65, cy + r * 0.5, cx - r * 0.65, cy + r * 0.5)
  elseif i == 3 then
    love.graphics.rectangle("fill", cx - r * 0.5, cy - r * 0.5, r, r)
  elseif i == 4 then
    love.graphics.polygon("fill", cx, cy - r * 0.7, cx + r * 0.7, cy, cx, cy + r * 0.7, cx - r * 0.7, cy)
  elseif i == 5 then
    love.graphics.circle("line", cx, cy, r * 0.55)
  else
    love.graphics.line(cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55)
    love.graphics.line(cx - r * 0.55, cy + r * 0.55, cx + r * 0.55, cy - r * 0.55)
  end
end

local function draw_mini_board(cx, cy, cell, n, t)
  -- Decorative swirl of colours for the title card.
  for y = 1, n do
    for x = 1, n do
      local v = math.sin(x * 0.9 + t * 0.6) + math.cos(y * 0.7 - t * 0.4) + (x + y) * 0.15
      local i = math.floor(v * 1.7) % COLORS + 1
      if x + y <= 3 + math.floor(t * 1.5) % (n * 2) then i = 4 end
      local col = PALETTE[i]
      love.graphics.setColor(col[1], col[2], col[3])
      love.graphics.rectangle("fill", cx + (x - 1 - n / 2) * cell, cy + (y - 1 - n / 2) * cell, cell - 1, cell - 1, 2, 2)
    end
  end
end

local function draw_title()
  local s = game.state
  local cx = W / 2

  draw_mini_board(cx, 120, 13, 8, s.elapsed)

  love.graphics.setFont(fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("FLOODER", 0, 196, W, "center")

  love.graphics.setFont(fonts.body)
  love.graphics.setColor(0.72, 0.78, 0.90)
  love.graphics.printf("flood the board in as few moves as you can", 0, 250, W, "center")

  -- Board size picker
  local y = 300
  local bw = 128
  local x0 = cx - (bw * #SIZES + 12 * (#SIZES - 1)) / 2
  for i, size in ipairs(SIZES) do
    local x = x0 + (i - 1) * (bw + 12)
    local on = i == s.size
    love.graphics.setColor(on and 0.20 or 0.11, on and 0.30 or 0.16, on and 0.50 or 0.28)
    love.graphics.rectangle("fill", x, y, bw, 54, 10, 10)
    if on then
      love.graphics.setColor(1.0, 0.86, 0.24)
      love.graphics.setLineWidth(3)
      love.graphics.rectangle("line", x, y, bw, 54, 10, 10)
    end
    love.graphics.setFont(fonts.hud)
    love.graphics.setColor(1, 1, 1, on and 1 or 0.6)
    love.graphics.printf(size.name, x, y + 6, bw, "center")
    love.graphics.setFont(fonts.small)
    love.graphics.printf(size.n .. " x " .. size.n, x, y + 32, bw, "center")
  end

  local stat = s.stats[s.size]
  love.graphics.setFont(fonts.body)
  love.graphics.setColor(0.65, 0.72, 0.86)
  local line = stat.played > 0
    and ("WON " .. stat.won .. " / " .. stat.played .. "   ·   STREAK " .. stat.streak .. "   ·   BEST STREAK " .. stat.best_streak)
    or "beat the bot: finish within its move count"
  love.graphics.printf(line, 0, 372, W, "center")

  local blink = 0.6 + 0.4 * math.sin(s.elapsed * 4)
  love.graphics.setFont(fonts.hud)
  love.graphics.setColor(1.0, 0.86, 0.24, blink)
  love.graphics.printf("PRESS A TO PLAY", 0, 412, W, "center")
end

local function draw_board()
  local s = game.state
  local st = s.st
  local ox, oy, c = board_origin()
  local n = st.w

  love.graphics.setColor(0.10, 0.14, 0.24)
  love.graphics.rectangle("fill", ox - 8, oy - 8, c * n + 16, c * n + 16, 10, 10)

  -- Cells that the selected colour would absorb.
  local preview = {}
  if s.scene == "play" then
    for _, p in ipairs(rules.preview(st, s.sel)) do
      preview[(p.y - 1) * n + p.x] = true
    end
  end

  local pulse = 0.5 + 0.5 * math.sin(s.elapsed * 7)
  for y = 1, st.h do
    for x = 1, n do
      local k = (y - 1) * n + x
      local col = PALETTE[st.grid[y][x]]
      local inset = 0
      local t0 = s.pop[k]
      if t0 then
        local t = s.elapsed - t0
        if t < 0 then
          inset = c * 0.5
        elseif t < 0.18 then
          inset = c * 0.5 * (1 - t / 0.18) - c * 0.12 * math.sin(t / 0.18 * math.pi)
        end
      end
      love.graphics.setColor(col[1], col[2], col[3])
      love.graphics.rectangle("fill", ox + (x - 1) * c + inset, oy + (y - 1) * c + inset, c - inset * 2, c - inset * 2)
      if preview[k] then
        love.graphics.setColor(1, 1, 1, 0.35 + 0.45 * pulse)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", ox + (x - 1) * c + 3, oy + (y - 1) * c + 3, c - 6, c - 6, 3, 3)
      end
    end
  end
end

local function draw_panel()
  local s = game.state
  local st = s.st
  local x, w = PANEL_X, W - 20 - PANEL_X

  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.65, 0.72, 0.86)
  love.graphics.print("MOVES", x, 34)
  love.graphics.setFont(fonts.big)
  local left = st.max_moves - st.moves
  if left <= 3 and not st.won then
    love.graphics.setColor(0.95, 0.40, 0.42)
  else
    love.graphics.setColor(1, 1, 1)
  end
  love.graphics.print(st.moves .. " / " .. st.max_moves, x, 50)

  -- Progress bar: share of the board flooded.
  local frac = rules.size(st) / (st.w * st.h)
  love.graphics.setColor(0.13, 0.18, 0.30)
  love.graphics.rectangle("fill", x, 96, w, 12, 6, 6)
  local col = PALETTE[st.grid[1][1]]
  love.graphics.setColor(col[1], col[2], col[3])
  love.graphics.rectangle("fill", x, 96, math.max(12, w * frac), 12, 6, 6)
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.65, 0.72, 0.86)
  love.graphics.print(math.floor(frac * 100 + 0.5) .. "% FLOODED", x, 114)

  local current = st.grid[1][1]
  for i = 1, COLORS do
    local sy = SWATCH_Y + (i - 1) * (SWATCH_H + SWATCH_GAP)
    local pc = PALETTE[i]
    local dim = i == current and 0.35 or 1
    love.graphics.setColor(pc[1] * dim, pc[2] * dim, pc[3] * dim)
    love.graphics.rectangle("fill", x, sy, w, SWATCH_H, 8, 8)
    draw_glyph(i, x + 22, sy + SWATCH_H / 2, 10)
    love.graphics.setFont(fonts.small)
    love.graphics.setColor(0.06, 0.08, 0.14, 0.85)
    love.graphics.print(tostring(i), x + w - 16, sy + 4)
    if i == s.sel and s.scene == "play" then
      love.graphics.setColor(1, 1, 1)
      love.graphics.setLineWidth(3)
      love.graphics.rectangle("line", x - 4, sy - 4, w + 8, SWATCH_H + 8, 10, 10)
      local g = rules.gain(st, i)
      love.graphics.setFont(fonts.hud)
      love.graphics.setColor(0.06, 0.08, 0.14)
      love.graphics.printf("+" .. g, x, sy + 9, w - 24, "right")
    end
  end

  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.50, 0.57, 0.72)
  love.graphics.printf("A pick · B menu · Y new", x - 10, 448, w + 20, "center")
end

local function draw_gameover()
  local s = game.state
  local st = s.st
  local ox, oy, c = board_origin()
  local bw = c * st.w
  local cx, cy = ox + bw / 2, oy + bw / 2

  love.graphics.setColor(0.04, 0.06, 0.12, 0.85)
  love.graphics.rectangle("fill", cx - 170, cy - 80, 340, 160, 12, 12)
  love.graphics.setColor(st.won and 1.0 or 0.95, st.won and 0.86 or 0.32, st.won and 0.24 or 0.36)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", cx - 170, cy - 80, 340, 160, 12, 12)

  love.graphics.setFont(fonts.big)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(st.won and "FLOODED!" or "OUT OF MOVES", cx - 170, cy - 62, 340, "center")

  local stat = s.stats[s.size]
  love.graphics.setFont(fonts.body)
  love.graphics.setColor(0.80, 0.85, 0.94)
  local msg
  if st.won then
    local spare = st.max_moves - st.moves
    msg = "in " .. st.moves .. " moves"
      .. (spare > 0 and (", " .. spare .. " to spare") or ", just in time")
  else
    msg = math.floor(rules.size(st) / (st.w * st.h) * 100 + 0.5) .. "% flooded"
  end
  love.graphics.printf(msg .. "\nstreak " .. stat.streak, cx - 170, cy - 18, 340, "center")

  love.graphics.setFont(fonts.hud)
  love.graphics.setColor(1.0, 0.86, 0.24)
  love.graphics.printf("A: NEW BOARD", cx - 170, cy + 38, 340, "center")
end

function game.draw()
  local sw, sh = love.graphics.getDimensions()
  local scale = math.min(sw / W, sh / H)
  love.graphics.push()
  love.graphics.translate(math.floor((sw - W * scale) / 2), math.floor((sh - H * scale) / 2))
  love.graphics.scale(scale)

  love.graphics.setColor(0.06, 0.08, 0.14)
  love.graphics.rectangle("fill", 0, 0, W, H)

  if game.state.scene == "title" then
    draw_title()
  else
    draw_board()
    draw_panel()
    if game.state.scene == "gameover" then draw_gameover() end
  end

  love.graphics.pop()
end

return game
