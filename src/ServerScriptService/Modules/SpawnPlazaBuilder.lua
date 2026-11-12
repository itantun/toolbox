--!strict
-- ============================================================================
-- 🪨 МОДУЛЬ: SpawnPlazaBuilder (ServerScriptService.Modules.SpawnPlazaBuilder)
-- Процедурная каменная площадь спавна: тёмная подложка, плиты «вразбежку» с
-- разной высотой/наклоном/оттенком, трещины, мох, камешки, бордюр-скос,
-- врезанный постамент с неоновой руной, фонари, валуны и кристаллы.
-- Только Part/WedgePart/Neon и встроенные материалы — без изображений.
-- Вся раскладка берётся из Random.new(Seed): площадь всегда одинакова.
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local PartKit = require(Modules:WaitForChild("PartKit"))

local SpawnPlazaBuilder = {}

export type PlazaRefs = { Model: Model, SpawnLocation: SpawnLocation }

type Style = { Material: Enum.Material, Weight: number, Colors: { Color3 } }

-- Запись о плите: нужна, чтобы класть детали точно в её локальной системе координат
type Slab = {
	Cf: CFrame, -- центр плиты с учётом рысканья и наклона
	W: number,
	D: number,
	Thick: number,
	Gap: number,
	TopY: number,
	Used: { [number]: boolean }, -- занятые углы (фаска / мох)
}

type SlabSpec = {
	Name: string,
	CX: number,
	CZ: number,
	W: number,
	D: number,
	Gap: number,
	TopMin: number,
	TopMax: number,
	Thick: number,
	Styles: { Style },
}

type Circle = { X: number, Z: number, R: number }

-- Углы плиты в локальных координатах (знаки X/Z)
local CORNERS: { { number } } = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }

local C = GameConfig.SPAWN_PLAZA

-- ============================== ПОМОЩНИКИ ===================================

local function range(rng: Random, lo: number, hi: number): number
	return lo + (hi - lo) * rng:NextNumber()
end

