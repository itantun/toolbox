#!/usr/bin/env python3
"""v51 -> v52: правки клиентских скриптов (ClientController, ToolAnimator)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patcher  # noqa: E402

# ----------------------------------------------------------------------------
# ToolAnimator: обработчики «начало взмаха» и «момент удара» для эффектов кирки
# ----------------------------------------------------------------------------
p = Patcher("src/ReplicatedStorage/Modules/ToolAnimator.lua")
p.sub(
    "local ToolAnimator = {}\n",
    "local ToolAnimator = {}\n\n"
    "-- v52: внешние обработчики эффектов кирки (ставит PickaxeFX): начало взмаха и момент удара\n"
    "ToolAnimator.OnSwingStart = nil :: ((char: Model, isCrit: boolean) -> ())?\n"
    "ToolAnimator.OnImpact = nil :: ((char: Model) -> ())?\n",
)
p.sub(
    "\tst.ImpactDone = false\n",
    "\tst.ImpactDone = false\n"
    "\tlocal onSwing = ToolAnimator.OnSwingStart\n"
    "\tif onSwing then\n"
    "\t\ttask.spawn(onSwing, st.Char, crit)\n"
    "\tend\n",
)
p.sub(
    "\t\t\tst.ImpactDone = true\n",
    "\t\t\tst.ImpactDone = true\n"
    "\t\t\tlocal onImpact = ToolAnimator.OnImpact\n"
    "\t\t\tif onImpact then\n"
    "\t\t\t\ttask.spawn(onImpact, char)\n"
    "\t\t\tend\n",
)
p.save()

# ----------------------------------------------------------------------------
# ClientController: новые окна магазина и рюкзака, фаза суток из атрибутов,
# плавное освещение, цвет искр удара
# ----------------------------------------------------------------------------
p = Patcher("src/StarterPlayer/StarterPlayerScripts/ClientController.client.lua")
p.sub(
    "ToolAnimator.Start()\n",
    "ToolAnimator.Start()\n"
    'local ClientBus = require(Modules:WaitForChild("ClientBus")) -- v52: шина новых окон (ShopUI / BackpackUI) и эффектов\n',
)

NEW_CLOCK = '''local function updateClockAndDepthText()
	-- v52: время фазы показывает карточка таймера справа внизу (PhaseHud); здесь — только глубина
	local band = GameConfig.GetDepthBand(math.max(1, CurrentDepthBlocks))
	local zoneShort = (CurrentDepthBlocks <= 0) and "Поверхность" or band.ZoneName
	if IsNightMode then
		clockLbl.Text = string.format("Ночь · шахта закрыта · %d/30 м", CurrentDepthBlocks)
		clockLbl.TextColor3 = Color3.fromRGB(255, 145, 125)
		if clockStar then clockStar.Visible = false end
		if clockMoon then clockMoon.Visible = true end
	else
		clockLbl.Text = string.format("День · Глубина: %d/30 м (%s)", CurrentDepthBlocks, zoneShort)
		clockLbl.TextColor3 = Color3.fromRGB(255, 235, 115)
		if clockStar then clockStar.Visible = true end
		if clockMoon then clockMoon.Visible = false end
	end
end

-- v52: фаза суток — из атрибута ReplicatedStorage.Phase (общий серверный цикл NightCycleService)
local function syncPhaseFromServer()
	IsNightMode = ReplicatedStorage:GetAttribute(GameConfig.PHASE.AttrPhase) == "Night"
	updateClockAndDepthText()
end
ReplicatedStorage:GetAttributeChangedSignal(GameConfig.PHASE.AttrPhase):Connect(syncPhaseFromServer)
syncPhaseFromServer()

'''
p.between("local function updateClockAndDepthText()\n", "DayNightEvent.OnClientEvent:Connect(", NEW_CLOCK)

p.sub(
    "local function openShopMenuHere()\n"
    "\tbagModal.Visible = false\n"
    "\tshopModal.Visible = true\n"
    "\tSoundManager.PlayUISound(\"ShopOpen\") -- v28: shop open swoosh\n"
    "\trefreshShopView()\n"
    "end\n",
    "local function openShopMenuHere()\n"
    "\t-- v52: старая карусель больше не показывается — открываем новый магазин (ShopUI)\n"
    "\tbagModal.Visible = false\n"
    "\tshopModal.Visible = false\n"
    "\tClientBus.OpenShop:Fire()\n"
    "end\n",
)
p.sub(
    "\t\tif shopModal.Visible then\n"
    "\t\t\tshopModal.Visible = false\n"
    "\t\telse\n"
    "\t\t\topenShopMenuHere()\n"
    "\t\tend\n",
    "\t\tif ClientBus.IsWindowOpen(\"Shop\") then -- v52\n"
    "\t\t\tClientBus.CloseShop:Fire()\n"
    "\t\telse\n"
    "\t\t\topenShopMenuHere()\n"
    "\t\tend\n",
)
p.sub(
    "\t\tif not shopModal.Visible and isOnShopPad() then\n",
    "\t\tif not ClientBus.IsWindowOpen(\"Shop\") and isOnShopPad() then\n",
)
p.sub(
    "\t\tshopModal.Visible = false\n"
    "\t\tbagModal.Visible = not bagModal.Visible\n"
    "\t\tif bagModal.Visible then rebuildInventorySlots() end\n",
    "\t\tClientBus.ToggleBag:Fire() -- v52: новое окно рюкзака с 3D-иконками руды (BackpackUI)\n",
    count=3,
)
p.sub(
    "\telseif input.KeyCode == Enum.KeyCode.Escape then\n"
    "\t\tshopModal.Visible = false\n"
    "\t\tbagModal.Visible = false\n",
    "\telseif input.KeyCode == Enum.KeyCode.Escape then\n"
    "\t\tshopModal.Visible = false\n"
    "\t\tbagModal.Visible = false\n"
    "\t\tClientBus.CloseAll:Fire() -- v52: Esc закрывает и новые окна\n",
)
p.sub(
    'player:GetAttribute("ProgressionUIOpen") then',
    'player:GetAttribute("ProgressionUIOpen") or player:GetAttribute("UpgradeUIOpen") then',
    count=2,
)
p.sub(
    "\tshakeCamera(0.08)\n",
    "\t-- v52: искры удара красятся в цвет руды, а тряска камеры играет в момент удара (PickaxeFX)\n"
    "\tClientBus.SetLastHit(accentCol)\n",
)
p.between(
    "\t\tif onShopPad and not WasOnShopPad then\n",
    "\t\t-- v14: окно продажи не открывается",
    "\t\t-- v52: магазин открывает ProximityPrompt торговца Гоши (и кнопка «Shop»), а не вход в зону\n"
    "\t\tWasOnShopPad = onShopPad\n\n",
)
p.sub(
    "\t\t\tlocal surfBright = IsNightMode and L.NightBrightness or L.DayBrightness\n"
    "\t\t\tlocal surfAmbient = IsNightMode and L.NightAmbient or L.DayAmbient\n"
    "\t\t\tlocal surfOutdoor = IsNightMode and L.NightOutdoorAmbient or L.DayOutdoorAmbient\n",
    "\t\t\t-- v52: плавный переход день/ночь — доля ночи 0..1 из Lighting.NightBlend (её ведёт NightFX)\n"
    "\t\t\tlocal blendValue = Lighting:FindFirstChild(\"NightBlend\")\n"
    "\t\t\tlocal nightBlend = (blendValue and blendValue:IsA(\"NumberValue\")) and blendValue.Value or (IsNightMode and 1 or 0)\n"
    "\t\t\tlocal PL = GameConfig.PHASE_LIGHTING\n"
    "\t\t\tlocal surfBright = L.DayBrightness + (L.NightBrightness - L.DayBrightness) * nightBlend\n"
    "\t\t\tlocal surfAmbient = L.DayAmbient:Lerp(L.NightAmbient, nightBlend)\n"
    "\t\t\tlocal surfOutdoor = L.DayOutdoorAmbient:Lerp(L.NightOutdoorAmbient, nightBlend)\n",
)
p.sub(
    "\t\t\t\tatm.Density = 0.24 + darkFactor * L.DeepAtmosphereExtraDensity\n"
    "\t\t\t\tatm.Color = Color3.fromRGB(185, 210, 240):Lerp(Color3.fromRGB(26, 28, 44), darkFactor)\n"
    "\t\t\t\tatm.Decay = Color3.fromRGB(95, 115, 145):Lerp(Color3.fromRGB(16, 18, 30), darkFactor)\n",
    "\t\t\t\tatm.Density = PL.Day.AtmosphereDensity + (PL.Night.AtmosphereDensity - PL.Day.AtmosphereDensity) * nightBlend\n"
    "\t\t\t\t\t+ darkFactor * L.DeepAtmosphereExtraDensity\n"
    "\t\t\t\tatm.Color = PL.Day.AtmosphereColor:Lerp(PL.Night.AtmosphereColor, nightBlend):Lerp(Color3.fromRGB(26, 28, 44), darkFactor)\n"
    "\t\t\t\tatm.Decay = PL.Day.AtmosphereDecay:Lerp(PL.Night.AtmosphereDecay, nightBlend):Lerp(Color3.fromRGB(16, 18, 30), darkFactor)\n",
)
p.save()
