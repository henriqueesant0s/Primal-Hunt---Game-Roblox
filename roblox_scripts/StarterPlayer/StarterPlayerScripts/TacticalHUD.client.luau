
--!strict
--[[
	PROJECT ABYSS | TacticalHUD.client.lua
	Localização: StarterPlayer/StarterPlayerScripts/TacticalHUD.client.lua

	HUD Assimétrico Kairos-09 (Obsidian / Pale Ivory / Muted Gold / Dirty Olive):
	1. HUD dos 4 Caçadores: bússola minimalista superior, diretiva de contenção, mira dinâmica limpa,
	   telemetria de esquadrão sem caixas ruidosas, dock compacto de vitais & habilidades [Q]/[G]/[F]
	   e Radar Acústico sob demanda com animação rápida ativada pela tecla [R].
	2. HUD do Monstro: barra superior de Biomassa Onyx, gotejamento viscoso a 100%, Hive Sense [♥ BPM],
	   retícula de garras, biométrica da carne, habilidades de mutação e supressão de Cúpula Estática.
	3. Telas Pós-Partida: Colapso CRT + Relatório de Autópsia (CLEANSED // CADAVER RECLAIMED) para Caçadores;
	   Inundação de fluido Onyx + THE APEX SURPASSES THE SHELL. para Monstro.
]]

local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AEM_UIKit = require(ReplicatedStorage:WaitForChild("AEM_UIKit"))

local LocalPlayer = Players.LocalPlayer
local LOG_PREFIX = "[PROJECT ABYSS][TacticalHUD]"

local AUDIO_IDS = {
	Stage2Alert = "rbxassetid://9126102843",
	Stage3Alert = "rbxassetid://118218169117498",
	CRTOff = "rbxassetid://9117867630",
	CRTBeep = "rbxassetid://9118777856",
	BoneCrunch = "rbxassetid://137260412436272",
}

local CONFIG = {
	GuiName = "ProjectAbyss_TacticalHUD",
	DownedBillboardPrefix = "ProjectAbyss_DownedBeacon_",
	BarTweenInfo = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	BannerInTween = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	BannerOutTween = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	RadarOpenTween = TweenInfo.new(0.20, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
	RadarCloseTween = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	BannerHoldSeconds = 4.5,
	DefaultMaxJetpack = 100,
	DefaultMaxShield = 100,
	DefaultMaxStamina = 100,
	DefaultMaxEvolution = 100,
	DefaultMaxDomeCooldown = 75,
	BillboardMaxDistance = 260,
	RadarRangeStuds = 220,
}

type RoleStyle = {
	tag: string,
	displayName: string,
	accent: Color3,
}

local HUNTER_ROLES: { [string]: RoleStyle } = {
	Trapper = { tag = "TRK", displayName = "TRACKER", accent = AEM_UIKit.AMBER_WIRE },
	Assault = { tag = "AST", displayName = "ASSAULT", accent = AEM_UIKit.IVORY_TEXT },
	Support = { tag = "SUP", displayName = "SUPPORT", accent = AEM_UIKit.AMBER_GLOW },
	Medic = { tag = "MED", displayName = "MEDIC", accent = AEM_UIKit.AMBER_SOFT },
}

local SKILL_DISPLAY_META: { [string]: { label: string, glyph: string } } = {
	HarpoonTether = { label = "HARPOON", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.HarpoonTether },
	PlanetScanner = { label = "SCANNER", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.PlanetScanner },
	DeployDome = { label = "DOME STAGE", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.DeployDome },
	PersonalMatrix = { label = "AEGIS MATRIX", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.PersonalMatrix },
	DrawIonRifle = { label = "ION RIFLE", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.DrawIonRifle },
	HealingBeam = { label = "MED BEAM", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.HealingBeam },
	HealingBurst = { label = "HEAL PULSE", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.HealingBurst },
	OrbitalBarrage = { label = "ORBITAL", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.OrbitalBarrage },
	ShieldProjector = { label = "SHIELD PROJ", glyph = AEM_UIKit.SKILL_ID_TO_GLYPH.ShieldProjector },
}

local MONSTER_STAGE_TITLES = {
	[1] = "STAGE I: THE STALKER // PHANTOM CARAPACE",
	[2] = "STAGE II: THE APEX VESSEL // ONYX MUTATION",
	[3] = "STAGE III: OBLIVION TITAN // APEX OVERLOAD",
}

local function setWireBracketColor(frame: Frame, col: Color3): ()
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("Frame") and not string.find(child.Name, "_Glow", 1, true) then
			if child.Name == "SlantedRailContainer" then
				setWireBracketColor(child, col)
			elseif string.find(child.Name, "Bracket", 1, true) or string.find(child.Name, "TopBot", 1, true) or string.find(child.Name, "Slant", 1, true) then
				child.BackgroundColor3 = col
			end
		end
	end
end

local WEAPON_CAPS: { [string]: number } = {
	PlasmaRifle = 72,
	IonRifle = 48,
	BioCarbine = 60,
	GaussSMG = 84,
	LaserCutter = 100,
}

local function isHunterRole(role: string?): boolean
	return role ~= nil and HUNTER_ROLES[role] ~= nil
end

local function getNumberAttr(instance: Instance, attrName: string, fallback: number): number
	local value = instance:GetAttribute(attrName)
	if typeof(value) == "number" then
		if value ~= value then
			return fallback
		end
		return value
	end
	return fallback
end

local function getBoolAttr(instance: Instance, attrName: string): boolean
	return instance:GetAttribute(attrName) == true
end

local function getStringAttr(instance: Instance, attrName: string): string?
	local value = instance:GetAttribute(attrName)
	if typeof(value) == "string" then
		return value
	end
	return nil
end

local function clearConnections(list: { RBXScriptConnection }): ()
	for _, conn in ipairs(list) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(list)
end

-- Grupo e sons de alerta / encerramento
local alertSoundGroup: SoundGroup
do
	local existingGroup = SoundService:FindFirstChild("ProjectAbyss_HUDAlerts")
	if existingGroup ~= nil and existingGroup:IsA("SoundGroup") then
		alertSoundGroup = existingGroup :: SoundGroup
	else
		alertSoundGroup = Instance.new("SoundGroup")
		alertSoundGroup.Name = "ProjectAbyss_HUDAlerts"
		alertSoundGroup.Volume = 0.9
		alertSoundGroup.Parent = SoundService
	end
end

local function playOneShotAlert(soundId: string, speed: number?, volume: number?): ()
	if soundId == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.SoundGroup = alertSoundGroup
	s.PlaybackSpeed = speed or 1
	s.Volume = volume or 0.72
	s.Parent = alertSoundGroup
	s:Play()
	s.Ended:Once(function()
		if s.Parent ~= nil then
			s:Destroy()
		end
	end)
	Debris:AddItem(s, 7)
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
do
	local existingHud = playerGui:FindFirstChild(CONFIG.GuiName)
	if existingHud ~= nil then
		existingHud:Destroy()
	end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = CONFIG.GuiName
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 6
screenGui.Parent = playerGui

local crtLayer = AEM_UIKit.createCRTScanlineLayer(screenGui, 2)
crtLayer.root.Visible = false

local hudCanvas, getHudScale = AEM_UIKit.createScaledCanvas(screenGui, "TacticalHUDCanvas", 6)
local toastCanvas, _ = AEM_UIKit.createScaledCanvas(screenGui, "ToastScaledCanvas", 36)
local function syncCinemaVisibility()
	hudCanvas.Visible = LocalPlayer:GetAttribute("AbyssCinemaActive") ~= true
end
LocalPlayer:GetAttributeChangedSignal("AbyssCinemaActive"):Connect(syncCinemaVisibility)
syncCinemaVisibility()

-- Silencia o ScreenGui legado MonsterControls (sem destruir lógica de MonsterClient)
local function suppressLegacyMonsterGui(): ()
	local legacy = playerGui:FindFirstChild("MonsterControls")
	if legacy ~= nil and legacy:IsA("ScreenGui") then
		(legacy :: ScreenGui).Enabled = false
	end
end
suppressLegacyMonsterGui()

-- ============================================================================
-- ELEMENTOS GLOBAIS COMPARTILHADOS EM RODADA (KAIROS-09 AMBER WIREFRAME)
-- ============================================================================
local stageBanner = AEM_UIKit.createWireBracketFrame(hudCanvas, {
	name = "GlobalStageBanner",
	parent = hudCanvas,
	anchorPoint = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, -70),
	size = UDim2.fromOffset(580, 40),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.80,
	bracketColor = AEM_UIKit.BOSS_CRIMSON,
	bracketThickness = 1.25,
	bracketLength = 12,
	mode = "LeftRight",
	glow = true,
	zIndex = 24,
})
stageBanner.Visible = false
local stageBannerLabel = AEM_UIKit.makeMonoLabel({
	name = "AlertText",
	parent = stageBanner,
	size = UDim2.fromScale(0.94, 0.80),
	position = UDim2.fromScale(0.03, 0.10),
	text = "",
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	alignX = Enum.TextXAlignment.Center,
	textScaled = true,
	minText = 14,
	maxText = 18,
	zIndex = 25,
})

local bossHealthBar = AEM_UIKit.createSegmentedBossBar(hudCanvas, {
	name = "BossHealthBar",
	parent = hudCanvas,
	position = UDim2.new(0.5, 0, 0, 58),
	anchorPoint = Vector2.new(0.5, 0),
	widthPx = 740,
	barHeightPx = 15,
	segments = 24,
	archDepthPx = 5,
	headerText = MONSTER_STAGE_TITLES[1],
	subLeftText = "VITALS // 1200 / 1200",
	subRightText = "CARAPACE // 600 / 600",
	zIndex = 12,
})
bossHealthBar.root.Visible = false

local matchStatusBar = Instance.new("Frame")
matchStatusBar.Name = "MatchStatusBar"
matchStatusBar.AnchorPoint = Vector2.new(0.5, 0)
matchStatusBar.Position = UDim2.new(0.5, 0, 0, 156)
matchStatusBar.Size = UDim2.fromOffset(300, 24)
matchStatusBar.BackgroundTransparency = 1
matchStatusBar.BorderSizePixel = 0
matchStatusBar.Visible = false
matchStatusBar.ZIndex = 12
matchStatusBar.Parent = hudCanvas

local matchStatusLabel = AEM_UIKit.makeMonoLabel({
	name = "StatusText",
	parent = matchStatusBar,
	size = UDim2.fromScale(0.96, 0.90),
	position = UDim2.fromScale(0.02, 0.05),
	text = "CAÇA  ·  00:00",
	color = AEM_UIKit.IVORY_TEXT,
	alignX = Enum.TextXAlignment.Center,
	textSize = 17,
	zIndex = 13,
})

local relayContainer = AEM_UIKit.createWireBracketFrame(hudCanvas, {
	name = "PowerRelayPanel",
	parent = hudCanvas,
	anchorPoint = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 184),
	size = UDim2.fromOffset(340, 32),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.84,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.2,
	bracketLength = 8,
	mode = "LeftRight",
	glow = true,
	zIndex = 12,
})
relayContainer.Visible = false
local relayBarText = AEM_UIKit.makeMonoLabel({
	name = "RelayText",
	parent = relayContainer,
	size = UDim2.fromScale(0.92, 0.54),
	position = UDim2.fromScale(0.04, 0.08),
	text = "A.E.M. ANCHOR RELAY // 12000 / 12000 HP",
	color = AEM_UIKit.IVORY_TEXT,
	alignX = Enum.TextXAlignment.Center,
	textSize = 12,
	zIndex = 13,
})
local relaySegBar = AEM_UIKit.createSlimBar({
	name = "RelaySlimBar",
	parent = relayContainer,
	size = UDim2.new(0.80, 0, 0, 3),
	position = UDim2.fromScale(0.10, 0.74),
	fillColor = AEM_UIKit.AMBER_WIRE,
	zIndex = 13,
})

local roomBoostFrame = AEM_UIKit.createWireBracketFrame(hudCanvas, {
	name = "RoomBoostFrame",
	parent = hudCanvas,
	anchorPoint = Vector2.new(0, 0),
	position = UDim2.fromOffset(28, 146),
	size = UDim2.fromOffset(176, 26),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.86,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.2,
	bracketLength = 7,
	mode = "Corners",
	glow = true,
	zIndex = 12,
})
roomBoostFrame.Visible = false

local roomBoostButton = Instance.new("TextButton")
roomBoostButton.Name = "RoomBoostButton"
roomBoostButton.Size = UDim2.fromScale(1, 1)
roomBoostButton.BackgroundTransparency = 1
roomBoostButton.BorderSizePixel = 0
roomBoostButton.AutoButtonColor = false
roomBoostButton.Text = "2x MARROW BOOST"
roomBoostButton.TextColor3 = AEM_UIKit.AMBER_WIRE
roomBoostButton.ZIndex = 13
roomBoostButton.Parent = roomBoostFrame
AEM_UIKit.styleButtonText(roomBoostButton, Enum.FontWeight.Bold, 11, 12, 0.82, false)

local rewardToast = AEM_UIKit.createWireBracketFrame(toastCanvas, {
	name = "EconomyRewardToast",
	parent = toastCanvas,
	anchorPoint = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 210),
	size = UDim2.fromOffset(540, 42),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.80,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.2,
	bracketLength = 12,
	mode = "LeftRight",
	glow = true,
	zIndex = 26,
})
rewardToast.Visible = false
local rewardToastLabel = AEM_UIKit.makeMonoLabel({
	name = "ToastText",
	parent = rewardToast,
	size = UDim2.fromScale(0.92, 0.84),
	position = UDim2.fromScale(0.04, 0.08),
	text = "",
	color = AEM_UIKit.AMBER_GLOW,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.SemiBold,
	alignX = Enum.TextXAlignment.Center,
	wrapped = true,
	textScaled = true,
	minText = 13,
	maxText = 16,
	zIndex = 27,
})

-- ============================================================================
-- 1) HUD DOS 4 CAÇADORES (KAIROS-09 6-ZONE AMBER WIREFRAME + RADAR [R])
-- ============================================================================
local hunterHudRoot = Instance.new("Frame")
hunterHudRoot.Name = "HunterHUDRoot"
hunterHudRoot.Size = UDim2.fromScale(1, 1)
hunterHudRoot.BackgroundTransparency = 1
hunterHudRoot.Visible = false
hunterHudRoot.ZIndex = 4
hunterHudRoot.Parent = hudCanvas

-- F3: Canto Superior Esquerdo — Emblema A.E.M. + Containment Area Kairos-09
local topLeftIdentity = Instance.new("Frame")
topLeftIdentity.Name = "TopLeftIdentity"
topLeftIdentity.AnchorPoint = Vector2.new(0, 0)
topLeftIdentity.Position = UDim2.fromOffset(28, 64)
topLeftIdentity.Size = UDim2.fromOffset(380, 74)
topLeftIdentity.BackgroundTransparency = 1
topLeftIdentity.BorderSizePixel = 0
topLeftIdentity.ZIndex = 10
topLeftIdentity.Parent = hunterHudRoot

do
	local emblem = AEM_UIKit.createInvertedTriangleLogo(topLeftIdentity, 42, AEM_UIKit.AMBER_WIRE)
	emblem.Position = UDim2.fromOffset(0, 2)

	AEM_UIKit.makeMonoLabel({
		name = "OrgTitle",
		parent = topLeftIdentity,
		size = UDim2.fromOffset(300, 24),
		position = UDim2.fromOffset(52, 0),
		text = "A.E.M.",
		color = AEM_UIKit.IVORY_TEXT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Bold,
		textSize = 24,
		zIndex = 11,
	})

	AEM_UIKit.makeMonoLabel({
		name = "OrgSubtitle",
		parent = topLeftIdentity,
		size = UDim2.fromOffset(300, 16),
		position = UDim2.fromOffset(52, 23),
		text = "RECLAMATION TEAM",
		color = AEM_UIKit.AMBER_SOFT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.SemiBold,
		textSize = 13,
		zIndex = 11,
	})

	local identityRule = Instance.new("Frame")
	identityRule.Name = "IdentityHairline"
	identityRule.Position = UDim2.fromOffset(0, 46)
	identityRule.Size = UDim2.fromOffset(340, 1)
	identityRule.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
	identityRule.BackgroundTransparency = 0.25
	identityRule.BorderSizePixel = 0
	identityRule.ZIndex = 11
	identityRule.Parent = topLeftIdentity

	local ruleGrad = Instance.new("UIGradient")
	ruleGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.75, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	ruleGrad.Parent = identityRule

	AEM_UIKit.makeMonoLabel({
		name = "SectorLocation",
		parent = topLeftIdentity,
		size = UDim2.fromOffset(360, 20),
		position = UDim2.fromOffset(0, 51),
		text = "CONTAINMENT AREA - KAIROS-09",
		color = AEM_UIKit.IVORY_TEXT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.SemiBold,
		textSize = 15,
		zIndex = 11,
	})
end

-- F4 (Empilhado abaixo do BossHealthBar): Bússola + Timer
local compassBar = Instance.new("Frame")
compassBar.Name = "CompassTelemetryBar"
compassBar.AnchorPoint = Vector2.new(0.5, 0)
compassBar.Position = UDim2.new(0.5, 0, 0, 132)
compassBar.Size = UDim2.fromOffset(360, 24)
compassBar.BackgroundTransparency = 1
compassBar.BorderSizePixel = 0
compassBar.ZIndex = 10
compassBar.Parent = hunterHudRoot

do
	local compassRule = Instance.new("Frame")
	compassRule.Name = "CompassHairline"
	compassRule.Size = UDim2.new(0.78, 0, 0, 1)
	compassRule.AnchorPoint = Vector2.new(0.5, 1)
	compassRule.Position = UDim2.new(0.5, 0, 1, 0)
	compassRule.BackgroundColor3 = AEM_UIKit.HAIRLINE_DIM
	compassRule.BackgroundTransparency = 0.55
	compassRule.BorderSizePixel = 0
	compassRule.ZIndex = 11
	compassRule.Parent = compassBar
end

local compassText = AEM_UIKit.makeMonoLabel({
	name = "CompassHeading",
	parent = compassBar,
	size = UDim2.fromScale(0.96, 0.90),
	position = UDim2.fromScale(0.02, 0.05),
	text = "NW · 000° N · NE  |  00:00",
	color = AEM_UIKit.IVORY_TEXT,
	alignX = Enum.TextXAlignment.Center,
	textSize = 13,
	zIndex = 11,
})

-- F5: Canto Superior Direito — Diretiva Borderless
local objectivePanel = Instance.new("Frame")
objectivePanel.Name = "ContainmentObjectivePanel"
objectivePanel.AnchorPoint = Vector2.new(1, 0)
objectivePanel.Position = UDim2.new(1, -28, 0, 64)
objectivePanel.Size = UDim2.fromOffset(320, 74)
objectivePanel.BackgroundTransparency = 1
objectivePanel.BorderSizePixel = 0
objectivePanel.ZIndex = 10
objectivePanel.Parent = hunterHudRoot

do
	local rightTick = Instance.new("Frame")
	rightTick.Name = "ObjectiveTick"
	rightTick.AnchorPoint = Vector2.new(1, 0)
	rightTick.Position = UDim2.new(1, 0, 0, 2)
	rightTick.Size = UDim2.fromOffset(1, 44)
	rightTick.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
	rightTick.BackgroundTransparency = 0.35
	rightTick.BorderSizePixel = 0
	rightTick.ZIndex = 11
	rightTick.Parent = objectivePanel
end

AEM_UIKit.makeMonoLabel({
	name = "ObjHeader",
	parent = objectivePanel,
	size = UDim2.new(1, -10, 0, 16),
	position = UDim2.fromOffset(0, 0),
	text = "OBJECTIVE //",
	color = AEM_UIKit.AMBER_SOFT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.SemiBold,
	alignX = Enum.TextXAlignment.Right,
	textSize = 14,
	zIndex = 11,
})
local objectiveLine1 = AEM_UIKit.makeMonoLabel({
	name = "ObjLine1",
	parent = objectivePanel,
	size = UDim2.new(1, -10, 0, 24),
	position = UDim2.fromOffset(0, 18),
	text = "PURGE SPECIMEN",
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	alignX = Enum.TextXAlignment.Right,
	textSize = 21,
	zIndex = 11,
})
local objectiveLine2 = AEM_UIKit.makeMonoLabel({
	name = "ObjLine2",
	parent = objectivePanel,
	size = UDim2.new(1, -10, 0, 16),
	position = UDim2.fromOffset(0, 44),
	text = "STAGE I · MUTATION",
	color = AEM_UIKit.AMBER_WIRE,
	weight = Enum.FontWeight.Medium,
	alignX = Enum.TextXAlignment.Right,
	textSize = 12,
	zIndex = 11,
})

-- Mira Dinâmica Central Limpa
local crosshairRoot = Instance.new("Frame")
crosshairRoot.Name = "DynamicCrosshair"
crosshairRoot.AnchorPoint = Vector2.new(0.5, 0.5)
crosshairRoot.Position = UDim2.fromScale(0.5, 0.5)
crosshairRoot.Size = UDim2.fromOffset(56, 56)
crosshairRoot.BackgroundTransparency = 1
crosshairRoot.ZIndex = 9
crosshairRoot.Parent = hunterHudRoot

