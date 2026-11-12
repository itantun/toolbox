--!strict
-- ============================================================================
-- 🎒 КЛИЕНТ: BackpackUI (StarterPlayerScripts.BackpackUI)
-- v52: окно рюкзака с 3D-иконками руды.
--   • Каждая ячейка — ViewportFrame с моделью руды (камень + кристаллы цвета руды),
--     медленное вращение, подсветка; у светящихся руд — мерцающие «✦».
--   • В ячейке: иконка, название, счётчик «×N», цена за штуку. Пустые ячейки затемнены.
--   • Сверху — полоса вместимости «Занято / Всего», меняющая цвет при заполнении.
--   • Пустой рюкзак показывает подсказку «Иди в шахту!».
-- Открывается кнопкой рюкзака в HUD и клавишами B / I (через ClientBus.ToggleBag).
-- Вращение и мерцание работают только пока окно открыто.
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
local OreIconModels = require(Modules:WaitForChild("OreIconModels"))
local InputBlocker = require(Modules:WaitForChild("InputBlocker"))

local SyncPlayerData = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SyncPlayerData") :: RemoteEvent

local UI = GameConfig.UI
local CFG = GameConfig.BACKPACK_UI
local WIN = CFG.WindowSize
local SLOT = CFG.SlotSize

local State = {
	Inventory = {} :: { [string]: number },
	MorningInventory = {} :: { [string]: number },
	BagUsed = 0,
	BagMax = GameConfig.BASE_BACKPACK_SLOTS,
	BagValue = 0,
	BackpackLevel = 1,
	DirtBlocks = 0,
}

type Slot = {
	Root: Frame,
	Count: TextLabel,
	Price: TextLabel,
	Spin: UIKit.SpinItem?,
	Twinkles: { TextLabel },
}

local IsOpen = false
local OpenToken = 0
local Slots: { [string]: Slot } = {}
local EmptySlots: { Frame } = {}
local ActiveTweens: { Tween } = {}
local LayoutSignature = ""

-- ---------------------------------------------------------------------------
-- Каркас окна
-- ---------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "BackpackV52"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 29
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

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
window.Active = true
window.ZIndex = 2
UIKit.Corner(window, 22)
UIKit.Gradient(window, UI.BgTop, UI.BgBottom, 90)
local windowStroke = UIKit.Stroke(window, Color3.new(1, 1, 1), 3)
UIKit.Gradient(windowStroke, UI.Green, UI.Blue, 35)
local winScale = Instance.new("UIScale")
winScale.Parent = window
UIKit.BindScale(winScale, WIN.X, WIN.Y, 1.1)

UIKit.Label(window, {
	Name = "Title", Text = "🎒 РЮКЗАК", Size = UDim2.new(0, 300, 0, 38), Position = UDim2.fromOffset(24, 12),
	Font = UI.FontTitle, TextSize = 27, XAlign = Enum.TextXAlignment.Left, Color = UI.Green, Stroke = true, ZIndex = 3,
})
local subtitle = UIKit.Label(window, {
	Name = "Subtitle", Text = "", Size = UDim2.new(1, -120, 0, 16), Position = UDim2.fromOffset(26, 48),
	TextSize = 12, XAlign = Enum.TextXAlignment.Left, Color = UI.TextDim, ZIndex = 3,
})

local closeBtn = UIKit.Button(window, "Close", "✕", UDim2.fromOffset(40, 40), UDim2.new(1, -56, 0, 14), UI.Red, UI.RedDark)
closeBtn.TextSize = 20
closeBtn.ZIndex = 4

-- Полоса вместимости
local barBack = UIKit.Frame(window, "CapacityBar", UDim2.new(1, -48, 0, 30), UDim2.fromOffset(24, 74), UI.SlotEmpty)
barBack.ZIndex = 3
UIKit.Corner(barBack, 15)
UIKit.Stroke(barBack, UI.PanelLight, 2)
local barFill = UIKit.Frame(barBack, "Fill", UDim2.fromScale(0, 1), UDim2.new(), CFG.BarOk)
barFill.ZIndex = 4
UIKit.Corner(barFill, 15)
local barGloss = UIKit.Gradient(barFill, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170), 90)
barGloss.Name = "Gloss"
local barText = UIKit.Label(barBack, {
	Name = "Text", Text = "0 / 10", Font = UI.FontBlack, TextSize = 15, Stroke = true, ZIndex = 5,
})

