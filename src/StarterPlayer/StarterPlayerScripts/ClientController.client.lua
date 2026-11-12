--!strict
-- ============================================================================
-- 🎮 КЛИЕНТСКИЙ КОНТРОЛЛЕР: ClientController (StarterPlayerScripts / StarterGui)
-- Версия: v13.0 — Полная реализация всех 13 пунктов ТЗ:
-- 1) Синхронная анимация правой руки и кирки через ToolAnimator + скорость от уровня кирки.
-- 2) Динамический Рюкзак: кастомные иконки «камень с вкраплениями», показываются ТОЛЬКО
--    реально добытые руды (count > 0, пустых слотов нет!), 3 режима сортировки
--    (по стоимости / по количеству / по глубине), категории (Обычная / Редкая / Утренняя ×3).
-- 3) Нижняя кнопка «💰 К продаже» (v14): мгновенный телепорт в зону автопродажи (кулдаун 4с).
-- 4) Современный 3D-Магазин с 2 вкладками: «⛏️ Кирки (1–10 ур.)» и «🎒 Рюкзаки (1–10 ур.)»,
--    3D ViewportFrame-просмотром, свайпом влево/вправо на телефоне, стрелками и колесом мыши на ПК!
--    Никакой тренировки силы или вместимости навыками в магазине нет!
-- 5) Панель продажи в зоне «$ SELL» с кнопками «Продать всё» и «Продать выбранное».
-- ============================================================================

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then return end

if player:GetAttribute("MinerClientV8Active") then
	return
end
player:SetAttribute("MinerClientV8Active", true)

-- v14: стандартный список игроков Roblox справа сверху перекрыл бы пилюлю монет (как на референсе её нет)
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then break end
		task.wait(0.5)
	end
end)

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local OreConfig = require(Modules:WaitForChild("OreConfig"))
local SoundManager = require(Modules:WaitForChild("SoundManager"))
local VFXModule = require(Modules:WaitForChild("VFXModule"))
local HudModule = require(Modules:WaitForChild("HudModule"))
local EquipmentBuilder = require(Modules:WaitForChild("EquipmentBuilder"))
local ToolAnimator = require(Modules:WaitForChild("ToolAnimator"))
ToolAnimator.Start()

SoundManager.EnsureSoundsFolder()

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local MineBlockRemote       = remotesFolder:WaitForChild("MineBlock") :: RemoteEvent
local BuyPickaxeRemote      = remotesFolder:WaitForChild("BuyPickaxe") :: RemoteEvent
local BuyBackpackRemote     = remotesFolder:WaitForChild("BuyBackpack") :: RemoteEvent
local SellNotifyRemote      = remotesFolder:WaitForChild("SellNotify") :: RemoteEvent   -- v14: «+XXX монет» после автопродажи
local TeleportToSpawnRemote = remotesFolder:WaitForChild("TeleportToSpawn") :: RemoteEvent
local TeleportToShopRemote = remotesFolder:WaitForChild("TeleportToShop") :: RemoteEvent -- v27: Shop button teleports to the shop
local SyncPlayerData        = remotesFolder:WaitForChild("SyncPlayerData") :: RemoteEvent
local DayNightEvent         = remotesFolder:WaitForChild("DayNightEvent") :: RemoteEvent

local State = {
	Coins = 0,
	Level = 1,
	XP = 0,
	RequiredXP = 100,
	Strength = GameConfig.BASE_STRENGTH,
	StrengthXP = 0,
	RequiredStrengthXP = 35,
	Energy = GameConfig.ENERGY.BaseMax,
	MaxEnergy = GameConfig.ENERGY.BaseMax,
	EnergyRegen = GameConfig.ENERGY.PassiveRegenPerSec,
	HitDamage = 6,
	PickaxeTier = 1,
	UnlockedPickaxes = { [1] = true } :: { [number]: boolean },
	BackpackLevel = 1,
	UnlockedBackpacks = { [1] = true } :: { [number]: boolean },
	BagUsed = 0,
	BagMax = GameConfig.BASE_BACKPACK_SLOTS,
	BagValue = 0,
	MaxDepthReached = 0,
	Inventory = {} :: { [string]: number },
	MorningInventory = {} :: { [string]: number },
	AttackCooldown = 0.48,
	Prestige = 0,
}

-- ============================================================================
-- 1. БАЗОВЫЕ UI-УТИЛИТЫ
-- ============================================================================
local playerGui = player:WaitForChild("PlayerGui")
for _, name in ipairs({"MinerSimulatorHUD", "MinerSimulatorHUD_v5", "MinerSimulatorHUD_v6", "MinerSimulatorHUD_v7", "MinerSimulatorHUD_v8"}) do
	local old = playerGui:FindFirstChild(name)
	if old then old:Destroy() end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MinerSimulatorHUD_v8"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local function makeModernPanel(name: string, size: UDim2, pos: UDim2, strokeCol: Color3, parent: Instance?): Frame
	-- v24: wooden panel with a gold rim (reference style)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 0.04
	f.Parent = parent or screenGui

	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 16)

	local grad = Instance.new("UIGradient", f)
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(124, 80, 44)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(94, 59, 32)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 37, 20)),
	})
	grad.Rotation = 90

	local st = Instance.new("UIStroke", f)
	st.Color = Color3.fromRGB(40, 24, 12)
	st.Thickness = 3.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local rim = Instance.new("Frame")
	rim.Name = "GoldRim"
	rim.BackgroundTransparency = 1
	rim.Size = UDim2.new(1, -8, 1, -8)
	rim.Position = UDim2.fromOffset(4, 4)
	rim.Parent = f
	Instance.new("UICorner", rim).CornerRadius = UDim.new(0, 12)
	local rs = Instance.new("UIStroke", rim)
	rs.Color = Color3.fromRGB(255, 200, 80):Lerp(strokeCol, 0.3)
	rs.Thickness = 2
	rs.Transparency = 0.1
	return f
end

local function makeLabel(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	text: string,
	color: Color3,
	fontSize: number?,
	alignX: Enum.TextXAlignment?
): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.Size = size
	lbl.Position = pos
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = fontSize or 15
	lbl.TextColor3 = color
	lbl.TextXAlignment = alignX or Enum.TextXAlignment.Left
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

-- Vector close cross: the font glyphs "✕"/"✖" render as empty boxes in GothamBlack.
local function vecCross(btn: TextButton)
	btn.Text = ""
	btn:SetAttribute("CloseX", true)
	if btn:FindFirstChild("XCross") then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = "XCross"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(0.6, 0.6)
	holder.ZIndex = btn.ZIndex + 2
	holder.Active = false
	for pass = 1, 2 do
		for _, rot in ipairs({ 45, -45 }) do
			local bar = Instance.new("Frame")
			bar.Name = "XBar"
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.fromScale(1.08, 0.26)
			bar.Rotation = rot
			bar.BackgroundColor3 = Color3.new(1, 1, 1)
			bar.ZIndex = pass
			bar.Active = false
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0.5, 0)
			bc.Parent = bar
			if pass == 1 then
				local bs = Instance.new("UIStroke")
				bs.Color = Color3.fromRGB(110, 6, 18)
				bs.Thickness = 2.5
				bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				bs.Parent = bar
			else
				local bg = Instance.new("UIGradient")
				bg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 214, 214))
				bg.Rotation = 90 - rot
				bg.Parent = bar
			end
			bar.Parent = holder
		end
	end
	holder.Parent = btn
end

-- Vector arrow chevron ("◀"/"▶" glyphs are missing in GothamBlack)
local function vecChevron(b: TextButton, dir: number)
	b.Text = ""
	for _, sgn in ipairs({ -1, 1 }) do
		local bar = Instance.new("Frame")
		bar.Name = "Chevron"
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, 0, 0.5, sgn * 8)
		bar.Size = UDim2.fromOffset(34, 11)
		bar.Rotation = sgn * 35 * -dir
		bar.BackgroundColor3 = Color3.fromRGB(54, 60, 76)
		bar.ZIndex = b.ZIndex + 1
		bar.Active = false
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = bar
		bar.Parent = b
	end
end

local function makeButton(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	text: string,
	accentColor: Color3,
	onClick: () -> ()
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = size
	btn.Position = pos
	btn.BackgroundColor3 = Color3.fromRGB(38, 42, 54)
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 14
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = text
	btn.AutoButtonColor = true
	btn.Parent = parent

	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
	local grad = Instance.new("UIGradient", btn)
	grad.Color = ColorSequence.new(accentColor, accentColor:Lerp(Color3.new(0, 0, 0), 0.35))
	grad.Rotation = 90

	local st = Instance.new("UIStroke", btn)
	st.Color = accentColor:Lerp(Color3.new(0, 0, 0), 0.6)
	st.Thickness = 2.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	btn.TextStrokeTransparency = 0.35
	btn.TextStrokeColor3 = accentColor:Lerp(Color3.new(0, 0, 0), 0.7)
	-- v24: glossy cartoon highlight
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.82
	gloss.BorderSizePixel = 0
	gloss.Size = UDim2.new(1, -8, 0.42, 0)
	gloss.Position = UDim2.fromOffset(4, 3)
	gloss.Parent = btn
	Instance.new("UICorner", gloss).CornerRadius = UDim.new(0, 9)

	btn.MouseButton1Click:Connect(onClick)
	return btn
end

local function formatCoins(n: number): string
	if n <= 0 then return "FREE" end
	if n >= 1e6 then
		local txt = string.gsub(string.format("%.2fM 💰", n / 1e6), "%.00M", "M")
		return txt
	elseif n >= 1e4 then
		return string.format("%.1fK 💰", n / 1e3)
	end
	return string.format("%d 💰", n)
end

-- ============================================================================
-- 2. КАСТОМНАЯ ИКОНКА РУДЫ («КАМЕНЬ С ВКРАПЛЕНИЯМИ», А НЕ ПРОСТО КВАДРАТ!)
-- Строит многослойную иконку породы с каменной матрицей, сколами и прожилками/друзами.
-- ==============================================================================
local function buildOreMatrixIcon(parent: Instance, bInfo: any, isMorningVein: boolean): Frame
	local holder = Instance.new("Frame")
	holder.Name = "OreMatrixIcon"
	holder.Size = UDim2.fromOffset(54, 54)
	holder.Position = UDim2.new(0, 10, 0.5, -27)
	holder.BackgroundColor3 = isMorningVein and Color3.fromRGB(68, 52, 22) or bInfo.Color:Lerp(Color3.new(0, 0, 0), 0.28)
	holder.Parent = parent
	Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 12)

	local st = Instance.new("UIStroke", holder)
	st.Color = isMorningVein and Color3.fromRGB(255, 215, 65) or bInfo.AccentColor
	st.Thickness = isMorningVein and 2.5 or 1.8

	-- Внутренняя глыба каменной породы со скошенным углом
	local rock = Instance.new("Frame", holder)
	rock.Name = "RockCore"
	rock.Size = UDim2.fromOffset(40, 40)
	rock.Position = UDim2.fromOffset(7, 7)
	rock.Rotation = 8
	rock.BackgroundColor3 = bInfo.Color
	Instance.new("UICorner", rock).CornerRadius = UDim.new(0, 9)

	local rGrad = Instance.new("UIGradient", rock)
	rGrad.Color = ColorSequence.new(bInfo.Color:Lerp(Color3.new(1, 1, 1), 0.14), bInfo.Color:Lerp(Color3.new(0, 0, 0), 0.25))
	rGrad.Rotation = 45

	-- 5 вкраплений / прожилок / кристаллов внутри каменной матрицы!
	local specks = {
		{ x = 6,  y = 8,  w = 11, h = 5,  rot = -22 },
		{ x = 22, y = 7,  w = 9,  h = 9,  rot = 35  },
		{ x = 13, y = 18, w = 14, h = 6,  rot = 14  },
		{ x = 7,  y = 27, w = 10, h = 6,  rot = -30 },
		{ x = 23, y = 24, w = 11, h = 8,  rot = 48  },
	}
	for i, sp in ipairs(specks) do
		local fleck = Instance.new("Frame", rock)
		fleck.Name = "Inclusion_" .. i
		fleck.Size = UDim2.fromOffset(sp.w, sp.h)
		fleck.Position = UDim2.fromOffset(sp.x, sp.y)
		fleck.Rotation = sp.rot
		local useSec = (bInfo.SecondaryAccent ~= nil) and (i % 2 == 0)
		if isMorningVein and i == 3 then
			fleck.BackgroundColor3 = Color3.fromRGB(255, 225, 75)
		else
			fleck.BackgroundColor3 = useSec and bInfo.SecondaryAccent or bInfo.AccentColor
		end
		Instance.new("UICorner", fleck).CornerRadius = UDim.new(0, 3)
	end

	-- Маленький значок в правом нижнем углу иконки
	local miniBadge = makeLabel(
		holder,
		"MiniEmoji",
		UDim2.fromOffset(20, 20),
		UDim2.new(1, -18, 1, -18),
		isMorningVein and "🌅" or bInfo.Icon,
		Color3.new(1, 1, 1),
		13,
		Enum.TextXAlignment.Center
	)
	miniBadge.ZIndex = 4

	return holder