do
	local crossCenter = Instance.new("Frame")
	crossCenter.AnchorPoint = Vector2.new(0.5, 0.5)
	crossCenter.Position = UDim2.fromScale(0.5, 0.5)
	crossCenter.Size = UDim2.fromOffset(2, 2)
	crossCenter.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
	crossCenter.BorderSizePixel = 0
	crossCenter.Parent = crosshairRoot
end

local crossTicks: { Frame } = {}
local crosshairTicks: { top: Frame, bot: Frame, left: Frame, right: Frame }
do
	local function makeTick(size: UDim2): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.BackgroundColor3 = AEM_UIKit.IVORY_TEXT
		f.BackgroundTransparency = 0.15
		f.BorderSizePixel = 0
		f.Parent = crosshairRoot
		table.insert(crossTicks, f)
		return f
	end
	crosshairTicks = {
		top = makeTick(UDim2.fromOffset(1, 6)),
		bot = makeTick(UDim2.fromOffset(1, 6)),
		left = makeTick(UDim2.fromOffset(6, 1)),
		right = makeTick(UDim2.fromOffset(6, 1)),
	}
end

-- F6: Canto Inferior Esquerdo — Telemetria do Esquadrão (Borderless acima dos vitais)
local squadContainer = Instance.new("Frame")
squadContainer.Name = "SquadSidebar"
squadContainer.AnchorPoint = Vector2.new(0, 1)
squadContainer.Position = UDim2.new(0, 36, 1, -132)
squadContainer.Size = UDim2.fromOffset(244, 112)
squadContainer.BackgroundTransparency = 1
squadContainer.BorderSizePixel = 0
squadContainer.ZIndex = 10
squadContainer.Parent = hunterHudRoot

do
	local squadLeftRule = Instance.new("Frame")
	squadLeftRule.Name = "SquadHairline"
	squadLeftRule.Position = UDim2.fromOffset(0, 2)
	squadLeftRule.Size = UDim2.new(0, 1, 1, -6)
	squadLeftRule.BackgroundColor3 = AEM_UIKit.HAIRLINE_DIM
	squadLeftRule.BackgroundTransparency = 0.45
	squadLeftRule.BorderSizePixel = 0
	squadLeftRule.ZIndex = 11
	squadLeftRule.Parent = squadContainer
end

AEM_UIKit.makeMonoLabel({
	name = "SquadHeader",
	parent = squadContainer,
	size = UDim2.fromOffset(220, 14),
	position = UDim2.fromOffset(8, 0),
	text = "SQUAD",
	color = AEM_UIKit.AMBER_SOFT,
	textSize = 11,
	zIndex = 11,
})

type SquadRowUI = {
	rowFrame: Frame,
	pip: Frame,
	rowLabel: TextLabel,
	hpBar: AEM_UIKit.SegmentedBarHandle,
	pctLabel: TextLabel,
	downedBadge: TextLabel,
	assignedPlayer: Player?,
	isDownedActive: boolean,
	isContaminated: boolean,
	rawTag: string,
	rawName: string,
	rawPct: number,
	isDead: boolean,
}

local squadRows: { SquadRowUI } = {}
for idx = 1, 4 do
	local row = Instance.new("Frame")
	row.Name = "SquadRow_" .. tostring(idx)
	row.Size = UDim2.fromOffset(232, 21)
	row.Position = UDim2.fromOffset(8, 17 + (idx - 1) * 23)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Visible = false
	row.ZIndex = 11
	row.Parent = squadContainer

	local pip = Instance.new("Frame")
	pip.Name = "RolePip"
	pip.Size = UDim2.fromOffset(2, 13)
	pip.Position = UDim2.fromOffset(0, 2)
	pip.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
	pip.BorderSizePixel = 0
	pip.ZIndex = 12
	pip.Parent = row

	local rowLabel = AEM_UIKit.makeMonoLabel({
		name = "TelemetryLine",
		parent = row,
		size = UDim2.fromOffset(152, 14),
		position = UDim2.fromOffset(6, 0),
		text = "AST · Operator",
		color = AEM_UIKit.IVORY_TEXT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.SemiBold,
		truncate = true,
		textSize = 12,
		zIndex = 12,
	})

	local pctLabel = AEM_UIKit.makeMonoLabel({
		name = "PctReadout",
		parent = row,
		size = UDim2.fromOffset(68, 14),
		position = UDim2.fromOffset(164, 0),
		text = "100%",
		color = AEM_UIKit.IVORY_TEXT,
		alignX = Enum.TextXAlignment.Right,
		textSize = 11,
		zIndex = 12,
	})

	local downedBadge = AEM_UIKit.makeMonoLabel({
		name = "DownedFlag",
		parent = row,
		size = UDim2.fromOffset(72, 14),
		position = UDim2.fromOffset(160, 0),
		text = "DOWN",
		color = AEM_UIKit.BOSS_CRIMSON,
		alignX = Enum.TextXAlignment.Right,
		textSize = 11,
		zIndex = 13,
	})
	downedBadge.Visible = false

	local hpBar = AEM_UIKit.createSlimBar({
		name = "SquadHPBar",
		parent = row,
		size = UDim2.fromOffset(226, 2),
		position = UDim2.fromOffset(6, 17),
		fillColor = AEM_UIKit.IVORY_TEXT,
		trackTransparency = 0.82,
		zIndex = 12,
	})

	table.insert(squadRows, {
		rowFrame = row,
		pip = pip,
		rowLabel = rowLabel,
		hpBar = hpBar,
		pctLabel = pctLabel,
		downedBadge = downedBadge,
		assignedPlayer = nil,
		isDownedActive = false,
		isContaminated = false,
		rawTag = "AST",
		rawName = "Operator",
		rawPct = 100,
		isDead = false,
	})
end

-- F6: Canto Inferior Esquerdo — Medidores Inclinados HP & SHIELD + Micro-Telemetria JPK/BPM
local vitalsBracket = AEM_UIKit.createWireBracketFrame(hunterHudRoot, {
	name = "VitalsBracketContainer",
	parent = hunterHudRoot,
	anchorPoint = Vector2.new(0, 1),
	position = UDim2.new(0, 36, 1, -28),
	size = UDim2.fromOffset(276, 92),
	bgTransparency = 1,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.4,
	bracketLength = 10,
	mode = "LeftSlanted",
	slantDeg = -7,
	glow = true,
	zIndex = 10,
})

local hunterHpGauge = AEM_UIKit.createSlantedGauge(vitalsBracket, {
	name = "HPGauge",
	parent = vitalsBracket,
	position = UDim2.fromOffset(10, 4),
	size = UDim2.fromOffset(258, 28),
	labelLeftText = "HP",
	labelRightText = "100%",
	fillColor = AEM_UIKit.IVORY_TEXT,
	glowColor = AEM_UIKit.AMBER_WIRE,
	barHeight = 5,
	slantDeg = -2.2,
	zIndex = 11,
})

local hunterShdGauge = AEM_UIKit.createSlantedGauge(vitalsBracket, {
	name = "ShieldGauge",
	parent = vitalsBracket,
	position = UDim2.fromOffset(10, 36),
	size = UDim2.fromOffset(258, 24),
	labelLeftText = "SHIELD",
	labelRightText = "100%",
	fillColor = AEM_UIKit.AMBER_GLOW,
	glowColor = AEM_UIKit.AMBER_WIRE,
	barHeight = 3,
	slantDeg = -2.2,
	zIndex = 11,
})

local jpkSegBar = AEM_UIKit.createSlimBar({
	name = "JPKMicroBar",
	parent = vitalsBracket,
	size = UDim2.fromOffset(110, 2),
	position = UDim2.fromOffset(12, 74),
	fillColor = AEM_UIKit.AMBER_WIRE,
	trackTransparency = 0.80,
	zIndex = 11,
})

local hunterJpkAsciiLbl = AEM_UIKit.makeMonoLabel({
	name = "JPKMicroLabel",
	parent = vitalsBracket,
	size = UDim2.fromOffset(72, 14),
	position = UDim2.fromOffset(128, 67),
	text = "JPK 100%",
	color = AEM_UIKit.AMBER_SOFT,
	textSize = 11,
	zIndex = 11,
})

local hunterBpmLbl = AEM_UIKit.makeMonoLabel({
	name = "BPMMonitor",
	parent = vitalsBracket,
	size = UDim2.fromOffset(72, 14),
	position = UDim2.fromOffset(196, 67),
	text = "82 BPM",
	color = AEM_UIKit.AMBER_SOFT,
	alignX = Enum.TextXAlignment.Right,
	textSize = 11,
	zIndex = 11,
})

-- F7: Centro-Baixo — Linha Única Borderless CLASS // AMMO
local classAmmoLabel = AEM_UIKit.makeMonoLabel({
	name = "ClassAmmoLabel",
	parent = hunterHudRoot,
	size = UDim2.fromOffset(500, 26),
	position = UDim2.new(0.5, 0, 1, -24),
	text = "CLASS: TRACKER // HOLSTERED",
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	alignX = Enum.TextXAlignment.Center,
	textSize = 18,
	strokeTransparency = 0.80,
	zIndex = 11,
})
classAmmoLabel.AnchorPoint = Vector2.new(0.5, 1)

-- F8: Canto Inferior Direito — Bandeja Angular de 3 Ícones Chamfrados ([Q] / [G] / [F])
local abilityTrayRoot = Instance.new("Frame")
abilityTrayRoot.Name = "AbilityTrayRoot"
abilityTrayRoot.AnchorPoint = Vector2.new(1, 1)
abilityTrayRoot.Position = UDim2.new(1, -28, 1, -22)
abilityTrayRoot.Size = UDim2.fromOffset(308, 108)
abilityTrayRoot.BackgroundTransparency = 1
abilityTrayRoot.BorderSizePixel = 0
abilityTrayRoot.ClipsDescendants = false
abilityTrayRoot.ZIndex = 10
abilityTrayRoot.Parent = hunterHudRoot

local onSecondarySkillActivated: (() -> ())? = nil
local onClassSkillActivated: (() -> ())? = nil
local onDomeActivated: (() -> ())? = nil

local secondaryBadge = AEM_UIKit.createChamferedAbilityBadge(abilityTrayRoot, {
	name = "SecondaryBadge",
	parent = abilityTrayRoot,
	position = UDim2.fromOffset(0, 10),
	sizePx = 56,
	glyph = "harpoon",
	label = "HARPOON",
	keybind = "Q",
	clickable = true,
	onActivated = function()
		if onSecondarySkillActivated ~= nil then
			onSecondarySkillActivated()
		end
	end,
	zIndex = 12,
})

local scannerBadge = AEM_UIKit.createChamferedAbilityBadge(abilityTrayRoot, {
	name = "ScannerBadge",
	parent = abilityTrayRoot,
	position = UDim2.fromOffset(100, 5),
	sizePx = 56,
	glyph = "scanner",
	label = "SCANNER",
	keybind = "G",
	clickable = true,
	onActivated = function()
		if onClassSkillActivated ~= nil then
			onClassSkillActivated()
		end
	end,
	zIndex = 12,
})

local domeBadge = AEM_UIKit.createChamferedAbilityBadge(abilityTrayRoot, {
	name = "DomeBadge",
	parent = abilityTrayRoot,
	position = UDim2.fromOffset(200, 0),
	sizePx = 56,
	glyph = "dome",
	label = "DOME STAGE",
	keybind = "F",
	clickable = true,
	onActivated = function()
		if onDomeActivated ~= nil then
			onDomeActivated()
		end
	end,
	zIndex = 12,
})

local cachedBadgeSkillIds: { [string]: string } = {
	Secondary = "",
	Class = "",
}

-- F9: Radar Acústico Wireframe Retrátil ([R]) acima da Bandeja de Habilidades
type AcousticContactEntry = {
	worldPos: Vector3,
	color: Color3,
	createdAt: number,
	expiresAt: number,
}

