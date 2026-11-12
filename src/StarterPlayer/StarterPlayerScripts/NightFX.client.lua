--!strict
-- ============================================================================
-- 🌙 КЛИЕНТ: NightFX (StarterPlayerScripts.NightFX)
-- v52: всё, что игрок ВИДИТ при смене дня и ночи.
--   • Небо идёт вместе с фазой: днём солнце проходит путь от утра до вечера, ночная фаза
--     всегда под ночным небом, рассвет наступает с открытием шахты.
--   • Плавный переход освещения: Bloom, оттенок цветокоррекции и «доля ночи»
--     Lighting.NightBlend (по ней ClientController смешивает яркость, Ambient и атмосферу).
--   • Баннеры: «🌙 НОЧЬ НАСТУПИЛА — вы на базе», «☀️ ШАХТА ОТКРЫТА», предупреждение нарушителю.
--   • Большая стена у входа в шахту: подъём и опускание за 2–3 секунды, гул, пыль у
--     основания, лёгкая тряска камеры у тех, кто рядом, пульсирующие красные руны.
--   • Живой обратный отсчёт «Откроется через: 0:42» на обеих сторонах стены.
-- Состояние задаёт сервер: атрибуты ReplicatedStorage (Phase, PhaseEndsAt) и атрибут
-- Raised у модели стены. Клиент только анимирует. Покадровых циклов нет: твины и
-- редкие task.wait; отсчёт идёт только ночью.
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
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

local NightNotice = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("NightNotice") :: RemoteEvent

local UI = GameConfig.UI
local P = GameConfig.PHASE
local FX = GameConfig.NIGHT_FX
local PL = GameConfig.PHASE_LIGHTING
local rng = Random.new()

local function isNightPhase(): boolean
	return ReplicatedStorage:GetAttribute(P.AttrPhase) == "Night"
end

-- ---------------------------------------------------------------------------
-- 1. Освещение: доля ночи 0..1 в Lighting.NightBlend + небо, Bloom, оттенок
-- ---------------------------------------------------------------------------
local existingBlend = Lighting:FindFirstChild("NightBlend")
local blend: NumberValue
if existingBlend and existingBlend:IsA("NumberValue") then
	blend = existingBlend
else
	local created = Instance.new("NumberValue")
	created.Name = "NightBlend"
	created.Parent = Lighting
	blend = created
end

local BlendTween: Tween? = nil

-- Доля ночи 0..1 управляет Bloom и оттенком картинки (яркость, Ambient и атмосферу по ней же
-- смешивает ClientController)
local function applyBlend(b: number)
	local bloom = Lighting:FindFirstChild("NeonBloom")
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = PL.Day.BloomIntensity + (PL.Night.BloomIntensity - PL.Day.BloomIntensity) * b
		bloom.Size = PL.Day.BloomSize + (PL.Night.BloomSize - PL.Day.BloomSize) * b
	end
	local cc = Lighting:FindFirstChild("ModernColorCorrection")
	if cc and cc:IsA("ColorCorrectionEffect") then
		cc.TintColor = PL.Day.Tint:Lerp(PL.Night.Tint, b)
	end
end
blend.Changed:Connect(applyBlend)

local function setLighting(night: boolean, instant: boolean)
	if BlendTween then
		BlendTween:Cancel()
		BlendTween = nil
	end
	local target = night and 1 or 0
	if instant then
		blend.Value = target
		applyBlend(target)
		return
	end
	local tw = TweenService:Create(blend, TweenInfo.new(P.LightingTweenSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = target })
	BlendTween = tw
	tw:Play()
end

-- Часы неба идут вместе с фазой: день — от утра (ClockStart) до вечера (ClockEnd), ночная фаза —
-- всегда под ночным небом (21:00 -> 04:00), рассвет приходит с открытием шахты. Движение — это
-- несколько длинных линейных твинов Lighting.ClockTime на фазу, без покадрового кода.
local SkyToken = 0
local SkyTween: Tween? = nil

-- Ведёт часы вперёд до toHours (значение больше 24 означает «после полуночи») за seconds секунд.
-- Возвращает false, если за это время фаза сменилась.
local function advanceClock(toHours: number, seconds: number, token: number): boolean
	local function tweenTo(target: number, duration: number)
		local tw = TweenService:Create(Lighting, TweenInfo.new(duration, Enum.EasingStyle.Linear), { ClockTime = target })
		SkyTween = tw
		tw:Play()
		task.wait(duration)
	end
	local from = Lighting.ClockTime
	local to = toHours % 24
	if seconds <= 0.05 then
		Lighting.ClockTime = to
	elseif to >= from or (from - to) < 1 then
		tweenTo(to, seconds)
	else
		-- путь лежит через полночь: до 24:00, затем с 00:00
		local total = (24 - from) + to
		local first = seconds * (24 - from) / total
		tweenTo(23.99, first)
		if token ~= SkyToken then
			return false
		end
		Lighting.ClockTime = 0
		tweenTo(to, seconds - first)
	end
	return token == SkyToken
