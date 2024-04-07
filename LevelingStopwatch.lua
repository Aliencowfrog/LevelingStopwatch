-- Specify addon name, which *must* be identical to addon folder
-- name (and therefore also identical to TOC file basename without
-- extension)
local addonName = "LevelingStopwatch"

-- Specify name of persistent global variable, which *must* be
-- identical to the name defined inside the TOC file
local savedVariable = "LevelingStopwatch"

-- Initialize a few variables
local debug = false
local frame = CreateFrame("Frame", nil, UIParent)
local textColumns = {}
local settings = nil
local addonLoaded = false
local events = {}
local currentLevel = 0
local levelTimes = nil
local levelLabels = nil
local previousLevelTotalTime = nil
local currentLevelTimeOffset = nil
local textLevelLabels = nil
local textLevelTotalTimes = nil
local textLevelTimes = nil
local timeLastUpdate = 0

-- Print function for debugging
local function print(variable)
    if type(variable) == "string" or type(variable) == "number" then
        DEFAULT_CHAT_FRAME:AddMessage(variable)
    elseif type(variable) == "boolean" then
        if variable then
            print("true")
        else
            print("false")
        end
    elseif type(variable) == "nil" then
        print("nil")
    elseif type(variable) == "table" then
        for key, value in variable do
            print(key .. " -> " .. value)
        end
    else
        error("unsupported variable type")
    end
end

-- Split string into table
local function split(s, delimiter)
    local t = {}
    local n = string.len(s)
    local m = string.len(delimiter)
    local offset = 1
    for i = 1, n do
        if string.sub(s, i, i + m - 1) == delimiter then
            t[table.getn(t) + 1] = string.sub(s, offset, i - 1)
            i = i + m - 1
            offset = i + 1
        end
    end
    t[table.getn(t) + 1] = string.sub(s, offset, n)
    return t
end

-- Reverse table
local function reverse(t)
    local reversed = {}
    for i = table.getn(t), 1, -1 do
        reversed[table.getn(reversed) + 1] = t[i]
    end
    return reversed
end

-- Convert seconds to readable date
local function formatTime(seconds)
    local days = math.floor(seconds / 60 / 60 / 24)
    seconds = seconds - days * 24 * 60 * 60
    local hours = math.floor(seconds / 60 / 60)
    seconds = seconds - hours * 60 * 60
    local minutes = math.floor(seconds / 60)
    seconds = seconds - minutes * 60
    seconds = math.floor(seconds)
    return string.format(settings.formatString, days, hours, minutes, seconds)
end

-- Refresh variables if levels changed, calculate level times from
-- total timestamps and generate level labels, cache the lines for
-- the three text columns in a variable
local function refreshLevelTables()
    -- Reset variables
    levelTimes = {}
    levelLabels = {}
    previousLevelTotalTime = 0
    local expectedNextLabel = 1
    for i = 1, 59 do
        if settings.levels[i] ~= nil then
            levelTimes[i] = settings.levels[i] - previousLevelTotalTime
            previousLevelTotalTime = settings.levels[i]
        end
        if settings.levels[i] ~= nil or i == currentLevel then
            if expectedNextLabel == i then
                levelLabels[i] = "Level " .. i
            else
                levelLabels[i] = "Level " .. expectedNextLabel .. "-" .. i
            end
            expectedNextLabel = i + 1
        end
    end
    if debug then
        print("levelTimes")
        print(levelTimes)
        print("levelLabels")
        print(levelLabels)
    end
    -- Usually, we don't want to print all 59 lines for the 59 times
    -- that the time taken per level has been or will be measured, so
    -- there is an option to set the number of limes to be shown. We
    -- need to find out which levels (or level brackets) will be
    -- printed.
    local linesCount = 0
    local minLevelToPrint = 59
    for i = 59, 1, -1 do
        if linesCount >= settings.maxLines then
            break
        end
        if levelLabels[i] ~= nil then
            minLevelToPrint = i
            linesCount = linesCount + 1
        end
    end
    -- Cache the text for the columns in variables, so we don't need
    -- to generate them new every OnUpdate, but only if required
    -- (due to level-up)
    textLevelLabels = ""
    textLevelTotalTimes = ""
    textLevelTimes = ""
    for i = minLevelToPrint, 59 do
        if levelTimes[i] ~= nil then
            textLevelLabels = textLevelLabels .. levelLabels[i] .. "\n"
            textLevelTotalTimes = textLevelTotalTimes .. formatTime(settings.levels[i]) .. "\n"
            textLevelTimes = textLevelTimes .. formatTime(levelTimes[i]) .. "\n"
        end
    end
    if debug then
        print("textLevelLabels")
        print(textLevelLabels)
        print("textLevelTotalTimes")
        print(textLevelTotalTimes)
        print("textLevelTimes")
        print(textLevelTimes)
    end
    -- Force refresh, ignoring usual refreshFrequency
    timeLastUpdate = 0
