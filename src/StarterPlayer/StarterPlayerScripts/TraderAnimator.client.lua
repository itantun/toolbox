--!strict
-- ============================================================================
-- 🎭 LOCALSCRIPT: TraderAnimator (StarterPlayerScripts)
-- Оживляет торговца Гошу на каждом клиенте через Motor6D.C0 (от атрибута BaseC0):
--   а) спокойное покачивание корпуса (зацикленный твин туда-обратно);
--   б) голова следит за ближайшим игроком (пересчёт несколько раз в секунду);
--   в) дружеское махание правой рукой каждые WaveIntervalMin..Max секунд.
-- Без RenderStepped/Heartbeat: один цикл task.wait. Далеко от торговца — «спит».
-- ============================================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local CFG = GameConfig.MARKET

local localPlayer = Players.LocalPlayer

type Rig = {
	Model: Model,
	Root: BasePart,
	Torso: BasePart,
	Waist: Motor6D,
	Neck: Motor6D,
	ShoulderR: Motor6D,
	WaistBase: CFrame,
	NeckBase: CFrame,
	ShoulderBase: CFrame,
	Sway: Tween?,
	NeckTween: Tween?,
	LookActive: boolean,
	LastYaw: number,
	LastPitch: number,
	Waving: boolean,
	WaveId: number,
	NextWave: number,
}

local rigs: { [Instance]: Rig } = {}
local pending: { [Instance]: boolean } = {}
local rand = Random.new()

-- Базовая поза сустава: атрибут BaseC0, а если его нет — текущее значение C0
local function baseOf(motor: Motor6D): CFrame
	local v = motor:GetAttribute("BaseC0")
	if typeof(v) == "CFrame" then
		return v
	end
	return motor.C0
end

local function findMotor(owner: Instance, name: string): Motor6D?
	local m = owner:WaitForChild(name, 10)
	if m and m:IsA("Motor6D") then
		return m
	end
	return nil
end

-- Собирает ссылки на детали и суставы; nil, если чего-то не хватает
local function buildRig(model: Model): Rig?
	local root = model:WaitForChild("Root", 15)
	local torso = model:WaitForChild("Torso", 15)
	if not (root and root:IsA("BasePart") and torso and torso:IsA("BasePart")) then
		return nil
	end
	local waist = findMotor(root, "Waist")
	local neck = findMotor(torso, "Neck")
	local shoulder = findMotor(torso, "ShoulderR")
	if not (waist and neck and shoulder) then
		return nil
	end
	return {
		Model = model,
		Root = root,
		Torso = torso,
		Waist = waist,
		Neck = neck,
		ShoulderR = shoulder,
		WaistBase = baseOf(waist),
		NeckBase = baseOf(neck),
		ShoulderBase = baseOf(shoulder),
		Sway = nil,
		NeckTween = nil,
		LookActive = false,
		LastYaw = 0,
		LastPitch = 0,
		Waving = false,
		WaveId = 0,
		NextWave = os.clock() + rand:NextNumber(CFG.WaveIntervalMin, CFG.WaveIntervalMax),
	}
end

-- Проверка, что модель и все нужные детали ещё живы
local function isAlive(rig: Rig): boolean
	return rig.Model.Parent ~= nil
		and rig.Root.Parent ~= nil
		and rig.Torso.Parent ~= nil
		and rig.Waist.Parent ~= nil
		and rig.Neck.Parent ~= nil
		and rig.ShoulderR.Parent ~= nil
end

local function tweenTo(motor: Motor6D, goal: CFrame, time: number, style: Enum.EasingStyle, dir: Enum.EasingDirection): Tween
	local tween = TweenService:Create(motor, TweenInfo.new(time, style, dir), { C0 = goal })
	tween:Play()
	return tween
end

-- ---------------------------------------------------------------------------
-- а) Покачивание: один зацикленный твин, пока игрок рядом
-- ---------------------------------------------------------------------------
local function startIdle(rig: Rig)
	if rig.Sway then
		return
	end
	local goal = rig.WaistBase * CFrame.Angles(math.rad(CFG.SwayPitchDeg), 0, math.rad(CFG.SwayRollDeg))
	local info = TweenInfo.new(CFG.SwayPeriod, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(rig.Waist, info, { C0 = goal })
	rig.Sway = tween
	tween:Play()
end

local function stopIdle(rig: Rig)
	local tween = rig.Sway
	if tween then
		tween:Cancel()
		rig.Sway = nil
		rig.Waist.C0 = rig.WaistBase
	end
end

-- ---------------------------------------------------------------------------
-- б) Взгляд: ближайший игрок в радиусе LookDistance
-- ---------------------------------------------------------------------------
local function nearestTarget(rig: Rig): Vector3?
	local origin = rig.Root.Position
	local best: Vector3? = nil
	local bestDist = CFG.LookDistance
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
		if part and part:IsA("BasePart") then
			local dist = (part.Position - origin).Magnitude
			if dist < bestDist then
				bestDist = dist
				best = part.Position
			end
		end
	end
	return best
end

