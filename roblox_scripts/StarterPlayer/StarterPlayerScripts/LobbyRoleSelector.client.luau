

--!strict
--[[
	PROJECT ABYSS | LobbyRoleSelector.client.lua
	Location: StarterPlayer/StarterPlayerScripts/LobbyRoleSelector.client.lua

	Kairos-09 Biometric Terminal (#FF9000 Amber Wireframe Suite):
	- Translucent void-glass surfaces (#0C0906, 0.72-0.88 transparency), #FF9000 amber wire brackets, and crisp high-DPI BuilderSans + RobotoMono telemetry.
	- Clean top telemetry + compact bottom command dock preserving the panoramic Stasis Chamber vista.
	- 4+1 formation: 4 Hunter operator dossiers + isolated Specimen Monster dossier.
	- Preserves 100% of MatchStateChanged, UpdateUI, SelectRolePreference, RoleTerminalPrompt, attribute signals, hotkeys, and GamePass contracts.
]]

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AEM_UIKit = require(ReplicatedStorage:WaitForChild("AEM_UIKit"))

local LocalPlayer = Players.LocalPlayer
local LOG_PREFIX = "[PROJECT ABYSS][LobbyRoleSelector]"

local CONFIG = {
	GuiName = "ProjectAbyss_LobbyRoleSelector",
	ClickDebounceSeconds = 0.45,
	ConfirmationTimeoutSeconds = 4.0,
	PanelTweenInfo = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

type RoleCardSpec = {
	roleKey: string,
	slotTag: string,
	hotkeyLabel: string,
	title: string,
	subtitle: string,
	description: string,
	kitSummary: string,
	accent: Color3,
}

local HUNTER_SLOT_SPECS: { RoleCardSpec } = {
	{
		roleKey = "Trapper",
		slotTag = "SLOT 01",
		hotkeyLabel = "[4]",
		title = "TRACKER",
		subtitle = "CONTAINMENT FIELD",
		description = "Tracks specimen signatures with Planet Scanner and deploys the Static Containment Dome.",
		kitSummary = "HARPOON [Q] · SCANNER [G]\nDOME STAGE [F] · GAUSS SMG",
		accent = AEM_UIKit.AMBER_WIRE,
	},
	{
		roleKey = "Assault",
		slotTag = "SLOT 02",
		hotkeyLabel = "[2]",
		title = "ASSAULT",
		subtitle = "HEAVY ORDNANCE",
		description = "Sustains heavy plasma suppression and absorbs frontal damage via personal Aegis Matrix.",
		kitSummary = "AEGIS MATRIX [Q] · ION RIFLE [G]\nDOME STAGE [F] · PLASMA RIFLE",
		accent = AEM_UIKit.IVORY_TEXT,
	},
	{
		roleKey = "Support",
		slotTag = "SLOT 03",
		hotkeyLabel = "[5]",
		title = "SUPPORT",
		subtitle = "TACTICAL SHIELDING",
		description = "Projects ballistic shields onto allies and calls down precision Orbital Barrage strikes.",
		kitSummary = "ORBITAL [Q] · SHIELD PROJ [G]\nDOME STAGE [F] · LASER CUTTER",
		accent = AEM_UIKit.AMBER_GLOW,
	},
	{
		roleKey = "Medic",
		slotTag = "SLOT 04",
		hotkeyLabel = "[3]",
		title = "MEDIC",
		subtitle = "BIO-TRIAGE UNIT",
		description = "Stabilizes squad vitals via tethered Med Beam and emergency Heal Pulse triage.",
		kitSummary = "MED BEAM [Q] · HEAL PULSE [G]\nDOME STAGE [F] · BIO-CARBINE",
		accent = AEM_UIKit.AMBER_SOFT,
	},
}

local MONSTER_SPEC: RoleCardSpec = {
	roleKey = "Monster",
	slotTag = "SPECIMEN",
	hotkeyLabel = "[1]",
	title = "MONSTER",
	subtitle = "STAGE I · THE STALKER",
	description = "Devour prey biomass, evolve through Stage III, and shatter the A.E.M. Power Relay.",
	kitSummary = "LEAP [1] · CHARGE [2] · ACID [3]\nSMELL PULSE [Q] · DEVOUR [E]\nEVOLVE [V] · STEALTH [CTRL]",
	accent = AEM_UIKit.BOSS_CRIMSON,
}

local VALID_ROLE_BY_KEY: { [string]: RoleCardSpec } = {
	Monster = MONSTER_SPEC,
}
for _, spec in ipairs(HUNTER_SLOT_SPECS) do
	VALID_ROLE_BY_KEY[spec.roleKey] = spec
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local existingGui = playerGui:FindFirstChild(CONFIG.GuiName)
if existingGui ~= nil then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = CONFIG.GuiName
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 8
screenGui.Enabled = false
screenGui.Parent = playerGui

local crtLayer = AEM_UIKit.createCRTScanlineLayer(screenGui, 2)
crtLayer.root.Visible = false

local scaledCanvas, getLobbyScale = AEM_UIKit.createScaledCanvas(screenGui, "LobbyScaledCanvas", 6)

local backdropButton = Instance.new("TextButton")
backdropButton.Name = "ModalBackdrop"
backdropButton.Size = UDim2.fromScale(1, 1)
backdropButton.BackgroundColor3 = AEM_UIKit.VOID_GLASS
backdropButton.BackgroundTransparency = 0.56
backdropButton.BorderSizePixel = 0
backdropButton.Text = ""
backdropButton.AutoButtonColor = false
backdropButton.Visible = false
backdropButton.ZIndex = 3
backdropButton.Parent = screenGui

-- ============================================================================
-- TOP TELEMETRY BAR (CLEARS COREGUI INSET, KAIROS-09 WIREFRAME HEADER)
-- ============================================================================
local topBar = Instance.new("Frame")
topBar.Name = "TopTelemetryBar"
topBar.Position = UDim2.new(0, 24, 0, 46)
topBar.Size = UDim2.new(1, -48, 0, 60)
topBar.BackgroundTransparency = 1
topBar.BorderSizePixel = 0
topBar.ZIndex = 6
topBar.Parent = scaledCanvas

local topLeftCard = AEM_UIKit.createScrimPanel({
	name = "TopRegistryCard",
	parent = topBar,
	position = UDim2.fromScale(0, 0),
	size = UDim2.fromOffset(440, 60),
	bgColor = AEM_UIKit.VOID_GLASS,
	peakAlpha = 0.82,
	fadeDirection = "LeftToRight",
	accentEdge = "Left",
	accentColor = AEM_UIKit.AMBER_WIRE,
	accentThickness = 1.5,
	zIndex = 6,
})

local registryLogo = AEM_UIKit.createInvertedTriangleLogo(topLeftCard, 36, AEM_UIKit.AMBER_WIRE)
registryLogo.Position = UDim2.fromOffset(10, 12)
registryLogo.ZIndex = 8

local topTitleLbl = AEM_UIKit.makeMonoLabel({
	name = "TerminalTitle",
	parent = topLeftCard,
	size = UDim2.new(1, -66, 0, 24),
	position = UDim2.fromOffset(54, 7),
	text = "A.E.M.  //  KAIROS-09 REGISTRY",
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	textSize = 18,
	zIndex = 8,
})

local topSectorLbl = AEM_UIKit.makeMonoLabel({
	name = "SectorStatus",
	parent = topLeftCard,
	size = UDim2.new(1, -66, 0, 18),
	position = UDim2.fromOffset(54, 33),
	text = "CONTAINMENT SECTOR  ·  INTEGRITY 94%",
	color = AEM_UIKit.AMBER_SOFT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.SemiBold,
	textSize = 12,
	zIndex = 8,
})

local topRightCard = AEM_UIKit.createScrimPanel({
	name = "TopTelemetryCard",
	parent = topBar,
	anchorPoint = Vector2.new(1, 0),
	position = UDim2.fromScale(1, 0),
	size = UDim2.fromOffset(380, 60),
	bgColor = AEM_UIKit.VOID_GLASS,
	peakAlpha = 0.82,
	fadeDirection = "RightToLeft",
	accentEdge = "Right",
	accentColor = AEM_UIKit.AMBER_WIRE,
	accentThickness = 1.5,
	zIndex = 6,
})

local pingBpmLbl = AEM_UIKit.makeMonoLabel({
	name = "PingAndBpm",
	parent = topRightCard,
	size = UDim2.new(1, -24, 0, 24),
	position = UDim2.fromOffset(12, 7),
	text = "PING --ms  ·  78 BPM",
	color = AEM_UIKit.IVORY_TEXT,
	alignX = Enum.TextXAlignment.Right,
	textSize = 14,
	zIndex = 8,
})

local currencyLbl = AEM_UIKit.makeMonoLabel({
	name = "CurrencyHeader",
	parent = topRightCard,
	size = UDim2.new(1, -24, 0, 18),
	position = UDim2.fromOffset(12, 33),
	text = "MARROW 0  ·  CORES 0",
	color = AEM_UIKit.AMBER_WIRE,
	alignX = Enum.TextXAlignment.Right,
	textSize = 13,
	zIndex = 8,
})

local lastTopY = -1
local function updateTopInsetPosition(): ()
	local topInset = AEM_UIKit.getLogicalTopInset(getLobbyScale)
	local targetY = if topInset > 0 then topInset + 6 else 40
	if targetY ~= lastTopY then
		lastTopY = targetY
		topBar.Position = UDim2.new(0, 24, 0, targetY)
	end
end
updateTopInsetPosition()

-- ============================================================================
-- COMPACT BOTTOM COMMAND DOCK (PRESERVES STASIS CHAMBER VISTA)
-- ============================================================================
local dockBar = AEM_UIKit.createWireBracketFrame(scaledCanvas, {
	name = "LobbyTacticalDock",
	parent = scaledCanvas,
	anchorPoint = Vector2.new(0.5, 1),
	position = UDim2.new(0.5, 0, 1, -14),
	size = UDim2.fromOffset(960, 56),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.80,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.25,
	bracketLength = 14,
	mode = "LeftRight",
	glow = true,
	zIndex = 6,
})

local dockBottomRule = Instance.new("Frame")
dockBottomRule.Name = "DockBottomRule"
dockBottomRule.Size = UDim2.new(1, 0, 0, 1)
dockBottomRule.Position = UDim2.new(0, 0, 1, -1)
dockBottomRule.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
dockBottomRule.BackgroundTransparency = 0.30
dockBottomRule.BorderSizePixel = 0
dockBottomRule.ZIndex = 7
dockBottomRule.Parent = dockBar

local dockTimerLabel = AEM_UIKit.makeMonoLabel({
	name = "DockTimer",
	parent = dockBar,
	size = UDim2.fromScale(0.26, 0.44),
	position = UDim2.fromScale(0.020, 0.08),
	text = "AWAITING SQUAD (1/5)",
	color = AEM_UIKit.AMBER_WIRE,
	textSize = 13,
	zIndex = 8,
})

local dockRoleLabel = AEM_UIKit.makeMonoLabel({
	name = "DockRole",
	parent = dockBar,
	size = UDim2.fromScale(0.26, 0.40),
	position = UDim2.fromScale(0.020, 0.52),
	text = "LOCKED SLOT: NONE",
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Medium,
	textSize = 13,
	zIndex = 8,
})

local function createDockCmdButton(name: string, text: string, posX: number, width: number, accent: Color3): (TextButton, UIStroke)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.fromScale(width, 0.72)
	btn.Position = UDim2.fromScale(posX, 0.14)
	btn.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	btn.BackgroundTransparency = 0.82
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = text
	btn.TextColor3 = accent
	btn.ZIndex = 8
	btn.Parent = dockBar
	local stroke = AEM_UIKit.applyBevelStroke(btn, AEM_UIKit.HAIRLINE_DIM, 1, 0.35)
	AEM_UIKit.styleButtonText(btn, Enum.FontWeight.SemiBold, 9, 15, 0.84, true)
	AEM_UIKit.createWireBracketFrame(btn, {
		name = "BtnBrackets",
		parent = btn,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		bgTransparency = 1,
		bracketColor = accent,
		bracketLength = 7,
		bracketThickness = 1,
		bracketTransparency = 0.30,
		mode = "Corners",
		glow = false,
		zIndex = 9,
	})
	return btn, stroke
end

local btnTabDeploy, strokeTabDeploy = createDockCmdButton("F1_DeployButton", "[F1]  DEPLOY LOADOUT", 0.295, 0.225, AEM_UIKit.AMBER_GLOW)
local btnTabBio, strokeTabBio = createDockCmdButton("F2_BioArchivesButton", "[F2]  BIO-ARCHIVES", 0.530, 0.225, AEM_UIKit.IVORY_TEXT)
local btnTabPass, strokeTabPass = createDockCmdButton("F3_PassButton", "[F3]  CLEARANCE PASS", 0.765, 0.220, AEM_UIKit.AMBER_WIRE)

-- ============================================================================
-- MAIN KAIROS-09 TERMINAL MODAL CONTAINER
-- ============================================================================
local mainFrame = AEM_UIKit.createWireBracketFrame(scaledCanvas, {
	name = "IntermissionContainer",
	parent = scaledCanvas,
	anchorPoint = Vector2.new(0.5, 0.5),
	position = UDim2.fromScale(0.5, 0.50),
	size = UDim2.fromOffset(1460, 660),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.80,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.5,
	bracketLength = 18,
	mode = "Corners",
	glow = true,
	clipsDescendants = false,
	zIndex = 10,
})
AEM_UIKit.applyBevelStroke(mainFrame, AEM_UIKit.HAIRLINE_DIM, 1, 0.45)
mainFrame.Visible = false

local modalHeader = Instance.new("Frame")
modalHeader.Name = "ModalHeader"
modalHeader.Size = UDim2.fromOffset(1416, 54)
modalHeader.Position = UDim2.fromOffset(22, 14)
modalHeader.BackgroundColor3 = AEM_UIKit.VOID_GLASS
modalHeader.BackgroundTransparency = 0.84
modalHeader.BorderSizePixel = 0
modalHeader.ZIndex = 12
modalHeader.Parent = mainFrame

local modalHeaderRule = Instance.new("Frame")
modalHeaderRule.Size = UDim2.new(1, 0, 0, 1)
modalHeaderRule.Position = UDim2.new(0, 0, 1, -1)
modalHeaderRule.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
modalHeaderRule.BackgroundTransparency = 0.35
modalHeaderRule.BorderSizePixel = 0
modalHeaderRule.ZIndex = 13
modalHeaderRule.Parent = modalHeader

local modalTitleLabel = AEM_UIKit.makeMonoLabel({
	name = "ModalTitle",
	parent = modalHeader,
	size = UDim2.fromOffset(880, 42),
	position = UDim2.fromOffset(12, 6),
	text = "SQUAD FORMATION  //  PROTOCOL 6-7-9",
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	textSize = 22,
	zIndex = 13,
})

local timerBadge = Instance.new("TextLabel")
timerBadge.Name = "TimerBadge"
timerBadge.Size = UDim2.fromOffset(310, 38)
timerBadge.Position = UDim2.fromOffset(960, 8)
timerBadge.BackgroundColor3 = AEM_UIKit.VOID_GLASS
timerBadge.BackgroundTransparency = 0.82
timerBadge.BorderSizePixel = 0
timerBadge.FontFace = AEM_UIKit.FONT_FACE_BOLD
timerBadge.Text = "AWAITING: 1/5"
timerBadge.TextColor3 = AEM_UIKit.AMBER_GLOW
timerBadge.TextScaled = false
timerBadge.TextSize = 15
timerBadge.ZIndex = 13
timerBadge.Parent = modalHeader
AEM_UIKit.applyTextContrast(timerBadge, 0.84)
AEM_UIKit.applyBevelStroke(timerBadge, AEM_UIKit.HAIRLINE_DIM, 1, 0.45)
AEM_UIKit.createWireBracketFrame(timerBadge, {
	name = "TimerBrackets",
	parent = timerBadge,
	size = UDim2.fromScale(1, 1),
	position = UDim2.fromScale(0, 0),
	bgTransparency = 1,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketLength = 8,
	bracketThickness = 1.1,
	mode = "LeftRight",
	glow = false,
	zIndex = 14,
})

local closeModalButton = Instance.new("TextButton")
closeModalButton.Name = "CloseModalButton"
closeModalButton.Size = UDim2.fromOffset(122, 38)
closeModalButton.Position = UDim2.fromOffset(1282, 8)
closeModalButton.BackgroundColor3 = Color3.fromRGB(36, 12, 10)
closeModalButton.BackgroundTransparency = 0.78
closeModalButton.BorderSizePixel = 0
closeModalButton.AutoButtonColor = false
closeModalButton.Text = "[X] ESC"
closeModalButton.TextColor3 = AEM_UIKit.IVORY_TEXT
closeModalButton.ZIndex = 13
closeModalButton.Parent = modalHeader
AEM_UIKit.applyBevelStroke(closeModalButton, AEM_UIKit.BOSS_CRIMSON, 1, 0.25)
AEM_UIKit.styleButtonText(closeModalButton, Enum.FontWeight.Bold, 13, 14, 0.84, false)
AEM_UIKit.createWireBracketFrame(closeModalButton, {
	name = "CloseBrackets",
	parent = closeModalButton,
	size = UDim2.fromScale(1, 1),
	position = UDim2.fromScale(0, 0),
	bgTransparency = 1,
	bracketColor = AEM_UIKit.BOSS_CRIMSON,
	bracketLength = 7,
	bracketThickness = 1,
	mode = "Corners",
	glow = false,
	zIndex = 14,
})

-- PAGE 1: DEPLOY LOADOUT (4 HUNTER SLOTS + 1 SPECIMEN MONSTER SLOT)
local deployPage = Instance.new("Frame")
deployPage.Name = "Page_DeployLoadout"
deployPage.Size = UDim2.fromOffset(1416, 568)
deployPage.Position = UDim2.fromOffset(22, 78)
deployPage.BackgroundTransparency = 1
deployPage.ZIndex = 11
deployPage.Parent = mainFrame

local hunterBoard = Instance.new("Frame")
hunterBoard.Name = "HunterSlotsBoard"
hunterBoard.Size = UDim2.fromOffset(1042, 500)
hunterBoard.Position = UDim2.fromOffset(0, 0)
hunterBoard.BackgroundTransparency = 1
hunterBoard.ZIndex = 11
hunterBoard.Parent = deployPage

local bulkheadDivider = Instance.new("Frame")
bulkheadDivider.Name = "BulkheadDivider"
bulkheadDivider.Size = UDim2.fromOffset(1, 500)
bulkheadDivider.Position = UDim2.fromOffset(1056, 0)
bulkheadDivider.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
bulkheadDivider.BackgroundTransparency = 0.45
bulkheadDivider.BorderSizePixel = 0
bulkheadDivider.ZIndex = 12
bulkheadDivider.Parent = deployPage

type SlotCardWidget = {
	spec: RoleCardSpec,
	button: TextButton,
	stroke: UIStroke,
	statusLabel: TextLabel,
	statusFill: Frame,
	statusStroke: UIStroke,
	isHovered: boolean,
}

local cardsByRole: { [string]: SlotCardWidget } = {}
local connections: { RBXScriptConnection } = {}
local pendingRole: string? = nil
local confirmedRole: string? = nil
local lastSentAt = 0
local pendingRequestId = 0

local selectRoleRemote: RemoteEvent? = nil
local matchStateRemote: RemoteEvent? = nil
local updateUIRemote: RemoteEvent? = nil

local function buildWireframeSilhouette(parent: Instance, color: Color3, roleKey: string, zIndex: number, boxW: number, boxH: number): { Frame }
	local parts: { Frame } = {}
	local cx = boxW * 0.5
	local cy = boxH * 0.5
	local center = Vector2.new(cx, cy)

	local function pushList(list: { Frame })
		for _, f in ipairs(list) do
			table.insert(parts, f)
		end
	end

	local function addDiamond(szPx: number, col: Color3, alpha: number, nameOpt: string?)
		local f = Instance.new("Frame")
		f.Name = nameOpt or "WireDiamond"
		f.Size = UDim2.fromOffset(szPx, szPx)
		f.Position = UDim2.fromOffset(cx, cy)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Rotation = 45
		f.BackgroundColor3 = col
		f.BackgroundTransparency = alpha
		f.BorderSizePixel = 0
		f.ZIndex = zIndex + 2
		f.Parent = parent
		table.insert(parts, f)
		return f
	end

	-- Subtle calibration axes
	table.insert(parts, AEM_UIKit.drawLinePx(parent, "CalAxisH", Vector2.new(cx - 58, cy), Vector2.new(cx + 58, cy), 1, AEM_UIKit.HAIRLINE_DIM, 0.72, zIndex, false))
	table.insert(parts, AEM_UIKit.drawLinePx(parent, "CalAxisV", Vector2.new(cx, cy - 38), Vector2.new(cx, cy + 38), 1, AEM_UIKit.HAIRLINE_DIM, 0.72, zIndex, false))

	if roleKey == "Monster" then
		-- Fractured Oblivion arcs + rotated diamond + vertical fissure + SpecimenGlandCore
		pushList(AEM_UIKit.drawArcPx(parent, "MonsterArcL", center, 34, 115, 245, 16, 1.6, AEM_UIKit.BOSS_CRIMSON, 0.14, zIndex + 1, true))
		pushList(AEM_UIKit.drawArcPx(parent, "MonsterArcR", center, 34, -65, 65, 16, 1.6, AEM_UIKit.BOSS_CRIMSON, 0.14, zIndex + 1, true))
		pushList(AEM_UIKit.drawPolylinePx(parent, "MonsterDiamond", {
			Vector2.new(cx, cy - 26),
			Vector2.new(cx + 26, cy),
			Vector2.new(cx, cy + 26),
			Vector2.new(cx - 26, cy),
		}, 1.3, AEM_UIKit.AMBER_WIRE, 0.22, zIndex + 1, true, false))
		table.insert(parts, AEM_UIKit.drawLinePx(parent, "MonsterSlit", Vector2.new(cx, cy - 34), Vector2.new(cx, cy + 34), 1.6, AEM_UIKit.AMBER_GLOW, 0.12, zIndex + 2, true))
		addDiamond(10, AEM_UIKit.AMBER_GLOW, 0.10, "SpecimenGlandCore")
	elseif roleKey == "Trapper" then
		-- Concentric acoustic tracking reticle
		pushList(AEM_UIKit.drawArcPx(parent, "TrackerRingOuter", center, 32, 0, 360, 24, 1.4, color, 0.16, zIndex + 1, true))
		pushList(AEM_UIKit.drawArcPx(parent, "TrackerRingInner", center, 18, 0, 360, 18, 1.1, AEM_UIKit.HAIRLINE_DIM, 0.24, zIndex + 1, false))
		table.insert(parts, AEM_UIKit.drawLinePx(parent, "TrackerDiagA", Vector2.new(cx - 10, cy - 10), Vector2.new(cx + 10, cy + 10), 1.2, AEM_UIKit.AMBER_GLOW, 0.14, zIndex + 2, false))
		table.insert(parts, AEM_UIKit.drawLinePx(parent, "TrackerDiagB", Vector2.new(cx - 10, cy + 10), Vector2.new(cx + 10, cy - 10), 1.2, AEM_UIKit.AMBER_GLOW, 0.14, zIndex + 2, false))
		addDiamond(7, AEM_UIKit.AMBER_GLOW, 0.10, "TrackerCore")
	elseif roleKey == "Assault" then
		-- Octagonal tactical frame + twin ballistic chevrons
		local octPts: { Vector2 } = {}
		for i = 0, 7 do
			local ang = math.rad(22.5 + i * 45)
			table.insert(octPts, Vector2.new(cx + math.cos(ang) * 30, cy + math.sin(ang) * 30))
		end
		pushList(AEM_UIKit.drawPolylinePx(parent, "AssaultOct", octPts, 1.2, AEM_UIKit.HAIRLINE_DIM, 0.30, zIndex + 1, true, false))
		pushList(AEM_UIKit.drawPolylinePx(parent, "AssaultChevTop", {
			Vector2.new(cx - 22, cy + 2),
			Vector2.new(cx, cy - 16),
			Vector2.new(cx + 22, cy + 2),
		}, 1.8, color, 0.10, zIndex + 2, false, true))
		pushList(AEM_UIKit.drawPolylinePx(parent, "AssaultChevBot", {
			Vector2.new(cx - 16, cy + 14),
			Vector2.new(cx, cy + 1),
			Vector2.new(cx + 16, cy + 14),
		}, 1.5, AEM_UIKit.AMBER_WIRE, 0.20, zIndex + 2, false, false))
	elseif roleKey == "Support" then
		-- Hexagonal shield projection node + inner diamond
		local hexPts: { Vector2 } = {}
		for i = 0, 5 do
			local ang = math.rad(-90 + i * 60)
			table.insert(hexPts, Vector2.new(cx + math.cos(ang) * 32, cy + math.sin(ang) * 32))
		end
		pushList(AEM_UIKit.drawPolylinePx(parent, "SupportHex", hexPts, 1.4, color, 0.16, zIndex + 1, true, true))
		pushList(AEM_UIKit.drawPolylinePx(parent, "SupportInner", {
			Vector2.new(cx, cy - 20),
			Vector2.new(cx + 20, cy),
			Vector2.new(cx, cy + 20),
			Vector2.new(cx - 20, cy),
		}, 1.2, AEM_UIKit.AMBER_WIRE, 0.26, zIndex + 1, true, false))
		addDiamond(8, AEM_UIKit.AMBER_GLOW, 0.12, "SupportCore")
	else
		-- Medic: precision surgical cross inside biometric ring
		pushList(AEM_UIKit.drawArcPx(parent, "MedicRing", center, 30, 0, 360, 24, 1.2, AEM_UIKit.HAIRLINE_DIM, 0.24, zIndex + 1, false))
		table.insert(parts, AEM_UIKit.drawLinePx(parent, "MedicCrossH", Vector2.new(cx - 20, cy), Vector2.new(cx + 20, cy), 1.8, color, 0.12, zIndex + 2, true))
		table.insert(parts, AEM_UIKit.drawLinePx(parent, "MedicCrossV", Vector2.new(cx, cy - 20), Vector2.new(cx, cy + 20), 1.8, color, 0.12, zIndex + 2, true))
		addDiamond(6, AEM_UIKit.AMBER_WIRE, 0.10, "MedicCore")
	end
	return parts
end

local footerFrame, footerStroke = AEM_UIKit.createBevelPanel({
	name = "DeployFooter",
	parent = deployPage,
	position = UDim2.fromOffset(0, 514),
	size = UDim2.fromOffset(1416, 54),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.82,
	strokeColor = AEM_UIKit.HAIRLINE_DIM,
	strokeThickness = 1,
	strokeTransparency = 0.35,
	accentEdge = "Top",
	accentColor = AEM_UIKit.AMBER_WIRE,
	zIndex = 12,
})
AEM_UIKit.createWireBracketFrame(footerFrame, {
	name = "FooterBrackets",
	parent = footerFrame,
	size = UDim2.fromScale(1, 1),
	position = UDim2.fromScale(0, 0),
	bgTransparency = 1,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketLength = 10,
	bracketThickness = 1.1,
	mode = "LeftRight",
	glow = false,
	zIndex = 13,
})

local preferenceIndicator = AEM_UIKit.makeMonoLabel({
	name = "CurrentPreference",
	parent = footerFrame,
	size = UDim2.fromOffset(480, 40),
	position = UDim2.fromOffset(18, 7),
	text = "CONFIRMED PREF: NONE",
	color = AEM_UIKit.IVORY_TEXT,
	textSize = 15,
	zIndex = 13,
})

local feedbackLabel = AEM_UIKit.makeMonoLabel({
	name = "ServerFeedback",
	parent = footerFrame,
	size = UDim2.fromOffset(880, 40),
	position = UDim2.fromOffset(518, 7),
	text = "SELECT OPERATOR DOSSIER TO REGISTER PREFERENCE  ·  MATCHMAKER ROTATES ROLES",
	color = AEM_UIKit.AMBER_SOFT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Medium,
	alignX = Enum.TextXAlignment.Right,
	textSize = 14,
	zIndex = 13,
})

local function refreshCardVisuals(): ()
	for roleKey, card in pairs(cardsByRole) do
		local isConfirmed = confirmedRole == roleKey
		local isPending = pendingRole == roleKey and not isConfirmed
		local isMonster = roleKey == "Monster"

		if isConfirmed then
			card.stroke.Color = if isMonster then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.AMBER_GLOW
			card.stroke.Thickness = 1.8
			card.stroke.Transparency = 0.08
			card.statusLabel.Text = if isMonster then "LOCKED IN ✓" else "READY ✓"
			card.statusLabel.TextColor3 = AEM_UIKit.IVORY_TEXT
			AEM_UIKit.applyTextContrast(card.statusLabel, 0.78)
			card.statusFill.BackgroundColor3 = if isMonster then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.AMBER_WIRE
			card.statusFill.BackgroundTransparency = 0.72
			card.statusStroke.Color = AEM_UIKit.AMBER_GLOW
			card.statusStroke.Thickness = 1.6
			card.statusStroke.Transparency = 0.08
		elseif isPending then
			card.stroke.Color = AEM_UIKit.AMBER_WIRE
			card.stroke.Thickness = 1.6
			card.stroke.Transparency = 0.15
			card.statusLabel.Text = "TRANSMITTING..."
			card.statusLabel.TextColor3 = AEM_UIKit.AMBER_GLOW
			AEM_UIKit.applyTextContrast(card.statusLabel, 0.80)
			card.statusFill.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
			card.statusFill.BackgroundTransparency = 0.78
			card.statusStroke.Color = AEM_UIKit.AMBER_WIRE
			card.statusStroke.Thickness = 1.4
			card.statusStroke.Transparency = 0.15
		elseif card.isHovered then
			card.stroke.Color = card.spec.accent
			card.stroke.Thickness = 1.4
			card.stroke.Transparency = 0.18
			card.statusLabel.Text = "SELECT  " .. card.spec.hotkeyLabel
			card.statusLabel.TextColor3 = AEM_UIKit.IVORY_TEXT
			AEM_UIKit.applyTextContrast(card.statusLabel, 0.84)
			card.statusFill.BackgroundColor3 = AEM_UIKit.CHARCOAL_ELEVATED
			card.statusFill.BackgroundTransparency = 0.76
			card.statusStroke.Color = card.spec.accent
			card.statusStroke.Thickness = 1.2
			card.statusStroke.Transparency = 0.22
		else
			card.stroke.Color = if isMonster then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.HAIRLINE_DIM
			card.stroke.Thickness = 1
			card.stroke.Transparency = if isMonster then 0.30 else 0.45
			card.statusLabel.Text = if isMonster then "STANDBY  " .. card.spec.hotkeyLabel else "AVAILABLE  " .. card.spec.hotkeyLabel
			card.statusLabel.TextColor3 = AEM_UIKit.AMBER_SOFT
			AEM_UIKit.applyTextContrast(card.statusLabel, 0.84)
			card.statusFill.BackgroundColor3 = AEM_UIKit.VOID_GLASS
			card.statusFill.BackgroundTransparency = 0.84
			card.statusStroke.Color = if isMonster then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.HAIRLINE_DIM
			card.statusStroke.Thickness = 1
			card.statusStroke.Transparency = 0.45
		end
	end

	if confirmedRole ~= nil and VALID_ROLE_BY_KEY[confirmedRole] ~= nil then
		local spec = VALID_ROLE_BY_KEY[confirmedRole]
		preferenceIndicator.Text = "CONFIRMED PREF: " .. spec.title
		preferenceIndicator.TextColor3 = AEM_UIKit.AMBER_GLOW
		dockRoleLabel.Text = "LOCKED SLOT: " .. spec.title
		dockRoleLabel.TextColor3 = spec.accent
	elseif pendingRole ~= nil and VALID_ROLE_BY_KEY[pendingRole] ~= nil then
		local spec = VALID_ROLE_BY_KEY[pendingRole]
		preferenceIndicator.Text = "TRANSMITTING: " .. spec.title .. "..."
		preferenceIndicator.TextColor3 = AEM_UIKit.AMBER_WIRE
		dockRoleLabel.Text = "SELECTING: " .. spec.title
		dockRoleLabel.TextColor3 = AEM_UIKit.AMBER_WIRE
	else
		preferenceIndicator.Text = "CONFIRMED PREF: NONE"
		preferenceIndicator.TextColor3 = AEM_UIKit.IVORY_TEXT
		dockRoleLabel.Text = "LOCKED SLOT: NONE"
		dockRoleLabel.TextColor3 = AEM_UIKit.AMBER_SOFT
	end
end

local function onCardClicked(roleKey: string): ()
	if selectRoleRemote == nil then
		feedbackLabel.Text = "LINK INITIALIZING — RETRY DEPLOY SIGNAL"
		feedbackLabel.TextColor3 = AEM_UIKit.BOSS_CRIMSON
		return
	end

	local now = os.clock()
	if now - lastSentAt < CONFIG.ClickDebounceSeconds then
		return
	end
	lastSentAt = now

	pendingRole = roleKey
	pendingRequestId += 1
	local requestId = pendingRequestId

	feedbackLabel.Text = "TRANSMITTING PREFERENCE TO KAIROS-09 MATCHMAKER..."
	feedbackLabel.TextColor3 = AEM_UIKit.AMBER_WIRE
	footerStroke.Color = AEM_UIKit.AMBER_WIRE
	refreshCardVisuals()

	selectRoleRemote:FireServer(roleKey)

	task.delay(CONFIG.ConfirmationTimeoutSeconds, function()
		if not screenGui.Parent or pendingRequestId ~= requestId then
			return
		end
		if pendingRole == roleKey and confirmedRole ~= roleKey then
			feedbackLabel.Text = "SIGNAL SENT  ·  AWAITING SERVER CONFIRMATION"
			feedbackLabel.TextColor3 = AEM_UIKit.AMBER_SOFT
			footerStroke.Color = AEM_UIKit.HAIRLINE_DIM
		end
	end)
end

local function buildSlotButton(parent: Instance, spec: RoleCardSpec, pos: UDim2, size: UDim2, cardW: number, isMonster: boolean)
	local btn = Instance.new("TextButton")
	btn.Name = "Card_" .. spec.roleKey
	btn.Position = pos
	btn.Size = size
	btn.BackgroundColor3 = AEM_UIKit.CHARCOAL
	btn.BackgroundTransparency = 0.82
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ClipsDescendants = true
	btn.Text = ""
	btn.ZIndex = 12
	btn.Parent = parent

	local stroke = AEM_UIKit.applyBevelStroke(btn, if isMonster then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.HAIRLINE_DIM, 1, if isMonster then 0.30 else 0.45)

	AEM_UIKit.createWireBracketFrame(btn, {
		name = "CardBrackets",
		parent = btn,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		bgTransparency = 1,
		bracketColor = if isMonster then AEM_UIKit.BOSS_CRIMSON else spec.accent,
		bracketLength = 11,
		bracketThickness = 1.25,
		bracketTransparency = 0.24,
		mode = "Corners",
		glow = false,
		zIndex = 15,
	})

	local topAccent = Instance.new("Frame")
	topAccent.Name = "TopAccent"
	topAccent.Size = UDim2.new(1, 0, 0, 2)
	topAccent.BackgroundColor3 = if isMonster then AEM_UIKit.BOSS_CRIMSON else spec.accent
	topAccent.BackgroundTransparency = if isMonster then 0.10 else 0.20
	topAccent.BorderSizePixel = 0
	topAccent.ZIndex = 16
	topAccent.Parent = btn

	local innerW = cardW - 30
	AEM_UIKit.makeMonoLabel({
		name = "SlotTag",
		parent = btn,
		size = UDim2.fromOffset(innerW - 60, 20),
		position = UDim2.fromOffset(15, 14),
		text = spec.slotTag,
		color = AEM_UIKit.AMBER_SOFT,
		textSize = 12,
		zIndex = 17,
	})

	AEM_UIKit.makeMonoLabel({
		name = "HotkeyTag",
		parent = btn,
		size = UDim2.fromOffset(56, 20),
		position = UDim2.fromOffset(cardW - 71, 14),
		text = spec.hotkeyLabel,
		color = spec.accent,
		alignX = Enum.TextXAlignment.Right,
		textSize = 14,
		zIndex = 17,
	})

	AEM_UIKit.makeMonoLabel({
		name = "RoleTitle",
		parent = btn,
		size = UDim2.fromOffset(innerW, 28),
		position = UDim2.fromOffset(15, 36),
		text = spec.title,
		color = AEM_UIKit.IVORY_TEXT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Bold,
		textSize = 22,
		zIndex = 17,
	})

	AEM_UIKit.makeMonoLabel({
		name = "RoleSubtitle",
		parent = btn,
		size = UDim2.fromOffset(innerW, 18),
		position = UDim2.fromOffset(15, 66),
		text = spec.subtitle,
		color = spec.accent,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.SemiBold,
		textSize = 12,
		zIndex = 17,
	})

	local wireH = 122
	local wireBox = Instance.new("Frame")
	wireBox.Name = "WireframePreview"
	wireBox.Size = UDim2.fromOffset(innerW, wireH)
	wireBox.Position = UDim2.fromOffset(15, 92)
	wireBox.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	wireBox.BackgroundTransparency = 0.86
	wireBox.BorderSizePixel = 0
	wireBox.ZIndex = 13
	wireBox.Parent = btn
	AEM_UIKit.applyBevelStroke(wireBox, AEM_UIKit.HAIRLINE_DIM, 1, 0.45)
	AEM_UIKit.createWireBracketFrame(wireBox, {
		name = "PreviewBrackets",
		parent = wireBox,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		bgTransparency = 1,
		bracketColor = if isMonster then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.HAIRLINE_DIM,
		bracketLength = 7,
		bracketThickness = 1,
		mode = "Corners",
		glow = false,
		zIndex = 14,
	})
	buildWireframeSilhouette(wireBox, spec.accent, spec.roleKey, 14, innerW, wireH)

	AEM_UIKit.makeMonoLabel({
		name = "KitSummary",
		parent = btn,
		size = UDim2.fromOffset(innerW, 82),
		position = UDim2.fromOffset(15, 224),
		text = spec.description,
		color = AEM_UIKit.IVORY_TEXT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Medium,
		wrapped = true,
		alignY = Enum.TextYAlignment.Top,
		textSize = 14,
		zIndex = 17,
	})

	AEM_UIKit.makeMonoLabel({
		name = "KitKeysLine",
		parent = btn,
		size = UDim2.fromOffset(innerW, 102),
		position = UDim2.fromOffset(15, 314),
		text = spec.kitSummary,
		color = AEM_UIKit.AMBER_SOFT,
		wrapped = true,
		alignY = Enum.TextYAlignment.Top,
		textSize = 12,
		zIndex = 17,
	})

	local statusFill = Instance.new("Frame")
	statusFill.Name = "ReadinessBar"
	statusFill.Size = UDim2.fromOffset(innerW, 48)
	statusFill.Position = UDim2.fromOffset(15, 434)
	statusFill.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	statusFill.BackgroundTransparency = 0.84
	statusFill.BorderSizePixel = 0
	statusFill.ZIndex = 17
	statusFill.Parent = btn
	local statusStroke = AEM_UIKit.applyBevelStroke(statusFill, if isMonster then AEM_UIKit.BOSS_CRIMSON else AEM_UIKit.HAIRLINE_DIM, 1, 0.45)

	local statusLabel = AEM_UIKit.makeMonoLabel({
		name = "StateLabel",
		parent = statusFill,
		size = UDim2.fromScale(0.92, 0.86),
		position = UDim2.fromScale(0.04, 0.07),
		text = "AVAILABLE",
		color = AEM_UIKit.AMBER_SOFT,
		alignX = Enum.TextXAlignment.Center,
		textSize = 14,
		zIndex = 18,
	})

	local widget: SlotCardWidget = {
		spec = spec,
		button = btn,
		stroke = stroke,
		statusLabel = statusLabel,
		statusFill = statusFill,
		statusStroke = statusStroke,
		isHovered = false,
	}
	cardsByRole[spec.roleKey] = widget

	table.insert(connections, btn.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		widget.isHovered = true
		refreshCardVisuals()
	end))
	table.insert(connections, btn.MouseLeave:Connect(function()
		widget.isHovered = false
		refreshCardVisuals()
	end))
	table.insert(connections, btn.Activated:Connect(function()
		onCardClicked(spec.roleKey)
	end))
end

for idx, spec in ipairs(HUNTER_SLOT_SPECS) do
	local xPx = (idx - 1) * 264
	buildSlotButton(hunterBoard, spec, UDim2.fromOffset(xPx, 0), UDim2.fromOffset(250, 500), 250, false)
end

buildSlotButton(deployPage, MONSTER_SPEC, UDim2.fromOffset(1071, 0), UDim2.fromOffset(345, 500), 345, true)

-- ============================================================================
-- PAGE 2: BIO-ARCHIVES (THE VIVISECTION / GENE FORGE 3D WIREFRAME)
-- ============================================================================
local bioPage = Instance.new("Frame")
bioPage.Name = "Page_BioArchives"
bioPage.Size = UDim2.fromOffset(1416, 568)
bioPage.Position = UDim2.fromOffset(22, 78)
bioPage.BackgroundTransparency = 1
bioPage.Visible = false
bioPage.ZIndex = 11
bioPage.Parent = mainFrame

local viewportBox = AEM_UIKit.createWireBracketFrame(bioPage, {
	name = "GeneForgeViewportBox",
	parent = bioPage,
	position = UDim2.fromOffset(0, 0),
	size = UDim2.fromOffset(736, 568),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.80,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.25,
	bracketLength = 16,
	mode = "Corners",
	glow = true,
	zIndex = 12,
})
AEM_UIKit.applyBevelStroke(viewportBox, AEM_UIKit.HAIRLINE_DIM, 1, 0.45)

local viewportTopRule = Instance.new("Frame")
viewportTopRule.Name = "TopAccentRule"
viewportTopRule.Size = UDim2.new(1, 0, 0, 1)
viewportTopRule.Position = UDim2.fromOffset(0, 0)
viewportTopRule.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
viewportTopRule.BackgroundTransparency = 0.25
viewportTopRule.BorderSizePixel = 0
viewportTopRule.ZIndex = 13
viewportTopRule.Parent = viewportBox

local vpFrame = Instance.new("ViewportFrame")
vpFrame.Name = "SpecimenWireframe3D"
vpFrame.Size = UDim2.fromOffset(300, 500)
vpFrame.Position = UDim2.fromOffset(218, 52)
vpFrame.BackgroundTransparency = 1
vpFrame.Ambient = Color3.fromRGB(160, 110, 48)
vpFrame.LightColor = Color3.fromRGB(255, 204, 120)
vpFrame.LightDirection = Vector3.new(-0.4, -0.6, -0.7)
vpFrame.ZIndex = 13
vpFrame.Parent = viewportBox

local vpWorld = Instance.new("WorldModel")
vpWorld.Parent = vpFrame
local vpCam = Instance.new("Camera")
vpCam.CFrame = CFrame.lookAt(Vector3.new(0, 1.90, 18.0), Vector3.new(0, 1.90, 0))
vpCam.FieldOfView = 36
vpCam.Parent = vpFrame
vpFrame.CurrentCamera = vpCam

-- Kairos-09 anatomical rig: charcoal-basalt chassis + amber wireframe ribs + glowing Onyx core
local rigModel = Instance.new("Model")
rigModel.Name = "VivisectionWireRig"
local function addStrut(name: string, size: Vector3, cf: CFrame, col: Color3, shape: Enum.PartType?, mat: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = col
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	if shape ~= nil then
		p.Shape = shape
	end
	p.Parent = rigModel
	return p
end

for v = 0, 6 do
	addStrut("Vertebra_" .. tostring(v), Vector3.new(0.42, 0.32, 0.42), CFrame.new(0, -1.0 + v * 0.70, 0), AEM_UIKit.CHARCOAL_ELEVATED, nil, Enum.Material.Metal)
end
for r = 1, 4 do
	local y = 0.55 + r * 0.56
	local w = 2.35 - math.abs(r - 2.5) * 0.30
	addStrut("RibL_" .. tostring(r), Vector3.new(w, 0.08, 0.11), CFrame.new(-w * 0.42, y, 0.30) * CFrame.Angles(0, math.rad(24), math.rad(-14)), AEM_UIKit.AMBER_WIRE)
	addStrut("RibR_" .. tostring(r), Vector3.new(w, 0.08, 0.11), CFrame.new(w * 0.42, y, 0.30) * CFrame.Angles(0, math.rad(-24), math.rad(14)), AEM_UIKit.AMBER_WIRE)
end
addStrut("CranialNode", Vector3.new(0.95, 1.10, 1.15), CFrame.new(0, 3.65, 0.22) * CFrame.Angles(math.rad(14), 0, 0), AEM_UIKit.IVORY_TEXT, nil, Enum.Material.SmoothPlastic)
addStrut("CrestBladeL", Vector3.new(0.12, 1.65, 0.20), CFrame.new(-0.62, 4.30, -0.25) * CFrame.Angles(math.rad(-20), 0, math.rad(-24)), AEM_UIKit.AMBER_GLOW, nil, Enum.Material.Metal)
addStrut("CrestBladeR", Vector3.new(0.12, 1.65, 0.20), CFrame.new(0.62, 4.30, -0.25) * CFrame.Angles(math.rad(-20), 0, math.rad(24)), AEM_UIKit.AMBER_GLOW, nil, Enum.Material.Metal)
addStrut("OnyxGlandCore", Vector3.new(0.92, 1.02, 0.92), CFrame.new(0, 1.85, 0.30), AEM_UIKit.AMBER_GLOW, Enum.PartType.Ball, Enum.Material.SmoothPlastic)
addStrut("ClavicleAxis", Vector3.new(3.8, 0.13, 0.16), CFrame.new(0, 2.78, 0), AEM_UIKit.IVORY_TEXT, nil, Enum.Material.Metal)
addStrut("TendonArmL", Vector3.new(0.14, 2.55, 0.14), CFrame.new(-1.95, 1.48, 0.18) * CFrame.Angles(math.rad(12), 0, math.rad(-10)), AEM_UIKit.AMBER_WIRE, nil, Enum.Material.Metal)
addStrut("TendonArmR", Vector3.new(0.14, 2.55, 0.14), CFrame.new(1.95, 1.48, 0.18) * CFrame.Angles(math.rad(12), 0, math.rad(10)), AEM_UIKit.AMBER_WIRE, nil, Enum.Material.Metal)
rigModel.Parent = vpWorld

AEM_UIKit.makeMonoLabel({
	name = "GeneForgeLabel",
	parent = viewportBox,
	size = UDim2.fromOffset(700, 24),
	position = UDim2.fromOffset(18, 12),
	text = "THE VIVISECTION  //  SPECIMEN ANATOMICAL SCHEMATIC",
	color = AEM_UIKit.AMBER_GLOW,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	textSize = 15,
	zIndex = 15,
})

local CALLOUT_NODES = {
	{
		id = "NODE 01 · CRANIAL SENSORIUM",
		pos = UDim2.fromOffset(16, 72),
		leaderFrom = Vector2.new(210, 106),
		leaderTo = Vector2.new(250, 106),
		info = "Optical receptor array and cardiac echolocation capable of tracking squad heartbeats through bulkheads.",
		spec = "RANGE: 120 STUDS  ·  DETECTION: CARDIAC BPM",
	},
	{
		id = "NODE 02 · THORACIC CARAPACE",
		pos = UDim2.fromOffset(526, 152),
		leaderFrom = Vector2.new(526, 186),
		leaderTo = Vector2.new(486, 186),
		info = "Layered onyx-basalt armor plating engineered to absorb sustained plasma and Gauss ballistic impact.",
		spec = "ARMOR SCALING: 600 / 1200 / 2000 BY STAGE",
	},
	{
		id = "NODE 03 · ONYX GLAND CORE",
		pos = UDim2.fromOffset(16, 356),
		leaderFrom = Vector2.new(210, 390),
		leaderTo = Vector2.new(250, 390),
		info = "Viscous bio-secretion core accumulating devoured prey biomass to trigger stage metamorphosis.",
		spec = "THRESHOLD: 100% BIO  ·  CHANNEL: HOLD [V] 5.0s",
	},
	{
		id = "NODE 04 · TENDON ACTUATORS",
		pos = UDim2.fromOffset(526, 436),
		leaderFrom = Vector2.new(526, 470),
		leaderTo = Vector2.new(486, 470),
		info = "Biomechanical pistons powering ballistic leaps, kinetic charges, and corrosive acid projection.",
		spec = "LEAP [1] 6s  ·  CHARGE [2] 8s  ·  ACID BREATH [3] 9s",
	},
}

local rightBioPanel = AEM_UIKit.createWireBracketFrame(bioPage, {
	name = "BioArchivesRight",
	parent = bioPage,
	position = UDim2.fromOffset(752, 0),
	size = UDim2.fromOffset(664, 568),
	bgColor = AEM_UIKit.CHARCOAL,
	bgTransparency = 0.80,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.25,
	bracketLength = 16,
	mode = "Corners",
	glow = true,
	zIndex = 12,
})
AEM_UIKit.applyBevelStroke(rightBioPanel, AEM_UIKit.HAIRLINE_DIM, 1, 0.45)

local rightBioLeftRule = Instance.new("Frame")
rightBioLeftRule.Name = "LeftAccentRule"
rightBioLeftRule.Size = UDim2.new(0, 1, 1, 0)
rightBioLeftRule.Position = UDim2.fromOffset(0, 0)
rightBioLeftRule.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
rightBioLeftRule.BackgroundTransparency = 0.35
rightBioLeftRule.BorderSizePixel = 0
rightBioLeftRule.ZIndex = 13
rightBioLeftRule.Parent = rightBioPanel

AEM_UIKit.makeMonoLabel({
	name = "InspectTag",
	parent = rightBioPanel,
	size = UDim2.fromScale(0.90, 0.06),
	position = UDim2.fromScale(0.05, 0.04),
	text = "SELECTED ANATOMICAL NODE",
	color = AEM_UIKit.AMBER_SOFT,
	textSize = 13,
	zIndex = 14,
})

local bioTitle = AEM_UIKit.makeMonoLabel({
	name = "InspectNodeTitle",
	parent = rightBioPanel,
	size = UDim2.fromScale(0.90, 0.09),
	position = UDim2.fromScale(0.05, 0.10),
	text = CALLOUT_NODES[1].id,
	color = AEM_UIKit.AMBER_GLOW,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	textSize = 20,
	zIndex = 14,
})

local bioDesc = AEM_UIKit.makeMonoLabel({
	name = "InspectNodeDesc",
	parent = rightBioPanel,
	size = UDim2.fromScale(0.90, 0.20),
	position = UDim2.fromScale(0.05, 0.20),
	text = CALLOUT_NODES[1].info,
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Medium,
	wrapped = true,
	alignY = Enum.TextYAlignment.Top,
	textSize = 15,
	zIndex = 14,
})

local bioSpecLbl = AEM_UIKit.makeMonoLabel({
	name = "InspectNodeSpec",
	parent = rightBioPanel,
	size = UDim2.fromScale(0.90, 0.09),
	position = UDim2.fromScale(0.05, 0.41),
	text = CALLOUT_NODES[1].spec,
	color = AEM_UIKit.AMBER_WIRE,
	wrapped = true,
	textSize = 14,
	zIndex = 14,
})

local bioRule = Instance.new("Frame")
bioRule.Size = UDim2.new(0.90, 0, 0, 1)
bioRule.Position = UDim2.fromScale(0.05, 0.52)
bioRule.BackgroundColor3 = AEM_UIKit.HAIRLINE_DIM
bioRule.BackgroundTransparency = 0.35
bioRule.BorderSizePixel = 0
bioRule.ZIndex = 13
bioRule.Parent = rightBioPanel

local economyDossierLabel = AEM_UIKit.makeMonoLabel({
	name = "CareerDossier",
	parent = rightBioPanel,
	size = UDim2.fromScale(0.90, 0.40),
	position = UDim2.fromScale(0.05, 0.56),
	text = "ARCHIVE TELEMETRY:\n• MARROW EXTRACT: 0\n• EXPERIENCE: 0 XP\n• HUNTER CONTAINMENTS: 0\n• ANOMALY BREACHES: 0",
	color = AEM_UIKit.AMBER_SOFT,
	wrapped = true,
	alignY = Enum.TextYAlignment.Top,
	textSize = 15,
	zIndex = 14,
})

local nodeButtons: { { btn: TextButton, stroke: UIStroke } } = {}
for nIdx, node in ipairs(CALLOUT_NODES) do
	AEM_UIKit.drawLinePx(viewportBox, "NodeLeader_" .. tostring(nIdx), node.leaderFrom, node.leaderTo, 1, AEM_UIKit.AMBER_WIRE, 0.45, 15, false)

	local tag = Instance.new("TextButton")
	tag.Name = "AnatomicalNode_" .. tostring(nIdx)
	tag.Size = UDim2.fromOffset(194, 68)
	tag.Position = node.pos
	tag.BackgroundColor3 = AEM_UIKit.CHARCOAL
	tag.BackgroundTransparency = if nIdx == 1 then 0.74 else 0.82
	tag.BorderSizePixel = 0
	tag.AutoButtonColor = false
	tag.TextWrapped = true
	tag.Text = node.id
	tag.TextColor3 = if nIdx == 1 then AEM_UIKit.AMBER_GLOW else AEM_UIKit.IVORY_TEXT
	tag.ZIndex = 16
	tag.Parent = viewportBox

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = tag

	local tagStroke = AEM_UIKit.applyBevelStroke(tag, if nIdx == 1 then AEM_UIKit.AMBER_GLOW else AEM_UIKit.HAIRLINE_DIM, 1, if nIdx == 1 then 0.15 else 0.45)
	AEM_UIKit.styleButtonText(tag, Enum.FontWeight.SemiBold, 9, 13, 0.84, false)
	AEM_UIKit.createWireBracketFrame(tag, {
		name = "NodeBrackets",
		parent = tag,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		bgTransparency = 1,
		bracketColor = AEM_UIKit.AMBER_WIRE,
		bracketLength = 6,
		bracketThickness = 1,
		bracketTransparency = 0.35,
		mode = "LeftRight",
		glow = false,
		zIndex = 17,
	})
	table.insert(nodeButtons, { btn = tag, stroke = tagStroke })

	table.insert(connections, tag.Activated:Connect(function()
		bioTitle.Text = node.id
		bioDesc.Text = node.info
		bioSpecLbl.Text = node.spec
		for j, entry in ipairs(nodeButtons) do
			local active = j == nIdx
			entry.btn.BackgroundTransparency = if active then 0.74 else 0.82
			entry.btn.TextColor3 = if active then AEM_UIKit.AMBER_GLOW else AEM_UIKit.IVORY_TEXT
			entry.stroke.Color = if active then AEM_UIKit.AMBER_GLOW else AEM_UIKit.HAIRLINE_DIM
			entry.stroke.Transparency = if active then 0.15 else 0.45
		end
	end))
end

-- ============================================================================
-- PAGE 3: CLEARANCE PASS (OBLIVION CLEARANCE / REQUISITION)
-- ============================================================================
local passPage = Instance.new("Frame")
passPage.Name = "Page_PassOblivion"
passPage.Size = UDim2.fromOffset(1416, 568)
passPage.Position = UDim2.fromOffset(22, 78)
passPage.BackgroundTransparency = 1
passPage.Visible = false
passPage.ZIndex = 11
passPage.Parent = mainFrame

local function makeRequisitionCard(name: string, xPx: number, title: string, desc: string, btnText: string, accent: Color3): (TextButton, TextLabel)
	local panel = AEM_UIKit.createWireBracketFrame(passPage, {
		name = name,
		parent = passPage,
		position = UDim2.fromOffset(xPx, 16),
		size = UDim2.fromOffset(696, 490),
		bgColor = AEM_UIKit.CHARCOAL,
		bgTransparency = 0.80,
		bracketColor = accent,
		bracketThickness = 1.25,
		bracketLength = 14,
		mode = "Corners",
		glow = true,
		zIndex = 12,
	})
	AEM_UIKit.applyBevelStroke(panel, AEM_UIKit.HAIRLINE_DIM, 1, 0.45)

	local topRule = Instance.new("Frame")
	topRule.Name = "TopAccentRule"
	topRule.Size = UDim2.new(1, 0, 0, 2)
	topRule.Position = UDim2.fromOffset(0, 0)
	topRule.BackgroundColor3 = accent
	topRule.BackgroundTransparency = 0.20
	topRule.BorderSizePixel = 0
	topRule.ZIndex = 13
	topRule.Parent = panel

	AEM_UIKit.makeMonoLabel({
		name = "PassTitle",
		parent = panel,
		size = UDim2.fromScale(0.90, 0.16),
		position = UDim2.fromScale(0.05, 0.08),
		text = title,
		color = accent,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Bold,
		textSize = 22,
		zIndex = 14,
	})
	AEM_UIKit.makeMonoLabel({
		name = "PassDesc",
		parent = panel,
		size = UDim2.fromScale(0.90, 0.36),
		position = UDim2.fromScale(0.05, 0.28),
		text = desc,
		color = AEM_UIKit.IVORY_TEXT,
		font = AEM_UIKit.FONT_TECH,
		weight = Enum.FontWeight.Medium,
		wrapped = true,
		alignY = Enum.TextYAlignment.Top,
		textSize = 16,
		zIndex = 14,
	})
	local statusLbl = AEM_UIKit.makeMonoLabel({
		name = "StatusLbl",
		parent = panel,
		size = UDim2.fromScale(0.90, 0.10),
		position = UDim2.fromScale(0.05, 0.66),
		text = "STATUS: NOT AUTHORIZED",
		color = AEM_UIKit.AMBER_SOFT,
		textSize = 15,
		zIndex = 14,
	})
	local btn = Instance.new("TextButton")
	btn.Name = "PurchaseButton"
	btn.Size = UDim2.fromScale(0.90, 0.15)
	btn.Position = UDim2.fromScale(0.05, 0.79)
	btn.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	btn.BackgroundTransparency = 0.78
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = btnText
	btn.TextColor3 = accent
	btn.ZIndex = 14
	btn.Parent = panel
	AEM_UIKit.applyBevelStroke(btn, accent, 1.2, 0.25)
	AEM_UIKit.styleButtonText(btn, Enum.FontWeight.Bold, 14, 16, 0.84, false)
	AEM_UIKit.createWireBracketFrame(btn, {
		name = "PurchaseBrackets",
		parent = btn,
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		bgTransparency = 1,
		bracketColor = accent,
		bracketLength = 10,
		bracketThickness = 1.1,
		mode = "LeftRight",
		glow = false,
		zIndex = 15,
	})
	return btn, statusLbl
end

local vipPassButton, vipStatusLabel = makeRequisitionCard(
	"Card_VIPClearance",
	0,
	"OBLIVION CLEARANCE  //  VIP",
	"• +50% MARROW EXTRACT (COINS) PER MATCH\n• +50% BIOMETRIC REGISTRY XP GAIN\n• GOLD [VIP] CALLSIGN BADGE IN TERMINAL & COMMS",
	"AUTHORIZE CLEARANCE [VIP]",
	AEM_UIKit.AMBER_WIRE
)

local monsterPassButton, monsterStatusLabel = makeRequisitionCard(
	"Card_MonsterOverride",
	720,
	"PROTOCOL OVERRIDE  //  2x SPECIMEN",
	"• 2x SPECIMEN ROTATION WEIGHT IN MATCHMAKER\n• PRIORITY APEX SIGNAL ON A.E.M. DEPLOYMENT QUEUE\n• STACKS WITH ISOLATED [SPECIMEN] SLOT PREFERENCE",
	"AUTHORIZE OVERRIDE [2x MONSTER]",
	AEM_UIKit.BOSS_CRIMSON
)

local passFeedbackLabel = AEM_UIKit.makeMonoLabel({
	name = "PassFeedback",
	parent = passPage,
	size = UDim2.fromOffset(1416, 40),
	position = UDim2.fromOffset(0, 522),
	text = "CLEARANCE TRANSACTIONS PROCESSED BY ROBLOX CLOUD MARKETPLACE.",
	color = AEM_UIKit.AMBER_SOFT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Medium,
	textSize = 14,
	zIndex = 14,
})

-- ============================================================================
-- TAB MANAGEMENT, MODAL STATE & REAL-TIME TELEMETRY
-- ============================================================================
local isModalOpen = false
local activeTab = "Deploy"

local uiBlur: BlurEffect
do
	local existingBlur = Lighting:FindFirstChild("ProjectAbyss_UIBlur")
	if existingBlur ~= nil and existingBlur:IsA("BlurEffect") then
		uiBlur = existingBlur :: BlurEffect
	else
		uiBlur = Instance.new("BlurEffect")
		uiBlur.Name = "ProjectAbyss_UIBlur"
		uiBlur.Parent = Lighting
	end
	uiBlur.Size = 0
	uiBlur.Enabled = false
end

local function updateTabHighlights(): ()
	deployPage.Visible = isModalOpen and activeTab == "Deploy"
	bioPage.Visible = isModalOpen and activeTab == "BioArchives"
	passPage.Visible = isModalOpen and activeTab == "Pass"

	if activeTab == "Deploy" then
		modalTitleLabel.Text = "SQUAD FORMATION  //  PROTOCOL 6-7-9"
	elseif activeTab == "BioArchives" then
		modalTitleLabel.Text = "BIO-ARCHIVES  //  THE VIVISECTION"
	else
		modalTitleLabel.Text = "OBLIVION CLEARANCE  //  REQUISITION"
	end

	local deployActive = isModalOpen and activeTab == "Deploy"
	local bioActive = isModalOpen and activeTab == "BioArchives"
	local passActive = isModalOpen and activeTab == "Pass"

	strokeTabDeploy.Color = if deployActive then AEM_UIKit.AMBER_GLOW else AEM_UIKit.HAIRLINE_DIM
	strokeTabDeploy.Thickness = if deployActive then 1.5 else 1
	strokeTabDeploy.Transparency = if deployActive then 0.12 else 0.48

	strokeTabBio.Color = if bioActive then AEM_UIKit.AMBER_GLOW else AEM_UIKit.HAIRLINE_DIM
	strokeTabBio.Thickness = if bioActive then 1.5 else 1
	strokeTabBio.Transparency = if bioActive then 0.12 else 0.48

	strokeTabPass.Color = if passActive then AEM_UIKit.AMBER_GLOW else AEM_UIKit.HAIRLINE_DIM
	strokeTabPass.Thickness = if passActive then 1.5 else 1
	strokeTabPass.Transparency = if passActive then 0.12 else 0.48
end

local autoCollapseToken = 0

local function setModalOpen(open: boolean, targetTab: string?): ()
	if open and not screenGui.Enabled then
		open = false
	end
	if not open or targetTab ~= nil then
		autoCollapseToken += 1
	end
	if targetTab ~= nil then
		activeTab = targetTab
	end

	isModalOpen = open
	backdropButton.Visible = open
	mainFrame.Visible = open
	updateTabHighlights()

	if open then
		uiBlur.Enabled = true
		TweenService:Create(uiBlur, CONFIG.PanelTweenInfo, { Size = 4 }):Play()
		mainFrame.Position = UDim2.fromScale(0.5, 0.53)
		TweenService:Create(mainFrame, CONFIG.PanelTweenInfo, {
			Position = UDim2.fromScale(0.5, 0.50),
		}):Play()
		refreshCardVisuals()
	else
		TweenService:Create(uiBlur, CONFIG.PanelTweenInfo, { Size = 0 }):Play()
		task.delay(0.22, function()
			if not isModalOpen then
				uiBlur.Enabled = false
			end
		end)
	end
end

local function setSelectorVisible(visible: boolean): ()
	if visible then
		screenGui.Enabled = true
		updateTopInsetPosition()
		topBar.Visible = true
		dockBar.Visible = true
		crtLayer.root.Visible = true
		refreshCardVisuals()
	else
		setModalOpen(false, nil)
		topBar.Visible = false
		dockBar.Visible = false
		crtLayer.root.Visible = false
		screenGui.Enabled = false
	end
end

table.insert(connections, btnTabDeploy.Activated:Connect(function()
	if isModalOpen and activeTab == "Deploy" then
		setModalOpen(false, nil)
	else
		setModalOpen(true, "Deploy")
	end
end))

table.insert(connections, btnTabBio.Activated:Connect(function()
	if isModalOpen and activeTab == "BioArchives" then
		setModalOpen(false, nil)
	else
		setModalOpen(true, "BioArchives")
	end
end))

table.insert(connections, btnTabPass.Activated:Connect(function()
	if isModalOpen and activeTab == "Pass" then
		setModalOpen(false, nil)
	else
		setModalOpen(true, "Pass")
	end
end))

table.insert(connections, closeModalButton.Activated:Connect(function()
	setModalOpen(false, nil)
end))
table.insert(connections, backdropButton.Activated:Connect(function()
	setModalOpen(false, nil)
end))

local HOTKEY_ROLE_MAP: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "Monster",
	[Enum.KeyCode.Two] = "Assault",
	[Enum.KeyCode.Three] = "Medic",
	[Enum.KeyCode.Four] = "Trapper",
	[Enum.KeyCode.Five] = "Support",
}

table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or UserInputService:GetFocusedTextBox() ~= nil or not screenGui.Enabled then
		return
	end
	if input.KeyCode == Enum.KeyCode.F1 or input.KeyCode == Enum.KeyCode.M then
		if isModalOpen and activeTab == "Deploy" then
			setModalOpen(false, nil)
		else
			setModalOpen(true, "Deploy")
		end
	elseif input.KeyCode == Enum.KeyCode.F2 then
		if isModalOpen and activeTab == "BioArchives" then
			setModalOpen(false, nil)
		else
			setModalOpen(true, "BioArchives")
		end
	elseif input.KeyCode == Enum.KeyCode.F3 then
		if isModalOpen and activeTab == "Pass" then
			setModalOpen(false, nil)
		else
			setModalOpen(true, "Pass")
		end
	elseif (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace) and isModalOpen then
		setModalOpen(false, nil)
	elseif isModalOpen and activeTab == "Deploy" and HOTKEY_ROLE_MAP[input.KeyCode] ~= nil then
		onCardClicked(HOTKEY_ROLE_MAP[input.KeyCode])
	end
end))

