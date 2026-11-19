--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(RS:WaitForChild("HunterCombatConfig"))
local Audio = require(RS:WaitForChild("HunterAudio"))
local Damage = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("DamageService"))
local Prey = require(game:GetService("ServerScriptService"):WaitForChild("PreyManager"))
local remotes = RS:WaitForChild("Remotes")
local match = remotes:WaitForChild("GameRemotes")
local hunters = remotes:WaitForChild("HunterRemotes")
local fire = hunters:WaitForChild("FireWeapon") :: RemoteEvent
local revive = hunters:WaitForChild("ReviveTeammate") :: RemoteEvent

local weapons: {[Player]: Tool} = {}
local nextShot: {[Player]: number} = {}
local nextRevive: {[Player]: number} = {}
type Attempt = {source: Model, target: Model, owner: Player, deadline: number}
local attempts: {[Player]: Attempt} = {}
local charConnections: {[Player]: {RBXScriptConnection}} = {}

local function hunting(): boolean
	return match:GetAttribute("MatchState") == "ActiveHunt" and match:GetAttribute("RoundClosed") ~= true
end

local function hunterRoot(body: Model?, downed: boolean): BasePart?
	if not body or not body:IsDescendantOf(workspace) or body:GetAttribute("IsDead") then return nil end
	local role = body:GetAttribute("Role")
	if typeof(role) ~= "string" or not Config.Hunters[role] or body:GetAttribute("IsDowned") ~= downed then return nil end
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	local root = body:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
	return root
end

local function activeWeaponId(c: Model): string?
	local role = c:GetAttribute("Role")
	if typeof(role) ~= "string" or not Config.Hunters[role] then return nil end
	local endsAt = c:GetAttribute("ClassSkillActiveUntil")
	if role == "Assault" and c:GetAttribute("ClassSkillId") == "DrawIonRifle"
		and typeof(endsAt) == "number" and endsAt > workspace:GetServerTimeNow() then
		return Config.EnhancedWeaponId
	end
	return Config.RoleWeapons[role]
end

local function buildWeapon(id: string): Tool
	local spec = Config.Weapons[id]
	local tool = Instance.new("Tool")
	tool.Name = if spec then spec.Name else id
	tool.ToolTip = "Segure o disparo para atirar"
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", id)
	local grip = Instance.new("Part")
	grip.Name = "Handle"
	grip.Size = Vector3.new(0.42, 0.8, 0.62)
	grip.Color = Color3.fromRGB(37, 53, 61)
	grip.Material = Enum.Material.Metal
	grip.CanCollide, grip.CanQuery, grip.CanTouch, grip.Massless = false, false, false, true
	grip.Parent = tool
	local function shell(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material)
		local part = Instance.new("Part")
		part.Name, part.Size, part.Color, part.Material = name, size, color, material
		part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, true
		part.CFrame = grip.CFrame * CFrame.new(offset)
		part.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = grip, part, part
	end
	local muzzleOffset = Vector3.new(0, 0.42, -1.38)
	if id == "BioCarbine" then
		shell("Corpo", Vector3.new(0.46, 0.44, 1.55), Vector3.new(0, 0.38, -0.35), Color3.fromRGB(196, 212, 216), Enum.Material.SmoothPlastic)
		shell("Cano", Vector3.new(0.18, 0.18, 0.95), Vector3.new(0, 0.42, -1.18), Color3.fromRGB(70, 92, 98), Enum.Material.Metal)
		shell("Ampola", Vector3.new(0.28, 0.24, 0.72), Vector3.new(0, 0.64, -0.30), Color3.fromRGB(92, 248, 162), Enum.Material.Neon)
		muzzleOffset = Vector3.new(0, 0.42, -1.65)
	elseif id == "GaussSMG" then
		shell("Chassi", Vector3.new(0.42, 0.42, 1.25), Vector3.new(0, 0.36, -0.28), Color3.fromRGB(68, 60, 52), Enum.Material.Metal)
		for _, side in {-1, 1} do
			shell("Trilho", Vector3.new(0.12, 0.16, 1.05), Vector3.new(0.25 * side, 0.38, -0.45), Color3.fromRGB(255, 198, 74), Enum.Material.Neon)
		end
		muzzleOffset = Vector3.new(0, 0.36, -1.15)
	elseif id == "LaserCutter" then
		shell("Carcaça", Vector3.new(0.56, 0.48, 1.52), Vector3.new(0, 0.40, -0.38), Color3.fromRGB(48, 74, 98), Enum.Material.Metal)
		shell("Núcleo", Vector3.new(0.32, 0.22, 0.96), Vector3.new(0, 0.46, -0.48), Color3.fromRGB(96, 198, 255), Enum.Material.Neon)
		for _, side in {-1, 1} do
			shell("Haste", Vector3.new(0.10, 0.14, 0.68), Vector3.new(0.22 * side, 0.40, -1.14), Color3.fromRGB(168, 224, 255), Enum.Material.Metal)
		end
		muzzleOffset = Vector3.new(0, 0.40, -1.45)
	else
		local enhanced = id == Config.EnhancedWeaponId
		shell("Carcaça", Vector3.new(0.64, 0.55, 1.85), Vector3.new(0, 0.42, -0.45), Color3.fromRGB(60, 92, 100), Enum.Material.Metal)
		shell("Célula", Vector3.new(0.67, 0.18, 0.84), Vector3.new(0, 0.45, -0.55), Color3.fromRGB(95, 255, 222), Enum.Material.Neon)
		if enhanced then
			for _, side in {-1, 1} do
				shell("Bobina iônica", Vector3.new(0.18, 0.35, 1.7), Vector3.new(0.38 * side, 0.48, -0.65), Color3.fromRGB(211, 139, 255), Enum.Material.Neon)
			end
		end
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "PlasmaEmitter"
	muzzle.Position = muzzleOffset
	muzzle.Parent = grip
	return tool
