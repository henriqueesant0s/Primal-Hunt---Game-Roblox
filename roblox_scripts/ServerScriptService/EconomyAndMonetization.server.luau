--!strict
--[[
	PROJECT ABYSS | EconomyAndMonetization.server.lua
	Localização: ServerScriptService/EconomyAndMonetization.server.lua

	Responsabilidade:
	- Persistência versionada com DataStoreService (UpdateAsync, pcall, trava de sessão, BindToClose).
	- Validação server-side de GamePass VIP (+50% Coins, +50% XP, Tag VIP dourada).
	- Validação server-side de GamePass Prioridade de Monstro (2x peso no sorteio integrado à rotação anti-monopólio).
	- Developer Product Boost de Recompensa da Sala via MarketplaceService.ProcessReceipt idempotente e vinculado à partida ativa.
	- Prevenção de duplicação de recompensas e zero confiança no cliente.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LOG_PREFIX = "[PROJECT ABYSS][Economy]"

-- ============================================================================
-- CONFIGURAÇÃO DE MONETIZAÇÃO E RECOMPENSAS (EDITÁVEL)
-- ============================================================================
-- Substitua os IDs abaixo pelos IDs reais publicados no Creator Hub do Roblox.
-- Enquanto estiverem em 0, a verificação externa é ignorada com segurança (sem erros).
local CONFIG = {
	DataStoreName = "ProjectAbyss_PlayerData_v1",
	SchemaVersion = 1,
	GamePassIds = {
		VIP = 0,
		MonsterPriority = 0,
	},
	DeveloperProductIds = {
		RoomCoinBoost = 0,
	},
	Rewards = {
		MonsterWinCoins = 180,
		MonsterWinXP = 240,
		HunterWinCoins = 140,
		HunterWinXP = 200,
		ParticipationCoins = 60,
		ParticipationXP = 90,
	},
	VIPMultiplier = 1.5,
	VIPTagColor = Color3.fromRGB(255, 208, 64),
	MonsterPriorityMultiplier = 2.0,
	RotationPenaltyLastMonster = 0.10,
	RotationBonusPerMatch = 0.25,
	RotationMaxBonus = 1.0,
	MaxStoredReceipts = 50,
	SessionLockTimeoutSeconds = 900,
	LoadMaxAttempts = 4,
	SaveMaxAttempts = 3,
	AutoSaveIntervalSeconds = 120,
}

-- Aguarda inicialização determinística do RemoteBootstrapper
if ReplicatedStorage:GetAttribute("RemotesReady") ~= true then
	while
		ReplicatedStorage:GetAttribute("BootstrapStatus") == nil
		or ReplicatedStorage:GetAttribute("BootstrapStatus") == "Initializing"
	do
		ReplicatedStorage:GetAttributeChangedSignal("BootstrapStatus"):Wait()
	end
end

assert(
	ReplicatedStorage:GetAttribute("RemotesReady") == true,
	string.format("%s RemoteBootstrapper falhou: %s", LOG_PREFIX, tostring(ReplicatedStorage:GetAttribute("BootstrapError")))
)

local remotesRoot = ReplicatedStorage:WaitForChild("Remotes")
local gameRemotes = remotesRoot:WaitForChild("GameRemotes")
local updateUIRemote = gameRemotes:WaitForChild("UpdateUI") :: RemoteEvent

gameRemotes:SetAttribute("VIPGamePassId", CONFIG.GamePassIds.VIP)
gameRemotes:SetAttribute("MonsterPriorityGamePassId", CONFIG.GamePassIds.MonsterPriority)
gameRemotes:SetAttribute("RoomCoinBoostProductId", CONFIG.DeveloperProductIds.RoomCoinBoost)

export type SessionLock = {
	JobId: string,
	LockedAt: number,
}

export type PlayerProfile = {
	SchemaVersion: number,
	Coins: number,
	XP: number,
	WinsAsMonster: number,
	WinsAsHunter: number,
	UnlockedSkins: { [string]: boolean },
	ProcessedReceipts: { [string]: number },
	MatchesSinceMonster: number,
	WasLastMonster: boolean,
	SessionLock: SessionLock?,
}

local SERVER_INSTANCE_TAG = if game.JobId ~= "" then game.JobId else ("Studio_" .. HttpService:GenerateGUID(false))

local playerDataStore: DataStore? = nil
do
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.DataStoreName)
	end)
	if ok then
		playerDataStore = storeOrErr :: DataStore
	else
		warn(string.format("%s DataStoreService indisponível (%s). Operando em modo de sessão em memória.", LOG_PREFIX, tostring(storeOrErr)))
	end