-- Сетка ячеек
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Slots"
scroll.Size = UDim2.new(1, -32, 1, -174)
scroll.Position = UDim2.fromOffset(16, 114)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = UI.Green
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ZIndex = 3
scroll.Parent = window
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(SLOT.X, SLOT.Y)
grid.CellPadding = UDim2.fromOffset(10, 10)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.Parent = scroll
local gridPad = Instance.new("UIPadding")
gridPad.PaddingTop = UDim.new(0, 6)
gridPad.PaddingBottom = UDim.new(0, 8)
gridPad.Parent = scroll

-- Подсказка для пустого рюкзака
local hint = UIKit.Label(window, {
	Name = "EmptyHint", Text = "⛏️ Иди в шахту!", Size = UDim2.new(1, -80, 0, 44), Position = UDim2.new(0, 40, 0.5, -10),
	Font = UI.FontTitle, TextSize = 34, Color = UI.Gold, Stroke = true, ZIndex = 9,
})
local hintSub = UIKit.Label(window, {
	Name = "EmptyHintSub", Text = "Добытая руда появится в этих ячейках", Size = UDim2.new(1, -80, 0, 20),
	Position = UDim2.new(0, 40, 0.5, 36), TextSize = 14, Color = UI.TextDim, ZIndex = 9,
})

local footer = UIKit.Label(window, {
	Name = "Footer", Text = "", Size = UDim2.new(1, -48, 0, 40), Position = UDim2.new(0, 24, 1, -52),
	TextSize = 13, Color = UI.Green, Wrapped = true, ZIndex = 3,
})

local spinner = UIKit.NewSpinner(CFG.IconSpinSeconds, scroll)

-- ---------------------------------------------------------------------------
-- Ячейки
-- ---------------------------------------------------------------------------
type Stack = { Key: string, OreId: string, Count: number, UnitPrice: number, Morning: boolean }

local function collectStacks(): { Stack }
	local stacks: { Stack } = {}
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
		local va, vb = a.Count * a.UnitPrice, b.Count * b.UnitPrice
		if va ~= vb then
			return va > vb
		end
		return a.Key < b.Key
	end)
	return stacks
end

