--!strict
-- ============================================================================
-- 🌙 МОДУЛЬ: NightWallBuilder (ServerScriptService.Modules.NightWallBuilder)
-- «Большая штука» у входа в шахту: монолит из чёрного базальта с красными рунами,
-- который ночью поднимается из земли и наглухо закрывает проход. Плюс невидимый
-- периметр с видимым красным забором, чтобы карьер нельзя было обойти.
-- Сервер НЕ анимирует стену: SetRaised мгновенно переключает состояние, а плавный
-- подъём/опускание (твин Root.CFrame), пульсацию рун, таймер и звук играет клиент.
-- Все размеры, цвета и тексты — в GameConfig.NIGHT_WALL (config_parts/30_night_wall.lua).
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local PartKit = require(Modules:WaitForChild("PartKit"))

local NightWallBuilder = {}

export type WallRefs = {
	Model: Model,
	Root: BasePart,
	DownCFrame: CFrame,
	UpCFrame: CFrame,
	Blockers: { BasePart },
	FencePanels: { BasePart },
	Emitters: { ParticleEmitter },
	Lights: { Light },
}

local TAG_MODEL = "NightMineWall"
local TAG_RUNE = "NightWallRune"
local TAG_COUNTDOWN = "NightWallCountdown"
local TAG_DUST = "NightWallDust"

-- Токены для защиты от устаревшего применения позы (день→ночь→день за короткое время)
local poseTokens: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- ----------------------------------------------------------------------------
-- Сборка подвижной стены
-- ----------------------------------------------------------------------------

