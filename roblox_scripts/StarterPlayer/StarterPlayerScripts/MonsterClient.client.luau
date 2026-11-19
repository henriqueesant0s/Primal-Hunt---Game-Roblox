--!strict
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Input=game:GetService("UserInputService")
local Tween=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local player=Players.LocalPlayer
local mouse=player:GetMouse()
local remotes=RS:WaitForChild("Remotes"):WaitForChild("MonsterRemotes")
local skills=remotes:WaitForChild("UseMonsterSkill") :: RemoteEvent
local eat=remotes:WaitForChild("EatPrey") :: RemoteEvent
local evolve=remotes:WaitForChild("EvolveStage") :: RemoteEvent
local smellRemote=remotes:WaitForChild("SmellPulse") :: RemoteEvent
local fauna=workspace:WaitForChild("ActivePrey")
local tracks=workspace:WaitForChild("Footprints")
local hunters: {[string]: boolean}={Assault=true,Medic=true,Trapper=true,Support=true}
local keys: {[Enum.KeyCode]: string}={[Enum.KeyCode.One]="LeapSmash",[Enum.KeyCode.Two]="FeralCharge",[Enum.KeyCode.Three]="AcidBreath"}
local heldEat,heldEvolve,heldStealth=false,false,false
local lastPulse=-math.huge
local channelStart=0
local channelName=""
local marking: {Instance}={}
local gui=Instance.new("ScreenGui")
gui.Name="MonsterControls"
gui.ResetOnSpawn=false
gui.DisplayOrder=2
gui.Enabled=false
gui.Parent=player:WaitForChild("PlayerGui")
local hint=Instance.new("TextLabel")
hint.AnchorPoint=Vector2.new(.5,1)
hint.Position=UDim2.fromScale(.5,.95)
hint.Size=UDim2.new(.8,0,0,46)
hint.BackgroundColor3=Color3.fromRGB(19,26,29)
hint.BackgroundTransparency=.23
hint.TextColor3=Color3.fromRGB(237,230,203)
hint.TextSize=14
hint.TextWrapped=true
hint.Font=Enum.Font.GothamMedium
hint.Visible=false
hint.Parent=gui
local function monster(): Model?
	local c=player.Character
	return if c and c:GetAttribute("Role")=="Monster" and not c:GetAttribute("IsDead") then c else nil
end
local function clearPulse()
	for _,v in marking do v:Destroy() end
	table.clear(marking)
end
local function addSonarTag(targetModel: Model, text: string, color: Color3)
	local adornee = targetModel.PrimaryPart or targetModel:FindFirstChildWhichIsA("BasePart")
	if not adornee then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "SonarPreyTag"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(185, 34)
	bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.Adornee = adornee
	bb.Parent = targetModel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
	lbl.BackgroundTransparency = 0.25
	lbl.TextColor3 = color
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextStrokeTransparency = 0.35
	lbl.Text = text
	lbl.Parent = bb
	table.insert(marking, bb)
end
local function highlight(object: Model, color: Color3)
	local h = Instance.new("Highlight")
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.FillColor = color
	h.OutlineColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.22
	h.OutlineTransparency = 0
	h.Adornee = object
	h.Parent = object
	table.insert(marking, h)
end
local function createScentBeam(fromRoot: BasePart, toPart: BasePart, color: Color3)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 3.5, 0)
	a0.Parent = fromRoot
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 2.0, 0)
	a1.Parent = toPart
	local beam = Instance.new("Beam")
	beam.Name = "SonarScentTrail"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	beam.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 0.1)})
	beam.Width0 = 1.6
	beam.Width1 = 0.8
	beam.CurveSize0 = 12
	beam.CurveSize1 = -8
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Parent = a0
	table.insert(marking, a0)
	table.insert(marking, a1)
