getgenv().script_name = "fuku"
getgenv().script_version = "beta"

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
while player == nil do
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end

local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/zwunio/juju/main/ui.lua"))()

local menu = lib["menu"]
local flags = lib["flags"]
local create_connection = lib["create_connection"]

local function bool(flag, fallback)
	local value = flags[flag]
	if value == nil then
		return fallback
	end
	return value == true
end

local function number(flag, fallback)
	local value = tonumber(flags[flag])
	if value == nil then
		return fallback
	end
	return value
end

local function choice(flag, fallback)
	local value = flags[flag]
	if type(value) == "table" then
		value = value[1] or next(value)
	end
	if type(value) == "string" then
		return value
	end
	return fallback
end

local group = menu.create_group("stuff")
group:create_tab("combat")
group:create_tab("visuals")
group:create_tab("misc")

local ragebot = group:create_section("combat", "ragebot", 1, 0.75, 0)

ragebot:create_element({ ["name"] = "enabled" }, {
	["toggle"] = { ["flag"] = "ragebot_main", ["default"] = false },
})

ragebot:create_element({ ["name"] = "weapon" }, {
	["dropdown"] = {
		["flag"] = "rage_weapon",
		["options"] = { "primary", "secondary", "melee" },
		["default"] = { "primary" },
		["multi"] = false,
		["requires_one"] = true,
	},
})

ragebot:create_element({ ["name"] = "method" }, {
	["dropdown"] = {
		["flag"] = "rage_method",
		["options"] = { "none", "prediction", "glue" },
		["default"] = { "glue" },
		["multi"] = false,
		["requires_one"] = true,
	},
})

ragebot:create_element({ ["name"] = "void spam" }, {
	["toggle"] = { ["flag"] = "rage_voidspam", ["default"] = true },
})

pcall(function()
	ragebot:create_element({ ["name"] = "attack time" }, {
		["slider"] = {
			["flag"] = "rage_attack_ms",
			["default"] = 100,
			["min"] = 10,
			["max"] = 500,
			["step"] = 1,
			["increment"] = 1,
			["rounding"] = 0,
			["decimals"] = 0,
			["suffix"] = "ms",
		},
	})
end)

pcall(function()
	ragebot:create_element({ ["name"] = "hide time" }, {
		["slider"] = {
			["flag"] = "rage_hide_ms",
			["default"] = 250,
			["min"] = 10,
			["max"] = 1000,
			["step"] = 1,
			["increment"] = 1,
			["rounding"] = 0,
			["decimals"] = 0,
			["suffix"] = "ms",
		},
	})
end)

local right = group:create_section("combat", "mods", 2, 0.25, 0)

right:create_element({ ["name"] = "fast melee" }, {
	["toggle"] = { ["flag"] = "fast_melee", ["default"] = false },
})

local rapid_fire_toggle = right:create_element({ ["name"] = "rapid fire" }, {
	["toggle"] = { ["flag"] = "rapid_fire", ["default"] = false },
})

right:create_element({ ["name"] = "no spread" }, {
	["toggle"] = { ["flag"] = "no_spread", ["default"] = false },
})

local function load_module(parent, name)
	if not parent then
		return nil
	end
	local child = parent:FindFirstChild(name) or parent:WaitForChild(name, 10)
	if not child then
		return nil
	end
	local ok, result = pcall(require, child)
	if ok then
		return result
	end
	return nil
end

local playerScripts = player:WaitForChild("PlayerScripts", 20)
local controllers = playerScripts and playerScripts:WaitForChild("Controllers", 20)
local clientModules = playerScripts and playerScripts:WaitForChild("Modules", 20)
local itemTypes = clientModules and clientModules:WaitForChild("ItemTypes", 20)
local sharedModules = ReplicatedStorage:WaitForChild("Modules", 20)

if not (controllers and itemTypes and sharedModules) then
	menu["new_notification"]("fuku: game modules unavailable", 6)
	return
end

local FighterController = load_module(controllers, "FighterController")
local CameraController = load_module(controllers, "CameraController")
local Melee = load_module(itemTypes, "Melee")
local Gun = load_module(itemTypes, "Gun")
local Utility = load_module(sharedModules, "Utility")
local EnumLibrary = load_module(sharedModules, "EnumLibrary")
local ItemLibrary = load_module(sharedModules, "ItemLibrary")
local SpectateController = load_module(controllers, "SpectateController")

