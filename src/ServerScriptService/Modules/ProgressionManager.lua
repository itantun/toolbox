--!strict
-- ============================================================================
-- 🌟 МОДУЛЬ: ProgressionManager (ServerScriptService.Modules.ProgressionManager)
-- ЗАДАЧА 1 — Серверная логика прокачки (v9.0):
-- • Начисление XP, повышение уровня (очко навыка, бонус монет, исцеление, золотые искры)
-- • Прокачка навыков (проверка очков и лимита 50 уровней)
-- • Престиж (с 50 уровня, макс. 10) + аура: золотая → алмазная → радужная
-- • Достижения: проверка прогресса, награды, уведомления
-- Все проверки выполняются ТОЛЬКО на сервере (защита от читов).
-- ============================================================================

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local ProgressionConfig = require(Modules:WaitForChild("ProgressionConfig"))

local ProgressionManager = {}

type Deps = {
	GetProfile: (Player) -> any,
	Sync: (Player) -> (),
}

local Deps: Deps? = nil
local ProgressionEvent: RemoteEvent? = nil
local RequestCooldown: { [string]: number } = {}

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- ============================================================================
-- 1. ДАННЫЕ ПРОФИЛЯ (значения по умолчанию, загрузка, сохранение)
-- ============================================================================
local function emptySkills(): { [string]: number }
	local t: { [string]: number } = {}
	for _, id in ipairs(ProgressionConfig.SKILL_ORDER) do
		t[id] = 0
	end
	return t
end

function ProgressionManager.CreateDefaultData()
	return {
		SkillPoints = 0,
		Skills = emptySkills(),
		Prestige = 0,
		Achievements = {} :: { [string]: boolean },
		FoundOres = {} :: { [string]: boolean },
		PeakCoins = 0,
	}
end

-- Безопасно переносит сохранённые поля в профиль. Старые сохранения (v8) получают очки навыков за уже набранные уровни.
function ProgressionManager.ApplySavedData(profile: any, saved: any)
	if type(saved) ~= "table" then return end

	profile.Prestige = math.clamp(math.floor(tonumber(saved.Prestige) or 0), 0, ProgressionConfig.PRESTIGE_MAX)
	profile.PeakCoins = math.max(profile.Coins or 0, tonumber(saved.PeakCoins) or 0)

	if type(saved.Skills) == "table" then
		for _, id in ipairs(ProgressionConfig.SKILL_ORDER) do
			profile.Skills[id] = math.clamp(math.floor(tonumber(saved.Skills[id]) or 0), 0, ProgressionConfig.SKILL_MAX_LEVEL)
		end
		profile.SkillPoints = math.max(0, math.floor(tonumber(saved.SkillPoints) or 0))
	else
		-- Миграция со старой версии: выдаём очки за все уже набранные уровни
		profile.SkillPoints = math.max(0, (profile.Level or 1) - 1) * ProgressionConfig.SKILL_POINTS_PER_LEVEL
	end

	if type(saved.Achievements) == "table" then
		for _, ach in ipairs(ProgressionConfig.ACHIEVEMENTS) do
			if saved.Achievements[ach.Id] == true then
				profile.Achievements[ach.Id] = true
			end
		end
	end

	if type(saved.FoundOres) == "table" then
		for k, v in pairs(saved.FoundOres) do
			if type(k) == "string" and v == true then
				profile.FoundOres[k] = true
			end
		end
	end

	-- Формула XP изменилась (Level * 100): XP не может превышать требование текущего уровня
	profile.XP = math.clamp(profile.XP or 0, 0, ProgressionConfig.GetRequiredXP(profile.Level) - 1)
end

function ProgressionManager.GetSaveData(profile: any)
	return {
		SkillPoints = profile.SkillPoints,
		Skills = profile.Skills,
		Prestige = profile.Prestige,
		Achievements = profile.Achievements,
		FoundOres = profile.FoundOres,
		PeakCoins = profile.PeakCoins,
	}
end

-- ============================================================================
-- 2. УТИЛИТЫ
-- ============================================================================
local function fire(player: Player, eventType: string, payload: any)
	if ProgressionEvent then
		pcall(function()
			(ProgressionEvent :: RemoteEvent):FireClient(player, eventType, payload)
		end)
	end
end

-- v50: lets other server modules send a ProgressionEvent message to one client
function ProgressionManager.Notify(player: Player, eventType: string, payload: any)
	fire(player, eventType, payload)
end