end
local function smell(c: Model)
	local now = os.clock()
	if now - lastPulse < 4.5 then return end
	lastPulse = now
	clearPulse()

	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = if root then root.Position else c:GetPivot().Position

	local sfx = Instance.new("Sound")
	sfx.SoundId = "rbxassetid://9126102843"
	sfx.Volume = 0.65
	sfx.PlaybackSpeed = 1.15
	sfx.Parent = game:GetService("SoundService")
	sfx:Play()
	Debris:AddItem(sfx, 3)

	-- Collect & sort ALL Fauna by distance so nearest 18 get Highlights (safely under 31 Highlight cap!)
	local preyList: { { model: Model, part: BasePart, dist: number } } = {}
	for _, animal in fauna:GetChildren() do
		if animal:IsA("Model") then
			local pPart = animal.PrimaryPart or animal:FindFirstChildWhichIsA("BasePart")
			if pPart then
				table.insert(preyList, { model = animal, part = pPart, dist = (pPart.Position - origin).Magnitude })
			end
		end
	end
	table.sort(preyList, function(a, b) return a.dist < b.dist end)

	for idx, entry in ipairs(preyList) do
		local animal = entry.model
		local isDead = animal:GetAttribute("IsDead") == true
		local tier = tonumber(animal:GetAttribute("PreyTier")) or 1
		local meat = tonumber(animal:GetAttribute("MeatValue")) or 25
		local sp = tostring(animal:GetAttribute("Species") or animal.Name)
		local col = if isDead
			then Color3.fromRGB(255, 232, 92)
			elseif tier == 2 then Color3.fromRGB(255, 86, 42)
			elseif sp == "SporeCrawler" then Color3.fromRGB(122, 255, 96)
			elseif sp == "AcidSpitterDrake" then Color3.fromRGB(168, 255, 58)
			else Color3.fromRGB(72, 240, 224)

		if idx <= 18 then
			highlight(animal, col)
		end
		if idx <= 10 then
			local prefix = if isDead then "[DEVORAR E]" elseif tier == 2 then "[ALFA]" else "[PRESA]"
			addSonarTag(animal, string.format("%s %s • %dm (+%d)", prefix, sp, math.round(entry.dist), meat), col)
		end
		if idx <= 3 and root then
			createScentBeam(root, entry.part, col)
		end
	end

	for _, p in Players:GetPlayers() do
		local body = p.Character
		if body and hunters[body:GetAttribute("Role")] and not body:GetAttribute("IsDead") then
			local hr = body:FindFirstChild("HumanoidRootPart") :: BasePart?
			local d = if hr then math.round((hr.Position - origin).Magnitude) else 0
			highlight(body, Color3.fromRGB(255, 62, 62))
			addSonarTag(body, string.format("[CAÇADOR] %s • %dm", tostring(body:GetAttribute("Role")), d), Color3.fromRGB(255, 82, 82))
		end
	end

	-- Ground-hugging non-obstructive expanding sonar shock ring (260 studs)
	local ring = Instance.new("Part")
	ring.Name = "PulsoOlfativo"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 208, 72)
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide, ring.CanQuery, ring.CanTouch = false, false, false
	ring.Size = Vector3.new(0.4, 8, 8)
	ring.CFrame = CFrame.new(origin - Vector3.yAxis * 2.5) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	Tween:Create(ring, TweenInfo.new(1.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, 260, 260),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 1.25)
	task.delay(6.5, function() if lastPulse == now then clearPulse() end end)
end
smellRemote.OnClientEvent:Connect(function()
	local c = monster()
	if c then smell(c) end
end)
local function closest(origin: Vector3): Model?
	local best: Model?=nil
	local distance=26
	for _,v in fauna:GetChildren() do
		if v:IsA("Model") and v.PrimaryPart and v:GetAttribute("IsDead") then
			local maxRange = if v:GetAttribute("PreyTier") == 2 then 24 else 18
			local d=(v.PrimaryPart.Position-origin).Magnitude
			if d<=maxRange and d<=distance then best,distance=v,d end
		end
	end
	return best
