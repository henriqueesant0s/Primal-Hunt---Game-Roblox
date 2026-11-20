--!strict
--[[
	PROJECT ABYSS | AEM_UIKit.lua
	Localização: ReplicatedStorage/AEM_UIKit

	Kairos-09 Amber Wireframe Design System (#FF9000):
	- Translucent void-glass surfaces (#0C0906) and #FF9000 amber wireframe geometry with subtle phosphor glow.
	- High-DPI typography: BuilderSans (condensed uppercase headers) + RobotoMono (tabular telemetry & keycaps) with dark contrast stroke.
	- Legacy Kairos-09 palette aliases preserved for zero-breakage compatibility across TacticalHUD & LobbyRoleSelector.
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AEM_UIKit = {}

-- Canonical Kairos-09 Amber Wireframe Tokens
AEM_UIKit.AMBER_WIRE = Color3.fromRGB(255, 144, 0)
AEM_UIKit.AMBER_GLOW = Color3.fromRGB(255, 188, 72)
AEM_UIKit.AMBER_SOFT = Color3.fromRGB(204, 138, 68)
AEM_UIKit.IVORY_TEXT = Color3.fromRGB(246, 238, 224)
AEM_UIKit.BOSS_CRIMSON = Color3.fromRGB(218, 38, 28)
AEM_UIKit.VOID_GLASS = Color3.fromRGB(12, 9, 6)
AEM_UIKit.HAIRLINE_DIM = Color3.fromRGB(122, 74, 24)
AEM_UIKit.TRACK_GLASS = Color3.fromRGB(24, 16, 8)
AEM_UIKit.TEXT_STROKE_DARK = Color3.fromRGB(8, 5, 2)

-- Primary & Legacy Tokens Mapped Cleanly to Kairos-09 Amber Wireframe Palette
AEM_UIKit.OBSIDIAN = AEM_UIKit.VOID_GLASS
AEM_UIKit.CHARCOAL = Color3.fromRGB(18, 13, 8)
AEM_UIKit.CHARCOAL_ELEVATED = Color3.fromRGB(26, 18, 10)
AEM_UIKit.TRACK_DARK = AEM_UIKit.TRACK_GLASS
AEM_UIKit.OLIVE_HAIRLINE = AEM_UIKit.HAIRLINE_DIM
AEM_UIKit.OLIVE_TACTICAL = AEM_UIKit.AMBER_WIRE
AEM_UIKit.PALE_IVORY = AEM_UIKit.IVORY_TEXT
AEM_UIKit.MUTED_BONE = AEM_UIKit.AMBER_SOFT
AEM_UIKit.MUTED_GOLD = AEM_UIKit.AMBER_WIRE
AEM_UIKit.PALE_GOLD = AEM_UIKit.AMBER_GLOW
AEM_UIKit.OXIDIZED_CRIMSON = AEM_UIKit.BOSS_CRIMSON
AEM_UIKit.CONTAINMENT_STEEL = AEM_UIKit.AMBER_WIRE

-- Legacy Aliases (all 24 keys preserved)
AEM_UIKit.ONYX_BLACK = AEM_UIKit.OBSIDIAN
AEM_UIKit.PANEL_SLATE = AEM_UIKit.CHARCOAL
AEM_UIKit.PANEL_ELEVATED = AEM_UIKit.CHARCOAL_ELEVATED
AEM_UIKit.BAR_TRACK = AEM_UIKit.TRACK_DARK
AEM_UIKit.OLIVE_MILITARY = AEM_UIKit.OLIVE_HAIRLINE
AEM_UIKit.PHOSPHOR_GREEN = AEM_UIKit.AMBER_WIRE
AEM_UIKit.INDUSTRIAL_AMBER = AEM_UIKit.AMBER_WIRE
AEM_UIKit.SURGICAL_IVORY = AEM_UIKit.IVORY_TEXT
AEM_UIKit.MUTED_IVORY = AEM_UIKit.AMBER_SOFT
AEM_UIKit.ARTERIAL_RED = AEM_UIKit.BOSS_CRIMSON
AEM_UIKit.SHOCK_CYAN = AEM_UIKit.AMBER_SOFT
AEM_UIKit.APEX_GOLD = AEM_UIKit.AMBER_GLOW

AEM_UIKit.FONT_MONO = Enum.Font.RobotoMono
AEM_UIKit.FONT_TECH = Enum.Font.BuilderSans

AEM_UIKit.FONT_DISPLAY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
AEM_UIKit.FONT_DISPLAY_SEMIBOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
AEM_UIKit.FONT_DISPLAY_MEDIUM = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)

AEM_UIKit.FONT_FACE_BOLD = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
AEM_UIKit.FONT_FACE_SEMIBOLD = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
AEM_UIKit.FONT_FACE_MEDIUM = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)

local MONO_WEIGHT_TO_FACE: { [Enum.FontWeight]: Font } = {
	[Enum.FontWeight.Bold] = AEM_UIKit.FONT_FACE_BOLD,
	[Enum.FontWeight.SemiBold] = AEM_UIKit.FONT_FACE_SEMIBOLD,
	[Enum.FontWeight.Medium] = AEM_UIKit.FONT_FACE_MEDIUM,
}

local SANS_WEIGHT_TO_FACE: { [Enum.FontWeight]: Font } = {
	[Enum.FontWeight.Bold] = AEM_UIKit.FONT_DISPLAY_BOLD,
	[Enum.FontWeight.SemiBold] = AEM_UIKit.FONT_DISPLAY_SEMIBOLD,
	[Enum.FontWeight.Medium] = AEM_UIKit.FONT_DISPLAY_MEDIUM,
}

export type BevelPanelProps = {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	bgColor: Color3?,
	bgTransparency: number?,
	strokeColor: Color3?,
	strokeThickness: number?,
	strokeTransparency: number?,
	zIndex: number?,
	clipsDescendants: boolean?,
	accentEdge: ("Top" | "Left" | "Right" | "Bottom" | "None")?,
	accentColor: Color3?,
	showCornerTicks: boolean?,
	showRivets: boolean?,
	showChamfer: boolean?,
}

export type CRTLayerHandle = {
	root: Frame,
	sweepBar: Frame,
	leftRed: Frame,
	leftGreen: Frame,
	rightRed: Frame,
	rightGreen: Frame,
	setAberration: (amount: number) -> (),
}

export type SegmentedBarHandle = {
	root: Frame,
	setRatio: (ratio: number, fillColor: Color3?) -> (),
}

export type WireBracketFrameProps = {
	name: string?,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	bgColor: Color3?,
	bgTransparency: number?,
	bracketColor: Color3?,
	bracketThickness: number?,
	bracketLength: number?,
	bracketTransparency: number?,
	mode: ("Corners" | "LeftRight" | "TopBottom" | "LeftSlanted")?,
	slantDeg: number?,
	glow: boolean?,
	zIndex: number?,
	clipsDescendants: boolean?,
}

export type SlantedGaugeProps = {
	name: string?,
	parent: Instance,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	labelLeftText: string?,
	labelRightText: string?,
	fillColor: Color3?,
	glowColor: Color3?,
	trackColor: Color3?,
	trackTransparency: number?,
	barHeight: number?,
	slantDeg: number?,
	showEndTicks: boolean?,
	zIndex: number?,
}

export type SlantedGaugeHandle = {
	root: Frame,
	fill: Frame,
	labelLeft: TextLabel,
	labelRight: TextLabel,
	setPercent: (pct: number, fillColor: Color3?, rightTextOverride: string?) -> (),
}

export type SegmentedBossBarProps = {
	name: string?,
	parent: Instance,
	position: UDim2?,
	anchorPoint: Vector2?,
	widthPx: number?,
	barHeightPx: number?,
	segments: number?,
	archDepthPx: number?,
	headerText: string?,
	subLeftText: string?,
	subRightText: string?,
	zIndex: number?,
}

export type SegmentedBossBarHandle = {
	root: Frame,
	setProgress: (ratio: number) -> (),
	setHeader: (text: string) -> (),
	setSubtext: (left: string?, right: string?) -> (),
}

export type GlyphId =
	"harpoon"
	| "dome"
	| "scanner"
	| "ion_rifle"
	| "matrix"
	| "heal_burst"
	| "heal_beam"
	| "projector"
	| "barrage"
	| "leap"
	| "charge"
	| "acid"
	| "smell"
	| "eat"
	| "evolve"
	| "stealth"

export type ChamferedAbilityBadgeProps = {
	name: string?,
	parent: Instance,
	position: UDim2?,
	anchorPoint: Vector2?,
	sizePx: number?,
	glyph: GlyphId | string,
	label: string?,
	keybind: string?,
	clickable: boolean?,
	onActivated: (() -> ())?,
	zIndex: number?,
}

export type ChamferedAbilityBadgeHandle = {
	root: Frame,
	setState: (stateText: string, progress: number?, ready: boolean?) -> (),
	setKeybind: (keyStr: string) -> (),
	setLabel: (titleStr: string) -> (),
	setGlyph: (glyphId: string) -> (),
}

function AEM_UIKit.applyTextContrast(
	guiText: TextLabel | TextButton,
	strokeTransparency: number?,
	strokeColor: Color3?
): ()
	guiText.TextStrokeColor3 = strokeColor or AEM_UIKit.TEXT_STROKE_DARK
	guiText.TextStrokeTransparency = if strokeTransparency ~= nil then strokeTransparency else 0.84
end

function AEM_UIKit.addTextConstraint(label: TextLabel | TextButton, minSize: number, maxSize: number): UITextSizeConstraint
	local existing = label:FindFirstChildOfClass("UITextSizeConstraint")
	local constraint = existing or Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
	return constraint
end

function AEM_UIKit.styleButtonText(
	btn: TextButton,
	weight: Enum.FontWeight?,
	minSize: number?,
	maxSize: number?,
	strokeTransparency: number?,
	useSans: boolean?
): UITextSizeConstraint?
	local chosenWeight = weight or Enum.FontWeight.SemiBold
	local map = if useSans == true then SANS_WEIGHT_TO_FACE else MONO_WEIGHT_TO_FACE
	btn.FontFace = map[chosenWeight] or (if useSans == true then AEM_UIKit.FONT_DISPLAY_SEMIBOLD else AEM_UIKit.FONT_FACE_SEMIBOLD)
	AEM_UIKit.applyTextContrast(btn, strokeTransparency)
	if minSize ~= nil and maxSize ~= nil and minSize == maxSize then
		btn.TextScaled = false
		btn.TextSize = maxSize
		local existing = btn:FindFirstChildOfClass("UITextSizeConstraint")
		if existing ~= nil then
			existing:Destroy()
		end
		return nil
	end
	btn.TextScaled = true
	return AEM_UIKit.addTextConstraint(btn, minSize or 13, maxSize or 16)
end

function AEM_UIKit.createScaledCanvas(parent: Instance, canvasName: string?, zIndex: number?): (Frame, () -> number)
	local canvas = Instance.new("Frame")
	canvas.Name = canvasName or "AEM_ResponsiveCanvas"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.ZIndex = zIndex or 4
	canvas.Parent = parent

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "AEM_ResponsiveScale"
	uiScale.Scale = 1
	uiScale.Parent = canvas

	local currentScale = 1
	local camConn: RBXScriptConnection? = nil
	local function updateScale(): ()
		local cam = Workspace.CurrentCamera
		if cam == nil then
			return
		end
		local vp = cam.ViewportSize
		if vp.X <= 0 or vp.Y <= 0 then
			return
		end
		local s = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.36, 2.5)
		currentScale = s
		uiScale.Scale = s
		canvas.Size = UDim2.fromScale(1 / s, 1 / s)
	end

	local function bindCamera(): ()
		if camConn ~= nil and camConn.Connected then
			camConn:Disconnect()
			camConn = nil
		end
		local cam = Workspace.CurrentCamera
		if cam ~= nil then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
			updateScale()
		end
	end

	bindCamera()
	local wsCamConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	parent.Destroying:Once(function()
		if camConn ~= nil and camConn.Connected then
			camConn:Disconnect()
		end
		if wsCamConn.Connected then
			wsCamConn:Disconnect()
		end
	end)

	return canvas, function(): number
		return currentScale
	end
end

function AEM_UIKit.getLogicalTopInset(getScale: (() -> number)?): number
	local topLeft, _ = GuiService:GetGuiInset()
	local scale = if getScale ~= nil then math.max(0.25, getScale()) else 1
	return math.ceil(topLeft.Y / scale)
end

function AEM_UIKit.createScrimPanel(props: {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	bgColor: Color3?,
	fadeDirection: ("LeftToRight" | "RightToLeft" | "Center" | "TopToBottom" | "None")?,
	peakAlpha: number?,
	accentEdge: ("Top" | "Left" | "Right" | "Bottom" | "None")?,
	accentColor: Color3?,
	accentThickness: number?,
	zIndex: number?,
}): Frame
	local baseZ = props.zIndex or 10
	local frame = Instance.new("Frame")
	frame.Name = props.name
	frame.Size = props.size
	frame.Position = props.position
	if props.anchorPoint ~= nil then
		frame.AnchorPoint = props.anchorPoint
	end
	frame.BackgroundColor3 = props.bgColor or AEM_UIKit.VOID_GLASS
	frame.BackgroundTransparency = if props.peakAlpha ~= nil then props.peakAlpha else 0.82
	frame.BorderSizePixel = 0
	frame.ZIndex = baseZ
	frame.Parent = props.parent

	local dir = props.fadeDirection or "None"
	if dir ~= "None" then
		local grad = Instance.new("UIGradient")
		if dir == "LeftToRight" then
			grad.Rotation = 0
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(0.68, 0.60),
				NumberSequenceKeypoint.new(1, 1),
			})
		elseif dir == "RightToLeft" then
			grad.Rotation = 0
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.32, 0.60),
				NumberSequenceKeypoint.new(1, 0.25),
			})
		elseif dir == "TopToBottom" then
			grad.Rotation = 90
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(0.75, 0.60),
				NumberSequenceKeypoint.new(1, 1),
			})
		else
			grad.Rotation = 0
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.18, 0.35),
				NumberSequenceKeypoint.new(0.82, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
		grad.Parent = frame
	end

	local edge = props.accentEdge
	if edge ~= nil and edge ~= "None" then
		local t = props.accentThickness or 1
		local bar = Instance.new("Frame")
		bar.Name = "AccentRule"
		bar.BackgroundColor3 = props.accentColor or AEM_UIKit.AMBER_WIRE
		bar.BackgroundTransparency = 0.18
		bar.BorderSizePixel = 0
		bar.ZIndex = baseZ + 2
		if edge == "Top" then
			bar.Size = UDim2.new(1, 0, 0, t)
			bar.Position = UDim2.fromScale(0, 0)
		elseif edge == "Bottom" then
			bar.Size = UDim2.new(1, 0, 0, t)
			bar.Position = UDim2.new(0, 0, 1, -t)
		elseif edge == "Left" then
			bar.Size = UDim2.new(0, t, 1, 0)
			bar.Position = UDim2.fromScale(0, 0)
		elseif edge == "Right" then
			bar.Size = UDim2.new(0, t, 1, 0)
			bar.Position = UDim2.new(1, -t, 0, 0)
		end
		bar.Parent = frame
	end

	return frame
end

function AEM_UIKit.createSlimBar(props: {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	fillColor: Color3?,
	trackColor: Color3?,
	trackTransparency: number?,
	zIndex: number?,
	notches: number?,
}): SegmentedBarHandle
	local baseZ = props.zIndex or 12
	local defaultFill = props.fillColor or AEM_UIKit.IVORY_TEXT
	local trackColor = props.trackColor or AEM_UIKit.TRACK_GLASS

	local root = Instance.new("Frame")
	root.Name = props.name
	root.Size = props.size
	root.Position = props.position
	if props.anchorPoint ~= nil then
		root.AnchorPoint = props.anchorPoint
	end
	root.BackgroundColor3 = trackColor
	root.BackgroundTransparency = if props.trackTransparency ~= nil then props.trackTransparency else 0.72
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.ZIndex = baseZ
	root.Parent = props.parent

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.Position = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = defaultFill
	fill.BorderSizePixel = 0
	fill.ZIndex = baseZ + 1
	fill.Parent = root

	local notchCount = props.notches or 0
	if notchCount > 1 then
		for i = 1, notchCount - 1 do
			local tick = Instance.new("Frame")
			tick.Name = "Notch_" .. tostring(i)
			tick.Size = UDim2.new(0, 1, 1, 0)
			tick.Position = UDim2.fromScale(i / notchCount, 0)
			tick.BackgroundColor3 = AEM_UIKit.VOID_GLASS
			tick.BackgroundTransparency = 0.35
			tick.BorderSizePixel = 0
			tick.ZIndex = baseZ + 2
			tick.Parent = root
		end
	end

	local lastRatio = -1
	local lastColor: Color3? = nil
	local activeTween: Tween? = nil

	local function setRatio(ratio: number, fillColor: Color3?): ()
		local clamped = math.clamp(ratio, 0, 1)
		local activeColor = fillColor or defaultFill
		if lastColor ~= activeColor then
			fill.BackgroundColor3 = activeColor
			lastColor = activeColor
		end
		if math.abs(clamped - lastRatio) < 0.004 then
			return
		end
		lastRatio = clamped
		if activeTween ~= nil then
			activeTween:Cancel()
		end
		local tw = TweenService:Create(fill, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(clamped, 1),
		})
		activeTween = tw
		tw:Play()
	end

	return {
		root = root,
		setRatio = setRatio,
	}
