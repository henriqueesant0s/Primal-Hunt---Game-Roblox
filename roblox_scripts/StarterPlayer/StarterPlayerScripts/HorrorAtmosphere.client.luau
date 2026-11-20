--!strict
--[[
	PROJECT ABYSS | HorrorAtmosphere.client.lua
	Localização: StarterPlayer/StarterPlayerScripts/HorrorAtmosphere.client.lua

	Responsabilidade:
	- Configurar e gerenciar exclusivamente instâncias próprias de Lighting (sem destruir efeitos existentes).
	- Monitorar distância em relação ao personagem com Role == "Monster" e Stage do monstro.
	- Controlar áudio 2D (Heartbeat) e áudio espacial 3D (TenseBreathing) sem recriação contínua de instâncias.
	- Renderizar vinheta programática não-bloqueante em ScreenGui exclusivo.
	- Aplicar tremor sutil e aditivo em Humanoid.CameraOffset, restaurando o estado anterior ao desativar.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local LOG_PREFIX = "[PROJECT ABYSS][HorrorAtmosphere]"

local AUDIO_IDS = {
	Heartbeat = "rbxassetid://6202853067",
	TenseBreathing = "rbxassetid://9119386548",
	AmbientWind = "rbxassetid://9114340693",
	DistantGroan = "rbxassetid://9114787480",
	DistantRoar = "rbxassetid://9113980319",
	CaveDrip = "rbxassetid://9120550180",
}

local CONFIG = {
	ProximityCheckInterval = 0.1,
	TensionSmoothSpeed = 5.5,
	OuterRangeStuds = 120,
	MidRangeStuds = 80,
	InnerRangeStuds = 50,
	AtmosphereName = "ProjectAbyss_Atmosphere",
	ColorCorrectionName = "ProjectAbyss_ColorCorrection",
	BloomName = "ProjectAbyss_Bloom",
	SoundGroupName = "ProjectAbyss_HorrorAudio",
	GuiName = "ProjectAbyss_HorrorVignette",
	SpatialAnchorName = "ProjectAbyss_MonsterAudioAnchor",
	BaseAtmosphereDensity = 0.31,
	MaxAtmosphereDensity = 0.38,
	BaseAtmosphereHaze = 2.1,
	MaxAtmosphereHaze = 3.4,
	BaseAtmosphereColor = Color3.fromRGB(112, 124, 118),
	TensionAtmosphereColor = Color3.fromRGB(108, 68, 62),
	BaseSaturation = -0.06,
	MaxDesaturation = -0.35,
	BaseContrast = 0.18,
	MaxContrast = 0.16,
	TensionTintColor = Color3.fromRGB(228, 185, 185),
	BloomIntensityBase = 0.08,
	BloomIntensityMax = 0.28,
	BloomSize = 18,
	BloomThreshold = 1.45,
	MaxExposureDelta = -0.17,
	MaxHeartbeatVolume = 0.85,
	MaxBreathingVolume = 0.65,
	BreathingMinRollOff = 10,
	BreathingMaxRollOff = 120,
	MaxCameraShakeAmplitude = 0.14,
	Stage3ShakeMultiplier = 1.35,
}

local function isValidAssetId(assetId: string): boolean
	if assetId == "" then
		return false
	end
	local numericPart = string.match(assetId, "^rbxassetid://(%d+)$")
	if numericPart == nil then
		return false
	end
	local idNumber = tonumber(numericPart)
	return idNumber ~= nil and idNumber > 0
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function getOrCreateManagedAtmosphere(): Atmosphere
	local existing = Lighting:FindFirstChild(CONFIG.AtmosphereName)
	if existing ~= nil and existing:IsA("Atmosphere") then
		return existing :: Atmosphere
	end

	-- Adota o Atmosphere existente na cena (sem destruí-lo) para que a densidade dinâmica renderize sem concorrência
	local sceneAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if sceneAtmosphere ~= nil then
		return sceneAtmosphere
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = CONFIG.AtmosphereName
	atmosphere.Density = CONFIG.BaseAtmosphereDensity
	atmosphere.Offset = 0.12
	atmosphere.Color = CONFIG.BaseAtmosphereColor
	atmosphere.Decay = Color3.fromRGB(48, 62, 68)
	atmosphere.Glare = 0.1
	atmosphere.Haze = CONFIG.BaseAtmosphereHaze
	atmosphere.Parent = Lighting
	return atmosphere
end

local function getOrCreateManagedColorCorrection(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild(CONFIG.ColorCorrectionName)
	if existing ~= nil and existing:IsA("ColorCorrectionEffect") then
		return existing :: ColorCorrectionEffect
	end

	-- Adota o ColorCorrectionEffect existente na cena para evitar empilhamento duplo
	local sceneCC = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if sceneCC ~= nil then
		return sceneCC
	end

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = CONFIG.ColorCorrectionName
	cc.Brightness = 0
	cc.Contrast = CONFIG.BaseContrast
	cc.Saturation = CONFIG.BaseSaturation
	cc.TintColor = Color3.new(1, 1, 1)
	cc.Enabled = true
	cc.Parent = Lighting
	return cc
end

local function getOrCreateManagedBloom(): BloomEffect
	local existing = Lighting:FindFirstChild(CONFIG.BloomName)
	if existing ~= nil and existing:IsA("BloomEffect") then
		return existing :: BloomEffect
	end

	-- Adota o Bloom existente na cena para evitar empilhamento e estouro de brilho Neon
	local sceneBloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if sceneBloom ~= nil then
		sceneBloom.Intensity = CONFIG.BloomIntensityBase
		sceneBloom.Size = CONFIG.BloomSize
		sceneBloom.Threshold = CONFIG.BloomThreshold
		sceneBloom.Enabled = true
		return sceneBloom
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Name = CONFIG.BloomName
	bloom.Intensity = CONFIG.BloomIntensityBase
	bloom.Size = CONFIG.BloomSize
	bloom.Threshold = CONFIG.BloomThreshold
	bloom.Enabled = true
	bloom.Parent = Lighting
	return bloom
end

local function getOrCreateManagedDOF(): DepthOfFieldEffect
	local existing = Lighting:FindFirstChild("ProjectAbyss_HorrorDOF")
	if existing and existing:IsA("DepthOfFieldEffect") then return existing end
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "ProjectAbyss_HorrorDOF"
	dof.FarIntensity = 0.16
	dof.FocusDistance = 42
	dof.InFocusRadius = 65
	dof.NearIntensity = 0
	dof.Enabled = false
	dof.Parent = Lighting
	return dof
end

local managedAtmosphere = getOrCreateManagedAtmosphere()
local managedColorCorrection = getOrCreateManagedColorCorrection()
local managedBloom = getOrCreateManagedBloom()
local managedDOF = getOrCreateManagedDOF()

local baseExposureCompensation: number = Lighting.ExposureCompensation
local baseAmbient: Color3 = Lighting.Ambient
local baseOutdoorAmbient: Color3 = Lighting.OutdoorAmbient
local baseAtmoDensity: number = managedAtmosphere.Density
local baseAtmoHaze: number = managedAtmosphere.Haze
local baseAtmoColor: Color3 = managedAtmosphere.Color
local baseColorBrightness: number = managedColorCorrection.Brightness
local baseColorContrast: number = managedColorCorrection.Contrast
local baseColorSaturation: number = managedColorCorrection.Saturation
local baseColorTint: Color3 = managedColorCorrection.TintColor
local baseBloomIntensity: number = managedBloom.Intensity
local targetDarkAmbient: Color3 = Color3.fromRGB(22, 28, 34)
local targetDarkOutdoor: Color3 = Color3.fromRGB(36, 44, 52)

local currentTension: number = 0
local targetTension: number = 0
local currentInnerDanger: number = 0
local targetInnerDanger: number = 0
local currentMidDanger: number = 0
local targetMidDanger: number = 0
local currentDistance: number = math.huge
local lastAppliedLightingTension: number = -1
local lastAppliedMidDanger: number = -1

local currentLightingZone: string = ""
local savedFootstepVolume: {[Sound]: number} = setmetatable({}, { __mode = "k" }) :: any
local applyAudioEffects: ((number, number) -> ())? = nil

local function resolveTargetLightingZone(role: any, root: BasePart?): string
	if role == "Lobby" then
		return "Lobby"
	end
	if role ~= nil and role ~= "Lobby" then
		return "Estuary"
	end
	if root ~= nil then
		return if root.Position.Y > 400 then "Lobby" else "Estuary"
	end
	if currentLightingZone ~= "" then
		return currentLightingZone
	end
	return "Lobby"
end

local function applyZoneLightingProfile(zone: string): ()
	if currentLightingZone == zone then return end
	currentLightingZone = zone

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays == nil then
		sunRays = Instance.new("SunRaysEffect")
		sunRays.Parent = Lighting
	end

	local sky = Lighting:FindFirstChildOfClass("Sky")

	if zone == "Lobby" then
		Lighting.GeographicLatitude = -54.66
		Lighting.ClockTime = 15.576
		Lighting.Brightness = 1.62
		Lighting.ExposureCompensation = 0.06
		Lighting.Ambient = Color3.fromRGB(53, 58, 62)
		Lighting.OutdoorAmbient = Color3.fromRGB(94, 89, 75)
		Lighting.ColorShift_Top = Color3.fromRGB(246, 218, 148)
		Lighting.ColorShift_Bottom = Color3.fromRGB(24, 24, 18)
		Lighting.ShadowSoftness = 0.22
		if sky ~= nil then
			sky.CelestialBodiesShown = false
			sky.SunAngularSize = 10
		end
		managedAtmosphere.Density = 0.24
		managedAtmosphere.Offset = 0.12
		managedAtmosphere.Haze = 3.2
		managedAtmosphere.Color = Color3.fromRGB(168, 140, 62)
		managedAtmosphere.Decay = Color3.fromRGB(68, 56, 26)
		managedAtmosphere.Glare = 0.48
		sunRays.Enabled = false
		sunRays.Intensity = 0
		sunRays.Spread = 0.78
		managedBloom.Enabled = true
		managedBloom.Intensity = 0.17
		managedBloom.Size = 48
		managedBloom.Threshold = 1.42
		managedColorCorrection.Brightness = 0.02
		managedColorCorrection.Contrast = 0.08
		managedColorCorrection.Saturation = -0.18
		managedColorCorrection.TintColor = Color3.fromRGB(250, 241, 220)
		managedDOF.Enabled = false
		currentDistance = math.huge
		currentTension = 0
		targetTension = 0
		currentMidDanger = 0
		targetMidDanger = 0
		currentInnerDanger = 0
		targetInnerDanger = 0
		if applyAudioEffects ~= nil then
			applyAudioEffects(0, 0)
		end
	else
		-- High-Visibility Atmospheric Horror-Hunt Dusk (clear terrain & lush forest readability + suspenseful mist)
		if sky ~= nil then
			sky.CelestialBodiesShown = false
			sky.SunAngularSize = 10
		end
		Lighting.GeographicLatitude = 42
		Lighting.ClockTime = 16.6
		Lighting.Brightness = 2.25
		Lighting.ExposureCompensation = 0.22
		Lighting.Ambient = Color3.fromRGB(58, 66, 72)
		Lighting.OutdoorAmbient = Color3.fromRGB(88, 98, 92)
		Lighting.ColorShift_Top = Color3.fromRGB(245, 212, 165)
		Lighting.ColorShift_Bottom = Color3.fromRGB(36, 42, 46)
		Lighting.ShadowSoftness = 0.28
		managedAtmosphere.Density = 0.31
		managedAtmosphere.Offset = 0.12
		managedAtmosphere.Haze = 2.1
		managedAtmosphere.Color = Color3.fromRGB(112, 124, 118)
		managedAtmosphere.Decay = Color3.fromRGB(196, 142, 96)
		managedAtmosphere.Glare = 0.34
		sunRays.Enabled = true
		sunRays.Intensity = 0.16
		sunRays.Spread = 0.78
		managedBloom.Enabled = true
		managedBloom.Intensity = 0.14
		managedBloom.Size = 22
		managedBloom.Threshold = 1.45
		managedColorCorrection.Brightness = 0.035
		managedColorCorrection.Contrast = 0.07
		managedColorCorrection.Saturation = -0.06
		managedColorCorrection.TintColor = Color3.fromRGB(246, 242, 234)
		managedDOF.Enabled = true
		managedDOF.FarIntensity = 0.06
		managedDOF.FocusDistance = 42
		managedDOF.InFocusRadius = 160
	end

	baseExposureCompensation = Lighting.ExposureCompensation
	baseAmbient = Lighting.Ambient
	baseOutdoorAmbient = Lighting.OutdoorAmbient
	baseAtmoDensity = managedAtmosphere.Density
	baseAtmoHaze = managedAtmosphere.Haze
	baseAtmoColor = managedAtmosphere.Color
	baseColorBrightness = managedColorCorrection.Brightness
	baseColorContrast = managedColorCorrection.Contrast
	baseColorSaturation = managedColorCorrection.Saturation
	baseColorTint = managedColorCorrection.TintColor
	baseBloomIntensity = managedBloom.Intensity
	lastAppliedLightingTension = -1
	lastAppliedMidDanger = -1
end

local function updateOilPatchFootstepMuffle(): ()
	local root = localRoot
	if not root or not root.Parent then return end
	local pos = root.Position
	local muffled = false
	for _, oil in ipairs(CollectionService:GetTagged("EstuaryOilPatch")) do
		if oil:IsA("BasePart") then
			local rel = oil.CFrame:PointToObjectSpace(pos)
			local half = oil.Size * 0.5
			if math.abs(rel.X) <= half.X + 2.0 and math.abs(rel.Z) <= half.Z + 2.0 and math.abs(rel.Y) <= 8.5 then
				muffled = true
				break
			end
		end
	end
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Sound") and (child.Name == "Running" or child.Name == "Splash" or child.Name == "Landing") then
			if savedFootstepVolume[child] == nil then
				savedFootstepVolume[child] = child.Volume
			end
			local baseVol = savedFootstepVolume[child] or 0.65
			child.Volume = if muffled then baseVol * 0.22 else baseVol
		end
	end
end

local function refreshSceneLightingBaselines(): ()
	local char = localCharacter
	local role = if char ~= nil then char:GetAttribute("Role") else nil
	currentLightingZone = ""
	applyZoneLightingProfile(resolveTargetLightingZone(role, localRoot))
end

local horrorSoundGroup: SoundGroup
do
	local existingGroup = SoundService:FindFirstChild(CONFIG.SoundGroupName)
	if existingGroup ~= nil and existingGroup:IsA("SoundGroup") then
		horrorSoundGroup = existingGroup :: SoundGroup
	else
		horrorSoundGroup = Instance.new("SoundGroup")
		horrorSoundGroup.Name = CONFIG.SoundGroupName
		horrorSoundGroup.Volume = 1
		horrorSoundGroup.Parent = SoundService
	end
end

local MUFFLE_EFFECT_NAME = "ProjectAbyss_TachycardiaMuffle"

local function ensureMuffleOnGroup(groupName: string): EqualizerSoundEffect?
	local grp = SoundService:FindFirstChild(groupName)
	if grp == nil or not grp:IsA("SoundGroup") then
		return nil
	end
	local existing = grp:FindFirstChild(MUFFLE_EFFECT_NAME)
	if existing ~= nil and existing:IsA("EqualizerSoundEffect") then
		return existing :: EqualizerSoundEffect
	end
	local eq = Instance.new("EqualizerSoundEffect")
	eq.Name = MUFFLE_EFFECT_NAME
	eq.HighGain = 0
	eq.MidGain = 0
	eq.LowGain = 0
	eq.Enabled = false
	eq.Parent = grp
	return eq
end

local function updateTachycardiaMuffle(tachyRatio: number): ()
	local active = tachyRatio > 0.005
	for _, grpName in ipairs({ "ProjectAbyss_HunterClientSFX", "ProjectAbyss_HUDAlerts" }) do
		local eq = ensureMuffleOnGroup(grpName)
		if eq ~= nil then
			eq.Enabled = active
			if active then
				eq.HighGain = lerpNumber(0, -20, tachyRatio)
				eq.MidGain = lerpNumber(0, -9, tachyRatio)
				eq.LowGain = lerpNumber(0, 3, tachyRatio)
			else
				eq.HighGain = 0
				eq.MidGain = 0
				eq.LowGain = 0
			end
		end
	end
end

local hasHeartbeatAsset = isValidAssetId(AUDIO_IDS.Heartbeat)
local hasBreathingAsset = isValidAssetId(AUDIO_IDS.TenseBreathing)

if not hasHeartbeatAsset then
	print(string.format("%s AUDIO_IDS.Heartbeat não configurado; operando em modo visual sem erro.", LOG_PREFIX))
end
if not hasBreathingAsset then
	print(string.format("%s AUDIO_IDS.TenseBreathing não configurado; operando em modo visual sem erro.", LOG_PREFIX))
end

local heartbeatSound = Instance.new("Sound")
heartbeatSound.Name = "ProjectAbyss_Heartbeat"
heartbeatSound.SoundGroup = horrorSoundGroup
heartbeatSound.Looped = true
heartbeatSound.Volume = 0
heartbeatSound.PlaybackSpeed = 1
if hasHeartbeatAsset then
	heartbeatSound.SoundId = AUDIO_IDS.Heartbeat
end
heartbeatSound.Parent = horrorSoundGroup

local spatialAudioAnchor = Instance.new("Part")
spatialAudioAnchor.Name = CONFIG.SpatialAnchorName
spatialAudioAnchor.Anchored = true
spatialAudioAnchor.CanCollide = false
spatialAudioAnchor.CanQuery = false
spatialAudioAnchor.CanTouch = false
spatialAudioAnchor.CastShadow = false
spatialAudioAnchor.Transparency = 1
spatialAudioAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
spatialAudioAnchor.Archivable = false
spatialAudioAnchor.CFrame = CFrame.new(0, -500, 0)
spatialAudioAnchor.Parent = Workspace

local spatialAttachment = Instance.new("Attachment")
spatialAttachment.Name = "EmitterAttachment"
spatialAttachment.Parent = spatialAudioAnchor

local breathingSound = Instance.new("Sound")
breathingSound.Name = "ProjectAbyss_TenseBreathing"
breathingSound.SoundGroup = horrorSoundGroup
breathingSound.Looped = true
breathingSound.Volume = 0
breathingSound.RollOffMode = Enum.RollOffMode.InverseTapered
breathingSound.RollOffMinDistance = CONFIG.BreathingMinRollOff
breathingSound.RollOffMaxDistance = CONFIG.BreathingMaxRollOff
if hasBreathingAsset then
	breathingSound.SoundId = AUDIO_IDS.TenseBreathing
end
breathingSound.Parent = spatialAttachment

type VignetteEdge = {
	frame: Frame,
	gradient: UIGradient,
}

local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local existingGui = playerGui:FindFirstChild(CONFIG.GuiName)
if existingGui ~= nil then
	existingGui:Destroy()
end

local vignetteGui = Instance.new("ScreenGui")
vignetteGui.Name = CONFIG.GuiName
vignetteGui.IgnoreGuiInset = true
vignetteGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
vignetteGui.ResetOnSpawn = false
vignetteGui.DisplayOrder = 2
vignetteGui.Enabled = false
vignetteGui.Parent = playerGui

local function createVignetteEdge(name: string, position: UDim2, size: UDim2, rotation: number): VignetteEdge
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.fromRGB(4, 5, 8)
	frame.BackgroundTransparency = 1
	frame.Active = false
	frame.Interactable = false
	frame.Parent = vignetteGui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.38, 0.52),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame

	return {
		frame = frame,
		gradient = gradient,
	}
end

local vignetteEdges: { VignetteEdge } = {
	createVignetteEdge("TopEdge", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.30), 90),
	createVignetteEdge("BottomEdge", UDim2.fromScale(0, 0.70), UDim2.fromScale(1, 0.30), 270),
	createVignetteEdge("LeftEdge", UDim2.fromScale(0, 0), UDim2.fromScale(0.26, 1), 0),
	createVignetteEdge("RightEdge", UDim2.fromScale(0.74, 0), UDim2.fromScale(0.26, 1), 180),
}

local trackedMonsterChar: Model? = nil
local trackedMonsterRoot: BasePart? = nil
local trackedMonsterStage: number = 1

local localCharacter: Model? = nil
local localHumanoid: Humanoid? = nil
local localRoot: BasePart? = nil

local lastAppliedShakeOffset: Vector3 = Vector3.zero
local currentBPM: number = 78
local targetBPM: number = 78
local lastPublishedBPM: number = -1
local bpmAccumulator: number = 0
local currentTachyRatio: number = 0

LocalPlayer:SetAttribute("ClientBPM", 78)

local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local characterConnections: { [Model]: { RBXScriptConnection } } = {}
local localCharConnections: { RBXScriptConnection } = {}
local runtimeConnections: { RBXScriptConnection } = {}

local function clearConnections(list: { RBXScriptConnection }): ()
	for _, conn in ipairs(list) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(list)
end

local function restoreCameraOffset(): ()
	if lastAppliedShakeOffset == Vector3.zero then
		return
	end

	local hum = localHumanoid
	if hum ~= nil and hum.Parent ~= nil then
		hum.CameraOffset = hum.CameraOffset - lastAppliedShakeOffset
	end
	lastAppliedShakeOffset = Vector3.zero
end

local function getCharacterRoot(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp ~= nil and hrp:IsA("BasePart") then
		return hrp :: BasePart
	end
	return character.PrimaryPart
end

local function recomputeMonsterReference(): ()
	local foundChar: Model? = nil
	local foundRoot: BasePart? = nil
	local foundStage = 1

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local char = player.Character
			if char ~= nil and char.Parent ~= nil then
				local role = char:GetAttribute("Role")
				local isDead = char:GetAttribute("IsDead")
				if role == "Monster" and isDead ~= true then
					local root = getCharacterRoot(char)
					if root ~= nil and root.Parent ~= nil then
						foundChar = char
						foundRoot = root
						local stageAttr = char:GetAttribute("Stage")
						if typeof(stageAttr) == "number" then
							foundStage = math.max(1, math.floor(stageAttr))
						end
						break
					end
				end
			end
		end
	end

	trackedMonsterChar = foundChar
	trackedMonsterRoot = foundRoot
	trackedMonsterStage = foundStage
end

local function onRemoteCharacterRemoved(character: Model): ()
	local conns = characterConnections[character]
	if conns ~= nil then
		clearConnections(conns)
		characterConnections[character] = nil
	end

	if trackedMonsterChar == character then
		trackedMonsterChar = nil
		trackedMonsterRoot = nil
		trackedMonsterStage = 1
		recomputeMonsterReference()
	end
end

local function onRemoteCharacterAdded(player: Player, character: Model): ()
	onRemoteCharacterRemoved(character)

	local conns: { RBXScriptConnection } = {}
	characterConnections[character] = conns

	table.insert(
		conns,
		character:GetAttributeChangedSignal("Role"):Connect(function()
			recomputeMonsterReference()
		end)
	)

	table.insert(
		conns,
		character:GetAttributeChangedSignal("Stage"):Connect(function()
			if trackedMonsterChar == character then
				local stageAttr = character:GetAttribute("Stage")
				trackedMonsterStage = if typeof(stageAttr) == "number" then math.max(1, math.floor(stageAttr)) else 1
			end
		end)
	)

	table.insert(
		conns,
		character:GetAttributeChangedSignal("IsDead"):Connect(function()
			recomputeMonsterReference()
		end)
	)

	table.insert(
		conns,
		character.ChildAdded:Connect(function(child: Instance)
			if child.Name == "HumanoidRootPart" and character:GetAttribute("Role") == "Monster" then
				recomputeMonsterReference()
			end
		end)
	)

	table.insert(
		conns,
		character.Destroying:Connect(function()
			onRemoteCharacterRemoved(character)
		end)
	)

	if character:GetAttribute("Role") == "Monster" then
		recomputeMonsterReference()
	end
end

local function onPlayerRemoving(player: Player): ()
	local conns = playerConnections[player]
	if conns ~= nil then
		clearConnections(conns)
		playerConnections[player] = nil
	end

	if player.Character ~= nil then
		onRemoteCharacterRemoved(player.Character)
	end
	recomputeMonsterReference()
end

local function onPlayerAdded(player: Player): ()
	if player == LocalPlayer then
		return
	end

	onPlayerRemoving(player)
	local conns: { RBXScriptConnection } = {}
	playerConnections[player] = conns

	table.insert(
		conns,
		player.CharacterAdded:Connect(function(character: Model)
			onRemoteCharacterAdded(player, character)
		end)
	)

	table.insert(
		conns,
		player.CharacterRemoving:Connect(function(character: Model)
			onRemoteCharacterRemoved(character)
		end)
	)

	if player.Character ~= nil then
		onRemoteCharacterAdded(player, player.Character)
	end
end

local function onLocalCharacterRemoving(): ()
	restoreCameraOffset()
	clearConnections(localCharConnections)
	localCharacter = nil
	localHumanoid = nil
	localRoot = nil
	targetTension = 0
	targetMidDanger = 0
	targetInnerDanger = 0
end

local function onLocalCharacterAdded(character: Model): ()
	onLocalCharacterRemoving()
	localCharacter = character

	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum ~= nil then
		localHumanoid = hum
		table.insert(
			localCharConnections,
			hum.Died:Connect(function()
				restoreCameraOffset()
				targetTension = 0
				targetMidDanger = 0
				targetInnerDanger = 0
			end)
		)
	end

	localRoot = getCharacterRoot(character)

	table.insert(
		localCharConnections,
		character.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Humanoid") and localHumanoid == nil then
				localHumanoid = child
				table.insert(
					localCharConnections,
					child.Died:Connect(function()
						restoreCameraOffset()
						targetTension = 0
						targetMidDanger = 0
						targetInnerDanger = 0
					end)
				)
			elseif child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
				localRoot = child
			end
		end)
	)

	table.insert(
		localCharConnections,
		character:GetAttributeChangedSignal("IsDead"):Connect(function()
			if character:GetAttribute("IsDead") == true then
				restoreCameraOffset()
			end
		end)
	)

	table.insert(
		localCharConnections,
		character:GetAttributeChangedSignal("Role"):Connect(function()
			local role = character:GetAttribute("Role")
			if role == "Monster" or role == "Lobby" then
				restoreCameraOffset()
			end
			applyZoneLightingProfile(resolveTargetLightingZone(role, localRoot))
		end)
	)
end

local function resetProximityTargets(): ()
	currentDistance = math.huge
	targetTension = 0
	targetMidDanger = 0
	targetInnerDanger = 0
end

local function evaluateMonsterProximity(): ()
	local lChar = localCharacter
	local lHum = localHumanoid
	local lRoot = localRoot

	if lChar == nil or lChar.Parent == nil or lRoot == nil or lRoot.Parent == nil then
		resetProximityTargets()
		return
	end

	local localRole = lChar:GetAttribute("Role")
	local localDead = lChar:GetAttribute("IsDead")
	if localRole == "Monster" or localRole == "Lobby" or localDead == true or (lHum ~= nil and lHum.Health <= 0) then
		resetProximityTargets()
		return
	end

	local mChar = trackedMonsterChar
	local mRoot = trackedMonsterRoot
	if mChar == nil or mChar.Parent == nil or mRoot == nil or mRoot.Parent == nil then
		recomputeMonsterReference()
		mChar = trackedMonsterChar
		mRoot = trackedMonsterRoot
		if mChar == nil or mRoot == nil then
			resetProximityTargets()
			return
		end
	end

	if mChar:GetAttribute("Role") ~= "Monster" or mChar:GetAttribute("IsDead") == true then
		recomputeMonsterReference()
		resetProximityTargets()
		return
	end

	local monsterPos = mRoot.Position
	spatialAudioAnchor.CFrame = CFrame.new(monsterPos)

	local dist = (lRoot.Position - monsterPos).Magnitude
	currentDistance = dist

	if dist > CONFIG.OuterRangeStuds then
		targetTension = 0
		targetMidDanger = 0
		targetInnerDanger = 0
		return
	end

	local normalizedOverall: number
	if dist > CONFIG.MidRangeStuds then
		local t = 1 - (dist - CONFIG.MidRangeStuds) / (CONFIG.OuterRangeStuds - CONFIG.MidRangeStuds)
		normalizedOverall = math.clamp(t, 0, 1) * 0.35
	elseif dist > CONFIG.InnerRangeStuds then
		local t = 1 - (dist - CONFIG.InnerRangeStuds) / (CONFIG.MidRangeStuds - CONFIG.InnerRangeStuds)
		normalizedOverall = 0.35 + math.clamp(t, 0, 1) * 0.35
	else
		local t = 1 - (dist / CONFIG.InnerRangeStuds)
		normalizedOverall = 0.70 + math.clamp(t, 0, 1) * 0.30
	end

	local midRatio = math.clamp((CONFIG.MidRangeStuds - dist) / CONFIG.MidRangeStuds, 0, 1)
	local innerRatio = math.clamp((CONFIG.InnerRangeStuds - dist) / CONFIG.InnerRangeStuds, 0, 1)

	if trackedMonsterStage >= 3 then
		normalizedOverall = math.clamp(normalizedOverall * 1.18, 0, 1)
		innerRatio = math.clamp(innerRatio * 1.25, 0, 1)
	end

	targetTension = normalizedOverall
	targetMidDanger = midRatio
	targetInnerDanger = innerRatio
end

local function applyLightingEffects(tension: number, midDanger: number): ()
	if
		math.abs(tension - lastAppliedLightingTension) < 0.003
		and math.abs(midDanger - lastAppliedMidDanger) < 0.003
	then
		return
	end

	lastAppliedLightingTension = tension
	lastAppliedMidDanger = midDanger

	managedAtmosphere.Density = lerpNumber(baseAtmoDensity, CONFIG.MaxAtmosphereDensity, tension)
	managedAtmosphere.Haze = lerpNumber(baseAtmoHaze, CONFIG.MaxAtmosphereHaze, tension)
	managedAtmosphere.Color = baseAtmoColor:Lerp(CONFIG.TensionAtmosphereColor, midDanger)

	managedColorCorrection.Brightness = baseColorBrightness
	managedColorCorrection.Saturation = lerpNumber(baseColorSaturation, CONFIG.MaxDesaturation, midDanger)
	managedColorCorrection.Contrast = lerpNumber(baseColorContrast, CONFIG.MaxContrast, tension)
	managedColorCorrection.TintColor = baseColorTint:Lerp(CONFIG.TensionTintColor, midDanger * 0.75)

	managedBloom.Intensity = lerpNumber(baseBloomIntensity, CONFIG.BloomIntensityMax, tension)

	Lighting.ExposureCompensation = baseExposureCompensation + (CONFIG.MaxExposureDelta * midDanger)
	Lighting.Ambient = baseAmbient:Lerp(targetDarkAmbient, midDanger * 0.55)
	Lighting.OutdoorAmbient = baseOutdoorAmbient:Lerp(targetDarkOutdoor, midDanger * 0.55)
end

type SpecimenAnimItem = {
	part: BasePart,
	baseCF: CFrame,
}

local cachedLobbyRef: Instance? = nil
local cachedSpecimenParts: { SpecimenAnimItem } = {}
local cachedStasisLight: PointLight? = nil
local cachedOscilloscopeLabels: { TextLabel } = {}
local lastOscilloscopeTick = 0

local function clearLobbyAnimCache(): ()
	cachedLobbyRef = nil
	table.clear(cachedSpecimenParts)
	cachedStasisLight = nil
	table.clear(cachedOscilloscopeLabels)
end

local function ensureLobbyAnimCache(): Instance?
	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby == nil then
		clearLobbyAnimCache()
		return nil
	end

	if cachedLobbyRef ~= lobby or #cachedSpecimenParts == 0 or cachedSpecimenParts[1].part.Parent == nil then
		clearLobbyAnimCache()
		cachedLobbyRef = lobby

		local specimenNames = {
			"BiomechanicalSpecimen",
			"SpecimenTorso",
			"SpecimenSkull",
			"SpecimenBioHeart",
			"SpecimenRib_1",
			"SpecimenRib_2",
			"SpecimenRib_3",
			"SpecimenRib_4",
			"SpecimenArm_-1",
			"SpecimenArm_1",
			"SpecimenMandible_-1",
			"SpecimenMandible_1",
		}
		for _, partName in ipairs(specimenNames) do
			local p = lobby:FindFirstChild(partName)
			if p ~= nil and p:IsA("BasePart") then
				table.insert(cachedSpecimenParts, { part = p :: BasePart, baseCF = (p :: BasePart).CFrame })
			end
		end

		local corePart = lobby:FindFirstChild("StasisAmberCore")
		if corePart ~= nil then
			local pt = corePart:FindFirstChildOfClass("PointLight")
			if pt ~= nil then
				cachedStasisLight = pt
			end
		end

		for idx = 1, 3 do
			local mon = lobby:FindFirstChild("BioOscilloscope_" .. tostring(idx))
			if mon ~= nil then
				local lbl = mon:FindFirstChildWhichIsA("TextLabel", true)
				if lbl ~= nil then
					table.insert(cachedOscilloscopeLabels, lbl)
				end
			end
		end
	end

	return lobby
end

local scannerHead: Model? = nil
local scannerRest = CFrame.identity
local scannerNextFrame = 0
local function updateLobbyAmbientVisuals(nowClock: number): ()
	local char = localCharacter
	local role = if char ~= nil then char:GetAttribute("Role") else nil
	if role ~= nil and role ~= "Lobby" then
		return
	end

	local lobby = ensureLobbyAnimCache()
	if lobby == nil then
		return
	end

	if nowClock >= scannerNextFrame then
		scannerNextFrame = nowClock + 1/30
		if not scannerHead or not scannerHead:IsDescendantOf(lobby) then
			local station = lobby:FindFirstChild("ContainmentScanner")
			local head = if station then station:FindFirstChild("ScanHead") else nil
			scannerHead = if head and head:IsA("Model") then head else nil
			if scannerHead and station and station:IsA("Model") then
				scannerRest = station:GetPivot() * CFrame.new(0.28,6.15,0)
			end
		end
		if scannerHead then
			local angle = math.rad(12+17*math.sin(workspace:GetServerTimeNow()*2*math.pi/5))
			scannerHead:PivotTo(scannerRest*CFrame.Angles(0,0,angle))
		end
	end
	local bobOffset = Vector3.new(0, math.sin(nowClock * 1.2) * 0.38, 0)
	for _, entry in ipairs(cachedSpecimenParts) do
		if entry.part.Parent ~= nil then
			entry.part.CFrame = entry.baseCF + bobOffset
		end
	end

	if cachedStasisLight ~= nil and cachedStasisLight.Parent ~= nil then
		cachedStasisLight.Brightness = 1.65 + math.sin(nowClock * 2.1) * 0.22
	end

	if nowClock - lastOscilloscopeTick >= 0.9 then
		lastOscilloscopeTick = nowClock
		for idx, lbl in ipairs(cachedOscilloscopeLabels) do
			if lbl.Parent ~= nil then
				local bpm = 41 + math.floor((math.sin(nowClock * 0.9 + idx) + 1) * 2)
				lbl.Text = "BIO-SCAN // BPM: " .. tostring(bpm)
			end
		end
	end
end

applyAudioEffects = function(tension: number, innerDanger: number): ()
	if hasHeartbeatAsset then
		if tension > 0.01 then
			if not heartbeatSound.IsPlaying then
				heartbeatSound:Play()
			end
			local stageBoost = if trackedMonsterStage >= 3 then 1.15 else 1.0
			heartbeatSound.Volume = math.clamp(tension * CONFIG.MaxHeartbeatVolume * stageBoost, 0, 1)
			heartbeatSound.PlaybackSpeed = lerpNumber(0.92, 1.55, innerDanger) * (if trackedMonsterStage >= 3 then 1.08 else 1.0)
		else
			if heartbeatSound.IsPlaying then
				heartbeatSound:Stop()
			end
			heartbeatSound.Volume = 0
		end
	end

	if hasBreathingAsset then
		if tension > 0.01 then
			if not breathingSound.IsPlaying then
				breathingSound:Play()
			end
			breathingSound.Volume = math.clamp(tension * CONFIG.MaxBreathingVolume, 0, 1)
			breathingSound.PlaybackSpeed = lerpNumber(0.95, 1.22, innerDanger)
		else
			if breathingSound.IsPlaying then
				breathingSound:Stop()
			end
			breathingSound.Volume = 0
		end
	end
end

local function applyVignetteEffects(innerDanger: number, tachyRatio: number, bpmValue: number, nowClock: number): ()
	if innerDanger <= 0.005 and tachyRatio <= 0.005 then
		if vignetteGui.Enabled then
			vignetteGui.Enabled = false
			for _, edge in ipairs(vignetteEdges) do
				edge.frame.BackgroundTransparency = 1
			end
		end
		return
	end

	if not vignetteGui.Enabled then
		vignetteGui.Enabled = true
	end

	local cardiacHz = if tachyRatio > 0.005 then math.clamp(bpmValue / 60, 1.8, 3.6) else lerpNumber(1.3, 2.8, innerDanger)
	local pulseWave = (math.sin(nowClock * math.pi * 2 * cardiacHz) + 1) * 0.5
	local tensionAlpha = innerDanger * 0.72 + pulseWave * innerDanger * 0.18
	local tachyAlpha = if tachyRatio > 0.005 then (0.20 + tachyRatio * 0.36 + pulseWave * (0.16 + tachyRatio * 0.14)) else 0
	local alpha = math.clamp(math.max(tensionAlpha, tachyAlpha), 0, 0.88)
	local transparency = 1 - alpha

	local redShift = math.clamp(math.max(innerDanger * (if trackedMonsterStage >= 3 then 1.0 else 0.85), tachyRatio), 0, 1)
	local targetRed = if tachyRatio > 0.005 then Color3.fromRGB(168, 14, 22) else Color3.fromRGB(130, 10, 16)
	local edgeColor = Color3.fromRGB(6, 7, 10):Lerp(targetRed, redShift)

	for _, edge in ipairs(vignetteEdges) do
		edge.frame.BackgroundColor3 = edgeColor
		edge.frame.BackgroundTransparency = transparency
	end
end

local function applyCameraShake(innerDanger: number, nowClock: number): ()
	local hum = localHumanoid
	local char = localCharacter

	if
		innerDanger <= 0.02
		or hum == nil
		or hum.Parent == nil
		or hum.Health <= 0
		or char == nil
		or char:GetAttribute("IsDead") == true
		or currentDistance > CONFIG.InnerRangeStuds
	then
		restoreCameraOffset()
		return
	end

	local stageFactor = if trackedMonsterStage >= 3 then CONFIG.Stage3ShakeMultiplier else 1.0
	local amplitude = CONFIG.MaxCameraShakeAmplitude * (innerDanger ^ 1.35) * stageFactor

	local noiseX = math.noise(nowClock * 17.3, 1.7, 0)
	local noiseY = math.noise(nowClock * 19.1, 4.3, 0)
	local newShake = Vector3.new(noiseX * amplitude, noiseY * amplitude * 0.85, 0)

	local baseOffset = hum.CameraOffset - lastAppliedShakeOffset
	hum.CameraOffset = baseOffset + newShake
	lastAppliedShakeOffset = newShake
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

table.insert(runtimeConnections, Players.PlayerAdded:Connect(onPlayerAdded))
table.insert(runtimeConnections, Players.PlayerRemoving:Connect(onPlayerRemoving))

table.insert(runtimeConnections, LocalPlayer.CharacterAdded:Connect(onLocalCharacterAdded))
table.insert(runtimeConnections, LocalPlayer.CharacterRemoving:Connect(onLocalCharacterRemoving))

if LocalPlayer.Character ~= nil then
	onLocalCharacterAdded(LocalPlayer.Character)
end

recomputeMonsterReference()

if Workspace:GetAttribute("WorldReady") == true then
	refreshSceneLightingBaselines()
	lastAppliedLightingTension = -1
end

table.insert(
	runtimeConnections,
	Workspace:GetAttributeChangedSignal("WorldReady"):Connect(function()
		if Workspace:GetAttribute("WorldReady") == true then
			refreshSceneLightingBaselines()
			lastAppliedLightingTension = -1
			clearLobbyAnimCache()
		end
	end)
)

local function computeTargetBPM(nowClock: number): (number, number)
	local char = localCharacter
	if char == nil or char.Parent == nil then
		return 78 + math.sin(nowClock * 1.1) * 2, 0
	end

	local role = char:GetAttribute("Role")
	if role == nil or role == "Lobby" then
		return 78 + math.sin(nowClock * 1.1) * 2, 0
	end

	if role == "Monster" then
		return 64, 0
	end

	local isDead = char:GetAttribute("IsDead") == true
	if isDead or (localHumanoid ~= nil and localHumanoid.Health <= 0) then
		return 0, 0
	end

	if char:GetAttribute("IsDowned") == true then
		return 186, 1
	end

	local bpm = 82
	if currentDistance < CONFIG.OuterRangeStuds then
		local proxRatio = math.clamp(1 - (currentDistance / CONFIG.OuterRangeStuds), 0, 1)
		bpm += proxRatio * 78
		if trackedMonsterStage >= 3 then
			bpm += proxRatio * 12
		end
	end

	local exertion = 0
	local fuel = char:GetAttribute("JetpackFuel")
	if typeof(fuel) == "number" and fuel < 65 then
		exertion += math.clamp((65 - fuel) / 65, 0, 1) * 14
	end
	if localRoot ~= nil and localRoot.Parent ~= nil then
		local speed = localRoot.AssemblyLinearVelocity.Magnitude
		if speed > 14 then
			exertion += math.clamp((speed - 14) / 28, 0, 1) * 12
		end
	end
	bpm += math.min(22, exertion)

	local hp = char:GetAttribute("CustomHealth")
	local maxHp = char:GetAttribute("MaxCustomHealth")
	if typeof(hp) == "number" and typeof(maxHp) == "number" and maxHp > 0 then
		local hpRatio = hp / maxHp
		if hpRatio < 0.6 then
			bpm += math.clamp((0.6 - hpRatio) / 0.6, 0, 1) * 24
		end
	end

	bpm = math.clamp(bpm, 76, 198)
	local tachy = if bpm > 160 then math.clamp((bpm - 160) / 28, 0, 1) else 0
	return bpm, tachy
end

local ambientWindSound = Instance.new("Sound")
ambientWindSound.Name = "ProjectAbyss_AmbientWind"
ambientWindSound.SoundGroup = horrorSoundGroup
ambientWindSound.SoundId = AUDIO_IDS.AmbientWind
ambientWindSound.Looped = true
ambientWindSound.Volume = 0
ambientWindSound.PlaybackSpeed = 0.85
ambientWindSound.Parent = horrorSoundGroup

local weatherHost = Instance.new("Part")
weatherHost.Name = "ProjectAbyss_WeatherHost"
weatherHost.Anchored = true
weatherHost.CanCollide, weatherHost.CanQuery, weatherHost.CanTouch = false, false, false
weatherHost.CastShadow = false
weatherHost.Transparency = 1
weatherHost.Size = Vector3.new(38, 18, 38)
weatherHost.Archivable = false
weatherHost.CFrame = CFrame.new(0, -400, 0)
weatherHost.Parent = Workspace

local weatherSpores = Instance.new("ParticleEmitter")
weatherSpores.Name = "AbyssalSporeAshWeather"
weatherSpores.Enabled = false
weatherSpores.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 168, 92)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(168, 224, 198)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(92, 108, 118)),
})
weatherSpores.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(0.5, 0.22), NumberSequenceKeypoint.new(1, 0)})
weatherSpores.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1)})
weatherSpores.Lifetime = NumberRange.new(2.8, 4.6)
weatherSpores.Rate = 20
weatherSpores.Speed = NumberRange.new(1.2, 3.2)
weatherSpores.SpreadAngle = Vector2.new(180, 180)
weatherSpores.LightEmission = 0.65
weatherSpores.Parent = weatherHost

