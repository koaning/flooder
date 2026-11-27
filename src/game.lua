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

-- High-contrast jewel/enamel console palette (distinguishable by hue & luminance).
local PALETTE = {
  { 0.94, 0.23, 0.27 }, -- 1: crimson
  { 0.98, 0.75, 0.13 }, -- 2: solar gold
  { 0.15, 0.80, 0.45 }, -- 3: emerald
  { 0.16, 0.60, 0.98 }, -- 4: cobalt
  { 0.62, 0.36, 0.96 }, -- 5: royal violet
  { 0.96, 0.32, 0.66 }, -- 6: arcade magenta
}

-- Console hardware surface tokens.
local BG_BASE = { 0.055, 0.068, 0.108 }
local WELL_DARK = { 0.042, 0.050, 0.078 }
local CHASSIS_LO = { 0.088, 0.104, 0.152 }
local CHASSIS_FACE = { 0.130, 0.154, 0.220 }
local CHASSIS_HI = { 0.270, 0.318, 0.435 }
local TEXT_HI = { 0.95, 0.97, 1.00 }
local TEXT_DIM = { 0.56, 0.63, 0.77 }
local GOLD = { 0.98, 0.78, 0.18 }
local DANGER = { 0.98, 0.25, 0.28 }

-- Geometry (virtual 640x480 pixels).
local BOARD_X, BOARD_Y, BOARD_PX = 28, 38, 384
local PANEL_X, PANEL_W = 438, 186
local DOCK_Y = 192
local KEY_SIZE = 46
local BAR_Y = 446

local fonts = {}

game.state = {
  scene = "title",
  st = nil,
  size = 2,
  sel = 1,
  elapsed = 0,
  pop = {},
  stats = {},
  sparks = {},
  shake = 0,
  stamp = 0,
  bounce = 0,
  gauge = 0,
  flood_frac = 0,
}

local function rng(n)
  return love.math.random(n)
end

---------------------------------------------------------------------------
-- Stats

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

-- Colour pad keys sit in a 3 x 2 grid inside the right-hand switch bay.
function game.orb_center(i)
  local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
  return PANEL_X + 35 + col * 58, DOCK_Y + 66 + row * 62
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
  s.sparks = {}
  s.shake, s.stamp, s.bounce = 0, 0, 0
  s.gauge = 1
  s.flood_frac = rules.size(st) / (st.w * st.h)
  -- Deal animation: tiles snap in diagonally from the top-left origin.
  s.pop = {}
  for y = 1, n do
    for x = 1, n do
      s.pop[(y - 1) * n + x] = s.elapsed + (x + y) * 0.015
    end
  end
end

local function burst_sparks()
  local s = game.state
  for i = 1, 88 do
    local a = love.math.random() * math.pi * 2
    local v = 55 + love.math.random() * 210
    s.sparks[#s.sparks + 1] = {
      x = BOARD_X + BOARD_PX / 2 + (love.math.random() - 0.5) * 140,
      y = BOARD_Y + BOARD_PX / 2 + (love.math.random() - 0.5) * 90,
      vx = math.cos(a) * v,
      vy = math.sin(a) * v - 65,
      r = love.math.random() * 6,
      vr = (love.math.random() - 0.5) * 9,
      sz = 5 + love.math.random() * 6,
      star = (i % 3 == 0),
      c = love.math.random(COLORS),
      life = 1.8 + love.math.random() * 1.1,
    }
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
    burst_sparks()
  else
    stat.streak = 0
    s.shake = 0.42
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
    s.pop[(p.y - 1) * s.st.w + p.x] = s.elapsed + p.d * 0.032
  end
  if #gained >= 8 then s.bounce = s.elapsed end
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
    if a == "left" then
      s.sel = (s.sel - 2) % COLORS + 1
    elseif a == "right" then
      s.sel = s.sel % COLORS + 1
    elseif a == "up" or a == "down" then
      s.sel = (s.sel + 2) % COLORS + 1
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
  love.graphics.setBackgroundColor(WELL_DARK[1], WELL_DARK[2], WELL_DARK[3])
  local bold = "assets/fonts/ChakraPetch-Bold.ttf"
  local semi = "assets/fonts/ChakraPetch-SemiBold.ttf"
  fonts.logo = love.graphics.newFont(bold, 66)
  fonts.huge = love.graphics.newFont(bold, 52)
  fonts.banner = love.graphics.newFont(bold, 44)
  fonts.big = love.graphics.newFont(bold, 26)
  fonts.hud = love.graphics.newFont(bold, 20)
  fonts.body = love.graphics.newFont(semi, 15)
  fonts.small = love.graphics.newFont(bold, 13)
  fonts.micro = love.graphics.newFont(bold, 11)
  game.state.scene = "title"
  game.state.st = nil
  game.state.elapsed = 0
  game.state.pop = {}
  game.state.sparks = {}
  game.state.stats = load_stats()
end

function game.update(dt)
  local s = game.state
  s.elapsed = s.elapsed + dt
  if s.shake > 0 then s.shake = math.max(0, s.shake - dt) end
  if s.st then
    local target = 1 - s.st.moves / s.st.max_moves
    s.gauge = s.gauge + (target - s.gauge) * math.min(1, dt * 12)
    local ftarget = rules.size(s.st) / (s.st.w * s.st.h)
    s.flood_frac = s.flood_frac + (ftarget - s.flood_frac) * math.min(1, dt * 10)
  end
  for i = #s.sparks, 1, -1 do
    local p = s.sparks[i]
    p.vy = p.vy + 220 * dt
    p.vx = p.vx * (1 - dt * 1.6)
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    p.r = p.r + p.vr * dt
    p.life = p.life - dt
    if p.life <= 0 or p.y > H + 20 then table.remove(s.sparks, i) end
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
  local ox, oy, c = board_origin()
  local cx, cy = math.floor((vx - ox) / c) + 1, math.floor((vy - oy) / c) + 1
  if cx >= 1 and cy >= 1 and cx <= s.st.w and cy <= s.st.h then
    action("color", s.st.grid[cy][cx])
    return
  end
  local half = KEY_SIZE / 2 + 5
  for i = 1, COLORS do
    local ox2, oy2 = game.orb_center(i)
    if math.abs(vx - ox2) <= half and math.abs(vy - oy2) <= half then
      action("color", i)
      return
    end
  end
