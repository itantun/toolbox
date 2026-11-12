--!strict
-- ============================================================================
-- 🛒 КЛИЕНТ: ShopUI (StarterPlayerScripts.ShopUI)
-- v52: яркий «живой» магазин торговца Гоши.
--   • Вкладки: Кирки / Рюкзаки / Бусты / Продать руду.
--   • Карточки: 3D-превью настоящей модели во ViewportFrame с медленным вращением,
--     рамка цвета редкости, блик по диагонали, мерцающие «✦», «поп» при наведении.
--   • Кнопка: «🪙 Цена» / «НАДЕТЬ» / «✓ НАДЕТО». Не хватает монет — тряска карточки,
--     красный тост и звук ошибки. Покупка — зелёная вспышка, конфетти и звук успеха.
--   • Открытие с Back-анимацией; закрытие — крестик, клик мимо окна, Esc или уход от прилавка.
-- Клиент только отправляет запросы (Remote ShopAction) — всё проверяет сервер (ShopService).
-- Анимации и вращение работают только пока окно открыто.
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
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
local EquipmentBuilder = require(Modules:WaitForChild("EquipmentBuilder"))
local OreIconModels = require(Modules:WaitForChild("OreIconModels"))
local InputBlocker = require(Modules:WaitForChild("InputBlocker"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData") :: RemoteEvent
local ShopAction = Remotes:WaitForChild("ShopAction") :: RemoteEvent
local ShopResult = Remotes:WaitForChild("ShopResult") :: RemoteEvent

local UI = GameConfig.UI
local CFG = GameConfig.SHOP_UI
local WIN = CFG.WindowSize
local CARD = CFG.CardSize

-- ---------------------------------------------------------------------------
-- Состояние (приходит с сервера через SyncPlayerData)
-- ---------------------------------------------------------------------------
local State = {
	Coins = 0,
	PickaxeTier = 1,
	BackpackLevel = 1,
	OwnedPickaxes = { [1] = true } :: { [number]: boolean },
	OwnedBackpacks = { [1] = true } :: { [number]: boolean },
	Inventory = {} :: { [string]: number },
	MorningInventory = {} :: { [string]: number },
	BagValue = 0,
}

type Card = {
	Root: Frame,
	Body: Frame,
	Scale: UIScale,
	Stroke: UIStroke,
	Preview: Frame,
	Title: TextLabel,
	Line1: TextLabel,
	Line2: TextLabel,
	Button: TextButton,
	ButtonGrad: UIGradient,
	Shine: UIGradient,
	Twinkles: { TextLabel },
	Spin: UIKit.SpinItem?,
	Key: string,
}

local IsOpen = false
local OpenToken = 0
local ActiveTab = "Pickaxes"
local TabFrames: { [string]: Frame } = {}
local TabCards: { [string]: { Card } } = {}
local TabButtons: { [string]: { Button: TextButton, Stroke: UIStroke } } = {}
local ActiveTweens: { Tween } = {}
local SellSignature = ""

-- ---------------------------------------------------------------------------
-- Каркас окна
-- ---------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "ShopV52"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

-- Затемнение: клик мимо окна закрывает магазин
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
window.Active = true -- окно «съедает» клики, чтобы они не закрывали магазин
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
fxGui.Name = "ShopV52Fx"
fxGui.ResetOnSpawn = false
fxGui.IgnoreGuiInset = true
fxGui.DisplayOrder = 40
fxGui.Parent = playerGui
local fxLayer = UIKit.Frame(fxGui, "FxLayer", UDim2.fromScale(1, 1), UDim2.new(), nil, 1)
fxLayer.Active = false

-- Шапка: название, монеты, крестик
UIKit.Label(window, {
	Name = "Title", Text = "🛒 РЫНОК ГОШИ", Size = UDim2.new(0, 360, 0, 40), Position = UDim2.fromOffset(24, 14),
	Font = UI.FontTitle, TextSize = 28, XAlign = Enum.TextXAlignment.Left, Color = UI.Gold, Stroke = true, ZIndex = 3,
})
UIKit.Label(window, {
	Name = "Subtitle", Text = "Кирки, рюкзаки, бусты и скупка руды", Size = UDim2.new(0, 360, 0, 16), Position = UDim2.fromOffset(26, 50),
	TextSize = 12, XAlign = Enum.TextXAlignment.Left, Color = UI.TextDim, ZIndex = 3,
})

local coinsPill = UIKit.Frame(window, "Coins", UDim2.fromOffset(210, 40), UDim2.new(1, -278, 0, 16), UI.Panel)
coinsPill.ZIndex = 3
UIKit.Corner(coinsPill, 20)
UIKit.Stroke(coinsPill, UI.Gold, 2, 0.2)
local coinsLabel = UIKit.Label(coinsPill, {
	Name = "Value", Text = "🪙 0", Font = UI.FontBlack, TextSize = 19, Color = UI.Gold, ZIndex = 4,
})

local closeBtn = UIKit.Button(window, "Close", "✕", UDim2.fromOffset(40, 40), UDim2.new(1, -56, 0, 16), UI.Red, UI.RedDark)
closeBtn.TextSize = 20
closeBtn.ZIndex = 4

-- Вкладки
local tabBar = UIKit.Frame(window, "Tabs", UDim2.new(1, -40, 0, 44), UDim2.fromOffset(20, 76), nil, 1)
tabBar.ZIndex = 3
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 10)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

-- Прокручиваемая область карточек
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Content"
scroll.Size = UDim2.new(1, -32, 1, -148)
scroll.Position = UDim2.fromOffset(16, 132)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = UI.Gold
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ZIndex = 3
scroll.Parent = window

local emptyLabel = UIKit.Label(window, {
	Name = "Empty", Text = "", Size = UDim2.new(1, -80, 0, 60), Position = UDim2.new(0, 40, 0.5, 20),
	Font = UI.FontBlack, TextSize = 22, Color = UI.TextDim, Wrapped = true, ZIndex = 4,
})
emptyLabel.Visible = false

local spinner = UIKit.NewSpinner(UI.ViewportSpinSeconds, scroll)

-- ---------------------------------------------------------------------------
-- Карточка товара
-- ---------------------------------------------------------------------------
local function makeCard(tabId: string, key: string, order: number, rarityColor: Color3, rng: Random): Card
	local root = UIKit.Frame(TabFrames[tabId], "Card_" .. key, UDim2.fromOffset(CARD.X, CARD.Y), UDim2.new(), nil, 1)
	root.LayoutOrder = order
	root.ZIndex = 3

	local body = UIKit.Frame(root, "Body", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1))
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.ZIndex = 3
	UIKit.Corner(body, 16)
	UIKit.Gradient(body, UI.PanelLight:Lerp(rarityColor, 0.12), UI.BgBottom, 90)
	local stroke = UIKit.Stroke(body, Color3.new(1, 1, 1), 2.5, 0.15)
	UIKit.Gradient(stroke, rarityColor:Lerp(Color3.new(1, 1, 1), 0.35), rarityColor:Lerp(Color3.new(0, 0, 0), 0.25), 60)
	local scale = Instance.new("UIScale")
	scale.Parent = body

	-- Подложка превью с отсветом цвета редкости
	local preview = UIKit.Frame(body, "Preview", UDim2.new(1, -20, 0, 118), UDim2.fromOffset(10, 10), Color3.new(1, 1, 1))
	preview.ZIndex = 4
	UIKit.Corner(preview, 12)
	UIKit.Gradient(preview, rarityColor:Lerp(UI.BgBottom, 0.55), UI.BgBottom, 90)

	local title = UIKit.Label(body, {
		Name = "Title", Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 134),
		Font = UI.FontBlack, TextSize = 15, Color = rarityColor:Lerp(Color3.new(1, 1, 1), 0.55), ZIndex = 5,
	})
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local line1 = UIKit.Label(body, {
		Name = "Line1", Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 160), TextSize = 13, ZIndex = 5,
	})
	local line2 = UIKit.Label(body, {
		Name = "Line2", Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 180), TextSize = 12,
		Color = UI.TextDim, Wrapped = true, YAlign = Enum.TextYAlignment.Top, ZIndex = 5,
	})

	local button, buttonGrad = UIKit.Button(body, "Action", "", UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 1, -50), UI.Gold, Color3.fromRGB(214, 130, 20))
	button.ZIndex = 6

	local twinkles = UIKit.AddTwinkles(preview, 3, rarityColor, rng, 7)
	local shine = UIKit.AddShine(body, 16, 9)

	-- Наведение: плавный «поп» и более яркая рамка
	body.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = UI.HoverScale }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.16), { Thickness = 4, Transparency = 0 }):Play()
	end)
	body.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.16), { Thickness = 2.5, Transparency = 0.15 }):Play()
	end)

	local card: Card = {
		Root = root, Body = body, Scale = scale, Stroke = stroke, Preview = preview, Title = title,
		Line1 = line1, Line2 = line2, Button = button, ButtonGrad = buttonGrad, Shine = shine,
		Twinkles = twinkles, Spin = nil, Key = key,
	}
	table.insert(TabCards[tabId], card)
	return card
