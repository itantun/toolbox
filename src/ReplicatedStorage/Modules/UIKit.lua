--!strict
-- ============================================================================
-- 🎨 МОДУЛЬ: UIKit (ReplicatedStorage.Modules.UIKit) — КЛИЕНТ
-- v52: общий набор для «живого» интерфейса: градиенты, скругления, обводки,
-- диагональный блик, мерцающие «✦», 3D-превью во ViewportFrame с медленным
-- вращением, тосты, конфетти, тряска карточки, звуки. Палитра — GameConfig.UI.
-- Анимации работают только пока окно открыто: вращением управляет Spinner,
-- который подключается к кадрам при Start и отключается при Stop.
-- ============================================================================

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local UI = GameConfig.UI
local UIKit = {}

-- ---------------------------------------------------------------------------
-- Базовые элементы
-- ---------------------------------------------------------------------------
function UIKit.Corner(obj: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or UI.Corner)
	c.Parent = obj
	return c
end

function UIKit.Stroke(obj: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

function UIKit.Gradient(obj: Instance, c0: Color3, c1: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c0, c1)
	g.Rotation = rotation or 90
	g.Parent = obj
	return g
end

function UIKit.Frame(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color or UI.Panel
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

export type LabelProps = {
	Name: string?,
	Text: string?,
	Size: UDim2?,
	Position: UDim2?,
	Font: Enum.Font?,
	Color: Color3?,
	TextSize: number?,
	XAlign: Enum.TextXAlignment?,
	YAlign: Enum.TextYAlignment?,
	Scaled: boolean?,
	Wrapped: boolean?,
	ZIndex: number?,
	Stroke: boolean?,
}

function UIKit.Label(parent: Instance, props: LabelProps): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = props.Name or "Label"
	l.BackgroundTransparency = 1
	l.Size = props.Size or UDim2.fromScale(1, 1)
	l.Position = props.Position or UDim2.new()
	l.Font = props.Font or UI.Font
	l.Text = props.Text or ""
	l.TextColor3 = props.Color or UI.Text
	l.TextSize = props.TextSize or 14
	l.TextScaled = props.Scaled == true
	l.TextWrapped = props.Wrapped == true
	l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Center
	l.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
	l.ZIndex = props.ZIndex or 1
	l.Parent = parent
	if props.Stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = 1.5
		s.Color = Color3.fromRGB(8, 10, 20)
		s.Transparency = 0.25
		s.Parent = l
	end
	return l
end

-- Кнопка с вертикальным градиентом, обводкой и «нажатием» через UIScale
function UIKit.Button(parent: Instance, name: string, text: string, size: UDim2, pos: UDim2, c0: Color3, c1: Color3): (TextButton, UIGradient)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.AutoButtonColor = false
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Font = UI.FontBlack
	b.Text = text
	b.TextSize = 15
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = parent
	UIKit.Corner(b, 10)
	local grad = UIKit.Gradient(b, c0, c1, 90)
	UIKit.Stroke(b, Color3.fromRGB(10, 12, 24), 2, 0.2)
	local ts = Instance.new("UIStroke")
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.Thickness = 1.5
	ts.Color = Color3.fromRGB(10, 12, 24)
	ts.Transparency = 0.3
	ts.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		scale.Scale = 0.94
	end)
	b.MouseButton1Up:Connect(function()
		scale.Scale = 1
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	return b, grad
end

-- ---------------------------------------------------------------------------
-- Адаптивный масштаб (ПК / планшет / телефон)
-- ---------------------------------------------------------------------------
function UIKit.ViewportSize(): Vector2
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

-- Масштабирует окно базового размера так, чтобы оно целиком помещалось на экране
function UIKit.BindScale(scale: UIScale, baseW: number, baseH: number, maxScale: number?): RBXScriptConnection?
	local function apply()
		local vp = UIKit.ViewportSize()
		scale:SetAttribute("Fit", math.clamp(math.min(vp.X / (baseW + 24), vp.Y / (baseH + 24)), 0.35, maxScale or 1.1))
		if scale:GetAttribute("Animating") ~= true then
			scale.Scale = scale:GetAttribute("Fit") :: number
		end
	end
	apply()
	local cam = Workspace.CurrentCamera
	if cam then
		return cam:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Блик и мерцание
-- ---------------------------------------------------------------------------
-- Диагональный блик: белая накладка, у которой видна только узкая полоса градиента.
-- Возвращает градиент; UIKit.PlayShine двигает его смещение слева направо.
function UIKit.AddShine(card: GuiObject, corner: number?, zIndex: number?): UIGradient
	local overlay = Instance.new("Frame")
	overlay.Name = "Shine"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = UI.Shine
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.ZIndex = zIndex or 8
	overlay.Parent = card
	UIKit.Corner(overlay, corner)
	local g = Instance.new("UIGradient")
	g.Rotation = 24
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.40, 1),
		NumberSequenceKeypoint.new(0.50, 0.68),
		NumberSequenceKeypoint.new(0.60, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1, 0)
	g.Parent = overlay
	return g
end

function UIKit.PlayShine(grad: UIGradient, delaySeconds: number?)
	grad.Offset = Vector2.new(-1, 0)
	TweenService:Create(
		grad,
		TweenInfo.new(UI.ShineSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, delaySeconds or 0),
		{ Offset = Vector2.new(1, 0) }
	):Play()
end

-- Мерцающие «✦» в случайных местах карточки. Твины бесконечные — их запускает и
-- останавливает владелец окна (UIKit.StartTwinkles / UIKit.StopTweens).
function UIKit.AddTwinkles(parent: GuiObject, count: number, color: Color3, rng: Random, zIndex: number?): { TextLabel }
	local out: { TextLabel } = {}
	for _ = 1, count do
		local size = rng:NextInteger(10, 18)
		local l = Instance.new("TextLabel")
		l.Name = "Twinkle"
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Size = UDim2.fromOffset(size + 6, size + 6)
		l.Position = UDim2.fromScale(rng:NextNumber(0.08, 0.92), rng:NextNumber(0.06, 0.55))
		l.Font = Enum.Font.GothamBold
		l.Text = "✦"
		l.TextSize = size
		l.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45)
		l.TextTransparency = 1
		l.ZIndex = zIndex or 7
		l:SetAttribute("Delay", rng:NextNumber(0, 1.6))
		l:SetAttribute("Period", rng:NextNumber(0.7, 1.3))
		l.Parent = parent
		table.insert(out, l)
	end
	return out
