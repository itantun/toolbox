--!nocheck
-- Дымовой прогон процедурных сборщиков вне Roblox (Lune + @lune/roblox).
-- Загружает ModuleScript-ы из src/ в поддельный DataModel и реально выполняет сборку:
-- кирки и рюкзаки 1..10, 3D-иконки руды, ночную стену, площадь спавна.
-- Lune проверяет имена свойств, типы значений и Enum-ы, поэтому опечатки и nil-ошибки
-- ловятся здесь, а не в Output игры. Запуск: lune run tools/smoke/smoke.luau
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local task = require("@lune/task")
local process = require("@lune/process")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local ROOT = process.cwd
if string.sub(ROOT, -1) ~= "/" then
	ROOT ..= "/"
end
local SRC = ROOT .. "src/"

-- Детерминированная замена Random
local RandomMT = {}
RandomMT.__index = RandomMT
function RandomMT.new(seed)
	return setmetatable({ s = (math.floor(seed or 1) % 2147483646) + 1 }, RandomMT)
end
local function step(self)
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function RandomMT:NextNumber(a, b)
	local r = step(self)
	if a and b then
		return a + (b - a) * r
	end
	return r
end
function RandomMT:NextInteger(a, b)
	return a + math.floor(step(self) * (b - a + 1))
end

-- Недостающие в Lune методы
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local found = self:FindFirstChild(name)
	if not found then
		error("WaitForChild: нет дочернего объекта " .. tostring(name) .. " у " .. self:GetFullName())
	end
	return found
end)
roblox.implementMethod("CollectionService", "AddTag", function(_self, inst, tag)
	inst:AddTag(tag)
end)
roblox.implementMethod("Players", "GetPlayerFromCharacter", function()
	return nil
end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return os.clock()
end)

local game = Instance.new("DataModel")
local services = { "ReplicatedStorage", "ServerScriptService", "StarterPlayer", "Workspace", "CollectionService", "Players", "Lighting", "TweenService", "Debris", "MaterialService", "RunService", "SoundService" }
for _, name in ipairs(services) do
	pcall(function()
		game:GetService(name)
	end)
end

local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function loadTree(dir, parent)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. entry
		if fs.isDir(path) then
			loadTree(path .. "/", ensureFolder(parent, entry))
		elseif string.sub(entry, -4) == ".lua" and not string.find(entry, "%.client%.lua$") and not string.find(entry, "%.server%.lua$") then
			local m = Instance.new("ModuleScript")
			m.Name = string.sub(entry, 1, -5)
			m.Source = fs.readFile(path)
			m.Parent = parent
		end
	end
end
loadTree(SRC .. "ReplicatedStorage/", game:GetService("ReplicatedStorage"))
loadTree(SRC .. "ServerScriptService/", game:GetService("ServerScriptService"))

-- CollectionService: в Lune метод AddTag(экземпляр, тег) перекрыт Instance:AddTag, поэтому подменяем сервис
local fakeCollection = {}
function fakeCollection:AddTag(inst, tag)
	inst:AddTag(tag)
end
function fakeCollection:GetTagged()
	return {}
end
local gameProxy = {}
function gameProxy:GetService(name)
	if name == "CollectionService" then
		return fakeCollection
	end
	return game:GetService(name)
end

local warnings = {}
local cache = {}
local env
local function requireModule(inst)
	if cache[inst] ~= nil then
		return cache[inst]
	end
	local moduleEnv = { script = inst }
	for key, value in pairs(env) do
		moduleEnv[key] = value
	end
	local fn = luau.load(inst.Source, { debugName = inst.Name, environment = moduleEnv })
	local result = fn()
	cache[inst] = result
	return result
