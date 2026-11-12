--!strict
-- Модульный фасад экономики и продажи руды (раздел 10 ТЗ)
local DataManager = require(script.Parent:WaitForChild("DataManager"))
return {
	GetBackpackSellValue = DataManager.GetBackpackSellValue,
	AutoSellOnWhitePad = DataManager.AutoSellOnWhitePad,
	BuyOrEquip3DPickaxe = DataManager.BuyOrEquip3DPickaxe,
	BuyStatUpgrade = DataManager.BuyStatUpgrade,
	GrantCaveChestReward = DataManager.GrantCaveChestReward,
}