if not (FighterController and CameraController and Melee and Gun and Utility and EnumLibrary and ItemLibrary) then
	menu["new_notification"]("fuku: failed to require modules", 6)
	return
end

pcall(function()
	if type(EnumLibrary.WaitForEnumBuilder) == "function" then
		EnumLibrary:WaitForEnumBuilder()
	end
end)

local items = ItemLibrary.Items
if type(items) ~= "table" then
	menu["new_notification"]("fuku: item library unavailable", 6)
	return
end

local UseItem = ReplicatedStorage:FindFirstChild("UseItem", true)
local tries = 0
while UseItem == nil and tries < 50 do
	tries += 1
	task.wait(0.1)
	UseItem = ReplicatedStorage:FindFirstChild("UseItem", true)
end

local UpdateCameraRotation = ReplicatedStorage:FindFirstChild("UpdateCameraRotation", true)

local rawindex = getrawmetatable(game).__index
local fallenHeight = Workspace.FallenPartsDestroyHeight

local rapid_fire_ignored = {
	["Sniper"] = true,
	["Crossbow"] = true,
	["Bow"] = true,
	["Daggers"] = true,
	["RPG"] = true,
}

local original_melee
original_melee = hookfunction(Melee.StartShooting, function(self, ...)
	local results = table.pack(original_melee(self, ...))
	if results[1] == true and flags.fast_melee and self.ClientFighter.IsLocalPlayer then
		self._attack_cooldown = self._last_attack
	end
	return table.unpack(results, 1, results.n)
end)

local original_gun
original_gun = hookfunction(Gun.StartShooting, function(self, ...)
	local results = table.pack(original_gun(self, ...))
	if results[1] and results[2] == "StartShooting" and self.ClientFighter.IsLocalPlayer then
		if flags.no_spread then
			results[4] = true
			if self.Name == "Revolver" then
				results[5] = true
			end
		end
		if flags.rapid_fire and not rapid_fire_ignored[self.Name] then
			self._shoot_cooldown = tick()
		end
	end
	return table.unpack(results, 1, results.n)
end)

local saved = {}

local function apply_rapid_fire(on)
	for name, data in pairs(items) do
		if type(data) == "table" and data.ShootCooldown and not rapid_fire_ignored[name] then
			local keep = saved[data]
			if not keep then
				keep = {
					ShootCooldown = data.ShootCooldown,
					ShootBurstCooldown = data.ShootBurstCooldown,
				}
				saved[data] = keep
			end
			if on then
				data.ShootCooldown = 0.001
				if keep.ShootBurstCooldown then
					data.ShootBurstCooldown = 0.001
				end
			else
				data.ShootCooldown = keep.ShootCooldown
				data.ShootBurstCooldown = keep.ShootBurstCooldown
			end
		end
	end
end

create_connection(rapid_fire_toggle["on_toggle_change"], apply_rapid_fire)

if flags.rapid_fire then
	apply_rapid_fire(true)
end

pcall(function()
	for index, value in pairs(debug.getupvalues(Gun._LocalTracers)) do
		if type(value) == "table" and rawget(value, "OOB_DEFAULT_WARN_DELAY") ~= nil then
			local getSpread = value.GetSpread
			local proxy = setmetatable({
				GetSpread = function(a, b, c, noSpread, ...)
					return getSpread(a, b, c, flags.no_spread or noSpread, ...)
				end,
			}, { __index = value })
			debug.setupvalue(Gun._LocalTracers, index, proxy)
			break
		end
	end
end)

local EYE = 1.75
local CROUCHED_EYE = 0.25
local GUN_HEIGHT = 4
local LEAD_CAP = 10
local SAMPLE_WINDOW = 0.15
local MAX_RANGE = 100
local MELEE_RANGE = 30
local VOID_JITTER = 60
local VOID_REFRESH = 0.03
local POSE_RESET = 12
local MAX_SHOTS = 10
local VOID = 1000000
local SLOT = { primary = 1, secondary = 2, melee = 3 }
local K0, K1, K2, K3, K4 = utf8.char(0), utf8.char(1), utf8.char(2), utf8.char(3), utf8.char(4)
local RELOAD_ANIMS = { "EmptyReload", "EmptyReloadStart", "EmptyReloadSegment", "EmptyReloadFinish", "Reload" }

local OFFSETS = {
	Vector3.new(0, 4, 0),
	Vector3.new(2, 4, 0),
	Vector3.new(-2, 4, 0),
	Vector3.new(0, 4, 2),
	Vector3.new(0, 4, -2),
	Vector3.new(3, 5, 3),
	Vector3.new(-3, 5, -3),
	Vector3.new(0, 7, 0),
}