end

-- UI refresh loop, which will be called by the game each time the
-- screen gets refreshed
frame:SetScript("OnUpdate", function()
    -- If addon isn't fully loaded yet, in particular if there is no
    -- guarantee that the saved persistent variable is loaded yet,
    -- then OnUpdate is not allowed to run. Not sure if this is even
    -- a possibility, but including this check anyway, just to be
    -- sure.
    if not addonLoaded then
        return
    end
    -- It's not necessary to refresh the addon with maximum FPS, so
    -- we're using a (slower) user-defined refresh frequency instead
    if GetTime() - timeLastUpdate < 1 / settings.refreshFrequency then
        return
    end
    -- Update time for next OnUpdate call
    timeLastUpdate = GetTime()
    -- We need to find out if there is new leveling information to
    -- be included into our database and subsequently shown in the
    -- overlay. This is the case if either currentLevel is still
    -- nil from initializing, or currentLevel is out of date because
    -- the actual character level has changed.
    if currentLevel ~= UnitLevel("player") then
        currentLevel = UnitLevel("player")
        currentLevelTimeOffset = nil
        refreshLevelTables()
        RequestTimePlayed()
    end
    -- Doesn't matter if data has been updated in the previous step
    -- or not, we need to update the text columns at this point, by
    -- filling them with the cached text lines
    textColumns[1]:SetText(textLevelLabels)
    textColumns[2]:SetText(textLevelTotalTimes)
    textColumns[3]:SetText(textLevelTimes)
    -- If level is still below 60, we have to add a final line which
    -- contains the currently running stopwatch
    if currentLevel < 60 then
        local currentLevelTime = "?"
        local currentLevelTotalTime = "?"
        if currentLevelTimeOffset ~= nil then
            currentLevelTime = currentLevelTimeOffset + GetTime()
            currentLevelTotalTime = previousLevelTotalTime + currentLevelTime
            currentLevelTime = formatTime(currentLevelTime)
            currentLevelTotalTime = formatTime(currentLevelTotalTime)
        end
        textColumns[1]:SetText(textLevelLabels .. levelLabels[currentLevel])
        textColumns[2]:SetText(textLevelTotalTimes .. currentLevelTotalTime)
        textColumns[3]:SetText(textLevelTimes .. currentLevelTime)
    end
    -- Reverse order of lines if user has set this option
    if settings.reverseOrder then
        for i = 1, 3 do
            local lines = split((textColumns[i]:GetText() or ""), "\n")
            textColumns[i]:SetText(table.concat(reverse(lines), "\n"))
        end
    end
    if currentLevel == 60 and settings.celebrate then
        for columnIndex = 1, 3 do
            local oldString = textColumns[columnIndex]:GetText() or ""
            local newString = ""
            for charPos = 1, string.len(oldString) do
                local color = ""
                for i = 1, 6 do
                    color = color .. string.format("%x", math.random(0, 15))
                end
                newString = newString .. "\124cff" .. color .. string.sub(oldString, charPos, charPos)
            end
            newString = newString .. "\124r"
            textColumns[columnIndex]:SetText(newString)
        end
    end
end)

-- Receiving RequestTimePlayed() information from server, which is
-- the same as the /played command in-game
function events.TIME_PLAYED_MSG()
    -- No idea where arg1 and arg2 are coming from. Seems like
    -- that's just the way the WoW Lua API works?
    local totalTimePlayed = arg1
    local timePlayedThisLevel = arg2
    -- If currentLevelTimeOffset isn't set, then we can calculate
    -- its value from the payload of the TIME_PLAYED_MSG event. When
    -- displaying the time in the text column later, we're using
    -- GetTime() to find out the difference between then and when
    -- the RequestTimePlayed() request has been received, as we're
    -- subtracting GetTime() here. Maybe it would make more sense
    -- to not subtract GetTime() from now, but use the time from
    -- when the request was sent? Doesn't seem worth implementing
    -- since the code will get more complicated with yet another
    -- variable in this module scope and the time difference seems
    -- to be only around 0.1 seconds when I measured it.
    if currentLevelTimeOffset == nil then
        currentLevelTimeOffset = timePlayedThisLevel - GetTime()
        if debug then
            print("currentLevelTimeOffset")
            print(currentLevelTimeOffset)
        end
        -- Force refresh, ignoring usual refreshFrequency
        timeLastUpdate = 0
    end
    -- Calculate the timestamp of the most recent level-up
    if currentLevel > 1 and settings.levels[currentLevel - 1] == nil then
        settings.levels[currentLevel - 1] = totalTimePlayed - timePlayedThisLevel
        refreshLevelTables()
    end