end

local profiles: { [Player]: PlayerProfile } = {}
local loadedPlayers: { [Player]: boolean } = {}
local dirtyPlayers: { [Player]: boolean } = {}
local vipOwnership: { [Player]: boolean } = {}
local monsterPriorityOwnership: { [Player]: boolean } = {}

local activeMatchId: string? = nil
local currentMatchState: string = "Intermission"
local activeParticipants: { [Player]: string } = {}
local roomBoostByMatch: { [string]: boolean } = {}
local rewardedMatchIds: { [string]: boolean } = {}
local isShuttingDown = false

-- ============================================================================
-- SCHEMA, NORMALIZAÇÃO E CÁLCULO DE PESO / ROTAÇÃO
-- ============================================================================
local function createDefaultProfile(): PlayerProfile
	return {
		SchemaVersion = CONFIG.SchemaVersion,
		Coins = 0,
		XP = 0,
		WinsAsMonster = 0,
		WinsAsHunter = 0,
		UnlockedSkins = { Default = true },
		ProcessedReceipts = {},
		MatchesSinceMonster = 0,
		WasLastMonster = false,
		SessionLock = nil,
	}
end

local function normalizeProfile(raw: any): PlayerProfile
	local base = createDefaultProfile()
	if typeof(raw) ~= "table" then
		return base
	end

	base.Coins = if typeof(raw.Coins) == "number" then math.max(0, math.floor(raw.Coins)) else 0
	base.XP = if typeof(raw.XP) == "number" then math.max(0, math.floor(raw.XP)) else 0
	base.WinsAsMonster = if typeof(raw.WinsAsMonster) == "number" then math.max(0, math.floor(raw.WinsAsMonster)) else 0
	base.WinsAsHunter = if typeof(raw.WinsAsHunter) == "number" then math.max(0, math.floor(raw.WinsAsHunter)) else 0
	base.MatchesSinceMonster = if typeof(raw.MatchesSinceMonster) == "number"
		then math.max(0, math.floor(raw.MatchesSinceMonster))
		else 0
	base.WasLastMonster = raw.WasLastMonster == true

	if typeof(raw.UnlockedSkins) == "table" then
		for skinKey, unlocked in pairs(raw.UnlockedSkins) do
			if typeof(skinKey) == "string" and unlocked == true then
				base.UnlockedSkins[skinKey] = true
			end
		end
	end

	if typeof(raw.ProcessedReceipts) == "table" then
		for receiptKey, ts in pairs(raw.ProcessedReceipts) do
			if typeof(receiptKey) == "string" and typeof(ts) == "number" then
				base.ProcessedReceipts[receiptKey] = ts
			end
		end
	end

	if typeof(raw.SessionLock) == "table" and typeof(raw.SessionLock.JobId) == "string" and typeof(raw.SessionLock.LockedAt) == "number" then
		base.SessionLock = {
			JobId = raw.SessionLock.JobId,
			LockedAt = raw.SessionLock.LockedAt,
		}
	end

	return base
end

local function trimReceipts(receipts: { [string]: number }): ()
	local keys: { string } = {}
	for k in pairs(receipts) do
		table.insert(keys, k)
	end
	if #keys <= CONFIG.MaxStoredReceipts then
		return
	end
	table.sort(keys, function(a: string, b: string): boolean
		return receipts[a] < receipts[b]
	end)
	local toRemove = #keys - CONFIG.MaxStoredReceipts
	for i = 1, toRemove do
		receipts[keys[i]] = nil
	end
end

