--!strict
-- ============================================================================
-- 🚀 ГЛАВНЫЙ СЕРВЕРНЫЙ СКРИПТ: ServerMain (ServerScriptService.ServerMain)
-- Версия: v14.0 (поверх v13) — автопродажа в зоне $ SELL (без меню), бег по Shift,
-- «страж» кирки (перевыдача при потере руки), точный текст ночного запрета, стартовый рюкзак 10 слотов.
-- Связывает механики v13:
-- • Цикл Утро → День → Вечер → Ночь с закрытием входа в шахту ночью (Пункт №10)
--   и случайным спавном 0–3 Утренних залежей ×3 каждое утро (Пункт №7).
-- • Автоматическое надевание Оранжевой Каски при входе в зону шахты и снятие
--   при выходе на поверхность (Пункт №11).
-- • Серверный телепорт по нижней кнопке «К продаже» (в зону автопродажи) с кулдауном 4 сек.
-- • Серверная покупка/экипировка Кирок 1–10 ур. и Рюкзаков 1–10 ур. (Пункты №5 и №9).
-- • Серверная продажа «Продать всё» и «Продать выбранное» в пункте приёма "$ SELL" (Пункт №13).
-- ============================================================================

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterGui = game:GetService("StarterGui")

print("⛏️ [ServerMain] Starting Miner Simulator...")

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
if not remotesFolder then
	local f = Instance.new("Folder")
	f.Name = "Remotes"
	f.Parent = ReplicatedStorage
	remotesFolder = f
end

local function getOrCreateRemote(name: string): RemoteEvent
	local existing = (remotesFolder :: Folder):FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = remotesFolder
	return re
end

local MineBlockRemote       = getOrCreateRemote("MineBlock")
local BuyUpgradeRemote      = getOrCreateRemote("BuyUpgrade")
local BuyPickaxeRemote      = getOrCreateRemote("BuyPickaxe")
local BuyBackpackRemote     = getOrCreateRemote("BuyBackpack")
local SellResourcesRemote   = getOrCreateRemote("SellResources")
local TeleportToSpawnRemote = getOrCreateRemote("TeleportToSpawn")
local TeleportToShopRemote = getOrCreateRemote("TeleportToShop") -- v27: Shop button -> teleport to the shop
local SyncPlayerData        = getOrCreateRemote("SyncPlayerData")
local DayNightEvent         = getOrCreateRemote("DayNightEvent")
local UpgradeSkillRemote    = getOrCreateRemote("UpgradeSkill")
local PrestigeRemote        = getOrCreateRemote("Prestige")
local ProgressionEvent      = getOrCreateRemote("ProgressionEvent")
local EquipFXRemote         = getOrCreateRemote("EquipFX")
local SellNotifyRemote      = getOrCreateRemote("SellNotify")   -- сервер -> клиент: «+XXX монет»
local SprintRemote          = getOrCreateRemote("Sprint")       -- клиент -> сервер: бег вкл/выкл
getOrCreateRemote("BlockFX") -- v51: server -> other clients: play the block hit shake (see VFXModule)

local GameConfig         = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local SoundManager       = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))
local VFXModule          = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("VFXModule"))
local ServerModules      = ServerScriptService:WaitForChild("Modules")
local DataManager        = require(ServerModules:WaitForChild("DataManager"))
local EquipmentManager   = require(ServerModules:WaitForChild("EquipmentManager"))
local WorldBuilder       = require(ServerModules:WaitForChild("WorldBuilder"))
local MineManager        = require(ServerModules:WaitForChild("MineManager"))
local ProgressionManager = require(ServerModules:WaitForChild("ProgressionManager"))

DataManager.SetSyncRemote(SyncPlayerData)
EquipmentManager.SetFxRemote(EquipFXRemote)
ProgressionManager.Init({
	GetProfile = function(player: Player)
		return DataManager.GetProfile(player)
	end,
	Sync = function(player: Player)
		DataManager.SyncToClient(player, SyncPlayerData)
	end,
}, {
	UpgradeSkill = UpgradeSkillRemote,
	Prestige = PrestigeRemote,
	ProgressionEvent = ProgressionEvent,
})

SoundManager.EnsureSoundsFolder()

local function onBuyPickaxeFromPedestal(player: Player, tier: number)
	DataManager.BuyOrEquip3DPickaxe(player, tier, EquipmentManager, SyncPlayerData)
end

local function onClaimCaveChest(player: Player, coinsReward: number, chestPart: BasePart)
	DataManager.GrantCaveChestReward(player, coinsReward, chestPart, SyncPlayerData)
end

local worldRefs = WorldBuilder.BuildWorld(EquipmentManager, onBuyPickaxeFromPedestal, onClaimCaveChest)
local blocksFolder = worldRefs.BlocksFolder

local function handleBlockClick(player: Player, block: BasePart)
	MineManager.HandleMineHit(player, block, DataManager, EquipmentManager, blocksFolder, SyncPlayerData)
