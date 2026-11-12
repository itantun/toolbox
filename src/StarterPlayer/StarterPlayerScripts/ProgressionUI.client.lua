--!strict
-- ============================================================================
-- 🌟 КЛИЕНТ: ProgressionUI (StarterPlayerScripts.ProgressionUI)
-- ЗАДАЧА 1 — Интерфейс прокачки в стиле топ-симуляторов 2026:
-- • Кнопки слева: ⚡ Навыки [K] · 🏆 Достижения [J] · 👑 Престиж [P]
-- • Окно навыков: иконки-плитки (скруглённые квадраты с градиентом), прогресс-бары,
--   кнопки «Улучшить» и «MAX»
-- • Окно достижений с прогрессом и наградами, окно престижа с превью ауры
-- • Попап «🎉 Уровень повышен! [X]» с фанфарами и UI-искрами, тосты достижений
-- • Подсветка при наведении (UIStroke) и анимация нажатия (Scale 1.0 → 0.95 → 1.0)
-- ============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then return end
if player:GetAttribute("ProgressionUIActive") then return end
player:SetAttribute("ProgressionUIActive", true)
player:SetAttribute("ProgressionUIOpen", false)

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ProgressionConfig = require(Modules:WaitForChild("ProgressionConfig"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
-- v26: vector icons shared with the HUD (same pictures as the reference)
local HudModule: any = nil
do
	local okHud, modHud = pcall(function()
		return require(Modules:WaitForChild("HudModule"))
	end)
	if okHud then
		HudModule = modHud
	end
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData") :: RemoteEvent
local UpgradeSkillRemote = Remotes:WaitForChild("UpgradeSkill") :: RemoteEvent
local PrestigeRemote = Remotes:WaitForChild("Prestige") :: RemoteEvent
local ProgressionEvent = Remotes:WaitForChild("ProgressionEvent") :: RemoteEvent

-- ============================================================================
-- 0. СОСТОЯНИЕ (приходит с сервера)
-- ============================================================================
local State = {
	Level = 1,
	XP = 0,
	RequiredXP = 100,
	Coins = 0,
	SkillPoints = 0,
	Skills = {} :: { [string]: number },
	Prestige = 0,
	Achievements = {} :: { [string]: boolean },
	AchievementProgress = {} :: { [string]: number },
	CanPrestige = false,
}

-- ============================================================================
-- 1. ПАЛИТРА И ЗВУКИ
-- ============================================================================
local C = {
	Bg = Color3.fromRGB(20, 20, 30),
	BgLight = Color3.fromRGB(52, 54, 78),
	Row = Color3.fromRGB(34, 36, 52),
	White = Color3.new(1, 1, 1),
	Muted = Color3.fromRGB(190, 200, 225),
	Gold = Color3.fromRGB(255, 210, 60),
	GoldDark = Color3.fromRGB(190, 110, 10),
	Green = Color3.fromRGB(70, 230, 110),
	GreenDark = Color3.fromRGB(20, 130, 60),
	Blue = Color3.fromRGB(60, 190, 255),
	BlueDark = Color3.fromRGB(25, 85, 190),
	Purple = Color3.fromRGB(175, 95, 255),
	PurpleDark = Color3.fromRGB(80, 30, 170),
	Pink = Color3.fromRGB(255, 95, 185),
	PinkDark = Color3.fromRGB(150, 25, 110),
	Red = Color3.fromRGB(245, 70, 80),
	Gray = Color3.fromRGB(110, 115, 135),
	GrayDark = Color3.fromRGB(55, 58, 72),
}

local FONT = Enum.Font.GothamBold

local function makeSound(cfg: { Id: string, Volume: number }): Sound
	local s = Instance.new("Sound")
	s.SoundId = cfg.Id
	s.Volume = cfg.Volume
	s.Parent = SoundService
	return s
end

local Sounds = {
	LevelUp = makeSound(ProgressionConfig.SOUNDS.LevelUp),
	Click = makeSound(ProgressionConfig.SOUNDS.Click),
	Achievement = makeSound(ProgressionConfig.SOUNDS.Achievement),
	Prestige = makeSound(ProgressionConfig.SOUNDS.Prestige),
}

local function playSound(s: Sound, pitch: number?)
	s.PlaybackSpeed = pitch or 1
	s.TimePosition = 0
	s:Play()
end

-- v47: приятный звук нового уровня
local function playLevelUpSound()
	local S = ProgressionConfig.SOUNDS :: any
	local custom = S.LevelUpCustom
	if custom and type(custom.Id) == "string" and custom.Id ~= "" then
		local s = makeSound(custom)
		s:Play()
		task.delay(8, function() s:Destroy() end)
		return
	end
	local chime = S.LevelUpChime
	-- до-ми-соль-до: мажорное арпеджио с лёгким эхо
	local notes = { 1.0, 1.26, 1.5, 2.0 }
	for i, pitch in ipairs(notes) do
		task.delay((i - 1) * 0.11, function()
			local s = Instance.new("Sound")
			s.SoundId = chime.Id
			s.Volume = chime.Volume * ((i == #notes) and 1.15 or 1)
			s.PlaybackSpeed = pitch
			local rv = Instance.new("ReverbSoundEffect")
			rv.DecayTime = 1.2
			rv.WetLevel = -8
			rv.DryLevel = 0
			rv.Parent = s
			local eq = Instance.new("EqualizerSoundEffect")
			eq.HighGain = -6
			eq.MidGain = 0
			eq.LowGain = 0
			eq.Parent = s
			s.Parent = SoundService
			s:Play()
			task.delay(4, function() s:Destroy() end)
		end)
	end
end

local function formatNumber(n: number): string
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e4 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

-- ============================================================================
-- 2. UI-КОНСТРУКТОР (UICorner + UIGradient + UIStroke)
-- ============================================================================
local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("ProgressionHUD")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ProgressionHUD"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 5
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local function corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function gradient(parent: Instance, c0: Color3, c1: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c0, c1)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3, textSize: number, alignX: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color
	l.TextSize = textSize
	l.TextXAlignment = alignX or Enum.TextXAlignment.Left
	l.TextStrokeTransparency = 0.5
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function panel(parent: Instance, name: string, size: UDim2, pos: UDim2, accent: Color3, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = C.White
	f.BackgroundTransparency = math.min(transparency or 0.3, 0.06)
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 14)
	-- v32: modern dark-glass panel + neon accent rim + soft gloss
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 42, 88):Lerp(accent, 0.08)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(26, 24, 54)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 13, 32)),
	})
	g.Rotation = 90
	g.Parent = f
	local os_ = stroke(f, accent, 3)
	os_.Transparency = 0.15
	local glossTop = Instance.new("Frame")
	glossTop.Name = "PanelGloss"
	glossTop.BackgroundColor3 = C.White
	glossTop.BackgroundTransparency = 0.94
	glossTop.BorderSizePixel = 0
	glossTop.Size = UDim2.new(1, -12, 0, 54)
	glossTop.Position = UDim2.fromOffset(6, 4)
	glossTop.Parent = f
	corner(glossTop, 12)
	local rim = Instance.new("Frame")
	rim.Name = "GoldRim"
	rim.BackgroundTransparency = 1
	rim.Size = UDim2.new(1, 12, 1, 12)
	rim.Position = UDim2.fromOffset(-6, -6)
	rim.Parent = f
	corner(rim, 20)
	local rs = stroke(rim, accent, 5)
	rs.Transparency = 0.72
	return f
end

-- Скруглённая «плитка» иконки как на картинке: градиент + глянцевый блик + эмодзи
local function iconTile(parent: Instance, icon: string, c0: Color3, c1: Color3, size: number, pos: UDim2): (Frame, TextLabel, UIGradient)
	local tile = Instance.new("Frame")
	tile.Name = "IconTile"
	tile.Size = UDim2.new(0, size, 0, size)
	tile.Position = pos
	tile.BackgroundColor3 = C.White
	tile.BorderSizePixel = 0
	tile.Parent = parent
	corner(tile, math.floor(size * 0.22))
	local g = gradient(tile, c0, c1, 45)
	stroke(tile, c0:Lerp(C.White, 0.45), 2)

	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.new(1, -8, 0.45, 0)
	gloss.Position = UDim2.new(0, 4, 0, 3)
	gloss.BackgroundColor3 = C.White
	gloss.BackgroundTransparency = 0.82
	gloss.BorderSizePixel = 0
	gloss.Parent = tile
	corner(gloss, math.floor(size * 0.18))

	local e = label(tile, icon, UDim2.new(0.72, 0, 0.72, 0), UDim2.new(0.14, 0, 0.14, 0), C.White, 24, Enum.TextXAlignment.Center)
	e.TextScaled = true
	e.TextStrokeTransparency = 1
	e.ZIndex = 2
	return tile, e, g
end

local function progressBar(parent: Instance, size: UDim2, pos: UDim2, c0: Color3, c1: Color3): (Frame, Frame, TextLabel)
	local bg = Instance.new("Frame")
	bg.Name = "Bar"
	bg.Size = size
	bg.Position = pos
	bg.BackgroundColor3 = Color3.fromRGB(8, 8, 20)
	bg.BackgroundTransparency = 0.05
	bg.BorderSizePixel = 0
	bg.Parent = parent
	corner(bg, 99)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = C.White
	fill.BorderSizePixel = 0
	fill.Parent = bg
	corner(fill, 99)
	gradient(fill, c0:Lerp(C.White, 0.1), c1, 0)
	local bst = stroke(bg, C.White, 1)
	bst.Transparency = 0.85
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = C.White
	shine.BackgroundTransparency = 0.7
	shine.BorderSizePixel = 0
	shine.Size = UDim2.new(1, -6, 0.38, 0)
	shine.Position = UDim2.fromOffset(3, 1)
	shine.Parent = fill
	corner(shine, 99)

	local txt = label(bg, "", UDim2.new(1, 0, 1, 0), UDim2.new(), C.White, 11, Enum.TextXAlignment.Center)
	txt.ZIndex = 3
	return bg, fill, txt
end

local function setBar(fill: Frame, ratio: number)
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0),
	}):Play()
end

-- Подсветка при наведении + анимация нажатия (1.0 → 0.95 → 1.0) + тихий клик
local function addButtonFx(btn: GuiButton, onClick: () -> ())
	local sc = Instance.new("UIScale")
	sc.Parent = btn
	local st = btn:FindFirstChildOfClass("UIStroke")
	local baseColor = st and st.Color or C.White
	local hovered = false
	local fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	btn.MouseEnter:Connect(function()
		hovered = true
		TweenService:Create(sc, fast, { Scale = 1.04 }):Play()
		if st then TweenService:Create(st, fast, { Color = C.White, Thickness = 3 }):Play() end
	end)
	btn.MouseLeave:Connect(function()
		hovered = false
		TweenService:Create(sc, fast, { Scale = 1 }):Play()
		if st then TweenService:Create(st, fast, { Color = baseColor, Thickness = 2 }):Play() end
	end)
	btn.Activated:Connect(function()
		playSound(Sounds.Click, 1.1)
		sc.Scale = 0.95
		TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = hovered and 1.04 or 1,
		}):Play()
		onClick()
	end)
end

local function button(parent: Instance, text: string, size: UDim2, pos: UDim2, c0: Color3, c1: Color3, textSize: number?, onClick: () -> ()): (TextButton, UIGradient)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.AnchorPoint = Vector2.new(0, 0)
	b.BackgroundColor3 = C.White
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Font = FONT
	b.Text = text
	b.TextColor3 = C.White
	b.TextSize = textSize or 16
	b.TextStrokeTransparency = 0.5
	b.Parent = parent
	corner(b, 10)
	local g = gradient(b, c0, c1, 90) -- акцент → тёмный
	stroke(b, c0:Lerp(C.White, 0.3), 2)
	addButtonFx(b, onClick)
	return b, g
end

-- ============================================================================
-- 3. АДАПТИВНЫЙ МАСШТАБ (ПК / планшет / телефон)
-- ============================================================================
local ResponsiveScales: { UIScale } = {}
local function getViewportScale(): number
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 760)
	return math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.55, 1.15)
end
local function responsive(obj: GuiObject): UIScale
	local sc = Instance.new("UIScale")
	sc.Scale = getViewportScale()
	sc.Parent = obj
	table.insert(ResponsiveScales, sc)
	return sc
end
local function refreshScales()
	local s = getViewportScale()
	for _, sc in ipairs(ResponsiveScales) do
		sc.Scale = s
	end
end
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales)
end

-- ============================================================================
-- 4. ОКНА (одно открытое за раз)
-- ============================================================================
type Window = { Frame: Frame, Scale: UIScale, Body: Frame, Title: TextLabel }
local Windows: { [string]: Window } = {}
local OpenWindowName: string? = nil
local refreshAll: () -> () = function() end

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

local function closeWindow()
	if not OpenWindowName then return end
	local w = Windows[OpenWindowName]
	OpenWindowName = nil
	player:SetAttribute("ProgressionUIOpen", false)
	if w then
		local target = getViewportScale()
		local t = TweenService:Create(w.Scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = target * 0.85 })
		t:Play()
		t.Completed:Once(function()
			if OpenWindowName == nil or Windows[OpenWindowName] ~= w then
				w.Frame.Visible = false
			end
			w.Scale.Scale = getViewportScale()
		end)
	end
end

local function openWindow(name: string)
	if OpenWindowName == name then
		closeWindow()
		return
	end
	if OpenWindowName then
		local prev = Windows[OpenWindowName]
		if prev then prev.Frame.Visible = false end
	end
	local w = Windows[name]
	if not w then return end
	OpenWindowName = name
	player:SetAttribute("ProgressionUIOpen", true)
	refreshAll()
	local target = getViewportScale()
	w.Scale.Scale = target * 0.8
	w.Frame.Visible = true
	TweenService:Create(w.Scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
end

local function createWindow(name: string, title: string, accent: Color3, width: number, height: number): Window
	local f = panel(screenGui, name, UDim2.new(0, width, 0, height), UDim2.new(0.5, 0, 0.5, 0), accent, 0.3)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Visible = false
	f.ZIndex = 10
	local sc = responsive(f)

	local titleLbl = label(f, title, UDim2.new(1, -200, 0, 34), UDim2.new(0, 20, 0, 12), accent, 22)
	-- v24: wooden title plaque like the reference board
	local plaque = Instance.new("Frame")
	plaque.Name = "TitlePlaque"
	plaque.Size = UDim2.new(0, math.min(width - 220, 300), 0, 42)
	plaque.Position = UDim2.new(0, 12, 0, 8)
	plaque.BackgroundColor3 = C.White
	plaque.BorderSizePixel = 0
	plaque.Parent = f
	corner(plaque, 10)
	gradient(plaque, accent:Lerp(C.White, 0.12), accent:Lerp(Color3.new(0, 0, 0), 0.5), 90)
	stroke(plaque, accent:Lerp(C.White, 0.5), 2)
	local pgl = Instance.new("Frame")
	pgl.BackgroundColor3 = C.White; pgl.BackgroundTransparency = 0.82; pgl.BorderSizePixel = 0
	pgl.Size = UDim2.new(1, -10, 0.42, 0); pgl.Position = UDim2.fromOffset(5, 3); pgl.Parent = plaque
	corner(pgl, 8)
	titleLbl.Parent = plaque
	titleLbl.Size = UDim2.new(1, -16, 1, -6)
	titleLbl.Position = UDim2.fromOffset(8, 3)
	titleLbl.TextColor3 = C.White
	titleLbl.TextStrokeTransparency = 0
	titleLbl.TextStrokeColor3 = Color3.fromRGB(14, 10, 30)
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.ZIndex = 2
	titleLbl.TextXAlignment = Enum.TextXAlignment.Center
	titleLbl.TextYAlignment = Enum.TextYAlignment.Center
	titleLbl.TextWrapped = false
	titleLbl.TextScaled = true
	local tsc = Instance.new("UITextSizeConstraint")
	tsc.MaxTextSize = 22
	tsc.Parent = titleLbl

	local xBtn = button(f, "✖", UDim2.new(0, 38, 0, 38), UDim2.new(1, -50, 0, 10), C.Red, Color3.fromRGB(120, 20, 30), 18, function()
		closeWindow()
	end)
	vecCross(xBtn)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -32, 1, -64)
	body.Position = UDim2.new(0, 16, 0, 56)
	body.Parent = f

	local w: Window = { Frame = f, Scale = sc, Body = body, Title = titleLbl }
	Windows[name] = w
	return w
