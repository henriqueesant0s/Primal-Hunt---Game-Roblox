--!strict
--[[
	PROJECT ABYSS | RemoteBootstrapper.server.lua
	Localização: ServerScriptService/RemoteBootstrapper.server.lua

	Responsabilidade:
	- Inicializar de forma determinística a hierarquia obrigatória de Remotes em ReplicatedStorage.
	- Garantir a existência das pastas obrigatórias em Workspace (Map, ActivePrey, Footprints).
	- Validar tipos de instâncias existentes e interromper com erro explícito em caso de conflito.
	- Validar a presença de Workspace.Map.PowerRelay sem criar objetos falsos ou sobrescrever modelos.
	- Sinalizar prontidão da infraestrutura via atributos em ReplicatedStorage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LOG_PREFIX = "[PROJECT ABYSS][RemoteBootstrapper]"
local SCHEMA_VERSION = 1

type RemoteContractMap = {
	[string]: { string },
}

local REMOTE_CONTRACT: RemoteContractMap = {
	MonsterRemotes = {
		"EatPrey",
		"EvolveStage",
		"UseMonsterSkill",
		"SmellPulse",
	},
	HunterRemotes = {
		"FireWeapon",
		"UseHunterSkill",
		"DeployDome",
		"PlanetScanner",
		"ReviveTeammate",
		"JetpackAction",
	},
	GameRemotes = {
		"MatchStateChanged",
		"UpdateUI",
		"SelectRolePreference",
	},
}

local WORKSPACE_FOLDERS: { string } = {
	"ActivePrey",
	"Footprints",
}

local function logInfo(message: string): ()
	print(string.format("%s %s", LOG_PREFIX, message))
end

local function logWarn(message: string): ()
	warn(string.format("%s AVISO: %s", LOG_PREFIX, message))
end

local function assertNoDuplicateChildren(parent: Instance, childName: string): ()
	local count = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName then
			count += 1
		end
	end

	if count > 1 then
		error(
			string.format(
				"%s Conflito de contrato: encontradas %d instâncias duplicadas com o nome '%s' em '%s'.",
				LOG_PREFIX,
				count,
				childName,
				parent:GetFullName()
			),
			0
		)
	end
end

local function ensureFolder(parent: Instance, folderName: string): Folder
	assertNoDuplicateChildren(parent, folderName)

	local existing = parent:FindFirstChild(folderName)
	if existing ~= nil then
		if not existing:IsA("Folder") then
			error(
				string.format(
					"%s Incompatibilidade de tipo: '%s.%s' deveria ser 'Folder', mas é '%s'. Inicialização interrompida.",
					LOG_PREFIX,
					parent:GetFullName(),
					folderName,
					existing.ClassName
				),
				0
			)
		end
		return existing :: Folder
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent
	return folder
end

local function ensureMapContainer(parent: Instance, mapName: string): Instance
	assertNoDuplicateChildren(parent, mapName)

	local existing = parent:FindFirstChild(mapName)
	if existing ~= nil then
		if not (existing:IsA("Folder") or existing:IsA("Model")) then
			error(
				string.format(
					"%s Incompatibilidade de tipo: '%s.%s' deveria ser 'Folder' ou 'Model', mas é '%s'. Inicialização interrompida.",
					LOG_PREFIX,
					parent:GetFullName(),
					mapName,
					existing.ClassName
				),
				0
			)
		end
		return existing
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = mapName
	mapFolder.Parent = parent
	return mapFolder
end

local function ensureRemoteEvent(parent: Folder, eventName: string): RemoteEvent
	assertNoDuplicateChildren(parent, eventName)

	local existing = parent:FindFirstChild(eventName)
	if existing ~= nil then
		if not existing:IsA("RemoteEvent") then
			error(
				string.format(
					"%s Incompatibilidade de tipo: '%s.%s' deveria ser 'RemoteEvent', mas é '%s'. Inicialização interrompida.",
					LOG_PREFIX,
					parent:GetFullName(),
					eventName,
					existing.ClassName
				),
				0
			)
		end
		return existing :: RemoteEvent
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = eventName
	remoteEvent.Parent = parent
	return remoteEvent
end

local function validatePowerRelay(mapContainer: Instance): boolean
	assertNoDuplicateChildren(mapContainer, "PowerRelay")

	local relay = mapContainer:FindFirstChild("PowerRelay")
	if relay == nil then
		logWarn(
			"Workspace.Map.PowerRelay não encontrado no boot. Nenhum objeto substituto será criado; aguardando instância oficial do sistema de mapa."
		)
		return false
	end

	if not (relay:IsA("Model") or relay:IsA("BasePart") or relay:IsA("Folder")) then
		error(
			string.format(
				"%s Incompatibilidade de tipo: 'Workspace.Map.PowerRelay' possui classe inesperada '%s'.",
				LOG_PREFIX,
				relay.ClassName
			),
			0
		)
	end

	logInfo(string.format("PowerRelay validado (%s: %s).", relay.ClassName, relay:GetFullName()))
	return true
end

local function bootstrapInfrastructure(): ()
	ReplicatedStorage:SetAttribute("RemotesReady", false)
	ReplicatedStorage:SetAttribute("BootstrapStatus", "Initializing")
	ReplicatedStorage:SetAttribute("BootstrapError", nil)
	ReplicatedStorage:SetAttribute("RemoteSchemaVersion", SCHEMA_VERSION)
	ReplicatedStorage:SetAttribute("PowerRelayReady", false)

	local remotesRoot = ensureFolder(ReplicatedStorage, "Remotes")
	remotesRoot:SetAttribute("NetworkReady", false)
	local createdOrValidatedCount = 0

	local categoryNames: { string } = { "MonsterRemotes", "HunterRemotes", "GameRemotes" }
	for _, categoryName in ipairs(categoryNames) do
		local categoryFolder = ensureFolder(remotesRoot, categoryName)
		local remoteList = REMOTE_CONTRACT[categoryName]
		for _, remoteName in ipairs(remoteList) do
			ensureRemoteEvent(categoryFolder, remoteName)
			createdOrValidatedCount += 1
		end
	end

	local mapContainer = ensureMapContainer(Workspace, "Map")
	local spawnFolders: { string } = { "MonsterSpawns", "HunterSpawns", "PreySpawns" }
	local spawnSummaryParts: { string } = {}
	for _, spawnFolderName in ipairs(spawnFolders) do
		local spawnFolder = ensureFolder(mapContainer, spawnFolderName)
		local partCount = 0
		for _, child in ipairs(spawnFolder:GetChildren()) do
			if child:IsA("BasePart") then
				partCount += 1
			end
		end
		table.insert(spawnSummaryParts, string.format("%s=%d", spawnFolderName, partCount))
	end
	logInfo("Spawns do mapa validados (" .. table.concat(spawnSummaryParts, ", ") .. ").")

	for _, folderName in ipairs(WORKSPACE_FOLDERS) do
		ensureFolder(Workspace, folderName)
	end

	local relayFound = validatePowerRelay(mapContainer)
	ReplicatedStorage:SetAttribute("PowerRelayReady", relayFound)

	if not relayFound then
		local relayWatchConnection: RBXScriptConnection? = nil
		relayWatchConnection = mapContainer.ChildAdded:Connect(function(child: Instance)
			if child.Name == "PowerRelay" then
				local ok, valid = pcall(validatePowerRelay, mapContainer)
				if ok and valid then
					ReplicatedStorage:SetAttribute("PowerRelayReady", true)
					if relayWatchConnection ~= nil then
						relayWatchConnection:Disconnect()
						relayWatchConnection = nil
					end
				elseif not ok then
					logWarn("PowerRelay adicionado com tipo inválido: " .. tostring(valid))
				end
			end
		end)
	end

	remotesRoot:SetAttribute("NetworkReady", true)
	ReplicatedStorage:SetAttribute("BootstrapStatus", "Ready")
	ReplicatedStorage:SetAttribute("RemotesReady", true)

	logInfo(
		string.format(
			"Infraestrutura inicializada com sucesso (%d RemoteEvents validados, Workspace sincronizado).",
			createdOrValidatedCount
		)
	)
end

local success, err = xpcall(bootstrapInfrastructure, debug.traceback)
if not success then
	local errorText = tostring(err)
	ReplicatedStorage:SetAttribute("RemotesReady", false)
	ReplicatedStorage:SetAttribute("BootstrapStatus", "Failed")
	ReplicatedStorage:SetAttribute("BootstrapError", errorText)
	error(string.format("%s Falha crítica na inicialização:\n%s", LOG_PREFIX, errorText), 0)
end