local GLUE_OFFSETS = {
	Vector3.zero,
	Vector3.new(2, 0, 0),
	Vector3.new(-2, 0, 0),
	Vector3.new(0, 0, 2),
	Vector3.new(0, 0, -2),
	Vector3.new(0, 2, 0),
}

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.IgnoreWater = true

local desync = { real = nil, server = nil, lastPose = nil, frozen = false }
local trackPose, trackFighter = nil, nil
local voidPose, voidAt = nil, 0
local fallenSet, fflagsSet = false, false
local spam = { phase = nil, endsAt = 0, shots = 0 }
local settleAt, equipAt, fireAt, rotationAt = 0, 0, 0, 0
local ping, pingAt = 0.08, 0
local reloadLatch = nil
local reloadRequestAt = 0
local trackers = setmetatable({}, { __mode = "k" })
local motion = setmetatable({}, { __mode = "k" })

local function settle_time()
	return math.clamp(ping + 0.02, 0.03, 0.12)
end

local function local_root()
	local fighter = FighterController.LocalFighter
	local entity = type(fighter) == "table" and fighter.Entity or nil
	local root = type(entity) == "table" and entity.RootPart or nil
	if root and root.Parent then
		return root
	end
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function identity(level)
	if type(setthreadidentity) ~= "function" then
		return nil
	end
	local old = type(getthreadidentity) == "function" and getthreadidentity() or nil
	setthreadidentity(level)
	return old
end

local function apply_fflags()
	if fflagsSet or type(setfflag) ~= "function" then
		return
	end
	fflagsSet = true
	pcall(setfflag, "DFIntS2PhysicsSenderRate", "120")
	pcall(setfflag, "DFIntAssemblyHistoryBufferSize", "2147483648")
end

local function restore_fflags()
	if not fflagsSet or type(setfflag) ~= "function" then
		return
	end
	fflagsSet = false
	pcall(setfflag, "DFIntS2PhysicsSenderRate", "15")
	pcall(setfflag, "DFIntAssemblyHistoryBufferSize", "15")
end

local function freeze(root)
	if desync.frozen or type(sethiddenproperty) ~= "function" then
		return
	end
	local old = identity(8)
	pcall(sethiddenproperty, root, "PhysicsRepRootPart", Workspace.Terrain)
	if old then
		identity(old)
	end
	desync.frozen = true
end

local function unfreeze(root)
	if not desync.frozen then
		return
	end
	desync.frozen = false
	if type(sethiddenproperty) ~= "function" then
		return
	end
	local old = identity(8)
	pcall(sethiddenproperty, root, "PhysicsRepRootPart", nil)
	if old then
		identity(old)
	end
end

local function protect_fallen()
	if fallenSet or type(sethiddenproperty) ~= "function" then
		return
	end
	local old = identity(8)
	pcall(sethiddenproperty, Workspace, "FallenPartsDestroyHeight", 0 / 0)
	if old then
		identity(old)
	end
	fallenSet = true
end

local function restore_fallen()
	if not fallenSet then
		return
	end
	fallenSet = false
	if type(sethiddenproperty) ~= "function" then
		return
	end
	local old = identity(8)
	pcall(sethiddenproperty, Workspace, "FallenPartsDestroyHeight", fallenHeight)
	if old then
		identity(old)
	end
end

local function update_ping()
	local now = tick()
	if now < pingAt then
		return
	end
	pingAt = now + 0.25
	local ok, value = pcall(player.GetNetworkPing, player)
	if ok and type(value) == "number" and value == value and value > 0 then
		ping = ping * 0.7 + math.clamp(value, 0, 0.5) * 0.3
	end
end

local function item_index(item)
	if type(item) ~= "table" then
		return nil
	end
	local ok, value = pcall(item.Get, item, "ItemIndex")
	if ok and type(value) == "number" then
		return value
	end
	local data = item.Data
	return type(data) == "table" and data.ItemIndex or nil
end

local function object_id(item)
	local ok, value = pcall(item.Get, item, "ObjectID")
	if ok and value ~= nil then
		return value
	end
	return item.ObjectId
end

local function item_by_slot(fighter, slot)
	if type(fighter) ~= "table" or type(fighter.Items) ~= "table" then
		return nil
	end
	for _, item in fighter.Items do
		if item_index(item) == slot then
			return item
		end
	end
	return nil
