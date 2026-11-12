--!strict
-- ============================================================================
-- 🎬 МОДУЛЬ: ToolAnimator (ReplicatedStorage.Modules.ToolAnimator) — КЛИЕНТ
-- Версия: v13.0 — Выполнено Требование №1:
-- • Правая рука игрока (Плечо + Локоть + Кисть на R15 и Правая рука на R6)
--   и 3D-кирка двигаются на 100% СИНХРОННО как единое целое!
-- • Привязка через BindToRenderStep с приоритетом RenderPriority.Character.Value + 20
--   гарантирует, что стандартный Animator Roblox не перебивает позу руки во время удара.
-- • Скорость и резкость удара масштабируются от уровня кирки (1..10 ур., SwingAnimSpeed).
-- • 3D-рюкзак на спине плавно надувается по мере заполнения и подпрыгивает при добыче.
-- ============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local ToolAnimator = {}

local SWING = {
	Windup = 0.14,
	Strike = 0.08,
	Hold = 0.04,
	Recover = 0.13,
	ArmWindup = 165,    -- высокий замах плеча вверх-назад
	ArmStrike = 42,     -- резкое опускание руки при ударе по породе
	ElbowWindup = 38,   -- сгиб локтя при замахе (R15)
	ElbowStrike = 12,   -- распрямление локтя в момент удара (R15)
	WristWindup = -24,  -- отвод кисти с киркой назад
	WristStrike = -88,  -- рубящий доворот кисти вниз в точку удара
}
local SWING_TOTAL = SWING.Windup + SWING.Strike + SWING.Hold + SWING.Recover

local FIRST_PERSON_REST_ARM = 28
local IDLE_HOLD_ARM = 22          -- в покое правая рука держит кирку перед собой (не висит отдельно!)
local IDLE_HOLD_ELBOW = 24
local ANIM_RANGE = 160

local SWAY = {
	Stiffness = 140,
	Damping = 11,
	RunLagDeg = 0,   -- v35: кирка жёстко в руке, без раскачки при беге
	BobDeg = 0, -- v35: без покачивания
	BobSpeed = 11,
}

local OUTLINE = {
	Color = Color3.fromRGB(22, 16, 30),
	MaxModels = 14,
	Range = 110,
	Refresh = 0.4,
}

local BAG_COLORS = {
	Empty = Color3.fromRGB(90, 95, 110),
	Ok = Color3.fromRGB(80, 230, 120),
	Yellow = Color3.fromRGB(255, 210, 55),
	Red = Color3.fromRGB(255, 60, 60),
}

type BagPart = {
	Part: BasePart,
	Weld: Weld?,
	BaseC0: CFrame,
	BaseSize: Vector3,
	Push: number,
	Inflate: boolean,
	DepthAxis: string,
	Tint: boolean,
	FillGlow: boolean,
	BaseColor: Color3,
}

type CharState = {
	Char: Model,
	Shoulder: Motor6D?,
	ShoulderOrig: CFrame?,
	Elbow: Motor6D?,
	ElbowOrig: CFrame?,
	WristMotor: Motor6D?,
	WristOrig: CFrame?,
	IsR6: boolean,
	Arm: number,
	ElbowDeg: number,
	Wrist: number,
	SwingT: number?,
	SwingSpeedMul: number,
	FromArm: number,
	FromElbow: number,
	FromWrist: number,
	Queue: number,
	CritFlash: boolean,
	ImpactDone: boolean,
	SwayP: number,
	SwayV: number,
	ArmReleased: boolean?,
	BagModel: Model?,
	BagParts: { BagPart },
	BagDepth: number,
	BagF: number,
	BagLastF: number,
	BounceT: number?,
	LastUsed: number?,
	FullTag: BillboardGui?,
	WasAnimatingBag: boolean,
	BagStage: number,
}

local LocalPlayer = Players.LocalPlayer
local States: { [Model]: CharState } = {}
local OrigMotorC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local Started = false

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end
local function easeInQuad(t: number): number
	return t * t
