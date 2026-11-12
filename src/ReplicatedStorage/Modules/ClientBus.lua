--!strict
-- ============================================================================
-- 🔗 МОДУЛЬ: ClientBus (ReplicatedStorage.Modules.ClientBus) — КЛИЕНТ
-- v52: общая шина клиентских скриптов. Модуль кэшируется, поэтому все LocalScript-ы
-- получают одни и те же BindableEvent-ы: старый ClientController просит открыть новое
-- окно магазина или рюкзака, а эффекты кирки узнают цвет последней ударенной руды.
-- ============================================================================

local Players = game:GetService("Players")

local ClientBus = {}

local function event(name: string): BindableEvent
	local e = Instance.new("BindableEvent")
	e.Name = name
	return e
end

ClientBus.OpenShop = event("OpenShop")     -- Fire(tabId: string?) — открыть / переключить окно магазина
ClientBus.CloseShop = event("CloseShop")   -- Fire() — закрыть магазин
ClientBus.ToggleBag = event("ToggleBag")   -- Fire() — открыть / закрыть окно рюкзака
ClientBus.CloseAll = event("CloseAll")     -- Fire() — закрыть все окна v52

-- Цвет руды последнего удара локального игрока (для искр удара)
ClientBus.LastHitColor = Color3.fromRGB(255, 220, 150)
ClientBus.LastHitClock = 0

function ClientBus.SetLastHit(color: Color3)
	ClientBus.LastHitColor = color
	ClientBus.LastHitClock = os.clock()
end

-- Пока открыто окно v52, копка и прицел отключены (ClientController читает этот атрибут)
local OpenWindows: { [string]: boolean } = {}

function ClientBus.SetWindowOpen(id: string, isOpen: boolean)
	if isOpen then
		OpenWindows[id] = true
	else
		OpenWindows[id] = nil
	end
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("UpgradeUIOpen", next(OpenWindows) ~= nil)
	end
end

function ClientBus.IsWindowOpen(id: string): boolean
	return OpenWindows[id] == true
end

return ClientBus
