--!strict
--[[
	PROJECT ABYSS | WorldBuilder.server.lua
	Localização: ServerScriptService/WorldBuilder.server.lua

	Responsabilidade (Pessoa 1 - Etapa 1):
	- Construir programaticamente o Workspace.Lobby suspenso em Vector3.new(0, 600, 0) com bunker sci-fi/militar,
	  visão panorâmica da arena e SpawnLocation nativo ("LobbySpawn").
	- Construir programaticamente a arena de caça Workspace.Map (840x840 studs em Y = 0) dentro de Map.Geometry:
	  solo por biomas, cânions de borda, plataforma central do Dropship, pilares rochosos escaláveis + passarelas
	  elevadas para Jetpack, floresta alienígena densa, 4 cavernas cobertas e complexo industrial com iluminação de emergência.
	- Configurar e reutilizar as pastas contratuais (MonsterSpawns, HunterSpawns, PreySpawns, ActivePrey, Footprints)
	  e o modelo PowerRelay (com PrimaryPart e atributos RelayHealth/MaxRelayHealth = 1000) sem quebrar referências
	  já cacheadas por MatchManager, PreyManager ou MonsterServer.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local LOG_PREFIX = "[PROJECT ABYSS][WorldBuilder]"

local LOBBY_ORIGIN = Vector3.new(4500, 600, 0)
local ARENA_SIZE = 1300
local ARENA_HALF = ARENA_SIZE * 0.5
local RELAY_POSITION = Vector3.new(0, 20, 0)
local RELAY_MAX_HP = 12000
local ESTUARY_MAP_VERSION = 6

-- ============================================================================
-- UTILITÁRIOS DE CONSTRUÇÃO E REÚSO DE CONTAINERS
-- ============================================================================
local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("Folder") then
			return existing :: Folder
		end
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensurePersistentModel(parent: Instance, name: string): Model
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("Model") then
			existing:ClearAllChildren()
			existing.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			return existing :: Model
		end
		existing:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = parent
	return model
end

local function makePart(props: {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?,
	castShadow: boolean?,
	reflectance: number?,
}): Part
	local part = Instance.new("Part")
	part.Name = props.name
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = props.color
	part.Material = props.material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.shape ~= nil then
		part.Shape = props.shape
	end
	if props.transparency ~= nil then
		part.Transparency = props.transparency
	end
	if props.canCollide ~= nil then
		part.CanCollide = props.canCollide
	end
	if props.castShadow ~= nil then
		part.CastShadow = props.castShadow
	end
	if props.reflectance ~= nil then
		part.Reflectance = props.reflectance
	end
	part.Parent = props.parent
	return part
end

local function makeRockMeshOrFallback(props: {
	name: string,
	templateName: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	canCollide: boolean?,
	castShadow: boolean?,
	transparency: number?,
}): BasePart
	local worldAssets = ServerStorage:FindFirstChild("WorldAssets")
	local template = if worldAssets ~= nil then worldAssets:FindFirstChild(props.templateName) else nil
	if template ~= nil and template:IsA("BasePart") then
		local cloned = (template :: BasePart):Clone()
		local collidable = if props.canCollide ~= nil then props.canCollide else false
		cloned.Name = props.name
		cloned.Size = props.size
		cloned.CFrame = props.cframe
		cloned.Color = props.color
		cloned.Material = props.material
		if cloned:IsA("MeshPart") then
			(cloned :: MeshPart).TextureID = ""
		end
		cloned.Anchored = true
		cloned.CanCollide = collidable
		cloned.CanQuery = collidable
		cloned.CanTouch = collidable
		cloned.CastShadow = if props.castShadow ~= nil then props.castShadow else true
		if props.transparency ~= nil then
			cloned.Transparency = props.transparency
		end
		cloned.Parent = props.parent
		return cloned
	end

	return makePart({
		name = props.name,
		size = props.size,
		cframe = props.cframe,
		color = props.color,
		material = props.material,
		shape = Enum.PartType.Wedge,
		transparency = props.transparency,
		canCollide = props.canCollide,
		castShadow = props.castShadow,
		parent = props.parent,
	})
end

local function spawnAssetMesh(props: {
	templateName: string,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	canCollide: boolean?,
	castShadow: boolean?,
	keepTexture: boolean?,
}): MeshPart?
	local worldAssets = ServerStorage:FindFirstChild("WorldAssets")
	local template = if worldAssets ~= nil then worldAssets:FindFirstChild(props.templateName) else nil
	if template == nil then
		return nil
	end

	local sourceMesh: MeshPart? = nil
	if template:IsA("MeshPart") then
		sourceMesh = template :: MeshPart
	else
		local inner = template:FindFirstChildWhichIsA("MeshPart", true)
		if inner ~= nil and inner:IsA("MeshPart") then
			sourceMesh = inner :: MeshPart
		end
	end

	if sourceMesh == nil then
		return nil
	end

	local clone = sourceMesh:Clone()
	clone.Name = props.name
	clone.Size = props.size
	clone.CFrame = props.cframe
	if props.keepTexture ~= true then
		clone.TextureID = ""
		clone.Color = props.color
		clone.Material = props.material
	end
	clone.Anchored = true
	clone.CanCollide = if props.canCollide ~= nil then props.canCollide else false
	clone.CastShadow = if props.castShadow ~= nil then props.castShadow else true
	clone.Parent = props.parent
	return clone
end

local function makeEllipsoidPart(props: {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	transparency: number?,
	castShadow: boolean?,
}): Part
	local part = Instance.new("Part")
	part.Name = props.name
	part.Size = props.size
	part.CFrame = props.cframe
	part.Color = props.color
	part.Material = props.material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = if props.castShadow ~= nil then props.castShadow else false
	if props.transparency ~= nil then
		part.Transparency = props.transparency
	end

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.one
	mesh.Parent = part

	part.Parent = props.parent
	return part
end

local function addPointLight(
	parent: Instance,
	color: Color3,
	brightness: number,
	range: number,
	shadows: boolean?
): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = if shadows ~= nil then shadows else false
	light.Parent = parent
	return light
end

local function makeSpawnPart(parent: Folder, name: string, position: Vector3, lookAtPos: Vector3?): Part
	local existing = parent:FindFirstChild(name)
	local part: Part
	if existing ~= nil and existing:IsA("Part") then
		part = existing :: Part
	else
		if existing ~= nil then
			existing:Destroy()
		end
		part = Instance.new("Part")
		part.Name = name
		part.Parent = parent
	end

	part.Size = Vector3.new(4, 0.4, 4)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	if lookAtPos ~= nil then
		local flatTarget = Vector3.new(lookAtPos.X, position.Y, lookAtPos.Z)
		if (flatTarget - position).Magnitude > 0.1 then
			part.CFrame = CFrame.lookAt(position, flatTarget)
		else
			part.CFrame = CFrame.new(position)
		end
	else
		part.CFrame = CFrame.new(position)
	end
	return part
end

local function clearChildrenExcept(parent: Instance, keepName: string?): ()
	for _, child in ipairs(parent:GetChildren()) do
		if keepName == nil or child.Name ~= keepName then
			child:Destroy()
		end
	end
end

local function addSurfaceHeader(
	parent: Instance,
	face: Enum.NormalId,
	titleText: string,
	textColor: Color3,
	bgColor: Color3?
): SurfaceGui
	local sGui = Instance.new("SurfaceGui")
	sGui.Name = "Plaque_" .. face.Name
	sGui.Face = face
	sGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sGui.PixelsPerStud = 36
	sGui.LightInfluence = 0.25
	sGui.Parent = parent

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = bgColor or Color3.fromRGB(10, 14, 20)
	bg.BackgroundTransparency = 0.1
	bg.BorderSizePixel = 0
	bg.Parent = sGui

	local stroke = Instance.new("UIStroke")
	stroke.Color = textColor
	stroke.Thickness = 3
	stroke.Transparency = 0.2
	stroke.Parent = bg

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(0.92, 0.84)
	lbl.Position = UDim2.fromScale(0.04, 0.08)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.Text = titleText
	lbl.TextColor3 = textColor
	lbl.TextScaled = true
	lbl.Parent = bg

	return sGui
end

local function addSpotLight(
	parent: Instance,
	face: Enum.NormalId,
	color: Color3,
	brightness: number,
	range: number,
	angle: number,
	shadows: boolean
): SpotLight
	local light = Instance.new("SpotLight")
	light.Face = face
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Angle = angle
	light.Shadows = shadows
	light.Parent = parent
	return light
end

local function configureWorldLighting(): ()
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = 16.85
	Lighting.GeographicLatitude = 42
	Lighting.Brightness = 1.75
	Lighting.ExposureCompensation = 0.12
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(22, 24, 24)
	Lighting.OutdoorAmbient = Color3.fromRGB(38, 42, 36)
	Lighting.ColorShift_Top = Color3.fromRGB(245, 210, 150)
	Lighting.ColorShift_Bottom = Color3.fromRGB(15, 18, 20)
	Lighting.ShadowSoftness = 0.25
	Lighting.EnvironmentDiffuseScale = 0.36
	Lighting.EnvironmentSpecularScale = 0.92

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky ~= nil then
		sky.CelestialBodiesShown = false
		sky.StarCount = 0
	end

	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo == nil then
		atmo = Instance.new("Atmosphere")
		atmo.Parent = Lighting
	end
	atmo.Density = 0.46
	atmo.Offset = 0.22
	atmo.Haze = 3.2
	atmo.Color = Color3.fromRGB(74, 77, 65)
	atmo.Decay = Color3.fromRGB(216, 182, 118)
	atmo.Glare = 0.42

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays == nil then
		sunRays = Instance.new("SunRaysEffect")
		sunRays.Parent = Lighting
	end
	sunRays.Enabled = true
	sunRays.Intensity = 0.16
	sunRays.Spread = 0.78

	local cc = Lighting:FindFirstChild("EstuaryBaseColorCorrection") :: ColorCorrectionEffect?
	if cc == nil then
		local anyCC = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		if anyCC ~= nil then
			cc = anyCC
		else
			local created = Instance.new("ColorCorrectionEffect")
			created.Name = "EstuaryBaseColorCorrection"
			created.Parent = Lighting
			cc = created
		end
	end
	if cc ~= nil then
		cc.Brightness = -0.02
		cc.Contrast = 0.24
		cc.Saturation = -0.26
		cc.TintColor = Color3.fromRGB(250, 246, 236)
		cc.Enabled = true
	end

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom ~= nil then
		bloom.Intensity = 0.06
		bloom.Size = 18
		bloom.Threshold = 1.95
		bloom.Enabled = true
	end

	local terrain = Workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(42, 48, 38)
	terrain.WaterReflectance = 0.85
	terrain.WaterTransparency = 0.35
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 4
	pcall(function()
		terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(18, 20, 23))
		terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(22, 24, 21))
		terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(32, 34, 29))
		terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(28, 30, 32))
		terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(30, 32, 34))
	end)
end

-- ============================================================================
-- LIMPEZA DO BASEPLATE PADRÃO E SPAWN RAIZ
-- ============================================================================
local function cleanupDefaultWorkspaceTemplate(): ()
	local defaultBaseplate = Workspace:FindFirstChild("Baseplate")
	if defaultBaseplate ~= nil and defaultBaseplate:IsA("BasePart") then
		defaultBaseplate:Destroy()
	end
	local defaultSpawn = Workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn ~= nil and defaultSpawn:IsA("SpawnLocation") then
		defaultSpawn:Destroy()
	end
end

