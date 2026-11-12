--!strict
-- ============================================================================
-- 🌟 МОДУЛЬ: ProgressionConfig (ReplicatedStorage.Modules.ProgressionConfig)
-- Версия: v13.0 — Выполнены Пункты №4, №6 и №8:
-- • УБРАНА «Вместимость рюкзака» из навыков (вместимость зависит ТОЛЬКО от купленного
--   рюкзака 1–10 уровня в Магазине).
-- • ДОБАВЛЕН навык «ЭНЕРГИЯ» (⚡): увеличивает макс. запас энергии (+12 ед./ур.)
--   и скорость восстановления энергии (+0.35 ед./сек за уровень).
-- • ТРЕНИРОВКА СИЛЫ («СИЛА» 💪) находится ТОЛЬКО в Навыках (убрана из Магазина).
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local ProgressionConfig = {}

ProgressionConfig.START_LEVEL = 1
ProgressionConfig.XP_PER_LEVEL = 100
ProgressionConfig.SKILL_POINTS_PER_LEVEL = 1
ProgressionConfig.LEVEL_UP_COINS_PER_LEVEL = 10
ProgressionConfig.LEVEL_UP_HEAL = true

ProgressionConfig.SOUNDS = {
	LevelUp     = { Id = "rbxassetid://1845399641", Volume = 0.45 }, -- старый звук (больше не играет)
	-- v47: мягкое арпеджио из «колокольчика» вместо резкого звука
	LevelUpChime = { Id = "rbxassetid://9113728756", Volume = 0.22 },
	-- Свой звук: загрузи LevelUp_Chime.ogg и вставь ID, например "rbxassetid://123"
	LevelUpCustom = { Id = "rbxassetid://135458320667545", Volume = 0.5 }, -- v48: звук игрока
	Click       = { Id = "rbxassetid://12221976",   Volume = 0.10 },
	Achievement = { Id = "rbxassetid://1839901345", Volume = 0.07 }, -- тихий мягкий сигнал (было 0.40)
	Prestige    = { Id = "rbxassetid://1845411858", Volume = 0.50 },
}

function ProgressionConfig.GetRequiredXP(level: number): number
	return math.max(1, math.floor(level)) * ProgressionConfig.XP_PER_LEVEL
end

-- ============================================================================
-- 2. НАВЫКИ ПЕРСОНАЖА (БЕЗ ВМЕСТИМОСТИ РЮКЗАКА! ЭНЕРГИЯ + ТРЕНИРОВКА СИЛЫ)
-- ============================================================================
ProgressionConfig.SKILL_MAX_LEVEL = 50
ProgressionConfig.CRIT_MULTIPLIER = 3
ProgressionConfig.BASE_ATTACK_COOLDOWN = 0.44
ProgressionConfig.MIN_ATTACK_COOLDOWN = 0.20

export type SkillInfo = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	PerLevel: number,
	Suffix: string,
	Color: Color3,
	ColorDark: Color3,
}

-- Порядок навыков в окне «⚡ Навыки»: Энергия и Тренировка Силы на первом плане!
ProgressionConfig.SKILL_ORDER = { "Energy", "Power", "Speed", "Luck", "Critical" }

ProgressionConfig.SKILLS = {
	Energy = {
		Id = "Energy", Name = "ENERGY", Icon = "⚡",
		Description = "Max energy (+12) and regen (+0.35/s per level)",
		PerLevel = 12, Suffix = " energy",
		Color = Color3.fromRGB(55, 225, 145), ColorDark = Color3.fromRGB(18, 115, 68),
	},
	Power = {
		Id = "Power", Name = "STRENGTH", Icon = "💪",
		Description = "Pickaxe damage to blocks",
		PerLevel = 5, Suffix = "% damage",
		Color = Color3.fromRGB(255, 125, 55), ColorDark = Color3.fromRGB(150, 42, 18),
	},
	Speed = {
		Id = "Speed", Name = "MINING SPEED", Icon = "⛏️",
		Description = "Pickaxe swing rate",
		PerLevel = 2, Suffix = "% faster",
		Color = Color3.fromRGB(255, 215, 60), ColorDark = Color3.fromRGB(165, 105, 12),
	},
	Luck = {
		Id = "Luck", Name = "GEOLOGIST (LUCK)", Icon = "🍀",
		Description = "Chance to find an extra nugget",
		PerLevel = 1.5, Suffix = "% chance",
		Color = Color3.fromRGB(70, 200, 255), ColorDark = Color3.fromRGB(20, 80, 170),
	},
	Critical = {
		Id = "Critical", Name = "PRECISE HIT (CRIT)", Icon = "🔥",
		Description = "Critical hit chance (×3 damage)",
		PerLevel = 1, Suffix = "% crit",
		Color = Color3.fromRGB(200, 90, 255), ColorDark = Color3.fromRGB(90, 25, 160),
	},
} :: { [string]: SkillInfo }

