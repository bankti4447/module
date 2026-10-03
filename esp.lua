-- NEXT HUB external ESP module
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Module = { running = false, enabled = false, itemEnabled = false, config = nil, gui = nil, entries = {}, itemEntries = {}, itemCache = {}, itemCacheAt = 0, itemConfig = false, bodyCache = {}, deathConnections = {}, worker = nil, origin = Vector2.new(0, 0), nextPlayer = 0, nextItem = 0 }
local LocalPlayer = Players.LocalPlayer

local function gamePlayerName(player, character)
	local keys = { "GameName", "CharacterName", "PlayerName", "NameTag", "Nickname", "Username" }
	local roots = { player, character }
	for _, root in ipairs(roots) do
		if root then
			for _, key in ipairs(keys) do
				local attr = root:GetAttribute(key)
				if type(attr) == "string" and attr ~= "" then return attr end
				local value = root:FindFirstChild(key, true)
				if value and value:IsA("StringValue") and value.Value ~= "" then return value.Value end
			end
		end
	end
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, item in ipairs(playerGui:GetDescendants()) do
			if item:IsA("TextLabel") or item:IsA("TextButton") then
				local lower = string.lower(item.Name)
				if (lower:find("nametag", 1, true) or lower:find("playername", 1, true) or lower == "username") and item.Text ~= "" then
					return item.Text
				end
			end
		end
	end
	return player.DisplayName or player.Name
end

local function hide(entry)
	if entry then
		entry.box.Visible = false
		entry.name.Visible = false
		entry.distance.Visible = false
		if entry.healthBack then entry.healthBack.Visible = false end
		if entry.healthFill then entry.healthFill.Visible = false end
	end
end

local function destroyEntry(entry)
	if not entry then return end
	if entry.box then entry.box:Destroy() end
	if entry.name then entry.name:Destroy() end
	if entry.distance then entry.distance:Destroy() end
	if entry.healthBack then entry.healthBack:Destroy() end
	if entry.healthFill then entry.healthFill:Destroy() end
end

local newEntry

local function itemCategory(name)
	local lower = string.lower(tostring(name or ""))
	if lower:find("armor", 1, true) or lower:find("helmet", 1, true) or lower:find("vest", 1, true) or lower:find("helmet", 1, true) then
		return "Armor"
	end
	if lower:find("weapon", 1, true) or lower:find("gun", 1, true) or lower:find("rifle", 1, true) or lower:find("pistol", 1, true) or lower:find("shotgun", 1, true) or lower:find("smg", 1, true) then
		return "Weapons"
	end
	return nil
end

local function configItemInfo(itemId)
	if Module.itemConfig == false then
		Module.itemConfig = nil
		pcall(function()
			local shared = ReplicatedStorage:FindFirstChild("Shared")
			local module = shared and shared:FindFirstChild("Config")
			if module and module:IsA("ModuleScript") then Module.itemConfig = require(module) end
		end)
	end
	local config = Module.itemConfig
	if type(config) ~= "table" then return nil end
	local info
	pcall(function()
		if type(config.ShopItem) == "function" then info = config.ShopItem(itemId) end
		info = info or (type(config.Shop) == "table" and config.Shop[itemId])
	end)
	if type(info) ~= "table" then return nil end
	return info
end

local function configItemCategory(itemId)
	local info = configItemInfo(itemId)
	if type(info) ~= "table" then return nil end
	local kind = string.lower(tostring(info.Kind or info.StoreCat or info.Category or ""))
	if kind == "armor" or kind == "shield" or kind == "helmet" or kind == "headgear" or kind == "vest" then return "Armor" end
	if kind == "asr" or kind == "melee" or kind == "knife" or kind == "gun" or kind == "rifle" or kind == "pistol" or kind == "smg" or kind == "shotgun" then return "Weapons" end
	return nil
end

local function configItemLabel(itemId)
	local info = configItemInfo(itemId)
	if type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then return info.Name end
	local config = Module.itemConfig
	if type(config) == "table" and type(config.WeaponLabel) == "function" then
		local label
		pcall(function() label = config.WeaponLabel(itemId) end)
		if type(label) == "string" and label ~= "" then return label end
	end
	return nil
