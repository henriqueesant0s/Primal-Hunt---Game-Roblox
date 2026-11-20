--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Config = require(RS:WaitForChild("HunterCombatConfig"))
local Audio = require(RS:WaitForChild("HunterAudio"))
local Damage = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("DamageService"))
local remotes = RS:WaitForChild("Remotes")
local match = remotes:WaitForChild("GameRemotes")
local notice = match:WaitForChild("UpdateUI") :: RemoteEvent
local useSkill = remotes:WaitForChild("HunterRemotes"):WaitForChild("UseHunterSkill") :: RemoteEvent

local HEAL_RADIUS, HEAL_AMOUNT = 40, 350
local SHIELD_RANGE, SHIELD_CAPACITY = 40, 75
local MATRIX_SHIELD = 100
local BEAM_RANGE, BEAM_TICK, BEAM_HEAL, BEAM_REVIVE_TIME = 48, 0.25, 8, 3.0
local HARPOON_RANGE = 55
local BARRAGE_RANGE, BARRAGE_RADIUS, BARRAGE_DAMAGE = 180, 18, 38
local BARRAGE_DELAYS = {1.0, 1.4, 1.8, 2.2, 2.6}

type Projection = {target: Model, extra: number, sourcePoint: Attachment, targetPoint: Attachment}
type Cast = {body: Model, role: string, activeUntil: number, readyAt: number, shield: Projection?}
type HealingBeamState = {target: Model, sourcePoint: Attachment, targetPoint: Attachment, nextTick: number, downedHeld: number}
type HarpoonState = {monster: Model, sourcePoint: Attachment, targetPoint: Attachment, maxLength: number}
type BarrageState = {zone: Model, center: Vector3, strikeAt: {number}, nextIndex: number}
type SecondaryCast = {
	player: Player,
	body: Model,
	role: string,
	activeUntil: number,
	readyAt: number,
	matrixExtra: number?,
	matrixAura: Highlight?,
	beam: HealingBeamState?,
	harpoon: HarpoonState?,
	barrage: BarrageState?,
}

local casts: {[Player]: Cast} = {}
local secondaryCasts: {[Player]: SecondaryCast} = {}
local lastPrimaryRequest: {[Player]: number} = {}
local lastSecondaryRequest: {[Player]: number} = {}

local function feedback(p: Player, message: string)
	notice:FireClient(p, "HunterAbilityNotice", {message = message})
end

local function hunting(): boolean
	return match:GetAttribute("MatchState") == "ActiveHunt" and match:GetAttribute("RoundClosed") ~= true
end

local function hunterRoot(body: Model?): BasePart?
	if not body or not body:IsDescendantOf(workspace) or body:GetAttribute("IsDead") then return nil end
	local role = body:GetAttribute("Role")
	local root = body:FindFirstChild("HumanoidRootPart")
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if typeof(role) ~= "string" or not Config.Hunters[role] or not humanoid or humanoid.Health <= 0
		or not root or not root:IsA("BasePart") then return nil end
	return root
end

local function shieldValue(body: Model): number
	local value = body:GetAttribute("PersonalShield")
	return if typeof(value) == "number" then math.max(0, value) else 0
end

