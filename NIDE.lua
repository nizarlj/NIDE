local fs = require("filesystem")
local keyboard = require("keyboard") 
local shell = require("shell")
local term = require("term")
local text = require("text")
local unicode = require("unicode")
local internet = require("internet")

if not term.isAvailable() then
  return
end

-- color palette 
local panelColor = 0x2D2D2D
local editorColor = 0x0F0F0F
local lineNumberColor = 0x858585
local editorColorHighlighted = 0x525252
local lineNumberColorHighlighted = 0xC9C9C9
local textColor = 0xC8C8C8
local statusBarColor = 0x007ACC

local parentDirectoryColor = 0xFF3838
local folderColor = 0xF9FF85
local fileColor = 0x85ACFF

local keywordColor = 0xC586C0
local builtinColor = 0xFCFC9A
local stringColor = 0xDB3D3D
local commentColor = 0x698A35
local operatorColor = 0xFFFFFF
local valueColor = 0x569CD6

local gpu = term.gpu()

-- syntax highlighting groups
local keywords = {
  "break",
  "do",
  "else",
  "for",
  "if",
  "elseif",
  "return",
  "then",
  "repeat",
  "while",
  "until",
  "end",
  "function",
  "in",
  "and",
  "or",
  "not"
}

local builtins = {
  "assert",
  "collectgarbage",
  "dofile",
  "error",
  "getfenv",
  "getmetatable",
  "ipairs",
  "loadfile",
  "loadstring",
  "module",
  "next",
  "pairs",
  "pcall",
  "print",
  "rawequal",
  "rawget",
  "rawset",
  "require",
  "select",
  "setfenv",
  "setmetatable",
  "tonumber",
  "tostring",
  "type",
  "unpack",
  "xpcall"
}

local operators = {
  "+",
  "-",
  "*",
  "/",
  "%",
  "#",
  "^",
  "=",
  "==",
  "~=",
  "<",
  "<=",
  ">",
  ">=",
  ".."
}

local values = {
	"false",
	"nil",
	"true",
	"_G",
  "_VERSION",
  "local"
}

local syntax = {
  keywords,
  builtins,
  operators,
  values
}

for index, syntaxBundle in pairs(syntax) do
  for index, element in pairs(syntaxBundle) do
    syntaxBundle[element] = true
  end
end

-- patterns to match for syntax-highlighting
local patterns = {
  {"^%-%-%[%[.-%]%]", commentColor},
  {"^%-%-.*", commentColor},
  {"^\"\"", stringColor},
  {"^\".-[^\\]\"", stringColor},
  {"^\'\'", stringColor},
  {"^\'.-[^\\]\'", stringColor},
  {"^%[%[.-%]%]", stringColor},
  {"^[%w_%+%-%%%#%*%/%^%=%~%<%>%.]+", function(text)
    if values[text] ~= nil or tonumber(text) then
      local match = text:match('^0x%x%x%x%x%x%x$')

      if match then
        -- local luminosity = 0.2126 * tonumber('0x' .. text:sub(3, 4)) + 0.7152 * tonumber('0x' .. text:sub(5, 6)) + 0.0722 * tonumber('0x' .. text:sub(7, 8))
        -- if luminosity > 20 then
        --   return 0x000000, tonumber(text)
        -- else
        --   return 0xffffff, tonumber(text)
        -- end
        return tonumber(match)
      else
        return valueColor
      end
    elseif keywords[text] then
      return keywordColor
    elseif operators[text] then
      return operatorColor
    elseif builtins[text] then
      return builtinColor
    end
    return textColor
  end
  }
}

