--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Damage = require(script.Parent.DamageService)
local Prey = require(script.Parent.PreyManager)
local remotes = RS.Remotes.MonsterRemotes
local gameEvents = RS.Remotes.GameRemotes
local relay = workspace.Map.PowerRelay
local hunters: {[string]: boolean} = {Assault=true, Medic=true, Trapper=true, Support=true}
local stats = {{1500,800},{2600,1500},{4200,2500}}
local NEST_EVOLVE_RADIUS = 34
local cooldown: {[string]: number} = {ClawSlash=0.42,LeapSmash=6,FeralCharge=8,AcidBreath=9,Climb=1.2}
local costs: {[string]: number} = {ClawSlash=0,LeapSmash=22,FeralCharge=30,AcidBreath=0,Climb=14}
local ROAR_SFX = "rbxassetid://9113980319"
local CLAW_SFX = "rbxassetid://9119073323"
local LEAP_LAUNCH_SFX = "rbxassetid://9126009951"
local SLAM_IMPACT_SFX = "rbxassetid://9114362401"
local CHARGE_ROAR_SFX = "rbxassetid://9113980644"
local ACID_HISS_SFX = "rbxassetid://9116395089"
local EVOLVE_SURGE_SFX = "rbxassetid://9126102843"
local EVOLVE_FINISH_SFX = "rbxassetid://118218169117498"
local rng = Random.new()
type Session = {player: Player, body: Model, root: BasePart, humanoid: Humanoid, speed: number,
	deadlines: {[string]: number}, action: string?, ownsPhysics: boolean, oldArmor: number?, oldAnchor: boolean,
	attachment: Attachment?, motor: LinearVelocity?, comboStep: number, lastComboAt: number, cocoonDome: Part?}
local sessions: {[Player]: Session} = {}
local lastSkill: {[Player]: number} = {}
local lastEvolve: {[Player]: number} = {}
local function combat(): boolean
	local state=gameEvents:GetAttribute("MatchState")
	return gameEvents:GetAttribute("RoundClosed") ~= true and (state == "MonsterHeadStart" or state == "ActiveHunt")
end
local function valid(s: Session): boolean
	return combat() and s.player.Character==s.body and s.body.Parent~=nil and s.root.Parent==s.body
		and s.body:GetAttribute("Role")=="Monster" and not s.body:GetAttribute("IsDead") and s.humanoid.Health>0
end
local function finish(s: Session)
	if s.cocoonDome then s.cocoonDome:Destroy() s.cocoonDome=nil end
	if s.motor then s.motor:Destroy() s.motor=nil end
	if s.attachment then s.attachment:Destroy() s.attachment=nil end
	if s.oldArmor~=nil then
		if s.body:GetAttribute("Role")=="Monster" then
			s.body:SetAttribute("Armor",math.clamp(s.oldArmor,0,s.body:GetAttribute("MaxArmor")))
		end
		s.oldArmor=nil
		if s.root.Parent and not s.body:GetAttribute("IsDead") then s.root.Anchored=s.oldAnchor end
		s.body:SetAttribute("IsEvolving",false)
	end
	if s.ownsPhysics then
		if s.root.Parent and s.root:CanSetNetworkOwnership() then s.root:SetNetworkOwnershipAuto() end
		s.ownsPhysics=false
	end
	s.action=nil
	s.body:SetAttribute("MonsterAction",nil)
end
local function remove(p: Player)
	local s=sessions[p]
	if s then
		finish(s)
		if s.body:GetAttribute("IsStealth") then s.humanoid.WalkSpeed=s.speed end
		s.body:SetAttribute("IsStealth",nil)
		sessions[p]=nil
	end
end
local function session(p: Player): Session?
	local existing=sessions[p]
	if existing and valid(existing) then return existing end
	if existing then remove(p) end
	local body=p.Character
	if not body or body:GetAttribute("Role")~="Monster" or body:GetAttribute("IsDead") or not combat() then return nil end
	local root=body:FindFirstChild("HumanoidRootPart")
	local h=body:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not h or h.Health<=0 then return nil end
	local s: Session={player=p,body=body,root=root,humanoid=h,speed=h.WalkSpeed,deadlines={},action=nil,
		ownsPhysics=false,oldArmor=nil,oldAnchor=false,attachment=nil,motor=nil,comboStep=0,lastComboAt=0,cocoonDome=nil}
	sessions[p]=s
	return s
