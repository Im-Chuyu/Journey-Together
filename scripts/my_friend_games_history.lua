-- Result-only archive. One small tail page stays resident; sealed pages are
-- immutable persistent strings and are fetched only on a history click.
local json = setmetatable({}, {__index = function(_, key) return require("json")[key] end})
local M = {PAGE_SIZE = 20}
local Archive = {}; Archive.__index = Archive
function M.New(read, write, prefix, exists)
    return setmetatable({read = read, write = write, prefix = prefix,
        exists = exists, queue = {}, waiting = {}, total = 0, tail = {}}, Archive)
end
function M.ForWorld(world)
    if world._my_friend_games_history ~= nil then return world._my_friend_games_history end
    if TheSim == nil or world.meta == nil or type(world.meta.session_identifier) ~= "string"
        or world.meta.session_identifier == "" then return end
    local shard = TheShard ~= nil and TheShard:GetShardId() or "local"
    local prefix = "my_friend_games_" .. world.meta.session_identifier .. "_" .. tostring(shard) .. "_"
    local archive = M.New(function(key, cb) TheSim:GetPersistentString(key, cb) end,
        function(key, value, cb) TheSim:SetPersistentString(key, value, false, cb) end, prefix,
        function(key, cb) TheSim:CheckPersistentStringExists(key, cb) end)
    world._my_friend_games_history = archive
    return archive
end
function Archive:Load(cb)
    if self.loaded then cb(true); return end
    self.waiting[#self.waiting + 1] = cb
    if self.loading then return end
    self.loading = true
    local function Complete(good)
        self.loaded, self.loading = good, false
        if not good then self.failed = true end
        local waiting = self.waiting; self.waiting = {}
        for _, fn in ipairs(waiting) do fn(good) end
    end
    self.read(self.prefix .. "head", function(ok, value)
        if not ok and self.exists ~= nil then
            -- A read failure is not proof that the file is absent. Never
            -- overwrite an existing archive with an empty one after an IO error.
            self.exists(self.prefix .. "head", function(found) Complete(not found) end)
            return
        end
        local good = not ok
        if ok then
            local decoded, data = pcall(json.decode, value or "")
            good = decoded and type(data) == "table" and type(data.total) == "number"
                and data.total >= 0 and data.total % 1 == 0 and type(data.tail) == "table"
                and #data.tail == (data.total > 0 and (data.total - 1) % M.PAGE_SIZE + 1 or 0)
            if good then self.total, self.tail = data.total, data.tail end
        end
        Complete(good)
    end)
end
function Archive:Pump()
    if self.writing or #self.queue == 0 then return end
    self.writing = true
    self:Load(function(ok)
        if not ok then self.writing = false; return end
        local tail = {}; for i, row in ipairs(self.tail) do tail[i] = row end
        local function Commit()
            if #tail == M.PAGE_SIZE then tail = {} end
            tail[#tail + 1] = self.queue[1]
            local total = self.total + 1
            self.write(self.prefix .. "head", json.encode({total = total, tail = tail}), function(saved)
                self.writing = false
                if saved then
                    self.failed = nil
                    self.total, self.tail = total, tail
                    table.remove(self.queue, 1); self:Pump()
                else self.failed = true end
            end)
        end
        if #tail == M.PAGE_SIZE then
            self.write(self.prefix .. tostring(math.ceil(self.total / M.PAGE_SIZE)), json.encode(tail), function(saved)
                if saved then Commit() else self.writing, self.failed = false, true end
            end)
        else Commit() end
    end)
end
function Archive:Append(record)
    self.queue[#self.queue + 1] = record
    self:Pump()
end
function Archive:Page(page, cb)
    self:Pump() -- Retry an interrupted write on activity, never a polling task.
    self:Load(function(ok)
        if not ok then cb(nil); return end
        local total = self.total
        local pages = math.max(1, math.ceil(total / M.PAGE_SIZE))
        page = math.max(1, math.min(pages, page))
        local block = pages - page + 1
        local function Reply(rows)
            if type(rows) ~= "table" then cb(nil); return end
            local result = {}; for i = #rows, 1, -1 do result[#result + 1] = rows[i] end
            cb({page = page, pages = pages, total = total, rows = result,
                pending = #self.queue > 0, failed = self.failed == true})
        end
        if block == pages then Reply(self.tail)
        else self.read(self.prefix .. tostring(block), function(found, value)
            local decoded, rows = pcall(json.decode, found and value or "")
            if decoded then Reply(rows) else cb(nil) end
        end) end
    end)
end
return M
