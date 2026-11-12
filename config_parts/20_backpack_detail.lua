
-- ============================================================================
-- 19. ДЕТАЛИЗАЦИЯ РЮКЗАКОВ (швы, пряжки, фонарь, кристаллы, эмблемы) — модуль BackpackDetailer
-- Все цвета и размеры отделки живут здесь; в модуле нет «зашитых» значений.
-- ============================================================================
export type BackpackDetailLevelCfg = {
	Metal: Color3,           -- металл: пряжки, кольца, уголки
	Accent: Color3,          -- главный акцент уровня (верёвка, латунь, золото, стекло, магма)
	Accent2: Color3,         -- второй акцент (кожа, пластины, тёмный фиолет)
	Glow: Color3,            -- цвет свечения (линза, кристаллы, неон)
	Glow2: Color3,           -- запасной цвет свечения (звёздочки, искры)
	Cloth: Color3,           -- ткань заплат, ремешков и тёмных рёбер
	Thread: Color3,          -- нить швов
	Count: number,           -- число кристаллов / осколков / ответвлений трещин / звёздочек
	LightBrightness: number, -- яркость источника света (только на персонаже)
	LightRange: number,      -- дальность источника света
	EmitRate: number,        -- частота частиц в секунду (0 — без частиц)
	Shine: number,           -- блеск металла и стекла (Reflectance)
}

GameConfig.BACKPACK_DETAIL_SHARED = {
	Seed = 5200,        -- Random.new(Seed + уровень): раскладка стабильна
	MaxParts = 45,      -- максимум дополнительных деталей на рюкзак
	MaxLights = 2,      -- максимум источников света на рюкзак
	MaxEmitters = 2,    -- максимум излучателей частиц на рюкзак
	Lift = 0.015,       -- подъём детали над поверхностью (в долях масштаба)
	StitchDash = 0.11,  -- длина одного стежка
	StitchPerRow = 5,   -- стежков в ряду
	ScuffCount = 3,     -- число потёртостей
	WaistLimit = 0.44,  -- ниже CenterY − Height × значение детали не ставятся
}

