dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/pipes.lua" )

---@class ItemSorter : ShapeClass
---@field sv table
---@field cl table
ItemSorter = class( nil )
ItemSorter.connectionInput = sm.interactable.connectionType.logic
ItemSorter.connectionOutput = sm.interactable.connectionType.none
ItemSorter.maxParentCount = 1
ItemSorter.maxChildCount = 0

local ItemSorterUuid = sm.uuid.new( "d4f8b2c1-7a39-4e6f-91b0-5c8d2e4a7f13" )
local ItemPumpUuid = sm.uuid.new( "b7e4a201-9c58-4f2d-8a61-0d3e5f7a9124" )
local ItemFilterUuid = sm.uuid.new( "c0d192e4-a5ff-403f-8202-aac8f6946e17" )

-- IN = local +X (dump). OUT = local -X (sorted destinations).
local InDirectionLocal = sm.vec3.new( 1, 0, 0 )
local DirectionDotThreshold = 0.5

local FilterSlotCount = 10
local StartInterval = 4
local MaxInFlight = 20
local MoveQty = 1
local TravelSeconds = 0.55
local SecondsPerShape = 0.05
local FixedTickHz = 40
local MaxTransfersPerTick = 3

local ScanRadius = 32
local OverviewMaxItems = 48

-- Craftbot-like taxonomy order (ALL is display-only)
local CategoryOrder = { "tools", "blocks", "interactive", "parts", "consumable" }
local CategoryTitle = {
	tools = "Tools",
	blocks = "Blocks",
	interactive = "Interactive",
	parts = "Parts",
	consumable = "Consumable"
}

-- Interactable type names from sm.interactable.types (for Interactive set)
local InteractableTypeNames = {
	"electricEngine", "gasEngine", "steering", "seat", "controller", "button",
	"lever", "sensor", "thruster", "radio", "horn", "tone", "logic", "timer",
	"particlePreview", "spring", "pointLight", "spotLight", "chest", "scripted",
	"piston", "simpleInteractive"
}

local InteractiveUuidSet = nil

local function buildInteractiveUuidSet()
	local set = {}
	set[tostring( ItemSorterUuid )] = true
	set[tostring( ItemPumpUuid )] = true
	set[tostring( ItemFilterUuid )] = true
	if sm.item.getInteractablesUuidsOfType then
		for _, typeName in ipairs( InteractableTypeNames ) do
			local ok, list = pcall( sm.item.getInteractablesUuidsOfType, typeName )
			if ok and list then
				for _, uid in ipairs( list ) do
					set[tostring( uid )] = true
				end
			end
		end
	end
	return set
end

local function ensureInteractiveSet()
	if not InteractiveUuidSet then
		InteractiveUuidSet = buildInteractiveUuidSet()
	end
	return InteractiveUuidSet
end

--- Classify uuid into Craftbot-like tab category using sm.item predicates.
--- Detection (priority): isTool → Tools; isBlock → Blocks; edible/plantable/
--- harvestablePart → Consumable; interactables set / qualityLevel → Interactive;
--- isJoint or remaining isPart → Parts; else Consumable.
local function getItemCategory( uuid )
	if not uuid or uuid == sm.uuid.getNil() then
		return "consumable"
	end
	if sm.item.isTool( uuid ) then
		return "tools"
	end
	if sm.item.isBlock( uuid ) then
		return "blocks"
	end
	if sm.item.isHarvestablePart and sm.item.isHarvestablePart( uuid ) then
		return "consumable"
	end
	if sm.item.getEdible then
		local ok, edible = pcall( sm.item.getEdible, uuid )
		if ok and edible then
			return "consumable"
		end
	end
	if sm.item.getPlantable then
		local ok, plant = pcall( sm.item.getPlantable, uuid )
		if ok and plant then
			return "consumable"
		end
	end
	local key = tostring( uuid )
	local interactiveSet = ensureInteractiveSet()
	if interactiveSet[key] then
		return "interactive"
	end
	if sm.item.getQualityLevel then
		local ok, ql = pcall( sm.item.getQualityLevel, uuid )
		if ok and type( ql ) == "number" and ql > 0 and sm.item.isPart( uuid ) then
			return "interactive"
		end
	end
	if sm.item.isJoint and sm.item.isJoint( uuid ) then
		return "parts"
	end
	if sm.item.isPart( uuid ) then
		return "parts"
	end
	return "consumable"
