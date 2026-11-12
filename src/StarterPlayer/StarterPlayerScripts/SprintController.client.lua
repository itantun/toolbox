--!nonstrict
-- ============================================================================
-- SprintController (v14) — бег по Shift (ПК) и кнопка «БЕГ» (телефон)
-- Скорость выставляет СЕРВЕР (ServerMain п. 3c): клиент только сообщает «бегу / не бегу».
-- Бег бесплатный (энергия не расходуется): так удобнее ходить между шахтой и рынком.
-- ============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if player:GetAttribute("SprintControllerActive") then return end
player:SetAttribute("SprintControllerActive", true)

local SprintRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Sprint")
local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local sprinting = false
local shiftHeld = false
local touchToggle = false
local BASE_FOV = nil

local function setSprint(on)
	if on == sprinting then return end
	sprinting = on
	SprintRemote:FireServer(on)
	local cam = workspace.CurrentCamera
	if cam then
		BASE_FOV = BASE_FOV or cam.FieldOfView
		TweenService:Create(cam, TweenInfo.new(0.25), { FieldOfView = on and (BASE_FOV + 8) or BASE_FOV }):Play()
	end
end

local function recompute()
	setSprint(shiftHeld or touchToggle)
end

-- ПК: Shift (держать)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftHeld = true
		recompute()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftHeld = false
		recompute()
	end
end)

-- Телефон: кнопка-переключатель внизу справа
if UserInputService.TouchEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "SprintButtonGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton", gui)
	btn.Size = UDim2.fromOffset(84, 84)
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -150, 1, -26)
	btn.BackgroundColor3 = Color3.fromRGB(18, 28, 60)
	btn.BackgroundTransparency = 0.12
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 20
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "SPRINT"
	btn.AutoButtonColor = false
	Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke", btn)
	st.Color = Color3.fromRGB(70, 200, 255)
	st.Thickness = 3
	local ts = Instance.new("UIStroke") -- обводка текста
	ts.Thickness = 2
	ts.Color = Color3.fromRGB(8, 14, 34)
	ts.Parent = btn

	btn.Activated:Connect(function()
		touchToggle = not touchToggle
		btn.BackgroundColor3 = touchToggle and Color3.fromRGB(40, 170, 90) or Color3.fromRGB(18, 28, 60)
		st.Color = touchToggle and Color3.fromRGB(90, 255, 150) or Color3.fromRGB(70, 200, 255)
		recompute()
	end)
end

-- Сброс при смерти / возрождении
local function onCharacter(char)
	shiftHeld = false
	touchToggle = false
	sprinting = false
	BASE_FOV = nil
	local cam = workspace.CurrentCamera
	if cam then BASE_FOV = cam.FieldOfView end
	local gui = player.PlayerGui:FindFirstChild("SprintButtonGui")
	local b = gui and gui:FindFirstChildOfClass("TextButton")
	if b then
		b.BackgroundColor3 = Color3.fromRGB(18, 28, 60)
	end
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then onCharacter(player.Character) end

-- Если окно потеряло фокус с зажатым Shift — отпустить бег
UserInputService.WindowFocusReleased:Connect(function()
	shiftHeld = false
	recompute()
end)

print("✅ [SprintController] Shift = sprint (x" .. tostring(GameConfig.SPRINT.SprintMultiplier) .. ")")