local function finiteVector(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e7
end

local function getMonster(): (Model?, BasePart?)
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and c:GetAttribute("Role") == "Monster" and not c:GetAttribute("IsDead") then
			local humanoid = c:FindFirstChildOfClass("Humanoid")
			local root = c:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				return c, root
			end
		end
	end
	return nil, nil
end

local function characterExclusions(): {Instance}
	local ignore: {Instance} = {}
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(ignore, player.Character) end
	end
	local prey = workspace:FindFirstChild("ActivePrey")
	if prey then table.insert(ignore, prey) end
	return ignore
end

local function reachable(caster: Model, source: BasePart, target: Model): BasePart?
	if caster == target or target:GetAttribute("IsDowned") or not Players:GetPlayerFromCharacter(target) then return nil end
	local dest = hunterRoot(target)
	if not dest then return nil end
	local offset = dest.Position - source.Position
	if offset.Magnitude > SHIELD_RANGE then return nil end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = characterExclusions()
	params.RespectCanCollide = true
	if offset.Magnitude > 0.1 and workspace:Raycast(source.Position, offset, params) then return nil end
	return dest
end

local function chooseAlly(c: Model, source: BasePart, preferred: unknown): Model?
	if typeof(preferred) == "Instance" and preferred:IsA("Model")
		and shieldValue(preferred) < SHIELD_CAPACITY and reachable(c, source, preferred) then
		return preferred
	end
	local closest: Model? = nil
	local best = math.huge
	for _, p in Players:GetPlayers() do
		local target = p.Character
		if not target or shieldValue(target) >= SHIELD_CAPACITY then continue end
		local dest = reachable(c, source, target)
		if dest then
			local distance = (source.Position - dest.Position).Magnitude
			if distance < best then closest, best = target, distance end
		end
	end
	return closest
end

local function project(c: Model, source: BasePart, preferred: unknown): Projection?
	local target = chooseAlly(c, source, preferred)
	if not target then return nil end
	local dest = hunterRoot(target)
	local base = shieldValue(target)
	if not dest or base >= SHIELD_CAPACITY then return nil end
	local from = Instance.new("Attachment")
	from.Name = "ShieldProjectorSource"
	from.Parent = source
	local to = Instance.new("Attachment")
	to.Name = "ShieldProjectorTarget"
	to.Parent = dest
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = from, to
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 0.22, 0.42
	beam.Color = ColorSequence.new(Color3.fromRGB(99, 191, 255))
	beam.LightEmission = 0.85
	beam.Parent = from
	target:SetAttribute("PersonalShield", SHIELD_CAPACITY)
	Audio.PlayAtPart(source, "ProjectorActivate")
	Audio.StartLoop(from, "ProjectorLoop")
	return {target = target, extra = SHIELD_CAPACITY - base, sourcePoint = from, targetPoint = to}
end

local function healTeam(source: BasePart): boolean
	local helped = false
	for _, p in Players:GetPlayers() do
		local target = p.Character
		local root = hunterRoot(target)
		if not target or not root or (root.Position - source.Position).Magnitude > HEAL_RADIUS then continue end
		if target:GetAttribute("IsDowned") then
			local maxHealth = target:GetAttribute("MaxCustomHealth")
			if typeof(maxHealth) == "number" and Damage.Revive(target, maxHealth * 0.5) then helped = true end
		elseif Damage.Heal(target, HEAL_AMOUNT) > 0 then
			helped = true
		end
	end
	if helped then
		local pulse = Instance.new("Part")
		pulse.Name = "HealingBurst"
		pulse.Anchored = true
		pulse.CanCollide, pulse.CanQuery, pulse.CanTouch, pulse.CastShadow = false, false, false, false
		pulse.Shape = Enum.PartType.Ball
		pulse.Size = Vector3.one
		pulse.CFrame = CFrame.new(source.Position)
		pulse.Color = Color3.fromRGB(99, 244, 161)
		pulse.Material = Enum.Material.Neon
		pulse.Transparency = 0.88
		pulse.Parent = workspace
		TweenService:Create(pulse, TweenInfo.new(0.5), {Size = Vector3.one * HEAL_RADIUS * 2, Transparency = 1}):Play()
		Debris:AddItem(pulse, 0.55)
		Audio.PlayAtPart(source, "HealBurst")
	end
	return helped
end

local function endEffect(cast: Cast)
	local shield = cast.shield
	if shield then
		shield.sourcePoint:Destroy()
		shield.targetPoint:Destroy()
		if shield.target:GetAttribute("PersonalShield") ~= nil then
			-- As duas reservas absorvem o mesmo impacto. Expira apenas a diferença concedida pelo projetor.
			shield.target:SetAttribute("PersonalShield", math.max(0, shieldValue(shield.target) - shield.extra))
		end
		cast.shield = nil
	end
	cast.activeUntil = 0
	cast.body:SetAttribute("ClassSkillActiveUntil", 0)
end

local function beamTargetValid(caster: Model, source: BasePart, target: Model): BasePart?
	if caster == target or not target:IsDescendantOf(workspace) or target:GetAttribute("IsDead")
		or not Players:GetPlayerFromCharacter(target) then
		return nil
	end
	local dest = hunterRoot(target)
	if not dest then return nil end
	local offset = dest.Position - source.Position
	if offset.Magnitude > BEAM_RANGE then return nil end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = characterExclusions()
	params.RespectCanCollide = true
	if offset.Magnitude > 0.1 and workspace:Raycast(source.Position, offset, params) then return nil end
	return dest
end

local function needsBeamHelp(target: Model): boolean
	if target:GetAttribute("IsDowned") == true then return true end
	local hp = target:GetAttribute("CustomHealth")
	local maxHp = target:GetAttribute("MaxCustomHealth")
	return typeof(hp) == "number" and typeof(maxHp) == "number" and maxHp > 0 and hp < maxHp
end

local function chooseBeamAlly(c: Model, source: BasePart, preferred: unknown): (Model?, BasePart?)
	if typeof(preferred) == "Instance" and preferred:IsA("Model") and needsBeamHelp(preferred) then
		local dest = beamTargetValid(c, source, preferred)
		if dest then return preferred, dest end
	end
	local bestDowned: Model? = nil
	local bestDownedDest: BasePart? = nil
	local bestDownedDist = math.huge
	local bestHurt: Model? = nil
	local bestHurtDest: BasePart? = nil
	local bestRatio = 1
	for _, p in Players:GetPlayers() do
		local target = p.Character
		if not target or not needsBeamHelp(target) then continue end
		local dest = beamTargetValid(c, source, target)
		if not dest then continue end
		local dist = (dest.Position - source.Position).Magnitude
		if target:GetAttribute("IsDowned") == true then
			if dist < bestDownedDist then
				bestDowned, bestDownedDest, bestDownedDist = target, dest, dist
			end
		else
			local hp = target:GetAttribute("CustomHealth") :: number
			local maxHp = target:GetAttribute("MaxCustomHealth") :: number
			local ratio = hp / maxHp
			if ratio < bestRatio then
				bestHurt, bestHurtDest, bestRatio = target, dest, ratio
			end
		end
	end
	if bestDowned then return bestDowned, bestDownedDest end
	return bestHurt, bestHurtDest
end

local function startHealingBeam(c: Model, source: BasePart, preferred: unknown, now: number): HealingBeamState?
	local target, dest = chooseBeamAlly(c, source, preferred)
	if not target or not dest then return nil end
	local from = Instance.new("Attachment")
	from.Name = "HealingBeamSource"
	from.Parent = source
	local to = Instance.new("Attachment")
	to.Name = "HealingBeamTarget"
	to.Parent = dest
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = from, to
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 0.24, 0.38
	beam.Color = ColorSequence.new(Color3.fromRGB(78, 245, 166))
	beam.LightEmission = 0.9
	beam.Parent = from
	Audio.StartLoop(from, "HealBeamLoop")
	return {target = target, sourcePoint = from, targetPoint = to, nextTick = now + BEAM_TICK, downedHeld = 0}
end

local function startHarpoon(c: Model, source: BasePart): HarpoonState?
	local monster, monsterRoot = getMonster()
	if not monster or not monsterRoot then return nil end
	local delta = monsterRoot.Position - source.Position
	local dist = delta.Magnitude
	if dist > HARPOON_RANGE then return nil end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = characterExclusions()
	params.RespectCanCollide = true
	if dist > 0.1 and workspace:Raycast(source.Position, delta, params) then return nil end
	local from = Instance.new("Attachment")
	from.Name = "HarpoonSource"
	from.Parent = source
	local to = Instance.new("Attachment")
	to.Name = "HarpoonTarget"
	to.Parent = monsterRoot
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = from, to
	beam.FaceCamera = true
	beam.Width0, beam.Width1 = 0.2, 0.2
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 198, 72))
	beam.LightEmission = 0.85
	beam.Parent = from
	monster:SetAttribute("IsHarpooned", true)
	Audio.PlayAtPart(source, "HarpoonFire")
	return {
		monster = monster,
		sourcePoint = from,
		targetPoint = to,
		maxLength = math.clamp(dist + 4, 20, HARPOON_RANGE),
	}