-- ============================================================================
-- 1) CONSTRUÇÃO DO LOBBY BIO-INDUSTRIAL + THE OBLIVION CHAIN SPIRE & MIMIC WELL
-- ============================================================================
local function buildExteriorVista(lobbyFolder: Folder): ()
	local vistaFolder = ensurePersistentModel(lobbyFolder, "ExteriorVista")

	local baseY = LOBBY_ORIGIN.Y - 15.5 -- Y = 584.5
	local waterY = LOBBY_ORIGIN.Y - 12.0 -- Y = 588.0
	local almostBlack = Color3.fromRGB(11, 12, 10)
	local deepCharcoal = Color3.fromRGB(20, 21, 16)
	local weatheredCharcoal = Color3.fromRGB(30, 31, 22)
	local dirtyOliveDark = Color3.fromRGB(44, 42, 28)
	local mutedGold = Color3.fromRGB(202, 168, 88)
	local paleIvory = Color3.fromRGB(246, 228, 168)

	-- Plano abissal contínuo sob toda a bacia alagada (em X = +4500 junto ao Lobby, fora do céu do Estuário)
	makePart({
		name = "BasinAbyssFloor",
		size = Vector3.new(3200, 3, 2200),
		cframe = CFrame.new(0, baseY - 2, -1050),
		color = almostBlack,
		material = Enum.Material.Ground,
		canCollide = false,
		castShadow = false,
		parent = vistaFolder,
	})

	-- Corpos d'água rasos escuros e reflexivos visíveis pelo corredor central + lagoas laterais
	makePart({
		name = "ReflectiveWaterBasin",
		size = Vector3.new(1800, 0.5, 1680),
		cframe = CFrame.new(-65, waterY, -860),
		color = Color3.fromRGB(22, 22, 15),
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.62,
		canCollide = false,
		castShadow = false,
		parent = vistaFolder,
	})
	for _, poolSpec in ipairs({
		{ name = "WesternTarnPool", pos = Vector3.new(-255, waterY + 0.08, -410), size = Vector3.new(320, 0.3, 380), yaw = -18, refl = 0.65 },
		{ name = "EasternFloodPool", pos = Vector3.new(175, waterY + 0.06, -470), size = Vector3.new(280, 0.3, 340), yaw = 22, refl = 0.60 },
	}) do
		makePart({
			name = poolSpec.name,
			size = poolSpec.size,
			cframe = CFrame.new(poolSpec.pos) * CFrame.Angles(0, math.rad(poolSpec.yaw), 0),
			color = Color3.fromRGB(22, 22, 15),
			material = Enum.Material.SmoothPlastic,
			reflectance = poolSpec.refl,
			canCollide = false,
			castShadow = false,
			parent = vistaFolder,
		})
	end
	for gIdx, sheen in ipairs({
		{ pos = Vector3.new(-15, waterY + 0.22, -175), size = Vector3.new(26, 0.06, 115), yaw = -15, transp = 0.91 },
		{ pos = Vector3.new(-58, waterY + 0.22, -295), size = Vector3.new(34, 0.06, 155), yaw = -18, transp = 0.92 },
		{ pos = Vector3.new(-112, waterY + 0.22, -430), size = Vector3.new(44, 0.06, 195), yaw = -17, transp = 0.92 },
		{ pos = Vector3.new(-168, waterY + 0.22, -575), size = Vector3.new(56, 0.06, 235), yaw = -19, transp = 0.93 },
		{ pos = Vector3.new(-222, waterY + 0.22, -715), size = Vector3.new(68, 0.06, 265), yaw = -18, transp = 0.93 },
		{ pos = Vector3.new(-275, waterY + 0.22, -860), size = Vector3.new(82, 0.06, 300), yaw = -16, transp = 0.94 },
	}) do
		makeEllipsoidPart({
			name = "WaterHorizonSheen_" .. tostring(gIdx),
			size = sheen.size,
			cframe = CFrame.new(sheen.pos) * CFrame.Angles(0, math.rad(sheen.yaw), 0),
			color = Color3.fromRGB(194, 160, 82),
			material = Enum.Material.Neon,
			transparency = sheen.transp,
			parent = vistaFolder,
		})
	end

	-- 1) MALHAS NATIVAS BLENDER 5.3 DE PAISAGEM (7638 + 3840 + 2622 tris em coordenadas exatas 1:1)
	local landscapeModel = ensurePersistentModel(vistaFolder, "BlenderLandscapeModel")
	makeRockMeshOrFallback({
		name = "BlenderForegroundBasin",
		templateName = "BlenderBasinMesh",
		size = Vector3.new(1140.0, 247.764, 708.0),
		cframe = CFrame.new(-50.0, 681.297, -436.0) * CFrame.Angles(0, math.pi, 0),
		color = deepCharcoal,
		material = Enum.Material.Basalt,
		canCollide = false,
		castShadow = true,
		parent = landscapeModel,
	})
	makeRockMeshOrFallback({
		name = "BlenderMidgroundCanyons",
		templateName = "BlenderCanyonMesh",
		size = Vector3.new(1283.767, 237.907, 688.835),
		cframe = CFrame.new(-98.935, 684.954, -535.418) * CFrame.Angles(0, math.pi, 0),
		color = weatheredCharcoal,
		material = Enum.Material.Slate,
		canCollide = false,
		castShadow = true,
		parent = landscapeModel,
	})
	makeRockMeshOrFallback({
		name = "BlenderHorizonRange",
		templateName = "BlenderHorizonMesh",
		size = Vector3.new(1970.0, 439.643, 440.0),
		cframe = CFrame.new(-65.0, 793.822, -1040.0) * CFrame.Angles(0, math.pi, 0),
		color = dirtyOliveDark,
		material = Enum.Material.Rock,
		canCollide = false,
		castShadow = false,
		parent = landscapeModel,
	})

	-- Detalhes rochosos e pilares ancestrais em ruína nas margens do cânion
	local function corridorCenterX(zCoord: number): number
		return -10 + ((-zCoord - 120) / 820) * -285
	end
	for rIdx = 1, 24 do
		local t = rIdx / 24
		local zCoord = -118 - (t ^ 1.15) * 320
		local cCenter = corridorCenterX(zCoord)
		local sideSign = if rIdx % 2 == 1 then -1 else 1
		local lane = if (rIdx % 5 == 0) then (math.sin(rIdx * 2.1) * 40) else (sideSign * (72 + (rIdx % 5) * 30 + math.sin(rIdx * 1.7) * 16))
		local scale = 5.0 + (rIdx % 5) * 2.4
		makeRockMeshOrFallback({
			name = "SmallRockCluster_" .. tostring(rIdx),
			templateName = if rIdx % 3 == 0 then "VolcanicRockTemplate" elseif rIdx % 2 == 0 then "BoulderTemplateB" else "BoulderTemplateA",
			size = Vector3.new(scale * 1.45, scale * 1.05, scale * 1.25),
			cframe = CFrame.new(cCenter + lane, waterY - 1.0 + scale * 0.28, zCoord)
				* CFrame.Angles(math.rad(rIdx * 11 % 16), math.rad(rIdx * 53), math.rad((rIdx % 3 - 1) * 12)),
			color = almostBlack,
			material = Enum.Material.Basalt,
			canCollide = false,
			parent = vistaFolder,
		})
	end
	for sIdx = 1, 20 do
		local t = sIdx / 20
		local zCoord = -140 - (t ^ 1.18) * 340
		local cCenter = corridorCenterX(zCoord)
		local sideSign = if sIdx % 2 == 0 then 1 else -1
		local spikeH = 9.0 + (sIdx % 5) * 3.8
		local spikeW = 2.6 + (sIdx % 3) * 1.0
		makeRockMeshOrFallback({
			name = "DesolateSilhouette_" .. tostring(sIdx),
			templateName = "SpikeTemplateA",
			size = Vector3.new(spikeW, spikeH, spikeW * 0.9),
			cframe = CFrame.new(cCenter + sideSign * (62 + (sIdx % 6) * 34), waterY - 2.0 + spikeH * 0.36, zCoord)
				* CFrame.Angles(math.rad(math.sin(sIdx * 1.4) * 8), math.rad(sIdx * 37), math.rad(math.cos(sIdx * 1.9) * 10)),
			color = Color3.fromRGB(9, 10, 8),
			material = Enum.Material.Slate,
			canCollide = false,
			parent = vistaFolder,
		})
	end

	-- 2) THE MIMIC WELL: FENDA DIMENSIONAL DE HORIZONTE DE EVENTOS FRATURADO (Sem sol liso)
	local portalPos = Vector3.new(-312, LOBBY_ORIGIN.Y + 122, -988)
	local mimicWellModel = ensurePersistentModel(vistaFolder, "MimicWellAperture")

	local wellCore = makeEllipsoidPart({
		name = "MimicWellCore",
		size = Vector3.new(124, 195, 32),
		cframe = CFrame.new(portalPos) * CFrame.Angles(math.rad(6), math.rad(-14), math.rad(-11)),
		color = paleIvory,
		material = Enum.Material.Neon,
		transparency = 0.38,
		parent = mimicWellModel,
	})
	addPointLight(wellCore, paleIvory, 1.5, 500, false)

	-- 14 fragmentos irregulares no contorno rompendo o horizonte de eventos da fenda
	for sIdx = 1, 14 do
		local ang = math.rad((sIdx / 14) * 360 + math.sin(sIdx * 2.1) * 14)
		local radDist = 52 + (sIdx % 3) * 26
		local shardPos = portalPos + Vector3.new(math.cos(ang) * radDist, math.sin(ang) * radDist * 1.18, 4 + (sIdx % 2) * 5)
		local shardDir = (shardPos - portalPos).Unit
		makeRockMeshOrFallback({
			name = "MimicWellJaggedShard_" .. tostring(sIdx),
			templateName = "SpikeTemplateA",
			size = Vector3.new(18 + (sIdx % 3) * 8, 95 + (sIdx % 4) * 32, 14 + (sIdx % 2) * 6),
			cframe = CFrame.lookAt(shardPos, shardPos + shardDir) * CFrame.Angles(math.rad(90), math.rad(sIdx * 43), 0),
			color = if sIdx % 2 == 0 then Color3.fromRGB(214, 174, 78) else paleIvory,
			material = Enum.Material.Neon,
			transparency = 0.45 + (sIdx % 3) * 0.11,
			canCollide = false,
			castShadow = false,
			parent = mimicWellModel,
		})
	end

	-- 9 garras/grampos monolíticos escuros da megaestrutura ancorados na borda do Mimic Well
	for cIdx = 1, 9 do
		local ang = math.rad((cIdx / 9) * 360 + 18)
		local clampPos = portalPos + Vector3.new(math.cos(ang) * 96, math.sin(ang) * 118, 22)
		makePart({
			name = "MimicWellClamp_" .. tostring(cIdx),
			size = Vector3.new(26 + (cIdx % 3) * 7, 64 + (cIdx % 4) * 16, 24),
			cframe = CFrame.lookAt(clampPos, portalPos) * CFrame.Angles(math.rad(12), math.rad(cIdx * 17), math.rad(28)),
			color = Color3.fromRGB(8, 9, 7),
			material = Enum.Material.Slate,
			canCollide = false,
			castShadow = false,
			parent = mimicWellModel,
		})
	end

	-- 6 arcos parciais concêntricos de distorção luminosa e névoa de contorno
	for dIdx = 1, 6 do
		local ang = math.rad((dIdx / 6) * 360 + dIdx * 17)
		local arcRadius = 155 + (dIdx % 3) * 52
		local arcPos = portalPos + Vector3.new(math.cos(ang) * arcRadius, math.sin(ang) * arcRadius * 0.92, -10)
		makePart({
			name = "MimicWellDistortionArc_" .. tostring(dIdx),
			size = Vector3.new(72 + (dIdx % 3) * 28, 8, 12),
			cframe = CFrame.new(arcPos) * CFrame.Angles(0, 0, ang + math.pi * 0.5),
			color = if dIdx % 2 == 0 then mutedGold else Color3.fromRGB(168, 144, 72),
			material = Enum.Material.Neon,
			transparency = 0.78 + (dIdx % 2) * 0.06,
			canCollide = false,
			castShadow = false,
			parent = mimicWellModel,
		})
	end

	makeEllipsoidPart({
		name = "MimicWellGoldenAura",
		size = Vector3.new(280, 340, 50),
		cframe = CFrame.new(portalPos + Vector3.new(0, 0, -14)) * CFrame.Angles(math.rad(4), math.rad(-12), math.rad(-9)),
		color = mutedGold,
		material = Enum.Material.Neon,
		transparency = 0.68,
		parent = mimicWellModel,
	})
	makeEllipsoidPart({
		name = "MimicWellHazeVeil",
		size = Vector3.new(490, 470, 68),
		cframe = CFrame.new(portalPos + Vector3.new(0, 0, -28)),
		color = Color3.fromRGB(142, 122, 62),
		material = Enum.Material.Neon,
		transparency = 0.84,
		parent = mimicWellModel,
	})
	for wIdx = 1, 4 do
		makeEllipsoidPart({
			name = "MimicWellHazeWisp_" .. tostring(wIdx),
			size = Vector3.new(210 + wIdx * 32, 90 + wIdx * 16, 40),
			cframe = CFrame.new(portalPos + Vector3.new((wIdx - 2.5) * 75, (wIdx % 2 == 0 and 48 or -38), 28 + wIdx * 10))
				* CFrame.Angles(0, 0, math.rad((wIdx % 2 == 0 and 16 or -20))),
			color = Color3.fromRGB(178, 152, 84),
			material = Enum.Material.Neon,
			transparency = 0.88 + (wIdx % 2) * 0.04,
			parent = mimicWellModel,
		})
	end

	-- 9 feixes volumétricos direcionais saindo do Mimic Well + partículas sutis de distorção atmosférica
	local rayCarrier = makePart({
		name = "MimicWellRayCarrier",
		size = Vector3.new(2, 2, 2),
		cframe = CFrame.new(portalPos),
		color = paleIvory,
		material = Enum.Material.SmoothPlastic,
		transparency = 1,
		canCollide = false,
		castShadow = false,
		parent = mimicWellModel,
	})
	rayCarrier.CanQuery = false
	rayCarrier.CanTouch = false

	local beamAlphaSeq = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.89),
		NumberSequenceKeypoint.new(0.65, 0.94),
		NumberSequenceKeypoint.new(1, 1),
	})
	local beamColorSeq = ColorSequence.new(paleIvory, mutedGold)

	for bIdx = 1, 9 do
		local ang = math.rad(-58 + (bIdx - 1) * 15 + math.sin(bIdx * 2.1) * 4)
		local rayLen = 680 + (bIdx % 3) * 160
		local startOffset = Vector3.new(math.sin(bIdx * 1.7) * 26, math.cos(bIdx * 1.3) * 22, -10)
		local endOffset = startOffset + Vector3.new(math.cos(ang) * rayLen, math.sin(ang) * rayLen * 0.52 - 120, 420 + (bIdx % 3) * 90)

		local att0 = Instance.new("Attachment")
		att0.Name = "RayOrigin_" .. tostring(bIdx)
		att0.Position = startOffset
		att0.Parent = rayCarrier

		local att1 = Instance.new("Attachment")
		att1.Name = "RayTarget_" .. tostring(bIdx)
		att1.Position = endOffset
		att1.Parent = rayCarrier

		local beam = Instance.new("Beam")
		beam.Name = "MimicWellBeam_" .. tostring(bIdx)
		beam.Attachment0 = att0
		beam.Attachment1 = att1
		beam.FaceCamera = true
		beam.LightInfluence = 0
		beam.LightEmission = 0.65
		beam.Color = beamColorSeq
		beam.Transparency = beamAlphaSeq
		beam.Width0 = 28 + (bIdx % 4) * 5
		beam.Width1 = 150 + (bIdx % 3) * 42
		beam.Segments = 12
		beam.Parent = rayCarrier
	end

	local moteAnchor = makePart({
		name = "MimicWellDistortionMoteAnchor",
		size = Vector3.new(120, 40, 120),
		cframe = CFrame.new(-110, 616, -240),
		color = paleIvory,
		material = Enum.Material.SmoothPlastic,
		transparency = 1,
		canCollide = false,
		castShadow = false,
		parent = mimicWellModel,
	})
	moteAnchor.CanQuery = false
	moteAnchor.CanTouch = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MimicWellDistortionMotes"
	emitter.Rate = 6
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.Size = NumberSequence.new(1.2)
	emitter.Color = ColorSequence.new(paleIvory, mutedGold)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.84),
		NumberSequenceKeypoint.new(0.75, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.6
	emitter.Parent = moteAnchor

	-- 3) THE OBLIVION CHAIN SPIRE: MEGAESTRUTURA ASTRONÔMICA ANTIGA DO BLENDER (Coordenadas 1:1)
	local spireModel = ensurePersistentModel(vistaFolder, "OblivionChainSpire")
	makeRockMeshOrFallback({
		name = "SpireCoreAndRings",
		templateName = "OblivionSpireCoreMesh",
		size = Vector3.new(434.142, 479.208, 165.932),
		cframe = CFrame.new(-305.315, 747.098, -949.375) * CFrame.Angles(0, math.pi, 0),
		color = Color3.fromRGB(10, 11, 9),
		material = Enum.Material.Slate,
		canCollide = false,
		castShadow = false,
		parent = spireModel,
	})
	makeRockMeshOrFallback({
		name = "SpireBladesAndNeedles",
		templateName = "OblivionSpireBladesMesh",
		size = Vector3.new(884.814, 812.887, 168.708),
		cframe = CFrame.new(-329.753, 709.855, -941.342) * CFrame.Angles(0, math.pi, 0),
		color = Color3.fromRGB(7, 8, 6),
		material = Enum.Material.Metal,
		canCollide = false,
		castShadow = false,
		parent = spireModel,
	})
	makeRockMeshOrFallback({
		name = "SpireGoldenRimHighlights",
		templateName = "OblivionSpireRimMesh",
		size = Vector3.new(725.317, 535.489, 120.146),
		cframe = CFrame.new(-275.135, 701.884, -944.751) * CFrame.Angles(0, math.pi, 0),
		color = Color3.fromRGB(204, 170, 88),
		material = Enum.Material.Neon,
		transparency = 0.44,
		canCollide = false,
		castShadow = false,
		parent = spireModel,
	})
end

local function buildLobby(): SpawnLocation
	local lobbyFolder = ensureFolder(Workspace, "Lobby")
	lobbyFolder:ClearAllChildren()

	local lobbyAssets = ServerStorage:FindFirstChild("LobbyAssets")
	local hangarTemplate = if lobbyAssets ~= nil then lobbyAssets:FindFirstChild("OrbitalHangar3DTemplate") else nil
	assert(hangarTemplate ~= nil and hangarTemplate:IsA("Model"), LOG_PREFIX .. " OrbitalHangar3DTemplate ausente em ServerStorage.LobbyAssets")

	local delta = LOBBY_ORIGIN - Vector3.new(0, 600, 0)
	for _, item in ipairs((hangarTemplate :: Model):GetChildren()) do
		local cloned = item:Clone()
		if delta.Magnitude > 0.001 then
			if cloned:IsA("BasePart") then
				cloned.CFrame = cloned.CFrame + delta
			elseif cloned:IsA("Model") then
				cloned:PivotTo(cloned:GetPivot() + delta)
			else
				for _, desc in ipairs(cloned:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.CFrame = desc.CFrame + delta
					end
				end
			end
		end
		cloned.Parent = lobbyFolder
	end

	buildExteriorVista(lobbyFolder)
	if delta.Magnitude > 0.001 then
		local vistaModel = lobbyFolder:FindFirstChild("ExteriorVista")
		if vistaModel ~= nil then
			for _, desc in ipairs(vistaModel:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.CFrame = desc.CFrame + delta
				end
			end
		end
	end

	local lobbySpawn = Instance.new("SpawnLocation")
	lobbySpawn.Name = "LobbySpawn"
	lobbySpawn.Size = Vector3.new(12, 0.2, 12)
	lobbySpawn.CFrame = CFrame.new(LOBBY_ORIGIN + Vector3.new(0, 0.1, 40))
	lobbySpawn.Transparency = 1
	lobbySpawn.CanCollide = false
	lobbySpawn.CanTouch = false
	lobbySpawn.CanQuery = false
	lobbySpawn.CastShadow = false
	lobbySpawn.Anchored = true
	lobbySpawn.Neutral = true
	lobbySpawn.Enabled = true
	lobbySpawn.Duration = 0
	lobbySpawn.TopSurface = Enum.SurfaceType.Smooth
	lobbySpawn.Parent = lobbyFolder

	return lobbySpawn
end

-- ============================================================================
-- 2) ECOSYSTEM-DRIVEN 4v1 HUNTING ENVIRONMENT ("HuntingMap_Ecosystem")
--    Evolve Stage 2 Multi-Biome Alien Caldera & Canyon Ravines (1300x1300 studs)
-- ============================================================================
local ECOSYSTEM_VERSION = 6

local PALETTE = {
	OBSIDIAN = Color3.fromRGB(14, 16, 18),
	BASALT = Color3.fromRGB(18, 20, 23),            -- #121417 Weathered wet basalt
	BASALT_CLIFF = Color3.fromRGB(25, 27, 31),
	ANCIENT_ALLOY = Color3.fromRGB(20, 22, 24),     -- Ancient extraterrestrial remnants
	PETRIFIED_WOOD = Color3.fromRGB(207, 199, 176), -- #CFC7B0 Bone-pale dead trees & carcasses
	BONE_WEATHERED = Color3.fromRGB(178, 170, 148),
	FLORA_DEEP = Color3.fromRGB(26, 33, 23),        -- Dense alien coastal fern / dark olive
	FLORA_OLIVE = Color3.fromRGB(44, 51, 33),       -- Mid-canopy alien brush
	FLORA_OCHRE = Color3.fromRGB(82, 73, 44),       -- Pale-amber / dried alien reed stalks
	BRINE_OLIVE = Color3.fromRGB(48, 54, 42),       -- Brackish waterfall & silt olive
	SULFUR_OCHRE = Color3.fromRGB(64, 59, 41),      -- Earthy tar-marsh mineral silt
	ARTERIAL_RED = Color3.fromRGB(132, 30, 30),     -- Muted weathered A.E.M. field containers
	RUST_IRON = Color3.fromRGB(54, 34, 30),         -- Corroded dark oxidized iron
	BEACON_GOLD = Color3.fromRGB(255, 184, 77),     -- #FFB84D Harsh pale-gold floodlights
	SURF_GOLD = Color3.fromRGB(255, 215, 140),      -- Faint pale-gold bioluminescent surf
	CHARCOAL_IRON = Color3.fromRGB(28, 31, 34),
	OIL_SLICK = Color3.fromRGB(9, 10, 12),
	WATERFALL_FOAM = Color3.fromRGB(196, 186, 158),
}

-- 4 Dome Combat Clearings (135x135) equipped with center LoS-breaking pillar clusters
local ARENA_A_CENTER = Vector2.new(-315, 245)  -- SW A.E.M. Geothermal Courtyard
local ARENA_B_CENTER = Vector2.new(-325, -215) -- NW Petrified Canopy Sunken Glade
local ARENA_C_CENTER = Vector2.new(330, -235)  -- NE Obsidian Canyon Confluence Basin
local ARENA_D_CENTER = Vector2.new(325, 210)   -- SE Leviathan Graveyard Caldera

-- 5 Cavernous North & Flank Grottos (>= 60w x 38h Stage 3 Clearance)
local GROTTO_WEST = Vector2.new(-465, -485)
local GROTTO_NORTH = Vector2.new(-18, -530)    -- Hidden Cave Behind Waterfall (EvolutionHollow #1)
local GROTTO_EAST = Vector2.new(445, -490)     -- East Basalt Sea Cave Grotto north of NE Canyons
local GROTTO_SW = Vector2.new(-525, 195)       -- Geothermal Intake Cavern
local GROTTO_SE = Vector2.new(515, 185)        -- Leviathan Bone Cavern

-- Diagonal 45-deg Causeway Approaches to Central Anchor Butte (breaks cross-map orthogonal sightlines!)
local CAUSEWAY_DIRS: { Vector2 } = {
	Vector2.new(-0.72, -0.69).Unit,
	Vector2.new(0.71, -0.70).Unit,
	Vector2.new(-0.69, 0.72).Unit,
	Vector2.new(0.70, 0.71).Unit,
}

type Segment2D = { a: Vector2, b: Vector2, halfWidth: number }

-- Winding Brackish River & Creek Network carving low-ground stealth highways across 1300x1300
local RIVER_SEGMENTS: { Segment2D } = {
	-- West Brackish River Loop (flows past SW Geothermal trench & through NW Canopy forest)
	{ a = Vector2.new(-215, 515), b = Vector2.new(-210, 345), halfWidth = 22 },
	{ a = Vector2.new(-210, 345), b = Vector2.new(-165, 155), halfWidth = 22 },
	{ a = Vector2.new(-165, 155), b = Vector2.new(-420, 145), halfWidth = 23 },
	{ a = Vector2.new(-420, 145), b = Vector2.new(-475, -85), halfWidth = 24 },
	{ a = Vector2.new(-475, -85), b = Vector2.new(-445, -355), halfWidth = 24 },
	{ a = Vector2.new(-445, -355), b = Vector2.new(-195, -430), halfWidth = 24 },
	{ a = Vector2.new(-195, -430), b = Vector2.new(-88, -110), halfWidth = 22 },

	-- East Oily Black Creek Loop (flows through SE Tar Marshes & NE Confluence)
	{ a = Vector2.new(210, 515), b = Vector2.new(185, 340), halfWidth = 23 },
	{ a = Vector2.new(185, 340), b = Vector2.new(155, 135), halfWidth = 22 },
	{ a = Vector2.new(185, 340), b = Vector2.new(430, 265), halfWidth = 24 },
	{ a = Vector2.new(430, 265), b = Vector2.new(485, 45), halfWidth = 24 },
	{ a = Vector2.new(485, 45), b = Vector2.new(335, -70), halfWidth = 23 },
	{ a = Vector2.new(315, -245), b = Vector2.new(105, -135), halfWidth = 22 },
	{ a = Vector2.new(-18, -505), b = Vector2.new(-15, -315), halfWidth = 24 },
}

-- NE Obsidian Slot Canyons: Main Corridors >= 44-46 studs wide (Stage 3 never snags!)
local NE_MAIN_CANYONS: { Segment2D } = {
	-- Western Fork: Center-North pass -> NE Arena Confluence -> North Cliff Grotto
	{ a = Vector2.new(125, -115), b = Vector2.new(245, -185), halfWidth = 23 },
	{ a = Vector2.new(245, -185), b = Vector2.new(210, -340), halfWidth = 23 },
	{ a = Vector2.new(210, -340), b = Vector2.new(340, -455), halfWidth = 23 },
	{ a = Vector2.new(340, -455), b = Vector2.new(445, -490), halfWidth = 23 },
	-- Eastern S-Curve Loop: SE-NE Ridge Pass -> Outer Badlands -> NE Confluence
	{ a = Vector2.new(335, -45), b = Vector2.new(465, -125), halfWidth = 23 },
	{ a = Vector2.new(465, -125), b = Vector2.new(495, -285), halfWidth = 23 },
	{ a = Vector2.new(495, -285), b = Vector2.new(345, -310), halfWidth = 23 },
	{ a = Vector2.new(345, -310), b = Vector2.new(330, -235), halfWidth = 23 },
}

-- Optional 26-stud (halfWidth = 13) narrow fissure shortcuts strictly for Stage 1/2 juking!
local NE_STEALTH_SHORTCUTS: { Segment2D } = {
	{ a = Vector2.new(235, -265), b = Vector2.new(365, -155), halfWidth = 13 },
	{ a = Vector2.new(185, -415), b = Vector2.new(340, -385), halfWidth = 13 },
}

-- 4 Interior Dividing Ridge Spines + South Hunter Drop Bluff (each broken only by 42-48 stud curved S-passes)
type RidgeSpine = { a: Vector2, b: Vector2, halfWidth: number, height: number, passPos: Vector2, passHalfW: number }
local DIVIDING_RIDGES: { RidgeSpine } = {
	-- 1) West Spine separating NW Petrified Canopy from SW Geothermal Complex (pass at -320, 45)
	{ a = Vector2.new(-135, 38), b = Vector2.new(-575, 62), halfWidth = 38, height = 40, passPos = Vector2.new(-320, 50), passHalfW = 24 },
	-- 2) East Spine separating NE Obsidian Canyons from SE Tar Marshes (pass at 335, -45)
	{ a = Vector2.new(135, -42), b = Vector2.new(575, -25), halfWidth = 38, height = 42, passPos = Vector2.new(335, -34), passHalfW = 24 },
	-- 3) North Spine separating NW Canopy from NE Canyons (pass at -15, -315)
	{ a = Vector2.new(-15, -148), b = Vector2.new(-15, -495), halfWidth = 36, height = 44, passPos = Vector2.new(-15, -315), passHalfW = 24 },
	-- 4) South Spine separating SW Ruins from SE Marshes (pass at 0, 265)
	{ a = Vector2.new(0, 152), b = Vector2.new(0, 405), halfWidth = 34, height = 36, passPos = Vector2.new(0, 265), passHalfW = 24 },
}

