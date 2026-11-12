-- ============================================================================
-- v52: НОЧНАЯ СТЕНА У ВХОДА В ШАХТУ («БОЛЬШАЯ ШТУКА») И ЕЁ ЗАБОР-ПЕРИМЕТР.
-- Все размеры (studs), цвета, свет, время подъёма и тексты — здесь.
-- Мировые координаты: земля Y = 0, +Z — к спавну, −Z — к шахте.
-- ============================================================================
GameConfig.NIGHT_WALL = {
	Name = "NightMineWall",
	Seed = 5205,

	-- Габариты подвижной стены (в поднятом положении)
	CenterX = 0,
	CenterZ = -15.6,
	Width = 30,
	Thickness = 3,
	Height = 18,
	SinkDepth = 23.5, -- на сколько стена уходит вниз (кончики шипов остаются ниже Y = -1.5)
	LiftSeconds = 2.6, -- длительность подъёма/опускания (анимацию играет клиент)

	-- Слои монолита
	PlinthHeight = 2.5,
	SkirtHeight = 1.0,
	SkirtWidth = 30.6,
	SkirtThickness = 3.8,
	BodyWidth = 24,
	BodyThickness = 2.8,
	CapHeight = 1.2,
	ButtressWidth = 3,

	-- Шипы по верху
	SpikeCount = 13,
	SpikeMinHeight = 1.6,
	SpikeMaxHeight = 3.5,

	-- Табличка с текстом (на каждой стороне)
	PanelSize = Vector2.new(21, 10.5),
	PanelCenterY = 0.3, -- относительно центра стены
	PanelThickness = 0.2,

	Colors = {
		Basalt = Color3.fromRGB(30, 26, 38),
		BasaltDark = Color3.fromRGB(20, 17, 26),
		Slate = Color3.fromRGB(42, 37, 52),
		SlateLight = Color3.fromRGB(54, 48, 66),
		Rock = Color3.fromRGB(26, 22, 31),
		Spike = Color3.fromRGB(24, 20, 30),
		Panel = Color3.fromRGB(12, 9, 16),
		Rune = Color3.fromRGB(255, 40, 40),
	},

	-- Красные огни (не более 4)
	Light = {
		Color = Color3.fromRGB(255, 50, 40),
		Brightness = 2.4,
		Range = 26,
	},

	-- Дым по верху стены (маленький Rate — экономим частицы)
	Smoke = {
		Rate = 5,
		Color1 = Color3.fromRGB(90, 30, 34),
		Color2 = Color3.fromRGB(48, 44, 52),
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(1, 2.2),
		SizeStart = 2.2,
		SizeEnd = 6,
		Transparency = 0.6,
	},

	-- Пыль у основания (клиент вызывает :Emit() при подъёме/опускании)
	Dust = {
		Color1 = Color3.fromRGB(150, 140, 126),
		Color2 = Color3.fromRGB(110, 104, 98),
		Height = 0.6,
		Y = 0.3,
		Lifetime = NumberRange.new(1.8, 3),
		Speed = NumberRange.new(4, 9),
		SizeStart = 5,
		SizeEnd = 13,
		Transparency = 0.45,
	},

	-- Надписи на обеих сторонах
	Gui = {
		PixelsPerStud = 24,
		Brightness = 1.6,
		BackdropColor = Color3.fromRGB(10, 6, 14),
		BackdropTransparency = 0.2,
		StrokeColor = Color3.fromRGB(255, 50, 50),
		StrokeThickness = 5,
		CornerRadius = 22,
		TextStrokeColor = Color3.fromRGB(0, 0, 0),
		Font = Enum.Font.GothamBlack,
		Title = "🌙 НОЧЬ",
		TitleColor = Color3.fromRGB(190, 170, 255),
		Subtitle = "ШАХТА ЗАКРЫТА",
		SubtitleColor = Color3.fromRGB(255, 70, 70),
		Countdown = "Откроется через: 0:00",
		CountdownColor = Color3.fromRGB(255, 214, 120),
		Hint = "Возвращайся утром!",
		HintColor = Color3.fromRGB(235, 235, 245),
	},

	-- Периметр карьера (невидимые блокировщики; Высота берётся из GameConfig.WALL_HEIGHT)
	Perimeter = {
		Thickness = 2,
		WestX = -63.5,
		EastX = 63.5,
		NorthZ = -141.5,
		GateHalfWidth = 15, -- проём, который закрывает сама стена
	},

	-- Видимый забор вдоль периметра: красные энергопанели и базальтовые столбы
	Fence = {
		PanelHeight = 12,
		PanelThickness = 0.3,
		PanelColor = Color3.fromRGB(255, 40, 50),
		PanelMaterial = Enum.Material.ForceField,
		FenceTransparency = 0.45, -- ночью; днём панели полностью прозрачны
		PostSpacing = 18,
		PostHeight = 15,
		PostWidth = 1.6,
		PostColor = Color3.fromRGB(28, 24, 34),
		CapSize = Vector3.new(1.1, 0.6, 1.1),
		CapDayColor = Color3.fromRGB(70, 22, 26),
		CapNightColor = Color3.fromRGB(255, 45, 45),
	},
}
