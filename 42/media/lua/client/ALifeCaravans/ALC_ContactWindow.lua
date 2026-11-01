require "ALifeCaravans/ALC_Style"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
local A=ALifeCaravans
local U,L=A.Style,A.Lines
local Panel=type(ISCollapsableWindow)=="table" and ISCollapsableWindow:derive("ALCContactWindow") or nil
local actions={
    {"hail","hail","Flag them down"}, {"trade","trade","Trade"},
    {"ride","panel_ride","Request a seat"}, {"escort","panel_escort","Escort convoy"},
    {"news","news","Ask for news"}, {"wait","wait","Ask them to wait"},
    {"farewell","farewell","Let them go"}, {"inspect_cargo","panel_cargo","Inspect cargo"},
    {"distress_help","panel_rescue","Help the crew"}, {"caravan_status","panel_status","Detailed status"},
}

if Panel then
    function Panel:createChildren()
        ISCollapsableWindow.createChildren(self)
        self.buttons={}
        local width=math.floor((self.width-36)/2)
        local rowHeight=math.max(38,getTextManager():getFontHeight(UIFont.Small)+16)
        for i,action in ipairs(actions) do
            local x=12+((i-1)%2)*(width+12)
            local y=174+math.floor((i-1)/2)*(rowHeight+8)
            local button=ISButton:new(x,y,width,rowHeight,L.ui(action[2],action[3]),self,Panel.act)
            button.command=action[1]
            button:initialise()
            U.button(button,action[1]=="trade")
            self:addChild(button)
            self.buttons[#self.buttons+1]=button
        end
        local bottom=174+5*(rowHeight+8)+8
        self:setHeight(bottom+40)
        self.closeButton=ISButton:new(self.width-132,bottom,120,28,L.ui("close_button","Close"),self,Panel.close)
        self.closeButton:initialise()
        U.button(self.closeButton)
        self:addChild(self.closeButton)
        self.detailList=ISScrollingListBox:new(12,174,self.width-24,bottom-182)
        self.detailList:initialise()
        self.detailList:instantiate()
        self.detailList.itemheight=math.max(36,getTextManager():getFontHeight(UIFont.Small)+14)
        self.detailList.backgroundColor=U.rgba(U.palette().panel)
        self.detailList.doDrawItem=function(box,y,item)
            local row,c=item.item,U.palette()
            local icon=U.icon(row.type)
            if icon then box:drawTextureScaledAspect(icon,8,y+4,28,28,1,1,1,1) end
            local x=icon and 44 or 12
            U.text(box,U.fit(row.label,box.width-160),x,y+8,c.text)
            local value=U.fit(row.value or "",140)
            local tw=getTextManager():MeasureStringX(UIFont.Small,value)
            U.text(box,value,box.width-26-tw,y+8,c.accent)
            return y+box.itemheight
        end
        self:addChild(self.detailList)
        self.detailList:setVisible(false)
        self.backButton=ISButton:new(12,bottom,120,28,L.ui("back_button","Back"),self,Panel.back)
        self.backButton:initialise()
        U.button(self.backButton)
        self:addChild(self.backButton)
        self.backButton:setVisible(false)
        self:setY(math.max(10,math.floor((getCore():getScreenHeight()-self.height)/2)))
        self.joyIndex=1
    end

    function Panel:act(button)
        if button.enable==false then return end
        if A.Convoy.entry(self.vehicleId)==nil then self:close() return end
        A.Client.send(button.command,{vehicleId=self.vehicleId},self.playerNum)
    end

    function Panel:prerender()
        local e=A.Convoy.entry(self.vehicleId)
        if not e then self:close() return end
        U.window(self)
        ISCollapsableWindow.prerender(self)
        U.header(self,e,L.ui("contact_heading","CONVOY CONTACT"))
        local c=U.palette()
        local kind=L.ui("kind_"..tostring(e.kind),tostring(e.kind or "?"))
        U.text(self,U.fit(tostring(e.name or "?").." / "..kind,self.width-24),12,117,c.text)
        U.text(self,U.fit(self.detailTitle or L.ui("contact_hint","Stop the convoy to trade or board. Stay nearby."),self.width-24),12,143,c.muted)
        for i,button in ipairs(self.buttons) do
            button:setVisible(not self.detail)
            local command=button.command
            local allowed=true
            if command=="hail" then allowed=not e.halted
            elseif command=="trade" then allowed=e.halted and e.trade and not e.hostile and A.settings.tradeEnabled
            elseif command=="ride" then allowed=e.halted and not e.hostile and A.settings.allowRiders
            elseif command=="escort" then allowed=not e.hostile and not e.escort and A.settings.escortContracts
            elseif command=="wait" or command=="farewell" then allowed=e.halted and not e.hostile
            elseif command=="distress_help" then allowed=e.sosState=="open" and not e.hostile and A.settings.sosContracts end
            button:setEnable(allowed==true)
            if self.joyfocus then button:setJoypadFocused(i==self.joyIndex,self.joyfocus) end
        end
    end

    function Panel:back()
        self.detail,self.detailTitle=nil,nil
        self.detailList:setVisible(false)
        self.backButton:setVisible(false)
    end
    function Panel:showDetail(title,rows)
        self.detail,self.detailTitle=true,title
        self.detailList:clear()
        for _,row in ipairs(rows) do self.detailList:addItem(row.label,row) end
        self.detailList:setVisible(true)
        self.backButton:setVisible(true)
    end

    function Panel:close()
        self:setVisible(false)
        self:removeFromUIManager()
        if A.Client.contact==self then A.Client.contact=nil end
        if self.joyfocus and type(setJoypadFocus)=="function" then setJoypadFocus(self.playerNum or 0,nil) end
    end
    function Panel:onGainJoypadFocus(data) self.joyfocus=data end
    function Panel:onLoseJoypadFocus() self.joyfocus=nil end
    function Panel:onJoypadDirLeft() self.joyIndex=math.max(1,self.joyIndex-1) end
    function Panel:onJoypadDirRight() self.joyIndex=math.min(#self.buttons,self.joyIndex+1) end
    function Panel:onJoypadDirUp()
        if self.detail then self.detailList:onJoypadDirUp() else self.joyIndex=math.max(1,self.joyIndex-2) end
    end
    function Panel:onJoypadDirDown()
        if self.detail then self.detailList:onJoypadDirDown() else self.joyIndex=math.min(#self.buttons,self.joyIndex+2) end
    end
    function Panel:onJoypadDown(button)
        if button==Joypad.BButton then if self.detail then self:back() else self:close() end
        elseif button==Joypad.AButton and not self.detail then self:act(self.buttons[self.joyIndex]) end
    end
end

function U.openContact(vehicleId,playerNum)
    if not Panel or not A.Convoy.entry(vehicleId) then return false end
    if A.Client.contact then A.Client.contact:close() end
    local width=math.min(640,getCore():getScreenWidth()-40)
    local win=Panel:new(math.floor((getCore():getScreenWidth()-width)/2),60,width,460)
    win.vehicleId,win.playerNum=vehicleId,playerNum or 0
    win:setTitle(L.ui("contact_title","Caravan"))
    win:initialise()
    win:addToUIManager()
    win:setVisible(true)
    win:setResizable(false)
    A.Client.contact=win
    if JoypadState and JoypadState.players and JoypadState.players[win.playerNum+1] and type(setJoypadFocus)=="function" then
        setJoypadFocus(win.playerNum,win)
    end
    return true
end
return U.openContact