-- Собирает все видимые детали стены в ПОДНЯТОЙ позе и приваривает их к Root
local function buildWall(model: Model, root: BasePart, upCF: CFrame, rng: Random): ({ Light }, { ParticleEmitter })
	local cfg = GameConfig.NIGHT_WALL
	local col = cfg.Colors
	local H = cfg.Height
	local halfH = H / 2
	local lights: { Light } = {}
	local emitters: { ParticleEmitter } = {}

	local folder = Instance.new("Folder")
	folder.Name = "Wall"
	folder.Parent = model

	-- Добавляет деталь: локальный CFrame задан относительно центра стены
	local function add(name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, glow: boolean?): Part
		local p = PartKit.Block(folder, name, size, upCF * localCF, color, material, {
			Anchored = false,
			Massless = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = glow ~= true,
		})
		PartKit.WeldTo(p, root)
		return p
	end

	local function addWedge(name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material): WedgePart
		local p = PartKit.Wedge(folder, name, size, upCF * localCF, color, material, {
			Anchored = false,
			Massless = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		PartKit.WeldTo(p, root)
		return p
	end

	-- Основные размеры слоёв
	local bodyBottom = -halfH + cfg.PlinthHeight
	local bodyTop = halfH - cfg.CapHeight
	local bodyH = bodyTop - bodyBottom
	local bodyMidY = (bodyTop + bodyBottom) / 2
	local plinthMidY = -halfH + cfg.PlinthHeight / 2
	local halfBody = cfg.BodyThickness / 2
	local halfThick = cfg.Thickness / 2
	local buttX = cfg.BodyWidth / 2 + cfg.ButtressWidth / 2 -- центр контрфорса по X

	-- Плита-основание (тяжёлый цоколь) и юбка
	add("Plinth", Vector3.new(cfg.Width, cfg.PlinthHeight, cfg.Thickness), CFrame.new(0, plinthMidY, 0), col.BasaltDark, Enum.Material.Basalt)
	add("Skirt", Vector3.new(cfg.SkirtWidth, cfg.SkirtHeight, cfg.SkirtThickness), CFrame.new(0, -halfH + cfg.SkirtHeight / 2, 0), col.Rock, Enum.Material.Rock)

	-- Углублённые плиты на цоколе (обе стороны)
	for _, s in ipairs({ 1, -1 }) do
		for _, x in ipairs({ -9, 0, 9 }) do
			add("PlinthInset", Vector3.new(6, cfg.PlinthHeight - 1.1, 0.2), CFrame.new(x, plinthMidY + 0.2, s * (halfThick + 0.05)), col.Slate, Enum.Material.Slate)
		end
	end

	-- Сколы-клинья на юбке (обе стороны); у задней стороны клин развёрнут на 180°
	for _, s in ipairs({ 1, -1 }) do
		for _, x in ipairs({ -13.5, -4.5, 4.5, 13.5 }) do
			local yaw = if s == 1 then 0 else math.pi
			addWedge("Chip", Vector3.new(1.2, 0.8, 0.4), CFrame.new(x, -halfH + cfg.SkirtHeight + 0.4 - 0.05, s * (halfThick + 0.2)) * CFrame.Angles(0, yaw + math.rad(rng:NextNumber(-8, 8)), 0), col.Rock, Enum.Material.Rock)
		end
	end

	-- Центральное тело, шапка, контрфорсы
	add("Body", Vector3.new(cfg.BodyWidth, bodyH, cfg.BodyThickness), CFrame.new(0, bodyMidY, 0), col.Basalt, Enum.Material.Basalt)
	add("Cap", Vector3.new(cfg.Width, cfg.CapHeight, cfg.Thickness), CFrame.new(0, halfH - cfg.CapHeight / 2, 0), col.BasaltDark, Enum.Material.Basalt)
	for _, sx in ipairs({ -1, 1 }) do
		add("Buttress", Vector3.new(cfg.ButtressWidth, bodyH, cfg.Thickness), CFrame.new(sx * buttX, bodyMidY, 0), col.Slate, Enum.Material.Slate)
		-- Рёбра между телом и контрфорсом (выступают с обеих сторон)
		add("Rib", Vector3.new(0.9, bodyH, cfg.Thickness + 0.2), CFrame.new(sx * (cfg.BodyWidth / 2 - 0.7), bodyMidY, 0), col.SlateLight, Enum.Material.Slate)
		-- Ступенчатое «крыло» по внешней кромке
		add("Wing", Vector3.new(1.2, bodyH * 0.65, cfg.Thickness + 0.6), CFrame.new(sx * (cfg.Width / 2 - 0.6), bodyBottom + bodyH * 0.325, 0), col.Rock, Enum.Material.Rock)
	end

	-- Панель-основа под надпись и выступающие карнизы выше/ниже неё
	local ph = cfg.PanelSize.Y
	local panelTop = cfg.PanelCenterY + ph / 2
	local panelBottom = cfg.PanelCenterY - ph / 2
	local upperLedgeY = panelTop + 0.2
	local lowerLedgeY = panelBottom - 0.2
	add("LedgeUpper", Vector3.new(cfg.BodyWidth, 0.3, cfg.BodyThickness + 0.5), CFrame.new(0, upperLedgeY, 0), col.SlateLight, Enum.Material.Slate)
	add("LedgeLower", Vector3.new(cfg.BodyWidth, 0.3, cfg.BodyThickness + 0.5), CFrame.new(0, lowerLedgeY, 0), col.SlateLight, Enum.Material.Slate)

	-- Углублённые вставки на контрфорсах (обе стороны)
	for _, s in ipairs({ 1, -1 }) do
		for _, sx in ipairs({ -1, 1 }) do
			add("ButtressInset", Vector3.new(1.8, bodyH - 2.2, 0.2), CFrame.new(sx * (buttX - 0.2), bodyMidY, s * (halfThick + 0.1)), col.BasaltDark, Enum.Material.Slate)
		end
	end

	-- Таблички с SurfaceGui. Нормаль +Z (к спавну) = грань Back, нормаль −Z (к яме) = грань Front.
	local panelZ = halfBody + cfg.PanelThickness / 2
	local panelFront = add("SignPanelFront", Vector3.new(cfg.PanelSize.X, ph, cfg.PanelThickness), CFrame.new(0, cfg.PanelCenterY, panelZ), col.Panel, Enum.Material.SmoothPlastic)
	local panelBack = add("SignPanelBack", Vector3.new(cfg.PanelSize.X, ph, cfg.PanelThickness), CFrame.new(0, cfg.PanelCenterY, -panelZ), col.Panel, Enum.Material.SmoothPlastic)
	NightWallBuilder._BuildSign(panelFront, Enum.NormalId.Back)
	NightWallBuilder._BuildSign(panelBack, Enum.NormalId.Front)

	-- Красные неоновые руны (по 14 деталей на сторону), все с тегом NightWallRune
	local runeZBody = halfBody + 0.1
	local runeZButt = halfThick + 0.25
	local rowTopY = (upperLedgeY + 0.15 + bodyTop) / 2
	local rowBottomY = (bodyBottom + lowerLedgeY - 0.15) / 2
	local lightHosts: { Part } = {}

	local function addRune(s: number, x: number, y: number, w: number, h: number, z: number, diamond: boolean): Part
		local rot = if diamond then CFrame.Angles(0, 0, math.rad(45)) else CFrame.identity
		local p = add("Rune", Vector3.new(w, h, 0.2), CFrame.new(x, y, s * z) * rot, col.Rune, Enum.Material.Neon, true)
		CollectionService:AddTag(p, TAG_RUNE)
		return p
	end

	for _, s in ipairs({ 1, -1 }) do
		-- Верхний ряд: ромбы и вертикальные чёрточки (7)
		local mainDiamond = addRune(s, 0, rowTopY, 0.9, 0.9, runeZBody, true)
		table.insert(lightHosts, mainDiamond)
		addRune(s, -5, rowTopY, 0.6, 0.6, runeZBody, true)
		addRune(s, 5, rowTopY, 0.6, 0.6, runeZBody, true)
		for _, x in ipairs({ -7.6, -2.4, 2.4, 7.6 }) do
			addRune(s, x, rowTopY, 0.22, 1.3, runeZBody, false)
		end
		-- Нижний ряд: длинная планка и два ромба (3)
		local bar = addRune(s, 0, rowBottomY, 7, 0.22, runeZBody, false)
		table.insert(lightHosts, bar)
		addRune(s, -5.5, rowBottomY, 0.55, 0.55, runeZBody, true)
		addRune(s, 5.5, rowBottomY, 0.55, 0.55, runeZBody, true)
		-- Боковые колонны на контрфорсах (по 2 на контрфорс = 4)
		for _, sx in ipairs({ -1, 1 }) do
			addRune(s, sx * buttX, bodyMidY + 1.2, 0.28, 6.5, runeZButt, false)
			addRune(s, sx * buttX, bodyMidY - 4.2, 0.8, 0.8, runeZButt, true)
		end
	end

	-- Красные огни: по одному в центральном ромбе и нижней планке каждой стороны (4)
	local lc = cfg.Light
	for _, host in ipairs(lightHosts) do
		local l = PartKit.PointLight(host, lc.Color, lc.Brightness, lc.Range)
		l.Enabled = false
		table.insert(lights, l)
	end

	-- Шипы по верху: клинья-плавники разной высоты, чередуются по направлению
	local n = cfg.SpikeCount
	local span = cfg.Width - 2.4
	for i = 1, n do
		local x = -span / 2 + (i - 1) * span / (n - 1)
		local centerBoost = 1 - math.abs(x) / (cfg.Width / 2)
		local h = cfg.SpikeMinHeight + (cfg.SpikeMaxHeight - cfg.SpikeMinHeight) * (0.3 + 0.7 * centerBoost) * rng:NextNumber(0.85, 1)
		h = math.min(h, cfg.SpikeMaxHeight)
		local yaw = (if i % 2 == 0 then math.pi else 0) + math.rad(rng:NextNumber(-6, 6))
		local color = PartKit.Lighten(col.Spike, rng:NextNumber(0, 0.12))
		addWedge("Spike", Vector3.new(1.8, h, 2.2), CFrame.new(x, halfH + h / 2 - 0.05, 0) * CFrame.Angles(0, yaw, 0), color, Enum.Material.Basalt)
	end
	-- Боковые «рога» на краях: клинья, повёрнутые вдоль X
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -0.8, 0.8 }) do
			local yaw = sx * math.pi / 2
			addWedge("Horn", Vector3.new(1.1, 2.6, 1.6), CFrame.new(sx * (cfg.Width / 2 - 0.8), halfH + 1.25, sz) * CFrame.Angles(0, yaw, 0), col.Spike, Enum.Material.Basalt)
		end
	end

	-- Невидимые точки дыма по верху стены
	local sm = cfg.Smoke
	for _, x in ipairs({ -9, 0, 9 }) do
		local anchor = PartKit.Block(folder, "SmokeAnchor", Vector3.new(1, 0.2, 1), upCF * CFrame.new(x, halfH + 0.1, 0), col.Spike, Enum.Material.SmoothPlastic, {
			Anchored = false,
			Massless = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 1,
		})
		PartKit.WeldTo(anchor, root)
		local pe = PartKit.Emitter(anchor, {
			Name = "Smoke",
			Texture = PartKit.TEXTURE_SMOKE,
			Color = sm.Color1,
			Color2 = sm.Color2,
			Rate = sm.Rate,
			Lifetime = sm.Lifetime,
			Speed = sm.Speed,
			SizeStart = sm.SizeStart,
			SizeEnd = sm.SizeEnd,
			Spread = 25,
			LightEmission = 0,
			Transparency = sm.Transparency,
			Acceleration = Vector3.new(0, 1, 0),
			Drag = 0.5,
			RotSpeed = NumberRange.new(-20, 20),
			Enabled = false,
		})
		pe.EmissionDirection = Enum.NormalId.Top
		table.insert(emitters, pe)
	end

	return lights, emitters