end

---------------------------------------------------------------------------
-- Drawing primitives

local lg -- love.graphics, bound in game.draw

local function mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function setc(col, a)
  lg.setColor(col[1], col[2], col[3], a or col[4] or 1)
end

local function shade(col, k, a)
  lg.setColor(math.min(1, col[1] * k), math.min(1, col[2] * k), math.min(1, col[3] * k), a or 1)
end

-- 45-degree chamfered rectangle polygon.
local function chamfer_pts(x, y, w, h, c)
  c = math.min(c, w / 2, h / 2)
  return {
    x + c, y,
    x + w - c, y,
    x + w, y + c,
    x + w, y + h - c,
    x + w - c, y + h,
    x + c, y + h,
    x, y + h - c,
    x, y + c,
  }
end

local function chamfer_fill(x, y, w, h, c)
  lg.polygon("fill", chamfer_pts(x, y, w, h, c))
end

local function chamfer_line(x, y, w, h, c)
  lg.polygon("line", chamfer_pts(x, y, w, h, c))
end

-- Machined console chassis panel with hard drop shadow, beveled rim and top accent strip.
local function console_panel(x, y, w, h, cut, accent)
  cut = cut or 8
  -- Hard cast shadow
  lg.setColor(0, 0, 0, 0.45)
  chamfer_fill(x + 3, y + 4, w, h, cut)
  -- Outer dark frame
  setc(WELL_DARK)
  chamfer_fill(x - 1, y - 1, w + 2, h + 2, cut + 1)
  -- Main brushed slate face
  setc(CHASSIS_FACE)
  chamfer_fill(x, y, w, h, cut)
  -- Inner recessed face
  setc(CHASSIS_LO)
  chamfer_fill(x + 2, y + 2, w - 4, h - 4, math.max(2, cut - 1))
  -- Top-left metallic highlight edge
  lg.setLineWidth(1.5)
  setc(CHASSIS_HI, 0.72)
  lg.line(x + cut, y + 1, x + w - cut, y + 1)
  lg.line(x + 1, y + cut, x + cut, y + 1)
  lg.line(x + 1, y + cut, x + 1, y + h - cut)
  -- Bottom-right shadow bevel
  lg.setColor(0, 0, 0, 0.55)
  lg.line(x + cut, y + h - 1, x + w - cut, y + h - 1)
  lg.line(x + w - 1, y + cut, x + w - 1, y + h - cut)
  -- Accent bar across the top chamfer
  if accent then
    setc(accent, 0.92)
    lg.rectangle("fill", x + cut + 4, y + 1, w - (cut + 4) * 2, 3)
  end
end

-- Crisp console corner targeting brackets (used for board previews and keycap cursor).
local function corner_brackets(x, y, w, h, len, col, lw)
  lg.setLineWidth(lw or 2.5)
  setc(col)
  -- top-left
  lg.line(x, y + len, x, y, x + len, y)
  -- top-right
  lg.line(x + w - len, y, x + w, y, x + w, y + len)
  -- bottom-right
  lg.line(x + w, y + h - len, x + w, y + h, x + w - len, y + h)
  -- bottom-left
  lg.line(x + len, y + h, x, y + h, x, y + h - len)
end

-- Extruded arcade typography: crisp hard 3D block shadow + sharp face (no bubbly outline).
local function arcade_text(text, x, y, w, align, font, fill, depth, shadow_col)
  depth = depth or 3
  shadow_col = shadow_col or WELL_DARK
  lg.setFont(font)
  for d = depth, 1, -1 do
    setc(shadow_col, 0.95)
    lg.printf(text, x + d * 0.5, y + d, w, align)
  end
  setc(fill)
  lg.printf(text, x, y, w, align)
end

