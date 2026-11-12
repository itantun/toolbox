--!strict
-- ============================================================================
-- 🎒 МОДУЛЬ: BackpackDetailer (ReplicatedStorage.Modules.BackpackDetailer)
-- v52: временная заглушка интерфейса — заменяется полной реализацией.
-- ============================================================================

local BackpackDetailer = {}

export type AddOpts = {
	Push: number?,
	Inflate: boolean?,
	DepthAxis: string?,
	Tint: boolean?,
	FillGlow: boolean?,
	Shape: Enum.PartType?,
	Rounded: boolean?,
	Wedge: boolean?,
	Reflectance: number?,
	Transparency: number?,
}

export type DecorateContext = {
	Model: Model,            -- модель рюкзака (в неё уже добавлены все базовые детали)
	Level: number,           -- уровень рюкзака 1..10
	Scale: number,           -- общий масштаб рюкзака
	Anchored: boolean,       -- true для витрины / ViewportFrame
	OnCharacter: boolean,    -- true, если рюкзак на спине персонажа (детали варятся к торсу)
	Origin: CFrame,          -- мировая система координат рюкзака (CFrame торса или точки витрины)
	Width: number,           -- габарит корпуса по X
	Height: number,          -- габарит корпуса по Y
	Depth: number,           -- габарит корпуса по Z
	CenterY: number,         -- локальный Y центра корпуса
	CenterZ: number,         -- локальный Z центра корпуса
	FrontZ: number,          -- локальный Z внешней (дальней от спины) грани корпуса
	Palette: { [string]: Color3 },
	Add: (name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, opts: AddOpts?) -> BasePart,
}

function BackpackDetailer.Decorate(_ctx: DecorateContext) end

return BackpackDetailer