end

-- Надпись на табличке: фон, красная обводка, 4 строки (третья — таймер с тегом)
function NightWallBuilder._BuildSign(panel: BasePart, face: Enum.NormalId)
	local g = GameConfig.NIGHT_WALL.Gui

	local gui = Instance.new("SurfaceGui")
	gui.Name = "NightSign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = g.PixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = g.Brightness
	gui.AlwaysOnTop = false
	gui.MaxDistance = 600
	gui.ResetOnSpawn = false

	local back = Instance.new("Frame")
	back.Name = "Backdrop"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = g.BackdropColor
	back.BackgroundTransparency = g.BackdropTransparency
	back.BorderSizePixel = 0
	back.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, g.CornerRadius)
	corner.Parent = back

	local stroke = Instance.new("UIStroke")
	stroke.Color = g.StrokeColor
	stroke.Thickness = g.StrokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = back

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(34, 10, 18), Color3.fromRGB(8, 5, 12))
	grad.Parent = back

	-- Создаёт строку надписи с крупным шрифтом и контуром
	local function label(name: string, text: string, color: Color3, y: number, h: number): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.Position = UDim2.fromScale(0.04, y)
		t.Size = UDim2.fromScale(0.92, h)
		t.BackgroundTransparency = 1
		t.Text = text
		t.TextColor3 = color
		t.Font = g.Font
		t.TextScaled = true
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.TextYAlignment = Enum.TextYAlignment.Center
		local ts = Instance.new("UIStroke")
		ts.Color = g.TextStrokeColor
		ts.Thickness = 3
		ts.Parent = t
		t.Parent = back
		return t
	end

	label("Title", g.Title, g.TitleColor, 0.04, 0.27)
	label("Subtitle", g.Subtitle, g.SubtitleColor, 0.31, 0.26)
	local countdown = label("Countdown", g.Countdown, g.CountdownColor, 0.58, 0.21)
	label("Hint", g.Hint, g.HintColor, 0.8, 0.15)
	CollectionService:AddTag(countdown, TAG_COUNTDOWN)

	gui.Parent = panel