end

-- When an addon has been loaded by the game, this event fires
function events.ADDON_LOADED()
    -- Event ADDON_LOADED fires for every addon, so we need to check
    -- if the current event belongs to *this* addon
    if arg1 ~= addonName then
        return
    end
    -- No need to listen for ADDON_LOADED anymore
    frame:UnregisterEvent(event)
    -- If data was stored in SavedVariables file, it has already
    -- been loaded at this point, and we can read the settings
    local env = getfenv(1)
    if type(env[savedVariable]) ~= "table" then
        env[savedVariable] = {}
    end
    settings = env[savedVariable]
    -- Initialize default values for settings
    local defaultSettings = {}
    defaultSettings.characterName = UnitName("player")
    defaultSettings.frameAnchor = "TOPLEFT"
    defaultSettings.frameOffsetX = 20
    defaultSettings.frameOffsetY = -100
    defaultSettings.columnAnchor = "TOPRIGHT"
    defaultSettings.columnOffsetX = 20
    defaultSettings.columnOffsetY = 0
    defaultSettings.textJustifyV = "TOP"
    defaultSettings.textJustifyH = {[1] = "LEFT", [2] = "RIGHT", [3] = "RIGHT"}
    defaultSettings.fontName = ""
    defaultSettings.fontSize = 12
    defaultSettings.textColor = "ffffff"
    defaultSettings.textOpacity = 1.0
    defaultSettings.formatString = "%dd%02dh%02dm%02ds"
    defaultSettings.maxLines = 5
    defaultSettings.reverseOrder = false
    defaultSettings.refreshFrequency = 1
    defaultSettings.levels = {}
    defaultSettings.celebrate = true
    for key, value in defaultSettings do
        if settings[key] == nil then
            settings[key] = value
        end
    end
    -- Sanity check for character name
    if settings.characterName ~= UnitName("player") then
        error("Corrupted storage. This should never happen. Please reset addon settings.")
    end
    -- Continue setting up frame
    frame:SetFrameStrata("BACKGROUND")
    frame:SetWidth(1)
    frame:SetHeight(1)
    frame:ClearAllPoints()
    frame:SetPoint(settings.frameAnchor, settings.frameOffsetX, settings.frameOffsetY)
    frame:Show()
    -- Draw (empty) text columns onto frame
    local columnCount = 3
    for i = 1, columnCount do
        -- Some settings can either be one value for all columns, or
        -- a table with individual values for each column
        local columnSettings = {}
        for _, key in {"columnAnchor", "columnOffsetX", "columnOffsetY", "textJustifyV", "textJustifyH", "fontName", "fontSize", "textColor", "textOpacity"} do
            if type(settings[key]) == "table" then
                columnSettings[key] = settings[key][i]
            else
                columnSettings[key] = settings[key]
            end
        end
        textColumns[i] = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        textColumns[i]:ClearAllPoints()
        if i == 1 then
            textColumns[i]:SetPoint("TOPLEFT", frame)
        else
            textColumns[i]:SetPoint("TOPLEFT", textColumns[i - 1], columnSettings.columnAnchor, columnSettings.columnOffsetX, columnSettings.columnOffsetY)
        end
        -- To set the font name and font size in the next step, we
        -- need to explicitly specify the font name since there
        -- doesn't seem to be an option for "use default font". So
        -- if the user didn't set a custom font, we're reading the
        -- name of the default font, overwriting nil or "", which
        -- we're interpreting as "use default font".
        if columnSettings.fontName == nil or columnSettings.fontName == "" then
            columnSettings.fontName = textColumns[i]:GetFont()
        end
        textColumns[i]:SetFont(columnSettings.fontName, columnSettings.fontSize)
        -- Calculate color values
        local textColorRed = tonumber(string.sub(columnSettings.textColor, 1, 2), 16) / 255
        local textColorGreen = tonumber(string.sub(columnSettings.textColor, 3, 4), 16) / 255
        local textColorBlue = tonumber(string.sub(columnSettings.textColor, 5, 6), 16) / 255
        textColumns[i]:SetTextColor(textColorRed, textColorGreen, textColorBlue, columnSettings.textOpacity)
        textColumns[i]:SetJustifyV(columnSettings.textJustifyV)
        textColumns[i]:SetJustifyH(columnSettings.textJustifyH)
    end
    textColumns[1]:SetText("Loading...")
    -- Activate OnUpdate UI refresh loop
    addonLoaded = true
end

-- Install event listeners
for event in events do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function()
    events[event]()
end)