end

-- Маленькая плашка в углу превью (редкость слева, уровень справа)
local function addTag(card: Card, text: string, color: Color3, right: boolean)
	local tag = UIKit.Frame(card.Preview, right and "LevelTag" or "RarityTag", UDim2.fromOffset(right and 54 or 96, 18),
		right and UDim2.new(1, -60, 0, 6) or UDim2.fromOffset(6, 6), color:Lerp(Color3.new(0, 0, 0), 0.45))
	tag.ZIndex = 8
	UIKit.Corner(tag, 9)
	UIKit.Label(tag, { Text = text, Font = UI.FontBlack, TextSize = 10, Color = color:Lerp(Color3.new(1, 1, 1), 0.6), ZIndex = 9 })
end

-- 3D-превью: модель в ViewportFrame, камера медленно облетает её
local function addModelPreview(card: Card, model: Model, center: Vector3, distance: number, height: number, phase: number)
	local vp, cam, world = UIKit.Viewport(card.Preview, "Model", UDim2.fromScale(1, 1), UDim2.new())
	vp.ZIndex = 5
	model.Parent = world
	local item: UIKit.SpinItem = { Viewport = vp, Camera = cam, Center = center, Distance = distance, Height = height, Phase = phase }
	card.Spin = item
	UIKit.OrbitCamera(item, 0)