end

-- ============================================================================
-- 3. ВЕРХНИЙ ИНДИКАТОР ВРЕМЕНИ СУТОК, ГЛУБИНЫ И ПОЛОСЫ ЭНЕРГИИ
-- ============================================================================
local hud: any = nil

local clockBadge = makeModernPanel("ClockBadge", UDim2.new(0, 420, 0, 58), UDim2.new(0.5, -210, 0, 96), Color3.fromRGB(85, 225, 155), screenGui)
local clockLbl = makeLabel(clockBadge, "ClockText", UDim2.new(1, -16, 0, 20), UDim2.new(0, 8, 0, 4), "Day · Depth: 0 / 30 m (Surface)", Color3.fromRGB(255, 235, 115), 13, Enum.TextXAlignment.Center)
-- v25: navy glowing HUD plate (reference screenshot style)
local function styleNavy(f: Frame, accent: Color3)
	local g = f:FindFirstChildOfClass("UIGradient")
	if g then g.Color = ColorSequence.new(Color3.fromRGB(40, 70, 162), Color3.fromRGB(16, 28, 86)) end
	local st = f:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = accent
		st.Thickness = 3
	end
	local rim = f:FindFirstChild("GoldRim")
	if rim then rim:Destroy() end
	local gl = Instance.new("Frame")
	gl.Name = "Gloss"
	gl.BackgroundColor3 = Color3.new(1, 1, 1)
	gl.BackgroundTransparency = 0.9
	gl.BorderSizePixel = 0
	gl.Size = UDim2.new(1, -12, 0.46, 0)
	gl.Position = UDim2.fromOffset(6, 3)
	gl.Parent = f
	Instance.new("UICorner", gl).CornerRadius = UDim.new(0, 12)
end
styleNavy(clockBadge, Color3.fromRGB(70, 215, 255))
clockLbl.TextColor3 = Color3.new(1, 1, 1)
clockLbl.TextStrokeTransparency = 0.4
clockLbl.TextStrokeColor3 = Color3.fromRGB(10, 18, 50)
-- v26: drawn star (day) / moon (night) instead of emoji, like the reference
local clockStar = HudModule.DrawIcon(clockBadge, "Star", 22, 6)
local clockMoon = HudModule.DrawIcon(clockBadge, "Moon", 20, 6)
if clockStar then clockStar.Position = UDim2.fromOffset(12, 3) end
if clockMoon then
	clockMoon.Position = UDim2.fromOffset(13, 4)
	clockMoon.Visible = false
end
clockLbl.Position = UDim2.new(0, 36, 0, 4)
clockLbl.Size = UDim2.new(1, -48, 0, 20)

local energyBg = Instance.new("Frame", clockBadge)
energyBg.Name = "EnergyBarBg"
energyBg.Size = UDim2.new(1, -24, 0, 18)
energyBg.Position = UDim2.new(0, 12, 0, 30)
energyBg.BackgroundColor3 = Color3.fromRGB(8, 14, 44)
Instance.new("UICorner", energyBg).CornerRadius = UDim.new(1, 0)

local energyFill = Instance.new("Frame", energyBg)
energyFill.Name = "Fill"
energyFill.Size = UDim2.new(1, 0, 1, 0)
energyFill.BackgroundColor3 = Color3.fromRGB(65, 220, 135)
do -- v25: glossy energy bar
	local eg = Instance.new("UIGradient", energyFill)
	eg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 190, 170))
	eg.Rotation = 90
	local es = Instance.new("UIStroke", energyBg)
	es.Color = Color3.fromRGB(150, 255, 170)
	es.Thickness = 1.5
	es.Transparency = 0.3
end
Instance.new("UICorner", energyFill).CornerRadius = UDim.new(1, 0)

local energyLbl = makeLabel(energyBg, "EnergyText", UDim2.new(1, 0, 1, 0), UDim2.new(), "Energy: 100 / 100 (+2.4/s)", Color3.new(1, 1, 1), 11, Enum.TextXAlignment.Center)
do -- v26: drawn lightning bolt at the left end of the energy bar
	local eb = HudModule.DrawIcon(energyBg, "Bolt", 22, 6)
	if eb then eb.Position = UDim2.new(0, 4, 0.5, -11) end
end

local nightBanner = makeModernPanel("NightRespawnBanner", UDim2.new(0, 520, 0, 66), UDim2.new(0.5, -260, 0, -95), Color3.fromRGB(115, 165, 255), screenGui)
nightBanner.Visible = false
nightBanner.ZIndex = 35
styleNavy(nightBanner, Color3.fromRGB(70, 215, 255))
local nightBannerLbl = makeLabel(nightBanner, "BannerText", UDim2.new(1, -24, 1, 0), UDim2.new(0, 12, 0, 0), "Night!", Color3.fromRGB(220, 235, 255), 16, Enum.TextXAlignment.Center)
nightBannerLbl.TextWrapped = true
do -- v26: drawn star on the left of the banner (like the reference), text without emoji
	local bs = HudModule.DrawIcon(nightBanner, "Star", 40, 36)
	if bs then bs.Position = UDim2.new(0, 16, 0.5, -20) end
	nightBannerLbl.Position = UDim2.new(0, 62, 0, 0)
	nightBannerLbl.Size = UDim2.new(1, -76, 1, 0)
end

local BannerToken = 0
local function showBannerNotification(text: string, borderColor: Color3)
	BannerToken += 1
	local token = BannerToken
	local cleanText = string.gsub(text, "^[\128-\255]+%s*", "") -- v26: the drawn star replaces leading emoji
	nightBannerLbl.Text = cleanText
	local st = nightBanner:FindFirstChildOfClass("UIStroke")
	if st then st.Color = borderColor end
	nightBanner.Position = UDim2.new(0.5, -260, 0, -85)
	nightBanner.Visible = true
	TweenService:Create(nightBanner, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -260, 0, 154),
	}):Play()

	task.delay(4.8, function()
		if token ~= BannerToken then return end
		TweenService:Create(nightBanner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, -260, 0, -95),
		}):Play()
		task.wait(0.36)
		if token == BannerToken then nightBanner.Visible = false end
	end)
end

local CurrentDaySec = 360
local CurrentNightSec = 0
local IsNightMode = false
local CurrentDepthBlocks = 0

local function updateClockAndDepthText()
	local band = GameConfig.GetDepthBand(math.max(1, CurrentDepthBlocks))
	local zoneShort = (CurrentDepthBlocks <= 0) and "Surface" or band.ZoneName
	if IsNightMode then
		local m = math.floor(CurrentNightSec / 60)
		local s = CurrentNightSec % 60
		clockLbl.Text = string.format("Night (Mine Closed: %02d:%02d) · %d/30 m", m, s, CurrentDepthBlocks)
		clockLbl.TextColor3 = Color3.fromRGB(255, 145, 125)
		if clockStar then clockStar.Visible = false end -- v26
		if clockMoon then clockMoon.Visible = true end
	else
		local m = math.floor(CurrentDaySec / 60)
		local s = CurrentDaySec % 60
		clockLbl.Text = string.format("Day %02d:%02d · Depth: %d/30 m (%s)", m, s, CurrentDepthBlocks, zoneShort)
		clockLbl.TextColor3 = Color3.fromRGB(255, 235, 115)
		if clockStar then clockStar.Visible = true end -- v26
		if clockMoon then clockMoon.Visible = false end
	end
end

DayNightEvent.OnClientEvent:Connect(function(eventType: string, payload: any)
	if eventType == "DayTick" then
		IsNightMode = false
		CurrentDaySec = tonumber(payload) or 0
		updateClockAndDepthText()
	elseif eventType == "NightTick" then
		IsNightMode = true
		CurrentNightSec = tonumber(payload) or 0
		updateClockAndDepthText()
	elseif eventType == "EveningWarning" then
		showBannerNotification(tostring(payload), Color3.fromRGB(255, 175, 65))
	elseif eventType == "NightStarted" or eventType == "NightEntryBlocked" then
		IsNightMode = true
		updateClockAndDepthText()
		showBannerNotification(tostring(payload), Color3.fromRGB(255, 95, 85))
	elseif eventType == "DayStarted" or eventType == "MorningVeinsSpawned" then
		IsNightMode = false
		updateClockAndDepthText()
		showBannerNotification(tostring(payload), Color3.fromRGB(255, 215, 65))
	end
end)

-- ============================================================================
-- 4. ОБНОВЛЁННЫЙ ДИНАМИЧЕСКИЙ РЮКЗАК / ИНВЕНТАРЬ (ПУНКТЫ №2, №7 И №13 ТЗ)
-- • Отображаются ТОЛЬКО те руды, которых у игрока реально > 0!
-- • Нет пустых ячеек или серых заглушек.
-- • У каждой руды — кастомная иконка «камень с вкраплениями».
-- • Сортировка: «По стоимости», «По количеству», «По глубине».
-- • (v14) Только просмотр содержимого. Продажа — автоматически в зоне «$ SELL».
-- ============================================================================
local bagModal = makeModernPanel("BackpackModal", UDim2.new(0, 620, 0, 440), UDim2.new(0.5, -310, 0.5, -220), Color3.fromRGB(85, 225, 120), screenGui)
bagModal:GetPropertyChangedSignal("Visible"):Connect(function()
	if bagModal.Visible then SoundManager.PlayUISound("UIClick") end -- v24: quiet open sound
end)
bagModal.Visible = false
bagModal.ZIndex = 20

makeLabel(bagModal, "Title", UDim2.new(1, -90, 0, 28), UDim2.new(0, 18, 0, 10), "🎒 BACKPACK", Color3.fromRGB(105, 245, 140), 17)
local bagSummaryLbl = makeLabel(bagModal, "Summary", UDim2.new(1, -40, 0, 18), UDim2.new(0, 18, 0, 38), "Only mined blocks are shown. Morning Veins are worth ×3!", Color3.fromRGB(215, 228, 245), 12)

local bagCloseBtn = makeButton(bagModal, "CloseBtn", UDim2.new(0, 34, 0, 34), UDim2.new(1, -46, 0, 10), "✖", Color3.fromRGB(225, 65, 75), function()
	bagModal.Visible = false
end)
vecCross(bagCloseBtn)

-- Кнопки сортировки (По стоимости / По количеству / По глубине)
local CurrentSortMode = "Value" -- "Value" | "Count" | "Depth"
local SelectedOreKeys: { [string]: boolean } = {}
local rebuildInventorySlots: () -> () = function() end

local sortBar = Instance.new("Frame", bagModal)
sortBar.Size = UDim2.new(1, -36, 0, 32)
sortBar.Position = UDim2.new(0, 18, 0, 60)
sortBar.BackgroundTransparency = 1

makeLabel(sortBar, "SortLbl", UDim2.new(0, 105, 1, 0), UDim2.new(0, 0, 0, 0), "Sort:", Color3.fromRGB(185, 200, 225), 13)

local sortValueBtn = makeButton(sortBar, "SortValue", UDim2.new(0, 145, 0, 28), UDim2.new(0, 108, 0, 2), "💰 By value", Color3.fromRGB(255, 195, 55), function()
	CurrentSortMode = "Value"
	rebuildInventorySlots()
end)
local sortCountBtn = makeButton(sortBar, "SortCount", UDim2.new(0, 150, 0, 28), UDim2.new(0, 262, 0, 2), "📦 By amount", Color3.fromRGB(70, 175, 255), function()
	CurrentSortMode = "Count"
	rebuildInventorySlots()
end)
local sortDepthBtn = makeButton(sortBar, "SortDepth", UDim2.new(0, 145, 0, 28), UDim2.new(0, 420, 0, 2), "⬇️ By depth", Color3.fromRGB(165, 110, 255), function()
	CurrentSortMode = "Depth"
	rebuildInventorySlots()
end)

local slotsScroll = Instance.new("ScrollingFrame", bagModal)
slotsScroll.Size = UDim2.new(1, -36, 1, -158)
slotsScroll.Position = UDim2.new(0, 18, 0, 98)
slotsScroll.BackgroundTransparency = 1
slotsScroll.BorderSizePixel = 0
slotsScroll.ScrollBarThickness = 6
slotsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
slotsScroll.CanvasSize = UDim2.new()

local slotsGrid = Instance.new("UIGridLayout", slotsScroll)
slotsGrid.CellSize = UDim2.new(0, 282, 0, 78)
slotsGrid.CellPadding = UDim2.new(0, 12, 0, 10)
slotsGrid.SortOrder = Enum.SortOrder.LayoutOrder

local emptyBagLabel = makeLabel(
	bagModal,
	"EmptyBagNotice",
	UDim2.new(1, -40, 0, 60),
	UDim2.new(0, 20, 0.5, -20),
	"⛏️ Your backpack is empty.\nGo down into the mine to dig your first ore!",
	Color3.fromRGB(175, 190, 215),
	15,
	Enum.TextXAlignment.Center
)