end
local function easeInOutSine(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

local function isFirstPerson(char: Model): boolean
	local cam = Workspace.CurrentCamera
	local head = char:FindFirstChild("Head") :: BasePart?
	if not cam or not head then return false end
	return (cam.CFrame.Position - head.Position).Magnitude < 1.6
end

local function getState(char: Model): CharState
	local st = States[char]
	if st then return st end
	local newSt: CharState = {
		Char = char,
		Shoulder = nil,
		ShoulderOrig = nil,
		Elbow = nil,
		ElbowOrig = nil,
		WristMotor = nil,
		WristOrig = nil,
		IsR6 = false,
		Arm = IDLE_HOLD_ARM,
		ElbowDeg = IDLE_HOLD_ELBOW,
		Wrist = 0,
		SwingT = nil,
		SwingSpeedMul = 1.0,
		FromArm = IDLE_HOLD_ARM,
		FromElbow = IDLE_HOLD_ELBOW,
		FromWrist = 0,
		Queue = 0,
		CritFlash = false,
		ImpactDone = false,
		SwayP = 0,
		SwayV = 0,
		BagModel = nil,
		BagParts = {},
		BagDepth = 1,
		BagF = 1,
		BagLastF = -1,
		BounceT = nil,
		LastUsed = nil,
		FullTag = nil,
		WasAnimatingBag = false,
		BagStage = 0,
	}
	States[char] = newSt
	char.AncestryChanged:Connect(function()
		if not char.Parent then
			States[char] = nil
		end
	end)
	return newSt
end

local function resolveArmMotors(st: CharState)
	local char = st.Char
	local ua = char:FindFirstChild("RightUpperArm")
	if ua then
		st.IsR6 = false
		local sh = ua:FindFirstChild("RightShoulder")
		if sh and sh:IsA("Motor6D") then
			st.Shoulder = sh
			if not OrigMotorC0[sh] then OrigMotorC0[sh] = sh.C0 end
			st.ShoulderOrig = OrigMotorC0[sh]
		end
		local la = char:FindFirstChild("RightLowerArm")
		local el = la and la:FindFirstChild("RightElbow")
		if el and el:IsA("Motor6D") then
			st.Elbow = el
			if not OrigMotorC0[el] then OrigMotorC0[el] = el.C0 end
			st.ElbowOrig = OrigMotorC0[el]
		end
		local rh = char:FindFirstChild("RightHand")
		local wr = rh and rh:FindFirstChild("RightWrist")
		if wr and wr:IsA("Motor6D") then
			st.WristMotor = wr
			if not OrigMotorC0[wr] then OrigMotorC0[wr] = wr.C0 end
			st.WristOrig = OrigMotorC0[wr]
		end
	else
		local torso = char:FindFirstChild("Torso")
		local sh = torso and torso:FindFirstChild("Right Shoulder")
		if sh and sh:IsA("Motor6D") then
			st.IsR6 = true
			st.Shoulder = sh
			if not OrigMotorC0[sh] then OrigMotorC0[sh] = sh.C0 end
			st.ShoulderOrig = OrigMotorC0[sh]
		end
	end
end

local function getPickMotor(char: Model): Motor6D?
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	local m = hand and hand:FindFirstChild("PickaxeMotor")
	if m and m:IsA("Motor6D") then return m end
	return nil
end

local function critFlash(char: Model)
	local pick = char:FindFirstChild("VisualPickaxe") :: Model?
	if not pick or not pick.PrimaryPart then return end
	local off = pick:GetAttribute("HeadOffset")
	local pos = (typeof(off) == "CFrame") and (pick.PrimaryPart.CFrame * (off :: CFrame)).Position or pick.PrimaryPart.Position

	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 170, 50)
	flash.Size = Vector3.new(1, 1, 1)
	flash.CFrame = CFrame.new(pos)
	flash.Transparency = 0.15
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Parent = Workspace

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 60)
	light.Range = 14
	light.Brightness = 4
	light.Parent = flash

	local info = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(flash, info, { Size = Vector3.new(4.5, 4.5, 4.5), Transparency = 1 }):Play()
	TweenService:Create(light, info, { Brightness = 0 }):Play()
	Debris:AddItem(flash, 0.6)
end

local function startSwing(st: CharState, crit: boolean)
	local motor = getPickMotor(st.Char)
	local speedMul = (motor and (motor:GetAttribute("SwingAnimSpeed") :: number?)) or 1.0
	st.SwingSpeedMul = math.clamp(speedMul, 0.85, 1.65)
	st.FromArm = st.Arm
	st.FromElbow = st.ElbowDeg
	st.FromWrist = st.Wrist
	st.SwingT = os.clock()
	st.CritFlash = crit
	st.ImpactDone = false
end

