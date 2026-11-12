--!strict
-- ============================================================================
-- v47: LiveOreFX — «живые» руды. Кристаллы и трещины рядом с игроком мягко
-- пульсируют светом, каждый блок в своём ритме. Работает только на клиенте.
-- ============================================================================
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local TAG = "LiveOre47"
local RADIUS = 70
local MAX_BLOCKS = 120

type LightRec = { L: PointLight, B: number }
type Entry = { Block: BasePart, Phase: number, Speed: number, Lights: { LightRec }, Glints: { BasePart }, Cracks: { BasePart } }

local cache: { [Instance]: Entry } = setmetatable({}, { __mode = "k" }) :: any
local near: { Entry } = {}

local function build(block: BasePart): Entry
	local e: Entry = {
		Block = block,
		Phase = math.random() * math.pi * 2,
		Speed = 1.6 + math.random() * 1.2,
		Lights = {}, Glints = {}, Cracks = {},
	}
	for _, ch in ipairs(block:GetChildren()) do
		if ch:IsA("PointLight") then
			table.insert(e.Lights, { L = ch, B = ch.Brightness })
		end
	end
	local f = block:FindFirstChild("LiveOre")
	if f then
		for _, p in ipairs(f:GetChildren()) do
			if p:IsA("BasePart") then
				if p.Name == "LiveGlint" then
					table.insert(e.Glints, p)
				elseif p.Name == "LiveCrack" then
					table.insert(e.Cracks, p)
				end
			end
		end
	end
	return e
end

local function refresh()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local cp = cam.CFrame.Position
	local list: { Entry } = {}
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") and inst.Parent and (inst.Position - cp).Magnitude < RADIUS then
			local e = cache[inst]
			if not e then
				e = build(inst)
				if #e.Lights + #e.Glints + #e.Cracks > 0 then
					cache[inst] = e
				end
			end
			table.insert(list, e :: Entry)
			if #list >= MAX_BLOCKS then break end
		end
	end
	near = list
end

local acc = 0
RunService.RenderStepped:Connect(function(dt: number)
	acc += dt
	if acc > 0.5 then
		acc = 0
		refresh()
	end
	local t = os.clock()
	for _, e in ipairs(near) do
		if e.Block.Parent then
			local s = (math.sin(t * e.Speed + e.Phase) + 1) / 2
			for _, l in ipairs(e.Lights) do
				l.L.Brightness = l.B * (0.7 + 0.6 * s)
			end
			for _, g in ipairs(e.Glints) do
				g.Transparency = 0.75 - 0.5 * s
			end
			for _, c in ipairs(e.Cracks) do
				c.Transparency = 0.35 - 0.3 * s
			end
		end
	end
end)

refresh()