end

local function scrollList(parent: Instance, size: UDim2, pos: UDim2): ScrollingFrame
	local sf = Instance.new("ScrollingFrame")
	sf.Size = size
	sf.Position = pos
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.ScrollBarThickness = 6
	sf.ScrollBarImageColor3 = C.Muted
	sf.CanvasSize = UDim2.new()
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = sf
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = sf
	return sf
end

local function rowFrame(parent: Instance, name: string, height: number, accent: Color3, order: number): Frame
	local r = Instance.new("Frame")
	r.Name = name
	r.LayoutOrder = order
	r.Size = UDim2.new(1, 0, 0, height)
	r.BackgroundColor3 = C.White
	r.BackgroundTransparency = 0.2
	r.BorderSizePixel = 0
	r.Parent = parent
	corner(r, 12)
	gradient(r, Color3.fromRGB(52, 48, 96):Lerp(accent, 0.12), Color3.fromRGB(26, 24, 54), 90) -- v32: modern glass row
	local rst = stroke(r, accent, 1.5)
	rst.Transparency = 0.45
	local strip = Instance.new("Frame")
	strip.Name = "AccentStrip"
	strip.BackgroundColor3 = accent
	strip.BorderSizePixel = 0
	strip.Size = UDim2.new(0, 4, 1, -20)
	strip.Position = UDim2.fromOffset(2, 10)
	strip.Parent = r
	corner(strip, 4)
	local rgl = Instance.new("Frame")
	rgl.Name = "RowGloss"
	rgl.BackgroundColor3 = C.White; rgl.BackgroundTransparency = 0.95; rgl.BorderSizePixel = 0
	rgl.Size = UDim2.new(1, -8, 0.45, 0); rgl.Position = UDim2.fromOffset(4, 2); rgl.Parent = r
	corner(rgl, 10)
	return r
end

-- ============================================================================
-- v33: SKILLS & ACHIEVEMENTS — exactly like the reference:
-- wooden frame + wooden title plaque with a vector icon, red close button,
-- glossy purple rows, big gradient icon tiles with vector pictures,
-- colored names, "Lv. x / 50", thick progress bars, green Upgrade / blue MAX,
-- "Reward:" + coins + stars, big % on the right, green check when done.
-- ============================================================================
local REF = {
	PanelTop = Color3.fromRGB(70, 54, 98), PanelBot = Color3.fromRGB(36, 28, 56),
	Wood = Color3.fromRGB(164, 100, 48), WoodDark = Color3.fromRGB(78, 44, 20), WoodLight = Color3.fromRGB(226, 160, 84),
	RowTop = Color3.fromRGB(88, 76, 126), RowBot = Color3.fromRGB(46, 38, 74),
	Cream = Color3.fromRGB(255, 238, 205), Lav = Color3.fromRGB(205, 212, 255),
	Track = Color3.fromRGB(20, 16, 34), RewardGold = Color3.fromRGB(255, 205, 70),
	Green0 = Color3.fromRGB(110, 230, 90), Green1 = Color3.fromRGB(24, 140, 44), GreenRim = Color3.fromRGB(200, 255, 170),
	Max0 = Color3.fromRGB(126, 146, 220), Max1 = Color3.fromRGB(60, 70, 150), MaxRim = Color3.fromRGB(196, 210, 255),
	Blue0 = Color3.fromRGB(96, 186, 255), Blue1 = Color3.fromRGB(28, 88, 214), BlueRim = Color3.fromRGB(176, 224, 255),
	GoldT0 = Color3.fromRGB(255, 216, 72), GoldT1 = Color3.fromRGB(238, 136, 20), GoldRim = Color3.fromRGB(255, 242, 170),
	AchBorder = Color3.fromRGB(132, 122, 206),
}