-- Natural Feeding Lakes, Tidal Basins & Waterfall Plunge Pool
local WATER_BASINS: { { center: Vector2, radius: number } } = {
	{ center = Vector2.new(-385, 485), radius = 34 }, -- SW Coastal Marsh Basin
	{ center = Vector2.new(395, 480), radius = 34 },  -- SE Coastal Tarn
	{ center = Vector2.new(-455, 130), radius = 40 }, -- West Feeding Lake Hotspot
	{ center = Vector2.new(445, 195), radius = 46 },  -- SE Sulfur Tar Marsh Lagoon
	{ center = Vector2.new(-465, -475), radius = 28 },
	{ center = Vector2.new(-18, -485), radius = 38 }, -- Waterfall Plunge Lake
	{ center = Vector2.new(445, -475), radius = 28 },
}

-- 12 Multi-Tiered Rock & Industrial Plateaus (kept clear of NE main canyon floors so Stage 3 never snags!)
local ELEVATED_PLATEAUS: { { center: Vector2, radius: number, height: number, ancient: boolean? } } = {
	{ center = Vector2.new(-215, 225), radius = 26, height = 22, ancient = true },  -- SW Reactor Overlook (+22s)
	{ center = Vector2.new(-405, 295), radius = 28, height = 20, ancient = true },  -- SW Western Refinery Deck (+20s)
	{ center = Vector2.new(215, 215), radius = 26, height = 20, ancient = false },  -- SE Leviathan Spine Terrace (+20s)
	{ center = Vector2.new(445, 115), radius = 26, height = 21, ancient = false },  -- SE Marsh Bluff (+21s)
	{ center = Vector2.new(-225, -205), radius = 28, height = 22, ancient = false },-- NW Tier-1 Forest Ridge (+22s)
	{ center = Vector2.new(-280, -255), radius = 23, height = 42, ancient = true }, -- NW Tier-2 Canopy Step (+42s, +20s step!)
	{ center = Vector2.new(-455, -235), radius = 26, height = 23, ancient = false },-- NW Outer Canopy Mesa (+23s)
	{ center = Vector2.new(150, -240), radius = 25, height = 24, ancient = true },  -- NE Canyon Rim Overlook (+24s, clear of fork!)
	{ center = Vector2.new(155, -425), radius = 22, height = 43, ancient = false }, -- NE Tier-2 Mesa Step (+43s, clear of NWBend)
	{ center = Vector2.new(412, -205), radius = 24, height = 26, ancient = false }, -- NE East Badlands Bluff (center mesa island!)
	{ center = Vector2.new(-155, -15), radius = 22, height = 21, ancient = true },  -- West Relay Flank Butte (+21s)
	{ center = Vector2.new(155, 15), radius = 22, height = 21, ancient = true },    -- East Relay Flank Butte (+21s)
}

local function smoothstep01(t: number): number
	local c = math.clamp(t, 0, 1)
	return c * c * (3 - 2 * c)
end