local function sync(player: Player)
	if Deps then
		Deps.Sync(player)
	end
end

local function getRoot(player: Player): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function rateLimited(player: Player, action: string, seconds: number): boolean
	local key = tostring(player.UserId) .. ":" .. action
	local now = os.clock()
	if (now - (RequestCooldown[key] or 0)) < seconds then
		return true
	end
	RequestCooldown[key] = now
	return false
end

-- Обновляет рекорд накопленных монет (для достижения «Богач»)
function ProgressionManager.TrackCoins(profile: any)
	if (profile.Coins or 0) > (profile.PeakCoins or 0) then
		profile.PeakCoins = profile.Coins
	end
end

function ProgressionManager.CountOresFound(profile: any): number
	local count = 0
	for _, b in ipairs(GameConfig.BLOCK_LIST) do
		if profile.FoundOres[b.Id] then
			count += 1
		end
	end
	return count
end

function ProgressionManager.GetStatValue(profile: any, stat: string): number
	if stat == "TotalMined" then
		return profile.TotalMined or 0
	elseif stat == "PeakCoins" then
		return profile.PeakCoins or 0
	elseif stat == "OresFound" then
		return ProgressionManager.CountOresFound(profile)
	elseif stat == "MaxDepth" then
		return profile.MaxDepthReached or 0
	elseif stat == "BestCombo" or stat == "LuckyOpened" or stat == "TntExploded"
		or stat == "TreasuresFound" or stat == "DailyStreak" then
		return profile[stat] or 0
	end
	return 0
end