table.insert(connections, ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, playerTriggered: Player)
	if playerTriggered == LocalPlayer and prompt.Name == "RoleTerminalPrompt" and screenGui.Enabled then
		setModalOpen(true, "Deploy")
		local targetRole = prompt:GetAttribute("TargetRole")
		if typeof(targetRole) == "string" and VALID_ROLE_BY_KEY[targetRole] ~= nil then
			onCardClicked(targetRole)
		end
	end
end))

local function handleMatchState(state: string, timeRemaining: number?, extraData: { [string]: any }?): ()
	if state == "Intermission" then
		local char = LocalPlayer.Character
		local currentRole = if char ~= nil then char:GetAttribute("Role") else "Lobby"
		if currentRole ~= nil and currentRole ~= "Lobby" then
			setSelectorVisible(false)
			return
		end

		if extraData ~= nil and extraData.waitingForPlayers == true then
			local readyCount = tonumber(extraData.readyPlayers) or 0
			local requiredCount = math.max(1, tonumber(extraData.requiredPlayers) or 5)
			local txt = string.format("AWAITING SQUAD (%d/%d)", readyCount, requiredCount)
			timerBadge.Text = txt
			dockTimerLabel.Text = txt
		elseif typeof(timeRemaining) == "number" then
			local secs = math.max(0, math.ceil(timeRemaining))
			timerBadge.Text = string.format("DEPLOYMENT IN: %ds", secs)
			dockTimerLabel.Text = string.format("INTERMISSION %ds", secs)
		else
			timerBadge.Text = "INTERMISSION"
			dockTimerLabel.Text = "INTERMISSION"
		end

		setSelectorVisible(true)
	else
		pendingRole = nil
		if state == "PostMatch" then
			confirmedRole = nil
		end
		setSelectorVisible(false)
	end