local Radar: {
	togglePill: TextButton,
	emitWave: (worldOrigin: Vector3, waveColor: Color3?) -> (),
	refreshPill: (nowClock: number) -> (),
	setOpen: (open: boolean, instant: boolean?) -> (),
	toggle: () -> (),
	clearContacts: () -> (),
	updateFrame: (dt: number, now: number, look: Vector3, rootPos: Vector3?) -> (),
}
do
	local radarTogglePill = Instance.new("TextButton")
	radarTogglePill.Name = "RadarTogglePill"
	radarTogglePill.AnchorPoint = Vector2.new(1, 1)
	radarTogglePill.Position = UDim2.new(1, -28, 1, -142)
	radarTogglePill.Size = UDim2.fromOffset(220, 26)
	radarTogglePill.BackgroundTransparency = 1
	radarTogglePill.BorderSizePixel = 0
	radarTogglePill.AutoButtonColor = false
	radarTogglePill.Text = ""
	radarTogglePill.ZIndex = 11
	radarTogglePill.Parent = hunterHudRoot

	local radarPillWire = AEM_UIKit.createWireBracketFrame(radarTogglePill, {
		name = "RadarPillWire",
		parent = radarTogglePill,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		bgColor = AEM_UIKit.VOID_GLASS,
		bgTransparency = 0.88,
		bracketColor = AEM_UIKit.AMBER_WIRE,
		bracketThickness = 1.2,
		bracketLength = 8,
		mode = "Corners",
		glow = true,
		zIndex = 11,
	})

	local radarPillDot = Instance.new("Frame")
	radarPillDot.Name = "RadarStatusDot"
	radarPillDot.AnchorPoint = Vector2.new(0, 0.5)
	radarPillDot.Position = UDim2.new(0, 12, 0.5, 0)
	radarPillDot.Size = UDim2.fromOffset(6, 6)
	radarPillDot.Rotation = 45
	radarPillDot.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
	radarPillDot.BorderSizePixel = 0
	radarPillDot.ZIndex = 13
	radarPillDot.Parent = radarTogglePill

	local radarAlertLabel = AEM_UIKit.makeMonoLabel({
		name = "RadarCalmState",
		parent = radarTogglePill,
		size = UDim2.fromScale(0.66, 0.88),
		position = UDim2.new(0, 25, 0.06, 0),
		text = "RADAR · STANDBY",
		color = AEM_UIKit.AMBER_SOFT,
		textSize = 12,
		zIndex = 13,
	})

	AEM_UIKit.makeMonoLabel({
		name = "RadarKeyBadge",
		parent = radarTogglePill,
		size = UDim2.fromScale(0.20, 0.88),
		position = UDim2.fromScale(0.75, 0.06),
		text = "[R]",
		color = AEM_UIKit.AMBER_WIRE,
		alignX = Enum.TextXAlignment.Right,
		textSize = 13,
		zIndex = 13,
	})

	-- Gaveta Animada do Radar Acústico (Frame vetorial com clipping + escopo circular drawArcPx)
	local acousticRadarPanel = Instance.new("Frame")
	acousticRadarPanel.Name = "AcousticRadarPanel"
	acousticRadarPanel.AnchorPoint = Vector2.new(1, 1)
	acousticRadarPanel.Position = UDim2.new(1, -28, 1, -176)
	acousticRadarPanel.Size = UDim2.fromOffset(244, 0)
	acousticRadarPanel.BackgroundTransparency = 1
	acousticRadarPanel.BorderSizePixel = 0
	acousticRadarPanel.ClipsDescendants = true
	acousticRadarPanel.Visible = false
	acousticRadarPanel.ZIndex = 12
	acousticRadarPanel.Parent = hunterHudRoot

	local radarBody = Instance.new("Frame")
	radarBody.Name = "RadarBody"
	radarBody.AnchorPoint = Vector2.new(0.5, 1)
	radarBody.Position = UDim2.fromScale(0.5, 1)
	radarBody.Size = UDim2.fromOffset(244, 244)
	radarBody.BackgroundTransparency = 1
	radarBody.BorderSizePixel = 0
	radarBody.Visible = false
	radarBody.ZIndex = 12
	radarBody.Parent = acousticRadarPanel

	AEM_UIKit.makeMonoLabel({
		name = "RadarScopeTitle",
		parent = radarBody,
		size = UDim2.fromOffset(156, 18),
		position = UDim2.fromOffset(8, 4),
		text = "ACOUSTIC RADAR",
		color = AEM_UIKit.AMBER_GLOW,
		textSize = 12,
		zIndex = 13,
	})

	AEM_UIKit.makeMonoLabel({
		name = "RadarRangeTag",
		parent = radarBody,
		size = UDim2.fromOffset(64, 18),
		position = UDim2.fromOffset(172, 4),
		text = "220m",
		color = AEM_UIKit.AMBER_SOFT,
		alignX = Enum.TextXAlignment.Right,
		textSize = 12,
		zIndex = 13,
	})

	local radarScope = Instance.new("Frame")
	radarScope.Name = "AcousticScopeCircle"
	radarScope.AnchorPoint = Vector2.new(0.5, 0.5)
	radarScope.Position = UDim2.fromOffset(122, 134)
	radarScope.Size = UDim2.fromOffset(196, 196)
	radarScope.BackgroundTransparency = 1
	radarScope.BorderSizePixel = 0
	radarScope.ClipsDescendants = true
	radarScope.ZIndex = 13
	radarScope.Parent = radarBody

	local radarScopeScale = Instance.new("UIScale")
	radarScopeScale.Name = "RadarScopeScale"
	radarScopeScale.Scale = 0.86
	radarScopeScale.Parent = radarScope

	local radarScopeRingSegs = AEM_UIKit.drawArcPx(radarScope, "AcousticScopeRing", Vector2.new(98, 98), 96, 0, 360, 48, 1.4, AEM_UIKit.AMBER_WIRE, 0.18, 13, true)

	for _, ringScale in ipairs({ 0.66, 0.34 }) do
		AEM_UIKit.drawArcPx(
			radarScope,
			"RangeRing_" .. tostring(math.floor(ringScale * 100)),
			Vector2.new(98, 98),
			96 * ringScale,
			0,
			360,
			if ringScale > 0.5 then 40 else 28,
			1,
			AEM_UIKit.AMBER_WIRE,
			0.58,
			13,
			false
		)
	end

	do
		local scopeCrossH = Instance.new("Frame")
		scopeCrossH.AnchorPoint = Vector2.new(0.5, 0.5)
		scopeCrossH.Size = UDim2.fromOffset(192, 1)
		scopeCrossH.Position = UDim2.fromScale(0.5, 0.5)
		scopeCrossH.BackgroundColor3 = AEM_UIKit.HAIRLINE_DIM
		scopeCrossH.BackgroundTransparency = 0.55
		scopeCrossH.BorderSizePixel = 0
		scopeCrossH.ZIndex = 13
		scopeCrossH.Parent = radarScope

		local scopeCrossV = Instance.new("Frame")
		scopeCrossV.AnchorPoint = Vector2.new(0.5, 0.5)
		scopeCrossV.Size = UDim2.fromOffset(1, 192)
		scopeCrossV.Position = UDim2.fromScale(0.5, 0.5)
		scopeCrossV.BackgroundColor3 = AEM_UIKit.HAIRLINE_DIM
		scopeCrossV.BackgroundTransparency = 0.55
		scopeCrossV.BorderSizePixel = 0
		scopeCrossV.ZIndex = 13
		scopeCrossV.Parent = radarScope
	end

	local radarSweepPivot = Instance.new("Frame")
	radarSweepPivot.Name = "SweepPivot"
	radarSweepPivot.AnchorPoint = Vector2.new(0.5, 0.5)
	radarSweepPivot.Position = UDim2.fromScale(0.5, 0.5)
	radarSweepPivot.Size = UDim2.fromScale(1, 1)
	radarSweepPivot.BackgroundTransparency = 1
	radarSweepPivot.ZIndex = 14
	radarSweepPivot.Parent = radarScope

	do
		for rayIdx, raySpec in ipairs({
			{ angle = -7, alpha = 0.45 },
			{ angle = -14, alpha = 0.68 },
			{ angle = -21, alpha = 0.85 },
		}) do
			local rayHolder = Instance.new("Frame")
			rayHolder.Name = "SweepTrailHolder_" .. tostring(rayIdx)
			rayHolder.AnchorPoint = Vector2.new(0.5, 0.5)
			rayHolder.Position = UDim2.fromScale(0.5, 0.5)
			rayHolder.Size = UDim2.fromScale(1, 1)
			rayHolder.Rotation = raySpec.angle
			rayHolder.BackgroundTransparency = 1
			rayHolder.ZIndex = 14
			rayHolder.Parent = radarSweepPivot

			local ray = Instance.new("Frame")
			ray.Name = "SweepTrailRay_" .. tostring(rayIdx)
			ray.AnchorPoint = Vector2.new(0.5, 1)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.new(0, 2, 0.46, 0)
			ray.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
			ray.BackgroundTransparency = raySpec.alpha
			ray.BorderSizePixel = 0
			ray.ZIndex = 14
			ray.Parent = rayHolder
		end

		local radarSweepLine = Instance.new("Frame")
		radarSweepLine.Name = "SweepLine"
		radarSweepLine.AnchorPoint = Vector2.new(0.5, 1)
		radarSweepLine.Position = UDim2.fromScale(0.5, 0.5)
		radarSweepLine.Size = UDim2.new(0, 2, 0.47, 0)
		radarSweepLine.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
		radarSweepLine.BackgroundTransparency = 0.12
		radarSweepLine.BorderSizePixel = 0
		radarSweepLine.ZIndex = 14
		radarSweepLine.Parent = radarSweepPivot

		local sweepLineGrad = Instance.new("UIGradient")
		sweepLineGrad.Rotation = 90
		sweepLineGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 0.85),
		})
		sweepLineGrad.Parent = radarSweepLine
	end

	local radarNorthPip = AEM_UIKit.makeMonoLabel({
		name = "NorthMarker",
		parent = radarScope,
		size = UDim2.fromOffset(18, 18),
		position = UDim2.fromScale(0.5, 0.09),
		text = "N",
		color = AEM_UIKit.AMBER_WIRE,
		alignX = Enum.TextXAlignment.Center,
		textSize = 13,
		zIndex = 15,
	})
	radarNorthPip.AnchorPoint = Vector2.new(0.5, 0.5)

	local radarAllyPips: { Frame } = {}
	for pIdx = 1, 4 do
		local pip = Instance.new("Frame")
		pip.Name = "AllyPip_" .. tostring(pIdx)
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Size = UDim2.fromOffset(5, 5)
		pip.Rotation = 45
		pip.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
		pip.BorderSizePixel = 0
		pip.Visible = false
		pip.ZIndex = 15
		pip.Parent = radarScope
		table.insert(radarAllyPips, pip)
	end

	local activeAcousticContacts: { AcousticContactEntry } = {}
	local radarContactPips: { Frame } = {}
	for cIdx = 1, 6 do
		local cPip = Instance.new("Frame")
		cPip.Name = "AcousticContactPip_" .. tostring(cIdx)
		cPip.AnchorPoint = Vector2.new(0.5, 0.5)
		cPip.Size = UDim2.fromOffset(6, 6)
		cPip.Rotation = 45
		cPip.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
		cPip.BorderSizePixel = 0
		cPip.Visible = false
		cPip.ZIndex = 16
		cPip.Parent = radarScope
		AEM_UIKit.applyBevelStroke(cPip, AEM_UIKit.VOID_GLASS, 1, 0.25, Enum.LineJoinMode.Miter)
		table.insert(radarContactPips, cPip)
	end

	do
		local scopeDot = Instance.new("Frame")
		scopeDot.Name = "ScopeCenterDot"
		scopeDot.AnchorPoint = Vector2.new(0.5, 0.5)
		scopeDot.Position = UDim2.fromScale(0.5, 0.5)
		scopeDot.Size = UDim2.fromOffset(5, 5)
		scopeDot.Rotation = 45
		scopeDot.BackgroundColor3 = AEM_UIKit.IVORY_TEXT
		scopeDot.BorderSizePixel = 0
		scopeDot.ZIndex = 17
		scopeDot.Parent = radarScope
	end

	local acousticWaveCount = 0
	local lastAcousticSpikeAt = 0
	local lastSpikeWorldPos: Vector3? = nil
	local lastSpikeColor: Color3 = AEM_UIKit.AMBER_WIRE
	local lastSpikeDistance: number? = nil

	local isRadarOpen = false
	local radarAnimToken = 0
	local radarSizeTween: Tween? = nil
	local radarScaleTween: Tween? = nil
	local radarSweepAngle = 0

	local function setRadarScopeRingColor(col: Color3): ()
		for _, seg in ipairs(radarScopeRingSegs) do
			seg.BackgroundColor3 = col
		end
	end

	local function refreshRadarPillVisuals(nowClock: number): ()
		local hasSpike = (nowClock - lastAcousticSpikeAt) < 4.5
		if hasSpike then
			local distLabel = if lastSpikeDistance ~= nil then string.format(" · %dm", lastSpikeDistance :: number) else ""
			radarAlertLabel.Text = "SPIKE" .. distLabel
			radarAlertLabel.TextColor3 = AEM_UIKit.AMBER_GLOW
			radarPillDot.BackgroundColor3 = AEM_UIKit.BOSS_CRIMSON
			setWireBracketColor(radarPillWire, AEM_UIKit.AMBER_GLOW)
			setRadarScopeRingColor(AEM_UIKit.AMBER_GLOW)
		elseif isRadarOpen then
			radarAlertLabel.Text = "RADAR · ACTIVE"
			radarAlertLabel.TextColor3 = AEM_UIKit.IVORY_TEXT
			radarPillDot.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
			setWireBracketColor(radarPillWire, AEM_UIKit.AMBER_WIRE)
			setRadarScopeRingColor(AEM_UIKit.AMBER_WIRE)
		else
			radarAlertLabel.Text = "RADAR · STANDBY"
			radarAlertLabel.TextColor3 = AEM_UIKit.AMBER_SOFT
			radarPillDot.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
			setWireBracketColor(radarPillWire, AEM_UIKit.AMBER_WIRE)
			setRadarScopeRingColor(AEM_UIKit.AMBER_WIRE)
		end
	end

	local function spawnAcousticRing(worldOrigin: Vector3, chosenColor: Color3): ()
		if not isRadarOpen or not acousticRadarPanel.Visible then
			return
		end
		if acousticWaveCount >= 8 then
			return
		end

		local cam = Workspace.CurrentCamera
		local localChar = LocalPlayer.Character
		local localRoot = if localChar ~= nil then localChar:FindFirstChild("HumanoidRootPart") else nil
		if cam == nil or localRoot == nil or not localRoot:IsA("BasePart") then
			return
		end

		local delta = worldOrigin - (localRoot :: BasePart).Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local dist = flat.Magnitude
		local normDist = math.clamp(dist / CONFIG.RadarRangeStuds, 0.05, 0.88)
		local look = cam.CFrame.LookVector
		local fwd = Vector3.new(look.X, 0, look.Z)
		local relX, relY = 0, -normDist * 0.43
		if fwd.Magnitude > 0.001 and dist > 0.1 then
			fwd = fwd.Unit
			local right = Vector3.new(-fwd.Z, 0, fwd.X)
			local dir = flat.Unit
			relX = dir:Dot(right) * normDist * 0.43
			relY = -dir:Dot(fwd) * normDist * 0.43
		end

		acousticWaveCount += 1

		local ring = Instance.new("Frame")
		ring.Name = "AcousticPingRing"
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5 + relX, 0.5 + relY)
		ring.Size = UDim2.fromOffset(52, 52)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.ZIndex = 15
		ring.Parent = radarScope

		local ringScale = Instance.new("UIScale")
		ringScale.Name = "PingRingScale"
		ringScale.Scale = 8 / 52
		ringScale.Parent = ring

		local ringSegs = AEM_UIKit.drawArcPx(ring, "PingArc", Vector2.new(26, 26), 25, 0, 360, 24, 1.4, chosenColor, 0.08, 15, false)

		local tw = TweenService:Create(ringScale, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		local fadeInfo = TweenInfo.new(0.85, Enum.EasingStyle.Linear)
		for _, seg in ipairs(ringSegs) do
			TweenService:Create(seg, fadeInfo, {
				BackgroundTransparency = 1,
			}):Play()
		end
		tw:Play()
		tw.Completed:Once(function()
			acousticWaveCount = math.max(0, acousticWaveCount - 1)
			if ring.Parent ~= nil then
				ring:Destroy()
			end
		end)
	end

	local function emitAcousticWave(worldOrigin: Vector3, waveColor: Color3?): ()
		local chosenColor = waveColor or AEM_UIKit.AMBER_WIRE
		local now = os.clock()
		lastAcousticSpikeAt = now
		lastSpikeWorldPos = worldOrigin
		lastSpikeColor = chosenColor

		local cam = Workspace.CurrentCamera
		local localChar = LocalPlayer.Character
		local localRoot = if localChar ~= nil then localChar:FindFirstChild("HumanoidRootPart") else nil
		if cam == nil or localRoot == nil or not localRoot:IsA("BasePart") then
			return
		end

		local delta = worldOrigin - (localRoot :: BasePart).Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local dist = flat.Magnitude
		lastSpikeDistance = math.floor(dist + 0.5)
		refreshRadarPillVisuals(now)

		local updated = false
		for _, entry in ipairs(activeAcousticContacts) do
			if (entry.worldPos - worldOrigin).Magnitude < 18 and (now - entry.createdAt) < 0.7 then
				entry.worldPos = worldOrigin
				entry.color = chosenColor
				entry.expiresAt = now + 4.5
				updated = true
				break
			end
		end
		if not updated then
			if #activeAcousticContacts >= 6 then
				table.remove(activeAcousticContacts, 1)
			end
			table.insert(activeAcousticContacts, {
				worldPos = worldOrigin,
				color = chosenColor,
				createdAt = now,
				expiresAt = now + 4.5,
			})
		end

		spawnAcousticRing(worldOrigin, chosenColor)
	end

	local function setRadarOpen(open: boolean, instant: boolean?): ()
		if isRadarOpen == open and not instant then
			return
		end
		isRadarOpen = open
		radarAnimToken += 1
		local myToken = radarAnimToken

		if radarSizeTween ~= nil then
			radarSizeTween:Cancel()
			radarSizeTween = nil
		end
		if radarScaleTween ~= nil then
			radarScaleTween:Cancel()
			radarScaleTween = nil
		end

		refreshRadarPillVisuals(os.clock())

		if instant == true then
			acousticRadarPanel.Size = UDim2.fromOffset(244, if open then 244 else 0)
			acousticRadarPanel.Visible = open
			radarBody.Visible = open
			radarScopeScale.Scale = if open then 1 else 0.86
			return
		end

		if open then
			acousticRadarPanel.Visible = true
			radarBody.Visible = true
			acousticRadarPanel.Size = UDim2.fromOffset(244, 0)
			radarScopeScale.Scale = 0.86
			radarSweepAngle = 0
			radarSweepPivot.Rotation = 0
			playOneShotAlert(AUDIO_IDS.CRTBeep, 1.32, 0.22)

			local openSizeTw = TweenService:Create(acousticRadarPanel, CONFIG.RadarOpenTween, {
				Size = UDim2.fromOffset(244, 244),
			})
			local openScaleTw = TweenService:Create(radarScopeScale, CONFIG.RadarOpenTween, {
				Scale = 1,
			})
			radarSizeTween = openSizeTw
			radarScaleTween = openScaleTw
			openSizeTw:Play()
			openScaleTw:Play()

			if lastSpikeWorldPos ~= nil and (os.clock() - lastAcousticSpikeAt) <= 4.0 then
				spawnAcousticRing(lastSpikeWorldPos, lastSpikeColor)
			end
		else
			playOneShotAlert(AUDIO_IDS.CRTBeep, 0.92, 0.18)
			local closeSizeTw = TweenService:Create(acousticRadarPanel, CONFIG.RadarCloseTween, {
				Size = UDim2.fromOffset(244, 0),
			})
			local closeScaleTw = TweenService:Create(radarScopeScale, CONFIG.RadarCloseTween, {
				Scale = 0.86,
			})
			radarSizeTween = closeSizeTw
			radarScaleTween = closeScaleTw
			closeScaleTw:Play()
			closeSizeTw.Completed:Once(function()
				if myToken == radarAnimToken and not isRadarOpen then
					acousticRadarPanel.Visible = false
					radarBody.Visible = false
				end
			end)
			closeSizeTw:Play()
		end
	end

	Radar = {
		togglePill = radarTogglePill,
		emitWave = emitAcousticWave,
		refreshPill = refreshRadarPillVisuals,
		setOpen = setRadarOpen,
		toggle = function()
			if not hunterHudRoot.Visible then
				return
			end
			setRadarOpen(not isRadarOpen, false)
		end,
		clearContacts = function()
			lastSpikeWorldPos = nil
			lastSpikeDistance = nil
			table.clear(activeAcousticContacts)
			for _, cPip in ipairs(radarContactPips) do
				cPip.Visible = false
			end
			setRadarOpen(false, true)
		end,
		updateFrame = function(dt: number, now: number, look: Vector3, myPos: Vector3?)
			if not (isRadarOpen and acousticRadarPanel.Visible) then
				return
			end
			radarSweepAngle = (radarSweepAngle + dt * 165) % 360
			radarSweepPivot.Rotation = radarSweepAngle

			local fwd = Vector3.new(look.X, 0, look.Z)
			if fwd.Magnitude <= 0.001 then
				return
			end
			fwd = fwd.Unit
			local right = Vector3.new(-fwd.Z, 0, fwd.X)
			local northRelX = Vector3.new(0, 0, -1):Dot(right)
			local northRelY = -Vector3.new(0, 0, -1):Dot(fwd)
			radarNorthPip.Position = UDim2.fromScale(0.5 + northRelX * 0.42, 0.5 + northRelY * 0.42)

			local pipIdx = 0
			if myPos ~= nil then
				for _, slot in ipairs(squadRows) do
					local ally = slot.assignedPlayer
					if ally ~= nil and ally ~= LocalPlayer and not slot.isDead and ally.Character ~= nil then
						local allyRoot = ally.Character:FindFirstChild("HumanoidRootPart")
						if allyRoot ~= nil and allyRoot:IsA("BasePart") then
							pipIdx += 1
							if pipIdx <= #radarAllyPips then
								local pip = radarAllyPips[pipIdx]
								local dVec = (allyRoot :: BasePart).Position - myPos
								local flat = Vector3.new(dVec.X, 0, dVec.Z)
								local dist = flat.Magnitude
								local norm = math.clamp(dist / CONFIG.RadarRangeStuds, 0.04, 0.88)
								local rx, ry = 0, 0
								if dist > 0.1 then
									local dir = flat.Unit
									rx = dir:Dot(right) * norm * 0.43
									ry = -dir:Dot(fwd) * norm * 0.43
								end
								pip.Position = UDim2.fromScale(0.5 + rx, 0.5 + ry)
								pip.BackgroundColor3 = if slot.isDownedActive then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.AMBER_GLOW
								pip.Visible = true
							end
						end
					end
				end

				local contactIdx = 0
				for idx = #activeAcousticContacts, 1, -1 do
					local entry = activeAcousticContacts[idx]
					if now >= entry.expiresAt then
						table.remove(activeAcousticContacts, idx)
					end
				end
				for _, entry in ipairs(activeAcousticContacts) do
					contactIdx += 1
					if contactIdx <= #radarContactPips then
						local cPip = radarContactPips[contactIdx]
						local dVec = entry.worldPos - myPos
						local flat = Vector3.new(dVec.X, 0, dVec.Z)
						local dist = flat.Magnitude
						local norm = math.clamp(dist / CONFIG.RadarRangeStuds, 0.05, 0.88)
						local rx, ry = 0, -norm * 0.43
						if dist > 0.1 then
							local dir = flat.Unit
							rx = dir:Dot(right) * norm * 0.43
							ry = -dir:Dot(fwd) * norm * 0.43
						end
						local lifeFrac = math.clamp((entry.expiresAt - now) / 4.5, 0, 1)
						cPip.Position = UDim2.fromScale(0.5 + rx, 0.5 + ry)
						cPip.BackgroundColor3 = entry.color
						cPip.BackgroundTransparency = 1 - lifeFrac
						cPip.Visible = true
					end
				end
				for j = contactIdx + 1, #radarContactPips do
					radarContactPips[j].Visible = false
				end
			end
			for j = pipIdx + 1, #radarAllyPips do
				radarAllyPips[j].Visible = false
			end
		end,
	}
end

-- ============================================================================
-- 2) HUD DO MONSTRO (F10: KAIROS-09 #FF9000 / CRIMSON WIREFRAME)
-- ============================================================================
local monsterHudRoot = Instance.new("Frame")
monsterHudRoot.Name = "MonsterHUDRoot"
monsterHudRoot.Size = UDim2.fromScale(1, 1)
monsterHudRoot.BackgroundTransparency = 1
monsterHudRoot.Visible = false
monsterHudRoot.ZIndex = 4
monsterHudRoot.Parent = hudCanvas

-- Barra Superior de Biomassa (empilhada abaixo do BossHealthBar no Top-Center)
local monsterTopBar = AEM_UIKit.createWireBracketFrame(monsterHudRoot, {
	name = "MonsterTopBiomassBar",
	parent = monsterHudRoot,
	anchorPoint = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 128),
	size = UDim2.fromOffset(440, 38),
	bgColor = Color3.fromRGB(23,32,35),
	bgTransparency = 0.12,
	bracketColor = Color3.fromRGB(255,194,116),
	bracketThickness = 1.2,
	bracketLength = 10,
	mode = "LeftRight",
	glow = true,
	zIndex = 12,
})
local monsterStageBadge = AEM_UIKit.makeMonoLabel({
	name = "StageBadge",
	parent = monsterTopBar,
	size = UDim2.fromScale(0.31, 0.84),
	position = UDim2.fromScale(0.04, 0.08),
	text = "ESTÁGIO I",
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	textSize = 18,
	zIndex = 13,
})
AEM_UIKit.makeMonoLabel({
	name = "BiomassPrefix",
	parent = monsterTopBar,
	size = UDim2.fromScale(0.27, 0.84),
	position = UDim2.fromScale(0.31, 0.08),
	text = "BIOMASSA",
	color = AEM_UIKit.AMBER_WIRE,
	textSize = 18,
	zIndex = 13,
})
local monsterBioSegBar = AEM_UIKit.createSlimBar({
	name = "BiomassSegBar",
	parent = monsterTopBar,
	size = UDim2.new(0.28, 0, 0, 4),
	position = UDim2.fromScale(0.585, 0.44),
	fillColor = AEM_UIKit.AMBER_GLOW,
	trackTransparency = 0.78,
	notches = 5,
	zIndex = 13,
})
local monsterBiomassText = AEM_UIKit.makeMonoLabel({
	name = "BiomassLabel",
	parent = monsterTopBar,
	size = UDim2.fromScale(0.10, 0.84),
	position = UDim2.fromScale(0.87, 0.08),
	text = "0%",
	color = AEM_UIKit.AMBER_GLOW,
	alignX = Enum.TextXAlignment.Right,
	textSize = 18,
	zIndex = 13,
})

local monsterEvolveBanner = AEM_UIKit.createWireBracketFrame(monsterHudRoot, {
	name = "EvolutionMatrixReadyBanner",
	parent = monsterHudRoot,
	anchorPoint = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 218),
	size = UDim2.fromOffset(440, 32),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.84,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.2,
	bracketLength = 10,
	mode = "LeftRight",
	glow = true,
	zIndex = 15,
})
monsterEvolveBanner.Visible = false
local monsterEvolvePrompt = AEM_UIKit.makeMonoLabel({
	name = "EvolvePromptText",
	parent = monsterEvolveBanner,
	size = UDim2.fromScale(0.94, 0.66),
	position = UDim2.fromScale(0.03, 0.10),
	text = "EVOLUTION MATRIX READY  ·  HOLD [V] IN ISOLATION",
	color = AEM_UIKit.AMBER_GLOW,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	alignX = Enum.TextXAlignment.Center,
	textSize = 13,
	zIndex = 16,
})
local monsterChannelBar = AEM_UIKit.createSlimBar({
	name = "ChannelProgressBar",
	parent = monsterEvolveBanner,
	size = UDim2.fromScale(0.92, 0.10),
	position = UDim2.fromScale(0.04, 0.82),
	fillColor = AEM_UIKit.AMBER_WIRE,
	zIndex = 16,
})
monsterChannelBar.root.Visible = false

-- Retícula Predatória de Garras (Wireframe Diamond Centro + Lâminas)
local clawReticle = Instance.new("Frame")
clawReticle.Name = "PredatoryClawReticle"
clawReticle.AnchorPoint = Vector2.new(0.5, 0.5)
clawReticle.Position = UDim2.fromScale(0.5, 0.5)
clawReticle.Size = UDim2.fromOffset(64, 64)
clawReticle.BackgroundTransparency = 1
clawReticle.ZIndex = 9
clawReticle.Parent = monsterHudRoot

local clawCenterRing = Instance.new("Frame")
clawCenterRing.AnchorPoint = Vector2.new(0.5, 0.5)
clawCenterRing.Position = UDim2.fromScale(0.5, 0.5)
clawCenterRing.Size = UDim2.fromOffset(4, 4)
clawCenterRing.Rotation = 45
clawCenterRing.BackgroundTransparency = 1
clawCenterRing.ZIndex = 10
clawCenterRing.Parent = clawReticle
AEM_UIKit.applyBevelStroke(clawCenterRing, AEM_UIKit.AMBER_WIRE, 1.2, 0.12, Enum.LineJoinMode.Miter)

local clawBlades: { { frame: Frame, dirX: number, dirY: number } } = {}
for _, bSpec in ipairs({
	{ rot = -45, dx = -1, dy = -1 },
	{ rot = 45, dx = 1, dy = -1 },
	{ rot = 45, dx = -1, dy = 1 },
	{ rot = -45, dx = 1, dy = 1 },
}) do
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(11, 1.5)
	f.Rotation = bSpec.rot
	f.BackgroundColor3 = AEM_UIKit.IVORY_TEXT
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.ZIndex = 10
	f.Parent = clawReticle
	table.insert(clawBlades, { frame = f, dirX = bSpec.dx, dirY = bSpec.dy })
end

-- Visão Sensorial Hive Sense (Tags borderless ♥ BPM sobre os 4 Caçadores)
local hiveSenseLayer = Instance.new("Frame")
hiveSenseLayer.Name = "HiveSenseOverlay"
hiveSenseLayer.Size = UDim2.fromScale(1, 1)
hiveSenseLayer.BackgroundTransparency = 1
hiveSenseLayer.ZIndex = 7
hiveSenseLayer.Parent = monsterHudRoot

