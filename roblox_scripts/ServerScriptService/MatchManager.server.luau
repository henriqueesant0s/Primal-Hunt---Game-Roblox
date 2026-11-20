--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DamageService = require(script.Parent.DamageService)
local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes")
local changed = remotes:WaitForChild("MatchStateChanged") :: RemoteEvent
local updateUI = remotes:WaitForChild("UpdateUI") :: RemoteEvent
local selectRole = remotes:WaitForChild("SelectRolePreference") :: RemoteEvent
local map = workspace:WaitForChild("Map")
local relay = map:WaitForChild("PowerRelay") :: Model
local monsterSpawns = map:WaitForChild("MonsterSpawns")
local hunterSpawns = map:WaitForChild("HunterSpawns")
local INTERMISSION, HEAD_START, HUNT, POST_MATCH = 20, 15, 12 * 60, 10
local RELAY_MAX_HP = 12000
local DROPSHIP_RESPAWN_DELAY = 40
local RELAY_SIREN_SFX = "rbxassetid://9118805665"
local RELAY_SHATTER_SFX = "rbxassetid://9113086636"
local ROLES = {"Monster", "Assault", "Medic", "Trapper", "Support"}
local IS_STUDIO = RunService:IsStudio()
local function minRequiredPlayers(): number
	return if IS_STUDIO then 1 else #ROLES
end
local ALLOWED: {[string]: boolean} = { Monster = true, Assault = true, Medic = true, Trapper = true, Support = true }
local rng = Random.new()
type Entry = {player: Player, role: string, character: Model, eliminated: boolean, deployed: boolean}
type Data = {[string]: any}
type Outcome = {winner: string, reason: string}
local entries: {Entry} = {}
local byPlayer: {[Player]: Entry} = {}
local queue: {[Player]: number} = {}
local priorities: {[Player]: string} = {}
local lastPreference: {[Player]: number} = {}
local initialized: {[Model]: boolean} = setmetatable({}, {__mode = "k"}) :: any
local queueSerial = 0
local phase = "Intermission"
local remaining = 0
local extra: Data = {}
local outcome: Outcome? = nil
local suddenDeathActive = false
local stage3SirenPlayed = false
local roundHadMonster = false
local roundHadHunters = false
local pendingRespawnAt: {[Player]: number} = {}

local function playRelayGlobalSound(soundId: string, volume: number, pitch: number)
	local core = relay.PrimaryPart or relay:FindFirstChildWhichIsA("BasePart")
	if not core then return end
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 40
	s.RollOffMaxDistance = 1400
	s.Parent = core
	s:Play()
	game:GetService("Debris"):AddItem(s, 8)
end

local function setRelayBeaconsActive(isActive: boolean)
	relay:SetAttribute("BeaconsActive", isActive)
	for _, desc in ipairs(relay:GetDescendants()) do
		if desc:IsA("Beam") or desc:IsA("SpotLight") then
			desc.Enabled = isActive
		elseif desc:IsA("PointLight") and desc.Parent and desc.Parent.Name == "Core" then
			desc.Color = if isActive then Color3.fromRGB(255, 184, 77) else Color3.fromRGB(138, 28, 28)
			desc.Brightness = if isActive then 2.4 else 0.8
		elseif desc:IsA("BasePart") and desc.Name == "Core" then
			desc.Color = if isActive then Color3.fromRGB(255, 184, 77) else Color3.fromRGB(58, 20, 20)
			desc.Material = if isActive then Enum.Material.Neon else Enum.Material.Slate
		end
	end
end

local function announce(state: string, seconds: number, data: Data)
	phase, remaining, extra = state, seconds, data
	remotes:SetAttribute("TimeRemaining", seconds)
	remotes:SetAttribute("WaitingForPlayers", data.waitingForPlayers == true)
	remotes:SetAttribute("Winner", data.winner)
	remotes:SetAttribute("WinReason", data.reason)
	remotes:SetAttribute("MatchState", state)
	changed:FireAllClients(state, seconds, data)
end