end

local function refreshEconomyStrip(): ()
	local coins = tonumber(LocalPlayer:GetAttribute("Coins")) or 0
	local xp = tonumber(LocalPlayer:GetAttribute("XP")) or 0
	local winsM = tonumber(LocalPlayer:GetAttribute("WinsAsMonster")) or 0
	local winsH = tonumber(LocalPlayer:GetAttribute("WinsAsHunter")) or 0
	local onyxCores = winsM + winsH
	local isVIP = LocalPlayer:GetAttribute("IsVIP") == true
	local hasPriority = LocalPlayer:GetAttribute("HasMonsterPriority") == true

	currencyLbl.Text = string.format("MARROW %d  ·  CORES %d", coins, onyxCores)
	economyDossierLabel.Text = string.format(
		"ARCHIVE TELEMETRY:\n• MARROW EXTRACT: %d\n• EXPERIENCE: %d XP\n• HUNTER CONTAINMENTS: %d\n• ANOMALY BREACHES: %d",
		coins,
		xp,
		winsH,
		winsM
	)

	vipStatusLabel.Text = if isVIP then "STATUS: AUTHORIZED ✓ (+50% ACTIVE)" else "STATUS: STANDARD CLEARANCE"
	vipStatusLabel.TextColor3 = if isVIP then AEM_UIKit.AMBER_GLOW else AEM_UIKit.AMBER_SOFT
	vipPassButton.Text = if isVIP then "CLEARANCE ACTIVE ✓" else "AUTHORIZE CLEARANCE [VIP]"

	monsterStatusLabel.Text = if hasPriority then "STATUS: PRIORITY 2x ACTIVE ✓" else "STATUS: 1x ROTATION WEIGHT"
	monsterStatusLabel.TextColor3 = if hasPriority then AEM_UIKit.AMBER_GLOW else AEM_UIKit.AMBER_SOFT
	monsterPassButton.Text = if hasPriority then "OVERRIDE ACTIVE ✓" else "AUTHORIZE OVERRIDE [2x MONSTER]"
