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

-- Saturated "candy" palette.
local PALETTE = {
  { 1.00, 0.33, 0.38 }, -- red
  { 1.00, 0.80, 0.22 }, -- yellow
  { 0.36, 0.86, 0.38 }, -- green
  { 0.24, 0.62, 1.00 }, -- blue
  { 0.64, 0.42, 1.00 }, -- purple
  { 1.00, 0.52, 0.80 }, -- pink
}

local INK = { 0.12, 0.08, 0.24 }   -- outlines and dark text
local CREAM = { 1.00, 0.98, 0.94 } -- cards and frames

-- Geometry (virtual pixels).
local BOARD_X, BOARD_Y, BOARD_PX = 28, 28, 384
local PANEL_X, PANEL_W = 440, 180
local DOCK_Y = 214
local ORB_R = 23
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
  confetti = {},
  shake = 0,
  stamp = 0,
  bounce = 0,
  gauge = 0,
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

-- Orbs sit in a 3 x 2 grid inside the dock.
function game.orb_center(i)
  local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
  return PANEL_X + 34 + col * 56, DOCK_Y + 62 + row * 66
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
  s.confetti = {}
  s.shake, s.stamp, s.bounce = 0, 0, 0
  s.gauge = 1
  -- Deal animation: tiles pop in diagonally from the corner.
  s.pop = {}
  for y = 1, n do
    for x = 1, n do
      s.pop[(y - 1) * n + x] = s.elapsed + (x + y) * 0.018
    end
  end
end