end
local function playMonsterSFX(parent: BasePart, soundId: string, volume: number, speed: number, maxDist: number)
	if not parent.Parent then return end
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 16
	s.RollOffMaxDistance = maxDist
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 6)
end
local function pulse(position: Vector3, diameter: number, color: Color3)
	local orb=Instance.new("Part")
	orb.Name="MonsterImpact"
	orb.Anchored=true
	orb.CanCollide,orb.CanTouch,orb.CanQuery=false,false,false
	orb.Material,orb.Color=Enum.Material.Neon,color
	orb.Shape=Enum.PartType.Ball
	orb.Transparency=.74
	orb.Size=Vector3.one
	orb.Position=position
	orb.Parent=workspace
	TweenService:Create(orb,TweenInfo.new(.32),{Size=Vector3.one*diameter,Transparency=1}):Play()
	Debris:AddItem(orb,.36)
	local ring = Instance.new("Part")
	ring.Name = "MonsterShockRing"
	ring.Anchored = true
	ring.CanCollide, ring.CanTouch, ring.CanQuery = false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.25, 2, 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, diameter * 1.15, diameter * 1.15),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.40)
end
local function slashArcVFX(root: BasePart, color: Color3, scale: number)
	local arc = Instance.new("Part")
	arc.Name = "MonsterClawArc"
	arc.Anchored = true
	arc.CanCollide, arc.CanTouch, arc.CanQuery = false, false, false
	arc.Material = Enum.Material.Neon
	arc.Color = color
	arc.Transparency = 0.22
	arc.Size = Vector3.new(5.8 * scale, 0.32, 3.2 * scale)
	local roll = if math.random() > 0.5 then math.rad(28) else math.rad(-28)
	local startCF = root.CFrame * CFrame.new(0, 1.4 * scale, -4.5 * scale) * CFrame.Angles(0, math.rad(25), roll)
	arc.CFrame = startCF
	arc.Parent = workspace
	TweenService:Create(arc, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = startCF * CFrame.Angles(0, math.rad(-50), 0) * CFrame.new(0, 0, -2.5 * scale),
		Transparency = 1,
	}):Play()
	Debris:AddItem(arc, 0.26)
end
local function rays(body: Model): RaycastParams
	local params=RaycastParams.new()
	params.FilterDescendantsInstances={body}
	return params
end
local function victim(part: BasePart): Model?
	local parent: Instance?=part
	while parent and parent~=workspace do
		if parent:IsA("Model") and (parent==relay or parent.Parent==workspace.ActivePrey or
			(hunters[parent:GetAttribute("Role")] and Players:GetPlayerFromCharacter(parent))) then return parent end
		parent=parent.Parent
	end
	return nil
end
local function strike(s: Session, center: Vector3, radius: number, amount: number, hit: {[Model]: boolean}, facing: Vector3?, cone: number, push: boolean)
	local overlap=OverlapParams.new()
	overlap.FilterDescendantsInstances={s.body}
	for _,part in workspace:GetPartBoundsInRadius(center,radius,overlap) do
		local model=victim(part)
		if not model or hit[model] then continue end
		local core=model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if not core or not core:IsA("BasePart") then continue end
		local delta=core.Position-center
		if delta.Magnitude>radius or (facing and delta.Magnitude>.05 and facing:Dot(delta.Unit)<cone) then continue end
		local wall=workspace:Raycast(center,delta,rays(s.body))
		if wall and not wall.Instance:IsDescendantOf(model) then continue end
		hit[model]=true
		if model==relay then
			if s.body:GetAttribute("Stage")==3 and gameEvents:GetAttribute("MatchState")=="ActiveHunt" then
				relay:SetAttribute("RelayHealth",math.max(0,relay:GetAttribute("RelayHealth")-amount))
			end
		elseif model.Parent==workspace.ActivePrey then Prey.Damage(model,amount)
		else
			Damage.ApplyDamage(s.player,model,amount)
			if push and not core.Anchored and not model:GetAttribute("IsDowned") then
				local attachment=Instance.new("Attachment")
				attachment.Parent=core
				local force=Instance.new("LinearVelocity")
				force.Attachment0=attachment
				force.MaxForce=core.AssemblyMass*1600
				force.VectorVelocity=s.root.CFrame.LookVector*52+Vector3.yAxis*12
				force.Parent=attachment
				Debris:AddItem(attachment,.18)
			end
		end
	end