end

local function runSky(phase: string, instant: boolean)
	SkyToken += 1
	local token = SkyToken
	if SkyTween then
		SkyTween:Cancel()
		SkyTween = nil
	end
	local endsAt = ReplicatedStorage:GetAttribute(P.AttrEndsAt)
	local length = ReplicatedStorage:GetAttribute(P.AttrLength)
	if type(endsAt) ~= "number" or type(length) ~= "number" then
		return
	end
	local cfg = phase == "Night" and PL.Night or PL.Day
	-- положение часов неба в момент серверного времени t
	local function clockAt(t: number): number
		local frac = math.clamp(1 - (endsAt - t) / math.max(1, length), 0, 1)
		return cfg.ClockStart + (cfg.ClockEnd - cfg.ClockStart) * frac
	end
	task.spawn(function()
		local now = Workspace:GetServerTimeNow()
		if instant then
			Lighting.ClockTime = clockAt(now) % 24
		else
			-- смена фазы: закат или рассвет «прокручивается» за время перехода освещения
			local lead = math.clamp(endsAt - now, 0, P.LightingTweenSeconds)
			if not advanceClock(clockAt(now + lead), lead, token) then
				return
			end
		end
		local remaining = endsAt - Workspace:GetServerTimeNow()
		if remaining > 0.1 then
			advanceClock(cfg.ClockEnd, remaining, token)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- 2. Баннер сверху по центру
-- ---------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "NightFxV52"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 25
gui.Parent = playerGui

local banner = UIKit.Frame(gui, "Banner", UDim2.fromOffset(600, 92), UDim2.new(0.5, 0, 0, -140), Color3.new(1, 1, 1))
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Visible = false
UIKit.Corner(banner, 22)
local bannerGrad = UIKit.Gradient(banner, UI.BgTop, UI.BgBottom, 90)
local bannerStroke = UIKit.Stroke(banner, UI.Gold, 3.5)
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner
local bannerGloss = UIKit.Frame(banner, "Gloss", UDim2.new(1, -16, 0.4, 0), UDim2.fromOffset(8, 5), Color3.new(1, 1, 1), 0.88)
UIKit.Corner(bannerGloss, 16)
local bannerTitle = UIKit.Label(banner, {
	Name = "Title", Size = UDim2.new(1, -28, 0, 40), Position = UDim2.fromOffset(14, 10),
	Font = UI.FontBlack, TextSize = 27, Scaled = true, Stroke = true, ZIndex = 2,
})
local titleLimit = Instance.new("UITextSizeConstraint")
titleLimit.MaxTextSize = 28
titleLimit.Parent = bannerTitle
local bannerSub = UIKit.Label(banner, {
	Name = "Sub", Size = UDim2.new(1, -28, 0, 26), Position = UDim2.fromOffset(14, 54),
	TextSize = 16, Color = Color3.fromRGB(240, 240, 255), Scaled = true, ZIndex = 2,
})
local subLimit = Instance.new("UITextSizeConstraint")
subLimit.MaxTextSize = 17
subLimit.Parent = bannerSub
local bannerShine = UIKit.AddShine(banner, 22, 3)

local BannerToken = 0

local function showBanner(kind: string, subOverride: string?)
	local cfg = (FX.Banners :: any)[kind]
	if not cfg then
		return
	end
	BannerToken += 1
	local token = BannerToken
	bannerTitle.Text = cfg.Title
	bannerSub.Text = subOverride or cfg.Sub
	bannerGrad.Color = ColorSequence.new(cfg.Top, cfg.Bottom)
	bannerStroke.Color = cfg.Stroke
	bannerScale.Scale = math.clamp(UIKit.ViewportSize().X / 660, 0.5, 1.1)
	banner.Position = UDim2.new(0.5, 0, 0, -140)
	banner.Visible = true
	TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 162),
	}):Play()
	UIKit.PlayShine(bannerShine, 0.35)
	task.delay(P.BannerSeconds, function()
		if token ~= BannerToken then
			return
		end
		local out = TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -140),
		})
		out:Play()
		out.Completed:Wait()
		if token == BannerToken then
			banner.Visible = false
		end
	end)