end

function AEM_UIKit.createSegmentedBar(props: {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2?,
	segments: number?,
	fillColor: Color3?,
	trackColor: Color3?,
	zIndex: number?,
}): SegmentedBarHandle
	return AEM_UIKit.createSlimBar({
		name = props.name,
		parent = props.parent,
		size = props.size,
		position = props.position,
		anchorPoint = props.anchorPoint,
		fillColor = props.fillColor,
		trackColor = props.trackColor,
		zIndex = props.zIndex,
		notches = props.segments or 4,
	})
end

function AEM_UIKit.applyBevelStroke(
	parent: GuiObject,
	color: Color3,
	thickness: number?,
	transparency: number?,
	lineJoinMode: Enum.LineJoinMode?
): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = if transparency ~= nil then transparency else 0.58
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = lineJoinMode or Enum.LineJoinMode.Miter
	stroke.Parent = parent
	return stroke
end

function AEM_UIKit.makeMonoLabel(props: {
	name: string,
	parent: Instance,
	size: UDim2,
	position: UDim2,
	text: string,
	color: Color3?,
	font: Enum.Font?,
	weight: Enum.FontWeight?,
	strokeTransparency: number?,
	alignX: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	textSize: number?,
	minText: number?,
	maxText: number?,
	textScaled: boolean?,
	wrapped: boolean?,
	truncate: boolean?,
	zIndex: number?,
}): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = props.name
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Size = props.size
	lbl.Position = props.position

	local useSans = props.font == AEM_UIKit.FONT_TECH or props.font == Enum.Font.BuilderSans or props.font == Enum.Font.Gotham
	local targetWeight = props.weight or (if useSans then Enum.FontWeight.SemiBold else Enum.FontWeight.Bold)
	local faceMap = if useSans then SANS_WEIGHT_TO_FACE else MONO_WEIGHT_TO_FACE
	lbl.FontFace = faceMap[targetWeight] or (if useSans then AEM_UIKit.FONT_DISPLAY_SEMIBOLD else AEM_UIKit.FONT_FACE_BOLD)

	lbl.Text = props.text
	lbl.TextColor3 = props.color or AEM_UIKit.IVORY_TEXT
	AEM_UIKit.applyTextContrast(lbl, props.strokeTransparency)
	lbl.TextWrapped = props.wrapped == true
	lbl.TextXAlignment = props.alignX or Enum.TextXAlignment.Left
	lbl.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	if props.truncate == true then
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if props.zIndex ~= nil then
		lbl.ZIndex = props.zIndex
	end

	if props.textScaled == true then
		lbl.TextScaled = true
		lbl.Parent = props.parent
		AEM_UIKit.addTextConstraint(lbl, props.minText or 13, props.maxText or 18)
	else
		lbl.TextScaled = false
		lbl.TextSize = props.textSize or props.maxText or 15
		lbl.Parent = props.parent
	end

	return lbl
end