end

local function stat(item, key)
	if type(item) ~= "table" then
		return 0
	end
	local ok, value = pcall(item.Get, item, key)
	if ok and type(value) == "number" then
		return value
	end
	local data = item.Data
	if type(data) == "table" and type(data[key]) == "number" then
		return data[key]
	end
	return 0
end

local function shot_cooldown(item)
	local live = items[item.Name]
	local info = item.Info

	local function pick(key)
		if type(live) == "table" then
			local value = tonumber(live[key])
			if value then
				return value
			end
		end
		if type(info) == "table" then
			local value = tonumber(info[key])
			if value then
				return value
			end
		end
		return tonumber(item[key])
	end

	local burst = math.max(pick("ShootBurst") or 1, 1)
	local burstCooldown = pick("ShootBurstCooldown") or 0
	local cooldown = pick("ShootCooldown") or 0

	if item.Name == "Revolver" then
		cooldown = pick("QuickShotCooldown") or cooldown
	end

	if flags.rapid_fire and not rapid_fire_ignored[item.Name] then
		cooldown = math.min(cooldown, 0.001)
		burstCooldown = math.min(burstCooldown, 0.001)
	end

	return cooldown, burst, burstCooldown
end

local function reconcile(item, now)
	local entry = trackers[item]
	if not entry then
		entry = { raw = stat(item, "Ammo"), spend = 0, deadline = nil, nextAt = 0 }
		trackers[item] = entry
	end

	local ammo = stat(item, "Ammo")

	if ammo > entry.raw then
		entry.raw, entry.spend, entry.deadline, entry.nextAt = ammo, 0, nil, 0
		return entry
	end

	if ammo < entry.raw then
		entry.spend = math.max(entry.spend - (entry.raw - ammo), 0)
		entry.raw = ammo
	end

	if entry.spend <= 0 then
		entry.deadline = nil
	end

	if entry.deadline and now >= entry.deadline then
		entry.spend, entry.nextAt, entry.deadline = 0, 0, nil
	end

	return entry
end

local function expected_ammo(item, now)
	local entry = reconcile(item, now)
	return math.max(entry.raw - entry.spend, 0)
end

local function record_shot(item, now)
	local entry = reconcile(item, now)
	if now < entry.nextAt then
		return
	end

	local available = math.max(entry.raw - entry.spend, 0)
	if available <= 0 then
		return
	end

	local cooldown, burst, burstCooldown = shot_cooldown(item)
	entry.spend += math.min(burst, available)
	entry.deadline = now + ping + 0.06
	entry.nextAt = now + (burst - 1) * burstCooldown + math.max(cooldown, burstCooldown)
end

local function can_shoot(item, now)
	local entry = reconcile(item, now)
	if now < entry.nextAt then
		return false
	end
	local empty = item._shoot_cooldown_no_ammo
	if type(empty) == "number" and now < empty then
		return false
	end
	local equip = item._equip_cooldown
	if type(equip) == "number" and now < equip then
		return false
	end
	if not (flags.rapid_fire and not rapid_fire_ignored[item.Name]) then
		local cooldown = item._shoot_cooldown
		if type(cooldown) == "number" and now < cooldown then
			return false
		end
	end
	return true
end