local function distToSegment2D(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local lenSq = ab:Dot(ab)
	if lenSq < 0.001 then
		return (p - a).Magnitude
	end
	local u = math.clamp((p - a):Dot(ab) / lenSq, 0, 1)
	return (p - (a + ab * u)).Magnitude
end

local function distToMainSlotCanyon(p: Vector2): (number, number)
	local minD = math.huge
	local hwAtMin = 22
	for _, seg in ipairs(NE_MAIN_CANYONS) do
		local d = distToSegment2D(p, seg.a, seg.b)
		if d < minD then
			minD = d
			hwAtMin = seg.halfWidth
		end
	end
	return minD, hwAtMin
end

local function causewayFactor(p: Vector2, rCenter: number): number
	if rCenter < 52 or rCenter > 154 then
		return 0
	end
	local best = 0
	for _, dir in ipairs(CAUSEWAY_DIRS) do
		local proj = p:Dot(dir)
		if proj > 44 and proj < 154 then
			local perp = (p - dir * proj).Magnitude
			if perp < 26 then
				local w = 1 - smoothstep01((perp - 16) / 10)
				if w > best then best = w end
			end
		end
	end
	return best
end

local function isWaterOrRiver(p: Vector2): number
	local rCenter = p.Magnitude
	local riverW = 0
	if rCenter >= 78 and rCenter <= 136 then
		local moatBand = 1 - math.abs(rCenter - 107) / 29
		if moatBand > 0 then
			riverW = math.max(riverW, smoothstep01(moatBand * 1.45))
		end
	end
	for _, seg in ipairs(RIVER_SEGMENTS) do
		local d = distToSegment2D(p, seg.a, seg.b)
		if d < seg.halfWidth + 10 then
			local w = 1 - smoothstep01((d - (seg.halfWidth - 4)) / 14)
			if w > riverW then riverW = w end
		end
	end
	for _, pool in ipairs(WATER_BASINS) do
		local d = (p - pool.center).Magnitude
		if d < pool.radius + 8 then
			local w = 1 - smoothstep01((d - (pool.radius - 5)) / 13)
			if w > riverW then riverW = w end
		end
	end
	riverW *= (1 - causewayFactor(p, rCenter))
	return riverW
end

local function sampleEstuarySurface(x: number, z: number): (number, Enum.Material)
	local p = Vector2.new(x, z)
	local rCenter = p.Magnitude

	-- Cohesive multi-octave rolling terrain base + internal sightline hills (breaks flat homogeneity!)
	local n1 = math.noise(x * 0.0055, z * 0.0055, 17.3)
	local n2 = math.noise(x * 0.016, z * 0.016, 41.7)
	local ridgeN = 1 - math.abs(math.noise(x * 0.0085, z * 0.0085, 73.1))
	local ridgeN2 = 1 - math.abs(math.noise(x * 0.011, z * 0.011, 109.4))
	local northSlope = smoothstep01((380 - z) / 860) * 7.5
	local extraHill = 0
	if rCenter > 135 and z < 470 then
		local mainDist = distToMainSlotCanyon(p)
		if mainDist > 32 then
			local hillMask = smoothstep01((rCenter - 135) / 55) * smoothstep01((mainDist - 32) / 22)
			extraHill = (ridgeN2 ^ 2.0) * 14.0 * hillMask
		end
	end

	local h = 6.5 + northSlope + n1 * 7.5 + n2 * 2.0 + (ridgeN ^ 1.7) * 15.5 + extraHill
	local mat = Enum.Material.Ground

	-- Distinct Biome Topographic Signatures (zero disconnected colors; basalt/ground/slate only!)
	if x < -115 and z < 35 then
		-- Biome 1 (NW): Petrified Canopy Terraces — rolling forest hills (Y=+10..+28) with creek gullies
		local forestWave = smoothstep01(((-x - 125) / 360)) * 10.5 + math.max(0, n1) * 7.5
		h += forestWave
		mat = if n1 > 0.22 then Enum.Material.Basalt else Enum.Material.Ground
	elseif x > 130 and z < 35 then
		-- Biome 2 (NE): Obsidian Slot Canyons & Badlands — elevated tableland carved by 46w main canyons!
		local tableMask = smoothstep01((x - 140) / 75) * smoothstep01((25 - z) / 75) * (1 - smoothstep01((-z - 465) / 80))
		local tableY = 34.0 + (ridgeN ^ 1.7) * 14.0 + n1 * 5.0
		local mainDist, mainHW = distToMainSlotCanyon(p)
		local carveW = 0
		if mainDist < mainHW + 10 then
			-- Steep crisp 46-stud wide canyon walls so Stage 3 fits effortlessly!
			carveW = 1 - smoothstep01((mainDist - mainHW) / 10)
		end
		for _, sc in ipairs(NE_STEALTH_SHORTCUTS) do
			local scDist = distToSegment2D(p, sc.a, sc.b)
			if scDist < sc.halfWidth + 8 then
				carveW = math.max(carveW, 1 - smoothstep01((scDist - sc.halfWidth) / 8))
			end
		end
		local canyonFloorY = 2.8 + n2 * 0.8
		local neElevation = tableY * (1 - carveW) + canyonFloorY * carveW
		h = h * (1 - tableMask) + neElevation * tableMask
		if tableMask > 0.25 then
			mat = Enum.Material.Basalt
		end
	elseif x < -115 and z >= 55 and z < 395 then
		-- Biome 3 (SW): Ruined A.E.M. Geothermal Excavation — stepped angular shelves (+5, +17, +28)
		local rawStep = math.clamp(((-x - 140) / 350) * 20 + n1 * 7, 0, 26)
		local tiered = math.floor(rawStep / 9) * 9 + smoothstep01((rawStep % 9) / 9) * 3.5
		h = 5.5 + tiered + n2 * 0.9
		mat = Enum.Material.Basalt
	elseif x > 115 and z >= 55 and z < 395 then
		-- Biome 4 (SE): Sulfur Tar Marshes & Leviathan Graveyard — sunken marsh flats + tall rocky island ridges (+14..+26)
		local hummock = math.max(0, n1) * 24.0 + (ridgeN ^ 2.1) * 19.0
		h = 2.0 + hummock + n2 * 1.2
		mat = if h > 9.0 then Enum.Material.Basalt else Enum.Material.Mud
	end

	-- 4 Interior Dividing Ridge Spines separating Biomes & Breaking Cross-Map Sightlines
	for _, spine in ipairs(DIVIDING_RIDGES) do
		local dSpine = distToSegment2D(p, spine.a, spine.b)
		if dSpine < spine.halfWidth + 18 then
			local ridgeFactor = 1 - smoothstep01((dSpine - spine.halfWidth * 0.35) / (spine.halfWidth * 0.65 + 18))
			-- Curved S-hook canyon pass carved cleanly through the ridge!
			local passDist = (p - spine.passPos).Magnitude
			local passClear = 1 - smoothstep01((passDist - spine.passHalfW) / 18)
			local eff = ridgeFactor * (1 - passClear)
			if eff > 0.02 then
				local targetRidgeY = spine.height + n2 * 5.0
				h = h * (1 - eff) + math.max(h, targetRidgeY) * eff
				if eff > 0.3 then mat = Enum.Material.Basalt end
			end
		end
	end

	-- South Hunter Insertion Bluff (Z = +395..+460): hides arena interior from Hunter drop zone at Z=+525!
	if z > 375 and z < 475 and math.abs(x) < 580 then
		local bluffMask = smoothstep01((z - 375) / 28) * (1 - smoothstep01((z - 448) / 27))
		-- 3 angled 44-stud wide exit gorges curving out of Insertion Beach
		local gorgeClear = 0
		for _, gx in ipairs({ -225, 0, 225 }) do
			local curvedX = gx + math.sin((z - 425) * 0.035) * 26
			local gd = math.abs(x - curvedX)
			if gd < 34 then
				gorgeClear = math.max(gorgeClear, 1 - smoothstep01((gd - 21) / 13))
			end
		end
		local eff = bluffMask * (1 - gorgeClear)
		if eff > 0.02 then
			h = h * (1 - eff) + (28.0 + n2 * 4.5) * eff
			if eff > 0.35 then mat = Enum.Material.Basalt end
		end
	end

	-- South Black-Sand Shoreline & Deep Abyssal Sea (Z >= 485)
	if z > 485 then
		local beachT = smoothstep01((z - 485) / 68)
		local targetBeach = 4.2 * (1 - beachT * 0.65) + n2 * 0.5
		h = h * (1 - beachT) + targetBeach * beachT
		mat = if z > 535 then Enum.Material.Mud else Enum.Material.Basalt
		if z > 578 then
			local seaT = smoothstep01((z - 578) / 48)
			h = -4.2 - seaT * 7.5
			mat = Enum.Material.Basalt
		end
	end

	-- Multi-tiered Jetpack & Climb Rock Plateaus (+19..+23s steps)
	for _, plat in ipairs(ELEVATED_PLATEAUS) do
		local d = (p - plat.center).Magnitude
		if d < plat.radius + 14 then
			local w = 1 - smoothstep01((d - (plat.radius - 4)) / 18)
			h = h * (1 - w) + plat.height * w
			if w > 0.35 then mat = Enum.Material.Basalt end
		end
	end

	-- 4 Open 135x135 Dome Combat Clearings
	for _, arena in ipairs({
		{ c = ARENA_A_CENTER, y = 2.8 },
		{ c = ARENA_B_CENTER, y = 4.6 },
		{ c = ARENA_C_CENTER, y = 2.8 },
		{ c = ARENA_D_CENTER, y = 2.4 },
	}) do
		local d = (p - arena.c).Magnitude
		if d < 88 then
			local w = 1 - smoothstep01((d - 66) / 22)
			h = h * (1 - w) + arena.y * w
			if w > 0.45 then mat = Enum.Material.Basalt end
		end
	end

	-- Brackish Rivers, Feeding Lakes & Central Moat (-4.3 Mud bed => shallow water!)
	local riverW = isWaterOrRiver(p)
	if riverW > 0.01 then
		h = h * (1 - riverW) + (-4.3) * riverW
		if riverW > 0.35 then
			mat = Enum.Material.Mud
		end
	end

	-- Central Raised Caldera Butte (+20 studs) + 4 Diagonal Causeways
	local cFactor = causewayFactor(p, rCenter)
	if cFactor > 0.01 then
		local rampT = 1 - smoothstep01((rCenter - 60) / 86)
		local rampY = 5.4 + rampT * 14.6
		h = h * (1 - cFactor) + rampY * cFactor
		mat = Enum.Material.Basalt
	end
	if rCenter < 84 then
		local butteW = 1 - smoothstep01((rCenter - 62) / 22)
		h = h * (1 - butteW) + 20.0 * butteW
		if butteW > 0.3 then
			mat = Enum.Material.Basalt
		end
	end

	-- North Inland Eroded Basalt Cliffs (+48..+64s) with Cavernous Grottos carved open
	if z < -445 then
		local grottoClear = 0
		for _, gCenter in ipairs({ GROTTO_WEST, GROTTO_NORTH, GROTTO_EAST }) do
			local gd = (p - gCenter).Magnitude
			if gd < 74 then
				local gw = 1 - smoothstep01((gd - 50) / 24)
				if gw > grottoClear then grottoClear = gw end
			end
		end
		local cliffRise = smoothstep01((-z - 465) / 92) * (1 - grottoClear)
		if cliffRise > 0.01 then
			local cragNoise = math.noise(x * 0.022, z * 0.022, 88.4) * 7.5
			local targetCliffY = 48.0 + smoothstep01((-z - 540) / 70) * 14.0 + cragNoise
			h = h * (1 - cliffRise) + targetCliffY * cliffRise
			if cliffRise > 0.25 then
				mat = Enum.Material.Basalt
			end
		end
	end

	-- East & West Natural Coastal Basalt Perimeter Headlands
	local absX = math.abs(x)
	if absX > 590 and z < 565 then
		local edgeT = smoothstep01((absX - 590) / 62)
		local grottoSideClear = 0
		for _, gCenter in ipairs({ GROTTO_SW, GROTTO_SE }) do
			local gd = (p - gCenter).Magnitude
			if gd < 68 then
				grottoSideClear = math.max(grottoSideClear, 1 - smoothstep01((gd - 46) / 22))
			end
		end
		local headlandY = 44.0 + math.noise(x * 0.025, z * 0.025, 63.2) * 9.0
		local eff = edgeT * (1 - grottoSideClear)
		h = h * (1 - eff) + headlandY * eff
		if eff > 0.2 then
			mat = Enum.Material.Basalt
		end
	end

	-- Final Stage-3 NE Slot Canyon Floor Enforcement (guarantees >= 44-48 stud clear width on all 8 main segments)
	if x > 105 and z < 15 then
		local mainDist, mainHW = distToMainSlotCanyon(p)
		local effHW = mainHW + 1.5
		if mainDist < effHW + 10 then
			local carveFinal = 1 - smoothstep01((mainDist - effHW) / 10)
			local floorY = 2.8 + n2 * 0.8
			h = h * (1 - carveFinal) + math.min(h, floorY) * carveFinal
			if carveFinal > 0.25 then
				mat = Enum.Material.Basalt
			end
		end
	end

	return h, mat
end

local function buildEstuaryVoxelTerrain(): ()
	local terrain = Workspace.Terrain
	terrain:Clear()

	local cell = 4
	local minX, maxX = -688, 688
	local minY, maxY = -16, 76
	local minZ, maxZ = -688, 688

	local nx = math.floor((maxX - minX) / cell)
	local ny = math.floor((maxY - minY) / cell)
	local stripCellsZ = 8
	local totalZ = math.floor((maxZ - minZ) / cell)

	local zStartIdx = 0
	while zStartIdx < totalZ do
		local nz = math.min(stripCellsZ, totalZ - zStartIdx)
		local stripMinZ = minZ + zStartIdx * cell
		local stripMaxZ = stripMinZ + nz * cell

		local mats = table.create(nx)
		local occs = table.create(nx)
		for ix = 1, nx do
			local colM = table.create(ny)
			local colO = table.create(ny)
			for iy = 1, ny do
				colM[iy] = table.create(nz, Enum.Material.Air)
				colO[iy] = table.create(nz, 0)
			end
			mats[ix] = colM
			occs[ix] = colO
		end

		for ix = 1, nx do
			local wx = minX + (ix - 0.5) * cell
			for iz = 1, nz do
				local wz = stripMinZ + (iz - 0.5) * cell
				local surfY, surfMat = sampleEstuarySurface(wx, wz)
				for iy = 1, ny do
					local wyBottom = minY + (iy - 1) * cell
					local wyTop = wyBottom + cell
					if wyBottom < surfY then
						local fill = math.clamp((surfY - wyBottom) / cell, 0, 1)
						mats[ix][iy][iz] = if wyTop < surfY - 6 then Enum.Material.Rock else surfMat
						occs[ix][iy][iz] = fill
					elseif wyBottom < 0 and surfY <= -3.8 then
						local waterFill = if wyBottom == -4 then 0.88 else 1.0
						mats[ix][iy][iz] = Enum.Material.Water
						occs[ix][iy][iz] = waterFill
					end
				end
			end
		end

		local region = Region3.new(
			Vector3.new(minX, minY, stripMinZ),
			Vector3.new(maxX, maxY, stripMaxZ)
		):ExpandToGrid(cell)
		terrain:WriteVoxels(region, cell, mats, occs)

		zStartIdx += nz
		task.wait()
	end
end

-- Helper: Creates an invisible, anchored, non-collidable GameplayNode marker Part with CollectionService tag
local function makeGameplayNode(
	nodesFolder: Folder,
	name: string,
	tagName: string,
	position: Vector3,
	size: Vector3?,
	extraAttrs: { [string]: any }?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.new(6, 6, 6)
	p.CFrame = CFrame.new(position)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p:SetAttribute("NodeType", tagName)
	if extraAttrs then
		for k, v in pairs(extraAttrs) do
			p:SetAttribute(k, v)
		end
	end
	p.Parent = nodesFolder
	CollectionService:AddTag(p, tagName)
	return p
end

-- Helper: Creates a clean, non-snagging Climbable rock/monolith surface in ClimbableSurfaces
-- Tagged with CollectionService "Climbable" AND Attribute IsClimbable = true
local function makeClimbableWall(
	climbFolder: Folder,
	name: string,
	bottomPos: Vector3,
	topPos: Vector3,
	width: number,
	useAncientStyle: boolean?
): BasePart
	local height = math.max(8, topPos.Y - bottomPos.Y)
	local horiz = Vector3.new(topPos.X - bottomPos.X, 0, topPos.Z - bottomPos.Z)
	local outward = if horiz.Magnitude > 0.1 then -horiz.Unit else Vector3.new(0, 0, 1)
	local midPos = Vector3.new((bottomPos.X + topPos.X) * 0.5, bottomPos.Y + height * 0.5, (bottomPos.Z + topPos.Z) * 0.5)
	local wallCF = CFrame.lookAt(midPos, midPos + outward)

	local slab = makePart({
		name = name,
		size = Vector3.new(width, height, 4.5),
		cframe = wallCF,
		color = if useAncientStyle then PALETTE.ANCIENT_ALLOY else PALETTE.BASALT_CLIFF,
		material = if useAncientStyle then Enum.Material.Slate else Enum.Material.Basalt,
		canCollide = true,
		castShadow = false,
		parent = climbFolder,
	})
	slab:SetAttribute("IsClimbable", true)
	CollectionService:AddTag(slab, "Climbable")

	local templateName = if useAncientStyle then "EcosystemAncientMonolithMesh" else "EcosystemClimbableWallMesh"
	local visual = spawnAssetMesh({
		templateName = templateName,
		name = name .. "_ReliefMesh",
		size = Vector3.new(width + 2.5, height + 1.5, 6.2),
		cframe = wallCF,
		color = if useAncientStyle then PALETTE.ANCIENT_ALLOY else PALETTE.BASALT_CLIFF,
		material = if useAncientStyle then Enum.Material.Slate else Enum.Material.Basalt,
		parent = climbFolder,
		canCollide = false,
		castShadow = false,
		keepTexture = false,
	})
	if visual ~= nil then
		visual.CanQuery = false
		visual.CanTouch = false
		visual:SetAttribute("IsClimbable", true)
		CollectionService:AddTag(visual, "Climbable")
		slab.Transparency = 1
	end

	local truss = Instance.new("TrussPart")
	truss.Name = name .. "_ClimbAssist"
	truss.Size = Vector3.new(2, height, 2)
	truss.CFrame = wallCF * CFrame.new(0, 0, -1.6)
	truss.Anchored = true
	truss.Transparency = 1
	truss.CanCollide = true
	truss.CastShadow = false
	truss:SetAttribute("IsClimbable", true)
	CollectionService:AddTag(truss, "Climbable")
	truss.Parent = climbFolder

	return slab
end

local function buildPerimeterAndShoreline(
	terrainGeom: Folder,
	nodesFolder: Folder,
	hunterSpawnsFolder: Folder
): ()
	local boundsFolder = ensureFolder(terrainGeom, "EstuaryPerimeterBounds")
	local h = 150
	local half = ARENA_HALF + 8
	for _, spec in ipairs({
		{ name = "BoundNorth", pos = Vector3.new(0, h * 0.5, -half), size = Vector3.new(ARENA_SIZE + 40, h, 8) },
		{ name = "BoundSouth", pos = Vector3.new(0, h * 0.5, half), size = Vector3.new(ARENA_SIZE + 40, h, 8) },
		{ name = "BoundWest", pos = Vector3.new(-half, h * 0.5, 0), size = Vector3.new(8, h, ARENA_SIZE + 40) },
		{ name = "BoundEast", pos = Vector3.new(half, h * 0.5, 0), size = Vector3.new(8, h, ARENA_SIZE + 40) },
	}) do
		local wall = makePart({
			name = spec.name,
			size = spec.size,
			cframe = CFrame.new(spec.pos),
			color = PALETTE.BASALT,
			material = Enum.Material.Basalt,
			transparency = 1,
			canCollide = true,
			castShadow = false,
			parent = boundsFolder,
		})
		wall.CanQuery = false
	end

	local shoreFolder = ensureFolder(terrainGeom, "ShorelineAndFeedingGrounds")

	-- Pale-gold bioluminescent surf ribbons along South shoreline (Z = ~574)
	local surfColorSeq = ColorSequence.new(PALETTE.SURF_GOLD, PALETTE.BEACON_GOLD)
	local surfAlphaSeq = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.52),
		NumberSequenceKeypoint.new(0.75, 0.58),
		NumberSequenceKeypoint.new(1, 1),
	})
	for sIdx = 1, 10 do
		local x0 = -560 + (sIdx - 1) * 112
		local x1 = x0 + 112
		local z0 = 574 + math.sin(sIdx * 1.3) * 5
		local z1 = 574 + math.sin((sIdx + 1) * 1.3) * 5
		local carrier = makePart({
			name = "BiolumSurfSegment_" .. tostring(sIdx),
			size = Vector3.new(18, 0.25, 4.5),
			cframe = CFrame.new((x0 + x1) * 0.5, 0.14, (z0 + z1) * 0.5),
			color = PALETTE.SURF_GOLD,
			material = Enum.Material.Neon,
			transparency = 0.72,
			canCollide = false,
			castShadow = false,
			parent = shoreFolder,
		})
		carrier.CanQuery = false
		if sIdx % 2 == 1 then
			addPointLight(carrier, PALETTE.SURF_GOLD, 0.65, 42, false)
		end

		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(x0 - carrier.Position.X, 0.08, z0 - carrier.Position.Z)
		a0.Parent = carrier
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(x1 - carrier.Position.X, 0.08, z1 - carrier.Position.Z)
		a1.Parent = carrier

		local surfBeam = Instance.new("Beam")
		surfBeam.Name = "BiolumSurfRibbon_" .. tostring(sIdx)
		surfBeam.Attachment0 = a0
		surfBeam.Attachment1 = a1
		surfBeam.Color = surfColorSeq
		surfBeam.Transparency = surfAlphaSeq
		surfBeam.LightEmission = 0.62
		surfBeam.LightInfluence = 0.2
		surfBeam.Width0 = 5.5
		surfBeam.Width1 = 6.5
		surfBeam.FaceCamera = false
		surfBeam.Segments = 6
		surfBeam.Parent = carrier
	end

	-- Pelagic carcass & bone storytelling sites along coastal drops & distant feeding grounds
	local carcassSites = {
		{ pos = Vector2.new(-265, 505), size = Vector3.new(16, 6.4, 22), yaw = 24 },
		{ pos = Vector2.new(-85, 518), size = Vector3.new(18, 7.2, 24), yaw = -32 },
		{ pos = Vector2.new(105, 512), size = Vector3.new(17, 6.6, 22), yaw = 48 },
		{ pos = Vector2.new(285, 498), size = Vector3.new(19, 7.6, 25), yaw = -46 },
		{ pos = Vector2.new(-455, 130), size = Vector3.new(14, 5.2, 18), yaw = 62 },
		{ pos = Vector2.new(440, 210), size = Vector3.new(16, 6.0, 20), yaw = -38 },
		{ pos = Vector2.new(-425, -395), size = Vector3.new(15, 5.4, 19), yaw = 22 },
		{ pos = Vector2.new(395, -415), size = Vector3.new(15, 5.4, 19), yaw = -28 },
	}
	for idx, spec in ipairs(carcassSites) do
		local surfY = sampleEstuarySurface(spec.pos.X, spec.pos.Y)
		local cf = CFrame.new(spec.pos.X, math.max(-1.0, surfY) + spec.size.Y * 0.35, spec.pos.Y)
			* CFrame.Angles(math.rad((idx % 3 - 1) * 5), math.rad(spec.yaw), math.rad((idx % 2 == 0 and 7 or -7)))
		spawnAssetMesh({
			templateName = "EstuaryPelagicRibcageMesh",
			name = "FeedingCarcassRemains_" .. tostring(idx),
			size = spec.size,
			cframe = cf,
			color = if idx > 4 then PALETTE.BONE_WEATHERED else PALETTE.PETRIFIED_WOOD,
			material = Enum.Material.Slate,
			parent = shoreFolder,
			canCollide = (idx <= 4),
			castShadow = false,
			keepTexture = false,
		})
	end

	-- Weathered A.E.M. field drop crates & beacon at South Insertion Beach (Z = ~535)
	for idx, crateSpec in ipairs({
		{ pos = Vector2.new(-38, 535), yaw = 18 },
		{ pos = Vector2.new(34, 538), yaw = -24 },
	}) do
		local y = sampleEstuarySurface(crateSpec.pos.X, crateSpec.pos.Y)
		spawnAssetMesh({
			templateName = "SciFiContainer",
			name = "ShoreFieldCrate_" .. tostring(idx),
			size = Vector3.new(8.2, 4.6, 5.4),
			cframe = CFrame.new(crateSpec.pos.X, y + 2.1, crateSpec.pos.Y) * CFrame.Angles(0, math.rad(crateSpec.yaw), math.rad(3)),
			color = PALETTE.ARTERIAL_RED,
			material = Enum.Material.CorrodedMetal,
			parent = shoreFolder,
			canCollide = true,
			castShadow = false,
			keepTexture = false,
		})
	end
	local dropBeacon = makePart({
		name = "InsertionFieldTripod",
		size = Vector3.new(1.2, 7.5, 1.2),
		cframe = CFrame.new(-4, (sampleEstuarySurface(-4, 534)) + 3.6, 534) * CFrame.Angles(math.rad(4), 0, math.rad(-3)),
		color = PALETTE.CHARCOAL_IRON,
		material = Enum.Material.Metal,
		castShadow = false,
		parent = shoreFolder,
	})
	local flareHead = makePart({
		name = "InsertionBeaconLamp",
		size = Vector3.new(1.5, 0.9, 1.5),
		cframe = dropBeacon.CFrame * CFrame.new(0, 4.0, 0),
		color = PALETTE.BEACON_GOLD,
		material = Enum.Material.Neon,
		castShadow = false,
		parent = shoreFolder,
	})
	addPointLight(flareHead, PALETTE.BEACON_GOLD, 1.35, 44, false)

	-- 4 HunterSpawns + 4 "HunterSpawnZone" GameplayNodes behind the South Insertion Bluff (Z = 524)
	clearChildrenExcept(hunterSpawnsFolder, nil)
	for i, pt in ipairs({
		Vector2.new(-24, 524),
		Vector2.new(-8, 522),
		Vector2.new(8, 522),
		Vector2.new(24, 524),
	}) do
		local gy = sampleEstuarySurface(pt.X, pt.Y)
		local worldPos = Vector3.new(pt.X, gy + 0.5, pt.Y)
		makeSpawnPart(hunterSpawnsFolder, string.format("Spawn%02d", i), worldPos, Vector3.new(0, 20, 0))
		makeGameplayNode(nodesFolder, string.format("HunterSpawnZone_%02d", i), "HunterSpawnZone", worldPos + Vector3.new(0, 3, 0), Vector3.new(10, 8, 10))
	end
end