end
local function own(s: Session)
	if s.root:CanSetNetworkOwnership() then s.root:SetNetworkOwner(nil) s.ownsPhysics=true end
end
local function active(s: Session, action: string): boolean
	return sessions[s.player]==s and s.action==action and valid(s)
end
local function driveHorizontal(s: Session, velocity: Vector3)
	local a=Instance.new("Attachment")
	a.Parent=s.root
	local motor=Instance.new("LinearVelocity")
	motor.Attachment0=a
	motor.VelocityConstraintMode=Enum.VelocityConstraintMode.Plane
	motor.PrimaryTangentAxis=Vector3.xAxis
	motor.SecondaryTangentAxis=Vector3.zAxis
	motor.PlaneVelocity=Vector2.new(velocity.X,velocity.Z)
	motor.MaxForce=s.root.AssemblyMass*1800
	motor.Parent=a
	s.attachment,s.motor=a,motor
end
local function leap(s: Session, target: Vector3)
	own(s)
	playMonsterSFX(s.root, LEAP_LAUNCH_SFX, 0.85, 0.72, 220)
	local diff=target-s.root.Position
	local flat=Vector3.new(diff.X,0,diff.Z)
	if flat.Magnitude>55 then flat=flat.Unit*55 end
	local gravity=math.max(workspace.Gravity,1)
	local duration=.88
	local y=gravity*duration*.5+math.clamp(diff.Y,-12,12)/duration
	s.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	driveHorizontal(s,flat/duration)
	s.root.AssemblyLinearVelocity=flat/duration+Vector3.yAxis*y
	local start=os.clock()
	while active(s,"LeapSmash") and os.clock()-start<3 do
		task.wait(.035)
		if not active(s,"LeapSmash") then return end
		if os.clock()-start>.18 and s.root.AssemblyLinearVelocity.Y<=1 then
			local length=s.humanoid.HipHeight+s.root.Size.Y/2+.85
			local floor=workspace:Raycast(s.root.Position,-Vector3.yAxis*math.max(3.5,length),rays(s.body))
			if floor and floor.Normal.Y>.45 then
				strike(s,s.root.Position,15,55,{},nil,0,false)
				pulse(floor.Position,30,Color3.fromRGB(255,154,74))
				playMonsterSFX(s.root, SLAM_IMPACT_SFX, 1.0, 0.78, 320)
				break
			end
		end
	end
end
local function charge(s: Session)
	own(s)
	playMonsterSFX(s.root, CHARGE_ROAR_SFX, 0.92, 0.85, 280)
	local forward=s.root.CFrame.LookVector
	local dir=Vector3.new(forward.X,0,forward.Z).Unit
	driveHorizontal(s,dir*65)
	local hit: {[Model]: boolean}={}
	local start=os.clock()
	local tick = 0
	while active(s,"FeralCharge") and os.clock()-start<.68 do
		strike(s,s.root.Position,8,45,hit,dir,-.1,true)
		tick += 1
		if tick % 3 == 0 then
			pulse(s.root.Position - Vector3.yAxis * 2.5, 11, Color3.fromRGB(255, 108, 28))
		end
		local obstacle=workspace:Raycast(s.root.Position,dir*4,rays(s.body))
		if obstacle and obstacle.Instance.CanCollide and not victim(obstacle.Instance) then break end
		task.wait(.045)
	end
	if s.root.Parent then
		s.root.AssemblyLinearVelocity=Vector3.yAxis*s.root.AssemblyLinearVelocity.Y
	end
end
local function acid(s: Session)
	playMonsterSFX(s.root, ACID_HISS_SFX, 0.82, 0.82, 200)
	for _=1,8 do
		if not active(s,"AcidBreath") then break end
		local dir=s.root.CFrame.LookVector
		strike(s,s.root.Position,29,9,{},dir,math.cos(math.rad(34)),false)
		local endHit=workspace:Raycast(s.root.Position,dir*23,rays(s.body))
		local reach=if endHit then endHit.Distance else 23
		pulse(s.root.Position+dir*reach*.68,math.min(12,reach*.45),Color3.fromRGB(139,248,68))
		task.wait(.25)
	end
