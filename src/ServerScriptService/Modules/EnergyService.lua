--!strict
-- Модульный фасад выносливости/энергии шахтёра (раздел 10 ТЗ)
local DataManager = require(script.Parent:WaitForChild("DataManager"))
return {
	GetMaxEnergy = DataManager.GetMaxEnergy,
	TryConsumeEnergy = DataManager.TryConsumeEnergy,
	StartEnergyRegenLoop = DataManager.StartEnergyRegenLoop,
}
