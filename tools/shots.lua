-- Scripted screenshot run for `make screenshots`.
--
-- Runs as a coroutine inside tools/shot_runner.lua and saves:
--   docs/screenshots/title.png      title screen
--   docs/screenshots/cart.png       Geyser-style cartridge label (used by `make cart`)
--   docs/screenshots/gameplay.png   a medium board part-way through
--   docs/screenshots/win.png        a won round

return {
  -- Deterministic save state for screenshots (never touches real user saves)
  save = {
    ["stats.txt"] = "2 played 9\n2 won 6\n2 streak 3\n2 best_streak 4\n2 best_spare 2\n",
  },
  run = function(ctx)
    local game = require("src.game")
    local rules = require("src.rules")

    local function best_color(st)
      local best, best_gain = nil, -1
      for c = 1, st.colors do
        local g = rules.gain(st, c)
        if g > best_gain then best, best_gain = c, g end
      end
      return best
    end

    ctx.frame(40)
    ctx.shot("title.png")
    ctx.cartridge("cart.png")

    -- Medium board: play 9 greedy moves, then hover a good colour so the
    -- preview outlines show.
    ctx.key("space")
    ctx.frame(2)
    local st = game.state.st
    for _ = 1, 9 do
      ctx.key(tostring(best_color(st)))
      ctx.frame(3)
    end
    ctx.frame(30)
    game.state.sel = best_color(st)
    ctx.frame(4)
    ctx.shot("gameplay.png")

    while game.state.scene == "play" do
      ctx.key(tostring(best_color(st)))
      ctx.frame(2)
    end
    ctx.frame(40)
    ctx.shot("win.png")
  end,
}
