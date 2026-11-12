--!strict
-- Модульный фасад сохранения профилей в DataStore (раздел 10 ТЗ)
local DataManager = require(script.Parent:WaitForChild("DataManager"))
return {
	LoadPlayerProfile = DataManager.LoadPlayerProfile,
	SavePlayerProfile = DataManager.SavePlayerProfile,
	StartAutoSaveLoop = DataManager.StartAutoSaveLoop,
}
