
-- ============================================================================
-- ============================================================================
-- v52: «СОЧНОЕ» ОБНОВЛЕНИЕ. ВСЕ НОВЫЕ ЦЕНЫ, ДЛИТЕЛЬНОСТИ И ЦВЕТА — НИЖЕ.
-- Цены кирок, рюкзаков и руды по-прежнему в разделах 6, 8 и 9 этого же файла.
-- ============================================================================
-- ============================================================================

-- ============================================================================
-- 12. РУССКИЕ НАЗВАНИЯ ДЛЯ НОВОГО ИНТЕРФЕЙСА (магазин, рюкзак, уведомления)
-- ============================================================================
GameConfig.RU_NAMES = {
	Ores = {
		Grass = "Трава", Dirt = "Земля", Clay = "Песок", Stone = "Камень", Coal = "Уголь",
		Iron = "Железная руда", Copper = "Магма", Tin = "Ледяной камень", Silver = "Серебряная руда",
		Gold = "Золотая руда", Amethyst = "Аметист", Ruby = "Рубин", Emerald = "Изумруд",
		Sapphire = "Обсидиан", Diamond = "Алмаз", Mithril = "Кристалл Бездны",
	} :: { [string]: string },
	Pickaxes = {
		"Деревянная кирка", "Каменная кирка", "Железная кирка", "Стальная кирка", "Сапфировая кирка",
		"Хрустальная кирка", "Аметистовая кирка", "Кирка Бездны", "Золотая кирка", "Королевская кирка",
	},
	Backpacks = {
		"Холщовый мешок", "Кожаный рюкзак", "Походный рюкзак", "Городской рюкзак", "Рюкзак «Авангард»",
		"Шахтёрский ящик", "Рюкзак «Полярная звезда»", "Кристальный рюкзак", "Вулканический рюкзак", "Звёздный рюкзак",
	},
}

function GameConfig.GetOreNameRu(oreId: string): string
	local info = GameConfig.BLOCK_TYPES[oreId]
	return GameConfig.RU_NAMES.Ores[oreId] or (info and info.Name) or oreId
end

-- ============================================================================
-- 13. ПАЛИТРА ИНТЕРФЕЙСА И РЕДКОСТИ
-- ============================================================================
GameConfig.UI = {
	BgTop = Color3.fromRGB(34, 38, 72),
	BgBottom = Color3.fromRGB(12, 13, 26),
	Panel = Color3.fromRGB(24, 27, 50),
	PanelLight = Color3.fromRGB(44, 50, 88),
	Slot = Color3.fromRGB(30, 34, 62),
	SlotEmpty = Color3.fromRGB(14, 15, 28),
	Text = Color3.fromRGB(242, 246, 255),
	TextDim = Color3.fromRGB(160, 172, 204),
	Gold = Color3.fromRGB(255, 205, 70),
	Green = Color3.fromRGB(80, 228, 128),
	GreenDark = Color3.fromRGB(26, 150, 78),
	Red = Color3.fromRGB(255, 84, 84),
	RedDark = Color3.fromRGB(170, 34, 44),
	Blue = Color3.fromRGB(70, 160, 255),
	BlueDark = Color3.fromRGB(34, 86, 190),
	Purple = Color3.fromRGB(176, 92, 255),
	Shine = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	FontBlack = Enum.Font.GothamBlack,
	FontTitle = Enum.Font.FredokaOne,
	FontMono = Enum.Font.RobotoMono,
	Corner = 14,
	OpenSeconds = 0.38,       -- плавное открытие окон (Back)
	CloseSeconds = 0.18,
	HoverScale = 1.06,        -- «поп» карточки при наведении
	ShineInterval = 2.8,      -- раз в N секунд по карточкам пробегает диагональный блик
	ShineSeconds = 0.75,
	ViewportSpinSeconds = 9,  -- полный оборот 3D-превью
	ToastSeconds = 2.6,
}

GameConfig.RARITY = {
	{ Id = "Common", Name = "ОБЫЧНАЯ", Color = Color3.fromRGB(168, 176, 188) },
	{ Id = "Uncommon", Name = "НЕОБЫЧНАЯ", Color = Color3.fromRGB(86, 206, 84) },
	{ Id = "Rare", Name = "РЕДКАЯ", Color = Color3.fromRGB(58, 150, 255) },
	{ Id = "Epic", Name = "ЭПИЧЕСКАЯ", Color = Color3.fromRGB(176, 92, 255) },
	{ Id = "Legendary", Name = "ЛЕГЕНДАРНАЯ", Color = Color3.fromRGB(255, 192, 36) },
}
-- Редкость (индекс в RARITY) для уровней 1..10 кирок и рюкзаков
GameConfig.TIER_RARITY = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5 }
-- Редкость руды по категории
GameConfig.ORE_CATEGORY_RARITY = { Common = 1, Rare = 3, Precious = 4, Relic = 5 } :: { [string]: number }