function ToolAnimator.PlaySwing(char: Model?, isCrit: boolean?)
	if not char then return end
	local st = getState(char)
	local now = os.clock()
	local mul = st.SwingSpeedMul or 1.0
	if st.SwingT and (now - st.SwingT) * mul < (SWING.Windup + SWING.Strike) then
		if isCrit then
			st.Queue = math.min(st.Queue + 1, 2)
		end
		return
	end
	startSwing(st, isCrit == true)
end

function ToolAnimator.AddCritSwing(char: Model?)
	if not char then return end
	local st = getState(char)
	st.Queue = math.min(st.Queue + 1, 2)
	if not st.SwingT then
		startSwing(st, true)
		st.Queue = math.max(0, st.Queue - 1)
	end
end

-- ============================================================================
-- КАДР: ПРАВАЯ РУКА + КИРКА ДВИГАЮТСЯ СИНХРОННО
-- ============================================================================
local function updatePickaxe(st: CharState, dt: number, now: number, isLocal: boolean)
	local char = st.Char
	resolveArmMotors(st)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local motor = getPickMotor(char)
	if not motor then return end

	-- v35: on the surface the pickaxe is hidden -> give the arm back to the normal walk animation
	if char:GetAttribute("PickaxeHidden") == true and not st.SwingT then
		if not st.ArmReleased then
			st.ArmReleased = true
			if st.Shoulder and st.ShoulderOrig then st.Shoulder.C0 = st.ShoulderOrig end
			if st.Elbow and st.ElbowOrig then st.Elbow.C0 = st.ElbowOrig end
			if st.WristMotor and st.WristOrig then st.WristMotor.C0 = st.WristOrig end
		end
		st.SwayP, st.SwayV = 0, 0
		return
	end
	st.ArmReleased = false

	local fp = isLocal and isFirstPerson(char)
	local restArm = fp and FIRST_PERSON_REST_ARM or IDLE_HOLD_ARM
	local restElbow = fp and 16 or IDLE_HOLD_ELBOW

	local arm, elbowDeg, wrist = restArm, restElbow, 0
	if st.SwingT then
		local t = (now - st.SwingT) * (st.SwingSpeedMul or 1.0)
		local W, S, H, R = SWING.Windup, SWING.Strike, SWING.Hold, SWING.Recover
		if t < W then
			local a = easeOutQuad(t / W)
			arm = lerp(st.FromArm, SWING.ArmWindup, a)
			elbowDeg = lerp(st.FromElbow, SWING.ElbowWindup, a)
			wrist = lerp(st.FromWrist, SWING.WristWindup, a)
		elseif t < W + S then
			local a = easeInQuad((t - W) / S)
			arm = lerp(SWING.ArmWindup, SWING.ArmStrike, a)
			elbowDeg = lerp(SWING.ElbowWindup, SWING.ElbowStrike, a)
			wrist = lerp(SWING.WristWindup, SWING.WristStrike, a)
		elseif t < W + S + H then
			arm, elbowDeg, wrist = SWING.ArmStrike, SWING.ElbowStrike, SWING.WristStrike
		elseif t < SWING_TOTAL then
			local a = easeInOutSine((t - W - S - H) / R)
			arm = lerp(SWING.ArmStrike, restArm, a)
			elbowDeg = lerp(SWING.ElbowStrike, restElbow, a)
			wrist = lerp(SWING.WristStrike, 0, a)
		else
			st.SwingT = nil
		end

		if t >= W + S and not st.ImpactDone then
			st.ImpactDone = true
			if st.CritFlash then
				st.CritFlash = false
				task.spawn(critFlash, char)
			end
		end

		if st.SwingT and st.Queue > 0 and t >= W + S + H then
			st.Queue -= 1
			st.Arm, st.ElbowDeg, st.Wrist = arm, elbowDeg, wrist
			startSwing(st, true)
		elseif not st.SwingT and st.Queue > 0 then
			st.Queue -= 1
			st.Arm, st.ElbowDeg, st.Wrist = arm, elbowDeg, wrist
			startSwing(st, true)
		end
	end
	st.Arm, st.ElbowDeg, st.Wrist = arm, elbowDeg, wrist

	-- Инерция при беге (двигаются и рука, и кирка вместе!)
	local target = 0
	local bob = 0
	if root then
		local v = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local k = math.clamp(speed / 16, 0, 1.4)
		target = math.clamp(-v.Z / 16, -1, 1.2) * SWAY.RunLagDeg
		bob = math.sin(now * SWAY.BobSpeed) * SWAY.BobDeg * k
	end
	local accel = (target - st.SwayP) * SWAY.Stiffness - st.SwayV * SWAY.Damping
	st.SwayV += accel * dt
	st.SwayP += st.SwayV * dt
	local swayMul = st.SwingT and 0.20 or 1
	local swayOffset = (st.SwayP + bob) * swayMul

	local finalArm = arm + swayOffset * 0.65
	local finalWrist = wrist + swayOffset * 0.55

	-- Применяем к плечу, локтю и кисти правой руки, чтобы рука всегда держала и била киркой!
	local shoulder = st.Shoulder
	if shoulder and st.ShoulderOrig then
		local rot = st.IsR6
			and CFrame.Angles(0, 0, math.rad(finalArm))
			or CFrame.Angles(math.rad(finalArm), 0, 0)
		shoulder.C0 = st.ShoulderOrig * rot
		shoulder.Transform = CFrame.identity -- v35: walk anim no longer swings the pickaxe arm
	end

	if not st.IsR6 then
		if st.Elbow and st.ElbowOrig then
			st.Elbow.C0 = st.ElbowOrig * CFrame.Angles(math.rad(elbowDeg), 0, 0)
			st.Elbow.Transform = CFrame.identity
		end
		if st.WristMotor and st.WristOrig then
			st.WristMotor.C0 = st.WristOrig * CFrame.Angles(math.rad(finalWrist * 0.35), 0, 0)
			st.WristMotor.Transform = CFrame.identity
		end
	end

	local base = motor:GetAttribute("BaseC0")
	local grip = motor:GetAttribute("GripPos")
	if typeof(base) == "CFrame" and typeof(grip) == "Vector3" then
		local g = CFrame.new(grip :: Vector3)
		motor.C0 = g * CFrame.Angles(math.rad(finalWrist * 0.65), 0, 0) * g:Inverse() * (base :: CFrame)
	end
