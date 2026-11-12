--!strict
-- ============================================================================
-- 📦 МОДУЛЬ: GameConfig (ReplicatedStorage.Modules.GameConfig)
-- Версия: v13.0 — Полное выполнение 13 обязательных требований:
-- • Шахта 30×30×30 блоков (120×120×120 studs) с коллизией CanCollide = true,
--   неровными стенами, полками, подпорками, лампами, вагонетками и карманами пещер.
-- • 16 видов пород и руды (каменная матрица + 3D-вкрапления) + Утренние залежи (0–3 шт., цена ×3).
-- • 10 уровней Кирок (1–10 ур.) и 10 уровней Рюкзаков (1–10 ур. по референсу от холщового до киберпанка).
-- • Вместимость рюкзака зависит ТОЛЬКО от купленного рюкзака (1–10 ур.).
-- • Тренировка силы и Энергия — ТОЛЬКО в Навыках (убраны из Магазина).
-- • Ночью вход в шахту закрыт; при входе в шахту надевается Оранжевая Каска;
--   внизу экрана — кнопка быстрого возврата «Наверх / Спаун».
-- ============================================================================

local GameConfig = {}

-- ============================================================================
-- 1. ПАРАМЕТРЫ ШАХТЫ 30×30×30 БЛОКОВ И КООРДИНАТЫ ПЛОЩАДИ
-- ============================================================================
GameConfig.MINE_GRID_SIZE = 20          -- v31: 20 крупных блоков по X и 20 по Z (та же площадь 120×120 studs)
GameConfig.MINE_LEVELS_COUNT = 30       -- 30 уровней в глубину (v31: до Y ≈ -183 studs)
GameConfig.BLOCK_WIDTH = 6.0            -- v31: блоки руды крупнее — 6×6×6 studs (было 4×4×4)
GameConfig.BLOCK_HEIGHT = 6.0
GameConfig.MINE_TOP_ORIGIN = Vector3.new(-57, -3, -135) -- v31: центры блоков X: -57..+57, Z: -135..-21 (края -60..60 / -138..-18)

-- Границы региона шахты (для надевания оранжевой каски и ночного барьера)
GameConfig.MINE_ZONE_BOUNDS = {
	MinX = -61.5, MaxX = 61.5,
	MinZ = -139.5, MaxZ = -16.0,
	TopY = 12, BottomY = -205, -- v49: exact mine pit + collar bounds
}

-- Координаты на открытой площади (Неоновый павильон SHOP и рынок приёма руды $ SELL)
GameConfig.SPAWN_POSITION       = Vector3.new(0, 3.5, 22)     -- Безопасная точка спавна
GameConfig.WHITE_SELL_PAD_POS   = Vector3.new(-32, 0.25, 6)   -- Современный рынок приёма руды "$ SELL"
GameConfig.GREEN_SHOP_PAD_POS   = Vector3.new(32, 0.25, 6)    -- Павильон "🛒 SHOP" (Кирки и Рюкзаки 1–10)
GameConfig.SELL_ZONE_RADIUS     = 18.0                        -- Радиус зоны автопродажи (вход = продажа)
GameConfig.AUTO_SELL = {
	CheckInterval = 0.25,   -- как часто сервер проверяет, стоит ли игрок в зоне
	RepeatSeconds = 2.0,    -- пока игрок в зоне, новую добычу сдаём не чаще, чем раз в N секунд
}

-- Вход в шахту: тропинка идёт от спавна (Z=22) к арке с вывеской «ШАХТА» (Z=-12)
GameConfig.MINE_ENTRANCE_POS = Vector3.new(0, 0, -12)
GameConfig.MINE_SIGN_TEXT = "ШАХТА"
GameConfig.NIGHT_CLOSED_MESSAGE = "Шахта закрыта на ночь. Возвращайся утром!"

GameConfig.MAX_MINE_DISTANCE = 12.0 -- v49: strictly first 2 blocks in radius (2 * 6.0 studs)
GameConfig.AUTOSAVE_INTERVAL = 60
GameConfig.SPAWN_TELEPORT_COOLDOWN = 4.0 -- Кулдаун кнопки «К продаже» (сек)
-- v14: кнопка внизу телепортирует прямо в зону автопродажи (внутрь SELL_ZONE_RADIUS), руда сдаётся сразу
GameConfig.SELL_TELEPORT_POSITION = Vector3.new(-32, 3.5, 12)

-- Бег (Shift на ПК, кнопка на телефоне). Бесплатный: расходует 0 энергии.
GameConfig.SPRINT = {
	WalkSpeed = 16,
	SprintMultiplier = 1.6,   -- 16 -> ~25.6
}

GameConfig.MAP_HALF_EXTENT = 145
-- v19c: smaller playable area (mine / SHOP / SELL keep their size). Cliffs stand on these lines.
GameConfig.MAP_BOUNDS = { MinX = -72, MaxX = 80, MinZ = -150, MaxZ = 66 } -- v19d: edges = mine walls
GameConfig.WALL_HEIGHT = 60
GameConfig.FALL_THRESHOLD_Y = -205 -- v49: below bottom of 30-level mine (-186)

-- ============================================================================
-- 2. ЭНЕРГИЯ И АНТИ-ФАРМ ЗАЩИТА
-- ============================================================================
GameConfig.ENERGY = {
	BaseMax = 100,                 -- Базовый максимум энергии
	PerSkillLevelMaxBonus = 12,    -- +12 к макс. энергии за каждый уровень навыка «Энергия»
	PerSkillLevelRegenBonus = 0.35,-- +0.35 регенерации/сек за каждый уровень навыка «Энергия»
	BaseSwingCost = 6.0,           -- Базовая трата энергии за удар
	DepthExtraCostMax = 6.0,       -- На дне (30 бл.) удар тратит до 12 энергии
	-- v50: swings cost half and energy comes back faster, so mining no longer
	-- stalls after ~16 swings (the biggest frustration for young players)
	SwingCostMultiplier = 0.5,
	PassiveRegenPerSec = 3.6,      -- Базовое восстановление в секунду
	SurfaceRestRegenPerSec = 9.0,  -- Восстановление на поверхности и каменных полках
}

-- ============================================================================
-- v50: COMBO — break blocks quickly one after another to build a streak.
-- Every block adds bonus XP; every MilestoneEvery-th block pays bonus coins.
-- ============================================================================
GameConfig.COMBO = {
	WindowSeconds = 6.0,       -- next block must break within this time
	XPBonusPerStep = 0.01,     -- +1% XP per combo step ...
	XPBonusMaxSteps = 20,      -- ... up to +20%
	MilestoneEvery = 5,
	-- v51: the coin bonus is small on purpose. A milestone pays (combo × CoinsPerComboStep)
	-- blocks' worth of ore from that depth, capped at CoinsMaxCombo: at most ONE block's
	-- worth every 5 blocks. Near the surface that is 0–1 coin.
	CoinsPerComboStep = 0.05,
	CoinsMaxCombo = 20,
}

-- ============================================================================
-- v50: SURPRISE BLOCKS hidden in the mine (rolled per cell on every mine reset)
--   Lucky    — random prize (coins, energy, ore shower, Power Frenzy, jackpot)
--   TNT      — blows up the 3×3×3 blocks around it and collects their ore
--   Treasure — a chest of coins + full energy
-- ============================================================================
GameConfig.SPECIAL_BLOCKS = {
	MinDepth = 2, -- never on the grass layer
	Lucky = {
		Id = "Lucky", Name = "🍀 Lucky Block", Icon = "🍀", Chance = 0.012,
		Color = Color3.fromRGB(255, 205, 40), AccentColor = Color3.fromRGB(255, 240, 150), HitSound = "CrystalChime",
	},
	TNT = {
		Id = "TNT", Name = "💥 TNT", Icon = "💥", Chance = 0.009, BlastRadius = 1,
		OverflowCoinShare = 0.5, -- ore that does not fit into the backpack is paid at half price
		XPShare = 0.25,          -- blown-up blocks give a quarter of their normal XP
		-- blocks that need a better pickaxe than the player's survive the blast
		Color = Color3.fromRGB(226, 52, 44), AccentColor = Color3.fromRGB(255, 140, 60), HitSound = "CoalTap",
	},
	Treasure = {
		Id = "Treasure", Name = "🧰 Treasure Chest", Icon = "🧰", Chance = 0.005,
		Color = Color3.fromRGB(156, 100, 50), AccentColor = Color3.fromRGB(255, 215, 70), HitSound = "OreTap",
	},
	FrenzySeconds = 20,       -- Lucky prize: Power Frenzy duration
	FrenzyDamageMultiplier = 2,
	-- v51: coin prizes are measured in "blocks of ore from the depth of the surprise block that
	-- the player's pickaxe can mine", so near the surface (ore worth 1–2 coins) a Lucky Block
	-- pays a handful of coins, not a pickaxe. Deep down the same prize is worth more, but only
	-- for players whose pickaxe can really mine the ore there.
	Rewards = {
		LuckyMin = 3, LuckyMax = 6,   -- the common Lucky Block prize
		LuckyWithEnergy = 2,          -- coins that come with the "full energy" prize
		Jackpot = 12,                 -- the rare jackpot (8% of Lucky Blocks)
		TreasureMin = 10, TreasureMax = 14,
	},
}