end

local function setButton(card: Card, text: string, c0: Color3, c1: Color3, textColor: Color3?)
	card.Button.Text = text
	card.ButtonGrad.Color = ColorSequence.new(c0, c1)
	card.Button.TextColor3 = textColor or Color3.new(1, 1, 1)
end

local function cardCenter(card: Card): Vector2
	return card.Body.AbsolutePosition + card.Body.AbsoluteSize / 2 - fxLayer.AbsolutePosition
end

local function failFeedback(card: Card?, message: string)
	UIKit.PlaySfx("Error")
	UIKit.Toast(fxLayer, message, UI.Red)
	if card then
		UIKit.Shake(card.Body)
		UIKit.Flash(card.Body, UI.Red, 16)
	end
end

local function successFeedback(card: Card?, message: string, confetti: boolean)
	UIKit.PlaySfx("Success")
	UIKit.Toast(fxLayer, message, UI.Green)
	if card then
		UIKit.Flash(card.Body, UI.Green, 16)
		if confetti then
			UIKit.Confetti(fxLayer, cardCenter(card), { UI.Gold, UI.Green, Color3.new(1, 1, 1), UI.Blue }, 18)
		end
	end
end

local function findCard(tabId: string, key: string): Card?
	for _, card in ipairs(TabCards[tabId] or {}) do
		if card.Key == key then
			return card
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Вкладки «Кирки» и «Рюкзаки»
-- ---------------------------------------------------------------------------
local function requestGear(tabId: string, level: number, cost: number, card: Card)
	local isPick = tabId == "Pickaxes"
	local owned = isPick and State.OwnedPickaxes[level] or State.OwnedBackpacks[level]
	local equipped = (isPick and State.PickaxeTier or State.BackpackLevel) == level
	if equipped then
		UIKit.PlaySfx("Click")
		return
	end
	if not owned and State.Coins < cost then
		failFeedback(card, string.format("Не хватает монет! Нужно ещё %s 🪙", UIKit.FormatCoins(cost - State.Coins)))
		return
	end
	UIKit.PlaySfx("Click")
	ShopAction:FireServer(isPick and "BuyPickaxe" or "BuyBackpack", level)
end

