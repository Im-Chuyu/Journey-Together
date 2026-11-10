local M = {}

function M.PrepareCommand(command)
    local x, _, z = command.player.Transform:GetWorldPosition()
    local tx, tz = TheWorld.Map:GetTileCoordsAtPoint(x, 0, z)
    local cx, cy, cz = TheWorld.Map:GetTileCenterPoint(tx, tz)
    if cx ~= nil then command.build_point = Vector3(cx, cy, cz) end
end

return M
