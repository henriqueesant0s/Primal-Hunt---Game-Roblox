--!strict
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

export type CueSpec = {
	Id: string,
	Volume: number,
	Speed: number,
	TimePos: number?,
	MinDist: number?,
	MaxDist: number?,
	Looped: boolean?,
	Cleanup: number?,
}

local CUES: {[string]: CueSpec} = table.freeze({
	JetpackThrust = table.freeze({Id = "rbxassetid://9113044263", Volume = 0.40, Speed = 1.12, MinDist = 8, MaxDist = 130, Looped = true}),
	JetpackDodge = table.freeze({Id = "rbxassetid://9126009951", Volume = 0.60, Speed = 1.25, MinDist = 10, MaxDist = 140, Cleanup = 2.0}),
	PlasmaRifle = table.freeze({Id = "rbxassetid://9116236630", Volume = 0.42, Speed = 1.38, TimePos = 0.16, MinDist = 10, MaxDist = 180, Cleanup = 1.4}),
	IonRifle = table.freeze({Id = "rbxassetid://9114315138", Volume = 0.55, Speed = 1.22, MinDist = 12, MaxDist = 210, Cleanup = 2.2}),
	BioCarbine = table.freeze({Id = "rbxassetid://9116225257", Volume = 0.38, Speed = 1.55, MinDist = 10, MaxDist = 170, Cleanup = 1.6}),
	GaussSMG = table.freeze({Id = "rbxassetid://9113180776", Volume = 0.36, Speed = 1.32, MinDist = 10, MaxDist = 160, Cleanup = 1.1}),
	LaserCutter = table.freeze({Id = "rbxassetid://9116235979", Volume = 0.38, Speed = 1.60, TimePos = 0.14, MinDist = 10, MaxDist = 175, Cleanup = 1.4}),
	WeaponHit = table.freeze({Id = "rbxassetid://9119073323", Volume = 0.44, Speed = 1.15, MinDist = 8, MaxDist = 120, Cleanup = 0.8}),
	ReviveLoop = table.freeze({Id = "rbxassetid://9119103113", Volume = 0.42, Speed = 1.05, MinDist = 6, MaxDist = 75, Looped = true}),
	ReviveComplete = table.freeze({Id = "rbxassetid://9114302479", Volume = 0.58, Speed = 1.18, MinDist = 10, MaxDist = 130, Cleanup = 3.0}),
	DomeDeploy = table.freeze({Id = "rbxassetid://9125544480", Volume = 0.70, Speed = 1.08, MinDist = 25, MaxDist = 420, Cleanup = 7.2}),
	DomeHum = table.freeze({Id = "rbxassetid://9125550012", Volume = 0.28, Speed = 0.92, MinDist = 20, MaxDist = 260, Looped = true}),
	DomeCollapse = table.freeze({Id = "rbxassetid://9114340693", Volume = 0.62, Speed = 0.85, MinDist = 25, MaxDist = 350, Cleanup = 4.0}),
	ScannerPulse = table.freeze({Id = "rbxassetid://9125981390", Volume = 0.54, Speed = 1.08, MinDist = 14, MaxDist = 220, Cleanup = 2.8}),
	ScannerPingLocal = table.freeze({Id = "rbxassetid://9125981390", Volume = 0.32, Speed = 1.16, Cleanup = 2.5}),
	EquipIonRifle = table.freeze({Id = "rbxassetid://9118592471", Volume = 0.54, Speed = 1.35, MinDist = 10, MaxDist = 140, Cleanup = 2.2}),
	MatrixActivate = table.freeze({Id = "rbxassetid://9114315023", Volume = 0.52, Speed = 1.25, MinDist = 10, MaxDist = 140, Cleanup = 2.4}),
	MatrixLoop = table.freeze({Id = "rbxassetid://9125549390", Volume = 0.24, Speed = 1.05, MinDist = 6, MaxDist = 90, Looped = true}),
	MatrixEnd = table.freeze({Id = "rbxassetid://9119072660", Volume = 0.45, Speed = 0.92, MinDist = 8, MaxDist = 110, Cleanup = 1.4}),
	HealBurst = table.freeze({Id = "rbxassetid://9116394545", Volume = 0.60, Speed = 1.12, MinDist = 12, MaxDist = 150, Cleanup = 2.5}),
	HealBeamLoop = table.freeze({Id = "rbxassetid://9116395089", Volume = 0.34, Speed = 0.96, MinDist = 8, MaxDist = 110, Looped = true}),
	HarpoonFire = table.freeze({Id = "rbxassetid://9125419776", Volume = 0.58, Speed = 1.30, MinDist = 12, MaxDist = 160, Cleanup = 2.4}),
	HarpoonBreak = table.freeze({Id = "rbxassetid://9113660376", Volume = 0.62, Speed = 1.35, MinDist = 14, MaxDist = 180, Cleanup = 2.5}),
	ProjectorActivate = table.freeze({Id = "rbxassetid://9117060349", Volume = 0.44, Speed = 1.22, MinDist = 8, MaxDist = 110, Cleanup = 1.4}),
	ProjectorLoop = table.freeze({Id = "rbxassetid://9125549390", Volume = 0.30, Speed = 1.18, MinDist = 8, MaxDist = 110, Looped = true}),
	BarrageWarning = table.freeze({Id = "rbxassetid://9119662934", Volume = 0.56, Speed = 1.28, MinDist = 20, MaxDist = 300, Cleanup = 2.2}),
	BarrageImpact = table.freeze({Id = "rbxassetid://9114362401", Volume = 0.68, Speed = 1.10, MinDist = 24, MaxDist = 320, Cleanup = 5.0}),
	AbilityDenied = table.freeze({Id = "rbxassetid://9125540237", Volume = 0.34, Speed = 0.96, Cleanup = 1.0}),
})

