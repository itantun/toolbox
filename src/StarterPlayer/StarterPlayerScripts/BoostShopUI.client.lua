--!strict
-- ============================================================================
-- ⚡ КЛИЕНТ: BoostShopUI (StarterPlayerScripts.BoostShopUI)
-- v52: окно бустов (Удача / Скорость / Монеты). Открывается вкладкой «⚡ Бусты»
-- в обычном меню магазина (ClientController) — сам магазин кирок и рюкзаков остался прежним.
--   • Карточки с рамкой цвета буста, диагональным бликом, мерцающими «✦» и «попом» при наведении.
--   • Кнопка «🪙 Цена» / «ПРОДЛИТЬ · 🪙 Цена»; на карточке — живой остаток активного буста.
--   • Не хватает монет — тряска карточки, красный тост и звук ошибки.
--     Покупка — зелёная вспышка, конфетти и звук успеха.
--   • Плавное открытие (Back); закрытие — крестик, клик мимо окна, Esc или уход с площадки магазина.
-- Клиент только отправляет запрос (Remote ShopAction) — цену, монеты, расстояние и кулдаун
-- проверяет сервер (ShopService). Анимации работают только пока окно открыто.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local UIKit = require(Modules:WaitForChild("UIKit"))
local ClientBus = require(Modules:WaitForChild("ClientBus"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData") :: RemoteEvent
local ShopAction = Remotes:WaitForChild("ShopAction") :: RemoteEvent
local ShopResult = Remotes:WaitForChild("ShopResult") :: RemoteEvent

local UI = GameConfig.UI
local CFG = GameConfig.SHOP_UI
local WIN = CFG.WindowSize
local CARD = CFG.CardSize

type Card = {
	Body: Frame,
	Line1: TextLabel,
	Button: TextButton,
	ButtonGrad: UIGradient,
	Shine: UIGradient,
	Twinkles: { TextLabel },
	Id: string,
}

local Coins = 0
local IsOpen = false
local OpenToken = 0
local Cards: { Card } = {}
local ActiveTweens: { Tween } = {}

-- ---------------------------------------------------------------------------
-- Каркас окна
-- ---------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "BoostShopV52"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

-- Затемнение: клик мимо окна закрывает его
local dim = Instance.new("TextButton")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.AutoButtonColor = false
dim.Text = ""
dim.Parent = gui

local window = UIKit.Frame(gui, "Window", UDim2.fromOffset(WIN.X, WIN.Y), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1))
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Active = true -- окно «съедает» клики, чтобы они не закрывали его
window.ZIndex = 2
UIKit.Corner(window, 22)
UIKit.Gradient(window, UI.BgTop, UI.BgBottom, 90)
local windowStroke = UIKit.Stroke(window, Color3.new(1, 1, 1), 3)
UIKit.Gradient(windowStroke, UI.Gold, UI.Purple, 35)
local winScale = Instance.new("UIScale")
winScale.Parent = window
UIKit.BindScale(winScale, WIN.X, WIN.Y, 1.1)

-- Слой эффектов (тосты и конфетти) — отдельный всегда включённый ScreenGui поверх окна
local fxGui = Instance.new("ScreenGui")
fxGui.Name = "BoostShopV52Fx"
fxGui.ResetOnSpawn = false
fxGui.IgnoreGuiInset = true
fxGui.DisplayOrder = 40
fxGui.Parent = playerGui
local fxLayer = UIKit.Frame(fxGui, "FxLayer", UDim2.fromScale(1, 1), UDim2.new(), nil, 1)
fxLayer.Active = false

UIKit.Label(window, {
	Name = "Title", Text = "⚡ БУСТЫ", Size = UDim2.new(0, 300, 0, 40), Position = UDim2.fromOffset(24, 14),
	Font = UI.FontTitle, TextSize = 28, XAlign = Enum.TextXAlignment.Left, Color = UI.Gold, Stroke = true, ZIndex = 3,
})
UIKit.Label(window, {
	Name = "Subtitle", Text = "Повторная покупка продлевает буст", Size = UDim2.new(0, 340, 0, 16), Position = UDim2.fromOffset(26, 50),
	TextSize = 12, XAlign = Enum.TextXAlignment.Left, Color = UI.TextDim, ZIndex = 3,
})

local coinsPill = UIKit.Frame(window, "Coins", UDim2.fromOffset(200, 40), UDim2.new(1, -268, 0, 16), UI.Panel)
coinsPill.ZIndex = 3
UIKit.Corner(coinsPill, 20)
UIKit.Stroke(coinsPill, UI.Gold, 2, 0.2)
local coinsLabel = UIKit.Label(coinsPill, {
	Name = "Value", Text = "🪙 0", Font = UI.FontBlack, TextSize = 19, Color = UI.Gold, ZIndex = 4,
})

local closeBtn = UIKit.Button(window, "Close", "✕", UDim2.fromOffset(40, 40), UDim2.new(1, -56, 0, 16), UI.Red, UI.RedDark)
closeBtn.TextSize = 20
closeBtn.ZIndex = 4

local row = UIKit.Frame(window, "Cards", UDim2.new(1, -40, 0, CARD.Y), UDim2.fromOffset(20, 84), nil, 1)
row.ZIndex = 3
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.Padding = UDim.new(0, 16)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Parent = row

-- ---------------------------------------------------------------------------
-- Карточки бустов
-- ---------------------------------------------------------------------------
local function boostRemaining(id: string): number
	local endsAt = player:GetAttribute("Boost_" .. id .. "_EndsAt")
	if type(endsAt) ~= "number" then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

local function failFeedback(card: Card?, message: string)
	UIKit.PlaySfx("Error")
	UIKit.Toast(fxLayer, message, UI.Red)
	if card then
		UIKit.Shake(card.Body)
		UIKit.Flash(card.Body, UI.Red, 16)
	end
end

local function makeCard(cfg: any, order: number, rng: Random): Card
	local rarity = GameConfig.RARITY[cfg.Rarity] or GameConfig.RARITY[1]
	local color: Color3 = cfg.Color

	-- внешний кадр держит место в ряду, внутренний «Body» можно трясти и масштабировать
	local root = UIKit.Frame(row, "Card_" .. cfg.Id, UDim2.fromOffset(CARD.X, CARD.Y), UDim2.new(), nil, 1)
	root.LayoutOrder = order
	root.ZIndex = 3
	local body = UIKit.Frame(root, "Body", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1))
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.ZIndex = 3
	UIKit.Corner(body, 16)
	UIKit.Gradient(body, UI.PanelLight:Lerp(color, 0.12), UI.BgBottom, 90)
	local stroke = UIKit.Stroke(body, Color3.new(1, 1, 1), 2.5, 0.15)
	UIKit.Gradient(stroke, color:Lerp(Color3.new(1, 1, 1), 0.35), color:Lerp(Color3.new(0, 0, 0), 0.25), 60)
	local scale = Instance.new("UIScale")
	scale.Parent = body

	local preview = UIKit.Frame(body, "Preview", UDim2.new(1, -20, 0, 118), UDim2.fromOffset(10, 10), Color3.new(1, 1, 1))
	preview.ZIndex = 4
	UIKit.Corner(preview, 12)
	UIKit.Gradient(preview, color:Lerp(UI.BgBottom, 0.55), UI.BgBottom, 90)

	local function tag(text: string, right: boolean)
		local t = UIKit.Frame(preview, right and "MultTag" or "RarityTag", UDim2.fromOffset(right and 54 or 96, 18),
			right and UDim2.new(1, -60, 0, 6) or UDim2.fromOffset(6, 6), color:Lerp(Color3.new(0, 0, 0), 0.45))
		t.ZIndex = 8
		UIKit.Corner(t, 9)
		UIKit.Label(t, { Text = text, Font = UI.FontBlack, TextSize = 10, Color = color:Lerp(Color3.new(1, 1, 1), 0.6), ZIndex = 9 })
	end
	tag(rarity.Name, false)
	tag("×" .. tostring(cfg.Multiplier), true)

	-- крупная иконка в светящемся круге
	local halo = UIKit.Frame(preview, "Halo", UDim2.fromOffset(84, 84), UDim2.new(0.5, -42, 0.5, -36), color, 0.55)
	halo.ZIndex = 5
	UIKit.Corner(halo, 42)
	UIKit.Stroke(halo, color:Lerp(Color3.new(1, 1, 1), 0.4), 2, 0.2)
	UIKit.Label(halo, { Text = cfg.Icon, TextSize = 46, ZIndex = 6 })

	UIKit.Label(body, {
		Name = "Title", Text = cfg.Name .. " ×" .. tostring(cfg.Multiplier), Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 134), Font = UI.FontBlack, TextSize = 15, Color = color:Lerp(Color3.new(1, 1, 1), 0.55), ZIndex = 5,
	})
	local line1 = UIKit.Label(body, {
		Name = "Line1", Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 160), TextSize = 13, ZIndex = 5,
	})
	UIKit.Label(body, {
		Name = "Line2", Text = cfg.Desc, Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 180), TextSize = 12,
		Color = UI.TextDim, Wrapped = true, YAlign = Enum.TextYAlignment.Top, ZIndex = 5,
	})

	local button, buttonGrad = UIKit.Button(body, "Action", "", UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 1, -50), UI.Gold, Color3.fromRGB(214, 130, 20))
	button.ZIndex = 6

	local twinkles = UIKit.AddTwinkles(preview, 3, color, rng, 7)
	local shine = UIKit.AddShine(body, 16, 9)

	-- наведение: плавный «поп» и более яркая рамка
	body.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = UI.HoverScale }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.16), { Thickness = 4, Transparency = 0 }):Play()
	end)
	body.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.16), { Thickness = 2.5, Transparency = 0.15 }):Play()
	end)

	local card: Card = {
		Body = body, Line1 = line1, Button = button, ButtonGrad = buttonGrad, Shine = shine, Twinkles = twinkles, Id = cfg.Id,
	}
	button.Activated:Connect(function()
		if Coins < cfg.Price then
			failFeedback(card, string.format("Не хватает монет! Нужно ещё %s 🪙", UIKit.FormatCoins(cfg.Price - Coins)))
			return
		end
		UIKit.PlaySfx("Click")
		ShopAction:FireServer("BuyBoost", cfg.Id)
	end)
	return card
