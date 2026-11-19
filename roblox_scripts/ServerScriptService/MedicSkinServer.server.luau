--!strict
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local R15_LIMBS = {
	"Head", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local SCALE_NAMES = {
	"HeadScale", "BodyWidthScale", "BodyHeightScale",
	"BodyDepthScale", "BodyTypeScale", "BodyProportionScale",
}

local BLOCKY_SCALES: {[string]: number} = {
	HeadScale = 1,
	BodyWidthScale = 1,
	BodyHeightScale = 1,
	BodyDepthScale = 1,
	BodyTypeScale = 0,
	BodyProportionScale = 0,
}

local warnedMissingTemplate = false

local function getTemplate(): Model?
	local folder = ServerStorage:FindFirstChild("HunterAssets")
	local tpl = folder and folder:FindFirstChild("MedicBioVanguardTemplate")
	return if tpl and tpl:IsA("Model") then tpl else nil
end

local function shouldWearMedic(character: Model): boolean
	local role = character:GetAttribute("Role")
	local pref = character:GetAttribute("PreferredRole")
	if role == "Medic" then
		return true
	end
	if role == "Lobby" and pref == "Medic" then
		return true
	end
	return false
end

local function waitForR15Limbs(character: Model, humanoid: Humanoid): boolean
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false
	end
	local deadline = os.clock() + 4
	while character.Parent ~= nil and os.clock() < deadline do
		local ready = true
		for _, limbName in ipairs(R15_LIMBS) do
			if not character:FindFirstChild(limbName) then
				ready = false
				break
			end
		end
		if ready then
			return true
		end
		task.wait(0.05)
	end
	return false
end

local function createBootJetFX(footPart: BasePart, outfitFolder: Folder)
	for _, spec in ipairs({
		{ name = "MedicBootJetFX_Cyan", x = -0.24, color = Color3.fromRGB(35, 224, 255) },
		{ name = "MedicBootJetFX_Amber", x = 0.24, color = Color3.fromRGB(255, 134, 28) },
	}) do
		local oldAtt = footPart:FindFirstChild("MedicBootJetAtt_" .. spec.name)
		if oldAtt then oldAtt:Destroy() end

		local att = Instance.new("Attachment")
		att.Name = "MedicBootJetAtt_" .. spec.name
		att.Position = Vector3.new(spec.x, -0.05, 0.56)
		att.Orientation = Vector3.new(-38, 180, 0)
		att.Parent = footPart

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = spec.name
		emitter.Enabled = false
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.25, spec.color),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 40, 60)),
		})
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.28),
			NumberSequenceKeypoint.new(0.4, 0.22),
			NumberSequenceKeypoint.new(1, 0.04),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.LightEmission = 0.9
		emitter.Lifetime = NumberRange.new(0.14, 0.24)
		emitter.Rate = 55
		emitter.Speed = NumberRange.new(10, 16)
		emitter.SpreadAngle = Vector2.new(8, 8)
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Parent = att

		local tag = Instance.new("ObjectValue")
		tag.Name = "BootJetAttRef"
		tag.Value = att
		tag.Parent = outfitFolder
	end
end

local function removeMedicSkin(character: Model)
	local outfit = character:FindFirstChild("MedicBioVanguardOutfit")
	if outfit then
		for _, child in ipairs(outfit:GetChildren()) do
			if child:IsA("ObjectValue") and child.Name == "BootJetAttRef" and child.Value then
				child.Value:Destroy()
			end
		end
		outfit:Destroy()
	end

	for _, limbName in ipairs({"LeftFoot", "RightFoot"}) do
		local foot = character:FindFirstChild(limbName)
		if foot then
			for _, desc in ipairs(foot:GetChildren()) do
				if desc:IsA("Attachment") and string.sub(desc.Name, 1, 15) == "MedicBootJetAtt" then
					desc:Destroy()
				end
			end
		end
	end

	local saved = character:FindFirstChild("MedicSavedAppearance")
	if saved and saved:IsA("Configuration") then
		for _, limbName in ipairs(R15_LIMBS) do
			local part = character:FindFirstChild(limbName)
			if part and part:IsA("BasePart") then
				local val = saved:GetAttribute("Part_" .. limbName)
				if typeof(val) == "number" then
					part.Transparency = val
				end
			end
		end

		local head = character:FindFirstChild("Head")
		if head then
			for _, desc in ipairs(head:GetChildren()) do
				if desc:IsA("Decal") then
					local val = saved:GetAttribute("Decal_" .. desc.Name)
					if typeof(val) == "number" then
						desc.Transparency = val
					end
				end
			end
		end

		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Accessory") then
				local handle = child:FindFirstChild("Handle")
				if handle and handle:IsA("BasePart") then
					local val = saved:GetAttribute("Acc_" .. child.Name)
					if typeof(val) == "number" then
						handle.Transparency = val
					end
				end
			end
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			for _, sName in ipairs(SCALE_NAMES) do
				local valObj = humanoid:FindFirstChild(sName)
				local orig = saved:GetAttribute("Scale_" .. sName)
				if valObj and valObj:IsA("NumberValue") and typeof(orig) == "number" then
					valObj.Value = orig
				end
			end
		end

		saved:Destroy()
	end

	character:SetAttribute("MedicSkinActive", false)