-- Vector icons (100 x 100 design box):
-- { kind "r" frame / "x" text, x, y, w, h, rotation, radius, c0, c1, gradRot, strokeColor, strokeW, transparency, text }
local ICONS = {
	Bolt = {
		{ "p", { 52, 4, 78, 4, 60, 40, 80, 40, 32, 96, 42, 56, 20, 56 }, "#fff27a", "#ff9e12", "#8a4206", 5, 0 },
		{ "p", { 55, 10, 66, 10, 48, 46, 37, 46 }, "#ffffff", "#ffffff", "#000000", 0, 0.45 },
	},
	Muscle = {
		{ "r", 44, 72, 60, 28, 0, 0.5, "#ffd98e", "#f2a23a", 90, "#8a4a10", 4, 0, "" },
		{ "r", 40, 58, 42, 34, 0, 0.5, "#ffe2a4", "#f5ac44", 90, "#8a4a10", 4, 0, "" },
		{ "r", 68, 46, 26, 52, 12, 0.5, "#ffd98e", "#f2a23a", 90, "#8a4a10", 4, 0, "" },
		{ "r", 64, 20, 34, 28, 0, 0.45, "#ffe2a4", "#f5ac44", 90, "#8a4a10", 4, 0, "" },
		{ "r", 44, 72, 60, 28, 0, 0.5, "#ffd98e", "#f2a23a", 90, "#000000", 0, 0, "" },
		{ "r", 40, 58, 42, 34, 0, 0.5, "#ffe2a4", "#f5ac44", 90, "#000000", 0, 0, "" },
		{ "r", 68, 46, 26, 52, 12, 0.5, "#ffd98e", "#f2a23a", 90, "#000000", 0, 0, "" },
		{ "r", 64, 20, 34, 28, 0, 0.45, "#ffe2a4", "#f5ac44", 90, "#000000", 0, 0, "" },
		{ "r", 58, 24, 14, 3, 0, 0.5, "#c47a22", "#c47a22", 90, "#000000", 0, 0.1, "" },
		{ "r", 56, 54, 4, 16, 30, 0.5, "#c47a22", "#c47a22", 90, "#000000", 0, 0.2, "" },
		{ "r", 32, 50, 16, 8, -15, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.35, "" },
	},
	Pickaxe = {
		{ "r", 45.7, 57.74, 10.32, 66.27, 45, 0.5, "#ffc75e", "#c8661a", 45, "#6a3208", 3, 0, "" },
		{ "r", 45.7, 57.74, 10.32, 66.27, 45, 0.5, "#ffc75e", "#c8661a", 45, "#000000", 0, 0, "" },
		{ "r", 55.16, 29.79, 12.9, 39.22, -51.63, 0.5, "#eef9ff", "#7c8fa6", 141.63, "#26324a", 3, 0, "" },
		{ "r", 38.82, 21.19, 6.88, 18.95, -85.91, 0.5, "#eef9ff", "#7c8fa6", 175.91, "#26324a", 3, 0, "" },
		{ "r", 73.65, 48.28, 12.9, 39.22, 141.63, 0.5, "#eef9ff", "#7c8fa6", -51.63, "#26324a", 3, 0, "" },
		{ "r", 82.25, 64.62, 6.88, 18.95, 175.91, 0.5, "#eef9ff", "#7c8fa6", -85.91, "#26324a", 3, 0, "" },
		{ "r", 55.16, 29.79, 12.9, 39.22, -51.63, 0.5, "#eef9ff", "#7c8fa6", 141.63, "#000000", 0, 0, "" },
		{ "r", 38.82, 21.19, 6.88, 18.95, -85.91, 0.5, "#eef9ff", "#7c8fa6", 175.91, "#000000", 0, 0, "" },
		{ "r", 73.65, 48.28, 12.9, 39.22, 141.63, 0.5, "#eef9ff", "#7c8fa6", -51.63, "#000000", 0, 0, "" },
		{ "r", 82.25, 64.62, 6.88, 18.95, 175.91, 0.5, "#eef9ff", "#7c8fa6", -85.91, "#000000", 0, 0, "" },
		{ "r", 65.48, 37.96, 14.62, 14.62, 45, 0.25, "#ffe27a", "#d08a1a", 45, "#6a3208", 3, 0, "" },
		{ "r", 51.72, 27.64, 4.3, 13.76, -45, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.3, "" },
	},
	Clover = {
		{ "r", 64, 84, 8, 26, -35, 0.5, "#3fc25a", "#1c7a30", 90, "#0e4a1a", 3, 0, "" },
		{ "r", 35, 35, 36, 36, 0, 0.5, "#9dff8e", "#26a83c", 90, "#0e4a1a", 4, 0, "" },
		{ "r", 65, 35, 36, 36, 0, 0.5, "#9dff8e", "#26a83c", 90, "#0e4a1a", 4, 0, "" },
		{ "r", 35, 63, 36, 36, 0, 0.5, "#8ef27e", "#1e9632", 90, "#0e4a1a", 4, 0, "" },
		{ "r", 65, 63, 36, 36, 0, 0.5, "#8ef27e", "#1e9632", 90, "#0e4a1a", 4, 0, "" },
		{ "r", 35, 35, 36, 36, 0, 0.5, "#9dff8e", "#26a83c", 90, "#000000", 0, 0, "" },
		{ "r", 65, 35, 36, 36, 0, 0.5, "#9dff8e", "#26a83c", 90, "#000000", 0, 0, "" },
		{ "r", 35, 63, 36, 36, 0, 0.5, "#8ef27e", "#1e9632", 90, "#000000", 0, 0, "" },
		{ "r", 65, 63, 36, 36, 0, 0.5, "#8ef27e", "#1e9632", 90, "#000000", 0, 0, "" },
		{ "r", 50, 49, 12, 12, 0, 0.5, "#1e8a32", "#1e8a32", 90, "#000000", 0, 0.1, "" },
		{ "r", 29, 28, 10, 7, -30, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.35, "" },
	},
	Target = {
		{ "r", 50, 50, 86, 86, 0, 0.5, "#ff8a7a", "#d01e2e", 90, "#5a0a14", 4.5, 0, "" },
		{ "r", 50, 50, 62, 62, 0, 0.5, "#ffffff", "#ffd8d8", 90, "#a01a26", 2.5, 0, "" },
		{ "r", 50, 50, 40, 40, 0, 0.5, "#ff7464", "#d01e2e", 90, "#a01a26", 2.5, 0, "" },
		{ "r", 50, 50, 17, 17, 0, 0.5, "#ffffff", "#fff0c8", 90, "#a01a26", 2, 0, "" },
		{ "r", 50, 7, 8, 20, 0, 0.45, "#fff07a", "#ffb01e", 90, "#5a0a14", 2.5, 0, "" },
		{ "r", 50, 93, 8, 20, 0, 0.45, "#fff07a", "#ffb01e", 90, "#5a0a14", 2.5, 0, "" },
		{ "r", 7, 50, 20, 8, 0, 0.45, "#fff07a", "#ffb01e", 90, "#5a0a14", 2.5, 0, "" },
		{ "r", 93, 50, 20, 8, 0, 0.45, "#fff07a", "#ffb01e", 90, "#5a0a14", 2.5, 0, "" },
		{ "r", 30, 28, 20, 9, -38, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.35, "" },
		{ "x", 82, 18, 30, 30, 0, 0, "#fff27a", "#ffae18", 90, "#b8600a", 3, 0, "\u{2605}" },
	},
	Feet = {
		{ "r", 34, 66, 26, 40, -12, 0.5, "#fff3dc", "#f0be82", 90, "#6a3410", 3.5, 0, "" },
		{ "r", 23, 38, 12, 12, 0, 0.5, "#fff3dc", "#f0be82", 90, "#6a3410", 3, 0, "" },
		{ "r", 33, 33, 12, 12, 0, 0.5, "#fff3dc", "#f0be82", 90, "#6a3410", 3, 0, "" },
		{ "r", 43, 36, 10, 10, 0, 0.5, "#fff3dc", "#f0be82", 90, "#6a3410", 3, 0, "" },
		{ "r", 67, 50, 26, 40, 12, 0.5, "#fff3dc", "#f0be82", 90, "#6a3410", 3.5, 0, "" },
		{ "r", 58, 20, 10, 10, 0, 0.5, "#fff3dc", "#f0be82", 90, "#6a3410", 3, 0, "" },
		{ "r", 68, 17, 12, 12, 0, 0.5, "#fff3dc", "#f0be82", 90, "#6a3410", 3, 0, "" },
		{ "r", 78, 22, 12, 12, 0, 0.5, "#fff3dc", "#f0be82", 90, "#6a3410", 3, 0, "" },
		{ "r", 30, 58, 6, 14, -12, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.2, "" },
		{ "r", 63, 42, 6, 14, 12, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.2, "" },
	},
	Info = {
		{ "r", 50, 50, 90, 90, 0, 0.5, "#9ad6ff", "#3a6ee8", 90, "#ffffff", 6, 0, "" },
		{ "r", 50, 28, 66, 30, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.7, "" },
		{ "r", 50, 28, 16, 16, 0, 0.5, "#ffffff", "#ffffff", 90, "#1c3a90", 2, 0, "" },
		{ "r", 50, 63, 15, 38, 0, 0.4, "#ffffff", "#e4eeff", 90, "#1c3a90", 2, 0, "" },
	},
	Check = {
		{ "r", 50, 50, 90, 90, 0, 0.5, "#8ef27e", "#1e9a3c", 90, "#0e5a1e", 4, 0, "" },
		{ "r", 50, 28, 66, 30, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.7, "" },
		{ "r", 36, 58, 14, 34, -45, 0.5, "#ffffff", "#e8ffe8", 90, "#0e5a1e", 3, 0, "" },
		{ "r", 58, 49, 14, 58, 40, 0.5, "#ffffff", "#e8ffe8", 90, "#0e5a1e", 3, 0, "" },
		{ "r", 36, 58, 14, 34, -45, 0.5, "#ffffff", "#e8ffe8", 90, "#000000", 0, 0, "" },
		{ "r", 58, 49, 14, 58, 40, 0.5, "#ffffff", "#e8ffe8", 90, "#000000", 0, 0, "" },
	},
	CheckMark = {
		{ "r", 32, 60, 18, 42, -45, 0.5, "#ffffff", "#e8ffe8", 90, "#0e5a1e", 4, 0, "" },
		{ "r", 59, 48, 18, 76, 40, 0.5, "#ffffff", "#e8ffe8", 90, "#0e5a1e", 4, 0, "" },
		{ "r", 32, 60, 18, 42, -45, 0.5, "#ffffff", "#e8ffe8", 90, "#000000", 0, 0, "" },
		{ "r", 59, 48, 18, 76, 40, 0.5, "#ffffff", "#e8ffe8", 90, "#000000", 0, 0, "" },
	},
	Crown = {
		{ "r", 20, 44, 20, 20, 45, 0.15, "#ffe866", "#f5ab1e", 90, "#8a4a06", 4, 0, "" },
		{ "r", 50, 34, 24, 24, 45, 0.15, "#ffe866", "#f5ab1e", 90, "#8a4a06", 4, 0, "" },
		{ "r", 80, 44, 20, 20, 45, 0.15, "#ffe866", "#f5ab1e", 90, "#8a4a06", 4, 0, "" },
		{ "r", 50, 64, 74, 32, 0, 0.18, "#ffe866", "#f0a020", 90, "#8a4a06", 4, 0, "" },
		{ "r", 20, 44, 20, 20, 45, 0.15, "#ffe866", "#f5ab1e", 90, "#000000", 0, 0, "" },
		{ "r", 50, 34, 24, 24, 45, 0.15, "#ffe866", "#f5ab1e", 90, "#000000", 0, 0, "" },
		{ "r", 80, 44, 20, 20, 45, 0.15, "#ffe866", "#f5ab1e", 90, "#000000", 0, 0, "" },
		{ "r", 50, 64, 74, 32, 0, 0.18, "#ffe866", "#f0a020", 90, "#000000", 0, 0, "" },
		{ "r", 20, 29, 12, 12, 0, 0.5, "#fff6c0", "#ffd23c", 90, "#8a4a06", 3, 0, "" },
		{ "r", 50, 16, 13, 13, 0, 0.5, "#fff6c0", "#ffd23c", 90, "#8a4a06", 3, 0, "" },
		{ "r", 80, 29, 12, 12, 0, 0.5, "#fff6c0", "#ffd23c", 90, "#8a4a06", 3, 0, "" },
		{ "r", 50, 82, 80, 13, 0, 0.4, "#f5b52a", "#c8780e", 90, "#8a4a06", 3.5, 0, "" },
		{ "r", 50, 63, 15, 15, 45, 0.2, "#ff8aa6", "#d4204e", 90, "#7a0a24", 2.5, 0, "" },
		{ "r", 27, 64, 11, 11, 0, 0.5, "#a6eeff", "#2a8fe0", 90, "#123f86", 2, 0, "" },
		{ "r", 73, 64, 11, 11, 0, 0.5, "#a6eeff", "#2a8fe0", 90, "#123f86", 2, 0, "" },
		{ "r", 30, 55, 18, 6, 0, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.35, "" },
	},
	Medal = {
		{ "r", 40, 24, 18, 46, -25, 0.1, "#5a9bff", "#1d4fc4", 90, "#0f2a72", 3, 0, "" },
		{ "r", 60, 24, 18, 46, 25, 0.1, "#5a9bff", "#1d4fc4", 90, "#0f2a72", 3, 0, "" },
		{ "r", 50, 64, 58, 58, 0, 0.5, "#ffe066", "#f0a020", 90, "#9a5a08", 4, 0, "" },
		{ "r", 50, 64, 40, 40, 0, 0.5, "#ffb52a", "#ff9412", 90, "#d08a1a", 2.5, 0, "" },
		{ "x", 50, 65, 34, 34, 0, 0, "#fff5b0", "#fff5b0", 90, "#b0600a", 2, 0, "\u{2605}" },
		{ "r", 36, 52, 8, 14, 20, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.4, "" },
	},
	MoneyBag = {
		{ "r", 39, 15, 22, 15, -25, 0.5, "#ffe48a", "#ffe48a", 90, "#9a6a1a", 4, 0, "" },
		{ "r", 61, 15, 22, 15, 25, 0.5, "#ffe48a", "#ffe48a", 90, "#9a6a1a", 4, 0, "" },
		{ "r", 50, 29, 26, 14, 0, 0.3, "#ffe48a", "#ffe48a", 90, "#9a6a1a", 4, 0, "" },
		{ "r", 50, 65, 78, 64, 0, 0.48, "#ffe48a", "#f2c25a", 90, "#9a6a1a", 4, 0, "" },
		{ "r", 39, 15, 22, 15, -25, 0.5, "#ffe48a", "#ffe48a", 90, "#000000", 0, 0, "" },
		{ "r", 61, 15, 22, 15, 25, 0.5, "#ffe48a", "#ffe48a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 29, 26, 14, 0, 0.3, "#ffe48a", "#ffe48a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 65, 78, 64, 0, 0.48, "#ffe48a", "#f2c25a", 90, "#000000", 0, 0, "" },
		{ "r", 50, 36, 36, 8, 0, 0.5, "#d99c34", "#d99c34", 90, "#8a5a14", 2, 0, "" },
		{ "x", 50, 67, 42, 48, 0, 0, "#58de72", "#1f9a3c", 90, "#0f5a22", 3, 0, "$" },
		{ "r", 27, 58, 9, 22, 15, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.4, "" },
	},
	Diamond = {
		{ "r", 50, 58, 46, 46, 45, 0.08, "#8ee6ff", "#2a8fe0", 90, "#123f86", 3, 0, "" },
		{ "r", 50, 38, 66, 22, 0, 0.2, "#f0fcff", "#86dcff", 90, "#123f86", 3, 0, "" },
		{ "r", 50, 66, 3, 34, 0, 0, "#d8f6ff", "#d8f6ff", 90, "#000000", 0, 0.45, "" },
		{ "r", 38, 62, 3, 26, -32, 0, "#d8f6ff", "#d8f6ff", 90, "#000000", 0, 0.5, "" },
		{ "r", 62, 62, 3, 26, 32, 0, "#d8f6ff", "#d8f6ff", 90, "#000000", 0, 0.5, "" },
		{ "r", 32, 34, 12, 6, -10, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.2, "" },
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
	Star = {
		{ "x", 50, 52, 96, 96, 0, 0, "#fff27a", "#ffae18", 90, "#b8600a", 6, 0, "\u{2605}" },
	},
	Coin = {
		{ "r", 50, 50, 86, 86, 0, 0.5, "#ffe066", "#f0a020", 90, "#9a5a08", 8, 0, "" },
		{ "r", 50, 50, 56, 56, 0, 0.5, "#ffc83a", "#ffb020", 90, "#d08a1a", 4, 0, "" },
		{ "r", 36, 32, 12, 20, 30, 0.5, "#ffffff", "#ffffff", 90, "#000000", 0, 0.4, "" },
	},
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

local function drawSpec(parent: Instance, spec: { any }, size: number, z: number?): Frame
	local base = z or 3
	local k = size / 100
	local root = Instance.new("Frame")
	root.Name = "VIcon"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(size, size)
	root.ZIndex = base
	for i, s in ipairs(spec) do
		if s[1] == "p" then
			drawPoly(root, s, k, base + i, i)
			continue
		end
		local obj: GuiObject
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
			(obj :: TextLabel).TextColor3 = Color3.fromHex(s[8])
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

-- Big glossy icon tile (rounded square, gradient, light rim, gloss, vector picture)
local function refTile(parent: Instance, key: string?, emoji: string, c0: Color3, c1: Color3, size: number, pos: UDim2): (Frame, UIGradient, UIStroke)
	local tile = Instance.new("Frame")
	tile.Name = "IconTile"
	tile.Size = UDim2.fromOffset(size, size)
	tile.Position = pos
	tile.BackgroundColor3 = C.White
	tile.BorderSizePixel = 0
	tile.Parent = parent
	corner(tile, math.floor(size * 0.24))
	local g = gradient(tile, c0, c1, 90)
	local st = stroke(tile, c0:Lerp(C.White, 0.5), 3)
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = C.White
	gloss.BackgroundTransparency = 0.78
	gloss.BorderSizePixel = 0
	gloss.Size = UDim2.new(1, -10, 0.44, 0)
	gloss.Position = UDim2.fromOffset(5, 4)
	gloss.Parent = tile
	corner(gloss, math.floor(size * 0.2))
	-- v34: darker bottom bevel + soft glow + drop shadow (more depth)
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.84
	shade.BorderSizePixel = 0
	shade.AnchorPoint = Vector2.new(0.5, 1)
	shade.Size = UDim2.new(1, -6, 0.32, 0)
	shade.Position = UDim2.new(0.5, 0, 1, -3)
	shade.Parent = tile
	corner(shade, math.floor(size * 0.2))
	local spec = key and ICONS[key]
	if spec then
		local glow = Instance.new("Frame")
		glow.Name = "IconGlow"
		glow.BackgroundColor3 = C.White
		glow.BackgroundTransparency = 0.86
		glow.BorderSizePixel = 0
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.48)
		glow.Size = UDim2.fromScale(0.72, 0.72)
		glow.ZIndex = 2
		glow.Parent = tile
		corner(glow, size)
		local isz = math.floor(size * 0.76)
		local sh = Instance.new("CanvasGroup")
		sh.Name = "IconShadow"
		sh.BackgroundTransparency = 1
		sh.BorderSizePixel = 0
		sh.AnchorPoint = Vector2.new(0.5, 0.5)
		sh.Size = UDim2.fromOffset(isz, isz)
		sh.Position = UDim2.new(0.5, math.max(1, math.floor(size * 0.03)), 0.5, math.max(2, math.floor(size * 0.05)))
		sh.GroupTransparency = 0.62
		sh.ZIndex = 2
		sh.Parent = tile
		local shIc = drawSpec(sh, spec, isz, 2)
		for _, d in ipairs(shIc:GetDescendants()) do
			if d:IsA("UIGradient") then
				d:Destroy()
			elseif d:IsA("UIStroke") then
				d.Color = Color3.fromRGB(20, 8, 40)
			elseif d:IsA("TextLabel") then
				d.TextColor3 = Color3.fromRGB(20, 8, 40)
			elseif d:IsA("Frame") then
				d.BackgroundColor3 = Color3.fromRGB(20, 8, 40)
				if d.BackgroundTransparency > 0 and d.BackgroundTransparency < 1 then
					d.BackgroundTransparency = 1
				end
			end
		end
		local ic = drawSpec(tile, spec, isz, 3)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
	else
		local e = label(tile, emoji, UDim2.fromScale(0.74, 0.74), UDim2.fromScale(0.13, 0.13), C.White, 30, Enum.TextXAlignment.Center)
		e.TextScaled = true
		e.TextStrokeTransparency = 1
		e.ZIndex = 3
	end
	return tile, g, st
end

-- Glossy purple row with a colored border
local function refRow(parent: Instance, name: string, height: number, border: Color3, order: number): (Frame, UIGradient, UIStroke)
	local r = Instance.new("Frame")
	r.Name = name
	r.LayoutOrder = order
	r.Size = UDim2.new(1, 0, 0, height)
	r.BackgroundColor3 = C.White
	r.BorderSizePixel = 0
	r.Parent = parent
	corner(r, 16)
	local g = gradient(r, REF.RowTop, REF.RowBot, 90)
	local st = stroke(r, border, 2.5)
	st.Transparency = 0.3
	local gl = Instance.new("Frame")
	gl.Name = "RowGloss"
	gl.BackgroundColor3 = C.White
	gl.BackgroundTransparency = 0.93
	gl.BorderSizePixel = 0
	gl.Size = UDim2.new(1, -12, 0.42, 0)
	gl.Position = UDim2.fromOffset(6, 3)
	gl.Parent = r
	corner(gl, 12)
	return r, g, st
end

-- Thick dark track + bright glossy fill + bold centered text
local function refBar(parent: Instance, size: UDim2, pos: UDim2, c0: Color3, c1: Color3): (Frame, Frame, TextLabel, UIGradient)
	local bg = Instance.new("Frame")
	bg.Name = "Bar"
	bg.Size = size
	bg.Position = pos
	bg.BackgroundColor3 = REF.Track
	bg.BorderSizePixel = 0
	bg.Parent = parent
	corner(bg, 99)
	local bst = stroke(bg, Color3.new(0, 0, 0), 1.5)
	bst.Transparency = 0.45
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = C.White
	fill.BorderSizePixel = 0
	fill.Parent = bg
	corner(fill, 99)
	local fg = gradient(fill, c0, c1, 90)
	local sh = Instance.new("Frame")
	sh.Name = "Shine"
	sh.BackgroundColor3 = C.White
	sh.BackgroundTransparency = 0.65
	sh.BorderSizePixel = 0
	sh.Size = UDim2.new(1, -8, 0.36, 0)
	sh.Position = UDim2.fromOffset(4, 2)
	sh.Parent = fill
	corner(sh, 99)
	local txt = label(bg, "", UDim2.fromScale(1, 1), UDim2.new(), C.White, 15, Enum.TextXAlignment.Center)
	txt.Font = Enum.Font.GothamBlack
	txt.TextStrokeTransparency = 0.2
	txt.TextWrapped = false
	txt.ZIndex = 3
	return bg, fill, txt, fg
end

-- Chunky glossy button (green Upgrade / blue MAX)
local function refButton(parent: Instance, text: string, size: UDim2, pos: UDim2, c0: Color3, c1: Color3, rim: Color3, textSize: number, onClick: () -> ()): (TextButton, UIGradient)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = C.White
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Font = Enum.Font.GothamBlack
	b.Text = text
	b.TextColor3 = C.White
	b.TextSize = textSize
	b.TextStrokeColor3 = c1:Lerp(Color3.new(0, 0, 0), 0.55)
	b.TextStrokeTransparency = 0.15
	b.Parent = parent
	corner(b, 14)
	local g = gradient(b, c0, c1, 90)
	stroke(b, rim, 2)
	local gl = Instance.new("Frame")
	gl.Name = "Gloss"
	gl.BackgroundColor3 = C.White
	gl.BackgroundTransparency = 0.8
	gl.BorderSizePixel = 0
	gl.Size = UDim2.new(1, -10, 0.42, 0)
	gl.Position = UDim2.fromOffset(5, 3)
	gl.Parent = b
	corner(gl, 10)
	addButtonFx(b, onClick)
	return b, g
end

local function refBtnState(btn: TextButton, grad: UIGradient, enabled: boolean, c0: Color3, c1: Color3, text: string?)
	if enabled then
		grad.Color = ColorSequence.new(c0, c1)
		btn.TextTransparency = 0
	else
		grad.Color = ColorSequence.new(c0:Lerp(C.Gray, 0.4), c1:Lerp(C.GrayDark, 0.4))
		btn.TextTransparency = 0.2
	end
	if text then btn.Text = text end
end

-- Wooden frame + wooden title plaque with a vector icon + red close button
local function refWindow(w: Window, iconKey: string, titleText: string)
	local f = w.Frame
	local g = f:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(REF.PanelTop, REF.PanelBot)
	end
	local st = f:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = REF.Wood
		st.Thickness = 7
		st.Transparency = 0
	end
	local rim = f:FindFirstChild("GoldRim")
	local rs = rim and rim:FindFirstChildOfClass("UIStroke")
	if rs then
		rs.Color = REF.WoodDark
		rs.Thickness = 3
		rs.Transparency = 0
	end
	local gloss = f:FindFirstChild("PanelGloss")
	if gloss and gloss:IsA("Frame") then
		gloss.BackgroundTransparency = 0.96
	end
	local plaque = f:FindFirstChild("TitlePlaque")
	if plaque and plaque:IsA("Frame") then
		plaque.Size = UDim2.new(0, 340, 0, 58)
		plaque.Position = UDim2.new(0, 28, 0, -22)
		local pg = plaque:FindFirstChildOfClass("UIGradient")
		if pg then
			pg.Color = ColorSequence.new(Color3.fromRGB(150, 92, 46), Color3.fromRGB(88, 52, 24))
		end
		local ps = plaque:FindFirstChildOfClass("UIStroke")
		if ps then
			ps.Color = REF.WoodLight
			ps.Thickness = 3
		end
		local ic = drawSpec(plaque, ICONS[iconKey], 64, 4)
		ic.Position = UDim2.fromOffset(6, -10)
	end
	w.Title.Text = titleText
	w.Title.TextColor3 = REF.Cream
	w.Title.TextStrokeColor3 = Color3.fromRGB(60, 30, 8)
	w.Title.TextStrokeTransparency = 0
	w.Title.Position = UDim2.fromOffset(72, 4)
	w.Title.Size = UDim2.new(1, -82, 1, -8)
	w.Title.TextXAlignment = Enum.TextXAlignment.Left
	local tsc = w.Title:FindFirstChildOfClass("UITextSizeConstraint")
	if tsc then tsc.MaxTextSize = 34 end
	for _, ch in ipairs(f:GetChildren()) do
		if ch:IsA("TextButton") and ch:GetAttribute("CloseX") then
			ch.Size = UDim2.fromOffset(52, 52)
			ch.Position = UDim2.new(1, -60, 0, -16)
			ch.Text = ""
			ch.Font = Enum.Font.GothamBlack
			ch.TextSize = 30
			ch.TextStrokeColor3 = Color3.fromRGB(90, 0, 10)
			ch.TextStrokeTransparency = 0.2
			local cg = ch:FindFirstChildOfClass("UIGradient")
			if cg then cg.Color = ColorSequence.new(Color3.fromRGB(255, 92, 92), Color3.fromRGB(186, 18, 32)) end
			local cc = ch:FindFirstChildOfClass("UICorner")
			if cc then cc.CornerRadius = UDim.new(0, 14) end
			local cgl = Instance.new("Frame")
			cgl.BackgroundColor3 = C.White
			cgl.BackgroundTransparency = 0.78
			cgl.BorderSizePixel = 0
			cgl.Size = UDim2.new(1, -10, 0.42, 0)
			cgl.Position = UDim2.fromOffset(5, 3)
			cgl.Parent = ch
			corner(cgl, 10)
		end
	end
	w.Body.Position = UDim2.new(0, 16, 0, 50)
	w.Body.Size = UDim2.new(1, -32, 1, -62)
end

local function refFooter(body: Instance, iconKey: string?, iconText: string?, text: string)
	local holder = Instance.new("Frame")
	holder.Name = "Footer"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 26)
	holder.Position = UDim2.new(0, 0, 1, -26)
	holder.Parent = body
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.Padding = UDim.new(0, 8)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = holder
	if iconKey and ICONS[iconKey] then
		drawSpec(holder, ICONS[iconKey], 24, 3).LayoutOrder = 1
	elseif iconText then
		local b = Instance.new("TextLabel")
		b.Size = UDim2.fromOffset(22, 22)
		b.BackgroundColor3 = Color3.fromRGB(140, 110, 230)
		b.Text = iconText
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 14
		b.TextColor3 = C.White
		b.LayoutOrder = 1
		b.Parent = holder
		corner(b, 11)
		stroke(b, C.White, 1.5)
	end
	local t = label(holder, text, UDim2.new(0, 0, 1, 0), UDim2.new(), REF.Lav, 16, Enum.TextXAlignment.Center)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.TextWrapped = false
	t.LayoutOrder = 2
end

local SKILL_PAL: { [string]: { Color3 } } = {
	Energy = { Color3.fromRGB(118, 240, 118), Color3.fromRGB(22, 150, 62) },
	Power = { Color3.fromRGB(255, 120, 72), Color3.fromRGB(205, 40, 30) },
	Speed = { Color3.fromRGB(255, 212, 72), Color3.fromRGB(232, 128, 18) },
	Luck = { Color3.fromRGB(104, 232, 112), Color3.fromRGB(20, 140, 60) },
	Critical = { Color3.fromRGB(206, 104, 255), Color3.fromRGB(112, 40, 206) },
}
local SKILL_ICON: { [string]: string } = { Energy = "Bolt", Power = "Muscle", Speed = "Pickaxe", Luck = "Clover", Critical = "Target" }
local ACH_PAL: { [string]: { Color3 } } = {
	FirstSteps = { Color3.fromRGB(96, 214, 200), Color3.fromRGB(20, 124, 128) },
	Miner = { Color3.fromRGB(110, 170, 255), Color3.fromRGB(36, 82, 200) },
	Master = { Color3.fromRGB(214, 120, 255), Color3.fromRGB(108, 40, 200) },
	Rich = { Color3.fromRGB(120, 230, 110), Color3.fromRGB(24, 140, 64) },
	Collector = { Color3.fromRGB(255, 132, 196), Color3.fromRGB(196, 40, 120) },
}
local ACH_ICON: { [string]: string } = { FirstSteps = "Feet", Miner = "Pickaxe", Master = "Medal", Rich = "MoneyBag", Collector = "Diamond" }

-- ============================================================================
-- 5. ОКНО НАВЫКОВ (КАК НА КАРТИНКЕ)
-- ============================================================================
local skillsWin = createWindow("SkillsWindow", "SKILLS", C.Purple, 780, 660)
refWindow(skillsWin, "Bolt", "SKILLS")

local pointsChip = Instance.new("Frame")
pointsChip.Name = "PointsChip"
pointsChip.Size = UDim2.new(0, 250, 0, 48)
pointsChip.Position = UDim2.new(1, -326, 0, -14)
pointsChip.BackgroundColor3 = C.White
pointsChip.BorderSizePixel = 0
pointsChip.Parent = skillsWin.Frame
corner(pointsChip, 24)
gradient(pointsChip, Color3.fromRGB(255, 228, 92), Color3.fromRGB(236, 148, 18), 90)
stroke(pointsChip, Color3.fromRGB(255, 246, 190), 3)
do
	local cgl = Instance.new("Frame")
	cgl.BackgroundColor3 = C.White
	cgl.BackgroundTransparency = 0.75
	cgl.BorderSizePixel = 0
	cgl.Size = UDim2.new(1, -16, 0.4, 0)
	cgl.Position = UDim2.fromOffset(8, 3)
	cgl.Parent = pointsChip
	corner(cgl, 12)
	drawSpec(pointsChip, ICONS.Star, 36, 3).Position = UDim2.fromOffset(12, 6)
end
local pointsLbl = label(pointsChip, "Skill Points: 0", UDim2.new(1, -60, 1, 0), UDim2.new(0, 52, 0, 0), C.White, 20, Enum.TextXAlignment.Left)
pointsLbl.Font = Enum.Font.GothamBlack
pointsLbl.TextWrapped = false
pointsLbl.TextStrokeColor3 = Color3.fromRGB(130, 64, 4)
pointsLbl.TextStrokeTransparency = 0.1

drawSpec(skillsWin.Body, ICONS.Star, 28, 3).Position = UDim2.fromOffset(4, 0)
local skillsInfoLbl = label(skillsWin.Body, "", UDim2.new(1, -44, 0, 28), UDim2.new(0, 40, 0, 0), REF.Cream, 19)
skillsInfoLbl.TextWrapped = false
local skillsList = scrollList(skillsWin.Body, UDim2.new(1, 0, 1, -66), UDim2.new(0, 0, 0, 36))
refFooter(skillsWin.Body, "Info", nil, "1 skill point per level  •  Max 50 levels  •  Key [K]")

type SkillRow = {
	Tile: Frame,
	LevelLbl: TextLabel,
	DescLbl: TextLabel,
	Fill: Frame,
	BarTxt: TextLabel,
	UpBtn: TextButton,
	UpGrad: UIGradient,
	MaxBtn: TextButton,
	MaxGrad: UIGradient,
}
local SkillRows: { [string]: SkillRow } = {}

for order, skillId in ipairs(ProgressionConfig.SKILL_ORDER) do
	local info = ProgressionConfig.SKILLS[skillId]
	local pal = SKILL_PAL[skillId] or { info.Color, info.ColorDark }
	local row = refRow(skillsList, "Skill_" .. skillId, 102, pal[1], order)
	local tile = refTile(row, SKILL_ICON[skillId], info.Icon, pal[1], pal[2], 82, UDim2.fromOffset(10, 10))

	local nameLbl = label(row, info.Name, UDim2.new(0, 270, 0, 28), UDim2.fromOffset(106, 8), pal[1]:Lerp(C.White, 0.1), 23)
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextWrapped = false
	nameLbl.TextStrokeColor3 = Color3.fromRGB(24, 12, 34)
	nameLbl.TextStrokeTransparency = 0.25
	local lvlLbl = label(row, "Lv. 0 / 50", UDim2.new(0, 120, 0, 28), UDim2.fromOffset(366, 8), C.White, 18, Enum.TextXAlignment.Right)
	lvlLbl.TextWrapped = false
	local descLbl = label(row, "", UDim2.new(0, 380, 0, 30), UDim2.fromOffset(106, 36), C.White, 14)
	descLbl.TextYAlignment = Enum.TextYAlignment.Top
	descLbl.TextStrokeTransparency = 0.6
	local _, fill, barTxt = refBar(row, UDim2.new(0, 380, 0, 20), UDim2.fromOffset(106, 72), pal[1]:Lerp(C.White, 0.15), pal[2])

	local upBtn, upGrad = refButton(row, "Upgrade", UDim2.new(0, 142, 0, 64), UDim2.new(1, -240, 0.5, -32), REF.Green0, REF.Green1, REF.GreenRim, 24, function()
		UpgradeSkillRemote:FireServer(skillId, 1)
	end)
	local maxBtn, maxGrad = refButton(row, "MAX", UDim2.new(0, 86, 0, 64), UDim2.new(1, -92, 0.5, -32), REF.Max0, REF.Max1, REF.MaxRim, 22, function()
		UpgradeSkillRemote:FireServer(skillId, "max")
	end)
	maxBtn.TextColor3 = Color3.fromRGB(222, 230, 255)

	SkillRows[skillId] = {
		Tile = tile, LevelLbl = lvlLbl, DescLbl = descLbl, Fill = fill, BarTxt = barTxt,
		UpBtn = upBtn, UpGrad = upGrad, MaxBtn = maxBtn, MaxGrad = maxGrad,
	}
end

-- ============================================================================
-- 6. ОКНО ДОСТИЖЕНИЙ (КАК НА КАРТИНКЕ)
-- ============================================================================
local achWin = createWindow("AchievementsWindow", "ACHIEVEMENTS", C.Gold, 720, 660)
refWindow(achWin, "Trophy", "ACHIEVEMENTS")
do
	drawSpec(achWin.Body, ICONS.Check, 28, 3).Position = UDim2.fromOffset(4, 0)
end
local achCountLbl = label(achWin.Body, "", UDim2.new(1, -44, 0, 28), UDim2.new(0, 40, 0, 0), REF.Cream, 19)
achCountLbl.TextWrapped = false
local achList = scrollList(achWin.Body, UDim2.new(1, 0, 1, -66), UDim2.new(0, 0, 0, 36))
refFooter(achWin.Body, "Trophy", nil, "Finish goals to earn coins and skill points  •  Key [J]")

type AchRow = {
	TileGrad: UIGradient, TileStroke: UIStroke, Fill: Frame, FillGrad: UIGradient, BarTxt: TextLabel,
	StatusLbl: TextLabel, Check: Frame, Row: Frame, RowGrad: UIGradient, RowStroke: UIStroke, DescLbl: TextLabel,
}
local AchRows: { [string]: AchRow } = {}

for order, ach in ipairs(ProgressionConfig.ACHIEVEMENTS) do
	local row, rowGrad, rowStroke = refRow(achList, "Ach_" .. ach.Id, 98, REF.AchBorder, order)
	local _, tileGrad, tileStroke = refTile(row, ACH_ICON[ach.Id], ach.Icon, (ACH_PAL[ach.Id] or { REF.Blue0 })[1], (ACH_PAL[ach.Id] or { REF.Blue0, REF.Blue1 })[2], 80, UDim2.fromOffset(10, 9))

	local nameLbl = label(row, ach.Name, UDim2.new(0, 300, 0, 30), UDim2.fromOffset(104, 8), C.White, 24)
	nameLbl.Font = Enum.Font.GothamBlack
	nameLbl.TextWrapped = false
	nameLbl.TextStrokeColor3 = Color3.fromRGB(24, 12, 34)
	nameLbl.TextStrokeTransparency = 0.25
	local descLbl = label(row, ach.Description, UDim2.new(0, 320, 0, 22), UDim2.fromOffset(104, 39), REF.Lav, 17)
	descLbl.TextWrapped = false
	descLbl.TextStrokeTransparency = 0.6
	local _, fill, barTxt, fillGrad = refBar(row, UDim2.new(0, 334, 0, 22), UDim2.fromOffset(104, 66), Color3.fromRGB(110, 236, 255), Color3.fromRGB(28, 150, 240))

	-- "Reward:" + coins + stars (like the reference)
	local rHdr = label(row, "Reward:", UDim2.new(0, 140, 0, 22), UDim2.new(1, -252, 0, 14), REF.RewardGold, 17, Enum.TextXAlignment.Center)
	rHdr.Font = Enum.Font.GothamBlack
	rHdr.TextWrapped = false
	rHdr.TextStrokeTransparency = 0.3
	local rLine = Instance.new("Frame")
	rLine.Name = "RewardLine"
	rLine.BackgroundTransparency = 1
	rLine.Size = UDim2.new(0, 140, 0, 26)
	rLine.Position = UDim2.new(1, -252, 0, 38)
	rLine.Parent = row
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.Padding = UDim.new(0, 4)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = rLine
	local function rText(txt: string, ord: number)
		local t = label(rLine, txt, UDim2.new(0, 0, 1, 0), UDim2.new(), REF.RewardGold:Lerp(C.White, 0.35), 17, Enum.TextXAlignment.Center)
		t.Font = Enum.Font.GothamBlack
		t.AutomaticSize = Enum.AutomaticSize.X
		t.TextWrapped = false
		t.TextStrokeTransparency = 0.25
		t.LayoutOrder = ord
	end
	if ach.RewardCoins > 0 then
		rText("+" .. formatNumber(ach.RewardCoins), 1)
		drawSpec(rLine, ICONS.Coin, 20, 3).LayoutOrder = 2
	end
	if ach.RewardSkillPoints > 0 then
		rText(" +" .. tostring(ach.RewardSkillPoints), 3)
		drawSpec(rLine, ICONS.Star, 22, 3).LayoutOrder = 4
	end

	local status = label(row, "0%", UDim2.new(0, 100, 0, 44), UDim2.new(1, -108, 0.5, -22), C.White, 32, Enum.TextXAlignment.Center)
	status.Font = Enum.Font.GothamBlack
	status.TextWrapped = false
	status.TextStrokeColor3 = Color3.fromRGB(20, 10, 40)
	status.TextStrokeTransparency = 0.2

	local check = Instance.new("Frame")
	check.Name = "DoneCheck"
	check.Size = UDim2.fromOffset(54, 54)
	check.Position = UDim2.new(1, -86, 0.5, -27)
	check.BackgroundColor3 = C.White
	check.BorderSizePixel = 0
	check.Visible = false
	check.Parent = row
	corner(check, 12)
	gradient(check, Color3.fromRGB(110, 236, 96), Color3.fromRGB(26, 150, 46), 90)
	stroke(check, C.White, 3)
	do
		local cgl = Instance.new("Frame")
		cgl.BackgroundColor3 = C.White
		cgl.BackgroundTransparency = 0.75
		cgl.BorderSizePixel = 0
		cgl.Size = UDim2.new(1, -8, 0.42, 0)
		cgl.Position = UDim2.fromOffset(4, 3)
		cgl.Parent = check
		corner(cgl, 9)
		local cm = drawSpec(check, ICONS.CheckMark, 40, 3)
		cm.AnchorPoint = Vector2.new(0.5, 0.5)
		cm.Position = UDim2.fromScale(0.5, 0.5)
	end

	AchRows[ach.Id] = {
		TileGrad = tileGrad, TileStroke = tileStroke, Fill = fill, FillGrad = fillGrad, BarTxt = barTxt,
		StatusLbl = status, Check = check, Row = row, RowGrad = rowGrad, RowStroke = rowStroke, DescLbl = descLbl,
	}
end

-- ============================================================================
-- 7. ОКНО ПРЕСТИЖА
-- ============================================================================
local prestigeWin = createWindow("PrestigeWindow", "👑 PRESTIGE", C.Pink, 520, 430)
local pBody = prestigeWin.Body

local _, auraGrad = refTile(pBody, "Crown", "👑", C.Gold, C.GoldDark, 96, UDim2.new(0, 8, 0, 6))
local prestigeBig = label(pBody, "Prestige 0 / 10", UDim2.new(1, -130, 0, 34), UDim2.new(0, 122, 0, 6), C.White, 26)
local auraLbl = label(pBody, "", UDim2.new(1, -130, 0, 22), UDim2.new(0, 122, 0, 44), C.Gold, 16)
local bonusLbl = label(pBody, "", UDim2.new(1, -130, 0, 22), UDim2.new(0, 122, 0, 70), C.Muted, 14)

local reqLbl = label(pBody, "", UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 120), C.White, 15)
local _, reqFill, reqTxt = progressBar(pBody, UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, 146), C.Pink, C.PinkDark)