-- v14: кнопок продажи больше нет. Рюкзак — только просмотр; руда продаётся автоматически в зоне «$ SELL».
local sellInfoLbl = makeLabel(bagModal, "AutoSellInfo", UDim2.new(1, -36, 0, 40), UDim2.new(0, 18, 1, -48),
	"💰 Ore sells automatically: just step into the green $ SELL zone on the surface",
	Color3.fromRGB(120, 245, 170), 13, Enum.TextXAlignment.Center)
sellInfoLbl.TextWrapped = true

rebuildInventorySlots = function()
	for _, child in ipairs(slotsScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	type OreEntry = {
		Key: string,
		BlockInfo: any,
		Count: number,
		UnitPrice: number,
		TotalValue: number,
		IsMorning: boolean,
		DepthOrder: number,
	}

	local entries: { OreEntry } = {}
	for idx, bInfo in ipairs(GameConfig.BLOCK_LIST) do
		local regCnt = State.Inventory[bInfo.Id] or 0
		if regCnt > 0 then
			table.insert(entries, {
				Key = "Reg_" .. bInfo.Id,
				BlockInfo = bInfo,
				Count = regCnt,
				UnitPrice = bInfo.SellPrice,
				TotalValue = regCnt * bInfo.SellPrice,
				IsMorning = false,
				DepthOrder = idx,
			})
		end
		local mornCnt = State.MorningInventory[bInfo.Id] or 0
		if mornCnt > 0 then
			local uPrice = bInfo.SellPrice * GameConfig.MORNING_VEINS.SellPriceMultiplier
			table.insert(entries, {
				Key = "Morn_" .. bInfo.Id,
				BlockInfo = bInfo,
				Count = mornCnt,
				UnitPrice = uPrice,
				TotalValue = mornCnt * uPrice,
				IsMorning = true,
				DepthOrder = idx + 0.5,
			})
		end
	end

	emptyBagLabel.Visible = (#entries == 0)

	table.sort(entries, function(a, b)
		if CurrentSortMode == "Value" then
			if a.TotalValue ~= b.TotalValue then return a.TotalValue > b.TotalValue end
			return a.UnitPrice > b.UnitPrice
		elseif CurrentSortMode == "Count" then
			if a.Count ~= b.Count then return a.Count > b.Count end
			return a.TotalValue > b.TotalValue
		else
			return a.DepthOrder < b.DepthOrder
		end
	end)

	local selectedSum = 0
	local selectedCount = 0

	for orderIdx, entry in ipairs(entries) do
		local bInfo = entry.BlockInfo
		local isSel = false

		local borderCol = entry.IsMorning and Color3.fromRGB(255, 215, 65) or bInfo.AccentColor
		local card = makeModernPanel("Slot_" .. entry.Key, UDim2.new(0, 282, 0, 78), UDim2.new(), isSel and Color3.fromRGB(85, 255, 145) or borderCol, slotsScroll)
		card.LayoutOrder = orderIdx

		-- Кастомная иконка породы с вкраплениями
		buildOreMatrixIcon(card, bInfo, entry.IsMorning)

		local titleText = entry.IsMorning and ("" .. bInfo.Name .. " (Morning ×3)") or bInfo.Name
		local catText = entry.IsMorning and "Morning Vein ×3" or (bInfo.Category or "Block")

		makeLabel(card, "Name", UDim2.new(1, -110, 0, 20), UDim2.new(0, 72, 0, 6), titleText, entry.IsMorning and Color3.fromRGB(255, 225, 85) or bInfo.AccentColor, 13)
		makeLabel(card, "Cat",  UDim2.new(1, -110, 0, 16), UDim2.new(0, 72, 0, 25), string.format("%s · Depth %d–%d m", catText, bInfo.MinDepth, bInfo.MaxDepth), Color3.fromRGB(185, 200, 220), 11)
		makeLabel(card, "Cnt",  UDim2.new(1, -110, 0, 18), UDim2.new(0, 72, 0, 41), string.format("Amount: %d (%d 💰 each)", entry.Count, entry.UnitPrice), Color3.new(1, 1, 1), 12)
		makeLabel(card, "Tot",  UDim2.new(1, -110, 0, 16), UDim2.new(0, 72, 0, 58), string.format("Total: +%d 💰", entry.TotalValue), Color3.fromRGB(255, 220, 70), 12)

	end

end

-- ============================================================================
-- 5. МАГАЗИН-КАРУСЕЛЬ С 3D-МОДЕЛЯМИ (1–10 УР. КИРОК И РЮКЗАКОВ) — стиль референса «МАГАЗИН КИРОК»
-- • Центральная карточка крупная, соседние меньше; у каждой — своя 3D-модель в ViewportFrame.
-- • Свайп влево/вправо (телефон), стрелки ◀ ▶ на экране и на клавиатуре, колесо мыши (ПК).
-- • Под моделью: название, статы, цена, кнопка «Купить / Надеть».
-- ============================================================================
-- v24: rarity tiers like the reference (common grey, uncommon green, rare blue, epic purple, legendary gold)
type RarityTier = { Name: string, Col: Color3 }
local RARITY_TIERS: { RarityTier } = {
	{ Name = "COMMON", Col = Color3.fromRGB(168, 176, 188) },
	{ Name = "UNCOMMON", Col = Color3.fromRGB(86, 206, 84) },
	{ Name = "RARE", Col = Color3.fromRGB(58, 150, 255) },
	{ Name = "EPIC", Col = Color3.fromRGB(176, 92, 255) },
	{ Name = "LEGENDARY", Col = Color3.fromRGB(255, 192, 36) },
}
local SHOP_RARITY_IDX: { number } = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 }
local SHOP_RARITY: { Color3 } = {}
for i = 1, 10 do
	SHOP_RARITY[i] = RARITY_TIERS[SHOP_RARITY_IDX[i]].Col
end

-- v31: МЕНЮ «МАГАЗИН КИРОК / МАГАЗИН РЮКЗАКОВ» ПОЛНОСТЬЮ ПЕРЕДЕЛАНО ПО РЕФЕРЕНСУ
-- • Пещера с кристаллами на фоне, деревянная табличка-заголовок с киркой, красная кнопка ✕.
-- • 5 карточек в ряд: центральная самая крупная и светится золотом, боковые меньше.
-- • На карточке: цветная плашка с названием, 3D-модель, цена с монетой, зелёная кнопка «Купить».
-- • Белые стрелки ◀ ▶ по бокам, точки-индикатор снизу (жёлтая — выбранная).
type ShopTierRu = { Pick: string, Bag: string, Col: Color3, Dark: Color3 }
local SHOP_TIERS_RU: { ShopTierRu } = {
	{ Pick = "Simple Pickaxe", Bag = "Simple Backpack", Col = Color3.fromRGB(96, 200, 72), Dark = Color3.fromRGB(34, 110, 32) },
	{ Pick = "Common Pickaxe", Bag = "Common Backpack", Col = Color3.fromRGB(152, 160, 172), Dark = Color3.fromRGB(70, 76, 90) },
	{ Pick = "Rare Pickaxe", Bag = "Rare Backpack", Col = Color3.fromRGB(58, 142, 255), Dark = Color3.fromRGB(22, 62, 156) },
	{ Pick = "Epic Pickaxe", Bag = "Epic Backpack", Col = Color3.fromRGB(172, 86, 255), Dark = Color3.fromRGB(82, 30, 156) },
	{ Pick = "Legendary Pickaxe", Bag = "Legendary Backpack", Col = Color3.fromRGB(255, 192, 34), Dark = Color3.fromRGB(176, 98, 10) },
}
local SHOP_TIER_OF_LVL: { number } = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 }
for i = 1, 10 do
	SHOP_RARITY[i] = SHOP_TIERS_RU[SHOP_TIER_OF_LVL[i]].Col
end

local function shopShortNum(n: number): string
	if n >= 1e6 then
		local s = (string.gsub(string.format("%.1f", n / 1e6), "%.0$", ""))
		return s .. "M"
	elseif n >= 1e3 then
		local s = (string.gsub(string.format("%.1f", n / 1e3), "%.0$", ""))
		return s .. "K"
	end
	return tostring(math.floor(n))
end

local shopModal = Instance.new("Frame")
shopModal.Name = "Shop3DGuiModal"
shopModal.Size = UDim2.fromOffset(1000, 580)
shopModal.AnchorPoint = Vector2.new(0.5, 0.5)
shopModal.Position = UDim2.fromScale(0.5, 0.5)
shopModal.BackgroundColor3 = Color3.new(1, 1, 1)
shopModal.BorderSizePixel = 0
shopModal.ClipsDescendants = true
shopModal.Visible = false
shopModal.ZIndex = 20
shopModal.Parent = screenGui
Instance.new("UICorner", shopModal).CornerRadius = UDim.new(0, 20)
do
	local g = Instance.new("UIGradient", shopModal)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 30, 52)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(34, 40, 66)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 16, 30)),
	})
	g.Rotation = 90
	local st = Instance.new("UIStroke", shopModal)
	st.Color = Color3.fromRGB(12, 12, 22)
	st.Thickness = 5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local scale = Instance.new("UIScale", shopModal)
	local function fit()
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(vp.X / 1040, vp.Y / 620), 0.42, 1.15)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end

-- Фон-пещера: тёмные камни, сталактиты, светящиеся синие и фиолетовые кристаллы
do
	local function deco(name: string, size: UDim2, pos: UDim2, col: Color3, rot: number, tr: number, rad: number, z: number?): Frame
		local d = Instance.new("Frame")
		d.Name = name
		d.Size = size
		d.Position = pos
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.BackgroundColor3 = col
		d.BackgroundTransparency = tr
		d.BorderSizePixel = 0
		d.Rotation = rot
		d.ZIndex = z or 21
		d.Parent = shopModal
		if rad > 0 then
			Instance.new("UICorner", d).CornerRadius = UDim.new(0, rad)
		end
		return d
	end
	local rng = Random.new(31)
	-- каменный потолок и пол
	for i = 1, 30 do
		local top = (i % 2 == 0)
		local x = rng:NextNumber(0, 1)
		local y = top and rng:NextNumber(-0.02, 0.08) or rng:NextNumber(0.9, 1.02)
		local sz = rng:NextInteger(80, 170)
		local sh = rng:NextInteger(34, 58)
		deco("CaveRock", UDim2.fromOffset(sz, math.floor(sz * rng:NextNumber(0.55, 0.85))), UDim2.fromScale(x, y),
			Color3.fromRGB(sh, sh + 6, sh + 26), 0 * rng:NextNumber(-25, 25), 0.15, 30) -- v51: unrotated, so the window clips them
	end
	-- боковые скалы
	for i = 1, 12 do
		local left = (i % 2 == 0)
		local x = left and rng:NextNumber(-0.03, 0.04) or rng:NextNumber(0.96, 1.03)
		local sz = rng:NextInteger(70, 130)
		local sh = rng:NextInteger(30, 50)
		deco("CaveRockSide", UDim2.fromOffset(sz, sz), UDim2.fromScale(x, rng:NextNumber(0.1, 0.9)),
			Color3.fromRGB(sh, sh + 5, sh + 22), 0 * rng:NextNumber(0, 90), 0.2, 30)
	end
	-- сталактиты
	for i = 1, 9 do
		local x = 0.06 + (i - 1) * 0.11 + rng:NextNumber(-0.02, 0.02)
		local sz = rng:NextInteger(26, 44)
		deco("Stalactite", UDim2.fromOffset(sz, sz), UDim2.new(x, 0, 0, rng:NextInteger(44, 60)), Color3.fromRGB(44, 50, 76), 45, 0.1, 4)
	end
	-- кристаллы
	local function crystalCluster(x: number, y: number, col: Color3, sc: number)
		deco("CrystalGlow", UDim2.fromOffset(math.floor(150 * sc), math.floor(150 * sc)), UDim2.fromScale(x, y), col, 0, 0.82, math.floor(75 * sc))
		local shards = {
			{ w = 18, h = 62, dx = 0, dy = -8, r = 0 },
			{ w = 14, h = 44, dx = -18, dy = 4, r = -24 },
			{ w = 13, h = 40, dx = 18, dy = 6, r = 22 },
			{ w = 10, h = 28, dx = -32, dy = 14, r = -40 },
			{ w = 10, h = 26, dx = 32, dy = 15, r = 38 },
		}
		for _, s in ipairs(shards) do
			local c = deco("Crystal", UDim2.fromOffset(math.floor(s.w * sc), math.floor(s.h * sc)),
				UDim2.new(x, math.floor(s.dx * sc), y, math.floor(s.dy * sc)), Color3.new(1, 1, 1), s.r, 0.02, 3, 22)
			local cg = Instance.new("UIGradient", c)
			cg.Color = ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.6), col:Lerp(Color3.new(0, 0, 0), 0.25))
			cg.Rotation = 90
			local cs = Instance.new("UIStroke", c)
			cs.Color = col:Lerp(Color3.new(1, 1, 1), 0.7)
			cs.Transparency = 0.35
			cs.Thickness = 1.5
		end
	end
	local BLUE = Color3.fromRGB(70, 190, 255)
	local PURPLE = Color3.fromRGB(176, 96, 255)
	crystalCluster(0.07, 0.87, BLUE, 1.15)
	crystalCluster(0.93, 0.87, PURPLE, 1.15)
	crystalCluster(0.05, 0.36, PURPLE, 0.8)
	crystalCluster(0.95, 0.36, BLUE, 0.8)
	crystalCluster(0.2, 0.95, PURPLE, 0.7)
	crystalCluster(0.8, 0.95, BLUE, 0.7)
	-- мягкое свечение в центре пещеры
	deco("CaveCentreLight", UDim2.fromOffset(620, 420), UDim2.fromScale(0.5, 0.55), Color3.fromRGB(90, 110, 200), 0, 0.88, 210)
