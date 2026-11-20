--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Motion = require(game:GetService("ReplicatedStorage"):WaitForChild("AbyssCombatMotion"))

local activePrey = workspace:WaitForChild("ActivePrey")
local localPlayer = Players.LocalPlayer

local MOTOR_NAMES = {
	"HeadMotor", "LegFLMotor", "LegFRMotor", "LegBLMotor", "LegBRMotor", "TailMotor",
}

type FaunaAnimState = {
	phase: number,
	seed: number,
	motors: { [string]: Motor6D },
	baseC0s: { [string]: CFrame },
	poses: { [string]: CFrame },
}

local states: { [Model]: FaunaAnimState } = {}

local function rot(rxDeg: number, ryDeg: number, rzDeg: number): CFrame
	return CFrame.Angles(math.rad(rxDeg), math.rad(ryDeg), math.rad(rzDeg))
end

local function initAnimalState(m: Model): FaunaAnimState?
	local tronco = m.PrimaryPart
	if not tronco then
		return nil
	end
	local motors: { [string]: Motor6D } = {}
	local baseC0s: { [string]: CFrame } = {}
	local poses: { [string]: CFrame } = {}
	for _, mName in ipairs(MOTOR_NAMES) do
		local mot = tronco:FindFirstChild(mName)
		if mot and mot:IsA("Motor6D") then
			motors[mName] = mot
			local b = mot:GetAttribute("BaseC0")
			baseC0s[mName] = if typeof(b) == "CFrame" then b else mot.C0
			poses[mName] = CFrame.identity
		end
	end
	for _, name in MOTOR_NAMES do
		if not motors[name] then return nil end
	end
	local st: FaunaAnimState = {
		phase = math.random() * math.pi * 2,
		seed = math.random() * 10,
		motors = motors,
		baseC0s = baseC0s,
		poses = poses,
	}
	states[m] = st
	return st
end

