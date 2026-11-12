--!strict
-- ============================================================================
-- ⏱️ КЛИЕНТ: PhaseHud (StarterPlayerScripts.PhaseHud)
-- v52: правый нижний угол экрана.
--   • Карточка таймера День/Ночь: круглая иконка ☀️/🌙 со свечением, крупная надпись
--     «ДЕНЬ» / «НОЧЬ», подпись «до ночи» / «до дня», время мм:сс моноширинным шрифтом
--     и полоса прогресса. Янтарный градиент днём, индиго-фиолетовый ночью, плавный
--     переход между фазами; в последние 10 секунд карточка пульсирует красным.
--   • Над таймером — вертикальный список чипов активных бустов: иконка, название,
--     множитель «×2», остаток мм:сс и убывающая мини-полоса. Чип пульсирует перед
--     окончанием и плавно исчезает, когда буст закончился.
-- Клиент ничего не считает сам: фаза — атрибуты ReplicatedStorage (Phase, PhaseEndsAt,
-- PhaseLength), бусты — атрибуты игрока Boost_<Id>_EndsAt / Boost_<Id>_Total, время —
-- workspace:GetServerTimeNow(). ScreenGui не сбрасывается при возрождении.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
if not player then
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local UIKit = require(Modules:WaitForChild("UIKit"))

local UI = GameConfig.UI
local P = GameConfig.PHASE
local HUD = GameConfig.PHASE_HUD
local BOOSTS = GameConfig.BOOSTS

local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "PhaseHudV52"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 6
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- Колонка: чипы бустов сверху, карточка таймера снизу; растёт вверх от правого нижнего угла
local stack = UIKit.Frame(gui, "Stack", UDim2.fromOffset(HUD.CardSize.X, 0), UDim2.new(1, -HUD.Margin, 1, -HUD.Margin), nil, 1)
stack.AnchorPoint = Vector2.new(1, 1)
stack.AutomaticSize = Enum.AutomaticSize.Y
local stackLayout = Instance.new("UIListLayout")
stackLayout.Padding = UDim.new(0, HUD.ChipGap)
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
stackLayout.Parent = stack
local stackScale = Instance.new("UIScale")
stackScale.Parent = stack

-- ---------------------------------------------------------------------------
-- Карточка таймера
-- ---------------------------------------------------------------------------
local card = UIKit.Frame(stack, "PhaseCard", UDim2.fromOffset(HUD.CardSize.X, HUD.CardSize.Y), UDim2.new(), nil, 1)
card.LayoutOrder = 1000
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local function phaseLayer(name: string, style: any, transparency: number): Frame
	local layer = UIKit.Frame(card, name, UDim2.fromScale(1, 1), UDim2.new(), Color3.new(1, 1, 1), transparency)
	UIKit.Corner(layer, 20)
	UIKit.Gradient(layer, style.Top, style.Bottom, 65)
	return layer
end
local dayLayer = phaseLayer("DayLayer", HUD.Day, 0)
local nightLayer = phaseLayer("NightLayer", HUD.Night, 1)
nightLayer.ZIndex = 2

-- Рамка и блик поверх обоих слоёв
local frameLayer = UIKit.Frame(card, "Frame", UDim2.fromScale(1, 1), UDim2.new(), nil, 1)
frameLayer.ZIndex = 3
UIKit.Corner(frameLayer, 20)
local cardStroke = UIKit.Stroke(frameLayer, HUD.Day.Glow, 3)
local gloss = UIKit.Frame(card, "Gloss", UDim2.new(1, -16, 0.42, 0), UDim2.fromOffset(8, 5), Color3.new(1, 1, 1), 0.86)
gloss.ZIndex = 3
UIKit.Corner(gloss, 14)