end

local function startBarrage(c: Model, source: BasePart, payload: unknown, now: number): BarrageState
	local targetPos: Vector3
	if typeof(payload) == "Vector3" and finiteVector(payload) then
		local offset = payload - source.Position
		targetPos = if offset.Magnitude > BARRAGE_RANGE then source.Position + offset.Unit * BARRAGE_RANGE else payload
	else
		local _, monsterRoot = getMonster()
		if monsterRoot and (monsterRoot.Position - source.Position).Magnitude <= BARRAGE_RANGE then
			targetPos = monsterRoot.Position
		else
			targetPos = source.Position + source.CFrame.LookVector * 35
		end
	end
	local params = RaycastParams.new()
	local ignore: {Instance} = {}
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(ignore, player.Character) end
	end
	local arena = workspace:FindFirstChild("MobileArena")
	if arena then table.insert(ignore, arena) end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local groundHit = workspace:Raycast(targetPos + Vector3.yAxis * 30, -Vector3.yAxis * 170, params)
	local center = if groundHit then groundHit.Position else targetPos

	local zone = Instance.new("Model")
	zone.Name = "OrbitalBarrageZone"
	local disc = Instance.new("Part")
	disc.Name = "WarningDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide, disc.CanQuery, disc.CanTouch, disc.CastShadow = false, false, false, false
	disc.Material = Enum.Material.Neon
	disc.Color = Color3.fromRGB(255, 88, 72)
	disc.Transparency = 0.72
	disc.Size = Vector3.new(0.35, BARRAGE_RADIUS * 2, BARRAGE_RADIUS * 2)
	disc.CFrame = CFrame.new(center + Vector3.yAxis * 0.2) * CFrame.Angles(0, 0, math.pi * 0.5)
	disc.Parent = zone
	local guide = Instance.new("Part")
	guide.Name = "TargetBeacon"
	guide.Anchored = true
	guide.CanCollide, guide.CanQuery, guide.CanTouch, guide.CastShadow = false, false, false, false
	guide.Material = Enum.Material.Neon
	guide.Color = Color3.fromRGB(96, 198, 255)
	guide.Transparency = 0.65
	guide.Size = Vector3.new(0.8, 120, 0.8)
	guide.CFrame = CFrame.new(center + Vector3.yAxis * 60)
	guide.Parent = zone
	zone.Parent = workspace

	local strikeAt: {number} = {}
	for _, delaySec in BARRAGE_DELAYS do
		table.insert(strikeAt, now + delaySec)
	end
	Audio.PlayWorldOneShot("BarrageWarning", center)
	return {zone = zone, center = center, strikeAt = strikeAt, nextIndex = 1}
