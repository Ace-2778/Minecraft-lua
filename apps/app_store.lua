-- Stable App Store for CC:Tweaked / ComputerCraft
-- Features: Install / Update / Delete / Refresh
-- Supports subdirectories under /apps (e.g. games/dodge.lua)
-- Uses http.get for robust downloads + atomic replace (temp file then move)

local REPO_USER = "Ace-2778"
local REPO_NAME = "Minecraft-lua"
local BRANCH    = "main"

local APPS_DIR  = shell.resolve("apps")
local INDEX_URL = ("https://raw.githubusercontent.com/%s/%s/%s/apps/index.txt")
  :format(REPO_USER, REPO_NAME, BRANCH)

local function remoteUrl(relPath)
  return ("https://raw.githubusercontent.com/%s/%s/%s/apps/%s")
    :format(REPO_USER, REPO_NAME, BRANCH, relPath)
end

if not http then
  error("HTTP is disabled. Enable it in CC:Tweaked config to use App Store.")
end

if not fs.exists(APPS_DIR) then fs.makeDir(APPS_DIR) end

-- ---------- Helpers ----------
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function ensureDir(path)
  if path == "" or path == "." or fs.exists(path) then return end
  local parent = fs.getDir(path)
  if parent and parent ~= "" and parent ~= "." then ensureDir(parent) end
  if not fs.exists(path) then fs.makeDir(path) end
end

local function ensureParentDirs(filePath)
  local parent = fs.getDir(filePath)
  if parent and parent ~= "" and parent ~= "." then ensureDir(parent) end
end

local function localPath(relPath)
  return fs.combine(APPS_DIR, relPath)
end

local function existsLocal(relPath)
  return fs.exists(localPath(relPath))
end

local function deleteLocal(relPath)
  local p = localPath(relPath)
  if fs.exists(p) then
    fs.delete(p)
    return true
  end
  return false
end

-- Robust download: http.get -> write file
-- Returns: ok(boolean), err(string)
local function downloadUrlToFile(url, dst)
  local res, err = http.get(url, { ["User-Agent"] = "CCT-AppStore" })
  if not res then
    return false, ("http.get failed: " .. tostring(err))
  end

  local code = res.getResponseCode and res.getResponseCode() or 200
  if code ~= 200 then
    local body = res.readAll() or ""
    res.close()
    return false, ("HTTP " .. tostring(code) .. " " .. (body:sub(1, 60)))
  end

  local data = res.readAll()
  res.close()

  if not data or #data == 0 then
    return false, "Empty response"
  end

  ensureParentDirs(dst)

  local h = fs.open(dst, "wb")
  if not h then
    return false, "Cannot open dst for write: " .. dst
  end
  h.write(data)
  h.close()
  return true, nil
end

-- Atomic install/update:
-- download to temp, only replace on success
local function atomicDownload(relPath)
  local url = remoteUrl(relPath)
  local dst = localPath(relPath)
  local tmp = dst .. ".tmp"

  -- download to tmp first
  if fs.exists(tmp) then fs.delete(tmp) end
  local ok, err = downloadUrlToFile(url, tmp)
  if not ok then
    if fs.exists(tmp) then fs.delete(tmp) end
    return false, err
  end

  -- replace
  if fs.exists(dst) then fs.delete(dst) end
  fs.move(tmp, dst)
  return true, nil
end

-- ---------- Fetch remote index ----------
local function fetchIndex()
  local ok, errOrTxt = pcall(function()
    local res, err = http.get(INDEX_URL, { ["User-Agent"] = "CCT-AppStore" })
    if not res then return nil, ("http.get failed: " .. tostring(err)) end
    local code = res.getResponseCode and res.getResponseCode() or 200
    local txt = res.readAll() or ""
    res.close()
    if code ~= 200 then return nil, ("HTTP " .. tostring(code) .. " " .. txt:sub(1, 60)) end
    if txt == "" then return nil, "Index empty" end
    return txt, nil
  end)

  if not ok then
    return nil, "fetchIndex crash: " .. tostring(errOrTxt)
  end

  local txt, err = errOrTxt[1], errOrTxt[2]
  if not txt then return nil, err end
  return txt, nil
