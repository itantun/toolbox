--!strict
-- ============================================================================
-- 🔨 МОДУЛЬ: EquipmentManager (ReplicatedStorage.Modules.EquipmentBuilder &
--            ServerScriptService.Modules.EquipmentManager)
-- Версия: v13.0 — Выполняет Пункты №1, №5, №9 и №11:
-- 1) 10 уровней 3D-кирок (1..10 ур.) с креплением к правой кисти через Motor6D
--    (PickaxeMotor) и полной синхронизацией с анимацией правой руки R15/R6.
-- 2) 10 уровней 3D-рюкзаков (1..10 ур.) строго по референсу «От классики до киберпанка»:
--    • Ур. 1: Холщовый с клапаном и пряжкой
--    • Ур. 2: Кожаный со спальной скаткой сверху
--    • Ур. 3: Оливковый полевой со скаткой и двойными ремнями
--    • Ур. 4: Чёрный городской кофр со стальным шильдиком
--    • Ур. 5: Синий «Авангард» со светящимся белым ромбом
--    • Ур. 6: Бронированный тактический с подсумками MOLLE
--    • Ур. 7: Белый кибер-корпус «Полярная Звезда» с голубой 4-лучевой звездой
--    • Ур. 8: Тёмно-фиолетовый «Корона» с неоновыми контурами и короной
--    • Ур. 9: Вулканический экзо-ранец с багровыми магмовыми каналами
--    • Ур. 10: Квантовый кибер-ранец с 4 светящимися голубыми крыльями-кристаллами
-- 3) 3D Оранжевая шахтёрская каска (MinerHardHat) по референсу (рёбра жёсткости,
--    козырёк, боковые пазы, внутренняя подвеска и налобный фонарик), автоматически
--    надеваемая при входе в шахту и снимаемая на поверхности!
-- 4) Поддержка рендера в 3D ViewportFrame магазина (BuildShowcaseModelForViewport).
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local PickaxeJuice = require(script.Parent:WaitForChild("PickaxeJuice"))
local BackpackDetailer = require(script.Parent:WaitForChild("BackpackDetailer"))

local EquipmentManager = {}

local FxRemote: RemoteEvent? = nil

-- v29: кирка в точности по референсу: гладкое лезвие без срезов, рукоять, втулка и колпачок
-- со скошенными рёбрами. 1 px референса = 0.0104 stud; все Y в таблицах — от центра головы HeadY.
local PICK = {
	HeadY = 1.78,
	GripY = -1.55,
	RestTiltDeg = 25,
}

-- Лезвие — цепочка перекрывающихся вытянутых эллипсоидов, вписанных в силуэт референса
-- (гладкая поверхность вместо плоских срезанных сегментов).
-- { x, y, уголГрад, толщина Z, высота, длина } — правое плечо (левое зеркально); угол > 0 — вниз к острию.
local PICK_BEADS: { { number } } = {
	{ 0.1872, 0.0726, 0.56, 0.5881, 0.6203, 1.8607 },
	{ 0.2843, 0.07, 0.56, 0.5813, 0.5976, 1.7926 },
	{ 0.3814, 0.0673, 0.56, 0.5679, 0.5764, 1.7292 },
	{ 0.4761, 0.0608, 1.34, 0.5589, 0.5533, 1.6598 },
	{ 0.565, 0.055, 2.92, 0.5538, 0.5356, 1.6067 },
	{ 0.6506, 0.0467, 4.77, 0.5515, 0.5217, 1.5649 },
	{ 0.7343, 0.0357, 6.76, 0.5507, 0.5075, 1.5226 },
	{ 0.8167, 0.0244, 8.78, 0.5487, 0.4961, 1.4881 },
	{ 0.8977, 0.0105, 10.75, 0.5417, 0.4824, 1.4471 },
	{ 0.9773, -0.0059, 12.62, 0.5302, 0.4684, 1.4052 },
	{ 1.0553, -0.0246, 14.35, 0.5167, 0.4535, 1.3605 },
	{ 1.1313, -0.0453, 15.94, 0.5026, 0.4361, 1.3083 },
	{ 1.2053, -0.0648, 17.4, 0.4888, 0.4185, 1.2556 },
	{ 1.2769, -0.0882, 18.73, 0.4756, 0.4011, 1.2035 },
	{ 1.3462, -0.1151, 19.98, 0.4632, 0.3833, 1.15 },
	{ 1.4132, -0.1403, 21.18, 0.4515, 0.3651, 1.0954 },
	{ 1.4777, -0.1687, 22.37, 0.4402, 0.345, 1.0349 },
	{ 1.54, -0.1977, 23.56, 0.4291, 0.3236, 0.9709 },
	{ 1.6, -0.2272, 24.8, 0.4174, 0.302, 0.9062 },
	{ 1.6578, -0.2573, 26.11, 0.404, 0.2799, 0.8395 },
	{ 1.7131, -0.2853, 27.49, 0.388, 0.2567, 0.77 },
	{ 1.766, -0.3163, 28.95, 0.3669, 0.2351, 0.7053 },
	{ 1.8162, -0.3449, 30.48, 0.3408, 0.2122, 0.6364 },
	{ 1.8635, -0.3736, 32.06, 0.3096, 0.1898, 0.5694 },
	{ 1.9077, -0.3995, 33.67, 0.2766, 0.167, 0.5012 },
	{ 1.9482, -0.4247, 35.26, 0.2427, 0.1453, 0.436 },
	{ 1.9852, -0.449, 36.81, 0.21, 0.1245, 0.3735 },
	{ 2.0181, -0.4691, 38.26, 0.181, 0.1042, 0.3126 },
	{ 2.047, -0.4898, 39.59, 0.1515, 0.087, 0.2611 },
	{ 2.072, -0.5084, 40.77, 0.1253, 0.0717, 0.2149 },
	{ 2.0931, -0.5244, 41.8, 0.1029, 0.058, 0.174 },
	{ 2.1108, -0.5377, 42.68, 0.0841, 0.0461, 0.1383 },
	{ 2.1252, -0.5512, 43.4, 0.0682, 0.0362, 0.1087 },
	{ 2.1377, -0.5606, 44.04, 0.0515, 0.0286, 0.0858 },
	{ 2.1502, -0.5701, 44.68, 0.0384, 0.0192, 0.0577 },
}

-- Призмы вдоль Y: { верхY, низY, ширина X, глубина Z, фаска рёбер }; пластины без фаски — 4 числа.
local PICK_SHAPES: { [string]: { number } } = {
	Handle = { 0.4836, -3.5724, 0.4784, 0.4368, 0.1404 },
	HandleFlare = { -3.4684, -4.134, 0.52, 0.468, 0.1508 },
	HandleTip = { -4.134, -4.1964, 0.3536, 0.312 },
	Socket = { 0.3484, -0.2548, 0.6864, 0.7904, 0.0728 },
	SocketBand = { -0.2444, -0.4108, 0.6656, 0.7696, 0.0832 },
	SocketRim = { 0.4316, 0.338, 0.6032, 0.7072 },
	Cap = { 0.5252, 0.4212, 0.572, 0.52, 0.104 },
	CapTop = { 0.5564, 0.5148, 0.4576, 0.416 },
}

local function getMeshTemplate(name: string): MeshPart?
	local assets = ReplicatedStorage:FindFirstChild(GameConfig.MESH_ASSETS_FOLDER)
	local meshes = assets and assets:FindFirstChild("Meshes")
	local found = meshes and meshes:FindFirstChild(name)
	if not found then return nil end
	if found:IsA("MeshPart") then return found end
	return found:FindFirstChildWhichIsA("MeshPart", true)
end

local function styleBase(p: BasePart, name: string, size: Vector3, color: Color3, mat: Enum.Material, reflectance: number?)
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat
	p.Reflectance = reflectance or 0
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function newPart(parent: Instance, name: string, size: Vector3, color: Color3, mat: Enum.Material, reflectance: number?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	if shape then p.Shape = shape end
	styleBase(p, name, size, color, mat, reflectance)
	p.Parent = parent
	return p
end

local function newWedge(parent: Instance, name: string, size: Vector3, color: Color3, mat: Enum.Material, reflectance: number?): WedgePart
	local w = Instance.new("WedgePart")
	styleBase(w, name, size, color, mat, reflectance)
	w.Parent = parent
	return w
end

local function newRoundedBox(parent: Instance, name: string, size: Vector3, color: Color3, mat: Enum.Material, reflectance: number?): BasePart
	local tpl = getMeshTemplate("RoundedBox")
	if tpl then
		local m = tpl:Clone()
		styleBase(m, name, size, color, mat, reflectance)
		m.Parent = parent
		return m
	end
	return newPart(parent, name, size, color, mat, reflectance)
end

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

local function getPickTierCfg(level: number)
	local cl = math.clamp(math.floor(level), 1, GameConfig.MAX_PICKAXE_LEVEL)
	return GameConfig.PICKAXE_TIERS[cl] or GameConfig.PICKAXE_TIERS[1]
end

export type PickaxeBuildOptions = { Scale: number?, LowDetail: boolean?, ForViewport: boolean? }

-- ============================================================================
-- 1. СБОРКА 3D-КИРКИ (УРОВНИ 1–10)
-- ============================================================================
function EquipmentManager.BuildModernPickaxeParts(
	container: Instance,
	level: number,
	baseCFrame: CFrame,
	anchored: boolean,
	opts: PickaxeBuildOptions?
): (BasePart, CFrame)
	local o: PickaxeBuildOptions = opts or {}
	local k = o.Scale or 1
	local low = o.LowDetail == true
	local forVp = o.ForViewport == true
	local cfg = getPickTierCfg(level)
	local tierLvl = math.clamp(math.floor(level), 1, GameConfig.MAX_PICKAXE_LEVEL)
	local hs = cfg.HeadScale
	local headY = PICK.HeadY

	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * k, y * k, z * k)
	end
	local function sz(x: number, y: number, z: number): Vector3
		return Vector3.new(x * k, y * k, z * k)
	end

	local placed: { BasePart } = {}
	local function place(p: BasePart, localCF: CFrame)
		p.CFrame = baseCFrame * localCF
		p.Anchored = anchored
		table.insert(placed, p)
	end

	-- Восьмигранная призма вдоль Y (брусок со скошенными продольными рёбрами, как на референсе):
	-- основной брусок + поперечный брусок + 4 клина на рёбрах; s — масштаб вокруг центра головы.
	local function prism(name: string, d: { number }, s: number, color: Color3, mat: Enum.Material, refl: number): BasePart
		local yTop, yBot = d[1] * s, d[2] * s
		local w, dz, ch = d[3] * s, d[4] * s, d[5] * s
		local yc = headY + (yTop + yBot) / 2
		local h = yTop - yBot
		local core = newPart(container, name, sz(w, h, dz - 2 * ch), color, mat, refl)
		place(core, at(0, yc, 0))
		local cross = newPart(container, name .. "Cross", sz(w - 2 * ch, h - 0.004, dz), color, mat, refl)
		place(cross, at(0, yc, 0))
		for _, qx in ipairs({ -1, 1 }) do
			for _, qz in ipairs({ -1, 1 }) do
				local edge = newWedge(container, name .. "Edge", sz(h, ch, ch), color, mat, refl)
				place(edge, CFrame.fromMatrix(
					Vector3.new(qx * (w - ch) / 2, yc, qz * (dz - ch) / 2) * k,
					Vector3.new(0, qx * qz, 0),
					Vector3.new(qx, 0, 0),
					Vector3.new(0, 0, -qz)
				))
			end
		end
		return core
	end

	local function slab(name: string, d: { number }, s: number, color: Color3, mat: Enum.Material, refl: number): BasePart
		local yTop, yBot = d[1] * s, d[2] * s
		local p = newPart(container, name, sz(d[3] * s, yTop - yBot, d[4] * s), color, mat, refl)
		place(p, at(0, headY + (yTop + yBot) / 2, 0))
		return p
	end

	-- Рукоять: восьмигранный брусок, книзу расширение и торец.
	local wood, woodMat = cfg.HandleColor, cfg.HandleMaterial
	local hd = PICK_SHAPES.Handle
	local handle = prism("Handle", hd, 1, wood, woodMat, 0.04)
	local handleLocal = at(0, headY + (hd[1] + hd[2]) / 2, 0)
	prism("HandleFlare", PICK_SHAPES.HandleFlare, 1, wood, woodMat, 0.04)
	slab("HandleEnd", PICK_SHAPES.HandleTip, 1, darken(wood, 0.15), woodMat, 0.04)

	-- Навершие (втулка, обод, колпачок, лезвие) масштабируется по тиру вокруг центра головы.
	local socket = prism("HeadCollar", PICK_SHAPES.Socket, hs, cfg.TrimColor, cfg.TrimMaterial, 0.15)
	prism("HeadBand", PICK_SHAPES.SocketBand, hs, darken(cfg.TrimColor, 0.3), cfg.TrimMaterial, 0.15)
	slab("HeadRim", PICK_SHAPES.SocketRim, hs, darken(cfg.TrimColor, 0.18), cfg.TrimMaterial, 0.15)
	prism("HeadCap", PICK_SHAPES.Cap, hs, lighten(wood, 0.06), woodMat, 0.04)
	slab("HeadCapTop", PICK_SHAPES.CapTop, hs, lighten(wood, 0.1), woodMat, 0.04)

	-- Лезвие: гладкое, из перекрывающихся эллипсоидов (вписаны в силуэт референса, без срезов).
	local nBeads = #PICK_BEADS
	for _, side in ipairs({ -1, 1 }) do
		for i, b in ipairs(PICK_BEADS) do
			if not low or i % 2 == 1 or i == nBeads then
				local a = math.rad(b[3])
				local bead = newPart(container, "Blade", sz(b[4] * hs, b[5] * hs, b[6] * hs), cfg.BladeColor, cfg.HeadMaterial, cfg.HeadReflectance)
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = bead
				place(bead, CFrame.fromMatrix(
					Vector3.new(side * b[1] * hs, headY + b[2] * hs, 0) * k,
					Vector3.new(0, 0, 1),
					Vector3.new(side * math.sin(a), math.cos(a), 0)
				))
			end
		end
	end

	-- v52: «сочная» отделка кирки — неоновая полоса на лезвии, светящийся кристалл, PointLight,
	-- блёстки и шлейф взмаха. Цвета и сила эффектов по уровням — GameConfig.PICKAXE_FX.
	local okJuice, errJuice = pcall(PickaxeJuice.Decorate, {
		Container = container,
		Level = tierLvl,
		Scale = k,
		HeadScale = hs,
		HeadY = headY,
		Beads = PICK_BEADS,
		SocketDepth = PICK_SHAPES.Socket[4],
		Socket = socket,
		Place = place,
		ForViewport = forVp,
		LowDetail = low,
	})
	if not okJuice then
		warn("[EquipmentBuilder] PickaxeJuice: " .. tostring(errJuice))
	end

	if not anchored then
		for _, p in ipairs(placed) do
			if p ~= handle then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = handle
				wc.Part1 = p
				wc.Parent = p
			end
		end
	end

	if container:IsA("Model") then
		container:SetAttribute("HeadOffset", handleLocal:Inverse() * at(0, headY, 0))
		container:SetAttribute("PickaxeTier", cfg.Level)
		container:SetAttribute("SwingAnimSpeed", cfg.SwingAnimSpeed or 1.0)
	end

	return handle, handleLocal
end

-- ============================================================================
-- 2. ЭКИПИРОВКА КИРКИ В ПРАВУЮ РУКУ (R15 И R6) С ЖЁСТКОЙ ПРИВЯЗКОЙ MOTOR6D
-- ============================================================================
function EquipmentManager.EquipPickaxe(character: Model, level: number)
	local PICK_HAND_SCALE = 0.65 -- v30: smaller pickaxe in hand
	if not character then return end

	for _, child in ipairs(character:GetChildren()) do
		if child.Name == "VisualPickaxe" or (child:IsA("Tool") and child:GetAttribute("IsMinerPickaxe")) then
			child:Destroy()
		end
	end

	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
	if not hand or not hand:IsA("BasePart") then return end
	local oldMotor = hand:FindFirstChild("PickaxeMotor")
	if oldMotor then oldMotor:Destroy() end

	local cfg = getPickTierCfg(level)

	local model = Instance.new("Model")
	model.Name = "VisualPickaxe"

	local gripAtt = hand:FindFirstChild("RightGripAttachment")
	local gripPos: Vector3
	if gripAtt and gripAtt:IsA("Attachment") then
		gripPos = gripAtt.Position
	elseif hand.Name == "Right Arm" then
		gripPos = Vector3.new(0, -1, 0)
	else
		gripPos = Vector3.new(0, -0.15, 0)
	end

	local pickToHand = CFrame.new(gripPos)
		* CFrame.Angles(math.rad(PICK.RestTiltDeg), 0, 0)
		* CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, -1))
		* CFrame.new(0, -PICK.GripY * PICK_HAND_SCALE, 0)

	local pickSpace = hand.CFrame * pickToHand
	local handle, handleLocal = EquipmentManager.BuildModernPickaxeParts(model, cfg.Level, pickSpace, false, { Scale = PICK_HAND_SCALE })
	model.PrimaryPart = handle
	model.Parent = character

	local motor = Instance.new("Motor6D")
	motor.Name = "PickaxeMotor"
	motor.Part0 = hand
	motor.Part1 = handle
	motor.C0 = pickToHand * handleLocal
	motor.C1 = CFrame.identity
	motor:SetAttribute("BaseC0", motor.C0)
	motor:SetAttribute("GripPos", gripPos)
	motor:SetAttribute("SwingAnimSpeed", cfg.SwingAnimSpeed or 1.0)
	motor.Parent = hand
	-- v35: the pickaxe is only visible inside the mine zone
	EquipmentManager.SetPickaxeVisible(character, character:GetAttribute("InMineZone") == true)
end

