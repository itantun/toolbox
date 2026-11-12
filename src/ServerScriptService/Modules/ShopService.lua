--!strict
-- ============================================================================
-- 🛒 МОДУЛЬ: ShopService (ServerScriptService.Modules.ShopService)
-- v52: серверная покупка бустов (вкладка «⚡ Бусты» в меню магазина).
-- Клиент только ПРОСИТ («купи буст Luck»), сервер проверяет всё сам: тип аргументов,
-- кулдаун, расстояние до магазина, цену и монеты. Клиенту возвращается результат для
-- анимации окна. Кирки и рюкзаки покупаются как раньше (Remote-ы BuyPickaxe / BuyBackpack).
-- Настройки — GameConfig.SHOP_UI и GameConfig.BOOSTS.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local ShopService = {}

export type Deps = {
	DataManager: any,
	BoostService: any,
	SyncRemote: RemoteEvent,
	ActionRemote: RemoteEvent, -- клиент -> сервер: (action: string, arg: any)
	ResultRemote: RemoteEvent, -- сервер -> клиент: (ok: boolean, action: string, info: { [string]: any })
}

local LastAction: { [number]: number } = {}
local Initialized = false

-- Игрок должен стоять у магазина (по горизонтали) и на уровне площади
local function isNearShop(root: BasePart): boolean
	local center = GameConfig.GREEN_SHOP_PAD_POS
	local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
	return flat <= GameConfig.SHOP_UI.MaxDistance and math.abs(root.Position.Y - center.Y) <= 12
end

function ShopService.Init(deps: Deps)
	if Initialized then
		return
	end
	Initialized = true

	deps.ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		if action ~= "BuyBoost" or type(arg) ~= "string" then
			return
		end
		local now = os.clock()
		if (now - (LastAction[player.UserId] or 0)) < GameConfig.SHOP_UI.ActionCooldown then
			return
		end
		LastAction[player.UserId] = now

		local cfg = GameConfig.BOOSTS.Items[arg]
		if not cfg or not cfg.InShop then
			return
		end
		local profile = deps.DataManager.GetProfile(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not profile or not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then
			return
		end
		if not isNearShop(root) then
			deps.ResultRemote:FireClient(player, false, action, { Id = cfg.Id, Reason = "Far" })
			return
		end
		if (profile.Coins or 0) < cfg.Price then
			deps.ResultRemote:FireClient(player, false, action, { Id = cfg.Id, Reason = "NoCoins" })
			return
		end
		profile.Coins -= cfg.Price
		local remaining = deps.BoostService.Activate(player, cfg.Id)
		deps.DataManager.UpdateLeaderstats(player)
		deps.DataManager.SyncToClient(player, deps.SyncRemote)
		deps.ResultRemote:FireClient(player, true, action, { Id = cfg.Id, Remaining = remaining })
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		LastAction[player.UserId] = nil
	end)
end

return ShopService
