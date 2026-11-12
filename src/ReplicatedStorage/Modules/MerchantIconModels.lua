--!strict
-- ============================================================================
-- 🧰 MODULE: MerchantIconModels (ReplicatedStorage.Modules.MerchantIconModels)
-- 3D icons for the Night Merchant cards (ViewportFrame, same idea as OreIconModels):
-- toolbox with a wrench, treasure map, burger with a soda cup, round green potion
-- and a blue shield-shaped potion. Everything is built from Parts, no assets.
-- Models face +Z; the UI sways the camera around the front side.
-- ============================================================================

local PartKit = require(script.Parent:WaitForChild("PartKit"))

local MerchantIconModels = {}

export type CameraInfo = { Center: Vector3, Distance: number, Height: number }

local CAMERAS: { [string]: CameraInfo } = {
	RepairKit = { Center = Vector3.new(0, 0.2, 0), Distance = 9.2, Height = 1.6 },
	TreasureMap = { Center = Vector3.new(0, 0, 0), Distance = 8.4, Height = 0.8 },
	Food = { Center = Vector3.new(0.2, 0.4, 0), Distance = 10.2, Height = 2.4 },
	Potion = { Center = Vector3.new(0, 0.3, 0), Distance = 9.2, Height = 0.9 },
	Shield = { Center = Vector3.new(0, 0.3, 0), Distance = 9.2, Height = 0.9 },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Cylinder whose axis points along X / Y / Z of the model
local function cylX(parent: Instance, name: string, d: number, len: number, pos: Vector3, color: Color3, mat: Enum.Material, tr: number?): Part
	return PartKit.Cylinder(parent, name, d, len, CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, mat, { Transparency = tr })
end
local function cylY(parent: Instance, name: string, d: number, len: number, pos: Vector3, color: Color3, mat: Enum.Material, tr: number?): Part
	return PartKit.Cylinder(parent, name, d, len, CFrame.new(pos), color, mat, { Transparency = tr })
end
local function cylZ(parent: Instance, name: string, d: number, len: number, pos: Vector3, color: Color3, mat: Enum.Material, tr: number?): Part
	return PartKit.Cylinder(parent, name, d, len, CFrame.new(pos) * CFrame.Angles(math.rad(90), 0, 0), color, mat, { Transparency = tr })
end

local function newModel(name: string): (Model, Part)
	local model = Instance.new("Model")
	model.Name = "MerchantIcon_" .. name
	local root = PartKit.Block(model, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1 })
	model.PrimaryPart = root
	return model, root
end

-- ---------------------------------------------------------------------------
local function buildRepairKit(): Model
	local m = newModel("RepairKit")
	local red, redDark, redLight = rgb(226, 44, 48), rgb(150, 24, 36), rgb(255, 104, 96)
	local steel, steelDark = rgb(196, 206, 232), rgb(92, 100, 128)
	local purple = rgb(112, 90, 196)
	local P = Enum.Material.SmoothPlastic

	PartKit.Block(m, "Body", Vector3.new(3.0, 1.5, 1.7), CFrame.new(0, -0.35, 0), red, P)
	PartKit.Block(m, "BodyTrim", Vector3.new(3.04, 0.3, 1.74), CFrame.new(0, -0.95, 0), redDark, P)
	PartKit.Block(m, "Lid", Vector3.new(3.1, 0.56, 1.78), CFrame.new(0, 0.68, 0), redLight, P)
	PartKit.Block(m, "Seam", Vector3.new(3.12, 0.06, 1.8), CFrame.new(0, 0.4, 0), rgb(46, 20, 30), P)
	for _, sx in ipairs({ -1, 1 }) do
		PartKit.Block(m, "SidePlate", Vector3.new(0.1, 1.9, 0.62), CFrame.new(sx * 1.53, -0.1, 0), steel, Enum.Material.Metal)
		cylY(m, "HandlePost", 0.2, 0.5, Vector3.new(sx * 0.72, 1.2, 0), purple, P)
	end
	cylX(m, "HandleBar", 0.24, 1.7, Vector3.new(0, 1.48, 0), purple, P)
	PartKit.Block(m, "Latch", Vector3.new(0.52, 0.5, 0.1), CFrame.new(0, 0.38, 0.9), steel, Enum.Material.Metal)
	PartKit.Ball(m, "LatchHole", 0.14, CFrame.new(0, 0.38, 0.97), steelDark, P)

	-- wrench on the front face
	local ang = math.rad(40)
	local dir = Vector3.new(math.cos(ang), math.sin(ang), 0)
	local c = Vector3.new(0, -0.4, 0.93)
	PartKit.Block(m, "WrenchHandle", Vector3.new(1.75, 0.26, 0.1), CFrame.new(c) * CFrame.Angles(0, 0, ang), steel, Enum.Material.Metal)
	local head = c + dir * 0.95
	cylZ(m, "WrenchHead", 0.78, 0.12, head, steel, Enum.Material.Metal)
	PartKit.Block(m, "WrenchJaw", Vector3.new(0.34, 0.42, 0.14), CFrame.new(head + dir * 0.3) * CFrame.Angles(0, 0, ang), rgb(120, 22, 36), P)
	local tail = c - dir * 0.95
	cylZ(m, "WrenchRing", 0.6, 0.12, tail, steel, Enum.Material.Metal)
	cylZ(m, "WrenchHole", 0.26, 0.14, tail, redDark, P)
	return m
