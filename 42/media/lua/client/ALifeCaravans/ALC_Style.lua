-- Original layouts; optionally consume Jeem's public palette, never its assets.
require "ALifeCaravans/01_ALC_Lines"
local A=ALifeCaravans
local U={icons={}}
A.Style=U
local fallback={window={0.075,0.09,0.105},windowEdge={0.28,0.34,0.38},
    panel={0.105,0.13,0.15},panelEdge={0.20,0.26,0.29},button={0.13,0.18,0.20},
    buttonEdge={0.28,0.36,0.38},buttonOver={0.20,0.27,0.29},primary={0.17,0.31,0.30},
    primaryOver={0.23,0.39,0.36},text={0.88,0.91,0.90},muted={0.60,0.69,0.70},
    name={0.96,0.94,0.83},accent={0.43,0.78,0.69},selected={0.18,0.31,0.30},
    good={0.56,0.85,0.65},warn={0.94,0.72,0.40},bad={0.93,0.46,0.40}}

function U.palette()
    local style=ProjectALifeJimmy and ProjectALifeJimmy.Style
    if style and type(style.refresh)=="function" then style.refresh() end
    local out={}
    for k,v in pairs(fallback) do out[k]=style and style.colors and style.colors[k] or v end
    return out
end

function U.rgba(c,a) return {r=c[1],g=c[2],b=c[3],a=a or 1} end
function U.text(ui,text,x,y,color,font)
    ui:drawText(tostring(text or ""),x,y,color[1],color[2],color[3],1,font or UIFont.Small)
end
function U.fit(text,width,font)
    text=tostring(text or "")
    local tm=getTextManager()
    font=font or UIFont.Small
    if tm:MeasureStringX(font,text)<=width then return text end
    local chars={}
    for char in string.gmatch(text,"[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1]=char end
    while #chars>0 do
        chars[#chars]=nil
        local short=table.concat(chars).."..."
        if tm:MeasureStringX(font,short)<=width then return short end
    end
    return ""
end
function U.panel(ui,x,y,w,h,c)
    c=c or U.palette()
    ui:drawRect(x,y,w,h,0.98,c.panel[1],c.panel[2],c.panel[3])
    ui:drawRectBorder(x,y,w,h,1,c.panelEdge[1],c.panelEdge[2],c.panelEdge[3])
end
function U.window(win)
    local c=U.palette()
    win.backgroundColor=U.rgba(c.window,0.98)
    win.borderColor=U.rgba(c.windowEdge)
end
function U.button(button,primary)
    local c=U.palette()
    button.backgroundColor=U.rgba(primary and c.primary or c.button)
    button.backgroundColorMouseOver=U.rgba(primary and c.primaryOver or c.buttonOver)
    button.borderColor=U.rgba(primary and c.accent or c.buttonEdge)
    button.textColor=U.rgba(c.text)
end
function U.entry(entry)
    local c=U.palette()
    entry.backgroundColor=U.rgba(c.panel)
    entry.borderColor=U.rgba(c.buttonEdge)
    entry:setTextRGBA(c.text[1],c.text[2],c.text[3],1)
end
function U.icon(fullType)
    if not fullType then return nil end
    if U.icons[fullType]==nil then
        local ok,texture=pcall(function()
            local item=getScriptManager():FindItem(fullType)
            return item and item:getNormalTexture()
        end)
        U.icons[fullType]=ok and texture or false
    end
    return U.icons[fullType] or nil
end
function U.state(entry)
    local L=A.Lines
    if entry.threatState=="escape" then return L.ui("state_escape","Getting out of danger"),"warn" end
    if entry.hostile then return L.ui("state_hostile","Hostile"),"bad" end
    if entry.halted then return L.ui("state_waiting","Stopped"),"good" end
    return L.ui("state_travelling","On the road"),"accent"
end
function U.header(win,entry,heading)
    local c=U.palette()
    U.panel(win,12,28,win.width-24,78,c)
    win:drawRect(12,28,3,78,1,c.accent[1],c.accent[2],c.accent[3])
    U.text(win,heading,24,35,c.accent)
    local title=tostring(entry.leader or entry.name or "?")
    if entry.callsign and entry.callsign~="" then title=title.." / "..entry.callsign end
    U.text(win,U.fit(title,win.width-48,UIFont.Medium),24,52,c.name,UIFont.Medium)
    local status,tone=U.state(entry)
    local route=A.Lines.ui("route_to","To {dest}",{dest=entry.dest or "?"})
    U.text(win,U.fit(route,win.width*0.52),24,82,c.muted)
    local width=getTextManager():MeasureStringX(UIFont.Small,status)
    U.text(win,status,win.width-24-width,82,c[tone])
end
return U
