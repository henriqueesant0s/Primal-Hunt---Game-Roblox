--!strict
--[[
	PRIMAL HUNT | CinematicCutsceneDirector (LocalScript)
	Responsável por todas as cutscenes cinematográficas 3D sem alterar o HUD existente:
	1. Despertar do Monstro (Abertura na Gruta Abissal)
	2. Inserção Orbital de Dropship dos Caçadores (Nave 3D client-side + propulsores)
	3. Metamorfose no Ninho Abissal (Órbita no Casulo + Revelação do Estágio 2/3)
	4. Morte Súbita (Estágio 3) e Encerramento da Partida (PostMatch)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local gameRemotes = remotes:WaitForChild("GameRemotes")
local matchStateChanged = gameRemotes:WaitForChild("MatchStateChanged") :: RemoteEvent
local updateUI = gameRemotes:WaitForChild("UpdateUI") :: RemoteEvent

local HUNTER_ROLES: {[string]: boolean} = {
	Assault = true,
	Medic = true,
	Trapper = true,
	Support = true,
}

local SFX_ROAR = "rbxassetid://9113980319"
local SFX_SURGE = "rbxassetid://9126102843"
local SFX_FINISH = "rbxassetid://118218169117498"
local SFX_IMPACT = "rbxassetid://9114362401"
local SFX_DRONE = "rbxassetid://9125550012"

-- Dedicated widescreen letterbox GUI (DisplayOrder = 1, non-intrusive over HUD)
local oldGui = playerGui:FindFirstChild("PrimalHunt_CutsceneCinema")
if oldGui then oldGui:Destroy() end

local cinemaGui = Instance.new("ScreenGui")
cinemaGui.Name = "PrimalHunt_CutsceneCinema"
cinemaGui.IgnoreGuiInset = true
cinemaGui.DisplayOrder = 1
cinemaGui.ResetOnSpawn = false
cinemaGui.Enabled = true
cinemaGui.Parent = playerGui

local topBar = Instance.new("Frame")
topBar.Name = "TopLetterbox"
topBar.BackgroundColor3 = Color3.new(0, 0, 0)
topBar.BorderSizePixel = 0
topBar.Size = UDim2.fromScale(1, 0.115)
topBar.Position = UDim2.fromScale(0, -0.13)
topBar.Active = false
topBar.Parent = cinemaGui

local bottomBar = Instance.new("Frame")
bottomBar.Name = "BottomLetterbox"
bottomBar.BackgroundColor3 = Color3.new(0, 0, 0)
bottomBar.BorderSizePixel = 0
bottomBar.Size = UDim2.fromScale(1, 0.115)
bottomBar.Position = UDim2.fromScale(0, 1.02)
bottomBar.Active = false
bottomBar.Parent = cinemaGui

local captionLabel = Instance.new("TextLabel")
captionLabel.Name = "CinemaTitle"
captionLabel.Size = UDim2.fromScale(0.84, 0.65)
captionLabel.Position = UDim2.fromScale(0.08, 0.18)
captionLabel.BackgroundTransparency = 1
captionLabel.Font = Enum.Font.GothamBold
captionLabel.TextColor3 = Color3.fromRGB(245, 224, 182)
captionLabel.TextStrokeTransparency = 0.35
captionLabel.TextScaled = true
captionLabel.Text = ""
captionLabel.Parent = bottomBar

local subLabel = Instance.new("TextLabel")
subLabel.Name = "CinemaSkipHint"
subLabel.Size = UDim2.fromScale(0.45, 0.42)
subLabel.Position = UDim2.fromScale(0.275, 0.36)
subLabel.BackgroundTransparency = 1
subLabel.Font = Enum.Font.GothamMedium
subLabel.TextColor3 = Color3.fromRGB(168, 174, 182)
subLabel.TextScaled = true
subLabel.Text = "[Backspace] Pular Cena"
subLabel.Parent = topBar

local activeToken = 0
local activeRenderConn: RBXScriptConnection? = nil
local temporaryProps: {Instance} = {}
local introPlayedMatchId = ""
local currentMatchNonce = ""

local function playCinemaSound(soundId: string, volume: number, speed: number)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.Parent = SoundService
	s:Play()
	task.delay(6, function()
		if s.Parent then s:Destroy() end
	end)
end

local function setBarsVisible(visible: boolean, titleText: string?)
	if titleText then
		captionLabel.Text = titleText
	end
	local goalTop = if visible then UDim2.fromScale(0, 0) else UDim2.fromScale(0, -0.13)
	local goalBot = if visible then UDim2.fromScale(0, 0.885) else UDim2.fromScale(0, 1.02)
	TweenService:Create(topBar, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goalTop }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goalBot }):Play()