-- ============================================================================
-- 3. ВИЗУАЛЬНЫЕ ЭФФЕКТЫ (видны всем игрокам)
-- ============================================================================
local function emitBurst(root: BasePart, colors: { Color3 }, count: number, speed: number, size: number)
	local att = Instance.new("Attachment")
	att.Name = "ProgressionBurst"
	att.Parent = root

	local keypoints = {}
	for i, c in ipairs(colors) do
		local t = (#colors == 1) and 0 or (i - 1) / (#colors - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(t, c))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end

	local pe = Instance.new("ParticleEmitter")
	pe.Texture = SPARKLE_TEXTURE
	pe.Color = ColorSequence.new(keypoints)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(0.6, size * 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(0.8, 1.5)
	pe.Speed = NumberRange.new(speed * 0.6, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -6, 0)
	pe.Drag = 2
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-180, 180)
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(count)

	local light = Instance.new("PointLight")
	light.Color = colors[1]
	light.Range = 14
	light.Brightness = 3
	light.Parent = att

	task.delay(0.4, function()
		if light.Parent then light.Brightness = 1.2 end
	end)
	Debris:AddItem(att, 2.5)
end

-- Аура престижа вокруг игрока: золотая (1–3) → алмазная (4–6) → радужная (7–10)
function ProgressionManager.ApplyAura(character: Model?, prestige: number)
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end

	local old = root:FindFirstChild("PrestigeAura")
	if old then old:Destroy() end
	local oldTag = character:FindFirstChild("PrestigeTag")
	if oldTag then oldTag:Destroy() end

	local aura = ProgressionConfig.GetAura(prestige)
	if not aura then return end

	local att = Instance.new("Attachment")
	att.Name = "PrestigeAura"
	att.Position = Vector3.new(0, -2.6, 0)
	att.Parent = root

	local keypoints = {}
	for i, c in ipairs(aura.Colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #aura.Colors - 1), c))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, aura.Colors[1]))
	end

	-- Поднимающиеся искры от ног
	local rise = Instance.new("ParticleEmitter")
	rise.Name = "AuraRise"
	rise.Texture = SPARKLE_TEXTURE
	rise.Color = ColorSequence.new(keypoints)
	rise.LightEmission = 1
	rise.LightInfluence = 0
	rise.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	rise.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	rise.Lifetime = NumberRange.new(1.0, 1.8)
	rise.Speed = NumberRange.new(2, 4)
	rise.EmissionDirection = Enum.NormalId.Top
	rise.SpreadAngle = Vector2.new(35, 35)
	rise.Acceleration = Vector3.new(0, 1.5, 0)
	rise.Rotation = NumberRange.new(0, 360)
	rise.RotSpeed = NumberRange.new(-90, 90)
	rise.Rate = 10 + prestige * 3
	rise.Parent = att

	local light = Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Color = aura.Colors[1]
	light.Range = 8 + prestige * 0.5
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = att

	-- Значок престижа над головой
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local bb = Instance.new("BillboardGui")
		bb.Name = "PrestigeTag"
		bb.Size = UDim2.new(0, 130, 0, 28)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.MaxDistance = 80
		bb.Adornee = head
		bb.Parent = character

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.Text = string.format("👑 Prestige %d", prestige)
		lbl.TextColor3 = aura.Colors[1]
		lbl.TextStrokeTransparency = 0.4
		lbl.Parent = bb
	end

	-- Радужная аура плавно переливается цветами
	if aura.Rainbow then
		task.spawn(function()
			local hue = 0
			while att.Parent do
				hue = (hue + 0.01) % 1
				light.Color = Color3.fromHSV(hue, 0.8, 1)
				local tag = character:FindFirstChild("PrestigeTag")
				local lbl = tag and tag:FindFirstChildOfClass("TextLabel")
				if lbl then
					lbl.TextColor3 = Color3.fromHSV(hue, 0.6, 1)
				end
				task.wait(0.1)
			end
		end)
	end
end

-- ============================================================================
-- 4. ДОСТИЖЕНИЯ
-- ============================================================================
function ProgressionManager.CheckAchievements(player: Player, profile: any): boolean
	local anyUnlocked = false
	for _, ach in ipairs(ProgressionConfig.ACHIEVEMENTS) do
		if not profile.Achievements[ach.Id] then
			local goal = ProgressionConfig.GetAchievementGoal(ach)
			if goal > 0 and ProgressionManager.GetStatValue(profile, ach.Stat) >= goal then
				profile.Achievements[ach.Id] = true
				profile.Coins += ach.RewardCoins
				profile.SkillPoints += ach.RewardSkillPoints
				ProgressionManager.TrackCoins(profile)
				anyUnlocked = true

				fire(player, "Achievement", {
					Id = ach.Id,
					Name = ach.Name,
					Icon = ach.Icon,
					RewardCoins = ach.RewardCoins,
					RewardSkillPoints = ach.RewardSkillPoints,
				})

				local root = getRoot(player)
				if root then
					emitBurst(root, { Color3.fromRGB(255, 215, 60), Color3.fromRGB(255, 255, 255) }, 30, 14, 0.6)
				end
			end
		end
	end
	return anyUnlocked
end

-- Отмечает найденный вид руды (для «Коллекционера»)
function ProgressionManager.RegisterOreFound(profile: any, blockId: string)
	profile.FoundOres[blockId] = true
end

-- ============================================================================
-- 5. ОПЫТ И ПОВЫШЕНИЕ УРОВНЯ
-- ============================================================================
local function onLevelUp(player: Player, profile: any, levelsGained: number, bonusCoins: number)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid and ProgressionConfig.LEVEL_UP_HEAL then
		humanoid.Health = humanoid.MaxHealth
	end

	local root = getRoot(player)
	if root then
		-- Золотые искры + «фейерверк» вокруг игрока
		emitBurst(root, { Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 180, 30) }, 70, 22, 0.8)
		task.delay(0.25, function()
			if root.Parent then
				emitBurst(root, { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 215, 60) }, 40, 30, 0.5)
			end
		end)
	end

	fire(player, "LevelUp", {
		Level = profile.Level,
		LevelsGained = levelsGained,
		BonusCoins = bonusCoins,
		SkillPoints = profile.SkillPoints,
		CanPrestige = profile.Level >= ProgressionConfig.PRESTIGE_REQUIRED_LEVEL and profile.Prestige < ProgressionConfig.PRESTIGE_MAX,
	})
end

-- Начисляет XP (с учётом бонуса престижа). Возвращает число полученных уровней.
function ProgressionManager.GrantXP(player: Player, profile: any, rawAmount: number): number
	local amount = math.max(0, math.floor(rawAmount * ProgressionConfig.GetXPMultiplier(profile.Prestige) + 0.5))
	profile.XP += amount

	local gained = 0
	local bonusCoins = 0
	local req = ProgressionConfig.GetRequiredXP(profile.Level)
	while profile.XP >= req do
		profile.XP -= req
		profile.Level += 1
		profile.SkillPoints += ProgressionConfig.SKILL_POINTS_PER_LEVEL
		bonusCoins += profile.Level * ProgressionConfig.LEVEL_UP_COINS_PER_LEVEL
		gained += 1
		req = ProgressionConfig.GetRequiredXP(profile.Level)
	end

	if gained > 0 then
		profile.Coins += bonusCoins
		ProgressionManager.TrackCoins(profile)
		onLevelUp(player, profile, gained, bonusCoins)
	end
	return gained
