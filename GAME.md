# Flooder

flood the board in as few moves as you can

Notes for agents about this game (the toolchain notes are in `AGENTS.md`).

- Code: `src/rules.lua` holds the pure Lua game rules (unit-tested directly by
  `tests/test_rules.lua`), `src/game.lua` holds scenes, input, drawing and save
  persistence, and `main.lua` wires LÖVE callbacks to `src/game.lua`.
- Resolution: virtual `640x480` letterboxed to the window
  (configured in `conf.lua` and `game.mk`).
- Rules: `rules.new` deals a board, `rules.flood` makes a move and returns the
  absorbed cells with their ripple distance, `rules.preview`/`rules.gain` look
  ahead, and `rules.greedy_moves` sets each board's move limit (so every board
  is winnable).
- Controls: D-pad / arrows move the colour selection (previewed on the board),
  A / Space / Enter floods, 1-6 or mouse click picks directly, B / Backspace
  menu, Y / R new board, Esc (or Back) quits on desktop/handhelds. On the title
  screen left/right picks the board size.
- Save data: `stats.txt` in LÖVE's save directory (`t.identity = "flooder"`),
  lines of `<size index> <field> <value>` (played, won, streak, best_streak,
  best_spare).