end

local function fireBarrageShell(attacker: Player, center: Vector3)
	Audio.PlayWorldOneShot("BarrageImpact", center, 0.06)
	local shell = Instance.new("Part")
	shell.Name = "OrbitalStrikeBeam"
	shell.Shape = Enum.PartType.Cylinder
	shell.Anchored = true
	shell.CanCollide, shell.CanQuery, shell.CanTouch, shell.CastShadow = false, false, false, false
	shell.Material = Enum.Material.Neon
	shell.Color = Color3.fromRGB(132, 224, 255)
	shell.Transparency = 0.25
	shell.Size = Vector3.new(120, BARRAGE_RADIUS * 0.7, BARRAGE_RADIUS * 0.7)
	shell.CFrame = CFrame.new(center + Vector3.yAxis * 60) * CFrame.Angles(0, 0, math.pi * 0.5)
	shell.Parent = workspace
	TweenService:Create(shell, TweenInfo.new(0.28), {Transparency = 1}):Play()
	Debris:AddItem(shell, 0.32)

	local monster, monsterRoot = getMonster()
	if monster and monsterRoot then
		local delta = monsterRoot.Position - center
		local xz = Vector2.new(delta.X, delta.Z).Magnitude
		if xz <= BARRAGE_RADIUS and math.abs(delta.Y) <= 30 then
			Damage.ApplyDamage(attacker, monster, BARRAGE_DAMAGE)
		end
	end
end