local function computeMonsterWeight(player: Player): number
	local profile = profiles[player]
	if profile == nil then
		return 1.0
	end

	local baseWeight: number
	if profile.WasLastMonster then
		-- Penalidade severa de rotação: impede monopólio mesmo com GamePass 2x
		baseWeight = CONFIG.RotationPenaltyLastMonster
	else
		local bonus = math.min(profile.MatchesSinceMonster * CONFIG.RotationBonusPerMatch, CONFIG.RotationMaxBonus)
		baseWeight = 1.0 + bonus
	end

	if monsterPriorityOwnership[player] == true then
		baseWeight *= CONFIG.MonsterPriorityMultiplier
	end

	return math.max(0.05, math.floor(baseWeight * 100 + 0.5) / 100)
end

local function syncPlayerAttributes(player: Player): ()
	local profile = profiles[player]
	if profile == nil then
		return
	end

	local isVIP = vipOwnership[player] == true
	local hasPriority = monsterPriorityOwnership[player] == true
	local weight = computeMonsterWeight(player)

	player:SetAttribute("Coins", profile.Coins)
	player:SetAttribute("XP", profile.XP)
	player:SetAttribute("WinsAsMonster", profile.WinsAsMonster)
	player:SetAttribute("WinsAsHunter", profile.WinsAsHunter)
	player:SetAttribute("IsVIP", isVIP)
	player:SetAttribute("VIPTagText", if isVIP then "VIP" else nil)
	player:SetAttribute("VIPTagColor", if isVIP then CONFIG.VIPTagColor else nil)
	player:SetAttribute("HasMonsterPriority", hasPriority)
	player:SetAttribute("MonsterSelectionWeight", weight)
	player:SetAttribute("WasLastMonster", profile.WasLastMonster)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats == nil or not leaderstats:IsA("Folder") then
		if leaderstats ~= nil then
			leaderstats:Destroy()
		end
		local statsFolder = Instance.new("Folder")
		statsFolder.Name = "leaderstats"
		statsFolder.Parent = player
		leaderstats = statsFolder
	end

	local coinsValue = leaderstats:FindFirstChild("Coins")
	if coinsValue == nil or not coinsValue:IsA("IntValue") then
		local v = Instance.new("IntValue")
		v.Name = "Coins"
		v.Parent = leaderstats
		coinsValue = v
	end
	(coinsValue :: IntValue).Value = profile.Coins

	local winsValue = leaderstats:FindFirstChild("Wins")
	if winsValue == nil or not winsValue:IsA("IntValue") then
		local v = Instance.new("IntValue")
		v.Name = "Wins"
		v.Parent = leaderstats
		winsValue = v
	end
	(winsValue :: IntValue).Value = profile.WinsAsMonster + profile.WinsAsHunter
end

-- ============================================================================
-- VERIFICAÇÃO DE GAMEPASSES (EXCLUSIVO DO SERVIDOR)
-- ============================================================================
local function checkGamePassServer(player: Player, passId: number): boolean
	if passId <= 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if not ok then
		warn(string.format("%s Falha ao validar GamePass %d para %s: %s", LOG_PREFIX, passId, player.Name, tostring(owns)))
		return false
	end
	return owns == true
end

local function refreshPlayerPasses(player: Player): ()
	vipOwnership[player] = checkGamePassServer(player, CONFIG.GamePassIds.VIP)
	monsterPriorityOwnership[player] = checkGamePassServer(player, CONFIG.GamePassIds.MonsterPriority)

	if player.Parent == Players and loadedPlayers[player] then
		syncPlayerAttributes(player)
		updateUIRemote:FireClient(player, "VIPStatus", {
			isVIP = vipOwnership[player] == true,
			hasMonsterPriority = monsterPriorityOwnership[player] == true,
			tag = if vipOwnership[player] then "VIP" else nil,
		})
	end
end

-- ============================================================================
-- CARREGAMENTO E SALVAMENTO SEGUROS COM UPDATEASYNC + SESSION LOCK
-- ============================================================================
local function getPlayerKey(userId: number): string
	return "Player_" .. tostring(userId)
end