local function buildRiversOilAndWaterfall(terrainGeom: Folder): ()
	local riverFolder = ensureFolder(terrainGeom, "RiverAndWaterfallSystem")

	-- 16 Onyx Oil-Slick Patches along rivers & SE Tar Marshes (MasksFootprints = true + muffles audio)
	for _, spec in ipairs({
		{ pos = Vector2.new(-165, 155), size = Vector2.new(36, 48), yaw = 18 },
		{ pos = Vector2.new(-465, 25), size = Vector2.new(36, 54), yaw = -8 },
		{ pos = Vector2.new(-455, -245), size = Vector2.new(36, 50), yaw = 26 },
		{ pos = Vector2.new(-135, -265), size = Vector2.new(32, 46), yaw = -38 },
		{ pos = Vector2.new(175, 285), size = Vector2.new(40, 56), yaw = 12 },
		{ pos = Vector2.new(345, 225), size = Vector2.new(44, 58), yaw = -24 },
		{ pos = Vector2.new(445, 195), size = Vector2.new(48, 62), yaw = 32 },
		{ pos = Vector2.new(265, 145), size = Vector2.new(38, 48), yaw = -16 },
		{ pos = Vector2.new(475, 45), size = Vector2.new(36, 50), yaw = 18 },
		{ pos = Vector2.new(335, -48), size = Vector2.new(34, 46), yaw = -30 },
		{ pos = Vector2.new(210, -210), size = Vector2.new(34, 48), yaw = 22 },
		{ pos = Vector2.new(155, 135), size = Vector2.new(32, 46), yaw = -12 },
		{ pos = Vector2.new(-107, 0), size = Vector2.new(28, 42), yaw = 2 },
		{ pos = Vector2.new(107, 0), size = Vector2.new(28, 42), yaw = -4 },
		{ pos = Vector2.new(-320, 48), size = Vector2.new(32, 46), yaw = 14 },
		{ pos = Vector2.new(0, 265), size = Vector2.new(32, 44), yaw = -8 },
	}) do
		local slick = makePart({
			name = "EstuaryOilPatch",
			size = Vector3.new(spec.size.X, 0.14, spec.size.Y),
			cframe = CFrame.new(spec.pos.X, -0.35, spec.pos.Y) * CFrame.Angles(0, math.rad(spec.yaw), 0),
			color = PALETTE.OIL_SLICK,
			material = Enum.Material.Slate,
			reflectance = 0.22,
			transparency = 0.24,
			canCollide = false,
			castShadow = false,
			parent = riverFolder,
		})
		local oval = Instance.new("SpecialMesh")
		oval.MeshType = Enum.MeshType.Sphere
		oval.Scale = Vector3.one
		oval.Parent = slick
		slick.CanQuery = true
		slick:SetAttribute("MasksFootprints", true)
		CollectionService:AddTag(slick, "EstuaryOilPatch")
	end

	-- Hidden Cave Waterfall Curtain at GROTTO_NORTH (-18, 0..38, -502)
	local wfOrigin = Vector3.new(GROTTO_NORTH.X, 19, GROTTO_NORTH.Y + 28)
	local wfAnchor = makePart({
		name = "NorthGrottoWaterfallAnchor",
		size = Vector3.new(54, 38, 1.5),
		cframe = CFrame.new(wfOrigin),
		color = PALETTE.WATERFALL_FOAM,
		material = Enum.Material.Glass,
		transparency = 0.76,
		canCollide = false,
		castShadow = false,
		parent = riverFolder,
	})
	wfAnchor.CanQuery = false
	wfAnchor.CanTouch = false

	for bIdx = 1, 4 do
		local xOff = -19 + (bIdx - 1) * 12.6
		local topAtt = Instance.new("Attachment")
		topAtt.Position = Vector3.new(xOff, 19, 0)
		topAtt.Parent = wfAnchor
		local botAtt = Instance.new("Attachment")
		botAtt.Position = Vector3.new(xOff, -19.5, 2.5)
		botAtt.Parent = wfAnchor

		local veil = Instance.new("Beam")
		veil.Name = "WaterfallVeilBeam_" .. tostring(bIdx)
		veil.Attachment0 = topAtt
		veil.Attachment1 = botAtt
		veil.Width0 = 14.0
		veil.Width1 = 16.0
		veil.LightEmission = 0.16
		veil.LightInfluence = 0.75
		veil.Color = ColorSequence.new(PALETTE.WATERFALL_FOAM, PALETTE.BRINE_OLIVE)
		veil.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.28),
			NumberSequenceKeypoint.new(0.9, 0.35),
			NumberSequenceKeypoint.new(1, 0.75),
		})
		veil.FaceCamera = false
		veil.Parent = wfAnchor
	end

	local mistPart = makePart({
		name = "WaterfallPlungeMist",
		size = Vector3.new(48, 4, 12),
		cframe = CFrame.new(wfOrigin.X, 1.2, wfOrigin.Z + 3),
		color = PALETTE.WATERFALL_FOAM,
		material = Enum.Material.SmoothPlastic,
		transparency = 1,
		canCollide = false,
		castShadow = false,
		parent = riverFolder,
	})
	mistPart.CanQuery = false
	local mistPE = Instance.new("ParticleEmitter")
	mistPE.Rate = 18
	mistPE.Lifetime = NumberRange.new(2.2, 3.8)
	mistPE.Speed = NumberRange.new(2, 5)
	mistPE.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 11) })
	mistPE.Color = ColorSequence.new(PALETTE.WATERFALL_FOAM)
	mistPE.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(0.5, 0.62), NumberSequenceKeypoint.new(1, 1) })
	mistPE.Parent = mistPart

	local wfSound = Instance.new("Sound")
	wfSound.Name = "WaterfallAmbientLoop"
	wfSound.SoundId = "rbxassetid://9120550180"
	wfSound.Looped = true
	wfSound.Volume = 0.48
	wfSound.RollOffMode = Enum.RollOffMode.InverseTapered
	wfSound.RollOffMinDistance = 18
	wfSound.RollOffMaxDistance = 240
	wfSound.Parent = mistPart
	wfSound:Play()
end

-- Builds Multi-Tiered Plateaus + Dividing Ridge Climb Faces + Flanking Ambush Walls
local function buildElevationPlateausAndClimbables(terrainGeom: Folder, climbFolder: Folder): ()
	local platFolder = ensureFolder(terrainGeom, "JetpackPlateausAndRidges")

	for idx, plat in ipairs(ELEVATED_PLATEAUS) do
		makeRockMeshOrFallback({
			name = "PlateauRimCrag_" .. tostring(idx),
			templateName = if idx % 2 == 0 then "RockTemplateA" else "VolcanicRockTemplate",
			size = Vector3.new(plat.radius * 1.45, 7.5, plat.radius * 1.25),
			cframe = CFrame.new(plat.center.X, plat.height - 2.2, plat.center.Y) * CFrame.Angles(0, math.rad(idx * 41), 0),
			color = PALETTE.BASALT_CLIFF,
			material = Enum.Material.Basalt,
			canCollide = true,
			castShadow = false,
			parent = platFolder,
		})

		spawnAssetMesh({
			templateName = if plat.ancient then "EcosystemAncientMonolithMesh" else "CreatorStore_BasaltCliffAMesh",
			name = "PlateauCoverPillar_" .. tostring(idx),
			size = Vector3.new(9.5, 11.5, 6.2),
			cframe = CFrame.new(plat.center.X + 7, plat.height + 4.8, plat.center.Y - 5) * CFrame.Angles(math.rad(6), math.rad(idx * 55), math.rad(-5)),
			color = if plat.ancient then PALETTE.ANCIENT_ALLOY else PALETTE.BASALT_CLIFF,
			material = Enum.Material.Slate,
			parent = platFolder,
			canCollide = true,
			castShadow = false,
			keepTexture = false,
		})

		for sideIdx, angDeg in ipairs({ 35 + idx * 30, 205 + idx * 30 }) do
			local rad = math.rad(angDeg)
			local dir2D = Vector2.new(math.cos(rad), math.sin(rad))
			local foot2D = plat.center + dir2D * (plat.radius + 7)
			local lip2D = plat.center + dir2D * (plat.radius - 3)
			local footY = math.max(-2.0, (sampleEstuarySurface(foot2D.X, foot2D.Y)))
			makeClimbableWall(
				climbFolder,
				string.format("Plateau%d_ClimbFace_%d", idx, sideIdx),
				Vector3.new(foot2D.X, footY, foot2D.Y),
				Vector3.new(lip2D.X, plat.height + 0.5, lip2D.Y),
				13,
				plat.ancient == true and sideIdx == 2
			)
		end
	end

	local extraClimbRoutes = {
		-- Central Caldera Anchor Butte climb walls (4 sides between causeways)
		{ name = "CentralButte_ClimbWest", bot = Vector3.new(-74, -1.0, 0), top = Vector3.new(-58, 20.4, 0), w = 15, ancient = true },
		{ name = "CentralButte_ClimbEast", bot = Vector3.new(74, -1.0, 0), top = Vector3.new(58, 20.4, 0), w = 15, ancient = true },
		{ name = "CentralButte_ClimbNorth", bot = Vector3.new(0, -1.0, -74), top = Vector3.new(0, 20.4, -58), w = 15, ancient = true },
		{ name = "CentralButte_ClimbSouth", bot = Vector3.new(0, -1.0, 74), top = Vector3.new(0, 20.4, 58), w = 15, ancient = false },

		-- Dividing Ridge Crossing Faces (allows Monster to vault between biomes without funneling through passes!)
		{ name = "WestSpine_ClimbNorth", bot = Vector3.new(-215, 8.0, 2), top = Vector3.new(-215, 40.5, 28), w = 16, ancient = false },
		{ name = "WestSpine_ClimbSouth", bot = Vector3.new(-215, 6.0, 96), top = Vector3.new(-215, 40.5, 68), w = 16, ancient = false },
		{ name = "EastSpine_ClimbSouth", bot = Vector3.new(235, 3.0, 12), top = Vector3.new(235, 42.5, -16), w = 16, ancient = false },
		{ name = "EastSpine_ClimbNorth", bot = Vector3.new(455, 2.0, -82), top = Vector3.new(455, 42.5, -52), w = 16, ancient = false },
		{ name = "NorthSpine_ClimbWest", bot = Vector3.new(-58, 9.0, -215), top = Vector3.new(-32, 44.5, -215), w = 16, ancient = true },
		{ name = "NorthSpine_ClimbEast", bot = Vector3.new(30, 8.0, -215), top = Vector3.new(4, 44.5, -215), w = 16, ancient = true },
		{ name = "SouthSpine_ClimbWest", bot = Vector3.new(-42, 4.0, 215), top = Vector3.new(-16, 36.5, 215), w = 15, ancient = true },
		{ name = "SouthSpine_ClimbEast", bot = Vector3.new(42, 3.0, 215), top = Vector3.new(16, 36.5, 215), w = 15, ancient = false },
		-- South Hunter Bluff climbs + NE Slot Canyon tableland climbs
		{ name = "SouthBluff_ClimbWest", bot = Vector3.new(-125, 4.0, 472), top = Vector3.new(-125, 29.0, 442), w = 15, ancient = false },
		{ name = "SouthBluff_ClimbEast", bot = Vector3.new(125, 4.0, 472), top = Vector3.new(125, 29.0, 442), w = 15, ancient = false },
		{ name = "NECanyonRim_ClimbMid", bot = Vector3.new(295, 3.0, -205), top = Vector3.new(295, 36.0, -172), w = 15, ancient = false },
		{ name = "NECanyonRim_ClimbNorth", bot = Vector3.new(385, 3.0, -345), top = Vector3.new(415, 38.0, -372), w = 15, ancient = false },
	}

	for _, r in ipairs(extraClimbRoutes) do
		makeClimbableWall(climbFolder, r.name, r.bot, r.top, r.w, r.ancient)
	end
end

local function buildGrottosEvolutionHollowsAndNests(
	terrainGeom: Folder,
	nodesFolder: Folder,
	monsterSpawnsFolder: Folder
): ()
	local cavesFolder = ensureFolder(terrainGeom, "EvolutionHollowsAndAlienRuins")
	local nestsFolder = ensureFolder(terrainGeom, "TerritorialNestSites")

	-- 5 Cavernous North & Flank Grottos (>= 60w x 38h Stage 3 Clearance; NO glowing neon crystals!)
	local grottoSpecs = {
		{ name = "WestSeaGrotto", center = GROTTO_WEST, facing = Vector2.new(0.28, 1).Unit, archSpan = 60, archClearH = 38 },
		{ name = "NorthWaterfallGrotto", center = GROTTO_NORTH, facing = Vector2.new(0, 1), archSpan = 62, archClearH = 39 },
		{ name = "EastArenaCGrotto", center = GROTTO_EAST, facing = Vector2.new(-0.32, 1).Unit, archSpan = 62, archClearH = 39 },
		{ name = "SWGeothermalIntakeGrotto", center = GROTTO_SW, facing = Vector2.new(1, -0.15).Unit, archSpan = 60, archClearH = 38 },
		{ name = "SELeviathanCaveGrotto", center = GROTTO_SE, facing = Vector2.new(-1, 0.1).Unit, archSpan = 60, archClearH = 38 },
	}

	for _, g in ipairs(grottoSpecs) do
		local rawFloorY = sampleEstuarySurface(g.center.X, g.center.Y)
		local baseFloorY = math.max(1.0, rawFloorY)
		local origin3D = Vector3.new(g.center.X, baseFloorY, g.center.Y)
		local forward3D = Vector3.new(g.facing.X, 0, g.facing.Y).Unit
		local grottoCF = CFrame.lookAt(origin3D, origin3D + forward3D)
		local halfSpan = g.archSpan * 0.5

		for _, side in ipairs({ -1, 1 }) do
			makeRockMeshOrFallback({
				name = string.format("%s_Pillar_%d", g.name, side),
				templateName = if side < 0 then "VolcanicRockTemplate" else "MountainTemplateC",
				size = Vector3.new(42, g.archClearH + 22, 58),
				cframe = grottoCF * CFrame.new(side * (halfSpan + 29), (g.archClearH + 14) * 0.46, 2)
					* CFrame.Angles(0, math.rad(side * 16), math.rad(side * -5)),
				color = PALETTE.BASALT,
				material = Enum.Material.Basalt,
				canCollide = true,
				castShadow = false,
				parent = cavesFolder,
			})
		end

		makeRockMeshOrFallback({
			name = g.name .. "_BackCliffMass",
			templateName = "MountainTemplateC",
			size = Vector3.new(g.archSpan + 86, g.archClearH + 28, 40),
			cframe = grottoCF * CFrame.new(0, (g.archClearH + 20) * 0.45, 62),
			color = PALETTE.BASALT,
			material = Enum.Material.Basalt,
			canCollide = true,
			castShadow = false,
			parent = cavesFolder,
		})

		for crownIdx, zOff in ipairs({ -14, 18 }) do
			makeRockMeshOrFallback({
				name = string.format("%s_DomeCrown_%d", g.name, crownIdx),
				templateName = if crownIdx % 2 == 1 then "VolcanicRockTemplate" else "RockTemplateB",
				size = Vector3.new(g.archSpan + 64, 16, 42),
				cframe = grottoCF * CFrame.new(0, g.archClearH + 11 + (crownIdx % 2) * 2, zOff)
					* CFrame.Angles(math.rad((crownIdx - 1.5) * 3), math.rad(crownIdx * 16), 0),
				color = PALETTE.BASALT_CLIFF,
				material = Enum.Material.Basalt,
				canCollide = true,
				castShadow = false,
				parent = cavesFolder,
			})
		end
	end

	-- Walkable Upper Cliff Ledges & Horizon Spires along North Wall (Z = -590)
	for cIdx = 1, 9 do
		local cx = -560 + (cIdx - 1) * 140
		makeRockMeshOrFallback({
			name = "NorthCliffSpire_" .. tostring(cIdx),
			templateName = if cIdx % 2 == 0 then "Evolve_SlotCanyonWallMesh" else "MountainTemplateC",
			size = Vector3.new(88, 62 + (cIdx % 3) * 12, 48),
			cframe = CFrame.new(cx, 50, -595) * CFrame.Angles(0, math.rad(cIdx * 31), 0),
			color = PALETTE.BASALT,
			material = Enum.Material.Basalt,
			canCollide = true,
			castShadow = false,
			parent = cavesFolder,
		})
	end

	-- 8 Concealed Evolution Hollows distributed across all 5 Biomes for safe Stage 1 -> Stage 2 evolution!
	local evolutionHollows = {
		{ name = "EvolutionHollow_WaterfallCave", pos = Vector2.new(-18, -535), profile = "HighCover_BehindWaterfall_DualFlankArch", buildRuin = false },
		{ name = "EvolutionHollow_NWCanopyRootHollow", pos = Vector2.new(-495, -285), profile = "DenseForestCanopy_RootEnclosure_TwoExits", buildRuin = true },
		{ name = "EvolutionHollow_NESlotCanyonPocket", pos = Vector2.new(475, -365), profile = "SlotCanyonDeadfall_OverheadBridge_TwoExits", buildRuin = false },
		{ name = "EvolutionHollow_SWGeothermalVault", pos = Vector2.new(-475, 295), profile = "IndustrialBlastWall_SiloShelter_ThreeExits", buildRuin = true },
		{ name = "EvolutionHollow_SELeviathanSkullHollow", pos = Vector2.new(465, 285), profile = "BoneCanopy_OilyStealthCover_ThreeExits", buildRuin = false },
		{ name = "EvolutionHollow_NWSpineCrevice", pos = Vector2.new(-215, -395), profile = "CliffOverhang_RiverBedEscape", buildRuin = false },
		{ name = "EvolutionHollow_NEBadlandsAlcove", pos = Vector2.new(195, -425), profile = "CanyonPocket_HighVerticalEscape", buildRuin = true },
		{ name = "EvolutionHollow_SouthWestTrench", pos = Vector2.new(-185, 345), profile = "IndustrialCoolantTrench_StealthPocket", buildRuin = false },
	}

	for idx, eh in ipairs(evolutionHollows) do
		local gy = math.max(0.5, (sampleEstuarySurface(eh.pos.X, eh.pos.Y)))
		local center3D = Vector3.new(eh.pos.X, gy, eh.pos.Y)
		makeGameplayNode(nodesFolder, eh.name, "EvolutionHollow", center3D + Vector3.new(0, 4, 0), Vector3.new(36, 18, 36), { RiskRewardProfile = eh.profile })

		if idx ~= 1 then
			local baseYaw = (idx - 1) * 58
			for arcIdx, relDeg in ipairs({ 135, 225 }) do
				local ang = math.rad(baseYaw + relDeg)
				local wallPos = center3D + Vector3.new(math.cos(ang) * 32, 9.5, math.sin(ang) * 32)
				makeRockMeshOrFallback({
					name = string.format("%s_ShelterCrag_%d", eh.name, arcIdx),
					templateName = if arcIdx == 1 then "CreatorStore_BasaltCliffAMesh" else "RockTemplateA",
					size = Vector3.new(26, 22, 14),
					cframe = CFrame.lookAt(wallPos, Vector3.new(center3D.X, wallPos.Y, center3D.Z)),
					color = PALETTE.BASALT_CLIFF,
					material = Enum.Material.Basalt,
					canCollide = true,
					castShadow = false,
					parent = cavesFolder,
				})
			end
			if eh.buildRuin then
				spawnAssetMesh({
					templateName = "EcosystemAncientMonolithMesh",
					name = eh.name .. "_CantileverMonolith",
					size = Vector3.new(18, 30, 8),
					cframe = CFrame.new(center3D + Vector3.new(0, 12, -24)) * CFrame.Angles(math.rad(20), math.rad(idx * 25), 0),
					color = PALETTE.ANCIENT_ALLOY,
					material = Enum.Material.Slate,
					parent = cavesFolder,
					canCollide = true,
					castShadow = false,
					keepTexture = false,
				})
			end
		end
	end

	-- 5 Asymmetric Territorial Nest Locations (3+ approach routes, natural rock cover)
	local nestSites = {
		{ name = "NestLocation_NWCanopyGlade", pos = ARENA_B_CENTER, routes = 4 },
		{ name = "NestLocation_NESlotConfluence", pos = ARENA_C_CENTER, routes = 4 },
		{ name = "NestLocation_SWGeothermalYard", pos = ARENA_A_CENTER, routes = 4 },
		{ name = "NestLocation_SELeviathanBasin", pos = ARENA_D_CENTER, routes = 3 },
		{ name = "NestLocation_NorthWaterfallRidge", pos = Vector2.new(-155, -455), routes = 3 },
	}
	for nIdx, ns in ipairs(nestSites) do
		local gy = math.max(0.5, (sampleEstuarySurface(ns.pos.X, ns.pos.Y)))
		local nPos = Vector3.new(ns.pos.X, gy, ns.pos.Y)
		makeGameplayNode(nodesFolder, ns.name, "NestLocation", nPos + Vector3.new(0, 4, 0), Vector3.new(44, 18, 44), { ApproachRoutes = ns.routes })

		for k = 1, 3 do
			local ang = math.rad((k - 1) * 120 + nIdx * 28)
			local rockPos = nPos + Vector3.new(math.cos(ang) * 34, 4.0, math.sin(ang) * 34)
			makeRockMeshOrFallback({
				name = string.format("Nest%d_DefenseCrag_%d", nIdx, k),
				templateName = if k % 2 == 0 then "BoulderTemplateA" else "RockTemplateB",
				size = Vector3.new(15, 10, 11),
				cframe = CFrame.lookAt(rockPos, Vector3.new(nPos.X, rockPos.Y, nPos.Z)),
				color = PALETTE.BASALT,
				material = Enum.Material.Basalt,
				canCollide = true,
				castShadow = false,
				parent = nestsFolder,
			})
		end
		local nestTpl = ServerStorage:FindFirstChild("WorldAssets") and ServerStorage.WorldAssets:FindFirstChild("AbyssalEvolutionNest3DTemplate")
		if nestTpl and nestTpl:IsA("Model") then
			local nestClone = nestTpl:Clone()
			nestClone.Name = string.format("Nest%d_AbyssalEvolutionNest3D", nIdx)
			nestClone:SetAttribute("EvolutionNest", true)
			nestClone:SetAttribute("NestId", ns.name)
			nestClone:PivotTo(CFrame.new(nPos + Vector3.new(0, -0.35, 0)) * CFrame.Angles(0, math.atan2(-nPos.X, -nPos.Z), 0))
			nestClone.Parent = nestsFolder
		end
		makeRockMeshOrFallback({
			name = string.format("Nest%d_OrganicClutchHusk", nIdx),
			templateName = "BoulderTemplateB",
			size = Vector3.new(9.5, 3.6, 8.5),
			cframe = CFrame.new(nPos + Vector3.new(0, 1.2, 0)),
			color = PALETTE.OBSIDIAN,
			material = Enum.Material.Slate,
			canCollide = true,
			castShadow = false,
			parent = nestsFolder,
		})
	end

	-- 4 MonsterSpawns deep inside remote North/NW/NE grottos & canyon coves (zero LoS from South Drop!)
	clearChildrenExcept(monsterSpawnsFolder, nil)
	for i, mSpec in ipairs({
		{ pos = Vector3.new(GROTTO_WEST.X + 20, 9.0, GROTTO_WEST.Y + 30), look = Vector3.new(-320, 9, -220) },
		{ pos = Vector3.new(GROTTO_NORTH.X + 2, 9.0, GROTTO_NORTH.Y + 34), look = Vector3.new(0, 20, 0) },
		{ pos = Vector3.new(GROTTO_EAST.X - 24, 9.0, GROTTO_EAST.Y + 14), look = Vector3.new(330, 9, -235) },
		{ pos = Vector3.new(-471, 7.0, -275), look = Vector3.new(-325, 7, -215) },
	}) do
		makeSpawnPart(monsterSpawnsFolder, string.format("Spawn%02d", i), mSpec.pos, mSpec.look)
		makeGameplayNode(nodesFolder, string.format("MonsterSpawnZone_%02d", i), "MonsterSpawnZone", mSpec.pos + Vector3.new(0, 3, 0), Vector3.new(14, 10, 14))
	end
