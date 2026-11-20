--!strict
-- O servidor de armas/habilidades valida o acerto antes de chamar ApplyDamage.
local damageApplied = Instance.new("BindableEvent")
local DamageService = {DamageApplied = damageApplied.Event}
local gameRemotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("GameRemotes")

local HUNTERS: {[string]: boolean} = { Assault = true, Medic = true, Trapper = true, Support = true }
local BLEED_SECONDS = 30
local bleeding: {[Model]: number} = setmetatable({}, { __mode = "k" }) :: any

local function inCombat(): boolean
	local phase = gameRemotes:GetAttribute("MatchState")
	return not gameRemotes:GetAttribute("RoundClosed") and (phase == "MonsterHeadStart" or phase == "ActiveHunt")
end

local function numberAttribute(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if typeof(value) == "number" then math.max(0, value) else 0
end

-- O estado definitivo da partida está nos atributos. O Humanoid conserva pelo
-- menos um ponto para que a animação, o revive e a câmera continuem disponíveis.
function DamageService.SyncHumanoid(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.BreakJointsOnDeath = false
	if humanoid.Health <= 0 or humanoid.MaxHealth < 1 then return end
	local maximum = numberAttribute(character, "MaxCustomHealth")
	if maximum <= 0 then return end
	local ratio = math.clamp(numberAttribute(character, "CustomHealth") / maximum, 0, 1)
	local nativeHealth = math.max(1, humanoid.MaxHealth * ratio)
	if math.abs(humanoid.Health - nativeHealth) > 0.001 then
		humanoid.Health = nativeHealth
	end
end

local function markDead(character: Model)
	bleeding[character] = nil
	character:SetAttribute("IsDead", true)
	character:SetAttribute("IsDowned", false)
	character:SetAttribute("BleedoutRemaining", 0)
	character:SetAttribute("CustomHealth", 0)
	DamageService.SyncHumanoid(character)
end

local function startBleeding(character: Model)
	local deadline = os.clock() + BLEED_SECONDS
	bleeding[character] = deadline
	character:SetAttribute("HasBeenDowned", true)
	character:SetAttribute("BleedoutRemaining", BLEED_SECONDS)
	character:SetAttribute("IsDowned", true)
	task.spawn(function()
		while bleeding[character] == deadline do
			if character.Parent == nil or not HUNTERS[character:GetAttribute("Role")]
				or character:GetAttribute("IsDowned") ~= true or character:GetAttribute("IsDead") then
				bleeding[character] = nil
				break
			end
			local remaining = math.max(0, math.ceil(deadline - os.clock()))
			character:SetAttribute("BleedoutRemaining", remaining)
			if remaining == 0 then
				markDead(character)
				break
			end
			task.wait(1)
		end
	end)
end

-- Já validada a habilidade de revive pelo servidor do médico, esta operação
-- restaura um caçador caído. A segunda queda na mesma rodada é definitiva.
function DamageService.Revive(character: Model, health: number): boolean
	if not inCombat() or gameRemotes:GetAttribute("SuddenDeath") == true
		or typeof(health) ~= "number" or not (health > 0 and health < math.huge)
		or not HUNTERS[character:GetAttribute("Role")] or character:GetAttribute("IsDead")
		or character:GetAttribute("IsDowned") ~= true then return false end
	bleeding[character] = nil
	character:SetAttribute("CustomHealth", math.min(health, numberAttribute(character, "MaxCustomHealth")))
	character:SetAttribute("BleedoutRemaining", 0)
	character:SetAttribute("IsDowned", false)
	DamageService.SyncHumanoid(character)
	return true
end

-- O servidor da habilidade valida quem cura e o alcance. Retorna a vida recuperada.
function DamageService.Heal(character: Model, amount: number): number
	if not inCombat() or typeof(amount) ~= "number" or not (amount > 0 and amount < math.huge) then
		return 0
	end
	if typeof(character) ~= "Instance" or not character:IsA("Model") or not character:IsDescendantOf(workspace) then
		return 0
	end
	local role = character:GetAttribute("Role")
	if typeof(role) ~= "string" or not HUNTERS[role] or character:GetAttribute("IsDead") or character:GetAttribute("IsDowned") then
		return 0
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return 0 end

	local current = numberAttribute(character, "CustomHealth")
	local maximum = numberAttribute(character, "MaxCustomHealth")
	if not (current > 0 and current < maximum and maximum < math.huge) then return 0 end
	local newHealth = math.min(current + amount, maximum)
	character:SetAttribute("CustomHealth", newHealth)
	DamageService.SyncHumanoid(character)
	return newHealth - current
end

local function absorb(character: Model, name: string, amount: number): number
	local current = numberAttribute(character, name)
	local absorbed = math.min(current, amount)
	if absorbed > 0 then character:SetAttribute(name, current - absorbed) end
	return amount - absorbed
end

function DamageService.ApplyDamage(attacker: Player?, targetCharacter: Model, amount: number, ignoreArmor: boolean?)
	if not inCombat() or typeof(targetCharacter) ~= "Instance" or not targetCharacter:IsA("Model")
		or typeof(amount) ~= "number" or not (amount > 0 and amount < math.huge) then return end
	local role = targetCharacter:GetAttribute("Role")
	if role ~= "Monster" and not HUNTERS[role] then return end
	if targetCharacter:GetAttribute("IsDead") or targetCharacter:GetAttribute("IsDowned") then return end
	local remaining = absorb(targetCharacter, "PersonalShield", amount)
	if not ignoreArmor then remaining = absorb(targetCharacter, "Armor", remaining) end
	local previousHealth = numberAttribute(targetCharacter, "CustomHealth")
	local applied = amount - remaining + math.min(previousHealth, remaining)
	if applied > 0 then damageApplied:Fire(attacker, targetCharacter, applied) end
	if remaining <= 0 then return end
	local health = math.max(0, previousHealth - remaining)
	targetCharacter:SetAttribute("CustomHealth", health)
	if health > 0 then
		DamageService.SyncHumanoid(targetCharacter)
	elseif role == "Monster" or targetCharacter:GetAttribute("HasBeenDowned") then
		markDead(targetCharacter)
	else
		startBleeding(targetCharacter)
		DamageService.SyncHumanoid(targetCharacter)
	end
end

return DamageService


