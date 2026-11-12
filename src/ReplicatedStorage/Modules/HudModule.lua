--!nonstrict
-- ============================================================================
-- HudModule (v10 · ЗАДАЧА 1 — красивые плашки UI)
-- ----------------------------------------------------------------------------
-- Верхние плашки:  🎒 Рюкзак · ⛏️ Кирка · 💰 Монеты   (по центру сверху)
-- Левые плашки:    💪 Сила · ⭐ Уровень · ✨ Опыт      (колонка слева)
-- Стиль: тёмный градиент RGB(25,25,35)→(40,40,55), UICorner 12, UIStroke 2px
-- цвета акцента, мягкая тень (чёрная, прозрачность 0.5), иконка слева,
-- маленький заголовок сверху, крупное значение снизу.
-- Анимации: bounce значения 1→1.2→1, hover 1.05, въезд сверху/слева с fade,
-- плавное заполнение полос, вспышка + звук при росте, счётчик монет.
--
-- Использование (ClientController):
--   local hud = HudModule.new(screenGui, { OnBackpackClick = function() ... end })
--   hud:Update(State)   -- State: Coins, BagUsed, BagMax, PickaxeTier, Strength,
--                       -- StrengthXP, RequiredStrengthXP, Level, XP, RequiredXP, Prestige
--   hud.LeftColumn      -- сюда ProgressionUI ставит кнопки Навыки/Достижения/Престиж
-- ============================================================================

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local SoundManager = require(Modules:WaitForChild("SoundManager"))
local ProgressionConfig = require(Modules:WaitForChild("ProgressionConfig"))

local HudModule = {}
HudModule.__index = HudModule

-- ============================================================================
-- НАСТРОЙКИ (меняйте здесь)
-- ============================================================================
-- ID иконок после загрузки PNG из папки icons/ через Asset Manager
-- (формат "rbxassetid://123456789"). Пусто = эмодзи-иконка в цветной плитке.
HudModule.ICONS = {
	Backpack = "",
	Pickaxe  = "",
	Coins    = "",
	Strength = "",
	Level    = "",
	XP       = "",
}

local EMOJI = {
	Backpack = "🎒", Pickaxe = "⛏️", Coins = "💰",
	Strength = "💪", Level = "⭐", XP = "✨",
}

-- v25: glowing navy plates like the reference screenshot
local ACCENT = {
	Backpack = Color3.fromRGB(70, 215, 255),
	Pickaxe  = Color3.fromRGB(70, 215, 255),
	Coins    = Color3.fromRGB(70, 215, 255),
	Strength = Color3.fromRGB(255, 176, 60),
	Level    = Color3.fromRGB(70, 200, 255),
	XP       = Color3.fromRGB(110, 170, 255),
}
-- colour of the icon tile on the left side of each plate
local TILE = {
	Backpack = Color3.fromRGB(255, 140, 40),
	Pickaxe  = Color3.fromRGB(90, 170, 255),
	Coins    = Color3.fromRGB(255, 196, 40),
	Strength = Color3.fromRGB(255, 150, 40),
	Level    = Color3.fromRGB(60, 150, 255),
	XP       = Color3.fromRGB(150, 90, 255),
}

local BG_TOP = Color3.fromRGB(40, 70, 162) -- v25: navy
local BG_BOTTOM = Color3.fromRGB(16, 28, 86) -- v25: navy
local CORNER = 16
local STROKE = 3
local SHADOW_OFFSET = Vector2.new(3, 4)
local SHADOW_TRANSPARENCY = 0.5

local TOP_CARD_SIZE = Vector2.new(196, 72)
local TOP_GAP = 20
local TOP_Y = 14
local LEFT_CARD_SIZE = Vector2.new(240, 72)
local LEFT_GAP = 10
local LEFT_POS = UDim2.new(0, 14, 0, 70) -- ниже системных кнопок Roblox
local MAX_PICKAXE_STARS = 10 -- v11: 9 уровней кирки (Деревянная → Адамантиевая)

-- Градиент полос прогресса: зелёный → жёлтый → красный
local BAR_GREEN  = Color3.fromRGB(70, 225, 95)
local BAR_YELLOW = Color3.fromRGB(255, 210, 50)
local BAR_RED    = Color3.fromRGB(245, 65, 65)

-- ============================================================================
-- ВСПОМОГАТЕЛЬНОЕ
-- ============================================================================
local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function corner(obj: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
	return c
end

function HudModule.FormatNumber(n: number): string
	n = math.floor(n + 0.5)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (n < 0 and "-" or "") .. out
end

-- цвет точки t (0..1) на градиенте зелёный→жёлтый→красный
local function barColorAt(t: number): Color3
	t = math.clamp(t, 0, 1)
	if t < 0.5 then
		return BAR_GREEN:Lerp(BAR_YELLOW, t * 2)
	end
	return BAR_YELLOW:Lerp(BAR_RED, (t - 0.5) * 2)
end

-- Градиент для заполненной части: срез 0..ratio общего градиента,
-- чтобы полупустая полоса была зелёно-жёлтой, а полная доходила до красного.
local function barSequence(ratio: number): ColorSequence
	ratio = math.clamp(ratio, 0.001, 1)
	if ratio <= 0.5 then
		return ColorSequence.new(BAR_GREEN, barColorAt(ratio))
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, BAR_GREEN),
		ColorSequenceKeypoint.new(math.clamp(0.5 / ratio, 0.01, 0.99), BAR_YELLOW),
		ColorSequenceKeypoint.new(1, barColorAt(ratio)),
	})
end

local function getViewportScale(): number
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 760)
	return math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.55, 1.15)
end

-- Плавное появление: запоминаем исходную прозрачность всех элементов,
-- ставим 1 и возвращаем твином.
local function captureFade(root: Instance)
	local list = {}
	local function add(obj: Instance)
		if obj:IsA("UIStroke") then
			table.insert(list, { obj, { Transparency = obj.Transparency } })
		elseif obj:IsA("TextLabel") or obj:IsA("TextButton") then
			table.insert(list, { obj, { TextTransparency = obj.TextTransparency, BackgroundTransparency = obj.BackgroundTransparency } })
		elseif obj:IsA("ImageLabel") then
			table.insert(list, { obj, { ImageTransparency = obj.ImageTransparency, BackgroundTransparency = obj.BackgroundTransparency } })
		elseif obj:IsA("Frame") then
			table.insert(list, { obj, { BackgroundTransparency = obj.BackgroundTransparency } })
		end
	end
	add(root)
	for _, d in ipairs(root:GetDescendants()) do add(d) end
	return list
end

local function hideForFade(list)
	for _, item in ipairs(list) do
		local obj, props = item[1], item[2]
		for k in pairs(props) do obj[k] = 1 end
	end
end

local function playFade(list, t: number)
	for _, item in ipairs(list) do
		tween(item[1], t, item[2])
	end
end

-- ============================================================================
-- ПЛАШКА
-- ============================================================================
type Card = {
	Key: string,
	Holder: Frame,
	Wrap: Frame,
	Body: Frame,
	Stroke: UIStroke,
	Title: TextLabel,
	Value: TextLabel,
	ValueScale: UIScale,
	Sub: TextLabel?,
	Fill: Frame?,
	FillGradient: UIGradient?,
	Flash: Frame,
	Icon: GuiObject,
	Button: TextButton,
	HomePos: UDim2,
}