end

local function refreshItems()
	local now = os.clock()
	if now - Module.itemCacheAt < 0.75 then return end
	Module.itemCacheAt = now
	local list = {}
	local loot = Workspace:FindFirstChild("WarzLoot")
	if not loot then Module.itemCacheList = list; return end
	for _, object in ipairs(loot:GetChildren()) do
		local isModel = object:IsA("Model")
		local isPart = object:IsA("BasePart")
		if isModel or isPart then
			local rawName = object:GetAttribute("LootName")
			local rawId = object:GetAttribute("LootItemId") or object:GetAttribute("ItemId")
			local lootName = type(rawName) == "string" and rawName or ""
			local lootId = rawId ~= nil and tostring(rawId) or ""
			local displayName = lootName ~= "" and lootName or configItemLabel(lootId) or lootId
			local category = configItemCategory(lootId) or itemCategory(displayName)
			local lower = string.lower(displayName)
			local excluded = lower:find("ammo", 1, true) or lower:find("medical", 1, true) or lower:find("medkit", 1, true) or lower:find("food", 1, true)
			if not excluded and lootId ~= "" and category then
				Module.itemCache[object] = displayName ~= "" and displayName or lootId
				table.insert(list, object)
			end
		end
	end
	Module.itemCacheList = list
end

local function updateItems(camera, config)
	if Module.itemEnabled ~= true then
		for _, entry in pairs(Module.itemEntries) do hide(entry) end
		return
	end
	refreshItems()
	local seen = {}
	for _, object in ipairs(Module.itemCacheList or {}) do
		if object.Parent then
			local part = object:IsA("BasePart") and object or object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
			if part then
				local point = camera:WorldToScreenPoint(part.Position)
				local distance = (camera.CFrame.Position - part.Position).Magnitude
				local entry = Module.itemEntries[object]
				if not entry then entry = newEntry(); Module.itemEntries[object] = entry end
				seen[object] = true
				if point.Z > 0 and distance <= (tonumber(config.ESPMaxDistance) or 900) then
					entry.box.Visible = false
					entry.name.Position = UDim2.fromOffset(point.X - Module.origin.X, point.Y - 10 - Module.origin.Y)
					entry.name.Text = tostring(Module.itemCache[object] or object.Name)
					entry.name.TextColor3 = Color3.fromRGB(255, 220, 120)
					entry.name.Visible = true
					entry.distance.Visible = false
					entry.healthBack.Visible = false
					entry.healthFill.Visible = false
				else
					hide(entry)
				end
			end
		end
	end
	for object, entry in pairs(Module.itemEntries) do
		if not seen[object] or not object.Parent then destroyEntry(entry); Module.itemEntries[object] = nil; Module.itemCache[object] = nil end
	end
end

newEntry = function()
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ZIndex = 20
	box.Visible = false
	box.Parent = Module.gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(110, 180, 255)
	stroke.Transparency = 0
	stroke.Parent = box
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromOffset(240, 16)
	name.AnchorPoint = Vector2.new(0.5, 1)
	name.Font = Enum.Font.SourceSans
	name.TextSize = 13
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0
	name.ZIndex = 22
	name.Visible = false
	name.Parent = Module.gui
	local distance = name:Clone()
	distance.TextSize = 12
	distance.TextColor3 = Color3.fromRGB(190, 190, 200)
	distance.AnchorPoint = Vector2.new(0.5, 0)
	distance.ZIndex = 22
	distance.Parent = Module.gui
	local healthBack = Instance.new("Frame")
	healthBack.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	healthBack.BorderSizePixel = 0
	healthBack.ZIndex = 21
	healthBack.Visible = false
	healthBack.Parent = Module.gui
	local healthFill = Instance.new("Frame")
	healthFill.BackgroundColor3 = Color3.fromRGB(80, 220, 110)
	healthFill.BorderSizePixel = 0
	healthFill.ZIndex = 22
	healthFill.Visible = false
	healthFill.Parent = Module.gui
	return { box = box, stroke = stroke, name = name, distance = distance, healthBack = healthBack, healthFill = healthFill }
end