local function loadPlayerProfile(player: Player): ()
	local key = getPlayerKey(player.UserId)

	if playerDataStore == nil then
		local memProfile = createDefaultProfile()
		profiles[player] = memProfile
		loadedPlayers[player] = true
		dirtyPlayers[player] = false
		refreshPlayerPasses(player)
		syncPlayerAttributes(player)
		return
	end

	local store = playerDataStore :: DataStore
	local loadedData: PlayerProfile? = nil

	for attempt = 1, CONFIG.LoadMaxAttempts do
		if player.Parent ~= Players then
			return
		end

		local lockConflict = false
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(oldRaw: any): any
				local profile = normalizeProfile(oldRaw)
				local lock = profile.SessionLock
				local now = os.time()

				if lock ~= nil and lock.JobId ~= SERVER_INSTANCE_TAG and (now - lock.LockedAt) < CONFIG.SessionLockTimeoutSeconds then
					lockConflict = true
					return nil -- Aborta gravação para não sobrescrever sessão ativa em outro servidor
				end

				profile.SessionLock = {
					JobId = SERVER_INSTANCE_TAG,
					LockedAt = now,
				}
				return profile
			end)
		end)

		if ok and not lockConflict and result ~= nil then
			loadedData = normalizeProfile(result)
			break
		end

		if lockConflict then
			warn(string.format("%s Sessão ainda travada para %s (tentativa %d/%d).", LOG_PREFIX, player.Name, attempt, CONFIG.LoadMaxAttempts))
		elseif not ok then
			local errStr = tostring(result)
			if RunService:IsStudio() and (string.find(errStr, "API access is not enabled", 1, true) ~= nil or string.find(errStr, "StudioAccessToApisNotAllowed", 1, true) ~= nil) then
				warn(string.format("%s Studio sem acesso a APIs habilitado (Game Settings > Security > Enable Studio Access to API Services). Carregamento em modo protegido de sessão.", LOG_PREFIX))
				break
			end
			warn(string.format("%s Erro no Load UpdateAsync de %s (tentativa %d/%d): %s", LOG_PREFIX, player.Name, attempt, CONFIG.LoadMaxAttempts, errStr))
		end

		if attempt < CONFIG.LoadMaxAttempts then
			task.wait(1.5 * attempt)
		end
	end

	if player.Parent ~= Players then
		return
	end

	if loadedData == nil then
		warn(string.format("%s Não foi possível carregar dados com segurança para %s; gravações ficarão bloqueadas nesta sessão.", LOG_PREFIX, player.Name))
		profiles[player] = createDefaultProfile()
		loadedPlayers[player] = false
		refreshPlayerPasses(player)
		syncPlayerAttributes(player)
		return
	end

	profiles[player] = loadedData
	loadedPlayers[player] = true
	dirtyPlayers[player] = false

	refreshPlayerPasses(player)
	syncPlayerAttributes(player)

	updateUIRemote:FireClient(player, "EconomyProfileLoaded", {
		coins = loadedData.Coins,
		xp = loadedData.XP,
		winsAsMonster = loadedData.WinsAsMonster,
		winsAsHunter = loadedData.WinsAsHunter,
		isVIP = vipOwnership[player] == true,
		hasMonsterPriority = monsterPriorityOwnership[player] == true,
	})
end

