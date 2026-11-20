--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(RS:WaitForChild("HunterCombatConfig"))
local Audio = require(RS:WaitForChild("HunterAudio"))
local Damage = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("DamageService"))
local remotes = RS:WaitForChild("Remotes")
local match = remotes:WaitForChild("GameRemotes")
local hunterEvents = remotes:WaitForChild("HunterRemotes")
local domeEvent = hunterEvents:WaitForChild("DeployDome") :: RemoteEvent
local scanEvent = hunterEvents:WaitForChild("PlanetScanner") :: RemoteEvent
local ui = match:WaitForChild("UpdateUI") :: RemoteEvent

local RADIUS, HEIGHT, SEGMENTS = 60, 140, 36
local DOME_RANGE, DOME_TIME, DOME_RECHARGE = 100, 60, 75
local SCAN_TIME, SCAN_RECHARGE = 5, 35
local domeReady, scanReady = 0, 0
type Dome = {
	model: Model, center: Vector3, caster: Model, monster: Model, untilTime: number,
	damage: number, threshold: number, lastInside: {[Model]: Vector3},
}
type Scan = {
	caster: Model, monster: Model, humanoid: Humanoid, untilTime: number, updateAt: number,
	baseSpeed: number, appliedSpeed: number, changed: RBXScriptConnection?,
}
local dome: Dome? = nil
local scan: Scan? = nil
local lastDomeRequest: {[Player]: number} = {}
local lastScanRequest: {[Player]: number} = {}

local function hunting(): boolean
	return match:GetAttribute("MatchState") == "ActiveHunt" and match:GetAttribute("RoundClosed") ~= true
end

local function isHunter(c: Model): boolean
	local role = c:GetAttribute("Role")
	return typeof(role) == "string" and Config.Hunters[role] == true
end

local function rootOf(c: Model?): BasePart?
	if not c or not c:IsDescendantOf(workspace) then return nil end
	local root = c:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getMonster(): (Model?, BasePart?)
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and c:GetAttribute("Role") == "Monster" and not c:GetAttribute("IsDead") then
			local root = rootOf(c)
			if root then return c, root end
		end
	end
	return nil, nil
end

local function publish(c: Model)
	if not isHunter(c) then return end
	c:SetAttribute("DomeCooldown", domeReady)
	c:SetAttribute("ScannerCooldown", if c:GetAttribute("Role") == "Trapper" then scanReady else 0)
end

local function publishTeam()
	match:SetAttribute("DomeActiveUntil", if dome then dome.untilTime else 0)
	for _, p in Players:GetPlayers() do
		if p.Character then publish(p.Character) end
	end
end

local function notice(p: Player, message: string)
	ui:FireClient(p, "HunterAbilityNotice", {message = message})
end

local function request(p: Player, limiter: {[Player]: number}): Model?
	local now = os.clock()
	if now < (limiter[p] or -math.huge) + 0.4 then return nil end
	limiter[p] = now
	local c = p.Character
	if not c or not isHunter(c) then return nil end
	if not hunting() then notice(p, "Aguarde o início da caçada.") return nil end
	if c:GetAttribute("IsDead") or c:GetAttribute("IsDowned") then notice(p, "Habilidade indisponível enquanto incapacitado.") return nil end
	local h = c:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 and rootOf(c) then c else nil
end

local function addWall(model: Model, name: string, size: Vector3, cf: CFrame, cylinder: boolean)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.CastShadow = false
	if cylinder then part.Shape = Enum.PartType.Cylinder end
	part.Size = size
	part.CFrame = cf
	part.Material = Enum.Material.ForceField
	part.Transparency = if cylinder then 0.86 else 0.64
	part.Color = Color3.fromRGB(168, 148, 96)
	part.Parent = model
end

