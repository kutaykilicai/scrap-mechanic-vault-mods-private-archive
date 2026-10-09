dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/pipes.lua" )

---@class ItemFilter : ShapeClass
---@field sv table
---@field cl table
ItemFilter = class( nil )

local ItemFilterUuid = sm.uuid.new( "c0d192e4-a5ff-403f-8202-aac8f6946e17" )

-- IN port = top (local +Y). Connect this toward the main network.
-- OUT port = bottom (local -Y). Connect this toward the filtered chest.
local InDirectionLocal = sm.vec3.new( 0, 1, 0 )
local InDirectionDotThreshold = 0.5

local FilterSlotCount = 10

-- Storage shape UUIDs matching vanilla ContainerUuids (pipes.lua / survival_items.lua).
-- setFilters must ONLY target these — never ItemPump whitelist containers, Craftbot,
-- or other non-chest shapes (that was the Craftbot first-item-only dump bug).
local StorageShapeUuidSet = {
	["056e5ff1-f030-40df-946a-b830bf494c92"] = true, -- obj_container_gas
	["da4833fd-f981-4e08-a9f7-48e630a7c146"] = true, -- obj_container_battery
	["ea10d1af-b97a-46fb-8895-dfd1becb53bb"] = true, -- obj_container_water
	["38ec258d-c644-4f08-8635-3f7434c884dd"] = true, -- obj_container_seed
	["76331bbf-abbd-4b8d-bb54-f721a5b6193b"] = true, -- obj_container_fertilizer
	["096d4daf-639e-4947-a1a6-1890eaa94464"] = true, -- obj_container_ammo
	["be29592a-ef58-4b1d-b18c-895023abd27f"] = true, -- obj_container_chemical
	["ad35f7e6-af8f-40fa-aef4-77d827ac8a8a"] = true, -- obj_container_chest
	["e9efc008-8fae-4391-9ad1-6a62dbab5760"] = true, -- obj_container_chest_looting
	["5cb15c93-4fa9-48da-9974-2e95ca6c9e1c"] = true, -- obj_craftbot_refinery
	["9601f2ca-9552-48b0-afc1-b0f200461114"] = true, -- obj_container_XXL_chest
	["4c474cff-3f6a-4306-93d1-c4c74578afd2"] = true, -- obj_container_smallchest_pipe
	-- Extra pipe-capable storage chests present in survival_items but not listed in ContainerUuids
	["fcfae5e2-1df9-47d8-bb9a-30bec9b5b1f5"] = true, -- obj_container_smallchest
	["7527cf2e-1705-4214-9d07-3dc374957e25"] = true, -- obj_container_tinychest
}

local function isStorageShape( shape )
	return StorageShapeUuidSet[tostring( shape:getShapeUuid() )] == true
end

function ItemFilter.server_onCreate( self )
	self.sv = {}
	self.sv.lastFilterSignature = nil
	self.sv.lastNetworkSignature = nil
	self.sv.lastTargets = {}
	self.sv.didStuckClear = false

	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container = self.shape:getInteractable():addContainer( 0, FilterSlotCount )
	end
end