local function savePlayerProfile(player: Player, releaseLock: boolean, extraReceiptId: string?): boolean
	if loadedPlayers[player] ~= true then
		-- Proteção estrita contra sobrescrita caso o carregamento inicial tenha falhado
		return false
	end

	local profile = profiles[player]
	if profile == nil then
		return false
	end

	if playerDataStore == nil then
		if extraReceiptId ~= nil then
			profile.ProcessedReceipts[extraReceiptId] = os.time()
			trimReceipts(profile.ProcessedReceipts)
		end
		dirtyPlayers[player] = false
		return true
	end

	local store = playerDataStore :: DataStore
	local key = getPlayerKey(player.UserId)

	for attempt = 1, CONFIG.SaveMaxAttempts do
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(oldRaw: any): any
				local current = normalizeProfile(oldRaw)

				-- Verifica posse do lock antes de gravar
				if current.SessionLock ~= nil and current.SessionLock.JobId ~= SERVER_INSTANCE_TAG then
					local age = os.time() - current.SessionLock.LockedAt
					if age < CONFIG.SessionLockTimeoutSeconds then
						error("SessionLock pertence a outro servidor ativo.")
					end
				end

				current.SchemaVersion = CONFIG.SchemaVersion
				current.Coins = profile.Coins
				current.XP = profile.XP
				current.WinsAsMonster = profile.WinsAsMonster
				current.WinsAsHunter = profile.WinsAsHunter
				current.UnlockedSkins = table.clone(profile.UnlockedSkins)
				current.MatchesSinceMonster = profile.MatchesSinceMonster
				current.WasLastMonster = profile.WasLastMonster

				for rId, ts in pairs(profile.ProcessedReceipts) do
					current.ProcessedReceipts[rId] = ts
				end
				if extraReceiptId ~= nil then
					current.ProcessedReceipts[extraReceiptId] = os.time()
					profile.ProcessedReceipts[extraReceiptId] = current.ProcessedReceipts[extraReceiptId]
				end
				trimReceipts(current.ProcessedReceipts)
				trimReceipts(profile.ProcessedReceipts)

				if releaseLock then
					current.SessionLock = nil
				else
					current.SessionLock = {
						JobId = SERVER_INSTANCE_TAG,
						LockedAt = os.time(),
					}
				end

				return current
			end)
		end)

		if ok then
			dirtyPlayers[player] = false
			return true
		end

		warn(string.format("%s Falha ao salvar %s (tentativa %d/%d): %s", LOG_PREFIX, player.Name, attempt, CONFIG.SaveMaxAttempts, tostring(err)))
		if attempt < CONFIG.SaveMaxAttempts and not isShuttingDown then
			task.wait(0.8 * attempt)
		end
	end

	return false
end