end

local function refreshWeapon(p: Player)
	local c = p.Character
	local bag = p:FindFirstChildOfClass("Backpack")
	local tool = weapons[p]
	local id = if c and hunting() and hunterRoot(c, false) then activeWeaponId(c) else nil
	if not c or not id then
		if tool then tool:Destroy() end
		weapons[p], nextShot[p] = nil, nil
		return
	end
	if tool and tool:GetAttribute("WeaponId") == id and (tool.Parent == c or (bag ~= nil and tool.Parent == bag)) then return end
	if not bag then return end
	if tool then tool:Destroy() end
	local new = buildWeapon(id)
	weapons[p] = new
	new.Parent = bag
	local humanoid = c:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:EquipTool(new) end
end

local function canContinue(p: Player, a: Attempt): boolean
	if not hunting() or match:GetAttribute("SuddenDeath") == true or p.Character ~= a.source or a.owner.Character ~= a.target or a.owner.Parent ~= Players then return false end
	local source = hunterRoot(a.source, false)
	local target = hunterRoot(a.target, true)
	return source ~= nil and target ~= nil and (source.Position - target.Position).Magnitude <= Config.ReviveRange
end

local function finishAttempt(p: Player, a: Attempt, complete: boolean)
	if attempts[p] ~= a then return end
	attempts[p] = nil
	local targetRoot = a.target:FindFirstChild("HumanoidRootPart")
	local stillReviving = false
	for _, other in attempts do
		if other.target == a.target then
			stillReviving = true
			break
		end
	end
	if not stillReviving then Audio.StopLoop(targetRoot, "ReviveLoop") end
	local restored = false
	if complete and canContinue(p, a) then
		local maxHealth = a.target:GetAttribute("MaxCustomHealth")
		if typeof(maxHealth) == "number" and maxHealth > 0 then restored = Damage.Revive(a.target, maxHealth * 0.5) end
	end
	if restored then Audio.PlayAtPart(targetRoot, "ReviveComplete") end
	if p.Parent == Players then revive:FireClient(p, a.target, if restored then "Complete" else "Cancel") end
end

revive.OnServerEvent:Connect(function(p: Player, target: unknown, holding: unknown)
	if typeof(holding) ~= "boolean" or typeof(target) ~= "Instance" or not target:IsA("Model") then return end
	local now = workspace:GetServerTimeNow()
	local a = attempts[p]
	if not holding then
		if a and a.target == target then finishAttempt(p, a, now >= a.deadline) end
		return
	end
	if a or match:GetAttribute("SuddenDeath") == true or now < (nextRevive[p] or 0) then return end
	nextRevive[p] = now + 0.12
	local owner = Players:GetPlayerFromCharacter(target)
	local c = p.Character
	if not c or not owner or owner == p then return end
	local attempt: Attempt = {source = c, target = target, owner = owner, deadline = now + Config.ReviveSeconds}
	if not canContinue(p, attempt) then return end
	attempts[p] = attempt
	Audio.StartLoop(target:FindFirstChild("HumanoidRootPart"), "ReviveLoop")
	revive:FireClient(p, target, "Started", attempt.deadline)
end)

