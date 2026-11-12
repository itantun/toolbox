--!strict
-- ============================================================================
-- 🌍 МОДУЛЬ: WorldBuilder (ServerScriptService.Modules.WorldBuilder)
-- Версия: v13.0 — Выполняет Пункты №5, №10, №12 и №13:
-- • Большая шахта-выработка 30×30×30 блоков (120×120×120 studs), все стены и блоки
--   имеют CanCollide = true, Anchored = true, Transparency = 0 (без щелей и провалов).
-- • Ночной барьер входа в шахту (NightMineBarrier): ночью закрывает вход сверху!
-- • Неоновый павильон магазина «🛒 SHOP» (по референсу Неоновая площадь магазина и продажи.png)
--   с 4 3D-пьедесталами рюкзаков/кирок и голубой неоновой вывеской.
-- • Современный большой пункт приёма руды «$ SELL» (Пункт №13 ТЗ):
--   - зелёная неоновая арка "$ SELL" со стрелками и символом обмена;
--   - прилавок и механические весы приёма руды;
--   - NPC Скупщик руды Гром в оранжевой каске;
--   - электронное табло с курсами всех руд и Утренних Залежей ×3;
--   - мешки с рудой, ржавые вагонетки на рельсах, фонари и частицы монет.
-- ============================================================================

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))
-- v52: процедурные постройки «сочного» обновления
local SpawnPlazaBuilder = require(script.Parent:WaitForChild("SpawnPlazaBuilder"))
local VFXModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("VFXModule"))

local WorldBuilder = {}

local NightLights: { PointLight } = {}
local FlickerLamps: { { Light: PointLight, BaseBrightness: number, Globe: BasePart } } = {}
local ChestCooldowns: { [string]: number } = {}
local NightBarrierPart: Part? = nil
local MineSignLabel: TextLabel? = nil
local MineSignNeon: { BasePart } = {}

local function makePart(
	name: string,
	size: Vector3,
	cframeOrPos: CFrame | Vector3,
	color: Color3,
	mat: Enum.Material?,
	parent: Instance,
	shape: Enum.PartType?,
	canCollide: boolean?,
	transparency: number?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	if typeof(cframeOrPos) == "CFrame" then
		p.CFrame = cframeOrPos
	else
		p.Position = cframeOrPos
	end
	p.Anchored = true
	p.CanCollide = (canCollide == nil) and true or canCollide
	p.CanTouch = false
	p.Transparency = transparency or 0
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.TopSurface = Enum.SurfaceType.SmoothNoOutlines
	p.BottomSurface = Enum.SurfaceType.SmoothNoOutlines
	p.LeftSurface = Enum.SurfaceType.SmoothNoOutlines
	p.RightSurface = Enum.SurfaceType.SmoothNoOutlines
	p.FrontSurface = Enum.SurfaceType.SmoothNoOutlines
	p.BackSurface = Enum.SurfaceType.SmoothNoOutlines
	p.Parent = parent
	return p
end

function WorldBuilder.ApplyUploadedGreenTilePattern(targetPart: BasePart, useDarkVariant: boolean)
	local pal = useDarkVariant and GameConfig.TEXTURES.DarkGreenTilePalette or GameConfig.TEXTURES.LightGreenTilePalette
	targetPart.Color = pal.Base

	local tex = Instance.new("Texture")
	tex.Name = useDarkVariant and "UploadedDarkGreenTileTex" or "UploadedLightGreenTileTex"
	tex.Face = Enum.NormalId.Top
	tex.Texture = useDarkVariant and GameConfig.TEXTURES.UploadedDarkGreenTile or GameConfig.TEXTURES.UploadedLightGreenTile
	tex.Color3 = pal.Grid
	tex.Transparency = 0.35
	tex.StudsPerTileU = 3.5
	tex.StudsPerTileV = 3.5
	tex.Parent = targetPart
end

function WorldBuilder.SetupOpenSky2026()
	pcall(function()
		MaterialService.Use2022Materials = true
	end)
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)

	Lighting.ClockTime = 14.0
	Lighting.Brightness = GameConfig.LIGHTING.DayBrightness
	Lighting.Ambient = GameConfig.LIGHTING.DayAmbient
	Lighting.OutdoorAmbient = GameConfig.LIGHTING.DayOutdoorAmbient
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1.0
	Lighting.EnvironmentSpecularScale = 0.3 -- v47: убрали стеклянные блики солнца

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local sky = Instance.new("Sky", Lighting)
	sky.Name = "OpenSkybox2026"
	sky.SunAngularSize = 18
	sky.MoonAngularSize = 12
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true

	local atmosphere = Instance.new("Atmosphere", Lighting)
	atmosphere.Name = "MineAtmosphere"
	atmosphere.Density = 0.24
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(185, 210, 240)
	atmosphere.Decay = Color3.fromRGB(95, 115, 145)
	atmosphere.Glare = 0.12
	atmosphere.Haze = 1.1

	local cc = Instance.new("ColorCorrectionEffect", Lighting)
	cc.Name = "ModernColorCorrection"
	cc.Saturation = GameConfig.LIGHTING.Saturation
	cc.Contrast = 0.10
	cc.Brightness = 0.01

	local bloom = Instance.new("BloomEffect", Lighting)
	bloom.Name = "NeonBloom"
	bloom.Intensity = 0.48
	bloom.Size = 22
	bloom.Threshold = 0.86

	local sunRays = Instance.new("SunRaysEffect", Lighting)
	sunRays.Name = "DaySunRays"
	sunRays.Intensity = 0.07
	sunRays.Spread = 0.65

	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds", Workspace.Terrain)
	clouds.Cover = 0.52
	clouds.Density = 0.45
	clouds.Color = Color3.fromRGB(252, 254, 255)
end

-- ============================================================================
-- v19: NIGHT MERCHANT STALL (reference photo + NightMinerMarket.server.lua)
-- Visible ONLY at night: wooden stall, lanterns, a STANDING merchant in a top hat,
-- repair kit, books, burger, soda, potions, candles, ore buyback table with scales.
-- ============================================================================
local NightMerchantModel: Model? = nil
local NightMerchantParent: Instance? = nil

