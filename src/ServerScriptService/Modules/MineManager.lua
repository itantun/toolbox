--!strict
-- ============================================================================
-- ⛏️ МОДУЛЬ: MineManager (ServerScriptService.Modules.MineManager)
-- Версия: v13.0 — Выполняет Пункты №1, №7, №10 и №12:
-- • Шахта 30×30×30 блоков с жёсткой коллизией (CanCollide = true, Anchored = true,
--   Transparency = 0, CanTouch = false) — нельзя видеть сквозь карту или провалиться!
-- • Каждое утро спавнит от 0 до 3 Утренних залежей руды (по 6–12 блоков в кластере):
--   - тип руды строго соответствует глубине появления;
--   - продаётся в 3 раза дороже (×3) обычной руды той же глубины;
--   - светится золотистым сиянием и искрами, имеет подпись «🌅 Утренняя залежь (×3)»;
--   - исчезает после добычи или при наступлении ночи;
--   - не спавнится на поверхности, внутри игроков или вне досягаемости.
-- • Полная серверная проверка удара, энергии, уровня кирки (1..10) и анти-фарм.
-- ============================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local OreConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("OreConfig"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))
local VFXModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("VFXModule"))

local MineManager = {}

export type VoxelCell = {
	BlockId: string,
	HP: number,
	MaxHP: number,
	Mined: boolean,
	Part: BasePart?,
	Color: Color3,
	IsMorningVein: boolean?,
	Special: string?, -- v50: "Lucky" | "TNT" | "Treasure"
}

local VoxelGrid: { [number]: { [number]: { [number]: VoxelCell } } } = {}
local LevelFolders: { [number]: Folder } = {}
local CurrentBlocksFolder: Folder? = nil
local CurrentClickCallback: ((Player, BasePart) -> ())? = nil
local IsNightClosed: boolean = false
local ActiveMorningVeinCoords: { { Lvl: number, Row: number, Col: number } } = {}

local LastHitTimes: { [number]: number } = {}
local PlayerMiningStats: { [number]: {
	LastLayer: number,
	SameLayerCount: number,
	RecentBreaks: { number },
	LastRootPos: Vector3?,
	LastPosCheckClock: number,
	Combo: number,          -- v50: blocks broken in a row
	LastBreakClock: number,
} } = {}

local rng = Random.new()

local TEXTURE_FACES = {
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
}

-- 4 подземных пещерных кармана внутри шахты 30×30×30
local CAVE_POCKETS = {
	-- v31: сетка 20×20 (блоки 6 studs) — карманы пересчитаны под новую сетку
	{ CenterLvl = 6,  CenterRow = 4,  CenterCol = 16, RadiusLvl = 2, RadiusXZ = 2 },
	{ CenterLvl = 13, CenterRow = 16, CenterCol = 4,  RadiusLvl = 2, RadiusXZ = 2 },
	{ CenterLvl = 20, CenterRow = 5,  CenterCol = 5,  RadiusLvl = 2, RadiusXZ = 2 },
	{ CenterLvl = 27, CenterRow = 15, CenterCol = 15, RadiusLvl = 2, RadiusXZ = 2 },
}

local function isInsideCavePocket(lvl: number, row: number, col: number): boolean
	for _, pocket in ipairs(CAVE_POCKETS) do
		local dl = (lvl - pocket.CenterLvl) / pocket.RadiusLvl
		local dr = (row - pocket.CenterRow) / pocket.RadiusXZ
		local dc = (col - pocket.CenterCol) / pocket.RadiusXZ
		if (dl * dl + dr * dr + dc * dc) <= 1.0 then
			return true
		end
	end
	return false
end

local function pickWeightedOre(lvl: number): string
	local band = GameConfig.GetDepthBand(lvl)
	local totalWeight = 0
	for _, pair in ipairs(band.Weights) do
		totalWeight += pair[2]
	end
	local roll = rng:NextNumber(0, totalWeight)
	local acc = 0
	for _, pair in ipairs(band.Weights) do
		acc += pair[2]
		if roll <= acc then
			return pair[1]
		end
	end
	return band.Weights[1][1]
end

