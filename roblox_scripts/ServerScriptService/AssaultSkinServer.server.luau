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

local function getTemplate(): Model?
	local folder = ServerStorage:FindFirstChild("HunterAssets")
	local tpl = folder and folder:FindFirstChild("AssaultVanguardTemplate")
	return if tpl and tpl:IsA("Model") then tpl else nil
end

local function shouldWearAssault(character: Model): boolean
	local role = character:GetAttribute("Role")
	local pref = character:GetAttribute("PreferredRole")
	if role == "Assault" then
		return true
	end
	if role == "Lobby" and pref == "Assault" then
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

local function removeAssaultSkin(character: Model)
	local outfit = character:FindFirstChild("AssaultVanguardOutfit")
	if outfit then
		outfit:Destroy()
	end

	local saved = character:FindFirstChild("AssaultSavedAppearance")
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
					local val = desc:GetAttribute("AssaultOriginalTransparency")
					if val == nil then val = saved:GetAttributes()["Decal_" .. desc.Name] end
					desc:SetAttribute("AssaultOriginalTransparency",nil)
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
					local val = handle:GetAttribute("AssaultOriginalTransparency")
					if val == nil then val = saved:GetAttributes()["Acc_" .. child.Name] end
					handle:SetAttribute("AssaultOriginalTransparency",nil)
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

	character:SetAttribute("AssaultSkinActive", false)
end

local function applyAssaultSkin(character: Model)
	if character:GetAttribute("AssaultSkinActive") == true then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 4) :: Humanoid?
	if not humanoid or not waitForR15Limbs(character, humanoid) then
		return
	end
	if not shouldWearAssault(character) then
		return
	end

	local waitDeadline = os.clock() + 1
	while (character:GetAttribute("MedicSkinActive") == true or character:FindFirstChild("MedicSavedAppearance") ~= nil) and os.clock() < waitDeadline do
		task.wait(0.02)
	end
	if not shouldWearAssault(character) then
		return
	end

	if character:GetAttribute("AssaultSkinActive") == true then return end
	local template = getTemplate()
	if not template then
		warn("[AssaultSkinServer] AssaultVanguardTemplate nao encontrado em ServerStorage.HunterAssets")
		return
	end

	-- Remove residual outfit if any
	local oldOutfit = character:FindFirstChild("AssaultVanguardOutfit")
	if oldOutfit then oldOutfit:Destroy() end
	local oldSaved = character:FindFirstChild("AssaultSavedAppearance")
	if oldSaved then oldSaved:Destroy() end

	-- Save original appearance & scales cleanly
	local saved = Instance.new("Configuration")
	saved.Name = "AssaultSavedAppearance"

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
				desc:SetAttribute("AssaultOriginalTransparency", desc.Transparency)
				desc.Transparency = 1
			end
		end
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle:SetAttribute("AssaultOriginalTransparency", handle.Transparency)
				handle.Transparency = 1
			end
		end
	end

	saved.Parent = character

	-- Clone all 66 Assault Vanguard MeshParts and weld each to its R15 limb
	local outfit = Instance.new("Folder")
	outfit.Name = "AssaultVanguardOutfit"
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
				weld.Name = "AssaultWeld"
				weld.Part0 = targetPart
				weld.Part1 = clone
				weld.C0 = relVal.Value
				weld.C1 = CFrame.identity
				weld.Parent = clone
			end
		end
	end

	character:SetAttribute("AssaultSkinActive", true)
end

local function evaluateCharacter(character: Model)
	if character.Parent == nil then
		return
	end
	if shouldWearAssault(character) then
		applyAssaultSkin(character)
	else
		if character:GetAttribute("AssaultSkinActive") == true or character:FindFirstChild("AssaultVanguardOutfit") then
			removeAssaultSkin(character)
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