end

-- ============================================================================
-- DISTINCT BIOME LANDMARKS & CORRIDOR SIGHTLINE (LoS) BAFFLES
-- Differentiated solely by geology, vertical silhouette & architecture (cohesive dark palette!)
-- ============================================================================
local function buildBiomeLandmarksAndLoSBaffles(terrainGeom: Folder): ()
	local lmFolder = ensureFolder(terrainGeom, "BiomeLandmarksAndLoSBaffles")

	-- Helper: safely places rock/wall baffle in NE without ever narrowing a main canyon below 38-46 studs!
	local function placeCheckedBaffle(name: string, pos2D: Vector2, size: Vector3, yawDeg: number, templateName: string, color: Color3, mat: Enum.Material, sinkFrac: number?): ()
		local dMain, hw = distToMainSlotCanyon(pos2D)
		local clearanceNeeded = hw + math.max(size.X, size.Z) * 0.48 + 2.0
		if dMain < clearanceNeeded then
			return
		end
		local surfY = sampleEstuarySurface(pos2D.X, pos2D.Y)
		if surfY < -1.5 then return end
		spawnAssetMesh({
			templateName = templateName,
			name = name,
			size = size,
			cframe = CFrame.new(pos2D.X, surfY + size.Y * (sinkFrac or 0.42), pos2D.Y) * CFrame.Angles(0, math.rad(yawDeg), 0),
			color = color,
			material = mat,
			parent = lmFolder,
			canCollide = true,
			castShadow = false,
			keepTexture = false,
		})
	end

	-- 1) BIOME 2 (NE): OBSIDIAN SLOT CANYON CLIFF SPIRES & WIDE OVERHEAD BASALT BRIDGES (>= 46w Stage 3 clearance!)
	local neArchBridges = {
		{ pos = Vector2.new(185, -150), span = 96, h = 44, yaw = 38 },
		{ pos = Vector2.new(228, -262), span = 98, h = 46, yaw = 78 },
		{ pos = Vector2.new(275, -398), span = 96, h = 46, yaw = -42 },
		{ pos = Vector2.new(400, -85), span = 94, h = 44, yaw = 52 },
		{ pos = Vector2.new(480, -205), span = 96, h = 46, yaw = 82 },
		{ pos = Vector2.new(335, -272), span = 94, h = 44, yaw = -65 },
	}
	for aIdx, arch in ipairs(neArchBridges) do
		spawnAssetMesh({
			templateName = "EstuaryBasaltArchMesh",
			name = "NE_CanyonBridgeArch_" .. tostring(aIdx),
			size = Vector3.new(arch.span, arch.h, 24),
			cframe = CFrame.new(arch.pos.X, arch.h * 0.48 + 3.0, arch.pos.Y) * CFrame.Angles(0, math.rad(arch.yaw), 0),
			color = PALETTE.BASALT_CLIFF,
			material = Enum.Material.Basalt,
			parent = lmFolder,
			canCollide = false, -- Overhead arch bridges span clear above; terrain walls handle canyon collision!
			castShadow = false,
			keepTexture = false,
		})
	end

	-- Striated Obsidian Slot-Canyon Spire clusters framing the NE mesas (never narrowing main canyon < 42s!)
	local neCanyonWallSpots = {
		{ p = Vector2.new(165, -225), s = Vector3.new(44, 46, 26), y = 25 },
		{ p = Vector2.new(285, -135), s = Vector3.new(46, 48, 28), y = -35 },
		{ p = Vector2.new(295, -295), s = Vector3.new(42, 46, 24), y = 62 },
		{ p = Vector2.new(410, -205), s = Vector3.new(48, 50, 28), y = 12 },
		{ p = Vector2.new(410, -345), s = Vector3.new(46, 48, 28), y = -48 },
		{ p = Vector2.new(555, -205), s = Vector3.new(48, 52, 30), y = 85 },
		{ p = Vector2.new(135, -345), s = Vector3.new(44, 48, 26), y = -18 },
		{ p = Vector2.new(275, -510), s = Vector3.new(48, 52, 30), y = 40 },
		{ p = Vector2.new(545, -355), s = Vector3.new(46, 50, 28), y = 110 },
		{ p = Vector2.new(155, -465), s = Vector3.new(44, 48, 26), y = -72 },
		{ p = Vector2.new(535, -95), s = Vector3.new(46, 46, 26), y = 22 },
		{ p = Vector2.new(175, -62), s = Vector3.new(40, 42, 24), y = -55 },
	}
	for idx, wSpot in ipairs(neCanyonWallSpots) do
		placeCheckedBaffle(
			"NE_SlotCanyonSpire_" .. tostring(idx),
			wSpot.p,
			wSpot.s,
			wSpot.y,
			if idx % 2 == 0 then "Evolve_SlotCanyonWallMesh" else "CreatorStore_BasaltCliffAMesh",
			PALETTE.BASALT,
			Enum.Material.Basalt,
			0.40
		)
	end

	-- 2) BIOME 3 (SW): RUINED A.E.M. GEOTHERMAL COMPLEX (Silos, Coolant Pipes, Blast Walls, Crates)
	local swSilos = {
		{ pos = Vector2.new(-255, 295), s = Vector3.new(32, 42, 26), yaw = 22 },
		{ pos = Vector2.new(-385, 205), s = Vector3.new(34, 46, 28), yaw = -48 },
		{ pos = Vector2.new(-355, 345), s = Vector3.new(30, 38, 24), yaw = 65 },
		{ pos = Vector2.new(-215, 165), s = Vector3.new(28, 36, 24), yaw = -18 },
		{ pos = Vector2.new(-495, 255), s = Vector3.new(34, 44, 28), yaw = 112 },
		{ pos = Vector2.new(-295, 135), s = Vector3.new(28, 38, 24), yaw = 42 },
	}
	for sIdx, silo in ipairs(swSilos) do
		local gy = sampleEstuarySurface(silo.pos.X, silo.pos.Y)
		spawnAssetMesh({
			templateName = "Evolve_GeothermalSiloRuinMesh",
			name = "SW_GeothermalSilo_" .. tostring(sIdx),
			size = silo.s,
			cframe = CFrame.new(silo.pos.X, gy + silo.s.Y * 0.44, silo.pos.Y) * CFrame.Angles(0, math.rad(silo.yaw), 0),
			color = if sIdx % 2 == 0 then PALETTE.RUST_IRON else PALETTE.CHARCOAL_IRON,
			material = Enum.Material.CorrodedMetal,
			parent = lmFolder,
			canCollide = true,
			castShadow = false,
			keepTexture = false,
		})
	end

	-- Elevated A.E.M. Conduit Pipe Bridges (Stage 3 clearance Y=36+ below, LoS break overhead!)
	for pIdx, pSpec in ipairs({
		{ a = Vector2.new(-255, 295), b = Vector2.new(-385, 205), y = 40 },
		{ a = Vector2.new(-385, 205), b = Vector2.new(-295, 135), y = 39 },
		{ a = Vector2.new(-215, 165), b = Vector2.new(-255, 295), y = 38 },
	}) do
		local pA = Vector3.new(pSpec.a.X, pSpec.y, pSpec.a.Y)
		local pB = Vector3.new(pSpec.b.X, pSpec.y, pSpec.b.Y)
		local span = (pB - pA).Magnitude
		makePart({
			name = "SW_GeothermalPipeBridge_" .. tostring(pIdx),
			size = Vector3.new(5.5, 5.5, span),
			cframe = CFrame.lookAt((pA + pB) * 0.5, pB),
			color = PALETTE.CHARCOAL_IRON,
			material = Enum.Material.CorrodedMetal,
			canCollide = true,
			castShadow = false,
			parent = lmFolder,
		})
	end

	-- Weathered A.E.M. tactical blast barriers & crates in SW ruins
	for cIdx, cratePos in ipairs({
		Vector2.new(-295, 255), Vector2.new(-338, 222), Vector2.new(-265, 225), Vector2.new(-355, 275),
		Vector2.new(-165, 275), Vector2.new(-425, 175), Vector2.new(-245, 365), Vector2.new(-445, 325),
	}) do
		local gy = sampleEstuarySurface(cratePos.X, cratePos.Y)
		spawnAssetMesh({
			templateName = "SciFiContainer",
			name = "SW_AEMRuinedModule_" .. tostring(cIdx),
			size = Vector3.new(12, 8.5, 7.5),
			cframe = CFrame.new(cratePos.X, gy + 3.8, cratePos.Y) * CFrame.Angles(0, math.rad(cIdx * 43), math.rad((cIdx % 3 - 1) * 4)),
			color = if cIdx % 2 == 0 then PALETTE.ARTERIAL_RED else PALETTE.RUST_IRON,
			material = Enum.Material.CorrodedMetal,
			parent = lmFolder,
			canCollide = true,
			castShadow = false,
			keepTexture = false,
		})
	end

	-- 3) BIOME 4 (SE): LEVIATHAN GRAVEYARD COLOSSAL RIBCAGE ARCHES & SULFUR TAR MONOLITHS
	local seRibs = {
		{ pos = Vector2.new(275, 245), s = Vector3.new(36, 22, 42), yaw = 32 },
		{ pos = Vector2.new(335, 195), s = Vector3.new(38, 24, 44), yaw = -24 },
		{ pos = Vector2.new(385, 245), s = Vector3.new(34, 21, 40), yaw = 68 },
		{ pos = Vector2.new(235, 315), s = Vector3.new(32, 20, 38), yaw = -52 },
		{ pos = Vector2.new(445, 155), s = Vector3.new(36, 23, 42), yaw = 14 },
		{ pos = Vector2.new(475, 285), s = Vector3.new(34, 21, 40), yaw = -76 },
		{ pos = Vector2.new(185, 165), s = Vector3.new(30, 18, 36), yaw = 45 },
		{ pos = Vector2.new(355, 85), s = Vector3.new(32, 20, 38), yaw = -36 },
		{ pos = Vector2.new(295, 355), s = Vector3.new(30, 19, 36), yaw = 18 },
		{ pos = Vector2.new(515, 125), s = Vector3.new(34, 22, 40), yaw = -62 },
	}
	for rIdx, rib in ipairs(seRibs) do
		local gy = math.max(-1.0, (sampleEstuarySurface(rib.pos.X, rib.pos.Y)))
		spawnAssetMesh({
			templateName = "EstuaryPelagicRibcageMesh",
			name = "SE_LeviathanColossalRib_" .. tostring(rIdx),
			size = rib.s,
			cframe = CFrame.new(rib.pos.X, gy + rib.s.Y * 0.36, rib.pos.Y) * CFrame.Angles(math.rad((rIdx % 3 - 1) * 6), math.rad(rib.yaw), math.rad((rIdx % 2 == 0 and 8 or -8))),
			color = if rIdx % 2 == 0 then PALETTE.PETRIFIED_WOOD else PALETTE.BONE_WEATHERED,
			material = Enum.Material.Slate,
			parent = lmFolder,
			canCollide = false, -- Arch ribs act as overhead bone tunnels & visual cover without snagging!
			castShadow = false,
			keepTexture = false,
		})
	end

	-- Solid Basalt Hummock Spires & LoS-breaking Rock Ridges across SE Marshes, SW Approaches, Center & NW
	for bIdx, spec in ipairs({
		{ p = Vector2.new(245, 155), s = Vector3.new(32, 34, 24) },
		{ p = Vector2.new(395, 145), s = Vector3.new(34, 36, 26) },
		{ p = Vector2.new(285, 295), s = Vector3.new(32, 34, 24) },
		{ p = Vector2.new(485, 225), s = Vector3.new(34, 36, 26) },
		{ p = Vector2.new(145, 245), s = Vector3.new(30, 32, 24) },
		{ p = Vector2.new(365, 335), s = Vector3.new(34, 36, 26) },
		{ p = Vector2.new(210, 365), s = Vector3.new(30, 32, 24) },
		{ p = Vector2.new(415, 45), s = Vector3.new(30, 34, 24) },
		{ p = Vector2.new(165, 85), s = Vector3.new(28, 30, 22) },
		{ p = Vector2.new(525, 345), s = Vector3.new(34, 36, 26) },
		-- Center Caldera outer ring baffles (breaks cross-moat LoS)
		{ p = Vector2.new(-175, -105), s = Vector3.new(28, 32, 22) },
		{ p = Vector2.new(165, 115), s = Vector3.new(28, 32, 22) },
		{ p = Vector2.new(-165, 115), s = Vector3.new(28, 32, 22) },
		{ p = Vector2.new(115, 175), s = Vector3.new(28, 30, 22) },
		{ p = Vector2.new(-115, -175), s = Vector3.new(28, 32, 22) },
		{ p = Vector2.new(105, -185), s = Vector3.new(26, 30, 20) },
	}) do
		placeCheckedBaffle(
			"SE_MarshBasaltCrag_" .. tostring(bIdx),
			spec.p,
			spec.s,
			bIdx * 47,
			if bIdx % 2 == 0 then "Evolve_SlotCanyonWallMesh" else "CreatorStore_BasaltCliffBMesh",
			PALETTE.BASALT,
			Enum.Material.Basalt,
			0.38
		)
	end

	-- 4) BIOME 1 (NW) & TRANSITION CORRIDOR SIGHTLINE BAFFLES + RIDGE PASS MONOLITHS
	local transitionBaffles = {
		-- NW Petrified Canopy rock ridges & interlocking root spurs
		Vector2.new(-245, -135), Vector2.new(-395, -165), Vector2.new(-305, -315), Vector2.new(-165, -285),
		Vector2.new(-425, -45), Vector2.new(-525, -175), Vector2.new(-355, -425), Vector2.new(-145, -185),
		Vector2.new(-285, -85), Vector2.new(-385, -295), Vector2.new(-495, -85), Vector2.new(-195, -345),
		Vector2.new(-375, -115), Vector2.new(-265, -445),
		-- Dividing Ridge Pass Gate Monoliths (forced S-curve sightline breaks)
		Vector2.new(-322, 22), Vector2.new(-318, 78),
		Vector2.new(338, -62), Vector2.new(332, -8),
		Vector2.new(-38, -312), Vector2.new(12, -318),
		Vector2.new(-22, 268), Vector2.new(24, 262),
		-- South Hunter Bluff exit baffles + Insertion Beach rock outcrops
		Vector2.new(-235, 395), Vector2.new(12, 390), Vector2.new(235, 395),
		Vector2.new(-125, 485), Vector2.new(125, 485), Vector2.new(-345, 365), Vector2.new(325, 405),
		-- Dome Combat Clearing Center Pillars + Flanking Cover (pillar-kiting cover inside Arenas A..D)
		ARENA_A_CENTER + Vector2.new(14, -12), ARENA_A_CENTER + Vector2.new(-16, 14),
		ARENA_B_CENTER + Vector2.new(-14, 12), ARENA_B_CENTER + Vector2.new(16, -14),
		ARENA_C_CENTER + Vector2.new(12, 14), ARENA_C_CENTER + Vector2.new(-14, -12),
		ARENA_D_CENTER + Vector2.new(-12, -14), ARENA_D_CENTER + Vector2.new(16, 12),
		-- Ridge-crest and open-pocket baffles breaking long internal lines of sight
		Vector2.new(0, -185), Vector2.new(0, -265), Vector2.new(0, 185), Vector2.new(0, 345),
		Vector2.new(-360, 48), Vector2.new(90, 265), Vector2.new(-90, 185), Vector2.new(-90, -270),
		Vector2.new(-90, -355), Vector2.new(-355, 185), Vector2.new(355, -355), Vector2.new(185, -265),
	}
	for tIdx, bPos in ipairs(transitionBaffles) do
		local tmpl = if tIdx % 3 == 0 then "EcosystemAncientMonolithMesh"
			elseif tIdx % 2 == 0 then "Evolve_SlotCanyonWallMesh"
			else "CreatorStore_BasaltCliffAMesh"
		local bSize = if tmpl == "EcosystemAncientMonolithMesh"
			then Vector3.new(18, 36, 14)
			else Vector3.new(28, 34, 22)
		placeCheckedBaffle(
			"CorridorSightlineBaffle_" .. tostring(tIdx),
			bPos,
			bSize,
			tIdx * 37,
			tmpl,
			if tmpl == "EcosystemAncientMonolithMesh" then PALETTE.ANCIENT_ALLOY else PALETTE.BASALT_CLIFF,
			Enum.Material.Slate,
			0.40
		)
	end

	-- Staggered biome-specific solid LoS baffle matrix (~80-95 tactical blockers cutting long horizontal rays)
	local bRng = Random.new(68411)
	local gridSerial = 0
	local rowIdx = 0
	for gz = -440, 360, 110 do
		rowIdx += 1
		local rowOffset = (rowIdx % 2) * 55
		for gx = -480 + rowOffset, 480, 110 do
			local bPt = Vector2.new(gx + bRng:NextNumber(-22, 22), gz + bRng:NextNumber(-22, 22))
			if bPt.Magnitude < 125 or math.abs(bPt.X) > 575 or bPt.Y < -485 or bPt.Y > 385 then continue end
			if (bPt - ARENA_A_CENTER).Magnitude < 48 or (bPt - ARENA_B_CENTER).Magnitude < 48
				or (bPt - ARENA_C_CENTER).Magnitude < 48 or (bPt - ARENA_D_CENTER).Magnitude < 48 then
				continue
			end
			if isWaterOrRiver(bPt) > 0.35 then continue end
			local dMain, hw = distToMainSlotCanyon(bPt)
			if dMain < hw + 22 then continue end
			local nearPass = false
			for _, spine in ipairs(DIVIDING_RIDGES) do
				if (bPt - spine.passPos).Magnitude < spine.passHalfW + 10 then
					nearPass = true
					break
				end
			end
			if nearPass then continue end

			gridSerial += 1
			local tmpl: string
			local size: Vector3
			local col: Color3
			local mat: Enum.Material
			if bPt.X < 0 and bPt.Y < 0 then
				tmpl = if gridSerial % 2 == 0 then "Evolve_CanopyArchTreeMesh" else "CreatorStore_BasaltCliffAMesh"
				size = Vector3.new(34, 38, 26)
				col = if gridSerial % 2 == 0 then PALETTE.PETRIFIED_WOOD else PALETTE.BASALT_CLIFF
				mat = Enum.Material.Slate
			elseif bPt.X >= 0 and bPt.Y < 0 then
				tmpl = "Evolve_SlotCanyonWallMesh"
				size = Vector3.new(38, 46, 24)
				col = PALETTE.BASALT
				mat = Enum.Material.Basalt
			elseif bPt.X < 0 and bPt.Y >= 0 then
				tmpl = if gridSerial % 2 == 0 then "Evolve_GeothermalSiloRuinMesh" else "EcosystemAncientMonolithMesh"
				size = Vector3.new(30, 40, 24)
				col = if gridSerial % 2 == 0 then PALETTE.RUST_IRON else PALETTE.CHARCOAL_IRON
				mat = Enum.Material.CorrodedMetal
			else
				tmpl = if gridSerial % 2 == 0 then "CreatorStore_BasaltCliffBMesh" else "Evolve_SlotCanyonWallMesh"
				size = Vector3.new(34, 38, 24)
				col = PALETTE.BASALT_CLIFF
				mat = Enum.Material.Basalt
			end

			placeCheckedBaffle(
				"BiomeBaffleMatrix_" .. tostring(gridSerial),
				bPt,
				size,
				bRng:NextNumber(0, 360),
				tmpl,
				col,
				mat,
				0.40
			)
		end
	end
