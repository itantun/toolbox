--!strict
-- ============================================================================
-- 💾 МОДУЛЬ: DataManager (ServerScriptService.Modules.DataManager)
-- Версия: v13.0 — Выполняет Пункты №2, №4, №5, №6, №7, №8, №9 и №13:
-- • Кирки 1–10 уровня и Рюкзаки 1–10 уровня (покупка и экипировка в 3D-Магазине).
-- • Вместимость рюкзака зависит ТОЛЬКО от купленного рюкзака (1..10 ур.).
-- • Навык «Энергия» увеличивает макс. энергию (+12/ур.) и регенерацию (+0.35/с за ур.).
-- • Раздельный учёт обычной руды (Inventory) и Утренних Залежей ×3 (MorningInventory).
-- • Серверная продажа руды: «Продать всё» и «Продать выбранное» с проверкой дистанции
--   до зоны приёма руды "$ SELL", проверкой реального наличия в инвентаре и защитой от дюпа!
-- ============================================================================

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))
local VFXModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("VFXModule"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProgressionConfig"))
local ProgressionManager = require(script.Parent:WaitForChild("ProgressionManager"))
local BoostService = require(script.Parent:WaitForChild("BoostService")) -- v52: бусты торговца

local DataManager = {}
local DefaultSyncRemote: RemoteEvent? = nil
local rng = Random.new()

function DataManager.SetSyncRemote(remote: RemoteEvent)
	DefaultSyncRemote = remote
end

export type PlayerProfile = {
	Coins: number,
	Level: number,
	XP: number,
	Strength: number,
	StrengthXP: number,
	Energy: number,
	MaxEnergy: number,
	PickaxeTier: number,                   -- 1..10
	UnlockedPickaxes: { [number]: boolean },
	BackpackLevel: number,                 -- 1..10
	UnlockedBackpacks: { [number]: boolean },
	TotalMined: number,
	MaxDepthReached: number,
	Inventory: { [string]: number },        -- Обычная руда
	MorningInventory: { [string]: number }, -- Утренние залежи (цена ×3)
	SkillPoints: number,
	Skills: { [string]: number },
	Prestige: number,
	Achievements: { [string]: boolean },
	FoundOres: { [string]: boolean },
	PeakCoins: number,
	BackpackDirt: number, -- 0..100 % (derived from DirtBlocks, for bars)
	DirtBlocks: number, -- v32: blocks mined since last cleaning
	FoodStock: number, -- v32: burgers in supplies
	-- v50: fun stats (achievements) and the daily reward streak
	BestCombo: number,
	LuckyOpened: number,
	TntExploded: number,
	TreasuresFound: number,
	DailyStreak: number,
	LastDailyDay: number, -- UTC day number of the last claimed daily reward
	LoadFailed: boolean?, -- the save could not be read: never write this profile back
}

local Profiles: { [number]: PlayerProfile } = {}
local SellDebounce: { [number]: number } = {}
local ShopDebounce: { [number]: number } = {}

local okStore, ProfileStore = pcall(function()
	return DataStoreService:GetDataStore("MinerSimulator_Save_v13")
end)

local function createDefaultProfile(): PlayerProfile
	local inv: { [string]: number } = {}
	local morningInv: { [string]: number } = {}
	for _, b in ipairs(GameConfig.BLOCK_LIST) do
		inv[b.Id] = 0
		morningInv[b.Id] = 0
	end
	local prog = ProgressionManager.CreateDefaultData()
	return {
		Coins = 0,
		Level = 1,
		XP = 0,
		Strength = GameConfig.BASE_STRENGTH,
		StrengthXP = 0,
		Energy = GameConfig.ENERGY.BaseMax,
		MaxEnergy = GameConfig.ENERGY.BaseMax,
		PickaxeTier = 1, -- Уровень 1 (Деревянная кирка)
		UnlockedPickaxes = { [1] = true },
		BackpackLevel = 1, -- Уровень 1 (Холщовый ранец)
		UnlockedBackpacks = { [1] = true },
		TotalMined = 0,
		MaxDepthReached = 0,
		Inventory = inv,
		MorningInventory = morningInv,
		SkillPoints = prog.SkillPoints,
		Skills = prog.Skills,
		Prestige = prog.Prestige,
		Achievements = prog.Achievements,
		FoundOres = prog.FoundOres,
		PeakCoins = prog.PeakCoins,
		BackpackDirt = 0,
		DirtBlocks = 0,
		FoodStock = 0,
		BestCombo = 0,
		LuckyOpened = 0,
		TntExploded = 0,
		TreasuresFound = 0,
		DailyStreak = 0,
		LastDailyDay = 0,
	}
end

function DataManager.GetProfile(player: Player): PlayerProfile?
	return Profiles[player.UserId]
end

function DataManager.GetPickaxeTier(player: Player): number
	local profile = Profiles[player.UserId]
	return profile and math.clamp(profile.PickaxeTier, 1, GameConfig.MAX_PICKAXE_LEVEL) or 1
end

-- ПУНКТ №6 ТЗ: Максимум энергии зависит от навыка «Энергия» (+12 ед./ур.)
function DataManager.GetMaxEnergy(player: Player): number
	local profile = Profiles[player.UserId]
	if not profile then return GameConfig.ENERGY.BaseMax end
	return GameConfig.ENERGY.BaseMax + ProgressionConfig.GetMaxEnergyBonus(profile.Skills)
end

function DataManager.GetEnergyRegenPerSec(player: Player, onSurfaceOrRest: boolean): number
	local profile = Profiles[player.UserId]
	local base = onSurfaceOrRest and GameConfig.ENERGY.SurfaceRestRegenPerSec or GameConfig.ENERGY.PassiveRegenPerSec
	if not profile then return base end
	return base + ProgressionConfig.GetEnergyRegenBonus(profile.Skills)
end

function DataManager.TryConsumeEnergy(player: Player, cost: number): (boolean, number)
	local profile = Profiles[player.UserId]
	if not profile then return false, 0 end
	profile.MaxEnergy = DataManager.GetMaxEnergy(player)
	if profile.Energy < cost then
		return false, profile.Energy
	end
	profile.Energy = math.max(0, profile.Energy - cost)
	return true, profile.Energy
end

function DataManager.GetBackpackUsed(player: Player): number
	local profile = Profiles[player.UserId]
	if not profile then return 0 end
	local sum = 0
	for _, cnt in pairs(profile.Inventory) do
		if cnt > 0 then sum += cnt end
	end
	for _, cnt in pairs(profile.MorningInventory) do
		if cnt > 0 then sum += cnt end
	end
	return sum
end

-- ПУНКТ №4 ТЗ: Вместимость определяется ТОЛЬКО текущим надетым рюкзаком (1..10 ур.)!
function DataManager.GetMaxBackpack(player: Player): number
	local profile = Profiles[player.UserId]
	if not profile then return GameConfig.BASE_BACKPACK_SLOTS end
	return GameConfig.CalculateEffectiveBackpack(profile.BackpackLevel, profile.DirtBlocks or 0)
end

function DataManager.GetHitDamage(player: Player): number
	local profile = Profiles[player.UserId]
	if not profile then return 6 end
	local base = GameConfig.CalculateHitDamage(profile.PickaxeTier, profile.Strength)
	return math.max(1, math.floor(base * ProgressionConfig.GetDamageMultiplier(profile.Skills, profile.Prestige) + 0.5))
end

function DataManager.RollHitDamage(player: Player): (number, boolean)
	local profile = Profiles[player.UserId]
	local damage = DataManager.GetHitDamage(player)
	if profile and rng:NextNumber() < ProgressionConfig.GetCritChance(profile.Skills) then
		return damage * ProgressionConfig.CRIT_MULTIPLIER, true
	end
	return damage, false
end

function DataManager.GetAttackCooldown(player: Player): number
	local profile = Profiles[player.UserId]
	if not profile then return 0.48 end
	local tierCfg = GameConfig.PICKAXE_TIERS[profile.PickaxeTier] or GameConfig.PICKAXE_TIERS[1]
	local baseCd = tierCfg.BaseSwingCooldown or 0.45
	local speedSkill = ProgressionConfig.GetSkillLevel(profile.Skills, "Speed")
	local mult = (1 + 0.02 * speedSkill) * ProgressionConfig.GetPrestigeMultiplier(profile.Prestige)
	-- v52: буст «Скорость» ускоряет удар (и опускает нижний предел кулдауна)
	local boost = BoostService.GetMultiplier(player, "MineSpeed")
	return math.clamp(baseCd / (mult * boost), 0.20 / boost, 0.60)
end

function DataManager.GetBackpackSellValue(player: Player): number
	local profile = Profiles[player.UserId]
	if not profile then return 0 end
	local total = 0
	for bId, cnt in pairs(profile.Inventory) do
		local info = GameConfig.BLOCK_TYPES[bId]
		if info and cnt > 0 then
			total += info.SellPrice * cnt
		end
	end
	for bId, cnt in pairs(profile.MorningInventory) do
		local info = GameConfig.BLOCK_TYPES[bId]
		if info and cnt > 0 then
			total += (info.SellPrice * GameConfig.MORNING_VEINS.SellPriceMultiplier) * cnt
		end
	end
	return math.floor(total * ProgressionConfig.GetCoinMultiplier(profile.Prestige) + 0.5)
end

function DataManager.UpdateLeaderstats(player: Player)
	local profile = Profiles[player.UserId]
	if not profile then return end

	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local lvl = ls:FindFirstChild("Level") :: IntValue?
		local str = ls:FindFirstChild("Strength") :: IntValue?
		local coins = ls:FindFirstChild("Coins") :: IntValue?
		local mined = ls:FindFirstChild("Mined") :: IntValue?
		if lvl then lvl.Value = profile.Level end
		if str then str.Value = profile.Strength end
		if coins then coins.Value = profile.Coins end
		if mined then mined.Value = profile.TotalMined end
	end
end

function DataManager.UpdateBagAttributes(player: Player)
	local profile = Profiles[player.UserId]
	if not profile then return end
	player:SetAttribute("BagUsed", DataManager.GetBackpackUsed(player))
	player:SetAttribute("BagMax", DataManager.GetMaxBackpack(player))
	player:SetAttribute("BagMaxBase", GameConfig.CalculateMaxBackpack(profile.BackpackLevel))
	local dirtBlocks = math.floor(profile.DirtBlocks or 0)
	profile.BackpackDirt = GameConfig.GetDirtPercent(dirtBlocks)
	player:SetAttribute("BagDirt", profile.BackpackDirt)
	player:SetAttribute("BagDirtBlocks", dirtBlocks)
	player:SetAttribute("BagDirtStage", GameConfig.GetDirtStage(dirtBlocks))
	player:SetAttribute("FoodStock", math.floor(profile.FoodStock or 0))
	player:SetAttribute("PickaxeTier", profile.PickaxeTier)
	player:SetAttribute("BackpackLevel", profile.BackpackLevel)
end

-- v52: список купленных уровней массивом — разреженная таблица { [1] = true, [3] = true }
-- при передаче через RemoteEvent обрезается на первом пропуске
local function ownedLevels(unlocked: { [number]: boolean }, maxLevel: number): { number }
	local list: { number } = {}
	for lvl = 1, maxLevel do
		if unlocked[lvl] then
			table.insert(list, lvl)
		end
	end
	return list
end

function DataManager.SyncToClient(player: Player, syncRemote: RemoteEvent?)
	local profile = Profiles[player.UserId]
	if not profile then return end
	syncRemote = syncRemote or DefaultSyncRemote
	profile.MaxEnergy = DataManager.GetMaxEnergy(player)
	DataManager.UpdateLeaderstats(player)
	DataManager.UpdateBagAttributes(player)

	local achProgress: { [string]: number } = {}
	for _, ach in ipairs(ProgressionConfig.ACHIEVEMENTS) do
		achProgress[ach.Id] = ProgressionManager.GetStatValue(profile, ach.Stat)
	end

	if syncRemote then
		pcall(function()
			syncRemote:FireClient(player, {
				Coins = profile.Coins,
				Level = profile.Level,
				XP = profile.XP,
				RequiredXP = GameConfig.GetRequiredLevelXP(profile.Level),
				Strength = profile.Strength,
				StrengthXP = profile.StrengthXP,
				RequiredStrengthXP = GameConfig.GetRequiredStrengthXP(profile.Strength),
				Energy = math.floor(profile.Energy + 0.5),
				MaxEnergy = profile.MaxEnergy,
				EnergyRegen = DataManager.GetEnergyRegenPerSec(player, false),
				HitDamage = DataManager.GetHitDamage(player),
				PickaxeTier = profile.PickaxeTier,
				UnlockedPickaxes = profile.UnlockedPickaxes,
				BackpackLevel = profile.BackpackLevel,
				UnlockedBackpacks = profile.UnlockedBackpacks,
				OwnedPickaxes = ownedLevels(profile.UnlockedPickaxes, GameConfig.MAX_PICKAXE_LEVEL),
				OwnedBackpacks = ownedLevels(profile.UnlockedBackpacks, GameConfig.MAX_BACKPACK_LEVEL),
				BagUsed = DataManager.GetBackpackUsed(player),
				BagMax = DataManager.GetMaxBackpack(player),
				BagValue = DataManager.GetBackpackSellValue(player),
				MaxDepthReached = profile.MaxDepthReached, BackpackDirt = math.floor(profile.BackpackDirt or 0),
				DirtBlocks = math.floor(profile.DirtBlocks or 0),
				DirtStage = GameConfig.GetDirtStage(profile.DirtBlocks or 0),
				FoodStock = math.floor(profile.FoodStock or 0),
				Inventory = profile.Inventory,
				MorningInventory = profile.MorningInventory,
				SkillPoints = profile.SkillPoints,
				Skills = profile.Skills,
				Prestige = profile.Prestige,
				Achievements = profile.Achievements,
				AchievementProgress = achProgress,
				AttackCooldown = DataManager.GetAttackCooldown(player),
				CanPrestige = profile.Level >= ProgressionConfig.PRESTIGE_REQUIRED_LEVEL
					and profile.Prestige < ProgressionConfig.PRESTIGE_MAX,
			})
		end)
	end
end

function DataManager.AddResourceToBackpack(
	player: Player,
	blockId: string,
	xpAmount: number,
	strXpAmount: number,
	levelIndex: number,
	isMorningVein: boolean?
): string?
	local profile = Profiles[player.UserId]
	if not profile then return nil end

	if isMorningVein then
		profile.MorningInventory[blockId] = (profile.MorningInventory[blockId] or 0) + 1
	else
		profile.Inventory[blockId] = (profile.Inventory[blockId] or 0) + 1
	end
	profile.TotalMined += 1
	do -- v32: every mined block makes the backpack dirtier (stages at 20/50/100/300 blocks)
		local beforeStage = GameConfig.GetDirtStage(profile.DirtBlocks or 0)
		profile.DirtBlocks = math.min(99999, (profile.DirtBlocks or 0) + 1)
		profile.BackpackDirt = GameConfig.GetDirtPercent(profile.DirtBlocks)
		local afterStage = GameConfig.GetDirtStage(profile.DirtBlocks)
		DataManager.UpdateBagAttributes(player)
		if afterStage ~= beforeStage then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local st = GameConfig.BACKPACK_DIRT.Stages[afterStage]
			if root and st then
				pcall(function()
					VFXModule.SpawnFloatingText(root.Position + Vector3.new(0, 3, 0), string.format("🎒 Backpack: %s (-%d%% slots)", st.Name, math.floor(st.Penalty * 100 + 0.5)), Color3.fromRGB(170, 200, 90))
				end)
			end
		end
	end
	if levelIndex > (profile.MaxDepthReached or 0) then
		profile.MaxDepthReached = levelIndex
	end
	ProgressionManager.RegisterOreFound(profile, blockId)

	profile.StrengthXP += strXpAmount
	local reqStr = GameConfig.GetRequiredStrengthXP(profile.Strength)
	while profile.StrengthXP >= reqStr do
		profile.StrengthXP -= reqStr
		profile.Strength += 1
		reqStr = GameConfig.GetRequiredStrengthXP(profile.Strength)
	end

	ProgressionManager.GrantXP(player, profile, xpAmount)

	local luckyId: string? = nil
	-- v52: буст «Удача» умножает шанс бонусной руды
	if rng:NextNumber() < ProgressionConfig.GetLuckChance(profile.Skills, profile.Prestige) * BoostService.GetMultiplier(player, "Luck")
		and DataManager.GetBackpackUsed(player) < DataManager.GetMaxBackpack(player) then
		local idx = 1
		for i, b in ipairs(GameConfig.BLOCK_LIST) do
			if b.Id == blockId then
				idx = i
				break
			end
		end
		local bonus = GameConfig.BLOCK_LIST[math.min(idx + 1, #GameConfig.BLOCK_LIST)]
		profile.Inventory[bonus.Id] = (profile.Inventory[bonus.Id] or 0) + 1
		ProgressionManager.RegisterOreFound(profile, bonus.Id)
		luckyId = bonus.Id
	end

	ProgressionManager.CheckAchievements(player, profile)
	DataManager.UpdateLeaderstats(player)
	return luckyId
end

function DataManager.GrantCaveChestReward(player: Player, coinsReward: number, chestPart: BasePart, syncRemote: RemoteEvent?)
	local profile = Profiles[player.UserId]
	if not profile then return end
	profile.Coins += coinsReward
	profile.Energy = DataManager.GetMaxEnergy(player)
	ProgressionManager.TrackCoins(profile)
	ProgressionManager.CheckAchievements(player, profile)

	SoundManager.PlayAt("CoinChime", chestPart.Position)
	VFXModule.PlayPurchaseOrSellBurst(chestPart.Position, Color3.fromRGB(255, 215, 65))
	VFXModule.SpawnFloatingText(
		chestPart.Position + Vector3.new(0, 2, 0),
		string.format("🧰 +%d coins and +100%% Energy!", coinsReward),
		Color3.fromRGB(255, 225, 75)
	)
	DataManager.SyncToClient(player, syncRemote)
end

-- ============================================================================
-- v50: COMBO, SURPRISE BLOCKS AND DAILY REWARD (called by MineManager / ServerMain)
-- ============================================================================
-- Sends a ProgressionEvent message ("Combo", "Special", "DailyReward", "Toast"...) to one client
function DataManager.Notify(player: Player, eventType: string, payload: any)
	ProgressionManager.Notify(player, eventType, payload)
end

-- Adds coins outside of selling (combo bonus, Lucky Block, Treasure Chest, TNT overflow).
-- applyCoinBonus = true multiplies by the prestige coin bonus. Returns the coins actually added.
function DataManager.GrantCoins(player: Player, amount: number, applyCoinBonus: boolean?): number
	local profile = Profiles[player.UserId]
	if not profile or amount <= 0 then return 0 end
	local mult = applyCoinBonus and ProgressionConfig.GetCoinMultiplier(profile.Prestige) or 1
	local coins = math.max(1, math.floor(amount * mult + 0.5))
	profile.Coins += coins
	ProgressionManager.TrackCoins(profile)
	return coins
end

function DataManager.RefillEnergy(player: Player)
	local profile = Profiles[player.UserId]
	if not profile then return end
	profile.MaxEnergy = DataManager.GetMaxEnergy(player)
	profile.Energy = profile.MaxEnergy
end

-- XP without an ore (surprise blocks)
function DataManager.GrantXP(player: Player, amount: number)
	local profile = Profiles[player.UserId]
	if not profile then return end
	ProgressionManager.GrantXP(player, profile, amount)
end

-- Counts a fun stat ("LuckyOpened" | "TntExploded" | "TreasuresFound") and re-checks achievements
function DataManager.AddFunStat(player: Player, stat: string, amount: number?)
	local profile = Profiles[player.UserId]
	if not profile then return end
	local add = amount or 1
	if stat == "LuckyOpened" then
		profile.LuckyOpened += add
	elseif stat == "TntExploded" then
		profile.TntExploded += add
	elseif stat == "TreasuresFound" then
		profile.TreasuresFound += add
	else
		return
	end
	ProgressionManager.CheckAchievements(player, profile)
end

function DataManager.RegisterCombo(player: Player, combo: number)
	local profile = Profiles[player.UserId]
	if not profile or combo <= profile.BestCombo then return end
	profile.BestCombo = combo
	ProgressionManager.CheckAchievements(player, profile)
end

-- Grants the daily reward once per UTC day. Returns nil when it was already claimed today.
function DataManager.ClaimDailyReward(player: Player): { Day: number, Coins: number, SkillPoints: number }?
	local profile = Profiles[player.UserId]
	if not profile or profile.LoadFailed then return nil end
	local today = math.floor(os.time() / 86400)
	if today <= profile.LastDailyDay then return nil end

	profile.DailyStreak = (today == profile.LastDailyDay + 1) and (profile.DailyStreak + 1) or 1
	profile.LastDailyDay = today
	local coins, skillPoints = GameConfig.GetDailyReward(profile.DailyStreak, profile.Level)
	profile.Coins += coins
	profile.SkillPoints += skillPoints
	ProgressionManager.TrackCoins(profile)
	ProgressionManager.CheckAchievements(player, profile)
	return { Day = profile.DailyStreak, Coins = coins, SkillPoints = skillPoints }
end

-- ============================================================================
-- СЕРВЕРНАЯ ПРОДАЖА РУДЫ В ПУНКТЕ ПРИЁМА «$ SELL» (ПУНКТ №7 И №13 ТЗ)
-- Поддерживает продажу ВСЕЙ руды (mode = "all") или ВЫБРАННЫХ позиций (mode = "selected").
-- Проверяет: расстояние до зоны продажи, реальное наличие руды, отсутствие спама!
-- ============================================================================
-- ============================================================================
-- v18: BACKPACK CLEANING (server-validated: only inside the $ SELL zone, costs coins)
-- ============================================================================
local CleanDebounce: { [number]: number } = {}

function DataManager.CleanBackpack(player: Player, _syncRemote: RemoteEvent?): (boolean, string)
	-- v32: dirt can be cleaned ONLY at night with the Night Merchant's Repair Kit
	local now = os.clock()
	if (now - (CleanDebounce[player.UserId] or 0)) < GameConfig.BACKPACK_DIRT.CleanCooldown then
		return false, "cooldown"
	end
	CleanDebounce[player.UserId] = now
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		VFXModule.SpawnFloatingText(root.Position + Vector3.new(0, 2, 0), "🌙 Dirt can be cleaned only at night: buy a Repair Kit from the Night Merchant!", Color3.fromRGB(255, 160, 110))
	end
	return false, "night merchant only"
end

-- v32: called by the Night Merchant Repair Kit
function DataManager.ResetDirt(player: Player)
	local profile = Profiles[player.UserId]
	if not profile then return end
	profile.DirtBlocks = 0
	profile.BackpackDirt = 0
	DataManager.UpdateBagAttributes(player)
end

-- v32: eat a burger from supplies — anywhere, any time (even deep in the mine)
local EatDebounce: { [number]: number } = {}
function DataManager.EatFood(player: Player, syncRemote: RemoteEvent?): (boolean, string)
	local now = os.clock()
	if (now - (EatDebounce[player.UserId] or 0)) < GameConfig.FOOD.EatCooldown then
		return false, "cooldown"
	end
	EatDebounce[player.UserId] = now
	local profile = Profiles[player.UserId]
	if not profile then return false, "no profile" end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local stock = math.floor(profile.FoodStock or 0)
	if stock <= 0 then
		if root then VFXModule.SpawnFloatingText(root.Position + Vector3.new(0, 2, 0), "🍔 No food! Buy burgers from the Night Merchant", Color3.fromRGB(255, 140, 100)) end
		return false, "no food"
	end
	local maxE = DataManager.GetMaxEnergy(player)
	profile.MaxEnergy = maxE
	if profile.Energy >= maxE - 0.5 then
		if root then VFXModule.SpawnFloatingText(root.Position + Vector3.new(0, 2, 0), "⚡ Energy is already full", Color3.fromRGB(150, 230, 255)) end
		return false, "full"
	end
	profile.FoodStock = stock - 1
	profile.Energy = maxE
	DataManager.UpdateBagAttributes(player)
	DataManager.SyncToClient(player, syncRemote)
	if root then
		VFXModule.SpawnFloatingText(root.Position + Vector3.new(0, 2, 0), string.format("🍔 Yum! Energy restored  (left: %d)", profile.FoodStock), Color3.fromRGB(255, 200, 90))
	end
	return true, "ok"
end

function DataManager.SellResourcesServer(
	player: Player,
	mode: string?,
	selectedKeys: { [string]: boolean }?,
	syncRemote: RemoteEvent?,
	silentOutOfZone: boolean?,
	zoneCenter: Vector3?, -- v52: продажа у торговца Гоши — другая точка и радиус
	zoneRadius: number?
): (number, number)
	local now = os.clock()
	if (now - (SellDebounce[player.UserId] or 0)) < 0.65 then return 0, 0 end

	local profile = Profiles[player.UserId]
	if not profile then return 0, 0 end

	-- Проверка, что игрок находится в зоне приёма руды "$ SELL"
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return 0, 0 end
	local sellCenter = zoneCenter or GameConfig.WHITE_SELL_PAD_POS
	local horizDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(sellCenter.X, 0, sellCenter.Z)).Magnitude
	if horizDist > (zoneRadius or (GameConfig.SELL_ZONE_RADIUS + 4)) or math.abs(root.Position.Y - sellCenter.Y) > 10 then
		if not silentOutOfZone then
			VFXModule.SpawnFloatingText(
				root.Position + Vector3.new(0, 2, 0),
				"📍 Step into the $ SELL zone on the surface!",
				Color3.fromRGB(255, 120, 90)
			)
		end
		return 0, 0
	end

	local sellAll = (mode ~= "selected") or (type(selectedKeys) ~= "table")
	local rawTotalCoins = 0
	local soldItemsCount = 0

	for bId, cnt in pairs(profile.Inventory) do
		if cnt > 0 and (sellAll or (selectedKeys and selectedKeys["Reg_" .. bId] == true)) then
			local info = GameConfig.BLOCK_TYPES[bId]
			if info then
				rawTotalCoins += info.SellPrice * cnt
				soldItemsCount += cnt
				profile.Inventory[bId] = 0
			end
		end
	end

	for bId, cnt in pairs(profile.MorningInventory) do
		if cnt > 0 and (sellAll or (selectedKeys and selectedKeys["Morn_" .. bId] == true)) then
			local info = GameConfig.BLOCK_TYPES[bId]
			if info then
				rawTotalCoins += (info.SellPrice * GameConfig.MORNING_VEINS.SellPriceMultiplier) * cnt
				soldItemsCount += cnt
				profile.MorningInventory[bId] = 0
			end
		end
	end

	if soldItemsCount <= 0 or rawTotalCoins <= 0 then
		return 0, 0
	end

	SellDebounce[player.UserId] = now
	-- v52: буст «Монеты» и зелье Ночного торговца — через BoostService (множители перемножаются)
	local potionMul = BoostService.GetMultiplier(player, "Coins")
	local earnedCoins = math.floor(rawTotalCoins * ProgressionConfig.GetCoinMultiplier(profile.Prestige) * potionMul + 0.5)
	profile.Coins += earnedCoins
	profile.Energy = DataManager.GetMaxEnergy(player)
	ProgressionManager.TrackCoins(profile)
	ProgressionManager.CheckAchievements(player, profile)

	local pos = root.Position
	SoundManager.PlayAt("CoinChime", pos)
	VFXModule.PlayPurchaseOrSellBurst(pos, Color3.fromRGB(85, 245, 130))
	VFXModule.SpawnFloatingText(
		pos + Vector3.new(0, 2.0, 0),
		string.format("+%d монет", earnedCoins),
		Color3.fromRGB(255, 225, 65)
	)

	DataManager.SyncToClient(player, syncRemote)
	return earnedCoins, soldItemsCount
end

-- Автопродажа: вызывается сервером, когда игрок стоит в зоне «$ SELL». Меню и кнопки не нужны.
function DataManager.AutoSellOnWhitePad(player: Player, syncRemote: RemoteEvent?): (number, number)
	return DataManager.SellResourcesServer(player, "all", nil, syncRemote, true)
end

-- v52: продажа у торговца Гоши (вкладка «Продать руду»). selectedKeys = nil — продать всё.
-- Расстояние до прилавка, наличие руды и защита от спама проверяются тут же, на сервере.
function DataManager.SellAtTrader(player: Player, selectedKeys: { [string]: boolean }?, syncRemote: RemoteEvent?): (number, number)
	return DataManager.SellResourcesServer(
		player,
		selectedKeys and "selected" or "all",
		selectedKeys,
		syncRemote,
		true,
		GameConfig.GREEN_SHOP_PAD_POS,
		GameConfig.SHOP_UI.MaxDistance
	)
end

-- ============================================================================
-- ПОКУПКА И ЭКИПИРОВКА КИРОК (1–10 УР.) И РЮКЗАКОВ (1–10 УР.) В 3D-МАГАЗИНЕ
-- ============================================================================
-- v52: обе функции возвращают исход для окна магазина: "Bought" | "Equipped" | "NoCoins" | nil
function DataManager.BuyOrEquip3DPickaxe(
	player: Player,
	level: number,
	equipmentManager: any,
	syncRemote: RemoteEvent?
): string?
	local now = os.clock()
	if (now - (ShopDebounce[player.UserId] or 0)) < 0.25 then return nil end
	ShopDebounce[player.UserId] = now

	local profile = Profiles[player.UserId]
	if not profile then return nil end

	local lvl = math.clamp(math.floor(level), 1, GameConfig.MAX_PICKAXE_LEVEL)
	local tierCfg = GameConfig.PICKAXE_TIERS[lvl]
	if not tierCfg then return nil end
	local nameRu = GameConfig.RU_NAMES.Pickaxes[lvl] or tierCfg.Name

	local pos = (player.Character and player.Character:GetPivot().Position) or GameConfig.GREEN_SHOP_PAD_POS

	if profile.UnlockedPickaxes[lvl] then
		profile.PickaxeTier = lvl
		if player.Character then
			equipmentManager.EquipPickaxe(player.Character, lvl)
		end
		VFXModule.SpawnFloatingText(pos, string.format("⛏️ Надета: %s (ур. %d)", nameRu, lvl), tierCfg.BladeColor)
		DataManager.SyncToClient(player, syncRemote)
		return "Equipped"
	end

	if profile.Coins < tierCfg.Cost then
		VFXModule.SpawnFloatingText(
			pos,
			string.format("Не хватает монет! Нужно %d 💰 — %s", tierCfg.Cost, nameRu),
			Color3.fromRGB(255, 95, 95)
		)
		return "NoCoins"
	end

	profile.Coins -= tierCfg.Cost
	profile.UnlockedPickaxes[lvl] = true
	profile.PickaxeTier = lvl

	if player.Character then
		equipmentManager.EquipPickaxe(player.Character, lvl)
	end

	SoundManager.PlayAt("ShopPurchase", pos)
	VFXModule.PlayPurchaseOrSellBurst(pos, tierCfg.BladeColor)
	VFXModule.SpawnFloatingText(
		pos + Vector3.new(0, 1.5, 0),
		string.format("✨ Куплена и надета: %s (ур. %d)!", nameRu, lvl),
		tierCfg.BladeColor
	)

	DataManager.SyncToClient(player, syncRemote)
	return "Bought"
end

function DataManager.BuyOrEquip3DBackpack(
	player: Player,
	level: number,
	equipmentManager: any,
	syncRemote: RemoteEvent?
): string?
	local now = os.clock()
	if (now - (ShopDebounce[player.UserId] or 0)) < 0.25 then return nil end
	ShopDebounce[player.UserId] = now

	local profile = Profiles[player.UserId]
	if not profile then return nil end

	local lvl = math.clamp(math.floor(level), 1, GameConfig.MAX_BACKPACK_LEVEL)
	local bagCfg = GameConfig.BACKPACK_TIERS[lvl]
	if not bagCfg then return nil end
	local nameRu = GameConfig.RU_NAMES.Backpacks[lvl] or bagCfg.Name

	local pos = (player.Character and player.Character:GetPivot().Position) or GameConfig.GREEN_SHOP_PAD_POS

	if profile.UnlockedBackpacks[lvl] then
		profile.BackpackLevel = lvl
		if player.Character then
			equipmentManager.EquipBackpack(player.Character, lvl)
		end
		VFXModule.SpawnFloatingText(pos, string.format("🎒 Надет: %s (%d мест)", nameRu, bagCfg.Capacity), bagCfg.Fitting)
		DataManager.SyncToClient(player, syncRemote)
		return "Equipped"
	end

	if profile.Coins < bagCfg.Cost then
		VFXModule.SpawnFloatingText(
			pos,
			string.format("Не хватает монет! Нужно %d 💰 — %s", bagCfg.Cost, nameRu),
			Color3.fromRGB(255, 95, 95)
		)
		return "NoCoins"
	end

	profile.Coins -= bagCfg.Cost
	profile.UnlockedBackpacks[lvl] = true
	profile.BackpackLevel = lvl

	if player.Character then
		equipmentManager.EquipBackpack(player.Character, lvl)
	end

	SoundManager.PlayAt("ShopPurchase", pos)
	VFXModule.PlayPurchaseOrSellBurst(pos, bagCfg.Fitting)
	VFXModule.SpawnFloatingText(
		pos + Vector3.new(0, 1.5, 0),
		string.format("🎒 Куплен и надет: %s (%d мест)!", nameRu, bagCfg.Capacity),
		Color3.fromRGB(85, 245, 140)
	)

	DataManager.SyncToClient(player, syncRemote)
	return "Bought"
end

function DataManager.StartEnergyRegenLoop()
	task.spawn(function()
		while task.wait(1.0) do
			for _, p in ipairs(Players:GetPlayers()) do
				local profile = Profiles[p.UserId]
				if profile then
					local maxE = DataManager.GetMaxEnergy(p)
					profile.MaxEnergy = maxE
					if profile.Energy < maxE then
						local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
						local onSurface = (root == nil) or (root.Position.Y >= -1.0)
						local regen = DataManager.GetEnergyRegenPerSec(p, onSurface)
						profile.Energy = math.min(maxE, profile.Energy + regen)
						DataManager.SyncToClient(p, DefaultSyncRemote)
					end
				end
			end
		end
	end)
end

function DataManager.LoadPlayerProfile(player: Player): PlayerProfile
	local profile = createDefaultProfile()

	if okStore and ProfileStore then
		-- v50: retry the read, and if it still fails remember that so an empty
		-- default profile can never overwrite the player's real save
		local ok: boolean, saved: any = false, nil
		for attempt = 1, 3 do
			ok, saved = pcall(function()
				return ProfileStore:GetAsync("MinerV13_" .. player.UserId)
			end)
			if ok then break end
			if attempt < 3 then task.wait(0.5 * attempt) end
		end
		if not ok then
			profile.LoadFailed = true
			warn(string.format("[DataManager] Could not load the save of %s: %s", player.Name, tostring(saved)))
		end
		if ok and type(saved) == "table" then
			profile.Coins = math.max(0, tonumber(saved.Coins) or 0)
			profile.Level = math.max(1, tonumber(saved.Level) or 1)
			profile.XP = math.max(0, tonumber(saved.XP) or 0)
			profile.Strength = math.max(1, tonumber(saved.Strength) or 1)
			profile.StrengthXP = math.max(0, tonumber(saved.StrengthXP) or 0)
			profile.PickaxeTier = math.clamp(tonumber(saved.PickaxeTier) or 1, 1, GameConfig.MAX_PICKAXE_LEVEL)
			profile.BackpackLevel = math.clamp(tonumber(saved.BackpackLevel) or 1, 1, GameConfig.MAX_BACKPACK_LEVEL)
			profile.TotalMined = math.max(0, tonumber(saved.TotalMined) or 0)
			profile.MaxDepthReached = math.max(0, tonumber(saved.MaxDepthReached) or 0)
			profile.BackpackDirt = math.clamp(tonumber(saved.BackpackDirt) or 0, 0, 100)
			if tonumber(saved.DirtBlocks) then
				profile.DirtBlocks = math.max(0, math.floor(tonumber(saved.DirtBlocks) or 0))
			else -- migrate old % dirt into blocks
				profile.DirtBlocks = math.floor(profile.BackpackDirt / 100 * GameConfig.BACKPACK_DIRT.MaxBlocks)
			end
			profile.BackpackDirt = GameConfig.GetDirtPercent(profile.DirtBlocks)
			profile.FoodStock = math.clamp(math.floor(tonumber(saved.FoodStock) or 0), 0, GameConfig.FOOD.MaxStock)
			profile.BestCombo = math.max(0, math.floor(tonumber(saved.BestCombo) or 0))
			profile.LuckyOpened = math.max(0, math.floor(tonumber(saved.LuckyOpened) or 0))
			profile.TntExploded = math.max(0, math.floor(tonumber(saved.TntExploded) or 0))
			profile.TreasuresFound = math.max(0, math.floor(tonumber(saved.TreasuresFound) or 0))
			profile.DailyStreak = math.max(0, math.floor(tonumber(saved.DailyStreak) or 0))
			profile.LastDailyDay = math.max(0, math.floor(tonumber(saved.LastDailyDay) or 0))
			local sc = type(saved.Cosmetics) == "table" and saved.Cosmetics or {}
			;(profile :: any).Cosmetics = { TopHat = sc.TopHat == true, TopHatOn = sc.TopHatOn == true }
			;(profile :: any).MorningCharm = saved.MorningCharm == true
			BoostService.Load(player, saved.Boosts) -- v52: бусты сохраняются вместе с прогрессом
			ProgressionManager.ApplySavedData(profile, saved)
			if type(saved.UnlockedPickaxes) == "table" then
				for k, v in pairs(saved.UnlockedPickaxes) do
					local idx = tonumber(k)
					if idx and idx >= 1 and idx <= GameConfig.MAX_PICKAXE_LEVEL and v == true then
						profile.UnlockedPickaxes[idx] = true
					end
				end
			end
			if type(saved.UnlockedBackpacks) == "table" then
				for k, v in pairs(saved.UnlockedBackpacks) do
					local idx = tonumber(k)
					if idx and idx >= 1 and idx <= GameConfig.MAX_BACKPACK_LEVEL and v == true then
						profile.UnlockedBackpacks[idx] = true
					end
				end
			end
			if type(saved.Inventory) == "table" then
				for k, v in pairs(saved.Inventory) do
					if GameConfig.BLOCK_TYPES[k] and type(v) == "number" then
						profile.Inventory[k] = math.max(0, math.floor(v))
					end
				end
			end
			if type(saved.MorningInventory) == "table" then
				for k, v in pairs(saved.MorningInventory) do
					if GameConfig.BLOCK_TYPES[k] and type(v) == "number" then
						profile.MorningInventory[k] = math.max(0, math.floor(v))
					end
				end
			end
			if type(saved.Energy) == "number" then
				profile.Energy = math.clamp(saved.Energy, 0, DataManager.GetMaxEnergy(player))
			end
		end
	end

	Profiles[player.UserId] = profile
	profile.MaxEnergy = DataManager.GetMaxEnergy(player)
	if not profile.Energy or profile.Energy <= 0 then
		profile.Energy = profile.MaxEnergy
	end

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player

	local lvl = Instance.new("IntValue", ls)
	lvl.Name = "Level"
	lvl.Value = profile.Level

	local str = Instance.new("IntValue", ls)
	str.Name = "Strength"
	str.Value = profile.Strength

	local coins = Instance.new("IntValue", ls)
	coins.Name = "Coins"
	coins.Value = profile.Coins

	local mined = Instance.new("IntValue", ls)
	mined.Name = "Mined"
	mined.Value = profile.TotalMined

	DataManager.UpdateLeaderstats(player)
	return profile
end

function DataManager.SavePlayerProfile(player: Player)
	local profile = Profiles[player.UserId]
	if not profile or not okStore or not ProfileStore then return end
	if profile.LoadFailed then return end
	pcall(function()
		local progSave = ProgressionManager.GetSaveData(profile)
		ProfileStore:SetAsync("MinerV13_" .. player.UserId, {
			Coins = profile.Coins,
			Level = profile.Level,
			XP = profile.XP,
			Strength = profile.Strength,
			StrengthXP = profile.StrengthXP,
			Energy = profile.Energy,
			PickaxeTier = profile.PickaxeTier,
			UnlockedPickaxes = profile.UnlockedPickaxes,
			BackpackLevel = profile.BackpackLevel,
			UnlockedBackpacks = profile.UnlockedBackpacks,
			TotalMined = profile.TotalMined,
			MaxDepthReached = profile.MaxDepthReached, BackpackDirt = math.floor(profile.BackpackDirt or 0),
			DirtBlocks = math.floor(profile.DirtBlocks or 0), FoodStock = math.floor(profile.FoodStock or 0),
			Cosmetics = (profile :: any).Cosmetics, MorningCharm = (profile :: any).MorningCharm == true,
			BestCombo = profile.BestCombo,
			LuckyOpened = profile.LuckyOpened,
			TntExploded = profile.TntExploded,
			TreasuresFound = profile.TreasuresFound,
			DailyStreak = profile.DailyStreak,
			LastDailyDay = profile.LastDailyDay,
			Inventory = profile.Inventory,
			MorningInventory = profile.MorningInventory,
			SkillPoints = progSave.SkillPoints,
			Skills = progSave.Skills,
			Prestige = progSave.Prestige,
			Achievements = progSave.Achievements,
			FoundOres = progSave.FoundOres,
			PeakCoins = progSave.PeakCoins,
			Boosts = BoostService.Serialize(player), -- v52: остаток секунд по каждому бусту
		})
	end)
end

function DataManager.RemovePlayerProfile(player: Player)
	DataManager.SavePlayerProfile(player)
	BoostService.Clear(player)
	Profiles[player.UserId] = nil
	SellDebounce[player.UserId] = nil
	ShopDebounce[player.UserId] = nil
	CleanDebounce[player.UserId] = nil
end

function DataManager.StartAutoSaveLoop()
	DataManager.StartEnergyRegenLoop()
	task.spawn(function()
		while task.wait(GameConfig.AUTOSAVE_INTERVAL) do
			for _, p in ipairs(Players:GetPlayers()) do
				task.spawn(DataManager.SavePlayerProfile, p)
			end
		end
	end)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			DataManager.SavePlayerProfile(p)
		end
	end)
end

return DataManager
