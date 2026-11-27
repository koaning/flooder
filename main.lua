local game = require("src.game")

function love.load(args)
  game.load(args)
end

function love.update(dt)
  game.update(dt)
end

function love.draw()
  game.draw()
end

function love.keypressed(key)
  game.keypressed(key)
end

function love.gamepadpressed(joystick, button)
  game.gamepadpressed(joystick, button)
end

function love.mousepressed(x, y, button)
  game.mousepressed(x, y, button)
end
