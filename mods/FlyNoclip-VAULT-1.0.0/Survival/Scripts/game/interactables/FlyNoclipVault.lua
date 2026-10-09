-- FlyNoclip-VAULT 1.0.0
-- Survival "Uçuş İşaretçisi" (Fly Beacon). Yeni, izole bir parça scripti.
-- Hiçbir oyun scriptini (SurvivalGame, SurvivalPlayer, WaterManager...) değiştirmez,
-- global hook yok, dofile yok, kalıcı storage yok (dünya save'ine veri yazmaz).
--
-- Mod:  0 = KAPALI (hiçbir şeye dokunmaz)
--       1 = UÇUŞ   (character:setSwimming + setDiving: havada yüzme -> baktığın yöne uç)
--       2 = UÇUŞ + NOCLIP (deneysel "duvardan geç": Shift basılı duvara it -> duvarın arkasına ışınla)
--
-- Kontroller:
--   E (parçaya bak)          : Kapalı -> Uçuş -> Uçuş+Noclip -> Kapalı
--   U / Tinker (parçaya bak) : hız seviyesi
--   Ctrl'e hızlı 2 kez bas   : her yerde KAPAT (parça yüklü olduğu sürece)
--   Shift                    : uçarken 2x hız

FlyNoclipVault = class()
FlyNoclipVault.maxParentCount = 0
FlyNoclipVault.maxChildCount = 0

local SPEEDS = { 2.0, 3.5, 6.0, 10.0 }
local SPRINT_MULT = 2.0
local DEFAULT_SPEED_IDX = 2
local DOUBLE_TAP_TICKS = 20          -- 0.5 s @ 40 tick/s
local PHASE_PUSH_TICKS = 8           -- duvara ~0.2 s itince geç
local PHASE_COOLDOWN_TICKS = 30      -- 0.75 s
local PHASE_MAX_DIST = 8.0
local PHASE_STEP = 0.25
local FAR_WARN_DIST = 150.0
local MODE_NAMES = { [0] = "KAPALI", [1] = "UÇUŞ", [2] = "UÇUŞ + NOCLIP" }

local function atan2(y, x)
	if math.atan2 then return math.atan2(y, x) end
	return math.atan(y, x)
end

local function charOf(player)
	if player == nil or not sm.exists(player) then return nil end
	local c = player.character
	if c ~= nil and sm.exists(c) then return c end
	return nil
end

local function setSpeedFraction(character, v)
	if character ~= nil and sm.exists(character) and type(character.publicData) == "table" then
		character.publicData.waterMovementSpeedFraction = v
	end
end

-- ---------------------------------------------------------------- server

function FlyNoclipVault.server_onCreate(self)
	self.sv = { players = {}, speedIdx = DEFAULT_SPEED_IDX, tick = 0, phaseBroken = false }
end

function FlyNoclipVault.sv_msg(self, player, text)
	if player ~= nil and sm.exists(player) then
		self.network:sendToClient(player, "cl_msg", text)
	end
end

function FlyNoclipVault.sv_sendState(self, player, st)
	if player ~= nil and sm.exists(player) then
		self.network:sendToClient(player, "cl_state", { mode = st and st.mode or 0, speedIdx = self.sv.speedIdx })
	end
end

function FlyNoclipVault.sv_clientSpeed(self, player, st, v)
	-- Host'ta publicData yeterli; multiplayer client'ta clientPublicData da gerekli.
	if st == nil or st.lastClientSpeed ~= v then
		if st ~= nil then st.lastClientSpeed = v end
		if player ~= nil and sm.exists(player) then
			self.network:sendToClient(player, "cl_speed", v)
		end
	end
end

-- Uçuşu kapat ve sadece bizim değiştirdiklerimizi vanilla varsayılana döndür.
function FlyNoclipVault.sv_disable(self, player, reason)
	local id = player and player.id
	local st = id and self.sv.players[id]
	if st == nil then return end
	self.sv.players[id] = nil
	local character = charOf(player)
	if character ~= nil then
		if character:isDiving() then character:setDiving(false) end
		if character:isSwimming() then character:setSwimming(false) end
		setSpeedFraction(character, 1.0) -- WaterManager'ın sudan çıkınca koyduğu değer
	end
	self:sv_clientSpeed(player, nil, 1.0)
	self:sv_sendState(player, nil)
	self:sv_msg(player, "Uçuş KAPALI" .. (reason and (" (" .. reason .. ")") or ""))
end

function FlyNoclipVault.sv_setMode(self, player, mode)
	if mode == 0 then
		self:sv_disable(player, nil)
		return
	end
	local character = charOf(player)
	if character == nil then return end
	local st = self.sv.players[player.id]
	if st == nil then
		st = { player = player, mode = mode, crouchPrev = false, lastTap = -1000,
			pushTicks = 0, lastPhase = -1000, farWarned = false }
		self.sv.players[player.id] = st
	end
	st.mode = mode
	self:sv_apply(st)
	self:sv_sendState(player, st)
	if mode == 2 and self.sv.phaseBroken then
		self:sv_msg(player, "UÇUŞ + NOCLIP (noclip bu oyun sürümünde çalışmadı, sadece uçuş)")
	else
		self:sv_msg(player, MODE_NAMES[mode] .. "  |  Kapat: Ctrl'e 2 kez hızlı bas")
	end
end

function FlyNoclipVault.sv_apply(self, st)
	local character = charOf(st.player)
	if character == nil then return end
	if not character:isSwimming() then character:setSwimming(true) end
	if not character:isDiving() then character:setDiving(true) end
	local v = SPEEDS[self.sv.speedIdx] or SPEEDS[DEFAULT_SPEED_IDX]
	if character:isSprinting() then v = v * SPRINT_MULT end
	setSpeedFraction(character, v)
	self:sv_clientSpeed(st.player, st, v)
end

function FlyNoclipVault.sv_n_toggle(self, _, caller)
	if caller == nil then return end
	local st = self.sv.players[caller.id]
	local mode = st and st.mode or 0
	self:sv_setMode(caller, (mode + 1) % 3)
end

function FlyNoclipVault.sv_n_speed(self, _, caller)
	self.sv.speedIdx = self.sv.speedIdx % #SPEEDS + 1
	for _, st in pairs(self.sv.players) do
		self:sv_apply(st)
		self:sv_sendState(st.player, st)
	end
	if caller ~= nil then
		self:sv_sendState(caller, self.sv.players[caller.id])
		self:sv_msg(caller, "Uçuş hızı: " .. self.sv.speedIdx .. "/" .. #SPEEDS)
	end
end

function FlyNoclipVault.sv_n_hello(self, _, caller)
	if caller ~= nil then self:sv_sendState(caller, self.sv.players[caller.id]) end
end

-- Elinde/sırtında taşınan bir şey varsa (sandık vb.) uçuş takılmaya yol açar.
local function isCarrying(player)
	local ok, carry = pcall(function() return player:getCarry() end)
	if not ok or carry == nil then return false end
	local ok2, empty = pcall(function() return carry:isEmpty() end)
	return ok2 and empty == false
end

local function rayHitsSolid(a, b)
	local ok, hit, res = pcall(sm.physics.raycast, a, b)
	if not ok or not hit then return false end
	if res ~= nil and res.type == "character" then return false end
	return true
end

-- p noktası karakter için boş mu? (geldiğimiz duvarın arka yüzü p'den görünmeli,
-- yani p duvarın içinde değil; etrafında 0.4 m yatay / yarım boy dikey boşluk olmalı)
local function isFreeSpot(p, back, halfH)
	if not rayHitsSolid(p, back) then return false end
	local axes = {
		sm.vec3.new(0.4, 0, 0), sm.vec3.new(-0.4, 0, 0),
		sm.vec3.new(0, 0.4, 0), sm.vec3.new(0, -0.4, 0),
		sm.vec3.new(0, 0, halfH), sm.vec3.new(0, 0, -halfH),
	}
	for _, a in ipairs(axes) do
		if rayHitsSolid(p, p + a) or rayHitsSolid(p + a, p) then return false end
	end
	return true
end

function FlyNoclipVault.sv_tryPhase(self, st, character)
	if self.sv.phaseBroken then return end
	if self.sv.tick - st.lastPhase < PHASE_COOLDOWN_TICKS then return end
	local pos = character.worldPosition
	local dir = character.direction
	if pos == nil or dir == nil or dir:length() < 0.01 then return end
	dir = dir:normalize()
	-- Duvara yaslanmış + Shift basılı + neredeyse durmuş olmalı
	local pushing = character:isSprinting() and rayHitsSolid(pos, pos + dir * 1.2)
		and character.velocity:length() < 0.6
	if not pushing then st.pushTicks = 0 return end
	st.pushTicks = st.pushTicks + 1
	if st.pushTicks < PHASE_PUSH_TICKS then return end
	st.pushTicks = 0

	local okH, h = pcall(function() return character:getHeight() end)
	local halfH = ((okH and type(h) == "number" and h > 0.5) and h or 1.8) * 0.5 + 0.05
	local target = nil
	local t = 1.0
	while t <= PHASE_MAX_DIST do
		local p = pos + dir * t
		if isFreeSpot(p, pos + dir * 0.45, halfH) then target = p break end
		t = t + PHASE_STEP
	end
	if target == nil then
		self:sv_msg(st.player, "Noclip: " .. PHASE_MAX_DIST .. " m içinde boş yer yok")
		st.lastPhase = self.sv.tick
		return
	end

	local player = st.player
	local yaw = atan2(dir.y, dir.x) - math.pi / 2
	local pitch = math.asin(math.max(-1, math.min(1, dir.z)))
	local ok, err = pcall(function()
		local newChar = sm.character.createCharacter(player, character:getWorld(), target, yaw, pitch)
		player:setCharacter(newChar)
	end)
	st.lastPhase = self.sv.tick
	if not ok then
		self.sv.phaseBroken = true
		print("[FlyNoclipVault] phase failed: " .. tostring(err))
		self:sv_msg(player, "Noclip bu sürümde çalışmadı; sadece uçuş açık kalıyor")
	end
end

function FlyNoclipVault.server_onFixedUpdate(self, dt)
	if next(self.sv.players) == nil then return end -- kapalıyken hiçbir şey yapma
	self.sv.tick = self.sv.tick + 1
	local myPos = self.shape.worldPosition
	for id, st in pairs(self.sv.players) do
		local player = st.player
		if player == nil or not sm.exists(player) then
			self.sv.players[id] = nil
		else
			local character = charOf(player)
			if character ~= nil then
				-- Ctrl çift dokunuş -> kapat
				local crouch = character:isCrouching()
				local disabled = false
				if crouch and not st.crouchPrev then
					if self.sv.tick - st.lastTap <= DOUBLE_TAP_TICKS then
						self:sv_disable(player, "Ctrl x2")
						disabled = true
					else
						st.lastTap = self.sv.tick
					end
				end
				st.crouchPrev = crouch
				if not disabled and isCarrying(player) then
					self:sv_disable(player, "bir şey taşırken uçmak takılmaya yol açar")
					disabled = true
				end
				if not disabled then
					self:sv_apply(st)
					if st.mode == 2 then self:sv_tryPhase(st, character) end
					local d = (character.worldPosition - myPos):length()
					if d > FAR_WARN_DIST and not st.farWarned then
						st.farWarned = true
						self:sv_msg(player, "Uyarı: Uçuş İşaretçisinden çok uzaklaştın. Parça yüklenmezse kontrol (Ctrl x2) çalışmaz.")
					elseif d < FAR_WARN_DIST * 0.8 then
						st.farWarned = false
					end
				end
			end
		end
	end
end

-- Parça toplanır/yok olursa kimse uçuşta kalmasın.
function FlyNoclipVault.server_onDestroy(self)
	if self.sv == nil then return end
	for _, st in pairs(self.sv.players) do
		local character = charOf(st.player)
		if character ~= nil then
			if character:isDiving() then character:setDiving(false) end
			if character:isSwimming() then character:setSwimming(false) end
			setSpeedFraction(character, 1.0)
		end
	end
	self.sv.players = {}
end

-- ---------------------------------------------------------------- client

function FlyNoclipVault.client_onCreate(self)
	self.cl = { mode = 0, speedIdx = DEFAULT_SPEED_IDX }
	self.network:sendToServer("sv_n_hello")
end

function FlyNoclipVault.cl_state(self, data)
	if type(data) == "table" then
		self.cl.mode = data.mode or 0
		self.cl.speedIdx = data.speedIdx or DEFAULT_SPEED_IDX
	end
end

function FlyNoclipVault.cl_msg(self, text)
	sm.gui.displayAlertText(tostring(text), 3)
end

function FlyNoclipVault.cl_speed(self, v)
	if sm.isHost then return end
	local player = sm.localPlayer.getPlayer()
	local character = player and player.character
	if character ~= nil and sm.exists(character) and type(character.clientPublicData) == "table" then
		character.clientPublicData.waterMovementSpeedFraction = v
	end
end

function FlyNoclipVault.client_canInteract(self, character)
	local nextMode = (self.cl.mode + 1) % 3
	sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true),
		"Uçuş: " .. MODE_NAMES[self.cl.mode] .. "  ->  " .. MODE_NAMES[nextMode])
	sm.gui.setInteractionText("", sm.gui.getKeyBinding("Tinker", true),
		"Hız " .. self.cl.speedIdx .. "/" .. #SPEEDS)
	return true
end

function FlyNoclipVault.client_onInteract(self, character, state)
	if state then self.network:sendToServer("sv_n_toggle") end
end

function FlyNoclipVault.client_canTinker(self, character)
	return true
end

function FlyNoclipVault.client_onTinker(self, character, state)
	if state then self.network:sendToServer("sv_n_speed") end
end
