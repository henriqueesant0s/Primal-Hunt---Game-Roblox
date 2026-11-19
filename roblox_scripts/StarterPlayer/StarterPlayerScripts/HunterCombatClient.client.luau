--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local p = Players.LocalPlayer
local mouse = p:GetMouse()
local Config = require(RS:WaitForChild("HunterCombatConfig"))
local Audio = require(RS:WaitForChild("HunterAudio"))
local AEM_UIKit = require(RS:WaitForChild("AEM_UIKit"))
local remotes = RS:WaitForChild("Remotes")
local match = remotes:WaitForChild("GameRemotes")
local hunters = remotes:WaitForChild("HunterRemotes")
local fire = hunters:WaitForChild("FireWeapon") :: RemoteEvent
local revive = hunters:WaitForChild("ReviveTeammate") :: RemoteEvent

local gui = Instance.new("ScreenGui")
gui.Name = "HunterInteraction"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 4
gui.Parent = p:WaitForChild("PlayerGui")
local interactionCanvas, _ = AEM_UIKit.createScaledCanvas(gui, "HunterInteractionCanvas", 4)
local prompt = Instance.new("TextButton")
prompt.Name = "RevivePrompt"
prompt.AnchorPoint = Vector2.new(0.5, 1)
prompt.Position = UDim2.new(0.5, 0, 1, -90)
prompt.Size = UDim2.fromOffset(336, 38)
prompt.BackgroundTransparency = 1
prompt.BorderSizePixel = 0
prompt.AutoButtonColor = false
prompt.Text = ""
prompt.Visible = false
prompt.ZIndex = 10
prompt.Parent = interactionCanvas
local wireFrame = AEM_UIKit.createWireBracketFrame(prompt, {
	name = "WireFrame",
	parent = prompt,
	size = UDim2.fromScale(1, 1),
	position = UDim2.fromScale(0, 0),
	bgColor = AEM_UIKit.VOID_GLASS,
	bgTransparency = 0.84,
	bracketColor = AEM_UIKit.AMBER_WIRE,
	bracketThickness = 1.25,
	bracketLength = 10,
	mode = "LeftRight",
	glow = true,
	zIndex = 10,
})
local promptText = AEM_UIKit.makeMonoLabel({
	name = "PromptLabel",
	parent = prompt,
	size = UDim2.new(1, -24, 1, -6),
	position = UDim2.fromOffset(12, 1),
	text = "",
	color = AEM_UIKit.IVORY_TEXT,
	font = AEM_UIKit.FONT_TECH,
	weight = Enum.FontWeight.Bold,
	alignX = Enum.TextXAlignment.Center,
	alignY = Enum.TextYAlignment.Center,
	textSize = 15,
	truncate = true,
	zIndex = 12,
})
local progressTrack = Instance.new("Frame")
progressTrack.Name = "ProgressTrack"
progressTrack.AnchorPoint = Vector2.new(0.5, 1)
progressTrack.Position = UDim2.new(0.5, 0, 1, -2)
progressTrack.Size = UDim2.new(1, -16, 0, 3)
progressTrack.BackgroundColor3 = AEM_UIKit.TRACK_GLASS
progressTrack.BackgroundTransparency = 0.68
progressTrack.BorderSizePixel = 0
progressTrack.Visible = false
progressTrack.ZIndex = 12
progressTrack.Parent = prompt
local progressFill = Instance.new("Frame")
progressFill.Name = "ProgressFill"
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
progressFill.BackgroundTransparency = 0.04
progressFill.BorderSizePixel = 0
progressFill.ZIndex = 13
progressFill.Parent = progressTrack
local lastBracketColor: Color3? = nil
local function setBracketColor(col: Color3)
	if lastBracketColor == col then return end
	lastBracketColor = col
	for _, child in wireFrame:GetChildren() do
		if child:IsA("Frame") and not string.find(child.Name, "_Glow", 1, true) then
			child.BackgroundColor3 = col
		end
	end
end

local equipped: Tool? = nil
local firing = false
local nextShot = 0
local candidate: Model? = nil
local holding: Model? = nil
local holdingKey = false
local deadline: number? = nil
local weaponConns: {RBXScriptConnection} = {}
local bodyConns: {RBXScriptConnection} = {}

