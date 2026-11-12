--!strict
-- ============================================================================
-- 🎒 МОДУЛЬ: BackpackDetailer (ReplicatedStorage.Modules.BackpackDetailer)
-- v52: «проход детализации» рюкзаков. После базовой сборки (EquipmentBuilder) модуль
-- сканирует реальную поверхность корпуса и кладёт поверх неё швы, потёртости, пряжки,
-- кольца и уникальные детали каждого из 10 уровней. Все детали создаются через ctx.Add
-- (Massless, без коллизий, привариваются к торсу). Цвета и размеры — GameConfig.BACKPACK_DETAIL.
-- ============================================================================

local PartKit = require(script.Parent:WaitForChild("PartKit"))
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local BackpackDetailer = {}

export type AddOpts = {
	Push: number?,
	Inflate: boolean?,
	DepthAxis: string?,
	Tint: boolean?,
	FillGlow: boolean?,
	Shape: Enum.PartType?,
	Rounded: boolean?,
	Wedge: boolean?,
	Reflectance: number?,
	Transparency: number?,
}

export type DecorateContext = {
	Model: Model,            -- модель рюкзака (в неё уже добавлены все базовые детали)
	Level: number,           -- уровень рюкзака 1..10
	Scale: number,           -- общий масштаб рюкзака
	Anchored: boolean,       -- true для витрины / ViewportFrame
	OnCharacter: boolean,    -- true, если рюкзак на спине персонажа (детали варятся к торсу)
	Origin: CFrame,          -- мировая система координат рюкзака (CFrame торса или точки витрины)
	Width: number,           -- габарит корпуса по X
	Height: number,          -- габарит корпуса по Y
	Depth: number,           -- габарит корпуса по Z
	CenterY: number,         -- локальный Y центра корпуса
	CenterZ: number,         -- локальный Z центра корпуса
	FrontZ: number,          -- локальный Z внешней (дальней от спины) грани корпуса
	Palette: { [string]: Color3 },
	Add: (name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, opts: AddOpts?) -> BasePart,
}

-- ----------------------------------------------------------------------------
-- Настройки: значения по умолчанию на случай, если раздел конфига не найден
-- ----------------------------------------------------------------------------
type LevelCfg = {
	Metal: Color3, Accent: Color3, Accent2: Color3, Glow: Color3, Glow2: Color3, Cloth: Color3, Thread: Color3,
	Count: number, LightBrightness: number, LightRange: number, EmitRate: number, Shine: number,
}

type SharedCfg = {
	Seed: number, MaxParts: number, MaxLights: number, MaxEmitters: number, Lift: number,
	StitchDash: number, StitchPerRow: number, ScuffCount: number, WaistLimit: number,
}

local DEFAULT_LEVEL: LevelCfg = {
	Metal = Color3.fromRGB(190, 194, 202), Accent = Color3.fromRGB(214, 170, 70), Accent2 = Color3.fromRGB(90, 60, 40),
	Glow = Color3.fromRGB(120, 220, 255), Glow2 = Color3.fromRGB(255, 255, 255), Cloth = Color3.fromRGB(60, 50, 40),
	Thread = Color3.fromRGB(220, 200, 160), Count = 0, LightBrightness = 0, LightRange = 0, EmitRate = 0, Shine = 0.2,
}

local DEFAULT_SHARED: SharedCfg = {
	Seed = 5200, MaxParts = 45, MaxLights = 2, MaxEmitters = 2, Lift = 0.015,
	StitchDash = 0.11, StitchPerRow = 5, ScuffCount = 3, WaistLimit = 0.44,
}

-- Копирует из источника только поля нужного типа; остальное берётся из значений по умолчанию
local function mergeCfg(defaults: any, source: any): any
	local out: { [string]: any } = {}
	for k, v in pairs(defaults :: { [string]: any }) do
		local sv = if typeof(source) == "table" then (source :: { [string]: any })[k] else nil
		out[k] = if sv ~= nil and typeof(sv) == typeof(v) then sv else v
	end
	return out
end

local function loadConfig(level: number): (LevelCfg, SharedCfg)
	local root = GameConfig :: any
	local levels = root.BACKPACK_DETAIL
	local lc: any = if typeof(levels) == "table" then levels[level] else nil
	local sc: any = root.BACKPACK_DETAIL_SHARED
	return mergeCfg(DEFAULT_LEVEL, lc) :: LevelCfg, mergeCfg(DEFAULT_SHARED, sc) :: SharedCfg
end

-- ----------------------------------------------------------------------------
-- Сканирование поверхности: каждая деталь корпуса — осево-выровненный объём в локальной системе
-- ----------------------------------------------------------------------------
type Box = {
	Name: string, Color: Color3,
	Cx: number, Cy: number, Cz: number, -- центр
	Ex: number, Ey: number, Ez: number, -- полуразмеры осевой оболочки
	Ell: boolean,                       -- эллипсоид (шар / SpecialMesh Sphere)
	Push: number,
}

local function isEllipsoid(p: BasePart): boolean
	if p:IsA("Part") and (p :: Part).Shape == Enum.PartType.Ball then
		return true
	end
	local m = p:FindFirstChildOfClass("SpecialMesh")
	return m ~= nil and m.MeshType == Enum.MeshType.Sphere
end

local function makeBox(p: BasePart, origin: CFrame): Box
	local cf = origin:ToObjectSpace(p.CFrame)
	local hx, hy, hz = p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2
	local xv, yv, zv = cf.XVector, cf.YVector, cf.ZVector
	local push = p:GetAttribute("Push")
	return {
		Name = p.Name, Color = p.Color,
		Cx = cf.X, Cy = cf.Y, Cz = cf.Z,
		Ex = math.max(math.abs(xv.X) * hx + math.abs(yv.X) * hy + math.abs(zv.X) * hz, 1e-3),
		Ey = math.max(math.abs(xv.Y) * hx + math.abs(yv.Y) * hy + math.abs(zv.Y) * hz, 1e-3),
		Ez = math.max(math.abs(xv.Z) * hx + math.abs(yv.Z) * hy + math.abs(zv.Z) * hz, 1e-3),
		Ell = isEllipsoid(p),
		Push = if typeof(push) == "number" then push else 0,
	}
end

