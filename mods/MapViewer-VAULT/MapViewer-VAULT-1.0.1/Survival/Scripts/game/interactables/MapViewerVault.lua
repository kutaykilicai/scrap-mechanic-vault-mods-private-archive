-- Map Viewer VAULT
-- Survival interactable. No Mod Manager, no terrain script, no Overworld cell streaming.
-- Waypoints live on this shape's storage (saved with the world, per terminal).

MapViewerVault = class()

local LAYOUT = "$SURVIVAL_DATA/Gui/Layouts/MapViewerVault/MapViewerVault.layout"
local MAX_WP = 12
local CELL_M = 32

local function atan2(y, x)
	if math.atan2 then
		return math.atan2(y, x)
	end
	return math.atan(y, x)
end

local function num(v)
	local n = tonumber(v)
	if n == nil then
		return 0
	end
	return n
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function bearingName(dx, dy)
	local ang = math.deg(atan2(dx, dy))
	if ang < 0 then
		ang = ang + 360
	end
	local names = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	local idx = math.floor((ang + 22.5) / 45) % 8 + 1
	return names[idx], ang
end

local function cleanName(raw, fallback)
	if type(raw) ~= "string" then
		return fallback
	end
	local name = raw:gsub("[%c]", ""):sub(1, 24)
	if name == "" then
		return fallback
	end
	return name
end

local function playerCharacter()
	local player = sm.localPlayer.getPlayer()
	if player == nil then
		return nil
	end
	if player.character ~= nil then
		return player.character
	end
	if player.getCharacter ~= nil then
		return player:getCharacter()
	end
	return nil
end

local function characterPosition(char)
	if char == nil or char.worldPosition == nil then
		return nil
	end
	local p = char.worldPosition
	return num(p.x), num(p.y), num(p.z)
end

local function characterYaw(char)
	if char == nil then
		return nil
	end
	local dir = char.direction
	if dir == nil and char.getDirection ~= nil then
		dir = char:getDirection()
	end
	if dir == nil then
		return nil
	end
	return math.deg(atan2(num(dir.x), num(dir.y)))
end

function MapViewerVault.server_onCreate(self)
	if type(self.storage.waypoints) ~= "table" then
		self.storage.waypoints = {}
	end
	self.network:setClientData({ waypoints = self.storage.waypoints })
end

function MapViewerVault.server_onRefresh(self)
	self:server_onCreate()
end