end

-- ============================================================================
-- КАДР: РЮКЗАК
-- ============================================================================
local function indexBag(st: CharState, bag: Model)
	st.BagModel = bag
	st.BagParts = {}
	st.BagDepth = (bag:GetAttribute("BodyDepth") :: number?) or 1
	st.BagLastF = -1
	st.BagStage = 0
	for _, d in ipairs(bag:GetDescendants()) do
		if d:IsA("BasePart") then
			local baseC0 = d:GetAttribute("BaseC0")
			if typeof(baseC0) == "CFrame" then
				local w = d:FindFirstChild("BagWeld")
				table.insert(st.BagParts, {
					Part = d,
					Weld = (w and w:IsA("Weld")) and w or nil,
					BaseC0 = baseC0 :: CFrame,
					BaseSize = (d:GetAttribute("BaseSize") :: Vector3?) or d.Size,
					Push = (d:GetAttribute("Push") :: number?) or 0,
					Inflate = d:GetAttribute("Inflate") == true,
					DepthAxis = tostring(d:GetAttribute("DepthAxis") or "Z"),
					Tint = d:GetAttribute("Tint") == true,
					FillGlow = d:GetAttribute("FillGlow") == true,
					BaseColor = (d:GetAttribute("BaseColor") :: Color3?) or d.Color,
				})
			else
				-- v47: остальные детали (карманы, канты, замки) тоже прыгают вместе с рюкзаком
				local w = d:FindFirstChild("BagWeld")
				if w and w:IsA("Weld") and not string.find(d.Name, "Strap") then
					table.insert(st.BagParts, {
						Part = d, Weld = w, BaseC0 = w.C0, BaseSize = d.Size, Push = 0,
						Inflate = false, DepthAxis = "Z", Tint = false, FillGlow = false, BaseColor = d.Color,
					} :: any)
				end
			end
		end
	end

	local body = bag:FindFirstChild("Body") :: BasePart?
	if body then
		local bb = Instance.new("BillboardGui")
		bb.Name = "FullTag"
		bb.Size = UDim2.fromOffset(150, 50)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 80
		bb.Enabled = false
		bb.Adornee = body
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.Text = "FULL!"
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 70, 70)
		lbl.Parent = bb
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(40, 0, 0)
		stroke.Parent = lbl
		local scale = Instance.new("UIScale")
		scale.Parent = lbl
		bb.Parent = body
		st.FullTag = bb
	end
end

