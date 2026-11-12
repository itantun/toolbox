--!strict
-- ============================================================================
-- ✨ МОДУЛЬ: PickaxeJuice (ReplicatedStorage.Modules.PickaxeJuice)
-- v52: «сочная» отделка кирки поверх готовой геометрии EquipmentBuilder:
--   • неоновая полоса вдоль лезвия (видна с обеих сторон);
--   • светящийся кристалл в центре головы + PointLight малого радиуса;
--   • постоянные блёстки (sparkles_main.dds, LightEmission = 1) цвета уровня;
--   • шлейф (Trail) между краями лезвия — включается клиентом на время взмаха;
--   • излучатель искр удара (клиент вызывает :Emit, новые объекты не создаются);
--   • топовые уровни: метка FxEpic для пульсации свечения и тяжёлые частицы.
-- Все цвета и сила эффектов — GameConfig.PICKAXE_FX / PICKAXE_SWING_FX.
-- ============================================================================

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local PartKit = require(script.Parent:WaitForChild("PartKit"))

local PickaxeJuice = {}

export type JuiceContext = {
	Container: Instance,        -- модель кирки
	Level: number,              -- уровень кирки 1..10
	Scale: number,              -- общий масштаб кирки (в руке 0.65)
	HeadScale: number,          -- масштаб головы по уровню
	HeadY: number,              -- локальный Y центра головы
	Beads: { { number } },      -- профиль лезвия: { x, y, уголDeg, толщина, высота, длина }
	SocketDepth: number,        -- глубина втулки по Z (до масштаба)
	Socket: BasePart,           -- втулка головы (центр эффектов)
	Place: (p: BasePart, localCF: CFrame) -> (), -- ставит деталь в систему кирки и регистрирует сварку
	ForViewport: boolean,       -- превью в магазине: свет и частицы не нужны (они там не рисуются)
	LowDetail: boolean,
}

-- Размер блёсток в конфиге задан для кирки в руке (масштаб 0.65)
local HAND_SCALE = 0.65
-- Смещение центра втулки относительно центра головы (из PICK_SHAPES.Socket), до масштаба головы
local SOCKET_CENTER_Y = 0.0468

