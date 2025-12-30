-- CC:Tweaked Music Player (GUI) - Stream from GitHub music folder
-- Requires: speaker peripheral + HTTP enabled + DFPWM files in GitHub repo music/
-- Requires: music/index.txt in repo

local speaker = peripheral.find("speaker")
if not speaker then
  error("No speaker found! Place a speaker next to the computer.")
end

if not http then
  error("HTTP API disabled! Enable http in CC:Tweaked config.")
end

local dfpwm = require("cc.audio.dfpwm")
local decoder = dfpwm.make_decoder()

-- ====== Repo Config ======
local REPO_USER = "Ace-2778"
local REPO_NAME = "Minecraft-lua"
local BRANCH = "main"

local INDEX_URL = ("https://raw.githubusercontent.com/%s/%s/%s/music/index.txt")
  :format(REPO_USER, REPO_NAME, BRANCH)

local function musicUrl(path)
  -- path is relative to music/ (may include subdirs)
  return ("https://raw.githubusercontent.com/%s/%s/%s/music/%s")
    :format(REPO_USER, REPO_NAME, BRANCH, path)
end

-- ---------- UI Helpers ----------
local w, h = term.getSize()

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function centerText(y, text, fg, bg)
  local x = math.floor((w - #text) / 2) + 1
  term.setCursorPos(x, y)
  if bg then term.setBackgroundColor(bg) end
  if fg then term.setTextColor(fg) end
  term.write(text)
end

local function drawBox(x1, y1, x2, y2, bg)
  term.setBackgroundColor(bg or colors.gray)
  for yy = y1, y2 do
    term.setCursorPos(x1, yy)
    term.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function drawButton(x, y, label, active)
  local bw = #label + 2
  term.setCursorPos(x, y)
  term.setBackgroundColor(active and colors.lime or colors.gray)
  term.setTextColor(colors.black)
  term.write(" " .. label .. " ")
  return bw
end

local function isInside(px, py, x, y, bw, bh)
  return px >= x and px < x + bw and py >= y and py < y + bh
end

-- ---------- Remote Music Helpers ----------
local function fetchIndex()
  local res, err = http.get(INDEX_URL, { ["User-Agent"] = "CCT-MusicPlayer" })
  if not res then
    return nil, "Index http.get failed: " .. tostring(err)
  end

  local code = res.getResponseCode and res.getResponseCode() or 200
  local txt = res.readAll() or ""
  res.close()

  if code ~= 200 then
    return nil, "Index HTTP " .. tostring(code) .. " " .. txt:sub(1, 80)
  end
  if txt == "" then
    return nil, "Index empty"
  end
  return txt, nil
end

local function parseIndex(txt)
  local list = {}
  for line in txt:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then
      table.insert(list, line)
    end
  end
  table.sort(list)
  return list
end

local function listMusicRemote()
  local txt, err = fetchIndex()
  if not txt then
    return {}, err
  end
  return parseIndex(txt), nil
end

-- ---------- Player State ----------
local songs = {}
local selected = 1
local playing = false
local paused = false
local currentSong = nil

local statusMsg = ""

local scroll = 0
local listHeight = h - 9
if listHeight < 5 then listHeight = 5 end

-- progress
local bytesPlayed = 0
local totalBytes = 0   -- if unknown, keep 0
local progress = 0

-- playback coroutine
local playbackThread = nil
local stopRequested = false

local function setStatus(msg)
  statusMsg = msg or ""
end

-- ---------- Playback (stream from GitHub) ----------
local function stopSong()
  stopRequested = true
  playing = false
  paused = false
  progress = 0
  bytesPlayed = 0
  totalBytes = 0
end

local function playSong(name)
  stopSong()
  stopRequested = false

  currentSong = name
  bytesPlayed = 0
  progress = 0
  totalBytes = 0
  playing = true
  paused = false

  local url = musicUrl(name)

  playbackThread = coroutine.create(function()
    local res, err = http.get(url, { ["User-Agent"] = "CCT-MusicPlayer" })
    if not res then
      setStatus("Play failed: " .. tostring(err))
      playing = false
      return
    end

    local code = res.getResponseCode and res.getResponseCode() or 200
    if code ~= 200 then
      local body = res.readAll() or ""
      res.close()
      setStatus("Play HTTP " .. tostring(code) .. " " .. body:sub(1, 60))
      playing = false
      return
    end

    -- Try get content length if supported
    if res.getResponseHeaders then
      local headers = res.getResponseHeaders()
      if headers and headers["Content-Length"] then
        totalBytes = tonumber(headers["Content-Length"]) or 0
      end
    end

    setStatus("Streaming: " .. name)

    while true do
      if stopRequested then break end

      if paused then
        os.sleep(0.05)
      else
        -- read in chunks
        local chunk = res.read(16 * 1024)
        if not chunk then break end

        bytesPlayed = bytesPlayed + #chunk
        if totalBytes > 0 then
          progress = bytesPlayed / totalBytes
        else
          progress = 0 -- unknown
        end

        local buffer = decoder(chunk)
        while not speaker.playAudio(buffer) do
          if stopRequested then break end
          os.pullEvent("speaker_audio_empty")
        end
      end
    end

    res.close()
    playing = false
    paused = false
    setStatus("Finished: " .. name)
  end)
end

local function nextSong()
  if #songs == 0 then return end
  selected = selected + 1
  if selected > #songs then selected = 1 end
  playSong(songs[selected])
end

local function prevSong()
  if #songs == 0 then return end
  selected = selected - 1
  if selected < 1 then selected = #songs end
  playSong(songs[selected])
end

local function togglePause()
  if not playing then return end
  paused = not paused
end

-- ---------- UI ----------
local function drawUI()
  term.setBackgroundColor(colors.black)
  term.clear()

  -- Header
  drawBox(1, 1, w, 3, colors.blue)
  centerText(2, "🎵 CCT Music Player (GitHub Stream)", colors.white, colors.blue)

  -- Songs list panel
  drawBox(1, 4, math.floor(w * 0.55), h, colors.black)
  term.setCursorPos(2, 4)
  term.setTextColor(colors.yellow)
  term.setBackgroundColor(colors.black)
  term.write("Songs (GitHub /music/index.txt)")

  local listX1 = 2
  local listY1 = 6
  local listX2 = math.floor(w * 0.55) - 1

  drawBox(1, 5, math.floor(w * 0.55), h, colors.black)

  -- Scroll bounds
  local maxScroll = math.max(0, #songs - listHeight)
  scroll = clamp(scroll, 0, maxScroll)

  for i = 1, listHeight do
    local idx = i + scroll
    local y = listY1 + i - 1
    term.setCursorPos(listX1, y)

    local text = songs[idx] or ""
    if #text > (listX2 - listX1 + 1) then
      text = text:sub(1, (listX2 - listX1 + 1) - 3) .. "..."
    end

    if idx == selected then
      term.setBackgroundColor(colors.gray)
      term.setTextColor(colors.black)
    else
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
    end

    term.write(string.rep(" ", listX2 - listX1 + 1))
    term.setCursorPos(listX1, y)
    term.write(text)
  end

  -- Right panel
  local rightX = math.floor(w * 0.55) + 1
  drawBox(rightX, 4, w, h, colors.black)

  term.setCursorPos(rightX + 1, 5)
  term.setTextColor(colors.cyan)
  term.write("Now Playing:")

  term.setCursorPos(rightX + 1, 6)
  term.setTextColor(colors.white)
  local np = currentSong or "(none)"
  if #np > (w - rightX - 1) then
    np = np:sub(1, (w - rightX - 1) - 3) .. "..."
  end
  term.write(np)

  -- Progress bar
  term.setCursorPos(rightX + 1, 8)
  term.setTextColor(colors.cyan)
  term.write("Progress:")

  local barW = w - (rightX + 2)
  local filled = 0
  if totalBytes > 0 then
    filled = math.floor(barW * clamp(progress, 0, 1))
  end

  term.setCursorPos(rightX + 1, 9)
  term.setBackgroundColor(colors.gray)
  term.write(string.rep(" ", barW))

  term.setCursorPos(rightX + 1, 9)
  term.setBackgroundColor(colors.lime)
  term.write(string.rep(" ", filled))

  term.setBackgroundColor(colors.black)
  term.setCursorPos(rightX + 1, 10)
  term.setTextColor(colors.white)
  if totalBytes > 0 then
    term.write(string.format("%d%%", math.floor(progress * 100)))
  else
    term.write("Streaming... (size unknown)")
  end

  -- Buttons
  local bx = rightX + 1
  local by = h - 3

  local btnPrevW = drawButton(bx, by, "<<", false)
  local btnPlayW = drawButton(bx + btnPrevW + 1, by, playing and (paused and "Resume" or "Pause") or "Play", false)
  local btnNextW = drawButton(bx + btnPrevW + btnPlayW + 2, by, ">>", false)
  local btnStopW = drawButton(w - 6, by, "Stop", false)

  -- footer tips + status
  term.setCursorPos(rightX + 1, h - 2)
  term.setTextColor(colors.lightGray)
  term.setBackgroundColor(colors.black)
  term.write("Click song | Wheel scroll | Q quit")

  term.setCursorPos(rightX + 1, h - 1)
  term.setTextColor(colors.orange)
  term.write(statusMsg:sub(1, w - rightX - 1))
end

local function handleClick(x, y)
  -- Click on song list
  local listX2 = math.floor(w * 0.55) - 1
  local listY1 = 6
  if x >= 2 and x <= listX2 and y >= listY1 and y < listY1 + listHeight then
    local idx = (y - listY1 + 1) + scroll
    if songs[idx] then
      selected = idx
      playSong(songs[selected])
    end
    return
  end

  -- Buttons area
  local rightX = math.floor(w * 0.55) + 1
  local bx = rightX + 1
  local by = h - 3

  local prevW = 4
  local playW = (playing and (paused and 8 or 7) or 6) + 2
  local nextW = 4
  local stopW = 6

  if isInside(x, y, bx, by, prevW, 1) then
    prevSong(); return
  end

  if isInside(x, y, bx + prevW + 1, by, playW, 1) then
    if not playing then
      if songs[selected] then playSong(songs[selected]) end
    else
      togglePause()
    end
    return
  end

  if isInside(x, y, bx + prevW + playW + 2, by, nextW, 1) then
    nextSong(); return
  end

  if isInside(x, y, w - stopW, by, stopW, 1) then
    stopSong(); setStatus("Stopped"); return
  end
end

-- ---------- Startup ----------
local function refreshSongs()
  setStatus("Fetching music list...")
  drawUI()
  local list, err = listMusicRemote()
  if err then
    songs = {}
    selected = 1
    setStatus(err)
  else
    songs = list
    if #songs == 0 then
      setStatus("No songs in music/index.txt")
    else
      setStatus("Loaded " .. #songs .. " song(s).")
    end
    selected = clamp(selected, 1, math.max(1, #songs))
  end
end

refreshSongs()
drawUI()

-- ---------- Main Loop ----------
while true do
  drawUI()

  -- step playback coroutine
  if playbackThread and coroutine.status(playbackThread) ~= "dead" then
    local ok, err = coroutine.resume(playbackThread)
    if not ok then
      setStatus("Playback error: " .. tostring(err))
      playing = false
      paused = false
      playbackThread = nil
    end
  end

  local e = { os.pullEvent() }
  local ev = e[1]

  if ev == "mouse_click" then
    handleClick(e[3], e[4])
  elseif ev == "mouse_scroll" then
    scroll = scroll + e[2]
  elseif ev == "key" then
    local k = e[2]
    if k == keys.q then
      stopSong()
      term.setBackgroundColor(colors.black)
      term.clear()
      term.setCursorPos(1, 1)
      break
    elseif k == keys.up then
      selected = clamp(selected - 1, 1, #songs)
      if selected < scroll + 1 then scroll = scroll - 1 end
    elseif k == keys.down then
      selected = clamp(selected + 1, 1, #songs)
      if selected > scroll + listHeight then scroll = scroll + 1 end
    elseif k == keys.enter then
      if songs[selected] then playSong(songs[selected]) end
    elseif k == keys.space then
      if playing then togglePause() end
    elseif k == keys.left then
      prevSong()
    elseif k == keys.right then
      nextSong()
    elseif k == keys.s then
      stopSong(); setStatus("Stopped")
    elseif k == keys.r then
      refreshSongs()
    end
  elseif ev == "term_resize" then
    w, h = term.getSize()
    listHeight = h - 9
    if listHeight < 5 then listHeight = 5 end
  end
end