end

local function parseIndex(txt)
  local list = {}
  for line in txt:gmatch("[^\r\n]+") do
    line = trim(line)
    if line ~= "" and not line:match("^#") then
      line = line:gsub("^apps/", "")
      table.insert(list, line)
    end
  end
  table.sort(list)
  return list
end

-- ---------- UI ----------
local w, h = term.getSize()

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function clear(bg)
  term.setBackgroundColor(bg or colors.black)
  term.clear()
  term.setCursorPos(1,1)
end

local function drawBox(x1,y1,x2,y2,bg)
  term.setBackgroundColor(bg or colors.gray)
  for y=y1,y2 do
    term.setCursorPos(x1,y)
    term.write(string.rep(" ", x2-x1+1))
  end
end

local function centerText(y, text, fg, bg)
  if bg then term.setBackgroundColor(bg) end
  if fg then term.setTextColor(fg) end
  local x = math.floor((w - #text)/2) + 1
  term.setCursorPos(x, y)
  term.write(text)
end

local function writeAt(x,y,text,fg,bg)
  if bg then term.setBackgroundColor(bg) end
  if fg then term.setTextColor(fg) end
  term.setCursorPos(x,y)
  term.write(text)
end

local function button(x,y,label,enabled)
  local bw = #label + 2
  term.setCursorPos(x,y)
  term.setBackgroundColor(enabled and colors.lime or colors.gray)
  term.setTextColor(colors.black)
  term.write(" "..label.." ")
  return bw
end

local function inside(px,py,x,y,bw,bh)
  return px>=x and px<x+bw and py>=y and py<y+bh
end

local statusMsg = ""
local remoteApps = {}
local selected = 1
local scroll = 0

local listX1 = 2
local listY1 = 6
local listX2 = math.floor(w*0.62)
local listH  = h - 8
if listH < 5 then listH = 5 end
local rightX  = listX2 + 2

local function setStatus(msg) statusMsg = msg or "" end

local function drawUI()
  clear(colors.black)

  drawBox(1,1,w,3,colors.blue)
  centerText(2,"🛒 App Store (Stable)",colors.white,colors.blue)

  writeAt(2,4,"Local: "..APPS_DIR.."  |  Remote index: index.txt",colors.yellow,colors.black)

  drawBox(1,5,listX2+1,h-2,colors.black)

  local count = #remoteApps
  if count == 0 then
    writeAt(2,6,"(No apps loaded. Click Refresh.)",colors.lightGray,colors.black)
  end

  local maxScroll = math.max(0, count - listH)
  scroll = clamp(scroll, 0, maxScroll)
  selected = clamp(selected, 1, math.max(1, count))

  for i=1,listH do
    local idx = i + scroll
    local y = listY1 + i - 1
    local rel = remoteApps[idx] or ""
    local installed = rel ~= "" and existsLocal(rel)

    local lineW = (listX2 - listX1 + 1)
    local show = rel
    if #show > lineW - 12 then
      show = show:sub(1, lineW - 15) .. "..."
    end

    if idx == selected then
      term.setBackgroundColor(colors.gray)
      term.setTextColor(colors.black)
    else
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
    end

    term.setCursorPos(listX1,y)
    term.write(string.rep(" ", lineW))
    term.setCursorPos(listX1,y)

    if rel ~= "" then
      term.write(show)
      local tag = installed and "[Installed]" or "[Remote]"
      term.setCursorPos(listX2 - #tag + 1, y)
      term.setTextColor(installed and colors.lime or colors.lightGray)
      term.write(tag)
    end
  end

  drawBox(rightX,4,w,h-2,colors.black)
  local cur = remoteApps[selected]
  local installed = cur and existsLocal(cur)

  writeAt(rightX,5,"Selected:",colors.cyan,colors.black)
  writeAt(rightX,6,cur or "(none)",colors.white,colors.black)

  writeAt(rightX,8,"Actions:",colors.cyan,colors.black)
  local bx = rightX
  local by = 10

  local canInstall = cur ~= nil and not installed
  local canUpdate  = cur ~= nil and installed
  local canDelete  = cur ~= nil and installed

  button(bx, by,   "Install", canInstall)
  button(bx, by+2, "Update",  canUpdate)
  button(bx, by+4, "Delete",  canDelete)
  button(bx, by+6, "Refresh", true)

  drawBox(1,h-1,w,h-1,colors.gray)
  writeAt(2,h-1,statusMsg,colors.black,colors.gray)
  writeAt(w-16,h-1,"Q:Quit",colors.black,colors.gray)
end

local function refreshRemote()
  setStatus("Fetching app index...")
  drawUI()

  local txt, err = fetchIndex()
  if not txt then
    remoteApps = {}
    selected, scroll = 1, 0
    setStatus("Index fetch failed: "..tostring(err))
    return
  end

  remoteApps = parseIndex(txt)
  selected, scroll = 1, 0
  setStatus("Loaded "..tostring(#remoteApps).." app(s).")
end

local function doInstall()
  local app = remoteApps[selected]
  if not app then setStatus("No app selected.") return end
  if existsLocal(app) then setStatus("Already installed.") return end

  setStatus("Installing "..app.." ...")
  drawUI()

  local ok, err = atomicDownload(app)
  if ok then
    setStatus("Installed: "..app)
  else
    setStatus("Install failed: "..tostring(err))
  end
end

local function doUpdate()
  local app = remoteApps[selected]
  if not app then setStatus("No app selected.") return end
  if not existsLocal(app) then setStatus("Not installed.") return end

  setStatus("Updating "..app.." ...")
  drawUI()

  local ok, err = atomicDownload(app)
  if ok then
    setStatus("Updated: "..app)
  else
    setStatus("Update failed: "..tostring(err))
  end
end

local function doDelete()
  local app = remoteApps[selected]
  if not app then setStatus("No app selected.") return end
  if not existsLocal(app) then setStatus("Not installed.") return end

  setStatus("Deleting "..app.." ...")
  drawUI()

  deleteLocal(app)
  setStatus("Deleted: "..app)
end

-- ---------- Main ----------
refreshRemote()

while true do
  drawUI()
  local e = { os.pullEvent() }
  local ev = e[1]

  if ev == "term_resize" then
    w,h = term.getSize()
    listX2 = math.floor(w*0.62)
    listH = h - 8
    if listH < 5 then listH = 5 end
    rightX = listX2 + 2

  elseif ev == "mouse_scroll" then
    scroll = scroll + e[2]

  elseif ev == "mouse_click" then
    local x, y = e[3], e[4]

    if x >= listX1 and x <= listX2 and y >= listY1 and y < listY1 + listH then
      local idx = (y - listY1 + 1) + scroll
      if remoteApps[idx] then selected = idx end
    end

    local bx = rightX
    local by = 10
    local cur = remoteApps[selected]
    local installed = cur and existsLocal(cur)

    local canInstall = cur ~= nil and not installed
    local canUpdate  = cur ~= nil and installed
    local canDelete  = cur ~= nil and installed

    local wInstall = #"Install" + 2
    local wUpdate  = #"Update" + 2
    local wDelete  = #"Delete" + 2
    local wRefresh = #"Refresh" + 2

    if inside(x,y,bx,by,wInstall,1) and canInstall then doInstall() end
    if inside(x,y,bx,by+2,wUpdate,1) and canUpdate then doUpdate() end
    if inside(x,y,bx,by+4,wDelete,1) and canDelete then doDelete() end
    if inside(x,y,bx,by+6,wRefresh,1) then refreshRemote() end

  elseif ev == "key" then
    local k = e[2]
    if k == keys.q then
      clear(colors.black)
      break
    elseif k == keys.up then
      selected = clamp(selected - 1, 1, math.max(1, #remoteApps))
      if selected < scroll + 1 then scroll = scroll - 1 end
    elseif k == keys.down then
      selected = clamp(selected + 1, 1, math.max(1, #remoteApps))
      if selected > scroll + listH then scroll = scroll + 1 end
    end
  end
end