function WorldBuilder.BuildNightMerchant(parent: Instance, basePos: Vector3): Model
	if NightMerchantModel then
		NightMerchantModel:Destroy()
		NightMerchantModel = nil
	end
	local m = Instance.new("Model")
	m.Name = "NightMerchantStall"
	local o = CFrame.new(basePos)

	local wood = Color3.fromRGB(105, 61, 34)
	local darkWood = Color3.fromRGB(64, 38, 27)
	local trim = Color3.fromRGB(145, 88, 45)
	local gold = Color3.fromRGB(255, 183, 75)
	local crystalBlue = Color3.fromRGB(65, 155, 255)
	local potionPink = Color3.fromRGB(205, 75, 230)
	local potionGreen = Color3.fromRGB(70, 220, 120)
	local suit = Color3.fromRGB(38, 34, 52)
	local skin = Color3.fromRGB(234, 190, 150)
	local purple = Color3.fromRGB(110, 60, 170)
	local ironCol = Color3.fromRGB(42, 48, 58)

	local function P(name: string, size: Vector3, x: number, y: number, z: number, color: Color3, mat: Enum.Material?, shape: Enum.PartType?, collide: boolean?, transp: number?, rot: CFrame?): Part
		local cf = o * CFrame.new(x, y, z)
		if rot then cf = cf * rot end
		return makePart(name, size, cf, color, mat, m, shape, collide == true, transp)
	end
	local function light(p: Instance, color: Color3, brightness: number, range: number)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Brightness = brightness
		l.Range = range
		l.Shadows = false
		l.Parent = p
	end
	local function boardText(p: Part, text: string, textColor: Color3)
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 50
		g.LightInfluence = 0
		g.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = text
		t.TextColor3 = textColor
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.Parent = g
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.fromRGB(40, 22, 12)
		st.Parent = t
	end
	local function cyl(name: string, height: number, diameter: number, x: number, y: number, z: number, color: Color3, mat: Enum.Material?): Part
		return P(name, Vector3.new(height, diameter, diameter), x, y, z, color, mat, Enum.PartType.Cylinder, false, nil, CFrame.Angles(0, 0, math.rad(90)))
	end
	local function candle(x: number, y: number, z: number)
		cyl("Candle", 0.55, 0.22, x, y + 0.28, z, Color3.fromRGB(240, 230, 200), Enum.Material.SmoothPlastic)
		local f = P("CandleFlame", Vector3.new(0.16, 0.16, 0.16), x, y + 0.66, z, gold, Enum.Material.Neon, Enum.PartType.Ball)
		light(f, gold, 0.8, 6)
	end
	local function potion(x: number, y: number, z: number, color: Color3)
		local b = P("Potion", Vector3.new(0.62, 0.62, 0.62), x, y + 0.31, z, color, Enum.Material.Glass, Enum.PartType.Ball, false, 0.12)
		cyl("PotionNeck", 0.32, 0.2, x, y + 0.72, z, Color3.fromRGB(200, 220, 230), Enum.Material.Glass)
		cyl("PotionCork", 0.12, 0.22, x, y + 0.92, z, trim, Enum.Material.Wood)
		light(b, color, 0.6, 5)
	end

	-- Floor and frame
	P("MerchantFloor", Vector3.new(30, 0.3, 13), -1.5, 0.15, -2.5, Color3.fromRGB(56, 50, 46), Enum.Material.Slate, nil, true)
	for _, x in ipairs({ -8.5, 8.5 }) do
		P("FrontPost", Vector3.new(0.7, 9, 0.7), x, 4.5, -6, darkWood, Enum.Material.Wood, nil, true)
		P("RearPost", Vector3.new(0.7, 9, 0.7), x, 4.5, 0, darkWood, Enum.Material.Wood, nil, true)
	end
	P("RoofBeamFront", Vector3.new(18, 0.7, 0.7), 0, 8.7, -6, trim, Enum.Material.Wood)
	P("RoofBeamBack", Vector3.new(18, 0.7, 0.7), 0, 8.7, 0, trim, Enum.Material.Wood)
	P("Roof", Vector3.new(20, 0.6, 8), 0, 9.3, -3, darkWood, Enum.Material.WoodPlanks, nil, true, nil, CFrame.Angles(math.rad(-7), 0, 0))
	-- Striped awning over the counter
	for i = -4, 4 do
		local col = (i % 2 == 0) and purple or Color3.fromRGB(40, 30, 62)
		P("AwningStripe", Vector3.new(2, 0.18, 2.4), i * 2, 8.35, -6.9, col, Enum.Material.Fabric, nil, false, nil, CFrame.Angles(math.rad(28), 0, 0))
	end

	-- Back wall and shelves
	P("BackWall", Vector3.new(17, 6.2, 0.4), 0, 5.4, -0.2, wood, Enum.Material.WoodPlanks, nil, true)
	local shelfYs = { 4.6, 6.0, 7.3 }
	for _, y in ipairs(shelfYs) do
		P("DisplayShelf", Vector3.new(15.5, 0.25, 1.0), 0, y, -0.85, trim, Enum.Material.WoodPlanks)
	end

	-- Counter
	P("MainCounter", Vector3.new(17, 3, 1.6), 0, 1.5, -5, darkWood, Enum.Material.WoodPlanks, nil, true)
	P("CounterTop", Vector3.new(17.6, 0.3, 2.0), 0, 3.15, -5, trim, Enum.Material.WoodPlanks, nil, true)
	local cy = 3.3

	-- Counter goods: repair kit, books, burger, soda, potions, top hat
	P("RepairKit", Vector3.new(1.5, 0.8, 0.8), -6.4, cy + 0.4, -5, Color3.fromRGB(190, 45, 38), Enum.Material.SmoothPlastic)
	P("RepairKitLid", Vector3.new(1.55, 0.12, 0.85), -6.4, cy + 0.6, -5, Color3.fromRGB(150, 32, 28), Enum.Material.SmoothPlastic)
	P("RepairKitHandle", Vector3.new(0.7, 0.12, 0.14), -6.4, cy + 0.95, -5, Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
	P("RepairKitLatch", Vector3.new(0.22, 0.16, 0.06), -6.4, cy + 0.52, -5.43, Color3.fromRGB(205, 210, 218), Enum.Material.Metal)
	for i, col in ipairs({ Color3.fromRGB(50, 85, 145), Color3.fromRGB(130, 40, 40), Color3.fromRGB(46, 110, 70) }) do
		P("Book", Vector3.new(1.1, 0.26, 0.8), -4.2 + (i - 2) * 0.06, cy + 0.13 + (i - 1) * 0.27, -5, col, Enum.Material.SmoothPlastic, nil, false, nil, CFrame.Angles(0, math.rad((i - 2) * 9), 0))
	end
	cyl("BurgerBunBottom", 0.28, 1.0, -2.2, cy + 0.14, -5, Color3.fromRGB(214, 150, 70), Enum.Material.SmoothPlastic)
	cyl("BurgerPatty", 0.2, 1.06, -2.2, cy + 0.38, -5, Color3.fromRGB(96, 52, 30), Enum.Material.SmoothPlastic)
	cyl("BurgerCheese", 0.06, 1.08, -2.2, cy + 0.5, -5, Color3.fromRGB(255, 196, 40), Enum.Material.SmoothPlastic)
	cyl("BurgerLettuce", 0.06, 1.1, -2.2, cy + 0.56, -5, Color3.fromRGB(90, 190, 60), Enum.Material.SmoothPlastic)
	P("BurgerBunTop", Vector3.new(1.0, 1.0, 1.0), -2.2, cy + 0.62, -5, Color3.fromRGB(222, 160, 76), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	cyl("SodaCan", 0.9, 0.5, -0.9, cy + 0.45, -5, Color3.fromRGB(220, 40, 50), Enum.Material.SmoothPlastic)
	cyl("SodaStraw", 0.6, 0.08, -0.82, cy + 1.1, -5, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	potion(1.0, cy, -5, crystalBlue)
	potion(2.0, cy, -5.1, potionPink)
	potion(3.0, cy, -5, potionGreen)
	cyl("TopHatBrim", 0.1, 1.5, 5.4, cy + 0.05, -5, Color3.fromRGB(24, 22, 28), Enum.Material.Fabric)
	cyl("TopHatCrown", 0.9, 0.95, 5.4, cy + 0.5, -5, Color3.fromRGB(24, 22, 28), Enum.Material.Fabric)
	cyl("TopHatBand", 0.18, 0.98, 5.4, cy + 0.2, -5, purple, Enum.Material.Fabric)
	candle(7.2, cy, -5)

	-- Shelf goods
	for i = 0, 4 do
		local col = (i % 2 == 0) and Color3.fromRGB(70, 50, 120) or Color3.fromRGB(150, 110, 60)
		P("ShelfBook", Vector3.new(0.28, 0.9, 0.7), -6.5 + i * 0.32, shelfYs[1] + 0.58, -0.85, col, Enum.Material.SmoothPlastic)
	end
	potion(-3.2, shelfYs[1] + 0.12, -0.85, potionPink)
	potion(-2.2, shelfYs[1] + 0.12, -0.85, crystalBlue)
	P("ShelfToolbox", Vector3.new(1.2, 0.7, 0.6), 0.2, shelfYs[1] + 0.48, -0.85, Color3.fromRGB(190, 45, 38), Enum.Material.SmoothPlastic)
	candle(2.4, shelfYs[1] + 0.12, -0.85)
	candle(3.0, shelfYs[1] + 0.12, -0.85)
	P("OreJar", Vector3.new(0.8, 0.9, 0.8), 5.2, shelfYs[1] + 0.58, -0.85, crystalBlue, Enum.Material.Glass, nil, false, 0.25)
	for i = 0, 3 do
		cyl("ShelfSoda", 0.8, 0.42, -5.5 + i * 0.7, shelfYs[2] + 0.53, -0.85, (i % 2 == 0) and Color3.fromRGB(220, 40, 50) or Color3.fromRGB(40, 140, 220), Enum.Material.SmoothPlastic)
	end
	potion(-1.0, shelfYs[2] + 0.12, -0.85, potionGreen)
	potion(0.0, shelfYs[2] + 0.12, -0.85, potionPink)
	potion(1.0, shelfYs[2] + 0.12, -0.85, crystalBlue)
	cyl("ShelfHatBrim", 0.1, 1.3, 4.5, shelfYs[2] + 0.18, -0.85, Color3.fromRGB(24, 22, 28), Enum.Material.Fabric)
	cyl("ShelfHatCrown", 0.8, 0.85, 4.5, shelfYs[2] + 0.6, -0.85, Color3.fromRGB(24, 22, 28), Enum.Material.Fabric)
	for i = 0, 2 do
		candle(-4 + i * 4, shelfYs[3] + 0.12, -0.85)
	end

	-- STANDING merchant (behind the counter, no seat)
	local nz = -2.7
	for _, sx in ipairs({ -1, 1 }) do
		P("MerchantLeg", Vector3.new(0.8, 2.6, 0.8), sx * 0.5, 1.3, nz, Color3.fromRGB(28, 26, 34), Enum.Material.Fabric)
		P("MerchantArm", Vector3.new(0.7, 2.2, 0.7), sx * 1.45, 3.75, nz - 0.2, suit, Enum.Material.Fabric, nil, false, nil, CFrame.Angles(math.rad(25), 0, 0))
		P("MerchantHand", Vector3.new(0.6, 0.6, 0.6), sx * 1.45, 2.85, nz - 0.75, skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	P("MerchantTorso", Vector3.new(2.2, 2.3, 1.1), 0, 3.75, nz, suit, Enum.Material.Fabric)
	P("MerchantShirt", Vector3.new(0.6, 1.7, 0.05), 0, 3.95, nz - 0.57, Color3.fromRGB(235, 232, 225), Enum.Material.SmoothPlastic)
	P("MerchantBowtie", Vector3.new(0.7, 0.3, 0.1), 0, 4.7, nz - 0.62, purple, Enum.Material.SmoothPlastic)
	local head = P("MerchantHead", Vector3.new(1.3, 1.3, 1.3), 0, 5.55, nz, skin, Enum.Material.SmoothPlastic)
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	P("MerchantMustache", Vector3.new(0.8, 0.14, 0.08), 0, 5.3, nz - 0.68, Color3.fromRGB(60, 40, 28), Enum.Material.SmoothPlastic)
	cyl("MerchantHatBrim", 0.12, 2.0, 0, 6.26, nz, Color3.fromRGB(24, 22, 28), Enum.Material.Fabric)
	cyl("MerchantHatCrown", 1.3, 1.3, 0, 6.95, nz, Color3.fromRGB(24, 22, 28), Enum.Material.Fabric)
	cyl("MerchantHatBand", 0.24, 1.34, 0, 6.45, nz, purple, Enum.Material.Fabric)
	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "MerchantName"
	nameGui.Size = UDim2.fromOffset(200, 40)
	nameGui.StudsOffset = Vector3.new(0, 2.4, 0)
	nameGui.MaxDistance = 60
	nameGui.Parent = head
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.fromScale(1, 1)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = "🌙 Night Merchant"
	nameLbl.TextColor3 = Color3.fromRGB(255, 225, 165)
	nameLbl.TextScaled = true
	nameLbl.Font = Enum.Font.FredokaOne
	nameLbl.Parent = nameGui
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 2
	nameStroke.Parent = nameLbl

	-- Sign board
	local sign = P("NightMerchantSign", Vector3.new(9, 1.6, 0.3), 0, 7.95, -6.45, darkWood, Enum.Material.WoodPlanks)
	boardText(sign, "🌙 NIGHT MERCHANT", gold)

	-- Hanging lanterns
	for _, x in ipairs({ -7.6, 7.6 }) do
		P("LanternChain", Vector3.new(0.1, 0.9, 0.1), x, 7.9, -6.4, ironCol, Enum.Material.Metal)
		P("LanternCap", Vector3.new(0.9, 0.18, 0.9), x, 7.4, -6.4, ironCol, Enum.Material.Metal)
		local lamp = P("WarmLantern", Vector3.new(0.7, 0.9, 0.7), x, 6.85, -6.4, gold, Enum.Material.Neon)
		P("LanternBase", Vector3.new(0.9, 0.16, 0.9), x, 6.33, -6.4, ironCol, Enum.Material.Metal)
		light(lamp, Color3.fromRGB(255, 166, 75), 2.2, 18)
	end

	-- Ore buyback table (left)
	P("OreBuybackTable", Vector3.new(6.5, 2, 3), -13.5, 1, -4, darkWood, Enum.Material.WoodPlanks, nil, true)
	P("OreTableTop", Vector3.new(6.9, 0.3, 3.3), -13.5, 2.15, -4, trim, Enum.Material.WoodPlanks, nil, true)
	P("OreSignPost", Vector3.new(0.35, 5, 0.35), -13.5, 2.5, -2.6, darkWood, Enum.Material.Wood)
	local oreSign = P("OreBuybackSign", Vector3.new(5.4, 1.1, 0.25), -13.5, 4.6, -2.85, darkWood, Enum.Material.WoodPlanks)
	boardText(oreSign, "ORE BUYBACK • 70%", Color3.fromRGB(255, 205, 120))
	for i = 0, 2 do
		local sx = -15.3 + i * 1.6
		P("OreSack", Vector3.new(1.4, 1.4, 1.4), sx, 3.0, -4.6, Color3.fromRGB(150, 112, 72), Enum.Material.Fabric, Enum.PartType.Ball)
		cyl("OreSackTie", 0.16, 0.7, sx, 3.65, -4.6, Color3.fromRGB(110, 80, 50), Enum.Material.Fabric)
		local ore = P("OreChunk", Vector3.new(0.6, 0.6, 0.6), sx, 3.85, -4.6, crystalBlue, Enum.Material.Neon, Enum.PartType.Ball)
		light(ore, crystalBlue, 0.4, 4)
	end
	P("ScaleBase", Vector3.new(1.0, 0.2, 1.0), -11.6, 2.4, -3.3, gold, Enum.Material.Metal)
	P("ScalePole", Vector3.new(0.16, 1.8, 0.16), -11.6, 3.3, -3.3, gold, Enum.Material.Metal)
	P("ScaleBeam", Vector3.new(2.4, 0.14, 0.14), -11.6, 4.15, -3.3, gold, Enum.Material.Metal)
	for _, dx in ipairs({ -1.05, 1.05 }) do
		P("ScaleChain", Vector3.new(0.06, 0.7, 0.06), -11.6 + dx, 3.8, -3.3, gold, Enum.Material.Metal)
		cyl("ScalePan", 0.08, 0.8, -11.6 + dx, 3.45, -3.3, gold, Enum.Material.Metal)
	end

	-- Barrels and crates (right)
	for i = 0, 2 do
		P("Barrel", Vector3.new(2, 1.5, 1.5), 11 + (i % 2) * 1.7, 1, -4.5 + i * 1.6, wood, Enum.Material.Wood, Enum.PartType.Cylinder, true, nil, CFrame.Angles(0, 0, math.rad(90)))
	end
	for i = 0, 2 do
		P("SupplyCrate", Vector3.new(1.5, 1.2, 1.5), 13.4, 0.9 + i * 1.2, -1.5, trim, Enum.Material.WoodPlanks, nil, true, nil, CFrame.Angles(0, math.rad(i * 12), 0))
	end
	for i = 1, 8 do
		local x = -14 + (i * 3.3 % 27)
		local z = -8.2 + (i % 3) * 0.5
		P("ScatteredOre", Vector3.new(0.5, 0.45, 0.6), x, 0.5, z, (i % 2 == 0) and crystalBlue or Color3.fromRGB(115, 90, 180), Enum.Material.Neon, nil, false, nil, CFrame.Angles(0.2, i, 0.4))
	end

	-- Fireflies
	local fly = P("FireflyVolume", Vector3.new(26, 5, 12), -1.5, 3.5, -4, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, nil, false, 1)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Fireflies"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.18), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(3, 5)
	pe.Rate = 5
	pe.Speed = NumberRange.new(0.3, 0.8)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = fly

	m.PrimaryPart = m:FindFirstChild("MerchantFloor") :: BasePart
	NightMerchantModel = m
	NightMerchantParent = parent
	m.Parent = nil -- day by default; appears via SetNightMerchantActive(true)
	return m
end

function WorldBuilder.SetNightMerchantActive(isNight: boolean)
	local m = NightMerchantModel
	if not m then return end
	if isNight then
		m.Parent = NightMerchantParent
	else
		m.Parent = nil
	end
end

function WorldBuilder.SetNightLightsActive(isNight: boolean)
	WorldBuilder.SetNightMerchantActive(isNight)
	local targetBrightness = isNight and 1.85 or 0.25
	for _, pl in ipairs(NightLights) do
		if pl and pl.Parent then
			TweenService:Create(pl, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Brightness = targetBrightness,
			}):Play()
		end
	end
end

-- ============================================================================
-- 1. УПРАВЛЕНИЕ НОЧНЫМ БАРЬЕРОМ ШАХТЫ (ПУНКТ №10: НОЧЬЮ ВХОД ЗАКРЫТ!)
-- ============================================================================
function WorldBuilder.SetNightMineBarrierActive(isNight: boolean)
	if not NightBarrierPart or not NightBarrierPart.Parent then return end
	NightBarrierPart.CanCollide = isNight
	NightBarrierPart.Transparency = isNight and 0.45 or 1.0
	local gui = NightBarrierPart:FindFirstChild("NightClosedGui") :: SurfaceGui?
	if gui then
		gui.Enabled = isNight
	end
	local bbg = NightBarrierPart:FindFirstChild("NightClosedBillboard") :: BillboardGui?
	if bbg then
		bbg.Enabled = isNight
	end

	-- Вывеска над входом: днём золотая «ШАХТА», ночью красная «ЗАКРЫТО»
	if MineSignLabel then
		MineSignLabel.Text = isNight and "ЗАКРЫТО" or GameConfig.MINE_SIGN_TEXT
		MineSignLabel.TextColor3 = isNight and Color3.fromRGB(255, 96, 82) or Color3.fromRGB(255, 214, 80)
	end
	for _, neon in ipairs(MineSignNeon) do
		if neon.Parent then
			neon.Color = isNight and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(255, 190, 50)
		end
	end
end

-- ============================================================================
-- 2. СОВРЕМЕННЫЙ БОЛЬШОЙ ПУНКТ ПРИЁМА РУДЫ «$ SELL» (ПУНКТ №13 ТЗ + РЕФЕРЕНС!)
-- Включает: неоновую вывеску "$ SELL", NPC Скупщика Грома, прилавок, весы для руды,
-- табло с курсами цен (включая ×3 за утренние залежи), мешки с рудой, вагонетку,
-- фонари и удобную светящуюся зону продажи!
-- ============================================================================
local function buildRustyMinecart(parent: Instance, cframe: CFrame, fillWithOreColor: Color3?)
	local cart = Instance.new("Model")
	cart.Name = "RustyMinecart"
	cart.Parent = parent

	makePart("RailL", Vector3.new(0.25, 0.2, 6.5), cframe * CFrame.new(-1.1, -1.15, 0), Color3.fromRGB(95, 72, 58), Enum.Material.CorrodedMetal, cart)
	makePart("RailR", Vector3.new(0.25, 0.2, 6.5), cframe * CFrame.new(1.1, -1.15, 0), Color3.fromRGB(95, 72, 58), Enum.Material.CorrodedMetal, cart)
	for tie = -2, 2 do
		makePart("Tie_" .. tie, Vector3.new(3.0, 0.18, 0.45), cframe * CFrame.new(0, -1.28, tie * 1.3), Color3.fromRGB(88, 58, 36), Enum.Material.WoodPlanks, cart)
	end

	makePart("CartBody", Vector3.new(2.5, 1.7, 3.6), cframe, Color3.fromRGB(112, 68, 48), Enum.Material.CorrodedMetal, cart)
	makePart("CartRim", Vector3.new(2.7, 0.22, 3.8), cframe * CFrame.new(0, 0.85, 0), Color3.fromRGB(78, 52, 38), Enum.Material.Metal, cart)

	for _, wx in ipairs({ -1.25, 1.25 }) do
		for _, wz in ipairs({ -1.1, 1.1 }) do
			makePart(
				"Wheel",
				Vector3.new(0.25, 0.9, 0.9),
				cframe * CFrame.new(wx, -0.75, wz) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(58, 46, 40),
				Enum.Material.CorrodedMetal,
				cart,
				Enum.PartType.Cylinder
			)
		end
	end

	makePart("CartRockFill", Vector3.new(2.2, 0.65, 3.2), cframe * CFrame.new(0, 0.72, 0), Color3.fromRGB(92, 96, 104), Enum.Material.Slate, cart)
	if fillWithOreColor then
		for k = 1, 4 do
			makePart(
				"OreChunk_" .. k,
				Vector3.new(0.65, 0.55, 0.65),
				cframe * CFrame.new((k - 2.5) * 0.42, 1.12, ((k % 2) - 0.5) * 0.8) * CFrame.Angles(k * 0.4, k * 0.7, 0),
				fillWithOreColor,
				Enum.Material.Glass,
				cart
			)
		end
	end
end

-- ============================================================================
-- v28: shared NEON KIOSK booth for the SHOP / SELL kiosks (reference prompt):
-- dark grey stone-and-metal booth, emissive neon trim on roof and base,
-- glowing signboard on top of the roof, soft rim light from the ceiling.
-- ============================================================================
local KIOSK_STONE = Color3.fromRGB(96, 100, 112)
local KIOSK_STONE_DARK = Color3.fromRGB(66, 70, 82)
local KIOSK_METAL = Color3.fromRGB(50, 54, 66)
local KIOSK_SIGN_BG = Color3.fromRGB(12, 18, 32)

local function kioskRound(inst: Instance, px: number?, scale: number?)
	local c = Instance.new("UICorner")
	if scale then
		c.CornerRadius = UDim.new(scale, 0)
	else
		c.CornerRadius = UDim.new(0, px or 8)
	end
	c.Parent = inst
end

local function kioskSurfaceGui(part: BasePart, pps: number): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = "KioskGui"
	g.Face = Enum.NormalId.Back
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pps
	g.LightInfluence = 0
	g.Brightness = 1.5
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = part
	return g
end

local function kioskSignBackground(sg: SurfaceGui, accent: Color3): Frame
	local bg = Instance.new("Frame")
	bg.Name = "SignBg"
	bg.Position = UDim2.fromOffset(8, 8)
	bg.Size = UDim2.new(1, -16, 1, -16)
	bg.BackgroundColor3 = KIOSK_SIGN_BG
	bg.BorderSizePixel = 0
	bg.ZIndex = 1
	bg.Parent = sg
	kioskRound(bg, 18)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(accent:Lerp(KIOSK_SIGN_BG, 0.45), KIOSK_SIGN_BG)
	grad.Rotation = 90
	grad.Parent = bg
	local edge = Instance.new("UIStroke")
	edge.Color = accent
	edge.Thickness = 6
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = bg
	return bg
end

local function kioskSignText(sg: SurfaceGui, text: string, accent: Color3, x: number, w: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = "SignText"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, 24)
	t.Size = UDim2.fromOffset(w, 182)
	t.Font = Enum.Font.GothamBlack
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.ZIndex = 4
	t.Parent = sg
	local s = Instance.new("UIStroke")
	s.Color = accent:Lerp(Color3.new(0, 0, 0), 0.25)
	s.Thickness = 6
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = t
	return t
end

-- white shopping-cart icon built from rounded UI bars (cx, cy = centre in px, s = size in px)
local function drawCartIcon(parent: Instance, cx: number, cy: number, s: number, col: Color3)
	local function bar(w: number, h: number, x: number, y: number, rot: number)
		local f = Instance.new("Frame")
		f.Name = "CartBar"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(w, h)
		f.Position = UDim2.fromOffset(cx + x * s, cy + y * s)
		f.Rotation = rot
		f.BackgroundColor3 = col
		f.BorderSizePixel = 0
		f.ZIndex = 3
		f.Parent = parent
		kioskRound(f, math.floor(math.min(w, h) / 2))
	end
	local t = math.max(6, math.floor(s * 0.085))
	bar(s * 0.28, t, -0.41, -0.37, 18) -- handle
	bar(s * 0.72, t, 0.02, -0.26, 0) -- basket top
	bar(s * 0.54, t, 0.04, 0.12, 0) -- basket bottom
	bar(t, s * 0.42, -0.29, -0.07, -14) -- left side
	bar(t, s * 0.42, 0.35, -0.07, 14) -- right side
	bar(t * 0.7, s * 0.36, -0.07, -0.07, -6) -- grid bar
	bar(t * 0.7, s * 0.36, 0.15, -0.07, 6) -- grid bar
	bar(s * 0.62, t, 0.06, 0.25, 0) -- under-frame
	for _, wx in ipairs({ -0.15, 0.27 }) do
		local w = Instance.new("Frame")
		w.Name = "CartWheel"
		w.AnchorPoint = Vector2.new(0.5, 0.5)
		w.Size = UDim2.fromOffset(s * 0.17, s * 0.17)
		w.Position = UDim2.fromOffset(cx + wx * s, cy + 0.39 * s)
		w.BackgroundColor3 = col
		w.BorderSizePixel = 0
		w.ZIndex = 3
		w.Parent = parent
		kioskRound(w, nil, 0.5)
	end
end

-- round green "$" badge for the SELL signboard
local function drawDollarBadge(parent: Instance, cx: number, cy: number, s: number, col: Color3)
	local b = Instance.new("Frame")
	b.Name = "DollarBadge"
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromOffset(cx, cy)
	b.Size = UDim2.fromOffset(s, s)
	b.BackgroundColor3 = col
	b.BorderSizePixel = 0
	b.ZIndex = 3
	b.Parent = parent
	kioskRound(b, nil, 0.5)
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(1, 1, 1)
	st.Thickness = 6
	st.Parent = b
	local d = Instance.new("TextLabel")
	d.BackgroundTransparency = 1
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale(0.5, 0.52)
	d.Size = UDim2.fromScale(0.78, 0.78)
	d.Font = Enum.Font.GothamBlack
	d.Text = "$"
	d.TextScaled = true
	d.TextColor3 = Color3.new(1, 1, 1)
	d.ZIndex = 4
	d.Parent = b
end

-- v30: chamfered (octagonal) slab: centre rect + side rect + 4 diamond corners. Returns all parts.
local function kioskOctSlab(model: Instance, name: string, center: Vector3, w: number, d: number, c: number, h: number, color: Color3, mat: Enum.Material, canCollide: boolean?): { BasePart }
	local cc = true
	if canCollide ~= nil then
		cc = canCollide
	end
	local parts: { BasePart } = {}
	table.insert(parts, makePart(name, Vector3.new(w - 2 * c, h, d), center, color, mat, model, nil, cc))
	table.insert(parts, makePart(name, Vector3.new(w, h, d - 2 * c), center, color, mat, model, nil, cc))
	local s = c * math.sqrt(2)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local cf = CFrame.new(center + Vector3.new(sx * (w / 2 - c), 0, sz * (d / 2 - c))) * CFrame.Angles(0, math.rad(45), 0)
			table.insert(parts, makePart(name, Vector3.new(s, h, s), cf, color, mat, model, nil, cc))
		end
	end
	return parts
end

-- v30: neon outline that follows the chamfered slab edge
local function kioskOctNeon(model: Instance, name: string, center: Vector3, w: number, d: number, c: number, t: number, color: Color3)
	for _, sz in ipairs({ -1, 1 }) do
		makePart(name, Vector3.new(w - 2 * c, t, t), center + Vector3.new(0, 0, sz * d / 2), color, Enum.Material.Neon, model, nil, false)
	end
	for _, sx in ipairs({ -1, 1 }) do
		makePart(name, Vector3.new(t, t, d - 2 * c), center + Vector3.new(sx * w / 2, 0, 0), color, Enum.Material.Neon, model, nil, false)
	end
	local L = c * math.sqrt(2) + t
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local mid = center + Vector3.new(sx * (w / 2 - c / 2), 0, sz * (d / 2 - c / 2))
			local dir = Vector3.new(sx, 0, -sz)
			makePart(name, Vector3.new(t, t, L), CFrame.lookAt(mid, mid + dir), color, Enum.Material.Neon, model, nil, false)
		end
	end
end

-- v30: OPEN booth shell (NO WALLS): square stone columns with neon-banded feet, roof slab with neon trims,
-- ceiling lights, big glowing signboard on top. Returns the signboard part.
-- opts: zBack, zFront (roof extent), floorY (top of the platform), pillarZs (list of column Z offsets),
--       pillarSize, lights (ceiling light count)
local function buildNeonKioskShell(model: Instance, centerPos: Vector3, accent: Color3, halfW: number, signW: number, prefix: string, opts: { [string]: any }?): Part
	local o = opts or {}
	local zBack: number = o.zBack or -8.5
	local zFront: number = o.zFront or 1.0
	local floorY: number = o.floorY or 0.4
	local pSize: number = o.pillarSize or 1.8
	local pillarZs: { number } = o.pillarZs or { zBack + 1.0, zFront - 1.0 }
	local lightCount: number = o.lights or 4
	local depth = zFront - zBack
	local zMid = (zBack + zFront) / 2
	local roofY = 12.55
	local roofBottom = roofY - 0.8
	local rim = accent:Lerp(Color3.new(1, 1, 1), 0.55)
	local pillarH = roofBottom - floorY

	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (halfW - pSize / 2 - 0.3)
		for _, pz in ipairs(pillarZs) do
			local p = centerPos + Vector3.new(x, 0, pz)
			makePart(prefix .. "KioskPillar", Vector3.new(pSize, pillarH, pSize), p + Vector3.new(0, floorY + pillarH / 2, 0), KIOSK_STONE, Enum.Material.Slate, model)
			makePart(prefix .. "KioskPillarFoot", Vector3.new(pSize + 0.8, 2.4, pSize + 0.8), p + Vector3.new(0, floorY + 1.2, 0), KIOSK_STONE_DARK, Enum.Material.Slate, model)
			makePart(prefix .. "KioskPillarFootCap", Vector3.new(pSize + 1.0, 0.35, pSize + 1.0), p + Vector3.new(0, floorY + 2.55, 0), KIOSK_METAL, Enum.Material.Metal, model)
			makePart(prefix .. "KioskPillarNeonBand", Vector3.new(pSize + 0.92, 0.22, pSize + 0.92), p + Vector3.new(0, floorY + 1.8, 0), accent, Enum.Material.Neon, model, nil, false)
			makePart(prefix .. "KioskPillarCapital", Vector3.new(pSize + 0.6, 0.7, pSize + 0.6), p + Vector3.new(0, roofBottom - 0.35, 0), KIOSK_STONE_DARK, Enum.Material.Slate, model)
		end
	end

	makePart(prefix .. "KioskRoof", Vector3.new(halfW * 2 + 0.8, 1.6, depth + 0.8), centerPos + Vector3.new(0, roofY, zMid), KIOSK_STONE_DARK, Enum.Material.Slate, model)
	makePart(prefix .. "KioskRoofCap", Vector3.new(halfW * 2 + 1.0, 0.35, depth + 1.0), centerPos + Vector3.new(0, roofY + 0.95, zMid), KIOSK_METAL, Enum.Material.Metal, model)
	for _, ny in ipairs({ roofY - 0.68, roofY + 0.62 }) do
		makePart(prefix .. "KioskRoofNeonFront", Vector3.new(halfW * 2 + 1.0, 0.24, 0.24), centerPos + Vector3.new(0, ny, zMid + depth / 2 + 0.5), accent, Enum.Material.Neon, model, nil, false)
		for _, sx in ipairs({ -1, 1 }) do
			makePart(prefix .. "KioskRoofNeonSide", Vector3.new(0.24, 0.24, depth + 1.0), centerPos + Vector3.new(sx * (halfW + 0.5), ny, zMid), accent, Enum.Material.Neon, model, nil, false)
		end
	end

	if lightCount > 0 then
		local span = halfW * 2 - 5.2
		for i = 1, lightCount do
			local lx = -halfW + 2.6 + (i - 0.5) * (span / lightCount)
			local lamp = makePart(prefix .. "KioskCeilingLight", Vector3.new(2.0, 0.12, 1.0), centerPos + Vector3.new(lx, roofBottom - 0.06, zMid), rim, Enum.Material.Neon, model, nil, false)
			local sl = Instance.new("SpotLight")
			sl.Face = Enum.NormalId.Bottom
			sl.Angle = 80
			sl.Range = 18
			sl.Brightness = 2.4
			sl.Color = rim
			sl.Shadows = false
			sl.Parent = lamp
		end
	end

	local signY = roofY + 3.6
	local signZ = zFront - 0.6
	local sign = makePart(prefix .. "KioskSignboard", Vector3.new(signW, 4.6, 0.8), centerPos + Vector3.new(0, signY, signZ), KIOSK_SIGN_BG, Enum.Material.SmoothPlastic, model)
	makePart(prefix .. "KioskSignBack", Vector3.new(signW + 0.8, 5.4, 0.5), centerPos + Vector3.new(0, signY, signZ - 0.55), KIOSK_METAL, Enum.Material.Metal, model)
	for _, sy in ipairs({ -1, 1 }) do
		makePart(prefix .. "KioskSignNeonH", Vector3.new(signW - 1.2, 0.28, 0.3), centerPos + Vector3.new(0, signY + sy * 2.44, signZ + 0.3), accent, Enum.Material.Neon, model, nil, false)
		makePart(prefix .. "KioskSignNeonV", Vector3.new(0.28, 3.4, 0.3), centerPos + Vector3.new(sy * (signW / 2 + 0.14), signY, signZ + 0.3), accent, Enum.Material.Neon, model, nil, false)
		-- chamfered neon corners like the reference sign
		for _, cx in ipairs({ -1, 1 }) do
			local cp = centerPos + Vector3.new(cx * (signW / 2 - 0.23), signY + sy * 2.07, signZ + 0.3)
			makePart(prefix .. "KioskSignNeonCorner", Vector3.new(1.3, 0.28, 0.3), CFrame.new(cp) * CFrame.Angles(0, 0, math.rad(-cx * sy * 45)), accent, Enum.Material.Neon, model, nil, false)
		end
	end
	-- short struts holding the sign above the roof
	for _, sx in ipairs({ -1, 1 }) do
		makePart(prefix .. "KioskSignStrut", Vector3.new(0.6, 1.6, 0.6), centerPos + Vector3.new(sx * signW * 0.32, roofY + 1.2, signZ - 0.55), KIOSK_METAL, Enum.Material.Metal, model)
	end
	local glow = Instance.new("SurfaceLight")
	glow.Face = Enum.NormalId.Back
	glow.Angle = 110
	glow.Range = 16
	glow.Brightness = 2.2
	glow.Color = accent
	glow.Parent = sign
	return sign
end

function WorldBuilder.BuildModernSellMarket(parent: Instance, centerPos: Vector3): Part
	local market = Instance.new("Model")
	market.Name = "ModernOreSellMarket"
	market.Parent = parent

	-- =========================================================================
	-- v30: SELL STATION rebuilt 1:1 from the reference (right kiosk), NO WALLS:
	-- chamfered stone platform with neon-green edge, two stone columns with a
	-- roof and the big "$ SELL" sign, free-hanging glowing recycle symbol with
	-- double up-chevrons, short neon-banded posts, "Sell Your Items! [E] Sell"
	-- plaque on a stand and the glowing green circle.
	-- =========================================================================
	local neonGreen = Color3.fromRGB(60, 255, 120)
	local darkSteel = Color3.fromRGB(36, 42, 54)
	local stone = Color3.fromRGB(92, 98, 108)
	local stoneDark = Color3.fromRGB(64, 70, 80)
	local floorY = 1.05

	-- 1) chamfered two-tier platform + neon edge
	kioskOctSlab(market, "MarketPlatform", centerPos + Vector3.new(0, 0.3, 0), 24, 20, 2.2, 0.8, stoneDark, Enum.Material.Slate)
	kioskOctNeon(market, "NeonBorder", centerPos + Vector3.new(0, 0.45, 0), 24.1, 20.1, 2.2, 0.25, neonGreen)
	kioskOctSlab(market, "MarketPlatformTop", centerPos + Vector3.new(0, 0.85, 0), 23, 19, 2.0, 0.3, stone, Enum.Material.Slate)
	for _, gp in ipairs(kioskOctSlab(market, "SellGlossFloor", centerPos + Vector3.new(0, 1.02, 0), 22.4, 18.4, 1.9, 0.05, Color3.fromRGB(78, 86, 98), Enum.Material.SmoothPlastic, false)) do
		gp.Reflectance = 0.18
	end

	-- 2) open shell: one thick column per side at the back, shallow roof, "$ SELL" sign
	local sellSign = buildNeonKioskShell(market, centerPos, neonGreen, 11.0, 15.0, "Sell", {
		zBack = -9.0,
		zFront = -4.6,
		floorY = floorY,
		pillarZs = { -6.8 },
		pillarSize = 2.4,
		lights = 0,
	})
	do
		local sg = kioskSurfaceGui(sellSign, 50)
		kioskSignBackground(sg, neonGreen)
		drawDollarBadge(sg, 140, 115, 160, Color3.fromRGB(34, 196, 86))
		kioskSignText(sg, "SELL", neonGreen, 250, 476)
	end
	local roofBottom = 12.55 - 0.8

	-- 3) free-hanging glowing recycle symbol (two arcs with arrow heads)
	local ringC = centerPos + Vector3.new(0, floorY + 7.0, -6.8)
	local ringR = 2.6
	local SEG = 32
	for i = 0, SEG - 1 do
		local aDeg = (i + 0.5) / SEG * 360
		local d90 = math.abs(((aDeg - 90 + 180) % 360) - 180)
		local d270 = math.abs(((aDeg - 270 + 180) % 360) - 180)
		if d90 >= 16 and d270 >= 16 then
			local a = math.rad(aDeg)
			local p = ringC + Vector3.new(math.cos(a) * ringR, math.sin(a) * ringR, 0)
			makePart("RecycleRing", Vector3.new(2 * math.pi * ringR / SEG * 1.12, 0.7, 0.3), CFrame.new(p) * CFrame.Angles(0, 0, a + math.pi / 2), neonGreen, Enum.Material.Neon, market, nil, false)
		end
	end
	for _, aDeg in ipairs({ 104, 284 }) do
		local a = math.rad(aDeg)
		local p = ringC + Vector3.new(math.cos(a) * ringR, math.sin(a) * ringR, 0)
		local tng = Vector3.new(math.sin(a), -math.cos(a), 0)
		local tip = p + tng * 0.9
		local back = math.atan2(-tng.Y, -tng.X)
		for _, sgn in ipairs({ -1, 1 }) do
			local ang = back + sgn * math.rad(40)
			local dir = Vector3.new(math.cos(ang), math.sin(ang), 0)
			makePart("RecycleArrow", Vector3.new(1.5, 0.7, 0.32), CFrame.new(tip + dir * 0.65) * CFrame.Angles(0, 0, ang), neonGreen, Enum.Material.Neon, market, nil, false)
		end
	end
	-- thin hanger rods from the roof
	for _, sx in ipairs({ -1, 1 }) do
		local a = math.rad(sx == 1 and 60 or 120)
		local topY = ringC.Y + math.sin(a) * ringR
		local len = roofBottom - topY
		makePart("RecycleHanger", Vector3.new(0.14, len, 0.14), Vector3.new(ringC.X + math.cos(a) * ringR, topY + len / 2, ringC.Z), darkSteel, Enum.Material.Metal, market, nil, false)
	end
	local recycleGlow = makePart("RecycleGlow", Vector3.new(0.2, 0.2, 0.2), ringC + Vector3.new(0, 0, 1.0), neonGreen, Enum.Material.Neon, market, nil, false, 1)
	local rgl = Instance.new("PointLight")
	rgl.Color = neonGreen
	rgl.Range = 14
	rgl.Brightness = 1.8
	rgl.Parent = recycleGlow

	-- double up-chevrons on both sides of the symbol (also hanging)
	for _, sx in ipairs({ -1, 1 }) do
		local cx = sx * 5.8
		for _, ay in ipairs({ floorY + 6.2, floorY + 7.9 }) do
			local apex = centerPos + Vector3.new(cx, ay + 0.6, -6.8)
			makePart("UpArrow", Vector3.new(1.75, 0.48, 0.3), CFrame.new(apex + Vector3.new(-0.6, -0.6, 0)) * CFrame.Angles(0, 0, math.rad(45)), neonGreen, Enum.Material.Neon, market, nil, false)
			makePart("UpArrow", Vector3.new(1.75, 0.48, 0.3), CFrame.new(apex + Vector3.new(0.6, -0.6, 0)) * CFrame.Angles(0, 0, math.rad(-45)), neonGreen, Enum.Material.Neon, market, nil, false)
		end
		local rodBottom = floorY + 7.9 + 0.6
		makePart("UpArrowHanger", Vector3.new(0.12, roofBottom - rodBottom, 0.12), centerPos + Vector3.new(cx, (roofBottom + rodBottom) / 2, -6.8), darkSteel, Enum.Material.Metal, market, nil, false)
	end

	-- 4) short stone posts with neon bands at the front corners
	for _, sx in ipairs({ -1, 1 }) do
		for _, pz in ipairs({ -0.6, 6.4 }) do
			local p = centerPos + Vector3.new(sx * 9.9, 0, pz)
			makePart("SellPost", Vector3.new(1.6, 3.4, 1.6), p + Vector3.new(0, floorY + 1.7, 0), KIOSK_STONE_DARK, Enum.Material.Slate, market)
			makePart("SellPostCap", Vector3.new(1.9, 0.35, 1.9), p + Vector3.new(0, floorY + 3.55, 0), KIOSK_METAL, Enum.Material.Metal, market)
			makePart("SellPostNeon", Vector3.new(1.72, 0.22, 1.72), p + Vector3.new(0, floorY + 2.5, 0), neonGreen, Enum.Material.Neon, market, nil, false)
		end
		makePart("SellPostRail", Vector3.new(0.5, 0.6, 5.4), centerPos + Vector3.new(sx * 9.9, floorY + 0.3, 2.9), KIOSK_STONE_DARK, Enum.Material.Slate, market)
		makePart("SellPostRailNeon", Vector3.new(0.56, 0.12, 5.4), centerPos + Vector3.new(sx * 9.9, floorY + 0.55, 2.9), neonGreen, Enum.Material.Neon, market, nil, false)
	end

	-- 5) black plaque "Sell Your Items!" + green "E  Sell" button on a low stand (working E prompt)
	local plaqueZ = -2.5
	local plaque = makePart("SellPlaque", Vector3.new(7.4, 2.6, 0.3), centerPos + Vector3.new(0, floorY + 2.6, plaqueZ), Color3.fromRGB(10, 12, 16), Enum.Material.SmoothPlastic, market)
	for _, sx in ipairs({ -1, 1 }) do
		makePart("SellPlaqueLeg", Vector3.new(0.35, 1.4, 0.35), centerPos + Vector3.new(sx * 2.8, floorY + 0.7, plaqueZ - 0.05), darkSteel, Enum.Material.Metal, market)
	end
	makePart("SellPlaqueBase", Vector3.new(6.6, 0.25, 1.2), centerPos + Vector3.new(0, floorY + 0.12, plaqueZ), darkSteel, Enum.Material.Metal, market)
	makePart("SellPlaqueNeon", Vector3.new(7.6, 0.14, 0.16), centerPos + Vector3.new(0, floorY + 1.26, plaqueZ + 0.1), neonGreen, Enum.Material.Neon, market, nil, false)
	do
		local pg = kioskSurfaceGui(plaque, 60)
		local bg = Instance.new("Frame")
		bg.Position = UDim2.fromOffset(4, 4)
		bg.Size = UDim2.new(1, -8, 1, -8)
		bg.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
		bg.BorderSizePixel = 0
		bg.ZIndex = 1
		bg.Parent = pg
		kioskRound(bg, 22)
		local bst = Instance.new("UIStroke")
		bst.Color = neonGreen
		bst.Thickness = 3
		bst.Parent = bg
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(20, 12)
		title.Size = UDim2.fromOffset(404, 56)
		title.Font = Enum.Font.GothamBlack
		title.Text = "Sell Your Items!"
		title.TextScaled = true
		title.TextColor3 = Color3.new(1, 1, 1)
		title.ZIndex = 3
		title.Parent = pg
		local btn = Instance.new("Frame")
		btn.AnchorPoint = Vector2.new(0.5, 0)
		btn.Position = UDim2.fromOffset(222, 80)
		btn.Size = UDim2.fromOffset(250, 62)
		btn.BackgroundColor3 = Color3.fromRGB(16, 22, 18)
		btn.BorderSizePixel = 0
		btn.ZIndex = 3
		btn.Parent = pg
		kioskRound(btn, 16)
		local btnSt = Instance.new("UIStroke")
		btnSt.Color = Color3.fromRGB(70, 80, 74)
		btnSt.Thickness = 2
		btnSt.Parent = btn
		local key = Instance.new("Frame")
		key.Position = UDim2.fromOffset(12, 7)
		key.Size = UDim2.fromOffset(48, 48)
		key.BackgroundColor3 = Color3.fromRGB(46, 214, 92)
		key.BorderSizePixel = 0
		key.ZIndex = 4
		key.Parent = btn
		kioskRound(key, 10)
		local kgr = Instance.new("UIGradient")
		kgr.Color = ColorSequence.new(Color3.fromRGB(150, 255, 170), Color3.fromRGB(40, 190, 80))
		kgr.Rotation = 90
		kgr.Parent = key
		local kl = Instance.new("TextLabel")
		kl.BackgroundTransparency = 1
		kl.Size = UDim2.fromScale(1, 1)
		kl.Font = Enum.Font.GothamBlack
		kl.Text = "E"
		kl.TextScaled = true
		kl.TextColor3 = Color3.new(1, 1, 1)
		kl.ZIndex = 5
		kl.Parent = key
		local bl = Instance.new("TextLabel")
		bl.BackgroundTransparency = 1
		bl.Position = UDim2.fromOffset(76, 6)
		bl.Size = UDim2.fromOffset(156, 50)
		bl.Font = Enum.Font.GothamBlack
		bl.Text = "Sell"
		bl.TextScaled = true
		bl.TextColor3 = Color3.new(1, 1, 1)
		bl.ZIndex = 5
		bl.Parent = btn
	end
	local sellPrompt = Instance.new("ProximityPrompt")
	sellPrompt.Name = "SellPlaquePrompt"
	sellPrompt.ActionText = "Sell"
	sellPrompt.ObjectText = "Sell Your Items!"
	sellPrompt.KeyboardKeyCode = Enum.KeyCode.E
	sellPrompt.HoldDuration = 0
	sellPrompt.MaxActivationDistance = 14
	sellPrompt.RequiresLineOfSight = false
	sellPrompt.Parent = plaque

	-- v32: Wash Station removed — dirt is cleaned only at night (Night Merchant Repair Kit)

	-- 6) glowing green sell circle in front of the plaque
	local sellPadPos = centerPos + Vector3.new(0, floorY + 0.05, 3.8)
	local pad = makePart(
		"WhiteSellPad",
		Vector3.new(0.3, 10.6, 10.6),
		CFrame.new(sellPadPos) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 255, 160),
		Enum.Material.Neon,
		market,
		Enum.PartType.Cylinder,
		true,
		0.35
	)
	makePart("SellPadNeonRing", Vector3.new(0.26, 11.8, 11.8), CFrame.new(sellPadPos - Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), neonGreen, Enum.Material.Neon, market, Enum.PartType.Cylinder, false)
	makePart("SellPadOuterRing", Vector3.new(0.24, 12.8, 12.8), CFrame.new(sellPadPos - Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), darkSteel, Enum.Material.Metal, market, Enum.PartType.Cylinder, false)

	local pl = Instance.new("PointLight", pad)
	pl.Color = neonGreen
	pl.Range = 14
	pl.Brightness = 1.8

	local att = Instance.new("Attachment", pad)
	local pe = Instance.new("ParticleEmitter", att)
	pe.Color = ColorSequence.new(neonGreen, Color3.fromRGB(200, 255, 210))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(1.0, 1.8)
	pe.Rate = 14
	pe.Speed = NumberRange.new(3.0, 5.0)
	pe.EmissionDirection = Enum.NormalId.Right
	pe.SpreadAngle = Vector2.new(15, 15)

	local bg = Instance.new("BillboardGui", pad)
	bg.Name = "ZoneBillboard"
	bg.Size = UDim2.new(0, 240, 0, 60)
	bg.StudsOffset = Vector3.new(0, 4.8, 0)
	bg.MaxDistance = 110
	local card = Instance.new("Frame", bg)
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(18, 28, 22)
	card.BackgroundTransparency = 0.15
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke", card)
	st.Color = neonGreen
	st.Thickness = 2
	local t1 = Instance.new("TextLabel", card)
	t1.Size = UDim2.new(1, -12, 0.54, 0)
	t1.Position = UDim2.new(0, 6, 0, 3)
	t1.BackgroundTransparency = 1
	t1.Font = Enum.Font.GothamBold
	t1.TextColor3 = neonGreen
	t1.TextScaled = true
	t1.Text = "💰 SELL ORE"
	local t2 = Instance.new("TextLabel", card)
	t2.Size = UDim2.new(1, -12, 0.38, 0)
	t2.Position = UDim2.new(0, 6, 0.56, 0)
	t2.BackgroundTransparency = 1
	t2.Font = Enum.Font.SourceSansBold
	t2.TextColor3 = Color3.fromRGB(235, 245, 240)
	t2.TextScaled = true
	t2.Text = "Step into the zone — ore sells automatically"

	WorldBuilder.ExtendSellMarket(market, centerPos)

	return pad
