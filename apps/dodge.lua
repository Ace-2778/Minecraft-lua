-- Dodge Game for CC:Tweaked
-- Controls: A/Left = move left, D/Right = move right, Q = quit

local w, h = term.getSize()
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)

math.randomseed(os.clock() * 100000)

-- Player setup
local playerX = math.floor(w / 2)
local playerY = h
local score = 0

-- Falling rocks
local rocks = {}
local rockSpawnRate = 0.12     -- 初始生成概率（每帧）
local rockSpeed = 0.12         -- 初始下落速度（秒/格）
local frameDelay = 0.05        -- 每帧刷新时间

local lastFall = os.clock()

local function drawTextCentered(y, text)
  local x = math.floor((w - #text) / 2) + 1
  term.setCursorPos(x, y)
  term.write(text)
end

local function draw()
  term.clear()

  -- UI
  term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow)
  term.write("Score: " .. score)
  term.setCursorPos(w - 10, 1)
  term.setTextColor(colors.lightGray)
  term.write("Q=Quit")

  -- Draw rocks
  term.setTextColor(colors.red)
  for i = 1, #rocks do
    local r = rocks[i]
    if r.y >= 2 and r.y <= h then
      term.setCursorPos(r.x, r.y)
      term.write("*")
    end
  end

  -- Draw player
  term.setTextColor(colors.lime)
  term.setCursorPos(playerX, playerY)
  term.write("A")
end

local function spawnRock()
  if math.random() < rockSpawnRate then
    table.insert(rocks, {x = math.random(1, w), y = 2})
  end
end

local function moveRocks()
  if os.clock() - lastFall >= rockSpeed then
    lastFall = os.clock()

    for i = #rocks, 1, -1 do
      rocks[i].y = rocks[i].y + 1

      -- If out of screen, remove
      if rocks[i].y > h then
        table.remove(rocks, i)
        score = score + 1
      end
    end
  end
end

local function checkCollision()
  for i = 1, #rocks do
    if rocks[i].x == playerX and rocks[i].y == playerY then
      return true
    end
  end
  return false
end

local function gameOver()
  term.clear()
  term.setTextColor(colors.red)
  drawTextCentered(math.floor(h/2) - 1, "GAME OVER!")
  term.setTextColor(colors.white)
  drawTextCentered(math.floor(h/2), "Final Score: " .. score)
  term.setTextColor(colors.lightGray)
  drawTextCentered(math.floor(h/2) + 2, "Press any key to exit...")
  os.pullEvent("key")
end

local function updateDifficulty()
  -- 随着分数提高，加快速度、增加生成概率
  rockSpawnRate = math.min(0.35, 0.12 + score * 0.003)
  rockSpeed = math.max(0.03, 0.12 - score * 0.0015)
end

-- Intro screen
term.clear()
term.setTextColor(colors.cyan)
drawTextCentered(4, "=== DODGE: Meteor Shower ===")
term.setTextColor(colors.white)
drawTextCentered(6, "Move: A/D or Arrow Keys")
drawTextCentered(7, "Avoid the falling '*' rocks")
drawTextCentered(8, "Quit: Q")
term.setTextColor(colors.lightGray)
drawTextCentered(10, "Press any key to start...")
os.pullEvent("key")

-- Game loop
local running = true
while running do
  spawnRock()
  moveRocks()
  updateDifficulty()
  draw()

  if checkCollision() then
    running = false
    break
  end

  -- Input (non-blocking)
  local timer = os.startTimer(frameDelay)
  while true do
    local ev, p1 = os.pullEvent()
    if ev == "timer" and p1 == timer then
      break
    elseif ev == "key" then
      if p1 == keys.left or p1 == keys.a then
        playerX = math.max(1, playerX - 1)
      elseif p1 == keys.right or p1 == keys.d then
        playerX = math.min(w, playerX + 1)
      elseif p1 == keys.q then
        running = false
        break
      end
    end
  end
end

gameOver()
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