local function evaluate()
	if outcome or (phase ~= "MonsterHeadStart" and phase ~= "ActiveHunt") then return end
	local monster: Entry? = nil
	local standingHunters = 0
	for _, entry in entries do
		if entry.role == "Monster" then
			monster = entry
		elseif not entry.eliminated and not entry.character:GetAttribute("IsDead")
			and not entry.character:GetAttribute("IsDowned") then
			standingHunters += 1
		end
	end
	if roundHadMonster and (not monster or monster.eliminated or monster.character:GetAttribute("IsDead")) then
		outcome = {winner = "Hunters", reason = "MonsterEliminated"}
	elseif roundHadHunters and standingHunters == 0 then
		outcome = {winner = "Monster", reason = if suddenDeathActive then "PowerRelayDestroyed" else "HuntersIncapacitated"}
	elseif suddenDeathActive and not roundHadHunters then
		outcome = {winner = "Monster", reason = "RelayDestroyed"}
	end
	if outcome then remotes:SetAttribute("RoundClosed", true) end
end

local function markLost(player: Player, character: Model)
	local entry = byPlayer[player]
	if not entry or entry.character ~= character or entry.eliminated then return end
	entry.eliminated = true
	character:SetAttribute("IsDead", true)
	character:SetAttribute("CustomHealth", 0)
	if phase == "ActiveHunt" and entry.role ~= "Monster" and not suddenDeathActive then
		pendingRespawnAt[player] = os.clock() + DROPSHIP_RESPAWN_DELAY
		remotes:SetAttribute("DropshipRespawnAvailable", true)
	end
	evaluate()
end

local function setStats(character: Model, role: string)
	local monster = role == "Monster"
	local hunter = role ~= "Lobby" and not monster
	local hp = if monster then 1500 else 100
	local armor = if monster then 800 else 0
	character:SetAttribute("MaxCustomHealth", hp)
	character:SetAttribute("CustomHealth", hp)
	character:SetAttribute("MaxArmor", armor)
	character:SetAttribute("Armor", armor)
	character:SetAttribute("IsDowned", false)
	character:SetAttribute("IsDead", false)
	character:SetAttribute("HasBeenDowned", false)
	character:SetAttribute("BleedoutRemaining", 0)
	character:SetAttribute("Stage", if monster then 1 else nil)
	character:SetAttribute("EvolutionEnergy", if monster then 0 else nil)
	character:SetAttribute("IsEvolving", if monster then false else nil)
	character:SetAttribute("Stamina", if monster then 100 else nil)
	character:SetAttribute("JetpackFuel", if hunter then 100 else nil)
	character:SetAttribute("PersonalShield", if hunter then 0 else nil)
	character:SetAttribute("DomeCooldown", if hunter then 0 else nil)
	character:SetAttribute("ScannerCooldown", if hunter then 0 else nil)
	character:SetAttribute("Role", role)
	DamageService.SyncHumanoid(character)
end

local function onCharacter(player: Player, character: Model)
	if initialized[character] then return end
	initialized[character] = true
	local old = byPlayer[player]
	if old and old.character ~= character then markLost(player, old.character) end
	setStats(character, "Lobby")
	character:SetAttribute("PreferredRole", priorities[player])

	local function attachHumanoid(humanoid: Humanoid)
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Connect(function() markLost(player, character) end)
		humanoid.HealthChanged:Connect(function(health)
			if health > 0 then DamageService.SyncHumanoid(character) end
		end)
		DamageService.SyncHumanoid(character)
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then attachHumanoid(child) end
	end)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then attachHumanoid(humanoid) end
	for _, name in {"CustomHealth", "MaxCustomHealth"} do
		character:GetAttributeChangedSignal(name):Connect(function() DamageService.SyncHumanoid(character) end)
	end
	local anchoredByMatch = false
	local function onCondition()
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local stopped = character:GetAttribute("IsDowned") or character:GetAttribute("IsDead")
			if stopped and not root.Anchored then
				root.Anchored = true
				anchoredByMatch = true
			elseif not stopped and anchoredByMatch then
				root.Anchored = false
				anchoredByMatch = false
			end
		end
		evaluate()
	end
	character:GetAttributeChangedSignal("IsDead"):Connect(onCondition)
	character:GetAttributeChangedSignal("IsDowned"):Connect(onCondition)
	character:GetAttributeChangedSignal("Stage"):Connect(function()
		if character:GetAttribute("Role") == "Monster" and character:GetAttribute("Stage") == 3 and phase == "ActiveHunt" and not stage3SirenPlayed then
			stage3SirenPlayed = true
			playRelayGlobalSound(RELAY_SIREN_SFX, 0.95, 0.88)
			updateUI:FireAllClients("Stage3AnchorObjective", {
				title = "DESTROY THE A.E.M. ANCHOR RELAY",
				relayHealth = relay:GetAttribute("RelayHealth") or RELAY_MAX_HP,
				maxRelayHealth = RELAY_MAX_HP,
			})
		end
	end)
