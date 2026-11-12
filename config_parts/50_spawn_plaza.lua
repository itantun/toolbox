-- ============================================================================
-- 🪨 v52: КАМЕННАЯ ПЛОЩАДЬ СПАВНА (SpawnPlazaBuilder)
-- Все размеры, цвета, материалы и количества деталей — здесь. Единицы — studs.
-- Земля: верх Y = 0. Площадь строго внутри Bounds; проходы остаются свободными.
-- ============================================================================
GameConfig.SPAWN_PLAZA = {
	Seed = 52017, -- Random.new(Seed): раскладка всегда одинаковая

	-- Границы площади и центр постамента (SpawnLocation)
	Bounds = { MinX = -17, MaxX = 17, MinZ = 13.5, MaxZ = 33 },
	Center = { X = 0, Z = 22 },

	-- Свободные проходы (для коллизионных деталей по периметру)
	Passages = {
		NorthHalfWidth = 6.5, -- север: X ∈ [−6.5; 6.5] (тропа в шахту)
		SouthHalfWidth = 8, -- юг: X ∈ [−8; 8] (к ночному торговцу)
		SideZMin = 18.5, -- запад/восток: Z ∈ [18.5; 27.5]
		SideZMax = 27.5,
		FreeRadius = 7, -- свободный круг вокруг центра
	},

	-- Тёмная подложка: щели между плитами читаются как чёрные трещины
	Plate = {
		TopY = 0.12,
		Thickness = 0.3,
		Color = Color3.fromRGB(14, 12, 20),
		Material = Enum.Material.Basalt,
	},
	CrevicePlateColor = Color3.fromRGB(14, 12, 20), -- цвет «срезанных» углов и трещин

	-- Низкий скошенный бордюр: с земли (Y = 0) на площадь без прыжка
	Border = {
		Width = 1.0,
		HeightMin = 0.22,
		HeightMax = 0.30,
		SegmentTarget = 2.8,
		SegmentJitter = 0.35,
		PathStripTop = 0.40, -- плоская вставка у тропы (тропа имеет верх Y ≈ 0.45)
		Material = Enum.Material.Cobblestone,
		Colors = {
			Color3.fromRGB(104, 98, 126),
			Color3.fromRGB(116, 109, 138),
			Color3.fromRGB(92, 86, 112),
		},
	},

	-- Плиты: ряды со случайной высотой ряда и независимыми колонками (кладка «вразбежку»)
	Slab = {
		RowTarget = 2.3,
		ColTarget = 2.7,
		RowJitter = 0.28,
		ColJitter = 0.30,
		GapMin = 0.22, -- зазор между плитами 0.2–0.4
		GapMax = 0.38,
		Thickness = 0.4,
		TopMin = 0.35, -- верх любой точки плиты: 0.34–0.50
		TopMax = 0.49,
		MaxTiltDeg = 1.2,
		MaxRise = 0.05, -- макс. перепад верха плиты от центра до угла
		MaxYawDeg = 2.0,
		ColorJitter = 0.06,
		MinSize = 0.9,
		Styles = {
			{
				Material = Enum.Material.Slate,
				Weight = 4,
				Colors = {
					Color3.fromRGB(128, 120, 150),
					Color3.fromRGB(116, 108, 138),
					Color3.fromRGB(140, 131, 162),
					Color3.fromRGB(104, 97, 128),
				},
			},
			{
				Material = Enum.Material.Rock,
				Weight = 3,
				Colors = {
					Color3.fromRGB(122, 114, 140),
					Color3.fromRGB(108, 102, 126),
					Color3.fromRGB(134, 126, 150),
				},
			},
			{
				Material = Enum.Material.Cobblestone,
				Weight = 3,
				Colors = {
					Color3.fromRGB(118, 110, 140),
					Color3.fromRGB(100, 94, 122),
					Color3.fromRGB(132, 124, 154),
				},
			},
			{
				Material = Enum.Material.Basalt,
				Weight = 1,
				Colors = {
					Color3.fromRGB(78, 73, 96),
					Color3.fromRGB(88, 82, 106),
				},
			},
			{
				Material = Enum.Material.Concrete,
				Weight = 2,
				Colors = {
					Color3.fromRGB(138, 130, 158),
					Color3.fromRGB(124, 117, 146),
					Color3.fromRGB(112, 105, 134),
				},
			},
		},
	},

	-- Мелкие детали на плитах (без коллизий)
	Details = {
		Lift = 0.017, -- подъём накладок над поверхностью плиты (против Z-fighting)
		ChamferCount = 32,
		ChamferSizeMin = 0.45,
		ChamferSizeMax = 0.95,
		CrackCount = 26,
		CrackThickness = 0.025,
		CrackWidth = 0.05,
		CrackColor = Color3.fromRGB(26, 22, 36),
		MossCreviceCount = 16,
		MossCornerCount = 12,
		MossColors = {
			Color3.fromRGB(78, 128, 62),
			Color3.fromRGB(96, 148, 70),
			Color3.fromRGB(60, 104, 56),
		},
		PebbleCount = 34,
		PebbleMin = 0.12,
		PebbleMax = 0.30,
		PebbleColors = {
			Color3.fromRGB(96, 90, 118),
			Color3.fromRGB(70, 66, 90),
			Color3.fromRGB(130, 123, 152),
		},
		RaisedCount = 8, -- небольшие выпуклые камни как на референсе
		RaisedBaseColor = Color3.fromRGB(100, 96, 130),
		RaisedCapColor = Color3.fromRGB(128, 124, 160),
	},

	-- Постамент спавна: врезанный тёмный камень + кольцо подогнанных камней
	Dais = {
		Size = 7,
		TopY = 0.52,
		Thickness = 0.5,
		Color = Color3.fromRGB(54, 50, 68),
		Material = Enum.Material.Slate,
		ChamferSize = 0.65,
		RingWidth = 2.5,
		RingTopMin = 0.44,
		RingTopMax = 0.50,
		RingTarget = 2.6,
		RingStyles = {
			{
				Material = Enum.Material.Slate,
				Weight = 3,
				Colors = {
					Color3.fromRGB(82, 77, 102),
					Color3.fromRGB(92, 86, 112),
					Color3.fromRGB(74, 70, 94),
				},
			},
			{
				Material = Enum.Material.Basalt,
				Weight = 2,
				Colors = {
					Color3.fromRGB(66, 62, 84),
					Color3.fromRGB(76, 71, 94),
				},
			},
		},
		GrooveColor = Color3.fromRGB(18, 16, 28),
		InlayColor = Color3.fromRGB(96, 160, 255),
		InlayTransparency = 0.3,
		OuterRingRadius = 2.7,
		OuterRingSegments = 20,
		InnerRingRadius = 1.35,
		InnerRingSegments = 12,
	},

	-- Каменные фонари: тёплый свет, не больше 6 источников
	Lanterns = {
		Positions = {
			{ X = -15.3, Z = 15.6 },
			{ X = 15.3, Z = 15.6 },
			{ X = -15.3, Z = 31.4 },
			{ X = 15.3, Z = 31.4 },
			{ X = -7.7, Z = 15.4 },
			{ X = 7.7, Z = 15.4 },
		},
		BaseY = 0.3,
		StoneColor = Color3.fromRGB(96, 90, 116),
		StoneDarkColor = Color3.fromRGB(70, 66, 90),
		StoneMaterial = Enum.Material.Slate,
		CoreColor = Color3.fromRGB(255, 190, 110),
		LightColor = Color3.fromRGB(255, 176, 92),
		LightBrightness = 1.1,
		LightRange = 15,
		Radius = 0.7, -- запас на габарит при проверке проходов
	},

	-- Валуны: кластеры из 2–4 повёрнутых блоков/клиньев/эллипсоидов (с коллизией)
	Boulders = {
		Clusters = 9,
		MainSizeMin = 1.2,
		MainSizeMax = 2.3,
		EdgeInsetMin = 0.5,
		EdgeInsetMax = 2.2,
		Materials = { Enum.Material.Slate, Enum.Material.Rock, Enum.Material.Basalt, Enum.Material.Cobblestone },
		Colors = {
			Color3.fromRGB(84, 79, 104),
			Color3.fromRGB(98, 92, 120),
			Color3.fromRGB(72, 68, 90),
			Color3.fromRGB(110, 104, 132),
		},
	},

	-- Кристаллы: 3–6 наклонных призм на кластер; свет по умолчанию выключен (лимит 6 на постройку)
	Crystals = {
		Clusters = 4,
		PerClusterMin = 3,
		PerClusterMax = 6,
		LengthMin = 0.9,
		LengthMax = 2.0,
		WidthMin = 0.22,
		WidthMax = 0.40,
		MaxTiltDeg = 24,
		Radius = 1.2,
		LightCount = 0,
		LightBrightness = 0.6,
		LightRange = 8,
		BaseColor = Color3.fromRGB(46, 42, 62),
		Palettes = {
			Color3.fromRGB(80, 215, 255),
			Color3.fromRGB(170, 110, 255),
		},
		GlassTransparency = 0.22,
	},

	EdgeMargin = 0.25, -- отступ деталей периметра от границ области
}