local function disconnect(conns: {RBXScriptConnection})
	for _, conn in conns do conn:Disconnect() end
	table.clear(conns)
end

local function stopHold()
	local target = holding
	holding, deadline = nil, nil
	if target then revive:FireServer(target, false) end
end

local function beginHold()
	local target = candidate
	if holding or not target or match:GetAttribute("SuddenDeath") == true or Input:GetFocusedTextBox() then return end
	firing = false
	holding = target
	deadline = nil
	revive:FireServer(target, true)
end

local function clearWeapon()
	disconnect(weaponConns)
	equipped = nil
	firing = false
end

local function shoot(c: Model, spec: Config.WeaponSpec)
	local head = c:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end
	local aim = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {c}
	local hit = workspace:Raycast(aim.Origin, aim.Direction * spec.Range, params)
	local point = if hit then hit.Position else aim.Origin + aim.Direction * spec.Range
	local direction = point - head.Position
	if direction.Magnitude > 0.01 then fire:FireServer(head.Position, direction.Unit, spec.Id) end
end

local function tryShot()
	local c = p.Character
	local now = os.clock()
	if not c or not equipped or equipped.Parent ~= c or holding or now < nextShot then return end
	local id = equipped:GetAttribute("WeaponId")
	local spec = if typeof(id) == "string" then Config.Weapons[id] else nil
	if not spec then return end
	nextShot = now + spec.Interval
	shoot(c, spec)
end

local function bindTool(child: Instance)
	if not child:IsA("Tool") then return end
	local id = child:GetAttribute("WeaponId")
	if typeof(id) ~= "string" or Config.Weapons[id] == nil then return end
	clearWeapon()
	equipped = child
	table.insert(weaponConns, child.Activated:Connect(function()
		if not holding and not Input:GetFocusedTextBox() then
			firing = true
			tryShot()
		end
	end))
	table.insert(weaponConns, child.Deactivated:Connect(function() firing = false end))
end

local function clearBody()
	holdingKey = false
	stopHold()
	candidate = nil
	prompt.Visible = false
	disconnect(bodyConns)
	clearWeapon()
end

local function bindBody(c: Model)
	clearBody()
	table.insert(bodyConns, c.ChildAdded:Connect(bindTool))
	table.insert(bodyConns, c.ChildRemoved:Connect(function(child)
		if child == equipped then clearWeapon() end
	end))
	for _, child in c:GetChildren() do bindTool(child) end
end
p.CharacterAdded:Connect(bindBody)
p.CharacterRemoving:Connect(clearBody)
if p.Character then bindBody(p.Character) end

local function closestAlly(root: BasePart): Model?
	local nearest: Model? = nil
	local distance = Config.ReviveRange
	for _, ally in Players:GetPlayers() do
		local c = ally.Character
		if ally == p or not c or not c:GetAttribute("IsDowned") or c:GetAttribute("IsDead") then continue end
		local role = c:GetAttribute("Role")
		local part = c:FindFirstChild("HumanoidRootPart")
		if typeof(role) == "string" and Config.Hunters[role] and part and part:IsA("BasePart") then
			local gap = (part.Position - root.Position).Magnitude
			if gap <= distance then nearest, distance = c, gap end
		end
	end
	return nearest
end

Input.InputBegan:Connect(function(key, processed)
	if not processed and key.KeyCode == Enum.KeyCode.E then
		holdingKey = true
		beginHold()
	end
end)
local touch: InputObject? = nil
prompt.InputBegan:Connect(function(key)
	if key.UserInputType == Enum.UserInputType.Touch and not touch then touch = key beginHold() end
end)
Input.InputEnded:Connect(function(key)
	if key.KeyCode == Enum.KeyCode.E or key == touch then
		if key.KeyCode == Enum.KeyCode.E then holdingKey = false end
		touch = nil
		stopHold()
	elseif key.UserInputType == Enum.UserInputType.MouseButton1 then firing = false end
end)
local function releaseInput()
	holdingKey = false
	touch = nil
	firing = false
	stopHold()
end
Input.WindowFocusReleased:Connect(releaseInput)
Input.TextBoxFocused:Connect(releaseInput)
revive.OnClientEvent:Connect(function(target, state, endsAt)
	if holding ~= target then return end
	if state == "Started" then deadline = endsAt else holding, deadline = nil, nil end
end)