-- Круглая иконка со свечением
local glow = UIKit.Frame(card, "IconGlow", UDim2.fromOffset(74, 74), UDim2.fromOffset(6, 3), HUD.Day.Glow, 0.72)
glow.ZIndex = 4
UIKit.Corner(glow, 37)
local iconDisc = UIKit.Frame(card, "IconDisc", UDim2.fromOffset(58, 58), UDim2.fromOffset(14, 11), Color3.fromRGB(20, 18, 40), 0.35)
iconDisc.ZIndex = 5
UIKit.Corner(iconDisc, 29)
local iconStroke = UIKit.Stroke(iconDisc, HUD.Day.Glow, 2.5)
local dayIcon = UIKit.Label(iconDisc, { Name = "DayIcon", Text = HUD.Day.Icon, TextSize = 34, ZIndex = 6 })
local nightIcon = UIKit.Label(iconDisc, { Name = "NightIcon", Text = HUD.Night.Icon, TextSize = 34, ZIndex = 6 })
nightIcon.TextTransparency = 1

local titleLabel = UIKit.Label(card, {
	Name = "Title", Text = HUD.Day.Title, Size = UDim2.fromOffset(88, 30), Position = UDim2.fromOffset(84, 10),
	Font = UI.FontBlack, TextSize = 26, XAlign = Enum.TextXAlignment.Left, Stroke = true, ZIndex = 6,
})
local subLabel = UIKit.Label(card, {
	Name = "Sub", Text = HUD.Day.Sub, Size = UDim2.fromOffset(88, 16), Position = UDim2.fromOffset(85, 42),
	TextSize = 13, XAlign = Enum.TextXAlignment.Left, Color = Color3.fromRGB(255, 244, 228), ZIndex = 6,
})
local timeLabel = UIKit.Label(card, {
	Name = "Time", Text = "--:--", Size = UDim2.fromOffset(92, 36), Position = UDim2.new(1, -104, 0, 16),
	Font = UI.FontMono, TextSize = 29, XAlign = Enum.TextXAlignment.Right, Stroke = true, ZIndex = 6,
})

local barBack = UIKit.Frame(card, "Bar", UDim2.new(1, -28, 0, 9), UDim2.new(0, 14, 1, -20), Color3.fromRGB(12, 10, 26), 0.45)
barBack.ZIndex = 5
UIKit.Corner(barBack, 5)
local barFill = UIKit.Frame(barBack, "Fill", UDim2.fromScale(1, 1), UDim2.new(), HUD.Day.Bar)
barFill.ZIndex = 6
UIKit.Corner(barFill, 5)

local CurrentPhase = ""
local WarningOn = false
local PulseTween: Tween? = nil

local function styleOf(phase: string): any
	return phase == "Night" and HUD.Night or HUD.Day
end

-- Плавная смена оформления между фазами (кроссфейд двух градиентных слоёв)
local function applyPhaseStyle(phase: string, instant: boolean)
	local style = styleOf(phase)
	local night = phase == "Night"
	local info = TweenInfo.new(instant and 0 or HUD.StyleTweenSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(nightLayer, info, { BackgroundTransparency = night and 0 or 1 }):Play()
	TweenService:Create(dayLayer, info, { BackgroundTransparency = night and 1 or 0 }):Play()
	TweenService:Create(nightIcon, info, { TextTransparency = night and 0 or 1 }):Play()
	TweenService:Create(dayIcon, info, { TextTransparency = night and 1 or 0 }):Play()
	TweenService:Create(glow, info, { BackgroundColor3 = style.Glow }):Play()
	TweenService:Create(iconStroke, info, { Color = style.Glow }):Play()
	TweenService:Create(barFill, info, { BackgroundColor3 = style.Bar }):Play()
	if not WarningOn then
		TweenService:Create(cardStroke, info, { Color = style.Glow }):Play()
	end
	titleLabel.Text = style.Title
	subLabel.Text = style.Sub
end

-- Последние секунды фазы: пульсация и предупреждающий цвет
local function setWarning(on: boolean)
	if on == WarningOn then
		return
	end
	WarningOn = on
	if PulseTween then
		PulseTween:Cancel()
		PulseTween = nil
	end
	local quick = TweenInfo.new(0.25)
	if on then
		TweenService:Create(cardStroke, quick, { Color = HUD.Warning }):Play()
		TweenService:Create(timeLabel, quick, { TextColor3 = HUD.Warning:Lerp(Color3.new(1, 1, 1), 0.55) }):Play()
		local pulse = TweenService:Create(cardScale, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 })
		pulse:Play()
		PulseTween = pulse
	else
		TweenService:Create(cardStroke, quick, { Color = styleOf(CurrentPhase).Glow }):Play()
		TweenService:Create(timeLabel, quick, { TextColor3 = UI.Text }):Play()
		TweenService:Create(cardScale, quick, { Scale = 1 }):Play()
	end