local function buildDome(center: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "MobileArena"
	local width = 2 * RADIUS * math.tan(math.pi / SEGMENTS) + 0.5
	for i = 1, SEGMENTS do
		local angle = 2 * math.pi * i / SEGMENTS
		local normal = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local at = center + normal * RADIUS
		local facing = CFrame.lookAt(at, at + normal)
		addWall(model, "Barreira", Vector3.new(width, HEIGHT, 1.5), facing, false)
		local rim = Instance.new("Part")
		rim.Name = "Anel"
		rim.Anchored = true
		rim.CanCollide, rim.CanTouch, rim.CanQuery, rim.CastShadow = false, false, false, false
		rim.Material, rim.Color = Enum.Material.Neon, Color3.fromRGB(255, 184, 77)
		rim.Size, rim.CFrame = Vector3.new(width, 0.45, 1.6), facing
		rim.Parent = model
	end
	for _, sign in {-1, 1} do
		local at = center + Vector3.yAxis * (sign * HEIGHT * 0.5)
		addWall(model, "Tampa", Vector3.new(1.5, 2 * RADIUS + 2, 2 * RADIUS + 2), CFrame.new(at) * CFrame.Angles(0, 0, math.pi * 0.5), true)
	end
	local audioCore = Instance.new("Part")
	audioCore.Name = "AudioCore"
	audioCore.Size = Vector3.one
	audioCore.Position = center
	audioCore.Anchored = true
	audioCore.Transparency = 1
	audioCore.CanCollide, audioCore.CanQuery, audioCore.CanTouch, audioCore.CastShadow = false, false, false, false
	audioCore.Parent = model
	model.Parent = workspace
	Audio.StartLoop(audioCore, "DomeHum")
	Audio.PlayWorldOneShot("DomeDeploy", center)
	return model
end

local function closeDome(recharge: boolean)
	local active = dome
	if not active then return end
	dome = nil
	active.model:Destroy()
	if recharge then Audio.PlayWorldOneShot("DomeCollapse", active.center) end
	domeReady = if recharge then workspace:GetServerTimeNow() + DOME_RECHARGE else 0
	publishTeam()
end

local function trackBoundary(active: Dome)
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if not c or c:GetAttribute("IsDead") or (c ~= active.monster and not isHunter(c)) then continue end
		local root = rootOf(c)
		if not root then continue end
		local delta = root.Position - active.center
		local radial = Vector2.new(delta.X, delta.Z).Magnitude
		if radial <= RADIUS and math.abs(delta.Y) <= HEIGHT * 0.5 then
			active.lastInside[c] = root.Position
		elseif active.lastInside[c] and (radial > RADIUS + 2 or math.abs(delta.Y) > HEIGHT * 0.5 + 2) then
			-- A física segura a borda normalmente. Recoloca quem a atravessou num salto de replicação.
			local correction = active.lastInside[c] - root.Position
			c:PivotTo(c:GetPivot() + correction)
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

domeEvent.OnServerEvent:Connect(function(p: Player)
	local c = request(p, lastDomeRequest)
	if not c then return end
	local now = workspace:GetServerTimeNow()
	if dome then notice(p, "A cúpula da equipe já está ativa.") return end
	if now < domeReady then notice(p, "A cúpula está recarregando.") return end
	local root = rootOf(c)
	local monster, monsterRoot = getMonster()
	if not root or not monster or not monsterRoot or (root.Position - monsterRoot.Position).Magnitude >= DOME_RANGE then
		notice(p, "Aproxime-se a menos de 100 studs do monstro.")
		return
	end
	local maxHealth = c:GetAttribute("MaxCustomHealth")
	if typeof(maxHealth) ~= "number" or maxHealth <= 0 then return end
	local active: Dome = {model = buildDome(root.Position), center = root.Position, caster = c, monster = monster,
		untilTime = now + DOME_TIME, damage = 0, threshold = maxHealth * 0.5, lastInside = {}}
	dome = active
	trackBoundary(active)
	publishTeam()
end)

Damage.DamageApplied:Connect(function(attacker: Player?, target: Model, amount: number)
	local active = dome
	if active and target == active.caster and attacker and attacker.Character == active.monster and hunting() then
		active.damage += amount
		if active.damage >= active.threshold then closeDome(true) end
	end
end)

local function forHunters(kind: string, data: {[string]: any})
	for _, player in Players:GetPlayers() do
		local c = player.Character
		if c and isHunter(c) then ui:FireClient(player, kind, data) end
	end
end

local function stopScan()
	local active = scan
	if not active then return end
	scan = nil
	if active.changed then active.changed:Disconnect() end
	if active.humanoid.Parent and active.humanoid.WalkSpeed == active.appliedSpeed then
		active.humanoid.WalkSpeed = active.baseSpeed
	end
	forHunters("ScannerEnded", {})
end

local function sendPosition(active: Scan, position: Vector3, now: number)
	active.updateAt = now + 0.25
	forHunters("PlanetScannerPulse", {targetPosition = position, endsAt = active.untilTime, duration = active.untilTime - now})
end

scanEvent.OnServerEvent:Connect(function(p: Player)
	local c = request(p, lastScanRequest)
	if not c then return end
	if c:GetAttribute("Role") ~= "Trapper" then notice(p, "Somente o Trapper pode ativar o rastreio.") return end
	local now = workspace:GetServerTimeNow()
	if now < scanReady then notice(p, "O scanner está recarregando.") return end
	local monster, root = getMonster()
	if not monster or not root then notice(p, "Nenhum monstro ativo para rastrear.") return end
	local h = c:FindFirstChildOfClass("Humanoid")
	if not h then return end
	local active: Scan = {caster = c, monster = monster, humanoid = h, untilTime = now + SCAN_TIME, updateAt = 0,
		baseSpeed = h.WalkSpeed, appliedSpeed = h.WalkSpeed * 1.25, changed = nil}
	scan = active
	scanReady = now + SCAN_RECHARGE
	h.WalkSpeed = active.appliedSpeed
	active.changed = h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if scan == active and h.WalkSpeed ~= active.appliedSpeed then
			active.baseSpeed = h.WalkSpeed
			active.appliedSpeed = active.baseSpeed * 1.25
			h.WalkSpeed = active.appliedSpeed
		end
	end)
	publishTeam()
	Audio.PlayAtPart(rootOf(c), "ScannerPulse")
	sendPosition(active, root.Position, now)
end)

