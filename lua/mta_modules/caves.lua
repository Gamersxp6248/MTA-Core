if IS_MTA_GM then return end

local TAG = "mta_hives"

local HIVE = {
	Base = "base_anim",
	Type = "anim",
	PrintName = "Hive",
	Author = "Earu",
	Spawnable = false,
	AdminOnly = true,
	ms_notouch = true,
	PhysgunDisabled = true,
	dont_televate = true,
}

local function is_in_caves(ply)
	if not ply.IsInZone then return false end
	if not ply:IsInZone("cave") then return false end

	return true
end

local npc_classes = {
	npc_antlion = "antlions",
	npc_antlion_worker = "antlion_workers",
	npc_antlionguard = "antlion_guards",
}

if SERVER then
	function HIVE:Initialize()
		self:SetSolid(SOLID_VPHYSICS)
		self:SetModel("models/props_wasteland/antlionhill.mdl")
		self:SetModelScale(1 / 3)
		self:SetHealth(1000)
		self:Activate()

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			phys:EnableMotion(false)
			phys:Wake()
		end
	end

	function HIVE:OnTakeDamage(dmg_info)
		local attacker = dmg_info:GetAttacker()
		if not IsValid(attacker) then return end
		if not attacker:IsPlayer() then return end

		local cur_health = self:Health()
		local dmg = dmg_info:GetDamage()
		local new_health = cur_health - dmg
		self:SetHealth(new_health)

		if new_health <= 0 then
			local prev_pos = self:GetPos()
			MTA.IncreasePlayerFactor(dmg_info:GetAttacker(), 100)
			self:Remove()

			-- respawn after 10mins
			timer.Simple(10 * 60, function()
				local new_hive = ents.Create("mta_hive")
				new_hive:SetPos(prev_pos)
				new_hive:Spawn()
			end)
		else
			MTA.IncreasePlayerFactor(dmg_info:GetAttacker(), math.ceil(1 * (dmg / 10)))
		end
	end

	local hive_spots = {
		Vector (-78, -2591, -69),
		Vector (-1616, -2533, -100),
		Vector (1189, 1725, -217),
	}
	local function spawn_hives()
		if not landmark then return end

		local cave_center = landmark.get("land_caves")
		if not cave_center then return end

		for _, hive in pairs(ents.FindByClass("mta_hive")) do
			hive:Remove()
		end

		for _, spot in ipairs(hive_spots) do
			local pos = cave_center + spot
			local hive = ents.Create("mta_hive")
			hive:SetPos(pos)
			hive:Spawn()
		end
	end

	hook.Add("InitPostEntity", TAG, spawn_hives)
	hook.Add("PostCleanupMap", TAG, spawn_hives)
	hook.Add("MTAReset", TAG, spawn_hives)
end

if CLIENT then
	local GREEN_COLOR = Color(0, 255, 0)
	local MAT = Material("models/props_combine/portalball001_sheet")
	function HIVE:Draw()
		self:DrawModel()

		render.MaterialOverride(MAT)
		render.SetColorModulation(0, 1, 0)
			self:DrawModel()
		render.SetColorModulation(1, 1, 1)
		render.MaterialOverride()

		cam.Start2D()
		MTA.ManagedHighlightEntity(self, ("HIVE: %d/1000"):format(self:Health()), GREEN_COLOR)
		cam.End2D()
	end
end

scripted_ents.Register(HIVE, "mta_hive")

hook.Add("MTAIsInValidArea", TAG, function(ply)
	if is_in_caves(ply) then return true end
end)

if SERVER then
	local function add_coefs()
		MTA.Coeficients.npc_antlion = {
			["kill_coef"] = 1.5,
			["damage_coef"] = 1,
		}

		MTA.Coeficients.npc_antlion_worker = {
			["kill_coef"] = 1.5,
			["damage_coef"] = 1,
		}

		MTA.Coeficients.npc_antlionguard = {
			["kill_coef"] = 5,
			["damage_coef"] = 1,
		}
	end

	local npcs = {}
	for npc_class, npc_key in pairs(npc_classes) do
		npcs[npc_key] = function() return ents.Create(npc_class) end
	end

	hook.Add("MTANPCSpawnProcess", TAG, function(ply, pos, wanted_lvl)
		if not is_in_caves(ply) then return end

		add_coefs()

		local spawn_function, npc_class = npcs.antlions, "npc_antlion"
		if wanted_lvl > 10 then
			if math.random(0, 100) < 25 then
				spawn_function, npc_class = npcs.antlion_workers, "npc_antlion_worker"
			end

			if wanted_lvl > 20 and math.random(0, 100) < 5 then
				spawn_function, npc_class = npcs.antlion_guards, "npc_antlionguard"
			end
		end

		return spawn_function, npc_class
	end)

	local function DENY(ply)
		if is_in_caves(ply) then return false end
	end

	hook.Add("MTAStatIncrease", TAG, DENY)
	hook.Add("MTACanBeBounty", TAG, DENY)
	hook.Add("MTACanUpdateBadge", TAG, DENY)

	-- dont respawn npcs where they shouldnt be
	hook.Add("MTADisplaceNPC", TAG, function(ply, npc_class)
		if is_in_caves(ply) and npc_classes[npc_class] then return false end
		if not is_in_caves(ply) and npc_classes[npc_class] then return false end
	end)

	hook.Add("MTAShouldConsiderEntity", TAG, function(ent, ply)
		if not is_in_caves(ply) then return end

		return npc_classes[ent:GetClass()] ~= nil
	end)
end

if CLIENT then
	local prev_color, prev_text = MTA.PrimaryColor, MTA.WantedText

	-- for reloads
	if is_in_caves(LocalPlayer()) then
		MTA.PrimaryColor = Color(0, 255, 0)
		MTA.WantedText = "HIVE"
	end

	hook.Add("PlayerEnteredZone", TAG, function(_, zone)
		if zone ~= "cave" then return end

		MTA.OnGoingEvent = "mines"

		prev_color, prev_text = MTA.PrimaryColor, MTA.WantedText
		MTA.PrimaryColor = Color(0, 255, 0)
		MTA.WantedText = "HIVE"
	end)

	hook.Add("PlayerExitedZone", TAG, function(_, zone)
		if zone ~= "cave" then return end

		MTA.OnGoingEvent = false
		MTA.PrimaryColor = prev_color
		MTA.WantedText = prev_text
	end)

	local song = "https://gitlab.com/metastruct/mta_projects/mta/-/raw/master/external/songs/caves/TRACK_1.ogg"
	hook.Add("MTAGetDefaultSong", TAG, function()
		local ply = LocalPlayer()

		if not ply.IsInZone then return end
		if not ply:IsInZone("cave") then return end

		return song, "caves.dat"
	end)

	hook.Add("MTASpawnEffect", TAG, function(pos, npc_class)
		if npc_classes[npc_class] then
			return false -- ignore for now
		end
	end)
end