end

local function updatePhase()
	local phase = ReplicatedStorage:GetAttribute(P.AttrPhase)
	local endsAt = ReplicatedStorage:GetAttribute(P.AttrEndsAt)
	local length = ReplicatedStorage:GetAttribute(P.AttrLength)
	if type(phase) ~= "string" or type(endsAt) ~= "number" or type(length) ~= "number" then
		timeLabel.Text = "--:--"
		return
	end
	if phase ~= CurrentPhase then
		local first = CurrentPhase == ""
		CurrentPhase = phase
		applyPhaseStyle(phase, first)
	end
	local remaining = math.max(0, endsAt - Workspace:GetServerTimeNow())
	timeLabel.Text = UIKit.FormatTime(remaining, true)
	TweenService:Create(barFill, TweenInfo.new(0.2, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(math.clamp(remaining / math.max(1, length), 0, 1), 1),
	}):Play()
	setWarning(remaining > 0 and remaining <= P.WarningSeconds)
end

-- ---------------------------------------------------------------------------
-- Чипы бустов
-- ---------------------------------------------------------------------------
type Chip = {
	Root: Frame,
	Scale: UIScale,
	Stroke: UIStroke,
	Time: TextLabel,
	Fill: Frame,
	EndsAt: number,
	Warn: boolean,
	Pulse: Tween?,
	Color: Color3,
}

local Chips: { [string]: Chip } = {}

local function makeChip(id: string, order: number): Chip
	local cfg = BOOSTS.Items[id]
	local root = UIKit.Frame(stack, "Boost_" .. id, UDim2.fromOffset(HUD.ChipSize.X, HUD.ChipSize.Y), UDim2.new(), Color3.new(1, 1, 1))
	root.LayoutOrder = order
	UIKit.Corner(root, 15)
	UIKit.Gradient(root, UI.PanelLight:Lerp(cfg.Color, 0.28), UI.BgBottom, 80)
	local stroke = UIKit.Stroke(root, cfg.Color, 2)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = root

	local disc = UIKit.Frame(root, "Icon", UDim2.fromOffset(34, 34), UDim2.fromOffset(6, 6), cfg.Color, 0.55)
	UIKit.Corner(disc, 17)
	UIKit.Label(disc, { Text = cfg.Icon, TextSize = 20, ZIndex = 2 })
	UIKit.Label(root, {
		Name = "Name", Text = cfg.Name, Size = UDim2.new(1, -122, 0, 18), Position = UDim2.fromOffset(48, 5),
		Font = UI.FontBlack, TextSize = 14, XAlign = Enum.TextXAlignment.Left, ZIndex = 2,
	})
	UIKit.Label(root, {
		Name = "Mult", Text = "×" .. tostring(cfg.Multiplier), Size = UDim2.fromOffset(40, 14), Position = UDim2.fromOffset(48, 26),
		Font = UI.FontBlack, TextSize = 13, XAlign = Enum.TextXAlignment.Left, Color = cfg.Color:Lerp(Color3.new(1, 1, 1), 0.35), ZIndex = 2,
	})
	local timeText = UIKit.Label(root, {
		Name = "Time", Text = "00:00", Size = UDim2.fromOffset(64, 20), Position = UDim2.new(1, -72, 0, 4),
		Font = UI.FontMono, TextSize = 16, XAlign = Enum.TextXAlignment.Right, ZIndex = 2,
	})
	local back = UIKit.Frame(root, "Bar", UDim2.new(1, -100, 0, 7), UDim2.fromOffset(90, 30), Color3.fromRGB(10, 10, 22), 0.35)
	UIKit.Corner(back, 4)
	local fill = UIKit.Frame(back, "Fill", UDim2.fromScale(1, 1), UDim2.new(), cfg.Color)
	fill.ZIndex = 2
	UIKit.Corner(fill, 4)

	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	return { Root = root, Scale = scale, Stroke = stroke, Time = timeText, Fill = fill, EndsAt = 0, Warn = false, Pulse = nil, Color = cfg.Color }
