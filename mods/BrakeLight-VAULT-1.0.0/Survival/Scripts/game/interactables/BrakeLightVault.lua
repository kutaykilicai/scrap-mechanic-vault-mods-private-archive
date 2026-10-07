-- BrakeLightVault.lua — Fren Rölesi / Brake Relay (BrakeLight-VAULT 1.0.0)
--
-- Driver's Seat --(power)--> Brake Relay --(logic)--> vanilla lights
--
-- The seat cannot connect to lights (lights only take logic), but it can
-- connect to parts that take a "power" input, like engines. This part takes
-- that power input, reads the seat's forward/back steering value, and turns
-- its logic output ON while S is held (value < 0). Lights connected from
-- this part then light up like brake lights.
--
-- Self-contained: no storage, no GUI, no global hooks, no other scripts
-- touched. Only reads its own single parent.

BrakeLightVault = class()
BrakeLightVault.maxParentCount = 1
BrakeLightVault.maxChildCount = 255
BrakeLightVault.connectionInput = sm.interactable.connectionType.power
BrakeLightVault.connectionOutput = sm.interactable.connectionType.logic
BrakeLightVault.colorNormal = sm.color.new( 0xcc1a1aff )
BrakeLightVault.colorHighlight = sm.color.new( 0xff4a4aff )
BrakeLightVault.poseWeightCount = 1

-- Vanilla logic gate screen frames: 0..5 = gate icons OFF, 6..11 = same icons ON.
local UV_OFF = 1 -- "OR" icon, off
local UV_ON = 7  -- "OR" icon, lit
local BRAKE_THRESHOLD = -0.05

-- Returns the seat's forward/back value: +1 = W, -1 = S, 0 = none / nobody seated.
local function readSeatForward( parent )
	if parent == nil or not sm.exists( parent ) then
		return 0
	end
	local ok, value = pcall( parent.getSteeringPower, parent )
	if ok and type( value ) == "number" then
		return value
	end
	ok, value = pcall( parent.getPower, parent )
	if ok and type( value ) == "number" then
		return value
	end
	return 0
end

-- SERVER --

function BrakeLightVault.server_onCreate( self )
	self.sv = { braking = false }
	self.interactable:setActive( false )
	self.interactable:setPower( 0 )
end

function BrakeLightVault.server_onFixedUpdate( self, timeStep )
	local parent = self.interactable:getSingleParent()
	local braking = readSeatForward( parent ) < BRAKE_THRESHOLD
	if braking ~= self.sv.braking then
		self.sv.braking = braking
		self.interactable:setActive( braking )
		self.interactable:setPower( braking and 1 or 0 )
	end
end

-- CLIENT (visual only) --

function BrakeLightVault.client_onCreate( self )
	self.cl = { lit = nil }
	self:cl_applyVisual( false )
end

function BrakeLightVault.client_onUpdate( self, dt )
	local lit = self.interactable:isActive()
	if lit ~= self.cl.lit then
		self:cl_applyVisual( lit )
	end
end

function BrakeLightVault.cl_applyVisual( self, lit )
	self.cl.lit = lit
	self.interactable:setUvFrameIndex( lit and UV_ON or UV_OFF )
	self.interactable:setPoseWeight( 0, lit and 1 or 0 )
end

function BrakeLightVault.client_canInteract( self, character )
	local parent = self.interactable:getSingleParent()
	local status = parent ~= nil and "Seat connected" or "Connect Driver's Seat -> this"
	sm.gui.setInteractionText( "Brake Relay", status )
	sm.gui.setInteractionText( "", "S = lights ON" )
	return true
end
