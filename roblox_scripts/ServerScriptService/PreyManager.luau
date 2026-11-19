--!strict
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local DamageService = require(script.Parent.DamageService)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local gameEvents = remotes:WaitForChild("GameRemotes")
local active = workspace:WaitForChild("ActivePrey")
local spawns = workspace:WaitForChild("Map"):WaitForChild("PreySpawns")

local HUNTERS: {[string]: boolean} = { Assault = true, Medic = true, Trapper = true, Support = true }
local ROAR_SFX = "rbxassetid://9113980319"
local POUNCE_SFX = "rbxassetid://9113980644"
local HIT_SFX = "rbxassetid://9119073323"
local SHRIEK_SFX = "rbxassetid://9114787480"
local CRUNCH_SFX = "rbxassetid://137260412436272"
local ACID_SPIT_SFX = "rbxassetid://9116395089"

local SPECIES_CONFIG: {[string]: {
	tpl: string, tier: number, hp: number, meat: number, armor: number, buff: number,
	groundY: number, scale: number, walkSpeed: number, chaseSpeed: number,
	atkRange: number, atkDmg: number, atkCd: number, mode: string, glow: Color3,
}} = {
	RedGoliath = {
		tpl = "RedGoliath3DTemplate", tier = 2, hp = 1100, meat = 100, armor = 250, buff = 0.10,
		groundY = 2.35, scale = 1.0, walkSpeed = 9.5, chaseSpeed = 26,
		atkRange = 13.5, atkDmg = 160, atkCd = 2.15, mode = "Pounce", glow = Color3.fromRGB(255, 88, 22),
	},
	ObsidianCragback = {
		tpl = "ObsidianCragback3DTemplate", tier = 2, hp = 1650, meat = 100, armor = 380, buff = 0.12,
		groundY = 4.79, scale = 1.0, walkSpeed = 7.5, chaseSpeed = 22,
		atkRange = 15.0, atkDmg = 210, atkCd = 2.65, mode = "MagmaStomp", glow = Color3.fromRGB(255, 72, 16),
	},
	BiolumMantisStalker = {
		tpl = "BiolumMantisStalker3DTemplate", tier = 2, hp = 1320, meat = 100, armor = 280, buff = 0.14,
		groundY = 3.59, scale = 1.0, walkSpeed = 10.5, chaseSpeed = 28,
		atkRange = 14.5, atkDmg = 175, atkCd = 1.75, mode = "ScytheSlash", glow = Color3.fromRGB(62, 255, 164),
	},
	HornedCeratopsBull = {
		tpl = "HornedCeratopsBull3DTemplate", tier = 2, hp = 1850, meat = 100, armor = 420, buff = 0.12,
		groundY = 4.10, scale = 1.0, walkSpeed = 8.0, chaseSpeed = 24,
		atkRange = 15.5, atkDmg = 220, atkCd = 2.50, mode = "HornCharge", glow = Color3.fromRGB(255, 82, 42),
	},
	CoastalScavenger = {
		tpl = "CoastalScavenger3DTemplate", tier = 1, hp = 250, meat = 25, armor = 60, buff = 0,
		groundY = 2.14, scale = 1.0, walkSpeed = 5.5, chaseSpeed = 21,
		atkRange = 0, atkDmg = 0, atkCd = 99, mode = "Flee", glow = Color3.fromRGB(48, 232, 218),
	},
	SporeCrawler = {
		tpl = "SporeCrawler3DTemplate", tier = 1, hp = 340, meat = 30, armor = 90, buff = 0.05,
		groundY = 2.81, scale = 1.0, walkSpeed = 6.2, chaseSpeed = 13,
		atkRange = 14.0, atkDmg = 36, atkCd = 3.2, mode = "SporeBurst", glow = Color3.fromRGB(116, 250, 84),
	},
	AcidSpitterDrake = {
		tpl = "AcidSpitterDrake3DTemplate", tier = 1, hp = 460, meat = 45, armor = 115, buff = 0.08,
		groundY = 3.56, scale = 1.0, walkSpeed = 8.2, chaseSpeed = 19,
		atkRange = 36.0, atkDmg = 48, atkCd = 2.6, mode = "AcidSpit", glow = Color3.fromRGB(148, 255, 42),
	},
	SwampStalkerRaptor = {
		tpl = "SwampStalkerRaptor3DTemplate", tier = 1, hp = 390, meat = 35, armor = 95, buff = 0.08,
		groundY = 3.24, scale = 1.0, walkSpeed = 9.0, chaseSpeed = 24,
		atkRange = 11.0, atkDmg = 42, atkCd = 1.8, mode = "RaptorPounce", glow = Color3.fromRGB(255, 184, 42),
	},
	ThornbackBoar = {
		tpl = "ThornbackBoar3DTemplate", tier = 1, hp = 320, meat = 35, armor = 85, buff = 0.04,
		groundY = 2.44, scale = 1.0, walkSpeed = 7.0, chaseSpeed = 22,
		atkRange = 0, atkDmg = 0, atkCd = 99, mode = "Flee", glow = Color3.fromRGB(255, 108, 26),
	},
	MireCrocoSnapper = {
		tpl = "MireCrocoSnapper3DTemplate", tier = 1, hp = 360, meat = 35, armor = 95, buff = 0.05,
		groundY = 1.27, scale = 1.0, walkSpeed = 6.0, chaseSpeed = 18,
		atkRange = 0, atkDmg = 0, atkCd = 99, mode = "Flee", glow = Color3.fromRGB(255, 218, 62),
	},
}