end

-- ============================================================================
-- 3. НЕОНОВЫЙ ПАВИЛЬОН МАГАЗИНА «🛒 SHOP» С 3D-ВИТРИНОЙ РЮКЗАКОВ И КИРОК
-- (По референсу «Неоновая площадь магазина и продажи.png»)
-- ============================================================================
function WorldBuilder.BuildNeonShopPavilion(
	worldFolder: Folder,
	centerPos: Vector3,
	equipmentManager: any
): Part
	local shopModel = Instance.new("Model")
	shopModel.Name = "NeonShopPavilion"
	shopModel.Parent = worldFolder

	-- =========================================================================
	-- v30: SHOP rebuilt 1:1 from the reference (left kiosk), NO WALLS:
	-- chamfered blue-stone stage with a neon-blue edge, four stone columns,
	-- roof with neon trims + 4 ceiling lights, big "🛒 SHOP" sign on top,
	-- four backpacks (orange / olive / dark navy / glowing sci-fi) on round
	-- neon pedestals with black coin price tags.
	-- =========================================================================
	local neonBlue = Color3.fromRGB(35, 160, 255)
	local neonCyan = neonBlue
	local stoneBlue = Color3.fromRGB(74, 82, 120)
	local stoneBlueDark = Color3.fromRGB(50, 56, 88)
	local floorY = 1.05

	-- 1) chamfered two-tier stage + neon edge + tile seams
	kioskOctSlab(shopModel, "ShopPlatform", centerPos + Vector3.new(0, 0.3, 0), 28, 21, 2.4, 0.8, stoneBlueDark, Enum.Material.Slate)
	kioskOctNeon(shopModel, "ShopNeonBase", centerPos + Vector3.new(0, 0.45, 0), 28.1, 21.1, 2.4, 0.25, neonBlue)
	kioskOctSlab(shopModel, "ShopPlatformTop", centerPos + Vector3.new(0, 0.85, 0), 27, 20, 2.2, 0.3, stoneBlue, Enum.Material.Slate)
	for _, gp in ipairs(kioskOctSlab(shopModel, "ShopGlossFloor", centerPos + Vector3.new(0, 1.02, 0), 26.4, 19.4, 2.1, 0.05, Color3.fromRGB(88, 98, 146), Enum.Material.SmoothPlastic, false)) do
		gp.Reflectance = 0.2
	end
	for i = -2, 2 do
		makePart("ShopFloorSeam", Vector3.new(0.08, 0.02, 15.0), centerPos + Vector3.new(i * 5.2, 1.055, 0), Color3.fromRGB(64, 72, 112), Enum.Material.SmoothPlastic, shopModel, nil, false)
	end

	-- 2) open shell (4 columns, roof, ceiling lights) + glowing "SHOP" sign with a white cart icon
	local sign = buildNeonKioskShell(shopModel, centerPos, neonBlue, 13.6, 17.5, "Shop", {
		zBack = -9.6,
		zFront = -0.8,
		floorY = floorY,
		pillarZs = { -8.4, -2.0 },
		pillarSize = 1.8,
		lights = 4,
	})
	do
		local sg = kioskSurfaceGui(sign, 50)
		kioskSignBackground(sg, neonBlue)
		drawCartIcon(sg, 150, 115, 175, Color3.new(1, 1, 1))
		kioskSignText(sg, "SHOP", neonBlue, 270, 560)
	end

	-- 3) four round neon pedestals + backpacks + coin price tags
	local pedZ = -5.2
	local SHOW_LEVELS = { 2, 3, 4, 10 } -- orange, olive-yellow, dark navy, glowing cyan sci-fi
	local function fmtCoins(n: number): string
		local s = tostring(math.floor(n + 0.5))
		local f = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
		if string.sub(f, 1, 1) == "," then
			f = string.sub(f, 2)
		end
		return f
	end
	local up = CFrame.Angles(0, 0, math.rad(90))
	for i, bagLvl in ipairs(SHOW_LEVELS) do
		local x = -7.8 + (i - 1) * 5.2
		local base = centerPos + Vector3.new(x, floorY, pedZ)
		-- wide dark base disc with a neon ring, then a narrower upper disc with a neon ring + glossy top
		makePart("BagPedestalBase_" .. bagLvl, Vector3.new(0.6, 4.4, 4.4), CFrame.new(base + Vector3.new(0, 0.3, 0)) * up, Color3.fromRGB(40, 46, 70), Enum.Material.Metal, shopModel, Enum.PartType.Cylinder)
		makePart("BagPedestalUnderglow_" .. bagLvl, Vector3.new(0.16, 4.6, 4.6), CFrame.new(base + Vector3.new(0, 0.5, 0)) * up, neonBlue, Enum.Material.Neon, shopModel, Enum.PartType.Cylinder, false)
		makePart("BagPedestal_" .. bagLvl, Vector3.new(0.9, 3.6, 3.6), CFrame.new(base + Vector3.new(0, 1.05, 0)) * up, Color3.fromRGB(48, 54, 80), Enum.Material.Metal, shopModel, Enum.PartType.Cylinder)
		local ring = makePart("BagPedestalNeon_" .. bagLvl, Vector3.new(0.16, 3.8, 3.8), CFrame.new(base + Vector3.new(0, 1.42, 0)) * up, neonBlue, Enum.Material.Neon, shopModel, Enum.PartType.Cylinder, false)
		local top = makePart("BagPedestalGloss_" .. bagLvl, Vector3.new(0.1, 3.4, 3.4), CFrame.new(base + Vector3.new(0, 1.52, 0)) * up, Color3.fromRGB(70, 84, 130), Enum.Material.Glass, shopModel, Enum.PartType.Cylinder, false)
		top.Reflectance = 0.4
		local topY = 1.57
		local pl = Instance.new("PointLight")
		pl.Color = neonBlue
		pl.Range = 9
		pl.Brightness = 1.6
		pl.Parent = ring
		local att = Instance.new("Attachment")
		att.Parent = ring
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(150, 225, 255), neonBlue)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Rate = 5
		pe.Speed = NumberRange.new(1.2, 2.2)
		pe.EmissionDirection = Enum.NormalId.Right
		pe.SpreadAngle = Vector2.new(35, 35)
		pe.Parent = att

		if equipmentManager and equipmentManager.BuildBackpackParts then
			local displayBag = Instance.new("Model")
			displayBag.Name = "ShowcaseBag_" .. bagLvl
			displayBag.Parent = shopModel
			local okB, errB = pcall(function()
				equipmentManager.BuildBackpackParts(displayBag, bagLvl, CFrame.new(base + Vector3.new(0, topY + 1.95, 0)), true, 0.95)
			end)
			if not okB then
				warn("[WorldBuilder] v30 showcase bag " .. bagLvl .. ": " .. tostring(errB))
			end
		end

		local cost = 0
		local okS, st = pcall(function()
			return GameConfig.GetBackpackStyle(bagLvl)
		end)
		if okS and st and st.Cost then
			cost = st.Cost
		end
		-- price tag stands on the front edge of the pedestal top, like the reference
		local tag = makePart("BagPriceTag_" .. bagLvl, Vector3.new(3.3, 0.66, 0.12), base + Vector3.new(0, topY + 0.33, 1.55), Color3.fromRGB(12, 16, 26), Enum.Material.SmoothPlastic, shopModel, nil, false)
		local tg = kioskSurfaceGui(tag, 60)
		local fr = Instance.new("Frame")
		fr.Position = UDim2.fromOffset(2, 2)
		fr.Size = UDim2.new(1, -4, 1, -4)
		fr.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
		fr.BorderSizePixel = 0
		fr.ZIndex = 1
		fr.Parent = tg
		kioskRound(fr, 10)
		local fst = Instance.new("UIStroke")
		fst.Color = Color3.fromRGB(40, 48, 70)
		fst.Thickness = 2
		fst.Parent = fr
		local coin = Instance.new("Frame")
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Position = UDim2.fromOffset(30, 20)
		coin.Size = UDim2.fromOffset(26, 26)
		coin.BackgroundColor3 = Color3.fromRGB(255, 198, 40)
		coin.BorderSizePixel = 0
		coin.ZIndex = 3
		coin.Parent = tg
		kioskRound(coin, nil, 0.5)
		local cst = Instance.new("UIStroke")
		cst.Color = Color3.fromRGB(190, 126, 18)
		cst.Thickness = 3
		cst.Parent = coin
		local shine = Instance.new("Frame")
		shine.AnchorPoint = Vector2.new(0.5, 0.5)
		shine.Position = UDim2.fromScale(0.5, 0.5)
		shine.Size = UDim2.fromScale(0.46, 0.46)
		shine.BackgroundColor3 = Color3.fromRGB(255, 232, 130)
		shine.BorderSizePixel = 0
		shine.ZIndex = 4
		shine.Parent = coin
		kioskRound(shine, nil, 0.5)
		local pt = Instance.new("TextLabel")
		pt.BackgroundTransparency = 1
		pt.Position = UDim2.fromOffset(52, 3)
		pt.Size = UDim2.fromOffset(138, 34)
		pt.Font = Enum.Font.GothamBlack
		pt.Text = fmtCoins(cost)
		pt.TextScaled = true
		pt.TextColor3 = Color3.new(1, 1, 1)
		pt.ZIndex = 3
		pt.Parent = tg
	end

	-- 4) shop circle on the open floor in front of the pedestals (opens the swipe shop, Lv.1–10)
	local shopPadPos = centerPos + Vector3.new(0, floorY + 0.05, 4.0)
	local pad = makePart(
		"GreenShopPad",
		Vector3.new(0.3, 10.6, 10.6),
		CFrame.new(shopPadPos) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 200, 255),
		Enum.Material.Neon,
		shopModel,
		Enum.PartType.Cylinder,
		true,
		0.45
	)
	makePart("ShopPadNeonRing", Vector3.new(0.26, 11.8, 11.8), CFrame.new(shopPadPos - Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), neonBlue, Enum.Material.Neon, shopModel, Enum.PartType.Cylinder, false)

	local bg = Instance.new("BillboardGui", pad)
	bg.Name = "ZoneBillboard"
	bg.Size = UDim2.new(0, 250, 0, 60)
	bg.StudsOffset = Vector3.new(0, 4.8, 0)
	bg.MaxDistance = 110
	local card = Instance.new("Frame", bg)
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(16, 24, 36)
	card.BackgroundTransparency = 0.15
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke", card)
	st.Color = neonCyan
	st.Thickness = 2
	local t1 = Instance.new("TextLabel", card)
	t1.Size = UDim2.new(1, -12, 0.54, 0)
	t1.Position = UDim2.new(0, 6, 0, 3)
	t1.BackgroundTransparency = 1
	t1.Font = Enum.Font.GothamBold
	t1.TextColor3 = neonCyan
	t1.TextScaled = true
	t1.Text = "🛒 SHOP (LV.1–10)"
	local t2 = Instance.new("TextLabel", card)
	t2.Size = UDim2.new(1, -12, 0.38, 0)
	t2.Position = UDim2.new(0, 6, 0.56, 0)
	t2.BackgroundTransparency = 1
	t2.Font = Enum.Font.SourceSansBold
	t2.TextColor3 = Color3.fromRGB(235, 245, 255)
	t2.TextScaled = true
	t2.Text = "Pickaxes Lv.1–10 & Backpacks Lv.1–10 (Swipe)"

	return pad
