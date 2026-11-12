--!strict
-- ============================================================================
-- 🗺️ MODULE: TreasureMapService (ServerScriptService.Modules.TreasureMapService)
-- Night Merchant "Treasure Map": hides one treasure per player on the island surface
-- (curated open-ground spots from MerchantConfig), shows a marker (red X, half-buried
-- chest, golden beam, name tag) and pays out when the owner digs it up.
-- The purchase itself (coins, night/distance checks) is validated by ServerMain.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MerchantConfig = require(Modules:WaitForChild("MerchantConfig"))
local PartKit = require(Modules:WaitForChild("PartKit"))

local TreasureMapService = {}

type Treasure = {
	Model: Model,
	Position: Vector3,
	Digging: boolean,
}

type Deps = {
	DataManager: any,
	SoundManager: any,
	VFXModule: any,
	SyncRemote: RemoteEvent?,
}

local Active: { [number]: Treasure } = {}
local Injected: Deps? = nil
local Rng = Random.new()
local Folder: Folder? = nil

local COMPASS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }

-- -Z is north (where the mine is), +X is east
function TreasureMapService.Describe(from: Vector3, to: Vector3): (string, number)
	local dx, dz = to.X - from.X, to.Z - from.Z
	local deg = math.deg(math.atan2(dx, -dz)) % 360
	local idx = math.floor((deg + 22.5) / 45) % 8 + 1
	return COMPASS[idx], math.floor(math.sqrt(dx * dx + dz * dz) + 0.5)
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Marker model with its pivot on the ground surface. "Hitbox" carries the Dig prompt.
function TreasureMapService.BuildMarker(ownerName: string): Model
	local model = Instance.new("Model")
	model.Name = "Treasure_" .. ownerName
	local wood, woodDark, gold = rgb(122, 80, 44), rgb(84, 52, 30), rgb(255, 204, 60)
	local W, M = Enum.Material.Wood, Enum.Material.Metal

	local hitbox = PartKit.Block(model, "Hitbox", Vector3.new(4.5, 3, 4.5), CFrame.new(0, 1.2, 0), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1 })
	model.WorldPivot = CFrame.new() -- pivot on the ground so PivotTo places the marker on the surface

	PartKit.Ellipsoid(model, "Mound", Vector3.new(4.2, 0.9, 3.2), CFrame.new(0, 0.05, 0), rgb(112, 80, 52), Enum.Material.Ground)
	-- chest: half buried, tilted a little
	local tilt = CFrame.Angles(0, math.rad(18), math.rad(-5))
	PartKit.Block(model, "ChestBody", Vector3.new(2.4, 1.3, 1.5), tilt * CFrame.new(0, 0.4, 0), wood, W)
	PartKit.Cylinder(model, "ChestLid", 1.5, 2.4, tilt * CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)), woodDark, W)
	for _, sx in ipairs({ -0.85, 0.85 }) do
		PartKit.Block(model, "TrimBand", Vector3.new(0.18, 1.34, 1.56), tilt * CFrame.new(sx, 0.4, 0), gold, M)
		PartKit.Cylinder(model, "TrimBandLid", 1.56, 0.18, tilt * CFrame.new(sx, 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)), gold, M)
	end
	PartKit.Block(model, "Lock", Vector3.new(0.36, 0.46, 0.1), tilt * CFrame.new(0, 0.9, 0.78), gold, M)
	-- spilled coins and the red X on the ground
	for i = 1, 5 do
		local a = math.rad(i * 50 + 20)
		PartKit.Cylinder(model, "Coin", 0.5, 0.07, CFrame.new(math.cos(a) * 1.9, 0.12, 1.1 + math.sin(a) * 0.5) * CFrame.Angles(math.rad(Rng:NextNumber(-20, 20)), 0, math.rad(Rng:NextNumber(-20, 20))), gold, M)
	end
	for _, s in ipairs({ -45, 45 }) do
		PartKit.Block(model, "MarkX", Vector3.new(3.2, 0.06, 0.55), CFrame.new(0, 0.05, 3.2) * CFrame.Angles(0, math.rad(s), 0), rgb(214, 30, 34), Enum.Material.SmoothPlastic)
	end

	-- soft golden beam and sparkles
	local beam = PartKit.Cylinder(model, "Beam", 1.4, 36, CFrame.new(0, 18, 0), rgb(255, 210, 90), Enum.Material.Neon, { Transparency = 0.82, CastShadow = false })
	PartKit.PointLight(beam, rgb(255, 205, 90), 1.5, 16)
	PartKit.Emitter(hitbox, {
		Name = "TreasureSparkles", Color = rgb(255, 230, 140), Color2 = rgb(255, 190, 60), Rate = 10,
		Lifetime = NumberRange.new(1.2, 2.0), Speed = NumberRange.new(1, 3), SizeStart = 0.5, Spread = 60,
		Acceleration = Vector3.new(0, 2, 0),
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "TreasureTag"
	gui.Size = UDim2.fromOffset(240, 34)
	gui.StudsOffset = Vector3.new(0, 5.5, 0)
	gui.MaxDistance = 140
	gui.AlwaysOnTop = false
	gui.Adornee = hitbox
	gui.Parent = hitbox
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = rgb(255, 226, 120)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = rgb(40, 24, 8)
	label.Text = "💰 " .. ownerName .. "'s treasure"
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DigPrompt"
	prompt.ActionText = "Dig"
	prompt.ObjectText = "Treasure"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = MerchantConfig.TreasureMap.HoldSeconds
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = hitbox
	return model
end

local function groundAt(x: number, z: number, ignore: Instance): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local hit = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -120, 0), params)
	-- props on the ground would lift the marker: only accept ground-level hits
	if hit and hit.Position.Y < 1.2 and hit.Position.Y > -1 then
		return hit.Position
	end
	return Vector3.new(x, 0, z)