end
local function findNearestNest(pos: Vector3): (Vector3?, number)
	local bestPos: Vector3? = nil
	local bestDist = math.huge
	local eco = workspace:FindFirstChild("HuntingMap_Ecosystem")
	if eco then
		local gn = eco:FindFirstChild("GameplayNodes")
		if gn then
			for _, n in ipairs(gn:GetChildren()) do
				if n:IsA("BasePart") and (n:GetAttribute("NodeType") == "NestLocation" or string.find(n.Name, "Nest")) then
					local d = (n.Position - pos).Magnitude
					if d < bestDist then bestDist, bestPos = d, n.Position end
				end
			end
		end
		local props = eco:FindFirstChild("HorrorHuntProps_V3")
		if props and bestPos == nil then
			for _, p in ipairs(props:GetChildren()) do
				if p:GetAttribute("EvolutionNest") == true then
					local nPos = p:GetPivot().Position
					local d = (nPos - pos).Magnitude
					if d < bestDist then bestDist, bestPos = d, nPos end
				end
			end
		end
	end
	return bestPos, bestDist
end
local function clawSlash(s: Session)
	local now = os.clock()
	if now - s.lastComboAt > 1.65 then
		s.comboStep = 0
	end
	s.comboStep = (s.comboStep % 3) + 1
	s.lastComboAt = now
	local combo = s.comboStep
	s.body:SetAttribute("SlashCombo", combo)

	local stage = tonumber(s.body:GetAttribute("Stage")) or 1
	local scale = math.max(1, s.body:GetScale())
	local forward = s.root.CFrame.LookVector
	playMonsterSFX(s.root, CLAW_SFX, 0.82, 0.72 + combo * 0.06 + rng:NextNumber(-0.04, 0.04), 170)

	if combo == 1 then
		local dmg = 28 + (stage - 1) * 10
		slashArcVFX(s.root, Color3.fromRGB(255, 92, 28), scale * 1.15)
		strike(s, s.root.Position + forward * (6.0 * scale), 15.0 * scale, dmg, {}, forward, math.cos(math.rad(68)), false)
		task.wait(0.24)
	elseif combo == 2 then
		local dmg = 34 + (stage - 1) * 12
		if rng:NextNumber() < 0.45 then playMonsterSFX(s.root, ROAR_SFX, 0.55, 0.92, 190) end
		slashArcVFX(s.root, Color3.fromRGB(255, 118, 36), scale * 1.25)
		strike(s, s.root.Position + forward * (6.4 * scale), 16.0 * scale, dmg, {}, forward, math.cos(math.rad(72)), false)
		task.wait(0.26)
	else
		local dmg = 46 + (stage - 1) * 16
		playMonsterSFX(s.root, ROAR_SFX, 0.78, 0.78, 220)
		playMonsterSFX(s.root, SLAM_IMPACT_SFX, 0.92, 0.84, 240)
		local slamCenter = s.root.Position + forward * (6.8 * scale)
		pulse(slamCenter - Vector3.yAxis * 2.0, 22 * scale, Color3.fromRGB(255, 68, 24))
		strike(s, slamCenter, 18.0 * scale, dmg, {}, nil, -1, true)
		task.wait(0.32)
	end
end
local function finite(v: Vector3): boolean
	return v.X==v.X and v.Y==v.Y and v.Z==v.Z and v.Magnitude<1e7