end

-- ----------------------------------------------------------------------------
-- Пыль у основания (не приварена, остаётся на уровне земли)
-- ----------------------------------------------------------------------------
local function buildDust(model: Model): { ParticleEmitter }
	local cfg = GameConfig.NIGHT_WALL
	local d = cfg.Dust
	local base = PartKit.Block(model, "DustBase", Vector3.new(cfg.Width, d.Height, cfg.Thickness + 2), CFrame.new(cfg.CenterX, d.Y, cfg.CenterZ), d.Color1, Enum.Material.SmoothPlastic, {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
	})

	-- Три излучателя разного характера: крупные клубы, мелкая быстрая пыль и тёмные облака
	local variants = {
		{ c1 = d.Color1, c2 = d.Color2, s0 = d.SizeStart, s1 = d.SizeEnd, life = d.Lifetime, speed = d.Speed, spread = 55 },
		{ c1 = d.Color2, c2 = d.Color1, s0 = d.SizeStart * 0.5, s1 = d.SizeEnd * 0.55, life = NumberRange.new(1, 1.8), speed = NumberRange.new(8, 14), spread = 70 },
		{ c1 = PartKit.Darken(d.Color2, 0.35), c2 = d.Color2, s0 = d.SizeStart * 1.3, s1 = d.SizeEnd * 1.4, life = NumberRange.new(2.4, 3.6), speed = NumberRange.new(2, 5), spread = 40 },
	}
	local result: { ParticleEmitter } = {}
	for _, v in ipairs(variants) do
		local pe = PartKit.Emitter(base, {
			Name = "Dust",
			Texture = PartKit.TEXTURE_SMOKE,
			Color = v.c1,
			Color2 = v.c2,
			Rate = 0,
			Lifetime = v.life,
			Speed = v.speed,
			SizeStart = v.s0,
			SizeEnd = v.s1,
			Spread = v.spread,
			LightEmission = 0,
			Transparency = d.Transparency,
			Acceleration = Vector3.new(0, 1.5, 0),
			Drag = 2,
			RotSpeed = NumberRange.new(-30, 30),
			Enabled = false,
		})
		pe.Shape = Enum.ParticleEmitterShape.Box
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		pe.EmissionDirection = Enum.NormalId.Top
		CollectionService:AddTag(pe, TAG_DUST)
		table.insert(result, pe)
	end
	return result