local isServer = RunService:IsServer()
local groupName = if isServer then "ProjectAbyss_HunterSFX" else "ProjectAbyss_HunterClientSFX"

local function ensureGroup(): SoundGroup
	local existing = SoundService:FindFirstChild(groupName)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = groupName
	group.Volume = 0.85
	group.Parent = SoundService
	return group
end

local activeGroup = ensureGroup()
local rng = Random.new()
local lastLocal: {[string]: number} = {}

local function jitterSpeed(base: number, jitter: number?): number
	if jitter and jitter > 0 then
		return math.max(0.2, base + rng:NextNumber(-jitter, jitter))
	end
	return base
end

local function configureSpatialSound(sound: Sound, spec: CueSpec, pitchJitter: number?)
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume
	sound.PlaybackSpeed = jitterSpeed(spec.Speed, pitchJitter)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = spec.MinDist or 10
	sound.RollOffMaxDistance = spec.MaxDist or 150
	sound.Looped = spec.Looped == true
	sound.SoundGroup = activeGroup
end

local HunterAudio = {Cues = CUES}

function HunterAudio.PlayWorldOneShot(cueName: string, position: Vector3, pitchJitter: number?): Sound?
	local spec = CUES[cueName]
	if not spec then return nil end
	local terrain = workspace.Terrain
	local att = Instance.new("Attachment")
	att.Name = "HunterSFX_" .. cueName
	att.WorldPosition = position
	att.Parent = terrain

	local sound = Instance.new("Sound")
	sound.Name = "Audio"
	configureSpatialSound(sound, spec, pitchJitter)
	sound.Looped = false
	sound.Parent = att
	sound.TimePosition = spec.TimePos or 0
	sound:Play()

	sound.Ended:Once(function()
		if att.Parent then att:Destroy() end
	end)
	Debris:AddItem(att, spec.Cleanup or 4)
	return sound
end

function HunterAudio.PlayAtPart(host: Instance?, cueName: string, pitchJitter: number?): Sound?
	local spec = CUES[cueName]
	if not spec or not host or not (host:IsA("BasePart") or host:IsA("Attachment")) or not host:IsDescendantOf(workspace) then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "HunterOneShot_" .. cueName
	configureSpatialSound(sound, spec, pitchJitter)
	sound.Looped = false
	sound.Parent = host
	sound.TimePosition = spec.TimePos or 0
	sound:Play()

	sound.Ended:Once(function()
		if sound.Parent then sound:Destroy() end
	end)
	Debris:AddItem(sound, spec.Cleanup or 4)
	return sound
end

function HunterAudio.StartLoop(host: Instance?, cueName: string): Sound?
	local spec = CUES[cueName]
	if not spec or not host or not (host:IsA("BasePart") or host:IsA("Attachment")) then
		return nil
	end
	local loopName = "HunterLoop_" .. cueName
	local existing = host:FindFirstChild(loopName)
	local sound: Sound
	if existing and existing:IsA("Sound") then
		sound = existing
	else
		sound = Instance.new("Sound")
		sound.Name = loopName
		configureSpatialSound(sound, spec)
		sound.Looped = true
		sound.Parent = host
	end
	if not sound.IsPlaying then
		sound.TimePosition = spec.TimePos or 0
		sound:Play()
	end
	return sound
end

function HunterAudio.StopLoop(host: Instance?, cueName: string)
	if not host then return end
	local existing = host:FindFirstChild("HunterLoop_" .. cueName)
	if existing and existing:IsA("Sound") then
		existing:Stop()
		existing:Destroy()
	end
end

function HunterAudio.PlayLocal(cueName: string): Sound?
	if isServer then return nil end
	local spec = CUES[cueName]
	if not spec then return nil end
	local now = os.clock()
	if now - (lastLocal[cueName] or -math.huge) < 0.18 then return nil end
	lastLocal[cueName] = now

	local localName = "Local_" .. cueName
	local existing = activeGroup:FindFirstChild(localName)
	local sound: Sound
	if existing and existing:IsA("Sound") then
		sound = existing
	else
		sound = Instance.new("Sound")
		sound.Name = localName
		sound.SoundId = spec.Id
		sound.Volume = spec.Volume
		sound.PlaybackSpeed = spec.Speed
		sound.Looped = false
		sound.SoundGroup = activeGroup
		sound.Parent = activeGroup
	end
	sound.TimePosition = spec.TimePos or 0
	sound:Play()
	return sound
end

if not isServer then
	task.spawn(function()
		pcall(function()
			local seen: {[string]: boolean} = {}
			local list: {Instance} = {}
			for _, spec in CUES do
				if not seen[spec.Id] then
					seen[spec.Id] = true
					local s = Instance.new("Sound")
					s.SoundId = spec.Id
					table.insert(list, s)
				end
			end
			ContentProvider:PreloadAsync(list)
			for _, inst in list do
				inst:Destroy()
			end
		end)
	end)
end

return HunterAudio