type HiveMarkerEntry = {
	frame: Frame,
	label: TextLabel,
	topTick: Frame,
	botTick: Frame,
}
local hiveMarkers: { HiveMarkerEntry } = {}
for m = 1, 4 do
	local mkFrame = Instance.new("Frame")
	mkFrame.Name = "HiveHeartMarker_" .. tostring(m)
	mkFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mkFrame.Size = UDim2.fromOffset(76, 22)
	mkFrame.BackgroundTransparency = 1
	mkFrame.BorderSizePixel = 0
	mkFrame.Visible = false
	mkFrame.ZIndex = 8
	mkFrame.Parent = hiveSenseLayer

	local topTick = Instance.new("Frame")
	topTick.AnchorPoint = Vector2.new(0.5, 0)
	topTick.Position = UDim2.fromScale(0.5, 0)
	topTick.Size = UDim2.fromOffset(12, 1)
	topTick.BackgroundColor3 = AEM_UIKit.BOSS_CRIMSON
	topTick.BackgroundTransparency = 0.25
	topTick.BorderSizePixel = 0
	topTick.ZIndex = 8
	topTick.Parent = mkFrame

	local botTick = Instance.new("Frame")
	botTick.AnchorPoint = Vector2.new(0.5, 1)
	botTick.Position = UDim2.fromScale(0.5, 1)
	botTick.Size = UDim2.fromOffset(12, 1)
	botTick.BackgroundColor3 = AEM_UIKit.BOSS_CRIMSON
	botTick.BackgroundTransparency = 0.25
	botTick.BorderSizePixel = 0
	botTick.ZIndex = 8
	botTick.Parent = mkFrame

	local mkLbl = AEM_UIKit.makeMonoLabel({
		name = "BPMTag",
		parent = mkFrame,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		text = "♥ 96",
		color = AEM_UIKit.BOSS_CRIMSON,
		alignX = Enum.TextXAlignment.Center,
		textSize = 14,
		strokeTransparency = 0.78,
		zIndex = 9,
	})

	table.insert(hiveMarkers, {
		frame = mkFrame,
		label = mkLbl,
		topTick = topTick,
		botTick = botTick,
	})
end

-- Alerta de Supressão da Cúpula Estática (Sem borda full-screen!)
local domeSuppressionOverlay = Instance.new("Frame")
domeSuppressionOverlay.Name = "DomeSuppressionOverlay"
domeSuppressionOverlay.Size = UDim2.fromScale(1, 1)
domeSuppressionOverlay.BackgroundTransparency = 1
domeSuppressionOverlay.Visible = false
domeSuppressionOverlay.ZIndex = 18
domeSuppressionOverlay.Parent = monsterHudRoot

local domeWarnBox = AEM_UIKit.createWireBracketFrame(domeSuppressionOverlay, {
	name = "ContainmentInhibitedBox",
	parent = domeSuppressionOverlay,
	anchorPoint = Vector2.new(0.5, 0),
	position = UDim2.new(0.5, 0, 0, 174),
	size = UDim2.fromOffset(400, 28),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.84,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.2,
	bracketLength = 10,
	mode = "LeftRight",
	glow = true,
	zIndex = 19,
})
local domeWarnLabel = AEM_UIKit.makeMonoLabel({
	name = "InhibitWarning",
	parent = domeWarnBox,
	size = UDim2.fromScale(0.96, 0.84),
	position = UDim2.fromScale(0.02, 0.08),
	text = "CONTAINMENT DOME INHIBITED · 60s",
	color = AEM_UIKit.AMBER_GLOW,
	alignX = Enum.TextXAlignment.Center,
	textSize = 13,
	zIndex = 20,
})

-- Canto Inferior Esquerdo do Monstro: Biométrica da Carne (Slanted Wireframe)
local monsterBiometrics = AEM_UIKit.createWireBracketFrame(monsterHudRoot, {
	name = "MonsterBiometrics",
	parent = monsterHudRoot,
	anchorPoint = Vector2.new(0, 1),
	position = UDim2.new(0, 28, 1, -24),
	size = UDim2.fromOffset(264, 114),
	bgColor = Color3.fromRGB(23,32,35),
	bgTransparency = 0.18,
	bracketColor = AEM_UIKit.BOSS_CRIMSON,
	bracketThickness = 1.4,
	bracketLength = 10,
	mode = "LeftSlanted",
	slantDeg = -8,
	glow = true,
	zIndex = 12,
})

AEM_UIKit.makeMonoLabel({
	name = "FleshHeader",
	parent = monsterBiometrics,
	size = UDim2.fromOffset(240, 16),
	position = UDim2.fromOffset(10, 2),
	text = "SINAIS VITAIS",
	color = Color3.fromRGB(255,194,116),
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	textSize = 12,
	zIndex = 13,
})

local monsterHpGauge = AEM_UIKit.createSlantedGauge(monsterBiometrics, {
	name = "MonsterHPGauge",
	parent = monsterBiometrics,
	position = UDim2.fromOffset(10, 20),
	size = UDim2.fromOffset(252, 26),
	labelLeftText = "HP",
	labelRightText = "1200 / 1200",
	fillColor = AEM_UIKit.IVORY_TEXT,
	glowColor = AEM_UIKit.BOSS_CRIMSON,
	barHeight = 4,
	slantDeg = -2.0,
	zIndex = 13,
})

local monsterArmorGauge = AEM_UIKit.createSlantedGauge(monsterBiometrics, {
	name = "MonsterArmorGauge",
	parent = monsterBiometrics,
	position = UDim2.fromOffset(10, 50),
	size = UDim2.fromOffset(252, 24),
	labelLeftText = "ARMADURA",
	labelRightText = "600 / 600",
	fillColor = AEM_UIKit.AMBER_GLOW,
	glowColor = AEM_UIKit.AMBER_WIRE,
	barHeight = 3,
	slantDeg = -2.0,
	zIndex = 13,
})

local monsterStamGauge = AEM_UIKit.createSlantedGauge(monsterBiometrics, {
	name = "MonsterStaminaGauge",
	parent = monsterBiometrics,
	position = UDim2.fromOffset(10, 80),
	size = UDim2.fromOffset(252, 24),
	labelLeftText = "VIGOR",
	labelRightText = "100%",
	fillColor = AEM_UIKit.AMBER_WIRE,
	glowColor = AEM_UIKit.AMBER_WIRE,
	barHeight = 3,
	slantDeg = -2.0,
	zIndex = 13,
})

-- Canto Inferior Direito do Monstro: Bandeja de 8 Habilidades Chamfradas
local MonsterFieldDeck = require(ReplicatedStorage:WaitForChild("MonsterFieldDeck"))
local fieldSlots = MonsterFieldDeck.mount(monsterHudRoot, monsterBiometrics, getHudScale)

-- ============================================================================
-- 3) TELAS DE FIM DE PARTIDA (F11: KAIROS-09 DOSSIERS + REWARDS)
-- ============================================================================
local postMatchOverlay = Instance.new("Frame")
postMatchOverlay.Name = "PostMatchOverlay"
postMatchOverlay.Size = UDim2.fromScale(1, 1)
postMatchOverlay.BackgroundColor3 = AEM_UIKit.VOID_GLASS
postMatchOverlay.BackgroundTransparency = 0.38
postMatchOverlay.Visible = false
postMatchOverlay.ZIndex = 28
postMatchOverlay.Parent = screenGui

type DossierRowRefs = {
	keyLbl: TextLabel,
	valLbl: TextLabel,
}

type PostDossierHandle = {
	root: Frame,
	rows: { DossierRowRefs },
	rewardsCoinsLbl: TextLabel,
	rewardsXpLbl: TextLabel,
	rewardsBonusLbl: TextLabel,
	rewardsTotalLbl: TextLabel,
	countdownLbl: TextLabel,
}

local function buildPostDossier(
	parent: Instance,
	name: string,
	size: UDim2,
	bracketColor: Color3,
	titleText: string,
	subtitleText: string,
	statusTagText: string,
	statusTagColor: Color3,
	rewardsHeading: string,
	rowKeys: { string },
	baseZ: number
): PostDossierHandle
	local root = AEM_UIKit.createWireBracketFrame(parent, {
		name = name,
		parent = parent,
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = size,
		bgColor = AEM_UIKit.VOID_GLASS,
		bgTransparency = 0.78,
		bracketColor = bracketColor,
		bracketThickness = 1.4,
		bracketLength = 20,
		mode = "Corners",
		glow = true,
		zIndex = baseZ,
	})
	root.Visible = false

	local logo = AEM_UIKit.createInvertedTriangleLogo(root, 36, bracketColor)
	logo.Position = UDim2.fromOffset(24, 20)
	logo.ZIndex = baseZ + 1

	AEM_UIKit.makeMonoLabel({
		name = "DossierTitle",
		parent = root,
		size = UDim2.fromOffset(500, 26),
		position = UDim2.fromOffset(70, 18),
		text = titleText,
		color = AEM_UIKit.IVORY_TEXT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Bold,
		textSize = 22,
		zIndex = baseZ + 1,
	})

	AEM_UIKit.makeMonoLabel({
		name = "DossierSubtitle",
		parent = root,
		size = UDim2.fromOffset(500, 18),
		position = UDim2.fromOffset(70, 44),
		text = subtitleText,
		color = AEM_UIKit.AMBER_SOFT,
		textSize = 12,
		zIndex = baseZ + 1,
	})

	local statusTag = AEM_UIKit.createWireBracketFrame(root, {
		name = "StatusTag",
		parent = root,
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -24, 0, 22),
		size = UDim2.fromOffset(260, 30),
		bgColor = AEM_UIKit.VOID_GLASS,
		bgTransparency = 0.82,
		bracketColor = statusTagColor,
		bracketThickness = 1.2,
		bracketLength = 8,
		mode = "LeftRight",
		glow = true,
		zIndex = baseZ + 1,
	})

	AEM_UIKit.makeMonoLabel({
		name = "StatusTagLabel",
		parent = statusTag,
		size = UDim2.fromScale(0.94, 0.90),
		position = UDim2.fromScale(0.03, 0.05),
		text = statusTagText,
		color = statusTagColor,
		alignX = Enum.TextXAlignment.Center,
		textSize = 12,
		zIndex = baseZ + 2,
	})

	local topDivider = Instance.new("Frame")
	topDivider.Name = "HeaderDivider"
	topDivider.Position = UDim2.fromOffset(24, 72)
	topDivider.Size = UDim2.new(1, -48, 0, 1)
	topDivider.BackgroundColor3 = bracketColor
	topDivider.BackgroundTransparency = 0.45
	topDivider.BorderSizePixel = 0
	topDivider.ZIndex = baseZ + 1
	topDivider.Parent = root

	local rows: { DossierRowRefs } = {}
	for i, keyLabelText in ipairs(rowKeys) do
		local y = 90 + (i - 1) * 40
		local rowRule = Instance.new("Frame")
		rowRule.Position = UDim2.fromOffset(24, y + 32)
		rowRule.Size = UDim2.new(1, -48, 0, 1)
		rowRule.BackgroundColor3 = AEM_UIKit.HAIRLINE_DIM
		rowRule.BackgroundTransparency = 0.68
		rowRule.BorderSizePixel = 0
		rowRule.ZIndex = baseZ + 1
		rowRule.Parent = root

		local kLbl = AEM_UIKit.makeMonoLabel({
			name = "RowKey_" .. tostring(i),
			parent = root,
			size = UDim2.fromOffset(280, 24),
			position = UDim2.fromOffset(28, y + 2),
			text = keyLabelText,
			color = AEM_UIKit.AMBER_SOFT,
			textSize = 13,
			zIndex = baseZ + 2,
		})
		local vLbl = AEM_UIKit.makeMonoLabel({
			name = "RowVal_" .. tostring(i),
			parent = root,
			size = UDim2.new(1, -336, 0, 24),
			position = UDim2.fromOffset(312, y + 2),
			text = "--",
			color = AEM_UIKit.IVORY_TEXT,
			font = AEM_UIKit.FONT_TECH,
			weight = Enum.FontWeight.Bold,
			alignX = Enum.TextXAlignment.Right,
			truncate = true,
			textSize = 15,
			zIndex = baseZ + 2,
		})
		table.insert(rows, { keyLbl = kLbl, valLbl = vLbl })
	end

	local footerY = 90 + #rowKeys * 40 + 10
	local footerRule = Instance.new("Frame")
	footerRule.Name = "FooterDivider"
	footerRule.Position = UDim2.fromOffset(24, footerY)
	footerRule.Size = UDim2.new(1, -48, 0, 1)
	footerRule.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
	footerRule.BackgroundTransparency = 0.40
	footerRule.BorderSizePixel = 0
	footerRule.ZIndex = baseZ + 1
	footerRule.Parent = root

	AEM_UIKit.makeMonoLabel({
		name = "RewardsHeading",
		parent = root,
		size = UDim2.fromOffset(360, 18),
		position = UDim2.fromOffset(28, footerY + 10),
		text = rewardsHeading,
		color = AEM_UIKit.AMBER_WIRE,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Bold,
		textSize = 13,
		zIndex = baseZ + 2,
	})

	local rewardsBonusLbl = AEM_UIKit.makeMonoLabel({
		name = "RewardsBonus",
		parent = root,
		size = UDim2.new(1, -420, 0, 18),
		position = UDim2.fromOffset(396, footerY + 10),
		text = "STANDARD CLEARANCE",
		color = AEM_UIKit.AMBER_SOFT,
		alignX = Enum.TextXAlignment.Right,
		textSize = 12,
		zIndex = baseZ + 2,
	})

	local rewardsCoinsLbl = AEM_UIKit.makeMonoLabel({
		name = "RewardsCoins",
		parent = root,
		size = UDim2.fromOffset(260, 26),
		position = UDim2.fromOffset(28, footerY + 34),
		text = "+0 MARROW",
		color = AEM_UIKit.AMBER_GLOW,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Bold,
		textSize = 20,
		zIndex = baseZ + 2,
	})

	local rewardsXpLbl = AEM_UIKit.makeMonoLabel({
		name = "RewardsXP",
		parent = root,
		size = UDim2.fromOffset(240, 26),
		position = UDim2.fromOffset(300, footerY + 34),
		text = "+0 XP",
		color = AEM_UIKit.IVORY_TEXT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Bold,
		textSize = 20,
		zIndex = baseZ + 2,
	})

	local rewardsTotalLbl = AEM_UIKit.makeMonoLabel({
		name = "RewardsTotal",
		parent = root,
		size = UDim2.new(1, -568, 0, 26),
		position = UDim2.fromOffset(544, footerY + 34),
		text = "STOCK: 0 MARROW",
		color = AEM_UIKit.AMBER_SOFT,
		alignX = Enum.TextXAlignment.Right,
		textSize = 14,
		zIndex = baseZ + 2,
	})

	local countdownLbl = AEM_UIKit.makeMonoLabel({
		name = "ReturnCountdown",
		parent = root,
		size = UDim2.new(1, -56, 0, 18),
		position = UDim2.new(0, 28, 1, -28),
		text = "RETURNING TO KAIROS-09 TERMINAL // 10s",
		color = AEM_UIKit.AMBER_SOFT,
		alignX = Enum.TextXAlignment.Center,
		textSize = 12,
		zIndex = baseZ + 2,
	})

	return {
		root = root,
		rows = rows,
		rewardsCoinsLbl = rewardsCoinsLbl,
		rewardsXpLbl = rewardsXpLbl,
		rewardsBonusLbl = rewardsBonusLbl,
		rewardsTotalLbl = rewardsTotalLbl,
		countdownLbl = countdownLbl,
	}
end

local PostUI: {
	crtShutLine: Frame,
	autopsyDossier: PostDossierHandle,
	onyxFloodFrame: Frame,
	onyxDossier: PostDossierHandle,
	monsterWinHeadline: TextLabel,
	monsterWinSub: TextLabel,
}
do
	local postMatchCanvas, _ = AEM_UIKit.createScaledCanvas(postMatchOverlay, "PostMatchScaledCanvas", 30)

	local crtShutLine = Instance.new("Frame")
	crtShutLine.Name = "CRTShutdownLine"
	crtShutLine.AnchorPoint = Vector2.new(0.5, 0.5)
	crtShutLine.Position = UDim2.fromScale(0.5, 0.5)
	crtShutLine.Size = UDim2.fromScale(1, 0.02)
	crtShutLine.BackgroundColor3 = AEM_UIKit.IVORY_TEXT
	crtShutLine.BorderSizePixel = 0
	crtShutLine.Visible = false
	crtShutLine.ZIndex = 34
	crtShutLine.Parent = postMatchOverlay

	local autopsyDossier = buildPostDossier(
		postMatchCanvas,
		"HuntersAutopsyReport",
		UDim2.fromOffset(880, 440),
		AEM_UIKit.AMBER_WIRE,
		"KAIROS-09 AUTOPSY & RECLAMATION DOSSIER",
		"SECTOR DECONTAMINATION LOG // A.E.M. COMMAND",
		"CLEANSED // CADAVER RECLAIMED",
		AEM_UIKit.BOSS_CRIMSON,
		"EXTRACTION REWARDS",
		{
			"CLASSIFICATION",
			"TERMINATION CAUSE",
			"PEAK MUTATION",
			"POWER RELAY INTEGRITY",
			"ASSIGNED ROLE",
		},
		30
	)

	-- Vitória do Monstro: Sobreposição Translúcida + Dossier Wireframe Crimson/Amber
	local onyxFloodFrame = Instance.new("Frame")
	onyxFloodFrame.Name = "MonsterOnyxFlood"
	onyxFloodFrame.Size = UDim2.fromScale(1, 1)
	onyxFloodFrame.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	onyxFloodFrame.BackgroundTransparency = 0.88
	onyxFloodFrame.BorderSizePixel = 0
	onyxFloodFrame.Visible = false
	onyxFloodFrame.ZIndex = 29
	onyxFloodFrame.Parent = postMatchOverlay

	local onyxDossier = buildPostDossier(
		postMatchCanvas,
		"MonsterOnyxTextBox",
		UDim2.fromOffset(880, 440),
		AEM_UIKit.BOSS_CRIMSON,
		"THE APEX SURPASSES THE SHELL.",
		"PROTOCOL 6-7-9 CONVERGED // CONTAINMENT ERASED",
		"BREACH CONFIRMED // APEX",
		AEM_UIKit.AMBER_WIRE,
		"APEX REWARDS",
		{
			"PROTOCOL STATUS",
			"BREACH CAUSE",
			"PEAK MUTATION",
			"POWER RELAY INTEGRITY",
			"ASSIGNED ROLE",
		},
		33
	)

	local monsterWinHeadline = onyxDossier.root:FindFirstChild("DossierTitle") :: TextLabel
	local monsterWinSub = onyxDossier.root:FindFirstChild("DossierSubtitle") :: TextLabel

	PostUI = {
		crtShutLine = crtShutLine,
		autopsyDossier = autopsyDossier,
		onyxFloodFrame = onyxFloodFrame,
		onyxDossier = onyxDossier,
		monsterWinHeadline = monsterWinHeadline,
		monsterWinSub = monsterWinSub,
	}
end

-- ============================================================================
-- 4) PLANET SCANNER E BEACONS DE ALIADOS CAÍDOS
-- ============================================================================
local scannerContainer = Instance.new("Frame")
scannerContainer.Name = "PlanetScannerIndicator"
scannerContainer.AnchorPoint = Vector2.new(0.5, 0.5)
scannerContainer.Position = UDim2.fromScale(0.5, 0.5)
scannerContainer.Size = UDim2.fromOffset(196, 196)
scannerContainer.BackgroundTransparency = 1
scannerContainer.Visible = false
scannerContainer.ZIndex = 9
scannerContainer.Parent = hunterHudRoot

do
	local scannerRing = Instance.new("Frame")
	scannerRing.Name = "Ring"
	scannerRing.Size = UDim2.fromScale(1, 1)
	scannerRing.BackgroundTransparency = 1
	scannerRing.ZIndex = 9
	scannerRing.Parent = scannerContainer
	AEM_UIKit.drawArcPx(scannerRing, "ScannerArc", Vector2.new(98, 98), 96, 0, 360, 48, 1.2, AEM_UIKit.AMBER_WIRE, 0.32, 9, true)
end

local scannerArrow = Instance.new("TextLabel")
scannerArrow.Name = "DirectionalMarker"
scannerArrow.AnchorPoint = Vector2.new(0.5, 0.5)
scannerArrow.Position = UDim2.fromOffset(98, 12)
scannerArrow.Size = UDim2.fromOffset(22, 22)
scannerArrow.BackgroundTransparency = 1
scannerArrow.BorderSizePixel = 0
scannerArrow.FontFace = AEM_UIKit.FONT_FACE_BOLD
scannerArrow.Text = "^"
scannerArrow.TextColor3 = AEM_UIKit.AMBER_GLOW
scannerArrow.TextSize = 20
scannerArrow.ZIndex = 10
scannerArrow.Parent = scannerContainer
AEM_UIKit.applyTextContrast(scannerArrow, 0.78)