end

-- ============================================================================
-- 6. ПРОКАЧКА НАВЫКОВ
-- ============================================================================
function ProgressionManager.UpgradeSkill(player: Player, skillId: any, amount: any)
	if not Deps then return end
	if type(skillId) ~= "string" or not ProgressionConfig.SKILLS[skillId] then return end
	if rateLimited(player, "Skill", 0.12) then return end

	local profile = Deps.GetProfile(player)
	if not profile then return end

	local current = ProgressionConfig.GetSkillLevel(profile.Skills, skillId)
	if current >= ProgressionConfig.SKILL_MAX_LEVEL then
		fire(player, "Toast", { Text = "⭐ Skill is already max level!", Color = Color3.fromRGB(255, 215, 60) })
		return
	end
	if profile.SkillPoints <= 0 then
		fire(player, "Toast", { Text = "No skill points! Level up ⛏️", Color = Color3.fromRGB(255, 95, 95) })
		return
	end

	local want = 1
	if amount == "max" then
		want = ProgressionConfig.SKILL_MAX_LEVEL
	elseif type(amount) == "number" then
		want = math.clamp(math.floor(amount), 1, ProgressionConfig.SKILL_MAX_LEVEL)
	end

	local add = math.min(want, profile.SkillPoints, ProgressionConfig.SKILL_MAX_LEVEL - current)
	profile.Skills[skillId] = current + add
	profile.SkillPoints -= add

	fire(player, "SkillUpgraded", { SkillId = skillId, Level = profile.Skills[skillId], Added = add })
	sync(player)
end

-- ============================================================================
-- 7. ПРЕСТИЖ
-- ============================================================================
function ProgressionManager.DoPrestige(player: Player)
	if not Deps then return end
	if rateLimited(player, "Prestige", 1.0) then return end

	local profile = Deps.GetProfile(player)
	if not profile then return end

	if profile.Prestige >= ProgressionConfig.PRESTIGE_MAX then
		fire(player, "Toast", { Text = "👑 Max prestige reached!", Color = Color3.fromRGB(255, 215, 60) })
		return
	end
	if profile.Level < ProgressionConfig.PRESTIGE_REQUIRED_LEVEL then
		fire(player, "Toast", {
			Text = string.format("Level %d required for prestige!", ProgressionConfig.PRESTIGE_REQUIRED_LEVEL),
			Color = Color3.fromRGB(255, 95, 95),
		})
		return
	end

	profile.Prestige += 1
	profile.Level = ProgressionConfig.START_LEVEL
	profile.XP = 0
	if ProgressionConfig.PRESTIGE_RESETS_SKILLS then
		profile.Skills = emptySkills()
		profile.SkillPoints = 0
	end

	ProgressionManager.ApplyAura(player.Character, profile.Prestige)

	local aura = ProgressionConfig.GetAura(profile.Prestige)
	local root = getRoot(player)
	if root and aura then
		emitBurst(root, aura.Colors, 120, 34, 1.0)
	end

	fire(player, "Prestige", {
		Prestige = profile.Prestige,
		AuraName = aura and aura.Name or "",
		BonusPercent = math.floor((ProgressionConfig.GetPrestigeMultiplier(profile.Prestige) - 1) * 100 + 0.5),
	})
	sync(player)
end

-- ============================================================================
-- 8. ИНИЦИАЛИЗАЦИЯ (вызывается из ServerMain)
-- ============================================================================
function ProgressionManager.Init(deps: Deps, remotes: { UpgradeSkill: RemoteEvent, Prestige: RemoteEvent, ProgressionEvent: RemoteEvent })
	Deps = deps
	ProgressionEvent = remotes.ProgressionEvent

	remotes.UpgradeSkill.OnServerEvent:Connect(function(player: Player, skillId: any, amount: any)
		local ok, err = pcall(function()
			ProgressionManager.UpgradeSkill(player, skillId, amount)
		end)
		if not ok then warn("[ProgressionManager] UpgradeSkill:", err) end
	end)

	remotes.Prestige.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(function()
			ProgressionManager.DoPrestige(player)
		end)
		if not ok then warn("[ProgressionManager] Prestige:", err) end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		RequestCooldown[tostring(player.UserId) .. ":Skill"] = nil
		RequestCooldown[tostring(player.UserId) .. ":Prestige"] = nil
	end)
end

return ProgressionManager