end

-- Буст закончился: чип плавно растворяется и удаляется
local function fadeOutChip(chip: Chip)
	if chip.Pulse then
		chip.Pulse:Cancel()
	end
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local root = chip.Root
	TweenService:Create(root, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(chip.Scale, info, { Scale = 0.8 }):Play()
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(0.5, function()
		root:Destroy()
	end)
end

local function updateBoosts()
	local now = Workspace:GetServerTimeNow()
	for order, id in ipairs(BOOSTS.Order) do
		local endsAt = player:GetAttribute("Boost_" .. id .. "_EndsAt")
		local total = player:GetAttribute("Boost_" .. id .. "_Total")
		local remaining = (type(endsAt) == "number") and (endsAt - now) or 0
		local chip = Chips[id]
		if remaining > 0 and type(endsAt) == "number" then
			if not chip then
				chip = makeChip(id, order)
				Chips[id] = chip
			elseif endsAt > chip.EndsAt + 0.5 then
				-- буст продлили: короткий «поп»
				chip.Scale.Scale = 1.12
				TweenService:Create(chip.Scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			chip.EndsAt = endsAt
			chip.Time.Text = UIKit.FormatTime(remaining, true)
			local window = (type(total) == "number" and total > 0) and total or BOOSTS.Items[id].Duration
			TweenService:Create(chip.Fill, TweenInfo.new(0.2, Enum.EasingStyle.Linear), {
				Size = UDim2.fromScale(math.clamp(remaining / window, 0, 1), 1),
			}):Play()

			local warn = remaining <= BOOSTS.ExpireWarnSeconds
			if warn ~= chip.Warn then
				chip.Warn = warn
				if chip.Pulse then
					chip.Pulse:Cancel()
					chip.Pulse = nil
				end
				if warn then
					chip.Stroke.Color = HUD.Warning
					local pulse = TweenService:Create(chip.Scale, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 })
					pulse:Play()
					chip.Pulse = pulse
				else
					chip.Stroke.Color = chip.Color
					chip.Scale.Scale = 1
				end
			end
		elseif chip then
			Chips[id] = nil
			fadeOutChip(chip)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Адаптив: масштаб и отступ над мобильными кнопками; тосты старого HUD — над колонкой
-- ---------------------------------------------------------------------------
local ToastHolder: GuiObject? = nil

local function bottomInset(): number
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local vp = UIKit.ViewportSize()
		return (math.min(vp.X, vp.Y) <= 500) and HUD.TouchBottomInsetPhone or HUD.TouchBottomInsetTablet
	end
	return 0
end

local function layout()
	local vp = UIKit.ViewportSize()
	stackScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.62, 1.1)
	stack.Position = UDim2.new(1, -HUD.Margin, 1, -(HUD.Margin + bottomInset()))
end

local function placeToasts()
	local holder = ToastHolder
	if holder and holder.Parent then
		holder.Position = UDim2.new(1, -16, 1, -(stack.AbsoluteSize.Y + HUD.Margin + bottomInset() + 10))
	end
end

layout()
local camera = Workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		layout()
		placeToasts()
	end)
end
stack:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeToasts)

-- Тосты ProgressionUI стоят в том же углу — поднимаем их над таймером и чипами
task.spawn(function()
	for _ = 1, 60 do
		local found = playerGui:FindFirstChild("Toasts", true)
		if found and found:IsA("GuiObject") then
			ToastHolder = found
			placeToasts()
			return
		end
		task.wait(0.5)
	end
end)

-- ---------------------------------------------------------------------------
-- Обновление: 5 раз в секунду (без покадровых циклов), мгновенно — при смене атрибутов
-- ---------------------------------------------------------------------------
ReplicatedStorage:GetAttributeChangedSignal(P.AttrPhase):Connect(updatePhase)
player.AttributeChanged:Connect(function(name: string)
	if string.sub(name, 1, 6) == "Boost_" then
		updateBoosts()
	end
end)

task.spawn(function()
	while true do
		updatePhase()
		updateBoosts()
		task.wait(0.2)
	end
end)