end

-- ---------------------------------------------------------------------------
-- 3. Стена у входа в шахту: анимация, пыль, гул, тряска, руны
-- ---------------------------------------------------------------------------
local Wall: Model? = nil
local WallToken = 0
local RuneTweens: { Tween } = {}
local LidTweens: { Tween } = {}
local RumbleSound: Sound? = nil
local SlamSound: Sound? = nil

local function wallSound(parent: Instance, key: string, existing: Sound?): Sound?
	if existing and existing.Parent then
		return existing
	end
	local cfg = GameConfig.SFX[key]
	if not cfg then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "V52_" .. key
	s.SoundId = cfg.Id
	s.Volume = cfg.Volume
	s.PlaybackSpeed = cfg.Pitch
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 220
	s.Parent = parent
	return s
end

local function setRunesPulsing(on: boolean)
	UIKit.StopTweens(RuneTweens)
	for _, rune in ipairs(CollectionService:GetTagged("NightWallRune")) do
		if rune:IsA("BasePart") then
			if on then
				rune.Color = FX.RuneDim
				local tw = TweenService:Create(
					rune,
					TweenInfo.new(FX.RunePulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, rng:NextNumber(0, 0.3)),
					{ Color = FX.RuneBright }
				)
				tw:Play()
				table.insert(RuneTweens, tw)
			else
				rune.Color = FX.RuneDim
			end
		end
	end
end

-- Лёгкая тряска камеры через Humanoid.CameraOffset (только на время движения стены и только рядом)
local function shakeNearWall(wallPos: Vector3, seconds: number, token: number)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds and token == WallToken do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") then
				local dist = (root.Position - wallPos).Magnitude
				local k = math.clamp(1 - dist / FX.ShakeDistance, 0, 1) * FX.ShakeStrength
				if k > 0.01 then
					TweenService:Create(hum, TweenInfo.new(0.07, Enum.EasingStyle.Linear), {
						CameraOffset = Vector3.new(rng:NextNumber(-k, k), rng:NextNumber(-k, k), 0),
					}):Play()
				end
			end
			task.wait(0.08)
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			TweenService:Create(hum, TweenInfo.new(0.2), { CameraOffset = Vector3.zero }):Play()
		end
	end)
end

-- Крышка над карьером: плиты проявляются волной от входа (сервер позже фиксирует итог)
local function setLidVisible(visible: boolean, instant: boolean)
	UIKit.StopTweens(LidTweens)
	local target = visible and 0 or 1
	for _, part in ipairs(CollectionService:GetTagged("NightWallLid")) do
		if part:IsA("BasePart") then
			if instant then
				part.Transparency = target
			else
				local delay = tonumber(part:GetAttribute("FadeDelay")) or 0
				local tw = TweenService:Create(
					part,
					TweenInfo.new(FX.LidFadeSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, delay),
					{ Transparency = target }
				)
				tw:Play()
				table.insert(LidTweens, tw)
			end
		end
	end
end

local function wallPoses(wall: Model): (BasePart?, CFrame?, CFrame?)
	local root = wall.PrimaryPart or wall:FindFirstChild("Root")
	local up = wall:GetAttribute("UpCFrame")
	local down = wall:GetAttribute("DownCFrame")
	if root and root:IsA("BasePart") and typeof(up) == "CFrame" and typeof(down) == "CFrame" then
		return root, up, down
	end
	return nil, nil, nil
end