local homeSpeciesCache: {[BasePart]: string} = {}
local tier1Cycle = {"CoastalScavenger", "SporeCrawler", "AcidSpitterDrake", "SwampStalkerRaptor", "ThornbackBoar", "MireCrocoSnapper"}
local tier2Cycle = {"RedGoliath", "ObsidianCragback", "BiolumMantisStalker", "HornedCeratopsBull"}
local function makeGroundRaycastParams(): RaycastParams
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { workspace.Terrain }
	rp.IgnoreWater = true
	return rp
end
local t1Idx, t2Idx = 0, 0
local function resolveSpeciesForHome(home: BasePart): string
	local attr = home:GetAttribute("PreySpecies")
	if typeof(attr) == "string" and SPECIES_CONFIG[attr] then
		return attr
	end
	if homeSpeciesCache[home] then
		return homeSpeciesCache[home]
	end
	local tierAttr = home:GetAttribute("PreyTier")
	local chosen: string
	if typeof(tierAttr) == "number" and tierAttr >= 2 then
		t2Idx = (t2Idx % #tier2Cycle) + 1
		chosen = tier2Cycle[t2Idx]
	else
		t1Idx = (t1Idx % #tier1Cycle) + 1
		chosen = tier1Cycle[t1Idx]
	end
	homeSpeciesCache[home] = chosen
	return chosen
end

local prey = {}

type PartOffset = { part: BasePart, localCF: CFrame }
type Animal = {
	home: BasePart,
	tier: number,
	species: string,
	groundY: number,
	nextMove: number,
	seed: number,
	offsets: {PartOffset},
	aggroTarget: Model?,
	nextAttack: number,
	nextRoar: number,
}
type Meal = { body: Model, animal: Model, origin: Vector3, started: number }

local animals: {[Model]: Animal} = {}
local meals: {[Player]: Meal} = {}
local claims: {[Model]: Player} = {}
local lastRequest: {[Player]: number} = {}
local respawns: {[BasePart]: number} = {}
local speedBuffId: {[Model]: number} = setmetatable({}, { __mode = "k" }) :: any
local running = false
local rng = Random.new()

local function combat(): boolean
	local state = gameEvents:GetAttribute("MatchState")
	return gameEvents:GetAttribute("RoundClosed") ~= true and (state == "MonsterHeadStart" or state == "ActiveHunt")
end

local function cloneMeshOrPart(
	model: Model,
	templateName: string,
	partName: string,
	size: Vector3,
	localCF: CFrame,
	color: Color3,
	material: Enum.Material,
	keepTexture: boolean?
): BasePart
	local worldAssets = ServerStorage:FindFirstChild("WorldAssets")
	local tmpl = if worldAssets then worldAssets:FindFirstChild(templateName) else nil
	local sourceMesh: MeshPart? = nil
	if tmpl then
		if tmpl:IsA("MeshPart") then
			sourceMesh = tmpl
		else
			sourceMesh = tmpl:FindFirstChildWhichIsA("MeshPart", true)
		end
	end

	local part: BasePart
	if sourceMesh then
		local c = sourceMesh:Clone()
		c.Name = partName
		c.Size = size
		if not keepTexture then
			c.TextureID = ""
			c.Color = color
			c.Material = material
		end
		c.Anchored = true
		c.CanCollide = false
		c.CanTouch = false
		c.CanQuery = true
		c.CastShadow = true
		part = c
	else
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = size
		p.Color = color
		p.Material = material
		p.Shape = Enum.PartType.Ball
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = true
		part = p
	end
	part.CFrame = localCF
	part.Parent = model
	return part
end

local function makeSmallPart(
	model: Model,
	name: string,
	size: Vector3,
	localCF: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then p.Shape = shape end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.CFrame = localCF
	p.Parent = model
	return p
end

local function playOneShot3D(parent: BasePart, soundId: string, volume: number, speed: number, maxDist: number)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 14
	s.RollOffMaxDistance = maxDist
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 5)
end

local function pivotRig(m: Model, _data: Animal, targetCF: CFrame)
	if not m.PrimaryPart then return end
	m:PivotTo(targetCF)
end

local function cloneFaunaTemplate(templateName: string): Model?
	local faunaAssets = ServerStorage:FindFirstChild("FaunaAssets")
	local tpl = faunaAssets and faunaAssets:FindFirstChild(templateName)
	if tpl and tpl:IsA("Model") then
		return tpl:Clone()
	end
	return nil
end

local function spawnAnimal(home: BasePart)
	local species = resolveSpeciesForHome(home)
	local cfg = SPECIES_CONFIG[species] or SPECIES_CONFIG.CoastalScavenger
	local tier = cfg.tier
	local offsets: {PartOffset} = {}
	local m = cloneFaunaTemplate(cfg.tpl)
	local measured = if m then m:GetAttribute("ExactGroundY") else nil
	local groundOffsetY = if typeof(measured) == "number" then measured else cfg.groundY

	if m and m.PrimaryPart then
		for _, desc in ipairs(m:GetDescendants()) do
			if desc:IsA("BasePart") then
				if desc == m.PrimaryPart then
					desc.Anchored = true
					desc.CanCollide = false
					desc.CanTouch = false
					desc.CanQuery = true
					desc.Transparency = 1
				else
					desc.Anchored = false
					desc.CanCollide = false
					desc.CanTouch = false
					desc.Massless = true
					if string.sub(desc.Name, 1, 5) == "Node_" then
						desc.Transparency = 1
						desc.CanQuery = false
					else
						desc.CanQuery = true
					end
				end
			end
		end
	else
		-- Fallback seguro caso o template não exista
		m = Instance.new("Model")
		local fallback = makeSmallPart(m, "Tronco", Vector3.new(3, 2, 4), CFrame.new(), cfg.glow, Enum.Material.Slate, Enum.PartType.Block)
		m.PrimaryPart = fallback
	end

	local rayParams = makeGroundRaycastParams()
	local floorHit = workspace:Raycast(Vector3.new(home.Position.X, 160, home.Position.Z), -Vector3.yAxis * 280, rayParams)
	local spawnPos = if floorHit and floorHit.Normal.Y > 0.35
		then floorHit.Position + Vector3.yAxis * groundOffsetY
		else home.Position + Vector3.new(0, groundOffsetY, 0)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local spawnCF = CFrame.new(spawnPos) * CFrame.Angles(0, yaw, 0)

	m.Name = species
	m:SetAttribute("Species", species)
	m:SetAttribute("PreyTier", tier)
	m:SetAttribute("MaxPreyHealth", cfg.hp)
	m:SetAttribute("PreyHealth", cfg.hp)
	m:SetAttribute("MeatValue", cfg.meat)
	m:SetAttribute("ArmorValue", cfg.armor)
	m:SetAttribute("SpeedBuffPct", cfg.buff)
	m:SetAttribute("IsDead", false)
	m:SetAttribute("MoveSpeed", 0)
	m:SetAttribute("AttackCount", 0)

	local data: Animal = {
		home = home,
		tier = tier,
		species = species,
		groundY = groundOffsetY,
		nextMove = 0,
		seed = rng:NextNumber(0, math.pi * 2),
		offsets = offsets,
		aggroTarget = nil,
		nextAttack = 0,
		nextRoar = 0,
	}
	animals[m] = data
	m.Parent = active
	pivotRig(m, data, spawnCF)
end

local function applyMonsterFeastSpeedBuff(body: Model, bonusPct: number, duration: number)
	if bonusPct <= 0 then return end
	local hum = body:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local token = (speedBuffId[body] or 0) + 1
	speedBuffId[body] = token

	local baseSpeedAttr = body:GetAttribute("BaseMonsterWalkSpeed")
	local baseSpeed = if typeof(baseSpeedAttr) == "number" and baseSpeedAttr > 8 then baseSpeedAttr else math.max(16, hum.WalkSpeed)
	body:SetAttribute("BaseMonsterWalkSpeed", baseSpeed)
	body:SetAttribute("RedGoliathSpeedBuffUntil", workspace:GetServerTimeNow() + duration)
	if not body:GetAttribute("IsStealth") then
		hum.WalkSpeed = baseSpeed * (1 + bonusPct)
	end

	task.delay(duration, function()
		if speedBuffId[body] ~= token then return end
		body:SetAttribute("RedGoliathSpeedBuffUntil", 0)
		if body.Parent and not body:GetAttribute("IsDead") and not body:GetAttribute("IsStealth") then
			local h = body:FindFirstChildOfClass("Humanoid")
			if h then h.WalkSpeed = baseSpeed end
		end
	end)
end

local function stopMeal(p: Player)
	local meal = meals[p]
	if not meal then return end
	meals[p], claims[meal.animal] = nil, nil
	meal.body:SetAttribute("IsEating", false)
end

local function canEat(p: Player, body: Model, animal: Model): boolean
	local root = body:FindFirstChild("HumanoidRootPart")
	local part = animal.PrimaryPart
	local eatRadius = if animal:GetAttribute("PreyTier") == 2 then 24 else 18
	return combat() and p.Character == body and body:GetAttribute("Role") == "Monster"
		and not body:GetAttribute("IsDead") and not body:GetAttribute("IsEvolving")
		and not body:GetAttribute("MonsterAction") and animals[animal] ~= nil and animal.Parent == active
		and animal:GetAttribute("IsDead") == true and root ~= nil and root:IsA("BasePart")
		and part ~= nil and (root.Position - part.Position).Magnitude <= eatRadius
end

function prey.Damage(animal: Model, amount: number, attacker: Player?)
	local data = animals[animal]
	if not combat() or not data or animal:GetAttribute("IsDead") or not (amount > 0 and amount < math.huge) then return end
	if attacker and attacker.Character and (data.tier == 2 or data.species == "AcidSpitterDrake" or data.species == "SporeCrawler") then
		data.aggroTarget = attacker.Character
	end
	local primary = animal.PrimaryPart
	if primary then
		playOneShot3D(primary, HIT_SFX, 0.55, if data.tier == 2 then 0.75 else 1.18, 95)
	end
	local hp = math.max(0, (animal:GetAttribute("PreyHealth") or 0) - amount)
	animal:SetAttribute("PreyHealth", hp)
	if hp == 0 then
		animal:SetAttribute("IsDead", true)
		animal:SetAttribute("MoveSpeed", 0)
		if primary then
			playOneShot3D(primary, if data.tier == 2 then ROAR_SFX else SHRIEK_SFX, 0.72, if data.tier == 2 then 0.62 else 1.35, 130)
			local steam = Instance.new("ParticleEmitter")
			steam.Name = "BiomassSteam"
			steam.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 168, 72)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(168, 36, 28)),
			})
			steam.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(1, 0),
			})
			steam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			steam.Lifetime = NumberRange.new(0.8, 1.6)
			steam.Rate = 12
			steam.Speed = NumberRange.new(1.2, 2.8)
			steam.LightEmission = 0.6
			steam.Parent = primary
		end
		local dropY = if data.tier == 2 then -1.1 else -0.55
		pivotRig(animal, data, animal:GetPivot() * CFrame.new(0, dropY, 0) * CFrame.Angles(0, 0, math.rad(72)))
	end
