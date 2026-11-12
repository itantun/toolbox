--!strict
-- ============================================================================
-- 🛒 МОДУЛЬ: MarketBuilder (ServerScriptService.Modules.MarketBuilder)
-- Процедурно строит рынок: деревянный прилавок с тентом и гирляндой, ковёр,
-- бочки, ящики, весы, образцы руды, полки с товарами и НОВОГО торговца Гошу
-- (модель из деталей, без Humanoid, на Motor6D — анимируется на клиенте
-- скриптом TraderAnimator). Только Part/Cylinder/Ball, внешних ассетов нет.
-- Лавка смотрит в +Z; торговец стоит за прилавком (Z меньше центра).
-- Сервер НЕ подключает Triggered — это делает скрипт магазина.
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PartKit = require(Shared:WaitForChild("PartKit"))

local CFG = GameConfig.MARKET
local COL = CFG.Colors
local M = Enum.Material

export type MarketRefs = {
	Model: Model,
	Prompt: ProximityPrompt,
	Trader: Model,
	Pad: BasePart,
}

local MarketBuilder = {}

-- Состояние текущей сборки: центр рынка и детерминированный генератор
local ox = 0
local oz = 0
local rng: Random = Random.new(CFG.Seed)

-- ============================================================================
-- Помощники
-- ============================================================================

-- Мировой CFrame из локальных координат рынка (Y — абсолютный, земля = 0)
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(ox + x, y, oz + z)
end

local function world(x: number, y: number, z: number): Vector3
	return Vector3.new(ox + x, y, oz + z)
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): Part
	return PartKit.Block(parent, name, size, cf, color, mat, { CanCollide = collide == true })
end

local function cyl(parent: Instance, name: string, d: number, h: number, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): Part
	return PartKit.Cylinder(parent, name, d, h, cf, color, mat, { CanCollide = collide == true })
end

local function ball(parent: Instance, name: string, d: number, cf: CFrame, color: Color3, mat: Enum.Material): Part
	return PartKit.Ball(parent, name, d, cf, color, mat)
end

local function ell(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	return PartKit.Ellipsoid(parent, name, size, cf, color, mat)
end

-- Тонкий стержень/цепь/проволока между двумя точками
local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, thick: number, color: Color3, mat: Enum.Material): Part
	local len = math.max((b - a).Magnitude, 0.05)
	return PartKit.Block(parent, name, Vector3.new(thick, thick, len), CFrame.lookAt((a + b) / 2, b), color, mat)
end