-- ============================================================================
-- 3. ПРЕСТИЖ И ДОСТИЖЕНИЯ
-- ============================================================================
ProgressionConfig.PRESTIGE_REQUIRED_LEVEL = 50
ProgressionConfig.PRESTIGE_MAX = 10
ProgressionConfig.PRESTIGE_BONUS = 0.10
ProgressionConfig.PRESTIGE_RESETS_SKILLS = false

export type AuraInfo = {
	MinPrestige: number,
	Name: string,
	Colors: { Color3 },
	Rainbow: boolean,
}

ProgressionConfig.PRESTIGE_AURAS = {
	{ MinPrestige = 1, Name = "Golden",  Rainbow = false, Colors = { Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 170, 30) } },
	{ MinPrestige = 4, Name = "Diamond", Rainbow = false, Colors = { Color3.fromRGB(170, 250, 255), Color3.fromRGB(60, 190, 255) } },
	{ MinPrestige = 7, Name = "Rainbow", Rainbow = true, Colors = {
		Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 200, 50), Color3.fromRGB(80, 255, 110),
		Color3.fromRGB(60, 190, 255), Color3.fromRGB(190, 90, 255),
	} },
} :: { AuraInfo }

function ProgressionConfig.GetAura(prestige: number): AuraInfo?
	local found: AuraInfo? = nil
	for _, aura in ipairs(ProgressionConfig.PRESTIGE_AURAS) do
		if prestige >= aura.MinPrestige then
			found = aura
		end
	end
	return found
end

export type AchievementInfo = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Stat: string,
	Goal: number,
	RewardCoins: number,
	RewardSkillPoints: number,
}

