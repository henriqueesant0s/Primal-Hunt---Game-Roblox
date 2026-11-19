--!strict
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

local STEP_SFX = "rbxassetid://9114362401"
local SLASH_SFX = "rbxassetid://9119073323"
local BREATH_SFX = "rbxassetid://9119386548"

local MOTOR_NAMES = {
	"RootMotor", "WaistMotor", "NeckMotor", "CrownLMotor", "CrownRMotor",
	"ShoulderUpLMotor", "ElbowUpLMotor", "ShoulderUpRMotor", "ElbowUpRMotor",
	"ShoulderLoLMotor", "ShoulderLoRMotor",
	"Tent0Motor", "Tent1Motor", "Tent2Motor", "Tent3Motor", "Tent4Motor", "Tent5Motor",
}

local motors: { [string]: Motor6D } = {}
local currentPoses: { [string]: CFrame } = {}
local lastAction = ""
local actionStarted = 0
local slashParity = 1
local stridePhase = 0
local lastStepQuarter = -1

local function rot(rxDeg: number, ryDeg: number, rzDeg: number): CFrame
	return CFrame.Angles(math.rad(rxDeg), math.rad(ryDeg), math.rad(rzDeg))
end

local function resolveMotors(): boolean
	local outfit = character:FindFirstChild("MonsterAbyssalOutfit")
	if not outfit then
		return false
	end
	local allFound = true
	for _, mName in ipairs(MOTOR_NAMES) do
		local m = motors[mName]
		if not m or not m:IsDescendantOf(outfit) then
			local found = outfit:FindFirstChild(mName, true)
			if found and found:IsA("Motor6D") then
				motors[mName] = found
				if not currentPoses[mName] then
					currentPoses[mName] = CFrame.identity
				end
			else
				allFound = false
			end
		end
	end
	return allFound
end

local function playSpatialSFX(soundId: string, volume: number, speed: number, minDist: number, maxDist: number)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = minDist
	s.RollOffMaxDistance = maxDist
	s.Parent = rootPart
	s:Play()
	Debris:AddItem(s, 3.5)
end

local breatheLoop = Instance.new("Sound")
breatheLoop.Name = "MonsterAbyssalBreathing"
breatheLoop.SoundId = BREATH_SFX
breatheLoop.Looped = true
breatheLoop.Volume = 0
breatheLoop.PlaybackSpeed = 0.72
breatheLoop.RollOffMode = Enum.RollOffMode.InverseTapered
breatheLoop.RollOffMinDistance = 12
breatheLoop.RollOffMaxDistance = 90
breatheLoop.Parent = rootPart

local LocalPlayer = Players.LocalPlayer
local appliedCamZoom = false
local syncedStageCam = 0
character:GetAttributeChangedSignal("Role"):Connect(function()
	if character:GetAttribute("Role") ~= "Monster" then
		table.clear(motors)
		table.clear(currentPoses)
		if appliedCamZoom and LocalPlayer and LocalPlayer.Character == character then
			appliedCamZoom = false
			syncedStageCam = 0
			LocalPlayer.CameraMaxZoomDistance = 12
			LocalPlayer.CameraMinZoomDistance = 0.5
			humanoid.CameraOffset = Vector3.zero
		end
		if breatheLoop.IsPlaying then
			breatheLoop:Stop()
		end
	end
end)