end

task.spawn(function()
	MineManager.InitMine(blocksFolder, handleBlockClick)
	local count, list = MineManager.SpawnMorningVeins()
	if count > 0 then
		DayNightEvent:FireAllClients(
			"MorningVeinsSpawned",
			string.format("🌅 Morning! Morning Veins in the mine (×3 💰): %d (%s)", count, table.concat(list, ", "))
		)
	end
end)

-- ============================================================================
-- 1. ПРОВЕРКА НАХОЖДЕНИЯ В ЗОНЕ ШАХТЫ: ОРАНЖЕВАЯ КАСКА (ПУНКТ №11)
--    И ЗАЩИТА НОЧНОГО ВХОДА В ШАХТУ (ПУНКТ №10) + ЗАЩИТА ГРАНИЦ КАРТЫ (ПУНКТ №12)
-- ============================================================================
local NightWarnCooldown: { [number]: number } = {}

local function isPositionInMineZone(pos: Vector3): boolean
	local b = GameConfig.MINE_ZONE_BOUNDS
	return (pos.X >= b.MinX and pos.X <= b.MaxX and pos.Z >= b.MinZ and pos.Z <= b.MaxZ and pos.Y <= b.TopY)
end

task.spawn(function()
	while task.wait(0.12) do
		local isNight = MineManager.IsNightClosed()
		local now = os.clock()

		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if char and root then
				local pos = root.Position

				-- Защита от выпадения за пределы карты (Пункт №12)
				if pos.Y < GameConfig.FALL_THRESHOLD_Y or pos.X < GameConfig.MAP_BOUNDS.MinX - 6 or pos.X > GameConfig.MAP_BOUNDS.MaxX + 6 or pos.Z < GameConfig.MAP_BOUNDS.MinZ - 6 or pos.Z > GameConfig.MAP_BOUNDS.MaxZ + 6 then
					root.AssemblyLinearVelocity = Vector3.zero
					root.CFrame = CFrame.new(GameConfig.SPAWN_POSITION)
					pos = root.Position
				end

				local inMine = isPositionInMineZone(pos)

				-- ПУНКТ №10: Ночью вход в шахту сверху закрыт!
				if isNight and inMine and pos.Y > -3.5 then
					root.AssemblyLinearVelocity = Vector3.zero
					root.CFrame = CFrame.new(math.clamp(pos.X, -6, 6), 3.8, -4.0)
					inMine = false
					if (now - (NightWarnCooldown[player.UserId] or 0)) > 2.0 then
						NightWarnCooldown[player.UserId] = now
						VFXModule.SpawnFloatingText(
							root.Position + Vector3.new(0, 2, 0),
							GameConfig.NIGHT_CLOSED_MESSAGE,
							Color3.fromRGB(255, 105, 85)
						)
						DayNightEvent:FireClient(player, "NightEntryBlocked", GameConfig.NIGHT_CLOSED_MESSAGE)
					end
				end

				-- ПУНКТ №11: Автоматическое надевание/снятие Оранжевой Каски на голове!
				EquipmentManager.UpdateMinerHardHat(char, inMine)
			end
		end
	end
end)