end

local function buildCentralAnchorRelay(terrainGeom: Folder, nodesFolder: Folder, mapFolder: Folder): Model
	local relayZone = ensureFolder(terrainGeom, "CentralAnchorRelay")

	local existingRelay = mapFolder:FindFirstChild("PowerRelay")
	local relayModel: Model
	if existingRelay ~= nil and existingRelay:IsA("Model") then
		relayModel = existingRelay :: Model
	else
		if existingRelay ~= nil then existingRelay:Destroy() end
		relayModel = Instance.new("Model")
		relayModel.Name = "PowerRelay"
		relayModel.Parent = mapFolder
	end

	local existingCore = relayModel:FindFirstChild("Core")
	clearChildrenExcept(relayModel, "Core")

	local corePart: Part
	if existingCore ~= nil and existingCore:IsA("Part") then
		corePart = existingCore :: Part
	else
		if existingCore ~= nil then existingCore:Destroy() end
		corePart = Instance.new("Part")
		corePart.Name = "Core"
		corePart.Parent = relayModel
	end
	corePart:ClearAllChildren()

	corePart.Size = Vector3.new(11, 20, 11)
	corePart.CFrame = CFrame.new(RELAY_POSITION + Vector3.new(0, 11, 0))
	corePart.Color = PALETTE.BEACON_GOLD
	corePart.Material = Enum.Material.Neon
	corePart.Anchored = true
	corePart.CanCollide = true
	corePart.Transparency = 0.12
	relayModel.PrimaryPart = corePart
	addPointLight(corePart, PALETTE.BEACON_GOLD, 2.4, 125, true)

	local _ = spawnAssetMesh({
		templateName = "EstuaryAnchorPylonMesh",
		name = "AnchorPylonChassis",
		size = Vector3.new(22, 34, 22),
		cframe = CFrame.new(RELAY_POSITION + Vector3.new(0, 16.5, 0)),
		color = PALETTE.CHARCOAL_IRON,
		material = Enum.Material.Metal,
		parent = relayModel,
		canCollide = true,
		castShadow = false,
		keepTexture = false,
	})

	for idx, cOff in ipairs({
		Vector3.new(-8.5, 0, -8.5),
		Vector3.new(8.5, 0, -8.5),
		Vector3.new(-8.5, 0, 8.5),
		Vector3.new(8.5, 0, 8.5),
	}) do
		local bulkhead = makePart({
			name = "AnchorBulkheadLeg_" .. tostring(idx),
			size = Vector3.new(3.4, 28, 3.4),
			cframe = CFrame.new(RELAY_POSITION + cOff + Vector3.new(0, 14, 0)),
			color = PALETTE.CHARCOAL_IRON,
			material = Enum.Material.Metal,
			castShadow = false,
			parent = relayModel,
		})

		local floodHousing = makePart({
			name = "AtmosphericBeaconHousing_" .. tostring(idx),
			size = Vector3.new(3.2, 2.2, 3.2),
			cframe = bulkhead.CFrame * CFrame.new(0, 15.0, 0),
			color = PALETTE.BEACON_GOLD,
			material = Enum.Material.Neon,
			castShadow = false,
			parent = relayModel,
		})
		addSpotLight(floodHousing, Enum.NormalId.Top, PALETTE.BEACON_GOLD, 3.2, 60, 48, false)
		addSpotLight(floodHousing, Enum.NormalId.Bottom, PALETTE.BEACON_GOLD, 1.8, 52, 65, false)

		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1.0, 0)
		a0.Parent = floodHousing
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 390, 0)
		a1.Parent = floodHousing

		local skyBeam = Instance.new("Beam")
		skyBeam.Name = "AnchorSkyFloodBeam_" .. tostring(idx)
		skyBeam.Attachment0 = a0
		skyBeam.Attachment1 = a1
		skyBeam.FaceCamera = true
		skyBeam.LightEmission = 0.78
		skyBeam.LightInfluence = 0
		skyBeam.Color = ColorSequence.new(PALETTE.BEACON_GOLD, PALETTE.SURF_GOLD)
		skyBeam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.28),
			NumberSequenceKeypoint.new(0.25, 0.56),
			NumberSequenceKeypoint.new(0.75, 0.84),
			NumberSequenceKeypoint.new(1, 1),
		})
		skyBeam.Width0 = 3.8
		skyBeam.Width1 = 22.0
		skyBeam.Segments = 8
		skyBeam.Parent = floodHousing
	end

	-- 8 Surrounding Cover Monoliths + 4 A.E.M. Supply Modules on the Caldera Butte (breaks Relay sightlines!)
	for pIdx = 1, 8 do
		local ang = math.rad((pIdx - 1) * 45 + 18)
		local pillarPos = RELAY_POSITION + Vector3.new(math.cos(ang) * 44, 9.5, math.sin(ang) * 44)
		spawnAssetMesh({
			templateName = "EcosystemAncientMonolithMesh",
			name = "RelayCoverPillar_" .. tostring(pIdx),
			size = Vector3.new(9.5, 22, 6.5),
			cframe = CFrame.lookAt(pillarPos, Vector3.new(RELAY_POSITION.X, pillarPos.Y, RELAY_POSITION.Z)),
			color = PALETTE.ANCIENT_ALLOY,
			material = Enum.Material.Slate,
			parent = relayZone,
			canCollide = true,
			castShadow = false,
			keepTexture = false,
		})
	end

	for sIdx, crateSpec in ipairs({
		{ offset = Vector3.new(-26, 2.6, 20), yaw = 24 },
		{ offset = Vector3.new(27, 2.6, -18), yaw = -32 },
		{ offset = Vector3.new(-24, 2.6, -26), yaw = 68 },
		{ offset = Vector3.new(24, 2.6, 26), yaw = -18 },
	}) do
		spawnAssetMesh({
			templateName = "SciFiContainer",
			name = "AEM_SupplyContainer_" .. tostring(sIdx),
			size = Vector3.new(9.4, 5.2, 6.2),
			cframe = CFrame.new(RELAY_POSITION + crateSpec.offset) * CFrame.Angles(0, math.rad(crateSpec.yaw), 0),
			color = PALETTE.ARTERIAL_RED,
			material = Enum.Material.CorrodedMetal,
			parent = relayZone,
			canCollide = true,
			castShadow = false,
			keepTexture = false,
		})
	end

	makeGameplayNode(nodesFolder, "CentralRelayObjective_Core", "CentralRelayObjective", RELAY_POSITION + Vector3.new(0, 10, 0), Vector3.new(26, 24, 26), { MaxRelayHealth = RELAY_MAX_HP, ApproachCount = 4 })

	relayModel:SetAttribute("Health", RELAY_MAX_HP)
	relayModel:SetAttribute("MaxHealth", RELAY_MAX_HP)
	relayModel:SetAttribute("MaxRelayHealth", RELAY_MAX_HP)
	relayModel:SetAttribute("RelayHealth", RELAY_MAX_HP)
	return relayModel
end

local function isClearForTree(p: Vector2, placed: { Vector2 }): boolean
	if p.Magnitude < 146 then return false end
	if math.abs(p.X) > 580 or p.Y > 475 or p.Y < -490 then return false end
	if (p - ARENA_A_CENTER).Magnitude < 46 then return false end
	if (p - ARENA_B_CENTER).Magnitude < 42 then return false end
	if (p - ARENA_C_CENTER).Magnitude < 46 then return false end
	if (p - ARENA_D_CENTER).Magnitude < 46 then return false end
	if isWaterOrRiver(p) > 0.35 then return false end
	-- Stage 3 clearance guard: NEVER drop a collidable tree inside NE main canyons or ridge pass mouths!
	local dMain, hw = distToMainSlotCanyon(p)
	if dMain < hw + 14 then return false end
	for _, spine in ipairs(DIVIDING_RIDGES) do
		if (p - spine.passPos).Magnitude < spine.passHalfW + 6 then return false end
	end
	for _, other in ipairs(placed) do
		if (p - other).Magnitude < 15.5 then return false end
	end
	return true
end

