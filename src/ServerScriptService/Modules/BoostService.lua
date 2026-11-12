--!strict
-- ============================================================================
-- 🚀 МОДУЛЬ: BoostService (ServerScriptService.Modules.BoostService)
-- v52: бусты торговца (Удача / Скорость / Монеты) и зелье Ночного торговца.
--   • Сервер хранит ТОЧНОЕ время конца каждого буста (workspace:GetServerTimeNow()).
--   • Клиент только показывает: читает атрибуты игрока Boost_<Id>_EndsAt / Boost_<Id>_Total.
--   • Повторная покупка ПРОДЛЕВАЕТ буст, а не сбрасывает его.
--   • В сохранение пишется остаток секунд: между сессиями буст «стоит на паузе».
-- Цены, длительности и множители — GameConfig.BOOSTS.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local BoostService = {}

type BoostState = {
	EndsAt: number, -- момент конца, сек workspace:GetServerTimeNow()
	Total: number,  -- длина текущего «окна» буста (для полоски прогресса на клиенте)
}

local Active: { [number]: { [string]: BoostState } } = {}
local ChangedCallback: ((Player) -> ())? = nil
local LoopStarted = false

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function attrName(id: string, suffix: string): string
	return "Boost_" .. id .. "_" .. suffix
end

-- Публикуем состояние буста в атрибуты игрока (их читает клиентский HUD)
local function publish(player: Player, id: string)
	local map = Active[player.UserId]
	local st = map and map[id]
	if st then
		player:SetAttribute(attrName(id, "Total"), st.Total)
		player:SetAttribute(attrName(id, "EndsAt"), st.EndsAt)
	else
		player:SetAttribute(attrName(id, "EndsAt"), nil)
		player:SetAttribute(attrName(id, "Total"), nil)
	end
	if id == "Potion" then
		-- совместимость с v51: старые скрипты читают SellBoostUntil (os.time)
		local remaining = st and math.max(0, st.EndsAt - serverNow()) or 0
		player:SetAttribute("SellBoostUntil", remaining > 0 and (os.time() + math.floor(remaining)) or 0)
	end
end

local function notifyChanged(player: Player)
	local cb = ChangedCallback
	if cb then
		task.spawn(cb, player)
	end
end

-- Вызывается при любом изменении набора бустов игрока (сервер пересылает клиенту новые статы)
function BoostService.SetChangedCallback(fn: (Player) -> ())
	ChangedCallback = fn
end

function BoostService.GetRemaining(player: Player, id: string): number
	local map = Active[player.UserId]
	local st = map and map[id]
	if not st then
		return 0
	end
	return math.max(0, st.EndsAt - serverNow())
end

function BoostService.IsActive(player: Player, id: string): boolean
	return BoostService.GetRemaining(player, id) > 0
end

-- Произведение множителей всех активных бустов с данным параметром ("Luck" | "MineSpeed" | "Coins")
function BoostService.GetMultiplier(player: Player, stat: string): number
	local map = Active[player.UserId]
	if not map then
		return 1
	end
	local mult = 1
	local now = serverNow()
	for id, st in pairs(map) do
		local cfg = GameConfig.BOOSTS.Items[id]
		if cfg and cfg.Stat == stat and st.EndsAt > now then
			mult *= cfg.Multiplier
		end
	end
	return mult
end

-- Включает или ПРОДЛЕВАЕТ буст. Возвращает новый остаток в секундах (0 — буст неизвестен).
function BoostService.Activate(player: Player, id: string, seconds: number?): number
	local cfg = GameConfig.BOOSTS.Items[id]
	if not cfg then
		return 0
	end
	local map = Active[player.UserId]
	if not map then
		map = {}
		Active[player.UserId] = map
	end
	local now = serverNow()
	local st = map[id]
	local remaining = (st and st.EndsAt > now) and (st.EndsAt - now) or 0
	local newRemaining = math.min(GameConfig.BOOSTS.MaxSeconds, remaining + math.max(1, seconds or cfg.Duration))
	map[id] = { EndsAt = now + newRemaining, Total = newRemaining }
	publish(player, id)
	notifyChanged(player)
	return newRemaining
end

-- Восстановление из сохранения: saved = { [id] = остаток секунд }
function BoostService.Load(player: Player, saved: any)
	local map: { [string]: BoostState } = {}
	Active[player.UserId] = map
	if type(saved) ~= "table" then
		return
	end
	local now = serverNow()
	for id, value in pairs(saved) do
		local remaining = tonumber(value)
		if type(id) == "string" and GameConfig.BOOSTS.Items[id] and remaining and remaining >= 1 then
			local clamped = math.min(GameConfig.BOOSTS.MaxSeconds, math.floor(remaining))
			map[id] = { EndsAt = now + clamped, Total = clamped }
			publish(player, id)
		end
	end
end

-- Данные для сохранения: остаток секунд по каждому активному бусту
function BoostService.Serialize(player: Player): { [string]: number }
	local out: { [string]: number } = {}
	local map = Active[player.UserId]
	if map then
		local now = serverNow()
		for id, st in pairs(map) do
			local remaining = math.floor(st.EndsAt - now)
			if remaining >= 1 then
				out[id] = remaining
			end
		end
	end
	return out
end

function BoostService.Clear(player: Player)
	Active[player.UserId] = nil
end

-- Фоновая проверка истечения (раз в полсекунды, без покадровых циклов)
function BoostService.Start()
	if LoopStarted then
		return
	end
	LoopStarted = true
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = serverNow()
			for _, player in ipairs(Players:GetPlayers()) do
				local map = Active[player.UserId]
				if map then
					local expired = false
					for id, st in pairs(map) do
						if st.EndsAt <= now then
							map[id] = nil
							publish(player, id)
							expired = true
						end
					end
					if expired then
						notifyChanged(player)
					end
				end
			end
		end
	end)
end

return BoostService
