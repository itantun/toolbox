--!strict
-- ============================================================================
-- 🔊 МОДУЛЬ: SoundManager (ReplicatedStorage.Modules.SoundManager) — v10
-- • Настоящие звуки добычи руды (удар кирки + каменная крошка / металлический звон)
-- • Пул вариантов + случайная высота тона → каждый удар звучит немного иначе
-- • Звук играет ЛОКАЛЬНО у каждого клиента (через RemoteEvent "SfxEvent"):
--   - игрок, который бьёт, слышит удар мгновенно (без задержки сети) и без «двойного» звука
--   - остальные игроки рядом (до 90 studs) тоже слышат удары
-- • Больше НЕ создаёт 2 Sound в каждом блоке шахты (раньше это тысячи лишних объектов)
-- API совместим с v8/v9: EnsureSoundsFolder, AttachQuietBlockSounds, PlayQuietTap,
-- PlayQuietCrumble, PlayUISound.
-- ============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local SoundManager = {}

local IS_SERVER = RunService:IsServer()
local HEAR_DISTANCE = 90
local rng = Random.new()
local preloaded = false
local clientHooked = false
local sfxRemote: RemoteEvent? = nil

type Layer = { Ids: { string }, Volume: number?, PitchMin: number?, PitchMax: number?, Delay: number?, MaxDuration: number? }

local function pick(ids: { string }?): string?
	if not ids or #ids == 0 then return nil end
	return ids[rng:NextInteger(1, #ids)]
end

local function getRemote(): RemoteEvent?
	if sfxRemote then return sfxRemote end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if IS_SERVER then
		if not folder then
			local f = Instance.new("Folder")
			f.Name = "Remotes"
			f.Parent = ReplicatedStorage
			folder = f
		end
		local re = (folder :: Instance):FindFirstChild("SfxEvent")
		if not re then
			local n = Instance.new("RemoteEvent")
			n.Name = "SfxEvent"
			n.Parent = folder
			re = n
		end
		sfxRemote = re :: RemoteEvent
	elseif folder then
		local re = folder:FindFirstChild("SfxEvent")
		if re and re:IsA("RemoteEvent") then sfxRemote = re end
	end
	return sfxRemote
end

-- Плавно глушит звук через maxDuration секунд (чтобы удар не «тянулся»)
local function limit(s: Sound, maxDuration: number?)
	if not maxDuration then return end
	task.delay(maxDuration, function()
		if s.Parent and s.IsPlaying then
			TweenService:Create(s, TweenInfo.new(0.12), { Volume = 0 }):Play()
		end
	end)
end

-- Проигрывает один слой звука (3D, если задана позиция; иначе 2D)
local function playLayer(layer: Layer, position: Vector3?, volumeMul: number)
	local id = pick(layer.Ids)
	if not id then return end
	local function go()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = (layer.Volume or 0.4) * volumeMul
		s.PlaybackSpeed = rng:NextNumber(layer.PitchMin or 1, layer.PitchMax or 1)
		if position then
			local att = Instance.new("Attachment")
			att.WorldPosition = position
			att.Parent = Workspace.Terrain
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 10
			s.RollOffMaxDistance = HEAR_DISTANCE
			s.Parent = att
			Debris:AddItem(att, 3)
		else
			s.Parent = SoundService
			Debris:AddItem(s, 6)
		end
		s:Play()
		limit(s, layer.MaxDuration)
	end
	if layer.Delay and layer.Delay > 0 then
		task.delay(layer.Delay, go)
	else
		go()
	end
end

-- Проигрывает звук по ключу из GameConfig.SOUNDS локально (вызывается на клиенте)
local function playLocal(soundKey: string, position: Vector3?)
	local cfg: any = GameConfig.SOUNDS[soundKey]
	if not cfg then return end
	pcall(function()
		playLayer(cfg :: Layer, position, 1)
		if cfg.Layers then
			for _, layer in ipairs(cfg.Layers) do
				playLayer(layer :: Layer, position, 1)
			end
		end
	end)
end

-- На сервере: отправить звук игрокам рядом (кроме exclude); position = nil → 2D звук только target
local function broadcast(soundKey: string, position: Vector3?, exclude: Player?, onlyTarget: Player?)
	local re = getRemote()
	if not re then return end
	if onlyTarget then
		re:FireClient(onlyTarget, soundKey, position)
		return
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= exclude then
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if position == nil or (root and root:IsA("BasePart") and (root.Position - position).Magnitude <= HEAR_DISTANCE) then
				re:FireClient(plr, soundKey, position)
			end
		end
	end
end

local function hookClient()
	if IS_SERVER or clientHooked then return end
	clientHooked = true
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Remotes", 30)
		local re = folder and folder:WaitForChild("SfxEvent", 30)
		if re and re:IsA("RemoteEvent") then
			sfxRemote = re
			re.OnClientEvent:Connect(function(soundKey: any, position: any)
				if type(soundKey) == "string" then
					playLocal(soundKey, typeof(position) == "Vector3" and position or nil)
				end
			end)
		end
	end)
end

function SoundManager.ResetCleanAudioEnvironment()
	pcall(function()
		SoundService.AmbientReverb = Enum.ReverbType.NoReverb
	end)
end

-- Создаёт папку ReplicatedStorage.Sounds (для предзагрузки) и подключает клиент к SfxEvent
function SoundManager.EnsureSoundsFolder(): Folder
	SoundManager.ResetCleanAudioEnvironment()
	if IS_SERVER then
		getRemote()
	else
		hookClient()
	end

	local existing = ReplicatedStorage:FindFirstChild("Sounds")
	local folder: Folder
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Sounds"
		folder.Parent = ReplicatedStorage
	end

	local toPreload: { Instance } = {}
	if IS_SERVER then
		for soundKey, cfgAny in pairs(GameConfig.SOUNDS) do
			local cfg: any = cfgAny
			local ids: { string } = {}
			for _, id in ipairs(cfg.Ids or {}) do table.insert(ids, id) end
			for _, layer in ipairs(cfg.Layers or {}) do
				for _, id in ipairs(layer.Ids or {}) do table.insert(ids, id) end
			end
			for i, id in ipairs(ids) do
				local name = soundKey .. (i == 1 and "" or "_" .. i)
				local found = folder:FindFirstChild(name)
				local snd: Sound
				if found and found:IsA("Sound") then
					snd = found
				else
					snd = Instance.new("Sound")
					snd.Name = name
					snd.Parent = folder
				end
				snd.SoundId = id
				snd.Volume = 0
			end
		end
	else
		for _, s in ipairs(folder:GetChildren()) do
			table.insert(toPreload, s)
		end
		if not preloaded then
			preloaded = true
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync(toPreload)
				end)
			end)
		end
	end
	return folder
