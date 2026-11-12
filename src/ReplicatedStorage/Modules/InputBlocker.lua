--!strict
-- ============================================================================
-- 🔒 МОДУЛЬ: InputBlocker (ReplicatedStorage.Modules.InputBlocker) — КЛИЕНТ
-- Версия: v15.0 — Выполнены Пункты №8 и №17 ТЗ:
-- • Полная блокировка управления камерой (MouseWheel зум, правая кнопка мыши,
--   тач-свайпы, клавиши I/O/стрелки) и персонажем (WASD, Прыжок, Shift-бег),
--   пока открыто ЛЮБОЕ окно интерфейса (Shop, Inventory, Навыки, Достижения, Престиж).
-- • Фиксирует Workspace.CurrentCamera в режиме Enum.CameraType.Scriptable
--   на текущем CFrame до закрытия всех окон, затем плавно возвращает Custom.
-- ============================================================================

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InputBlocker = {}

local ACTION_NAME = "MinerMenuInputSink_v15"
local RENDER_BIND_NAME = "MinerMenuCameraFreeze_v15"

local OpenMenus: { [string]: boolean } = {}
local Locked = false
local SavedCamCFrame: CFrame? = nil
local SavedWalkSpeed: number = 16
local SavedJumpPower: number = 50
local CloseCallbacks: { [string]: () -> () } = {}

local function sinkInput(_actionName: string, _inputState: Enum.UserInputState, _inputObject: InputObject)
	return Enum.ContextActionResult.Sink
end

local function hasAnyOpenMenu(): boolean
	for _, isOpen in pairs(OpenMenus) do
		if isOpen then
			return true
		end
	end
	return false
end

local function applyLockState(shouldLock: boolean)
	local player = Players.LocalPlayer
	if not player then return end

	if shouldLock and not Locked then
		Locked = true
		player:SetAttribute("AnyMenuOpen", true)

		local cam = Workspace.CurrentCamera
		if cam then
			SavedCamCFrame = cam.CFrame
			cam.CameraType = Enum.CameraType.Scriptable
		end

		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			if hum.WalkSpeed > 0 then
				SavedWalkSpeed = hum.WalkSpeed
			end
			if hum.JumpPower > 0 then
				SavedJumpPower = hum.JumpPower
			end
			hum.WalkSpeed = 0
			hum.JumpPower = 0
		end

		-- Перехватываем колесо мыши, правую кнопку, свайпы, WASD, прыжок и зум I/O
		pcall(function()
			ContextActionService:BindActionAtPriority(
				ACTION_NAME,
				sinkInput,
				false,
				Enum.ContextActionPriority.High.Value + 500,
				Enum.UserInputType.MouseWheel,
				Enum.UserInputType.MouseButton2,
				Enum.UserInputType.MouseButton3,
				Enum.KeyCode.W,
				Enum.KeyCode.A,
				Enum.KeyCode.S,
				Enum.KeyCode.D,
				Enum.KeyCode.Up,
				Enum.KeyCode.Down,
				Enum.KeyCode.Space,
				Enum.KeyCode.LeftShift,
				Enum.KeyCode.RightShift,
				Enum.KeyCode.I,
				Enum.KeyCode.O
			)
		end)

		pcall(function()
			RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Camera.Value + 15, function()
				if not Locked then return end
				local c = Workspace.CurrentCamera
				if c and SavedCamCFrame then
					if c.CameraType ~= Enum.CameraType.Scriptable then
						c.CameraType = Enum.CameraType.Scriptable
					end
					c.CFrame = SavedCamCFrame
				end
				local ch = player.Character
				local hm = ch and ch:FindFirstChildOfClass("Humanoid")
				if hm then
					hm.WalkSpeed = 0
					hm.JumpPower = 0
				end
			end)
		end)

	elseif (not shouldLock) and Locked then
		Locked = false
		player:SetAttribute("AnyMenuOpen", false)

		pcall(function()
			ContextActionService:UnbindAction(ACTION_NAME)
		end)
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_BIND_NAME)
		end)

		local cam = Workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Custom
		end

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			local shiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			hum.WalkSpeed = shiftDown and 25 or math.max(16, SavedWalkSpeed or 16)
			hum.JumpPower = (SavedJumpPower and SavedJumpPower > 0) and SavedJumpPower or 50
		end
	end
end

function InputBlocker.SetMenuOpen(menuId: string, isOpen: boolean)
	if isOpen then
		OpenMenus[menuId] = true
	else
		OpenMenus[menuId] = nil
	end
	applyLockState(hasAnyOpenMenu())
end

function InputBlocker.RegisterCloseCallback(menuId: string, fn: () -> ())
	CloseCallbacks[menuId] = fn
end

function InputBlocker.CloseOtherMenus(exceptMenuId: string)
	for id, isOpen in pairs(OpenMenus) do
		if id ~= exceptMenuId and isOpen then
			OpenMenus[id] = nil
			local cb = CloseCallbacks[id]
			if cb then
				pcall(cb)
			end
		end
	end
	applyLockState(hasAnyOpenMenu())
end

function InputBlocker.CloseAllMenus()
	for id, _ in pairs(OpenMenus) do
		OpenMenus[id] = nil
		local cb = CloseCallbacks[id]
		if cb then
			pcall(cb)
		end
	end
	applyLockState(false)
end

function InputBlocker.IsLocked(): boolean
	return Locked
end

return InputBlocker
