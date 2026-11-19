--!strict
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local FOOT_OFFSET = CFrame.new(0, -2.75, 0)

local STAGE_VISUALS: { [number]: { neonColor: Color3, lightColor: Color3, brightness: number, range: number, emberRate: number } } = {
	[1] = {
		neonColor = Color3.fromRGB(255, 86, 20),
		lightColor = Color3.fromRGB(255, 82, 24),
		brightness = 2.6,
		range = 20,
		emberRate = 18,
	},
	[2] = {
		neonColor = Color3.fromRGB(255, 148, 28),
		lightColor = Color3.fromRGB(255, 136, 32),
		brightness = 3.8,
		range = 28,
		emberRate = 28,
	},
	[3] = {
		neonColor = Color3.fromRGB(255, 208, 96),
		lightColor = Color3.fromRGB(255, 168, 56),
		brightness = 5.4,
		range = 40,
		emberRate = 42,
	},
}

local function getArticulatedTemplate(): Model?
	local monsterAssets = ServerStorage:FindFirstChild("MonsterAssets")
	local tpl = monsterAssets and monsterAssets:FindFirstChild("AbyssMonsterArticulatedTemplate")
	return if tpl and tpl:IsA("Model") then tpl else nil
end

local function shouldWearMonster(character: Model): boolean
	return character:GetAttribute("Role") == "Monster"
end

local function updateStageAndStateVisuals(character: Model): ()
	local outfit = character:FindFirstChild("MonsterAbyssalOutfit")
	if not outfit then
		return
	end

	local rawStage = character:GetAttribute("Stage")
	local stage = if typeof(rawStage) == "number" then math.clamp(math.round(rawStage), 1, 3) else 1
	local stageCfg = STAGE_VISUALS[stage] or STAGE_VISUALS[1]
	local isStealth = character:GetAttribute("IsStealth") == true
	local action = character:GetAttribute("MonsterAction")
	local isEvolving = character:GetAttribute("IsEvolving") == true

	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and character:GetAttribute("Role") == "Monster" then
		local camY = if stage >= 3 then 11.2 elseif stage == 2 then 8.5 else 6.2
		hum.CameraOffset = Vector3.new(0, camY, 0)
	end

	for _, desc in ipairs(outfit:GetDescendants()) do
		if desc:IsA("BasePart") then
			if string.sub(desc.Name, 1, 5) == "MArt_" then
				local minStage = desc:GetAttribute("MinStage")
				local maxStage = desc:GetAttribute("MaxStage")
				local visible = true
				if typeof(minStage) == "number" and stage < minStage then
					visible = false
				end
				if typeof(maxStage) == "number" and stage > maxStage then
					visible = false
				end
				desc.Transparency = if not visible then 1 elseif isStealth then 0.58 else 0
				if desc:GetAttribute("MatKind") == "Neon" then
					desc.Color = stageCfg.neonColor
				end
			else
				desc.Transparency = 1
			end
		elseif desc:IsA("PointLight") and desc.Name == "MonsterCoreLight" then
			desc.Color = stageCfg.lightColor
			desc.Brightness = if isStealth then stageCfg.brightness * 0.30 else stageCfg.brightness
			desc.Range = if isStealth then stageCfg.range * 0.50 else stageCfg.range
		elseif desc:IsA("ParticleEmitter") then
			if desc.Name == "SolarEmberEmitter" then
				desc.Enabled = not isStealth
				desc.Rate = stageCfg.emberRate
			elseif desc.Name == "AcidBreathEmitter" then
				desc.Enabled = (action == "AcidBreath")
			elseif desc.Name == "EvolveAuraEmitter" then
				desc.Enabled = isEvolving
			end
		end
	end
end