local function tone(list: { Color3 }): Color3
	return list[rng:NextInteger(1, #list)]
end

-- Небольшой разброс яркости, чтобы доски не выглядели одинаковыми
local function vary(c: Color3, a: number): Color3
	local t = rng:NextNumber(-a, a)
	if t >= 0 then
		return PartKit.Lighten(c, t)
	end
	return PartKit.Darken(c, -t)
end

-- Высота нижней стороны тента на заданном Z (локальные координаты)
local function roofUnderY(z: number): number
	local r = CFG.Roof
	return r.FrontY + (r.FrontZ - z) * (r.BackY - r.FrontY) / (r.FrontZ - r.BackZ)
end

-- ============================================================================
-- Мелкие модели: кристалл, образец руды, мешок, ящик, бочка, фонарь
-- ============================================================================

-- Кристалл: cf — основание, растёт вдоль +Y
local function crystal(parent: Instance, cf: CFrame, h: number, color: Color3)
	local w = h * 0.34
	local shaft = box(parent, "Crystal", Vector3.new(w, h, w), cf * CFrame.new(0, h / 2, 0), color, M.Neon)
	shaft.Transparency = 0.1
	local tip = box(parent, "CrystalTip", Vector3.new(w * 0.72, w * 0.72, w * 0.72), cf * CFrame.new(0, h + w * 0.1, 0) * CFrame.Angles(math.pi / 4, math.pi / 4, 0), PartKit.Lighten(color, 0.35), M.Neon)
	tip.Transparency = 0.05
end

-- Образец: камень с двумя кристаллами
local function oreSample(parent: Instance, cf: CFrame, color: Color3)
	box(parent, "SampleRock", Vector3.new(0.95, 0.5, 0.8), cf * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), COL.RockDark, M.Slate)
	crystal(parent, cf * CFrame.new(-0.18, 0.45, 0.05) * CFrame.Angles(0.15, 0, 0.2), 0.5, color)
	crystal(parent, cf * CFrame.new(0.2, 0.4, -0.1) * CFrame.Angles(-0.2, 0, -0.3), 0.35, color)
end

-- Мешок с завязкой; gem — необязательные кристаллы сверху
local function sack(parent: Instance, cf: CFrame, s: number, gem: Color3?)
	ell(parent, "SackBody", Vector3.new(1.5 * s, 1.5 * s, 1.3 * s), cf * CFrame.new(0, 0.7 * s, 0), vary(COL.Burlap, 0.06), M.Fabric)
	ell(parent, "SackFold", Vector3.new(0.9 * s, 0.55 * s, 0.8 * s), cf * CFrame.new(0, 1.45 * s, 0), COL.BurlapDark, M.Fabric)
	cyl(parent, "SackTie", 0.85 * s, 0.1, cf * CFrame.new(0, 1.25 * s, 0), COL.Rope, M.Fabric)
	if s >= 1 then
		box(parent, "SackPatch", Vector3.new(0.5 * s, 0.45 * s, 0.06), cf * CFrame.new(0.3 * s, 0.75 * s, -0.62 * s), COL.BurlapDark, M.Fabric)
	end
	if gem then
		crystal(parent, cf * CFrame.new(-0.2 * s, 1.5 * s, 0) * CFrame.Angles(0, 0, 0.25), 0.55 * s, gem)
		crystal(parent, cf * CFrame.new(0.22 * s, 1.5 * s, 0.05) * CFrame.Angles(0.2, 0, -0.3), 0.42 * s, gem)
	end
end

-- Деревянный ящик (каркас + рейки): cf — центр основания, s — размер
local function crate(parent: Instance, cf: CFrame, s: number)
	box(parent, "CrateCore", Vector3.new(s - 0.08, s - 0.08, s - 0.08), cf * CFrame.new(0, s / 2, 0), COL.WoodDeep, M.Wood, true)
	local e = s / 2 - 0.1
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			box(parent, "CratePost", Vector3.new(0.2, s, 0.2), cf * CFrame.new(sx * e, s / 2, sz * e), vary(COL.WoodDark, 0.08), M.Wood)
		end
	end
	if s < 1.6 then
		return -- маленькие ящики: только каркас, без реек
	end
	for _, sz in ipairs({ -1, 1 }) do
		for _, ky in ipairs({ 0.3, 0.7 }) do
			box(parent, "CrateSlat", Vector3.new(s - 0.1, 0.26, 0.08), cf * CFrame.new(0, s * ky, sz * (s / 2 - 0.02)), vary(tone(COL.WoodTones), 0.06), M.Wood)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		box(parent, "CrateSlatSide", Vector3.new(0.08, 0.26, s - 0.1), cf * CFrame.new(sx * (s / 2 - 0.02), s * 0.5, 0), vary(tone(COL.WoodTones), 0.06), M.Wood)
	end
end

-- Бочка с металлическими обручами: cf — центр основания; withOre — открытая, с самородками
local function barrel(parent: Instance, cf: CFrame, withOre: boolean)
	cyl(parent, "BarrelLow", 1.7, 0.9, cf * CFrame.new(0, 0.45, 0), vary(COL.WoodMid, 0.06), M.Wood, true)
	cyl(parent, "BarrelMid", 2.0, 1.0, cf * CFrame.new(0, 1.4, 0), vary(COL.WoodMid, 0.06), M.Wood, true)
	cyl(parent, "BarrelTop", 1.7, 0.9, cf * CFrame.new(0, 2.35, 0), vary(COL.WoodMid, 0.06), M.Wood, true)
	cyl(parent, "BarrelHoop", 1.78, 0.12, cf * CFrame.new(0, 0.35, 0), COL.Metal, M.Metal)
	cyl(parent, "BarrelHoop", 2.07, 0.12, cf * CFrame.new(0, 1.0, 0), COL.Metal, M.Metal)
	cyl(parent, "BarrelHoop", 2.07, 0.12, cf * CFrame.new(0, 1.8, 0), COL.Metal, M.Metal)
	cyl(parent, "BarrelHoop", 1.78, 0.12, cf * CFrame.new(0, 2.5, 0), COL.Metal, M.Metal)
	if withOre then
		cyl(parent, "BarrelInside", 1.5, 0.06, cf * CFrame.new(0, 2.8, 0), COL.WoodDeep, M.Slate)
		for i = 1, 3 do
			local a = i * 2.1
			ball(parent, "Nugget", 0.4, cf * CFrame.new(math.cos(a) * 0.35, 2.95, math.sin(a) * 0.35), COL.GemGold, M.Neon)
		end
	else
		cyl(parent, "BarrelLid", 1.62, 0.06, cf * CFrame.new(0, 2.8, 0), COL.WoodLight, M.Wood)
	end
end

-- Фонарь: cf — основание. Свет внутри — только если withLight
local function lantern(parent: Instance, cf: CFrame, s: number, withLight: boolean)
	local gh = 0.9 * s
	box(parent, "LanternBase", Vector3.new(0.7 * s, 0.1 * s, 0.7 * s), cf * CFrame.new(0, 0.05 * s, 0), COL.MetalDark, M.Metal)
	local core = box(parent, "LanternGlow", Vector3.new(0.5 * s, gh, 0.5 * s), cf * CFrame.new(0, 0.1 * s + gh / 2, 0), COL.LanternGlass, M.Neon)
	core.Transparency = 0.1
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			box(parent, "LanternPost", Vector3.new(0.08 * s, gh + 0.1 * s, 0.08 * s), cf * CFrame.new(sx * 0.28 * s, 0.1 * s + gh / 2, sz * 0.28 * s), COL.MetalDark, M.Metal)
		end
	end
	box(parent, "LanternTop", Vector3.new(0.72 * s, 0.1 * s, 0.72 * s), cf * CFrame.new(0, 0.15 * s + gh, 0), COL.MetalDark, M.Metal)
	box(parent, "LanternCap", Vector3.new(0.45 * s, 0.14 * s, 0.45 * s), cf * CFrame.new(0, 0.27 * s + gh, 0), COL.MetalDark, M.Metal)
	cyl(parent, "LanternRing", 0.32 * s, 0.05, cf * CFrame.new(0, 0.38 * s + gh, 0), COL.Brass, M.Metal)
	if withLight then
		PartKit.PointLight(core, COL.WarmLight, CFG.Lights.Lantern.Brightness, CFG.Lights.Lantern.Range)
	end
end

-- ============================================================================
-- Стойка: пол, прилавок, столбы, задняя стена, тент, гирлянда, вывеска
-- ============================================================================

-- Дощатый настил за прилавком
local function buildFloor(root: Instance)
	local f = folder(root, "Floor")
	local n = 5
	local zFrom, zTo = -7.0, -1.8
	local step = (zTo - zFrom) / n
	for i = 1, n do
		box(f, "FloorPlank", Vector3.new(14.6, 0.1, step - 0.03), at(0, 0.05, zFrom + (i - 0.5) * step), vary(tone(COL.WoodTones), 0.08), M.WoodPlanks)
	end
end

-- Прилавок: доски, рамки, столешница с бортиками
local function buildCounter(root: Instance)
	local f = folder(root, "Counter")
	local CT = CFG.Counter
	local W, D, H, T = CT.Width, CT.Depth, CT.Height, CT.TopThickness
	local pw = W / CT.PlankCount
	local ph = H - 0.55

	for i = 1, CT.PlankCount do
		local x = -W / 2 + (i - 0.5) * pw
		box(f, "FrontPlank", Vector3.new(pw - 0.03, ph, 0.22), at(x, 0.4 + ph / 2, D / 2 - 0.11 + rng:NextNumber(-0.02, 0.03)), vary(tone(COL.WoodTones), 0.06), M.Wood, true)
	end
	box(f, "BackPanel", Vector3.new(W - 0.2, H - 0.4, 0.2), at(0, 0.2 + (H - 0.4) / 2, -D / 2 + 0.1), COL.WoodDark, M.Wood, true)
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "SidePanel", Vector3.new(0.24, H - 0.4, D), at(sx * (W / 2 - 0.12), 0.2 + (H - 0.4) / 2, 0), COL.WoodMid, M.Wood, true)
	end
	-- Цоколь, рейки и угловые стойки
	box(f, "Kickboard", Vector3.new(W + 0.1, 0.4, 0.34), at(0, 0.2, D / 2 + 0.07), COL.WoodDeep, M.Wood, true)
	box(f, "MidRail", Vector3.new(W, 0.2, 0.1), at(0, 1.55, D / 2 + 0.05), COL.WoodDark, M.Wood)
	box(f, "TopRail", Vector3.new(W + 0.1, 0.3, 0.3), at(0, H - 0.15, D / 2 + 0.1), COL.WoodDark, M.Wood, true)
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "CornerTrim", Vector3.new(0.4, H, 0.4), at(sx * (W / 2 - 0.2), H / 2, D / 2 - 0.05), COL.WoodDeep, M.Wood)
	end
	-- Диагональные раскосы на передней панели (по две X-образные пары)
	for _, cx in ipairs({ -4.4, 4.4 }) do
		rod(f, "Brace", world(cx - 1.4, 0.7, D / 2 + 0.14), world(cx + 1.4, 2.5, D / 2 + 0.14), 0.16, COL.WoodDeep, M.Wood)
		rod(f, "Brace", world(cx - 1.4, 2.5, D / 2 + 0.14), world(cx + 1.4, 0.7, D / 2 + 0.14), 0.16, COL.WoodDeep, M.Wood)
	end

	-- Столешница из четырёх досок
	local topW = W + 0.6
	local topD = D + 0.6
	for j = 1, 4 do
		local z = -topD / 2 + (j - 0.5) * (topD / 4)
		box(f, "TopBoard", Vector3.new(topW, T, topD / 4 - 0.02), at(0, H + T / 2, z), vary(PartKit.Lighten(tone(COL.WoodTones), 0.05), 0.05), M.Wood, true)
	end
	box(f, "LipFront", Vector3.new(topW + 0.28, 0.34, 0.14), at(0, H + 0.11, topD / 2 + 0.07), COL.WoodDark, M.Wood)
	box(f, "LipBack", Vector3.new(topW + 0.28, 0.34, 0.14), at(0, H + 0.11, -topD / 2 - 0.07), COL.WoodDark, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "LipSide", Vector3.new(0.14, 0.34, topD), at(sx * (topW / 2 + 0.07), H + 0.11, 0), COL.WoodDark, M.Wood)
		for _, sz in ipairs({ -1, 1 }) do
			box(f, "CornerPlate", Vector3.new(0.34, 0.08, 0.34), at(sx * (topW / 2 - 0.1), H + T + 0.02, sz * (topD / 2 - 0.1)), COL.Brass, M.Metal)
		end
	end
