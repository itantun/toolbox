--!strict
-- ============================================================================
-- 💎 МОДУЛЬ: OreIconModels (ReplicatedStorage.Modules.OreIconModels)
-- v52: 3D-иконка руды для ViewportFrame — базовый камень + кристаллы / самородки
-- цвета руды. Собирается из Part-ов по данным GameConfig.BLOCK_TYPES; форма
-- детерминирована (Random.new от имени руды), поэтому иконка всегда одинакова.
-- Настройки камеры и размеров — GameConfig.ORE_ICON.
-- ============================================================================

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local PartKit = require(script.Parent:WaitForChild("PartKit"))

local OreIconModels = {}

-- Руды, у которых вкрапления выглядят как вытянутые кристаллы (остальные — самородки)
local CRYSTAL_STYLES: { [string]: boolean } = {
	CrystalClusters = true,
	EmeraldTiles = true,
	MithrilVeins = true,
	IceFrost = true,
	VoidCracks = true,
}

local function seedOf(text: string): number
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end

-- Собирает модель иконки с центром в начале координат. PrimaryPart — базовый камень.
function OreIconModels.Build(oreId: string): Model
	local info: any = GameConfig.BLOCK_TYPES[oreId] or GameConfig.BLOCK_TYPES.Stone
	local cfg = GameConfig.ORE_ICON
	local rng = Random.new(seedOf(oreId) + cfg.Seed)

	local model = Instance.new("Model")
	model.Name = "OreIcon_" .. oreId

	local rockColor: Color3 = info.Color
	local rockMat: Enum.Material = info.Mat
	local accent: Color3 = info.AccentColor
	local accent2: Color3 = info.SecondaryAccent or PartKit.Lighten(accent, 0.25)
	local glow = info.HasGlow == true
	local inclMat: Enum.Material = glow and Enum.Material.Neon or info.InclusionMat

	-- 1) Базовый камень: центральная глыба и неровные обломки вокруг
	local base = PartKit.Block(
		model, "Rock", Vector3.new(1.7, 1.15, 1.5),
		CFrame.new(0, -0.25, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), math.rad(rng:NextNumber(-6, 6))),
		rockColor, rockMat
	)
	for i = 1, cfg.RockChunks do
		local a = (i / cfg.RockChunks) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local size = Vector3.new(rng:NextNumber(0.7, 1.1), rng:NextNumber(0.55, 0.95), rng:NextNumber(0.7, 1.1))
		local shade = rng:NextNumber(-0.12, 0.1)
		local color = shade >= 0 and PartKit.Lighten(rockColor, shade) or PartKit.Darken(rockColor, -shade)
		PartKit.Block(
			model, "RockChunk", size,
			CFrame.new(math.cos(a) * 0.72, -0.35 + rng:NextNumber(-0.12, 0.15), math.sin(a) * 0.66)
				* CFrame.Angles(math.rad(rng:NextNumber(-22, 22)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-22, 22))),
			color, rockMat
		)
	end

	if CRYSTAL_STYLES[info.InclusionStyle] then
		-- 2a) Друза кристаллов: высокий центральный и наклонённые наружу боковые
		local count = cfg.CrystalCount
		for i = 1, count do
			local central = i == 1
			local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.35, 0.35)
			local r = central and 0 or rng:NextNumber(0.32, 0.62)
			local h = central and rng:NextNumber(1.35, 1.6) or rng:NextNumber(0.65, 1.15)
			local w = central and 0.42 or rng:NextNumber(0.24, 0.36)
			local tilt = central and math.rad(rng:NextNumber(-6, 6)) or math.rad(18 + r * 38)
			local color = (i % 3 == 0) and accent2 or accent
			-- ось кристалла: наклон наружу от центра друзы
			local rootCF = CFrame.new(math.cos(a) * r, 0.15, math.sin(a) * r)
				* CFrame.Angles(0, -a, 0)
				* CFrame.Angles(0, 0, -tilt)
			local body = PartKit.Block(
				model, "Crystal", Vector3.new(w, h, w),
				rootCF * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0),
				color, inclMat, { Reflectance = glow and 0 or 0.25, Transparency = (inclMat == Enum.Material.Glass) and 0.15 or 0 }
			)
			-- остриё: куб, поставленный на вершину
			PartKit.Block(
				model, "CrystalTip", Vector3.new(w * 0.72, w * 0.72, w * 0.72),
				rootCF * CFrame.new(0, h, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.26)),
				PartKit.Lighten(color, 0.2), inclMat, { Reflectance = glow and 0 or 0.25, Transparency = body.Transparency }
			)
		end
	else
		-- 2b) Самородки / вкрапления на верхней половине камня
		local count = cfg.NuggetCount
		for i = 1, count do
			local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			local up = rng:NextNumber(0.15, 0.95)
			local flat = math.sqrt(math.max(0, 1 - up * up))
			local pos = Vector3.new(math.cos(a) * flat * 0.95, -0.2 + up * 0.72, math.sin(a) * flat * 0.85)
			local size = rng:NextNumber(0.26, 0.5)
			local color = (i % 3 == 0) and accent2 or accent
			local cf = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3))
			if i % 2 == 0 then
				PartKit.Ball(model, "Nugget", size, cf, color, inclMat, { Reflectance = glow and 0 or 0.18 })
			else
				PartKit.Block(model, "Nugget", Vector3.new(size, size * 0.8, size * 1.1), cf, color, inclMat, { Reflectance = glow and 0 or 0.18 })
			end
		end
		if info.InclusionStyle == "LavaCracks" then
			-- светящиеся трещины магмы поверх камня
			for i = 1, 3 do
				PartKit.Block(
					model, "LavaCrack", Vector3.new(1.5, 0.06, 0.09),
					CFrame.new(0, 0.34, -0.4 + i * 0.22) * CFrame.Angles(0, math.rad(rng:NextNumber(-40, 40)), 0),
					accent, Enum.Material.Neon
				)
			end
		end
	end

	model.PrimaryPart = base
	model:SetAttribute("Glow", glow)
	return model
end

return OreIconModels