-- Выбирает ценную руду, характерную именно для данной глубины (для Утренней залежи ×3)
local function pickCharacteristicOreForMorningVein(lvl: number): string
	if lvl <= 7 then
		return "Coal"
	elseif lvl <= 12 then
		return "Coal"
	elseif lvl <= 17 then
		return "Iron"
	elseif lvl <= 22 then
		local opts = { "Iron", "Copper", "Tin" }
		return opts[rng:NextInteger(1, #opts)]
	elseif lvl <= 26 then
		local opts = { "Silver", "Gold" }
		return opts[rng:NextInteger(1, #opts)]
	elseif lvl <= 28 then
		local opts = { "Gold", "Amethyst", "Ruby" }
		return opts[rng:NextInteger(1, #opts)]
	else
		local opts = { "Ruby", "Emerald", "Sapphire", "Diamond", "Mithril" }
		return opts[rng:NextInteger(1, #opts)]
	end
end

local function computeCellWorldPos(lvl: number, row: number, col: number): Vector3
	local bw = GameConfig.BLOCK_WIDTH
	local bh = GameConfig.BLOCK_HEIGHT
	return Vector3.new(
		GameConfig.MINE_TOP_ORIGIN.X + (col - 1) * bw,
		GameConfig.MINE_TOP_ORIGIN.Y - (lvl - 1) * bh,
		GameConfig.MINE_TOP_ORIGIN.Z + (row - 1) * bw
	)
end

function MineManager.SetNightClosed(closed: boolean)
	IsNightClosed = closed
end

function MineManager.IsNightClosed(): boolean
	return IsNightClosed
end

-- ============================================================================
-- 1. ДЕКОРИРОВАНИЕ БЛОКА РЕАЛИСТИЧНЫМИ ВКРАПЛЕНИЯМИ И УТРЕННИМ СИЯНИЕМ (×3)
-- ============================================================================
local function decorateRealisticOreBlock(block: Part, bInfo: any, isMorningVein: boolean?)
	local style = bInfo.InclusionStyle or "None"
	if style == "None" and not isMorningVein then return end

	local incFolder = Instance.new("Folder")
	incFolder.Name = "OreInclusions"
	incFolder.Parent = block

	local bw = GameConfig.BLOCK_WIDTH
	local half = bw * 0.5

	if bInfo.UseGreenTileTexture then
		local texId = (bInfo.Id == "Emerald")
			and GameConfig.TEXTURES.UploadedDarkGreenTile
			or GameConfig.TEXTURES.UploadedLightGreenTile
		for _, face in ipairs(TEXTURE_FACES) do
			local tex = Instance.new("Texture")
			tex.Name = "GreenTileMatrixOverlay"
			tex.Face = face
			tex.Texture = texId
			tex.Color3 = (bInfo.Id == "Emerald")
				and GameConfig.TEXTURES.LightGreenTilePalette.Base
				or GameConfig.TEXTURES.DarkGreenTilePalette.Grid
			tex.Transparency = 0.52
			tex.StudsPerTileU = 4
			tex.StudsPerTileV = 4
			tex.Parent = block
		end
	elseif bInfo.UseSubtleTexture or isMorningVein then
		for _, face in ipairs(TEXTURE_FACES) do
			local tex = Instance.new("Texture")
			tex.Name = "RockMatrixStrata"
			tex.Face = face
			tex.Texture = GameConfig.TEXTURES.SubtleOreTexture
			tex.Color3 = isMorningVein and Color3.fromRGB(255, 215, 75) or bInfo.AccentColor
			tex.Transparency = isMorningVein and 0.45 or 0.72
			tex.StudsPerTileU = 4.5
			tex.StudsPerTileV = 4.5
			tex.Parent = block
		end
	end

	local faceNormals = {
		Vector3.new(0, 1, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, -1, 0),
	}

	local count = math.clamp((bInfo.InclusionCount or 4) + (isMorningVein and 3 or 0), 2, 10)
	for i = 1, count do
		local normal = faceNormals[((i - 1) % #faceNormals) + 1]
		local tangent1 = (math.abs(normal.Y) > 0.9) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		local tangent2 = normal:Cross(tangent1)

		local u = (rng:NextNumber() - 0.5) * (bw * 0.62)
		local v = (rng:NextNumber() - 0.5) * (bw * 0.62)
		local surfaceCenter = block.Position + normal * (half - 0.04) + tangent1 * u + tangent2 * v

		local inc = Instance.new("Part")
		inc.Name = "OreVein_" .. i
		inc.Anchored = true
		inc.CanCollide = false
		inc.CanTouch = false
		inc.CanQuery = false
		inc.CastShadow = false
		inc.TopSurface = Enum.SurfaceType.SmoothNoOutlines
		inc.BottomSurface = Enum.SurfaceType.SmoothNoOutlines

		if isMorningVein and (i % 2 == 0) then
			inc.Color = Color3.fromRGB(255, 215, 65)
			inc.Material = Enum.Material.Neon
		else
			local useSecondary = (bInfo.SecondaryAccent ~= nil) and (i % 3 == 0)
			inc.Color = useSecondary and bInfo.SecondaryAccent or bInfo.AccentColor
			inc.Material = bInfo.InclusionMat or Enum.Material.Metal
		end

		if style == "CoalSeams" then
			inc.Size = Vector3.new(1.35, 0.32, 0.45)
			inc.CFrame = CFrame.new(surfaceCenter) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3.14), rng:NextNumber(-0.2, 0.2))
		elseif style == "MetallicFlecks" or style == "GoldNuggets" then
			local s = (style == "GoldNuggets") and rng:NextNumber(0.38, 0.68) or rng:NextNumber(0.45, 0.82)
			inc.Size = Vector3.new(s * 1.2, s * 0.75, s)
			inc.Reflectance = (style == "GoldNuggets") and 0.32 or 0.18
			inc.CFrame = CFrame.new(surfaceCenter) * CFrame.Angles(rng:NextNumber(0, 3.14), rng:NextNumber(0, 3.14), rng:NextNumber(0, 3.14))
		elseif style == "LavaCracks" or style == "VoidCracks" then
			-- светящаяся трещина, лежащая плашмя на грани блока
			inc.Material = Enum.Material.Neon
			inc.Color = (i % 2 == 0) and bInfo.AccentColor or (bInfo.SecondaryAccent or bInfo.AccentColor)
			inc.Reflectance = 0
			local crackLen = rng:NextNumber(1.9, 3.2)
			inc.Size = Vector3.new(crackLen, 0.14, rng:NextNumber(0.2, 0.36))
			local flat = CFrame.fromMatrix(surfaceCenter, tangent1, normal, tangent1:Cross(normal))
			local ang = rng:NextNumber(0, 3.14) + ((i % 2 == 0) and 0.9 or 0)
			inc.CFrame = flat * CFrame.Angles(0, ang, 0)
		elseif style == "IceFrost" then
			-- короткие ледяные зубцы разной высоты
			inc.Material = Enum.Material.Glass
			inc.Color = (i % 2 == 0) and bInfo.AccentColor or (bInfo.SecondaryAccent or bInfo.AccentColor)
			inc.Reflectance = 0.2
			inc.Size = Vector3.new(rng:NextNumber(0.45, 0.8), rng:NextNumber(0.8, 1.5), rng:NextNumber(0.45, 0.8))
			inc.CFrame = CFrame.lookAt(surfaceCenter + normal * 0.35, surfaceCenter + normal * 2 + tangent1 * rng:NextNumber(-0.5, 0.5)) * CFrame.Angles(math.rad(90), 0, 0)
		elseif style == "MalachiteVeins" or style == "SilverVeins" then
			inc.Size = Vector3.new(1.45, 0.28, 0.38)
			inc.Reflectance = (style == "SilverVeins") and 0.35 or 0.20
			inc.CFrame = CFrame.new(surfaceCenter) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 3.14), rng:NextNumber(-0.6, 0.6))
		elseif style == "CrystalClusters" or style == "EmeraldTiles" or style == "MithrilVeins" then
			local len = rng:NextNumber(0.9, 1.6)
			local thick = rng:NextNumber(0.42, 0.7)
			inc.Size = Vector3.new(thick, len, thick)
			inc.Reflectance = 0.25
			inc.Transparency = 0
			local lookAt = surfaceCenter + normal + tangent1 * rng:NextNumber(-0.45, 0.45) + tangent2 * rng:NextNumber(-0.45, 0.45)
			inc.CFrame = CFrame.lookAt(surfaceCenter + normal * (len * 0.22), lookAt) * CFrame.Angles(math.rad(90), 0, 0)
			if style == "EmeraldTiles" and not isMorningVein then
				inc.Color = (i % 2 == 0)
					and GameConfig.TEXTURES.LightGreenTilePalette.Base
					or GameConfig.TEXTURES.DarkGreenTilePalette.Grid
			end
			if style == "CrystalClusters" and (i % 2 == 1) then
				-- парный маленький кристалл рядом: получается «друза», как на референсе
				local twin = inc:Clone()
				twin.Name = "OreVeinTwin_" .. i
				twin.Size = Vector3.new(thick * 0.62, len * 0.62, thick * 0.62)
				twin.CFrame = inc.CFrame * CFrame.new(thick * 1.1, -len * 0.12, 0) * CFrame.Angles(0, rng:NextNumber(0, 3.14), math.rad(rng:NextNumber(-28, 28)))
				twin.Parent = incFolder
			end
		else
			inc.Size = Vector3.new(0.55, 0.35, 0.48)
			inc.CFrame = CFrame.new(surfaceCenter) * CFrame.Angles(0, rng:NextNumber(0, 3.14), 0)
		end

		inc.Parent = incFolder
	end

	-- Особый визуальный эффект Утренней залежи (×3 цена): золотое свечение + искры + бейдж
	if isMorningVein then
		local sp = Instance.new("Sparkles", block)
		sp.Name = "MorningVeinSparkles"
		sp.SparkleColor = Color3.fromRGB(255, 225, 95)

		local bg = Instance.new("BillboardGui", block)
		bg.Name = "MorningVeinTag"
		bg.Size = UDim2.new(0, 165, 0, 32)
		bg.StudsOffset = Vector3.new(0, 2.6, 0)
		bg.AlwaysOnTop = false
		bg.MaxDistance = 28

		local lbl = Instance.new("TextLabel", bg)
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundColor3 = Color3.fromRGB(32, 24, 12)
		lbl.BackgroundTransparency = 0.15
		lbl.Font = Enum.Font.GothamBold
		lbl.TextColor3 = Color3.fromRGB(255, 225, 75)
		lbl.TextScaled = true
		lbl.Text = string.format("🌅 Morning Vein: %s (×3 💰)", bInfo.Name)
		Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
		local st = Instance.new("UIStroke", lbl)
		st.Color = Color3.fromRGB(255, 200, 50)
		st.Thickness = 1.5
	end
end

-- ============================================================================
-- v47: «ЖИВЫЕ» БЛОКИ КАК НА РЕФЕРЕНСЕ — гранёные матовые кристаллы, выпирающие
-- из породы, светящиеся трещины и камешки. Без бликов солнца (Reflectance = 0,
-- никакого стекла). Пульсацию свечения делает клиентский скрипт LiveOreFX.
-- ============================================================================
local LC = Color3.fromRGB
local SL, BS, GR, SA = Enum.Material.Slate, Enum.Material.Basalt, Enum.Material.Ground, Enum.Material.Sand
-- v51: every block type has its own base rock, colour and crystal shape, so each ore can be
-- told apart at a glance (in v50 most ores were the same grey slate with different gems):
--   Stone   rough grey rock with light strata, dark seams and chiselled slabs on top
--   Coal    grey basalt with black coal seams and lumps
--   Iron    warm granite with round rusty nuggets and steel flecks
--   Magma   cracked lava with glowing cracks and embers
--   Ice     pale glacier ice with white icicles
--   Silver  dark blue slate with bright silver veins
--   Gold    teal slate with a gold vein and round golden nuggets
--   Amethyst purple rock with tall crystal spikes
--   Ruby    maroon rock with big round-cut red gems
--   Emerald dark green rock with flat emerald-cut tiles and green cracks
--   Obsidian black rock with thin blue blades
--   Diamond white marble with sparkling cyan diamonds
--   Abyss   black-violet rock with violet cracks and cyan crystals
local MAT = Enum.Material
local LIVE47: { [string]: any } = {
	Grass    = { base = LC(150, 100, 60), mat = GR, grass = LC(92, 204, 62) },
	Dirt     = { base = LC(150, 100, 60), mat = GR, rock = LC(108, 68, 40), rocks = 4, pebble = LC(180, 174, 166), pebbles = 2 },
	Clay     = { base = LC(236, 204, 128), mat = SA, rock = LC(204, 164, 96), rocks = 3 },
	Stone    = { base = LC(126, 132, 146), mat = MAT.Rock, bands = 2, band = LC(164, 170, 184), seams = 2, seam = LC(74, 78, 92),
		topPlates = 2, plate = LC(158, 164, 178) },
	Coal     = { base = LC(92, 92, 102), mat = BS, bands = 2, band = LC(20, 20, 26), bandMin = 0.45, bandMax = 0.8,
		rock = LC(18, 18, 24), rocks = 6, flecks = 3, fleck = LC(160, 166, 186) },
	Iron     = { base = LC(160, 138, 122), mat = MAT.Granite, gem = LC(206, 104, 50), gems = 8, shape = "nugget", gemMat = MAT.CorrodedMetal,
		flecks = 5, fleck = LC(200, 206, 216), fleckMat = MAT.Metal },
	Copper   = { base = LC(78, 46, 40), mat = MAT.CrackedLava, crack = LC(255, 120, 25), cracks = 6, crackWidth = 1.3, embers = 6, ember = LC(255, 196, 70),
		rock = LC(44, 30, 30), rocks = 2, light = LC(255, 140, 40), glow = true },
	Tin      = { base = LC(170, 208, 238), mat = MAT.Glacier, gem = LC(236, 248, 255), gems = 8, shape = "spike",
		flecks = 3, fleck = LC(255, 255, 255), glow = true },
	Silver   = { base = LC(80, 88, 112), mat = SL, crack = LC(234, 240, 250), cracks = 6, crackWidth = 1.6, crackMat = MAT.Metal, crackName = "LiveVein",
		flecks = 6, fleck = LC(226, 232, 244), fleckMat = MAT.Metal },
	Gold     = { base = LC(74, 96, 104), mat = SL, bands = 1, band = LC(255, 204, 60), bandMin = 0.22, bandMax = 0.34, bandMat = MAT.SmoothPlastic,
		gem = LC(255, 198, 40), gems = 7, shape = "nugget", glow = true },
	Amethyst = { base = LC(94, 74, 122), mat = SL, gem = LC(192, 98, 255), gems = 9, shape = "spike", glow = true },
	Ruby     = { base = LC(106, 58, 66), mat = BS, gem = LC(255, 40, 60), gems = 7, glow = true },
	Emerald  = { base = LC(36, 72, 52), mat = BS, gem = LC(60, 240, 110), gems = 7, shape = "tile", crack = LC(60, 255, 90), cracks = 5, glow = true },
	Sapphire = { base = LC(28, 28, 40), mat = BS, gem = LC(76, 132, 255), gems = 9, shape = "shard", glow = true },
	Diamond  = { base = LC(202, 216, 232), mat = MAT.Marble, gem = LC(140, 230, 255), gems = 7, shape = "diamond",
		flecks = 5, fleck = LC(255, 255, 255), fleckMat = MAT.Neon, glow = true },
	Mithril  = { base = LC(30, 20, 50), mat = BS, gem = LC(80, 240, 255), gems = 4, shape = "spike", crack = LC(210, 80, 255), cracks = 6, crackWidth = 1.3, glow = true },
}

local GRASS_FLOWER_COLORS = {
	LC(255, 214, 64), LC(255, 122, 172), LC(255, 255, 255), LC(150, 186, 255), LC(255, 150, 70),
}

local LIVE47_FACES = {
	Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, -1, 0),
}

local function live47Part(folder: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Reflectance = 0
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.TopSurface = Enum.SurfaceType.SmoothNoOutlines
	p.BottomSurface = Enum.SurfaceType.SmoothNoOutlines
	p.Parent = folder
	return p
end

local function live47Shade(c: Color3, k: number): Color3
	if k >= 0 then return c:Lerp(Color3.new(1, 1, 1), k) end
	return c:Lerp(Color3.new(0, 0, 0), -k)
end

-- ============================================================================
-- v50: SURPRISE BLOCKS — Lucky Block (yellow "?"), TNT (red with a white band)
-- and Treasure Chest (wood with gold fittings). See GameConfig.SPECIAL_BLOCKS.
-- ============================================================================
local SIDE_FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
local ALL_FACES = {
	Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left,
	Enum.NormalId.Right, Enum.NormalId.Top, Enum.NormalId.Bottom,
}

local function getSpecialInfo(id: string?): any
	local sb = GameConfig.SPECIAL_BLOCKS
	if id == "Lucky" then
		return sb.Lucky
	elseif id == "TNT" then
		return sb.TNT
	elseif id == "Treasure" then
		return sb.Treasure
	end
	return nil
end

local function specialFaceText(host: BasePart, text: string, faces: { Enum.NormalId }, textColor: Color3, strokeColor: Color3)
	for _, face in ipairs(faces) do
		local sg = Instance.new("SurfaceGui")
		sg.Name = "SpecialFace"
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 24
		sg.LightInfluence = 0.2
		sg.Parent = host

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.Font = Enum.Font.GothamBlack
		lbl.Text = text
		lbl.TextScaled = true
		lbl.TextColor3 = textColor
		lbl.TextStrokeColor3 = strokeColor
		lbl.TextStrokeTransparency = 0
		lbl.Parent = sg
	end
end

-- A horizontal band wrapped around the block; it never pokes into the shaft walls.
local function specialBand(folder: Instance, block: Part, name: string, height: number, yOffset: number, color: Color3, mat: Enum.Material, row: number, col: number): Part
	local N = GameConfig.MINE_GRID_SIZE
	local bw = GameConfig.BLOCK_WIDTH
	local out, inset = 0.07, -0.02
	local exW = (col == 1) and inset or out
	local exE = (col == N) and inset or out
	local exN = (row == 1) and inset or out
	local exS = (row == N) and inset or out
	return live47Part(
		folder,
		name,
		Vector3.new(bw + exW + exE, height, bw + exN + exS),
		CFrame.new(block.Position + Vector3.new((exE - exW) / 2, yOffset, (exS - exN) / 2)),
		color,
		mat
	)
end

local function applySpecialStyle(block: Part, special: any, row: number, col: number)
	local folder = Instance.new("Folder")
	folder.Name = "LiveOre"
	folder.Parent = block

	block.MaterialVariant = ""
	block.Reflectance = 0
	block.Color = special.Color

	local glow = Instance.new("PointLight")
	glow.Name = "LiveGlow"
	glow.Color = special.AccentColor
	glow.Range = 9
	glow.Brightness = 0.9
	glow.Parent = block

	if special.Id == "Lucky" then
		block.Material = Enum.Material.SmoothPlastic
		specialFaceText(block, "?", ALL_FACES, Color3.new(1, 1, 1), LC(214, 120, 10))
		specialBand(folder, block, "LuckyTrimTop", 0.5, GameConfig.BLOCK_HEIGHT / 2 - 0.3, LC(255, 240, 150), Enum.Material.Neon, row, col)
		specialBand(folder, block, "LuckyTrimBottom", 0.5, -GameConfig.BLOCK_HEIGHT / 2 + 0.3, LC(255, 240, 150), Enum.Material.Neon, row, col)
	elseif special.Id == "TNT" then
		block.Material = Enum.Material.SmoothPlastic
		local band = specialBand(folder, block, "TntLabelBand", 2.3, 0, LC(250, 246, 236), Enum.Material.SmoothPlastic, row, col)
		specialFaceText(band, "TNT", SIDE_FACES, LC(30, 26, 26), LC(250, 246, 236))
		specialBand(folder, block, "TntStripeTop", 0.35, 2.1, LC(150, 28, 26), Enum.Material.SmoothPlastic, row, col)
		specialBand(folder, block, "TntStripeBottom", 0.35, -2.1, LC(150, 28, 26), Enum.Material.SmoothPlastic, row, col)
	else -- Treasure
		block.Material = Enum.Material.WoodPlanks
		specialBand(folder, block, "ChestGoldBand", 0.7, 0.9, LC(255, 208, 60), Enum.Material.Metal, row, col)
		specialBand(folder, block, "ChestGoldBase", 0.5, -GameConfig.BLOCK_HEIGHT / 2 + 0.3, LC(214, 164, 40), Enum.Material.Metal, row, col)
		local lock = specialBand(folder, block, "ChestLockGlow", 1.3, -0.2, LC(255, 226, 110), Enum.Material.Neon, row, col)
		local full = lock.Size
		lock.Size = Vector3.new(full.X, 1.3, 1.3)
		local lock2 = lock:Clone()
		lock2.Size = Vector3.new(1.3, 1.3, full.Z)
		lock2.Parent = folder
		local sp = Instance.new("Sparkles")
		sp.Name = "TreasureSparkles"
		sp.SparkleColor = LC(255, 226, 110)
		sp.Parent = block
	end

	pcall(function()
		CollectionService:AddTag(block, "LiveOre47")
	end)
end

local function applyLive47(block: Part, bInfo: any, isMorningVein: boolean?, lvl: number?, row: number?, col: number?)
	local cfg = LIVE47[bInfo.Id]
	if not cfg then return end

	-- v49: remove all old textures and duplicate OreInclusions caps to prevent any Z-fighting
	for _, ch in ipairs(block:GetChildren()) do
		if ch:IsA("Texture") or ch:IsA("Decal") or ch:IsA("SurfaceAppearance") then
			ch:Destroy()
		elseif ch.Name == "OreInclusions" then
			if isMorningVein then
				for _, d in ipairs(ch:GetChildren()) do
					if string.sub(d.Name, 1, 7) ~= "OreVein" then d:Destroy() end
				end
			else
				ch:Destroy()
			end
		end
	end
	block.MaterialVariant = ""
	block.Material = cfg.mat or Enum.Material.Slate
	block.Color = live47Shade(cfg.base, rng:NextNumber(-0.05, 0.05))
	block.Reflectance = 0

	local folder = Instance.new("Folder")
	folder.Name = "LiveOre"
	folder.Parent = block

	local bw = GameConfig.BLOCK_WIDTH
	local bh = GameConfig.BLOCK_HEIGHT
	local pos = block.Position

	-- v50: GRASS — a thick green turf cap that hangs over the brown dirt body, so a Grass
	-- block can never be mistaken for a Dirt block, from above or from the side.
	if cfg.grass then
		local N = GameConfig.MINE_GRID_SIZE
		local green = live47Shade(cfg.grass, rng:NextNumber(-0.04, 0.04))
		-- the turf sticks out a little on every side, except into the shaft walls
		local out, inset = 0.06, -0.02
		local exW = (col == 1) and inset or out -- towards -X
		local exE = (col == N) and inset or out -- towards +X
		local exN = (row == 1) and inset or out -- towards -Z
		local exS = (row == N) and inset or out -- towards +Z
		local capH = 1.5
		local lift = rng:NextNumber(0.03, 0.08) -- uneven tops: neighbouring caps never z-fight
		live47Part(
			folder,
			"GrassCap",
			Vector3.new(bw + exW + exE, capH, bw + exN + exS),
			CFrame.new(pos + Vector3.new((exE - exW) / 2, bh / 2 + lift - capH / 2, (exS - exN) / 2)),
			green,
			Enum.Material.Grass
		)

		-- jagged green fringe hanging below the cap on every open side
		local capBottom = bh / 2 + lift - capH
		local fringeColor = live47Shade(green, -0.12)
		local sides = {
			{ n = Vector3.new(1, 0, 0), wall = (col == N) },
			{ n = Vector3.new(-1, 0, 0), wall = (col == 1) },
			{ n = Vector3.new(0, 0, 1), wall = (row == N) },
			{ n = Vector3.new(0, 0, -1), wall = (row == 1) },
		}
		for _, side in ipairs(sides) do
			if not side.wall then
				local along = Vector3.new(side.n.Z, 0, -side.n.X)
				-- two teeth of different depth per side: jagged, but cheap
				local split = rng:NextNumber(-0.9, 0.9)
				for _, seg in ipairs({ { -bw / 2, split }, { split, bw / 2 } }) do
					local w = seg[2] - seg[1]
					local h = rng:NextNumber(0.3, 1.1)
					local center = pos + side.n * (bw / 2 + 0.02) + along * (seg[1] + w / 2) + Vector3.new(0, capBottom - h / 2 + 0.04, 0)
					local size = (side.n.X ~= 0) and Vector3.new(0.14, h, w) or Vector3.new(w, h, 0.14)
					live47Part(folder, "GrassFringe", size, CFrame.new(center), fringeColor, Enum.Material.Grass)
				end
			end
		end

		-- tufts and flowers only where the top is open to the sky
		if lvl == 1 then
			local topY = bh / 2 + lift
			for _ = 1, rng:NextInteger(1, 2) do
				local h = rng:NextNumber(0.45, 0.9)
				live47Part(
					folder,
					"GrassTuft",
					Vector3.new(0.55, h, 0.14),
					CFrame.new(pos + Vector3.new(rng:NextNumber(-2.3, 2.3), topY + h / 2 - 0.05, rng:NextNumber(-2.3, 2.3)))
						* CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)),
					live47Shade(cfg.grass, rng:NextNumber(0.1, 0.24)),
					Enum.Material.Grass
				)
			end
			if rng:NextNumber() < 0.25 then
				local fx, fz = rng:NextNumber(-2.2, 2.2), rng:NextNumber(-2.2, 2.2)
				local stemH = rng:NextNumber(0.6, 0.95)
				local petal = GRASS_FLOWER_COLORS[rng:NextInteger(1, #GRASS_FLOWER_COLORS)]
				live47Part(folder, "FlowerStem", Vector3.new(0.12, stemH, 0.12), CFrame.new(pos + Vector3.new(fx, topY + stemH / 2 - 0.05, fz)), LC(58, 150, 46))
				local head = live47Part(folder, "FlowerHead", Vector3.new(0.6, 0.6, 0.6), CFrame.new(pos + Vector3.new(fx, topY + stemH + 0.12, fz)), petal)
				head.Shape = Enum.PartType.Ball
				local heart = live47Part(folder, "FlowerHeart", Vector3.new(0.3, 0.3, 0.3), CFrame.new(pos + Vector3.new(fx, topY + stemH + 0.34, fz)), LC(255, 196, 40))
				heart.Shape = Enum.PartType.Ball
			end
		end
		return
	end

	if not (cfg.gems or cfg.rocks or cfg.cracks or cfg.bands or cfg.flecks or cfg.embers) then return end

	-- v49: Filter out faces that touch the outer shaft walls (row=1, row=N, col=1, col=N)
	-- so no rock or crystal ever pokes into MineWallN/S/W/E and causes black glitching blocks!
	local N = GameConfig.MINE_GRID_SIZE
	local allowedFaces: { Vector3 } = {}
	for _, fn in ipairs(LIVE47_FACES) do
		local blockedByWall = (row == 1 and fn.Z < -0.5)
			or (row == N and fn.Z > 0.5)
			or (col == 1 and fn.X < -0.5)
			or (col == N and fn.X > 0.5)
		if not blockedByWall then
			table.insert(allowedFaces, fn)
		end
	end
	if #allowedFaces == 0 then
		allowedFaces = { Vector3.new(0, 1, 0) }
	end

	local function ext(t: Vector3): number
		return (math.abs(t.Y) > 0.9) and bh or bw
	end
	local function faceFrame(n: Vector3): (Vector3, Vector3, Vector3)
		local t1 = (math.abs(n.Y) > 0.9) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		local t2 = n:Cross(t1)
		local half = (math.abs(n.Y) > 0.9) and bh / 2 or bw / 2
		return pos + n * half, t1, t2
	end
	local function facePoint(n: Vector3, margin: number): (Vector3, Vector3, Vector3)
		local c, t1, t2 = faceFrame(n)
		local u = rng:NextNumber(-0.5, 0.5) * math.max(0, ext(t1) - margin * 2)
		local w = rng:NextNumber(-0.5, 0.5) * math.max(0, ext(t2) - margin * 2)
		return c + t1 * u + t2 * w, t1, t2
	end
	local fi = rng:NextInteger(0, #allowedFaces - 1)
	local function nextFace(): Vector3
		fi += 1
		return allowedFaces[(fi % #allowedFaces) + 1]
	end
	-- a frame lying on the next face: its +Y axis points out of the block
	local function surfaceCF(margin: number, squareTurn: boolean?): CFrame
		local n = nextFace()
		local surf, t1 = facePoint(n, margin)
		local turn = squareTurn and (rng:NextInteger(0, 1) * math.pi / 2) or rng:NextNumber(0, math.pi)
		return CFrame.fromMatrix(surf, t1, n) * CFrame.Angles(0, turn, 0)
	end
	local function glint(size: Vector3, cf: CFrame, color: Color3, transparency: number)
		if cfg.glow then
			local g = live47Part(folder, "LiveGlint", size, cf, color, Enum.Material.Neon)
			g.Transparency = transparency
		end
	end

	-- 0) stripes running around the four sides: rock strata (stone), coal seams, a gold vein.
	-- One part shows on every side face, which keeps the common blocks cheap.
	local function band(name: string, height: number, yOffset: number, color: Color3, mat: Enum.Material?)
		local out, inset = rng:NextNumber(0.04, 0.09), -0.02 -- uneven depth: neighbouring stripes never z-fight
		local exW = (col == 1) and inset or out
		local exE = (col == N) and inset or out
		local exN = (row == 1) and inset or out
		local exS = (row == N) and inset or out
		live47Part(folder, name, Vector3.new(bw + exW + exE, height, bw + exN + exS),
			CFrame.new(pos + Vector3.new((exE - exW) / 2, yOffset, (exS - exN) / 2)), color, mat)
	end
	local bandCount = cfg.bands or 0
	for i = 1, bandCount do
		local h = rng:NextNumber(cfg.bandMin or 0.8, cfg.bandMax or 1.5)
		local y = ((i - 0.5) / bandCount - 0.5) * bh + rng:NextNumber(-0.5, 0.5)
		y = math.clamp(y, -bh / 2 + h / 2 + 0.15, bh / 2 - h / 2 - 0.15)
		band("LiveBand", h, y, live47Shade(cfg.band, rng:NextNumber(-0.06, 0.08)), cfg.bandMat or Enum.Material.Slate)
	end
	for _ = 1, (cfg.seams or 0) do
		band("LiveSeam", rng:NextNumber(0.1, 0.16), rng:NextNumber(-bh / 2 + 0.6, bh / 2 - 0.6), cfg.seam, Enum.Material.Slate)
	end
	-- chiselled slabs on the top face (the face a miner looks at while digging down)
	for _ = 1, (cfg.topPlates or 0) do
		local w, d = rng:NextNumber(1.6, 2.6), rng:NextNumber(1.2, 2.0)
		local c = pos + Vector3.new(rng:NextNumber(-1.5, 1.5), bh / 2 + 0.04, rng:NextNumber(-1.5, 1.5))
		live47Part(folder, "LivePlate", Vector3.new(w, 0.24, d), CFrame.new(c) * CFrame.Angles(0, rng:NextInteger(0, 1) * math.pi / 2, 0),
			live47Shade(cfg.plate, rng:NextNumber(-0.08, 0.1)), Enum.Material.Slate)
	end

	-- 1) crystals; every ore has its own cut
	local gemCount = (cfg.gems or 0) + ((isMorningVein and cfg.gems) and 2 or 0)
	local shape = cfg.shape or "facet"
	for i = 1, gemCount do
		local big = (i <= 3)
		local s = (big and rng:NextNumber(1.5, 2.1) or rng:NextNumber(0.8, 1.3)) * (cfg.gemScale or 1)
		local baseCF = surfaceCF(s * 0.6)
		local gemCol = live47Shade(cfg.gem, rng:NextNumber(-0.08, 0.08))

		if shape == "spike" then
			-- tall crystal with a pointed tip (ice, amethyst, abyss)
			local len = rng:NextNumber(1.3, 2.1) * (big and 1.25 or 1)
			local th = rng:NextNumber(0.45, 0.75)
			local axis = baseCF * CFrame.Angles(rng:NextNumber(-0.45, 0.45), 0, rng:NextNumber(-0.45, 0.45))
			live47Part(folder, "LiveGem", Vector3.new(th, len, th), axis * CFrame.new(0, len * 0.5 - 0.25, 0) * CFrame.Angles(0, math.pi / 4, 0), gemCol)
			live47Part(folder, "LiveGem", Vector3.new(th * 0.72, th * 0.72, th * 0.72), axis * CFrame.new(0, len - 0.25, 0) * CFrame.Angles(math.rad(-35.26), 0, math.rad(45)), live47Shade(gemCol, 0.25))
			glint(Vector3.new(th * 0.3, len * 0.7, th * 0.3), axis * CFrame.new(0, len * 0.5 - 0.2, 0) * CFrame.Angles(0, math.pi / 4, 0) * CFrame.new(th * 0.42, 0, 0), live47Shade(gemCol, 0.45), 0.55)
		elseif shape == "nugget" then
			-- round nugget with a little satellite (iron, gold)
			local d = s * 0.85
			local nug = live47Part(folder, "LiveGem", Vector3.new(d, d, d), baseCF * CFrame.new(0, d * 0.12, 0), gemCol, cfg.gemMat)
			nug.Shape = Enum.PartType.Ball
			local d2 = d * 0.5
			local sat = live47Part(folder, "LiveGem", Vector3.new(d2, d2, d2), baseCF * CFrame.new(d * 0.55, d2 * 0.1, d * 0.15), live47Shade(gemCol, 0.2), cfg.gemMat)
			sat.Shape = Enum.PartType.Ball
			glint(Vector3.new(d * 0.3, d * 0.3, d * 0.3), baseCF * CFrame.new(-d * 0.12, d * 0.5, -d * 0.1), live47Shade(gemCol, 0.55), 0.4)
		elseif shape == "shard" then
			-- thin leaning blade (obsidian)
			local len = rng:NextNumber(1.5, 2.6)
			local wd = rng:NextNumber(0.6, 1.1)
			local axis = baseCF * CFrame.Angles(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6))
			live47Part(folder, "LiveGem", Vector3.new(wd, len, 0.22), axis * CFrame.new(0, len * 0.5 - 0.3, 0), gemCol)
			glint(Vector3.new(wd * 0.45, len * 0.8, 0.05), axis * CFrame.new(0, len * 0.5 - 0.25, 0.12), live47Shade(gemCol, 0.5), 0.45)
		elseif shape == "tile" then
			-- flat step-cut gem (emerald)
			local w, d = s * 1.15, s * 0.8
			live47Part(folder, "LiveGem", Vector3.new(w, 0.3, d), baseCF * CFrame.new(0, 0.06, 0), live47Shade(gemCol, -0.28))
			live47Part(folder, "LiveGem", Vector3.new(w * 0.72, 0.3, d * 0.66), baseCF * CFrame.new(0, 0.2, 0), gemCol)
			glint(Vector3.new(w * 0.4, 0.05, d * 0.3), baseCF * CFrame.new(0, 0.37, 0), live47Shade(gemCol, 0.5), 0.4)
		elseif shape == "diamond" then
			-- a cube standing on its corner, half sunk into the rock, with a bright core
			local onCorner = CFrame.Angles(math.rad(54.74), 0, math.rad(45))
			local d = s * 0.8
			live47Part(folder, "LiveGem", Vector3.new(d, d, d), baseCF * CFrame.new(0, d * 0.3, 0) * onCorner, gemCol)
			glint(Vector3.new(d * 0.45, d * 0.45, d * 0.45), baseCF * CFrame.new(0, d * 0.82, 0) * onCorner, live47Shade(gemCol, 0.6), 0.3)
		else
			-- big faceted gem, half sunk into the rock (ruby)
			local rot = CFrame.Angles(rng:NextNumber(0.35, 0.75), rng:NextNumber(0, math.pi), rng:NextNumber(0.35, 0.75))
			live47Part(folder, "LiveGem", Vector3.new(s, s * rng:NextNumber(0.8, 1.05), s), baseCF * CFrame.new(0, s * 0.12, 0) * rot, gemCol)
			live47Part(folder, "LiveGem", Vector3.new(s * 0.62, s * 0.62, s * 0.62), baseCF * CFrame.new(0, s * 0.42, 0) * rot * CFrame.Angles(math.pi / 4, 0, math.pi / 4), live47Shade(gemCol, 0.28))
			glint(Vector3.new(s * 0.34, s * 0.34, s * 0.34), baseCF * CFrame.new(0, s * 0.6, 0) * rot * CFrame.Angles(0, math.pi / 4, math.pi / 4), live47Shade(gemCol, 0.5), 0.5)
		end
	end

	-- 2) lumps sticking out (dirt clods, sand, coal, cooled lava)
	for _ = 1, (cfg.rocks or 0) do
		local s = cfg.big and rng:NextNumber(0.9, 1.5) or rng:NextNumber(0.55, 1.05)
		local cf = surfaceCF(s * 0.6) * CFrame.new(0, s * 0.05, 0)
			* CFrame.Angles(rng:NextNumber(0.3, 0.8), rng:NextNumber(0, math.pi), rng:NextNumber(0.3, 0.8))
		live47Part(folder, "LiveRock", Vector3.new(s, s * rng:NextNumber(0.65, 0.95), s * rng:NextNumber(0.8, 1.1)), cf,
			live47Shade(cfg.rock, rng:NextNumber(-0.12, 0.12)), Enum.Material.Slate)
	end
	-- a few small light pebbles (dirt)
	for _ = 1, (cfg.pebbles or 0) do
		local sz = rng:NextNumber(0.3, 0.5)
		local cf = surfaceCF(sz) * CFrame.Angles(rng:NextNumber(0.2, 0.6), 0, rng:NextNumber(0.2, 0.6))
		live47Part(folder, "LivePebble", Vector3.new(sz, sz * 0.7, sz * 0.9), cf, live47Shade(cfg.pebble, rng:NextNumber(-0.08, 0.08)), Enum.Material.Slate)
	end
	-- small bright flecks (steel in iron, glitter in coal and diamond, frost on ice, silver grains)
	for _ = 1, (cfg.flecks or 0) do
		local sz = rng:NextNumber(0.22, 0.4)
		local cf = surfaceCF(sz) * CFrame.Angles(rng:NextNumber(0.4, 1.0), 0, rng:NextNumber(0.4, 1.0))
		live47Part(folder, "LiveFleck", Vector3.new(sz, sz, sz), cf, cfg.fleck, cfg.fleckMat)
	end
	-- glowing embers (magma)
	for _ = 1, (cfg.embers or 0) do
		local sz = rng:NextNumber(0.35, 0.7)
		local e = live47Part(folder, "LiveGlint", Vector3.new(sz, sz, sz), surfaceCF(sz) * CFrame.new(0, sz * 0.1, 0), cfg.ember, Enum.Material.Neon)
		e.Shape = Enum.PartType.Ball
	end

	-- 3) zig-zag cracks: glowing (magma, emerald, abyss) or metal veins (silver)
	for _ = 1, (cfg.cracks or 0) do
		local n = nextFace()
		local center, t1, t2 = faceFrame(n)
		local p0 = facePoint(n, 1.2)
		local dir = t1 * rng:NextNumber(-1, 1) + t2 * rng:NextNumber(-1, 1)
		if dir.Magnitude < 0.1 then dir = t1 end
		dir = dir.Unit
		local lim1, lim2 = ext(t1) / 2 - 0.3, ext(t2) / 2 - 0.3
		for _ = 1, rng:NextInteger(2, 4) do
			local p1 = p0 + dir * rng:NextNumber(0.9, 1.8)
			local rel = p1 - center
			p1 = center + t1 * math.clamp(rel:Dot(t1), -lim1, lim1) + t2 * math.clamp(rel:Dot(t2), -lim2, lim2)
			local d = p1 - p0
			if d.Magnitude > 0.2 then
				local mid = (p0 + p1) / 2 + n * 0.03
				local wdt = rng:NextNumber(0.16, 0.3) * (cfg.crackWidth or 1)
				local c = live47Part(folder, cfg.crackName or "LiveCrack", Vector3.new(wdt, 0.08, d.Magnitude + wdt * 0.6), CFrame.lookAt(mid, mid + d.Unit, n), cfg.crack, cfg.crackMat or Enum.Material.Neon)
				if not cfg.crackMat then c.Transparency = 0.05 end
			end
			p0 = p1
			local ang = rng:NextNumber(-1.0, 1.0)
			dir = (dir * math.cos(ang) + n:Cross(dir) * math.sin(ang)).Unit
		end
	end

	-- 4) soft light + the tag the client uses to make the block pulse (LiveOreFX)
	if cfg.glow then
		if not bInfo.HasGlow then
			local pl = Instance.new("PointLight")
			pl.Name = "LiveGlow"
			pl.Color = cfg.light or cfg.gem or cfg.crack
			pl.Range = 6
			pl.Brightness = 0.5
			pl.Parent = block
		end
		pcall(function()
			CollectionService:AddTag(block, "LiveOre47")
		end)
	end
end

function MineManager.BuildInitialTemplate()
	local N = GameConfig.MINE_GRID_SIZE
	local D = GameConfig.MINE_LEVELS_COUNT
	table.clear(ActiveMorningVeinCoords)

	for lvl = 1, D do
		VoxelGrid[lvl] = {}
		for row = 1, N do
			VoxelGrid[lvl][row] = {}
			for col = 1, N do
				local bId = pickWeightedOre(lvl)
				local bInfo = GameConfig.BLOCK_TYPES[bId] or GameConfig.BLOCK_TYPES.Stone
				local shade = 0.93 + rng:NextNumber() * 0.14
				local c = bInfo.Color
				local finalCol = Color3.new(
					math.clamp(c.R * shade, 0, 1),
					math.clamp(c.G * shade, 0, 1),
					math.clamp(c.B * shade, 0, 1)
				)
				local carved = isInsideCavePocket(lvl, row, col)
				VoxelGrid[lvl][row][col] = {
					BlockId = bId,
					HP = bInfo.HP,
					MaxHP = bInfo.HP,
					Mined = carved,
					Part = nil,
					Color = finalCol,
					IsMorningVein = false,
				}
			end
		end
	end

	-- Геологические рудные жилы по 4–7 блоков
	local veinSeeds = 65
	for _ = 1, veinSeeds do
		local seedLvl = rng:NextInteger(4, D)
		local seedRow = rng:NextInteger(2, N - 1)
		local seedCol = rng:NextInteger(2, N - 1)
		local veinOreId = pickWeightedOre(seedLvl)
		local bInfo = GameConfig.BLOCK_TYPES[veinOreId]
		if bInfo and veinOreId ~= "Stone" and veinOreId ~= "Dirt" and veinOreId ~= "Grass" then
			local veinLength = rng:NextInteger(4, 7)
			local cl, cr, cc = seedLvl, seedRow, seedCol
			for _step = 1, veinLength do
				if VoxelGrid[cl] and VoxelGrid[cl][cr] and VoxelGrid[cl][cr][cc] then
					local cell = VoxelGrid[cl][cr][cc]
					if not cell.Mined then
						cell.BlockId = veinOreId
						cell.HP = bInfo.HP
						cell.MaxHP = bInfo.HP
						cell.Color = bInfo.Color
					end
				end
				cl = math.clamp(cl + rng:NextInteger(-1, 1), bInfo.MinDepth, math.min(D, bInfo.MaxDepth))
				cr = math.clamp(cr + rng:NextInteger(-1, 1), 1, N)
				cc = math.clamp(cc + rng:NextInteger(-1, 1), 1, N)
			end
		end
	end

	-- v50: hide surprise blocks (Lucky / TNT / Treasure) below the grass layer
	local sb = GameConfig.SPECIAL_BLOCKS
	for lvl = sb.MinDepth, D do
		for row = 1, N do
			for col = 1, N do
				local cell = VoxelGrid[lvl][row][col]
				if not cell.Mined then
					local roll = rng:NextNumber()
					local specialId: string? = nil
					if roll < sb.Lucky.Chance then
						specialId = "Lucky"
					elseif roll < sb.Lucky.Chance + sb.TNT.Chance then
						specialId = "TNT"
					elseif roll < sb.Lucky.Chance + sb.TNT.Chance + sb.Treasure.Chance then
						specialId = "Treasure"
					end
					if specialId then
						cell.Special = specialId
						cell.HP = GameConfig.GetSpecialBlockHP(lvl)
						cell.MaxHP = cell.HP
					end
				end
			end
		end
	end
end

local function getOrCreateLevelFolder(blocksFolder: Folder, lvl: number): Folder
	if LevelFolders[lvl] and LevelFolders[lvl].Parent == blocksFolder then
		return LevelFolders[lvl]
	end
	local f = Instance.new("Folder")
	f.Name = "Level_" .. lvl
	f.Parent = blocksFolder
	LevelFolders[lvl] = f
	return f
end

local function isCellExposed(lvl: number, row: number, col: number): boolean
	if lvl <= 1 then return true end -- v50: deeper blocks appear when a neighbour is mined
	local N = GameConfig.MINE_GRID_SIZE
	local D = GameConfig.MINE_LEVELS_COUNT
	if col == N and (lvl % 2 == 1) then return true end

	local neighbors = {
		{ lvl - 1, row, col },
		{ lvl + 1, row, col },
		{ lvl, row - 1, col },
		{ lvl, row + 1, col },
		{ lvl, row, col - 1 },
		{ lvl, row, col + 1 },
	}
	for _, nb in ipairs(neighbors) do
		local nl, nr, nc = nb[1], nb[2], nb[3]
		if nl >= 1 and nl <= D and nr >= 1 and nr <= N and nc >= 1 and nc <= N then
			local nbCell = VoxelGrid[nl] and VoxelGrid[nl][nr] and VoxelGrid[nl][nr][nc]
			if nbCell and nbCell.Mined then
				return true
			end
		end
	end
	return false
end

-- ============================================================================
-- 3. СПАВН БЛОКА С ЖЁСТКОЙ КОЛЛИЗИЕЙ (CanCollide = true, Anchored = true, Transparency = 0)
-- ============================================================================
function MineManager.SpawnBlockIfNeeded(
	blocksFolder: Folder,
	lvl: number,
	row: number,
	col: number,
	animateGrow: boolean,
	onBlockClicked: ((Player, BasePart) -> ())?
): BasePart?
	local cell = VoxelGrid[lvl] and VoxelGrid[lvl][row] and VoxelGrid[lvl][row][col]
	if not cell or cell.Mined or (cell.Part and cell.Part.Parent) then
		return cell and cell.Part or nil
	end

	local folder = getOrCreateLevelFolder(blocksFolder, lvl)
	local bId = cell.BlockId
	local bInfo = GameConfig.BLOCK_TYPES[bId] or GameConfig.BLOCK_TYPES.Stone
	local special = getSpecialInfo(cell.Special)
	local pos = computeCellWorldPos(lvl, row, col)
	local bw = GameConfig.BLOCK_WIDTH
	local bh = GameConfig.BLOCK_HEIGHT
	local fullSize = Vector3.new(bw, bh, bw)

	local block = Instance.new("Part")
	block.Name = string.format("Block_%s_L%d_R%d_C%d", bId, lvl, row, col)
	block.Position = pos
	-- ПУНКТ №12 ТЗ: Все блоки физически плотные, не прозрачные, без провалов!
	block.Anchored = true
	block.CanCollide = true
	block.CanTouch = false
	block.Transparency = 0
	block.Color = cell.Color
	block.Material = bInfo.Mat
	block.TopSurface = Enum.SurfaceType.SmoothNoOutlines
	block.BottomSurface = Enum.SurfaceType.SmoothNoOutlines
	block.LeftSurface = Enum.SurfaceType.SmoothNoOutlines
	block.RightSurface = Enum.SurfaceType.SmoothNoOutlines
	block.FrontSurface = Enum.SurfaceType.SmoothNoOutlines
	block.BackSurface = Enum.SurfaceType.SmoothNoOutlines

	if animateGrow and lvl <= 2 then
		block.Size = Vector3.new(bw * 0.25, 0.25, bw * 0.25)
		TweenService:Create(
			block,
			TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = fullSize }
		):Play()
	else
		block.Size = fullSize
	end

	-- v50: a single styling pass per block (the old stacked texture passes built
	-- and then destroyed dozens of instances for every block)
	if special then
		applySpecialStyle(block, special, row, col)
	else
		if cell.IsMorningVein then
			decorateRealisticOreBlock(block, bInfo, true) -- gold veins, sparkles and the ×3 tag
		end
		applyLive47(block, bInfo, cell.IsMorningVein, lvl, row, col)
	end

	if not special and (bInfo.HasGlow or cell.IsMorningVein) then
		local pl = Instance.new("PointLight", block)
		pl.Color = cell.IsMorningVein and Color3.fromRGB(255, 215, 75) or bInfo.AccentColor
		pl.Range = (bInfo.GlowRange or 6) + (cell.IsMorningVein and 4 or 0)
		pl.Brightness = (bInfo.GlowBrightness or 0.75) + (cell.IsMorningVein and 0.55 or 0)
	end

	local priceMult = cell.IsMorningVein and GameConfig.MORNING_VEINS.SellPriceMultiplier or 1
	block:SetAttribute("IsMineBlock", true)
	block:SetAttribute("BlockId", bId)
	block:SetAttribute("BlockName", cell.IsMorningVein and ("🌅 Morning Vein: " .. bInfo.Name) or bInfo.Name)
	block:SetAttribute("IsMorningVein", cell.IsMorningVein == true)
	block:SetAttribute("HP", cell.HP)
	block:SetAttribute("MaxHP", cell.MaxHP)
	block:SetAttribute("SellPrice", bInfo.SellPrice * priceMult)
	block:SetAttribute("MinPickaxeLevel", bInfo.MinPickaxeLevel or 1)
	block:SetAttribute("TargetMineTimeSec", bInfo.TargetMineTimeSec or "2.5 s")
	block:SetAttribute("EnergyCost", bInfo.EnergyCost or 6)
	block:SetAttribute("XP", cell.IsMorningVein and (bInfo.XP * 2) or bInfo.XP)
	block:SetAttribute("StrengthXP", bInfo.StrengthXP)
	block:SetAttribute("LevelIndex", lvl)
	block:SetAttribute("GridRow", row)
	block:SetAttribute("GridCol", col)
	block:SetAttribute("HitSound", bInfo.HitSound)
	block:SetAttribute("AccentColor", cell.IsMorningVein and Color3.fromRGB(255, 215, 75) or bInfo.AccentColor)
	block:SetAttribute("OriginPos", pos)
	if special then
		block:SetAttribute("Special", special.Id)
		block:SetAttribute("BlockName", special.Name)
		block:SetAttribute("SellPrice", 0)
		block:SetAttribute("MinPickaxeLevel", 1)
		block:SetAttribute("TargetMineTimeSec", "Surprise!")
		block:SetAttribute("EnergyCost", 4)
		block:SetAttribute("XP", 10 + lvl * 2)
		block:SetAttribute("StrengthXP", 4)
		block:SetAttribute("HitSound", special.HitSound)
		block:SetAttribute("AccentColor", special.AccentColor)
	elseif bId == "Grass" and not cell.IsMorningVein then
		block:SetAttribute("AccentColor", LIVE47.Grass.grass) -- green chips and tooltip
	end

	pcall(function()
		CollectionService:AddTag(block, "MineOreBlock")
	end)

	local cd = Instance.new("ClickDetector")
	cd.Name = "BlockClickDetector"
	cd.MaxActivationDistance = GameConfig.MAX_MINE_DISTANCE
	cd.CursorIcon = GameConfig.TEXTURES.CrosshairIcon
	cd.Parent = block
	if onBlockClicked then
		cd.MouseClick:Connect(function(plr: Player)
			onBlockClicked(plr, block)
		end)
	end

	block.Parent = folder
	cell.Part = block
	return block
end

local function revealNeighbors(lvl: number, row: number, col: number)
	if not CurrentBlocksFolder then return end
	local N = GameConfig.MINE_GRID_SIZE
	local D = GameConfig.MINE_LEVELS_COUNT
	local neighbors = {
		{ lvl + 1, row, col },
		{ lvl - 1, row, col },
		{ lvl, row + 1, col },
		{ lvl, row - 1, col },
		{ lvl, row, col + 1 },
		{ lvl, row, col - 1 },
	}
	for _, nb in ipairs(neighbors) do
		local nl, nr, nc = nb[1], nb[2], nb[3]
		if nl >= 1 and nl <= D and nr >= 1 and nr <= N and nc >= 1 and nc <= N then
			MineManager.SpawnBlockIfNeeded(CurrentBlocksFolder, nl, nr, nc, false, CurrentClickCallback)
		end
	end
end

-- ============================================================================
-- 4. УТРЕННИЕ СЛУЧАЙНЫЕ ЗАЛЕЖИ РУДЫ: 0–3 ШТУКИ КАЖДОЕ УТРО, ЦЕНА ×3 (ПУНКТ №7 ТЗ)
-- ============================================================================
local function isSafeFromPlayers(worldPos: Vector3): boolean
	local minClear = GameConfig.MORNING_VEINS.MinPlayerClearanceStuds
	for _, plr in ipairs(Players:GetPlayers()) do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - worldPos).Magnitude < minClear then
			return false
		end
	end
	return true
end

function MineManager.ClearMorningVeinsForNight()
	if not CurrentBlocksFolder then return end
	for _, coord in ipairs(ActiveMorningVeinCoords) do
		local cell = VoxelGrid[coord.Lvl] and VoxelGrid[coord.Lvl][coord.Row] and VoxelGrid[coord.Lvl][coord.Row][coord.Col]
		if cell and cell.IsMorningVein and not cell.Mined then
			cell.IsMorningVein = false
			local bId = pickWeightedOre(coord.Lvl)
			local bInfo = GameConfig.BLOCK_TYPES[bId] or GameConfig.BLOCK_TYPES.Stone
			cell.BlockId = bId
			cell.HP = bInfo.HP
			cell.MaxHP = bInfo.HP
			cell.Color = bInfo.Color
			if cell.Part and cell.Part.Parent then
				cell.Part:Destroy()
				cell.Part = nil
				MineManager.SpawnBlockIfNeeded(CurrentBlocksFolder, coord.Lvl, coord.Row, coord.Col, false, CurrentClickCallback)
			end
		end
	end
	table.clear(ActiveMorningVeinCoords)
end

function MineManager.SpawnMorningVeins(): (number, { string })
	if not CurrentBlocksFolder then return 0, {} end
	MineManager.ClearMorningVeinsForNight()

	local count = rng:NextInteger(GameConfig.MORNING_VEINS.MinCount, GameConfig.MORNING_VEINS.MaxCount)
	if count <= 0 then
		return 0, {}
	end

	local N = GameConfig.MINE_GRID_SIZE
	local descriptions: { string } = {}

	for v = 1, count do
		local depthLvl = rng:NextInteger(GameConfig.MORNING_VEINS.MinSpawnDepth, GameConfig.MORNING_VEINS.MaxSpawnDepth)
		local oreId = pickCharacteristicOreForMorningVein(depthLvl)
		local bInfo = GameConfig.BLOCK_TYPES[oreId] or GameConfig.BLOCK_TYPES.Iron
		local clusterSize = rng:NextInteger(GameConfig.MORNING_VEINS.MinBlocksPerVein, GameConfig.MORNING_VEINS.MaxBlocksPerVein)

		-- Размещаем залежь ближе к открытым слоям или бортам выработки, чтобы игрок мог до неё докопаться
		local curLvl = depthLvl
		local curRow = rng:NextInteger(3, N - 2)
		local curCol = rng:NextInteger(3, N - 2)

		local placedBlocks = 0
		for _step = 1, clusterSize * 2 do
			if placedBlocks >= clusterSize then break end
			local pos = computeCellWorldPos(curLvl, curRow, curCol)
			local cell = VoxelGrid[curLvl] and VoxelGrid[curLvl][curRow] and VoxelGrid[curLvl][curRow][curCol]
			if cell and isSafeFromPlayers(pos) then
				if cell.Part and cell.Part.Parent then
					cell.Part:Destroy()
					cell.Part = nil
				end
				cell.BlockId = oreId
				cell.HP = bInfo.HP
				cell.MaxHP = bInfo.HP
				cell.Mined = false
				cell.Color = bInfo.Color:Lerp(Color3.fromRGB(255, 215, 70), 0.18)
				cell.IsMorningVein = true
				cell.Special = nil
				table.insert(ActiveMorningVeinCoords, { Lvl = curLvl, Row = curRow, Col = curCol })
				MineManager.SpawnBlockIfNeeded(CurrentBlocksFolder, curLvl, curRow, curCol, false, CurrentClickCallback)
				placedBlocks += 1
			end
			curLvl = math.clamp(curLvl + rng:NextInteger(-1, 1), GameConfig.MORNING_VEINS.MinSpawnDepth, GameConfig.MORNING_VEINS.MaxSpawnDepth)
			curRow = math.clamp(curRow + rng:NextInteger(-1, 1), 2, N - 1)
			curCol = math.clamp(curCol + rng:NextInteger(-1, 1), 2, N - 1)
		end

		table.insert(descriptions, string.format("%s (%d m, ×3 💰)", bInfo.Name, depthLvl))
	end

	return count, descriptions
end

function MineManager.InitMine(blocksFolder: Folder, onBlockClicked: ((Player, BasePart) -> ())?)
	CurrentBlocksFolder = blocksFolder
	CurrentClickCallback = onBlockClicked
	MineManager.BuildInitialTemplate()

	local N = GameConfig.MINE_GRID_SIZE
	local D = GameConfig.MINE_LEVELS_COUNT
	for lvl = 1, D do
		local spawnedInLevel = 0
		for row = 1, N do
			for col = 1, N do
				if isCellExposed(lvl, row, col) then
					MineManager.SpawnBlockIfNeeded(blocksFolder, lvl, row, col, false, onBlockClicked)
					spawnedInLevel += 1
				end
			end
		end
		if spawnedInLevel > 0 and lvl % 4 == 0 then
			task.wait()
		end
	end
end

function MineManager.RespawnAllBlocksForNight(blocksFolder: Folder, onBlockClicked: ((Player, BasePart) -> ())?)
	CurrentBlocksFolder = blocksFolder
	CurrentClickCallback = onBlockClicked

	for lvl, folder in pairs(LevelFolders) do
		if folder and folder.Parent then
			folder:Destroy()
		end
		LevelFolders[lvl] = nil
	end

	MineManager.BuildInitialTemplate()

	local N = GameConfig.MINE_GRID_SIZE
	local D = GameConfig.MINE_LEVELS_COUNT
	for lvl = 1, D do
		for row = 1, N do
			for col = 1, N do
				if isCellExposed(lvl, row, col) then
					MineManager.SpawnBlockIfNeeded(blocksFolder, lvl, row, col, lvl <= 2, onBlockClicked)
				end
			end
		end
		if lvl % 5 == 0 then
			task.wait(0.03)
		end
	end
end

-- ============================================================================
-- 5. СЕРВЕРНАЯ ОБРАБОТКА УДАРА ПО БЛОКУ
-- ============================================================================
local function getCell(lvl: number, row: number, col: number): VoxelCell?
	return VoxelGrid[lvl] and VoxelGrid[lvl][row] and VoxelGrid[lvl][row][col]
end

-- v50: prize of a Lucky Block or a Treasure Chest (also paid when TNT blows one up)
local function grantSpecialReward(player: Player, specialId: string, lvl: number, worldPos: Vector3, dataManager: any)
	local sb = GameConfig.SPECIAL_BLOCKS
	local rw = sb.Rewards -- all prizes are measured in "blocks of ore from this depth"
	local pickLvl = dataManager.GetPickaxeTier(player)
	local title, sub = "", ""
	local color = Color3.fromRGB(255, 225, 75)
	local frenzySeconds = 0

	if specialId == "Treasure" then
		local coins = dataManager.GrantCoins(player, GameConfig.GetSpecialCoins(lvl, rng:NextNumber(rw.TreasureMin, rw.TreasureMax), pickLvl), true)
		dataManager.RefillEnergy(player)
		dataManager.AddFunStat(player, "TreasuresFound", 1)
		title, sub = "🧰 Treasure Chest!", string.format("+%d coins and full energy", coins)
		SoundManager.PlayAt("CoinChime", worldPos)
	else
		local roll = rng:NextNumber()
		if roll < 0.45 then
			local coins = dataManager.GrantCoins(player, GameConfig.GetSpecialCoins(lvl, rng:NextNumber(rw.LuckyMin, rw.LuckyMax), pickLvl), true)
			title, sub = "🍀 Lucky Block!", string.format("+%d coins", coins)
		elseif roll < 0.65 then
			local coins = dataManager.GrantCoins(player, GameConfig.GetSpecialCoins(lvl, rw.LuckyWithEnergy, pickLvl), true)
			dataManager.RefillEnergy(player)
			title, sub = "🍀 Lucky Block!", string.format("Full energy and +%d coins", coins)
			color = Color3.fromRGB(120, 235, 255)
		elseif roll < 0.80 then
			-- ore shower: the best of three rolls for this depth that the player's pickaxe can mine
			local oreId: string? = nil
			for _ = 1, 3 do
				local other = pickWeightedOre(lvl)
				local otherInfo = GameConfig.BLOCK_TYPES[other]
				if otherInfo and (otherInfo.MinPickaxeLevel or 1) <= pickLvl
					and (not oreId or otherInfo.SellPrice > GameConfig.BLOCK_TYPES[oreId].SellPrice) then
					oreId = other
				end
			end
			local info = GameConfig.BLOCK_TYPES[oreId or "Stone"] or GameConfig.BLOCK_TYPES.Stone
			local added = 0
			for _ = 1, 3 do
				if dataManager.GetBackpackUsed(player) < dataManager.GetMaxBackpack(player) then
					dataManager.AddResourceToBackpack(player, info.Id, math.max(1, math.floor(info.XP * 0.5)), 1, lvl, false)
					added += 1
				end
			end
			if added > 0 then
				title, sub = "🍀 Lucky Block!", string.format("Ore shower: +%d %s %s", added, info.Icon, info.Name)
			else
				local coins = dataManager.GrantCoins(player, info.SellPrice * 3, true)
				title, sub = "🍀 Lucky Block!", string.format("Backpack full, so +%d coins", coins)
			end
			color = info.AccentColor
		elseif roll < 0.92 then
			frenzySeconds = sb.FrenzySeconds
			player:SetAttribute("FrenzyUntil", os.time() + frenzySeconds)
			title, sub = "🔥 POWER FRENZY!", string.format("×%d pickaxe damage for %d s", sb.FrenzyDamageMultiplier, sb.FrenzySeconds)
			color = Color3.fromRGB(255, 130, 50)
		else
			local coins = dataManager.GrantCoins(player, GameConfig.GetSpecialCoins(lvl, rw.Jackpot, pickLvl), true)
			title, sub = "🎰 JACKPOT!", string.format("+%d coins", coins)
		end
		dataManager.AddFunStat(player, "LuckyOpened", 1)
		SoundManager.PlayAt("LuckyPrize", worldPos)
	end

	VFXModule.PlayPurchaseOrSellBurst(worldPos, color)
	VFXModule.SpawnFloatingText(worldPos + Vector3.new(0, 2.6, 0), title .. " " .. sub, color)
	dataManager.Notify(player, "Special", { Kind = specialId, Title = title, Sub = sub, Color = color, Frenzy = frenzySeconds })
end

-- v50: TNT — breaks every block around it and collects the ore. What does not fit
-- into the backpack is paid out as coins right away. TNT caught in the blast chains.
local function explodeTnt(player: Player, lvl: number, row: number, col: number, dataManager: any, chainDepth: number)
	local radius = GameConfig.SPECIAL_BLOCKS.TNT.BlastRadius
	local pickLvl = dataManager.GetPickaxeTier(player)
	local center = computeCellWorldPos(lvl, row, col)
	local broken: { { number } } = {}
	local chained: { { number } } = {}
	local collected, overflowValue = 0, 0

	for dl = -radius, radius do
		for dr = -radius, radius do
			for dc = -radius, radius do
				local nl, nr, nc = lvl + dl, row + dr, col + dc
				local cell = getCell(nl, nr, nc)
				-- v51: blocks that need a better pickaxe survive the blast (no free deep ore for beginners)
				local tooHard = cell ~= nil and not cell.Special
					and ((GameConfig.BLOCK_TYPES[cell.BlockId] or GameConfig.BLOCK_TYPES.Stone).MinPickaxeLevel or 1) > pickLvl
				if cell and not cell.Mined and not tooHard then
					local specialId = cell.Special
					local wasMorning = cell.IsMorningVein == true
					cell.Mined = true
					cell.IsMorningVein = false
					cell.Special = nil
					if cell.Part then
						cell.Part:Destroy()
						cell.Part = nil
					end
					table.insert(broken, { nl, nr, nc })

					if specialId == "TNT" then
						table.insert(chained, { nl, nr, nc })
					elseif specialId then
						grantSpecialReward(player, specialId, nl, computeCellWorldPos(nl, nr, nc), dataManager)
					else
						local info = GameConfig.BLOCK_TYPES[cell.BlockId] or GameConfig.BLOCK_TYPES.Stone
						if dataManager.GetBackpackUsed(player) < dataManager.GetMaxBackpack(player) then
							dataManager.AddResourceToBackpack(
								player, cell.BlockId,
								math.max(1, math.floor(info.XP * GameConfig.SPECIAL_BLOCKS.TNT.XPShare)), math.max(1, math.floor(info.StrengthXP * GameConfig.SPECIAL_BLOCKS.TNT.XPShare)),
								nl, wasMorning
							)
							collected += 1
						else
							overflowValue += info.SellPrice * (wasMorning and GameConfig.MORNING_VEINS.SellPriceMultiplier or 1)
						end
					end
				end
			end
		end
	end
	for _, c in ipairs(broken) do
		revealNeighbors(c[1], c[2], c[3])
	end

	local overflowCoins = overflowValue > 0 and dataManager.GrantCoins(player, overflowValue * GameConfig.SPECIAL_BLOCKS.TNT.OverflowCoinShare, true) or 0
	dataManager.AddFunStat(player, "TntExploded", 1)

	-- harmless built-in blast effect: no pressure, no broken joints
	local boom = Instance.new("Explosion")
	boom.BlastPressure = 0
	boom.BlastRadius = GameConfig.BLOCK_WIDTH * (radius + 0.5)
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Position = center
	boom.Parent = workspace
	SoundManager.PlayAt("Explosion", center)
	VFXModule.PlayDestroyVFX(center, Color3.fromRGB(226, 52, 44), Color3.fromRGB(255, 170, 60), Enum.Material.Slate)

	local sub = string.format("%d blocks blown up, +%d ore", #broken, collected)
	if overflowCoins > 0 then
		sub ..= string.format(", +%d coins", overflowCoins)
	end
	VFXModule.SpawnFloatingText(center + Vector3.new(0, 3, 0), "💥 BOOM! " .. sub, Color3.fromRGB(255, 150, 60))
	dataManager.Notify(player, "Special", { Kind = "TNT", Title = "💥 KABOOM!", Sub = sub, Color = Color3.fromRGB(255, 130, 50) })

	if chainDepth < 3 then
		for _, c in ipairs(chained) do
			task.delay(0.25, function()
				if player.Parent then
					explodeTnt(player, c[1], c[2], c[3], dataManager, chainDepth + 1)
					dataManager.SyncToClient(player)
				end
			end)
		end
	end
end

function MineManager.HandleMineHit(
	player: Player,
	targetBlock: Instance,
	dataManager: any,
	equipmentManager: any,
	blocksFolder: Folder,
	syncRemote: RemoteEvent
)
	if not targetBlock or not targetBlock:IsA("BasePart") then return end
	if not targetBlock:IsDescendantOf(blocksFolder) then return end
	if not targetBlock:GetAttribute("IsMineBlock") then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then return end

	-- v49 REQUIREMENT 1: Player MUST be inside the Mine Zone to mine blocks!
	local zb = GameConfig.MINE_ZONE_BOUNDS
	local pos = root.Position
	local inMineZone = (char:GetAttribute("InMineZone") == true)
		and (pos.X >= zb.MinX and pos.X <= zb.MaxX and pos.Z >= zb.MinZ and pos.Z <= zb.MaxZ and pos.Y <= zb.TopY)
	if not inMineZone then
		return
	end

	-- v49 REQUIREMENT 2: Player MUST have an active visible Pickaxe in hand!
	local visualPick = char:FindFirstChild("VisualPickaxe")
	local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	local hasPickInHand = visualPick ~= nil
		and (char:GetAttribute("PickaxeHidden") ~= true)
		and (visualPick:GetAttribute("Shown") ~= false)
		and (hand ~= nil and hand:FindFirstChild("PickaxeMotor") ~= nil)
	if not hasPickInHand then
		return
	end

	-- v49 REQUIREMENT 3: Strictly only the first 2 blocks in radius (2 * 6.0 = 12.0 studs)!
	local blockPos = (targetBlock:GetAttribute("OriginPos") :: Vector3) or targetBlock.Position
	local delta = pos - blockPos
	local maxAxial = math.max(math.abs(delta.X), math.abs(delta.Y), math.abs(delta.Z))
	if delta.Magnitude > (GameConfig.MAX_MINE_DISTANCE + 1.5) or maxAxial > (GameConfig.BLOCK_WIDTH * 2.18) then
		return
	end

	-- Если сейчас НОЧЬ и игрок стоит на поверхности — копать закрытую шахту сверху нельзя!
	-- v52: ночью копка строго запрещена на сервере, где бы игрок ни стоял
	if IsNightClosed then
		VFXModule.SpawnFloatingText(
			blockPos,
			"🌙 Шахта закрыта на ночь. Возвращайся утром!",
			Color3.fromRGB(255, 110, 90)
		)
		return
	end

	local now = os.clock()
	local stats = PlayerMiningStats[player.UserId]
	if not stats then
		stats = {
			LastLayer = 1,
			SameLayerCount = 0,
			RecentBreaks = {},
			LastRootPos = root.Position,
			LastPosCheckClock = now,
			Combo = 0,
			LastBreakClock = 0,
		}
		PlayerMiningStats[player.UserId] = stats
	else
		local dt = math.max(0.05, now - stats.LastPosCheckClock)
		if stats.LastRootPos then
			local horizSpeed = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(stats.LastRootPos.X, 0, stats.LastRootPos.Z)).Magnitude / dt
			if horizSpeed > GameConfig.ANTI_FARM.MaxPlayerSpeedStudsPerSec and dt < 1.5 then
				stats.LastRootPos = root.Position
				stats.LastPosCheckClock = now
				return
			end
		end
		stats.LastRootPos = root.Position
		stats.LastPosCheckClock = now
	end

	local lastHit = LastHitTimes[player.UserId] or 0
	if (now - lastHit) < dataManager.GetAttackCooldown(player) * 0.86 then
		return
	end
	LastHitTimes[player.UserId] = now

	-- v50: surprise blocks (Lucky / TNT / Treasure) pay coins, so a full backpack never blocks them
	local specialId = targetBlock:GetAttribute("Special") :: string?
	local special = getSpecialInfo(specialId)

	local bagUsed = dataManager.GetBackpackUsed(player)
	local bagMax = dataManager.GetMaxBackpack(player)
	if not special and bagUsed >= bagMax then
		VFXModule.SpawnFloatingText(
			blockPos,
			string.format("🎒 Backpack full (%d/%d)! Sell ore in the $ SELL zone or buy a bigger backpack!", bagUsed, bagMax),
			Color3.fromRGB(255, 95, 95)
		)
		return
	end

	local levelIndex = (targetBlock:GetAttribute("LevelIndex") :: number) or 1
	local baseEnergyCost = (targetBlock:GetAttribute("EnergyCost") :: number) or GameConfig.ENERGY.BaseSwingCost
	local depthExtra = (levelIndex / GameConfig.MINE_LEVELS_COUNT) * GameConfig.ENERGY.DepthExtraCostMax
	local totalEnergyCost = math.floor((baseEnergyCost + depthExtra * 0.45) * GameConfig.ENERGY.SwingCostMultiplier * 10) / 10

	local hasEnergy, currentEnergy = dataManager.TryConsumeEnergy(player, totalEnergyCost)
	if not hasEnergy then
		VFXModule.SpawnFloatingText(
			blockPos,
			string.format("⚡ Low energy (%d/%d)! Upgrade Energy [K] or rest a moment.", math.floor(currentEnergy), dataManager.GetMaxEnergy(player)),
			Color3.fromRGB(255, 195, 65)
		)
		dataManager.SyncToClient(player, syncRemote)
		return
	end

	local blockId = tostring(targetBlock:GetAttribute("BlockId") or "Stone")
	local pickLvl = dataManager.GetPickaxeTier(player)
	local canMineFull, tierDamageMult, tierWarning = true, 1.0, ""
	if not special then
		canMineFull, tierDamageMult, tierWarning = OreConfig.CanPickaxeMine(pickLvl, blockId)
	end

	local rawDamage, isCrit = dataManager.RollHitDamage(player)
	local effectiveDamage = math.max(1, math.floor(rawDamage * tierDamageMult + 0.5))
	if (tonumber(player:GetAttribute("FrenzyUntil")) or 0) > os.time() then
		effectiveDamage *= GameConfig.SPECIAL_BLOCKS.FrenzyDamageMultiplier -- Lucky Block prize: Power Frenzy
	end

	equipmentManager.BroadcastSwing(player, isCrit)

	if not canMineFull then
		SoundManager.PlayQuietTap("WeakPickaxeClink", blockPos, targetBlock, player)
		VFXModule.SpawnFloatingText(blockPos + Vector3.new(0, 1.8, 0), tierWarning, Color3.fromRGB(255, 110, 85))
	end

	local maxHp = (targetBlock:GetAttribute("MaxHP") :: number) or 20
	local currentHp = (targetBlock:GetAttribute("HP") :: number) or maxHp
	local newHp = math.max(0, currentHp - effectiveDamage) -- v37: HP never goes below 0
	targetBlock:SetAttribute("HP", newHp)

	local row = (targetBlock:GetAttribute("GridRow") :: number) or 1
	local col = (targetBlock:GetAttribute("GridCol") :: number) or 1
	local hitCell = getCell(levelIndex, row, col)
	if hitCell then
		hitCell.HP = newHp
	end

	local hitSoundKey = tostring(targetBlock:GetAttribute("HitSound") or "StoneTap")
	local accentColor = (targetBlock:GetAttribute("AccentColor") :: Color3) or targetBlock.Color
	local mainColor = targetBlock.Color
	local blockMat = targetBlock.Material

	if canMineFull then
		SoundManager.PlayQuietTap(hitSoundKey, blockPos, targetBlock, player)
	end

	if isCrit and canMineFull then
		SoundManager.PlayAt("CritHit", blockPos) -- v35: crit only happens when the Critical skill is upgraded
		VFXModule.SpawnFloatingText(blockPos + Vector3.new(0, 2.5, 0), string.format("🔥 CRIT! -%d", effectiveDamage), Color3.fromRGB(255, 120, 40))
		VFXModule.PlayPurchaseOrSellBurst(blockPos, Color3.fromRGB(255, 140, 40))
	end

	if newHp > 0 then
		VFXModule.UpdateBlockCracks(targetBlock, newHp, maxHp)
		VFXModule.PlayHitShakeAndParticles(targetBlock, accentColor, player)
		local pct = math.clamp(math.floor((1 - newHp / math.max(1, maxHp)) * 100), 1, 99)
		VFXModule.SpawnFloatingText(blockPos + Vector3.new(0, 1.2, 0), string.format("⛏️ Cracked: %d%% (-%d HP)", pct, effectiveDamage), accentColor)
		dataManager.SyncToClient(player, syncRemote)
	else
		local validBreaks = {}
		for _, t in ipairs(stats.RecentBreaks) do
			if (now - t) <= 10.0 then
				table.insert(validBreaks, t)
			end
		end
		table.insert(validBreaks, now)
		stats.RecentBreaks = validBreaks
		-- v37 FIX: раньше здесь был `return` -> блок оставался с 0 HP и не ломался ~10 сек.
		-- Теперь блок ломается ВСЕГДА, а при слишком быстрой добыче просто режется опыт.
		local overRateMult = 1.0
		if #validBreaks > GameConfig.ANTI_FARM.MaxBlocksPerTenSeconds then
			overRateMult = 0.5
		end

		if math.abs(levelIndex - stats.LastLayer) <= 1 then
			stats.SameLayerCount += 1
		else
			stats.LastLayer = levelIndex
			stats.SameLayerCount = 1
		end

		local antiCampMult = 1.0
		if stats.SameLayerCount > GameConfig.ANTI_FARM.SameLayerPenaltyThreshold then
			local excess = stats.SameLayerCount - GameConfig.ANTI_FARM.SameLayerPenaltyThreshold
			antiCampMult = math.max(GameConfig.ANTI_FARM.SameLayerMinMultiplier, 1.0 - excess * 0.025)
		end
		antiCampMult *= overRateMult

		-- v50: COMBO — every block broken within the window keeps the streak alive
		local comboCfg = GameConfig.COMBO
		local combo = ((now - stats.LastBreakClock) <= comboCfg.WindowSeconds) and (stats.Combo + 1) or 1
		stats.Combo = combo
		stats.LastBreakClock = now
		local comboXpMult = 1 + math.min(combo - 1, comboCfg.XPBonusMaxSteps) * comboCfg.XPBonusPerStep

		local isMorningVein = (targetBlock:GetAttribute("IsMorningVein") == true)
		local blockName = tostring(targetBlock:GetAttribute("BlockName") or "Stone")
		local xpAmount = math.max(1, math.floor(((targetBlock:GetAttribute("XP") :: number) or 10) * antiCampMult * comboXpMult))
		local strXpAmount = math.max(1, math.floor(((targetBlock:GetAttribute("StrengthXP") :: number) or 4) * antiCampMult))
		local bInfo = GameConfig.BLOCK_TYPES[blockId] or GameConfig.BLOCK_TYPES.Stone

		if hitCell then
			hitCell.Mined = true
			hitCell.IsMorningVein = false
			hitCell.Special = nil
			hitCell.Part = nil
		end

		targetBlock:Destroy()
		revealNeighbors(levelIndex, row, col)

		SoundManager.PlayQuietCrumble(blockPos)
		VFXModule.PlayDestroyVFX(blockPos, mainColor, accentColor, blockMat)

		if special then
			dataManager.GrantXP(player, xpAmount)
			if special.Id == "TNT" then
				explodeTnt(player, levelIndex, row, col, dataManager, 0)
			else
				grantSpecialReward(player, special.Id, levelIndex, blockPos, dataManager)
			end
		else
			local luckyId = dataManager.AddResourceToBackpack(player, blockId, xpAmount, strXpAmount, levelIndex, isMorningVein)
			local updatedUsed = dataManager.GetBackpackUsed(player)
			bagMax = dataManager.GetMaxBackpack(player)

			local morningNote = isMorningVein and " [Morning Vein ×3 💰]" or ""
			VFXModule.SpawnFloatingText(
				blockPos,
				string.format("%s +1 %s%s (%d/%d 🎒)", bInfo.Icon, blockName, morningNote, updatedUsed, bagMax),
				isMorningVein and Color3.fromRGB(255, 225, 75) or accentColor
			)

			if luckyId then
				local lucky = GameConfig.BLOCK_TYPES[luckyId]
				if lucky then
					VFXModule.SpawnFloatingText(blockPos + Vector3.new(0, 3, 0), string.format("🍀 GEOLOGIST! +1 %s %s", lucky.Icon, lucky.Name), Color3.fromRGB(120, 255, 140))
				end
			end
		end

		-- combo milestone: bonus coins every few blocks, bigger the deeper you dig
		local comboCoins = 0
		if combo % comboCfg.MilestoneEvery == 0 then
			local worth = math.min(combo, comboCfg.CoinsMaxCombo) * comboCfg.CoinsPerComboStep
			local amount = math.floor(GameConfig.GetDepthOreValue(levelIndex, pickLvl) * worth + 0.5)
			if amount > 0 then
				comboCoins = dataManager.GrantCoins(player, amount, true)
				VFXModule.SpawnFloatingText(blockPos + Vector3.new(0, 4.2, 0), string.format("🔥 COMBO ×%d! +%d coins", combo, comboCoins), Color3.fromRGB(255, 150, 50))
			else
				VFXModule.SpawnFloatingText(blockPos + Vector3.new(0, 4.2, 0), string.format("🔥 COMBO ×%d!", combo), Color3.fromRGB(255, 150, 50))
			end
		end
		dataManager.RegisterCombo(player, combo)
		dataManager.Notify(player, "Combo", { Count = combo, Window = comboCfg.WindowSeconds, BonusCoins = comboCoins })

		dataManager.SyncToClient(player, syncRemote)
	end
end

function MineManager.CleanupPlayer(player: Player)
	LastHitTimes[player.UserId] = nil
	PlayerMiningStats[player.UserId] = nil
end

return MineManager
