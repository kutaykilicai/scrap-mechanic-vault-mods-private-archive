local V={} V.__index=V
local function v(x,y,z) return setmetatable({x=x,y=y,z=z},V) end
V.__add=function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
V.__sub=function(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end
V.__mul=function(a,s) return v(a.x*s,a.y*s,a.z*s) end
function V:length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function V:normalize() local l=self:length() return v(self.x/l,self.y/l,self.z/l) end
local alerts, sent = {}, {}
local function inWall(p) return p.x>=1.0 and p.x<=2.0 end
local recreated=nil
sm={ vec3={new=v}, isHost=true,
 exists=function(o) return o~=nil end,
 gui={displayAlertText=function(t) alerts[#alerts+1]=t end, setInteractionText=function() end, getKeyBinding=function() return "E" end},
 physics={raycast=function(a,b)
   local steps=50
   local prevIn=inWall(a)
   for i=1,steps do local p=a+(b-a)*(i/steps); local cur=inWall(p); if cur and not prevIn then return true,{type="body"} end prevIn=cur end
   return false,nil end},
 character={createCharacter=function(pl,w,pos,yaw,pitch) recreated=pos; return {new=true} end},
 localPlayer={getPlayer=function() return nil end},
}
function class() return {} end
dofile(arg[1])
local char={swim=false,dive=false,crouch=false,sprint=false,publicData={waterMovementSpeedFraction=1.0},
 worldPosition=v(0.6,0,0),direction=v(1,0,0),velocity=v(0,0,0)}
function char:isSwimming() return self.swim end function char:setSwimming(b) self.swim=b end
function char:isDiving() return self.dive end function char:setDiving(b) self.dive=b end
function char:isCrouching() return self.crouch end function char:isSprinting() return self.sprint end
function char:getHeight() return 1.8 end function char:getWorld() return "W" end
local player={id=1,character=char}
function player:getCarry() return {isEmpty=function() return true end} end
function player:setCharacter(c) end
local self=setmetatable({shape={worldPosition=v(0,0,0)},network={sendToClient=function(_,p,ev,d) sent[#sent+1]=ev end,sendToServer=function() end}},{__index=FlyNoclipVault})
self:server_onCreate()
self:server_onFixedUpdate(0.025) assert(not char.swim, "off must not touch")
self:sv_n_toggle(nil,player) assert(char.swim and char.dive and char.publicData.waterMovementSpeedFraction==9.5,"fly on")
char.sprint=true self:server_onFixedUpdate(0.025) assert(char.publicData.waterMovementSpeedFraction==19.0,"sprint")
self:sv_n_toggle(nil,player) assert(self.sv.players[1].mode==2)
for i=1,10 do self:server_onFixedUpdate(0.025) end
assert(recreated and recreated.x>2.0, "phase target beyond wall: "..tostring(recreated and recreated.x))
print("phase to x="..recreated.x)
char.sprint=false
local function tk(n) for i=1,(n or 1) do self:server_onFixedUpdate() end end
local function on() return self.sv.players[1]~=nil end
-- holding Shift (boost) long, release, then tap: must NOT turn off
char.sprint=true tk(40) char.sprint=false tk(2) char.sprint=true tk(2) char.sprint=false tk(2) assert(on(),"hold+tap must not off")
tk(30)
-- Shift tap-tap -> off
char.sprint=true tk(3) char.sprint=false tk(3) char.sprint=true tk(3) char.sprint=false tk(1)
assert(not on() and not char.swim and not char.dive and char.publicData.waterMovementSpeedFraction==1.0,"shift x2 off")
-- Ctrl tap-tap -> off
self:sv_setMode(player,1) tk(30)
char.crouch=true tk(3) char.crouch=false tk(3) char.crouch=true tk(3) char.crouch=false tk(1) assert(not on(),"ctrl x2 off")
-- nod -> off
self:sv_setMode(player,1) tk(5)
char.direction=v(0,0.1,0.99) tk(5) char.direction=v(0,0.1,-0.99) tk(5) assert(on(),"half nod stays on")
char.direction=v(0,0.1,0.99) tk(1) assert(not on() and not char.swim,"nod off")
-- slow nod (> 1.5 s between) -> stays on
self:sv_setMode(player,1) char.direction=v(1,0,0) tk(5)
char.direction=v(0,0.1,0.99) tk(2) char.direction=v(1,0,0) tk(70) char.direction=v(0,0.1,-0.99) tk(2) char.direction=v(1,0,0) tk(70) char.direction=v(0,0.1,0.99) tk(2)
assert(on(),"slow nod must not off")
-- moderate dive (z=-0.9) must not count
self:sv_disable(player) char.direction=v(1,0,0)
self:sv_n_toggle(nil,player) self:sv_n_speed(nil,player) assert(char.publicData.waterMovementSpeedFraction==16.5)
self:server_onDestroy() assert(not char.swim and char.publicData.waterMovementSpeedFraction==1.0,"destroy cleanup")
self:server_onCreate() sm.character.createCharacter=function() error("not allowed") end
self:sv_setMode(player,2) char.sprint=true for i=1,10 do self:server_onFixedUpdate() end
assert(self.sv.phaseBroken and char.swim, "phase failure keeps flight")
-- carry auto-off
player.getCarry=function() return {isEmpty=function() return false end} end
self:server_onFixedUpdate() assert(self.sv.players[1]==nil and not char.swim,"carry off")
print("ALL OK", #alerts)
for _,a in ipairs(alerts) do print(" -",a) end