local connections: {[Player]: {RBXScriptConnection}} = {}
local function unbind(p: Player)
	for _, conn in connections[p] or {} do conn:Disconnect() end
	connections[p] = nil
end
local function watch(p: Player)
	local function bind(c: Model)
		unbind(p)
		local wasDown = c:GetAttribute("IsDowned") == true
		connections[p] = {
			c:GetAttributeChangedSignal("Role"):Connect(function() publish(c) end),
			c:GetAttributeChangedSignal("IsDowned"):Connect(function()
				local down = c:GetAttribute("IsDowned") == true
				local active = dome
				if active and down and not wasDown and hunting() and isHunter(c) then
					active.untilTime -= 10
					if workspace:GetServerTimeNow() >= active.untilTime then closeDome(true) else publishTeam() end
				end
				wasDown = down
			end),
		}
		publish(c)
	end
	p.CharacterAdded:Connect(bind)
	p.CharacterRemoving:Connect(function() unbind(p) end)
	if p.Character then bind(p.Character) end
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(p)
	unbind(p)
	lastDomeRequest[p], lastScanRequest[p] = nil, nil
end)
for _, p in Players:GetPlayers() do watch(p) end

local function refreshRound()
	if hunting() then return end
	domeReady, scanReady = 0, 0
	closeDome(false)
	stopScan()
	publishTeam()
end
match:GetAttributeChangedSignal("RoundClosed"):Connect(refreshRound)
match:GetAttributeChangedSignal("MatchState"):Connect(refreshRound)
refreshRound()

RunService.Heartbeat:Connect(function()
	if not dome and not scan then return end
	if not hunting() then refreshRound() return end
	local now = workspace:GetServerTimeNow()
	local active = dome
	if active then
		if now >= active.untilTime or not rootOf(active.monster) or not rootOf(active.caster)
			or active.monster:GetAttribute("IsDead") or active.caster:GetAttribute("IsDead") then
			closeDome(true)
		else
			trackBoundary(active)
		end
	end
	local pulse = scan
	if pulse then
		local target = rootOf(pulse.monster)
		if now >= pulse.untilTime or not target or pulse.monster:GetAttribute("IsDead")
			or not rootOf(pulse.caster) or pulse.caster:GetAttribute("Role") ~= "Trapper"
			or pulse.caster:GetAttribute("IsDowned") or pulse.caster:GetAttribute("IsDead") then
			stopScan()
		elseif now >= pulse.updateAt then sendPosition(pulse, target.Position, now) end
	end
end)
