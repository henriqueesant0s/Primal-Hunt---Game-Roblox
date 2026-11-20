--!strict
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

type Rotor = {part: BasePart, rest: CFrame, period: number, offset: number, relay: Instance?, originalColor: Color3}
local rotors: {[Instance]: Rotor} = {}

local function track(obj: Instance)
	if not obj:IsA("BasePart") then return end
	local rest, period = obj:GetAttribute("ArtRestPose"), obj:GetAttribute("ArtPeriod")
	if typeof(rest)~="CFrame" or typeof(period)~="number" or math.abs(period)<.1 then return end
	rotors[obj] = {
		part=obj,
		rest=rest,
		period=period,
		offset=tonumber(obj:GetAttribute("ArtPhase")) or 0,
		relay=if obj:GetAttribute("ArtKind")=="Relay" then obj:FindFirstAncestor("PowerRelay") else nil,
		originalColor=obj.Color,
	}
end
for _, part in CollectionService:GetTagged("AbyssArtRotor") do track(part) end
CollectionService:GetInstanceAddedSignal("AbyssArtRotor"):Connect(track)
CollectionService:GetInstanceRemovedSignal("AbyssArtRotor"):Connect(function(part) rotors[part]=nil end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator<1/30 then return end
	accumulator %= 1/30
	local camera = workspace.CurrentCamera
	if not camera then return end
	local now = workspace:GetServerTimeNow()
	for _, rotor in rotors do
		local part,relay = rotor.part,rotor.relay
		local range = if relay then 740 else 155
		if (rotor.rest.Position-camera.CFrame.Position).Magnitude>range then continue end
		if relay and relay:GetAttribute("BeaconsActive")==false then
			part.Color=Color3.fromRGB(39,47,51)
			part.Material=Enum.Material.Metal
		else
			if relay then
				part.Color=rotor.originalColor
				part.Material=Enum.Material.Neon
			end
			local phase=((now+rotor.offset)%math.abs(rotor.period))/rotor.period
			part.CFrame=rotor.rest*CFrame.Angles(0,phase*math.pi*2,0)
		end
	end
end)