end

local function promptPassFromGameRemotes(attrName: string, alreadyOwned: boolean, labelName: string): ()
	if alreadyOwned then
		passFeedbackLabel.Text = labelName .. " IS ALREADY AUTHORIZED ON YOUR REGISTRY."
		passFeedbackLabel.TextColor3 = AEM_UIKit.AMBER_GLOW
		return
	end
	local gameRemotesFolder = if selectRoleRemote ~= nil then selectRoleRemote.Parent else nil
	local passId = if gameRemotesFolder ~= nil then tonumber(gameRemotesFolder:GetAttribute(attrName)) or 0 else 0
	if passId <= 0 then
		passFeedbackLabel.Text = labelName .. " // AWAITING CLOUD GAMEPASS ID CONFIGURATION."
		passFeedbackLabel.TextColor3 = AEM_UIKit.AMBER_WIRE
		return
	end
	MarketplaceService:PromptGamePassPurchase(LocalPlayer, passId)
end

table.insert(connections, vipPassButton.Activated:Connect(function()
	promptPassFromGameRemotes("VIPGamePassId", LocalPlayer:GetAttribute("IsVIP") == true, "OBLIVION VIP CLEARANCE")
end))
table.insert(connections, monsterPassButton.Activated:Connect(function()
	promptPassFromGameRemotes("MonsterPriorityGamePassId", LocalPlayer:GetAttribute("HasMonsterPriority") == true, "2x SPECIMEN OVERRIDE")
end))