local function endSecondaryEffect(cast: SecondaryCast)
	if cast.matrixAura then
		cast.matrixAura:Destroy()
		cast.matrixAura = nil
	end
	if cast.matrixExtra then
		local extra = cast.matrixExtra
		cast.matrixExtra = nil
		local root = cast.body:FindFirstChild("HumanoidRootPart")
		Audio.StopLoop(root, "MatrixLoop")
		if hunting() and root and root:IsA("BasePart") then
			Audio.PlayAtPart(root, "MatrixEnd")
		end
		if cast.body:GetAttribute("PersonalShield") ~= nil then
			cast.body:SetAttribute("PersonalShield", math.max(0, shieldValue(cast.body) - extra))
		end
		if cast.body:GetAttribute("MaxPersonalShield") ~= nil then
			cast.body:SetAttribute("MaxPersonalShield", 100)
		end
	end
	if cast.beam then
		cast.beam.sourcePoint:Destroy()
		cast.beam.targetPoint:Destroy()
		cast.beam = nil
	end
	if cast.harpoon then
		local monster = cast.harpoon.monster
		cast.harpoon.sourcePoint:Destroy()
		cast.harpoon.targetPoint:Destroy()
		if monster.Parent ~= nil then
			monster:SetAttribute("IsHarpooned", false)
		end
		cast.harpoon = nil
	end
	if cast.barrage then
		cast.barrage.zone:Destroy()
		cast.barrage = nil
	end
	cast.activeUntil = 0
	cast.body:SetAttribute("SecondarySkillActiveUntil", 0)
end

local function clearSecondary(p: Player, cast: SecondaryCast)
	endSecondaryEffect(cast)
	cast.body:SetAttribute("SecondarySkillId", nil)
	cast.body:SetAttribute("SecondarySkillCooldown", nil)
	cast.body:SetAttribute("SecondarySkillActiveUntil", nil)
	secondaryCasts[p] = nil
end

local function clear(p: Player, cast: Cast)
	endEffect(cast)
	cast.body:SetAttribute("ClassSkillId", nil)
	cast.body:SetAttribute("ClassSkillCooldown", nil)
	casts[p] = nil
end

local function castSecondary(p: Player, c: Model, source: BasePart, role: string, spec: Config.SkillSpec, payload: unknown, now: number)
	local old = secondaryCasts[p]
	if old then
		if old.body == c and old.role == role and now < old.readyAt then
			feedback(p, "Habilidade secundária em recarga.")
			return
		end
		clearSecondary(p, old)
	end

	local matrixExtra: number? = nil
	local matrixAura: Highlight? = nil
	local beam: HealingBeamState? = nil
	local harpoon: HarpoonState? = nil
	local barrage: BarrageState? = nil

	if role == "Assault" then
		local base = shieldValue(c)
		local total = base + MATRIX_SHIELD
		c:SetAttribute("MaxPersonalShield", math.max(100, total))
		c:SetAttribute("PersonalShield", total)
		matrixExtra = MATRIX_SHIELD
		local aura = Instance.new("Highlight")
		aura.Name = "PersonalMatrixAura"
		aura.FillColor = Color3.fromRGB(88, 214, 255)
		aura.OutlineColor = Color3.fromRGB(255, 148, 92)
		aura.FillTransparency = 0.68
		aura.Adornee = c
		aura.Parent = c
		matrixAura = aura
		Audio.PlayAtPart(source, "MatrixActivate")
		Audio.StartLoop(source, "MatrixLoop")
	elseif role == "Medic" then
		beam = startHealingBeam(c, source, payload, now)
		if not beam then
			feedback(p, "Nenhum aliado ferido ou caído visível em até 48 studs.")
			return
		end
	elseif role == "Trapper" then
		harpoon = startHarpoon(c, source)
		if not harpoon then
			feedback(p, "Aproxime-se a até 55 studs com visão limpa do monstro.")
			return
		end
	elseif role == "Support" then
		barrage = startBarrage(c, source, payload, now)
	else
		return
	end

	local activeUntil = if spec.Duration > 0 then now + spec.Duration else 0
	local cast: SecondaryCast = {
		player = p,
		body = c,
		role = role,
		activeUntil = activeUntil,
		readyAt = now + spec.Cooldown,
		matrixExtra = matrixExtra,
		matrixAura = matrixAura,
		beam = beam,
		harpoon = harpoon,
		barrage = barrage,
	}
	secondaryCasts[p] = cast
	c:SetAttribute("SecondarySkillId", spec.Id)
	c:SetAttribute("SecondarySkillCooldown", cast.readyAt)
	c:SetAttribute("SecondarySkillActiveUntil", activeUntil)