end

function ItemSorter.server_onCreate( self )
	self.sv = {}
	self.sv.tickAcc = 0
	self.sv.inFlight = {}
	self.sv.viewBaseline = nil
	ensureInteractiveSet()

	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container = self.shape:getInteractable():addContainer( 0, FilterSlotCount )
	end
	-- Index 1 = nearby-storage mirror shown in the Sortbot GUI
	local display = self.shape.interactable:getContainer( 1 )
	if not display then
		self.shape:getInteractable():addContainer( 1, OverviewMaxItems, 999999 )
	end
end

local function isSorterEnabled( self )
	local parent = self.shape:getInteractable():getSingleParent()
	if parent then
		return parent.active == true
	end
	return true
end

local function collectFilterUuids( container )
	local seen = {}
	local uuids = {}
	if not container then
		return uuids
	end
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
	return uuids
end

local function uuidAllowed( uuid, filterUuids )
	if #filterUuids == 0 then
		return true
	end
	local key = tostring( uuid )
	for _, f in ipairs( filterUuids ) do
		if tostring( f ) == key then
			return true
		end
	end
	return false
end

local function containerUuidSet( container )
	local set = {}
	local empty = true
	if not container or not sm.exists( container ) then
		return set, true
	end
	for slot = 0, container:getSize() - 1 do
		local item = container:getItem( slot )
		if item.quantity > 0 and item.uuid ~= sm.uuid.getNil() then
			empty = false
			set[tostring( item.uuid )] = true
		end
	end
	return set, empty
end

