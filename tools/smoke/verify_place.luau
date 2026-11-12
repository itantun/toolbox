--!nocheck
-- Проверка собранного места: файл читается как место Roblox, все скрипты на месте.
-- Запуск: lune run tools/smoke/verify_place.luau place/MinerSimulator_v52.rbxlx
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local process = require("@lune/process")

local path = process.args[1]
local game = roblox.deserializePlace(fs.readFile(path))

local expected = {
	{ "ReplicatedStorage", "Modules", { "GameConfig", "PartKit", "UIKit", "ClientBus", "PickaxeJuice", "OreIconModels", "EquipmentBuilder", "ToolAnimator" } },
	{ "ServerScriptService", "Modules", { "BoostService", "NightCycleService", "NightWallBuilder", "ShopService", "SpawnPlazaBuilder", "DataManager", "EquipmentManager", "WorldBuilder", "MineManager" } },
}
local missing = 0
for _, group in ipairs(expected) do
	local folder = game:GetService(group[1]):FindFirstChild(group[2])
	for _, name in ipairs(group[3]) do
		local inst = folder and folder:FindFirstChild(name)
		if not inst or not inst:IsA("ModuleScript") or #inst.Source < 50 then
			missing += 1
			print("MISSING " .. group[1] .. "." .. group[2] .. "." .. name)
		end
	end
end

local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
for _, name in ipairs({ "ClientController", "ProgressionUI", "LiveOreFX", "SprintController", "BoostShopUI", "BackpackUI", "PhaseHud", "NightFX", "PickaxeFX" }) do
	local inst = sps and sps:FindFirstChild(name)
	if not inst or not inst:IsA("LocalScript") or #inst.Source < 50 then
		missing += 1
		print("MISSING StarterPlayerScripts." .. name)
	end
end

local main = game:GetService("ServerScriptService"):FindFirstChild("ServerMain")
if not main or not main:IsA("Script") then
	missing += 1
	print("MISSING ServerScriptService.ServerMain")
end

local bootstrap = game:GetService("StarterGui"):FindFirstChild("MinerClientBootstrap")
local mirror = bootstrap and bootstrap:FindFirstChild("ClientController")
local original = sps and sps:FindFirstChild("ClientController")
if not mirror or not original or mirror.Source ~= original.Source then
	missing += 1
	print("MIRROR MISMATCH StarterGui.MinerClientBootstrap.ClientController")
end

local scripts = 0
for _, d in ipairs(game:GetDescendants()) do
	if d:IsA("LuaSourceContainer") then
		scripts += 1
	end
end
print(string.format("scripts in place: %d, problems: %d", scripts, missing))
process.exit(missing == 0 and 0 or 1)