local function spawnSellCoins(bag: Model)
	local body = bag:FindFirstChild("Body") :: BasePart?
	if not body then return end
	local origin = body.Position + Vector3.new(0, body.Size.Y * 0.6, 0)
	for i = 1, 12 do
		local coin = Instance.new("Part")
		coin.Name = "SellCoin"
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.12, 0.55, 0.55)
		coin.Color = Color3.fromRGB(255, 205, 50)
		coin.Material = Enum.Material.Metal
		coin.Reflectance = 0.35
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		coin.CFrame = CFrame.new(origin) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0)
		coin.Parent = Workspace
		coin.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 14, 14 + math.random() * 10, (math.random() - 0.5) * 14)
		coin.AssemblyAngularVelocity = Vector3.new(math.random() * 20, math.random() * 20, 0)
		task.delay(0.45, function()
			if coin.Parent then
				TweenService:Create(coin, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(coin, 0.85)
	end
end

local function updateBackpack(st: CharState, plr: Player?, dt: number, now: number)
	local bag = st.Char:FindFirstChild("VisualBackpack") :: Model?
	if not bag then return end
	if st.BagModel ~= bag then
		indexBag(st, bag)
	end

	local used = (plr and plr:GetAttribute("BagUsed") :: number?) or 0
	local max = math.max(1, (plr and plr:GetAttribute("BagMax") :: number?) or 1)
	local r = math.clamp(used / max, 0, 1)

	if st.LastUsed ~= nil then
		if used > (st.LastUsed :: number) then
			st.BounceT = now
		elseif used == 0 and (st.LastUsed :: number) > 0 then
			st.BounceT = now
			task.spawn(spawnSellCoins, bag)
		end
	end
	st.LastUsed = used

	local pulse = (math.sin(now * 8) + 1) / 2
	local fTarget: number, tintCol: Color3, tintA: number, glowCol: Color3
	local full = r >= 1
	local stage = (r < 0.25 and 1) or (r < 0.5 and 2) or (r < 0.75 and 3) or (full and 5) or 4
	if r < 0.25 then
		fTarget, tintCol, tintA, glowCol = 0.88, Color3.new(0, 0, 0), 0.12, BAG_COLORS.Empty
	elseif r < 0.5 then
		fTarget, tintCol, tintA, glowCol = 0.88 + (r - 0.25) / 0.25 * 0.16, Color3.new(0, 0, 0), 0.0, BAG_COLORS.Ok
	elseif r < 0.75 then
		fTarget, tintCol, tintA, glowCol = 1.06, BAG_COLORS.Yellow, 0.28, BAG_COLORS.Yellow
	elseif not full then
		fTarget, tintCol, tintA, glowCol = 1.12, BAG_COLORS.Red, 0.20 + 0.18 * pulse, BAG_COLORS.Red:Lerp(Color3.new(1, 1, 1), 0.35 * pulse)
	else
		fTarget, tintCol, tintA, glowCol = 1.16, BAG_COLORS.Red, 0.38 + 0.1 * pulse, BAG_COLORS.Red
	end
	st.BagF += (fTarget - st.BagF) * math.min(1, dt * 8)

	local bounceY, squash = 0, 0
	if st.BounceT then
		local t = (now - (st.BounceT :: number)) / 0.36
		if t < 1 then
			bounceY = math.sin(t * math.pi) * 0.5 * (1 - t * 0.4) -- v47: заметнее прыжок
			squash = math.sin(t * math.pi * 2) * 0.06 * (1 - t)
		else
			st.BounceT = nil
		end
	end
	local shake = CFrame.identity
	if full then
		shake = CFrame.new((math.random() - 0.5) * 0.09, (math.random() - 0.5) * 0.05, 0) * CFrame.Angles(0, 0, (math.random() - 0.5) * 0.06)
	end

	local animating = st.BounceT ~= nil or full or (r >= 0.75) or stage ~= st.BagStage or math.abs(st.BagF - st.BagLastF) > 0.002
	st.BagStage = stage
	if not animating and not st.WasAnimatingBag then
		return
	end
	st.WasAnimatingBag = animating
	st.BagLastF = st.BagF

	local df = st.BagF - 1
	local rootOff = CFrame.new(0, bounceY, 0) * CFrame.Angles(-bounceY * 0.35, 0, 0) * shake
	for _, bp in ipairs(st.BagParts) do
		local p = bp.Part
		if p.Parent then
			local push = bp.Push * st.BagDepth * df
			if bp.Weld then
				bp.Weld.C0 = rootOff * CFrame.new(0, 0, push) * bp.BaseC0
			end
			if bp.Inflate then
				local xy = 1 + df * 0.3 + squash
				local s = bp.BaseSize
				if bp.DepthAxis == "X" then
					p.Size = Vector3.new(s.X * (1 + df), s.Y * xy, s.Z * xy)
				else
					p.Size = Vector3.new(s.X * xy, s.Y * (xy - squash * 2), s.Z * (1 + df))
				end
			end
			if bp.Tint then
				p.Color = bp.BaseColor:Lerp(tintCol, tintA)
			elseif bp.FillGlow then
				p.Color = glowCol
			end
		end
	end

	if st.FullTag then
		st.FullTag.Enabled = full
		if full then
			local lbl = st.FullTag:FindFirstChildOfClass("TextLabel")
			local sc = lbl and lbl:FindFirstChildOfClass("UIScale")
			if sc then sc.Scale = 1 + 0.12 * pulse end
		end
	end
end

local function refreshOutlines()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	local candidates: { { Model: Model, Dist: number } } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			for _, name in ipairs({ "VisualPickaxe", "VisualBackpack" }) do
				local m = char:FindFirstChild(name)
				if m and m:IsA("Model") then
					local pivot = m:GetPivot().Position
					local d = (pivot - camPos).Magnitude
					if plr == LocalPlayer then d = -1 end
					table.insert(candidates, { Model = m, Dist = d })
				end
			end
		end
	end
	table.sort(candidates, function(a, b) return a.Dist < b.Dist end)
	for i, c in ipairs(candidates) do
		local hl = c.Model:FindFirstChild("ToonOutline")
		local want = i <= OUTLINE.MaxModels and c.Dist <= OUTLINE.Range
		if want and not hl then
			local h = Instance.new("Highlight")
			h.Name = "ToonOutline"
			h.Adornee = c.Model
			h.FillTransparency = 1
			h.OutlineTransparency = 0
			h.OutlineColor = OUTLINE.Color
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = c.Model
		elseif not want and hl then
			hl:Destroy()
		end
	end
end

local FP_VISIBLE_PARTS = { "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" }
local function keepFirstPersonVisible()
	local char = LocalPlayer and LocalPlayer.Character
	if not char or not isFirstPerson(char) then return end
	local pick = char:FindFirstChild("VisualPickaxe")
	if pick then
		for _, d in ipairs(pick:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
	end
	for _, name in ipairs(FP_VISIBLE_PARTS) do
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.LocalTransparencyModifier = 0
		end
	end
end

function ToolAnimator.Start()
	if Started then return end
	Started = true

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	task.spawn(function()
		local fx = remotes:WaitForChild("EquipFX", 30)
		if fx and fx:IsA("RemoteEvent") then
			fx.OnClientEvent:Connect(function(kind: any, char: any, isCrit: any, _userId: any)
				if kind ~= "Swing" or typeof(char) ~= "Instance" or not char:IsA("Model") then return end
				local localChar = LocalPlayer and LocalPlayer.Character
				if char == localChar then
					if isCrit == true then
						ToolAnimator.AddCritSwing(char)
					end
				else
					ToolAnimator.PlaySwing(char, false)
					if isCrit == true then
						ToolAnimator.AddCritSwing(char)
					end
				end
			end)
		end
	end)

	local outlineTimer = 0
	-- Выполняем анимацию правой руки и кирки ПОСЛЕ стандартного шага анимации персонажа,
	-- чтобы рука и кирка всегда двигались синхронно!
	RunService:BindToRenderStep("MinerArmAndPickaxeSync", Enum.RenderPriority.Character.Value + 20, function(dt: number)
		local now = os.clock()
		local cam = Workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if char and char.Parent then
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local isLocal = plr == LocalPlayer
				if root and (isLocal or (root.Position - camPos).Magnitude <= ANIM_RANGE) then
					local st = getState(char)
					pcall(updatePickaxe, st, dt, now, isLocal)
					pcall(updateBackpack, st, plr, dt, now)
				end
			end
		end
		outlineTimer += dt
		if outlineTimer >= OUTLINE.Refresh then
			outlineTimer = 0
			pcall(refreshOutlines)
		end
	end)

	RunService:BindToRenderStep("MinerFirstPersonTool", Enum.RenderPriority.Camera.Value + 2, function()
		pcall(keepFirstPersonVisible)
	end)
end

return ToolAnimator