local resetText = ProgressionConfig.PRESTIGE_RESETS_SKILLS
	and "Resets: level, XP and skills.\nKeeps: coins, pickaxes, backpack and achievements."
	or "Resets: level and XP.\nKeeps: skills, coins, pickaxes, backpack and achievements."
label(pBody, resetText, UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 0, 176), C.Muted, 13)
local nextAuraLbl = label(pBody, "", UDim2.new(1, -16, 0, 20), UDim2.new(0, 8, 0, 220), C.Muted, 13)

local confirmUntil = 0
local prestigeBtn: TextButton
local prestigeBtnGrad: UIGradient
prestigeBtn, prestigeBtnGrad = button(pBody, "👑 PRESTIGE NOW", UDim2.new(1, -16, 0, 60), UDim2.new(0, 8, 1, -70), C.Pink, C.PinkDark, 20, function()
	if not State.CanPrestige then return end
	if os.clock() < confirmUntil then
		confirmUntil = 0
		PrestigeRemote:FireServer()
	else
		confirmUntil = os.clock() + 3
		prestigeBtn.Text = "⚠️ Sure? Tap again!"
		task.delay(3.05, function()
			if os.clock() >= confirmUntil then refreshAll() end
		end)
	end
end)

-- ============================================================================
-- 8. КНОПКИ СЛЕВА (стиль «Магазин» / «Индекс» с картинки)
-- ============================================================================
local sideMenu = Instance.new("Frame")
sideMenu.Name = "ProgressionSideMenu"
sideMenu.BackgroundTransparency = 1
sideMenu.AnchorPoint = Vector2.new(0, 0.5)
sideMenu.Size = UDim2.new(0, 224, 0, 290) -- v26: 4 buttons like the reference
sideMenu.Position = UDim2.new(0, 14, 0.5, 30)
-- v10: встраиваемся в левую колонку HUD под плашки Сила/Уровень/Опыт
-- (у колонки свой адаптивный UIScale). Если HUD не найден — стоим отдельно.
do
	local hudGui = playerGui:WaitForChild("MinerSimulatorHUD_v8", 6)
	local column = hudGui and hudGui:WaitForChild("LeftColumn", 6)
	if column then
		sideMenu.AnchorPoint = Vector2.new(0, 0)
		sideMenu.Position = UDim2.new()
		sideMenu.LayoutOrder = 10
		sideMenu.Parent = column
	else
		sideMenu.Parent = screenGui
		responsive(sideMenu)
	end