local function buildGearTab(tabId: string)
	local isPick = tabId == "Pickaxes"
	local rng = Random.new(isPick and 5201 or 5202)
	local maxLevel = isPick and GameConfig.MAX_PICKAXE_LEVEL or GameConfig.MAX_BACKPACK_LEVEL
	local preview = GameConfig.SHOP_PREVIEW
	for level = 1, maxLevel do
		local rarity = GameConfig.GetTierRarity(level)
		local card = makeCard(tabId, tostring(level), level, rarity.Color, rng)
		addTag(card, rarity.Name, rarity.Color, false)
		addTag(card, "Ур. " .. level, rarity.Color, true)

		local model = Instance.new("Model")
		model.Name = "Preview"
		local cost = 0
		if isPick then
			local cfg = GameConfig.PICKAXE_TIERS[level]
			cost = cfg.Cost
			card.Title.Text = GameConfig.RU_NAMES.Pickaxes[level] or cfg.Name
			card.Line1.Text = string.format("⚔ Урон %d   ⏱ %.2f с", cfg.Damage, cfg.BaseSwingCooldown)
			card.Line2.Text = "Мощнее удар — глубже руда"
			-- та же сборка, что и у кирки в руке (EquipmentBuilder + PickaxeJuice)
			local ok = pcall(EquipmentBuilder.BuildModernPickaxeParts, model, level, CFrame.Angles(0, 0, math.rad(-18)), true,
				{ Scale = 1, LowDetail = true, ForViewport = true })
			if ok then
				addModelPreview(card, model, Vector3.new(0, 0.1, 0), preview.PickaxeDistance, preview.PickaxeHeight, level * 0.6)
			end
		else
			local cfg = GameConfig.BACKPACK_TIERS[level]
			cost = cfg.Cost
			card.Title.Text = GameConfig.RU_NAMES.Backpacks[level] or cfg.Name
			card.Line1.Text = string.format("📦 Вместимость: %d", cfg.Capacity)
			card.Line2.Text = "Больше руды за один спуск"
			local ok = pcall(EquipmentBuilder.BuildBackpackParts, model, level, CFrame.new(), true, 1.0)
			if ok then
				addModelPreview(card, model, Vector3.new(0, 0, 0), preview.BackpackDistance, preview.BackpackHeight, level * 0.6)
			end
		end
		card.Button.Activated:Connect(function()
			requestGear(tabId, level, cost, card)
		end)
	end
end

local function refreshGearTab(tabId: string)
	local isPick = tabId == "Pickaxes"
	for _, card in ipairs(TabCards[tabId] or {}) do
		local level = tonumber(card.Key) or 1
		local cost = isPick and GameConfig.PICKAXE_TIERS[level].Cost or GameConfig.BACKPACK_TIERS[level].Cost
		local owned = isPick and State.OwnedPickaxes[level] or State.OwnedBackpacks[level]
		local equipped = (isPick and State.PickaxeTier or State.BackpackLevel) == level
		if equipped then
			setButton(card, isPick and "✓ НАДЕТА" or "✓ НАДЕТ", UI.GreenDark, Color3.fromRGB(16, 92, 50), Color3.fromRGB(200, 255, 215))
		elseif owned then
			setButton(card, "НАДЕТЬ", UI.Blue, UI.BlueDark)
		elseif State.Coins >= cost then
			setButton(card, "🪙 " .. UIKit.FormatCoins(cost), UI.Gold, Color3.fromRGB(214, 130, 20))
		else
			setButton(card, "🪙 " .. UIKit.FormatCoins(cost), Color3.fromRGB(120, 108, 92), Color3.fromRGB(70, 60, 56), Color3.fromRGB(255, 190, 180))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Вкладка «Бусты»
-- ---------------------------------------------------------------------------
local function boostRemaining(id: string): number
	local endsAt = player:GetAttribute("Boost_" .. id .. "_EndsAt")
	if type(endsAt) ~= "number" then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

