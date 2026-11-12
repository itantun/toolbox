--!strict
-- ============================================================================
-- 🛒 МОДУЛЬ: ShopService (ServerScriptService.Modules.ShopService)
-- v52: серверная часть нового магазина торговца Гоши.
-- Клиент только ПРОСИТ («купи кирку 3», «купи буст Luck», «продай руду»), сервер
-- проверяет всё сам: тип и диапазон аргументов, кулдаун, расстояние до торговца,
-- цену и монеты, наличие руды. Клиенту возвращается результат для анимации окна.
-- Настройки — GameConfig.SHOP_UI и GameConfig.BOOSTS.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local ShopService = {}

export type Deps = {
	DataManager: any,
	EquipmentManager: any,
	BoostService: any,
	SoundManager: any,
	SyncRemote: RemoteEvent,
	ActionRemote: RemoteEvent, -- клиент -> сервер: (action: string, arg: any)
	ResultRemote: RemoteEvent, -- сервер -> клиент: (ok: boolean, action: string, info: { [string]: any })
}

local LastAction: { [number]: number } = {}
local Initialized = false

-- Игрок должен стоять у прилавка (по горизонтали) и на уровне площади
local function isNearTrader(root: BasePart): boolean
	local center = GameConfig.GREEN_SHOP_PAD_POS
	local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
	return flat <= GameConfig.SHOP_UI.MaxDistance and math.abs(root.Position.Y - center.Y) <= 12
end

local function toLevel(arg: any, maxLevel: number): number?
	local n = tonumber(arg)
	if not n or n ~= n or n ~= math.floor(n) or n < 1 or n > maxLevel then
		return nil
	end
	return n
end

function ShopService.Init(deps: Deps)
	if Initialized then
		return
	end
	Initialized = true

	local function reply(player: Player, ok: boolean, action: string, info: { [string]: any })
		deps.ResultRemote:FireClient(player, ok, action, info)
	end

	deps.ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		if type(action) ~= "string" then
			return
		end
		local now = os.clock()
		if (now - (LastAction[player.UserId] or 0)) < GameConfig.SHOP_UI.ActionCooldown then
			return
		end
		LastAction[player.UserId] = now

		local profile = deps.DataManager.GetProfile(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not profile or not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then
			return
		end
		if not isNearTrader(root) then
			reply(player, false, action, { Reason = "Far" })
			return
		end

		if action == "BuyPickaxe" or action == "BuyBackpack" then
			local isPick = action == "BuyPickaxe"
			local level = toLevel(arg, isPick and GameConfig.MAX_PICKAXE_LEVEL or GameConfig.MAX_BACKPACK_LEVEL)
			if not level then
				return
			end
			local outcome: string?
			if isPick then
				outcome = deps.DataManager.BuyOrEquip3DPickaxe(player, level, deps.EquipmentManager, deps.SyncRemote)
			else
				outcome = deps.DataManager.BuyOrEquip3DBackpack(player, level, deps.EquipmentManager, deps.SyncRemote)
			end
			if outcome == "Bought" or outcome == "Equipped" then
				reply(player, true, action, { Level = level, Outcome = outcome })
			elseif outcome == "NoCoins" then
				reply(player, false, action, { Level = level, Reason = "NoCoins" })
			end
		elseif action == "BuyBoost" then
			if type(arg) ~= "string" then
				return
			end
			local cfg = GameConfig.BOOSTS.Items[arg]
			if not cfg or not cfg.InShop then
				return
			end
			if (profile.Coins or 0) < cfg.Price then
				reply(player, false, action, { Id = cfg.Id, Reason = "NoCoins" })
				return
			end
			profile.Coins -= cfg.Price
			local remaining = deps.BoostService.Activate(player, cfg.Id)
			deps.DataManager.UpdateLeaderstats(player)
			deps.DataManager.SyncToClient(player, deps.SyncRemote)
			reply(player, true, action, { Id = cfg.Id, Remaining = remaining })
		elseif action == "SellOre" then
			-- arg: "All" либо ключ стопки руды ("Reg_<Id>" — обычная, "Morn_<Id>" — утренняя жила)
			local selected: { [string]: boolean }? = nil
			if arg ~= "All" then
				if type(arg) ~= "string" or #arg > 40 then
					return
				end
				local kind, oreId = string.match(arg, "^(%a+)_(%w+)$")
				if (kind ~= "Reg" and kind ~= "Morn") or not oreId or not GameConfig.BLOCK_TYPES[oreId] then
					return
				end
				selected = { [arg] = true }
			end
			local earned, count = deps.DataManager.SellAtTrader(player, selected, deps.SyncRemote)
			if earned > 0 then
				reply(player, true, action, { Earned = earned, Count = count, Key = arg })
			else
				reply(player, false, action, { Reason = "Empty", Key = arg })
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		LastAction[player.UserId] = nil
	end)
end

return ShopService
