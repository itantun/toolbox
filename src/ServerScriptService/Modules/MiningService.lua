--!strict
-- Модульный фасад серверной копки и анти-эксплойта (раздел 10 ТЗ)
local MineManager = require(script.Parent:WaitForChild("MineManager"))
return {
	HandleMineHit = MineManager.HandleMineHit,
	CleanupPlayer = MineManager.CleanupPlayer,
}