-- config including all keybinds
local function loadConfig()
  -- Try to load user settings.
  local env = {}
  local config = loadfile("/etc/NIDE.cfg", nil, env)
  if config then
    pcall(config)
  end
  -- Fill in defaults.
  -- env.keybinds = env.keybinds or {}
  env.keybinds = {
    left = {{"left"}},
    right = {{"right"}},
    up = {{"up"}},
    down = {{"down"}},
    home = {{"home"}},
    eol = {{"end"}},
    pageUp = {{"pageUp"}},
    pageDown = {{"pageDown"}},

    toggleExplorerPanel = {{"control", "p"}},

    backspace = {{"back"}, {"shift", "back"}},
    delete = {{"delete"}},
    deleteLine = {{"control", "delete"}, {"shift", "delete"}},
    newline = {{"enter"}},
    toggleSyntaxHighlighting = {{"control", "h"}},

    quit = {{"control", "q"}},
    refresh = {{"control", "r"}},

    save = {{"control", "s"}},
    close = {{"control", "w"}},
    find = {{"control", "f"}},
    findnext = {{"control", "g"}, {"f3"}},
    cut = {{"control", "k"}},
    uncut = {{"control", "u"}},
    newFile = {{"control", "n"}},
  }
  -- Generate config file if it didn't exist.
  if not config then
    local root = fs.get("/")
    if root and not root.isReadOnly() then
      fs.makeDirectory("/etc")
      local f = io.open("/etc/NIDE.cfg", "w")
      if f then
        local serialization = require("serialization")
        for k, v in pairs(env) do
          f:write(k.."="..tostring(serialization.serialize(v, math.huge)).."\n")
        end
        f:close()
      end
    end
  end
  return env
end


local running = true
local buffer = {}
local colorBuffer = {}
local scrollX, scrollY = 1, 0
local config = loadConfig()
local currentDirectory = "/"
local openFiles = {nil}
local navbarButtons = {}
local screen = "editor"
local explorerItemsAmountHorizontal = 5
local explorerItemsAmountVertical = 4
local applySyntaxHighlighting = true

local w, h = gpu.getResolution()

local panelWidth = math.floor(w/10)
local panelHeight = math.floor(h/24)
local explorerPanel = false
local explorerItemWidth = math.floor((w - 2) / explorerItemsAmountHorizontal)
local explorerItemHeight = math.floor((h - panelHeight - 2) / explorerItemsAmountVertical)

local lineNumberOffset = 7

local xOffset = lineNumberOffset + 1
local yOffset = panelHeight