function GameConfig.GetSpecialBlockHP(levelIndex: number): number
	return 16 + math.floor(levelIndex) * 6
end

-- Average sell price of one block at this depth (weighted by how often each block appears).
-- With pickaxeLevel, ore that this pickaxe cannot mine yet counts as worth nothing: a beginner
-- can dig straight down through plain stone to 20+ m in a couple of minutes, and bonuses
-- found down there must not pay like real deep mining.
function GameConfig.GetDepthOreValue(levelIndex: number, pickaxeLevel: number?): number
	local band = GameConfig.GetDepthBand(levelIndex)
	local total, weight = 0, 0
	for _, pair in ipairs(band.Weights) do
		local info = GameConfig.BLOCK_TYPES[pair[1]]
		if info then
			if not pickaxeLevel or (info.MinPickaxeLevel or 1) <= pickaxeLevel then
				total += info.SellPrice * pair[2]
			end
			weight += pair[2]
		end
	end
	return weight > 0 and total / weight or 1
end

-- Coin prize worth `blocksWorth` blocks of ore from this depth (see GetDepthOreValue)
function GameConfig.GetSpecialCoins(levelIndex: number, blocksWorth: number, pickaxeLevel: number?): number
	return math.max(1, math.floor(GameConfig.GetDepthOreValue(levelIndex, pickaxeLevel) * blocksWorth + 0.5))
end

-- ============================================================================
-- v50: DAILY REWARD — first join of each (UTC) day; missing a day restarts the streak.
-- Coins grow a little with the player's level so the gift stays useful later on.
-- ============================================================================
GameConfig.DAILY_REWARDS = { -- v51: small on day one (a first pickaxe costs 65 coins)
	{ Coins = 10 },
	{ Coins = 20 },
	{ Coins = 30 },
	{ Coins = 45 },
	{ Coins = 65 },
	{ Coins = 90 },
	{ Coins = 150, SkillPoints = 1 },
}
GameConfig.DAILY_REWARD_LEVEL_BONUS = 0.15 -- +15% coins per player level above 1

function GameConfig.GetDailyReward(streakDay: number, playerLevel: number): (number, number)
	local n = #GameConfig.DAILY_REWARDS
	local entry = GameConfig.DAILY_REWARDS[((math.max(1, math.floor(streakDay)) - 1) % n) + 1]
	local mult = 1 + GameConfig.DAILY_REWARD_LEVEL_BONUS * math.max(0, math.floor(playerLevel) - 1)
	return math.floor(entry.Coins * mult + 0.5), entry.SkillPoints or 0
end

GameConfig.ANTI_FARM = {
	SameLayerPenaltyThreshold = 40,
	SameLayerMinMultiplier = 0.35,
	MaxBlocksPerTenSeconds = 16,
	MaxPlayerSpeedStudsPerSec = 95,
}

-- ============================================================================
-- 3. ЦИКЛ ДЕНЬ / ВЕЧЕР / НОЧЬ / УТРО И УТРЕННИЕ ЗАЛЕЖИ (0–3 ШТ., ЦЕНА ×3)
-- • День длится 360 сек (6 минут), включая утреннюю фазу и вечернее предупреждение за 20 сек.
-- • Ночь длится 60 сек (1 минута): вход в шахту с поверхности закрыт барьером!
-- • Каждое утро сервер случайно спавнит от 0 до 3 Утренних залежей (по 6–12 блоков),
--   которые продаются в 3 раза дороже обычной руды той же глубины!
-- ============================================================================
GameConfig.DAY_DURATION_SECONDS = 360    -- 6 минут: Утро + День + Вечер
GameConfig.EVENING_WARNING_SECONDS = 20  -- За 20 сек до ночи предупреждение
GameConfig.NIGHT_DURATION_SECONDS = 60   -- 1 минута ночи (вход в шахту закрыт)
GameConfig.NIGHT_GRACE_EXIT_SECONDS = 15 -- Игрокам внутри даётся 15 сек до безопасной эвакуации наверх
GameConfig.TRANSITION_TWEEN_TIME = 2.5

-- v50: one place for the day / night / deep-mine light. WorldBuilder, ServerMain and the
-- client depth darkening all read it. Days are brighter and more colourful, and the
-- mine gets moody with depth but never pitch black (young players got lost in the dark).
GameConfig.LIGHTING = {
	DayBrightness = 2.2,
	DayAmbient = Color3.fromRGB(158, 162, 174),
	DayOutdoorAmbient = Color3.fromRGB(176, 186, 204),
	NightBrightness = 0.45,
	NightAmbient = Color3.fromRGB(36, 42, 68),
	NightOutdoorAmbient = Color3.fromRGB(42, 50, 78),
	Saturation = 0.26,
	DeepDarkness = 0.88, -- share of the brightness lost at the very bottom
	DeepAmbient = Color3.fromRGB(34, 36, 54),
	DeepOutdoorAmbient = Color3.fromRGB(30, 32, 48),
	DeepExposure = -0.26,
	DeepAtmosphereExtraDensity = 0.26,
}

GameConfig.MORNING_VEINS = {
	MinCount = 0,
	MaxCount = 3,                  -- От 0 до 3 залежей каждое утро
	MinBlocksPerVein = 6,
	MaxBlocksPerVein = 12,         -- 6–12 блоков в одной утренней залежи
	SellPriceMultiplier = 3,       -- Цена продажи ×3!
	MinSpawnDepth = 4,             -- Не спавнятся на поверхности (только с 4 по 30 уровень глубины)
	MaxSpawnDepth = 30,
	MinPlayerClearanceStuds = 10,  -- Не спавнятся внутри игроков
}

-- ============================================================================
-- 4. ТЕКСТУРЫ И ПЛИТОЧНЫЕ ПАЛИТРЫ
-- ============================================================================
GameConfig.TEXTURES = {
	CrosshairIcon          = "rbxassetid://6034996695",
	SubtleOreTexture       = "rbxassetid://6372755229",
	CrackDecal             = "rbxassetid://6888915121",
	DustParticle           = "rbxassetid://243660364",
	UploadedDarkGreenTile  = "rbxassetid://6372755229",
	UploadedLightGreenTile = "rbxassetid://6372755229",
	DarkGreenTilePalette = {
		Base   = Color3.fromRGB(10, 58, 30),
		CellA  = Color3.fromRGB(6, 38, 19),
		CellB  = Color3.fromRGB(18, 88, 46),
		CellC  = Color3.fromRGB(26, 112, 58),
		Grid   = Color3.fromRGB(42, 165, 88),
	},
	LightGreenTilePalette = {
		Base   = Color3.fromRGB(72, 208, 142),
		CellA  = Color3.fromRGB(56, 190, 126),
		CellB  = Color3.fromRGB(84, 220, 154),
		CellC  = Color3.fromRGB(106, 232, 170),
		Grid   = Color3.fromRGB(185, 248, 216),
	},
}