end

do
	local rng = Random.new(5203)
	local order = 0
	for _, id in ipairs(GameConfig.BOOSTS.Order) do
		local cfg = GameConfig.BOOSTS.Items[id]
		if cfg and cfg.InShop then
			order += 1
			table.insert(Cards, makeCard(cfg, order, rng))
		end
	end
end

local function refresh()
	coinsLabel.Text = "🪙 " .. UIKit.FormatCoins(Coins)
	for _, card in ipairs(Cards) do
		local cfg = GameConfig.BOOSTS.Items[card.Id]
		local left = boostRemaining(card.Id)
		local price = "🪙 " .. UIKit.FormatCoins(cfg.Price)
		if left > 0 then
			card.Line1.Text = "✅ Активен: " .. UIKit.FormatTime(left)
			card.Line1.TextColor3 = UI.Green
			price = "ПРОДЛИТЬ · " .. price
		else
			card.Line1.Text = "⏱ " .. UIKit.FormatTime(cfg.Duration) .. " за покупку"
			card.Line1.TextColor3 = UI.Text
		end
		card.Button.Text = price
		if Coins >= cfg.Price then
			card.ButtonGrad.Color = ColorSequence.new(UI.Gold, Color3.fromRGB(214, 130, 20))
			card.Button.TextColor3 = Color3.new(1, 1, 1)
		else
			card.ButtonGrad.Color = ColorSequence.new(Color3.fromRGB(120, 108, 92), Color3.fromRGB(70, 60, 56))
			card.Button.TextColor3 = Color3.fromRGB(255, 190, 180)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Открытие / закрытие