-- ============================================================================
-- 2. ЦИКЛ УТРО / ДЕНЬ (360 СЕК) → ВЕЧЕР → НОЧЬ (60 СЕК, ШАХТА ЗАКРЫТА!)
-- ============================================================================
task.spawn(function()
	while true do
		-- УТРО И ДЕНЬ
		MineManager.SetNightClosed(false)
		WorldBuilder.SetNightMineBarrierActive(false)
		WorldBuilder.SetNightLightsActive(false)

		local dayRemaining = GameConfig.DAY_DURATION_SECONDS
		local eveningAnnounced = false
		while dayRemaining > 0 do
			if dayRemaining <= GameConfig.EVENING_WARNING_SECONDS and not eveningAnnounced then
				eveningAnnounced = true
				DayNightEvent:FireAllClients(
					"EveningWarning",
					string.format("🌆 Evening! The mine closes in %d s — finish mining!", dayRemaining)
				)
			end
			DayNightEvent:FireAllClients("DayTick", dayRemaining)
			task.wait(1)
			dayRemaining -= 1
		end

		-- НАСТУПЛЕНИЕ НОЧИ: закрываем вход в шахту сверху!
		MineManager.SetNightClosed(true)
		WorldBuilder.SetNightMineBarrierActive(true)
		WorldBuilder.SetNightLightsActive(true)
		MineManager.ClearMorningVeinsForNight()

		DayNightEvent:FireAllClients(
			"NightStarted",
			"🌙 Night! The mine is closed until morning. Miners inside have 15 s to leave!"
		)

		TweenService:Create(Lighting, TweenInfo.new(GameConfig.TRANSITION_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			ClockTime = 24.0,
			Brightness = GameConfig.LIGHTING.NightBrightness,
			Ambient = GameConfig.LIGHTING.NightAmbient,
			OutdoorAmbient = GameConfig.LIGHTING.NightOutdoorAmbient,
		}):Play()

		task.wait(1.2)
		Lighting.ClockTime = 0.0

		local nightRemaining = GameConfig.NIGHT_DURATION_SECONDS
		local evacuatedUnderground = false
		while nightRemaining > 0 do
			DayNightEvent:FireAllClients("NightTick", nightRemaining)
			-- Через 15 секунд после начала ночи бережно поднимаем оставшихся в шахте игроков наверх с сохранением всей добытой руды!
			if (GameConfig.NIGHT_DURATION_SECONDS - nightRemaining) >= GameConfig.NIGHT_GRACE_EXIT_SECONDS and not evacuatedUnderground then
				evacuatedUnderground = true
				for _, plr in ipairs(Players:GetPlayers()) do
					local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and isPositionInMineZone(root.Position) then
						root.AssemblyLinearVelocity = Vector3.zero
						root.CFrame = CFrame.new(GameConfig.SPAWN_POSITION + Vector3.new(math.random(-6, 6), 0, math.random(-4, 4)))
						EquipmentManager.UpdateMinerHardHat(plr.Character, false)
						VFXModule.SpawnFloatingText(root.Position + Vector3.new(0, 2, 0), "🌙 Shift over! You were moved to the surface (all ore kept).", Color3.fromRGB(130, 200, 255))
					end
				end
				-- Восстанавливаем выработанные породы шахты к новому утру
				MineManager.RespawnAllBlocksForNight(blocksFolder, handleBlockClick)
			end
			task.wait(1)
			nightRemaining -= 1
		end

		-- НАСТУПЛЕНИЕ УТРА: открываем шахту и спавним 0–3 Утренних залежи (цена ×3)!
		MineManager.SetNightClosed(false)
		WorldBuilder.SetNightMineBarrierActive(false)
		WorldBuilder.SetNightLightsActive(false)

		TweenService:Create(Lighting, TweenInfo.new(GameConfig.TRANSITION_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			ClockTime = 14.0,
			Brightness = GameConfig.LIGHTING.DayBrightness,
			Ambient = GameConfig.LIGHTING.DayAmbient,
			OutdoorAmbient = GameConfig.LIGHTING.DayOutdoorAmbient,
		}):Play()

		local veinCount, veinList = MineManager.SpawnMorningVeins()
		if veinCount > 0 then
			DayNightEvent:FireAllClients(
				"DayStarted",
				string.format("🌅 Morning! The mine is open! Morning Veins found (×3 💰): %d (%s)", veinCount, table.concat(veinList, ", "))
			)
		else
			DayNightEvent:FireAllClients("DayStarted", "☀️ Morning! The mine is open again!")
		end
		task.wait(GameConfig.TRANSITION_TWEEN_TIME)
	end
end)

-- ============================================================================
-- 3. СЕРВЕРНЫЙ ТЕЛЕПОРТ ПО НИЖНЕЙ КНОПКЕ «НАВЕРХ / СПАУН» (ПУНКТ №3 ТЗ)
-- ============================================================================
local SpawnTeleportCooldowns: { [number]: number } = {}

TeleportToSpawnRemote.OnServerEvent:Connect(function(player: Player)
	pcall(function()
		local now = os.clock()
		local last = SpawnTeleportCooldowns[player.UserId] or -999
		if (now - last) < GameConfig.SPAWN_TELEPORT_COOLDOWN then
			local waitLeft = math.ceil(GameConfig.SPAWN_TELEPORT_COOLDOWN - (now - last))
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				VFXModule.SpawnFloatingText(root.Position + Vector3.new(0, 2, 0), string.format("⏳ Teleport cooldown: %d s", waitLeft), Color3.fromRGB(255, 175, 75))
			end
			return
		end

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not char or not hum or hum.Health <= 0 or not root then return end

		SpawnTeleportCooldowns[player.UserId] = now
		root.AssemblyLinearVelocity = Vector3.zero
		-- v14: кнопка ведёт сразу в зону автопродажи; сервер продаст руду в течение долей секунды
		local targetPos = GameConfig.SELL_TELEPORT_POSITION + Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 4)
		root.CFrame = CFrame.new(targetPos)

		EquipmentManager.UpdateMinerHardHat(char, false)
		SoundManager.PlayAt("TeleportWhoosh", targetPos)
		VFXModule.PlayPurchaseOrSellBurst(targetPos, Color3.fromRGB(85, 225, 255))
		VFXModule.SpawnFloatingText(targetPos + Vector3.new(0, 2, 0), "💰 You are at the Sell zone!", Color3.fromRGB(110, 235, 255))

		-- сразу сдаём руду, не дожидаясь очередной проверки зоны
		task.delay(0.2, function()
			local ok, earned, count = pcall(function()
				return DataManager.AutoSellOnWhitePad(player, SyncPlayerData)
			end)
			if ok and earned and earned > 0 then
				SellNotifyRemote:FireClient(player, earned, count)
			end
		end)
	end)