local function burst_confetti()
  local s = game.state
  for _ = 1, 90 do
    local a = love.math.random() * math.pi - math.pi
    local v = 160 + love.math.random() * 260
    s.confetti[#s.confetti + 1] = {
      x = BOARD_X + BOARD_PX / 2, y = BOARD_Y + BOARD_PX / 2,
      vx = math.cos(a) * v, vy = math.sin(a) * v - 120,
      r = love.math.random() * 6, vr = (love.math.random() - 0.5) * 14,
      c = love.math.random(COLORS), life = 2.4,
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
    burst_confetti()
  else
    stat.streak = 0
    s.shake = 0.45
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
    s.pop[(p.y - 1) * s.st.w + p.x] = s.elapsed + p.d * 0.035
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
  love.graphics.setBackgroundColor(INK[1], INK[2], INK[3])
  local bold, medium = "assets/fonts/Fredoka-Bold.ttf", "assets/fonts/Fredoka-Medium.ttf"
  fonts.logo = love.graphics.newFont(bold, 76)
  fonts.huge = love.graphics.newFont(bold, 54)
  fonts.big = love.graphics.newFont(bold, 34)
  fonts.hud = love.graphics.newFont(bold, 22)
  fonts.body = love.graphics.newFont(medium, 17)
  fonts.small = love.graphics.newFont(bold, 13)
  game.state.scene = "title"
  game.state.st = nil
  game.state.elapsed = 0
  game.state.pop = {}
  game.state.confetti = {}
  game.state.stats = load_stats()
end

function game.update(dt)
  local s = game.state
  s.elapsed = s.elapsed + dt
  if s.shake > 0 then s.shake = math.max(0, s.shake - dt) end
  if s.st then
    local target = 1 - s.st.moves / s.st.max_moves
    s.gauge = s.gauge + (target - s.gauge) * math.min(1, dt * 10)
  end
  for i = #s.confetti, 1, -1 do
    local p = s.confetti[i]
    p.vy = p.vy + 520 * dt
    p.vx = p.vx * (1 - dt * 0.8)
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    p.r = p.r + p.vr * dt
    p.life = p.life - dt
    if p.life <= 0 or p.y > H + 20 then table.remove(s.confetti, i) end
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
  for i = 1, COLORS do
    local ox2, oy2 = game.orb_center(i)
    if (vx - ox2) ^ 2 + (vy - oy2) ^ 2 <= (ORB_R + 6) ^ 2 then
      action("color", i)
      return
    end
  end
end

---------------------------------------------------------------------------
-- Drawing primitives

local lg -- love.graphics, bound in game.draw

local function shade(col, k, a)
  lg.setColor(math.min(1, col[1] * k), math.min(1, col[2] * k), math.min(1, col[3] * k), a or 1)
end

local function mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Chunky text with a thick ink outline and a drop shadow.
local function outlined(text, x, y, w, align, font, fill, thick)
  thick = thick or 3
  lg.setFont(font)
  lg.setColor(INK[1], INK[2], INK[3], 0.55)
  lg.printf(text, x, y + thick + 2, w, align)
  lg.setColor(INK[1], INK[2], INK[3])
  for dx = -thick, thick, thick do
    for dy = -thick, thick, thick do
      if dx ~= 0 or dy ~= 0 then lg.printf(text, x + dx, y + dy, w, align) end
    end
  end
  lg.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
  lg.printf(text, x, y, w, align)
end

-- A raised card: drop shadow, ink rim, cream face.
local function card(x, y, w, h, r, face)
  face = face or CREAM
  lg.setColor(0, 0, 0, 0.28)
  lg.rectangle("fill", x + 4, y + 7, w, h, r, r)
  lg.setColor(INK[1], INK[2], INK[3])
  lg.rectangle("fill", x - 3, y - 3, w + 6, h + 6, r + 3, r + 3)
  lg.setColor(face[1], face[2], face[3])
  lg.rectangle("fill", x, y, w, h, r, r)
end

-- Glossy candy tile.
local function candy(x, y, s, col, glow)
  local r = math.max(3, s * 0.22)
  local k = 1 + (glow or 0)
  shade(col, 0.62 * k)
  lg.rectangle("fill", x, y, s, s, r, r)
  shade(col, k)
  lg.rectangle("fill", x, y, s, s - math.max(2, s * 0.12), r, r)
  lg.setColor(1, 1, 1, 0.38)
  lg.rectangle("fill", x + s * 0.16, y + s * 0.12, s * 0.38, s * 0.16, s * 0.08, s * 0.08)
end

-- White shape that identifies each colour without relying on hue.
local function glyph(i, cx, cy, r)
  lg.setColor(1, 1, 1, 0.92)
  lg.setLineWidth(math.max(2, r * 0.28))
  if i == 1 then
    lg.circle("fill", cx, cy, r * 0.5)
  elseif i == 2 then
    -- star
    local pts = {}
    for k = 0, 9 do
      local a = -math.pi / 2 + k * math.pi / 5
      local rr = k % 2 == 0 and r * 0.72 or r * 0.32
      pts[#pts + 1] = cx + math.cos(a) * rr
      pts[#pts + 1] = cy + math.sin(a) * rr
    end
    for k = 0, 4 do
      local a1, a2, a3 = k * 2, k * 2 + 1, (k * 2 + 2) % 10
      lg.polygon("fill", cx, cy, pts[a1 * 2 + 1], pts[a1 * 2 + 2], pts[a2 * 2 + 1], pts[a2 * 2 + 2])
      lg.polygon("fill", cx, cy, pts[a2 * 2 + 1], pts[a2 * 2 + 2], pts[a3 * 2 + 1], pts[a3 * 2 + 2])
    end
  elseif i == 3 then
    lg.rectangle("fill", cx - r * 0.45, cy - r * 0.45, r * 0.9, r * 0.9, r * 0.15, r * 0.15)
  elseif i == 4 then
    lg.polygon("fill", cx, cy - r * 0.68, cx + r * 0.6, cy, cx, cy + r * 0.68, cx - r * 0.6, cy)
  elseif i == 5 then
    lg.circle("line", cx, cy, r * 0.45)
  else
    lg.polygon("fill", cx, cy - r * 0.6, cx + r * 0.62, cy + r * 0.48, cx - r * 0.62, cy + r * 0.48)
  end
end

-- Glossy orb (palette button).
local function orb(i, cx, cy, r, dim)
  local col = PALETTE[i]
  local k = 1
  if dim then col = mix(col, { 0.85, 0.83, 0.90 }, 0.6) end
  lg.setColor(0, 0, 0, 0.22)
  lg.ellipse("fill", cx, cy + r * 0.92, r * 0.9, r * 0.28)
  lg.setColor(INK[1], INK[2], INK[3])
  lg.circle("fill", cx, cy, r + 3)
  shade(col, 0.62 * k)
  lg.circle("fill", cx, cy, r)
  shade(col, k)
  lg.circle("fill", cx, cy - r * 0.1, r * 0.9)
  lg.setColor(1, 1, 1, dim and 0.15 or 0.45)
  lg.ellipse("fill", cx - r * 0.3, cy - r * 0.45, r * 0.38, r * 0.2)
  glyph(i, cx, cy + 1, r * 0.62)
  if dim then
    lg.setColor(INK[1], INK[2], INK[3], 0.55)
    lg.setLineWidth(3)
    lg.line(cx - r * 0.7, cy + r * 0.7, cx + r * 0.7, cy - r * 0.7)
  end
end

-- Console-style button prompt: round button with a letter, then a label.
local BUTTON_COLORS = {
  A = { 0.36, 0.86, 0.38 },
  B = { 1.00, 0.33, 0.38 },
  Y = { 1.00, 0.80, 0.22 },
}
local function prompt(btn, label, x, y)
  lg.setFont(fonts.small)
  if btn == "+" then
    -- D-pad
    lg.setColor(INK[1], INK[2], INK[3])
    lg.rectangle("fill", x - 11, y - 4, 22, 8, 2, 2)
    lg.rectangle("fill", x - 4, y - 11, 8, 22, 2, 2)
    lg.setColor(CREAM[1], CREAM[2], CREAM[3])
    lg.rectangle("fill", x - 9, y - 2, 18, 4, 1, 1)
    lg.rectangle("fill", x - 2, y - 9, 4, 18, 1, 1)
  else
    local col = BUTTON_COLORS[btn]
    lg.setColor(INK[1], INK[2], INK[3])
    lg.circle("fill", x, y + 1, 12)
    shade(col, 1)
    lg.circle("fill", x, y, 10)
    lg.setColor(INK[1], INK[2], INK[3])
    lg.printf(btn, x - 10, y - 8, 20, "center")
  end
  lg.setColor(CREAM[1], CREAM[2], CREAM[3])
  lg.print(label, x + 17, y - 8)
  return x + 17 + fonts.small:getWidth(label) + 26
end

local function prompt_bar(items)
  lg.setColor(INK[1], INK[2], INK[3], 0.82)
  lg.rectangle("fill", 0, BAR_Y, W, H - BAR_Y)
  lg.setColor(1, 1, 1, 0.12)
  lg.rectangle("fill", 0, BAR_Y, W, 2)
  local total = 0
  for _, it in ipairs(items) do total = total + 17 + fonts.small:getWidth(it[2]) + 26 end
  local x = (W - total + 26) / 2 + 6
  for _, it in ipairs(items) do x = prompt(it[1], it[2], x, BAR_Y + 17) end
end

-- Drip, the droplet mascot. Its body takes the colour of your flood.
local function drip(cx, cy, r, col, mood, t)
  local squash = 1 + 0.06 * math.sin(t * 5)
  lg.push()
  lg.translate(cx, cy)
  lg.scale(1 / squash, squash)
  lg.setColor(0, 0, 0, 0.25)
  lg.ellipse("fill", 0, r * 1.05, r * 0.8, r * 0.2)
  -- ink outline
  lg.setColor(INK[1], INK[2], INK[3])
  lg.circle("fill", 0, 0, r + 3)
  lg.polygon("fill", -r * 0.78 - 3, -r * 0.5, r * 0.78 + 3, -r * 0.5, 0, -r * 1.75 - 4)
  -- body
  shade(col, 1)
  lg.circle("fill", 0, 0, r)
  lg.polygon("fill", -r * 0.78, -r * 0.55, r * 0.78, -r * 0.55, 0, -r * 1.75)
  lg.setColor(1, 1, 1, 0.45)
  lg.ellipse("fill", -r * 0.42, -r * 0.42, r * 0.2, r * 0.32)
  -- eyes (blink every few seconds)
  local blink = (t % 3.2) < 0.12
  lg.setColor(INK[1], INK[2], INK[3])
  if blink then
    lg.rectangle("fill", -r * 0.42, -r * 0.05, r * 0.26, 3)
    lg.rectangle("fill", r * 0.16, -r * 0.05, r * 0.26, 3)
  else
    lg.ellipse("fill", -r * 0.3, 0, r * 0.13, r * 0.2)
    lg.ellipse("fill", r * 0.3, 0, r * 0.13, r * 0.2)
    lg.setColor(1, 1, 1)
    lg.circle("fill", -r * 0.26, -r * 0.07, r * 0.05)
    lg.circle("fill", r * 0.34, -r * 0.07, r * 0.05)
  end
  -- mouth
  lg.setColor(INK[1], INK[2], INK[3])
  lg.setLineWidth(3)
  if mood == "worried" then
    lg.arc("line", "open", 0, r * 0.52, r * 0.18, math.pi * 1.15, math.pi * 1.85)
    lg.setColor(0.55, 0.85, 1.0)
    lg.circle("fill", r * 0.8, -r * 0.45, r * 0.12)
    lg.polygon("fill", r * 0.68, -r * 0.47, r * 0.92, -r * 0.47, r * 0.8, -r * 0.72)
  elseif mood == "sad" then
    lg.arc("line", "open", 0, r * 0.55, r * 0.22, math.pi * 1.2, math.pi * 1.8)
  else
    lg.arc("fill", "pie", 0, r * 0.25, r * 0.26, 0, math.pi)
    lg.setColor(1.0, 0.45, 0.55)
    lg.ellipse("fill", 0, r * 0.42, r * 0.12, r * 0.06)
    lg.setColor(1.0, 0.55, 0.65, 0.5)
    lg.ellipse("fill", -r * 0.6, r * 0.22, r * 0.15, r * 0.09)
    lg.ellipse("fill", r * 0.6, r * 0.22, r * 0.15, r * 0.09)
  end
  lg.pop()
end

-- Gradient backdrop with scrolling diagonal stripes, tinted by `tint`.
local function backdrop(tint, t)
  local top = mix({ 0.30, 0.20, 0.62 }, tint, 0.18)
  local bot = mix({ 0.12, 0.07, 0.30 }, tint, 0.10)
  local bands = 30
  for i = 0, bands - 1 do
    local c = mix(top, bot, i / (bands - 1))
    lg.setColor(c[1], c[2], c[3])
    lg.rectangle("fill", 0, i * H / bands, W, H / bands + 1)
  end
  lg.setColor(1, 1, 1, 0.045)
  local step, off = 56, (t * 18) % 56
  for x = -H - step, W + step, step do
    local x0 = x + off
    lg.polygon("fill", x0, 0, x0 + 24, 0, x0 + 24 + H, H, x0 + H, H)
  end
  -- soft floating bubbles
  for i = 1, 9 do
    local bx = (i * 97 + math.sin(t * 0.3 + i) * 30) % W
    local by = H - ((t * (12 + i * 3) + i * 71) % (H + 80)) + 40
    lg.setColor(1, 1, 1, 0.05)
    lg.circle("fill", bx, by, 10 + (i % 4) * 7)
  end
end

---------------------------------------------------------------------------
-- Scenes

local function draw_title()
  local s = game.state
  local t = s.elapsed
  backdrop(PALETTE[(math.floor(t / 2) % COLORS) + 1], t)

  -- Logo: one candy colour per letter, bobbing in a wave.
  local word = "FLOODER"
  local font = fonts.logo
  local widths, total = {}, 0
  for i = 1, #word do
    widths[i] = font:getWidth(word:sub(i, i)) + 2
    total = total + widths[i]
  end
  local x = (W - total) / 2 + 30
  for i = 1, #word do
    local ch = word:sub(i, i)
    local bob = math.sin(t * 3 - i * 0.6) * 6
    lg.push()
    lg.translate(x + widths[i] / 2, 92 + bob)
    lg.rotate(math.sin(t * 2 - i) * 0.05)
    outlined(ch, -widths[i], -44, widths[i] * 2, "center", font, PALETTE[(i - 1) % COLORS + 1], 5)
    lg.pop()
    x = x + widths[i]
  end
  local mascot_col = PALETTE[(math.floor(t / 2) % COLORS) + 1]
  drip((W - total) / 2 - 22, 104 + math.abs(math.sin(t * 3)) * -12, 26, mascot_col, "happy", t)

  -- Tagline ribbon
  local rw = 380
  lg.setColor(INK[1], INK[2], INK[3])
  lg.rectangle("fill", (W - rw) / 2 - 3, 152 - 3, rw + 6, 34, 17, 17)
  lg.setColor(1.0, 0.80, 0.22)
  lg.rectangle("fill", (W - rw) / 2, 152, rw, 28, 14, 14)
  lg.setFont(fonts.body)
  lg.setColor(INK[1], INK[2], INK[3])
  lg.printf("flood the board before your moves run out!", 0, 156, W, "center")

  -- Board size cards
  local cw, ch, gap = 156, 118, 22
  local x0 = (W - (cw * 3 + gap * 2)) / 2
  for i, size in ipairs(SIZES) do
    local on = i == s.size
    local cx = x0 + (i - 1) * (cw + gap)
    local cy = 236 + (on and -8 - math.abs(math.sin(t * 4)) * 4 or 0)
    card(cx, cy, cw, ch, 16, on and CREAM or { 0.80, 0.78, 0.90 })
    -- mini candy board
    local m, ts = 5, 15
    local mx = cx + (cw - m * ts) / 2
    for yy = 1, 3 do
      for xx = 1, m do
        local ci = ((xx * 3 + yy * 5 + i * 7) % COLORS) + 1
        if xx + yy <= 1 + i then ci = 4 end
        candy(mx + (xx - 1) * ts, cy + 14 + (yy - 1) * ts, ts - 1, PALETTE[ci])
      end
    end
    lg.setFont(fonts.hud)
    lg.setColor(INK[1], INK[2], INK[3], on and 1 or 0.55)
    lg.printf(size.name, cx, cy + 64, cw, "center")
    lg.setFont(fonts.small)
    lg.printf(size.n .. " x " .. size.n, cx, cy + 90, cw, "center")
    if on then
      lg.setColor(1.0, 0.80, 0.22)
      lg.setLineWidth(4)
      lg.rectangle("line", cx - 8, cy - 8, cw + 16, ch + 16, 20, 20)
      -- bouncing cursor arrow
      local ay = cy - 24 + math.sin(t * 8) * 3
      lg.setColor(INK[1], INK[2], INK[3])
      lg.polygon("fill", cx + cw / 2 - 13, ay - 3, cx + cw / 2 + 13, ay - 3, cx + cw / 2, ay + 15)
      lg.setColor(1.0, 0.80, 0.22)
      lg.polygon("fill", cx + cw / 2 - 9, ay, cx + cw / 2 + 9, ay, cx + cw / 2, ay + 10)
    end
  end

  local stat = s.stats[s.size]
  local line = stat.played > 0
    and ("WINS " .. stat.won .. "/" .. stat.played .. "    STREAK " .. stat.streak .. "    BEST " .. stat.best_streak)
    or "BEAT THE BOT: FINISH WITHIN ITS MOVE COUNT"
  outlined(line, 0, 374, W, "center", fonts.small, CREAM, 2)

  local blink = math.sin(t * 5) > -0.3
  if blink then
    outlined("PRESS START", 0, 396, W, "center", fonts.big, { 1.0, 0.80, 0.22 }, 3)
  end

  prompt_bar({ { "+", "SIZE" }, { "A", "PLAY" } })
end

local function draw_board(shx)
  local s = game.state
  local st = s.st
  local ox, oy, c = board_origin()
  local n = st.w
  local t = s.elapsed
  ox = ox + shx

  -- Frame
  card(BOARD_X - 10 + shx, BOARD_Y - 10, BOARD_PX + 20, BOARD_PX + 20, 18)
  lg.setColor(INK[1], INK[2], INK[3])
  lg.rectangle("fill", BOARD_X - 3 + shx, BOARD_Y - 3, BOARD_PX + 6, BOARD_PX + 6, 10, 10)

  local region = rules.region(st)
  local preview = {}
  if s.scene == "play" then
    for _, p in ipairs(rules.preview(st, s.sel)) do
      preview[(p.y - 1) * n + p.x] = true
    end
  end

  local lose = s.scene == "gameover" and not st.won
  for y = 1, st.h do
    for x = 1, n do
      local k = (y - 1) * n + x
      local col = PALETTE[st.grid[y][x]]
      local inset = 1
      local t0 = s.pop[k]
      if t0 then
        local dt = t - t0
        if dt < 0 then
          inset = c * 0.5
        elseif dt < 0.22 then
          local p = dt / 0.22
          inset = c * 0.5 * (1 - p) - c * 0.15 * math.sin(p * math.pi) + 1
        end
      end
      local px, py = ox + (x - 1) * c, oy + (y - 1) * c
      if inset < c * 0.5 then
        if region[k] then
          -- Owned region: tiles fuse into one blob with a shimmer sweep.
          local glow = 0.16 * math.max(0, math.sin(t * 2.5 - (x + y) * 0.35)) ^ 6
          local edge = y == st.h or not region[k + n]
          local bev = edge and math.max(2, c * 0.12) or 0
          shade(col, 0.62 + glow)
          lg.rectangle("fill", px + inset - 1, py + inset - 1, c - inset * 2 + 2, c - inset * 2 + 2)
          shade(col, 1 + glow)
          lg.rectangle("fill", px + inset - 1, py + inset - 1, c - inset * 2 + 2, c - inset * 2 + 2 - bev)
        else
          candy(px + inset, py + inset, c - inset * 2, col, lose and -0.35 or 0)
          if preview[k] then
            local a = 0.55 + 0.45 * math.sin(t * 8)
            lg.setColor(1, 1, 1, a)
            lg.setLineWidth(3)
            lg.rectangle("line", px + 3, py + 3, c - 6, c - 6, c * 0.2, c * 0.2)
          end
        end
      end
    end
  end

  -- Glossy glass reflection across the whole board
  lg.setColor(1, 1, 1, 0.06)
  lg.polygon("fill", BOARD_X + shx, BOARD_Y, BOARD_X + 150 + shx, BOARD_Y,
    BOARD_X + shx, BOARD_Y + 150)
end

local function draw_panel()
  local s = game.state
  local st = s.st
  local t = s.elapsed
  local x, w = PANEL_X, PANEL_W
  local left = st.max_moves - st.moves
  local cur = PALETTE[st.grid[1][1]]

  -- Moves card with a circular gauge and Drip
  card(x, 18, w, 176, 18)
  outlined("MOVES", x, 26, w, "center", fonts.small, CREAM, 2)
  local gx, gy, gr = x + w / 2, 104, 54
  lg.setLineWidth(12)
  lg.setColor(INK[1], INK[2], INK[3], 0.15)
  lg.arc("line", "open", gx, gy, gr, math.pi * 0.75, math.pi * 2.25, 40)
  local danger = left <= 3 and not st.won
  local gcol = danger and PALETTE[1] or { 0.36, 0.86, 0.38 }
  if s.gauge > 0.005 then
    lg.setColor(INK[1], INK[2], INK[3])
    lg.setLineWidth(16)
    lg.arc("line", "open", gx, gy, gr, math.pi * 0.75, math.pi * (0.75 + 1.5 * s.gauge), 40)
    shade(gcol, 1)
    lg.setLineWidth(10)
    lg.arc("line", "open", gx, gy, gr, math.pi * 0.75, math.pi * (0.75 + 1.5 * s.gauge), 40)
  end
  local pulse = danger and (1 + 0.12 * math.abs(math.sin(t * 6))) or 1
  lg.push()
  lg.translate(gx, gy - 6)
  lg.scale(pulse)
  outlined(tostring(left), -60, -34, 120, "center", fonts.huge, danger and PALETTE[1] or CREAM, 3)
  lg.pop()
  lg.setFont(fonts.small)
  lg.setColor(INK[1], INK[2], INK[3], 0.7)
  lg.printf("OF " .. st.max_moves .. " LEFT", gx - 60, gy + 30, 120, "center")

  local frac = rules.size(st) / (st.w * st.h)
  lg.setColor(INK[1], INK[2], INK[3], 0.6)
  lg.printf(math.floor(frac * 100 + 0.5) .. "% FLOODED", x, 172, w, "center")

  -- Drip sits on the top-right corner of the card
  local mood = "happy"
  if s.scene == "gameover" and not st.won then
    mood = "sad"
  elseif danger then
    mood = "worried"
  end
  local hop = 0
  local bt = t - s.bounce
  if bt < 0.4 then hop = -math.sin(bt / 0.4 * math.pi) * 18 end
  if s.scene == "gameover" and st.won then hop = -math.abs(math.sin(t * 6)) * 14 end
  drip(x + w - 22, 54 + hop, 16, cur, mood, t)

  -- Colour dock
  card(x, DOCK_Y, w, 220, 18)
  outlined("PICK A COLOUR", x, DOCK_Y + 8, w, "center", fonts.small, CREAM, 2)
  local current = st.grid[1][1]
  for i = 1, COLORS do
    local cx, cy = game.orb_center(i)
    local on = i == s.sel and s.scene == "play"
    if on then
      cy = cy - 6 - math.abs(math.sin(t * 5)) * 3
      lg.setColor(1.0, 0.80, 0.22, 0.6 + 0.4 * math.sin(t * 8))
      lg.setLineWidth(4)
      lg.circle("line", cx, cy, ORB_R + 9)
    end
    orb(i, cx, cy, ORB_R, i == current)
  end

  if s.scene == "play" then
    local g = rules.gain(st, s.sel)
    local label = s.sel == current and "ALREADY YOURS" or ("+" .. g .. " TILES")
    local bx, by = x + 16, DOCK_Y + 182
    lg.setColor(INK[1], INK[2], INK[3])
    lg.rectangle("fill", bx, by, w - 32, 28, 14, 14)
    lg.setFont(fonts.small)
    shade(s.sel == current and { 0.7, 0.7, 0.8 } or PALETTE[s.sel], 1)
    lg.printf(label, bx, by + 6, w - 32, "center")
  end
end

local function draw_gameover()
  local s = game.state
  local st = s.st
  local t = s.elapsed - s.stamp
  local cx, cy = BOARD_X + BOARD_PX / 2, BOARD_Y + BOARD_PX / 2

  lg.setColor(INK[1], INK[2], INK[3], math.min(0.45, t * 1.5))
  lg.rectangle("fill", BOARD_X, BOARD_Y, BOARD_PX, BOARD_PX, 10, 10)

  -- Stamp: slams in big and settles with a wobble
  local p = math.min(1, t / 0.28)
  local scale = 2.6 - 1.6 * p + (p >= 1 and math.sin(math.min(t - 0.28, 0.5) * 18) * 0.06 * (1 - math.min(1, (t - 0.28) * 2)) or 0)
  local text = st.won and "CLEAR!" or "OUT OF\nMOVES"
  local col = st.won and { 1.0, 0.80, 0.22 } or PALETTE[1]
  lg.push()
  lg.translate(cx, cy - 56)
  lg.rotate(-0.08)
  lg.scale(scale)
  outlined(text, -200, st.won and -36 or -60, 400, "center", st.won and fonts.logo or fonts.huge, col, 5)
  lg.pop()

  if t > 0.35 then
    local stat = s.stats[s.size]
    local msg
    if st.won then
      local spare = st.max_moves - st.moves
      msg = st.moves .. " MOVES  ·  " .. (spare > 0 and (spare .. " SPARE") or "JUST IN TIME!")
    else
      msg = math.floor(rules.size(st) / (st.w * st.h) * 100 + 0.5) .. "% FLOODED"
    end
    card(cx - 140, cy + 28, 280, 82, 16)
    lg.setFont(fonts.hud)
    lg.setColor(INK[1], INK[2], INK[3])
    lg.printf(msg, cx - 140, cy + 40, 280, "center")
    lg.setFont(fonts.small)
    lg.setColor(INK[1], INK[2], INK[3], 0.65)
    lg.printf("STREAK " .. stat.streak .. "   ·   BEST " .. stat.best_streak, cx - 140, cy + 76, 280, "center")
  end

  for _, c in ipairs(s.confetti) do
    lg.push()
    lg.translate(c.x, c.y)
    lg.rotate(c.r)
    shade(PALETTE[c.c], 1, math.min(1, c.life))
    lg.rectangle("fill", -5, -3, 10, 6, 1, 1)
    lg.pop()
  end
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
    backdrop(PALETTE[s.st.grid[1][1]], s.elapsed)
    local shx = s.shake > 0 and math.sin(s.elapsed * 60) * 8 * (s.shake / 0.45) or 0
    draw_board(shx)
    draw_panel()
    if s.scene == "gameover" then
      draw_gameover()
      prompt_bar({ { "A", "NEW BOARD" }, { "B", "MENU" } })
    else
      prompt_bar({ { "+", "CHOOSE" }, { "A", "FLOOD" }, { "Y", "NEW BOARD" }, { "B", "MENU" } })
    end
  end

  lg.pop()
end

return game
