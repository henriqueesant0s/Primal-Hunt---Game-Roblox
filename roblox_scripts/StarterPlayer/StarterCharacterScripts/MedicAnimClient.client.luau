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

local function rotCF(rxDeg: number, ryDeg: number, rzDeg: number): CFrame
	return CFrame.Angles(math.rad(rxDeg), math.rad(ryDeg), math.rad(rzDeg))
end

local function hasEquippedTool(): boolean
	return character:FindFirstChildOfClass("Tool") ~= nil
end

local function setBootJetFX(enabled: boolean)
	for _, footName in ipairs({"LeftFoot", "RightFoot"}) do
		local foot = character:FindFirstChild(footName)
		if foot then
			for _, desc in ipairs(foot:GetDescendants()) do
				if desc:IsA("ParticleEmitter") and string.sub(desc.Name, 1, 14) == "MedicBootJetFX" then
					desc.Enabled = enabled
				end
			end
		end
	end
end

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

if isOwner then
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then return end
		if character:GetAttribute("MedicSkinActive") ~= true then return end
		if character:GetAttribute("IsDowned") or character:GetAttribute("IsDead") then return end

		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			local now = os.clock()
			local vel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
			if now >= slideCooldownUntil and humanoid.FloorMaterial ~= Enum.Material.Air and vel.Magnitude > 5 then
				slidingUntil = now + 0.58
				slideCooldownUntil = now + 1.05
				local dir = if vel.Magnitude > 0.1 then vel.Unit else rootPart.CFrame.LookVector
				local bv = Instance.new("LinearVelocity")
				bv.Name = "MedicSlideBoost"
				local att = Instance.new("Attachment")
				att.Name = "MedicSlideAtt"
				att.Parent = rootPart
				bv.Attachment0 = att
				bv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
				bv.PrimaryTangentAxis = Vector3.xAxis
				bv.SecondaryTangentAxis = Vector3.zAxis
				bv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * 32
				bv.MaxForce = rootPart.AssemblyMass * 650
				bv.Parent = att
				task.delay(0.42, function()
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
	setBootJetFX(false)
end

character:GetAttributeChangedSignal("MedicSkinActive"):Connect(function()
	if character:GetAttribute("MedicSkinActive") ~= true then
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
	if character:GetAttribute("MedicSkinActive") ~= true then
		return
	end
	if humanoid.Health <= 0 or character:GetAttribute("IsDead") then
		setBootJetFX(false)
		return
	end

	local now = os.clock()
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

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

	local bootJetsFiring = false

	if now < slidingUntil then
		-- MEDIC SLIDE: crouched bio-pack recovery slide with boot jets braking
		currentState = "Slide"
		target.LowerTorso = CFrame.new(0, -1.04, 0.14) * rotCF(34, 12, -8)
		target.UpperTorso = rotCF(-18, -12, 6)
		target.Head = rotCF(-14, 0, 4)
		target.LeftUpperLeg = rotCF(46, 0, 4)
		target.LeftLowerLeg = rotCF(-10, 0, 0)
		target.LeftFoot = rotCF(-18, 0, 0)
		target.RightUpperLeg = rotCF(20, 10, -18)
		target.RightLowerLeg = rotCF(-88, 0, 0)
		target.RightFoot = rotCF(24, 0, 0)
		target.LeftUpperArm = rotCF(28, -10, 14)
		target.LeftLowerArm = rotCF(62, 0, 0)
		target.RightUpperArm = rotCF(-26, 0, -28)
		target.RightLowerArm = rotCF(24, 0, 0)
	elseif not grounded then
		-- MEDIC JUMP / BOOT-JET THRUSTER FLIGHT
		currentState = "Jump"
		local rising = vertVel > 1.2
		bootJetsFiring = rising
		if rising then
			target.LowerTorso = CFrame.new(0, 0.06, 0) * rotCF(-6, -4, 0)
			target.UpperTorso = rotCF(-7, 4, 0)
			target.Head = rotCF(10, 0, 0)
			target.LeftUpperLeg = rotCF(48, 0, 4)
			target.LeftLowerLeg = rotCF(-66, 0, 0)
			target.LeftFoot = rotCF(-22, 0, 0)
			target.RightUpperLeg = rotCF(16, 0, -4)
			target.RightLowerLeg = rotCF(-30, 0, 0)
			target.RightFoot = rotCF(-24, 0, 0)
			target.LeftUpperArm = rotCF(32, 0, 22)
			target.LeftLowerArm = rotCF(48, 0, 0)
			target.RightUpperArm = rotCF(24, 0, -22)
			target.RightLowerArm = rotCF(42, 0, 0)
		else
			target.LowerTorso = rotCF(-6, 0, 0)
			target.UpperTorso = rotCF(-8, 0, 0)
			target.Head = rotCF(11, 0, 0)
			target.LeftUpperLeg = rotCF(24, 0, 2)
			target.LeftLowerLeg = rotCF(-28, 0, 0)
			target.LeftFoot = rotCF(-8, 0, 0)
			target.RightUpperLeg = rotCF(20, 0, -2)
			target.RightLowerLeg = rotCF(-24, 0, 0)
			target.RightFoot = rotCF(-8, 0, 0)
			target.LeftUpperArm = rotCF(18, 0, 14)
			target.LeftLowerArm = rotCF(36, 0, 0)
			target.RightUpperArm = rotCF(18, 0, -14)
			target.RightLowerArm = rotCF(36, 0, 0)
		end
	elseif speed > 13.5 then
		-- MEDIC RUN (urgent combat-medic responder sprint)
		currentState = "Run"
		runPhase += dt * math.clamp(speed * 0.58, 7.8, 13.8)
		local s = math.sin(runPhase)
		local c = math.cos(runPhase)
		local bounce = math.abs(c) * 0.14 - 0.06
		target.LowerTorso = CFrame.new(s * 0.04, bounce, 0) * rotCF(-9, -s * 9, c * 3)
		target.UpperTorso = rotCF(-13, s * 12, -c * 3)
		target.Head = rotCF(16, -s * 3, 0)
		target.LeftUpperLeg = rotCF(s * 44 + 4, 0, 0)
		target.LeftLowerLeg = rotCF(-(44 - c * 28), 0, 0)
		target.LeftFoot = rotCF(-s * 15, 0, 0)
		target.RightUpperLeg = rotCF(-s * 44 + 4, 0, 0)
		target.RightLowerLeg = rotCF(-(44 + c * 28), 0, 0)
		target.RightFoot = rotCF(s * 15, 0, 0)
		target.LeftUpperArm = rotCF(24 - s * 22, 0, 8)
		target.LeftLowerArm = rotCF(66 + s * 6, -8, 0)
		target.RightUpperArm = rotCF(s * 38, 0, -8)
		target.RightLowerArm = rotCF(62 - s * 6, 0, 0)
	elseif speed > 0.7 then
		-- MEDIC WALK (stabilized Bio-Pack stride, left ECG forearm elevated slightly)
		currentState = "Walk"
		walkPhase += dt * math.clamp(speed * 0.52, 3.5, 8.5)
		local s = math.sin(walkPhase)
		local c = math.cos(walkPhase)
		local bob = math.abs(c) * 0.075 - 0.035
		target.LowerTorso = CFrame.new(s * 0.035, bob, 0) * rotCF(-2, -s * 5, c * 2)
		target.UpperTorso = rotCF(-3.5, s * 7, -c * 2)
		target.Head = rotCF(4, -s * 2.5, 0)
		target.LeftUpperLeg = rotCF(s * 26, 0, 0)
		target.LeftLowerLeg = rotCF(-(20 - c * 18), 0, 0)
		target.LeftFoot = rotCF(-s * 12, 0, 0)
		target.RightUpperLeg = rotCF(-s * 26, 0, 0)
		target.RightLowerLeg = rotCF(-(20 + c * 18), 0, 0)
		target.RightFoot = rotCF(s * 12, 0, 0)
		target.LeftUpperArm = rotCF(12 - s * 6, 0, 5)
		target.LeftLowerArm = rotCF(34, -10, 0)
		target.RightUpperArm = rotCF(s * 20, 0, -4)
		target.RightLowerArm = rotCF(24 - s * 4, 0, 0)
	else
		-- MEDIC IDLE (breathing readiness + subtle left ECG monitor scan)
		currentState = "Idle"
		local t = now * 2.1
		local breath = math.sin(t)
		local ecgGlance = math.max(0, math.sin(now * 0.75))
		target.UpperTorso = rotCF(-2 - breath * 1.1, 0, 0)
		target.Head = rotCF(2 + breath * 1.0 - ecgGlance * 5, ecgGlance * 8, 0)
		target.LeftUpperArm = rotCF(10 + ecgGlance * 14, 0, 5)
		target.LeftLowerArm = rotCF(28 + ecgGlance * 18, -10, 0)
		target.RightUpperArm = rotCF(4, 0, -4)
		target.RightLowerArm = rotCF(18, 0, 0)
	end

	setBootJetFX(bootJetsFiring)

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