end)

-- ============================================================================
-- 3a. v27: SHOP BUTTON -> SERVER TELEPORT ONTO THE SHOP PAD (the shop menu opens there)
-- ============================================================================
local SHOP_TELEPORT_COOLDOWN = 1.5
local ShopTeleportCooldowns: { [number]: number } = {}

TeleportToShopRemote.OnServerEvent:Connect(function(player: Player)
	pcall(function()
		local now = os.clock()
		local last = ShopTeleportCooldowns[player.UserId] or -999
		if (now - last) < SHOP_TELEPORT_COOLDOWN then return end

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not char or not hum or hum.Health <= 0 or not root then return end

		ShopTeleportCooldowns[player.UserId] = now
		root.AssemblyLinearVelocity = Vector3.zero
		-- the client opens the shop menu when the player stands on this pad (same zone as walking in)
		local targetPos = GameConfig.GREEN_SHOP_PAD_POS + Vector3.new((math.random() - 0.5) * 2, 3.25, 4 + (math.random() - 0.5) * 2)
		root.CFrame = CFrame.new(targetPos)

		EquipmentManager.UpdateMinerHardHat(char, false)
		SoundManager.PlayAt("TeleportWhoosh", targetPos)
		VFXModule.PlayPurchaseOrSellBurst(targetPos, Color3.fromRGB(85, 225, 255))
	end)
end)

-- ============================================================================
-- 3b. АВТОПРОДАЖА В ЗОНЕ «$ SELL» (v14): меню продажи убрано.
--     Игрок вошёл в зону -> вся руда сразу продана, на экране всплывает «+XXX монет».
--     Пока игрок стоит в зоне, новая добыча сдаётся не чаще, чем раз в RepeatSeconds.
-- ============================================================================
local InSellZone: { [number]: boolean } = {}
local LastAutoSell: { [number]: number } = {}

task.spawn(function()
	local center = GameConfig.WHITE_SELL_PAD_POS
	while task.wait(GameConfig.AUTO_SELL.CheckInterval) do
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude
				local inside = flat <= GameConfig.SELL_ZONE_RADIUS and math.abs(root.Position.Y - center.Y) <= 10
				local wasInside = InSellZone[player.UserId] == true
				InSellZone[player.UserId] = inside

				if inside then
					local due = (not wasInside) or ((now - (LastAutoSell[player.UserId] or 0)) >= GameConfig.AUTO_SELL.RepeatSeconds)
					if due then
						local ok, earned, count = pcall(function()
							return DataManager.AutoSellOnWhitePad(player, SyncPlayerData)
						end)
						LastAutoSell[player.UserId] = now
						if ok and earned and earned > 0 then
							SellNotifyRemote:FireClient(player, earned, count)
						end
					end
				end
			end
		end
	end
end)

-- ============================================================================
-- 3c. БЕГ (SHIFT): сервер ставит скорость, клиент только сообщает «бегу / не бегу»
-- ============================================================================
SprintRemote.OnServerEvent:Connect(function(player: Player, active: any)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local base = GameConfig.SPRINT.WalkSpeed
	hum.WalkSpeed = (active == true) and (base * GameConfig.SPRINT.SprintMultiplier) or base
end)

-- ============================================================================
-- 3d. «СТРАЖ» КИРКИ И РЮКЗАКА (v14): если рука персонажа была заменена (загрузка аватара,
--     смерть, ApplyDescription), кирка остаётся в мире без Motor6D и выглядит «невидимой».
--     Раз в секунду проверяем, что кирка привязана к ТЕКУЩЕЙ правой руке, иначе выдаём заново.
-- ============================================================================
task.spawn(function()
	while task.wait(1) do
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if char and hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") then
				local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
				if hand then
					local motor = hand:FindFirstChild("PickaxeMotor") :: Motor6D?
					local model = char:FindFirstChild("VisualPickaxe") :: Model?
					local healthy = motor ~= nil and model ~= nil and motor.Part0 == hand
						and motor.Part1 ~= nil and motor.Part1:IsDescendantOf(model)
					if not healthy then
						local prof = DataManager.GetProfile(player)
						if prof then
							pcall(EquipmentManager.EquipPickaxe, char, prof.PickaxeTier)
						end
					end
				end
			end
		end
	end
end)

-- ============================================================================
-- 4. ОБРАБОТКА REMOTEEVENTS КОПКИ, МАГАЗИНА И ПРОДАЖИ
-- ============================================================================
MineBlockRemote.OnServerEvent:Connect(function(player: Player, targetBlock: any)
	pcall(function()
		if typeof(targetBlock) == "Instance" and targetBlock:IsA("BasePart") then
			handleBlockClick(player, targetBlock)
		end
	end)
end)