end

-- Четыре столба с каменными основаниями, оковками, балками и раскосами
local function buildPillars(root: Instance)
	local f = folder(root, "Pillars")
	local P = CFG.Pillars
	local R = CFG.Roof
	local pts = {
		{ -P.X, P.FrontZ }, { P.X, P.FrontZ }, { -P.X, P.BackZ }, { P.X, P.BackZ },
	}
	for _, p in ipairs(pts) do
		local px, pz = p[1], p[2]
		local top = roofUnderY(pz) - 0.4
		box(f, "Pillar", Vector3.new(P.Size, top, P.Size), at(px, top / 2, pz), vary(COL.WoodDark, 0.05), M.Wood, true)
		box(f, "PillarPlinth", Vector3.new(1.35, 0.5, 1.35), at(px, 0.25, pz), COL.Stone, M.Cobblestone, true)
		box(f, "PillarCap", Vector3.new(1.2, 0.35, 1.2), at(px, top - 0.17, pz), COL.WoodDeep, M.Wood)
		box(f, "PillarBand", Vector3.new(1.0, 0.2, 1.0), at(px, 1.4, pz), COL.Metal, M.Metal)
		box(f, "PillarBand", Vector3.new(1.0, 0.2, 1.0), at(px, top - 1.2, pz), COL.Metal, M.Metal)
		-- Косынка под балкой (внутрь рынка)
		local dir = if px < 0 then 1 else -1
		rod(f, "KneeBrace", world(px + dir * 0.45, top - 1.6, pz), world(px + dir * 2.0, top - 0.4, pz), 0.28, COL.WoodMid, M.Wood)
	end

	-- Поперечные балки спереди и сзади
	local beamW = (P.X + 0.6) * 2
	for _, pz in ipairs({ P.FrontZ, P.BackZ }) do
		box(f, "Beam", Vector3.new(beamW, 0.4, 0.5), at(0, roofUnderY(pz) - 0.2, pz), COL.WoodDeep, M.Wood)
	end
	-- Боковые балки вдоль уклона тента
	local dz = P.FrontZ - P.BackZ
	local ang = math.atan2(R.BackY - R.FrontY, R.FrontZ - R.BackZ)
	local midZ = (P.FrontZ + P.BackZ) / 2
	local midY = (roofUnderY(P.FrontZ) + roofUnderY(P.BackZ)) / 2 - 0.2
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "SideBeam", Vector3.new(0.4, 0.4, dz / math.cos(ang)), at(sx * P.X, midY, midZ) * CFrame.Angles(ang, 0, 0), COL.WoodDeep, M.Wood)
	end

	-- Верёвочная обмотка на переднем правом столбе
	for i = 0, 4 do
		cyl(f, "RopeCoil", 1.05, 0.11, at(P.X, 4.4 + i * 0.17, P.FrontZ), COL.Rope, M.Fabric)
	end
	rod(f, "RopeEnd", world(P.X + 0.45, 4.5, P.FrontZ + 0.2), world(P.X + 0.7, 3.4, P.FrontZ + 0.5), 0.1, COL.Rope, M.Fabric)
end

-- Задняя стена из горизонтальных досок
local function buildBackWall(root: Instance)
	local f = folder(root, "BackWall")
	local rows, rh = 11, 0.95
	for i = 1, rows do
		box(f, "WallPlank", Vector3.new(14.6, rh - 0.03, 0.3), at(0, (i - 0.5) * rh, -7.1 + rng:NextNumber(-0.03, 0.03)), PartKit.Darken(vary(tone(COL.WoodTones), 0.08), 0.15), M.WoodPlanks, true)
	end
	for _, bx in ipairs({ -4.8, 0, 4.8 }) do
		box(f, "WallBatten", Vector3.new(0.34, rows * rh, 0.1), at(bx, rows * rh / 2, -6.92), COL.WoodDeep, M.Wood)
	end
end