function AEM_UIKit.createBevelPanel(props: BevelPanelProps): (Frame, UIStroke)
	local baseZ = props.zIndex or 1
	local strokeColor = props.strokeColor or AEM_UIKit.HAIRLINE_DIM

	local frame = Instance.new("Frame")
	frame.Name = props.name
	frame.Size = props.size
	frame.Position = props.position
	if props.anchorPoint ~= nil then
		frame.AnchorPoint = props.anchorPoint
	end
	frame.BackgroundColor3 = props.bgColor or AEM_UIKit.VOID_GLASS
	frame.BackgroundTransparency = if props.bgTransparency ~= nil then props.bgTransparency else 0.80
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = if props.clipsDescendants ~= nil then props.clipsDescendants else true
	frame.ZIndex = baseZ
	frame.Parent = props.parent

	local stroke = AEM_UIKit.applyBevelStroke(
		frame,
		strokeColor,
		props.strokeThickness or 1,
		if props.strokeTransparency ~= nil then props.strokeTransparency else 0.48
	)

	local accentEdge = props.accentEdge
	if accentEdge ~= nil and accentEdge ~= "None" then
		local accentBar = Instance.new("Frame")
		accentBar.Name = "AccentRule"
		accentBar.BackgroundColor3 = props.accentColor or AEM_UIKit.AMBER_WIRE
		accentBar.BackgroundTransparency = 0.15
		accentBar.BorderSizePixel = 0
		accentBar.ZIndex = baseZ + 2
		if accentEdge == "Top" then
			accentBar.Size = UDim2.new(1, 0, 0, 1)
			accentBar.Position = UDim2.fromScale(0, 0)
		elseif accentEdge == "Bottom" then
			accentBar.Size = UDim2.new(1, 0, 0, 1)
			accentBar.Position = UDim2.new(0, 0, 1, -1)
		elseif accentEdge == "Left" then
			accentBar.Size = UDim2.new(0, 1, 1, 0)
			accentBar.Position = UDim2.fromScale(0, 0)
		elseif accentEdge == "Right" then
			accentBar.Size = UDim2.new(0, 1, 1, 0)
			accentBar.Position = UDim2.new(1, -1, 0, 0)
		end
		accentBar.Parent = frame
	end

	if props.showCornerTicks == true then
		local tickColor = props.accentColor or AEM_UIKit.AMBER_WIRE
		local corners = {
			{ x = 0, y = 0, dx = 1, dy = 1 },
			{ x = 1, y = 0, dx = -1, dy = 1 },
			{ x = 0, y = 1, dx = 1, dy = -1 },
			{ x = 1, y = 1, dx = -1, dy = -1 },
		}
		for idx, c in ipairs(corners) do
			local hBar = Instance.new("Frame")
			hBar.Name = "CornerH_" .. tostring(idx)
			hBar.AnchorPoint = Vector2.new(if c.dx > 0 then 0 else 1, if c.dy > 0 then 0 else 1)
			hBar.Position = UDim2.fromScale(c.x, c.y)
			hBar.Size = UDim2.fromOffset(10, 1)
			hBar.BackgroundColor3 = tickColor
			hBar.BackgroundTransparency = 0.18
			hBar.BorderSizePixel = 0
			hBar.ZIndex = baseZ + 3
			hBar.Parent = frame

			local vBar = Instance.new("Frame")
			vBar.Name = "CornerV_" .. tostring(idx)
			vBar.AnchorPoint = Vector2.new(if c.dx > 0 then 0 else 1, if c.dy > 0 then 0 else 1)
			vBar.Position = UDim2.fromScale(c.x, c.y)
			vBar.Size = UDim2.fromOffset(1, 10)
			vBar.BackgroundColor3 = tickColor
			vBar.BackgroundTransparency = 0.18
			vBar.BorderSizePixel = 0
			vBar.ZIndex = baseZ + 3
			vBar.Parent = frame
		end
	end

	return frame, stroke
end

function AEM_UIKit.createHazardStripe(
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	zIndex: number?
): Frame
	local baseZ = zIndex or 3
	local strip = Instance.new("Frame")
	strip.Name = name
	strip.Size = size
	strip.Position = position
	strip.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	strip.BackgroundTransparency = 0.85
	strip.BorderSizePixel = 0
	strip.ClipsDescendants = true
	strip.ZIndex = baseZ
	strip.Parent = parent

	for i = 0, 18 do
		local bar = Instance.new("Frame")
		bar.Name = "HazardBar_" .. tostring(i)
		bar.Size = UDim2.new(0, 7, 2.2, 0)
		bar.Position = UDim2.new(0, i * 18 - 10, -0.6, 0)
		bar.Rotation = 35
		bar.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
		bar.BackgroundTransparency = 0.45
		bar.BorderSizePixel = 0
		bar.ZIndex = baseZ + 1
		bar.Parent = strip
	end

	return strip
end

function AEM_UIKit.createOnyxDripOverlay(
	parent: Instance,
	tendrilCount: number,
	fromBottom: boolean,
	zIndex: number?
): Frame
	local baseZ = zIndex or 4
	local holder = Instance.new("Frame")
	holder.Name = if fromBottom then "OnyxDripBottom" else "OnyxDripTop"
	holder.Size = UDim2.fromScale(1, 1)
	holder.Position = UDim2.fromScale(0, 0)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.Active = false
	holder.Interactable = false
	holder.ZIndex = baseZ
	holder.Parent = parent

	local baseBand = Instance.new("Frame")
	baseBand.Name = "DripBaseBand"
	baseBand.Size = UDim2.fromScale(1, 0.006)
	baseBand.Position = if fromBottom then UDim2.fromScale(0, 0.994) else UDim2.fromScale(0, 0)
	baseBand.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	baseBand.BackgroundTransparency = 0.82
	baseBand.BorderSizePixel = 0
	baseBand.ZIndex = baseZ
	baseBand.Parent = holder

	local count = math.max(4, tendrilCount)
	for i = 1, count do
		local t = (i - 0.5) / count
		local hScale = 0.012 + ((math.sin(i * 2.37) + 1) * 0.5) * 0.020
		local wPx = 1 + (i % 3)

		local tendril = Instance.new("Frame")
		tendril.Name = "OnyxTendril_" .. tostring(i)
		tendril.AnchorPoint = Vector2.new(0.5, if fromBottom then 1 else 0)
		tendril.Position = UDim2.fromScale(t, if fromBottom then 1 else 0)
		tendril.Size = UDim2.new(0, wPx, hScale, 0)
		tendril.BackgroundColor3 = AEM_UIKit.VOID_GLASS
		tendril.BackgroundTransparency = 0.78
		tendril.BorderSizePixel = 0
		tendril.ZIndex = baseZ
		tendril.Parent = holder

		local gloss = Instance.new("Frame")
		gloss.Name = "GlossSpec"
		gloss.Size = UDim2.new(0, 1, 0.58, 0)
		gloss.Position = UDim2.fromScale(0.30, if fromBottom then 0.24 else 0.14)
		gloss.BackgroundColor3 = AEM_UIKit.BOSS_CRIMSON
		gloss.BackgroundTransparency = 0.72
		gloss.BorderSizePixel = 0
		gloss.ZIndex = baseZ + 1
		gloss.Parent = tendril
	end

	return holder
end

function AEM_UIKit.createCRTScanlineLayer(parent: Instance, baseZ: number?): CRTLayerHandle
	local z = baseZ or 2
	local root = Instance.new("Frame")
	root.Name = "AEM_AtmosphericOverlay"
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromScale(0, 0)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Active = false
	root.Interactable = false
	root.ZIndex = z
	root.Parent = parent

	local sweepBar = Instance.new("Frame")
	sweepBar.Name = "PhosphorSweep"
	sweepBar.Size = UDim2.new(1, 0, 0, 1)
	sweepBar.BackgroundTransparency = 1
	sweepBar.Visible = false
	sweepBar.Parent = root

	local function makeEdgeStrip(name: string, pos: UDim2, size: UDim2, color: Color3, fadeLeftToRight: boolean): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Visible = false
		f.Active = false
		f.Interactable = false
		f.ZIndex = z + 2
		f.Parent = root

		local grad = Instance.new("UIGradient")
		grad.Rotation = 0
		if fadeLeftToRight then
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
		else
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			})
		end
		grad.Parent = f
		return f
	end

	local leftRed = makeEdgeStrip("AberrationLeftCrimson", UDim2.new(0, 0, 0, 0), UDim2.new(0, 3, 1, 0), AEM_UIKit.BOSS_CRIMSON, true)
	local leftGreen = makeEdgeStrip("AberrationLeftGold", UDim2.new(0, 2, 0, 0), UDim2.new(0, 2, 1, 0), AEM_UIKit.AMBER_WIRE, true)
	local rightRed = makeEdgeStrip("AberrationRightCrimson", UDim2.new(1, -3, 0, 0), UDim2.new(0, 3, 1, 0), AEM_UIKit.BOSS_CRIMSON, false)
	local rightGreen = makeEdgeStrip("AberrationRightGold", UDim2.new(1, -4, 0, 0), UDim2.new(0, 2, 1, 0), AEM_UIKit.AMBER_WIRE, false)

	local function setAberration(amount: number): ()
		local clamped = math.clamp(amount, 0, 1)
		if clamped <= 0.02 then
			leftRed.Visible = false
			leftGreen.Visible = false
			rightRed.Visible = false
			rightGreen.Visible = false
			leftRed.BackgroundTransparency = 1
			rightRed.BackgroundTransparency = 1
			leftGreen.BackgroundTransparency = 1
			rightGreen.BackgroundTransparency = 1
			return
		end
		local crimsonT = 1 - clamped * 0.18
		local amberT = 1 - clamped * 0.10
		leftRed.Visible = true
		leftGreen.Visible = true
		rightRed.Visible = true
		rightGreen.Visible = true
		leftRed.BackgroundTransparency = crimsonT
		rightRed.BackgroundTransparency = crimsonT
		leftGreen.BackgroundTransparency = amberT
		rightGreen.BackgroundTransparency = amberT
	end

	return {
		root = root,
		sweepBar = sweepBar,
		leftRed = leftRed,
		leftGreen = leftGreen,
		rightRed = rightRed,
		rightGreen = rightGreen,
		setAberration = setAberration,
	}
end

function AEM_UIKit.asciiBar(ratio: number, segments: number?): string
	local count = segments or 10
	local clamped = math.clamp(ratio, 0, 1)
	local filled = math.floor(clamped * count + 0.5)
	if clamped > 0 and filled == 0 then
		filled = 1
	end
	return string.rep("█", filled) .. string.rep("░", count - filled)
end

local GLITCH_CHARS = { "!", "3", "_", "#", "@", "7", "%" }