end

useSkill.OnServerEvent:Connect(function(p: Player, id: unknown, target: unknown)
	if typeof(id) ~= "string" then return end
	local now = workspace:GetServerTimeNow()
	local c = p.Character
	local source = hunterRoot(c)
	if not c or not source then return end
	local role = c:GetAttribute("Role")
	if typeof(role) ~= "string" then return end

	local secondarySpec = Config.SecondarySkills[role]
	if secondarySpec and secondarySpec.Id == id then
		if now < (lastSecondaryRequest[p] or 0) + 0.18 then return end
		lastSecondaryRequest[p] = now
		if not hunting() then feedback(p, "Aguarde o início da caçada.") return end
		if c:GetAttribute("IsDowned") then feedback(p, "Habilidade indisponível enquanto incapacitado.") return end
		castSecondary(p, c, source, role, secondarySpec, target, now)
		return
	end

	if role == "Trapper" then return end
	local spec = Config.ClassSkills[role]
	if not spec or spec.Id ~= id then return end
	if now < (lastPrimaryRequest[p] or 0) + 0.18 then return end
	lastPrimaryRequest[p] = now
	if not hunting() then feedback(p, "Aguarde o início da caçada.") return end
	if c:GetAttribute("IsDowned") then feedback(p, "Habilidade indisponível enquanto incapacitado.") return end
	local old = casts[p]
	if old then
		if old.body == c and old.role == role and now < old.readyAt then feedback(p, "Habilidade em recarga.") return end
		clear(p, old)
	end
	local shield: Projection? = nil
	if role == "Medic" then
		if not healTeam(source) then feedback(p, "Nenhum caçador ferido em até 40 studs.") return end
	elseif role == "Support" then
		shield = project(c, source, target)
		if not shield then feedback(p, "Mire em um aliado de pé, visível e a até 40 studs que precise de escudo.") return end
	end
	local activeUntil = if spec.Duration > 0 then now + spec.Duration else 0
	local cast: Cast = {body = c, role = role, activeUntil = activeUntil, readyAt = now + spec.Cooldown, shield = shield}
	casts[p] = cast
	c:SetAttribute("ClassSkillId", spec.Id)
	c:SetAttribute("ClassSkillCooldown", cast.readyAt)
	c:SetAttribute("ClassSkillActiveUntil", activeUntil)
	if role == "Assault" then Audio.PlayAtPart(source, "EquipIonRifle") end
end)

Damage.DamageApplied:Connect(function(attacker: Player?, target: Model, amount: number)
	if amount <= 0 or not attacker or not attacker.Character then return end
	if attacker.Character:GetAttribute("Role") ~= "Monster" then return end
	for p, cast in secondaryCasts do
		if cast.harpoon and cast.body == target and cast.harpoon.monster == attacker.Character then
			local mRoot = attacker.Character:FindFirstChild("HumanoidRootPart")
			endSecondaryEffect(cast)
			if mRoot and mRoot:IsA("BasePart") then Audio.PlayWorldOneShot("HarpoonBreak", mRoot.Position) end
			feedback(p, "O monstro atingiu você e rompeu o arpão!")
		end
	end
end)

local function clearClosedRound()
	if hunting() then return end
	for p, cast in casts do clear(p, cast) end
	for p, cast in secondaryCasts do clearSecondary(p, cast) end
