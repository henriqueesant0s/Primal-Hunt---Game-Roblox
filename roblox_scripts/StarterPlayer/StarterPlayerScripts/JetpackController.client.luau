--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local gameRemotes = remotes:WaitForChild("GameRemotes")
local actionEvent = remotes:WaitForChild("HunterRemotes"):WaitForChild("JetpackAction") :: RemoteEvent
local HUNTERS: {[string]: boolean} = {Assault = true, Medic = true, Trapper = true, Support = true}
local DOUBLE_TAP = 0.28
local axes: {[Enum.KeyCode]: Vector2} = {
	[Enum.KeyCode.W] = Vector2.new(0, 1), [Enum.KeyCode.S] = Vector2.new(0, -1),
	[Enum.KeyCode.D] = Vector2.new(1, 0), [Enum.KeyCode.A] = Vector2.new(-1, 0),
}
local taps: {[Enum.KeyCode]: number} = {}
local holdingJump = false
local sentThrust = false

local function hunter(): Humanoid?
	local body = player.Character
	if not body or gameRemotes:GetAttribute("MatchState") ~= "ActiveHunt" then return nil end
	local role = body:GetAttribute("Role")
	if typeof(role) ~= "string" or not HUNTERS[role] or body:GetAttribute("IsDowned") or body:GetAttribute("IsDead") then return nil end
	return body:FindFirstChildOfClass("Humanoid")
end

local function stop()
	if sentThrust then actionEvent:FireServer("StopThrust") end
	sentThrust = false
end

local function reset()
	holdingJump = false
	stop()
	table.clear(taps)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or UserInputService:GetFocusedTextBox() then return end
	local humanoid = hunter()
	if not humanoid then return end
	local key = input.KeyCode
	if key == Enum.KeyCode.Space then holdingJump = true return end
	local axis = axes[key]
	if not axis then return end
	local now = os.clock()
	local previous = taps[key]
	taps[key] = now
	if not previous or now - previous > DOUBLE_TAP or not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or humanoid.FloorMaterial ~= Enum.Material.Air then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local right = camera.CFrame.RightVector
	local flatRight = Vector3.new(right.X, 0, right.Z)
	if flatRight.Magnitude < 0.001 then return end
	flatRight = flatRight.Unit
	local forward = Vector3.yAxis:Cross(flatRight)
	taps[key] = nil
	actionEvent:FireServer("Dodge", flatRight * axis.X + forward * axis.Y)
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Space then
		holdingJump = false
		stop()
	end
end)

RunService.Heartbeat:Connect(function()
	if not holdingJump then return end
	local humanoid = hunter()
	if not humanoid or UserInputService:GetFocusedTextBox() then reset() return end
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	if airborne and not sentThrust then
		sentThrust = true
		actionEvent:FireServer("StartThrust")
	elseif not airborne then
		stop()
	end
end)

player.CharacterRemoving:Connect(reset)
UserInputService.WindowFocusReleased:Connect(reset)
UserInputService.TextBoxFocused:Connect(reset)