end
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 10)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = sideMenu

-- v25: big glossy side buttons like the reference (blue / orange / purple)
local SIDE_PALETTE: { { Color3 } } = {
	{ Color3.fromRGB(70, 196, 255), Color3.fromRGB(22, 104, 236) },
	{ Color3.fromRGB(255, 186, 70), Color3.fromRGB(236, 106, 20) },
	{ Color3.fromRGB(206, 110, 255), Color3.fromRGB(128, 44, 226) },
	{ Color3.fromRGB(110, 236, 130), Color3.fromRGB(26, 160, 70) },
}
local function sideButton(order: number, icon: string, text: string, c0: Color3, c1: Color3, onClick: () -> ()): (TextButton, TextLabel)
	local pal = SIDE_PALETTE[order]
	if pal then
		c0, c1 = pal[1], pal[2]
	end
	local b, bg = button(sideMenu, "", UDim2.new(0, 214, 0, 64), UDim2.new(), c0, c1, 16, onClick)
	b.LayoutOrder = order
	bg.Color = ColorSequence.new(c0, c1)
	local bc = b:FindFirstChildOfClass("UICorner")
	if bc then bc.CornerRadius = UDim.new(0, 16) end
	local bs = b:FindFirstChildOfClass("UIStroke")
	if bs then
		bs.Color = c0:Lerp(C.White, 0.55)
		bs.Thickness = 3.5
		bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	local gl = Instance.new("Frame")
	gl.Name = "Gloss"
	gl.BackgroundColor3 = C.White
	gl.BackgroundTransparency = 0.8
	gl.BorderSizePixel = 0
	gl.Size = UDim2.new(1, -12, 0.44, 0)
	gl.Position = UDim2.fromOffset(6, 3)
	gl.Parent = b
	corner(gl, 11)
	-- v26: translucent icon well + drawn picture (like the reference)
	local well = Instance.new("Frame")
	well.Name = "IconWell"
	well.BackgroundColor3 = C.White
	well.BackgroundTransparency = 0.82
	well.BorderSizePixel = 0
	well.Size = UDim2.fromOffset(54, 54)
	well.Position = UDim2.new(0, 7, 0.5, -27)
	well.Parent = b
	corner(well, 14)
	local ws = Instance.new("UIStroke")
	ws.Color = C.White
	ws.Transparency = 0.55
	ws.Thickness = 1.5
	ws.Parent = well
	local drawn: any = nil
	if HudModule and HudModule.DrawIcon then
		drawn = HudModule.DrawIcon(b, icon, 58, 3)
	end
	if drawn then
		drawn.Position = UDim2.new(0, 5, 0.5, -29)
	else
		local tile = iconTile(b, icon, c0:Lerp(C.White, 0.25), c1, 48, UDim2.new(0, 8, 0.5, -24))
		tile.Active = false
	end
	local t = label(b, text, UDim2.new(1, -78, 1, -8), UDim2.new(0, 70, 0, 4), C.White, 22)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextStrokeTransparency = 1
	local ts = Instance.new("UIStroke")
	ts.Color = c1:Lerp(Color3.new(0, 0, 0), 0.6)
	ts.Thickness = 2.5
	ts.Parent = t
	local tsc = t:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	tsc.MaxTextSize = 22
	tsc.MinTextSize = 10
	tsc.Parent = t
	return b, t
end

-- v26: exactly like the reference: Shop / Inventory / Achievements / Skills (Prestige opens from "+" on the Level plate)
local function fireHudBus(eventName: string)
	local hudGui = playerGui:FindFirstChild("MinerSimulatorHUD_v8")
	local bus = hudGui and hudGui:FindFirstChild("UIBus")
	local ev = bus and bus:FindFirstChild(eventName)
	if ev and ev:IsA("BindableEvent") then
		ev:Fire()
	end
end
sideButton(1, "Cart", "Shop", C.Purple, C.PurpleDark, function() fireHudBus("OpenShop") end)
sideButton(2, "Backpack", "Inventory", C.Gold, C.GoldDark, function() fireHudBus("OpenBag") end)
local achBtn = sideButton(3, "Trophy", "Achievements", C.Pink, C.PinkDark, function() openWindow("AchievementsWindow") end)
local skillsBtn = sideButton(4, "Chart", "Skills", C.Purple, C.PurpleDark, function() openWindow("SkillsWindow") end)
local prestigeSideLbl = Instance.new("TextLabel") -- v26: kept only for the refresh code (not shown)
local levelPlusBadge: Frame? = nil

-- v25: "+" on the Strength / Level plates opens Skills
task.spawn(function()
	local hudGui = playerGui:WaitForChild("MinerSimulatorHUD_v8", 15)
	if not hudGui then return end
	for _, nm in ipairs({ "StrengthCard", "LevelCard" }) do
		local pb: Instance? = nil
		for _ = 1, 60 do
			local card = hudGui:FindFirstChild(nm, true)
			pb = card and card:FindFirstChild("PlusBtn", true)
			if pb then break end
			task.wait(0.25)
		end
		if pb and pb:IsA("GuiButton") then
			local target = "SkillsWindow"
			if nm == "LevelCard" then
				target = "PrestigeWindow" -- v26: Prestige moved here from the side menu
				local bd = Instance.new("Frame")
				bd.Name = "PrestigeBadge"
				bd.AnchorPoint = Vector2.new(0.5, 0.5)
				bd.Position = UDim2.new(1, -2, 0, 2)
				bd.Size = UDim2.fromOffset(18, 18)
				bd.BackgroundColor3 = C.Red
				bd.ZIndex = 12
				bd.Visible = false
				bd.Parent = pb
				corner(bd, 99)
				local bt = label(bd, "!", UDim2.new(1, 0, 1, 0), UDim2.new(), C.White, 12, Enum.TextXAlignment.Center)
				bt.ZIndex = 13
				levelPlusBadge = bd
			end
			pb.Activated:Connect(function() openWindow(target) end)
		end
	end
end)

-- Красный значок-счётчик с пульсацией (непотраченные очки)
local function makeBadge(parent: Instance): (Frame, TextLabel)
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.new(0, 28, 0, 28)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -4, 0, 4)
	badge.BackgroundColor3 = C.Red
	badge.ZIndex = 5
	badge.Visible = false
	badge.Parent = parent
	corner(badge, 99)
	stroke(badge, C.White, 2)
	local t = label(badge, "0", UDim2.new(1, 0, 1, 0), UDim2.new(), C.White, 14, Enum.TextXAlignment.Center)
	t.ZIndex = 6
	local sc = Instance.new("UIScale")
	sc.Parent = badge
	TweenService:Create(sc, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.18 }):Play()
	return badge, t
end
local skillsBadge, skillsBadgeLbl = makeBadge(skillsBtn)
local achBadge, achBadgeLbl = makeBadge(achBtn)
achBadgeLbl.Text = "!"

-- ============================================================================
-- 9. ПОПАП «🎉 УРОВЕНЬ ПОВЫШЕН!» + UI-ИСКРЫ
-- ============================================================================
local popup = panel(screenGui, "LevelUpPopup", UDim2.new(0, 460, 0, 118), UDim2.new(0.5, 0, 0.3, 0), C.Gold, 0.15)
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Visible = false
popup.ZIndex = 30
local popupScale = Instance.new("UIScale")
popupScale.Parent = popup
local popupTitle = label(popup, "", UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 0, 14), C.Gold, 30, Enum.TextXAlignment.Center)
local popupSub = label(popup, "", UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 0, 62), C.White, 15, Enum.TextXAlignment.Center)
popupTitle.ZIndex = 31
popupSub.ZIndex = 31
local popupToken = 0

local function burstSparks(origin: UDim2, colors: { Color3 }, count: number)
	for i = 1, count do
		local s = label(screenGui, (i % 3 == 0) and "⭐" or "✦", UDim2.new(0, 26, 0, 26), origin, colors[(i % #colors) + 1], 24, Enum.TextXAlignment.Center)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.ZIndex = 32
		s.TextStrokeTransparency = 1
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local dist = math.random(140, 260)
		local target = origin + UDim2.new(0, math.cos(angle) * dist, 0, math.sin(angle) * dist * 0.7)
		local t = TweenService:Create(s, TweenInfo.new(0.9 + math.random() * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = target,
			Rotation = math.random(-200, 200),
			TextTransparency = 1,
			TextSize = 10,
		})
		t:Play()
		t.Completed:Once(function() s:Destroy() end)
	end
end

local function showPopup(title: string, sub: string, accent: Color3, sparkColors: { Color3 })
	popupToken += 1
	local my = popupToken
	popupTitle.Text = title
	popupTitle.TextColor3 = accent
	popupSub.Text = sub
	local st = popup:FindFirstChildOfClass("UIStroke")
	if st then st.Color = accent end

	local base = getViewportScale()
	popupScale.Scale = 0.2
	popup.Visible = true
	TweenService:Create(popupScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
	burstSparks(popup.Position, sparkColors, 18)

	task.delay(3.0, function()
		if my ~= popupToken then return end
		local t = TweenService:Create(popupScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		t:Play()
		t.Completed:Once(function()
			if my == popupToken then popup.Visible = false end
		end)
	end)
end

-- ============================================================================
-- 10. ТОСТЫ (справа снизу): достижения и сообщения
-- ============================================================================
local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.BackgroundTransparency = 1
toastHolder.AnchorPoint = Vector2.new(1, 1)
toastHolder.Size = UDim2.new(0, 340, 0, 300)
toastHolder.Position = UDim2.new(1, -16, 1, -110)
toastHolder.Parent = screenGui
responsive(toastHolder)
local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 8)
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastHolder
local toastOrder = 0

local TOAST_ICON: { [string]: string } = {
	["\u{2728}"] = "Star", ["\u{2B50}"] = "Star", ["\u{1F3C6}"] = "Trophy", ["\u{1F451}"] = "Crown",
	["\u{1F4B0}"] = "MoneyBag", ["\u{1F48E}"] = "Diamond", ["\u{26A1}"] = "Bolt", ["\u{1F3C5}"] = "Medal",
	["\u{1F4AA}"] = "Muscle", ["\u{1F340}"] = "Clover", ["\u{1F525}"] = "Target", ["\u{1F3AF}"] = "Target",
	["\u{1F463}"] = "Feet", ["\u{26CF}\u{FE0F}"] = "Pickaxe", ["\u{26CF}"] = "Pickaxe",
}
for _, a in ipairs(ProgressionConfig.ACHIEVEMENTS) do
	if a.Icon and ACH_ICON[a.Id] then TOAST_ICON[a.Icon] = ACH_ICON[a.Id] end
end
for sid, sk in pairs(ProgressionConfig.SKILLS) do
	if sk.Icon and SKILL_ICON[sid] then TOAST_ICON[sk.Icon] = SKILL_ICON[sid] end
end

local function showToast(icon: string, title: string, sub: string, accent: Color3, life: number?)
	toastOrder += 1
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, sub ~= "" and 66 or 46)
	holder.LayoutOrder = toastOrder
	holder.ClipsDescendants = false
	holder.Parent = toastHolder

	local t = panel(holder, "Toast", UDim2.new(1, 0, 1, 0), UDim2.new(1.2, 0, 0, 0), accent, 0.15)
	local tkey = TOAST_ICON[icon] or (ICONS[icon] and icon) or nil
	if tkey then
		refTile(t, tkey, icon, accent:Lerp(C.White, 0.15), accent:Lerp(C.Bg, 0.45), sub ~= "" and 48 or 34, UDim2.new(0, 8, 0.5, sub ~= "" and -24 or -17))
	else
		iconTile(t, icon, accent, accent:Lerp(C.Bg, 0.5), sub ~= "" and 48 or 34, UDim2.new(0, 8, 0.5, sub ~= "" and -24 or -17))
	end
	local left = sub ~= "" and 66 or 50
	label(t, title, UDim2.new(1, -left - 8, 0, 22), UDim2.new(0, left, 0, sub ~= "" and 9 or 12), accent:Lerp(C.White, 0.3), 15)
	if sub ~= "" then
		label(t, sub, UDim2.new(1, -left - 8, 0, 20), UDim2.new(0, left, 0, 34), C.White, 13)
	end

	TweenService:Create(t, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 0, 0, 0) }):Play()
	task.delay(life or 4.0, function()
		local out = TweenService:Create(t, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1.2, 0, 0, 0) })
		out:Play()
		out.Completed:Once(function() holder:Destroy() end)
	end)
end