RunService.Stepped:Connect(function(_, dt: number)
	if character:GetAttribute("Role") ~= "Monster" or character:GetAttribute("MonsterSkinActive") ~= true then
		if breatheLoop.IsPlaying then
			breatheLoop:Stop()
		end
		return
	end

	if humanoid.Health <= 0 or character:GetAttribute("IsDead") then
		if breatheLoop.IsPlaying then
			breatheLoop:Stop()
		end
		return
	end

	if not resolveMotors() then
		return
	end

	local stage = tonumber(character:GetAttribute("Stage")) or 1
	if LocalPlayer and LocalPlayer.Character == character then
		if not appliedCamZoom then
			appliedCamZoom = true
			LocalPlayer.CameraMaxZoomDistance = 68
			LocalPlayer.CameraMinZoomDistance = 14
		end
		if syncedStageCam ~= stage then
			syncedStageCam = stage
			local targetCamY = if stage >= 3 then 11.2 elseif stage == 2 then 8.5 else 6.2
			humanoid.CameraOffset = Vector3.new(0, targetCamY, 0)
		end
	end

	if not breatheLoop.IsPlaying then
		breatheLoop:Play()
	end

	local now = os.clock()
	local scale = math.max(1, character:GetScale())
	local stage = tonumber(character:GetAttribute("Stage")) or 1
	local isStealth = character:GetAttribute("IsStealth") == true
	local isEating = character:GetAttribute("IsEating") == true
	local isEvolving = character:GetAttribute("IsEvolving") == true
	local actionAttr = character:GetAttribute("MonsterAction")
	local action = if typeof(actionAttr) == "string" then actionAttr else ""

	if action ~= lastAction then
		lastAction = action
		actionStarted = now
		if action == "ClawSlash" then
			slashParity = -slashParity
			playSpatialSFX(SLASH_SFX, 0.72, 0.72 + (math.random() * 0.14), 14, 140)
		end
	end

	breatheLoop.Volume = if isStealth then 0.06 else (0.18 + stage * 0.04)

	local horizVel = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
	local speed = horizVel.Magnitude
	local vertVel = rootPart.AssemblyLinearVelocity.Y
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

	local target: { [string]: CFrame } = {}
	for _, mName in ipairs(MOTOR_NAMES) do
		target[mName] = CFrame.identity
	end

	local blendRate = 11

	-- Tentacle coiling helper (travelling sinusoidal waves along the 6 radial tendrils)
	local function setTentacles(phase: number, swingAmp: number, flareDeg: number, liftY: number)
		for ti = 0, 5 do
			local signSide = if (ti % 2 == 0) then 1 else -1
			local wave = math.sin(phase + ti * 1.15)
			local pitch = flareDeg + wave * swingAmp
			local yaw = signSide * math.cos(phase * 0.7 + ti * 1.4) * (swingAmp * 0.8)
			local roll = signSide * flareDeg * 0.35 + math.sin(phase * 0.9 + ti) * (swingAmp * 0.55)
			target["Tent" .. tostring(ti) .. "Motor"] = CFrame.new(0, liftY * 0.15, 0) * rot(pitch, yaw, roll)
		end
	end

	local function setCrown(phase: number, flareDeg: number, whipAmp: number)
		local w = math.sin(phase) * whipAmp
		local r = math.cos(phase * 0.85) * (whipAmp * 0.65)
		target.CrownLMotor = rot(flareDeg * 0.3 + r, w * 0.5, flareDeg + w)
		target.CrownRMotor = rot(flareDeg * 0.3 - r, -w * 0.5, -flareDeg - w)
	end

	if isEvolving then
		-- 2-PHASE NEST METAMORPHOSIS: 0..3.5s coiled fetal cocoon -> 3.5..5.0s roaring apex burst
		blendRate = 11
		local t = now - actionStarted
		local vibe = math.sin(now * 46) * 5.0
		if t < 3.5 then
			local curl = math.clamp(t / 3.5, 0, 1)
			target.RootMotor = CFrame.new(0, (-0.35 + curl * 0.45) * scale, 0) * rot(-18 - curl * 10, vibe * 0.25, 0)
			target.WaistMotor = rot(-26 + vibe * 0.4, math.sin(now * 14) * 4, 0)
			target.NeckMotor = rot(-24 + vibe, 0, 0)
			target.ShoulderUpLMotor = rot(-14, -44, 58)
			target.ElbowUpLMotor = rot(18, -56, 18)
			target.ShoulderUpRMotor = rot(-14, 44, -58)
			target.ElbowUpRMotor = rot(18, 56, -18)
			target.ShoulderLoLMotor = rot(-12, -38, 42)
			target.ShoulderLoRMotor = rot(-12, 38, -42)
			setCrown(now * 16, -24, 10)
			setTentacles(now * 12, 20, -28, 0.2)
		else
			target.RootMotor = CFrame.new(0, 0.78 * scale, 0) * rot(18 + vibe * 0.25, 0, 0)
			target.WaistMotor = rot(22 + vibe * 0.5, math.sin(now * 20) * 6, 0)
			target.NeckMotor = rot(24 + vibe, 0, 0)
			target.ShoulderUpLMotor = rot(18, 32, -26)
			target.ElbowUpLMotor = rot(20, -16, -12)
			target.ShoulderUpRMotor = rot(18, -32, 26)
			target.ElbowUpRMotor = rot(20, 16, 12)
			target.ShoulderLoLMotor = rot(24, 24, -18)
			target.ShoulderLoRMotor = rot(24, -24, 18)
			setCrown(now * 18, 42, 22)
			setTentacles(now * 14, 28, 22, 0.45)
		end

	elseif action == "ClawSlash" then
		-- 3-HIT CRUEL EXECUTIONER COMBO (SlashCombo 1: Right Cleave, 2: Left Cross-Rend, 3: 4-Arm Overhead Slam)
		blendRate = 26
		local combo = tonumber(character:GetAttribute("SlashCombo")) or 1
		local dur = if combo == 3 then 0.36 else 0.28
		local u = math.clamp((now - actionStarted) / dur, 0, 1)
		local windup = if u < 0.22 then (u / 0.22) else 1
		local swing = if u < 0.22 then -1.0 else math.sin(((u - 0.22) / 0.78) * math.pi)

		if combo == 3 then
			-- Combo Hit 3: Colossal 4-Arm Overhead Executioner Slam
			target.RootMotor = CFrame.new(0, (if u < 0.3 then 0.45 else -0.45) * scale, -0.45 * swing * scale) * rot(-22 * swing, 0, 0)
			target.WaistMotor = rot(-28 * swing, 0, 0)
			target.NeckMotor = rot(16 * swing, 0, 0)
			target.ShoulderUpLMotor = rot(42 * swing, -36 * swing, 28 - 44 * math.max(0, swing))
			target.ElbowUpLMotor = rot(22, -46 * math.max(0.2, swing), 16)
			target.ShoulderUpRMotor = rot(42 * swing, 36 * swing, -28 + 44 * math.max(0, swing))
			target.ElbowUpRMotor = rot(22, 46 * math.max(0.2, swing), -16)
			target.ShoulderLoLMotor = rot(34 * swing, -30 * swing, 24)
			target.ShoulderLoRMotor = rot(34 * swing, 30 * swing, -24)
		elseif combo == 1 then
			target.RootMotor = CFrame.new(0, 0.06 * scale, -0.35 * swing * scale) * rot(-12 * swing, 26 * swing, -7 * swing)
			target.WaistMotor = rot(-18 * swing, 32 * swing, 10 * swing)
			target.NeckMotor = rot(10 * swing, -18 * swing, 0)
			target.ShoulderUpRMotor = rot(36 * swing, 52 * swing - 18 * (1 - windup), -38 + 26 * math.max(0, swing))
			target.ElbowUpRMotor = rot(20, 44 * math.max(0.2, swing), -14)
			target.ShoulderLoRMotor = rot(30 * swing, 40 * swing, -28)
			target.ShoulderUpLMotor = rot(8, -22, 48)
			target.ElbowUpLMotor = rot(12, -28, 14)
			target.ShoulderLoLMotor = rot(8, -16, 34)
		else
			target.RootMotor = CFrame.new(0, 0.06 * scale, -0.35 * swing * scale) * rot(-12 * swing, -26 * swing, 7 * swing)
			target.WaistMotor = rot(-18 * swing, -32 * swing, -10 * swing)
			target.NeckMotor = rot(10 * swing, 18 * swing, 0)
			target.ShoulderUpLMotor = rot(36 * swing, -52 * swing + 18 * (1 - windup), 38 - 26 * math.max(0, swing))
			target.ElbowUpLMotor = rot(20, -44 * math.max(0.2, swing), 14)
			target.ShoulderLoLMotor = rot(30 * swing, -40 * swing, 28)
			target.ShoulderUpRMotor = rot(8, 22, -48)
			target.ElbowUpRMotor = rot(12, 28, -14)
			target.ShoulderLoRMotor = rot(8, 16, -34)
		end
		setCrown(now * 16, 22, 14)
		setTentacles(now * 12, 18, -12, 0.15)

	elseif action == "LeapSmash" then
		-- SKILL [1] LEAP SMASH: Coiled leap into crashing 4-arm seismic slam
		blendRate = 18
		local air = math.clamp(vertVel * 0.04, -1, 1)
		local slam = if grounded then 1 else 0
		target.RootMotor = CFrame.new(0, (if grounded then -0.45 else 0.35) * scale, 0) * rot(if grounded then -24 else (16 * air), 0, 0)
		target.WaistMotor = rot(if grounded then -26 else (16 * air), 0, 0)
		target.NeckMotor = rot(if grounded then 18 else -12, 0, 0)
		local armDrop = if grounded then 56 else -22
		local armFwd = if grounded then 48 else -18
		target.ShoulderUpLMotor = rot(18, -armFwd, armDrop)
		target.ElbowUpLMotor = rot(16, -34, 12)
		target.ShoulderUpRMotor = rot(18, armFwd, -armDrop)
		target.ElbowUpRMotor = rot(16, 34, -12)
		target.ShoulderLoLMotor = rot(14, -armFwd * 0.85, armDrop * 0.78)
		target.ShoulderLoRMotor = rot(14, armFwd * 0.85, -armDrop * 0.78)
		setCrown(now * 16, 26, 16)
		setTentacles(now * 12, 20, if grounded then -20 else 10, 0.1)

	elseif action == "FeralCharge" then
		-- SKILL [2] FERAL CHARGE: Low ramming bull posture with thrashing claws
		blendRate = 20
		local thrash = math.sin(now * 24)
		target.RootMotor = CFrame.new(0, -0.25 * scale, 0) * rot(-22, thrash * 8, 0)
		target.WaistMotor = rot(-18, -thrash * 14, thrash * 5)
		target.NeckMotor = rot(26, thrash * 6, 0)
		target.ShoulderUpLMotor = rot(24, -36 - thrash * 34, 42)
		target.ElbowUpLMotor = rot(22, -36, 12)
		target.ShoulderUpRMotor = rot(24, 36 - thrash * 34, -42)
		target.ElbowUpRMotor = rot(22, 36, -12)
		target.ShoulderLoLMotor = rot(18, -28 + thrash * 28, 30)
		target.ShoulderLoRMotor = rot(18, 28 + thrash * 28, -30)
		setCrown(now * 18, -14, 14)
		setTentacles(now * 18, 26, -16, 0.2)

	elseif action == "AcidBreath" then
		-- SKILL [3] ACID BREATH: Wide-flared crown, arched ribcage projecting forward
		blendRate = 16
		local vib = math.sin(now * 48) * 3.5
		target.RootMotor = rot(10, 0, 0)
		target.WaistMotor = rot(14 + vib * 0.3, 0, 0)
		target.NeckMotor = rot(-14 + vib, 0, 0)
		target.ShoulderUpLMotor = rot(-10, 18, 26)
		target.ElbowUpLMotor = rot(18, -22, 16)
		target.ShoulderUpRMotor = rot(-10, -18, -26)
		target.ElbowUpRMotor = rot(18, 22, -16)
		target.ShoulderLoLMotor = rot(10, 12, 18)
		target.ShoulderLoRMotor = rot(10, -12, -18)
		setCrown(now * 20, 36, 20)
		setTentacles(now * 14, 22, -12, 0.1)

	elseif action == "Climb" then
		-- WALL CLIMB: rapid 4-arm alternating claw scrambling
		blendRate = 18
		local cl = math.sin(now * 14)
		target.RootMotor = rot(-10, cl * 6, 0)
		target.WaistMotor = rot(-10, -cl * 10, 0)
		target.NeckMotor = rot(22, 0, 0)
		target.ShoulderUpLMotor = rot(20, -38 - cl * 38, 24 - cl * 24)
		target.ElbowUpLMotor = rot(24, -44, 16)
		target.ShoulderUpRMotor = rot(20, 38 - cl * 38, -24 - cl * 24)
		target.ElbowUpRMotor = rot(24, 44, -16)
		target.ShoulderLoLMotor = rot(18, -30 + cl * 32, 22)
		target.ShoulderLoRMotor = rot(18, 30 + cl * 32, -22)
		setCrown(now * 12, 8, 10)
		setTentacles(now * 14, 22, -14, 0.1)

	elseif isEating then
		-- DEVOUR BIOMASS ([E]): crouched feasting lunge + tearing claws
		blendRate = 12
		local tear = math.sin(now * 11)
		target.RootMotor = CFrame.new(0, -0.75 * scale, 0) * rot(-28 + tear * 5, 0, 0)
		target.WaistMotor = rot(-24 + tear * 7, tear * 10, 0)
		target.NeckMotor = rot(-18 - tear * 10, tear * 8, 0)
		target.ShoulderUpLMotor = rot(26 + tear * 18, -42, 48)
		target.ElbowUpLMotor = rot(24, -48 - tear * 16, 18)
		target.ShoulderUpRMotor = rot(26 - tear * 18, 42, -48)
		target.ElbowUpRMotor = rot(24, 48 - tear * 16, -18)
		target.ShoulderLoLMotor = rot(22, -32, 34)
		target.ShoulderLoRMotor = rot(22, 32, -34)
		setCrown(now * 9, 6, 8)
		setTentacles(now * 6, 14, -14, 0.1)

	elseif not grounded then
		-- MID-AIR FALL / JUMP
		blendRate = 10
		local pitch = math.clamp(vertVel * 0.45, -18, 18)
		target.RootMotor = rot(pitch * 0.5, 0, 0)
		target.WaistMotor = rot(-pitch * 0.4, 0, 0)
		target.NeckMotor = rot(pitch * 0.35, 0, 0)
		target.ShoulderUpLMotor = rot(10, -24, 34 - pitch * 0.6)
		target.ElbowUpLMotor = rot(14, -32, 12)
		target.ShoulderUpRMotor = rot(10, 24, -34 + pitch * 0.6)
		target.ElbowUpRMotor = rot(14, 32, -12)
		target.ShoulderLoLMotor = rot(12, -20, 28)
		target.ShoulderLoRMotor = rot(12, 20, -28)
		setCrown(now * 10, 14, 12)
		setTentacles(now * 10, 16, -18, 0.1)

	elseif speed > 1.2 then
		-- STALK / RUN STRIDE (with Stealth crouch modifier + Seismic 3D footsteps!)
		local stealthMul = if isStealth then 0.65 else 1.0
		local runFactor = math.clamp((speed - 8) / 14, 0, 1)
		local freq = math.clamp(speed * 0.38, 3.2, 11.5)
		stridePhase += dt * freq

		local s = math.sin(stridePhase)
		local c = math.cos(stridePhase)
		local bob = (math.abs(c) * 0.28 + 0.05) * (0.65 + 0.55 * runFactor)
		local crouchY = if isStealth then -0.58 else 0

		target.RootMotor = CFrame.new(s * 0.14 * scale, (bob + crouchY) * scale, 0)
			* rot(-(10 + 12 * runFactor + (if isStealth then 12 else 0)), s * 6 * stealthMul, c * 3.5)
		target.WaistMotor = rot(-(8 + 10 * runFactor) * stealthMul, -s * 12 * stealthMul, -c * 4)
		target.NeckMotor = rot((10 + 8 * runFactor), s * 6, 0)

		local armSw = (24 + 22 * runFactor) * stealthMul
		target.ShoulderUpLMotor = rot(12, -26 - s * armSw, 46 - runFactor * 8)
		target.ElbowUpLMotor = rot(16, -34 - math.max(0, s) * 16, 14)
		target.ShoulderUpRMotor = rot(12, 26 - s * armSw, -46 + runFactor * 8)
		target.ElbowUpRMotor = rot(16, 34 + math.max(0, -s) * 16, -14)

		target.ShoulderLoLMotor = rot(12, -22 + s * armSw * 0.85, 34)
		target.ShoulderLoRMotor = rot(12, 22 + s * armSw * 0.85, -34)

		setCrown(stridePhase * 0.8, if isStealth then -18 else (6 + 10 * runFactor), 8 + 8 * runFactor)
		setTentacles(stridePhase, 20 + 10 * runFactor, -12, bob)

		-- Trigger seismic footstep SFX at stride bottom peaks (not in stealth)
		local quarter = math.floor(stridePhase / math.pi)
		if quarter ~= lastStepQuarter then
			lastStepQuarter = quarter
			if not isStealth then
				playSpatialSFX(STEP_SFX, 0.22 + 0.18 * stage + 0.12 * runFactor, 0.42 + math.random() * 0.08, 18, 175)
			end
		end

	else
		-- SINISTER PREDATOR IDLE (hunched 4-arm claw guard, levitating ribcage breath, coiling tentacles)
		blendRate = 7
		local t = now * 1.85
		local b = math.sin(t)
		local sway = math.sin(now * 0.85)
		local crouchY = if isStealth then -0.55 else 0.12

		target.RootMotor = CFrame.new(0, (math.sin(t * 0.9) * 0.14 + crouchY) * scale, 0) * rot(if isStealth then -16 else -6, sway * 4, 0)
		target.WaistMotor = rot((-7 + b * 2.8) + (if isStealth then -10 else 0), sway * 5, 0)
		target.NeckMotor = rot(6 - b * 2.2, math.sin(now * 0.55) * 12, sway * 2)

		target.ShoulderUpLMotor = rot(12, -24 + b * 3, 46 + b * 4)
		target.ElbowUpLMotor = rot(16, -34 - b * 4, 14)
		target.ShoulderUpRMotor = rot(12, 24 - b * 3, -46 - b * 4)
		target.ElbowUpRMotor = rot(16, 34 + b * 4, -14)

		target.ShoulderLoLMotor = rot(12, -20 + b * 2, 34)
		target.ShoulderLoRMotor = rot(12, 20 - b * 2, -34)

		setCrown(now * 2.4, if isStealth then -20 else 4, 6)
		setTentacles(now * 2.1, 14, -12, b * 0.15)
	end

	local alpha = math.clamp(dt * blendRate, 0, 1)
	for _, mName in ipairs(MOTOR_NAMES) do
		local m = motors[mName]
		if m then
			local goal = target[mName] or CFrame.identity
			local cur = currentPoses[mName] or CFrame.identity
			local blended = cur:Lerp(goal, alpha)
			currentPoses[mName] = blended
			m.Transform = blended
		end
	end
end)