end

local function markerFolder(): Folder
	if Folder and Folder.Parent then
		return Folder
	end
	local f = Instance.new("Folder")
	f.Name = "TreasureMarkers"
	f.Parent = workspace
	Folder = f
	return f
end

local function remove(player: Player)
	local t = Active[player.UserId]
	if t then
		Active[player.UserId] = nil
		t.Model:Destroy()
	end
end

function TreasureMapService.HasActive(player: Player): boolean
	return Active[player.UserId] ~= nil
end

local function dig(player: Player, owner: Player, treasure: Treasure)
	local deps = Injected
	if not deps or player ~= owner or treasure.Digging or Active[owner.UserId] ~= treasure then
		return
	end
	local profile = deps.DataManager.GetProfile(owner)
	if not profile then
		return
	end
	treasure.Digging = true
	local cfg = MerchantConfig.TreasureMap
	local coins = math.floor(cfg.Price * Rng:NextNumber(cfg.LootMin, cfg.LootMax) + 0.5)
	local paid = deps.DataManager.GrantCoins(owner, coins, false)
	deps.DataManager.GrantXP(owner, cfg.XpBase + cfg.XpPerLevel * (profile.Level or 1))
	deps.DataManager.AddFunStat(owner, "TreasuresFound", 1)
	deps.DataManager.UpdateLeaderstats(owner)
	deps.DataManager.SyncToClient(owner, deps.SyncRemote)
	local pos = treasure.Position
	deps.SoundManager.PlayAt("CoinChime", pos)
	deps.VFXModule.PlayPurchaseOrSellBurst(pos + Vector3.new(0, 1, 0), rgb(255, 215, 65))
	deps.VFXModule.SpawnFloatingText(pos + Vector3.new(0, 3, 0), string.format("💰 Treasure found: +%d coins!", paid), rgb(255, 225, 75))
	remove(owner)
end

-- Hides a treasure for the player and returns the hint text. nil + reason if one is already active.
function TreasureMapService.Spawn(player: Player, from: Vector3): (string?, string?)
	if Active[player.UserId] then
		return nil, "🗺️ You already have a hidden treasure. Dig it up first!"
	end
	local spots = MerchantConfig.TreasureMap.Spots
	local spot = spots[Rng:NextInteger(1, #spots)]
	local folder = markerFolder()
	local pos = groundAt(spot.X, spot.Y, folder)
	local model = TreasureMapService.BuildMarker(player.Name)
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(Rng:NextNumber(0, 360)), 0))
	model.Parent = folder
	local treasure: Treasure = { Model = model, Position = pos, Digging = false }
	Active[player.UserId] = treasure
	local prompt = model:FindFirstChild("DigPrompt", true) :: ProximityPrompt?
	if prompt then
		prompt.Triggered:Connect(function(who: Player)
			dig(who, player, treasure)
		end)
	end
	local dirName, studs = TreasureMapService.Describe(from, pos)
	return string.format("🗺️ Treasure hidden %d studs to the %s!", studs, dirName), nil
end

function TreasureMapService.Start(deps: Deps)
	Injected = deps
	Players.PlayerRemoving:Connect(remove)
end

return TreasureMapService
