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

-- Curated PICO-8-inspired 6-colour palette balanced for both Dark & Light modes.
local PALETTE = {
  { 0.93, 0.18, 0.34 }, -- 1: crimson
  { 0.96, 0.67, 0.11 }, -- 2: amber-gold
  { 0.09, 0.75, 0.38 }, -- 3: emerald
  { 0.17, 0.60, 0.95 }, -- 4: azure
  { 0.55, 0.33, 0.82 }, -- 5: plum
  { 0.95, 0.44, 0.66 }, -- 6: rose
}

local THEMES = {
  dark = {
    bg = { 0.094, 0.106, 0.153 },       -- deep PICO-8 ink slate
    surface = { 0.137, 0.153, 0.216 },  -- subtle raised surface
    well = { 0.063, 0.071, 0.106 },     -- recessed board / track well
    border = { 0.282, 0.314, 0.424 },   -- crisp 2px structural border
    text = { 0.980, 0.945, 0.910 },     -- PICO-8 warm off-white (#FFF1E8)
    muted = { 0.545, 0.576, 0.682 },    -- quiet secondary text
    accent = { 1.000, 0.882, 0.240 },   -- crisp gold focus highlight
    danger = { 0.960, 0.200, 0.345 },   -- signal crimson
    frontier = { 0.990, 0.960, 0.920 }, -- flooded region outline
    scrim = { 0.055, 0.063, 0.098, 0.80 },
    bar_ok = { 0.14, 0.78, 0.44 },
    bar_warn = { 0.96, 0.67, 0.11 },
  },
  light = {
    bg = { 0.957, 0.937, 0.898 },       -- warm paper cream
    surface = { 0.902, 0.878, 0.827 },  -- subtle paper card
    well = { 0.835, 0.808, 0.753 },     -- recessed track / board seam
    border = { 0.620, 0.588, 0.533 },   -- matte stone border
    text = { 0.114, 0.133, 0.216 },     -- deep PICO-8 indigo ink
    muted = { 0.435, 0.427, 0.459 },    -- quiet secondary ink
    accent = { 0.114, 0.133, 0.216 },   -- crisp ink focus highlight
    danger = { 0.840, 0.125, 0.260 },   -- deep crimson
    frontier = { 0.114, 0.133, 0.216 }, -- crisp ink region outline
    scrim = { 0.957, 0.937, 0.898, 0.84 },
    bar_ok = { 0.114, 0.133, 0.216 },
    bar_warn = { 0.86, 0.54, 0.06 },
  },
}

-- Geometry (virtual 640x480 pixels) — board dominates the screen.
local TOP_Y = 14
local BOARD_X, BOARD_Y, BOARD_PX = 24, 46, 420
local SIDE_X, SIDE_W = 466, 150
local SWATCH_X, SWATCH_W, SWATCH_H, SWATCH_STEP = SIDE_X + 16, SIDE_W - 16, 44, 54
local THEME_BTN = { x = SIDE_X + 16, y = 388, w = SIDE_W - 16, h = 28 }
local TITLE_THEME_BTN = { x = 442, y = 440, w = 114, h = 26 }

local fonts = {}

game.state = {
  scene = "title",
  st = nil,
  size = 2,
  sel = 1,
  theme = "dark",
  elapsed = 0,
  pop = {},
  stats = {},
  stamp = 0,
  gauge = 1,
}

local function rng(n)
  return love.math.random(n)
end

local function cur_theme()
  return THEMES[game.state.theme] or THEMES.dark
end

---------------------------------------------------------------------------
-- Stats & theme persistence

local function blank_stats()
  local t = {}
  for i = 1, #SIZES do
    t[i] = { played = 0, won = 0, streak = 0, best_streak = 0, best_spare = -1 }
  end
  return t
end

-- stats.txt holds lines like "2 played 5" (size index, field, value),
-- plus optional "0 theme 1" (0 = dark, 1 = light).
local function load_stats()
  local t = blank_stats()
  local theme = "dark"
  if not love.filesystem.getInfo(SAVE_FILE) then return t, theme end
  local raw = love.filesystem.read(SAVE_FILE) or ""
  for i, k, v in raw:gmatch("(%d+) (%a[%w_]*) (%-?%d+)") do
    i = tonumber(i)
    v = tonumber(v)
    if i == 0 and k == "theme" then
      theme = (v == 1) and "light" or "dark"
    elseif t[i] and t[i][k] ~= nil then
      t[i][k] = v
    end
  end
  return t, theme
end

local function save_stats()
  local lines = {}
  for i, s in ipairs(game.state.stats) do
    for _, k in ipairs({ "played", "won", "streak", "best_streak", "best_spare" }) do
      lines[#lines + 1] = i .. " " .. k .. " " .. s[k]
    end
  end
  lines[#lines + 1] = "0 theme " .. (game.state.theme == "light" and 1 or 0)
  love.filesystem.write(SAVE_FILE, table.concat(lines, "\n") .. "\n")
end

local function toggle_theme()
  local s = game.state
  s.theme = (s.theme == "dark") and "light" or "dark"
  local th = cur_theme()
  love.graphics.setBackgroundColor(th.bg[1], th.bg[2], th.bg[3])
  save_stats()
end

---------------------------------------------------------------------------
-- Layout helpers (also used by tests to aim mouse clicks)

local function board_origin()
  local n = game.state.st.w
  local c = math.floor(BOARD_PX / n)
  local pad = math.floor((BOARD_PX - c * n) / 2)
  return BOARD_X + pad, BOARD_Y + pad, c
end

function game.cell_center(x, y)
  local ox, oy, c = board_origin()
  return ox + (x - 0.5) * c, oy + (y - 0.5) * c
end

-- Vertical sidebar colour swatches (i = 1..6).
local function swatch_rect(i)
  return SWATCH_X, BOARD_Y + (i - 1) * SWATCH_STEP, SWATCH_W, SWATCH_H
end

function game.orb_center(i)
  local rx, ry, rw, rh = swatch_rect(i)
  return rx + rw / 2, ry + rh / 2
end

---------------------------------------------------------------------------
-- Game flow

local function start_round()
  local s = game.state
  local n = SIZES[s.size].n
  local st = rules.new(n, n, COLORS, 1, rng)
  -- The move limit is what a greedy bot needs, so every board is winnable.
  st.max_moves = rules.greedy_moves(st)
  s.st = st
  s.scene = "play"
  s.sel = st.grid[1][1] % COLORS + 1
  s.stamp = 0
  s.gauge = 1
  -- Subtle crisp deal cascade from the top-left origin.
  s.pop = {}
  for y = 1, n do
    for x = 1, n do
      s.pop[(y - 1) * n + x] = s.elapsed + (x + y) * 0.010
    end
  end
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
  s.stamp = s.elapsed
  s.scene = "gameover"
end

local function pick(c)
  local s = game.state
  if s.scene ~= "play" or not s.st then return end
  local outcome, gained = rules.flood(s.st, c)
  if outcome == "same" or outcome == "over" then return end
  for _, p in ipairs(gained) do
    s.pop[(p.y - 1) * s.st.w + p.x] = s.elapsed + p.d * 0.022
  end
  if outcome == "win" then
    finish_round(true)
  elseif outcome == "lose" then
    finish_round(false)
  end
end

local function request_quit()
  if love.system.getOS() == "Web" then
    game.state.scene = "title"
  else
    love.event.quit()
  end
end

-- Input is mapped to actions shared by keyboard, gamepad and mouse.
local function action(a, arg)
  local s = game.state
  if a == "quit" then
    request_quit()
  elseif a == "theme" then
    toggle_theme()
  elseif s.scene == "title" then
    if a == "left" or a == "up" then
      s.size = (s.size - 2) % #SIZES + 1
    elseif a == "right" or a == "down" then
      s.size = s.size % #SIZES + 1
    elseif a == "ok" then
      start_round()
    end
  elseif s.scene == "play" then
    -- Up/Down navigate the vertical colour sidebar; Left/Right mirror it for ergonomics.
    if a == "up" or a == "left" then
      s.sel = (s.sel - 2) % COLORS + 1
    elseif a == "down" or a == "right" then
      s.sel = s.sel % COLORS + 1
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
  love.graphics.setDefaultFilter("nearest", "nearest")
  local bold = "assets/fonts/Silkscreen-Bold.ttf"
  local reg = "assets/fonts/Silkscreen-Regular.ttf"
  fonts.logo = love.graphics.newFont(bold, 48)
  fonts.banner = love.graphics.newFont(bold, 32)
  fonts.hud = love.graphics.newFont(bold, 16)
  fonts.body = love.graphics.newFont(reg, 16)
  fonts.small = love.graphics.newFont(reg, 12)
  fonts.micro = love.graphics.newFont(reg, 12)
  game.state.scene = "title"
  game.state.st = nil
  game.state.elapsed = 0
  game.state.pop = {}
  local stats, theme = load_stats()
  game.state.stats = stats
  game.state.theme = theme
  local th = cur_theme()
  love.graphics.setBackgroundColor(th.bg[1], th.bg[2], th.bg[3])
end

function game.update(dt)
  local s = game.state
  s.elapsed = s.elapsed + dt
  if s.st then
    local target = 1 - s.st.moves / s.st.max_moves
    s.gauge = s.gauge + (target - s.gauge) * math.min(1, dt * 14)
  end
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
  t = "theme",
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
  x = "theme",
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

local function hit_rect(vx, vy, r)
  return vx >= r.x and vx <= r.x + r.w and vy >= r.y and vy <= r.y + r.h
end

function game.mousepressed(x, y, button)
  if button ~= 1 then return end
  local s = game.state
  local vx, vy = to_virtual(x, y)
  if s.scene == "title" then
    if hit_rect(vx, vy, TITLE_THEME_BTN) then
      action("theme")
      return
    end
    -- Clicking a size option selects or starts it
    local cw, ch, gap = 136, 128, 16
    local x0, y0 = math.floor((W - (cw * 3 + gap * 2)) / 2), 184
    for i = 1, #SIZES do
      local cx = x0 + (i - 1) * (cw + gap)
      if vx >= cx and vx <= cx + cw and vy >= y0 and vy <= y0 + ch then
        if s.size == i then
          action("ok")
        else
          s.size = i
        end
        return
      end
    end
    action("ok")
    return
  end
  if s.scene ~= "play" then
    if hit_rect(vx, vy, THEME_BTN) then
      action("theme")
      return
    end
    action("ok")
    return
  end
  if hit_rect(vx, vy, THEME_BTN) then
    action("theme")
    return
  end
  local ox, oy, c = board_origin()
  local cx, cy = math.floor((vx - ox) / c) + 1, math.floor((vy - oy) / c) + 1
  if cx >= 1 and cy >= 1 and cx <= s.st.w and cy <= s.st.h then
    action("color", s.st.grid[cy][cx])
    return
  end
  for i = 1, COLORS do
    local rx, ry, rw, rh = swatch_rect(i)
    if vx >= rx - 14 and vx <= rx + rw + 4 and vy >= ry - 2 and vy <= ry + rh + 2 then
      action("color", i)
      return
    end
  end
end

---------------------------------------------------------------------------
-- Drawing primitives

local lg -- love.graphics, bound in game.draw

local function setc(col, a)
  lg.setColor(col[1], col[2], col[3], a or col[4] or 1)
end

local function shade(col, k, a)
  lg.setColor(math.min(1, col[1] * k), math.min(1, col[2] * k), math.min(1, col[3] * k), a or 1)
end

local function mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Six clean, adult, pixel-crisp geometric marks (no sparkly stars).
local function glyph(i, cx, cy, r, col, alpha)
  cx, cy = math.floor(cx + 0.5), math.floor(cy + 0.5)
  local s = math.max(3, math.floor(r + 0.5))
  lg.setColor(col[1], col[2], col[3], alpha or 0.92)
  if i == 1 then
    -- Solid square
    local hs = math.max(2, math.floor(s * 0.58))
    lg.rectangle("fill", cx - hs, cy - hs, hs * 2, hs * 2)
  elseif i == 2 then
    -- Crisp pixel plus (+)
    local arm = math.max(3, math.floor(s * 0.78))
    local th = math.max(2, math.floor(s * 0.34))
    local hth = math.floor(th / 2)
    lg.rectangle("fill", cx - arm, cy - hth, arm * 2, th)
    lg.rectangle("fill", cx - hth, cy - arm, th, arm * 2)
  elseif i == 3 then
    -- Hollow square frame
    local hs = math.max(3, math.floor(s * 0.65))
    lg.setLineWidth(math.max(2, math.floor(s * 0.28)))
    lg.rectangle("line", cx - hs, cy - hs, hs * 2, hs * 2)
  elseif i == 4 then
    -- Crisp diamond
    local d = math.max(3, math.floor(s * 0.80))
    lg.polygon("fill", cx, cy - d, cx + d, cy, cx, cy + d, cx - d, cy)
  elseif i == 5 then
    -- Hollow ring
    lg.setLineWidth(math.max(2, math.floor(s * 0.28)))
    lg.circle("line", cx, cy, math.max(3, math.floor(s * 0.62)))
  else
    -- Upward triangle
    local d = math.max(3, math.floor(s * 0.74))
    lg.polygon("fill", cx, cy - d, cx + d, cy + math.floor(d * 0.78), cx - d, cy + math.floor(d * 0.78))
  end
end

-- Flat PICO-8 tactile tile: matte colour face, crisp 2px bottom lip, subtle mark.
local function pixel_tile(x, y, s, col, idx, dim, show_glyph)
  if s <= 2 then return end
  local th = cur_theme()
  local base = dim and mix(col, th.bg, dim) or col
  local lip = math.max(2, math.floor(s * 0.10))
  -- Bottom shadow lip (flat pixel depth, zero white gloss)
  shade(base, 0.72)
  lg.rectangle("fill", x, y, s, s)
  -- Main flat matte face
  setc(base)
  lg.rectangle("fill", x, y, s, s - lip)

  -- Quiet tone-on-tone colour-blind mark
  if show_glyph and idx and s >= 18 then
    local gr = math.max(4, math.floor((s - lip) * 0.25))
    glyph(idx, x + s / 2, y + (s - lip) / 2, gr, { 1, 1, 1 }, dim and 0.16 or 0.34)
  end
end

-- Crisp corner lock brackets (used on previewed board tiles).
local function corner_ticks(x, y, w, h, len, col, lw)
  lg.setLineWidth(lw or 2)
  setc(col)
  lg.line(x, y + len, x, y, x + len, y)
  lg.line(x + w - len, y, x + w, y, x + w, y + len)
  lg.line(x + w, y + h - len, x + w, y + h, x + w - len, y + h)
  lg.line(x + len, y + h, x, y + h, x, y + h - len)
end

-- Crisp pixel theme button (works on title and gameplay).
local function draw_theme_chip(rect)
  local th = cur_theme()
  local is_dark = game.state.theme == "dark"
  setc(th.surface)
  lg.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
  lg.setLineWidth(1.5)
  setc(th.border)
  lg.rectangle("line", rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1)

  -- Tiny half-filled pixel icon
  local ix, iy = rect.x + 9, rect.y + math.floor((rect.h - 10) / 2)
  setc(th.text)
  lg.rectangle("line", ix, iy, 10, 10)
  if is_dark then
    lg.rectangle("fill", ix, iy, 5, 10)
  else
    lg.rectangle("fill", ix + 5, iy, 5, 10)
  end

  lg.setFont(fonts.micro)
  setc(th.text)
  lg.printf(is_dark and "X:DARK" or "X:LIGHT", rect.x + 22, rect.y + 6, rect.w - 24, "center")
end

---------------------------------------------------------------------------
-- Scenes

local function draw_title()
  local s = game.state
  local th = cur_theme()
  setc(th.bg)
  lg.rectangle("fill", 0, 0, W, H)

  -- Minimal 6-colour palette strip above title (fits neatly inside cart crop x=80..560)
  local sq, sq_gap = 20, 6
  local strip_w = COLORS * sq + (COLORS - 1) * sq_gap
  local sx0 = math.floor((W - strip_w) / 2)
  for i = 1, COLORS do
    pixel_tile(sx0 + (i - 1) * (sq + sq_gap), 42, sq, PALETTE[i], nil, nil, false)
  end

  -- Crisp pixel wordmark
  lg.setFont(fonts.logo)
  setc(th.well)
  lg.printf("FLOODER", 3, 79, W, "center")
  setc(th.text)
  lg.printf("FLOODER", 0, 76, W, "center")

  -- Quiet one-line premise
  lg.setFont(fonts.small)
  setc(th.muted)
  lg.printf("FLOOD THE BOARD WITHIN THE MOVE LIMIT", 80, 138, W - 160, "center")

  -- Three minimal stage cards (all inside x=100..540 so cart.png stays crisp & unclipped)
  local cw, ch, gap = 136, 128, 16
  local x0 = math.floor((W - (cw * 3 + gap * 2)) / 2)
  local y0 = 184

  for i, size in ipairs(SIZES) do
    local on = (i == s.size)
    local cx = x0 + (i - 1) * (cw + gap)
    local cy = y0

    setc(on and th.surface or th.bg)
    lg.rectangle("fill", cx, cy, cw, ch)
    lg.setLineWidth(on and 2.5 or 1.5)
    setc(on and th.accent or th.border)
    lg.rectangle("line", cx + 1, cy + 1, cw - 2, ch - 2)

    -- Proportional flat pixel mini-board preview (3x3, 4x4, 5x5)
    local m = i + 2
    local box = 60
    local cell = math.floor(box / m)
    local gw = cell * m
    local gx = math.floor(cx + (cw - gw) / 2)
    local gy = cy + 16
    setc(th.well)
    lg.rectangle("fill", gx - 2, gy - 2, gw + 4, gw + 4)

    local fc = PALETTE[((i * 2) % COLORS) + 1]
    for yy = 1, m do
      for xx = 1, m do
        local tx, ty = gx + (xx - 1) * cell, gy + (yy - 1) * cell
        if xx + yy <= i + 2 then
          setc(fc)
          lg.rectangle("fill", tx, ty, cell, cell)
        else
          local ci = ((xx * 3 + yy * 5 + i * 7) % COLORS) + 1
          if ci == ((i * 2) % COLORS) + 1 then ci = (ci % COLORS) + 1 end
          pixel_tile(tx + 0.5, ty + 0.5, cell - 1, PALETTE[ci], nil, on and nil or 0.42, false)
        end
      end
    end

    lg.setFont(fonts.hud)
    setc(on and th.text or th.muted)
    lg.printf(size.name, cx, cy + 84, cw, "center")

    lg.setFont(fonts.small)
    setc(on and th.accent or th.muted)
    lg.printf(size.n .. "X" .. size.n, cx, cy + 106, cw, "center")

    -- Simple minimal selector caret above active card
    if on then
      setc(th.accent)
      lg.polygon("fill", cx + cw / 2 - 6, cy - 11, cx + cw / 2 + 6, cy - 11, cx + cw / 2, cy - 4)
    end
  end

  -- Quiet single-line stats
  local stat = s.stats[s.size]
  lg.setFont(fonts.small)
  setc(th.muted)
  if stat.played > 0 then
    local line = "WINS " .. stat.won .. "/" .. stat.played
      .. "   -   STREAK " .. stat.streak
      .. "   -   BEST " .. stat.best_streak
    lg.printf(line, 80, 336, W - 160, "center")
  else
    lg.printf("EVERY BOARD IS SOLVABLE WITHIN THE LIMIT", 80, 336, W - 160, "center")
  end

  -- Calm, confident start prompt
  lg.setFont(fonts.hud)
  setc(th.text)
  lg.printf("PRESS A OR ENTER TO PLAY", 80, 384, W - 160, "center")

  -- Ultra-minimal bottom control line + clickable theme chip
  lg.setLineWidth(1)
  setc(th.border, 0.5)
  lg.line(84, 432, W - 84, 432)

  lg.setFont(fonts.micro)
  setc(th.muted)
  lg.print("< > SIZE     A PLAY", 90, 449)
  draw_theme_chip(TITLE_THEME_BTN)
end

local function draw_top_bar()
  local s = game.state
  local st = s.st
  local th = cur_theme()
  local left = st.max_moves - st.moves
  local danger = left <= 3 and not st.won

  -- Left: compact stage label
  lg.setFont(fonts.small)
  setc(th.muted)
  lg.print(SIZES[s.size].name .. " " .. st.w .. "X" .. st.h, BOARD_X, TOP_Y + 4)

  -- Center: slim horizontal moves progress bar (aligned cleanly above board + sidebar)
  local bar_x = 158
  local bar_w = 374
  local bar_y = TOP_Y + 6
  local bar_h = 12

  setc(th.well)
  lg.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
  lg.setLineWidth(1.5)
  setc(th.border)
  lg.rectangle("line", bar_x + 0.5, bar_y + 0.5, bar_w - 1, bar_h - 1)

  if s.gauge > 0.002 then
    local fill_col = th.bar_ok
    if danger then
      fill_col = th.danger
    elseif s.gauge <= 0.35 then
      fill_col = th.bar_warn
    end
    local fw = math.max(2, math.floor((bar_w - 4) * s.gauge + 0.5))
    setc(fill_col)
    lg.rectangle("fill", bar_x + 2, bar_y + 2, fw, bar_h - 4)
  end

  -- Right: crisp remaining / limit readout
  lg.setFont(fonts.hud)
  setc(danger and th.danger or th.text)
  local readout = tostring(left) .. "/" .. tostring(st.max_moves)
  lg.printf(readout, bar_x + bar_w + 10, TOP_Y + 2, (SIDE_X + SIDE_W) - (bar_x + bar_w + 10), "right")
end

local function draw_board()
  local s = game.state
  local st = s.st
  local th = cur_theme()
  local ox, oy, c = board_origin()
  local n = st.w
  local t = s.elapsed

  -- Minimal 2px board frame
  setc(th.well)
  lg.rectangle("fill", BOARD_X - 2, BOARD_Y - 2, BOARD_PX + 4, BOARD_PX + 4)
  lg.setLineWidth(2)
  setc(th.border)
  lg.rectangle("line", BOARD_X - 2, BOARD_Y - 2, BOARD_PX + 4, BOARD_PX + 4)

  local region = rules.region(st)
  local preview = {}
  if s.scene == "play" then
    for _, p in ipairs(rules.preview(st, s.sel)) do
      preview[(p.y - 1) * n + p.x] = true
    end
  end

  local lose = (s.scene == "gameover" and not st.won)

  -- Pass 1: tiles & seamless fused owned region
  for y = 1, st.h do
    for x = 1, n do
      local k = (y - 1) * n + x
      local ci = st.grid[y][x]
      local col = PALETTE[ci]
      local inset = 0
      local t0 = s.pop[k]
      if t0 then
        local dt = t - t0
        if dt < 0 then
          inset = c * 0.5
        elseif dt < 0.14 then
          inset = c * 0.45 * (1 - dt / 0.14)
        end
      end
      local px, py = ox + (x - 1) * c, oy + (y - 1) * c
      if inset < c * 0.5 then
        if region[k] then
          local fill = lose and mix(col, th.bg, 0.45) or col
          setc(fill)
          local pad = math.floor(inset)
          lg.rectangle("fill", px + pad, py + pad, c - pad * 2, c - pad * 2)
        else
          local pad = math.max(1, math.floor(inset + 0.5))
          local dim = lose and 0.52 or nil
          pixel_tile(px + pad, py + pad, c - pad * 2, col, ci, dim, true)
        end
      end
    end
  end

  -- Pass 2: crisp frontier outline along the exact boundary between owned & unowned cells
  lg.setLineWidth(2)
  setc(th.frontier, lose and 0.45 or 0.92)
  for y = 1, st.h do
    for x = 1, n do
      local k = (y - 1) * n + x
      if region[k] then
        local px, py = ox + (x - 1) * c, oy + (y - 1) * c
        if y > 1 and not region[k - n] then
          lg.line(px, py + 1, px + c, py + 1)
        end
        if y < st.h and not region[k + n] then
          lg.line(px, py + c - 1, px + c, py + c - 1)
        end
        if x > 1 and not region[k - 1] then
          lg.line(px + 1, py, px + 1, py + c)
        end
        if x < n and not region[k + 1] then
          lg.line(px + c - 1, py, px + c - 1, py + c)
        end
      end
    end
  end

  -- Quiet top-left origin marker at (1, 1)
  if region[1] then
    setc(th.frontier, lose and 0.30 or 0.72)
    lg.rectangle("fill", ox + 5, oy + 5, 4, 4)
  end

  -- Pass 3: calm, crisp corner lock ticks on previewed frontier cells
  if s.scene == "play" then
    local blen = math.max(5, math.floor(c * 0.28))
    for y = 1, st.h do
      for x = 1, n do
        local k = (y - 1) * n + x
        if preview[k] then
          local px, py = ox + (x - 1) * c, oy + (y - 1) * c
          corner_ticks(px + 2, py + 2, c - 4, c - 4, blen, { 0, 0, 0, 0.55 }, 3)
          corner_ticks(px + 3, py + 3, c - 6, c - 6, blen - 1, { 1, 1, 1, 0.96 }, 2)
        end
      end
    end
  end
end

local function draw_sidebar()
  local s = game.state
  local st = s.st
  local th = cur_theme()
  local cur_idx = st.grid[1][1]

  -- Vertical stack of 6 colour swatches (navigated with Up/Down)
  for i = 1, COLORS do
    local rx, ry, rw, rh = swatch_rect(i)
    local is_cur = (i == cur_idx)
    local is_sel = (i == s.sel and s.scene == "play")
    local col = PALETTE[i]

    -- Crisp pixel pointer in the left gutter for the active selection
    if is_sel then
      local py = math.floor(ry + rh / 2)
      setc(th.accent)
      lg.polygon("fill", SIDE_X + 2, py - 6, SIDE_X + 2, py + 6, SIDE_X + 10, py)
    end

    if is_cur then
      -- Active flood colour: quiet recessed slot
      setc(th.surface)
      lg.rectangle("fill", rx, ry, rw, rh)
      lg.setLineWidth(is_sel and 2 or 1.5)
      setc(is_sel and th.accent or th.border)
      lg.rectangle("line", rx + 1, ry + 1, rw - 2, rh - 2)

      -- Small muted swatch chip + geometric mark
      setc(mix(col, th.surface, 0.45))
      lg.rectangle("fill", rx + 8, ry + 10, 24, 24)
      glyph(i, rx + 20, ry + 22, 7, th.text, 0.45)

      lg.setFont(fonts.micro)
      setc(th.muted)
      lg.printf("ACTIVE", rx + 36, ry + 15, rw - 44, "right")
    else
      -- Selectable flat PICO-8 colour swatch bar
      shade(col, 0.72)
      lg.rectangle("fill", rx, ry, rw, rh)
      setc(col)
      lg.rectangle("fill", rx, ry, rw, rh - 3)

      -- Geometric colour-blind emblem on the left
      glyph(i, rx + 22, ry + (rh - 3) / 2, 9, { 1, 1, 1 }, 0.94)

      -- Show projected tile gain on the selected row, or quiet key digit on others
      if is_sel then
        local g = rules.gain(st, i)
        -- High-contrast dark ink badge works cleanly in both Dark and Light modes
        local tag = "+" .. tostring(g)
        local tw = math.max(38, fonts.small:getWidth(tag) + 12)
        setc(THEMES.dark.well, 0.86)
        lg.rectangle("fill", rx + rw - tw - 6, ry + 9, tw, 23)
        lg.setFont(fonts.small)
        setc(THEMES.dark.text)
        lg.printf(tag, rx + rw - tw - 6, ry + 13, tw, "center")
      else
        lg.setFont(fonts.micro)
        lg.setColor(0, 0, 0, 0.35)
        lg.printf(tostring(i), rx + rw - 26, ry + 14, 18, "right")
        lg.setColor(1, 1, 1, 0.85)
        lg.printf(tostring(i), rx + rw - 27, ry + 13, 18, "right")
      end

      -- Sharp selection border
      if is_sel then
        lg.setLineWidth(2.5)
        setc(th.accent)
        lg.rectangle("line", rx - 2, ry - 2, rw + 4, rh + 4)
      end
    end
  end

  -- Quiet divider & compact utility footer tucked at bottom of sidebar
  lg.setLineWidth(1)
  setc(th.border, 0.55)
  lg.line(SWATCH_X, 378, SIDE_X + SIDE_W, 378)

  draw_theme_chip(THEME_BTN)

  lg.setFont(fonts.micro)
  setc(th.muted)
  if s.scene == "play" then
    lg.print("A FLOOD", SWATCH_X, 426)
    lg.printf("Y NEW", SWATCH_X, 426, SWATCH_W, "right")
    lg.print("B MENU", SWATCH_X, 446)
    lg.printf("1-6", SWATCH_X, 446, SWATCH_W, "right")
  else
    lg.print("A NEW", SWATCH_X, 426)
    lg.printf("B MENU", SWATCH_X, 426, SWATCH_W, "right")
  end
end

local function draw_gameover()
  local s = game.state
  local st = s.st
  local th = cur_theme()
  local cx, cy = BOARD_X + BOARD_PX / 2, BOARD_Y + BOARD_PX / 2

  -- Calm matte scrim over the board (no sparkles, no confetti)
  setc(th.scrim)
  lg.rectangle("fill", BOARD_X, BOARD_Y, BOARD_PX, BOARD_PX)

  -- Clean minimal result panel
  local pw, ph = 332, 160
  local px, py = math.floor(cx - pw / 2), math.floor(cy - ph / 2)
  setc(th.bg)
  lg.rectangle("fill", px, py, pw, ph)
  lg.setLineWidth(2)
  setc(th.border)
  lg.rectangle("line", px, py, pw, ph)

  -- Crisp 4px top accent rule
  setc(st.won and th.bar_ok or th.danger)
  lg.rectangle("fill", px, py, pw, 4)

  -- Headline
  lg.setFont(fonts.banner)
  setc(st.won and th.text or th.danger)
  lg.printf(st.won and "CLEARED" or "OUT OF MOVES", px, py + 18, pw, "center")

  -- Primary outcome readout
  local stat = s.stats[s.size]
  local primary
  if st.won then
    local spare = st.max_moves - st.moves
    primary = st.moves .. "/" .. st.max_moves .. " MOVES"
      .. (spare > 0 and (" - " .. spare .. " SPARE") or " - PAR")
  else
    local pct = math.floor(rules.size(st) / (st.w * st.h) * 100 + 0.5)
    primary = pct .. "% FLOODED"
  end
  lg.setFont(fonts.body)
  setc(th.text)
  lg.printf(primary, px, py + 62, pw, "center")

  -- Quiet streak stats
  lg.setFont(fonts.small)
  setc(th.muted)
  lg.printf("STREAK " .. stat.streak .. "   -   BEST " .. stat.best_streak, px, py + 90, pw, "center")

  -- Subtle inline next-action cue
  lg.setLineWidth(1)
  setc(th.border, 0.5)
  lg.line(px + 20, py + 116, px + pw - 20, py + 116)
  lg.setFont(fonts.micro)
  setc(th.muted)
  lg.printf(st.won and "A NEW BOARD    B MENU" or "A TRY AGAIN    B MENU", px, py + 128, pw, "center")
end

function game.draw()
  lg = love.graphics
  local sw, sh = lg.getDimensions()
  local scale = math.min(sw / W, sh / H)
  lg.push()
  lg.translate(math.floor((sw - W * scale) / 2), math.floor((sh - H * scale) / 2))
  lg.scale(scale)

  local s = game.state
  local th = cur_theme()
  setc(th.bg)
  lg.rectangle("fill", 0, 0, W, H)

  if s.scene == "title" then
    draw_title()
  else
    draw_top_bar()
    draw_board()
    draw_sidebar()
    if s.scene == "gameover" then
      draw_gameover()
    end
  end

  lg.pop()
end

return game
