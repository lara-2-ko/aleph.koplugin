-- Native local dialogs for the board editor.
local UIManager = require("ui/uimanager")
local Dialog = {}
function Dialog.actions(opts)
    local menu
    local items={}
    for _, row in ipairs(opts.rows or {}) do
        local r=row
        items[#items+1]={text=r.label,callback=function() UIManager:close(menu); r.run() end}
    end
    menu=require("ui/widget/menu"):new{title=opts.title,item_table=items}
    UIManager:show(menu)
end
function Dialog.confirm(opts)
    UIManager:show(require("ui/widget/confirmbox"):new{text=opts.text,ok_text=opts.ok_label,ok_callback=opts.on_ok})
end
return Dialog