local function animateWall(wall: Model, raised: boolean, instant: boolean)
	WallToken += 1
	local token = WallToken
	local root, up, down = wallPoses(wall)
	if not root or not up or not down then
		return
	end
	local target = raised and up or down
	setRunesPulsing(raised)
	setLidVisible(raised, instant)
	if instant then
		root.CFrame = target
		return
	end

	local seconds = tonumber(wall:GetAttribute("LiftSeconds")) or 2.6
	local info = raised
		and TweenInfo.new(seconds, FX.RiseEasing, Enum.EasingDirection.Out)
		or TweenInfo.new(seconds, FX.LowerEasing, Enum.EasingDirection.In)
	TweenService:Create(root, info, { CFrame = target }):Play()

	-- пыль у основания: залп в начале и поток на время движения
	local dust: { ParticleEmitter } = {}
	for _, e in ipairs(CollectionService:GetTagged("NightWallDust")) do
		if e:IsA("ParticleEmitter") and e:IsDescendantOf(wall.Parent or Workspace) then
			e:Emit(FX.DustBurst)
			e.Enabled = true
			table.insert(dust, e)
		end
	end

	-- гул и финальный удар (звук идёт от стены и затухает с расстоянием)
	local soundHost = wall:FindFirstChild("DustBase", true) or root
	RumbleSound = wallSound(soundHost, "WallRumble", RumbleSound)
	SlamSound = wallSound(soundHost, "WallSlam", SlamSound)
	if RumbleSound then
		RumbleSound:Play()
	end
	shakeNearWall(up.Position, seconds, token)

	task.delay(seconds, function()
		for _, e in ipairs(dust) do
			if e.Parent then
				e.Enabled = false
			end
		end
		if token ~= WallToken then
			return
		end
		if SlamSound then
			SlamSound:Play()
		end
		for _, e in ipairs(dust) do
			if e.Parent then
				e:Emit(math.floor(FX.DustBurst / 2))
			end
		end
	end)
end

local function hookWall(inst: Instance)
	if not inst:IsA("Model") or Wall == inst then
		return
	end
	Wall = inst
	-- при входе в игру стена сразу встаёт в правильную позу (без анимации)
	task.defer(function()
		animateWall(inst, inst:GetAttribute("Raised") == true, true)
	end)
	inst:GetAttributeChangedSignal("Raised"):Connect(function()
		animateWall(inst, inst:GetAttribute("Raised") == true, false)
	end)
end
for _, inst in ipairs(CollectionService:GetTagged("NightMineWall")) do
	hookWall(inst)
end
CollectionService:GetInstanceAddedSignal("NightMineWall"):Connect(hookWall)
-- руны могут прогрузиться позже самой модели — подхватываем их в текущем состоянии
CollectionService:GetInstanceAddedSignal("NightWallRune"):Connect(function(rune: Instance)
	local wall = Wall
	if wall and wall:GetAttribute("Raised") == true and rune:IsA("BasePart") then
		local tw = TweenService:Create(
			rune,
			TweenInfo.new(FX.RunePulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Color = FX.RuneBright }
		)
		tw:Play()
		table.insert(RuneTweens, tw)
	end
end)

-- ---------------------------------------------------------------------------
-- 4. Обратный отсчёт на стене (только ночью, 4 раза в секунду)
-- ---------------------------------------------------------------------------
local CountdownToken = 0

local function runCountdown()
	CountdownToken += 1
	local token = CountdownToken
	task.spawn(function()
		local lastText = ""
		while token == CountdownToken and isNightPhase() do
			local endsAt = ReplicatedStorage:GetAttribute(P.AttrEndsAt)
			local remaining = (type(endsAt) == "number") and math.max(0, endsAt - Workspace:GetServerTimeNow()) or 0
			local text = FX.CountdownPrefix .. UIKit.FormatTime(remaining, false)
			if text ~= lastText then
				lastText = text
				for _, lbl in ipairs(CollectionService:GetTagged("NightWallCountdown")) do
					if lbl:IsA("TextLabel") then
						lbl.Text = text
					end
				end
			end
			task.wait(0.25)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- 5. Реакция на фазу и уведомления сервера
-- ---------------------------------------------------------------------------
local PhaseKnown = false

local function onPhaseChanged()
	local phase = ReplicatedStorage:GetAttribute(P.AttrPhase)
	if type(phase) ~= "string" then
		return
	end
	local night = phase == "Night"
	local first = not PhaseKnown
	PhaseKnown = true
	setLighting(night, first)
	runSky(phase, first)
	if night then
		runCountdown()
		if first then
			showBanner("NightJoin") -- игрок зашёл посреди ночи
		end
	else
		CountdownToken += 1
	end
end
ReplicatedStorage:GetAttributeChangedSignal(P.AttrPhase):Connect(onPhaseChanged)
onPhaseChanged()

NightNotice.OnClientEvent:Connect(function(kind: any, veinCount: any, veinList: any)
	if kind == "Night" then
		showBanner("Night")
		UIKit.PlaySfx("PhaseBell")
	elseif kind == "Day" then
		local count = tonumber(veinCount) or 0
		if count > 0 then
			showBanner("Day", string.format("Утренние жилы ×3 💰: %d (%s)", count, tostring(veinList)))
		else
			showBanner("Day")
		end
		UIKit.PlaySfx("PhaseBell")
	elseif kind == "ZoneWarn" then
		showBanner("ZoneWarn")
		UIKit.PlaySfx("Error")
	end
end)