local function collectSideEnds( self, wantInput )
	if not sm.exists( self.shape ) then
		return {}
	end

	local inDirWorld = self.shape.worldRotation * InDirectionLocal
	local selfPos = self.shape.worldPosition
	local ends = {}

	local function onVertex( vertex, parent )
		if not sm.exists( vertex.shape ) then
			return false
		end

		if parent.shape == self.shape then
			local dir = ( vertex.shape.worldPosition - selfPos ):normalize()
			local towardIn = dir:dot( inDirWorld ) > DirectionDotThreshold
			if wantInput then
				if not towardIn then
					return false
				end
			else
				if towardIn then
					return false
				end
			end
		end

		local uuid = vertex.shape:getShapeUuid()
		if uuid == ItemSorterUuid or uuid == ItemPumpUuid or uuid == ItemFilterUuid then
			if vertex.shape ~= self.shape then
				return false
			end
		end

		if vertex.shape == self.shape then
			return true
		end

		local interactable = vertex.shape:getInteractable()
		local container = interactable and interactable:getContainer( 0 )
		if container then
			local pathCopy = {}
			local srcPath = vertex.shapesOnPath or {}
			for i = 1, #srcPath do
				pathCopy[i] = srcPath[i]
			end
			ends[#ends + 1] = { container = container, shape = vertex.shape, path = pathCopy }
		end
		return true
	end

	ConstructPipedShapeGraph( self.shape, onVertex )
	return ends
end

local function buildTravelPath( self, srcEnd, dstEnd )
	local path = {}
	for i = #srcEnd.path, 1, -1 do
		path[#path + 1] = srcEnd.path[i]
	end
	path[#path + 1] = self.shape
	for i = 1, #dstEnd.path do
		path[#path + 1] = dstEnd.path[i]
	end
	return path
end

local function travelDurationSeconds( pathLen )
	return math.max( TravelSeconds, pathLen * SecondsPerShape )
end

local function canCollect( container, uuid, qty )
	if not container or not sm.exists( container ) then
		return false
	end
	if sm.container.canCollect then
		return sm.container.canCollect( container, uuid, qty )
	end
	return true
end

local function finishArrivals( self )
	local still = {}
	for _, parcel in ipairs( self.sv.inFlight ) do
		parcel.ticksLeft = parcel.ticksLeft - 1
		if parcel.ticksLeft <= 0 then
			if sm.exists( parcel.destContainer ) then
				sm.container.beginTransaction()
				sm.container.collect( parcel.destContainer, parcel.uuid, parcel.qty, true )
				if not sm.container.endTransaction() then
					if sm.exists( parcel.srcContainer ) then
						sm.container.beginTransaction()
						sm.container.collect( parcel.srcContainer, parcel.uuid, parcel.qty, true )
						sm.container.endTransaction()
					end
				end
			elseif sm.exists( parcel.srcContainer ) then
				sm.container.beginTransaction()
				sm.container.collect( parcel.srcContainer, parcel.uuid, parcel.qty, true )
				sm.container.endTransaction()
			end
		else
			still[#still + 1] = parcel
		end
	end
	self.sv.inFlight = still
end

-- Prefer OUT chests that already hold this uuid; else empty overflow chests.
local function pickDestination( dests, itemUuid )
	local key = tostring( itemUuid )
	local filteredMatches = {}
	local overflows = {}

	for _, dst in ipairs( dests ) do
		if sm.exists( dst.container ) then
			local set, empty = containerUuidSet( dst.container )
			if empty then
				overflows[#overflows + 1] = dst
			elseif set[key] then
				filteredMatches[#filteredMatches + 1] = dst
			end
		end
	end

	for _, dst in ipairs( filteredMatches ) do
		if canCollect( dst.container, itemUuid, MoveQty ) then
			return dst
		end
	end
	for _, dst in ipairs( overflows ) do
		if canCollect( dst.container, itemUuid, MoveQty ) then
			return dst
		end
	end
	return nil
end

local function tryLaunch( self )
	if #self.sv.inFlight >= MaxInFlight then
		return 0
	end

	local sources = collectSideEnds( self, true )
	local dests = collectSideEnds( self, false )
	if #sources == 0 or #dests == 0 then
		return 0
	end

	local filterContainer = self.shape.interactable:getContainer( 0 )
	local filterUuids = collectFilterUuids( filterContainer )
	local launched = 0

	for _, src in ipairs( sources ) do
		if launched >= MaxTransfersPerTick or #self.sv.inFlight >= MaxInFlight then
			break
		end
		if sm.exists( src.container ) and not src.container:isEmpty() then
			for slot = 0, src.container:getSize() - 1 do
				if launched >= MaxTransfersPerTick or #self.sv.inFlight >= MaxInFlight then
					break
				end
				local item = src.container:getItem( slot )
				if item.quantity > 0 and item.uuid ~= sm.uuid.getNil() and uuidAllowed( item.uuid, filterUuids ) then
					local dst = pickDestination( dests, item.uuid )
					if dst then
						sm.container.beginTransaction()
						sm.container.spend( src.container, item.uuid, MoveQty, true )
						if sm.container.endTransaction() then
							local travelPath = buildTravelPath( self, src, dst )
							local secs = travelDurationSeconds( #travelPath )
							local ticks = math.max( 8, math.floor( secs * FixedTickHz + 0.5 ) )
							self.sv.inFlight[#self.sv.inFlight + 1] = {
								uuid = item.uuid,
								qty = MoveQty,
								srcContainer = src.container,
								destContainer = dst.container,
								ticksLeft = ticks
							}
							self.network:sendToClients( "cl_n_itemTravel", {
								item = item.uuid,
								source = src.shape,
								dest = dst.shape,
								duration = secs,
								path = travelPath
							} )
							launched = launched + 1
						end
					end
				end
			end
		end
	end
	return launched
end

function ItemSorter.server_onFixedUpdate( self )
	if not sm.exists( self.shape ) then
		return
	end

	finishArrivals( self )

	if not isSorterEnabled( self ) then
		self.sv.tickAcc = 0
		return
	end

	self.sv.tickAcc = ( self.sv.tickAcc or 0 ) + 1
	if self.sv.tickAcc < StartInterval then
		return
	end
	self.sv.tickAcc = 0
	tryLaunch( self )
end

function ItemSorter.client_onCreate( self )
	self.cl = {}
	self.cl.pipeEffectPlayer = PipeEffectPlayer()
	self.cl.pipeEffectPlayer:onCreate()
	ensureInteractiveSet()
end

function ItemSorter.client_onUpdate( self, dt )
	if self.cl and self.cl.pipeEffectPlayer then
		self.cl.pipeEffectPlayer:update( dt )
	end
end

function ItemSorter.cl_n_itemTravel( self, data )
	if not self.cl or not self.cl.pipeEffectPlayer then
		return
	end
	if not data or not data.item or not data.source or not data.dest then
		return
	end
	if not sm.exists( data.source ) or not sm.exists( data.dest ) then
		return
	end

	-- Prefer server-built pipe path; else rebuild via ConstructPipedShapeGraph; else hard fallback.
	local duration = data.duration or TravelSeconds
	if duration < 0.7 then
		duration = 0.7
	end

	local path = nil
	if data.path and type( data.path ) == "table" and #data.path >= 2 then
		path = data.path
	else
		local ok, built = pcall( function()
			local sources = collectSideEnds( self, true )
			local dests = collectSideEnds( self, false )
			local srcEnd, dstEnd
			for _, s in ipairs( sources ) do
				if s.shape == data.source then
					srcEnd = s
					break
				end
			end
			for _, d in ipairs( dests ) do
				if d.shape == data.dest then
					dstEnd = d
					break
				end
			end
			if srcEnd and dstEnd then
				return buildTravelPath( self, srcEnd, dstEnd )
			end
			return nil
		end )
		if ok and built and #built >= 2 then
			path = built
		end
	end
	if not path or #path < 2 then
		path = { data.source, self.shape, data.dest }
	end
	-- Vacuum-style ShapeRenderable travel; pcall so non-shape items cannot kill client
	pcall( function()
		self.cl.pipeEffectPlayer:pushShapeEffectTask( path, data.item, nil, duration )
	end )
end



local function isSkippedUuid( uuid )
	return uuid == ItemSorterUuid or uuid == ItemPumpUuid or uuid == ItemFilterUuid
end

local function gatherNearbyChests( self )
	local chests = {}
	if not sm.exists( self.shape ) then
		return chests
	end
	local origin = self.shape.worldPosition
	local bodies = sm.body.getCreationBodies( self.shape:getBody() )
	for _, body in ipairs( bodies ) do
		if sm.exists( body ) then
			for _, shape in ipairs( body:getShapes() ) do
				if sm.exists( shape ) then
					local delta = shape.worldPosition - origin
					if delta:length() <= ScanRadius then
						local uuid = shape:getShapeUuid()
						if not isSkippedUuid( uuid ) then
							local interactable = shape:getInteractable()
							local container = interactable and interactable:getContainer( 0 )
							if container and sm.exists( container ) then
								chests[#chests + 1] = { shape = shape, container = container }
							end
						end
					end
				end
			end
		end
	end
	return chests
end

local function gatherNearbyStorage( self )
	local totals = {}
	local chests = gatherNearbyChests( self )
	for _, chest in ipairs( chests ) do
		local container = chest.container
		for slot = 0, container:getSize() - 1 do
			local item = container:getItem( slot )
			if item.quantity > 0 and item.uuid ~= sm.uuid.getNil() then
				local key = tostring( item.uuid )
				local entry = totals[key]
				if not entry then
					local cat = getItemCategory( item.uuid )
					entry = { uuid = item.uuid, itemId = key, quantity = 0, category = cat }
					totals[key] = entry
				end
				entry.quantity = entry.quantity + item.quantity
			end
		end
	end
	local list = {}
	for _, entry in pairs( totals ) do
		list[#list + 1] = entry
	end
	table.sort( list, function( a, b )
		if a.quantity == b.quantity then
			return a.itemId < b.itemId
		end
		return a.quantity > b.quantity
	end )
	return list
end

local function clearContainer( container )
	if not container or not sm.exists( container ) then
		return
	end
	sm.container.beginTransaction()
	for slot = 0, container:getSize() - 1 do
		local it = container:getItem( slot )
		if it.quantity > 0 and it.uuid ~= sm.uuid.getNil() then
			sm.container.spend( container, it.uuid, it.quantity, true )
		end
	end
	sm.container.endTransaction()
end

local function clearDisplay( display )
	clearContainer( display )
end

local function fillDisplay( display, items )
	clearDisplay( display )
	if not display or not sm.exists( display ) then
		return
	end
	sm.container.beginTransaction()
	for i, entry in ipairs( items ) do
		if i > OverviewMaxItems then
			break
		end
		sm.container.collect( display, entry.uuid, entry.quantity, true )
	end
	sm.container.endTransaction()
end

local function countUuid( container, uuid )
	local n = 0
	if not container or not sm.exists( container ) then
		return 0
	end
	for slot = 0, container:getSize() - 1 do
		local it = container:getItem( slot )
		if it.uuid == uuid then
			n = n + it.quantity
		end
	end
	return n
end

local function spendFromNearby( self, uuid, qty )
	if qty <= 0 then
		return true
	end
	local remaining = qty
	local chests = gatherNearbyChests( self )
	sm.container.beginTransaction()
	for _, chest in ipairs( chests ) do
		if remaining <= 0 then break end
		local container = chest.container
		if container and sm.exists( container ) then
			local have = countUuid( container, uuid )
			local take = math.min( have, remaining )
			if take > 0 then
				sm.container.spend( container, uuid, take, true )
				remaining = remaining - take
			end
		end
	end
	return sm.container.endTransaction() and remaining <= 0
end

--- Place as much as possible of uuid/qty into container (handles stack limits).
local function collectInto( container, uuid, qty )
	if qty <= 0 or not container or not sm.exists( container ) then
		return 0
	end
	local placed = 0
	local remaining = qty
	-- Try in chunks of stack size when available
	local stackSize = 64
	if sm.item.getStackSize then
		local ok, s = pcall( sm.item.getStackSize, uuid )
		if ok and type( s ) == "number" and s > 0 then
			stackSize = s
		end
	end
	while remaining > 0 do
		local chunk = math.min( remaining, stackSize )
		if sm.container.canCollect and not sm.container.canCollect( container, uuid, chunk ) then
			-- binary-ish shrink
			local okAny = false
			for tryQty = chunk, 1, -1 do
				if sm.container.canCollect( container, uuid, tryQty ) then
					sm.container.beginTransaction()
					sm.container.collect( container, uuid, tryQty, true )
					if sm.container.endTransaction() then
						placed = placed + tryQty
						remaining = remaining - tryQty
						okAny = true
					end
					break
				end
			end
			if not okAny then
				break
			end
		else
			sm.container.beginTransaction()
			sm.container.collect( container, uuid, chunk, true )
			if sm.container.endTransaction() then
				placed = placed + chunk
				remaining = remaining - chunk
			else
				break
			end
		end
	end
	return placed
end

--- Sort All: categorize nearby chest contents into category-dedicated chests.
--- When #chests >= #categories-with-items: one chest per category (no mix).
--- When fewer chests: exclusive chests for the fullest categories; leftover
--- categories SHARE the last chest (documented mixed edge case).
--- Same UUID always consolidated before placement.
local function sortAllNearbyChests( self )
	local chests = gatherNearbyChests( self )
	if #chests == 0 then
		return { ok = false, reason = "no_chests", mixed = false }
	end

	-- Aggregate all items by uuid
	local totals = {} -- key -> { uuid, quantity, category }
	for _, chest in ipairs( chests ) do
		local container = chest.container
		for slot = 0, container:getSize() - 1 do
			local item = container:getItem( slot )
			if item.quantity > 0 and item.uuid ~= sm.uuid.getNil() then
				local key = tostring( item.uuid )
				local row = totals[key]
				if not row then
					row = { uuid = item.uuid, quantity = 0, category = getItemCategory( item.uuid ) }
					totals[key] = row
				end
				row.quantity = row.quantity + item.quantity
			end
		end
	end

	-- Group by category
	local byCat = {}
	local catTotals = {}
	for _, row in pairs( totals ) do
		local cat = row.category
		byCat[cat] = byCat[cat] or {}
		byCat[cat][#byCat[cat] + 1] = row
		catTotals[cat] = ( catTotals[cat] or 0 ) + row.quantity
	end

	local catsWithItems = {}
	for _, cat in ipairs( CategoryOrder ) do
		if byCat[cat] and #byCat[cat] > 0 then
			catsWithItems[#catsWithItems + 1] = cat
		end
	end
	-- Sort categories by total quantity descending (fullest first)
	table.sort( catsWithItems, function( a, b )
		local ta, tb = catTotals[a] or 0, catTotals[b] or 0
		if ta == tb then
			return a < b
		end
		return ta > tb
	end )

	if #catsWithItems == 0 then
		return { ok = true, reason = "empty", mixed = false, categories = 0 }
	end

	-- Evacuate all chests
	for _, chest in ipairs( chests ) do
		clearContainer( chest.container )
	end

	-- Assign categories → chests
	local assignment = {} -- cat -> list of chest indices
	local mixed = false
	local nChests = #chests
	local nCats = #catsWithItems

	if nChests >= nCats then
		for i, cat in ipairs( catsWithItems ) do
			assignment[cat] = { i }
		end
		-- Extra chests become overflow for the fullest category
		if nChests > nCats then
			local primary = catsWithItems[1]
			for i = nCats + 1, nChests do
				assignment[primary][#assignment[primary] + 1] = i
			end
		end
	else
		-- Fewer chests than categories: exclusive for top (nChests-1), rest share last
		for i = 1, nChests - 1 do
			assignment[catsWithItems[i]] = { i }
		end
		local lastIdx = nChests
		for i = nChests, nCats do
			assignment[catsWithItems[i]] = { lastIdx }
		end
		if nCats > nChests then
			mixed = true
		end
	end

	-- Place items: consolidate UUID into assigned chest(s)
	local unplaced = 0
	for _, cat in ipairs( catsWithItems ) do
		local rows = byCat[cat]
		table.sort( rows, function( a, b )
			if a.quantity == b.quantity then
				return tostring( a.uuid ) < tostring( b.uuid )
			end
			return a.quantity > b.quantity
		end )
		local chestIdxs = assignment[cat] or { 1 }
		for _, row in ipairs( rows ) do
			local remaining = row.quantity
			for _, ci in ipairs( chestIdxs ) do
				if remaining <= 0 then break end
				local placed = collectInto( chests[ci].container, row.uuid, remaining )
				remaining = remaining - placed
			end
			-- Last-resort: any chest
			if remaining > 0 then
				for ci = 1, nChests do
					if remaining <= 0 then break end
					local placed = collectInto( chests[ci].container, row.uuid, remaining )
					remaining = remaining - placed
				end
			end
			unplaced = unplaced + remaining
		end
	end

	return {
		ok = true,
		mixed = mixed,
		categories = nCats,
		chests = nChests,
		unplaced = unplaced,
		cats = catsWithItems
	}
end

function ItemSorter.sv_n_sortAll( self, _, player )
	local result = sortAllNearbyChests( self )
	self.network:sendToClient( player, "cl_n_sortAllResult", result or { ok = false } )
end

function ItemSorter.cl_n_sortAllResult( self, result )
	if not result then
		return
	end
	if result.ok then
		local msg = "Sortbot: sorted by category"
		if result.mixed then
			msg = msg .. " (some categories share a chest — need more chests)"
		end
		if result.unplaced and result.unplaced > 0 then
			msg = msg .. " (some items did not fit)"
		end
		if sm.gui and sm.gui.displayAlertText then
			sm.gui.displayAlertText( msg, 4 )
		end
	else
		if sm.gui and sm.gui.displayAlertText then
			sm.gui.displayAlertText( "Sortbot: no nearby chests to sort", 3 )
		end
	end
end

function ItemSorter.client_onInteract( self, character, state )
	if state ~= true then
		return
	end
	-- Shift/crouch + Use = Sort All (no tinker API). Plain Use opens GUI.
	local crouching = false
	if character and sm.exists( character ) then
		if character.isCrouching then
			crouching = character:isCrouching()
		elseif character.isSprinting then
			-- fallback unused
		end
	end
	-- Also accept Binding "Crawl" held via getKeyBinding state if available
	if not crouching and sm.localPlayer and sm.localPlayer.getPlayer then
		local ok, pl = pcall( function() return sm.localPlayer.getPlayer() end )
		if ok and pl and pl.character and sm.exists( pl.character ) and pl.character.isCrouching then
			crouching = pl.character:isCrouching()
		end
	end
	if crouching then
		self.network:sendToServer( "sv_n_sortAll" )
		return
	end
	self.network:sendToServer( "sv_n_openStorageGui" )
end

function ItemSorter.sv_n_openStorageGui( self, _, player )
	local display = self.shape.interactable:getContainer( 1 )
	if not display then
		display = self.shape:getInteractable():addContainer( 1, OverviewMaxItems, 999999 )
	end
	local items = gatherNearbyStorage( self )
	self.sv.viewBaseline = {}
	for _, entry in ipairs( items ) do
		self.sv.viewBaseline[entry.itemId] = { uuid = entry.uuid, quantity = entry.quantity }
	end
	fillDisplay( display, items )
	self.network:sendToClient( player, "cl_n_openStorageGui" )
end

function ItemSorter.cl_n_openStorageGui( self )
	local display = self.shape.interactable:getContainer( 1 )
	if not display then
		return
	end
	self.cl = self.cl or {}
	if self.cl.gui then
		pcall( function()
			if self.cl.gui:isActive() then
				self.cl.gui:close()
			end
		end )
		self.cl.gui = nil
	end
	-- createContainerGui: aggregate nearby counts. CraftBot layout not used —
	-- createCraftBotGui is recipe-bound; no custom button slot here.
	-- Sort All: crouch + Use (no client_canTinker in vanilla).
	local gui = sm.gui.createContainerGui( true )
	gui:setContainer( "UpperGrid", display )
	gui:setText( "UpperName", "Sortbot — nearby (crouch+E = Sort All)" )
	gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
	gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
	gui:setOnCloseCallback( "cl_e_onClose" )
	gui:open()
	self.cl.gui = gui
end

function ItemSorter.cl_e_onClose( self )
	if self.cl then
		self.cl.gui = nil
	end
	self.network:sendToServer( "sv_n_closeStorageGui" )
end

function ItemSorter.sv_n_closeStorageGui( self )
	local display = self.shape.interactable:getContainer( 1 )
	local baseline = self.sv.viewBaseline or {}
	if display and sm.exists( display ) then
		for itemId, row in pairs( baseline ) do
			local still = countUuid( display, row.uuid )
			local taken = row.quantity - still
			if taken > 0 then
				spendFromNearby( self, row.uuid, taken )
			end
		end
		clearDisplay( display )
	end
	self.sv.viewBaseline = nil
end

function ItemSorter.client_onDestroy( self )
	if self.cl and self.cl.pipeEffectPlayer then
		self.cl.pipeEffectPlayer:onDestroy()
		self.cl.pipeEffectPlayer = nil
	end
	if self.cl and self.cl.gui then
		pcall( function()
			if self.cl.gui:isActive and self.cl.gui:isActive() then
				self.cl.gui:close()
			end
		end )
		self.cl.gui = nil
	end
end