-- ============================================================================
-- DEVELOPER PRODUCT: PROCESSRECEIPT IDEMPOTENTE (BOOST DE MOEDAS DA SALA)
-- ============================================================================
MarketplaceService.ProcessReceipt = function(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil or loadedPlayers[player] ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = profiles[player]
	if profile == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)

	-- Idempotência: se o recibo já foi registrado anteriormente, confirma sem duplicar efeito
	if profile.ProcessedReceipts[purchaseId] ~= nil then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if CONFIG.DeveloperProductIds.RoomCoinBoost <= 0 or receiptInfo.ProductId ~= CONFIG.DeveloperProductIds.RoomCoinBoost then
		warn(string.format("%s ProductId não reconhecido ou não configurado (%d).", LOG_PREFIX, receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Verificação de partida válida ativa e ausência de boost já aplicado nesta partida
	local matchId = activeMatchId
	local isValidMatch = matchId ~= nil
		and (currentMatchState == "MonsterHeadStart" or currentMatchState == "ActiveHunt")
		and activeParticipants[player] ~= nil
		and roomBoostByMatch[matchId :: string] ~= true

	if not isValidMatch or matchId == nil then
		updateUIRemote:FireClient(player, "RoomBoostDeferred", {
			message = "Boost só pode ser ativado durante uma partida ativa sem boost ativo.",
		})
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Persiste o recibo no DataStore ANTES de retornar PurchaseGranted
	local persisted = savePlayerProfile(player, false, purchaseId)
	if not persisted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	roomBoostByMatch[matchId] = true
	gameRemotes:SetAttribute("RoomCoinBoostActive", true)
	gameRemotes:SetAttribute("RoomCoinBoostMatchId", matchId)

	updateUIRemote:FireAllClients("RoomBoostActivated", {
		buyerName = player.DisplayName,
		matchId = matchId,
		multiplier = 2,
	})

	print(string.format("%s RoomCoinBoost ativado por %s para partida %s (recibo %s).", LOG_PREFIX, player.Name, matchId, purchaseId))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ============================================================================
-- CICLO DE PARTIDA E DISTRIBUIÇÃO DE RECOMPENSAS
-- ============================================================================
local function snapshotParticipants(): ()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char ~= nil then
			local role = char:GetAttribute("Role")
			if
				role == "Monster"
				or role == "Assault"
				or role == "Medic"
				or role == "Trapper"
				or role == "Support"
			then
				activeParticipants[player] = role :: string
			end
		end
	end
end

local function grantMatchRewards(): ()
	local matchId = activeMatchId
	if matchId == nil or rewardedMatchIds[matchId] then
		return
	end
	rewardedMatchIds[matchId] = true

	local winner = gameRemotes:GetAttribute("Winner")
	local roomMultiplier = if roomBoostByMatch[matchId] == true then 2 else 1

	for player, role in pairs(activeParticipants) do
		if player.Parent == Players and profiles[player] ~= nil then
			local profile = profiles[player]
			local isMonster = role == "Monster"
			local didWin = (isMonster and winner == "Monster") or (not isMonster and winner == "Hunters")

			local baseCoins = if didWin
				then (if isMonster then CONFIG.Rewards.MonsterWinCoins else CONFIG.Rewards.HunterWinCoins)
				else CONFIG.Rewards.ParticipationCoins
			local baseXP = if didWin
				then (if isMonster then CONFIG.Rewards.MonsterWinXP else CONFIG.Rewards.HunterWinXP)
				else CONFIG.Rewards.ParticipationXP

			local isVIP = vipOwnership[player] == true
			local vipFactor = if isVIP then CONFIG.VIPMultiplier else 1.0

			local finalCoins = math.floor(baseCoins * roomMultiplier * vipFactor + 0.5)
			local finalXP = math.floor(baseXP * vipFactor + 0.5)

			profile.Coins += finalCoins
			profile.XP += finalXP

			if didWin then
				if isMonster then
					profile.WinsAsMonster += 1
				else
					profile.WinsAsHunter += 1
				end
			end

			if isMonster then
				profile.WasLastMonster = true
				profile.MatchesSinceMonster = 0
			else
				profile.WasLastMonster = false
				profile.MatchesSinceMonster += 1
			end

			dirtyPlayers[player] = true
			syncPlayerAttributes(player)

			updateUIRemote:FireClient(player, "MatchRewards", {
				coins = finalCoins,
				xp = finalXP,
				totalCoins = profile.Coins,
				totalXP = profile.XP,
				won = didWin,
				role = role,
				vipApplied = isVIP,
				roomBoostApplied = roomMultiplier > 1,
			})

			task.spawn(savePlayerProfile, player, false, nil)
		end
	end

	table.clear(activeParticipants)
	activeMatchId = nil
	gameRemotes:SetAttribute("RoomCoinBoostActive", false)
	gameRemotes:SetAttribute("RoomCoinBoostMatchId", nil)
end

local function onMatchStateChanged(): ()
	local stateAttr = gameRemotes:GetAttribute("MatchState")
	if typeof(stateAttr) ~= "string" then
		return
	end
	currentMatchState = stateAttr

	if stateAttr == "MonsterHeadStart" then
		if activeMatchId == nil then
			local serverMatchId = gameRemotes:GetAttribute("MatchId")
			activeMatchId = if typeof(serverMatchId) == "string" and serverMatchId ~= ""
				then serverMatchId
				else HttpService:GenerateGUID(false)
			table.clear(activeParticipants)
			gameRemotes:SetAttribute("RoomCoinBoostActive", false)
			gameRemotes:SetAttribute("RoomCoinBoostMatchId", nil)
		end
		snapshotParticipants()
	elseif stateAttr == "ActiveHunt" then
		if activeMatchId == nil then
			local serverMatchId = gameRemotes:GetAttribute("MatchId")
			activeMatchId = if typeof(serverMatchId) == "string" and serverMatchId ~= ""
				then serverMatchId
				else HttpService:GenerateGUID(false)
		end
		snapshotParticipants()
	elseif stateAttr == "PostMatch" then
		grantMatchRewards()
	elseif stateAttr == "Intermission" then
		table.clear(activeParticipants)
		activeMatchId = nil
		gameRemotes:SetAttribute("RoomCoinBoostActive", false)
		gameRemotes:SetAttribute("RoomCoinBoostMatchId", nil)
	end
end

gameRemotes:GetAttributeChangedSignal("MatchState"):Connect(onMatchStateChanged)
onMatchStateChanged()

-- ============================================================================
-- CONEXÕES DE JOGADORES, GAMEPASS UPDATE, AUTOSAVE E BINDTOCLOSE
-- ============================================================================
local COMBAT_ROLES: { [string]: boolean } = {
	Monster = true,
	Assault = true,
	Medic = true,
	Trapper = true,
	Support = true,
}
local playerRoleConnections: { [Player]: { RBXScriptConnection } } = {}
local charRoleConnections: { [Player]: RBXScriptConnection } = {}

local function recordCharacterParticipant(player: Player, character: Model): ()
	if currentMatchState ~= "MonsterHeadStart" and currentMatchState ~= "ActiveHunt" then
		return
	end
	local role = character:GetAttribute("Role")
	if typeof(role) == "string" and COMBAT_ROLES[role] == true then
		activeParticipants[player] = role
	end
end

local function bindParticipantRoleTracking(player: Player): ()
	local existingConns = playerRoleConnections[player]
	if existingConns ~= nil then
		for _, conn in ipairs(existingConns) do
			if conn.Connected then
				conn:Disconnect()
			end
		end
		table.clear(existingConns)
	end
	if charRoleConnections[player] ~= nil then
		charRoleConnections[player]:Disconnect()
		charRoleConnections[player] = nil
	end

	local conns: { RBXScriptConnection } = {}
	playerRoleConnections[player] = conns

	local function attachChar(character: Model): ()
		if charRoleConnections[player] ~= nil then
			charRoleConnections[player]:Disconnect()
			charRoleConnections[player] = nil
		end
		charRoleConnections[player] = character:GetAttributeChangedSignal("Role"):Connect(function()
			recordCharacterParticipant(player, character)
		end)
		recordCharacterParticipant(player, character)
	end

	table.insert(conns, player.CharacterAdded:Connect(attachChar))
	table.insert(
		conns,
		player.CharacterRemoving:Connect(function()
			if charRoleConnections[player] ~= nil then
				charRoleConnections[player]:Disconnect()
				charRoleConnections[player] = nil
			end
		end)
	)
	if player.Character ~= nil then
		attachChar(player.Character)
	end
end

Players.PlayerAdded:Connect(function(player: Player)
	bindParticipantRoleTracking(player)
	task.spawn(loadPlayerProfile, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindParticipantRoleTracking(player)
	task.spawn(loadPlayerProfile, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	local pConns = playerRoleConnections[player]
	if pConns ~= nil then
		for _, conn in ipairs(pConns) do
			if conn.Connected then
				conn:Disconnect()
			end
		end
		playerRoleConnections[player] = nil
	end
	if charRoleConnections[player] ~= nil then
		charRoleConnections[player]:Disconnect()
		charRoleConnections[player] = nil
	end
	savePlayerProfile(player, true, nil)
	profiles[player] = nil
	loadedPlayers[player] = nil
	dirtyPlayers[player] = nil
	vipOwnership[player] = nil
	monsterPriorityOwnership[player] = nil
	activeParticipants[player] = nil
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased or player.Parent ~= Players then
		return
	end
	if gamePassId == CONFIG.GamePassIds.VIP or gamePassId == CONFIG.GamePassIds.MonsterPriority then
		refreshPlayerPasses(player)
	end
end)

-- Loop de autosave periódico para perfis modificados
task.spawn(function()
	while not isShuttingDown do
		task.wait(CONFIG.AutoSaveIntervalSeconds)
		if isShuttingDown then
			break
		end
		for player, isDirty in pairs(dirtyPlayers) do
			if isDirty and player.Parent == Players then
				task.spawn(savePlayerProfile, player, false, nil)
			end
		end
	end
end)

game:BindToClose(function()
	isShuttingDown = true
	if RunService:IsStudio() and #Players:GetPlayers() == 0 then
		return
	end

	local remainingSaves = 0
	for player, loaded in pairs(loadedPlayers) do
		if loaded then
			remainingSaves += 1
			task.spawn(function()
				savePlayerProfile(player, true, nil)
				remainingSaves -= 1
			end)
		end
	end

	local deadline = os.clock() + 24
	while remainingSaves > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