-- v51: the coin rewards of the early goals are small on purpose (ore near the surface sells
-- for 1–2 coins); the five original achievements keep their original rewards. Depth goals down
-- to 25 m pay almost nothing: plain stone goes that deep, so a starter pickaxe gets there fast.
-- v50: a long ladder of small goals. The ORDER matters: the HUD "Next goal" tracker
-- always shows the first one that is not finished yet, so keep it easy -> hard.
-- Stats: TotalMined, PeakCoins, OresFound, MaxDepth, BestCombo, LuckyOpened,
-- TntExploded, TreasuresFound, DailyStreak (see ProgressionManager.GetStatValue).
ProgressionConfig.ACHIEVEMENTS = {
	{ Id = "FirstSteps", Name = "First Steps",      Icon = "👣", Description = "Break 15 blocks",              Stat = "TotalMined",     Goal = 15,     RewardCoins = 40,    RewardSkillPoints = 1 },
	{ Id = "Depth3",     Name = "Digging Down",     Icon = "⬇️", Description = "Dig down to 3 m",              Stat = "MaxDepth",       Goal = 3,      RewardCoins = 5,     RewardSkillPoints = 0 },
	{ Id = "Combo5",     Name = "Combo Starter",    Icon = "🔥", Description = "Get a 5-block combo",          Stat = "BestCombo",      Goal = 5,      RewardCoins = 5,     RewardSkillPoints = 0 },
	{ Id = "Found4",     Name = "Rock Spotter",     Icon = "🔍", Description = "Find 4 kinds of blocks",       Stat = "OresFound",      Goal = 4,      RewardCoins = 5,     RewardSkillPoints = 0 },
	{ Id = "Mined50",    Name = "Busy Miner",       Icon = "⛏️", Description = "Break 50 blocks",              Stat = "TotalMined",     Goal = 50,     RewardCoins = 10,    RewardSkillPoints = 0 },
	{ Id = "Lucky1",     Name = "Lucky Find",       Icon = "🍀", Description = "Open a Lucky Block",           Stat = "LuckyOpened",    Goal = 1,      RewardCoins = 5,     RewardSkillPoints = 0 },
	{ Id = "Depth6",     Name = "Cave Explorer",    Icon = "🔦", Description = "Dig down to 6 m",              Stat = "MaxDepth",       Goal = 6,      RewardCoins = 5,     RewardSkillPoints = 0 },
	{ Id = "Miner",      Name = "Miner",            Icon = "⛏️", Description = "Break 150 blocks",             Stat = "TotalMined",     Goal = 150,    RewardCoins = 250,   RewardSkillPoints = 1 },
	{ Id = "Tnt1",       Name = "Kaboom!",          Icon = "💥", Description = "Blow up a TNT block",          Stat = "TntExploded",    Goal = 1,      RewardCoins = 5,     RewardSkillPoints = 0 },
	{ Id = "Coins500",   Name = "Piggy Bank",       Icon = "🐷", Description = "Save up 500 coins",            Stat = "PeakCoins",      Goal = 500,    RewardCoins = 0,     RewardSkillPoints = 1 },
	{ Id = "Combo10",    Name = "Combo Pro",        Icon = "🔥", Description = "Get a 10-block combo",         Stat = "BestCombo",      Goal = 10,     RewardCoins = 10,    RewardSkillPoints = 0 },
	{ Id = "Treasure1",  Name = "Treasure Hunter",  Icon = "🧰", Description = "Find a Treasure Chest",        Stat = "TreasuresFound", Goal = 1,      RewardCoins = 10,    RewardSkillPoints = 0 },
	{ Id = "Depth10",    Name = "Deep Diver",       Icon = "🤿", Description = "Dig down to 10 m",             Stat = "MaxDepth",       Goal = 10,     RewardCoins = 5,     RewardSkillPoints = 0 },
	{ Id = "Mined400",   Name = "Tunnel Maker",     Icon = "🚇", Description = "Break 400 blocks",             Stat = "TotalMined",     Goal = 400,    RewardCoins = 100,   RewardSkillPoints = 1 },
	{ Id = "Found8",     Name = "Rock Collector",   Icon = "🪨", Description = "Find 8 kinds of blocks",       Stat = "OresFound",      Goal = 8,      RewardCoins = 40,    RewardSkillPoints = 1 },
	{ Id = "Streak3",    Name = "Daily Visitor",    Icon = "📅", Description = "Play 3 days in a row",         Stat = "DailyStreak",    Goal = 3,      RewardCoins = 50,    RewardSkillPoints = 1 },
	{ Id = "Combo25",    Name = "Combo Master",     Icon = "🔥", Description = "Get a 25-block combo",         Stat = "BestCombo",      Goal = 25,     RewardCoins = 20,    RewardSkillPoints = 1 },
	{ Id = "Master",     Name = "Deep Master",      Icon = "🏅", Description = "Break 1000 blocks",            Stat = "TotalMined",     Goal = 1000,   RewardCoins = 2500,  RewardSkillPoints = 3 },
	{ Id = "Depth15",    Name = "Iron Depths",      Icon = "⚙️", Description = "Dig down to 15 m",             Stat = "MaxDepth",       Goal = 15,     RewardCoins = 5,     RewardSkillPoints = 0 },
	{ Id = "Rich",       Name = "Ore Trader",       Icon = "💰", Description = "Save up 10,000 coins",         Stat = "PeakCoins",      Goal = 10000,  RewardCoins = 0,     RewardSkillPoints = 3 },
	{ Id = "Lucky10",    Name = "Lucky Streak",     Icon = "🍀", Description = "Open 10 Lucky Blocks",         Stat = "LuckyOpened",    Goal = 10,     RewardCoins = 100,   RewardSkillPoints = 1 },
	{ Id = "Tnt10",      Name = "Demolition Expert", Icon = "💥", Description = "Blow up 10 TNT blocks",       Stat = "TntExploded",    Goal = 10,     RewardCoins = 100,   RewardSkillPoints = 1 },
	{ Id = "Depth20",    Name = "Magma Zone",       Icon = "🌋", Description = "Dig down to 20 m",             Stat = "MaxDepth",       Goal = 20,     RewardCoins = 10,    RewardSkillPoints = 0 },
	{ Id = "Found12",    Name = "Gem Finder",       Icon = "💠", Description = "Find 12 kinds of blocks",      Stat = "OresFound",      Goal = 12,     RewardCoins = 300,   RewardSkillPoints = 2 },
	{ Id = "Streak7",    Name = "Loyal Miner",      Icon = "📅", Description = "Play 7 days in a row",         Stat = "DailyStreak",    Goal = 7,      RewardCoins = 200,   RewardSkillPoints = 2 },
	{ Id = "Mined2500",  Name = "Mega Miner",       Icon = "🏆", Description = "Break 2,500 blocks",           Stat = "TotalMined",     Goal = 2500,   RewardCoins = 2000,  RewardSkillPoints = 2 },
	{ Id = "Depth25",    Name = "Silver Hunter",    Icon = "🥈", Description = "Dig down to 25 m",             Stat = "MaxDepth",       Goal = 25,     RewardCoins = 10,    RewardSkillPoints = 0 },
	{ Id = "Combo50",    Name = "Unstoppable",      Icon = "🔥", Description = "Get a 50-block combo",         Stat = "BestCombo",      Goal = 50,     RewardCoins = 50,    RewardSkillPoints = 2 },
	{ Id = "Coins100k",  Name = "Gold Tycoon",      Icon = "👑", Description = "Save up 100,000 coins",        Stat = "PeakCoins",      Goal = 100000, RewardCoins = 0,     RewardSkillPoints = 3 },
	{ Id = "Depth30",    Name = "Bottom of the World", Icon = "🌍", Description = "Reach the bottom: 30 m",    Stat = "MaxDepth",       Goal = 30,     RewardCoins = 3000,  RewardSkillPoints = 5 },
	{ Id = "Collector",  Name = "Geologist",        Icon = "💎", Description = "Find all 16 block kinds",      Stat = "OresFound",      Goal = -1,     RewardCoins = 5000,  RewardSkillPoints = 5 },
	{ Id = "Mined5000",  Name = "Legend of the Mine", Icon = "🌟", Description = "Break 5,000 blocks",         Stat = "TotalMined",     Goal = 5000,   RewardCoins = 6000,  RewardSkillPoints = 5 },
} :: { AchievementInfo }

