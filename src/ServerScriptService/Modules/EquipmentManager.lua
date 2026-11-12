--!strict
-- ============================================================================
-- 🛠️ МОДУЛЬ: EquipmentManager (ServerScriptService.Modules.EquipmentManager)
-- v52: серверный фасад. Раньше здесь лежала полная копия EquipmentBuilder
-- (2000+ строк, которые приходилось править дважды). Теперь единственный исходник
-- сборки кирок, рюкзаков и каски — ReplicatedStorage.Modules.EquipmentBuilder:
-- сервер и клиент (превью в магазине) строят одни и те же модели.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EquipmentBuilder"))
