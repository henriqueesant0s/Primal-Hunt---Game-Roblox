--!strict
local Input = game:GetService("UserInputService")
local Deck = {}
Deck.Input = Instance.new("BindableEvent")
Deck.SmellCooldown = 4.5

local actions = {
	{"ClawSlash","Garra","M1"}, {"LeapSmash","Salto","1"}, {"FeralCharge","Carga","2"},
	{"AcidBreath","Ácido","3"}, {"Smell","Faro","Q"}, {"Eat","Devorar","E"},
	{"Evolve","Evoluir","V"}, {"Stealth","Furtivo","CTRL"}, {"Climb","Escalar","ESPAÇO"},
}
local holds: {[string]: boolean} = {Eat=true, Evolve=true, Stealth=true}
local amber = Color3.fromRGB(255,194,116)
local muted = Color3.fromRGB(198,205,199)
local ivory = Color3.fromRGB(244,238,224)
export type Slot = {setState: (string, number?, boolean?) -> ()}

local function label(parent: GuiObject, name: string, value: string, y: number, size: number, color: Color3, bold: boolean): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Text = value
	text.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", if bold then Enum.FontWeight.Bold else Enum.FontWeight.Regular)
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(7,y)
	text.Size = UDim2.new(1,-10,0,size+4)
	text.ZIndex = 14
	text.Parent = parent
	return text
end

function Deck.mount(parent: Frame, vitals: Frame, canvasScale: ()->number): {[string]: Slot}
	local tray = Instance.new("Frame")
	tray.Name = "MonsterAbilityTray"
	tray.BackgroundTransparency = 1
	tray.AnchorPoint = Vector2.new(1,1)
	tray.ZIndex = 13
	tray.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = tray
	local vitalsScale = Instance.new("UIScale")
	vitalsScale.Parent = vitals
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(4,4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	grid.Parent = tray

	local result: {[string]: Slot} = {}
	local keyLabels: {TextLabel} = {}
	local active: {[InputObject]: string} = {}
	local function endInput(input: InputObject)
		local id = active[input]
		if id then active[input] = nil; Deck.Input:Fire(id,false) end
	end
	local function clear()
		for input in active do endInput(input) end
	end
	local release = Input.InputEnded:Connect(endInput)
	local blur = Input.WindowFocusReleased:Connect(clear)
	parent:GetPropertyChangedSignal("Visible"):Connect(function() if not parent.Visible then clear() end end)
	for i, action in actions do
		local id,title,key = action[1],action[2],action[3]
		local button = Instance.new("TextButton")
		button.Name = id
		button.Text = ""
		button.LayoutOrder = i
		button.BackgroundColor3 = Color3.fromRGB(23,32,35)
		button.BackgroundTransparency = 0.12
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.ClipsDescendants = true
		button.ZIndex = 13
		button.Parent = tray
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0,4)
		corner.Parent = button
		keyLabels[i] = label(button,"Comando",key,3,11,amber,true)
		label(button,"Acao",title,18,15,ivory,true)
		local status = label(button,"Estado","Pronta",37,11,muted,false)
		local bar = Instance.new("Frame")
		bar.Name = "Progresso"
		bar.AnchorPoint = Vector2.new(0,1)
		bar.Position = UDim2.fromScale(0,1)
		bar.Size = UDim2.new(1,0,0,3)
		bar.BackgroundColor3 = amber
		bar.BorderSizePixel = 0
		bar.ZIndex = 14
		bar.Parent = button
		result[id] = {setState=function(value,progress,ready)
			status.Text = value
			bar.BackgroundColor3 = if ready==false then muted else amber
			bar.Size = UDim2.new(math.clamp(progress or 1,0,1),0,0,3)
		end}
		button.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if not parent.Visible or active[input] then return end
			active[input] = id
			Deck.Input:Fire(id,true)
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then endInput(input) end
		end)
	end
	local function layout()
		local width = parent.AbsoluteSize.X
		if width < 1 then return end
		local touch = Input.PreferredInput == Enum.PreferredInput.Touch
		local compact = touch or width < 1050
		local columns = if compact then 5 else 9
		local w = math.clamp(math.floor((width-24-(columns-1)*4)/columns),50,78)
		local h = if compact then 56 else 66
		local rows = if compact then 2 else 1
		local inset = if touch then 90 else 14
		local inherited = math.max(canvasScale(),0.1)
		scale.Scale = 1/inherited
		vitalsScale.Scale = (if width < 650 then 0.75 else 0.94)/inherited
		grid.FillDirectionMaxCells = columns
		grid.CellSize = UDim2.fromOffset(w,h)
		tray.Size = UDim2.fromOffset(columns*w+(columns-1)*4,rows*h+(rows-1)*4)
		tray.Position = UDim2.new(1,-12/inherited,1,-inset/inherited)
		local metricsBottom = if width < 650 then inset+rows*(h+4)+8 elseif touch then inset else 18
		vitals.Position = UDim2.new(0,12/inherited,1,-metricsBottom/inherited)
		for i, t in keyLabels do
			t.Text = if touch then (if holds[actions[i][1]] then "SEGURE" else "TOQUE") else actions[i][3]
		end
	end
	local preferred = Input:GetPropertyChangedSignal("PreferredInput"):Connect(layout)
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	tray.Destroying:Once(function() clear(); release:Disconnect(); blur:Disconnect(); preferred:Disconnect() end)
	layout()
	return result
end
return Deck