-- ============================================================================
-- 5. ЗВУКИ ДОБЫЧИ, ТЕЛЕПОРТА, ПРОДАЖИ И АТМОСФЕРЫ ШАХТЫ
-- ============================================================================
GameConfig.SOUNDS = {
	-- v35: critical hit (heavy metallic clang + stone burst + short whoosh)
	CritHit = {
		Ids = { "rbxassetid://9116651688", "rbxassetid://9116651255" },
		Volume = 0.55, PitchMin = 0.62, PitchMax = 0.72, MaxDuration = 0.9,
		Layers = {
			{ Ids = { "rbxassetid://9119050283", "rbxassetid://9119050772" }, Volume = 0.42, PitchMin = 0.70, PitchMax = 0.80, Delay = 0.0, MaxDuration = 0.8 },
			{ Ids = { "rbxassetid://9103759121" }, Volume = 0.36, PitchMin = 0.80, PitchMax = 0.88, Delay = 0.01, MaxDuration = 0.5 },
			{ Ids = { "rbxassetid://9126073001" }, Volume = 0.18, PitchMin = 1.70, PitchMax = 1.90, Delay = 0.0, MaxDuration = 0.35 },
		},
	},
	-- v35: backpack got dirtier (wet mud squelch + gritty crumble)
	BagDirty = {
		Ids = { "rbxassetid://9125869504", "rbxassetid://9125869138" },
		Volume = 0.55, PitchMin = 0.55, PitchMax = 0.65, MaxDuration = 0.7,
		Layers = {
			{ Ids = { "rbxassetid://9119050772", "rbxassetid://9119050286" }, Volume = 0.26, PitchMin = 0.55, PitchMax = 0.65, Delay = 0.06, MaxDuration = 0.7 },
			{ Ids = { "rbxassetid://9125869138" }, Volume = 0.30, PitchMin = 0.45, PitchMax = 0.52, Delay = 0.16, MaxDuration = 0.6 },
		},
	},
	DirtTap = {
		Ids = { "rbxassetid://9125869504", "rbxassetid://9125869138" },
		Volume = 0.38, PitchMin = 0.88, PitchMax = 1.06, MaxDuration = 0.45,
	},
	StoneTap = {
		Ids = {
			"rbxassetid://9103759039",
			"rbxassetid://9103759121",
			"rbxassetid://9120146349",
		},
		Volume = 0.42, PitchMin = 0.92, PitchMax = 1.08, MaxDuration = 0.55,
		Layers = {
			{ Ids = { "rbxassetid://9125869504", "rbxassetid://9125869138" }, Volume = 0.16, PitchMin = 0.98, PitchMax = 1.15, Delay = 0.02, MaxDuration = 0.45 },
		},
	},
	CoalTap = {
		Ids = { "rbxassetid://9119050283", "rbxassetid://9103759039" },
		Volume = 0.40, PitchMin = 1.05, PitchMax = 1.22, MaxDuration = 0.50,
	},
	OreTap = {
		Ids = {
			"rbxassetid://9103759039",
			"rbxassetid://9103759121",
			"rbxassetid://9120146349",
		},
		Volume = 0.44, PitchMin = 1.00, PitchMax = 1.16, MaxDuration = 0.55,
		Layers = {
			{ Ids = { "rbxassetid://9116651255", "rbxassetid://9116651688" }, Volume = 0.14, PitchMin = 1.25, PitchMax = 1.50, Delay = 0.0, MaxDuration = 0.42 },
		},
	},
	CrystalChime = {
		Ids = { "rbxassetid://9116651255", "rbxassetid://9116651688" },
		Volume = 0.44, PitchMin = 1.35, PitchMax = 1.65, MaxDuration = 0.60,
		Layers = {
			{ Ids = { "rbxassetid://9103759121" }, Volume = 0.25, PitchMin = 1.10, PitchMax = 1.25, Delay = 0.0, MaxDuration = 0.45 },
		},
	},
	MithrilResonance = {
		Ids = { "rbxassetid://9116651688", "rbxassetid://9126073001" },
		Volume = 0.48, PitchMin = 0.82, PitchMax = 1.05, MaxDuration = 0.75,
		Layers = {
			{ Ids = { "rbxassetid://9103759039" }, Volume = 0.30, PitchMin = 1.20, PitchMax = 1.40, Delay = 0.0, MaxDuration = 0.50 },
		},
	},
	WeakPickaxeClink = {
		Ids = { "rbxassetid://9116651255" },
		Volume = 0.35, PitchMin = 0.65, PitchMax = 0.78, MaxDuration = 0.35,
	},
	StoneCrumble = {
		Ids = {
			"rbxassetid://9119050283",
			"rbxassetid://9119050772",
			"rbxassetid://9119050286",
		},
		Volume = 0.45, PitchMin = 0.92, PitchMax = 1.12, MaxDuration = 1.0,
		Layers = {
			{ Ids = { "rbxassetid://9118588165" }, Volume = 0.22, PitchMin = 1.02, PitchMax = 1.22, Delay = 0.06, MaxDuration = 0.8 },
		},
	},
	CaveDrip = {
		Ids = { "rbxassetid://9116651255", "rbxassetid://9125869138" },
		Volume = 0.18, PitchMin = 1.65, PitchMax = 1.95, MaxDuration = 0.30,
	},
	CaveEcho = {
		Ids = { "rbxassetid://9119050286" },
		Volume = 0.16, PitchMin = 0.52, PitchMax = 0.68, MaxDuration = 1.40,
	},
	TeleportWhoosh = {
		Ids = { "rbxassetid://9126073001" },
		Volume = 0.36, PitchMin = 1.12, PitchMax = 1.25, MaxDuration = 0.85,
	},
	CoinChime = {
		Ids = { "rbxassetid://9113728756" },
		Volume = 0.40, PitchMin = 1.0, PitchMax = 1.08, MaxDuration = 1.2,
		Layers = {
			{ Ids = { "rbxassetid://9113728042" }, Volume = 0.16, PitchMin = 1.30, PitchMax = 1.40, Delay = 0.12, MaxDuration = 0.7 },
			{ Ids = { "rbxassetid://607665037" }, Volume = 0.30, PitchMin = 1.0, PitchMax = 1.1, Delay = 0.05 },
		},
	},
	ShopPurchase = {
		Ids = { "rbxassetid://9113728042" },
		Volume = 0.42, PitchMin = 1.0, PitchMax = 1.06, MaxDuration = 1.5,
		Layers = {
			{ Ids = { "rbxassetid://9113728756" }, Volume = 0.26, PitchMin = 1.05, PitchMax = 1.12, Delay = 0.06, MaxDuration = 1.0 },
			{ Ids = { "rbxassetid://607665037" }, Volume = 0.20, PitchMin = 1.15, PitchMax = 1.25, Delay = 0.14 },
			{ Ids = { "rbxassetid://9126073001" }, Volume = 0.14, PitchMin = 1.25, PitchMax = 1.35, Delay = 0.2, MaxDuration = 0.9 },
		},
	},
	-- v28: shop / kiosk sound pack (layered, pitch-randomised, soft volumes)
	ShopOpen = {
		Ids = { "rbxassetid://9126073001" },
		Volume = 0.18, PitchMin = 1.30, PitchMax = 1.40, MaxDuration = 0.8,
		Layers = {
			{ Ids = { "rbxassetid://12221976" }, Volume = 0.12, PitchMin = 1.10, PitchMax = 1.18 },
			{ Ids = { "rbxassetid://607665037" }, Volume = 0.09, PitchMin = 1.45, PitchMax = 1.60, Delay = 0.07, MaxDuration = 0.6 },
		},
	},
	ShopSwipe = {
		Ids = { "rbxassetid://12221976" },
		Volume = 0.13, PitchMin = 1.20, PitchMax = 1.34,
		Layers = {
			{ Ids = { "rbxassetid://9126073001" }, Volume = 0.07, PitchMin = 1.85, PitchMax = 2.05, MaxDuration = 0.3 },
		},
	},
	-- v50: surprise blocks and combo (built from the sounds already used above)
	Explosion = {
		Ids = { "rbxassetid://9119050283", "rbxassetid://9119050772" },
		Volume = 0.75, PitchMin = 0.42, PitchMax = 0.52, MaxDuration = 1.3,
		Layers = {
			{ Ids = { "rbxassetid://9116651688" }, Volume = 0.45, PitchMin = 0.40, PitchMax = 0.48, Delay = 0.0, MaxDuration = 1.0 },
			{ Ids = { "rbxassetid://9119050286" }, Volume = 0.40, PitchMin = 0.70, PitchMax = 0.85, Delay = 0.12, MaxDuration = 1.0 },
		},
	},
	LuckyPrize = {
		Ids = { "rbxassetid://9113728042" },
		Volume = 0.42, PitchMin = 1.18, PitchMax = 1.30, MaxDuration = 1.4,
		Layers = {
			{ Ids = { "rbxassetid://9113728756" }, Volume = 0.30, PitchMin = 1.30, PitchMax = 1.42, Delay = 0.08, MaxDuration = 1.0 },
		},
	},
	ComboUp = { Ids = { "rbxassetid://9116651255" }, Volume = 0.16, PitchMin = 1.55, PitchMax = 1.85, MaxDuration = 0.35 },
	UIClick = { Ids = { "rbxassetid://12221976" }, Volume = 0.10, PitchMin = 1.0, PitchMax = 1.1 },
	StatUp = { Ids = { "rbxassetid://9126073001" }, Volume = 0.12, PitchMin = 0.9, PitchMax = 1.0, MaxDuration = 1.0 },
}

-- ============================================================================
-- 6. 16 ВИДОВ ПОРОД И РУДЫ (КАМЕННАЯ МАТРИЦА + 3D ВКРАПЛЕНИЯ НА ГЛУБИНЕ 1..30)
-- ВНИМАНИЕ: Уровни кирки теперь 1..10 (Уровень 1 — стартовая Деревянная кирка).
-- ============================================================================
export type InclusionStyle = "None" | "Pebbles" | "CoalSeams" | "MetallicFlecks" | "MalachiteVeins" | "GoldNuggets" | "SilverVeins" | "CrystalClusters" | "EmeraldTiles" | "MithrilVeins" | "LavaCracks" | "VoidCracks" | "IceFrost"

export type BlockTypeInfo = {
	Id: string,
	Name: string,
	Icon: string,
	Category: string,          -- "Common" | "Rare" | "Precious" | "Relic"
	MinDepth: number,          -- Глубина в блоках (1..30)
	MaxDepth: number,
	RarityLabel: string,
	HP: number,
	TargetMineTimeSec: string,
	SellPrice: number,
	MinPickaxeLevel: number,   -- Нужный уровень кирки (1..10)
	EnergyCost: number,
	XP: number,
	StrengthXP: number,
	Color: Color3,             -- Каменная матрица
	AccentColor: Color3,       -- Вкрапления / кристаллы
	SecondaryAccent: Color3?,
	Mat: Enum.Material,
	InclusionMat: Enum.Material,
	InclusionStyle: InclusionStyle,
	InclusionCount: number,
	UseSubtleTexture: boolean,
	UseGreenTileTexture: boolean?,
	HasGlow: boolean,
	GlowBrightness: number?,
	GlowRange: number?,
	HitSound: string,
}

