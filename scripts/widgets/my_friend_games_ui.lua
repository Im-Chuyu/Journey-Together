local Image = require("widgets/image")
local ImageButton = require("widgets/imagebutton")
local Text = require("widgets/text")
local M = {}
function M.Box(parent, x, y, w, h, r, g, b, a)
    local image = parent:AddChild(Image("images/global.xml", "square.tex"))
    image:SetSize(w, h); image:SetPosition(x, y); image:SetTint(r, g, b, a or 1); image:SetClickable(false)
    return image
end
function M.Text(parent, text, x, y, size, width)
    local value = parent:AddChild(Text(DEFAULTFONT, size or 24, text))
    value:SetPosition(x, y); value:SetClickable(false)
    if width ~= nil then value:SetTruncatedString(text, width, nil, true) end
    return value
end
function M.Button(parent, text, x, y, w, h, callback)
    local b = ImageButton("images/global.xml", "square.tex")
    if parent ~= nil then parent:AddChild(b) end
    b:ForceImageSize(w, h); b:SetPosition(x, y); b.scale_on_focus = false
    b:SetImageNormalColour(.12, .17, .2, 1); b:SetImageFocusColour(.24, .31, .34, 1)
    b:SetImageDisabledColour(.1, .1, .1, .7)
    b.label = M.Text(b, text, 0, 0, 20, w - 12)
    b.label:SetColour(1, .85, .5, 1); b:SetOnClick(callback)
    return b
end
return M
