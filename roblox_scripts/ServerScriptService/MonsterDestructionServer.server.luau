--!strict
--[[
	PRIMAL HUNT | MonsterDestructionServer
	Destruição dinâmica de cenário pelo Monstro Colossal (22..38.5 studs):
	- Derruba e estilhaça árvores & totens em ataques (ClawSlash, LeapSmash, FeralCharge, AcidBreath) ou atropelamento em corrida.
	- Substitui a árvore em pé pelo toco estilhaçado 3D do Blender (ShatteredTreeStump3D), arremessa tora quebrada (SplinteredLogChunk3D),
	  detritos de rocha em saltos sísmicos, partículas de folhas/lascas e áudio espacial pesado.
	- Regenera a floresta após 40s mantendo a arena limpa e destrutível.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CRACK_SFX = "rbxassetid://9113086636"
local CRASH_SFX = "rbxassetid://9114362401"

local ACTIVE_ACTIONS: {[string]: boolean} = {
	ClawSlash = true,
	LeapSmash = true,
	FeralCharge = true,
	AcidBreath = true,
}

local destroyedUntil: {[Instance]: number} = {}
local activeStumps: {[Instance]: Model} = {}
local rng = Random.new()

local function getTemplate(name: string): Model?
	local wa = ServerStorage:FindFirstChild("WorldAssets")
	local tpl = wa and wa:FindFirstChild(name)
	return if tpl and tpl:IsA("Model") then tpl else nil
end

local function playDestructionAudio(pos: Vector3, scale: number)
	local host = Instance.new("Part")
	host.Name = "DestructionSFXHost"
	host.Anchored = true
	host.CanCollide, host.CanQuery, host.CanTouch = false, false, false
	host.Transparency = 1
	host.Size = Vector3.one
	host.Position = pos
	host.Parent = workspace

	for _, info in ipairs({ {CRACK_SFX, 0.85, 0.72}, {CRASH_SFX, 0.75, 0.58} }) do
		local s = Instance.new("Sound")
		s.SoundId = info[1] :: string
		s.Volume = info[2] :: number
		s.PlaybackSpeed = (info[3] :: number) + rng:NextNumber(-0.08, 0.08)
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 20
		s.RollOffMaxDistance = 210 + scale * 30
		s.Parent = host
		s:Play()
	end

	-- Leaf & splinter burst particle
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(168, 126, 78)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(64, 128, 56)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(48, 42, 34)),
	})
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0)})
	pe.Lifetime = NumberRange.new(0.7, 1.5)
	pe.Speed = NumberRange.new(18, 38)
	pe.SpreadAngle = Vector2.new(80, 80)
	pe.Acceleration = Vector3.new(0, -32, 0)
	pe.Rate = 0
	pe.Parent = host
	pe:Emit(28)

	Debris:AddItem(host, 3.5)
end

local function setModelPartsVisible(target: Instance, visible: boolean)
	if target:IsA("BasePart") then
		if visible then
			local origT = target:GetAttribute("_OrigTrans")
			local origC = target:GetAttribute("_OrigCol")
			target.Transparency = if typeof(origT) == "number" then origT else 0
			target.CanCollide = if typeof(origC) == "boolean" then origC else true
		else
			if target:GetAttribute("_OrigTrans") == nil then
				target:SetAttribute("_OrigTrans", target.Transparency)
				target:SetAttribute("_OrigCol", target.CanCollide)
			end
			target.Transparency = 1
			target.CanCollide = false
		end
	end
	for _, d in ipairs(target:GetDescendants()) do
		if d:IsA("BasePart") then
			if visible then
				local origT = d:GetAttribute("_OrigTrans")
				local origC = d:GetAttribute("_OrigCol")
				d.Transparency = if typeof(origT) == "number" then origT else 0
				d.CanCollide = if typeof(origC) == "boolean" then origC else true
			else
				if d:GetAttribute("_OrigTrans") == nil then
					d:SetAttribute("_OrigTrans", d.Transparency)
					d:SetAttribute("_OrigCol", d.CanCollide)
				end
				d.Transparency = 1
				d.CanCollide = false
			end
		elseif d:IsA("PointLight") or d:IsA("ParticleEmitter") then
			d.Enabled = visible
		end
	end
end