function AEM_UIKit.corruptName(rawName: string, tickSeed: number): string
	local len = #rawName
	if len <= 2 then
		return "!_" .. rawName
	end
	local out: { string } = {}
	local idxA = (tickSeed % len) + 1
	local idxB = ((tickSeed * 3 + 2) % len) + 1
	for i = 1, len do
		local ch = string.sub(rawName, i, i)
		if i == idxA or i == idxB then
			ch = GLITCH_CHARS[((tickSeed + i) % #GLITCH_CHARS) + 1]
		end
		table.insert(out, ch)
	end
	return table.concat(out)
end

-- ============================================================================
-- Feature F2: Procedural Vector Primitives & Kairos-09 Wireframe Builders
-- ============================================================================

local function drawLinePx(
	parent: Instance,
	name: string,
	p1: Vector2,
	p2: Vector2,
	thickness: number,
	color: Color3,
	transparency: number?,
	zIndex: number?,
	glow: boolean?
): Frame
	local delta = p2 - p1
	local len = delta.Magnitude
	local mid = (p1 + p2) * 0.5
	local angle = math.deg(math.atan2(delta.Y, delta.X))
	local t = math.max(1, thickness)
	local alpha = if transparency ~= nil then transparency else 0.08
	local z = zIndex or 1

	if glow == true then
		local halo = Instance.new("Frame")
		halo.Name = name .. "_Glow"
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromOffset(mid.X, mid.Y)
		halo.Size = UDim2.fromOffset(len + t + 2, t + 2.5)
		halo.Rotation = angle
		halo.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
		halo.BackgroundTransparency = math.clamp(alpha + 0.74, 0.78, 0.94)
		halo.BorderSizePixel = 0
		halo.Active = false
		halo.ZIndex = math.max(1, z - 1)
		halo.Parent = parent
	end

	local line = Instance.new("Frame")
	line.Name = name
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset(mid.X, mid.Y)
	line.Size = UDim2.fromOffset(len + t * 0.45, t)
	line.Rotation = angle
	line.BackgroundColor3 = color
	line.BackgroundTransparency = alpha
	line.BorderSizePixel = 0
	line.Active = false
	line.ZIndex = z
	line.Parent = parent
	return line
end

local function drawPolylinePx(
	parent: Instance,
	prefix: string,
	pts: { Vector2 },
	thickness: number,
	color: Color3,
	transparency: number?,
	zIndex: number?,
	closed: boolean?,
	glow: boolean?
): { Frame }
	local lines: { Frame } = {}
	local n = #pts
	if n < 2 then
		return lines
	end
	local last = if closed then n else n - 1
	for i = 1, last do
		local a = pts[i]
		local b = pts[(i % n) + 1]
		table.insert(lines, drawLinePx(parent, prefix .. "_" .. tostring(i), a, b, thickness, color, transparency, zIndex, glow))
	end
	return lines
end

local function drawArcPx(
	parent: Instance,
	prefix: string,
	center: Vector2,
	radius: number,
	startDeg: number,
	endDeg: number,
	steps: number,
	thickness: number,
	color: Color3,
	transparency: number?,
	zIndex: number?,
	glow: boolean?
): { Frame }
	local pts: { Vector2 } = {}
	local stepCount = math.max(1, steps)
	for i = 0, stepCount do
		local rad = math.rad(startDeg + (endDeg - startDeg) * (i / stepCount))
		table.insert(pts, Vector2.new(center.X + math.cos(rad) * radius, center.Y + math.sin(rad) * radius))
	end
	return drawPolylinePx(parent, prefix, pts, thickness, color, transparency, zIndex, false, glow)
end

AEM_UIKit.drawLinePx = drawLinePx
AEM_UIKit.drawPolylinePx = drawPolylinePx
AEM_UIKit.drawArcPx = drawArcPx

function AEM_UIKit.createInvertedTriangleLogo(parent: Instance, sizePx: number?, color: Color3?): Frame
	local sz = sizePx or 44
	local col = color or AEM_UIKit.AMBER_WIRE
	local baseZ = 12

	local root = Instance.new("Frame")
	root.Name = "AEM_InvertedTriangleLogo"
	root.Size = UDim2.fromOffset(sz, sz)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = false
	root.Active = false
	root.ZIndex = baseZ
	root.Parent = parent

	-- Outer Inverted Triangle (▼)
	local p1 = Vector2.new(0.08, 0.14) * sz
	local p2 = Vector2.new(0.92, 0.14) * sz
	local p3 = Vector2.new(0.50, 0.88) * sz
	drawPolylinePx(root, "OuterTri", { p1, p2, p3 }, math.max(1.5, sz * 0.042), col, 0.08, baseZ + 1, true, true)

	-- Inner Concentric Inverted Triangle (▼)
	local i1 = Vector2.new(0.23, 0.23) * sz
	local i2 = Vector2.new(0.77, 0.23) * sz
	local i3 = Vector2.new(0.50, 0.70) * sz
	drawPolylinePx(root, "InnerTri", { i1, i2, i3 }, math.max(1.0, sz * 0.025), col, 0.26, baseZ + 1, true, false)

	-- Radial Struts + Core Diamond + Center Node
	local centroid = Vector2.new(0.50, 0.39) * sz
	local stopDist = 0.10 * sz
	local innerVerts = { i1, i2, i3 }
	for idx, v in ipairs(innerVerts) do
		local vec = centroid - v
		if vec.Magnitude > stopDist + 1 then
			local stopPt = centroid - vec.Unit * stopDist
			drawLinePx(root, "TriStrut_" .. tostring(idx), v, stopPt, 1, col, 0.48, baseZ, false)
		end
	end

	local coreDia = Instance.new("Frame")
	coreDia.Name = "CoreDiamond"
	coreDia.AnchorPoint = Vector2.new(0.5, 0.5)
	coreDia.Position = UDim2.fromOffset(centroid.X, centroid.Y)
	coreDia.Size = UDim2.fromOffset(math.max(5, sz * 0.15), math.max(5, sz * 0.15))
	coreDia.Rotation = 45
	coreDia.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	coreDia.BackgroundTransparency = 0.55
	coreDia.BorderSizePixel = 0
	coreDia.Active = false
	coreDia.ZIndex = baseZ + 2
	coreDia.Parent = root
	AEM_UIKit.applyBevelStroke(coreDia, col, 1.2, 0.12, Enum.LineJoinMode.Miter)

	local centerDot = Instance.new("Frame")
	centerDot.Name = "CenterDot"
	centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	centerDot.Position = UDim2.fromOffset(centroid.X, centroid.Y)
	centerDot.Size = UDim2.fromOffset(math.max(2, sz * 0.06), math.max(2, sz * 0.06))
	centerDot.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
	centerDot.BackgroundTransparency = 0.05
	centerDot.BorderSizePixel = 0
	centerDot.Active = false
	centerDot.ZIndex = baseZ + 3
	centerDot.Parent = root

	return root
end

function AEM_UIKit.createWireBracketFrame(parent: Instance, props: WireBracketFrameProps): Frame
	local baseZ = props.zIndex or 10
	local bgAlpha = if props.bgTransparency ~= nil
		then (if props.bgTransparency >= 0.999 then 1 else math.clamp(props.bgTransparency, 0.7801, 1))
		else 1

	local root = Instance.new("Frame")
	root.Name = props.name or "WireBracketFrame"
	root.Size = props.size
	root.Position = props.position
	if props.anchorPoint ~= nil then
		root.AnchorPoint = props.anchorPoint
	end
	root.BackgroundColor3 = props.bgColor or AEM_UIKit.VOID_GLASS
	root.BackgroundTransparency = bgAlpha
	root.BorderSizePixel = 0
	root.ClipsDescendants = if props.clipsDescendants ~= nil then props.clipsDescendants else false
	root.ZIndex = baseZ
	root.Parent = parent

	local t = math.clamp(props.bracketThickness or 1.25, 1, 1.5)
	local len = props.bracketLength or 12
	local alpha = if props.bracketTransparency ~= nil then props.bracketTransparency else 0.14
	local col = props.bracketColor or AEM_UIKit.AMBER_WIRE
	local useGlow = props.glow ~= false
	local mode = props.mode or "Corners"

	local function addSeg(segParent: Instance, segName: string, anchor: Vector2, pos: UDim2, sz: UDim2): ()
		if useGlow then
			local halo = Instance.new("Frame")
			halo.Name = segName .. "_Glow"
			halo.AnchorPoint = anchor
			halo.Position = pos
			halo.Size = UDim2.new(sz.X.Scale, sz.X.Offset + 2.5, sz.Y.Scale, sz.Y.Offset + 2.5)
			halo.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
			halo.BackgroundTransparency = 0.84
			halo.BorderSizePixel = 0
			halo.Active = false
			halo.ZIndex = baseZ + 1
			halo.Parent = segParent
		end
		local seg = Instance.new("Frame")
		seg.Name = segName
		seg.AnchorPoint = anchor
		seg.Position = pos
		seg.Size = sz
		seg.BackgroundColor3 = col
		seg.BackgroundTransparency = alpha
		seg.BorderSizePixel = 0
		seg.Active = false
		seg.ZIndex = baseZ + 2
		seg.Parent = segParent
	end

	if mode == "Corners" then
		local corners = {
			{ x = 0, y = 0, ax = 0, ay = 0 },
			{ x = 1, y = 0, ax = 1, ay = 0 },
			{ x = 0, y = 1, ax = 0, ay = 1 },
			{ x = 1, y = 1, ax = 1, ay = 1 },
		}
		for idx, c in ipairs(corners) do
			local anchor = Vector2.new(c.ax, c.ay)
			local pos = UDim2.fromScale(c.x, c.y)
			addSeg(root, "BracketH_" .. tostring(idx), anchor, pos, UDim2.fromOffset(len, t))
			addSeg(root, "BracketV_" .. tostring(idx), anchor, pos, UDim2.fromOffset(t, len))
		end
	elseif mode == "LeftRight" then
		addSeg(root, "BracketLeftRail", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0, t, 1, 0))
		addSeg(root, "BracketLeftTop", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromOffset(len, t))
		addSeg(root, "BracketLeftBot", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromOffset(len, t))
		addSeg(root, "BracketRightRail", Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0, t, 1, 0))
		addSeg(root, "BracketRightTop", Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromOffset(len, t))
		addSeg(root, "BracketRightBot", Vector2.new(1, 1), UDim2.fromScale(1, 1), UDim2.fromOffset(len, t))
	elseif mode == "TopBottom" then
		local vStub = math.min(len, 8)
		local corners = {
			{ x = 0, y = 0, ax = 0, ay = 0 },
			{ x = 1, y = 0, ax = 1, ay = 0 },
			{ x = 0, y = 1, ax = 0, ay = 1 },
			{ x = 1, y = 1, ax = 1, ay = 1 },
		}
		for idx, c in ipairs(corners) do
			local anchor = Vector2.new(c.ax, c.ay)
			local pos = UDim2.fromScale(c.x, c.y)
			addSeg(root, "TopBotH_" .. tostring(idx), anchor, pos, UDim2.fromOffset(len, t))
			addSeg(root, "TopBotV_" .. tostring(idx), anchor, pos, UDim2.fromOffset(t, vStub))
		end
	elseif mode == "LeftSlanted" then
		local slantContainer = Instance.new("Frame")
		slantContainer.Name = "SlantedRailContainer"
		slantContainer.AnchorPoint = Vector2.new(0.5, 0.5)
		slantContainer.Position = UDim2.new(0, -6, 0.5, 0)
		slantContainer.Size = UDim2.new(0, 10, 1, 0)
		slantContainer.Rotation = props.slantDeg or -8
		slantContainer.BackgroundTransparency = 1
		slantContainer.BorderSizePixel = 0
		slantContainer.ClipsDescendants = false
		slantContainer.Active = false
		slantContainer.ZIndex = baseZ + 1
		slantContainer.Parent = root

		addSeg(slantContainer, "SlantRail", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0, t, 1, 0))
		addSeg(slantContainer, "SlantTopSerif", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromOffset(6, t))
		addSeg(slantContainer, "SlantBotSerif", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromOffset(6, t))
	end

	return root
end