-- ============================================================================
-- 10b. v50: «NEXT GOAL» TRACKER, COMBO METER AND POWER-FRENZY TIMER (top right,
--      under the Coins card). The goal is always the first unfinished achievement.
-- ============================================================================
local refreshGoal: () -> () = function() end
local showCombo: (count: number, window: number, bonusCoins: number) -> () = function() end
local showFrenzy: (seconds: number) -> () = function() end
do
	local funHud = Instance.new("Frame")
	funHud.Name = "FunHud"
	funHud.BackgroundTransparency = 1
	funHud.AnchorPoint = Vector2.new(1, 0)
	funHud.Size = UDim2.fromOffset(250, 230)
	funHud.Position = UDim2.new(1, -14, 0, 102)
	funHud.Parent = screenGui
	responsive(funHud)
	local funLayout = Instance.new("UIListLayout")
	funLayout.Padding = UDim.new(0, 10)
	funLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	funLayout.SortOrder = Enum.SortOrder.LayoutOrder
	funLayout.Parent = funHud

	-- Next goal ------------------------------------------------------------------
	local goalPanel = panel(funHud, "NextGoal", UDim2.fromOffset(250, 78), UDim2.new(), C.Gold, 0.1)
	goalPanel.LayoutOrder = 1
	local goalScale = Instance.new("UIScale")
	goalScale.Parent = goalPanel
	local goalHdr = label(goalPanel, "🎯 NEXT GOAL", UDim2.new(0, 130, 0, 16), UDim2.fromOffset(12, 7), C.Gold, 12)
	goalHdr.TextWrapped = false
	local goalReward = label(goalPanel, "", UDim2.new(0, 110, 0, 16), UDim2.new(1, -122, 0, 7), C.Gold:Lerp(C.White, 0.35), 12, Enum.TextXAlignment.Right)
	goalReward.TextWrapped = false
	local goalName = label(goalPanel, "", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 25), C.White, 16)
	goalName.TextWrapped = false
	goalName.TextTruncate = Enum.TextTruncate.AtEnd
	local _, goalFill, goalTxt = progressBar(goalPanel, UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 52), C.Green, Color3.fromRGB(20, 130, 60))
	local goalBtn = Instance.new("TextButton")
	goalBtn.Name = "OpenAchievements"
	goalBtn.BackgroundTransparency = 1
	goalBtn.Text = ""
	goalBtn.Size = UDim2.fromScale(1, 1)
	goalBtn.ZIndex = 6
	goalBtn.Parent = goalPanel
	goalBtn.MouseButton1Click:Connect(function()
		playSound(Sounds.Click)
		openWindow("AchievementsWindow")
	end)

	local shownGoalId: string? = nil
	refreshGoal = function()
		local nextAch: ProgressionConfig.AchievementInfo? = nil
		for _, ach in ipairs(ProgressionConfig.ACHIEVEMENTS) do
			if State.Achievements[ach.Id] ~= true then
				nextAch = ach
				break
			end
		end
		if not nextAch then
			goalName.Text = "All goals complete! 🏆"
			goalReward.Text = ""
			goalTxt.Text = ""
			setBar(goalFill, 1)
			return
		end
		local goal = ProgressionConfig.GetAchievementGoal(nextAch)
		local value = math.min(State.AchievementProgress[nextAch.Id] or 0, goal)
		local rewards = {}
		if nextAch.RewardCoins > 0 then table.insert(rewards, string.format("+%s 💰", formatNumber(nextAch.RewardCoins))) end
		if nextAch.RewardSkillPoints > 0 then table.insert(rewards, string.format("+%d ✨", nextAch.RewardSkillPoints)) end
		goalName.Text = nextAch.Description
		goalReward.Text = table.concat(rewards, " ")
		goalTxt.Text = string.format("%s / %s", formatNumber(value), formatNumber(goal))
		setBar(goalFill, value / math.max(1, goal))
		if shownGoalId ~= nil and shownGoalId ~= nextAch.Id then
			-- a new goal appeared: little pop so the player notices it
			goalScale.Scale = 1.18
			TweenService:Create(goalScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		shownGoalId = nextAch.Id
	end

	-- Combo meter ------------------------------------------------------------------
	local comboPanel = panel(funHud, "ComboMeter", UDim2.fromOffset(210, 64), UDim2.new(), Color3.fromRGB(255, 150, 50), 0.1)
	comboPanel.LayoutOrder = 2
	comboPanel.Visible = false
	local comboScale = Instance.new("UIScale")
	comboScale.Parent = comboPanel
	local comboStroke = comboPanel:FindFirstChildOfClass("UIStroke")
	local comboTitle = label(comboPanel, "", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 5), C.White, 24, Enum.TextXAlignment.Center)
	comboTitle.Font = Enum.Font.GothamBlack
	comboTitle.TextWrapped = false
	local comboSub = label(comboPanel, "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 32), C.Muted, 12, Enum.TextXAlignment.Center)
	comboSub.TextWrapped = false
	local _, comboFill = progressBar(comboPanel, UDim2.new(1, -24, 0, 7), UDim2.fromOffset(12, 51), Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 120, 40))
	local comboToken = 0

	local function comboColor(count: number): Color3
		if count >= 25 then return Color3.fromRGB(200, 110, 255) end
		if count >= 10 then return Color3.fromRGB(255, 90, 90) end
		if count >= 5 then return Color3.fromRGB(255, 150, 50) end
		return C.Gold
	end

	showCombo = function(count: number, window: number, bonusCoins: number)
		comboToken += 1
		local my = comboToken
		if count < 2 then
			comboPanel.Visible = false
			return
		end
		local col = comboColor(count)
		local xpPct = math.floor(math.min(count - 1, GameConfig.COMBO.XPBonusMaxSteps) * GameConfig.COMBO.XPBonusPerStep * 100 + 0.5)
		comboTitle.Text = string.format("%s ×%d", count >= 25 and "🔥 MEGA COMBO" or "🔥 COMBO", count)
		comboTitle.TextColor3 = col:Lerp(C.White, 0.25)
		comboSub.Text = bonusCoins > 0 and string.format("+%s 💰 combo bonus!", formatNumber(bonusCoins)) or string.format("+%d%% XP  ·  keep digging!", xpPct)
		comboSub.TextColor3 = bonusCoins > 0 and C.Gold or C.Muted
		if comboStroke then comboStroke.Color = col end
		comboPanel.Visible = true

		comboScale.Scale = bonusCoins > 0 and 1.3 or 1.14
		TweenService:Create(comboScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		playSound(Sounds.Click, math.min(2.4, 1.3 + count * 0.04))
		if bonusCoins > 0 then
			burstSparks(UDim2.new(1, -120, 0, 230), { col, C.Gold, C.White }, 8)
		end

		comboFill.Size = UDim2.fromScale(1, 1)
		TweenService:Create(comboFill, TweenInfo.new(window, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
		task.delay(window, function()
			if my == comboToken then comboPanel.Visible = false end
		end)
	end

	-- Power Frenzy timer (Lucky Block prize) ---------------------------------------
	local frenzyPanel = panel(funHud, "FrenzyTimer", UDim2.fromOffset(210, 38), UDim2.new(), Color3.fromRGB(255, 110, 50), 0.1)
	frenzyPanel.LayoutOrder = 3
	frenzyPanel.Visible = false
	local frenzyLbl = label(frenzyPanel, "", UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), Color3.fromRGB(255, 200, 120), 15, Enum.TextXAlignment.Center)
	frenzyLbl.TextWrapped = false
	local frenzyToken = 0

	showFrenzy = function(seconds: number)
		frenzyToken += 1
		local my = frenzyToken
		frenzyPanel.Visible = true
		task.spawn(function()
			for left = math.floor(seconds), 1, -1 do
				if my ~= frenzyToken then return end
				frenzyLbl.Text = string.format("🔥 POWER FRENZY ×%d  ·  %d s", GameConfig.SPECIAL_BLOCKS.FrenzyDamageMultiplier, left)
				task.wait(1)
			end
			if my == frenzyToken then frenzyPanel.Visible = false end
		end)
	end
end

-- ============================================================================
-- 11. ОБНОВЛЕНИЕ ВСЕГО ИНТЕРФЕЙСА
-- ============================================================================
local function setButtonState(btn: TextButton, grad: UIGradient, enabled: boolean, c0: Color3, c1: Color3, text: string?)
	if enabled then
		grad.Color = ColorSequence.new(c0, c1)
		btn.TextTransparency = 0
	else
		grad.Color = ColorSequence.new(C.Gray, C.GrayDark)
		btn.TextTransparency = 0.25
	end
	if text then btn.Text = text end
end

local function fmtBonus(info: ProgressionConfig.SkillInfo, level: number): string
	return string.format("+%s%s", tostring(info.PerLevel * level), info.Suffix)
end

refreshAll = function()
	-- Навыки (v33 reference style)
	local prestigePct = math.floor((ProgressionConfig.GetPrestigeMultiplier(State.Prestige) - 1) * 100 + 0.5)
	pointsLbl.Text = string.format("Skill Points: %d", State.SkillPoints)
	skillsInfoLbl.Text = string.format("Level %d   •   Prestige %d (+%d%% to all)", State.Level, State.Prestige, prestigePct)

	for skillId, refs in pairs(SkillRows) do
		local info = ProgressionConfig.SKILLS[skillId]
		local lvl = ProgressionConfig.GetSkillLevel(State.Skills, skillId)
		local maxed = lvl >= ProgressionConfig.SKILL_MAX_LEVEL
		refs.LevelLbl.Text = string.format("Lv. %d / %d", lvl, ProgressionConfig.SKILL_MAX_LEVEL)
		if maxed then
			refs.DescLbl.Text = string.format("%s: %s  ★ MAX", info.Description, fmtBonus(info, lvl))
		else
			refs.DescLbl.Text = string.format("%s: %s", info.Description, fmtBonus(info, lvl))
		end
		setBar(refs.Fill, lvl / ProgressionConfig.SKILL_MAX_LEVEL)
		refs.BarTxt.Text = string.format("%d%%", math.floor(lvl / ProgressionConfig.SKILL_MAX_LEVEL * 100))

		local can = (not maxed) and State.SkillPoints > 0
		refBtnState(refs.UpBtn, refs.UpGrad, can or State.SkillPoints == 0 and not maxed, REF.Green0, REF.Green1, maxed and "MAXED" or "Upgrade")
		refBtnState(refs.MaxBtn, refs.MaxGrad, can or State.SkillPoints == 0 and not maxed, REF.Max0, REF.Max1, nil)
	end

	skillsBadge.Visible = State.SkillPoints > 0
	skillsBadgeLbl.Text = State.SkillPoints > 99 and "99+" or tostring(State.SkillPoints)

	-- Достижения (v33 reference style)
	local done = 0
	for _, ach in ipairs(ProgressionConfig.ACHIEVEMENTS) do
		local refs = AchRows[ach.Id]
		local goal = ProgressionConfig.GetAchievementGoal(ach)
		local unlocked = State.Achievements[ach.Id] == true
		local value = math.min(State.AchievementProgress[ach.Id] or 0, goal)
		if unlocked then
			done += 1
			value = goal
			refs.RowGrad.Color = ColorSequence.new(Color3.fromRGB(214, 132, 34), Color3.fromRGB(128, 66, 16))
			refs.RowStroke.Color = Color3.fromRGB(255, 210, 84)
			refs.RowStroke.Transparency = 0
			refs.RowStroke.Thickness = 3
			refs.TileGrad.Color = ColorSequence.new(REF.GoldT0, REF.GoldT1)
			refs.TileStroke.Color = REF.GoldRim
			refs.FillGrad.Color = ColorSequence.new(Color3.fromRGB(255, 236, 110), Color3.fromRGB(240, 150, 20))
			refs.DescLbl.TextColor3 = REF.Cream
			refs.StatusLbl.Visible = false
			refs.Check.Visible = true
		else
			refs.RowGrad.Color = ColorSequence.new(REF.RowTop, REF.RowBot)
			refs.RowStroke.Color = REF.AchBorder
			refs.RowStroke.Transparency = 0.3
			refs.RowStroke.Thickness = 2.5
			local apal = ACH_PAL[ach.Id]
			if apal then
				refs.TileGrad.Color = ColorSequence.new(apal[1], apal[2])
				refs.TileStroke.Color = apal[1]:Lerp(C.White, 0.5)
			else
				refs.TileGrad.Color = ColorSequence.new(REF.Blue0, REF.Blue1)
				refs.TileStroke.Color = REF.BlueRim
			end
			refs.FillGrad.Color = ColorSequence.new(Color3.fromRGB(110, 236, 255), Color3.fromRGB(28, 150, 240))
			refs.DescLbl.TextColor3 = REF.Lav
			refs.StatusLbl.Visible = true
			refs.StatusLbl.Text = string.format("%d%%", math.floor(value / math.max(1, goal) * 100))
			refs.Check.Visible = false
		end
		setBar(refs.Fill, value / math.max(1, goal))
		refs.BarTxt.Text = string.format("%s / %s", formatNumber(value), formatNumber(goal))
	end
	achCountLbl.Text = string.format("Completed: %d / %d   •   Rewards are given automatically", done, #ProgressionConfig.ACHIEVEMENTS)
	refreshGoal()

	-- Престиж
	local maxP = ProgressionConfig.PRESTIGE_MAX
	local req = ProgressionConfig.PRESTIGE_REQUIRED_LEVEL
	local aura = ProgressionConfig.GetAura(State.Prestige)
	prestigeBig.Text = string.format("Prestige %d / %d", State.Prestige, maxP)
	prestigeSideLbl.Text = State.Prestige > 0 and string.format("Prestige %d", State.Prestige) or "Prestige"
	if levelPlusBadge then
		levelPlusBadge.Visible = State.Level >= req and State.Prestige < maxP -- v26: "!" when prestige is ready
	end
	if aura then
		auraLbl.Text = "Aura: " .. aura.Name
		auraLbl.TextColor3 = aura.Colors[1]
		auraGrad.Color = ColorSequence.new(aura.Colors[1], aura.Colors[#aura.Colors])
		if aura.Rainbow then
			local kps = {}
			for i, c in ipairs(aura.Colors) do
				table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#aura.Colors - 1), c))
			end
			auraGrad.Color = ColorSequence.new(kps)
		end
	else
		auraLbl.Text = "Aura: none (unlocks at Prestige 1)"
		auraLbl.TextColor3 = C.Muted
		auraGrad.Color = ColorSequence.new(C.Gray, C.GrayDark)
	end

	local nowPct = math.floor((ProgressionConfig.GetPrestigeMultiplier(State.Prestige) - 1) * 100 + 0.5)
	local nextPct = math.floor((ProgressionConfig.GetPrestigeMultiplier(math.min(maxP, State.Prestige + 1)) - 1) * 100 + 0.5)
	bonusLbl.Text = State.Prestige >= maxP
		and string.format("Bonus: +%d%% to all (max!)", nowPct)
		or string.format("Bonus: +%d%% → +%d%% to all", nowPct, nextPct)

	reqLbl.Text = string.format("Requires level %d (now: %d)", req, State.Level)
	setBar(reqFill, State.Level / req)
	reqTxt.Text = string.format("%d / %d", math.min(State.Level, req), req)

	local nextAura: ProgressionConfig.AuraInfo? = nil
	for _, a in ipairs(ProgressionConfig.PRESTIGE_AURAS) do
		if a.MinPrestige > State.Prestige then
			nextAura = a
			break
		end
	end
	nextAuraLbl.Text = nextAura and string.format("Next aura: %s (at Prestige %d)", nextAura.Name, nextAura.MinPrestige) or "All auras unlocked! 🌈"

	if os.clock() >= confirmUntil then
		if State.Prestige >= maxP then
			setButtonState(prestigeBtn, prestigeBtnGrad, false, C.Pink, C.PinkDark, "👑 MAX PRESTIGE")
		elseif State.CanPrestige then
			setButtonState(prestigeBtn, prestigeBtnGrad, true, C.Pink, C.PinkDark, "👑 PRESTIGE NOW")
		else
			setButtonState(prestigeBtn, prestigeBtnGrad, false, C.Pink, C.PinkDark, string.format("🔒 Level %d required", req))
		end
	end
end

-- ============================================================================
-- 12. СОБЫТИЯ С СЕРВЕРА
-- ============================================================================
local firstSync = true
SyncPlayerData.OnClientEvent:Connect(function(data: any)
	if type(data) ~= "table" then return end
	State.Level = data.Level or State.Level
	State.XP = data.XP or State.XP
	State.RequiredXP = data.RequiredXP or State.RequiredXP
	State.Coins = data.Coins or State.Coins
	State.SkillPoints = data.SkillPoints or State.SkillPoints
	State.Skills = data.Skills or State.Skills
	State.Prestige = data.Prestige or State.Prestige
	State.Achievements = data.Achievements or State.Achievements
	State.AchievementProgress = data.AchievementProgress or State.AchievementProgress
	if data.CanPrestige ~= nil then State.CanPrestige = data.CanPrestige end
	refreshAll()
	if firstSync then
		firstSync = false
		if State.SkillPoints > 0 then
			showToast("✨", string.format("You have %d skill points!", State.SkillPoints), "Open ⚡ Skills [K] to upgrade", C.Purple)
		end
	end
end)

ProgressionEvent.OnClientEvent:Connect(function(eventType: string, payload: any)
	if type(payload) ~= "table" then payload = {} end

	if eventType == "LevelUp" then
		playLevelUpSound()
		local gained = tonumber(payload.LevelsGained) or 1
		local sub = string.format("+%d ✨ skill point  ·  +%s 💰  ·  ❤️ Health restored", gained, formatNumber(tonumber(payload.BonusCoins) or 0))
		if payload.CanPrestige then
			sub ..= "\n👑 PRESTIGE available!"
		end
		showPopup(string.format("🎉 Level Up! [%d]", tonumber(payload.Level) or State.Level), sub, C.Gold, { C.Gold, C.White, Color3.fromRGB(255, 170, 40) })

	elseif eventType == "Achievement" then
		playSound(Sounds.Achievement, 1.05)
		local parts = {}
		if (tonumber(payload.RewardCoins) or 0) > 0 then table.insert(parts, string.format("+%s 💰", formatNumber(payload.RewardCoins))) end
		if (tonumber(payload.RewardSkillPoints) or 0) > 0 then table.insert(parts, string.format("+%d ✨", payload.RewardSkillPoints)) end
		showToast(tostring(payload.Icon or "🏆"), "🏆 Achievement Unlocked: " .. tostring(payload.Name or ""), "Reward: " .. table.concat(parts, "  "), C.Gold)
		if OpenWindowName ~= "AchievementsWindow" then
			achBadge.Visible = true
			task.delay(6, function() achBadge.Visible = false end)
		end

	elseif eventType == "Prestige" then
		playSound(Sounds.Prestige, 0.9)
		closeWindow()
		local aura = ProgressionConfig.GetAura(tonumber(payload.Prestige) or 0)
		local colors = aura and aura.Colors or { C.Pink }
		showPopup(
			string.format("👑 PRESTIGE %d!", tonumber(payload.Prestige) or 0),
			string.format("Aura: %s  ·  Bonus +%d%% to all!", tostring(payload.AuraName or ""), tonumber(payload.BonusPercent) or 0),
			colors[1], colors
		)

	elseif eventType == "SkillUpgraded" then
		local refs = SkillRows[tostring(payload.SkillId)]
		if refs then
			local sc = refs.Tile:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			sc.Parent = refs.Tile
			sc.Scale = 1.25
			TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			local info = ProgressionConfig.SKILLS[tostring(payload.SkillId)]
			local plus = label(refs.Tile, string.format("+%d", tonumber(payload.Added) or 1), UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 0, -6), info and info.Color or C.White, 20, Enum.TextXAlignment.Center)
			plus.ZIndex = 8
			local t = TweenService:Create(plus, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, 0, 0, -34), TextTransparency = 1, TextStrokeTransparency = 1,
			})
			t:Play()
			t.Completed:Once(function() plus:Destroy() end)
		end

	elseif eventType == "Toast" then
		local col = typeof(payload.Color) == "Color3" and payload.Color or C.White
		local sub = tostring(payload.Sub or "")
		showToast("💬", tostring(payload.Text or ""), sub, col, sub ~= "" and 8 or nil)

	-- v50: combo meter, surprise blocks, daily reward, first-visit hints
	elseif eventType == "Combo" then
		showCombo(tonumber(payload.Count) or 0, tonumber(payload.Window) or GameConfig.COMBO.WindowSeconds, tonumber(payload.BonusCoins) or 0)

	elseif eventType == "Special" then
		local col = typeof(payload.Color) == "Color3" and payload.Color or C.Gold
		local kind = tostring(payload.Kind or "")
		local icon = (kind == "TNT" and "💥") or (kind == "Treasure" and "💰") or "🍀"
		playSound(Sounds.Achievement, kind == "TNT" and 0.8 or 1.25)
		showToast(icon, tostring(payload.Title or ""), tostring(payload.Sub or ""), col, 5)
		if (tonumber(payload.Frenzy) or 0) > 0 then
			showFrenzy(tonumber(payload.Frenzy) or 0)
		end

	elseif eventType == "DailyReward" then
		playSound(Sounds.Achievement, 1.15)
		local sub = string.format("+%s 💰", formatNumber(tonumber(payload.Coins) or 0))
		if (tonumber(payload.SkillPoints) or 0) > 0 then
			sub ..= string.format("  ·  +%d ✨ skill point", tonumber(payload.SkillPoints) or 0)
		end
		sub ..= "\nCome back tomorrow for a bigger gift!"
		showPopup(string.format("🎁 Daily Reward: Day %d", tonumber(payload.Day) or 1), sub, C.Gold, { C.Gold, C.White, C.Green })

	elseif eventType == "Welcome" then
		showToast("⛏️", "Dig!", "Walk through the MINE gate and tap blocks", C.Green, 12)
		showToast("💰", "Sell!", "Stand on the $ SELL pad to get coins", C.Gold, 12)
		showToast("🎯", "Follow your goals", "Top right: your next reward", C.Purple, 12)
	end
end)

-- ============================================================================
-- 13. ГОРЯЧИЕ КЛАВИШИ: [K] Навыки · [J] Достижения · [P] Престиж
-- ============================================================================
UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.K then
		openWindow("SkillsWindow")
	elseif input.KeyCode == Enum.KeyCode.J then
		openWindow("AchievementsWindow")
	elseif input.KeyCode == Enum.KeyCode.P then
		openWindow("PrestigeWindow")
	end
end)


-- ============================================================================
-- v32: NIGHT MERCHANT WINDOW — exactly like the reference:
-- starry night panel, 🌙 title + subtitle, coin pill, red round ✖,
-- 3×2 neon cards (round icon, name, description, price, colored button),
-- bottom bar with the red backpack icon ("Backpack is empty" / sell 70%).
-- ============================================================================
do
	local NMRemote = Remotes:WaitForChild("NightMerchant", 20) :: RemoteEvent?
	local okIB, IB = pcall(function() return require(Modules:WaitForChild("InputBlocker")) end)
	local okSM, SM = pcall(function() return require(Modules:WaitForChild("SoundManager")) end)
	local okGC, GC = pcall(function() return require(Modules:WaitForChild("GameConfig")) end)
	if NMRemote then
		local NIGHT_0 = Color3.fromRGB(30, 26, 66)
		local NIGHT_1 = Color3.fromRGB(12, 12, 34)
		local CARD_0 = Color3.fromRGB(30, 28, 62)
		local CARD_1 = Color3.fromRGB(16, 15, 38)
		local GOLD = Color3.fromRGB(255, 205, 90)
		local CREAM = Color3.fromRGB(255, 236, 196)
		local MUTED = Color3.fromRGB(176, 172, 214)
		local GREY = Color3.fromRGB(96, 94, 120)
		local WHITE = Color3.new(1, 1, 1)

		local function mCorner(p: Instance, r: number)
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p
		end
		local function mStroke(p: Instance, col: Color3, th: number, tr: number?): UIStroke
			local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th; s.Transparency = tr or 0
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p
			return s
		end
		local function mGrad(p: Instance, c0: Color3, c1: Color3, rot: number?): UIGradient
			local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(c0, c1); g.Rotation = rot or 90; g.Parent = p
			return g
		end
		local function mLabel(parent: Instance, text: string, size: UDim2, pos: UDim2, ts: number, col: Color3, font: Enum.Font?, xa: Enum.TextXAlignment?): TextLabel
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = size; t.Position = pos
			t.Text = text; t.TextSize = ts; t.TextColor3 = col
			t.Font = font or Enum.Font.GothamBold
			t.TextXAlignment = xa or Enum.TextXAlignment.Left
			t.TextYAlignment = Enum.TextYAlignment.Center
			t.TextWrapped = true
			t.Parent = parent
			return t
		end
		local function press(btn: GuiObject)
			local sc = btn:FindFirstChild("PressScale") :: UIScale?
			if not sc then
				local ns = Instance.new("UIScale"); ns.Name = "PressScale"; ns.Parent = btn
				sc = ns
			end
			;(sc :: UIScale).Scale = 0.92
			TweenService:Create(sc :: UIScale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			if okSM and SM and SM.PlayUISound then pcall(SM.PlayUISound, "UIClick") end
		end

		local gui = Instance.new("ScreenGui")
		gui.Name = "NightMerchantGui"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 30
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = player:WaitForChild("PlayerGui")

		local dim = Instance.new("Frame")
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.fromRGB(4, 4, 14)
		dim.BackgroundTransparency = 1
		dim.Visible = false
		dim.Active = true
		dim.Parent = gui

		local W, H = 812, 600
		local panel = Instance.new("Frame")
		panel.Name = "NightMerchantWindow"
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.fromOffset(W, H)
		panel.BackgroundColor3 = WHITE
		panel.ClipsDescendants = false
		panel.Parent = dim
		mCorner(panel, 22)
		mGrad(panel, NIGHT_0, NIGHT_1, 90)
		mStroke(panel, Color3.fromRGB(120, 110, 230), 3, 0.1)
		local scale = Instance.new("UIScale"); scale.Parent = panel
		local function rescale()
			local vp = (Workspace.CurrentCamera :: Camera).ViewportSize
			scale.Scale = math.clamp(math.min(vp.X / (W + 60), vp.Y / (H + 60)), 0.42, 1.15)
		end
		rescale()
		;(Workspace.CurrentCamera :: Camera):GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

		-- outer neon glow
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.BackgroundTransparency = 1
		glow.Size = UDim2.new(1, 12, 1, 12)
		glow.Position = UDim2.fromOffset(-6, -6)
		glow.Parent = panel
		mCorner(glow, 26)
		mStroke(glow, Color3.fromRGB(140, 120, 255), 5, 0.72)

		-- twinkling stars
		local starRng = Random.new(31)
		for i = 1, 46 do
			local s = Instance.new("Frame")
			local sz = starRng:NextInteger(2, 4)
			s.Name = "Star"
			s.BorderSizePixel = 0
			s.BackgroundColor3 = (i % 5 == 0) and Color3.fromRGB(255, 230, 160) or Color3.fromRGB(210, 215, 255)
			s.BackgroundTransparency = starRng:NextNumber(0.15, 0.6)
			s.Size = UDim2.fromOffset(sz, sz)
			s.Position = UDim2.new(starRng:NextNumber(0.02, 0.98), 0, starRng:NextNumber(0.02, 0.98), 0)
			s.Parent = panel
			mCorner(s, 9)
			TweenService:Create(s, TweenInfo.new(starRng:NextNumber(0.9, 2.2), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.9 }):Play()
		end

		-- header: moon + title + subtitle
		local moon = mLabel(panel, "🌙", UDim2.fromOffset(60, 60), UDim2.fromOffset(20, 12), 44, GOLD, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
		moon.TextScaled = true
		local title = mLabel(panel, "NIGHT MERCHANT", UDim2.new(1, -330, 0, 44), UDim2.fromOffset(86, 12), 36, CREAM, Enum.Font.GothamBlack)
		mGrad(title, Color3.fromRGB(255, 244, 210), Color3.fromRGB(255, 196, 92), 90)
		local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(40, 22, 70); ts.Thickness = 2.5; ts.Parent = title
		mLabel(panel, "Open only at night  •  Ore buyback 70%", UDim2.new(1, -330, 0, 22), UDim2.fromOffset(88, 56), 16, MUTED, Enum.Font.GothamBold)

		-- coin pill
		local pill = Instance.new("Frame")
		pill.Name = "CoinPill"
		pill.Size = UDim2.fromOffset(150, 44)
		pill.Position = UDim2.new(1, -226, 0, 20)
		pill.BackgroundColor3 = WHITE
		pill.Parent = panel
		mCorner(pill, 22)
		mGrad(pill, Color3.fromRGB(44, 36, 20), Color3.fromRGB(24, 20, 12), 90)
		mStroke(pill, GOLD, 2.5)
		local coinsLbl = mLabel(pill, "💰 0", UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), 22, GOLD, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)

		-- red round close button
		local closeBtn = Instance.new("TextButton")
		closeBtn.Name = "Close"
		closeBtn.Size = UDim2.fromOffset(48, 48)
		closeBtn.Position = UDim2.new(1, -64, 0, 18)
		closeBtn.BackgroundColor3 = WHITE
		closeBtn.AutoButtonColor = false
		closeBtn.Text = "✖"
		closeBtn.TextColor3 = WHITE
		closeBtn.TextSize = 24
		closeBtn.Font = Enum.Font.GothamBlack
		closeBtn.Parent = panel
		mCorner(closeBtn, 99)
		mGrad(closeBtn, Color3.fromRGB(255, 92, 92), Color3.fromRGB(190, 28, 44), 90)
		mStroke(closeBtn, Color3.fromRGB(255, 190, 190), 2.5)
		vecCross(closeBtn)

		-- 3×2 neon cards
		local ITEMS = {
			{ Id = "RepairKit",    Icon = "🧰", Name = "Repair Kit",    Desc = "Cleans ALL dirt from your backpack. Night only!", Col = Color3.fromRGB(255, 70, 92),  Btn = "CLEAN" },
			{ Id = "Book",         Icon = "📘", Name = "Book",          Desc = "Read it: +XP and +Strength XP",                      Col = Color3.fromRGB(70, 150, 255), Btn = "BUY" },
			{ Id = "Food",         Icon = "🍔", Name = "Food",          Desc = "Burger & soda go to your supplies. Eat anytime [H]", Col = Color3.fromRGB(255, 150, 40), Btn = "BUY" },
			{ Id = "Potion",       Icon = "🧪", Name = "Miner Potion",  Desc = "+25% coins at $ SELL for 3 minutes",                Col = Color3.fromRGB(80, 230, 110), Btn = "BUY" },
			{ Id = "TopHat",       Icon = "🎩", Name = "Top Hat",       Desc = "Cosmetic: a classy night hat for your miner",        Col = Color3.fromRGB(180, 92, 255), Btn = "BUY" },
			{ Id = "MorningCharm", Icon = "🌅", Name = "Morning Bonus", Desc = "Coins + full energy at sunrise",                     Col = Color3.fromRGB(60, 222, 240), Btn = "BUY" },
		}
		type Card = { Price: TextLabel, Extra: TextLabel, Btn: TextButton, BtnGrad: UIGradient, Col: Color3, Base: string, Stroke: UIStroke }
		local cards: { [string]: Card } = {}
		local last: any = nil
		local CW, CH, GAP = 246, 182, 17
		for i, it in ipairs(ITEMS) do
			local col = (i - 1) % 3
			local rowI = math.floor((i - 1) / 3)
			local x = 26 + col * (CW + GAP)
			local y = 98 + rowI * (CH + GAP)
			local cg = Instance.new("Frame")
			cg.Name = it.Id .. "_Glow"
			cg.BackgroundTransparency = 1
			cg.Size = UDim2.fromOffset(CW + 10, CH + 10)
			cg.Position = UDim2.fromOffset(x - 5, y - 5)
			cg.Parent = panel
			mCorner(cg, 20)
			mStroke(cg, it.Col, 6, 0.75)
			local card = Instance.new("Frame")
			card.Name = it.Id
			card.Size = UDim2.fromOffset(CW, CH)
			card.Position = UDim2.fromOffset(x, y)
			card.BackgroundColor3 = WHITE
			card.Parent = panel
			mCorner(card, 16)
			mGrad(card, CARD_0:Lerp(it.Col, 0.08), CARD_1, 90)
			local cst = mStroke(card, it.Col, 2.5)
			-- round icon
			local ic = Instance.new("Frame")
			ic.Name = "Icon"
			ic.Size = UDim2.fromOffset(66, 66)
			ic.Position = UDim2.fromOffset(14, 14)
			ic.BackgroundColor3 = WHITE
			ic.Parent = card
			mCorner(ic, 99)
			mGrad(ic, it.Col:Lerp(WHITE, 0.15), it.Col:Lerp(Color3.new(0, 0, 0), 0.55), 90)
			mStroke(ic, it.Col:Lerp(WHITE, 0.45), 2.5)
			local em = mLabel(ic, it.Icon, UDim2.fromScale(0.66, 0.66), UDim2.fromScale(0.17, 0.17), 30, WHITE, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
			em.TextScaled = true
			mLabel(card, it.Name, UDim2.new(1, -100, 0, 24), UDim2.fromOffset(90, 14), 19, WHITE, Enum.Font.GothamBlack)
			local d = mLabel(card, it.Desc, UDim2.new(1, -100, 0, 54), UDim2.fromOffset(90, 38), 13, MUTED, Enum.Font.GothamMedium)
			d.TextYAlignment = Enum.TextYAlignment.Top
			local price = mLabel(card, "💰 0", UDim2.new(0.5, -14, 0, 28), UDim2.fromOffset(14, 96), 21, GOLD, Enum.Font.GothamBlack)
			local extra = mLabel(card, "", UDim2.new(0.5, -14, 0, 28), UDim2.new(0.5, 0, 0, 96), 12, it.Col:Lerp(WHITE, 0.35), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
			local btn = Instance.new("TextButton")
			btn.Name = "Buy"
			btn.Size = UDim2.new(1, -28, 0, 40)
			btn.Position = UDim2.fromOffset(14, CH - 54)
			btn.BackgroundColor3 = WHITE
			btn.AutoButtonColor = false
			btn.Text = it.Btn
			btn.TextColor3 = WHITE
			btn.TextSize = 20
			btn.Font = Enum.Font.GothamBlack
			btn.Parent = card
			mCorner(btn, 12)
			local bgr = mGrad(btn, it.Col:Lerp(WHITE, 0.12), it.Col:Lerp(Color3.new(0, 0, 0), 0.35), 90)
			mStroke(btn, it.Col:Lerp(WHITE, 0.5), 2)
			local bts = Instance.new("UIStroke"); bts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; bts.Color = it.Col:Lerp(Color3.new(0, 0, 0), 0.6); bts.Thickness = 1.5; bts.Parent = btn
			local gl = Instance.new("Frame")
			gl.BackgroundColor3 = WHITE; gl.BackgroundTransparency = 0.82; gl.BorderSizePixel = 0
			gl.Size = UDim2.new(1, -10, 0.42, 0); gl.Position = UDim2.fromOffset(5, 3); gl.Parent = btn
			mCorner(gl, 9)
			btn.MouseButton1Click:Connect(function()
				press(btn)
				;(NMRemote :: RemoteEvent):FireServer("Buy", it.Id)
			end)
			cards[it.Id] = { Price = price, Extra = extra, Btn = btn, BtnGrad = bgr, Col = it.Col, Base = it.Btn, Stroke = cst }
		end

		-- bottom bar: red backpack icon + "Backpack is empty" / sell 70%
		local bar = Instance.new("Frame")
		bar.Name = "BackpackBar"
		bar.Size = UDim2.new(1, -52, 0, 60)
		bar.Position = UDim2.fromOffset(26, 98 + 2 * (CH + GAP) + 4)
		bar.BackgroundColor3 = WHITE
		bar.Parent = panel
		mCorner(bar, 16)
		mGrad(bar, Color3.fromRGB(34, 30, 64), Color3.fromRGB(18, 16, 40), 90)
		mStroke(bar, Color3.fromRGB(255, 80, 96), 2, 0.35)
		local bi = Instance.new("Frame")
		bi.Size = UDim2.fromOffset(44, 44)
		bi.Position = UDim2.fromOffset(10, 8)
		bi.BackgroundColor3 = WHITE
		bi.Parent = bar
		mCorner(bi, 12)
		mGrad(bi, Color3.fromRGB(255, 92, 100), Color3.fromRGB(176, 26, 44), 90)
		mStroke(bi, Color3.fromRGB(255, 180, 180), 2)
		local bie = mLabel(bi, "🎒", UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15), 24, WHITE, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
		bie.TextScaled = true
		local barLbl = mLabel(bar, "Backpack is empty", UDim2.new(1, -250, 1, 0), UDim2.fromOffset(66, 0), 19, CREAM, Enum.Font.GothamBlack)
		local sellBtn = Instance.new("TextButton")
		sellBtn.Name = "SellAll"
		sellBtn.Size = UDim2.fromOffset(170, 42)
		sellBtn.Position = UDim2.new(1, -180, 0, 9)
		sellBtn.BackgroundColor3 = WHITE
		sellBtn.AutoButtonColor = false
		sellBtn.Text = "SELL 70%"
		sellBtn.TextColor3 = WHITE
		sellBtn.TextSize = 18
		sellBtn.Font = Enum.Font.GothamBlack
		sellBtn.Visible = false
		sellBtn.Parent = bar
		mCorner(sellBtn, 12)
		mGrad(sellBtn, Color3.fromRGB(255, 186, 70), Color3.fromRGB(226, 110, 20), 90)
		mStroke(sellBtn, Color3.fromRGB(255, 226, 160), 2)
		sellBtn.MouseButton1Click:Connect(function()
			press(sellBtn)
			;(NMRemote :: RemoteEvent):FireServer("Sell")
		end)
		local status = mLabel(panel, "", UDim2.new(1, -40, 0, 26), UDim2.new(0, 20, 1, -34), 16, CREAM, Enum.Font.GothamBold, Enum.TextXAlignment.Center)

		local function setBtn(card: Card, txt: string, enabled: boolean)
			card.Btn.Text = txt
			local c = enabled and card.Col or GREY
			card.BtnGrad.Color = ColorSequence.new(c:Lerp(WHITE, 0.12), c:Lerp(Color3.new(0, 0, 0), 0.35))
			card.Btn.TextTransparency = enabled and 0 or 0.25
			card.Stroke.Transparency = enabled and 0 or 0.45
		end

		local function dirtName(stage: number): string
			if okGC and GC and GC.GetDirtStageName then return GC.GetDirtStageName(stage) end
			return ({ [0] = "Clean", "Slightly Dirty", "Dirty", "Very Dirty", "Extremely Dirty" })[stage] or "Clean"
		end

		local function apply(st: any)
			if type(st) ~= "table" then return end
			last = st
			local coins = math.floor(st.Coins or 0)
			coinsLbl.Text = "💰 " .. tostring(coins)
			for id, card in pairs(cards) do
				local p = (st.Prices and st.Prices[id]) or 0
				card.Price.Text = (p > 0) and ("💰 " .. tostring(p)) or "✔ Owned"
				card.Extra.Text = ""
				local afford = p <= coins
				if id == "RepairKit" then
					local stg = math.floor(st.DirtStage or 0)
					local pen = ({ [0] = 0, 10, 20, 30, 40 })[stg] or 0
					card.Extra.Text = stg > 0 and string.format("%s -%d%%", dirtName(stg), pen) or "✨ Clean"
					if stg <= 0 and (st.Dirt or 0) <= 0 then setBtn(card, "CLEAN ✔", false) else setBtn(card, "CLEAN", afford) end
				elseif id == "Food" then
					card.Extra.Text = string.format("Stock: %d/%d", math.floor(st.FoodStock or 0), math.floor(st.FoodMax or 20))
					if (st.FoodStock or 0) >= (st.FoodMax or 20) then setBtn(card, "FULL", false) else setBtn(card, "BUY", afford) end
				elseif id == "TopHat" and st.OwnsHat then
					setBtn(card, st.HatOn and "UNEQUIP" or "EQUIP", true)
				elseif id == "MorningCharm" and st.Charm then
					card.Extra.Text = "until sunrise"
					setBtn(card, "ACTIVE", false)
				elseif id == "Potion" and (st.PotionLeft or 0) > 0 then
					card.Extra.Text = string.format("%d:%02d left", math.floor(st.PotionLeft / 60), st.PotionLeft % 60)
					setBtn(card, "EXTEND", afford)
				else
					setBtn(card, card.Base, afford)
				end
			end
			local bb = math.floor(st.Buyback or 0)
			if bb > 0 then
				barLbl.Text = string.format("Ore in backpack: %d / %d  →  +%d 💰 (70%%)", math.floor(st.BagUsed or 0), math.floor(st.BagMax or 0), bb)
				sellBtn.Visible = true
			else
				barLbl.Text = "Backpack is empty"
				sellBtn.Visible = false
			end
		end

		local isOpen = false
		local function close()
			if not isOpen then return end
			isOpen = false
			TweenService:Create(dim, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = scale.Scale * 0.85 }):Play()
			task.delay(0.19, function()
				if not isOpen then dim.Visible = false; rescale() end
			end)
			if okIB and IB then pcall(IB.SetMenuOpen, "NightMerchant", false) end
		end
		local function open()
			if okIB and IB then
				pcall(IB.CloseOtherMenus, "NightMerchant")
				pcall(IB.SetMenuOpen, "NightMerchant", true)
			end
			if isOpen then return end
			isOpen = true
			status.Text = ""
			rescale()
			local target = scale.Scale
			scale.Scale = target * 0.85
			dim.Visible = true
			TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.4 }):Play()
			TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back), { Scale = target }):Play()
			if okSM and SM and SM.PlayUISound then pcall(SM.PlayUISound, "UIClick") end
		end
		if okIB and IB then pcall(IB.RegisterCloseCallback, "NightMerchant", close) end
		closeBtn.MouseButton1Click:Connect(function() press(closeBtn); close() end)
		UserInputService.InputBegan:Connect(function(input: InputObject, _gpe: boolean)
			if isOpen and input.KeyCode == Enum.KeyCode.Escape then close() end
		end)

		;(NMRemote :: RemoteEvent).OnClientEvent:Connect(function(kind: any, a: any, b: any, c: any)
			if kind == "Open" then
				apply(a); open()
			elseif kind == "Close" then
				close()
			elseif kind == "Result" then
				status.Text = tostring(b or "")
				status.TextColor3 = (a == true) and Color3.fromRGB(130, 240, 150) or Color3.fromRGB(255, 130, 110)
				if c then apply(c) end
			end
		end)
		-- potion countdown refresh
		task.spawn(function()
			while true do
				task.wait(1)
				if isOpen and last and (last.PotionLeft or 0) > 0 then
					last.PotionLeft -= 1
					apply(last)
				end
			end
		end)
	end