end

local function enqueue(player: Player)
	queueSerial += 1
	queue[player] = queueSerial
end

local function onPlayer(player: Player)
	if queue[player] then return end
	enqueue(player)
	player.CharacterAdded:Connect(function(character) onCharacter(player, character) end)
	player.CharacterRemoving:Connect(function(character) markLost(player, character) end)
	if player.Character then onCharacter(player, player.Character) end
	changed:FireClient(player, phase, remaining, extra)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	local entry = byPlayer[player]
	if entry then markLost(player, entry.character) end
	queue[player], priorities[player], lastPreference[player] = nil, nil, nil
end)
for _, player in Players:GetPlayers() do onPlayer(player) end

selectRole.OnServerEvent:Connect(function(player: Player, requested: any)
	local now = os.clock()
	if phase ~= "Intermission" or not queue[player] or now - (lastPreference[player] or -math.huge) < 0.5 then return end
	lastPreference[player] = now
	local character = player.Character
	if not character or character:GetAttribute("Role") ~= "Lobby"
		or typeof(requested) ~= "string" or not ALLOWED[requested] then return end
	priorities[player] = requested
	character:SetAttribute("PreferredRole", requested)
	updateUI:FireClient(player, "RolePreferenceConfirmed", {preferredRole = requested})
end)

local function readyPlayers(): {Player}
	local ready: {Player} = {}
	for player in queue do
		local c = player.Character
		local h = if c then c:FindFirstChildOfClass("Humanoid") else nil
		if c and c:IsDescendantOf(workspace) and initialized[c] and h and h.Health > 0
			and c:GetAttribute("Role") == "Lobby" and c:FindFirstChild("HumanoidRootPart") then
			table.insert(ready, player)
		end
	end
	table.sort(ready, function(a, b) return queue[a] < queue[b] end)
	return ready
end

local function spawnPoints(folder: Instance): {BasePart}
	local points: {BasePart} = {}
	for _, item in folder:GetChildren() do
		if item:IsA("BasePart") then table.insert(points, item) end
	end
	table.sort(points, function(a, b) return a.Name < b.Name end)
	return points
end

local lastMonsterId: number? = nil

local function chooseMonster(pool: {Player}): Player
	local total = 0
	local weights: {number} = {}
	for index, player in pool do
		local weight = player:GetAttribute("MonsterSelectionWeight")
		local tickets = if typeof(weight) == "number" and weight > 0 then weight else 1
		if priorities[player] == "Monster" then tickets *= 2 end
		if player.UserId == lastMonsterId and #pool > 1 then tickets = 0 end
		weights[index] = tickets
		total += tickets
	end
	local ticket = rng:NextNumber() * total
	for index, player in pool do
		ticket -= weights[index]
		if ticket < 0 then return player end
	end
	return pool[1]
end