end
Input.InputBegan:Connect(function(input,processed)
	if Input:GetFocusedTextBox() ~= nil then return end
	if processed and input.KeyCode ~= Enum.KeyCode.Q then return end
	local c=monster()
	if not c then return end
	local key=input.KeyCode
	local skill=keys[key]
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local origin = c:GetPivot().Position
		local aim = mouse.Hit.Position - origin
		skills:FireServer("ClawSlash", origin + (if aim.Magnitude > 80 then aim.Unit * 80 else aim))
	elseif skill then
		local origin=c:GetPivot().Position
		local aim=mouse.Hit.Position-origin
		skills:FireServer(skill,origin+(if aim.Magnitude>80 then aim.Unit*80 else aim))
	elseif key==Enum.KeyCode.E and not heldEat then
		local prey=closest(c:GetPivot().Position)
		if prey then heldEat=true eat:FireServer(prey) end
	elseif key==Enum.KeyCode.V and not heldEvolve then
		heldEvolve=true
		evolve:FireServer(true)
	elseif key==Enum.KeyCode.LeftControl and not heldStealth then
		heldStealth=true
		skills:FireServer("StealthOn",Vector3.zero)
	elseif key==Enum.KeyCode.Q then
		smell(c)
	elseif key==Enum.KeyCode.Space then
		local h=c:FindFirstChildOfClass("Humanoid")
		if h and h.FloorMaterial==Enum.Material.Air then skills:FireServer("Climb",Vector3.zero) end
	end
end)
local function release(key: Enum.KeyCode?)
	if heldEat and (not key or key==Enum.KeyCode.E) then heldEat=false skills:FireServer("CancelEat",Vector3.zero) end
	if heldEvolve and (not key or key==Enum.KeyCode.V) then heldEvolve=false evolve:FireServer(false) end
	if heldStealth and (not key or key==Enum.KeyCode.LeftControl) then heldStealth=false skills:FireServer("StealthOff",Vector3.zero) end
end
Input.InputEnded:Connect(function(input) release(input.KeyCode) end)
Input.WindowFocusReleased:Connect(function() release(nil) end)
player.CharacterRemoving:Connect(function() release(nil) clearPulse() end)