for _, ecoAttr in ipairs({ "Coins", "XP", "WinsAsMonster", "WinsAsHunter", "IsVIP", "HasMonsterPriority" }) do
	table.insert(connections, LocalPlayer:GetAttributeChangedSignal(ecoAttr):Connect(refreshEconomyStrip))
end
refreshEconomyStrip()

local function handleUpdateUI(notificationType: string, payload: { [string]: any }?): ()
	if typeof(notificationType) ~= "string" then
		return
	end
	local data = if typeof(payload) == "table" then payload else {}

	if
		notificationType == "RolePreferenceConfirmed"
		or notificationType == "RolePreferenceUpdated"
		or notificationType == "PreferenceConfirmed"
		or notificationType == "RolePreference"
		or notificationType == "SelectRolePreference"
	then
		local roleValue = data.preferredRole or data.role
		if typeof(roleValue) == "string" and VALID_ROLE_BY_KEY[roleValue] ~= nil then
			confirmedRole = roleValue
			pendingRole = nil
			feedbackLabel.Text = "SLOT REGISTERED BY A.E.M. SERVER: " .. VALID_ROLE_BY_KEY[roleValue].title
			feedbackLabel.TextColor3 = AEM_UIKit.AMBER_GLOW
			footerStroke.Color = AEM_UIKit.AMBER_WIRE
			refreshCardVisuals()

			if isModalOpen and activeTab == "Deploy" then
				autoCollapseToken += 1
				local myCollapse = autoCollapseToken
				task.delay(0.85, function()
					if myCollapse == autoCollapseToken and isModalOpen and activeTab == "Deploy" then
						setModalOpen(false, nil)
					end
				end)
			end
		end
	elseif notificationType == "RolePreferenceRejected" or notificationType == "RolePreferenceDenied" then
		pendingRole = nil
		local reasonText = if typeof(data.message) == "string"
			then data.message
			elseif typeof(data.reason) == "string" then data.reason
			else "REQUEST REJECTED BY A.E.M. SERVER."
		feedbackLabel.Text = string.upper(reasonText)
		feedbackLabel.TextColor3 = AEM_UIKit.BOSS_CRIMSON
		footerStroke.Color = AEM_UIKit.BOSS_CRIMSON
		refreshCardVisuals()
	elseif notificationType == "RoleAssigned" then
		local assigned = data.role
		if typeof(assigned) == "string" and VALID_ROLE_BY_KEY[assigned] ~= nil then
			pendingRole = nil
			feedbackLabel.Text = "ASSIGNED TO MATCH DEPLOYMENT: " .. VALID_ROLE_BY_KEY[assigned].title
			feedbackLabel.TextColor3 = VALID_ROLE_BY_KEY[assigned].accent
			footerStroke.Color = VALID_ROLE_BY_KEY[assigned].accent
			refreshCardVisuals()
		end
	elseif notificationType == "EconomyProfileLoaded" or notificationType == "VIPStatus" or notificationType == "MatchRewards" then
		refreshEconomyStrip()
	end
