--!strict
-- ============================================================================
-- ✨ МОДУЛЬ: VFXModule (ReplicatedStorage.Modules.VFXModule)
-- Описание: Визуальные эффекты современного Симулятора Шахтёра 2026 (v8.0):
-- • Плавная анимация взмаха кирки (0.3 сек через TweenService), синхронизированная со стуком
-- • Лёгкое дрожание блока, частицы осколков, трещины по мере снижения HP
-- • Эффект продажи монет на белой платформе и вспышка света при покупке кирки в 3D-магазине
-- ============================================================================

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local VFXModule = {}

local ALL_FACES = {
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
}

-- 1. Взмах кирки (v11): вся анимация теперь в ToolAnimator и проигрывается на КЛИЕНТЕ
-- (раньше сервер и клиент двигали руку одновременно — отсюда рывки).
-- Функция оставлена для совместимости со старыми вызовами.
function VFXModule.PlayCharacterSwingAnimation(character: Model?)
	if not character then return end
	if RunService:IsClient() then
		local ok, animator = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ToolAnimator")) :: any
		end)
		if ok and animator then
			animator.PlaySwing(character, false)
		end
	end
end

-- 2. Трещины на блоке
function VFXModule.UpdateBlockCracks(block: BasePart, hp: number, maxHp: number)
	if not block or not block.Parent then return end

	pcall(function()
		local ratio = math.clamp(hp / math.max(1, maxHp), 0, 1)
		local damageRatio = 1 - ratio

		local fxFolder = block:FindFirstChild("DamageFX") :: Folder?
		if not fxFolder then
			local f = Instance.new("Folder")
			f.Name = "DamageFX"
			f.Parent = block
			fxFolder = f

			for _, face in ipairs(ALL_FACES) do
				local decal = Instance.new("Decal")
				decal.Name = "CrackDecal_" .. face.Name
				decal.Face = face
				decal.Texture = GameConfig.TEXTURES.CrackDecal
				decal.Color3 = Color3.fromRGB(20, 24, 32)
				decal.Transparency = 0.65
				decal.Parent = f
			end
		end

		for _, child in ipairs((fxFolder :: Folder):GetChildren()) do
			if child:IsA("Decal") then
				child.Transparency = math.clamp(0.75 - damageRatio * 0.68, 0.06, 0.75)
			end
		end
	end)
end

-- 3. Удар по блоку: дрожание + осколки.
-- v51: the WHOLE block shakes together with its decorations (grass cap, fringe, tufts, flowers,
-- clods, crystals). Soft blocks (grass, dirt, sand) wobble much more than rock, and blades of
-- grass and flowers swing wider than the block. Everything plays on the CLIENTS: the server only
-- asks the other players' clients to play it. Before, the server moved the bare block itself
-- (replicated, choppy, decorations stayed still) and the hitting player saw the chips twice.
local IS_SERVER = RunService:IsServer()
local SOFT_BLOCKS: { [string]: boolean } = { Grass = true, Dirt = true, Clay = true }
local SWAY_PARTS: { [string]: boolean } = { GrassTuft = true, FlowerStem = true, FlowerHead = true, FlowerHeart = true }
local FX_DISTANCE = 110

type ShakeRec = { P: BasePart, CF: CFrame, Sway: boolean }
type ShakeState = { Token: number, Parts: { ShakeRec }, Pivot: CFrame }
local ShakeStates: { [Instance]: ShakeState } = setmetatable({}, { __mode = "k" }) :: any
local blockFxRemote: RemoteEvent? = nil

local function getBlockFxRemote(): RemoteEvent?
	if blockFxRemote then return blockFxRemote end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local re = folder and folder:FindFirstChild("BlockFX")
	if re and re:IsA("RemoteEvent") then
		blockFxRemote = re
	end
	return blockFxRemote
end

