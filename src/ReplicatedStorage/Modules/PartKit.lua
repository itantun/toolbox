--!strict
-- ============================================================================
-- 🧱 МОДУЛЬ: PartKit (ReplicatedStorage.Modules.PartKit)
-- Общие помощники процедурной 3D-сборки (v52): блоки, клинья, цилиндры, шары,
-- сварка, свет, частицы и надписи на SurfaceGui. Используется и сервером
-- (рынок, площадь спавна, ночная стена), и клиентом (3D-иконки во ViewportFrame).
-- Никаких внешних ассетов: только Part / WedgePart и встроенные текстуры.
-- ============================================================================

local PartKit = {}

export type Opts = {
	Anchored: boolean?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
	Massless: boolean?,
	Transparency: number?,
	Reflectance: number?,
}

-- Встроенные текстуры частиц Roblox (внешние ассеты не используются)
PartKit.TEXTURE_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
PartKit.TEXTURE_FIRE = "rbxasset://textures/particles/fire_main.dds"
PartKit.TEXTURE_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- Общая настройка детали. По умолчанию деталь — декор: закреплена, без коллизий и касаний.
local function style(p: BasePart, parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, opts: Opts?)
	local o: Opts = opts or {}
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = if o.Anchored == nil then true else o.Anchored
	p.CanCollide = o.CanCollide == true
	p.CanQuery = if o.CanQuery == nil then o.CanCollide == true else o.CanQuery
	p.CanTouch = o.CanTouch == true
	p.CastShadow = if o.CastShadow == nil then true else o.CastShadow
	p.Massless = o.Massless == true
	p.Transparency = o.Transparency or 0
	p.Reflectance = o.Reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
end

-- Прямоугольный блок
function PartKit.Block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, opts: Opts?): Part
	local p = Instance.new("Part")
	style(p, parent, name, size, cf, color, material, opts)
	return p
end

-- Клин (как стандартный WedgePart: высокая вертикальная грань со стороны +Z, скос спускается к -Z)
function PartKit.Wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, opts: Opts?): WedgePart
	local p = Instance.new("WedgePart")
	style(p, parent, name, size, cf, color, material, opts)
	return p
end

-- Цилиндр, ось которого направлена вдоль локальной оси Y переданного CFrame
-- (у стандартного цилиндра ось идёт по X — здесь поворот уже учтён).
function PartKit.Cylinder(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, material: Enum.Material, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	style(p, parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, opts)
	return p
end

-- Шар
function PartKit.Ball(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, material: Enum.Material, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	style(p, parent, name, Vector3.new(diameter, diameter, diameter), cf, color, material, opts)
	return p
end

-- Эллипсоид (шар, растянутый по осям через SpecialMesh)
function PartKit.Ellipsoid(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, opts: Opts?): Part
	local p = Instance.new("Part")
	style(p, parent, name, size, cf, color, material, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Жёсткая сварка детали с корневой деталью (WeldConstraint хранится в привариваемой детали)
function PartKit.WeldTo(part: BasePart, root: BasePart): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = part
	w.Parent = part
	return w
end

-- Приварить все детали контейнера к корню и снять с них закрепление (корень остаётся как есть)
function PartKit.WeldAll(container: Instance, root: BasePart)
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			PartKit.WeldTo(d, root)
			d.Anchored = false
		end
	end
end

function PartKit.PointLight(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
	return l
end

function PartKit.SpotLight(parent: Instance, color: Color3, brightness: number, range: number, angle: number, face: Enum.NormalId): SpotLight
	local l = Instance.new("SpotLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Angle = angle
	l.Face = face
	l.Shadows = false
	l.Parent = parent
	return l
end

export type EmitterProps = {
	Name: string?,
	Texture: string?,
	Color: Color3?,
	Color2: Color3?,
	Rate: number?,
	Lifetime: NumberRange?,
	Speed: NumberRange?,
	SizeStart: number?,
	SizeEnd: number?,
	Spread: number?,
	LightEmission: number?,
	Transparency: number?,
	Acceleration: Vector3?,
	Drag: number?,
	RotSpeed: NumberRange?,
	Enabled: boolean?,
	ZOffset: number?,
}

-- Излучатель частиц на встроенной текстуре (по умолчанию — блёстки sparkles_main.dds)
function PartKit.Emitter(parent: Instance, props: EmitterProps): ParticleEmitter
	local c1 = props.Color or Color3.new(1, 1, 1)
	local c2 = props.Color2 or c1
	local pe = Instance.new("ParticleEmitter")
	pe.Name = props.Name or "Sparkles"
	pe.Texture = props.Texture or PartKit.TEXTURE_SPARKLE
	pe.Color = ColorSequence.new(c1, c2)
	pe.LightEmission = props.LightEmission or 1
	pe.Rate = props.Rate or 6
	pe.Lifetime = props.Lifetime or NumberRange.new(0.6, 1.1)
	pe.Speed = props.Speed or NumberRange.new(0.5, 1.5)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, props.SizeStart or 0.25),
		NumberSequenceKeypoint.new(1, props.SizeEnd or 0),
	})
	local t = props.Transparency or 0
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, t),
		NumberSequenceKeypoint.new(0.7, t),
		NumberSequenceKeypoint.new(1, 1),
	})
	local spread = props.Spread or 180
	pe.SpreadAngle = Vector2.new(spread, spread)
	pe.Acceleration = props.Acceleration or Vector3.zero
	pe.Drag = props.Drag or 0
	pe.RotSpeed = props.RotSpeed or NumberRange.new(-90, 90)
	pe.Rotation = NumberRange.new(0, 360)
	pe.ZOffset = props.ZOffset or 0
	pe.Enabled = if props.Enabled == nil then true else props.Enabled
	pe.Parent = parent
	return pe
end

export type LabelProps = {
	PixelsPerStud: number?,
	Font: Enum.Font?,
	TextColor: Color3?,
	StrokeColor: Color3?,
	StrokeThickness: number?,
	Brightness: number?,
	Name: string?,
}

-- Надпись на грани детали (SurfaceGui + TextLabel на всю грань). Возвращает оба объекта.
function PartKit.SurfaceLabel(part: BasePart, face: Enum.NormalId, text: string, props: LabelProps?): (SurfaceGui, TextLabel)
	local o: LabelProps = props or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.Name or "LabelGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.PixelsPerStud or 40
	gui.LightInfluence = 0
	gui.Brightness = o.Brightness or 1
	gui.Parent = part

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = o.Font or Enum.Font.GothamBlack -- поддерживает кириллицу
	lbl.TextScaled = true
	lbl.Text = text
	lbl.TextColor3 = o.TextColor or Color3.new(1, 1, 1)
	lbl.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = o.StrokeThickness or 3
	stroke.Color = o.StrokeColor or Color3.fromRGB(20, 14, 10)
	stroke.Parent = lbl
	return gui, lbl
end

function PartKit.Lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

function PartKit.Darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

return PartKit