local function updateOrigin()
	if not Module.gui then return end
	local probe = Module.gui:FindFirstChild("OriginProbe")
	if not probe then
		probe = Instance.new("Frame")
		probe.Name = "OriginProbe"
		probe.Size = UDim2.fromOffset(1, 1)
		probe.BackgroundTransparency = 1
		probe.BorderSizePixel = 0
		probe.Position = UDim2.fromOffset(0, 0)
		probe.Parent = Module.gui
	end
	local ok, position = pcall(function() return probe.AbsolutePosition end)
	if ok and typeof(position) == "Vector2" then Module.origin = position end
end

local function alive(character, player)
	if not character or not character.Parent then return false end
	if character:GetAttribute("WarzDead") == true or character:GetAttribute("WarzHidden") == true then return false end
	if player and player:GetAttribute("CSGO_Dead") == true then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return not humanoid or humanoid.Health > 0
end

local function bindDeathSignals(player, character, entry)
	local old = Module.deathConnections[player]
	if old and old.character == character then return end
	if old then
		for _, connection in ipairs(old.connections) do pcall(function() connection:Disconnect() end) end
	end
	local state = { character = character, connections = {} }
	Module.deathConnections[player] = state
	local function hideNow()
		if Module.deathConnections[player] == state then hide(entry) end
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then table.insert(state.connections, humanoid.Died:Connect(hideNow)) end
	if character then table.insert(state.connections, character:GetAttributeChangedSignal("WarzDead"):Connect(function()
		if character:GetAttribute("WarzDead") == true then hideNow() end
	end)) end
end

local bodyNames = {
	Head = true, Body = true, Arms = true, Legs = true, Torso = true,
	UpperTorso = true, LowerTorso = true, LeftArm = true, RightArm = true,
	LeftLeg = true, RightLeg = true, ["Left Arm"] = true, ["Right Arm"] = true,
	["Left Leg"] = true, ["Right Leg"] = true, LeftUpperArm = true,
	LeftLowerArm = true, LeftHand = true, RightUpperArm = true,
	RightLowerArm = true, RightHand = true, LeftUpperLeg = true,
	LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true,
	RightLowerLeg = true, RightFoot = true,
}

local function projectBounds(character, camera)
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local count = 0
	local cached = Module.bodyCache[character]
	local now = os.clock()
	if not cached or now - cached.at > 0.75 then
		local parts = {}
		for _, item in ipairs(character:GetDescendants()) do
			if item:IsA("BasePart") and bodyNames[item.Name] then table.insert(parts, item) end
		end
		cached = { at = now, parts = parts }
		Module.bodyCache[character] = cached
	end
	for _, item in ipairs(cached.parts) do
		if item:IsA("BasePart") and bodyNames[item.Name] then
			local half = item.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local point = camera:WorldToScreenPoint(item.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)))
						if point.Z > 0.05 then
							count = count + 1
							minX = math.min(minX, point.X); minY = math.min(minY, point.Y)
							maxX = math.max(maxX, point.X); maxY = math.max(maxY, point.Y)
						end
					end
				end
			end
		end
	end
	if count == 0 then return nil end
	return minX, minY, maxX, maxY
end

