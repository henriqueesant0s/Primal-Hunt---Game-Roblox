--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
	return
end

local R15_MOTORS: {[string]: {part: string, joint: string}} = {
	LowerTorso = { part = "LowerTorso", joint = "Root" },
	UpperTorso = { part = "UpperTorso", joint = "Waist" },
	Head = { part = "Head", joint = "Neck" },
	LeftUpperArm = { part = "LeftUpperArm", joint = "LeftShoulder" },
	LeftLowerArm = { part = "LeftLowerArm", joint = "LeftElbow" },
	LeftHand = { part = "LeftHand", joint = "LeftWrist" },
	RightUpperArm = { part = "RightUpperArm", joint = "RightShoulder" },
	RightLowerArm = { part = "RightLowerArm", joint = "RightElbow" },
	RightHand = { part = "RightHand", joint = "RightWrist" },
	LeftUpperLeg = { part = "LeftUpperLeg", joint = "LeftHip" },
	LeftLowerLeg = { part = "LeftLowerLeg", joint = "LeftKnee" },
	LeftFoot = { part = "LeftFoot", joint = "LeftAnkle" },
	RightUpperLeg = { part = "RightUpperLeg", joint = "RightHip" },
	RightLowerLeg = { part = "RightLowerLeg", joint = "RightKnee" },
	RightFoot = { part = "RightFoot", joint = "RightAnkle" },
}

local motors: {[string]: Motor6D} = {}
for key, info in pairs(R15_MOTORS) do
	local p = character:FindFirstChild(info.part)
	local m = if p then p:FindFirstChild(info.joint) else nil
	if m and m:IsA("Motor6D") then
		motors[key] = m
	end
end

local localPlayer = Players:GetPlayerFromCharacter(character)
local isOwner = localPlayer == Players.LocalPlayer

-- Coordinate note: in Roblox R15 CFrame space, X=Right, Y=Up, Z=Back (-Z=Forward)
-- Pitch forward (-Z) = CFrame.Angles(-rad, 0, 0) for limbs? Check right-hand rule around +X:
-- Thumb along +X (Right): fingers curl from +Y toward +Z (Backward)!
-- So:
--   +theta around +X tilts +Y (Up) -> +Z (Backward), and -Y (Down) -> -Z (Forward)!
--   Wait: for upward parts (Torso/Head), +theta around +X pitches BACKWARD; -theta around +X pitches FORWARD!
--   For downward limbs (Arms/Legs), +theta around +X swings FORWARD (-Z); -theta around +X swings BACKWARD (+Z)!
--   Therefore Knees (LowerLeg) bend backward (+Z) with NEGATIVE X angle; Elbows (LowerArm) bend forward (-Z) with POSITIVE X angle!

local function rotCF(rxDeg: number, ryDeg: number, rzDeg: number): CFrame
	return CFrame.Angles(math.rad(rxDeg), math.rad(ryDeg), math.rad(rzDeg))
end

local function hasEquippedTool(): boolean
	return character:FindFirstChildOfClass("Tool") ~= nil
end

-- Animation state variables
local walkPhase = 0
local runPhase = 0
local currentState = "Idle"
local slidingUntil = 0
local slideCooldownUntil = 0
local sprintHeld = false
local baseWalkSpeed: number? = nil
local currentPoses: {[string]: CFrame} = {}

for key in pairs(motors) do
	currentPoses[key] = CFrame.identity
end

-- Sprint & Slide controls for Assault skin owner only
if isOwner then
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then return end
		if character:GetAttribute("AssaultSkinActive") ~= true then return end
		if character:GetAttribute("IsDowned") or character:GetAttribute("IsDead") then return end

		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			local now = os.clock()
			local vel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
			if now >= slideCooldownUntil and humanoid.FloorMaterial ~= Enum.Material.Air and vel.Magnitude > 5 then
				slidingUntil = now + 0.62
				slideCooldownUntil = now + 1.05
				local dir = if vel.Magnitude > 0.1 then vel.Unit else rootPart.CFrame.LookVector
				local bv = Instance.new("LinearVelocity")
				bv.Name = "AssaultSlideBoost"
				local att = Instance.new("Attachment")
				att.Name = "AssaultSlideAtt"
				att.Parent = rootPart
				bv.Attachment0 = att
				bv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
				bv.PrimaryTangentAxis = Vector3.xAxis
				bv.SecondaryTangentAxis = Vector3.zAxis
				bv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * 32
				bv.MaxForce = rootPart.AssemblyMass * 650
				bv.Parent = att
				task.delay(0.45, function()
					if bv.Parent then bv:Destroy() end
					if att.Parent then att:Destroy() end
				end)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = false
		end
	end)