local function buildBoostTab()
	local rng = Random.new(5203)
	local order = 0
	for _, id in ipairs(GameConfig.BOOSTS.Order) do
		local cfg = GameConfig.BOOSTS.Items[id]
		if cfg and cfg.InShop then
			order += 1
			local rarity = GameConfig.RARITY[cfg.Rarity] or GameConfig.RARITY[1]
			local card = makeCard("Boosts", id, order, cfg.Color, rng)
			addTag(card, rarity.Name, cfg.Color, false)
			addTag(card, "×" .. tostring(cfg.Multiplier), cfg.Color, true)
			-- крупная иконка в светящемся круге
			local halo = UIKit.Frame(card.Preview, "Halo", UDim2.fromOffset(84, 84), UDim2.new(0.5, -42, 0.5, -36), cfg.Color, 0.55)
			halo.ZIndex = 5
			UIKit.Corner(halo, 42)
			UIKit.Stroke(halo, cfg.Color:Lerp(Color3.new(1, 1, 1), 0.4), 2, 0.2)
			UIKit.Label(halo, { Text = cfg.Icon, TextSize = 46, ZIndex = 6 })
			card.Title.Text = cfg.Name .. " ×" .. tostring(cfg.Multiplier)
			card.Line1.Text = "⏱ " .. UIKit.FormatTime(cfg.Duration) .. " за покупку"
			card.Line2.Text = cfg.Desc
			card.Button.Activated:Connect(function()
				if State.Coins < cfg.Price then
					failFeedback(card, string.format("Не хватает монет! Нужно ещё %s 🪙", UIKit.FormatCoins(cfg.Price - State.Coins)))
					return
				end
				UIKit.PlaySfx("Click")
				ShopAction:FireServer("BuyBoost", id)
			end)
		end
	end
end

local function refreshBoostTab()
	for _, card in ipairs(TabCards.Boosts or {}) do
		local cfg = GameConfig.BOOSTS.Items[card.Key]
		if cfg then
			local left = boostRemaining(cfg.Id)
			local affordable = State.Coins >= cfg.Price
			local price = "🪙 " .. UIKit.FormatCoins(cfg.Price)
			if left > 0 then
				card.Line1.Text = "✅ Активен: " .. UIKit.FormatTime(left)
				card.Line1.TextColor3 = UI.Green
				price = "ПРОДЛИТЬ · " .. price
			else
				card.Line1.Text = "⏱ " .. UIKit.FormatTime(cfg.Duration) .. " за покупку"
				card.Line1.TextColor3 = UI.Text
			end
			if affordable then
				setButton(card, price, UI.Gold, Color3.fromRGB(214, 130, 20))
			else
				setButton(card, price, Color3.fromRGB(120, 108, 92), Color3.fromRGB(70, 60, 56), Color3.fromRGB(255, 190, 180))
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Вкладка «Продать руду»
-- ---------------------------------------------------------------------------
type OreStack = { Key: string, OreId: string, Count: number, UnitPrice: number, Morning: boolean }

local function collectStacks(): { OreStack }
	local stacks: { OreStack } = {}
	for _, info in ipairs(GameConfig.BLOCK_LIST) do
		local reg = State.Inventory[info.Id] or 0
		if reg > 0 then
			table.insert(stacks, { Key = "Reg_" .. info.Id, OreId = info.Id, Count = reg, UnitPrice = info.SellPrice, Morning = false })
		end
		local morn = State.MorningInventory[info.Id] or 0
		if morn > 0 then
			table.insert(stacks, {
				Key = "Morn_" .. info.Id, OreId = info.Id, Count = morn,
				UnitPrice = info.SellPrice * GameConfig.MORNING_VEINS.SellPriceMultiplier, Morning = true,
			})
		end
	end
	table.sort(stacks, function(a, b)
		return a.Count * a.UnitPrice > b.Count * b.UnitPrice
	end)
	return stacks
end

local function clearTab(tabId: string)
	for _, card in ipairs(TabCards[tabId]) do
		local spin = card.Spin
		if spin then
			spinner.Remove(spin.Viewport)
		end
		card.Root:Destroy()
	end
	table.clear(TabCards[tabId])
end

local function registerSpin(tabId: string)
	spinner.Clear()
	for _, card in ipairs(TabCards[tabId] or {}) do
		local spin = card.Spin
		if spin then
			spinner.Add(spin)
		end
	end
end

local function startTwinkles(tabId: string)
	UIKit.StopTweens(ActiveTweens)
	for _, card in ipairs(TabCards[tabId] or {}) do
		UIKit.StartTwinkles(card.Twinkles, ActiveTweens)
	end
end