end

local function applyMedicSkin(character: Model)
	if character:GetAttribute("MedicSkinActive") == true then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 4) :: Humanoid?
	if not humanoid or not waitForR15Limbs(character, humanoid) then
		return
	end
	if not shouldWearMedic(character) then
		return
	end

	-- Wait for AssaultSkinServer cleanup if switching Assault -> Medic in Lobby
	local waitDeadline = os.clock() + 1
	while (character:GetAttribute("AssaultSkinActive") == true or character:FindFirstChild("AssaultSavedAppearance") ~= nil) and os.clock() < waitDeadline do
		task.wait(0.02)
	end
	if not shouldWearMedic(character) then
		return
	end

	local template = getTemplate()
	if not template then
		if not warnedMissingTemplate then
			warnedMissingTemplate = true
			warn("[MedicSkinServer] MedicBioVanguardTemplate nao encontrado em ServerStorage.HunterAssets (aguardando importacao do FBX)")
		end
		return
	end

	local oldOutfit = character:FindFirstChild("MedicBioVanguardOutfit")
	if oldOutfit then oldOutfit:Destroy() end
	local oldSaved = character:FindFirstChild("MedicSavedAppearance")
	if oldSaved then oldSaved:Destroy() end

	local saved = Instance.new("Configuration")
	saved.Name = "MedicSavedAppearance"

	for _, sName in ipairs(SCALE_NAMES) do
		local valObj = humanoid:FindFirstChild(sName)
		if valObj and valObj:IsA("NumberValue") then
			saved:SetAttribute("Scale_" .. sName, valObj.Value)
			valObj.Value = BLOCKY_SCALES[sName]
		end
	end

	for _, limbName in ipairs(R15_LIMBS) do
		local part = character:FindFirstChild(limbName)
		if part and part:IsA("BasePart") then
			saved:SetAttribute("Part_" .. limbName, part.Transparency)
			part.Transparency = 1
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		for _, desc in ipairs(head:GetChildren()) do
			if desc:IsA("Decal") then
				saved:SetAttribute("Decal_" .. desc.Name, desc.Transparency)
				desc.Transparency = 1
			end
		end
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				saved:SetAttribute("Acc_" .. child.Name, handle.Transparency)
				handle.Transparency = 1
			end
		end
	end

	saved.Parent = character

	local outfit = Instance.new("Folder")
	outfit.Name = "MedicBioVanguardOutfit"
	outfit.Parent = character

	for _, tplPart in ipairs(template:GetChildren()) do
		if tplPart:IsA("BasePart") then
			local targetName = tplPart:GetAttribute("TargetLimb")
			local relVal = tplPart:FindFirstChild("RelOffset")
			local targetPart = if typeof(targetName) == "string" then character:FindFirstChild(targetName) else nil
			if targetPart and targetPart:IsA("BasePart") and relVal and relVal:IsA("CFrameValue") then
				local clone = tplPart:Clone()
				local rVal = clone:FindFirstChild("RelOffset")
				if rVal then rVal:Destroy() end
				clone.Anchored = false
				clone.CanCollide = false
				clone.CanTouch = false
				clone.CanQuery = false
				clone.Massless = true
				clone.CFrame = targetPart.CFrame * relVal.Value
				clone.Parent = outfit

				local weld = Instance.new("Weld")
				weld.Name = "MedicWeld"
				weld.Part0 = targetPart
				weld.Part1 = clone
				weld.C0 = relVal.Value
				weld.C1 = CFrame.identity
				weld.Parent = clone
			end
		end
	end

	for _, footName in ipairs({"LeftFoot", "RightFoot"}) do
		local foot = character:FindFirstChild(footName)
		if foot and foot:IsA("BasePart") then
			createBootJetFX(foot, outfit)
		end
	end

	character:SetAttribute("MedicSkinActive", true)
end

local function evaluateCharacter(character: Model)
	if character.Parent == nil then
		return
	end
	if shouldWearMedic(character) then
		applyMedicSkin(character)
	else
		if character:GetAttribute("MedicSkinActive") == true or character:FindFirstChild("MedicBioVanguardOutfit") then
			removeMedicSkin(character)
		end
	end
end

local function bindCharacter(character: Model)
	character:GetAttributeChangedSignal("Role"):Connect(function()
		evaluateCharacter(character)
	end)
	character:GetAttributeChangedSignal("PreferredRole"):Connect(function()
		evaluateCharacter(character)
	end)
	local hunterAssets = ServerStorage:FindFirstChild("HunterAssets")
	if hunterAssets then
		hunterAssets.ChildAdded:Connect(function(child)
			if child.Name == "MedicBioVanguardTemplate" then
				task.defer(evaluateCharacter, character)
			end
		end)
	end
	task.defer(evaluateCharacter, character)
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	bindPlayer(p)
end