end

-- Деревянная табличка-заголовок «МАГАЗИН КИРОК»
local banner = Instance.new("Frame", shopModal)
banner.Name = "WoodBanner"
banner.Size = UDim2.fromOffset(500, 78)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 14)
banner.BackgroundColor3 = Color3.new(1, 1, 1)
banner.BorderSizePixel = 0
banner.ZIndex = 42
Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 12)
do
	local g = Instance.new("UIGradient", banner)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 134, 70)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(164, 102, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(112, 66, 30)),
	})
	g.Rotation = 90
	local st = Instance.new("UIStroke", banner)
	st.Color = Color3.fromRGB(56, 30, 12)
	st.Thickness = 5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	-- доски: две продольные щели
	for _, gy in ipairs({ 0.34, 0.67 }) do
		local groove = Instance.new("Frame", banner)
		groove.Name = "PlankGroove"
		groove.Size = UDim2.new(1, -16, 0, 2)
		groove.Position = UDim2.new(0, 8, gy, 0)
		groove.BackgroundColor3 = Color3.fromRGB(86, 50, 22)
		groove.BackgroundTransparency = 0.35
		groove.BorderSizePixel = 0
		groove.ZIndex = 43
	end
	-- гвозди
	for _, nx in ipairs({ 0.03, 0.97 }) do
		for _, ny in ipairs({ 0.22, 0.78 }) do
			local n = Instance.new("Frame", banner)
			n.Name = "Nail"
			n.AnchorPoint = Vector2.new(0.5, 0.5)
			n.Size = UDim2.fromOffset(8, 8)
			n.Position = UDim2.fromScale(nx, ny)
			n.BackgroundColor3 = Color3.fromRGB(214, 196, 160)
			n.ZIndex = 43
			Instance.new("UICorner", n).CornerRadius = UDim.new(1, 0)
			Instance.new("UIStroke", n).Color = Color3.fromRGB(70, 44, 18)
		end
	end
end
local bannerIcon = Instance.new("TextLabel", banner)
bannerIcon.Name = "PickIcon"
bannerIcon.AnchorPoint = Vector2.new(0.5, 0.5)
bannerIcon.Size = UDim2.fromOffset(96, 96)
bannerIcon.Position = UDim2.new(0, 22, 0.5, -4)
bannerIcon.Rotation = -16
bannerIcon.BackgroundTransparency = 1
bannerIcon.Font = Enum.Font.GothamBlack
bannerIcon.TextSize = 70
bannerIcon.Text = "⛏️"
bannerIcon.ZIndex = 44
local bannerTitle = Instance.new("TextLabel", banner)
bannerTitle.Name = "Title"
bannerTitle.Size = UDim2.new(1, -120, 1, -16)
bannerTitle.Position = UDim2.new(0, 84, 0, 8)
bannerTitle.BackgroundTransparency = 1
bannerTitle.Font = Enum.Font.GothamBlack
bannerTitle.RichText = true
bannerTitle.TextScaled = true
bannerTitle.TextColor3 = Color3.new(1, 1, 1)
bannerTitle.Text = 'PICKAXE <font color="#FFC21A">SHOP</font>'
bannerTitle.ZIndex = 44
do
	local st = Instance.new("UIStroke", bannerTitle)
	st.Thickness = 4
	st.Color = Color3.fromRGB(42, 22, 8)
	local c = Instance.new("UITextSizeConstraint", bannerTitle)
	c.MaxTextSize = 46
end

-- Красная кнопка ✕ (правый верхний угол)
local closeShopBtn = Instance.new("TextButton", shopModal)
closeShopBtn.Name = "CloseBtn"
closeShopBtn.Size = UDim2.fromOffset(64, 64)
closeShopBtn.Position = UDim2.new(1, -82, 0, 18)
closeShopBtn.BackgroundColor3 = Color3.new(1, 1, 1)
closeShopBtn.Font = Enum.Font.GothamBlack
closeShopBtn.Text = "✕"
closeShopBtn.TextSize = 38
closeShopBtn.TextColor3 = Color3.new(1, 1, 1)
closeShopBtn.TextStrokeTransparency = 0.2
closeShopBtn.TextStrokeColor3 = Color3.fromRGB(90, 10, 10)
closeShopBtn.ZIndex = 45
do
	Instance.new("UICorner", closeShopBtn).CornerRadius = UDim.new(0, 14)
	local g = Instance.new("UIGradient", closeShopBtn)
	g.Color = ColorSequence.new(Color3.fromRGB(255, 92, 80), Color3.fromRGB(196, 26, 26))
	g.Rotation = 90
	local st = Instance.new("UIStroke", closeShopBtn)
	st.Color = Color3.fromRGB(70, 8, 8)
	st.Thickness = 4
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local gl = Instance.new("Frame", closeShopBtn)
	gl.Name = "Gloss"
	gl.BackgroundColor3 = Color3.new(1, 1, 1)
	gl.BackgroundTransparency = 0.78
	gl.BorderSizePixel = 0
	gl.Size = UDim2.new(1, -10, 0.4, 0)
	gl.Position = UDim2.fromOffset(5, 4)
	gl.ZIndex = 45
	Instance.new("UICorner", gl).CornerRadius = UDim.new(0, 10)
end
vecCross(closeShopBtn)
closeShopBtn.MouseButton1Click:Connect(function()
	shopModal.Visible = false
end)

local ShopCategory = "Pickaxes" -- "Pickaxes" | "Backpacks"
local SelectedShopLevel = 1
local refreshShopView: () -> () = function() end
local ActiveViewportModel: Model? = nil

-- Переключатель «Кирки / Рюкзаки» — две маленькие деревянные плитки слева сверху
local function makeCategoryTab(name: string, icon: string, caption: string, xOff: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton", shopModal)
	b.Name = name
	b.Size = UDim2.fromOffset(74, 70)
	b.Position = UDim2.fromOffset(xOff, 18)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.Text = ""
	b.AutoButtonColor = true
	b.ZIndex = 45
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)
	local g = Instance.new("UIGradient", b)
	g.Color = ColorSequence.new(Color3.fromRGB(190, 126, 66), Color3.fromRGB(110, 64, 30))
	g.Rotation = 90
	local st = Instance.new("UIStroke", b)
	st.Color = Color3.fromRGB(56, 30, 12)
	st.Thickness = 3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local ic = Instance.new("TextLabel", b)
	ic.Size = UDim2.new(1, 0, 0, 42)
	ic.Position = UDim2.fromOffset(0, 2)
	ic.BackgroundTransparency = 1
	ic.Font = Enum.Font.GothamBlack
	ic.TextSize = 32
	ic.Text = icon
	ic.ZIndex = 46
	local cap = Instance.new("TextLabel", b)
	cap.Size = UDim2.new(1, -4, 0, 18)
	cap.Position = UDim2.new(0, 2, 1, -22)
	cap.BackgroundTransparency = 1
	cap.Font = Enum.Font.GothamBlack
	cap.TextScaled = true
	cap.TextColor3 = Color3.new(1, 1, 1)
	cap.Text = caption
	cap.ZIndex = 46
	Instance.new("UIStroke", cap).Thickness = 2
	b.MouseButton1Click:Connect(onClick)
	return b
end
local tabPickaxesBtn = makeCategoryTab("TabPickaxes", "⛏️", "Pickaxes", 18, function()
	ShopCategory = "Pickaxes"
	SelectedShopLevel = math.clamp(State.PickaxeTier, 1, 10)
	SoundManager.PlayUISound("ShopSwipe")
	refreshShopView()
end)
local tabBackpacksBtn = makeCategoryTab("TabBackpacks", "🎒", "Backpacks", 102, function()
	ShopCategory = "Backpacks"
	SelectedShopLevel = math.clamp(State.BackpackLevel, 1, 10)
	SoundManager.PlayUISound("ShopSwipe")
	refreshShopView()
end)

-- Область карусели
local carousel = Instance.new("Frame", shopModal)
carousel.Name = "Carousel"
carousel.Size = UDim2.new(1, -180, 0, 390)
carousel.Position = UDim2.new(0, 90, 0, 112)
carousel.BackgroundTransparency = 1
carousel.ZIndex = 22

local function stepShopLevel(delta: number)
	local nxt = SelectedShopLevel + delta
	if nxt < 1 or nxt > 10 then return end
	SelectedShopLevel = nxt
	SoundManager.PlayUISound("ShopSwipe") -- v28: carousel swipe
	refreshShopView()
end

-- Белые стрелки ◀ ▶ как на референсе
local function makeArrow(name: string, xScale: number, xOff: number, txt: string, delta: number)
	local b = Instance.new("TextButton", shopModal)
	b.Name = name
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Size = UDim2.fromOffset(54, 78)
	b.Position = UDim2.new(xScale, xOff, 0, 307)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.Text = txt
	b.TextSize = 36
	b.TextColor3 = Color3.fromRGB(54, 60, 76)
	b.ZIndex = 45
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 16)
	local g = Instance.new("UIGradient", b)
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 212, 224))
	g.Rotation = 90
	local st = Instance.new("UIStroke", b)
	st.Color = Color3.fromRGB(36, 40, 54)
	st.Thickness = 4
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	vecChevron(b, delta)
	b.MouseButton1Click:Connect(function()
		stepShopLevel(delta)
	end)
end
makeArrow("PrevBtn", 0, 8, "◀", -1)
makeArrow("NextBtn", 1, -62, "▶", 1)

-- v51: card layout measured from the reference picture: the cards no longer overlap (every
-- title stays readable), the side cards shrink, rise a little and fan out with a slight tilt.
local CARD_LAYOUT = {
	[0]  = { w = 240, h = 368, dx = 0,    dy = 4,   rot = 0,  z = 5 },
	[-1] = { w = 178, h = 288, dx = -224, dy = -12, rot = -3, z = 3 },
	[1]  = { w = 178, h = 288, dx = 224,  dy = -12, rot = 3,  z = 3 },
	[-2] = { w = 134, h = 222, dx = -378, dy = -22, rot = -6, z = 1 },
	[2]  = { w = 134, h = 222, dx = 378,  dy = -22, rot = 6,  z = 1 },
}

-- Золотое свечение за центральной карточкой (behind every card, so it never tints the neighbours)
local centreGlow = Instance.new("Frame", carousel)
centreGlow.Name = "CentreGlow"
centreGlow.AnchorPoint = Vector2.new(0.5, 0.5)
centreGlow.Size = UDim2.fromOffset(240 + 40, 368 + 40)
centreGlow.Position = UDim2.new(0.5, 0, 0.5, 4)
centreGlow.BackgroundColor3 = Color3.fromRGB(255, 214, 70)
centreGlow.BackgroundTransparency = 0.55
centreGlow.BorderSizePixel = 0
centreGlow.ZIndex = 21
Instance.new("UICorner", centreGlow).CornerRadius = UDim.new(0, 38)
local centreGlowOuter = centreGlow:Clone()
centreGlowOuter.Name = "CentreGlowOuter"
centreGlowOuter.Size = UDim2.fromOffset(240 + 84, 368 + 84)
centreGlowOuter.BackgroundTransparency = 0.8
centreGlowOuter.ZIndex = 20
centreGlowOuter.Parent = carousel
do -- a third, faint layer makes the halo fade out softly instead of ending in a hard box
	local outerCorner = centreGlowOuter:FindFirstChildOfClass("UICorner")
	if outerCorner then outerCorner.CornerRadius = UDim.new(0, 58) end
	local far = centreGlow:Clone()
	far.Name = "CentreGlowFar"
	far.Size = UDim2.fromOffset(240 + 132, 368 + 132)
	far.BackgroundTransparency = 0.9
	far.ZIndex = 19
	local farCorner = far:FindFirstChildOfClass("UICorner")
	if farCorner then farCorner.CornerRadius = UDim.new(0, 80) end
	far.Parent = carousel
end

type ShopCard = {
	Frame: Frame, VP: ViewportFrame, Cam: Camera, Strip: Frame, Title: TextLabel, Level: TextLabel,
	Stats: TextLabel, Price: TextLabel, Coin: Frame, Btn: TextButton, Stroke: UIStroke, Grad: UIGradient,
	Glow: Frame, Hit: TextButton?, ModelKey: string, Model: Model?, Slot: number,
	BtnGrad: UIGradient, BtnLip: Frame, BtnStroke: UIStroke, BtnTextStroke: UIStroke,
}
local ShopCards: { [number]: ShopCard } = {}