local function pickStyle(rng: Random, styles: { Style }): Style
	local total = 0
	for _, s in ipairs(styles) do
		total += s.Weight
	end
	local roll = rng:NextNumber() * total
	for _, s in ipairs(styles) do
		roll -= s.Weight
		if roll <= 0 then
			return s
		end
	end
	return styles[#styles]
end

local function pickColor(rng: Random, colors: { Color3 }): Color3
	return colors[rng:NextInteger(1, #colors)]
end

-- Лёгкий разброс яркости, чтобы соседние плиты не были одного оттенка
local function tint(c: Color3, rng: Random, amount: number): Color3
	local k = 1 + (rng:NextNumber() * 2 - 1) * amount
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

-- Делит отрезок [a; b] на неравные части (границы возвращаются списком)
local function splitSpan(a: number, b: number, target: number, jitter: number, rng: Random): { number }
	local n = math.max(1, math.floor((b - a) / target + 0.5))
	local weights: { number } = {}
	local total = 0
	for i = 1, n do
		local w = 1 + (rng:NextNumber() * 2 - 1) * jitter
		weights[i] = w
		total += w
	end
	local bounds: { number } = { a }
	local acc = 0
	for i = 1, n - 1 do
		acc += weights[i]
		bounds[i + 1] = a + (b - a) * acc / total
	end
	bounds[n + 1] = b
	return bounds
end

local function newFolder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Малый наклон с ограничением перепада высот по плите
local function slabTilt(rng: Random, w: number, d: number, maxRise: number): (number, number, number)
	local S = C.Slab
	local tx = math.rad(range(rng, -S.MaxTiltDeg, S.MaxTiltDeg))
	local tz = math.rad(range(rng, -S.MaxTiltDeg, S.MaxTiltDeg))
	local rise = d / 2 * math.abs(math.sin(tx)) + w / 2 * math.abs(math.sin(tz))
	if rise > maxRise then
		local k = maxRise / rise
		tx *= k
		tz *= k
		rise = maxRise
	end
	return tx, tz, rise
end

-- Создаёт одну плиту (колизия включена) и возвращает запись о ней
local function makeSlab(parent: Instance, spec: SlabSpec, rng: Random): Slab
	local style = pickStyle(rng, spec.Styles)
	local color = tint(pickColor(rng, style.Colors), rng, C.Slab.ColorJitter)
	local yaw = math.rad(range(rng, -C.Slab.MaxYawDeg, C.Slab.MaxYawDeg))
	local tx, tz, rise = slabTilt(rng, spec.W, spec.D, math.min(C.Slab.MaxRise, (spec.TopMax - spec.TopMin) * 0.45))
	local lo, hi = spec.TopMin + rise, spec.TopMax - rise
	local top = if hi > lo then range(rng, lo, hi) else (spec.TopMin + spec.TopMax) / 2
	local cf = CFrame.new(spec.CX, top - spec.Thick / 2, spec.CZ) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tx, 0, tz)
	PartKit.Block(parent, spec.Name, Vector3.new(spec.W, spec.Thick, spec.D), cf, color, style.Material, { CanCollide = true })
	return { Cf = cf, W = spec.W, D = spec.D, Thick = spec.Thick, Gap = spec.Gap, TopY = top, Used = {} }
end

-- Срезанный угол: плоский тёмный треугольник на верхней грани плиты.
-- Клин лежит «на боку»: локальная X — вверх, прямой угол — в углу плиты.
local function addChamfer(parent: Instance, slab: Slab, corner: number, c1: number, c2: number)
	local sx, sz = CORNERS[corner][1], CORNERS[corner][2]
	local ix = Vector3.new(-sx, 0, 0)
	local iz = Vector3.new(0, 0, -sz)
	local b, a, h, d
	if sx == sz then
		b, a, h, d = ix, iz, c1, c2
	else
		b, a, h, d = iz, ix, c2, c1
	end
	local vertex = Vector3.new(sx * slab.W / 2, slab.Thick / 2 + C.Details.Lift, sz * slab.D / 2)
	local center = vertex + b * (h / 2) + a * (d / 2)
	local localCf = CFrame.fromMatrix(center, Vector3.new(0, 1, 0), b, -a)
	PartKit.Wedge(parent, "Скос", Vector3.new(0.02, h, d), slab.Cf * localCf, C.CrevicePlateColor, Enum.Material.Slate)
	slab.Used[corner] = true
end

-- ============================ ПОДЛОЖКА И БОРДЮР =============================

local function buildPlate(parent: Instance)
	local B, P, W = C.Bounds, C.Plate, C.Border.Width
	local sizeX = (B.MaxX - B.MinX) - 2 * W
	local sizeZ = (B.MaxZ - B.MinZ) - 2 * W
	local cx = (B.MinX + B.MaxX) / 2
	local cz = (B.MinZ + B.MaxZ) / 2
	PartKit.Block(
		parent,
		"ТёмнаяПодложка",
		Vector3.new(sizeX, P.Thickness, sizeZ),
		CFrame.new(cx, P.TopY - P.Thickness / 2, cz),
		P.Color,
		P.Material,
		{ CanCollide = true }
	)
end

-- Один сегмент бордюра: клин-скос (высокая грань — внутрь площади) или плоская вставка у тропы.
-- Клин поднимается к локальной +Z, поэтому поворот задаёт «внутреннюю» сторону.
local function borderPiece(
	parent: Instance,
	rng: Random,
	along0: number,
	along1: number,
	fixed: number,
	side: number,
	flat: boolean
)
	local Bd = C.Border
	local len = along1 - along0
	local mid = (along0 + along1) / 2
	local color = tint(pickColor(rng, Bd.Colors), rng, 0.05)
	local isNS = side <= 2 -- 1 = север, 2 = юг, 3 = запад, 4 = восток
	local pos2d = if isNS then Vector3.new(mid, 0, fixed) else Vector3.new(fixed, 0, mid)
	if flat then
		local h = Bd.PathStripTop
		local size = if isNS then Vector3.new(len, h, Bd.Width) else Vector3.new(Bd.Width, h, len)
		PartKit.Block(parent, "БордюрТропы", size, CFrame.new(pos2d.X, h / 2, pos2d.Z), color, Bd.Material, { CanCollide = true })
		return
	end
	local h = range(rng, Bd.HeightMin, Bd.HeightMax)
	local yaw = 0
	if side == 2 then
		yaw = math.pi
	elseif side == 3 then
		yaw = math.pi / 2
	elseif side == 4 then
		yaw = -math.pi / 2
	end
	PartKit.Wedge(
		parent,
		"БордюрСкос",
		Vector3.new(len, h, Bd.Width),
		CFrame.new(pos2d.X, h / 2, pos2d.Z) * CFrame.Angles(0, yaw, 0),
		color,
		Bd.Material,
		{ CanCollide = true }
	)
end

local function buildBorder(parent: Instance, rng: Random)
	local B, Bd = C.Bounds, C.Border
	local halfN = C.Passages.NorthHalfWidth
	local w = Bd.Width
	local northZ = B.MinZ + w / 2
	local southZ = B.MaxZ - w / 2
	local westX = B.MinX + w / 2
	local eastX = B.MaxX - w / 2

	-- Север: скосы по краям и плоская вставка напротив тропы
	local sections: { { number } } = { { B.MinX, -halfN, 0 }, { -halfN, halfN, 1 }, { halfN, B.MaxX, 0 } }
	for _, s in ipairs(sections) do
		local bounds = splitSpan(s[1], s[2], Bd.SegmentTarget, Bd.SegmentJitter, rng)
		for i = 1, #bounds - 1 do
			borderPiece(parent, rng, bounds[i], bounds[i + 1], northZ, 1, s[3] == 1)
		end
	end
	-- Юг, запад, восток — только скосы
	local south = splitSpan(B.MinX, B.MaxX, Bd.SegmentTarget, Bd.SegmentJitter, rng)
	for i = 1, #south - 1 do
		borderPiece(parent, rng, south[i], south[i + 1], southZ, 2, false)
	end
	local sideSpan = splitSpan(B.MinZ + w, B.MaxZ - w, Bd.SegmentTarget, Bd.SegmentJitter, rng)
	for i = 1, #sideSpan - 1 do
		borderPiece(parent, rng, sideSpan[i], sideSpan[i + 1], westX, 3, false)
	end
	local sideSpanE = splitSpan(B.MinZ + w, B.MaxZ - w, Bd.SegmentTarget, Bd.SegmentJitter, rng)
	for i = 1, #sideSpanE - 1 do
		borderPiece(parent, rng, sideSpanE[i], sideSpanE[i + 1], eastX, 4, false)
	end
end

-- ================================== ПЛИТЫ ===================================

local function buildGridSlabs(parent: Instance, rng: Random): { Slab }
	local B, S, D = C.Bounds, C.Slab, C.Dais
	local w = C.Border.Width
	local x0, x1 = B.MinX + w, B.MaxX - w
	local z0, z1 = B.MinZ + w, B.MaxZ - w
	local cx, cz = C.Center.X, C.Center.Z
	local h = D.Size / 2 + D.RingWidth -- половина квадратного выреза под постамент и кольцо

	-- Четыре области вокруг выреза: { minX, maxX, minZ, maxZ }
	local regions: { { number } } = {
		{ x0, cx - h, z0, z1 },
		{ cx + h, x1, z0, z1 },
		{ cx - h, cx + h, z0, cz - h },
		{ cx - h, cx + h, cz + h, z1 },
	}
	local slabs: { Slab } = {}
	local index = 0
	for _, r in ipairs(regions) do
		if r[2] - r[1] > 0.5 and r[4] - r[3] > 0.5 then
			local rows = splitSpan(r[3], r[4], S.RowTarget, S.RowJitter, rng)
			for ri = 1, #rows - 1 do
				-- каждая строка режется на колонки по-своему: кладка «вразбежку»
				local cols = splitSpan(r[1], r[2], S.ColTarget, S.ColJitter, rng)
				for ci = 1, #cols - 1 do
					local gap = range(rng, S.GapMin, S.GapMax)
					local sw = (cols[ci + 1] - cols[ci]) - gap
					local sd = (rows[ri + 1] - rows[ri]) - gap
					if sw >= S.MinSize and sd >= S.MinSize then
						index += 1
						local slab = makeSlab(parent, {
							Name = "Плита" .. index,
							CX = (cols[ci] + cols[ci + 1]) / 2,
							CZ = (rows[ri] + rows[ri + 1]) / 2,
							W = sw,
							D = sd,
							Gap = gap,
							TopMin = S.TopMin,
							TopMax = S.TopMax,
							Thick = S.Thickness,
							Styles = S.Styles,
						}, rng)
						table.insert(slabs, slab)
					end
				end
			end
		end
	end
	return slabs
end

-- Кольцо подогнанных камней вокруг постамента (внутри выреза сетки плит)
local function buildRing(parent: Instance, rng: Random): { Slab }
	local D = C.Dais
	local cx, cz = C.Center.X, C.Center.Z
	local dh = D.Size / 2
	local h = dh + D.RingWidth
	local slabs: { Slab } = {}
	local index = 0

	-- sideKind: 1 — север, 2 — юг (полная длина, включают углы); 3 — запад, 4 — восток
	local function ringSide(minX: number, maxX: number, minZ: number, maxZ: number, alongX: boolean, sideKind: number)
		local a0, a1 = if alongX then minX else minZ, if alongX then maxX else maxZ
		local bounds = splitSpan(a0, a1, D.RingTarget, 0.25, rng)
		for i = 1, #bounds - 1 do
			local gap = range(rng, C.Slab.GapMin, C.Slab.GapMax)
			local along = (bounds[i] + bounds[i + 1]) / 2
			local length = (bounds[i + 1] - bounds[i]) - gap
			local depth = D.RingWidth - gap
			local px = if alongX then along else (minX + maxX) / 2
			local pz = if alongX then (minZ + maxZ) / 2 else along
			index += 1
			local slab = makeSlab(parent, {
				Name = "КамньКольца" .. index,
				CX = px,
				CZ = pz,
				W = if alongX then length else depth,
				D = if alongX then depth else length,
				Gap = gap,
				TopMin = D.RingTopMin,
				TopMax = D.RingTopMax,
				Thick = C.Slab.Thickness,
				Styles = D.RingStyles,
			}, rng)
			table.insert(slabs, slab)
			-- крайние камни северной/южной сторон получают срез внешнего угла
			if sideKind <= 2 then
				local cut = range(rng, C.Details.ChamferSizeMin, C.Details.ChamferSizeMax)
				if i == 1 then
					addChamfer(parent, slab, if sideKind == 1 then 1 else 4, cut, cut)
				elseif i == #bounds - 1 then
					addChamfer(parent, slab, if sideKind == 1 then 2 else 3, cut, cut)
				end
			end
		end
	end

	ringSide(cx - h, cx + h, cz - h, cz - dh, true, 1)
	ringSide(cx - h, cx + h, cz + dh, cz + h, true, 2)
	ringSide(cx - h, cx - dh, cz - dh, cz + dh, false, 3)
	ringSide(cx + dh, cx + h, cz - dh, cz + dh, false, 4)
	return slabs
end

-- ============================ ДЕТАЛИ НА ПЛИТАХ ==============================

local function addCrack(parent: Instance, slab: Slab, rng: Random)
	local Dt = C.Details
	local theta = range(rng, 0, math.pi)
	local c, s = math.abs(math.cos(theta)), math.abs(math.sin(theta))
	local cxl = range(rng, -slab.W * 0.18, slab.W * 0.18)
	local czl = range(rng, -slab.D * 0.18, slab.D * 0.18)
	local roomX = slab.W / 2 - 0.12 - math.abs(cxl)
	local roomZ = slab.D / 2 - 0.12 - math.abs(czl)
	local maxLen = 2 * math.min(roomX / math.max(c, 0.05), roomZ / math.max(s, 0.05))
	local len = math.min(range(rng, 0.7, 1.9), maxLen)
	if len < 0.35 then
		return
	end
	local y = slab.Thick / 2 + Dt.Lift
	local main = slab.Cf * CFrame.new(cxl, y, czl) * CFrame.Angles(0, theta, 0)
	PartKit.Block(parent, "Трещина", Vector3.new(len, Dt.CrackThickness, Dt.CrackWidth), main, Dt.CrackColor, Enum.Material.Slate)
end

local function addMossCrevice(parent: Instance, slab: Slab, rng: Random)
	local side = rng:NextInteger(1, 4)
	local alongX = side <= 2 -- края ±X тянутся вдоль Z
	local edgeLen = if alongX then slab.D else slab.W
	local len = math.min(range(rng, 0.7, 1.6), edgeLen * 0.8)
	local room = math.max(0, edgeLen / 2 - len / 2 - 0.1)
	local along = range(rng, -room, room)
	local sign = if side % 2 == 1 then 1 else -1
	local offset = sign * ((if alongX then slab.W else slab.D) / 2 + slab.Gap / 2)
	local ly = 0.19 - slab.Cf.Position.Y
	local lpos = if alongX then Vector3.new(offset, ly, along) else Vector3.new(along, ly, offset)
	local size = if alongX then Vector3.new(0.12, 0.06, len) else Vector3.new(len, 0.06, 0.12)
	PartKit.Block(parent, "МохВЩели", size, slab.Cf * CFrame.new(lpos), pickColor(rng, C.Details.MossColors), Enum.Material.Grass)
end

local function addMossCorner(parent: Instance, slab: Slab, rng: Random): boolean
	local corner = rng:NextInteger(1, 4)
	if slab.Used[corner] then
		return false
	end
	local sizeX, sizeZ = range(rng, 0.45, 0.85), range(rng, 0.35, 0.65)
	local r = math.sqrt(sizeX * sizeX + sizeZ * sizeZ) / 2
	local ox, oz = slab.W / 2 - r - 0.03, slab.D / 2 - r - 0.03
	if ox <= 0 or oz <= 0 then
		return false
	end
	local sx, sz = CORNERS[corner][1], CORNERS[corner][2]
	local cf = slab.Cf * CFrame.new(sx * ox, slab.Thick / 2 + C.Details.Lift, sz * oz) * CFrame.Angles(0, range(rng, 0, math.pi), 0)
	PartKit.Block(parent, "МохУгол", Vector3.new(sizeX, 0.03, sizeZ), cf, pickColor(rng, C.Details.MossColors), Enum.Material.Grass)
	slab.Used[corner] = true
	return true
end

local function addPebble(parent: Instance, slab: Slab, rng: Random)
	local Dt = C.Details
	local s = range(rng, Dt.PebbleMin, Dt.PebbleMax)
	local lx = range(rng, -(slab.W / 2 - 0.3), slab.W / 2 - 0.3)
	local lz = range(rng, -(slab.D / 2 - 0.3), slab.D / 2 - 0.3)
	local color = tint(pickColor(rng, Dt.PebbleColors), rng, 0.08)
	local rot = CFrame.Angles(range(rng, -0.4, 0.4), range(rng, 0, math.pi * 2), range(rng, -0.4, 0.4))
	local cf = slab.Cf * CFrame.new(lx, slab.Thick / 2 + s * 0.3, lz) * rot
	if rng:NextNumber() < 0.4 then
		PartKit.Ball(parent, "Камешек", s, cf, color, Enum.Material.Slate)
	else
		PartKit.Block(parent, "Камешек", Vector3.new(s, s * 0.6, s * range(rng, 0.7, 1.1)), cf, color, Enum.Material.Slate)
	end
end

-- Небольшой выпуклый камень: два слоя, верхний чуть светлее и повёрнут
local function addRaisedStone(parent: Instance, slab: Slab, rng: Random)
	local Dt = C.Details
	local bx, bz = range(rng, 0.8, 1.2), range(rng, 0.7, 1.0)
	local r = math.sqrt(bx * bx + bz * bz) / 2
	local roomX, roomZ = slab.W / 2 - r - 0.05, slab.D / 2 - r - 0.05
	if roomX <= 0 or roomZ <= 0 then
		return
	end
	local lx, lz = range(rng, -roomX, roomX), range(rng, -roomZ, roomZ)
	local yaw = range(rng, 0, math.pi)
	local base = slab.Cf * CFrame.new(lx, slab.Thick / 2 + 0.05, lz) * CFrame.Angles(0, yaw, 0)
	PartKit.Block(parent, "ВыпуклыйКамень", Vector3.new(bx, 0.12, bz), base, Dt.RaisedBaseColor, Enum.Material.Slate)
	local cap = slab.Cf
		* CFrame.new(lx, slab.Thick / 2 + 0.135, lz)
		* CFrame.Angles(0, yaw + range(rng, -0.2, 0.2), 0)
	PartKit.Block(parent, "ВыпуклыйКамень", Vector3.new(bx * 0.68, 0.07, bz * 0.68), cap, Dt.RaisedCapColor, Enum.Material.Slate)
end

local function buildDetails(parent: Instance, slabs: { Slab }, rng: Random)
	local Dt = C.Details
	local n = #slabs
	if n == 0 then
		return
	end
	for _ = 1, Dt.ChamferCount do
		local slab = slabs[rng:NextInteger(1, n)]
		local corner = rng:NextInteger(1, 4)
		local c1 = range(rng, Dt.ChamferSizeMin, Dt.ChamferSizeMax)
		local c2 = range(rng, Dt.ChamferSizeMin, Dt.ChamferSizeMax)
		if not slab.Used[corner] and slab.W > c1 * 2.2 and slab.D > c2 * 2.2 then
			addChamfer(parent, slab, corner, c1, c2)
		end
	end
	for _ = 1, Dt.CrackCount do
		addCrack(parent, slabs[rng:NextInteger(1, n)], rng)
	end
	for _ = 1, Dt.MossCreviceCount do
		addMossCrevice(parent, slabs[rng:NextInteger(1, n)], rng)
	end
	local placed = 0
	local tries = 0
	while placed < Dt.MossCornerCount and tries < Dt.MossCornerCount * 6 do
		tries += 1
		if addMossCorner(parent, slabs[rng:NextInteger(1, n)], rng) then
			placed += 1
		end
	end
	for _ = 1, Dt.PebbleCount do
		addPebble(parent, slabs[rng:NextInteger(1, n)], rng)
	end
	for _ = 1, Dt.RaisedCount do
		addRaisedStone(parent, slabs[rng:NextInteger(1, n)], rng)
	end
end

-- ================================ ПОСТАМЕНТ =================================

local function buildDais(parent: Instance, rng: Random): SpawnLocation
	local D = C.Dais
	local cx, cz = C.Center.X, C.Center.Z
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawnLocation"
	spawn.Size = Vector3.new(D.Size, D.Thickness, D.Size)
	spawn.CFrame = CFrame.new(cx, D.TopY - D.Thickness / 2, cz)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Color = D.Color
	spawn.Material = D.Material
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = parent

	-- Срезанные углы постамента
	local record: Slab = {
		Cf = spawn.CFrame,
		W = D.Size,
		D = D.Size,
		Thick = D.Thickness,
		Gap = 0,
		TopY = D.TopY,
		Used = {},
	}
	for corner = 1, 4 do
		addChamfer(parent, record, corner, D.ChamferSize, D.ChamferSize)
	end

	local lift = C.Details.Lift
	local grooveY = D.TopY + lift + 0.003
	local inlayY = grooveY + 0.02

	-- Кольца: канавка + тонкая неоновая вставка; в четырёх сторонах света — разрывы под руны
	local function ring(radius: number, segments: number, withGroove: boolean, skipEvery: number)
		local chord = 2 * radius * math.sin(math.pi / segments)
		for i = 0, segments - 1 do
			if skipEvery <= 0 or i % skipEvery ~= 0 then
				local theta = 2 * math.pi * i / segments
				local rot = CFrame.Angles(0, -(theta + math.pi / 2), 0)
				local pos = Vector3.new(cx + radius * math.cos(theta), 0, cz + radius * math.sin(theta))
				if withGroove then
					PartKit.Block(parent, "КанавкаКольца", Vector3.new(chord * 1.04, 0.02, 0.2), CFrame.new(pos.X, grooveY, pos.Z) * rot, D.GrooveColor, D.Material)
				end
				PartKit.Block(
					parent,
					"РунаКольца",
					Vector3.new(chord * 1.04, 0.02, 0.07),
					CFrame.new(pos.X, inlayY, pos.Z) * rot,
					D.InlayColor,
					Enum.Material.Neon,
					{ Transparency = D.InlayTransparency, CastShadow = false }
				)
			end
		end
	end
	ring(D.OuterRingRadius, D.OuterRingSegments, true, 5)
	ring(D.InnerRingRadius, D.InnerRingSegments, false, 0)

	-- Лучи-руны по сторонам света, ромбы у углов и центральный ромб
	for i = 0, 3 do
		local theta = math.pi / 2 * i
		local rot = CFrame.Angles(0, -(theta + math.pi / 2) + math.pi / 2, 0)
		local rr = D.OuterRingRadius + 0.45
		PartKit.Block(parent, "ГрооваЛуча", Vector3.new(0.9, 0.02, 0.2), CFrame.new(cx + rr * math.cos(theta), grooveY, cz + rr * math.sin(theta)) * rot, D.GrooveColor, D.Material)
		PartKit.Block(
			parent,
			"РунаЛуча",
			Vector3.new(0.9, 0.02, 0.07),
			CFrame.new(cx + rr * math.cos(theta), inlayY, cz + rr * math.sin(theta)) * rot,
			D.InlayColor,
			Enum.Material.Neon,
			{ Transparency = D.InlayTransparency, CastShadow = false }
		)
	end
	local diamondOffset = D.Size / 2 - 1.15
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			PartKit.Block(
				parent,
				"РомбУгла",
				Vector3.new(0.5, 0.02, 0.5),
				CFrame.new(cx + sx * diamondOffset, inlayY, cz + sz * diamondOffset) * CFrame.Angles(0, math.pi / 4, 0),
				D.InlayColor,
				Enum.Material.Neon,
				{ Transparency = D.InlayTransparency, CastShadow = false }
			)
		end
	end
	PartKit.Block(
		parent,
		"РомбЦентра",
		Vector3.new(0.5, 0.02, 0.5),
		CFrame.new(cx, inlayY, cz) * CFrame.Angles(0, math.pi / 4 + range(rng, -0.05, 0.05), 0),
		D.InlayColor,
		Enum.Material.Neon,
		{ Transparency = D.InlayTransparency, CastShadow = false }
	)
	return spawn
end

-- ================================ ПЕРИМЕТР ==================================

-- Проверка: деталь с габаритным радиусом r не мешает проходам, кругу вокруг спавна и соседям
local function isFree(x: number, z: number, r: number, placed: { Circle }): boolean
	local B, P, m = C.Bounds, C.Passages, C.EdgeMargin
	if x - r < B.MinX + m or x + r > B.MaxX - m or z - r < B.MinZ + m or z + r > B.MaxZ - m then
		return false
	end
	local half = if z < C.Center.Z then P.NorthHalfWidth else P.SouthHalfWidth
	if math.abs(x) < half + r then
		return false
	end
	if z + r > P.SideZMin and z - r < P.SideZMax then
		return false
	end
	local dx, dz = x - C.Center.X, z - C.Center.Z
	if math.sqrt(dx * dx + dz * dz) < P.FreeRadius + r then
		return false
	end
	for _, c in ipairs(placed) do
		local ex, ez = x - c.X, z - c.Z
		if math.sqrt(ex * ex + ez * ez) < r + c.R - 0.2 then
			return false
		end
	end
	return true
end

-- Подбор места у одного из краёв площади; nil — не нашлось
local function findEdgeSpot(rng: Random, r: number, placed: { Circle }): (number?, number?)
	local B, Bo = C.Bounds, C.Boulders
	for _ = 1, 80 do
		local edge = rng:NextInteger(1, 4)
		local inset = r + range(rng, Bo.EdgeInsetMin, Bo.EdgeInsetMax)
		local x, z
		if edge == 1 then
			x, z = range(rng, B.MinX + r, B.MaxX - r), B.MinZ + inset
		elseif edge == 2 then
			x, z = range(rng, B.MinX + r, B.MaxX - r), B.MaxZ - inset
		elseif edge == 3 then
			x, z = B.MinX + inset, range(rng, B.MinZ + r, B.MaxZ - r)
		else
			x, z = B.MaxX - inset, range(rng, B.MinZ + r, B.MaxZ - r)
		end
		if isFree(x, z, r, placed) then
			return x, z
		end
	end
	return nil, nil
end

-- Каменный фонарь: основание, столб, площадка, клетка со светящимся ядром, крышка
local function buildLantern(parent: Instance, x: number, z: number, yaw: number, index: number)
	local L = C.Lanterns
	local model = Instance.new("Model")
	model.Name = "КаменныйФонарь" .. index
	model.Parent = parent
	local origin = CFrame.new(x, L.BaseY, z) * CFrame.Angles(0, yaw, 0)
	local mat = L.StoneMaterial

	PartKit.Block(model, "Основание", Vector3.new(0.95, 0.22, 0.95), origin * CFrame.new(0, 0.11, 0), L.StoneDarkColor, mat, { CanCollide = true })
	PartKit.Cylinder(model, "Столб", 0.38, 1.0, origin * CFrame.new(0, 0.72, 0), L.StoneColor, mat, { CanCollide = true })
	PartKit.Block(model, "Площадка", Vector3.new(0.8, 0.12, 0.8), origin * CFrame.new(0, 1.28, 0), L.StoneColor, mat)
	local core = PartKit.Block(
		model,
		"Ядро",
		Vector3.new(0.42, 0.48, 0.42),
		origin * CFrame.new(0, 1.58, 0),
		L.CoreColor,
		Enum.Material.Neon,
		{ CastShadow = false }
	)
	PartKit.PointLight(core, L.LightColor, L.LightBrightness, L.LightRange)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			PartKit.Block(model, "СтойкаКлетки", Vector3.new(0.08, 0.52, 0.08), origin * CFrame.new(sx * 0.31, 1.59, sz * 0.31), L.StoneDarkColor, mat)
		end
	end
	PartKit.Block(model, "Крышка", Vector3.new(0.98, 0.14, 0.98), origin * CFrame.new(0, 1.92, 0), L.StoneColor, mat)
	PartKit.Block(model, "КрышкаВерх", Vector3.new(0.6, 0.14, 0.6), origin * CFrame.new(0, 2.06, 0), L.StoneDarkColor, mat)
	PartKit.Ball(model, "Навершие", 0.22, origin * CFrame.new(0, 2.22, 0), L.StoneColor, mat)
end

-- Описание кластера валунов до размещения: нужен габаритный радиус
type BoulderPart = { Kind: number, Off: Vector3, Size: Vector3, Rot: CFrame, Mat: Enum.Material, Color: Color3 }

local function genBoulder(rng: Random): ({ BoulderPart }, number)
	local Bo = C.Boulders
	local parts: { BoulderPart } = {}
	local count = rng:NextInteger(2, 4)
	local radius = 0
	local mainSize = range(rng, Bo.MainSizeMin, Bo.MainSizeMax)
	for i = 1, count do
		local scale = if i == 1 then mainSize else mainSize * range(rng, 0.35, 0.65)
		local size = Vector3.new(scale * range(rng, 0.8, 1.15), scale * range(rng, 0.55, 0.9), scale * range(rng, 0.8, 1.15))
		local off = Vector3.zero
		if i > 1 then
			local ang = range(rng, 0, math.pi * 2)
			local dist = mainSize * 0.45 + scale * 0.25
			off = Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
		end
		local rot = CFrame.Angles(range(rng, -0.35, 0.35), range(rng, 0, math.pi * 2), range(rng, -0.35, 0.35))
		local kind = rng:NextInteger(1, 3) -- 1 блок, 2 клин, 3 эллипсоид
		table.insert(parts, {
			Kind = kind,
			Off = off,
			Size = size,
			Rot = rot,
			Mat = Bo.Materials[rng:NextInteger(1, #Bo.Materials)],
			Color = tint(pickColor(rng, Bo.Colors), rng, 0.07),
		})
		local reach = Vector3.new(off.X, 0, off.Z).Magnitude + math.sqrt(size.X * size.X + size.Z * size.Z) / 2
		radius = math.max(radius, reach)
	end
	return parts, radius
end

local function buildBoulder(parent: Instance, x: number, z: number, parts: { BoulderPart }, index: number)
	local model = Instance.new("Model")
	model.Name = "Валун" .. index
	model.Parent = parent
	for _, p in ipairs(parts) do
		local cf = CFrame.new(x + p.Off.X, 0.2 + p.Size.Y * 0.38, z + p.Off.Z) * p.Rot
		local opts = { CanCollide = true }
		if p.Kind == 2 then
			PartKit.Wedge(model, "Обломок", p.Size, cf, p.Color, p.Mat, opts)
		elseif p.Kind == 3 then
			PartKit.Ellipsoid(model, "Булыжник", p.Size, cf, p.Color, p.Mat, opts)
		else
			PartKit.Block(model, "Глыба", p.Size, cf, p.Color, p.Mat, opts)
		end
	end
end

-- Кластер кристаллов: камень-основание и 3–6 наклонных призм с остриями
local function buildCrystals(parent: Instance, x: number, z: number, index: number, rng: Random)
	local K = C.Crystals
	local model = Instance.new("Model")
	model.Name = "Кристаллы" .. index
	model.Parent = parent
	local tone = K.Palettes[(index - 1) % #K.Palettes + 1]
	local base = PartKit.Block(
		model,
		"ОснованиеКристаллов",
		Vector3.new(1.5, 0.36, 1.2),
		CFrame.new(x, 0.28, z) * CFrame.Angles(0, range(rng, 0, math.pi), 0),
		K.BaseColor,
		Enum.Material.Basalt,
		{ CanCollide = true }
	)
	if index <= K.LightCount then
		PartKit.PointLight(base, tone, K.LightBrightness, K.LightRange)
	end
	local origin = Vector3.new(x, 0.44, z)
	local n = rng:NextInteger(K.PerClusterMin, K.PerClusterMax)
	for i = 1, n do
		local len = range(rng, K.LengthMin, K.LengthMax)
		local width = range(rng, K.WidthMin, K.WidthMax)
		local ang = range(rng, 0, math.pi * 2)
		local dist = range(rng, 0, 0.45)
		local pos = origin + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
		local tilt = math.rad(range(rng, 6, K.MaxTiltDeg))
		local frame = CFrame.new(pos) * CFrame.Angles(0, ang, 0) * CFrame.Angles(tilt, 0, 0)
		local glowing = i == 1 or rng:NextNumber() < 0.3
		local color = tint(tone, rng, 0.12)
		PartKit.Block(
			model,
			"Кристалл",
			Vector3.new(width, len, width),
			frame * CFrame.new(0, len / 2 - 0.05, 0),
			color,
			if glowing then Enum.Material.Neon else Enum.Material.Glass,
			{ Transparency = if glowing then 0 else K.GlassTransparency, Reflectance = if glowing then 0 else 0.1, CastShadow = false }
		)
		local tip = len * 0.28
		PartKit.Block(
			model,
			"ОстриёКристалла",
			Vector3.new(width * 0.6, tip, width * 0.6),
			frame * CFrame.new(0, len - 0.05 + tip / 2 - 0.01, 0) * CFrame.Angles(0, math.pi / 4, 0),
			PartKit.Lighten(color, 0.25),
			Enum.Material.Neon,
			{ CastShadow = false }
		)
	end
end

local function buildPerimeter(parent: Instance, rng: Random)
	local placed: { Circle } = {}
	local lanterns = newFolder(parent, "Фонари")
	local boulders = newFolder(parent, "Валуны")
	local crystals = newFolder(parent, "Кристаллы")

	for i, p in ipairs(C.Lanterns.Positions) do
		local yaw = range(rng, -0.4, 0.4)
		if isFree(p.X, p.Z, C.Lanterns.Radius, placed) then
			buildLantern(lanterns, p.X, p.Z, yaw, i)
			table.insert(placed, { X = p.X, Z = p.Z, R = C.Lanterns.Radius })
		end
	end

	-- сначала кристаллы (небольшой габарит), затем валуны занимают остаток периметра
	for i = 1, C.Crystals.Clusters do
		local x, z = findEdgeSpot(rng, C.Crystals.Radius, placed)
		if x and z then
			buildCrystals(crystals, x, z, i, rng)
			table.insert(placed, { X = x, Z = z, R = C.Crystals.Radius })
		end
	end

	for i = 1, C.Boulders.Clusters do
		-- не поместился — пробуем другую форму кластера
		for _ = 1, 8 do
			local parts, radius = genBoulder(rng)
			local x, z = findEdgeSpot(rng, radius, placed)
			if x and z then
				buildBoulder(boulders, x, z, parts, i)
				table.insert(placed, { X = x, Z = z, R = radius })
				break
			end
		end
	end
end

-- ============================== ТОЧКА ВХОДА =================================

function SpawnPlazaBuilder.Build(parent: Instance): PlazaRefs
	local old = parent:FindFirstChild("StoneSpawnPlaza")
	if old then
		old:Destroy()
	end

	local rng = Random.new(C.Seed)
	local model = Instance.new("Model")
	model.Name = "StoneSpawnPlaza"

	local baseFolder = newFolder(model, "Основа")
	local borderFolder = newFolder(model, "Бордюр")
	local slabFolder = newFolder(model, "Плиты")
	local detailFolder = newFolder(model, "Детали")
	local daisFolder = newFolder(model, "Постамент")
	local perimeterFolder = newFolder(model, "Периметр")

	buildPlate(baseFolder)
	buildBorder(borderFolder, rng)

	local slabs = buildGridSlabs(slabFolder, rng)
	local ringSlabs = buildRing(daisFolder, rng)
	for _, s in ipairs(ringSlabs) do
		table.insert(slabs, s)
	end
	buildDetails(detailFolder, slabs, rng)

	local spawn = buildDais(daisFolder, rng)
	buildPerimeter(perimeterFolder, rng)

	model.Parent = parent
	return { Model = model, SpawnLocation = spawn }
end

return SpawnPlazaBuilder