local scannerDistLabel = AEM_UIKit.makeMonoLabel({
	name = "DistanceLabel",
	parent = scannerContainer,
	size = UDim2.fromOffset(240, 28),
	position = UDim2.fromScale(0.5, 1.04),
	text = "SPECIMEN · -- STUDS",
	color = AEM_UIKit.IVORY_TEXT,
	alignX = Enum.TextXAlignment.Center,
	textSize = 13,
	zIndex = 10,
})
scannerDistLabel.AnchorPoint = Vector2.new(0.5, 0)

type DownedBillboardData = {
	gui: BillboardGui,
	wireFrame: Frame,
	label: TextLabel,
}

local downedBillboards: { [Player]: DownedBillboardData } = {}

local function removeDownedBillboard(player: Player): ()
	local entry = downedBillboards[player]
	if entry ~= nil then
		if entry.gui.Parent ~= nil then
			entry.gui:Destroy()
		end
		downedBillboards[player] = nil
	end
end

local function ensureDownedBillboard(player: Player, targetCharacter: Model): ()
	local adornee = targetCharacter:FindFirstChild("Head") or targetCharacter:FindFirstChild("HumanoidRootPart") or targetCharacter.PrimaryPart
	if adornee == nil or not adornee:IsA("BasePart") then
		removeDownedBillboard(player)
		return
	end

	local existing = downedBillboards[player]
	if existing ~= nil and existing.gui.Parent ~= nil then
		existing.gui.Adornee = adornee :: BasePart
		return
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = CONFIG.DownedBillboardPrefix .. player.Name
	bb.Adornee = adornee :: BasePart
	bb.Size = UDim2.fromOffset(224, 42)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = CONFIG.BillboardMaxDistance
	bb.ResetOnSpawn = false
	bb.Parent = playerGui

	local wireFrame = AEM_UIKit.createWireBracketFrame(bb, {
		name = "AlertWire",
		parent = bb,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		bgColor = AEM_UIKit.VOID_GLASS,
		bgTransparency = 0.82,
		bracketColor = AEM_UIKit.BOSS_CRIMSON,
		bracketThickness = 1.3,
		bracketLength = 8,
		mode = "Corners",
		glow = true,
		zIndex = 2,
	})

	local lbl = AEM_UIKit.makeMonoLabel({
		name = "HelpLabel",
		parent = wireFrame,
		size = UDim2.fromScale(0.92, 0.86),
		position = UDim2.fromScale(0.04, 0.07),
		text = "SOS · " .. string.upper(player.DisplayName),
		color = AEM_UIKit.BOSS_CRIMSON,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Bold,
		alignX = Enum.TextXAlignment.Center,
		wrapped = true,
		truncate = true,
		textSize = 14,
		zIndex = 4,
	})

	downedBillboards[player] = {
		gui = bb,
		wireFrame = wireFrame,
		label = lbl,
	}
end

-- ============================================================================
-- 5) LÓGICA DE ESTADO, TELEMETRIA E BINDINGS ORIGINAIS DE GAMEPLAY
-- ============================================================================
local peakJetpack = CONFIG.DefaultMaxJetpack
local peakShield = CONFIG.DefaultMaxShield
local peakStamina = CONFIG.DefaultMaxStamina
local hunterConfig = require(ReplicatedStorage:WaitForChild("HunterCombatConfig"))
local hunterAudio = require(ReplicatedStorage:WaitForChild("HunterAudio"))
local classSkills = hunterConfig.ClassSkills
local secondarySkills = hunterConfig.SecondarySkills

local localCharConnections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local charConnections: { [Model]: { RBXScriptConnection } } = {}
local relayConnections: { RBXScriptConnection } = {}
local globalConnections: { RBXScriptConnection } = {}

local lastMonsterStageByChar: { [Model]: number } = {}
local highestAnnouncedStage = 1
local bannerToken = 0
local cachedMatchState: string = "Intermission"
local activePostMatchWinner: string? = nil
local activePostMatchReason: string = ""

local equippedWeaponId: string = ""
local equippedWeaponMax: number = 72
local equippedWeaponCurrent: number = 72
local isFiringVisual = false
local lastShotTelemetryAt = 0
local monsterHitFlashUntil = 0
local hunterAberrationFlash = 0
local lastKnownHunterHP: number? = nil

local monsterCooldownEnds: { [string]: number } = {
	LeapSmash = 0,
	FeralCharge = 0,
	AcidBreath = 0,
	Smell = 0,
}
local lastMonsterActionSeen: string? = nil
local monsterChannelKind: string = ""
local monsterChannelStartedAt = 0
local cachedShortTimer: string = "00:00"

type MatchRewardsPayload = {
	coins: number,
	xp: number,
	totalCoins: number?,
	totalXP: number?,
	won: boolean?,
	role: string?,
	vipApplied: boolean,
	roomBoostApplied: boolean,
}
local lastMatchRewards: MatchRewardsPayload? = nil
local cachedWorkspaceMonsterDummy: Model? = nil

local function getGameRemotesFolder(): Instance?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	return if remotes ~= nil then remotes:FindFirstChild("GameRemotes") else nil
end

local function scanWorkspaceMonsterDummy(): Model?
	if cachedWorkspaceMonsterDummy ~= nil and cachedWorkspaceMonsterDummy.Parent ~= nil and getStringAttr(cachedWorkspaceMonsterDummy, "Role") == "Monster" then
		return cachedWorkspaceMonsterDummy
	end
	cachedWorkspaceMonsterDummy = nil
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and Players:GetPlayerFromCharacter(child) == nil and getStringAttr(child, "Role") == "Monster" then
			cachedWorkspaceMonsterDummy = child
			return child
		end
	end
	return nil
end

local function findMonsterModel(includeDead: boolean?): Model?
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		if c ~= nil and getStringAttr(c, "Role") == "Monster" and (includeDead == true or not getBoolAttr(c, "IsDead")) then
			return c
		end
	end
	local dummy = scanWorkspaceMonsterDummy()
	if dummy ~= nil and (includeDead == true or not getBoolAttr(dummy, "IsDead")) then
		return dummy
	end
	return nil
end

local stageBannerState: "hidden" | "in" | "shown" | "out" = "hidden"
local stageBannerTween: Tween? = nil
local stageBannerCurrentTargetY = 142
local rewardToastState: "hidden" | "in" | "shown" = "hidden"
local rewardToastTween: Tween? = nil
local rewardToastCurrentTargetY = 210

local function computeTopStackTargets(): (number, number, number)
	local topInset = AEM_UIKit.getLogicalTopInset(getHudScale)
	local base = math.max(58, topInset + 6)
	local nextY = base

	topLeftIdentity.Position = UDim2.fromOffset(28, base)
	roomBoostFrame.Position = UDim2.fromOffset(28, base + 82)
	objectivePanel.Position = UDim2.new(1, -28, 0, base)

	if bossHealthBar.root.Visible then
		bossHealthBar.root.Position = UDim2.new(0.5, 0, 0, base - 4)
		nextY = (base - 4) + 70
	end

	if monsterHudRoot.Visible then
		monsterTopBar.Position = UDim2.new(0.5, 0, 0, nextY)
		nextY += 38 + 4
	elseif hunterHudRoot.Visible and compassBar.Visible then
		compassBar.Position = UDim2.new(0.5, 0, 0, nextY)
		nextY += 24 + 4
	end

	if matchStatusBar.Visible then
		matchStatusBar.Position = UDim2.new(0.5, 0, 0, nextY)
		nextY += 24 + 4
	end

	if relayContainer.Visible then
		relayContainer.Position = UDim2.new(0.5, 0, 0, nextY)
		nextY += 32 + 4
	end

	if monsterHudRoot.Visible and domeSuppressionOverlay.Visible then
		domeWarnBox.Position = UDim2.new(0.5, 0, 0, nextY)
		nextY += 28 + 4
	end

	if monsterHudRoot.Visible and monsterEvolveBanner.Visible then
		monsterEvolveBanner.Position = UDim2.new(0.5, 0, 0, nextY)
		nextY += 32 + 4
	end

	local stageTargetY = math.min(340, nextY + 4)
	return base, nextY, stageTargetY
end

local function repositionTopStack(force: boolean?): ()
	local _, nextY, stageTargetY = computeTopStackTargets()

	if stageBanner.Visible and stageBannerState ~= "out" then
		if stageBannerState == "shown" then
			if force == true or math.abs(stageBanner.Position.Y.Offset - stageTargetY) > 1 then
				stageBanner.Position = UDim2.new(0.5, 0, 0, stageTargetY)
				stageBannerCurrentTargetY = stageTargetY
			end
		elseif stageBannerState == "in" and math.abs(stageBannerCurrentTargetY - stageTargetY) > 1 then
			stageBannerCurrentTargetY = stageTargetY
			if stageBannerTween ~= nil then
				stageBannerTween:Cancel()
			end
			local tw = TweenService:Create(stageBanner, CONFIG.BannerInTween, {
				Position = UDim2.new(0.5, 0, 0, stageTargetY),
			})
			stageBannerTween = tw
			tw.Completed:Once(function()
				if stageBannerState == "in" and stageBannerTween == tw then
					stageBannerState = "shown"
				end
			end)
			tw:Play()
		end
	end

	if rewardToast.Visible then
		local toastY = math.min(390, if stageBanner.Visible then stageTargetY + 40 + 6 else nextY + 4)
		if rewardToastState == "shown" then
			if force == true or math.abs(rewardToast.Position.Y.Offset - toastY) > 1 then
				rewardToast.Position = UDim2.new(0.5, 0, 0, toastY)
				rewardToastCurrentTargetY = toastY
			end
		elseif rewardToastState == "in" and math.abs(rewardToastCurrentTargetY - toastY) > 1 then
			rewardToastCurrentTargetY = toastY
			if rewardToastTween ~= nil then
				rewardToastTween:Cancel()
			end
			local tw = TweenService:Create(rewardToast, CONFIG.BannerInTween, {
				Position = UDim2.new(0.5, 0, 0, toastY),
			})
			rewardToastTween = tw
			tw.Completed:Once(function()
				if rewardToastState == "in" and rewardToastTween == tw then
					rewardToastState = "shown"
				end
			end)
			tw:Play()
		end
	end
end

local function updateBossHealthBar(): ()
	local canShow = hunterHudRoot.Visible and cachedMatchState ~= "PostMatch"
	local mModel = if canShow then findMonsterModel(true) else nil
	local wasVisible = bossHealthBar.root.Visible

	if mModel == nil then
		bossHealthBar.root.Visible = false
		if wasVisible then
			repositionTopStack(true)
		end
		return
	end

	local stage = math.clamp(math.floor(getNumberAttr(mModel, "Stage", 1)), 1, 3)
	local hp = math.max(0, getNumberAttr(mModel, "CustomHealth", 0))
	local maxHp = math.max(1, getNumberAttr(mModel, "MaxCustomHealth", 1200))
	local armor = math.max(0, getNumberAttr(mModel, "Armor", 0))
	local maxArmor = math.max(0, getNumberAttr(mModel, "MaxArmor", 0))
	local isEvolving = getBoolAttr(mModel, "IsEvolving")

	bossHealthBar.setHeader(MONSTER_STAGE_TITLES[stage] or MONSTER_STAGE_TITLES[1])
	bossHealthBar.setProgress(math.clamp(hp / maxHp, 0, 1))

	local subLeft = string.format("VITALS // %d / %d", math.ceil(hp), math.ceil(maxHp))
	local subRight = if isEvolving
		then "EVOLVING // ARMOR EXPOSED"
		elseif maxArmor > 0 and armor > 0 then string.format("CARAPACE // %d / %d", math.ceil(armor), math.ceil(maxArmor))
		elseif maxArmor > 0 then "CARAPACE // EXPOSED"
		else string.format("%d%%", math.round(math.clamp(hp / maxHp, 0, 1) * 100))
	bossHealthBar.setSubtext(subLeft, subRight)
	bossHealthBar.root.Visible = true
	if not wasVisible then
		repositionTopStack(true)
	end
end

local function updatePowerRelayUI(): ()
	local mapContainer = Workspace:FindFirstChild("Map")
	local relay = if mapContainer ~= nil then mapContainer:FindFirstChild("PowerRelay") else nil
	local localRole = if LocalPlayer.Character ~= nil then getStringAttr(LocalPlayer.Character, "Role") else nil
	if relay == nil or localRole == "Lobby" or localRole == nil or cachedMatchState == "PostMatch" then
		relayContainer.Visible = false
		repositionTopStack(false)
		return
	end

	local gameRemotes = getGameRemotesFolder()
	local hp = getNumberAttr(relay, "RelayHealth", 0)
	local maxHp = math.max(1, getNumberAttr(relay, "MaxRelayHealth", 100))
	local suddenDeath = if gameRemotes ~= nil then gameRemotes:GetAttribute("SuddenDeath") == true else false
	local shouldShow = suddenDeath or highestAnnouncedStage >= 3 or (hp > 0 and hp < maxHp)
	relayContainer.Visible = shouldShow

	if shouldShow then
		if suddenDeath or hp <= 0 then
			relayBarText.Text = "A.E.M. ANCHOR RELAY // SHATTERED · SUDDEN DEATH"
			relaySegBar.setRatio(0, AEM_UIKit.BOSS_CRIMSON)
			setWireBracketColor(relayContainer, AEM_UIKit.BOSS_CRIMSON)
		else
			local ratio = math.clamp(hp / maxHp, 0, 1)
			relayBarText.Text = string.format(
				"A.E.M. ANCHOR RELAY // %d / %d HP (%d%%)",
				math.ceil(hp),
				math.ceil(maxHp),
				math.clamp(math.floor(ratio * 100 + 0.5), 0, 100)
			)
			local col = if ratio < 0.35 then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.AMBER_WIRE
			relaySegBar.setRatio(ratio, col)
			setWireBracketColor(relayContainer, col)
		end
	end
	repositionTopStack(false)
end

local function showStageBanner(stageNumber: number): ()
	local text: string? = nil
	if stageNumber == 2 then
		text = "ALERT // SPECIMEN REACHED STAGE II MUTATION"
		setWireBracketColor(stageBanner, AEM_UIKit.AMBER_WIRE)
		stageBannerLabel.TextColor3 = AEM_UIKit.AMBER_GLOW
	elseif stageNumber >= 3 then
		local localRole = if LocalPlayer.Character ~= nil then getStringAttr(LocalPlayer.Character, "Role") else nil
		text = if localRole == "Monster"
			then "STAGE III APEX VESSEL // DESTROY THE A.E.M. ANCHOR RELAY"
			else "STAGE III BREACH // DEFEND THE A.E.M. ANCHOR RELAY"
		setWireBracketColor(stageBanner, AEM_UIKit.BOSS_CRIMSON)
		stageBannerLabel.TextColor3 = AEM_UIKit.BOSS_CRIMSON
	end
	if text == nil then
		return
	end

	bannerToken += 1
	local myToken = bannerToken
	if stageBannerTween ~= nil then
		stageBannerTween:Cancel()
		stageBannerTween = nil
	end

	local _, _, targetY = computeTopStackTargets()
	stageBannerCurrentTargetY = targetY
	stageBannerState = "in"
	stageBannerLabel.Text = text
	stageBanner.Visible = true
	stageBanner.Position = UDim2.new(0.5, 0, 0, -70)
	playOneShotAlert(if stageNumber >= 3 then AUDIO_IDS.Stage3Alert else AUDIO_IDS.Stage2Alert, 1, 0.78)

	local inTween = TweenService:Create(stageBanner, CONFIG.BannerInTween, {
		Position = UDim2.new(0.5, 0, 0, targetY),
	})
	stageBannerTween = inTween
	inTween.Completed:Once(function()
		if myToken == bannerToken and stageBannerState == "in" then
			stageBannerState = "shown"
		end
	end)
	inTween:Play()

	task.delay(CONFIG.BannerHoldSeconds, function()
		if myToken ~= bannerToken or not screenGui.Parent then
			return
		end
		stageBannerState = "out"
		local outTween = TweenService:Create(stageBanner, CONFIG.BannerOutTween, {
			Position = UDim2.new(0.5, 0, 0, -70),
		})
		stageBannerTween = outTween
		outTween.Completed:Once(function()
			if myToken == bannerToken then
				stageBanner.Visible = false
				stageBannerState = "hidden"
				repositionTopStack(false)
			end
		end)
		outTween:Play()
	end)
end

local function bindPowerRelay(): ()
	clearConnections(relayConnections)

	local mapContainer = Workspace:FindFirstChild("Map")
	if mapContainer == nil then
		table.insert(relayConnections, Workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Map" then
				bindPowerRelay()
			end
		end))
		updatePowerRelayUI()
		return
	end

	local relay = mapContainer:FindFirstChild("PowerRelay")
	if relay ~= nil then
		table.insert(relayConnections, relay:GetAttributeChangedSignal("RelayHealth"):Connect(updatePowerRelayUI))
		table.insert(relayConnections, relay:GetAttributeChangedSignal("MaxRelayHealth"):Connect(updatePowerRelayUI))
		table.insert(relayConnections, relay.Destroying:Connect(updatePowerRelayUI))
	else
		table.insert(relayConnections, mapContainer.ChildAdded:Connect(function(child: Instance)
			if child.Name == "PowerRelay" then
				bindPowerRelay()
			end
		end))
	end
	updatePowerRelayUI()
end

local function resolveCooldownSeconds(rawValue: number): number
	if rawValue > 1000 then
		return math.max(0, rawValue - Workspace:GetServerTimeNow())
	end
	return math.max(0, rawValue)
end

local function updateAbilityBadge(
	badge: AEM_UIKit.ChamferedAbilityBadgeHandle,
	slotKey: string,
	skillId: string,
	fallbackLabel: string,
	cdSec: number,
	maxCd: number,
	activeSec: number
): ()
	local meta = SKILL_DISPLAY_META[skillId]
	local displayLabel = if meta ~= nil then meta.label else string.upper(fallbackLabel)
	local glyphId = if meta ~= nil then meta.glyph else (AEM_UIKit.SKILL_ID_TO_GLYPH[skillId] or "scanner")

	if cachedBadgeSkillIds[slotKey] ~= skillId then
		cachedBadgeSkillIds[slotKey] = skillId
		badge.setLabel(displayLabel)
		badge.setGlyph(glyphId)
	end

	if activeSec > 0 then
		badge.setState("ACTIVE", 1, true)
	elseif cdSec <= 0.05 then
		badge.setState("READY", 1, true)
	else
		local denom = math.max(1, maxCd)
		local progress = math.clamp(1 - (cdSec / denom), 0, 1)
		badge.setState(string.format("%ds", math.ceil(cdSec)), progress, false)
	end
end

local function refreshFieldTiles(char: Model): ()
	local now = Workspace:GetServerTimeNow()
	local gameRemotes = getGameRemotesFolder()
	local activeUntil = if gameRemotes ~= nil then getNumberAttr(gameRemotes, "DomeActiveUntil", 0) else 0
	local domeCd = resolveCooldownSeconds(getNumberAttr(char, "DomeCooldown", 0))
	local role = getStringAttr(char, "Role") or ""
	local skill = classSkills[role]
	local skillCd = resolveCooldownSeconds(getNumberAttr(char, if role == "Trapper" then "ScannerCooldown" else "ClassSkillCooldown", 0))
	local secondary = secondarySkills[role]

	updateAbilityBadge(domeBadge, "Dome", "DeployDome", "DOME STAGE", domeCd, CONFIG.DefaultMaxDomeCooldown, math.max(0, activeUntil - now))

	if skill ~= nil then
		local left = math.max(0, getNumberAttr(char, "ClassSkillActiveUntil", 0) - now)
		updateAbilityBadge(scannerBadge, "Class", skill.Id, skill.Label, skillCd, skill.Cooldown or 30, left)
	end

	if secondary ~= nil then
		local secCd = resolveCooldownSeconds(getNumberAttr(char, "SecondarySkillCooldown", 0))
		local secLeft = math.max(0, getNumberAttr(char, "SecondarySkillActiveUntil", 0) - now)
		updateAbilityBadge(secondaryBadge, "Secondary", secondary.Id, secondary.Label, secCd, secondary.Cooldown or 25, secLeft)
	end
end

local WIN_REASON_LABELS: { [string]: string } = {
	MonsterEliminated = "SPECIMEN TERMINATED",
	HuntersIncapacitated = "SQUAD INCAPACITATED",
	PowerRelayDestroyed = "POWER RELAY DESTROYED",
	TimeExpired = "CONTAINMENT WINDOW EXPIRED",
}

local function formatWinReason(reason: string?, fallback: string): string
	if reason == nil or reason == "" then
		return fallback
	end
	return WIN_REASON_LABELS[reason] or string.upper(reason)
end

local function updateObjectiveDirective(): ()
	local mModel = findMonsterModel()
	local mStage = if mModel ~= nil then math.clamp(math.floor(getNumberAttr(mModel, "Stage", 1)), 1, 3) else math.clamp(highestAnnouncedStage, 1, 3)
	objectiveLine1.Text = if mStage >= 3 then "DEFEND POWER RELAY" else "PURGE SPECIMEN"
	objectiveLine2.Text = string.format("STAGE %s · MUTATION", string.rep("I", mStage))
end