local function updatePlayer(player, camera, config)
	local entry = Module.entries[player]
	if not entry then entry = newEntry(); Module.entries[player] = entry end
	local character = player.Character
	bindDeathSignals(player, character, entry)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if not alive(character, player) or not root or not head then hide(entry); return end
	local distance = (camera.CFrame.Position - root.Position).Magnitude
	if distance > (tonumber(config.ESPMaxDistance) or 900) then hide(entry); return end
	local top = camera:WorldToScreenPoint(head.Position + Vector3.new(0, 0.35, 0))
	local bottom = camera:WorldToScreenPoint(root.Position - Vector3.new(0, 3.0, 0))
	if top.Z <= 0.05 or bottom.Z <= 0.05 then hide(entry); return end
	local height = math.max(bottom.Y - top.Y + 8, 8)
	local width = math.max(height * 0.50, 4)
	local x = ((top.X + bottom.X) * 0.5) - width * 0.5 - Module.origin.X
	local y = top.Y - 4 - Module.origin.Y
	entry.box.Position = UDim2.fromOffset(x, y)
	entry.box.Size = UDim2.fromOffset(width, height)
	entry.stroke.Color = config.TeamColors and Color3.fromRGB(110, 180, 255) or Color3.fromRGB(110, 180, 255)
	entry.box.Visible = config.Box ~= false
	entry.name.Position = UDim2.fromOffset(x + width * 0.5, y - 2)
	entry.name.Text = tostring(gamePlayerName(player, character))
	entry.name.Visible = config.Name ~= false
	entry.distance.Position = UDim2.fromOffset(x + width * 0.5, y + height + 2)
	entry.distance.Text = string.format("%d m", math.floor(distance + 0.5))
	entry.distance.Visible = config.Distance ~= false
	if config.Health ~= false then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local fraction = 1
		if humanoid and humanoid.MaxHealth > 0 then
			fraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		end
		local barX = x - 6
		entry.healthBack.Position = UDim2.fromOffset(barX, y)
		entry.healthBack.Size = UDim2.fromOffset(3, height)
		entry.healthBack.Visible = true
		local fillHeight = math.max(1, math.floor(height * fraction))
		entry.healthFill.Position = UDim2.fromOffset(barX, y + height - fillHeight)
		entry.healthFill.Size = UDim2.fromOffset(3, fillHeight)
		entry.healthFill.BackgroundColor3 = Color3.fromRGB(math.floor(255 - 175 * fraction), math.floor(75 + 145 * fraction), 80)
		entry.healthFill.Visible = true
	else
		entry.healthBack.Visible = false
		entry.healthFill.Visible = false
	end
end

local function update()
	if Module.config then
		Module.enabled = Module.config.ESP == true
	end
	if not Module.running then return end
	local camera = Workspace.CurrentCamera
	local config = Module.config or {}
	if not camera then return end
	updateOrigin()
	local now = os.clock()
	if now >= Module.nextItem then
		Module.nextItem = now + (1 / 30)
		pcall(updateItems, camera, config)
	end
	if not Module.enabled then
		for _, entry in pairs(Module.entries) do hide(entry) end
		return
	end
	if now < Module.nextPlayer then return end
	Module.nextPlayer = now + (1 / 60)
	local seen = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			seen[player] = true
			updatePlayer(player, camera, config)
		end
	end
	for player, entry in pairs(Module.entries) do
		if not seen[player] then
			local state = Module.deathConnections[player]
			if state then for _, connection in ipairs(state.connections) do pcall(function() connection:Disconnect() end) end end
			Module.deathConnections[player] = nil
			destroyEntry(entry); Module.entries[player] = nil
		end
	end
end

function Module.Start(config, parent)
	if Module.running then return Module end
	Module.config = config or {}
	Module.gui = Instance.new("ScreenGui")
	Module.gui.Name = "NextHubExternalESP"
	Module.gui.IgnoreGuiInset = true
	Module.gui.ResetOnSpawn = false
	Module.gui.DisplayOrder = 20
	Module.gui.Parent = parent or (LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui"))
	Module.running = true
	Module.enabled = Module.config.ESP == true
	Module.itemEnabled = Module.config.ItemESP == true
	Module.worker = task.spawn(function()
		while Module.running do
			pcall(update)
			task.wait(1 / 60)
		end
	end)
	return Module
end

function Module.SetItemEnabled(state)
	Module.itemEnabled = state == true
	if not Module.itemEnabled then
		for _, entry in pairs(Module.itemEntries) do hide(entry) end
	end
end

function Module.SetEnabled(state)
	Module.enabled = state == true
	end

function Module.Stop()
	Module.running = false
	Module.worker = nil
	for player, state in pairs(Module.deathConnections) do
		for _, connection in ipairs(state.connections) do pcall(function() connection:Disconnect() end) end
		Module.deathConnections[player] = nil
	end
	for player, entry in pairs(Module.entries) do destroyEntry(entry); Module.entries[player] = nil end
	for object, entry in pairs(Module.itemEntries) do destroyEntry(entry); Module.itemEntries[object] = nil end
	if Module.gui then Module.gui:Destroy(); Module.gui = nil end
end

return Module