end

-- Оставлено для совместимости: звуки больше не вкладываются в каждый блок
function SoundManager.AttachQuietBlockSounds(_block: BasePart, _hitSoundKey: string) end

-- Удар кирки по блоку.
-- Клиент: играет сразу у себя. Сервер: рассылает остальным игрокам рядом (кроме ударившего).
function SoundManager.PlayQuietTap(soundKey: string, blockPosition: Vector3, _hostBlock: BasePart?, excludePlayer: Player?)
	if not GameConfig.SOUNDS[soundKey] then soundKey = "StoneTap" end
	if IS_SERVER then
		broadcast(soundKey, blockPosition, excludePlayer, nil)
	else
		playLocal(soundKey, blockPosition)
	end
end

-- Разрушение блока (сервер рассылает всем рядом, включая ударившего)
function SoundManager.PlayQuietCrumble(blockPosition: Vector3)
	if IS_SERVER then
		broadcast("StoneCrumble", blockPosition, nil, nil)
	else
		playLocal("StoneCrumble", blockPosition)
	end
end

-- 2D-звук интерфейса. На сервере нужно указать игрока: PlayUISound("CoinChime", player)
function SoundManager.PlayUISound(soundKey: string, targetPlayer: Player?)
	if IS_SERVER then
		if targetPlayer then
			broadcast(soundKey, nil, nil, targetPlayer)
		end
	else
		playLocal(soundKey, nil)
	end
end

-- Звук в точке мира для всех рядом (продажа, покупка)
function SoundManager.PlayAt(soundKey: string, position: Vector3)
	if IS_SERVER then
		broadcast(soundKey, position, nil, nil)
	else
		playLocal(soundKey, position)
	end
end

return SoundManager