for k = -2, 2 do
	local lay = CARD_LAYOUT[k]
	local s = lay.w / 240
	local base = 22 + lay.z * 3
	local isCentre = (k == 0)

	-- outer frame = dark outline; the coloured face with its bright rim sits inside it
	local f = Instance.new("Frame", carousel)
	f.Name = "Card_" .. k
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(lay.w, lay.h)
	f.Position = UDim2.new(0.5, lay.dx, 0.5, lay.dy)
	f.Rotation = lay.rot
	f.BackgroundColor3 = Color3.fromRGB(20, 16, 28)
	f.BorderSizePixel = 0
	f.ZIndex = base
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, math.floor(20 * s))

	local rimW = isCentre and 6 or math.max(3, math.floor(4 * s + 0.5))
	local inset = rimW + 2
	local face = Instance.new("Frame", f)
	face.Name = "Face"
	face.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	face.Position = UDim2.fromOffset(inset, inset)
	face.BackgroundColor3 = Color3.new(1, 1, 1)
	face.BorderSizePixel = 0
	Instance.new("UICorner", face).CornerRadius = UDim.new(0, math.floor(14 * s))
	local grad = Instance.new("UIGradient", face)
	grad.Rotation = 90
	local stroke = Instance.new("UIStroke", face)
	stroke.Thickness = rimW
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	-- Цветная плашка с названием сверху
	local stripH = math.floor(42 * s)
	local strip = Instance.new("Frame", face)
	strip.Name = "TitleStrip"
	strip.Size = UDim2.new(1, -8, 0, stripH)
	strip.Position = UDim2.fromOffset(4, 4)
	strip.BackgroundColor3 = Color3.new(0, 0, 0)
	strip.BorderSizePixel = 0
	strip.ZIndex = 3
	Instance.new("UICorner", strip).CornerRadius = UDim.new(0, math.floor(11 * s))
	local title = Instance.new("TextLabel", strip)
	title.Size = UDim2.new(1, -8, 1, -6)
	title.Position = UDim2.fromOffset(4, 3)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.ZIndex = 4
	do
		local tst = Instance.new("UIStroke", title)
		tst.Thickness = math.max(1.5, 2.5 * s)
		tst.Color = Color3.fromRGB(20, 14, 10)
		local c = Instance.new("UITextSizeConstraint", title)
		c.MaxTextSize = isCentre and 24 or 18
		c.MinTextSize = 7
	end

	-- Маленький значок уровня (под плашкой, справа)
	local lvlTag = Instance.new("TextLabel", face)
	lvlTag.Name = "LevelTag"
	lvlTag.AnchorPoint = Vector2.new(1, 0)
	lvlTag.Size = UDim2.fromOffset(math.floor(54 * s), math.floor(21 * s))
	lvlTag.Position = UDim2.new(1, -6, 0, stripH + 8)
	lvlTag.BackgroundColor3 = Color3.fromRGB(24, 20, 30)
	lvlTag.BackgroundTransparency = 0.4
	lvlTag.Font = Enum.Font.GothamBlack
	lvlTag.TextScaled = true
	lvlTag.TextColor3 = Color3.new(1, 1, 1)
	lvlTag.ZIndex = 5
	Instance.new("UICorner", lvlTag).CornerRadius = UDim.new(1, 0)

	-- Свечение за моделью и сама 3D-модель (крупнее, чем раньше)
	local glow = Instance.new("Frame", face)
	glow.Name = "ModelGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Size = UDim2.fromOffset(math.floor(196 * s), math.floor(170 * s))
	glow.Position = UDim2.fromScale(0.5, isCentre and 0.38 or 0.4)
	glow.BackgroundColor3 = Color3.new(1, 1, 1)
	glow.BackgroundTransparency = 0.62
	glow.BorderSizePixel = 0
	glow.ZIndex = 2
	Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)

	local vp = Instance.new("ViewportFrame", face)
	vp.Size = UDim2.new(1, -8, isCentre and 0.5 or 0.52, 0)
	vp.Position = UDim2.new(0, 4, 0.13, 0)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 205, 225)
	vp.LightColor = Color3.fromRGB(255, 250, 235)
	vp.LightDirection = Vector3.new(-1, -1, -1)
	vp.ZIndex = 4
	local cam = Instance.new("Camera", vp)
	cam.FieldOfView = 45
	vp.CurrentCamera = cam

	local stats = Instance.new("TextLabel", face)
	stats.Size = UDim2.new(1, -14, 0.07, 0)
	stats.Position = UDim2.new(0, 7, 0.625, 0)
	stats.BackgroundTransparency = 1
	stats.Font = Enum.Font.GothamBold
	stats.TextScaled = true
	stats.TextColor3 = Color3.new(1, 1, 1)
	stats.Visible = isCentre
	stats.ZIndex = 5
	do
		Instance.new("UIStroke", stats).Thickness = 1.5
		local c = Instance.new("UITextSizeConstraint", stats)
		c.MaxTextSize = 15
	end

	-- Цена: монета + сумма (как «💎 2.5M» на референсе)
	local priceRow = Instance.new("Frame", face)
	priceRow.Name = "PriceRow"
	priceRow.Size = UDim2.new(1, -12, 0.11, 0)
	priceRow.Position = UDim2.new(0, 6, isCentre and 0.7 or 0.675, 0)
	priceRow.BackgroundTransparency = 1
	priceRow.ZIndex = 5
	do
		local l = Instance.new("UIListLayout", priceRow)
		l.FillDirection = Enum.FillDirection.Horizontal
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
		l.VerticalAlignment = Enum.VerticalAlignment.Center
		l.Padding = UDim.new(0, math.floor(6 * s))
		l.SortOrder = Enum.SortOrder.LayoutOrder
	end
	local coinSz = math.floor(30 * s)
	local coin = Instance.new("Frame", priceRow)
	coin.Name = "CoinIcon"
	coin.Size = UDim2.fromOffset(coinSz, coinSz)
	coin.BackgroundColor3 = Color3.new(1, 1, 1)
	coin.LayoutOrder = 1
	Instance.new("UICorner", coin).CornerRadius = UDim.new(1, 0)
	do
		local cg = Instance.new("UIGradient", coin)
		cg.Color = ColorSequence.new(Color3.fromRGB(255, 236, 110), Color3.fromRGB(230, 150, 20))
		cg.Rotation = 90
		local cst = Instance.new("UIStroke", coin)
		cst.Color = Color3.fromRGB(110, 60, 6)
		cst.Thickness = 2
		local inner = Instance.new("TextLabel", coin)
		inner.Size = UDim2.fromScale(1, 1)
		inner.BackgroundTransparency = 1
		inner.Font = Enum.Font.GothamBlack
		inner.TextScaled = true
		inner.Text = "$"
		inner.TextColor3 = Color3.fromRGB(160, 92, 10)
	end
	local price = Instance.new("TextLabel", priceRow)
	price.Name = "Price"
	price.Size = UDim2.new(0, 0, 1, 0)
	price.AutomaticSize = Enum.AutomaticSize.X
	price.BackgroundTransparency = 1
	price.Font = Enum.Font.GothamBlack
	price.TextSize = math.floor(30 * s)
	price.TextColor3 = Color3.new(1, 1, 1)
	price.LayoutOrder = 2
	do
		local pst = Instance.new("UIStroke", price)
		pst.Thickness = 2.5
		pst.Color = Color3.fromRGB(20, 14, 10)
	end

	-- Зелёная кнопка «Купить» с объёмной кромкой. The gradient lives on a separate plate:
	-- a UIGradient on the button itself would also tint its text, and the reference has white text.
	local btnSize = UDim2.new(1, -18, 0.15, 0)
	local lip = Instance.new("Frame", face)
	lip.Name = "BtnLip"
	lip.AnchorPoint = Vector2.new(0.5, 1)
	lip.Size = btnSize
	lip.Position = UDim2.new(0.5, 0, 1, -5)
	lip.BackgroundColor3 = Color3.fromRGB(22, 92, 30)
	lip.BorderSizePixel = 0
	lip.ZIndex = 5
	Instance.new("UICorner", lip).CornerRadius = UDim.new(0, math.floor(12 * s))
	local plate = Instance.new("Frame", face)
	plate.Name = "BtnPlate"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Size = btnSize
	plate.Position = UDim2.new(0.5, 0, 1, -10)
	plate.BackgroundColor3 = Color3.new(1, 1, 1)
	plate.BorderSizePixel = 0
	plate.ZIndex = 6
	Instance.new("UICorner", plate).CornerRadius = UDim.new(0, math.floor(12 * s))
	local plateGrad = Instance.new("UIGradient", plate)
	plateGrad.Color = ColorSequence.new(Color3.fromRGB(120, 240, 90), Color3.fromRGB(40, 170, 50))
	plateGrad.Rotation = 90
	local plateStroke = Instance.new("UIStroke", plate)
	plateStroke.Color = Color3.fromRGB(18, 76, 26)
	plateStroke.Thickness = isCentre and 3.5 or 2.5
	plateStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	do
		local bgl = Instance.new("Frame", plate)
		bgl.Name = "Gloss"
		bgl.BackgroundColor3 = Color3.new(1, 1, 1)
		bgl.BackgroundTransparency = 0.78
		bgl.BorderSizePixel = 0
		bgl.Size = UDim2.new(1, -10, 0.4, 0)
		bgl.Position = UDim2.fromOffset(5, 3)
		Instance.new("UICorner", bgl).CornerRadius = UDim.new(0, math.floor(9 * s))
	end
	local btn = Instance.new("TextButton", face)
	btn.Name = "BuyBtn"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Size = btnSize
	btn.Position = UDim2.new(0.5, 0, 1, -10)
	btn.BackgroundTransparency = 1
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "Buy"
	btn.AutoButtonColor = false
	btn.ZIndex = 7
	local btnTextStroke = Instance.new("UIStroke", btn)
	btnTextStroke.Thickness = math.max(1.5, 3 * s)
	btnTextStroke.Color = Color3.fromRGB(18, 76, 26)
	do
		local c = Instance.new("UITextSizeConstraint", btn)
		c.MaxTextSize = isCentre and 30 or 20
		c.MinTextSize = 8
		local pad = Instance.new("UIPadding", btn)
		pad.PaddingTop = UDim.new(0, math.floor(6 * s))
		pad.PaddingBottom = UDim.new(0, math.floor(6 * s))
	end

	local card: ShopCard = {
		Frame = f, VP = vp, Cam = cam, Strip = strip, Title = title, Level = lvlTag, Stats = stats,
		Price = price, Coin = coin, Btn = btn, Stroke = stroke, Grad = grad, Glow = glow, Hit = nil,
		ModelKey = "", Model = nil, Slot = k,
		BtnGrad = plateGrad, BtnLip = lip, BtnStroke = plateStroke, BtnTextStroke = btnTextStroke,
	}
	if isCentre then
		btn.MouseButton1Click:Connect(function()
			if ShopCategory == "Pickaxes" then
				BuyPickaxeRemote:FireServer(SelectedShopLevel)
			else
				BuyBackpackRemote:FireServer(SelectedShopLevel)
			end
		end)
	else
		-- боковые карточки: нажатие выводит карточку в центр
		btn.MouseButton1Click:Connect(function() stepShopLevel(k) end)
		local hit = Instance.new("TextButton", f)
		hit.Name = "Hit"
		hit.Size = UDim2.new(1, 0, 0.8, 0)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = 9
		hit.MouseButton1Click:Connect(function() stepShopLevel(k) end)
		card.Hit = hit
	end
	ShopCards[k] = card
end

-- Искорки вокруг центральной карточки
local shopSparkles: { TextLabel } = {}
local SPARK_POS: { Vector2 } = { Vector2.new(-138, -170), Vector2.new(140, -130), Vector2.new(-146, 70), Vector2.new(142, 150), Vector2.new(0, -194), Vector2.new(-70, 190) }
for i, p in ipairs(SPARK_POS) do
	local sp = Instance.new("TextLabel", carousel)
	sp.Name = "Sparkle"
	sp.AnchorPoint = Vector2.new(0.5, 0.5)
	sp.Size = UDim2.fromOffset(26, 26)
	sp.Position = UDim2.new(0.5, p.X, 0.5, p.Y)
	sp.BackgroundTransparency = 1
	sp.Font = Enum.Font.GothamBlack
	sp.TextScaled = true
	sp.Text = "✦"
	sp.TextColor3 = Color3.fromRGB(255, 240, 170)
	sp.ZIndex = 41
	shopSparkles[i] = sp
end
task.spawn(function()
	local t = 0
	while true do
		local dt = task.wait(1 / 30)
		if shopModal.Visible then
			t += dt
			local pulse = 0.5 + 0.5 * math.sin(t * 2.4)
			centreGlow.BackgroundTransparency = 0.5 + pulse * 0.15
			centreGlowOuter.BackgroundTransparency = 0.76 + pulse * 0.12
			for i, sp in ipairs(shopSparkles) do
				local a = 0.5 + 0.5 * math.sin(t * 3 + i * 1.7)
				sp.TextTransparency = 1 - a
				sp.Rotation = (t * 60 + i * 40) % 360
				local sz = math.floor(12 + a * 18)
				sp.Size = UDim2.fromOffset(sz, sz)
			end
		end
	end
end)