local function shakeBlockLocal(block: BasePart)
	local found = ShakeStates[block]
	if not found then
		-- rest poses are captured once, before the first shake ever moves anything
		local parts: { ShakeRec } = { { P = block, CF = block.CFrame, Sway = false } }
		for _, d in ipairs(block:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, { P = d, CF = d.CFrame, Sway = SWAY_PARTS[d.Name] == true })
			end
		end
		found = { Token = 0, Parts = parts, Pivot = CFrame.new(block.Position) }
		ShakeStates[block] = found
	end
	local state = found :: ShakeState
	state.Token += 1
	local my = state.Token

	local soft = SOFT_BLOCKS[tostring(block:GetAttribute("BlockId"))] == true
	-- v52: дрожание спокойнее — амплитуда и наклон умножаются на GameConfig.BLOCK_HIT_SHAKE
	local shakeCfg = GameConfig.BLOCK_HIT_SHAKE
	local amp = (soft and 0.2 or 0.09) * shakeCfg.Scale
	local tilt = (soft and 0.035 or 0.012) * shakeCfg.Scale
	local steps = soft and 8 or 5
	local pivot = state.Pivot
	local pivotInv = pivot:Inverse()

	task.spawn(function()
		for i = 1, steps do
			if my ~= state.Token or not block.Parent then return end
			local k = 1 - (i - 1) / steps
			local side = (i % 2 == 0) and 1 or -1
			-- sideways wobble plus a little squash downwards (never upwards: players stand on blocks)
			local offset = CFrame.new(side * amp * k * (0.6 + math.random() * 0.4), -amp * 0.35 * k, (math.random() - 0.5) * amp * k)
				* CFrame.Angles((math.random() - 0.5) * tilt * k, 0, side * tilt * k)
			local move = pivot * offset * pivotInv
			for _, rec in ipairs(state.Parts) do
				if rec.P.Parent then
					local cf = move * rec.CF
					if rec.Sway then
						cf = cf * CFrame.Angles(0, 0, side * 0.22 * shakeCfg.SwayScale * k)
					end
					rec.P.CFrame = cf
				end
			end
			task.wait(0.03)
		end
		if my == state.Token then
			for _, rec in ipairs(state.Parts) do
				if rec.P.Parent then
					rec.P.CFrame = rec.CF
				end
			end
		end
	end)
end

local function chipsLocal(block: BasePart, accentColor: Color3)
	local soft = SOFT_BLOCKS[tostring(block:GetAttribute("BlockId"))] == true
	local origin = (block:GetAttribute("OriginPos") :: Vector3?) or block.Position

	local emitterPart = Instance.new("Part")
	emitterPart.Size = Vector3.new(0.2, 0.2, 0.2)
	emitterPart.Position = origin + Vector3.new(0, 1.8, 0)
	emitterPart.Transparency = 1
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.Parent = Workspace

	local chips = Instance.new("ParticleEmitter", emitterPart)
	chips.Color = ColorSequence.new(block.Color, accentColor)
	chips.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, soft and 0.42 or 0.32),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	chips.Lifetime = NumberRange.new(0.22, soft and 0.6 or 0.45)
	chips.Speed = NumberRange.new(6, 13)
	chips.SpreadAngle = Vector2.new(180, 180)
	chips.Acceleration = Vector3.new(0, -28, 0)
	chips.Enabled = false
	chips:Emit(soft and 14 or 8) -- soft ground throws more crumbs

	Debris:AddItem(emitterPart, 0.8)
end

-- hitter: on the server, the player whose own client has already played the effect
function VFXModule.PlayHitShakeAndParticles(block: BasePart, accentColor: Color3, hitter: Player?)
	if not block or not block.Parent then return end

	if IS_SERVER then
		local re = getBlockFxRemote()
		if not re then return end
		local pos = block.Position
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= hitter then
				local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - pos).Magnitude <= FX_DISTANCE then
					re:FireClient(plr, block, accentColor)
				end
			end
		end
		return
	end

	pcall(function()
		shakeBlockLocal(block)
		chipsLocal(block, accentColor)
	end)
end

