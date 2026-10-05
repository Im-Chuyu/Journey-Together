-- Shared name rules; mobile keyboards may append whitespace or a UTF-8 BOM.
local M = {}

function M.Normalize(name)
    if type(name) ~= "string" then return "" end
    name = name:match("^[ \t\r\n\v\f]*(.-)[ \t\r\n\v\f]*$")
    name = name:gsub("^\239\187\191", ""):gsub("\239\187\191$", "")
    return name:match("^[ \t\r\n\v\f]*(.-)[ \t\r\n\v\f]*$")
end

function M.IsValid(name)
    -- Check ASCII controls explicitly: %c depends on the runtime's locale.
    return type(name) == "string" and #name > 0 and #name <= 48
        and not name:find("[%z\1-\31\127<>|]")
end

function M.ReadInput(dialog, entered, initial)
    if type(entered) == "string" then return M.Normalize(entered) end
    local edit = dialog.edit_text
    local fallback
    local function Read(object, method)
        if object == nil or type(object[method]) ~= "function" then return end
        local ok, value = pcall(object[method], object)
        if not ok or type(value) ~= "string" then return end
        value = M.Normalize(value)
        if value ~= "" then
            fallback = fallback or value
            -- Some mobile getters still contain the prefilled name while
            -- another getter exposes the newly committed keyboard text.
            if value ~= initial then return value end
        end
    end
    return Read(edit, "GetLineEditString")
        or Read(edit, "GetString")
        or Read(edit ~= nil and edit.inst ~= nil and edit.inst.TextEditWidget or nil, "GetString")
        or Read(dialog, "GetActualString")
        or fallback or ""
end

return M