end

-- ============================================================================
-- 4. АРХИТЕКТУРА ШАХТЫ 30×30×30 БЛОКОВ С НЕПРОНИЦАЕМЫМИ СТЕНАМИ И ДЕТАЛЯМИ
-- ============================================================================
local function buildRubblePile(parent: Instance, basePos: Vector3, count: number, rockColor: Color3)
	local folder = Instance.new("Folder", parent)
	folder.Name = "RockfallRubble"
	for i = 1, count do
		local sx = 1.4 + (i % 3) * 0.85
		local sy = 1.0 + (i % 2) * 0.75
		local sz = 1.3 + ((i + 1) % 3) * 0.8
		local offset = Vector3.new(math.sin(i * 2.1) * 2.2, sy * 0.4, math.cos(i * 1.7) * 2.2)
		makePart(
			"Boulder_" .. i,
			Vector3.new(sx, sy, sz),
			CFrame.new(basePos + offset) * CFrame.Angles(i * 0.35, i * 0.8, i * 0.25),
			rockColor,
			(i % 2 == 0) and Enum.Material.Slate or Enum.Material.Basalt,
			folder,
			nil,
			true,
			0
		)
	end
end

local function buildOldMineLamp(parent: Instance, pos: Vector3, depthRatio: number)
	local lampModel = Instance.new("Model")
	lampModel.Name = "OldMineLamp"
	lampModel.Parent = parent

	makePart("Bracket", Vector3.new(0.35, 0.35, 1.2), pos + Vector3.new(0, 0.6, 0), Color3.fromRGB(68, 52, 42), Enum.Material.CorrodedMetal, lampModel)
	makePart("Cap", Vector3.new(1.1, 0.25, 1.1), pos + Vector3.new(0, 0.35, 0), Color3.fromRGB(58, 44, 36), Enum.Material.CorrodedMetal, lampModel)

	local baseBright = math.clamp(1.35 * (1 - depthRatio * 0.60), 0.35, 1.35)
	local lampColor = Color3.fromRGB(255, math.floor(195 - depthRatio * 45), math.floor(110 - depthRatio * 40))

	local globe = makePart("LampBulb", Vector3.new(0.75, 0.95, 0.75), pos - Vector3.new(0, 0.15, 0), lampColor, Enum.Material.Neon, lampModel)
	local pl = Instance.new("PointLight", globe)
	pl.Color = lampColor
	pl.Range = math.clamp(22 - depthRatio * 7, 12, 22)
	pl.Brightness = baseBright
	pl.Shadows = true

	table.insert(FlickerLamps, { Light = pl, BaseBrightness = baseBright, Globe = globe })
end