local previous: Vector3?=nil
local lastTrack: Vector3?=nil
local follow: Model?=nil
local foot=1
local myTracks=Instance.new("Folder")
myTracks.Name="TrilhaLocal"
myTracks.Parent=tracks
local function footprints()
	local own=player.Character
	if not own or not hunters[own:GetAttribute("Role")] or own:GetAttribute("IsDead") then
		if follow or #myTracks:GetChildren()>0 then myTracks:ClearAllChildren() end
		follow,previous,lastTrack=nil,nil,nil
		return
	end
	local body: Model?=nil
	for _,p in Players:GetPlayers() do
		local other=p.Character
		if other and other:GetAttribute("Role")=="Monster" and not other:GetAttribute("IsDead") then body=other break end
	end
	if body~=follow then
		myTracks:ClearAllChildren()
		follow,previous,lastTrack=body,nil,nil
	end
	if not body then return end
	local root=body:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end
	local pos=root.Position
	local old=previous
	previous=pos
	if not old or body:GetAttribute("IsStealth") or body:GetAttribute("IsEvolving") then lastTrack=pos return end
	local delta=Vector3.new(pos.X-old.X,0,pos.Z-old.Z)
	if delta.Magnitude>18 then lastTrack=pos return end
	if delta.Magnitude<.85 or (lastTrack and (pos-lastTrack).Magnitude<3.6) then return end
	local params=RaycastParams.new()
	params.FilterDescendantsInstances={body,own,myTracks,fauna}
	params.RespectCanCollide=true
	params.IgnoreWater=false
	local h=body:FindFirstChildOfClass("Humanoid")
	local reach=if h then math.max(3.5,h.HipHeight+root.Size.Y/2+.75) else 5
	local floor=workspace:Raycast(pos+root.CFrame.RightVector*(foot*.75),-Vector3.yAxis*reach,params)
	if not floor or floor.Normal.Y<.45 then return end

	-- Meandering Brackish Rivers & Oily Creeks: shallow water washes away Monster tracks!
	local inShallowWater = (floor.Material == Enum.Material.Water)
	if not inShallowWater then
		local waterCheck = workspace:Raycast(pos + Vector3.yAxis * 2.5, -Vector3.yAxis * (reach + 3.0), params)
		if waterCheck and waterCheck.Material == Enum.Material.Water then
			inShallowWater = true
		elseif floor.Instance and (floor.Instance:GetAttribute("MasksFootprints") == true or floor.Instance.Name == "EstuaryOilPatch") then
			inShallowWater = true
		end
	end
	if inShallowWater then
		-- Wash away recent trailing tracks rapidly when entering brackish river water
		local children = myTracks:GetChildren()
		for i = math.max(1, #children - 2), #children do
			local tr = children[i]
			if tr and tr:IsA("BasePart") then
				Tween:Create(tr, TweenInfo.new(0.45), { Transparency = 1 }):Play()
				Debris:AddItem(tr, 0.5)
			end
		end
		lastTrack = pos
		return
	end

	local direction=delta.Unit-floor.Normal*delta.Unit:Dot(floor.Normal)
	if direction.Magnitude<.1 then return end
	local at=floor.Position+floor.Normal*.055
	local basis=CFrame.lookAt(at,at+direction,floor.Normal)
	local printPart=Instance.new("Part")
	printPart.Name="Pegada"
	printPart.Shape=Enum.PartType.Cylinder
	printPart.Size=Vector3.new(.08, 1.35, 1.05)
	printPart.Anchored=true
	printPart.CanCollide,printPart.CanTouch,printPart.CanQuery=false,false,false
	printPart.Color=Color3.fromRGB(194, 132, 62)
	printPart.Material=Enum.Material.Neon
	printPart.Transparency=.42
	printPart.CFrame=basis * CFrame.Angles(0, 0, math.rad(90))
	printPart.Parent=myTracks
	Debris:AddItem(printPart,22)
	foot=-foot
	lastTrack=pos
end
local nestNoticeUntil = 0
local nestBeacon: Model? = nil
local function clearNestBeacon()
	if nestBeacon then
		nestBeacon:Destroy()
		nestBeacon = nil
	end
end
local function updateNestBeacon(c: Model?)
	if not c then
		clearNestBeacon()
		return
	end
	local energy = tonumber(c:GetAttribute("EvolutionEnergy")) or 0
	local stage = tonumber(c:GetAttribute("Stage")) or 1
	local rawNest = c:GetAttribute("NearestNestPos")
	if energy < 100 or stage >= 3 or typeof(rawNest) ~= "Vector3" or (rawNest :: Vector3).Magnitude < 1 then
		clearNestBeacon()
		return
	end
	local nestPos = rawNest :: Vector3
	local rootPos = c:GetPivot().Position
	local dist = math.round((nestPos - rootPos).Magnitude)
	if not nestBeacon then
		local bm = Instance.new("Model")
		bm.Name = "MonsterNestHomingBeacon"
		local pillar = Instance.new("Part")
		pillar.Name = "BeaconBeam"
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Anchored = true
		pillar.CanCollide, pillar.CanQuery, pillar.CanTouch = false, false, false
		pillar.Material = Enum.Material.Neon
		pillar.Color = Color3.fromRGB(255, 72, 24)
		pillar.Transparency = 0.48
		pillar.Size = Vector3.new(260, 4.5, 4.5)
		pillar.Parent = bm

		local labelAnchor = Instance.new("Part")
		labelAnchor.Name = "BeaconLabelAnchor"
		labelAnchor.Anchored = true
		labelAnchor.CanCollide, labelAnchor.CanQuery, labelAnchor.CanTouch = false, false, false
		labelAnchor.Transparency = 1
		labelAnchor.Size = Vector3.one
		labelAnchor.Parent = bm

		local bb = Instance.new("BillboardGui")
		bb.Name = "NestMarkerUI"
		bb.AlwaysOnTop = true
		bb.Size = UDim2.fromOffset(220, 44)
		bb.StudsOffset = Vector3.new(0, 14, 0)
		bb.Parent = labelAnchor

		local txt = Instance.new("TextLabel")
		txt.Name = "DistLabel"
		txt.Size = UDim2.fromScale(1, 1)
		txt.BackgroundColor3 = Color3.fromRGB(24, 10, 10)
		txt.BackgroundTransparency = 0.25
		txt.TextColor3 = Color3.fromRGB(255, 198, 72)
		txt.Font = Enum.Font.GothamBold
		txt.TextScaled = true
		txt.Parent = bb

		bm.Parent = workspace
		nestBeacon = bm
	end
	local beam = nestBeacon and nestBeacon:FindFirstChild("BeaconBeam") :: BasePart?
	local anchor = nestBeacon and nestBeacon:FindFirstChild("BeaconLabelAnchor") :: BasePart?
	if beam and anchor then
		local near = c:GetAttribute("NearEvolutionNest") == true
		local pulseColor = if near then Color3.fromRGB(255, 208, 64) else Color3.fromRGB(255, 58, 22)
		beam.Color = pulseColor
		beam.CFrame = CFrame.new(nestPos + Vector3.new(0, 125, 0)) * CFrame.Angles(0, 0, math.rad(90))
		anchor.Position = nestPos
		local lbl = anchor:FindFirstChild("NestMarkerUI") and anchor.NestMarkerUI:FindFirstChild("DistLabel") :: TextLabel?
		if lbl then
			lbl.Text = if near
				then "NINHO ABISSAL — SEGURE [V]!"
				else string.format("NINHO DE EVOLUÇÃO • %dm", dist)
		end
	end
end
RS.Remotes.GameRemotes.UpdateUI.OnClientEvent:Connect(function(kind: any)
	if kind == "MonsterNestRequired" then
		nestNoticeUntil = os.clock() + 3.0
	end
end)
task.spawn(function()
	while gui.Parent do
		local c=monster()
		hint.Visible=c~=nil
		updateNestBeacon(c)
		if c then
			local state=if c:GetAttribute("IsEating") then "Devorando" elseif c:GetAttribute("IsEvolving") then "Metamorfose" else ""
			if channelName~=state then channelName,channelStart=state,os.clock() end
			if state~="" then
				local duration=if state=="Devorando" then 2.5 else 5
				hint.Text=string.format("%s   %.1f / %.1f s",state,math.min(duration,os.clock()-channelStart),duration)
			else
				local stage = tonumber(c:GetAttribute("Stage")) or 1
				local energy = tonumber(c:GetAttribute("EvolutionEnergy")) or 0
				local stam = math.floor(tonumber(c:GetAttribute("Stamina")) or 0)
				if os.clock() < nestNoticeUntil or (energy >= 100 and stage < 3) then
					local near = c:GetAttribute("NearEvolutionNest") == true
					local dist = tonumber(c:GetAttribute("NearestNestDist")) or 0
					if near then
						hint.Text = string.format("Estágio %d • NO NINHO ABISSAL — SEGURE [V] PARA EVOLUIR (5s)!", stage)
					else
						hint.Text = string.format("ENERGIA 100%%! Retorne ao Ninho de Evolução (%dm) — Siga o Feixe Rubro e segure [V]", dist)
					end
				else
					local nearestPreyDist = math.huge
					local cPos = c:GetPivot().Position
					for _, f in fauna:GetChildren() do
						if f:IsA("Model") and f.PrimaryPart then
							local fd = (f.PrimaryPart.Position - cPos).Magnitude
							if fd < nearestPreyDist then nearestPreyDist = fd end
						end
					end
					local preyInfo = if nearestPreyDist < math.huge then string.format("Presa +%dm", math.round(nearestPreyDist)) else "Sem presas perto"
					local tod = workspace:GetAttribute("TimeOfDayLabel")
					local todStr = if typeof(tod) == "string" and tod ~= "" then ("  •  " .. tod) else ""
					hint.Text=string.format("Estágio %d   •   Energia %d/100   •   Vigor %d/100   •   %s%s\n1 Salto   2 Investida   3 Ácido   Q Sonar   Ctrl Furtivo   E Devorar   V Ninho",
						stage, energy, stam, preyInfo, todStr)
				end
			end
		else
			channelName=""
			if heldEat or heldStealth or heldEvolve then release(nil) end
			if #marking>0 then clearPulse() end
		end
		footprints()
		task.wait(.12)
	end
end)