end

-- ============================================================================
-- v32: 🍔 FOOD SUPPLIES — eat a burger anywhere (even in the mine): full energy.
-- Button in the left HUD column + hotkey [H]. Server validates the stock.
-- ============================================================================
do
	local EatRemote = Remotes:WaitForChild("EatFood", 20) :: RemoteEvent?
	if EatRemote then
		local ORANGE_0 = Color3.fromRGB(255, 176, 66)
		local ORANGE_1 = Color3.fromRGB(222, 96, 18)
		local food = Instance.new("TextButton")
		food.Name = "FoodSuppliesButton"
		food.Size = UDim2.fromOffset(214, 54)
		food.AutoButtonColor = false
		food.Text = ""
		food.BackgroundColor3 = C.White
		food.LayoutOrder = 11
		corner(food, 16)
		local fg = gradient(food, ORANGE_0, ORANGE_1, 90)
		local fs = stroke(food, ORANGE_0:Lerp(C.White, 0.55), 3)
		local gl = Instance.new("Frame")
		gl.BackgroundColor3 = C.White; gl.BackgroundTransparency = 0.8; gl.BorderSizePixel = 0
		gl.Size = UDim2.new(1, -12, 0.44, 0); gl.Position = UDim2.fromOffset(6, 3); gl.Parent = food
		corner(gl, 11)
		local ic = label(food, "🍔", UDim2.fromOffset(44, 44), UDim2.fromOffset(8, 5), C.White, 30, Enum.TextXAlignment.Center)
		ic.TextScaled = true
		ic.TextStrokeTransparency = 1
		local cnt = label(food, "x0", UDim2.new(1, -70, 0, 28), UDim2.fromOffset(60, 4), C.White, 22)
		cnt.Font = Enum.Font.GothamBlack
		cnt.TextStrokeTransparency = 0.3
		local hint = label(food, "[H] Eat • full energy", UDim2.new(1, -70, 0, 18), UDim2.fromOffset(60, 31), Color3.fromRGB(255, 240, 210), 12)
		hint.TextStrokeTransparency = 0.6

		local placed = false
		do
			local hudGui = playerGui:FindFirstChild("MinerSimulatorHUD_v8")
			local column = hudGui and hudGui:FindFirstChild("LeftColumn")
			if column and sideMenu.Parent == column then
				food.Parent = column
				placed = true
			end
		end
		if not placed then
			food.AnchorPoint = Vector2.new(0, 1)
			food.Position = UDim2.new(0, 14, 1, -18)
			food.Parent = screenGui
			responsive(food)
		end

		local function refreshFood()
			local n = math.floor(tonumber(player:GetAttribute("FoodStock")) or 0)
			cnt.Text = string.format("x%d  Burgers", n)
			if n > 0 then
				fg.Color = ColorSequence.new(ORANGE_0, ORANGE_1)
				fs.Transparency = 0
				hint.Text = "[H] Eat • full energy"
			else
				fg.Color = ColorSequence.new(C.Gray, C.GrayDark)
				fs.Transparency = 0.5
				hint.Text = "Buy at the 🌙 Night Merchant"
			end
		end
		refreshFood()
		player:GetAttributeChangedSignal("FoodStock"):Connect(refreshFood)

		local lastEat = 0
		local function eat()
			if os.clock() - lastEat < 0.6 then return end
			lastEat = os.clock()
			local sc = food:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			sc.Parent = food
			;(sc :: UIScale).Scale = 0.92
			TweenService:Create(sc :: UIScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			playSound(Sounds.Click, 1.1)
			;(EatRemote :: RemoteEvent):FireServer()
		end
		food.Activated:Connect(eat)
		UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
			if gpe or UserInputService:GetFocusedTextBox() then return end
			if input.KeyCode == Enum.KeyCode.H then eat() end
		end)
	end
end

refreshAll()
print("✅ [ProgressionUI] Ready")
