--!strict
--[[
	PROJECT ABYSS | EstuaryWildlifeTraps.server.lua
	Sound Traps (Brine Gulls & Scavenging Seabird Flocks) + Oily Creek Stealth Check
	- Monitors roosting seabird clusters across The Black-Sand Estuary (25-stud trigger radius).
	- Sprinting through a roost (unless crouched/stealth or muffled on an EstuaryOilPatch) scatters
	  the flock loudly into the twilight sky with cross-map visual silhouettes and acoustic alerts.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local gameEvents = remotes:WaitForChild("GameRemotes")
local updateUI = gameEvents:WaitForChild("UpdateUI") :: RemoteEvent

local HUNTERS: {[string]: boolean} = { Assault = true, Medic = true, Trapper = true, Support = true }
local TRIGGER_RADIUS = 25
local SPRINT_THRESHOLD = 14.2
local ROOST_COOLDOWN = 35
local SHRIEK_SFX = "rbxassetid://9114787480"
local WINGS_SFX = "rbxassetid://9120769888"

type BirdVisual = { body: Part, wingL: Part, wingR: Part, localOffset: Vector3 }
type FlockState = {
	anchor: BasePart,
	birds: {BirdVisual},
	readyAt: number,
	scattered: boolean,
}

local flocks: {[BasePart]: FlockState} = {}
local rng = Random.new()

local function inCombat(): boolean
	local state = gameEvents:GetAttribute("MatchState")
	return gameEvents:GetAttribute("RoundClosed") ~= true and (state == "MonsterHeadStart" or state == "ActiveHunt")
end

local function isOnOilPatch(position: Vector3): boolean
	for _, oil in ipairs(CollectionService:GetTagged("EstuaryOilPatch")) do
		if oil:IsA("BasePart") then
			local rel = oil.CFrame:PointToObjectSpace(position)
			local half = oil.Size * 0.5
			if math.abs(rel.X) <= half.X + 2.5 and math.abs(rel.Z) <= half.Z + 2.5 and math.abs(rel.Y) <= 9 then
				return true
			end
		end
	end
	return false
end

local function spawnPerchedBirds(anchor: BasePart): {BirdVisual}
	local existing = anchor:FindFirstChild("PerchedFlock")
	if existing then existing:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "PerchedFlock"
	folder.Parent = anchor

	local list: {BirdVisual} = {}
	local darkPlumage = Color3.fromRGB(22, 24, 26)
	local paleWingTip = Color3.fromRGB(196, 188, 166)

	for i = 1, 9 do
		local ang = (math.pi * 2 * i / 9) + rng:NextNumber(-0.25, 0.25)
		local rad = rng:NextNumber(2.0, 8.5)
		local offset = Vector3.new(math.cos(ang) * rad, rng:NextNumber(0.3, 1.4), math.sin(ang) * rad)
		local yaw = rng:NextNumber(0, math.pi * 2)
		local baseCF = CFrame.new(anchor.Position + offset) * CFrame.Angles(0, yaw, 0)

		local body = Instance.new("Part")
		body.Name = "BrineGull_" .. tostring(i)
		body.Size = Vector3.new(0.55, 0.45, 1.25)
		body.Color = darkPlumage
		body.Material = Enum.Material.Slate
		body.Anchored = true
		body.CanCollide, body.CanQuery, body.CanTouch = false, false, false
		body.CastShadow = false
		body.CFrame = baseCF
		body.Parent = folder

		local wingL = Instance.new("Part")
		wingL.Name = "WingL"
		wingL.Size = Vector3.new(1.35, 0.12, 0.55)
		wingL.Color = paleWingTip
		wingL.Material = Enum.Material.SmoothPlastic
		wingL.Anchored = true
		wingL.CanCollide, wingL.CanQuery, wingL.CanTouch = false, false, false
		wingL.CastShadow = false
		wingL.CFrame = baseCF * CFrame.new(-0.7, 0.1, 0) * CFrame.Angles(0, 0, math.rad(14))
		wingL.Parent = body

		local wingR = Instance.new("Part")
		wingR.Name = "WingR"
		wingR.Size = Vector3.new(1.35, 0.12, 0.55)
		wingR.Color = paleWingTip
		wingR.Material = Enum.Material.SmoothPlastic
		wingR.Anchored = true
		wingR.CanCollide, wingR.CanQuery, wingR.CanTouch = false, false, false
		wingR.CastShadow = false
		wingR.CFrame = baseCF * CFrame.new(0.7, 0.1, 0) * CFrame.Angles(0, 0, math.rad(-14))
		wingR.Parent = body

		table.insert(list, { body = body, wingL = wingL, wingR = wingR, localOffset = offset })
	end
	return list
end

local function scatterFlock(state: FlockState, triggerCharacter: Model)
	state.scattered = true
	local now = os.clock()
	state.readyAt = now + ROOST_COOLDOWN
	local origin = state.anchor.Position

	-- Spatial shriek + wing-flap burst audible across the estuary
	for _, spec in ipairs({
		{ id = SHRIEK_SFX, vol = 0.92, spd = 1.04 },
		{ id = WINGS_SFX, vol = 0.88, spd = 0.98 },
	}) do
		local snd = Instance.new("Sound")
		snd.SoundId = spec.id
		snd.Volume = spec.vol
		snd.PlaybackSpeed = spec.spd
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 22
		snd.RollOffMaxDistance = 720
		snd.Parent = state.anchor
		snd:Play()
		Debris:AddItem(snd, 7)
	end

	-- Rising atmospheric beacon column / silhouette ring so players spot the flock across 850 studs
	local flare = Instance.new("Part")
	flare.Name = "GullScatterBeacon"
	flare.Shape = Enum.PartType.Cylinder
	flare.Anchored = true
	flare.CanCollide, flare.CanQuery, flare.CanTouch = false, false, false
	flare.CastShadow = false
	flare.Material = Enum.Material.Neon
	flare.Color = Color3.fromRGB(245, 210, 150)
	flare.Transparency = 0.72
	flare.Size = Vector3.new(95, 3.2, 3.2)
	flare.CFrame = CFrame.new(origin + Vector3.new(0, 47.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	flare.Parent = Workspace
	TweenService:Create(flare, TweenInfo.new(3.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(125, 0.8, 0.8),
	}):Play()
	Debris:AddItem(flare, 4.0)

	-- Animate individual gulls spiraling skyward
	for idx, b in ipairs(state.birds) do
		if b.body.Parent then
			local outAng = (math.pi * 2 * idx / #state.birds) + rng:NextNumber(-0.2, 0.2)
			local climbTarget = origin + Vector3.new(math.cos(outAng) * 42, 82 + (idx % 4) * 9, math.sin(outAng) * 42)
			local lookCF = CFrame.lookAt(climbTarget, climbTarget + Vector3.new(math.cos(outAng), 0.6, math.sin(outAng)))
			TweenService:Create(b.body, TweenInfo.new(3.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				CFrame = lookCF,
				Transparency = 1,
			}):Play()
			TweenService:Create(b.wingL, TweenInfo.new(3.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				CFrame = lookCF * CFrame.new(-1.1, 0.35, 0) * CFrame.Angles(0, 0, math.rad(32)),
				Transparency = 1,
			}):Play()
			TweenService:Create(b.wingR, TweenInfo.new(3.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				CFrame = lookCF * CFrame.new(1.1, 0.35, 0) * CFrame.Angles(0, 0, math.rad(-32)),
				Transparency = 1,
			}):Play()
		end
	end

	local role = triggerCharacter:GetAttribute("Role")
	updateUI:FireAllClients("BrineGullAlert", {
		position = origin,
		triggeredByMonster = (role == "Monster"),
	})
	if role == "Monster" then
		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			if c and HUNTERS[c:GetAttribute("Role")] then
				updateUI:FireClient(p, "PlanetScannerPulse", {
					targetPosition = origin,
					endsAt = Workspace:GetServerTimeNow() + 2.4,
					duration = 2.4,
				})
			end
		end
	end
end

local function rebuildFlockRegistry()
	table.clear(flocks)
	local roostContainers: {Instance} = {}
	local eco = Workspace:FindFirstChild("HuntingMap_Ecosystem")
	if eco then
		local tg = eco:FindFirstChild("TerrainAndGeometry")
		local br = if tg then tg:FindFirstChild("BrineGullFlocks") else nil
		if br then table.insert(roostContainers, br) end
	end
	local mapFolder = Workspace:FindFirstChild("Map")
	local geom = if mapFolder then mapFolder:FindFirstChild("Geometry") else nil
	local legacyRoosts = if geom then geom:FindFirstChild("BrineGullFlocks") else nil
	if legacyRoosts then table.insert(roostContainers, legacyRoosts) end

	for _, roostFolder in ipairs(roostContainers) do
		for _, child in ipairs(roostFolder:GetChildren()) do
			if child:IsA("BasePart") then
				flocks[child] = {
					anchor = child,
					birds = spawnPerchedBirds(child),
					readyAt = 0,
					scattered = false,
				}
			end
		end
	end
end

local lastFloraClueAt: {[Model]: number} = setmetatable({}, { __mode = "k" }) :: any

local function maybeLeaveDisturbedFloraClue(c: Model, pos: Vector3)
	if c:GetAttribute("Role") ~= "Monster" then return end
	local now = os.clock()
	if now - (lastFloraClueAt[c] or 0) < 3.2 then return end
	for _, bush in ipairs(CollectionService:GetTagged("ConcealmentFlora")) do
		if bush:IsA("BasePart") and (bush.Position - pos).Magnitude <= 14 then
			lastFloraClueAt[c] = now
			-- Subtle temporary disturbed-flora swaying & spore dust clue so attentive Hunters can investigate!
			local baseCF = bush.CFrame
			TweenService:Create(bush, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				CFrame = baseCF * CFrame.Angles(math.rad(14), 0, math.rad(-10)),
			}):Play()
			task.delay(0.25, function()
				if bush.Parent then
					TweenService:Create(bush, TweenInfo.new(1.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
						CFrame = baseCF,
					}):Play()
				end
			end)
			local clueAnchor = Instance.new("Part")
			clueAnchor.Name = "DisturbedFloraSporeClue"
			clueAnchor.Size = Vector3.new(4, 2, 4)
			clueAnchor.Position = pos + Vector3.new(0, 1.5, 0)
			clueAnchor.Anchored = true
			clueAnchor.Transparency = 1
			clueAnchor.CanCollide, clueAnchor.CanQuery, clueAnchor.CanTouch = false, false, false
			clueAnchor.CastShadow = false
			clueAnchor.Parent = Workspace
			local pe = Instance.new("ParticleEmitter")
			pe.Rate = 7
			pe.Lifetime = NumberRange.new(2.0, 3.5)
			pe.Speed = NumberRange.new(0.8, 2.2)
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
			pe.Color = ColorSequence.new(Color3.fromRGB(196, 174, 112))
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
			pe.LightEmission = 0.25
			pe.Parent = clueAnchor
			task.delay(5.5, function() pe.Enabled = false end)
			Debris:AddItem(clueAnchor, 9.0)
			break
		end
	end
end

Workspace:GetAttributeChangedSignal("WorldReady"):Connect(function()
	if Workspace:GetAttribute("WorldReady") == true then
		rebuildFlockRegistry()
	end
end)
if Workspace:GetAttribute("WorldReady") == true then
	rebuildFlockRegistry()
end

task.spawn(function()
	while true do
		task.wait(0.2)
		local now = os.clock()
		for anchor, state in pairs(flocks) do
			if anchor.Parent == nil then
				flocks[anchor] = nil
				continue
			end
			if state.scattered and now >= state.readyAt then
				state.scattered = false
				state.birds = spawnPerchedBirds(anchor)
			end
		end

		if not inCombat() then continue end

		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			if not c or c:GetAttribute("IsDead") or c:GetAttribute("IsDowned") or c:GetAttribute("IsStealth") == true then
				continue
			end
			local role = c:GetAttribute("Role")
			if role ~= "Monster" and not HUNTERS[role] then continue end
			local root = c:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then continue end

			local vel = root.AssemblyLinearVelocity
			local flatSpeed = Vector2.new(vel.X, vel.Z).Magnitude
			if flatSpeed >= 10.5 and c:GetAttribute("IsStealth") ~= true then
				maybeLeaveDisturbedFloraClue(c, root.Position)
			end
			if flatSpeed < SPRINT_THRESHOLD then continue end
			if isOnOilPatch(root.Position) then continue end

			for _, state in pairs(flocks) do
				if not state.scattered then
					local d = (root.Position - state.anchor.Position).Magnitude
					if d <= TRIGGER_RADIUS then
						scatterFlock(state, c)
					end
				end
			end
		end
	end
end)