local function pickRoles(ready: {Player})
	local pool: {Player} = {}
	local limit = math.min(#ready, #ROLES)
	for i = 1, limit do table.insert(pool, ready[i]) end
	if #pool == 1 then
		local p = pool[1]
		local char = p.Character :: Model
		local wanted = priorities[p] or (if char then char:GetAttribute("PreferredRole") else nil)
		local chosenRole = if typeof(wanted) == "string" and ALLOWED[wanted] then wanted else "Monster"
		if chosenRole == "Monster" then
			lastMonsterId = p.UserId
		end
		priorities[p] = nil
		local entry: Entry = {player = p, role = chosenRole, character = char, eliminated = false, deployed = false}
		byPlayer[p] = entry
		table.insert(entries, entry)
		updateUI:FireClient(p, "RoleAssigned", {role = chosenRole})
		roundHadMonster = (chosenRole == "Monster")
		roundHadHunters = (chosenRole ~= "Monster")
		return
	end
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local used: {[string]: boolean} = {}
	local assignment: {[Player]: string} = {}
	local monster = chooseMonster(pool)
	lastMonsterId = monster.UserId
	assignment[monster], used.Monster = "Monster", true
	for _, p in pool do
		local wanted = priorities[p]
		if not assignment[p] and wanted and not used[wanted] then
			assignment[p], used[wanted] = wanted, true
		end
	end
	for _, p in pool do
		if not assignment[p] then
			for _, role in ROLES do
				if not used[role] then
					assignment[p], used[role] = role, true
					break
				end
			end
		end
		local role = assignment[p]
		local entry: Entry = {player = p, role = role, character = p.Character :: Model, eliminated = false, deployed = false}
		byPlayer[p] = entry
		table.insert(entries, entry)
		updateUI:FireClient(p, "RoleAssigned", {role = role})
	end
	roundHadMonster = false
	roundHadHunters = false
	for _, entry in entries do
		if entry.role == "Monster" then
			roundHadMonster = true
		else
			roundHadHunters = true
		end
	end
end

local function deploy(entry: Entry, point: BasePart, offset: Vector3)
	if entry.eliminated or entry.player.Character ~= entry.character then return end
	entry.character:PivotTo(point.CFrame * CFrame.new(offset + Vector3.new(0, 4, 0)))
	local root = entry.character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	setStats(entry.character, entry.role)
	entry.deployed = true
end

local function stepDropshipRespawns()
	if phase ~= "ActiveHunt" or suddenDeathActive or outcome ~= nil then return end
	local now = os.clock()
	local hunters = spawnPoints(hunterSpawns)
	if #hunters == 0 then return end
	for player, dueAt in pairs(pendingRespawnAt) do
		if now >= dueAt then
			pendingRespawnAt[player] = nil
			local entry = byPlayer[player]
			if entry and entry.eliminated and player.Parent == Players and not suddenDeathActive and outcome == nil then
				local c = player.Character
				if c and c:IsDescendantOf(workspace) then
					entry.character = c
					entry.eliminated = false
					local pt = hunters[rng:NextInteger(1, #hunters)]
					c:PivotTo(pt.CFrame * CFrame.new(0, 4, 0))
					local root = c:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") then
						root.Anchored = false
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
					end
					setStats(c, entry.role)
					updateUI:FireClient(player, "HunterAbilityNotice", { message = "REINSERÇÃO COSTEIRA CONCLUÍDA" })
				end
			end
		end
	end
end

local function countdown(state: string, duration: number, data: Data, checkRoster: boolean): boolean
	local deadline = os.clock() + duration
	local shown = -1
	while true do
		if checkRoster and #readyPlayers() < minRequiredPlayers() then return false end
		local seconds = math.max(0, math.ceil(deadline - os.clock()))
		if seconds ~= shown then
			announce(state, seconds, data)
			shown = seconds
		end
		if state == "ActiveHunt" or state == "MonsterHeadStart" then
			stepDropshipRespawns()
			evaluate()
			if outcome then return false end
		end
		if seconds == 0 then return true end
		task.wait(0.2)
	end
end

local function triggerSuddenDeath()
	if suddenDeathActive then return end
	suddenDeathActive = true
	table.clear(pendingRespawnAt)
	remotes:SetAttribute("SuddenDeath", true)
	remotes:SetAttribute("DropshipRespawnAvailable", false)
	setRelayBeaconsActive(false)
	playRelayGlobalSound(RELAY_SHATTER_SFX, 1.0, 0.82)
	updateUI:FireAllClients("SuddenDeathTriggered", {
		title = "MORTE SÚBITA — RELAY A.E.M. DESTRUÍDO",
		subtitle = "Dropship, reanimações e extração permanentemente desativados.",
	})
	evaluate()
end

local function resetRelay()
	suddenDeathActive = false
	stage3SirenPlayed = false
	table.clear(pendingRespawnAt)
	remotes:SetAttribute("SuddenDeath", false)
	remotes:SetAttribute("DropshipRespawnAvailable", true)
	relay:SetAttribute("MaxRelayHealth", RELAY_MAX_HP)
	relay:SetAttribute("RelayHealth", RELAY_MAX_HP)
	setRelayBeaconsActive(true)
end
relay:GetAttributeChangedSignal("RelayHealth"):Connect(function()
	if phase == "PostMatch" then return end
	local vulnerable = false
	for _, e in entries do
		if e.role == "Monster" and not e.eliminated and e.character:GetAttribute("Stage") == 3 then
			vulnerable = phase == "ActiveHunt"
			break
		end
	end
	if not vulnerable and not suddenDeathActive and relay:GetAttribute("RelayHealth") ~= RELAY_MAX_HP then
		relay:SetAttribute("RelayHealth", RELAY_MAX_HP)
	elseif vulnerable and (relay:GetAttribute("RelayHealth") or RELAY_MAX_HP) <= 0 then
		triggerSuddenDeath()
	else
		evaluate()
	end
end)

local function finishRound(result: Outcome)
	remotes:SetAttribute("RoundClosed", true)
	countdown("PostMatch", POST_MATCH, {winner = result.winner, reason = result.reason}, false)
	table.clear(byPlayer)
	for _, entry in entries do
		local player = entry.player
		if player.Parent == Players then
			enqueue(player)
			if entry.deployed and player.Character == entry.character then
				-- O novo avatar também remove escala, equipamento e efeitos da rodada.
				setStats(entry.character, "Lobby")
				initialized[entry.character] = nil
				task.spawn(function()
					local ok, err = pcall(function() player:LoadCharacterAsync() end)
					if not ok and player.Parent == Players then
						warn("Falha ao retornar ao lobby", player.UserId, err)
						if player.Character == entry.character then
							local spawnAt = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
							if spawnAt then entry.character:PivotTo(spawnAt.CFrame + Vector3.new(0, 4, 0)) end
							initialized[entry.character] = true
						end
					end
				end)
			end
		end
	end
	table.clear(entries)
	outcome = nil
	resetRelay()
end

resetRelay()
while true do
	local ready = readyPlayers()
	local requiredPlayers = minRequiredPlayers()
	if #ready < requiredPlayers then
		if phase ~= "Intermission" or extra.readyPlayers ~= #ready or not extra.waitingForPlayers then
			announce("Intermission", INTERMISSION, {waitingForPlayers = true, readyPlayers = #ready, requiredPlayers = requiredPlayers})
		end
		task.wait(0.5)
		continue
	end
	if not countdown("Intermission", INTERMISSION, {waitingForPlayers = false}, true) then continue end
	ready = readyPlayers()
	if #ready < minRequiredPlayers() then continue end
	local monsters, hunters = spawnPoints(monsterSpawns), spawnPoints(hunterSpawns)
	if #monsters == 0 or #hunters == 0 then
		warn("MatchManager: faltam peças em MonsterSpawns ou HunterSpawns")
		continue
	end
	workspace:SetAttribute("HuntLightingEpoch", workspace:GetServerTimeNow())
	remotes:SetAttribute("MatchId", game:GetService("HttpService"):GenerateGUID(false))
	remotes:SetAttribute("RoundClosed", false)
	announce("RoleAssignment", 0, {})
	pickRoles(ready)
	resetRelay()
	for _, entry in entries do
		if entry.role == "Monster" then deploy(entry, monsters[rng:NextInteger(1, #monsters)], Vector3.zero) end
	end
	if roundHadMonster then
		countdown("MonsterHeadStart", if #entries == 1 then 5 else HEAD_START, {}, false)
	end
	if not outcome then
		local index = 0
		for _, entry in entries do
			if entry.role ~= "Monster" then
				local point = hunters[index % #hunters + 1]
				deploy(entry, point, Vector3.new(math.floor(index / #hunters) * 5, 0, 0))
				index += 1
			end
		end
		countdown("ActiveHunt", HUNT, {}, false)
	end
	finishRound(outcome or {winner = "Hunters", reason = "TimeExpired"})
end