end

function UIKit.StartTwinkles(labels: { TextLabel }, into: { Tween })
	for _, l in ipairs(labels) do
		if l.Parent then
			l.TextTransparency = 1
			l.Rotation = 0
			local period = (l:GetAttribute("Period") :: number?) or 1
			local delayTime = (l:GetAttribute("Delay") :: number?) or 0
			local tw = TweenService:Create(
				l,
				TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delayTime),
				{ TextTransparency = 0.05, Rotation = 45 }
			)
			tw:Play()
			table.insert(into, tw)
		end
	end
end

function UIKit.StopTweens(tweens: { Tween })
	for _, tw in ipairs(tweens) do
		tw:Cancel()
	end
	table.clear(tweens)
end

-- ---------------------------------------------------------------------------
-- 3D-превью: ViewportFrame + камера, которая медленно облетает модель
-- ---------------------------------------------------------------------------
export type SpinItem = {
	Viewport: ViewportFrame,
	Camera: Camera,
	Center: Vector3,
	Distance: number,
	Height: number,
	Phase: number,
}

function UIKit.Viewport(parent: Instance, name: string, size: UDim2, pos: UDim2): (ViewportFrame, Camera, WorldModel)
	local vp = Instance.new("ViewportFrame")
	vp.Name = name
	vp.Size = size
	vp.Position = pos
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(150, 156, 180)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -1.6, -0.8)
	vp.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.Parent = vp
	vp.CurrentCamera = cam
	local world = Instance.new("WorldModel")
	world.Parent = vp
	return vp, cam, world
end

function UIKit.OrbitCamera(item: SpinItem, angle: number)
	local a = angle + item.Phase
	local eye = item.Center + Vector3.new(math.sin(a) * item.Distance, item.Height, math.cos(a) * item.Distance)
	item.Camera.CFrame = CFrame.lookAt(eye, item.Center)
end

export type Spinner = {
	Add: (item: SpinItem) -> (),
	Remove: (vp: ViewportFrame) -> (),
	Clear: () -> (),
	Start: () -> (),
	Stop: () -> (),
}

-- Spinner вращает камеры всех зарегистрированных превью. clip — прокручиваемая область:
-- превью за её пределами не обновляются (ViewportFrame не перерисовывается зря).
function UIKit.NewSpinner(periodSeconds: number, clip: GuiObject?): Spinner
	local items: { SpinItem } = {}
	local conn: RBXScriptConnection? = nil
	local angle = 0

	local function visible(vp: ViewportFrame): boolean
		if not clip then
			return true
		end
		local top = clip.AbsolutePosition.Y
		local bottom = top + clip.AbsoluteSize.Y
		local y0 = vp.AbsolutePosition.Y
		return (y0 + vp.AbsoluteSize.Y) >= top and y0 <= bottom
	end

	local spinner = {} :: Spinner
	function spinner.Add(item: SpinItem)
		table.insert(items, item)
		UIKit.OrbitCamera(item, angle)
	end
	function spinner.Remove(vp: ViewportFrame)
		for i = #items, 1, -1 do
			if items[i].Viewport == vp then
				table.remove(items, i)
			end
		end
	end
	function spinner.Clear()
		table.clear(items)
	end
	function spinner.Start()
		if conn then
			return
		end
		conn = RunService.Heartbeat:Connect(function(dt: number)
			angle = (angle + dt * (2 * math.pi) / periodSeconds) % (2 * math.pi)
			for _, item in ipairs(items) do
				if item.Viewport.Parent and visible(item.Viewport) then
					UIKit.OrbitCamera(item, angle)
				end
			end
		end)
	end
	function spinner.Stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
	return spinner