local function makeSlot(stack: Stack, order: number): Slot
	local info: any = GameConfig.BLOCK_TYPES[stack.OreId]
	local rarity = GameConfig.RARITY[GameConfig.ORE_CATEGORY_RARITY[info.Category] or 1] or GameConfig.RARITY[1]
	local color = stack.Morning and UI.Gold or rarity.Color

	local root = UIKit.Frame(scroll, "Slot_" .. stack.Key, UDim2.fromOffset(SLOT.X, SLOT.Y), UDim2.new(), Color3.new(1, 1, 1))
	root.LayoutOrder = order
	root.ZIndex = 3
	UIKit.Corner(root, 14)
	UIKit.Gradient(root, UI.Slot:Lerp(color, 0.16), UI.BgBottom, 90)
	local stroke = UIKit.Stroke(root, Color3.new(1, 1, 1), 2, 0.1)
	UIKit.Gradient(stroke, color:Lerp(Color3.new(1, 1, 1), 0.3), color:Lerp(Color3.new(0, 0, 0), 0.3), 60)

	-- 3D-иконка руды
	local vp, cam, world = UIKit.Viewport(root, "Icon", UDim2.new(1, -12, 0, 92), UDim2.fromOffset(6, 6))
	vp.ZIndex = 4
	local model = OreIconModels.Build(stack.OreId)
	model.Parent = world
	if model:GetAttribute("Glow") == true then
		vp.Ambient = Color3.fromRGB(190, 190, 215) -- светящиеся руды подсвечены ярче
	end
	local icon = GameConfig.ORE_ICON
	local spin: UIKit.SpinItem = {
		Viewport = vp, Camera = cam, Center = icon.Center, Distance = icon.CameraDistance, Height = icon.CameraHeight, Phase = order * 0.8,
	}
	UIKit.OrbitCamera(spin, 0)

	-- блёстки для светящихся руд и утренних жил (частицы во ViewportFrame не рисуются)
	local twinkles: { TextLabel } = {}
	if model:GetAttribute("Glow") == true or stack.Morning then
		twinkles = UIKit.AddTwinkles(vp, 3, stack.Morning and UI.Gold or info.AccentColor, Random.new(order * 97 + 11), 6)
	end

	local count = UIKit.Label(root, {
		Name = "Count", Text = "×" .. stack.Count, Size = UDim2.fromOffset(70, 22), Position = UDim2.new(1, -76, 0, 6),
		Font = UI.FontBlack, TextSize = 17, XAlign = Enum.TextXAlignment.Right, Stroke = true, ZIndex = 7,
	})
	if stack.Morning then
		local tag = UIKit.Frame(root, "MorningTag", UDim2.fromOffset(44, 18), UDim2.fromOffset(6, 6), UI.Gold:Lerp(Color3.new(0, 0, 0), 0.4))
		tag.ZIndex = 7
		UIKit.Corner(tag, 9)
		UIKit.Label(tag, { Text = "🌅 ×3", Font = UI.FontBlack, TextSize = 10, Color = UI.Gold, ZIndex = 8 })
	end
	local name = UIKit.Label(root, {
		Name = "Name", Text = GameConfig.GetOreNameRu(stack.OreId), Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 100),
		Font = UI.FontBlack, TextSize = 13, Color = color:Lerp(Color3.new(1, 1, 1), 0.55), ZIndex = 5,
	})
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local price = UIKit.Label(root, {
		Name = "Price", Text = "", Size = UDim2.new(1, -8, 0, 30), Position = UDim2.fromOffset(4, 122),
		TextSize = 12, Color = UI.Gold, Wrapped = true, ZIndex = 5,
	})

	return { Root = root, Count = count, Price = price, Spin = spin, Twinkles = twinkles }
end

local function fillSlot(slot: Slot, stack: Stack, order: number)
	slot.Root.LayoutOrder = order
	slot.Count.Text = "×" .. stack.Count
	slot.Price.Text = string.format("🪙 %s/шт\nвсего %s", UIKit.FormatCoins(stack.UnitPrice), UIKit.FormatCoins(stack.Count * stack.UnitPrice))
end

local function makeEmptySlot(order: number): Frame
	local root = UIKit.Frame(scroll, "Empty", UDim2.fromOffset(SLOT.X, SLOT.Y), UDim2.new(), UI.SlotEmpty, 0.25)
	root.LayoutOrder = order
	root.ZIndex = 3
	UIKit.Corner(root, 14)
	UIKit.Stroke(root, UI.PanelLight, 1.5, 0.6)
	UIKit.Label(root, { Text = "＋", TextSize = 30, Color = UI.PanelLight, ZIndex = 4 })
	return root
end

local function registerEffects()
	spinner.Clear()
	UIKit.StopTweens(ActiveTweens)
	for _, slot in pairs(Slots) do
		local spin = slot.Spin
		if spin then
			spinner.Add(spin)
		end
		UIKit.StartTwinkles(slot.Twinkles, ActiveTweens)
	end
end