local function applyPostMatchRewardsToDossier(dossier: PostDossierHandle, payload: MatchRewardsPayload?): ()
	local localCoins = math.floor(tonumber(LocalPlayer:GetAttribute("Coins")) or 0)
	if payload == nil then
		dossier.rewardsCoinsLbl.Text = "PENDING AUDIT"
		dossier.rewardsXpLbl.Text = "-- XP"
		dossier.rewardsBonusLbl.Text = "EXTRACTION LEDGER"
		dossier.rewardsTotalLbl.Text = string.format("STOCK: %d MARROW", localCoins)
		return
	end

	dossier.rewardsCoinsLbl.Text = string.format("+%d MARROW", math.floor(payload.coins))
	dossier.rewardsXpLbl.Text = string.format("+%d XP", math.floor(payload.xp))
	local bonuses: { string } = {}
	if payload.vipApplied then
		table.insert(bonuses, "VIP +50%")
	end
	if payload.roomBoostApplied then
		table.insert(bonuses, "2x ROOM BOOST")
	end
	dossier.rewardsBonusLbl.Text = if #bonuses > 0 then table.concat(bonuses, " // ") else "STANDARD CLEARANCE"
	local totalStock = math.floor(payload.totalCoins or localCoins)
	dossier.rewardsTotalLbl.Text = string.format("STOCK: %d MARROW", totalStock)
end

local function updatePostMatchCountdown(seconds: number?): ()
	local secs = if typeof(seconds) == "number" then math.max(0, math.floor(seconds)) else 0
	local text = string.format("RETURNING TO KAIROS-09 TERMINAL // %02ds", secs)
	PostUI.autopsyDossier.countdownLbl.Text = text
	PostUI.onyxDossier.countdownLbl.Text = text
end

local function refreshPostMatchDossiers(winner: string?): ()
	local gameRemotes = getGameRemotesFolder()
	local mapFolder = Workspace:FindFirstChild("Map")
	local relay = if mapFolder ~= nil then mapFolder:FindFirstChild("PowerRelay") else nil
	local relayHp = if relay ~= nil then math.max(0, getNumberAttr(relay, "RelayHealth", 0)) else 0
	local maxRelayHp = if relay ~= nil then math.max(1, getNumberAttr(relay, "MaxRelayHealth", 12000)) else 12000
	local suddenDeath = if gameRemotes ~= nil then gameRemotes:GetAttribute("SuddenDeath") == true else false
	local relayPct = math.clamp(math.round((relayHp / maxRelayHp) * 100), 0, 100)
	local relayText = if suddenDeath or relayHp <= 0
		then "SHATTERED (0%)"
		else string.format("%d / %d (%d%%)", math.ceil(relayHp), math.ceil(maxRelayHp), relayPct)

	local peakStage = math.clamp(highestAnnouncedStage, 1, 3)
	local stageLabel = MONSTER_STAGE_TITLES[peakStage] or MONSTER_STAGE_TITLES[1]
	local charRole = if LocalPlayer.Character ~= nil then getStringAttr(LocalPlayer.Character, "Role") else nil
	local roleLabel = string.upper(if lastMatchRewards ~= nil and typeof(lastMatchRewards.role) == "string" and lastMatchRewards.role ~= ""
		then lastMatchRewards.role :: string
		elseif typeof(charRole) == "string" and charRole ~= "" and charRole ~= "Lobby" then charRole :: string
		else "OPERATIVE")

	if winner == "Hunters" then
		local r = PostUI.autopsyDossier.rows
		r[1].valLbl.Text = "BIOMECHANICAL ANOMALY"
		r[2].valLbl.Text = formatWinReason(activePostMatchReason, "SPECIMEN TERMINATED")
		r[3].valLbl.Text = stageLabel
		r[4].valLbl.Text = relayText
		r[5].valLbl.Text = roleLabel
		applyPostMatchRewardsToDossier(PostUI.autopsyDossier, lastMatchRewards)
	else
		local r = PostUI.onyxDossier.rows
		r[1].valLbl.Text = "CONTAINMENT OVERRUN"
		r[2].valLbl.Text = formatWinReason(activePostMatchReason, "BREACH COMPLETE")
		r[3].valLbl.Text = stageLabel
		r[4].valLbl.Text = relayText
		r[5].valLbl.Text = roleLabel
		applyPostMatchRewardsToDossier(PostUI.onyxDossier, lastMatchRewards)
	end
end

local function triggerPostMatchScreen(winner: string?, reason: string?): ()
	activePostMatchWinner = winner
	activePostMatchReason = reason or ""
	Radar.setOpen(false, true)
	if stageBannerTween ~= nil then
		stageBannerTween:Cancel()
		stageBannerTween = nil
	end
	if rewardToastTween ~= nil then
		rewardToastTween:Cancel()
		rewardToastTween = nil
	end
	stageBanner.Visible = false
	stageBannerState = "hidden"
	rewardToast.Visible = false
	rewardToastState = "hidden"
	bossHealthBar.root.Visible = false
	matchStatusBar.Visible = false
	roomBoostFrame.Visible = false
	postMatchOverlay.Visible = true
	hunterHudRoot.Visible = false
	monsterHudRoot.Visible = false
	relayContainer.Visible = false
	scannerContainer.Visible = false
	crtLayer.root.Visible = true
	repositionTopStack(true)
	refreshPostMatchDossiers(winner)

	local gameRemotes = getGameRemotesFolder()
	local remTime = if gameRemotes ~= nil then gameRemotes:GetAttribute("TimeRemaining") else nil
	updatePostMatchCountdown(if typeof(remTime) == "number" then remTime else 10)

	if winner == "Hunters" then
		PostUI.onyxFloodFrame.Visible = false
		PostUI.onyxDossier.root.Visible = false
		PostUI.autopsyDossier.root.Visible = false
		PostUI.crtShutLine.Visible = true
		PostUI.crtShutLine.Size = UDim2.fromScale(1, 0.08)
		playOneShotAlert(AUDIO_IDS.CRTOff, 1.0, 0.72)
		playOneShotAlert(AUDIO_IDS.CRTBeep, 1.15, 0.55)

		TweenService:Create(PostUI.crtShutLine, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 0.002),
		}):Play()

		task.delay(0.24, function()
			if cachedMatchState ~= "PostMatch" or activePostMatchWinner ~= "Hunters" then
				return
			end
			PostUI.crtShutLine.Visible = false
			PostUI.autopsyDossier.root.Visible = true
			refreshPostMatchDossiers("Hunters")
		end)
	else
		PostUI.autopsyDossier.root.Visible = false
		PostUI.crtShutLine.Visible = false
		PostUI.onyxFloodFrame.Visible = true
		PostUI.onyxDossier.root.Visible = true
		PostUI.onyxFloodFrame.BackgroundTransparency = 0.88
		playOneShotAlert(AUDIO_IDS.BoneCrunch, 0.92, 0.80)
		playOneShotAlert(AUDIO_IDS.Stage3Alert, 0.65, 0.65)
		TweenService:Create(PostUI.onyxFloodFrame, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.35,
		}):Play()
		refreshPostMatchDossiers("Monster")
	end
end

local function refreshMatchStatusBarVisibility(): ()
	local char = LocalPlayer.Character
	local role = if char ~= nil then getStringAttr(char, "Role") else nil
	local inIntermissionLobby = (cachedMatchState == "Intermission" or cachedMatchState == "Lobby" or cachedMatchState == "Waiting")
		and (role == nil or role == "Lobby")
	if inIntermissionLobby or cachedMatchState == "PostMatch" or (not hunterHudRoot.Visible and not monsterHudRoot.Visible) then
		matchStatusBar.Visible = false
	elseif hunterHudRoot.Visible then
		matchStatusBar.Visible = (cachedMatchState ~= "ActiveHunt")
	else
		matchStatusBar.Visible = true
	end
	repositionTopStack(true)
end

local function refreshLocalHUD(): ()
	suppressLegacyMonsterGui()

	if cachedMatchState == "PostMatch" and activePostMatchWinner ~= nil then
		return
	end
	postMatchOverlay.Visible = false

	local char = LocalPlayer.Character
	if char == nil or char.Parent == nil then
		Radar.setOpen(false, true)
		hunterHudRoot.Visible = false
		monsterHudRoot.Visible = false
		bossHealthBar.root.Visible = false
		crtLayer.root.Visible = false
		relayContainer.Visible = false
		refreshMatchStatusBarVisibility()
		return
	end

	local role = getStringAttr(char, "Role")
	if role == nil or role == "Lobby" then
		Radar.setOpen(false, true)
		hunterHudRoot.Visible = false
		monsterHudRoot.Visible = false
		bossHealthBar.root.Visible = false
		crtLayer.root.Visible = false
		relayContainer.Visible = false
		lastKnownHunterHP = nil
		refreshMatchStatusBarVisibility()
		return
	end

	local hp = getNumberAttr(char, "CustomHealth", 0)
	local maxHp = math.max(1, getNumberAttr(char, "MaxCustomHealth", 100))
	local isDowned = getBoolAttr(char, "IsDowned")
	local isDead = getBoolAttr(char, "IsDead")

	if isHunterRole(role) then
		monsterHudRoot.Visible = false
		hunterHudRoot.Visible = true
		crtLayer.root.Visible = true

		if lastKnownHunterHP ~= nil and hp < lastKnownHunterHP then
			hunterAberrationFlash = 1.0
		end
		lastKnownHunterHP = hp

		local style = HUNTER_ROLES[role :: string]
		setWireBracketColor(vitalsBracket, if isDowned then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.AMBER_WIRE)

		if isDead then
			hunterBpmLbl.Text = "TERMINATED"
			hunterBpmLbl.TextColor3 = AEM_UIKit.AMBER_SOFT
		elseif isDowned then
			local bleed = math.max(0, math.ceil(getNumberAttr(char, "BleedoutRemaining", 0)))
			hunterBpmLbl.Text = string.format("DOWN %ds", bleed)
			hunterBpmLbl.TextColor3 = AEM_UIKit.BOSS_CRIMSON
		end

		local hpRatio = math.clamp(hp / maxHp, 0, 1)
		local hpPct = math.round(hpRatio * 100)
		local hpColor = if hpRatio < 0.3 then AEM_UIKit.BOSS_CRIMSON elseif hpRatio < 0.6 then AEM_UIKit.AMBER_WIRE else AEM_UIKit.IVORY_TEXT
		hunterHpGauge.setPercent(hpPct, hpColor)

		local shield = math.max(0, getNumberAttr(char, "PersonalShield", 0))
		local maxShieldAttr = getNumberAttr(char, "MaxPersonalShield", 0)
		peakShield = if maxShieldAttr > 0 then maxShieldAttr else math.max(peakShield, shield)
		local shdPct = math.round(math.clamp(shield / math.max(1, peakShield), 0, 1) * 100)
		hunterShdGauge.setPercent(shdPct, AEM_UIKit.AMBER_GLOW)

		local fuel = math.max(0, getNumberAttr(char, "JetpackFuel", 0))
		local maxFuelAttr = getNumberAttr(char, "MaxJetpackFuel", 0)
		peakJetpack = if maxFuelAttr > 0 then maxFuelAttr else math.max(peakJetpack, fuel)
		local jpkRatio = math.clamp(fuel / math.max(1, peakJetpack), 0, 1)
		local jpkPct = math.floor(jpkRatio * 100 + 0.5)
		jpkSegBar.setRatio(jpkRatio, AEM_UIKit.AMBER_WIRE)
		hunterJpkAsciiLbl.Text = string.format("JPK %d%%", jpkPct)

		if equippedWeaponId ~= "" then
			local ammoRatio = equippedWeaponCurrent / math.max(1, equippedWeaponMax)
			classAmmoLabel.Text = string.format("CLASS: %s // AMMO: %d / %d", style.displayName, equippedWeaponCurrent, equippedWeaponMax)
			classAmmoLabel.TextColor3 = if ammoRatio <= 0.25 then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.IVORY_TEXT
		else
			classAmmoLabel.Text = string.format("CLASS: %s // HOLSTERED", style.displayName)
			classAmmoLabel.TextColor3 = AEM_UIKit.AMBER_SOFT
		end

		updateObjectiveDirective()

		refreshFieldTiles(char)
	elseif role == "Monster" then
		Radar.setOpen(false, true)
		hunterHudRoot.Visible = false
		crtLayer.root.Visible = false
		monsterHudRoot.Visible = true
		lastKnownHunterHP = nil

		local stage = math.clamp(math.floor(getNumberAttr(char, "Stage", 1)), 1, 3)
		monsterStageBadge.Text = string.format("ESTÁGIO %s", string.rep("I", stage))

		local energy = math.clamp(getNumberAttr(char, "EvolutionEnergy", 0), 0, CONFIG.DefaultMaxEvolution)
		local pct = math.floor(energy + 0.5)
		local bioReady = energy >= 100 and stage < 3
		monsterBioSegBar.setRatio(energy / 100, if bioReady then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.AMBER_GLOW)
		monsterBiomassText.Text = string.format("%d%%", pct)
		monsterBiomassText.TextColor3 = if bioReady then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.AMBER_GLOW

		local isEating = getBoolAttr(char, "IsEating")
		local isEvolving = getBoolAttr(char, "IsEvolving")
		if isEvolving then
			if monsterChannelKind ~= "Evolving" then
				monsterChannelKind = "Evolving"
				monsterChannelStartedAt = os.clock()
			end
			monsterEvolveBanner.Visible = true
			monsterChannelBar.root.Visible = true
		elseif isEating then
			if monsterChannelKind ~= "Eating" then
				monsterChannelKind = "Eating"
				monsterChannelStartedAt = os.clock()
			end
			monsterEvolveBanner.Visible = true
			monsterChannelBar.root.Visible = true
		elseif bioReady then
			monsterChannelKind = ""
			monsterEvolveBanner.Visible = true
			monsterChannelBar.root.Visible = false
			local near = getBoolAttr(char, "NearEvolutionNest")
			local distance = math.round(getNumberAttr(char, "NearestNestDist", 0))
			monsterEvolvePrompt.Text = if near then "NO NINHO  ·  SEGURE EVOLUIR POR 5 s" elseif distance>0 then string.format("PROCURE UM NINHO  ·  %d studs",distance) else "PROCURE UM NINHO"
		else
			monsterChannelKind = ""
			monsterEvolveBanner.Visible = false
			monsterChannelBar.root.Visible = false
		end

		local hpPct = math.clamp(hp / maxHp, 0, 1) * 100
		local mHpColor = if hpPct < 30 then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.IVORY_TEXT
		monsterHpGauge.setPercent(hpPct, mHpColor, string.format("%d / %d", math.ceil(hp), math.ceil(maxHp)))

		local armor = math.max(0, getNumberAttr(char, "Armor", 0))
		local maxArmor = math.max(1, getNumberAttr(char, "MaxArmor", 100))
		local armPct = math.clamp(armor / maxArmor, 0, 1) * 100
		monsterArmorGauge.setPercent(armPct, AEM_UIKit.AMBER_GLOW, string.format("%d / %d", math.ceil(armor), math.ceil(maxArmor)))

		local stamina = math.max(0, getNumberAttr(char, "Stamina", 0))
		local maxStamAttr = getNumberAttr(char, "MaxStamina", 0)
		peakStamina = if maxStamAttr > 0 then maxStamAttr else math.max(peakStamina, stamina)
		local stamRatio = math.clamp(stamina / math.max(1, peakStamina), 0, 1)
		local stamPct = math.floor(stamRatio * 100 + 0.5)
		monsterStamGauge.setPercent(stamPct, AEM_UIKit.AMBER_WIRE, string.format("%d%%", stamPct))

		local curAction = getStringAttr(char, "MonsterAction")
		if curAction ~= nil and curAction ~= lastMonsterActionSeen then
			if curAction == "LeapSmash" then
				monsterCooldownEnds.LeapSmash = os.clock() + 6
			elseif curAction == "FeralCharge" then
				monsterCooldownEnds.FeralCharge = os.clock() + 8
			elseif curAction == "AcidBreath" then
				monsterCooldownEnds.AcidBreath = os.clock() + 9
			end
		end
		lastMonsterActionSeen = curAction
	else
		Radar.setOpen(false, true)
		hunterHudRoot.Visible = false
		monsterHudRoot.Visible = false
		bossHealthBar.root.Visible = false
		crtLayer.root.Visible = false
	end

	updateBossHealthBar()
	updatePowerRelayUI()
	refreshMatchStatusBarVisibility()
end

local function refreshSquadAndBillboards(): ()
	local localChar = LocalPlayer.Character
	local localRole = if localChar ~= nil then getStringAttr(localChar, "Role") else nil
	local localIsHunter = isHunterRole(localRole)

	local hunterPlayers: { Player } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char ~= nil and char.Parent ~= nil then
			local role = getStringAttr(char, "Role")
			if isHunterRole(role) then
				table.insert(hunterPlayers, player)
			elseif player ~= LocalPlayer then
				removeDownedBillboard(player)
			end
		elseif player ~= LocalPlayer then
			removeDownedBillboard(player)
		end
	end

	table.sort(hunterPlayers, function(a: Player, b: Player): boolean
		if a == LocalPlayer then
			return false
		elseif b == LocalPlayer then
			return true
		end
		return a.Name < b.Name
	end)

	for i = 1, 4 do
		local slot = squadRows[i]
		local hunter = hunterPlayers[i]
		if hunter ~= nil and localIsHunter then
			local char = hunter.Character :: Model
			local role = getStringAttr(char, "Role") :: string
			local style = HUNTER_ROLES[role]
			local hp = math.max(0, getNumberAttr(char, "CustomHealth", 0))
			local maxHp = math.max(1, getNumberAttr(char, "MaxCustomHealth", 100))
			local ratio = math.clamp(hp / maxHp, 0, 1)
			local isDowned = getBoolAttr(char, "IsDowned")
			local isDead = getBoolAttr(char, "IsDead")
			local isContam = (hunter ~= LocalPlayer) and (getBoolAttr(char, "HasBeenDowned") or getBoolAttr(char, "IsContaminated"))

			local pct = math.floor(ratio * 100 + 0.5)
			local displayName = if hunter == LocalPlayer then hunter.DisplayName .. " (YOU)" else hunter.DisplayName
			local barCol = if isDead then AEM_UIKit.MUTED_BONE elseif isDowned or ratio < 0.35 then AEM_UIKit.OXIDIZED_CRIMSON elseif ratio < 0.65 then AEM_UIKit.MUTED_GOLD else AEM_UIKit.PALE_IVORY

			slot.assignedPlayer = hunter
			slot.rawTag = style.tag
			slot.rawName = displayName
			slot.rawPct = pct
			slot.isDead = isDead
			slot.isDownedActive = isDowned
			slot.isContaminated = isContam
			slot.pip.BackgroundColor3 = if isDead then AEM_UIKit.MUTED_BONE elseif isDowned then AEM_UIKit.OXIDIZED_CRIMSON else style.accent
			slot.rowFrame.Visible = true
			slot.hpBar.setRatio(if isDead then 0 else ratio, barCol)

			if isDead then
				slot.rowLabel.Text = string.format("%s · %s", style.tag, displayName)
				slot.rowLabel.TextColor3 = AEM_UIKit.MUTED_BONE
				slot.pctLabel.Text = "DEAD"
				slot.pctLabel.TextColor3 = AEM_UIKit.MUTED_BONE
				slot.pctLabel.Visible = true
				slot.downedBadge.Visible = false
				if hunter ~= LocalPlayer then
					removeDownedBillboard(hunter)
				end
			elseif isDowned then
				local bleed = math.max(0, math.ceil(getNumberAttr(char, "BleedoutRemaining", 0)))
				slot.rowLabel.Text = string.format("%s · %s", style.tag, displayName)
				slot.rowLabel.TextColor3 = AEM_UIKit.OXIDIZED_CRIMSON
				slot.pctLabel.Visible = false
				slot.downedBadge.Visible = true
				slot.downedBadge.Text = string.format("DOWN %ds", bleed)
				if hunter ~= LocalPlayer then
					ensureDownedBillboard(hunter, char)
					local bb = downedBillboards[hunter]
					if bb ~= nil then
						bb.label.Text = string.format("SOS %ds · %s", bleed, string.upper(hunter.DisplayName))
					end
				end
			else
				slot.rowLabel.Text = string.format("%s · %s", style.tag, displayName)
				slot.rowLabel.TextColor3 = if hunter == LocalPlayer then AEM_UIKit.PALE_GOLD else AEM_UIKit.PALE_IVORY
				slot.pctLabel.Text = string.format("%d%%", pct)
				slot.pctLabel.TextColor3 = barCol
				slot.pctLabel.Visible = true
				slot.downedBadge.Visible = false
				if hunter ~= LocalPlayer then
					removeDownedBillboard(hunter)
				end
			end
		else
			slot.assignedPlayer = nil
			slot.rowFrame.Visible = false
			slot.downedBadge.Visible = false
			slot.isDownedActive = false
			slot.isContaminated = false
			if hunter ~= nil and hunter ~= LocalPlayer then
				removeDownedBillboard(hunter)
			end
		end
	end
end

local lastKnownMonsterHP: number? = nil
local lastKnownMonsterArmor: number? = nil

