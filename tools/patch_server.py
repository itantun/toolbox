#!/usr/bin/env python3
"""v51 -> v52: правки серверных скриптов (DataManager, ServerMain, WorldBuilder, MineManager)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patcher  # noqa: E402

S = "src/ServerScriptService/"

# ----------------------------------------------------------------------------
# DataManager: бусты (скорость / удача / монеты), сохранение бустов, продажа у торговца,
# исход покупки для окна магазина
# ----------------------------------------------------------------------------
p = Patcher(S + "Modules/DataManager.lua")

p.sub(
    'local ProgressionManager = require(script.Parent:WaitForChild("ProgressionManager"))\n',
    'local ProgressionManager = require(script.Parent:WaitForChild("ProgressionManager"))\n'
    'local BoostService = require(script.Parent:WaitForChild("BoostService")) -- v52: бусты торговца\n',
)

p.sub(
    "\tlocal mult = (1 + 0.02 * speedSkill) * ProgressionConfig.GetPrestigeMultiplier(profile.Prestige)\n"
    "\treturn math.clamp(baseCd / mult, 0.20, 0.60)\n",
    "\tlocal mult = (1 + 0.02 * speedSkill) * ProgressionConfig.GetPrestigeMultiplier(profile.Prestige)\n"
    "\t-- v52: буст «Скорость» ускоряет удар (и опускает нижний предел кулдауна)\n"
    "\tlocal boost = BoostService.GetMultiplier(player, \"MineSpeed\")\n"
    "\treturn math.clamp(baseCd / (mult * boost), 0.20 / boost, 0.60)\n",
)

p.sub(
    "\tif rng:NextNumber() < ProgressionConfig.GetLuckChance(profile.Skills, profile.Prestige)\n",
    "\t-- v52: буст «Удача» умножает шанс бонусной руды\n"
    "\tif rng:NextNumber() < ProgressionConfig.GetLuckChance(profile.Skills, profile.Prestige) * BoostService.GetMultiplier(player, \"Luck\")\n",
)

p.sub(
    "\tsyncRemote: RemoteEvent?,\n\tsilentOutOfZone: boolean?\n): (number, number)\n",
    "\tsyncRemote: RemoteEvent?,\n\tsilentOutOfZone: boolean?,\n"
    "\tzoneCenter: Vector3?, -- v52: продажа у торговца Гоши — другая точка и радиус\n"
    "\tzoneRadius: number?\n): (number, number)\n",
)
p.sub(
    "\tlocal sellCenter = GameConfig.WHITE_SELL_PAD_POS\n",
    "\tlocal sellCenter = zoneCenter or GameConfig.WHITE_SELL_PAD_POS\n",
)
p.sub(
    "\tif horizDist > GameConfig.SELL_ZONE_RADIUS + 4 or math.abs(root.Position.Y - sellCenter.Y) > 10 then\n",
    "\tif horizDist > (zoneRadius or (GameConfig.SELL_ZONE_RADIUS + 4)) or math.abs(root.Position.Y - sellCenter.Y) > 10 then\n",
)
p.sub(
    '\tlocal potionMul = ((tonumber(player:GetAttribute("SellBoostUntil")) or 0) > os.time()) and 1.25 or 1\n',
    '\t-- v52: буст «Монеты» и зелье Ночного торговца — через BoostService (множители перемножаются)\n'
    '\tlocal potionMul = BoostService.GetMultiplier(player, "Coins")\n',
)
p.sub('\t\tstring.format("+%d coins", earnedCoins),\n', '\t\tstring.format("+%d монет", earnedCoins),\n')

p.sub(
    "function DataManager.AutoSellOnWhitePad(player: Player, syncRemote: RemoteEvent?): (number, number)\n"
    "\treturn DataManager.SellResourcesServer(player, \"all\", nil, syncRemote, true)\n"
    "end\n",
    "function DataManager.AutoSellOnWhitePad(player: Player, syncRemote: RemoteEvent?): (number, number)\n"
    "\treturn DataManager.SellResourcesServer(player, \"all\", nil, syncRemote, true)\n"
    "end\n\n"
    "-- v52: продажа у торговца Гоши (вкладка «Продать руду»). selectedKeys = nil — продать всё.\n"
    "-- Расстояние до прилавка, наличие руды и защита от спама проверяются тут же, на сервере.\n"
    "function DataManager.SellAtTrader(player: Player, selectedKeys: { [string]: boolean }?, syncRemote: RemoteEvent?): (number, number)\n"
    "\treturn DataManager.SellResourcesServer(\n"
    "\t\tplayer,\n"
    "\t\tselectedKeys and \"selected\" or \"all\",\n"
    "\t\tselectedKeys,\n"
    "\t\tsyncRemote,\n"
    "\t\ttrue,\n"
    "\t\tGameConfig.GREEN_SHOP_PAD_POS,\n"
    "\t\tGameConfig.SHOP_UI.MaxDistance\n"
    "\t)\n"
    "end\n",
)

NEW_BUY = '''-- v52: обе функции возвращают исход для окна магазина: "Bought" | "Equipped" | "NoCoins" | nil
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

'''
p.between("function DataManager.BuyOrEquip3DPickaxe(\n", "function DataManager.StartEnergyRegenLoop()\n", NEW_BUY)

p.sub(
    "\t\t\t;(profile :: any).MorningCharm = saved.MorningCharm == true\n",
    "\t\t\t;(profile :: any).MorningCharm = saved.MorningCharm == true\n"
    "\t\t\tBoostService.Load(player, saved.Boosts) -- v52: бусты сохраняются вместе с прогрессом\n",
)
p.sub(
    "\t\t\tPeakCoins = progSave.PeakCoins,\n",
    "\t\t\tPeakCoins = progSave.PeakCoins,\n"
    "\t\t\tBoosts = BoostService.Serialize(player), -- v52: остаток секунд по каждому бусту\n",
)
p.sub(
    "\tDataManager.SavePlayerProfile(player)\n\tProfiles[player.UserId] = nil\n",
    "\tDataManager.SavePlayerProfile(player)\n\tBoostService.Clear(player)\n\tProfiles[player.UserId] = nil\n",
)
p.save()

# ----------------------------------------------------------------------------
# MineManager: ночью копка запрещена на сервере ВСЕГДА (а не только с поверхности)
# ----------------------------------------------------------------------------
p = Patcher(S + "Modules/MineManager.lua")
p.sub(
    "\tif IsNightClosed and root.Position.Y > -1.0 then\n"
    "\t\tVFXModule.SpawnFloatingText(\n"
    "\t\t\tblockPos,\n"
    "\t\t\t\"🌙 The mine is closed at night. Come back in the morning.\",\n",
    "\t-- v52: ночью копка строго запрещена на сервере, где бы игрок ни стоял\n"
    "\tif IsNightClosed then\n"
    "\t\tVFXModule.SpawnFloatingText(\n"
    "\t\t\tblockPos,\n"
    "\t\t\t\"🌙 Шахта закрыта на ночь. Возвращайся утром!\",\n",
)
p.save()

# ----------------------------------------------------------------------------
# WorldBuilder: каменная площадь спавна, рынок с торговцем, зоны без декора, тропа, вывеска
# ----------------------------------------------------------------------------
p = Patcher(S + "Modules/WorldBuilder.lua")
p.sub(
    'local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))\n',
    'local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))\n'
    '-- v52: процедурные постройки «сочного» обновления\n'
    'local SpawnPlazaBuilder = require(script.Parent:WaitForChild("SpawnPlazaBuilder"))\n'
    'local MarketBuilder = require(script.Parent:WaitForChild("MarketBuilder"))\n',
)
p.between(
    '\tlocal spawnPad = Instance.new("SpawnLocation")\n',
    "\t-- Строим современный Пункт",
    "\t-- v52: каменная площадь спавна из настоящей геометрии (SpawnLocation встроен в камень)\n"
    "\tSpawnPlazaBuilder.Build(worldFolder)\n\n",
)
p.sub(
    "\tlocal greenShopPad = WorldBuilder.BuildNeonShopPavilion(worldFolder, GameConfig.GREEN_SHOP_PAD_POS, equipmentManager)\n",
    "\t-- v52: деревянный рынок с торговцем Гошей вместо неонового павильона «SHOP»\n"
    "\tlocal greenShopPad = MarketBuilder.Build(worldFolder, GameConfig.GREEN_SHOP_PAD_POS).Pad\n",
)
p.sub(
    "\t\tif math.abs(x) < 11 + m and z > -18 - m and z < 32 + m then return true end -- spawn pad & gravel path\n",
    "\t\tif math.abs(x) < 11 + m and z > -18 - m and z < 32 + m then return true end -- spawn pad & gravel path\n"
    "\t\tif math.abs(x) < 19 + m and z > 12 - m and z < 34.5 + m then return true end -- v52: каменная площадь спавна\n",
    count=2,
)
p.sub("\tlocal zFrom, zTo = 18, -17.8\n", "\tlocal zFrom, zTo = 13.4, -17.8 -- v52: тропа начинается от края каменной площади\n")
p.sub(
    '\t\tMineSignLabel.Text = isNight and "CLOSED" or GameConfig.MINE_SIGN_TEXT\n',
    '\t\tMineSignLabel.Text = isNight and "ЗАКРЫТО" or GameConfig.MINE_SIGN_TEXT\n',
)
p.save()

# ----------------------------------------------------------------------------
# ServerMain: новые модули и Remote-ы, стена, цикл дня/ночи через NightCycleService,
# зелье через BoostService, запуск магазина
# ----------------------------------------------------------------------------
p = Patcher(S + "ServerMain.server.lua")
p.sub(
    'local ProgressionManager = require(ServerModules:WaitForChild("ProgressionManager"))\n',
    'local ProgressionManager = require(ServerModules:WaitForChild("ProgressionManager"))\n'
    '\n'
    '-- v52: модули и Remote-ы «сочного» обновления\n'
    'local BoostService = require(ServerModules:WaitForChild("BoostService"))\n'
    'local NightCycleService = require(ServerModules:WaitForChild("NightCycleService"))\n'
    'local NightWallBuilder = require(ServerModules:WaitForChild("NightWallBuilder"))\n'
    'local ShopService = require(ServerModules:WaitForChild("ShopService"))\n'
    'local ShopActionRemote = getOrCreateRemote("ShopAction")   -- клиент -> сервер: запрос магазина\n'
    'local ShopResultRemote = getOrCreateRemote("ShopResult")   -- сервер -> клиент: результат запроса\n'
    'local NightNoticeRemote = getOrCreateRemote("NightNotice") -- сервер -> клиент: «ночь / утро / шахта закрыта»\n',
)
p.sub(
    "local blocksFolder = worldRefs.BlocksFolder\n",
    "local blocksFolder = worldRefs.BlocksFolder\n\n"
    "-- v52: большая ночная стена у входа в шахту (состояние — сервер, анимация — клиент)\n"
    "local nightWallRefs = NightWallBuilder.Build(worldRefs.WorldFolder)\n",
)
p.sub(
    'string.format("🌅 Morning! Morning Veins in the mine (×3 💰): %d (%s)", count, table.concat(list, ", "))',
    'string.format("🌅 Утро! В шахте Утренние жилы (×3 💰): %d (%s)", count, table.concat(list, ", "))',
)
p.between(
    "\t\t\t\t-- ПУНКТ №10: Ночью вход в шахту сверху закрыт!\n",
    "\t\t\t\t-- ПУНКТ №11:",
    "\t\t\t\t-- v52: ночью зону шахты проверяет NightCycleService (раз в 0.5 с, телепорт на базу);\n"
    "\t\t\t\t-- здесь только не выдаём каску тому, кто оказался в зоне ночью\n"
    "\t\t\t\tif isNight and inMine then\n"
    "\t\t\t\t\tinMine = false\n"
    "\t\t\t\tend\n\n",
)
p.between(
    "task.spawn(function()\n\twhile true do\n\t\t-- УТРО И ДЕНЬ\n",
    "\n-- ============================================================================\n-- 3. СЕРВЕРНЫЙ ТЕЛЕПОРТ",
    "-- v52: цикл вынесен в NightCycleService — атрибуты Phase / PhaseEndsAt / PhaseLength в ReplicatedStorage,\n"
    "-- мгновенный телепорт всех игроков на базу в момент наступления ночи, стена у входа, проверка зоны.\n"
    "NightCycleService.Start({\n"
    "\tMineManager = MineManager,\n"
    "\tWorldBuilder = WorldBuilder,\n"
    "\tEquipmentManager = EquipmentManager,\n"
    "\tNightWallBuilder = NightWallBuilder,\n"
    "\tWallRefs = nightWallRefs,\n"
    "\tBlocksFolder = blocksFolder,\n"
    "\tOnBlockClicked = handleBlockClick,\n"
    "\tNoticeRemote = NightNoticeRemote,\n"
    "\tDayNightEvent = DayNightEvent,\n"
    "})\n",
)
p.sub(
    "\tPotion       = function(_p: any) return 150 end,\n",
    "\tPotion       = function(_p: any) return GameConfig.BOOSTS.Items.Potion.Price end, -- v52: цена в конфиге бустов\n",
)
p.sub(
    '\t\tPotionLeft = math.max(0, (tonumber(player:GetAttribute("SellBoostUntil")) or 0) - os.time()),\n',
    '\t\tPotionLeft = math.floor(BoostService.GetRemaining(player, "Potion")), -- v52\n',
)
p.sub(
    '\t\t\tlocal untilT = math.max(os.time(), tonumber(player:GetAttribute("SellBoostUntil")) or 0) + 180\n'
    '\t\t\tplayer:SetAttribute("SellBoostUntil", untilT)\n',
    '\t\t\tBoostService.Activate(player, "Potion") -- v52: зелье — обычный буст (продлевается, сохраняется, виден чипом)\n',
)
p.sub(
    "DataManager.StartAutoSaveLoop()\n",
    "DataManager.StartAutoSaveLoop()\n\n"
    "-- v52: бусты (сервер хранит время конца) и магазин торговца Гоши (все запросы проверяет сервер)\n"
    "BoostService.SetChangedCallback(function(player: Player)\n"
    "\tDataManager.SyncToClient(player, SyncPlayerData)\n"
    "end)\n"
    "BoostService.Start()\n"
    "ShopService.Init({\n"
    "\tDataManager = DataManager,\n"
    "\tEquipmentManager = EquipmentManager,\n"
    "\tBoostService = BoostService,\n"
    "\tSoundManager = SoundManager,\n"
    "\tSyncRemote = SyncPlayerData,\n"
    "\tActionRemote = ShopActionRemote,\n"
    "\tResultRemote = ShopResultRemote,\n"
    "})\n",
)
p.save()
