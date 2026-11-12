--!strict
-- Модульный фасад генератора шахты 20x20x100 (раздел 10 ТЗ)
local MineManager = require(script.Parent:WaitForChild("MineManager"))
return {
	BuildInitialTemplate = MineManager.BuildInitialTemplate,
	InitMine = MineManager.InitMine,
	RespawnAllBlocksForNight = MineManager.RespawnAllBlocksForNight,
	TriggerRichVeinEvent = MineManager.TriggerRichVeinEvent,
}