activePrey.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		states[child] = nil
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local cam = workspace.CurrentCamera
	local char = localPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local origin = if root and root:IsA("BasePart")
		then root.Position
		elseif cam then cam.CFrame.Position
		else Vector3.zero

	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()

	for _, animal in ipairs(activePrey:GetChildren()) do
		if not animal:IsA("Model") or not animal.PrimaryPart then
			continue
		end

		if (animal.PrimaryPart.Position - origin).Magnitude > 420 then
			continue
		end

		local st = states[animal] or initAnimalState(animal)
		if not st then
			continue
		end

		local isDead = animal:GetAttribute("IsDead") == true
		local speed = tonumber(animal:GetAttribute("MoveSpeed")) or 0
		local tier = tonumber(animal:GetAttribute("PreyTier")) or 1
		local sp = tostring(animal:GetAttribute("Species") or "")
		local impact = tonumber(animal:GetAttribute("AttackImpactAt")) or -math.huge
		local attackPhase = 1 + (serverNow-impact)/Motion.windup(sp)

		local target: { [string]: CFrame } = {}
		for _, mName in ipairs(MOTOR_NAMES) do
			target[mName] = CFrame.identity
		end

		local blendRate = 12
		if isDead then
			blendRate = 7
			target.HeadMotor = rot(-32, 16, 22)
			target.LegFLMotor = rot(-36, 0, -28)
			target.LegFRMotor = rot(28, 0, 24)
			target.LegBLMotor = rot(34, 0, -22)
			target.LegBRMotor = rot(-30, 0, 26)
			target.TailMotor = rot(-18, 22, 0)
		elseif attackPhase>=0 and attackPhase<1.95 then
			blendRate = 28
			local head,forelimbs,tail = Motion.fauna(sp,attackPhase)
			local spread = if sp=="BiolumMantisStalker" then 0.72 else 0.36
			target.HeadMotor = rot(head, head*.11,0)
			target.LegFLMotor = rot(forelimbs*1.45,forelimbs*spread,-math.abs(forelimbs)*.36)
			target.LegFRMotor = rot(forelimbs*1.45,-forelimbs*spread,math.abs(forelimbs)*.36)
			target.LegBLMotor = rot(-forelimbs*.70,0,0)
			target.LegBRMotor = rot(-forelimbs*.70,0,0)
			target.TailMotor = rot(tail,tail*.55,0)
		elseif speed > 0.4 then
			local freqMul = if sp == "ObsidianCragback" or sp == "HornedCeratopsBull" then 0.72
				elseif sp == "SporeCrawler" or sp == "SwampStalkerRaptor" then 1.25
				elseif sp == "AcidSpitterDrake" or sp == "ThornbackBoar" then 1.15
				else 1.0
			local freq = (if tier == 2
				then math.clamp(speed * 0.48, 4.5, 13.5)
				else math.clamp(speed * 0.72, 5.0, 16.5)) * freqMul
			st.phase += dt * freq
			local s = math.sin(st.phase)
			local c = math.cos(st.phase)

			if sp == "SwampStalkerRaptor" then
				-- Bipedal alternating hind stride + tucked fore-claws + balancing whip tail
				target.LegBLMotor = rot(s * 38, 0, -4)
				target.LegBRMotor = rot(-s * 38, 0, 4)
				target.LegFLMotor = rot(-14 + c * 10, 0, 12)
				target.LegFRMotor = rot(-14 - c * 10, 0, -12)
				target.HeadMotor = rot(c * 9 + 6, s * 5, 0)
				target.TailMotor = rot(-4 + math.sin(st.phase * 2) * 5, -s * 18, 0)
			elseif sp == "BiolumMantisStalker" then
				-- Raised serrated scythe-arms + wide insectoid scuttle
				target.LegFLMotor = rot(-28 + c * 10, math.sin(st.phase * 0.5) * 12, -10)
				target.LegFRMotor = rot(-28 - c * 10, -math.sin(st.phase * 0.5) * 12, 10)
				target.LegBLMotor = rot(s * 24, 0, -18 - c * 6)
				target.LegBRMotor = rot(-s * 24, 0, 18 + c * 6)
				target.HeadMotor = rot(6 + s * 5, math.sin(now * 2.2) * 14, 0)
				target.TailMotor = rot(12 + c * 8, 0, 0)
			elseif sp == "MireCrocoSnapper" then
				-- Low reptilian S-undulation crawl & paddle tail sweep
				target.LegFLMotor = rot(s * 26, c * 18, -22)
				target.LegFRMotor = rot(-s * 26, -c * 18, 22)
				target.LegBLMotor = rot(-s * 26, -c * 18, -22)
				target.LegBRMotor = rot(s * 26, c * 18, 22)
				target.HeadMotor = rot(-4, -s * 12, 0)
				target.TailMotor = rot(2, s * 28, 0)
			elseif sp == "ThornbackBoar" then
				-- Bounding front-back razorback gallop
				local backS = math.sin(st.phase + 2.2)
				target.LegFLMotor = rot(s * 34, 0, -4)
				target.LegFRMotor = rot(math.sin(st.phase + 0.4) * 34, 0, 4)
				target.LegBLMotor = rot(backS * 34, 0, -4)
				target.LegBRMotor = rot(math.sin(st.phase + 2.6) * 34, 0, 4)
				target.HeadMotor = rot(c * 10 - 6, 0, 0)
				target.TailMotor = rot(18 + s * 14, c * 14, 0)
			else
				local amp = if sp == "ObsidianCragback" or sp == "HornedCeratopsBull" then 24 elseif speed > 14 then 38 else 26
				local crabRoll = if sp == "SporeCrawler" then 16 else 3
				target.LegFLMotor = rot(s * amp, 0, -crabRoll - s * 4)
				target.LegBRMotor = rot(s * amp * 0.92, 0, crabRoll + s * 4)
				target.LegFRMotor = rot(-s * amp, 0, crabRoll - s * 4)
				target.LegBLMotor = rot(-s * amp * 0.92, 0, -crabRoll + s * 4)
				target.HeadMotor = rot(c * (if sp == "AcidSpitterDrake" then 14 else 8) - 4, math.sin(st.phase * 0.5) * 8, 0)
				target.TailMotor = rot(8 + math.sin(st.phase * 2) * 10, c * (if sp == "AcidSpitterDrake" then 26 else 18), 0)
			end
		else
			blendRate = 6
			local t = now * 1.9 + st.seed
			local b = math.sin(t)
			local scan = math.sin(now * 0.8 + st.seed)
			target.HeadMotor = rot(b * 4.5, scan * 16, math.cos(now * 0.6 + st.seed) * 3)
			target.TailMotor = rot(4 + b * 4, math.sin(now * 2.3 + st.seed) * 14, 0)
			target.LegFLMotor = rot(b * 1.8, 0, 0)
			target.LegFRMotor = rot(-b * 1.8, 0, 0)
		end

		local alpha = 1 - math.exp(-dt * blendRate)
		for _, mName in ipairs(MOTOR_NAMES) do
			local mot = st.motors[mName]
			local baseC0 = st.baseC0s[mName]
			if mot and baseC0 then
				local goal = target[mName] or CFrame.identity
				local cur = st.poses[mName] or CFrame.identity
				local blended = cur:Lerp(goal, alpha)
				st.poses[mName] = blended
				mot.C0 = baseC0 * blended
			end
		end
	end
end)

