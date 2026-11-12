--!strict
-- ============================================================================
-- 🌙 МОДУЛЬ: NightCycleService (ServerScriptService.Modules.NightCycleService)
-- v52: серверный цикл День / Ночь, общий для всех игроков.
--   • Состояние — в атрибутах ReplicatedStorage: Phase, PhaseEndsAt, PhaseLength
--     (время конца в секундах workspace:GetServerTimeNow(), клиент считает остаток сам).
--   • В момент наступления ночи ВСЕ игроки мгновенно переносятся на базу
--     (PivotTo + сброс скорости), затем поднимается стена у входа в шахту.
--   • Ночью сервер раз в ~0.5 с проверяет зону шахты: любой, кто оказался внутри,
--     переносится на базу с предупреждением. Копка ночью запрещена на сервере.
--   • Утром стена опускается, шахта открывается, появляются Утренние жилы.
-- Длительности — GameConfig.PHASE.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local NightCycleService = {}

export type Deps = {
	MineManager: any,
	WorldBuilder: any,
	EquipmentManager: any,
	NightWallBuilder: any,
	WallRefs: any,
	BlocksFolder: Folder,
	OnBlockClicked: (Player, BasePart) -> (),
	NoticeRemote: RemoteEvent,  -- сервер -> клиент: разовые уведомления ("Night" | "Day" | "ZoneWarn")
	DayNightEvent: RemoteEvent, -- старый канал v51: баннер «Вечер!»
}

local P = GameConfig.PHASE
local rng = Random.new()
local IsNightNow = false
local Started = false
local LastZoneWarn: { [number]: number } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Публикуем фазу. Phase пишется последним: к моменту сигнала остальные атрибуты уже новые.
local function setPhase(name: string, length: number): number
	local endsAt = serverNow() + length
	ReplicatedStorage:SetAttribute(P.AttrLength, length)
	ReplicatedStorage:SetAttribute(P.AttrEndsAt, endsAt)
	ReplicatedStorage:SetAttribute(P.AttrPhase, name)
	return endsAt
end

function NightCycleService.IsNight(): boolean
	return IsNightNow
end

-- Зона шахты для ночной проверки: весь карьер по X/Z на любой высоте
function NightCycleService.IsInMineZone(pos: Vector3): boolean
	local b = GameConfig.MINE_ZONE_BOUNDS
	return pos.X >= b.MinX and pos.X <= b.MaxX and pos.Z >= b.MinZ and pos.Z <= b.MaxZ
end

-- Мгновенный перенос игрока на базу. Возвращает true, если персонаж был перенесён.
function NightCycleService.TeleportToBase(player: Player, equipmentManager: any?): boolean
	local char = player.Character
	if not char then
		return false
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") then
		return false
	end
	-- Погибший персонаж не трогаем: он возродится на базе сам (CharacterAdded в ServerMain)
	if hum and hum.Health <= 0 then
		return false
	end
	if hum then
		hum.Sit = false
	end
	local spread = P.TeleportSpread
	local target = GameConfig.SPAWN_POSITION
		+ Vector3.new(rng:NextNumber(-spread.X, spread.X), 0, rng:NextNumber(-spread.Z, spread.Z))
	char:PivotTo(CFrame.new(target))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if equipmentManager then
		pcall(equipmentManager.UpdateMinerHardHat, char, false)
	end
	return true
end

function NightCycleService.Start(deps: Deps)
	if Started then
		return
	end
	Started = true

	local function evictFromMine(player: Player)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		if not NightCycleService.IsInMineZone(root.Position) then
			return
		end
		if NightCycleService.TeleportToBase(player, deps.EquipmentManager) then
			local now = os.clock()
			if (now - (LastZoneWarn[player.UserId] or 0)) >= P.ZoneWarnCooldown then
				LastZoneWarn[player.UserId] = now
				deps.NoticeRemote:FireClient(player, "ZoneWarn")
			end
		end
	end

	local function beginNight()
		IsNightNow = true
		deps.MineManager.SetNightClosed(true)
		-- 1) сначала все на базу — никто не окажется под поднимающейся стеной
		for _, player in ipairs(Players:GetPlayers()) do
			NightCycleService.TeleportToBase(player, deps.EquipmentManager)
		end
		-- 2) шахта запечатывается: стена, периметр, «крышка» над карьером, ночной свет
		deps.NightWallBuilder.SetRaised(deps.WallRefs, true)
		deps.WorldBuilder.SetNightMineBarrierActive(true)
		deps.WorldBuilder.SetNightLightsActive(true)
		deps.MineManager.ClearMorningVeinsForNight()
		setPhase("Night", P.NightSeconds)
		deps.NoticeRemote:FireAllClients("Night")
		-- 3) пока шахта пуста, восстанавливаем выработанные блоки к новому утру
		task.delay(P.BlockRespawnDelay, function()
			if IsNightNow then
				deps.MineManager.RespawnAllBlocksForNight(deps.BlocksFolder, deps.OnBlockClicked)
			end
		end)
	end

	local function beginDay(announce: boolean)
		IsNightNow = false
		deps.MineManager.SetNightClosed(false)
		deps.NightWallBuilder.SetRaised(deps.WallRefs, false)
		deps.WorldBuilder.SetNightMineBarrierActive(false)
		deps.WorldBuilder.SetNightLightsActive(false)
		setPhase("Day", P.DaySeconds)
		if announce then
			local veinCount, veinList = deps.MineManager.SpawnMorningVeins()
			deps.NoticeRemote:FireAllClients("Day", veinCount, table.concat(veinList, ", "))
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		LastZoneWarn[player.UserId] = nil
	end)

	-- Первая фаза выставляется сразу, чтобы атрибуты существовали до входа первого игрока
	beginDay(false)

	task.spawn(function()
		while true do
			-- ДЕНЬ: ждём конца фазы, за N секунд до ночи — предупреждение
			local dayEndsAt = ReplicatedStorage:GetAttribute(P.AttrEndsAt) :: number
			local eveningAnnounced = false
			while serverNow() < dayEndsAt do
				local left = dayEndsAt - serverNow()
				if not eveningAnnounced and left <= P.EveningWarningSeconds then
					eveningAnnounced = true
					deps.DayNightEvent:FireAllClients(
						"EveningWarning",
						string.format("🌆 Вечер! Шахта закроется через %d с — заканчивай копать!", math.ceil(left))
					)
				end
				task.wait(math.clamp(left, 0.05, 0.25))
			end

			-- НОЧЬ: телепорт, стена, проверка зоны раз в ZoneCheckInterval
			beginNight()
			local nightEndsAt = ReplicatedStorage:GetAttribute(P.AttrEndsAt) :: number
			while serverNow() < nightEndsAt do
				for _, player in ipairs(Players:GetPlayers()) do
					evictFromMine(player)
				end
				task.wait(math.clamp(nightEndsAt - serverNow(), 0.05, P.ZoneCheckInterval))
			end

			-- УТРО
			beginDay(true)
		end
	end)
end

return NightCycleService