-- ---------------------------------------------------------------------------
local function distanceToShop(): number
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return math.huge
	end
	local c = GameConfig.GREEN_SHOP_PAD_POS
	return Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z).Magnitude
end

local function closeWindow()
	if not IsOpen then
		return
	end
	IsOpen = false
	OpenToken += 1
	local token = OpenToken
	ClientBus.SetWindowOpen("Boosts", false)
	UIKit.StopTweens(ActiveTweens)
	winScale:SetAttribute("Animating", true)
	TweenService:Create(dim, TweenInfo.new(UI.CloseSeconds), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(winScale, TweenInfo.new(UI.CloseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = ((winScale:GetAttribute("Fit") :: number?) or 1) * 0.7,
	}):Play()
	task.delay(UI.CloseSeconds, function()
		if token == OpenToken then
			gui.Enabled = false
			winScale:SetAttribute("Animating", nil)
		end
	end)
end

local function openWindow()
	if IsOpen then
		return
	end
	if distanceToShop() > CFG.AutoCloseDistance then
		UIKit.PlaySfx("Error")
		UIKit.Toast(fxLayer, "Бусты продаются в магазине — подойди к нему!", UI.Red)
		return
	end
	IsOpen = true
	OpenToken += 1
	local token = OpenToken
	ClientBus.SetWindowOpen("Boosts", true)
	gui.Enabled = true
	refresh()
	for _, card in ipairs(Cards) do
		UIKit.StartTwinkles(card.Twinkles, ActiveTweens)
	end

	-- плавное открытие: окно «выпрыгивает» с Back-смягчением
	local fit = (winScale:GetAttribute("Fit") :: number?) or 1
	winScale:SetAttribute("Animating", true)
	winScale.Scale = fit * 0.6
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, TweenInfo.new(UI.OpenSeconds), { BackgroundTransparency = 0.45 }):Play()
	local tw = TweenService:Create(winScale, TweenInfo.new(UI.OpenSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit })
	tw:Play()
	tw.Completed:Once(function()
		if token == OpenToken then
			winScale:SetAttribute("Animating", nil)
			winScale.Scale = (winScale:GetAttribute("Fit") :: number?) or fit
		end
	end)
	UIKit.PlaySfx("Open")

	-- один лёгкий цикл, пока окно открыто: остаток бустов, блики, уход с площадки магазина
	task.spawn(function()
		local sinceShine = UI.ShineInterval - 0.5
		while IsOpen and token == OpenToken do
			task.wait(0.25)
			if not IsOpen or token ~= OpenToken then
				break
			end
			if distanceToShop() > CFG.AutoCloseDistance then
				closeWindow()
				break
			end
			refresh()
			sinceShine += 0.25
			if sinceShine >= UI.ShineInterval then
				sinceShine = 0
				for i, card in ipairs(Cards) do
					UIKit.PlayShine(card.Shine, (i - 1) * 0.08)
				end
			end
		end
	end)