end

local localCharRoleConn: RBXScriptConnection? = nil

local function bindLocalCharacter(character: Model): ()
	if localCharRoleConn ~= nil then
		localCharRoleConn:Disconnect()
		localCharRoleConn = nil
	end
	localCharRoleConn = character:GetAttributeChangedSignal("Role"):Connect(function()
		local role = character:GetAttribute("Role")
		if role ~= "Lobby" then
			setSelectorVisible(false)
		elseif matchStateRemote ~= nil then
			local parentFolder = matchStateRemote.Parent
			if parentFolder ~= nil and parentFolder:GetAttribute("MatchState") == "Intermission" then
				setSelectorVisible(true)
			end
		end
	end)
end

table.insert(connections, LocalPlayer.CharacterAdded:Connect(bindLocalCharacter))
if LocalPlayer.Character ~= nil then
	bindLocalCharacter(LocalPlayer.Character)
end

local okTopbarInset, topbarInsetSignal = pcall(function()
	return GuiService:GetPropertyChangedSignal("TopbarInset")
end)
if okTopbarInset and topbarInsetSignal ~= nil then
	table.insert(connections, (topbarInsetSignal :: RBXScriptSignal):Connect(updateTopInsetPosition))
end

local camViewportConn: RBXScriptConnection? = nil
local function bindCameraViewportInset(): ()
	if camViewportConn ~= nil and camViewportConn.Connected then
		camViewportConn:Disconnect()
		camViewportConn = nil
	end
	local cam = Workspace.CurrentCamera
	if cam ~= nil then
		camViewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(updateTopInsetPosition)
		end)
	end
	task.defer(updateTopInsetPosition)