end
remotes.UseMonsterSkill.OnServerEvent:Connect(function(p: Player, name: any, target: any)
	if typeof(name)~="string" or typeof(target)~="Vector3" or not finite(target) then return end
	if name=="CancelEat" then Prey.CancelMeal(p) return end
	local now=os.clock()
	local s=session(p)
	if not s then return end
	if name=="StealthOff" then
		if s.body:GetAttribute("IsStealth") then s.body:SetAttribute("IsStealth",false) s.humanoid.WalkSpeed=s.speed end
		return
	end
	if now-(lastSkill[p] or -math.huge)<.10 then return end
	lastSkill[p]=now
	if s.action or s.body:GetAttribute("IsEating") or s.root.Anchored then return end
	if name=="StealthOn" then
		if not s.body:GetAttribute("IsStealth") then
			s.speed=s.humanoid.WalkSpeed
			s.body:SetAttribute("IsStealth",true)
			s.humanoid.WalkSpeed=math.min(s.speed,7)
		end
		return
	end
	if not cooldown[name] or now<(s.deadlines[name] or 0) or s.body:GetAttribute("IsStealth") then return end
	local stamina=s.body:GetAttribute("Stamina")
	if typeof(stamina)~="number" or stamina<costs[name] then return end
	if name=="LeapSmash" and (s.humanoid.FloorMaterial==Enum.Material.Air or (target-s.root.Position).Magnitude>500) then return end
	local climbWallHit: RaycastResult? = nil
	local isTaggedClimbable = false
	if name=="Climb" then
		local rp = rays(s.body)
		local look = s.root.CFrame.LookVector
		local right = s.root.CFrame.RightVector
		for _, dir in ipairs({ look, (look + right * 0.38).Unit, (look - right * 0.38).Unit }) do
			local hit = workspace:Raycast(s.root.Position, dir * 9.0, rp)
			if hit and hit.Instance.CanCollide and not victim(hit.Instance) then
				local tagged = CollectionService:HasTag(hit.Instance, "Climbable") or hit.Instance:GetAttribute("IsClimbable") == true
				if tagged or math.abs(hit.Normal.Y) <= 0.42 then
					climbWallHit = hit
					isTaggedClimbable = tagged
					break
				end
			end
		end
		if not climbWallHit then return end
	end
	local actualCooldown = if name == "Climb" and isTaggedClimbable then 0.68 else cooldown[name]
	local actualCost = if name == "Climb" and isTaggedClimbable then 9 else costs[name]
	if stamina < actualCost then return end
	s.deadlines[name]=now+actualCooldown
	s.body:SetAttribute("Stamina",stamina-actualCost)
	s.action=name
	s.body:SetAttribute("MonsterAction",name)
	local ok,err=pcall(function()
		if name=="LeapSmash" then leap(s,target)
		elseif name=="FeralCharge" then charge(s)
		elseif name=="AcidBreath" then acid(s)
		elseif name=="ClawSlash" then clawSlash(s)
		else
			own(s)
			local intoWall = if climbWallHit then (-climbWallHit.Normal * 9) else (s.root.CFrame.LookVector * 8)
			local upSpeed = if isTaggedClimbable then 54 else 48
			s.root.AssemblyLinearVelocity = Vector3.yAxis * upSpeed + Vector3.new(intoWall.X, 0, intoWall.Z)
			task.wait(.26)
			-- Brief wall-cling stabilization on Climbable cliffs & ancient monoliths so Monster can perch or chain jumps
			if isTaggedClimbable and active(s, "Climb") and s.humanoid.MoveDirection.Magnitude < 0.25 then
				local clingAtt = Instance.new("Attachment")
				clingAtt.Parent = s.root
				local clingLV = Instance.new("LinearVelocity")
				clingLV.Attachment0 = clingAtt
				clingLV.MaxForce = s.root.AssemblyMass * 2200
				clingLV.VectorVelocity = Vector3.new(intoWall.X * 0.25, 1.2, intoWall.Z * 0.25)
				clingLV.Parent = clingAtt
				s.attachment, s.motor = clingAtt, clingLV
				local clingStart = os.clock()
				while active(s, "Climb") and os.clock() - clingStart < 0.65 and s.humanoid.MoveDirection.Magnitude < 0.35 do
					task.wait(0.05)
				end
			end
		end
	end)
	if not ok then warn("MonsterServer",name,err) end
	if sessions[p]==s and s.action==name then finish(s) end
end)
remotes.EvolveStage.OnServerEvent:Connect(function(p: Player, start: any)
	if typeof(start)~="boolean" then return end
	local s=session(p)
	if not s then return end
	if not start then
		if s.action=="Evolve" and os.clock()<s.deadlines.Evolve then finish(s) end
		return
	end
	local now=os.clock()
	if now-(lastEvolve[p] or -math.huge)<.3 then return end
	lastEvolve[p]=now
	local stage=s.body:GetAttribute("Stage")
	if (stage~=1 and stage~=2) or s.action or s.root.Anchored or s.body:GetAttribute("IsEating")
		or s.body:GetAttribute("EvolutionEnergy")<100 then return end
	local nestPos, nestDist = findNearestNest(s.root.Position)
	if not nestPos or nestDist > NEST_EVOLVE_RADIUS then
		gameEvents.UpdateUI:FireClient(p, "MonsterNestRequired", { nestPos = nestPos or Vector3.zero, dist = math.round(nestDist) })
		playMonsterSFX(s.root, "rbxassetid://9114787480", 0.72, 0.78, 180)
		return
	end
	s.action="Evolve"
	s.body:SetAttribute("MonsterAction","Evolve")
	s.oldArmor=s.body:GetAttribute("Armor")
	s.oldAnchor=s.root.Anchored
	s.root.Anchored=true
	s.body:SetAttribute("Armor",0)
	s.body:SetAttribute("IsEvolving",true)
	-- O prazo identifica esta tentativa, inclusive se o jogador cancelar e reiniciar.
	s.deadlines.Evolve=now+5
	local deadline=s.deadlines.Evolve
	local dome = Instance.new("Part")
	dome.Name = "AbyssalCocoonDome"
	dome.Shape = Enum.PartType.Ball
	dome.Anchored = true
	dome.CanCollide, dome.CanQuery, dome.CanTouch = false, false, false
	dome.Material = Enum.Material.ForceField
	dome.Color = Color3.fromRGB(255, 86, 22)
	dome.Transparency = 0.25
	dome.Size = Vector3.one * 15
	dome.Position = s.root.Position
	dome.Parent = workspace
	s.cocoonDome = dome
	TweenService:Create(dome, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Size = Vector3.one * 24,
		Color = Color3.fromRGB(255, 208, 68),
	}):Play()
	gameEvents.UpdateUI:FireAllClients("MonsterEvolutionStarted", {
		monsterUserId = p.UserId,
		monsterPos = s.root.Position,
		nestPos = nestPos,
		targetStage = stage + 1,
		duration = 5,
	})
	playMonsterSFX(s.root, EVOLVE_SURGE_SFX, 0.95, 0.85, 360)
	task.delay(5,function()
		if not active(s,"Evolve") or s.deadlines.Evolve~=deadline then return end
		local nextStage=stage+1
		local nextStats=stats[nextStage]
		local health=s.body:GetAttribute("CustomHealth")
		local maximum=s.body:GetAttribute("MaxCustomHealth")
		s.body:ScaleTo(if nextStage==2 then 1.35 else 1.75)
		s.body:SetAttribute("Stage",nextStage)
		s.body:SetAttribute("MaxCustomHealth",nextStats[1])
		s.body:SetAttribute("CustomHealth",math.min(nextStats[1],health+nextStats[1]-maximum))
		s.body:SetAttribute("MaxArmor",nextStats[2])
		s.oldArmor = nextStats[2]
		s.body:SetAttribute("EvolutionEnergy",0)
		finish(s)
		playMonsterSFX(s.root, EVOLVE_FINISH_SFX, 1.0, 0.92, 480)
		pulse(s.root.Position, 44, Color3.fromRGB(255, 196, 68))
		gameEvents.UpdateUI:FireAllClients("MonsterStageChanged", {stage=nextStage, monsterUserId=p.UserId})
		gameEvents.UpdateUI:FireAllClients("MonsterEvolutionCompleted", {
			newStage = nextStage,
			monsterUserId = p.UserId,
			monsterPos = s.root.Position,
		})
	end)
end)
Players.PlayerRemoving:Connect(function(p) remove(p) lastSkill[p],lastEvolve[p]=nil,nil end)
Prey.Start()
task.spawn(function()
	local previous=os.clock()
	while true do
		task.wait(.25)
		local now=os.clock()
		for _, p in ipairs(Players:GetPlayers()) do
			session(p)
		end
		for p,s in sessions do
			if not valid(s) then remove(p)
			else
				local np, nd = findNearestNest(s.root.Position)
				s.body:SetAttribute("NearEvolutionNest", np ~= nil and nd <= NEST_EVOLVE_RADIUS)
				s.body:SetAttribute("NearestNestPos", np or Vector3.zero)
				s.body:SetAttribute("NearestNestDist", if nd < math.huge then math.round(nd) else 0)
				if not s.action then
					local value=s.body:GetAttribute("Stamina")
					if typeof(value)=="number" and value<100 then s.body:SetAttribute("Stamina",math.min(100,value+(now-previous)*10)) end
				end
			end
		end
		previous=now
	end
end)