if not IS_SERVER then
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes", 60)
		local re = folder and folder:WaitForChild("BlockFX", 60)
		if re and re:IsA("RemoteEvent") then
			re.OnClientEvent:Connect(function(block: any, accentColor: any)
				if typeof(block) == "Instance" and block:IsA("BasePart") and typeof(accentColor) == "Color3" then
					VFXModule.PlayHitShakeAndParticles(block, accentColor)
				end
			end)
		end
	end)
end

-- 4. Частицы осколков при разрушении блока
function VFXModule.PlayDestroyVFX(position: Vector3, mainColor: Color3, accentColor: Color3, mat: Enum.Material)
	pcall(function()
		local p = Instance.new("Part")
		p.Size = Vector3.new(0.3, 0.3, 0.3)
		p.Position = position
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Parent = Workspace

		local pe = Instance.new("ParticleEmitter", p)
		pe.Color = ColorSequence.new(mainColor, accentColor)
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Lifetime = NumberRange.new(0.35, 0.65)
		pe.Speed = NumberRange.new(7, 15)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Acceleration = Vector3.new(0, -25, 0)
		pe.Enabled = false
		pe:Emit(18)

		Debris:AddItem(p, 0.8)

		for i = 1, 5 do
			local shard = Instance.new("Part")
			shard.Size = Vector3.new(0.65, 0.65, 0.65)
			shard.Color = (i <= 2) and accentColor or mainColor
			shard.Material = mat
			shard.Position = position + Vector3.new((math.random() - 0.5) * 1.8, (math.random() - 0.5) * 1.8, (math.random() - 0.5) * 1.8)
			shard.Anchored = false
			shard.CanCollide = true
			shard.CanQuery = false
			shard.Parent = Workspace

			local sm = Instance.new("SpecialMesh", shard)
			sm.MeshType = Enum.MeshType.Sphere
			sm.Scale = Vector3.new(1, 0.85, 1)

			shard.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 16, math.random(7, 14), (math.random() - 0.5) * 16)
			TweenService:Create(shard, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			Debris:AddItem(shard, 0.45)
		end
	end)
end

-- 5. Эффект частиц монет при авто-продаже и вспышки света при покупке (Приоритет №5, п. 5)
function VFXModule.PlayPurchaseOrSellBurst(position: Vector3, burstColor: Color3)
	pcall(function()
		local flash = Instance.new("Part")
		flash.Shape = Enum.PartType.Ball
		flash.Material = Enum.Material.Neon
		flash.Color = burstColor
		flash.Size = Vector3.new(1.5, 1.5, 1.5)
		flash.Position = position
		flash.Transparency = 0.25
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.Parent = Workspace

		local pe = Instance.new("ParticleEmitter", flash)
		pe.Color = ColorSequence.new(burstColor, Color3.new(1, 1, 1))
		pe.LightEmission = 0.9
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Lifetime = NumberRange.new(0.35, 0.7)
		pe.Speed = NumberRange.new(8, 16)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Enabled = false
		pe:Emit(20)

		TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(6.5, 6.5, 6.5),
			Transparency = 1,
		}):Play()

		Debris:AddItem(flash, 0.75)
	end)
end

function VFXModule.SpawnFloatingText(position: Vector3, text: string, color: Color3)
	pcall(function()
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.3, 0.3, 0.3)
		anchor.Position = position + Vector3.new((math.random() - 0.5) * 1.2, 2.5, (math.random() - 0.5) * 1.2)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Parent = Workspace

		local bg = Instance.new("BillboardGui", anchor)
		bg.Size = UDim2.new(0, 230, 0, 48)
		bg.AlwaysOnTop = true

		local lbl = Instance.new("TextLabel", bg)
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextColor3 = color
		lbl.TextStrokeTransparency = 0.15
		lbl.TextScaled = true
		lbl.Text = text

		TweenService:Create(anchor, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = anchor.Position + Vector3.new(0, 3.2, 0),
		}):Play()
		TweenService:Create(lbl, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()

		Debris:AddItem(anchor, 0.9)
	end)
end

return VFXModule
