--!strict
-- ============================================================================
-- 🎩 МОДУЛЬ: MerchantNpcBuilder (ServerScriptService.Modules.MerchantNpcBuilder)
-- Ночной торговец за прилавком. Сначала мгновенно строится процедурный персонаж
-- (скруглённая голова, пиджак, фетровая шляпа), затем в фоне подгружается настоящий
-- R15-аватар из каталога Roblox (HumanoidDescription) и заменяет его. Если аватар
-- не загрузился — остаётся процедурный вариант. Анимации (idle + редкое приветствие)
-- запускаются при каждом появлении лавки: SetActive(stall, true).
-- Все ID, цвета и тайминги — в таблице CONFIG ниже.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartKit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PartKit"))

local MerchantNpcBuilder = {}

local SKIN = Color3.fromRGB(234, 190, 150)

local CONFIG = {
	Avatar = {
		HatAccessory = "1029025", -- The Classic ROBLOX Fedora
		HairAccessory = "63690008", -- Pal Hair (brown)
		Shirt = 382538295, -- Guitar Tee with Black Jacket
		Pants = 382537569, -- Black Jeans
		SkinColor = SKIN,
		HeightScale = 1,
		WidthScale = 1,
		DepthScale = 1,
		HeadScale = 1,
	},
	Animations = {
		Idle = "rbxassetid://507766388",
		Wave = "rbxassetid://507770239",
		WaveMinDelay = 10,
		WaveMaxDelay = 14,
		WaveHold = 2.8,
	},
	Load = {
		Attempts = 3,
		RetryDelay = 6,
	},
	NameTag = {
		Text = "🌙 Night Merchant",
		Height = 7.0, -- above the feet
	},
	Colors = {
		Skin = SKIN,
		Jacket = Color3.fromRGB(38, 34, 52),
		Lapel = Color3.fromRGB(58, 52, 78),
		Shirt = Color3.fromRGB(235, 232, 225),
		Pants = Color3.fromRGB(28, 26, 34),
		Shoes = Color3.fromRGB(20, 18, 22),
		Hair = Color3.fromRGB(84, 52, 32),
		Hat = Color3.fromRGB(24, 22, 28),
		Accent = Color3.fromRGB(110, 60, 170),
		Belt = Color3.fromRGB(70, 44, 28),
		Gold = Color3.fromRGB(255, 183, 75),
	},
}

export type NpcOptions = {
	LoadAvatar: boolean?,
}

type NpcState = {
	Stall: Model,
	Origin: CFrame,
	Fallback: Model?,
	Avatar: Model?,
	Active: boolean,
	Destroyed: boolean,
	Gen: number,
	Loop: thread?,
	Tracks: { AnimationTrack },
}

local States: { [Model]: NpcState } = setmetatable({}, { __mode = "k" }) :: any
local rng = Random.new()