-- Тент: полосатые полосы со скруглённым (фестонным) передним краем
local function buildRoof(root: Instance)
	local f = folder(root, "Awning")
	local R = CFG.Roof
	local dz = R.FrontZ - R.BackZ
	local dy = R.BackY - R.FrontY
	local ang = math.atan2(dy, dz)
	local len = math.sqrt(dz * dz + dy * dy)
	local th = R.Thickness
	local n = R.Stripes
	local w = R.HalfWidth * 2 / n
	local frame = at(0, (R.FrontY + R.BackY) / 2 + th / 2, (R.FrontZ + R.BackZ) / 2) * CFrame.Angles(ang, 0, 0)

	for i = 1, n do
		local x = -R.HalfWidth + (i - 0.5) * w
		local col = if i % 2 == 1 then COL.AwningA else COL.AwningB
		local strip = frame * CFrame.new(x, 0, 0)
		box(f, "AwningStripe", Vector3.new(w - 0.02, th, len), strip, col, M.Fabric)
		-- Полукруглый «зубец» свисает под передним краем полосы
		ell(f, "AwningScallop", Vector3.new(w - 0.04, 1.0, 0.26), strip * CFrame.new(0, -th / 2 - 0.35, len / 2 - 0.1), col, M.Fabric)
	end
	for _, rx in ipairs(R.RafterX) do
		box(f, "Rafter", Vector3.new(0.3, 0.3, len), frame * CFrame.new(rx, -th / 2 - 0.15, 0), COL.WoodDark, M.Wood)
	end
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "AwningSide", Vector3.new(0.28, 0.6, len), frame * CFrame.new(sx * (R.HalfWidth + 0.1), 0.05, 0), COL.WoodDeep, M.Wood)
	end
	box(f, "AwningBack", Vector3.new(R.HalfWidth * 2 + 0.5, 0.6, 0.3), frame * CFrame.new(0, 0.05, -len / 2), COL.WoodDeep, M.Wood)
end