function GameConfig.GetTierRarity(level: number)
	local idx = GameConfig.TIER_RARITY[math.clamp(math.floor(level), 1, #GameConfig.TIER_RARITY)] or 1
	return GameConfig.RARITY[idx]
end

-- ============================================================================
-- 14. КИРКИ: НЕОН, КРИСТАЛЛ, СВЕТ, БЛЁСТКИ, ШЛЕЙФ (по уровням 1..10)
-- Цвет металла лезвия — BladeColor в PICKAXE_TIERS (раздел 8).
-- ============================================================================
export type PickaxeFxConfig = {
	Neon: Color3,          -- неоновая полоса на лезвии и шлейф взмаха
	Core: Color3,          -- светящийся кристалл в центре головы
	SparkleRate: number,   -- блёсток в секунду (ParticleEmitter, sparkles_main.dds)
	SparkleSize: number,
	LightRange: number,    -- PointLight малого радиуса
	LightBrightness: number,
	TrailWidth: number,    -- ширина шлейфа относительно длины лезвия (0..1)
	Epic: boolean,         -- топовые уровни: пульсация свечения и тяжёлые частицы
}

GameConfig.PICKAXE_FX = {
	[1]  = { Neon = Color3.fromRGB(255, 176, 64),  Core = Color3.fromRGB(255, 214, 120), SparkleRate = 2,  SparkleSize = 0.16, LightRange = 4,   LightBrightness = 0.35, TrailWidth = 0.55, Epic = false },
	[2]  = { Neon = Color3.fromRGB(196, 232, 255), Core = Color3.fromRGB(220, 244, 255), SparkleRate = 3,  SparkleSize = 0.17, LightRange = 4.5, LightBrightness = 0.45, TrailWidth = 0.60, Epic = false },
	[3]  = { Neon = Color3.fromRGB(92, 190, 255),  Core = Color3.fromRGB(150, 218, 255), SparkleRate = 4,  SparkleSize = 0.18, LightRange = 5,   LightBrightness = 0.60, TrailWidth = 0.65, Epic = false },
	[4]  = { Neon = Color3.fromRGB(64, 236, 214),  Core = Color3.fromRGB(150, 255, 236), SparkleRate = 5,  SparkleSize = 0.19, LightRange = 5.5, LightBrightness = 0.75, TrailWidth = 0.70, Epic = false },
	[5]  = { Neon = Color3.fromRGB(96, 186, 255),  Core = Color3.fromRGB(40, 110, 255),  SparkleRate = 7,  SparkleSize = 0.20, LightRange = 6,   LightBrightness = 0.90, TrailWidth = 0.75, Epic = false },
	[6]  = { Neon = Color3.fromRGB(170, 250, 255), Core = Color3.fromRGB(96, 226, 255),  SparkleRate = 9,  SparkleSize = 0.21, LightRange = 6.5, LightBrightness = 1.05, TrailWidth = 0.80, Epic = false },
	[7]  = { Neon = Color3.fromRGB(214, 140, 255), Core = Color3.fromRGB(176, 84, 255),  SparkleRate = 11, SparkleSize = 0.22, LightRange = 7,   LightBrightness = 1.20, TrailWidth = 0.85, Epic = false },
	[8]  = { Neon = Color3.fromRGB(255, 84, 232),  Core = Color3.fromRGB(150, 60, 255),  SparkleRate = 14, SparkleSize = 0.24, LightRange = 8,   LightBrightness = 1.45, TrailWidth = 0.90, Epic = true },
	[9]  = { Neon = Color3.fromRGB(255, 232, 120), Core = Color3.fromRGB(255, 176, 30),  SparkleRate = 18, SparkleSize = 0.26, LightRange = 9,   LightBrightness = 1.70, TrailWidth = 0.95, Epic = true },
	[10] = { Neon = Color3.fromRGB(255, 246, 190), Core = Color3.fromRGB(255, 120, 40),  SparkleRate = 24, SparkleSize = 0.30, LightRange = 10,  LightBrightness = 2.00, TrailWidth = 1.00, Epic = true },
} :: { [number]: PickaxeFxConfig }

GameConfig.PICKAXE_SWING_FX = {
	TrailSeconds = 0.34,       -- сколько шлейф включён после начала взмаха
	TrailLifetime = 0.16,
	ImpactSparks = 14,         -- искр цвета руды при ударе (Emit, без создания объектов)
	ImpactSparksEpic = 26,
	CameraShake = 0.10,        -- лёгкая тряска камеры при ударе (studs)
	PulseSeconds = 0.9,        -- период пульсации свечения топовых кирок
	PulseMin = 0.55,           -- доля яркости в нижней точке пульсации
	FxRange = 90,              -- дальше этого расстояния чужие эффекты не проигрываются
}

function GameConfig.GetPickaxeFx(level: number): PickaxeFxConfig
	return GameConfig.PICKAXE_FX[math.clamp(math.floor(level), 1, GameConfig.MAX_PICKAXE_LEVEL)] or GameConfig.PICKAXE_FX[1]
end

-- ============================================================================
-- 15. ЦИКЛ ДНЯ И НОЧИ (атрибуты ReplicatedStorage + workspace:GetServerTimeNow())
-- ============================================================================
GameConfig.PHASE = {
	DaySeconds = GameConfig.DAY_DURATION_SECONDS,
	NightSeconds = GameConfig.NIGHT_DURATION_SECONDS,
	EveningWarningSeconds = GameConfig.EVENING_WARNING_SECONDS,
	WarningSeconds = 10,          -- последние секунды фазы: таймер пульсирует предупреждающим цветом
	ZoneCheckInterval = 0.5,      -- как часто сервер ночью проверяет зону шахты
	ZoneWarnCooldown = 2.5,       -- не чаще, чем раз в N секунд показываем предупреждение нарушителю
	BlockRespawnDelay = 2.0,      -- через сколько секунд после наступления ночи восстанавливаются блоки
	TeleportSpread = Vector3.new(7, 0, 4), -- разброс точек на базе, чтобы игроки не стояли друг в друге
	LightingTweenSeconds = 3.0,   -- плавный переход освещения
	BannerSeconds = 4.5,
	-- Имена атрибутов ReplicatedStorage (читает клиент)
	AttrPhase = "Phase",          -- "Day" | "Night"
	AttrEndsAt = "PhaseEndsAt",   -- момент конца фазы в секундах workspace:GetServerTimeNow()
	AttrLength = "PhaseLength",   -- длительность текущей фазы, сек
}

-- Освещение фаз. Яркость и Ambient берутся из GameConfig.LIGHTING (раздел 3).
GameConfig.PHASE_LIGHTING = {
	Day = {
		ClockTime = 14,
		AtmosphereColor = Color3.fromRGB(185, 210, 240),
		AtmosphereDecay = Color3.fromRGB(95, 115, 145),
		AtmosphereDensity = 0.24,
		BloomIntensity = 0.48,
		BloomSize = 22,
		Tint = Color3.fromRGB(255, 255, 255),
	},
	Night = {
		ClockTime = 0,
		AtmosphereColor = Color3.fromRGB(70, 84, 150),
		AtmosphereDecay = Color3.fromRGB(22, 26, 56),
		AtmosphereDensity = 0.30,
		BloomIntensity = 0.95,
		BloomSize = 32,
		Tint = Color3.fromRGB(196, 206, 255),
	},
}

-- Карточка таймера и чипы бустов (правый нижний угол)
GameConfig.PHASE_HUD = {
	CardSize = Vector2.new(252, 96),
	ChipSize = Vector2.new(252, 46),
	ChipGap = 6,
	Margin = 14,
	TouchBottomInsetPhone = 124,   -- на телефоне карточка стоит над кнопками прыжка и бега
	TouchBottomInsetTablet = 228,
	Day = {
		Title = "ДЕНЬ", Sub = "до ночи", Icon = "☀️",
		Top = Color3.fromRGB(255, 182, 52), Bottom = Color3.fromRGB(226, 92, 24),
		Glow = Color3.fromRGB(255, 222, 120), Bar = Color3.fromRGB(255, 236, 150),
	},
	Night = {
		Title = "НОЧЬ", Sub = "до дня", Icon = "🌙",
		Top = Color3.fromRGB(92, 78, 224), Bottom = Color3.fromRGB(34, 22, 104),
		Glow = Color3.fromRGB(160, 150, 255), Bar = Color3.fromRGB(190, 180, 255),
	},
	Warning = Color3.fromRGB(255, 70, 70),
	StyleTweenSeconds = 0.8,
}

-- ============================================================================
-- 16. БУСТЫ ТОРГОВЦА (сервер хранит точное время конца, клиент только показывает)
-- ============================================================================
export type BoostConfig = {
	Id: string,
	Name: string,
	Icon: string,
	Desc: string,
	Stat: string,          -- "Luck" | "MineSpeed" | "Coins"
	Multiplier: number,
	Duration: number,      -- секунд за одну покупку (повторная покупка ПРОДЛЕВАЕТ буст)
	Price: number,
	Color: Color3,
	Rarity: number,
	InShop: boolean,       -- продаётся ли у торговца Гоши
}

GameConfig.BOOSTS = {
	Order = { "Luck", "Speed", "Coins", "Potion" },
	MaxSeconds = 3600,        -- больше часа буст не накапливается
	ExpireWarnSeconds = 10,   -- чип пульсирует, когда осталось меньше
	Items = {
		Luck = {
			Id = "Luck", Name = "Удача", Icon = "🍀", Desc = "Шанс бонусной руды ×2",
			Stat = "Luck", Multiplier = 2, Duration = 300, Price = 450,
			Color = Color3.fromRGB(86, 220, 110), Rarity = 2, InShop = true,
		},
		Speed = {
			Id = "Speed", Name = "Скорость", Icon = "⚡", Desc = "Кирка бьёт в 1.5 раза быстрее",
			Stat = "MineSpeed", Multiplier = 1.5, Duration = 300, Price = 600,
			Color = Color3.fromRGB(80, 190, 255), Rarity = 3, InShop = true,
		},
		Coins = {
			Id = "Coins", Name = "Монеты", Icon = "💰", Desc = "Продажа руды приносит ×2 монет",
			Stat = "Coins", Multiplier = 2, Duration = 300, Price = 900,
			Color = Color3.fromRGB(255, 200, 60), Rarity = 4, InShop = true,
		},
		-- Зелье Ночного торговца (существовало в v51 как атрибут SellBoostUntil) — теперь тоже буст с чипом
		Potion = {
			Id = "Potion", Name = "Зелье шахтёра", Icon = "🧪", Desc = "+25% монет при продаже",
			Stat = "Coins", Multiplier = 1.25, Duration = 180, Price = 150,
			Color = Color3.fromRGB(205, 100, 235), Rarity = 2, InShop = false,
		},
	} :: { [string]: BoostConfig },
}

-- ============================================================================
-- 17. МАГАЗИН И ОКНО РЮКЗАКА
-- ============================================================================
GameConfig.SHOP_UI = {
	MaxDistance = 20,          -- сервер: дальше от торговца покупка и продажа отклоняются
	AutoCloseDistance = 26,    -- клиент сам закрывает окно, если игрок ушёл
	ActionCooldown = 0.25,     -- сервер: минимальный интервал между действиями магазина
	WindowSize = Vector2.new(880, 580),
	CardSize = Vector2.new(198, 276),
	Tabs = {
		{ Id = "Pickaxes", Title = "Кирки", Icon = "⛏️", Color = Color3.fromRGB(255, 176, 64) },
		{ Id = "Backpacks", Title = "Рюкзаки", Icon = "🎒", Color = Color3.fromRGB(96, 200, 120) },
		{ Id = "Boosts", Title = "Бусты", Icon = "⚡", Color = Color3.fromRGB(110, 170, 255) },
		{ Id = "Sell", Title = "Продать руду", Icon = "💰", Color = Color3.fromRGB(255, 205, 70) },
	},
}

GameConfig.BACKPACK_UI = {
	WindowSize = Vector2.new(760, 540),
	SlotSize = Vector2.new(132, 158),
	MinSlots = 10,             -- сколько ячеек показывать минимум (пустые затемнены)
	WarnRatio = 0.7,           -- полоса вместимости желтеет
	FullRatio = 0.9,           -- полоса вместимости краснеет
	BarOk = Color3.fromRGB(80, 228, 128),
	BarWarn = Color3.fromRGB(255, 200, 60),
	BarFull = Color3.fromRGB(255, 84, 84),
	IconSpinSeconds = 12,      -- полный оборот 3D-иконки руды
}

-- ============================================================================
-- 18. ЗВУКИ НОВОГО ИНТЕРФЕЙСА И ЭФФЕКТОВ (только встроенные rbxasset://sounds/...)
-- ============================================================================
export type SfxConfig = { Id: string, Volume: number, Pitch: number }

GameConfig.SFX = {
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.45, Pitch = 1.0 },
	Tab = { Id = "rbxasset://sounds/switch.wav", Volume = 0.40, Pitch = 1.15 },
	Open = { Id = "rbxasset://sounds/switch.wav", Volume = 0.45, Pitch = 0.80 },
	Success = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Pitch = 1.20 },
	Error = { Id = "rbxasset://sounds/bass.wav", Volume = 0.50, Pitch = 0.90 },
	Swing = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.14, Pitch = 1.35 },
	Impact = { Id = "rbxasset://sounds/hit.wav", Volume = 0.16, Pitch = 1.50 },
	WallRumble = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.90, Pitch = 0.42 },
	WallSlam = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1.00, Pitch = 0.55 },
	PhaseBell = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Pitch = 0.60 },
} :: { [string]: SfxConfig }