function AEM_UIKit.createSlantedGauge(parent: Instance, props: SlantedGaugeProps): SlantedGaugeHandle
	local baseZ = props.zIndex or 12
	local barH = props.barHeight or 4
	local slantDeg = if props.slantDeg ~= nil then props.slantDeg else -2.0
	local defaultFill = props.fillColor or AEM_UIKit.IVORY_TEXT
	local glowCol = props.glowColor or AEM_UIKit.AMBER_WIRE

	local root = Instance.new("Frame")
	root.Name = props.name or "SlantedGauge"
	root.Size = props.size or UDim2.fromOffset(252, 26)
	root.Position = props.position or UDim2.fromOffset(0, 0)
	if props.anchorPoint ~= nil then
		root.AnchorPoint = props.anchorPoint
	end
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = false
	root.ZIndex = baseZ
	root.Parent = parent

	local labelLeft = Instance.new("TextLabel")
	labelLeft.Name = "LabelLeft"
	labelLeft.BackgroundTransparency = 1
	labelLeft.BorderSizePixel = 0
	labelLeft.Position = UDim2.fromOffset(2, 0)
	labelLeft.Size = UDim2.new(0.55, 0, 0, 16)
	labelLeft.Rotation = 0
	labelLeft.FontFace = AEM_UIKit.FONT_DISPLAY_BOLD
	labelLeft.TextSize = 14
	labelLeft.TextScaled = false
	labelLeft.TextColor3 = AEM_UIKit.IVORY_TEXT
	labelLeft.TextXAlignment = Enum.TextXAlignment.Left
	labelLeft.TextYAlignment = Enum.TextYAlignment.Center
	labelLeft.Text = props.labelLeftText or "HP"
	labelLeft.ZIndex = baseZ + 4
	AEM_UIKit.applyTextContrast(labelLeft)
	labelLeft.Parent = root

	local labelRight = Instance.new("TextLabel")
	labelRight.Name = "LabelRight"
	labelRight.BackgroundTransparency = 1
	labelRight.BorderSizePixel = 0
	labelRight.Position = UDim2.new(0.45, -2, 0, -2)
	labelRight.Size = UDim2.new(0.55, 0, 0, 16)
	labelRight.Rotation = 0
	labelRight.FontFace = AEM_UIKit.FONT_FACE_BOLD
	labelRight.TextSize = 14
	labelRight.TextScaled = false
	labelRight.TextColor3 = AEM_UIKit.IVORY_TEXT
	labelRight.TextXAlignment = Enum.TextXAlignment.Right
	labelRight.TextYAlignment = Enum.TextYAlignment.Center
	labelRight.Text = props.labelRightText or "100%"
	labelRight.ZIndex = baseZ + 4
	AEM_UIKit.applyTextContrast(labelRight)
	labelRight.Parent = root

	local trackPivot = Instance.new("Frame")
	trackPivot.Name = "TrackPivot"
	trackPivot.AnchorPoint = Vector2.new(0.5, 0.5)
	trackPivot.Position = UDim2.new(0.5, 0, 1, -5)
	trackPivot.Size = UDim2.new(1, 0, 0, barH)
	trackPivot.Rotation = slantDeg
	trackPivot.BackgroundTransparency = 1
	trackPivot.BorderSizePixel = 0
	trackPivot.ClipsDescendants = false
	trackPivot.ZIndex = baseZ
	trackPivot.Parent = root

	local glowUnderlay = Instance.new("Frame")
	glowUnderlay.Name = "GlowUnderlay"
	glowUnderlay.AnchorPoint = Vector2.new(0, 0.5)
	glowUnderlay.Position = UDim2.fromScale(0, 0.5)
	glowUnderlay.Size = UDim2.new(1, 2, 1, 4)
	glowUnderlay.BackgroundColor3 = glowCol
	glowUnderlay.BackgroundTransparency = 0.85
	glowUnderlay.BorderSizePixel = 0
	glowUnderlay.ZIndex = baseZ
	glowUnderlay.Parent = trackPivot

	local trackClip = Instance.new("Frame")
	trackClip.Name = "TrackClip"
	trackClip.Size = UDim2.fromScale(1, 1)
	trackClip.Position = UDim2.fromScale(0, 0)
	trackClip.BackgroundColor3 = props.trackColor or AEM_UIKit.VOID_GLASS
	trackClip.BackgroundTransparency = if props.trackTransparency ~= nil then props.trackTransparency else 0.76
	trackClip.BorderSizePixel = 0
	trackClip.ClipsDescendants = true
	trackClip.ZIndex = baseZ + 1
	trackClip.Parent = trackPivot

	local baseline = Instance.new("Frame")
	baseline.Name = "AmberBaseline"
	baseline.Size = UDim2.new(1, 0, 0, 1)
	baseline.Position = UDim2.new(0, 0, 1, -1)
	baseline.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
	baseline.BackgroundTransparency = 0.45
	baseline.BorderSizePixel = 0
	baseline.ZIndex = baseZ + 1
	baseline.Parent = trackClip

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.Position = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = defaultFill
	fill.BackgroundTransparency = 0.05
	fill.BorderSizePixel = 0
	fill.ZIndex = baseZ + 2
	fill.Parent = trackClip

	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 224, 170)),
	})
	fillGrad.Parent = fill

	if props.showEndTicks ~= false then
		for _, spec in ipairs({
			{ name = "LeftTick", x = 0 },
			{ name = "RightTick", x = 1 },
		}) do
			local tick = Instance.new("Frame")
			tick.Name = spec.name
			tick.AnchorPoint = Vector2.new(0.5, 0.5)
			tick.Position = UDim2.fromScale(spec.x, 0.5)
			tick.Size = UDim2.fromOffset(1.5, barH + 5)
			tick.Rotation = 14
			tick.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
			tick.BackgroundTransparency = 0.25
			tick.BorderSizePixel = 0
			tick.ZIndex = baseZ + 3
			tick.Parent = trackPivot
		end
	end

	local lastRatio = -1
	local lastColor: Color3? = nil
	local activeTween: Tween? = nil
	local activeGlowTween: Tween? = nil

	local function setPercent(pct: number, fillColorOverride: Color3?, rightTextOverride: string?): ()
		local clamped = math.clamp(pct, 0, 100)
		local ratio = clamped / 100
		labelRight.Text = rightTextOverride or string.format("%d%%", math.round(clamped))

		local targetColor = fillColorOverride or defaultFill
		if lastColor ~= targetColor then
			fill.BackgroundColor3 = targetColor
			lastColor = targetColor
		end

		if math.abs(ratio - lastRatio) < 0.004 then
			return
		end
		lastRatio = ratio

		if activeTween ~= nil then
			activeTween:Cancel()
		end
		if activeGlowTween ~= nil then
			activeGlowTween:Cancel()
		end

		local twInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local twFill = TweenService:Create(fill, twInfo, { Size = UDim2.fromScale(ratio, 1) })
		local twGlow = TweenService:Create(glowUnderlay, twInfo, { Size = UDim2.new(ratio, 2, 1, 4) })
		activeTween = twFill
		activeGlowTween = twGlow
		twFill:Play()
		twGlow:Play()
	end

	return {
		root = root,
		fill = fill,
		labelLeft = labelLeft,
		labelRight = labelRight,
		setPercent = setPercent,
	}
end

local function sampleBossGradientColor(t: number): Color3
	local c0 = Color3.fromRGB(255, 144, 0) -- #FF9000
	local c1 = Color3.fromRGB(232, 80, 0) -- #E85000
	local c2 = Color3.fromRGB(212, 34, 24) -- #D42218
	local clamped = math.clamp(t, 0, 1)
	if clamped <= 0.5 then
		return c0:Lerp(c1, clamped * 2)
	end
	return c1:Lerp(c2, (clamped - 0.5) * 2)
end