function MapViewerVault.sv_addHere(self, params, caller)
	local char = nil
	if caller ~= nil then
		char = caller.character
		if char == nil and caller.getCharacter ~= nil then
			char = caller:getCharacter()
		end
	end
	local x, y, z = characterPosition(char)
	if x == nil then
		return
	end
	local list = self.storage.waypoints
	local fallback = "WP " .. tostring(#list + 1)
	local name = cleanName(type(params) == "table" and params.name or nil, fallback)
	list[#list + 1] = { name = name, x = x, y = y, z = z }
	while #list > MAX_WP do
		table.remove(list, 1)
	end
	self.storage.waypoints = list
	self.network:setClientData({ waypoints = list })
end

function MapViewerVault.sv_removeLast(self)
	local list = self.storage.waypoints
	if type(list) ~= "table" or #list == 0 then
		return
	end
	table.remove(list)
	self.storage.waypoints = list
	self.network:setClientData({ waypoints = list })
end

function MapViewerVault.sv_clear(self)
	self.storage.waypoints = {}
	self.network:setClientData({ waypoints = self.storage.waypoints })
end

function MapViewerVault.client_onCreate(self)
	self.waypoints = {}
	self.cl_open = false
	self.cl_acc = 0
	self.gui = sm.gui.createGuiFromLayout(LAYOUT)
	self.gui:setButtonCallback("Close", "cl_onClose")
	self.gui:setButtonCallback("AddHere", "cl_onAddHere")
	self.gui:setButtonCallback("RemoveLast", "cl_onRemoveLast")
	self.gui:setButtonCallback("Clear", "cl_onClear")
	if self.gui.setTextChangedCallback ~= nil then
		self.gui:setTextChangedCallback("WpName", "cl_onName")
	end
	self.pendingName = ""
end

function MapViewerVault.client_onRefresh(self)
	if self.gui == nil then
		self:client_onCreate()
	end
end

function MapViewerVault.client_onClientDataUpdate(self, data)
	self.waypoints = {}
	if type(data) == "table" and type(data.waypoints) == "table" then
		self.waypoints = data.waypoints
	end
	if self.gui ~= nil then
		self:cl_refresh()
	end
end

function MapViewerVault.client_canInteract(self)
	sm.gui.setInteractionText("", "Open map")
	return true
end

function MapViewerVault.client_onInteract(self, character, state)
	if state ~= true then
		return
	end
	self.cl_open = true
	self:cl_refresh()
	self.gui:open()
end

function MapViewerVault.client_onUpdate(self, dt)
	if self.gui == nil then
		return
	end
	local active = self.cl_open
	if self.gui.isActive ~= nil then
		local ok, value = pcall(function()
			return self.gui:isActive()
		end)
		if ok then
			active = value and true or false
			self.cl_open = active
		end
	end
	if not active then
		return
	end
	self.cl_acc = self.cl_acc + dt
	if self.cl_acc < 0.25 then
		return
	end
	self.cl_acc = 0
	self:cl_refresh()
end

function MapViewerVault.cl_onClose(self)
	self.cl_open = false
	if self.gui ~= nil then
		self.gui:close()
	end
end

function MapViewerVault.cl_onName(self, text)
	self.pendingName = text or ""
end

function MapViewerVault.cl_onAddHere(self)
	local name = self.pendingName or ""
	if self.gui.getText ~= nil then
		local ok, text = pcall(function()
			return self.gui:getText("WpName")
		end)
		if ok and type(text) == "string" then
			name = text
		end
	end
	self.network:sendToServer("sv_addHere", { name = name })
end

function MapViewerVault.cl_onRemoveLast(self)
	self.network:sendToServer("sv_removeLast", {})
end

function MapViewerVault.cl_onClear(self)
	self.network:sendToServer("sv_clear", {})
end

function MapViewerVault.cl_buildRose(self, px, py)
	local cells = {}
	for gy = -3, 3 do
		cells[gy] = {}
		for gx = -3, 3 do
			cells[gy][gx] = "."
		end
	end
	cells[0][0] = "@"
	local wps = self.waypoints or {}
	for i = 1, #wps do
		local wp = wps[i]
		if type(wp) == "table" then
			local cx = clamp(math.floor((num(wp.x) - px) / CELL_M + 0.5), -3, 3)
			local cy = clamp(math.floor((num(wp.y) - py) / CELL_M + 0.5), -3, 3)
			local letter = string.char(string.byte("A") + i - 1)
			if cx ~= 0 or cy ~= 0 then
				cells[cy][cx] = letter
			end
		end
	end
	local lines = { "N (+Y)  1 cell = 32m" }
	for gy = 3, -3, -1 do
		local row = {}
		for gx = -3, 3 do
			row[#row + 1] = cells[gy][gx]
		end
		lines[#lines + 1] = table.concat(row, " ")
	end
	lines[#lines + 1] = "S"
	return table.concat(lines, "\n")
end

function MapViewerVault.cl_buildList(self, px, py, pz)
	local wps = self.waypoints or {}
	if #wps == 0 then
		return "No waypoints yet.\nStand on a spot, type a name, ADD HERE.\nSaved on this block only."
	end
	local lines = {}
	for i = 1, #wps do
		local wp = wps[i]
		if type(wp) == "table" then
			local dx = num(wp.x) - px
			local dy = num(wp.y) - py
			local dz = num(wp.z) - pz
			local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
			local face = bearingName(dx, dy)
			local letter = string.char(string.byte("A") + i - 1)
			lines[#lines + 1] = string.format(
				"%s %s  %.0fm %s  (%.0f, %.0f, %.0f)",
				letter,
				cleanName(wp.name, "WP"),
				dist,
				face,
				num(wp.x),
				num(wp.y),
				num(wp.z)
			)
		end
	end
	return table.concat(lines, "\n")
end

function MapViewerVault.cl_refresh(self)
	if self.gui == nil then
		return
	end
	local char = playerCharacter()
	local px, py, pz = characterPosition(char)
	if px == nil then
		local sp = self.shape and self.shape.worldPosition or nil
		if sp ~= nil then
			px, py, pz = num(sp.x), num(sp.y), num(sp.z)
		else
			px, py, pz = 0, 0, 0
		end
	end
	local yaw = characterYaw(char)
	self.gui:setText("Pos", string.format("YOU   X %.1f    Y %.1f    Z %.1f", px, py, pz))
	if yaw == nil then
		self.gui:setText("Yaw", "Facing unknown. +Y = North on this grid.")
	else
		self.gui:setText("Yaw", string.format("Facing %.0f deg from +Y.  +Y = North, +X = East.", yaw))
	end
	local term = ""
	if self.shape ~= nil and self.shape.worldPosition ~= nil then
		local sp = self.shape.worldPosition
		term = string.format("\nThis block  X %.0f  Y %.0f  Z %.0f", num(sp.x), num(sp.y), num(sp.z))
	end
	self.gui:setText("Rose", self:cl_buildRose(px, py))
	self.gui:setText("WpList", self:cl_buildList(px, py, pz) .. term)
end
