--[[
	Util
	A collection of shared helper functions used by various modules.
]]
--
local Util = {}
local StudioService = game:GetService("StudioService")
local Selection = game:GetService("Selection")
function Util.getFirstSelected()
	local selected = Selection:Get()
	if #selected > 0 then
		return selected[1]
	end
	return nil
end
function Util.getActiveScript()
	return StudioService.ActiveScript
end
function Util.isDescendantOfType(instance, types)
	if type(types) == "string" then
		types = { types }
	end
	local current = instance
	while current do
		for _, typeName in ipairs(types) do
			if current:IsA(typeName) then
				return true
			end
		end
		current = current.Parent
	end
	if instance:IsDescendantOf(workspace) then
		return table.find(types, "Workspace") ~= nil
	end
	return false
end
function Util.getSibling(instance, Type)
	while instance and instance.Parent do
		local needed = instance:FindFirstChildWhichIsA(Type)
		if needed then
			return needed
		end
		instance = instance.Parent
	end
	return nil
end
function Util.isConsole(document)
	local name = document.Name and document.Name:lower() or ""
	return name:match("output") or name:match("console")
end
return Util