function PickaxeJuice.Decorate(ctx: JuiceContext)
	local fx = GameConfig.GetPickaxeFx(ctx.Level)
	local k, hs, headY = ctx.Scale, ctx.HeadScale, ctx.HeadY
	local beads = ctx.Beads
	local n = #beads
	if n < 4 then
		return
	end
	local sizeMul = k / HAND_SCALE

	local function deco(name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, transparency: number?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.Transparency = transparency or 0
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = ctx.Container
		ctx.Place(p, localCF)
		return p
	end

	-- 1) Неоновая полоса: сегменты вдоль осевой линии лезвия, чуть толще самого лезвия
	local first = 2
	while first < n and beads[first][1] < 0.46 do
		first += 1
	end
	local step = ctx.LowDetail and 7 or 4
	local rootHeight = beads[1][5]
	for _, side in ipairs({ -1, 1 }) do
		local i = first
		while i < n - 1 do
			local j = math.min(i + step, n - 1)
			local a, b = beads[i], beads[j]
			local cx = (a[1] + b[1]) / 2 * hs
			local cy = (a[2] + b[2]) / 2 * hs
			local ang = math.rad((a[3] + b[3]) / 2)
			local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) * hs * 1.1
			local thick = math.max(a[4], b[4]) * hs + 0.06
			local height = math.max(0.045, 0.13 * hs * (a[5] + b[5]) / (2 * rootHeight))
			deco(
				"NeonStrip",
				Vector3.new(thick, height, len) * k,
				CFrame.fromMatrix(
					Vector3.new(side * cx, headY + cy, 0) * k,
					Vector3.new(0, 0, 1),
					Vector3.new(side * math.sin(ang), math.cos(ang), 0)
				),
				fx.Neon,
				Enum.Material.Neon
			)
			i = j
		end
	end

	-- 2) Кристалл-сердечник: ромб, проходящий сквозь втулку, и яркая сердцевина
	local coreY = (headY + SOCKET_CENTER_Y * hs) * k
	local coreSize = (0.30 + 0.018 * ctx.Level) * hs
	local coreDepth = ctx.SocketDepth * hs + 0.16
	local core = deco(
		"CrystalCore",
		Vector3.new(coreSize, coreSize, coreDepth) * k,
		CFrame.new(0, coreY, 0) * CFrame.Angles(0, 0, math.rad(45)),
		fx.Core,
		Enum.Material.Neon
	)
	core:SetAttribute("BaseColor", fx.Core)
	deco(
		"CrystalHeart",
		Vector3.new(coreSize * 0.45, coreSize * 0.45, coreDepth + 0.07) * k,
		CFrame.new(0, coreY, 0) * CFrame.Angles(0, 0, math.rad(45)),
		PartKit.Lighten(fx.Core, 0.65),
		Enum.Material.Neon
	)

	ctx.Container:SetAttribute("FxEpic", fx.Epic)
	ctx.Container:SetAttribute("FxNeon", fx.Neon)

	-- В ViewportFrame свет, частицы и шлейфы не рисуются — не создаём их зря
	if ctx.ForViewport then
		return
	end

	-- 3) PointLight малого радиуса
	local light = PartKit.PointLight(core, fx.Core:Lerp(fx.Neon, 0.5), fx.LightBrightness, fx.LightRange * math.max(0.6, k))
	light.Name = "CoreLight"
	light:SetAttribute("BaseBrightness", fx.LightBrightness)

	-- 4) Постоянные блёстки по всей голове: невидимая зона вдоль лезвия
	local tip = beads[n]
	local zone = deco(
		"SparkleZone",
		Vector3.new(tip[1] * 2 * hs, 0.7 * hs, 0.3) * k,
		CFrame.new(0, (headY + tip[2] * 0.4 * hs) * k, 0),
		fx.Neon,
		Enum.Material.SmoothPlastic,
		1
	)
	PartKit.Emitter(zone, {
		Name = "TierSparkles",
		Color = PartKit.Lighten(fx.Neon, 0.4),
		Color2 = fx.Core,
		Rate = fx.SparkleRate,
		SizeStart = fx.SparkleSize * sizeMul,
		Lifetime = NumberRange.new(0.5, 1.0),
		Speed = NumberRange.new(0.4, 1.4),
		Spread = 180,
	})
	if fx.Epic then
		-- Топовые уровни: редкие крупные «звёзды» и (для 10 уровня) язычки огня у кристалла
		PartKit.Emitter(zone, {
			Name = "EpicGlints",
			Color = Color3.new(1, 1, 1),
			Color2 = fx.Neon,
			Rate = 3,
			SizeStart = 0.6 * sizeMul,
			Lifetime = NumberRange.new(0.7, 1.2),
			Speed = NumberRange.new(0.1, 0.5),
			RotSpeed = NumberRange.new(-200, 200),
		})
		if ctx.Level >= GameConfig.MAX_PICKAXE_LEVEL then
			PartKit.Emitter(core, {
				Name = "RoyalFlame",
				Texture = PartKit.TEXTURE_FIRE,
				Color = fx.Neon,
				Color2 = fx.Core,
				Rate = 8,
				SizeStart = 0.55 * sizeMul,
				Lifetime = NumberRange.new(0.35, 0.6),
				Speed = NumberRange.new(0.8, 1.6),
				Spread = 25,
				Acceleration = Vector3.new(0, 2.5, 0),
			})
		end
	end

	-- 5) Искры удара: выключенный излучатель, клиент красит его в цвет руды и вызывает :Emit
	local sparks = PartKit.Emitter(core, {
		Name = "ImpactSparks",
		Color = fx.Neon,
		Rate = 0,
		SizeStart = 0.34 * sizeMul,
		Lifetime = NumberRange.new(0.22, 0.45),
		Speed = NumberRange.new(7, 15),
		Spread = 75,
		Acceleration = Vector3.new(0, -28, 0),
		Drag = 3,
		Enabled = false,
	})
	sparks:SetAttribute("BaseEnabled", false)

	-- 6) Шлейф между краями лезвия (точки крепления — в системе втулки, она без поворота)
	local idx = math.clamp(math.floor(n * fx.TrailWidth + 0.5), 2, n)
	local edge = beads[idx]
	local function tipAttachment(name: string, side: number): Attachment
		local att = Instance.new("Attachment")
		att.Name = name
		att.Position = Vector3.new(side * edge[1] * hs, (edge[2] - SOCKET_CENTER_Y) * hs, 0) * k
		att.Parent = ctx.Socket
		return att
	end
	local swing = GameConfig.PICKAXE_SWING_FX
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = tipAttachment("TipL", -1)
	trail.Attachment1 = tipAttachment("TipR", 1)
	trail.Color = ColorSequence.new(PartKit.Lighten(fx.Neon, 0.3), fx.Core)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = swing.TrailLifetime
	trail.MinLength = 0.03
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = false
	trail.Enabled = false
	trail:SetAttribute("BaseEnabled", false)
	trail.Parent = ctx.Socket
end

return PickaxeJuice