-- Перестраиваем сетку только когда меняется НАБОР стопок; иначе обновляем числа
local function refresh()
	local stacks = collectStacks()
	local keys = {}
	for _, st in ipairs(stacks) do
		table.insert(keys, st.Key)
	end
	local signature = table.concat(keys, ";")

	if signature ~= LayoutSignature then
		LayoutSignature = signature
		local alive: { [string]: boolean } = {}
		for order, st in ipairs(stacks) do
			alive[st.Key] = true
			local slot = Slots[st.Key]
			if not slot then
				slot = makeSlot(st, order)
				Slots[st.Key] = slot
			end
			fillSlot(slot, st, order)
		end
		for key, slot in pairs(Slots) do
			if not alive[key] then
				slot.Root:Destroy()
				Slots[key] = nil
			end
		end
		-- пустые затемнённые ячейки добивают сетку до минимума и до целого ряда
		for _, f in ipairs(EmptySlots) do
			f:Destroy()
		end
		table.clear(EmptySlots)
		local columns = math.max(1, math.floor((WIN.X - 32 + 10) / (SLOT.X + 10)))
		local total = math.max(CFG.MinSlots, math.ceil(#stacks / columns) * columns)
		for i = #stacks + 1, total do
			table.insert(EmptySlots, makeEmptySlot(1000 + i))
		end
		if IsOpen then
			registerEffects()
		end
	else
		for order, st in ipairs(stacks) do
			local slot = Slots[st.Key]
			if slot then
				fillSlot(slot, st, order)
			end
		end
	end

	-- Полоса вместимости: зелёная -> жёлтая -> красная
	local ratio = math.clamp(State.BagUsed / math.max(1, State.BagMax), 0, 1)
	local barColor = (ratio >= CFG.FullRatio and CFG.BarFull) or (ratio >= CFG.WarnRatio and CFG.BarWarn) or CFG.BarOk
	TweenService:Create(barFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = barColor,
	}):Play()
	barFill.Visible = ratio > 0.001
	barText.Text = string.format("%d / %d%s", State.BagUsed, State.BagMax, ratio >= 1 and "  ·  ПОЛНЫЙ!" or "")

	local empty = #stacks == 0
	hint.Visible = empty
	hintSub.Visible = empty

	local bagName = GameConfig.RU_NAMES.Backpacks[State.BackpackLevel] or ""
	local penalty = math.floor(GameConfig.GetDirtPenalty(State.DirtBlocks) * 100 + 0.5)
	subtitle.Text = bagName .. (penalty > 0 and string.format("  ·  грязь: −%d%% мест", penalty) or "  ·  чистый")
	footer.Text = empty and "Руду можно продать торговцу Гоше на рынке или в зоне $ SELL"
		or string.format("💰 Всё содержимое стоит %s 🪙 — продай торговцу Гоше или в зоне $ SELL", UIKit.FormatCoins(State.BagValue))
end

-- ---------------------------------------------------------------------------
-- Открытие / закрытие
-- ---------------------------------------------------------------------------
local function closeBag()
	if not IsOpen then
		return
	end
	IsOpen = false
	OpenToken += 1
	local token = OpenToken
	ClientBus.SetWindowOpen("Bag", false)
	spinner.Stop()
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

local function openBag()
	if IsOpen then
		return
	end
	pcall(InputBlocker.CloseAllMenus)
	IsOpen = true
	OpenToken += 1
	local token = OpenToken
	ClientBus.SetWindowOpen("Bag", true)
	gui.Enabled = true
	refresh()
	registerEffects()

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
end

closeBtn.Activated:Connect(function()
	UIKit.PlaySfx("Click")
	closeBag()
end)
dim.Activated:Connect(closeBag)
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Escape and IsOpen then
		closeBag()
	end
end)

ClientBus.ToggleBag.Event:Connect(function()
	if IsOpen then
		closeBag()
	else
		openBag()
	end
end)
ClientBus.CloseAll.Event:Connect(closeBag)
ClientBus.OpenShop.Event:Connect(closeBag) -- открыли магазин — рюкзак закрывается

SyncPlayerData.OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.Inventory) == "table" then
		State.Inventory = data.Inventory
	end
	if type(data.MorningInventory) == "table" then
		State.MorningInventory = data.MorningInventory
	end
	State.BagUsed = tonumber(data.BagUsed) or 0
	State.BagMax = tonumber(data.BagMax) or State.BagMax
	State.BagValue = tonumber(data.BagValue) or 0
	State.BackpackLevel = tonumber(data.BackpackLevel) or State.BackpackLevel
	State.DirtBlocks = tonumber(data.DirtBlocks) or 0
	if IsOpen then
		refresh()
	end
end)