end

local function clearTemporaryProps()
	for _, inst in ipairs(temporaryProps) do
		if inst.Parent then inst:Destroy() end
	end
	table.clear(temporaryProps)
end

local function stopCutscene(restoreCamera: boolean)
	activeToken += 1
	if activeRenderConn then
		activeRenderConn:Disconnect()
		activeRenderConn = nil
	end
	clearTemporaryProps()
	setBarsVisible(false, nil)
	if restoreCamera then
		local cam = workspace.CurrentCamera
		if cam then
			cam.FieldOfView = 70
			local char = localPlayer.Character
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			if hum then
				cam.CameraSubject = hum
			end
			cam.CameraType = Enum.CameraType.Custom
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Backspace and activeRenderConn ~= nil then
		stopCutscene(true)
	end
end)

local function runCameraSpline(duration: number, fovStart: number, fovEnd: number, title: string, stepFn: (alpha: number) -> CFrame)
	stopCutscene(false)
	activeToken += 1
	local myToken = activeToken
	local cam = workspace.CurrentCamera
	if not cam then return end

	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = fovStart
	setBarsVisible(true, title)

	local started = os.clock()
	activeRenderConn = RunService.RenderStepped:Connect(function()
		if myToken ~= activeToken then return end
		local elapsed = os.clock() - started
		local u = math.clamp(elapsed / duration, 0, 1)
		local smoothU = u * u * (3 - 2 * u)
		local currentCam = workspace.CurrentCamera
		if currentCam then
			currentCam.CameraType = Enum.CameraType.Scriptable
			currentCam.FieldOfView = fovStart + (fovEnd - fovStart) * smoothU
			currentCam.CFrame = stepFn(smoothU)
		end
		if u >= 1 then
			stopCutscene(true)
		end
	end)
end

local function spawnClientDropship(anchorPos: Vector3): Model
	local ship = Instance.new("Model")
	ship.Name = "AEM_OrbitalDropship_Client"

	local function part(name: string, size: Vector3, rel: CFrame, col: Color3, mat: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.Material = mat
		p.Color = col
		p.Size = size
		p.CFrame = CFrame.new(anchorPos) * rel
		p.Parent = ship
		return p
	end

	part("Hull", Vector3.new(10, 4.5, 22), CFrame.new(0, 0, 0), Color3.fromRGB(36, 42, 50), Enum.Material.Metal)
	part("CockpitVisor", Vector3.new(6.2, 2.2, 4.8), CFrame.new(0, 0.2, -10.5) * CFrame.Angles(math.rad(-18), 0, 0), Color3.fromRGB(255, 162, 54), Enum.Material.Neon)
	part("WingL", Vector3.new(14, 1.0, 7.5), CFrame.new(-10.5, 0.4, 2) * CFrame.Angles(0, math.rad(12), math.rad(8)), Color3.fromRGB(28, 33, 40), Enum.Material.Metal)
	part("WingR", Vector3.new(14, 1.0, 7.5), CFrame.new(10.5, 0.4, 2) * CFrame.Angles(0, math.rad(-12), math.rad(-8)), Color3.fromRGB(28, 33, 40), Enum.Material.Metal)

	for _, sx in ipairs({-9.5, 9.5}) do
		local pod = part("Thruster_" .. tostring(sx), Vector3.new(3.2, 3.2, 7.2), CFrame.new(sx, -0.6, 3.5), Color3.fromRGB(24, 26, 30), Enum.Material.CorrodedMetal)
		local glow = part("ThrusterGlow_" .. tostring(sx), Vector3.new(2.2, 2.2, 0.8), CFrame.new(sx, -1.8, 3.5) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(255, 138, 42), Enum.Material.Neon)
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 186, 84), Color3.fromRGB(92, 92, 98))
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.4)})
		pe.Lifetime = NumberRange.new(0.4, 0.8)
		pe.Rate = 48
		pe.Speed = NumberRange.new(16, 28)
		pe.EmissionDirection = Enum.NormalId.Bottom
		pe.Parent = glow
		local spot = Instance.new("SpotLight")
		spot.Color = Color3.fromRGB(255, 224, 178)
		spot.Brightness = 3.5
		spot.Range = 95
		spot.Face = Enum.NormalId.Bottom
		spot.Parent = pod
	end

	-- 4 Drop Ropes descending from bay
	for _, rx in ipairs({-2.2, 2.2}) do
		part("DropCable_" .. tostring(rx), Vector3.new(0.22, 32, 0.22), CFrame.new(rx, -18, 0), Color3.fromRGB(22, 22, 24), Enum.Material.Metal)
	end

	ship.Parent = workspace
	table.insert(temporaryProps, ship)
	return ship