-- Гирлянда: неоновые шарики на провисающей проволоке, света — всего три
local function buildGarland(root: Instance)
	local f = folder(root, "Garland")
	local G = CFG.Garland
	local step = G.HalfSpan * 2 / (G.Count - 1)
	local pts: { Vector3 } = {}
	for i = 0, G.Count - 1 do
		local x = -G.HalfSpan + i * step
		local phase = (i % G.SwagStep) / G.SwagStep
		local y = G.Y - G.Sag * math.sin(math.pi * phase)
		pts[#pts + 1] = world(x, y, G.Z)
	end
	for i = 1, #pts - 1 do
		rod(f, "GarlandWire", pts[i], pts[i + 1], 0.05, COL.MetalDark, M.Metal)
	end
	for i, p in ipairs(pts) do
		local bulb = ball(f, "Bulb", 0.4, CFrame.new(p), COL.Bulbs[(i % #COL.Bulbs) + 1], M.Neon)
		if (i - 1) % G.LightEvery == G.LightOffset then
			PartKit.PointLight(bulb, COL.WarmLight, CFG.Lights.Garland.Brightness, CFG.Lights.Garland.Range)
		end
	end
end

-- Вывеска «РЫНОК» на крыше тента (текст на SurfaceGui)
local function buildSign(root: Instance)
	local f = folder(root, "Sign")
	local z = 2.2
	local cy = 11.0
	local roofTop = roofUnderY(z) + CFG.Roof.Thickness
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "SignPost", Vector3.new(0.35, cy - roofTop + 0.4, 0.35), at(sx * 2.8, roofTop + (cy - roofTop + 0.4) / 2 - 0.2, z), COL.WoodDeep, M.Wood)
	end
	local board = box(f, "SignBoard", Vector3.new(6.7, 1.7, 0.3), at(0, cy, z), COL.SignBoard, M.WoodPlanks)
	PartKit.SurfaceLabel(board, Enum.NormalId.Back, CFG.SignText, {
		TextColor = COL.SignText,
		StrokeColor = COL.SignStroke,
		PixelsPerStud = 50,
		StrokeThickness = 4,
		Name = "SignLabel",
	})
	box(f, "SignFrameTop", Vector3.new(7.2, 0.25, 0.46), at(0, cy + 0.98, z), COL.WoodDark, M.Wood)
	box(f, "SignFrameBottom", Vector3.new(7.2, 0.25, 0.46), at(0, cy - 0.98, z), COL.WoodDark, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		box(f, "SignFrameSide", Vector3.new(0.25, 2.2, 0.46), at(sx * 3.47, cy, z), COL.WoodDark, M.Wood)
		for _, sy in ipairs({ -1, 1 }) do
			ball(f, "SignNail", 0.18, at(sx * 3.1, cy + sy * 0.6, z + 0.17), COL.Brass, M.Metal)
		end
	end
end

-- Подвесной фонарь на кронштейне (левый передний столб) + фонарик на прилавке
local function buildLanterns(root: Instance)
	local f = folder(root, "Lanterns")
	local P = CFG.Pillars
	local armY = roofUnderY(P.FrontZ) - 1.2
	local armX = -P.X
	local armZ = P.FrontZ + 0.45
	box(f, "LanternArm", Vector3.new(0.22, 0.22, 1.6), at(armX, armY, armZ + 0.9), COL.WoodDeep, M.Wood)
	rod(f, "LanternArmBrace", world(armX, armY - 1.0, armZ), world(armX, armY, armZ + 1.5), 0.14, COL.WoodDeep, M.Wood)
	local hangZ = armZ + 1.6
	rod(f, "LanternChain", world(armX, armY - 0.1, hangZ), world(armX, armY - 0.75, hangZ), 0.06, COL.MetalDark, M.Metal)
	lantern(f, at(armX, armY - 0.75 - 1.3, hangZ), 1.0, true)
	-- Фонарик на столешнице
	local topY = CFG.Counter.Height + CFG.Counter.TopThickness
	lantern(f, at(-6.4, topY, -0.6), 0.9, true)
end

-- ============================================================================
-- Ковёр
-- ============================================================================

local function buildCarpet(root: Instance): Part
	local f = folder(root, "Carpet")
	local CP = CFG.Carpet
	local w, d, zc, t = CP.Width, CP.Depth, CP.ZCenter, CP.Thickness
	local pad = PartKit.Block(f, "Carpet", Vector3.new(w, t, d), at(0, t / 2, zc), COL.CarpetBase, M.Fabric)
	local y = t + 0.015
	local function flat(name: string, size: Vector3, x: number, z: number, color: Color3, yaw: number?)
		box(f, name, Vector3.new(size.X, 0.03, size.Z), at(x, y, zc + z) * CFrame.Angles(0, yaw or 0, 0), color, M.Fabric)
	end
	-- Две каймы: золотая и синяя
	flat("BorderGold", Vector3.new(w - 0.6, 0, 0.28), 0, -(d / 2 - 0.3), COL.CarpetBorder)
	flat("BorderGold", Vector3.new(w - 0.6, 0, 0.28), 0, d / 2 - 0.3, COL.CarpetBorder)
	flat("BorderGold", Vector3.new(0.28, 0, d - 0.6), -(w / 2 - 0.3), 0, COL.CarpetBorder)
	flat("BorderGold", Vector3.new(0.28, 0, d - 0.6), w / 2 - 0.3, 0, COL.CarpetBorder)
	flat("BorderBlue", Vector3.new(w - 1.4, 0, 0.5), 0, -(d / 2 - 0.85), COL.CarpetInner)
	flat("BorderBlue", Vector3.new(w - 1.4, 0, 0.5), 0, d / 2 - 0.85, COL.CarpetInner)
	flat("BorderBlue", Vector3.new(0.5, 0, d - 1.8), -(w / 2 - 0.85), 0, COL.CarpetInner)
	flat("BorderBlue", Vector3.new(0.5, 0, d - 1.8), w / 2 - 0.85, 0, COL.CarpetInner)
	-- Два вложенных ромба в центре
	for _, r in ipairs({ 2.2, 1.4 }) do
		for _, qx in ipairs({ -1, 1 }) do
			for _, qz in ipairs({ -1, 1 }) do
				local yaw = if qx * qz > 0 then math.pi / 4 else -math.pi / 4
				flat("Diamond", Vector3.new(r * 1.4142, 0, 0.18), qx * r / 2, qz * r / 2, COL.CarpetPattern, yaw)
			end
		end
	end
	flat("Medallion", Vector3.new(0.7, 0, 0.7), 0, 0, COL.CarpetBorder, math.pi / 4)
	-- Бахрома по коротким краям
	for i = -3, 3 do
		flat("Fringe", Vector3.new(0.14, 0, 0.4), i * 1.4, -(d / 2 + 0.2), COL.CarpetFringe)
		flat("Fringe", Vector3.new(0.14, 0, 0.4), i * 1.4, d / 2 + 0.2, COL.CarpetFringe)
	end
	return pad
end

-- ============================================================================
-- Реквизит: ящики, бочки, мешки, камни, весы, образцы, полки
-- ============================================================================

local function buildProps(root: Instance)
	local f = folder(root, "Props")
	-- Слева: стопка ящиков и мешки с рудой
	crate(f, at(-9.6, 0, 0.3), 2.2)
	crate(f, at(-9.7, 2.2, 0.2) * CFrame.Angles(0, 0.26, 0), 1.5)
	crate(f, at(-11.9, 0, -1.2) * CFrame.Angles(0, -0.2, 0), 1.8)
	sack(f, at(-11.8, 0, 1.3) * CFrame.Angles(0, 0.5, 0), 1.1, COL.GemRuby)
	sack(f, at(-9.5, 0, -3.3) * CFrame.Angles(0, -0.4, 0), 1.0, COL.GemGold)
	-- Справа: бочки и небольшой ящик
	barrel(f, at(9.4, 0, 0.6), true)
	barrel(f, at(10.9, 0, -1.0), false)
	barrel(f, at(9.0, 0, -2.7), false)
	crate(f, at(11.7, 0, 1.2) * CFrame.Angles(0, 0.3, 0), 1.4)
	-- Камни с кристаллами по краям
	local function rocks(x: number, z: number, color: Color3)
		box(f, "GroundRock", Vector3.new(1.6, 0.9, 1.3), at(x, 0.4, z) * CFrame.Angles(0.1, 0.5, 0.08), COL.StoneDark, M.Slate)
		box(f, "GroundRock", Vector3.new(0.9, 0.6, 0.8), at(x + 1.0, 0.25, z + 0.5) * CFrame.Angles(0, -0.4, 0.1), COL.Stone, M.Rock)
		crystal(f, at(x - 0.2, 0.75, z) * CFrame.Angles(0.15, 0, 0.2), 0.8, color)
		crystal(f, at(x + 0.3, 0.7, z - 0.15) * CFrame.Angles(-0.2, 0, -0.3), 0.55, color)
	end
	rocks(-11.6, -3.6, COL.GemEmerald)
	rocks(11.0, -4.2, COL.GemDiamond)
end

-- Весы, образцы руды, монеты и книга учёта на столешнице
local function buildCounterProps(root: Instance)
	local f = folder(root, "CounterProps")
	local topY = CFG.Counter.Height + CFG.Counter.TopThickness
	-- Весы: основание, стойка, коромысло, чаши на цепочках
	local sx, sz = -4.2, 0.3
	box(f, "ScaleBase", Vector3.new(1.4, 0.18, 0.9), at(sx, topY + 0.09, sz), COL.WoodDeep, M.Wood)
	cyl(f, "ScalePost", 0.16, 1.7, at(sx, topY + 1.0, sz), COL.Brass, M.Metal)
	ball(f, "ScaleCap", 0.28, at(sx, topY + 1.9, sz), COL.Brass, M.Metal)
	box(f, "ScaleBeam", Vector3.new(3.2, 0.1, 0.12), at(sx, topY + 1.85, sz), COL.Brass, M.Metal)
	for _, side in ipairs({ -1, 1 }) do
		local ex = sx + side * 1.5
		cyl(f, "ScalePan", 0.95, 0.08, at(ex, topY + 0.85, sz), COL.Brass, M.Metal)
		rod(f, "ScaleChain", world(ex, topY + 1.82, sz), world(ex - 0.35, topY + 0.88, sz), 0.03, COL.Metal, M.Metal)
		rod(f, "ScaleChain", world(ex, topY + 1.82, sz), world(ex + 0.35, topY + 0.88, sz), 0.03, COL.Metal, M.Metal)
	end
	box(f, "ScaleWeight", Vector3.new(0.35, 0.35, 0.35), at(sx - 1.5, topY + 1.07, sz) * CFrame.Angles(0, 0.4, 0), COL.Gold, M.Metal)
	ball(f, "ScaleStone", 0.3, at(sx + 1.4, topY + 1.03, sz), COL.GemDiamond, M.Neon)
	ball(f, "ScaleStone", 0.26, at(sx + 1.62, topY + 1.01, sz), COL.GemRuby, M.Neon)

	-- Образцы руды: золото, рубин, изумруд, алмаз
	local gems = { COL.GemGold, COL.GemRuby, COL.GemEmerald, COL.GemDiamond }
	for i, c in ipairs(gems) do
		oreSample(f, at(2.8 + (i - 1) * 1.25, topY, 0.7), c)
	end

	-- Стопка монет и книга учёта
	for i = 0, 3 do
		cyl(f, "Coin", 0.6, 0.08, at(-1.2, topY + 0.04 + i * 0.08, 1.0) * CFrame.Angles(0, i * 0.5, 0), COL.Gold, M.Metal)
	end
	box(f, "Ledger", Vector3.new(1.0, 0.14, 0.75), at(0.2, topY + 0.07, 1.0) * CFrame.Angles(0, 0.14, 0), COL.CarpetBase, M.Fabric)
	box(f, "LedgerPages", Vector3.new(0.9, 0.08, 0.66), at(0.2, topY + 0.1, 1.0) * CFrame.Angles(0, 0.14, 0), COL.Paper, M.SmoothPlastic)
end

-- Три полки на задней стене и товары на них
local function buildShelves(root: Instance)
	local f = folder(root, "Shelves")
	local zS = -6.4
	local S1, S2, S3 = 3.6, 5.4, 7.2
	for _, sy in ipairs({ S1, S2, S3 }) do
		box(f, "ShelfBoard", Vector3.new(14.4, 0.2, 1.1), at(0, sy - 0.1, zS), vary(COL.WoodMid, 0.06), M.Wood, true)
		for _, sx in ipairs({ -6.8, 6.8 }) do
			rod(f, "ShelfBracket", world(sx, sy - 0.2, zS + 0.5), world(sx, sy - 1.0, zS - 0.5), 0.14, COL.WoodDeep, M.Wood)
		end
	end

	-- Нижняя полка: мешки и ящичек
	sack(f, at(-6.2, S1, zS), 0.7, nil)
	sack(f, at(-5.0, S1, zS + 0.1) * CFrame.Angles(0, 0.4, 0), 0.7, nil)
	crate(f, at(-3.6, S1, zS), 1.0)
	sack(f, at(5.8, S1, zS), 0.7, nil)
	sack(f, at(4.5, S1, zS + 0.1) * CFrame.Angles(0, -0.4, 0), 0.7, nil)

	-- Средняя полка: книги, красный ящик с инструментами, бутылки
	local bx = -6.8
	for i = 1, 6 do
		local bw = rng:NextNumber(0.22, 0.36)
		local bh = rng:NextNumber(0.8, 1.15)
		local lean = if i == 6 then CFrame.Angles(0, 0, math.rad(-14)) else CFrame.identity
		box(f, "Book", Vector3.new(bw, bh, 0.7), at(bx + bw / 2, S2 + bh / 2, zS) * lean, tone(COL.BookColors), M.SmoothPlastic)
		bx += bw + 0.02
	end
	box(f, "Toolbox", Vector3.new(1.3, 0.7, 0.6), at(-4.4, S2 + 0.35, zS), COL.ToolboxRed, M.SmoothPlastic)
	box(f, "ToolboxHandle", Vector3.new(0.8, 0.06, 0.06), at(-4.4, S2 + 0.8, zS), COL.MetalDark, M.Metal)
	box(f, "ToolboxPlate", Vector3.new(0.42, 0.42, 0.02), at(-4.4, S2 + 0.37, zS + 0.31), COL.Paper, M.SmoothPlastic)
	local glassColors = { COL.BottleGlass, COL.BottleBrown, COL.BottleGlass }
	for i, gc in ipairs(glassColors) do
		local x = 3.4 + (i - 1) * 0.6
		local b = cyl(f, "Bottle", 0.5, 0.7, at(x, S2 + 0.35, zS), gc, M.Glass)
		b.Transparency = 0.15
		cyl(f, "BottleNeck", 0.2, 0.3, at(x, S2 + 0.85, zS), gc, M.Glass)
	end

	-- Верхняя полка: факелы, цилиндр, зелья с неоновой жидкостью
	for i = 0, 2 do
		local tilt = (i - 1) * 0.14
		local base = at(-6.0 + i * 0.5, S3 + 0.55, zS) * CFrame.Angles(0, 0, tilt)
		cyl(f, "Torch", 0.12, 1.1, base, COL.WoodDeep, M.Wood)
		ball(f, "TorchFlame", 0.3, base * CFrame.new(0, 0.65, 0), COL.TorchFire, M.Neon)
	end
	cyl(f, "HatBrim", 1.4, 0.08, at(-3.3, S3 + 0.04, zS), COL.TopHat, M.Fabric)
	cyl(f, "HatCrown", 0.9, 0.8, at(-3.3, S3 + 0.48, zS), COL.TopHat, M.Fabric)
	cyl(f, "HatBand", 0.94, 0.14, at(-3.3, S3 + 0.2, zS), COL.HatBand, M.Fabric)
	local potions = { COL.PotionBlue, COL.PotionPurple, COL.PotionGreen }
	for i, pc in ipairs(potions) do
		local x = 3.8 + (i - 1) * 1.0
		ball(f, "Potion", 0.55, at(x, S3 + 0.28, zS), pc, M.Neon)
		cyl(f, "PotionNeck", 0.18, 0.3, at(x, S3 + 0.62, zS), COL.BottleGlass, M.Glass)
		ball(f, "PotionCork", 0.16, at(x, S3 + 0.82, zS), COL.Cork, M.Wood)
	end

	-- Запасная кирка на стене над полками
	local pk = at(4.0, 8.6, -6.78) * CFrame.Angles(0, 0, math.rad(8))
	cyl(f, "SparePickHandle", 0.2, 3.4, pk * CFrame.Angles(0, 0, math.pi / 2), COL.WoodLight, M.Wood)
	box(f, "SparePickHead", Vector3.new(0.3, 0.3, 0.3), pk * CFrame.new(-1.6, 0, 0), COL.Steel, M.Metal)
	box(f, "SparePickBlade", Vector3.new(0.26, 0.8, 0.26), pk * CFrame.new(-1.7, 0.55, 0) * CFrame.Angles(0, 0, math.rad(18)), COL.Steel, M.Metal)
	box(f, "SparePickBlade", Vector3.new(0.26, 0.8, 0.26), pk * CFrame.new(-1.7, -0.55, 0) * CFrame.Angles(0, 0, math.rad(-18)), COL.Steel, M.Metal)
	for _, px in ipairs({ 3.4, 5.4 }) do
		box(f, "WallPeg", Vector3.new(0.14, 0.14, 0.3), at(px, 8.6 + (px - 4.0) * 0.14 - 0.15, -6.82), COL.MetalDark, M.Metal)
	end
end

-- ============================================================================
-- Торговец Гоша
-- ============================================================================

local function npcOpts(transparency: number?): PartKit.Opts
	return { Anchored = false, Massless = true, CanCollide = false, CanQuery = false, Transparency = transparency }
end

local function makeMotor(name: string, owner: BasePart, p0: BasePart, p1: BasePart, pivot: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = p0.CFrame:ToObjectSpace(pivot)
	m.C1 = p1.CFrame:ToObjectSpace(pivot)
	m:SetAttribute("BaseC0", m.C0)
	m.Parent = owner
	return m
end

-- Табличка с именем и подсказкой над головой (тёмная плашка с золотой обводкой)
local function buildTag(head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "TraderTag"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(250, 66)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = CFG.TagMaxDistance
	gui.LightInfluence = 0
	gui.Parent = head

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = COL.TagBg
	plate.BackgroundTransparency = 0.15
	plate.BorderSizePixel = 0
	plate.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = plate

	local stroke = Instance.new("UIStroke")
	stroke.Color = COL.TagStroke
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = plate

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0, 0.04)
	name.Size = UDim2.fromScale(1, 0.56)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.Text = CFG.TraderName
	name.TextColor3 = COL.TagName
	name.TextStrokeTransparency = 0.5
	name.Parent = plate

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromScale(0, 0.6)
	hint.Size = UDim2.fromScale(1, 0.34)
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.Text = CFG.HintText
	hint.TextColor3 = COL.TagHint
	hint.Parent = plate
end

-- Сборка торговца: Root (закреплён) + Motor6D-суставы + приваренные аксессуары
local function buildTrader(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = CFG.NpcModelName

	local frame = CFrame.new(ox + CFG.Trader.X, 0, oz + CFG.Trader.Z) * CFrame.Angles(0, math.pi, 0)
	local function L(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	-- Помощники привязки к конечности
	local function nBlock(limb: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, tr: number?): Part
		local p = PartKit.Block(model, name, size, cf, color, mat, npcOpts(tr))
		PartKit.WeldTo(p, limb)
		return p
	end
	local function nBall(limb: BasePart, name: string, d: number, cf: CFrame, color: Color3, mat: Enum.Material): Part
		local p = PartKit.Ball(model, name, d, cf, color, mat, npcOpts(nil))
		PartKit.WeldTo(p, limb)
		return p
	end
	local function nCyl(limb: BasePart, name: string, d: number, h: number, cf: CFrame, color: Color3, mat: Enum.Material, tr: number?): Part
		local p = PartKit.Cylinder(model, name, d, h, cf, color, mat, npcOpts(tr))
		PartKit.WeldTo(p, limb)
		return p
	end
	local function nEll(limb: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
		local p = PartKit.Ellipsoid(model, name, size, cf, color, mat, npcOpts(nil))
		PartKit.WeldTo(p, limb)
		return p
	end

	-- Корень (бёдра) и основные части тела
	local rootPart = PartKit.Block(model, "Root", Vector3.new(1, 1, 1), L(0, 2.2, 0), COL.Trousers, M.SmoothPlastic, { Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1 })
	local torsoCF = L(0, 3.55, 0)
	local torso = PartKit.Block(model, "Torso", Vector3.new(3.0, 2.7, 1.9), torsoCF, COL.Shirt, M.SmoothPlastic, npcOpts(nil))
	local headCF = L(0, 5.9, 0)
	local head = PartKit.Ball(model, "Head", 2.1, headCF, COL.Skin, M.SmoothPlastic, npcOpts(nil))

	-- Руки: в покое наклонены вперёд на 70°, кисти лежат на столешнице
	local restTilt = CFrame.Angles(math.rad(70), 0, 0)
	local pivotL = L(-1.95, 4.5, 0) * restTilt
	local pivotR = L(1.95, 4.5, 0) * restTilt
	local armL = PartKit.Block(model, "ArmL", Vector3.new(0.85, 2.6, 0.85), pivotL * CFrame.new(0, -1.3, 0), COL.Shirt, M.SmoothPlastic, npcOpts(nil))
	local armR = PartKit.Block(model, "ArmR", Vector3.new(0.85, 2.6, 0.85), pivotR * CFrame.new(0, -1.3, 0), COL.Shirt, M.SmoothPlastic, npcOpts(nil))

	-- Ноги приварены к Root
	local legs: { BasePart } = {}
	for _, sx in ipairs({ -1, 1 }) do
		local leg = nBlock(rootPart, "Leg", Vector3.new(1.3, 2.1, 1.3), L(sx * 0.8, 1.15, 0), COL.Trousers, M.SmoothPlastic)
		leg.Name = if sx < 0 then "LegL" else "LegR"
		legs[#legs + 1] = leg
		nBlock(rootPart, "Boot", Vector3.new(1.4, 0.6, 1.8), L(sx * 0.8, 0.3, -0.25), COL.Boots, M.Leather)
	end

	-- Суставы: pivot строится из итоговых позиций, поэтому ничего не «прыгает»
	makeMotor("Waist", rootPart, rootPart, torso, L(0, 2.2, 0))
	makeMotor("Neck", torso, torso, head, L(0, 4.9, 0))
	makeMotor("ShoulderL", torso, torso, armL, pivotL)
	makeMotor("ShoulderR", torso, torso, armR, pivotR)

	-- Туловище: фартук, ремень, лямки, карман, бабочка, воротник
	nBlock(torso, "Apron", Vector3.new(2.4, 2.1, 0.12), torsoCF * CFrame.new(0, -0.3, -1.0), COL.Apron, M.Leather)
	nBlock(torso, "ApronPocket", Vector3.new(1.1, 0.7, 0.08), torsoCF * CFrame.new(0, -0.6, -1.08), COL.ApronDark, M.Leather)
	nBlock(torso, "Belt", Vector3.new(3.06, 0.25, 1.96), torsoCF * CFrame.new(0, -1.0, 0), COL.ApronDark, M.Leather)
	nBlock(torso, "Buckle", Vector3.new(0.5, 0.4, 0.1), torsoCF * CFrame.new(0, -1.0, -1.0), COL.Gold, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		nBlock(torso, "ApronStrap", Vector3.new(0.25, 0.7, 0.1), torsoCF * CFrame.new(sx * 0.85, 1.05, -0.99), COL.ApronDark, M.Leather)
		nBall(torso, "Rivet", 0.14, torsoCF * CFrame.new(sx * 1.0, 0.65, -1.07), COL.Brass, M.Metal)
		nBlock(torso, "Collar", Vector3.new(0.6, 0.35, 0.1), torsoCF * CFrame.new(sx * 0.45, 1.3, -0.97) * CFrame.Angles(0, 0, sx * math.rad(-35)), COL.Cuff, M.SmoothPlastic)
		nEll(torso, "BowWing", Vector3.new(0.6, 0.42, 0.2), torsoCF * CFrame.new(sx * 0.38, 1.12, -1.02), COL.BowTie, M.Fabric)
	end
	nBall(torso, "BowKnot", 0.3, torsoCF * CFrame.new(0, 1.12, -1.04), COL.BowTie, M.Fabric)

	-- Руки: манжеты и кисти
	local function dressArm(arm: BasePart, pivot: CFrame)
		nBlock(arm, "Cuff", Vector3.new(1.0, 0.35, 1.0), pivot * CFrame.new(0, -1.1, 0), COL.Cuff, M.SmoothPlastic)
		nBall(arm, "Hand", 0.75, pivot * CFrame.new(0, -1.5, 0), COL.Skin, M.SmoothPlastic)
	end
	dressArm(armL, pivotL)
	dressArm(armR, pivotR)

	-- Голова: уши, нос, румянец, глаза, брови
	local HR = 1.05
	for _, sx in ipairs({ -1, 1 }) do
		nBall(head, "Ear", 0.4, headCF * CFrame.new(sx * 1.02, 0, -0.05), COL.Skin, M.SmoothPlastic)
		nBall(head, "Sideburn", 0.5, headCF * CFrame.new(sx * 0.93, 0.45, 0.25), COL.Hair, M.Fabric)
		nEll(head, "Cheek", Vector3.new(0.4, 0.25, 0.15), headCF * CFrame.new(sx * 0.72, -0.2, -0.72) * CFrame.Angles(0, sx * math.rad(35), 0), COL.Cheek, M.SmoothPlastic).Transparency = 0.35
		nBall(head, "EyeWhite", 0.42, headCF * CFrame.new(sx * 0.42, 0.15, -0.86), COL.EyeWhite, M.SmoothPlastic)
		nBall(head, "Pupil", 0.22, headCF * CFrame.new(sx * 0.42, 0.13, -0.98), COL.Pupil, M.SmoothPlastic)
		nBlock(head, "Brow", Vector3.new(0.6, 0.14, 0.14), headCF * CFrame.new(sx * 0.45, 0.62, -0.88) * CFrame.Angles(0, 0, sx * math.rad(-12)), COL.Moustache, M.Fabric)
	end
	nBall(head, "Nose", 0.5, headCF * CFrame.new(0, -0.08, -1.05), COL.SkinShade, M.SmoothPlastic)

	-- Круглые очки: оправа (кольцо) + стёкла, переносица и дужки
	for _, sx in ipairs({ -1, 1 }) do
		local lensCF = headCF * CFrame.new(sx * 0.47, 0.15, -1.14) * CFrame.Angles(math.pi / 2, 0, 0)
		nCyl(head, "GlassesRing", 0.88, 0.12, lensCF, COL.GlassesFrame, M.Metal)
		nCyl(head, "Lens", 0.7, 0.1, lensCF * CFrame.new(0, -0.02, 0), COL.Lens, M.Glass, 0.55)
		nBlock(head, "GlassesTemple", Vector3.new(0.08, 0.08, 1.0), headCF * CFrame.new(sx * 0.97, 0.2, -0.62), COL.GlassesFrame, M.Metal)
	end
	nBlock(head, "GlassesBridge", Vector3.new(0.16, 0.08, 0.08), headCF * CFrame.new(0, 0.2, -1.14), COL.GlassesFrame, M.Metal)

	-- Большие закрученные усы
	for _, sx in ipairs({ -1, 1 }) do
		nEll(head, "Moustache", Vector3.new(0.9, 0.42, 0.45), headCF * CFrame.new(sx * 0.48, -0.36, -1.0) * CFrame.Angles(0, 0, sx * math.rad(18)), COL.Moustache, M.Fabric)
		nBall(head, "MoustacheTip", 0.3, headCF * CFrame.new(sx * 0.88, -0.2, -0.72), COL.Moustache, M.Fabric)
	end

	-- Улыбка: дуга из маленьких шариков по поверхности головы
	for i = -3, 3 do
		local sx = i * 0.14
		local sy = -0.8 + 0.15 * (sx / 0.42) ^ 2
		local sz = -math.sqrt(math.max(0.05, HR * HR - sx * sx - sy * sy)) - 0.03
		nBall(head, "Smile", 0.11, headCF * CFrame.new(sx, sy, sz), COL.Mouth, M.SmoothPlastic)
	end

	-- Шляпа с широкими полями и красной лентой (чуть набекрень)
	local hatCF = headCF * CFrame.Angles(0, 0, math.rad(-4))
	nCyl(head, "HatBrim", 3.1, 0.12, hatCF * CFrame.new(0, 0.8, -0.1), COL.Hat, M.Fabric)
	nCyl(head, "HatCrown", 1.85, 1.0, hatCF * CFrame.new(0, 1.3, 0), COL.Hat, M.Fabric)
	nCyl(head, "HatBand", 1.9, 0.24, hatCF * CFrame.new(0, 0.98, 0), COL.HatBand, M.Fabric)
	nCyl(head, "HatTop", 1.6, 0.06, hatCF * CFrame.new(0, 1.83, 0), COL.HatTop, M.Fabric)

	buildTag(head)

	-- Невидимый блок, чтобы игроки не проходили сквозь торговца
	local blocker = PartKit.Block(model, "TraderCollider", Vector3.new(3.6, 7.5, 2.4), L(0, 3.75, 0), COL.Hat, M.SmoothPlastic, { Anchored = true, CanCollide = true, CanQuery = true, Transparency = 1 })
	blocker.CanTouch = false

	model.PrimaryPart = rootPart
	CollectionService:AddTag(model, CFG.NpcTag)
	model.Parent = parent
	return model
end

-- ============================================================================
-- ProximityPrompt на невидимой опоре у прилавка
-- ============================================================================

local function buildPrompt(root: Instance): ProximityPrompt
	local anchor = PartKit.Block(root, "ShopPromptAnchor", Vector3.new(4, 1.6, 0.6), at(0, CFG.PromptHeight, CFG.PromptZ), COL.WoodDark, M.SmoothPlastic, { Transparency = 1, CanCollide = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = CFG.ActionText
	prompt.ObjectText = CFG.TraderName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = CFG.MaxActivationDistance
	prompt.Parent = anchor
	CollectionService:AddTag(prompt, CFG.PromptTag)
	return prompt
end

-- ============================================================================
-- Публичный API
-- ============================================================================

function MarketBuilder.Build(parent: Instance, centerPos: Vector3): MarketRefs
	ox = centerPos.X
	oz = centerPos.Z
	rng = Random.new(CFG.Seed)

	local old = parent:FindFirstChild(CFG.ModelName)
	if old then
		old:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = CFG.ModelName

	buildFloor(model)
	buildBackWall(model)
	buildCounter(model)
	buildPillars(model)
	buildRoof(model)
	buildGarland(model)
	buildSign(model)
	buildLanterns(model)
	buildShelves(model)
	buildCounterProps(model)
	buildProps(model)
	local pad = buildCarpet(model)
	local trader = buildTrader(model)
	local prompt = buildPrompt(model)

	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	model:SetAttribute("PartCount", count)

	model.Parent = parent
	return { Model = model, Prompt = prompt, Trader = trader, Pad = pad }
end

return MarketBuilder