local function evaluateGlobalMonsterStage(character: Model): ()
	if getStringAttr(character, "Role") ~= "Monster" then
		lastMonsterStageByChar[character] = nil
		return
	end

	local mHp = getNumberAttr(character, "CustomHealth", 0)
	local mAr = getNumberAttr(character, "Armor", 0)
	if (lastKnownMonsterHP ~= nil and mHp < lastKnownMonsterHP) or (lastKnownMonsterArmor ~= nil and mAr < lastKnownMonsterArmor) then
		monsterHitFlashUntil = os.clock() + 0.18
	end
	lastKnownMonsterHP = mHp
	lastKnownMonsterArmor = mAr

	local stageAttr = getNumberAttr(character, "Stage", 1)
	local currentStage = math.max(1, math.floor(stageAttr))
	local prevStage = lastMonsterStageByChar[character]
	lastMonsterStageByChar[character] = currentStage

	if currentStage == 1 then
		highestAnnouncedStage = 1
		updatePowerRelayUI()
		updateBossHealthBar()
		return
	end

	local effectivePrev = prevStage or highestAnnouncedStage
	if currentStage > effectivePrev and currentStage > highestAnnouncedStage then
		highestAnnouncedStage = currentStage
		if currentStage == 2 or currentStage >= 3 then
			showStageBanner(currentStage)
		end
		updatePowerRelayUI()
	elseif currentStage > highestAnnouncedStage then
		highestAnnouncedStage = currentStage
		updatePowerRelayUI()
	end
	updateBossHealthBar()
end

local function onAnyCharacterRemoved(player: Player, character: Model): ()
	local conns = charConnections[character]
	if conns ~= nil then
		clearConnections(conns)
		charConnections[character] = nil
	end
	lastMonsterStageByChar[character] = nil
	removeDownedBillboard(player)

	if player ~= LocalPlayer then
		refreshSquadAndBillboards()
	end
end

local function onAnyCharacterAdded(player: Player, character: Model): ()
	onAnyCharacterRemoved(player, character)
	local conns: { RBXScriptConnection } = {}
	charConnections[character] = conns

	table.insert(conns, character:GetAttributeChangedSignal("Role"):Connect(function()
		evaluateGlobalMonsterStage(character)
		if player == LocalPlayer then
			refreshLocalHUD()
		end
		refreshSquadAndBillboards()
	end))

	table.insert(conns, character:GetAttributeChangedSignal("Stage"):Connect(function()
		evaluateGlobalMonsterStage(character)
		refreshLocalHUD()
	end))

	for _, mAttr in ipairs({ "CustomHealth", "MaxCustomHealth", "Armor", "MaxArmor", "IsEating", "IsEvolving", "IsDead", "MonsterAction" }) do
		table.insert(conns, character:GetAttributeChangedSignal(mAttr):Connect(function()
			if getStringAttr(character, "Role") == "Monster" then
				evaluateGlobalMonsterStage(character)
				if mAttr == "IsEating" and character:GetAttribute("IsEating") == true then
					Radar.emitWave(character:GetPivot().Position, AEM_UIKit.AMBER_WIRE)
				elseif mAttr == "MonsterAction" and character:GetAttribute("MonsterAction") ~= nil then
					Radar.emitWave(character:GetPivot().Position, AEM_UIKit.BOSS_CRIMSON)
				end
			end
		end))
	end

	for _, attrName in ipairs({ "CustomHealth", "MaxCustomHealth", "IsDowned", "IsDead", "BleedoutRemaining", "HasBeenDowned", "IsContaminated" }) do
		table.insert(conns, character:GetAttributeChangedSignal(attrName):Connect(function()
			refreshSquadAndBillboards()
		end))
	end

	table.insert(conns, character.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Head" or child.Name == "HumanoidRootPart" then
			refreshSquadAndBillboards()
		end
	end))

	table.insert(conns, character.Destroying:Connect(function()
		onAnyCharacterRemoved(player, character)
	end))

	evaluateGlobalMonsterStage(character)
	refreshSquadAndBillboards()
end

local function onLocalCharacterRemoving(): ()
	clearConnections(localCharConnections)
	equippedWeaponId = ""
	isFiringVisual = false
	refreshLocalHUD()
	refreshSquadAndBillboards()
end

local function onLocalCharacterAdded(character: Model): ()
	onLocalCharacterRemoving()
	peakJetpack = CONFIG.DefaultMaxJetpack
	peakShield = CONFIG.DefaultMaxShield
	peakStamina = CONFIG.DefaultMaxStamina
	monsterCooldownEnds.LeapSmash = 0
	monsterCooldownEnds.FeralCharge = 0
	monsterCooldownEnds.AcidBreath = 0
	monsterCooldownEnds.Smell = 0
	lastMonsterActionSeen = nil

	local watchedLocalAttrs: { string } = {
		"Role",
		"CustomHealth",
		"MaxCustomHealth",
		"Armor",
		"MaxArmor",
		"IsDowned",
		"IsDead",
		"BleedoutRemaining",
		"Stage",
		"EvolutionEnergy",
		"IsEating",
		"IsEvolving",
		"IsStealth",
		"NearEvolutionNest",
		"NearestNestDist",
		"Stamina",
		"MaxStamina",
		"JetpackFuel",
		"MaxJetpackFuel",
		"PersonalShield",
		"MaxPersonalShield",
		"DomeCooldown",
		"ScannerCooldown",
		"ClassSkillCooldown",
		"ClassSkillActiveUntil",
		"SecondarySkillCooldown",
		"SecondarySkillActiveUntil",
		"MonsterAction",
	}

	for _, attrName in ipairs(watchedLocalAttrs) do
		table.insert(localCharConnections, character:GetAttributeChangedSignal(attrName):Connect(refreshLocalHUD))
	end

	table.insert(localCharConnections, character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			local wId = getStringAttr(child, "WeaponId")
			if wId ~= nil then
				equippedWeaponId = wId
				equippedWeaponMax = WEAPON_CAPS[wId] or 72
				equippedWeaponCurrent = equippedWeaponMax
			end
		end
	end))
	table.insert(localCharConnections, character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and getStringAttr(child, "WeaponId") == equippedWeaponId then
			equippedWeaponId = ""
		end
	end))

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local wId = getStringAttr(child, "WeaponId")
			if wId ~= nil then
				equippedWeaponId = wId
				equippedWeaponMax = WEAPON_CAPS[wId] or 72
				equippedWeaponCurrent = equippedWeaponMax
			end
		end
	end

	table.insert(localCharConnections, character:GetAttributeChangedSignal("Role"):Connect(refreshSquadAndBillboards))
	refreshLocalHUD()
	refreshSquadAndBillboards()
end

local function onPlayerRemoving(player: Player): ()
	local conns = playerConnections[player]
	if conns ~= nil then
		clearConnections(conns)
		playerConnections[player] = nil
	end
	if player.Character ~= nil then
		onAnyCharacterRemoved(player, player.Character)
	end
	removeDownedBillboard(player)
	refreshSquadAndBillboards()
end

local function onPlayerAdded(player: Player): ()
	onPlayerRemoving(player)
	local conns: { RBXScriptConnection } = {}
	playerConnections[player] = conns

	table.insert(conns, player.CharacterAdded:Connect(function(character: Model)
		onAnyCharacterAdded(player, character)
	end))
	table.insert(conns, player.CharacterRemoving:Connect(function(character: Model)
		onAnyCharacterRemoved(player, character)
	end))
	if player.Character ~= nil then
		onAnyCharacterAdded(player, player.Character)
	end
end

local function formatTimerMMSS(seconds: number?): string
	local secs = if typeof(seconds) == "number" then math.max(0, math.ceil(seconds)) else 0
	return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

local function formatMatchStatus(state: string, seconds: number?, extraData: { [string]: any }?): string
	if state == "Intermission" then
		return "INTERMISSION // " .. formatTimerMMSS(seconds)
	elseif state == "RoleAssignment" then
		return "ASSIGNING PROTOCOLS..."
	elseif state == "MonsterHeadStart" then
		return "VANTAGEM DO MONSTRO  ·  " .. formatTimerMMSS(seconds)
	elseif state == "ActiveHunt" then
		return "CAÇA  ·  " .. formatTimerMMSS(seconds)
	elseif state == "PostMatch" then
		local winner = if extraData ~= nil and typeof(extraData.winner) == "string" then extraData.winner else nil
		local tag = if winner == "Monster" then "CONTAINMENT BREACH" elseif winner == "Hunters" then "SPECIMEN CLEANSED" else "SESSION CLOSED"
		return string.format("%s // %s", tag, formatTimerMMSS(seconds))
	end
	if typeof(state) == "string" then
		return string.upper(state)
	end
	return "ACTIVE"
end

local toastToken = 0
local scannerActiveUntil = 0
local scannerTargetPos: Vector3? = nil

local function showRewardToast(message: string, borderColor: Color3): ()
	toastToken += 1
	local myToken = toastToken
	if rewardToastTween ~= nil then
		rewardToastTween:Cancel()
		rewardToastTween = nil
	end
	setWireBracketColor(rewardToast, borderColor)
	rewardToastLabel.TextColor3 = AEM_UIKit.IVORY_TEXT
	rewardToastLabel.Text = string.upper(message)
	rewardToast.Visible = true
	local _, nextY, stageTargetY = computeTopStackTargets()
	local targetY = math.min(390, if stageBanner.Visible then stageTargetY + 40 + 6 else nextY + 4)
	rewardToastCurrentTargetY = targetY
	rewardToastState = "in"
	rewardToast.Position = UDim2.new(0.5, 0, 0, targetY - 18)
	local tw = TweenService:Create(rewardToast, CONFIG.BannerInTween, {
		Position = UDim2.new(0.5, 0, 0, targetY),
	})
	rewardToastTween = tw
	tw.Completed:Once(function()
		if myToken == toastToken and rewardToastState == "in" then
			rewardToastState = "shown"
		end
	end)
	tw:Play()

	task.delay(5.0, function()
		if myToken ~= toastToken or not screenGui.Parent then
			return
		end
		rewardToast.Visible = false
		rewardToastState = "hidden"
	end)
end

local function refreshRoomBoostButton(gameRemotesFolder: Instance?): ()
	if gameRemotesFolder == nil then
		roomBoostFrame.Visible = false
		return
	end
	local state = gameRemotesFolder:GetAttribute("MatchState")
	local inRound = state == "MonsterHeadStart" or state == "ActiveHunt"
	roomBoostFrame.Visible = inRound
	if not inRound then
		return
	end

	local active = gameRemotesFolder:GetAttribute("RoomCoinBoostActive") == true
	if active then
		roomBoostButton.Text = "2x MARROW ACTIVE"
		roomBoostButton.TextColor3 = AEM_UIKit.AMBER_GLOW
		setWireBracketColor(roomBoostFrame, AEM_UIKit.AMBER_GLOW)
	else
		roomBoostButton.Text = "2x MARROW BOOST"
		roomBoostButton.TextColor3 = AEM_UIKit.AMBER_WIRE
		setWireBracketColor(roomBoostFrame, AEM_UIKit.AMBER_WIRE)
	end
end

-- Tag [VIP] dourada no chat moderno (TextChatService)
pcall(function()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source ~= nil then
			local sender = Players:GetPlayerByUserId(source.UserId)
			if sender ~= nil and sender:GetAttribute("IsVIP") == true then
				props.PrefixText = '<font color="#E6CA7E"><b>[VIP]</b></font> ' .. (message.PrefixText or "")
			end
		end
		return props
	end
end)

task.spawn(function()
	if ReplicatedStorage:GetAttribute("RemotesReady") ~= true then
		while ReplicatedStorage:GetAttribute("BootstrapStatus") == nil or ReplicatedStorage:GetAttribute("BootstrapStatus") == "Initializing" do
			ReplicatedStorage:GetAttributeChangedSignal("BootstrapStatus"):Wait()
		end
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local gameRemotes = if remotes ~= nil then remotes:FindFirstChild("GameRemotes") else nil
	if remotes ~= nil then
		local field = remotes:WaitForChild("HunterRemotes")
		local dome = field:WaitForChild("DeployDome") :: RemoteEvent
		local scanner = field:WaitForChild("PlanetScanner") :: RemoteEvent
		local useSkill = field:WaitForChild("UseHunterSkill") :: RemoteEvent

		local function activateClassSkill()
			local c = LocalPlayer.Character
			if not c then return end
			local role = getStringAttr(c, "Role") or ""
			local skill = classSkills[role]
			if not skill then return end
			if role == "Trapper" then scanner:FireServer() return end
			local target: Model? = nil
			if role == "Support" then
				local object: Instance? = LocalPlayer:GetMouse().Target
				while object and object ~= Workspace do
					if object:IsA("Model") and object ~= c and Players:GetPlayerFromCharacter(object) and isHunterRole(getStringAttr(object, "Role")) then
						target = object
						break
					end
					object = object.Parent
				end
			end
			useSkill:FireServer(skill.Id, target)
		end

		local function activateSecondarySkill()
			local c = LocalPlayer.Character
			if not c then return end
			local role = getStringAttr(c, "Role") or ""
			local skill = secondarySkills[role]
			if not skill then return end
			local payload: any = nil
			if role == "Medic" then
				local object: Instance? = LocalPlayer:GetMouse().Target
				while object and object ~= Workspace do
					if object:IsA("Model") and object ~= c and Players:GetPlayerFromCharacter(object) and isHunterRole(getStringAttr(object, "Role")) then
						payload = object
						break
					end
					object = object.Parent
				end
			elseif role == "Support" then
				local aim = LocalPlayer:GetMouse().UnitRay
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				local ignore: { Instance } = { c }
				local arena = Workspace:FindFirstChild("MobileArena")
				if arena then table.insert(ignore, arena) end
				params.FilterDescendantsInstances = ignore
				params.RespectCanCollide = true
				local hit = Workspace:Raycast(aim.Origin, aim.Direction * 180, params)
				payload = if hit then hit.Position else aim.Origin + aim.Direction * 180
			end
			useSkill:FireServer(skill.Id, payload)
		end

		onDomeActivated = function()
			dome:FireServer()
		end
		onClassSkillActivated = activateClassSkill
		onSecondarySkillActivated = activateSecondarySkill
		table.insert(globalConnections, Radar.togglePill.Activated:Connect(Radar.toggle))

		table.insert(globalConnections, UserInputService.InputBegan:Connect(function(key, processed)
			if processed or UserInputService:GetFocusedTextBox() or not hunterHudRoot.Visible then return end
			if key.KeyCode == Enum.KeyCode.F then dome:FireServer()
			elseif key.KeyCode == Enum.KeyCode.G then activateClassSkill()
			elseif key.KeyCode == Enum.KeyCode.Q then activateSecondarySkill()
			elseif key.KeyCode == Enum.KeyCode.R then Radar.toggle()
			elseif key.UserInputType == Enum.UserInputType.MouseButton1 and equippedWeaponId ~= "" then
				isFiringVisual = true
			end
		end))
		table.insert(globalConnections, UserInputService.InputEnded:Connect(function(key)
			if key.UserInputType == Enum.UserInputType.MouseButton1 then
				isFiringVisual = false
			end
		end))
	end

	local matchChanged = if gameRemotes ~= nil then gameRemotes:FindFirstChild("MatchStateChanged") else nil
	local updateUIRemote = if gameRemotes ~= nil then gameRemotes:FindFirstChild("UpdateUI") else nil

	if gameRemotes ~= nil then
		local initState = gameRemotes:GetAttribute("MatchState")
		if typeof(initState) == "string" then
			cachedMatchState = initState
			local initTime = gameRemotes:GetAttribute("TimeRemaining")
			local initExtra: { [string]: any } = {
				waitingForPlayers = gameRemotes:GetAttribute("WaitingForPlayers") == true,
				winner = gameRemotes:GetAttribute("Winner"),
				reason = gameRemotes:GetAttribute("WinReason"),
			}
			cachedShortTimer = formatTimerMMSS(if typeof(initTime) == "number" then initTime else nil)
			matchStatusLabel.Text = formatMatchStatus(initState, if typeof(initTime) == "number" then initTime else nil, initExtra)
			if initState == "PostMatch" and typeof(initExtra.winner) == "string" then
				triggerPostMatchScreen(initExtra.winner, if typeof(initExtra.reason) == "string" then initExtra.reason else nil)
			end
			refreshMatchStatusBarVisibility()
		end
		refreshRoomBoostButton(gameRemotes)
		table.insert(globalConnections, gameRemotes:GetAttributeChangedSignal("RoomCoinBoostActive"):Connect(function()
			refreshRoomBoostButton(gameRemotes)
		end))
		table.insert(globalConnections, gameRemotes:GetAttributeChangedSignal("MatchState"):Connect(function()
			refreshRoomBoostButton(gameRemotes)
		end))
		table.insert(globalConnections, roomBoostButton.Activated:Connect(function()
			if gameRemotes:GetAttribute("RoomCoinBoostActive") == true then
				showRewardToast("2x MARROW BOOST ALREADY ACTIVE IN SESSION.", AEM_UIKit.MUTED_GOLD)
				return
			end
			local productId = tonumber(gameRemotes:GetAttribute("RoomCoinBoostProductId")) or 0
			if productId <= 0 then
				showRewardToast("2x ROOM BOOST AWAITING PRODUCT ID.", AEM_UIKit.MUTED_BONE)
				return
			end
			MarketplaceService:PromptProductPurchase(LocalPlayer, productId)
		end))
	end

	if matchChanged ~= nil and matchChanged:IsA("RemoteEvent") then
		table.insert(globalConnections, (matchChanged :: RemoteEvent).OnClientEvent:Connect(function(state: string, timeRemaining: number?, extraData: { [string]: any }?)
			cachedMatchState = state
			cachedShortTimer = formatTimerMMSS(timeRemaining)
			matchStatusLabel.Text = formatMatchStatus(state, timeRemaining, extraData)
			refreshMatchStatusBarVisibility()
			refreshRoomBoostButton(gameRemotes)

			if state == "PostMatch" then
				local winner = if typeof(extraData) == "table" and typeof(extraData.winner) == "string"
					then extraData.winner
					elseif gameRemotes ~= nil and typeof(gameRemotes:GetAttribute("Winner")) == "string" then (gameRemotes:GetAttribute("Winner") :: string)
					else "Hunters"
				local reason = if typeof(extraData) == "table" and typeof(extraData.reason) == "string"
					then extraData.reason
					elseif gameRemotes ~= nil and typeof(gameRemotes:GetAttribute("WinReason")) == "string" then (gameRemotes:GetAttribute("WinReason") :: string)
					else ""
				if not postMatchOverlay.Visible or activePostMatchWinner ~= winner then
					triggerPostMatchScreen(winner, reason)
				end
				updatePostMatchCountdown(timeRemaining)
			elseif state == "Intermission" or state == "Lobby" or state == "Waiting" then
				activePostMatchWinner = nil
				lastMatchRewards = nil
				postMatchOverlay.Visible = false
				bossHealthBar.root.Visible = false
				highestAnnouncedStage = 1
				scannerActiveUntil = 0
				scannerTargetPos = nil
				scannerContainer.Visible = false
				Radar.clearContacts()
				table.clear(lastMonsterStageByChar)
				refreshLocalHUD()
			else
				activePostMatchWinner = nil
				lastMatchRewards = nil
				postMatchOverlay.Visible = false
				if typeof(extraData) == "table" and extraData.event == "MonsterEvolved" and typeof(extraData.stage) == "number" then
					local newStage = math.max(1, math.floor(extraData.stage))
					if newStage > highestAnnouncedStage then
						highestAnnouncedStage = newStage
						if newStage >= 2 then
							showStageBanner(newStage)
						end
						updateObjectiveDirective()
						updatePowerRelayUI()
						updateBossHealthBar()
					end
				else
					refreshLocalHUD()
				end
			end
		end))
	end

	if updateUIRemote ~= nil and updateUIRemote:IsA("RemoteEvent") then
		table.insert(globalConnections, (updateUIRemote :: RemoteEvent).OnClientEvent:Connect(function(notificationType: string, payload: { [string]: any }?)
			if notificationType == "HunterAbilityNotice" and typeof(payload) == "table" and typeof(payload.message) == "string" then
				hunterAudio.PlayLocal("AbilityDenied")
				showRewardToast(payload.message, AEM_UIKit.MUTED_GOLD)
			elseif notificationType == "ScannerEnded" then
				scannerActiveUntil = 0
				scannerTargetPos = nil
				scannerContainer.Visible = false
			elseif notificationType == "MonsterStageChanged" and typeof(payload) == "table" and typeof(payload.stage) == "number" then
				local newStage = math.max(1, math.floor(payload.stage))
				if newStage > highestAnnouncedStage then
					highestAnnouncedStage = newStage
					if newStage >= 2 then
						showStageBanner(newStage)
					end
					updateObjectiveDirective()
					updatePowerRelayUI()
				end
			elseif notificationType == "MatchRewards" and typeof(payload) == "table" then
				local gainedCoins = tonumber(payload.coins) or 0
				local gainedXP = tonumber(payload.xp) or 0
				local vipApplied = payload.vipApplied == true
				local roomBoostApplied = payload.roomBoostApplied == true
				lastMatchRewards = {
					coins = gainedCoins,
					xp = gainedXP,
					totalCoins = if typeof(payload.totalCoins) == "number" then payload.totalCoins else nil,
					totalXP = if typeof(payload.totalXP) == "number" then payload.totalXP else nil,
					won = if typeof(payload.won) == "boolean" then payload.won else nil,
					role = if typeof(payload.role) == "string" then payload.role else nil,
					vipApplied = vipApplied,
					roomBoostApplied = roomBoostApplied,
				}
				if postMatchOverlay.Visible or cachedMatchState == "PostMatch" then
					refreshPostMatchDossiers(activePostMatchWinner)
				else
					local vipTag = if vipApplied then " | VIP +50%" else ""
					local boostTag = if roomBoostApplied then " | BOOST 2x" else ""
					local resultWord = if payload.won == true then "MISSION SUCCESS" else "EXTRACTED"
					showRewardToast(string.format("%s: +%d MARROW  |  +%d XP%s%s", resultWord, gainedCoins, gainedXP, vipTag, boostTag), AEM_UIKit.AMBER_GLOW)
				end
			elseif notificationType == "RoomBoostActivated" and typeof(payload) == "table" then
				local buyer = if typeof(payload.buyerName) == "string" then payload.buyerName else "OPERATOR"
				showRewardToast(string.format("2x MARROW BOOST AUTHORIZED BY %s!", string.upper(buyer)), AEM_UIKit.PALE_GOLD)
				refreshRoomBoostButton(gameRemotes)
			elseif notificationType == "RoomBoostDeferred" and typeof(payload) == "table" then
				local msg = if typeof(payload.message) == "string" then payload.message else "BOOST QUEUED."
				showRewardToast(msg, AEM_UIKit.OXIDIZED_CRIMSON)
			elseif notificationType == "SuddenDeathTriggered" and typeof(payload) == "table" then
				updatePowerRelayUI()
				updateObjectiveDirective()
				showRewardToast("SUDDEN DEATH · A.E.M. ANCHOR RELAY SHATTERED · REVIVES OFFLINE", AEM_UIKit.OXIDIZED_CRIMSON)
			elseif notificationType == "ApexFeastBuff" then
				showRewardToast("RED GOLIATH CONSUMED · +4 BIOMASS BARS · +10% SPEED (20s)", AEM_UIKit.PALE_GOLD)
			elseif notificationType == "BrineGullAlert" and typeof(payload) == "table" and typeof(payload.position) == "Vector3" then
				if hunterHudRoot.Visible then
					Radar.emitWave(payload.position :: Vector3, AEM_UIKit.PALE_GOLD)
				end
				showRewardToast("COASTAL FLOCK SCATTERED · ACOUSTIC BEARING LOGGED", AEM_UIKit.MUTED_BONE)
			elseif notificationType == "PlanetScanner" or notificationType == "PlanetScannerPulse" or notificationType == "ScannerReveal" then
				local data = if typeof(payload) == "table" then payload else {}
				local wasScanning = os.clock() < scannerActiveUntil
				local dur = if typeof(data.duration) == "number" then math.max(0.5, data.duration) else 5
				scannerActiveUntil = os.clock() + (if typeof(data.endsAt) == "number" then math.max(0, data.endsAt - Workspace:GetServerTimeNow()) else dur)
				scannerTargetPos = if typeof(data.targetPosition) == "Vector3" then data.targetPosition else nil
				if typeof(scannerTargetPos) == "Vector3" then
					Radar.emitWave(scannerTargetPos :: Vector3, AEM_UIKit.PALE_GOLD)
				end
				if not wasScanning then hunterAudio.PlayLocal("ScannerPingLocal") end
			end
		end))
	end
end)