end

-- ---------------------------------------------------------------------------
local function buildTreasureMap(): Model
	local m = newModel("TreasureMap")
	local tilt = CFrame.Angles(0, 0, math.rad(-8))
	local parch, parchDark = rgb(240, 216, 160), rgb(186, 142, 86)
	local roll, rollEnd = rgb(218, 180, 122), rgb(140, 92, 50)
	local F = Enum.Material.Fabric

	PartKit.Block(m, "Edge", Vector3.new(2.8, 2.0, 0.05), tilt * CFrame.new(0, 0, -0.03), parchDark, F)
	PartKit.Block(m, "Sheet", Vector3.new(2.7, 1.9, 0.1), tilt, parch, F)
	for _, y in ipairs({ 1.0, -1.0 }) do
		local z = 0.1
		PartKit.Cylinder(m, "Roll", 0.46, 2.9, tilt * CFrame.new(0, y, z) * CFrame.Angles(0, 0, math.rad(90)), roll, F)
		for _, sx in ipairs({ -1, 1 }) do
			PartKit.Cylinder(m, "RollCap", 0.5, 0.08, tilt * CFrame.new(sx * 1.46, y, z) * CFrame.Angles(0, 0, math.rad(90)), rollEnd, F)
			PartKit.Cylinder(m, "RollCore", 0.22, 0.1, tilt * CFrame.new(sx * 1.47, y, z) * CFrame.Angles(0, 0, math.rad(90)), rgb(100, 64, 32), F)
		end
	end
	-- land patches and a dotted trail to the X
	local patches = {
		{ -0.7, 0.25, 0.9, 0.6 }, { 0.2, -0.35, 1.0, 0.55 }, { 0.75, 0.45, 0.6, 0.4 },
	}
	for _, p in ipairs(patches) do
		PartKit.Ellipsoid(m, "Land", Vector3.new(p[3], p[4], 0.03), tilt * CFrame.new(p[1], p[2], 0.06), rgb(206, 170, 108), F)
	end
	local trail = { { -0.9, -0.55 }, { -0.62, -0.38 }, { -0.35, -0.5 }, { -0.1, -0.3 }, { 0.12, -0.05 }, { 0.3, 0.12 }, { 0.46, 0.22 } }
	for _, t in ipairs(trail) do
		PartKit.Ball(m, "Dot", 0.1, tilt * CFrame.new(t[1], t[2], 0.09), rgb(122, 72, 40), F)
	end
	for _, s in ipairs({ -45, 45 }) do
		PartKit.Block(m, "MarkX", Vector3.new(0.82, 0.17, 0.05), tilt * CFrame.new(0.68, 0.32, 0.1) * CFrame.Angles(0, 0, math.rad(s)), rgb(224, 36, 42), Enum.Material.SmoothPlastic)
	end
	return m
end