-- Builds Dense Petrified Canopy (~215 Tall Trees) + High Stage-1 Concealment Vegetation (~660 Non-Collidable Flora)
-- Performance budget: 100% of Flora_* & underbrush have CanCollide = false, CastShadow = false!
local function buildEcosystemVegetation(
	vegFolder: Folder,
	climbFolder: Folder
): { Vector3 }
	local perchPositions: { Vector3 } = {}
	local placedTrees: { Vector2 } = {}

	local treeCandidates: { Vector2 } = {}
	local tRng = Random.new(67960)
	-- NW Dense Petrified Canopy cluster (130 candidates)
	for _ = 1, 130 do
		table.insert(treeCandidates, Vector2.new(tRng:NextNumber(-565, -110), tRng:NextNumber(-470, 20)))
	end
	-- SE Leviathan & Tar Marsh perimeter & island trees (75 candidates)
	for _ = 1, 75 do
		table.insert(treeCandidates, Vector2.new(tRng:NextNumber(110, 565), tRng:NextNumber(65, 405)))
	end
	-- SW Geothermal perimeter & West creek corridors (65 candidates)
	for _ = 1, 65 do
		table.insert(treeCandidates, Vector2.new(tRng:NextNumber(-565, -115), tRng:NextNumber(75, 395)))
	end
	-- Center caldera outer belt + NE plateau rims (65 candidates)
	for _ = 1, 65 do
		table.insert(treeCandidates, Vector2.new(tRng:NextNumber(135, 555), tRng:NextNumber(-470, -65)))
	end

	local treeIdx = 0
	for _, coord in ipairs(treeCandidates) do
		if treeIdx >= 215 then break end
		if not isClearForTree(coord, placedTrees) then continue end
		table.insert(placedTrees, coord)
		treeIdx += 1

		local groundY, surfMat = sampleEstuarySurface(coord.X, coord.Y)
		local isArchCanopy = (coord.X < -90 and coord.Y < 45 and treeIdx % 3 ~= 0) or (treeIdx % 2 == 0)
		local hasPerch = (treeIdx % 6 == 0) and (#perchPositions < 18)
		local treeH = if isArchCanopy then (36 + (treeIdx % 4) * 3.5) else (32 + (treeIdx % 4) * 3)
		local treeW = if isArchCanopy then (38 + (treeIdx % 3) * 4.5) else (26 + (treeIdx % 3) * 3.5)
		local toCenter = (Vector2.new(0, 0) - coord)
		local branchDir2D = if toCenter.Magnitude > 1 then toCenter.Unit else Vector2.new(1, 0)
		local yaw = if hasPerch then math.atan2(-branchDir2D.X, -branchDir2D.Y) else math.rad((treeIdx * 53) % 360)

		spawnAssetMesh({
			templateName = if isArchCanopy then "Evolve_CanopyArchTreeMesh" else "EstuaryPetrifiedTreeMesh",
			name = "PetrifiedTree_" .. tostring(treeIdx),
			size = Vector3.new(treeW, treeH, treeW * 0.94),
			cframe = CFrame.new(coord.X, groundY + treeH * 0.44, coord.Y)
				* CFrame.Angles(math.rad((treeIdx % 3 - 1) * 2.5), yaw, 0),
			color = if surfMat == Enum.Material.Basalt then PALETTE.BONE_WEATHERED else PALETTE.PETRIFIED_WOOD,
			material = Enum.Material.Slate,
			parent = vegFolder,
			canCollide = true,
			castShadow = false,
			keepTexture = false,
		})

		if hasPerch then
			local perchHeight = treeH * 0.78
			local branchWorldDir = Vector3.new(branchDir2D.X, 0.05, branchDir2D.Y).Unit
			local branchOrigin = Vector3.new(coord.X, groundY + perchHeight, coord.Y)
			local branchMid = branchOrigin + branchWorldDir * 8.5

			makePart({
				name = "TreeAmbushPerch_" .. tostring(treeIdx),
				size = Vector3.new(7.5, 1.8, 17.5),
				cframe = CFrame.lookAt(branchMid, branchMid + branchWorldDir),
				color = PALETTE.PETRIFIED_WOOD,
				material = Enum.Material.Slate,
				transparency = 1,
				canCollide = true,
				castShadow = false,
				parent = vegFolder,
			})
			makeClimbableWall(
				climbFolder,
				"TreeClimbTrunk_" .. tostring(treeIdx),
				Vector3.new(coord.X, groundY, coord.Y) - branchWorldDir * 3.5,
				branchOrigin,
				5.5,
				false
			).Transparency = 1
			table.insert(perchPositions, branchMid + Vector3.new(0, 1.4, 0))
		end
	end

	-- 1) 28 Dense Stage-1 Concealment Thickets (10-16 studs tall alien flora breaking sniper & aerial LoS!)
	local heavyFloraZones: { { center: Vector2, radius: number, count: number } } = {
		{ center = Vector2.new(-355, -245), radius = 62, count = 24 }, -- NW Sunken Forest Stalking Belt
		{ center = Vector2.new(-245, -155), radius = 56, count = 22 }, -- NW Canopy Inner Screen
		{ center = Vector2.new(-465, -165), radius = 58, count = 22 }, -- NW Western Creek Cover
		{ center = Vector2.new(-345, -365), radius = 56, count = 22 }, -- NW North Ridge Thicket
		{ center = Vector2.new(-225, -335), radius = 54, count = 20 }, -- NW Waterfall Approach Thicket
		{ center = Vector2.new(-485, -335), radius = 50, count = 20 }, -- NW Root Hollow Stealth Zone
		{ center = Vector2.new(-165, -75), radius = 52, count = 20 },  -- Center-NW Corridor Curtain
		{ center = Vector2.new(-365, -55), radius = 50, count = 18 },  -- West Ridge Pass Cover
		{ center = Vector2.new(235, 225), radius = 58, count = 24 },   -- SE Marsh Reed Wall
		{ center = Vector2.new(385, 285), radius = 58, count = 24 },   -- SE Leviathan Marsh Thicket
		{ center = Vector2.new(465, 135), radius = 54, count = 20 },   -- SE East Tarn Concealment
		{ center = Vector2.new(175, 115), radius = 52, count = 20 },   -- Center-SE Approach Brush
		{ center = Vector2.new(335, 125), radius = 52, count = 20 },   -- SE Mid-Marsh Island Cover
		{ center = Vector2.new(285, 345), radius = 52, count = 18 },   -- SE Outer Coastal Marsh
		{ center = Vector2.new(135, 295), radius = 48, count = 16 },   -- SE Inner Slough Reed Bank
		{ center = Vector2.new(-285, 165), radius = 50, count = 18 },  -- SW Geothermal Canal Brush
		{ center = Vector2.new(-445, 215), radius = 52, count = 18 },  -- SW Outer Ruins Fern Screen
		{ center = Vector2.new(-175, 285), radius = 50, count = 18 },  -- SW Cool-Water Conduit Brush
		{ center = Vector2.new(-115, 155), radius = 48, count = 16 },  -- Center-SW Gate Screen
		{ center = Vector2.new(295, -205), radius = 44, count = 16 },  -- NE Confluence Oasis Screen
		{ center = Vector2.new(435, -295), radius = 46, count = 16 },  -- NE Upper Shelf Thicket
		{ center = Vector2.new(155, -185), radius = 46, count = 14 },  -- NE West Mesa Skirt
		{ center = Vector2.new(-125, 455), radius = 48, count = 16 },  -- South Bluff Left Cover
		{ center = Vector2.new(125, 455), radius = 48, count = 16 },   -- South Bluff Right Cover
		{ center = Vector2.new(-85, -35), radius = 48, count = 16 },   -- Central Moat NW Fog Screen
		{ center = Vector2.new(85, 35), radius = 48, count = 16 },     -- Central Moat SE Fog Screen
	}

	local floraSerial = 0
	local function placeFoliageMesh(
		templateName: string,
		pos2D: Vector2,
		size: Vector3,
		color: Color3,
		tiltDeg: number,
		yawDeg: number,
		isConcealment: boolean
	)
		if floraSerial >= 660 then return end
		local rawY, surfMat = sampleEstuarySurface(pos2D.X, pos2D.Y)
		if rawY < -2.2 or surfMat == Enum.Material.Water then return end
		local dMain, hw = distToMainSlotCanyon(pos2D)
		if dMain < hw - 2 then return end

		floraSerial += 1
		local m = spawnAssetMesh({
			templateName = templateName,
			name = "Flora_" .. tostring(floraSerial),
			size = size,
			cframe = CFrame.new(pos2D.X, rawY + size.Y * 0.42 - 0.35, pos2D.Y)
				* CFrame.Angles(math.rad(tiltDeg), math.rad(yawDeg), 0),
			color = color,
			material = Enum.Material.Grass,
			parent = vegFolder,
			canCollide = false,
			castShadow = false,
			keepTexture = false,
		})
		if m ~= nil then
			m.CanQuery = false
			m.CanTouch = false
			if isConcealment then
				CollectionService:AddTag(m, "ConcealmentFlora")
			end
		end
	end

	local rng = Random.new(67901)
	for _, hz in ipairs(heavyFloraZones) do
		for i = 1, hz.count do
			local ang = i * 2.39996 + rng:NextNumber(-0.18, 0.18)
			if math.sin(ang * 2) > 0.84 then continue end
			local rad = math.sqrt(i / hz.count) * hz.radius
			local pt = hz.center + Vector2.new(math.cos(ang) * rad, math.sin(ang) * rad)
			local tmpl = if i % 3 == 0
				then "EcosystemAlienFloraMesh"
				elseif i % 3 == 1 then "EcosystemFernFrondMesh"
				else "EcosystemTallGrassMesh"
			local h = if tmpl == "EcosystemAlienFloraMesh"
				then rng:NextNumber(11.5, 16.0)
				elseif tmpl == "EcosystemFernFrondMesh" then rng:NextNumber(9.5, 13.0)
				else rng:NextNumber(8.5, 11.8)
			local w = h * rng:NextNumber(1.15, 1.55)
			local col = if i % 4 == 0 then PALETTE.FLORA_OCHRE elseif i % 2 == 0 then PALETTE.FLORA_DEEP else PALETTE.FLORA_OLIVE
			placeFoliageMesh(tmpl, pt, Vector3.new(w, h, w), col, rng:NextNumber(-7, 7), rng:NextNumber(0, 360), true)
		end
	end

	-- 2) High Riverbank Reed Curtains & Marsh Stalks (screens Stage 1 Monster feeding in shallow creeks)
	for segIdx, seg in ipairs(RIVER_SEGMENTS) do
		for step = 1, 9 do
			local t = step / 10
			local mid = seg.a:Lerp(seg.b, t)
			local tangent = (seg.b - seg.a).Unit
			local normal = Vector2.new(-tangent.Y, tangent.X)
			local side = if (step + segIdx) % 2 == 0 then 1 else -1
			local bankPt = mid + normal * (side * (seg.halfWidth + rng:NextNumber(4.5, 14.0)))
			local tmpl = if step % 3 == 0 then "EcosystemTallGrassMesh" elseif step % 2 == 0 then "EcosystemAlienFloraMesh" else "EcosystemRaisedGrassMesh"
			local h = rng:NextNumber(7.5, 11.5)
			local col = if step % 3 == 0 then PALETTE.FLORA_OCHRE else PALETTE.FLORA_OLIVE
			local trampledTilt = if step % 6 == 0 then 48 else rng:NextNumber(-6, 6)
			placeFoliageMesh(tmpl, bankPt, Vector3.new(h * 1.35, h, h * 1.35), col, trampledTilt, rng:NextNumber(0, 360), true)
		end
	end

	-- 3) Mid-Height Concealment Shrubs distributed evenly across outer corridors & ridgelines
	for gIdx = 1, 140 do
		local ang = gIdx * 2.39996
		local rad = 165 + ((gIdx * 37) % 415)
		local pt = Vector2.new(math.cos(ang) * rad, math.sin(ang) * rad)
		if (pt - ARENA_A_CENTER).Magnitude > 50 and (pt - ARENA_B_CENTER).Magnitude > 48
			and (pt - ARENA_C_CENTER).Magnitude > 50 and (pt - ARENA_D_CENTER).Magnitude > 50 then
			local tmpl = if gIdx % 3 == 0 then "EcosystemAlienFloraMesh" else "EcosystemRaisedGrassMesh"
			local h = rng:NextNumber(6.5, 10.2)
			placeFoliageMesh(tmpl, pt, Vector3.new(h * 1.35, h, h * 1.35), if gIdx % 4 == 0 then PALETTE.FLORA_OCHRE else PALETTE.FLORA_DEEP, rng:NextNumber(-5, 5), rng:NextNumber(0, 360), true)
		end
	end

	return perchPositions
end

local function buildBrineGullSoundTraps(terrainGeom: Folder, perchPositions: { Vector3 }): ()
	local flockFolder = ensureFolder(terrainGeom, "BrineGullFlocks")
	-- Roosts placed at biome choke transitions & coastal salt-flats (never cluttering far-North Stage 1 safe starts!)
	local shoreAndRiverRoosts: { Vector2 } = {
		Vector2.new(-225, 425), Vector2.new(0, 420), Vector2.new(225, 425),
		Vector2.new(-320, 50), Vector2.new(335, -35), Vector2.new(0, 265),
		Vector2.new(-155, -135), Vector2.new(155, -140),
		Vector2.new(-185, 195), Vector2.new(195, 195),
		Vector2.new(-420, 145), Vector2.new(435, 185),
	}
	for idx, coord in ipairs(shoreAndRiverRoosts) do
		local rawY = sampleEstuarySurface(coord.X, coord.Y)
		local y = math.max(0.8, rawY) + 1.2
		local anchor = makePart({
			name = "BrineGullRoost_" .. tostring(idx),
			size = Vector3.new(3, 0.5, 3),
			cframe = CFrame.new(coord.X, y, coord.Y),
			color = PALETTE.BASALT,
			material = Enum.Material.Basalt,
			transparency = 1,
			canCollide = false,
			castShadow = false,
			parent = flockFolder,
		})
		anchor.CanQuery = false
	end
	for pIdx = 1, math.min(4, #perchPositions) do
		local anchor = makePart({
			name = "CanopyGullRoost_" .. tostring(pIdx),
			size = Vector3.new(3, 0.5, 3),
			cframe = CFrame.new(perchPositions[pIdx]),
			color = PALETTE.BASALT,
			material = Enum.Material.Basalt,
			transparency = 1,
			canCollide = false,
			castShadow = false,
			parent = flockFolder,
		})
		anchor.CanQuery = false
	end
end

local function populateWildlifeHotspotsAndPreySpawns(
	preySpawnsFolder: Folder,
	nodesFolder: Folder
): (number, number)
	clearChildrenExcept(preySpawnsFolder, nil)

	-- 34 Tier-1 Low-Threat Hotspots arranged in 3 protected Stage-1 Feeding Loops (NONE sitting directly in front of South Hunter Drop!)
	local tier1Coords: { Vector2 } = {
		-- Loop 1: NW Petrified Canopy & Western Creek (12 spawns -> quick early Stage 2 feed path)
		Vector2.new(-445, -395), Vector2.new(-355, -390), Vector2.new(-245, -355), Vector2.new(-195, -425),
		Vector2.new(-465, -245), Vector2.new(-385, -245), Vector2.new(-285, -185), Vector2.new(-455, -95),
		Vector2.new(-355, -85), Vector2.new(-215, -135), Vector2.new(-485, -15), Vector2.new(-325, -20),
		-- Loop 2: NE Obsidian Slot Canyons & Northern Confluence (11 spawns inside 42-46w canyon corridors)
		Vector2.new(385, -475), Vector2.new(275, -415), Vector2.new(175, -365), Vector2.new(225, -285),
		Vector2.new(345, -310), Vector2.new(475, -285), Vector2.new(465, -155), Vector2.new(335, -185),
		Vector2.new(195, -165), Vector2.new(395, -85), Vector2.new(165, -245),
		-- Loop 3: SE Tar Marshes & SW Geothermal Coolant Channels (11 spawns)
		Vector2.new(455, 195), Vector2.new(365, 225), Vector2.new(255, 245), Vector2.new(485, 85),
		Vector2.new(195, 145), Vector2.new(395, 345),
		Vector2.new(-445, 135), Vector2.new(-365, 165), Vector2.new(-235, 175), Vector2.new(-395, 295), Vector2.new(-215, 285),
	}

	-- 8 Tier-2 Alpha Wildlife Hotspots (RedGoliath: 100 Meat + 250 Armor + 10% SpeedBuff) at strategic chokes
	local tier2Coords: { Vector2 } = {
		Vector2.new(GROTTO_WEST.X + 18, GROTTO_WEST.Y + 42),
		Vector2.new(GROTTO_NORTH.X, GROTTO_NORTH.Y + 45),
		Vector2.new(GROTTO_EAST.X - 18, GROTTO_EAST.Y + 38),
		Vector2.new(-320, 48),   -- West Dividing Spine Pass guardian
		Vector2.new(335, -38),   -- East Dividing Spine Pass guardian
		Vector2.new(-155, -25),  -- Center-West Moat crossing
		Vector2.new(155, 25),    -- Center-East Moat crossing
		Vector2.new(445, 265),   -- SE Leviathan Cavern approach
	}

	local idx = 0
	for t1Idx, coord in ipairs(tier1Coords) do
		idx += 1
		local rawY = sampleEstuarySurface(coord.X, coord.Y)
		local gy = math.max(-2.4, rawY)
		local worldPos = Vector3.new(coord.X, gy + 0.3, coord.Y)
		local sp = makeSpawnPart(preySpawnsFolder, string.format("Spawn%02d", idx), worldPos, nil)
		sp:SetAttribute("PreyTier", 1)
		makeGameplayNode(nodesFolder, string.format("WildlifeHotspot_Tier1_%02d", t1Idx), "WildlifeHotspot_Tier1", worldPos + Vector3.new(0, 2.5, 0), Vector3.new(12, 6, 12), { PreyTier = 1 })
	end
	for t2Idx, coord in ipairs(tier2Coords) do
		idx += 1
		local rawY = sampleEstuarySurface(coord.X, coord.Y)
		local gy = math.max(-2.6, rawY)
		local worldPos = Vector3.new(coord.X, gy + 0.4, coord.Y)
		local sp = makeSpawnPart(preySpawnsFolder, string.format("Spawn%02d", idx), worldPos, nil)
		sp:SetAttribute("PreyTier", 2)
		makeGameplayNode(nodesFolder, string.format("WildlifeHotspot_Alpha_%02d", t2Idx), "WildlifeHotspot_Alpha", worldPos + Vector3.new(0, 4, 0), Vector3.new(18, 10, 18), { PreyTier = 2, Species = "RedGoliath" })
	end

	return #tier1Coords, #tier2Coords
end

-- ============================================================================
-- TELEPORTE DE SEGURANÇA PARA JOGADORES QUE ENTRARAM ANTES DO LOBBY
-- ============================================================================
local function relocateLobbyPlayers(lobbySpawn: SpawnLocation): ()
	local spawnCFrame = lobbySpawn.CFrame + Vector3.new(0, 4, 0)
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char ~= nil then
			local role = char:GetAttribute("Role")
			if role == nil or role == "Lobby" then
				local pos = char:GetPivot().Position
				if pos.Y < 500 then
					char:PivotTo(spawnCFrame)
				end
			end
		end
	end
end

-- ============================================================================
-- EXECUÇÃO PRINCIPAL DO WORLD BUILDER
-- ============================================================================
local function buildWorld(): ()
	Workspace:SetAttribute("WorldReady", false)

	configureWorldLighting()
	cleanupDefaultWorkspaceTemplate()

	local existingLobby = Workspace:FindFirstChild("Lobby")
	local existingLobbySpawn = if existingLobby then existingLobby:FindFirstChild("LobbySpawn") else nil
	local existingEco = Workspace:FindFirstChild("HuntingMap_Ecosystem")
	local lobbySpawn: SpawnLocation

	if Workspace:GetAttribute("EstuaryMapVersion") == ECOSYSTEM_VERSION
		and existingLobbySpawn ~= nil
		and existingLobbySpawn:IsA("SpawnLocation")
		and existingEco ~= nil
		and existingEco:FindFirstChild("TerrainAndGeometry") ~= nil
		and existingEco:FindFirstChild("ClimbableSurfaces") ~= nil
		and existingEco:FindFirstChild("Vegetation") ~= nil
		and existingEco:FindFirstChild("GameplayNodes") ~= nil
	then
		lobbySpawn = existingLobbySpawn
		local mapFolder = Workspace:FindFirstChild("Map")
		local relay = if mapFolder then mapFolder:FindFirstChild("PowerRelay") else nil
		if relay then
			relay:SetAttribute("MaxRelayHealth", RELAY_MAX_HP)
			relay:SetAttribute("RelayHealth", RELAY_MAX_HP)
		end
	else
		-- Preserve existing refined Lobby + LobbyExterior_OblivionSpire when upgrading HuntingMap_Ecosystem!
		if existingLobbySpawn ~= nil and existingLobbySpawn:IsA("SpawnLocation") and Workspace:FindFirstChild("LobbyExterior_OblivionSpire") ~= nil then
			lobbySpawn = existingLobbySpawn
		else
			lobbySpawn = buildLobby()
		end

		local mapFolder = ensureFolder(Workspace, "Map")
		local legacyGeometry = ensureFolder(mapFolder, "Geometry")
		legacyGeometry:ClearAllChildren()

		local monsterSpawnsFolder = ensureFolder(mapFolder, "MonsterSpawns")
		local hunterSpawnsFolder = ensureFolder(mapFolder, "HunterSpawns")
		local preySpawnsFolder = ensureFolder(mapFolder, "PreySpawns")
		ensureFolder(Workspace, "ActivePrey")
		ensureFolder(Workspace, "Footprints")

		local ecoRoot = ensureFolder(Workspace, "HuntingMap_Ecosystem")
		local terrainGeom = ensureFolder(ecoRoot, "TerrainAndGeometry")
		local climbFolder = ensureFolder(ecoRoot, "ClimbableSurfaces")
		local vegFolder = ensureFolder(ecoRoot, "Vegetation")
		local nodesFolder = ensureFolder(ecoRoot, "GameplayNodes")
		terrainGeom:ClearAllChildren()
		climbFolder:ClearAllChildren()
		vegFolder:ClearAllChildren()
		nodesFolder:ClearAllChildren()

		buildEstuaryVoxelTerrain()
		buildPerimeterAndShoreline(terrainGeom, nodesFolder, hunterSpawnsFolder)
		buildRiversOilAndWaterfall(terrainGeom)
		buildElevationPlateausAndClimbables(terrainGeom, climbFolder)
		buildGrottosEvolutionHollowsAndNests(terrainGeom, nodesFolder, monsterSpawnsFolder)
		buildBiomeLandmarksAndLoSBaffles(terrainGeom)
		buildCentralAnchorRelay(terrainGeom, nodesFolder, mapFolder)
		local perches = buildEcosystemVegetation(vegFolder, climbFolder)
		buildBrineGullSoundTraps(terrainGeom, perches)
		local tier1Count, tier2Count = populateWildlifeHotspotsAndPreySpawns(preySpawnsFolder, nodesFolder)

		Workspace:SetAttribute("EstuaryMapVersion", ECOSYSTEM_VERSION)
		print(
			string.format(
				"%s HuntingMap_Ecosystem (%dx%d v%d) built | HunterSpawns=%d, MonsterSpawns=%d, Wildlife(T1=%d, Alpha=%d), Climbable=%d, Veg=%d, Nodes=%d",
				LOG_PREFIX,
				ARENA_SIZE,
				ARENA_SIZE,
				ECOSYSTEM_VERSION,
				#hunterSpawnsFolder:GetChildren(),
				#monsterSpawnsFolder:GetChildren(),
				tier1Count,
				tier2Count,
				#climbFolder:GetChildren(),
				#vegFolder:GetChildren(),
				#nodesFolder:GetChildren()
			)
		)
	end

	relocateLobbyPlayers(lobbySpawn)
	Workspace:SetAttribute("WorldReady", true)
end

buildWorld()