GameConfig.BLOCK_LIST = {
	-- 1. Трава / Верхний дёрн (Глубина 1–2)
	{
		Id = "Grass", Name = "Grass", Icon = "🌿", Category = "Common",
		MinDepth = 1, MaxDepth = 2, RarityLabel = "Surface",
		HP = 12, TargetMineTimeSec = "0.8–1.1 s", SellPrice = 1, MinPickaxeLevel = 1, EnergyCost = 6,
		XP = 4, StrengthXP = 2,
		Color = Color3.fromRGB(96, 190, 60), AccentColor = Color3.fromRGB(118, 86, 56),
		Mat = Enum.Material.SmoothPlastic, InclusionMat = Enum.Material.Ground,
		InclusionStyle = "Pebbles", InclusionCount = 2, UseSubtleTexture = false, HasGlow = false, HitSound = "DirtTap",
	},
	-- 2. Земля / Суглинок (Глубина 1–7)
	{
		Id = "Dirt", Name = "Dirt", Icon = "🟫", Category = "Common",
		MinDepth = 1, MaxDepth = 7, RarityLabel = "Common",
		HP = 16, TargetMineTimeSec = "1.0–1.5 s", SellPrice = 1, MinPickaxeLevel = 1, EnergyCost = 6,
		XP = 5, StrengthXP = 2,
		Color = Color3.fromRGB(116, 84, 56), AccentColor = Color3.fromRGB(92, 66, 44),
		Mat = Enum.Material.Ground, InclusionMat = Enum.Material.Slate,
		InclusionStyle = "Pebbles", InclusionCount = 2, UseSubtleTexture = false, HasGlow = false, HitSound = "DirtTap",
	},
	-- 3. Глина (Глубина 1–7)
	{
		Id = "Clay", Name = "Sand", Icon = "🟨", Category = "Common",
		MinDepth = 1, MaxDepth = 7, RarityLabel = "Frequent",
		HP = 22, TargetMineTimeSec = "1.3–1.8 s", SellPrice = 2, MinPickaxeLevel = 1, EnergyCost = 6,
		XP = 7, StrengthXP = 3,
		Color = Color3.fromRGB(212, 168, 108), AccentColor = Color3.fromRGB(170, 128, 80),
		Mat = Enum.Material.Sand, InclusionMat = Enum.Material.Sandstone,
		InclusionStyle = "Pebbles", InclusionCount = 3, UseSubtleTexture = false, HasGlow = false, HitSound = "DirtTap",
	},
	-- 4. Камень (Глубина 3–24)
	{
		Id = "Stone", Name = "Stone", Icon = "🪨", Category = "Common",
		MinDepth = 3, MaxDepth = 24, RarityLabel = "Mine Base",
		HP = 42, TargetMineTimeSec = "2.5–4.0 s", SellPrice = 2, MinPickaxeLevel = 1, EnergyCost = 7,
		XP = 10, StrengthXP = 4,
		Color = Color3.fromRGB(118, 122, 128), AccentColor = Color3.fromRGB(142, 146, 154),
		Mat = Enum.Material.Slate, InclusionMat = Enum.Material.Granite,
		InclusionStyle = "Pebbles", InclusionCount = 2, UseSubtleTexture = true, HasGlow = false, HitSound = "StoneTap",
	},
	-- 5. Уголь (Глубина 4–22)
	{
		Id = "Coal", Name = "Coal", Icon = "⚫", Category = "Common",
		MinDepth = 4, MaxDepth = 22, RarityLabel = "Common Ore",
		HP = 85, TargetMineTimeSec = "3.0–5.0 s", SellPrice = 6, MinPickaxeLevel = 2, EnergyCost = 7,
		XP = 18, StrengthXP = 7,
		Color = Color3.fromRGB(76, 80, 86), AccentColor = Color3.fromRGB(22, 24, 28), SecondaryAccent = Color3.fromRGB(42, 46, 52),
		Mat = Enum.Material.Slate, InclusionMat = Enum.Material.Basalt,
		InclusionStyle = "CoalSeams", InclusionCount = 5, UseSubtleTexture = true, HasGlow = false, HitSound = "CoalTap",
	},
	-- 6. Железная руда (Глубина 13–24)
	{
		Id = "Iron", Name = "Iron Ore", Icon = "⛏️", Category = "Rare",
		MinDepth = 13, MaxDepth = 24, RarityLabel = "Uncommon",
		HP = 210, TargetMineTimeSec = "5.0–8.0 s", SellPrice = 14, MinPickaxeLevel = 3, EnergyCost = 8,
		XP = 32, StrengthXP = 12,
		Color = Color3.fromRGB(108, 112, 118), AccentColor = Color3.fromRGB(172, 88, 64), SecondaryAccent = Color3.fromRGB(182, 192, 206),
		Mat = Enum.Material.Granite, InclusionMat = Enum.Material.Metal,
		InclusionStyle = "MetallicFlecks", InclusionCount = 6, UseSubtleTexture = true, HasGlow = false, HitSound = "OreTap",
	},
	-- 7. Медная руда (Глубина 18–26)
	{
		Id = "Copper", Name = "Magma", Icon = "🌋", Category = "Rare",
		MinDepth = 18, MaxDepth = 26, RarityLabel = "Uncommon",
		HP = 260, TargetMineTimeSec = "6.0–9.0 s", SellPrice = 24, MinPickaxeLevel = 3, EnergyCost = 8,
		XP = 42, StrengthXP = 15,
		Color = Color3.fromRGB(82, 52, 42), AccentColor = Color3.fromRGB(255, 120, 28), SecondaryAccent = Color3.fromRGB(255, 214, 70),
		Mat = Enum.Material.Basalt, InclusionMat = Enum.Material.Neon,
		InclusionStyle = "LavaCracks", InclusionCount = 8, UseSubtleTexture = false, HasGlow = false, HitSound = "OreTap",
	},
	-- 8. Оловянная руда (Глубина 18–26)
	{
		Id = "Tin", Name = "Ice Stone", Icon = "🧊", Category = "Rare",
		MinDepth = 18, MaxDepth = 26, RarityLabel = "Uncommon+",
		HP = 290, TargetMineTimeSec = "6.5–9.0 s", SellPrice = 32, MinPickaxeLevel = 4, EnergyCost = 8,
		XP = 50, StrengthXP = 18,
		Color = Color3.fromRGB(128, 176, 222), AccentColor = Color3.fromRGB(226, 246, 255), SecondaryAccent = Color3.fromRGB(110, 178, 255),
		Mat = Enum.Material.Ice, InclusionMat = Enum.Material.Glass,
		InclusionStyle = "IceFrost", InclusionCount = 7, UseSubtleTexture = true, HasGlow = false, HitSound = "OreTap",
	},
	-- 9. Серебряная руда (Глубина 23–28)
	{
		Id = "Silver", Name = "Silver Ore", Icon = "🥈", Category = "Rare",
		MinDepth = 23, MaxDepth = 28, RarityLabel = "Rare",
		HP = 520, TargetMineTimeSec = "8.0–12.0 s", SellPrice = 58, MinPickaxeLevel = 5, EnergyCost = 9,
		XP = 78, StrengthXP = 26,
		Color = Color3.fromRGB(68, 74, 84), AccentColor = Color3.fromRGB(232, 240, 252), SecondaryAccent = Color3.fromRGB(185, 198, 215),
		Mat = Enum.Material.Slate, InclusionMat = Enum.Material.Metal,
		InclusionStyle = "SilverVeins", InclusionCount = 6, UseSubtleTexture = true, HasGlow = false, HitSound = "OreTap",
	},
	-- 10. Золотая руда (Глубина 24–29)
	{
		Id = "Gold", Name = "Gold Ore", Icon = "🪙", Category = "Rare",
		MinDepth = 24, MaxDepth = 29, RarityLabel = "Rare+",
		HP = 720, TargetMineTimeSec = "10.0–15.0 s", SellPrice = 120, MinPickaxeLevel = 5, EnergyCost = 9,
		XP = 115, StrengthXP = 36,
		Color = Color3.fromRGB(142, 140, 132), AccentColor = Color3.fromRGB(255, 204, 48), SecondaryAccent = Color3.fromRGB(218, 162, 32),
		Mat = Enum.Material.Limestone, InclusionMat = Enum.Material.Metal,
		InclusionStyle = "GoldNuggets", InclusionCount = 6, UseSubtleTexture = true, HasGlow = true, GlowBrightness = 0.45, GlowRange = 5, HitSound = "OreTap",
	},
	-- 11. Аметист (Глубина 27–30)
	{
		Id = "Amethyst", Name = "Amethyst", Icon = "🔮", Category = "Precious",
		MinDepth = 27, MaxDepth = 30, RarityLabel = "Epic",
		HP = 1150, TargetMineTimeSec = "12.0–16.0 s", SellPrice = 200, MinPickaxeLevel = 6, EnergyCost = 10,
		XP = 165, StrengthXP = 50,
		Color = Color3.fromRGB(112, 108, 122), AccentColor = Color3.fromRGB(186, 88, 255), SecondaryAccent = Color3.fromRGB(224, 165, 255),
		Mat = Enum.Material.Granite, InclusionMat = Enum.Material.Glass,
		InclusionStyle = "CrystalClusters", InclusionCount = 6, UseSubtleTexture = true, HasGlow = true, GlowBrightness = 0.65, GlowRange = 6, HitSound = "CrystalChime",
	},
	-- 12. Рубин (Глубина 28–30)
	{
		Id = "Ruby", Name = "Ruby", Icon = "♦️", Category = "Precious",
		MinDepth = 28, MaxDepth = 30, RarityLabel = "Epic+",
		HP = 1450, TargetMineTimeSec = "14.0–18.0 s", SellPrice = 285, MinPickaxeLevel = 7, EnergyCost = 10,
		XP = 210, StrengthXP = 64,
		Color = Color3.fromRGB(64, 62, 68), AccentColor = Color3.fromRGB(255, 42, 72), SecondaryAccent = Color3.fromRGB(255, 115, 135),
		Mat = Enum.Material.Basalt, InclusionMat = Enum.Material.Glass,
		InclusionStyle = "CrystalClusters", InclusionCount = 6, UseSubtleTexture = true, HasGlow = true, GlowBrightness = 0.75, GlowRange = 6.5, HitSound = "CrystalChime",
	},
	-- 13. Изумруд (Глубина 29–30)
	{
		Id = "Emerald", Name = "Emerald", Icon = "💚", Category = "Precious",
		MinDepth = 29, MaxDepth = 30, RarityLabel = "Legendary",
		HP = 1950, TargetMineTimeSec = "15.0–20.0 s", SellPrice = 340, MinPickaxeLevel = 7, EnergyCost = 11,
		XP = 260, StrengthXP = 78,
		Color = Color3.fromRGB(46, 64, 52), AccentColor = Color3.fromRGB(42, 225, 118), SecondaryAccent = Color3.fromRGB(14, 92, 48),
		Mat = Enum.Material.Slate, InclusionMat = Enum.Material.Glass,
		InclusionStyle = "EmeraldTiles", InclusionCount = 7, UseSubtleTexture = true, UseGreenTileTexture = true, HasGlow = true, GlowBrightness = 0.85, GlowRange = 7, HitSound = "CrystalChime",
	},
	-- 14. Сапфир (Глубина 29–30)
	{
		Id = "Sapphire", Name = "Obsidian", Icon = "🔷", Category = "Precious",
		MinDepth = 29, MaxDepth = 30, RarityLabel = "Legendary",
		HP = 2350, TargetMineTimeSec = "16.0–20.0 s", SellPrice = 385, MinPickaxeLevel = 8, EnergyCost = 11,
		XP = 310, StrengthXP = 92,
		Color = Color3.fromRGB(30, 34, 48), AccentColor = Color3.fromRGB(52, 96, 190), SecondaryAccent = Color3.fromRGB(96, 150, 235),
		Mat = Enum.Material.Basalt, InclusionMat = Enum.Material.Glass,
		InclusionStyle = "CrystalClusters", InclusionCount = 7, UseSubtleTexture = true, HasGlow = true, GlowBrightness = 0.85, GlowRange = 7, HitSound = "CrystalChime",
	},
	-- 15. Алмаз (Глубина 29–30)
	{
		Id = "Diamond", Name = "Diamond", Icon = "💎", Category = "Relic",
		MinDepth = 29, MaxDepth = 30, RarityLabel = "Mythic",
		HP = 3400, TargetMineTimeSec = "18.0–25.0 s", SellPrice = 700, MinPickaxeLevel = 8, EnergyCost = 12,
		XP = 480, StrengthXP = 140,
		Color = Color3.fromRGB(58, 68, 84), AccentColor = Color3.fromRGB(64, 196, 255), SecondaryAccent = Color3.fromRGB(190, 240, 255),
		Mat = Enum.Material.Basalt, InclusionMat = Enum.Material.Glass,
		InclusionStyle = "CrystalClusters", InclusionCount = 8, UseSubtleTexture = true, HasGlow = true, GlowBrightness = 1.05, GlowRange = 8, HitSound = "CrystalChime",
	},
	-- 16. Мифрил (Глубина 30)
	{
		Id = "Mithril", Name = "Abyss Crystal", Icon = "🔮", Category = "Relic",
		MinDepth = 30, MaxDepth = 30, RarityLabel = "Relic (Bottom)",
		HP = 5200, TargetMineTimeSec = "22.0–30.0 s", SellPrice = 1500, MinPickaxeLevel = 9, EnergyCost = 12,
		XP = 850, StrengthXP = 240,
		Color = Color3.fromRGB(38, 24, 62), AccentColor = Color3.fromRGB(170, 82, 255), SecondaryAccent = Color3.fromRGB(226, 176, 255),
		Mat = Enum.Material.Basalt, InclusionMat = Enum.Material.Neon,
		InclusionStyle = "VoidCracks", InclusionCount = 9, UseSubtleTexture = true, HasGlow = true, GlowBrightness = 1.25, GlowRange = 9.5, HitSound = "MithrilResonance",
	},
}