local nextHorrorStinger = os.clock() + 14
local stingerIds = { AUDIO_IDS.DistantGroan, AUDIO_IDS.DistantRoar, AUDIO_IDS.CaveDrip }
local activeRigLight: Instance? = nil

local CYCLE_PERIOD_SECONDS = 180 -- Full 24h cycle every 3 minutes in Estuary gameplay
local cycleAnchorServerTime: number? = nil

	-- Keyframes: 6.0 Dawn, 12.5 Day, 16.5 Golden Dusk, 22.0 Playable Biolum Night
	type KF = { h: number, bright: number, amb: Color3, outAmb: Color3, top: Color3, bot: Color3, dens: number, haze: number, atmoCol: Color3, decay: Color3, tint: Color3, sunInt: number }
	local keys: {KF} = {
		{ h = 0.0,  bright = 1.90, amb = Color3.fromRGB(48, 58, 76), outAmb = Color3.fromRGB(74, 88, 108), top = Color3.fromRGB(132, 162, 212), bot = Color3.fromRGB(32, 42, 54), dens = 0.31, haze = 2.2, atmoCol = Color3.fromRGB(78, 96, 118), decay = Color3.fromRGB(96, 128, 168), tint = Color3.fromRGB(224, 234, 248), sunInt = 0.06 },
		{ h = 6.0,  bright = 2.15, amb = Color3.fromRGB(64, 56, 62), outAmb = Color3.fromRGB(102, 84, 78), top = Color3.fromRGB(255, 168, 118), bot = Color3.fromRGB(42, 34, 42), dens = 0.29, haze = 2.0, atmoCol = Color3.fromRGB(132, 108, 102), decay = Color3.fromRGB(224, 132, 92), tint = Color3.fromRGB(252, 236, 224), sunInt = 0.18 },
		{ h = 12.5, bright = 2.55, amb = Color3.fromRGB(68, 76, 82), outAmb = Color3.fromRGB(104, 114, 106), top = Color3.fromRGB(244, 240, 226), bot = Color3.fromRGB(48, 56, 54), dens = 0.26, haze = 1.7, atmoCol = Color3.fromRGB(132, 146, 138), decay = Color3.fromRGB(196, 204, 188), tint = Color3.fromRGB(250, 250, 246), sunInt = 0.12 },
		{ h = 16.6, bright = 2.25, amb = Color3.fromRGB(58, 66, 72), outAmb = Color3.fromRGB(88, 98, 92),  top = Color3.fromRGB(245, 212, 165), bot = Color3.fromRGB(36, 42, 46), dens = 0.30, haze = 2.1, atmoCol = Color3.fromRGB(112, 124, 118), decay = Color3.fromRGB(196, 142, 96), tint = Color3.fromRGB(246, 242, 234), sunInt = 0.16 },
		{ h = 20.5, bright = 1.92, amb = Color3.fromRGB(48, 58, 76), outAmb = Color3.fromRGB(74, 88, 108), top = Color3.fromRGB(138, 166, 214), bot = Color3.fromRGB(32, 42, 54), dens = 0.31, haze = 2.2, atmoCol = Color3.fromRGB(78, 96, 118), decay = Color3.fromRGB(96, 128, 168), tint = Color3.fromRGB(224, 234, 248), sunInt = 0.06 },
		{ h = 24.0, bright = 1.90, amb = Color3.fromRGB(48, 58, 76), outAmb = Color3.fromRGB(74, 88, 108), top = Color3.fromRGB(132, 162, 212), bot = Color3.fromRGB(32, 42, 54), dens = 0.31, haze = 2.2, atmoCol = Color3.fromRGB(78, 96, 118), decay = Color3.fromRGB(96, 128, 168), tint = Color3.fromRGB(224, 234, 248), sunInt = 0.06 },
	}
	local function sampleCycleKeyframes(clockHour: number)
	local k0, k1 = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if clockHour >= keys[i].h and clockHour <= keys[i + 1].h then
			k0, k1 = keys[i], keys[i + 1]
			break
		end
	end
	local span = math.max(0.001, k1.h - k0.h)
	local a = math.clamp((clockHour - k0.h) / span, 0, 1)
	local label = if clockHour >= 19.2 or clockHour < 5.2
		then "NOITE ABISSAL"
		elseif clockHour < 8.5 then "ALVORADA RUBRA"
		elseif clockHour < 15.5 then "DIA DE CAÇA"
		else "CREPÚSCULO"
	local nightFactor = if clockHour >= 19.2 or clockHour < 5.5 then 1.0 elseif clockHour < 8.0 or clockHour >= 16.5 then 0.55 else 0.25
	return k0, k1, a, label, nightFactor