end
env = {
	game = gameProxy, workspace = game:GetService("Workspace"), Instance = Instance, Random = RandomMT, task = task,
	require = requireModule,
	warn = function(...)
		table.insert(warnings, table.concat({ ... }, " "))
	end,
	print = function() end,
	Enum = roblox.Enum, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame, Color3 = roblox.Color3,
	UDim = roblox.UDim, UDim2 = roblox.UDim2, ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, NumberRange = roblox.NumberRange,
	Font = roblox.Font, BrickColor = roblox.BrickColor,
	math = math, string = string, table = table, os = os, ipairs = ipairs, pairs = pairs, next = next, type = type, typeof = typeof,
	tostring = tostring, tonumber = tonumber, pcall = pcall, error = error, select = select, setmetatable = setmetatable,
	getmetatable = getmetatable, assert = assert, unpack = unpack, utf8 = utf8, bit32 = bit32,
}

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Modules = RS.Modules
local ServerModules = SSS.Modules

local function stats(root)
	local parts, lights, emitters, unanchored = 0, 0, 0, 0
	local minV, maxV = Vector3.new(1e9, 1e9, 1e9), Vector3.new(-1e9, -1e9, -1e9)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			if not d.Anchored then
				unanchored += 1
			end
			local cf, sz = d.CFrame, d.Size
			local hx = (math.abs(cf.RightVector.X) * sz.X + math.abs(cf.UpVector.X) * sz.Y + math.abs(cf.LookVector.X) * sz.Z) / 2
			local hy = (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z) / 2
			local hz = (math.abs(cf.RightVector.Z) * sz.X + math.abs(cf.UpVector.Z) * sz.Y + math.abs(cf.LookVector.Z) * sz.Z) / 2
			minV = Vector3.new(math.min(minV.X, cf.X - hx), math.min(minV.Y, cf.Y - hy), math.min(minV.Z, cf.Z - hz))
			maxV = Vector3.new(math.max(maxV.X, cf.X + hx), math.max(maxV.Y, cf.Y + hy), math.max(maxV.Z, cf.Z + hz))
		elseif d:IsA("Light") then
			lights += 1
		elseif d:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	return string.format("parts=%d lights=%d emitters=%d unanchored=%d  box=(%.1f..%.1f, %.1f..%.1f, %.1f..%.1f)",
		parts, lights, emitters, unanchored, minV.X, maxV.X, minV.Y, maxV.Y, minV.Z, maxV.Z)
end