GameConfig.BLOCK_TYPES = {}
for _, b in ipairs(GameConfig.BLOCK_LIST) do
	GameConfig.BLOCK_TYPES[b.Id] = b
end

-- ============================================================================
-- 7. РАСПРЕДЕЛЕНИЕ ПОРОД ПО 30 БЛОКАМ ГЛУБИНЫ (СТРОГО ПО ТЗ)
-- ============================================================================
export type DepthBandConfig = {
	MinDepth: number,
	MaxDepth: number,
	ZoneName: string,
	AmbientFactor: number,
	FogEnd: number,
	Weights: { { any } },
}

GameConfig.DEPTH_BANDS = {
	-- v50: the top layer is a green meadow (mostly Grass); plain brown Dirt starts right below it
	{
		MinDepth = 1, MaxDepth = 1,
		ZoneName = "1 m · Grass meadow",
		AmbientFactor = 1.00, FogEnd = 420,
		Weights = { {"Grass", 68}, {"Dirt", 20}, {"Clay", 12} },
	},
	{
		MinDepth = 2, MaxDepth = 2,
		ZoneName = "2 m · Soft dirt and sand",
		AmbientFactor = 1.00, FogEnd = 420,
		Weights = { {"Dirt", 70}, {"Clay", 30} },
	},
	{
		MinDepth = 3, MaxDepth = 7,
		ZoneName = "3–7 m · Dirt, loam and first stones",
		AmbientFactor = 0.85, FogEnd = 340,
		Weights = { {"Dirt", 46}, {"Clay", 26}, {"Stone", 25}, {"Coal", 3} },
	},
	{
		MinDepth = 8, MaxDepth = 12,
		ZoneName = "8–12 m · Stone and coal",
		AmbientFactor = 0.70, FogEnd = 270,
		Weights = { {"Stone", 72}, {"Clay", 10}, {"Coal", 18} },
	},
	{
		MinDepth = 13, MaxDepth = 17,
		ZoneName = "13–17 m · Coal veins and rare iron",
		AmbientFactor = 0.55, FogEnd = 215,
		Weights = { {"Stone", 56}, {"Coal", 34}, {"Iron", 10} },
	},
	{
		MinDepth = 18, MaxDepth = 22,
		ZoneName = "18–22 m · Iron, copper and tin belt",
		AmbientFactor = 0.42, FogEnd = 175,
		Weights = { {"Stone", 28}, {"Coal", 24}, {"Iron", 22}, {"Copper", 15}, {"Tin", 11} },
	},
	{
		MinDepth = 23, MaxDepth = 26,
		ZoneName = "23–26 m · Silver slate and early gold",
		AmbientFactor = 0.30, FogEnd = 140,
		Weights = { {"Stone", 20}, {"Iron", 18}, {"Copper", 20}, {"Tin", 15}, {"Silver", 19}, {"Gold", 8} },
	},
	{
		MinDepth = 27, MaxDepth = 28,
		ZoneName = "27–28 m · Gold quartzite and amethysts",
		AmbientFactor = 0.20, FogEnd = 115,
		Weights = { {"Silver", 24}, {"Gold", 34}, {"Amethyst", 28}, {"Ruby", 14} },
	},
	{
		MinDepth = 29, MaxDepth = 30,
		ZoneName = "29–30 m · Relic bottom (Ruby, Emerald, Sapphire, Diamond, Mithril)",
		AmbientFactor = 0.12, FogEnd = 90,
		Weights = { {"Gold", 12}, {"Amethyst", 15}, {"Ruby", 20}, {"Emerald", 18}, {"Sapphire", 16}, {"Diamond", 12}, {"Mithril", 7} },
	},
} :: { DepthBandConfig }

