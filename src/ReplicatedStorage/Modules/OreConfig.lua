--!strict
-- ============================================================================
-- 💎 МОДУЛЬ: OreConfig (ReplicatedStorage.Modules.OreConfig)
-- Версия: v13.0 — Конфигурация 16 пород, Утренних залежей (×3), 10 кирок и 10 рюкзаков.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local OreConfig = {}

OreConfig.Blocks = GameConfig.BLOCK_LIST
OreConfig.ById = GameConfig.BLOCK_TYPES
OreConfig.DepthBands = GameConfig.DEPTH_BANDS
OreConfig.Pickaxes = GameConfig.PICKAXE_TIERS
OreConfig.Backpacks = GameConfig.BACKPACK_TIERS
OreConfig.MorningVeins = GameConfig.MORNING_VEINS
OreConfig.Textures = GameConfig.TEXTURES
OreConfig.Energy = GameConfig.ENERGY
OreConfig.AntiFarm = GameConfig.ANTI_FARM

function OreConfig.GetOreInfo(oreId: string)
	return GameConfig.BLOCK_TYPES[oreId] or GameConfig.BLOCK_TYPES.Stone
end

function OreConfig.GetDepthBand(depthBlocks: number)
	return GameConfig.GetDepthBand(depthBlocks)
end

function OreConfig.CanPickaxeMine(pickaxeLevel: number, oreId: string): (boolean, number, string)
	local info = OreConfig.GetOreInfo(oreId)
	local reqLvl = info.MinPickaxeLevel or 1
	local curLvl = math.max(1, math.floor(pickaxeLevel))
	if curLvl >= reqLvl then
		return true, 1.0, ""
	end
	local reqPick = GameConfig.PICKAXE_TIERS[reqLvl]
	local reqName = reqPick and reqPick.Name or ("Pickaxe Lv." .. reqLvl)
	return false, 0.08, string.format("⚠️ Too hard! You need %s (Lv.%d)", reqName, reqLvl)
end

return OreConfig
