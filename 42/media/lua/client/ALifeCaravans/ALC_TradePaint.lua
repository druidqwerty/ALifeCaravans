require "ALifeCaravans/ALC_Style"
local A=ALifeCaravans
local U,L=A.Style,A.Lines
local P={}

function P.row(win,list,y,item,alt)
    local c=U.palette()
    local row=item.item
    local w,h=list:getWidth()-14,list.itemheight
    local screenY=y+list:getYScroll()
    if screenY+h<0 or screenY>list.height then return y+h end
    local selected=tonumber(row.selected) or 0
    local color=selected>0 and c.selected or c.panel
    list:drawRect(0,y,w,h-1,alt and 0.85 or 1,color[1],color[2],color[3])
    if selected>0 then list:drawRect(0,y,3,h-1,1,c.accent[1],c.accent[2],c.accent[3]) end
    if win.joyfocus and win.joyList==list and item.index==list.selected then
        list:drawRectBorder(0,y,w,h-1,1,c.accent[1],c.accent[2],c.accent[3])
    end
    local icon=U.icon(row.item or row.type)
    if icon then list:drawTextureScaledAspect(icon,8,y+9,30,30,1,1,1,1) end
    U.text(list,U.fit(row.name,w-140),46,y+5,c.text)
    U.text(list,L.ui("item_value","{price} each / {count} available",{price=row.price,count=row.count}),
        46,y+h-22,c.muted)
    local counter="-   "..selected.."   +"
    local tw=getTextManager():MeasureStringX(UIFont.Small,counter)
    U.text(list,counter,w-8-tw,y+7,selected>0 and c.accent or c.muted)
    return y+h
end

function P.layout(win)
    if not win.sellList then return end
    local half=math.floor((win.width-36)/2)
    local top=140+win.searchHeight
    for i,list in ipairs({win.sellList,win.giveList}) do
        list:setX(i==1 and 12 or 24+half)
        list:setY(top)
        list:setWidth(half)
        list:setHeight(math.max(48,win.height-top-133))
        list.backgroundColor=U.rgba(U.palette().panel)
        list.borderColor=U.rgba(U.palette().panelEdge)
        local entry=i==1 and win.sellSearch or win.giveSearch
        entry:setX(list.x)
        entry:setY(136)
        entry:setWidth(half)
    end
    win.tradeButton:setY(win.height-38)
    win.clearButton:setY(win.height-38)
    win.closeButton:setY(win.height-38)
    win.closeButton:setX(win.width-132)
end

function P.window(win,entry)
    U.window(win)
    U.header(win,entry,L.ui("exchange_heading","ROADSIDE EXCHANGE"))
    local c=U.palette()
    U.text(win,win.theyLabel,12,113,c.name)
    U.text(win,win.youLabel,win.giveList.x,113,c.name)
    local top=win.height-124
    U.panel(win,12,top,win.width-24,78,c)
    local q=win.quote or {}
    local values={q.cost or 0,q.credit or 0,q.balance or 0}
    local labels={L.ui("basket_cost","YOU RECEIVE"),L.ui("basket_credit","YOU OFFER"),L.ui("basket_balance","BALANCE")}
    local third=math.floor((win.width-48)/3)
    for i=1,3 do
        local x=24+(i-1)*third
        U.text(win,labels[i],x,top+6,c.muted)
        U.text(win,tostring(values[i]),x,top+23,i==3 and (q.ok and c.good or c.warn) or c.text,UIFont.Medium)
    end
    local verdict=L.ui("basket_empty","Select goods from either side")
    if q.ok then verdict=L.ui("basket_ready","Offer ready. Extra value is a gift; no cash change.")
    elseif q.reason=="short" then verdict=L.ui("basket_short","Add goods worth {amount} to complete this offer",{amount=-(q.balance or 0)}) end
    U.text(win,U.fit(verdict,win.width-48),24,top+54,q.ok and c.good or c.muted)
    if #win.sellList.items==0 then
        U.text(win,L.ui("no_matches","No matching items"),24,win.sellList.y+12,c.muted)
    end
    if #win.giveList.items==0 then
        U.text(win,L.ui("no_matches","No matching items"),win.giveList.x+12,win.giveList.y+12,c.muted)
    end
end
return P
