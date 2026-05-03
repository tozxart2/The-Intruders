local Data = {}
local DataFunctions = {}
local Http = game:GetService("HttpService")

local function persistToFile(folderName, fileName, payload)
    return pcall(function()
        writefile(folderName .. "/" .. fileName, Http:JSONEncode(payload))
    end)
end

local function persistInstance(self)
    return persistToFile(self.FolderName, self.FileName, self.Data)
end

function Data.new(folderName, fileName, data)
    if not isfolder(folderName) then
        makefolder(folderName)
    end

    local savedData

    if isfile(folderName .. "/" .. fileName) then
        local success, result = pcall(function()
            return Http:JSONDecode(readfile(folderName .. "/" .. fileName))
        end)

        if success then
            savedData = result
        end
    end

    if not savedData then
        savedData = data
    else
        for i, v in pairs(data) do
            if not savedData[i] then
                savedData[i] = v
            end
        end
    end

    -- Check for missing default settings and update the file if needed
    local shouldUpdateFile = false
    for i, v in pairs(data) do
        if savedData[i] == nil then
            savedData[i] = v
            shouldUpdateFile = true
        end
    end

    if shouldUpdateFile then
        local success, errorMsg = persistToFile(folderName, fileName, savedData)
        if not success then
            warn("Error while updating missing default values:", errorMsg)
        end
    end

    return setmetatable({
        Data = savedData,
        FolderName = folderName,
        FileName = fileName,
        _lastSuspendSnapshot = nil
    }, {
        __index = DataFunctions
    })
end

function DataFunctions:ResetToDefaults(defaultData)
    for i, v in pairs(defaultData) do
        self.Data[i] = v
    end
    local success, errorMsg = persistInstance(self)
    if not success then
        warn("Error while resetting values:", errorMsg)
    end
end

function DataFunctions:Update(data)
    for i, v in pairs(data) do
        self.Data[i] = v
    end
    local success, errorMsg = persistInstance(self)
    if not success then
        warn("Error while updating values:", errorMsg)
    end
end

function DataFunctions:Set(name, value)
    local success, errorMsg = pcall(function()
        self.Data[name] = value
        local persistSuccess, persistError = persistInstance(self)
        if not persistSuccess then
            error(persistError)
        end
    end)

    if not success then
        warn("Error while setting value:", errorMsg)
    end
end

function DataFunctions:BatchUpdate(data)
    if type(data) ~= "table" then
        warn("Error while batch updating values:", "data must be a table")
        return false, 0, "data must be a table"
    end

    local changedCount = 0
    for i, v in pairs(data) do
        if self.Data[i] ~= v then
            changedCount = changedCount + 1
        end
        self.Data[i] = v
    end

    local success, errorMsg = persistInstance(self)
    if not success then
        warn("Error while batch updating values:", errorMsg)
        return false, 0, errorMsg
    end

    return true, changedCount
end

function DataFunctions:SuspendTruthy(excludeKeys)
    local excludeLookup = {}
    if type(excludeKeys) == "table" then
        for key, value in pairs(excludeKeys) do
            if type(key) == "number" then
                excludeLookup[value] = true
            elseif value then
                excludeLookup[key] = true
            end
        end
    end

    local snapshot = {}
    local offMap = {}
    local suspendCount = 0

    for key, value in pairs(self.Data) do
        if value and not excludeLookup[key] then
            snapshot[key] = value
            offMap[key] = false
            suspendCount = suspendCount + 1
        end
    end

    if suspendCount == 0 then
        self._lastSuspendSnapshot = nil
        return true, {}, 0
    end

    local success, changedCount, errorMsg = self:BatchUpdate(offMap)
    if not success then
        return false, nil, 0, errorMsg
    end

    self._lastSuspendSnapshot = snapshot
    return true, snapshot, changedCount
end

function DataFunctions:ResumeTruthy(snapshot)
    local restoreSnapshot = snapshot
    if type(restoreSnapshot) ~= "table" then
        restoreSnapshot = self._lastSuspendSnapshot
    end

    if type(restoreSnapshot) ~= "table" then
        return false, 0, "no snapshot provided"
    end

    local restoreMap = {}
    local restoreCount = 0
    for key, value in pairs(restoreSnapshot) do
        restoreMap[key] = value
        restoreCount = restoreCount + 1
    end

    if restoreCount == 0 then
        if restoreSnapshot == self._lastSuspendSnapshot then
            self._lastSuspendSnapshot = nil
        end
        return true, 0
    end

    local success, changedCount, errorMsg = self:BatchUpdate(restoreMap)
    if not success then
        return false, 0, errorMsg
    end

    if restoreSnapshot == self._lastSuspendSnapshot then
        self._lastSuspendSnapshot = nil
    end

    return true, changedCount
end

function DataFunctions:Get(name)
    local success, result = pcall(function()
        return self.Data[name]
    end)

    if success then
        return result
    else
        warn("Error while getting value:", result)
        return nil
    end
end

return Data
