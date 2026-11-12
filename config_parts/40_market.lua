
-- ============================================================================
-- 40. РЫНОК И ТОРГОВЕЦ ГОША (MarketBuilder + TraderAnimator)
-- Все цвета, размеры, дистанции, тайминги и тексты рынка — только здесь.
-- Координаты прилавка заданы относительно центра рынка:
-- +X вправо, +Z к покупателям (наружу), Y = 0 — верх земли.
-- ============================================================================
GameConfig.MARKET = {
	Seed = 4040,

	-- Имена и теги (на них опираются клиентский аниматор и скрипт магазина)
	ModelName = "MarketStall",
	NpcModelName = "TraderGosha",
	NpcTag = "TraderNPC",
	PromptTag = "TraderShopPrompt",

	-- Тексты
	TraderName = "Торговец Гоша",
	HintText = "[E] Открыть магазин",
	ActionText = "Открыть магазин",
	SignText = "РЫНОК",

	-- Подсказка (ProximityPrompt) и табличка над головой
	MaxActivationDistance = 12,
	TagMaxDistance = 60,
	PromptHeight = 3.9,
	PromptZ = 2.3,

	-- Анимация торговца (клиент)
	LookDistance = 40,          -- дальше этого расстояния голова смотрит прямо
	AnimateDistance = 90,       -- дальше — аниматор «спит»
	LookInterval = 0.35,        -- пересчёт взгляда, сек
	SleepInterval = 1,          -- проверка дистанции в режиме сна, сек
	LookTweenTime = 0.25,
	YawLimitDeg = 70,
	PitchLimitDeg = 25,
	SwayPeriod = 2.4,           -- полупериод покачивания, сек
	SwayRollDeg = 1.6,
	SwayPitchDeg = 1.1,
	WaveIntervalMin = 9,
	WaveIntervalMax = 18,
	WaveRaiseTime = 0.4,
	WaveSwingTime = 0.22,
	WaveLowerTime = 0.45,
	WaveSwingsMin = 2,
	WaveSwingsMax = 3,
	WaveForwardDeg = -20,       -- наклон поднятой руки вперёд
	WaveRaiseDeg = 150,         -- подъём руки в сторону
	WaveSwingDeg = 22,          -- размах кисти влево-вправо

	-- Прилавок
	Counter = {
		Width = 14,
		Depth = 3,
		Height = 3,
		TopThickness = 0.22,
		PlankCount = 14,
	},

	-- Опорные столбы (X — смещение от центра, Z — перед/зад)
	Pillars = {
		X = 7.7,
		FrontZ = 0.9,
		BackZ = -6.6,
		Size = 0.9,
	},

	-- Тент: перед выше нижним краем, к задней стене поднимается
	Roof = {
		FrontZ = 3.2,
		BackZ = -7.8,
		FrontY = 9.4,
		BackY = 10.65,
		HalfWidth = 9,
		Stripes = 12,
		Thickness = 0.25,
		RafterX = { -8.4, -4.2, 0, 4.2, 8.4 },
	},

	-- Гирлянда лампочек (света — только 3 штуки на всю гирлянду)
	Garland = {
		Count = 13,
		HalfSpan = 8.4,
		Y = 8.7,
		Sag = 1.0,
		Z = 3.5,
		SwagStep = 4,
		LightEvery = 4,
		LightOffset = 2,
	},

	-- Ковёр перед прилавком
	Carpet = {
		Width = 10,
		Depth = 7,
		ZCenter = 6.5,
		Thickness = 0.12,
	},

	-- Торговец: позиция относительно центра рынка (стоит за прилавком, лицом к +Z)
	Trader = {
		X = 0,
		Z = -3.4,
	},

	-- Свет (в сумме не больше 6 на рынок)
	Lights = {
		Lantern = { Brightness = 1.6, Range = 22 },
		Garland = { Brightness = 0.9, Range = 14 },
	},

	Colors = {
		-- Дерево
		WoodLight = Color3.fromRGB(184, 130, 78),
		WoodMid = Color3.fromRGB(146, 98, 56),
		WoodDark = Color3.fromRGB(98, 62, 36),
		WoodDeep = Color3.fromRGB(60, 38, 24),
		WoodTones = {
			Color3.fromRGB(176, 124, 74),
			Color3.fromRGB(150, 102, 60),
			Color3.fromRGB(128, 84, 48),
			Color3.fromRGB(164, 114, 68),
			Color3.fromRGB(112, 72, 42),
			Color3.fromRGB(190, 138, 86),
		},

		-- Тент
		AwningA = Color3.fromRGB(198, 52, 46),
		AwningB = Color3.fromRGB(246, 228, 194),

		-- Металл, камень, ткань
		Metal = Color3.fromRGB(88, 92, 100),
		MetalDark = Color3.fromRGB(48, 50, 56),
		Brass = Color3.fromRGB(206, 164, 70),
		Gold = Color3.fromRGB(255, 200, 60),
		Rope = Color3.fromRGB(198, 166, 110),
		Burlap = Color3.fromRGB(172, 136, 86),
		BurlapDark = Color3.fromRGB(128, 96, 58),
		Stone = Color3.fromRGB(104, 104, 110),
		StoneDark = Color3.fromRGB(70, 72, 80),

		-- Свет
		WarmLight = Color3.fromRGB(255, 176, 90),
		LanternGlass = Color3.fromRGB(255, 190, 100),
		Bulbs = {
			Color3.fromRGB(255, 224, 140),
			Color3.fromRGB(255, 176, 84),
			Color3.fromRGB(255, 236, 200),
			Color3.fromRGB(255, 140, 90),
		},

		-- Образцы руды
		GemGold = Color3.fromRGB(255, 200, 60),
		GemRuby = Color3.fromRGB(230, 40, 70),
		GemEmerald = Color3.fromRGB(50, 225, 120),
		GemDiamond = Color3.fromRGB(160, 240, 255),
		RockDark = Color3.fromRGB(70, 66, 74),

		-- Ковёр
		CarpetBase = Color3.fromRGB(138, 32, 44),
		CarpetBorder = Color3.fromRGB(226, 178, 70),
		CarpetInner = Color3.fromRGB(40, 66, 120),
		CarpetPattern = Color3.fromRGB(244, 214, 150),
		CarpetFringe = Color3.fromRGB(232, 214, 170),

		-- Товары на полках
		BookColors = {
			Color3.fromRGB(170, 48, 48),
			Color3.fromRGB(48, 96, 170),
			Color3.fromRGB(60, 130, 80),
			Color3.fromRGB(190, 150, 60),
			Color3.fromRGB(110, 60, 140),
			Color3.fromRGB(90, 70, 50),
		},
		ToolboxRed = Color3.fromRGB(200, 44, 40),
		BottleGlass = Color3.fromRGB(120, 170, 130),
		BottleBrown = Color3.fromRGB(120, 70, 40),
		Cork = Color3.fromRGB(190, 150, 100),
		TorchFire = Color3.fromRGB(255, 150, 50),
		PotionBlue = Color3.fromRGB(80, 160, 255),
		PotionPurple = Color3.fromRGB(190, 90, 255),
		PotionGreen = Color3.fromRGB(90, 240, 140),
		TopHat = Color3.fromRGB(28, 24, 30),
		Steel = Color3.fromRGB(150, 160, 172),
		Paper = Color3.fromRGB(236, 226, 196),

		-- Вывеска
		SignBoard = Color3.fromRGB(78, 48, 30),
		SignText = Color3.fromRGB(255, 214, 110),
		SignStroke = Color3.fromRGB(30, 18, 10),

		-- Торговец
		Skin = Color3.fromRGB(242, 196, 156),
		SkinShade = Color3.fromRGB(232, 150, 128),
		Shirt = Color3.fromRGB(238, 226, 200),
		Cuff = Color3.fromRGB(214, 200, 172),
		Apron = Color3.fromRGB(150, 98, 56),
		ApronDark = Color3.fromRGB(104, 66, 38),
		Trousers = Color3.fromRGB(66, 56, 74),
		Boots = Color3.fromRGB(46, 30, 24),
		Hat = Color3.fromRGB(32, 28, 36),
		HatTop = Color3.fromRGB(52, 46, 58),
		HatBand = Color3.fromRGB(186, 48, 52),
		Moustache = Color3.fromRGB(82, 54, 34),
		Hair = Color3.fromRGB(96, 64, 40),
		GlassesFrame = Color3.fromRGB(224, 184, 74),
		Lens = Color3.fromRGB(190, 225, 255),
		EyeWhite = Color3.fromRGB(250, 250, 250),
		Pupil = Color3.fromRGB(40, 30, 28),
		Mouth = Color3.fromRGB(132, 46, 46),
		Cheek = Color3.fromRGB(255, 150, 140),
		BowTie = Color3.fromRGB(190, 40, 52),

		-- Табличка над головой торговца
		TagBg = Color3.fromRGB(24, 18, 14),
		TagStroke = Color3.fromRGB(255, 200, 90),
		TagName = Color3.fromRGB(255, 222, 130),
		TagHint = Color3.fromRGB(236, 228, 210),
	},
}