end

local function eatRequest(p: Player, target: any)
	if typeof(target) ~= "Instance" or not target:IsA("Model") then return end
	if meals[p] then return end
	local now = os.clock()
	if now - (lastRequest[p] or -math.huge) < 0.2 then return end
	lastRequest[p] = now
	local body = p.Character
	if not body or claims[target] or not canEat(p, body, target) then return end
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart
	meals[p] = { body = body, animal = target, origin = root.Position, started = now }
	claims[target] = p
	body:SetAttribute("IsEating", true)
	playOneShot3D(root, CRUNCH_SFX, 0.85, 0.92, 120)
end

local function updateMeals(now: number)
	for p, meal in meals do
		local body, animal = meal.body, meal.animal
		local root = body:FindFirstChild("HumanoidRootPart")
		if not canEat(p, body, animal) or not root or not root:IsA("BasePart") or (root.Position - meal.origin).Magnitude > 3.0 then
			stopMeal(p)
		elseif now - meal.started >= 2.5 then
			stopMeal(p)
			playOneShot3D(root, CRUNCH_SFX, 0.95, 0.78, 140)
			local data = animals[animal]
			local meat = animal:GetAttribute("MeatValue") or 25
			local armorGain = animal:GetAttribute("ArmorValue") or 50
			local buffPct = animal:GetAttribute("SpeedBuffPct") or 0
			body:SetAttribute("EvolutionEnergy", math.clamp((body:GetAttribute("EvolutionEnergy") or 0) + meat, 0, 100))
			body:SetAttribute("Armor", math.clamp((body:GetAttribute("Armor") or 0) + armorGain, 0, body:GetAttribute("MaxArmor") or 600))
			if typeof(buffPct) == "number" and buffPct > 0 then
				applyMonsterFeastSpeedBuff(body, buffPct, 20)
				gameEvents.UpdateUI:FireClient(p, "ApexFeastBuff", { bonusPct = 10, duration = 20 })
			end
			if data then
				respawns[data.home] = now + (if data.tier == 2 then 55 else 22)
			end
			animals[animal] = nil
			animal:Destroy()
		end
	end