end

closeBtn.Activated:Connect(function()
	UIKit.PlaySfx("Click")
	closeWindow()
end)
dim.Activated:Connect(closeWindow)
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Escape and IsOpen then
		closeWindow()
	end
end)

ClientBus.OpenShop.Event:Connect(openWindow)
ClientBus.CloseShop.Event:Connect(closeWindow)
ClientBus.CloseAll.Event:Connect(closeWindow)
ClientBus.ToggleBag.Event:Connect(closeWindow) -- открыли рюкзак — окно бустов закрывается

-- ---------------------------------------------------------------------------
-- Данные и ответы сервера
-- ---------------------------------------------------------------------------
SyncPlayerData.OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" then
		return
	end
	Coins = tonumber(data.Coins) or Coins
	if IsOpen then
		refresh()
	end
end)

ShopResult.OnClientEvent:Connect(function(ok: any, action: any, info: any)
	if action ~= "BuyBoost" or type(info) ~= "table" then
		return
	end
	local found: Card? = nil
	for _, card in ipairs(Cards) do
		if card.Id == info.Id then
			found = card
		end
	end
	local cfg = GameConfig.BOOSTS.Items[tostring(info.Id)]
	if ok == true and cfg then
		UIKit.PlaySfx("Success")
		UIKit.Toast(fxLayer, string.format("%s %s ×%s — осталось %s", cfg.Icon, cfg.Name, tostring(cfg.Multiplier),
			UIKit.FormatTime(tonumber(info.Remaining) or cfg.Duration)), UI.Green)
		if found then
			UIKit.Flash(found.Body, UI.Green, 16)
			local center = found.Body.AbsolutePosition + found.Body.AbsoluteSize / 2 - fxLayer.AbsolutePosition
			UIKit.Confetti(fxLayer, center, { UI.Gold, UI.Green, Color3.new(1, 1, 1), UI.Blue }, 18)
		end
	elseif info.Reason == "Far" then
		failFeedback(nil, "Подойди ближе к магазину!")
	else
		failFeedback(found, "Не хватает монет!")
	end
end)
