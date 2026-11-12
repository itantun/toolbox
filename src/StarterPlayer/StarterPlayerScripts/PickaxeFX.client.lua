--!strict
-- ============================================================================
-- ⛏️ КЛИЕНТ: PickaxeFX (StarterPlayerScripts.PickaxeFX)
-- v52: «живые» эффекты кирки поверх анимации взмаха ToolAnimator.
--   • Взмах: шлейф (Trail) между краями лезвия включается на долю секунды + тихий свист.
--   • Удар: залп искр цвета руды из готового излучателя (:Emit — новые объекты не
--     создаются), лёгкая тряска камеры и звук удара.
--   • Топовые кирки (FxEpic): пульсирующее свечение кристалла и PointLight.
-- Покадровых циклов нет: бесконечные твины для пульсации и короткие task.delay.
-- Настройки — GameConfig.PICKAXE_SWING_FX.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
if not player then
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local UIKit = require(Modules:WaitForChild("UIKit"))
local ClientBus = require(Modules:WaitForChild("ClientBus"))
local ToolAnimator = require(Modules:WaitForChild("ToolAnimator"))

local SWING = GameConfig.PICKAXE_SWING_FX
local rng = Random.new()

local TrailTokens: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function getShownPickaxe(char: Model): Model?
	local pick = char:FindFirstChild("VisualPickaxe")
	if pick and pick:IsA("Model") and pick:GetAttribute("Shown") ~= false then
		return pick
	end
	return nil
end

-- Чужие эффекты проигрываем только рядом с камерой
local function inRange(char: Model): boolean
	local cam = Workspace.CurrentCamera
	local root = char:FindFirstChild("HumanoidRootPart")
	if not cam or not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - cam.CFrame.Position).Magnitude <= SWING.FxRange
end

-- Взмах: включаем шлейф между краями лезвия
ToolAnimator.OnSwingStart = function(char: Model, _isCrit: boolean)
	local isLocal = char == player.Character
	if not isLocal and not inRange(char) then
		return
	end
	local pick = getShownPickaxe(char)
	if not pick then
		return
	end
	local trail = pick:FindFirstChild("SwingTrail", true)
	if trail and trail:IsA("Trail") then
		local token = (TrailTokens[trail] or 0) + 1
		TrailTokens[trail] = token
		trail.Enabled = true
		task.delay(SWING.TrailSeconds, function()
			if TrailTokens[trail] == token and trail.Parent then
				trail.Enabled = false
			end
		end)
	end
	if isLocal then
		UIKit.PlaySfx("Swing")
	end
end

-- Короткая тряска камеры локального игрока (три толчка и возврат)
local function shakeCamera()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local k = SWING.CameraShake
	task.spawn(function()
		for _ = 1, 3 do
			TweenService:Create(hum, TweenInfo.new(0.03, Enum.EasingStyle.Linear), {
				CameraOffset = Vector3.new(rng:NextNumber(-k, k), rng:NextNumber(-k, k), 0),
			}):Play()
			task.wait(0.035)
		end
		TweenService:Create(hum, TweenInfo.new(0.08), { CameraOffset = Vector3.zero }):Play()
	end)
end

-- Удар: искры цвета руды из готового излучателя
ToolAnimator.OnImpact = function(char: Model)
	local isLocal = char == player.Character
	if not isLocal and not inRange(char) then
		return
	end
	local pick = getShownPickaxe(char)
	if not pick then
		return
	end
	local sparks = pick:FindFirstChild("ImpactSparks", true)
	if sparks and sparks:IsA("ParticleEmitter") then
		local color: Color3
		if isLocal and (os.clock() - ClientBus.LastHitClock) < 1.5 then
			color = ClientBus.LastHitColor
		else
			local neon = pick:GetAttribute("FxNeon")
			color = (typeof(neon) == "Color3") and neon or Color3.fromRGB(255, 230, 170)
		end
		sparks.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.45), color)
		sparks:Emit(pick:GetAttribute("FxEpic") == true and SWING.ImpactSparksEpic or SWING.ImpactSparks)
	end
	if isLocal then
		shakeCamera()
		UIKit.PlaySfx("Impact")
	end
end

-- ---------------------------------------------------------------------------
-- Топовые кирки: пульсация кристалла и света (бесконечные твины, отменяются вместе с киркой)
-- ---------------------------------------------------------------------------
local function startEpicPulse(pick: Model)
	if pick:GetAttribute("FxEpic") ~= true or pick:GetAttribute("PulseStarted") then
		return
	end
	local core = pick:WaitForChild("CrystalCore", 5)
	if not core or not core:IsA("BasePart") then
		return
	end
	pick:SetAttribute("PulseStarted", true)
	local tweens: { Tween } = {}
	local info = TweenInfo.new(SWING.PulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

	local baseColor = core:GetAttribute("BaseColor")
	if typeof(baseColor) == "Color3" then
		local tw = TweenService:Create(core, info, { Color = baseColor:Lerp(Color3.new(1, 1, 1), 0.5) })
		tw:Play()
		table.insert(tweens, tw)
	end
	local light = core:WaitForChild("CoreLight", 5)
	if light and light:IsA("PointLight") then
		local baseBrightness = tonumber(light:GetAttribute("BaseBrightness")) or light.Brightness
		light.Brightness = baseBrightness
		local tw = TweenService:Create(light, info, { Brightness = baseBrightness * SWING.PulseMin })
		tw:Play()
		table.insert(tweens, tw)
	end

	pick.AncestryChanged:Connect(function(_child: Instance, parent: Instance?)
		if parent == nil then
			UIKit.StopTweens(tweens)
		end
	end)
end

local function hookCharacter(char: Model)
	local function check(child: Instance)
		if child.Name == "VisualPickaxe" and child:IsA("Model") then
			task.spawn(startEpicPulse, child)
		end
	end
	char.ChildAdded:Connect(check)
	for _, child in ipairs(char:GetChildren()) do
		check(child)
	end
end

local function hookPlayer(plr: Player)
	plr.CharacterAdded:Connect(hookCharacter)
	if plr.Character then
		hookCharacter(plr.Character)
	end
end

Players.PlayerAdded:Connect(hookPlayer)
for _, plr in ipairs(Players:GetPlayers()) do
	hookPlayer(plr)
end