BuyPickaxeRemote.OnServerEvent:Connect(function(player: Player, level: any)
	pcall(function()
		local lvl = tonumber(level)
		if lvl then
			DataManager.BuyOrEquip3DPickaxe(player, math.floor(lvl), EquipmentManager, SyncPlayerData)
		end
	end)
end)

BuyBackpackRemote.OnServerEvent:Connect(function(player: Player, level: any)
	pcall(function()
		local lvl = tonumber(level)
		if lvl then
			DataManager.BuyOrEquip3DBackpack(player, math.floor(lvl), EquipmentManager, SyncPlayerData)
		end
	end)
end)

-- v32: cleaning only via the Night Merchant Repair Kit (old remote now just shows a hint).
local CleanBackpackRemote = getOrCreateRemote("CleanBackpack")
CleanBackpackRemote.OnServerEvent:Connect(function(player: Player)
	pcall(function()
		DataManager.CleanBackpack(player, SyncPlayerData)
	end)
end)

local function hookWashPrompt(inst: Instance)
	if inst:IsA("ProximityPrompt") and inst.Name == "WashStationPrompt" and not inst:GetAttribute("Hooked") then
		inst:SetAttribute("Hooked", true)
		inst.Triggered:Connect(function(player: Player)
			pcall(function()
				DataManager.CleanBackpack(player, SyncPlayerData)
			end)
		end)
	end
end
for _, d in ipairs(workspace:GetDescendants()) do
	hookWashPrompt(d)
end
workspace.DescendantAdded:Connect(hookWashPrompt)

-- v32: eat a burger from supplies anywhere (surface or mine) -> full energy
local EatFoodRemote = getOrCreateRemote("EatFood")
EatFoodRemote.OnServerEvent:Connect(function(player: Player)
	pcall(function()
		local ok = DataManager.EatFood(player, SyncPlayerData)
		if ok then pcall(function() SoundManager.PlayUISound("ShopPurchase", player) end) end
	end)
end)

-- Ручная продажа через меню удалена (v14): руда продаётся автоматически в зоне «$ SELL» (см. п. 3b).