local function removeMonsterSkin(character: Model): ()
	local outfit = character:FindFirstChild("MonsterAbyssalOutfit")
	if outfit then
		outfit:Destroy()
	end

	local saved = character:FindFirstChild("MonsterSavedAppearance")
	if saved then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
				local val = child:GetAttribute("MonsterSavedTransparency")
				if typeof(val) == "number" then
					child.Transparency = val
					child:SetAttribute("MonsterSavedTransparency", nil)
				end
			elseif child:IsA("Accessory") then
				local handle = child:FindFirstChild("Handle")
				if handle and handle:IsA("BasePart") then
					local val = handle:GetAttribute("MonsterSavedTransparency")
					if typeof(val) == "number" then
						handle.Transparency = val
						handle:SetAttribute("MonsterSavedTransparency", nil)
					end
				end
			end
		end

		local head = character:FindFirstChild("Head")
		if head then
			for _, desc in ipairs(head:GetChildren()) do
				if desc:IsA("Decal") then
					local val = desc:GetAttribute("MonsterSavedTransparency")
					if typeof(val) == "number" then
						desc.Transparency = val
						desc:SetAttribute("MonsterSavedTransparency", nil)
					end
				end
			end
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end

		saved:Destroy()
	end

	character:SetAttribute("MonsterSkinActive", false)
end

local function createMonsterVFX(outfit: Model): ()
	local chest = outfit:FindFirstChild("Node_Chest")
	local head = outfit:FindFirstChild("Node_Head")
	local pelvis = outfit:FindFirstChild("Node_Pelvis")

	if chest and chest:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Name = "MonsterCoreLight"
		light.Shadows = false
		light.Parent = chest

		local embers = Instance.new("ParticleEmitter")
		embers.Name = "SolarEmberEmitter"
		embers.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 224, 118)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 108, 28)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(168, 24, 12)),
		})
		embers.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.22),
			NumberSequenceKeypoint.new(0.5, 0.34),
			NumberSequenceKeypoint.new(1, 0),
		})
		embers.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		embers.Lifetime = NumberRange.new(0.9, 1.8)
		embers.Rate = 18
		embers.Speed = NumberRange.new(2.2, 5.2)
		embers.SpreadAngle = Vector2.new(45, 45)
		embers.Acceleration = Vector3.new(0, 4.5, 0)
		embers.LightEmission = 1
		embers.Parent = chest
	end

	if head and head:IsA("BasePart") then
		local mouthAtt = Instance.new("Attachment")
		mouthAtt.Name = "AcidMouthAttachment"
		mouthAtt.Position = Vector3.new(0, -0.25, -0.85)
		mouthAtt.Parent = head

		local acid = Instance.new("ParticleEmitter")
		acid.Name = "AcidBreathEmitter"
		acid.Enabled = false
		acid.EmissionDirection = Enum.NormalId.Front
		acid.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(204, 255, 110)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 245, 48)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(48, 120, 24)),
		})
		acid.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.5, 1.45),
			NumberSequenceKeypoint.new(1, 2.2),
		})
		acid.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.10),
			NumberSequenceKeypoint.new(1, 1),
		})
		acid.Lifetime = NumberRange.new(0.45, 0.85)
		acid.Rate = 85
		acid.Speed = NumberRange.new(34, 48)
		acid.SpreadAngle = Vector2.new(18, 18)
		acid.Acceleration = Vector3.new(0, -14, 0)
		acid.LightEmission = 0.85
		acid.Parent = mouthAtt
	end

	if pelvis and pelvis:IsA("BasePart") then
		local evolveFX = Instance.new("ParticleEmitter")
		evolveFX.Name = "EvolveAuraEmitter"
		evolveFX.Enabled = false
		evolveFX.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 180)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 152, 32)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 44, 18)),
		})
		evolveFX.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.65),
			NumberSequenceKeypoint.new(1, 0),
		})
		evolveFX.Lifetime = NumberRange.new(0.7, 1.3)
		evolveFX.Rate = 65
		evolveFX.Speed = NumberRange.new(6, 14)
		evolveFX.SpreadAngle = Vector2.new(180, 180)
		evolveFX.Acceleration = Vector3.new(0, 12, 0)
		evolveFX.LightEmission = 1
		evolveFX.Parent = pelvis
	end
end