end
match:GetAttributeChangedSignal("RoundClosed"):Connect(clearClosedRound)
match:GetAttributeChangedSignal("MatchState"):Connect(clearClosedRound)
Players.PlayerRemoving:Connect(function(p)
	local cast = casts[p]
	if cast then clear(p, cast) end
	local sec = secondaryCasts[p]
	if sec then clearSecondary(p, sec) end
	lastPrimaryRequest[p] = nil
	lastSecondaryRequest[p] = nil
end)
local nextCheck = 0
RunService.Heartbeat:Connect(function()
	if next(casts) == nil and next(secondaryCasts) == nil then return end
	local now = workspace:GetServerTimeNow()

	-- Contenção contínua do arpão e disparos da barragem ocorrem sem estrangulamento de 80ms.
	for p, cast in secondaryCasts do
		local c = cast.body
		if p.Character ~= c or c:GetAttribute("Role") ~= cast.role or not hunting() or now >= cast.readyAt then
			clearSecondary(p, cast)
			continue
		end

		local barrage = cast.barrage
		if barrage then
			while barrage.nextIndex <= #barrage.strikeAt and now >= barrage.strikeAt[barrage.nextIndex] do
				barrage.nextIndex += 1
				fireBarrageShell(p, barrage.center)
			end
			if barrage.nextIndex > #barrage.strikeAt and now >= cast.activeUntil then
				endSecondaryEffect(cast)
			end
			continue
		end

		if cast.activeUntil <= 0 then continue end
		local root = hunterRoot(c)
		if now >= cast.activeUntil or not root or c:GetAttribute("IsDowned") then
			endSecondaryEffect(cast)
			continue
		end

		if cast.matrixExtra and shieldValue(c) <= 0 then
			endSecondaryEffect(cast)
			continue
		end

		local beam = cast.beam
		if beam then
			if not beamTargetValid(c, root, beam.target) then
				endSecondaryEffect(cast)
			elseif now >= beam.nextTick then
				beam.nextTick = now + BEAM_TICK
				if beam.target:GetAttribute("IsDowned") == true then
					beam.downedHeld += BEAM_TICK
					if beam.downedHeld >= BEAM_REVIVE_TIME - 1e-4 then
						local maxHealth = beam.target:GetAttribute("MaxCustomHealth")
						if typeof(maxHealth) == "number" and maxHealth > 0 and Damage.Revive(beam.target, maxHealth * 0.5) then
							beam.downedHeld = 0
							Audio.PlayAtPart(beam.target:FindFirstChild("HumanoidRootPart"), "ReviveComplete")
						end
					end
				else
					beam.downedHeld = 0
					Damage.Heal(beam.target, BEAM_HEAL)
				end
			end
			continue
		end

		local harpoon = cast.harpoon
		if harpoon then
			local monster = harpoon.monster
			local mRoot = monster:FindFirstChild("HumanoidRootPart")
			local mHumanoid = monster:FindFirstChildOfClass("Humanoid")
			if not monster:IsDescendantOf(workspace) or monster:GetAttribute("IsDead") or not mHumanoid or mHumanoid.Health <= 0
				or not mRoot or not mRoot:IsA("BasePart") then
				endSecondaryEffect(cast)
				continue
			end
			local toTrapper = root.Position - mRoot.Position
			local dist = toTrapper.Magnitude
			local monsterAction = monster:GetAttribute("MonsterAction")
			local aggressive = monsterAction == "LeapSmash" or monsterAction == "FeralCharge" or monsterAction == "AcidBreath"
			if aggressive and (dist <= 14 or (dist > 0.01 and mRoot.CFrame.LookVector:Dot(toTrapper / dist) >= 0.35)) then
				endSecondaryEffect(cast)
				Audio.PlayWorldOneShot("HarpoonBreak", mRoot.Position)
				feedback(p, "O monstro rompeu o cabo do arpão!")
				continue
			end
			if dist > 85 then
				endSecondaryEffect(cast)
			elseif dist > harpoon.maxLength and dist > 0.01 then
				local outwardDir = -toTrapper / dist
				local clamped = root.Position + outwardDir * harpoon.maxLength
				monster:PivotTo(monster:GetPivot() + (clamped - mRoot.Position))
				local vel = mRoot.AssemblyLinearVelocity
				local outwardSpeed = vel:Dot(outwardDir)
				if outwardSpeed > 0 then
					mRoot.AssemblyLinearVelocity = vel - outwardDir * outwardSpeed
				end
			end
		end
	end

	if now < nextCheck then return end
	nextCheck = now + 0.08
	for p, cast in casts do
		local c = cast.body
		if p.Character ~= c or c:GetAttribute("Role") ~= cast.role or not hunting() or now >= cast.readyAt then
			clear(p, cast)
		elseif cast.activeUntil > 0 then
			local root = hunterRoot(c)
			local shield = cast.shield
			if now >= cast.activeUntil or not root or c:GetAttribute("IsDowned")
				or (shield and (shieldValue(shield.target) <= 0 or not reachable(c, root, shield.target))) then
				endEffect(cast)
			end
		end
	end
end)