end

-- ---------------------------------------------------------------------------
-- Обратная связь: звук, тост, тряска, вспышка, конфетти
-- ---------------------------------------------------------------------------
local SfxCache: { [string]: Sound } = {}

function UIKit.PlaySfx(key: string)
	local cfg = GameConfig.SFX[key]
	if not cfg then
		return
	end
	local cached = SfxCache[key]
	if cached and cached.Parent then
		cached:Play()
		return
	end
	local s = Instance.new("Sound")
	s.Name = "V52Sfx_" .. key
	s.SoundId = cfg.Id
	s.Volume = cfg.Volume
	s.PlaybackSpeed = cfg.Pitch
	s.Parent = SoundService
	SfxCache[key] = s
	s:Play()
end

-- Всплывающая плашка сверху по центру (красная — ошибка, зелёная — успех)
function UIKit.Toast(layer: Instance, text: string, color: Color3)
	local old = layer:FindFirstChild("V52Toast")
	if old then
		old:Destroy()
	end
	local t = Instance.new("Frame")
	t.Name = "V52Toast"
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Size = UDim2.fromOffset(420, 46)
	t.Position = UDim2.new(0.5, 0, 0, -60)
	t.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.55)
	t.BorderSizePixel = 0
	t.ZIndex = 200
	t.Parent = layer
	UIKit.Corner(t, 12)
	UIKit.Stroke(t, color, 2.5)
	local sc = Instance.new("UIScale")
	sc.Scale = math.clamp(UIKit.ViewportSize().X / 520, 0.6, 1)
	sc.Parent = t
	UIKit.Label(t, {
		Text = text,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Font = UI.FontBlack,
		TextSize = 17,
		Scaled = false,
		Wrapped = true,
		ZIndex = 201,
	})
	TweenService:Create(t, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 64),
	}):Play()
	task.delay(UI.ToastSeconds, function()
		if not t.Parent then
			return
		end
		local out = TweenService:Create(t, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -60),
		})
		out:Play()
		out.Completed:Wait()
		t:Destroy()
	end)
end

-- Короткая тряска элемента по горизонтали (элемент не должен управляться UIListLayout / UIGridLayout)
function UIKit.Shake(obj: GuiObject)
	if obj:GetAttribute("Shaking") then
		return
	end
	obj:SetAttribute("Shaking", true)
	local base = obj.Position
	task.spawn(function()
		for _, dx in ipairs({ -9, 8, -6, 5, -3, 0 }) do
			if not obj.Parent then
				return
			end
			TweenService:Create(obj, TweenInfo.new(0.045, Enum.EasingStyle.Quad), {
				Position = base + UDim2.fromOffset(dx, 0),
			}):Play()
			task.wait(0.05)
		end
		obj.Position = base
		obj:SetAttribute("Shaking", nil)
	end)
end

-- Цветная вспышка поверх элемента (зелёная при покупке)
function UIKit.Flash(obj: GuiObject, color: Color3, corner: number?)
	local f = Instance.new("Frame")
	f.Name = "Flash"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 30
	f.Parent = obj
	UIKit.Corner(f, corner)
	local tw = TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	tw:Play()
	tw.Completed:Once(function()
		f:Destroy()
	end)
end

-- Конфетти из искр «✦», разлетающихся из точки экрана (создаются один раз на событие)
function UIKit.Confetti(layer: Instance, center: Vector2, colors: { Color3 }, count: number)
	local rng = Random.new()
	for i = 1, count do
		local l = Instance.new("TextLabel")
		l.Name = "Confetti"
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Size = UDim2.fromOffset(26, 26)
		l.Position = UDim2.fromOffset(center.X, center.Y)
		l.Font = Enum.Font.GothamBold
		l.Text = (i % 3 == 0) and "✧" or "✦"
		l.TextSize = rng:NextInteger(14, 24)
		l.TextColor3 = colors[((i - 1) % #colors) + 1]
		l.ZIndex = 210
		l.Parent = layer
		local a = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(60, 170)
		local tw = TweenService:Create(l, TweenInfo.new(rng:NextNumber(0.5, 0.8), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(center.X + math.cos(a) * dist, center.Y + math.sin(a) * dist + 30),
			TextTransparency = 1,
			Rotation = rng:NextNumber(-180, 180),
		})
		tw:Play()
		tw.Completed:Once(function()
			l:Destroy()
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Форматирование
-- ---------------------------------------------------------------------------
-- 1234567 -> "1 234 567"
function UIKit.FormatCoins(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s
	while true do
		local replaced, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1 %2")
		out = replaced
		if k == 0 then
			break
		end
	end
	return out
end

-- Секунды -> "мм:сс" (pad = true) или "м:сс"
function UIKit.FormatTime(seconds: number, pad: boolean?): string
	local s = math.max(0, math.ceil(seconds - 0.001))
	local m = math.floor(s / 60)
	return string.format(pad and "%02d:%02d" or "%d:%02d", m, s % 60)
end

return UIKit
