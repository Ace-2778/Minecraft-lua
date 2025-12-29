-- /system/desktop.lua
-- Folder-based App Desktop for CC:Tweaked (Advanced Computer recommended)

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)

local w, h = term.getSize()
local listTop = 3
local listBottom = h - 2
local visible = listBottom - listTop + 1

local scroll = 0
local selected = 1
local current = "/apps"

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function isLua(name) return name:match("%.lua$") ~= nil end

local function getEntries(path)
  if not fs.exists(path) then fs.makeDir(path) end
  local items = fs.list(path)
  local folders, files = {}, {}

  for _, it in ipairs(items) do
    local full = fs.combine(path, it)
    if fs.isDir(full) then
      table.insert(folders, {name = it, full = full, kind = "dir"})
    elseif isLua(it) then
      table.insert(files, {name = it:gsub("%.lua$", ""), file = it, full = full, kind = "lua"})
    end
  end

  table.sort(folders, function(a,b) return a.name:lower() < b.name:lower() end)
  table.sort(files, function(a,b) return a.name:lower() < b.name:lower() end)

  local entries = {}
  for _, f in ipairs(folders) do table.insert(entries, f) end
  for _, f in ipairs(files) do table.insert(entries, f) end

  return entries
end

local function drawHeader(path, count)
  term.setBackgroundColor(colors.blue)
  term.setTextColor(colors.white)
  term.setCursorPos(1,1)
  term.write(string.rep(" ", w))

  term.setCursorPos(2,1)
  term.write("< Back")

  term.setCursorPos(10,1)
  term.write("CCT Desktop")

  term.setCursorPos(22,1)
  term.write(path)

  term.setCursorPos(w-10,1)
  term.write("Items:"..count)
end

local function drawFooter()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.lightGray)
  term.setCursorPos(1,h)
  term.write(string.rep(" ", w))
  term.setCursorPos(2,h)
  term.write("Click folder to enter | Click app to run | Scroll | Q quit")
end

local function clear()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
end

local function drawList(entries)
  -- list background
  term.setBackgroundColor(colors.gray)
  for y=2,h-1 do
    term.setCursorPos(1,y)
    term.write(string.rep(" ", w))
  end

  -- title row
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.black)
  term.setCursorPos(2,2)
  term.write("Folders & Apps")

  for i=1,visible do
    local idx = i + scroll
    local y = listTop + i - 1

    term.setCursorPos(2,y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", w-2))

    if idx <= #entries then
      local e = entries[idx]
      local label
      if e.kind == "dir" then
        label = "📁 "..e.name
        term.setTextColor(colors.yellow)
      else
        label = "▶ "..e.name
        term.setTextColor(colors.lime)
      end

      if idx == selected then
        term.setBackgroundColor(colors.lightBlue)
        term.setTextColor(colors.black)
      else
        term.setBackgroundColor(colors.gray)
      end

      term.setCursorPos(2,y)
      if #label > w-3 then label = label:sub(1, w-6).."..." end
      term.write(label)
    end
  end
end

local function draw(path, entries)
  clear()
  drawHeader(path, #entries)
  drawList(entries)
  drawFooter()
end

local function goUp()
  if current == "/apps" then return end
  local parent = fs.getDir(current)
  if parent == "" then parent = "/" end
  current = parent
  scroll, selected = 0, 1
end

local function enter(entries)
  if #entries == 0 then return end
  local e = entries[selected]
  if e.kind == "dir" then
    current = e.full
    scroll, selected = 0, 1
  else
    -- run lua app
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)

    if multishell and multishell.launch then
      multishell.launch({}, e.full)
    else
      shell.run(e.full)
    end
  end
end

local function clickBack(x,y)
  return y == 1 and x >= 2 and x <= 7
end

local function main()
  if not fs.exists("/apps") then fs.makeDir("/apps") end

  while true do
    local entries = getEntries(current)
    selected = clamp(selected, 1, math.max(1, #entries))
    scroll = clamp(scroll, 0, math.max(0, #entries - visible))

    draw(current, entries)

    local ev, p1, x, y = os.pullEvent()

    if ev == "mouse_scroll" then
      if p1 == 1 then
        scroll = clamp(scroll+1, 0, math.max(0, #entries - visible))
      else
        scroll = clamp(scroll-1, 0, math.max(0, #entries - visible))
      end

    elseif ev == "mouse_click" then
      if clickBack(x,y) then
        goUp()
      elseif y >= listTop and y <= listBottom then
        local idx = scroll + (y - listTop + 1)
        if idx >= 1 and idx <= #entries then
          selected = idx
          -- left click to open/run
          if p1 == 1 then
            enter(entries)
          end
        end
      end

    elseif ev == "key" then
      if p1 == keys.q then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1,1)
        return
      elseif p1 == keys.up then
        selected = clamp(selected-1, 1, math.max(1, #entries))
        if selected < scroll+1 then scroll = selected-1 end
      elseif p1 == keys.down then
        selected = clamp(selected+1, 1, math.max(1, #entries))
        if selected > scroll+visible then scroll = selected-visible end
      elseif p1 == keys.enter then
        enter(entries)
      elseif p1 == keys.backspace then
        goUp()
      end
    end
  end
end

main()