local function findMonsterPosition(): Vector3?
	local m = findMonsterModel()
	if m ~= nil then
		local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		if root ~= nil and root:IsA("BasePart") then
			return (root :: BasePart).Position
		end
	end
	return scannerTargetPos
end

table.insert(globalConnections, Workspace.ChildAdded:Connect(function(child: Instance)
	if hunterHudRoot.Visible and (child.Name == "MonsterImpact" or child.Name == "PulsoOlfativo" or child.Name == "GullScatterBeacon") and child:IsA("BasePart") then
		Radar.emitWave((child :: BasePart).Position, AEM_UIKit.BOSS_CRIMSON)
	elseif monsterHudRoot.Visible and child.Name == "PulsoOlfativo" and child:IsA("BasePart") then
		monsterCooldownEnds.Smell = os.clock() + MonsterFieldDeck.SmellCooldown
	elseif child:IsA("Model") and Players:GetPlayerFromCharacter(child) == nil and getStringAttr(child, "Role") == "Monster" then
		cachedWorkspaceMonsterDummy = child
		updateBossHealthBar()
	end
end))

do
	local slowAccumulator = 0
	local radarAccumulator = 0
	local glitchSeed = 0

	table.insert(globalConnections, RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()

	if hunterAberrationFlash > 0 then
		hunterAberrationFlash = math.max(0, hunterAberrationFlash - dt * 2.2)
	end
	local bpm = tonumber(LocalPlayer:GetAttribute("ClientBPM")) or 82
	if hunterHudRoot.Visible then
		local panicRatio = if bpm >= 150 then math.clamp((bpm - 150) / 40, 0, 0.75) * ((math.sin(now * 9) + 1) * 0.5) else 0
		crtLayer.setAberration(math.max(hunterAberrationFlash, panicRatio))
	else
		crtLayer.setAberration(0)
	end

	repositionTopStack(false)

	local cam = Workspace.CurrentCamera
	if hunterHudRoot.Visible and cam ~= nil then
		local look = cam.CFrame.LookVector
		local deg = math.floor((-math.deg(math.atan2(-look.X, -look.Z)) + 360) % 360 + 0.5)
		local cardinal = if deg < 45 or deg >= 315 then "N" elseif deg < 135 then "E" elseif deg < 225 then "S" else "W"
		local nextCard = if cardinal == "N" then "E" elseif cardinal == "E" then "S" elseif cardinal == "S" then "W" else "N"
		local prevCard = if cardinal == "N" then "W" elseif cardinal == "W" then "S" elseif cardinal == "S" then "E" else "N"
		compassText.Text = string.format("%s  ·  %03d° %s  ·  %s   |   %s", prevCard, deg, cardinal, nextCard, cachedShortTimer)

		local localChar = LocalPlayer.Character
		local root = if localChar ~= nil then localChar:FindFirstChild("HumanoidRootPart") else nil
		local moveSpeed = if root ~= nil and root:IsA("BasePart") then (root :: BasePart).AssemblyLinearVelocity.Magnitude else 0
		local spread = 8 + math.clamp(moveSpeed * 0.22, 0, 8) + (if isFiringVisual then 4 else 0)
		crosshairTicks.top.Position = UDim2.new(0.5, 0, 0.5, -spread)
		crosshairTicks.bot.Position = UDim2.new(0.5, 0, 0.5, spread)
		crosshairTicks.left.Position = UDim2.new(0.5, -spread, 0.5, 0)
		crosshairTicks.right.Position = UDim2.new(0.5, spread, 0.5, 0)
		local hitActive = now < monsterHitFlashUntil
		local crossColor = if hitActive then AEM_UIKit.AMBER_WIRE else AEM_UIKit.IVORY_TEXT
		for _, t in ipairs(crossTicks) do
			t.BackgroundColor3 = crossColor
		end

		local rootPos: Vector3? = if root ~= nil and root:IsA("BasePart") then (root :: BasePart).Position else nil
		Radar.updateFrame(dt, now, look, rootPos)
	end

	if monsterHudRoot.Visible then
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local gameRemotes = if remotes ~= nil then remotes:FindFirstChild("GameRemotes") else nil
		local activeUntil = if gameRemotes ~= nil then getNumberAttr(gameRemotes, "DomeActiveUntil", 0) else 0
		local remDome = activeUntil - Workspace:GetServerTimeNow()
		if remDome > 0 then
			domeSuppressionOverlay.Visible = true
			domeWarnLabel.Text = string.format("CONTAINMENT DOME INHIBITED · %ds", math.ceil(remDome))
		else
			domeSuppressionOverlay.Visible = false
		end
		repositionTopStack(false)

		if monsterChannelKind == "Evolving" then
			local elapsed = math.min(5.0, now - monsterChannelStartedAt)
			monsterEvolvePrompt.Text = string.format("METAMORPHOSIS  ·  %.1f / 5.0s", elapsed)
			monsterChannelBar.setRatio(elapsed / 5.0, AEM_UIKit.PALE_GOLD)
		elseif monsterChannelKind == "Eating" then
			local elapsed = math.min(2.5, now - monsterChannelStartedAt)
			monsterEvolvePrompt.Text = string.format("DEVOURING BIOMASS  ·  %.1f / 2.5s", elapsed)
			monsterChannelBar.setRatio(elapsed / 2.5, AEM_UIKit.MUTED_GOLD)
		end

		local mChar = LocalPlayer.Character
		local hum = if mChar ~= nil then mChar:FindFirstChildOfClass("Humanoid") else nil
		local spread = 11
		if mChar ~= nil and (getStringAttr(mChar, "MonsterAction") == "LeapSmash" or (hum ~= nil and hum.FloorMaterial == Enum.Material.Air)) then
			spread = 20
		elseif now < monsterHitFlashUntil then
			spread = 7
		end
		for _, blade in ipairs(clawBlades) do
			blade.frame.Position = UDim2.new(0.5, blade.dirX * spread, 0.5, blade.dirY * spread)
			blade.frame.BackgroundColor3 = if now < monsterHitFlashUntil then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.IVORY_TEXT
		end

		local mPos = if mChar ~= nil then mChar:GetPivot().Position else Vector3.zero
		local sFactor = math.max(0.1, getHudScale())
		local vpSize = if cam ~= nil then cam.ViewportSize else Vector2.new(1280, 720)
		local logicalW = vpSize.X / sFactor
		local logicalH = vpSize.Y / sFactor
		local markerIdx = 0
		if cam ~= nil then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= LocalPlayer and p.Character ~= nil and isHunterRole(getStringAttr(p.Character, "Role")) and not getBoolAttr(p.Character, "IsDead") then
					local hRoot = p.Character:FindFirstChild("HumanoidRootPart")
					if hRoot ~= nil and hRoot:IsA("BasePart") then
						markerIdx += 1
						if markerIdx <= #hiveMarkers then
							local mk = hiveMarkers[markerIdx]
							local worldPt = (hRoot :: BasePart).Position + Vector3.new(0, 3.4, 0)
							local vp, onScreen = cam:WorldToViewportPoint(worldPt)
							local dist = ((hRoot :: BasePart).Position - mPos).Magnitude
							local estBpm = math.clamp(math.round(84 + math.clamp(1 - dist / 120, 0, 1) * 78 + (if getBoolAttr(p.Character, "IsDowned") then 35 else 0)), 80, 192)
							local x = (if onScreen then vp.X else vpSize.X - vp.X) / sFactor
							local y = (if onScreen then vp.Y else vpSize.Y - vp.Y) / sFactor
							local tagCol = if estBpm >= 140 then AEM_UIKit.AMBER_GLOW else AEM_UIKit.BOSS_CRIMSON
							mk.frame.Position = UDim2.fromOffset(math.clamp(x, 76, math.max(80, logicalW - 76)), math.clamp(y, 76, math.max(96, logicalH - 120)))
							mk.label.Text = string.format("♥ %d", estBpm)
							mk.label.TextColor3 = tagCol
							mk.topTick.BackgroundColor3 = tagCol
							mk.botTick.BackgroundColor3 = tagCol
							mk.frame.Visible = true
						end
					end
				end
			end
		end
		for j = markerIdx + 1, #hiveMarkers do
			hiveMarkers[j].frame.Visible = false
		end
	end

	if os.clock() < scannerActiveUntil then
		local localChar = LocalPlayer.Character
		local localRole = if localChar ~= nil then getStringAttr(localChar, "Role") else nil
		local targetPos = findMonsterPosition()
		if isHunterRole(localRole) and cachedMatchState == "ActiveHunt" and targetPos ~= nil and cam ~= nil then
			local delta = targetPos - cam.CFrame.Position
			local flatDelta = Vector3.new(delta.X, 0, delta.Z)
			local look = cam.CFrame.LookVector
			local flatForward = Vector3.new(look.X, 0, look.Z)
			if flatForward.Magnitude > 0.001 and flatDelta.Magnitude > 0.001 then
				flatForward = flatForward.Unit
				local flatRight = Vector3.new(-flatForward.Z, 0, flatForward.X)
				local dir = flatDelta.Unit
				local angle = math.atan2(dir:Dot(flatRight), dir:Dot(flatForward))
				scannerArrow.Position = UDim2.fromOffset(98 + math.sin(angle) * 84, 98 - math.cos(angle) * 84)
				scannerArrow.Rotation = math.deg(angle)
				scannerDistLabel.Text = string.format("SPECIMEN · %d STUDS", math.floor(delta.Magnitude + 0.5))
				scannerContainer.Visible = true
			end
		else
			scannerContainer.Visible = false
		end
	elseif scannerContainer.Visible then
		scannerContainer.Visible = false
	end

	radarAccumulator += dt
	if hunterHudRoot.Visible and radarAccumulator >= 0.45 then
		radarAccumulator = 0
		local mChar = findMonsterModel()
		if mChar ~= nil and not getBoolAttr(mChar, "IsStealth") then
			local mRoot = mChar:FindFirstChild("HumanoidRootPart")
			if mRoot ~= nil and mRoot:IsA("BasePart") then
				if (mRoot :: BasePart).AssemblyLinearVelocity.Magnitude > 22 or getBoolAttr(mChar, "IsEating") then
					Radar.emitWave((mRoot :: BasePart).Position, AEM_UIKit.MUTED_GOLD)
				end
			end
		end

		Radar.refreshPill(now)
	end

	slowAccumulator += dt
	if slowAccumulator < 0.2 then
		return
	end
	slowAccumulator = 0
	glitchSeed += 1

	local char = LocalPlayer.Character
	updateBossHealthBar()

	if hunterHudRoot.Visible and char ~= nil then
		refreshFieldTiles(char)

		local isDowned = getBoolAttr(char, "IsDowned")
		local isDead = getBoolAttr(char, "IsDead")
		if not isDead and not isDowned then
			if bpm >= 160 then
				hunterBpmLbl.Text = string.format("%d BPM!", bpm)
				hunterBpmLbl.TextColor3 = AEM_UIKit.BOSS_CRIMSON
			elseif bpm >= 120 then
				hunterBpmLbl.Text = string.format("%d BPM", bpm)
				hunterBpmLbl.TextColor3 = AEM_UIKit.AMBER_GLOW
			else
				hunterBpmLbl.Text = string.format("%d BPM", bpm)
				hunterBpmLbl.TextColor3 = AEM_UIKit.AMBER_SOFT
			end
		end

		local roleStr = getStringAttr(char, "Role") or ""
		local style = HUNTER_ROLES[roleStr]
		local classNameText = if style ~= nil then style.displayName else string.upper(roleStr)
		if equippedWeaponId ~= "" then
			if isFiringVisual and not isDead and not isDowned then
				equippedWeaponCurrent = math.max(0, equippedWeaponCurrent - 2)
				lastShotTelemetryAt = now
			elseif now - lastShotTelemetryAt > 0.7 and equippedWeaponCurrent < equippedWeaponMax then
				equippedWeaponCurrent = math.min(equippedWeaponMax, equippedWeaponCurrent + 6)
			end
			local ammoRatio = equippedWeaponCurrent / math.max(1, equippedWeaponMax)
			classAmmoLabel.Text = string.format("CLASS: %s // AMMO: %d / %d", classNameText, equippedWeaponCurrent, equippedWeaponMax)
			classAmmoLabel.TextColor3 = if ammoRatio <= 0.25 then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.IVORY_TEXT
		else
			classAmmoLabel.Text = string.format("CLASS: %s // HOLSTERED", classNameText)
			classAmmoLabel.TextColor3 = AEM_UIKit.AMBER_SOFT
		end

		for i = 1, 4 do
			local slot = squadRows[i]
			if slot.rowFrame.Visible and not slot.isDead then
				if slot.isContaminated and (glitchSeed % 7 == 0) then
					slot.rowLabel.Text = string.format("%s · %s", slot.rawTag, AEM_UIKit.corruptName(slot.rawName, glitchSeed))
					slot.rowLabel.TextColor3 = AEM_UIKit.AMBER_WIRE
				elseif not slot.isDownedActive then
					slot.rowLabel.Text = string.format("%s · %s", slot.rawTag, slot.rawName)
					slot.rowLabel.TextColor3 = if slot.assignedPlayer == LocalPlayer then AEM_UIKit.AMBER_GLOW else AEM_UIKit.IVORY_TEXT
				end
			end
		end
	end

	if monsterHudRoot.Visible and char ~= nil then
		local function updateMonsterCdBadge(badge: MonsterFieldDeck.Slot, endAt: number, totalCd: number, reqStam: number, curStam: number)
			local rem = endAt - now
			if rem > 0.1 then
				badge.setState(string.format("%d s", math.ceil(rem)), math.clamp(1 - rem / math.max(1, totalCd), 0, 1), false)
			elseif reqStam > 0 and curStam < reqStam then
				badge.setState("Vigor", math.clamp(curStam / reqStam, 0, 1), false)
			else
				badge.setState("Pronta", 1, true)
			end
		end

		fieldSlots.ClawSlash.setState(if getStringAttr(char,"MonsterAction")=="ClawSlash" then "Ativa" else "Pronta",1,true)
		local mStam = math.max(0, getNumberAttr(char, "Stamina", 0))
		updateMonsterCdBadge(fieldSlots.LeapSmash, monsterCooldownEnds.LeapSmash, 6, 22, mStam)
		updateMonsterCdBadge(fieldSlots.FeralCharge, monsterCooldownEnds.FeralCharge, 8, 30, mStam)
		updateMonsterCdBadge(fieldSlots.AcidBreath, monsterCooldownEnds.AcidBreath, 9, 0, mStam)
		updateMonsterCdBadge(fieldSlots.Smell, monsterCooldownEnds.Smell, MonsterFieldDeck.SmellCooldown, 0, mStam)

		if getBoolAttr(char, "IsEating") then
			local elapsed = math.min(2.5, now - monsterChannelStartedAt)
			fieldSlots.Eat.setState("Ativa", math.clamp(elapsed / 2.5, 0, 1), true)
		else
			fieldSlots.Eat.setState("Segure", 1, true)
		end

		local mStage = math.clamp(math.floor(getNumberAttr(char, "Stage", 1)), 1, 3)
		local mEnergy = math.clamp(getNumberAttr(char, "EvolutionEnergy", 0), 0, 100)
		if mStage >= 3 then
			fieldSlots.Evolve.setState("Máximo", 1, false)
		elseif getBoolAttr(char, "IsEvolving") then
			local elapsed = math.min(5.0, now - monsterChannelStartedAt)
			fieldSlots.Evolve.setState("Ativa", math.clamp(elapsed / 5.0, 0, 1), true)
		elseif mEnergy >= 100 then
			local near = getBoolAttr(char,"NearEvolutionNest")
			fieldSlots.Evolve.setState(if near then "Segure" else "Ninho", 1, near)
		else
			fieldSlots.Evolve.setState(string.format("%d%%", math.floor(mEnergy)), math.clamp(mEnergy / 100, 0, 1), false)
		end

		if getBoolAttr(char, "IsStealth") then
			fieldSlots.Stealth.setState("Ativa", 1, true)
		else
			fieldSlots.Stealth.setState("Segure", 1, true)
		end

		local mHum = char:FindFirstChildOfClass("Humanoid")
		local mAction = getStringAttr(char, "MonsterAction")
		if mAction == "Climb" then
			fieldSlots.Climb.setState("Ativa", 1, true)
		elseif mStam < 14 then
			fieldSlots.Climb.setState("Vigor", math.clamp(mStam / 14, 0, 1), false)
		elseif mHum ~= nil and mHum.FloorMaterial == Enum.Material.Air then
			fieldSlots.Climb.setState("Pronta", 1, true)
		else
			fieldSlots.Climb.setState("No ar", 1, true)
		end
	end

	local pulse = (math.sin(now * 6.5) + 1) * 0.5
	for _, slot in ipairs(squadRows) do
		if slot.isDownedActive then
			slot.downedBadge.TextTransparency = pulse * 0.35
		end
	end
	for _, entry in pairs(downedBillboards) do
		for _, child in ipairs(entry.wireFrame:GetChildren()) do
			if child:IsA("Frame") and not string.find(child.Name, "_Glow", 1, true) then
				child.BackgroundTransparency = 0.08 + pulse * 0.45
			end
		end
	end
end))
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

table.insert(globalConnections, Players.PlayerAdded:Connect(onPlayerAdded))
table.insert(globalConnections, Players.PlayerRemoving:Connect(onPlayerRemoving))
table.insert(globalConnections, LocalPlayer.CharacterAdded:Connect(onLocalCharacterAdded))
table.insert(globalConnections, LocalPlayer.CharacterRemoving:Connect(onLocalCharacterRemoving))
table.insert(globalConnections, playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == "MonsterControls" and child:IsA("ScreenGui") then
		(child :: ScreenGui).Enabled = false
	end
end))

if LocalPlayer.Character ~= nil then
	onLocalCharacterAdded(LocalPlayer.Character)
end

bindPowerRelay()

screenGui.Destroying:Connect(function()
	clearConnections(globalConnections)
	clearConnections(localCharConnections)
	clearConnections(relayConnections)
	for player, conns in pairs(playerConnections) do
		clearConnections(conns)
		playerConnections[player] = nil
	end
	for char, conns in pairs(charConnections) do
		clearConnections(conns)
		charConnections[char] = nil
	end
	for player in pairs(downedBillboards) do
		removeDownedBillboard(player)
	end
end)