-- Walks the filter OUT subgraph.
-- stopAtStorage=true (normal): setFilters targets = first-layer storage only; do NOT
-- recurse past chests (that was flooding Craftbot dump chests on the same creation).
-- stopAtStorage=false (one-shot stuck clear): find ALL storage on the OUT flood so we
-- can setFilters({}) on chests that are no longer legitimate targets.
local function collectDownstreamContainers( self, stopAtStorage )
	if stopAtStorage == nil then
		stopAtStorage = true
	end
	if not sm.exists( self.shape ) then
		return {}, ""
	end

	local inDirWorld = self.shape.worldRotation * InDirectionLocal
	local selfPos = self.shape.worldPosition
	local containers = {}
	local ids = {}

	local function onVertex( vertex, parent )
		if not sm.exists( vertex.shape ) then
			return false
		end

		if parent.shape == self.shape then
			local dir = ( vertex.shape.worldPosition - selfPos ):normalize()
			if dir:dot( inDirWorld ) > InDirectionDotThreshold then
				return false -- upstream/main network side
			end
		end

		if vertex.shape:getShapeUuid() == ItemFilterUuid then
			return false -- downstream filter owns its own sub-network
		end

		if isStorageShape( vertex.shape ) then
			local interactable = vertex.shape:getInteractable()
			local container = interactable and interactable:getContainer( 0 )
			if container then
				containers[#containers + 1] = container
				ids[#ids + 1] = vertex.shape:getId()
			end
			-- Stop at chest so Craftbot/Depo dump chests beyond the sort bank
			-- are never whitelist targets.
			if stopAtStorage then
				return false
			end
		end
		return true -- pipes / ItemPump / other non-storage: keep walking
	end

	ConstructPipedShapeGraph( self.shape, onVertex )
	table.sort( ids )
	return containers, table.concat( ids, "," )
end

-- Every distinct item type sitting in the filter's own slots, in a stable
-- (sorted) order - one of each is enough, quantity in the slot doesn't matter.
local function collectFilterUuids( container )
	local seen = {}
	local uuids = {}
	for slot = 0, FilterSlotCount - 1 do
		local slotItem = container:getItem( slot )
		if slotItem.quantity > 0 and slotItem.uuid ~= sm.uuid.getNil() then
			local key = tostring( slotItem.uuid )
			if not seen[key] then
				seen[key] = true
				uuids[#uuids + 1] = slotItem.uuid
			end
		end
	end
	table.sort( uuids, function( a, b ) return tostring( a ) < tostring( b ) end )
	return uuids
end

function ItemFilter.server_onFixedUpdate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		return
	end

	local filterUuids = collectFilterUuids( container )
	local filterKeys = {}
	for i, uuid in ipairs( filterUuids ) do
		filterKeys[i] = tostring( uuid )
	end
	local filterSignature = table.concat( filterKeys, "," )

	local targets, networkSignature = collectDownstreamContainers( self, true )

	-- One-shot: clear setFilters on OUT-flood storage that is NOT a first-layer
	-- target (Craftbot Depo dump chests that inherited a stale whitelist).
	-- Sibling filters re-apply their own targets on their next tick.
	if not self.sv.didStuckClear then
		local legit = {}
		for _, t in ipairs( targets ) do
			legit[t] = true
		end
		local flooded = collectDownstreamContainers( self, false )
		for _, c in ipairs( flooded ) do
			if sm.exists( c ) and not legit[c] then
				c:setFilters( {} )
			end
		end
		self.sv.didStuckClear = true
	end

	-- setFilters only when selection or first-layer network changes (avoids Craftbot
	-- selection-sound spam). Clear chests that left the first-layer target set.
	if filterSignature ~= self.sv.lastFilterSignature or networkSignature ~= self.sv.lastNetworkSignature then
		local currentSet = {}
		for _, targetContainer in ipairs( targets ) do
			if sm.exists( targetContainer ) then
				currentSet[targetContainer] = true
				targetContainer:setFilters( filterUuids )
			end
		end
		for _, prev in ipairs( self.sv.lastTargets or {} ) do
			if sm.exists( prev ) and not currentSet[prev] then
				prev:setFilters( {} )
			end
		end
		self.sv.lastTargets = targets
		self.sv.lastNetworkSignature = networkSignature
	end

	self.sv.lastFilterSignature = filterSignature
end

function ItemFilter.server_onDestroy( self )
	local targets = ( self.sv and self.sv.lastTargets ) or {}
	if #targets == 0 then
		targets = collectDownstreamContainers( self )
	end
	for _, targetContainer in ipairs( targets ) do
		if sm.exists( targetContainer ) then
			targetContainer:setFilters( {} )
		end
	end
end

function ItemFilter.client_canCarry( self )
	local container = self.shape.interactable:getContainer( 0 )
	if container and sm.exists( container ) then
		return not container:isEmpty()
	end
	return false
end

function ItemFilter.client_onInteract( self, _, state )
	if state == true then
		local container = self.shape.interactable:getContainer( 0 )
		if container then
			self.cl = self.cl or {}
			local gui = sm.gui.createContainerGui( true )
			gui:setContainer( "UpperGrid", container )
			gui:setText( "UpperName", "Item Filter" )
			gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			gui:setOnCloseCallback( "cl_e_onClose" )
			gui:open()
			self.cl.gui = gui
		end
	end
end

function ItemFilter.cl_e_onClose( self )
	if self.cl then
		self.cl.gui = nil
	end
end

function ItemFilter.client_onDestroy( self )
	if self.cl and self.cl.gui and self.cl.gui:isActive() then
		self.cl.gui:close()
		self.cl.gui = nil
	end
end