end

-- ----------------------------------------------------------------------------
-- Периметр: невидимые блокировщики + красный забор
-- ----------------------------------------------------------------------------
local function buildPerimeter(model: Model): ({ BasePart }, { BasePart })
	local cfg = GameConfig.NIGHT_WALL
	local per = cfg.Perimeter
	local fence = cfg.Fence
	local T = per.Thickness
	local wallTop = GameConfig.WALL_HEIGHT
	local gateX = per.GateHalfWidth
	local sz = cfg.CenterZ

	local blockers: { BasePart } = {}
	local panels: { BasePart } = {}

	local blockerFolder = Instance.new("Folder")
	blockerFolder.Name = "Blockers"
	blockerFolder.Parent = model
	local fenceFolder = Instance.new("Folder")
	fenceFolder.Name = "Fence"
	fenceFolder.Parent = model

	-- Центральный блокировщик в проёме: стена целиком, высота WALL_HEIGHT (не перепрыгнуть)
	local gate = PartKit.Block(blockerFolder, "WallBlocker", Vector3.new(cfg.Width, wallTop, cfg.Thickness), CFrame.new(cfg.CenterX, wallTop / 2, cfg.CenterZ), col_dummy or Color3.new(), Enum.Material.SmoothPlastic, {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
	})
	table.insert(blockers, gate)

	-- Участки кольца: a→b по осям; ext — на сколько удлинить конец, чтобы углы перекрывались
	local legs = {
		{ name = "PerimSouthWest", a = Vector3.new(-gateX, 0, sz), b = Vector3.new(per.WestX, 0, sz), extA = 0, extB = T / 2 },
		{ name = "PerimWest", a = Vector3.new(per.WestX, 0, sz), b = Vector3.new(per.WestX, 0, per.NorthZ), extA = T / 2, extB = T / 2 },
		{ name = "PerimNorth", a = Vector3.new(per.WestX, 0, per.NorthZ), b = Vector3.new(per.EastX, 0, per.NorthZ), extA = T / 2, extB = T / 2 },
		{ name = "PerimEast", a = Vector3.new(per.EastX, 0, per.NorthZ), b = Vector3.new(per.EastX, 0, sz), extA = T / 2, extB = T / 2 },
		{ name = "PerimSouthEast", a = Vector3.new(per.EastX, 0, sz), b = Vector3.new(gateX, 0, sz), extA = T / 2, extB = 0 },
	}

	local capEdge = fence.PostWidth / 2 + 0.2
	for li, leg in ipairs(legs) do
		local len = (leg.b - leg.a).Magnitude
		local dir = (leg.b - leg.a).Unit
		local startP = leg.a - dir * leg.extA
		local stopP = leg.b + dir * leg.extB
		local totalLen = len + leg.extA + leg.extB
		local mid = (startP + stopP) / 2
		local alongX = math.abs(dir.X) > 0.5

		-- Невидимый блокировщик (по умолчанию без коллизии, SetRaised включает)
		local bSize = if alongX then Vector3.new(totalLen, wallTop, T) else Vector3.new(T, wallTop, totalLen)
		local blocker = PartKit.Block(blockerFolder, leg.name, bSize, CFrame.new(mid.X, wallTop / 2, mid.Z), Color3.new(), Enum.Material.SmoothPlastic, {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 1,
		})
		table.insert(blockers, blocker)

		-- Красная энергопанель (днём полностью прозрачна)
		local pSize = if alongX then Vector3.new(totalLen, fence.PanelHeight, fence.PanelThickness) else Vector3.new(fence.PanelThickness, fence.PanelHeight, totalLen)
		local panel = PartKit.Block(fenceFolder, "FencePanel", pSize, CFrame.new(mid.X, fence.PanelHeight / 2, mid.Z), fence.PanelColor, fence.PanelMaterial, {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Transparency = 1,
		})
		table.insert(panels, panel)

		-- Столбы через каждые ~PostSpacing studs; у проёма отступаем от стены
		local count = math.max(1, math.ceil(len / fence.PostSpacing))
		local points: { Vector3 } = {}
		for k = 0, count - 1 do
			local offset = len * k / count
			if li == 1 and k == 0 then
				offset = capEdge
			end
			table.insert(points, leg.a + dir * offset)
		end
		if li == #legs then
			table.insert(points, leg.b - dir * capEdge)
		end
		for _, pt in ipairs(points) do
			local postH = fence.PostHeight
			PartKit.Block(fenceFolder, "FencePost", Vector3.new(fence.PostWidth, postH, fence.PostWidth), CFrame.new(pt.X, postH / 2 - 1, pt.Z), fence.PostColor, Enum.Material.Basalt)
			PartKit.Block(fenceFolder, "FenceCap", fence.CapSize, CFrame.new(pt.X, postH - 1 + fence.CapSize.Y / 2, pt.Z), fence.CapDayColor, Enum.Material.Neon, { CastShadow = false })
		end
	end

	return blockers, panels