-- v35: show / hide the pickaxe in hand (hidden on the surface, shown in the mine)
function EquipmentManager.SetPickaxeVisible(character: Model?, visible: boolean)
	if not character then return end
	if character:GetAttribute("PickaxeHidden") ~= (not visible) then
		character:SetAttribute("PickaxeHidden", not visible)
	end
	local model = character:FindFirstChild("VisualPickaxe")
	if not model then return end
	if model:GetAttribute("Shown") == visible then return end
	model:SetAttribute("Shown", visible)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local base = d:GetAttribute("BaseTransparency")
			if type(base) ~= "number" then
				base = d.Transparency
				d:SetAttribute("BaseTransparency", base)
			end
			d.Transparency = visible and (base :: number) or 1
		elseif d:IsA("Decal") or d:IsA("Texture") then
			local base = d:GetAttribute("BaseTransparency")
			if type(base) ~= "number" then
				base = d.Transparency
				d:SetAttribute("BaseTransparency", base)
			end
			d.Transparency = visible and (base :: number) or 1
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Highlight") then
			local base = d:GetAttribute("BaseEnabled")
			if type(base) ~= "boolean" then
				base = (d :: any).Enabled
				d:SetAttribute("BaseEnabled", base)
			end
			(d :: any).Enabled = visible and (base :: boolean) or false
		end
	end
end

function EquipmentManager.SetFxRemote(remote: RemoteEvent)
	FxRemote = remote
end

function EquipmentManager.BroadcastSwing(player: Player, isCrit: boolean)
	local remote = FxRemote
	local char = player.Character
	if not remote or not char then return end
	pcall(function()
		remote:FireAllClients("Swing", char, isCrit == true, player.UserId)
	end)
end

function EquipmentManager.PlaySwingAnimation(character: Model?)
	if not character then return end
	local plr = Players:GetPlayerFromCharacter(character)
	if plr then
		EquipmentManager.BroadcastSwing(plr, false)
	end
end