end

local function validCombatTarget(c: Model?): BasePart?
	if not c or c.Parent == nil or c:GetAttribute("IsDead") or c:GetAttribute("IsDowned") then return nil end
	local role = c:GetAttribute("Role")
	if role ~= "Monster" and not HUNTERS[role] then return nil end
	local root = c:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function orientedGroundCF(currentCF: CFrame, groundPos: Vector3, dir: Vector3, normal: Vector3, dt: number): CFrame
	local tangent = dir - normal * dir:Dot(normal)
	local fwd = if tangent.Magnitude > 0.05 then tangent.Unit else dir
	local goalRot = CFrame.lookAt(Vector3.zero, fwd, normal)
	local smoothRot = currentCF.Rotation:Lerp(goalRot, math.clamp(dt * 11, 0, 1))
	return CFrame.new(groundPos) * smoothRot
end

local function stepGoliath(m: Model, data: Animal, candidates: {Model}, params: RaycastParams, dt: number, now: number)
	local primary = m.PrimaryPart
	if not primary then return end
	local cfg = SPECIES_CONFIG[data.species] or SPECIES_CONFIG.RedGoliath
	local gOff = data.groundY
	local position = primary.Position
	local homePos = data.home.Position

	-- Pick nearest living Monster or Hunter indiscriminately within territorial range
	local bestChar: Model? = nil
	local bestRoot: BasePart? = nil
	local bestDist = if data.species == "AcidSpitterDrake" then 52 else 42

	if data.aggroTarget then
		local r = validCombatTarget(data.aggroTarget)
		if r and (r.Position - homePos).Magnitude <= 82 then
			bestChar = data.aggroTarget
			bestRoot = r
			bestDist = (r.Position - position).Magnitude
		else
			data.aggroTarget = nil
		end
	end

	for _, char in ipairs(candidates) do
		local r = validCombatTarget(char)
		if r then
			local d = (r.Position - position).Magnitude
			local stealthPenalty = if char:GetAttribute("IsStealth") == true then 18 else 0
			if d < (bestDist - stealthPenalty) and (r.Position - homePos).Magnitude <= 72 then
				bestDist = d
				bestChar = char
				bestRoot = r
			end
		end
	end

	data.aggroTarget = bestChar

	if bestChar and bestRoot then
		if now >= data.nextRoar then
			data.nextRoar = now + 8.5
			if cfg.mode == "AcidSpit" or cfg.mode == "SporeBurst" then
				playOneShot3D(primary, ACID_SPIT_SFX, 0.72, 1.05, 160)
			else
				playOneShot3D(primary, ROAR_SFX, 0.85, if data.species == "ObsidianCragback" then 0.72 else 0.92, 220)
			end
		end

		local toTarget = Vector3.new(bestRoot.Position.X - position.X, 0, bestRoot.Position.Z - position.Z)
		local flatDist = toTarget.Magnitude
		local dir = if flatDist > 0.1 then toTarget.Unit else primary.CFrame.LookVector

		if flatDist <= cfg.atkRange and now >= data.nextAttack then
			data.nextAttack = now + cfg.atkCd
			m:SetAttribute("AttackCount", (m:GetAttribute("AttackCount") or 0) + 1)

			if cfg.mode == "AcidSpit" then
				playOneShot3D(primary, ACID_SPIT_SFX, 0.85, 1.15, 160)
				local spit = Instance.new("Part")
				spit.Name = "DrakeVenomSpit"
				spit.Shape = Enum.PartType.Ball
				spit.Anchored = true
				spit.CanCollide, spit.CanQuery, spit.CanTouch = false, false, false
				spit.Material = Enum.Material.Neon
				spit.Color = cfg.glow
				spit.Size = Vector3.one * 1.4
				spit.Position = position + dir * 2.5 + Vector3.yAxis * 0.8
				spit.Parent = workspace
				local tgtPos = bestRoot.Position
				TweenService:Create(spit, TweenInfo.new(0.24, Enum.EasingStyle.Linear), { Position = tgtPos, Size = Vector3.one * 3.8, Transparency = 0.65 }):Play()
				Debris:AddItem(spit, 0.30)
				DamageService.ApplyDamage(nil, bestChar, cfg.atkDmg)
			elseif cfg.mode == "SporeBurst" then
				playOneShot3D(primary, ACID_SPIT_SFX, 0.80, 0.82, 140)
				local cloud = Instance.new("Part")
				cloud.Name = "ToxicSporeCloud"
				cloud.Shape = Enum.PartType.Ball
				cloud.Anchored = true
				cloud.CanCollide, cloud.CanQuery, cloud.CanTouch = false, false, false
				cloud.Material = Enum.Material.Neon
				cloud.Color = cfg.glow
				cloud.Transparency = 0.45
				cloud.Size = Vector3.one * 4
				cloud.Position = position
				cloud.Parent = workspace
				TweenService:Create(cloud, TweenInfo.new(0.55), { Size = Vector3.one * 26, Transparency = 1 }):Play()
				Debris:AddItem(cloud, 0.60)
				for _, cand in ipairs(candidates) do
					local cr = validCombatTarget(cand)
					if cr and (cr.Position - position).Magnitude <= 14.5 then
						DamageService.ApplyDamage(nil, cand, cfg.atkDmg)
					end
				end
			else
				-- Pounce (RedGoliath) or MagmaStomp (ObsidianCragback)
				playOneShot3D(primary, POUNCE_SFX, 0.95, if data.species == "ObsidianCragback" then 0.65 else 1.0, 190)
				DamageService.ApplyDamage(nil, bestChar, cfg.atkDmg)
				if not bestRoot.Anchored and not bestChar:GetAttribute("IsDowned") then
					local att = Instance.new("Attachment")
					att.Parent = bestRoot
					local lv = Instance.new("LinearVelocity")
					lv.Attachment0 = att
					lv.MaxForce = bestRoot.AssemblyMass * 1900
					lv.VectorVelocity = dir * (if data.species == "ObsidianCragback" then 66 else 56) + Vector3.yAxis * 16
					lv.Parent = att
					Debris:AddItem(att, 0.22)
				end
				local shock = Instance.new("Part")
				shock.Name = "FaunaSlamShock"
				shock.Shape = Enum.PartType.Ball
				shock.Anchored = true
				shock.CanCollide, shock.CanQuery, shock.CanTouch = false, false, false
				shock.Material = Enum.Material.Neon
				shock.Color = cfg.glow
				shock.Transparency = 0.55
				shock.Size = Vector3.one * 2.5
				shock.Position = bestRoot.Position
				shock.Parent = workspace
				TweenService:Create(shock, TweenInfo.new(0.32), { Size = Vector3.one * (if data.species == "ObsidianCragback" then 30 else 22), Transparency = 1 }):Play()
				Debris:AddItem(shock, 0.36)
			end
		end

		local holdDist = if cfg.mode == "AcidSpit" then 22 else 7.5
		if flatDist > holdDist then
			local speed = cfg.chaseSpeed
			local step = dir * math.min(dt * speed, 3.0)
			local nextPos = position + step
			if (nextPos - homePos).Magnitude <= 76 then
				local hit = workspace:Raycast(nextPos + Vector3.yAxis * 10, -Vector3.yAxis * 24, params)
				if hit and hit.Normal.Y > 0.55 then
					local ground = hit.Position + Vector3.yAxis * gOff
					m:SetAttribute("MoveSpeed", speed)
					pivotRig(m, data, orientedGroundCF(primary.CFrame, ground, dir, hit.Normal, dt))
					return
				end
			end
		end
		m:SetAttribute("MoveSpeed", 0)
		pivotRig(m, data, orientedGroundCF(primary.CFrame, position, dir, Vector3.yAxis, dt))
		return
	end

	-- Territorial patrol around mineral pool / moat den
	if now < data.nextMove then
		m:SetAttribute("MoveSpeed", 0)
		return
	end
	local patrolAng = data.seed + now * 0.42
	local patrolTarget = homePos + Vector3.new(math.cos(patrolAng) * 18, 0, math.sin(patrolAng) * 18)
	local delta = Vector3.new(patrolTarget.X - position.X, 0, patrolTarget.Z - position.Z)
	if delta.Magnitude > 1.5 then
		local dir = delta.Unit
		local speed = cfg.walkSpeed
		local nextPos = position + dir * math.min(dt * speed, 1.8)
		local hit = workspace:Raycast(nextPos + Vector3.yAxis * 10, -Vector3.yAxis * 24, params)
		if hit and hit.Normal.Y > 0.55 then
			local ground = hit.Position + Vector3.yAxis * gOff
			m:SetAttribute("MoveSpeed", speed)
			pivotRig(m, data, orientedGroundCF(primary.CFrame, ground, dir, hit.Normal, dt))
		else
			m:SetAttribute("MoveSpeed", 0)
			data.nextMove = now + 0.5
		end
	else
		m:SetAttribute("MoveSpeed", 0)
	end