-- Детали, которые не считаются «поверхностью» (нити, ручки, бегунки, лямки)
local SKIP_PREFIX = { "Strap", "Stitch", "Handle", "Zip", "PocketZip", "Dtl" }

local function isSurfacePart(p: BasePart, s: number): boolean
	if p.Transparency >= 0.9 then
		return false
	end
	for _, pre in ipairs(SKIP_PREFIX) do
		if string.sub(p.Name, 1, #pre) == pre then
			return false
		end
	end
	local sz = p.Size
	return math.max(sz.X, sz.Y, sz.Z) >= 0.12 * s
end

-- ----------------------------------------------------------------------------
-- Главная функция
-- ----------------------------------------------------------------------------
function BackpackDetailer.Decorate(ctx: DecorateContext)
	local level = math.clamp(math.floor(ctx.Level), 1, 10)
	local s: number = if ctx.Scale > 0 then ctx.Scale else 1
	local cfg, shared = loadConfig(level)
	local rng = Random.new(shared.Seed + level)

	local W, H, D = ctx.Width, ctx.Height, ctx.Depth
	local cy, cz = ctx.CenterY, ctx.CenterZ
	local backZ = cz - D / 2           -- ближе к торсу детали не ставятся
	local minY = cy - H * shared.WaistLimit -- ниже пояса детали не ставятся
	local LIFT = shared.Lift * s
	local pal = ctx.Palette
	local bodyColor: Color3 = pal.body or Color3.fromRGB(120, 100, 80)
	local metalMat = Enum.Material.Metal

	-- Сканирование существующих деталей модели
	local surfaces: { Box } = {}
	local byName: { [string]: { Box } } = {}
	for _, d in ipairs(ctx.Model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.9 then
			local b = makeBox(d, ctx.Origin)
			local list = byName[d.Name]
			if not list then
				list = {}
				byName[d.Name] = list
			end
			table.insert(list :: { Box }, b)
			if isSurfacePart(d, s) then
				table.insert(surfaces, b)
			end
		end
	end

	local function find(name: string): Box?
		local l = byName[name]
		return if l then l[1] else nil
	end

	local function findAll(name: string): { Box }
		return byName[name] or {}
	end

	-- Внешний Z поверхности в точке (x, y); nil, если точка не покрыта
	local function zAtRaw(x: number, y: number): (number?, number)
		local best: number? = nil
		local push = 0
		for _, b in ipairs(surfaces) do
			local dx = (x - b.Cx) / b.Ex
			local dy = (y - b.Cy) / b.Ey
			local z: number? = nil
			if b.Ell then
				local d2 = dx * dx + dy * dy
				if d2 < 1 then
					z = b.Cz + b.Ez * math.sqrt(1 - d2)
				end
			elseif math.abs(dx) <= 1 and math.abs(dy) <= 1 then
				z = b.Cz + b.Ez
			end
			if z and (best == nil or z > best) then
				best = z
				push = b.Push
			end
		end
		return best, push
	end

	-- Если точка вне корпуса, ищем ближайшую покрытую, смещаясь к центру корпуса
	local function zAt(x: number, y: number): (number, number)
		for i = 0, 6 do
			local f = 1 - i * 0.12
			local z, push = zAtRaw(x * f, cy + (y - cy) * f)
			if z then
				return z, push
			end
		end
		return ctx.FrontZ - 0.05 * s, 0
	end

	-- Верхняя поверхность над точкой (x, z)
	local function topAt(x: number, z: number): (number?, number)
		local best: number? = nil
		local push = 0
		for _, b in ipairs(surfaces) do
			local dx = (x - b.Cx) / b.Ex
			local dz = (z - b.Cz) / b.Ez
			local y: number? = nil
			if b.Ell then
				local d2 = dx * dx + dz * dz
				if d2 < 1 then
					y = b.Cy + b.Ey * math.sqrt(1 - d2)
				end
			elseif math.abs(dx) <= 1 and math.abs(dz) <= 1 then
				y = b.Cy + b.Ey
			end
			if y and (best == nil or y > best) then
				best = y
				push = b.Push
			end
		end
		return best, push
	end

	-- Боковая поверхность (sign = ±1) в точке (y, z); возвращает координату X
	local function sideAt(y: number, z: number, sign: number): (number?, number)
		local best: number? = nil
		local push = 0
		for _, b in ipairs(surfaces) do
			local dy = (y - b.Cy) / b.Ey
			local dz = (z - b.Cz) / b.Ez
			local x: number? = nil
			if b.Ell then
				local d2 = dy * dy + dz * dz
				if d2 < 1 then
					x = b.Cx + sign * b.Ex * math.sqrt(1 - d2)
				end
			elseif math.abs(dy) <= 1 and math.abs(dz) <= 1 then
				x = b.Cx + sign * b.Ex
			end
			if x and (best == nil or sign * x > sign * best) then
				best = x
				push = b.Push
			end
		end
		return best, push
	end

	-- Нормаль передней поверхности по градиенту Z (наклон ограничен, чтобы не скакать на стыках)
	local function normalAt(x: number, y: number): Vector3
		local d = 0.05 * s
		local fx = math.clamp((zAt(x + d, y) - zAt(x - d, y)) / (2 * d), -0.7, 0.7)
		local fy = math.clamp((zAt(x, y + d) - zAt(x, y - d)) / (2 * d), -0.7, 0.7)
		return Vector3.new(-fx, -fy, 1).Unit
	end

	-- Точка на поверхности, смещённая вдоль нормали на extra
	local function surfPoint(x: number, y: number, extra: number): (Vector3, number)
		local z, push = zAt(x, y)
		return Vector3.new(x, y, z) + normalAt(x, y) * (extra + LIFT), push
	end

	-- ------------------------------------------------------------------------
	-- Создание деталей с учётом лимитов
	-- ------------------------------------------------------------------------
	local count, lights, emitters = 0, 0, 0

	local function withPush(opts: AddOpts?, push: number?): AddOpts
		local o: AddOpts = {}
		if opts then
			o.Shape = opts.Shape
			o.Wedge = opts.Wedge
			o.Reflectance = opts.Reflectance
			o.Transparency = opts.Transparency
		end
		o.Push = push
		return o
	end

	local function put(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, opts: AddOpts?, onTop: boolean?): BasePart?
		if count >= shared.MaxParts then
			return nil
		end
		local pos = cf.Position
		if pos.Y < minY or (not onTop and pos.Z < backZ + 0.02 * s) then
			return nil
		end
		count += 1
		local ok, part = pcall(ctx.Add, "Dtl" .. name, size, cf, color, mat, opts)
		if ok and typeof(part) == "Instance" and (part :: Instance):IsA("BasePart") then
			return part :: BasePart
		end
		return nil
	end

	-- Плоская пластина, лежащая на поверхности и повёрнутая по её нормали
	local function plate(name: string, w: number, h: number, thick: number, x: number, y: number, roll: number,
		color: Color3, mat: Enum.Material, extra: number?, opts: AddOpts?): BasePart?
		local z, push = zAt(x, y)
		local n = normalAt(x, y)
		local pos = Vector3.new(x, y, z) + n * (thick / 2 + LIFT + (extra or 0))
		local cf = CFrame.lookAt(pos, pos - n) * CFrame.Angles(0, 0, roll)
		return put(name, Vector3.new(w, h, thick), cf, color, mat, withPush(opts, push))
	end

	-- Диск (цилиндр, ось которого направлена по нормали поверхности): кольца, заклёпки
	local function disc(name: string, diameter: number, thick: number, x: number, y: number,
		color: Color3, mat: Enum.Material, extra: number?, opts: AddOpts?): BasePart?
		local z, push = zAt(x, y)
		local n = normalAt(x, y)
		local pos = Vector3.new(x, y, z) + n * (thick / 2 + LIFT + (extra or 0))
		local cf = CFrame.lookAt(pos, pos - n) * CFrame.Angles(0, math.rad(-90), 0)
		local o = withPush(opts, push)
		o.Shape = Enum.PartType.Cylinder
		return put(name, Vector3.new(thick, diameter, diameter), cf, color, mat, o)
	end

	local function ball(name: string, diameter: number, pos: Vector3, color: Color3, mat: Enum.Material, push: number?, opts: AddOpts?): BasePart?
		local o = withPush(opts, push)
		o.Shape = Enum.PartType.Ball
		return put(name, Vector3.new(diameter, diameter, diameter), CFrame.new(pos), color, mat, o)
	end

	-- Стержень между двумя точками (round = цилиндр, иначе брусок)
	local function bar(name: string, a: Vector3, b: Vector3, t: number, color: Color3, mat: Enum.Material,
		push: number?, round: boolean?, opts: AddOpts?): BasePart?
		local d = b - a
		local len = d.Magnitude
		if len < 1e-4 then
			return nil
		end
		local dir = d / len
		local ref = if math.abs(dir.Z) < 0.9 then Vector3.zAxis else Vector3.yAxis
		local cf = CFrame.fromMatrix((a + b) / 2, dir, ref:Cross(dir).Unit)
		local o = withPush(opts, push)
		if round then
			o.Shape = Enum.PartType.Cylinder
		end
		return put(name, Vector3.new(len + t * 0.5, t, t), cf, color, mat, o)
	end

	-- Цепочка стержней по точкам поверхности
	local function pathBars(name: string, pts: { Vector3 }, pushes: { number }, t: number, color: Color3,
		mat: Enum.Material, round: boolean?, opts: AddOpts?, altColor: Color3?): { BasePart }
		local out: { BasePart } = {}
		for i = 1, #pts - 1 do
			local c = if altColor and i % 2 == 0 then altColor else color
			local p = bar(name, pts[i], pts[i + 1], t, c, mat, pushes[i], round, opts)
			if p then
				table.insert(out, p)
			end
		end
		return out
	end

	local function addLight(parent: BasePart, color: Color3)
		if not ctx.OnCharacter or lights >= shared.MaxLights or cfg.LightBrightness <= 0 then
			return
		end
		lights += 1
		PartKit.PointLight(parent, color, cfg.LightBrightness, cfg.LightRange)
	end

	local function addEmitter(parent: BasePart, props: PartKit.EmitterProps)
		if not ctx.OnCharacter or emitters >= shared.MaxEmitters or cfg.EmitRate <= 0 then
			return
		end
		emitters += 1
		PartKit.Emitter(parent, props)
	end

	-- Ряд стежков вдоль отрезка по поверхности
	local function stitchRow(x1: number, y1: number, x2: number, y2: number, n: number, color: Color3)
		local ang = math.atan2(y2 - y1, x2 - x1)
		for i = 1, n do
			local t = (i - 0.5) / n
			plate("Stitch", shared.StitchDash * s, 0.022 * s, 0.012 * s, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, ang,
				color, Enum.Material.Fabric)
		end
	end

	-- Горизонтальная полуширина разметки на объёме b на высоте долей dyFrac от его центра
	local function span(b: Box, dyFrac: number): number
		if b.Ell then
			return b.Ex * math.sqrt(math.max(1 - dyFrac * dyFrac, 0.04)) * 0.8
		end
		return b.Ex * 0.85
	end

	-- Позиции плечевых лямок (для якорных колец и заклёпок)
	local strapXs: { number } = { -0.26 * W, 0.26 * W }
	do
		local straps = findAll("StrapShoulder")
		if #straps >= 2 then
			strapXs = { straps[1].Cx, straps[2].Cx }
		end
	end

	-- Заклёпки на плечевых лямках (имя содержит «Strap» — они не прыгают отдельно от лямки)
	local function shoulderRivets(color: Color3)
		for _, b in ipairs(findAll("StrapShoulder")) do
			for _, off in ipairs({ 0.30, 0.62 }) do
				local z = b.Cz + b.Ez - off * s
				put("StrapRivet", Vector3.new(0.03 * s, 0.09 * s, 0.09 * s),
					CFrame.new(b.Cx, b.Cy + b.Ey + 0.012 * s, z) * CFrame.Angles(0, 0, math.rad(90)),
					color, metalMat, { Shape = Enum.PartType.Cylinder, Reflectance = cfg.Shine }, true)
			end
		end
	end

	-- Бугельные полосы-стяжки скатки с латунной пряжкой (уровни 2 и 3)
	local function bedrollBands(bandColor: Color3, buckleColor: Color3)
		local b = find("Bedroll")
		if not b or b.Ex < b.Ey * 1.5 then
			return
		end
		for _, sx in ipairs({ -1, 1 }) do
			local x = b.Cx + sx * b.Ex * 0.62
			local r = b.Ey + 0.025 * s
			put("BedrollBand", Vector3.new(0.10 * s, r * 2, r * 2), CFrame.new(x, b.Cy, b.Cz),
				bandColor, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, Push = b.Push })
			put("BedrollBuckle", Vector3.new(0.12 * s, 0.14 * s, 0.03 * s), CFrame.new(x, b.Cy, b.Cz + r + 0.014 * s),
				buckleColor, metalMat, { Reflectance = cfg.Shine, Push = b.Push })
		end
	end

	-- ------------------------------------------------------------------------
	-- Особенности уровней
	-- ------------------------------------------------------------------------
	local features: { [number]: () -> () } = {}

	-- 1. Холщовый мешок: верёвочная перевязь с узлом и заплата со стежками
	features[1] = function()
		local y = cy + 0.34 * H
		local t = 0.075 * s
		local pts: { Vector3 } = {}
		local pushes: { number } = {}
		for i = 0, 8 do
			local p, pp = surfPoint((-0.47 + i * 0.1175) * W, y, t * 0.5)
			table.insert(pts, p)
			table.insert(pushes, pp)
		end
		pathBars("Rope", pts, pushes, t, cfg.Accent, Enum.Material.Fabric, true)

		local kx = 0.12 * W
		local knotPos, kp = surfPoint(kx, y, t * 0.9)
		ball("RopeKnot", 0.16 * s, knotPos, cfg.Accent2, Enum.Material.Fabric, kp)
		local endA, pa = surfPoint(kx + 0.05 * W, y - 0.30 * s, 0.025 * s)
		local endB, pb = surfPoint(kx - 0.03 * W, y - 0.26 * s, 0.025 * s)
		bar("RopeEnd", knotPos, endA, 0.05 * s, cfg.Accent, Enum.Material.Fabric, pa, true)
		bar("RopeEnd", knotPos, endB, 0.05 * s, cfg.Accent2, Enum.Material.Fabric, pb, true)

		-- заплата с восемью стежками по краям
		local px, py, pw, ph, pth = -0.30 * W, cy + 0.18 * H, 0.36 * s, 0.30 * s, 0.016 * s
		plate("Patch", pw, ph, pth, px, py, 0.08, cfg.Cloth, Enum.Material.Fabric)
		for _, sx in ipairs({ -0.5, 0.5 }) do
			for _, sy in ipairs({ -1, 1 }) do
				plate("Stitch", shared.StitchDash * s, 0.022 * s, 0.012 * s, px + sx * pw * 0.52, py + sy * ph * 0.40, 0.08 + math.rad(90),
					cfg.Thread, Enum.Material.Fabric, pth)
			end
			for _, sy in ipairs({ -1, 1 }) do
				plate("Stitch", shared.StitchDash * s, 0.022 * s, 0.012 * s, px + sx * pw * 0.40, py + sy * ph * 0.5, 0.08,
					cfg.Thread, Enum.Material.Fabric, pth)
			end
		end
	end

	-- 2. Кожаный рюкзак: латунные пряжки на ремнях клапана, шляпки на боковых карманах, заклёпки
	features[2] = function()
		local buckles = findAll("BuckleFrame")
		local spots: { Box } = {}
		for _, b in ipairs(buckles) do
			table.insert(spots, b)
		end
		if #spots == 0 then
			for _, sx in ipairs({ -1, 1 }) do
				table.insert(spots, { Name = "BuckleFrame", Color = cfg.Metal, Cx = sx * 0.25 * W, Cy = cy + 0.18 * H, Cz = cz,
					Ex = 0.17 * s, Ey = 0.15 * s, Ez = 0.03 * s, Ell = false, Push = 0 })
			end
		end
		for _, b in ipairs(spots) do
			plate("BrassPin", b.Ex * 1.8, 0.04 * s, 0.03 * s, b.Cx, b.Cy, 0, cfg.Accent, metalMat, 0, { Reflectance = cfg.Shine })
			for _, sx in ipairs({ -1, 1 }) do
				disc("BrassRivet", 0.06 * s, 0.025 * s, b.Cx + sx * b.Ex * 0.78, b.Cy + b.Ey * 0.72, cfg.Accent, metalMat, 0,
					{ Reflectance = cfg.Shine })
			end
		end
		for _, f in ipairs(findAll("SidePocketFlap")) do
			local sign = if f.Cx < 0 then -1 else 1
			for _, dz in ipairs({ -0.15, 0.15 }) do
				local z = f.Cz + dz * s
				local x, push = sideAt(f.Cy, z, sign)
				if x then
					ball("Stud", 0.07 * s, Vector3.new(x + sign * 0.02 * s, f.Cy, z), cfg.Accent, metalMat, push, { Reflectance = cfg.Shine })
				end
			end
		end
		bedrollBands(cfg.Accent2, cfg.Accent)
		shoulderRivets(cfg.Accent)
	end

	-- 3. Походный рюкзак: стяжки скатки, фонарик с линзой и SpotLight, карабин
	features[3] = function()
		bedrollBands(cfg.Accent, cfg.Metal)

		-- фонарик на боку: корпус вдоль оси Z, светит наружу от спины
		local fy, fz = cy + 0.12 * H, cz
		local sideX, fpush = sideAt(fy, fz, 1)
		local r, len = 0.085 * s, 0.50 * s
		local fx = (sideX or W / 2) + r + 0.012 * s
		local axis = CFrame.Angles(0, math.rad(-90), 0) -- ось цилиндра X → +Z
		local function lamp(name: string, length: number, diameter: number, dz: number, color: Color3, mat: Enum.Material): BasePart?
			return put(name, Vector3.new(length, diameter, diameter), CFrame.new(fx, fy, fz + dz) * axis, color, mat,
				{ Shape = Enum.PartType.Cylinder, Push = fpush, Reflectance = if mat == metalMat then cfg.Shine else 0 })
		end
		lamp("FlashBody", len, r * 2, 0, cfg.Accent2, Enum.Material.SmoothPlastic)
		lamp("FlashCap", 0.05 * s, r * 2.05, -len / 2, cfg.Metal, metalMat)
		lamp("FlashRing", 0.07 * s, r * 2 + 0.035 * s, len / 2 - 0.02 * s, cfg.Metal, metalMat)
		local lens = lamp("FlashLens", 0.03 * s, r * 1.6, len / 2 + 0.02 * s, cfg.Glow, Enum.Material.Neon)
		for _, dz in ipairs({ -0.14, 0.12 }) do
			put("FlashClip", Vector3.new(r * 2 + 0.04 * s, r * 2 + 0.04 * s, 0.05 * s), CFrame.new(fx, fy, fz + dz * s),
				cfg.Cloth, Enum.Material.Fabric, { Push = fpush })
		end
		if lens and ctx.OnCharacter and lights < shared.MaxLights and cfg.LightBrightness > 0 then
			lights += 1
			PartKit.SpotLight(lens, cfg.Glow, cfg.LightBrightness, cfg.LightRange, 60, Enum.NormalId.Right)
		end

		-- карабин на петле у левого нижнего угла
		local kx, ky = -0.42 * W, cy - 0.28 * H
		plate("LoopTab", 0.07 * s, 0.24 * s, 0.016 * s, kx, ky + 0.10 * s, 0, cfg.Cloth, Enum.Material.Fabric)
		local cw, ch, bt = 0.17 * s, 0.27 * s, 0.026 * s
		local cyk = ky - 0.06 * s
		local lift = 0.016 * s
		plate("Carabiner", cw, bt, bt, kx, cyk + ch / 2, 0, cfg.Metal, metalMat, lift, { Reflectance = cfg.Shine })
		plate("Carabiner", cw, bt, bt, kx, cyk - ch / 2, 0, cfg.Metal, metalMat, lift, { Reflectance = cfg.Shine })
		plate("Carabiner", bt, ch, bt, kx - cw / 2, cyk, 0, cfg.Metal, metalMat, lift, { Reflectance = cfg.Shine })
		plate("Carabiner", bt, ch * 0.8, bt, kx + cw / 2, cyk - ch * 0.1, 0, cfg.Glow2, metalMat, lift, { Reflectance = cfg.Shine })
		shoulderRivets(cfg.Metal)
	end

	-- 4. Городской рюкзак: бегунки молний, светоотражающая лента, стальной шильдик с заклёпками
	features[4] = function()
		-- бегунок на дальнем от штатной ручки конце молнии
		local zips = findAll("Zip")
		local pulls = findAll("ZipPull")
		local sx0, sy0 = 0.20 * W, cy + 0.30 * H
		if #zips > 0 then
			local ref = if #pulls > 0 then pulls[1].Cx else 0
			local far = zips[1]
			for _, z in ipairs(zips) do
				if math.abs(z.Cx - ref) > math.abs(far.Cx - ref) then
					far = z
				end
			end
			sx0, sy0 = far.Cx, far.Cy
		end
		local function pull(x: number, y: number)
			plate("ZipSlider", 0.12 * s, 0.07 * s, 0.04 * s, x, y, 0, cfg.Metal, metalMat, 0, { Reflectance = cfg.Shine })
			plate("ZipPullTab", 0.05 * s, 0.20 * s, 0.02 * s, x, y - 0.12 * s, 0, cfg.Metal, metalMat, 0.02 * s, { Reflectance = cfg.Shine })
		end
		pull(sx0, sy0)
		local pocket = find("FrontPocket")
		if pocket then
			pull(pocket.Cx + pocket.Ex * 0.45, pocket.Cy + pocket.Ey * 0.55)
		end

		-- светоотражающая лента на кармане
		local pb: Box = pocket or { Name = "FrontPocket", Color = cfg.Metal, Cx = 0, Cy = cy - 0.12 * H, Cz = cz, Ex = 0.3 * W, Ey = 0.2 * H,
			Ez = 0.1, Ell = false, Push = 0 }
		local n = 5
		local half = span(pb, 0.1)
		local step = half * 2 / n
		for i = 1, n do
			plate("Reflect", step * 1.04, 0.07 * s, 0.014 * s, pb.Cx - half + (i - 0.5) * step, pb.Cy + pb.Ey * 0.1, 0,
				cfg.Glow, Enum.Material.Neon, 0, { Transparency = 0.25 })
		end

		-- шильдик (поверх верхней нашивки, если она есть)
		local patch = find("TopPatch")
		local bx, by = if patch then patch.Cx else 0, if patch then patch.Cy else cy + 0.32 * H
		plate("Badge", 0.42 * s, 0.20 * s, 0.03 * s, bx, by, 0, cfg.Accent, metalMat, 0, { Reflectance = cfg.Shine })
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				disc("BadgeRivet", 0.045 * s, 0.02 * s, bx + sx * 0.18 * s, by + sy * 0.075 * s, cfg.Metal, metalMat, 0.03 * s,
					{ Reflectance = cfg.Shine })
			end
		end
		for _, dy in ipairs({ -0.03, 0.03 }) do
			plate("BadgeLine", 0.24 * s, 0.018 * s, 0.01 * s, bx, by + dy * s, 0, cfg.Accent2, metalMat, 0.03 * s)
		end
	end

	-- 5. «Авангард»: металлические уголки и светящиеся боковые полосы цвета ромба
	features[5] = function()
		local emblem = find("EmblemDiamond")
		local glow: Color3 = if emblem then emblem.Color else cfg.Glow
		local panel = find("BasePanel")
		-- нижние и верхние уголки: вертикальная и горизонтальная планки
		local corners: { { number } } = {}
		local bx = if panel then panel.Ex * 0.88 else 0.36 * W
		local by = math.max(if panel then panel.Cy else cy - 0.30 * H, minY + 0.22 * s)
		table.insert(corners, { -bx, by, 1, 1 })
		table.insert(corners, { bx, by, -1, 1 })
		table.insert(corners, { -0.34 * W, cy + 0.34 * H, 1, -1 })
		table.insert(corners, { 0.34 * W, cy + 0.34 * H, -1, -1 })
		for _, c in ipairs(corners) do
			local x, y, inward, up = c[1], c[2], c[3], c[4]
			plate("CornerGuard", 0.28 * s, 0.06 * s, 0.03 * s, x + inward * 0.11 * s, y - up * 0.12 * s, 0, cfg.Metal, metalMat, 0,
				{ Reflectance = cfg.Shine })
			plate("CornerGuard", 0.06 * s, 0.28 * s, 0.03 * s, x, y + up * 0.0, 0, cfg.Metal, metalMat, 0, { Reflectance = cfg.Shine })
		end
		-- светящиеся боковые полосы
		local first: BasePart? = nil
		for _, sign in ipairs({ -1, 1 }) do
			local pts: { Vector3 } = {}
			local pushes: { number } = {}
			for i = 0, 3 do
				local y = cy + (0.26 - i * 0.17) * H
				local x, push = sideAt(y, cz, sign)
				if x then
					table.insert(pts, Vector3.new(x + sign * 0.02 * s, y, cz))
					table.insert(pushes, push)
				end
			end
			for _, p in ipairs(pathBars("SideGlow", pts, pushes, 0.04 * s, glow, Enum.Material.Neon)) do
				first = first or p
			end
		end
		if first then
			addLight(first :: BasePart, glow)
		end
	end

	-- 6. Шахтёрский ящик: уголки, клёпаные пластины, кристаллы руды, клетка-лампа
	features[6] = function()
		local lx = 0.30 * W
		local corners: { { number } } = {
			{ -0.36 * W, cy + 0.34 * H, 1, 1 }, { 0.36 * W, cy + 0.34 * H, -1, 1 },
			{ -0.36 * W, cy - 0.32 * H, 1, -1 }, { 0.36 * W, cy - 0.32 * H, -1, -1 },
		}
		for _, c in ipairs(corners) do
			local x, y, inward, up = c[1], c[2], c[3], c[4]
			plate("Bracket", 0.28 * s, 0.06 * s, 0.03 * s, x + inward * 0.11 * s, y, 0, cfg.Metal, metalMat, 0, { Reflectance = cfg.Shine })
			plate("Bracket", 0.06 * s, 0.28 * s, 0.03 * s, x, y - up * 0.11 * s, 0, cfg.Metal, metalMat, 0, { Reflectance = cfg.Shine })
		end
		for _, sx in ipairs({ -1, 1 }) do
			local x, y = sx * 0.38 * W, cy + 0.02 * H
			plate("RivetPlate", 0.30 * s, 0.50 * s, 0.03 * s, x, y, 0, cfg.Accent2, metalMat, 0, { Reflectance = cfg.Shine })
			for _, sy in ipairs({ -1, 1 }) do
				disc("PlateRivet", 0.05 * s, 0.02 * s, x, y + sy * 0.20 * s, cfg.Metal, metalMat, 0.03 * s, { Reflectance = cfg.Shine })
			end
		end

		-- кристаллы руды торчат сверху наклонными призмами со скошенной вершиной
		local xs = { -0.04, 0.16, 0.32 }
		for i = 1, math.min(math.floor(cfg.Count), #xs) do
			local x = xs[i] * W
			local z0 = cz + 0.10 * D
			local top, push = topAt(x, z0)
			if top then
				local h = rng:NextNumber(0.34, 0.50) * s
				local frame = CFrame.new(x, top - 0.04 * s, z0)
					* CFrame.Angles(math.rad(rng:NextNumber(-8, 12)), 0, math.rad(rng:NextNumber(-22, 22)))
				local neon = i == 2
				local color = if neon then cfg.Glow2 else cfg.Glow
				local mat = if neon then Enum.Material.Neon else Enum.Material.Glass
				local opts: AddOpts = { Push = push, Transparency = if neon then 0 else 0.25, Reflectance = if neon then 0 else 0.2 }
				put("OreCrystal", Vector3.new(0.17 * s, h, 0.14 * s), frame * CFrame.new(0, h / 2, 0), color, mat, opts)
				put("OreCrystalTip", Vector3.new(0.17 * s, 0.14 * s, 0.14 * s), frame * CFrame.new(0, h + 0.07 * s, 0), color, mat,
					{ Push = push, Wedge = true, Transparency = opts.Transparency, Reflectance = opts.Reflectance })
			end
		end

		-- тяжёлая лампа-клетка: основание, четыре прута, крышка, лампочка и свет
		local lz = cz - 0.05 * D
		local top, lpush = topAt(-lx, lz)
		if top then
			local base = top + 0.02 * s
			put("LampBase", Vector3.new(0.22 * s, 0.05 * s, 0.22 * s), CFrame.new(-lx, base, lz), cfg.Metal, metalMat,
				{ Push = lpush, Reflectance = cfg.Shine })
			for _, ox in ipairs({ -1, 1 }) do
				for _, oz in ipairs({ -1, 1 }) do
					put("LampBar", Vector3.new(0.025 * s, 0.26 * s, 0.025 * s),
						CFrame.new(-lx + ox * 0.085 * s, base + 0.155 * s, lz + oz * 0.085 * s), cfg.Metal, metalMat, { Push = lpush })
				end
			end
			put("LampCap", Vector3.new(0.22 * s, 0.03 * s, 0.22 * s), CFrame.new(-lx, base + 0.30 * s, lz), cfg.Metal, metalMat, { Push = lpush })
			local bulb = ball("LampBulb", 0.15 * s, Vector3.new(-lx, base + 0.15 * s, lz), cfg.Accent, Enum.Material.Neon, lpush)
			if bulb then
				addLight(bulb, cfg.Accent)
			end
		end
	end

	-- 7. «Полярная звезда»: золотые диагональные лучи, наконечники, заклёпки и искорки
	features[7] = function()
		local plateBox = find("StarPlate")
		local ex, ey = if plateBox then plateBox.Cx else 0, if plateBox then plateBox.Cy else cy + 0.12 * H
		local halfX = if plateBox then plateBox.Ex else 0.30 * s
		local halfY = if plateBox then plateBox.Ey else 0.30 * s
		local gold = cfg.Accent
		local R = 0.17 * s
		for _, ang in ipairs({ 45, 135 }) do
			plate("StarRay", R * 2, 0.04 * s, 0.025 * s, ex, ey, math.rad(ang), gold, metalMat, 0.012 * s, { Reflectance = cfg.Shine })
		end
		for _, a in ipairs({ 45, 135, 225, 315 }) do
			local dx, dy = math.cos(math.rad(a)) * R, math.sin(math.rad(a)) * R
			plate("StarTip", 0.07 * s, 0.07 * s, 0.03 * s, ex + dx, ey + dy, math.rad(45), gold, metalMat, 0.012 * s, { Reflectance = cfg.Shine })
		end
		local sx = { -0.8, 0.8 }
		for _, kx in ipairs(sx) do
			for _, ky in ipairs(sx) do
				ball("StarStud", 0.05 * s, (surfPoint(ex + kx * halfX, ey + ky * halfY, 0.02 * s)), gold, metalMat, 0, { Reflectance = cfg.Shine })
			end
		end
		local centerPos, cp = surfPoint(ex, ey, 0.05 * s)
		local core = ball("StarBead", 0.09 * s, centerPos, gold, Enum.Material.Neon, cp)
		if core then
			addLight(core, cfg.Glow)
		end
		-- пара синих «✦» на верхней части корпуса
		for _, side in ipairs({ -1, 1 }) do
			local x, y = side * 0.28 * W, cy + 0.30 * H
			plate("Twinkle", 0.14 * s, 0.025 * s, 0.015 * s, x, y, 0, cfg.Glow, Enum.Material.Neon)
			plate("Twinkle", 0.025 * s, 0.14 * s, 0.015 * s, x, y, 0, cfg.Glow2, Enum.Material.Neon)
		end
	end

	-- 8. Кристальный «Корона»: стеклянные пластины, внутреннее свечение, осколки сверху
	features[8] = function()
		local glassMat = Enum.Material.Glass
		local layout: { { number } } = {
			{ -0.34, 0.14, 0.24, 0.34, 0.45 }, { 0.34, 0.14, 0.24, 0.34, 0.45 },
			{ -0.36, -0.22, 0.22, 0.26, 0.38 }, { 0.36, -0.22, 0.22, 0.26, 0.38 },
		}
		local firstCore: BasePart? = nil
		for i, l in ipairs(layout) do
			local x, y = l[1] * W, cy + l[2] * H
			plate("GlassShell", l[3] * W, l[4] * H, 0.03 * s, x, y, if i % 2 == 0 then 0.10 else -0.10, cfg.Accent, glassMat, 0.02 * s,
				{ Transparency = l[5], Reflectance = cfg.Shine })
			if i <= 2 then
				local pos, push = surfPoint(x, y, 0.035 * s)
				local core = ball("CrystalCore", 0.14 * s, pos, cfg.Glow, Enum.Material.Neon, push)
				if i == 1 then
					firstCore = core
				end
			end
		end
		if firstCore then
			addLight(firstCore :: BasePart, cfg.Glow)
		end
		-- осколки кристалла на верхней грани
		local xs = { -0.30, -0.10, 0.10, 0.30 }
		for i = 1, math.min(math.floor(cfg.Count), #xs) do
			local x = xs[i] * W
			local z0 = cz + 0.05 * D
			local top, push = topAt(x, z0)
			if top then
				local h = rng:NextNumber(0.26, 0.42) * s
				local frame = CFrame.new(x, top - 0.03 * s, z0)
					* CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-20, 20)))
				local color = if i % 2 == 0 then cfg.Glow2 else cfg.Accent
				local opts: AddOpts = { Push = push, Transparency = 0.3, Reflectance = cfg.Shine }
				put("Shard", Vector3.new(0.12 * s, h, 0.10 * s), frame * CFrame.new(0, h / 2, 0), color, glassMat, opts)
				put("ShardTip", Vector3.new(0.12 * s, 0.11 * s, 0.10 * s), frame * CFrame.new(0, h + 0.055 * s, 0), color, glassMat,
					{ Push = push, Wedge = true, Transparency = 0.3, Reflectance = cfg.Shine })
			end
		end
	end

	-- 9. Вулканический: огненные трещины, броневые рёбра, редкие угольки
	features[9] = function()
		local t = 0.035 * s
		local firstBar: BasePart? = nil
		local function crack(startX: number, dir: number, colorA: Color3, colorB: Color3)
			local x, y = startX, cy + 0.30 * H
			local pts: { Vector3 } = {}
			local pushes: { number } = {}
			local function addPoint()
				local p, pp = surfPoint(x, y, t * 0.5)
				table.insert(pts, p)
				table.insert(pushes, pp)
			end
			addPoint()
			for _ = 1, 4 do
				x += dir * rng:NextNumber(-0.05, 0.07) * W
				y -= rng:NextNumber(0.07, 0.11) * H
				addPoint()
			end
			for _, p in ipairs(pathBars("EmberCrack", pts, pushes, t, colorA, Enum.Material.Neon, false, nil, colorB)) do
				firstBar = firstBar or p
			end
			return pts, pushes
		end
		local ptsA, pushA = crack(-0.34 * W, 1, cfg.Glow, cfg.Glow2)
		local ptsB, pushB = crack(0.34 * W, -1, cfg.Glow2, cfg.Glow)
		for i = 1, math.min(math.floor(cfg.Count), 2) do
			local pts, pushes = if i == 1 then ptsA else ptsB, if i == 1 then pushA else pushB
			if #pts >= 3 then
				local from = pts[3]
				local sign = if i == 1 then -1 else 1
				local toPos = surfPoint(from.X + sign * 0.10 * W, from.Y - 0.05 * H, t * 0.5)
				bar("EmberBranch", from, toPos, t * 0.8, cfg.Glow, Enum.Material.Neon, pushes[3])
			end
		end
		-- броневые рёбра по бокам лицевой панели
		for _, sx in ipairs({ -1, 1 }) do
			for k, dy in ipairs({ 0.28, 0.12, -0.04 }) do
				plate("ArmorRib", 0.24 * W, 0.075 * s, 0.035 * s, sx * 0.38 * W, cy + dy * H, sx * (0.06 + 0.02 * k),
					cfg.Cloth, metalMat, 0, { Reflectance = cfg.Shine })
			end
		end
		if firstBar then
			local fb = firstBar :: BasePart
			addLight(fb, cfg.Glow)
			addEmitter(fb, {
				Name = "Embers", Texture = PartKit.TEXTURE_FIRE, Color = cfg.Glow2, Color2 = cfg.Glow,
				Rate = math.min(cfg.EmitRate, 4), Lifetime = NumberRange.new(0.7, 1.2), Speed = NumberRange.new(0.2, 0.6),
				SizeStart = 0.14 * s, SizeEnd = 0, Spread = 40, Acceleration = Vector3.new(0, 0.8, 0), Transparency = 0.2,
				LightEmission = 1,
			})
		end
	end

	-- 10. Звёздный рюкзак: золотая пентаграмма на эмблеме, космические пластины, неоновые «звёзды»
	features[10] = function()
		local emblem = find("QuantumDiamond")
		local ex, ey = if emblem then emblem.Cx else 0, if emblem then emblem.Cy else cy + 0.22 * H
		local R = 0.19 * s
		local t = 0.035 * s
		local pts: { Vector3 } = {}
		local pushes: { number } = {}
		for k = 0, 4 do
			local a = math.rad(72 * k)
			local p, pp = surfPoint(ex + math.sin(a) * R, ey + math.cos(a) * R, t * 0.5 + 0.01 * s)
			table.insert(pts, p)
			table.insert(pushes, pp)
		end
		for k = 1, 5 do
			local a, b = pts[k], pts[(k + 1) % 5 + 1]
			bar("GoldStar", a, b, t, cfg.Accent, metalMat, pushes[k], false, { Reflectance = cfg.Shine * 2 })
		end
		local centerPos, cp = surfPoint(ex, ey, 0.07 * s)
		local bead = ball("StarBead", 0.08 * s, centerPos, cfg.Accent, Enum.Material.Neon, cp)
		if bead then
			addLight(bead, cfg.Accent2)
			addEmitter(bead, {
				Name = "Sparkles", Texture = PartKit.TEXTURE_SPARKLE, Color = cfg.Accent, Color2 = cfg.Glow,
				Rate = math.min(cfg.EmitRate, 6), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(0.3, 0.9),
				SizeStart = 0.18 * s, SizeEnd = 0, Spread = 180, LightEmission = 1,
			})
		end
		-- космические пластины двух оттенков
		local layout: { { number } } = {
			{ -0.36, 0.12, 0.22, 0.30 }, { 0.36, 0.12, 0.22, 0.30 },
			{ -0.36, -0.22, 0.22, 0.24 }, { 0.36, -0.22, 0.22, 0.24 },
		}
		for i, l in ipairs(layout) do
			plate("CosmicPlate", l[3] * W, l[4] * H, 0.03 * s, l[1] * W, cy + l[2] * H, if i % 2 == 0 then 0.08 else -0.08,
				if i % 2 == 0 then cfg.Cloth else cfg.Accent2, metalMat, 0, { Reflectance = cfg.Shine })
		end
		-- мелкие неоновые «звёзды» на пластинах (детерминированный разброс)
		local starColors = { cfg.Glow2, cfg.Glow, cfg.Accent }
		for i = 1, math.floor(cfg.Count) do
			local l = layout[(i - 1) % #layout + 1]
			local x = (l[1] + rng:NextNumber(-0.09, 0.09)) * W
			local y = cy + (l[2] + rng:NextNumber(-0.10, 0.10)) * H
			local pos, push = surfPoint(x, y, 0.03 * s)
			ball("CosmicStar", rng:NextNumber(0.035, 0.055) * s, pos, starColors[(i - 1) % #starColors + 1], Enum.Material.Neon, push)
		end
	end

	-- ------------------------------------------------------------------------
	-- Запуск: сначала особенности уровня, затем общие детали (в остаток лимита)
	-- ------------------------------------------------------------------------
	local feature = features[level]
	if feature then
		feature()
	end

	-- Шов по краю клапана / кармана и нижний шов лицевой панели
	local lid = find("Lid")
	local flap = lid or find("PocketFlap")
	local n = math.max(1, math.floor(shared.StitchPerRow))
	if flap then
		local dyFrac = if lid then -0.80 else -0.55
		local half = span(flap, math.abs(dyFrac))
		local y = flap.Cy + flap.Ey * dyFrac
		stitchRow(flap.Cx - half, y, flap.Cx + half, y, n, cfg.Thread)
	else
		stitchRow(-0.30 * W, cy + 0.05 * H, 0.30 * W, cy + 0.05 * H, n, cfg.Thread)
	end
	stitchRow(-0.30 * W, cy - 0.34 * H, 0.30 * W, cy - 0.34 * H, n, cfg.Thread)

	-- Потёртости: на мягких рюкзаках заплатки светлее/темнее, на технических — тонкие царапины
	local soft = level <= 6
	for i = 1, math.max(0, math.floor(shared.ScuffCount)) do
		local x = rng:NextNumber(-0.36, 0.36) * W
		local y = cy + rng:NextNumber(-0.26, 0.34) * H
		local roll = rng:NextNumber(-0.5, 0.5)
		if soft then
			local color = if i % 2 == 0 then PartKit.Lighten(bodyColor, 0.14) else PartKit.Darken(bodyColor, 0.18)
			plate("Scuff", rng:NextNumber(0.20, 0.32) * s, rng:NextNumber(0.13, 0.20) * s, 0.012 * s, x, y, roll, color, Enum.Material.Fabric)
		else
			plate("Scratch", rng:NextNumber(0.22, 0.36) * s, 0.014 * s, 0.01 * s, x, y, roll, PartKit.Lighten(bodyColor, 0.30), metalMat, 0,
				{ Reflectance = 0.2 })
		end
	end

	-- Якорные кольца у основания плечевых лямок на верхней грани
	for _, x in ipairs(strapXs) do
		local z0 = cz - D * 0.22
		local top, push = topAt(x, z0)
		if top then
			put("TopRing", Vector3.new(0.025 * s, 0.15 * s, 0.15 * s), CFrame.new(x, top + 0.012 * s, z0) * CFrame.Angles(0, 0, math.rad(90)),
				cfg.Metal, metalMat, { Shape = Enum.PartType.Cylinder, Push = push, Reflectance = cfg.Shine })
		end
	end

	-- Кольца с хвостиками ремней и металлическими наконечниками у нижних углов
	for _, sx in ipairs({ -1, 1 }) do
		local x, y = sx * 0.40 * W, cy - 0.20 * H
		disc("Ring", 0.16 * s, 0.03 * s, x, y, cfg.Metal, metalMat, 0, { Reflectance = cfg.Shine })
		plate("Tail", 0.09 * s, 0.26 * s, 0.016 * s, x, y - 0.17 * s, sx * 0.05, cfg.Cloth, Enum.Material.Fabric, 0.02 * s)
		plate("TailTip", 0.10 * s, 0.05 * s, 0.022 * s, x + sx * 0.012 * s, y - 0.31 * s, sx * 0.05, cfg.Metal, metalMat, 0.02 * s,
			{ Reflectance = cfg.Shine })
	end
end

return BackpackDetailer