-- ============================================================================
-- 5. ПОДКЛЮЧЕНИЕ ИГРОКОВ
-- ============================================================================
local function onPlayerAdded(player: Player)
	local profile = DataManager.LoadPlayerProfile(player)
	ProgressionManager.CheckAchievements(player, profile)

	task.spawn(function()
		local pGui = player:WaitForChild("PlayerGui", 10)
		if pGui and not pGui:FindFirstChild("MinerClientBootstrap") then
			local template = StarterGui:FindFirstChild("MinerClientBootstrap")
			if template then
				template:Clone().Parent = pGui
			end
		end
	end)

	local function onCharacterAdded(char: Model)
		local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if root then
			task.wait(0.15)
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.new(GameConfig.SPAWN_POSITION)
		end
		-- v14: ждём загрузку аватара, иначе рука может быть заменена уже ПОСЛЕ выдачи кирки
		if not player:HasAppearanceLoaded() then
			local loaded = false
			local conn = player.CharacterAppearanceLoaded:Connect(function() loaded = true end)
			local t0 = os.clock()
			while not loaded and (os.clock() - t0) < 6 and char.Parent do
				task.wait(0.1)
			end
			conn:Disconnect()
		end
		task.wait(0.2)
		local hum0 = char:FindFirstChildOfClass("Humanoid")
		if hum0 then hum0.WalkSpeed = GameConfig.SPRINT.WalkSpeed end
		local currentProfile = DataManager.GetProfile(player) or profile
		EquipmentManager.EquipPickaxe(char, currentProfile.PickaxeTier)
		EquipmentManager.EquipBackpack(char, currentProfile.BackpackLevel)
		EquipmentManager.UpdateMinerHardHat(char, false)
		ProgressionManager.ApplyAura(char, currentProfile.Prestige)
		DataManager.SyncToClient(player, SyncPlayerData)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	local lastDirtStage = tonumber(player:GetAttribute("BagDirtStage")) or 0
	player:GetAttributeChangedSignal("BagDirtStage"):Connect(function()
		local ch = player.Character
		-- v35: squelch sound whenever the backpack gets dirtier
		local newStage = tonumber(player:GetAttribute("BagDirtStage")) or 0
		if newStage > lastDirtStage then
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				SoundManager.PlayAt("BagDirty", r.Position)
			else
				SoundManager.PlayUISound("BagDirty", player)
			end
		end
		lastDirtStage = newStage
		local bp = ch and ch:FindFirstChild("VisualBackpack")
		if bp and bp:IsA("Model") then
			EquipmentManager.ApplyBackpackDirt(bp, tonumber(player:GetAttribute("BagDirtStage")) or 0)
		end
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	task.delay(0.5, function()
		if player.Parent then
			DataManager.SyncToClient(player, SyncPlayerData)
		end
	end)

	-- v50: daily reward, a welcome hint for brand-new miners, and a warning when the
	-- save could not be read (that session is never written back, see DataManager)
	local isNewPlayer = profile.TotalMined == 0
	task.delay(6, function()
		if not player.Parent then return end
		if profile.LoadFailed then
			DataManager.Notify(player, "Toast", {
				Text = "⚠️ Your save did not load",
				Sub = "This visit will not be saved. Please rejoin!",
				Color = Color3.fromRGB(255, 120, 100),
			})
		end
		if isNewPlayer then
			DataManager.Notify(player, "Welcome", {})
		end
		local daily = DataManager.ClaimDailyReward(player)
		if daily then
			DataManager.Notify(player, "DailyReward", daily)
			SoundManager.PlayUISound("LuckyPrize", player)
			DataManager.SyncToClient(player, SyncPlayerData)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	MineManager.CleanupPlayer(player)
	DataManager.RemovePlayerProfile(player)
	SpawnTeleportCooldowns[player.UserId] = nil
	ShopTeleportCooldowns[player.UserId] = nil -- v27
	NightWarnCooldown[player.UserId] = nil
	InSellZone[player.UserId] = nil
	LastAutoSell[player.UserId] = nil
end)


-- ============================================================================
-- v19d: NIGHT MERCHANT SHOP — every purchase / sale is validated on the server
-- (night only, distance to the stall, coins, item id, debounce). Buyback = 70%.
-- ============================================================================
local NightMerchantRemote = getOrCreateRemote("NightMerchant")
local MERCHANT_POS = Vector3.new(0, 0, 46)
local MERCHANT_RADIUS = 18
local MERCHANT_BUYBACK = 0.70
local MerchantDebounce: { [number]: number } = {}

local MERCHANT_ITEMS: { [string]: (any) -> number } = {
	RepairKit    = function(_p: any) return GameConfig.BACKPACK_DIRT.RepairKitPrice end, -- v32: fixed 85
	Book         = function(p: any) return 120 + 15 * (p.Level or 1) end,
	Food         = function(_p: any) return GameConfig.FOOD.Price end,
	Potion       = function(_p: any) return 150 end,
	TopHat       = function(p: any) if p.Cosmetics and p.Cosmetics.TopHat then return 0 end return 800 end,
	MorningCharm = function(p: any) if p.MorningCharm then return 0 end return 300 end,
}

local function merchantState(player: Player, profile: any)
	local prices = {}
	for id, fn in pairs(MERCHANT_ITEMS) do prices[id] = fn(profile) end
	return {
		Prices = prices,
		Coins = profile.Coins or 0,
		Buyback = math.floor(DataManager.GetBackpackSellValue(player) * MERCHANT_BUYBACK),
		OwnsHat = (profile.Cosmetics and profile.Cosmetics.TopHat) == true,
		HatOn = (profile.Cosmetics and profile.Cosmetics.TopHatOn) == true,
		Charm = profile.MorningCharm == true,
		Dirt = math.floor(profile.DirtBlocks or 0),
		DirtStage = GameConfig.GetDirtStage(profile.DirtBlocks or 0),
		FoodStock = math.floor(profile.FoodStock or 0),
		FoodMax = GameConfig.FOOD.MaxStock,
		BagUsed = DataManager.GetBackpackUsed(player),
		BagMax = DataManager.GetMaxBackpack(player),
		PotionLeft = math.max(0, (tonumber(player:GetAttribute("SellBoostUntil")) or 0) - os.time()),
	}
end

local function merchantCheck(player: Player): (any, BasePart?, string?)
	local profile = DataManager.GetProfile(player) :: any
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not profile or not root then return nil, nil, nil end
	profile.Cosmetics = profile.Cosmetics or { TopHat = false, TopHatOn = false }
	if not MineManager.IsNightClosed() then
		return nil, root, "🌙 The Night Merchant only trades at night!"
	end
	local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(MERCHANT_POS.X, 0, MERCHANT_POS.Z)).Magnitude
	if d > MERCHANT_RADIUS or math.abs(root.Position.Y - MERCHANT_POS.Y) > 12 then
		return nil, root, "📍 Come closer to the Night Merchant!"
	end
	return profile, root, nil
end