end

local function updateHorrorHuntAmbience(nowClock: number)
	local inEstuary = currentLightingZone == "Estuary"
	local nightStrength = 0.5
	if inEstuary then
		if cycleAnchorServerTime == nil then
			cycleAnchorServerTime = Workspace:GetServerTimeNow()
		end
		local epoch = Workspace:GetAttribute("HuntLightingEpoch")
		local anchor = if typeof(epoch)=="number" then epoch else (cycleAnchorServerTime :: number)
		local elapsedCycle = math.max(0, Workspace:GetServerTimeNow() - anchor)
		local clockHour = (16.2 + (elapsedCycle / CYCLE_PERIOD_SECONDS) * 24.0) % 24.0
		local k0, k1, a, phaseLabel, nf = sampleCycleKeyframes(clockHour)
		nightStrength = nf

		Lighting.ClockTime = clockHour
		Lighting.Brightness = lerpNumber(k0.bright, k1.bright, a)
		baseAmbient = k0.amb:Lerp(k1.amb, a)
		baseOutdoorAmbient = k0.outAmb:Lerp(k1.outAmb, a)
		baseAtmoDensity = lerpNumber(k0.dens, k1.dens, a)
		baseAtmoHaze = lerpNumber(k0.haze, k1.haze, a)
		baseAtmoColor = k0.atmoCol:Lerp(k1.atmoCol, a)
		baseColorTint = k0.tint:Lerp(k1.tint, a)
		baseExposureCompensation = 0.25 + 0.18 * nf
		baseAmbient = baseAmbient:Lerp(Color3.fromRGB(89,99,114),0.46*nf)
		baseOutdoorAmbient = baseOutdoorAmbient:Lerp(Color3.fromRGB(113,126,144),0.42*nf)
		Lighting.ColorShift_Top = k0.top:Lerp(k1.top,a)
		Lighting.ColorShift_Bottom = k0.bot:Lerp(k1.bot,a)
		if currentMidDanger <= 0.005 and currentTension <= 0.005 then
			Lighting.Ambient = baseAmbient
			Lighting.OutdoorAmbient = baseOutdoorAmbient
			managedAtmosphere.Density = baseAtmoDensity
			managedAtmosphere.Haze = baseAtmoHaze
			managedAtmosphere.Color = baseAtmoColor
			managedAtmosphere.Decay = k0.decay:Lerp(k1.decay, a)
			managedColorCorrection.TintColor = baseColorTint
			Lighting.ExposureCompensation = baseExposureCompensation
		else
			managedAtmosphere.Decay = k0.decay:Lerp(k1.decay, a)
			lastAppliedLightingTension = -1
		end
		local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
		if sunRays then sunRays.Intensity = lerpNumber(k0.sunInt, k1.sunInt, a) end
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky then
			sky.CelestialBodiesShown = true
			sky.SunAngularSize = 11
			sky.MoonAngularSize = 18
		end

		local hr = math.floor(clockHour)
		local mn = math.floor((clockHour - hr) * 60)
		Workspace:SetAttribute("TimeOfDayLabel", string.format("%s (%02d:%02d)", phaseLabel, hr, mn))

		if not ambientWindSound.IsPlaying then ambientWindSound:Play() end
		ambientWindSound.Volume = 0.16
		local cam = Workspace.CurrentCamera
		if cam then
			weatherHost.CFrame = CFrame.new(cam.CFrame.Position + cam.CFrame.LookVector * 14)
		end
		weatherSpores.Enabled = true
	else
		cycleAnchorServerTime = nil
		Workspace:SetAttribute("TimeOfDayLabel", nil)
		ambientWindSound.Volume = 0
		if ambientWindSound.IsPlaying then ambientWindSound:Stop() end
		weatherSpores.Enabled = false
	end

	-- Role tactical Headlamp (Hunter) vs Night-Vision Rim Light (Monster)
	local char = localCharacter
	local role = if char then char:GetAttribute("Role") else nil
	local dead = if char then (char:GetAttribute("IsDead") == true) else true
	local headOrRoot = if char then (char:FindFirstChild("Head") or localRoot) else nil
	local wantLightKind = if not inEstuary or dead or not headOrRoot or not headOrRoot:IsA("BasePart")
		then "None"
		elseif role == "Monster" then "Monster"
		elseif role == "Assault" or role == "Medic" or role == "Trapper" or role == "Support" then "Hunter"
		else "None"

	if activeRigLight and (not activeRigLight.Parent or activeRigLight:GetAttribute("Kind") ~= wantLightKind) then
		activeRigLight:Destroy()
		activeRigLight = nil
	end
	if wantLightKind == "Hunter" and not activeRigLight and headOrRoot and headOrRoot:IsA("BasePart") then
		local sl = Instance.new("SpotLight")
		sl.Name = "TacticalHunterHeadlamp"
		sl:SetAttribute("Kind", "Hunter")
		sl.Face = Enum.NormalId.Front
		sl.Angle = 58
		sl.Brightness = 3.2
		sl.Range = 90
		sl.Shadows = true
		sl.Color = Color3.fromRGB(224, 240, 255)
		sl.Parent = headOrRoot
		activeRigLight = sl
	elseif wantLightKind == "Monster" and not activeRigLight and localRoot then
		local pl = Instance.new("PointLight")
		pl.Name = "MonsterNightVision"
		pl:SetAttribute("Kind", "Monster")
		pl.Brightness = 1.35
		pl.Range = 64
		pl.Shadows = false
		pl.Color = Color3.fromRGB(255, 194, 150)
		pl.Parent = localRoot
		activeRigLight = pl
	end

	if activeRigLight and activeRigLight:IsA("SpotLight") then
		activeRigLight.Brightness = 1.6 + nightStrength * 2.2
	elseif activeRigLight and activeRigLight:IsA("PointLight") then
		activeRigLight.Brightness = 0.65 + nightStrength * 0.95
	end

	-- Distant spatial horror whispers / echoes in Estuary mist
	if inEstuary and nowClock >= nextHorrorStinger and localRoot then
		nextHorrorStinger = nowClock + math.random(15, 28)
		local ang = math.random() * math.pi * 2
		local d = math.random(85, 135)
		local p = Instance.new("Part")
		p.Name = "SpatialHorrorEcho"
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.Transparency = 1
		p.Size = Vector3.one
		p.Position = localRoot.Position + Vector3.new(math.cos(ang) * d, math.random(4, 16), math.sin(ang) * d)
		p.Parent = Workspace
		local s = Instance.new("Sound")
		s.SoundId = stingerIds[math.random(1, #stingerIds)]
		s.SoundGroup = horrorSoundGroup
		s.Volume = 0.36
		s.PlaybackSpeed = 0.65 + math.random() * 0.25
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 18
		s.RollOffMaxDistance = 175
		s.Parent = p
		s:Play()
		game:GetService("Debris"):AddItem(p, 5)
	end
end

local proximityAccumulator = 0

table.insert(
	runtimeConnections,
	RunService.Heartbeat:Connect(function(dt: number)
		local nowClock = os.clock()
		updateLobbyAmbientVisuals(nowClock)

		proximityAccumulator += dt
		if proximityAccumulator >= CONFIG.ProximityCheckInterval then
			proximityAccumulator = 0
			local lChar = localCharacter
			local lRole = if lChar then lChar:GetAttribute("Role") else nil
			applyZoneLightingProfile(resolveTargetLightingZone(lRole, localRoot))
			updateHorrorHuntAmbience(nowClock)
			updateOilPatchFootstepMuffle()
			evaluateMonsterProximity()
		end

		local desiredBPM, desiredTachy = computeTargetBPM(nowClock)
		targetBPM = desiredBPM
		local bpmAlpha = math.clamp(dt * 4.5, 0, 1)
		currentBPM = lerpNumber(currentBPM, targetBPM, bpmAlpha)
		currentTachyRatio = if desiredTachy > 0 or currentBPM > 160
			then math.clamp((currentBPM - 160) / 28, 0, 1)
			else lerpNumber(currentTachyRatio, 0, bpmAlpha)
		if currentTachyRatio < 0.004 and desiredTachy == 0 then
			currentTachyRatio = 0
		end

		bpmAccumulator += dt
		if bpmAccumulator >= 0.15 then
			bpmAccumulator = 0
			local roundedBPM = math.max(0, math.round(currentBPM))
			if roundedBPM ~= lastPublishedBPM then
				lastPublishedBPM = roundedBPM
				LocalPlayer:SetAttribute("ClientBPM", roundedBPM)
			end
			updateTachycardiaMuffle(currentTachyRatio)
		end

		local hasActiveTension = currentTension > 0.001
			or targetTension > 0.001
			or currentMidDanger > 0.001
			or targetMidDanger > 0.001
			or currentInnerDanger > 0.001
			or targetInnerDanger > 0.001
			or lastAppliedShakeOffset ~= Vector3.zero

		if not hasActiveTension and currentTachyRatio <= 0.001 then
			if vignetteGui.Enabled then
				applyVignetteEffects(0, 0, currentBPM, nowClock)
			end
			return
		end

		local alpha = 1 - math.exp(-CONFIG.TensionSmoothSpeed * dt)
		currentTension = lerpNumber(currentTension, targetTension, alpha)
		currentMidDanger = lerpNumber(currentMidDanger, targetMidDanger, alpha)
		currentInnerDanger = lerpNumber(currentInnerDanger, targetInnerDanger, alpha)

		if currentTension < 0.001 and targetTension == 0 then
			currentTension = 0
		end
		if currentMidDanger < 0.001 and targetMidDanger == 0 then
			currentMidDanger = 0
		end
		if currentInnerDanger < 0.001 and targetInnerDanger == 0 then
			currentInnerDanger = 0
		end

		applyLightingEffects(currentTension, currentMidDanger)
		if applyAudioEffects ~= nil then
			applyAudioEffects(currentTension, currentInnerDanger)
		end
		applyVignetteEffects(currentInnerDanger, currentTachyRatio, currentBPM, nowClock)
		applyCameraShake(currentInnerDanger, nowClock)
	end)
)

vignetteGui.Destroying:Connect(function()
	updateTachycardiaMuffle(0)
	restoreCameraOffset()
	clearConnections(runtimeConnections)
	clearConnections(localCharConnections)
	for player, conns in pairs(playerConnections) do
		clearConnections(conns)
		playerConnections[player] = nil
	end
	for char, conns in pairs(characterConnections) do
		clearConnections(conns)
		characterConnections[char] = nil
	end
end)