local function rebuildSellTab()
	local stacks = collectStacks()
	local parts = {}
	for _, st in ipairs(stacks) do
		table.insert(parts, st.Key .. "=" .. st.Count)
	end
	local signature = table.concat(parts, ";") .. "|" .. State.BagValue
	if signature == SellSignature then
		return
	end
	SellSignature = signature
	clearTab("Sell")
	local rng = Random.new(5204)

	if #stacks > 0 then
		-- Первая карточка — «Продать всё»
		local all = makeCard("Sell", "All", 0, UI.Gold, rng)
		addTag(all, "ВСЁ СРАЗУ", UI.Gold, false)
		UIKit.Label(all.Preview, { Text = "💰", TextSize = 62, ZIndex = 6 })
		all.Title.Text = "Продать всю руду"
		local total = 0
		for _, st in ipairs(stacks) do
			total += st.Count
		end
		all.Line1.Text = string.format("📦 В рюкзаке: %d шт.", total)
		all.Line2.Text = "Бусты и престиж увеличивают выручку"
		setButton(all, "ПРОДАТЬ · 🪙 " .. UIKit.FormatCoins(State.BagValue), UI.Green, UI.GreenDark)
		all.Button.Activated:Connect(function()
			UIKit.PlaySfx("Click")
			ShopAction:FireServer("SellOre", "All")
		end)
	end

	for order, st in ipairs(stacks) do
		local info: any = GameConfig.BLOCK_TYPES[st.OreId]
		local rarity = GameConfig.RARITY[GameConfig.ORE_CATEGORY_RARITY[info.Category] or 1] or GameConfig.RARITY[1]
		local color = st.Morning and UI.Gold or rarity.Color
		local card = makeCard("Sell", st.Key, order, color, rng)
		addTag(card, st.Morning and "УТРЕННЯЯ ×3" or rarity.Name, color, false)
		addTag(card, "×" .. st.Count, color, true)
		local icon = GameConfig.ORE_ICON
		addModelPreview(card, OreIconModels.Build(st.OreId), icon.Center, icon.CameraDistance, icon.CameraHeight, order * 0.7)
		card.Title.Text = GameConfig.GetOreNameRu(st.OreId)
		card.Line1.Text = string.format("×%d  ·  🪙 %s/шт", st.Count, UIKit.FormatCoins(st.UnitPrice))
		card.Line2.Text = st.Morning and "Утренняя жила: цена ×3" or "Обычная руда"
		setButton(card, "ПРОДАТЬ · 🪙 " .. UIKit.FormatCoins(st.Count * st.UnitPrice), UI.Green, UI.GreenDark)
		local key = st.Key
		card.Button.Activated:Connect(function()
			UIKit.PlaySfx("Click")
			ShopAction:FireServer("SellOre", key)
		end)
	end

	if IsOpen and ActiveTab == "Sell" then
		registerSpin("Sell")
		startTwinkles("Sell")
		emptyLabel.Visible = #stacks == 0
	end
end

-- ---------------------------------------------------------------------------
-- Переключение вкладок и обновление
-- ---------------------------------------------------------------------------
local function refreshActiveTab()
	coinsLabel.Text = "🪙 " .. UIKit.FormatCoins(State.Coins)
	if ActiveTab == "Pickaxes" or ActiveTab == "Backpacks" then
		refreshGearTab(ActiveTab)
	elseif ActiveTab == "Boosts" then
		refreshBoostTab()
	elseif ActiveTab == "Sell" then
		rebuildSellTab()
	end
end

local function switchTab(tabId: string)
	if not TabFrames[tabId] then
		return
	end
	ActiveTab = tabId
	for id, frame in pairs(TabFrames) do
		frame.Parent = if id == tabId then scroll else nil
	end
	for id, tab in pairs(TabButtons) do
		local active = id == tabId
		tab.Button.BackgroundTransparency = active and 0 or 0.45
		tab.Stroke.Transparency = active and 0 or 0.6
		tab.Button.TextColor3 = active and Color3.new(1, 1, 1) or UI.TextDim
	end
	scroll.CanvasPosition = Vector2.zero
	emptyLabel.Text = "Рюкзак пуст — иди в шахту! ⛏️"
	emptyLabel.Visible = false
	refreshActiveTab()
	if tabId == "Sell" then
		emptyLabel.Visible = #TabCards.Sell == 0
	end
	if IsOpen then
		registerSpin(tabId)
		startTwinkles(tabId)
	end
end