function GameConfig.GetDepthBand(levelIndex: number): DepthBandConfig
	local d = math.clamp(math.floor(levelIndex), 1, GameConfig.MINE_LEVELS_COUNT)
	for _, band in ipairs(GameConfig.DEPTH_BANDS) do
		if d >= band.MinDepth and d <= band.MaxDepth then
			return band
		end
	end
	return GameConfig.DEPTH_BANDS[#GameConfig.DEPTH_BANDS]
end

GameConfig.MINE_LEVELS = {}
for lvl = 1, GameConfig.MINE_LEVELS_COUNT do
	local band = GameConfig.GetDepthBand(lvl)
	GameConfig.MINE_LEVELS[lvl] = {
		Name = string.format("Depth %d m · %s", lvl, band.ZoneName),
		Weights = band.Weights,
	}
end

-- ============================================================================
-- 8. 10 УРОВНЕЙ КИРОК (УРОВНИ 1–10 ДЛЯ 3D-СВАЙПА В МАГАЗИНЕ)
-- Индексы 1..10 (и совместимость с 0..9). Каждый уровень ускоряет анимацию взмаха!
-- ============================================================================
export type PickaxeTierConfig = {
	Level: number,
	Name: string,
	ShortName: string,
	Cost: number,
	Damage: number,
	BaseSwingCooldown: number,
	SwingAnimSpeed: number,    -- Скорость анимации руки и кирки (1.00 .. 1.45)
	UnlockSummary: string,
	VisualDesc: string,
	BladeColor: Color3,
	HeadMaterial: Enum.Material,
	HeadReflectance: number,
	HandleColor: Color3,
	HandleMaterial: Enum.Material,
	TrimColor: Color3,
	TrimMaterial: Enum.Material,
	GemColor: Color3,
	GemGlow: number,
	HeadScale: number,
	Glow: boolean,
	Sparkles: boolean,
	FireAura: boolean,
}

GameConfig.MAX_PICKAXE_LEVEL = 10
GameConfig.MAX_PICKAXE_TIER = 10

GameConfig.PICKAXE_TIERS = {
	[1] = {
		Level = 1, Name = "Wooden Pickaxe", ShortName = "Wooden",
		Cost = 0, Damage = 6, BaseSwingCooldown = 0.48, SwingAnimSpeed = 1.00,
		UnlockSummary = "Grass, Dirt, Clay, soft Stone",
		VisualDesc = "Oak handle and wooden head with leather wrap",
		BladeColor = Color3.fromRGB(176, 122, 72), HeadMaterial = Enum.Material.Wood, HeadReflectance = 0,
		HandleColor = Color3.fromRGB(132, 84, 46), HandleMaterial = Enum.Material.Wood,
		TrimColor = Color3.fromRGB(92, 58, 34), TrimMaterial = Enum.Material.Wood,
		GemColor = Color3.fromRGB(255, 170, 70), GemGlow = 0.08, HeadScale = 1.00,
		Glow = false, Sparkles = false, FireAura = false,
	},
	[2] = {
		Level = 2, Name = "Stone Pickaxe", ShortName = "Stone",
		Cost = 65, Damage = 11, BaseSwingCooldown = 0.46, SwingAnimSpeed = 1.04,
		UnlockSummary = "Stone and Coal seams",
		VisualDesc = "Hewn slate blade with an iron collar",
		BladeColor = Color3.fromRGB(136, 140, 150), HeadMaterial = Enum.Material.Slate, HeadReflectance = 0,
		HandleColor = Color3.fromRGB(128, 82, 46), HandleMaterial = Enum.Material.Wood,
		TrimColor = Color3.fromRGB(78, 80, 90), TrimMaterial = Enum.Material.Slate,
		GemColor = Color3.fromRGB(170, 220, 255), GemGlow = 0.15, HeadScale = 1.04,
		Glow = false, Sparkles = false, FireAura = false,
	},
	[3] = {
		Level = 3, Name = "Iron Pickaxe", ShortName = "Iron",
		Cost = 320, Damage = 18, BaseSwingCooldown = 0.44, SwingAnimSpeed = 1.08,
		UnlockSummary = "Unlocks Iron and Copper Ore",
		VisualDesc = "Forged steel head with rivets and a quartz inlay",
		BladeColor = Color3.fromRGB(145, 152, 166), HeadMaterial = Enum.Material.Metal, HeadReflectance = 0.14,
		HandleColor = Color3.fromRGB(124, 76, 42), HandleMaterial = Enum.Material.Wood,
		TrimColor = Color3.fromRGB(62, 66, 76), TrimMaterial = Enum.Material.Metal,
		GemColor = Color3.fromRGB(120, 200, 255), GemGlow = 0.25, HeadScale = 1.08,
		Glow = false, Sparkles = false, FireAura = false,
	},
	[4] = {
		Level = 4, Name = "Steel Pickaxe", ShortName = "Steel",
		Cost = 820, Damage = 24, BaseSwingCooldown = 0.42, SwingAnimSpeed = 1.12,
		UnlockSummary = "Unlocks Tin Ore and mines Copper faster",
		VisualDesc = "Heavy copper-tin alloy with a malachite crystal",
		BladeColor = Color3.fromRGB(215, 132, 68), HeadMaterial = Enum.Material.Metal, HeadReflectance = 0.20,
		HandleColor = Color3.fromRGB(108, 66, 38), HandleMaterial = Enum.Material.Wood,
		TrimColor = Color3.fromRGB(68, 125, 92), TrimMaterial = Enum.Material.Metal,
		GemColor = Color3.fromRGB(72, 225, 145), GemGlow = 0.34, HeadScale = 1.12,
		Glow = false, Sparkles = false, FireAura = false,
	},
	[5] = {
		Level = 5, Name = "Sapphire Pickaxe", ShortName = "Sapphire",
		Cost = 1950, Damage = 34, BaseSwingCooldown = 0.40, SwingAnimSpeed = 1.16,
		UnlockSummary = "Unlocks Silver and Gold Ore",
		VisualDesc = "Polished steel with gold edges and a ruby core",
		BladeColor = Color3.fromRGB(255, 198, 48), HeadMaterial = Enum.Material.Metal, HeadReflectance = 0.28,
		HandleColor = Color3.fromRGB(98, 58, 34), HandleMaterial = Enum.Material.Wood,
		TrimColor = Color3.fromRGB(196, 120, 30), TrimMaterial = Enum.Material.Metal,
		GemColor = Color3.fromRGB(255, 80, 80), GemGlow = 0.45, HeadScale = 1.16,
		Glow = true, Sparkles = false, FireAura = false,
	},
	[6] = {
		Level = 6, Name = "Crystal Pickaxe", ShortName = "Crystal",
		Cost = 5800, Damage = 48, BaseSwingCooldown = 0.38, SwingAnimSpeed = 1.22,
		UnlockSummary = "Unlocks Amethyst geodes",
		VisualDesc = "Quartz-amethyst blade with a soft glow",
		BladeColor = Color3.fromRGB(185, 95, 255), HeadMaterial = Enum.Material.Glass, HeadReflectance = 0.24,
		HandleColor = Color3.fromRGB(72, 62, 108), HandleMaterial = Enum.Material.Wood,
		TrimColor = Color3.fromRGB(210, 220, 245), TrimMaterial = Enum.Material.Metal,
		GemColor = Color3.fromRGB(225, 145, 255), GemGlow = 0.56, HeadScale = 1.20,
		Glow = true, Sparkles = false, FireAura = false,
	},
	[7] = {
		Level = 7, Name = "Amethyst Pickaxe", ShortName = "Amethyst",
		Cost = 18500, Damage = 68, BaseSwingCooldown = 0.36, SwingAnimSpeed = 1.27,
		UnlockSummary = "Unlocks Ruby and Emerald",
		VisualDesc = "Faceted emerald blade in a gold frame",
		BladeColor = Color3.fromRGB(35, 215, 110), HeadMaterial = Enum.Material.Glass, HeadReflectance = 0.22,
		HandleColor = Color3.fromRGB(54, 66, 56), HandleMaterial = Enum.Material.Wood,
		TrimColor = Color3.fromRGB(240, 200, 90), TrimMaterial = Enum.Material.Metal,
		GemColor = Color3.fromRGB(150, 255, 170), GemGlow = 0.68, HeadScale = 1.25,
		Glow = true, Sparkles = false, FireAura = false,
	},
	[8] = {
		Level = 8, Name = "Void Pickaxe", ShortName = "Void",
		Cost = 62000, Damage = 96, BaseSwingCooldown = 0.34, SwingAnimSpeed = 1.33,
		UnlockSummary = "Unlocks Sapphire and Diamond",
		VisualDesc = "Pure diamond with a blue shine",
		BladeColor = Color3.fromRGB(80, 220, 255), HeadMaterial = Enum.Material.Glass, HeadReflectance = 0.28,
		HandleColor = Color3.fromRGB(52, 74, 112), HandleMaterial = Enum.Material.Metal,
		TrimColor = Color3.fromRGB(220, 242, 255), TrimMaterial = Enum.Material.Metal,
		GemColor = Color3.fromRGB(160, 245, 255), GemGlow = 0.80, HeadScale = 1.30,
		Glow = true, Sparkles = true, FireAura = false,
	},
	[9] = {
		Level = 9, Name = "Golden Pickaxe", ShortName = "Golden",
		Cost = 210000, Damage = 138, BaseSwingCooldown = 0.32, SwingAnimSpeed = 1.39,
		UnlockSummary = "Unlocks relic Mithril at the bottom (30 m)",
		VisualDesc = "Teal-silver mithril with star sparks",
		BladeColor = Color3.fromRGB(70, 235, 225), HeadMaterial = Enum.Material.Metal, HeadReflectance = 0.35,
		HandleColor = Color3.fromRGB(44, 52, 78), HandleMaterial = Enum.Material.Metal,
		TrimColor = Color3.fromRGB(200, 255, 250), TrimMaterial = Enum.Material.Metal,
		GemColor = Color3.fromRGB(120, 255, 245), GemGlow = 0.90, HeadScale = 1.36,
		Glow = true, Sparkles = true, FireAura = false,
	},
	[10] = {
		Level = 10, Name = "Royal Gold Pickaxe", ShortName = "Royal",
		Cost = 750000, Damage = 195, BaseSwingCooldown = 0.29, SwingAnimSpeed = 1.45,
		UnlockSummary = "Maximum speed and damage on every block",
		VisualDesc = "Obsidian-gold blade with a fiery plasma aura",
		BladeColor = Color3.fromRGB(38, 32, 44), HeadMaterial = Enum.Material.Metal, HeadReflectance = 0.32,
		HandleColor = Color3.fromRGB(30, 26, 34), HandleMaterial = Enum.Material.Metal,
		TrimColor = Color3.fromRGB(255, 190, 55), TrimMaterial = Enum.Material.Neon,
		GemColor = Color3.fromRGB(255, 120, 30), GemGlow = 1.00, HeadScale = 1.42,
		Glow = true, Sparkles = true, FireAura = true,
	},
}
-- Совместимость с индексом 0
GameConfig.PICKAXE_TIERS[0] = GameConfig.PICKAXE_TIERS[1]
-- v28: pickaxe looks re-themed per the pickaxe-shop reference rarities
-- (Lv1-2 simple wood, 3-4 common steel, 5-6 rare blue crystal, 7-8 epic purple, 9-10 legendary gold)
do
	local C = Color3.fromRGB
	local M = Enum.Material
	local LOOK: { [number]: { [string]: any } } = {
		[2] = { BladeColor = C(150, 116, 84), TrimColor = C(96, 70, 46) },
		[4] = { BladeColor = C(176, 182, 194), HeadMaterial = M.Metal, HeadReflectance = 0.22, TrimColor = C(70, 74, 86), GemColor = C(200, 225, 255) },
		[5] = { BladeColor = C(64, 156, 255), HeadMaterial = M.Metal, HeadReflectance = 0.3, HandleColor = C(40, 48, 76), HandleMaterial = M.Metal, TrimColor = C(200, 214, 236), GemColor = C(150, 225, 255), GemGlow = 0.5 },
		[6] = { BladeColor = C(90, 205, 255), HeadMaterial = M.Glass, HeadReflectance = 0.26, HandleColor = C(36, 44, 78), TrimColor = C(56, 118, 210), GemColor = C(190, 245, 255), GemGlow = 0.62 },
		[7] = { BladeColor = C(166, 86, 246), HeadMaterial = M.Glass, HeadReflectance = 0.24, HandleColor = C(56, 38, 84), TrimColor = C(112, 60, 182), GemColor = C(226, 162, 255), GemGlow = 0.7 },
		[8] = { BladeColor = C(132, 58, 224), HeadMaterial = M.Metal, HeadReflectance = 0.3, HandleColor = C(40, 28, 62), HandleMaterial = M.Metal, TrimColor = C(206, 126, 255), GemColor = C(255, 122, 240), GemGlow = 0.82 },
		[9] = { BladeColor = C(250, 192, 46), HeadMaterial = M.Metal, HeadReflectance = 0.36, HandleColor = C(36, 28, 30), HandleMaterial = M.Metal, TrimColor = C(206, 140, 34), GemColor = C(255, 236, 140), GemGlow = 0.9 },
		[10] = { BladeColor = C(255, 206, 62), HeadMaterial = M.Metal, HeadReflectance = 0.42, HandleColor = C(24, 20, 26), HandleMaterial = M.Metal, TrimColor = C(255, 168, 40), GemColor = C(255, 110, 40), GemGlow = 1.0 },
	}
	for lvl, look in pairs(LOOK) do
		local t = GameConfig.PICKAXE_TIERS[lvl]
		if t then
			for k, v in pairs(look) do
				t[k] = v
			end
		end
	end
end

-- ============================================================================
-- 9. 10 УРОВНЕЙ РЮКЗАКОВ (СТРОГО ПО РЕФЕРЕНСУ «ОТ КЛАССИКИ ДО КИБЕРПАНКА»)
-- Вместимость рюкзака зависит ТОЛЬКО от купленного уровня рюкзака 1..10!
-- ============================================================================
export type BackpackTierConfig = {
	Level: number,
	Name: string,
	ShortName: string,
	Capacity: number,
	Cost: number,
	VisualDesc: string,
	Body: Color3,
	Trim: Color3,
	Fitting: Color3,
	BodyMaterial: Enum.Material,
	FittingMaterial: Enum.Material,
	Reflectance: number,
	Transparency: number,
	HasFlap: boolean,
	HasBedroll: boolean,
	HasTacticalPockets: boolean,
	EmblemType: string, -- "None" | "Plate" | "Diamond" | "Star" | "Crown" | "Magma" | "CyberWings"
	NeonSeams: boolean,
	Crystals: boolean,
}

GameConfig.MAX_BACKPACK_LEVEL = 10

GameConfig.BACKPACK_TIERS = {
	[1] = {
		Level = 1, Name = "Camo Scout Pack Lv.1", ShortName = "Scout",
		Capacity = 10, Cost = 0,
		VisualDesc = "Tan camo canvas with a buckled flap and a front pocket",
		Body = Color3.fromRGB(170, 128, 82), Trim = Color3.fromRGB(108, 74, 44), Fitting = Color3.fromRGB(192, 196, 204),
		BodyMaterial = Enum.Material.Fabric, FittingMaterial = Enum.Material.Metal,
		Reflectance = 0, Transparency = 0,
		HasFlap = true, HasBedroll = false, HasTacticalPockets = false, EmblemType = "None", NeonSeams = false, Crystals = false,
	},
	[2] = {
		Level = 2, Name = "Leather Bedroll Pack Lv.2", ShortName = "Leather",
		Capacity = 25, Cost = 80,
		VisualDesc = "Thick brown leather, side pockets and a bedroll on top",
		Body = Color3.fromRGB(126, 84, 52), Trim = Color3.fromRGB(86, 54, 32), Fitting = Color3.fromRGB(185, 188, 195),
		BodyMaterial = Enum.Material.Leather, FittingMaterial = Enum.Material.Metal,
		Reflectance = 0.02, Transparency = 0,
		HasFlap = true, HasBedroll = true, HasTacticalPockets = false, EmblemType = "None", NeonSeams = false, Crystals = false,
	},
	[3] = {
		Level = 3, Name = "Field Expedition Pack Lv.3", ShortName = "Field",
		Capacity = 45, Cost = 240,
		VisualDesc = "Olive canvas with bedroll, double straps and pouches",
		Body = Color3.fromRGB(102, 116, 68), Trim = Color3.fromRGB(72, 84, 48), Fitting = Color3.fromRGB(178, 182, 172),
		BodyMaterial = Enum.Material.Fabric, FittingMaterial = Enum.Material.Metal,
		Reflectance = 0.02, Transparency = 0,
		HasFlap = true, HasBedroll = true, HasTacticalPockets = true, EmblemType = "None", NeonSeams = false, Crystals = false,
	},
	[4] = {
		Level = 4, Name = "City Pack Lv.4", ShortName = "City",
		Capacity = 75, Cost = 680,
		VisualDesc = "Matte black zip body with a steel badge",
		Body = Color3.fromRGB(48, 52, 58), Trim = Color3.fromRGB(32, 35, 40), Fitting = Color3.fromRGB(165, 172, 184),
		BodyMaterial = Enum.Material.SmoothPlastic, FittingMaterial = Enum.Material.Metal,
		Reflectance = 0.06, Transparency = 0,
		HasFlap = false, HasBedroll = false, HasTacticalPockets = false, EmblemType = "Plate", NeonSeams = false, Crystals = false,
	},
	[5] = {
		Level = 5, Name = "Vanguard Pack Lv.5", ShortName = "Vanguard",
		Capacity = 120, Cost = 1850,
		VisualDesc = "Blue impact-proof shell with a glowing white diamond",
		Body = Color3.fromRGB(38, 108, 215), Trim = Color3.fromRGB(24, 68, 148), Fitting = Color3.fromRGB(235, 245, 255),
		BodyMaterial = Enum.Material.SmoothPlastic, FittingMaterial = Enum.Material.Neon,
		Reflectance = 0.12, Transparency = 0,
		HasFlap = false, HasBedroll = false, HasTacticalPockets = false, EmblemType = "Diamond", NeonSeams = false, Crystals = false,
	},
	[6] = {
		Level = 6, Name = "Armored Tactical Pack Lv.6", ShortName = "Tactical",
		Capacity = 180, Cost = 4900,
		VisualDesc = "Reinforced carbon pack with MOLLE straps and double locks",
		Body = Color3.fromRGB(36, 38, 44), Trim = Color3.fromRGB(22, 24, 28), Fitting = Color3.fromRGB(128, 134, 145),
		BodyMaterial = Enum.Material.Metal, FittingMaterial = Enum.Material.Metal,
		Reflectance = 0.14, Transparency = 0,
		HasFlap = false, HasBedroll = false, HasTacticalPockets = true, EmblemType = "Plate", NeonSeams = false, Crystals = false,
	},
	[7] = {
		Level = 7, Name = "North Star Cyber Pack Lv.7", ShortName = "North Star",
		Capacity = 270, Cost = 13500,
		VisualDesc = "White titanium plates with a neon star core",
		Body = Color3.fromRGB(218, 224, 234), Trim = Color3.fromRGB(38, 42, 52), Fitting = Color3.fromRGB(45, 195, 255),
		BodyMaterial = Enum.Material.SmoothPlastic, FittingMaterial = Enum.Material.Neon,
		Reflectance = 0.18, Transparency = 0,
		HasFlap = false, HasBedroll = false, HasTacticalPockets = true, EmblemType = "Star", NeonSeams = true, Crystals = false,
	},
	[8] = {
		Level = 8, Name = "Neon Crown Pack Lv.8", ShortName = "Crown",
		Capacity = 400, Cost = 38000,
		VisualDesc = "Dark purple cyber case with neon edges and a crown emblem",
		Body = Color3.fromRGB(34, 28, 48), Trim = Color3.fromRGB(22, 18, 34), Fitting = Color3.fromRGB(168, 65, 255),
		BodyMaterial = Enum.Material.SmoothPlastic, FittingMaterial = Enum.Material.Neon,
		Reflectance = 0.16, Transparency = 0,
		HasFlap = false, HasBedroll = false, HasTacticalPockets = true, EmblemType = "Crown", NeonSeams = true, Crystals = false,
	},
	[9] = {
		Level = 9, Name = "Volcanic Exo Pack Lv.9", ShortName = "Volcanic",
		Capacity = 620, Cost = 110000,
		VisualDesc = "Faceted basalt armor with glowing red energy lines",
		Body = Color3.fromRGB(28, 26, 30), Trim = Color3.fromRGB(18, 16, 20), Fitting = Color3.fromRGB(255, 42, 32),
		BodyMaterial = Enum.Material.Basalt, FittingMaterial = Enum.Material.Neon,
		Reflectance = 0.20, Transparency = 0,
		HasFlap = false, HasBedroll = false, HasTacticalPockets = true, EmblemType = "Magma", NeonSeams = true, Crystals = true,
	},
	[10] = {
		Level = 10, Name = "Quantum Cyber Pack Lv.10", ShortName = "Quantum",
		Capacity = 1000, Cost = 340000,
		VisualDesc = "Futuristic reactor pack with 4 crystal energy wings",
		Body = Color3.fromRGB(24, 30, 42), Trim = Color3.fromRGB(14, 18, 28), Fitting = Color3.fromRGB(0, 225, 255),
		BodyMaterial = Enum.Material.Metal, FittingMaterial = Enum.Material.Neon,
		Reflectance = 0.25, Transparency = 0,
		HasFlap = false, HasBedroll = false, HasTacticalPockets = true, EmblemType = "CyberWings", NeonSeams = true, Crystals = true,
	},
}

function GameConfig.GetBackpackStyle(level: number): BackpackTierConfig
	local cl = math.clamp(math.floor(level), 1, GameConfig.MAX_BACKPACK_LEVEL)
	return GameConfig.BACKPACK_TIERS[cl] or GameConfig.BACKPACK_TIERS[1]
end

function GameConfig.GetBackpackScale(level: number): number
	local cl = math.clamp(math.floor(level), 1, GameConfig.MAX_BACKPACK_LEVEL)
	return 0.94 + (cl - 1) * 0.022
end

GameConfig.MESH_ASSETS_FOLDER = "Assets"
GameConfig.BASE_BACKPACK_SLOTS = 10   -- стартовый рюкзак: РОВНО 10 слотов
GameConfig.BASE_STRENGTH = 1

function GameConfig.CalculateHitDamage(pickaxeLevel: number, strength: number): number
	local cl = math.clamp(math.floor(pickaxeLevel), 1, GameConfig.MAX_PICKAXE_LEVEL)
	local tierCfg = GameConfig.PICKAXE_TIERS[cl] or GameConfig.PICKAXE_TIERS[1]
	local strBonus = math.floor(math.max(0, strength - 1) / 3)
	return tierCfg.Damage + strBonus
end

-- Вместимость зависит ТОЛЬКО от купленного и надетого рюкзака (1..10 ур.)!
function GameConfig.CalculateMaxBackpack(backpackLevel: number): number
	local style = GameConfig.GetBackpackStyle(backpackLevel)
	return style.Capacity
end

function GameConfig.GetRequiredLevelXP(level: number): number
	return math.max(1, math.floor(level)) * 100
end

function GameConfig.GetRequiredStrengthXP(strength: number): number
	return math.floor(35 * (math.max(1, strength) ^ 1.18))
end

-- ============================================================================
-- v32: BACKPACK DIRT — 5 states (exactly like the reference)
--   0 Clean            : 0..19 blocks   -> 0% slots lost
--   1 Slightly Dirty   : 20+ blocks     -> -10% slots
--   2 Dirty            : 50+ blocks     -> -20% slots
--   3 Very Dirty       : 100+ blocks    -> -30% slots
--   4 Extremely Dirty  : 300+ blocks    -> -40% slots
-- Counter = blocks mined since the last cleaning (saved in DataStore).
-- Cleaning: ONLY at night — buy the Repair Kit from the Night Merchant.
-- ============================================================================
GameConfig.BACKPACK_DIRT = {
	CleanCooldown = 2.0,
	RepairKitPrice = 85,
	MaxBlocks = 300,
	Stages = {
		{ Blocks = 20,  Penalty = 0.10, Name = "Slightly Dirty",  Color = Color3.fromRGB(190, 200, 110) },
		{ Blocks = 50,  Penalty = 0.20, Name = "Dirty",           Color = Color3.fromRGB(160, 175, 80) },
		{ Blocks = 100, Penalty = 0.30, Name = "Very Dirty",      Color = Color3.fromRGB(125, 150, 55) },
		{ Blocks = 300, Penalty = 0.40, Name = "Extremely Dirty", Color = Color3.fromRGB(95, 125, 40) },
	},
	CleanName = "Clean",
	CleanColor = Color3.fromRGB(140, 230, 255),
}

function GameConfig.GetDirtStage(blocks: number): number
	local b = math.max(0, math.floor(tonumber(blocks) or 0))
	local stage = 0
	for i, st in ipairs(GameConfig.BACKPACK_DIRT.Stages) do
		if b >= st.Blocks then stage = i end
	end
	return stage
end

function GameConfig.GetDirtPenalty(blocks: number): number
	local st = GameConfig.BACKPACK_DIRT.Stages[GameConfig.GetDirtStage(blocks)]
	return st and st.Penalty or 0
end

function GameConfig.GetDirtStageName(stage: number): string
	local st = GameConfig.BACKPACK_DIRT.Stages[math.floor(tonumber(stage) or 0)]
	return st and st.Name or GameConfig.BACKPACK_DIRT.CleanName
end

function GameConfig.GetDirtStageColor(stage: number): Color3
	local st = GameConfig.BACKPACK_DIRT.Stages[math.floor(tonumber(stage) or 0)]
	return st and st.Color or GameConfig.BACKPACK_DIRT.CleanColor
end

-- 0..100 (for bars): 300 blocks = 100%
function GameConfig.GetDirtPercent(blocks: number): number
	local b = math.clamp(math.floor(tonumber(blocks) or 0), 0, GameConfig.BACKPACK_DIRT.MaxBlocks)
	return math.floor(b / GameConfig.BACKPACK_DIRT.MaxBlocks * 100)
end

-- Next threshold (nil when already at the last stage)
function GameConfig.GetNextDirtThreshold(blocks: number): number?
	local st = GameConfig.BACKPACK_DIRT.Stages[GameConfig.GetDirtStage(blocks) + 1]
	return st and st.Blocks or nil
end

function GameConfig.CalculateEffectiveBackpack(level: number, dirtBlocks: number): number
	local cap = GameConfig.CalculateMaxBackpack(level)
	local lost = math.floor(cap * GameConfig.GetDirtPenalty(dirtBlocks) + 0.5)
	return math.max(1, cap - lost)
end

-- kept for old callers: cleaning is a fixed-price Night Merchant item now
function GameConfig.GetCleanCost(_level: number, _dirt: number): number
	return GameConfig.BACKPACK_DIRT.RepairKitPrice
end

-- v32: Night Merchant food supplies (burgers are stored and eaten any time)
GameConfig.FOOD = {
	Price = 45,
	MaxStock = 20,
	EatCooldown = 1.0,
	Key = "H",
}

