--!strict
-- ============================================================================
-- 🌙 MODULE: MerchantConfig (ReplicatedStorage.Modules.MerchantConfig)
-- Night Merchant: window texts, card order and colours, Treasure Map settings.
-- Prices of other items stay in GameConfig (RepairKitPrice, FOOD.Price, BOOSTS.Items.*);
-- the server sends the final prices to the client, the UI only displays them.
-- ============================================================================

export type CardStyle = {
	Id: string,
	Name: string,
	Desc: string,
	Button: string,
	Accent: Color3, -- outline / glow
	Bg0: Color3, -- card gradient: top-left
	Bg1: Color3, -- card gradient: bottom-right
	BtnTop: Color3,
	BtnBottom: Color3,
	BtnEdge: Color3, -- darker bottom edge of the "3D" button
}

local MerchantConfig = {}

MerchantConfig.Title = "NIGHT MERCHANT"
MerchantConfig.Subtitle = "Open only at night • Ore buyback 70%"
MerchantConfig.EmptyBag = "Backpack is empty"
MerchantConfig.SellFormat = "Sell ore: +%s coins (70%%)"
MerchantConfig.StockFormat = "Stock: %d/%d"
MerchantConfig.ActiveFormat = "Active: %s"

-- Card order: top row 3 cards, bottom row 2 cards (centred)
MerchantConfig.Order = { "RepairKit", "TreasureMap", "Food", "Potion", "Shield" }
MerchantConfig.TopRow = 3

MerchantConfig.Cards = {
	RepairKit = {
		Id = "RepairKit", Name = "Repair Kit", Desc = "Cleans all dirt from your backpack. Night only!", Button = "CLEAN",
		Accent = Color3.fromRGB(255, 70, 80), Bg0 = Color3.fromRGB(104, 24, 50), Bg1 = Color3.fromRGB(38, 12, 30),
		BtnTop = Color3.fromRGB(255, 96, 96), BtnBottom = Color3.fromRGB(214, 36, 48), BtnEdge = Color3.fromRGB(122, 14, 30),
	},
	TreasureMap = {
		Id = "TreasureMap", Name = "Treasure Map", Desc = "Discover hidden loot on the island!", Button = "BUY",
		Accent = Color3.fromRGB(255, 200, 50), Bg0 = Color3.fromRGB(104, 66, 16), Bg1 = Color3.fromRGB(40, 24, 18),
		BtnTop = Color3.fromRGB(255, 220, 70), BtnBottom = Color3.fromRGB(240, 170, 20), BtnEdge = Color3.fromRGB(140, 86, 8),
	},
	Food = {
		Id = "Food", Name = "Food", Desc = "Burger & soda to restore energy!", Button = "BUY",
		Accent = Color3.fromRGB(255, 142, 36), Bg0 = Color3.fromRGB(112, 50, 14), Bg1 = Color3.fromRGB(42, 20, 22),
		BtnTop = Color3.fromRGB(255, 168, 60), BtnBottom = Color3.fromRGB(240, 118, 20), BtnEdge = Color3.fromRGB(136, 62, 8),
	},
	Potion = {
		Id = "Potion", Name = "Miner Potion", Desc = "+25% coins at $ SELL for 3 minutes!", Button = "BUY",
		Accent = Color3.fromRGB(70, 226, 84), Bg0 = Color3.fromRGB(18, 88, 36), Bg1 = Color3.fromRGB(10, 34, 26),
		BtnTop = Color3.fromRGB(104, 236, 70), BtnBottom = Color3.fromRGB(40, 178, 50), BtnEdge = Color3.fromRGB(16, 94, 28),
	},
	Shield = {
		Id = "Shield", Name = "Shield Potion", Desc = "Gain a temporary shield!", Button = "BUY",
		Accent = Color3.fromRGB(60, 140, 255), Bg0 = Color3.fromRGB(18, 60, 138), Bg1 = Color3.fromRGB(12, 24, 66),
		BtnTop = Color3.fromRGB(80, 176, 255), BtnBottom = Color3.fromRGB(36, 100, 236), BtnEdge = Color3.fromRGB(14, 52, 150),
	},
} :: { [string]: CardStyle }

-- Window palette
MerchantConfig.Palette = {
	PanelTop = Color3.fromRGB(44, 26, 98),
	PanelBottom = Color3.fromRGB(14, 12, 46),
	PanelStroke = Color3.fromRGB(150, 96, 255),
	Gold = Color3.fromRGB(255, 205, 80),
	GoldLight = Color3.fromRGB(255, 240, 150),
	GoldDark = Color3.fromRGB(255, 160, 30),
	Muted = Color3.fromRGB(176, 166, 224),
	Desc = Color3.fromRGB(230, 224, 246),
	Ok = Color3.fromRGB(130, 240, 150),
	Fail = Color3.fromRGB(255, 130, 110),
}

-- Treasure Map: the price is x2.5 of the original 250 like all other prices
MerchantConfig.TreasureMap = {
	Price = 625,
	LootMin = 1.3, -- coins = Price * random(LootMin..LootMax)
	LootMax = 2.4,
	XpBase = 40, -- + XpPerLevel * player level
	XpPerLevel = 10,
	HoldSeconds = 0.8,
	-- Axis mapping for the direction hint: -Z is north (where the mine is), +X is east.
	-- Open ground on the island: outside the mine pit X[-66,66] Z[-144,-13], the spawn plaza,
	-- the merchant stall (0,46 r20), the SELL market (-32,6) and the SHOP pavilion (32,6).
	Spots = {
		Vector2.new(-58, 24), Vector2.new(-46, 40), Vector2.new(-60, 54), Vector2.new(-36, 56),
		Vector2.new(-62, 14), Vector2.new(28, 58), Vector2.new(36, 40), Vector2.new(50, 56),
		Vector2.new(60, 30), Vector2.new(72, 12), Vector2.new(73, -30), Vector2.new(73, -75),
		Vector2.new(74, -120),
	},
}

return MerchantConfig