for order, tab in ipairs(CFG.Tabs) do
	local frame = UIKit.Frame(scroll, "Tab_" .. tab.Id, UDim2.new(1, -10, 0, 0), UDim2.new(), nil, 1)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = nil
	frame.ZIndex = 3
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD.X, CARD.Y)
	grid.CellPadding = UDim2.fromOffset(12, 14)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.Parent = frame
	TabFrames[tab.Id] = frame
	TabCards[tab.Id] = {}

	local btn = Instance.new("TextButton")
	btn.Name = "Tab_" .. tab.Id
	btn.Size = UDim2.new(1 / #CFG.Tabs, -8, 1, 0)
	btn.LayoutOrder = order
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BorderSizePixel = 0
	btn.Font = UI.FontBlack
	btn.TextSize = 16
	btn.Text = tab.Icon .. " " .. tab.Title
	btn.ZIndex = 4
	btn.Parent = tabBar
	UIKit.Corner(btn, 12)
	UIKit.Gradient(btn, tab.Color, tab.Color:Lerp(Color3.new(0, 0, 0), 0.5), 90)
	local stroke = UIKit.Stroke(btn, tab.Color:Lerp(Color3.new(1, 1, 1), 0.4), 2)
	TabButtons[tab.Id] = { Button = btn, Stroke = stroke }
	btn.Activated:Connect(function()
		if ActiveTab ~= tab.Id then
			UIKit.PlaySfx("Tab")
			switchTab(tab.Id)
		end
	end)
end

buildGearTab("Pickaxes")
buildGearTab("Backpacks")
buildBoostTab()

-- ---------------------------------------------------------------------------
-- Открытие / закрытие
-- ---------------------------------------------------------------------------
local function closeShop()
	if not IsOpen then
		return
	end
	IsOpen = false
	OpenToken += 1
	local token = OpenToken
	ClientBus.SetWindowOpen("Shop", false)
	spinner.Stop()
	UIKit.StopTweens(ActiveTweens)
	winScale:SetAttribute("Animating", true)
	TweenService:Create(dim, TweenInfo.new(UI.CloseSeconds), { BackgroundTransparency = 1 }):Play()
	local tw = TweenService:Create(winScale, TweenInfo.new(UI.CloseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = ((winScale:GetAttribute("Fit") :: number?) or 1) * 0.7,
	})
	tw:Play()
	task.delay(UI.CloseSeconds, function()
		if token == OpenToken then
			gui.Enabled = false
			winScale:SetAttribute("Animating", nil)
		end
	end)
end

local function distanceToTrader(): number
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return math.huge
	end
	local c = GameConfig.GREEN_SHOP_PAD_POS
	return Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z).Magnitude
end

local function openShop(tabId: string?)
	if IsOpen then
		if tabId and tabId ~= ActiveTab then
			switchTab(tabId)
		end
		return
	end
	if distanceToTrader() > CFG.AutoCloseDistance then
		UIKit.PlaySfx("Error")
		UIKit.Toast(fxLayer, "Подойди к торговцу Гоше на рынке!", UI.Red)
		return
	end
	pcall(InputBlocker.CloseAllMenus) -- закрываем окна навыков / достижений, если были открыты
	IsOpen = true
	OpenToken += 1
	local token = OpenToken
	ClientBus.SetWindowOpen("Shop", true)
	gui.Enabled = true
	switchTab(tabId or ActiveTab)

	-- Плавное открытие: окно «выпрыгивает» с Back-смягчением
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
	spinner.Start()

	-- Один лёгкий цикл на время, пока окно открыто: блики, таймеры бустов, уход от прилавка
	task.spawn(function()
		local sinceShine = UI.ShineInterval - 0.5
		while IsOpen and token == OpenToken do
			task.wait(0.25)
			if not IsOpen or token ~= OpenToken then
				break
			end
			if distanceToTrader() > CFG.AutoCloseDistance then
				closeShop()
				break
			end
			if ActiveTab == "Boosts" then
				refreshBoostTab()
			end
			sinceShine += 0.25
			if sinceShine >= UI.ShineInterval then
				sinceShine = 0
				for i, card in ipairs(TabCards[ActiveTab] or {}) do
					UIKit.PlayShine(card.Shine, (i - 1) * 0.07)
				end
			end
		end
	end)
end

closeBtn.Activated:Connect(function()
	UIKit.PlaySfx("Click")
	closeShop()
end)
dim.Activated:Connect(closeShop)
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Escape and IsOpen then
		closeShop()
	end
end)

