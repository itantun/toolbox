--!strict
-- ============================================================================
-- 🌐 MODULE: LocalizationConfig (ReplicatedStorage.Modules.LocalizationConfig)
-- Version: v16.0 — Requirement #14:
-- • All in-game UI, signs, buttons, prompts, and notifications use clean English.
-- • Full English -> Russian translation dictionary for Roblox LocalizationService
--   and reference verification.
-- ============================================================================

local LocalizationService = game:GetService("LocalizationService")

local LocalizationConfig = {}

export type TranslationEntry = {
	En: string,
	Ru: string,
	Context: string,
}

LocalizationConfig.ENTRIES = {
	{ En = "Shop", Ru = "Магазин", Context = "Left Square Tile / Bottom Pill Button / Stall Sign" },
	{ En = "Sell", Ru = "Продажа / Продать", Context = "Bottom Pill Button / Sell Stall Sign" },
	{ En = "Sell All", Ru = "Продать всё", Context = "Sell Zone World Prompt & Button" },
	{ En = "Sell Your Items!", Ru = "Сдайте свою руду!", Context = "Sell Stall Neon Prompt Board" },
	{ En = "[E] Sell", Ru = "[E] Продать", Context = "Sell Stall Interactive Key Prompt" },
	{ En = "Skills", Ru = "Навыки", Context = "Left Square Tile / Skills Window Header" },
	{ En = "Stats", Ru = "Статистика / Достижения", Context = "Left Square Tile" },
	{ En = "Rebirth", Ru = "Престиж / Перерождение", Context = "Left Square Tile / Prestige Window" },
	{ En = "Coins", Ru = "Монеты", Context = "Top-Right Coin Pill / Leaderstats" },
	{ En = "Energy", Ru = "Энергия", Context = "Top Status Bar / Skills Window" },
	{ En = "Strength", Ru = "Сила", Context = "Left Mini Stat Bar / Skills Window / Leaderstats" },
	{ En = "Health", Ru = "Здоровье", Context = "Top Status Bar" },
	{ En = "Backpack", Ru = "Рюкзак", Context = "Inventory Window / Shop Category" },
	{ En = "Backpacks", Ru = "Рюкзаки", Context = "Shop Tab Button" },
	{ En = "Pickaxe", Ru = "Кирка", Context = "Equipment / Tooltip" },
	{ En = "Pickaxes", Ru = "Кирки", Context = "Shop Tab Button" },
	{ En = "PICKAXE SHOP", Ru = "МАГАЗИН КИРОК", Context = "Shop Carousel Wooden Header" },
	{ En = "BACKPACK SHOP", Ru = "МАГАЗИН РЮКЗАКОВ", Context = "Shop Carousel Wooden Header" },
	{ En = "MINE", Ru = "ШАХТА", Context = "3D Wooden Mine Entrance Sign" },
	{ En = "CLOSED", Ru = "ЗАКРЫТО", Context = "Mine Entrance Sign at Night" },
	{ En = "OPEN", Ru = "ОТКРЫТО", Context = "Mine Status Indicator" },
	{ En = "Buy", Ru = "Купить", Context = "Shop Carousel Card Button" },
	{ En = "Equip", Ru = "Надеть", Context = "Shop Carousel Card Button" },
	{ En = "Equipped", Ru = "Надето", Context = "Shop Carousel Card Status" },
	{ En = "Owned", Ru = "Куплено", Context = "Shop Carousel Card Status" },
	{ En = "Not Enough Coins", Ru = "Недостаточно монет", Context = "Shop Status / Purchase Error" },
	{ En = "Spawn", Ru = "Спаун", Context = "Bottom Teleport Pill Button" },
	{ En = "Surface", Ru = "Поверхность", Context = "Depth Indicator / Teleport Target" },
	{ En = "Upgrade", Ru = "Улучшить", Context = "Bottom Pill Button / Skills Row Button" },
	{ En = "Teleport", Ru = "Телепорт", Context = "Bottom Pill Button" },
	{ En = "Night Merchant", Ru = "Ночной торговец", Context = "Night Stall Sign & Window Header" },
	{ En = "ORE BUYBACK • 70%", Ru = "СКУПКА РУДЫ • 70%", Context = "Night Merchant Left Table Sign" },
	{ En = "Sell All Ore (70% Value)", Ru = "Продать всю руду (70% цены)", Context = "Night Merchant Window Button" },
	{ En = "Repair Kit", Ru = "Ремонтный набор", Context = "Night Merchant Item (Cleans Backpack & Buffs Pickaxe)" },
	{ En = "Book", Ru = "Книга шахтёра", Context = "Night Merchant Item (+XP & +Strength XP)" },
	{ En = "Food", Ru = "Еда (Бургер и содовая)", Context = "Night Merchant Item (Full Energy + Max Energy Buff)" },
	{ En = "Consumable", Ru = "Зелье шахтёра", Context = "Night Merchant Item (Speed & Luck Potion)" },
	{ En = "Cosmetic", Ru = "Косметика (Цилиндр и неоновые очки)", Context = "Night Merchant Item" },
	{ En = "Morning Bonus", Ru = "Утренний бонус (Талисман жил)", Context = "Night Merchant Item (Guarantees 3 Morning Veins)" },
	{ En = "Dirt", Ru = "Загрязнение", Context = "HUD & Inventory Backpack Dirt Bar" },
	{ En = "Clean Backpack", Ru = "Почистить рюкзак", Context = "Inventory / Sell Zone / HUD Button" },
	{ En = "Depth", Ru = "Глубина", Context = "Top Status Bar / Inventory Sorting" },
	{ En = "Ore Vein", Ru = "Рудная жила", Context = "Mine Block Tag" },
	{ En = "Rare Vein", Ru = "Редкая жила (Утренняя ×3)", Context = "Morning Vein Tag (x3 Value)" },
	{ En = "Achievement Unlocked", Ru = "Достижение открыто", Context = "Achievement Toast Notification" },
	{ En = "You must be in the Shop zone.", Ru = "Вы должны находиться в зоне магазина.", Context = "Shop Zone Restriction Warning" },
	{ En = "The mine is closed at night.", Ru = "Ночью шахта закрыта.", Context = "Night Mine Entry Restriction Warning" },
	{ En = "Camo Scout Pack", Ru = "Камуфляжный рюкзак разведчика", Context = "Backpack Lvl 1" },
	{ En = "Wash Station", Ru = "Мойка", Context = "SELL zone backpack cleaning" },
	{ En = "TNT", Ru = "Динамит", Context = "Mine prop crate" },
	{ En = "NIGHT MERCHANT", Ru = "НОЧНОЙ ТОРГОВЕЦ", Context = "Night Merchant window title" },
	{ En = "Open only at night  •  Ore buyback 70%", Ru = "Работает только ночью  •  Скупка руды 70%", Context = "Night Merchant subtitle" },
	{ En = "Trade", Ru = "Торговать", Context = "Night Merchant prompt" },
	{ En = "BUY", Ru = "КУПИТЬ", Context = "Merchant card button" },
	{ En = "EQUIP", Ru = "НАДЕТЬ", Context = "Merchant cosmetic button" },
	{ En = "UNEQUIP", Ru = "СНЯТЬ", Context = "Merchant cosmetic button" },
	{ En = "ACTIVE", Ru = "АКТИВНО", Context = "Merchant Morning Bonus button" },
	{ En = "CLEAN", Ru = "ЧИСТО", Context = "Merchant Repair Kit button" },
	{ En = "Top Hat", Ru = "Цилиндр", Context = "Cosmetic" },
	{ En = "Miner Potion", Ru = "Зелье шахтёра", Context = "Consumable" },
	{ En = "Cleans all dirt from your backpack", Ru = "Полностью очищает рюкзак от грязи", Context = "Repair Kit desc" },
	{ En = "+XP and +Strength XP", Ru = "+Опыт и +опыт Силы", Context = "Book desc" },
	{ En = "Burger & soda: full energy", Ru = "Бургер и газировка: полная энергия", Context = "Food desc" },
	{ En = "Miner Potion: +25% coins at $ SELL, 3 min", Ru = "Зелье шахтёра: +25% монет на $ SELL, 3 мин", Context = "Potion desc" },
	{ En = "Top Hat, saved forever", Ru = "Цилиндр, сохраняется навсегда", Context = "Cosmetic desc" },
	{ En = "Coins + full energy at sunrise", Ru = "Монеты + полная энергия на рассвете", Context = "Morning Bonus desc" },
	{ En = "Your backpack is empty!", Ru = "Ваш рюкзак пуст!", Context = "Merchant error" },
	{ En = "The Night Merchant only trades at night!", Ru = "Ночной торговец торгует только ночью!", Context = "Merchant error" },
	{ En = "Come closer to the Night Merchant!", Ru = "Подойдите ближе к Ночному торговцу!", Context = "Merchant error" },
} :: { TranslationEntry }

LocalizationConfig.EN_TO_RU = {} :: { [string]: string }
for _, item in ipairs(LocalizationConfig.ENTRIES) do
	LocalizationConfig.EN_TO_RU[item.En] = item.Ru
end

function LocalizationConfig.Translate(enText: string, lang: string?): string
	if lang == "ru" or lang == "ru-ru" then
		return LocalizationConfig.EN_TO_RU[enText] or enText
	end
	return enText
end

function LocalizationConfig.RegisterRobloxLocalizationTable()
	pcall(function()
		local existing = LocalizationService:FindFirstChild("MinerSimulatorLocalization")
		if existing then return end
		local lt = Instance.new("LocalizationTable")
		lt.Name = "MinerSimulatorLocalization"
		lt.SourceLocaleId = "en-us"
		local entries = {}
		for _, item in ipairs(LocalizationConfig.ENTRIES) do
			table.insert(entries, {
				Key = item.En,
				Source = item.En,
				Context = item.Context,
				Values = { ["ru-ru"] = item.Ru },
			})
		end
		lt:SetEntries(entries)
		lt.Parent = LocalizationService
	end)
end

return LocalizationConfig