-- ---------------------------------------------------------------------------
local function buildFood(): Model
	local m = newModel("Food")
	local P = Enum.Material.SmoothPlastic
	local cx = -0.55
	local bun, bunDark = rgb(228, 154, 66), rgb(190, 116, 44)

	cylY(m, "BunBottom", 2.3, 0.45, Vector3.new(cx, -0.9, 0), bun, P)
	cylY(m, "BunBase", 2.34, 0.14, Vector3.new(cx, -1.08, 0), bunDark, P)
	cylY(m, "Patty", 2.4, 0.4, Vector3.new(cx, -0.46, 0), rgb(92, 50, 30), Enum.Material.Slate)
	PartKit.Block(m, "Cheese", Vector3.new(2.5, 0.08, 2.5), CFrame.new(cx, -0.2, 0) * CFrame.Angles(0, math.rad(45), 0), rgb(255, 206, 50), P)
	for i = 0, 3 do
		local a = math.rad(45 + 90 * i)
		PartKit.Block(m, "CheeseDrip", Vector3.new(0.5, 0.34, 0.07), CFrame.new(cx + math.cos(a) * 1.16, -0.34, math.sin(a) * 1.16) * CFrame.Angles(0, -a + math.rad(90), 0), rgb(255, 196, 40), P)
	end
	cylY(m, "Tomato", 2.15, 0.14, Vector3.new(cx, -0.06, 0), rgb(218, 52, 40), P)
	cylY(m, "Lettuce", 2.5, 0.12, Vector3.new(cx, 0.08, 0), rgb(92, 188, 58), P)
	for i = 1, 9 do
		local a = (i / 9) * math.pi * 2
		PartKit.Ellipsoid(m, "LettuceRuffle", Vector3.new(0.66, 0.24, 0.5), CFrame.new(cx + math.cos(a) * 1.2, 0.08, math.sin(a) * 1.2) * CFrame.Angles(0, -a, 0), i % 2 == 0 and rgb(118, 206, 70) or rgb(78, 168, 52), P)
	end
	PartKit.Ellipsoid(m, "BunTop", Vector3.new(2.4, 1.34, 2.4), CFrame.new(cx, 0.68, 0), rgb(232, 156, 58), P)
	local seeds = { { 20, 10 }, { 28, 80 }, { 36, 150 }, { 24, 220 }, { 42, 280 }, { 48, 330 }, { 52, 40 }, { 56, 120 }, { 14, 300 }, { 58, 200 } }
	for _, s in ipairs(seeds) do
		local phi, theta = math.rad(s[1]), math.rad(s[2])
		local pos = Vector3.new(cx + 1.2 * math.sin(phi) * math.cos(theta), 0.68 + 0.67 * math.cos(phi), 1.2 * math.sin(phi) * math.sin(theta))
		PartKit.Ellipsoid(m, "Seed", Vector3.new(0.2, 0.09, 0.12), CFrame.new(pos) * CFrame.Angles(0, -theta, math.rad(s[1] * 0.6)), rgb(255, 238, 196), P)
	end

	-- striped soda cup behind the burger
	local cupX, cupZ = 1.5, -0.55
	local bands = { { 0.9, rgb(214, 40, 48) }, { 0.97, rgb(248, 248, 252) }, { 1.04, rgb(214, 40, 48) }, { 1.11, rgb(248, 248, 252) } }
	for i, b in ipairs(bands) do
		cylY(m, "CupBand", b[1], 0.45, Vector3.new(cupX, -0.62 + (i - 1) * 0.45, cupZ), b[2], P)
	end
	cylY(m, "CupLid", 1.22, 0.12, Vector3.new(cupX, 1.2, cupZ), rgb(190, 30, 40), P)
	PartKit.Ellipsoid(m, "CupDome", Vector3.new(1.0, 0.3, 1.0), CFrame.new(cupX, 1.3, cupZ), rgb(206, 38, 46), P)
	PartKit.Block(m, "Straw", Vector3.new(0.12, 1.3, 0.12), CFrame.new(cupX + 0.18, 1.85, cupZ) * CFrame.Angles(0, 0, math.rad(-18)), rgb(250, 250, 252), P)
	PartKit.Block(m, "StrawBand", Vector3.new(0.13, 0.22, 0.13), CFrame.new(cupX + 0.22, 1.95, cupZ) * CFrame.Angles(0, 0, math.rad(-18)), rgb(214, 40, 48), P)
	return m
end

-- ---------------------------------------------------------------------------
local function addCork(m: Model, y: number)
	cylY(m, "Cork", 0.76, 0.6, Vector3.new(0, y, 0), rgb(168, 116, 66), Enum.Material.Wood)
	cylY(m, "CorkTop", 0.82, 0.1, Vector3.new(0, y + 0.32, 0), rgb(132, 86, 48), Enum.Material.Wood)
end