ClientBus.OpenShop.Event:Connect(function(tabId: any)
	openShop(type(tabId) == "string" and tabId or nil)
end)
ClientBus.CloseShop.Event:Connect(closeShop)
ClientBus.CloseAll.Event:Connect(closeShop)
ClientBus.ToggleBag.Event:Connect(closeShop) -- открыли рюкзак — магазин закрывается

-- ProximityPrompt торговца Гоши («E — Открыть магазин»)
local function hookPrompt(inst: Instance)
	if inst:IsA("ProximityPrompt") and not inst:GetAttribute("ShopHooked") then
		inst:SetAttribute("ShopHooked", true)
		inst.Triggered:Connect(function(who: Player)
			if who == player then
				openShop(nil)
			end
		end)
	end
end
for _, inst in ipairs(CollectionService:GetTagged("TraderShopPrompt")) do
	hookPrompt(inst)
end
CollectionService:GetInstanceAddedSignal("TraderShopPrompt"):Connect(hookPrompt)

-- ---------------------------------------------------------------------------
-- Данные и ответы сервера
-- ---------------------------------------------------------------------------
local function toOwnedSet(list: any, fallback: any): { [number]: boolean }
	local set: { [number]: boolean } = {}
	if type(list) == "table" then
		for _, lvl in ipairs(list) do
			if type(lvl) == "number" then
				set[lvl] = true
			end
		end
	elseif type(fallback) == "table" then
		for k, v in pairs(fallback) do
			local lvl = tonumber(k)
			if lvl and v == true then
				set[lvl] = true
			end
		end
	end
	return set
end

SyncPlayerData.OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" then
		return
	end
	State.Coins = tonumber(data.Coins) or State.Coins
	State.PickaxeTier = tonumber(data.PickaxeTier) or State.PickaxeTier
	State.BackpackLevel = tonumber(data.BackpackLevel) or State.BackpackLevel
	State.OwnedPickaxes = toOwnedSet(data.OwnedPickaxes, data.UnlockedPickaxes)
	State.OwnedBackpacks = toOwnedSet(data.OwnedBackpacks, data.UnlockedBackpacks)
	State.OwnedPickaxes[State.PickaxeTier] = true
	State.OwnedBackpacks[State.BackpackLevel] = true
	if type(data.Inventory) == "table" then
		State.Inventory = data.Inventory
	end
	if type(data.MorningInventory) == "table" then
		State.MorningInventory = data.MorningInventory
	end
	State.BagValue = tonumber(data.BagValue) or 0
	if IsOpen then
		refreshActiveTab()
	end
end)

ShopResult.OnClientEvent:Connect(function(ok: any, action: any, info: any)
	if type(action) ~= "string" or type(info) ~= "table" then
		return
	end
	if info.Reason == "Far" then
		failFeedback(nil, "Подойди ближе к торговцу Гоше!")
		return
	end
	if action == "BuyPickaxe" or action == "BuyBackpack" then
		local tabId = action == "BuyPickaxe" and "Pickaxes" or "Backpacks"
		local card = findCard(tabId, tostring(info.Level))
		if ok == true then
			local names = action == "BuyPickaxe" and GameConfig.RU_NAMES.Pickaxes or GameConfig.RU_NAMES.Backpacks
			local name = names[tonumber(info.Level) or 1] or ""
			if info.Outcome == "Bought" then
				successFeedback(card, "✨ Куплено: " .. name .. "!", true)
			else
				successFeedback(card, "Надето: " .. name, false)
			end
		else
			failFeedback(card, "Не хватает монет!")
		end
	elseif action == "BuyBoost" then
		local card = findCard("Boosts", tostring(info.Id))
		local cfg = GameConfig.BOOSTS.Items[tostring(info.Id)]
		if ok == true and cfg then
			successFeedback(card, string.format("%s %s ×%s — осталось %s", cfg.Icon, cfg.Name, tostring(cfg.Multiplier),
				UIKit.FormatTime(tonumber(info.Remaining) or cfg.Duration)), true)
		else
			failFeedback(card, "Не хватает монет!")
		end
	elseif action == "SellOre" then
		if ok == true then
			successFeedback(findCard("Sell", tostring(info.Key)), string.format("💰 Продано %d шт. за %s 🪙",
				tonumber(info.Count) or 0, UIKit.FormatCoins(tonumber(info.Earned) or 0)), true)
		else
			failFeedback(nil, "Нечего продавать — рюкзак пуст!")
		end
	end
end)