-- ---------------------------------------------------------------------------
-- Процедурный персонаж (запасной вариант). origin — центр стоп на полу лавки,
-- лицом к покупателям (-Z).
-- ---------------------------------------------------------------------------
function MerchantNpcBuilder.BuildFallback(parent: Instance, origin: CFrame): Model
	local C = CONFIG.Colors
	local model = Instance.new("Model")
	model.Name = "MerchantFallback"

	local plastic = Enum.Material.SmoothPlastic
	local fabric = Enum.Material.Fabric

	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	local function ball(name: string, d: number, p: Vector3, color: Color3, mat: Enum.Material): Part
		return PartKit.Ball(model, name, d, at(p.X, p.Y, p.Z), color, mat)
	end
	local function egg(name: string, size: Vector3, p: Vector3, color: Color3, mat: Enum.Material, rot: CFrame?): Part
		return PartKit.Ellipsoid(model, name, size, at(p.X, p.Y, p.Z) * (rot or CFrame.new()), color, mat)
	end
	-- Цилиндр между двумя точками (локальные координаты персонажа)
	local function limb(name: string, a: Vector3, b: Vector3, d: number, color: Color3, mat: Enum.Material): Part
		local cf = origin * CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(-math.pi / 2, 0, 0)
		return PartKit.Cylinder(model, name, d, (b - a).Magnitude, cf, color, mat)
	end

	-- Ноги и обувь
	for _, sx in ipairs({ -1, 1 }) do
		limb("Leg", Vector3.new(sx * 0.5, 0.45, 0), Vector3.new(sx * 0.5, 2.3, 0), 0.85, C.Pants, fabric)
		egg("Shoe", Vector3.new(0.9, 0.55, 1.4), Vector3.new(sx * 0.5, 0.27, -0.18), C.Shoes, plastic)
	end
	egg("Hips", Vector3.new(1.95, 0.8, 1.05), Vector3.new(0, 2.35, 0), C.Pants, fabric)
	PartKit.Cylinder(model, "Belt", 1.75, 0.16, at(0, 2.55, 0), C.Belt, plastic)
	PartKit.Block(model, "BeltBuckle", Vector3.new(0.3, 0.2, 0.06), at(0, 2.55, -0.9), C.Gold, Enum.Material.Metal)

	-- Корпус: сужающийся пиджак, рубашка, лацканы, воротник, бабочка
	egg("JacketWaist", Vector3.new(1.85, 1.3, 1.0), Vector3.new(0, 2.85, 0), C.Jacket, fabric)
	egg("JacketChest", Vector3.new(2.25, 1.9, 1.2), Vector3.new(0, 3.75, 0), C.Jacket, fabric)
	egg("Shirt", Vector3.new(0.75, 1.5, 0.3), Vector3.new(0, 3.95, -0.5), C.Shirt, plastic)
	for _, sx in ipairs({ -1, 1 }) do
		PartKit.Block(model, "Lapel", Vector3.new(0.3, 1.25, 0.1), at(sx * 0.46, 3.95, -0.56) * CFrame.Angles(0, sx * math.rad(-14), sx * math.rad(-10)), C.Lapel, fabric)
		egg("Collar", Vector3.new(0.5, 0.26, 0.4), Vector3.new(sx * 0.3, 4.6, -0.33), C.Shirt, plastic, CFrame.Angles(0, 0, sx * math.rad(-25)))
	end
	for i, y in ipairs({ 3.2, 2.95 }) do
		ball("JacketButton" .. i, 0.13, Vector3.new(0, y, -0.6), C.Gold, Enum.Material.Metal)
	end
	egg("PocketSquare", Vector3.new(0.3, 0.2, 0.08), Vector3.new(-0.8, 3.7, -0.6), C.Accent, fabric, CFrame.Angles(0, 0, math.rad(12)))
	for _, sx in ipairs({ -1, 1 }) do
		egg("BowTieWing", Vector3.new(0.42, 0.26, 0.16), Vector3.new(sx * 0.27, 4.48, -0.5), C.Accent, fabric, CFrame.Angles(0, 0, sx * math.rad(14)))
	end
	ball("BowTieKnot", 0.2, Vector3.new(0, 4.48, -0.52), C.Accent, fabric)

	-- Руки: плечо, локоть, манжета, кисть лежит на прилавке
	for _, sx in ipairs({ -1, 1 }) do
		local shoulder = Vector3.new(sx * 1.2, 4.2, 0)
		local elbow = Vector3.new(sx * 1.45, 3.55, -0.55)
		local wrist = Vector3.new(sx * 1.05, 3.3, -1.3)
		local dir = (wrist - elbow).Unit
		ball("Shoulder", 0.8, shoulder, C.Jacket, fabric)
		limb("UpperArm", shoulder, elbow, 0.62, C.Jacket, fabric)
		ball("Elbow", 0.6, elbow, C.Jacket, fabric)
		limb("Forearm", elbow, wrist, 0.56, C.Jacket, fabric)
		limb("Cuff", wrist - dir * 0.14, wrist + dir * 0.04, 0.6, C.Shirt, plastic)
		local handPos = wrist + dir * 0.36
		PartKit.Ellipsoid(model, "Hand", Vector3.new(0.58, 0.36, 0.78), origin * CFrame.lookAt(handPos, handPos + dir), C.Skin, plastic)
	end

	-- Шея и голова (классическая форма Head) с лицом
	limb("Neck", Vector3.new(0, 4.4, 0), Vector3.new(0, 4.75, 0), 0.5, C.Skin, plastic)
	local headY = 5.0
	local head = PartKit.Block(model, "Head", Vector3.new(2, 1, 1) * 1.12, at(0, headY, 0), C.Skin, plastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25) * 1.12
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	-- Волосы, выглядывающие из-под шляпы
	egg("HairCap", Vector3.new(1.5, 0.8, 1.5), Vector3.new(0, headY + 0.38, 0.05), C.Hair, plastic)
	egg("HairBack", Vector3.new(1.45, 1.2, 0.7), Vector3.new(0, headY + 0.05, 0.5), C.Hair, plastic)
	for _, sx in ipairs({ -1, 1 }) do
		egg("HairSide", Vector3.new(0.4, 0.9, 1.1), Vector3.new(sx * 0.66, headY + 0.12, 0.08), C.Hair, plastic)
		egg("HairBang", Vector3.new(0.55, 0.3, 0.4), Vector3.new(sx * 0.38, headY + 0.5, -0.42), C.Hair, plastic, CFrame.Angles(0, 0, sx * math.rad(-12)))
	end
	egg("HairFringe", Vector3.new(0.9, 0.32, 0.35), Vector3.new(0, headY + 0.52, -0.46), C.Hair, plastic)

	-- Фетровая шляпа: широкие поля, смятая тулья, лента
	local hatTilt = CFrame.Angles(math.rad(-5), 0, math.rad(2))
	PartKit.Cylinder(model, "HatBrim", 2.15, 0.1, at(0, headY + 0.56, 0) * hatTilt, C.Hat, fabric)
	PartKit.Cylinder(model, "HatCrown", 1.6, 0.45, at(0, headY + 0.84, 0) * hatTilt, C.Hat, fabric)
	PartKit.Cylinder(model, "HatCrownTop", 1.35, 0.25, at(0, headY + 1.15, 0) * hatTilt, C.Hat, fabric)
	for _, sx in ipairs({ -1, 1 }) do
		egg("HatPinch", Vector3.new(0.7, 0.35, 1.25), Vector3.new(sx * 0.3, headY + 1.3, 0), C.Hat, fabric, hatTilt)
	end
	PartKit.Cylinder(model, "HatBand", 1.65, 0.2, at(0, headY + 0.7, 0) * hatTilt, C.Accent, fabric)

	model.Parent = parent
	return model