end

local function clearCustomTransforms()
	for _, m in pairs(motors) do
		m.Transform = CFrame.identity
	end
end

character:GetAttributeChangedSignal("AssaultSkinActive"):Connect(function()
	if character:GetAttribute("AssaultSkinActive") ~= true then
		sprintHeld = false
		slidingUntil = 0
		if baseWalkSpeed ~= nil then
			humanoid.WalkSpeed = baseWalkSpeed
			baseWalkSpeed = nil
		end
		clearCustomTransforms()
	end
end)

RunService.Stepped:Connect(function(_, dt: number)
	if character:GetAttribute("AssaultSkinActive") ~= true then
		return
	end
	if humanoid.Health <= 0 or character:GetAttribute("IsDead") then
		return
	end

	local now = os.clock()
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

	-- Ground sprint boost when Shift held (doesn't touch airborne Jetpack dodge)
	if isOwner then
		if sprintHeld and grounded and not character:GetAttribute("IsDowned") then
			if baseWalkSpeed == nil then
				baseWalkSpeed = humanoid.WalkSpeed
			end
			if humanoid.WalkSpeed < 22 then
				humanoid.WalkSpeed = 22
			end
		elseif baseWalkSpeed ~= nil then
			humanoid.WalkSpeed = baseWalkSpeed
			baseWalkSpeed = nil
		end
	end

	local horizVel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
	local speed = horizVel.Magnitude
	local vertVel = rootPart.AssemblyLinearVelocity.Y

	-- Refresh motor table if any Motor6D was swapped
	for key, info in pairs(R15_MOTORS) do
		if not motors[key] or motors[key].Parent == nil then
			local p = character:FindFirstChild(info.part)
			local m = if p then p:FindFirstChild(info.joint) else nil
			if m and m:IsA("Motor6D") then
				motors[key] = m
			end
		end
	end

	local target: {[string]: CFrame} = {}
	for key in pairs(motors) do
		target[key] = CFrame.identity
	end

	if now < slidingUntil then
		-- ASSAULT SLIDE: low power-slide, lead Left leg extended forward (-Z), Right knee tucked
		currentState = "Slide"
		target.LowerTorso = CFrame.new(0, -1.08, 0.16) * rotCF(36, 14, -10)
		target.UpperTorso = rotCF(-20, -14, 6)
		target.Head = rotCF(-16, 0, 4)
		target.LeftUpperLeg = rotCF(46, 0, 4)
		target.LeftLowerLeg = rotCF(-10, 0, 0)
		target.LeftFoot = rotCF(-16, 0, 0)
		target.RightUpperLeg = rotCF(22, 12, -20)
		target.RightLowerLeg = rotCF(-92, 0, 0)
		target.RightFoot = rotCF(26, 0, 0)
		target.LeftUpperArm = rotCF(32, -14, 16)
		target.LeftLowerArm = rotCF(68, 0, 0)
		target.RightUpperArm = rotCF(-30, 0, -32)
		target.RightLowerArm = rotCF(22, 0, 0)
	elseif not grounded then
		-- ASSAULT JUMP / JETPACK AIRBORNE
		currentState = "Jump"
		local rising = vertVel > 2
		if rising then
			target.LowerTorso = CFrame.new(0, 0.05, 0) * rotCF(-4, -6, 0)
			target.UpperTorso = rotCF(-8, 6, 0)
			target.Head = rotCF(10, 0, 0)
			target.LeftUpperLeg = rotCF(56, 0, 4)
			target.LeftLowerLeg = rotCF(-78, 0, 0)
			target.LeftFoot = rotCF(-10, 0, 0)
			target.RightUpperLeg = rotCF(22, 0, -4)
			target.RightLowerLeg = rotCF(-48, 0, 0)
			target.RightFoot = rotCF(-16, 0, 0)
			target.LeftUpperArm = rotCF(38, 0, 22)
			target.LeftLowerArm = rotCF(52, 0, 0)
			target.RightUpperArm = rotCF(28, 0, -22)
			target.RightLowerArm = rotCF(46, 0, 0)
		else
			target.LowerTorso = rotCF(-6, 0, 0)
			target.UpperTorso = rotCF(-10, 0, 0)
			target.Head = rotCF(12, 0, 0)
			target.LeftUpperLeg = rotCF(26, 0, 2)
			target.LeftLowerLeg = rotCF(-24, 0, 0)
			target.LeftFoot = rotCF(6, 0, 0)
			target.RightUpperLeg = rotCF(22, 0, -2)
			target.RightLowerLeg = rotCF(-22, 0, 0)
			target.RightFoot = rotCF(6, 0, 0)
			target.LeftUpperArm = rotCF(18, 0, 14)
			target.LeftLowerArm = rotCF(35, 0, 0)
			target.RightUpperArm = rotCF(18, 0, -14)
			target.RightLowerArm = rotCF(35, 0, 0)
		end
	elseif speed > 13.5 then
		-- ASSAULT RUN (13.5+ studs/s)
		currentState = "Run"
		runPhase += dt * math.clamp(speed * 0.56, 7.5, 13.5)
		local s = math.sin(runPhase)
		local c = math.cos(runPhase)
		local bounce = math.abs(c) * 0.14 - 0.06
		target.LowerTorso = CFrame.new(s * 0.04, bounce, 0) * rotCF(-8, -s * 9, c * 3)
		target.UpperTorso = rotCF(-12, s * 12, -c * 3)
		target.Head = rotCF(16, -s * 3, 0)
		target.LeftUpperLeg = rotCF(s * 42 + 4, 0, 0)
		target.LeftLowerLeg = rotCF(-(42 - c * 28), 0, 0)
		target.LeftFoot = rotCF(-s * 12, 0, 0)
		target.RightUpperLeg = rotCF(-s * 42 + 4, 0, 0)
		target.RightLowerLeg = rotCF(-(42 + c * 28), 0, 0)
		target.RightFoot = rotCF(s * 12, 0, 0)
		target.LeftUpperArm = rotCF(-s * 36, 0, 6)
		target.LeftLowerArm = rotCF(60 + s * 6, 0, 0)
		target.RightUpperArm = rotCF(s * 36, 0, -6)
		target.RightLowerArm = rotCF(60 - s * 6, 0, 0)
	elseif speed > 0.7 then
		-- ASSAULT WALK (heavy tactical stride)
		currentState = "Walk"
		walkPhase += dt * math.clamp(speed * 0.52, 3.5, 8.5)
		local s = math.sin(walkPhase)
		local c = math.cos(walkPhase)
		local bob = math.abs(c) * 0.08 - 0.04
		target.LowerTorso = CFrame.new(s * 0.04, bob, 0) * rotCF(-2, -s * 5, c * 2)
		target.UpperTorso = rotCF(-4, s * 7, -c * 2)
		target.Head = rotCF(4, -s * 2, 0)
		target.LeftUpperLeg = rotCF(s * 26, 0, 0)
		target.LeftLowerLeg = rotCF(-(22 - c * 18), 0, 0)
		target.LeftFoot = rotCF(-s * 10, 0, 0)
		target.RightUpperLeg = rotCF(-s * 26, 0, 0)
		target.RightLowerLeg = rotCF(-(22 + c * 18), 0, 0)
		target.RightFoot = rotCF(s * 10, 0, 0)
		target.LeftUpperArm = rotCF(-s * 19, 0, 4)
		target.LeftLowerArm = rotCF(24, 0, 0)
		target.RightUpperArm = rotCF(s * 19, 0, -4)
		target.RightLowerArm = rotCF(24, 0, 0)
	else
		-- ASSAULT IDLE (breathing combat readiness)
		currentState = "Idle"
		local t = now * 2.1
		local breath = math.sin(t)
		target.UpperTorso = rotCF(-2 - breath * 1.2, 0, 0)
		target.Head = rotCF(2 + breath * 1.0, 0, 0)
		target.LeftUpperArm = rotCF(4, 0, 4)
		target.LeftLowerArm = rotCF(18, 0, 0)
		target.RightUpperArm = rotCF(4, 0, -4)
		target.RightLowerArm = rotCF(18, 0, 0)
	end

	-- Keep right arm raised when holding a weapon Tool
	if hasEquippedTool() and currentState ~= "Slide" then
		target.RightUpperArm = rotCF(78, 0, -8)
		target.RightLowerArm = rotCF(18, 0, 0)
	end

	local alpha = math.clamp(dt * (if currentState == "Slide" then 18 else 14), 0, 1)
	for key, motor in pairs(motors) do
		local goal = target[key] or CFrame.identity
		local cur = currentPoses[key] or CFrame.identity
		local blended = cur:Lerp(goal, alpha)
		currentPoses[key] = blended
		motor.Transform = blended
	end
end)