local function applyMonsterSkin(character: Model): ()
	if character:GetAttribute("MonsterSkinActive") == true and character:FindFirstChild("MonsterAbyssalOutfit") then
		updateStageAndStateVisuals(character)
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 4)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 4)
	if not root or not root:IsA("BasePart") or not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	-- Aguarda cabeca do avatar existir para evitar partes residuais visiveis
	if not character:FindFirstChild("Head") then
		character:WaitForChild("Head", 2)
	end

	if not shouldWearMonster(character) then
		return
	end

	-- Garante que skins de cacador nao permanecam ativas se houve troca rapida
	local waitDeadline = os.clock() + 0.5
	while (character:GetAttribute("AssaultSkinActive") == true or character:GetAttribute("MedicSkinActive") == true) and os.clock() < waitDeadline do
		task.wait(0.02)
	end
	if not shouldWearMonster(character) then
		return
	end

	local template = getArticulatedTemplate()
	if not template then
		warn("[MonsterSkinServer] AbyssMonsterArticulatedTemplate nao encontrado em ServerStorage.MonsterAssets")
		return
	end

	local oldOutfit = character:FindFirstChild("MonsterAbyssalOutfit")
	if oldOutfit then
		oldOutfit:Destroy()
	end
	local oldSaved = character:FindFirstChild("MonsterSavedAppearance")
	if oldSaved then
		oldSaved:Destroy()
	end

	local saved = Instance.new("Configuration")
	saved.Name = "MonsterSavedAppearance"

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			if child:GetAttribute("MonsterSavedTransparency") == nil then
				child:SetAttribute("MonsterSavedTransparency", child.Transparency)
			end
			child.Transparency = 1
		elseif child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				if handle:GetAttribute("MonsterSavedTransparency") == nil then
					handle:SetAttribute("MonsterSavedTransparency", handle.Transparency)
				end
				handle.Transparency = 1
			end
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		for _, desc in ipairs(head:GetChildren()) do
			if desc:IsA("Decal") then
				if desc:GetAttribute("MonsterSavedTransparency") == nil then
					desc:SetAttribute("MonsterSavedTransparency", desc.Transparency)
				end
				desc.Transparency = 1
			end
		end
	end

	saved.Parent = character

	local outfit = template:Clone()
	outfit.Name = "MonsterAbyssalOutfit"
	for _, desc in ipairs(outfit:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
		end
	end

	local nodeRoot = outfit:FindFirstChild("Node_Root")
	if not nodeRoot or not nodeRoot:IsA("BasePart") then
		warn("[MonsterSkinServer] Node_Root ausente em AbyssMonsterArticulatedTemplate")
		outfit:Destroy()
		return
	end

	outfit:PivotTo(root.CFrame * FOOT_OFFSET)
	outfit.Parent = character

	local rootWeld = Instance.new("Weld")
	rootWeld.Name = "MonsterRootWeld"
	rootWeld.Part0 = root
	rootWeld.Part1 = nodeRoot
	rootWeld.C0 = FOOT_OFFSET
	rootWeld.C1 = CFrame.identity
	rootWeld.Parent = nodeRoot

	createMonsterVFX(outfit)
	humanoid.CameraOffset = Vector3.new(0, 6.2, 0)

	character:SetAttribute("MonsterSkinActive", true)
	updateStageAndStateVisuals(character)
end

local function evaluateCharacter(character: Model): ()
	if character.Parent == nil then
		return
	end
	if shouldWearMonster(character) then
		applyMonsterSkin(character)
	else
		if character:GetAttribute("MonsterSkinActive") == true or character:FindFirstChild("MonsterAbyssalOutfit") then
			removeMonsterSkin(character)
		end
	end
end

local function bindCharacter(character: Model): ()
	character:GetAttributeChangedSignal("Role"):Connect(function()
		evaluateCharacter(character)
	end)
	for _, attr in ipairs({ "Stage", "IsStealth", "MonsterAction", "IsEvolving" }) do
		character:GetAttributeChangedSignal(attr):Connect(function()
			updateStageAndStateVisuals(character)
		end)
	end
	task.defer(evaluateCharacter, character)
end

local function bindPlayer(player: Player): ()
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	bindPlayer(p)
end