end

-- ---------------------------------------------------------------------------
-- Настоящий аватар
-- ---------------------------------------------------------------------------
local function createAvatar(): Model
	local cfg = CONFIG.Avatar
	local desc = Instance.new("HumanoidDescription")
	desc.HatAccessory = cfg.HatAccessory
	desc.HairAccessory = cfg.HairAccessory
	desc.Shirt = cfg.Shirt
	desc.Pants = cfg.Pants
	desc.HeadColor = cfg.SkinColor
	desc.TorsoColor = cfg.SkinColor
	desc.LeftArmColor = cfg.SkinColor
	desc.RightArmColor = cfg.SkinColor
	desc.LeftLegColor = cfg.SkinColor
	desc.RightLegColor = cfg.SkinColor
	desc.HeightScale = cfg.HeightScale
	desc.WidthScale = cfg.WidthScale
	desc.DepthScale = cfg.DepthScale
	desc.HeadScale = cfg.HeadScale
	return game:GetService("Players"):CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
end

-- Делает аватар статичным и ставит ногами на пол. false — модель непригодна.
local function prepareAvatar(avatar: Model, origin: CFrame): boolean
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	local root = avatar:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return false
	end
	avatar.Name = "MerchantAvatar"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = false
	if not humanoid:FindFirstChildOfClass("Animator") then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local head = avatar:FindFirstChild("Head")
	if head and not head:FindFirstChildOfClass("Decal") then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Texture = "rbxasset://textures/face.png"
		face.Face = Enum.NormalId.Front
		face.Parent = head
	end

	for _, d in ipairs(avatar:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	root.Anchored = true

	-- Ноги на пол: сначала приблизительно, затем по нижней точке стоп
	avatar:PivotTo(origin * CFrame.new(0, 3, 0))
	local lowest = math.huge
	for _, footName in ipairs({ "LeftFoot", "RightFoot" }) do
		local foot = avatar:FindFirstChild(footName)
		if foot and foot:IsA("BasePart") then
			lowest = math.min(lowest, foot.Position.Y - foot.Size.Y / 2)
		end
	end
	if lowest < math.huge then
		avatar:PivotTo(avatar:GetPivot() + Vector3.new(0, origin.Position.Y - lowest, 0))
	end
	return true
end

local function loadAvatarAsync(st: NpcState)
	for attempt = 1, CONFIG.Load.Attempts do
		if st.Destroyed then
			return
		end
		local ok, result = pcall(createAvatar)
		if st.Destroyed then
			if ok then
				result:Destroy()
			end
			return
		end
		if ok and prepareAvatar(result, st.Origin) then
			if st.Fallback then
				st.Fallback:Destroy()
				st.Fallback = nil
			end
			st.Avatar = result
			result.Parent = st.Stall
			if st.Active and st.Stall.Parent then
				MerchantNpcBuilder.SetActive(st.Stall, true)
			end
			return
		end
		if ok then
			result:Destroy()
		else
			warn("[MerchantNpcBuilder] avatar load failed (" .. attempt .. "/" .. CONFIG.Load.Attempts .. "): " .. tostring(result))
		end
		if attempt < CONFIG.Load.Attempts then
			task.wait(CONFIG.Load.RetryDelay)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Анимации
-- ---------------------------------------------------------------------------
local function stopAnimation(st: NpcState)
	st.Gen += 1
	local loop = st.Loop
	st.Loop = nil
	if loop then
		pcall(task.cancel, loop)
	end
	for _, track in ipairs(st.Tracks) do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	table.clear(st.Tracks)
end

local function loadTrack(animator: Animator, id: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok then
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

local function startAnimation(st: NpcState)
	local avatar = st.Avatar
	if not avatar or not st.Active or not st.Stall.Parent then
		return
	end
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local gen = st.Gen
	-- На случай, если Humanoid снова включил столкновения у частей тела
	for _, d in ipairs(avatar:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end

	local A = CONFIG.Animations
	st.Loop = task.spawn(function()
		local idle = loadTrack(animator, A.Idle, Enum.AnimationPriority.Idle, true)
		local wave = loadTrack(animator, A.Wave, Enum.AnimationPriority.Action, false)
		if st.Gen ~= gen then
			return
		end
		if idle then
			table.insert(st.Tracks, idle)
			idle:Play(0.3)
		end
		if wave then
			table.insert(st.Tracks, wave)
		end
		while st.Gen == gen and st.Stall.Parent do
			task.wait(rng:NextNumber(A.WaveMinDelay, A.WaveMaxDelay))
			if st.Gen ~= gen or not st.Stall.Parent then
				break
			end
			if wave then
				wave:Play(0.25)
				task.wait(A.WaveHold)
				if st.Gen == gen then
					wave:Stop(0.35)
				end
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Публичный API
-- ---------------------------------------------------------------------------

-- Строит торговца внутри лавки: запасной персонаж, табличку с именем, мягкий свет.
-- origin — центр стоп на полу лавки (лицом к покупателям, -Z).
function MerchantNpcBuilder.Build(stall: Model, origin: CFrame, opts: NpcOptions?): Model
	local fallback = MerchantNpcBuilder.BuildFallback(stall, origin)

	local anchor = PartKit.Block(stall, "MerchantNameAnchor", Vector3.new(0.2, 0.2, 0.2), origin * CFrame.new(0, CONFIG.NameTag.Height, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CastShadow = false })
	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "MerchantName"
	nameGui.Size = UDim2.fromOffset(200, 40)
	nameGui.MaxDistance = 60
	nameGui.Parent = anchor
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.fromScale(1, 1)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = CONFIG.NameTag.Text
	nameLbl.TextColor3 = Color3.fromRGB(255, 225, 165)
	nameLbl.TextScaled = true
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.Parent = nameGui
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 2
	nameStroke.Parent = nameLbl

	local glow = PartKit.Block(stall, "MerchantGlow", Vector3.new(0.2, 0.2, 0.2), origin * CFrame.new(0, 4.3, -1.8), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CastShadow = false })
	PartKit.PointLight(glow, Color3.fromRGB(255, 190, 120), 0.9, 10)

	local st: NpcState = {
		Stall = stall,
		Origin = origin,
		Fallback = fallback,
		Avatar = nil,
		Active = false,
		Destroyed = false,
		Gen = 0,
		Loop = nil,
		Tracks = {},
	}
	States[stall] = st
	-- pcall: Instance.Destroying is absent in the out-of-engine (Lune) smoke environment
	pcall(function()
		stall.Destroying:Connect(function()
			st.Destroyed = true
			stopAnimation(st)
			States[stall] = nil
		end)
	end)

	if not opts or opts.LoadAvatar ~= false then
		task.spawn(loadAvatarAsync, st)
	end
	return fallback
end

-- Вызывать после того, как лавка переставлена в мир (active) или убрана (не active).
-- Каждый вызов сначала гасит прежний цикл анимаций, поэтому дублей не бывает.
function MerchantNpcBuilder.SetActive(stall: Model, active: boolean)
	local st = States[stall]
	if not st then
		return
	end
	stopAnimation(st)
	st.Active = active
	if active then
		startAnimation(st)
	end
end

return MerchantNpcBuilder