-- Точки-индикатор снизу (выбранная — жёлтая, остальные серые)
local dotsRow = Instance.new("Frame", shopModal)
dotsRow.Name = "PageDots"
dotsRow.Size = UDim2.fromOffset(300, 22)
dotsRow.AnchorPoint = Vector2.new(0.5, 1)
dotsRow.Position = UDim2.new(0.5, 0, 1, -24)
dotsRow.BackgroundTransparency = 1
dotsRow.ZIndex = 42
do
	local l = Instance.new("UIListLayout", dotsRow)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, 10)
end
local ShopDots: { Frame } = {}
for i = 1, 10 do
	local d = Instance.new("Frame", dotsRow)
	d.Size = UDim2.fromOffset(14, 14)
	d.BackgroundColor3 = Color3.fromRGB(150, 154, 166)
	d.LayoutOrder = i
	d.ZIndex = 42
	Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
	local dst = Instance.new("UIStroke", d)
	dst.Color = Color3.fromRGB(20, 20, 30)
	dst.Thickness = 2
	ShopDots[i] = d
end

-- Свайп по области карусели
local swipeStartX: number? = nil
local swipeStartY: number? = nil
carousel.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		swipeStartX, swipeStartY = input.Position.X, input.Position.Y
	end
end)
carousel.InputEnded:Connect(function(input: InputObject)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and swipeStartX and swipeStartY then
		local dx = input.Position.X - swipeStartX
		local dy = input.Position.Y - swipeStartY
		swipeStartX, swipeStartY = nil, nil
		if math.abs(dx) > 40 and math.abs(dx) > math.abs(dy) then
			stepShopLevel(dx < 0 and 1 or -1)
		elseif dy > 90 and math.abs(dy) > math.abs(dx) then
			shopModal.Visible = false
		end
	end
end)
-- v51: while the shop is open the mouse wheel flips through the cards anywhere on the
-- screen, and the camera zoom is frozen (the wheel used to zoom the camera out as well)
local lastWheelStep = 0
UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel or not shopModal.Visible then return end
	local now = os.clock()
	if now - lastWheelStep < 0.09 then return end
	lastWheelStep = now
	stepShopLevel(input.Position.Z > 0 and -1 or 1)
end)
do
	local savedMin: number? = nil
	local savedMax: number? = nil
	local function setZoomLocked(locked: boolean)
		if locked then
			if savedMin then return end
			local cam = workspace.CurrentCamera
			local minD, maxD = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
			local dist = cam and (cam.CFrame.Position - cam.Focus.Position).Magnitude or minD
			dist = math.clamp(dist, minD, math.max(minD, maxD))
			savedMin, savedMax = minD, maxD
			player.CameraMaxZoomDistance = dist
			player.CameraMinZoomDistance = dist
		elseif savedMin and savedMax then
			player.CameraMinZoomDistance = savedMin
			player.CameraMaxZoomDistance = savedMax
			savedMin, savedMax = nil, nil
		end
	end
	shopModal:GetPropertyChangedSignal("Visible"):Connect(function()
		setZoomLocked(shopModal.Visible)
	end)
end

local function buildCardModel(card: ShopCard, lvl: number)
	local key = ShopCategory .. lvl
	if card.ModelKey == key and card.Model and card.Model.Parent then return end
	if card.Model then card.Model:Destroy() card.Model = nil end
	card.ModelKey = key
	local m = Instance.new("Model")
	m.Name = "ViewportPreviewModel"
	if ShopCategory == "Pickaxes" then
		local h = EquipmentBuilder.BuildModernPickaxeParts(m, lvl, CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(15), 0, math.rad(-28)), true, { Scale = 0.85, ForViewport = true })
		m.PrimaryPart = h
		-- v29: камера по габаритам модели — широкое навершие целиком помещается в карточку
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		local corners = {
			Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1),
			Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, -1),
		}
		for _, inst in ipairs(m:GetDescendants()) do
			if inst:IsA("BasePart") then
				local e = inst.Size / 2
				for _, c in ipairs(corners) do
					local p = inst.CFrame * (e * c)
					lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
					hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
				end
			end
		end
		local ctr, ext = (lo + hi) / 2, (hi - lo) / 2
		local vs = card.VP.AbsoluteSize
		local aspect = 1
		if vs.X > 1 and vs.Y > 1 then
			aspect = vs.X / vs.Y
		end
		local tanHalf = math.tan(math.rad(card.Cam.FieldOfView / 2))
		local dist = math.max(5.2, math.max(ext.Y / tanHalf, ext.X / (tanHalf * aspect)) * 1.08 + ext.Z)
		card.Cam.CFrame = CFrame.lookAt(ctr + Vector3.new(0, 0, dist), ctr)
	else
		local b = EquipmentBuilder.BuildBackpackParts(m, lvl, CFrame.new(0, -0.1, 0), true, 1.0)
		m.PrimaryPart = b
		card.Cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.1, 4.6), Vector3.new(0, 0.1, 0))
	end
	m.Parent = card.VP
	card.Model = m
end

refreshShopView = function()
	local isPick = (ShopCategory == "Pickaxes")
	bannerTitle.Text = isPick and 'PICKAXE <font color="#FFC21A">SHOP</font>' or 'BACKPACK <font color="#FFC21A">SHOP</font>'
	bannerIcon.Text = isPick and "⛏️" or "🎒"
	for _, tb in ipairs({ tabPickaxesBtn, tabBackpacksBtn }) do
		local active = (tb == tabPickaxesBtn) == isPick
		local st = tb:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = active and Color3.fromRGB(255, 214, 60) or Color3.fromRGB(56, 30, 12)
			st.Thickness = active and 4 or 3
		end
		local tg = tb:FindFirstChildOfClass("UIGradient")
		if tg then
			tg.Color = active and ColorSequence.new(Color3.fromRGB(226, 160, 84), Color3.fromRGB(150, 92, 40))
				or ColorSequence.new(Color3.fromRGB(150, 100, 58), Color3.fromRGB(84, 50, 24))
		end
	end

	for k = -2, 2 do
		local card = ShopCards[k]
		local lvl = SelectedShopLevel + k
		if lvl < 1 or lvl > 10 then
			card.Frame.Visible = false
		else
			card.Frame.Visible = true
			local cfg: any = isPick and GameConfig.PICKAXE_TIERS[lvl] or GameConfig.BACKPACK_TIERS[lvl]
			local tier = SHOP_TIERS_RU[SHOP_TIER_OF_LVL[lvl]]
			local col = tier.Col
			card.Grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, col:Lerp(Color3.new(1, 1, 1), 0.2)),
				ColorSequenceKeypoint.new(0.5, col),
				ColorSequenceKeypoint.new(1, col:Lerp(Color3.new(0, 0, 0), 0.5)),
			})
			card.Strip.BackgroundColor3 = tier.Dark
			card.Frame.BackgroundColor3 = tier.Dark:Lerp(Color3.new(0, 0, 0), 0.6)
			card.Stroke.Color = (k == 0) and Color3.fromRGB(255, 244, 170) or col:Lerp(Color3.new(1, 1, 1), 0.5)
			card.Title.Text = isPick and tier.Pick or tier.Bag
			card.Level.Text = "Lv. " .. lvl
			card.Glow.BackgroundColor3 = col:Lerp(Color3.new(1, 1, 1), 0.55)

			local equipped = isPick and (State.PickaxeTier == lvl) or (not isPick and State.BackpackLevel == lvl)
			local owned = isPick and (State.UnlockedPickaxes[lvl] == true) or (not isPick and State.UnlockedBackpacks[lvl] == true)
			local cost = tonumber(cfg.Cost) or 0
			local affordable = State.Coins >= cost
			local locked = (not equipped and not owned and not affordable)
			if equipped then
				card.Coin.Visible = false
				card.Price.Text = "✅ Equipped"
				card.Btn.Text = "Equipped"
			elseif owned then
				card.Coin.Visible = false
				card.Price.Text = "✔ Owned"
				card.Btn.Text = "Equip"
			elseif cost <= 0 then
				card.Coin.Visible = false
				card.Price.Text = "Free"
				card.Btn.Text = "Take"
			else
				card.Coin.Visible = true
				card.Price.Text = shopShortNum(cost)
				card.Btn.Text = affordable and "Buy" or "🔒 Buy"
			end
			card.Price.TextColor3 = locked and Color3.fromRGB(255, 130, 120) or Color3.new(1, 1, 1)
			card.BtnGrad.Color = locked and ColorSequence.new(Color3.fromRGB(168, 168, 180), Color3.fromRGB(98, 98, 112))
				or ColorSequence.new(Color3.fromRGB(120, 240, 90), Color3.fromRGB(40, 170, 50))
			local btnDark = locked and Color3.fromRGB(46, 46, 58) or Color3.fromRGB(18, 76, 26)
			card.BtnLip.BackgroundColor3 = locked and Color3.fromRGB(58, 58, 72) or Color3.fromRGB(22, 92, 30)
			card.BtnStroke.Color = btnDark
			card.BtnTextStroke.Color = btnDark

			if k == 0 then
				if isPick then
					card.Stats.Text = string.format("💥 Damage: %d   ⚡ %.2f s", cfg.Damage, cfg.BaseSwingCooldown)
				else
					card.Stats.Text = string.format("🎒 Capacity: %d", cfg.Capacity)
				end
			end
			buildCardModel(card, lvl)
			if k == 0 then ActiveViewportModel = card.Model end
		end
	end

	for i, d in ipairs(ShopDots) do
		local sel = (i == SelectedShopLevel)
		d.Size = sel and UDim2.fromOffset(20, 20) or UDim2.fromOffset(14, 14)
		d.BackgroundColor3 = sel and Color3.fromRGB(255, 210, 40) or Color3.fromRGB(150, 154, 166)
	end
end

-- ============================================================================
-- 6. НИЖНЯЯ ПАНЕЛЬ БЫСТРОГО ДОСТУПА: РЮКЗАК, КНОПКА «⬆️ НАВЕРХ / СПАУН» (ПУНКТ №3) И 3D МАГАЗИН
-- ============================================================================
local bottomDock = Instance.new("Frame", screenGui)
bottomDock.Name = "BottomActionDock"
bottomDock.Size = UDim2.new(0, 100, 0, 104) -- v27: only the Sell tile stays at the bottom
bottomDock.Position = UDim2.new(0.5, -50, 1, -116)
bottomDock.BackgroundTransparency = 1

-- Квадратная плитка в стиле референса: крупная иконка сверху, подпись снизу, глянцевый градиент и толстая тёмная обводка.
local function makeTile(name: string, icon: string, caption: string, posX: number, top: Color3, bottom: Color3, onClick: () -> ()): (TextButton, TextLabel)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(100, 100) -- v26
	b.Position = UDim2.fromOffset(posX, 2)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.Text = ""
	b.AutoButtonColor = false
	b.Parent = bottomDock
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 18)
	local g = Instance.new("UIGradient", b)
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	local st = Instance.new("UIStroke", b)
	st.Color = top:Lerp(Color3.new(1, 1, 1), 0.5) -- v25: bright rim like the reference
	st.Thickness = 4
	local tg = Instance.new("Frame", b)
	tg.Name = "Gloss"
	tg.BackgroundColor3 = Color3.new(1, 1, 1)
	tg.BackgroundTransparency = 0.82
	tg.BorderSizePixel = 0
	tg.Size = UDim2.new(1, -10, 0.42, 0)
	tg.Position = UDim2.fromOffset(5, 3)
	Instance.new("UICorner", tg).CornerRadius = UDim.new(0, 13)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local ic = Instance.new("TextLabel", b)
	ic.Size = UDim2.new(1, 0, 0, 52)
	ic.Position = UDim2.fromOffset(0, 4)
	ic.BackgroundTransparency = 1
	ic.Font = Enum.Font.GothamBlack
	ic.TextSize = 40
	ic.Text = icon
	-- v26: drawn picture like the reference (the emoji label stays hidden as a fallback)
	local vic = HudModule.DrawIcon(b, icon, 62, 3)
	if vic then
		ic.Visible = false
		vic.AnchorPoint = Vector2.new(0.5, 0)
		vic.Position = UDim2.new(0.5, 0, 0, 6)
	end

	local cap = Instance.new("TextLabel", b)
	cap.Size = UDim2.new(1, -6, 0, 22)
	cap.Position = UDim2.new(0, 3, 1, -26)
	cap.BackgroundTransparency = 1
	cap.Font = Enum.Font.GothamBlack
	cap.TextSize = 15
	cap.TextColor3 = Color3.new(1, 1, 1)
	cap.Text = caption
	local cs = Instance.new("UIStroke", cap)
	cs.Thickness = 2.5
	cs.Color = bottom:Lerp(Color3.new(0, 0, 0), 0.7)

	local sc = Instance.new("UIScale", b)
	b.MouseEnter:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1.06 }):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1 }):Play() end)
	b.MouseButton1Down:Connect(function() sc.Scale = 0.94 end)
	b.MouseButton1Up:Connect(function() sc.Scale = 1.06 end)
	b.Activated:Connect(onClick)
	return b, cap