local function is_reloading(item)
	local cooldown = item._reload_cooldown
	if type(cooldown) == "number" and tick() < cooldown then
		return true
	end
	local threads = item._reload_threads
	if type(threads) == "table" then
		local active = threads[#threads]
		if active ~= nil and coroutine.status(active) ~= "dead" then
			return true
		end
	end
	local viewModel = item.ViewModel
	if type(viewModel) == "table" then
		for _, name in RELOAD_ANIMS do
			local ok, playing = pcall(viewModel.IsAnimationPlaying, viewModel, name)
			if ok and playing == true then
				return true
			end
		end
	end
	return false
end

local function start_reload(item)
	local now = tick()
	if now < reloadRequestAt or is_reloading(item) or stat(item, "AmmoReserve") <= 0 then
		return
	end
	reloadRequestAt = now + 0.25
	local old = identity(2)
	local ok, started = pcall(item.StartReloading, item)
	if not ok or started ~= true then
		pcall(item.Input, item, "StartReloading")
	end
	if old then
		identity(old)
	end
end

local function alive(fighter)
	if type(fighter) ~= "table" or type(fighter.Items) ~= "table" or next(fighter.Items) == nil then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function match_active()
	if not SpectateController then
		return true
	end
	local subject = SpectateController.CurrentDuelSubject
	if type(subject) ~= "table" then
		return true
	end
	local data = subject.Data
	if type(data) == "table" and data.Status ~= nil then
		return data.Status == "RoundStarted"
	end
	return true
end

local function invincible(fighter)
	local entity = fighter.Entity
	if type(entity) ~= "table" then
		return true
	end
	if entity._invincibility_visual then
		return true
	end
	if entity.IsInvincible == true then
		return true
	end
	if type(fighter.IsInvincible) == "function" then
		local ok, value = pcall(fighter.IsInvincible, fighter)
		if ok and value == true then
			return true
		end
	end
	return false
end

local function deflecting(fighter)
	local item = fighter.EquippedItem
	if type(item) ~= "table" then
		return false
	end
	if type(item.IsDeflecting) == "function" then
		local ok, value = pcall(item.IsDeflecting, item)
		if ok and value == true then
			return true
		end
	end
	return item._deflect_hash ~= nil
		and type(item._attack_cooldown) == "number"
		and tick() < item._attack_cooldown
end

local function shielded(target, from)
	local fighter = target.fighter
	if type(fighter.Items) ~= "table" then
		return false
	end

	local holding, has = false, false
	for _, item in fighter.Items do
		if item.Name == "Riot Shield" then
			has = true
			if fighter.EquippedItem == item then
				holding = true
			end
		end
	end
	if not has or not holding then
		return false
	end

	local delta = from - target.root.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 2 then
		return false
	end

	local look = target.root.CFrame.LookVector
	local ok, rotation = pcall(fighter.GetRotationCFrame, fighter)
	if ok and typeof(rotation) == "CFrame" then
		look = rotation.LookVector
	end
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.001 then
		return false
	end

	return look.Unit:Dot(flat.Unit) > 0.35
end

local function environment_of(who, fighter)
	local value = who:GetAttribute("EnvironmentID")
	if value == nil and type(fighter) == "table" and type(fighter.Get) == "function" then
		local ok, result = pcall(fighter.Get, fighter, "EnvironmentID")
		if ok then
			value = result
		end
	end
	return value
end

local function pick_target(current)
	local fighter = FighterController.LocalFighter
	local root = local_root()
	if not root or type(fighter) ~= "table" then
		return nil
	end

	local myTeam = player:GetAttribute("TeamID")
	if myTeam == nil then
		return nil
	end

	local myEnvironment = environment_of(player, fighter)
	local best, bestScore = nil, math.huge

	for _, enemy in FighterController.Objects do
		local who = type(enemy) == "table" and enemy.Player or nil
		if who and who ~= player then
			local team = who:GetAttribute("TeamID")
			if team ~= nil and team ~= myTeam then
				local model = who.Character
				local humanoid = model and model:FindFirstChildOfClass("Humanoid")
				local enemyRoot = model and model:FindFirstChild("HumanoidRootPart")
				local head = model and model:FindFirstChild("HitboxHead")
				if humanoid and humanoid.Health > 0 and enemyRoot and head and head:IsA("BasePart") then
					if head.Position.Magnitude < VOID and enemyRoot.Position.Magnitude < VOID then
						local active = true
						if type(enemy.IsActive) == "function" then
							local ok, value = pcall(enemy.IsActive, enemy)
							active = ok and value == true
						end
						if active and not invincible(enemy) then
							local theirEnvironment = environment_of(who, enemy)
							if myEnvironment == nil or theirEnvironment == nil or theirEnvironment == myEnvironment then
								local score = (enemyRoot.Position - root.Position).Magnitude
								if current == enemy then
									score = score * 0.8
								end
								if score < bestScore then
									bestScore = score
									best = {
										fighter = enemy,
										character = model,
										root = enemyRoot,
										part = head,
									}
								end
							end
						end
					end
				end
			end
		end
	end

	return best
end

local function observe(target, now)
	local position = target.part.Position
	local reported = Vector3.zero

	local ok, value = pcall(function()
		return target.root.AssemblyLinearVelocity
	end)
	if ok and typeof(value) == "Vector3" and value == value then
		reported = value
	end

	local entry = motion[target.fighter]
	if not entry then
		entry = { samples = {}, velocity = Vector3.zero }
		motion[target.fighter] = entry
	end

	local samples = entry.samples
	samples[#samples + 1] = { t = now, p = position }
	while #samples > 2 and now - samples[1].t > SAMPLE_WINDOW do
		table.remove(samples, 1)
	end

	local derived = Vector3.zero
	local first = samples[1]
	local span = now - first.t
	if span > 0.03 then
		local delta = position - first.p
		derived = delta / span
		if delta.Magnitude > 60 then
			entry.velocity = Vector3.zero
			derived = Vector3.zero
		end
	end

	local instant = reported
	if derived.Magnitude > instant.Magnitude then
		instant = derived
	end
	if instant.Magnitude > 200 then
		instant = instant.Unit * 200
	end

	entry.velocity = entry.velocity * 0.65 + instant * 0.35

	local velocity = entry.velocity
	if velocity.Magnitude < 2 then
		return Vector3.zero
	end
	return velocity
end

local function lead_vector(velocity, deltaTime)
	if velocity.Magnitude < 2 then
		return Vector3.zero
	end
	local leadTime = math.clamp(ping * 2 + deltaTime, 0, 0.3)
	local lead = velocity * leadTime
	lead = Vector3.new(lead.X, lead.Y * 0.35, lead.Z)
	if lead.Magnitude > LEAD_CAP then
		lead = lead.Unit * LEAD_CAP
	end
	return lead
end

local function aim_result(origin, target)
	local ignore = { player.Character }
	local viewModels = Workspace:FindFirstChild("ViewModels")
	if viewModels then
		ignore[#ignore + 1] = viewModels
	end
	castParams.FilterDescendantsInstances = ignore

	local direction = target.part.Position - origin
	if direction.Magnitude < 0.01 then
		return true, true
	end

	local hit = Workspace:Raycast(origin, direction, castParams)
	if hit == nil then
		return true, true
	end
	if hit.Instance == target.part then
		return true, true
	end
	if hit.Instance:IsDescendantOf(target.character) then
		return true, false
	end
	return false, false
end

local function eye_offset(fighter)
	local crouched = false
	if type(fighter.IsCrouching) == "function" then
		local ok, value = pcall(fighter.IsCrouching, fighter)
		crouched = ok and value == true
	end
	return Vector3.new(0, crouched and CROUCHED_EYE or EYE, 0)
end

local function head_drop(target)
	return target.part.Position.Y - target.root.Position.Y
end

local function solve_gun(target, eye, velocity, deltaTime, method)
	local fallback = nil

	if method == "glue" then
		local head = target.part
		local _, yaw = head.CFrame:ToOrientation()
		local frame = CFrame.new(head.Position) * CFrame.Angles(0, yaw, 0)
		local base = Vector3.new(0, GUN_HEIGHT - head_drop(target), 0.05)
		local floor = target.root.Position.Y + 2

		for _, extra in GLUE_OFFSETS do
			local position = (frame * CFrame.new(base + extra)).Position
			if position.Y >= floor then
				local origin = position + eye
				local possible, isHead = aim_result(origin, target)
				if possible and not shielded(target, origin) then
					if isHead then
						return CFrame.new(position)
					end
					fallback = fallback or CFrame.new(position)
				end
			end
		end

		if fallback then
			return fallback
		end
	end

	local anchor = target.root.Position
	if method == "prediction" then
		anchor = anchor + lead_vector(velocity, deltaTime)
	end

	for _, offset in OFFSETS do
		local position = anchor + offset
		local origin = position + eye
		local possible, isHead = aim_result(origin, target)
		if possible and not shielded(target, origin) then
			if isHead then
				return CFrame.new(position)
			end
			fallback = fallback or CFrame.new(position)
		end
	end

	return fallback
end

local function solve_melee(target, velocity, deltaTime, method)
	if method == "glue" then
		return CFrame.new(target.part.Position)
	end
	local position = target.root.Position
	if method == "prediction" then
		position = position + lead_vector(velocity, deltaTime)
	end
	return CFrame.new(position)
end

local function void_pose(now)
	if not voidPose or now >= voidAt then
		voidPose = CFrame.new(math.random(-100000, 100000), math.random(90000, 110000), math.random(-100000, 100000))
		voidAt = now + VOID_REFRESH
	end
	return voidPose
end

local function send_rotation(aim)
	if not UpdateCameraRotation then
		return
	end
	local now = tick()
	if now < rotationAt then
		return
	end
	rotationAt = now + 0.1
	local pitch, yaw = aim:ToOrientation()
	pcall(function()
		UpdateCameraRotation:FireServer(Utility:EncodeCameraRotation(math.deg(pitch), math.deg(yaw)), nil)
	end)
end

local function hide_rotation()
	if not UpdateCameraRotation then
		return
	end
	local now = tick()
	if now < rotationAt then
		return
	end
	rotationAt = now + 0.1
	pcall(function()
		UpdateCameraRotation:FireServer(Utility:EncodeCameraRotation(90, math.random(0, 360)), nil)
	end)
end

local function fire_gun(item, aim, part, now)
	local inner = {
		[K0] = Utility:EncodeCFrame(aim),
		[K1] = Utility:EncodeCFrame(aim + Vector3.new(0.01, 0.01, 0.01)),
		[K2] = part,
		[K3] = Utility:EncodeCFrame(CFrame.new()),
	}
	if item.Name == "Revolver" then
		inner[K4] = true
	end
	local outer = { [K1] = inner }
	if item.IsRaycast then
		outer[K2] = true
	end
	local id = object_id(item)
	if id == nil then
		return
	end
	pcall(function()
		UseItem:FireServer(id, EnumLibrary:ToEnum("StartShooting"), outer, nil)
	end)
	record_shot(item, now)
end

local function fire_melee(item, aim, part)
	local viewModel = item.ViewModel
	if type(viewModel) ~= "table" then
		return
	end
	local ok, keys = pcall(viewModel.GetAnimationKeys, viewModel, "Attack")
	if not ok or type(keys) ~= "table" or #keys == 0 then
		return
	end
	local inner = {
		[K0] = Utility:EncodeCFrame(aim),
		[K1] = Utility:EncodeCFrame(aim + Vector3.new(0.01, 0.01, 0.01)),
		[K2] = part,
		[K3] = Utility:EncodeCFrame(CFrame.new()),
	}
	local id = object_id(item)
	if id == nil then
		return
	end
	pcall(function()
		UseItem:FireServer(id, EnumLibrary:ToEnum("StartShooting"), {
			[K1] = inner,
			[K2] = EnumLibrary:ToEnum(keys[math.random(#keys)]),
		}, nil)
	end)
end

local function resolve_slot(fighter)
	local wanted = SLOT[choice("rage_weapon", "primary")] or 1
	if wanted == 3 then
		return 3
	end

	local preferred = item_by_slot(fighter, wanted)
	if preferred and (stat(preferred, "Ammo") > 0 or stat(preferred, "AmmoReserve") > 0) then
		return wanted
	end

	local otherSlot = wanted == 1 and 2 or 1
	local alternate = item_by_slot(fighter, otherSlot)
	if alternate and (stat(alternate, "Ammo") > 0 or stat(alternate, "AmmoReserve") > 0) then
		return otherSlot
	end

	if item_by_slot(fighter, 3) then
		return 3
	end

	return wanted
end

local function restore()
	local root = local_root()
	if root and desync.real then
		root.CFrame = desync.real
	end
end

local reference_update = CameraController.Update
CameraController.Update = function(...)
	restore()
	local results = table.pack(reference_update(...))
	local root = local_root()
	if root and desync.server then
		root.CFrame = desync.server
	end
	return table.unpack(results, 1, results.n)
end

RunService.PreRender:Connect(restore)

local function drop(root)
	if root and desync.real then
		root.CFrame = desync.real
	end
	desync.server = nil
	desync.real = nil
	desync.lastPose = nil
	trackPose, trackFighter = nil, nil
	voidPose, voidAt = nil, 0
	reloadLatch = nil
	spam.phase = nil
	spam.shots = 0
	restore_fallen()
	restore_fflags()
	if root then
		unfreeze(root)
	end
end

RunService.Heartbeat:Connect(function(deltaTime)
	local root = local_root()
	if not root then
		drop(nil)
		return
	end

	local fighter = FighterController.LocalFighter

	if not bool("ragebot_main", false) or not UseItem or not alive(fighter) or not match_active() then
		drop(root)
		return
	end

	local current = rawindex(root, "CFrame")
	if desync.real == nil or desync.lastPose == nil or (current.Position - desync.lastPose.Position).Magnitude > 0.05 then
		desync.real = current
	end

	update_ping()
	protect_fallen()
	apply_fflags()

	local now = tick()
	local slot = resolve_slot(fighter)
	local equipped = fighter.EquippedItem
	local method = choice("rage_method", "glue")
	local pose, attacking, target = nil, false, nil

	if item_index(equipped) ~= slot then
		reloadLatch = nil
		spam.phase = nil
		if now >= equipAt then
			equipAt = now + 0.3
			task.spawn(fighter.EquipItem, fighter, slot)
		end
		pose = void_pose(now)
	elseif type(equipped.IsEquipping) == "function" and select(2, pcall(equipped.IsEquipping, equipped)) == true then
		spam.phase = nil
		pose = void_pose(now)
	elseif slot == 3 then
		reloadLatch = nil
		spam.phase = nil
		target = pick_target(trackFighter)
		if target then
			local velocity = observe(target, now)
			pose = solve_melee(target, velocity, deltaTime, method)
			trackPose, trackFighter = pose, target.fighter
			attacking = now >= fireAt
		else
			trackPose, trackFighter = nil, nil
			pose = void_pose(now)
		end
	elseif reloadLatch == equipped then
		spam.phase = nil
		if stat(equipped, "Ammo") <= 0 and stat(equipped, "AmmoReserve") <= 0 then
			reloadLatch = nil
			pose = void_pose(now)
		elseif stat(equipped, "Ammo") > 0 and not is_reloading(equipped) then
			reloadLatch = nil
			trackers[equipped] = nil
		else
			pose = void_pose(now)
			start_reload(equipped)
		end
	elseif stat(equipped, "Ammo") <= 0 then
		reloadLatch = equipped
		spam.phase = nil
		pose = void_pose(now)
	else
		target = pick_target(trackFighter)
		if target then
			local velocity = observe(target, now)
			local eye = eye_offset(fighter)
			local solved = solve_gun(target, eye, velocity, deltaTime, method)

			if solved then
				if trackFighter ~= target.fighter or trackPose == nil or (solved.Position - trackPose.Position).Magnitude > POSE_RESET then
					settleAt = now + settle_time()
				end
				trackPose, trackFighter = solved, target.fighter

				local exposed = true
				if bool("rage_voidspam", true) then
					local attackWindow = math.clamp(number("rage_attack_ms", 100), 10, 500) / 1000
					local hideWindow = math.clamp(number("rage_hide_ms", 250), 10, 1000) / 1000
					if spam.phase == nil then
						spam.phase = "attack"
						spam.shots = 0
						settleAt = now + settle_time()
						spam.endsAt = now + settle_time() + attackWindow
					elseif now >= spam.endsAt then
						if spam.phase == "attack" then
							spam.phase = "hide"
							spam.endsAt = now + hideWindow + math.random() * (VOID_JITTER / 1000)
						else
							spam.phase = "attack"
							spam.shots = 0
							settleAt = now + settle_time()
							spam.endsAt = now + settle_time() + attackWindow
						end
					end
					exposed = spam.phase == "attack" and spam.shots < MAX_SHOTS
				else
					spam.phase = nil
					spam.shots = 0
				end

				if exposed then
					pose = solved
					local origin = solved.Position + eye
					attacking = aim_result(origin, target)
						and now >= settleAt
						and now >= fireAt
						and expected_ammo(equipped, now) > 0
						and (target.part.Position - origin).Magnitude <= MAX_RANGE
						and not is_reloading(equipped)
						and can_shoot(equipped, now)
						and not deflecting(target.fighter)
						and not shielded(target, origin)
				else
					pose = void_pose(now)
				end
			else
				spam.phase = nil
				trackPose, trackFighter = nil, nil
				pose = void_pose(now)
			end
		else
			spam.phase = nil
			trackPose, trackFighter = nil, nil
			pose = void_pose(now)
		end
	end

	if pose == nil then
		pose = void_pose(now)
	end

	freeze(root)
	desync.server = pose
	desync.lastPose = pose
	root.CFrame = pose

	local landed = false

	if attacking and target and target.part.Parent then
		local live = target.part.Position
		local limit = slot == 3 and MELEE_RANGE or MAX_RANGE
		if live.Magnitude < VOID and (live - pose.Position).Magnitude <= limit then
			local eye = eye_offset(fighter)
			local aim = CFrame.lookAt(pose.Position + eye, live)
			send_rotation(aim)
			if slot == 3 then
				fire_melee(equipped, aim, target.part)
				fireAt = now + 1 / 120
				landed = true
			else
				fire_gun(equipped, aim, target.part, now)
				fireAt = now + 1 / 120
				spam.shots += 1
				landed = true
			end
		end
	end

	if landed then
		voidPose, voidAt = nil, 0
	else
		hide_rotation()
	end
end)

task.delay(1, function()
	menu["new_notification"]("fuku loaded", 1)
end)