local function attachTopHat(char: Model?, on: boolean)
	if not char then return end
	local old = char:FindFirstChild("MerchantTopHat")
	if old then old:Destroy() end
	if not on then return end
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then return end
	local hat = Instance.new("Model")
	hat.Name = "MerchantTopHat"
	local function hp(name: string, size: Vector3, offset: Vector3, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.Fabric
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = head.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
		p.Parent = hat
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = p
		w.Parent = p
	end
	local top = head.Size.Y / 2
	hp("Brim",  Vector3.new(0.14, 2.3, 2.3),  Vector3.new(0, top + 0.07, 0), Color3.fromRGB(28, 24, 30))
	hp("Crown", Vector3.new(1.45, 1.45, 1.45), Vector3.new(0, top + 0.82, 0), Color3.fromRGB(34, 28, 38))
	hp("Band",  Vector3.new(0.26, 1.5, 1.5),   Vector3.new(0, top + 0.30, 0), Color3.fromRGB(170, 40, 50))
	hat.Parent = char
end

local function merchantReply(player: Player, ok: boolean, msg: string, profile: any?)
	NightMerchantRemote:FireClient(player, "Result", ok, msg, profile and merchantState(player, profile) or nil)
end

local function merchantOpen(player: Player)
	local profile, _root, err = merchantCheck(player)
	if not profile then
		if err then
			NightMerchantRemote:FireClient(player, "Close")
			NightMerchantRemote:FireClient(player, "Result", false, err)
		end
		return
	end
	NightMerchantRemote:FireClient(player, "Open", merchantState(player, profile))
end

NightMerchantRemote.OnServerEvent:Connect(function(player: Player, action: any, itemId: any)
	if type(action) ~= "string" then return end
	local now = os.clock()
	if (now - (MerchantDebounce[player.UserId] or 0)) < 0.35 then return end
	MerchantDebounce[player.UserId] = now
	if action == "Open" then
		merchantOpen(player)
		return
	end
	local profile, root, err = merchantCheck(player)
	if not profile or not root then
		if err then merchantReply(player, false, err, nil) end
		return
	end
	local msg = ""
	if action == "Sell" then
		local earned = math.floor(DataManager.GetBackpackSellValue(player) * MERCHANT_BUYBACK)
		if earned <= 0 then
			merchantReply(player, false, "🎒 Your backpack is empty!", profile)
			return
		end
		for k in pairs(profile.Inventory) do profile.Inventory[k] = 0 end
		for k in pairs(profile.MorningInventory) do profile.MorningInventory[k] = 0 end
		profile.Coins += earned
		msg = string.format("💰 Night buyback: +%d coins (70%%)", earned)
		SoundManager.PlayAt("CoinChime", root.Position)
	elseif action == "Buy" and type(itemId) == "string" and MERCHANT_ITEMS[itemId] then
		local price = MERCHANT_ITEMS[itemId](profile)
		if itemId == "TopHat" and price == 0 then
			profile.Cosmetics.TopHatOn = not profile.Cosmetics.TopHatOn
			attachTopHat(player.Character, profile.Cosmetics.TopHatOn)
			merchantReply(player, true, profile.Cosmetics.TopHatOn and "🎩 Top Hat equipped" or "🎩 Top Hat removed", profile)
			return
		end
		if itemId == "MorningCharm" and profile.MorningCharm then
			merchantReply(player, false, "🌅 Morning Bonus is already active until sunrise", profile)
			return
		end
		if itemId == "RepairKit" and (profile.DirtBlocks or 0) <= 0 then
			merchantReply(player, false, "✨ Your backpack is already clean!", profile)
			return
		end
		if itemId == "Food" and (profile.FoodStock or 0) >= GameConfig.FOOD.MaxStock then
			merchantReply(player, false, string.format("🍔 Supplies are full (%d/%d)", profile.FoodStock or 0, GameConfig.FOOD.MaxStock), profile)
			return
		end
		if (profile.Coins or 0) < price then
			merchantReply(player, false, "💰 Not Enough Coins", profile)
			return
		end
		profile.Coins -= price
		if itemId == "RepairKit" then
			DataManager.ResetDirt(player)
			msg = "🧰 Repair Kit used: backpack is clean, all slots are back!"
		elseif itemId == "Book" then
			-- v50: through GrantXP, so a book can level the player up right away
			ProgressionManager.GrantXP(player, profile, 40 + 10 * (profile.Level or 1))
			profile.StrengthXP = (profile.StrengthXP or 0) + 30
			msg = "📘 Book read: +XP and +Strength XP"
		elseif itemId == "Food" then
			profile.FoodStock = math.min(GameConfig.FOOD.MaxStock, (profile.FoodStock or 0) + 1)
			msg = string.format("🍔 Burger added to supplies (x%d). Eat anytime: [%s]", profile.FoodStock, GameConfig.FOOD.Key)
		elseif itemId == "Potion" then
			local untilT = math.max(os.time(), tonumber(player:GetAttribute("SellBoostUntil")) or 0) + 180
			player:SetAttribute("SellBoostUntil", untilT)
			msg = "🧪 Miner Potion: +25% coins at $ SELL for 3 min"
		elseif itemId == "TopHat" then
			profile.Cosmetics.TopHat = true
			profile.Cosmetics.TopHatOn = true
			attachTopHat(player.Character, true)
			msg = "🎩 Top Hat bought and equipped!"
		elseif itemId == "MorningCharm" then
			profile.MorningCharm = true
			msg = "🌅 Morning Bonus active: reward at sunrise"
		end
		SoundManager.PlayUISound("ShopPurchase", player)
	else
		return
	end
	DataManager.UpdateLeaderstats(player)
	DataManager.UpdateBagAttributes(player)
	DataManager.SyncToClient(player, SyncPlayerData)
	VFXModule.SpawnFloatingText(root.Position + Vector3.new(0, 2, 0), msg, Color3.fromRGB(255, 215, 120))
	merchantReply(player, true, msg, profile)
end)

-- ProximityPrompt at the stall (enabled only at night)
local merchantAnchor = Instance.new("Part")
merchantAnchor.Name = "NightMerchantPromptAnchor"
merchantAnchor.Anchored = true
merchantAnchor.CanCollide = false
merchantAnchor.CanQuery = false
merchantAnchor.CanTouch = false
merchantAnchor.Transparency = 1
merchantAnchor.Size = Vector3.new(4, 6, 4)
merchantAnchor.Position = MERCHANT_POS + Vector3.new(0, 3, 0)
merchantAnchor.Parent = workspace
local merchantPrompt = Instance.new("ProximityPrompt")
merchantPrompt.Name = "NightMerchantPrompt"
merchantPrompt.ActionText = "Trade"
merchantPrompt.ObjectText = "Night Merchant"
merchantPrompt.KeyboardKeyCode = Enum.KeyCode.E
merchantPrompt.HoldDuration = 0
merchantPrompt.MaxActivationDistance = 13
merchantPrompt.RequiresLineOfSight = false
merchantPrompt.Enabled = false
merchantPrompt.Parent = merchantAnchor
merchantPrompt.Triggered:Connect(function(player: Player)
	merchantOpen(player)
end)

-- Night watcher: prompt on/off, close windows at sunrise, pay Morning Bonus
task.spawn(function()
	local wasNight = MineManager.IsNightClosed()
	while true do
		local isNight = MineManager.IsNightClosed()
		merchantPrompt.Enabled = isNight
		if wasNight and not isNight then
			NightMerchantRemote:FireAllClients("Close")
			for _, pl in ipairs(Players:GetPlayers()) do
				local pr = DataManager.GetProfile(pl) :: any
				if pr and pr.MorningCharm then
					pr.MorningCharm = false
					local bonus = 150 + 60 * (pr.PickaxeTier or 1)
					pr.Coins += bonus
					pr.Energy = DataManager.GetMaxEnergy(pl)
					DataManager.UpdateLeaderstats(pl)
					DataManager.SyncToClient(pl, SyncPlayerData)
					local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if r then
						VFXModule.SpawnFloatingText(r.Position + Vector3.new(0, 3, 0), string.format("🌅 Morning Bonus: +%d coins & full energy!", bonus), Color3.fromRGB(255, 200, 90))
					end
					SoundManager.PlayUISound("CoinChime", pl)
				end
			end
		end
		wasNight = isNight
		task.wait(1)
	end
end)

-- Re-attach the saved Top Hat after respawn
local function hookHatRespawn(pl: Player)
	pl.CharacterAdded:Connect(function(ch: Model)
		task.wait(2)
		local pr = DataManager.GetProfile(pl) :: any
		if pr and pr.Cosmetics and pr.Cosmetics.TopHat and pr.Cosmetics.TopHatOn then
			attachTopHat(ch, true)
		end
	end)
	if pl.Character then
		task.delay(3, function()
			local pr = DataManager.GetProfile(pl) :: any
			if pr and pr.Cosmetics and pr.Cosmetics.TopHat and pr.Cosmetics.TopHatOn then
				attachTopHat(pl.Character, true)
			end
		end)
	end
end
Players.PlayerAdded:Connect(hookHatRespawn)
for _, pl in ipairs(Players:GetPlayers()) do hookHatRespawn(pl) end
Players.PlayerRemoving:Connect(function(pl: Player) MerchantDebounce[pl.UserId] = nil end)

-- v28: "E  Sell" button on the SELL kiosk plaque: sells the whole backpack, same as the pad
task.spawn(function()
	local prompt: ProximityPrompt? = nil
	for _ = 1, 60 do
		local found = workspace:FindFirstChild("SellPlaquePrompt", true)
		if found and found:IsA("ProximityPrompt") then
			prompt = found
			break
		end
		task.wait(0.5)
	end
	if not prompt then
		warn("[ServerMain] v28: SellPlaquePrompt not found")
		return
	end
	local busy: { [number]: boolean } = {}
	prompt.Triggered:Connect(function(player: Player)
		if busy[player.UserId] then
			return
		end
		busy[player.UserId] = true
		local ok, earned = pcall(function()
			return DataManager.AutoSellOnWhitePad(player, SyncPlayerData)
		end)
		if not ok then
			warn("[ServerMain] v28 E-Sell failed: " .. tostring(earned))
		elseif not earned or earned <= 0 then
			SoundManager.PlayUISound("UIClick", player)
		end
		task.delay(0.6, function()
			busy[player.UserId] = nil
		end)
	end)
end)

DataManager.StartAutoSaveLoop()

print("✅ [ServerMain] Systems started")