end
bindCameraViewportInset()
table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewportInset))

table.insert(connections, RunService.Heartbeat:Connect(function()
	if screenGui.Enabled then
		updateTopInsetPosition()
	end
end))

local pingTimer = 0
local rigYaw = 0
table.insert(connections, RunService.RenderStepped:Connect(function(dt: number)
	if not screenGui.Enabled then
		return
	end
	updateTopInsetPosition()
	pingTimer += dt
	if pingTimer >= 0.4 then
		pingTimer = 0
		local pingMs = math.max(1, math.round(LocalPlayer:GetNetworkPing() * 1000))
		local bpm = tonumber(LocalPlayer:GetAttribute("ClientBPM")) or 78
		pingBpmLbl.Text = string.format("PING %dms  ·  %d BPM", pingMs, bpm)
	end
	if isModalOpen and activeTab == "BioArchives" then
		rigYaw += dt * 0.65
		rigModel:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, rigYaw, 0))
	end
end))

task.spawn(function()
	local status = ReplicatedStorage:GetAttribute("BootstrapStatus")
	if status == "Initializing" then
		while ReplicatedStorage:GetAttribute("BootstrapStatus") == "Initializing" do
			ReplicatedStorage:GetAttributeChangedSignal("BootstrapStatus"):Wait()
		end
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if remotes == nil then
		warn(string.format("%s ReplicatedStorage.Remotes not found.", LOG_PREFIX))
		return
	end

	local gameRemotes = remotes:WaitForChild("GameRemotes", 15)
	if gameRemotes == nil then
		warn(string.format("%s GameRemotes not found.", LOG_PREFIX))
		return
	end

	local matchRemote = gameRemotes:WaitForChild("MatchStateChanged", 15)
	local uiRemote = gameRemotes:WaitForChild("UpdateUI", 15)
	local selectRemote = gameRemotes:WaitForChild("SelectRolePreference", 15)

	if
		matchRemote == nil
		or not matchRemote:IsA("RemoteEvent")
		or uiRemote == nil
		or not uiRemote:IsA("RemoteEvent")
		or selectRemote == nil
		or not selectRemote:IsA("RemoteEvent")
	then
		warn(string.format("%s Invalid or missing GameRemotes RemoteEvents.", LOG_PREFIX))
		return
	end

	matchStateRemote = matchRemote :: RemoteEvent
	updateUIRemote = uiRemote :: RemoteEvent
	selectRoleRemote = selectRemote :: RemoteEvent

	table.insert(connections, (matchStateRemote :: RemoteEvent).OnClientEvent:Connect(handleMatchState))
	table.insert(connections, (updateUIRemote :: RemoteEvent).OnClientEvent:Connect(handleUpdateUI))

	local initialState = gameRemotes:GetAttribute("MatchState")
	if typeof(initialState) == "string" then
		local initialRemaining = gameRemotes:GetAttribute("TimeRemaining")
		local waitingAttr = gameRemotes:GetAttribute("WaitingForPlayers") == true
		handleMatchState(
			initialState,
			if typeof(initialRemaining) == "number" then initialRemaining else nil,
			if waitingAttr then { waitingForPlayers = true } else nil
		)
	end
end)

screenGui.Destroying:Connect(function()
	uiBlur.Size = 0
	uiBlur.Enabled = false
	if localCharRoleConn ~= nil then
		localCharRoleConn:Disconnect()
		localCharRoleConn = nil
	end
	if camViewportConn ~= nil and camViewportConn.Connected then
		camViewportConn:Disconnect()
		camViewportConn = nil
	end
	for _, conn in ipairs(connections) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(connections)
end)