GameConfig.BACKPACK_DETAIL = {
	-- 1. Холщовый мешок: верёвка и заплата
	[1] = {
		Metal = Color3.fromRGB(198, 202, 210), Accent = Color3.fromRGB(196, 164, 110), Accent2 = Color3.fromRGB(150, 112, 66),
		Glow = Color3.fromRGB(255, 214, 140), Glow2 = Color3.fromRGB(255, 236, 190), Cloth = Color3.fromRGB(122, 92, 56),
		Thread = Color3.fromRGB(232, 212, 166), Count = 0, LightBrightness = 0, LightRange = 0, EmitRate = 0, Shine = 0.1,
	},
	-- 2. Кожаный рюкзак: латунные пряжки, заклёпки
	[2] = {
		Metal = Color3.fromRGB(214, 170, 70), Accent = Color3.fromRGB(214, 170, 70), Accent2 = Color3.fromRGB(120, 70, 36),
		Glow = Color3.fromRGB(255, 214, 140), Glow2 = Color3.fromRGB(255, 236, 190), Cloth = Color3.fromRGB(92, 52, 30),
		Thread = Color3.fromRGB(230, 196, 150), Count = 0, LightBrightness = 0, LightRange = 0, EmitRate = 0, Shine = 0.25,
	},
	-- 3. Походный рюкзак: скатка, фонарик, карабин
	[3] = {
		Metal = Color3.fromRGB(186, 190, 180), Accent = Color3.fromRGB(64, 72, 36), Accent2 = Color3.fromRGB(58, 60, 64),
		Glow = Color3.fromRGB(255, 244, 200), Glow2 = Color3.fromRGB(255, 250, 225), Cloth = Color3.fromRGB(58, 66, 32),
		Thread = Color3.fromRGB(208, 208, 160), Count = 0, LightBrightness = 1.4, LightRange = 16, EmitRate = 0, Shine = 0.25,
	},
	-- 4. Городской рюкзак: бегунки, светоотражающая лента, шильдик
	[4] = {
		Metal = Color3.fromRGB(178, 184, 194), Accent = Color3.fromRGB(150, 156, 166), Accent2 = Color3.fromRGB(88, 92, 102),
		Glow = Color3.fromRGB(170, 182, 196), Glow2 = Color3.fromRGB(220, 230, 240), Cloth = Color3.fromRGB(30, 32, 38),
		Thread = Color3.fromRGB(88, 92, 102), Count = 0, LightBrightness = 0, LightRange = 0, EmitRate = 0, Shine = 0.3,
	},
	-- 5. «Авангард»: уголки и светящиеся боковые полосы
	[5] = {
		Metal = Color3.fromRGB(196, 202, 212), Accent = Color3.fromRGB(230, 236, 250), Accent2 = Color3.fromRGB(22, 70, 160),
		Glow = Color3.fromRGB(246, 249, 255), Glow2 = Color3.fromRGB(150, 200, 255), Cloth = Color3.fromRGB(16, 48, 120),
		Thread = Color3.fromRGB(70, 140, 245), Count = 0, LightBrightness = 0.5, LightRange = 5, EmitRate = 0, Shine = 0.3,
	},
	-- 6. Шахтёрский ящик: клёпаные пластины, кристаллы, шахтёрская лампа
	[6] = {
		Metal = Color3.fromRGB(134, 138, 146), Accent = Color3.fromRGB(255, 190, 80), Accent2 = Color3.fromRGB(70, 72, 80),
		Glow = Color3.fromRGB(80, 220, 255), Glow2 = Color3.fromRGB(140, 255, 200), Cloth = Color3.fromRGB(40, 42, 46),
		Thread = Color3.fromRGB(88, 92, 100), Count = 3, LightBrightness = 1.6, LightRange = 12, EmitRate = 0, Shine = 0.3,
	},
	-- 7. «Полярная звезда»: золотой звёздный акцент
	[7] = {
		Metal = Color3.fromRGB(204, 210, 220), Accent = Color3.fromRGB(255, 205, 70), Accent2 = Color3.fromRGB(230, 236, 242),
		Glow = Color3.fromRGB(40, 150, 255), Glow2 = Color3.fromRGB(120, 200, 255), Cloth = Color3.fromRGB(172, 178, 188),
		Thread = Color3.fromRGB(172, 178, 188), Count = 2, LightBrightness = 0.6, LightRange = 6, EmitRate = 0, Shine = 0.3,
	},
	-- 8. Кристальный «Корона»: стеклянные пластины и внутреннее свечение
	[8] = {
		Metal = Color3.fromRGB(122, 112, 142), Accent = Color3.fromRGB(150, 90, 255), Accent2 = Color3.fromRGB(96, 50, 190),
		Glow = Color3.fromRGB(190, 110, 255), Glow2 = Color3.fromRGB(230, 170, 255), Cloth = Color3.fromRGB(46, 42, 56),
		Thread = Color3.fromRGB(72, 62, 92), Count = 4, LightBrightness = 1.0, LightRange = 7, EmitRate = 0, Shine = 0.12,
	},
	-- 9. Вулканический: огненные трещины и броневые рёбра
	[9] = {
		Metal = Color3.fromRGB(112, 106, 106), Accent = Color3.fromRGB(255, 110, 30), Accent2 = Color3.fromRGB(255, 190, 70),
		Glow = Color3.fromRGB(255, 90, 20), Glow2 = Color3.fromRGB(255, 170, 50), Cloth = Color3.fromRGB(30, 24, 24),
		Thread = Color3.fromRGB(72, 58, 58), Count = 2, LightBrightness = 0.8, LightRange = 7, EmitRate = 3, Shine = 0.2,
	},
	-- 10. Звёздный рюкзак: золотая звезда, космические пластины, блёстки
	[10] = {
		Metal = Color3.fromRGB(112, 126, 142), Accent = Color3.fromRGB(255, 200, 60), Accent2 = Color3.fromRGB(52, 24, 120),
		Glow = Color3.fromRGB(120, 230, 255), Glow2 = Color3.fromRGB(255, 255, 255), Cloth = Color3.fromRGB(22, 40, 120),
		Thread = Color3.fromRGB(52, 72, 86), Count = 8, LightBrightness = 0.8, LightRange = 7, EmitRate = 5, Shine = 0.15,
	},
} :: { [number]: BackpackDetailLevelCfg }
