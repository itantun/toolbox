#!/usr/bin/env python3
"""v52: доводка ShopUI и DataManager (списки купленных уровней для клиента)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patcher  # noqa: E402

p = Patcher("src/StarterPlayer/StarterPlayerScripts/ShopUI.client.lua")
# Слой эффектов — в отдельном всегда включённом ScreenGui: тосты видны и при закрытом окне
p.sub(
    '-- Слой эффектов (тосты и конфетти) поверх окна\n'
    'local fxLayer = UIKit.Frame(gui, "FxLayer", UDim2.fromScale(1, 1), UDim2.new(), nil, 1)\n'
    'fxLayer.Active = false\n'
    'fxLayer.ZIndex = 50\n',
    '-- Слой эффектов (тосты и конфетти) — отдельный всегда включённый ScreenGui поверх окна\n'
    'local fxGui = Instance.new("ScreenGui")\n'
    'fxGui.Name = "ShopV52Fx"\n'
    'fxGui.ResetOnSpawn = false\n'
    'fxGui.IgnoreGuiInset = true\n'
    'fxGui.DisplayOrder = 40\n'
    'fxGui.Parent = playerGui\n'
    'local fxLayer = UIKit.Frame(fxGui, "FxLayer", UDim2.fromScale(1, 1), UDim2.new(), nil, 1)\n'
    'fxLayer.Active = false\n',
)
p.sub(
    '\t\tUIKit.Toast(playerGui:FindFirstChild("ShopV52Toasts") or gui, "Подойди к торговцу Гоше на рынке!", UI.Red)\n',
    '\t\tUIKit.Toast(fxLayer, "Подойди к торговцу Гоше на рынке!", UI.Red)\n',
)
# В прокрутке лежит только активная вкладка — высота холста считается по ней одной
p.sub(
    "\tfor id, frame in pairs(TabFrames) do\n"
    "\t\tframe.Visible = id == tabId\n"
    "\tend\n",
    "\tfor id, frame in pairs(TabFrames) do\n"
    "\t\tframe.Parent = if id == tabId then scroll else nil\n"
    "\tend\n",
)
p.sub(
    '\tlocal frame = UIKit.Frame(scroll, "Tab_" .. tab.Id, UDim2.new(1, -10, 0, 0), UDim2.new(), nil, 1)\n'
    "\tframe.AutomaticSize = Enum.AutomaticSize.Y\n"
    "\tframe.Visible = false\n",
    '\tlocal frame = UIKit.Frame(scroll, "Tab_" .. tab.Id, UDim2.new(1, -10, 0, 0), UDim2.new(), nil, 1)\n'
    "\tframe.AutomaticSize = Enum.AutomaticSize.Y\n"
    "\tframe.Parent = nil\n",
)
p.save()

p = Patcher("src/ServerScriptService/Modules/DataManager.lua")
p.sub(
    "function DataManager.SyncToClient(player: Player, syncRemote: RemoteEvent?)\n",
    "-- v52: список купленных уровней массивом — разреженная таблица { [1] = true, [3] = true }\n"
    "-- при передаче через RemoteEvent обрезается на первом пропуске\n"
    "local function ownedLevels(unlocked: { [number]: boolean }, maxLevel: number): { number }\n"
    "\tlocal list: { number } = {}\n"
    "\tfor lvl = 1, maxLevel do\n"
    "\t\tif unlocked[lvl] then\n"
    "\t\t\ttable.insert(list, lvl)\n"
    "\t\tend\n"
    "\tend\n"
    "\treturn list\n"
    "end\n\n"
    "function DataManager.SyncToClient(player: Player, syncRemote: RemoteEvent?)\n",
)
p.sub(
    "\t\t\t\tUnlockedBackpacks = profile.UnlockedBackpacks,\n",
    "\t\t\t\tUnlockedBackpacks = profile.UnlockedBackpacks,\n"
    "\t\t\t\tOwnedPickaxes = ownedLevels(profile.UnlockedPickaxes, GameConfig.MAX_PICKAXE_LEVEL),\n"
    "\t\t\t\tOwnedBackpacks = ownedLevels(profile.UnlockedBackpacks, GameConfig.MAX_BACKPACK_LEVEL),\n",
)
p.save()
