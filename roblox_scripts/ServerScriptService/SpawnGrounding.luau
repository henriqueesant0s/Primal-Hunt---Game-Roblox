--!strict
-- Ajusta os marcadores ao terreno final, depois de instalar vegetação e colisores.
local Grounding = {}

function Grounding.resolve(map: Instance, ecosystem: Instance, apply: boolean): {string}
	local terrainRay = RaycastParams.new()
	terrainRay.FilterType = Enum.RaycastFilterType.Include
	terrainRay.FilterDescendantsInstances = {workspace.Terrain}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = {ecosystem, map}
	overlap.RespectCanCollide = true
	overlap.MaxParts = 1
	local results: {string} = {}
	local nodes = ecosystem:FindFirstChild("GameplayNodes")
	local playerPads: {Vector3} = {}

	for _, group in {"HunterSpawns", "MonsterSpawns", "PreySpawns"} do
		local folder = map:FindFirstChild(group)
		if not folder then continue end
		local radius = if group == "MonsterSpawns" then 5 elseif group == "HunterSpawns" then 2.5 else 3.5
		local markers = folder:GetChildren()
		table.sort(markers, function(a,b) return a.Name < b.Name end)
		local occupied: {Vector3} = {}
		local tiers: {[number]: number} = {}
		for _, marker in markers do
			if not marker:IsA("BasePart") then continue end
			local origin = marker.Position
			local tier = tonumber(marker:GetAttribute("PreyTier")) or 1
			tiers[tier] = (tiers[tier] or 0) + 1
			local function candidate(x: number, z: number): Vector3?
				local function floor(dx: number, dz: number): RaycastResult?
					return workspace:Raycast(Vector3.new(x+dx, 240, z+dz), Vector3.new(0,-360,0), terrainRay)
				end
				local hit = floor(0,0)
				if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.77 then return nil end
				for _, offset in {Vector2.xAxis, -Vector2.xAxis, Vector2.yAxis, -Vector2.yAxis} do
					local foot = floor(offset.X*radius, offset.Y*radius)
					if not foot or foot.Material == Enum.Material.Water or math.abs(foot.Position.Y-hit.Position.Y) > radius * 0.65 then return nil end
				end
				local pos = hit.Position + Vector3.yAxis*0.3
				if group == "PreySpawns" then
					for _, pad in playerPads do
						if (pos-pad).Magnitude < 75 then return nil end
					end
				end
				for _, other in occupied do
					if (Vector2.new(x-other.X,z-other.Z)).Magnitude < radius*2+3 then return nil end
				end
				local height = if group=="MonsterSpawns" then 30 else radius*2
				if #workspace:GetPartBoundsInBox(CFrame.new(pos+Vector3.yAxis*(height/2+0.5)),Vector3.new(radius*2,height,radius*2),overlap)>0 then return nil end
				return pos
			end
			local target = candidate(origin.X,origin.Z)
			for ring=1,24 do
				if target then break end
				local count=ring*6
				for i=0,count-1 do
					local angle=i*math.pi*2/count
					target=candidate(origin.X+6*ring*math.cos(angle),origin.Z+6*ring*math.sin(angle))
					if target then break end
				end
			end
			if not target then
				table.insert(results,"SEM PISO "..group.."/"..marker.Name)
				continue
			end
			table.insert(occupied,target)
			if group ~= "PreySpawns" then table.insert(playerPads,target) end
			if (origin-target).Magnitude > 0.15 then
				table.insert(results,string.format("%s/%s %.1f",group,marker.Name,(origin-target).Magnitude))
				if apply then
					local heading=marker.CFrame.LookVector
					marker.CFrame=CFrame.lookAt(target,target+Vector3.new(heading.X,0,heading.Z).Unit)
					if nodes then
						local index = string.match(marker.Name,"%d+$") or ""
						local name = if group=="MonsterSpawns" then "MonsterSpawnZone_"..index elseif group=="HunterSpawns" then "HunterSpawnZone_"..index else string.format("WildlifeHotspot_%s_%02d",if tier==2 then "Alpha" else "Tier1",tiers[tier])
						local zone = nodes:FindFirstChild(name)
						local height = if group=="PreySpawns" then (if tier==2 then 4 else 2.5) else 3
						if zone and zone:IsA("BasePart") then zone.Position=target+Vector3.yAxis*height end
					end
				end
			end
		end
	end
	return results
end
return Grounding