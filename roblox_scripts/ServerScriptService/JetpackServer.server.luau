--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Audio = require(ReplicatedStorage:WaitForChild("HunterAudio"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local gameRemotes = remotes:WaitForChild("GameRemotes")
local actionEvent = remotes:WaitForChild("HunterRemotes"):WaitForChild("JetpackAction") :: RemoteEvent
local HUNTERS: {[string]: boolean} = {Assault = true, Medic = true, Trapper = true, Support = true}
local CAPACITY = 100
local DRAIN_PER_SECOND = 20
local REGEN_PER_SECOND = 25
local REGEN_DELAY = 1.5
local DODGE_COST = 25
local DODGE_DURATION = 0.22
local DODGE_SPEED = 68
local ASCENT_SPEED = 28

type Flight = {
	body: Model, root: BasePart, humanoid: Humanoid, fuel: number, groundedTime: number,
	attachment: Attachment?, lift: LinearVelocity?, dash: LinearVelocity?,
	dashUntil: number, requestedUntil: number, publishedAt: number,
}
local flights: {[Player]: Flight} = {}
local lastStart: {[Player]: number} = {}
local lastDodge: {[Player]: number} = {}

local function eligible(body: Model): boolean
	local role = body:GetAttribute("Role")
	return gameRemotes:GetAttribute("MatchState") == "ActiveHunt"
		and gameRemotes:GetAttribute("RoundClosed") ~= true
		and typeof(role) == "string" and HUNTERS[role] == true
		and body:GetAttribute("IsDead") ~= true and body:GetAttribute("IsDowned") ~= true
end

local function stopLift(f: Flight)
	f.requestedUntil = 0
	if f.attachment then Audio.StopLoop(f.attachment, "JetpackThrust") end
	if f.lift then f.lift:Destroy() end
	f.lift = nil
end

local function stopDash(f: Flight)
	if f.dash then f.dash:Destroy() end
	f.dash = nil
end

local function release(player: Player)
	local f = flights[player]
	if f then
		stopLift(f)
		stopDash(f)
		if f.attachment then f.attachment:Destroy() end
		flights[player] = nil
	end
end

local function flightFor(player: Player): Flight?
	local body = player.Character
	local current = flights[player]
	if not body or not body:IsDescendantOf(workspace) or not eligible(body) then
		if current then release(player) end
		return nil
	end
	if current and current.body == body and current.root.Parent == body
		and current.humanoid.Parent == body then return current end
	if current then release(player) end
	local root = body:FindFirstChild("HumanoidRootPart")
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then return nil end
	local initial = body:GetAttribute("JetpackFuel")
	local fuel = if typeof(initial) == "number" then math.clamp(initial, 0, CAPACITY) else CAPACITY
	local f: Flight = {body = body, root = root, humanoid = humanoid, fuel = fuel, groundedTime = 0,
		attachment = nil, lift = nil, dash = nil, dashUntil = 0, requestedUntil = 0, publishedAt = 0}
	body:SetAttribute("JetpackFuel", fuel)
	flights[player] = f
	return f
end

local function canMove(f: Flight): boolean
	local state = f.humanoid:GetState()
	return not f.root.Anchored and f.humanoid.Health > 0 and not f.humanoid.Sit
		and state ~= Enum.HumanoidStateType.Swimming and state ~= Enum.HumanoidStateType.Climbing
end

local function newMotor(f: Flight, name: string): LinearVelocity
	local attachment = f.attachment
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "HunterJetpackAttachment"
		attachment.Parent = f.root
		f.attachment = attachment
	end
	local motor = Instance.new("LinearVelocity")
	motor.Name = name
	motor.Attachment0 = attachment
	motor.RelativeTo = Enum.ActuatorRelativeTo.World
	motor.ForceLimitsEnabled = true
	motor.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	return motor
end

local function startLift(f: Flight)
	local motor = newMotor(f, "HunterJetpackLift")
	motor.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	motor.LineDirection = Vector3.yAxis
	motor.LineVelocity = ASCENT_SPEED
	motor.MaxForce = f.root.AssemblyMass * (workspace.Gravity + 110)
	motor.Parent = f.root
	f.lift = motor
	f.requestedUntil = 0
	Audio.StartLoop(f.attachment, "JetpackThrust")
end

local function publish(f: Flight, now: number)
	f.body:SetAttribute("JetpackFuel", math.round(f.fuel * 10) / 10)
	f.publishedAt = now
end

actionEvent.OnServerEvent:Connect(function(player: Player, action: unknown, direction: unknown)
	if action == "StopThrust" then
		local f = flights[player]
		if f then stopLift(f) end
		return
	end
	if action ~= "StartThrust" and action ~= "Dodge" then return end
	local now = os.clock()
	local requests = if action == "Dodge" then lastDodge else lastStart
	if now - (requests[player] or -math.huge) < 0.08 then return end
	requests[player] = now
	local f = flightFor(player)
	if not f or not canMove(f) then return end
	if action == "StartThrust" then
		if not f.lift and f.fuel > 0 then
			-- Let the server observe a just-started jump before applying lift.
			f.requestedUntil = now + 0.45
		end
		return
	end
	if f.humanoid.FloorMaterial ~= Enum.Material.Air or f.fuel < DODGE_COST
		or f.dash or typeof(direction) ~= "Vector3" then return end
	local length = direction.Magnitude
	if not (length >= 0.95 and length <= 1.05 and math.abs(direction.Y) <= 0.02) then return end
	local horizontal = Vector2.new(direction.X, direction.Z).Unit
	local motor = newMotor(f, "HunterJetpackDodge")
	motor.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	motor.PrimaryTangentAxis = Vector3.xAxis
	motor.SecondaryTangentAxis = Vector3.zAxis
	motor.PlaneVelocity = horizontal * DODGE_SPEED
	motor.MaxForce = f.root.AssemblyMass * 900
	motor.Parent = f.root
	f.dash = motor
	f.dashUntil = now + DODGE_DURATION
	f.fuel -= DODGE_COST
	Audio.PlayAtPart(f.root, "JetpackDodge", 0.05)
	publish(f, now)
	if f.fuel <= 0 then stopLift(f) end
end)

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local f = flightFor(player)
		if not f then continue end
		local grounded = f.humanoid.FloorMaterial ~= Enum.Material.Air
		local movable = canMove(f)
		if f.dash and (grounded or not movable or now >= f.dashUntil) then stopDash(f) end
		if f.lift and (grounded or not movable) then stopLift(f) end
		if not movable then f.requestedUntil = 0 end
		if f.requestedUntil > now and not grounded and not f.lift and f.fuel > 0 then startLift(f) end
		local before = f.fuel
		if f.lift then
			f.fuel = math.max(0, f.fuel - DRAIN_PER_SECOND * dt)
			if f.fuel == 0 then stopLift(f) end
		end
		if grounded and movable then
			f.groundedTime += dt
			local regenTime = math.clamp(f.groundedTime - REGEN_DELAY, 0, dt)
			f.fuel = math.min(CAPACITY, f.fuel + REGEN_PER_SECOND * regenTime)
		else
			f.groundedTime = 0
		end
		if f.fuel ~= before and (now - f.publishedAt >= 0.1 or f.fuel == 0 or f.fuel == CAPACITY) then
			publish(f, now)
		elseif f.fuel == before and now - f.publishedAt >= 0.1 and
			f.body:GetAttribute("JetpackFuel") ~= math.round(f.fuel * 10) / 10 then
			publish(f, now)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	release(player)
	lastStart[player] = nil
	lastDodge[player] = nil
end)