-- concatinate two tables
local function tableConcat(t1,t2)
  for i=1,#t2 do
      t1[#t1+1] = t2[i]
  end
  return t1
end


-- split string by seperator
local function split (inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t={}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end


-- serialize a table
local function serialize(t)
    local s = {""}
    for i=1,#t do
        s[#s+1] = "{"
        for j=1,#t[i] do
        s[#s+1] = t[i][j]
        s[#s+1] = ","
        end
        s[#s+1] = "},"
    end
    s = table.concat(s)
    return s
end

-- return a table with all the directories and files given a certain path
local function sortedDir(path)
    local dirs = {fs.path(path)}
    local files = {}
  
    for element in fs.list(path) do
      if fs.isDirectory(element) then
        table.insert(dirs, path .. element)
      else
        table.insert(files, path .. element)
      end
    end
    return tableConcat(dirs, files)
end


local function addButton(options)
    options["text"]            = options["text"] or "undefined"
    options["dropdown"]        = options["dropdown"] or {}
    options["callback"]        = options["callback"] or nil
    options["alignment"]       = options["alignment"] or "left"
    options["foregroundColor"] = options["foregroundColor"] or textColor
    options["backgroundColor"] = options["backgroundColor"] or panelColor


    table.insert(navbarButtons, options)
end

-- draw the explorer / file system
local function drawNavbar()
    -- panels
    gpu.setBackground(panelColor)
    gpu.fill(1, 1, w, panelHeight, " ")

    gpu.setForeground(textColor)
    local buttonXLeft = 1
    local buttonXRight = w + 1

    for _, button in pairs(navbarButtons) do
        gpu.setForeground(button["foregroundColor"])
        gpu.setBackground(button["backgroundColor"])

        if button["alignment"] == "left" then
            gpu.set(buttonXLeft, 1, button["text"])
            buttonXLeft = buttonXLeft + unicode.len(button["text"]) + 1
        else
            buttonXRight = buttonXRight - unicode.len(button["text"])
            gpu.set(buttonXRight, 1, button["text"])
            buttonXRight = buttonXRight - 1
        end
    end

    gpu.setForeground(textColor)
    gpu.setBackground(editorColor)
end


local function drawExplorer()
    gpu.setBackground(editorColor)
    gpu.fill(1, panelHeight + 1, w, h, " ")

    gpu.setBackground(panelColor)
    gpu.fill(2, panelHeight + 2, w - 2, h - panelHeight - 2, " ")

    gpu.setForeground(textColor)

    local dirs = sortedDir(currentDirectory)
    for index = 1, math.min(#dirs, explorerItemsAmountHorizontal * explorerItemsAmountVertical + 1) do
        
        if index == 1 then
            gpu.setBackground(parentDirectoryColor)
        elseif fs.isDirectory(dirs[index]) then
            gpu.setBackground(folderColor)
        else 
            gpu.setBackground(fileColor)
        end

        local x = 1 + explorerItemWidth * ((index - 1) % explorerItemsAmountHorizontal)
        local y = panelHeight + 3 + explorerItemHeight * ((math.floor((index - 1) / explorerItemsAmountHorizontal)))
        gpu.fill(x + math.floor(explorerItemWidth / 4), y, explorerItemWidth - math.floor(explorerItemWidth / 4), explorerItemHeight - math.floor(explorerItemHeight / 4), " ")

        local dirName = dirs[index]:sub(#currentDirectory + 1)

        for i = 1, math.floor(#dirName / (explorerItemWidth - math.floor(explorerItemWidth / 4 + 2))) + 1 do
            gpu.set(x + math.floor(explorerItemWidth / 4) + 1, y + i, dirName:sub((i - 1) * (explorerItemWidth - math.floor(explorerItemWidth / 4 + 2)) + 1, i * (explorerItemWidth - math.floor(explorerItemWidth / 4 + 2))))
        end
    
    end

    gpu.setBackground(editorColor)
end


-- local function drawPanels(path)
--     -- panels
--     gpu.setBackground(panelColor)
--     gpu.fill(1, 1, w, panelHeight, " ")

--     if explorerPanel then
--         gpu.fill(1, 1, panelWidth, h, " ")
    
--         -- draw parent directory, directories and finally files on top of the panels
--         path = (path or currentDirectory)
--         local dirs = sortedDir(path)
--         for index = 1, #dirs do
--         if index == 1 then
--             gpu.setForeground(parentDirectoryColor)
--             gpu.set(2, yOffset + index * 2 - 1, dirs[index]:sub(1, panelWidth - 2))
--         else
--             if fs.isDirectory(dirs[index]) then
--             gpu.setForeground(folderColor)
--             else 
--             gpu.setForeground(fileColor)
--             end
--             gpu.set(2, yOffset + index * 2 - 1, dirs[index]:sub(#path + 1):sub(1, panelWidth - 2))
--         end
--         end
--     end
    
--     gpu.setForeground(textColor)
--     gpu.setBackground(editorColor)
-- end


-- local function checkExplorer(x, y)
--     local dirs = sortedDir(currentDirectory)
--     x = tonumber(x)
--     y = tonumber(y)
--     if x < panelWidth and y > yOffset and y < yOffset + #dirs * 2 then
--       return dirs[(y - math.floor(yOffset) + 1) / 2]
--     end
--     return false
-- end


local function getArea()
    local x, y, w, h = term.getGlobalArea()
    return x, y, w, h - 1
end


-- draws status bar
local function drawStatusBar(text)
    gpu.setBackground(statusBarColor)
    gpu.setForeground(textColor)
    gpu.fill(1, h, w, 1, " ")
    gpu.set(2, h, text .. string.rep(" ", w - unicode.len(text)))
    gpu.setBackground(editorColor)
end


-- returns cursor position in "editor space" rather than "screen space"
local function getCursor()
    local cx, cy = term.getCursor()
    return cx + scrollX - xOffset, cy + scrollY - yOffset
end


local function setCursor(ncx, ncy)
    local bcx, bcy = getCursor()
    bcx = bcx - scrollX
    bcy = bcy - scrollY

    local ncx = xOffset + math.max(1, math.min(ncx - scrollX, w - xOffset - 1))
    local ncy = yOffset + math.max(1, math.min(ncy - scrollY, h - yOffset))

    local cx, cy = ncx - xOffset + scrollX - 1, ncy - yOffset + scrollY

    -- redraw character which the cursor was on because the cursor turns the color of a character back to while
    if colorBuffer[cy] and applySyntaxHighlighting then
        for index, text in pairs(colorBuffer[cy]) do
            if index > 1 and text["start"] >= scrollX then
                if text["end"] >= bcx then
                    gpu.setForeground(text["color"])
                    gpu.set(bcx + xOffset, bcy + yOffset, string.sub(colorBuffer[cy][1], bcx, bcx))
                    break
                end
            end
        end
    end

    term.setCursor(ncx, ncy)
    drawStatusBar("cx: " .. cx .. ",cy: " .. cy .. ", #buffer: " .. #buffer)
end


-- returns line based on mouse position or number given as parameter
local function getLine(lineNr)
    local _, cy = getCursor()
    local lineNr = (lineNr or cy)
    return (buffer[lineNr] or "")
end


local function syntaxHighlight(lineNr)
    local _, cy = getCursor()
    local lineNr = (lineNr or cy)
    local line = getLine(lineNr)
  
    if colorBuffer[lineNr] == nil then colorBuffer[lineNr] = {line} end
  
    if colorBuffer[lineNr][1] ~= line or #colorBuffer[lineNr] == 1 then
      colorBuffer[lineNr] = {line}
      local len = 0
      for char = 1, line:len() do
        if char > len then
          local patternFound = false
  
          for pat = 1, #patterns do
            local data = patterns[pat]
            local foundb, founde = line:find(data[1], char)
  
            if foundb ~= nil then
              local text = line:sub(foundb, founde)
              local color = data[2]
              local bgcolor = data[3]
  
              if type(color) == 'function' then
                color, bgcolor = color(text)
              end
  
              table.insert(colorBuffer[lineNr], {["start"] = foundb, ["end"] = founde, ["color"] = color})
              len = len + (founde - foundb + 1)
  
              patternFound = true
  
              break
            end
          end
  
          if not patternFound then
            if colorBuffer[lineNr][#colorBuffer[lineNr]]["color"] == textColor then
              colorBuffer[lineNr][#colorBuffer[lineNr]]["end"] = colorBuffer[lineNr][#colorBuffer[lineNr]]["end"] + 1
            else
              table.insert(colorBuffer[lineNr], {["start"] = char, ["end"] = char, ["color"] = textColor})
            end
            len = len + 1
          end
        end
      end
    end
end


local function drawLine(lineNr)
    local _, _, w, _ = getArea()
    local _, cy = getCursor()
    local lineNr = lineNr or cy
  
    local line = getLine(lineNr)
  
    -- (cy == lineNr) and editorColorHighlighted or editorColor
    gpu.setBackground(editorColor)
  
    -- (cy == lineNr) and lineNumberColorHighlighted or lineNumberColor
    gpu.setForeground(lineNumberColor)
    gpu.set(1, lineNr - scrollY + yOffset, string.rep(" ", lineNumberOffset - unicode.len(lineNr)) .. lineNr .. " ")
  
    if applySyntaxHighlighting then
      syntaxHighlight(lineNr)
      for index, text in pairs(colorBuffer[lineNr]) do
        if index > 1 and text["start"] >= scrollX then
          gpu.setForeground(text["color"])
          gpu.set(xOffset + text["start"], lineNr - scrollY + yOffset, (line):sub(text["start"], text["end"]))
        end
      end
    else
      gpu.setForeground(textColor)
      gpu.set(xOffset + 1, lineNr - scrollY + yOffset, (line):sub(scrollX))
    end
    gpu.set(xOffset + #line:sub(scrollX) + 1, lineNr - scrollY + yOffset, string.rep(" ", w))
end


-- draws whole screen
local function drawScreen()
    local _, cy = getCursor()

    gpu.setBackground(editorColor)
    gpu.fill(1, yOffset + 1, w, h, " ")

    for i = 1, math.min(h - yOffset - 1, #buffer) do
        drawLine(i + scrollY)
    end
    drawStatusBar("Screen Redrawn")
end


-- draw screen more efficiently by moving part of screen instead of redrawing whole screen
local function scrollDraw(dir)
    local dir = (dir or "down")
    local _, cy = getCursor()
  
    if dir == "down" then
      gpu.copy(1, panelHeight + 2, w, h - yOffset, 0, -1)
      drawLine()
    elseif dir == "up" then
      gpu.copy(1, panelHeight + 1, w, h - yOffset, 0, 1)
      drawLine(cy)
    end
end

-- move cursor to the left
local function left(n)
    n = (n or 1)
    local cx, cy = getCursor()

    if cx - scrollX == 1 and scrollX > 1 then
        scrollX = scrollX - 1
        drawScreen()
    end
    setCursor(cx - n, cy)
end


-- move cursor up
local function up(n)
    n = (n or 1)
    local cx, cy = getCursor()
    local nextX = 1

    if cy - scrollY == 1 and scrollY > 0 then
        scrollY = scrollY - 1
        scrollDraw("up")
    end

    -- if cx > #getLine(cy - 1) then
        -- nextX = 
    -- end
    
    if cy - scrollY > 1 then
        setCursor(nextX, cy - n)
    end
end
  

-- move cursor down
local function down(n)
    n = (n or 1)
    local cx, cy = getCursor()
    local nextX = 1

    if cy - scrollY == h - yOffset - 1 and cy < #buffer then
        scrollY = scrollY + 1
        scrollDraw("down")
    end

    -- if cx > #getLine(cy + 1) then
        -- nextX = 
    -- end
  
    if cy < #buffer then
        setCursor(nextX, cy + n)
    end
end


-- move cursor to the right
local function right(n, insert)
    n = (n or 1)
    local cx, cy = getCursor()
    local line = getLine()
    local insert = insert or false

    if cx - scrollX == w - xOffset - 1 and (cx - 2 < #line or insert) then
        scrollX = scrollX + 1
        drawScreen()
    end

    if cx - 2 < #line then
        setCursor(cx + n, cy)
    end
end


local function insert(value)
    if not value or unicode.len(value) < 1 then
        return
    end
    local cx, cy = getCursor()
    local line = getLine()
    buffer[cy] = line:sub(1, cx - 2) .. value .. line:sub(cx - 1, unicode.len(line))
    right(unicode.len(value), true)
    drawLine()
end


local function quit()
    gpu.setBackground(0x000000)
    term.clear()
    running = false
end

local function save() 
    local f, reason = io.open(openFiles[1], "w")
    if f then
        local chars, firstLine = 0, true
        for _, line in ipairs(buffer) do
            if not firstLine then
                line = "\n" .. line
            end
            firstLine = false
            f:write(line)
            chars = chars + unicode.len(line)
        end
        f:close()
        drawStatusBar("File Saved")
    end
end


local function drawPopup(text) 
    local text = text or "undefined"
    screen = "popup"

    -- local popUpX
end

-- keybindings
local keyBindHandlers = {
    up = up,
    down = down,
    left = left,
    right = right,
    quit = quit,
    toggleExplorerPanel = function()
        explorerPanel = not explorerPanel
        if explorerPanel == true then
            xOffset = xOffset + panelWidth
            drawPanels()
        else
            xOffset = xOffset - panelWidth
            gpu.setBackground(editorColor)
            gpu.fill(1, panelHeight + 1, panelWidth, h, " ")
        end
    end,
    -- refresh = function()
    --   shell.execute("NIDELOADER.lua")
    --   shell.execute("NIDE.lua")
    --   term.clear()
    --   running = false
    -- end,
    newline = function()
        local cx, cy = getCursor()
        local line = getLine()
        table.insert(buffer, cy, line:sub(1, cx - 2))
        buffer[cy + 1] = line:sub(cx - 1)
        drawScreen()
        down()
    end,
    backspace = function()
        local cx, cy = getCursor()
        if cx - scrollX == 1 then
            if cy ~= 1 then
                setCursor(#getLine(cy - 1) + 1, cy - 1)
                buffer[cy - 1] = buffer[cy - 1] .. buffer[cy]
                table.remove(buffer, cy)
                drawScreen()
            end
        else
            local line = getLine()
            left()
            buffer[cy] = line:sub(1, cx - 3) .. line:sub(cx - 1)
            drawLine()
        end
    end,
    save = function()
        if openFiles[1] ~= nil then
            save()
        else
            drawPopup()
        end
    end,
    toggleSyntaxHighlighting = function()
      applySyntaxHighlighting = not applySyntaxHighlighting
      drawScreen()
    end
}


-- returns the keybindhandler
local function getKeyBindHandler(code)
    if type(config.keybinds) ~= "table" then return end
    -- Look for matches, prefer more 'precise' keybinds, e.g. prefer
    -- ctrl+del over del.
    local result, resultName, resultWeight = nil, nil, 0
    for command, keybinds in pairs(config.keybinds) do
      if type(keybinds) == "table" and keyBindHandlers[command] then
        for _, keybind in ipairs(keybinds) do
          if type(keybind) == "table" then
            local alt, control, shift, key = false, false, false, nil
            for _, value in ipairs(keybind) do
              if value == "alt" then alt = true
              elseif value == "control" then control = true
              elseif value == "shift" then shift = true
              else key = value end
            end
            local keyboardAddress = term.keyboard()
            if (alt     == not not keyboard.isAltDown(keyboardAddress)) and
               (control == not not keyboard.isControlDown(keyboardAddress)) and
               (shift   == not not keyboard.isShiftDown(keyboardAddress)) and
               code == keyboard.keys[key] and
               #keybind > resultWeight
            then
              resultWeight = #keybind
              resultName = command
              result = keyBindHandlers[command]
            end
          end
        end
      end
    end
    return result, resultName
  end


-- handle keypress
local function onKeyDown(char, code)
    local handler = getKeyBindHandler(code)
    if handler then
      handler()
    elseif screen == "editor" then
      if not keyboard.isControl(char) then
        insert(unicode.char(char))
      elseif unicode.char(char) == "\t" then
        insert("  ")
      end
    end
end


local function loadFile(fileName)
    local fileName = fileName or openFiles[1]
    scrollX, scrollY = 1, 0
    setCursor(1, 1)

    if fileName == nil then
        buffer = {""}
        drawLine()
        return true
    end

    local f = io.open(fileName)
    if f then
        gpu.setBackground(editorColor)
        gpu.fill(1, yOffset + 1, w, h - yOffset, " ")
        buffer = {}

        for fline in f:lines() do
            table.insert(buffer, fline)
        end
        f:close()

        if #buffer == 0 then 
            table.insert(buffer, "") 
            drawLine()
            return true
        end

        for i = yOffset + 1, #buffer do
            syntaxHighlight(i)
        end
        drawScreen()
        return true
    end
    return false
end
  

local function handleTouch(touchX, touchY)
    touchX = tonumber(touchX)
    touchY = tonumber(touchY)

    local buttonXLeft = 1
    local buttonXRight = w + 1

    for _, button in pairs(navbarButtons) do
        if button["alignment"] == "left" then
            if touchX >= buttonXLeft and touchX <= buttonXLeft + unicode.len(button["text"]) and touchY >= 1 and touchY <= panelHeight then
                if #button["dropdown"] == 0 and button["callback"] ~= nil then
                    local callback = button["callback"]
                    callback('Jason')
                end
                break
            else
                buttonXLeft = buttonXLeft + unicode.len(button["text"]) + 1
            end
        else
            if touchX >= buttonXRight - unicode.len(button["text"]) and touchX <= buttonXRight and touchY >= 1 and touchY <= panelHeight then
                if #button["dropdown"] == 0 and button["callback"] ~= nil then
                    local callback = button["callback"]
                    callback('Jason')
                end
                break
            else
                buttonXRight = buttonXRight - unicode.len(button["text"]) - 1
            end
        end
    end

    if screen == "explorer" then
        local dirs = sortedDir(currentDirectory)
        for index = 1, math.min(#dirs, explorerItemsAmountHorizontal * explorerItemsAmountVertical + 1) do
            local x = 1 + explorerItemWidth * ((index - 1) % explorerItemsAmountHorizontal)
            local y = panelHeight + 3 + explorerItemHeight * ((math.floor((index - 1) / explorerItemsAmountHorizontal)))
            if touchX > x + math.floor(explorerItemWidth / 4) and touchX < x + explorerItemWidth - math.floor(explorerItemWidth / 4) and touchY > y and touchY < y + explorerItemHeight - math.floor(explorerItemHeight / 4) then
                if fs.isDirectory(dirs[index]) then
                    currentDirectory = dirs[index]
                    drawExplorer()
                else
                    screen = "editor"
                    openFiles[1] = dirs[index]
                    loadFile(dirs[index])
                end
            end    
        end
    end

    return false
end

addButton({["text"] = "Explorer", ["callback"] = function() 
    screen = 'explorer' 
    term.setCursorBlink(false)
    -- setCursor(1, panelHeight + 1)
    term.setCursor(1, yOffset + 1)
    drawExplorer()
end})

addButton({["text"] = "X", ["alignment"] = "right", ["foregroundColor"] = 0xFFFFFF, ["backgroundColor"] = 0xFF0000,["callback"] = quit})

gpu.setBackground(editorColor)
term.clear()
term.setCursorBlink(true)

if explorerPanel then
    xOffset = xOffset + panelWidth
end

drawNavbar()
term.setCursor(xOffset + 1, yOffset + 1)
loadFile()

-- main loop
while running do
    local event, address, arg1, arg2, arg3 = term.pull()
    if event == "key_down" then
        onKeyDown(arg1, arg2)
    elseif event == "scroll" then
    --   onScroll(arg3)
    elseif event == "touch" or event == "drag" then
        handleTouch(arg1, arg2)
    end
  end