local failed = 0
local function run(label, fn)
	local before = #warnings
	local ok, res = pcall(fn)
	if not ok then
		failed += 1
		print("FAIL  " .. label .. ": " .. tostring(res))
	elseif #warnings > before then
		failed += 1
		print("WARN  " .. label .. ": " .. warnings[#warnings])
	else
		print("ok    " .. label .. (res and ("  " .. res) or ""))
	end
end

local GameConfig
run("GameConfig", function()
	GameConfig = requireModule(Modules.GameConfig)
end)
local Builder
run("EquipmentBuilder require", function()
	Builder = requireModule(Modules.EquipmentBuilder)
end)

local world = Instance.new("Folder")
world.Name = "MinerWorld"
world.Parent = game:GetService("Workspace")

for level = 1, 10 do
	run("pickaxe " .. level .. " (в руке)", function()
		local m = Instance.new("Model")
		Builder.BuildModernPickaxeParts(m, level, roblox.CFrame.new(), false, { Scale = 0.65 })
		return stats(m)
	end)
	run("pickaxe " .. level .. " (превью)", function()
		local m = Instance.new("Model")
		Builder.BuildModernPickaxeParts(m, level, roblox.CFrame.new(), true, { Scale = 1, LowDetail = true, ForViewport = true })
		return stats(m)
	end)
	run("backpack " .. level .. " (на спине)", function()
		local m = Instance.new("Model")
		local torso = Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Size = roblox.Vector3.new(2, 1.6, 1)
		torso.CFrame = roblox.CFrame.new(0, 3, 0)
		Builder.BuildBackpackParts(m, level, torso, false, 1.0)
		local minZ, minName = 1e9, "?"
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and not string.find(d.Name, "Strap") then
				local cf, sz = d.CFrame, d.Size
				local hz = (math.abs(cf.RightVector.Z) * sz.X + math.abs(cf.UpVector.Z) * sz.Y + math.abs(cf.LookVector.Z) * sz.Z) / 2
				if cf.Z - hz < minZ then
					minZ = cf.Z - hz
					minName = d.Name
				end
			end
		end
		return stats(m) .. string.format("  ближайшая к спине деталь %s z=%.2f (спина торса z=0.50)", minName, minZ)
	end)
	run("backpack " .. level .. " (превью)", function()
		local m = Instance.new("Model")
		Builder.BuildBackpackParts(m, level, roblox.CFrame.new(), true, 1.0)
		return stats(m)
	end)
end

run("ore icons", function()
	local Icons = requireModule(Modules.OreIconModels)
	local total = 0
	for _, info in ipairs(GameConfig.BLOCK_LIST) do
		local m = Icons.Build(info.Id)
		total += #m:GetChildren()
		assert(m.PrimaryPart, "нет PrimaryPart у " .. info.Id)
	end
	return "ores=" .. #GameConfig.BLOCK_LIST .. " parts=" .. total
end)

run("merchant icons", function()
	local Icons = requireModule(Modules.MerchantIconModels)
	local total = 0
	for _, id in ipairs(Icons.Ids) do
		local m = Icons.Build(id)
		local parts = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		assert(parts >= 10, "слишком мало деталей в иконке " .. id .. ": " .. parts)
		assert(m.PrimaryPart, "нет PrimaryPart у иконки " .. id)
		assert(Icons.Camera(id).Distance > 0, "нет камеры для " .. id)
		total += parts
	end
	local MerchantConfig = requireModule(Modules.MerchantConfig)
	for _, id in ipairs(MerchantConfig.Order) do
		assert(MerchantConfig.Cards[id], "нет карточки " .. id)
		assert(table.find(Icons.Ids, id), "нет иконки " .. id)
	end
	return "icons=" .. #Icons.Ids .. " parts=" .. total
end)

run("treasure marker + spots", function()
	local Service = requireModule(ServerModules.TreasureMapService)
	local m = Service.BuildMarker("Tester")
	local parts = 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	assert(parts >= 15, "слишком мало деталей в маркере клада: " .. parts)
	assert(m:FindFirstChild("DigPrompt", true), "нет ProximityPrompt «Dig»")
	assert(m:FindFirstChild("TreasureTag", true), "нет BillboardGui с именем")
	local dirName, studs = Service.Describe(roblox.Vector3.new(0, 0, 46), roblox.Vector3.new(0, 0, -39))
	assert(dirName == "north" and studs == 85, "Describe: " .. dirName .. " " .. studs)
	local dir2 = Service.Describe(roblox.Vector3.new(0, 0, 46), roblox.Vector3.new(60, 0, -14))
	assert(dir2 == "north-east", "Describe NE: " .. dir2)
	-- spots lie on open ground: not in the mine pit, spawn plaza, stall radius or inside the map bounds
	local MC = requireModule(Modules.MerchantConfig)
	local B = GameConfig.MAP_BOUNDS
	for _, s in ipairs(MC.TreasureMap.Spots) do
		local x, z = s.X, s.Y
		assert(not (x >= -66 and x <= 66 and z >= -144 and z <= -13), "клад в шахте: " .. x .. "," .. z)
		assert(not (x >= -17 and x <= 17 and z >= 13.5 and z <= 33), "клад на площади спавна: " .. x .. "," .. z)
		assert(math.sqrt(x * x + (z - 46) ^ 2) > 20, "клад у лавки торговца: " .. x .. "," .. z)
		assert(math.sqrt((x + 32) ^ 2 + (z - 6) ^ 2) > 20 and math.sqrt((x - 32) ^ 2 + (z - 6) ^ 2) > 20, "клад у рынка/магазина: " .. x .. "," .. z)
		assert(x > B.MinX + 4 and x < B.MaxX - 4 and z > B.MinZ + 4 and z < B.MaxZ - 4, "клад у края карты: " .. x .. "," .. z)
	end
	return "marker parts=" .. parts .. " spots=" .. #MC.TreasureMap.Spots
end)

run("NightWallBuilder", function()
	local WallBuilder = requireModule(ServerModules.NightWallBuilder)
	local refs = WallBuilder.Build(world)
	local down = stats(refs.Model)
	-- днём стена целиком под землёй и невидима, крышка прозрачна
	assert(#refs.WallParts > 100, "мало деталей стены: " .. #refs.WallParts)
	for _, p in ipairs(refs.WallParts) do
		assert(p.CFrame.Position.Y + p.Size.Y / 2 < -1, "деталь стены торчит днём: " .. p.Name .. " y=" .. p.CFrame.Position.Y)
		assert(p.Transparency == 1, "деталь стены видна днём: " .. p.Name)
	end
	assert(#refs.LidParts == 46, "ожидалось 46 деталей крышки, найдено " .. #refs.LidParts)
	for _, p in ipairs(refs.LidParts) do
		assert(p.Transparency == 1, "крышка видна днём: " .. p.Name)
	end
	WallBuilder.SetRaised(refs, true)
	local shown = 0
	local widest = 0
	for _, p in ipairs(refs.WallParts) do
		if p.Transparency == 0 then
			shown += 1
		end
		widest = math.max(widest, math.abs(p.CFrame.Position.X) + p.Size.X / 2)
	end
	assert(shown > 100, "стена не показалась ночью: " .. shown)
	assert(widest >= 64, "стена не дотягивается до углов карьера: " .. widest)
	for _, b in ipairs(refs.Blockers) do
		assert(b.CanCollide == true, "блокер не включился: " .. b.Name)
	end
	WallBuilder.SetRaised(refs, false)
	for _, b in ipairs(refs.Blockers) do
		assert(b.CanCollide == false, "блокер не выключился: " .. b.Name)
	end
	local countdown = 0
	for _, d in ipairs(refs.Model:GetDescendants()) do
		if d:IsA("TextLabel") and d:HasTag("NightWallCountdown") then
			countdown += 1
		end
	end
	assert(countdown == 4, "ожидалось 4 надписи отсчёта, найдено " .. countdown)
	return down .. "  blockers=" .. #refs.Blockers
end)

run("SpawnPlazaBuilder", function()
	local refs = requireModule(ServerModules.SpawnPlazaBuilder).Build(world)
	assert(refs.SpawnLocation:IsA("SpawnLocation"), "нет SpawnLocation")
	return stats(refs.Model)
end)

run("MerchantNpcBuilder (запасной персонаж)", function()
	local Npc = requireModule(ServerModules.MerchantNpcBuilder)
	local stall = Instance.new("Model")
	stall.Name = "NightMerchantStall"
	local fallback = Npc.Build(stall, roblox.CFrame.new(0, 0.3, -2.7), { LoadAvatar = false })
	assert(fallback.Parent == stall, "запасной персонаж не в лавке")
	local head = fallback:FindFirstChild("Head")
	assert(head and head:IsA("BasePart"), "нет головы")
	assert(head:FindFirstChildOfClass("SpecialMesh") and head:FindFirstChildOfClass("Decal"), "у головы нет меша или лица")
	local tag = stall:FindFirstChild("MerchantName", true)
	assert(tag and tag:IsA("BillboardGui"), "нет таблички MerchantName")
	local count = 0
	for _, d in ipairs(fallback:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
			assert(d.Anchored and not d.CanCollide, "деталь должна быть закреплена и без коллизий: " .. d.Name)
		end
	end
	assert(count > 20 and count < 70, "неожиданное число деталей: " .. count)
	for _ = 1, 3 do
		Npc.SetActive(stall, true)
		Npc.SetActive(stall, false)
	end
	return stats(fallback)
end)

run("server modules load", function()
	requireModule(ServerModules.BoostService)
	requireModule(ServerModules.NightCycleService)
	requireModule(ServerModules.ShopService)
	requireModule(ServerModules.TreasureMapService)
	return nil
end)

print(failed == 0 and "SMOKE OK" or ("SMOKE FAILED: " .. failed))
process.exit(failed == 0 and 0 or 1)