-- ============================================================================
-- 3. СБОРКА 3D-РЮКЗАКА ПО УРОВНЯМ 1–10 (СТРОГО ПО РЕФЕРЕНСУ 1..10 LVL!)
-- Может использоваться как для крепления на спину персонажа (anchored = false),
-- так и для 3D-витрины и ViewportFrame магазина (anchored = true).
-- ============================================================================
type BagPartOpts = {
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

-- v23: generated backpack geometry (name, shape, size xyz, pos xyz, rot xyz deg, colour, material, push, flags)
-- v28: backpack geometry regenerated from the 10-backpack reference sheet (bag_gen2.py)
local BAG_SHAPES: { [number]: { { any } } } = {
	[1] = {
		{"BodyCore","B",1.8,1.366,0.795,0,-0.135,-0.087,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",0.828,0.486,0.795,0,0.791,-0.087,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.368,0.216,0.795,0,-0.926,-0.087,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.795,0.972,0.972,-0.414,0.548,-0.087,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.795,0.432,0.432,-0.684,-0.818,-0.087,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.613,0.731,-0.84,-0.062,-0.087,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.54,1.365,0.16,-0.396,0.041,-0.455,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.795,0.972,0.972,0.414,0.548,-0.087,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.795,0.432,0.432,0.684,-0.818,-0.087,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.613,0.731,0.84,-0.062,-0.087,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.54,1.365,0.16,0.396,0.041,-0.455,0,0,0,"trim","L",0,""},
		{"Body","E",1.728,1.985,0.698,0,-0.021,0.206,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",1.836,0.34,0.95,0,-0.934,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.192,0.08,0.08,0.888,0.623,0.31,0,0,99,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,0.842,0.766,0.31,0,0,117,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,0.753,0.887,0.31,0,0,135,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,0.632,0.976,0.31,0,0,153,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,0.489,1.022,0.31,0,0,171,"welt","L",1,""},
		{"Welt","C",0.868,0.08,0.08,0,1.034,0.31,0,0,-180,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,-0.489,1.022,0.31,0,0,-171,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,-0.632,0.976,0.31,0,0,-153,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,-0.753,0.887,0.31,0,0,-135,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,-0.842,0.766,0.31,0,0,-117,"welt","L",1,""},
		{"Welt","C",0.192,0.08,0.08,-0.888,0.623,0.31,0,0,-99,"welt","L",1,""},
		{"Welt","C",1.406,0.08,0.08,-0.9,-0.135,0.31,0,0,-90,"welt","L",1,""},
		{"Welt","C",0.152,0.08,0.08,-0.886,-0.872,0.31,0,0,-75,"welt","L",1,""},
		{"Welt","C",0.152,0.08,0.08,-0.832,-0.966,0.31,0,0,-45,"welt","L",1,""},
		{"Welt","C",0.152,0.08,0.08,-0.738,-1.02,0.31,0,0,-15,"welt","L",1,""},
		{"Welt","C",1.408,0.08,0.08,0,-1.034,0.31,0,0,0,"welt","L",1,""},
		{"Welt","C",0.152,0.08,0.08,0.738,-1.02,0.31,0,0,15,"welt","L",1,""},
		{"Welt","C",0.152,0.08,0.08,0.832,-0.966,0.31,0,0,45,"welt","L",1,""},
		{"Welt","C",0.152,0.08,0.08,0.886,-0.872,0.31,0,0,75,"welt","L",1,""},
		{"Welt","C",1.406,0.08,0.08,0.9,-0.135,0.31,0,0,90,"welt","L",1,""},
		{"Lid","E",1.854,1.075,1.105,0,0.62,-0.02,0,0,0,"flap","L",0.5,"T"},
		{"Stitch","B",0.067,0.028,0.02,-0.666,0.569,0.375,7.815,-31.124,-10.774,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.545,0.559,0.436,8.103,-23.112,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.423,0.554,0.479,8.003,-16.839,-4.911,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.302,0.544,0.509,8.705,-11.512,-4.793,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.181,0.533,0.526,9.522,-6.722,-4.723,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.06,0.528,0.535,9.914,-2.211,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.06,0.528,0.535,9.914,2.211,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.181,0.533,0.526,9.522,6.722,4.723,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.302,0.544,0.509,8.705,11.512,4.793,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.423,0.554,0.479,8.003,16.839,4.911,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.545,0.559,0.436,8.103,23.112,0,"thread","P",1,""},
		{"Stitch","B",0.067,0.028,0.02,0.666,0.569,0.375,7.815,31.124,10.774,"thread","P",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.749,0.537,-13.692,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.666,0.55,-4.83,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.583,0.551,3.935,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.5,0.539,12.779,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.428,0.537,-10,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.347,0.55,-7.915,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.267,0.56,-6.017,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.186,0.567,-4.246,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.105,0.572,-2.558,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.025,0.574,-0.917,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,-0.056,0.574,0.707,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,-0.136,0.572,2.344,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,-0.217,0.568,4.024,0,0,"trim","L",1,""},
		{"BuckleFrame","B",0.44,0.38,0.07,0,0.467,0.619,12.779,0,0,"metal","M",1,""},
		{"BuckleHole","B",0.25,0.19,0.08,0,0.465,0.726,12.779,0,0,"hole","P",1,""},
		{"BuckleTongue","B",0.05,0.22,0.09,0,0.464,0.843,12.779,0,0,"metal","M",1,""},
		{"StrapRivet","S",0.08,0.08,0.08,-0.07,0.57,0.719,12.779,0,0,"metal","M",1,""},
		{"StrapRivet","S",0.08,0.08,0.08,0.07,0.57,0.719,12.779,0,0,"metal","M",1,""},
		{"FrontPocket","E",1.116,0.744,0.52,0,-0.517,0.448,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.172,0.372,0.56,0,-0.338,0.453,0,0,0,"flap","L",1,""},
		{"Stitch","B",0.064,0.028,0.02,-0.415,-0.378,0.656,22.53,-24.172,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,-0.296,-0.383,0.698,21.246,-14.875,-4.666,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,-0.177,-0.388,0.722,21.666,-8.22,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,-0.059,-0.388,0.734,20.797,-2.651,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,0.059,-0.388,0.734,20.797,2.651,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,0.177,-0.388,0.722,21.666,8.22,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,0.296,-0.383,0.698,21.246,14.875,4.666,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,0.415,-0.378,0.656,22.53,24.172,0,"thread","P",1,""},
		{"Stitch","B",0.055,0.028,0.02,-0.357,-0.794,0.529,59.942,-26.803,0,"thread","P",1,""},
		{"Stitch","B",0.055,0.028,0.02,-0.254,-0.793,0.593,43.589,-16.038,0,"thread","P",1,""},
		{"Stitch","B",0.055,0.028,0.02,-0.152,-0.792,0.623,38.19,-8.792,0,"thread","P",1,""},
		{"Stitch","B",0.055,0.028,0.02,-0.051,-0.792,0.636,36.161,-2.817,0,"thread","P",1,""},
		{"Stitch","B",0.055,0.028,0.02,0.051,-0.792,0.636,36.161,2.817,0,"thread","P",1,""},
		{"Stitch","B",0.055,0.028,0.02,0.152,-0.792,0.623,38.19,8.792,0,"thread","P",1,""},
		{"Stitch","B",0.055,0.028,0.02,0.254,-0.793,0.593,43.589,16.038,0,"thread","P",1,""},
		{"Stitch","B",0.055,0.028,0.02,0.357,-0.794,0.529,59.942,26.803,0,"thread","P",1,""},
		{"PocketBuckle","B",0.26,0.22,0.06,0,-0.436,0.742,33.659,0,0,"metal","M",1,""},
		{"PocketBuckleHole","B",0.13,0.1,0.065,0,-0.439,0.83,33.659,0,0,"hole","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.66,-0.794,0.322,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.54,-0.794,0.322,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.425,-0.8,0.353,34.662,-22.182,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.304,-0.803,0.558,52.663,-20.967,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.182,-0.801,0.639,38.19,-8.792,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,-0.061,-0.801,0.656,36.161,-2.817,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.061,-0.801,0.656,36.161,2.817,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.182,-0.801,0.639,38.19,8.792,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.304,-0.803,0.558,52.663,20.967,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.425,-0.8,0.353,34.662,22.182,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.54,-0.794,0.322,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.066,0.028,0.02,0.66,-0.794,0.322,0,0,0,"thread","P",1,""},
		{"SidePocket","E",0.46,0.827,0.62,-0.96,-0.455,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.352,0.659,-0.96,-0.186,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.827,0.12,-1.195,-0.455,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.779,-0.975,0.414,-0.087,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,-0.99,0.414,0.111,0,0,0,"metal","M",1,""},
		{"SidePocket","E",0.46,0.827,0.62,0.96,-0.455,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.352,0.659,0.96,-0.186,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.827,0.12,1.195,-0.455,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.779,0.975,0.414,-0.087,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,0.99,0.414,0.111,0,0,0,"metal","M",1,""},
		{"Handle","C",0.124,0.12,0.12,0.291,1.215,-0.116,0,0,102.43,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,0.256,1.292,-0.116,0,0,125.818,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,0.19,1.355,-0.116,0,0,146.127,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,0.101,1.396,-0.116,0,0,163.766,"trim","L",0.5,""},
		{"Handle","C",0.144,0.12,0.12,0,1.41,-0.116,0,0,-180,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,-0.101,1.396,-0.116,0,0,-163.766,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,-0.19,1.355,-0.116,0,0,-146.127,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,-0.256,1.292,-0.116,0,0,-125.818,"trim","L",0.5,""},
		{"Handle","C",0.124,0.12,0.12,-0.291,1.215,-0.116,0,0,-102.43,"trim","L",0.5,""},
		{"CamoSpot","C",0.02,0.3,0.3,-0.542,0.683,0.43,-180,-66.665,-172.297,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.21,0.21,-0.423,0.638,0.507,-180,-66.665,-172.297,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.26,0.26,0.488,0.456,0.446,0,-71.373,13.324,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.182,0.182,0.592,0.418,0.439,0,-71.373,13.324,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.2,0.2,0.651,0.83,0.317,0,-55.36,28.334,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.14,0.14,0.728,0.797,0.317,-180,-90,-180,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.2,0.2,-0.687,0.249,0.402,-180,-59.73,-171.464,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.14,0.14,-0.598,0.216,0.452,0,-32.977,-17.462,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.2,0.2,0.145,0.871,0.468,0,-83.951,28.36,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.14,0.14,0.225,0.842,0.495,0,-83.951,28.36,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.22,0.22,-0.578,-0.415,0.431,-180,-66.917,168.546,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.154,0.154,-0.493,-0.445,0.569,-180,-47.617,-167.674,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.2,0.2,0.543,-0.623,0.383,0,-62.957,-20.934,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.14,0.14,0.623,-0.653,0.349,0,-62.957,-20.934,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.16,0.16,-0.272,-0.748,0.615,-180,-70.206,147.335,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.112,0.112,-0.208,-0.772,0.643,-180,-70.206,147.335,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.18,0.18,0.687,-0.104,0.422,0,-62.161,-2.45,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.126,0.126,0.759,-0.131,0.402,0,-62.161,-2.45,"camoA","L",1,""},
	},
	[2] = {
		{"BodyCore","B",2,1.452,0.836,0,-0.15,-0.092,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",0.92,0.54,0.836,0,0.846,-0.092,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.52,0.24,0.836,0,-0.996,-0.092,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,1.08,1.08,-0.46,0.576,-0.092,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,0.48,0.48,-0.76,-0.876,-0.092,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.741,0.769,-0.94,-0.067,-0.092,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.6,1.473,0.16,-0.44,0.045,-0.48,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.836,1.08,1.08,0.46,0.576,-0.092,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,0.48,0.48,0.76,-0.876,-0.092,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.741,0.769,0.94,-0.067,-0.092,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.6,1.473,0.16,0.44,0.045,-0.48,0,0,0,"trim","L",0,""},
		{"Body","E",1.92,2.143,0.734,0,-0.022,0.213,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",2.04,0.34,1,0,-1.016,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.209,0.08,0.08,0.987,0.66,0.326,0,0,99,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,0.935,0.818,0.326,0,0,117,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,0.837,0.953,0.326,0,0,135,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,0.702,1.051,0.326,0,0,153,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,0.543,1.103,0.326,0,0,171,"welt","L",1,""},
		{"Welt","C",0.96,0.08,0.08,0,1.116,0.326,0,0,-180,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,-0.543,1.103,0.326,0,0,-171,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,-0.702,1.051,0.326,0,0,-153,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,-0.837,0.953,0.326,0,0,-135,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,-0.935,0.818,0.326,0,0,-117,"welt","L",1,""},
		{"Welt","C",0.209,0.08,0.08,-0.987,0.66,0.326,0,0,-99,"welt","L",1,""},
		{"Welt","C",1.493,0.08,0.08,-1,-0.15,0.326,0,0,-90,"welt","L",1,""},
		{"Welt","C",0.164,0.08,0.08,-0.984,-0.936,0.326,0,0,-75,"welt","L",1,""},
		{"Welt","C",0.164,0.08,0.08,-0.924,-1.04,0.326,0,0,-45,"welt","L",1,""},
		{"Welt","C",0.164,0.08,0.08,-0.82,-1.1,0.326,0,0,-15,"welt","L",1,""},
		{"Welt","C",1.56,0.08,0.08,0,-1.116,0.326,0,0,0,"welt","L",1,""},
		{"Welt","C",0.164,0.08,0.08,0.82,-1.1,0.326,0,0,15,"welt","L",1,""},
		{"Welt","C",0.164,0.08,0.08,0.924,-1.04,0.326,0,0,45,"welt","L",1,""},
		{"Welt","C",0.164,0.08,0.08,0.984,-0.936,0.326,0,0,75,"welt","L",1,""},
		{"Welt","C",1.493,0.08,0.08,1,-0.15,0.326,0,0,90,"welt","L",1,""},
		{"Lid","E",2.06,1.161,1.163,0,0.67,-0.02,0,0,0,"flap","L",0.5,"T"},
		{"Stitch","B",0.075,0.028,0.02,-0.739,0.603,0.393,9.191,-29.782,-14.077,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.605,0.588,0.457,9.778,-22.024,0,"thread","P",1,""},
		{"Stitch","B",0.074,0.028,0.02,-0.47,0.583,0.503,9.47,-16.006,-4.385,"thread","P",1,""},
		{"Stitch","B",0.074,0.028,0.02,-0.336,0.573,0.533,9.977,-10.927,-4.292,"thread","P",1,""},
		{"Stitch","B",0.074,0.028,0.02,-0.201,0.563,0.552,10.643,-6.375,-4.235,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.067,0.557,0.561,10.965,-2.097,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.067,0.557,0.561,10.965,2.097,0,"thread","P",1,""},
		{"Stitch","B",0.074,0.028,0.02,0.201,0.563,0.552,10.643,6.375,4.235,"thread","P",1,""},
		{"Stitch","B",0.074,0.028,0.02,0.336,0.573,0.533,9.977,10.927,4.292,"thread","P",1,""},
		{"Stitch","B",0.074,0.028,0.02,0.47,0.583,0.503,9.47,16.006,4.385,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.605,0.588,0.457,9.778,22.024,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,0.739,0.603,0.393,9.191,29.782,14.077,"thread","P",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.486,0.809,0.495,-15.142,-16.556,-4.41,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.486,0.726,0.511,-6.04,-16.557,-1.727,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.486,0.643,0.513,2.912,-16.558,0.831,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.486,0.56,0.502,11.936,-16.557,3.447,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.485,0.488,0.498,-12.565,-14.42,-3.177,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.485,0.407,0.514,-10.041,-13.754,-2.411,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.485,0.326,0.527,-7.84,-13.267,-1.81,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.484,0.246,0.537,-5.854,-12.915,-1.313,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.484,0.165,0.544,-4.01,-12.673,-0.881,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.484,0.084,0.548,-2.257,-12.523,-0.49,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.484,0.004,0.55,-0.551,-12.457,-0.119,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.484,-0.077,0.55,1.144,-12.471,0.247,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.484,-0.157,0.547,2.862,-12.566,0.623,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,-0.484,-0.238,0.542,4.642,-12.746,1.026,"trim","L",1,""},
		{"BuckleFrame","B",0.352,0.304,0.07,-0.497,0.524,0.582,11.936,-16.557,3.447,"metal","M",1,""},
		{"BuckleHole","B",0.2,0.152,0.08,-0.5,0.522,0.692,11.936,-16.557,3.447,"hole","P",1,""},
		{"BuckleTongue","B",0.05,0.176,0.09,-0.501,0.521,0.814,11.936,-16.557,3.447,"metal","M",1,""},
		{"StrapRivet","S",0.08,0.08,0.08,-0.561,0.617,0.662,11.936,-16.557,3.447,"metal","M",1,""},
		{"StrapRivet","S",0.08,0.08,0.08,-0.421,0.617,0.704,11.936,-16.557,3.447,"metal","M",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.486,0.809,0.495,-15.142,16.556,4.41,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.486,0.726,0.511,-6.04,16.557,1.727,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.486,0.643,0.513,2.912,16.558,-0.831,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.486,0.56,0.502,11.936,16.557,-3.447,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.485,0.488,0.498,-12.565,14.42,3.177,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.485,0.407,0.514,-10.041,13.754,2.411,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.485,0.326,0.527,-7.84,13.267,1.81,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.484,0.246,0.537,-5.854,12.915,1.313,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.484,0.165,0.544,-4.01,12.673,0.881,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.484,0.084,0.548,-2.257,12.523,0.49,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.484,0.004,0.55,-0.551,12.457,0.119,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.484,-0.077,0.55,1.144,12.471,-0.247,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.484,-0.157,0.547,2.862,12.566,-0.623,"trim","L",1,""},
		{"FlapStrap","B",0.2,0.1,0.05,0.484,-0.238,0.542,4.642,12.746,-1.026,"trim","L",1,""},
		{"BuckleFrame","B",0.352,0.304,0.07,0.497,0.524,0.582,11.936,16.557,-3.447,"metal","M",1,""},
		{"BuckleHole","B",0.2,0.152,0.08,0.5,0.522,0.692,11.936,16.557,-3.447,"hole","P",1,""},
		{"BuckleTongue","B",0.05,0.176,0.09,0.501,0.521,0.814,11.936,16.557,-3.447,"metal","M",1,""},
		{"StrapRivet","S",0.08,0.08,0.08,0.421,0.617,0.704,11.936,16.557,-3.447,"metal","M",1,""},
		{"StrapRivet","S",0.08,0.08,0.08,0.561,0.617,0.662,11.936,16.557,-3.447,"metal","M",1,""},
		{"FrontPocket","E",1.24,0.804,0.52,0,-0.558,0.471,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.302,0.402,0.56,0,-0.365,0.476,0,0,0,"flap","L",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.46,-0.411,0.677,22.983,-22.082,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.328,-0.416,0.72,21.253,-13.511,-4.183,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.197,-0.421,0.744,21.355,-7.454,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.066,-0.421,0.756,20.49,-2.401,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.066,-0.421,0.756,20.49,2.401,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.197,-0.421,0.744,21.355,7.454,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.328,-0.416,0.72,21.253,13.511,4.183,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.46,-0.411,0.677,22.983,22.082,0,"thread","P",1,""},
		{"Stitch","B",0.061,0.028,0.02,-0.396,-0.857,0.552,58.005,-25.687,0,"thread","P",1,""},
		{"Stitch","B",0.061,0.028,0.02,-0.282,-0.855,0.617,41.405,-14.998,0,"thread","P",1,""},
		{"Stitch","B",0.061,0.028,0.02,-0.169,-0.854,0.647,36.08,-8.146,0,"thread","P",1,""},
		{"Stitch","B",0.061,0.028,0.02,-0.056,-0.854,0.66,34.098,-2.601,0,"thread","P",1,""},
		{"Stitch","B",0.061,0.028,0.02,0.056,-0.854,0.66,34.098,2.601,0,"thread","P",1,""},
		{"Stitch","B",0.061,0.028,0.02,0.169,-0.854,0.647,36.08,8.146,0,"thread","P",1,""},
		{"Stitch","B",0.061,0.028,0.02,0.282,-0.855,0.617,41.405,14.998,0,"thread","P",1,""},
		{"Stitch","B",0.061,0.028,0.02,0.396,-0.857,0.552,58.005,25.687,0,"thread","P",1,""},
		{"PocketBuckle","B",0.26,0.22,0.06,0,-0.468,0.766,31.838,0,0,"metal","M",1,""},
		{"PocketBuckleHole","B",0.13,0.1,0.065,0,-0.471,0.852,31.838,0,0,"hole","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.733,-0.888,0.326,90,0,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.6,-0.888,0.326,90,0,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.471,-0.883,0.353,37.277,-22.412,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.338,-0.886,0.552,60.462,-20.955,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.202,-0.885,0.614,44.629,-10.511,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.067,-0.884,0.636,40.419,-3.267,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.067,-0.884,0.636,40.419,3.267,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.202,-0.885,0.614,44.629,10.511,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.338,-0.886,0.552,60.462,20.955,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.471,-0.883,0.353,37.277,22.412,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.6,-0.888,0.326,90,0,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.733,-0.888,0.326,90,0,0,"thread","P",1,""},
		{"SidePocket","E",0.46,0.893,0.653,-1.06,-0.491,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.38,0.694,-1.06,-0.201,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.893,0.12,-1.295,-0.491,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.82,-1.075,0.447,-0.092,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,-1.09,0.447,0.117,0,0,0,"metal","M",1,""},
		{"SidePocket","E",0.46,0.893,0.653,1.06,-0.491,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.38,0.694,1.06,-0.201,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.893,0.12,1.295,-0.491,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.82,1.075,0.447,-0.092,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,1.09,0.447,0.117,0,0,0,"metal","M",1,""},
		{"Bedroll","C",2.08,0.62,0.62,0,1.476,-0.06,0,0,0,{124,108,86},"F",0.5,""},
		{"BedrollStripe","C",0.1,0.64,0.64,0,1.476,-0.06,0,0,0,{150,137,120},"F",0.5,""},
		{"BedrollStrap","C",0.13,0.68,0.68,-0.6,1.476,-0.06,0,0,0,"trim","L",0.5,""},
		{"BedrollStrap","C",0.13,0.68,0.68,0.6,1.476,-0.06,0,0,0,"trim","L",0.5,""},
	},
	[3] = {
		{"BodyCore","B",1.96,2.056,0.878,0,-0.147,-0.096,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",0.902,0.529,0.878,0,1.145,-0.096,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.49,0.235,0.878,0,-1.292,-0.096,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.878,1.058,1.058,-0.451,0.881,-0.096,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.878,0.47,0.47,-0.745,-1.175,-0.096,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,2.2,0.808,-0.92,-0.085,-0.096,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.588,1.861,0.16,-0.431,0.056,-0.506,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.878,1.058,1.058,0.451,0.881,-0.096,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.878,0.47,0.47,0.745,-1.175,-0.096,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,2.2,0.808,0.92,-0.085,-0.096,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.588,1.861,0.16,0.431,0.056,-0.506,0,0,0,"trim","L",0,""},
		{"Body","E",1.882,2.707,0.771,0,-0.028,0.22,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",1.999,0.34,1.05,0,-1.31,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.206,0.08,0.08,0.967,0.963,0.343,0,0,99,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,0.917,1.118,0.343,0,0,117,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,0.82,1.25,0.343,0,0,135,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,0.688,1.347,0.343,0,0,153,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,0.533,1.397,0.343,0,0,171,"welt","L",1,""},
		{"Welt","C",0.942,0.08,0.08,0,1.41,0.343,0,0,-180,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,-0.533,1.397,0.343,0,0,-171,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,-0.688,1.347,0.343,0,0,-153,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,-0.82,1.25,0.343,0,0,-135,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,-0.917,1.118,0.343,0,0,-117,"welt","L",1,""},
		{"Welt","C",0.206,0.08,0.08,-0.967,0.963,0.343,0,0,-99,"welt","L",1,""},
		{"Welt","C",2.096,0.08,0.08,-0.98,-0.147,0.343,0,0,-90,"welt","L",1,""},
		{"Welt","C",0.162,0.08,0.08,-0.964,-1.234,0.343,0,0,-75,"welt","L",1,""},
		{"Welt","C",0.162,0.08,0.08,-0.905,-1.335,0.343,0,0,-45,"welt","L",1,""},
		{"Welt","C",0.162,0.08,0.08,-0.804,-1.394,0.343,0,0,-15,"welt","L",1,""},
		{"Welt","C",1.53,0.08,0.08,0,-1.41,0.343,0,0,0,"welt","L",1,""},
		{"Welt","C",0.162,0.08,0.08,0.804,-1.394,0.343,0,0,15,"welt","L",1,""},
		{"Welt","C",0.162,0.08,0.08,0.905,-1.335,0.343,0,0,45,"welt","L",1,""},
		{"Welt","C",0.162,0.08,0.08,0.964,-1.234,0.343,0,0,75,"welt","L",1,""},
		{"Welt","C",2.096,0.08,0.08,0.98,-0.147,0.343,0,0,90,"welt","L",1,""},
		{"Lid","E",2.019,1.466,1.221,0,0.846,-0.02,0,0,0,"flap","L",0.5,"T"},
		{"Stitch","B",0.075,0.028,0.02,-0.725,0.734,0.409,10.32,-31.697,-18.9,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.593,0.714,0.475,10.542,-23.588,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.461,0.709,0.524,9.968,-17.192,-4.493,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.329,0.694,0.556,10.447,-11.769,-8.692,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.197,0.684,0.576,10.757,-6.878,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.066,0.679,0.585,10.909,-2.264,-4.298,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.066,0.679,0.585,10.909,2.264,4.298,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.197,0.684,0.576,10.757,6.878,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.329,0.694,0.556,10.447,11.769,8.692,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.461,0.709,0.524,9.968,17.192,4.493,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.593,0.714,0.475,10.542,23.588,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,0.725,0.734,0.409,10.32,31.697,18.9,"thread","P",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,1.019,0.594,-11.171,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.937,0.606,-5.827,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.855,0.61,-0.599,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.774,0.608,4.618,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.692,0.597,9.926,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.61,0.579,15.436,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.538,0.59,-7.429,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.457,0.6,-6.215,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.377,0.608,-5.082,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.297,0.614,-4.009,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.216,0.619,-2.981,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.136,0.623,-1.984,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,0.056,0.625,-1.007,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,-0.025,0.625,-0.041,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,-0.105,0.625,0.925,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,-0.185,0.623,1.9,0,0,"trim","L",1,""},
		{"FlapStrap","B",0.22,0.1,0.05,0,-0.266,0.62,2.895,0,0,"trim","L",1,""},
		{"BuckleFrame","B",0.44,0.38,0.07,0,0.61,0.667,15.436,0,0,"metal","M",1,""},
		{"BuckleHole","B",0.25,0.19,0.08,0,0.607,0.775,15.436,0,0,"hole","P",1,""},
		{"BuckleTongue","B",0.05,0.22,0.09,0,0.606,0.894,15.436,0,0,"metal","M",1,""},
		{"StrapRivet","S",0.08,0.08,0.08,-0.07,0.828,0.741,-74.564,0,0,"metal","M",1,""},
		{"StrapRivet","S",0.08,0.08,0.08,0.07,0.828,0.741,-74.564,0,0,"metal","M",1,""},
		{"FrontPocket","E",1.215,1.015,0.52,0,-0.705,0.494,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.276,0.508,0.56,0,-0.461,0.499,0,0,0,"flap","L",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.451,-0.53,0.696,22.638,-23,-4.437,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.322,-0.534,0.74,20.067,-14.075,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.193,-0.534,0.766,18.184,-7.791,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.064,-0.539,0.777,18.705,-2.502,-4.245,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.064,-0.539,0.777,18.705,2.502,4.245,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.193,-0.534,0.766,18.184,7.791,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.322,-0.534,0.74,20.067,14.075,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.451,-0.53,0.696,22.638,23,4.437,"thread","P",1,""},
		{"Stitch","B",0.06,0.028,0.02,-0.389,-1.079,0.576,51.721,-29.849,0,"thread","P",1,""},
		{"Stitch","B",0.06,0.028,0.02,-0.277,-1.077,0.641,34.918,-16.64,0,"thread","P",1,""},
		{"Stitch","B",0.06,0.028,0.02,-0.166,-1.076,0.67,29.98,-8.897,0,"thread","P",1,""},
		{"Stitch","B",0.06,0.028,0.02,-0.055,-1.076,0.683,28.189,-2.824,0,"thread","P",1,""},
		{"Stitch","B",0.06,0.028,0.02,0.055,-1.076,0.683,28.189,2.824,0,"thread","P",1,""},
		{"Stitch","B",0.06,0.028,0.02,0.166,-1.076,0.67,29.98,8.897,0,"thread","P",1,""},
		{"Stitch","B",0.06,0.028,0.02,0.277,-1.077,0.641,34.918,16.64,0,"thread","P",1,""},
		{"Stitch","B",0.06,0.028,0.02,0.389,-1.079,0.576,51.721,29.849,0,"thread","P",1,""},
		{"PocketBuckle","B",0.26,0.22,0.06,0,-0.589,0.787,27.707,0,0,"metal","M",1,""},
		{"PocketBuckleHole","B",0.13,0.1,0.065,0,-0.591,0.871,27.707,0,0,"hole","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.719,-1.17,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.588,-1.17,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.457,-1.17,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.33,-1.176,0.388,30.387,-16.677,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.199,-1.18,0.561,63.084,-14.698,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,-0.066,-1.179,0.602,50.535,-4.329,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.066,-1.179,0.602,50.535,4.329,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.199,-1.18,0.561,63.084,14.698,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.33,-1.176,0.388,30.387,16.677,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.457,-1.17,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.588,-1.17,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.072,0.028,0.02,0.719,-1.17,0.355,0,0,0,"thread","P",1,""},
		{"SidePocket","E",0.46,1.128,0.685,-1.04,-0.62,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.479,0.728,-1.04,-0.254,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,1.128,0.12,-1.275,-0.62,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.861,-1.055,0.564,-0.096,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,-1.07,0.564,0.123,0,0,0,"metal","M",1,""},
		{"SidePocket","E",0.46,1.128,0.685,1.04,-0.62,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.479,0.728,1.04,-0.254,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,1.128,0.12,1.275,-0.62,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.861,1.055,0.564,-0.096,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,1.07,0.564,0.123,0,0,0,"metal","M",1,""},
		{"Bedroll","C",2.038,0.62,0.62,0,1.77,-0.06,0,0,0,{96,108,52},"F",0.5,""},
		{"BedrollStripe","C",0.1,0.64,0.64,0,1.77,-0.06,0,0,0,{128,137,93},"F",0.5,""},
		{"BedrollStrap","C",0.13,0.68,0.68,-0.588,1.77,-0.06,0,0,0,"trim","L",0.5,""},
		{"BedrollStrap","C",0.13,0.68,0.68,0.588,1.77,-0.06,0,0,0,"trim","L",0.5,""},
		{"CamoSpot","C",0.02,0.3,0.3,-0.59,0.931,0.477,-180,-66.353,-173.758,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.21,0.21,-0.471,0.886,0.553,-180,-66.353,-173.758,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.26,0.26,0.531,0.622,0.485,0,-71.113,10.85,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.182,0.182,0.635,0.583,0.476,0,-71.113,10.85,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.2,0.2,0.709,1.13,0.353,0,-54.959,23.505,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.14,0.14,0.786,1.098,0.35,-180,-90,-180,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.2,0.2,-0.748,0.339,0.436,-180,-59.356,-173.09,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.14,0.14,-0.659,0.306,0.487,0,-32.831,-17.479,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.2,0.2,0.157,1.187,0.519,0,-83.861,23.627,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.14,0.14,0.237,1.157,0.542,0,-83.861,23.627,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.22,0.22,-0.63,-0.565,0.469,-180,-66.607,170.695,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.154,0.154,-0.544,-0.596,0.605,-180,-47.118,-168.95,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.2,0.2,0.591,-0.848,0.416,0,-62.609,-17.177,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.14,0.14,0.671,-0.878,0.383,0,-62.609,-17.177,"camoB","L",1,""},
		{"CamoSpot","C",0.02,0.16,0.16,-0.296,-1.018,0.662,-180,-71.71,154.618,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.112,0.112,-0.232,-1.042,0.691,-180,-71.71,154.618,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.18,0.18,0.748,-0.141,0.459,0,-61.806,-1.98,"camoA","L",1,""},
		{"CamoSpot","C",0.02,0.126,0.126,0.82,-0.168,0.438,0,-61.806,-1.98,"camoA","L",1,""},
		{"BackStrapX","B",0.16,2.594,0.05,0,-0.056,-0.606,0,0,-30,"trim","L",0,""},
		{"BackStrapX","B",0.16,2.594,0.05,0,-0.056,-0.606,0,0,30,"trim","L",0,""},
		{"BackStrapRing","C",0.06,0.2,0.2,0,-0.056,-0.636,0,90,0,"metal","M",0,""},
	},
	[4] = {
		{"BodyCore","B",1.9,1.503,0.711,0,-0.266,-0.078,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",0.38,0.76,0.711,0,0.866,-0.078,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.444,0.228,0.711,0,-1.131,-0.078,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.711,1.52,1.52,-0.19,0.486,-0.078,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.711,0.456,0.456,-0.722,-1.018,-0.078,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.544,0.654,-0.89,-0.199,-0.078,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.57,1.644,0.16,-0.418,0.05,-0.403,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.711,1.52,1.52,0.19,0.486,-0.078,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.711,0.456,0.456,0.722,-1.018,-0.078,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.544,0.654,0.89,-0.199,-0.078,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.57,1.644,0.16,0.418,0.05,-0.403,0,0,0,"trim","L",0,""},
		{"Body","E",1.824,2.391,0.624,0,-0.025,0.191,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",1.938,0.34,0.85,0,-1.145,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.278,0.08,0.08,0.931,0.603,0.277,0,0,99,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,0.859,0.826,0.277,0,0,117,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,0.721,1.016,0.277,0,0,135,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,0.531,1.154,0.277,0,0,153,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,0.307,1.227,0.277,0,0,171,"welt","L",1,""},
		{"Welt","C",0.42,0.08,0.08,0,1.246,0.277,0,0,-180,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,-0.307,1.227,0.277,0,0,-171,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,-0.531,1.154,0.277,0,0,-153,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,-0.721,1.016,0.277,0,0,-135,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,-0.859,0.826,0.277,0,0,-117,"welt","L",1,""},
		{"Welt","C",0.278,0.08,0.08,-0.931,0.603,0.277,0,0,-99,"welt","L",1,""},
		{"Welt","C",1.543,0.08,0.08,-0.95,-0.266,0.277,0,0,-90,"welt","L",1,""},
		{"Welt","C",0.158,0.08,0.08,-0.935,-1.075,0.277,0,0,-75,"welt","L",1,""},
		{"Welt","C",0.158,0.08,0.08,-0.878,-1.173,0.277,0,0,-45,"welt","L",1,""},
		{"Welt","C",0.158,0.08,0.08,-0.779,-1.23,0.277,0,0,-15,"welt","L",1,""},
		{"Welt","C",1.484,0.08,0.08,0,-1.246,0.277,0,0,0,"welt","L",1,""},
		{"Welt","C",0.158,0.08,0.08,0.779,-1.23,0.277,0,0,15,"welt","L",1,""},
		{"Welt","C",0.158,0.08,0.08,0.878,-1.173,0.277,0,0,45,"welt","L",1,""},
		{"Welt","C",0.158,0.08,0.08,0.935,-1.075,0.277,0,0,75,"welt","L",1,""},
		{"Welt","C",1.543,0.08,0.08,0.95,-0.266,0.277,0,0,90,"welt","L",1,""},
		{"Zip","B",0.183,0.07,0.04,0.709,0.359,0.369,-8.702,25.588,109.513,"trim","L",1,""},
		{"Zip","B",0.178,0.07,0.04,0.654,0.5,0.369,-11.803,23.635,117.53,"trim","L",1,""},
		{"Zip","B",0.173,0.07,0.04,0.584,0.627,0.369,-14.56,21.102,125.808,"trim","L",1,""},
		{"Zip","B",0.167,0.07,0.04,0.498,0.739,0.369,-16.915,18.046,134.472,"trim","L",1,""},
		{"Zip","B",0.161,0.07,0.04,0.401,0.831,0.369,-18.83,14.537,143.644,"trim","L",1,""},
		{"Zip","B",0.156,0.07,0.04,0.294,0.903,0.369,-20.279,10.659,153.407,"trim","L",1,""},
		{"Zip","B",0.153,0.07,0.04,0.179,0.952,0.369,-21.251,6.508,163.751,"trim","L",1,""},
		{"Zip","B",0.15,0.07,0.04,0.06,0.976,0.369,-21.738,2.188,174.529,"trim","L",1,""},
		{"Zip","B",0.15,0.07,0.04,-0.06,0.976,0.369,-21.738,-2.188,-174.529,"trim","L",1,""},
		{"Zip","B",0.153,0.07,0.04,-0.179,0.952,0.369,-21.251,-6.508,-163.751,"trim","L",1,""},
		{"Zip","B",0.156,0.07,0.04,-0.294,0.903,0.369,-20.279,-10.659,-153.407,"trim","L",1,""},
		{"Zip","B",0.161,0.07,0.04,-0.401,0.831,0.369,-18.83,-14.537,-143.644,"trim","L",1,""},
		{"Zip","B",0.167,0.07,0.04,-0.498,0.739,0.369,-16.915,-18.046,-134.472,"trim","L",1,""},
		{"Zip","B",0.173,0.07,0.04,-0.584,0.627,0.369,-14.56,-21.102,-125.808,"trim","L",1,""},
		{"Zip","B",0.178,0.07,0.04,-0.654,0.5,0.369,-11.803,-23.635,-117.53,"trim","L",1,""},
		{"Zip","B",0.183,0.07,0.04,-0.709,0.359,0.369,-8.702,-25.588,-109.513,"trim","L",1,""},
		{"ZipPull","B",0.12,0.24,0.05,0.551,0.591,0.413,-12.091,17.725,3.731,"metal","M",1,""},
		{"FrontPocket","E",1.178,0.897,0.52,0,-0.623,0.402,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.237,0.448,0.56,0,-0.408,0.407,0,0,0,"flap","L",1,""},
		{"PocketZip","B",0.154,0.065,0.035,-0.437,-0.507,0.572,-13.203,-26.681,-5.081,{18,18,22},"P",1,""},
		{"PocketZip","B",0.154,0.065,0.035,-0.311,-0.512,0.621,-9.808,-15.641,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.154,0.065,0.035,-0.187,-0.513,0.648,-8.738,-8.52,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.154,0.065,0.035,-0.062,-0.513,0.66,-8.319,-2.723,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.154,0.065,0.035,0.062,-0.513,0.66,-8.319,2.723,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.154,0.065,0.035,0.187,-0.513,0.648,-8.738,8.52,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.154,0.065,0.035,0.311,-0.512,0.621,-9.808,15.641,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.154,0.065,0.035,0.437,-0.507,0.572,-13.203,26.681,5.081,{18,18,22},"P",1,""},
		{"PocketZipPull","B",0.1,0.2,0.04,0.253,-0.624,0.667,0.079,11.546,-0.016,"metal","M",1,""},
		{"Stitch","B",0.058,0.028,0.02,-0.377,-0.954,0.483,55.12,-28.654,0,"thread","P",1,""},
		{"Stitch","B",0.058,0.028,0.02,-0.268,-0.953,0.548,38.319,-16.436,0,"thread","P",1,""},
		{"Stitch","B",0.058,0.028,0.02,-0.161,-0.952,0.578,33.147,-8.872,0,"thread","P",1,""},
		{"Stitch","B",0.058,0.028,0.02,-0.054,-0.952,0.591,31.247,-2.826,0,"thread","P",1,""},
		{"Stitch","B",0.058,0.028,0.02,0.054,-0.952,0.591,31.247,2.826,0,"thread","P",1,""},
		{"Stitch","B",0.058,0.028,0.02,0.161,-0.952,0.578,33.147,8.872,0,"thread","P",1,""},
		{"Stitch","B",0.058,0.028,0.02,0.268,-0.953,0.548,38.319,16.436,0,"thread","P",1,""},
		{"Stitch","B",0.058,0.028,0.02,0.377,-0.954,0.483,55.12,28.654,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.697,-1.006,0.289,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.57,-1.006,0.289,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.448,-1.012,0.295,35.345,-24.207,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.319,-1.01,0.344,25.206,-13.3,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.193,-1.015,0.515,50.436,-12.504,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.064,-1.014,0.543,44.163,-3.822,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.064,-1.014,0.543,44.163,3.822,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.193,-1.015,0.515,50.436,12.504,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.319,-1.01,0.344,25.206,13.3,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.448,-1.012,0.295,35.345,24.207,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.57,-1.006,0.289,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.697,-1.006,0.289,0,0,0,"thread","P",1,""},
		{"SidePocket","E",0.46,0.996,0.555,-1.01,-0.548,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.423,0.59,-1.01,-0.224,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.996,0.12,-1.245,-0.548,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.697,-1.025,0.498,-0.078,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,-1.04,0.498,0.1,0,0,0,"metal","M",1,""},
		{"SidePocket","E",0.46,0.996,0.555,1.01,-0.548,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.423,0.59,1.01,-0.224,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.996,0.12,1.245,-0.548,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.697,1.025,0.498,-0.078,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,1.04,0.498,0.1,0,0,0,"metal","M",1,""},
		{"Handle","C",0.124,0.12,0.12,0.291,1.287,-0.104,0,0,102.43,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,0.256,1.364,-0.104,0,0,125.818,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,0.19,1.427,-0.104,0,0,146.127,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,0.101,1.468,-0.104,0,0,163.766,"trim","L",0.5,""},
		{"Handle","C",0.144,0.12,0.12,0,1.482,-0.104,0,0,-180,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,-0.101,1.468,-0.104,0,0,-163.766,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,-0.19,1.427,-0.104,0,0,-146.127,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,-0.256,1.364,-0.104,0,0,-125.818,"trim","L",0.5,""},
		{"Handle","C",0.124,0.12,0.12,-0.291,1.287,-0.104,0,0,-102.43,"trim","L",0.5,""},
		{"TopPatch","B",0.5,0.32,0.035,0,0.75,0.441,-12.452,0,0,{122,126,132},"F",1,""},
		{"PatchSlot","B",0.06,0.16,0.04,-0.1,0.754,0.489,-12.452,0,0,{34,36,40},"P",1,""},
		{"PatchSlot","B",0.06,0.16,0.04,0.1,0.754,0.489,-12.452,0,0,{34,36,40},"P",1,""},
	},
	[5] = {
		{"BodyCore","B",2.1,1.531,0.836,0,-0.158,-0.092,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",0.966,0.567,0.836,0,0.891,-0.092,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.596,0.252,0.836,0,-1.049,-0.092,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,1.134,1.134,-0.483,0.608,-0.092,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,0.504,0.504,-0.798,-0.923,-0.092,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.833,0.769,-0.99,-0.07,-0.092,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.63,1.551,0.16,-0.462,0.047,-0.48,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.836,1.134,1.134,0.483,0.608,-0.092,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,0.504,0.504,0.798,-0.923,-0.092,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.833,0.769,0.99,-0.07,-0.092,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.63,1.551,0.16,0.462,0.047,-0.48,0,0,0,"trim","L",0,""},
		{"Body","E",2.016,2.256,0.734,0,-0.024,0.213,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",2.142,0.34,1,0,-1.075,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.217,0.08,0.08,1.036,0.696,0.326,0,0,99,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,0.982,0.862,0.326,0,0,117,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,0.879,1.004,0.326,0,0,135,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,0.737,1.107,0.326,0,0,153,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,0.571,1.161,0.326,0,0,171,"welt","L",1,""},
		{"Welt","C",1.006,0.08,0.08,0,1.175,0.326,0,0,-180,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,-0.571,1.161,0.326,0,0,-171,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,-0.737,1.107,0.326,0,0,-153,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,-0.879,1.004,0.326,0,0,-135,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,-0.982,0.862,0.326,0,0,-117,"welt","L",1,""},
		{"Welt","C",0.217,0.08,0.08,-1.036,0.696,0.326,0,0,-99,"welt","L",1,""},
		{"Welt","C",1.571,0.08,0.08,-1.05,-0.157,0.326,0,0,-90,"welt","L",1,""},
		{"Welt","C",0.17,0.08,0.08,-1.033,-0.986,0.326,0,0,-75,"welt","L",1,""},
		{"Welt","C",0.17,0.08,0.08,-0.97,-1.095,0.326,0,0,-45,"welt","L",1,""},
		{"Welt","C",0.17,0.08,0.08,-0.861,-1.158,0.326,0,0,-15,"welt","L",1,""},
		{"Welt","C",1.636,0.08,0.08,0,-1.175,0.326,0,0,0,"welt","L",1,""},
		{"Welt","C",0.17,0.08,0.08,0.861,-1.158,0.326,0,0,15,"welt","L",1,""},
		{"Welt","C",0.17,0.08,0.08,0.97,-1.095,0.326,0,0,45,"welt","L",1,""},
		{"Welt","C",0.17,0.08,0.08,1.033,-0.986,0.326,0,0,75,"welt","L",1,""},
		{"Welt","C",1.571,0.08,0.08,1.05,-0.158,0.326,0,0,90,"welt","L",1,""},
		{"Zip","B",0.176,0.07,0.04,0.783,0.339,0.421,-10.806,26.862,112.9,"trim","L",1,""},
		{"Zip","B",0.175,0.07,0.04,0.723,0.472,0.421,-14.606,24.726,121.924,"trim","L",1,""},
		{"Zip","B",0.172,0.07,0.04,0.645,0.592,0.421,-17.948,21.986,130.866,"trim","L",1,""},
		{"Zip","B",0.17,0.07,0.04,0.551,0.697,0.421,-20.769,18.722,139.757,"trim","L",1,""},
		{"Zip","B",0.167,0.07,0.04,0.443,0.785,0.421,-23.038,15.022,148.638,"trim","L",1,""},
		{"Zip","B",0.165,0.07,0.04,0.325,0.852,0.421,-24.74,10.978,157.546,"trim","L",1,""},
		{"Zip","B",0.164,0.07,0.04,0.198,0.898,0.421,-25.872,6.686,166.499,"trim","L",1,""},
		{"Zip","B",0.163,0.07,0.04,0.067,0.922,0.421,-26.437,2.245,175.494,"trim","L",1,""},
		{"Zip","B",0.163,0.07,0.04,-0.067,0.922,0.421,-26.437,-2.245,-175.494,"trim","L",1,""},
		{"Zip","B",0.164,0.07,0.04,-0.198,0.898,0.421,-25.872,-6.686,-166.499,"trim","L",1,""},
		{"Zip","B",0.165,0.07,0.04,-0.325,0.852,0.421,-24.74,-10.978,-157.546,"trim","L",1,""},
		{"Zip","B",0.167,0.07,0.04,-0.443,0.785,0.421,-23.038,-15.022,-148.638,"trim","L",1,""},
		{"Zip","B",0.17,0.07,0.04,-0.551,0.697,0.421,-20.769,-18.722,-139.757,"trim","L",1,""},
		{"Zip","B",0.172,0.07,0.04,-0.645,0.592,0.421,-17.948,-21.986,-130.866,"trim","L",1,""},
		{"Zip","B",0.175,0.07,0.04,-0.723,0.472,0.421,-14.606,-24.726,-121.924,"trim","L",1,""},
		{"Zip","B",0.176,0.07,0.04,-0.783,0.339,0.421,-10.806,-26.862,-112.9,"trim","L",1,""},
		{"ZipPull","B",0.12,0.24,0.05,0.608,0.554,0.47,-14.723,18.485,4.763,"metal","M",1,""},
		{"FrontPocket","E",1.302,0.846,0.52,0,-0.588,0.471,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.367,0.423,0.56,0,-0.384,0.476,0,0,0,"flap","L",1,""},
		{"PocketZip","B",0.167,0.065,0.035,-0.482,-0.482,0.642,-13.421,-24.309,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.167,0.065,0.035,-0.344,-0.482,0.69,-10.486,-14.197,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.167,0.065,0.035,-0.206,-0.482,0.717,-9.342,-7.711,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.167,0.065,0.035,-0.069,-0.488,0.73,-8.448,-2.457,-4.144,{18,18,22},"P",1,""},
		{"PocketZip","B",0.167,0.065,0.035,0.069,-0.488,0.73,-8.448,2.457,4.144,{18,18,22},"P",1,""},
		{"PocketZip","B",0.167,0.065,0.035,0.206,-0.482,0.717,-9.342,7.711,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.167,0.065,0.035,0.344,-0.482,0.69,-10.486,14.197,0,{18,18,22},"P",1,""},
		{"PocketZip","B",0.167,0.065,0.035,0.482,-0.482,0.642,-13.421,24.309,0,{18,18,22},"P",1,""},
		{"PocketZipPull","B",0.1,0.2,0.04,0.279,-0.594,0.736,0.569,10.473,-0.103,"metal","M",1,""},
		{"Stitch","B",0.064,0.028,0.02,-0.415,-0.901,0.552,56.67,-25.409,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,-0.296,-0.9,0.617,39.953,-14.616,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,-0.177,-0.899,0.647,34.693,-7.896,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,-0.059,-0.899,0.66,32.747,-2.516,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,0.059,-0.899,0.66,32.747,2.516,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,0.177,-0.899,0.647,34.693,7.896,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,0.296,-0.9,0.617,39.953,14.616,0,"thread","P",1,""},
		{"Stitch","B",0.064,0.028,0.02,0.415,-0.901,0.552,56.67,25.409,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,-0.77,-0.935,0.338,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,-0.63,-0.935,0.338,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,-0.495,-0.942,0.344,38.328,-22.66,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,-0.354,-0.945,0.524,69.389,-21.703,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,-0.212,-0.944,0.601,47.043,-10.577,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,-0.071,-0.943,0.625,42.043,-3.26,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,0.071,-0.943,0.625,42.043,3.26,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,0.212,-0.944,0.601,47.043,10.577,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,0.354,-0.945,0.524,69.389,21.703,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,0.495,-0.942,0.344,38.328,22.66,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,0.63,-0.935,0.338,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.077,0.028,0.02,0.77,-0.935,0.338,0,0,0,"thread","P",1,""},
		{"Handle","C",0.124,0.12,0.12,0.291,1.216,-0.122,0,0,102.43,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,0.256,1.293,-0.122,0,0,125.818,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,0.19,1.356,-0.122,0,0,146.127,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,0.101,1.397,-0.122,0,0,163.766,"trim","L",0.5,""},
		{"Handle","C",0.144,0.12,0.12,0,1.411,-0.122,0,0,-180,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,-0.101,1.397,-0.122,0,0,-163.766,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,-0.19,1.356,-0.122,0,0,-146.127,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,-0.256,1.293,-0.122,0,0,-125.818,"trim","L",0.5,""},
		{"Handle","C",0.124,0.12,0.12,-0.291,1.216,-0.122,0,0,-102.43,"trim","L",0.5,""},
		{"EmblemDiamond","B",0.42,0.42,0.05,0,0.473,0.563,-9,0,45,"fit","P",1,""},
	},
	[6] = {
		{"BodyCore","B",2.2,1.445,0.953,0,-0.165,-0.105,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",1.012,0.594,0.953,0,0.854,-0.105,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.672,0.264,0.953,0,-1.019,-0.105,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.953,1.188,1.188,-0.506,0.557,-0.105,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.953,0.528,0.528,-0.836,-0.887,-0.105,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.796,0.877,-1.04,-0.069,-0.105,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.66,1.52,0.16,-0.484,0.046,-0.551,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.953,1.188,1.188,0.506,0.557,-0.105,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.953,0.528,0.528,0.836,-0.887,-0.105,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.796,0.877,1.04,-0.069,-0.105,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.66,1.52,0.16,0.484,0.046,-0.551,0,0,0,"trim","L",0,""},
		{"Body","E",2.112,2.211,0.837,0,-0.023,0.233,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",2.244,0.34,1.14,0,-1.051,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.226,0.08,0.08,1.085,0.649,0.372,0,0,99,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,1.029,0.824,0.372,0,0,117,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,0.921,0.972,0.372,0,0,135,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,0.772,1.08,0.372,0,0,153,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,0.598,1.137,0.372,0,0,171,"welt","L",1,""},
		{"Welt","C",1.052,0.08,0.08,0,1.151,0.372,0,0,-180,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,-0.598,1.137,0.372,0,0,-171,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,-0.772,1.08,0.372,0,0,-153,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,-0.921,0.972,0.372,0,0,-135,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,-1.029,0.824,0.372,0,0,-117,"welt","L",1,""},
		{"Welt","C",0.226,0.08,0.08,-1.085,0.649,0.372,0,0,-99,"welt","L",1,""},
		{"Welt","C",1.485,0.08,0.08,-1.1,-0.165,0.372,0,0,-90,"welt","L",1,""},
		{"Welt","C",0.177,0.08,0.08,-1.082,-0.954,0.372,0,0,-75,"welt","L",1,""},
		{"Welt","C",0.177,0.08,0.08,-1.016,-1.068,0.372,0,0,-45,"welt","L",1,""},
		{"Welt","C",0.177,0.08,0.08,-0.902,-1.134,0.372,0,0,-15,"welt","L",1,""},
		{"Welt","C",1.712,0.08,0.08,0,-1.151,0.372,0,0,0,"welt","L",1,""},
		{"Welt","C",0.177,0.08,0.08,0.902,-1.134,0.372,0,0,15,"welt","L",1,""},
		{"Welt","C",0.177,0.08,0.08,1.016,-1.068,0.372,0,0,45,"welt","L",1,""},
		{"Welt","C",0.177,0.08,0.08,1.082,-0.954,0.372,0,0,75,"welt","L",1,""},
		{"Welt","C",1.485,0.08,0.08,1.1,-0.165,0.372,0,0,90,"welt","L",1,""},
		{"Zip","B",0.175,0.07,0.04,0.821,0.333,0.468,-12.518,28.713,114.804,"trim","L",1,""},
		{"Zip","B",0.174,0.07,0.04,0.758,0.463,0.468,-16.864,26.362,124.321,"trim","L",1,""},
		{"Zip","B",0.173,0.07,0.04,0.676,0.581,0.468,-20.646,23.372,133.526,"trim","L",1,""},
		{"Zip","B",0.172,0.07,0.04,0.577,0.684,0.468,-23.806,19.843,142.424,"trim","L",1,""},
		{"Zip","B",0.171,0.07,0.04,0.464,0.77,0.468,-26.321,15.878,151.055,"trim","L",1,""},
		{"Zip","B",0.17,0.07,0.04,0.34,0.836,0.468,-28.192,11.577,159.474,"trim","L",1,""},
		{"Zip","B",0.17,0.07,0.04,0.207,0.881,0.469,-29.429,7.04,167.744,"trim","L",1,""},
		{"Zip","B",0.169,0.07,0.04,0.07,0.904,0.469,-30.045,2.362,175.924,"trim","L",1,""},
		{"Zip","B",0.169,0.07,0.04,-0.07,0.904,0.469,-30.045,-2.362,-175.924,"trim","L",1,""},
		{"Zip","B",0.17,0.07,0.04,-0.207,0.881,0.469,-29.429,-7.04,-167.744,"trim","L",1,""},
		{"Zip","B",0.17,0.07,0.04,-0.34,0.836,0.468,-28.192,-11.577,-159.474,"trim","L",1,""},
		{"Zip","B",0.171,0.07,0.04,-0.464,0.77,0.468,-26.321,-15.878,-151.055,"trim","L",1,""},
		{"Zip","B",0.172,0.07,0.04,-0.577,0.684,0.468,-23.806,-19.843,-142.424,"trim","L",1,""},
		{"Zip","B",0.173,0.07,0.04,-0.676,0.581,0.468,-20.646,-23.372,-133.526,"trim","L",1,""},
		{"Zip","B",0.174,0.07,0.04,-0.758,0.463,0.468,-16.864,-26.362,-124.321,"trim","L",1,""},
		{"Zip","B",0.175,0.07,0.04,-0.821,0.333,0.468,-12.518,-28.713,-114.804,"trim","L",1,""},
		{"ZipPull","B",0.12,0.24,0.05,0.637,0.542,0.522,-16.903,19.751,5.863,"metal","M",1,""},
		{"FrontPocket","E",1.364,0.829,0.52,0,-0.576,0.535,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.432,0.415,0.56,0,-0.377,0.54,0,0,0,"flap","L",1,""},
		{"Stitch","B",0.079,0.028,0.02,-0.505,-0.427,0.741,23.451,-20.269,-3.867,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,-0.361,-0.431,0.784,21.503,-12.341,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,-0.216,-0.431,0.81,19.546,-6.832,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,-0.072,-0.431,0.822,18.748,-2.197,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,0.072,-0.431,0.822,18.748,2.197,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,0.216,-0.431,0.81,19.546,6.832,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,0.361,-0.431,0.784,21.503,12.341,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,0.505,-0.427,0.741,23.451,20.269,3.867,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,-0.435,-0.883,0.617,57.199,-24.087,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,-0.31,-0.882,0.682,40.523,-13.866,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,-0.186,-0.881,0.711,35.237,-7.492,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,-0.062,-0.881,0.724,33.275,-2.387,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,0.062,-0.881,0.724,33.275,2.387,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,0.186,-0.881,0.711,35.237,7.492,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,0.31,-0.882,0.682,40.523,13.866,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,0.435,-0.883,0.617,57.199,24.087,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.807,-0.911,0.384,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.66,-0.911,0.384,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.518,-0.919,0.385,41.575,-22.79,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.371,-0.922,0.601,65.228,-20.12,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.222,-0.92,0.671,46.042,-9.885,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.074,-0.919,0.694,41.381,-3.054,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.074,-0.919,0.694,41.381,3.054,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.222,-0.92,0.671,46.042,9.885,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.371,-0.922,0.601,65.228,20.12,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.518,-0.919,0.385,41.575,22.79,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.66,-0.911,0.384,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.807,-0.911,0.384,0,0,0,"thread","P",1,""},
		{"SidePocket","E",0.46,0.921,0.744,-1.16,-0.507,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.392,0.791,-1.16,-0.207,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.921,0.12,-1.395,-0.507,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.934,-1.175,0.461,-0.105,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,-1.19,0.461,0.134,0,0,0,"metal","M",1,""},
		{"SidePocket","E",0.46,0.921,0.744,1.16,-0.507,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.392,0.791,1.16,-0.207,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.921,0.12,1.395,-0.507,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.934,1.175,0.461,-0.105,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,1.19,0.461,0.134,0,0,0,"metal","M",1,""},
		{"Handle","C",0.124,0.12,0.12,0.291,1.193,-0.14,0,0,102.43,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,0.256,1.27,-0.14,0,0,125.818,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,0.19,1.333,-0.14,0,0,146.127,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,0.101,1.374,-0.14,0,0,163.766,"trim","L",0.5,""},
		{"Handle","C",0.144,0.12,0.12,0,1.388,-0.14,0,0,-180,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,-0.101,1.374,-0.14,0,0,-163.766,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,-0.19,1.333,-0.14,0,0,-146.127,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,-0.256,1.27,-0.14,0,0,-125.818,"trim","L",0.5,""},
		{"Handle","C",0.124,0.12,0.12,-0.291,1.193,-0.14,0,0,-102.43,"trim","L",0.5,""},
		{"Molle","B",0.33,0.06,0.04,-0.566,0.789,0.423,-32.623,-22.351,-13.68,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,-0.188,0.788,0.521,-22.671,-5.596,-2.333,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,0.188,0.788,0.521,-22.671,5.596,2.333,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,0.566,0.789,0.423,-32.623,22.351,13.68,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,-0.564,0.556,0.524,-16.444,-16.818,-4.881,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,-0.188,0.555,0.594,-13.288,-4.677,-1.103,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,0.188,0.555,0.594,-13.288,4.677,1.103,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,0.564,0.556,0.524,-16.444,16.818,4.881,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,-0.564,0.324,0.574,-8.546,-14.813,-2.2,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,-0.188,0.324,0.635,-7.227,-4.267,-0.541,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,0.188,0.324,0.635,-7.227,4.267,0.541,"welt","L",1,""},
		{"Molle","B",0.33,0.06,0.04,0.564,0.324,0.574,-8.546,14.813,2.2,"welt","L",1,""},
		{"MagPouch","E",0.42,0.56,0.24,-0.493,-0.624,0.82,4.727,-19.295,1.565,{46,48,52},"F",1,""},
		{"PouchFlap","E",0.44,0.2,0.26,-0.464,-0.374,1.012,-24.581,-2.524,-1.154,{40,42,46},"F",1,""},
		{"PouchBuckle","B",0.14,0.1,0.05,-0.46,-0.505,1.03,76.679,-0.049,0.205,"metal","M",1,""},
		{"MagPouch","E",0.42,0.56,0.24,0,-0.622,0.894,3.48,0,0,{46,48,52},"F",1,""},
		{"PouchFlap","E",0.44,0.2,0.26,0,-0.377,1.078,-22.745,0,0,{40,42,46},"F",1,""},
		{"PouchBuckle","B",0.14,0.1,0.05,0,-0.505,1.106,73.841,0,0,"metal","M",1,""},
		{"MagPouch","E",0.42,0.56,0.24,0.493,-0.624,0.82,4.727,19.295,-1.565,{46,48,52},"F",1,""},
		{"PouchFlap","E",0.44,0.2,0.26,0.464,-0.374,1.012,-24.581,2.524,1.154,{40,42,46},"F",1,""},
		{"PouchBuckle","B",0.14,0.1,0.05,0.46,-0.505,1.03,76.679,0.049,-0.205,"metal","M",1,""},
		{"MolleSideBuckle","B",0.16,0.12,0.05,-0.669,0.561,0.544,-16.444,-16.818,-4.881,"metal","M",1,""},
		{"MolleSideBuckle","B",0.16,0.12,0.05,0.67,0.561,0.565,-16.903,19.751,5.863,"metal","M",1,""},
	},
	[7] = {
		{"BodyCore","B",2.04,1.789,0.795,0,-0.153,-0.087,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",0.938,0.551,0.795,0,1.017,-0.087,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.55,0.245,0.795,0,-1.17,-0.087,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.795,1.102,1.102,-0.469,0.742,-0.087,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.795,0.49,0.49,-0.775,-1.048,-0.087,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,2.016,0.731,-0.96,-0.078,-0.087,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.612,1.706,0.16,-0.449,0.052,-0.455,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.795,1.102,1.102,0.469,0.742,-0.087,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.795,0.49,0.49,0.775,-1.048,-0.087,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,2.016,0.731,0.96,-0.078,-0.087,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.612,1.706,0.16,0.449,0.052,-0.455,0,0,0,"trim","L",0,""},
		{"Body","E",1.958,2.482,0.698,0,-0.026,0.206,0,0,0,{26,28,34},"L",0.5,"TI"},
		{"BasePanel","E",2.081,0.34,0.95,0,-1.193,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.212,0.07,0.07,1.007,0.827,0.31,0,0,99,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,0.954,0.989,0.31,0,0,117,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,0.854,1.126,0.31,0,0,135,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,0.716,1.226,0.31,0,0,153,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,0.554,1.279,0.31,0,0,171,"fit","N",1,""},
		{"Welt","C",0.978,0.07,0.07,0,1.293,0.31,0,0,-180,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,-0.554,1.279,0.31,0,0,-171,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,-0.716,1.226,0.31,0,0,-153,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,-0.854,1.126,0.31,0,0,-135,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,-0.954,0.989,0.31,0,0,-117,"fit","N",1,""},
		{"Welt","C",0.212,0.07,0.07,-1.007,0.827,0.31,0,0,-99,"fit","N",1,""},
		{"Welt","C",1.829,0.07,0.07,-1.02,-0.153,0.31,0,0,-90,"fit","N",1,""},
		{"Welt","C",0.167,0.07,0.07,-1.004,-1.109,0.31,0,0,-75,"fit","N",1,""},
		{"Welt","C",0.167,0.07,0.07,-0.942,-1.215,0.31,0,0,-45,"fit","N",1,""},
		{"Welt","C",0.167,0.07,0.07,-0.836,-1.276,0.31,0,0,-15,"fit","N",1,""},
		{"Welt","C",1.59,0.07,0.07,0,-1.293,0.31,0,0,0,"fit","N",1,""},
		{"Welt","C",0.167,0.07,0.07,0.836,-1.276,0.31,0,0,15,"fit","N",1,""},
		{"Welt","C",0.167,0.07,0.07,0.942,-1.215,0.31,0,0,45,"fit","N",1,""},
		{"Welt","C",0.167,0.07,0.07,1.004,-1.109,0.31,0,0,75,"fit","N",1,""},
		{"Welt","C",1.829,0.07,0.07,1.02,-0.153,0.31,0,0,90,"fit","N",1,""},
		{"FrontPocket","E",1.265,0.931,0.52,0,-0.646,0.448,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.328,0.465,0.56,0,-0.423,0.453,0,0,0,"flap","L",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.469,-0.487,0.65,24.638,-21.903,-4.167,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.335,-0.491,0.693,22.015,-13.393,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.201,-0.491,0.72,19.975,-7.418,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,-0.067,-0.491,0.732,19.147,-2.386,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.067,-0.491,0.732,19.147,2.386,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.201,-0.491,0.72,19.975,7.418,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.335,-0.491,0.693,22.015,13.393,0,"thread","P",1,""},
		{"Stitch","B",0.073,0.028,0.02,0.469,-0.487,0.65,24.638,21.903,4.167,"thread","P",1,""},
		{"Stitch","B",0.063,0.028,0.02,-0.404,-0.99,0.53,54.119,-27.548,0,"thread","P",1,""},
		{"Stitch","B",0.063,0.028,0.02,-0.288,-0.988,0.594,37.291,-15.568,0,"thread","P",1,""},
		{"Stitch","B",0.063,0.028,0.02,-0.172,-0.988,0.624,32.183,-8.36,0,"thread","P",1,""},
		{"Stitch","B",0.063,0.028,0.02,-0.057,-0.987,0.637,30.314,-2.658,0,"thread","P",1,""},
		{"Stitch","B",0.063,0.028,0.02,0.057,-0.987,0.637,30.314,2.658,0,"thread","P",1,""},
		{"Stitch","B",0.063,0.028,0.02,0.172,-0.988,0.624,32.183,8.36,0,"thread","P",1,""},
		{"Stitch","B",0.063,0.028,0.02,0.288,-0.988,0.594,37.291,15.568,0,"thread","P",1,""},
		{"Stitch","B",0.063,0.028,0.02,0.404,-0.99,0.53,54.119,27.548,0,"thread","P",1,""},
		{"PocketGlow","B",0.696,0.06,0.04,0,-0.483,0.744,16.072,0,0,"fit","N",1,""},
		{"Stitch","B",0.075,0.028,0.02,-0.748,-1.053,0.322,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,-0.612,-1.053,0.322,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,-0.476,-1.053,0.322,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,-0.343,-1.058,0.37,27.79,-13.924,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,-0.207,-1.062,0.55,53.154,-12.273,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,-0.069,-1.061,0.58,45.732,-3.713,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,0.069,-1.061,0.58,45.732,3.713,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,0.207,-1.062,0.55,53.154,12.273,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,0.343,-1.058,0.37,27.79,13.924,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,0.476,-1.053,0.322,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,0.612,-1.053,0.322,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.075,0.028,0.02,0.748,-1.053,0.322,0,0,0,"thread","P",1,""},
		{"Handle","C",0.124,0.12,0.12,0.291,1.334,-0.116,0,0,102.43,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,0.256,1.411,-0.116,0,0,125.818,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,0.19,1.474,-0.116,0,0,146.127,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,0.101,1.515,-0.116,0,0,163.766,"trim","L",0.5,""},
		{"Handle","C",0.144,0.12,0.12,0,1.529,-0.116,0,0,-180,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,-0.101,1.515,-0.116,0,0,-163.766,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,-0.19,1.474,-0.116,0,0,-146.127,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,-0.256,1.411,-0.116,0,0,-125.818,"trim","L",0.5,""},
		{"Handle","C",0.124,0.12,0.12,-0.291,1.334,-0.116,0,0,-102.43,"trim","L",0.5,""},
		{"StarPlate","B",0.74,0.74,0.03,0,0.467,0.536,-6.91,0,0,{18,20,26},"P",1,""},
		{"StarFrameT","B",0.78,0.06,0.05,0,0.83,0.479,-14.845,0,0,"fit","N",1,""},
		{"StarFrameB","B",0.78,0.06,0.05,0,0.106,0.573,-1.712,0,0,"fit","N",1,""},
		{"StarFrameL","B",0.06,0.78,0.05,-0.363,0.468,0.519,-7.533,-8.771,-1.155,"fit","N",1,""},
		{"StarFrameR","B",0.06,0.78,0.05,0.363,0.468,0.519,-7.533,8.771,1.155,"fit","N",1,""},
		{"StarRayV","B",0.08,0.6,0.04,0,0.469,0.581,-6.91,0,0,"fit","N",1,""},
		{"StarRayH","B",0.6,0.08,0.04,0,0.469,0.583,-6.91,0,0,"fit","N",1,""},
		{"StarCore","B",0.2,0.2,0.045,0,0.469,0.585,-6.91,0,45,"fit","N",1,""},
		{"SideTube","C",1.81,0.1,0.1,-1.1,-0.052,0.151,0,0,90,"fit","N",0.5,""},
		{"SideTube","C",1.81,0.1,0.1,1.1,-0.052,0.151,0,0,90,"fit","N",0.5,""},
		{"NeonSeam","B",0.05,0.259,0.03,-0.816,-0.776,0.316,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,-0.82,-0.518,0.345,16.089,-36.475,9.729,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,-0.819,-0.259,0.392,5.788,-29.597,2.866,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,-0.819,0,0.404,-0.608,-28.254,-0.288,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,-0.819,0.259,0.386,-7.299,-30.344,-3.702,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,-0.82,0.519,0.328,-20.004,-39.546,-13.05,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,-0.816,0.776,0.316,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,0.816,-0.776,0.316,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,0.82,-0.518,0.345,16.089,36.475,-9.729,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,0.819,-0.259,0.392,5.788,29.597,-2.866,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,0.819,0,0.404,-0.608,28.254,0.288,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,0.819,0.259,0.386,-7.299,30.344,3.702,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,0.82,0.519,0.328,-20.004,39.546,13.05,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.259,0.03,0.816,0.776,0.316,0,0,0,"fit","N",1,""},
	},
	[8] = {
		{"BodyCore","B",2.12,1.617,0.836,0,-0.159,-0.092,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",0.975,0.572,0.836,0,0.936,-0.092,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.611,0.254,0.836,0,-1.095,-0.092,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,1.145,1.145,-0.488,0.65,-0.092,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,0.509,0.509,-0.806,-0.968,-0.092,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.906,0.769,-1,-0.073,-0.092,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.636,1.613,0.16,-0.466,0.049,-0.48,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.836,1.145,1.145,0.488,0.65,-0.092,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.836,0.509,0.509,0.806,-0.968,-0.092,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.906,0.769,1,-0.073,-0.092,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.636,1.613,0.16,0.466,0.049,-0.48,0,0,0,"trim","L",0,""},
		{"Body","E",2.035,2.346,0.734,0,-0.024,0.213,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",2.162,0.34,1,0,-1.122,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.219,0.07,0.07,1.046,0.738,0.326,0,0,99,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,0.991,0.906,0.326,0,0,117,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,0.887,1.049,0.326,0,0,135,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,0.744,1.153,0.326,0,0,153,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,0.576,1.208,0.326,0,0,171,"fit","N",1,""},
		{"Welt","C",1.015,0.07,0.07,0,1.222,0.326,0,0,-180,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,-0.576,1.208,0.326,0,0,-171,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,-0.744,1.153,0.326,0,0,-153,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,-0.887,1.049,0.326,0,0,-135,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,-0.991,0.906,0.326,0,0,-117,"fit","N",1,""},
		{"Welt","C",0.219,0.07,0.07,-1.046,0.738,0.326,0,0,-99,"fit","N",1,""},
		{"Welt","C",1.657,0.07,0.07,-1.06,-0.159,0.326,0,0,-90,"fit","N",1,""},
		{"Welt","C",0.172,0.07,0.07,-1.043,-1.031,0.326,0,0,-75,"fit","N",1,""},
		{"Welt","C",0.172,0.07,0.07,-0.979,-1.141,0.326,0,0,-45,"fit","N",1,""},
		{"Welt","C",0.172,0.07,0.07,-0.869,-1.205,0.326,0,0,-15,"fit","N",1,""},
		{"Welt","C",1.651,0.07,0.07,0,-1.222,0.326,0,0,0,"fit","N",1,""},
		{"Welt","C",0.172,0.07,0.07,0.869,-1.205,0.326,0,0,15,"fit","N",1,""},
		{"Welt","C",0.172,0.07,0.07,0.979,-1.141,0.326,0,0,45,"fit","N",1,""},
		{"Welt","C",0.172,0.07,0.07,1.043,-1.031,0.326,0,0,75,"fit","N",1,""},
		{"Welt","C",1.657,0.07,0.07,1.06,-0.159,0.326,0,0,90,"fit","N",1,""},
		{"FrontPocket","E",1.314,0.88,0.52,0,-0.611,0.471,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.38,0.44,0.56,0,-0.4,0.476,0,0,0,"flap","L",1,""},
		{"Stitch","B",0.076,0.028,0.02,-0.487,-0.457,0.675,24.161,-21.045,-4.006,"thread","P",1,""},
		{"Stitch","B",0.076,0.028,0.02,-0.348,-0.461,0.718,21.841,-12.843,0,"thread","P",1,""},
		{"Stitch","B",0.076,0.028,0.02,-0.209,-0.461,0.744,19.836,-7.112,0,"thread","P",1,""},
		{"Stitch","B",0.076,0.028,0.02,-0.069,-0.461,0.756,19.021,-2.287,0,"thread","P",1,""},
		{"Stitch","B",0.076,0.028,0.02,0.069,-0.461,0.756,19.021,2.287,0,"thread","P",1,""},
		{"Stitch","B",0.076,0.028,0.02,0.209,-0.461,0.744,19.836,7.112,0,"thread","P",1,""},
		{"Stitch","B",0.076,0.028,0.02,0.348,-0.461,0.718,21.841,12.843,0,"thread","P",1,""},
		{"Stitch","B",0.076,0.028,0.02,0.487,-0.457,0.675,24.161,21.045,4.006,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,-0.419,-0.937,0.553,55.631,-25.802,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,-0.299,-0.935,0.617,38.851,-14.705,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,-0.179,-0.934,0.647,33.649,-7.918,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,-0.06,-0.934,0.66,31.733,-2.52,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,0.06,-0.934,0.66,31.733,2.52,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,0.179,-0.934,0.647,33.649,7.918,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,0.299,-0.935,0.617,38.851,14.705,0,"thread","P",1,""},
		{"Stitch","B",0.065,0.028,0.02,0.419,-0.937,0.553,55.631,25.802,0,"thread","P",1,""},
		{"PocketGlow","B",0.723,0.06,0.04,0,-0.452,0.769,15.628,0,0,"fit","N",1,""},
		{"Stitch","B",0.078,0.028,0.02,-0.777,-0.982,0.338,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,-0.636,-0.982,0.338,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,-0.499,-0.989,0.336,39.301,-23.503,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,-0.356,-0.988,0.393,28.959,-13.357,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,-0.214,-0.991,0.59,49.228,-10.974,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,-0.071,-0.99,0.616,43.43,-3.358,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,0.071,-0.99,0.616,43.43,3.358,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,0.214,-0.991,0.59,49.228,10.974,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,0.356,-0.988,0.393,28.959,13.357,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,0.499,-0.989,0.336,39.301,23.503,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,0.636,-0.982,0.338,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.078,0.028,0.02,0.777,-0.982,0.338,0,0,0,"thread","P",1,""},
		{"SidePocket","E",0.46,0.978,0.653,-1.12,-0.538,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.415,0.694,-1.12,-0.22,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.978,0.12,-1.355,-0.538,0,0,0,0,"fit","N",1,""},
		{"CompressionStrap","B",0.05,0.12,0.82,-1.135,0.489,-0.092,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,-1.15,0.489,0.117,0,0,0,"metal","M",1,""},
		{"SidePocketNeon","B",0.05,0.05,0.612,-1.355,-0.049,0,0,0,0,"fit","N",1,""},
		{"SidePocket","E",0.46,0.978,0.653,1.12,-0.538,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.415,0.694,1.12,-0.22,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.978,0.12,1.355,-0.538,0,0,0,0,"fit","N",1,""},
		{"CompressionStrap","B",0.05,0.12,0.82,1.135,0.489,-0.092,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,1.15,0.489,0.117,0,0,0,"metal","M",1,""},
		{"SidePocketNeon","B",0.05,0.05,0.612,1.355,-0.049,0,0,0,0,"fit","N",1,""},
		{"Handle","C",0.124,0.12,0.12,0.291,1.263,-0.122,0,0,102.43,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,0.256,1.34,-0.122,0,0,125.818,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,0.19,1.403,-0.122,0,0,146.127,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,0.101,1.444,-0.122,0,0,163.766,"trim","L",0.5,""},
		{"Handle","C",0.144,0.12,0.12,0,1.458,-0.122,0,0,-180,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,-0.101,1.444,-0.122,0,0,-163.766,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,-0.19,1.403,-0.122,0,0,-146.127,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,-0.256,1.34,-0.122,0,0,-125.818,"trim","L",0.5,""},
		{"Handle","C",0.124,0.12,0.12,-0.291,1.263,-0.122,0,0,-102.43,"trim","L",0.5,""},
		{"OctoNeon","B",0.501,0.06,0.04,0.473,0.688,0.458,-16.317,13.902,147.37,"fit","N",1,""},
		{"OctoNeon","B",0.582,0.06,0.04,0,0.821,0.476,-17.908,0,-180,"fit","N",1,""},
		{"OctoNeon","B",0.501,0.06,0.04,-0.473,0.688,0.458,-16.317,-13.902,-147.37,"fit","N",1,""},
		{"OctoNeon","B",0.404,0.06,0.04,-0.669,0.368,0.469,-8.74,-18.978,-92.862,"fit","N",1,""},
		{"OctoNeon","B",0.501,0.06,0.04,-0.472,0.047,0.545,-1.24,-10.69,-34.678,"fit","N",1,""},
		{"OctoNeon","B",0.582,0.06,0.04,0,-0.085,0.588,0.927,0,0,"fit","N",1,""},
		{"OctoNeon","B",0.501,0.06,0.04,0.472,0.047,0.545,-1.24,10.69,34.678,"fit","N",1,""},
		{"OctoNeon","B",0.404,0.06,0.04,0.669,0.368,0.469,-8.74,18.978,92.862,"fit","N",1,""},
		{"CrownBase","B",0.46,0.09,0.05,0,0.268,0.588,-4.583,0,0,"fit","N",1,""},
		{"CrownSpike","B",0.08,0.26,0.05,-0.181,0.399,0.569,-6.989,-3.955,13.516,"fit","N",1,""},
		{"CrownJewel","S",0.1,0.1,0.1,-0.214,0.552,0.554,-10.181,-4.971,-0.892,"fit","N",1,""},
		{"CrownSpike","B",0.08,0.32,0.05,0,0.429,0.572,-7.428,0,0,"fit","N",1,""},
		{"CrownJewel","S",0.1,0.1,0.1,0,0.612,0.552,-11.295,0,0,"fit","N",1,""},
		{"CrownSpike","B",0.08,0.26,0.05,0.181,0.399,0.569,-6.989,3.955,-13.516,"fit","N",1,""},
		{"CrownJewel","S",0.1,0.1,0.1,0.214,0.552,0.554,-10.181,4.971,0.892,"fit","N",1,""},
		{"TinyStarV","B",0.04,0.16,0.03,-0.636,0.978,0.338,0,0,0,"fit","N",1,""},
		{"TinyStarH","B",0.16,0.04,0.03,-0.636,0.978,0.34,0,0,0,"fit","N",1,""},
		{"TinyStarV","B",0.04,0.16,0.03,0.636,0.978,0.338,0,0,0,"fit","N",1,""},
		{"TinyStarH","B",0.16,0.04,0.03,0.636,0.978,0.34,0,0,0,"fit","N",1,""},
		{"TinyStarV","B",0.04,0.16,0.03,0.811,-0.049,0.448,0.612,25.072,-0.259,"fit","N",1,""},
		{"TinyStarH","B",0.16,0.04,0.03,0.812,-0.049,0.45,0.612,25.072,-0.259,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,-0.848,-0.733,0.332,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,-0.852,-0.49,0.359,17.803,-36.577,10.833,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,-0.851,-0.245,0.409,6.439,-29.883,3.219,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,-0.851,0,0.421,-0.676,-28.562,-0.323,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,-0.851,0.245,0.403,-8.116,-30.617,-4.154,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,-0.852,0.491,0.341,-22.064,-39.518,-14.462,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,-0.848,0.733,0.332,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,0.848,-0.733,0.332,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,0.852,-0.49,0.359,17.803,36.577,-10.833,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,0.851,-0.245,0.409,6.439,29.883,-3.219,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,0.851,0,0.421,-0.676,28.562,0.323,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,0.851,0.245,0.403,-8.116,30.617,4.154,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,0.852,0.491,0.341,-22.064,39.518,14.462,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.244,0.03,0.848,0.733,0.332,0,0,0,"fit","N",1,""},
	},
	[9] = {
		{"BodyCore","B",2.28,1.602,0.937,0,-0.171,-0.103,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",1.049,0.616,0.937,0,0.938,-0.103,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.733,0.274,0.937,0,-1.109,-0.103,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.937,1.231,1.231,-0.524,0.63,-0.103,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.937,0.547,0.547,-0.866,-0.972,-0.103,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.943,0.862,-1.08,-0.075,-0.103,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.684,1.644,0.16,-0.502,0.05,-0.541,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.937,1.231,1.231,0.524,0.63,-0.103,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.937,0.547,0.547,0.866,-0.972,-0.103,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,1.943,0.862,1.08,-0.075,-0.103,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.684,1.644,0.16,0.502,0.05,-0.541,0,0,0,"trim","L",0,""},
		{"Body","E",2.189,2.391,0.823,0,-0.025,0.23,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",2.326,0.34,1.12,0,-1.145,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.233,0.07,0.07,1.125,0.725,0.366,0,0,99,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,1.066,0.906,0.366,0,0,117,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,0.954,1.06,0.366,0,0,135,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,0.8,1.172,0.366,0,0,153,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,0.62,1.23,0.366,0,0,171,"fit","N",1,""},
		{"Welt","C",1.089,0.07,0.07,0,1.246,0.366,0,0,-180,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,-0.62,1.23,0.366,0,0,-171,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,-0.8,1.172,0.366,0,0,-153,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,-0.954,1.06,0.366,0,0,-135,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,-1.066,0.906,0.366,0,0,-117,"fit","N",1,""},
		{"Welt","C",0.233,0.07,0.07,-1.125,0.725,0.366,0,0,-99,"fit","N",1,""},
		{"Welt","C",1.642,0.07,0.07,-1.14,-0.171,0.366,0,0,-90,"fit","N",1,""},
		{"Welt","C",0.182,0.07,0.07,-1.122,-1.04,0.366,0,0,-75,"fit","N",1,""},
		{"Welt","C",0.182,0.07,0.07,-1.053,-1.159,0.366,0,0,-45,"fit","N",1,""},
		{"Welt","C",0.182,0.07,0.07,-0.935,-1.227,0.366,0,0,-15,"fit","N",1,""},
		{"Welt","C",1.773,0.07,0.07,0,-1.246,0.366,0,0,0,"fit","N",1,""},
		{"Welt","C",0.182,0.07,0.07,0.935,-1.227,0.366,0,0,15,"fit","N",1,""},
		{"Welt","C",0.182,0.07,0.07,1.053,-1.159,0.366,0,0,45,"fit","N",1,""},
		{"Welt","C",0.182,0.07,0.07,1.122,-1.04,0.366,0,0,75,"fit","N",1,""},
		{"Welt","C",1.642,0.07,0.07,1.14,-0.171,0.366,0,0,90,"fit","N",1,""},
		{"FrontPocket","E",1.414,0.897,0.52,0,-0.623,0.526,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.484,0.448,0.56,0,-0.408,0.531,0,0,0,"flap","L",1,""},
		{"Stitch","B",0.082,0.028,0.02,-0.524,-0.463,0.731,22.855,-19.782,-3.74,"thread","P",1,""},
		{"Stitch","B",0.082,0.028,0.02,-0.374,-0.468,0.774,20.689,-12.018,0,"thread","P",1,""},
		{"Stitch","B",0.082,0.028,0.02,-0.224,-0.468,0.8,18.784,-6.641,0,"thread","P",1,""},
		{"Stitch","B",0.082,0.028,0.02,-0.075,-0.467,0.812,18.01,-2.134,0,"thread","P",1,""},
		{"Stitch","B",0.082,0.028,0.02,0.075,-0.467,0.812,18.01,2.134,0,"thread","P",1,""},
		{"Stitch","B",0.082,0.028,0.02,0.224,-0.468,0.8,18.784,6.641,0,"thread","P",1,""},
		{"Stitch","B",0.082,0.028,0.02,0.374,-0.468,0.774,20.689,12.018,0,"thread","P",1,""},
		{"Stitch","B",0.082,0.028,0.02,0.524,-0.463,0.731,22.855,19.782,3.74,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.45,-0.955,0.608,55.12,-24.483,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.321,-0.953,0.673,38.319,-13.811,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.192,-0.952,0.702,33.147,-7.411,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,-0.064,-0.952,0.715,31.247,-2.355,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.064,-0.952,0.715,31.247,2.355,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.192,-0.952,0.702,33.147,7.411,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.321,-0.953,0.673,38.319,13.811,0,"thread","P",1,""},
		{"Stitch","B",0.07,0.028,0.02,0.45,-0.955,0.608,55.12,24.483,0,"thread","P",1,""},
		{"PocketGlow","B",0.777,0.06,0.04,0,-0.459,0.824,14.734,0,0,"fit","N",1,""},
		{"Stitch","B",0.084,0.028,0.02,-0.836,-1.006,0.378,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,-0.684,-1.006,0.378,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,-0.532,-1.006,0.378,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,-0.383,-1.012,0.427,31.808,-13.702,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,-0.23,-1.015,0.64,50.436,-10.471,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,-0.077,-1.014,0.667,44.163,-3.187,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,0.077,-1.014,0.667,44.163,3.187,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,0.23,-1.015,0.64,50.436,10.471,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,0.383,-1.012,0.427,31.808,13.702,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,0.532,-1.006,0.378,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,0.684,-1.006,0.378,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.084,0.028,0.02,0.836,-1.006,0.378,0,0,0,"thread","P",1,""},
		{"SidePocket","E",0.46,0.996,0.731,-1.2,-0.548,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.423,0.777,-1.2,-0.224,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.996,0.12,-1.435,-0.548,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.918,-1.215,0.498,-0.103,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,-1.23,0.498,0.131,0,0,0,"metal","M",1,""},
		{"SidePocket","E",0.46,0.996,0.731,1.2,-0.548,0,0,0,0,"body","L",1,"T"},
		{"SidePocketFlap","E",0.5,0.423,0.777,1.2,-0.224,0,0,0,0,"flap","L",1,""},
		{"SidePocketStrap","B",0.05,0.996,0.12,1.435,-0.548,0,0,0,0,"trim","L",1,""},
		{"CompressionStrap","B",0.05,0.12,0.918,1.215,0.498,-0.103,0,0,0,"trim","L",1,""},
		{"CompressionBuckle","B",0.07,0.17,0.2,1.23,0.498,0.131,0,0,0,"metal","M",1,""},
		{"Handle","C",0.124,0.12,0.12,0.291,1.287,-0.137,0,0,102.43,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,0.256,1.364,-0.137,0,0,125.818,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,0.19,1.427,-0.137,0,0,146.127,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,0.101,1.468,-0.137,0,0,163.766,"trim","L",0.5,""},
		{"Handle","C",0.144,0.12,0.12,0,1.482,-0.137,0,0,-180,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,-0.101,1.468,-0.137,0,0,-163.766,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,-0.19,1.427,-0.137,0,0,-146.127,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,-0.256,1.364,-0.137,0,0,-125.818,"trim","L",0.5,""},
		{"Handle","C",0.124,0.12,0.12,-0.291,1.287,-0.137,0,0,-102.43,"trim","L",0.5,""},
		{"MagmaVein","B",0.08,0.897,0.04,-0.206,0.4,0.619,-7.574,-4.36,-28.579,"fit","N",1,""},
		{"MagmaVein","B",0.07,0.648,0.04,-0.573,0.05,0.592,-1.446,-12.943,47.676,"fit","N",1,""},
		{"MagmaVein","B",0.07,0.448,0.04,-0.775,0.747,0.378,0,0,-62,"fit","N",1,""},
		{"ShoulderPlate","B",0.684,0.16,0.843,-0.684,1.046,-0.103,0,0,-24,"dark","P",1,""},
		{"ShoulderNeon","B",0.684,0.05,0.05,-0.684,1.106,0.328,0,0,-24,"fit","N",1,""},
		{"MagmaVein","B",0.08,0.897,0.04,0.206,0.4,0.619,-7.574,4.36,28.579,"fit","N",1,""},
		{"MagmaVein","B",0.07,0.648,0.04,0.573,0.05,0.592,-1.446,12.943,-47.676,"fit","N",1,""},
		{"MagmaVein","B",0.07,0.448,0.04,0.775,0.747,0.378,0,0,62,"fit","N",1,""},
		{"ShoulderPlate","B",0.684,0.16,0.843,0.684,1.046,-0.103,0,0,24,"dark","P",1,""},
		{"ShoulderNeon","B",0.684,0.05,0.05,0.684,1.106,0.328,0,0,24,"fit","N",1,""},
		{"MagmaBar","B",1.14,0.06,0.04,0,0.952,0.481,-25.613,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,-0.912,-0.747,0.372,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,-0.916,-0.5,0.393,19.436,-37.43,12.105,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,-0.915,-0.25,0.449,7.07,-30.865,3.641,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,-0.915,0,0.462,-0.743,-29.548,-0.367,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,-0.915,0.25,0.442,-8.906,-31.593,-4.693,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,-0.916,0.5,0.373,-24.008,-40.255,-16.056,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,-0.912,0.747,0.372,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,0.912,-0.747,0.372,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,0.916,-0.5,0.393,19.436,37.43,-12.105,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,0.915,-0.25,0.449,7.07,30.865,-3.641,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,0.915,0,0.462,-0.743,29.548,0.367,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,0.915,0.25,0.442,-8.906,31.593,4.693,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,0.916,0.5,0.373,-24.008,40.255,16.056,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.249,0.03,0.912,0.747,0.372,0,0,0,"fit","N",1,""},
	},
	[10] = {
		{"BodyCore","B",2.2,1.774,0.878,0,-0.165,-0.096,0,0,0,"body","L",0.5,"TI"},
		{"BodyCore","B",1.012,0.594,0.878,0,1.019,-0.096,0,0,0,"body","L",0.5,"T"},
		{"BodyCore","B",1.672,0.264,0.878,0,-1.184,-0.096,0,0,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.878,1.188,1.188,-0.506,0.722,-0.096,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.878,0.528,0.528,-0.836,-1.052,-0.096,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,2.053,0.808,-1.04,-0.079,-0.096,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.66,1.737,0.16,-0.484,0.053,-0.506,0,0,0,"trim","L",0,""},
		{"BodyCorner","C",0.878,1.188,1.188,0.506,0.722,-0.096,0,90,0,"body","L",0.5,"T"},
		{"BodyCorner","C",0.878,0.528,0.528,0.836,-1.052,-0.096,0,90,0,"body","L",0.5,"T"},
		{"SideBulge","E",0.26,2.053,0.808,1.04,-0.079,-0.096,0,0,0,"edge","L",0.5,"T"},
		{"BackPad","E",0.66,1.737,0.16,0.484,0.053,-0.506,0,0,0,"trim","L",0,""},
		{"Body","E",2.112,2.527,0.771,0,-0.026,0.22,0,0,0,"body","L",0.5,"TI"},
		{"BasePanel","E",2.244,0.34,1.05,0,-1.216,-0.03,0,0,0,"trim","L",0.5,""},
		{"Welt","C",0.226,0.07,0.07,1.085,0.814,0.343,0,0,99,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,1.029,0.988,0.343,0,0,117,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,0.921,1.137,0.343,0,0,135,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,0.772,1.245,0.343,0,0,153,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,0.598,1.301,0.343,0,0,171,"fit","N",1,""},
		{"Welt","C",1.052,0.07,0.07,0,1.316,0.343,0,0,-180,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,-0.598,1.301,0.343,0,0,-171,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,-0.772,1.245,0.343,0,0,-153,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,-0.921,1.137,0.343,0,0,-135,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,-1.029,0.988,0.343,0,0,-117,"fit","N",1,""},
		{"Welt","C",0.226,0.07,0.07,-1.085,0.814,0.343,0,0,-99,"fit","N",1,""},
		{"Welt","C",1.814,0.07,0.07,-1.1,-0.165,0.343,0,0,-90,"fit","N",1,""},
		{"Welt","C",0.177,0.07,0.07,-1.082,-1.118,0.343,0,0,-75,"fit","N",1,""},
		{"Welt","C",0.177,0.07,0.07,-1.016,-1.232,0.343,0,0,-45,"fit","N",1,""},
		{"Welt","C",0.177,0.07,0.07,-0.902,-1.298,0.343,0,0,-15,"fit","N",1,""},
		{"Welt","C",1.712,0.07,0.07,0,-1.316,0.343,0,0,0,"fit","N",1,""},
		{"Welt","C",0.177,0.07,0.07,0.902,-1.298,0.343,0,0,15,"fit","N",1,""},
		{"Welt","C",0.177,0.07,0.07,1.016,-1.232,0.343,0,0,45,"fit","N",1,""},
		{"Welt","C",0.177,0.07,0.07,1.082,-1.118,0.343,0,0,75,"fit","N",1,""},
		{"Welt","C",1.814,0.07,0.07,1.1,-0.165,0.343,0,0,90,"fit","N",1,""},
		{"FrontPocket","E",1.364,0.948,0.52,0,-0.658,0.494,0,0,0,"body","L",1,"T"},
		{"PocketFlap","E",1.432,0.474,0.56,0,-0.431,0.499,0,0,0,"flap","L",1,""},
		{"Stitch","B",0.079,0.028,0.02,-0.505,-0.493,0.697,23.397,-20.535,-3.875,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,-0.361,-0.498,0.741,20.928,-12.496,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,-0.216,-0.498,0.767,18.985,-6.905,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,-0.072,-0.497,0.779,18.197,-2.219,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,0.072,-0.497,0.779,18.197,2.219,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,0.216,-0.498,0.767,18.985,6.905,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,0.361,-0.498,0.741,20.928,12.496,0,"thread","P",1,""},
		{"Stitch","B",0.079,0.028,0.02,0.505,-0.493,0.697,23.397,20.535,3.875,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,-0.435,-1.008,0.576,53.627,-26.078,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,-0.31,-1.006,0.641,36.794,-14.576,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,-0.186,-1.005,0.67,31.719,-7.799,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,-0.062,-1.005,0.683,29.866,-2.476,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,0.062,-1.005,0.683,29.866,2.476,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,0.186,-1.005,0.67,31.719,7.799,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,0.31,-1.006,0.641,36.794,14.576,0,"thread","P",1,""},
		{"Stitch","B",0.068,0.028,0.02,0.435,-1.008,0.576,53.627,26.078,0,"thread","P",1,""},
		{"PocketGlow","B",0.75,0.06,0.04,0,-0.489,0.791,15.224,0,0,"fit","N",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.807,-1.076,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.66,-1.076,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.513,-1.076,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.37,-1.082,0.398,30.247,-14.136,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.222,-1.086,0.59,54.706,-11.711,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,-0.074,-1.085,0.621,46.579,-3.519,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.074,-1.085,0.621,46.579,3.519,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.222,-1.086,0.59,54.706,11.711,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.37,-1.082,0.398,30.247,14.136,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.513,-1.076,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.66,-1.076,0.355,0,0,0,"thread","P",1,""},
		{"Stitch","B",0.081,0.028,0.02,0.807,-1.076,0.355,0,0,0,"thread","P",1,""},
		{"Handle","C",0.124,0.12,0.12,0.291,1.357,-0.129,0,0,102.43,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,0.256,1.434,-0.129,0,0,125.818,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,0.19,1.497,-0.129,0,0,146.127,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,0.101,1.538,-0.129,0,0,163.766,"trim","L",0.5,""},
		{"Handle","C",0.144,0.12,0.12,0,1.552,-0.129,0,0,-180,"trim","L",0.5,""},
		{"Handle","C",0.142,0.12,0.12,-0.101,1.538,-0.129,0,0,-163.766,"trim","L",0.5,""},
		{"Handle","C",0.136,0.12,0.12,-0.19,1.497,-0.129,0,0,-146.127,"trim","L",0.5,""},
		{"Handle","C",0.129,0.12,0.12,-0.256,1.434,-0.129,0,0,-125.818,"trim","L",0.5,""},
		{"Handle","C",0.124,0.12,0.12,-0.291,1.357,-0.129,0,0,-102.43,"trim","L",0.5,""},
		{"QuantumDiamond","B",0.46,0.46,0.05,0,0.423,0.6,-6.593,0,45,"fit","N",1,""},
		{"QuantumDiamondInner","B",0.3,0.3,0.05,0,0.425,0.656,-6.593,0,45,"body","P",1,""},
		{"QuantumDiamondCore","B",0.13,0.13,0.05,0,0.425,0.711,-6.593,0,45,"fit","N",1,""},
		{"CircuitLine","B",0.06,0.579,0.035,-0.443,0.953,0.416,-26.021,-15.839,-42.59,"fit","N",1,""},
		{"CircuitLine","B",0.06,0.579,0.035,-0.442,-0.106,0.581,1.205,-9.52,35.199,"fit","N",1,""},
		{"CircuitLine","B",0.06,0.526,0.035,-0.664,0.423,0.499,-8.832,-17.96,-2.743,"fit","N",1,""},
		{"CircuitLine","B",0.06,0.579,0.035,0.443,0.953,0.416,-26.021,15.839,42.59,"fit","N",1,""},
		{"CircuitLine","B",0.06,0.579,0.035,0.442,-0.106,0.581,1.205,9.52,-35.199,"fit","N",1,""},
		{"CircuitLine","B",0.06,0.526,0.035,0.664,0.423,0.499,-8.832,17.96,2.743,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,-0.88,-0.79,0.349,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,-0.884,-0.528,0.373,17.385,-36.963,10.662,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,-0.883,-0.264,0.426,6.28,-30.183,3.167,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,-0.883,0,0.438,-0.659,-28.845,-0.318,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,-0.883,0.264,0.419,-7.915,-30.926,-4.087,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,-0.884,0.528,0.354,-21.563,-39.947,-14.238,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,-0.88,0.79,0.349,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,0.88,-0.79,0.349,0,0,0,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,0.884,-0.528,0.373,17.385,36.963,-10.662,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,0.883,-0.264,0.426,6.28,30.183,-3.167,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,0.883,0,0.438,-0.659,28.845,0.318,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,0.883,0.264,0.419,-7.915,30.926,4.087,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,0.884,0.528,0.354,-21.563,39.947,14.238,"fit","N",1,""},
		{"NeonSeam","B",0.05,0.263,0.03,0.88,0.79,0.349,0,0,0,"fit","N",1,""},
	},
}

function EquipmentManager.BuildBackpackParts(
	model: Model,
	level: number,
	torsoPartOrCF: BasePart | CFrame,
	anchored: boolean,
	scaleMult: number?
): BasePart
	local lvl = math.clamp(math.floor(level), 1, GameConfig.MAX_BACKPACK_LEVEL)
	local s = GameConfig.GetBackpackScale(lvl) * (scaleMult or 1.0)
	local style = GameConfig.GetBackpackStyle(lvl)

	local isCharTorso = typeof(torsoPartOrCF) == "Instance" and (torsoPartOrCF :: Instance):IsA("BasePart")
	local torsoPart: BasePart? = isCharTorso and (torsoPartOrCF :: BasePart) or nil
	local originCF: CFrame = isCharTorso and (torsoPart :: BasePart).CFrame or (torsoPartOrCF :: CFrame)

	local tW, tH, tZ = 2.0, 2.0, 1.0
	if torsoPart then
		tW, tH, tZ = torsoPart.Size.X, torsoPart.Size.Y, torsoPart.Size.Z
	end

	local BW = 2.0 * s
	local BH = 2.35 * s
	local RC = 0.48 * s
	local BD = 1.02 * s
	local PD = 0.36 * s
	-- v20: every level has its own proportions (W, H, D multipliers)
	local DIM = ({ { 0.9, 0.88, 0.95 }, { 1.0, 0.95, 1.0 }, { 0.98, 1.2, 1.05 }, { 0.95, 1.06, 0.85 }, { 1.05, 1.0, 1.0 },
		{ 1.1, 0.98, 1.14 }, { 1.02, 1.1, 0.95 }, { 1.06, 1.04, 1.0 }, { 1.14, 1.06, 1.12 }, { 1.1, 1.12, 1.05 } })[lvl] or { 1, 1, 1 }
	BW *= DIM[1]
	BH *= DIM[2]
	BD *= DIM[3]
	local topY = isCharTorso and (tH / 2 + 0.42 * s) or (BH / 2 + 0.2 * s)
	local yb = topY - RC - BH / 2
	local zc = isCharTorso and (tZ / 2 + BD / 2 + 0.02) or 0
	local front = zc + BD / 2

	local function add(name: string, size: Vector3, localCF: CFrame, color: Color3, mat: Enum.Material, opts: BagPartOpts?): BasePart
		local o: BagPartOpts = opts or {}
		local p: BasePart
		if o.Wedge then
			p = newWedge(model, name, size, color, mat, o.Reflectance)
		elseif o.Rounded then
			p = newRoundedBox(model, name, size, color, mat, o.Reflectance)
		else
			p = newPart(model, name, size, color, mat, o.Reflectance, o.Shape)
		end
		p.Transparency = o.Transparency or 0
		p.Anchored = anchored
		p.CFrame = originCF * localCF

		if torsoPart and not anchored then
			local w = Instance.new("Weld")
			w.Name = "BagWeld"
			w.Part0 = torsoPart
			w.Part1 = p
			w.C0 = localCF
			w.C1 = CFrame.identity
			w.Parent = p
		end

		if o.Push ~= nil or o.Inflate or o.Tint or o.FillGlow then
			p:SetAttribute("BaseC0", localCF)
			p:SetAttribute("BaseSize", size)
			p:SetAttribute("Push", o.Push or 0)
			p:SetAttribute("Inflate", o.Inflate == true)
			p:SetAttribute("DepthAxis", o.DepthAxis or "Z")
			p:SetAttribute("Tint", o.Tint == true)
			p:SetAttribute("FillGlow", o.FillGlow == true)
			p:SetAttribute("BaseColor", color)
		end
		return p
	end

	local bodyCol, trimCol, fitCol = style.Body, style.Trim, style.Fitting
	local bodyMat, fitMat = style.BodyMaterial, style.FittingMaterial
	local refl, transp = style.Reflectance, style.Transparency
	local bodyOpts = { Push = 0.5, Inflate = true, Tint = true, Rounded = true, Reflectance = refl, Transparency = transp }

	-- ========================================================================
	-- v23: REAL BACKPACK SILHOUETTE (generated + previewed by bag_gen.py):
	-- rounded-rectangle body, puffy front panel, domed lid or zipper arc,
	-- pillow pockets, side pockets, welts, thread stitching, leather colours.
	-- ========================================================================
	bodyMat = Enum.Material.Leather
	local PAL28 = { -- v28: body, trim, metal, camoA, camoB, thread, fit (bag_gen2.py)
		{ 176, 136, 90, 110, 78, 48, 198, 202, 210, 132, 98, 58, 208, 176, 126, 228, 208, 162, 198, 202, 210 },
		{ 156, 86, 46, 98, 56, 32, 200, 204, 212, 128, 70, 38, 178, 106, 62, 230, 196, 150, 200, 204, 212 },
		{ 118, 132, 62, 76, 86, 44, 186, 190, 180, 84, 96, 44, 156, 168, 92, 208, 208, 160, 186, 190, 180 },
		{ 42, 46, 56, 26, 28, 34, 178, 184, 194, 34, 38, 46, 60, 64, 74, 88, 92, 102, 178, 184, 194 },
		{ 28, 108, 232, 24, 26, 32, 196, 202, 212, 22, 90, 200, 70, 140, 245, 18, 70, 160, 246, 249, 255 },
		{ 38, 40, 44, 24, 26, 28, 134, 138, 146, 30, 32, 36, 52, 54, 60, 72, 74, 80, 134, 138, 146 },
		{ 232, 236, 242, 26, 28, 34, 204, 210, 220, 212, 216, 224, 246, 248, 250, 172, 178, 188, 40, 150, 255 },
		{ 30, 28, 38, 18, 16, 24, 122, 112, 142, 24, 22, 30, 46, 42, 56, 72, 62, 92, 170, 70, 255 },
		{ 30, 28, 30, 16, 14, 16, 112, 106, 106, 22, 20, 22, 48, 44, 46, 72, 58, 58, 255, 40, 30 },
		{ 20, 26, 34, 12, 16, 22, 112, 126, 142, 16, 20, 28, 36, 44, 56, 52, 72, 86, 0, 220, 255 },
	}
	local pc = PAL28[lvl] or PAL28[1]
	local function c28(i: number): Color3
		return Color3.fromRGB(pc[i], pc[i + 1], pc[i + 2])
	end
	bodyCol = c28(1)
	trimCol = c28(4)
	fitCol = c28(19)
	local PAL: { [string]: Color3 } = {
		body = bodyCol,
		flap = lighten(bodyCol, 0.05),
		edge = darken(bodyCol, 0.12),
		trim = trimCol,
		welt = darken(trimCol, 0.1),
		metal = c28(7),
		hole = Color3.fromRGB(44, 38, 34),
		thread = c28(16),
		fit = fitCol,
		dark = Color3.fromRGB(46, 40, 44),
		camoA = c28(10),
		camoB = c28(13),
	}
	local MATS: { [string]: Enum.Material } = {
		L = Enum.Material.Leather, M = Enum.Material.Metal, N = Enum.Material.Neon, F = Enum.Material.Fabric,
		W = Enum.Material.Wood, G = Enum.Material.Glass, P = Enum.Material.SmoothPlastic,
	}
	local body: BasePart = nil :: any
	for _, d in ipairs(BAG_SHAPES[lvl] or BAG_SHAPES[1]) do
		local cv = d[12]
		local col: Color3 = bodyCol
		if typeof(cv) == "table" then
			col = Color3.fromRGB(cv[1], cv[2], cv[3])
		else
			col = PAL[cv] or bodyCol
		end
		local mcode: string = d[13]
		local flags: string = d[15]
		local sh: string = d[2]
		local o: BagPartOpts = { Push = d[14] }
		if string.find(flags, "T", 1, true) then o.Tint = true end
		if string.find(flags, "I", 1, true) then o.Inflate = true end
		if sh == "C" then
			o.Shape = Enum.PartType.Cylinder
		elseif sh == "S" then
			o.Shape = Enum.PartType.Ball
		end
		if mcode == "M" then
			o.Reflectance = 0.25
		elseif mcode == "G" then
			o.Transparency = 0.3
			o.Reflectance = 0.1
		end
		local cf = CFrame.new(d[6] * s, yb + d[7] * s, zc + d[8] * s) * CFrame.Angles(math.rad(d[9]), math.rad(d[10]), math.rad(d[11]))
		local p = add(d[1], Vector3.new(d[3] * s, d[4] * s, d[5] * s), cf, col, MATS[mcode] or bodyMat, o)
		if sh == "E" then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		end
		if d[1] == "Body" then body = p end
	end

	-- 6) ПЛЕЧЕВЫЕ ЛЯМКИ (когда рюкзак на спине игрока)
	if isCharTorso then
		local strapCol = darken(trimCol, 0.1)
		local strapW = 0.30 * math.min(s, 1.1)
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * tW * 0.26
			add("StrapShoulder", Vector3.new(strapW, 0.14, tZ + 0.30), CFrame.new(x, tH / 2 + 0.05, 0.08), strapCol, bodyMat, { Rounded = true })
			local chestLen = tH * 0.82
			local chestTop = tH / 2 + 0.02
			add("StrapChest", Vector3.new(strapW * 0.92, chestLen, 0.12), CFrame.new(x, chestTop - chestLen / 2, -tZ / 2 - 0.07), strapCol, bodyMat, nil)
			add("StrapBuckle", Vector3.new(strapW * 1.15, 0.16, 0.07), CFrame.new(x, -tH * 0.08, -tZ / 2 - 0.15), fitCol, fitMat, { Reflectance = 0.3 })
		end
	end

	-- v52: детализация рюкзака (швы, пряжки, фонари, кристаллы, эмблемы) — модуль BackpackDetailer.
	-- Ошибка в отделке не должна ломать экипировку, поэтому вызов защищён pcall.
	local okDetail, errDetail = pcall(BackpackDetailer.Decorate, {
		Model = model,
		Level = lvl,
		Scale = s,
		Anchored = anchored,
		OnCharacter = isCharTorso,
		Origin = originCF,
		Width = BW,
		Height = BH,
		Depth = BD,
		CenterY = yb,
		CenterZ = zc,
		FrontZ = front,
		Palette = PAL,
		Add = add,
	})
	if not okDetail then
		warn("[EquipmentBuilder] BackpackDetailer: " .. tostring(errDetail))
	end

	model:SetAttribute("BackpackLevel", lvl)
	model:SetAttribute("BodyDepth", BD)
	model:SetAttribute("StyleName", style.Name)
	model.PrimaryPart = body
	return body
end

-- ============================================================================
-- v32: BACKPACK DIRT VISUALS — 5 states like the reference
-- (Clean -> Slightly Dirty -> Dirty -> Very Dirty -> Extremely Dirty):
-- the bag gets an olive/green camo-mud tint and more camo patches each stage.
-- ============================================================================
local DIRT_STAINS = {
	-- part, x, y, w, h, rot
	{ "Body", -0.28, 0.30, 0.30, 0.18, 12 },
	{ "FrontPocket", 0.22, -0.10, 0.34, 0.30, -8 },
	{ "Body", 0.30, 0.18, 0.22, 0.14, -20 },
	{ "FrontPocket", -0.30, 0.15, 0.22, 0.22, 25 },
	{ "Body", 0.02, 0.40, 0.36, 0.10, 4 },
	{ "FrontPocket", 0.0, -0.32, 0.50, 0.14, 0 },
	{ "Body", -0.38, -0.05, 0.16, 0.30, 0 },
	{ "Body", 0.40, -0.10, 0.14, 0.26, 0 },
	{ "FrontPocket", 0.34, 0.25, 0.16, 0.16, 40 },
	{ "Body", -0.10, 0.12, 0.18, 0.12, -35 },
	{ "Body", 0.18, -0.36, 0.30, 0.14, 15 },
	{ "Body", -0.24, -0.30, 0.26, 0.16, -18 },
	{ "FrontPocket", -0.12, 0.34, 0.30, 0.14, 8 },
	{ "FrontPocket", 0.10, 0.05, 0.26, 0.18, -30 },
	{ "Body", 0.36, 0.38, 0.18, 0.12, 22 },
	{ "Body", -0.40, 0.40, 0.16, 0.12, -10 },
	{ "FrontPocket", -0.36, -0.30, 0.20, 0.16, 30 },
	{ "Body", 0.05, -0.10, 0.20, 0.14, 50 },
}
local DIRT_STAGE_PATCHES = { [0] = 0, [1] = 4, [2] = 8, [3] = 13, [4] = 18 }
local DIRT_STAGE_TINT = { [0] = 0, [1] = 0.16, [2] = 0.32, [3] = 0.48, [4] = 0.64 }
local DIRT_CAMO = {
	Color3.fromRGB(104, 128, 54), -- olive
	Color3.fromRGB(62, 86, 36),   -- moss
	Color3.fromRGB(128, 118, 66), -- khaki mud
	Color3.fromRGB(84, 66, 42),   -- brown mud
}
local DIRT_TINT_COLOR = Color3.fromRGB(96, 116, 52)

function EquipmentManager.ApplyBackpackDirt(model: Model, stage: number)
	if not model then return end
	local s = math.clamp(math.floor(tonumber(stage) or 0), 0, 4)
	if model:GetAttribute("DirtStage") == s then return end
	model:SetAttribute("DirtStage", s)
	model:SetAttribute("Dirt", s)
	for _, ch in ipairs(model:GetChildren()) do
		if ch.Name == "DirtStain" then ch:Destroy() end
	end
	-- 1) camo-mud tint of the bag itself (neon trims keep glowing like the reference)
	local k = DIRT_STAGE_TINT[s] or 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "DirtStain" and p.Material ~= Enum.Material.Neon and p.Transparency < 0.95 then
			local orig = p:GetAttribute("DirtOrigColor")
			if typeof(orig) ~= "Color3" then
				orig = p.Color
				p:SetAttribute("DirtOrigColor", orig)
			end
			p.Color = (orig :: Color3):Lerp(DIRT_TINT_COLOR, k)
		end
	end
	if s <= 0 then return end
	-- 2) camo patches
	for i = 1, (DIRT_STAGE_PATCHES[s] or 0) do
		local st = DIRT_STAINS[i]
		if not st then break end
		local target = model:FindFirstChild(st[1], true)
		if target and target:IsA("BasePart") then
			local tsz = target.Size
			local grow = 1 + 0.12 * (s - 1)
			local p = Instance.new("Part")
			p.Name = "DirtStain"
			p.Size = Vector3.new(math.max(0.08, tsz.X * st[4] * grow), math.max(0.08, tsz.Y * st[5] * grow), 0.04)
			p.Color = DIRT_CAMO[((i - 1) % #DIRT_CAMO) + 1]
			p.Material = (i % 3 == 0) and Enum.Material.Mud or Enum.Material.Sand
			p.Transparency = 0.05
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Massless = true
			p.Anchored = target.Anchored
			p.CFrame = target.CFrame * CFrame.new(tsz.X * st[2], tsz.Y * st[3], tsz.Z / 2 + 0.02) * CFrame.Angles(0, 0, math.rad(st[6]))
			if not target.Anchored then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = p
				wc.Part1 = target
				wc.Parent = p
			end
			p.Parent = model
		end
	end
end

-- v46: снимаем ВСЕ рюкзаки с персонажа (а не только первый найденный),
-- чтобы при покупке нового на спине всегда был ровно один рюкзак
function EquipmentManager.RemoveAllBackpacks(character: Model)
	if not character then return end
	for _, d in ipairs(character:GetDescendants()) do
		if d.Parent and d:IsA("Model") and (d.Name == "VisualBackpack" or d:GetAttribute("BackpackLevel") ~= nil) then
			d:Destroy()
		end
	end
	-- на всякий случай: отдельные детали рюкзака, приваренные к телу вне модели
	for _, d in ipairs(character:GetDescendants()) do
		if d.Parent and d:IsA("BasePart") and d:FindFirstChild("BagWeld") then
			d:Destroy()
		end
	end
end

function EquipmentManager.EquipBackpack(character: Model, level: number)
	if not character then return end
	EquipmentManager.RemoveAllBackpacks(character)

	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	if not torso or not torso:IsA("BasePart") then return end

	local model = Instance.new("Model")
	model.Name = "VisualBackpack"
	EquipmentManager.BuildBackpackParts(model, level, torso, false, 1.0)
	model.Parent = character
	local ownerPlr = Players:GetPlayerFromCharacter(character)
	if ownerPlr then
		EquipmentManager.ApplyBackpackDirt(model, tonumber(ownerPlr:GetAttribute("BagDirtStage")) or 0)
	end
end

-- ============================================================================
-- 4. ОРАНЖЕВАЯ ШАХТЁРСКАЯ КАСКА ПРИ ВХОДЕ В ШАХТУ (ПУНКТ №11 ТЗ)
-- Построена строго по референсу «Оранжевая каска: виды 3D-модели.png»:
-- купол с центральным и боковыми рёбрами жёсткости, передний козырёк,
-- боковые крепления, тёмный внутренний обод и компактный налобный фонарь!
-- ============================================================================
function EquipmentManager.UpdateMinerHardHat(character: Model?, inMineZone: boolean)
	if not character then return end
	-- v35: pickaxe follows the same zone rule as the hard hat
	if character:GetAttribute("InMineZone") ~= inMineZone then
		character:SetAttribute("InMineZone", inMineZone)
	end
	EquipmentManager.SetPickaxeVisible(character, inMineZone)

	local existing = character:FindFirstChild("MinerHardHat")
	if not inMineZone then
		if existing then existing:Destroy() end
		return
	end
	if existing and existing:GetAttribute("HatVersion") == 49 then return end
	if existing then existing:Destroy() end

	local head = character:FindFirstChild("Head") :: BasePart?
	if not head or not head:IsA("BasePart") then return end

	local hatModel = Instance.new("Model")
	hatModel.Name = "MinerHardHat"
	hatModel:SetAttribute("HatVersion", 49)

	-- v35: smooth hard hat built from ellipsoids (Ball parts can't be stretched, so we use
	-- SpecialMesh Sphere): rounded dome, raised ridges, wide brim with front peak,
	-- dark inner band, side clips with rivets, glossy highlight and a real headlamp.
	local k = math.clamp(head.Size.Y / 1.2, 0.8, 1.35)
	local ORANGE = Color3.fromRGB(255, 124, 22)
	local ORANGE_HI = Color3.fromRGB(255, 154, 52)
	local ORANGE_LO = Color3.fromRGB(222, 92, 12)
	local DARK = Color3.fromRGB(34, 36, 42)
	local METAL = Color3.fromRGB(168, 172, 182)
	local SP = Enum.Material.SmoothPlastic

	local function addHatPart(name: string, size: Vector3, off: CFrame, col: Color3, mat: Enum.Material, kind: string?, refl: number?): BasePart
		local shape = nil
		if kind == "c" then shape = Enum.PartType.Cylinder elseif kind == "b" then shape = Enum.PartType.Ball end
		local p = newPart(hatModel, name, size * k, col, mat, refl or 0.1, shape)
		p.CastShadow = false
		if kind == "s" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		local offK = off.Rotation + off.Position * k
		p.CFrame = head.CFrame * offK
		local w = Instance.new("Weld")
		w.Name = "HatWeld"
		w.Part0 = head
		w.Part1 = p
		w.C0 = offK
		w.C1 = CFrame.identity
		w.Parent = p
		return p
	end

	-- 1) dark inner suspension band hugging the head
	addHatPart("SuspensionBand", Vector3.new(1.30, 0.16, 1.38), CFrame.new(0, 0.42, 0), DARK, SP, "s", 0)
	-- 2) wide rounded brim + front peak (front = -Z of the head)
	addHatPart("HatBrim", Vector3.new(1.62, 0.12, 1.70), CFrame.new(0, 0.50, -0.06), ORANGE_LO, SP, "s")
	addHatPart("FrontPeak", Vector3.new(1.12, 0.10, 0.82), CFrame.new(0, 0.49, -0.66) * CFrame.Angles(math.rad(-8), 0, 0), ORANGE_LO, SP, "s")
	-- 3) smooth dome
	local dome = addHatPart("HatDome", Vector3.new(1.38, 1.02, 1.48), CFrame.new(0, 0.62, 0.02), ORANGE, SP, "s", 0.14)
	-- 4) raised ridges (centre + two sides)
	addHatPart("CenterRidge", Vector3.new(0.24, 1.00, 1.56), CFrame.new(0, 0.68, 0.02), ORANGE_HI, SP, "s", 0.14)
	for _, sx in ipairs({ -1, 1 }) do
		addHatPart("SideRidge", Vector3.new(0.18, 0.86, 1.40), CFrame.new(sx * 0.38, 0.66, 0.02) * CFrame.Angles(0, 0, math.rad(sx * -22)), ORANGE_HI, SP, "s", 0.14)
		-- side clips with metal rivets
		addHatPart("SideClip", Vector3.new(0.14, 0.22, 0.32), CFrame.new(sx * 0.69, 0.54, 0.02), ORANGE_LO, SP, "s")
		addHatPart("SideRivet", Vector3.new(0.09, 0.09, 0.09), CFrame.new(sx * 0.76, 0.54, 0.02), METAL, Enum.Material.Metal, "b", 0.2)
	end
	-- 5) glossy highlight on the dome
	local gloss = addHatPart("HatGloss", Vector3.new(0.40, 0.22, 0.52), CFrame.new(-0.30, 0.98, -0.20) * CFrame.Angles(math.rad(-20), 0, math.rad(24)), Color3.fromRGB(255, 236, 205), SP, "s", 0)
	gloss.Transparency = 0.55
	-- 6) v49 headlamp: mount plate, housing, chrome bezel, glowing lens + forward SpotLight & fill PointLight
	local lampCF = CFrame.new(0, 0.80, -0.70) * CFrame.Angles(math.rad(12), 0, 0)
	local toFront = CFrame.Angles(0, math.rad(90), 0) -- cylinder local -X (Left) points forward (-Z)
	addHatPart("HeadlampMount", Vector3.new(0.36, 0.26, 0.08), lampCF, DARK, SP, nil, 0)
	addHatPart("HeadlampHousing", Vector3.new(0.18, 0.32, 0.32), lampCF * CFrame.new(0, 0, -0.12) * toFront, DARK, Enum.Material.Metal, "c", 0.05)
	addHatPart("HeadlampBezel", Vector3.new(0.05, 0.38, 0.38), lampCF * CFrame.new(0, 0, -0.215) * toFront, METAL, Enum.Material.Metal, "c", 0.3)
	local lampLens = addHatPart("HeadlampLens", Vector3.new(0.04, 0.28, 0.28), lampCF * CFrame.new(0, 0, -0.235) * toFront, Color3.fromRGB(255, 246, 205), Enum.Material.Neon, "c", 0)
	local spot = Instance.new("SpotLight")
	spot.Name = "MinerHelmetLight"
	spot.Face = Enum.NormalId.Left -- local -X is forward (-Z) after +90 deg Y rotation
	spot.Color = Color3.fromRGB(255, 240, 195)
	spot.Range = 36
	spot.Brightness = 2.6
	spot.Angle = 76
	spot.Shadows = true
	spot.Parent = lampLens

	-- Dedicated forward-oriented emitter angled slightly downward (-14 deg) to light blocks ahead & underfoot
	local emitter = addHatPart("HeadlampBeamEmitter", Vector3.new(0.12, 0.12, 0.12), CFrame.new(0, 0.76, -0.96) * CFrame.Angles(math.rad(-14), 0, 0), Color3.fromRGB(255, 246, 205), Enum.Material.SmoothPlastic, nil, 0)
	emitter.Transparency = 1
	local mainBeam = Instance.new("SpotLight")
	mainBeam.Name = "MinerHelmetSpotLight"
	mainBeam.Face = Enum.NormalId.Front
	mainBeam.Color = Color3.fromRGB(255, 242, 202)
	mainBeam.Range = 46
	mainBeam.Brightness = 3.2
	mainBeam.Angle = 82
	mainBeam.Shadows = true
	mainBeam.Parent = emitter

	local fillLight = Instance.new("PointLight")
	fillLight.Name = "MinerHelmetPointLight"
	fillLight.Color = Color3.fromRGB(255, 232, 185)
	fillLight.Range = 22
	fillLight.Brightness = 1.45
	fillLight.Shadows = false
	fillLight.Parent = emitter

	hatModel.PrimaryPart = dome
	hatModel.Parent = character
end

return EquipmentManager