end

local function stepScavenger(m: Model, data: Animal, playerPoints: {Vector3}, params: RaycastParams, dt: number, now: number)
	local primary = m.PrimaryPart
	if not primary then return end
	local position = primary.Position
	local distance, nearest = 42, position
	for _, point in ipairs(playerPoints) do
		local gap = (point - position).Magnitude
		if gap < distance then
			distance, nearest = gap, point
		end
	end

	if distance < 42 and now >= data.nextMove then
		local away = Vector3.new(position.X - nearest.X, 0, position.Z - nearest.Z)
		if away.Magnitude < 0.1 then away = Vector3.xAxis end
		if distance < 24 and now >= data.nextRoar then
			data.nextRoar = now + 6.0
			playOneShot3D(primary, SHRIEK_SFX, 0.36, 1.45, 95)
		end
		local speed = 21
		for _, turn in ipairs({ 0, 0.85, -0.85, 1.65, -1.65 }) do
			local dir = CFrame.Angles(0, turn + math.sin(data.seed + now * 0.6) * 0.14, 0):VectorToWorldSpace(away.Unit)
			local step = dir * math.min(dt * speed, 2.2)
			local nextPos = position + step
			if (nextPos - data.home.Position).Magnitude > 90 then continue end
			if workspace:Raycast(position, step + dir * 1.8, params) then continue end
			local hit = workspace:Raycast(nextPos + Vector3.yAxis * 14, -Vector3.yAxis * 65, params)
			if hit and hit.Normal.Y > 0.45 and math.abs(hit.Position.Y + data.groundY - position.Y) < 8.5 then
				local ground = hit.Position + Vector3.yAxis * data.groundY
				m:SetAttribute("MoveSpeed", speed)
				pivotRig(m, data, orientedGroundCF(primary.CFrame, ground, dir, hit.Normal, dt))
				return
			end
		end
		m:SetAttribute("MoveSpeed", 0)
		data.nextMove = now + 0.35
		return
	end

	-- Gentle ambient foraging patrol around its home spot
	if now < data.nextMove then
		m:SetAttribute("MoveSpeed", 0)
		return
	end
	local wanderAng = data.seed + now * 0.55
	local wanderTarget = data.home.Position + Vector3.new(math.cos(wanderAng) * 11, 0, math.sin(wanderAng) * 11)
	local delta = Vector3.new(wanderTarget.X - position.X, 0, wanderTarget.Z - position.Z)
	if delta.Magnitude > 1.2 then
		local dir = delta.Unit
		local speed = 5.5
		local nextPos = position + dir * math.min(dt * speed, 0.9)
		if not workspace:Raycast(position, dir * 1.6, params) then
			local hit = workspace:Raycast(nextPos + Vector3.yAxis * 14, -Vector3.yAxis * 65, params)
			if hit and hit.Normal.Y > 0.45 and math.abs(hit.Position.Y + data.groundY - position.Y) < 8.5 then
				local ground = hit.Position + Vector3.yAxis * data.groundY
				m:SetAttribute("MoveSpeed", speed)
				pivotRig(m, data, orientedGroundCF(primary.CFrame, ground, dir, hit.Normal, dt))
				return
			end
		end
	end
	m:SetAttribute("MoveSpeed", 0)