RunService.Heartbeat:Connect(function()
	if next(attempts) == nil then return end
	local now = workspace:GetServerTimeNow()
	for p, a in attempts do
		if not canContinue(p, a) then finishAttempt(p, a, false)
		elseif now >= a.deadline then finishAttempt(p, a, true) end
	end
end)

local function finiteVector(v: Vector3): boolean
	return v.Magnitude < math.huge
end

fire.OnServerEvent:Connect(function(p: Player, origin: unknown, direction: unknown, weaponId: unknown)
	if typeof(weaponId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	local spec = Config.Weapons[weaponId]
	if not spec or not finiteVector(origin) or not (direction.Magnitude >= 0.99 and direction.Magnitude <= 1.01) then return end
	local now = os.clock()
	local due = nextShot[p] or now
	-- Até 25 ms de variação de entrega, mantendo a cadência acumulada.
	if now + 0.025 < due then return end
	local c = p.Character
	local tool = weapons[p]
	if not hunting() or not c or not tool or tool.Parent ~= c
		or not hunterRoot(c, false) or attempts[p] then return end
	if tool:GetAttribute("WeaponId") ~= weaponId or activeWeaponId(c) ~= weaponId then return end
	local head = c:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or (origin - head.Position).Magnitude > 7 then return end
	nextShot[p] = math.max(now, due) + spec.Interval
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {c}
	local ray = direction.Unit * spec.Range
	local hit = workspace:Raycast(head.Position, ray, params)
	local endpoint = if hit then hit.Position else head.Position + ray
	local hitMonster = false
	if hit then
		local ancestor: Instance? = hit.Instance
		while ancestor and ancestor ~= workspace do
			if ancestor:IsA("Model") then
				if ancestor:GetAttribute("Role") == "Monster" and Players:GetPlayerFromCharacter(ancestor) then
					hitMonster = true
					Damage.ApplyDamage(p, ancestor, spec.Damage)
					break
				elseif ancestor.Parent == workspace:FindFirstChild("ActivePrey") then
					hitMonster = true
					Prey.Damage(ancestor, spec.Damage, p)
					break
				end
			end
			ancestor = ancestor.Parent
		end
	end
	local handle = tool:FindFirstChild("Handle")
	local emitter = if handle then handle:FindFirstChild("PlasmaEmitter") else nil
	local start = head.Position
	if emitter and emitter:IsA("Attachment") and (emitter.WorldPosition - start).Magnitude < 5 then start = emitter.WorldPosition end
	fire:FireAllClients(start, endpoint, weaponId, hitMonster)
end)

local function detach(p: Player)
	for _, conn in charConnections[p] or {} do conn:Disconnect() end
	charConnections[p] = nil
	if weapons[p] then weapons[p]:Destroy() end
	weapons[p], nextShot[p], nextRevive[p] = nil, nil, nil
	for helper, a in attempts do
		if helper == p or a.owner == p then finishAttempt(helper, a, false) end
	end
end

local function watchPlayer(p: Player)
	local function bind(c: Model)
		detach(p)
		local conns = {}
		charConnections[p] = conns
		local function changed() refreshWeapon(p) end
		for _, key in {"Role", "IsDowned", "IsDead", "ClassSkillId", "ClassSkillActiveUntil"} do table.insert(conns, c:GetAttributeChangedSignal(key):Connect(changed)) end
		table.insert(conns, c.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") or child.Name == "HumanoidRootPart" then changed() end
		end))
		changed()
	end
	p.CharacterAdded:Connect(bind)
	p.CharacterRemoving:Connect(function() detach(p) end)
	p.ChildAdded:Connect(function(child) if child:IsA("Backpack") then refreshWeapon(p) end end)
	if p.Character then bind(p.Character) end
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(detach)
for _, p in Players:GetPlayers() do watchPlayer(p) end
local function updateRoster()
	for _, p in Players:GetPlayers() do refreshWeapon(p) end
end
match:GetAttributeChangedSignal("MatchState"):Connect(updateRoster)
match:GetAttributeChangedSignal("RoundClosed"):Connect(updateRoster)