end

-- ----------------------------------------------------------------------------
-- Публичный API
-- ----------------------------------------------------------------------------

-- Строит стену, периметр и пыль. Модель возвращается в ОПУЩЕННОЙ позе, всё выключено.
function NightWallBuilder.Build(parent: Instance): WallRefs
	local cfg = GameConfig.NIGHT_WALL
	local rng = Random.new(cfg.Seed)

	local upCF = CFrame.new(cfg.CenterX, cfg.Height / 2, cfg.CenterZ)
	local downCF = upCF - Vector3.new(0, cfg.SinkDepth, 0)

	local model = Instance.new("Model")
	model.Name = cfg.Name

	-- Невидимый корень, к которому приварена вся стена; клиент твинит именно его
	local root = PartKit.Block(model, "Root", Vector3.new(1, 1, 1), upCF, cfg.Colors.Basalt, Enum.Material.SmoothPlastic, {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
	})
	model.PrimaryPart = root

	local lights, emitters = buildWall(model, root, upCF, rng)
	local dust = buildDust(model)
	local blockers, panels = buildPerimeter(model)
	local _ = dust

	-- Только теперь, когда всё приварено, опускаем корень: сборка следует за ним
	root.CFrame = downCF

	model:SetAttribute("Raised", false)
	model:SetAttribute("DownCFrame", downCF)
	model:SetAttribute("UpCFrame", upCF)
	model:SetAttribute("LiftSeconds", cfg.LiftSeconds)
	CollectionService:AddTag(model, TAG_MODEL)
	model.Parent = parent

	return {
		Model = model,
		Root = root,
		DownCFrame = downCF,
		UpCFrame = upCF,
		Blockers = blockers,
		FencePanels = panels,
		Emitters = emitters,
		Lights = lights,
	}
end

-- Мгновенное авторитетное переключение. Коллизия включается сразу, поза Root
-- выставляется после времени анимации (для поздно зашедших игроков).
function NightWallBuilder.SetRaised(refs: WallRefs, raised: boolean)
	local cfg = GameConfig.NIGHT_WALL
	local model = refs.Model
	local changed = model:GetAttribute("Raised") ~= raised

	model:SetAttribute("Raised", raised)

	for _, b in ipairs(refs.Blockers) do
		b.CanCollide = raised
	end
	for _, e in ipairs(refs.Emitters) do
		e.Enabled = raised
	end
	for _, l in ipairs(refs.Lights) do
		l.Enabled = raised
	end
	for _, p in ipairs(refs.FencePanels) do
		p.Transparency = if raised then cfg.Fence.FenceTransparency else 1
	end

	local fenceFolder = model:FindFirstChild("Fence")
	if fenceFolder then
		local capColor = if raised then cfg.Fence.CapNightColor else cfg.Fence.CapDayColor
		for _, child in ipairs(fenceFolder:GetChildren()) do
			if child.Name == "FenceCap" and child:IsA("BasePart") then
				child.Color = capColor
			end
		end
	end

	-- Повторный вызов с тем же значением не трогает уже запланированную позу
	if not changed then
		return
	end

	local token = (poseTokens[model] or 0) + 1
	poseTokens[model] = token
	local target = if raised then refs.UpCFrame else refs.DownCFrame
	local liftSeconds = model:GetAttribute("LiftSeconds")
	local delaySeconds = (if typeof(liftSeconds) == "number" then liftSeconds else cfg.LiftSeconds) + 0.5

	task.delay(delaySeconds, function()
		if poseTokens[model] == token and model.Parent ~= nil then
			refs.Root.CFrame = target
		end
	end)
end

return NightWallBuilder