end

-- v27: the bottom Shop tile was removed. The Shop button (side menu), the "+" on Coins and the M key
-- teleport the player onto the SHOP pad (server-side teleport), and the shop menu opens there.
local LastShopTeleportClock = -999
local function isOnShopPad(): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end
	local p = root.Position
	local padPos = GameConfig.GREEN_SHOP_PAD_POS + Vector3.new(0, 0.35, 4.0)
	local dist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(padPos.X, 0, padPos.Z)).Magnitude
	return dist <= 6.2 and math.abs(p.Y - padPos.Y) < 6
end
local function openShopMenuHere()
	bagModal.Visible = false
	shopModal.Visible = true
	SoundManager.PlayUISound("ShopOpen") -- v28: shop open swoosh
	refreshShopView()
end
local function goToShop()
	bagModal.Visible = false
	if isOnShopPad() then
		if shopModal.Visible then
			shopModal.Visible = false
		else
			openShopMenuHere()
		end
		return
	end
	local now = os.clock()
	if (now - LastShopTeleportClock) < 1.5 then return end
	LastShopTeleportClock = now
	shopModal.Visible = false
	TeleportToShopRemote:FireServer()
	-- the SHOP zone check opens the menu on arrival; this is only a fallback
	task.delay(0.9, function()
		if not shopModal.Visible and isOnShopPad() then
			openShopMenuHere()
		end
	end)
end

-- v25: "+" on the Coins plate opens the shop (same as the Shop tile)
task.spawn(function()
	local pb: Instance? = nil
	for _ = 1, 80 do
		local holder = screenGui:FindFirstChild("TopRightCoins")
		pb = holder and holder:FindFirstChild("PlusBtn", true)
		if pb then break end
		task.wait(0.25)
	end
	if pb and pb:IsA("GuiButton") then
		pb.Activated:Connect(function() goToShop() end) -- v27: same as the Shop button
	end
end)

-- v27: the bottom Backpack tile was removed (the Inventory button and the Backpack plate open the bag)

local LastSpawnClickClock = -999
local spawnBtn: TextButton
local spawnCaption: TextLabel
spawnBtn, spawnCaption = makeTile("TeleportSpawnBottomBtn", "MoneyBag", "Sell", 0, Color3.fromRGB(110, 235, 110), Color3.fromRGB(30, 160, 60), function()
	if shopModal.Visible or bagModal.Visible then
		showBannerNotification("⚠️ Close the shop/backpack before teleporting!", Color3.fromRGB(255, 175, 75))
		return
	end
	local now = os.clock()
	if (now - LastSpawnClickClock) < GameConfig.SPAWN_TELEPORT_COOLDOWN then
		return
	end
	LastSpawnClickClock = now
	TeleportToSpawnRemote:FireServer()
	task.spawn(function()
		for sec = math.ceil(GameConfig.SPAWN_TELEPORT_COOLDOWN), 1, -1 do
			spawnCaption.Text = string.format("%d s", sec)
			task.wait(1)
		end
		spawnCaption.Text = "Sell"
	end)
end)

-- v26: the side menu (ProgressionUI) opens the shop / backpack through these events
do
	local uiBus = Instance.new("Folder")
	uiBus.Name = "UIBus"
	uiBus.Parent = screenGui
	local busShop = Instance.new("BindableEvent")
	busShop.Name = "OpenShop"
	busShop.Parent = uiBus
	local busBag = Instance.new("BindableEvent")
	busBag.Name = "OpenBag"
	busBag.Parent = uiBus
	busShop.Event:Connect(function() goToShop() end) -- v27: teleport to the shop, the menu opens there
	busBag.Event:Connect(function()
		shopModal.Visible = false
		bagModal.Visible = not bagModal.Visible
		if bagModal.Visible then rebuildInventorySlots() end
	end)
end
hud = HudModule.new(screenGui, {
	OnBackpackClick = function()
		shopModal.Visible = false
		bagModal.Visible = not bagModal.Visible
		if bagModal.Visible then rebuildInventorySlots() end
	end,
})


-- ============================================================================
-- v14: ВСПЛЫВАЮЩЕЕ «+XXX МОНЕТ» ПОСЛЕ АВТОПРОДАЖИ (без меню и кнопок)
-- ============================================================================
local sellPopup = Instance.new("Frame", screenGui)
sellPopup.Name = "AutoSellPopup"
sellPopup.AnchorPoint = Vector2.new(0.5, 0.5)
sellPopup.Size = UDim2.fromOffset(330, 74)
sellPopup.Position = UDim2.new(0.5, 0, 0.3, 0)
sellPopup.BackgroundColor3 = Color3.fromRGB(14, 34, 26)
sellPopup.BackgroundTransparency = 0.1
sellPopup.Visible = false
sellPopup.ZIndex = 40
Instance.new("UICorner", sellPopup).CornerRadius = UDim.new(0, 18)
do
	local st = Instance.new("UIStroke", sellPopup)
	st.Color = Color3.fromRGB(55, 245, 115)
	st.Thickness = 3
end
local sellPopupAmount = Instance.new("TextLabel", sellPopup)
sellPopupAmount.Size = UDim2.new(1, -20, 0, 42)
sellPopupAmount.Position = UDim2.new(0, 10, 0, 6)
sellPopupAmount.BackgroundTransparency = 1
sellPopupAmount.Font = Enum.Font.GothamBlack
sellPopupAmount.TextScaled = true
sellPopupAmount.TextColor3 = Color3.fromRGB(255, 220, 70)
sellPopupAmount.ZIndex = 41
Instance.new("UIStroke", sellPopupAmount).Thickness = 2.5
local sellPopupSub = Instance.new("TextLabel", sellPopup)
sellPopupSub.Size = UDim2.new(1, -20, 0, 20)
sellPopupSub.Position = UDim2.new(0, 10, 0, 48)
sellPopupSub.BackgroundTransparency = 1
sellPopupSub.Font = Enum.Font.GothamBold
sellPopupSub.TextSize = 14
sellPopupSub.TextColor3 = Color3.fromRGB(190, 245, 215)
sellPopupSub.ZIndex = 41

local SellPopupToken = 0
SellNotifyRemote.OnClientEvent:Connect(function(earned: any, count: any)
	SellPopupToken += 1
	local token = SellPopupToken
	sellPopupAmount.Text = "+" .. formatCoins(tonumber(earned) or 0)
	sellPopupSub.Text = string.format("Sold: %d ore", tonumber(count) or 0)
	sellPopup.Position = UDim2.new(0.5, 0, 0.3, 24)
	sellPopup.BackgroundTransparency = 0.1
	sellPopup.Visible = true
	TweenService:Create(sellPopup, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.3, 0),
	}):Play()
	task.delay(2.4, function()
		if token ~= SellPopupToken then return end
		local tw = TweenService:Create(sellPopup, TweenInfo.new(0.35), { Position = UDim2.new(0.5, 0, 0.3, -30), BackgroundTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		if token == SellPopupToken then sellPopup.Visible = false end
	end)
end)

-- ============================================================================
-- 7. ПРИЦЕЛ И ИНДИКАТОР ПОРОДЫ
-- ============================================================================
local crosshair = Instance.new("Frame", screenGui)
crosshair.Size = UDim2.new(0, 36, 0, 36)
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.BackgroundTransparency = 1
crosshair.Visible = false
crosshair.ZIndex = 25

local chRing = Instance.new("Frame", crosshair)
chRing.Size = UDim2.new(1, 0, 1, 0)
chRing.BackgroundTransparency = 0.82
chRing.BackgroundColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", chRing).CornerRadius = UDim.new(1, 0)
local chStroke = Instance.new("UIStroke", chRing)
chStroke.Color = Color3.fromRGB(255, 225, 75)
chStroke.Thickness = 2

local hoverBox = makeModernPanel("HoverInfo", UDim2.new(0, 220, 0, 64), UDim2.new(0.5, -110, 1, 8), Color3.fromRGB(255, 220, 70), crosshair)
local hoverTitle = makeLabel(hoverBox, "Name", UDim2.new(1, -10, 0, 20), UDim2.new(0, 5, 0, 3), "Stone", Color3.fromRGB(255, 235, 95), 13, Enum.TextXAlignment.Center)
local hoverSub = makeLabel(hoverBox, "ReqPick", UDim2.new(1, -10, 0, 16), UDim2.new(0, 5, 0, 21), "Pickaxe Lv.1+ · ~2.5 s", Color3.fromRGB(200, 220, 240), 11, Enum.TextXAlignment.Center)

local hoverHpBg = Instance.new("Frame", hoverBox)
hoverHpBg.Size = UDim2.new(1, -16, 0, 14)
hoverHpBg.Position = UDim2.new(0, 8, 0, 42)
hoverHpBg.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
Instance.new("UICorner", hoverHpBg).CornerRadius = UDim.new(1, 0)
local hoverHpFill = Instance.new("Frame", hoverHpBg)
hoverHpFill.Size = UDim2.new(1, 0, 1, 0)
hoverHpFill.BackgroundColor3 = Color3.fromRGB(75, 230, 105)
Instance.new("UICorner", hoverHpFill).CornerRadius = UDim.new(1, 0)
local hoverHpTxt = makeLabel(hoverHpBg, "Txt", UDim2.new(1, 0, 1, 0), UDim2.new(), "42 / 42 HP", Color3.new(1, 1, 1), 11, Enum.TextXAlignment.Center)

local selectionBox = Instance.new("SelectionBox", screenGui)
selectionBox.LineThickness = 0.045
selectionBox.SurfaceTransparency = 0.9

-- ============================================================================
-- 8. ОБНОВЛЕНИЕ ВСЕГО ИНТЕРФЕЙСА И ГОРЯЧИЕ КЛАВИШИ
-- ============================================================================
local function refreshUI()
	if hud then hud:Update(State) end

	local eRatio = math.clamp(State.Energy / math.max(1, State.MaxEnergy), 0, 1)
	TweenService:Create(energyFill, TweenInfo.new(0.25), { Size = UDim2.new(eRatio, 0, 1, 0) }):Play()
	energyFill.BackgroundColor3 = Color3.fromRGB(245, 85, 65):Lerp(Color3.fromRGB(65, 225, 135), eRatio)
	energyLbl.Text = string.format("Energy: %d / %d (+%.1f/s)", State.Energy, State.MaxEnergy, State.EnergyRegen)

	do -- v32: dirt stage instead of %
		local stg = GameConfig.GetDirtStage(State.DirtBlocks or 0)
		local pen = math.floor(GameConfig.GetDirtPenalty(State.DirtBlocks or 0) * 100 + 0.5)
		local dirtTxt = GameConfig.GetDirtStageName(stg) .. (pen > 0 and string.format(" (-%d%%)", pen) or "")
		bagSummaryLbl.Text = string.format("Filled: %d / %d slots · Dirt: %s · 🍔 x%d · Total value: +%d 💰", State.BagUsed, State.BagMax, dirtTxt, State.FoodStock or 0, State.BagValue)
	end

	if bagModal.Visible then
		rebuildInventorySlots()
	end
	if shopModal.Visible then
		refreshShopView()
	end
end

SyncPlayerData.OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" then return end
	State.Coins = data.Coins or State.Coins
	State.Level = data.Level or State.Level
	State.XP = data.XP or State.XP
	State.RequiredXP = data.RequiredXP or State.RequiredXP
	State.Strength = data.Strength or State.Strength
	State.StrengthXP = data.StrengthXP or State.StrengthXP
	State.RequiredStrengthXP = data.RequiredStrengthXP or State.RequiredStrengthXP
	State.Energy = (data.Energy ~= nil) and data.Energy or State.Energy
	State.MaxEnergy = data.MaxEnergy or State.MaxEnergy
	State.EnergyRegen = data.EnergyRegen or State.EnergyRegen
	State.HitDamage = data.HitDamage or State.HitDamage
	State.PickaxeTier = (data.PickaxeTier ~= nil) and data.PickaxeTier or State.PickaxeTier
	State.UnlockedPickaxes = data.UnlockedPickaxes or State.UnlockedPickaxes
	State.BackpackLevel = data.BackpackLevel or State.BackpackLevel
	State.UnlockedBackpacks = data.UnlockedBackpacks or State.UnlockedBackpacks
	State.BagUsed = data.BagUsed or 0
	State.BagMax = data.BagMax or State.BagMax
	State.BagValue = data.BagValue or 0
	State.BagDirt = data.BackpackDirt or 0
	State.DirtBlocks = data.DirtBlocks or 0
	State.FoodStock = data.FoodStock or 0
	State.MaxDepthReached = data.MaxDepthReached or State.MaxDepthReached
	State.Inventory = data.Inventory or State.Inventory
	State.MorningInventory = data.MorningInventory or State.MorningInventory
	State.AttackCooldown = data.AttackCooldown or State.AttackCooldown
	State.Prestige = data.Prestige or State.Prestige
	refreshUI()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.I then
		shopModal.Visible = false
		bagModal.Visible = not bagModal.Visible
		if bagModal.Visible then rebuildInventorySlots() end
	elseif input.KeyCode == Enum.KeyCode.M then
		goToShop() -- v27: same as the Shop button
	elseif input.KeyCode == Enum.KeyCode.G then
		if not shopModal.Visible and not bagModal.Visible then
			local now = os.clock()
			if (now - LastSpawnClickClock) >= GameConfig.SPAWN_TELEPORT_COOLDOWN then
				LastSpawnClickClock = now
				TeleportToSpawnRemote:FireServer()
			end
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		shopModal.Visible = false
		bagModal.Visible = false
	elseif shopModal.Visible and input.KeyCode == Enum.KeyCode.Left then
		stepShopLevel(-1)
	elseif shopModal.Visible and input.KeyCode == Enum.KeyCode.Right then
		stepShopLevel(1)
	end
end)