-- v26: vector icons drawn with frames (same pictures as the reference HUD, no emoji).
-- Shape = { kind ("r" frame / "x" text), x, y, w, h, rotation, radius (share of the short side),
--          colour top, colour bottom, gradient rotation, stroke colour, stroke width, transparency, text }
-- in a 100 x 100 design box, scaled to the requested size.
local ICON_SPECS = {
	Strength = {
		{ "r", 50, 50, 92, 92, 0, 0.26, "#ffb04a", "#f0641a", 90, "#b24a0c", 3, 0, "" },
		{ "r", 50, 27, 80, 34, 0, 0.45, "#ffffff", "#ffffff", 90, "#000000", 0, 0.8, "" },
		{ "r", 44.56, 70.32, 40.8, 19.04, 0, 0.5, "#ffd98e", "#f2a23a", 90, "#7a3a08", 2.8, 0, "" },
		{ "r", 41.84, 60.8, 28.56, 23.12, 0, 0.5, "#ffe2a4", "#f5ac44", 90, "#7a3a08", 2.8, 0, "" },
		{ "r", 60.88, 52.64, 17.68, 35.36, 12, 0.5, "#ffd98e", "#f2a23a", 90, "#7a3a08", 2.8, 0, "" },
		{ "r", 58.16, 34.96, 23.12, 19.04, 0, 0.45, "#ffe2a4", "#f5ac44", 90, "#7a3a08", 2.8, 0, "" },
		{ "r", 44.56, 70.32, 40.8, 19.04, 0, 0.5, "#ffd98e", "#f2a23a", 90, "#000000", 0, 0, "" },
		{ "r", 41.84, 60.8, 28.56, 23.12, 0, 0.5, "#ffe2a4", "#f5ac44", 90, "#000000", 0, 0, "" },
		{ "r", 60.88, 52.64, 17.68, 35.36, 12, 0.5, "#ffd98e", "#f2a23a", 90, "#000000", 0, 0, "" },
		{ "r", 58.16, 34.96, 23.12, 19.04, 0, 0.45, "#ffe2a4", "#f5ac44", 90, "#000000", 0, 0, "" },
		{ "r", 54.08, 37.68, 9.52, 2.04, 0, 0.5, "#c47a22", "#c47a22", 90, "#000000", 0, 0.1, "" },
		{ "r", 52.72, 58.08, 2.72, 10.88, 30, 0.5, "#c47a22", "#c47a22", 90, "#000000", 0, 0.2, "" },
		{ "r", 36.4, 55.36, 10.88, 5.44, -15, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.35, "" },
	},
	Level = {
		{ "r", 50, 50, 92, 92, 0, 0.26, "#6fd2ff", "#1f6be6", 90, "#1a4aa8", 3, 0, "" },
		{ "r", 50, 27, 80, 34, 0, 0.45, "#ffffff", "#ffffff", 90, "#000000", 0, 0.8, "" },
		{ "x", 50, 54, 74, 74, 0, 0, "#fff27a", "#ffae18", 90, "#cf6e0a", 4, 0, "\u{2605}" },
	},
	XP = {
		{ "r", 50, 50, 92, 92, 0, 0.26, "#bc8fff", "#6a30d8", 90, "#4a1c9e", 3, 0, "" },
		{ "r", 50, 27, 80, 34, 0, 0.45, "#ffffff", "#ffffff", 90, "#000000", 0, 0.8, "" },
		{ "p", { 51.48, 17.96, 70.72, 17.96, 57.4, 44.6, 72.2, 44.6, 36.68, 86.04, 44.08, 56.44, 27.8, 56.44 }, "#fff27a", "#ffa514", "#7a3606", 5, 0 },
		{ "p", { 53.7, 22.4, 61.84, 22.4, 48.52, 49.04, 40.38, 49.04 }, "#ffffff", "#ffffff", "#000000", 0, 0.45 },
	},
	BackpackTile = {
		{ "r", 50, 50, 92, 92, 0, 0.26, "#c95cff", "#7a2ad6", 90, "#5a1a9e", 3, 0, "" },
		{ "r", 50, 27, 80, 34, 0, 0.45, "#ffffff", "#ffffff", 90, "#000000", 0, 0.8, "" },
		{ "r", 50, 24.8, 22.4, 14.4, 0, 0.5, "#000000", "#000000", 90, "#5a1c0a", 4.8, 1, "" },
		{ "r", 23.6, 63.2, 12.8, 32, 0, 0.4, "#ff8a48", "#e2441a", 90, "#5a1c0a", 3.2, 0, "" },
		{ "r", 76.4, 63.2, 12.8, 32, 0, 0.4, "#ff8a48", "#e2441a", 90, "#5a1c0a", 3.2, 0, "" },
		{ "r", 50, 58.4, 52.8, 56, 0, 0.3, "#ff8a48", "#e2441a", 90, "#5a1c0a", 3.2, 0, "" },
		{ "r", 23.6, 63.2, 12.8, 32, 0, 0.4, "#ff8a48", "#e2441a", 90, "#000000", 0, 0, "" },
		{ "r", 76.4, 63.2, 12.8, 32, 0, 0.4, "#ff8a48", "#e2441a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 58.4, 52.8, 56, 0, 0.3, "#ff8a48", "#e2441a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 48, 48, 2.4, 0, 0, "#b8340f", "#b8340f", 90, "#000000", 0, 0, "" },
		{ "r", 50, 69.6, 33.6, 22.4, 0, 0.3, "#ffe66e", "#ffc12a", 90, "#5a1c0a", 2.4, 0, "" },
		{ "r", 50, 64.8, 30.4, 2, 0, 0, "#c98a10", "#c98a10", 90, "#000000", 0, 0, "" },
		{ "r", 50, 63.2, 6.4, 8, 0, 0.3, "#ffe66e", "#ffe66e", 90, "#5a1c0a", 1.6, 0, "" },
		{ "r", 35.6, 44, 7.2, 16, 10, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.45, "" },
	},
	PickaxeTile = {
		{ "r", 50, 50, 92, 92, 0, 0.26, "#62b4f2", "#2a6cc8", 90, "#1a4aa8", 3, 0, "" },
		{ "r", 50, 27, 80, 34, 0, 0.45, "#ffffff", "#ffffff", 90, "#000000", 0, 0.8, "" },
		{ "r", 45.7, 57.74, 10.32, 66.27, 45, 0.5, "#ffc75e", "#c8661a", 45, "#6a3208", 2.58, 0, "" },
		{ "r", 45.7, 57.74, 10.32, 66.27, 45, 0.5, "#ffc75e", "#c8661a", 45, "#000000", 0, 0, "" },
		{ "r", 55.16, 29.79, 12.9, 39.22, -51.63, 0.5, "#eef9ff", "#5aa6f0", 141.63, "#1c3f86", 2.58, 0, "" },
		{ "r", 38.82, 21.19, 6.88, 18.95, -85.91, 0.5, "#eef9ff", "#5aa6f0", 175.91, "#1c3f86", 2.58, 0, "" },
		{ "r", 73.65, 48.28, 12.9, 39.22, 141.63, 0.5, "#eef9ff", "#5aa6f0", -51.63, "#1c3f86", 2.58, 0, "" },
		{ "r", 82.25, 64.62, 6.88, 18.95, 175.91, 0.5, "#eef9ff", "#5aa6f0", -85.91, "#1c3f86", 2.58, 0, "" },
		{ "r", 55.16, 29.79, 12.9, 39.22, -51.63, 0.5, "#eef9ff", "#5aa6f0", 141.63, "#000000", 0, 0, "" },
		{ "r", 38.82, 21.19, 6.88, 18.95, -85.91, 0.5, "#eef9ff", "#5aa6f0", 175.91, "#000000", 0, 0, "" },
		{ "r", 73.65, 48.28, 12.9, 39.22, 141.63, 0.5, "#eef9ff", "#5aa6f0", -51.63, "#000000", 0, 0, "" },
		{ "r", 82.25, 64.62, 6.88, 18.95, 175.91, 0.5, "#eef9ff", "#5aa6f0", -85.91, "#000000", 0, 0, "" },
		{ "r", 65.48, 37.96, 14.62, 14.62, 45, 0.25, "#ffe27a", "#d08a1a", 45, "#6a3208", 2.58, 0, "" },
		{ "r", 51.72, 27.64, 4.3, 13.76, -45, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.3, "" },
	},
	Coins = {
		{ "r", 50, 54, 77.94, 45, 0, 0.12, "#d4840e", "#d4840e", 90, "#8a4a06", 4, 0, "" },
		{ "r", 50, 54, 77.94, 45, 60, 0.12, "#d4840e", "#d4840e", 90, "#8a4a06", 4, 0, "" },
		{ "r", 50, 54, 77.94, 45, 120, 0.12, "#d4840e", "#d4840e", 90, "#8a4a06", 4, 0, "" },
		{ "r", 50, 54, 77.94, 45, 0, 0.12, "#d4840e", "#d4840e", 90, "#000000", 0, 0, "" },
		{ "r", 50, 54, 77.94, 45, 60, 0.12, "#d4840e", "#d4840e", 90, "#000000", 0, 0, "" },
		{ "r", 50, 54, 77.94, 45, 120, 0.12, "#d4840e", "#d4840e", 90, "#000000", 0, 0, "" },
		{ "r", 50, 50, 77.94, 45, 0, 0.12, "#ffd23f", "#ffd23f", 90, "#b86208", 4, 0, "" },
		{ "r", 50, 50, 77.94, 45, 60, 0.12, "#ffd23f", "#ffd23f", 90, "#b86208", 4, 0, "" },
		{ "r", 50, 50, 77.94, 45, 120, 0.12, "#ffd23f", "#ffd23f", 90, "#b86208", 4, 0, "" },
		{ "r", 50, 50, 77.94, 45, 0, 0.12, "#ffd23f", "#ffd23f", 90, "#000000", 0, 0, "" },
		{ "r", 50, 50, 77.94, 45, 60, 0.12, "#ffd23f", "#ffd23f", 90, "#000000", 0, 0, "" },
		{ "r", 50, 50, 77.94, 45, 120, 0.12, "#ffd23f", "#ffd23f", 90, "#000000", 0, 0, "" },
		{ "r", 50, 50, 57.16, 33, 0, 0.12, "#f5a51f", "#f5a51f", 90, "#d98a12", 2.5, 0, "" },
		{ "r", 50, 50, 57.16, 33, 60, 0.12, "#f5a51f", "#f5a51f", 90, "#d98a12", 2.5, 0, "" },
		{ "r", 50, 50, 57.16, 33, 120, 0.12, "#f5a51f", "#f5a51f", 90, "#d98a12", 2.5, 0, "" },
		{ "r", 50, 50, 57.16, 33, 0, 0.12, "#f5a51f", "#f5a51f", 90, "#000000", 0, 0, "" },
		{ "r", 50, 50, 57.16, 33, 60, 0.12, "#f5a51f", "#f5a51f", 90, "#000000", 0, 0, "" },
		{ "r", 50, 50, 57.16, 33, 120, 0.12, "#f5a51f", "#f5a51f", 90, "#000000", 0, 0, "" },
		{ "x", 50, 52, 44, 52, 0, 0, "#fff3a8", "#ffcf3a", 90, "#b0600a", 3, 0, "$" },
		{ "r", 30, 32, 9, 20, 30, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.45, "" },
	},
	Backpack = {
		{ "r", 50, 16, 28, 18, 0, 0.5, "#000000", "#000000", 90, "#5a1c0a", 6, 1, "" },
		{ "r", 17, 64, 16, 40, 0, 0.4, "#ff8a48", "#e2441a", 90, "#5a1c0a", 4, 0, "" },
		{ "r", 83, 64, 16, 40, 0, 0.4, "#ff8a48", "#e2441a", 90, "#5a1c0a", 4, 0, "" },
		{ "r", 50, 58, 66, 70, 0, 0.3, "#ff8a48", "#e2441a", 90, "#5a1c0a", 4, 0, "" },
		{ "r", 17, 64, 16, 40, 0, 0.4, "#ff8a48", "#e2441a", 90, "#000000", 0, 0, "" },
		{ "r", 83, 64, 16, 40, 0, 0.4, "#ff8a48", "#e2441a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 58, 66, 70, 0, 0.3, "#ff8a48", "#e2441a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 45, 60, 3, 0, 0, "#b8340f", "#b8340f", 90, "#000000", 0, 0, "" },
		{ "r", 50, 72, 42, 28, 0, 0.3, "#ffe66e", "#ffc12a", 90, "#5a1c0a", 3, 0, "" },
		{ "r", 50, 66, 38, 2.5, 0, 0, "#c98a10", "#c98a10", 90, "#000000", 0, 0, "" },
		{ "r", 50, 64, 8, 10, 0, 0.3, "#ffe66e", "#ffe66e", 90, "#5a1c0a", 2, 0, "" },
		{ "r", 32, 40, 9, 20, 10, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.45, "" },
	},
	Cart = {
		{ "r", 14, 20, 22, 9, 0, 0.5, "#ffffff", "#ffffff", 90, "#1756c8", 5, 0, "" },
		{ "r", 24.5, 45, 9, 60.66, 165.43, 0.5, "#ffffff", "#ffffff", -75.43, "#1756c8", 5, 0, "" },
		{ "r", 58, 46, 62, 38, 0, 0.16, "#ffffff", "#ffffff", 90, "#1756c8", 5, 0, "" },
		{ "r", 56, 73, 54, 9, 0, 0.5, "#ffffff", "#ffffff", 90, "#1756c8", 5, 0, "" },
		{ "r", 14, 20, 22, 9, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0, "" },
		{ "r", 24.5, 45, 9, 60.66, 165.43, 0.5, "#ffffff", "#ffffff", -75.43, "#000000", 0, 0, "" },
		{ "r", 58, 46, 62, 38, 0, 0.16, "#ffffff", "#ffffff", 90, "#000000", 0, 0, "" },
		{ "r", 56, 73, 54, 9, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0, "" },
		{ "r", 47, 46, 4.5, 28, 0, 0, "#1d3f9a", "#1d3f9a", 90, "#000000", 0, 0, "" },
		{ "r", 68, 46, 4.5, 28, 0, 0, "#1d3f9a", "#1d3f9a", 90, "#000000", 0, 0, "" },
		{ "r", 58, 46, 52, 4.5, 0, 0, "#1d3f9a", "#1d3f9a", 90, "#000000", 0, 0, "" },
		{ "r", 37, 87, 15, 15, 0, 0.5, "#ffffff", "#ffffff", 90, "#1756c8", 5, 0, "" },
		{ "r", 75, 87, 15, 15, 0, 0.5, "#ffffff", "#ffffff", 90, "#1756c8", 5, 0, "" },
	},
	MoneyBag = {
		{ "r", 39, 15, 22, 15, -25, 0.5, "#ffe48a", "#ffe48a", 90, "#b4842a", 4, 0, "" },
		{ "r", 61, 15, 22, 15, 25, 0.5, "#ffe48a", "#ffe48a", 90, "#b4842a", 4, 0, "" },
		{ "r", 50, 29, 26, 14, 0, 0.3, "#ffe48a", "#ffe48a", 90, "#b4842a", 4, 0, "" },
		{ "r", 50, 65, 78, 64, 0, 0.48, "#ffe48a", "#f9d571", 90, "#b4842a", 4, 0, "" },
		{ "r", 39, 15, 22, 15, -25, 0.5, "#ffe48a", "#ffe48a", 90, "#000000", 0, 0, "" },
		{ "r", 61, 15, 22, 15, 25, 0.5, "#ffe48a", "#ffe48a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 29, 26, 14, 0, 0.3, "#ffe48a", "#ffe48a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 65, 78, 64, 0, 0.48, "#ffe48a", "#f9d571", 90, "#000000", 0, 0, "" },
		{ "r", 50, 36, 36, 8, 0, 0.5, "#d99c34", "#d99c34", 90, "#8a5a14", 2, 0, "" },
		{ "x", 50, 67, 42, 48, 0, 0, "#58de72", "#1f9a3c", 90, "#0f5a22", 3, 0, "$" },
		{ "r", 27, 58, 9, 22, 15, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.4, "" },
	},
	Trophy = {
		{ "r", 23, 33, 22, 26, 0, 0.5, "#000000", "#000000", 90, "#c4800e", 6, 1, "" },
		{ "r", 77, 33, 22, 26, 0, 0.5, "#000000", "#000000", 90, "#c4800e", 6, 1, "" },
		{ "r", 50, 34, 50, 46, 0, 0.36, "#ffe866", "#f5ab1e", 90, "#8a4a06", 3.5, 0, "" },
		{ "r", 50, 63, 12, 16, 0, 0, "#f5b52a", "#f5b52a", 90, "#8a4a06", 3.5, 0, "" },
		{ "r", 50, 73, 30, 8, 0, 0.3, "#f5b52a", "#f5b52a", 90, "#8a4a06", 3.5, 0, "" },
		{ "r", 50, 84, 46, 14, 0, 0.25, "#f0a21c", "#f0a21c", 90, "#8a4a06", 3.5, 0, "" },
		{ "r", 50, 34, 50, 46, 0, 0.36, "#ffe866", "#f5ab1e", 90, "#000000", 0, 0, "" },
		{ "r", 50, 63, 12, 16, 0, 0, "#f5b52a", "#f5b52a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 73, 30, 8, 0, 0.3, "#f5b52a", "#f5b52a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 84, 46, 14, 0, 0.25, "#f0a21c", "#f0a21c", 90, "#000000", 0, 0, "" },
		{ "x", 50, 34, 30, 30, 0, 0, "#ffffff", "#fff6c8", 90, "#000000", 0, 0, "\u{2605}" },
		{ "r", 36, 28, 7, 18, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.45, "" },
	},
	Chart = {
		{ "r", 50, 91, 92, 7, 0, 0.5, "#ffffff", "#dfe8ff", 90, "#1d3f6a", 2.5, 0, "" },
		{ "r", 22, 71, 20, 34, 0, 0.22, "#9dff8e", "#26a83c", 90, "#0e4a1a", 4, 0, "" },
		{ "r", 49, 59, 20, 58, 0, 0.22, "#fff07a", "#ffb01e", 90, "#7a4206", 4, 0, "" },
		{ "r", 76, 47, 20, 82, 0, 0.22, "#ff9ad0", "#e0367e", 90, "#6a0a34", 4, 0, "" },
		{ "r", 17, 66, 5, 16, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.4, "" },
		{ "r", 44, 46, 5, 24, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.4, "" },
		{ "r", 71, 26, 5, 30, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.4, "" },
		{ "x", 76, 0, 30, 30, 0, 0, "#fff27a", "#ffae18", 90, "#b8600a", 3, 0, "\u{2605}" },
	},
	Star = {
		{ "x", 50, 52, 92, 92, 0, 0, "#fff27a", "#ffae18", 90, "#cf6e0a", 5, 0, "\u{2605}" },
	},
	Bolt = {
		{ "p", { 52, 4, 78, 4, 60, 40, 80, 40, 32, 96, 42, 56, 20, 56 }, "#ffe45a", "#ffa51e", "#b85a08", 6, 0 },
		{ "p", { 55, 10, 66, 10, 48, 46, 37, 46 }, "#ffffff", "#ffffff", "#000000", 0, 0.4 },
	},
	Moon = {
		{ "r", 50, 50, 78, 78, 0, 0.5, "#ffe066", "#ffb21e", 90, "#c87a0a", 3, 0, "" },
		{ "r", 69, 35, 56, 56, 0, 0.5, "#223c8c", "#223c8c", 90, "#000000", 0, 0, "" },
	},
}

local VECTOR_KEY = {
	Backpack = "BackpackTile", Pickaxe = "PickaxeTile", Coins = "Coins",
	Strength = "Strength", Level = "Level", XP = "XP",
}

-- Polygon row: { "p", {x1,y1, x2,y2, ...}, topHex, bottomHex, strokeHex, strokeW, transparency }
-- Filled with 1px scanlines (smooth vertical gradient), outlined with rounded rotated bars.
local function drawPoly(root: Frame, s: { any }, k: number, z: number, idx: number)
	local pts = s[2]
	local n = math.floor(#pts / 2)
	local c0, c1 = Color3.fromHex(s[3]), Color3.fromHex(s[4])
	local sw = s[6] or 0
	local tr = s[7] or 0
	local holder = Instance.new("Frame")
	holder.Name = "P" .. idx
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = z
	holder.Active = false
	local ymin, ymax = math.huge, -math.huge
	for j = 1, n do
		local y = pts[2 * j]
		ymin = math.min(ymin, y)
		ymax = math.max(ymax, y)
	end
	local span = math.max(1, ymax - ymin)
	local rowH = if tr > 0 then 1 else 2
	for py = math.floor(ymin * k), math.ceil(ymax * k) - 1 do
		local yc = (py + 0.5) / k
		local xs = {}
		for j = 1, n do
			local j2 = j % n + 1
			local x1, y1 = pts[2 * j - 1], pts[2 * j]
			local x2, y2 = pts[2 * j2 - 1], pts[2 * j2]
			if (y1 <= yc and y2 > yc) or (y2 <= yc and y1 > yc) then
				table.insert(xs, x1 + (yc - y1) / (y2 - y1) * (x2 - x1))
			end
		end
		table.sort(xs)
		local col = c0:Lerp(c1, math.clamp((yc - ymin) / span, 0, 1))
		for m = 1, #xs - 1, 2 do
			local a = math.floor(xs[m] * k + 0.5)
			local b = math.floor(xs[m + 1] * k + 0.5)
			if b > a then
				local f = Instance.new("Frame")
				f.Name = "S"
				f.BorderSizePixel = 0
				f.BackgroundColor3 = col
				f.BackgroundTransparency = tr
				f.Position = UDim2.fromOffset(a, py)
				f.Size = UDim2.fromOffset(b - a, math.min(rowH, math.ceil(ymax * k) - py))
				f.ZIndex = 1
				f.Active = false
				f.Parent = holder
			end
		end
	end
	if sw > 0 then
		local w = math.max(1, sw * k)
		local sc = Color3.fromHex(s[5])
		for j = 1, n do
			local j2 = j % n + 1
			local x1, y1 = pts[2 * j - 1] * k, pts[2 * j] * k
			local x2, y2 = pts[2 * j2 - 1] * k, pts[2 * j2] * k
			local dx, dy = x2 - x1, y2 - y1
			local e = Instance.new("Frame")
			e.Name = "E"
			e.BorderSizePixel = 0
			e.BackgroundColor3 = sc
			e.AnchorPoint = Vector2.new(0.5, 0.5)
			e.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
			e.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + w, w)
			e.Rotation = math.deg(math.atan2(dy, dx))
			e.ZIndex = 2
			e.Active = false
			local ec = Instance.new("UICorner")
			ec.CornerRadius = UDim.new(0.5, 0)
			ec.Parent = e
			e.Parent = holder
		end
	end
	holder.Parent = root
end

function HudModule.DrawIcon(parent: Instance, key: string, size: number, z: number?)
	local spec = ICON_SPECS[key]
	if not spec then
		return nil
	end
	local base = z or 3
	local k = size / 100
	local root = Instance.new("Frame")
	root.Name = "VIcon_" .. key
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(size, size)
	root.ZIndex = base
	root.Active = false
	for i, s in ipairs(spec) do
		if s[1] == "p" then
			drawPoly(root, s, k, base + i, i)
			continue
		end
		local obj
		if s[1] == "x" then
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.GothamBlack
			t.Text = s[14]
			t.TextSize = math.max(6, math.floor(s[5] * k + 0.5))
			t.TextColor3 = Color3.new(1, 1, 1)
			t.TextStrokeTransparency = 1
			obj = t
		else
			local f = Instance.new("Frame")
			f.BackgroundColor3 = Color3.new(1, 1, 1)
			f.BackgroundTransparency = s[13]
			obj = f
		end
		obj.Name = "P" .. i
		obj.BorderSizePixel = 0
		obj.AnchorPoint = Vector2.new(0.5, 0.5)
		obj.Position = UDim2.fromOffset(s[2] * k, s[3] * k)
		obj.Size = UDim2.fromOffset(s[4] * k, s[5] * k)
		obj.Rotation = s[6]
		obj.ZIndex = base + i
		obj.Active = false
		if s[7] > 0 then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, s[7] * math.min(s[4], s[5]) * k)
			c.Parent = obj
		end
		if s[8] ~= s[9] then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(Color3.fromHex(s[8]), Color3.fromHex(s[9]))
			g.Rotation = s[10]
			g.Parent = obj
		elseif s[1] == "x" then
			obj.TextColor3 = Color3.fromHex(s[8])
		else
			obj.BackgroundColor3 = Color3.fromHex(s[8])
		end
		if s[12] > 0 then
			local st = Instance.new("UIStroke")
			st.Color = Color3.fromHex(s[11])
			st.Thickness = math.max(1, s[12] * k)
			st.LineJoinMode = Enum.LineJoinMode.Round
			if s[1] ~= "x" then
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			end
			st.Parent = obj
		end
		obj.Parent = root
	end
	root.Parent = parent
	return root
end

local function makeIcon(parent: Instance, key: string, size: number, pos: UDim2): GuiObject
	local id = HudModule.ICONS[key]
	if id and id ~= "" then
		-- мягкая подложка цвета акцента, чтобы тёмные иконки (рюкзак) читались
		local back = Instance.new("Frame")
		back.Name = "Icon"
		back.Size = UDim2.fromOffset(size, size)
		back.Position = pos
		back.BackgroundColor3 = ACCENT[key]
		back.BackgroundTransparency = 0.78
		back.ZIndex = 3
		back.Parent = parent
		corner(back, 9)
		local img = Instance.new("ImageLabel")
		img.Name = "Image"
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(0.92, 0.92)
		img.Image = id
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 4
		img.Parent = back
		return back
	end
	-- v26: vector picture copied from the reference (no emoji)
	local vkey = VECTOR_KEY[key] or key
	if ICON_SPECS[vkey] then
		local holder = Instance.new("Frame")
		holder.Name = "Icon"
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.fromOffset(size, size)
		holder.Position = pos
		holder.ZIndex = 3
		holder.Parent = parent
		HudModule.DrawIcon(holder, vkey, size, 3)
		return holder
	end
	-- Fallback: эмодзи в цветной плитке
	local tile = Instance.new("Frame")
	tile.Name = "Icon"
	tile.Size = UDim2.fromOffset(size, size)
	tile.Position = pos
	tile.BackgroundColor3 = Color3.new(1, 1, 1)
	tile.ZIndex = 3
	tile.Parent = parent
	corner(tile, 9)
	local g = Instance.new("UIGradient")
	local a = TILE[key] or ACCENT[key]
	g.Color = ColorSequence.new(a:Lerp(Color3.new(1, 1, 1), 0.15), a:Lerp(Color3.new(0, 0, 0), 0.45))
	g.Rotation = 90
	g.Parent = tile
	local tst = Instance.new("UIStroke")
	tst.Color = a:Lerp(Color3.new(1, 1, 1), 0.5)
	tst.Thickness = 2
	tst.Parent = tile
	local tgl = Instance.new("Frame")
	tgl.Name = "Gloss"
	tgl.BackgroundColor3 = Color3.new(1, 1, 1)
	tgl.BackgroundTransparency = 0.75
	tgl.BorderSizePixel = 0
	tgl.Size = UDim2.new(1, -6, 0.42, 0)
	tgl.Position = UDim2.fromOffset(3, 2)
	tgl.ZIndex = 3
	tgl.Parent = tile
	corner(tgl, 7)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = EMOJI[key]
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.new(1, 1, 1)
	t.ZIndex = 4
	t.Parent = tile
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4); pad.PaddingRight = UDim.new(0, 4)
	pad.Parent = t
	return tile
end

local function textLabel(parent: Instance, name: string, size: UDim2, pos: UDim2, font: Enum.Font, color: Color3, maxSize: number, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = font
	l.TextColor3 = color
	l.TextScaled = true
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.ZIndex = 4
	l.Text = ""
	l.TextStrokeTransparency = 0.45
	l.TextStrokeColor3 = Color3.fromRGB(10, 18, 50)
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.MinTextSize = 8
	c.Parent = l
	return l
end

local function makeCard(parent: Instance, key: string, title: string, size: Vector2, order: number, opts: { Bar: boolean?, Sub: boolean?, Compact: boolean? }): Card
	local accent = ACCENT[key]

	-- Слот в UIListLayout (не двигается)
	local holder = Instance.new("Frame")
	holder.Name = key .. "Card"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size.X, size.Y)
	holder.LayoutOrder = order
	holder.Parent = parent

	-- Обёртка: hover-масштаб и въезд (тень + тело двигаются вместе)
	local wrap = Instance.new("Frame")
	wrap.Name = "Wrap"
	wrap.BackgroundTransparency = 1
	wrap.AnchorPoint = Vector2.new(0.5, 0.5)
	wrap.Position = UDim2.fromScale(0.5, 0.5)
	wrap.Size = UDim2.fromScale(1, 1)
	wrap.Parent = holder
	local hoverScale = Instance.new("UIScale")
	hoverScale.Parent = wrap

	-- Тень (отдельный фрейм — у объекта может быть только один UIStroke)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = SHADOW_TRANSPARENCY
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(SHADOW_OFFSET.X, SHADOW_OFFSET.Y)
	shadow.ZIndex = 1
	shadow.Parent = wrap
	corner(shadow, CORNER)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = Color3.new(1, 1, 1)
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 2
	body.ClipsDescendants = false
	body.Parent = wrap
	corner(body, CORNER)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(BG_TOP, BG_BOTTOM)
	grad.Rotation = 90
	grad.Parent = body
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = STROKE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = body
	-- v25: soft outer glow (behind the plate) + glossy top highlight
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.BackgroundColor3 = accent
	glow.BackgroundTransparency = 0.72
	glow.Size = UDim2.new(1, 10, 1, 10)
	glow.Position = UDim2.fromOffset(-5, -5)
	glow.ZIndex = 1
	glow.Parent = wrap
	corner(glow, CORNER + 5)
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.9
	gloss.BorderSizePixel = 0
	gloss.Size = UDim2.new(1, -10, 0.46, 0)
	gloss.Position = UDim2.fromOffset(5, 3)
	gloss.ZIndex = 2
	gloss.Parent = body
	corner(gloss, CORNER - 4)

	-- Вспышка при росте значения
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.5)
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 6
	flash.Parent = body
	corner(flash, CORNER)

	local compact = opts.Compact == true
	local iconSize = compact and 30 or 56 -- v26: big picture like the reference
	local pad = compact and 7 or 8
	local icon = makeIcon(body, key, iconSize, compact and UDim2.fromOffset(pad, 8) or UDim2.new(0, pad, 0.5, -iconSize / 2))
	local textX = pad + iconSize + 8

	local titleLbl = textLabel(body, "Title", UDim2.new(1, -textX - pad, 0, compact and 13 or 18), UDim2.fromOffset(textX, compact and 7 or 9),
		Enum.Font.GothamBold, Color3.new(1, 1, 1), compact and 12 or 15)
	titleLbl.Text = title

	local valueLbl = textLabel(body, "Value", UDim2.new(1, -textX - pad, 0, compact and 24 or 30), UDim2.fromOffset(textX, compact and 20 or 28),
		Enum.Font.GothamBlack, Color3.new(1, 1, 1), compact and 22 or 27)
	local valueScale = Instance.new("UIScale")
	valueScale.Parent = valueLbl

	local sub: TextLabel? = nil
	if opts.Sub then
		sub = textLabel(body, "Sub", UDim2.new(0.5, -pad, 0, 14), UDim2.new(0.5, 0, 0, 8),
			Enum.Font.GothamBlack, Color3.fromRGB(230, 240, 255), 14, Enum.TextXAlignment.Right)
	end

	local fill: Frame? = nil
	local fillGrad: UIGradient? = nil
	if opts.Bar then
		local barBg = Instance.new("Frame")
		barBg.Name = "BarBg"
		barBg.BackgroundColor3 = Color3.fromRGB(8, 14, 44)
		barBg.BorderSizePixel = 0
		barBg.ZIndex = 3
		if compact then
			barBg.Size = UDim2.new(1, -pad * 2, 0, 7)
			barBg.Position = UDim2.new(0, pad, 1, -13)
		else
			barBg.Size = UDim2.new(1, -textX - pad, 0, 9)
			barBg.Position = UDim2.new(0, textX, 1, -16)
		end
		barBg.Parent = body
		corner(barBg, 99)
		local f = Instance.new("Frame")
		f.Name = "Fill"
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BorderSizePixel = 0
		f.Size = UDim2.fromScale(0, 1)
		f.ZIndex = 4
		f.Parent = barBg
		corner(f, 99)
		local fg = Instance.new("UIGradient")
		fg.Color = barSequence(0)
		fg.Parent = f
		fill, fillGrad = f, fg
	end

	-- Прозрачная кнопка поверх: hover и клик
	local btn = Instance.new("TextButton")
	btn.Name = "Hit"
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Size = UDim2.fromScale(1, 1)
	btn.ZIndex = 8
	btn.AutoButtonColor = false
	btn.Parent = body
	btn.MouseEnter:Connect(function()
		tween(hoverScale, 0.15, { Scale = 1.05 })
		tween(stroke, 0.15, { Thickness = STROKE + 1 })
	end)
	btn.MouseLeave:Connect(function()
		tween(hoverScale, 0.18, { Scale = 1 })
		tween(stroke, 0.18, { Thickness = STROKE })
	end)

	return {
		Key = key, Holder = holder, Wrap = wrap, Body = body, Stroke = stroke,
		Title = titleLbl, Value = valueLbl, ValueScale = valueScale, Sub = sub,
		Fill = fill, FillGradient = fillGrad, Flash = flash, Icon = icon, Button = btn,
		HomePos = wrap.Position,
	}
end

-- v25: round "+" button on the right side of a plate (like the reference)
local function addPlus(card: Card, c0: Color3, c1: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = "PlusBtn"
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Size = UDim2.fromOffset(38, 38)
	b.Position = UDim2.new(1, -9, 0.5, 0)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = false
	b.Font = Enum.Font.GothamBlack
	b.Text = "" -- v26: drawn chunky plus (PlusBar frames below)
	b.TextSize = 30
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 0.35
	b.TextStrokeColor3 = c1:Lerp(Color3.new(0, 0, 0), 0.5)
	b.ZIndex = 9
	b.Parent = card.Body
	corner(b, 99)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c0, c1)
	g.Rotation = 90
	g.Parent = b
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(1, 1, 1)
	st.Thickness = 2.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b
	-- v26: chunky white plus made of two rounded bars with a dark outline (like the reference)
	for pass = 1, 2 do
		for i = 1, 2 do
			local bar = Instance.new("Frame")
			bar.Name = "PlusBar"
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = (i == 1) and UDim2.fromOffset(20, 7) or UDim2.fromOffset(7, 20)
			bar.BackgroundColor3 = Color3.new(1, 1, 1)
			bar.BorderSizePixel = 0
			bar.ZIndex = 9 + pass
			bar.Active = false
			bar.Parent = b
			corner(bar, 3)
			if pass == 1 then
				local bst = Instance.new("UIStroke")
				bst.Color = c1:Lerp(Color3.new(0, 0, 0), 0.55)
				bst.Thickness = 2
				bst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				bst.Parent = bar
			end
		end
	end
	local sc = Instance.new("UIScale")
	sc.Parent = b
	b.MouseEnter:Connect(function() tween(sc, 0.12, { Scale = 1.12 }) end)
	b.MouseLeave:Connect(function() tween(sc, 0.12, { Scale = 1 }) end)
	b.MouseButton1Down:Connect(function() sc.Scale = 0.9 end)
	b.MouseButton1Up:Connect(function() sc.Scale = 1.12 end)
	return b
end

local function bounce(card: Card)
	local sc = card.ValueScale
	tween(sc, 0.09, { Scale = 1.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Connect(function()
		tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end

local function flash(card: Card, strength: number?)
	card.Flash.BackgroundTransparency = 1 - (strength or 0.45)
	tween(card.Flash, 0.45, { BackgroundTransparency = 1 })
	tween(card.Stroke, 0.08, { Thickness = STROKE + 2 }).Completed:Connect(function()
		tween(card.Stroke, 0.3, { Thickness = STROKE })
	end)
end

local function setBar(card: Card, ratio: number)
	local fill, grad = card.Fill, card.FillGradient
	if not fill or not grad then return end
	ratio = math.clamp(ratio, 0, 1)
	grad.Color = barSequence(ratio)
	tween(fill, 0.35, { Size = UDim2.fromScale(ratio, 1) })
end

-- ============================================================================
-- КОНСТРУКТОР
-- ============================================================================
function HudModule.new(screenGui: ScreenGui, callbacks: { OnBackpackClick: (() -> ())? }?)
	local self = setmetatable({}, HudModule)
	local cb = callbacks or {}
	self._prev = {}
	self._first = true
	self._scales = {}

	-- Верхний ряд
	local top = Instance.new("Frame")
	top.Name = "TopPlates"
	top.BackgroundTransparency = 1
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, TOP_Y)
	top.Size = UDim2.fromOffset(TOP_CARD_SIZE.X * 2 + TOP_GAP, TOP_CARD_SIZE.Y)   -- v14: монеты вынесены вправо
	top.Parent = screenGui
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.Padding = UDim.new(0, TOP_GAP)
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Parent = top
	self.TopRow = top

	-- Левая колонка
	local left = Instance.new("Frame")
	left.Name = "LeftColumn"
	left.BackgroundTransparency = 1
	left.Position = LEFT_POS
	left.Size = UDim2.fromOffset(LEFT_CARD_SIZE.X, 600)
	left.Parent = screenGui
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Vertical
	ll.Padding = UDim.new(0, LEFT_GAP)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = left
	self.LeftColumn = left

	-- v14: пилюля монет в правом верхнем углу (как на референсе)
	local topRight = Instance.new("Frame")
	topRight.Name = "TopRightCoins"
	topRight.BackgroundTransparency = 1
	topRight.AnchorPoint = Vector2.new(1, 0)
	topRight.Position = UDim2.new(1, -14, 0, TOP_Y)
	topRight.Size = UDim2.fromOffset(236, TOP_CARD_SIZE.Y)
	topRight.Parent = screenGui
	local trl = Instance.new("UIListLayout")
	trl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	trl.Parent = topRight
	self.TopRight = topRight

	for _, root in ipairs({ top, left, topRight }) do
		local sc = Instance.new("UIScale")
		sc.Scale = getViewportScale()
		sc.Parent = root
		table.insert(self._scales, sc)
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local s = getViewportScale()
			for _, sc in ipairs(self._scales) do sc.Scale = s end
		end)
	end

	-- v25: top plates in the same style as "Jackpot / Rebirths" on the reference
	self.Cards = {
		Backpack = makeCard(top, "Backpack", "Backpack", TOP_CARD_SIZE, 1, { Bar = true }),
		Pickaxe  = makeCard(top, "Pickaxe", "Pickaxe", TOP_CARD_SIZE, 2, {}),
		Coins    = makeCard(topRight, "Coins", "Coins", Vector2.new(236, TOP_CARD_SIZE.Y), 3, {}),
		Strength = makeCard(left, "Strength", "Strength", LEFT_CARD_SIZE, 1, { Bar = true, Sub = true }),
		Level    = makeCard(left, "Level", "Level", LEFT_CARD_SIZE, 2, { Bar = true, Sub = true }),
		XP       = makeCard(left, "XP", "XP", LEFT_CARD_SIZE, 3, { Bar = true, Sub = true }),
	}

	-- Звёзды кирки (RichText)
	local pick = self.Cards.Pickaxe
	local stars = textLabel(pick.Body, "Stars", UDim2.new(1, -10, 0, 14), UDim2.new(0, 5, 1, -19),
		Enum.Font.GothamBlack, Color3.fromRGB(255, 215, 70), 11, Enum.TextXAlignment.Center)
	stars.RichText = true
	self.Stars = stars
	local starsScale = Instance.new("UIScale")
	starsScale.Parent = stars
	self.StarsScale = starsScale

	-- Монеты: значение на всю ширину снизу (числа бывают длинными)
	local coins = self.Cards.Coins
	coins.Value.Size = UDim2.new(1, -128, 0, 30)
	coins.Value.TextXAlignment = Enum.TextXAlignment.Center -- v26: centred like the reference
	coins.Value.TextColor3 = Color3.new(1, 1, 1)
	stars.Visible = false -- v25: "Level N" only, like the reference
	pick.Value.Size = UDim2.new(1, -80, 0, 30)
	-- v26: only the Backpack title is cyan (Pickaxe / Coins titles are white on the reference)
	self.Cards.Backpack.Title.TextColor3 = Color3.fromRGB(150, 225, 255)
	-- v26: plate bodies like the reference: Strength = dark amber, XP = dark violet, the rest navy
	local function bodyGrad(k, c0, c1)
		local g = self.Cards[k].Body:FindFirstChildOfClass("UIGradient")
		if g then g.Color = ColorSequence.new(c0, c1) end
	end
	bodyGrad("Strength", Color3.fromRGB(100, 62, 32), Color3.fromRGB(58, 34, 16))
	bodyGrad("XP", Color3.fromRGB(54, 46, 126), Color3.fromRGB(26, 22, 72))
	-- v26: no progress bars on the plates (the reference shows only numbers)
	for _, card in pairs(self.Cards) do
		local bb = card.Body:FindFirstChild("BarBg")
		if bb and bb:IsA("GuiObject") then bb.Visible = false end
	end
	-- round "+" buttons (Coins -> shop, Strength -> skills, Level -> prestige; wired in ClientController / ProgressionUI)
	self.Plus = {
		Coins = addPlus(coins, Color3.fromRGB(26, 38, 80), Color3.fromRGB(8, 14, 36)),
		Strength = addPlus(self.Cards.Strength, Color3.fromRGB(255, 200, 70), Color3.fromRGB(240, 120, 18)),
		Level = addPlus(self.Cards.Level, Color3.fromRGB(94, 200, 255), Color3.fromRGB(31, 111, 224)),
	}
	do -- v26: the coins "+" is dark with a thin dark rim (like the reference)
		local cs = self.Plus.Coins:FindFirstChildOfClass("UIStroke")
		if cs then
			cs.Color = Color3.fromRGB(8, 12, 30)
			cs.Thickness = 2
		end
	end
	for _, k in ipairs({ "Strength", "Level" }) do
		local sub = self.Cards[k].Sub
		if sub then
			sub.Size = UDim2.new(0.5, -58, 0, 16)
			sub.Position = UDim2.new(0.5, 0, 0, 10)
		end
		local vl = self.Cards[k].Value
		vl.Size = UDim2.new(1, -128, 0, 30)
	end
	do -- v26: XP "/ 100" sits on the value row at the right (like "/100" on the reference)
		local xs = self.Cards.XP.Sub
		if xs then
			xs.Size = UDim2.new(0.5, -12, 0, 22)
			xs.Position = UDim2.new(0.5, 0, 0, 32)
		end
	end

	-- Отслеживаемое число монет для счётчика
	self._coinValue = Instance.new("NumberValue")
	self._coinValue.Changed:Connect(function(v)
		coins.Value.Text = HudModule.FormatNumber(v)
	end)

	if cb.OnBackpackClick then
		self.Cards.Backpack.Button.MouseButton1Click:Connect(cb.OnBackpackClick)
	end

	self:_playEntrance()
	return self
end

function HudModule:_playEntrance()
	local function run(card: Card, fromOffset: UDim2, delay: number)
		local list = captureFade(card.Wrap)
		hideForFade(list)
		card.Wrap.Position = card.HomePos + fromOffset
		task.delay(delay, function()
			tween(card.Wrap, 0.55, { Position = card.HomePos }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			playFade(list, 0.45)
		end)
	end
	run(self.Cards.Backpack, UDim2.fromOffset(0, -110), 0.15)
	run(self.Cards.Pickaxe, UDim2.fromOffset(0, -110), 0.25)
	run(self.Cards.Coins, UDim2.fromOffset(0, -110), 0.35)
	run(self.Cards.Strength, UDim2.fromOffset(-260, 0), 0.30)
	run(self.Cards.Level, UDim2.fromOffset(-260, 0), 0.40)
	run(self.Cards.XP, UDim2.fromOffset(-260, 0), 0.50)
end

-- Всплывающий "+N" над монетами
function HudModule:_floatText(card: Card, text: string, color: Color3)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 20)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 1, 4)
	l.Font = Enum.Font.GothamBlack
	l.TextSize = 18
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.4
	l.Text = text
	l.ZIndex = 9
	l.Parent = card.Body
	tween(l, 0.9, { Position = UDim2.new(0.5, 0, 1, 26), TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(0.95, function() l:Destroy() end)
end

local function starsText(filled: number): string
	local s = '<font color="#FFD54A">' .. string.rep("★", filled) .. "</font>"
	if filled < MAX_PICKAXE_STARS then
		s ..= '<font color="#4A4C5E">' .. string.rep("★", MAX_PICKAXE_STARS - filled) .. "</font>"
	end
	return s
end

-- ============================================================================
-- ОБНОВЛЕНИЕ
-- ============================================================================
function HudModule:Update(state)
	local prev = self._prev
	local first = self._first
	local C = self.Cards

	-- 🎒 Рюкзак
	local used, max = state.BagUsed or 0, math.max(1, state.BagMax or 1)
	local bRatio = math.clamp(used / max, 0, 1)
	C.Backpack.Value.Text = string.format("%d/%d", used, max)
	setBar(C.Backpack, bRatio)
	local full = used >= max
	C.Backpack.Value.TextColor3 = full and BAR_RED or Color3.new(1, 1, 1)
	C.Backpack.Title.Text = full and "FULL!" or "Backpack"
	C.Backpack.Title.TextColor3 = full and BAR_RED or Color3.fromRGB(150, 225, 255)
	if not first and used ~= prev.BagUsed then bounce(C.Backpack) end
	if full and not self._bagPulse then
		self._bagPulse = TweenService:Create(C.Backpack.Stroke, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = BAR_RED })
		self._bagPulse:Play()
	elseif not full and self._bagPulse then
		self._bagPulse:Cancel()
		self._bagPulse = nil
		C.Backpack.Stroke.Color = ACCENT.Backpack
	end

	-- ⛏️ Кирка
	local tier = state.PickaxeTier or 1
	local pickLevel = math.clamp(tier, 1, 10)
	C.Pickaxe.Value.Text = "Level " .. pickLevel
	self.Stars.Text = starsText(math.clamp(pickLevel, 0, MAX_PICKAXE_STARS))
	if not first and tier ~= prev.PickaxeTier then
		bounce(C.Pickaxe)
		flash(C.Pickaxe)
		self.StarsScale.Scale = 1.35
		tween(self.StarsScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	-- 💰 Монеты (плавный счётчик)
	local coins = state.Coins or 0
	if first then
		self._coinValue.Value = coins
		C.Coins.Value.Text = HudModule.FormatNumber(coins)
	elseif coins ~= prev.Coins then
		tween(self._coinValue, 0.6, { Value = coins })
		bounce(C.Coins)
		local diff = coins - (prev.Coins or 0)
		if diff > 0 then
			flash(C.Coins, 0.35)
			self:_floatText(C.Coins, "+" .. HudModule.FormatNumber(diff), Color3.fromRGB(255, 225, 90))
		else
			self:_floatText(C.Coins, "-" .. HudModule.FormatNumber(-diff), Color3.fromRGB(255, 110, 110))
		end
	end

	-- 💪 Сила
	local str = state.Strength or 1
	C.Strength.Value.Text = HudModule.FormatNumber(str)
	C.Strength.Sub.Text = string.format("%d/%d", state.StrengthXP or 0, state.RequiredStrengthXP or 1)
	setBar(C.Strength, (state.StrengthXP or 0) / math.max(1, state.RequiredStrengthXP or 1))
	if not first and str > (prev.Strength or str) then
		bounce(C.Strength)
		flash(C.Strength)
		SoundManager.PlayUISound("StatUp")
	end

	-- ⭐ Уровень (полоса — путь до престижа)
	local lvl = state.Level or 1
	local need = ProgressionConfig.PRESTIGE_REQUIRED_LEVEL or 50
	C.Level.Value.Text = tostring(lvl)
	local prestige = state.Prestige or 0
	C.Level.Sub.Text = (prestige > 0 and ("P" .. prestige .. " · ") or "") .. string.format("to %d", need)
	setBar(C.Level, lvl / need)
	if not first and lvl > (prev.Level or lvl) then
		bounce(C.Level)
		flash(C.Level, 0.6) -- звук: фанфара уровня из ProgressionUI
	end

	-- ✨ Опыт
	local xp, req = state.XP or 0, math.max(1, state.RequiredXP or 1)
	C.XP.Value.Text = HudModule.FormatNumber(xp)
	C.XP.Sub.Text = "/ " .. HudModule.FormatNumber(req)
	setBar(C.XP, xp / req)
	if not first and xp > (prev.XP or xp) then
		bounce(C.XP)
		flash(C.XP, 0.2)
	end

	prev.BagUsed, prev.PickaxeTier, prev.Coins = used, tier, coins
	prev.Strength, prev.Level, prev.XP = str, lvl, xp
	self._first = false
end

return HudModule
