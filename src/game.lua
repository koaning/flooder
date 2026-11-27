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

-- Vintage Japanese print poster 6-colour palette (distinct hues & values without shapes).
local PALETTE = {
  { 0.792, 0.239, 0.165 }, -- 1: vermilion red
  { 0.882, 0.494, 0.145 }, -- 2: burnt orange
  { 0.910, 0.722, 0.212 }, -- 3: mustard ochre
  { 0.176, 0.588, 0.478 }, -- 4: vintage teal-green
  { 0.149, 0.412, 0.584 }, -- 5: petrol blue
  { 0.498, 0.243, 0.431 }, -- 6: dusty plum
}

local THEMES = {
  paper = {
    bg = { 0.937, 0.894, 0.808 },       -- warm vintage poster paper (#EFE4CE)
    surface = { 0.886, 0.835, 0.741 },  -- pressed paper stock
    well = { 0.835, 0.780, 0.682 },     -- subtle hairline seam / bar track
    border = { 0.635, 0.588, 0.510 },   -- print rule hairline
    ink = { 0.090, 0.086, 0.078 },      -- matte sumi ink (#171614)
    muted = { 0.412, 0.384, 0.341 },    -- warm secondary ink
    bar_ok = { 0.090, 0.086, 0.078 },   -- solid ink progress bar
    bar_warn = { 0.860, 0.470, 0.140 }, -- burnt orange
    danger = { 0.792, 0.220, 0.153 },   -- vermilion alert
    frontier = { 0.090, 0.086, 0.078 }, -- crisp ink outline around owned territory
    scrim = { 0.937, 0.894, 0.808, 0.78 },
  },
  ink = {
    bg = { 0.106, 0.102, 0.094 },       -- warm matte charcoal (#1B1A18)
    surface = { 0.157, 0.151, 0.139 },  -- raised matte card
    well = { 0.067, 0.063, 0.059 },     -- deep seam / track
    border = { 0.310, 0.294, 0.267 },   -- warm stone rule
    ink = { 0.937, 0.894, 0.808 },      -- warm cream ink (#EFE4CE)
    muted = { 0.580, 0.549, 0.498 },    -- warm muted cream
    bar_ok = { 0.937, 0.894, 0.808 },   -- crisp cream progress bar
    bar_warn = { 0.882, 0.494, 0.145 }, -- burnt orange
    danger = { 0.840, 0.260, 0.180 },   -- warm vermilion
    frontier = { 0.937, 0.894, 0.808 }, -- crisp cream outline around owned territory
    scrim = { 0.067, 0.063, 0.059, 0.78 },
  },
}

-- Geometry (virtual 640x480 pixels) — board dominates the play screen.
local TOP_Y = 12
local BOARD_X, BOARD_Y, BOARD_PX = 24, 46, 420
local SIDE_X, SIDE_W = 466, 150
local SWATCH_X, SWATCH_W, SWATCH_H, SWATCH_STEP = SIDE_X + 20, SIDE_W - 20, 48, 57

-- Title menu hit regions (centered cleanly inside cartridge safe core x=80..560).
local MENU_CARD_W, MENU_CARD_H, MENU_CARD_GAP = 136, 114, 16
local MENU_CARDS_X0 = math.floor((W - (MENU_CARD_W * 3 + MENU_CARD_GAP * 2)) / 2)
local MENU_CARDS_Y = 138
local MENU_OPT_X, MENU_OPT_W, MENU_OPT_H = 128, W - 256, 30
local MENU_THEME_Y = 276
local MENU_MARKS_Y = 310
local MENU_PLAY_RECT = { x = 190, y = 382, w = W - 380, h = 40 }

local fonts = {}

game.state = {
  scene = "title",
  st = nil,
  size = 2,
  sel = 1,
  menu_row = 1,   -- 1 = board size / play, 2 = theme (paper/ink), 3 = marks (off/on)
  theme = "paper",
  marks = false,  -- optional subtle colour-blind marks (off by default)
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
  return THEMES[game.state.theme] or THEMES.paper
end

---------------------------------------------------------------------------
-- Stats & preferences persistence

local function blank_stats()
  local t = {}
  for i = 1, #SIZES do
    t[i] = { played = 0, won = 0, streak = 0, best_streak = 0, best_spare = -1 }
  end
  return t
end

-- stats.txt holds lines like "2 played 5" plus optional "0 theme 1" / "0 marks 1".
local function load_stats()
  local t = blank_stats()
  local theme = "paper"
  local marks = false
  if not love.filesystem.getInfo(SAVE_FILE) then return t, theme, marks end
  local raw = love.filesystem.read(SAVE_FILE) or ""
  for i, k, v in raw:gmatch("(%d+) (%a[%w_]*) (%-?%d+)") do
    i = tonumber(i)
    v = tonumber(v)
    if i == 0 and k == "theme" then
      theme = (v == 1) and "ink" or "paper"
    elseif i == 0 and k == "marks" then
      marks = (v == 1)
    elseif t[i] and t[i][k] ~= nil then
      t[i][k] = v
    end
  end
  return t, theme, marks
end

local function save_stats()
  local lines = {}
  for i, s in ipairs(game.state.stats) do
    for _, k in ipairs({ "played", "won", "streak", "best_streak", "best_spare" }) do
      lines[#lines + 1] = i .. " " .. k .. " " .. s[k]
    end
  end
  lines[#lines + 1] = "0 theme " .. (game.state.theme == "ink" and 1 or 0)
  lines[#lines + 1] = "0 marks " .. (game.state.marks and 1 or 0)
  love.filesystem.write(SAVE_FILE, table.concat(lines, "\n") .. "\n")
end

local function toggle_theme()
  local s = game.state
  s.theme = (s.theme == "paper") and "ink" or "paper"
  local th = cur_theme()
  love.graphics.setBackgroundColor(th.bg[1], th.bg[2], th.bg[3])
  save_stats()
end

local function toggle_marks()
  local s = game.state
  s.marks = not s.marks
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
    s.pop[(p.y - 1) * s.st.w + p.x] = s.elapsed + p.d * 0.020
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
    game.state.menu_row = 1
  else
    love.event.quit()
  end
end

-- Input is mapped to actions shared by keyboard, gamepad and mouse.
local function action(a, arg)
  local s = game.state
  if a == "quit" then
    request_quit()
  elseif s.scene == "title" then
    if a == "up" then
      s.menu_row = (s.menu_row - 2) % 3 + 1
    elseif a == "down" then
      s.menu_row = s.menu_row % 3 + 1
    elseif a == "left" then
      if s.menu_row == 1 then
        s.size = (s.size - 2) % #SIZES + 1
      elseif s.menu_row == 2 then
        toggle_theme()
      else
        toggle_marks()
      end
    elseif a == "right" then
      if s.menu_row == 1 then
        s.size = s.size % #SIZES + 1
      elseif s.menu_row == 2 then
        toggle_theme()
      else
        toggle_marks()
      end
    elseif a == "ok" then
      if s.menu_row == 1 then
        start_round()
      elseif s.menu_row == 2 then
        toggle_theme()
      else
        toggle_marks()
      end
    elseif a == "start" then
      start_round()
    elseif a == "theme" then
      toggle_theme()
    end
  elseif s.scene == "play" then
    -- Up/Down navigate the vertical colour sidebar; Left/Right mirror it.
    if a == "up" or a == "left" then
      s.sel = (s.sel - 2) % COLORS + 1
    elseif a == "down" or a == "right" then
      s.sel = s.sel % COLORS + 1
    elseif a == "ok" or a == "start" then
      pick(s.sel)
    elseif a == "color" then
      s.sel = arg
      pick(arg)
    elseif a == "new" then
      start_round()
    elseif a == "back" then
      s.scene = "title"
      s.menu_row = 1
    end
  elseif s.scene == "gameover" then
    if a == "ok" or a == "start" or a == "new" then
      start_round()
    elseif a == "back" then
      s.scene = "title"
      s.menu_row = 1
    end
  end
end

function game.load()
  local bold = "assets/fonts/Barlow-Bold.ttf"
  local semi = "assets/fonts/Barlow-SemiBold.ttf"
  local med = "assets/fonts/Barlow-Medium.ttf"
  fonts.logo = love.graphics.newFont(bold, 62)
  fonts.banner = love.graphics.newFont(bold, 38)
  fonts.hud = love.graphics.newFont(bold, 20)
  fonts.sub = love.graphics.newFont(semi, 16)
  fonts.body = love.graphics.newFont(semi, 15)
  fonts.small = love.graphics.newFont(semi, 13)
  fonts.micro = love.graphics.newFont(med, 12)
  game.state.scene = "title"
  game.state.menu_row = 1
  game.state.st = nil
  game.state.elapsed = 0
  game.state.pop = {}
  local stats, theme, marks = load_stats()
  game.state.stats = stats
  game.state.theme = theme
  game.state.marks = marks
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
  a = "ok",
  start = "start",
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

local function in_rect(vx, vy, x, y, w, h)
  return vx >= x and vx <= x + w and vy >= y and vy <= y + h
end

function game.mousepressed(x, y, button)
  if button ~= 1 then return end
  local s = game.state
  local vx, vy = to_virtual(x, y)
  if s.scene == "title" then
    for i = 1, #SIZES do
      local cx = MENU_CARDS_X0 + (i - 1) * (MENU_CARD_W + MENU_CARD_GAP)
      if in_rect(vx, vy, cx, MENU_CARDS_Y, MENU_CARD_W, MENU_CARD_H) then
        s.menu_row = 1
        if s.size == i then
          start_round()
        else
          s.size = i
        end
        return
      end
    end
    if in_rect(vx, vy, MENU_OPT_X, MENU_THEME_Y, MENU_OPT_W, MENU_OPT_H) then
      s.menu_row = 2
      toggle_theme()
      return
    end
    if in_rect(vx, vy, MENU_OPT_X, MENU_MARKS_Y, MENU_OPT_W, MENU_OPT_H) then
      s.menu_row = 3
      toggle_marks()
      return
    end
    if in_rect(vx, vy, MENU_PLAY_RECT.x, MENU_PLAY_RECT.y, MENU_PLAY_RECT.w, MENU_PLAY_RECT.h) then
      start_round()
      return
    end
    action("ok")
    return
  end
  if s.scene ~= "play" then
    action("ok")
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
    if vx >= rx - 18 and vx <= rx + rw + 4 and vy >= ry - 3 and vy <= ry + rh + 3 then
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

local function mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Crisp selection caret (▶) pointing right.
local function caret(x, cy, size, col)
  setc(col)
  lg.polygon("fill", x, cy - size, x, cy + size, x + math.floor(size * 1.25), cy)
end

-- Optional subtle geometric marks (only rendered when MARKS: ON is chosen in menu).
local function mark(i, cx, cy, r, col, alpha)
  cx, cy = math.floor(cx + 0.5), math.floor(cy + 0.5)
  local s = math.max(3, math.floor(r + 0.5))
  lg.setColor(col[1], col[2], col[3], alpha or 0.72)
  lg.setLineWidth(1.8)
  if i == 1 then
    lg.circle("fill", cx, cy, s * 0.52)
  elseif i == 2 then
    local arm = math.floor(s * 0.72)
    lg.line(cx - arm, cy, cx + arm, cy)
    lg.line(cx, cy - arm, cx, cy + arm)
  elseif i == 3 then
    local hs = math.floor(s * 0.55)
    lg.rectangle("line", cx - hs, cy - hs, hs * 2, hs * 2)
  elseif i == 4 then
    local d = math.floor(s * 0.72)
    lg.polygon("fill", cx, cy - d, cx + d, cy, cx, cy + d, cx - d, cy)
  elseif i == 5 then
    lg.circle("line", cx, cy, s * 0.58)
  else
    local d = math.floor(s * 0.68)
    lg.polygon("fill", cx, cy - d, cx + d, cy + math.floor(d * 0.75), cx - d, cy + math.floor(d * 0.75))
  end
end

-- Flaring 6-colour retro print ribbon (inspired by vintage Japanese graphic posters).
local function poster_ribbon(y_top, y_bot, w_top, w_bot, alpha)
  local steps = 22
  local cx = W / 2
  for k = 0, steps - 1 do
    local t0, t1 = k / steps, (k + 1) / steps
    -- Smooth gentle outward flare toward the bottom of the poster
    local e0, e1 = t0 * t0, t1 * t1
    local y0 = y_top + (y_bot - y_top) * t0
    local y1 = y_top + (y_bot - y_top) * t1
    local hw0 = (w_top + (w_bot - w_top) * e0) / 2
    local hw1 = (w_top + (w_bot - w_top) * e1) / 2
    local sw0, sw1 = (hw0 * 2) / COLORS, (hw1 * 2) / COLORS
    for i = 1, COLORS do
      local x0a = cx - hw0 + (i - 1) * sw0
      local x0b = x0a + sw0 + 0.4
      local x1a = cx - hw1 + (i - 1) * sw1
      local x1b = x1a + sw1 + 0.4
      setc(PALETTE[i], alpha or 1)
      lg.polygon("fill", x0a, y0, x0b, y0, x1b, y1, x1a, y1)
    end
  end
end

-- Crisp corner ticks for previewed frontier cells.
local function corner_ticks(x, y, w, h, len, col, lw)
  lg.setLineWidth(lw or 2)
  setc(col)
  lg.line(x, y + len, x, y, x + len, y)
  lg.line(x + w - len, y, x + w, y, x + w, y + len)
  lg.line(x + w, y + h - len, x + w, y + h, x + w - len, y + h)
  lg.line(x + len, y + h, x, y + h, x, y + h - len)
end

---------------------------------------------------------------------------
-- Scenes

local function draw_title()
  local s = game.state
  local th = cur_theme()

  setc(th.bg)
  lg.rectangle("fill", 0, 0, W, H)

  -- Subtle editorial poster margin frame (visible on 640x480; clean inside cart.png)
  lg.setLineWidth(1.5)
  setc(th.border, 0.55)
  lg.rectangle("line", 14, 14, W - 28, H - 28)

  -- Iconic 6-colour retro print ribbon flaring cleanly from the header rule to the bottom
  poster_ribbon(114, H - 14, 130, 252, 0.96)

  -- Top bold ink poster headline & subtitle above the rule (cartridge-safe x=80..560)
  lg.setFont(fonts.logo)
  setc(th.ink)
  lg.printf("FLOODER", 80, 18, W - 160, "center")

  lg.setFont(fonts.micro)
  setc(th.muted)
  lg.printf("REPAINT THE BOARD WITHIN THE MOVE LIMIT", 80, 88, W - 160, "center")

  -- Crisp horizontal ink rule anchoring the ribbon cleanly with zero gaps
  setc(th.ink)
  lg.rectangle("fill", 96, 111, W - 192, 3)

  -- Row 1: Board Size Specimen Cards (all 3 inside x=96..544 -> cartridge safe!)
  local row1 = (s.menu_row == 1)
  for i, size in ipairs(SIZES) do
    local on = (i == s.size)
    local cx = MENU_CARDS_X0 + (i - 1) * (MENU_CARD_W + MENU_CARD_GAP)
    local cy = MENU_CARDS_Y

    -- Solid paper/charcoal plate over the ribbon
    setc(on and th.bg or th.surface)
    lg.rectangle("fill", cx, cy, MENU_CARD_W, MENU_CARD_H)
    lg.setLineWidth((on and row1) and 2.5 or 1.5)
    setc((on and row1) and th.ink or th.border)
    lg.rectangle("line", cx + 0.5, cy + 0.5, MENU_CARD_W - 1, MENU_CARD_H - 1)

    -- Pure-colour proportional mini-board specimen (3x3, 4x4, 5x5)
    local m = i + 2
    local box = 54
    local cell = math.floor(box / m)
    local gw = cell * m
    local gx = math.floor(cx + (MENU_CARD_W - gw) / 2)
    local gy = cy + 12
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
          local col = on and PALETTE[ci] or mix(PALETTE[ci], th.surface, 0.35)
          setc(col)
          lg.rectangle("fill", tx + 0.5, ty + 0.5, cell - 1, cell - 1)
        end
      end
    end

    -- Size name & grid dimensions
    lg.setFont(fonts.sub)
    setc(on and th.ink or th.muted)
    lg.printf(size.name, cx, cy + 72, MENU_CARD_W, "center")
    lg.setFont(fonts.micro)
    setc(on and th.ink or th.muted, on and 0.85 or 0.75)
    lg.printf(size.n .. " × " .. size.n, cx, cy + 92, MENU_CARD_W, "center")

    -- Crisp top caret on selected size when Row 1 is focused
    if on and row1 then
      setc(th.ink)
      lg.polygon("fill", cx + MENU_CARD_W / 2 - 6, cy - 9, cx + MENU_CARD_W / 2 + 6, cy - 9, cx + MENU_CARD_W / 2, cy - 2)
    end
  end

  -- Row 2 & Row 3: Clean Menu Options (Theme & Optional Marks live here, NOT in gameplay!)
  local function draw_option_row(row_idx, y, label, val_left, val_right, right_active)
    local focused = (s.menu_row == row_idx)
    setc(th.bg)
    lg.rectangle("fill", MENU_OPT_X, y, MENU_OPT_W, MENU_OPT_H)
    lg.setLineWidth(focused and 2 or 1)
    setc(focused and th.ink or th.border)
    lg.rectangle("line", MENU_OPT_X + 0.5, y + 0.5, MENU_OPT_W - 1, MENU_OPT_H - 1)

    if focused then
      caret(MENU_OPT_X + 10, y + MENU_OPT_H / 2, 5, th.ink)
    end

    lg.setFont(fonts.small)
    setc(focused and th.ink or th.muted)
    lg.print(label, MENU_OPT_X + 26, y + 7)

    -- Two-state clean editorial toggle on the right
    local rx = MENU_OPT_X + MENU_OPT_W - 134
    lg.setFont(fonts.small)
    setc(not right_active and th.ink or th.muted, not right_active and 1 or 0.55)
    lg.printf(val_left, rx, y + 7, 54, "right")
    setc(th.muted, 0.5)
    lg.printf("/", rx + 56, y + 7, 12, "center")
    setc(right_active and th.ink or th.muted, right_active and 1 or 0.55)
    lg.printf(val_right, rx + 70, y + 7, 54, "left")
  end

  draw_option_row(2, MENU_THEME_Y, "THEME", "PAPER", "INK", s.theme == "ink")
  draw_option_row(3, MENU_MARKS_Y, "MARKS", "OFF", "ON", s.marks)

  -- Quiet stats bar seated cleanly on a paper strip
  local stat = s.stats[s.size]
  setc(th.bg)
  lg.rectangle("fill", 128, 348, W - 256, 24)
  lg.setFont(fonts.micro)
  setc(th.muted)
  if stat.played > 0 then
    local line = "WINS " .. stat.won .. "/" .. stat.played
      .. "   ·   STREAK " .. stat.streak
      .. "   ·   BEST " .. stat.best_streak
    lg.printf(line, 128, 353, W - 256, "center")
  else
    lg.printf("EVERY BOARD IS WINNABLE WITHIN THE LIMIT", 128, 353, W - 256, "center")
  end

  -- Bold Matte Ink Play Bar
  local pr = MENU_PLAY_RECT
  setc(th.ink)
  lg.rectangle("fill", pr.x, pr.y, pr.w, pr.h)
  lg.setFont(fonts.hud)
  setc(th.bg)
  lg.printf("PLAY  " .. SIZES[s.size].name, pr.x, pr.y + 8, pr.w, "center")

  -- Minimal single-line footer legend on a crisp paper plate
  setc(th.bg)
  lg.rectangle("fill", 136, 434, W - 272, 22)
  lg.setFont(fonts.micro)
  setc(th.muted)
  lg.printf("D-PAD  NAVIGATE     ·     A / ENTER  SELECT", 136, 438, W - 272, "center")
end

local function draw_top_bar()
  local s = game.state
  local st = s.st
  local th = cur_theme()
  local left = st.max_moves - st.moves
  local danger = left <= 3 and not st.won

  -- Left: compact board size
  lg.setFont(fonts.small)
  setc(th.muted)
  lg.print(SIZES[s.size].name .. "  " .. st.w .. "×" .. st.h, BOARD_X, TOP_Y + 6)

  -- Center: slim horizontal moves remaining bar
  local bar_x = 148
  local bar_w = 386
  local bar_y = TOP_Y + 9
  local bar_h = 10

  setc(th.well)
  lg.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
  lg.setLineWidth(1)
  setc(th.border)
  lg.rectangle("line", bar_x + 0.5, bar_y + 0.5, bar_w - 1, bar_h - 1)

  if s.gauge > 0.002 then
    local fill_col = th.bar_ok
    if danger then
      fill_col = th.danger
    elseif s.gauge <= 0.35 then
      fill_col = th.bar_warn
    end
    local fw = math.max(2, math.floor((bar_w - 2) * s.gauge + 0.5))
    setc(fill_col)
    lg.rectangle("fill", bar_x + 1, bar_y + 1, fw, bar_h - 2)
  end

  -- Right: crisp moves counter
  lg.setFont(fonts.hud)
  setc(danger and th.danger or th.ink)
  local readout = tostring(left) .. " / " .. tostring(st.max_moves)
  lg.printf(readout, bar_x + bar_w + 8, TOP_Y + 1, (SIDE_X + SIDE_W) - (bar_x + bar_w + 8), "right")
end

local function draw_board()
  local s = game.state
  local st = s.st
  local th = cur_theme()
  local ox, oy, c = board_origin()
  local n = st.w
  local t = s.elapsed

  -- Minimal print border around the board
  setc(th.well)
  lg.rectangle("fill", BOARD_X - 2, BOARD_Y - 2, BOARD_PX + 4, BOARD_PX + 4)
  lg.setLineWidth(1.5)
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

  -- Pass 1: pure matte print tiles & fused owned territory
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
          local tile_col = lose and mix(col, th.bg, 0.52) or col
          setc(tile_col)
          lg.rectangle("fill", px + pad, py + pad, c - pad * 2, c - pad * 2)
          if s.marks and c >= 18 then
            mark(ci, px + c / 2, py + c / 2, math.max(4, c * 0.24), { 1, 1, 1 }, lose and 0.18 or 0.40)
          end
        end
      end
    end
  end

  -- Pass 2: crisp ink frontier outline along edges between owned & unowned cells
  lg.setLineWidth(2)
  setc(th.frontier, lose and 0.40 or 0.92)
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

  -- Quiet top-left origin pip
  if region[1] then
    setc(th.frontier, lose and 0.28 or 0.72)
    lg.rectangle("fill", ox + 5, oy + 5, 4, 4)
  end

  -- Pass 3: calm, crisp corner ticks on previewed frontier cells
  if s.scene == "play" then
    local blen = math.max(5, math.floor(c * 0.28))
    for y = 1, st.h do
      for x = 1, n do
        local k = (y - 1) * n + x
        if preview[k] then
          local px, py = ox + (x - 1) * c, oy + (y - 1) * c
          corner_ticks(px + 2, py + 2, c - 4, c - 4, blen, { 0.08, 0.07, 0.06, 0.65 }, 3)
          corner_ticks(px + 3, py + 3, c - 6, c - 6, blen - 1, { 0.98, 0.96, 0.92, 0.96 }, 2)
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

  -- Vertical stack of 6 pure colour bars (Up/Down selects; bold caret marks choice)
  for i = 1, COLORS do
    local rx, ry, rw, rh = swatch_rect(i)
    local is_cur = (i == cur_idx)
    local is_sel = (i == s.sel and s.scene == "play")
    local col = PALETTE[i]

    -- Bold crisp caret in front of the selected colour
    if is_sel then
      caret(SIDE_X + 2, math.floor(ry + rh / 2), 7, th.ink)
    end

    if is_cur then
      -- Active flood colour: quiet recessed slot with a left colour edge bar
      setc(th.surface)
      lg.rectangle("fill", rx, ry, rw, rh)
      setc(col, 0.55)
      lg.rectangle("fill", rx, ry, 8, rh)
      lg.setLineWidth(is_sel and 2 or 1)
      setc(is_sel and th.ink or th.border)
      lg.rectangle("line", rx + 0.5, ry + 0.5, rw - 1, rh - 1)

      if s.marks then
        mark(i, rx + 22, ry + rh / 2, 7, th.muted, 0.65)
      end

      lg.setFont(fonts.micro)
      setc(th.muted)
      lg.printf("ACTIVE", rx + 14, ry + 16, rw - 24, "right")
    else
      -- Pure flat matte colour bar (no desktop digits, no default shapes)
      setc(col)
      lg.rectangle("fill", rx, ry, rw, rh)

      if s.marks then
        mark(i, rx + 22, ry + rh / 2, 8, { 1, 1, 1 }, 0.88)
      end

      -- Selected colour gets a crisp ink outline & clean +N gain tag
      if is_sel then
        lg.setLineWidth(2.5)
        setc(th.ink)
        lg.rectangle("line", rx - 1.5, ry - 1.5, rw + 3, rh + 3)

        local g = rules.gain(st, i)
        local tag = "+" .. tostring(g)
        local tw = math.max(38, fonts.small:getWidth(tag) + 14)
        setc(THEMES.paper.ink, 0.88)
        lg.rectangle("fill", rx + rw - tw - 7, ry + 11, tw, 26)
        lg.setFont(fonts.small)
        setc(THEMES.paper.bg)
        lg.printf(tag, rx + rw - tw - 7, ry + 16, tw, "center")
      end
    end
  end

  -- Quiet minimal console legend at the bottom of the sidebar (no theme toggle here)
  lg.setLineWidth(1)
  setc(th.border, 0.55)
  lg.line(SWATCH_X, 396, SIDE_X + SIDE_W, 396)

  lg.setFont(fonts.micro)
  setc(th.muted)
  if s.scene == "play" then
    lg.print("UP/DN  PICK", SWATCH_X, 407)
    lg.print("A  FLOOD", SWATCH_X, 426)
    lg.print("Y  NEW   ·   B  MENU", SWATCH_X, 445)
  else
    lg.print("A  NEW BOARD", SWATCH_X, 412)
    lg.print("B  MENU", SWATCH_X, 432)
  end
end

local function draw_gameover()
  local s = game.state
  local st = s.st
  local th = cur_theme()
  local cx, cy = BOARD_X + BOARD_PX / 2, BOARD_Y + BOARD_PX / 2

  -- Calm matte scrim over the board
  setc(th.scrim)
  lg.rectangle("fill", BOARD_X, BOARD_Y, BOARD_PX, BOARD_PX)

  -- Clean editorial print result card
  local pw, ph = 316, 162
  local px, py = math.floor(cx - pw / 2), math.floor(cy - ph / 2)
  setc(th.bg)
  lg.rectangle("fill", px, py, pw, ph)
  lg.setLineWidth(2)
  setc(th.ink)
  lg.rectangle("line", px, py, pw, ph)

  -- Top print accent stripe (6-colour ribbon on win, vermilion bar on lose)
  if st.won then
    local sw = pw / COLORS
    for i = 1, COLORS do
      setc(PALETTE[i])
      lg.rectangle("fill", px + (i - 1) * sw, py, sw + 0.5, 6)
    end
  else
    setc(th.danger)
    lg.rectangle("fill", px, py, pw, 6)
  end

  -- Headline
  lg.setFont(fonts.banner)
  setc(st.won and th.ink or th.danger)
  lg.printf(st.won and "CLEARED" or "OUT OF MOVES", px, py + 18, pw, "center")

  -- Primary outcome readout
  local stat = s.stats[s.size]
  local primary
  if st.won then
    local spare = st.max_moves - st.moves
    primary = st.moves .. " / " .. st.max_moves .. " MOVES"
      .. (spare > 0 and ("  ·  " .. spare .. " SPARE") or "  ·  PAR")
  else
    local pct = math.floor(rules.size(st) / (st.w * st.h) * 100 + 0.5)
    primary = pct .. "% FLOODED"
  end
  lg.setFont(fonts.sub)
  setc(th.ink)
  lg.printf(primary, px, py + 68, pw, "center")

  -- Streak line
  lg.setFont(fonts.small)
  setc(th.muted)
  lg.printf("STREAK " .. stat.streak .. "   ·   BEST " .. stat.best_streak, px, py + 94, pw, "center")

  -- Clean action footer
  lg.setLineWidth(1)
  setc(th.border, 0.6)
  lg.line(px + 24, py + 122, px + pw - 24, py + 122)
  lg.setFont(fonts.micro)
  setc(th.muted)
  lg.printf(st.won and "A  NEW BOARD     ·     B  MENU" or "A  TRY AGAIN     ·     B  MENU", px, py + 132, pw, "center")
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