end

function prey.CancelMeal(p: Player)
	local meal = meals[p]
	if meal and os.clock() - meal.started < 2.5 then stopMeal(p) end
end

function prey.Start()
	if running then return end
	running = true
	remotes.MonsterRemotes.EatPrey.OnServerEvent:Connect(eatRequest)
	Players.PlayerRemoving:Connect(function(p)
		stopMeal(p)
		lastRequest[p] = nil
	end)
	task.spawn(function()
		local previous = os.clock()
		while true do
			local now = os.clock()
			local dt = math.clamp(now - previous, 0.01, 0.4)
			updateMeals(now)
			if combat() then
				local occupied: {[BasePart]: boolean} = {}
				local positions: {Vector3} = {}
				local candidates: {Model} = {}
				local exclusions: {Instance} = { active, spawns }
				local footprintsFolder = workspace:FindFirstChild("Footprints")
				if footprintsFolder then table.insert(exclusions, footprintsFolder) end

				for _, p in ipairs(Players:GetPlayers()) do
					local body = p.Character
					local root = if body then body:FindFirstChild("HumanoidRootPart") else nil
					if body then table.insert(exclusions, body) end
					if body and root and root:IsA("BasePart") and not body:GetAttribute("IsDead") then
						if not body:GetAttribute("IsStealth") then
							table.insert(positions, root.Position)
						end
						table.insert(candidates, body)
					end
				end

				local params = makeGroundRaycastParams()

				for m, data in animals do
					if m.Parent ~= active then
						animals[m] = nil
						continue
					end
					occupied[data.home] = true
					if not m:GetAttribute("IsDead") then
						if data.tier == 2 or data.species == "SporeCrawler" or data.species == "AcidSpitterDrake" or data.species == "SwampStalkerRaptor" then
							stepGoliath(m, data, candidates, params, dt, now)
						else
							stepScavenger(m, data, positions, params, dt, now)
						end
					end
				end

				for _, home in ipairs(spawns:GetChildren()) do
					if home:IsA("BasePart") and not occupied[home] and now >= (respawns[home] or 0) then
						spawnAnimal(home)
					end
				end
			else
				for m in animals do
					animals[m] = nil
					m:Destroy()
				end
				table.clear(respawns)
			end
			previous = now
			task.wait(0.05)
		end
	end)
end

return prey