local function buildPotion(): Model
	local m = newModel("Potion")
	local glass = rgb(110, 228, 120)
	PartKit.Ball(m, "Glass", 2.3, CFrame.new(0, -0.35, 0), glass, Enum.Material.Glass, { Transparency = 0.4, Reflectance = 0.1 })
	PartKit.Ellipsoid(m, "Liquid", Vector3.new(2.0, 1.6, 2.0), CFrame.new(0, -0.58, 0), rgb(70, 255, 60), Enum.Material.Neon, { Transparency = 0.1 })
	cylY(m, "LiquidTop", 1.72, 0.04, Vector3.new(0, 0.1, 0), rgb(176, 255, 120), Enum.Material.Neon)
	cylY(m, "Neck", 0.86, 0.8, Vector3.new(0, 1.05, 0), glass, Enum.Material.Glass, 0.35)
	cylY(m, "Rim", 1.08, 0.16, Vector3.new(0, 1.5, 0), rgb(150, 238, 156), Enum.Material.Glass, 0.15)
	addCork(m, 1.75)
	PartKit.Ellipsoid(m, "Shine", Vector3.new(0.34, 0.7, 0.1), CFrame.new(-0.72, 0.15, 0.98) * CFrame.Angles(0, math.rad(-25), math.rad(18)), rgb(255, 255, 255), Enum.Material.Neon, { Transparency = 0.35 })
	local sparks = { { -1.6, 0.9, 0.2 }, { 1.55, 0.2, 0.3 }, { 1.3, 1.5, 0.0 }, { -1.4, -0.9, 0.4 } }
	for _, s in ipairs(sparks) do
		PartKit.Ball(m, "Spark", 0.14, CFrame.new(s[1], s[2], s[3]), rgb(200, 255, 190), Enum.Material.Neon)
	end
	return m
end

local function buildShield(): Model
	local m = newModel("Shield")
	local blue, bright = rgb(58, 138, 255), rgb(96, 196, 255)
	local G = Enum.Material.Glass
	-- shield silhouette: rectangle + diamond point
	PartKit.Block(m, "ShieldTop", Vector3.new(2.0, 1.3, 0.9), CFrame.new(0, 0.35, 0), blue, G, { Transparency = 0.25 })
	PartKit.Block(m, "ShieldPoint", Vector3.new(1.414, 1.414, 0.9), CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(45)), blue, G, { Transparency = 0.25 })
	for _, sx in ipairs({ -1, 1 }) do
		cylZ(m, "ShieldShoulder", 0.5, 0.9, Vector3.new(sx * 0.88, 0.85, 0), blue, G, 0.25)
	end
	-- glowing emblem on the front
	PartKit.Block(m, "EmblemTop", Vector3.new(1.2, 0.8, 0.1), CFrame.new(0, 0.42, 0.46), bright, Enum.Material.Neon, { Transparency = 0.1 })
	PartKit.Block(m, "EmblemPoint", Vector3.new(0.85, 0.85, 0.1), CFrame.new(0, 0.0, 0.46) * CFrame.Angles(0, 0, math.rad(45)), bright, Enum.Material.Neon, { Transparency = 0.1 })
	PartKit.Block(m, "EmblemBar", Vector3.new(0.14, 1.2, 0.12), CFrame.new(0, 0.28, 0.5), rgb(220, 244, 255), Enum.Material.Neon)
	cylY(m, "Neck", 0.78, 0.7, Vector3.new(0, 1.4, 0), blue, G, 0.3)
	cylY(m, "Rim", 1.0, 0.16, Vector3.new(0, 1.78, 0), rgb(130, 206, 255), G, 0.15)
	addCork(m, 2.02)
	local sparks = { { -1.5, 1.0, 0.2 }, { 1.5, 0.3, 0.3 }, { 1.2, 1.7, 0.0 }, { -1.3, -0.6, 0.4 } }
	for _, s in ipairs(sparks) do
		PartKit.Ball(m, "Spark", 0.14, CFrame.new(s[1], s[2], s[3]), rgb(190, 230, 255), Enum.Material.Neon)
	end
	return m
end

local BUILDERS: { [string]: () -> Model } = {
	RepairKit = buildRepairKit,
	TreasureMap = buildTreasureMap,
	Food = buildFood,
	Potion = buildPotion,
	Shield = buildShield,
}

MerchantIconModels.Ids = { "RepairKit", "TreasureMap", "Food", "Potion", "Shield" }

-- Model centred near the origin, PrimaryPart = invisible Root
function MerchantIconModels.Build(id: string): Model
	local builder = BUILDERS[id]
	if not builder then
		error("MerchantIconModels: unknown icon " .. tostring(id))
	end
	return builder()
end

function MerchantIconModels.Camera(id: string): CameraInfo
	return CAMERAS[id] or CAMERAS.RepairKit
end

return MerchantIconModels