fire.OnClientEvent:Connect(function(start: Vector3, finish: Vector3, weaponId: string?, hitMonster: boolean?)
	local dist = (finish - start).Magnitude
	if dist < 0.05 then return end
	if typeof(weaponId) == "string" then Audio.PlayWorldOneShot(weaponId, start, 0.04) end
	if hitMonster == true then Audio.PlayWorldOneShot("WeaponHit", finish, 0.05) end
	local spec = if typeof(weaponId) == "string" then Config.Weapons[weaponId] else nil
	local thickness = if spec then spec.TraceThickness else 0.095
	local trail = Instance.new("Part")
	trail.Name = "PlasmaTrace"
	trail.Anchored = true
	trail.CanCollide, trail.CanQuery, trail.CanTouch, trail.CastShadow = false, false, false, false
	trail.Material = Enum.Material.Neon
	trail.Color = if spec then spec.TraceColor else Color3.fromRGB(88, 246, 213)
	trail.Size = Vector3.new(thickness, thickness, dist)
	trail.CFrame = CFrame.lookAt(start:Lerp(finish, 0.5), finish)
	trail.Parent = workspace
	Debris:AddItem(trail, 0.075)
end)

local nextScan = 0
RunService.Heartbeat:Connect(function()
	local c = p.Character
	local role = if c then c:GetAttribute("Role") else nil
	if not c or typeof(role) ~= "string" or not Config.Hunters[role] or c:GetAttribute("IsDead") or c:GetAttribute("IsDowned")
		or match:GetAttribute("MatchState") ~= "ActiveHunt" or match:GetAttribute("RoundClosed") then
		if holding then stopHold() end
		candidate, firing, prompt.Visible = nil, false, false
		return
	end
	local now = os.clock()
	if firing then tryShot() end
	if now < nextScan then return end
	nextScan = now + 0.10
	local root = c:FindFirstChild("HumanoidRootPart")
	candidate = if root and root:IsA("BasePart") then closestAlly(root) else nil
	if holdingKey and not holding and candidate then beginHold() end
	local target = holding
	if target and root and root:IsA("BasePart") then
		local other = target:FindFirstChild("HumanoidRootPart")
		if not other or not other:IsA("BasePart") or (root.Position - other.Position).Magnitude > Config.ReviveRange
			or not target:GetAttribute("IsDowned") or target:GetAttribute("IsDead") then stopHold() end
	end
	target = holding or candidate
	prompt.Visible = target ~= nil
	if not target then
		progressTrack.Visible = false
		progressFill.Size = UDim2.fromScale(0, 1)
		return
	end
	local ally = Players:GetPlayerFromCharacter(target)
	local name = string.upper(if ally then ally.DisplayName else target.Name)
	if match:GetAttribute("SuddenDeath") == true then
		setBracketColor(AEM_UIKit.BOSS_CRIMSON)
		promptText.TextColor3 = AEM_UIKit.BOSS_CRIMSON
		promptText.Text = "RELAY SHATTERED // REVIVE OFFLINE"
		progressTrack.Visible = false
		progressFill.Size = UDim2.fromScale(0, 1)
	elseif holding then
		setBracketColor(AEM_UIKit.AMBER_GLOW)
		promptText.TextColor3 = AEM_UIKit.AMBER_GLOW
		local endsAt = deadline
		local total = math.max(0.1, Config.ReviveSeconds)
		local remaining = if endsAt then math.clamp(endsAt - workspace:GetServerTimeNow(), 0, total) else total
		local ratio = math.clamp(1 - (remaining / total), 0, 1)
		promptText.Text = string.format("REVIVING %s // %.1fs", name, remaining)
		progressTrack.Visible = true
		progressFill.BackgroundColor3 = AEM_UIKit.AMBER_GLOW
		progressFill.Size = UDim2.fromScale(ratio, 1)
	else
		setBracketColor(AEM_UIKit.AMBER_WIRE)
		promptText.TextColor3 = AEM_UIKit.IVORY_TEXT
		promptText.Text = (if Input.TouchEnabled and not Input.KeyboardEnabled then "HOLD TO REVIVE // " else "[E] REVIVE // ") .. name
		progressTrack.Visible = false
		progressFill.Size = UDim2.fromScale(0, 1)
	end
end)