function WorldBuilder.BuildDeepMineArchitecture(
	worldFolder: Folder,
	onClaimCaveChest: ((Player, number, BasePart) -> ())?
)
	local shaftFolder = Instance.new("Folder", worldFolder)
	shaftFolder.Name = "DeepMineArchitecture"

	local totalMineDepth = GameConfig.MINE_LEVELS_COUNT * GameConfig.BLOCK_HEIGHT -- 30 * 6 = 180 studs
	local bottomY = GameConfig.MINE_TOP_ORIGIN.Y - totalMineDepth - 3             -- -186 studs
	local topWallY = -0.08 -- v49: strictly below surface Y = 0.0 so shaft walls NEVER poke through or Z-fight!
	local shaftWallH = topWallY - bottomY
	local wallMidY = (topWallY + bottomY) * 0.5
	local wallStoneCol = Color3.fromRGB(118, 108, 136) -- cool slate-lavender mine rock matching Reference 1

	-- v49: Exact non-overlapping monolithic shaft walls around the [-60..60] x [-138..-18] pit
	makePart("MineBedrockFloor", Vector3.new(148, 12, 148), Vector3.new(0, bottomY - 6, -78), Color3.fromRGB(52, 48, 66), Enum.Material.Basalt, shaftFolder, nil, true, 0)
	makePart("MineWallN", Vector3.new(144, shaftWallH, 12), Vector3.new(0, wallMidY, -144.04), wallStoneCol, Enum.Material.Rock, shaftFolder, nil, true, 0)
	makePart("MineWallS", Vector3.new(144, shaftWallH, 12), Vector3.new(0, wallMidY, -11.96),  wallStoneCol, Enum.Material.Rock, shaftFolder, nil, true, 0)
	makePart("MineWallW", Vector3.new(12, shaftWallH, 120), Vector3.new(-66.04, wallMidY, -78), wallStoneCol, Enum.Material.Rock, shaftFolder, nil, true, 0)
	makePart("MineWallE", Vector3.new(12, shaftWallH, 120), Vector3.new(66.04, wallMidY, -78),  wallStoneCol, Enum.Material.Rock, shaftFolder, nil, true, 0)

	-- v49: Layered Geological Strata Bands along the shaft walls so the mine edges look like real layered rock
	local strataPalette = {
		{ Color3.fromRGB(168, 110, 76), Enum.Material.Sandstone }, -- upper warm terracotta canyon crust
		{ Color3.fromRGB(132, 118, 148), Enum.Material.Slate },    -- upper-mid slate-lavender stone
		{ Color3.fromRGB(112, 102, 130), Enum.Material.Rock },     -- mid mine rock
		{ Color3.fromRGB(88, 82, 108), Enum.Material.Slate },      -- deep slate
		{ Color3.fromRGB(66, 62, 86), Enum.Material.Basalt },      -- abyssal basalt
	}
	for bandIdx = 1, 5 do
		local bandH = shaftWallH / 5
		local bandY = topWallY - (bandIdx - 0.5) * bandH
		local sCol = strataPalette[bandIdx][1]
		local sMat = strataPalette[bandIdx][2]
		makePart("ShaftStrataN_" .. bandIdx, Vector3.new(120.2, bandH - 0.08, 0.6), Vector3.new(0, bandY, -138.28), sCol, sMat, shaftFolder, nil, false, 0)
		makePart("ShaftStrataS_" .. bandIdx, Vector3.new(120.2, bandH - 0.08, 0.6), Vector3.new(0, bandY, -17.72),  sCol, sMat, shaftFolder, nil, false, 0)
		makePart("ShaftStrataW_" .. bandIdx, Vector3.new(0.6, bandH - 0.08, 119.6), Vector3.new(-60.28, bandY, -78), sCol, sMat, shaftFolder, nil, false, 0)
		makePart("ShaftStrataE_" .. bandIdx, Vector3.new(0.6, bandH - 0.08, 119.6), Vector3.new(60.28, bandY, -78),  sCol, sMat, shaftFolder, nil, false, 0)
	end

	-- v49: Clean Mine Rim Collar (stepped canyon stone & heavy timber curbing around the pit edge, zero Z-fighting)
	local rimFolder = Instance.new("Folder", shaftFolder)
	rimFolder.Name = "MineRimCollar"
	local rimTerra = Color3.fromRGB(168, 110, 76)
	local rimSlate = Color3.fromRGB(124, 114, 142)
	local rimWood  = Color3.fromRGB(108, 68, 38)
	-- North, West, East stone curbing + South left/right curbing (leaving X in [-7, 7] open for the entrance ramp)
	makePart("RimCurbN", Vector3.new(126.4, 0.42, 3.2), Vector3.new(0, 0.21, -139.65), rimSlate, Enum.Material.Slate, rimFolder, nil, true, 0)
	makePart("RimCurbW", Vector3.new(3.2, 0.42, 120.0), Vector3.new(-61.65, 0.21, -78), rimSlate, Enum.Material.Slate, rimFolder, nil, true, 0)
	makePart("RimCurbE", Vector3.new(3.2, 0.42, 120.0), Vector3.new(61.65, 0.21, -78),  rimSlate, Enum.Material.Slate, rimFolder, nil, true, 0)
	makePart("RimCurbSW", Vector3.new(53.2, 0.42, 3.2), Vector3.new(-33.6, 0.21, -16.35), rimSlate, Enum.Material.Slate, rimFolder, nil, true, 0)
	makePart("RimCurbSE", Vector3.new(53.2, 0.42, 3.2), Vector3.new(33.6, 0.21, -16.35),  rimSlate, Enum.Material.Slate, rimFolder, nil, true, 0)
	-- Upper terracotta cap strips on the rim curb
	makePart("RimCapN", Vector3.new(125.2, 0.26, 2.2), Vector3.new(0, 0.55, -139.85), rimTerra, Enum.Material.Sandstone, rimFolder, nil, true, 0)
	makePart("RimCapW", Vector3.new(2.2, 0.26, 119.6), Vector3.new(-61.85, 0.55, -78), rimTerra, Enum.Material.Sandstone, rimFolder, nil, true, 0)
	makePart("RimCapE", Vector3.new(2.2, 0.26, 119.6), Vector3.new(61.85, 0.55, -78),  rimTerra, Enum.Material.Sandstone, rimFolder, nil, true, 0)
	makePart("RimCapSW", Vector3.new(51.5, 0.26, 2.2), Vector3.new(-34.2, 0.55, -16.15), rimTerra, Enum.Material.Sandstone, rimFolder, nil, true, 0)
	makePart("RimCapSE", Vector3.new(51.5, 0.26, 2.2), Vector3.new(34.2, 0.55, -16.15),  rimTerra, Enum.Material.Sandstone, rimFolder, nil, true, 0)
	-- Timber mine collar beams framing the shaft interior edge just below Y = 0
	makePart("CollarBeamN", Vector3.new(119.6, 1.1, 0.8), Vector3.new(0, -0.60, -138.45), rimWood, Enum.Material.WoodPlanks, rimFolder, nil, true, 0)
	makePart("CollarBeamS", Vector3.new(119.6, 1.1, 0.8), Vector3.new(0, -0.60, -17.55),  rimWood, Enum.Material.WoodPlanks, rimFolder, nil, true, 0)
	makePart("CollarBeamW", Vector3.new(0.8, 1.1, 118.0), Vector3.new(-60.45, -0.60, -78), rimWood, Enum.Material.WoodPlanks, rimFolder, nil, true, 0)
	makePart("CollarBeamE", Vector3.new(0.8, 1.1, 118.0), Vector3.new(60.45, -0.60, -78),  rimWood, Enum.Material.WoodPlanks, rimFolder, nil, true, 0)

	-- ПУНКТ №10 ТЗ: НОЧНОЙ ЗАЩИТНЫЙ БАРЬЕР НАД ШАХТОЙ (включается только ночью!)
	local barrier = makePart(
		"NightMineBarrier",
		Vector3.new(136, 1.2, 132),
		Vector3.new(4, 1.2, -78),
		Color3.fromRGB(255, 75, 55),
		Enum.Material.ForceField,
		shaftFolder,
		nil,
		false,
		1.0
	)
	local bbg = Instance.new("BillboardGui", barrier)
	bbg.Name = "NightClosedBillboard"
	bbg.Size = UDim2.new(0, 360, 0, 72)
	bbg.StudsOffset = Vector3.new(0, 4.5, 52)
	bbg.MaxDistance = 120
	bbg.Enabled = false
	local bCard = Instance.new("Frame", bbg)
	bCard.Size = UDim2.new(1, 0, 1, 0)
	bCard.BackgroundColor3 = Color3.fromRGB(38, 16, 20)
	bCard.BackgroundTransparency = 0.1
	Instance.new("UICorner", bCard).CornerRadius = UDim.new(0, 12)
	local bst = Instance.new("UIStroke", bCard)
	bst.Color = Color3.fromRGB(255, 85, 75)
	bst.Thickness = 2
	local bTxt = Instance.new("TextLabel", bCard)
	bTxt.Size = UDim2.new(1, -16, 1, -10)
	bTxt.Position = UDim2.new(0, 8, 0, 5)
	bTxt.BackgroundTransparency = 1
	bTxt.Font = Enum.Font.GothamBold
	bTxt.TextColor3 = Color3.fromRGB(255, 195, 185)
	bTxt.TextScaled = true
	bTxt.Text = "🌙 " .. GameConfig.NIGHT_CLOSED_MESSAGE
	NightBarrierPart = barrier

	-- Неровные стены, деревянные подпорки, каменные полки и лампы по глубине 1..30
	for lvl = 6, GameConfig.MINE_LEVELS_COUNT, 3 do
		local yPos = GameConfig.MINE_TOP_ORIGIN.Y - (lvl - 1) * GameConfig.BLOCK_HEIGHT
		local depthRatio = lvl / GameConfig.MINE_LEVELS_COUNT
		local rockCol = Color3.fromRGB(
			math.floor(124 - depthRatio * 68),
			math.floor(114 - depthRatio * 64),
			math.floor(140 - depthRatio * 68)
		)

		makePart(
			"CragN_" .. lvl,
			Vector3.new(18 + (lvl % 5) * 4, 5.5, 3.2),
			CFrame.new(-36 + ((lvl * 13) % 72), yPos, -137.5) * CFrame.Angles(math.rad((lvl % 3) * 4), 0, 0),
			rockCol,
			(lvl > 18) and Enum.Material.Basalt or Enum.Material.Slate,
			shaftFolder
		)
		makePart(
			"CragW_" .. lvl,
			Vector3.new(3.2, 5.5, 18 + (lvl % 4) * 4),
			CFrame.new(-59.5, yPos, -118 + ((lvl * 11) % 78)),
			rockCol,
			(lvl > 18) and Enum.Material.Basalt or Enum.Material.Granite,
			shaftFolder
		)

	end

	-- v49: MineWallE already starts at X = 60.04 (flush with the 20x20 grid), so no overlapping MineEastFill is needed.

	-- 4 пещерных кармана с лужами, светящимися грибами и сундуками
	local pocketDefs = {
		{ Lvl = 6,  Row = 4,  Col = 16, RewardCoins = 30,  MushroomCol = Color3.fromRGB(85, 245, 165) },
		{ Lvl = 13, Row = 16, Col = 4,  RewardCoins = 95,  MushroomCol = Color3.fromRGB(95, 210, 255) },
		{ Lvl = 20, Row = 5,  Col = 5,  RewardCoins = 260, MushroomCol = Color3.fromRGB(195, 110, 255) },
		{ Lvl = 27, Row = 15, Col = 15, RewardCoins = 750, MushroomCol = Color3.fromRGB(70, 255, 215) },
	}
	for idx, pDef in ipairs(pocketDefs) do
		local bw = GameConfig.BLOCK_WIDTH
		local bh = GameConfig.BLOCK_HEIGHT
		local centerPos = Vector3.new(
			GameConfig.MINE_TOP_ORIGIN.X + (pDef.Col - 1) * bw,
			GameConfig.MINE_TOP_ORIGIN.Y - (pDef.Lvl - 1) * bh - 1.4,
			GameConfig.MINE_TOP_ORIGIN.Z + (pDef.Row - 1) * bw
		)
		local pocketFolder = Instance.new("Folder", shaftFolder)
		pocketFolder.Name = "CavePocket_" .. idx

		makePart(
			"CaveWaterPuddle",
			Vector3.new(0.25, 6.8, 6.8),
			CFrame.new(centerPos + Vector3.new(0, -0.35, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(38, 125, 185),
			Enum.Material.SmoothPlastic,
			pocketFolder,
			Enum.PartType.Cylinder,
			true,
			0
		)
		for m = 1, 4 do
			local ang = m * math.pi * 0.5 + 0.3
			local mPos = centerPos + Vector3.new(math.cos(ang) * 3.0, 0.2, math.sin(ang) * 3.0)
			makePart("MushroomStem_" .. m, Vector3.new(0.32, 0.9, 0.32), mPos, Color3.fromRGB(210, 220, 230), Enum.Material.SmoothPlastic, pocketFolder)
			local cap = makePart("MushroomCap_" .. m, Vector3.new(1.1, 0.55, 1.1), mPos + Vector3.new(0, 0.5, 0), pDef.MushroomCol, Enum.Material.Neon, pocketFolder, Enum.PartType.Ball)
			local mpl = Instance.new("PointLight", cap)
			mpl.Color = pDef.MushroomCol
			mpl.Range = 9
			mpl.Brightness = 0.85
		end

		local chest = makePart("DeepTreasureChest_" .. idx, Vector3.new(2.8, 2.0, 2.0), centerPos + Vector3.new(0, 0.65, 0), Color3.fromRGB(128, 78, 38), Enum.Material.WoodPlanks, pocketFolder)
		local chestBand = makePart("ChestGoldBand", Vector3.new(2.9, 0.35, 2.1), centerPos + Vector3.new(0, 0.85, 0), Color3.fromRGB(255, 200, 55), Enum.Material.Metal, pocketFolder)
		local cd = Instance.new("ClickDetector", chest)
		cd.MaxActivationDistance = 18
		-- v37: ONE-TIME chest. First player who loots it gets the coins, then the chest disappears.
		local chestLooted = false
		cd.MouseClick:Connect(function(plr: Player)
			if chestLooted or not chest.Parent then return end
			chestLooted = true
			cd.MaxActivationDistance = 0
			if onClaimCaveChest then
				onClaimCaveChest(plr, pDef.RewardCoins, chest)
			end
			local tInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			for _, part in ipairs({ chest, chestBand }) do
				if part and part.Parent then
					part.CanCollide = false
					TweenService:Create(part, tInfo, { Size = part.Size * 0.05, Transparency = 1 }):Play()
				end
			end
			task.delay(0.4, function()
				if chest.Parent then chest:Destroy() end
				if chestBand and chestBand.Parent then chestBand:Destroy() end
			end)
		end)
	end

	task.spawn(function()
		while task.wait(0.18) do
			for _, item in ipairs(FlickerLamps) do
				if item.Light and item.Light.Parent then
					local jitter = (math.random() - 0.5) * 0.22
					item.Light.Brightness = math.max(0.15, item.BaseBrightness + jitter)
				end
			end
		end
	end)
end


-- ============================================================================
-- 4b. v14: ТРОПИНКА, ВХОД С ВЫВЕСКОЙ «ШАХТА», ТРАВА, ДЕРЕВЬЯ И РАСШИРЕНИЕ ЗОНЫ ПРОДАЖИ
-- ============================================================================
local FONT_DISPLAY = Enum.Font.GothamBlack  -- поддерживает кириллицу (FredokaOne — нет)

function WorldBuilder.BuildGravelPath(parent: Instance)
	local folder = Instance.new("Folder", parent)
	folder.Name = "GravelPath"
	local rng = Random.new(1407)

	-- Жёлтая щебёночная тропинка от спавна (Z = 18) до входа (Z = -12). Ширина 10.
	local zFrom, zTo = 13.4, -17.8 -- v52: тропа начинается от края каменной площади
	local length = zFrom - zTo
	local midZ = (zFrom + zTo) * 0.5
	makePart("PathBase", Vector3.new(10, 0.5, length), Vector3.new(0, 0.2, midZ), Color3.fromRGB(222, 190, 112), Enum.Material.Sand, folder)
	makePart("PathCenterWear", Vector3.new(5.5, 0.52, length - 2), Vector3.new(0, 0.2, midZ), Color3.fromRGB(232, 204, 132), Enum.Material.Sand, folder)

	-- Щебень и галька по полотну
	local tones = { Color3.fromRGB(196, 160, 92), Color3.fromRGB(170, 140, 84), Color3.fromRGB(214, 192, 140), Color3.fromRGB(150, 130, 98) }
	for i = 1, 150 do
		local sz = rng:NextNumber(0.35, 0.9)
		local p = makePart("Pebble", Vector3.new(sz, sz * 0.5, sz * rng:NextNumber(0.8, 1.2)),
			CFrame.new(rng:NextNumber(-4.6, 4.6), 0.5, rng:NextNumber(zTo + 1, zFrom - 1)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			tones[rng:NextInteger(1, #tones)], Enum.Material.Slate, folder, nil, false)
		p.CanQuery = false
	end

	-- Бордюрные камни вдоль обеих сторон
	local z = zTo + 1
	local flip = 1
	while z < zFrom do
		for _, side in ipairs({ -5.4, 5.4 }) do
			local w = rng:NextNumber(1.1, 1.9)
			makePart("EdgeStone", Vector3.new(1.3, rng:NextNumber(0.8, 1.2), w),
				CFrame.new(side + rng:NextNumber(-0.15, 0.15), 0.4, z) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0),
				Color3.fromRGB(128 + flip * 8, 130 + flip * 8, 138 + flip * 8), Enum.Material.Slate, folder)
		end
		flip = -flip
		z += 2.6
	end
end

function WorldBuilder.BuildMineEntrance(parent: Instance)
	local folder = Instance.new("Folder", parent)
	folder.Name = "MineEntrance"
	local z0 = GameConfig.MINE_ENTRANCE_POS.Z
	local wood = Color3.fromRGB(112, 72, 40)
	local woodDark = Color3.fromRGB(78, 50, 28)
	local gold = Color3.fromRGB(255, 190, 50)
	MineSignNeon = {}

	-- Две массивные деревянные опоры на каменных основаниях
	for _, sx in ipairs({ -10.5, 10.5 }) do
		makePart("GateFoot", Vector3.new(4.2, 1.6, 4.2), Vector3.new(sx, 0.8, z0), Color3.fromRGB(104, 108, 118), Enum.Material.Slate, folder)
		makePart("GatePost", Vector3.new(2.2, 13.5, 2.2), Vector3.new(sx, 8.3, z0), wood, Enum.Material.WoodPlanks, folder)
		makePart("GatePostBand1", Vector3.new(2.6, 0.5, 2.6), Vector3.new(sx, 3.0, z0), Color3.fromRGB(60, 64, 74), Enum.Material.Metal, folder)
		makePart("GatePostBand2", Vector3.new(2.6, 0.5, 2.6), Vector3.new(sx, 10.5, z0), Color3.fromRGB(60, 64, 74), Enum.Material.Metal, folder)
	end

	-- Верхние балки и косые подкосы
	makePart("GateBeamTop", Vector3.new(26, 1.8, 2.4), Vector3.new(0, 15.4, z0), woodDark, Enum.Material.WoodPlanks, folder)
	makePart("GateBeamLow", Vector3.new(23, 1.2, 1.8), Vector3.new(0, 11.2, z0 + 0.2), wood, Enum.Material.WoodPlanks, folder)
	for _, sx in ipairs({ -1, 1 }) do
		makePart("GateBrace", Vector3.new(0.9, 5.2, 1.2),
			CFrame.new(sx * 8.6, 12.8, z0 + 0.1) * CFrame.Angles(0, 0, math.rad(-sx * 42)), woodDark, Enum.Material.WoodPlanks, folder)
	end

	-- Объёмная вывеска: деревянный щит + золотая неоновая рамка + текст «ШАХТА»
	local board = makePart("MineSignBoard", Vector3.new(19, 5.4, 1.4), Vector3.new(0, 19.0, z0 + 0.3), Color3.fromRGB(34, 26, 22), Enum.Material.WoodPlanks, folder)
	for _, d in ipairs({
		{ Vector3.new(19.8, 0.45, 1.7), Vector3.new(0, 21.9, z0 + 0.3) },
		{ Vector3.new(19.8, 0.45, 1.7), Vector3.new(0, 16.1, z0 + 0.3) },
		{ Vector3.new(0.45, 6.3, 1.7), Vector3.new(-9.7, 19.0, z0 + 0.3) },
		{ Vector3.new(0.45, 6.3, 1.7), Vector3.new(9.7, 19.0, z0 + 0.3) },
	}) do
		table.insert(MineSignNeon, makePart("SignNeonFrame", d[1], d[2], gold, Enum.Material.Neon, folder))
	end
	-- Опоры вывески к балке
	for _, sx in ipairs({ -7, 7 }) do
		makePart("SignStrut", Vector3.new(0.9, 3.4, 0.9), Vector3.new(sx, 17.0, z0 + 0.1), woodDark, Enum.Material.WoodPlanks, folder)
	end

	local gui = Instance.new("SurfaceGui", board)
	gui.Face = Enum.NormalId.Back            -- смотрит на игроков, идущих от спавна (+Z)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	local lbl = Instance.new("TextLabel", gui)
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = FONT_DISPLAY
	lbl.TextScaled = true
	lbl.Text = GameConfig.MINE_SIGN_TEXT
	lbl.TextColor3 = Color3.fromRGB(255, 214, 80)
	local strokeLbl = Instance.new("UIStroke", lbl)
	strokeLbl.Thickness = 5
	strokeLbl.Color = Color3.fromRGB(62, 30, 8)
	local pad = Instance.new("UIPadding", lbl)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	MineSignLabel = lbl

	local sl = Instance.new("PointLight", board)
	sl.Color = gold
	sl.Range = 26
	sl.Brightness = 1.4

	-- Фонари по бокам входа
	for _, sx in ipairs({ -8.2, 8.2 }) do
		local lamp = makePart("GateLantern", Vector3.new(1.3, 1.9, 1.3), Vector3.new(sx, 9.3, z0 + 2.0), Color3.fromRGB(255, 220, 120), Enum.Material.Neon, folder)
		makePart("GateLanternCap", Vector3.new(1.7, 0.4, 1.7), Vector3.new(sx, 10.4, z0 + 2.0), Color3.fromRGB(40, 44, 52), Enum.Material.Metal, folder)
		local pl = Instance.new("PointLight", lamp)
		pl.Color = Color3.fromRGB(255, 205, 120)
		pl.Range = 20
		pl.Brightness = 1.2
	end
	-- Перед входом больше нет мусора: только тропинка и вывеска.
end

function WorldBuilder.BuildGrassAndTrees(parent: Instance)
	local folder = Instance.new("Folder", parent)
	folder.Name = "GrassAndTrees"
	local rng = Random.new(20261107)
	local LIM = GameConfig.MAP_HALF_EXTENT - 6   -- до невидимых стен по периметру

	-- Зоны, где травы/деревьев быть не должно: тропа, спавн, рынок, павильон, площадь, шахта
	local function blocked(x: number, z: number, margin: number): boolean
		local m = margin
		if math.abs(x) < 8 + m and z > -16 - m and z < 26 + m then return true end        -- тропинка и спавн
		if x > -54 - m and x < -10 + m and z > -14 - m and z < 24 + m then return true end -- рынок SELL (площадь 40×34)
		if x > 10 - m and x < 56 + m and z > -8 - m and z < 22 + m then return true end    -- павильон SHOP
		if math.abs(x) < 44 + m and z > 2 - m and z < 14 + m then return true end          -- площадь
		if x > -72 - m and x < 82 + m and z > -152 - m and z < -10 + m then return true end -- шахта
		return false
	end

	-- 1) Крупные пятна травы разных оттенков по всей поверхности (даёт «живой» газон)
	local patchCols = { Color3.fromRGB(104, 224, 70), Color3.fromRGB(70, 180, 56), Color3.fromRGB(120, 232, 84), Color3.fromRGB(60, 160, 52) }
	local patches = 0
	for _ = 1, 400 do
		if patches >= 70 then break end
		local x = rng:NextNumber(GameConfig.MAP_BOUNDS.MinX + 6, GameConfig.MAP_BOUNDS.MaxX - 6)
		local z = rng:NextNumber(GameConfig.MAP_BOUNDS.MinZ + 6, GameConfig.MAP_BOUNDS.MaxZ - 6)
		if not blocked(x, z, 6) then
			patches += 1
			local d = rng:NextNumber(10, 26)
			local p = makePart("GrassPatch", Vector3.new(0.1, d, d * rng:NextNumber(0.7, 1.1)),
				CFrame.new(x, 0.04, z) * CFrame.Angles(0, rng:NextNumber(0, 3.14), math.rad(90)),
				patchCols[rng:NextInteger(1, #patchCols)], Enum.Material.Grass, folder, Enum.PartType.Cylinder, false, 0.4)
			p.CanQuery = false
			p.CastShadow = false
		end
	end

	-- 2) Кустики травы по ВСЕЙ карте: 2 тонких клина под углом, 3 оттенка зелёного
	local greens = { Color3.fromRGB(96, 214, 70), Color3.fromRGB(66, 176, 58), Color3.fromRGB(128, 232, 90) }
	local flowerCols = { Color3.fromRGB(255, 226, 90), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 150, 190), Color3.fromRGB(150, 200, 255) }
	local made = 0
	for _ = 1, 3000 do
		if made >= 420 then break end
		local x = rng:NextNumber(GameConfig.MAP_BOUNDS.MinX + 6, GameConfig.MAP_BOUNDS.MaxX - 6)
		local z = rng:NextNumber(GameConfig.MAP_BOUNDS.MinZ + 6, GameConfig.MAP_BOUNDS.MaxZ - 6)
		if not blocked(x, z, 1) then
			made += 1
			for k = 1, 2 do
				local h = rng:NextNumber(1.1, 2.2)
				local w = makePart("GrassBlade", Vector3.new(0.18, h, 0.9),
					CFrame.new(x, h * 0.5, z) * CFrame.Angles(0, rng:NextNumber(0, 3.14) + k * 1.57, rng:NextNumber(-0.18, 0.18)),
					greens[rng:NextInteger(1, #greens)], Enum.Material.Grass, folder, nil, false)
				w.CanQuery = false
				w.CastShadow = false
			end
			if made % 7 == 0 then   -- цветочек в каждом седьмом кустике
				local fl = makePart("Flower", Vector3.new(0.38, 0.38, 0.38), Vector3.new(x + 0.5, 1.2, z + 0.3),
					flowerCols[rng:NextInteger(1, #flowerCols)], Enum.Material.SmoothPlastic, folder, Enum.PartType.Ball, false)
				fl.CanQuery = false
				fl.CastShadow = false
			end
		end
	end

	-- 3) v19: trees removed (mine props are built in BuildMineProps)
end

-- Расширение пункта приёма руды: большая площадь с кольцом зоны автопродажи, столами, ящиками, фонарями
function WorldBuilder.ExtendSellMarket(market: Model, centerPos: Vector3)
	-- v30: plaza, lamp poles, tables, crates and benches removed (clean reference look).
	-- Only the auto-sell zone ring and the hint billboard remain.
	local neonGreen = Color3.fromRGB(55, 245, 115)

	-- Кольцо зоны автопродажи: радиус = SELL_ZONE_RADIUS
	local R = GameConfig.SELL_ZONE_RADIUS
	local SEG = 64
	for k = 0, SEG - 1 do
		local a = (k / SEG) * math.pi * 2
		local pos = Vector3.new(centerPos.X + math.cos(a) * R, 0.36, centerPos.Z + math.sin(a) * R)
		local segLen = (2 * math.pi * R / SEG) * 1.02
		local seg = makePart("AutoSellZoneRing", Vector3.new(segLen, 0.12, 0.45),
			CFrame.new(pos) * CFrame.Angles(0, -a - math.pi / 2, 0),
			neonGreen, Enum.Material.Neon, market, nil, false, 0.25)
		seg.CanQuery = false
		seg.CastShadow = false
	end

	-- Подсказка (билборд)
	local anchor = makePart("AutoSellHintAnchor", Vector3.new(0.4, 0.4, 0.4), centerPos + Vector3.new(0, 7.6, 14), neonGreen, Enum.Material.Neon, market, nil, false, 1)
	anchor.CanQuery = false
	local bg = Instance.new("BillboardGui", anchor)
	bg.Size = UDim2.new(0, 300, 0, 64)
	bg.MaxDistance = 95
	local card = Instance.new("Frame", bg)
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(14, 28, 22)
	card.BackgroundTransparency = 0.18
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	local st = Instance.new("UIStroke", card)
	st.Color = neonGreen
	st.Thickness = 2.5
	local t1 = Instance.new("TextLabel", card)
	t1.Size = UDim2.new(1, -16, 0.5, 0)
	t1.Position = UDim2.new(0, 8, 0, 4)
	t1.BackgroundTransparency = 1
	t1.Font = FONT_DISPLAY
	t1.TextScaled = true
	t1.TextColor3 = neonGreen
	t1.Text = "SELL YOUR ORE"
	local t2 = Instance.new("TextLabel", card)
	t2.Size = UDim2.new(1, -16, 0.38, 0)
	t2.Position = UDim2.new(0, 8, 0.56, 0)
	t2.BackgroundTransparency = 1
	t2.Font = Enum.Font.GothamBold
	t2.TextScaled = true
	t2.TextColor3 = Color3.fromRGB(235, 245, 240)
	t2.Text = "Step into the green circle to sell automatically"
end

-- ============================================================================
-- 5. СБОРКА ВСЕГО МИРА
-- ============================================================================
-- ============================================================================
-- v19: MINE PROPS instead of trees: crates, TNT, pickaxes, minecarts on rails,
-- barrels, ore piles and lanterns around the mine and on the field.
-- ============================================================================
function WorldBuilder.BuildMineProps(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "MineProps"
	folder.Parent = parent
	local rng = Random.new(1919)
	local WOOD = Color3.fromRGB(156, 104, 58)
	local WOOD_D = Color3.fromRGB(98, 63, 36)
	local IRON = Color3.fromRGB(74, 78, 88)
	local IRON_L = Color3.fromRGB(146, 152, 164)
	local ROCK = Color3.fromRGB(104, 98, 112)
	local ORE_COLS = {
		Color3.fromRGB(255, 196, 40),
		Color3.fromRGB(60, 170, 255),
		Color3.fromRGB(196, 80, 255),
		Color3.fromRGB(90, 230, 140),
	}

	local function P(name: string, size: Vector3, cf: CFrame, col: Color3, mat: Enum.Material?, collide: boolean?, shape: Enum.PartType?): Part
		local p = makePart(name, size, cf, col, mat or Enum.Material.SmoothPlastic, folder, shape, collide == true, 0)
		p.CanQuery = collide == true
		return p
	end

	local function crate(cf: CFrame, s: number, col: Color3?)
		local c = cf * CFrame.new(0, s / 2, 0)
		P("Crate", Vector3.new(s, s, s), c, col or WOOD, Enum.Material.WoodPlanks, true)
		local t = s * 0.12
		local h = s / 2 - t / 2 + 0.03
		for _, a in ipairs({ -1, 1 }) do
			for _, b in ipairs({ -1, 1 }) do
				P("CrateEdge", Vector3.new(t, s + 0.06, t), c * CFrame.new(a * h, 0, b * h), WOOD_D, Enum.Material.Wood)
				P("CrateEdge", Vector3.new(s + 0.06, t, t), c * CFrame.new(0, a * h, b * h), WOOD_D, Enum.Material.Wood)
				P("CrateEdge", Vector3.new(t, t, s + 0.06), c * CFrame.new(a * h, b * h, 0), WOOD_D, Enum.Material.Wood)
			end
		end
		local diag = math.sqrt(2) * (s - 2 * t)
		for _, b in ipairs({ -1, 1 }) do
			P("CrateBrace", Vector3.new(diag, t * 0.8, 0.1), c * CFrame.new(0, 0, b * (s / 2 + 0.04)) * CFrame.Angles(0, 0, math.rad(45 * b)), WOOD_D, Enum.Material.Wood)
			P("CrateBrace", Vector3.new(0.1, t * 0.8, diag), c * CFrame.new(b * (s / 2 + 0.04), 0, 0) * CFrame.Angles(math.rad(45 * b), 0, 0), WOOD_D, Enum.Material.Wood)
		end
	end

	local function tntCrate(cf: CFrame)
		crate(cf, 3, Color3.fromRGB(196, 46, 38))
		local label = P("TNTLabel", Vector3.new(2.2, 1, 0.05), cf * CFrame.new(0, 1.5, -1.64), Color3.fromRGB(240, 226, 190), Enum.Material.SmoothPlastic)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(220, 100)
		sg.LightInfluence = 0.6
		sg.Parent = label
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Text = "TNT"
		tl.Font = Enum.Font.FredokaOne
		tl.TextScaled = true
		tl.TextColor3 = Color3.fromRGB(170, 30, 24)
		tl.Parent = sg
	end

	local function barrel(cf: CFrame)
		local c = cf * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.rad(90))
		P("Barrel", Vector3.new(3.4, 2.6, 2.6), c, Color3.fromRGB(140, 90, 50), Enum.Material.Wood, true, Enum.PartType.Cylinder)
		for _, y in ipairs({ -1.05, 0, 1.05 }) do
			P("BarrelBand", Vector3.new(0.25, 2.72, 2.72), c * CFrame.new(y, 0, 0), IRON, Enum.Material.Metal, true, Enum.PartType.Cylinder)
		end
		P("BarrelLid", Vector3.new(0.08, 2.3, 2.3), c * CFrame.new(1.71, 0, 0), WOOD_D, Enum.Material.Wood, true, Enum.PartType.Cylinder)
	end

	-- v49: pickaxe prop with FULL collisions (all parts CanCollide = true + solid step-on bounding box)
	local function pickaxe(cf: CFrame, tiltDeg: number)
		local h = 4.4
		local base = cf * CFrame.Angles(math.rad(tiltDeg), 0, 0)
		P("PickHandle", Vector3.new(0.38, h, 0.38), base * CFrame.new(0, h / 2 - 0.6, 0), WOOD, Enum.Material.Wood, true)
		P("PickGrip", Vector3.new(0.46, 1, 0.46), base * CFrame.new(0, h - 1.7, 0), Color3.fromRGB(58, 40, 30), Enum.Material.Fabric, true)
		local top = base * CFrame.new(0, h - 0.6, 0)
		P("PickHeadCore", Vector3.new(0.76, 0.72, 0.72), top, IRON, Enum.Material.Metal, true)
		for _, sx in ipairs({ -1, 1 }) do
			P("PickHeadArm", Vector3.new(1.45, 0.50, 0.48), top * CFrame.new(sx * 0.95, -0.12, 0) * CFrame.Angles(0, 0, math.rad(sx * -14)), IRON_L, Enum.Material.Metal, true)
			P("PickHeadTip", Vector3.new(0.95, 0.36, 0.36), top * CFrame.new(sx * 1.9, -0.5, 0) * CFrame.Angles(0, 0, math.rad(sx * -34)), IRON_L, Enum.Material.Metal, true)
		end
		-- Solid invisible collision ramp/box so players can easily jump and stand on the pickaxe
		local colBox = makePart("PickaxeStepCollider", Vector3.new(4.2, h - 0.4, 1.3), base * CFrame.new(0, (h - 0.4) * 0.5, 0), IRON, Enum.Material.SmoothPlastic, folder, nil, true, 1)
		colBox.CanQuery = false
	end

	local function rails(cf: CFrame, length: number)
		for _, sx in ipairs({ -1, 1 }) do
			P("Rail", Vector3.new(0.3, 0.32, length), cf * CFrame.new(sx * 1.75, 0.41, 0), IRON_L, Enum.Material.Metal, true)
		end
		local n = math.max(2, math.floor(length / 2.2))
		for i = 0, n do
			P("Sleeper", Vector3.new(4.8, 0.25, 0.9), cf * CFrame.new(0, 0.13, -length / 2 + 0.45 + i * ((length - 0.9) / n)), WOOD_D, Enum.Material.Wood, true)
		end
	end

	-- v49: minecart with FULL collisions (all parts CanCollide = true + solid top step deck)
	local function minecart(cf: CFrame, oreCol: Color3)
		local L, W, H = 4.6, 3.2, 2.3
		local c = cf * CFrame.new(0, 1.15, 0)
		local BODY = Color3.fromRGB(116, 74, 42)
		P("CartFloor", Vector3.new(W, 0.3, L), c * CFrame.new(0, 0.15, 0), IRON, Enum.Material.Metal, true)
		for _, s in ipairs({ -1, 1 }) do
			P("CartSide", Vector3.new(0.26, H, L), c * CFrame.new(s * (W / 2 + 0.03), H / 2, 0) * CFrame.Angles(0, 0, math.rad(s * -8)), BODY, Enum.Material.WoodPlanks, true)
			P("CartEnd", Vector3.new(W + 0.5, H, 0.26), c * CFrame.new(0, H / 2, s * (L / 2 + 0.03)) * CFrame.Angles(math.rad(s * 8), 0, 0), BODY, Enum.Material.WoodPlanks, true)
			P("CartRim", Vector3.new(0.4, 0.3, L + 0.9), c * CFrame.new(s * (W / 2 + 0.32), H, 0), IRON_L, Enum.Material.Metal, true)
			P("CartRim", Vector3.new(W + 0.9, 0.3, 0.4), c * CFrame.new(0, H, s * (L / 2 + 0.32)), IRON_L, Enum.Material.Metal, true)
			P("CartAxle", Vector3.new(3.6, 0.22, 0.22), cf * CFrame.new(0, 1.22, s * 1.45), IRON, Enum.Material.Metal, true)
			for _, t in ipairs({ -1, 1 }) do
				local wcf = cf * CFrame.new(s * 1.75, 1.22, t * 1.45)
				P("CartWheel", Vector3.new(0.36, 1.3, 1.3), wcf, Color3.fromRGB(46, 48, 54), Enum.Material.Metal, true, Enum.PartType.Cylinder)
				P("CartHub", Vector3.new(0.44, 0.5, 0.5), wcf, IRON_L, Enum.Material.Metal, true, Enum.PartType.Cylinder)
			end
		end
		P("CartLoad", Vector3.new(W + 0.2, 1.15, L + 0.2), c * CFrame.new(0, H - 0.42, 0), ROCK, Enum.Material.Slate, true)
		for i = 1, 9 do
			local glow = i % 2 == 0
			local sz = rng:NextNumber(0.6, 1.1)
			P("CartOre", Vector3.new(sz, sz * 0.85, sz),
				c * CFrame.new(rng:NextNumber(-W / 2 + 0.7, W / 2 - 0.7), H - 0.05 + rng:NextNumber(0, 0.35), rng:NextNumber(-L / 2 + 0.7, L / 2 - 0.7))
					* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)),
				glow and oreCol or ROCK, glow and Enum.Material.Neon or Enum.Material.Slate, true)
		end
		-- Solid full-body collision hull so jumping onto the minecart from any side works smoothly
		local hull = makePart("CartFullCollider", Vector3.new(W + 0.9, H + 1.15, L + 0.9), cf * CFrame.new(0, (H + 1.15) * 0.5, 0), IRON, Enum.Material.SmoothPlastic, folder, nil, true, 1)
		hull.CanQuery = false
	end

	local function orePile(cf: CFrame, oreCol: Color3)
		for i = 1, 7 do
			local sz = rng:NextNumber(1.2, 2.4)
			P("PileRock", Vector3.new(sz, sz * 0.8, sz), cf * CFrame.new(rng:NextNumber(-1.8, 1.8), sz * 0.3, rng:NextNumber(-1.8, 1.8)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5)), ROCK, Enum.Material.Slate, true)
		end
		for _ = 1, 6 do
			local sz = rng:NextNumber(0.5, 0.9)
			P("PileOre", Vector3.new(sz, sz, sz), cf * CFrame.new(rng:NextNumber(-1.6, 1.6), rng:NextNumber(0.6, 1.4), rng:NextNumber(-1.6, 1.6)) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0), oreCol, Enum.Material.Neon, true)
		end
	end

	local function lanternPost(cf: CFrame)
		P("LanternPost", Vector3.new(0.5, 6.5, 0.5), cf * CFrame.new(0, 3.25, 0), WOOD_D, Enum.Material.Wood, true)
		P("LanternArm", Vector3.new(0.35, 0.35, 1.6), cf * CFrame.new(0, 6.2, -0.7), WOOD_D, Enum.Material.Wood)
		local lc = cf * CFrame.new(0, 5.3, -1.3)
		P("LanternCap", Vector3.new(0.9, 0.25, 0.9), lc * CFrame.new(0, 0.6, 0), IRON, Enum.Material.Metal)
		P("LanternHook", Vector3.new(0.1, 0.5, 0.1), lc * CFrame.new(0, 0.9, 0), IRON, Enum.Material.Metal)
		local glass = P("LanternGlass", Vector3.new(0.7, 1, 0.7), lc, Color3.fromRGB(255, 196, 96), Enum.Material.Neon)
		P("LanternBase", Vector3.new(0.9, 0.2, 0.9), lc * CFrame.new(0, -0.6, 0), IRON, Enum.Material.Metal)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 110)
		light.Range = 16
		light.Brightness = 0.25
		light.Shadows = false
		light.Parent = glass
		table.insert(NightLights, light)
	end

	local function site(origin: CFrame, oreIdx: number, withTnt: boolean)
		local oreCol = ORE_COLS[oreIdx]
		rails(origin, 22)
		minecart(origin * CFrame.new(0, 0, -5), oreCol)
		minecart(origin * CFrame.new(0, 0, 3.2), ORE_COLS[oreIdx % #ORE_COLS + 1])
		P("RailStop", Vector3.new(4.2, 1.2, 0.6), origin * CFrame.new(0, 0.6, 11.2), WOOD_D, Enum.Material.Wood, true)
		local left = origin * CFrame.new(-7, 0, -3)
		crate(left * CFrame.Angles(0, math.rad(8), 0), 4)
		crate(left * CFrame.new(0.3, 0, 4.4) * CFrame.Angles(0, math.rad(-12), 0), 3.4)
		crate(left * CFrame.new(0.2, 4, 0.2) * CFrame.Angles(0, math.rad(20), 0), 3)
		if withTnt then
			tntCrate(left * CFrame.new(-0.4, 0, 8.2) * CFrame.Angles(0, math.rad(195), 0))
		end
		pickaxe(left * CFrame.new(2.6, 0, -2.6), 20)
		pickaxe(origin * CFrame.new(7.5, 0, -6) * CFrame.Angles(0, math.rad(60), 0), -24)
		barrel(origin * CFrame.new(7, 0, 0))
		barrel(origin * CFrame.new(8.4, 0, 2.9))
		orePile(origin * CFrame.new(7.5, 0, 7.5), oreCol)
		lanternPost(origin * CFrame.new(-4.6, 0, 9.5) * CFrame.Angles(0, math.rad(180), 0))
	end

	local SITES = {
		{ CFrame.new(-31, 0, 52), 1, true },
		{ CFrame.new(32, 0, 52) * CFrame.Angles(0, math.pi, 0), 2, false },
	}
	-- single carts on short rails in the side strips (between SELL/SHOP and the cliffs)
	for i, p in ipairs({ Vector3.new(-63, 0, 30), Vector3.new(70, 0, 30) }) do
		local cf = CFrame.new(p)
		rails(cf, 12)
		minecart(cf * CFrame.new(0, 0, -1.5), ORE_COLS[i + 1])
		P("RailStop", Vector3.new(4.2, 1.2, 0.6), cf * CFrame.new(0, 0.6, 6.2), WOOD_D, Enum.Material.Wood, true)
		lanternPost(cf * CFrame.new(0, 0, 8.6) * CFrame.Angles(0, math.rad(180), 0))
	end
	-- compact clusters: crates + pickaxe + barrel/ore pile
	for i, p in ipairs({ Vector3.new(-63, 0, 3), Vector3.new(-63, 0, 47), Vector3.new(70, 0, 3), Vector3.new(70, 0, 47), Vector3.new(-14, 0, 60), Vector3.new(15, 0, 60) }) do
		local cf = CFrame.new(p) * CFrame.Angles(0, math.rad(i * 23), 0)
		crate(cf, 3.6)
		crate(cf * CFrame.new(0.2, 3.6, 0.1) * CFrame.Angles(0, math.rad(15), 0), 2.8)
		crate(cf * CFrame.new(0, 0, 4.4) * CFrame.Angles(0, math.rad(-10), 0), 3)
		pickaxe(cf * CFrame.new(0, 0, -3.6), 18)
		if i % 2 == 0 then
			barrel(cf * CFrame.new(0, 0, 8.6))
		else
			orePile(cf * CFrame.new(0, 0, 9), ORE_COLS[(i % #ORE_COLS) + 1])
		end
	end
	-- loose tools by the mine gate
	pickaxe(CFrame.new(-14.5, 0, -3) * CFrame.Angles(0, math.rad(70), 0), 22)
	crate(CFrame.new(14.5, 0, -3.5) * CFrame.Angles(0, math.rad(12), 0), 3)
	tntCrate(CFrame.new(14.8, 0, 0.4) * CFrame.Angles(0, math.rad(180 - 20), 0))
	for _, s in ipairs(SITES) do
		site(s[1], s[2], s[3])
	end
end

-- ============================================================================
-- v19d: mine-style ground instead of grass: dirt patches, stone slabs,
-- pebbles and a few glowing crystal shards (no grass, no trees).
-- ============================================================================
local function ensureGroundVariant(name: string, texKeyId: string): string?
	if texKeyId == "" then return nil end
	local MaterialService = game:GetService("MaterialService")
	if not MaterialService:FindFirstChild(name) then
		pcall(function()
			local v = Instance.new("MaterialVariant")
			v.Name = name
			v.BaseMaterial = Enum.Material.Slate
			v.ColorMap = "rbxassetid://" .. texKeyId
			v.StudsPerTile = 24
			v.Parent = MaterialService
		end)
	end
	return MaterialService:FindFirstChild(name) and name or nil
end

function WorldBuilder.ApplyMineGround(part: BasePart, stone: boolean?)
	-- v51: the open ground is light-grey cobblestone. It must not look like any block of the
	-- top mine layer: v49's terracotta read as dirt, v50's lawn blended with the Grass blocks.
	part.MaterialVariant = ""
	if stone then
		part.Material = Enum.Material.Slate
		part.Color = Color3.fromRGB(124, 114, 144)
	else
		part.Material = Enum.Material.Cobblestone
		part.Color = Color3.fromRGB(170, 168, 174)
	end
	part.CanCollide = true
end

-- v49: Builds a 3D stepped rock terrace plate with cracked stone fissure lines (Reference 1 style)
-- Lower layer: cool slate-lavender stone; Upper layer: warm terracotta/ochre cracked rock plate.
-- All layers have CanCollide = true so the ground has genuine 3D physical relief!
local function buildSteppedCanyonTerrace(
	folder: Instance,
	rng: Random,
	x: number,
	z: number,
	w: number,
	d: number,
	slateH: number,
	terraH: number,
	yaw: number,
	withUpperStep: boolean
)
	local slateCols = {
		Color3.fromRGB(126, 116, 148),
		Color3.fromRGB(116, 106, 138),
		Color3.fromRGB(134, 124, 154),
	}
	local terraCols = {
		Color3.fromRGB(174, 114, 78),
		Color3.fromRGB(162, 104, 70),
		Color3.fromRGB(184, 124, 86),
		Color3.fromRGB(154, 96, 64),
	}
	local crackSlateCol = Color3.fromRGB(86, 78, 106)
	local crackTerraCol = Color3.fromRGB(112, 68, 44)

	local baseCF = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	local sCol = slateCols[rng:NextInteger(1, #slateCols)]
	local tCol = terraCols[rng:NextInteger(1, #terraCols)]

	-- 1) Cool slate-lavender base ledge (wider footprint so the violet-grey rim is visible around the terracotta plate)
	local slatePlate = makePart(
		"SlateStrataLedge",
		Vector3.new(w + 2.2, slateH, d + 2.2),
		baseCF * CFrame.new(0, slateH * 0.5, 0),
		sCol,
		Enum.Material.Slate,
		folder,
		nil,
		true,
		0
	)
	slatePlate.CanQuery = false

	-- Beveled side shoulder on slate ledge for organic polygonal look
	local slateWing = makePart(
		"SlateStrataWing",
		Vector3.new(w * 0.82, slateH, d * 0.82),
		baseCF * CFrame.new(rng:NextNumber(-0.6, 0.6), slateH * 0.5 - 0.02, rng:NextNumber(-0.6, 0.6)) * CFrame.Angles(0, math.rad(28), 0),
		slateCols[rng:NextInteger(1, #slateCols)],
		Enum.Material.Slate,
		folder,
		nil,
		true,
		0
	)
	slateWing.CanQuery = false

	-- 2) Warm terracotta/ochre upper rock plate stepped on top of the slate-lavender base
	local totalY = slateH + terraH * 0.5
	local terraPlate = makePart(
		"TerracottaRockPlate",
		Vector3.new(w, terraH, d),
		baseCF * CFrame.new(rng:NextNumber(-0.35, 0.35), totalY, rng:NextNumber(-0.35, 0.35)) * CFrame.Angles(0, math.rad(8), 0),
		tCol,
		Enum.Material.Sandstone,
		folder,
		nil,
		true,
		0
	)
	terraPlate.CanQuery = false

	-- 3) 3D cracked rock fissure lines across the terracotta top surface (like Reference 1)
	local topY = slateH + terraH + 0.015
	local crackCount = rng:NextInteger(3, 5)
	for cIdx = 1, crackCount do
		local cLen = rng:NextNumber(math.min(w, d) * 0.35, math.min(w, d) * 0.78)
		local cOffX = rng:NextNumber(-w * 0.26, w * 0.26)
		local cOffZ = rng:NextNumber(-d * 0.26, d * 0.26)
		local cAng = rng:NextNumber(0, math.pi)
		local seam = makePart(
			"CanyonCrackSeam_" .. cIdx,
			Vector3.new(cLen, 0.03, rng:NextNumber(0.10, 0.18)),
			baseCF * CFrame.new(cOffX, topY, cOffZ) * CFrame.Angles(0, cAng, 0),
			crackTerraCol,
			Enum.Material.Slate,
			folder,
			nil,
			false,
			0
		)
		seam.CanQuery = false
		seam.CastShadow = false
		-- Secondary branching crack
		local brLen = cLen * rng:NextNumber(0.35, 0.55)
		local br = makePart(
			"CanyonCrackBranch_" .. cIdx,
			Vector3.new(brLen, 0.03, 0.09),
			baseCF * CFrame.new(cOffX, topY, cOffZ) * CFrame.Angles(0, cAng + math.rad(rng:NextInteger(38, 68)), 0) * CFrame.new(brLen * 0.4, 0, 0),
			crackTerraCol,
			Enum.Material.Slate,
			folder,
			nil,
			false,
			0
		)
		br.CanQuery = false
		br.CastShadow = false
	end

	-- Slate crack seams on the exposed violet-grey rim
	for sIdx = 1, 2 do
		local sideSign = (sIdx == 1) and -1 or 1
		local sCrack = makePart(
			"SlateCrackSeam_" .. sIdx,
			Vector3.new(rng:NextNumber(1.6, 3.0), 0.03, 0.11),
			baseCF * CFrame.new(sideSign * (w * 0.5 + 0.45), slateH + 0.015, rng:NextNumber(-d * 0.3, d * 0.3)) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0),
			crackSlateCol,
			Enum.Material.Slate,
			folder,
			nil,
			false,
			0
		)
		sCrack.CanQuery = false
		sCrack.CastShadow = false
	end

	-- 4) Optional 3rd stepped tier on larger plates so players feel multi-level walkable rock ledges
	if withUpperStep then
		local stepH = rng:NextNumber(0.32, 0.58)
		local sw, sd = w * rng:NextNumber(0.46, 0.64), d * rng:NextNumber(0.46, 0.64)
		local sx = rng:NextNumber(-w * 0.14, w * 0.14)
		local sz = rng:NextNumber(-d * 0.14, d * 0.14)
		local upper = makePart(
			"TerracottaUpperStep",
			Vector3.new(sw, stepH, sd),
			baseCF * CFrame.new(sx, slateH + terraH + stepH * 0.5, sz) * CFrame.Angles(0, math.rad(rng:NextInteger(-18, 18)), 0),
			terraCols[rng:NextInteger(1, #terraCols)],
			Enum.Material.Sandstone,
			folder,
			nil,
			true,
			0
		)
		upper.CanQuery = false
	end
end

function WorldBuilder.BuildGroundDetail(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "GroundDetail"
	folder.Parent = parent
	local rng = Random.new(20261149)
	local B = GameConfig.MAP_BOUNDS

	-- Keep SpawnPad, GravelPath, SELL station, SHOP station, Plaza, Night Merchant & Mine Pit strictly clear!
	local function blocked(x: number, z: number, m: number): boolean
		if math.abs(x) < 11 + m and z > -18 - m and z < 32 + m then return true end -- spawn pad & gravel path
		if math.abs(x) < 19 + m and z > 12 - m and z < 34.5 + m then return true end -- v52: каменная площадь спавна
		if x > -56 - m and x < -8 + m and z > -15 - m and z < 26 + m then return true end -- SELL station & ring
		if x > 8 - m and x < 58 + m and z > -10 - m and z < 25 + m then return true end -- SHOP pavilion & pad
		if math.abs(x) < 46 + m and z > 1 - m and z < 15 + m then return true end -- central plaza crossway
		if z < -13 + m then return true end -- mine pit + rim collar
		if math.abs(x) < 19 + m and z > 34 - m and z < 60 + m then return true end -- night merchant stall
		return false
	end

	local function rnd(): (number, number)
		return rng:NextNumber(B.MinX + 7, B.MaxX - 7), rng:NextNumber(B.MinZ + 7, B.MaxZ - 7)
	end

	-- 1) Base Slate-Lavender & Terracotta Cracked Strata Bands across the open ground (like Reference 1)
	local placedCenters: { Vector3 } = {}
	local function isSpaced(x: number, z: number, minDist: number): boolean
		local pt = Vector3.new(x, 0, z)
		for _, old in ipairs(placedCenters) do
			if (old - pt).Magnitude < minDist then
				return false
			end
		end
		table.insert(placedCenters, pt)
		return true
	end

	-- Curated stepped canyon rock terraces around the plaza, paths, and side canyons
	local presetTerraces = {
		{ -18, 33, 9.5, 8.0, 0.26, 0.34, 0.25, true },
		{  18, 33, 9.5, 8.0, 0.26, 0.34, -0.3, true },
		{ -46, 36, 12.0, 9.5, 0.30, 0.42, 0.4, true },
		{  48, 36, 12.0, 9.5, 0.30, 0.42, -0.35, true },
		{ -24, 56, 11.0, 9.0, 0.32, 0.45, 0.15, true },
		{  24, 56, 11.0, 9.0, 0.32, 0.45, -0.2, true },
		{ -62, 16, 10.0, 8.5, 0.28, 0.38, 0.5, false },
		{  64, 16, 10.0, 8.5, 0.28, 0.38, -0.45, false },
		{ -58, -6, 9.0,  7.0, 0.24, 0.32, 0.2, false },
		{  60, -6, 9.0,  7.0, 0.24, 0.32, -0.2, false },
	}
	for _, t in ipairs(presetTerraces) do
		if not blocked(t[1], t[2], 3.5) then
			isSpaced(t[1], t[2], 8)
			buildSteppedCanyonTerrace(folder, rng, t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
		end
	end

	-- Additional procedural stepped 3D rock terraces (non-overlapping, CanCollide = true)
	local n = 0
	for _ = 1, 500 do
		if n >= 28 then break end
		local x, z = rnd()
		if not blocked(x, z, 5.5) and isSpaced(x, z, 11.5) then
			n += 1
			local w = rng:NextNumber(6.5, 11.5)
			local d = rng:NextNumber(5.5, 10.0)
			local slateH = rng:NextNumber(0.22, 0.36)
			local terraH = rng:NextNumber(0.28, 0.48)
			local yaw = rng:NextNumber(0, math.pi)
			buildSteppedCanyonTerrace(folder, rng, x, z, w, d, slateH, terraH, yaw, (n % 2 == 0))
		end
	end

	-- 2) Medium stepped slate-lavender & terracotta flagstones with CanCollide = true
	local stoneCols = {
		Color3.fromRGB(128, 118, 148),
		Color3.fromRGB(168, 110, 76),
		Color3.fromRGB(152, 98, 66),
		Color3.fromRGB(116, 106, 136),
	}
	n = 0
	for _ = 1, 500 do
		if n >= 42 then break end
		local x, z = rnd()
		if not blocked(x, z, 2.5) and isSpaced(x, z, 5.5) then
			n += 1
			local h = rng:NextNumber(0.25, 0.55)
			local w = rng:NextNumber(2.8, 5.2)
			local d = rng:NextNumber(2.4, 4.6)
			local isSlate = (n % 2 == 0)
			local s = makePart(
				"CanyonStepStone",
				Vector3.new(w, h, d),
				CFrame.new(x, h * 0.5, z) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0),
				stoneCols[rng:NextInteger(1, #stoneCols)],
				isSlate and Enum.Material.Slate or Enum.Material.Sandstone,
				folder,
				nil,
				true,
				0
			)
			s.CanQuery = false
		end
	end

	-- 3) Surface crack seams & warm canyon pebbles (replacing all black pebbles)
	local pebbleCols = {
		Color3.fromRGB(156, 102, 68),
		Color3.fromRGB(124, 114, 142),
		Color3.fromRGB(178, 118, 82),
		Color3.fromRGB(138, 92, 62),
	}
	n = 0
	for _ = 1, 1200 do
		if n >= 130 then break end
		local x, z = rnd()
		if not blocked(x, z, 1.5) then
			n += 1
			local sz = rng:NextNumber(0.6, 1.65)
			local h = sz * rng:NextNumber(0.42, 0.72)
			local r = makePart(
				"CanyonRockChunk",
				Vector3.new(sz, h, sz * rng:NextNumber(0.75, 1.2)),
				CFrame.new(x, h * 0.45, z) * CFrame.Angles(rng:NextNumber(-0.18, 0.18), rng:NextNumber(0, 6.28), rng:NextNumber(-0.18, 0.18)),
				pebbleCols[rng:NextInteger(1, #pebbleCols)],
				(n % 2 == 0) and Enum.Material.Sandstone or Enum.Material.Slate,
				folder,
				nil,
				true,
				0
			)
			r.CanQuery = false
		end
	end

	-- 4) Rare glowing crystal clusters
	local crystalCols = { Color3.fromRGB(70, 190, 255), Color3.fromRGB(200, 90, 255), Color3.fromRGB(255, 200, 60) }
	n = 0
	for _ = 1, 500 do
		if n >= 18 then break end
		local x, z = rnd()
		if not blocked(x, z, 3) then
			n += 1
			local col = crystalCols[rng:NextInteger(1, #crystalCols)]
			for j = 1, 3 do
				local h = rng:NextNumber(0.8, 1.8)
				local c = makePart("CrystalShard", Vector3.new(0.45, h, 0.45),
					CFrame.new(x + (j - 2) * 0.5, h * 0.4, z + rng:NextNumber(-0.3, 0.3)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)),
					col, Enum.Material.Neon, folder, nil, false)
				c.CanQuery = false
			end
		end
	end
end

-- ============================================================================
-- v51: PLAZA GREENERY — a few chunky trees and bushes in round soil beds. There is no
-- grass or flowers on the ground any more: the only grass in the world is the top layer
-- of the mine, so the Grass blocks stand out against the stone plaza.
-- ============================================================================
function WorldBuilder.BuildPlazaGreenery(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "PlazaGreenery"
	folder.Parent = parent
	local rng = Random.new(20265050)
	local B = GameConfig.MAP_BOUNDS

	-- same keep-out zones as BuildGroundDetail
	local function blocked(x: number, z: number, m: number): boolean
		if math.abs(x) < 11 + m and z > -18 - m and z < 32 + m then return true end -- spawn pad & gravel path
		if math.abs(x) < 19 + m and z > 12 - m and z < 34.5 + m then return true end -- v52: каменная площадь спавна
		if x > -56 - m and x < -8 + m and z > -15 - m and z < 26 + m then return true end -- SELL station & ring
		if x > 8 - m and x < 58 + m and z > -10 - m and z < 25 + m then return true end -- SHOP pavilion & pad
		if math.abs(x) < 46 + m and z > 1 - m and z < 15 + m then return true end -- central plaza crossway
		if z < -13 + m then return true end -- mine pit + rim collar
		if math.abs(x) < 19 + m and z > 34 - m and z < 60 + m then return true end -- night merchant stall
		return false
	end
	local function spot(margin: number, edge: number): (number?, number?)
		for _ = 1, 30 do
			local x = rng:NextNumber(B.MinX + edge, B.MaxX - edge)
			local z = rng:NextNumber(B.MinZ + edge, B.MaxZ - edge)
			if not blocked(x, z, margin) then
				return x, z
			end
		end
		return nil, nil
	end
	local function deco(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
		local p = makePart(name, size, cf, color, mat, folder, shape, false)
		p.CanQuery = false
		p.CastShadow = false
		return p
	end

	local greens = { Color3.fromRGB(70, 168, 76), Color3.fromRGB(52, 140, 64), Color3.fromRGB(92, 186, 92) }
	local soilCol = Color3.fromRGB(112, 76, 48)
	local function soilBed(x: number, z: number, diameter: number)
		deco("SoilBed", Vector3.new(0.3, diameter, diameter), CFrame.new(x, 0.15, z) * CFrame.Angles(0, 0, math.rad(90)), soilCol, Enum.Material.Ground, Enum.PartType.Cylinder)
	end

	-- 3) round bushes
	for _ = 1, 16 do
		local x, z = spot(3, 6)
		if x and z then
			local s = rng:NextNumber(2.6, 3.8)
			soilBed(x + s * 0.2, z, s * 1.9)
			deco("Bush", Vector3.new(s, s, s), CFrame.new(x, s * 0.32, z), greens[rng:NextInteger(1, #greens)], Enum.Material.Grass, Enum.PartType.Ball)
			local s2 = s * 0.7
			deco("Bush", Vector3.new(s2, s2, s2), CFrame.new(x + s * 0.45, s2 * 0.34, z + rng:NextNumber(-0.8, 0.8)), greens[rng:NextInteger(1, #greens)], Enum.Material.Grass, Enum.PartType.Ball)
		end
	end

	-- 4) chunky toy trees; only the trunk is solid
	local trunkCol = Color3.fromRGB(134, 88, 50)
	local planted: { Vector3 } = {}
	for _ = 1, 16 do
		local x, z = spot(6, 8)
		if x and z then
			local here = Vector3.new(x, 0, z)
			local tooClose = false
			for _, other in ipairs(planted) do
				if (other - here).Magnitude < 14 then
					tooClose = true
					break
				end
			end
			if not tooClose then
				table.insert(planted, here)
				local h = rng:NextNumber(7, 10)
				soilBed(x, z, 6)
				makePart("TreeTrunk", Vector3.new(1.7, h, 1.7), CFrame.new(x, h * 0.5, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), trunkCol, Enum.Material.Wood, folder, nil, true)
				local crown = rng:NextNumber(7, 9)
				deco("TreeCrown", Vector3.new(crown, crown, crown), CFrame.new(x, h + crown * 0.25, z), greens[2], Enum.Material.Grass, Enum.PartType.Ball)
				deco("TreeCrown", Vector3.new(crown * 0.72, crown * 0.72, crown * 0.72), CFrame.new(x + crown * 0.38, h + crown * 0.05, z + crown * 0.15), greens[1], Enum.Material.Grass, Enum.PartType.Ball)
				deco("TreeCrown", Vector3.new(crown * 0.66, crown * 0.66, crown * 0.66), CFrame.new(x - crown * 0.34, h + crown * 0.12, z - crown * 0.2), greens[3], Enum.Material.Grass, Enum.PartType.Ball)
			end
		end
	end
end

-- ============================================================================
-- v19c: visible cartoon rock cliffs around the (smaller) map + grass cap on top
-- ============================================================================
function WorldBuilder.BuildBoundaryCliffs(parent: Instance)
	local B = GameConfig.MAP_BOUNDS
	local folder = Instance.new("Folder")
	folder.Name = "BoundaryCliffs"
	folder.Parent = parent
	local rng = Random.new(777)
	local H, T = 14, 8
	local rockCols = {
		Color3.fromRGB(118, 108, 128),
		Color3.fromRGB(98, 92, 110),
		Color3.fromRGB(134, 122, 140),
		Color3.fromRGB(110, 100, 104),
	}
	local crystalCols = { Color3.fromRGB(70, 190, 255), Color3.fromRGB(200, 90, 255), Color3.fromRGB(255, 200, 60) }
	local capCol = Color3.fromRGB(142, 136, 150) -- v51: plain rock on top (no grass outside the mine)
	local w = B.MaxX - B.MinX
	local d = B.MaxZ - B.MinZ
	local cx = (B.MaxX + B.MinX) / 2
	local cz = (B.MaxZ + B.MinZ) / 2
	local sides = {
		{ Vector3.new(cx, 0, B.MinZ - T / 2), Vector3.new(w + 2 * T, H, T), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), w },
		{ Vector3.new(cx, 0, B.MaxZ + T / 2), Vector3.new(w + 2 * T, H, T), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), w },
		{ Vector3.new(B.MinX - T / 2, 0, cz), Vector3.new(T, H, d + 2 * T), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), d },
		{ Vector3.new(B.MaxX + T / 2, 0, cz), Vector3.new(T, H, d + 2 * T), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), d },
	}
	for i, s in ipairs(sides) do
		local c: Vector3, size: Vector3, n: Vector3, along: Vector3, len: number = s[1], s[2], s[3], s[4], s[5]
		makePart("CliffWall" .. i, size, c + Vector3.new(0, H / 2 - 1, 0), rockCols[2], Enum.Material.Slate, folder, nil, true, 0)
		makePart("CliffCap" .. i, Vector3.new(size.X + 0.6, 1.2, size.Z + 0.6), c + Vector3.new(0, H - 0.6, 0), capCol, Enum.Material.Slate, folder, nil, true, 0)
		local t = -len / 2
		local k = 0
		while t < len / 2 do
			k += 1
			local sx = rng:NextNumber(5, 9)
			local sy = rng:NextNumber(6, 13)
			local sz = rng:NextNumber(3, 6)
			local face = c + along * t + n * (T / 2)
			local pos = face + n * (sz * 0.25) + Vector3.new(0, sy / 2 - 0.6, 0)
			local cf = CFrame.lookAt(pos, pos + n) * CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.15, 0.15))
			local rock = makePart("CliffRock", Vector3.new(sx, sy, sz), cf, rockCols[rng:NextInteger(1, #rockCols)], Enum.Material.Slate, folder, nil, true, 0)
			rock.CanQuery = false
			if rng:NextNumber() < 0.4 then
				local bs = rng:NextNumber(4, 7)
				makePart("CliffTopBoulder", Vector3.new(bs, bs * 0.8, bs),
					CFrame.new(c + along * t + Vector3.new(0, H + bs * 0.25, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
					rockCols[rng:NextInteger(1, #rockCols)], Enum.Material.Slate, folder, nil, true, 0)
			end
			if k % 5 == 0 then
				local col = crystalCols[rng:NextInteger(1, #crystalCols)]
				for j = 1, 3 do
					local ch = rng:NextNumber(1.4, 2.8)
					local cpos = face + n * (sz * 0.55 + 0.4) + along * ((j - 2) * 0.9) + Vector3.new(0, ch / 2, 0)
					local cr = makePart("CliffCrystal", Vector3.new(0.7, ch, 0.7),
						CFrame.new(cpos) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)),
						col, Enum.Material.Neon, folder, nil, false, 0)
					cr.CanQuery = false
				end
			end
			t += sx * 0.75
		end
	end
end

function WorldBuilder.BuildWorld(
	equipmentManager: any,
	_onBuyPickaxeTier: (Player, number) -> (),
	onClaimCaveChest: ((Player, number, BasePart) -> ())?
)
	for _, name in ipairs({"CyberMinerMap", "MinerWorld", "MineBlocks", "Baseplate"}) do
		local old = Workspace:FindFirstChild(name)
		if old then old:Destroy() end
	end
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("SpawnLocation") then obj:Destroy() end
	end

	table.clear(NightLights)
	table.clear(FlickerLamps)
	WorldBuilder.SetupOpenSky2026()
	SoundManager.EnsureSoundsFolder()

	local worldFolder = Instance.new("Folder", Workspace)
	worldFolder.Name = "MinerWorld"

	local blocksFolder = Instance.new("Folder", Workspace)
	blocksFolder.Name = "MineBlocks"

	-- Невидимые защитные стены по периметру карты + серверная проверка выхода за границы (Пункт №12 ТЗ)
	local MB = GameConfig.MAP_BOUNDS
	local wallH = GameConfig.WALL_HEIGHT
	local mbw, mbd = MB.MaxX - MB.MinX, MB.MaxZ - MB.MinZ
	local mcx, mcz = (MB.MaxX + MB.MinX) / 2, (MB.MaxZ + MB.MinZ) / 2
	makePart("WallN", Vector3.new(mbw + 20, wallH, 4), Vector3.new(mcx, wallH * 0.5, MB.MinZ - 2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, worldFolder, nil, true, 1)
	makePart("WallS", Vector3.new(mbw + 20, wallH, 4), Vector3.new(mcx, wallH * 0.5, MB.MaxZ + 2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, worldFolder, nil, true, 1)
	makePart("WallW", Vector3.new(4, wallH, mbd + 20), Vector3.new(MB.MinX - 2, wallH * 0.5, mcz), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, worldFolder, nil, true, 1)
	makePart("WallE", Vector3.new(4, wallH, mbd + 20), Vector3.new(MB.MaxX + 2, wallH * 0.5, mcz), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, worldFolder, nil, true, 1)

	-- v49: Exact ground slabs around the [-60..60] x [-138..-18] mine pit (zero gaps, zero Z-fighting)
	local canyonCol = Color3.fromRGB(168, 110, 76)
	local lx0, lx1 = MB.MinX - 30, MB.MaxX + 30
	local lz0, lz1 = MB.MinZ - 30, MB.MaxZ + 30
	WorldBuilder.ApplyMineGround(makePart("LawnSouth", Vector3.new(lx1 - lx0, 16, lz1 - (-18)), Vector3.new((lx0 + lx1) / 2, -8, (lz1 + (-18)) / 2), canyonCol, Enum.Material.Sandstone, worldFolder, nil, true, 0))
	WorldBuilder.ApplyMineGround(makePart("LawnNorth", Vector3.new(lx1 - lx0, 16, -138 - lz0), Vector3.new((lx0 + lx1) / 2, -8, (lz0 - 138) / 2), canyonCol, Enum.Material.Sandstone, worldFolder, nil, true, 0))
	WorldBuilder.ApplyMineGround(makePart("LawnWest",  Vector3.new(-60 - lx0, 16, 120), Vector3.new((lx0 - 60) / 2, -8, -78), canyonCol, Enum.Material.Sandstone, worldFolder, nil, true, 0))
	WorldBuilder.ApplyMineGround(makePart("LawnEast",  Vector3.new(lx1 - 60, 16, 120), Vector3.new((lx1 + 60) / 2, -8, -78), canyonCol, Enum.Material.Sandstone, worldFolder, nil, true, 0))

	local paveCol = Color3.fromRGB(165, 172, 182)
	makePart("PavementCross", Vector3.new(84, 0.25, 10), Vector3.new(0, 0.12, 8), paveCol, Enum.Material.Pavement, worldFolder)

	-- v52: каменная площадь спавна из настоящей геометрии (SpawnLocation встроен в камень)
	SpawnPlazaBuilder.Build(worldFolder)

	-- Строим современный Пункт Приёма Руды "$ SELL" (слева) и Неоновый Павильон "🛒 SHOP" (справа)
	local whiteSellPad = WorldBuilder.BuildModernSellMarket(worldFolder, GameConfig.WHITE_SELL_PAD_POS)
	local greenShopPad = WorldBuilder.BuildNeonShopPavilion(worldFolder, GameConfig.GREEN_SHOP_PAD_POS, equipmentManager)

	WorldBuilder.BuildDeepMineArchitecture(worldFolder, onClaimCaveChest)
	WorldBuilder.BuildGravelPath(worldFolder)
	WorldBuilder.BuildMineEntrance(worldFolder)
	WorldBuilder.BuildGroundDetail(worldFolder)
	WorldBuilder.BuildPlazaGreenery(worldFolder)
	WorldBuilder.BuildMineProps(worldFolder)
	WorldBuilder.BuildBoundaryCliffs(worldFolder)
	WorldBuilder.BuildNightMerchant(worldFolder, Vector3.new(0, 0, 46))

	return {
		WorldFolder = worldFolder,
		BlocksFolder = blocksFolder,
		WhiteSellPad = whiteSellPad,
		GreenShopPad = greenShopPad,
	}
end

return WorldBuilder