end

local function playMonsterAwakeningCutscene(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	playCinemaSound(SFX_ROAR, 0.88, 0.78)
	runCameraSpline(4.1, 56, 68, "DESPERTAR DO PREDADOR ABISSAL • ESTÁGIO 1", function(u: number): CFrame
		local liveRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local center = if liveRoot then liveRoot.Position else root.Position
		local fwd = if liveRoot then liveRoot.CFrame.LookVector else root.CFrame.LookVector
		local baseYaw = math.atan2(fwd.X, fwd.Z)
		local ang = baseYaw + math.rad(-58 + u * 118)
		local radius = 21 - u * 4.5
		local height = 1.5 + u * 8.2
		local camPos = center + Vector3.new(math.sin(ang) * radius, height, math.cos(ang) * radius)
		local lookAt = center + Vector3.new(0, 5.2 + u * 1.4, 0)
		return CFrame.lookAt(camPos, lookAt)
	end)
end

local function playDropshipInsertionCutscene(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local dropOrigin = root.Position
	local ship = spawnClientDropship(dropOrigin + Vector3.new(0, 34, 0))
	local startShipPos = dropOrigin + Vector3.new(0, 38, -28)
	local hoverShipPos = dropOrigin + Vector3.new(0, 29, 0)
	local exitShipPos = dropOrigin + Vector3.new(0, 58, 95)

	playCinemaSound(SFX_DRONE, 0.62, 0.92)
	runCameraSpline(4.1, 66, 70, "INSERÇÃO TÁTICA A.E.M. • ESTUÁRIO DA FENDA", function(u: number): CFrame
		local liveRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local p = if liveRoot then liveRoot.Position else dropOrigin
		local shipPos: Vector3
		if u < 0.65 then
			local k = u / 0.65
			shipPos = startShipPos:Lerp(hoverShipPos, k)
		else
			local k = (u - 0.65) / 0.35
			shipPos = hoverShipPos:Lerp(exitShipPos, k * k)
		end
		if ship.Parent then
			ship:PivotTo(CFrame.new(shipPos))
		end
		local ang = math.rad(140 - u * 125)
		local radius = 38 - u * 24
		local height = 28 - u * 23.5
		local camPos = p + Vector3.new(math.sin(ang) * radius, height, math.cos(ang) * radius)
		local target = p:Lerp(shipPos, math.max(0, 0.55 - u * 0.55)) + Vector3.new(0, 2.5, 0)
		return CFrame.lookAt(camPos, target)
	end)
end

local function tryPlayRoleIntro(stateName: string)
	if stateName ~= "MonsterHeadStart" and stateName ~= "ActiveHunt" then return end
	local char = localPlayer.Character
	if not char then return end
	local role = char:GetAttribute("Role")
	if typeof(role) ~= "string" or role == "Lobby" then return end
	if introPlayedMatchId == currentMatchNonce then return end

	if role == "Monster" then
		introPlayedMatchId = currentMatchNonce
		task.defer(function()
			playMonsterAwakeningCutscene(char)
		end)
	elseif HUNTER_ROLES[role] and stateName == "ActiveHunt" then
		introPlayedMatchId = currentMatchNonce
		task.defer(function()
			playDropshipInsertionCutscene(char)
		end)
	end
end

matchStateChanged.OnClientEvent:Connect(function(state: any, _seconds: any, data: any)
	if state == "Lobby" then
		currentMatchNonce = tostring(os.clock())
		introPlayedMatchId = ""
		stopCutscene(true)
	elseif state == "MonsterHeadStart" then
		if currentMatchNonce == "" then
			currentMatchNonce = tostring(os.clock())
		end
		tryPlayRoleIntro("MonsterHeadStart")
	elseif state == "ActiveHunt" then
		if currentMatchNonce == "" then
			currentMatchNonce = tostring(os.clock())
		end
		tryPlayRoleIntro("ActiveHunt")
	elseif state == "PostMatch" then
		local winner = if typeof(data) == "table" and typeof(data.winner) == "string" then data.winner else "Fim"
		local title = if winner == "Monster" then "DOMÍNIO DO ABISMO • MONSTRO VITORIOSO" else "AMEAÇA NEUTRALIZADA • CAÇADORES VITORIOSOS"
		local char = localPlayer.Character
		local center = if char then char:GetPivot().Position else Vector3.zero
		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			if c and not c:GetAttribute("IsDead") and c:GetAttribute("Role") == (if winner == "Monster" then "Monster" else c:GetAttribute("Role")) then
				if winner == "Monster" or HUNTER_ROLES[tostring(c:GetAttribute("Role"))] then
					center = c:GetPivot().Position
					break
				end
			end
		end
		playCinemaSound(SFX_IMPACT, 0.72, 0.75)
		runCameraSpline(3.4, 64, 54, title, function(u: number): CFrame
			local ang = math.rad(u * 95)
			local camPos = center + Vector3.new(math.cos(ang) * 28, 9 + u * 6, math.sin(ang) * 28)
			return CFrame.lookAt(camPos, center + Vector3.new(0, 4.5, 0))
		end)
	end
end)

updateUI.OnClientEvent:Connect(function(kind: any, data: any)
	if kind == "MonsterEvolutionStarted" and typeof(data) == "table" then
		local isLocalMonster = (data.monsterUserId == localPlayer.UserId)
		local targetStage = tonumber(data.targetStage) or 2
		playCinemaSound(SFX_SURGE, if isLocalMonster then 0.85 else 0.42, 0.88)
		if isLocalMonster then
			local mPos = if typeof(data.monsterPos) == "Vector3" then (data.monsterPos :: Vector3) else Vector3.zero
			runCameraSpline(4.85, 62, 74, string.format("METAMORFOSE NO NINHO • ASCENSÃO AO ESTÁGIO %d", targetStage), function(u: number): CFrame
				local char = localPlayer.Character
				local c = if char then char:GetPivot().Position else mPos
				local ang = math.rad(u * 285)
				local rad = 24 + math.sin(u * math.pi) * 6
				local h = 4.5 + u * 11.5
				return CFrame.lookAt(c + Vector3.new(math.cos(ang) * rad, h, math.sin(ang) * rad), c + Vector3.new(0, 5.5, 0))
			end)
		end
	elseif kind == "MonsterEvolutionCompleted" and typeof(data) == "table" then
		local newStage = tonumber(data.newStage) or 2
		playCinemaSound(SFX_FINISH, 0.92, 0.92)
		if data.monsterUserId == localPlayer.UserId then
			local char = localPlayer.Character
			local stageName = if newStage >= 3 then "ESTÁGIO 3 — DEUS DO ECLIPSE" else "ESTÁGIO 2 — TIRANO CARMESIM"
			runCameraSpline(2.1, 78, 66, stageName, function(u: number): CFrame
				local c = if char then char:GetPivot().Position else (if typeof(data.monsterPos) == "Vector3" then (data.monsterPos :: Vector3) else Vector3.zero)
				local camPos = c + Vector3.new(math.sin(u * 0.9) * 26, 7 + newStage * 2, 26 - u * 4)
				return CFrame.lookAt(camPos, c + Vector3.new(0, 6 + newStage * 2, 0))
			end)
		end
	elseif kind == "SuddenDeathTriggered" then
		playCinemaSound(SFX_ROAR, 0.85, 0.66)
		local char = localPlayer.Character
		if char and not char:GetAttribute("IsDead") and char:GetAttribute("Role") ~= "Lobby" then
			local relay = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("PowerRelay")
			local relayPos = if relay then relay:GetPivot().Position else Vector3.new(0, 12, 0)
			local cPos = char:GetPivot().Position
			runCameraSpline(2.6, 68, 56, "ESTÁGIO 3 DESPERTO • DEFENDA / DESTRUA O RELAY!", function(u: number): CFrame
				local eye = cPos + Vector3.new(0, 12, 16)
				return CFrame.lookAt(eye:Lerp(relayPos + Vector3.new(18, 14, 18), u * 0.45), relayPos)
			end)
		end
	end
end)

local function bindCharacter(char: Model)
	char:GetAttributeChangedSignal("Role"):Connect(function()
		local st = gameRemotes:GetAttribute("MatchState")
		if typeof(st) == "string" then
			tryPlayRoleIntro(st)
		end
	end)
	local st = gameRemotes:GetAttribute("MatchState")
	if typeof(st) == "string" then
		tryPlayRoleIntro(st)
	end
end
if localPlayer.Character then
	bindCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(bindCharacter)