local function shatterProp(propTarget: Instance, impactOrigin: Vector3, scale: number)
	if propTarget:GetAttribute("DestroyedByMonster") == true then return end
	propTarget:SetAttribute("DestroyedByMonster", true)
	destroyedUntil[propTarget] = os.clock() + 40

	local pos: Vector3
	local baseGroundY: number
	if propTarget:IsA("BasePart") then
		pos = propTarget.Position
		baseGroundY = pos.Y - propTarget.Size.Y * 0.44
	elseif propTarget:IsA("Model") then
		pos = propTarget:GetPivot().Position
		baseGroundY = pos.Y
	else
		return
	end

	setModelPartsVisible(propTarget, false)

	-- Hide matching LushCrown_* if any
	local crownName = propTarget:GetAttribute("CrownModelName")
	if typeof(crownName) == "string" and propTarget.Parent then
		local crown = propTarget.Parent:FindFirstChild(crownName)
		if crown then
			setModelPartsVisible(crown, false)
		end
	end

	playDestructionAudio(pos, scale)

	local pushDir = Vector3.new(pos.X - impactOrigin.X, 0, pos.Z - impactOrigin.Z)
	if pushDir.Magnitude < 0.1 then pushDir = Vector3.xAxis end
	pushDir = pushDir.Unit

	-- Spawn Blender ShatteredTreeStump3D
	local stumpTpl = getTemplate("ShatteredTreeStump3DTemplate")
	if stumpTpl then
		local stump = stumpTpl:Clone()
		stump.Name = "DestroyedStump_" .. propTarget.Name
		for _, p in ipairs(stump:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
			end
		end
		stump:PivotTo(CFrame.new(pos.X, baseGroundY, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		pcall(function() stump:ScaleTo(math.clamp(scale * 0.9, 0.9, 1.5)) end)
		stump.Parent = workspace
		activeStumps[propTarget] = stump
		Debris:AddItem(stump, 41)
	end

	-- Fling 2 SplinteredLogChunk3D logs outward!
	local logTpl = getTemplate("SplinteredLogChunk3DTemplate")
	if logTpl then
		for li = 1, 2 do
			local chunk = logTpl:Clone()
			chunk.Name = "FlyingLogChunk"
			local mainP = chunk.PrimaryPart or chunk:FindFirstChildWhichIsA("BasePart")
			if mainP then
				for _, p in ipairs(chunk:GetDescendants()) do
					if p:IsA("BasePart") then
						p.CanCollide = false
						p.Anchored = false
						p.Massless = true
						if p ~= mainP then
							local wc = Instance.new("WeldConstraint")
							wc.Part0 = mainP
							wc.Part1 = p
							wc.Parent = p
						end
					end
				end
				chunk:PivotTo(CFrame.new(pos.X, baseGroundY + 5 + li * 4, pos.Z) * CFrame.Angles(rng:NextNumber(-1, 1), rng:NextNumber(0, 6.28), rng:NextNumber(-1, 1)))
				chunk.Parent = workspace
				mainP.AssemblyLinearVelocity = pushDir * rng:NextNumber(38, 62) + Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(22, 36), rng:NextNumber(-14, 14))
				mainP.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
			end
			Debris:AddItem(chunk, 5.5)
		end
	end
end

local lastTick = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastTick < 0.14 then return end
	lastTick = now

	-- Regrow trees after 40s
	for prop, exp in pairs(destroyedUntil) do
		if now >= exp then
			destroyedUntil[prop] = nil
			local stump = activeStumps[prop]
			if stump and stump.Parent then stump:Destroy() end
			activeStumps[prop] = nil
			if prop.Parent then
				prop:SetAttribute("DestroyedByMonster", nil)
				setModelPartsVisible(prop, true)
				local crownName = prop:GetAttribute("CrownModelName")
				if typeof(crownName) == "string" and prop.Parent then
					local crown = prop.Parent:FindFirstChild(crownName)
					if crown then setModelPartsVisible(crown, true) end
				end
			end
		end
	end

	local eco = workspace:FindFirstChild("HuntingMap_Ecosystem")
	if not eco then return end
	local roots: {Instance} = {}
	local veg = eco:FindFirstChild("Vegetation")
	local props = eco:FindFirstChild("HorrorHuntProps_V3")
	if veg then table.insert(roots, veg) end
	if props then table.insert(roots, props) end
	if #roots == 0 then return end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = roots

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char or char:GetAttribute("Role") ~= "Monster" or char:GetAttribute("IsDead") or char:GetAttribute("IsEvolving") then
			continue
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or root.Position.Y > 300 then continue end

		local scale = math.max(1, char:GetScale())
		local stage = tonumber(char:GetAttribute("Stage")) or 1
		local act = tostring(char:GetAttribute("MonsterAction") or "")
		local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		local isAttacking = ACTIVE_ACTIONS[act] == true
		local isBulldozing = speed > 14 or stage >= 2

		if not isAttacking and not isBulldozing then continue end

		local center = if isAttacking then root.Position + root.CFrame.LookVector * (7 * scale) else root.Position
		local radius = if act == "LeapSmash" then 22 * scale elseif isAttacking then 15.5 * scale else 10.5 * scale

		local checked: {[Instance]: boolean} = {}
		for _, hitPart in ipairs(workspace:GetPartBoundsInRadius(center, radius, overlap)) do
			local target: Instance? = nil
			if hitPart:GetAttribute("DestructibleTree") == true or hitPart.Name:find("^PetrifiedTree_") then
				target = hitPart
			else
				local cur: Instance? = hitPart.Parent
				while cur and cur ~= eco do
					if cur:IsA("Model") and (cur:GetAttribute("DestructibleTree") == true or cur.Name:find("^LushTree3D_") or cur.Name:find("^SporeTree_") or cur.Name:find("^BoneTotem_")) then
						target = cur
						break
					end
					cur = cur.Parent
				end
			end

			if target and not checked[target] then
				checked[target] = true
				shatterProp(target, root.Position, scale)
			end
		end
	end
end)