UserInputService.TouchSwipe:Connect(function(swipeDir: Enum.SwipeDirection, _numTouches: number, gpe: boolean)
	if gpe or not shopModal.Visible then return end
	if swipeDir == Enum.SwipeDirection.Left then
		stepShopLevel(1)
	elseif swipeDir == Enum.SwipeDirection.Right then
		stepShopLevel(-1)
	elseif swipeDir == Enum.SwipeDirection.Down then
		shopModal.Visible = false
	end
end)

-- ============================================================================
-- 9. УДАР КИРКОЙ ПО БЛОКУ + ВРАЩЕНИЕ 3D-МОДЕЛИ В МАГАЗИНЕ + ЗОНЫ SHOP / SELL
-- ============================================================================
local HoveredBlock: BasePart? = nil
local IsMouseDown = false
local LastSwingClock = 0

local function shakeCamera(intensity: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	task.spawn(function()
		for _ = 1, 4 do
			local dx = (math.random() - 0.5) * intensity
			local dy = (math.random() - 0.5) * intensity
			cam.CFrame = cam.CFrame * CFrame.new(dx, dy, 0)
			task.wait(0.025)
		end
	end)
end

local function canPlayerMineNow(char: Model?, root: BasePart?): boolean
	if not char or not root then return false end
	-- 1) Must be inside the Mine Zone
	local zb = GameConfig.MINE_ZONE_BOUNDS
	local pos = root.Position
	local inZone = (char:GetAttribute("InMineZone") == true)
		and (pos.X >= zb.MinX and pos.X <= zb.MaxX and pos.Z >= zb.MinZ and pos.Z <= zb.MaxZ and pos.Y <= zb.TopY)
	if not inZone then return false end
	-- 2) Must have an active visible Pickaxe equipped in hand
	local visualPick = char:FindFirstChild("VisualPickaxe")
	if not visualPick or char:GetAttribute("PickaxeHidden") == true or visualPick:GetAttribute("Shown") == false then
		return false
	end
	local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	if not hand or not hand:FindFirstChild("PickaxeMotor") then
		return false
	end
	return true
end

local function raycastMineBlock(): BasePart?
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local blocksFolder = Workspace:FindFirstChild("MineBlocks")
	if not cam or not char or not root or not blocksFolder then return nil end

	-- v49: Cannot target or mine blocks outside the mine zone or without a pickaxe in hand
	if not canPlayerMineNow(char, root) then
		return nil
	end

	local mPos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mPos.X, mPos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { blocksFolder }

	-- Limit camera ray distance so distant blocks can't even be raycasted
	local camToRoot = (cam.CFrame.Position - root.Position).Magnitude
	local maxRayLen = camToRoot + GameConfig.MAX_MINE_DISTANCE + 4
	local res = Workspace:Raycast(ray.Origin, ray.Direction * maxRayLen, params)
	if not res or not res.Instance then return nil end

	local hit = res.Instance
	while hit and hit.Parent and not hit:GetAttribute("IsMineBlock") and hit ~= blocksFolder do
		hit = hit.Parent :: BasePart
	end

	if hit and hit:IsA("BasePart") and hit:GetAttribute("IsMineBlock") then
		local bPos = (hit:GetAttribute("OriginPos") :: Vector3) or hit.Position
		local delta = root.Position - bPos
		local maxAxial = math.max(math.abs(delta.X), math.abs(delta.Y), math.abs(delta.Z))
		-- v49: Strictly first 2 blocks in radius (12.0 studs / 2 * 6.0 block width)
		if delta.Magnitude <= GameConfig.MAX_MINE_DISTANCE and maxAxial <= (GameConfig.BLOCK_WIDTH * 2.08) then
			return hit
		end
	end
	return nil
end

local function swingPickaxeAtBlock()
	if bagModal.Visible or shopModal.Visible or player:GetAttribute("ProgressionUIOpen") then return end
	local target = HoveredBlock or raycastMineBlock()
	if not target then return end

	local now = os.clock()
	if (now - LastSwingClock) < State.AttackCooldown then return end
	LastSwingClock = now

	ToolAnimator.PlaySwing(player.Character, false)

	local hitSoundKey = tostring(target:GetAttribute("HitSound") or "StoneTap")
	SoundManager.PlayQuietTap(hitSoundKey, target.Position, target)

	local accentCol = (target:GetAttribute("AccentColor") :: Color3) or target.Color
	VFXModule.PlayHitShakeAndParticles(target, accentCol)
	shakeCamera(0.08)

	MineBlockRemote:FireServer(target)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
	if gpe then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		IsMouseDown = true
		swingPickaxeAtBlock()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		IsMouseDown = false
	end
end)

local WasOnShopPad = false
local WasOnSellPad = false
local LastDepthAmbientUpdate = 0
local ViewportSpinAngle = 0

task.spawn(function()
	while task.wait(5.5) do
		if CurrentDepthBlocks >= 6 then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local soundChoice = (math.random() < 0.7) and "CaveDrip" or "CaveEcho"
				SoundManager.PlayQuietTap(soundChoice, root.Position + Vector3.new(math.random(-12, 12), math.random(-4, 8), math.random(-12, 12)))
			end
		end
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	-- Плавное 3D-вращение модели в окне 3D-Магазина
	if shopModal.Visible and ActiveViewportModel and ActiveViewportModel.PrimaryPart then
		ViewportSpinAngle = (ViewportSpinAngle + dt * 55) % 360
		pcall(function()
			if ShopCategory == "Pickaxes" then
				ActiveViewportModel:PivotTo(CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(15), math.rad(ViewportSpinAngle), math.rad(-25)))
			else
				ActiveViewportModel:PivotTo(CFrame.new(0, -0.1, 0) * CFrame.Angles(0, math.rad(ViewportSpinAngle), 0))
			end
		end)
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	if root then
		local pos = root.Position
		local rawDepth = math.floor((0 - pos.Y) / GameConfig.BLOCK_HEIGHT)
		local clampedDepth = math.clamp(rawDepth, 0, GameConfig.MINE_LEVELS_COUNT)
		if clampedDepth ~= CurrentDepthBlocks then
			CurrentDepthBlocks = clampedDepth
			updateClockAndDepthText()
		end

		-- v49: Smooth progressive darkness with depth + dynamic Hard Hat Headlamp boost
		local now = os.clock()
		if (now - LastDepthAmbientUpdate) > 0.08 then
			LastDepthAmbientUpdate = now
			local inMine = (char:GetAttribute("InMineZone") == true) or (pos.Y < -1.5)
			local totalDepthStuds = GameConfig.MINE_LEVELS_COUNT * GameConfig.BLOCK_HEIGHT
			local smoothDepth = inMine and math.clamp((-pos.Y) / totalDepthStuds, 0, 1) or 0
			-- Non-linear curve so darkness already feels atmospheric by depth 3..8 and pitch-deep below 15
			local darkFactor = math.clamp(smoothDepth ^ 0.72, 0, 1)

			-- v50: shared GameConfig.LIGHTING values; the bottom stays readable instead of pitch black
			local L = GameConfig.LIGHTING
			local surfBright = IsNightMode and L.NightBrightness or L.DayBrightness
			local surfAmbient = IsNightMode and L.NightAmbient or L.DayAmbient
			local surfOutdoor = IsNightMode and L.NightOutdoorAmbient or L.DayOutdoorAmbient

			Lighting.Brightness = surfBright * (1 - darkFactor * L.DeepDarkness)
			Lighting.Ambient = surfAmbient:Lerp(L.DeepAmbient, darkFactor)
			Lighting.OutdoorAmbient = surfOutdoor:Lerp(L.DeepOutdoorAmbient, darkFactor)
			Lighting.ExposureCompensation = L.DeepExposure * darkFactor

			local atm = Lighting:FindFirstChild("MineAtmosphere") :: Atmosphere?
			if atm then
				atm.Density = 0.24 + darkFactor * L.DeepAtmosphereExtraDensity
				atm.Color = Color3.fromRGB(185, 210, 240):Lerp(Color3.fromRGB(26, 28, 44), darkFactor)
				atm.Decay = Color3.fromRGB(95, 115, 145):Lerp(Color3.fromRGB(16, 18, 30), darkFactor)
			end

			-- Boost the player's Hard Hat Headlamp as it gets darker so it illuminates the shaft ahead
			local hat = char:FindFirstChild("MinerHardHat")
			if hat then
				local lensLight = hat:FindFirstChild("MinerHelmetLight", true) :: SpotLight?
				if lensLight then
					lensLight.Brightness = 2.0 + darkFactor * 2.8
					lensLight.Range = 30 + darkFactor * 24
				end
				local mainBeam = hat:FindFirstChild("MinerHelmetSpotLight", true) :: SpotLight?
				if mainBeam then
					mainBeam.Brightness = 2.4 + darkFactor * 3.4
					mainBeam.Range = 36 + darkFactor * 26
				end
				local fillLight = hat:FindFirstChild("MinerHelmetPointLight", true) :: PointLight?
				if fillLight then
					fillLight.Brightness = 1.1 + darkFactor * 1.65
					fillLight.Range = 18 + darkFactor * 12
				end
			end
		end

		-- Зона Неонового Павильона "SHOP"
		local shopPadPos = GameConfig.GREEN_SHOP_PAD_POS + Vector3.new(0, 0.35, 4.0)
		local distShop = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(shopPadPos.X, 0, shopPadPos.Z)).Magnitude
		local onShopPad = (distShop <= 6.2) and (math.abs(pos.Y - shopPadPos.Y) < 6)

		if onShopPad and not WasOnShopPad then
			WasOnShopPad = true
			bagModal.Visible = false
			shopModal.Visible = true
			SoundManager.PlayUISound("ShopOpen") -- v28: shop open swoosh
			refreshShopView()
		elseif not onShopPad and WasOnShopPad then
			WasOnShopPad = false
			shopModal.Visible = false
		end

		-- v14: окно продажи не открывается. Автопродажу выполняет сервер при входе в зону «$ SELL».
	end

	if bagModal.Visible or shopModal.Visible or player:GetAttribute("ProgressionUIOpen") then
		crosshair.Visible = false
		selectionBox.Adornee = nil
		UserInputService.MouseIconEnabled = true
		return
	end

	local mPos = UserInputService:GetMouseLocation()
	crosshair.Position = UDim2.new(0, mPos.X, 0, mPos.Y)

	local target = raycastMineBlock()
	HoveredBlock = target

	if target then
		crosshair.Visible = true
		UserInputService.MouseIconEnabled = false
		selectionBox.Adornee = target

		local hp = (target:GetAttribute("HP") :: number) or 20
		local maxHp = (target:GetAttribute("MaxHP") :: number) or 20
		local bName = tostring(target:GetAttribute("BlockName") or "Stone")
		local minPick = (target:GetAttribute("MinPickaxeLevel") :: number) or 1
		local targetTime = tostring(target:GetAttribute("TargetMineTimeSec") or "2.5 s")
		local reqCfg = GameConfig.PICKAXE_TIERS[minPick] or GameConfig.PICKAXE_TIERS[1]
		local hasPick = State.PickaxeTier >= minPick

		local ratio = math.clamp(hp / math.max(1, maxHp), 0, 1)
		local col = hasPick
			and Color3.fromRGB(245, 65, 65):Lerp(Color3.fromRGB(75, 230, 105), ratio)
			or Color3.fromRGB(255, 75, 75)

		selectionBox.Color3 = col
		chStroke.Color = col
		hoverTitle.Text = bName
		hoverSub.Text = hasPick
			and string.format("⛏️ Lv.%d %s+ · ⏱ %s", minPick, reqCfg.ShortName, targetTime)
			or string.format("⚠️ You need %s (Lv.%d)!", reqCfg.ShortName, minPick)
		hoverSub.TextColor3 = hasPick and Color3.fromRGB(190, 230, 210) or Color3.fromRGB(255, 105, 95)

		hoverHpFill.Size = UDim2.new(ratio, 0, 1, 0)
		hoverHpFill.BackgroundColor3 = col
		hoverHpTxt.Text = string.format("%d / %d HP", math.max(0, hp), maxHp)

		if IsMouseDown then
			swingPickaxeAtBlock()
		end
	else
		crosshair.Visible = false
		selectionBox.Adornee = nil
		UserInputService.MouseIconEnabled = true
	end
end)

refreshUI()
print("✅ [ClientController] Ready")