-- Six geometric colour-blind emblems (works at both tile scale and keycap scale).
local function glyph(i, cx, cy, r, col, alpha)
  col = col or { 1, 1, 1 }
  alpha = alpha or 0.94
  lg.setColor(col[1], col[2], col[3], alpha)
  lg.setLineWidth(math.max(1.8, r * 0.28))
  if i == 1 then
    -- Solid disc
    lg.circle("fill", cx, cy, r * 0.54)
  elseif i == 2 then
    -- Crisp 4-point diamond star
    local outer, inner = r * 0.78, r * 0.28
    local pts = {}
    for k = 0, 7 do
      local a = -math.pi / 2 + k * math.pi / 4
      local rr = (k % 2 == 0) and outer or inner
      pts[#pts + 1] = cx + math.cos(a) * rr
      pts[#pts + 1] = cy + math.sin(a) * rr
    end
    for k = 0, 3 do
      local v1, v2, v3 = k * 2, k * 2 + 1, (k * 2 + 2) % 8
      lg.polygon("fill", cx, cy, pts[v1 * 2 + 1], pts[v1 * 2 + 2], pts[v2 * 2 + 1], pts[v2 * 2 + 2])
      lg.polygon("fill", cx, cy, pts[v2 * 2 + 1], pts[v2 * 2 + 2], pts[v3 * 2 + 1], pts[v3 * 2 + 2])
    end
  elseif i == 3 then
    -- Sharp square
    local hs = r * 0.48
    lg.rectangle("fill", cx - hs, cy - hs, hs * 2, hs * 2)
  elseif i == 4 then
    -- Diamond
    lg.polygon("fill", cx, cy - r * 0.68, cx + r * 0.62, cy, cx, cy + r * 0.68, cx - r * 0.62, cy)
  elseif i == 5 then
    -- Hollow ring
    lg.circle("line", cx, cy, r * 0.48)
  else
    -- Upward triangle
    lg.polygon("fill", cx, cy - r * 0.62, cx + r * 0.64, cy + r * 0.50, cx - r * 0.64, cy + r * 0.50)
  end
end

-- 4-way faceted enamel block (rectangular or square).
local function bevel_rect(x, y, w, h, col, dim)
  if w <= 2 or h <= 2 then return end
  local base = dim and mix(col, WELL_DARK, dim) or col
  local b = math.max(2, math.floor(math.min(w, h) * 0.16))
  local top_c = mix(base, { 1, 1, 1 }, 0.34)
  local left_c = mix(base, { 1, 1, 1 }, 0.16)
  local right_c = { base[1] * 0.64, base[2] * 0.64, base[3] * 0.64 }
  local bot_c = { base[1] * 0.44, base[2] * 0.44, base[3] * 0.44 }

  -- Base fill
  setc(base)
  lg.rectangle("fill", x, y, w, h)
  -- Top bevel
  setc(top_c)
  lg.polygon("fill", x, y, x + w, y, x + w - b, y + b, x + b, y + b)
  -- Left bevel
  setc(left_c)
  lg.polygon("fill", x, y, x + b, y + b, x + b, y + h - b, x, y + h)
  -- Right bevel
  setc(right_c)
  lg.polygon("fill", x + w, y, x + w, y + h, x + w - b, y + h - b, x + w - b, y + b)
  -- Bottom bevel
  setc(bot_c)
  lg.polygon("fill", x, y + h, x + b, y + h - b, x + w - b, y + h - b, x + w, y + h)
  -- Crisp top-left corner pixel glint
  lg.setColor(1, 1, 1, dim and 0.18 or 0.45)
  lg.rectangle("fill", x + 1, y + 1, math.max(2, b), 1.5)
end

-- Sculpted 4-way faceted arcade enamel block (replaces glossy iOS candy pills).
local function bevel_tile(x, y, s, col, idx, dim, show_glyph)
  if s <= 2 then return end
  bevel_rect(x, y, s, s, col, dim)
  local b = math.max(2, math.floor(s * 0.16))
  -- Subtle etched colour-blind emblem stamped into the block face
  if show_glyph and idx and s >= 16 then
    local gr = math.max(4.5, (s - b * 2) * 0.36)
    local cx, cy = x + s / 2, y + s / 2
    glyph(idx, cx, cy + 1, gr, { 0, 0, 0 }, dim and 0.16 or 0.24)
    glyph(idx, cx, cy, gr, { 1, 1, 1 }, dim and 0.22 or 0.42)
  end
end

-- Tactile recessed arcade push-button keycap (for the 3x2 colour pad).
local function colour_keycap(i, cx, cy, size, current, selected, t)
  local col = PALETTE[i]
  local x, y = cx - size / 2, cy - size / 2
  local cut = 5

  -- Recessed switch socket
  setc(WELL_DARK)
  chamfer_fill(x - 3, y - 3, size + 6, size + 6, cut + 1)
  lg.setColor(1, 1, 1, 0.08)
  lg.line(x - 1, y + size + 3, x + size + 1, y + size + 3)

  if current then
    -- Latched / pressed down into socket
    local muted = mix(col, CHASSIS_LO, 0.62)
    setc(muted)
    chamfer_fill(x + 1, y + 2, size - 2, size - 3, cut - 1)
    lg.setColor(0, 0, 0, 0.35)
    lg.setLineWidth(1.5)
    chamfer_line(x + 1, y + 2, size - 2, size - 3, cut - 1)
    glyph(i, cx, cy + 1, size * 0.27, { 1, 1, 1 }, 0.38)
    -- Subtle latched slash
    lg.setColor(0, 0, 0, 0.45)
    lg.setLineWidth(2)
    lg.line(x + 8, y + size - 7, x + size - 8, y + 9)
  else
    local lift = selected and (-2 - math.abs(math.sin(t * 6)) * 1.5) or 0
    local ky = y + lift
    -- Keycap skirt (3D physical key travel depth)
    shade(col, 0.42)
    chamfer_fill(x, ky + 3, size, size - 2, cut)
    -- Top faceted cap
    bevel_rect(x + 1, ky, size - 2, size - 5, col, nil)
    -- Bright top edge highlight on selected key
    if selected then
      lg.setColor(1, 1, 1, 0.22)
      lg.rectangle("fill", x + 3, ky + 2, size - 6, size - 9)
    end
    -- Bold colour-blind emblem with dark engraved shadow
    glyph(i, cx, ky + (size - 4) / 2 + 1.5, size * 0.28, { 0, 0, 0 }, 0.45)
    glyph(i, cx, ky + (size - 4) / 2, size * 0.28, { 1, 1, 1 }, 0.96)
  end

  -- Tiny crisp key number inside a dark micro-tab at top-left (1..6)
  local tag_y = current and (y + 2) or (y + (selected and (-2 - math.abs(math.sin(t * 6)) * 1.5) or 0))
  setc(WELL_DARK, current and 0.65 or 0.85)
  lg.rectangle("fill", x + 1, tag_y, 12, 13)
  lg.setFont(fonts.micro)
  lg.setColor(1, 1, 1, current and 0.40 or 0.92)
  lg.printf(tostring(i), x + 1, tag_y - 1, 12, "center")

  -- Animated console lock-on brackets around selected keycap
  if selected then
    local pulse = 0.72 + 0.28 * math.sin(t * 9)
    local bcol = mix(GOLD, { 1, 1, 1 }, 0.35 * pulse)
    corner_brackets(x - 5, y - 5, size + 10, size + 10, 9, bcol, 2.5)
  end
end

-- Console hardware button prompts in the bottom footer bar.
local BUTTON_COLORS = {
  A = { 0.16, 0.80, 0.46 },
  B = { 0.94, 0.24, 0.28 },
  Y = { 0.98, 0.76, 0.14 },
}

local function prompt(btn, label, x, y)
  lg.setFont(fonts.small)
  if btn == "+" then
    -- Crisp hardware D-pad icon with metallic contrast
    setc(CHASSIS_HI, 0.45)
    lg.rectangle("fill", x - 11, y - 4.5, 22, 9)
    lg.rectangle("fill", x - 4.5, y - 11, 9, 22)
    setc(TEXT_HI, 0.88)
    lg.rectangle("fill", x - 10, y - 3.5, 20, 7)
    lg.rectangle("fill", x - 3.5, y - 10, 7, 20)
    setc(WELL_DARK)
    lg.rectangle("fill", x - 2, y - 2, 4, 4)
  else
    local col = BUTTON_COLORS[btn]
    -- Matte console face button with subtle specular rim
    setc(WELL_DARK)
    lg.circle("fill", x, y + 1, 10.5)
    shade(col, 0.52)
    lg.circle("fill", x, y + 1, 9)
    setc(col)
    lg.circle("fill", x, y - 0.5, 8.5)
    lg.setColor(1, 1, 1, 0.25)
    lg.arc("line", "open", x, y - 0.5, 7.2, math.pi * 1.15, math.pi * 1.85)
    setc(WELL_DARK)
    lg.printf(btn, x - 9, y - 8.5, 18, "center")
  end
  setc(TEXT_HI, 0.92)
  lg.print(label, x + 15, y - 8)
  return x + 15 + fonts.small:getWidth(label) + 28
end

local function prompt_bar(items, accent)
  setc(WELL_DARK, 0.96)
  lg.rectangle("fill", 0, BAR_Y, W, H - BAR_Y)
  -- Illuminated hardware divider strip tinted by current flood colour
  setc(accent or GOLD, 0.75)
  lg.rectangle("fill", 0, BAR_Y, W, 2)
  lg.setColor(1, 1, 1, 0.08)
  lg.rectangle("fill", 0, BAR_Y + 2, W, 1)

  local total = 0
  for _, it in ipairs(items) do
    total = total + 15 + fonts.small:getWidth(it[2]) + 28
  end
  local x = (W - total + 28) / 2 + 8
  for _, it in ipairs(items) do
    x = prompt(it[1], it[2], x, BAR_Y + 18)
  end
end

-- Atmospheric console backdrop: deep architectural grid + subtle live flood tint.
local function backdrop(tint, t)
  local top = mix(BG_BASE, tint, 0.14)
  local bot = mix({ 0.032, 0.038, 0.064 }, tint, 0.06)
  local bands = 24
  for i = 0, bands - 1 do
    local c = mix(top, bot, i / (bands - 1))
    setc(c)
    lg.rectangle("fill", 0, i * H / bands, W, H / bands + 1)
  end

  -- Crisp orthographic blueprint grid
  lg.setLineWidth(1)
  lg.setColor(1, 1, 1, 0.032)
  local step = 32
  for x = 0, W, step do
    lg.line(x, 0, x, H)
  end
  for y = 0, H, step do
    lg.line(0, y, W, y)
  end

  -- Subtle diagonal light sweep tinted by active flood colour
  setc(tint, 0.055)
  local sweep = (t * 26) % (W + H)
  lg.polygon("fill", sweep - 120, 0, sweep - 40, 0, sweep - 40 - H * 0.45, H, sweep - 120 - H * 0.45, H)

  -- Subtle horizontal scanline texture (ultra-light for clean handheld crispness)
  lg.setColor(0, 0, 0, 0.07)
  for y = 0, H, 4 do
    lg.rectangle("fill", 0, y, W, 1)
  end
end

-- Small geometric 3x3 Flooder mosaic emblem (pure geometric puzzle iconography).
local function flood_emblem(x, y, s, t)
  local gap = 2
  local cs = math.floor((s - gap * 2) / 3)
  local flood_col = PALETTE[(math.floor(t / 2.2) % COLORS) + 1]
  local pattern = {
    { 0, 0, 2 },
    { 0, 0, 5 },
    { 3, 6, 4 },
  }
  -- Outer dark socket
  setc(WELL_DARK)
  chamfer_fill(x - 4, y - 4, s + 8, s + 8, 5)
  setc(CHASSIS_HI, 0.6)
  lg.setLineWidth(1.5)
  chamfer_line(x - 4, y - 4, s + 8, s + 8, 5)
  for row = 1, 3 do
    for col = 1, 3 do
      local v = pattern[row][col]
      local px = x + (col - 1) * (cs + gap)
      local py = y + (row - 1) * (cs + gap)
      if v == 0 then
        -- Fused 2x2 top-left flood corner
        setc(flood_col)
        lg.rectangle("fill", px, py, cs + (col == 1 and gap or 0), cs + (row == 1 and gap or 0))
      else
        bevel_tile(px, py, cs, PALETTE[v], nil, nil, false)
      end
    end
  end
  -- Bright border on fused corner
  lg.setColor(1, 1, 1, 0.72)
  lg.setLineWidth(1.5)
  lg.rectangle("line", x + 0.5, y + 0.5, cs * 2 + gap - 1, cs * 2 + gap - 1)
end

---------------------------------------------------------------------------
-- Scenes

local function draw_title()
  local s = game.state
  local t = s.elapsed
  local accent = PALETTE[(math.floor(t / 2.4) % COLORS) + 1]
  backdrop(accent, t)

  -- Live ambient mosaic columns framing the far left & right edges symmetrically
  local ts = 28
  local edge_cols = {
    { x = 4, dim = 0.64, idx = 1 },
    { x = 34, dim = 0.80, idx = 2 },
    { x = W - 62, dim = 0.80, idx = 3 },
    { x = W - 32, dim = 0.64, idx = 4 },
  }
  for row = 0, 15 do
    for _, ec in ipairs(edge_cols) do
      local py = row * ts + 4
      local wave = math.floor((ec.idx * 2 + row + t * 1.4) % COLORS) + 1
      bevel_tile(ec.x, py, ts - 3, PALETTE[wave], nil, ec.dim, false)
    end
  end

  -- Center vignette panel backing for crisp contrast
  lg.setColor(WELL_DARK[1], WELL_DARK[2], WELL_DARK[3], 0.56)
  lg.rectangle("fill", 68, 0, W - 136, BAR_Y)

  -- Top 6-colour prismatic bar (centered cleanly above the logo)
  local sw_w = 24
  local bar_x = (W - COLORS * sw_w + 3) / 2
  for i = 1, COLORS do
    setc(PALETTE[i], 0.94)
    lg.rectangle("fill", bar_x + (i - 1) * sw_w, 26, sw_w - 3, 5)
  end

  -- Hero Logo Lockup (dynamically centered inside x=80..560 for cartridge cover!)
  local word = "FLOODER"
  local word_w = fonts.logo:getWidth(word)
  local emb_s, emb_gap = 48, 18
  local lock_w = emb_s + emb_gap + word_w
  local lock_x = math.floor((W - lock_w) / 2)
  local word_x = lock_x + emb_s + emb_gap

  flood_emblem(lock_x, 56, emb_s, t)
  -- Vibrant coloured secondary extrusion edge behind the crisp white wordmark
  lg.setFont(fonts.logo)
  setc(WELL_DARK, 0.95)
  lg.print(word, word_x + 4, 48)
  setc(accent, 0.85)
  lg.print(word, word_x + 2, 45)
  setc(TEXT_HI)
  lg.print(word, word_x, 42)
  -- Crisp horizontal flood accent bar matching the exact wordmark width
  setc(accent, 0.95)
  lg.rectangle("fill", word_x, 114, word_w, 3)

  -- Engraved subtitle bar
  lg.setFont(fonts.small)
  setc(TEXT_DIM)
  lg.printf("REPAINT THE BOARD  //  BEAT THE MOVE LIMIT", 80, 127, W - 160, "center")

  -- Stage / Board Size Selector (all 3 cartridges sit inside x=96..544 -> cartridge safe!)
  local cw, ch, gap = 138, 134, 17
  local x0 = (W - (cw * 3 + gap * 2)) / 2
  local y0 = 178

  for i, size in ipairs(SIZES) do
    local on = i == s.size
    local cx = x0 + (i - 1) * (cw + gap)
    local cy = y0 + (on and -6 or 4)
    console_panel(cx, cy, cw, ch, 8, on and GOLD or CHASSIS_HI)

    -- Proportional mini-board preview inside recessed dark socket
    local m = i + 2 -- 3x3, 4x4, 5x5
    local box = 60
    local cell = math.floor(box / m)
    local gw = cell * m
    local gx = math.floor(cx + (cw - gw) / 2)
    local gy = cy + 16
    setc(WELL_DARK)
    lg.rectangle("fill", gx - 3, gy - 3, gw + 6, gw + 6)
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
          bevel_tile(tx + 0.5, ty + 0.5, cell - 1, PALETTE[ci], nil, on and nil or 0.40, false)
        end
      end
    end
    -- Mini flooded border highlight
    lg.setColor(1, 1, 1, on and 0.65 or 0.30)
    lg.setLineWidth(1)
    lg.rectangle("line", gx - 3, gy - 3, gw + 6, gw + 6)

    -- Mode title & dimensions
    lg.setFont(fonts.hud)
    setc(on and TEXT_HI or TEXT_DIM)
    lg.printf(size.name, cx, cy + 84, cw, "center")

    lg.setFont(fonts.small)
    setc(on and GOLD or TEXT_DIM, on and 1 or 0.72)
    lg.printf(size.n .. " x " .. size.n, cx, cy + 109, cw, "center")

    -- Selected console targeting frame + chevron cursor
    if on then
      local pulse = 0.75 + 0.25 * math.sin(t * 7)
      corner_brackets(cx - 5, cy - 5, cw + 10, ch + 10, 12, mix(GOLD, TEXT_HI, 0.25 * pulse), 2.5)
      local ay = cy - 17 + math.sin(t * 7) * 2
      setc(GOLD)
      lg.polygon("fill", cx + cw / 2 - 7, ay, cx + cw / 2 + 7, ay, cx + cw / 2, ay + 8)
    end
  end

  -- Recessed Arcade Record Strip
  local stat = s.stats[s.size]
  local rx, ry, rw, rh = 116, 336, W - 232, 30
  setc(WELL_DARK, 0.92)
  chamfer_fill(rx, ry, rw, rh, 6)
  setc(CHASSIS_HI, 0.45)
  lg.setLineWidth(1.5)
  chamfer_line(rx, ry, rw, rh, 6)

  lg.setFont(fonts.small)
  if stat.played > 0 then
    local rec = "WINS " .. stat.won .. "/" .. stat.played
      .. "    //    STREAK " .. stat.streak
      .. "    //    BEST " .. stat.best_streak
    setc(TEXT_HI, 0.90)
    lg.printf(rec, rx, ry + 7, rw, "center")
  else
    setc(TEXT_DIM)
    lg.printf("CLEAR THE BOARD WITHIN THE PAR MOVE LIMIT", rx, ry + 7, rw, "center")
  end

  -- Classic Console Start Cue (clean pulsing glow, never fully invisible)
  local glow = 0.68 + 0.32 * math.sin(t * 5)
  local sc = mix(GOLD, TEXT_HI, 0.25 * glow)
  arcade_text("PRESS START", 0, 388, W, "center", fonts.big, sc, 3, WELL_DARK)
  -- Flanking console chevrons
  local chev = 104 + math.sin(t * 5) * 4
  setc(GOLD, glow)
  lg.polygon("fill", W / 2 - chev - 10, 396, W / 2 - chev - 10, 412, W / 2 - chev, 404)
  lg.polygon("fill", W / 2 + chev + 10, 396, W / 2 + chev + 10, 412, W / 2 + chev, 404)

  prompt_bar({ { "+", "SIZE" }, { "A", "PLAY" } }, accent)
end

local function draw_board(shx)
  local s = game.state
  local st = s.st
  local ox, oy, c = board_origin()
  local n = st.w
  local t = s.elapsed
  local cur_col = PALETTE[st.grid[1][1]]
  ox = ox + shx

  -- Outer machined playfield bezel
  local bx, by, bw, bh = BOARD_X - 10 + shx, 14, BOARD_PX + 20, BOARD_PX + 34
  console_panel(bx, by, bw, bh, 10, cur_col)

  -- Integrated bezel header strip (stage spec + live flood percentage)
  local sz_info = SIZES[s.size]
  setc(cur_col)
  lg.rectangle("fill", bx + 14, by + 10, 8, 8)
  lg.setFont(fonts.micro)
  setc(TEXT_HI, 0.90)
  lg.print(sz_info.name .. "  //  " .. sz_info.n .. "x" .. sz_info.n, bx + 28, by + 7)
  local pct = math.floor(rules.size(st) / (st.w * st.h) * 100 + 0.5)
  setc(TEXT_DIM)
  lg.printf("FLOOD  " .. pct .. "%", bx + 14, by + 7, bw - 28, "right")

  -- Recessed pitch-dark tile chamber
  setc(WELL_DARK)
  lg.rectangle("fill", BOARD_X - 3 + shx, BOARD_Y - 3, BOARD_PX + 6, BOARD_PX + 6)
  lg.setColor(0, 0, 0, 0.75)
  lg.setLineWidth(2)
  lg.rectangle("line", BOARD_X - 3 + shx, BOARD_Y - 3, BOARD_PX + 6, BOARD_PX + 6)

  -- Metallic corner accents on playfield bezel
  corner_brackets(bx - 1, by - 1, bw + 2, bh + 2, 12, mix(CHASSIS_HI, cur_col, 0.35), 2)

  local region = rules.region(st)
  local preview = {}
  if s.scene == "play" then
    for _, p in ipairs(rules.preview(st, s.sel)) do
      preview[(p.y - 1) * n + p.x] = true
    end
  end

  local lose = s.scene == "gameover" and not st.won

  -- First pass: draw tiles and seamless fused owned territory
  for y = 1, st.h do
    for x = 1, n do
      local k = (y - 1) * n + x
      local ci = st.grid[y][x]
      local col = PALETTE[ci]
      local inset = 0.5
      local t0 = s.pop[k]
      if t0 then
        local dt = t - t0
        if dt < 0 then
          inset = c * 0.5
        elseif dt < 0.20 then
          local p = dt / 0.20
          inset = c * 0.5 * (1 - p) - c * 0.12 * math.sin(p * math.pi) + 0.5
        end
      end
      local px, py = ox + (x - 1) * c, oy + (y - 1) * c
      if inset < c * 0.5 then
        if region[k] then
          -- Seamless fused territory with subtle travelling diagonal sheen
          local wave = 0.16 * math.max(0, math.sin(t * 2.4 - (x + y) * 0.32)) ^ 5
          local fill = lose and mix(col, WELL_DARK, 0.45) or mix(col, { 1, 1, 1 }, wave)
          setc(fill)
          local pad = math.max(0, inset - 0.5)
          lg.rectangle("fill", px + pad, py + pad, c - pad * 2, c - pad * 2)
          -- Subtle inner technical dot to preserve grid cadence
          lg.setColor(1, 1, 1, lose and 0.05 or 0.12)
          lg.rectangle("fill", px + c / 2 - 1, py + c / 2 - 1, 2, 2)
        else
          local dim = lose and 0.58 or nil
          bevel_tile(px + inset, py + inset, c - inset * 2, col, ci, dim, true)
        end
      end
    end
  end

  -- Second pass: crisp luminous contour around the outer frontier of the owned territory
  lg.setLineWidth(2)
  local rim_col = lose and mix(cur_col, TEXT_DIM, 0.5) or mix(cur_col, { 1, 1, 1 }, 0.72)
  setc(rim_col, lose and 0.55 or 0.92)
  for y = 1, st.h do
    for x = 1, n do
      local k = (y - 1) * n + x
      if region[k] then
        local px, py = ox + (x - 1) * c, oy + (y - 1) * c
        if y == 1 or not region[k - n] then
          lg.line(px, py + 1, px + c, py + 1)
        end
        if y == st.h or not region[k + n] then
          lg.line(px, py + c - 1, px + c, py + c - 1)
        end
        if x == 1 or not region[k - 1] then
          lg.line(px + 1, py, px + 1, py + c)
        end
        if x == n or not region[k + 1] then
          lg.line(px + c - 1, py, px + c - 1, py + c)
        end
      end
    end
  end

  -- Origin anchor beacon at top-left cell (1,1) so player sees where floods start
  if region[1] then
    local ac = math.max(5, math.floor(c * 0.28))
    lg.setColor(1, 1, 1, lose and 0.28 or 0.85)
    lg.setLineWidth(2)
    lg.line(ox + 4, oy + 4 + ac, ox + 4, oy + 4, ox + 4 + ac, oy + 4)
    lg.rectangle("fill", ox + 7, oy + 7, 3, 3)
  end

  -- Third pass: high-contrast animated console lock-on brackets on previewed frontier cells
  if s.scene == "play" then
    local pulse = 0.78 + 0.22 * math.sin(t * 9)
    local blen = math.max(5, math.floor(c * 0.30))
    for y = 1, st.h do
      for x = 1, n do
        local k = (y - 1) * n + x
        if preview[k] then
          local px, py = ox + (x - 1) * c, oy + (y - 1) * c
          lg.setColor(1, 1, 1, 0.22 * pulse)
          lg.rectangle("fill", px + 2, py + 2, c - 4, c - 4)
          -- Dark contrast backing behind bright targeting brackets
          corner_brackets(px + 2, py + 2, c - 4, c - 4, blen, { 0, 0, 0, 0.78 }, 4)
          corner_brackets(px + 2, py + 2, c - 4, c - 4, blen, { 1, 1, 1, pulse }, 2)
        end
      end
    end
  end
end

local function draw_panel()
  local s = game.state
  local st = s.st
  local t = s.elapsed
  local x, w = PANEL_X, PANEL_W
  local left = st.max_moves - st.moves
  local cur_idx = st.grid[1][1]
  local cur = PALETTE[cur_idx]
  local danger = left <= 3 and not st.won

  -------------------------------------------------------------------------
  -- Top Module: MOVES TELEMETRY & SEGMENTED LED METER
  local my, mh = 14, 168
  console_panel(x, my, w, mh, 9, danger and DANGER or cur)

  -- Module header + live status LED
  lg.setFont(fonts.micro)
  setc(TEXT_DIM)
  lg.print("MOVES REMAINING", x + 14, my + 12)
  local led_col = st.won and GOLD or (danger and DANGER or { 0.18, 0.86, 0.48 })
  local led_a = danger and (0.45 + 0.55 * math.abs(math.sin(t * 8))) or 0.95
  setc(led_col, led_a)
  lg.rectangle("fill", x + w - 22, my + 14, 8, 8)

  -- Recessed digital counter bay
  local bx, by, bw, bh = x + 12, my + 32, w - 24, 68
  setc(WELL_DARK)
  chamfer_fill(bx, by, bw, bh, 6)
  setc(CHASSIS_HI, 0.25)
  lg.setLineWidth(1)
  chamfer_line(bx, by, bw, bh, 6)

  -- Big crisp moves readout balanced cleanly beside LIMIT /max
  local pulse = danger and (1 + 0.08 * math.abs(math.sin(t * 7))) or 1
  lg.push()
  lg.translate(bx + bw * 0.36, by + bh / 2)
  lg.scale(pulse)
  arcade_text(tostring(left), -52, -31, 104, "center", fonts.huge, danger and DANGER or TEXT_HI, 3, { 0, 0, 0 })
  lg.pop()

  -- Vertical subtle divider inside the counter bay
  setc(CHASSIS_HI, 0.22)
  lg.rectangle("fill", bx + bw * 0.63, by + 13, 1, bh - 26)

  lg.setFont(fonts.micro)
  setc(TEXT_DIM, 0.72)
  lg.printf("LIMIT", bx + bw * 0.65, by + 15, bw * 0.33, "center")
  lg.setFont(fonts.hud)
  setc(TEXT_DIM, 0.95)
  lg.printf("/" .. st.max_moves, bx + bw * 0.65, by + 30, bw * 0.33, "center")

  -- Segmented Arcade LED Meter (14 discrete pips coloured by safety state)
  local segs = 14
  local sx0, sy0, sw = x + 14, my + 110, w - 28
  local gap = 3
  local seg_w = (sw - gap * (segs - 1)) / segs
  local lit = math.floor(s.gauge * segs + 0.5)
  local bar_col
  if danger then
    bar_col = DANGER
  elseif s.gauge <= 0.38 then
    bar_col = GOLD
  else
    bar_col = { 0.16, 0.84, 0.50 }
  end
  for i = 1, segs do
    local sx = sx0 + (i - 1) * (seg_w + gap)
    if i <= lit then
      setc(bar_col, 0.95)
      lg.rectangle("fill", sx, sy0, seg_w, 12)
      lg.setColor(1, 1, 1, 0.35)
      lg.rectangle("fill", sx, sy0, seg_w, 3)
    else
      setc(WELL_DARK)
      lg.rectangle("fill", sx, sy0, seg_w, 12)
    end
  end

  -- Territory progress telemetry bar
  local owned = rules.size(st)
  local total = st.w * st.h
  local pct = math.floor(owned / total * 100 + 0.5)
  lg.setFont(fonts.micro)
  setc(TEXT_DIM)
  lg.print("TERRITORY", x + 14, my + 132)
  setc(TEXT_HI, 0.92)
  lg.printf(owned .. "/" .. total .. " (" .. pct .. "%)", x + 14, my + 132, w - 28, "right")

  local bar_x, bar_y, bar_w, bar_h = x + 14, my + 150, w - 28, 7
  setc(WELL_DARK)
  lg.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
  local fw = math.max(2, math.floor(bar_w * s.flood_frac))
  setc(cur, 0.95)
  lg.rectangle("fill", bar_x, bar_y, fw, bar_h)
  lg.setColor(1, 1, 1, 0.32)
  lg.rectangle("fill", bar_x, bar_y, fw, 2)

  -------------------------------------------------------------------------
  -- Bottom Module: COLOUR PAD (3x2 Tactile Arcade Keycaps)
  console_panel(x, DOCK_Y, w, 240, 9, CHASSIS_HI)
  lg.setFont(fonts.micro)
  setc(TEXT_DIM)
  lg.print("COLOUR PAD", x + 14, DOCK_Y + 12)
  setc(TEXT_DIM, 0.65)
  lg.printf("KEYS 1-6", x + 14, DOCK_Y + 12, w - 28, "right")

  -- Subtle header divider
  setc(CHASSIS_HI, 0.25)
  lg.rectangle("fill", x + 12, DOCK_Y + 29, w - 24, 1)

  for i = 1, COLORS do
    local cx, cy = game.orb_center(i)
    local selected = i == s.sel and s.scene == "play"
    colour_keycap(i, cx, cy, KEY_SIZE, i == cur_idx, selected, t)
  end

  -- Bottom LCD gain readout bay
  local rx, ry, rw, rh = x + 12, DOCK_Y + 196, w - 24, 32
  setc(WELL_DARK)
  chamfer_fill(rx, ry, rw, rh, 5)
  setc(CHASSIS_HI, 0.3)
  lg.setLineWidth(1)
  chamfer_line(rx, ry, rw, rh, 5)

  if s.scene == "play" then
    local g = rules.gain(st, s.sel)
    local is_cur = s.sel == cur_idx
    lg.setFont(fonts.small)
    if is_cur then
      setc(TEXT_DIM, 0.8)
      lg.printf("ACTIVE COLOUR", rx, ry + 8, rw, "center")
    else
      -- Swatch pip + bold gain figure
      setc(PALETTE[s.sel])
      lg.rectangle("fill", rx + 12, ry + 9, 14, 14)
      lg.setColor(1, 1, 1, 0.35)
      lg.rectangle("fill", rx + 12, ry + 9, 14, 3)
      setc(TEXT_HI)
      lg.printf("GAIN   +" .. g .. " TILES", rx + 26, ry + 8, rw - 32, "center")
    end
  else
    lg.setFont(fonts.small)
    setc(st.won and GOLD or DANGER)
    lg.printf(st.won and "BOARD COMPLETE" or "NO MOVES LEFT", rx, ry + 8, rw, "center")
  end
end

-- Diagonal hazard stripes helper for the lose banner trim.
local function hazard_strip(x, y, w, h, col)
  setc(WELL_DARK)
  lg.rectangle("fill", x, y, w, h)
  setc(col, 0.85)
  local step = 14
  for sx = -h, w + step, step do
    local x1 = math.max(x, x + sx)
    local x2 = math.min(x + w, x + sx + 7)
    local x3 = math.min(x + w, x + sx + 7 - h)
    local x4 = math.max(x, x + sx - h)
    if x2 > x1 or x3 > x4 then
      lg.polygon("fill", x1, y, x2, y, x3, y + h, x4, y + h)
    end
  end
end

local function draw_gameover()
  local s = game.state
  local st = s.st
  local t = s.elapsed - s.stamp
  local cx, cy = BOARD_X + BOARD_PX / 2, BOARD_Y + BOARD_PX / 2

  -- Visor dim over the board
  local dim_a = math.min(0.62, t * 2.2)
  if st.won then
    lg.setColor(0.03, 0.05, 0.10, dim_a * 0.82)
  else
    lg.setColor(0.08, 0.02, 0.04, dim_a)
  end
  lg.rectangle("fill", BOARD_X, BOARD_Y, BOARD_PX, BOARD_PX)

  -- Geometric arcade sparks on victory
  for _, p in ipairs(s.sparks) do
    local a = math.min(1, p.life / 0.7)
    lg.push()
    lg.translate(p.x, p.y)
    lg.rotate(p.r)
    local hs = p.sz * 0.6
    if p.star then
      glyph(2, 0, 0, hs * 1.6, PALETTE[p.c], a)
      lg.setColor(1, 1, 1, a * 0.75)
      lg.rectangle("fill", -1.5, -1.5, 3, 3)
    else
      setc(PALETTE[p.c], a)
      lg.polygon("fill", 0, -hs * 1.35, hs, 0, 0, hs * 1.35, -hs, 0)
      lg.setColor(1, 1, 1, a * 0.65)
      lg.rectangle("fill", -1.5, -1.5, 3, 3)
    end
    lg.pop()
  end

  -- Slam-in console results banner
  local p = math.min(1, t / 0.22)
  local ease = 1 - (1 - p) ^ 3
  local bw, bh = BOARD_PX - 16, 174
  local bx, by = cx - bw / 2, cy - bh / 2

  lg.push()
  lg.translate(cx, cy)
  lg.scale(1, 0.15 + 0.85 * ease)
  lg.translate(-cx, -cy)

  local accent = st.won and GOLD or DANGER
  console_panel(bx, by, bw, bh, 10, nil)

  if st.won then
    setc(GOLD)
    lg.rectangle("fill", bx + 12, by + 2, bw - 24, 4)
    lg.rectangle("fill", bx + 12, by + bh - 6, bw - 24, 4)
  else
    hazard_strip(bx + 12, by + 3, bw - 24, 7, DANGER)
    hazard_strip(bx + 12, by + bh - 10, bw - 24, 7, DANGER)
  end

  -- Micro status header
  lg.setFont(fonts.micro)
  setc(accent, 0.95)
  lg.printf(st.won and "BOARD 100% FLOODED" or "MOVE LIMIT REACHED", bx, by + 16, bw, "center")

  -- Main arcade headline
  local headline = st.won and "STAGE CLEAR" or "OUT OF MOVES"
  arcade_text(headline, bx, by + 32, bw, "center", fonts.banner, st.won and GOLD or DANGER, 4, WELL_DARK)

  -- Recessed telemetry results block
  if t > 0.18 then
    local stat = s.stats[s.size]
    local rx, ry, rw, rh = bx + 18, by + 94, bw - 36, 58
    setc(WELL_DARK)
    chamfer_fill(rx, ry, rw, rh, 6)
    setc(accent, 0.45)
    lg.setLineWidth(1.5)
    chamfer_line(rx, ry, rw, rh, 6)

    local primary
    if st.won then
      local spare = st.max_moves - st.moves
      primary = st.moves .. " MOVES  //  " .. (spare > 0 and (spare .. " SPARE") or "PAR CLEAR!")
    else
      primary = math.floor(rules.size(st) / (st.w * st.h) * 100 + 0.5) .. "% FLOODED"
    end
    lg.setFont(fonts.hud)
    setc(TEXT_HI)
    lg.printf(primary, rx, ry + 7, rw, "center")

    lg.setFont(fonts.small)
    setc(TEXT_DIM)
    lg.printf("STREAK " .. stat.streak .. "    //    BEST " .. stat.best_streak, rx, ry + 34, rw, "center")
  end

  lg.pop()
end

function game.draw()
  lg = love.graphics
  local sw, sh = lg.getDimensions()
  local scale = math.min(sw / W, sh / H)
  lg.push()
  lg.translate(math.floor((sw - W * scale) / 2), math.floor((sh - H * scale) / 2))
  lg.scale(scale)

  local s = game.state
  if s.scene == "title" then
    draw_title()
  else
    local cur = PALETTE[s.st.grid[1][1]]
    backdrop(cur, s.elapsed)
    local shx = s.shake > 0 and math.sin(s.elapsed * 60) * 7 * (s.shake / 0.42) or 0
    draw_board(shx)
    draw_panel()
    if s.scene == "gameover" then
      draw_gameover()
      prompt_bar({ { "A", "NEW BOARD" }, { "B", "MENU" } }, s.st.won and GOLD or DANGER)
    else
      prompt_bar({ { "+", "CHOOSE" }, { "A", "FLOOD" }, { "Y", "NEW" }, { "B", "MENU" } }, cur)
    end
  end

  lg.pop()
end

return game