local function updateLook(rig: Rig)
	local target = nearestTarget(rig)
	local lookInfoTime = CFG.LookTweenTime
	if not target then
		if rig.LookActive then
			rig.LookActive = false
			rig.LastYaw = 0
			rig.LastPitch = 0
			if rig.NeckTween then
				rig.NeckTween:Cancel()
			end
			rig.NeckTween = tweenTo(rig.Neck, rig.NeckBase, lookInfoTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		return
	end

	-- Направление на цель в системе координат туловища (перёд торговца = -Z)
	local pivot = rig.Torso.CFrame * rig.NeckBase
	local d = rig.Torso.CFrame:VectorToObjectSpace(target - pivot.Position)
	local yaw = math.atan2(-d.X, -d.Z)
	local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
	local pitch = math.atan2(d.Y, flat)
	local yawMax = math.rad(CFG.YawLimitDeg)
	local pitchMax = math.rad(CFG.PitchLimitDeg)
	yaw = math.clamp(yaw, -yawMax, yawMax)
	pitch = math.clamp(pitch, -pitchMax, pitchMax)

	-- Не запускаем новый твин из-за мелких изменений угла
	if rig.LookActive and math.abs(yaw - rig.LastYaw) < 0.03 and math.abs(pitch - rig.LastPitch) < 0.03 then
		return
	end
	rig.LookActive = true
	rig.LastYaw = yaw
	rig.LastPitch = pitch
	if rig.NeckTween then
		rig.NeckTween:Cancel()
	end
	local goal = rig.NeckBase * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	rig.NeckTween = tweenTo(rig.Neck, goal, lookInfoTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- ---------------------------------------------------------------------------
-- в) Махание правой рукой: подъём, 2–3 взмаха, опускание (последовательные твины)
-- ---------------------------------------------------------------------------

-- Поза плеча: наклон вперёд, затем отведение в сторону (в системе туловища)
local function armPose(base: CFrame, forwardDeg: number, outDeg: number): CFrame
	return CFrame.new(base.Position) * CFrame.Angles(math.rad(forwardDeg), 0, 0) * CFrame.Angles(0, 0, math.rad(outDeg))
end

local function playWave(rig: Rig)
	rig.Waving = true
	rig.WaveId += 1
	local id = rig.WaveId
	local motor = rig.ShoulderR

	-- Шаг твина; возвращает false, если волну нужно прервать
	local function step(goal: CFrame, time: number, style: Enum.EasingStyle, dir: Enum.EasingDirection): boolean
		if rig.WaveId ~= id or not isAlive(rig) then
			return false
		end
		local tween = tweenTo(motor, goal, time, style, dir)
		tween.Completed:Wait()
		return rig.WaveId == id and isAlive(rig)
	end

	local fwd = CFG.WaveForwardDeg
	local raised = CFG.WaveRaiseDeg
	local swing = CFG.WaveSwingDeg
	local ok = step(armPose(rig.ShoulderBase, fwd, raised), CFG.WaveRaiseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if ok then
		local swings = rand:NextInteger(CFG.WaveSwingsMin, CFG.WaveSwingsMax)
		for i = 1, swings * 2 do
			local out = if i % 2 == 1 then raised - swing else raised
			ok = step(armPose(rig.ShoulderBase, fwd, out), CFG.WaveSwingTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			if not ok then
				break
			end
		end
	end
	if ok then
		step(rig.ShoulderBase, CFG.WaveLowerTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	end

	if rig.WaveId == id then
		rig.Waving = false
		if rig.ShoulderR.Parent then
			rig.ShoulderR.C0 = rig.ShoulderBase
		end
		rig.NextWave = os.clock() + rand:NextNumber(CFG.WaveIntervalMin, CFG.WaveIntervalMax)
	end
end

-- Сброс всех поз при засыпании (игрок далеко) — волну прерываем
local function sleepRig(rig: Rig)
	stopIdle(rig)
	if rig.Waving then
		rig.WaveId += 1
		rig.Waving = false
		rig.ShoulderR.C0 = rig.ShoulderBase
	end
end

-- ---------------------------------------------------------------------------
-- Регистрация торговцев (модель может реплицироваться после старта скрипта)
-- ---------------------------------------------------------------------------
local function register(inst: Instance)
	if not inst:IsA("Model") or rigs[inst] or pending[inst] then
		return
	end
	pending[inst] = true
	task.spawn(function()
		local rig = buildRig(inst)
		pending[inst] = nil
		if rig and inst.Parent then
			rigs[inst] = rig
		end
	end)
end

CollectionService:GetInstanceAddedSignal(CFG.NpcTag):Connect(register)
for _, inst in ipairs(CollectionService:GetTagged(CFG.NpcTag)) do
	register(inst)
end

-- Расстояние от локального игрока до торговца (nil, если персонажа нет)
local function distanceToLocal(rig: Rig): number?
	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return (hrp.Position - rig.Root.Position).Magnitude
	end
	return nil
end

-- Единственный цикл: частый шаг рядом, редкий (1 с) — когда все торговцы далеко
task.spawn(function()
	while true do
		local anyNear = false
		for model, rig in pairs(rigs) do
			if not isAlive(rig) then
				sleepRig(rig)
				rigs[model] = nil
			else
				local dist = distanceToLocal(rig)
				if dist == nil or dist > CFG.AnimateDistance then
					sleepRig(rig)
				else
					anyNear = true
					startIdle(rig)
					updateLook(rig)
					if not rig.Waving and os.clock() >= rig.NextWave then
						task.spawn(playWave, rig)
					end
				end
			end
		end
		task.wait(if anyNear then CFG.LookInterval else CFG.SleepInterval)
	end
end)