function AEM_UIKit.createSegmentedBossBar(parent: Instance, props: SegmentedBossBarProps): SegmentedBossBarHandle
	local baseZ = props.zIndex or 12
	local segCount = math.max(4, props.segments or 24)
	local widthPx = props.widthPx or 740
	local barH = props.barHeightPx or 15
	local archDepth = if props.archDepthPx ~= nil then props.archDepthPx else 5

	local root = Instance.new("Frame")
	root.Name = props.name or "SegmentedBossBar"
	root.Size = UDim2.fromOffset(widthPx + 130, barH + 46)
	root.Position = props.position or UDim2.new(0.5, 0, 0, 58)
	root.AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = false
	root.ZIndex = baseZ
	root.Parent = parent

	local headerLabel = Instance.new("TextLabel")
	headerLabel.Name = "HeaderLabel"
	headerLabel.BackgroundTransparency = 1
	headerLabel.BorderSizePixel = 0
	headerLabel.Position = UDim2.fromOffset(0, 0)
	headerLabel.Size = UDim2.new(1, 0, 0, 20)
	headerLabel.FontFace = AEM_UIKit.FONT_DISPLAY_BOLD
	headerLabel.TextSize = 16
	headerLabel.TextScaled = false
	headerLabel.TextColor3 = AEM_UIKit.IVORY_TEXT
	headerLabel.TextXAlignment = Enum.TextXAlignment.Center
	headerLabel.TextYAlignment = Enum.TextYAlignment.Center
	headerLabel.Text = props.headerText or "STAGE II: THE APEX VESSEL // ONYX MUTATION"
	headerLabel.ZIndex = baseZ + 5
	AEM_UIKit.applyTextContrast(headerLabel)
	headerLabel.Parent = root

	local barArea = Instance.new("Frame")
	barArea.Name = "BarArea"
	barArea.AnchorPoint = Vector2.new(0.5, 0)
	barArea.Position = UDim2.new(0.5, 0, 0, 24)
	barArea.Size = UDim2.fromOffset(widthPx, barH + archDepth + 6)
	barArea.BackgroundTransparency = 1
	barArea.BorderSizePixel = 0
	barArea.ClipsDescendants = false
	barArea.ZIndex = baseZ
	barArea.Parent = root

	local gap = 3
	local segW = (widthPx - (segCount - 1) * gap) / segCount
	local segFills: { Frame } = {}

	for i = 1, segCount do
		local xCenter = (i - 0.5) * (segW + gap) - gap * 0.5
		local u = ((i - 0.5) / segCount) * 2 - 1
		local yDrop = archDepth * (1 - u * u)
		local rotDeg = -u * 2.5

		local segCell = Instance.new("Frame")
		segCell.Name = "Segment_" .. tostring(i)
		segCell.AnchorPoint = Vector2.new(0.5, 0.5)
		segCell.Position = UDim2.fromOffset(xCenter, barH * 0.5 + 3 + yDrop)
		segCell.Size = UDim2.fromOffset(math.max(2, math.floor(segW)), barH)
		segCell.Rotation = rotDeg
		segCell.BackgroundColor3 = Color3.fromRGB(22, 13, 6)
		segCell.BackgroundTransparency = 0.68
		segCell.BorderSizePixel = 0
		segCell.ClipsDescendants = true
		segCell.ZIndex = baseZ + 1
		segCell.Parent = barArea

		AEM_UIKit.applyBevelStroke(segCell, AEM_UIKit.AMBER_WIRE, 1, 0.68, Enum.LineJoinMode.Miter)

		local segFill = Instance.new("Frame")
		segFill.Name = "Fill"
		segFill.Size = UDim2.fromScale(1, 1)
		segFill.Position = UDim2.fromScale(0, 0)
		segFill.BackgroundColor3 = Color3.new(1, 1, 1)
		segFill.BackgroundTransparency = 0.08
		segFill.BorderSizePixel = 0
		segFill.ZIndex = baseZ + 2
		segFill.Parent = segCell

		local tA = (i - 1) / segCount
		local tB = i / segCount
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, sampleBossGradientColor(tA)),
			ColorSequenceKeypoint.new(1, sampleBossGradientColor(tB)),
		})
		grad.Parent = segFill

		table.insert(segFills, segFill)
	end

	-- Outer Arched Wireframe Rails
	local railTopPts: { Vector2 } = {}
	local railBotPts: { Vector2 } = {}
	for s = 0, 12 do
		local frac = s / 12
		local u = frac * 2 - 1
		local drop = archDepth * (1 - u * u)
		local rx = frac * widthPx
		table.insert(railTopPts, Vector2.new(rx, drop))
		table.insert(railBotPts, Vector2.new(rx, barH + 6 + drop))
	end
	drawPolylinePx(barArea, "OuterRailTop", railTopPts, 1.2, AEM_UIKit.AMBER_WIRE, 0.25, baseZ + 3, false, true)
	drawPolylinePx(barArea, "OuterRailBot", railBotPts, 1.2, AEM_UIKit.AMBER_WIRE, 0.25, baseZ + 3, false, true)
	drawLinePx(barArea, "OuterCapLeft", railTopPts[1], railBotPts[1], 1.2, AEM_UIKit.AMBER_WIRE, 0.25, baseZ + 3, false)
	drawLinePx(barArea, "OuterCapRight", railTopPts[#railTopPts], railBotPts[#railBotPts], 1.2, AEM_UIKit.AMBER_WIRE, 0.25, baseZ + 3, false)

	-- Flanking ( ) Wireframe End Brackets
	local midY = barH * 0.5 + 3
	drawArcPx(barArea, "BracketLeft", Vector2.new(-8, midY), 14, 128, 232, 7, 2.0, AEM_UIKit.AMBER_GLOW, 0.10, baseZ + 4, true)
	drawArcPx(barArea, "BracketRight", Vector2.new(widthPx + 8, midY), 14, -52, 52, 7, 2.0, AEM_UIKit.AMBER_GLOW, 0.10, baseZ + 4, true)

	-- Outward /// Slanted Hazard Slashes
	for idx, offsetX in ipairs({ -34, -40, -46 }) do
		local slashL = Instance.new("Frame")
		slashL.Name = "HazardSlashLeft_" .. tostring(idx)
		slashL.AnchorPoint = Vector2.new(0.5, 0.5)
		slashL.Position = UDim2.fromOffset(offsetX, midY)
		slashL.Size = UDim2.fromOffset(2, 10)
		slashL.Rotation = 28
		slashL.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
		slashL.BackgroundTransparency = 0.16 + (idx - 1) * 0.20
		slashL.BorderSizePixel = 0
		slashL.ZIndex = baseZ + 3
		slashL.Parent = barArea
	end
	for idx, offsetX in ipairs({ widthPx + 34, widthPx + 40, widthPx + 46 }) do
		local slashR = Instance.new("Frame")
		slashR.Name = "HazardSlashRight_" .. tostring(idx)
		slashR.AnchorPoint = Vector2.new(0.5, 0.5)
		slashR.Position = UDim2.fromOffset(offsetX, midY)
		slashR.Size = UDim2.fromOffset(2, 10)
		slashR.Rotation = 28
		slashR.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
		slashR.BackgroundTransparency = 0.16 + (idx - 1) * 0.20
		slashR.BorderSizePixel = 0
		slashR.ZIndex = baseZ + 3
		slashR.Parent = barArea
	end

	-- Active Cutoff Tick (#FFF2D6 + Amber Glow Halo)
	local cutoffHalo = Instance.new("Frame")
	cutoffHalo.Name = "CutoffHalo"
	cutoffHalo.AnchorPoint = Vector2.new(0.5, 0.5)
	cutoffHalo.Size = UDim2.fromOffset(7, barH + 10)
	cutoffHalo.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
	cutoffHalo.BackgroundTransparency = 0.60
	cutoffHalo.BorderSizePixel = 0
	cutoffHalo.Visible = false
	cutoffHalo.ZIndex = baseZ + 5
	cutoffHalo.Parent = barArea

	local cutoffTick = Instance.new("Frame")
	cutoffTick.Name = "CutoffTick"
	cutoffTick.AnchorPoint = Vector2.new(0.5, 0.5)
	cutoffTick.Size = UDim2.fromOffset(3, barH + 8)
	cutoffTick.BackgroundColor3 = Color3.fromRGB(255, 242, 214)
	cutoffTick.BackgroundTransparency = 0.04
	cutoffTick.BorderSizePixel = 0
	cutoffTick.Visible = false
	cutoffTick.ZIndex = baseZ + 6
	cutoffTick.Parent = barArea

	-- Subtext Micro-Telemetry
	local subLeft = Instance.new("TextLabel")
	subLeft.Name = "SubLeft"
	subLeft.BackgroundTransparency = 1
	subLeft.BorderSizePixel = 0
	subLeft.Position = UDim2.fromOffset(0, barH + archDepth + 8)
	subLeft.Size = UDim2.new(0.48, 0, 0, 14)
	subLeft.FontFace = AEM_UIKit.FONT_FACE_MEDIUM
	subLeft.TextSize = 10
	subLeft.TextScaled = false
	subLeft.TextColor3 = AEM_UIKit.AMBER_SOFT
	subLeft.TextXAlignment = Enum.TextXAlignment.Left
	subLeft.TextYAlignment = Enum.TextYAlignment.Center
	subLeft.Text = props.subLeftText or ""
	subLeft.ZIndex = baseZ + 4
	AEM_UIKit.applyTextContrast(subLeft)
	subLeft.Parent = barArea

	local subRight = Instance.new("TextLabel")
	subRight.Name = "SubRight"
	subRight.BackgroundTransparency = 1
	subRight.BorderSizePixel = 0
	subRight.Position = UDim2.new(0.52, 0, 0, barH + archDepth + 8)
	subRight.Size = UDim2.new(0.48, 0, 0, 14)
	subRight.FontFace = AEM_UIKit.FONT_FACE_MEDIUM
	subRight.TextSize = 10
	subRight.TextScaled = false
	subRight.TextColor3 = AEM_UIKit.AMBER_SOFT
	subRight.TextXAlignment = Enum.TextXAlignment.Right
	subRight.TextYAlignment = Enum.TextYAlignment.Center
	subRight.Text = props.subRightText or ""
	subRight.ZIndex = baseZ + 4
	AEM_UIKit.applyTextContrast(subRight)
	subRight.Parent = barArea

	local function setProgress(ratio: number): ()
		local clamped = math.clamp(ratio, 0, 1)
		local exact = clamped * segCount
		for i, segFill in ipairs(segFills) do
			local segFrac = math.clamp(exact - (i - 1), 0, 1)
			segFill.Visible = segFrac > 0.005
			segFill.Size = UDim2.fromScale(segFrac, 1)
		end

		local showCutoff = clamped > 0.002 and clamped < 0.998
		cutoffTick.Visible = showCutoff
		cutoffHalo.Visible = showCutoff
		if showCutoff then
			local u = clamped * 2 - 1
			local cy = barH * 0.5 + 3 + archDepth * (1 - u * u)
			local cx = clamped * widthPx
			local rot = -u * 2.5
			cutoffTick.Position = UDim2.fromOffset(cx, cy)
			cutoffTick.Rotation = rot
			cutoffHalo.Position = UDim2.fromOffset(cx, cy)
			cutoffHalo.Rotation = rot
		end
	end

	local function setHeader(text: string): ()
		headerLabel.Text = text
	end

	local function setSubtext(left: string?, right: string?): ()
		if left ~= nil then
			subLeft.Text = left
		end
		if right ~= nil then
			subRight.Text = right
		end
	end

	setProgress(1)

	return {
		root = root,
		setProgress = setProgress,
		setHeader = setHeader,
		setSubtext = setSubtext,
	}
end

AEM_UIKit.SKILL_ID_TO_GLYPH = table.freeze({
	HarpoonTether = "harpoon",
	DeployDome = "dome",
	PlanetScanner = "scanner",
	DrawIonRifle = "ion_rifle",
	PersonalMatrix = "matrix",
	HealingBurst = "heal_burst",
	HealingBeam = "heal_beam",
	ShieldProjector = "projector",
	OrbitalBarrage = "barrage",
	LeapSmash = "leap",
	FeralCharge = "charge",
	AcidBreath = "acid",
	Smell = "smell",
	EatPrey = "eat",
	EvolveStage = "evolve",
	Stealth = "stealth",
})

local function buildProceduralGlyph(container: Instance, glyphId: string, sz: number, color: Color3, baseZ: number): { Frame }
	local lines: { Frame } = {}
	local t = math.max(1.4, sz * 0.032)
	local tThin = math.max(1.1, sz * 0.022)
	local function pt(nx: number, ny: number): Vector2
		return Vector2.new(nx * sz, ny * sz)
	end
	local function pushAll(arr: { Frame }): ()
		for _, f in ipairs(arr) do
			table.insert(lines, f)
		end
	end
	local function addDot(nx: number, ny: number, pxSize: number?, diamond: boolean?): ()
		local d = pxSize or math.max(3, sz * 0.07)
		local dot = Instance.new("Frame")
		dot.Name = "GlyphNode"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromOffset(nx * sz, ny * sz)
		dot.Size = UDim2.fromOffset(d, d)
		dot.Rotation = if diamond then 45 else 0
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = 0.04
		dot.BorderSizePixel = 0
		dot.Active = false
		dot.ZIndex = baseZ
		dot.Parent = container
		table.insert(lines, dot)
	end

	if glyphId == "harpoon" then
		table.insert(lines, drawLinePx(container, "Shaft", pt(0.22, 0.78), pt(0.76, 0.24), t, color, 0.04, baseZ, false))
		pushAll(drawPolylinePx(container, "BarbOuter", { pt(0.52, 0.28), pt(0.76, 0.24), pt(0.72, 0.48) }, t, color, 0.04, baseZ, false, false))
		pushAll(drawPolylinePx(container, "BarbInner", { pt(0.44, 0.42), pt(0.64, 0.36), pt(0.58, 0.56) }, tThin, color, 0.14, baseZ, false, false))
		table.insert(lines, drawLinePx(container, "TetherTick", pt(0.22, 0.78), pt(0.28, 0.84), tThin, color, 0.08, baseZ, false))
	elseif glyphId == "dome" then
		pushAll(drawArcPx(container, "DomeOuter", pt(0.50, 0.64), 0.28 * sz, 180, 360, 8, t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "DomeBase", pt(0.18, 0.64), pt(0.82, 0.64), t, color, 0.04, baseZ, false))
		pushAll(drawArcPx(container, "DomeInner", pt(0.50, 0.64), 0.17 * sz, 195, 345, 6, tThin, color, 0.20, baseZ, false))
		table.insert(lines, drawLinePx(container, "DomeMast", pt(0.50, 0.64), pt(0.50, 0.44), tThin, color, 0.12, baseZ, false))
		addDot(0.50, 0.64, math.max(4, sz * 0.08), false)
	elseif glyphId == "scanner" then
		pushAll(drawArcPx(container, "ScanCircle", pt(0.50, 0.50), 0.22 * sz, 0, 360, 12, t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "TickN", pt(0.50, 0.20), pt(0.50, 0.31), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "TickS", pt(0.50, 0.69), pt(0.50, 0.80), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "TickW", pt(0.20, 0.50), pt(0.31, 0.50), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "TickE", pt(0.69, 0.50), pt(0.80, 0.50), t, color, 0.04, baseZ, false))
		pushAll(drawPolylinePx(container, "CornerTL", { pt(0.24, 0.34), pt(0.24, 0.24), pt(0.34, 0.24) }, tThin, color, 0.18, baseZ, false, false))
		pushAll(drawPolylinePx(container, "CornerTR", { pt(0.66, 0.24), pt(0.76, 0.24), pt(0.76, 0.34) }, tThin, color, 0.18, baseZ, false, false))
		pushAll(drawPolylinePx(container, "CornerBL", { pt(0.24, 0.66), pt(0.24, 0.76), pt(0.34, 0.76) }, tThin, color, 0.18, baseZ, false, false))
		pushAll(drawPolylinePx(container, "CornerBR", { pt(0.66, 0.76), pt(0.76, 0.76), pt(0.76, 0.66) }, tThin, color, 0.18, baseZ, false, false))
		addDot(0.50, 0.50, math.max(4, sz * 0.08), true)
	elseif glyphId == "ion_rifle" then
		table.insert(lines, drawLinePx(container, "BodyBase", pt(0.18, 0.52), pt(0.74, 0.52), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "Barrel", pt(0.34, 0.44), pt(0.74, 0.44), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "Optic", pt(0.38, 0.38), pt(0.54, 0.38), tThin, color, 0.12, baseZ, false))
		table.insert(lines, drawLinePx(container, "Stock", pt(0.18, 0.52), pt(0.22, 0.66), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "Grip", pt(0.38, 0.52), pt(0.42, 0.64), t, color, 0.04, baseZ, false))
		pushAll(drawPolylinePx(container, "Muzzle", { pt(0.79, 0.42), pt(0.85, 0.48), pt(0.79, 0.54) }, tThin, color, 0.08, baseZ, false, false))
	elseif glyphId == "matrix" then
		pushAll(drawPolylinePx(container, "ShieldCrest", { pt(0.26, 0.28), pt(0.74, 0.28), pt(0.74, 0.54), pt(0.50, 0.78), pt(0.26, 0.54) }, t, color, 0.04, baseZ, true, false))
		table.insert(lines, drawLinePx(container, "Spine", pt(0.50, 0.34), pt(0.50, 0.70), tThin, color, 0.16, baseZ, false))
		table.insert(lines, drawLinePx(container, "Cross", pt(0.33, 0.48), pt(0.67, 0.48), tThin, color, 0.16, baseZ, false))
	elseif glyphId == "heal_burst" then
		local tBold = t * 1.6
		table.insert(lines, drawLinePx(container, "CrossV", pt(0.50, 0.28), pt(0.50, 0.72), tBold, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "CrossH", pt(0.28, 0.50), pt(0.72, 0.50), tBold, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "BurstTL", pt(0.25, 0.25), pt(0.34, 0.34), tThin, color, 0.12, baseZ, false))
		table.insert(lines, drawLinePx(container, "BurstTR", pt(0.75, 0.25), pt(0.66, 0.34), tThin, color, 0.12, baseZ, false))
		table.insert(lines, drawLinePx(container, "BurstBL", pt(0.25, 0.75), pt(0.34, 0.66), tThin, color, 0.12, baseZ, false))
		table.insert(lines, drawLinePx(container, "BurstBR", pt(0.75, 0.75), pt(0.66, 0.66), tThin, color, 0.12, baseZ, false))
	elseif glyphId == "heal_beam" then
		pushAll(drawPolylinePx(container, "EmitterDia", { pt(0.24, 0.43), pt(0.31, 0.50), pt(0.24, 0.57), pt(0.17, 0.50) }, tThin, color, 0.06, baseZ, true, false))
		pushAll(drawPolylinePx(container, "Beam", { pt(0.31, 0.50), pt(0.42, 0.38), pt(0.52, 0.62), pt(0.63, 0.48) }, t, color, 0.04, baseZ, false, false))
		table.insert(lines, drawLinePx(container, "TargetV", pt(0.73, 0.40), pt(0.73, 0.60), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "TargetH", pt(0.63, 0.50), pt(0.83, 0.50), t, color, 0.04, baseZ, false))
	elseif glyphId == "projector" then
		pushAll(drawPolylinePx(container, "Emitter", { pt(0.24, 0.42), pt(0.34, 0.50), pt(0.24, 0.58) }, t, color, 0.04, baseZ, true, false))
		table.insert(lines, drawLinePx(container, "Tripod", pt(0.26, 0.58), pt(0.22, 0.68), tThin, color, 0.14, baseZ, false))
		table.insert(lines, drawLinePx(container, "RayTop", pt(0.34, 0.50), pt(0.66, 0.30), tThin, color, 0.16, baseZ, false))
		table.insert(lines, drawLinePx(container, "RayBot", pt(0.34, 0.50), pt(0.66, 0.70), tThin, color, 0.16, baseZ, false))
		pushAll(drawArcPx(container, "BarrierArc", pt(0.48, 0.50), 0.28 * sz, -50, 50, 6, t, color, 0.04, baseZ, false))
	elseif glyphId == "barrage" then
		table.insert(lines, drawLinePx(container, "Strike1", pt(0.44, 0.20), pt(0.28, 0.66), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "Strike2", pt(0.58, 0.18), pt(0.42, 0.68), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "Strike3", pt(0.72, 0.22), pt(0.56, 0.66), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "Ground", pt(0.22, 0.74), pt(0.74, 0.74), t, color, 0.04, baseZ, false))
		pushAll(drawPolylinePx(container, "ImpactChev", { pt(0.36, 0.74), pt(0.44, 0.68), pt(0.52, 0.74) }, tThin, color, 0.12, baseZ, false, false))
	elseif glyphId == "leap" then
		pushAll(drawPolylinePx(container, "Arc", { pt(0.22, 0.70), pt(0.34, 0.34), pt(0.50, 0.24), pt(0.66, 0.36), pt(0.76, 0.64) }, t, color, 0.04, baseZ, false, false))
		pushAll(drawPolylinePx(container, "Arrow", { pt(0.66, 0.58), pt(0.76, 0.64), pt(0.80, 0.52) }, t, color, 0.04, baseZ, false, false))
		table.insert(lines, drawLinePx(container, "ShockH", pt(0.64, 0.72), pt(0.84, 0.72), tThin, color, 0.14, baseZ, false))
		table.insert(lines, drawLinePx(container, "ShockL", pt(0.72, 0.72), pt(0.66, 0.80), tThin, color, 0.14, baseZ, false))
		table.insert(lines, drawLinePx(container, "ShockR", pt(0.76, 0.72), pt(0.82, 0.80), tThin, color, 0.14, baseZ, false))
	elseif glyphId == "charge" then
		pushAll(drawPolylinePx(container, "Chev1", { pt(0.26, 0.32), pt(0.42, 0.50), pt(0.26, 0.68) }, t, color, 0.10, baseZ, false, false))
		pushAll(drawPolylinePx(container, "Chev2", { pt(0.44, 0.28), pt(0.62, 0.50), pt(0.44, 0.72) }, t, color, 0.06, baseZ, false, false))
		pushAll(drawPolylinePx(container, "Chev3", { pt(0.62, 0.28), pt(0.80, 0.50), pt(0.62, 0.72) }, t, color, 0.04, baseZ, false, false))
		table.insert(lines, drawLinePx(container, "SpeedTop", pt(0.18, 0.42), pt(0.32, 0.42), tThin, color, 0.20, baseZ, false))
		table.insert(lines, drawLinePx(container, "SpeedBot", pt(0.18, 0.58), pt(0.32, 0.58), tThin, color, 0.20, baseZ, false))
	elseif glyphId == "acid" then
		pushAll(drawPolylinePx(container, "Vent", { pt(0.20, 0.44), pt(0.28, 0.50), pt(0.20, 0.56) }, t, color, 0.04, baseZ, false, false))
		table.insert(lines, drawLinePx(container, "Spray1", pt(0.28, 0.50), pt(0.74, 0.28), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "Spray2", pt(0.28, 0.50), pt(0.78, 0.50), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "Spray3", pt(0.28, 0.50), pt(0.74, 0.72), t, color, 0.04, baseZ, false))
		addDot(0.78, 0.30, math.max(4, sz * 0.08), true)
		addDot(0.76, 0.70, math.max(4, sz * 0.08), true)
	elseif glyphId == "smell" then
		addDot(0.50, 0.72, math.max(4, sz * 0.08), false)
		pushAll(drawArcPx(container, "Scent1", pt(0.50, 0.72), 0.16 * sz, 215, 325, 5, t, color, 0.04, baseZ, false))
		pushAll(drawArcPx(container, "Scent2", pt(0.50, 0.72), 0.29 * sz, 215, 325, 6, t, color, 0.08, baseZ, false))
		pushAll(drawArcPx(container, "Scent3", pt(0.50, 0.72), 0.42 * sz, 220, 320, 7, tThin, color, 0.16, baseZ, false))
	elseif glyphId == "eat" then
		pushAll(drawPolylinePx(container, "JawTop", { pt(0.24, 0.34), pt(0.36, 0.46), pt(0.50, 0.34), pt(0.64, 0.46), pt(0.76, 0.34) }, t, color, 0.04, baseZ, false, false))
		pushAll(drawPolylinePx(container, "JawBot", { pt(0.24, 0.66), pt(0.36, 0.54), pt(0.50, 0.66), pt(0.64, 0.54), pt(0.76, 0.66) }, t, color, 0.04, baseZ, false, false))
		addDot(0.50, 0.50, math.max(4, sz * 0.08), false)
	elseif glyphId == "evolve" then
		table.insert(lines, drawLinePx(container, "Spire", pt(0.50, 0.22), pt(0.50, 0.78), t, color, 0.04, baseZ, false))
		pushAll(drawPolylinePx(container, "AscTop", { pt(0.34, 0.44), pt(0.50, 0.24), pt(0.66, 0.44) }, t, color, 0.04, baseZ, false, false))
		pushAll(drawPolylinePx(container, "AscMid", { pt(0.34, 0.64), pt(0.50, 0.44), pt(0.66, 0.64) }, t, color, 0.10, baseZ, false, false))
		pushAll(drawPolylinePx(container, "Cradle", { pt(0.28, 0.52), pt(0.50, 0.78), pt(0.72, 0.52) }, tThin, color, 0.16, baseZ, false, false))
	elseif glyphId == "stealth" then
		pushAll(drawPolylinePx(container, "EyeTop", { pt(0.20, 0.50), pt(0.36, 0.34), pt(0.64, 0.34), pt(0.80, 0.50) }, t, color, 0.06, baseZ, false, false))
		pushAll(drawPolylinePx(container, "EyeBot", { pt(0.20, 0.50), pt(0.36, 0.66), pt(0.64, 0.66), pt(0.80, 0.50) }, t, color, 0.06, baseZ, false, false))
		table.insert(lines, drawLinePx(container, "SlitPupil", pt(0.50, 0.38), pt(0.50, 0.62), t, color, 0.04, baseZ, false))
		table.insert(lines, drawLinePx(container, "StealthSlash", pt(0.24, 0.74), pt(0.76, 0.26), t, color, 0.04, baseZ, false))
	else
		-- Fallback Diamond Reticle
		pushAll(drawPolylinePx(container, "FallbackDia", { pt(0.50, 0.24), pt(0.76, 0.50), pt(0.50, 0.76), pt(0.24, 0.50) }, t, color, 0.06, baseZ, true, false))
		addDot(0.50, 0.50, math.max(4, sz * 0.08), false)
	end

	return lines
end

function AEM_UIKit.createChamferedAbilityBadge(parent: Instance, props: ChamferedAbilityBadgeProps): ChamferedAbilityBadgeHandle
	local baseZ = props.zIndex or 12
	local sz = props.sizePx or 56
	local rootW = math.max(86, sz + 30)
	local rootH = sz + 42

	local root = Instance.new("Frame")
	root.Name = props.name or "ChamferedAbilityBadge"
	root.Size = UDim2.fromOffset(rootW, rootH)
	root.Position = props.position or UDim2.fromOffset(0, 0)
	if props.anchorPoint ~= nil then
		root.AnchorPoint = props.anchorPoint
	end
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = false
	root.ZIndex = baseZ
	root.Parent = parent

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.BorderSizePixel = 0
	titleLabel.Position = UDim2.fromOffset(0, 0)
	titleLabel.Size = UDim2.new(1, 0, 0, 16)
	titleLabel.FontFace = AEM_UIKit.FONT_DISPLAY_BOLD
	titleLabel.TextSize = 12
	titleLabel.TextScaled = false
	titleLabel.TextColor3 = AEM_UIKit.IVORY_TEXT
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.Text = props.label or ""
	titleLabel.ZIndex = baseZ + 4
	AEM_UIKit.applyTextContrast(titleLabel)
	titleLabel.Parent = root

	local hexContainer = Instance.new("Frame")
	hexContainer.Name = "HexContainer"
	hexContainer.AnchorPoint = Vector2.new(0.5, 0)
	hexContainer.Position = UDim2.new(0.5, 0, 0, 18)
	hexContainer.Size = UDim2.fromOffset(sz, sz)
	hexContainer.BackgroundTransparency = 1
	hexContainer.BorderSizePixel = 0
	hexContainer.ClipsDescendants = false
	hexContainer.ZIndex = baseZ + 1
	hexContainer.Parent = root

	local function hexPt(nx: number, ny: number): Vector2
		return Vector2.new(nx * sz, ny * sz)
	end

	local outerHexLines = drawPolylinePx(
		hexContainer,
		"OuterHex",
		{
			hexPt(0.50, 0.03),
			hexPt(0.93, 0.27),
			hexPt(0.93, 0.73),
			hexPt(0.50, 0.97),
			hexPt(0.07, 0.73),
			hexPt(0.07, 0.27),
		},
		1.5,
		AEM_UIKit.AMBER_WIRE,
		0.08,
		baseZ + 2,
		true,
		true
	)

	drawPolylinePx(
		hexContainer,
		"InnerHex",
		{
			hexPt(0.50, 0.11),
			hexPt(0.85, 0.30),
			hexPt(0.85, 0.70),
			hexPt(0.50, 0.89),
			hexPt(0.15, 0.70),
			hexPt(0.15, 0.30),
		},
		1.0,
		AEM_UIKit.AMBER_WIRE,
		0.45,
		baseZ + 1,
		true,
		false
	)

	local cdTrack = Instance.new("Frame")
	cdTrack.Name = "CooldownTrack"
	cdTrack.AnchorPoint = Vector2.new(0.5, 0)
	cdTrack.Position = UDim2.new(0.5, 0, 1, 2)
	cdTrack.Size = UDim2.new(0.68, 0, 0, 2)
	cdTrack.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	cdTrack.BackgroundTransparency = 0.65
	cdTrack.BorderSizePixel = 0
	cdTrack.Visible = false
	cdTrack.ZIndex = baseZ + 3
	cdTrack.Parent = hexContainer

	local cdFill = Instance.new("Frame")
	cdFill.Name = "CooldownFill"
	cdFill.Size = UDim2.fromScale(0, 1)
	cdFill.Position = UDim2.fromScale(0, 0)
	cdFill.BackgroundColor3 = AEM_UIKit.AMBER_WIRE
	cdFill.BackgroundTransparency = 0.08
	cdFill.BorderSizePixel = 0
	cdFill.ZIndex = baseZ + 4
	cdFill.Parent = cdTrack

	local glyphHolder = Instance.new("Frame")
	glyphHolder.Name = "GlyphHolder"
	glyphHolder.Size = UDim2.fromOffset(sz, sz)
	glyphHolder.Position = UDim2.fromOffset(0, 0)
	glyphHolder.BackgroundTransparency = 1
	glyphHolder.BorderSizePixel = 0
	glyphHolder.ClipsDescendants = false
	glyphHolder.ZIndex = baseZ + 3
	glyphHolder.Parent = hexContainer

	local glyphLines = buildProceduralGlyph(glyphHolder, props.glyph, sz, AEM_UIKit.IVORY_TEXT, baseZ + 3)

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.BackgroundTransparency = 1
	statusLabel.BorderSizePixel = 0
	statusLabel.Position = UDim2.fromOffset(math.round(rootW * 0.56), 18 + sz - 14)
	statusLabel.Size = UDim2.fromOffset(44, 14)
	statusLabel.FontFace = AEM_UIKit.FONT_FACE_BOLD
	statusLabel.TextSize = 11
	statusLabel.TextScaled = false
	statusLabel.TextColor3 = AEM_UIKit.AMBER_GLOW
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Center
	statusLabel.Text = "READY"
	statusLabel.ZIndex = baseZ + 5
	AEM_UIKit.applyTextContrast(statusLabel)
	statusLabel.Parent = root

	local keycapFrame = Instance.new("Frame")
	keycapFrame.Name = "KeycapFrame"
	keycapFrame.AnchorPoint = Vector2.new(0.5, 1)
	keycapFrame.Position = UDim2.fromScale(0.5, 1)
	keycapFrame.BackgroundColor3 = AEM_UIKit.VOID_GLASS
	keycapFrame.BackgroundTransparency = 0.82
	keycapFrame.BorderSizePixel = 0
	keycapFrame.ZIndex = baseZ + 4
	keycapFrame.Parent = root
	AEM_UIKit.applyBevelStroke(keycapFrame, AEM_UIKit.AMBER_WIRE, 1, 0.22, Enum.LineJoinMode.Miter)

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.BackgroundTransparency = 1
	keyLabel.BorderSizePixel = 0
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.FontFace = AEM_UIKit.FONT_FACE_BOLD
	keyLabel.TextSize = 11
	keyLabel.TextScaled = false
	keyLabel.TextColor3 = AEM_UIKit.IVORY_TEXT
	keyLabel.TextXAlignment = Enum.TextXAlignment.Center
	keyLabel.TextYAlignment = Enum.TextYAlignment.Center
	keyLabel.ZIndex = baseZ + 5
	AEM_UIKit.applyTextContrast(keyLabel)
	keyLabel.Parent = keycapFrame

	local currentReady = true

	local function applyVisualReadyState(stateText: string, progress: number?, ready: boolean?): ()
		local isReady = ready ~= false
		currentReady = isReady
		statusLabel.Text = stateText

		local hexCol = if isReady then AEM_UIKit.AMBER_WIRE else AEM_UIKit.AMBER_SOFT
		local hexAlpha = if isReady then 0.08 else 0.52
		for _, line in ipairs(outerHexLines) do
			line.BackgroundColor3 = hexCol
			line.BackgroundTransparency = hexAlpha
		end

		local glyphCol = if isReady then AEM_UIKit.IVORY_TEXT else AEM_UIKit.AMBER_SOFT
		local glyphAlpha = if isReady then 0.04 else 0.45
		for _, gLine in ipairs(glyphLines) do
			gLine.BackgroundColor3 = glyphCol
			gLine.BackgroundTransparency = glyphAlpha
		end

		if isReady then
			statusLabel.TextColor3 = if stateText == "ACTIVE" then AEM_UIKit.AMBER_WIRE else AEM_UIKit.AMBER_GLOW
			cdTrack.Visible = false
		else
			statusLabel.TextColor3 = AEM_UIKit.AMBER_SOFT
			cdTrack.Visible = true
			cdFill.Size = UDim2.fromScale(math.clamp(progress or 0, 0, 1), 1)
		end
	end

	local function setKeybind(keyStr: string): ()
		keyLabel.Text = keyStr
		local len = #keyStr
		local w = if len >= 3 then 38 elseif len == 2 then 30 else 24
		keycapFrame.Size = UDim2.fromOffset(w, 18)
	end

	local function setLabel(titleStr: string): ()
		titleLabel.Text = titleStr
	end

	local function setGlyph(glyphId: string): ()
		glyphHolder:ClearAllChildren()
		glyphLines = buildProceduralGlyph(glyphHolder, glyphId, sz, AEM_UIKit.IVORY_TEXT, baseZ + 3)
		local glyphCol = if currentReady then AEM_UIKit.IVORY_TEXT else AEM_UIKit.AMBER_SOFT
		local glyphAlpha = if currentReady then 0.04 else 0.45
		for _, gLine in ipairs(glyphLines) do
			gLine.BackgroundColor3 = glyphCol
			gLine.BackgroundTransparency = glyphAlpha
		end
	end

	setKeybind(props.keybind or "")
	applyVisualReadyState("READY", 1, true)

	if props.clickable == true or props.onActivated ~= nil then
		local hitBtn = Instance.new("TextButton")
		hitBtn.Name = "HitButton"
		hitBtn.Size = UDim2.fromScale(1, 1)
		hitBtn.BackgroundTransparency = 1
		hitBtn.Text = ""
		hitBtn.BorderSizePixel = 0
		hitBtn.ZIndex = baseZ + 8
		hitBtn.Parent = root
		if props.onActivated ~= nil then
			local callback = props.onActivated
			hitBtn.Activated:Connect(function()
				callback()
			end)
		end
	end

	return {
		root = root,
		setState = applyVisualReadyState,
		setKeybind = setKeybind,
		setLabel = setLabel,
		setGlyph = setGlyph,
	}
end

return table.freeze(AEM_UIKit)