function ProgressionConfig.GetAchievementGoal(ach: AchievementInfo): number
	if ach.Goal < 0 then
		return #GameConfig.BLOCK_LIST
	end
	return ach.Goal
end

-- ============================================================================
-- 4. РАСЧЁТ БОНУСОВ НАВЫКОВ
-- ============================================================================
function ProgressionConfig.GetSkillLevel(skills: { [string]: number }?, skillId: string): number
	if not skills then return 0 end
	return math.clamp(math.floor(skills[skillId] or 0), 0, ProgressionConfig.SKILL_MAX_LEVEL)
end

function ProgressionConfig.GetSkillBonus(skillId: string, level: number): number
	local info = ProgressionConfig.SKILLS[skillId]
	if not info then return 0 end
	return info.PerLevel * level
end

function ProgressionConfig.GetPrestigeMultiplier(prestige: number): number
	return 1 + ProgressionConfig.PRESTIGE_BONUS * math.clamp(prestige, 0, ProgressionConfig.PRESTIGE_MAX)
end

-- Энергия: +12 к макс. энергии и +0.35/с к регенерации за уровень навыка Energy
function ProgressionConfig.GetMaxEnergyBonus(skills: { [string]: number }?): number
	local eLvl = ProgressionConfig.GetSkillLevel(skills, "Energy")
	return eLvl * GameConfig.ENERGY.PerSkillLevelMaxBonus
end

function ProgressionConfig.GetEnergyRegenBonus(skills: { [string]: number }?): number
	local eLvl = ProgressionConfig.GetSkillLevel(skills, "Energy")
	return eLvl * GameConfig.ENERGY.PerSkillLevelRegenBonus
end

function ProgressionConfig.GetDamageMultiplier(skills: { [string]: number }?, prestige: number): number
	local power = ProgressionConfig.GetSkillLevel(skills, "Power")
	return (1 + 0.05 * power) * ProgressionConfig.GetPrestigeMultiplier(prestige)
end

function ProgressionConfig.GetAttackCooldown(skills: { [string]: number }?, prestige: number): number
	local speed = ProgressionConfig.GetSkillLevel(skills, "Speed")
	local cd = ProgressionConfig.BASE_ATTACK_COOLDOWN / ((1 + 0.02 * speed) * ProgressionConfig.GetPrestigeMultiplier(prestige))
	return math.max(ProgressionConfig.MIN_ATTACK_COOLDOWN, cd)
end

-- Вместимость из навыков ВСЕГДА 0 (Пункт №4 ТЗ: вместимость только от рюкзака 1–10 ур.)
function ProgressionConfig.GetCapacityBonus(_skills: { [string]: number }?): number
	return 0
end

function ProgressionConfig.GetLuckChance(skills: { [string]: number }?, prestige: number): number
	local luck = ProgressionConfig.GetSkillLevel(skills, "Luck")
	return math.clamp(0.015 * luck * ProgressionConfig.GetPrestigeMultiplier(prestige), 0, 0.75)
end

function ProgressionConfig.GetCritChance(skills: { [string]: number }?): number
	local crit = ProgressionConfig.GetSkillLevel(skills, "Critical")
	return math.clamp(0.01 * crit, 0, 0.50)
end

function ProgressionConfig.GetXPMultiplier(prestige: number): number
	return ProgressionConfig.GetPrestigeMultiplier(prestige)
end

function ProgressionConfig.GetCoinMultiplier(prestige: number): number
	return ProgressionConfig.GetPrestigeMultiplier(prestige)
end

return ProgressionConfig
